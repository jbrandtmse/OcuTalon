/// The payload of the approval live event: the public view of one approval request. Lane B publishes it.
Class OcuTalon.Live.Payload.Approval Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The approval request's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// One of Msg.Enum APPROVALKIND.
Property Kind As %String(%JSONFIELDNAME = "kind", MAXLEN = 32);

/// One of Msg.Enum APPROVALSTATE.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 32);

/// The incident's Ref, when the request belongs to one.
Property IncidentRef As %String(%JSONFIELDNAME = "incidentRef", MAXLEN = 22);

/// The tool that waits for the answer.
Property ToolName As %String(%JSONFIELDNAME = "toolName", MAXLEN = 128);

/// Why the request needs an answer.
Property Reason As %String(%JSONFIELDNAME = "reason", MAXLEN = 1000);

/// What the action would do, from the dry run.
Property DryRun As OcuTalon.Live.Payload.Part.DryRun(%JSONFIELDNAME = "dryRun");

/// When the request was raised, UTC to the second.
Property RaisedAt As %String(%JSONFIELDNAME = "raisedAt", MAXLEN = 20);

/// When the request expires, UTC to the second.
Property ExpiresAt As %String(%JSONFIELDNAME = "expiresAt", MAXLEN = 20);

/// The answer's action.
Property AnsweredAction As %String(%JSONFIELDNAME = "answeredAction", MAXLEN = 32);

/// One of Msg.Enum CHANNEL.
Property AnsweredChannel As %String(%JSONFIELDNAME = "answeredChannel", MAXLEN = 32);

/// Who answered.
Property AnsweredBy As %String(%JSONFIELDNAME = "answeredBy", MAXLEN = 128);

/// When the request was answered, UTC to the second.
Property AnsweredAt As %String(%JSONFIELDNAME = "answeredAt", MAXLEN = 20);

/// The result of the approved action.
Property Result As %String(%JSONFIELDNAME = "result", MAXLEN = 32);

/// When the action finished, UTC to the second.
Property FinishedAt As %String(%JSONFIELDNAME = "finishedAt", MAXLEN = 20);

/// The request's trace session id (AD-26).
Property TraceHeaderId As %Integer(%JSONFIELDNAME = "traceHeaderId");

/// The namespace that holds the trace.
Property TraceNamespace As %String(%JSONFIELDNAME = "traceNamespace", MAXLEN = 128);

}
