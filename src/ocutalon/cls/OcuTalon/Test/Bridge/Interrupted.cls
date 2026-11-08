/// Tests of the replays that an instance stop interrupted (Story 30.7; AD-5, AD-11, AD-16, AD-17, AD-31; NFR-13; DW-444, DW-582). THIS CLASS RUNS IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21): it saves approval rows that are executing, calls Approval.Reconcile on the running production, swaps Decide's
/// HostSinkClass for ProbeSink's shared mode, puts ZzReplayAgent behind ChatAgent and disables ChatAgent for a moment. Each live test is guarded by
/// RunnerFixture.ReadyReason. Every Ref a test saved is tracked under ^OcuTalonTest("Approval","refs") and every lock a job holds under
/// ^OcuTalonTest("Approval","job"), as Test.Bridge.Approval does, whose public helpers this class uses: before and after each test, and so after a
/// failed run too, Test.Bridge.Approval.Clean ends each tracked request and deletes its row, ChatAgent is enabled again and drained, and the sink,
/// the agent and the ApprovalRole row are put back.
///   - TestInterruptedReplayIsClosed (matrix 11): an executing tool_call row that no job holds the replay lock of is closed by Reconcile: failed,
///     Result interrupted, FinishedAt set, one approval.result, an Approval entry (finished, executing to failed, outcome interrupted) and an Action
///     entry interrupted, no tool request, the tool ran 0 times;
///   - TestLiveReplayIsLeftAlone (matrix 12): while another job holds the replay lock, Reconcile leaves the row executing and writes and fires nothing;
///     once the job lets go, the next Reconcile closes it;
///   - TestExecutingFixIsLeftAlone (matrix 13): an executing fix row, and an executing setting row, are untouched by Reconcile;
///   - TestHoldOfAnInterruptedReplayEnds (matrix 20, DW-582): the hold that waits on the replay of a tool_call whose runner is disabled ends within
///     10 seconds of the Reconcile that closes the row, long before Decide's timer, with one approval.result, one Approval entry, one Action entry
///     and the tool run 0 times; the request that was queued for the runner and is handled once the runner is enabled again is refused by
///     StartExecution and changes nothing.
Class OcuTalon.Test.Bridge.Interrupted Extends %UnitTest.TestCase
{

/// The class of the replay tests' tools: the source that the gate gives a held call of zz_replay_send.
Parameter TOOLCLASS = "OcuTalon.Test.Bridge.ZzReplayTool";

/// The runner item that the held calls name.
Parameter RUNNER = "ChatAgent";

/// The README account that answers (Install.Step.Users USER), the local install's real approver.
Parameter ANSWERER = "ocutalon";

/// The highest message header id when the run began.
Property Mark As %Integer;

/// The setting of Decide's HostSinkClass before a test put ProbeSink's shared mode, "" when none was put.
Property SavedSink As %DynamicObject;

/// The ApprovalRole row of Decide before the test touched it (RunnerFixture.RememberDefault).
Property Saved As %List;

/// 1 while the test has the runner item disabled.
Property RunnerDisabled As %Boolean [ InitialExpression = 0 ];

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
	Set ..Mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
	Kill ^||ZzProbeSink
	Set rows = ""
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RememberDefault(.rows, "Decide", "ApprovalRole")
	Set ..Saved = rows
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(##class(OcuTalon.Test.Agent.RunnerFixture).DefaultId("Decide", "ApprovalRole"))
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..RunnerDisabled {
		Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem(..#RUNNER, 1), ..#RUNNER_" is enabled again")
		Set ..RunnerDisabled = 0
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Drain(..#RUNNER), "and has handled the requests that were queued for it")
	}
	If $IsObject(..SavedSink) && ..SavedSink.%IsDefined("valueSet") {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).RestoreItemSetting("Decide", ..SavedSink), "Decide's HostSinkClass is put back")
	}
	Set ..SavedSink = ""
	Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..Saved), "the ApprovalRole row is put back")
	Kill ^||ZzProbeSink
	Quit $$$OK
}

/// Matrix 11 (DW-444): an executing tool_call row that no job holds the replay lock of is closed by Reconcile. The row is failed with the Result
/// interrupted and its FinishedAt set, approval.result fires once, the Approval entry says finished with the outcome interrupted, an Action entry
/// says interrupted, and no tool request is sent, so the call is not run again.
Method TestInterruptedReplayIsClosed()
{
	If '..Ready() Quit
	If '..UseSharedSink() Quit
	If '..UseReplayAgent() Quit
	Set ref = ..ReplayRow("executing")
	If ref = "" Quit
	Set owner = ..Prop(ref, "OwnerRef")
	Set ran = ##class(OcuTalon.Test.Bridge.ZzReplayTool).Ran("zz_replay_send")
	Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set before = ..RunnerRequests(ref)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Reconcile(), "Reconcile runs")
	Do $$$AssertEquals(..Prop(ref, "State")_"|"_..Prop(ref, "Result"), "failed|interrupted", "the row is failed with the Result interrupted")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Approval).JustNow(..Prop(ref, "FinishedAt")), "and its FinishedAt is set: "_..Prop(ref, "FinishedAt"))
	Set results = ##class(OcuTalon.Test.Bridge.Approval).WaitSinkCalls("approval.result", 1, 15)
	Do $$$AssertEquals(results.%Size(), 1, "approval.result fires once")
	If results.%Size() = 1 Do $$$AssertEquals(results.%Get(0).ownerRef_"|"_results.%Get(0).payload, owner_"|{""ref"":"""_ref_"""}", "owned by the row's OwnerRef, with only the Ref")
	Do ..AssertClosedEntries(audit, ref)
	Do $$$AssertEquals(..RunnerRequests(ref), before, "no tool request was sent, so the call did not run again")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.ZzReplayTool).Ran("zz_replay_send"), ran, "and the tool ran 0 times")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Reconcile(), "a second Reconcile runs")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SinkCalls("approval.result").%Size(), 1, "and fires nothing more")
}

/// Matrix 12 (DW-444): another job holds the replay lock of an executing tool_call, as a live replay does. Reconcile leaves the row executing and
/// writes no entry and fires no event; once the job releases the lock, the next Reconcile closes it.
Method TestLiveReplayIsLeftAlone()
{
	If '..Ready() Quit
	If '..UseSharedSink() Quit
	Set ref = ..FixtureRow("executing", "tool_call")
	If ref = "" Quit
	Set number = "j"_$Increment(^OcuTalonTest("Approval", "jobs"))
	Kill ^OcuTalonTest("Approval", "job", number)
	Set ^OcuTalonTest("Approval", "job", number, "spawned") = 1
	Job ##class(OcuTalon.Test.Bridge.Interrupted).HoldReplayLockInJob(number, ref, 60)
	Do ##class(OcuTalon.Test.Bridge.Approval).WaitNode($Name(^OcuTalonTest("Approval", "job", number, "locked")), 20)
	Do $$$AssertEquals($Get(^OcuTalonTest("Approval", "job", number, "locked")), 1, "a job holds the replay lock of the Ref")
	Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Reconcile(), "Reconcile runs")
	Do $$$AssertEquals(..Prop(ref, "State")_"|"_..Prop(ref, "Result")_"|"_..Prop(ref, "FinishedAt"), "executing||", "the row stays executing")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SinkCalls("approval.result").%Size(), 0, "no event fires")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(audit, "OcuTalon", "Approval", "Approval", ref).%Size(), 0, "no Approval entry names the Ref")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(audit, "OcuTalon", "Action", "Action", ref).%Size(), 0, "and no Action entry")
	Set ^OcuTalonTest("Approval", "job", number, "release") = 1
	Do ##class(OcuTalon.Test.Bridge.Approval).WaitNode($Name(^OcuTalonTest("Approval", "job", number, "done")), 20)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Reconcile(), "Reconcile runs again after the job released the lock")
	Do $$$AssertEquals(..Prop(ref, "State")_"|"_..Prop(ref, "Result"), "failed|interrupted", "and now closes the row")
	Do ..AssertClosedEntries(audit, ref)
}

/// Matrix 13 (DW-444): an executing fix row, and an executing setting row, are untouched by Reconcile (Fix.Run and SettingsOps close them).
Method TestExecutingFixIsLeftAlone()
{
	If '..Ready() Quit
	If '..UseSharedSink() Quit
	Set fix = ..FixtureRow("executing", "fix")
	Set setting = ..FixtureRow("executing", "setting")
	If (fix = "") || (setting = "") Quit
	Set fixText = ##class(OcuTalon.Test.Bridge.Approval).RowText(fix)
	Set settingText = ##class(OcuTalon.Test.Bridge.Approval).RowText(setting)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Reconcile(), "Reconcile runs")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.Approval).RowText(fix), fixText, "the executing fix row is unchanged")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.Approval).RowText(setting), settingText, "and so is the executing setting row")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SinkCalls("approval.result").%Size(), 0, "and no event fires")
}

/// Matrix 20 (DW-582): the hold of a replay that never got to run ends when Reconcile closes the row. The test approves a tool_call whose runner it
/// has disabled, so that the hold waits on its replay request (ChatAgent is disabled, and Decide waits for it); the test then calls StartExecution
/// (the crashed replay) and Reconcile. The hold ends within 10 seconds, before Decide has answered it, with one approval.result, one Approval entry
/// and one Action entry, and the tool ran 0 times. Once the runner is enabled again, the request that waited for it is refused by StartExecution:
/// still one approval.result, one Action entry, and the tool ran 0 times.
Method TestHoldOfAnInterruptedReplayEnds()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	If '..UseSharedSink() Quit
	If '..UseReplayAgent() Quit
	Set ran = ##class(OcuTalon.Test.Bridge.ZzReplayTool).Ran("zz_replay_send")
	Set ..RunnerDisabled = 1
	Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem(..#RUNNER, 0), ..#RUNNER_" is disabled")
	Set row = ##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow("tool_call", "zz_replay_send", "{}", ..#TOOLCLASS, ..#RUNNER)
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Set sc = ##class(OcuTalon.Bridge.Approval).Raise(row, .ref, ##class(OcuTalon.Test.Bridge.Approval).#SINK)
	If ref '= "" Set ^OcuTalonTest("Approval", "refs", ref) = ""
	Kill row
	Do $$$AssertStatusOK(sc, "the tool_call request is raised")
	If $$$ISERR(sc) Quit
	Set session = ##class(OcuTalon.Test.Bridge.Approval).HoldMessages(mark, ref).session
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Approval).WaitTask(ref, 10) '= "", "its task exists")
	Kill ^||ZzProbeSink
	Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(ref, "approve", "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner), "done", "Answer approves the held call: done")
	Do $$$AssertTrue(..WaitsOnReplay(ref, 20), "the hold waits on its replay request")
	Do $$$AssertEquals(..Prop(ref, "State"), "approved", "the row is still approved: the runner is disabled, so no replay started")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).StartExecution(ref), $$$OK, "StartExecution makes the row executing, as the replay that crashed did")
	Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).SinkCalls("approval.result").%Size()
	Set began = $ZHorolog
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Reconcile(), "Reconcile runs")
	Do $$$AssertEquals(..Prop(ref, "State")_"|"_..Prop(ref, "Result"), "failed|interrupted", "the row is failed with the Result interrupted")
	Set gone = ##class(OcuTalon.Test.Bridge.Approval).WaitHoldGone(ref, 10)
	Do $$$AssertEquals(gone, 1, "the hold ends within 10 seconds of Reconcile ("_$Number($ZHorolog - began, 1)_" seconds)")
	Do $$$AssertEquals(##class(Ens.Queue).GetCount(..#RUNNER), 1, "and while the replay request still waits on the disabled runner's queue, so neither the runner nor Decide's timer ended it")
	Do $$$AssertEquals(..DecideAnswers(session), 1, "the one response that the hold got is the deferred one")
	Set sent = ##class(OcuTalon.Test.Bridge.Approval).WaitSinkCalls("approval.result", results + 1, 15)
	Do $$$AssertEquals(sent.%Size(), results + 1, "one approval.result fires")
	Do ..AssertClosedEntries(audit, ref)
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.ZzReplayTool).Ran("zz_replay_send"), ran, "the tool ran 0 times")

	// the runner is enabled again: the request that waited for it is refused
	Set ..RunnerDisabled = 0
	Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem(..#RUNNER, 1), ..#RUNNER_" is enabled again")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Drain(..#RUNNER), "it handles the request that was queued for it")
	Do $$$AssertEquals(..Prop(ref, "State")_"|"_..Prop(ref, "Result"), "failed|interrupted", "the row is as Reconcile left it")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).LiveHold(ref), "", "and no hold came back")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SinkCalls("approval.result").%Size(), results + 1, "still one approval.result")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(audit, "OcuTalon", "Action", "Action", ref).%Size(), 1, "and one Action entry")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.ZzReplayTool).Ran("zz_replay_send"), ran, "the tool still ran 0 times")
}

/// The job body of TestLiveReplayIsLeftAlone: takes LOCK ^OcuTalon.Bridge.Replay(ref) as a live replay does, reports it, and keeps it until the
/// test sets release or the seconds pass.
ClassMethod HoldReplayLockInJob(number As %Integer, ref As %String, seconds As %Integer)
{
	Set run = $Name(^OcuTalonTest("Approval", "job", number))
	Try {
		Lock +^OcuTalon.Bridge.Replay(ref):10
		If $Test {
			Set @run@("locked") = 1
			Set deadline = $ZHorolog + seconds
			While '$Get(@run@("release")) && ($ZHorolog < deadline) {
				Hang 0.05
			}
			Lock -^OcuTalon.Bridge.Replay(ref)
		} Else {
			Set @run@("error") = "the lock was not taken"
		}
	} Catch exception {
		Set @run@("error") = exception.DisplayString()
	}
	Set @run@("done") = 1
}

/// Asserts that exactly one Approval entry that says finished (executing to failed, the outcome interrupted) and exactly one Action entry (interrupted)
/// name the Ref since the mark.
Method AssertClosedEntries(audit As %String, ref As %String)
{
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(audit, "OcuTalon", "Approval", "Approval", ref)
	Set finished = ""
	For i = 0:1:entries.%Size() - 1 {
		If entries.%Get(i).data.change = "finished" Set finished = finished _ $ListBuild(entries.%Get(i).data.change_"|"_entries.%Get(i).data.from_"|"_entries.%Get(i).data.to_"|"_entries.%Get(i).data.outcome)
	}
	Do $$$AssertEquals($ListLength(finished), 1, "one Approval entry that says finished carries the Ref")
	If $ListLength(finished) = 1 Do $$$AssertEquals($List(finished, 1), "finished|executing|failed|interrupted", "it is executing to failed, with the outcome interrupted")
	Set actions = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(audit, "OcuTalon", "Action", "Action", ref)
	Do $$$AssertEquals(actions.%Size(), 1, "one Action entry carries the Ref")
	If actions.%Size() = 1 Do $$$AssertEquals(actions.%Get(0).data.result_"|"_actions.%Get(0).data.approvalRef, "interrupted|"_ref, "and says interrupted")
}

/// 1 once the live hold of the Ref waits on a response with the completion key replay (polled up to the seconds).
ClassMethod WaitsOnReplay(ref As %String, seconds As %Integer) As %Boolean
{
	Set deadline = $ZHorolog + seconds
	Set waits = 0
	For {
		Set holdId = ##class(OcuTalon.Bridge.Approval).LiveHold(ref)
		Set hold = $Select(holdId = "": "", 1: ##class(OcuTalon.Bridge.Process.ApprovalHold).%OpenId(holdId))
		If $IsObject(hold) {
			For i = 1:1:hold.%MasterPendingResponses.Count() {
				If hold.%MasterPendingResponses.GetAt(i).CompletionKey = "replay" Set waits = 1
			}
		}
		If waits || ($ZHorolog >= deadline) Quit
		Hang 0.2
	}
	Quit waits
}

/// The number of responses that Decide has sent to an ApprovalHold in the session.
ClassMethod DecideAnswers(session As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = 'Decide' AND TargetConfigName = 'ApprovalHold' AND Type = 2", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// Saves an executing tool_call row for the replay tool and the runner ChatAgent (the source and runner of a call that a replay would send), so that a
/// second run of the call would move the runner's request count and the tool's counter. Tracked for the cleanup; returns its Ref.
Method ReplayRow(state As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow("tool_call", "zz_replay_send", "{}", ..#TOOLCLASS, ..#RUNNER)
	Set sc = ##class(OcuTalon.Test.Bridge.ApprovalRows).Save(row, state, 3600, ..#ANSWERER, .ref)
	If ref '= "" Set ^OcuTalonTest("Approval", "refs", ref) = ""
	Do $$$AssertStatusOK(sc, "the replay-tool row "_state_" is saved")
	Quit ref
}

/// Saves a fixture row of the kind directly in the state, with no hold and no task (RequiredRole OcuTalonUser, ExpiresAt an hour ahead), tracks it
/// and returns its Ref.
Method FixtureRow(state As %String, kind As %String) As %String [ Private ]
{
	Set sc = ##class(OcuTalon.Test.Bridge.ApprovalRows).Save(##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow(kind), state, 3600, ..#ANSWERER, .ref)
	If ref '= "" Set ^OcuTalonTest("Approval", "refs", ref) = ""
	Do $$$AssertStatusOK(sc, "the fixture row "_kind_" "_state_" is saved")
	Quit ref
}

/// The column of the approval row, read again from the database.
ClassMethod Prop(ref As %String, name As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Bridge.ApprovalRows).Prop(ref, name)
}

/// The number of requests of kind tool for the Ref that the runner has been sent since this run began.
Method RunnerRequests(ref As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Bridge.Approval).RunnerRequestsSince(..Mark, ref)
}

/// 1 when the production runs with every item; else the test fails with the reason.
Method Ready() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()
	If reason '= "" Do $$$AssertEquals(reason, "", "the production is ready")
	Quit reason = ""
}

/// The README account, the local install's real approver (Install.Step.Users); asserted to hold OcuTalonUser, else "".
Method Answerer() As %String [ Private ]
{
	Set user = ..#ANSWERER
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet(user, .roles)
	Set holds = $$$ISOK(sc) && ''$ListFind($ListFromString(roles), "OcuTalonUser")
	Do $$$AssertTrue(holds, "the answerer "_user_" holds OcuTalonUser")
	Quit $Select(holds: user, 1: "")
}

/// Decide's HostSinkClass is ProbeSink in its shared mode (Test.Bridge.Approval SharedSink), remembered for the cleanup. 1 when it is set.
Method UseSharedSink() As %Boolean [ Private ]
{
	Set sc = ##class(OcuTalon.Test.Bridge.Approval).SharedSink(.saved)
	Set ..SavedSink = saved
	Do $$$AssertStatusOK(sc, "Decide's HostSinkClass is ProbeSink in its shared mode")
	Quit $$$ISOK(sc)
}

/// ChatAgent runs ZzReplayAgent, and the runners' entries point at the CI mock key (Test.Bridge.Approval PointReplayAgent, put back by its Clean).
/// 1 when both are done.
Method UseReplayAgent() As %Boolean [ Private ]
{
	Set keys = ##class(OcuTalon.Test.Bridge.Approval).PointReplayAgent(.agent)
	Do $$$AssertStatusOK(keys, "the runners' entries point at the CI mock key")
	If $$$ISERR(keys) Quit 0
	Do $$$AssertStatusOK(agent, "ChatAgent runs ZzReplayAgent")
	Quit $$$ISOK(agent)
}

}
