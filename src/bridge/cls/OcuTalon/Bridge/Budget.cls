Include Ensemble

/// The budget API (AD-20): the state of the daily cost cap, and the mark of a day that reached it.
///   - State reads the day's spend from the Usage rows, the cap and the gateway's spend from the three budget settings of the Decide
///     item (DailyCostCapUSD, GatewaySpendUSD and GatewaySpendDate, through OcuTalon.Bridge.Ext.Accessor.ValueFor), and the day's
///     mark. The day is the local date of the instance zone, so it ends at local midnight, through OcuTalon.Bridge.Time. Rows of the
///     owner eval, and rows of unknown cost, are never counted.
///   - MarkCapped marks a day as capped once, under a lock, and tells the host sink once (budget.capped). The callers are the paths
///     that record a daily_cap fallback (Story 1.6); the mark is a plain global of the private database,
///     ^OcuTalonBP.UsageCapped(day) = the UTC time of the mark.
/// This class names no other OcuTalon package (AD-2).
Class OcuTalon.Bridge.Budget
{

/// The state of the daily spending cap: {"spent","cap","capped","resetsAt"}, where spent and cap are JSON numbers in US dollars,
/// capped is a JSON boolean and resetsAt is the end of the day as a UTC time.
///   - now is a UTC time (YYYY-MM-DDThh:mm:ssZ); empty or unreadable means the current time. The day is the instance-zone date of
///     now, from DayStartUtc (inclusive) to DayEndUtc (exclusive).
///   - spent is the sum of the CostUSD of the Usage rows recorded in the day, except rows of the owner eval and rows with no cost,
///     plus GatewaySpendUSD when GatewaySpendDate is the day.
///   - cap is DailyCostCapUSD; 0 means off. A setting that is not a number of 0 or more counts as 0, and so does a setting that
///     cannot be read (no production).
///   - capped is true when the day is marked (MarkCapped), or when cap is above 0 and spent has reached it.
ClassMethod State(now As %String = "") As %DynamicObject
{
	If ##class(OcuTalon.Bridge.Time).LocalDate(now) = "" Set now = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set day = ##class(OcuTalon.Bridge.Time).LocalDate(now)
	Set from = ##class(OcuTalon.Bridge.Time).DayStartUtc(day)
	Set to = ##class(OcuTalon.Bridge.Time).DayEndUtc(day)
	Set spent = ..UsageSpent(from, to)
	If ..Setting("GatewaySpendDate") = day Set spent = spent + ..Amount(..Setting("GatewaySpendUSD"))
	Set cap = ..Amount(..Setting("DailyCostCapUSD"))
	Set capped = ($Data(^OcuTalonBP.UsageCapped(day)) > 0) || ((cap > 0) && (spent >= cap))
	Set state = {}
	Do state.%Set("spent", spent, "number")
	Do state.%Set("cap", cap, "number")
	Do state.%Set("capped", capped, "boolean")
	Do state.%Set("resetsAt", to)
	Quit state
}

/// Marks the day (YYYY-MM-DD in the instance zone; empty means today) as capped, once, and fires budget.capped to the host sink.
///   - Under Lock +^OcuTalonBP.UsageCapped(day):5 it sets ^OcuTalonBP.UsageCapped(day) to the current UTC time when the node is
///     absent. A lock it cannot get in 5 seconds leaves no mark and fires no event; the failure is logged as a warning.
///   - After it has released the lock, it fires budget.capped with the owner instance and the payload {"day"} through Decide.FireEvent,
///     only when this call set the node. The sink is sinkClass, or, when that is empty, the HostSinkClass of the Decide item. A sink
///     that fails is logged as a warning and the mark stays.
/// A day that is not a date (the form is wrong, or the date does not exist) is refused with a warning: it returns 0, sets no mark and
/// fires no event. Returns 1 when this call set the mark, otherwise 0. It never throws.
ClassMethod MarkCapped(day As %String = "", sinkClass As %String = "") As %Boolean
{
	If day = "" Set day = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())
	If (day '? 4N1"-"2N1"-"2N) || (##class(OcuTalon.Bridge.Time).DayStartUtc(day) = "") {
		$$$LOGWARNING("The day '"_day_"' cannot be marked as capped: it is not a date, YYYY-MM-DD")
		Quit 0
	}
	Set marked = 0
	Set locked = 0
	Try {
		Lock +^OcuTalonBP.UsageCapped(day):5
		Set locked = $Test
		If 'locked {
			$$$LOGWARNING("The day "_day_" is not marked as capped: its lock was not free within 5 seconds")
		} ElseIf '$Data(^OcuTalonBP.UsageCapped(day)) {
			Set ^OcuTalonBP.UsageCapped(day) = ##class(OcuTalon.Bridge.Time).NowUtc()
			Set marked = 1
		}
	} Catch exception {
		$$$LOGWARNING("The day "_day_" could not be marked as capped: "_exception.DisplayString())
	}
	If locked Lock -^OcuTalonBP.UsageCapped(day)
	If marked {
		If sinkClass = "" Set sinkClass = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("HostSinkClass")
		Do ##class(OcuTalon.Bridge.Process.Decide).FireEvent(sinkClass, "instance", day, ##class(OcuTalon.Bridge.Ext.HostSink).#BUDGETCAPPED, ##class(OcuTalon.Bridge.Ext.HostSink).BudgetCappedPayload(day))
	}
	Quit marked
}

/// The sum of the CostUSD of the Usage rows recorded from the UTC time from (inclusive) to the UTC time to (exclusive), in US
/// dollars to 6 decimals, without rows of the owner eval and rows with no cost. The table is scanned, because Usage has no index
/// on RecordedAt. A scan that fails is logged as a warning and counts as 0.
ClassMethod UsageSpent(from As %String, to As %String) As %Numeric [ Private ]
{
	Set spent = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT CostUSD FROM OcuTalon_Bridge_Data.Usage WHERE RecordedAt >= ? AND RecordedAt < ? AND CostUSD IS NOT NULL AND (OwnerRef IS NULL OR OwnerRef <> 'eval')", from, to)
	If result.%SQLCODE < 0 {
		$$$LOGWARNING("The Usage rows of the day cannot be summed: "_result.%Message)
		Quit 0
	}
	While result.%Next() {
		Set spent = spent + result.%GetData(1)
	}
	Quit $Number(spent, 6)
}

/// The value of a budget setting of the Decide item, or "" when it cannot be read.
ClassMethod Setting(name As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor(name)
}

/// The value as an amount in US dollars: a number of 0 or more, otherwise 0.
ClassMethod Amount(value As %String) As %Numeric [ Private ]
{
	Quit $Select($IsValidNum(value, "", 0): +value, 1: 0)
}

}
