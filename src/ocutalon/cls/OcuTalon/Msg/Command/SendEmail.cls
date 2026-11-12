/// Sends one email from the session user's own mailbox (AD-1, AD-14, Story 35.2). Owner EmailOut. Origin system (FixExecutor's approved email fix) names the recipients of the approved fix; origin tool only the session user's own address, which CommandsIn checks against email.address and its owner email.owner. No other origin sends it. EmailOut validates the values and enforces the recipients itself (Story 21.6): a tool send only to the own address, a system send only with the ApprovalRef of an executing email fix whose recipients are exactly these.
Class OcuTalon.Msg.Command.SendEmail Extends OcuTalon.Msg.Command
{

/// The recipient addresses, comma-separated.
Property Recipients As %String(MAXLEN = 2000);

/// The subject line.
Property Subject As %String(MAXLEN = 200);

/// The message text.
Property Text As %String(MAXLEN = "");

/// The Ref of the approval request that allows the send. Required for origin system (FixExecutor's approved email fix): EmailOut reads that request
/// and sends once per approval. Empty for origin tool.
Property ApprovalRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="SendEmailDefaultData">
<Subscript>"SendEmail"</Subscript>
<Value name="1">
<Value>Recipients</Value>
</Value>
<Value name="2">
<Value>Subject</Value>
</Value>
<Value name="3">
<Value>Text</Value>
</Value>
<Value name="4">
<Value>ApprovalRef</Value>
</Value>
</Data>
<DefaultData>SendEmailDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
