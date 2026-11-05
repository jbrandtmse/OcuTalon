/// Saves one settings section (AD-1, AD-19): the section's slug and its changes as a JSON object of field to value. SettingsOps
/// validates every value against the section's row of its XData Sections before it writes anything. The class has no Section or Values
/// property: this is a persistent message class and VALUES is an SQL reserved word.
Class OcuTalon.Msg.Command.SaveSettings Extends OcuTalon.Msg.Command
{

/// The section: one slug of SettingsOps's XData Sections.
Property Slug As %String(MAXLEN = 32);

/// A JSON object of field name to value.
Property Changes As %String(MAXLEN = "");

/// The IRIS user who asked; set by the submitting code from its authenticated context, never from an argument.
Property ActingUser As %String(MAXLEN = 160);

Storage Default
{
<Data name="SaveSettingsDefaultData">
<Subscript>"SaveSettings"</Subscript>
<Value name="1">
<Value>Slug</Value>
</Value>
<Value name="2">
<Value>Changes</Value>
</Value>
<Value name="3">
<Value>ActingUser</Value>
</Value>
</Data>
<DefaultData>SaveSettingsDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
