/// A message on the simulated phone or mailbox (AD-14). Lane B.
Class OcuTalon.Data.SimMessage Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.SimMsg";

/// The public reference: 22 base64url characters from OcuTalon.Bridge.Ids.NewRef().
Property Ref As %String(MAXLEN = 22);

/// The owning session's Ref.
Property SessionRef As %String(MAXLEN = 22);

/// phone or mailbox.
Property Kind As %String(MAXLEN = 32);

/// in or out.
Property Direction As %String(MAXLEN = 32);

/// The email's ItemId.
Property ItemId As %String(MAXLEN = 22);

/// When the row was created, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

Index SessionRefIndex On SessionRef;

Index ItemIdIndex On ItemId;

Storage Default
{
<Data name="SimMessageDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>SessionRef</Value>
</Value>
<Value name="4">
<Value>Kind</Value>
</Value>
<Value name="5">
<Value>Direction</Value>
</Value>
<Value name="6">
<Value>ItemId</Value>
</Value>
<Value name="7">
<Value>CreatedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.SimMsgD</DataLocation>
<DefaultData>SimMessageDefaultData</DefaultData>
<IdLocation>^OcuTalonP.SimMsgD</IdLocation>
<IndexLocation>^OcuTalonP.SimMsgI</IndexLocation>
<StreamLocation>^OcuTalonP.SimMsgS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
