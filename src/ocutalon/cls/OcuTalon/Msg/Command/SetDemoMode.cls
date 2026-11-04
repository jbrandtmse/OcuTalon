/// Switches demo mode (AD-19).
Class OcuTalon.Msg.Command.SetDemoMode Extends OcuTalon.Msg.Command
{

/// The new demo mode setting.
Property DemoMode As %Boolean [ InitialExpression = 0 ];

/// The IRIS user who asked; set by the submitting code from its authenticated context, never from an argument.
Property ActingUser As %String(MAXLEN = 160);

Storage Default
{
<Data name="SetDemoModeDefaultData">
<Subscript>"SetDemoMode"</Subscript>
<Value name="1">
<Value>DemoMode</Value>
</Value>
<Value name="2">
<Value>ActingUser</Value>
</Value>
</Data>
<DefaultData>SetDemoModeDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
