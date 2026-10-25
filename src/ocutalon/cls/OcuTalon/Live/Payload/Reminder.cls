/// The payload of the reminder live event: one reminder. Lane B publishes it.
Class OcuTalon.Live.Payload.Reminder Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The reminder's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// What to be reminded of.
Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = 1000);

/// When the reminder is due, UTC to the second.
Property DueAt As %String(%JSONFIELDNAME = "dueAt", MAXLEN = 20);

/// The reminder state.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 32);

/// True when the reminder fired after its due time.
Property Late As %Boolean(%JSONFIELDNAME = "late") [ InitialExpression = 0 ];

/// The reminder's trace session id (AD-26).
Property TraceHeaderId As %Integer(%JSONFIELDNAME = "traceHeaderId");

/// The namespace that holds the trace.
Property TraceNamespace As %String(%JSONFIELDNAME = "traceNamespace", MAXLEN = 128);

/// The payload for a reminder row, with every row-backed field set. The reminder has no trace of its own, so
/// traceHeaderId and traceNamespace stay empty.
ClassMethod FromRow(row As OcuTalon.Data.Reminder) As OcuTalon.Live.Payload.Reminder
{
	Set payload = ..%New()
	Set payload.Ref = row.Ref
	Set payload.Text = row.Text
	Set payload.DueAt = row.DueAt
	Set payload.State = row.State
	Set payload.Late = row.Late
	Quit payload
}

}
