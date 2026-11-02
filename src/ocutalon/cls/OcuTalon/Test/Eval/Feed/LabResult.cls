/// A lab result as the test feed's partner sends it (Story 9.9; AD-22). Every property is text, so that any body saves and reaches its item: the typed
/// record that RECORDCLASS names decides whether the values are valid. It shares the Ens.MessageBody extent and sets no DEFAULTGLOBAL (a message, not a
/// table). The values are synthetic.
Class OcuTalon.Test.Eval.Feed.LabResult Extends (Ens.Request, %JSON.Adaptor)
{

/// The typed record that Intake validates this message as.
Parameter RECORDCLASS = "OcuTalon.Test.Eval.Feed.ChartResult";

Property ResultId As %String(MAXLEN = 40);

Property PatientRef As %String(MAXLEN = 40);

Property TestCode As %String(MAXLEN = 40);

/// The measured value, written as the lab writes it.
Property ResultValue As %String(MAXLEN = 40);

Property Units As %String(MAXLEN = 40);

Storage Default
{
<Data name="LabResultDefaultData">
<Subscript>"LabResult"</Subscript>
<Value name="1">
<Value>ResultId</Value>
</Value>
<Value name="2">
<Value>PatientRef</Value>
</Value>
<Value name="3">
<Value>TestCode</Value>
</Value>
<Value name="4">
<Value>ResultValue</Value>
</Value>
<Value name="5">
<Value>Units</Value>
</Value>
</Data>
<DefaultData>LabResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
