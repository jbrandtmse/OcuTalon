/// Saves the persona of one person (AD-1, AD-19; Epic 40). Origin web_user only: the person's own page, for the session in
/// SessionRef, which the server takes from the signed-in session and never from the client. A tool, an admin or any other
/// origin is refused by CommandsIn. Preset is one of Msg.Enum PERSONAPRESET; Language is used only by the preset language, Custom only by the
/// preset custom. SettingsOps validates the values and writes them.
Class OcuTalon.Msg.Command.SetPersona Extends OcuTalon.Msg.Command
{

/// The preset id.
Property Preset As %String(MAXLEN = "");

/// The language name, used when Preset is language.
Property Language As %String(MAXLEN = "");

/// The person's own words, used when Preset is custom. Not offered on the online demo.
Property Custom As %String(MAXLEN = "");

Storage Default
{
<Data name="SetPersonaDefaultData">
<Subscript>"SetPersona"</Subscript>
<Value name="1">
<Value>Preset</Value>
</Value>
<Value name="2">
<Value>Language</Value>
</Value>
<Value name="3">
<Value>Custom</Value>
</Value>
</Data>
<DefaultData>SetPersonaDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
