Include (EnsConstants, EnsErrors)

/// FixExecutor, the business operation that works out and carries out an approved fix (AD-16; Stories 7.1 and 7.3). Its item keeps PoolSize 1, so one job takes
/// one request at a time. It answers a Fix.Msg.DryRun and handles a Fix.Msg.Execute; any other request is the error 5001, which names its class.
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
///          A run that cannot start (2 and 3) saves its FixRun row (no copies), closes the request failed through Approval.FinishExecution (which accepts a request
///          that still is approved) and then sends IncidentManager one FixResult: Final 1, Total the number of targets, Resent, Completed, FailedAgain and Skipped 0,
///          and the plain Reason.
///       4. Approval.StartExecution moves the request from approved to executing, atomically; an error there is a refusal as in 1.
///       5. The run: the FixRun row is saved (the request's Ref, the incident's, the start time); the kind's Recheck reads all the targets before any copy is
///          made; the kind's Execute resends a repaired copy of each target that passed (Fix.Kind.RepairResend: through Resend, below) and registers each copy's
///          header id on the FixRun (Copies). A re-check that cannot read the production, or an error before any copy was made, ends like a run that cannot start,
///          with the reason NOREAD and one Type 3 warning (LOGRECHECK).
///       A run that resent nothing (every target was skipped) closes the request done and sends one final FixResult: Total the number of targets, Skipped the same
///       number, Resent, Completed and FailedAgain 0, and the plain Reason of the lowest skipped target. A run that resent at least one copy ends after its last
///       registration with its request still executing and no FixResult: the 60-second wait, the counts of the copies and the end of such a run are Story 7.4's,
///       so that no final result goes out before its copies are counted. The originals are never changed.
///     A failed FinishExecution (LOGFINISH) or a failed send (LOGRESULT) logs one Type 3 warning and the FixResult still goes. Log text goes through Bridge.Redact.
///   - Resend is the only method of the executor that switches namespace (AD-3, AD-16): it opens the original header and body in the production's namespace,
///     calling no OcuTalon class there, and resends each copy with Ens.MessageHeader.ResendDuplicatedMessage.
///   - The seams SendResult (the send to IncidentManager), Missing (the resources check), Check (the kind's Recheck) and Carry (the kind's Execute) are private
///     methods that a test subclass overrides (Test.Fix.ExecutorProbe).
/// FixExecutor calls no model. Lane A.
Class OcuTalon.Fix.Executor Extends Ens.BusinessOperation
{

/// The item that receives the FixResult (AD-16).
Parameter MANAGER = "IncidentManager";

/// The reasons of a run that cannot start without resources (the kind's NOTALLOWED is the third): the row cannot be used, and the failed messages cannot be read.
/// They render as "Nothing was resent: {reason}. Nothing was changed." (public text, veto U-141).
Parameter UNUSABLE = "OcuTalon couldn't read the approved fix";

Parameter NOREAD = "OcuTalon couldn't read the failed messages in that production";

/// The start of each log line of the executor.
Parameter LOGREFUSED = "FixExecutor refused an Execute for request ";

Parameter LOGFINISH = "FixExecutor could not close request ";

Parameter LOGRESULT = "FixExecutor could not send the result of request ";

Parameter LOGRECHECK = "FixExecutor could not read the failed messages for request ";

Parameter LOGCOPY = "FixExecutor could not resend message ";

Parameter LOGRUN = "FixExecutor could not save the run of request ";

Parameter LOGMISSING = "FixExecutor could not check the resources for request ";

/// The status of a request that is approved, a fix, and the state of a run that has started.
Parameter APPROVED = "approved";

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
	Set sc = ##class(OcuTalon.Bridge.Approval).StartExecution(ref)
	If $$$ISERR(sc) {
		Do ..Refuse(ref, "it could not be started: "_$SYSTEM.Status.GetErrorText(sc))
		Quit $$$OK
	}
	Do ..Run(row, incident, class, parameters, total)
	Quit $$$OK
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

/// The run (steps 4 to 5 of the class description) of a request that StartExecution has moved to executing.
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
		If copies = 0 Do ..CouldNotStart(row, total, ..#NOREAD, $IsObject(run) && (run.%Id() '= ""))
		Quit
	}
	If copies > 0 Quit
	Do ..Close(row.Ref, "done")
	Do ..Report(row, total, total, ..FirstReason(skipped))
}

/// The run's FixRun row, saved with no copies, the request closed failed (FinishExecution accepts it while it still is approved or already executing) and
/// then one final FixResult with the reason. A FixRun that cannot be saved logs one Type 3 warning and the run still ends. saved is 1 when the run's FixRun
/// has been saved already (the re-check ran).
Method CouldNotStart(row As OcuTalon.Bridge.Data.ApprovalRequest, total As %Integer, reason As %String, saved As %Boolean) [ Private ]
{
	If 'saved {
		Set run = ##class(OcuTalon.Data.FixRun).%New()
		Set run.ApprovalRef = row.Ref
		Set run.IncidentRef = row.IncidentRef
		Set run.StartedAt = ##class(OcuTalon.Data.Time).NowUtc()
		Set sc = run.%Save()
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGRUN_row.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		}
	}
	Do ..Close(row.Ref, "failed")
	Do ..Report(row, total, 0, reason)
}

/// Closes the request through FinishExecution with the result (done or failed). A failure logs one Type 3 warning; the run goes on to its FixResult.
Method Close(ref As %String, result As %String) [ Private ]
{
	Set sc = ##class(OcuTalon.Bridge.Approval).FinishExecution(ref, result)
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGFINISH_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
}

/// Sends IncidentManager the one final FixResult of a run that resent nothing: Total the number of targets, Skipped the given number, Resent, Completed and
/// FailedAgain 0 and the reason (redacted, at most 1000 characters). A failed send logs one Type 3 warning.
Method Report(row As OcuTalon.Bridge.Data.ApprovalRequest, total As %Integer, skipped As %Integer, reason As %String) [ Private ]
{
	Set result = ##class(OcuTalon.Fix.Msg.FixResult).%New()
	Set result.ApprovalRef = row.Ref
	Set result.IncidentRef = row.IncidentRef
	Set result.Final = 1
	Set result.Total = total
	Set result.Resent = 0
	Set result.Completed = 0
	Set result.FailedAgain = 0
	Set result.Skipped = skipped
	Set result.Reason = $Extract(##class(OcuTalon.Bridge.Redact).Text(reason), 1, 1000)
	Set sc = ..SendResult(result)
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGRESULT_row.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
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

/// The plain sentence, naming the message, for a copy that was not made (the codes of Resend).
ClassMethod SkipReason(code As %String, id As %String, field As %String, detail As %String) As %String [ Private ]
{
	Set name = "message "_id
	If code = "stopped" Quit name_" was not resent because the production isn't running"
	If code = "gone" Quit name_" is no longer in the production"
	If code = "status" Quit name_" is no longer in the error status"
	If code = "body" Quit name_" has no body that can be read any more"
	If code = "field" Quit "the field "_field_" is no longer a stored field of "_name
	If code = "changed" Quit "the field "_field_" of "_name_" changed while the run was starting"
	If code = "refused" Quit name_" was not resent because the production refused the copy"
	Quit name_" was not resent because of an internal error"
}

}
