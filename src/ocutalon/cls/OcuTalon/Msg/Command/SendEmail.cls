/// Sends one email from the session user's own mailbox (AD-1, AD-14, Story 35.2). Owner EmailOut. Origin system (FixExecutor's approved email fix) may name any recipients; origin tool only the session user's own address, which CommandsIn checks against email.address and its owner email.owner. No other origin sends it. EmailOut validates the values.
Class OcuTalon.Msg.Command.SendEmail Extends OcuTalon.Msg.Command
{

/// The recipient addresses, comma-separated.
Property Recipients As %String(MAXLEN = 2000);

/// The subject line.
Property Subject As %String(MAXLEN = 200);

/// The message text.
Property Text As %String(MAXLEN = "");

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
</Data>
<DefaultData>SendEmailDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
