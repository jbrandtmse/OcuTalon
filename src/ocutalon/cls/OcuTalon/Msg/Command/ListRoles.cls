/// Lists the IRIS users who hold an OcuTalon role (Story 25.4, AD-24). It has no property: the CommandResult's Data is {"handoff": uri}, the SecretHandoff uri of
/// the list, so that no user's name is in a traced message.
Class OcuTalon.Msg.Command.ListRoles Extends OcuTalon.Msg.Command
{

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
