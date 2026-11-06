/// A proposal of a persona for one person (AD-1, AD-11, AD-19; Epic 40). Origin tool only: the propose_persona tool of a turn that
/// began with the person's own message. SessionRef is the turn's owner. The values are those of SetPersona, and a proposal
/// changes nothing by itself: the person answers an approval request.
Class OcuTalon.Msg.Command.ProposePersona Extends OcuTalon.Msg.Command
{

/// The preset id.
Property Preset As %String(MAXLEN = "");

/// The language name, used when Preset is language.
Property Language As %String(MAXLEN = "") [ SqlFieldName = PersonaLanguage ];

/// The proposed own words, used when Preset is custom. Not offered on the online demo.
Property Custom As %String(MAXLEN = "");

Storage Default
{
<Data name="ProposePersonaDefaultData">
<Subscript>"ProposePersona"</Subscript>
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
<DefaultData>ProposePersonaDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
