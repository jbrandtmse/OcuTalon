/// A message body whose serial property is not XML-enabled: XMLExportToStream fails on it (ERROR #6249), which makes it the fixture of
/// SessionEvents.MessageHits' fallback for the bodies that the key proof's trace search cannot export. Tests save and delete their own.
Class OcuTalon.Test.Web.NoXmlBody Extends Ens.Request
{

Property Label As %String(MAXLEN = 64);

Property Parts As list Of OcuTalon.Test.Web.NoXmlPart;

Storage Default
{
<Data name="NoXmlBodyDefaultData">
<Subscript>"NoXmlBody"</Subscript>
<Value name="1">
<Value>Label</Value>
</Value>
<Value name="2">
<Value>Parts</Value>
</Value>
</Data>
<DefaultData>NoXmlBodyDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
