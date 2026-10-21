/// The base of every command verb (AD-1, AD-29). Lane B.
Class OcuTalon.Msg.Command Extends Ens.Request [ Abstract ]
{

/// Every command is answered with a CommandResult (AD-1).
Parameter RESPONSECLASSNAME = "OcuTalon.Msg.CommandResult";

/// One of Msg.Enum ORIGIN, set by Commands.Submit from the authenticated context, never from the payload (AD-1).
Property Origin As %String(MAXLEN = 32);

/// A repeat with the same key is ignored by the owner: the turn's ItemId plus the tool call's position (AD-1).
Property IdempotencyKey As %String(MAXLEN = 128);

/// The owning session's Ref.
Property SessionRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="CommandDefaultData">
<Subscript>"Command"</Subscript>
<Value name="1">
<Value>Origin</Value>
</Value>
<Value name="2">
<Value>IdempotencyKey</Value>
</Value>
<Value name="3">
<Value>SessionRef</Value>
</Value>
</Data>
<DefaultData>CommandDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
