Include Ensemble

/// The budget API (AD-20): the state of the daily cost cap, and the mark of a day that reached it.
///   - State reads the day's spend from the Usage rows, the cap and the gateway's spend from the three budget settings of the Decide
///     item (DailyCostCapUSD, GatewaySpendUSD and GatewaySpendDate, through OcuTalon.Bridge.Ext.Accessor.ValueFor), and the day's
///     mark. The day is the local date of the instance zone, so it ends at local midnight, through OcuTalon.Bridge.Time. Rows of the
///     owner eval, and rows of unknown cost, are never counted. A cap that is set never fails open silently (DW-76): State names each
///     fault in its output faults, and Decide's precheck logs them.
///   - MarkCapped marks a day as capped once, under a lock, and tells the host sink once (budget.capped). The callers are the paths
///     that record a daily_cap fallback (Decide.RecordFallback); the mark is a plain global of the private database,
///     ^OcuTalonBP.UsageCapped(day) = the UTC time of the mark.
/// This class names no other OcuTalon package (AD-2).
Class OcuTalon.Bridge.Budget
{

/// The SQLCODE of a statement that the process is not privileged for.
Parameter NOPRIVILEGECODE = -99;

/// The fault line of a Usage read that is refused for lack of an SQL privilege.
Parameter NOPRIVILEGE = "The Usage rows of the day cannot be read in this process, which holds no SQL privilege on them, so their spend is not counted";

/// The state of the daily spending cap: {"spent","cap","capped","resetsAt"}, where spent and cap are JSON numbers in US dollars,
/// capped is a JSON boolean and resetsAt is the end of the day as a UTC time.
///   - now is a UTC time (YYYY-MM-DDThh:mm:ssZ); empty or unreadable means the current time. The day is the instance-zone date of
///     now, from DayStartUtc (inclusive) to DayEndUtc (exclusive).
///   - spent is the sum of the CostUSD of the Usage rows recorded in the day, except rows of the owner eval and rows with no cost,
///     plus GatewaySpendUSD when GatewaySpendDate is the day.
///   - cap is DailyCostCapUSD; 0 means off. A setting that is not a number of 0 or more counts as 0, and so does a setting that
///     cannot be read (no production).
///   - capped is true when the day is marked (MarkCapped), or when cap is above 0 and spent has reached it.
///   - faults (DW-76) is a dynamic array with one plain line, passed through OcuTalon.Bridge.Redact.Text, for each way in which the
///     cap counts less than it was set to. The spend that can be read is still counted and compared with the cap. The lines, in this order:
///       - the Usage rows of the day cannot be read in this process, which holds no SQL privilege on them (the SELECT fails with the
///         SQLCODE of a missing privilege, -99), so their spend is not counted. That is the process of a web request. It is a fault
///         line and no warning, and the unpriced models are not listed then;
///       - DailyCostCapUSD cannot be read, or is not empty and not a number of 0 or more (it counts as 0, which is off);
///       - GatewaySpendUSD cannot be read, or is not empty and not a number of 0 or more (the gateway's spend is not counted);
///       - GatewaySpendDate cannot be read, or is not empty and not a date, YYYY-MM-DD (the gateway's spend is not counted);
///       - the cap is above 0, and the Usage rows of the day (owner not eval) of a model have no cost: one line for each model, naming it
///         (their spend is not counted).
ClassMethod State(now As %String = "", Output faults As %DynamicArray) As %DynamicObject
{
	Set faults = []
	If ##class(OcuTalon.Bridge.Time).LocalDate(now) = "" Set now = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set day = ##class(OcuTalon.Bridge.Time).LocalDate(now)
	Set from = ##class(OcuTalon.Bridge.Time).DayStartUtc(day)
	Set to = ##class(OcuTalon.Bridge.Time).DayEndUtc(day)
	Set spent = ..UsageSpent(from, to, .unreadable)
	If unreadable Do ..Fault(faults, ..#NOPRIVILEGE)
	Set capText = ..Setting("DailyCostCapUSD", .capStatus)
	Set cap = 0
	If $$$ISERR(capStatus) {
		Do ..Fault(faults, "The setting DailyCostCapUSD of Decide cannot be read, so the daily cost cap counts as off: "_$SYSTEM.Status.GetErrorText(capStatus))
	} ElseIf capText = "" {
		Set cap = 0
	} ElseIf '$IsValidNum(capText, "", 0) {
		Do ..Fault(faults, "The setting DailyCostCapUSD of Decide is not a number of 0 or more, so the daily cost cap counts as off")
	} Else {
		Set cap = +capText
	}
	Set gatewaySpend = ..Setting("GatewaySpendUSD", .spendStatus)
	If $$$ISERR(spendStatus) {
		Do ..Fault(faults, "The setting GatewaySpendUSD of Decide cannot be read, so the gateway's spend is not counted: "_$SYSTEM.Status.GetErrorText(spendStatus))
		Set gatewaySpend = 0
	} ElseIf (gatewaySpend '= "") && '$IsValidNum(gatewaySpend, "", 0) {
		Do ..Fault(faults, "The setting GatewaySpendUSD of Decide is not a number of 0 or more, so the gateway's spend is not counted")
		Set gatewaySpend = 0
	}
	Set gatewayDate = ..Setting("GatewaySpendDate", .dateStatus)
	If $$$ISERR(dateStatus) {
		Do ..Fault(faults, "The setting GatewaySpendDate of Decide cannot be read, so the gateway's spend is not counted: "_$SYSTEM.Status.GetErrorText(dateStatus))
		Set gatewayDate = ""
	} ElseIf (gatewayDate '= "") && '..IsDate(gatewayDate) {
		Do ..Fault(faults, "The setting GatewaySpendDate of Decide is not a date, YYYY-MM-DD, so the gateway's spend is not counted")
		Set gatewayDate = ""
	}
	If gatewayDate = day Set spent = spent + ..Amount(gatewaySpend)
	If (cap > 0) && 'unreadable {
		Set models = ..UnpricedModels(from, to)
		Set position = 0
		While $ListNext(models, position, model) {
			Do ..Fault(faults, "The Usage rows of today of the model '"_model_"' have no cost (no Price row has the model), so the daily cost cap does not count their spend")
		}
	}
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
///     only when this call set the node. The sink is sinkClass, or, when that is empty, the class that the HostSinkClass setting of
///     the Decide item names (Accessor.ValueFor; FireEvent checks it, so its warning names the class). A sink that fails is logged as
///     a warning and the mark stays.
/// A day that is not a date (the form is wrong, or the date does not exist) is refused with a warning: it returns 0, sets no mark and
/// fires no event. Returns 1 when this call set the mark, otherwise 0. It never throws. Call it outside any transaction: the host sink
/// is told after the change has committed (AD-31), and a lock taken inside a transaction is held until the transaction ends.
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
		If sinkClass = "" Set sinkClass = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("HostSinkClass")
		Do ##class(OcuTalon.Bridge.Process.Decide).FireEvent(sinkClass, "instance", day, ##class(OcuTalon.Bridge.Ext.HostSink).#BUDGETCAPPED, ##class(OcuTalon.Bridge.Ext.HostSink).BudgetCappedPayload(day))
	}
	Quit marked
}

/// The sum of the CostUSD of the Usage rows recorded from the UTC time from (inclusive) to the UTC time to (exclusive), in US
/// dollars to 6 decimals, without rows of the owner eval and rows with no cost. The table is scanned, because Usage has no index
/// on RecordedAt. A scan that fails counts as 0. It fails with the SQLCODE of a missing SQL privilege (NOPRIVILEGECODE) in a
/// process that holds none; that sets unreadable to 1 and logs nothing. Any other failure is logged as a warning.
ClassMethod UsageSpent(from As %String, to As %String, Output unreadable As %Boolean) As %Numeric [ Private ]
{
	Set spent = 0
	Set unreadable = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT CostUSD FROM OcuTalon_Bridge_Data.Usage WHERE RecordedAt >= ? AND RecordedAt < ? AND CostUSD IS NOT NULL AND (OwnerRef IS NULL OR OwnerRef <> 'eval')", from, to)
	If result.%SQLCODE < 0 {
		If result.%SQLCODE = ..#NOPRIVILEGECODE {
			Set unreadable = 1
		} Else {
			$$$LOGWARNING("The Usage rows of the day cannot be summed: "_result.%Message)
		}
		Quit 0
	}
	While result.%Next() {
		Set spent = spent + result.%GetData(1)
	}
	Quit $Number(spent, 6)
}

/// The value of a budget setting of the Decide item, or "" with the error in sc when it cannot be read.
ClassMethod Setting(name As %String, Output sc As %Status) As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor(name, , , .sc)
}

/// Adds one line to the faults, redacted.
ClassMethod Fault(faults As %DynamicArray, line As %String) [ Private ]
{
	Do faults.%Push(##class(OcuTalon.Bridge.Redact).Text($Translate(line, $Char(10, 13), "  ")))
}

/// 1 when the text is a date, YYYY-MM-DD, that exists.
ClassMethod IsDate(text As %String) As %Boolean [ Private ]
{
	Quit (text ? 4N1"-"2N1"-"2N) && (##class(OcuTalon.Bridge.Time).DayStartUtc(text) '= "")
}

/// The models, as a list, of the Usage rows recorded from the UTC time from (inclusive) to the UTC time to (exclusive) that have no
/// cost, without rows of the owner eval, each once and as it is written (a query would collate it to capitals). A row with no model counts
/// under the name (no model). A scan that fails is logged as a warning and gives an empty list.
ClassMethod UnpricedModels(from As %String, to As %String) As %List [ Private ]
{
	Set models = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT %EXACT(Model) FROM OcuTalon_Bridge_Data.Usage WHERE RecordedAt >= ? AND RecordedAt < ? AND CostUSD IS NULL AND (OwnerRef IS NULL OR OwnerRef <> 'eval')", from, to)
	If result.%SQLCODE < 0 {
		$$$LOGWARNING(##class(OcuTalon.Bridge.Redact).Text("The unpriced Usage rows of the day cannot be listed: "_result.%Message))
		Quit models
	}
	While result.%Next() {
		Set model = result.%GetData(1)
		If model = "" Set model = "(no model)"
		If '$ListFind(models, model) Set models = models _ $ListBuild(model)
	}
	Quit models
}

/// The value as an amount in US dollars: a number of 0 or more, otherwise 0.
ClassMethod Amount(value As %String) As %Numeric [ Private ]
{
	Quit $Select($IsValidNum(value, "", 0): +value, 1: 0)
}

}
