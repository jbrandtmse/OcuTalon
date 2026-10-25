/// The approval API (AD-11): the only way an approval request changes state.
///   - Raise (Story 3.4) validates an unsaved ApprovalRequest, saves it as pending under its lock and starts its hold synchronously through
///     ApprovalStartIn; a failed Raise leaves no row, no hold and no event, and approval.raised fires once, after the unlock;
///   - Hold and HoldResponse are the logic of the business process ApprovalHold, which stores only the request's Ref (AD-5): Hold sends the
///     Workflow task to the role WORKFLOWROLE and sets the 24-hour timer, and replies to the start;
///   - Reconcile (declared by Install.Step.Approvals, AD-23) cancels the Workflow tasks that no live hold of a pending row owns and starts
///     a new hold for each pending row whose hold is gone, timed from the row's ExpiresAt.
/// Epic 0 fixed the other signatures with stub bodies so that callers compile against them: Story 3.5 builds Answer, Expire and Cancel,
/// and Story 3.6 builds StartExecution and FinishExecution (Story 7.3 completes the execution). A stub status method returns an error that
/// says it is not implemented yet, so that no caller can mistake a stub for a change that happened; Answer answers not_found.
Class OcuTalon.Bridge.Approval
{

/// The Workflow role that holds the approvals' tasks, and the one technical Workflow user that is its only member (AD-11). The role is also
/// the name of the production item that is its EnsLib.Workflow.Operation, which takes its role from its own name.
Parameter WORKFLOWROLE = "OcuTalonApprovals";

Parameter WORKFLOWUSER = "OcuTalonWorkflow";

/// The production item through which any job starts a hold, and the item that holds.
Parameter STARTITEM = "ApprovalStartIn";

Parameter HOLDITEM = "ApprovalHold";

/// The actions of the Workflow task, and the start of its subject, which the Ref follows (Story 3.5 finds the task by it).
Parameter ACTIONS = "Approve,Reject";

Parameter TASKSUBJECT = "OcuTalon approval request ";

/// How long a request lives before it expires: 24 hours (AD-11).
Parameter EXPIRYSECONDS = 86400;

/// How long Raise waits for the lock of the new Ref, and how long ApprovalStartIn waits for the hold to start, in seconds.
Parameter LOCKSECONDS = 2;

Parameter STARTSECONDS = 10;

/// Raises one approval request from the unsaved row, and returns its public Ref in ref. The three optional arguments come after the Epic 0 pair:
/// sinkClass is the host sink that receives approval.raised (empty: the HostSinkClass setting), and sessionId and superSession are the
/// caller's trace session and its SuperSession (AD-26); an empty one is taken from the bridge context of this process, and then a new
/// session is started, tagged with the row's TraceRef.
///   1. It refuses, before anything is written, a request that is not an unsaved ApprovalRequest, a Kind that is not one of Msg.Enum
///      APPROVALKIND, an OwnerRef that is neither a 22-character reference, instance nor eval, a tool_call without a ToolName or with
///      ToolArguments that are not a JSON object or with a DryRun, a fix without a DryRun that is a JSON object or without a ResultTarget or
///      with a ToolName or ToolArguments, an IncidentRef or TraceRef that is neither empty nor a reference, a field that Raise and the later
///      state methods own (Ref, State, RequiredRole, RaisedAt, ExpiresAt, the four Answered fields, Result, FinishedAt), and an empty
///      ApprovalRole setting. Each refusal is an error status that names the field.
///   2. Under LOCK +^OcuTalon.Bridge.Approval(<new Ref>) for LOCKSECONDS it sets the Ref, the state pending, the RequiredRole from the
///      ApprovalRole setting of Decide, RaisedAt now and ExpiresAt EXPIRYSECONDS later, saves the row and starts the hold through
///      ApprovalStartIn. A lock that is not taken is an error that names the lock.
///   3. A failure after the save deletes the row and returns the error, so a failed Raise leaves no row, no hold and no event.
///   4. After the unlock it fires approval.raised once through Decide.FireEvent, with the row's OwnerRef and {"ref"}.
/// ref is empty when Raise fails.
ClassMethod Raise(request As OcuTalon.Bridge.Data.ApprovalRequest, Output ref As %String, sinkClass As %String = "", sessionId As %String = "", superSession As %String = "") As %Status
{
	Set ref = ""
	Set sc = ..Validate(request, .role)
	If $$$ISERR(sc) Quit sc
	Set newRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Lock +^OcuTalon.Bridge.Approval(newRef):..#LOCKSECONDS
	If '$Test {
		Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.Raise could not take the lock ^OcuTalon.Bridge.Approval(""" _ newRef _ """) in " _ ..#LOCKSECONDS _ " seconds")
	}
	Try {
		Set sc = ..SaveAndStart(request, newRef, role, sessionId, superSession)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Lock -^OcuTalon.Bridge.Approval(newRef)
	If $$$ISERR(sc) Quit sc
	If sinkClass = "" Set sinkClass = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("HostSinkClass")
	Do ##class(OcuTalon.Bridge.Process.Decide).FireEvent(sinkClass, request.OwnerRef, newRef, ##class(OcuTalon.Bridge.Ext.HostSink).#APPROVALRAISED, ##class(OcuTalon.Bridge.Ext.HostSink).RefPayload(newRef))
	Set ref = newRef
	Quit $$$OK
}

/// Raise's work under the lock: fixes the row's own fields, saves it and starts its hold. A start that fails deletes the row again.
ClassMethod SaveAndStart(request As OcuTalon.Bridge.Data.ApprovalRequest, newRef As %String, role As %String, sessionId As %String, superSession As %String) As %Status [ Private ]
{
	Set now = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set request.Ref = newRef
	Set request.State = "pending"
	Set request.RequiredRole = role
	Set request.RaisedAt = now
	Set request.ExpiresAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(now, ..#EXPIRYSECONDS)
	Set sc = request.%Save()
	If $$$ISERR(sc) Quit sc
	Set id = request.%Id()
	Set context = ##class(OcuTalon.Bridge.Context).Current()
	If $IsObject(context) {
		If sessionId '> 0 Set sessionId = context.ThreadSessionId
		If superSession = "" Set superSession = context.SuperSession
	}
	If superSession = "" Set superSession = request.TraceRef
	Try {
		Set sc = ..StartHold(newRef, sessionId, superSession)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		Do ##class(OcuTalon.Bridge.Data.ApprovalRequest).%DeleteId(id)
	}
	Quit sc
}

/// Starts the hold of the request with the Ref, through ApprovalStartIn, from any job: a sessionId above 0 is the trace session that the
/// hold joins (otherwise a new one starts) and superSession the tag of its messages. Returns the service's error, the hold's error or a
/// timeout of STARTSECONDS.
ClassMethod StartHold(ref As %String, sessionId As %String = "", superSession As %String = "") As %Status [ Internal ]
{
	Set sc = ##class(Ens.Director).CreateBusinessService(..#STARTITEM, .service)
	If $$$ISERR(sc) Quit sc
	Set message = ##class(OcuTalon.Bridge.Msg.ApprovalStart).%New()
	Set message.Ref = ref
	Set message.SessionId = $Select(sessionId > 0: sessionId, 1: "")
	Set message.SuperSession = superSession
	Quit service.ProcessInput(message, .output)
}

/// OK when the request may be raised; otherwise the first refusal, an error that names the field. role is the ApprovalRole setting.
ClassMethod Validate(request As %RegisteredObject, Output role As %String) As %Status [ Private ]
{
	Set role = ""
	If '$IsObject(request) || '$ClassMethod($ClassName(request), "%Extends", "OcuTalon.Bridge.Data.ApprovalRequest") {
		Quit ..Refuse("request", "is not an OcuTalon.Bridge.Data.ApprovalRequest")
	}
	If request.%Id() '= "" Quit ..Refuse("request", "is a saved row; Raise takes an unsaved one")
	Set kind = request.Kind
	If '$ListFind($ListFromString(##class(OcuTalon.Bridge.Msg.Enum).#APPROVALKIND), kind) {
		Quit ..Refuse("Kind", "'" _ kind _ "' is not one of " _ ##class(OcuTalon.Bridge.Msg.Enum).#APPROVALKIND)
	}
	If '..IsRef(request.OwnerRef) && (request.OwnerRef '= "instance") && (request.OwnerRef '= "eval") {
		Quit ..Refuse("OwnerRef", "is not a 22-character reference, instance or eval")
	}
	If kind = "tool_call" {
		If request.ToolName = "" Quit ..Refuse("ToolName", "is empty for a tool_call request")
		If '..IsJsonObject(request.ToolArguments) Quit ..Refuse("ToolArguments", "is not a JSON object")
		If request.DryRun '= "" Quit ..Refuse("DryRun", "must be empty for a tool_call request")
	} Else {
		If '..IsJsonObject(request.DryRun) Quit ..Refuse("DryRun", "is not a JSON object")
		If request.ResultTarget = "" Quit ..Refuse("ResultTarget", "is empty for a fix request")
		If request.ToolName '= "" Quit ..Refuse("ToolName", "must be empty for a fix request")
		If request.ToolArguments '= "" Quit ..Refuse("ToolArguments", "must be empty for a fix request")
	}
	For name = "IncidentRef", "TraceRef" {
		Set value = $Property(request, name)
		If (value '= "") && '..IsRef(value) Return ..Refuse(name, "is neither empty nor a 22-character reference")
	}
	For name = "Ref", "State", "RequiredRole", "RaisedAt", "ExpiresAt", "AnsweredAction", "AnsweredChannel", "AnsweredBy", "AnsweredAt", "Result", "FinishedAt" {
		If $Property(request, name) '= "" Return ..Refuse(name, "must be empty: Raise and the state methods set it")
	}
	Set role = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ApprovalRole", , , .sc)
	If $$$ISERR(sc) Quit ..Refuse("ApprovalRole", "cannot be read: " _ $SYSTEM.Status.GetErrorText(sc))
	If role = "" Quit ..Refuse("ApprovalRole", "setting is empty, so no role may answer a request")
	Quit $$$OK
}

/// The error status of a refused request: Raise's name, the field and the reason.
ClassMethod Refuse(field As %String, reason As %String) As %Status [ Private ]
{
	Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.Raise refuses the request: " _ field _ " " _ reason)
}

/// 1 when the text is a 22-character reference: the characters A-Z, a-z, 0-9, - and _ (Ids.NewRef).
ClassMethod IsRef(text As %String) As %Boolean [ Private ]
{
	Quit $Match(text, "^[A-Za-z0-9_-]{22}\z")
}

/// 1 when the text is JSON that parses to an object (not an array, a string or a number).
ClassMethod IsJsonObject(text As %String) As %Boolean [ Private ]
{
	If text = "" Quit 0
	Set valid = 0
	Try {
		Set object = {}.%FromJSON(text)
		Set valid = $IsObject(object) && ($ClassName(object) = "%Library.DynamicObject")
	} Catch exception {
		Set valid = 0
	}
	Quit valid
}

/// Answers the request. action is approve or reject, channel one of Msg.Enum CHANNEL, irisUser the answering IRIS user
/// and sessionRef the answering session. The result is one of done, already_answered, expired, not_found and
/// not_allowed; winner describes the answer that won when the result is already_answered. Not implemented yet: it
/// answers not_found with an empty winner. Story 3.5.
ClassMethod Answer(ref As %String, action As %String, channel As %String, irisUser As %String, sessionRef As %String, Output winner As %DynamicObject) As %String
{
	Set winner = {}
	Quit "not_found"
}

/// Expires a pending request that is past its expiry. Not implemented yet: Story 3.5.
ClassMethod Expire(ref As %String) As %Status
{
	Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.Expire is not implemented yet (Story 3.5)")
}

/// Cancels a pending request. Not implemented yet: Story 3.5.
ClassMethod Cancel(ref As %String) As %Status
{
	Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.Cancel is not implemented yet (Story 3.5)")
}

/// Moves an approved, unexpired request that is not yet executing to executing, atomically. Not implemented yet:
/// Story 3.6.
ClassMethod StartExecution(ref As %String) As %Status
{
	Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.StartExecution is not implemented yet (Story 3.6)")
}

/// Closes an executing request as done or failed, with the result of the run. Not implemented yet: Story 3.6.
ClassMethod FinishExecution(ref As %String, result As %String) As %Status
{
	Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.FinishExecution is not implemented yet (Story 3.6)")
}

/// The logic of ApprovalHold.OnRequest (AD-5): holds the request that the start names. It stores the Ref on the process, opens the row (a
/// missing or non-pending row is an error that names the Ref and the state, so a start that arrives after Raise deleted its row holds
/// nothing), sends an EnsLib.Workflow.TaskRequest to WORKFLOWROLE with the completion key task, sets the timer for the whole seconds until
/// the row's ExpiresAt (at least 1) with the key expiry, and replies to the start, so that ApprovalStartIn returns while the hold keeps
/// waiting. The task sets no %UserName, %Title, %Message or %Command: a %UserName would assign the task to that Workflow user, a member of
/// the role or not, and without one it goes to every active member, which is the one technical user. Makes no %AI call and runs no Python (AD-6).
ClassMethod Hold(hold As OcuTalon.Bridge.Process.ApprovalHold, request As OcuTalon.Bridge.Msg.ApprovalStart, Output response As %Persistent) [ Internal ]
{
	Set response = ""
	Set ref = request.Ref
	Set hold.Ref = ref
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If '$IsObject(row) Quit $SYSTEM.Status.Error(5001, "ApprovalHold: there is no approval request " _ ref)
	If row.State '= "pending" Quit $SYSTEM.Status.Error(5001, "ApprovalHold: the approval request " _ ref _ " is " _ row.State _ ", not pending")
	Set seconds = ##class(OcuTalon.Bridge.Time).SecondsUntil(row.ExpiresAt)
	If seconds = "" Quit $SYSTEM.Status.Error(5001, "ApprovalHold: the approval request " _ ref _ " has no readable ExpiresAt")
	If seconds < 1 Set seconds = 1
	Set task = ##class(EnsLib.Workflow.TaskRequest).%New()
	Set task.%Actions = ..#ACTIONS
	Set task.%Subject = ..#TASKSUBJECT _ ref
	Set sc = hold.SendRequestAsync(..#WORKFLOWROLE, task, 1, "task")
	If $$$ISERR(sc) Quit sc
	Set sc = hold.SetTimer(seconds, "expiry")
	If $$$ISERR(sc) Quit sc
	Quit hold.Reply(##class(Ens.Response).%New())
}

/// The logic of ApprovalHold.OnResponse: the answer of the Workflow task (key task) or the timer (key expiry). It changes no row in Story 3.4;
/// Story 3.5 acts on the answer, and on the timer, only when the row shows the answer.
ClassMethod HoldResponse(hold As OcuTalon.Bridge.Process.ApprovalHold, response As %Persistent, completionKey As %String) As %Status [ Internal ]
{
	Quit $$$OK
}

/// The id of a live ApprovalHold of the Ref, or "": an instance that is not completed, not terminated and still waits for at least one
/// response. Reconcile and the tests find a hold by it.
ClassMethod LiveHold(ref As %String) As %String
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT %ID FROM OcuTalon_Bridge_Process.ApprovalHold WHERE Ref = ?", ref)
	While result.%Next() {
		If ..IsLive(result.%GetData(1)) Return result.%GetData(1)
	}
	Quit ""
}

/// 1 when the ApprovalHold with the id is live (LiveHold).
ClassMethod IsLive(holdId As %String) As %Boolean [ Private ]
{
	Set hold = ##class(OcuTalon.Bridge.Process.ApprovalHold).%OpenId(holdId)
	If '$IsObject(hold) Quit 0
	Quit 'hold.%IsCompleted && 'hold.%IsTerminated && (hold.%MasterPendingResponses.Count() > 0)
}

/// Re-arms the holds after a start (AD-5, AD-23), in two passes that try every task and every row and combine the failures into one status,
/// each naming its Ref. It is idempotent and fires no event.
///   1. It cancels, with EnsLib.Workflow.Engine.%CancelRequest, every incomplete task of the role WORKFLOWROLE that is not the task of a live
///      hold of a pending row. The hold that sent a task is the BusinessProcessId of its TaskRequest's message header.
///   2. It starts, through ApprovalStartIn, a new hold for every pending row that has no live hold, in a new session whose SuperSession is the
///      row's TraceRef (AD-26). The new hold sets its timer from the row's ExpiresAt, and one that is past it fires at once.
/// The Lane A declaration OcuTalon.Install.Step.Approvals.Reconcile calls it, and the Reconcile step runs it after the production starts.
ClassMethod Reconcile() As %Status
{
	Set sc = $$$OK
	Set tasks = ##class(%SQL.Statement).%ExecDirect(, "SELECT TaskStatus_Request FROM EnsLib_Workflow.TaskResponse WHERE TaskStatus_RoleName = ? AND TaskStatus_IsComplete = 0", ..#WORKFLOWROLE)
	If tasks.%SQLCODE < 0 {
		Set sc = ..Combine(sc, "the open tasks of " _ ..#WORKFLOWROLE _ " cannot be read: SQLCODE " _ tasks.%SQLCODE _ " " _ tasks.%Message)
	}
	Set orphans = ""
	While tasks.%Next() {
		Set requestId = tasks.%GetData(1)
		If '..OwnedByLiveHold(requestId) Set orphans = orphans _ $ListBuild(requestId)
	}
	Set position = 0
	While $ListNext(orphans, position, requestId) {
		Set request = ##class(EnsLib.Workflow.TaskRequest).%OpenId(requestId)
		If '$IsObject(request) Continue
		Set one = ##class(EnsLib.Workflow.Engine).%CancelRequest(request)
		If $$$ISERR(one) Set sc = ..Combine(sc, "the orphaned task of " _ $Piece(request.%Subject, ..#TASKSUBJECT, 2) _ " (request " _ requestId _ ") was not cancelled: " _ $SYSTEM.Status.GetErrorText(one))
	}
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, TraceRef FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE State = 'pending'")
	If rows.%SQLCODE < 0 {
		Quit ..Combine(sc, "the pending requests cannot be read: SQLCODE " _ rows.%SQLCODE _ " " _ rows.%Message)
	}
	Set pending = ""
	While rows.%Next() {
		Set pending = pending _ $ListBuild($ListBuild(rows.%Get("Ref"), rows.%Get("TraceRef")))
	}
	Set position = 0
	While $ListNext(pending, position, entry) {
		Set ref = $List(entry, 1)
		If ..LiveHold(ref) '= "" Continue
		Set one = ..StartHold(ref, "", $List(entry, 2))
		If $$$ISERR(one) Set sc = ..Combine(sc, "the hold of " _ ref _ " did not start: " _ $SYSTEM.Status.GetErrorText(one))
	}
	Quit sc
}

/// 1 when the TaskRequest with the id was sent by a live hold whose row is pending.
ClassMethod OwnedByLiveHold(requestId As %String) As %Boolean [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT BusinessProcessId FROM Ens.MessageHeader WHERE MessageBodyClassName = 'EnsLib.Workflow.TaskRequest' AND MessageBodyId = ?", requestId)
	If 'result.%Next() Quit 0
	Set holdId = result.%GetData(1)
	If (holdId = "") || '..IsLive(holdId) Quit 0
	Set hold = ##class(OcuTalon.Bridge.Process.ApprovalHold).%OpenId(holdId)
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(hold.Ref)
	Quit $IsObject(row) && (row.State = "pending")
}

/// The status plus one more failure, with the text as its error.
ClassMethod Combine(sc As %Status, text As %String) As %Status [ Private ]
{
	Quit $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.Reconcile: " _ text))
}

}
