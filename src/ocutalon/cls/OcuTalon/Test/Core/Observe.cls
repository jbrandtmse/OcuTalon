Include Ensemble

/// What the tests of the routing observe, read the way a test may: the Delivery table, a session's event stream, the headers of a
/// SuperSession and the event log (Story 2.7). It has no Test methods and the product never refers to it. The tests of Intake,
/// WebChatOut, Delivery and the two production classes call these methods instead of each reading the tables itself.
///   - DeliveryRows, DeliveryCount and WaitDeliveries: the Delivery rows of an owner, whatever their kind, in the order they were
///     recorded;
///   - Events: the events of one type on a session's stream, with a wait for a number of them;
///   - WaitProcessed: the point after which an item has handled the requests that another sent it, and so after which an absence
///     can be asserted;
///   - LastLog, Warnings and RemoveWarnings: the warnings that a method logged after a row of the event log.
Class OcuTalon.Test.Core.Observe Extends %RegisteredObject
{

/// The Delivery rows of the owner, whatever their kind, in the order they were recorded.
ClassMethod DeliveryRows(owner As %String) As %ListOfObjects
{
	Set list = ##class(%ListOfObjects).%New()
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? ORDER BY ID", owner)
	While result.%Next() {
		Do list.Insert(##class(OcuTalon.Data.Delivery).%OpenId(result.%Get("ID")))
	}
	Quit list
}

/// The number of Delivery rows of the owner, whatever their kind.
ClassMethod DeliveryCount(owner As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE OwnerRef = ?", owner)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// Waits until the owner has count Delivery rows or the seconds have passed.
ClassMethod WaitDeliveries(owner As %String, count As %Integer, seconds As %Integer)
{
	Set end = $ZHorolog + seconds
	For {
		If (..DeliveryCount(owner) >= count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
}

/// The events of the type on the session's stream, in order. With seconds above 0 it waits until there are count of them or the
/// seconds have passed; with the default of 0 it reads the stream once.
ClassMethod Events(session As %String, type As %String, count As %Integer = 0, seconds As %Integer = 0) As %DynamicArray
{
	Set end = $ZHorolog + seconds
	For {
		Set found = []
		Set events = ##class(OcuTalon.Live.Event).Since(session, 0, 200, "session")
		Set iterator = events.%GetIterator()
		While iterator.%GetNext(, .event) {
			If event.type = type Do found.%Push(event)
		}
		If (found.%Size() >= count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// Waits until count requests from the source item to the target item in the SuperSession are completed, which means that the
/// target has handled them and sent on whatever it was going to send, or the seconds have passed. Answers 1 when they are.
ClassMethod WaitProcessed(trace As %String, source As %String, target As %String, count As %Integer, seconds As %Integer) As %Boolean
{
	Set end = $ZHorolog + seconds
	For {
		Set completed = 0
		Set requests = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, source, target)
		For i = 0:1:requests.%Size() - 1 {
			If requests.%Get(i).status = $$$eMessageStatusCompleted Set completed = completed + 1
		}
		If (completed >= count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit (completed >= count)
}

/// The number of the newest row of the event log.
ClassMethod LastLog() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of warnings that the method logged after the row mark, with a text that starts as given; text is the newest one's.
ClassMethod Warnings(mark As %Integer, Output text As %String, method As %String, start As %String) As %Integer
{
	Set text = ""
	Set count = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = ? AND Text %STARTSWITH ? ORDER BY ID", mark, method, start)
	While result.%Next() {
		Set count = count + 1
		Set text = result.%Get("Text")
	}
	Quit count
}

/// Removes those warnings.
ClassMethod RemoveWarnings(mark As %Integer, method As %String, start As %String)
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = ? AND Text %STARTSWITH ?", mark, method, start)
}

}
