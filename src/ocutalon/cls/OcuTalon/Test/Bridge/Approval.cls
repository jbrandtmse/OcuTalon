/// Tests of Approval.Raise, the hold and its Reconcile (Story 3.4; AD-5, AD-11, AD-23, AD-26, AD-31). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI
/// ONLY (Rule 21): it raises requests through the running production, completes Workflow tasks as OcuTalonWorkflow, disables ApprovalStartIn or
/// ApprovalHold for a moment, restarts the production once, and writes a System Default Settings row of Decide's ApprovalRole. Each live test is
/// guarded by RunnerFixture.ReadyReason. The tests make no IRIS user or role. Every Ref a test raised is tracked under ^OcuTalonTest("Approval","refs"):
/// before and after each test, and so after a failed run too, each tracked request is ended (its open tasks are completed with Approve, as Story 3.5's
/// Answer will do, and the test waits for its hold to end, so that no late response reaches a removed hold) and its row is deleted; the same cleanup
/// enables the two items again, releases the lock job of TestLockHeld and deletes the fixture Workflow role of TestReconcileCancelsOnlyOrphans and its
/// task. Rows 12 and 13 move a fixture row's RaisedAt and ExpiresAt directly, and the Reconcile tests settle a fixture row (State approved), as
/// Story 3.5 will; no other test changes a row. The settings row, the item state and the Workflow objects that a test changed are put back.
///   - TestRaiseToolCall (rows 3 and 5): a tool_call request gives one pending row with the given fields, RequiredRole OcuTalonUser, RaisedAt now
///     and ExpiresAt exactly 24 hours later, a 22-character base64url Ref, and no other field; the three messages of the hold share one new
///     session whose SuperSession is the TraceRef; the sink got one approval.raised, with the OwnerRef and {"ref"}, at transaction level 0 and
///     with the row existing; the task of the hold has the actions Approve,Reject, the subject TASKSUBJECT plus the Ref, no UserName or Title, is
///     in OcuTalonApprovals unassigned with one worklist item for OcuTalonWorkflow; the timer asks 86,395 to 86,400 seconds and ^Ens.Alarm holds it;
///     one ApprovalHold waits for exactly the keys task and expiry;
///   - TestRaiseFix (row 4): the same for a fix request, with DryRun, IncidentRef and ResultTarget kept and the tool fields empty;
///   - TestOwnerRefKinds: a request owned by the literal instance or eval (AD-2) is held and keeps its OwnerRef;
///   - TestCallerSession (row 6): the hold's messages are in the caller's session and SuperSession, from a bridge context and from Raise's arguments;
///     an argument wins over the context's value, and each of the two is resolved on its own (only a session, only a SuperSession);
///   - TestApprovalRole (row 7): RequiredRole is the ApprovalRole setting; an empty setting refuses Raise, which creates nothing;
///   - TestRefused (row 8): every refusal names its field, leaves ref empty, and makes no row, no hold and no sink call;
///   - TestLockHeld (row 9): a lock that another job holds gives an error that names it after about two seconds, and nothing is created;
///   - TestStartFails (row 10): with ApprovalStartIn disabled, Raise returns the director's error and nothing is left;
///   - TestStartTimesOut (row 10, a timeout): with ApprovalHold disabled, Raise returns ApprovalStartIn's timeout after about STARTSECONDS and
///     nothing is left; once the item is enabled again the hold takes the late start, refuses it and holds nothing;
///   - TestRestartKeepsTheHold (row 11): after a production restart and the Reconcile step the same hold, task and timer remain, nothing new starts,
///     and completing the task ends that hold;
///   - TestReconcileReArms (row 12): a hold that is gone gets a new one in a new session tagged with the TraceRef, timed from the row's ExpiresAt,
///     its orphaned task is discarded, the new task reaches the new hold, and a second Reconcile changes nothing;
///   - TestReconcilePastExpiry (row 13): a row past its expiry gets a hold whose timer asks 1 second, which ends the hold and its task;
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
Parameter GIVENFIELDS = "Kind,OwnerRef,TraceRef,IncidentRef,ToolName,ToolArguments,ResultTarget,DryRun";

/// The run's number.
Property Number As %Integer;

/// The ApprovalRole row of Decide before the test touched it (RunnerFixture.RememberDefault).
Property Saved As %List;

/// 1 while the test has ApprovalStartIn disabled.
Property Disabled As %Boolean [ InitialExpression = 0 ];

/// 1 while the test has ApprovalHold disabled.
Property HoldDisabled As %Boolean [ InitialExpression = 0 ];

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("Approval", "n"))
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
	If ..Disabled {
		Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem("ApprovalStartIn", 1), "ApprovalStartIn is enabled again")
		Set ..Disabled = 0
	}
	If ..HoldDisabled {
		Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem("ApprovalHold", 1), "ApprovalHold is enabled again")
		Set ..HoldDisabled = 0
	}
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

/// An OwnerRef may be the literal instance or eval (AD-2): Raise holds such a request, keeps the OwnerRef and tells the sink.
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
	}
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
	Do $$$AssertStatusOK(saved.%Save(), "the row is settled (approved), as Story 3.5's Answer will leave it")

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
/// row has IncidentRef, ResultTarget IncidentManager and a DryRun. Both have new OwnerRef and TraceRef.
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
Method HoldMessages(mark As %Integer, ref As %String) As %DynamicObject [ Private ]
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
ClassMethod TaskIds(ref As %String, openOnly As %Boolean = 0) As %List [ Private ]
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
Method WaitTask(ref As %String, seconds As %Integer) As %String [ Private ]
{
	Set deadline = $ZHorolog + seconds
	Set id = ..OpenTasks(ref)
	While (id = "") && ($ZHorolog < deadline) {
		Hang 0.1
		Set id = ..OpenTasks(ref)
	}
	Quit id
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

/// Completes the task as Story 3.5's Answer will: assigned to OcuTalonWorkflow, then completed with Approve.
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
ClassMethod Age(ref As %String, raisedAgo As %Integer, expiresIn As %Integer) [ Private ]
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
ClassMethod HoldCount(ref As %String = "") As %Integer [ Private ]
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
ClassMethod StartsSince(mark As %Integer) As %Integer [ Private ]
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

/// Settles the fixture row of the Ref (State approved), as Story 3.5's Answer will leave it.
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

/// Ends every request that a test tracked, also those a failed earlier run left: it enables ApprovalStartIn and ApprovalHold again if a
/// killed run left one disabled, releases a lock job that still holds the lock, ends each request and deletes its row, and deletes the
/// fixture Workflow roles.
ClassMethod Clean() [ Private ]
{
	For item = "ApprovalStartIn", "ApprovalHold" {
		Set status = $$$OK
		If '##class(Ens.Director).IsItemEnabled(item, .status) && $$$ISOK(status) Do ##class(Ens.Director).EnableConfigItem(item, 1)
	}
	Set number = ""
	For {
		Set number = $Order(^OcuTalonTest("Approval", "job", number))
		Quit:number=""
		If $Get(^OcuTalonTest("Approval", "job", number, "locked")) && '$Get(^OcuTalonTest("Approval", "job", number, "done")) {
			Set ^OcuTalonTest("Approval", "job", number, "release") = 1
			Do ..WaitNode($Name(^OcuTalonTest("Approval", "job", number, "done")), 20)
		}
	}
	Kill ^OcuTalonTest("Approval", "job")
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

}
