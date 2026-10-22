/// The answer Decide gives for turn and tool requests (AD-6). Lane A.
Class OcuTalon.Bridge.Msg.Reply Extends OcuTalon.Bridge.Msg.Result
{

/// The reply text.
Property Text As %String(MAXLEN = "");

/// True when untrusted content reached the turn (AD-10).
Property Tainted As %Boolean [ InitialExpression = 0 ];

/// True when the runner moved the conversation to a fresh AI session.
Property SessionRotated As %Boolean [ InitialExpression = 0 ];

/// True when any tool ran.
Property ToolsRun As %Boolean [ InitialExpression = 0 ];

/// True when the provider rejected the stored history (AD-8).
Property SessionBroken As %Boolean [ InitialExpression = 0 ];

/// True when Decide refused a turn because its conversation lock was still held after 2 seconds; such a reply has no text and no decision (AD-6).
Property Busy As %Boolean [ InitialExpression = 0 ];

/// JSON a tool may fill, such as check rows (AD-6).
Property HostData As %String(MAXLEN = "");

/// The provider's stop reason from Response.Extra, such as refusal or max_tokens; empty when it reports none (AD-8).
Property FinishReason As %String(MAXLEN = 32);

/// The agent steps of the call as a JSON array of {"kind","label","summary","durationMs","status","estimatedTokens"} records, in order,
/// redacted and cut (OcuTalon.Bridge.Redact); the runner fills it and Decide sends each record to AgentSteps as an AgentStep (AD-9).
/// Decide's own answer to a turn leaves it empty.
Property Steps As %String(MAXLEN = "");

/// A reply that says the conversation was busy: Busy is true and nothing else is set (AD-6).
/// Decide answers a refused turn with it and never signals busy with an error status.
ClassMethod NewBusy() As Reply
{
	Set reply = ..%New()
	Set reply.Busy = 1
	Quit reply
}

Storage Default
{
<Data name="ReplyDefaultData">
<Subscript>"Reply"</Subscript>
<Value name="1">
<Value>Text</Value>
</Value>
<Value name="2">
<Value>Tainted</Value>
</Value>
<Value name="3">
<Value>SessionRotated</Value>
</Value>
<Value name="4">
<Value>ToolsRun</Value>
</Value>
<Value name="5">
<Value>SessionBroken</Value>
</Value>
<Value name="6">
<Value>Busy</Value>
</Value>
<Value name="7">
<Value>HostData</Value>
</Value>
<Value name="8">
<Value>FinishReason</Value>
</Value>
<Value name="9">
<Value>Steps</Value>
</Value>
</Data>
<DefaultData>ReplyDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
