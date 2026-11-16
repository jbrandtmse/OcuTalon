/// One approval request of an incident: its Ref, state, fix kind, the item, count and after of the kinds that name them, and its result. Lane A.
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

/// The value that the dry run of a setting kind's request (rollback_setting, undo_rollback; Story 23.3, DW-1378) gives the setting after the run, as the result notice's {after}
/// shows it (Watch.SettingCause ShownAfter: redacted by Bridge.Redact); empty for any other kind and when the dry run has none.
Property After As %String(%JSONFIELDNAME = "after", MAXLEN = 1000);

/// What the resend did; empty until it ran.
Property Result As OcuTalon.Live.Payload.Part.IncidentRequestResult(%JSONFIELDNAME = "result");

}
