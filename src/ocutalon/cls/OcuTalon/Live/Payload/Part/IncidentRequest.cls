/// One approval request of an incident: its Ref, state, fix kind and result. Lane A.
Class OcuTalon.Live.Payload.Part.IncidentRequest Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The approval request's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// One of Msg.Enum APPROVALSTATE.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 32);

/// The name of the request's fix kind (Fix.Kind NAME), such as repair_resend, suspend_item, resume_item, reroute (Story 23.2) or partner_warning (Story 23.5).
Property FixKind As %String(%JSONFIELDNAME = "fixKind", MAXLEN = 64);

/// The item a suspend or resume changes, and the item a reroute sends the messages to (the request's parameters); empty for any other kind.
Property Item As %String(%JSONFIELDNAME = "item", MAXLEN = 128);

/// The number of messages a reroute's dry run said it affects; empty for any other kind.
Property Count As %Integer(%JSONFIELDNAME = "count");

/// What the resend did; empty until it ran.
Property Result As OcuTalon.Live.Payload.Part.IncidentRequestResult(%JSONFIELDNAME = "result");

}
