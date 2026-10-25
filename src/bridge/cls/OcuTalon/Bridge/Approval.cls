Include Ensemble

/// The approval API (AD-11): the only way an approval request changes state.
///   - Raise validates an unsaved ApprovalRequest, saves it as pending under its lock and starts its hold synchronously through
///     ApprovalStartIn; a failed Raise leaves no row, no hold and no event, and approval.raised fires once, after the unlock. It refuses to run
///     inside an open transaction ($TLevel above 0): the round trip to ApprovalStartIn commits every open level of the caller, and the hold's job
///     cannot see a row that is not committed. It runs in the caller's job and leaves that job's session and current header ids as they were
///     (StartHold), so a host job's later event-log rows keep their session. The gate (Policy.Gate) raises a tool_call request for a held call;
///   - Answer, Expire, Cancel, StartExecution and FinishExecution are the five state methods: each takes
///     LOCK +^OcuTalon.Bridge.Approval(<Ref>) for LOCKSECONDS plus TASKSECONDS (FinishExecution refuses an unknown result before it locks),
///     reads the row as the database holds it under that lock, changes it along AD-11's one path (pending to approved, rejected, expired or
///     cancelled; approved to executing to done or failed; approved to failed), refuses every other change with nothing changed and no event,
///     and, after the unlock and from its own job, writes one Approval audit entry for the change (Audit.Record) and then fires its HostSink
///     event (AD-31; StartExecution has no event). A refusal writes neither. The entry names the person on whose authority the change
///     happened (AD-17): the answerer for Answer, the approver for StartExecution and FinishExecution, the caller Cancel is given, and
///     otherwise the job's user with the channel system. A write that fails is logged as a warning and never undoes the change;
///   - Hold and HoldResponse are the logic of the business process ApprovalHold, which stores only the request's Ref (AD-5): Hold sends the
///     Workflow task to the role WORKFLOWROLE and sets the 24-hour timer, and replies to the start; HoldResponse acts only on what the row
///     shows: on the timer it expires the row, and it sends Msg.ApprovalOutcome to the row's ResultTarget on approval (a fix only), rejection
///     or expiry;
///   - Reconcile (declared by Install.Step.Approvals, AD-23) cancels the Workflow tasks that no live hold of a pending row owns and starts
///     a new hold for each pending row whose hold is gone, timed from the row's ExpiresAt.
/// Nothing here makes a %AI call or runs Python (AD-6).
Class OcuTalon.Bridge.Approval
{

/// The Workflow role that holds the approvals' tasks, and the one technical Workflow user that is its only member (AD-11). The role is also
/// the name of the production item that is its EnsLib.Workflow.Operation, which takes its role from its own name.
Parameter WORKFLOWROLE = "OcuTalonApprovals";

Parameter WORKFLOWUSER = "OcuTalonWorkflow";

/// The production item through which any job starts a hold, and the item that holds.
Parameter STARTITEM = "ApprovalStartIn";

Parameter HOLDITEM = "ApprovalHold";

/// The actions of the Workflow task, and the start of its subject, which the Ref follows (the hold's task is found by it).
Parameter ACTIONS = "Approve,Reject";

Parameter TASKSUBJECT = "OcuTalon approval request ";

/// How long a request lives before it expires: 24 hours (AD-11).
Parameter EXPIRYSECONDS = 86400;

/// How long Raise waits for the lock of the new Ref, and how long ApprovalStartIn waits for the hold to start, in seconds.
Parameter LOCKSECONDS = 2;

Parameter STARTSECONDS = 10;

/// How long Answer and Cancel wait for the hold's Workflow task to exist, in seconds: the Workflow operation creates it asynchronously after
/// the hold sends it. The five state methods wait LOCKSECONDS plus this for the row's lock, the longest any of them holds it.
Parameter TASKSECONDS = 5;

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
/// ref is empty when Raise fails. A $TLevel above 0 is refused first (Refuse names $TLevel and its value) before anything is written, and the
/// caller's transaction stays open and unchanged.
ClassMethod Raise(request As OcuTalon.Bridge.Data.ApprovalRequest, Output ref As %String, sinkClass As %String = "", sessionId As %String = "", superSession As %String = "") As %Status
{
	Set ref = ""
	If $TLevel > 0 Quit ..Refuse("$TLevel", "is " _ $TLevel _ ": Raise runs ApprovalStartIn's round trip, which commits every open transaction level of the caller, and the hold's job cannot see an uncommitted row")
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
	Try {
		Set context = ##class(OcuTalon.Bridge.Context).Current()
		If $IsObject(context) {
			If sessionId '> 0 Set sessionId = context.ThreadSessionId
			If superSession = "" Set superSession = context.SuperSession
		}
		If superSession = "" Set superSession = request.TraceRef
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
/// timeout of STARTSECONDS. The service's ProcessInput runs in this job and replaces the job's session id ($$$JobSessionId) and current header
/// id ($$$JobCurrentHeaderId), so both are put back afterwards, after the service is closed (closing it in a job that is no production job kills
/// the job-local array), also after an error status or an exception (which is thrown again): a defined value is set back, an undefined one is
/// killed again. Every caller keeps its own session: the gate, Reconcile and the incident manager.
ClassMethod StartHold(ref As %String, sessionId As %String = "", superSession As %String = "") As %Status [ Internal ]
{
	Set hadSession = $Data($$$JobSessionId) # 2
	Set session = $Get($$$JobSessionId)
	Set hadHeader = $Data($$$JobCurrentHeaderId) # 2
	Set header = $Get($$$JobCurrentHeaderId)
	Set sc = $$$OK
	Set thrown = ""
	Try {
		Set sc = ##class(Ens.Director).CreateBusinessService(..#STARTITEM, .service)
		If $$$ISOK(sc) {
			Set message = ##class(OcuTalon.Bridge.Msg.ApprovalStart).%New()
			Set message.Ref = ref
			Set message.SessionId = $Select(sessionId > 0: sessionId, 1: "")
			Set message.SuperSession = superSession
			Set sc = service.ProcessInput(message, .output)
		}
	} Catch exception {
		Set thrown = exception
	}
	// A service that CreateBusinessService made in a job that is not a production job kills the whole job-local array when it is closed, so it is
	// closed before the ids are put back.
	Set service = ""
	If hadSession {
		Set $$$JobSessionId = session
	} Else {
		Kill $$$JobSessionId
	}
	If hadHeader {
		Set $$$JobCurrentHeaderId = header
	} Else {
		Kill $$$JobCurrentHeaderId
	}
	If $IsObject(thrown) Throw thrown
	Quit sc
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
ClassMethod IsRef(text As %String) As %Boolean
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

/// Answers the request. action is approve or reject, channel one of Msg.Enum CHANNEL, irisUser the answering IRIS user, sessionRef the
/// answering session (empty, or a 22-character Ref; it is named in the audit entry, and no column holds it) and sinkClass the host sink that
/// receives the event (empty: the HostSinkClass setting). The result is one of done, already_answered, expired, not_found and not_allowed; winner is {"action",
/// "channel","at"} of the answer that won when the result is already_answered, otherwise {}. Under the row's lock it checks, in this order:
///   1. no row with the Ref, or a cancelled row: not_found;
///   2. an action that is not approve or reject, a channel that is not one of CHANNEL, a sessionRef that is neither empty nor a Ref, or an
///      irisUser who does not hold the row's RequiredRole (the role is in $SYSTEM.Security.GetUserRecursedRoleSet(irisUser); an error from that call, or an empty RequiredRole,
///      holds nobody): not_allowed;
///   3. an expired row: expired; an approved, rejected, executing, done or failed row: already_answered with the winner;
///   4. a pending row whose ExpiresAt is now or past, or unreadable: the row becomes expired with no answer fields, and the result is expired;
///   5. otherwise the answer is saved first (AnsweredAction, AnsweredChannel, AnsweredBy, AnsweredAt, State approved or rejected), then the
///      hold's Workflow task is completed as WORKFLOWUSER with Approve or Reject, and the result is done.
/// A lock that is not taken, or a save that fails, records nothing, is logged as a warning that names the Ref, and gives not_found. After the
/// unlock, done and step 4 each write one Approval entry (change answered or expired) naming irisUser, channel and sessionRef (the row's
/// OwnerRef when sessionRef is empty and that is a Ref), and then done fires approval.answered and step 4 fires approval.expired, from this job.
ClassMethod Answer(ref As %String, action As %String, channel As %String, irisUser As %String, sessionRef As %String, Output winner As %DynamicObject, sinkClass As %String = "") As %String
{
	Set winner = {}
	Set result = "not_found"
	Set event = ""
	Set facts = ""
	If '..IsRef(ref) Quit result
	If '..TakeLock(ref) {
		$$$LOGWARNING("OcuTalon.Bridge.Approval.Answer recorded nothing for "_ref_": it could not take the lock in "_(..#LOCKSECONDS + ..#TASKSECONDS)_" seconds")
		Quit result
	}
	Try {
		Set result = ..AnswerLocked(ref, action, channel, irisUser, sessionRef, .winner, .event, .facts)
	} Catch exception {
		Set result = "not_found"
		Set winner = {}
		Set event = ""
		Set facts = ""
		$$$LOGWARNING("OcuTalon.Bridge.Approval.Answer failed for "_ref_": "_exception.DisplayString())
	}
	Lock -^OcuTalon.Bridge.Approval(ref)
	If event '= "" {
		Do ..Audited(facts, irisUser, channel, sessionRef)
		Do ..Fire(sinkClass, event, facts.ownerRef, ref)
	}
	Quit result
}

/// Answer's work under the lock. event is the HostSink event type to fire after the unlock ("" for none) and facts the audit facts of the row
/// that changed (Facts, with change and outcome), "" when nothing changed.
ClassMethod AnswerLocked(ref As %String, action As %String, channel As %String, irisUser As %String, sessionRef As %String, Output winner As %DynamicObject, Output event As %String, Output facts As %DynamicObject) As %String [ Private ]
{
	Set event = ""
	Set facts = ""
	Set row = ..LockedRow(ref)
	If '$IsObject(row) || (row.State = "cancelled") Quit "not_found"
	If '$ListFind($ListBuild("approve", "reject"), action) || '$ListFind($ListFromString(##class(OcuTalon.Bridge.Msg.Enum).#CHANNEL), channel) || '..HoldsRole(irisUser, row.RequiredRole) || ((sessionRef '= "") && '..IsRef(sessionRef)) Quit "not_allowed"
	If row.State = "expired" Quit "expired"
	If row.State '= "pending" {
		Set winner = {"action": (row.AnsweredAction), "channel": (row.AnsweredChannel), "at": (row.AnsweredAt)}
		Quit "already_answered"
	}
	Set seconds = ##class(OcuTalon.Bridge.Time).SecondsUntil(row.ExpiresAt)
	If '(seconds > 0) {
		Set sc = ..MoveLocked(ref, "OcuTalon.Bridge.Approval.Answer", "pending", "expired", "", 0, 0, .facts)
		If $$$ISERR(sc) {
			$$$LOGWARNING("OcuTalon.Bridge.Approval.Answer could not expire "_ref_": "_$SYSTEM.Status.GetErrorText(sc))
			Quit "not_found"
		}
		Do facts.%Set("change", "expired", "string")
		Set event = ##class(OcuTalon.Bridge.Ext.HostSink).#APPROVALEXPIRED
		Quit "expired"
	}
	Set row.AnsweredAction = action
	Set row.AnsweredChannel = channel
	Set row.AnsweredBy = irisUser
	Set row.AnsweredAt = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set row.State = $Select(action = "approve": "approved", 1: "rejected")
	Set sc = row.%Save()
	If $$$ISERR(sc) {
		$$$LOGWARNING("OcuTalon.Bridge.Approval.Answer recorded nothing for "_ref_": the save failed: "_$SYSTEM.Status.GetErrorText(sc))
		Quit "not_found"
	}
	Set event = ##class(OcuTalon.Bridge.Ext.HostSink).#APPROVALANSWERED
	Set facts = ..Facts(row, "pending")
	Do facts.%Set("change", "answered", "string")
	Do facts.%Set("outcome", row.State, "string")
	Do ..CompleteHoldTask(ref, $Select(action = "approve": "Approve", 1: "Reject"))
	Quit "done"
}

/// 1 when the IRIS user holds the role: it is in the user's recursed role set, the names compared without case, as IRIS names roles. An empty
/// user or role, an unknown user and an error from the role set (reading another user's set needs %Admin_Secure:USE) hold nobody.
ClassMethod HoldsRole(irisUser As %String, role As %String) As %Boolean [ Private ]
{
	If (irisUser = "") || (role = "") Quit 0
	Set holds = 0
	Try {
		Set sc = $SYSTEM.Security.GetUserRecursedRoleSet(irisUser, .roles)
		Set holds = $$$ISOK(sc) && ''$ListFind($ListFromString($ZConvert(roles, "L")), $ZConvert(role, "L"))
	} Catch exception {
		Set holds = 0
	}
	Quit holds
}

/// Expires a pending request, whatever the clock says (DW-186): its caller, the hold's timer (set from ExpiresAt in whole seconds, rounded down),
/// decides that the time is up; Answer's past-expiry step makes the same change through the same helper, MoveLocked. A missing row, or a row in
/// any other state, is an error that names the Ref and the state, and nothing changes. After the unlock it fires approval.expired from this job,
/// to sinkClass (empty: the HostSinkClass setting).
ClassMethod Expire(ref As %String, sinkClass As %String = "") As %Status
{
	Quit ..Move(ref, "Expire", sinkClass, "pending", "expired", ##class(OcuTalon.Bridge.Ext.HostSink).#APPROVALEXPIRED, , , , "expired")
}

/// Cancels a pending request, and then completes the hold's Workflow task with no action (Workflow status Cancelled), so that the hold ends and
/// sends no ApprovalOutcome (AD-15). Any other state, or a missing row, is an error that names the Ref and the state. After the unlock it
/// writes the Approval entry (change cancelled) and fires approval.cancelled from this job, to sinkClass (empty: the HostSinkClass setting).
/// The entry names the person who cancelled: irisUser, channel (one of Msg.Enum CHANNEL) and sessionRef (empty, or a Ref), each defaulting
/// to the job's $Username, system and the row's OwnerRef when empty. Before it locks, a channel outside CHANNEL or a sessionRef that is
/// neither empty nor a Ref is an error that names the argument, and nothing changes.
ClassMethod Cancel(ref As %String, sinkClass As %String = "", channel As %String = "", irisUser As %String = "", sessionRef As %String = "") As %Status
{
	If (channel '= "") && '$ListFind($ListFromString(##class(OcuTalon.Bridge.Msg.Enum).#CHANNEL), channel) {
		Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.Cancel refuses the channel argument: it is not one of " _ ##class(OcuTalon.Bridge.Msg.Enum).#CHANNEL)
	}
	If (sessionRef '= "") && '..IsRef(sessionRef) {
		Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.Cancel refuses the sessionRef argument: it is neither empty nor a 22-character Ref")
	}
	Quit ..Move(ref, "Cancel", sinkClass, "pending", "cancelled", ##class(OcuTalon.Bridge.Ext.HostSink).#APPROVALCANCELLED, , , 1, "cancelled", irisUser, channel, sessionRef)
}

/// Moves an approved request whose ExpiresAt is still ahead (SecondsUntil above 0) to executing, the check and the change together under the
/// lock, so that of two callers at once exactly one succeeds. A row past its expiry stays approved and gets an error that says so; any other
/// state, or a missing row, is an error that names the Ref and the state. No event fires: AD-31 has no type for executing.
ClassMethod StartExecution(ref As %String) As %Status
{
	Quit ..Move(ref, "StartExecution", "", "approved", "executing", , , 1, , "started")
}

/// Closes a request with the result of the run. result must be done, failed or interrupted; any other value is an error that names it and the
/// Ref, and nothing is locked. An executing row becomes done (result done) or failed (failed or interrupted); an approved row whose run could not
/// start becomes failed, but only with the result failed. Result is set to the given result and FinishedAt to now. Every other case, and a
/// missing row, is an error that names the Ref, the state and the result. After the unlock it fires approval.result from this job, to
/// sinkClass (empty: the HostSinkClass setting).
ClassMethod FinishExecution(ref As %String, result As %String, sinkClass As %String = "") As %Status
{
	If '$ListFind($ListBuild("done", "failed", "interrupted"), result) {
		Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.FinishExecution refuses the result '" _ result _ "' for " _ $Extract(ref, 1, 64) _ ": it is not done, failed or interrupted")
	}
	Quit ..Move(ref, "FinishExecution", sinkClass, $Select(result = "failed": "executing,approved", 1: "executing"), $Select(result = "done": "done", 1: "failed"), ##class(OcuTalon.Bridge.Ext.HostSink).#APPROVALRESULT, result, , , "finished")
}

/// The one state change of Expire, Cancel, StartExecution and FinishExecution: under the row's lock, a row whose state is in from (a comma
/// list) gets the state to, and the result and FinishedAt when result is given; ahead 1 also needs ExpiresAt still ahead; cancelTask 1
/// completes the hold's task with no action after the save. Returns an error that names caller, the Ref, the state and the result for a row
/// that is missing or in another state, for a Ref that is not a 22-character reference (no row can have it), and for a lock that is not
/// taken; a refusal changes nothing, writes no audit entry and fires no event. After the unlock it writes the Approval entry of the change
/// (Audited, with change, result as the outcome of a run's end, and the person from irisUser, channel and sessionRef) and then fires event
/// (when given) from this job.
ClassMethod Move(ref As %String, caller As %String, sinkClass As %String, from As %String, to As %String, event As %String = "", result As %String = "", ahead As %Boolean = 0, cancelTask As %Boolean = 0, change As %String = "", irisUser As %String = "", channel As %String = "", sessionRef As %String = "") As %Status [ Private ]
{
	Set where = "OcuTalon.Bridge.Approval." _ caller
	If '..IsRef(ref) Quit $SYSTEM.Status.Error(5001, where _ " refuses " _ $Extract(ref, 1, 64) _ ": there is no approval request with that Ref")
	If '..TakeLock(ref) {
		Quit $SYSTEM.Status.Error(5001, where _ " could not take the lock ^OcuTalon.Bridge.Approval(""" _ ref _ """) in " _ (..#LOCKSECONDS + ..#TASKSECONDS) _ " seconds")
	}
	Set facts = ""
	Try {
		Set sc = ..MoveLocked(ref, where, from, to, result, ahead, cancelTask, .facts)
	} Catch exception {
		Set sc = exception.AsStatus()
		Set facts = ""
	}
	Lock -^OcuTalon.Bridge.Approval(ref)
	If $$$ISERR(sc) Quit sc
	Do facts.%Set("change", change, "string")
	Do facts.%Set("outcome", result, "string")
	Do ..Audited(facts, irisUser, channel, sessionRef)
	If event '= "" Do ..Fire(sinkClass, event, facts.ownerRef, ref)
	Quit $$$OK
}

/// Move's work under the lock, and the expiry of Answer's past-expiry step. facts is the row's audit facts (Facts) once the row has changed.
ClassMethod MoveLocked(ref As %String, where As %String, from As %String, to As %String, result As %String, ahead As %Boolean, cancelTask As %Boolean, Output facts As %DynamicObject) As %Status [ Private ]
{
	Set facts = ""
	Set row = ..LockedRow(ref)
	If '$IsObject(row) Quit $SYSTEM.Status.Error(5001, where _ " refuses " _ ref _ ": there is no approval request with that Ref")
	Set about = $Select(result '= "": " and the result " _ result, 1: "")
	If '$ListFind($ListFromString(from), row.State) {
		Quit $SYSTEM.Status.Error(5001, where _ " refuses " _ ref _ ": it is " _ row.State _ about _ ", and only " _ from _ " can become " _ to)
	}
	If ahead && '(##class(OcuTalon.Bridge.Time).SecondsUntil(row.ExpiresAt) > 0) {
		Quit $SYSTEM.Status.Error(5001, where _ " refuses " _ ref _ ": it is " _ row.State _ " and past its expiry, so it stays " _ row.State)
	}
	Set before = row.State
	Set row.State = to
	If result '= "" {
		Set row.Result = result
		Set row.FinishedAt = ##class(OcuTalon.Bridge.Time).NowUtc()
	}
	Set sc = row.%Save()
	If $$$ISERR(sc) Quit sc
	Set facts = ..Facts(row, before)
	If cancelTask Do ..CompleteHoldTask(ref, "")
	Quit $$$OK
}

/// The facts of a row that has just changed, for its Approval audit entry, as a dynamic object of strings: ref, kind, ownerRef, target
/// (ToolName for a tool_call, IncidentRef for a fix), from (the state before), to (the state now), and answeredBy and answeredChannel, the
/// approver. The caller adds change and outcome.
ClassMethod Facts(row As OcuTalon.Bridge.Data.ApprovalRequest, from As %String) As %DynamicObject [ Private ]
{
	Set facts = {}
	Do facts.%Set("ref", row.Ref, "string")
	Do facts.%Set("kind", row.Kind, "string")
	Do facts.%Set("ownerRef", row.OwnerRef, "string")
	Do facts.%Set("target", $Select(row.Kind = "tool_call": row.ToolName, 1: row.IncidentRef), "string")
	Do facts.%Set("from", from, "string")
	Do facts.%Set("to", row.State, "string")
	Do facts.%Set("answeredBy", row.AnsweredBy, "string")
	Do facts.%Set("answeredChannel", row.AnsweredChannel, "string")
	Quit facts
}

/// Writes the Approval audit entry of a change (facts, with its change and outcome), naming the person on whose authority it happened
/// (AD-17). An empty irisUser is the approver (answeredBy) for a run's start and end, else the job's $Username; an empty channel is the
/// approver's channel for a run's start and end, else system; an empty sessionRef is the row's OwnerRef when that is a Ref, else empty.
/// Nothing is written when facts is not an object. A write that fails (Audit.Record refuses, or IRIS writes nothing) is logged as a warning
/// that names the Ref, the change and the error; it never undoes the change and never escapes.
ClassMethod Audited(facts As %DynamicObject, irisUser As %String, channel As %String, sessionRef As %String) [ Private ]
{
	If '$IsObject(facts) Quit
	Set sc = $$$OK
	Try {
		Set change = facts.change
		Set approver = $ListFind($ListBuild("started", "finished"), change)
		If (irisUser = "") && approver Set irisUser = facts.answeredBy
		If irisUser = "" Set irisUser = $Username
		If (channel = "") && approver Set channel = facts.answeredChannel
		If channel = "" Set channel = "system"
		If (sessionRef = "") && ..IsRef(facts.ownerRef) Set sessionRef = facts.ownerRef
		Set data = {}
		Do data.%Set("irisUser", irisUser, "string")
		Do data.%Set("sessionRef", sessionRef, "string")
		Do data.%Set("channel", channel, "string")
		For name = "ref", "kind", "change", "from", "to", "outcome", "target", "ownerRef" {
			Do data.%Set(name, facts.%Get(name), "string")
		}
		Set sc = ##class(OcuTalon.Bridge.Audit).Record("Approval", data)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		$$$LOGWARNING("OcuTalon.Bridge.Approval: the Approval entry of "_facts.ref_" ("_facts.change_") was not written: "_$SYSTEM.Status.GetErrorText(sc))
	}
}

/// The row of the Ref as the database holds it, or "" when there is none. A row that this process already has open (a caller kept it) is read
/// again, so that a state method under the lock never checks or saves a stale copy.
ClassMethod LockedRow(ref As %String) As OcuTalon.Bridge.Data.ApprovalRequest [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If '$IsObject(row) Quit ""
	If $$$ISERR(row.%Reload()) Quit ""
	Quit row
}

/// 1 when the lock ^OcuTalon.Bridge.Approval(ref) is taken (the caller unlocks it), waiting up to LOCKSECONDS plus TASKSECONDS.
ClassMethod TakeLock(ref As %String) As %Boolean [ Private ]
{
	Lock +^OcuTalon.Bridge.Approval(ref):(..#LOCKSECONDS + ..#TASKSECONDS)
	Quit $Test
}

/// Fires the event of a change through Decide.FireEvent with the row's OwnerRef and {"ref"}, to sinkClass (empty: the HostSinkClass setting).
ClassMethod Fire(sinkClass As %String, event As %String, owner As %String, ref As %String) [ Private ]
{
	If sinkClass = "" Set sinkClass = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("HostSinkClass")
	Do ##class(OcuTalon.Bridge.Process.Decide).FireEvent(sinkClass, owner, ref, event, ##class(OcuTalon.Bridge.Ext.HostSink).RefPayload(ref))
}

/// The id of the hold's task: the newest open task (highest ID) whose subject is TASKSUBJECT plus the Ref, or "".
ClassMethod HoldTask(ref As %String) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM EnsLib_Workflow.TaskResponse WHERE %Subject = ? AND TaskStatus_IsComplete = 0 ORDER BY ID DESC", ..#TASKSUBJECT _ ref)
	If result.%Next() Quit result.%GetData(1)
	Quit ""
}

/// Completes the hold's task (HoldTask) as WORKFLOWUSER: AssignTask, then CompleteTask with the action (Approve or Reject), or with no action
/// for a cancel (Workflow status Cancelled). It polls up to TASKSECONDS for the task to exist. A task that does not appear, or fails to
/// complete, and any exception on the way, is logged as a warning that names the Ref and never escapes; the row's change stands.
ClassMethod CompleteHoldTask(ref As %String, action As %String) [ Private ]
{
	Try {
		Set deadline = $ZHorolog + ..#TASKSECONDS
		Set taskId = ..HoldTask(ref)
		While (taskId = "") && ($ZHorolog < deadline) {
			Hang 0.1
			Set taskId = ..HoldTask(ref)
		}
		If taskId = "" {
			$$$LOGWARNING("OcuTalon.Bridge.Approval: no open task of " _ ref _ " appeared in " _ ..#TASKSECONDS _ " seconds, so none was completed")
		} Else {
			Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(taskId)
			Set sc = task.AssignTask(..#WORKFLOWUSER)
			If $$$ISOK(sc) Set sc = task.CompleteTask(action)
			If $$$ISERR(sc) {
				$$$LOGWARNING("OcuTalon.Bridge.Approval: the task " _ taskId _ " of " _ ref _ " was not completed: " _ $SYSTEM.Status.GetErrorText(sc))
			}
		}
	} Catch exception {
		$$$LOGWARNING("OcuTalon.Bridge.Approval: the task of " _ ref _ " was not completed: " _ exception.DisplayString())
	}
}

/// The logic of ApprovalHold.OnRequest (AD-5): holds the request that the start names. It stores the Ref on the process, opens the row (a
/// missing or non-pending row is an error that names the Ref and the state, so a start that arrives after Raise deleted its row holds
/// nothing), sends an EnsLib.Workflow.TaskRequest to WORKFLOWROLE with the completion key task, sets the timer for the whole seconds until
/// the row's ExpiresAt (at least 1) with the key expiry, and replies to the start, so that ApprovalStartIn returns while the hold keeps
/// waiting. The task sets no %UserName, %Title, %Message or %Command: a %UserName would assign the task to that Workflow user, a member of
/// the role or not, and without one it goes to every active member, which is the one technical user. Makes no %AI call and runs no Python (AD-6).
ClassMethod Hold(hold As OcuTalon.Bridge.Process.ApprovalHold, request As OcuTalon.Bridge.Msg.ApprovalStart, Output response As %Persistent) As %Status [ Internal ]
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

/// The logic of ApprovalHold.OnResponse: the answer of the Workflow task (key task) or the timer (key expiry). The hold acts only on what the
/// row shows.
///   1. For the key expiry it first calls Expire(Ref); a row that is no longer pending is refused, which is expected, and any other failure is
///      logged as a warning.
///   2. It reads the row; with no row it does nothing.
///   3. For the key task the outcome is approved when the TaskResponse's %Action is Approve and the row is approved, and rejected when the
///      action is Reject and the row is rejected; anything else, a task completed outside Answer or cancelled by Cancel included, has none.
///   4. For the key expiry the outcome is the row's state when that is expired, approved or rejected, so that an answer whose task Answer could
///      not complete is delivered when the timer fires at the latest.
///   5. An approved tool_call sends nothing (the replay is Story 30.3's). Any other outcome is sent to the row's ResultTarget as an
///      OcuTalon.Bridge.Msg.ApprovalOutcome, asynchronously with no response; an empty ResultTarget sends nothing.
///   6. A failed send is logged as an error that names the Ref and the target; the method still returns OK, so that the hold ends.
ClassMethod HoldResponse(hold As OcuTalon.Bridge.Process.ApprovalHold, response As %Persistent, completionKey As %String) As %Status [ Internal ]
{
	Set ref = hold.Ref
	If completionKey = "expiry" {
		Set sc = ..Expire(ref)
		If $$$ISERR(sc) {
			Set pending = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
			If $IsObject(pending) && (pending.State = "pending") {
				$$$LOGWARNING("OcuTalon.Bridge.Approval: the timer of " _ ref _ " could not expire it: " _ $SYSTEM.Status.GetErrorText(sc))
			}
		}
	}
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If '$IsObject(row) Quit $$$OK
	Set outcome = ""
	If completionKey = "task" {
		Set action = $Select($IsObject(response) && response.%IsA("EnsLib.Workflow.TaskResponse"): response.%Action, 1: "")
		If (action = "Approve") && (row.State = "approved") Set outcome = "approved"
		If (action = "Reject") && (row.State = "rejected") Set outcome = "rejected"
	} ElseIf completionKey = "expiry" {
		If $ListFind($ListBuild("expired", "approved", "rejected"), row.State) Set outcome = row.State
	}
	Set target = row.ResultTarget
	If (outcome = "") || (target = "") || ((outcome = "approved") && (row.Kind = "tool_call")) Quit $$$OK
	Set message = ##class(OcuTalon.Bridge.Msg.ApprovalOutcome).%New()
	Set message.ApprovalRef = ref
	Set message.IncidentRef = row.IncidentRef
	Set message.Outcome = outcome
	Set sc = hold.SendRequestAsync(target, message, 0)
	If $$$ISERR(sc) {
		$$$LOGERROR("OcuTalon.Bridge.Approval: the outcome " _ outcome _ " of " _ ref _ " was not sent to " _ target _ ": " _ $SYSTEM.Status.GetErrorText(sc))
	}
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
