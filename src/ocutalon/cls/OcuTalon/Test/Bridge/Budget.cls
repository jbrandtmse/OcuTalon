/// Tests of the budget (Story 1.4; AD-18, AD-19, AD-20, AD-31): State and MarkCapped, in process. THIS CLASS RUNS IN THROWAWAY STACKS
/// AND IN CI ONLY (Rule 21): it deletes and writes the System Default Settings rows of the budget settings of the active production's
/// Decide item, and TestMarkDefaultDay marks today. No production is started and nothing is sent, but the settings are read the way
/// the product reads them, from the Decide item of the active production, so the tests write System Default Settings rows for it
/// (Install.Step.Production.WriteDefault) and put back the rows that were there. The Usage rows of the tests sit on days of 2001 and
/// 2025 that no real row reaches, and the tests delete them; the day marks they set are killed.
///   - TestStateOff: with no setting and no mark State is {"spent":0,"cap":0,"capped":false,"resetsAt":<the next midnight>}, with spent and
///     cap JSON numbers and capped a JSON boolean; an empty or unreadable now means the current time;
///   - TestStateDay: in America/New_York on 2025-03-09, a 23-hour day, a row counts from 05:00:00Z to 03:59:59Z of the next date and not a
///     second outside it; a row of the owner eval and a row of unknown cost never count; resetsAt is 04:00Z of the next date;
///   - TestStateCap: the cap is reached at spend = cap and not below it; the gateway's spend is added on its own date only; a cap that is
///     not a number of 0 or more counts as 0, which is off; a bad gateway spend counts as 0;
///   - TestMarkOnce: MarkCapped returns 1 and fires budget.capped once, with the owner instance and exactly {"day"}, the mark already set
///     during the call; a second call returns 0 and fires nothing; State reports capped for that day only, with no cap and no spend,
///     and with a cap that the spend is under;
///   - TestMarkDefaultSink: a call with no sink class tells the class that the HostSinkClass setting of the Decide item names, and
///     logs no warning;
///   - TestMarkDefaultDay: the day of a call with no day is today in the instance zone, observed in UTC+14 and in UTC-11, two zones whose
///     dates are never both the UTC date, and the mark holds the UTC time; a day that is not a date, or does not exist, is refused;
///   - TestMarkFiresAfterUnlock: the host sink is told after the lock of the day is released (the sink looks at the lock table, and a
///     lock that the test holds is seen there);
///   - TestMarkUnderLock: while another job holds the lock of the day, MarkCapped waits in the LOCK state, sets nothing and does not
///     return; once the other job has set the node and released the lock it returns 0;
///   - TestMarkSeveralAtOnce: three jobs wait for the lock of one day together; when it is released exactly one of them marks the day and
///     tells the sink;
///   - TestMarkLockTimeout: while another job holds the lock of the day for longer than the 5 seconds that MarkCapped waits, it returns 0,
///     sets no mark, sends no event and logs a warning that names the day;
///   - TestMarkSinkFails: a sink that returns an error, and one that throws, leave the mark set, return 1 and are logged as a warning that
///     names the sink, the event and the day.
/// Added by Story 1.6 (DW-76):
///   - TestFaults: State names each way in which a set cap counts less than it was set to, in its output faults, and still counts the spend
///     that it can read: a DailyCostCapUSD, GatewaySpendUSD or GatewaySpendDate that is not valid gives one line that names the setting; a
///     cap above 0 with Usage rows of the day that have no cost gives one line for each model, that names it and is redacted; a cap of 0
///     with such a row, and valid settings, give none; the JSON of State is the same with and without the output.
/// The settings rows are put in place and put back by Test.Agent.RunnerFixture (PutDefault, RememberDefault and RestoreDefaults).
/// The run's number is n from ^OcuTalonTest("BridgeBudget","n") (never reset); the child job reports through
/// ^OcuTalonTest("BridgeBudget",n,...), which OnBeforeAllTests and OnAfterAllTests delete with the reports of earlier runs.
Class OcuTalon.Test.Bridge.Budget Extends %UnitTest.TestCase
{

/// The host sink of the tests.
Parameter SINK = "OcuTalon.Test.Bridge.ProbeSink";

/// The budget settings of the Decide item.
Parameter SETTINGS = "DailyCostCapUSD,GatewaySpendUSD,GatewaySpendDate";

/// The run's number.
Property Number As %Integer;

/// The active production, whose Decide item the settings belong to.
Property Production As %String;

/// The DecisionRefs of the Usage rows that the test wrote.
Property Refs As %List;

/// The days whose mark the test may have set.
Property Days As %List;

/// The settings rows before the test touched them, each RunnerFixture.SnapshotDefault's $ListBuild(item, setting, existed, value, description).
Property Saved As %List;

/// The zone of the process before the test: -1 for none.
Property SavedZone As %String;

Method OnBeforeAllTests() As %Status
{
	Do ..CleanRuns()
	Set ..Number = $Increment(^OcuTalonTest("BridgeBudget", "n"))
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..CleanRuns()
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SavedZone = $SYSTEM.Process.TimeZone()
	Set ..Production = ##class(Ens.Director).GetActiveProductionName()
	Kill ^||ZzProbeSink
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..Refs, position, ref) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ?", ref)
	}
	Set ..Refs = ""
	Set position = 0
	While $ListNext(..Days, position, day) {
		Kill ^OcuTalonBP.UsageCapped(day)
	}
	Set ..Days = ""
	If ..Saved '= "" Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..Saved), "the rows of the settings are put back")
	Set ..Saved = ""
	Do $SYSTEM.Process.TimeZone($Select(..SavedZone = -1: "", 1: ..SavedZone))
	Kill ^||ZzProbeSink
	Quit $$$OK
}

/// With no setting row and no mark, on a day with no row: nothing spent, no cap, not capped, and the end of the day, in UTC.
Method TestStateOff()
{
	If '..Prepare() Quit
	Do $SYSTEM.Process.TimeZone("")
	Do ..Unmark("2001-02-04")
	Set state = ##class(OcuTalon.Bridge.Budget).State("2001-02-04T12:00:00Z")
	Do $$$AssertEquals(state.%ToJSON(), "{""spent"":0,""cap"":0,""capped"":false,""resetsAt"":""2001-02-05T00:00:00Z""}", "State is nothing spent, no cap, not capped, and the next midnight")
	Do $$$AssertEquals(state.%GetTypeOf("spent")_"|"_state.%GetTypeOf("cap")_"|"_state.%GetTypeOf("capped")_"|"_state.%GetTypeOf("resetsAt"), "number|number|boolean|string", "spent and cap are JSON numbers, capped a JSON boolean and resetsAt a string")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State("2001-02-04T00:00:00Z").resetsAt, "2001-02-05T00:00:00Z", "the first second of the day belongs to the day")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State("2001-02-04T23:59:59Z").resetsAt, "2001-02-05T00:00:00Z", "and so does the last")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State("2001-02-05T00:00:00Z").resetsAt, "2001-02-06T00:00:00Z", "while midnight begins the next day")

	Set now = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set current = ##class(OcuTalon.Bridge.Budget).State()
	Do $$$AssertTrue(current.resetsAt ]] now, "with no now, the day is today and it ends after the current time: "_current.resetsAt)
	Do $$$AssertEquals(current.resetsAt, ##class(OcuTalon.Bridge.Budget).State("not a time").resetsAt, "an unreadable now means the current time too")
	Do $$$AssertEquals(current.resetsAt, ##class(OcuTalon.Bridge.Time).DayEndUtc(##class(OcuTalon.Bridge.Time).LocalDate(now)), "and the end of the day is DayEndUtc of its local date")
}

/// New York on Sunday 2025-03-09, which lasts 23 hours (05:00Z to 04:00Z of the next date). The rows inside the day count, the rows a
/// second outside it do not, nor does a row of the owner eval or a row with no cost.
Method TestStateDay()
{
	If '..Prepare() Quit
	Do $SYSTEM.Process.TimeZone("America/New_York")
	Do ..Unmark("2025-03-09")
	Set ref = ..NewRef()
	Do ..AddRow(ref, "2025-03-09T05:00:00Z", .25, "zzsession000000000001")
	Do ..AddRow(ref, "2025-03-10T03:59:59Z", .5, "instance")
	Do ..AddRow(ref, "2025-03-09T04:59:59Z", 100, "instance")
	Do ..AddRow(ref, "2025-03-10T04:00:00Z", 100, "instance")
	Do ..AddRow(ref, "2025-03-09T12:00:00Z", 100, "eval")
	Do ..AddRow(ref, "2025-03-09T13:00:00Z", "", "instance")
	Set state = ##class(OcuTalon.Bridge.Budget).State("2025-03-09T12:00:00Z")
	Do $$$AssertEquals(state.spent, .75, "spent is the two rows inside the day: from 05:00:00Z to 03:59:59Z of the next date")
	Do $$$AssertEquals(state.cap_"|"_state.capped, "0|0", "with no cap, it is not capped")
	Do $$$AssertEquals(state.resetsAt, "2025-03-10T04:00:00Z", "the day ends at midnight in New York: 04:00Z")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State("2025-03-09T05:00:00Z").spent, .75, "the day is the same from its first instant")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State("2025-03-10T03:59:59Z").spent, .75, "and from its last second")
	Set before = ##class(OcuTalon.Bridge.Budget).State("2025-03-09T04:59:59Z")
	Do $$$AssertEquals(before.spent_"|"_before.resetsAt, "100|2025-03-09T05:00:00Z", "the second before it is the day before, 2025-03-08, which ends at 05:00Z and holds only the row at 04:59:59Z")
	Set next = ##class(OcuTalon.Bridge.Budget).State("2025-03-10T04:00:00Z")
	Do $$$AssertEquals(next.spent_"|"_next.resetsAt, "100|2025-03-11T04:00:00Z", "and the day after starts at 04:00:00Z, holds only the row at that second and ends 24 hours later")
}

/// The cap, the gateway's spend and the values that are not numbers, on the New York day of TestStateDay (spent 0.75).
Method TestStateCap()
{
	If '..Prepare() Quit
	Do $SYSTEM.Process.TimeZone("America/New_York")
	Do ..Unmark("2025-03-09")
	Set ref = ..NewRef()
	Do ..AddRow(ref, "2025-03-09T05:00:00Z", .25, "instance")
	Do ..AddRow(ref, "2025-03-10T03:59:59Z", .5, "instance")
	Set now = "2025-03-09T12:00:00Z"
	Do ..Put("DailyCostCapUSD", .75)
	Set state = ##class(OcuTalon.Bridge.Budget).State(now)
	Do $$$AssertEquals(state.cap_"|"_state.spent_"|"_state.capped, ".75|.75|1", "capped when spent has reached the cap")
	Do ..Put("DailyCostCapUSD", 1.75)
	Set state = ##class(OcuTalon.Bridge.Budget).State(now)
	Do $$$AssertEquals(state.cap_"|"_state.spent_"|"_state.capped, "1.75|.75|0", "not capped with 1 dollar to spare")
	Do ..Put("DailyCostCapUSD", .749999)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State(now).capped, 1, "capped below the spend")

	Do ..Put("DailyCostCapUSD", 2.75)
	Do ..Put("GatewaySpendUSD", 2)
	Do ..Put("GatewaySpendDate", "2025-03-09")
	Set state = ##class(OcuTalon.Bridge.Budget).State(now)
	Do $$$AssertEquals(state.spent_"|"_state.capped, "2.75|1", "the gateway's spend is added on its own date, so the cap of 2.75 is reached")
	Do ..Put("DailyCostCapUSD", 2.76)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State(now).capped, 0, "and a cap of 2.76 is not")
	Do ..Put("GatewaySpendDate", "2025-03-08")
	Set state = ##class(OcuTalon.Bridge.Budget).State(now)
	Do $$$AssertEquals(state.spent, .75, "the gateway's spend of the day before is not added")
	Do ..Put("GatewaySpendDate", "2025-03-10")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State(now).spent, .75, "nor is that of the day after")
	Do ..Put("GatewaySpendDate", "")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State(now).spent, .75, "nor is a spend with no date")
	Do ..Put("GatewaySpendDate", "2025-03-09")
	Do ..Put("GatewaySpendUSD", "x")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State(now).spent, .75, "a gateway spend that is not a number counts as 0")
	Do ..Put("GatewaySpendUSD", -3)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State(now).spent, .75, "and so does a negative one")
	Do ..Put("GatewaySpendUSD", 0.5)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State("2025-03-10T12:00:00Z").spent, 0, "the next day has nothing spent: the gateway's date is not its day")

	Do ..Put("GatewaySpendDate", "")
	For bad = "x", -1, "", "1,5", "$5" {
		Do ..Put("DailyCostCapUSD", bad)
		Set state = ##class(OcuTalon.Bridge.Budget).State(now)
		Do $$$AssertEquals(state.cap_"|"_state.capped, "0|0", "a cap of '"_bad_"' counts as 0, which is off, with 0.75 spent")
	}
	Do ..Put("DailyCostCapUSD", 0)
	Set state = ##class(OcuTalon.Bridge.Budget).State(now)
	Do $$$AssertEquals(state.cap_"|"_state.capped, "0|0", "a cap of 0 is off")
}

/// DW-76: the cap fails open, and says so. State gives, in its output faults, one redacted line for each way in which a set cap counts
/// less than it was set to, and still counts the spend that it can read. The settings are put one at a time, over valid ones, on a day of
/// 2001 that no real row reaches; the Usage rows are the test's, and OnAfterOneTest deletes them.
Method TestFaults()
{
	If '..Prepare() Quit
	Do $SYSTEM.Process.TimeZone("")
	Set day = "2001-02-06"
	Set now = day_"T12:00:00Z"
	Do ..Unmark(day)
	Set budget = "OcuTalon.Bridge.Budget"
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set ref = ..NewRef()
	Do ..AddRow(ref, day_"T06:00:00Z", .25, "instance")
	Do ..Put("DailyCostCapUSD", 5)
	Do ..Put("GatewaySpendUSD", 1)
	Do ..Put("GatewaySpendDate", day)

	// 6. every setting valid: no fault, and the JSON of State is what it was
	Set state = $ClassMethod(budget, "State", now, .faults)
	Do $$$AssertEquals(faults.%Size(), 0, "valid settings and priced rows give no fault")
	Do $$$AssertEquals(state.%ToJSON(), "{""spent"":1.25,""cap"":5,""capped"":false,""resetsAt"":""2001-02-07T00:00:00Z""}", "the JSON of State holds the same keys in the same order")
	Do $$$AssertEquals($ClassMethod(budget, "State", now).%ToJSON(), state.%ToJSON(), "with and without the output")
	Do $$$AssertEquals($ClassMethod(budget, "State", now, .again).%ToJSON(), state.%ToJSON(), "and the output is an array")
	Do $$$AssertTrue($IsObject(again) && again.%IsA("%Library.DynamicArray"), "faults is a dynamic array")

	// 1. a cap that is not a number
	Do ..Put("DailyCostCapUSD", "abc")
	Set state = $ClassMethod(budget, "State", now, .faults)
	Do $$$AssertEquals(faults.%Size(), 1, "a cap of abc gives one fault")
	Do $$$AssertTrue(faults.%Get(0) [ "DailyCostCapUSD", "that names DailyCostCapUSD: "_faults.%Get(0))
	Do $$$AssertEquals(state.cap_"|"_state.capped, "0|0", "and the cap counts as 0, which is off")
	Do $$$AssertEquals(state.spent, 1.25, "while the spend that can be read is still counted")

	// 2. a gateway spend that is not a number, with a cap that the priced rows alone reach
	Do ..Put("DailyCostCapUSD", .2)
	Do ..Put("GatewaySpendUSD", "x")
	Set state = $ClassMethod(budget, "State", now, .faults)
	Do $$$AssertEquals(faults.%Size(), 1, "a gateway spend of x gives one fault")
	Do $$$AssertTrue(faults.%Get(0) [ "GatewaySpendUSD", "that names GatewaySpendUSD: "_faults.%Get(0))
	Do $$$AssertEquals(state.spent_"|"_state.capped, ".25|1", "the gateway's spend is not counted, and the rows that can be read still reach the cap")

	// 3. a gateway date that is not a date
	Do ..Put("GatewaySpendUSD", 1)
	For bad = "2001-13-45", "2001-02-30", "today", "2001-2-6" {
		Do ..Put("GatewaySpendDate", bad)
		Set state = $ClassMethod(budget, "State", now, .faults)
		Do $$$AssertEquals(faults.%Size(), 1, "a gateway date of "_bad_" gives one fault")
		Do $$$AssertTrue(faults.%Get(0) [ "GatewaySpendDate", "that names GatewaySpendDate: "_faults.%Get(0))
		Do $$$AssertEquals(state.spent, .25, "and the gateway's spend is not counted")
	}
	Do ..Put("GatewaySpendDate", "")
	Do ..Put("GatewaySpendUSD", "")
	Set state = $ClassMethod(budget, "State", now, .faults)
	Do $$$AssertEquals(faults.%Size(), 0, "settings that are empty are no fault: nothing was set")
	Do ..Put("GatewaySpendDate", "2001-02-05")
	Set state = $ClassMethod(budget, "State", now, .faults)
	Do $$$AssertEquals(faults.%Size(), 0, "nor is a gateway date of another day")

	// 4. a cap above 0 and a Usage row of the day with no cost
	Do ..Put("DailyCostCapUSD", 1)
	Do $$$AssertStatusOK($ClassMethod(fixture, "AddUsage", ref, "zz-unpriced", 10, 5, 0, 0, "", day_"T07:00:00Z", "instance"), "a Usage row of zz-unpriced with no cost is saved")
	Do $$$AssertStatusOK($ClassMethod(fixture, "AddUsage", ref, "zz-unpriced", 10, 5, 0, 0, "", day_"T08:00:00Z", "instance"), "and a second one")
	Do $$$AssertStatusOK($ClassMethod(fixture, "AddUsage", ref, "zz-eval-unpriced", 10, 5, 0, 0, "", day_"T08:00:00Z", "eval"), "and one of the owner eval, which no cap counts")
	Do $$$AssertStatusOK($ClassMethod(fixture, "AddUsage", ref, "zz-other-day", 10, 5, 0, 0, "", "2001-02-07T08:00:00Z", "instance"), "and one of another day")
	Set state = $ClassMethod(budget, "State", now, .faults)
	Do $$$AssertEquals(faults.%Size(), 1, "the unpriced model gives one line, however many rows it has")
	Do $$$AssertTrue((faults.%Get(0) [ "zz-unpriced") && (faults.%Get(0) '[ "zz-eval-unpriced") && (faults.%Get(0) '[ "zz-other-day"), "that names the model, and no model of another owner or day: "_faults.%Get(0))
	Do $$$AssertEquals(state.capped_"|"_state.spent, "0|.25", "the cap fails open: the day is not capped, and spent leaves the rows out")
	Do $$$AssertStatusOK($ClassMethod(fixture, "AddUsage", ref, "zz-also-unpriced", 10, 5, 0, 0, "", day_"T09:00:00Z", "instance"), "a second unpriced model is saved")
	Do $ClassMethod(budget, "State", now, .faults)
	Do $$$AssertEquals(faults.%Size(), 2, "it gives a second line")
	Set fake = "zzfakebearer0123456789"
	Do $$$AssertStatusOK($ClassMethod(fixture, "AddUsage", ref, "zz Bearer "_fake, 10, 5, 0, 0, "", day_"T10:00:00Z", "instance"), "a model whose name holds a Bearer token is saved")
	Do $ClassMethod(budget, "State", now, .faults)
	Do $$$AssertEquals(faults.%Size(), 3, "it gives a third line")
	Set all = faults.%ToJSON()
	Do $$$AssertTrue(all '[ fake, "which is redacted: the fake token is in no line")
	Do $$$AssertTrue(all [ "[redacted]", "and shows [redacted]")

	// 5. a cap of 0 with such rows
	Do ..Put("DailyCostCapUSD", 0)
	Set state = $ClassMethod(budget, "State", now, .faults)
	Do $$$AssertEquals(faults.%Size(), 0, "with the cap off an unpriced row is no fault")
	Do ..Put("DailyCostCapUSD", "")
	Do $ClassMethod(budget, "State", now, .faults)
	Do $$$AssertEquals(faults.%Size(), 0, "nor with the cap empty")

	// several faults together, in the order of the specification: the cap, the gateway's spend, its date, the unpriced models
	Do ..Put("DailyCostCapUSD", "abc")
	Do ..Put("GatewaySpendUSD", "x")
	Do ..Put("GatewaySpendDate", "2001-13-45")
	Do $ClassMethod(budget, "State", now, .faults)
	Do $$$AssertEquals(faults.%Size(), 3, "three bad settings give three lines")
	Do $$$AssertTrue((faults.%Get(0) [ "DailyCostCapUSD") && (faults.%Get(1) [ "GatewaySpendUSD") && (faults.%Get(2) [ "GatewaySpendDate"), "the cap first, then the gateway's spend, then its date")
}

/// MarkCapped on a new day: it returns 1, tells the sink once, with the owner instance and exactly {"day"}, after the mark is set. A
/// second call returns 0 and tells nobody. State reports capped for the marked day, with no cap and nothing spent, and for no other day.
Method TestMarkOnce()
{
	If '..Prepare() Quit
	Do $SYSTEM.Process.TimeZone("")
	Set day = "2001-02-03"
	Do ..Unmark(day)
	Do ..Unmark("2001-02-04")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State("2001-02-03T12:00:00Z").capped, 0, "the day is not capped before the mark")
	Set marked = ##class(OcuTalon.Bridge.Budget).MarkCapped(day, ..#SINK)
	Do $$$AssertEquals(marked, 1, "the first call sets the mark")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "and the sink got one event")
	Set call = $Get(^||ZzProbeSink(1))
	Do $$$AssertEquals($List(call, 1)_"|"_$List(call, 2), "budget.capped|instance", "budget.capped for the owner instance")
	Do $$$AssertEquals($List(call, 3), "{""day"":""2001-02-03""}", "with exactly the day as its payload")
	Do $$$AssertEquals($List(call, 4), 0, "outside any transaction")
	Do $$$AssertEquals($List(call, 6), 1, "and with the mark already set")
	Do $$$AssertTrue(^OcuTalonBP.UsageCapped(day) ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "the mark holds a UTC time: "_^OcuTalonBP.UsageCapped(day))
	Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(day)), 1, "and is a node of its own")
	Set at = ^OcuTalonBP.UsageCapped(day)

	Set marked = ##class(OcuTalon.Bridge.Budget).MarkCapped(day, ..#SINK)
	Do $$$AssertEquals(marked, 0, "the second call returns 0")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "and sends no event")
	Do $$$AssertEquals(^OcuTalonBP.UsageCapped(day), at, "the mark is as it was")

	Set state = ##class(OcuTalon.Bridge.Budget).State("2001-02-03T12:00:00Z")
	Do $$$AssertEquals(state.capped_"|"_state.cap_"|"_state.spent, "1|0|0", "State reports the day capped, with no cap and nothing spent")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State("2001-02-04T12:00:00Z").capped, 0, "but not the next day")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State("2001-02-02T12:00:00Z").capped, 0, "nor the day before")
	Do ..Put("DailyCostCapUSD", 5)
	Set state = ##class(OcuTalon.Bridge.Budget).State("2001-02-03T12:00:00Z")
	Do $$$AssertEquals(state.capped_"|"_state.cap_"|"_state.spent, "1|5|0", "and capped with a cap of 5 dollars that nothing spent has reached")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State("2001-02-04T12:00:00Z").capped, 0, "while the next day, with the same cap and no mark, is not")
}

/// A call with no sink class tells the host sink that the HostSinkClass setting of the active production's Decide item names (here
/// the production's own sink, which takes every event): it returns 1, sets the mark and logs no warning. A sink class that FireEvent
/// refuses would be logged as a warning that names the day.
Method TestMarkDefaultSink()
{
	If '..Prepare() Quit
	Set day = "2001-02-12"
	Do ..Unmark(day)
	Set sink = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("HostSinkClass")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Ext.Accessor).Check("HostSinkClass", sink), "the Decide item names a host sink, "_sink)
	Set mark = ..LogMark()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).MarkCapped(day), 1, "a call with no sink class marks the day")
	Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(day)), 1, "the mark is set")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Process.Decide", "FireEvent", $ListBuild(day)), 0, "and the item's host sink took budget.capped: no warning names the day")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Budget", "MarkCapped"), 0, "and MarkCapped logged none")
}

/// A call with no day marks today in the instance zone and tells the sink that day. The zones are UTC+14 and UTC-11: at every moment at
/// least one of them has a local date other than the UTC date, so a default day of the UTC date fails here at every moment. A day that
/// is not a date, or does not exist, is refused with no mark and no event.
Method TestMarkDefaultDay()
{
	If '..Prepare() Quit
	For zone = "Pacific/Kiritimati", "Pacific/Pago_Pago" {
		Do $SYSTEM.Process.TimeZone(zone)
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Time).ToLocal("2025-01-15T12:00:00Z"), $Select(zone [ "Kiritimati": "2025-01-16T02:00:00", 1: "2025-01-15T01:00:00"), "the process is in "_zone_", whose local time is not the UTC time")
		Kill ^||ZzProbeSink
		Set first = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())
		If $Data(^OcuTalonBP.UsageCapped(first)) {
			Do $$$AssertSkipped("the day "_first_" is already marked in this database, so the default day in "_zone_" cannot be observed")
			Continue
		}
		Set ..Days = ..Days _ $ListBuild(first)
		Set utcBefore = ..UtcNow()
		Set marked = ##class(OcuTalon.Bridge.Budget).MarkCapped("", ..#SINK)
		Set utcAfter = ..UtcNow()
		Set last = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())
		Set ..Days = ..Days _ $ListBuild(last)
		Do $$$AssertEquals(marked, 1, "in "_zone_" a call with no day sets a mark")
		Set event = $Get(^||ZzProbeSink(1))
		Set day = $Select(event = "": "", 1: $Piece($List(event, 3), """", 4))
		Do $$$AssertTrue((day = first) || (day = last), "for today in the zone, which the sink is told: "_day_" (the zone's date is "_first_")")
		Do $$$AssertEquals($Select(day = "": 0, 1: $Data(^OcuTalonBP.UsageCapped(day))), 1, "and the mark is there")
		Set at = $Select(day = "": "", 1: $Get(^OcuTalonBP.UsageCapped(day)))
		Do $$$AssertTrue((at '= "") && '(utcBefore ] at) && '(at ] utcAfter), "and holds the UTC time of the call, not the local time: "_at_" lies between "_utcBefore_" and "_utcAfter)
	}

	Kill ^||ZzProbeSink
	For bad = "x", "2001-2-3", "2001-02-03T00:00:00Z", "2001-02-03 ", "2025-13-45", "2001-02-30" {
		Set marked = ##class(OcuTalon.Bridge.Budget).MarkCapped(bad, ..#SINK)
		Do $$$AssertEquals(marked_"|"_(+$Get(^||ZzProbeSink))_"|"_$Data(^OcuTalonBP.UsageCapped(bad)), "0|0|0", "the day '"_bad_"' is refused: no mark, no event")
	}
}

/// The sink is told after the lock of the day is released: the probe sink looks at the lock table when it is called. First the probe
/// is shown to see a lock that the test holds, and to see it gone once released, so that "no lock held" in the sink means something.
Method TestMarkFiresAfterUnlock()
{
	If '..Prepare() Quit
	Set probe = "OcuTalon.Test.Bridge.ProbeSink"
	Set other = "2001-02-09"
	Lock +^OcuTalonBP.UsageCapped(other):5
	Set held = $Test
	Do $$$AssertEquals(held, 1, "the test holds the lock of another day")
	If 'held Quit
	Do $$$AssertEquals($ClassMethod(probe, "LockHeld", other), 1, "the probe sees a lock that is held")
	Do $$$AssertEquals($ClassMethod(probe, "LockHeld", "2001-02-11"), 0, "and not the lock of a day that nobody holds")
	Lock -^OcuTalonBP.UsageCapped(other)
	Do $$$AssertEquals($ClassMethod(probe, "LockHeld", other), 0, "and sees it gone once it is released")

	Set day = "2001-02-10"
	Do ..Unmark(day)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).MarkCapped(day, ..#SINK), 1, "the day is marked")
	Set call = $Get(^||ZzProbeSink(1))
	Do $$$AssertEquals($List(call, 1)_"|"_$List(call, 6), "budget.capped|1", "and the sink was told, with the mark set")
	Do $$$AssertEquals($List(call, 7), 0, "while no process held the lock of the day")
}

/// Another job holds the lock of the day: MarkCapped waits for it (the job is in the LOCK state), sets nothing and has not returned.
/// That job sets the node and releases the lock, and MarkCapped then returns 0 and tells nobody.
Method TestMarkUnderLock()
{
	If '..Prepare() Quit
	Set day = "2001-02-06"
	Do ..Unmark(day)
	Set run = $Name(^OcuTalonTest("BridgeBudget", ..Number))
	Kill @run
	Lock +^OcuTalonBP.UsageCapped(day):5
	Set held = $Test
	Do $$$AssertEquals(held, 1, "the test holds the lock of the day")
	If 'held Quit
	Try {
		Job ##class(OcuTalon.Test.Bridge.Budget).MarkInJob(day, ..Number)
		Do $$$AssertEquals(..WaitBlocked(run, 120), 1, "the other job waits for the lock of the day: it is in the LOCK state")
		Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(day)), 0, "so the node is still absent")
		Do $$$AssertEquals($Get(@run@("done"), 0), 0, "and the call has not returned")
		Set ^OcuTalonBP.UsageCapped(day) = ##class(OcuTalon.Bridge.Time).NowUtc()
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Lock -^OcuTalonBP.UsageCapped(day)
	Do ..WaitFor($Name(@run@("done")), 1, 120)
	Do $$$AssertEquals($Get(@run@("done")), 1, "once the lock is released the call returns")
	Do $$$AssertEquals($Get(@run@("result")), 0, "with 0, because the node was set while it waited")
	Do $$$AssertTrue($Get(@run@("seconds"), 5) < 5, "on the release, before its 5-second wait for the lock ran out: "_$Get(@run@("seconds"))_" seconds")
	Do $$$AssertEquals($Get(@run@("events"), -1), 0, "and it told nobody")
	Do $$$AssertEquals($Get(@run@("error")), "", "and without an error")
	Kill @run
}

/// Three jobs call MarkCapped for one day together, while another process holds its lock, and all three wait for it. The test releases the lock
/// without marking the day: exactly one of the three marks it and returns 1, the other two find the mark and return 0, and the sinks
/// of the three jobs were told once in all.
Method TestMarkSeveralAtOnce()
{
	If '..Prepare() Quit
	Set day = "2001-02-08"
	Set jobs = 3
	Do ..Unmark(day)
	Set run = $Name(^OcuTalonTest("BridgeBudget", ..Number))
	Kill @run
	Lock +^OcuTalonBP.UsageCapped(day):5
	Set held = $Test
	Do $$$AssertEquals(held, 1, "the test holds the lock of the day")
	If 'held Quit
	Try {
		For i = 1:1:jobs {
			Job ##class(OcuTalon.Test.Bridge.Budget).MarkInJob(day, ..Number, i)
		}
		Set ready = 0
		For i = 1:1:jobs {
			Do ..WaitFor($Name(@run@(i, "started")), 1, 120)
			Set ready = ready + $Get(@run@(i, "started"), 0)
		}
		Do $$$AssertEquals(ready, jobs, "all "_jobs_" jobs started")
		Set @run@("go") = 1
		Set waiting = 0
		For i = 1:1:jobs {
			Set waiting = waiting + ..WaitBlocked($Name(@run@(i)), 120)
		}
		Do $$$AssertEquals(waiting, jobs, "all "_jobs_" jobs wait for the lock of the day")
		Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(day)), 0, "and the day is not marked")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Set @run@("go") = 1
	Lock -^OcuTalonBP.UsageCapped(day)
	Set finished = 0, marks = 0, events = 0, errors = "", slowest = 0
	For i = 1:1:jobs {
		Do ..WaitFor($Name(@run@(i, "done")), 1, 120)
		Set finished = finished + $Get(@run@(i, "done"), 0)
		Set marks = marks + $Get(@run@(i, "result"), 0)
		Set events = events + $Get(@run@(i, "events"), 0)
		Set errors = errors _ $Get(@run@(i, "error"))
		If $Get(@run@(i, "seconds"), 5) > slowest Set slowest = $Get(@run@(i, "seconds"), 5)
	}
	Do $$$AssertEquals(finished, jobs, "all "_jobs_" calls return once the lock is released")
	Do $$$AssertTrue(slowest < 5, "on the release, before their 5-second wait for the lock ran out: the slowest took "_slowest_" seconds")
	Do $$$AssertEquals(marks, 1, "exactly one of them marked the day")
	Do $$$AssertEquals(events, 1, "and exactly one budget.capped was sent")
	Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(day)), 1, "the day is marked")
	Do $$$AssertEquals(errors, "", "without an error")
	Kill @run
}

/// Another job holds the lock of the day for longer than MarkCapped waits: it gives up after its 5 seconds. It returns 0, sets no mark,
/// sends no event, and logs a warning that names the day.
Method TestMarkLockTimeout()
{
	If '..Prepare() Quit
	Set day = "2001-02-07"
	Do ..Unmark(day)
	Set run = $Name(^OcuTalonTest("BridgeBudget", ..Number))
	Kill @run
	Set mark = ..LogMark()
	Lock +^OcuTalonBP.UsageCapped(day):5
	Set held = $Test
	Do $$$AssertEquals(held, 1, "the test holds the lock of the day")
	If 'held Quit
	Try {
		Job ##class(OcuTalon.Test.Bridge.Budget).MarkInJob(day, ..Number)
		Do ..WaitFor($Name(@run@("done")), 1, 120)
		Do $$$AssertEquals($Get(@run@("done")), 1, "the call returns although the lock is still held")
		Do $$$AssertEquals($Get(@run@("result")), 0, "with 0")
		Do $$$AssertTrue(($Get(@run@("seconds"), 0) '< 4) && ($Get(@run@("seconds"), 0) < 10), "after it waited its 5 seconds for the lock: "_$Get(@run@("seconds"))_" seconds")
		Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(day)), 0, "no mark is set")
		Do $$$AssertEquals($Get(@run@("events"), -1), 0, "no event is sent")
		Do $$$AssertEquals($Get(@run@("error")), "", "and there is no error")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Lock -^OcuTalonBP.UsageCapped(day)
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Budget", "MarkCapped", $ListBuild(day)), 1, "one warning names the day whose lock was not free")
	Kill @run
}

/// The sink fails, by an error status and by an exception: the mark stays, MarkCapped returns 1, State reports the day capped, and the
/// warning names the sink, the event and the day.
Method TestMarkSinkFails()
{
	If '..Prepare() Quit
	Do $SYSTEM.Process.TimeZone("")
	Set n = 0
	For mode = "error", "throw" {
		Set day = "2001-03-0"_$Increment(n)
		Do ..Unmark(day)
		Kill ^||ZzProbeSink
		Set ^||ZzProbeSink("mode") = mode
		Set mark = ..LogMark()
		Set marked = ##class(OcuTalon.Bridge.Budget).MarkCapped(day, ..#SINK)
		Do $$$AssertEquals(marked, 1, "in "_mode_" mode the call returns 1")
		Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "the sink was called once")
		Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(day)), 1, "the mark stays")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State(day_"T12:00:00Z").capped, 1, "and State reports the day capped")
		Do ..AssertWarning(mark, ..#SINK, "budget.capped", day, mode)
		Kill ^||ZzProbeSink
		Set ^||ZzProbeSink("mode") = mode
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).MarkCapped(day, ..#SINK), 0, "a second call returns 0 in "_mode_" mode")
		Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and sends no event")
	}
	Set day = "2001-03-09"
	Do ..Unmark(day)
	Kill ^||ZzProbeSink
	Set mark = ..LogMark()
	Set marked = ##class(OcuTalon.Bridge.Budget).MarkCapped(day, "OcuTalon.Test.Bridge.ZzNoSuchSink")
	Do $$$AssertEquals(marked_"|"_$Data(^OcuTalonBP.UsageCapped(day)), "1|1", "a sink class that does not exist leaves the mark and returns 1")
	Do ..AssertWarning(mark, "OcuTalon.Test.Bridge.ZzNoSuchSink", "budget.capped", day, "a sink class that does not exist")
}

/// The job body of the lock tests: calls MarkCapped for the day and reports the job's pid, the result, the seconds the call took and the
/// number of events that the probe sink took, under ^OcuTalonTest("BridgeBudget", number), or under its subscript index when one is given.
/// A job with an index reports that it started and then waits (up to 120 seconds) for the test to set ^OcuTalonTest("BridgeBudget",
/// number, "go"), so that the jobs of one test call MarkCapped together.
ClassMethod MarkInJob(day As %String, number As %Integer, index As %Integer = "")
{
	Set run = $Select(index = "": $Name(^OcuTalonTest("BridgeBudget", number)), 1: $Name(^OcuTalonTest("BridgeBudget", number, index)))
	Try {
		Set @run@("pid") = $Job
		Set @run@("started") = 1
		If index '= "" {
			Set deadline = $ZHorolog + 120
			While '$Get(^OcuTalonTest("BridgeBudget", number, "go")) && ($ZHorolog < deadline) {
				Hang 0.05
			}
		}
		Set begun = $ZHorolog
		Set @run@("result") = ##class(OcuTalon.Bridge.Budget).MarkCapped(day, "OcuTalon.Test.Bridge.ProbeSink")
		Set @run@("seconds") = $ZHorolog - begun
		Set @run@("events") = +$Get(^||ZzProbeSink)
	} Catch exception {
		Set @run@("error") = exception.DisplayString()
	}
	Set @run@("done") = 1
}

/// --- helpers ---
/// 1 when a production is active, so that the settings of its Decide item can be written and read. Otherwise the test fails with the
/// reason, and quits. The rows of the three budget settings are removed for the test and put back by OnAfterOneTest.
Method Prepare() As %Boolean [ Private ]
{
	If ..Production = "" {
		Do $$$AssertTrue(0, "no production is active, so the budget settings of its Decide item cannot be read")
		Quit 0
	}
	Set names = $ListFromString(..#SETTINGS)
	Set position = 0
	While $ListNext(names, position, name) {
		Do ..Snapshot(name)
		Do ##class(Ens.Config.DefaultSettings).%DeleteId(..SettingId(name))
	}
	Quit 1
}

/// The id of the System Default Settings row of a setting of the Decide item of the active production.
Method SettingId(setting As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).DefaultId("Decide", setting)
}

/// Remembers the row of the setting, once, so that OnAfterOneTest can put it back (RunnerFixture.RememberDefault).
Method Snapshot(setting As %String) [ Private ]
{
	Set saved = ..Saved
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RememberDefault(.saved, "Decide", setting)
	Set ..Saved = saved
}

/// Writes the row of a setting of the Decide item of the active production (RunnerFixture.PutDefault: a value that cannot be saved is
/// set by SQL, which checks nothing, so that it can reach the item as a hand-edited global or an import would, and Budget counts it as 0).
Method Put(setting As %String, value As %String) [ Private ]
{
	Do ..Snapshot(setting)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).PutDefault("Decide", setting, value), "the setting "_setting_" is '"_value_"'")
}

/// Removes the mark of the day now, and again when the test is over.
Method Unmark(day As %String) [ Private ]
{
	Kill ^OcuTalonBP.UsageCapped(day)
	Set ..Days = ..Days _ $ListBuild(day)
}

/// A new DecisionRef, which the test deletes the Usage rows of afterwards.
Method NewRef() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Refs = ..Refs _ $ListBuild(ref)
	Quit ref
}

/// Saves a Usage row recorded at the UTC time for the owner, with the cost ("" for an unknown cost) and no token counts
/// (Test.Agent.RunnerFixture.AddUsage).
Method AddRow(ref As %String, recordedAt As %String, cost As %String, owner As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).AddUsage(ref, "claude-haiku-5-5", "", "", "", "", cost, recordedAt, owner), "a Usage row of "_owner_" at "_recordedAt_" is saved")
}

/// Deletes the reports of every run, this one and the runs that failed before: every node under the counter's level except the counter.
ClassMethod CleanRuns() [ Private ]
{
	Set run = ""
	For {
		Set run = $Order(^OcuTalonTest("BridgeBudget", run))
		Quit:run=""
		If run '= "n" Kill ^OcuTalonTest("BridgeBudget", run)
	}
}

/// Waits up to seconds for the global node named by ref to reach count.
ClassMethod WaitFor(ref As %String, count As %Integer, seconds As %Integer) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While (+$Get(@ref) < count) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

/// 1 when the job that reports under the global reference run has started and is in the LOCK state, waiting for a lock; it waits up to
/// seconds for that, and gives up when the job has returned. 0 when the job never waits for a lock.
ClassMethod WaitBlocked(run As %String, seconds As %Integer) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + seconds
	Set blocked = 0
	While 1 {
		Set pid = $Get(@run@("pid"))
		If pid '= "" {
			Try {
				Set blocked = ($Extract($SYSTEM.Process.State(pid), 1, 4) = "LOCK")
			} Catch exception {
				Set blocked = 0
			}
		}
		If blocked || $Get(@run@("done")) || ($ZHorolog '< deadline) Quit
		Hang 0.05
	}
	Quit blocked
}

/// The current UTC time, YYYY-MM-DDThh:mm:ssZ, from the clock that is UTC whatever the zone of the process.
ClassMethod UtcNow() As %String [ Private ]
{
	Quit $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T")_"Z"
}

/// The highest id of the event log (Test.Agent.RunnerFixture.EventMark).
ClassMethod LogMark() As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
}

/// Asserts that the event log holds, after the mark, one warning (type 3) of Decide's FireEvent whose text names the class, the event and
/// the subject (here the day).
Method AssertWarning(mark As %Integer, class As %String, event As %String, subject As %String, label As %String) [ Private ]
{
	Set found = ##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Process.Decide", "FireEvent", $ListBuild(class, event, subject))
	Do $$$AssertEquals(found, 1, label_": one warning names "_class_", "_event_" and "_subject)
}

}
