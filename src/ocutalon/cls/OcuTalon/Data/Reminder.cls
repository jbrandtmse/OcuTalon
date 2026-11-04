/// A reminder; the row is the truth and its ReminderTimer waiter mirrors it (AD-5, AD-18). Lane B.
Class OcuTalon.Data.Reminder Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Reminder";

/// The public reference: 22 base64url characters from OcuTalon.Bridge.Ids.NewRef().
Property Ref As %String(MAXLEN = 22);

/// The owning session's Ref.
Property SessionRef As %String(MAXLEN = 22);

/// What to remind the user of.
Property Text As %String(MAXLEN = 1000);

/// When the reminder is due, UTC to the second.
Property DueAt As %String(MAXLEN = 20);

/// pending, fired or cancelled.
Property State As %String(MAXLEN = 32);

/// True when the reminder fired more than 10 seconds after its due time (AD-18).
Property Late As %Boolean [ InitialExpression = 0 ];

/// When the row was created, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

/// The start header of the reminder's waiter (a ReminderTimer): the id of its trace session and the target of its trace link (AD-18, AD-26).
/// Empty until the waiter has started.
Property TraceHeaderId As %Integer;

/// The IdempotencyKey of the SetReminder that created the row, or empty (AD-1). A repeat of that command is answered from this row.
Property IdempotencyKey As %String(MAXLEN = 128);

/// The IdempotencyKey of the CancelReminder that cancelled the row, or empty (AD-1). A repeat of that command is answered from this row.
Property CancelKey As %String(MAXLEN = 128);

Index RefIndex On Ref [ Unique ];

Index SessionRefIndex On SessionRef;

Storage Default
{
<Data name="ReminderDefaultData">
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
<Value>Text</Value>
</Value>
<Value name="5">
<Value>DueAt</Value>
</Value>
<Value name="6">
<Value>State</Value>
</Value>
<Value name="7">
<Value>Late</Value>
</Value>
<Value name="8">
<Value>CreatedAt</Value>
</Value>
<Value name="9">
<Value>TraceHeaderId</Value>
</Value>
<Value name="10">
<Value>IdempotencyKey</Value>
</Value>
<Value name="11">
<Value>CancelKey</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.ReminderD</DataLocation>
<DefaultData>ReminderDefaultData</DefaultData>
<IdLocation>^OcuTalonP.ReminderD</IdLocation>
<IndexLocation>^OcuTalonP.ReminderI</IndexLocation>
<StreamLocation>^OcuTalonP.ReminderS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
