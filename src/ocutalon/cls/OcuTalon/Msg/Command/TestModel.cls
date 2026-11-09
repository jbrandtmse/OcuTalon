/// Tests the saved first model of one agent (AD-1, AD-8, AD-19; Story 18.3). Agent is TriageAgent, DiagnosisAgent or ChatAgent. CommandsIn takes it from
/// origin web_admin only, and SettingsOps builds the test request with Bridge.Settings.TestRequest, sends it to Decide synchronously and answers
/// Bridge.Settings.TestAnswer's {answered, seconds, reason} as the CommandResult's Data. It writes no setting and no audit entry, and a model test is never retried.
Class OcuTalon.Msg.Command.TestModel Extends OcuTalon.Msg.Command
{

/// The agent to test: one of the three first runner items.
Property Agent As %String(MAXLEN = 32);

Storage Default
{
<Data name="TestModelDefaultData">
<Subscript>"TestModel"</Subscript>
<Value name="1">
<Value>Agent</Value>
</Value>
</Data>
<DefaultData>TestModelDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
