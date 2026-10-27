/// A stand-in for the ReminderTimer that OcuTalon.Schedule.Reminder.Wake acts on, for the tests of the firing rule that need no production.
/// It has the Ref, and it records each timer set and each request sent instead of doing them; the status that SendRequestAsync answers
/// is set by the test. It has no Test methods and the product never refers to it.
Class OcuTalon.Test.Schedule.ReminderTimerDouble Extends %RegisteredObject
{

/// The Ref of the Reminder row that the waiter waits for.
Property Ref As %String(MAXLEN = 22);

/// The timers set, one "seconds|completionKey" string per call.
Property Timers As %DynamicArray;

/// The requests sent, one {target, kind, key, slots, session, responseRequired, storedState} object per call; storedState is the
/// State of the Ref's row as it is saved at the moment of the send ("" when there is no row).
Property Sent As %DynamicArray;

/// The status that SendRequestAsync answers.
Property SendStatus As %Status [ InitialExpression = 1 ];

Method %OnNew(ref As %String = "") As %Status
{
	Set ..Ref = ref
	Set ..Timers = []
	Set ..Sent = []
	Quit $$$OK
}

Method SetTimer(seconds As %Integer, key As %String) As %Status
{
	Do ..Timers.%Push(seconds _ "|" _ key)
	Quit $$$OK
}

Method SendRequestAsync(target As %String, request As %RegisteredObject, responseRequired As %Boolean = 1, completionKey As %String = "", description As %String = "") As %Status
{
	Set stored = ""
	If ##class(OcuTalon.Data.Reminder).RefIndexExists(..Ref, .id) Set stored = ##class(OcuTalon.Data.Reminder).StateGetStored(id)
	Do ..Sent.%Push({"target": (target), "kind": (request.Kind), "key": (request.CatalogKey), "slots": (request.Slots), "session": (request.SessionRef), "responseRequired": (+responseRequired), "storedState": (stored)})
	Quit ..SendStatus
}

}
