/// A Telegram chat paired with a session (AD-4, AD-14). Lane B.
Class OcuTalon.Data.Pairing Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Pairing";

/// The ChatRef: the chat reference that messages carry instead of a chat id.
Property Ref As %String(MAXLEN = 22);

/// The owning session's Ref.
Property SessionRef As %String(MAXLEN = 22);

/// The Telegram chat id; never passed to the audit writer or logs (AD-14).
Property ChatId As %String(MAXLEN = 32);

/// The name of the chat; never passed to the audit writer or logs (AD-14).
Property DisplayName As %String(MAXLEN = 128);

/// When the row was created, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

Index SessionRefIndex On SessionRef;

Index ChatIdIndex On ChatId;

Storage Default
{
<Data name="PairingDefaultData">
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
<Value>ChatId</Value>
</Value>
<Value name="5">
<Value>DisplayName</Value>
</Value>
<Value name="6">
<Value>CreatedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.PairingD</DataLocation>
<DefaultData>PairingDefaultData</DefaultData>
<IdLocation>^OcuTalonP.PairingD</IdLocation>
<IndexLocation>^OcuTalonP.PairingI</IndexLocation>
<StreamLocation>^OcuTalonP.PairingS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
