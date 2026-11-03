Include Ensemble

/// Tests of the parked state of the Telegram items and of the readiness check that the runner restarts use (Story 12.9; AD-22, AD-23,
/// DW-591). They run in throwaways and in CI only (Rule 21), against the CI mock, on a stack whose start has been parked
/// (docker/tests/lib-live.sh live_park_telegram, ci/warm.sh up). No bot is called and no token is read or written.
///   - TestPark: from a TelegramIn that runs against the mock, BotApi.Park leaves the stack as a start with no token does: both Enabled
///     rows 0, no job of either item, the Telegram mark off, no kept offset, and an empty list of Bot API calls at the mock;
///   - TestReadinessFollowsTheRow: RunnerFixture.NotRunningNow, which WaitAllRun, Restart and ReadyReason wait on, leaves out an item whose
///     Enabled row is 0 even when the production's runtime flag of the item still says enabled (the state that kept the restarts of the
///     runners waiting for TelegramIn in CI's lane-a Channel shard), and still reports an item whose row is 1 and which has no job.
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

}
