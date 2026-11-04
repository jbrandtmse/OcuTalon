/// The request that CommandsIn sends the Checks item for the RunHeartbeat command (AD-1, AD-18, AD-33): a person asks for a heartbeat beat now. Checks answers
/// it OK with an OcuTalon.Msg.CommandResult, and sends Intake the beat's Item when the beat runs (Checks.Process, Story 39.3). Lane A.
Class OcuTalon.Checks.Msg.BeatNow Extends Ens.Request
{

/// The Ref of the person's session, set by CommandsIn from the server-side session.
Property SessionRef As %String(MAXLEN = 22);

/// When the run was asked for: UTC to the second.
Property RequestedAt As %String(MAXLEN = 20);

Storage Default
{
<Data name="BeatNowDefaultData">
<Subscript>"BeatNow"</Subscript>
<Value name="1">
<Value>SessionRef</Value>
</Value>
<Value name="2">
<Value>RequestedAt</Value>
</Value>
</Data>
<DefaultData>BeatNowDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
