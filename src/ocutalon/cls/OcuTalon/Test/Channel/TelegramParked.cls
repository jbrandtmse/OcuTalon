Include Ensemble

/// Tests of the parked state of the Telegram items and of the readiness check that the runner restarts use (Story 12.9; AD-22, AD-23,
/// DW-591). They run in throwaways and in CI only (Rule 21), against the CI mock, on a stack whose start has been parked
/// (docker/tests/lib-live.sh live_park_telegram, ci/warm.sh up). No bot is called and no token is read or written.
///   - TestPark: from a TelegramIn that runs against the mock, BotApi.Park leaves the stack as a start with no token does: both Enabled
///     rows 0, no job of either item, the Telegram mark off, no kept offset, and an empty list of Bot API calls at the mock;
///   - TestReadinessFollowsTheRow: RunnerFixture.NotRunningNow, which WaitAllRun, Restart and ReadyReason wait on, leaves out an item whose
///     Enabled row is 0 even when the production's runtime flag of the item still says enabled (the state that kept the restarts of the
///     runners waiting for TelegramIn in CI's lane-a Channel shard), and still reports an item whose row is 1 and which has no job;
///   - TestStopAsksAgain, TestStopWithoutAskingStays, TestStopThatNeverEnds, TestNoAskWhenGone and TestParkWaitsLonger: the wait of the
///     park (LiveCase.AwaitStop) against a stub that stands for the production: a job that the first stop lost goes when the update is
///     asked for again (red without the retry, as the old single wait of 30 s had none), a wait without a retry asks for no update, a job
///     that never goes still fails at the bound with the updates counted, a job that is gone costs no update, and the park waits longer
///     than a test does;
///   - TestRealUpdateAndJobText: the same wait against the real production, whose update is asked for while TelegramIn runs, and the
///     text that names a job.
/// The Enabled rows, the runtime flag of TelegramIn and the Telegram mark are saved before each test and put back after it.
Class OcuTalon.Test.Channel.TelegramParked Extends %UnitTest.TestCase
{

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter CASE = "OcuTalon.Test.Channel.LiveCase";

Parameter BOTAPI = "OcuTalon.Test.Channel.BotApi";

/// The item the tests use.
Parameter ITEM = "TelegramIn";

/// "" when the stack can run these tests; otherwise the reason, which each test reports as its failure.
Property Missing As %String(MAXLEN = "");

/// The Enabled rows as found: for each Telegram item, the snapshot of RunnerFixture.SnapshotDefault.
Property Rows As %List;

/// The runtime flag of the item as found: $Data and the value.
Property FlagData As %Integer;

Property FlagValue As %String;

/// The Telegram mark as found.
Property Mark As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set ..Missing = $ClassMethod(..#FIXTURE, "ReadyReason")
	If ..Missing = "" Set ..Missing = $ClassMethod(mock, "TelegramMissingReason", $SYSTEM.Util.GetEnviron($Parameter(mock, "TELEGRAMBASEVAR")), $SYSTEM.Util.GetEnviron($Parameter(mock, "TELEGRAMTOKENVAR")))
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Rows = ""
	For item = "TelegramIn", "TelegramOut" {
		Set ..Rows = ..Rows _ $ListBuild($ClassMethod(..#FIXTURE, "SnapshotDefault", item, "Enabled"))
	}
	Set ..FlagData = $Data($$$ConfigIsEnabled(..#ITEM), value)
	Set ..FlagValue = $Get(value)
	Set ..Mark = ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Data.StatusMark).#TELEGRAMMARK)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..FlagData {
		Set $$$ConfigIsEnabled(..#ITEM) = ..FlagValue
	} Else {
		Kill $$$ConfigIsEnabled(..#ITEM)
	}
	Do $ClassMethod(..#FIXTURE, "RestoreDefaults", ..Rows)
	Do ##class(OcuTalon.Data.StatusMark).Record(##class(OcuTalon.Data.StatusMark).#TELEGRAMMARK, ..Mark)
	Quit $$$OK
}

/// 1 when the stack can run the tests; otherwise the test fails with the reason.
Method Ready() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// Park from a running TelegramIn: the state of a start with no token.
Method TestPark()
{
	If '..Ready() Quit
	Set rows = ""
	Do $$$AssertStatusOK($ClassMethod(..#CASE, "Enable", "TelegramIn", .rows), "TelegramIn is enabled and has a job against the mock")
	Do $$$AssertTrue($ListLength($ClassMethod(..#FIXTURE, "Jobs", "TelegramIn")) > 0, "TelegramIn runs before the park")
	Do $ClassMethod(..#BOTAPI, "SetOffset", 7)
	Do $$$AssertEquals($ClassMethod(..#BOTAPI, "Offset"), 7, "an offset is kept before the park")
	Do $$$AssertStatusOK($ClassMethod(..#BOTAPI, "Park"), "Park succeeds")
	For item = "TelegramIn", "TelegramOut" {
		Set row = $ClassMethod(..#FIXTURE, "SnapshotDefault", item, "Enabled")
		Do $$$AssertEquals($List(row, 3)_"|"_$List(row, 4), "1|0", item_"'s Enabled row is 0")
		Do $$$AssertEquals($ListLength($ClassMethod(..#FIXTURE, "Jobs", item)), 0, item_" has no job")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).TelegramState(.bot)_"|"_bot, "off|", "the Telegram mark is off, with no bot name")
	Do $$$AssertEquals($ClassMethod(..#BOTAPI, "Offset"), "", "no offset is kept")
	Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls().%Size(), 0, "the mock's list of Bot API calls is empty")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "NotRunningNow"), "", "every item that should run has its job")
}

/// The readiness check follows the Enabled row, not a runtime flag that a test left behind.
Method TestReadinessFollowsTheRow()
{
	If '..Ready() Quit
	Do $$$AssertStatusOK($ClassMethod(..#BOTAPI, "Park"), "the stack is parked first")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "NotRunningNow"), "", "a parked stack has every item that should run")
	Set $$$ConfigIsEnabled(..#ITEM) = 1
	Do $$$AssertTrue($ListFind($ListFromString(##class(OcuTalon.Install.Step.Production).NotRunning()), ..#ITEM) > 0, "the production's own check names "_..#ITEM_" while its runtime flag says enabled and it has no job")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "NotRunningNow"), "", "RunnerFixture.NotRunningNow leaves it out, as its Enabled row is 0")
	Do $$$AssertTrue($ClassMethod(..#FIXTURE, "WaitAllRun"), "and the wait of the restarts ends at once")

	Set saved = ""
	Do $ClassMethod(..#FIXTURE, "RememberDefault", .saved, ..#ITEM, "Enabled")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "PutDefault", ..#ITEM, "Enabled", 1), "the item's Enabled row is set to 1")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "NotRunningNow"), ..#ITEM, "an item whose row is 1 and which has no job is still reported")
	Do $$$AssertTrue($ClassMethod(..#FIXTURE, "StateOf", ..#ITEM) [ (..#ITEM_" row 1, runtime flag 1, jobs none"), "and the failure text says its row, its runtime flag and its jobs")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "RestoreDefaults", saved), "the row is put back")
}

/// The stub's alive jobs of an item: one until the production update has been asked for need times (the stop that was lost, then
/// found again), none after.
ClassMethod Jobs(item As %String) As %List
{
	Quit $Select($Get(^||TelegramParked("calls")) >= $Get(^||TelegramParked("need")): "", 1: $ListBuild(1))
}

/// The stub's production update: counts the times it is asked for.
ClassMethod Update()
{
	Set ^||TelegramParked("calls") = $Get(^||TelegramParked("calls")) + 1
}

/// Sets the stub: the job goes once the update has been asked for need times.
ClassMethod Stub(need As %Integer)
{
	Kill ^||TelegramParked
	Set ^||TelegramParked("need") = need
	Set ^||TelegramParked("calls") = 0
}

/// A job whose first stop was lost goes when the disable asks the production to update again.
Method TestStopAsksAgain()
{
	Do ..Stub(2)
	Set ok = $ClassMethod(..#CASE, "AwaitStop", "Stub", 8, 1, $ClassName(), .retries)
	Do $$$AssertTrue(ok, "a job that goes after two more updates is gone within the wait")
	Do $$$AssertEquals(retries, 2, "the production was asked to update twice")
	Kill ^||TelegramParked
}

/// A wait without a retry (the wait of the tests' stops) asks for no update, so a lost stop is not ended by it.
Method TestStopWithoutAskingStays()
{
	Do ..Stub(1)
	Set ok = $ClassMethod(..#CASE, "AwaitStop", "Stub", 2, 0, $ClassName(), .retries)
	Do $$$AssertNotTrue(ok, "without a retry the job is still there when the wait ends")
	Do $$$AssertEquals(retries, 0, "no update was asked for")
	Kill ^||TelegramParked
}

/// An item that cannot be stopped still fails at the bound, after the updates.
Method TestStopThatNeverEnds()
{
	Do ..Stub(1000)
	Set ok = $ClassMethod(..#CASE, "AwaitStop", "Stub", 5, 1, $ClassName(), .retries)
	Do $$$AssertNotTrue(ok, "a job that never goes fails the wait at the bound")
	Do $$$AssertTrue(retries >= 2, "and the production was asked to update meanwhile ("_retries_")")
	Kill ^||TelegramParked
}

/// A job that is already gone costs no update.
Method TestNoAskWhenGone()
{
	Do ..Stub(0)
	Set ok = $ClassMethod(..#CASE, "AwaitStop", "Stub", 3, 1, $ClassName(), .retries)
	Do $$$AssertTrue(ok, "an item with no job is gone at once")
	Do $$$AssertEquals(retries, 0, "no update was asked for")
	Kill ^||TelegramParked
}

/// The park waits longer than a test does, and updates again within the wait.
Method TestParkWaitsLonger()
{
	Do $$$AssertTrue($Parameter(..#BOTAPI, "PARKSECONDS") > $Parameter(..#CASE, "WAITJOB"), "the park waits longer than the "_$Parameter(..#CASE, "WAITJOB")_" s of a test")
	Do $$$AssertTrue(($Parameter(..#CASE, "RETRYSECONDS") > 0) && ($Parameter(..#CASE, "RETRYSECONDS") < $Parameter(..#CASE, "WAITJOB")), "and a disable asks again within a test's wait")
}

/// The wait against the real production: while TelegramIn runs, the wait to see it gone ends at the bound, the production update was asked
/// for and the failure text names the job. A park puts the stack back.
Method TestRealUpdateAndJobText()
{
	If '..Ready() Quit
	Set rows = ""
	Do $$$AssertStatusOK($ClassMethod(..#CASE, "Enable", "TelegramIn", .rows), "TelegramIn is enabled and has a job against the mock")
	Set text = $ClassMethod(..#CASE, "JobText", "TelegramIn")
	Do $$$AssertTrue(text [ "job ", "the text names the running job ("_text_")")
	Set ok = $ClassMethod(..#CASE, "AwaitStop", "TelegramIn", 3, 1, "", .retries, .why)
	Do $$$AssertNotTrue(ok, "a running item is not gone at the bound")
	Do $$$AssertTrue(retries >= 1, "and the real production was asked to update ("_retries_")")
	Do $$$AssertStatusOK($ClassMethod(..#BOTAPI, "Park"), "the stack is parked again")
	Do $$$AssertEquals($ClassMethod(..#CASE, "JobText", "TelegramIn"), "no job now", "the text says that a parked item has no job")
}

}
