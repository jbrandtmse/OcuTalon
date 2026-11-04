/// A request to IncidentManager, which alone writes incidents; it answers synchronously (AD-15). Lane A handles it.
Class OcuTalon.Msg.IncidentCommand Extends OcuTalon.Msg.Command
{

/// The verbs of an incident command (AD-15).
Parameter VERBS = "dismiss,closeForReplay,closeQuiet";

/// One of VERBS.
Property Verb As %String(MAXLEN = 32);

/// The incident that the verb applies to.
Property IncidentRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="IncidentCommandDefaultData">
<Subscript>"IncidentCommand"</Subscript>
<Value name="1">
<Value>Verb</Value>
</Value>
<Value name="2">
<Value>IncidentRef</Value>
</Value>
</Data>
<DefaultData>IncidentCommandDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
