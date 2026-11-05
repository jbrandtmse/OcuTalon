/// Sends the session's digest now (AD-1, AD-14, AD-32; Story 17.6's digest tool and Story 18.2's Send my digest now). It has only the base fields
/// of a command and no recipient, channel or address of any kind: the digest goes to the session's own digest.channels, so neither the model nor
/// an item chooses where it goes. Its SessionRef is the session whose channels are used, and CommandsIn refuses a tool that names another one.
Class OcuTalon.Msg.Command.SendDigest Extends OcuTalon.Msg.Command
{

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
