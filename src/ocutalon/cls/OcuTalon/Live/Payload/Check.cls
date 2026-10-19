/// The payload of the check live event: one background check. Lane A publishes it.
Class OcuTalon.Live.Payload.Check Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The check's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// The kind of check.
Property Kind As %String(%JSONFIELDNAME = "kind", MAXLEN = 32);

/// The namespace of the watched production.
Property Namespace As %String(%JSONFIELDNAME = "namespace", MAXLEN = 128);

/// The watched production class.
Property Production As %String(%JSONFIELDNAME = "production", MAXLEN = 128);

/// The production's display name.
Property DisplayName As %String(%JSONFIELDNAME = "displayName", MAXLEN = 128);

/// True when the production is stopped.
Property Stopped As %Boolean(%JSONFIELDNAME = "stopped") [ InitialExpression = 0 ];

/// When the check runs next, UTC to the second.
Property NextDueAt As %String(%JSONFIELDNAME = "nextDueAt", MAXLEN = 20);

/// When the check last ran, UTC to the second.
Property LastRunAt As %String(%JSONFIELDNAME = "lastRunAt", MAXLEN = 20);

/// One of Msg.Enum CHECKRESULT.
Property Result As %String(%JSONFIELDNAME = "result", MAXLEN = 32);

/// What the last run found.
Property Finding As %String(%JSONFIELDNAME = "finding", MAXLEN = 1000);

/// The check's trace session id (AD-26).
Property TraceHeaderId As %Integer(%JSONFIELDNAME = "traceHeaderId");

/// The namespace that holds the trace.
Property TraceNamespace As %String(%JSONFIELDNAME = "traceNamespace", MAXLEN = 128);

}
