/// ReminderTimer, the business process that waits for one reminder's due time (AD-5, AD-18). One waiter per reminder, and the waiter is
/// frozen: its one persistent property, Ref, is append-only, and its two methods each call OcuTalon.Schedule.Reminder, where the logic
/// lives. The start stores the start header on the row and sets the timer; the timer's wake fires the reminder if the row is still pending.
Class OcuTalon.Schedule.ReminderTimer Extends Ens.BusinessProcess
{

/// The Ref of the Reminder row that this process waits for.
Property Ref As %String(MAXLEN = 22);

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Quit ##class(OcuTalon.Schedule.Reminder).Start($this, request, .response)
}

Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, pCompletionKey As %String) As %Status
{
	Quit ##class(OcuTalon.Schedule.Reminder).Wake($this, pCompletionKey)
}

Storage Default
{
<Data name="ReminderTimerDefaultData">
<Subscript>"ReminderTimer"</Subscript>
<Value name="1">
<Value>Ref</Value>
</Value>
</Data>
<DefaultData>ReminderTimerDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
