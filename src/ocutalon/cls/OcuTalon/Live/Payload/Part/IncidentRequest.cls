/// One approval request of an incident: its Ref, state and result. Lane A.
Class OcuTalon.Live.Payload.Part.IncidentRequest Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The approval request's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// One of Msg.Enum APPROVALSTATE.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 32);

/// What the resend did; empty until it ran.
Property Result As OcuTalon.Live.Payload.Part.IncidentRequestResult(%JSONFIELDNAME = "result");

}
