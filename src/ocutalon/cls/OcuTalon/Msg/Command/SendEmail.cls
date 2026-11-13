/// Sends one email from the session user's own mailbox (AD-1, AD-14, Story 35.2). Owner EmailOut. Origin system (FixExecutor's approved email fix) names its approval (ApprovalRef); origin tool only the session user's own address, which CommandsIn checks against email.address and its owner email.owner. No other origin sends it. EmailOut validates the values and enforces the recipients itself (Story 21.6): a tool send only to the own address, a system send only with the ApprovalRef of an executing email fix and only to that fix's recipients. OcuTalon's own producers put no address in the command (Story 22.7, DW-1255): a system send leaves Recipients empty and EmailOut takes the recipients from the approval's row, and a tool send puts the marker OWNADDRESS in Recipients, which means the mailbox's own address (email.address). A command that carries Recipients is checked as it always was. A tool send goes out at most once per IdempotencyKey of its session: after a sent email the same key again sends nothing and answers sent; a send that failed before the server took it can be sent again, and one that may have reached the server or never finished answers failed.
Class OcuTalon.Msg.Command.SendEmail Extends OcuTalon.Msg.Command
{

/// The recipient addresses, comma-separated. OcuTalon's own producers leave it empty (a system send: EmailOut reads the recipients from the approval's
/// row) or put the marker OWNADDRESS in it (a tool send: the mailbox's own address), so that no address travels in the command or its trace (DW-1255).
Property Recipients As %String(MAXLEN = 2000);

/// The Recipients value of a tool send that means the mailbox's own address (the product key email.address). It is not an address, so no value that was ever
/// accepted as a recipient list is the marker.
Parameter OWNADDRESS = "own";

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
