/// The payload of the chat.message live event: one message of the chat. Lane B publishes it.
Class OcuTalon.Live.Payload.ChatMessage Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The turn's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// The page's own id for the message it sent.
Property ClientId As %String(%JSONFIELDNAME = "clientId", MAXLEN = 128);

/// One of Msg.Enum CHANNEL.
Property Channel As %String(%JSONFIELDNAME = "channel", MAXLEN = 32);

/// True when the message was sent from the guide.
Property FromGuide As %Boolean(%JSONFIELDNAME = "fromGuide") [ InitialExpression = 0 ];

/// One of queued, running, done.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 32);

/// The user's message.
Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = "");

/// The reply; empty until the turn is done.
Property ReplyText As %String(%JSONFIELDNAME = "replyText", MAXLEN = "");

/// When the message was created, UTC to the second.
Property CreatedAt As %String(%JSONFIELDNAME = "createdAt", MAXLEN = 20);

/// The turn's trace session id (AD-26).
Property TraceHeaderId As %Integer(%JSONFIELDNAME = "traceHeaderId");

/// The namespace that holds the trace.
Property TraceNamespace As %String(%JSONFIELDNAME = "traceNamespace", MAXLEN = 128);

}
