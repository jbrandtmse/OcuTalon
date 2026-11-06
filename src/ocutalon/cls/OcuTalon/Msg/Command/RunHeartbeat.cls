/// Asks for a heartbeat beat now (AD-1, AD-18; Epic 39). Origin web_user only: the person's own page, for the session in SessionRef, which the
/// server takes from the signed-in session. It has no property of its own: CommandsIn sends it to the Checks item as an
/// OcuTalon.Checks.Msg.BeatNow, whose answer (sent, or the reason a beat is held) is the command's result.
Class OcuTalon.Msg.Command.RunHeartbeat Extends OcuTalon.Msg.Command
{

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
