/// Asks, for one of the session's own incidents, for a drafted data transform (Story 27.1 creates the verb under the name Story 28.1 fixes; AD-1, AD-29). The incident's owner,
/// IncidentManager, answers it; until Story 28.1 writes its handler it answers failed. Only the origin tool sends it, and only for an incident the session can see
/// (Core.CommandsIn), through Core.Commands.Submit.
Class OcuTalon.Msg.Command.DraftTransform Extends OcuTalon.Msg.Command
{

/// The incident the transform is for.
Property IncidentRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="DraftTransformDefaultData">
<Subscript>"DraftTransform"</Subscript>
<Value name="1">
<Value>IncidentRef</Value>
</Value>
</Data>
<DefaultData>DraftTransformDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
