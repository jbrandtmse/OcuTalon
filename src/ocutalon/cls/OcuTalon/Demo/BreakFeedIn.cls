/// BreakFeedIn, the adapterless service through which the demo page breaks the feed (AD-1, AD-12, AD-14). The REST surface creates it
/// in its own process (Ens.Director.CreateBusinessService) and calls ProcessInput with a Demo.Press. Under the session's lock
/// (LOCK +^OcuTalon.Demo.BreakFeed(SessionRef), held to the end) it does these steps, in order:
///   - it asks Guide.Compute(SessionRef).BreakFeed whether the press is available; an inactive press answers its reason, and sends and
///     writes nothing;
///   - it sends IncidentManager a closeForReplay (SendRequestSync) for each of the session's own noticed resolved Orders incidents,
///     oldest first; a refusal (Ok 0) answers incident_in_progress, and nothing more happens;
///   - it writes the session's BreakFeedRun as sending and publishes breakfeed.progress;
///   - it sends PartnerTrigger a SendOrders request (SendRequestSync), which audits the press and makes the partner send the
///     session's batch;
///   - it marks the run sent and publishes breakfeed.progress again.
/// The lock is the only thing that keeps two quick presses from sending two batches: the second finds the first's run in the guide and
/// answers incident_in_progress, and so does a press that can't take the lock in LOCKWAIT seconds. A press is no turn: it makes no Turn and
/// no Decision, never asks the allowance and never sends to WebChatIn or Conversation. Its messages carry the SessionRef, and the session's
/// TraceRef as SuperSession, in a trace session of their own (AD-26).
/// The output is JSON text: {"outcome":"sent","state","startedAt"} or {"outcome":"inactive","reason"}. A bad input (not a Press, an empty
/// SessionRef, a session with no row) is an error status and nothing is written. An error from the close or the send is an error status;
/// a run whose send failed stays sending, and the guide's rule frees the control after NOTICEWAIT seconds. A publish that fails logs one
/// warning, and the press goes on.
Class OcuTalon.Demo.BreakFeedIn Extends Ens.BusinessService
{

/// The channel of the press: one of Msg.Enum CHANNEL.
Parameter CHANNEL = "web";

/// The origin of the close commands: one of Msg.Enum ORIGIN. The press comes from the signed-in page.
Parameter ORIGIN = "web_user";

/// The seconds a press waits for the session's lock.
Parameter LOCKWAIT = 10;

/// The seconds a close waits for IncidentManager's answer.
Parameter CLOSETIMEOUT = 10;

/// The seconds the send waits for PartnerTrigger's answer.
Parameter SENDTIMEOUT = 30;

/// The item that answers a close.
Parameter INCIDENTTARGET = "IncidentManager";

/// The item that makes the partner send.
Parameter TARGET = "PartnerTrigger";

Parameter ERRORINPUT = "BreakFeedIn takes a press of Break the feed from a session, and nothing else.";

Parameter ERRORSESSION = "The press's session has no session row.";

Parameter LOGPUBLISH = "BreakFeedIn could not publish the run's progress: ";

Parameter LOGTRIGGER = "BreakFeedIn could not make the partner send its orders: ";

Parameter LOGCLOSE = "BreakFeedIn could not close a resolved incident for the replay: ";

/// Takes a press; pOutput is the JSON text of the answer.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	If '$IsObject($Get(pInput)) || 'pInput.%IsA("OcuTalon.Demo.Press") || (pInput.SessionRef = "") Quit $SYSTEM.Status.Error(5001, ..#ERRORINPUT)
	Set ref = pInput.SessionRef
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	If '$IsObject(session) Quit $SYSTEM.Status.Error(5001, ..#ERRORSESSION)
	Lock +^OcuTalon.Demo.BreakFeed(ref):..#LOCKWAIT
	If '$Test {
		Set pOutput = ..Inactive("incident_in_progress")
		Quit $SYSTEM.Status.OK()
	}
	Try {
		Set sc = ..Press(session, .pOutput)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Lock -^OcuTalon.Demo.BreakFeed(ref)
	Quit sc
}

/// The steps of a press, under the session's lock; see the class comment.
Method Press(session As OcuTalon.Data.Session, Output output As %String) As %Status [ Private ]
{
	Set output = ""
	Set ref = session.Ref
	Set guide = ##class(OcuTalon.Demo.Guide).Compute(ref)
	If 'guide.BreakFeed.Active {
		Set output = ..Inactive(guide.BreakFeed.Reason)
		Quit $SYSTEM.Status.OK()
	}
	Set ..%SessionId = ""
	Set ..%SuperSession = session.TraceRef

	Set incidents = ##class(OcuTalon.Data.Ownership).ResolvedIncidents(ref, ##class(OcuTalon.Install.Step.Demo).#NAMESPACE, ##class(OcuTalon.Install.Step.Demo).#PRODUCTION, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	For i = 1:1:incidents.Count() {
		Set command = ##class(OcuTalon.Msg.IncidentCommand).%New()
		Set command.Verb = "closeForReplay"
		Set command.IncidentRef = incidents.GetAt(i).Ref
		Set command.SessionRef = ref
		Set command.Origin = ..#ORIGIN
		Kill result
		Set sc = ..Close(command, .result)
		If $SYSTEM.Status.IsError(sc) Quit
		If '$IsObject($Get(result)) || 'result.Ok {
			Set output = ..Inactive("incident_in_progress")
			Quit
		}
	}
	If $SYSTEM.Status.IsError(sc) {
		$$$LOGERROR(..#LOGCLOSE_$SYSTEM.Status.GetErrorText(sc))
		Quit sc
	}
	If output '= "" Quit $SYSTEM.Status.OK()

	Set run = ##class(OcuTalon.Data.BreakFeedRun).Start(ref, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Do ..Progress(ref, run)

	Set request = ##class(OcuTalon.Demo.Msg.SendOrders).%New()
	Set request.SessionRef = ref
	Set request.Channel = ..#CHANNEL
	Set sc = ..Trigger(request)
	If $SYSTEM.Status.IsError(sc) {
		$$$LOGERROR(..#LOGTRIGGER_$SYSTEM.Status.GetErrorText(sc))
		Quit sc
	}
	Set sc = run.MarkSent()
	If $SYSTEM.Status.IsError(sc) Quit sc
	Do ..Progress(ref, run)
	Set output = {"outcome": "sent", "state": (run.State), "startedAt": (run.StartedAt)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// The answer of a press that sent nothing: JSON text.
ClassMethod Inactive(reason As %String) As %String [ Private ]
{
	Quit {"outcome": "inactive", "reason": (reason)}.%ToJSON()
}

/// Publishes the run's progress on the session's stream, the one publisher of breakfeed.progress (AD-33). A failure is logged and
/// the press goes on.
Method Progress(ref As %String, run As OcuTalon.Data.BreakFeedRun) [ Private ]
{
	Set sc = ##class(OcuTalon.Live.Publish).Publish(ref, "breakfeed.progress", ##class(OcuTalon.Live.Payload.BreakFeedProgress).FromRow(run))
	If $SYSTEM.Status.IsError(sc) $$$LOGWARNING(..#LOGPUBLISH_$SYSTEM.Status.GetErrorText(sc))
}

/// The one close of the class: the command to IncidentManager, answered synchronously (AD-15). Private; a test subclass overrides it.
Method Close(command As OcuTalon.Msg.IncidentCommand, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Quit ..SendRequestSync(..#INCIDENTTARGET, command, .result, ..#CLOSETIMEOUT)
}

/// The one send of the class: the request to PartnerTrigger, answered synchronously. Private; a test subclass overrides it.
Method Trigger(request As OcuTalon.Demo.Msg.SendOrders) As %Status [ Private ]
{
	Quit ..SendRequestSync(..#TARGET, request, .response, ..#SENDTIMEOUT)
}

}
