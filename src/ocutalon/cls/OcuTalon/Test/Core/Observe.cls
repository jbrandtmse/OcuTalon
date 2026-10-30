Include Ensemble

/// What the tests of the routing observe, read the way a test may: the Delivery table, a session's event stream, the headers of a
/// SuperSession and the event log (Story 2.7). It has no Test methods and the product never refers to it. The tests of Intake,
/// WebChatOut, Delivery and the two production classes call these methods instead of each reading the tables itself.
///   - DeliveryRows, DeliveryCount and WaitDeliveries: the Delivery rows of an owner, whatever their kind, in the order they were
///     recorded;
///   - Events: the events of one type on a session's stream, with a wait for a number of them;
///   - WaitProcessed: the point after which an item has handled the requests that another sent it, and so after which an absence
///     can be asserted;
///   - LastLog, Warnings and RemoveWarnings: the warnings that a method logged after a row of the event log;
///   - TimeReads: the form in which a rendered text shows a UTC time, so that a test holds at any time of day.
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

/// How a rendered text shows the UTC time utc between its head and its tail, so that a test holds at any time of day: the catalog
/// shows a time as the instance-zone clock "HH:MM" when its local date is the date of the reading, and with the weekday or the date
/// ("Friday at HH:MM", "Oct 9 at HH:MM", "Dec 30, 2025 at HH:MM") when it is another day, and the "at" before a dated time becomes "on".
/// With joined 1 the head ends before the word "at" (it ends with a space, and the time follows as "at HH:MM" or "on <day> at HH:MM");
/// with joined 0 the time follows the head itself ("HH:MM" or "<day> at HH:MM"). The text starts with the head and ends with the
/// tail. Returns "sameday" for the clock alone, "otherday" for a clock with a day, and "" when the text is not head, a time and
/// tail, or when the clock is not the instance-zone clock of utc. It reads no clock itself.
ClassMethod TimeReads(text As %String, head As %String, tail As %String, utc As %String, joined As %Boolean = 1) As %String
{
	Set clock = $Extract(##class(OcuTalon.Data.Time).ToLocal(utc), 12, 16)
	Set size = $Length(text)
	If (clock = "") || (size < ($Length(head) + $Length(tail))) Quit ""
	If ($Extract(text, 1, $Length(head)) '= head) || ($Extract(text, size - $Length(tail) + 1, size) '= tail) Quit ""
	Set middle = $Extract(text, $Length(head) + 1, size - $Length(tail))
	Set day = "([A-Z][a-z]+|[A-Z][a-z]{2} [0-9]{1,2}(, [0-9]{4})?)"
	If $Match(middle, "^"_$Select(joined: "at ", 1: "")_clock_"$") Quit "sameday"
	If $Match(middle, "^"_$Select(joined: "on ", 1: "")_day_" at "_clock_"$") Quit "otherday"
	Quit ""
}

}
