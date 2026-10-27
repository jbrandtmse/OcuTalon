/// A message on the simulated phone or mailbox (AD-14). Lane B. A phone message (Kind phone) is recorded by SimPhoneOut with the
/// text as the device shows it; the mailbox's rows (Kind mailbox) carry the email's Sender and Subject. An incoming email (by
/// SimMailboxIn) carries an ItemId; sent mail (by SimMailboxOut) has none. A row written before Sender and Subject existed
/// reads them as empty.
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

/// The message's text as the device shows it; empty for a row that has none.
Property Text As %String(MAXLEN = "");

/// The email's sender, as the From line gives it; empty for a phone row.
Property Sender As %String(MAXLEN = 1000);

/// The email's subject; empty for a phone row.
Property Subject As %String(MAXLEN = 1000);

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
<Value name="8">
<Value>Text</Value>
</Value>
<Value name="9">
<Value>Sender</Value>
</Value>
<Value name="10">
<Value>Subject</Value>
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
