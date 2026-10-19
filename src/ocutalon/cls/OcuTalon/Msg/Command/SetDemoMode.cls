/// Switches demo mode (AD-19).
Class OcuTalon.Msg.Command.SetDemoMode Extends OcuTalon.Msg.Command
{

/// The new demo mode setting.
Property DemoMode As %Boolean [ InitialExpression = 0 ];

Storage Default
{
<Data name="SetDemoModeDefaultData">
<Subscript>"SetDemoMode"</Subscript>
<Value name="1">
<Value>DemoMode</Value>
</Value>
</Data>
<DefaultData>SetDemoModeDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
