/// A serial object that is not XML-enabled (it does not extend %XML.Adaptor): the part of Test.Web.NoXmlBody, so that the body cannot be
/// exported as XML, as a message body whose serial property is not XML-enabled cannot (the case of SessionEvents.MessageHits' fallback).
Class OcuTalon.Test.Web.NoXmlPart Extends %SerialObject
{

Property Text As %String(MAXLEN = 200);

Storage Default
{
<Data name="NoXmlPartState">
<Value name="1">
<Value>Text</Value>
</Value>
</Data>
<State>NoXmlPartState</State>
<StreamLocation>^OcuTalon.Test.Web.NoXmlPartS</StreamLocation>
<Type>%Storage.Serial</Type>
}
}
