/// The parameters of a repair_resend fix as the diagnosis names them (AD-15): the field to repair and the format it has and should have. A part of
/// OcuTalon.Watch.Msg.DiagnosisPayload. Lane A.
Class OcuTalon.Watch.Msg.FixParameters Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The field of the message body that the fix repairs.
Property Field As %String(%JSONFIELDNAME = "field", MAXLEN = 128);

/// The format the field has in the failed messages.
Property SourceFormat As %String(%JSONFIELDNAME = "sourceFormat", MAXLEN = 64);

/// The format the field should have.
Property TargetFormat As %String(%JSONFIELDNAME = "targetFormat", MAXLEN = 64);

}
