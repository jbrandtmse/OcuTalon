Include (EnsConstants, EnsErrors)

/// FixExecutor, the business operation that works out and carries out an approved fix (AD-16; Stories 7.1, 7.3 and 7.4). Its item has PoolSize 2: at most one job
/// waits for the copies of the runs at a time (Wait, below), and the other answers dry runs and starts runs. It answers a Fix.Msg.DryRun and handles a
/// Fix.Msg.Execute; any other request is the error 5001, which names its class.
///   - A Fix.Msg.DryRun is answered with a Fix.Msg.DryRunResult (DryRun): the incident is opened by its Ref, the kind by its name, and the kind's DryRun works out
///     the targets and the dry run's JSON. It changes nothing and calls no model. A dry run that cannot be worked out (an unknown or closed incident, an unknown kind, parameters
///     that are not a JSON object or that the kind refuses, a production that cannot be read) is still answered with OK: Reason holds one plain sentence (redacted),
///     and Targets and DryRun are empty.
///   - A Fix.Msg.Execute (IncidentManager sends it, asynchronously, when an approved request may run) carries only the Ref of the approval request; everything else
///     is read from the request's row (AD-11): the kind, its parameters and the targets (FixKind, FixParameters, FixTargets). It is handled in this order, and
///     the handler's answer is always OK (nothing is wanted back):
///       1. Refused: there is no row, it is not a fix, its State is not approved, or its ExpiresAt is not after now (UTC stamps, compared as text). The handler
///          writes, sends and resends nothing and logs one Type 4 line (LOGREFUSED: the Ref and why).
///       2. Could not start, the row is unusable (UNUSABLE): the kind is not registered, the parameters are not one JSON object, the targets are not positive whole
///          numbers in strictly ascending order, or the incident is missing or closed.
///       3. Could not start, no resources: the service user (the ServiceUser setting) lacks a pair of the kind's RESOURCES (Bridge.Policy.Gate.MissingOf, one
///          permission letter per CheckUserPermission call); the reason is the kind's NOTALLOWED. A check that throws counts as a pair missing and logs one
///          Type 3 warning (LOGMISSING).
///       4. Approval.StartExecution (the Start seam) moves the request from approved to executing, atomically. An error there reads the row again: a request that
///          still is approved and not past its expiry ends as could not start, with the reason NOSTART (DW-380); any other row is refused as in 1.
///       5. The run: the FixRun row is saved (the request's Ref, the incident's, the start time); the kind's Recheck reads all the targets before any copy is
///          made; the kind's Execute resends a repaired copy of each target that passed (Fix.Kind.RepairResend: through Resend, below) and registers each copy's
///          header id on the FixRun (Copies). A re-check that cannot read the production, or an error before any copy was made, ends like a run that cannot start,
///          with the reason NOREAD and one Type 3 warning (LOGRECHECK).
///     Every run that ends, ends once, in Finish: the counts and EndedAt are saved on the FixRun (End), the request is closed through Approval.FinishExecution (done or
///     failed; a failed one also from approved), one OcuTalon Action entry is written through Bridge.Audit (the WriteAudit seam: ActionEntry, the row's kind, the production
///     and namespace of the incident, the result, the counts, the request's Ref, the approver and the channel), and the one final FixResult (ResultOf) goes to IncidentManager
///     (Report), in the incident's trace session (AD-26), also when another job finishes it. A failed save (LOGRUN), close (LOGFINISH), audit write (LOGAUDIT) or send
///     (LOGRESULT) logs one Type 3 warning, and the rest still happens. Log text goes through Bridge.Redact.
///       - A run that cannot start (2, 3 and 4), and one that could not read before its first copy, close the request failed: Total the number of targets,
///         every other count 0 and the plain Reason.
///       - A run that resent nothing (every target was skipped) closes the request done: Total and Skipped the number of targets, Resent, Completed and
///         FailedAgain 0, and the plain Reason of the lowest skipped target.
///       - A run that resent copies (also one that erred after its first copy) saves ResentAt on its FixRun and waits for its copies (Wait), up to WAITSECONDS from
///         ResentAt. Each pass reads the copies through Watch.Reader.Evidence (the Statuses seam). A copy is completed when its status is Completed and failed again
///         when it is Error, Aborted, Discarded or Suspended; any other status, a header the read lacks and a read that does not give read are still running. When
///         every copy is completed or failed again the run ends done: Total the number of targets, Resent the number of copies, Completed and FailedAgain their
///         counts, Skipped the targets without a copy, Interrupted 0, and, for copies that failed again, the Reason of the failed copy with the lowest id (FailReason).
///         A run whose copies are not all done when the time is up is not waited for any more: one Type 3 warning (LOGWAIT), nothing is stored or sent, and the
///         request stays executing (Story 30.5 reports it in progress and its Sweep ends it). No final result ever goes out with a copy uncounted. A run whose ResentAt
///         cannot be saved (LOGRUN) is not waited for either, and its request stays executing in the same way.
///   - One writer of a run's end (AD-33). End and Mark, class methods of this class, are the only code that writes the end fields of a FixRun (EndedAt, Total, Resent,
///     Completed, FailedAgain, Skipped, Interrupted and Reason), each under the run's lock (RUNLOCK, TakeRun and FreeRun; at most RUNLOCKSECONDS to take it), and the stored
///     EndedAt and Interrupted decide whether a run may end. Three callers end runs: Finish (every end of Story 7.4); Fix.Run.Interrupt, which the Fix area's Reconcile() calls at a
///     start and which marks (Mark) each run that was cut short by the restart and closes its request; and Fix.Run.Sweep, which Checks calls on each heartbeat Tick, and which
///     ends a marked run with its counts as interrupted and a run that no waiter ended (below). Only the job whose End wrote closes the request, writes the entry and builds the
///     FixResult; Finish, when End refuses the run, does none of that and logs one Type 4 line (LOGENDED). Waiting leaves out a marked run, so that nothing resumes it.
///   - A waiter that stops (the job should quiesce or terminate, or its item is stopped) leaves its runs, with a ResentAt and no EndedAt, to Sweep (DW-395): a run whose copies
///     were all done inside its WAITSECONDS ends there, with the waiter's own counts and result, only later.
///   - One waiter (DW-381): Wait takes the lock WAITLOCK without waiting; the job that holds it makes a pass every WAITPAUSE seconds over every waiting run (Waiting:
///     ResentAt set, EndedAt empty, not marked as interrupted, the request executing, inside its WAITSECONDS) and ends each whose copies are done, so a job that finds the lock taken returns at
///     once and the holder finishes its run too. The holder stops when no run waits or when the job should quiesce or terminate, and looks once more after it unlocks.
///   - Resend is the only method of the executor that switches namespace (AD-3, AD-16): it opens the original header and body in the production's namespace,
///     calling no OcuTalon class there, and resends each copy with Ens.MessageHeader.ResendDuplicatedMessage. The wait reads through Watch.Reader.
///   - The seams SendResult (the send to IncidentManager), Start (StartExecution), Missing (the resources check), Check (the kind's Recheck), Carry (the kind's Execute),
///     Statuses (the read of the copies), Waiting (the waiting runs) and WriteAudit (the audit write) are private methods that a test subclass overrides
///     (Test.Fix.ExecutorProbe); its WAITSECONDS, WAITPAUSE and WAITLOCK are read as ..# in the instance methods, so a subclass's values apply. Read (the read behind Statuses),
///     Tally (the count of the copies), FailReason, ActionEntry and ResultOf are public class methods, which Fix.Run calls too.
/// FixExecutor calls no model. Lane A.
Class OcuTalon.Fix.Executor Extends Ens.BusinessOperation
{

/// The item that receives the FixResult (AD-16).
Parameter MANAGER = "IncidentManager";

/// The reasons of a run that cannot start, besides the kind's NOTALLOWED (no resources): the row cannot be used, and the failed messages cannot be read.
/// They render as "Nothing was resent: {reason}. Nothing was changed." (public text, veto U-141).
Parameter UNUSABLE = "OcuTalon couldn't read the approved fix";

Parameter NOREAD = "OcuTalon couldn't read the failed messages in that production";

/// The reason of an approved request whose StartExecution failed (public text, veto U-148). It renders as "Nothing was resent: OcuTalon couldn't start the resend.
/// Nothing was changed."
Parameter NOSTART = "OcuTalon couldn't start the resend";

/// How long a run waits for its copies, in seconds from ResentAt (AD-16), the pause between two passes of the waiter, in seconds, and the lock that makes one job
/// the waiter (DW-381).
Parameter WAITSECONDS = 60;

Parameter WAITPAUSE = 0.5;

Parameter WAITLOCK = "^OcuTalon.Fix.Wait";

/// The status of a copy that completed, and the statuses of a copy that failed again (Ens.DataType.MessageStatus, as Reader.Evidence gives them).
Parameter COPYDONE = "Completed";

Parameter COPYFAILED = "Error,Aborted,Discarded,Suspended";

/// The start of each log line of the executor.
Parameter LOGREFUSED = "FixExecutor refused an Execute for request ";

Parameter LOGFINISH = "FixExecutor could not close request ";

Parameter LOGRESULT = "FixExecutor could not send the result of request ";

Parameter LOGRECHECK = "FixExecutor could not read the failed messages for request ";

Parameter LOGCOPY = "FixExecutor could not resend message ";

Parameter LOGRUN = "FixExecutor could not save the run of request ";

Parameter LOGMISSING = "FixExecutor could not check the resources for request ";

Parameter LOGWAIT = "FixExecutor stopped waiting for the copies of request ";

Parameter LOGAUDIT = "FixExecutor could not write the audit entry of request ";

Parameter LOGLOOK = "FixExecutor could not read the copies of request ";

Parameter LOGENDED = "FixExecutor left the run of request ";

/// The lock of one run's end (a subscript of it is the FixRun's id), and the longest a job waits for it, in seconds (see End and Mark).
Parameter RUNLOCK = "^OcuTalon.Fix.Run";

Parameter RUNLOCKSECONDS = 2;

/// The state of a request that is approved, the state of one that is carried out, and the kind of a fix request.
Parameter APPROVED = "approved";

Parameter EXECUTING = "executing";

Parameter KINDFIX = "fix";

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Set pResponse = ""
	If $IsObject(pRequest) {
		If pRequest.%IsA("OcuTalon.Fix.Msg.DryRun") Quit ..DryRun(pRequest, .pResponse)
		If pRequest.%IsA("OcuTalon.Fix.Msg.Execute") Quit ..Execute(pRequest)
	}
	Quit $SYSTEM.Status.Error(5001, "FixExecutor does not handle a request of the class '"_$Select($IsObject(pRequest): $ClassName(pRequest), 1: "none")_"'")
}

/// Answers the request with its DryRunResult. Always OK: a dry run that cannot be worked out is the response's Reason.
Method DryRun(request As OcuTalon.Fix.Msg.DryRun, Output response As OcuTalon.Fix.Msg.DryRunResult) As %Status
{
	Set response = ##class(OcuTalon.Fix.Msg.DryRunResult).%New()
	Set response.IncidentRef = request.IncidentRef
	Set reason = ""
	Try {
		Set sc = ..Work(request, .targets, .dryRun)
		If $$$ISERR(sc) {
			Set reason = $SYSTEM.Status.GetOneErrorText(sc)
		} Else {
			Set response.Targets = targets
			Set response.DryRun = dryRun.%ToJSON()
		}
	} Catch exception {
		Set reason = "The dry run could not be worked out because of an internal error."
	}
	If reason '= "" {
		Set response.Targets = ""
		Set response.DryRun = ""
		If $Extract(reason, 1, 7) = "ERROR #" Set reason = $ZStrip($Piece(reason, ":", 2, *), "<W")
		Set response.Reason = $Extract(##class(OcuTalon.Bridge.Redact).Text(reason), 1, 1000)
	}
	Quit $$$OK
}

/// The targets and the dry run of the request, or an error status that says why not.
Method Work(request As OcuTalon.Fix.Msg.DryRun, Output targets As %String, Output dryRun As %DynamicObject) As %Status [ Private ]
{
	Set targets = ""
	Set dryRun = ""
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(request.IncidentRef)
	If '$IsObject(incident) Quit $$$ERROR($$$GeneralError, "There is no incident "_request.IncidentRef)
	If incident.State = ##class(OcuTalon.Watch.Transitions).#CLOSED Quit $$$ERROR($$$GeneralError, "The incident "_request.IncidentRef_" is closed")
	Set class = ##class(OcuTalon.Fix.Kind).ForName(request.FixKind)
	If class = "" Quit $$$ERROR($$$GeneralError, "The fix kind '"_request.FixKind_"' is not one of "_$ListToString(##class(OcuTalon.Fix.Kind).Names(), ","))
	Set parameters = ""
	Try {
		Set parameters = {}.%FromJSON(request.Parameters)
	} Catch {
		Set parameters = ""
	}
	If '$IsObject(parameters) || 'parameters.%IsA("%Library.DynamicObject") Quit $$$ERROR($$$GeneralError, "The parameters are not one JSON object")
	Quit $ClassMethod(class, "DryRun", incident, parameters, .targets, .dryRun)
}

/// Handles an Execute (see the class description). Always OK.
Method Execute(request As OcuTalon.Fix.Msg.Execute) As %Status
{
	Set ref = request.ApprovalRef
	Set row = $Select(ref = "": "", 1: ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref))
	Set why = ..Refusal(row)
	If why '= "" {
		Do ..Refuse(ref, why)
		Quit $$$OK
	}
	Set total = $Select(row.FixTargets = "": 0, 1: $Length(row.FixTargets, ","))
	Set reason = ..Unusable(row, .incident, .class, .parameters)
	If reason = "" {
		Set missing = ..Unchecked(class, ref)
		If missing '= "" {
			Set reason = $Parameter(class, "NOTALLOWED")
			If reason = "" Set reason = ..#UNUSABLE
		}
	}
	If reason '= "" {
		Do ..CouldNotStart(row, total, reason, 0)
		Quit $$$OK
	}
	Set sc = ..Start(ref)
	If $$$ISERR(sc) {
		If $$$ISOK(row.%Reload()) && (row.State = ..#APPROVED) && (row.ExpiresAt ] ##class(OcuTalon.Data.Time).NowUtc()) {
			Do ..CouldNotStart(row, total, ..#NOSTART, 0)
		} Else {
			Do ..Refuse(ref, "it could not be started: "_$SYSTEM.Status.GetErrorText(sc))
		}
		Quit $$$OK
	}
	Do ..Run(row, incident, class, parameters, total)
	Quit $$$OK
}

/// Moves the request from approved to executing (Approval.StartExecution; a seam for the tests).
Method Start(ref As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Approval).StartExecution(ref)
}

/// Why the Execute is refused: no row, not a fix, not approved, or past its expiry; "" when it is taken up.
Method Refusal(row As OcuTalon.Bridge.Data.ApprovalRequest) As %String [ Private ]
{
	If '$IsObject(row) Quit "there is no approval request with that Ref"
	If row.Kind '= ..#KINDFIX Quit "it is a "_row.Kind_" request, not a fix"
	If row.State '= ..#APPROVED Quit "it is "_row.State_", not approved"
	If '(row.ExpiresAt ] ##class(OcuTalon.Data.Time).NowUtc()) Quit "it is past its expiry"
	Quit ""
}

/// Logs one Type 4 line for an Execute that was refused: the Ref and why.
Method Refuse(ref As %String, why As %String) [ Private ]
{
	$$$LOGINFO(..#LOGREFUSED_$Extract(ref, 1, 64)_": "_##class(OcuTalon.Bridge.Redact).Text(why))
}

/// "" when the row can be used; else UNUSABLE. incident, class and parameters are what the run works from: the incident (open), the kind's class and the
/// parameters as one JSON object. The targets are positive whole numbers in strictly ascending order.
Method Unusable(row As OcuTalon.Bridge.Data.ApprovalRequest, Output incident As OcuTalon.Data.Incident, Output class As %String, Output parameters As %DynamicObject) As %String [ Private ]
{
	Set incident = ""
	Set parameters = ""
	Set class = ##class(OcuTalon.Fix.Kind).ForName(row.FixKind)
	If class = "" Quit ..#UNUSABLE
	Try {
		Set parameters = {}.%FromJSON(row.FixParameters)
	} Catch {
		Set parameters = ""
	}
	If '$IsObject(parameters) || 'parameters.%IsA("%Library.DynamicObject") Quit ..#UNUSABLE
	If '..AscendingIds(row.FixTargets) Quit ..#UNUSABLE
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(row.IncidentRef)
	If '$IsObject(incident) || (incident.State = ##class(OcuTalon.Watch.Transitions).#CLOSED) Quit ..#UNUSABLE
	Quit ""
}

/// 1 when the targets are positive whole numbers written without a leading zero, comma-separated, each above the one before.
ClassMethod AscendingIds(targets As %String) As %Boolean [ Private ]
{
	If targets = "" Quit 0
	Set last = 0
	For i = 1:1:$Length(targets, ",") {
		Set id = $Piece(targets, ",", i)
		If (id '? 1.N) || (id '= +id) || (+id < 1) || (+id '> last) Return 0
		Set last = +id
	}
	Quit 1
}

/// The resources check as a seam for the tests: the first pair of the kind's RESOURCES that the service user does not hold (Gate.MissingOf), or "". A check
/// that cannot be made counts as a pair missing.
Method Missing(class As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Policy.Gate).MissingOf($Parameter(class, "RESOURCES"), class_" fix")
}

/// Missing, with a check that throws counted as a pair missing (nothing may run on a permission that could not be read) and one Type 3 warning (LOGMISSING)
/// that names the request and says why.
Method Unchecked(class As %String, ref As %String) As %String [ Private ]
{
	Set missing = ""
	Try {
		Set missing = ..Missing(class)
	} Catch exception {
		Set missing = "unreadable"
		$$$LOGWARNING(..#LOGMISSING_ref_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Quit missing
}

/// The run (step 5 of the class description) of a request that StartExecution has moved to executing. It ends in Finish, or, for a run that resent copies, in the
/// wait for them.
Method Run(row As OcuTalon.Bridge.Data.ApprovalRequest, incident As OcuTalon.Data.Incident, class As %String, parameters As %DynamicObject, total As %Integer) [ Private ]
{
	Set run = ""
	Set failed = ""
	Set skipped = []
	Try {
		Set run = ##class(OcuTalon.Data.FixRun).%New()
		Set run.ApprovalRef = row.Ref
		Set run.IncidentRef = row.IncidentRef
		Set run.StartedAt = ##class(OcuTalon.Data.Time).NowUtc()
		$$$ThrowOnError(run.%Save())
		$$$ThrowOnError(..Check(class, incident, parameters, row.FixTargets, .passed, .skipped))
		If passed '= "" {
			$$$ThrowOnError(..Carry(class, incident, parameters, passed, .result, run))
			If $IsObject($Get(result)) && $IsObject(result.skipped) {
				Set iterator = result.skipped.%GetIterator()
				While iterator.%GetNext(, .entry) {
					Do skipped.%Push(entry)
				}
			}
		}
	} Catch exception {
		Set failed = exception.AsStatus()
	}
	Set copies = $Select($IsObject(run): run.Copies.Count(), 1: 0)
	If failed '= "" {
		$$$LOGWARNING(..#LOGRECHECK_row.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(failed)))
		If copies = 0 {
			Do ..CouldNotStart(row, total, ..#NOREAD, $IsObject(run) && (run.%Id() '= ""))
			Quit
		}
	}
	If copies > 0 {
		Set run.ResentAt = ##class(OcuTalon.Data.Time).NowUtc()
		Set sc = run.%Save()
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGRUN_row.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
			Quit
		}
		Do ..Wait()
		Quit
	}
	Do ..Finish(row, run, "done", {"total": (total), "resent": 0, "completed": 0, "failedAgain": 0, "skipped": (total), "reason": (..FirstReason(skipped))})
}

/// The run's FixRun row, saved with no copies when it was not saved yet, and then the end of the run (Finish) as failed: the request closed failed
/// (FinishExecution accepts it while it still is approved or already executing) and one final FixResult with the reason. A FixRun that cannot be saved logs one
/// Type 3 warning and the run still ends. saved is 1 when the run's FixRun has been saved already (the re-check ran).
Method CouldNotStart(row As OcuTalon.Bridge.Data.ApprovalRequest, total As %Integer, reason As %String, saved As %Boolean) [ Private ]
{
	If saved {
		Set run = ##class(OcuTalon.Data.FixRun).OfRequest(row.Ref)
	} Else {
		Set run = ##class(OcuTalon.Data.FixRun).%New()
		Set run.ApprovalRef = row.Ref
		Set run.IncidentRef = row.IncidentRef
		Set run.StartedAt = ##class(OcuTalon.Data.Time).NowUtc()
		Set sc = run.%Save()
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGRUN_row.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		}
	}
	Do ..Finish(row, run, "failed", {"total": (total), "resent": 0, "completed": 0, "failedAgain": 0, "skipped": 0, "reason": (reason)})
}

/// Closes the request through FinishExecution with the result (done or failed). A failure logs one Type 3 warning; the run goes on to its FixResult.
Method Close(ref As %String, result As %String) [ Private ]
{
	Set sc = ##class(OcuTalon.Bridge.Approval).FinishExecution(ref, result)
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGFINISH_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
}

/// The one end of every run of this job: the counts (a dynamic object of total, resent, completed, failedAgain, skipped and reason, as numbers and text) and EndedAt
/// are saved on the run's FixRun when it has an Id (End), the request is closed with the result (done or failed; Close), one Action entry is written (Audit) and the one
/// final FixResult goes to IncidentManager (Report). The reason is redacted and at most 1000 characters, here, so that the FixRun, the entry and the FixResult carry the
/// same text. A failed step logs its own Type 3 warning and the others still happen. When End refuses the run (another job ended it, or marked it as interrupted, or holds its
/// lock), nothing else happens here: one Type 4 line (LOGENDED) names the request and says why.
Method Finish(row As OcuTalon.Bridge.Data.ApprovalRequest, run As OcuTalon.Data.FixRun, result As %String, counts As %DynamicObject) [ Private ]
{
	Do counts.%Set("reason", $Extract(##class(OcuTalon.Bridge.Redact).Text(counts.reason), 1, 1000), "string")
	If $IsObject(run) && (run.%Id() '= "") {
		If '..End(run, counts, 0, .sc) {
			$$$LOGINFO(..#LOGENDED_row.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
			Quit
		}
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGRUN_row.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		}
	}
	Do ..Close(row.Ref, result)
	Do ..Audit(row, result, counts)
	Do ..Report(row, counts)
}

/// Takes the lock of the run (RUNLOCK, the FixRun's id as its subscript), waiting at most RUNLOCKSECONDS; 1 when it is taken, and FreeRun lets it go. A job that holds it takes it again
/// (End and Mark do) and lets it go as often.
ClassMethod TakeRun(id As %String) As %Boolean
{
	Set lock = ..#RUNLOCK
	Lock +@lock@(id):..#RUNLOCKSECONDS
	Quit $Test
}

/// Lets the lock of the run go once (see TakeRun).
ClassMethod FreeRun(id As %String)
{
	Set lock = ..#RUNLOCK
	Lock -@lock@(id)
}

/// The one writer of a run's end (AD-33), for every job that ends a run (Finish, Fix.Run.Interrupt and Fix.Run.Sweep): under the run's lock it sets EndedAt (UTC now) and the
/// counts of counts (a dynamic object of total, resent, completed, failedAgain, skipped, reason and, when the run was cut short, interrupted, which is 0 when it is missing) and
/// saves the run. The stored EndedAt and Interrupted decide (EndedAtGetStored and InterruptedGetStored; the object the caller holds is not read again). A run that was marked
/// (Mark) has Interrupted above 0 and no EndedAt; interrupted 1 ends only such a run, and interrupted 0 only one that is not marked. It gives 1 when it wrote, and sc holds the error of a
/// save that failed (the caller goes on as Finish does). It gives 0 and writes nothing, with the reason in sc as an error, for a run that has ended, one of the other kind, a run with
/// no Id and a lock that cannot be taken in RUNLOCKSECONDS (another job is ending the run).
ClassMethod End(run As OcuTalon.Data.FixRun, counts As %DynamicObject, interrupted As %Boolean, Output sc As %Status) As %Boolean
{
	Set sc = $$$OK
	Set id = $Select($IsObject(run): run.%Id(), 1: "")
	If id = "" {
		Set sc = $SYSTEM.Status.Error(5001, "the run has no Id")
		Quit 0
	}
	If '..TakeRun(id) {
		Set sc = $SYSTEM.Status.Error(5001, "another job holds the lock of the run")
		Quit 0
	}
	Set wrote = 0
	Try {
		Set ended = ##class(OcuTalon.Data.FixRun).EndedAtGetStored(id)
		Set marked = (+##class(OcuTalon.Data.FixRun).InterruptedGetStored(id) > 0)
		If ended '= "" {
			Set sc = $SYSTEM.Status.Error(5001, "the run has ended already")
		} ElseIf 'interrupted && marked {
			Set sc = $SYSTEM.Status.Error(5001, "the run is marked as interrupted")
		} ElseIf interrupted && 'marked {
			Set sc = $SYSTEM.Status.Error(5001, "the run is not marked as interrupted")
		} Else {
			Set run.EndedAt = ##class(OcuTalon.Data.Time).NowUtc()
			Set run.Total = counts.total
			Set run.Resent = counts.resent
			Set run.Completed = counts.completed
			Set run.FailedAgain = counts.failedAgain
			Set run.Skipped = counts.skipped
			Set run.Interrupted = +counts.interrupted
			Set run.Reason = counts.reason
			Set wrote = 1
			Set sc = run.%Save()
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Do ..FreeRun(id)
	Quit wrote
}

/// Marks a run as cut short, under the run's lock: Total is set to total (the number of the request's targets), Interrupted to total and at least 1 (so that a request with no targets
/// still shows as marked), and the run is saved. A run that has ended or is marked
/// already is refused (the stored EndedAt and Interrupted decide, as in End). It gives 1 when the run is marked; 0 otherwise, with the reason in sc as an error: a refusal, a save that failed
/// or a lock that cannot be taken in RUNLOCKSECONDS.
ClassMethod Mark(run As OcuTalon.Data.FixRun, total As %Integer, Output sc As %Status) As %Boolean
{
	Set sc = $$$OK
	Set id = $Select($IsObject(run): run.%Id(), 1: "")
	If id = "" {
		Set sc = $SYSTEM.Status.Error(5001, "the run has no Id")
		Quit 0
	}
	If '..TakeRun(id) {
		Set sc = $SYSTEM.Status.Error(5001, "another job holds the lock of the run")
		Quit 0
	}
	Try {
		If ##class(OcuTalon.Data.FixRun).EndedAtGetStored(id) '= "" {
			Set sc = $SYSTEM.Status.Error(5001, "the run has ended already")
		} ElseIf +##class(OcuTalon.Data.FixRun).InterruptedGetStored(id) > 0 {
			Set sc = $SYSTEM.Status.Error(5001, "the run is marked as interrupted already")
		} Else {
			Set run.Total = total
			Set run.Interrupted = $Select(total > 0: total, 1: 1)
			Set sc = run.%Save()
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Do ..FreeRun(id)
	Quit $$$ISOK(sc)
}

/// Writes the Action entry of a run that ended (WriteAudit; the entry is ActionEntry's). A write that fails or throws logs one Type 3 warning (LOGAUDIT).
Method Audit(row As OcuTalon.Bridge.Data.ApprovalRequest, result As %String, counts As %DynamicObject) [ Private ]
{
	Set sc = $$$OK
	Try {
		Set sc = ..WriteAudit(..ActionEntry(row, result, counts))
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGAUDIT_row.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
}

/// The data of the Action entry of a run that ended, for every job that ends a run: the action is the row's FixKind, the target "<production> in <namespace>" of the incident, the
/// result (done, failed or interrupted), the counts (total, resent, completed, failedAgain and skipped, as numbers), the request's Ref, the approver (the row's AnsweredBy, else the
/// job's user) and the channel (the row's AnsweredChannel, else system), and the row's OwnerRef as the session when that is a Ref. The entry holds no key, token, password or chat
/// identity: the row holds none.
ClassMethod ActionEntry(row As OcuTalon.Bridge.Data.ApprovalRequest, result As %String, counts As %DynamicObject) As %DynamicObject
{
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(row.IncidentRef)
	Set data = {}
	Do data.%Set("action", row.FixKind, "string")
	Do data.%Set("target", $Select($IsObject(incident): incident.Production_" in "_incident.Namespace, 1: ""), "string")
	Do data.%Set("result", result, "string")
	Set tally = {}
	For name = "total", "resent", "completed", "failedAgain", "skipped" {
		Do tally.%Set(name, +counts.%Get(name), "number")
	}
	Do data.%Set("counts", tally)
	Do data.%Set("approvalRef", row.Ref, "string")
	Do data.%Set("irisUser", $Select(row.AnsweredBy '= "": row.AnsweredBy, 1: $Username), "string")
	Do data.%Set("sessionRef", $Select(##class(OcuTalon.Bridge.Approval).IsRef(row.OwnerRef): row.OwnerRef, 1: ""), "string")
	Do data.%Set("channel", $Select(row.AnsweredChannel '= "": row.AnsweredChannel, 1: "system"), "string")
	Quit data
}

/// The one audit write of the executor: an entry of type Action, through the one writer of product code (a seam for the tests).
Method WriteAudit(data As %DynamicObject) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Audit).Record("Action", data)
}

/// Sends IncidentManager the one final FixResult of a run (ResultOf): the counts as Finish gives them. It goes in the incident's trace session (its TraceHeaderId)
/// with the request's TraceRef as the SuperSession (AD-26), whichever job sends it, and the session of the message being handled is put back afterwards; with no
/// incident the current session is kept. A failed send logs one Type 3 warning.
Method Report(row As OcuTalon.Bridge.Data.ApprovalRequest, counts As %DynamicObject) [ Private ]
{
	Set result = ..ResultOf(row, counts)
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(row.IncidentRef)
	Set session = ..%SessionId
	Set superSession = ..%SuperSession
	If $IsObject(incident) {
		If incident.TraceHeaderId '= "" Set ..%SessionId = incident.TraceHeaderId
		Set ..%SuperSession = row.TraceRef
	}
	Set sc = ..SendResult(result)
	Set ..%SessionId = session
	Set ..%SuperSession = superSession
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGRESULT_row.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
}

/// The final FixResult of a run, for every job that sends one (FixExecutor, and Checks through Fix.Run.Sweep): the request's Ref and the incident's, Final 1, the counts of counts
/// and the reason, and Interrupted 1 when counts.interrupted is above 0 (the run was cut short and targets were cut off).
ClassMethod ResultOf(row As OcuTalon.Bridge.Data.ApprovalRequest, counts As %DynamicObject) As OcuTalon.Fix.Msg.FixResult
{
	Set result = ##class(OcuTalon.Fix.Msg.FixResult).%New()
	Set result.ApprovalRef = row.Ref
	Set result.IncidentRef = row.IncidentRef
	Set result.Final = 1
	Set result.Interrupted = (+counts.interrupted > 0)
	Set result.Total = counts.total
	Set result.Resent = counts.resent
	Set result.Completed = counts.completed
	Set result.FailedAgain = counts.failedAgain
	Set result.Skipped = counts.skipped
	Set result.Reason = counts.reason
	Quit result
}

/// The reason of the skipped target with the lowest id (entries are {"id", "reason"}); "" when none was skipped.
ClassMethod FirstReason(skipped As %DynamicArray) As %String [ Private ]
{
	Set first = ""
	Set reason = ""
	Set iterator = skipped.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (first = "") || (+entry.id < first) {
			Set first = +entry.id
			Set reason = entry.reason
		}
	}
	Quit reason
}

/// The wait for the copies of the runs that resent some (see the class description). One job at a time is the waiter: it takes the lock WAITLOCK without waiting,
/// and a job that finds it taken returns at once, because the holder ends this run too. The holder makes a pass every WAITPAUSE seconds over every waiting run
/// (Waiting) until none waits, or the job should quiesce or terminate; after it unlocks it looks once more, so that a run saved while it was unlocking is not
/// left, and goes on if it can take the lock again.
Method Wait() [ Private ]
{
	Set lock = ..#WAITLOCK
	Set pause = ..#WAITPAUSE
	For {
		Lock +@lock:0
		If '$Test Quit
		Set stop = 0
		Kill last
		Try {
			For {
				If ##class(Ens.Job).ShouldBeQuiescent() || ##class(Ens.Job).ShouldTerminate() {
					Set stop = 1
					Quit
				}
				Set waiting = ..Waiting()
				Do ..Pass(waiting, .last)
				If $ListLength(waiting) = 0 Quit
				Hang pause
			}
		} Catch exception {
			Set stop = 1
			$$$LOGWARNING(..#LOGWAIT_"(any): "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
		}
		Lock -@lock
		If stop Quit
		If $ListLength(..Waiting()) = 0 Quit
	}
}

/// The ids of the FixRun rows that wait, as a list: ResentAt set, EndedAt empty, not marked as interrupted (Mark), the request's row executing and the time (WAITSECONDS from
/// ResentAt) not up (a seam for the tests).
Method Waiting() As %List [ Private ]
{
	Set waiting = ""
	Set now = ##class(OcuTalon.Watch.Settle).Seconds(##class(OcuTalon.Data.Time).NowUtc())
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.FixRun WHERE ResentAt IS NOT NULL AND EndedAt IS NULL AND (Interrupted IS NULL OR Interrupted = 0) ORDER BY ID")
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The waiting runs could not be read: "_rs.%Message))
	While rs.%Next() {
		Set run = ##class(OcuTalon.Data.FixRun).%OpenId(rs.%GetData(1))
		If '$IsObject(run) || $$$ISERR(run.%Reload()) || (run.ResentAt = "") || (run.EndedAt '= "") Continue
		Set start = ##class(OcuTalon.Watch.Settle).Seconds(run.ResentAt)
		If (start = "") || (now '< (start + ..#WAITSECONDS)) Continue
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(run.ApprovalRef)
		If '$IsObject(row) || $$$ISERR(row.%Reload()) || (row.State '= ..#EXECUTING) Continue
		Set waiting = waiting _ $ListBuild(run.%Id())
	}
	Quit waiting
}

/// One pass of the waiter over the waiting runs (ids): Look at each, and remember in last(id) how many of its copies still ran. A look that throws logs one Type 3
/// warning for the run (LOGLOOK) and counts its copies as still running. A run that last was looked at and no longer waits, with no EndedAt, has run out of time: it
/// is dropped with one Type 3 warning (LOGWAIT: the request and the copies still running), and nothing is stored or sent.
Method Pass(waiting As %List, ByRef last) [ Private ]
{
	Kill here
	Set position = 0
	While $ListNext(waiting, position, id) {
		Set here(id) = ""
		Set running = ""
		Try {
			Set running = ..Look(id)
		} Catch exception {
			If '$Data(last(id, "fault")) {
				Set last(id, "fault") = 1
				Set faulty = ##class(OcuTalon.Data.FixRun).%OpenId(id)
				Set named = $Select($IsObject(faulty): faulty.ApprovalRef, 1: id)
				$$$LOGWARNING(..#LOGLOOK_named_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
			}
			Set running = $Get(last(id), "some")
		}
		If running = "" {
			Kill last(id)
		} Else {
			Set last(id) = running
		}
	}
	Set id = ""
	For {
		Set id = $Order(last(id), 1, running)
		Quit:id=""
		If $Data(here(id)) Continue
		Kill last(id)
		Set run = ##class(OcuTalon.Data.FixRun).%OpenId(id)
		If '$IsObject(run) || $$$ISERR(run.%Reload()) || (run.EndedAt '= "") Continue
		$$$LOGWARNING(..#LOGWAIT_run.ApprovalRef_": "_running_" of "_run.Copies.Count()_" copies were still running after "_..#WAITSECONDS_" seconds")
	}
}

/// Looks at the copies of one waiting run: the number of copies that still run, or "" when the run is not waiting any more or has ended now. A run whose copies are
/// all completed or failed again ends here, done, through Finish with the counts of its own row and FixRun (Tally counts the copies).
Method Look(id As %String) As %Integer [ Private ]
{
	Set run = ##class(OcuTalon.Data.FixRun).%OpenId(id)
	If '$IsObject(run) || $$$ISERR(run.%Reload()) || (run.EndedAt '= "") Quit ""
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(run.ApprovalRef)
	If '$IsObject(row) || $$$ISERR(row.%Reload()) || (row.State '= ..#EXECUTING) Quit ""
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(run.IncidentRef)
	Set outcome = $Select($IsObject(incident): ..Statuses(incident, run, .statuses), 1: "")
	Set tally = ..Tally(run, outcome, $Get(statuses))
	If tally.running > 0 Quit tally.running
	Set total = $Select(row.FixTargets = "": 0, 1: $Length(row.FixTargets, ","))
	Set resent = run.Copies.Count()
	Set reason = $Select(tally.failed = "": "", 1: ..FailReason(incident, row, statuses.%Get(tally.failed)))
	Do ..Finish(row, run, "done", {"total": (total), "resent": (resent), "completed": (tally.completed), "failedAgain": (tally.failedAgain), "skipped": ($Select(total > resent: total - resent, 1: 0)), "reason": (reason)})
	Quit ""
}

/// Counts the copies of a run from a read (outcome and statuses as Read gives them), as a dynamic object: completed (their status is COPYDONE), failedAgain (one of COPYFAILED),
/// running (any other status, a header the read lacks, and every copy when the outcome is not read), failed (the id of the failed copy with the lowest id, "" when none) and lastAt:
/// the latest "at" of the copies that are done (completed or failed again), in seconds (Watch.Settle Seconds), and "" when a copy that is done has no usable "at" or none is done.
ClassMethod Tally(run As OcuTalon.Data.FixRun, outcome As %String, statuses As %DynamicObject) As %DynamicObject
{
	Set completed = 0
	Set failedAgain = 0
	Set running = 0
	Set failed = ""
	Set latest = ""
	Set unstamped = 0
	Set failedStatuses = $ListFromString(..#COPYFAILED)
	For i = 1:1:run.Copies.Count() {
		Set copy = run.Copies.GetAt(i)
		Set entry = $Select((outcome = "read") && $IsObject($Get(statuses)): statuses.%Get(copy), 1: "")
		Set status = $Select($IsObject(entry): entry.status, 1: "")
		If status = ..#COPYDONE {
			Set completed = completed + 1
		} ElseIf $ListFind(failedStatuses, status) {
			Set failedAgain = failedAgain + 1
			If (failed = "") || (+copy < +failed) Set failed = copy
		} Else {
			Set running = running + 1
			Continue
		}
		Set at = ##class(OcuTalon.Watch.Settle).Seconds($Select($IsObject(entry): entry.at, 1: ""))
		If at = "" {
			Set unstamped = 1
		} ElseIf (latest = "") || (at > latest) {
			Set latest = at
		}
	}
	Quit {"completed": (completed), "failedAgain": (failedAgain), "running": (running), "failed": (failed), "lastAt": ($Select(unstamped: "", 1: latest))}
}

/// The outcome of the read of the run's copies (a seam for the tests): Read's.
Method Statuses(incident As OcuTalon.Data.Incident, run As OcuTalon.Data.FixRun, Output statuses As %DynamicObject) As %String [ Private ]
{
	Quit ..Read(incident, run, .statuses)
}

/// The outcome of the read ("read" when statuses holds the copies) and the status of each copy of the run, for every job that counts a run's copies: statuses is a dynamic object
/// by the copy's header id of {"status" (as Reader.Evidence gives it), "error" (the raw error text), "target" (the copy's TargetConfigName), "at" (the header's timeProcessed, the time
/// of its last status change, a UTC stamp)}. The read is Reader.Evidence over the keys h<copy id>, in the incident's namespace and production, with the first group's ItemName, so
/// that the one reader reads the production (AD-3). A header the read lacks is not in statuses.
ClassMethod Read(incident As OcuTalon.Data.Incident, run As OcuTalon.Data.FixRun, Output statuses As %DynamicObject) As %String
{
	Set statuses = {}
	Set keys = ""
	For i = 1:1:run.Copies.Count() {
		Set keys = keys _ $Select(keys = "": "", 1: ",") _ "h" _ run.Copies.GetAt(i)
	}
	Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident.Ref)
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(incident.Namespace, incident.Production, $Select(groups.Count() > 0: groups.GetAt(1).ItemName, 1: ""), keys, .snapshot)
	If outcome '= "read" Quit outcome
	For i = 0:1:snapshot.failures.%Size() - 1 {
		Set failure = snapshot.failures.%Get(i)
		Do statuses.%Set(failure.headerId, {"status": (failure.status), "error": (failure.error), "target": (failure.targetConfigName), "at": (failure.timeProcessed)})
	}
	Quit outcome
}

/// The reason of a run whose copies failed again: that of the failed copy with the lowest id (entry, as Statuses gives it). When the pattern of its error text (Settle)
/// is that of one of the incident's groups whose ItemName is the copy's target, the copy failed with the incident's own error and the reason says the field
/// still wasn't accepted (the field of the row's parameters, in words). Otherwise it is the first sentence of the error text, without its closing full stop; with no text
/// it is the notice's "no error text". The caller redacts it. A class method, for every job that ends a run.
ClassMethod FailReason(incident As OcuTalon.Data.Incident, row As OcuTalon.Bridge.Data.ApprovalRequest, entry As %DynamicObject) As %String
{
	Set text = ##class(OcuTalon.Watch.ErrorText).Text($Select($IsObject(entry): entry.error, 1: ""))
	If text = "" Quit ##class(OcuTalon.Watch.Notice).#NOERRORTEXT
	Set field = ""
	Try {
		Set field = {}.%FromJSON(row.FixParameters).field
	} Catch {
		Set field = ""
	}
	If (field '= "") && $IsObject(incident) && ..Own(incident, entry.target, ##class(OcuTalon.Watch.Settle).Pattern(text)) {
		Quit "the "_##class(OcuTalon.Fix.Kind.RepairResend).FieldWords(field)_" still wasn't accepted"
	}
	Set sentence = ##class(OcuTalon.Watch.ErrorText).Summary(text)
	If $Extract(sentence, *) = "." Set sentence = $Extract(sentence, 1, *-1)
	Quit $Select(sentence = "": ##class(OcuTalon.Watch.Notice).#NOERRORTEXT, 1: sentence)
}

/// 1 when one of the incident's failure groups has the item name and the error pattern: a copy that fails at the item with that error failed with the incident's own.
ClassMethod Own(incident As OcuTalon.Data.Incident, item As %String, pattern As %String) As %Boolean [ Private ]
{
	Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident.Ref)
	For i = 1:1:groups.Count() {
		If (groups.GetAt(i).ItemName = item) && (groups.GetAt(i).ErrorPattern = pattern) Return 1
	}
	Quit 0
}

/// Sends the result to IncidentManager, asynchronously, with no answer wanted, in the session of the Execute that is being handled (a seam for the tests).
Method SendResult(result As OcuTalon.Fix.Msg.FixResult) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#MANAGER, result)
}

/// The kind's Recheck (a seam for the tests).
Method Check(class As %String, incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output passed As %String, Output skipped As %DynamicArray) As %Status [ Private ]
{
	Quit $ClassMethod(class, "Recheck", incident, parameters, targets, .passed, .skipped)
}

/// The kind's Execute (a seam for the tests).
Method Carry(class As %String, incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output result As %DynamicObject, run As OcuTalon.Data.FixRun) As %Status [ Private ]
{
	Quit $ClassMethod(class, "Execute", incident, parameters, targets, .result, run)
}

/// Resends a repaired copy of each entry of the plan, one at a time, and registers each copy on the run. plan is a dynamic array of {"id" (the original's
/// header id), "field", "value" (what the field held when the re-check read it) and "repaired" (the value the copy gets, worked out in the home namespace before
/// the switch)}. This is the only method of the executor that switches namespace (AD-3, AD-16), and it calls no OcuTalon class while it is in the production's
/// namespace, only Ens and % classes and the body's class. For each entry, in the production's namespace: the original's header and body are opened; the copy
/// is built only if the header still is in the status Error and the field still is a stored datatype property of the body's class (as that namespace resolves it,
/// found in the compiled dictionary, and set through the dictionary's own property name) that holds value; the copy is a %ConstructClone(0) of the body with the
/// field set, and it is sent with Ens.MessageHeader.ResendDuplicatedMessage(original, newId, the original's TargetConfigName, copy). Back in the home
/// namespace the new header id is appended to the run's Copies and saved. The originals are never changed. resent is the number of copies made; skipped
/// holds {"id", "reason"} for each entry that was not resent, the reason a plain sentence that names the message: the production isn't running (a status of
/// ErrProductionNotRunning, with no header made), another refusal, or a change since the re-check. An error thrown for one entry skips that entry and logs
/// one Type 3 warning. A resend that returns an error after its copy was queued (newId is set) counts as resent, with one Type 3 warning.
ClassMethod Resend(namespace As %String, plan As %DynamicArray, run As OcuTalon.Data.FixRun, Output resent As %Integer, Output skipped As %DynamicArray)
{
	Set resent = 0
	Set skipped = []
	Set home = $NAMESPACE
	New $NAMESPACE
	Set iterator = plan.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set id = entry.id
		Set code = ""
		Set detail = ""
		Set newId = ""
		Try {
			Set $NAMESPACE = namespace
			Set header = ##class(Ens.MessageHeader).%OpenId(id)
			If '$IsObject(header) {
				Set code = "gone"
			} ElseIf header.Status '= $$$eMessageStatusError {
				Set code = "status"
			} Else {
				Set bodyClass = header.MessageBodyClassName
				Set body = ""
				If (bodyClass '= "") && (header.MessageBodyId '= "") && ##class(%Dictionary.CompiledClass).%ExistsId(bodyClass) && $ClassMethod(bodyClass, "%Extends", "%Library.Persistent") {
					Set body = $ClassMethod(bodyClass, "%OpenId", header.MessageBodyId)
				}
				If '$IsObject(body) {
					Set code = "body"
				} Else {
					Set property = ##class(%Dictionary.CompiledProperty).%OpenId(bodyClass_"||"_entry.field)
					Set type = ""
					If $IsObject(property) && (property.Name = entry.field) && (property.Private = 0) && (property.Calculated = 0) && (property.Transient = 0) && (property.MultiDimensional = 0) && (property.Relationship = 0) && (property.Collection = "") {
						Set type = ##class(%Dictionary.CompiledClass).%OpenId(property.Type)
					}
					If '$IsObject(type) || (type.ClassType '= "datatype") {
						Set code = "field"
					} ElseIf $Property(body, property.Name) '= entry.value {
						Set code = "changed"
					} Else {
						Set copy = body.%ConstructClone(0)
						Set $Property(copy, property.Name) = entry.repaired
						Set sc = ##class(Ens.MessageHeader).ResendDuplicatedMessage(id, .newId, header.TargetConfigName, copy)
						If $$$ISOK(sc) || (newId '= "") {
							Set code = "sent"
							If $$$ISERR(sc) Set detail = $SYSTEM.Status.GetErrorText(sc)
						} Else {
							Set code = $Select($SYSTEM.Status.Equals(sc, $$$EnsErrProductionNotRunning): "stopped", 1: "refused")
							Set detail = $SYSTEM.Status.GetErrorText(sc)
						}
					}
				}
			}
		} Catch exception {
			Set code = "error"
			Set detail = exception.DisplayString()
		}
		Set $NAMESPACE = home
		If code = "sent" {
			Set resent = resent + 1
			If detail '= "" $$$LOGWARNING(..#LOGCOPY_id_": its copy "_newId_" was queued, and the resend then returned: "_##class(OcuTalon.Bridge.Redact).Text(detail))
			If $IsObject(run) {
				Do run.Copies.Insert(newId)
				Set sc = run.%Save()
				If $$$ISERR(sc) {
					$$$LOGWARNING(..#LOGRUN_run.ApprovalRef_": copy "_newId_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
				}
			}
			Continue
		}
		If (code = "refused") || (code = "error") {
			$$$LOGWARNING(..#LOGCOPY_id_": "_##class(OcuTalon.Bridge.Redact).Text(detail))
		}
		Do skipped.%Push({"id": (id), "reason": (..SkipReason(code, id, entry.field, detail))})
	}
}

/// The plain sentence, naming the message, for a copy that was not made (the codes of Resend); the field is named in words, as the re-check names it.
ClassMethod SkipReason(code As %String, id As %String, field As %String, detail As %String) As %String [ Private ]
{
	Set name = "message "_id
	Set words = ##class(OcuTalon.Fix.Kind.RepairResend).FieldWords(field)
	If code = "stopped" Quit name_" was not resent because the production isn't running"
	If code = "gone" Quit name_" is no longer in the production"
	If code = "status" Quit name_" is no longer in the error status"
	If code = "body" Quit name_" has no body that can be read any more"
	If code = "field" Quit "the "_words_" is no longer a stored field of "_name
	If code = "changed" Quit "the "_words_" of "_name_" changed while the run was starting"
	If code = "refused" Quit name_" was not resent because the production refused the copy"
	Quit name_" was not resent because of an internal error"
}

}
