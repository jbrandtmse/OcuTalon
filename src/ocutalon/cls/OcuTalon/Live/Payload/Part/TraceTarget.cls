/// One trace target: the message header and its namespace (AD-26). Shared by both lanes, owned by Lane B.
Class OcuTalon.Live.Payload.Part.TraceTarget Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The trace's session id.
Property TraceHeaderId As %Integer(%JSONFIELDNAME = "traceHeaderId");

/// The namespace that holds the trace.
Property TraceNamespace As %String(%JSONFIELDNAME = "traceNamespace", MAXLEN = 128);

}
