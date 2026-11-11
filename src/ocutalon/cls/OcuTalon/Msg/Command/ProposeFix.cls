/// Asks, for one of the session's own incidents, for a fix of a kind the chat may ask for (Story 23.2; AD-1, AD-16): suspend_item, resume_item, reroute or partner_warning (Story 23.5). The incident's owner,
/// IncidentManager, asks FixExecutor for the kind's dry run and raises the approval request itself; this command only names what is wanted.
Class OcuTalon.Msg.Command.ProposeFix Extends OcuTalon.Msg.Command
{

/// The incident the fix is for.
Property IncidentRef As %String(MAXLEN = 22);

/// The fix kind's name (Fix.Kind NAME).
Property FixKind As %String(MAXLEN = 64);

/// The kind's parameters, as one JSON object.
Property Parameters As %String(MAXLEN = 1000);

Storage Default
{
<Data name="ProposeFixDefaultData">
<Subscript>"ProposeFix"</Subscript>
<Value name="1">
<Value>IncidentRef</Value>
</Value>
<Value name="2">
<Value>FixKind</Value>
</Value>
<Value name="3">
<Value>Parameters</Value>
</Value>
</Data>
<DefaultData>ProposeFixDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
