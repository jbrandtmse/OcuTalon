/// Starts or checks the mailbox's OAuth2 sign-in (AD-1, AD-19; Story 21.3). CommandsIn takes it from origin web_admin only, and SettingsOps carries it out:
/// start answers the address that opens IRIS's authorization flow in a new tab (the Data of the CommandResult is {"url"}), and check answers whether IRIS's
/// OAuth2 client holds the mailbox's tokens ({"signedIn"}). It carries no secret and no token, and writes no setting; a start that has to enable IRIS's
/// redirection endpoint writes the Settings audit entry of that, in the name of ActingUser.
Class OcuTalon.Msg.Command.MailSignIn Extends OcuTalon.Msg.Command
{

/// What to do: start or check.
Property Action As %String(MAXLEN = 16);

/// The http or https origin of the page (the Origin of the command is the channel that sent it), from which the return address comes.
Property PageOrigin As %String(MAXLEN = 300);

/// The IRIS user who asked; set by the submitting code from its authenticated context, never from an argument.
Property ActingUser As %String(MAXLEN = 160);

Storage Default
{
<Data name="MailSignInDefaultData">
<Subscript>"MailSignIn"</Subscript>
<Value name="1">
<Value>Action</Value>
</Value>
<Value name="2">
<Value>PageOrigin</Value>
</Value>
<Value name="3">
<Value>ActingUser</Value>
</Value>
</Data>
<DefaultData>MailSignInDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
