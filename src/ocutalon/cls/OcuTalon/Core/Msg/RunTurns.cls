/// The request that tells Conversation to start the next turn of a session, or to sweep every session after a start (AD-30).
/// WebChatIn forwards it unchanged, and Conversation sends it to itself when a turn is done and another is queued.
Class OcuTalon.Core.Msg.RunTurns Extends Ens.Request
{

/// The session whose next turn starts; empty means every session: the sweep puts each running turn back in its queue and
/// starts the sessions that have queued turns.
Property SessionRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="RunTurnsDefaultData">
<Subscript>"RunTurns"</Subscript>
<Value name="1">
<Value>SessionRef</Value>
</Value>
</Data>
<DefaultData>RunTurnsDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
