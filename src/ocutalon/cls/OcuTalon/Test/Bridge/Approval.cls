/// Tests of Approval: Raise, the hold and its Reconcile (Story 3.4), and the five state methods, the hold's delivery and Msg.ApprovalOutcome
/// (Story 3.5; AD-5, AD-11, AD-15, AD-23, AD-26, AD-31). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it raises requests
/// through the running production, answers them as the README account, completes Workflow tasks as OcuTalonWorkflow, disables ApprovalStartIn,
/// ApprovalHold or OcuTalonApprovals for a moment, swaps Decide's HostSinkClass for ProbeSink's shared mode, restarts the production once, and writes
/// a System Default Settings row of Decide's ApprovalRole. Each live test is guarded by RunnerFixture.ReadyReason. The tests make no IRIS user or
/// role. Every Ref a test raised or saved is tracked under ^OcuTalonTest("Approval","refs"), every lock the test process holds under
/// ^OcuTalonTest("Approval","held") and every job under ^OcuTalonTest("Approval","job"): before and after each test, and so after a failed run
/// too, the locks are released, each job is waited for, each tracked request is ended (its open tasks are completed with Approve and the test waits
/// for its hold to end, so that no late response reaches a removed hold) and its row is deleted; the same cleanup enables the three items again and
/// deletes the fixture Workflow role of TestReconcileCancelsOnlyOrphans and its task. The settings row, Decide's HostSinkClass, the item state and
/// the Workflow objects that a test changed are put back. Reconcile's tests move a fixture row's RaisedAt and ExpiresAt directly and settle one.
/// Story 3.6: TestRaiseKeepsTheCallersJobIds (row 5a, DW-191) shows that Raise leaves the caller's session and current header ids as they were.
/// TestRaiseRefusesInATransaction (DW-187) shows that Raise itself refuses at $TLevel above 0 and leaves the caller's transaction open and uncommitted.
/// Its helpers Clean, TaskIds, WaitHoldSettled, Age, TrackOwner, WaitTask, HoldMessages, HoldRequests, HoldCount and StartsSince are public class methods, which
/// Test.Bridge.Gate reuses: TrackOwner tracks every row of an owner, so that the gate's held requests are ended and deleted by Clean.
/// Story 3.7: the five state methods write one Approval audit entry for every change they make, and these tests read it back from the IRIS audit
/// log through Test.Bridge.AuditLog (a mark taken just before the call, the Ref as the marker): TestAnswerApprovesAFix, TestAnswerRejects,
/// TestAnswerPastExpiry, TestTimerExpires, TestExpireDoesNotWaitForTheClock, TestCancel, TestOwnerRefKinds and TestEveryOtherTransitionIsRefused check the entry's
/// data (the Approval shape, the change, the states, the outcome, the target, the OwnerRef and the person it names), its description, its time and
/// the writing user; TestAnswerRefusals shows that a malformed sessionRef is not_allowed and that no refusal writes an entry;
/// TestFailedAuditNeverUndoesAChange shows that a write that fails (the event disabled) is warned, never undoes the change and never stops the event.
/// Every "no entry" check (AssertNoEntry) first writes an entry of its own window and finds it again with the same read, so that it cannot pass
/// because the read sees nothing; TestFailedAuditNeverUndoesAChange also shows that Record itself is refused while the event is disabled.
/// Every sessionRef that a test passes is a fresh Ref: Answer refuses anything else.
/// Story 3.5's tests, with the rows of its matrix:
///   - TestAnswerApprovesAFix (row 1): the answer is recorded with the given action, channel and user, the task is completed with Approve by
///     OcuTalonWorkflow, the sink hears one approval.answered with the row already approved, and the hold sends one approved outcome;
///   - TestAnswerRejects (row 2): a rejected fix sends one rejected outcome, a rejected tool_call with no ResultTarget sends none;
///   - TestApprovedToolCallRunsNothing (row 3): an approved tool_call sends no outcome and no request but the task and the timer; a rejected one
///     sends its outcome;
///   - TestTwoAnswersAtOnce (row 4): through the lock gate exactly one answer is done, the other is already_answered with the winner, and the task,
///     the one approval.answered and the one outcome are the winner's;
///   - TestAnswerRefusals (row 5): an unknown Ref is not_found; a user without the row's role, an empty or unknown user, a malformed action or
///     channel and a row raised for another role are not_allowed, and nothing changes; the role and input checks come before the state (an
///     approved row and a pending row past its expiry are not_allowed too), and a RequiredRole in another case is the same IRIS role;
///   - TestTimerExpires (row 6): the timer of a re-armed past request expires the row, sends one expired outcome from the new hold's session and
///     fires one approval.expired from the hold's job;
///   - TestAnswerPastExpiry (row 7): an answer past the expiry expires the row, leaves the task and sends no outcome, and the row can no longer be
///     started or cancelled;
///   - TestExpireDoesNotWaitForTheClock (row 8, DW-186): Expire expires a row whose expiry is still ahead;
///   - TestCancel (row 9): Cancel completes the task with status Cancelled, the hold ends with no outcome, and approval.cancelled fires once;
///   - TestEveryOtherTransitionIsRefused (row 10): every state and call pair is refused, with every column unchanged and no event, unless AD-11's
///     path allows it; an unknown Ref and a 600-character Ref are refused by the four status methods with an error that names the Ref, and Answer
///     gives not_found for the long one;
///   - TestHeldRowIsReadUnderTheLock (AD-11): Answer and StartExecution read the row under the lock even when the calling process holds it
///     open, so a stale copy cannot win;
///   - TestStartExecutionAtOnce (row 11): of two StartExecution calls through the gate exactly one succeeds;
///   - TestAnswerReArmed (row 12): an answer completes the new task of a re-armed request, and the outcome comes from the new hold's session;
///   - TestAnswerBeforeTheTaskExists (row 13): an answer waits for the task, completes it once it appears, and the outcome is sent;
///   - TestHoldActsOnlyOnTheRowsAnswer (row 14): a task completed directly while the row is pending ends the hold and sends nothing, and so does
///     a task completed with Approve on a row that shows rejected;
///   - TestTimerDeliversAnUndeliveredAnswer (row 15): the timer delivers an approved and a rejected answer whose task was never completed, and
///     the late approval is not started;
/// Story 3.4's tests, with the rows of its matrix:
///   - TestRaiseToolCall (rows 3 and 5): a tool_call request gives one pending row with the given fields, RequiredRole OcuTalonUser, RaisedAt now
///     and ExpiresAt exactly 24 hours later, a 22-character base64url Ref, and no other field; the three messages of the hold share one new
///     session whose SuperSession is the TraceRef; the sink got one approval.raised, with the OwnerRef and {"ref"}, at transaction level 0 and
///     with the row existing; the task of the hold has the actions Approve,Reject, the subject TASKSUBJECT plus the Ref, no UserName or Title, is
///     in OcuTalonApprovals unassigned with one worklist item for OcuTalonWorkflow; the timer asks 86,395 to 86,400 seconds and ^Ens.Alarm holds it;
///     one ApprovalHold waits for exactly the keys task and expiry;
///   - TestRaiseFix (row 4): the same for a fix request, with DryRun, IncidentRef, ResultTarget, FixKind, FixParameters and FixTargets kept and the tool fields empty;
///   - TestOwnerRefKinds: a request owned by the literal instance or eval (AD-2) is held and keeps its OwnerRef;
///   - TestCallerSession (row 6): the hold's messages are in the caller's session and SuperSession, from a bridge context and from Raise's arguments;
///     an argument wins over the context's value, and each of the two is resolved on its own (only a session, only a SuperSession);
///   - TestApprovalRole (row 7): RequiredRole is the ApprovalRole setting; an empty setting refuses Raise, which creates nothing;
///   - TestRefused (row 8): every refusal names its field, leaves ref empty, and makes no row, no hold and no sink call (a fix without a FixKind, with
///     FixParameters that are empty or not an object, or without FixTargets, and a tool_call with any of the three, included);
///   - TestLockHeld (row 9): a lock that another job holds gives an error that names it after about two seconds, and nothing is created;
///   - TestStartFails (row 10): with ApprovalStartIn disabled, Raise returns the director's error and nothing is left;
///   - TestStartTimesOut (row 10, a timeout): with ApprovalHold disabled, Raise returns ApprovalStartIn's timeout after about STARTSECONDS and
///     nothing is left; once the item is enabled again the hold takes the late start, refuses it and holds nothing;
///   - TestRestartKeepsTheHold (row 11): after a production restart and the Reconcile step the same hold, task and timer remain, nothing new starts,
///     and completing the task ends that hold;
///   - TestReconcileReArms (row 12): a hold that is gone gets a new one in a new session tagged with the TraceRef, timed from the row's ExpiresAt,
///     its orphaned task is discarded, the new task reaches the new hold, and a second Reconcile changes nothing;
///   - TestReconcilePastExpiry (row 13): a row past its expiry gets a hold whose timer asks 1 second, which expires the row and ends the hold and its task;
///   - TestReconcileLeavesSettledRows: a request whose row is no longer pending gets no hold, its orphaned task is still discarded, and a start
///     of it is refused by the hold;
///   - TestReconcileCancelsOnlyOrphans: Reconcile leaves an answered task and an open task of another Workflow role alone, and discards the task
///     of a live hold whose row is no longer pending;
///   - TestReconcileTriesEveryRow: with ApprovalStartIn disabled Reconcile's one error names every Ref and the orphaned tasks are still
///     discarded; once the item is enabled again, Reconcile re-arms every request (QA);
///   - TestHoldIsFrozen (row 14): ApprovalHold stores exactly Ref and declares exactly OnRequest and OnResponse, each one line that calls Approval.
Class OcuTalon.Test.Bridge.Approval Extends %UnitTest.TestCase
{

/// The host sink of the tests.
Parameter SINK = "OcuTalon.Test.Bridge.ProbeSink";

/// The fields that a request is given and that Raise must keep, in the order of Snapshot (the OwnerRef is the second, the TraceRef the third).
Parameter GIVENFIELDS = "Kind,OwnerRef,TraceRef,IncidentRef,ToolName,ToolArguments,ResultTarget,DryRun,FixKind,FixParameters,FixTargets";

/// The README account that answers (Install.Step.Users USER), the local install's real approver.
Parameter ANSWERER = "ocutalon";

/// The audit event of the Approval entries.
Parameter AUDITEVENT = "OcuTalon/Approval/Approval";

/// The run's number.
Property Number As %Integer;

/// The highest message header id when the run began: the outcomes of this run are the ones after it.
Property Mark As %Integer;

/// The setting of Decide's HostSinkClass before a test put ProbeSink's shared mode (RunnerFixture.UseItemSetting), "" when none was put.
Property SavedSink As %DynamicObject;

/// 1 while the test has OcuTalonApprovals disabled.
Property ApprovalsDisabled As %Boolean [ InitialExpression = 0 ];

/// The ApprovalRole row of Decide before the test touched it (RunnerFixture.RememberDefault).
Property Saved As %List;

/// 1 while the test has the audit event OcuTalon/Approval/Approval disabled.
Property AuditEventOff As %Boolean [ InitialExpression = 0 ];

/// 1 while the test has ApprovalStartIn disabled.
Property Disabled As %Boolean [ InitialExpression = 0 ];

/// 1 while the test has ApprovalHold disabled.
Property HoldDisabled As %Boolean [ InitialExpression = 0 ];

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("Approval", "n"))
	Set ..Mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ..Clean()
	Kill ^||ZzProbeSink
	Set rows = ""
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RememberDefault(.rows, "Decide", "ApprovalRole")
	Set ..Saved = rows
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(##class(OcuTalon.Test.Agent.RunnerFixture).DefaultId("Decide", "ApprovalRole"))
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..AuditEventOff {
		Do ..SetAuditEvent(1)
		Do $$$AssertEquals(..AuditEventState(), 1, "the audit event "_..#AUDITEVENT_" is enabled again")
		Set ..AuditEventOff = 0
	}
	If ..Disabled {
		Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem("ApprovalStartIn", 1), "ApprovalStartIn is enabled again")
		Set ..Disabled = 0
	}
	If ..HoldDisabled {
		Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem("ApprovalHold", 1), "ApprovalHold is enabled again")
		Set ..HoldDisabled = 0
	}
	If ..ApprovalsDisabled {
		Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem("OcuTalonApprovals", 1), "OcuTalonApprovals is enabled again")
		Set ..ApprovalsDisabled = 0
	}
	If $IsObject(..SavedSink) && ..SavedSink.%IsDefined("valueSet") {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).RestoreItemSetting("Decide", ..SavedSink), "Decide's HostSinkClass is put back")
	}
	Set ..SavedSink = ""
	Do ..Clean()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..Saved), "the ApprovalRole row is put back")
	Kill ^||ZzProbeSink
	Quit $$$OK
}

/// Rows 3 and 5: a tool_call request.
Method TestRaiseToolCall()
{
	If '..Ready() Quit
	Set row = ..NewRow("tool_call")
	Set given = ..Snapshot(row)
	Set rowsBefore = ..RowCount()
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Set sc = ..Raise(row, .ref)
	Do $$$AssertStatusOK(sc, "Raise is OK")
	Do $$$AssertTrue($Match(ref, "^[A-Za-z0-9_-]{22}\z"), "ref is 22 base64url characters: "_ref)
	Do $$$AssertEquals(..RowCount(), rowsBefore + 1, "one row was made")
	Set saved = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(saved), "the row has the Ref")
	If '$IsObject(saved) Quit
	Do $$$AssertEquals(saved.Ref, ref, "its Ref is ref")
	Do ..AssertGiven(saved, given, "tool_call")
	Do $$$AssertEquals(saved.State_"|"_saved.RequiredRole, "pending|OcuTalonUser", "it is pending and the required role is the default of the setting")
	Do $$$AssertTrue($Match(saved.RaisedAt, "^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z"), "RaisedAt has the form of a UTC time: "_saved.RaisedAt)
	Set age = ##class(OcuTalon.Bridge.Time).SecondsUntil(saved.RaisedAt)
	Do $$$AssertTrue((age <= 0) && (age >= -5), "RaisedAt is within 5 seconds of now: "_age)
	Do $$$AssertEquals(saved.ExpiresAt, ##class(OcuTalon.Bridge.Time).PlusSeconds(saved.RaisedAt, 86400), "ExpiresAt is exactly 24 hours after RaisedAt")
	Do $$$AssertEquals(saved.DryRun_"|"_saved.IncidentRef_"|"_saved.ResultTarget, "||", "DryRun, IncidentRef and ResultTarget are empty")
	Do $$$AssertEquals(saved.AnsweredAction_saved.AnsweredChannel_saved.AnsweredBy_saved.AnsweredAt_saved.Result_saved.FinishedAt, "", "the answer fields and the result fields are empty")

	Set messages = ..HoldMessages(mark, ref)
	Do $$$AssertTrue(messages.session > mark, "the hold's messages are in one new session: "_messages.session)
	Do $$$AssertEquals(messages.start.super_"|"_messages.task.super_"|"_messages.alarm.super, $ListGet(given, 3)_"|"_$ListGet(given, 3)_"|"_$ListGet(given, 3), "and carry the TraceRef as SuperSession")
	Do $$$AssertEquals(messages.task.session_"|"_messages.alarm.session, messages.session_"|"_messages.session, "the task and the timer are in that session")
	Do ..AssertSink(ref, $ListGet(given, 2), "the sink")

	// the hold (row 5)
	Set taskId = ..WaitTask(ref, 10)
	Do $$$AssertTrue(taskId '= "", "within 10 seconds the task exists: "_taskId)
	Set taskRequest = ##class(EnsLib.Workflow.TaskRequest).%OpenId(messages.task.bodyId)
	Do $$$AssertTrue($IsObject(taskRequest), "the TaskRequest is stored")
	If $IsObject(taskRequest) {
		Do $$$AssertEquals(taskRequest.%Actions, "Approve,Reject", "its actions are Approve and Reject")
		Do $$$AssertEquals(taskRequest.%Subject, ##class(OcuTalon.Bridge.Approval).#TASKSUBJECT_ref, "its subject is the constant and the Ref")
		Do $$$AssertEquals(taskRequest.%UserName_"|"_taskRequest.%Title_"|"_taskRequest.%Message_"|"_taskRequest.%Command, "|||", "it names no user, title, message or command")
	}
	If taskId '= "" {
		Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(taskId)
		Do $$$AssertEquals(task.%TaskStatus.Role.Name_"|"_task.%TaskStatus.AssignedTo_"|"_task.%TaskStatus.IsComplete, "OcuTalonApprovals||0", "the task is open and unassigned in the role")
		Do $$$AssertEquals(..WorklistUsers(taskId), "OcuTalonWorkflow", "its one worklist item is for OcuTalonWorkflow")
	}
	Set alarm = ##class(Ens.AlarmRequest).%OpenId(messages.alarm.bodyId)
	Do $$$AssertTrue($IsObject(alarm), "the AlarmRequest is stored")
	If $IsObject(alarm) {
		Set seconds = $Select(alarm.Timeout '= "": +alarm.Timeout, 1: +alarm.DurationInSeconds)
		Do $$$AssertTrue((seconds >= 86395) && (seconds <= 86400), "the timer asks 86,395 to 86,400 seconds: "_seconds)
		Do $$$AssertTrue(..AlarmEntry(messages.alarm.id, 10) '= "", "^Ens.Alarm holds its entry")
	}
	Set hold = ..Hold(ref)
	Do $$$AssertTrue($IsObject(hold), "one ApprovalHold is live for the Ref")
	Do $$$AssertEquals(..HoldCount(ref), 1, "and it is the only one")
	If $IsObject(hold) Do $$$AssertEquals(..Keys(hold), "expiry,task", "it waits for the keys task and expiry")
}

/// Row 4: a fix request.
Method TestRaiseFix()
{
	If '..Ready() Quit
	Set first = ..NewRow("tool_call")
	Set sc = ..Raise(first, .toolRef)
	Do $$$AssertStatusOK(sc, "a tool_call request is raised")
	Set row = ..NewRow("fix")
	Set given = ..Snapshot(row)
	Set rowsBefore = ..RowCount()
	Kill ^||ZzProbeSink
	Set sc = ..Raise(row, .ref)
	Do $$$AssertStatusOK(sc, "Raise of the fix request is OK")
	Do $$$AssertTrue($Match(ref, "^[A-Za-z0-9_-]{22}\z") && (ref '= toolRef), "ref is 22 base64url characters and differs from the other request's")
	Do $$$AssertEquals(..RowCount(), rowsBefore + 1, "one row was made")
	Set saved = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(saved), "the row has the Ref")
	If '$IsObject(saved) Quit
	Do ..AssertGiven(saved, given, "fix")
	Do $$$AssertEquals(saved.State_"|"_saved.RequiredRole, "pending|OcuTalonUser", "it is pending with the default required role")
	Do $$$AssertEquals(saved.ExpiresAt, ##class(OcuTalon.Bridge.Time).PlusSeconds(saved.RaisedAt, 86400), "ExpiresAt is exactly 24 hours after RaisedAt")
	Do $$$AssertEquals(saved.ToolName_"|"_saved.ToolArguments, "|", "ToolName and ToolArguments are empty")
	Do ..AssertSink(ref, $ListGet(given, 2), "the sink")
	Do $$$AssertTrue(..WaitTask(ref, 10) '= "", "the request is held: its task exists")
}

/// Row 6: the hold joins the caller's session, from a bridge context and from the arguments.
Method TestCallerSession()
{
	If '..Ready() Quit
	Set first = ..NewRow("tool_call")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Do $$$AssertStatusOK(..Raise(first, .ref1), "the first request is raised")
	Set messages = ..HoldMessages(mark, ref1)
	Set session = messages.session
	Do $$$AssertTrue(session > mark, "the first request has a session of its own: "_session)
	Set super = ##class(OcuTalon.Bridge.Ids).NewRef()

	// (a) a bridge context
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.ThreadSessionId = session
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, super), "a bridge context begins")
	Set second = ..NewRow("tool_call")
	Try {
		Set sc = ..Raise(second, .ref2)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertStatusOK(sc, "(a) Raise in the context is OK")
	Do ..AssertJoined(ref2, session, super, "(a)")

	// (b) the arguments
	Set third = ..NewRow("tool_call")
	Set super2 = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "(b) there is no context")
	Do $$$AssertStatusOK(..Raise(third, .ref3, session, super2), "(b) Raise with the session and the SuperSession is OK")
	Do ..AssertJoined(ref3, session, super2, "(b)")

	// (c) a context and different arguments: the arguments win
	Set fourth = ..NewRow("tool_call")
	Set mark2 = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Do $$$AssertStatusOK(..Raise(fourth, .ref4), "(c) a request with a session of its own is raised")
	Set session2 = ..HoldMessages(mark2, ref4).session
	Do $$$AssertTrue((session2 > mark2) && (session2 '= session), "(c) its session differs from the context's: "_session2)
	Set super3 = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set fifth = ..NewRow("tool_call")
	Set sc = ..RaiseInContext(fifth, .ref5, session, super, session2, super3)
	Do $$$AssertStatusOK(sc, "(c) Raise in the context with its own session and SuperSession is OK")
	Do ..AssertJoined(ref5, session2, super3, "(c)")

	// (d) a context and only the session: the SuperSession is the context's
	Set sixth = ..NewRow("tool_call")
	Set sc = ..RaiseInContext(sixth, .ref6, session, super, session2, "")
	Do $$$AssertStatusOK(sc, "(d) Raise in the context with only a session is OK")
	Do ..AssertJoined(ref6, session2, super, "(d)")

	// (e) a context and only the SuperSession: the session is the context's
	Set seventh = ..NewRow("tool_call")
	Set super4 = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = ..RaiseInContext(seventh, .ref7, session, super, "", super4)
	Do $$$AssertStatusOK(sc, "(e) Raise in the context with only a SuperSession is OK")
	Do ..AssertJoined(ref7, session, super4, "(e)")
}

/// An OwnerRef may be the literal instance or eval (AD-2): Raise holds such a request, keeps the OwnerRef and tells the sink. Its Cancel writes
/// one Approval entry that keeps the literal OwnerRef and names no session (the OwnerRef is not a Ref).
Method TestOwnerRefKinds()
{
	If '..Ready() Quit
	For owner = "instance", "eval" {
		Set row = ..NewRow($Select(owner = "instance": "tool_call", 1: "fix"))
		Set row.OwnerRef = owner
		Kill ^||ZzProbeSink
		Do $$$AssertStatusOK(..Raise(row, .ref), "Raise of a request owned by "_owner_" is OK")
		Set saved = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
		Do $$$AssertEquals($Select($IsObject(saved): saved.OwnerRef, 1: "<no row>"), owner, "its row keeps the OwnerRef "_owner)
		Do ..AssertSink(ref, owner, owner_": the sink")
		Do $$$AssertTrue(..WaitTask(ref, 10) '= "", owner_": the request is held")
		Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Cancel(ref, ..#SINK), owner_": Cancel is OK")
		Do ..AssertOneEntry(mark, ..Want(ref, row.Kind, "cancelled", "pending", "cancelled", "", $Select(row.Kind = "tool_call": row.ToolName, 1: row.IncidentRef), owner, $Username, "", "system"), owner_": the audit entry keeps the OwnerRef and names no session")
	}
}

/// Story 3.6, row 5a (DW-191): Raise runs ApprovalStartIn's round trip in the caller's job, which replaces the job's session and current header
/// ids, and puts both back: with %Ensemble("SessionId") and %Ensemble("CurrentHeaderId") set to known values they are unchanged afterwards, and
/// with both undefined they are still undefined, and a StartHold that fails keeps them the same way. The test kills both at the end.
Method TestRaiseKeepsTheCallersJobIds()
{
	If '..Ready() Quit
	Try {
		Set %Ensemble("SessionId") = 4711
		Set %Ensemble("CurrentHeaderId") = 4712
		Set sc = ..Raise(..NewRow("tool_call"), .ref)
		Do $$$AssertStatusOK(sc, "Raise with the ids of the job defined is OK")
		Set seen = $Get(%Ensemble("SessionId")) _ "|" _ $Get(%Ensemble("CurrentHeaderId"))
		Do $$$AssertTrue(seen = "4711|4712", "the job's session and current header ids are unchanged (got '" _ seen _ "')")
		Do $$$AssertTrue(..WaitTask(ref, 10) '= "", "and the request is held")
		Kill %Ensemble("SessionId"), %Ensemble("CurrentHeaderId")
		Set sc = ..Raise(..NewRow("tool_call"), .ref)
		Do $$$AssertStatusOK(sc, "Raise with both ids undefined is OK")
		Do $$$AssertEquals(($Data(%Ensemble("SessionId")) # 2) _ "|" _ ($Data(%Ensemble("CurrentHeaderId")) # 2), "0|0", "both are still undefined")
		Do $$$AssertTrue(..WaitTask(ref, 10) '= "", "and that request is held")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "Raise did not throw")
	}
	Kill %Ensemble("SessionId"), %Ensemble("CurrentHeaderId")

	// a start that fails (ApprovalStartIn refuses a message with no Ref) leaves the ids as they were too
	Try {
		Set %Ensemble("SessionId") = 4711
		Set %Ensemble("CurrentHeaderId") = 4712
		Set sc = ##class(OcuTalon.Bridge.Approval).StartHold("")
		Do $$$AssertStatusNotOK(sc, "a start with no Ref fails")
		Set seen = $Get(%Ensemble("SessionId")) _ "|" _ $Get(%Ensemble("CurrentHeaderId"))
		Do $$$AssertTrue(seen = "4711|4712", "after the failed start the ids are unchanged (got '" _ seen _ "')")
		Kill %Ensemble("SessionId"), %Ensemble("CurrentHeaderId")
		Set sc = ##class(OcuTalon.Bridge.Approval).StartHold("")
		Do $$$AssertStatusNotOK(sc, "a second failed start with both ids undefined fails")
		Do $$$AssertEquals(($Data(%Ensemble("SessionId")) # 2) _ "|" _ ($Data(%Ensemble("CurrentHeaderId")) # 2), "0|0", "and both are still undefined")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "StartHold did not throw")
	}
	Kill %Ensemble("SessionId"), %Ensemble("CurrentHeaderId")
}

/// DW-187: Raise inside an open transaction is refused before anything is written, with an error that names $TLevel and its value: ref is empty, no
/// row exists, no hold started and the sink got no call. The caller's transaction stays open at the same level with its own uncommitted write, which
/// the test's rollback then undoes: nothing of the caller's work was committed by a round trip through ApprovalStartIn (which commits every level).
/// Also refused at level 2.
Method TestRaiseRefusesInATransaction()
{
	If '..Ready() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Kill ^OcuTalonTest("Approval", "tx")
	Set outcome = ""
	For depth = 1, 2 {
		Set rowsBefore = ..RowCount()
		Set headerMark = $ClassMethod(fixture, "HeaderMark")
		Kill ^||ZzProbeSink
		Set ref = "unset"
		Set sc = ""
		Set level = ""
		Set written = ""
		Set rows = ""
		Set starts = ""
		For i = 1:1:depth {
			TSTART
		}
		Try {
			Set ^OcuTalonTest("Approval", "tx") = depth
			Set sc = ..Raise(..NewRow("tool_call"), .ref)
			Set level = $TLevel
			Set written = $Get(^OcuTalonTest("Approval", "tx"))
			Set rows = ..RowCount() - rowsBefore
			Set starts = ..StartsSince(headerMark)
		} Catch exception {
			Set outcome = outcome _ " " _ exception.DisplayString()
		}
		While $TLevel > 0 {
			TROLLBACK 1
		}
		Set label = "at level " _ depth _ ": "
		Do $$$AssertStatusNotOK(sc, label _ "Raise is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ("$TLevel is " _ depth), label _ "the error names $TLevel and its value: " _ $SYSTEM.Status.GetErrorText(sc))
		Do $$$AssertEquals(ref, "", label _ "ref is empty")
		Do $$$AssertEquals(level, depth, label _ "the caller's transaction is still open at its level")
		Do $$$AssertEquals(written, depth, label _ "with its own write in place")
		Do $$$AssertEquals(rows, 0, label _ "no row was written")
		Do $$$AssertEquals(starts, 0, label _ "no hold was started")
		Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, label _ "the sink got no call")
		Do $$$AssertEquals($Data(^OcuTalonTest("Approval", "tx")), 0, label _ "the rollback undid the caller's write: nothing was committed")
	}
	Do $$$AssertEquals(outcome, "", "Raise did not throw")
	Do $$$AssertEquals($TLevel, 0, "the test left no transaction open")
}

/// Raises the request inside a bridge context of the session and the SuperSession, with Raise's own session arguments, and ends the context.
Method RaiseInContext(row As OcuTalon.Bridge.Data.ApprovalRequest, Output ref As %String, contextSession As %Integer, contextSuper As %String, sessionId As %String, superSession As %String) As %Status [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.ThreadSessionId = contextSession
	Set sc = ##class(OcuTalon.Bridge.Context).Begin(request, contextSuper)
	If $$$ISERR(sc) Quit sc
	Try {
		Set sc = ..Raise(row, .ref, sessionId, superSession)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Quit sc
}

/// Row 7: RequiredRole comes from the ApprovalRole setting; an empty setting refuses Raise.
Method TestApprovalRole()
{
	If '..Ready() Quit
	Set role = "ZzApprover"_..Number
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", "Decide", "ApprovalRole", role), "the setting is "_role)
	Set row = ..NewRow("tool_call")
	Do $$$AssertStatusOK(..Raise(row, .ref), "Raise is OK")
	Set saved = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Do $$$AssertEquals($Select($IsObject(saved): saved.RequiredRole, 1: "<no row>"), role, "RequiredRole is the setting")

	Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", "Decide", "ApprovalRole", ""), "the setting is empty")
	Set empty = ..NewRow("tool_call")
	Set rowsBefore = ..RowCount()
	Set mark = $ClassMethod(fixture, "HeaderMark")
	Kill ^||ZzProbeSink
	Set sc = ..Raise(empty, .ref2)
	Do ..AssertRefused(sc, ref2, "ApprovalRole", "an empty setting")
	Do $$$AssertEquals(..RowCount(), rowsBefore, "no row was made")
	Do $$$AssertEquals(..StartsSince(mark), 0, "no hold was started")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and the sink got no call")
}

/// Row 8: each refusal alone names its field, leaves ref empty and makes no row, no hold and no sink call.
Method TestRefused()
{
	If '..Ready() Quit
	Set rowsBefore = ..RowCount()
	Set holdsBefore = ..HoldCount()
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Kill ^||ZzProbeSink
	Set ref = "zz"
	Set sc = ##class(OcuTalon.Bridge.Approval).Raise("", .ref, ..#SINK)
	Do ..AssertRefused(sc, ref, "request", "a request that is no object")
	Set ref = "zz"
	Set sc = ##class(OcuTalon.Bridge.Approval).Raise({"Kind": "tool_call"}, .ref, ..#SINK)
	Do ..AssertRefused(sc, ref, "request", "a request that is no ApprovalRequest")
	Set saved = ..NewRow("tool_call")
	Do $$$AssertStatusOK(saved.%Save(), "a saved row is made")
	Set savedId = saved.%Id()
	Set ref = "zz"
	Set sc = ##class(OcuTalon.Bridge.Approval).Raise(saved, .ref, ..#SINK)
	Do ..AssertRefused(sc, ref, "request", "a saved row")
	Do ##class(OcuTalon.Bridge.Data.ApprovalRequest).%DeleteId(savedId)

	Set bad = ..Refusals()
	Set position = 0
	While $ListNext(bad, position, case) {
		// each case: $ListBuild(kind, property, value, field)
		Set row = ..NewRow($List(case, 1))
		Set $Property(row, $List(case, 2)) = $List(case, 3)
		Set ref = "zz"
		Set sc = ##class(OcuTalon.Bridge.Approval).Raise(row, .ref, ..#SINK)
		Do ..AssertRefused(sc, ref, $List(case, 4), $List(case, 1)_" row with "_$List(case, 2)_" '"_$List(case, 3)_"'")
		Do $$$AssertEquals(row.%Id(), "", "the refused row is not saved")
	}
	Do $$$AssertEquals(..RowCount(), rowsBefore, "no row was made by any refusal")
	Do $$$AssertEquals(..HoldCount(), holdsBefore, "no hold was made")
	Do $$$AssertEquals(..StartsSince(mark), 0, "no hold was started")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and the sink got no call")
}

/// Row 9: another job holds LOCK ^OcuTalon.Bridge.Approval, so Raise waits about LOCKSECONDS and returns an error that names the lock.
Method TestLockHeld()
{
	If '..Ready() Quit
	Set run = $Name(^OcuTalonTest("Approval", "job", ..Number))
	Kill @run
	Set rowsBefore = ..RowCount()
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Kill ^||ZzProbeSink
	Job ##class(OcuTalon.Test.Bridge.Approval).HoldLockInJob(..Number, 60)
	Do ..WaitNode($Name(@run@("locked")), 20)
	Do $$$AssertEquals($Get(@run@("locked")), 1, "the other job holds the lock")
	If '$Get(@run@("locked")) {
		Set @run@("release") = 1
		Quit
	}
	Set row = ..NewRow("tool_call")
	Set begun = $ZHorolog
	Set sc = ..Raise(row, .ref)
	Set waited = $ZHorolog - begun
	Set @run@("release") = 1
	Do ..WaitNode($Name(@run@("done")), 20)
	Do $$$AssertStatusNotOK(sc, "Raise fails")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "^OcuTalon.Bridge.Approval", "the error names the lock: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(ref, "", "ref is empty")
	Do $$$AssertTrue((waited >= 1.5) && (waited < 8), "after about the lock's 2 seconds: "_waited)
	Do $$$AssertEquals(..RowCount(), rowsBefore, "no row was made")
	Do $$$AssertEquals(..StartsSince(mark), 0, "no hold was started")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and the sink got no call")
	Do $$$AssertEquals($Get(@run@("error")), "", "the other job ran without an error")
	Kill @run
}

/// Row 10: with ApprovalStartIn disabled, Raise returns the director's error, and no row, hold or sink call is left.
Method TestStartFails()
{
	If '..Ready() Quit
	Set rowsBefore = ..RowCount()
	Set holdsBefore = ..HoldCount()
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Kill ^||ZzProbeSink
	Set ..Disabled = 1
	Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem("ApprovalStartIn", 0), "ApprovalStartIn is disabled")
	Set expected = ##class(Ens.Director).CreateBusinessService("ApprovalStartIn", .service)
	Do $$$AssertStatusNotOK(expected, "the director refuses the disabled item")
	Set row = ..NewRow("tool_call")
	Set sc = ..Raise(row, .ref)
	Do $$$AssertStatusNotOK(sc, "Raise fails")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ $SYSTEM.Status.GetErrorText(expected), "with the director's error: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(ref, "", "ref is empty")
	Do $$$AssertEquals(..RowCount(), rowsBefore, "no row is left")
	Do $$$AssertEquals(..HoldCount(), holdsBefore, "no hold is left")
	Do $$$AssertEquals(..StartsSince(mark), 0, "no hold was started")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and the sink got no call")
	Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem("ApprovalStartIn", 1), "ApprovalStartIn is enabled again")
	Set ..Disabled = 0
}

/// Row 10, a timeout: with ApprovalHold disabled the start waits in its queue, so Raise returns ApprovalStartIn's timeout after about
/// STARTSECONDS, and no row, live hold or sink call is left. Once the item is enabled again, the hold takes the late start, refuses it
/// (there is no row) and holds nothing.
Method TestStartTimesOut()
{
	If '..Ready() Quit
	Set rowsBefore = ..RowCount()
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Kill ^||ZzProbeSink
	Set ..HoldDisabled = 1
	Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem("ApprovalHold", 0), "ApprovalHold is disabled")
	Set row = ..NewRow("tool_call")
	Set begun = $ZHorolog
	Set sc = ..Raise(row, .ref)
	Set waited = $ZHorolog - begun
	Do $$$AssertStatusNotOK(sc, "Raise fails")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "did not answer", "with ApprovalStartIn's timeout: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertTrue((waited >= 9) && (waited < 30), "after about STARTSECONDS: "_waited)
	Do $$$AssertEquals(ref, "", "ref is empty")
	Do $$$AssertEquals(..RowCount(), rowsBefore, "no row is left")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and the sink got no call")
	Set late = ..StartRef(mark)
	Do $$$AssertTrue(late '= "", "the start waits in ApprovalHold's queue: "_late)
	If late '= "" Set ^OcuTalonTest("Approval", "refs", late) = ""
	Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem("ApprovalHold", 1), "ApprovalHold is enabled again")
	Set ..HoldDisabled = 0
	Do $$$AssertEquals(..WaitStartDone(mark, 15), 1, "the hold takes the late start")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).LiveHold(late), "", "and holds nothing: no hold is live")
	Do $$$AssertEquals(..TaskCount(late), 0, "and no task was sent")
}

/// Row 11: the production restarts and the Reconcile step runs; the hold, its task and its timer are the same, and the answer reaches it.
Method TestRestartKeepsTheHold()
{
	If '..Ready() Quit
	Set row = ..NewRow("tool_call")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Do $$$AssertStatusOK(..Raise(row, .ref), "Raise is OK")
	Set taskId = ..WaitTask(ref, 10)
	Do $$$AssertTrue(taskId '= "", "the task exists: "_taskId)
	Set messages = ..HoldMessages(mark, ref)
	Set holdId = ##class(OcuTalon.Bridge.Approval).LiveHold(ref)
	Set alarmBefore = ..AlarmEntry(messages.alarm.id, 10)
	Do $$$AssertTrue((holdId '= "") && (alarmBefore '= ""), "the hold and its alarm entry are there before the restart")

	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).Start(), "the production restarts")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Reconcile).Run(), "the Reconcile step runs")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).LiveHold(ref), holdId, "the same ApprovalHold is live")
	Do $$$AssertEquals(..HoldCount(ref), 1, "and it is the only one with the Ref")
	Do $$$AssertEquals(..OpenTasks(ref), taskId, "its task is the same open task")
	Set alarmAfter = ..AlarmEntry(messages.alarm.id, 10)
	Do $$$AssertEquals($ListGet(alarmAfter, 1)_"|"_$ListGet(alarmAfter, 2), $ListGet(alarmBefore, 1)_"|"_$ListGet(alarmBefore, 2), "its ^Ens.Alarm entry and wake time are unchanged")
	Set hold = ##class(OcuTalon.Bridge.Approval).LiveHold(ref)
	If hold '= "" Do $$$AssertEquals(..Keys(##class(OcuTalon.Bridge.Process.ApprovalHold).%OpenId(hold)), "expiry,task", "it still waits for both keys")

	Do $$$AssertStatusOK(..Complete(taskId), "the task is completed")
	Do $$$AssertEquals(..WaitHoldGone(ref, 15), 1, "the TaskResponse reaches that hold: its key task is gone and the hold ends")
}

/// Row 12: the hold is gone; Reconcile cancels the orphaned task and starts a new hold timed from the row's ExpiresAt.
Method TestReconcileReArms()
{
	If '..Ready() Quit
	Set row = ..NewRow("tool_call")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Do $$$AssertStatusOK(..Raise(row, .ref), "Raise is OK")
	Set firstSession = ..HoldMessages(mark, ref).session
	Set oldTask = ..WaitTask(ref, 10)
	Set oldHold = ##class(OcuTalon.Bridge.Approval).LiveHold(ref)
	Do $$$AssertTrue((oldTask '= "") && (oldHold '= "") && (firstSession '= ""), "the first hold, its session and its task exist")
	Do ..Age(ref, 82800, 3600)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.ApprovalHold).%DeleteId(oldHold), "the hold instance is deleted")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).LiveHold(ref), "", "no hold is live")

	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Reconcile).Run(), "the Reconcile step runs")
	Set old = ##class(EnsLib.Workflow.TaskResponse).%OpenId(oldTask)
	Do $$$AssertEquals(old.%TaskStatus.IsComplete_"|"_..WorklistUsers(oldTask), "1|", "the orphaned task is discarded: it is complete and has no worklist item")
	Set newHold = ##class(OcuTalon.Bridge.Approval).LiveHold(ref)
	Do $$$AssertTrue((newHold '= "") && (newHold '= oldHold), "a new ApprovalHold is live: "_newHold)
	Do $$$AssertEquals(..HoldCount(ref), 1, "and it is the only ApprovalHold with the Ref")
	Set newTask = ..WaitTask(ref, 10)
	Do $$$AssertTrue((newTask '= "") && (newTask '= oldTask), "with a new open task: "_newTask)
	Set hold = ##class(OcuTalon.Bridge.Process.ApprovalHold).%OpenId(newHold)
	If $IsObject(hold) {
		Do $$$AssertEquals(hold.%SuperSession, row.TraceRef, "its SuperSession is the TraceRef")
		Do $$$AssertTrue((hold.%SessionId > 0) && (hold.%SessionId '= firstSession), "in a new session of its own: "_hold.%SessionId_", not "_firstSession)
		Do $$$AssertEquals(..Keys(hold), "expiry,task", "it waits for the keys task and expiry")
		Set seconds = ..TimerSeconds(hold.%SessionId)
		Do $$$AssertTrue((seconds >= 3595) && (seconds <= 3600), "its timer asks 3,595 to 3,600 seconds: "_seconds)
		Set sessionOfTask = ..TaskSession(newTask)
		Do $$$AssertEquals(sessionOfTask, hold.%SessionId, "the task is in the hold's session")
	}
	Do $$$AssertEquals(..WorklistUsers(newTask), "OcuTalonWorkflow", "the new task has one worklist item, for OcuTalonWorkflow")

	// idempotent
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Reconcile).Run(), "the Reconcile step runs again")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).LiveHold(ref), newHold, "the second run starts no hold")
	Do $$$AssertEquals(..OpenTasks(ref), newTask, "and cancels no task")
	Do $$$AssertEquals(..TaskCount(ref), 2, "the request has the discarded task and the new one")

	Do $$$AssertStatusOK(..Complete(newTask), "the new task is completed")
	Do $$$AssertEquals(..WaitHoldGone(ref, 15), 1, "its response reaches the new hold, which ends")
}

/// Row 13: a request past its expiry gets a hold whose timer asks 1 second, and the hold and its task end when it fires.
Method TestReconcilePastExpiry()
{
	If '..Ready() Quit
	Set row = ..NewRow("tool_call")
	Do $$$AssertStatusOK(..Raise(row, .ref), "Raise is OK")
	Kill row
	Set oldTask = ..WaitTask(ref, 10)
	Set oldHold = ##class(OcuTalon.Bridge.Approval).LiveHold(ref)
	Do $$$AssertTrue((oldTask '= "") && (oldHold '= ""), "the first hold and its task exist")
	Do ..Age(ref, 86460, -60)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.ApprovalHold).%DeleteId(oldHold), "the hold instance is deleted")

	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Reconcile).Run(), "the Reconcile step runs")
	Set messages = ..HoldMessages(mark, ref)
	Set alarm = ##class(Ens.AlarmRequest).%OpenId(messages.alarm.bodyId)
	Do $$$AssertTrue($IsObject(alarm), "the new hold's AlarmRequest is stored")
	If $IsObject(alarm) Do $$$AssertEquals($Select(alarm.Timeout '= "": +alarm.Timeout, 1: +alarm.DurationInSeconds), 1, "the timer asks 1 second")
	Do $$$AssertEquals(..WaitHoldGone(ref, 15), 1, "once it fires the hold has ended")
	Do $$$AssertEquals(..WaitState(ref, "expired", 15), "expired", "the row has expired")
	Do $$$AssertEquals(..OpenTasks(ref), "", "and its task is no longer open")
	Set taskId = ..TaskIds(ref)
	Do $$$AssertEquals($ListLength(taskId), 2, "the request has the discarded task and the cancelled one")
	Set position = 0
	While $ListNext(taskId, position, id) {
		Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(id)
		Do $$$AssertEquals(task.%TaskStatus.IsComplete_"|"_..WorklistUsers(id), "1|", "task "_id_" is complete and has no worklist item")
	}
}

/// Reconcile re-arms only a pending request: a request whose row is no longer pending gets no hold, and its orphaned task is still discarded.
Method TestReconcileLeavesSettledRows()
{
	If '..Ready() Quit
	Set row = ..NewRow("tool_call")
	Do $$$AssertStatusOK(..Raise(row, .ref), "Raise is OK")
	Set oldTask = ..WaitTask(ref, 10)
	Set oldHold = ##class(OcuTalon.Bridge.Approval).LiveHold(ref)
	Do $$$AssertTrue((oldTask '= "") && (oldHold '= ""), "the hold and its task exist")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.ApprovalHold).%DeleteId(oldHold), "the hold instance is deleted")
	Set saved = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Set saved.State = "approved"
	Do $$$AssertStatusOK(saved.%Save(), "the row is settled (approved)")

	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Reconcile).Run(), "the Reconcile step runs")
	Set old = ##class(EnsLib.Workflow.TaskResponse).%OpenId(oldTask)
	Do $$$AssertEquals(old.%TaskStatus.IsComplete_"|"_..WorklistUsers(oldTask), "1|", "the orphaned task is discarded")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).LiveHold(ref), "", "no hold is live for the settled request")
	Do $$$AssertEquals(..StartsSince(mark), 0, "no hold was started")
	Do $$$AssertEquals(..HoldCount(ref), 0, "no ApprovalHold instance has the Ref")
	Do $$$AssertEquals(..OpenTasks(ref), "", "and the request has no open task")
	Set sc = ##class(OcuTalon.Bridge.Approval).StartHold(ref)
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ (ref_" is approved, not pending"), "a start of the settled request is refused by the hold: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).LiveHold(ref)_"|"_..OpenTasks(ref), "|", "and holds nothing")
}

/// Reconcile cancels only orphaned tasks of its own role: an answered task keeps its status and completion time, an open task of another
/// Workflow role stays open, and the task of a live hold whose row is no longer pending is discarded.
Method TestReconcileCancelsOnlyOrphans()
{
	If '..Ready() Quit
	Set answered = ..NewRow("tool_call")
	Do $$$AssertStatusOK(..Raise(answered, .ref1), "the first request is raised")
	Set task1 = ..WaitTask(ref1, 10)
	Do $$$AssertStatusOK(..Complete(task1), "its task is answered")
	Do $$$AssertEquals(..WaitHoldGone(ref1, 15), 1, "and its hold ends")
	Do $$$AssertStatusOK(..Settle(ref1), "its row is settled")
	Set before1 = ..TaskState(task1)
	Set held = ..NewRow("tool_call")
	Do $$$AssertStatusOK(..Raise(held, .ref2), "the second request is raised")
	Set task2 = ..WaitTask(ref2, 10)
	Set hold2 = ##class(OcuTalon.Bridge.Approval).LiveHold(ref2)
	Do $$$AssertTrue((task2 '= "") && (hold2 '= ""), "its hold and task exist")
	Do $$$AssertStatusOK(..Settle(ref2), "its row is settled while its hold is live")
	Set other = ..OtherRoleTask()
	Do $$$AssertTrue(other '= "", "an open task of another Workflow role exists")

	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Reconcile(), "Reconcile runs")
	Do $$$AssertEquals(..TaskState(task1), before1, "the answered task keeps its status and completion time")
	Do $$$AssertEquals(..TaskState(other), "|0||", "the other role's task is still open")
	Set state2 = ..TaskState(task2)
	Do $$$AssertEquals($Piece(state2, "|", 2)_"|"_$Piece(state2, "|", 4), "1|", "the task of the live hold of a settled row is discarded: "_state2)
	Do ##class(OcuTalon.Bridge.Process.ApprovalHold).%DeleteId(hold2)
	Do ..RemoveOther()
}

/// Reconcile tries every task and every row, even when a start fails: with ApprovalStartIn disabled it returns one error that names each Ref,
/// still discards the orphaned tasks, and a run once the item is enabled again re-arms both requests.
Method TestReconcileTriesEveryRow()
{
	If '..Ready() Quit
	For number = 1:1:2 {
		Set row = ..NewRow("tool_call")
		Do $$$AssertStatusOK(..Raise(row, .ref), "request "_number_" is raised")
		Set refs(number) = ref
		Set task(number) = ..WaitTask(ref, 10)
		Set holdId = ##class(OcuTalon.Bridge.Approval).LiveHold(ref)
		Do $$$AssertTrue((task(number) '= "") && (holdId '= ""), "request "_number_" has a hold and a task")
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.ApprovalHold).%DeleteId(holdId), "its hold instance is deleted")
	}
	Set ..Disabled = 1
	Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem("ApprovalStartIn", 0), "ApprovalStartIn is disabled")
	Set sc = ##class(OcuTalon.Bridge.Approval).Reconcile()
	Do $$$AssertStatusNotOK(sc, "Reconcile reports the failed starts")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ refs(1)) && (text [ refs(2)), "its one error names both Refs: "_text)
	For number = 1:1:2 {
		Do $$$AssertEquals(..OpenTasks(refs(number)), "", "the orphaned task of request "_number_" is discarded in spite of the failure")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).LiveHold(refs(number)), "", "request "_number_" has no hold yet")
	}
	Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem("ApprovalStartIn", 1), "ApprovalStartIn is enabled again")
	Set ..Disabled = 0
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Reconcile(), "Reconcile is OK now")
	For number = 1:1:2 {
		Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).LiveHold(refs(number)) '= "", "request "_number_" has a live hold again")
		Do $$$AssertTrue(..WaitTask(refs(number), 10) '= "", "and an open task")
	}
}

/// Row 14: ApprovalHold stores exactly Ref and declares exactly OnRequest and OnResponse, each one line that calls OcuTalon.Bridge.Approval.
Method TestHoldIsFrozen()
{
	Set class = "OcuTalon.Bridge.Process.ApprovalHold"
	Set properties = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.PropertyDefinition WHERE parent = ? ORDER BY Name", class)
	While result.%Next() {
		Set properties = properties _ $Select(properties = "": "", 1: ",") _ result.%GetData(1)
	}
	Do $$$AssertEquals(properties, "Ref", "its own properties are exactly Ref")
	Set methods = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.MethodDefinition WHERE parent = ? ORDER BY Name", class)
	While result.%Next() {
		Set methods = methods _ $Select(methods = "": "", 1: ",") _ result.%GetData(1)
	}
	Do $$$AssertEquals(methods, "OnRequest,OnResponse", "its own methods are exactly OnRequest and OnResponse")
	For name = "OnRequest", "OnResponse" {
		Set method = ##class(%Dictionary.MethodDefinition).%OpenId(class_"||"_name)
		Set lines = 0
		Set calls = 0
		If $IsObject(method) {
			Do method.Implementation.Rewind()
			While 'method.Implementation.AtEnd {
				Set line = method.Implementation.ReadLine()
				If $ZStrip(line, "<>W") = "" Continue
				Set lines = lines + 1
				If line [ "##class(OcuTalon.Bridge.Approval)" Set calls = calls + 1
			}
		}
		Do $$$AssertEquals(lines_"|"_calls, "1|1", name_" is one line that calls OcuTalon.Bridge.Approval")
	}
}

/// Row 1: Answer approves a fix: the answer is recorded with the given channel and user, the task is completed as OcuTalonWorkflow with Approve, the
/// sink hears approval.answered once with the row already approved, and the hold sends one approved outcome.
Method TestAnswerApprovesAFix()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	Set info = ..RaiseHeld("fix")
	If '$IsObject(info) Quit
	Set ref = info.ref
	Set sessionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set result = ##class(OcuTalon.Bridge.Approval).Answer(ref, "approve", "web", user, sessionRef, .winner, ..#SINK)
	Do $$$AssertEquals(result, "done", "Answer returns done")
	Do ..AssertOneEntry(mark, ..Want(ref, "fix", "answered", "pending", "approved", "approved", info.incident, info.owner, user, sessionRef, "web"), "the audit entry")
	Do $$$AssertEquals(winner.%ToJSON(), "{}", "with no winner")
	Do $$$AssertEquals(..Prop(ref, "State")_"|"_..Prop(ref, "AnsweredAction")_"|"_..Prop(ref, "AnsweredChannel")_"|"_..Prop(ref, "AnsweredBy"), "approved|approve|web|"_user, "the row is approved with the action, channel and user")
	Do $$$AssertTrue(..JustNow(..Prop(ref, "AnsweredAt")), "AnsweredAt is a time within 5 seconds of now: "_..Prop(ref, "AnsweredAt"))
	Do $$$AssertEquals(..TaskFacts(info.task), "Approve|OcuTalonWorkflow|1|", "the task is complete with Approve by OcuTalonWorkflow and has no worklist item")
	Do $$$AssertEquals(..TaskCount(ref), 1, "and it is the request's only task")
	Do ..AssertEvents("approval.answered", "the sink")
	Do ..AssertEvent(1, "approval.answered", info.owner, ref, "approved", "the sink")
	Do $$$AssertEquals(..WaitHoldGone(ref, 15), 1, "the hold ends")
	Do ..AssertOneOutcome(ref, "approved", info, info.session, "the outcome")
}

/// Row 2: a rejected fix sends one rejected outcome; a rejected tool_call with no ResultTarget ends its hold and sends none.
Method TestAnswerRejects()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	Set fix = ..RaiseHeld("fix")
	If '$IsObject(fix) Quit
	Set fixSession = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(fix.ref, "reject", "web", user, fixSession, .winner, ..#SINK), "done", "(a) Answer rejects the fix: done")
	Do ..AssertOneEntry(mark, ..Want(fix.ref, "fix", "answered", "pending", "rejected", "rejected", fix.incident, fix.owner, user, fixSession, "web"), "(a) the audit entry")
	Do $$$AssertEquals(..Prop(fix.ref, "State"), "rejected", "(a) the row is rejected")
	Do $$$AssertEquals(..WaitHoldGone(fix.ref, 15), 1, "(a) the hold ends")
	Do ..AssertOneOutcome(fix.ref, "rejected", fix, fix.session, "(a) the outcome")

	Set tool = ..RaiseHeld("tool_call")
	If '$IsObject(tool) Quit
	Set toolSession = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(tool.ref, "reject", "web", user, toolSession, .winner, ..#SINK), "done", "(b) Answer rejects the tool call: done")
	Do ..AssertOneEntry(mark, ..Want(tool.ref, "tool_call", "answered", "pending", "rejected", "rejected", ..Prop(tool.ref, "ToolName"), tool.owner, user, toolSession, "web"), "(b) the audit entry: its target is the ToolName")
	Do $$$AssertEquals(..Prop(tool.ref, "State"), "rejected", "(b) the row is rejected")
	Do $$$AssertEquals(..WaitHoldGone(tool.ref, 15), 1, "(b) the hold ends")
	Do $$$AssertTrue(..WaitHoldSettled(tool.ref, tool.session, 15), "(b) and its OnResponse has returned")
	Do $$$AssertEquals(..Outcomes(tool.ref).%Size(), 0, "(b) no outcome is sent: the row has no ResultTarget")
}

/// Row 3: an approved tool_call runs nothing and sends nothing (the replay is Story 30.3's), also with a ResultTarget; a rejected one sends its outcome.
Method TestApprovedToolCallRunsNothing()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	Set first = ..RaiseHeld("tool_call", "IncidentManager")
	If '$IsObject(first) Quit
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(first.ref, "approve", "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK), "done", "Answer approves the targeted tool call: done")
	Do $$$AssertEquals(..Prop(first.ref, "State"), "approved", "the row is approved")
	Do $$$AssertEquals(..WaitHoldGone(first.ref, 15), 1, "the hold ends")
	Do $$$AssertTrue(..WaitHoldSettled(first.ref, first.session, 15), "and its OnResponse has returned")
	Do $$$AssertEquals(..HoldRequests(first.session), "Ens.AlarmRequest,EnsLib.Workflow.TaskRequest", "besides its TaskRequest and AlarmRequest the hold sent no request")
	Do $$$AssertEquals(..Outcomes(first.ref).%Size(), 0, "so no outcome, and nothing to Decide")

	Set second = ..RaiseHeld("tool_call", "IncidentManager")
	If '$IsObject(second) Quit
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(second.ref, "reject", "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK), "done", "Answer rejects the second targeted tool call: done")
	Do $$$AssertEquals(..WaitHoldGone(second.ref, 15), 1, "its hold ends")
	Do ..AssertOneOutcome(second.ref, "rejected", second, second.session, "the rejected one sends its outcome")
}

/// Row 4: two answers at once through the lock gate: exactly one gets done and the other already_answered with the winner's action, channel and
/// time; the row, the task, the one approval.answered and the one outcome are the winner's.
Method TestTwoAnswersAtOnce()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	If '..UseSharedSink() Quit
	Set info = ..RaiseHeld("fix")
	If '$IsObject(info) Quit
	Set ref = info.ref
	Set jobs = ..GateJobs(ref, $ListBuild($ListBuild("answer", "approve", "web"), $ListBuild("answer", "reject", "telegram")), user)
	Do $$$AssertEquals($ListLength(jobs), 2, "both jobs ran")
	If $ListLength(jobs) '= 2 Quit
	Set resultA = $Get(^OcuTalonTest("Approval", "job", $List(jobs, 1), "result"))
	Set resultB = $Get(^OcuTalonTest("Approval", "job", $List(jobs, 2), "result"))
	Do $$$AssertEquals($Get(^OcuTalonTest("Approval", "job", $List(jobs, 1), "error"))_$Get(^OcuTalonTest("Approval", "job", $List(jobs, 2), "error")), "", "neither job failed")
	Do $$$AssertTrue(((resultA = "done") && (resultB = "already_answered")) || ((resultA = "already_answered") && (resultB = "done")), "exactly one is done and the other already_answered: "_resultA_"|"_resultB)
	Set winnerJob = $Select(resultA = "done": $List(jobs, 1), 1: $List(jobs, 2))
	Set loserJob = $Select(resultA = "done": $List(jobs, 2), 1: $List(jobs, 1))
	Set action = ..Prop(ref, "AnsweredAction")
	Set channel = ..Prop(ref, "AnsweredChannel")
	Do $$$AssertEquals(action_"|"_channel, $Select(resultA = "done": "approve|web", 1: "reject|telegram"), "the row holds the winner's action and channel")
	Do $$$AssertEquals(..Prop(ref, "State"), $Select(action = "approve": "approved", 1: "rejected"), "and its state matches")
	Do $$$AssertTrue(..JustNow(..Prop(ref, "AnsweredAt")), "the winner's AnsweredAt is a time within 5 seconds of now: "_..Prop(ref, "AnsweredAt"))
	Set shown = {"action": (action), "channel": (channel), "at": (..Prop(ref, "AnsweredAt"))}
	Do $$$AssertEquals($Get(^OcuTalonTest("Approval", "job", loserJob, "winner")), shown.%ToJSON(), "the loser's winner is the row's action, channel and AnsweredAt")
	Do $$$AssertEquals($Get(^OcuTalonTest("Approval", "job", winnerJob, "winner")), "{}", "the winner's winner is empty")
	Do $$$AssertEquals(..TaskCount(ref)_"|"_..TaskFacts(info.task), "1|"_$Select(action = "approve": "Approve", 1: "Reject")_"|OcuTalonWorkflow|1|", "the task was completed once, with the winner's action")
	Do $$$AssertEquals(..WaitHoldGone(ref, 15), 1, "the hold ends")
	Do $$$AssertTrue(..WaitHoldSettled(ref, info.session, 15), "and its OnResponse has returned")
	Set calls = ##class(OcuTalon.Test.Agent.RunnerFixture).SinkCalls("approval.answered")
	Do $$$AssertEquals(calls.%Size(), 1, "exactly one approval.answered is recorded, also once the hold has acted (the hold fires none)")
	Do ..AssertOneOutcome(ref, $Select(action = "approve": "approved", 1: "rejected"), info, info.session, "the one outcome, the winner's")
}

/// Row 5: refused answers change nothing: an unknown Ref is not_found; a user without the role, an empty or an unknown user, a malformed
/// action or channel, and a row raised for another role are not_allowed.
Method TestAnswerRefusals()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	Set info = ..RaiseHeld("fix")
	If '$IsObject(info) Quit
	Set ref = info.ref
	Set before = ..RowText(ref)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set api = "OcuTalon.Bridge.Approval"
	Set result = $ClassMethod(api, "Answer", "ZzNoSuchRef"_..Number, "approve", "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK)
	Do $$$AssertEquals(result_"|"_winner.%ToJSON(), "not_found|{}", "(a) an unknown Ref is not_found with no winner")
	Set cases = $ListBuild($ListBuild("OcuTalonWorkflow", "approve", "web"), $ListBuild("", "approve", "web"), $ListBuild("ZzNoSuchUser"_..Number, "approve", "web"), $ListBuild(user, "maybe", "web"), $ListBuild(user, "approve", "fax"), $ListBuild(user, "", "web"), $ListBuild(user, "approve", ""))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = "'"_$List(case, 1)_"' "_$List(case, 2)_" "_$List(case, 3)
		Set result = $ClassMethod(api, "Answer", ref, $List(case, 2), $List(case, 3), $List(case, 1), ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK)
		Do $$$AssertEquals(result_"|"_winner.%ToJSON(), "not_allowed|{}", "(b, c) "_label_" is not_allowed with no winner")
	}
	For malformed = "zzsession", "987654321", $Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 21), ##class(OcuTalon.Bridge.Ids).NewRef() _ "x" {
		Set result = $ClassMethod(api, "Answer", ref, "approve", "web", user, malformed, .winner, ..#SINK)
		Do $$$AssertEquals(result_"|"_winner.%ToJSON(), "not_allowed|{}", "(g) a sessionRef of "_$Length(malformed)_" characters that is not a Ref is not_allowed with no winner: no chat id is ever 'the session'")
	}
	Do $$$AssertEquals(..RowText(ref), before, "the row is unchanged")
	Do $$$AssertEquals(..Prop(ref, "State"), "pending", "and pending")
	Do ..AssertNoEntry(mark, ref, "no refusal wrote an audit entry")
	Do $$$AssertEquals(..OpenTasks(ref), info.task, "the task is still open")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and the sink got no call")

	Set settled = ..FixtureRow("approved")
	Set past = ..FixtureRow("pending", -60)
	Set beforeBoth = ..RowText(settled)_..RowText(past)
	For target = settled, past {
		Set label = $Select(target = settled: "an approved row", 1: "a pending row past its expiry")
		Set result = $ClassMethod(api, "Answer", target, "approve", "web", "OcuTalonWorkflow", ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK)
		Do $$$AssertEquals(result_"|"_winner.%ToJSON(), "not_allowed|{}", "(e) a user without the role, on "_label_", is not_allowed with no winner: the role comes before the state")
		Set result = $ClassMethod(api, "Answer", target, "maybe", "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK)
		Do $$$AssertEquals(result_"|"_winner.%ToJSON(), "not_allowed|{}", "(e) a malformed action, on "_label_", is not_allowed with no winner")
	}
	Do $$$AssertEquals(..RowText(settled)_..RowText(past), beforeBoth, "(e) neither row changed")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "(e) and the sink got no call")

	Set cased = ..FixtureRow("approved")
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(cased)
	Set row.RequiredRole = "ocutalonuser"
	Do $$$AssertStatusOK(row.%Save(), "(f) the row's RequiredRole is ocutalonuser")
	Kill row
	Set result = $ClassMethod(api, "Answer", cased, "approve", "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK)
	Do $$$AssertEquals(result, "already_answered", "(f) a RequiredRole in another case is the same IRIS role, which the answerer holds")

	Set role = "ZzApprover"_..Number
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).PutDefault("Decide", "ApprovalRole", role), "(d) the ApprovalRole setting is "_role)
	Set other = ..RaiseHeld("fix")
	If '$IsObject(other) Quit
	Set beforeOther = ..RowText(other.ref)
	Set result = $ClassMethod(api, "Answer", other.ref, "approve", "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK)
	Do $$$AssertEquals(result_"|"_winner.%ToJSON(), "not_allowed|{}", "(d) the answerer does not hold the row's role "_role_": not_allowed")
	Do $$$AssertEquals(..RowText(other.ref), beforeOther, "(d) the row is unchanged")
	Do $$$AssertEquals(..OpenTasks(other.ref), other.task, "(d) its task is still open")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "(d) and the sink got no call")
}

/// Row 6: the timer of a re-armed hold expires a past request: the row is expired with no answer fields, one expired outcome goes out from the
/// new hold's session, the shared sink hears one approval.expired, and no task is open.
Method TestTimerExpires()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	If '..UseSharedSink() Quit
	Set info = ..RaiseHeld("fix")
	If '$IsObject(info) Quit
	Set ref = info.ref
	Set oldHold = ##class(OcuTalon.Bridge.Approval).LiveHold(ref)
	Do ..Age(ref, 86460, -60)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.ApprovalHold).%DeleteId(oldHold), "the hold instance is deleted")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Set auditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Reconcile).Run(), "the Reconcile step runs")
	Set newSession = ..HoldMessages(mark, ref).session
	Do $$$AssertTrue((newSession > mark) && (newSession '= info.session), "the new hold has a session of its own: "_newSession)
	Do $$$AssertEquals(..WaitHoldGone(ref, 15), 1, "within 15 seconds the hold has ended")
	Do ..AssertOneOutcome(ref, "expired", info, newSession, "the outcome")
	Do $$$AssertEquals(..Prop(ref, "State"), "expired", "the row is expired")
	Do $$$AssertEquals(..Prop(ref, "AnsweredAction")_..Prop(ref, "AnsweredChannel")_..Prop(ref, "AnsweredBy")_..Prop(ref, "AnsweredAt")_..Prop(ref, "Result")_..Prop(ref, "FinishedAt"), "", "with no answer fields")
	Do $$$AssertTrue(..WaitHoldSettled(ref, newSession, 15), "the hold's OnResponse has returned")
	Set calls = ##class(OcuTalon.Test.Agent.RunnerFixture).SinkCalls("approval.expired")
	Do $$$AssertEquals(calls.%Size(), 1, "the shared sink has exactly one approval.expired")
	If calls.%Size() = 1 Do $$$AssertEquals(calls.%Get(0).ownerRef_"|"_calls.%Get(0).payload, info.owner_"|{""ref"":"""_ref_"""}", "with the OwnerRef and {""ref""}")
	Do $$$AssertEquals(..OpenTasks(ref), "", "no task is open")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(ref, "approve", "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK), "expired", "a later Answer returns expired")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(auditMark, "OcuTalon", "Approval", "Approval", ref)
	Do $$$AssertEquals(entries.%Size(), 1, "one Approval entry carries the Ref: the timer's, and no later Answer added one")
	If entries.%Size() = 1 {
		Set entry = entries.%Get(0)
		Do ..AssertEntry(entry, auditMark, ..Want(ref, "fix", "expired", "pending", "expired", "", info.incident, info.owner, entry.username, info.owner, "system"), "the timer's entry names the hold job's user, system and the OwnerRef", "")
		Do $$$AssertNotEquals(entry.username, $Username, "and it is written by the hold's job, not by the test process")
	}
}

/// Row 7: an answer past the expiry, before the timer has fired, expires the row: expired with no answer fields, one approval.expired seen as
/// expired, the task still open and no outcome yet; a second answer is expired again with no new call, and StartExecution and Cancel are refused.
Method TestAnswerPastExpiry()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	Set info = ..RaiseHeld("fix")
	If '$IsObject(info) Quit
	Set ref = info.ref
	Do ..Age(ref, 86460, -60)
	Set sessionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set result = ##class(OcuTalon.Bridge.Approval).Answer(ref, "approve", "web", user, sessionRef, .winner, ..#SINK)
	Do $$$AssertEquals(result_"|"_winner.%ToJSON(), "expired|{}", "Answer returns expired with no winner")
	Do ..AssertOneEntry(mark, ..Want(ref, "fix", "expired", "pending", "expired", "", info.incident, info.owner, user, sessionRef, "web"), "the audit entry names the answerer")
	Do $$$AssertEquals(..Prop(ref, "State"), "expired", "the row is expired")
	Do $$$AssertEquals(..Prop(ref, "AnsweredAction")_..Prop(ref, "AnsweredChannel")_..Prop(ref, "AnsweredBy")_..Prop(ref, "AnsweredAt"), "", "with no answer fields")
	Do ..AssertEvents("approval.expired", "the sink")
	Do ..AssertEvent(1, "approval.expired", info.owner, ref, "expired", "the sink")
	Do $$$AssertEquals(..OpenTasks(ref), info.task, "the task is still open")
	Do $$$AssertEquals(..Outcomes(ref).%Size(), 0, "no outcome has been sent yet")
	Set result = ##class(OcuTalon.Bridge.Approval).Answer(ref, "approve", "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK)
	Do $$$AssertEquals(result_"|"_winner.%ToJSON(), "expired|{}", "a second Answer gives expired again")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Approval", "Approval", ref).%Size(), 1, "and adds no audit entry")
	Do ..AssertEvents("approval.expired", "the sink, still")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.Approval).StartExecution(ref), "StartExecution is refused")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.Approval).Cancel(ref, ..#SINK), "Cancel is refused")
	Do $$$AssertEquals(..Prop(ref, "State"), "expired", "the row stays expired")
}

/// Row 8 (DW-186): Expire needs no clock: a row whose ExpiresAt is still 30 seconds ahead expires, with one approval.expired; a second Expire is
/// an error that names expired.
Method TestExpireDoesNotWaitForTheClock()
{
	If '..Ready() Quit
	Set info = ..RaiseHeld("fix")
	If '$IsObject(info) Quit
	Set ref = info.ref
	Do ..Age(ref, 60, 30)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Expire(ref, ..#SINK), "Expire is OK with ExpiresAt 30 seconds ahead")
	Do ..AssertOneEntry(mark, ..Want(ref, "fix", "expired", "pending", "expired", "", info.incident, info.owner, $Username, info.owner, "system"), "the audit entry names the job's user, system and the OwnerRef")
	Do $$$AssertEquals(..Prop(ref, "State"), "expired", "the row is expired")
	Do ..AssertEvents("approval.expired", "the sink")
	Do ..AssertEvent(1, "approval.expired", info.owner, ref, "expired", "the sink")
	Set sc = ##class(OcuTalon.Bridge.Approval).Expire(ref, ..#SINK)
	Do $$$AssertStatusNotOK(sc, "a second Expire fails")
	Do $$$AssertTrue(($SYSTEM.Status.GetErrorText(sc) [ "it is expired") && ($SYSTEM.Status.GetErrorText(sc) [ ref), "and names the Ref and expired: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Approval", "Approval", ref).%Size(), 1, "and adds no audit entry")
	Do ..AssertEvents("approval.expired", "the sink, still")
}

/// Row 9: Cancel moves a pending request to cancelled and completes its task with no action: the hold ends and sends no outcome, the sink hears one
/// approval.cancelled, a later Answer is not_found and a second Cancel is an error that names cancelled.
Method TestCancel()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	Set info = ..RaiseHeld("fix")
	If '$IsObject(info) Quit
	Set ref = info.ref
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set before = ..RowText(ref)
	For case = $ListBuild("fax", ""), $ListBuild("", "zzsession"), $ListBuild("", "987654321") {
		Set sc = ##class(OcuTalon.Bridge.Approval).Cancel(ref, ..#SINK, $List(case, 1), "", $List(case, 2))
		Set argument = $Select($List(case, 1) '= "": "channel", 1: "sessionRef")
		Do $$$AssertStatusNotOK(sc, "(c) Cancel refuses a bad "_argument)
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ (argument_" argument"), "(c) and the error names the "_argument_": "_$SYSTEM.Status.GetErrorText(sc))
	}
	Do $$$AssertEquals(..RowText(ref), before, "(c) nothing changed")
	Do ..AssertNoEntry(mark, ref, "(c) and no entry was written")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "(c) the sink got no call")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Cancel(ref, ..#SINK), "Cancel is OK")
	Do ..AssertOneEntry(mark, ..Want(ref, "fix", "cancelled", "pending", "cancelled", "", info.incident, info.owner, $Username, info.owner, "system"), "(a) the audit entry names the job's user, system and the OwnerRef")
	Do $$$AssertEquals(..Prop(ref, "State"), "cancelled", "the row is cancelled")
	Do $$$AssertEquals(..Prop(ref, "AnsweredAction")_..Prop(ref, "AnsweredChannel")_..Prop(ref, "AnsweredBy")_..Prop(ref, "AnsweredAt"), "", "with no answer fields")
	Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(info.task)
	Do $$$AssertEquals(task.%Status_"|"_task.%TaskStatus.IsComplete_"|"_..WorklistUsers(info.task), "Cancelled|1|", "the task is complete with status Cancelled and has no worklist item")
	Kill task
	Do $$$AssertEquals(..WaitHoldGone(ref, 15), 1, "the hold ends")
	Do $$$AssertTrue(..WaitHoldSettled(ref, info.session, 15), "and its OnResponse has returned")
	Do $$$AssertEquals(..Outcomes(ref).%Size(), 0, "and no outcome is sent")
	Do ..AssertEvents("approval.cancelled", "the sink")
	Do ..AssertEvent(1, "approval.cancelled", info.owner, ref, "cancelled", "the sink")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(ref, "approve", "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK), "not_found", "a later Answer is not_found")
	Set sc = ##class(OcuTalon.Bridge.Approval).Cancel(ref, ..#SINK)
	Do $$$AssertStatusNotOK(sc, "a second Cancel fails")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "it is cancelled", "and names cancelled: "_$SYSTEM.Status.GetErrorText(sc))
	Do ..AssertEvents("approval.cancelled", "the sink, still")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Approval", "Approval", ref).%Size(), 1, "and the refused second Cancel added no audit entry")

	// (b) a cancel on a person's authority
	Set person = ..RaiseHeld("tool_call")
	If '$IsObject(person) Quit
	Set sessionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Cancel(person.ref, ..#SINK, "web", user, sessionRef), "(b) Cancel with a channel, a user and a session is OK")
	Do ..AssertOneEntry(mark, ..Want(person.ref, "tool_call", "cancelled", "pending", "cancelled", "", ..Prop(person.ref, "ToolName"), person.owner, user, sessionRef, "web"), "(b) the audit entry names the three arguments")
}

/// Row 10: every pair of a state and a call is refused unless AD-11's path allows it. Fixture rows in the 8 states and an approved row past its
/// expiry meet Answer approve and reject, Expire, Cancel, StartExecution and FinishExecution (done, failed, interrupted and x), each call on its
/// own row. A refusal names the Ref and the state, and changes no column and fires no event; an allowed change sets only its fields and fires its
/// event (none for StartExecution, which takes no sink: Decide's HostSinkClass is ProbeSink here so that an event of it would show). Answer on a pending row and Cancel on a pending row are rows 1 and 9: a fixture has no task.
Method TestEveryOtherTransitionIsRefused()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	If '..UseSharedSink() Quit
	Set gridMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set changes = 0
	Set none = ""
	Set keys = $ListBuild("pending", "approved", "approvedPast", "rejected", "expired", "cancelled", "executing", "done", "failed")
	Set ops = $ListBuild("answer approve", "answer reject", "expire", "cancel", "start", "finish done", "finish failed", "finish interrupted", "finish x")
	Set keyPosition = 0
	While $ListNext(keys, keyPosition, key) {
		Set state = $Select(key = "approvedPast": "approved", 1: key)
		Set opPosition = 0
		While $ListNext(ops, opPosition, op) {
			Set expected = ..Expected(key, op)
			Set kind = $List(expected, 1)
			If kind = "skip" Continue
			Set label = key_" + "_op
			Set ref = ..FixtureRow(state, $Select(key = "approvedPast": -60, 1: 3600))
			Set before = ..RowText(ref)
			Set owner = ..Prop(ref, "OwnerRef")
			Kill ^||ZzProbeSink
			Set done = ..Run(op, ref, user, .winner)
			If kind = "changed" {
				Set changes = changes + 1
				Set want(ref) = ..GridWant(ref, state, op, $List(expected, 2), owner)
			} Else {
				Set none = none _ $ListBuild(ref)
			}
			If kind = "refused" {
				Do $$$AssertEquals($List(done, 1), "ERR", label_" is refused")
				Set text = $List(done, 2)
				If op = "finish x" {
					Do $$$AssertTrue((text [ "'x'") && (text [ ref), label_": the error names the result x and the Ref: "_text)
				} Else {
					Do $$$AssertTrue((text [ ref) && (text [ ("it is "_state)), label_": the error names the Ref and the state: "_text)
				}
				If (key = "approvedPast") && (op = "start") Do $$$AssertTrue(text [ "past its expiry", label_": the error says the row is past its expiry: "_text)
				Do $$$AssertEquals(..RowText(ref), before, label_": no column changed")
				Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, label_": the sink got no call")
			} ElseIf kind = "changed" {
				Set finish = ($Piece(op, " ", 1) = "finish")
				Set skip = $Select(finish: "State,Result,FinishedAt", 1: "State")
				Do $$$AssertEquals($List(done, 1), "OK", label_" is allowed")
				Do $$$AssertEquals(..Prop(ref, "State"), $List(expected, 2), label_": the row becomes "_$List(expected, 2))
				Do $$$AssertEquals(..RowText(ref, skip), ..SkipText(before, skip), label_": no other column changed")
				If finish {
					Do $$$AssertEquals(..Prop(ref, "Result"), $Piece(op, " ", 2), label_": Result is the given result")
					Do $$$AssertTrue(..JustNow(..Prop(ref, "FinishedAt")), label_": FinishedAt is a time within 5 seconds of now: "_..Prop(ref, "FinishedAt"))
				}
				If $List(expected, 3) = "" {
					Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, label_": no event fires")
				} Else {
					Do ..AssertEvents($List(expected, 3), label)
					Do ..AssertEvent(1, $List(expected, 3), owner, ref, $List(expected, 2), label)
				}
			} Else {
				Do $$$AssertEquals($List(done, 1), kind, label_" gives "_kind)
				Set shown = "{}"
				If kind = "already_answered" Set shown = {"action": (..Prop(ref, "AnsweredAction")), "channel": (..Prop(ref, "AnsweredChannel")), "at": (..Prop(ref, "AnsweredAt"))}.%ToJSON()
				Do $$$AssertEquals($List(done, 2), shown, label_": the winner is "_shown)
				Do $$$AssertEquals(..RowText(ref), before, label_": no column changed")
				Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, label_": the sink got no call")
			}
		}
	}
	Set unknown = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set long = $Translate($Justify("", 600), " ", "z")
	Kill ^||ZzProbeSink
	For op = "expire", "cancel", "start", "finish done" {
		For target = unknown, long {
			Set label = $Select(target = unknown: "an unknown Ref", 1: "a 600-character Ref")_" + "_op
			Set done = ..Run(op, target, user, .winner)
			Do $$$AssertEquals($List(done, 1), "ERR", label_" is refused")
			Do $$$AssertTrue($List(done, 2) [ $Extract(target, 1, 22), label_": the error names the Ref: "_$Extract($List(done, 2), 1, 200))
		}
	}
	Set done = ..Run("answer approve", long, user, .winner)
	Do $$$AssertEquals($List(done, 1)_"|"_$List(done, 2), "not_found|{}", "a 600-character Ref is not_found for Answer")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and the sink got no call")

	// the audit log: each allowed change wrote exactly one entry, and no refusal or no-change result wrote one
	Do $$$AssertTrue(changes > 0, "the grid has allowed changes: "_changes)
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(gridMark, "OcuTalon", "Approval", "Approval", "", "", changes)
	Hang 1
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(gridMark, "OcuTalon", "Approval", "Approval")
	Kill found
	For index = 0:1:entries.%Size() - 1 {
		Set entry = entries.%Get(index)
		Set found(entry.data.ref) = $Get(found(entry.data.ref)) + 1
		Set found(entry.data.ref, 1) = entry
	}
	Set unexpected = ""
	Set position = 0
	While $ListNext(none, position, target) {
		If $Get(found(target)) Set unexpected = unexpected _ $ListBuild(target)
	}
	Do $$$AssertEquals($ListToString(unexpected), "", "no refusal and no no-change result wrote an audit entry")
	Set target = ""
	For {
		Set target = $Order(want(target))
		Quit:target=""
		Do $$$AssertEquals($Get(found(target)), 1, "the change of "_target_" wrote exactly one audit entry")
		If $Get(found(target)) = 1 Do ..AssertEntry(found(target, 1), gridMark, want(target), "the entry of "_target_" ("_want(target).change_" from "_want(target).from_")")
	}
}

/// What the entry of a change in the grid names: Expire the job's user and system, StartExecution and FinishExecution the row's approver
/// (the fixture's AnsweredBy and web); the session is the row's OwnerRef.
Method GridWant(ref As %String, state As %String, op As %String, to As %String, owner As %String) As %DynamicObject [ Private ]
{
	Set verb = $Piece(op, " ", 1)
	Set approver = (verb '= "expire")
	Quit ..Want(ref, "fix", $Case(verb, "expire": "expired", "start": "started", : "finished"), state, to, $Select(verb = "finish": $Piece(op, " ", 2), 1: ""), ..Prop(ref, "IncidentRef"), owner, $Select(approver: ..#ANSWERER, 1: $Username), owner, $Select(approver: "web", 1: "system"))
}

/// Row 9: a write that fails never undoes a change. With the audit event OcuTalon/Approval/Approval disabled, IRIS writes no entry: Answer is
/// still done, the row is approved, approval.answered fires once, a warning names the Ref and the change, and no entry carries the Ref.
Method TestFailedAuditNeverUndoesAChange()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	Set info = ..RaiseHeld("fix")
	If '$IsObject(info) Quit
	Set ref = info.ref
	Do $$$AssertEquals(..AuditEventState(), 1, "control: the audit event "_..#AUDITEVENT_" is enabled")
	Set ..AuditEventOff = 1
	Do ..SetAuditEvent(0)
	Do $$$AssertEquals(..AuditEventState(), 0, "the audit event is disabled for the test")
	Set probe = ..Want(##class(OcuTalon.Bridge.Ids).NewRef(), "fix", "answered", "pending", "approved", "approved", ##class(OcuTalon.Bridge.Ids).NewRef(), "instance", user, ##class(OcuTalon.Bridge.Ids).NewRef(), "web")
	Set probeSc = ##class(OcuTalon.Bridge.Audit).Record("Approval", probe)
	Do $$$AssertStatusNotOK(probeSc, "control: Record of a valid Approval entry is refused while the event is disabled")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(probeSc) [ "no entry of type Approval was written", "control: and the error says that no entry was written: "_$SYSTEM.Status.GetErrorText(probeSc))
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set logMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set result = ##class(OcuTalon.Bridge.Approval).Answer(ref, "approve", "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK)
	Do $$$AssertEquals(result_"|"_winner.%ToJSON(), "done|{}", "Answer is still done")
	Do $$$AssertEquals(..Prop(ref, "State")_"|"_..Prop(ref, "AnsweredBy"), "approved|"_user, "the row is approved by the answerer")
	Do ..AssertEvents("approval.answered", "the sink")
	Do ..AssertEvent(1, "approval.answered", info.owner, ref, "approved", "the sink")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(logMark, "OcuTalon.Bridge.Approval", "Audited", $ListBuild(ref, "answered")), 1, "one warning names the Ref and the change")
	Do ..AssertNoEntry(mark, ref, "no entry was written")
	Do $$$AssertEquals(..WaitHoldGone(ref, 15), 1, "the hold ends")
	Do ..AssertOneOutcome(ref, "approved", info, info.session, "the outcome")

	// the same for the methods that move a row
	Set second = ..RaiseHeld("fix")
	If '$IsObject(second) Quit
	Set logMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Kill ^||ZzProbeSink
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Cancel(second.ref, ..#SINK), "Cancel is still OK")
	Do $$$AssertEquals(..Prop(second.ref, "State"), "cancelled", "and the row is cancelled")
	Do ..AssertEvents("approval.cancelled", "the sink, after Cancel")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(logMark, "OcuTalon.Bridge.Approval", "Audited", $ListBuild(second.ref, "cancelled")), 1, "with one warning")
	Do ..AssertNoEntry(mark, second.ref, "and no entry")
}

/// AD-11: a state method reads the row under the lock, also when the calling process holds it open. With each fixture row held open in this
/// process while the database row moves on (another job's change, written with SQL), Answer gives already_answered with the database's winner
/// and StartExecution an error that names executing, and neither saves over the change.
Method TestHeldRowIsReadUnderTheLock()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	Set pending = ..FixtureRow("pending")
	Set approved = ..FixtureRow("approved")
	Set heldPending = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(pending)
	Set heldApproved = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(approved)
	Set at = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set result = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Bridge_Data.ApprovalRequest SET State = 'rejected', AnsweredAction = 'reject', AnsweredChannel = 'telegram', AnsweredBy = ?, AnsweredAt = ? WHERE Ref = ?", user, at, pending)
	Do $$$AssertEquals(result.%SQLCODE_"|"_result.%ROWCOUNT, "0|1", "another job rejects the pending row on the database")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Bridge_Data.ApprovalRequest SET State = 'executing' WHERE Ref = ?", approved)
	Do $$$AssertEquals(result.%SQLCODE_"|"_result.%ROWCOUNT, "0|1", "and starts the approved row")
	Do $$$AssertEquals(heldPending.State_"|"_heldApproved.State, "pending|approved", "the copies this process holds are stale")
	Kill ^||ZzProbeSink
	Set answer = ##class(OcuTalon.Bridge.Approval).Answer(pending, "approve", "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK)
	Set shown = {"action": "reject", "channel": "telegram", "at": (at)}
	Do $$$AssertEquals(answer_"|"_winner.%ToJSON(), "already_answered|"_shown.%ToJSON(), "Answer gives already_answered with the database's winner")
	Set sc = ##class(OcuTalon.Bridge.Approval).StartExecution(approved)
	Do $$$AssertTrue($$$ISERR(sc) && ($SYSTEM.Status.GetErrorText(sc) [ "it is executing"), "StartExecution is refused and names executing: "_$SYSTEM.Status.GetErrorText(sc))
	Kill heldPending, heldApproved
	Do $$$AssertEquals(..Prop(pending, "State")_"|"_..Prop(pending, "AnsweredChannel")_"|"_..Prop(approved, "State"), "rejected|telegram|executing", "neither saved over the database's change")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and the sink got no call")
}

/// Row 11: two StartExecution calls at once through the lock gate: exactly one returns OK, the other an error that names executing.
Method TestStartExecutionAtOnce()
{
	If '..Ready() Quit
	Set ref = ..FixtureRow("approved")
	Set jobs = ..GateJobs(ref, $ListBuild($ListBuild("start"), $ListBuild("start")), "")
	Do $$$AssertEquals($ListLength(jobs), 2, "both jobs ran")
	If $ListLength(jobs) '= 2 Quit
	Set resultA = $Get(^OcuTalonTest("Approval", "job", $List(jobs, 1), "result"))
	Set resultB = $Get(^OcuTalonTest("Approval", "job", $List(jobs, 2), "result"))
	Do $$$AssertEquals($Get(^OcuTalonTest("Approval", "job", $List(jobs, 1), "error"))_$Get(^OcuTalonTest("Approval", "job", $List(jobs, 2), "error")), "", "neither job failed")
	Do $$$AssertTrue(((resultA = "OK") && (resultB [ "it is executing")) || ((resultB = "OK") && (resultA [ "it is executing")), "exactly one returns OK and the other an error that names executing: "_resultA_" | "_resultB)
	Do $$$AssertEquals(..Prop(ref, "State"), "executing", "the row is executing")
}

/// Row 12: a request that Reconcile re-armed is answered through its new task: the new task is completed, the discarded one is untouched, and the
/// outcome comes from the new hold's session.
Method TestAnswerReArmed()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	Set info = ..RaiseHeld("fix")
	If '$IsObject(info) Quit
	Set ref = info.ref
	Set oldTask = info.task
	Set oldHold = ##class(OcuTalon.Bridge.Approval).LiveHold(ref)
	Do ..Age(ref, 82800, 3600)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.ApprovalHold).%DeleteId(oldHold), "the hold instance is deleted")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Reconcile).Run(), "the Reconcile step runs")
	Set newSession = ..HoldMessages(mark, ref).session
	Set newTask = ..WaitTask(ref, 10)
	Do $$$AssertTrue((newTask '= "") && (newTask '= oldTask), "the request has a new open task: "_newTask)
	Do $$$AssertTrue((newSession > mark) && (newSession '= info.session), "and a new hold in a session of its own: "_newSession)
	Set oldBefore = ..TaskState(oldTask)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(ref, "approve", "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK), "done", "Answer approves it: done")
	Do $$$AssertEquals(..TaskFacts(newTask), "Approve|OcuTalonWorkflow|1|", "the new task is completed with Approve")
	Do $$$AssertEquals(..TaskState(oldTask), oldBefore, "the discarded task is untouched")
	Do $$$AssertEquals(..WaitHoldGone(ref, 15), 1, "the new hold ends")
	Do ..AssertOneOutcome(ref, "approved", info, newSession, "the outcome comes from the new hold's session")
}

/// Row 13: an answer that arrives before the task exists is recorded, waits for the task, and completes it once it appears: the hold ends and
/// sends one approved outcome.
Method TestAnswerBeforeTheTaskExists()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	Set ..ApprovalsDisabled = 1
	Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem("OcuTalonApprovals", 0), "OcuTalonApprovals is disabled")
	Set row = ..NewRow("fix")
	Set trace = row.TraceRef
	Set incident = row.IncidentRef
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Set sc = ..Raise(row, .ref)
	Kill row
	Do $$$AssertStatusOK(sc, "the fix request is raised")
	If $$$ISERR(sc) Quit
	Set session = ..HoldMessages(mark, ref).session
	Do $$$AssertEquals(..TaskCount(ref), 0, "no task exists")
	Set number = ..StartJob("answer", ref, "approve", "web", user)
	Set deadline = $ZHorolog + 10
	While (..Prop(ref, "State") '= "approved") && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Do $$$AssertEquals(..Prop(ref, "State"), "approved", "the row shows the answer while the job waits for the task")
	Do $$$AssertEquals($Get(^OcuTalonTest("Approval", "job", number, "done")), "", "and the job has not returned yet")
	Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem("OcuTalonApprovals", 1), "OcuTalonApprovals is enabled again")
	Set ..ApprovalsDisabled = 0
	Set taskSeconds = ##class(OcuTalon.Bridge.Approval).#TASKSECONDS
	Do ..WaitNode($Name(^OcuTalonTest("Approval", "job", number, "done")), taskSeconds + 15)
	Do $$$AssertEquals($Get(^OcuTalonTest("Approval", "job", number, "result"))_"|"_$Get(^OcuTalonTest("Approval", "job", number, "error")), "done|", "the job gets done")
	Set ids = ..TaskIds(ref)
	Do $$$AssertEquals($ListLength(ids), 1, "the task appeared within TASKSECONDS ("_taskSeconds_" seconds) of the answer")
	If $ListLength(ids) = 1 Do $$$AssertEquals(..TaskFacts($List(ids, 1)), "Approve|OcuTalonWorkflow|1|", "and was completed with Approve by OcuTalonWorkflow")
	Do $$$AssertEquals(..WaitHoldGone(ref, 15), 1, "the hold ends")
	Do $$$AssertTrue(session > mark, "the hold has its session: "_session)
	Do ..AssertOneOutcome(ref, "approved", {"incident": (incident), "trace": (trace)}, session, "the outcome, in the hold's session")
}

/// Row 14: the hold acts only on the row: a task completed directly with Approve while the row is pending ends the hold, sends no outcome and
/// leaves the row pending with no answer fields; a task completed with Approve while the row shows rejected ends the hold and sends nothing
/// either, because the task's action is not the row's answer.
Method TestHoldActsOnlyOnTheRowsAnswer()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	Set info = ..RaiseHeld("fix")
	If '$IsObject(info) Quit
	Set ref = info.ref
	Do $$$AssertStatusOK(..Complete(info.task), "the task is completed directly with Approve")
	Do $$$AssertEquals(..WaitHoldGone(ref, 15), 1, "the hold ends")
	Do $$$AssertTrue(..WaitHoldSettled(ref, info.session, 15), "and its OnResponse has returned")
	Do $$$AssertEquals(..Outcomes(ref).%Size(), 0, "no outcome is sent")
	Do $$$AssertEquals(..Prop(ref, "State"), "pending", "the row is still pending")
	Do $$$AssertEquals(..Prop(ref, "AnsweredAction")_..Prop(ref, "AnsweredChannel")_..Prop(ref, "AnsweredBy")_..Prop(ref, "AnsweredAt"), "", "with no answer fields")

	Set other = ..RaiseHeld("fix")
	If '$IsObject(other) Quit
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(other.ref)
	Set row.AnsweredAction = "reject"
	Set row.AnsweredChannel = "web"
	Set row.AnsweredBy = user
	Set row.AnsweredAt = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set row.State = "rejected"
	Do $$$AssertStatusOK(row.%Save(), "a second row shows rejected, its task not completed")
	Kill row
	Do $$$AssertStatusOK(..Complete(other.task), "its task is completed directly with Approve")
	Do $$$AssertEquals(..WaitHoldGone(other.ref, 15), 1, "its hold ends")
	Do $$$AssertTrue(..WaitHoldSettled(other.ref, other.session, 15), "and its OnResponse has returned")
	Do $$$AssertEquals(..Outcomes(other.ref).%Size(), 0, "no outcome is sent: the task's action is not the row's answer")
	Do $$$AssertEquals(..Prop(other.ref, "State"), "rejected", "the row is still rejected")
}

/// Row 15: an answer that the row shows but whose task was never completed is delivered when the timer fires: for an approved and a rejected
/// request, the test holds the row's lock while Reconcile re-arms the past request, writes the answer as Answer would without completing the
/// task, and releases the lock. Each hold ends with one outcome, the row's own, the row keeps its state, and StartExecution is refused for
/// being past its expiry.
Method TestTimerDeliversAnUndeliveredAnswer()
{
	If '..Ready() Quit
	Set user = ..Answerer()
	If user = "" Quit
	Set count = 0
	For action = "approve", "reject" {
		Set info = ..RaiseHeld("fix")
		If '$IsObject(info) Quit
		Set info.state = $Select(action = "approve": "approved", 1: "rejected")
		Set oldHold = ##class(OcuTalon.Bridge.Approval).LiveHold(info.ref)
		Do ..Age(info.ref, 86460, -60)
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.ApprovalHold).%DeleteId(oldHold), info.state_": the hold instance is deleted")
		Lock +^OcuTalon.Bridge.Approval(info.ref):5
		If '$Test {
			Do $$$AssertTrue(0, info.state_": the test takes the row's lock")
			Quit
		}
		Set ^OcuTalonTest("Approval", "held", info.ref) = ""
		Set count = count + 1
		Set infos(count) = info
	}
	If count '= 2 Quit
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Reconcile).Run(), "the Reconcile step re-arms both requests (1 second timers)")
	For n = 1, 2 {
		Set info = infos(n)
		Set info.newSession = ..HoldMessages(mark, info.ref).session
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(info.ref)
		Set row.AnsweredAction = $Select(info.state = "approved": "approve", 1: "reject")
		Set row.AnsweredChannel = "web"
		Set row.AnsweredBy = user
		Set row.AnsweredAt = ##class(OcuTalon.Bridge.Time).NowUtc()
		Set row.State = info.state
		Do $$$AssertStatusOK(row.%Save(), info.state_": the answer is written on the row without completing the task")
		Kill row
		Lock -^OcuTalon.Bridge.Approval(info.ref)
		Kill ^OcuTalonTest("Approval", "held", info.ref)
	}
	For n = 1, 2 {
		Set info = infos(n)
		Do $$$AssertEquals(..WaitHoldGone(info.ref, 15), 1, info.state_": within 15 seconds the hold has ended")
		Do ..AssertOneOutcome(info.ref, info.state, info, info.newSession, "the "_info.state_" outcome")
		Do $$$AssertEquals(..Prop(info.ref, "State"), info.state, info.state_": the row keeps its state")
	}
	Set ref = infos(1).ref
	Set sc = ##class(OcuTalon.Bridge.Approval).StartExecution(ref)
	Do $$$AssertStatusNotOK(sc, "StartExecution is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "past its expiry", "for being past its expiry: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(..Prop(ref, "State"), "approved", "the row stays approved")
}

/// The job body of TestLockHeld: takes LOCK ^OcuTalon.Bridge.Approval, reports it, and keeps it until the test sets release or the seconds
/// pass.
ClassMethod HoldLockInJob(number As %Integer, seconds As %Integer)
{
	Set run = $Name(^OcuTalonTest("Approval", "job", number))
	Try {
		Lock +^OcuTalon.Bridge.Approval:10
		If $Test {
			Set @run@("locked") = 1
			Set deadline = $ZHorolog + seconds
			While '$Get(@run@("release")) && ($ZHorolog < deadline) {
				Hang 0.05
			}
			Lock -^OcuTalon.Bridge.Approval
		} Else {
			Set @run@("error") = "the lock was not taken"
		}
	} Catch exception {
		Set @run@("error") = exception.DisplayString()
	}
	Set @run@("done") = 1
}

/// --- fixtures and helpers ---
/// 1 when the production runs with every item; otherwise the test fails with the reason.
Method Ready() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()
	If reason '= "" Do $$$AssertEquals(reason, "", "the production is ready")
	Quit reason = ""
}

/// An unsaved request of the kind, as the matrix describes it: a tool_call row has ToolName zz_gate_held and ToolArguments {"value":1}; a fix
/// row has IncidentRef, ResultTarget IncidentManager, a DryRun and the fix's FixKind zz_fix, FixParameters {"field":"OrderDate"} and FixTargets 101,102,103.
/// Both have new OwnerRef and TraceRef.
Method NewRow(kind As %String) As OcuTalon.Bridge.Data.ApprovalRequest [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).%New()
	Set row.Kind = kind
	Set row.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.TraceRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	If kind = "tool_call" {
		Set row.ToolName = "zz_gate_held"
		Set row.ToolArguments = "{""value"":1}"
	} Else {
		Set row.IncidentRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set row.ResultTarget = "IncidentManager"
		Set row.DryRun = "{""affected"":3,""resend"":3,""leftOut"":0,""field"":""OrderDate"",""before"":""10/24/2026"",""after"":""2026-10-24"",""itemNoun"":""orders""}"
		Set row.FixKind = "zz_fix"
		Set row.FixParameters = "{""field"":""OrderDate""}"
		Set row.FixTargets = "101,102,103"
	}
	Quit row
}

/// Raises the request with the probe sink, and tracks its Ref for the cleanup the moment it is known. The sink's calls are in ^||ZzProbeSink.
Method Raise(row As OcuTalon.Bridge.Data.ApprovalRequest, Output ref As %String, sessionId As %String = "", superSession As %String = "") As %Status [ Private ]
{
	Set sc = ##class(OcuTalon.Bridge.Approval).Raise(row, .ref, ..#SINK, sessionId, superSession)
	If ref '= "" Set ^OcuTalonTest("Approval", "refs", ref) = ""
	Quit sc
}

/// The cases of TestRefused, each $ListBuild(kind, property, value, the field that the error names).
ClassMethod Refusals() As %List [ Private ]
{
	Set cases = $ListBuild(
		$ListBuild("tool_call", "Kind", "", "Kind"),
		$ListBuild("tool_call", "Kind", "other", "Kind"),
		$ListBuild("tool_call", "OwnerRef", "", "OwnerRef"),
		$ListBuild("tool_call", "OwnerRef", "x", "OwnerRef"),
		$ListBuild("tool_call", "ToolName", "", "ToolName"),
		$ListBuild("tool_call", "ToolArguments", "[1]", "ToolArguments"),
		$ListBuild("tool_call", "ToolArguments", "x", "ToolArguments"),
		$ListBuild("tool_call", "ToolArguments", "", "ToolArguments"),
		$ListBuild("tool_call", "DryRun", "{""affected"":1}", "DryRun"),
		$ListBuild("fix", "DryRun", "", "DryRun"),
		$ListBuild("fix", "DryRun", "x", "DryRun"),
		$ListBuild("fix", "ToolName", "zz_gate_held", "ToolName"),
		$ListBuild("fix", "ToolArguments", "{}", "ToolArguments"),
		$ListBuild("fix", "ResultTarget", "", "ResultTarget"),
		$ListBuild("fix", "FixKind", "", "FixKind"),
		$ListBuild("fix", "FixParameters", "", "FixParameters"),
		$ListBuild("fix", "FixParameters", "[1]", "FixParameters"),
		$ListBuild("fix", "FixTargets", "", "FixTargets"),
		$ListBuild("tool_call", "FixKind", "zz_fix", "FixKind"),
		$ListBuild("tool_call", "FixParameters", "{}", "FixParameters"),
		$ListBuild("tool_call", "FixTargets", "101", "FixTargets"),
		$ListBuild("tool_call", "IncidentRef", "x", "IncidentRef"),
		$ListBuild("tool_call", "TraceRef", "x", "TraceRef"))
	For name = "Ref", "State", "RequiredRole", "RaisedAt", "ExpiresAt", "AnsweredAction", "AnsweredChannel", "AnsweredBy", "AnsweredAt", "Result", "FinishedAt" {
		Set cases = cases _ $ListBuild($ListBuild("tool_call", name, "zz", name))
	}
	Quit cases
}

/// The refusal: an error status that names the field, an empty ref.
Method AssertRefused(sc As %Status, ref As %String, field As %String, label As %String) [ Private ]
{
	Do $$$AssertStatusNotOK(sc, label_" is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ("refuses the request: "_field_" "), label_": the error names "_field_": "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(ref, "", label_": ref is empty")
}

/// The fields that a request is given, as a $ListBuild in the order of GivenFields, taken before Raise so that no later change of the object
/// can hide a change of a field.
Method Snapshot(row As OcuTalon.Bridge.Data.ApprovalRequest) As %List [ Private ]
{
	Set list = ""
	Set names = ..#GIVENFIELDS
	For index = 1:1:$Length(names, ",") {
		Set list = list _ $ListBuild($Property(row, $Piece(names, ",", index)))
	}
	Quit list
}

/// The saved row has the fields that the request was given, from the snapshot taken before Raise.
Method AssertGiven(saved As OcuTalon.Bridge.Data.ApprovalRequest, given As %List, kind As %String) [ Private ]
{
	Set names = ..#GIVENFIELDS
	For index = 1:1:$Length(names, ",") {
		Set name = $Piece(names, ",", index)
		Do $$$AssertEquals($Property(saved, name), $ListGet(given, index), kind_": the given "_name_" is unchanged")
	}
}

/// The sink got exactly one call, approval.raised with the owner and {"ref"}, at transaction level 0, with the row existing.
Method AssertSink(ref As %String, owner As %String, label As %String) [ Private ]
{
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, label_" got one call")
	Set call = $Get(^||ZzProbeSink(1))
	Do $$$AssertEquals($ListGet(call, 1)_"|"_$ListGet(call, 2)_"|"_$ListGet(call, 3), "approval.raised|"_owner_"|{""ref"":"""_ref_"""}", label_": approval.raised with the OwnerRef and the Ref")
	Do $$$AssertEquals($ListGet(call, 4)_"|"_$ListGet(call, 5), "0|1", label_": at transaction level 0, with the row existing")
}

/// The request's hold is in the session and has the SuperSession (row 6): the hold's own fields, its task's header and the start.
Method AssertJoined(ref As %String, session As %Integer, super As %String, label As %String) [ Private ]
{
	Set taskId = ..WaitTask(ref, 10)
	Do $$$AssertTrue(taskId '= "", label_" the task exists")
	Set holdId = ##class(OcuTalon.Bridge.Approval).LiveHold(ref)
	Set hold = ##class(OcuTalon.Bridge.Process.ApprovalHold).%OpenId(holdId)
	Do $$$AssertTrue($IsObject(hold), label_" the hold is live")
	If $IsObject(hold) Do $$$AssertEquals(hold.%SessionId_"|"_hold.%SuperSession, session_"|"_super, label_" the hold is in the session with the SuperSession")
	If taskId '= "" {
		Set header = ..TaskHeader(taskId)
		Do $$$AssertEquals(header.session_"|"_header.super, session_"|"_super, label_" the task's message is too")
	}
}

/// The headers of the hold that Raise started after the mark, as {"session", "start", "task", "alarm"}; each header is {"id", "session",
/// "super", "bodyId"}. The session is the one of the ApprovalStart that names the Ref.
ClassMethod HoldMessages(mark As %Integer, ref As %String) As %DynamicObject
{
	Set messages = {"session": "", "start": {}, "task": {}, "alarm": {}}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SessionId, SuperSession, MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = 'OcuTalon.Bridge.Msg.ApprovalStart' AND SourceConfigName = 'ApprovalStartIn' AND TargetConfigName = 'ApprovalHold' ORDER BY ID", mark)
	While result.%Next() {
		Set body = ##class(OcuTalon.Bridge.Msg.ApprovalStart).%OpenId(result.%Get("MessageBodyId"))
		If '$IsObject(body) || (body.Ref '= ref) Continue
		Set messages.session = result.%Get("SessionId")
		Set messages.start = {"id": (result.%Get("ID")), "session": (result.%Get("SessionId")), "super": (result.%Get("SuperSession")), "bodyId": (result.%Get("MessageBodyId"))}
	}
	If messages.session = "" Quit messages
	For part = "task|EnsLib.Workflow.TaskRequest|OcuTalonApprovals", "alarm|Ens.AlarmRequest|Ens.Alarm" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID, SessionId, SuperSession, MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = 'ApprovalHold' AND MessageBodyClassName = ? AND TargetConfigName = ? ORDER BY ID", messages.session, $Piece(part, "|", 2), $Piece(part, "|", 3))
		If result.%Next() Do messages.%Set($Piece(part, "|", 1), {"id": (result.%Get("ID")), "session": (result.%Get("SessionId")), "super": (result.%Get("SuperSession")), "bodyId": (result.%Get("MessageBodyId"))})
	}
	Quit messages
}

/// The header of the TaskRequest of the task, as {"session", "super", "source", "bp"}.
Method TaskHeader(taskId As %String) As %DynamicObject [ Private ]
{
	Set header = {"session": "", "super": "", "source": "", "bp": ""}
	Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(taskId)
	If '$IsObject(task) Quit header
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT SessionId, SuperSession, SourceConfigName, BusinessProcessId FROM Ens.MessageHeader WHERE MessageBodyClassName = 'EnsLib.Workflow.TaskRequest' AND MessageBodyId = ?", task.%TaskStatus.Request.%Id())
	If result.%Next() {
		Set header.session = result.%Get("SessionId")
		Set header.super = result.%Get("SuperSession")
		Set header.source = result.%Get("SourceConfigName")
		Set header.bp = result.%Get("BusinessProcessId")
	}
	Quit header
}

/// The session of the task's TaskRequest.
Method TaskSession(taskId As %String) As %Integer [ Private ]
{
	Quit ..TaskHeader(taskId).session
}

/// The ids of the tasks that carry the Ref in their subject, oldest first, as a list.
ClassMethod TaskIds(ref As %String, openOnly As %Boolean = 0) As %List
{
	Set ids = ""
	Set sql = "SELECT ID FROM EnsLib_Workflow.TaskResponse WHERE %Subject = ?"_$Select(openOnly: " AND TaskStatus_IsComplete = 0", 1: "")_" ORDER BY ID"
	Set result = ##class(%SQL.Statement).%ExecDirect(, sql, ##class(OcuTalon.Bridge.Approval).#TASKSUBJECT_ref)
	While result.%Next() {
		Set ids = ids _ $ListBuild(result.%GetData(1))
	}
	Quit ids
}

/// The id of the one open task of the Ref, or "" (none), or the ids as a comma list when there are several.
ClassMethod OpenTasks(ref As %String) As %String [ Private ]
{
	Quit $ListToString(..TaskIds(ref, 1), ",")
}

/// The number of tasks, open or not, of the Ref.
ClassMethod TaskCount(ref As %String) As %Integer [ Private ]
{
	Quit $ListLength(..TaskIds(ref))
}

/// The id of the open task of the Ref once it exists (polled up to the seconds), or "".
ClassMethod WaitTask(ref As %String, seconds As %Integer) As %String
{
	Set deadline = $ZHorolog + seconds
	Set id = ..OpenTasks(ref)
	While (id = "") && ($ZHorolog < deadline) {
		Hang 0.1
		Set id = ..OpenTasks(ref)
	}
	Quit id
}

/// 1 when the UTC time YYYY-MM-DDThh:mm:ssZ is a readable time within the last 5 seconds (an empty or unreadable time is 0).
ClassMethod JustNow(stamp As %String) As %Boolean [ Private ]
{
	If stamp '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" Quit 0
	Set age = ##class(OcuTalon.Bridge.Time).SecondsUntil(stamp)
	Quit (age '< -5) && (age '> 0)
}

/// 1 once the hold of the Ref has gone, at least one response (the TaskResponse or the timer's alarm) has reached it in the session, and no
/// message to it in that session is still created, queued or delivered, which is when its OnResponse has returned (polled up to the seconds),
/// otherwise 0. The response must exist, so that a wrong session or a response that never came cannot pass as settled. A test that expects the
/// hold to have sent nothing reads after it.
ClassMethod WaitHoldSettled(ref As %String, session As %String, seconds As %Integer) As %Boolean
{
	Set deadline = $ZHorolog + seconds
	Set settled = 0
	For {
		If ##class(OcuTalon.Bridge.Approval).LiveHold(ref) = "" {
			Set open = 1
			Set responded = 0
			Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT SUM(CASE WHEN Status IN (1, 2, 3) THEN 1 ELSE 0 END), SUM(CASE WHEN Type = 2 THEN 1 ELSE 0 END) FROM Ens.MessageHeader WHERE SessionId = ? AND TargetConfigName = 'ApprovalHold'", session)
			If result.%Next() {
				Set open = +result.%GetData(1)
				Set responded = +result.%GetData(2)
			}
			If (open = 0) && (responded > 0) {
				Set settled = 1
				Quit
			}
		}
		If $ZHorolog >= deadline Quit
		Hang 0.1
	}
	Quit settled
}

/// 1 once no hold of the Ref is live (polled up to the seconds), otherwise 0.
ClassMethod WaitHoldGone(ref As %String, seconds As %Integer) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While (##class(OcuTalon.Bridge.Approval).LiveHold(ref) '= "") && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Quit ##class(OcuTalon.Bridge.Approval).LiveHold(ref) = ""
}

/// Waits (up to the seconds) for the global node to be set.
ClassMethod WaitNode(node As %String, seconds As %Integer) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While ($Get(@node) = "") && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

/// The names of the users who have a worklist item for the task, as a comma list.
ClassMethod WorklistUsers(taskId As %String) As %String [ Private ]
{
	Set users = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT UserName FROM EnsLib_Workflow.Worklist WHERE Task = ? ORDER BY UserName", taskId)
	While result.%Next() {
		Set users = users _ $Select(users = "": "", 1: ",") _ result.%GetData(1)
	}
	Quit users
}

/// Completes the task as Answer does: assigned to OcuTalonWorkflow, then completed with Approve.
ClassMethod Complete(taskId As %String) As %Status [ Private ]
{
	Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(taskId)
	If '$IsObject(task) Quit $SYSTEM.Status.Error(5001, "task "_taskId_" does not exist")
	Set sc = task.AssignTask(##class(OcuTalon.Bridge.Approval).#WORKFLOWUSER)
	If $$$ISERR(sc) Quit sc
	Quit task.CompleteTask("Approve")
}

/// The live hold of the Ref as an object, or "".
Method Hold(ref As %String) As OcuTalon.Bridge.Process.ApprovalHold [ Private ]
{
	Set id = ##class(OcuTalon.Bridge.Approval).LiveHold(ref)
	If id = "" Quit ""
	Quit ##class(OcuTalon.Bridge.Process.ApprovalHold).%OpenId(id)
}

/// The completion keys that the hold waits for, sorted, as a comma list.
ClassMethod Keys(hold As OcuTalon.Bridge.Process.ApprovalHold) As %String [ Private ]
{
	Set keys = ""
	For i = 1:1:hold.%MasterPendingResponses.Count() {
		Set sorted(hold.%MasterPendingResponses.GetAt(i).CompletionKey) = ""
	}
	Set key = ""
	For {
		Set key = $Order(sorted(key))
		Quit:key=""
		Set keys = keys _ $Select(keys = "": "", 1: ",") _ key
	}
	Quit keys
}

/// The seconds that the timer of the hold's session asks for: the AlarmRequest that ApprovalHold sent in the session.
ClassMethod TimerSeconds(session As %Integer) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = 'ApprovalHold' AND MessageBodyClassName = 'Ens.AlarmRequest' ORDER BY ID", session)
	If 'result.%Next() Quit ""
	Set alarm = ##class(Ens.AlarmRequest).%OpenId(result.%GetData(1))
	Quit $Select($IsObject(alarm): $Select(alarm.Timeout '= "": +alarm.Timeout, 1: +alarm.DurationInSeconds), 1: "")
}

/// ^Ens.Alarm's entry for the AlarmRequest header, as the stored $ListBuild (wake time, header id, ...), or "". Ens.Alarm stores the entry
/// when it handles the request, so the entry is polled for up to the seconds.
ClassMethod AlarmEntry(headerId As %String, seconds As %Integer = 0) As %List [ Private ]
{
	Set deadline = $ZHorolog + seconds
	For {
		Set id = ""
		For {
			Set id = $Order(^Ens.Alarm(id), 1, data)
			Quit:id=""
			If $ListGet(data, 2) = headerId Quit
		}
		If (id '= "") || ($ZHorolog >= deadline) Quit
		Hang 0.1
	}
	Quit $Select(id '= "": data, 1: "")
}

/// Moves a fixture row's RaisedAt back by raisedAgo seconds and sets ExpiresAt expiresIn seconds from now (negative: in the past). Only a
/// test does this; the row's State never changes.
ClassMethod Age(ref As %String, raisedAgo As %Integer, expiresIn As %Integer)
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Set now = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set row.RaisedAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(now, 0 - raisedAgo)
	Set row.ExpiresAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(now, expiresIn)
	Do row.%Save()
}

/// The number of ApprovalRequest rows.
ClassMethod RowCount() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ApprovalRequest")
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The number of ApprovalHold instances, of the Ref when there is one (live or not).
ClassMethod HoldCount(ref As %String = "") As %Integer
{
	If ref = "" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Process.ApprovalHold")
	} Else {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Process.ApprovalHold WHERE Ref = ?", ref)
	}
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The number of ApprovalStart messages sent to ApprovalHold after the header mark.
ClassMethod StartsSince(mark As %Integer) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = 'OcuTalon.Bridge.Msg.ApprovalStart'", mark)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The Ref of the first ApprovalStart message sent after the header mark, or "".
ClassMethod StartRef(mark As %Integer) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = 'OcuTalon.Bridge.Msg.ApprovalStart' ORDER BY ID", mark)
	If 'result.%Next() Quit ""
	Set body = ##class(OcuTalon.Bridge.Msg.ApprovalStart).%OpenId(result.%GetData(1))
	Quit $Select($IsObject(body): body.Ref, 1: "")
}

/// 1 once ApprovalHold has handled the first ApprovalStart message sent after the header mark (its status is past created, queued and
/// delivered; polled up to the seconds), otherwise 0.
ClassMethod WaitStartDone(mark As %Integer, seconds As %Integer) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + seconds
	For {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Status FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = 'OcuTalon.Bridge.Msg.ApprovalStart' ORDER BY ID", mark)
		Set status = $Select(result.%Next(): result.%GetData(1), 1: "")
		Set done = (status '= "") && '$ListFind($ListBuild(1, 2, 3), status)
		If done || ($ZHorolog >= deadline) Quit
		Hang 0.1
	}
	Quit done
}

/// Settles the fixture row of the Ref (State approved), with no answer fields.
ClassMethod Settle(ref As %String) As %Status [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If '$IsObject(row) Quit $SYSTEM.Status.Error(5001, "no row has the Ref "_ref)
	Set row.State = "approved"
	Quit row.%Save()
}

/// "<%Status>|<IsComplete>|<TimeCompleted>|<worklist users>" of the task, read again from the database.
ClassMethod TaskState(taskId As %String) As %String [ Private ]
{
	Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(taskId)
	If '$IsObject(task) Quit "<none>"
	Quit task.%Status_"|"_task.%TaskStatus.IsComplete_"|"_task.%TaskStatus.TimeCompleted_"|"_..WorklistUsers(taskId)
}

/// Makes an open task of the fixture Workflow role ZzApprovalOther<n>, which no hold sent, and tracks the role and the task for the cleanup.
/// Returns the task's id, or "".
Method OtherRoleTask() As %String [ Private ]
{
	Set role = "ZzApprovalOther"_..Number
	Set ^OcuTalonTest("Approval", "other", role) = ""
	If '##class(EnsLib.Workflow.RoleDefinition).%ExistsId(role) && $$$ISERR(##class(EnsLib.Workflow.RoleDefinition).CreateRole(role)) Quit ""
	Set request = ##class(EnsLib.Workflow.TaskRequest).%New()
	Set request.%Subject = role_" task"
	If $$$ISERR(request.%Save()) Quit ""
	Set task = ##class(EnsLib.Workflow.TaskResponse).%New()
	Set task.%Subject = request.%Subject
	Set task.%TaskStatus.Role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(role)
	Set task.%TaskStatus.Request = request
	If $$$ISERR(task.%Save()) Quit ""
	Set ^OcuTalonTest("Approval", "other", role, task.%Id()) = request.%Id()
	Quit task.%Id()
}

/// Deletes the fixture Workflow roles of OtherRoleTask and their tasks, also those a failed earlier run left.
ClassMethod RemoveOther() [ Private ]
{
	Set role = ""
	For {
		Set role = $Order(^OcuTalonTest("Approval", "other", role))
		Quit:role=""
		Set taskId = ""
		For {
			Set taskId = $Order(^OcuTalonTest("Approval", "other", role, taskId), 1, requestId)
			Quit:taskId=""
			Do ##class(EnsLib.Workflow.TaskResponse).%DeleteId(taskId)
			Do ##class(EnsLib.Workflow.TaskRequest).%DeleteId(requestId)
		}
		Do ##class(EnsLib.Workflow.RoleDefinition).%DeleteId(role)
	}
	Kill ^OcuTalonTest("Approval", "other")
}

/// Ends every request that a test tracked, also those a failed earlier run left: it enables ApprovalStartIn, ApprovalHold and
/// OcuTalonApprovals again if a killed run left one disabled, releases the row locks that the test process holds (tracked under
/// ^OcuTalonTest("Approval","held")), waits for every job to be done (a job that is still waiting for a lock is released first), ends each
/// request and deletes its row, deletes the fixture Workflow roles, and kills the shared sink's calls.
ClassMethod Clean()
{
	For item = "ApprovalStartIn", "ApprovalHold", "OcuTalonApprovals" {
		Set status = $$$OK
		If '##class(Ens.Director).IsItemEnabled(item, .status) && $$$ISOK(status) Do ##class(Ens.Director).EnableConfigItem(item, 1)
	}
	Set held = ""
	For {
		Set held = $Order(^OcuTalonTest("Approval", "held", held))
		Quit:held=""
		Lock -^OcuTalon.Bridge.Approval(held)
	}
	Kill ^OcuTalonTest("Approval", "held")
	Set number = ""
	For {
		Set number = $Order(^OcuTalonTest("Approval", "job", number))
		Quit:number=""
		If ($Get(^OcuTalonTest("Approval", "job", number, "locked")) || $Get(^OcuTalonTest("Approval", "job", number, "spawned"))) && '$Get(^OcuTalonTest("Approval", "job", number, "done")) {
			Set ^OcuTalonTest("Approval", "job", number, "release") = 1
			Do ..WaitNode($Name(^OcuTalonTest("Approval", "job", number, "done")), 20)
		}
	}
	Kill ^OcuTalonTest("Approval", "job")
	Kill ^OcuTalonTest("ProbeSink")
	Set ref = ""
	For {
		Set ref = $Order(^OcuTalonTest("Approval", "refs", ref))
		Quit:ref=""
		Do ..Remove(ref)
	}
	Do ..RemoveOther()
}

/// Ends the hold of the Ref by completing its open tasks, waits for it to end (a hold that is still live without an open task is deleted),
/// deletes the row and forgets the Ref.
ClassMethod Remove(ref As %String) [ Private ]
{
	Set ids = ..TaskIds(ref, 1)
	Set position = 0
	While $ListNext(ids, position, id) {
		Do ..Complete(id)
	}
	If '..WaitHoldGone(ref, 15) {
		Do ##class(OcuTalon.Bridge.Process.ApprovalHold).%DeleteId(##class(OcuTalon.Bridge.Approval).LiveHold(ref))
	}
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If $IsObject(row) Do ##class(OcuTalon.Bridge.Data.ApprovalRequest).%DeleteId(row.%Id())
	Kill ^OcuTalonTest("Approval", "refs", ref)
}

/// Tracks every approval row of the owner under ^OcuTalonTest("Approval","refs"), so that Clean ends its hold and deletes it. A test of another
/// class (Test.Bridge.Gate) that makes the gate raise requests tracks its owners, because the gate does not return the Ref.
ClassMethod TrackOwner(owner As %String)
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE OwnerRef = ?", owner)
	While result.%Next() {
		Set ^OcuTalonTest("Approval", "refs", result.%Get("Ref")) = ""
	}
}

/// --- the helpers of Story 3.7's tests ---
/// The data of an Approval entry, as the test expects it: the members of the Approval shape and the three of every entry.
ClassMethod Want(ref As %String, kind As %String, change As %String, from As %String, to As %String, outcome As %String, target As %String, ownerRef As %String, irisUser As %String, sessionRef As %String, channel As %String) As %DynamicObject [ Private ]
{
	Set want = {}
	Do want.%Set("ref", ref, "string")
	Do want.%Set("kind", kind, "string")
	Do want.%Set("change", change, "string")
	Do want.%Set("from", from, "string")
	Do want.%Set("to", to, "string")
	Do want.%Set("outcome", outcome, "string")
	Do want.%Set("target", target, "string")
	Do want.%Set("ownerRef", ownerRef, "string")
	Do want.%Set("irisUser", irisUser, "string")
	Do want.%Set("sessionRef", sessionRef, "string")
	Do want.%Set("channel", channel, "string")
	Quit want
}

/// Asserts an entry read back from the audit log: the data has exactly the members of the Approval shape with the wanted values, the description
/// is the one derived from them, the time is between the mark and now, and the writing user is username (default: this process's $Username; ""
/// does not check it).
Method AssertEntry(entry As %DynamicObject, mark As %String, want As %DynamicObject, label As %String, username As %String = {$Username}) [ Private ]
{
	Set data = entry.data
	Do $$$AssertTrue($IsObject(data), label_": the data is JSON")
	If '$IsObject(data) Quit
	Set shape = ##class(OcuTalon.Bridge.Audit).Shape("Approval")
	Do $$$AssertEquals(data.%Size(), $ListLength(shape), label_": the data has exactly the "_$ListLength(shape)_" members of the Approval shape")
	Set position = 0
	While $ListNext(shape, position, name) {
		Do $$$AssertEquals(data.%Get(name), want.%Get(name), label_": "_name_" is "_want.%Get(name))
	}
	Do $$$AssertEquals(entry.description, "Approval "_want.ref_" "_want.change_": "_want.to, label_": the description is derived from the data")
	Do $$$AssertTrue((entry.at ] mark) || (entry.at = mark), label_": the time "_entry.at_" is not before the mark "_mark)
	Do $$$AssertTrue('(entry.at ] ##class(OcuTalon.Test.Bridge.AuditLog).Now()), label_": and not after now")
	If username '= "" Do $$$AssertEquals(entry.username, username, label_": the entry is written by the user "_username)
}

/// Waits for the one Approval entry that carries the Ref of want, asserts that it is the only one, and asserts it.
Method AssertOneEntry(mark As %String, want As %DynamicObject, label As %String) [ Private ]
{
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Approval", "Approval", want.ref)
	Do $$$AssertEquals(entries.%Size(), 1, label_": one Approval entry carries the Ref "_want.ref)
	If entries.%Size() = 1 Do ..AssertEntry(entries.%Get(0), mark, want, label)
}

/// Asserts that no Approval entry carries the Ref since the mark. Entries are written before the call returns and are readable at once. So that
/// the check cannot pass because the read sees nothing of its window, it first writes an Action entry with a fresh marker and waits until the
/// same read from the same mark finds it, and only then reads for the Ref, whose entry, if any, was written before the control's.
Method AssertNoEntry(mark As %String, ref As %String, label As %String) [ Private ]
{
	Set control = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set data = {"action": "control", "target": (control), "result": "written", "counts": {}, "approvalRef": "", "irisUser": "ocutalon", "sessionRef": "", "channel": "system"}
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Audit).Record("Action", data), label_": control: an entry of the same window is written")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", control).%Size(), 1, label_": control: the same read from the same mark finds that entry")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Approval", "Approval", ref).%Size(), 0, label)
}

/// The Enabled flag of the Approval audit event, 1 or 0, or "" when it does not exist (Test.Bridge.AuditLog EventState).
ClassMethod AuditEventState() As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Bridge.AuditLog).EventState(..#AUDITEVENT)
}

/// Sets the Enabled flag of the Approval audit event (Test.Bridge.AuditLog SetEvent). A test that disables it sets AuditEventOff first, so that
/// OnAfterOneTest enables it again.
ClassMethod SetAuditEvent(enabled As %Boolean) [ Private ]
{
	Do ##class(OcuTalon.Test.Bridge.AuditLog).SetEvent(..#AUDITEVENT, enabled)
}

/// --- the helpers of Story 3.5's tests ---
/// The README account, the local install's real approver (Install.Step.Users); asserted to hold OcuTalonUser, else "".
Method Answerer() As %String [ Private ]
{
	Set user = ..#ANSWERER
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet(user, .roles)
	Set holds = $$$ISOK(sc) && ''$ListFind($ListFromString(roles), "OcuTalonUser")
	Do $$$AssertTrue(holds, "the answerer "_user_" holds OcuTalonUser")
	Quit $Select(holds: user, 1: "")
}

/// Raises a held request of the kind, tracks it, waits for its task and returns {"ref","owner","trace","incident","session","task"} (session is the
/// hold's, task the open task's id); the sink's calls are cleared. A tool_call has no ResultTarget unless one is given. "" when Raise fails.
Method RaiseHeld(kind As %String, resultTarget As %String = "<none>") As %DynamicObject [ Private ]
{
	Set row = ..NewRow(kind)
	If resultTarget '= "<none>" Set row.ResultTarget = resultTarget
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Set sc = ..Raise(row, .ref)
	Do $$$AssertStatusOK(sc, "the "_kind_" request is raised")
	If $$$ISERR(sc) Quit ""
	Set info = {"ref": (ref), "owner": (row.OwnerRef), "trace": (row.TraceRef), "incident": (row.IncidentRef), "session": "", "task": ""}
	Kill row
	Set info.task = ..WaitTask(ref, 10)
	Do $$$AssertTrue(info.task '= "", "its task exists")
	Set info.session = ..HoldMessages(mark, ref).session
	Kill ^||ZzProbeSink
	Quit info
}

/// Saves a fixture row directly in the state, with no hold and no task (RequiredRole OcuTalonUser, ExpiresAt expiresIn seconds from now), tracks it
/// and returns its Ref. An answered state has its Answered fields, a finished one its Result and FinishedAt.
Method FixtureRow(state As %String, expiresIn As %Integer = 3600, kind As %String = "fix") As %String [ Private ]
{
	Set row = ..NewRow(kind)
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ^OcuTalonTest("Approval", "refs", ref) = ""
	Set now = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set row.Ref = ref
	Set row.State = state
	Set row.RequiredRole = "OcuTalonUser"
	Set row.RaisedAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(now, -60)
	Set row.ExpiresAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(now, expiresIn)
	If $ListFind($ListBuild("approved", "rejected", "executing", "done", "failed"), state) {
		Set row.AnsweredAction = $Select(state = "rejected": "reject", 1: "approve")
		Set row.AnsweredChannel = "web"
		Set row.AnsweredBy = ..#ANSWERER
		Set row.AnsweredAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(now, -30)
	}
	If (state = "done") || (state = "failed") {
		Set row.Result = state
		Set row.FinishedAt = now
	}
	Do $$$AssertStatusOK(row.%Save(), "the fixture row "_state_" is saved")
	Quit ref
}

/// The column of the row, read again from the database (the instance is not kept).
ClassMethod Prop(ref As %String, name As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If '$IsObject(row) Quit "<no row>"
	Quit $Property(row, name)
}

/// All the columns of the row but those in skip (a comma list), as "name=value|" text.
ClassMethod RowText(ref As %String, skip As %String = "") As %String [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If '$IsObject(row) Quit "<no row>"
	Set text = ""
	Set names = "Ref,Kind,IncidentRef,OwnerRef,State,DryRun,ToolName,ToolArguments,RequiredRole,ResultTarget,TraceRef,RaisedAt,ExpiresAt,AnsweredAction,AnsweredChannel,AnsweredBy,AnsweredAt,Result,FinishedAt"
	For index = 1:1:$Length(names, ",") {
		Set name = $Piece(names, ",", index)
		If $ListFind($ListFromString(skip), name) Continue
		Set text = text _ name _ "=" _ $Property(row, name) _ "|"
	}
	Quit text
}

/// The text of RowText that was taken without skip, with the skipped columns taken out.
ClassMethod SkipText(text As %String, skip As %String) As %String [ Private ]
{
	Set result = ""
	For index = 1:1:$Length(text, "|") - 1 {
		Set part = $Piece(text, "|", index)
		If $ListFind($ListFromString(skip), $Piece(part, "=", 1)) Continue
		Set result = result _ part _ "|"
	}
	Quit result
}

/// "<%Action>|<%UserName>|<IsComplete>|<worklist users>" of the task.
ClassMethod TaskFacts(taskId As %String) As %String [ Private ]
{
	Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(taskId)
	If '$IsObject(task) Quit "<none>"
	Quit task.%Action_"|"_task.%UserName_"|"_task.%TaskStatus.IsComplete_"|"_..WorklistUsers(taskId)
}

/// The row's State once it is the given one (polled up to the seconds), else the State at the deadline. The hold counts as ended while its
/// OnResponse still runs, so a test that needs the timer's change waits for it.
Method WaitState(ref As %String, state As %String, seconds As %Integer) As %String [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While (..Prop(ref, "State") '= state) && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Quit ..Prop(ref, "State")
}

/// The ApprovalOutcome messages that ApprovalHold sent for the Ref after this run began, oldest first, as a dynamic array of {"session","super",
/// "target","status","outcome","approvalRef","incidentRef"}.
Method Outcomes(ref As %String) As %DynamicArray [ Private ]
{
	Set list = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT SessionId, SuperSession, TargetConfigName, Status, MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = 'OcuTalon.Bridge.Msg.ApprovalOutcome' AND SourceConfigName = 'ApprovalHold' ORDER BY ID", ..Mark)
	While result.%Next() {
		Set body = ##class(OcuTalon.Bridge.Msg.ApprovalOutcome).%OpenId(result.%Get("MessageBodyId"))
		If '$IsObject(body) || (body.ApprovalRef '= ref) Continue
		Do list.%Push({"session": (result.%Get("SessionId")), "super": (result.%Get("SuperSession")), "target": (result.%Get("TargetConfigName")), "status": (result.%Get("Status")), "outcome": (body.Outcome), "approvalRef": (body.ApprovalRef), "incidentRef": (body.IncidentRef)})
	}
	Quit list
}

/// The outcomes of the Ref once at least count exist and the target has handled each (its header is past created, queued and delivered), polled up
/// to the seconds; whatever exists at the deadline otherwise.
Method WaitOutcomes(ref As %String, count As %Integer, seconds As %Integer) As %DynamicArray [ Private ]
{
	Set deadline = $ZHorolog + seconds
	For {
		Set list = ..Outcomes(ref)
		Set handled = (list.%Size() '< count)
		For index = 0:1:list.%Size() - 1 {
			If $ListFind($ListBuild(1, 2, 3), list.%Get(index).status) Set handled = 0
		}
		If handled || ($ZHorolog >= deadline) Quit
		Hang 0.1
	}
	Quit list
}

/// Exactly one outcome of the Ref once its target IncidentManager has handled the first, with the outcome, the Ref, the incident and the hold's
/// SuperSession (the TraceRef); session is the hold's session ("" skips that check).
Method AssertOneOutcome(ref As %String, outcome As %String, info As %DynamicObject, session As %String, label As %String) [ Private ]
{
	Set list = ..WaitOutcomes(ref, 1, 15)
	Do $$$AssertEquals(list.%Size(), 1, label_": exactly one outcome is sent")
	If list.%Size() '= 1 Quit
	Set one = list.%Get(0)
	Do $$$AssertEquals(one.outcome_"|"_one.approvalRef_"|"_one.incidentRef_"|"_one.target, outcome_"|"_ref_"|"_info.incident_"|IncidentManager", label_": it is "_outcome_" for the Ref and the incident, to IncidentManager")
	Do $$$AssertEquals(one.super, info.trace, label_": it carries the TraceRef as SuperSession")
	If session '= "" Do $$$AssertEquals(one.session, session, label_": it is in the hold's session")
	Do $$$AssertNotTrue($ListFind($ListBuild(1, 2, 3), one.status), label_": the target has handled it")
}

/// The classes of the requests that the hold of the session sent, sorted, as a comma list.
ClassMethod HoldRequests(session As %String) As %String
{
	Set classes = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyClassName FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = 'ApprovalHold' AND Type = 1 ORDER BY MessageBodyClassName", session)
	While result.%Next() {
		Set classes = classes _ $Select(classes = "": "", 1: ",") _ result.%GetData(1)
	}
	Quit classes
}

/// The sink's private calls are exactly the event types, as a comma list.
Method AssertEvents(types As %String, label As %String) [ Private ]
{
	Set actual = ""
	For n = 1:1:+$Get(^||ZzProbeSink) {
		Set actual = actual _ $Select(actual = "": "", 1: ",") _ $List($Get(^||ZzProbeSink(n)), 1)
	}
	Do $$$AssertEquals(actual, types, label_" got the events "_types)
}

/// The sink's private call n: the type, the owner, {"ref"}, and the State of the row at that moment (ProbeSink's eighth element).
Method AssertEvent(n As %Integer, type As %String, owner As %String, ref As %String, state As %String, label As %String) [ Private ]
{
	Set call = $Get(^||ZzProbeSink(n))
	Do $$$AssertEquals($ListGet(call, 1)_"|"_$ListGet(call, 2)_"|"_$ListGet(call, 3), type_"|"_owner_"|{""ref"":"""_ref_"""}", label_": call "_n_" is "_type_" with the OwnerRef and the Ref")
	Do $$$AssertEquals($ListGet(call, 4)_"|"_$ListGet(call, 5)_"|"_$ListGet(call, 8), "0|1|"_state, label_": call "_n_" came at transaction level 0, after the change: the row was "_state)
}

/// What Expected says for a fixture of the key and the call of TestEveryOtherTransitionIsRefused, as $ListBuild(kind, new state or the state, event):
/// kind is skip (another test pins it), refused, changed, or the result of Answer.
ClassMethod Expected(key As %String, op As %String) As %List [ Private ]
{
	Set state = $Select(key = "approvedPast": "approved", 1: key)
	Set verb = $Piece(op, " ", 1)
	Set arg = $Piece(op, " ", 2)
	If verb = "answer" {
		If state = "pending" Quit $ListBuild("skip")
		Quit $ListBuild($Select(state = "expired": "expired", state = "cancelled": "not_found", 1: "already_answered"), state, "")
	}
	If verb = "expire" Quit $Select(state = "pending": $ListBuild("changed", "expired", "approval.expired"), 1: $ListBuild("refused", state, ""))
	If verb = "cancel" Quit $Select(state = "pending": $ListBuild("skip"), 1: $ListBuild("refused", state, ""))
	If verb = "start" Quit $Select(key = "approved": $ListBuild("changed", "executing", ""), 1: $ListBuild("refused", state, ""))
	If (arg = "done") && (state = "executing") Quit $ListBuild("changed", "done", "approval.result")
	If (arg = "failed") && ((state = "executing") || (state = "approved")) Quit $ListBuild("changed", "failed", "approval.result")
	If (arg = "interrupted") && (state = "executing") Quit $ListBuild("changed", "failed", "approval.result")
	Quit $ListBuild("refused", state, "")
}

/// Makes the call alone, with ProbeSink as the sink: $ListBuild(code, text). For Answer the code is its result and the text the winner as JSON;
/// for the status methods the code is OK or ERR and the text the error.
Method Run(op As %String, ref As %String, user As %String, Output winner As %DynamicObject) As %List [ Private ]
{
	Set winner = {}
	Set api = "OcuTalon.Bridge.Approval"
	Set verb = $Piece(op, " ", 1)
	Set arg = $Piece(op, " ", 2)
	If verb = "answer" {
		Set code = $ClassMethod(api, "Answer", ref, arg, "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK)
		Quit $ListBuild(code, winner.%ToJSON())
	}
	If verb = "expire" {
		Set sc = $ClassMethod(api, "Expire", ref, ..#SINK)
	} ElseIf verb = "cancel" {
		Set sc = $ClassMethod(api, "Cancel", ref, ..#SINK)
	} ElseIf verb = "start" {
		Set sc = $ClassMethod(api, "StartExecution", ref)
	} Else {
		Set sc = $ClassMethod(api, "FinishExecution", ref, arg, ..#SINK)
	}
	Quit $ListBuild($Select($$$ISOK(sc): "OK", 1: "ERR"), $SYSTEM.Status.GetErrorText(sc))
}

/// Sets Decide's HostSinkClass to ProbeSink in its shared mode, for the events that fire in the production's jobs, and saves what the item had
/// for OnAfterOneTest. 1 when it is set.
Method UseSharedSink() As %Boolean [ Private ]
{
	Kill ^OcuTalonTest("ProbeSink")
	Set ^OcuTalonTest("ProbeSink", "shared") = 1
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).UseItemSetting("Decide", "Host", "HostSinkClass", ..#SINK, .saved)
	Set ..SavedSink = saved
	Do $$$AssertStatusOK(sc, "Decide's HostSinkClass is ProbeSink in its shared mode")
	Quit $$$ISOK(sc)
}

/// Starts a job that calls Answer (kind answer) or StartExecution (kind start) and returns its number; ^OcuTalonTest("Approval","job",<n>) gets
/// its pid, result, winner and done.
ClassMethod StartJob(kind As %String, ref As %String, action As %String = "", channel As %String = "", user As %String = "") As %String [ Private ]
{
	Set number = "j"_$Increment(^OcuTalonTest("Approval", "jobs"))
	Kill ^OcuTalonTest("Approval", "job", number)
	Set ^OcuTalonTest("Approval", "job", number, "spawned") = 1
	Job ##class(OcuTalon.Test.Bridge.Approval).CallInJob(number, kind, ref, action, channel, user)
	Quit number
}

/// The job body: calls Answer or StartExecution with no sink argument, so that the event goes to Decide's HostSinkClass, and records its
/// pid, result, winner and done.
ClassMethod CallInJob(number As %String, kind As %String, ref As %String, action As %String, channel As %String, user As %String)
{
	Set run = $Name(^OcuTalonTest("Approval", "job", number))
	Try {
		Set @run@("pid") = $Job
		If kind = "answer" {
			Set result = ##class(OcuTalon.Bridge.Approval).Answer(ref, action, channel, user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner)
			Set @run@("result") = result
			Set @run@("winner") = winner.%ToJSON()
		} Else {
			Set sc = ##class(OcuTalon.Bridge.Approval).StartExecution(ref)
			Set @run@("result") = $Select($$$ISOK(sc): "OK", 1: $SYSTEM.Status.GetErrorText(sc))
		}
	} Catch exception {
		Set @run@("error") = exception.DisplayString()
	}
	Set @run@("done") = 1
}

/// The lock gate: the test takes LOCK ^OcuTalon.Bridge.Approval(ref), starts one job for each entry of jobs ($ListBuild(kind, action, channel)),
/// releases the lock once every job waits for it (WaitWaiters; asserted, and released at its deadline otherwise), and waits for each job to be
/// done. Returns the job numbers, or "" when the test could not take the lock.
Method GateJobs(ref As %String, jobs As %List, user As %String) As %List [ Private ]
{
	Lock +^OcuTalon.Bridge.Approval(ref):5
	If '$Test {
		Do $$$AssertTrue(0, "the test takes the row's lock")
		Quit ""
	}
	Set ^OcuTalonTest("Approval", "held", ref) = ""
	Set numbers = ""
	Set position = 0
	While $ListNext(jobs, position, job) {
		Set numbers = numbers _ $ListBuild(..StartJob($List(job, 1), ref, $ListGet(job, 2), $ListGet(job, 3), user))
	}
	Set pids = ""
	Set position = 0
	While $ListNext(numbers, position, number) {
		Do ..WaitNode($Name(^OcuTalonTest("Approval", "job", number, "pid")), 20)
		Set pids = pids _ $ListBuild($Get(^OcuTalonTest("Approval", "job", number, "pid")))
	}
	Set seen = ""
	Do $$$AssertTrue(..WaitWaiters(ref, pids, 20, .seen), "every job waits for the row's lock: pids "_$ListToString(pids)_", waiters "_seen)
	Lock -^OcuTalon.Bridge.Approval(ref)
	Kill ^OcuTalonTest("Approval", "held", ref)
	Set position = 0
	While $ListNext(numbers, position, number) {
		Do ..WaitNode($Name(^OcuTalonTest("Approval", "job", number, "done")), 30)
	}
	Quit numbers
}

/// 1 once every pid of the list is waiting for the lock of the Ref (polled up to the seconds), otherwise 0. A pid waits when
/// %SYS.LockQuery:Detail lists it as a waiter of the Ref's lock, or, as the fallback, when %SYS.ProcessQuery gives its State as LOCKW: the jobs
/// of the gate take no other lock. seen is the last listing, as [pid/State] entries.
ClassMethod WaitWaiters(ref As %String, pids As %List, seconds As %Integer, Output seen As %String) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + seconds
	For {
		Kill found
		Set rs = ##class(%ResultSet).%New("%SYS.LockQuery:Detail")
		If $$$ISOK(rs.Execute()) {
			While rs.Next() {
				Set waiters = rs.Get("WaiterPID")
				If (waiters = "") || '((rs.Get("LockString") [ ref) || (rs.Get("FullReference") [ ref)) Continue
				For index = 1:1:$Length(waiters, ",") {
					Set found(+$Piece(waiters, ",", index)) = ""
				}
			}
		}
		Set seen = ""
		Set all = 1
		Set position = 0
		While $ListNext(pids, position, pid) {
			Set process = $Select(pid = "": "", 1: ##class(%SYS.ProcessQuery).%OpenId(pid))
			Set state = $Select($IsObject(process): process.State, 1: "gone")
			Set seen = seen _ "[" _ pid _ "/" _ state _ "]"
			If (pid = "") || ('$Data(found(+pid)) && (state '= "LOCKW")) Set all = 0
		}
		If all || ($ZHorolog >= deadline) Quit
		Hang 0.1
	}
	Quit all
}

}
