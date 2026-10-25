Include Ensemble

/// The host sink of OcuTalon (AD-31): the bridge's HostSinkClass setting names it, and it is the one place where the
/// bridge's events become live events (AD-33). It publishes three event types:
///   - decision.recorded {ref}: a decision event on the owner's stream, the payload Live.Payload.Decision.FromRow makes from
///     the row, for every kind of decision. The row is read through Ownership.Decision, so the owner's own row is the only one
///     it finds; an empty or unknown ref, and a payload that is not an object, publish nothing;
///   - turn.step {decisionRef, label}: a turn.step event on the owner's stream with the Ref of the session's running turn,
///     the decision's Ref and the trimmed label, nothing else of the step. It publishes nothing when the label is empty,
///     when the session has no running turn, or when the bridge context of the job is active and belongs to another item
///     than the running turn's (an untrusted Intake turn of the same session);
///   - approval.raised, approval.answered, approval.expired, approval.cancelled and approval.result {ref}: an approval event,
///     the payload Live.Payload.Approval.FromRow makes from the request's row, to each recipient that can see the row. For
///     a session as the owner the recipient is the session itself. For the owner instance the request's IncidentRef comes
///     from Ownership.ApprovalIncident and the recipients are Session.Recipients' sessions, the ones that watch the
///     incident's production. Each recipient reads the row through Ownership.Approval, so a session that can't see it
///     (another session's request, an unnoticed incident's, any instance request with onlineDemo on) gets nothing. An empty
///     or unknown ref, a payload that is not an object, the owner eval and an owner that is no stream publish nothing.
/// decision.recorded and turn.step publish only for a session: the owners eval and instance publish nothing for them.
/// A cross-owner read that fails (the request's incident, the incident's watchers) is logged as a warning that names the
/// event type, the request and the incident, and publishes nothing; a failed read never means that nobody watches, and
/// nobody watching logs nothing (DW-68). budget.capped and the other types do nothing. OnEvent never fails its caller: it
/// returns OK for every input, and an error or an exception is logged as a warning and publishes nothing. It waits for a
/// stream's lock LOCKWAIT seconds, so that a busy stream drops the event: the page's next reload rebuilds its view.
Class OcuTalon.Core.BridgeSink Extends OcuTalon.Bridge.Ext.HostSink
{

/// Seconds to wait for a stream's lock before the event is dropped (AD-31).
Parameter LOCKWAIT = 1;

Parameter ERRORFAILED = "BridgeSink dropped an event: ";

Parameter ERRORPUBLISH = "BridgeSink could not publish an event: ";

Parameter ERRORRECIPIENTS = "BridgeSink could not read who receives an approval event: ";

/// Receives one event of the bridge. Always returns OK.
ClassMethod OnEvent(type As %String, ownerRef As %String, payload As %DynamicObject) As %Status
{
	Try {
		If ..IsApproval($Get(type)) {
			Do ..Approved($Get(type), $Get(ownerRef), $Get(payload))
			Quit
		}
		If '..IsSession($Get(ownerRef)) Quit
		If $Get(type) = ..#DECISIONRECORDED {
			Do ..Recorded(ownerRef, $Get(payload))
		} ElseIf $Get(type) = ..#TURNSTEP {
			Do ..Step(ownerRef, $Get(payload))
		}
	} Catch exception {
		$$$LOGWARNING(..#ERRORFAILED_exception.DisplayString())
	}
	Quit $$$OK
}

/// 1 when ownerRef is a session's Ref: a stream name that is not the instance stream.
ClassMethod IsSession(ownerRef As %String) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Live.Publish).IsStream(ownerRef) && (ownerRef '= ##class(OcuTalon.Live.Publish).#INSTANCE)
}

/// 1 when type is one of the five approval.* event types.
ClassMethod IsApproval(type As %String) As %Boolean [ Private ]
{
	Quit $ListFind($ListBuild(..#APPROVALRAISED, ..#APPROVALANSWERED, ..#APPROVALEXPIRED, ..#APPROVALCANCELLED, ..#APPROVALRESULT), type) > 0
}

/// approval.*: the request with the payload's ref, published as an approval event to each recipient that can see it.
ClassMethod Approved(type As %String, ownerRef As %String, payload As %DynamicObject) [ Private ]
{
	Set ref = ..Member(payload, "ref")
	If ref = "" Quit
	Set recipients = ..Receivers(ownerRef, ref, .incidentRef, .sc)
	If $SYSTEM.Status.IsError(sc) {
		$$$LOGWARNING(..#ERRORRECIPIENTS_type_", request "_ref_", incident "_incidentRef_": "_$SYSTEM.Status.GetOneStatusText(sc))
		Quit
	}
	Set position = 0
	While $ListNext(recipients, position, recipient) {
		Set row = ##class(OcuTalon.Data.Ownership).Approval(ref, recipient, .sc)
		If $SYSTEM.Status.IsError(sc) {
			$$$LOGWARNING(..#ERRORFAILED_type_", request "_ref_", recipient "_recipient_": "_$SYSTEM.Status.GetOneStatusText(sc))
			Continue
		}
		If '$IsObject(row) Continue
		Do ..Publish(recipient, "approval", ##class(OcuTalon.Live.Payload.Approval).FromRow(row, recipient))
	}
}

/// The sessions that receive the approval request of an owner, and the request's incident: a session owner receives it
/// itself, the owner instance gives the sessions that watch the incident of its request, and any other owner, and an
/// instance request that has no incident, give none. sc is an error when a cross-owner read failed.
ClassMethod Receivers(ownerRef As %String, ref As %String, Output incidentRef As %String, Output sc As %Status) As %List [ Private ]
{
	Set sc = $SYSTEM.Status.OK()
	Set incidentRef = ""
	If ownerRef = ##class(OcuTalon.Data.Ownership).#INSTANCE {
		Set incidentRef = ##class(OcuTalon.Data.Ownership).ApprovalIncident(ref, .sc)
		If $SYSTEM.Status.IsError(sc) || (incidentRef = "") Quit ""
	} ElseIf '..IsSession(ownerRef) {
		Quit ""
	}
	Quit ..Recipients(ownerRef, incidentRef, .sc)
}

/// The sessions that receive what the owner owns: Session.Recipients, with sc set to an error when the read failed.
ClassMethod Recipients(ownerRef As %String, incidentRef As %String, Output sc As %Status) As %List [ Private ]
{
	Quit ##class(OcuTalon.Data.Session).Recipients(ownerRef, incidentRef, .sc)
}

/// decision.recorded: the owner's decision with the payload's ref, published as a decision event.
ClassMethod Recorded(ownerRef As %String, payload As %DynamicObject) [ Private ]
{
	Set ref = ..Member(payload, "ref")
	If ref = "" Quit
	Set row = ##class(OcuTalon.Data.Ownership).Decision(ref, ownerRef, .sc)
	If $SYSTEM.Status.IsError(sc) {
		$$$LOGWARNING(..#ERRORFAILED_$SYSTEM.Status.GetOneStatusText(sc))
		Quit
	}
	If '$IsObject(row) Quit
	Do ..Publish(ownerRef, "decision", ##class(OcuTalon.Live.Payload.Decision).FromRow(row))
}

/// turn.step: the label of the step, for the owner's running turn.
ClassMethod Step(ownerRef As %String, payload As %DynamicObject) [ Private ]
{
	Set label = $ZStrip(..Member(payload, "label"), "<>WC")
	If label = "" Quit
	Set queue = ##class(OcuTalon.Data.Ownership).TurnQueue(ownerRef, .sc)
	If $SYSTEM.Status.IsError(sc) {
		$$$LOGWARNING(..#ERRORFAILED_$SYSTEM.Status.GetOneStatusText(sc))
		Quit
	}
	Set running = ""
	For i = 1:1:queue.Count() {
		If queue.GetAt(i).State = "running" {
			Set running = queue.GetAt(i)
			Quit
		}
	}
	If '$IsObject(running) Quit
	If ##class(OcuTalon.Bridge.Context).Active(), ##class(OcuTalon.Bridge.Context).Current().ItemId '= running.ItemId Quit
	Set step = ##class(OcuTalon.Live.Payload.TurnStep).%New()
	Set step.TurnRef = running.Ref
	Set step.DecisionRef = ..Member(payload, "decisionRef")
	Set step.Label = label
	Do ..Publish(ownerRef, "turn.step", step)
}

/// Publishes the payload on the owner's stream, waiting LOCKWAIT seconds for the lock. A failure is logged and goes no further.
ClassMethod Publish(ownerRef As %String, type As %String, payload As %RegisteredObject) [ Private ]
{
	Set sc = ##class(OcuTalon.Live.Publish).Publish(ownerRef, type, payload, , ..#LOCKWAIT)
	If $SYSTEM.Status.IsError(sc) $$$LOGWARNING(..#ERRORPUBLISH_$SYSTEM.Status.GetOneStatusText(sc))
}

/// The member of the payload as text: "" when the payload is not an object, or the member is not a string.
ClassMethod Member(payload As %DynamicObject, name As %String) As %String [ Private ]
{
	If '$IsObject(payload) || ($ClassName(payload) '= "%Library.DynamicObject") Quit ""
	Quit $Select(payload.%GetTypeOf(name) = "string": payload.%Get(name), 1: "")
}

}
