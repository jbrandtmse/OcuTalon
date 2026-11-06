/// Saves the heartbeat settings of one person (AD-1, AD-18, AD-19; Epic 39). Origin web_user only: the person's own page, for the session in
/// SessionRef, which the server takes from the signed-in session and never from the client. A tool, an admin or any other origin is refused by
/// CommandsIn. On is "1" or "0", Interval the minutes, From and To the active hours as HH:MM (both empty for all day) and Checklist the person's
/// own words. SettingsOps validates the values and writes them; none of them is judged by the message class.
Class OcuTalon.Msg.Command.SetHeartbeat Extends OcuTalon.Msg.Command
{

/// "1" for on, "0" for off.
Property On As %String(MAXLEN = "") [ SqlFieldName = HeartbeatOn ];

/// The minutes between the beats, as the text of a whole number.
Property Interval As %String(MAXLEN = "") [ SqlFieldName = HeartbeatInterval ];

/// The start of the active hours, HH:MM, or empty with To for all day.
Property From As %String(MAXLEN = "") [ SqlFieldName = HeartbeatFrom ];

/// The end of the active hours, HH:MM, or empty with From for all day.
Property To As %String(MAXLEN = "") [ SqlFieldName = HeartbeatTo ];

/// What the person wants the beat to look at.
Property Checklist As %String(MAXLEN = "");

Storage Default
{
<Data name="SetHeartbeatDefaultData">
<Subscript>"SetHeartbeat"</Subscript>
<Value name="1">
<Value>On</Value>
</Value>
<Value name="2">
<Value>Interval</Value>
</Value>
<Value name="3">
<Value>From</Value>
</Value>
<Value name="4">
<Value>To</Value>
</Value>
<Value name="5">
<Value>Checklist</Value>
</Value>
</Data>
<DefaultData>SetHeartbeatDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
