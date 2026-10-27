/// Tests of the chat's answer to "is everything OK?" over the running production (Story 5.7; AD-28, AD-30, AD-31). THEY RUN IN THROWAWAY STACKS AND IN
/// CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case, and fresh: a real Tick acts on every check row of the namespace, so each test asserts only on
/// its own rows. A message goes through WebChatIn to the real Conversation, the real Decide and the real ChatAgent, against the CI mock (PointKeys). The
/// scenario checks-false-all-clear, with its countdown armed at 1, answers the triage request with tellnow, the Chat agent's first request with a call of
/// check_status and its second with a reply that says that everything is fine, that everything passed and "I looked at the Orders production for you."
///   - TestFailingOrdersInTheChat (AC 1): session S watches Orders (due a day ahead), three failing orders tagged with S's TraceRef are sent, a real Tick
///     leaves the watch without a run, a Tick at its due time records it as failed, and S asks (the row is not due again during the turn). The Turn is done and no fallback; its reply is exactly "I looked at the Orders production for you." (the guard removed both
///     all-clears); its CheckKey is checks.notEverything and its CheckRows one failed row with the row's Finding and LastRunAt; the done chat.message
///     carries the same; and the decision has one tool step, "Reading the check results", ok;
///   - TestAllClearOnlyFromCode (AC 2): the same message for a watch whose run is passed (and not due for a day, so that no real Tick changes it): the same reply, the key checks.allPassed and one passed row;
///   - TestNothingWatchedInTheChat (AC 2): the same message for a session that watches nothing: the same reply, the key checks.nothingWatched and no row.
/// Every reply is also checked against both lists of phrases of the guard (AssertNoAllClear). After each test the countdown is cleared, and the turns of the
/// run's sessions are removed with their decisions.
Class OcuTalon.Test.Checks.Turns Extends OcuTalon.Test.Watch.Case
{

Parameter SESSIONPREFIX = "zzchkturn";

/// The marker of the scenario, and the message that carries it.
Parameter MARKER = "checks-false-all-clear";

Parameter ASK = "Is everything OK? [[mock:checks-false-all-clear]]";

/// The reply that the guard leaves of the scenario's last text.
Parameter REPLY = "I looked at the Orders production for you.";

/// The longest to wait for a turn through the mock, in seconds.
Parameter WAIT = 90;

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Test.Contract.Mock).Arm(..#MARKER, "")
	Quit ##super(testname)
}

Method OnAfterAllTests() As %Status
{
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	Quit ##super()
}

Method TestFailingOrdersInTheChat()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("failing")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set ref = ..Watch(session)
	If '..Fail(3, trace) Quit
	Do ..WaitFailed(3)
	If ..RealTick() = "" Quit
	Set check = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
	Do check.%Reload()
	Do $$$AssertEquals(check.LastRunAt_"|"_check.Result, "|", "a real Tick does not run the watch: it is not due for a day")
	If ..Tick(check.NextDueAt) = "" Quit
	Do check.%Reload()
	Do $$$AssertEquals(check.Result, "failed", "the Tick at the due time recorded the watch as failed")
	Do $$$AssertEquals($Extract(check.Finding, 1, 14), "3 new failures", "with the finding of the three failures: "_check.Finding)
	Set row = ..Ask(session, "failing")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State_"|"_row.FallbackReason_"|"_row.ReplyCatalogKey, "done||", "the Turn is done and no fallback")
	Do $$$AssertEquals(row.ReplyText, ..#REPLY, "the reply is the scenario's last sentence alone: both all-clears are gone")
	Do ..AssertNoAllClear(row.ReplyText)
	Do $$$AssertEquals(row.CheckKey, "checks.notEverything", "the key is checks.notEverything")
	Set expected = [{"result": "failed", "entry": "Orders production", "finding": (check.Finding), "checkedAt": (check.LastRunAt)}]
	Do $$$AssertEquals(row.CheckRows, expected.%ToJSON(), "and the rows are one failed row of the Orders production, with the row's Finding and LastRunAt")
	Do ..AssertDone(session, row, expected)
	Do ..AssertToolStep(row)
}

Method TestAllClearOnlyFromCode()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("passing")
	Set ref = ..Watch(session)
	Set ranAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set check = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
	Set check.Result = "passed"
	Set check.Finding = ""
	Set check.LastRunAt = ranAt
	Set check.NextDueAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(ranAt, 86400)
	Do $$$AssertStatusOK(check.%Save(), "the watch has a recorded passed run")
	Set row = ..Ask(session, "passing")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State_"|"_row.FallbackReason_"|"_row.ReplyCatalogKey, "done||", "the Turn is done and no fallback")
	Do $$$AssertEquals(row.ReplyText, ..#REPLY, "the reply is the same filtered text")
	Do ..AssertNoAllClear(row.ReplyText)
	Do $$$AssertEquals(row.CheckKey, "checks.allPassed", "the key is checks.allPassed: the all-clear comes from the code")
	Set expected = [{"result": "passed", "entry": "Orders production", "finding": "", "checkedAt": (ranAt)}]
	Do $$$AssertEquals(row.CheckRows, expected.%ToJSON(), "with one passed row")
	Do ..AssertDone(session, row, expected)
	Do ..AssertToolStep(row)
}

Method TestNothingWatchedInTheChat()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("nothing")
	Set row = ..Ask(session, "nothing")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State_"|"_row.FallbackReason_"|"_row.ReplyCatalogKey, "done||", "the Turn is done and no fallback")
	Do $$$AssertEquals(row.ReplyText, ..#REPLY, "the reply is the same filtered text")
	Do ..AssertNoAllClear(row.ReplyText)
	Do $$$AssertEquals(row.CheckKey, "checks.nothingWatched", "the key is checks.nothingWatched")
	Do $$$AssertEquals(row.CheckRows, "", "with no row")
	Do ..AssertDone(session, row, [])
	Do ..AssertToolStep(row)
}

/// --- helpers ---
/// Arms the countdown of the scenario at 1, sends the message of the session through WebChatIn and gives the Turn once it is done (or "" with a failed
/// assertion). The ItemId of the Turn joins ItemIds, so that OnAfterOneTest removes its steps, decisions and usage.
Method Ask(session As %String, name As %String) As OcuTalon.Data.Turn [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).Arm(..#MARKER, 1), "the countdown of "_..#MARKER_" is armed at 1")
	Set clientId = "zzc"_..Number_name
	Do $$$AssertStatusOK(..Send(session, clientId, ..#ASK, .output), "the message is accepted by WebChatIn")
	Set row = ..WaitDone(session, clientId)
	If '$IsObject(row) || (row.State '= "done") {
		Do $$$AssertTrue(0, "the Turn is done within "_..#WAIT_" seconds")
		Quit ""
	}
	Set ..ItemIds = ..ItemIds_$ListBuild(row.ItemId)
	Quit row
}

/// Asserts that the text holds no phrase of the guard's two lists, ignoring case.
Method AssertNoAllClear(text As %String) [ Private ]
{
	Set phrases = $ListFromString($Parameter("OcuTalon.Checks.ReplyGuard", "RESERVED")_","_$Parameter("OcuTalon.Checks.ReplyGuard", "BANNED"))
	Set position = 0
	While $ListNext(phrases, position, phrase) {
		Do $$$AssertNotTrue($ZConvert(text, "L") [ $ZConvert(phrase, "L"), "the reply does not say '"_phrase_"'")
	}
}

/// Asserts that the done chat.message of the session's stream for the Turn carries its replyText, checkKey and checks.
Method AssertDone(session As %String, row As OcuTalon.Data.Turn, expected As %DynamicArray) [ Private ]
{
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "chat.message", 3, ..#WAIT)
	Set done = ""
	Set iterator = events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If (event.payload.ref = row.Ref) && (event.payload.state = "done") Set done = event.payload
	}
	Do $$$AssertTrue($IsObject(done), "the stream holds the done chat.message of the Turn")
	If '$IsObject(done) Quit
	Do $$$AssertEquals(done.replyText, row.ReplyText, "it carries the same replyText")
	Do $$$AssertEquals(done.checkKey, row.CheckKey, "and the same checkKey")
	Set actual = $Select(done.%IsDefined("checks"): done.checks, 1: [])
	Do $$$AssertEquals(actual.%Size(), expected.%Size(), "and the same number of checks")
	For i = 0:1:expected.%Size() - 1 {
		If i '< actual.%Size() Quit
		#; The payload leaves out an empty member, so a member that is absent reads as an empty string.
		For member = "result", "entry", "finding", "checkedAt" {
			Do $$$AssertEquals($Select(actual.%Get(i).%IsDefined(member): actual.%Get(i).%Get(member), 1: ""), expected.%Get(i).%Get(member), "check "_(i + 1)_" has the same "_member)
		}
	}
}

/// Asserts that the turn decision has exactly one tool step, "Reading the check results", ok.
Method AssertToolStep(row As OcuTalon.Data.Turn) [ Private ]
{
	Set steps = ##class(OcuTalon.Test.Agent.RunnerFixture).StepsOf(row.TurnDecisionRef)
	Set tools = 0
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		If step.kind '= "tool" Continue
		Set tools = tools + 1
		Do $$$AssertEquals(step.label_"|"_step.status, "Reading the check results|ok", "the tool step is Reading the check results, ok")
		Do $$$AssertTrue(step.summary [ "check_status", "and its summary names check_status: "_$Extract(step.summary, 1, 120))
	}
	Do $$$AssertEquals(tools, 1, "the turn decision has exactly one tool step")
}

}
