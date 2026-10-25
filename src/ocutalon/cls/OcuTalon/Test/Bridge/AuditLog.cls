/// Reads entries back from the IRIS audit log for the tests (AD-17). THROWAWAY STACKS AND CI ONLY (Rule 21). It has no Test method, so
/// it is not a test class.
/// IRIS writes an audit row at once but updates its indexes (Event, EventType, EventSource, Username) up to a minute later, so a query
/// that names them waits for the index. These methods read %SYS.Audit in %SYS (the class has no rows in other namespaces), constrained
/// only by UTCTimeStamp >= the mark, which is the IDKEY and is current at once; every other condition is tested in ObjectScript. A test
/// finds its own entries by a marker (a fresh Ref in the entry's data or description), never by a count of all entries.
///   - Now returns the mark: the UTC time, to the millisecond, in the format of UTCTimeStamp. Take it just before the call under test.
///   - Entries returns the entries since the mark that match each condition that is not empty, as an array of
///     {at, username, data, description}: at is the UTCTimeStamp, username the writing process's $Username, data the event data as an
///     object when it is JSON (else the text) and description the text.
///   - Wait polls Entries until it finds count entries or seconds pass, and returns the last result.
Class OcuTalon.Test.Bridge.AuditLog
{

/// How long Wait polls by default, in seconds.
Parameter SECONDS = 10;

/// How long Wait pauses between two reads, in seconds.
Parameter PAUSE = 0.2;

/// The mark: the UTC time now, to the millisecond, as UTCTimeStamp holds it.
ClassMethod Now() As %String
{
	Quit $ZDateTime($ZTimeStamp, 3, 1, 3)
}

/// The entries of %SYS.Audit written at or after since (a mark of Now) that match source (EventSource), type (EventType), event (Event),
/// username (Username) and marker (the event data or the description holds it), each when it is not empty, oldest first.
ClassMethod Entries(since As %String, source As %String = "", type As %String = "", event As %String = "", marker As %String = "", username As %String = "") As %DynamicArray
{
	Set entries = []
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT UTCTimeStamp, Username, EventSource, EventType, Event, EventData, Description FROM %SYS.Audit WHERE UTCTimeStamp >= ? ORDER BY UTCTimeStamp, AuditIndex", since)
	If result.%SQLCODE < 0 Throw ##class(%Exception.General).%New("AuditLog", 5001, , "SQLCODE " _ result.%SQLCODE _ " " _ result.%Message)
	While result.%Next() {
		Set data = result.%GetData(6)
		Set description = result.%GetData(7)
		If (source '= "") && (result.%GetData(3) '= source) Continue
		If (type '= "") && (result.%GetData(4) '= type) Continue
		If (event '= "") && (result.%GetData(5) '= event) Continue
		If (username '= "") && (result.%GetData(2) '= username) Continue
		If (marker '= "") && (data '[ marker) && (description '[ marker) Continue
		Set entry = {}
		Do entry.%Set("at", result.%GetData(1), "string")
		Do entry.%Set("username", result.%GetData(2), "string")
		Try {
			Set parsed = {}.%FromJSON(data)
			Do entry.%Set("data", parsed)
		} Catch {
			Do entry.%Set("data", data, "string")
		}
		Do entry.%Set("description", description, "string")
		Do entries.%Push(entry)
	}
	Quit entries
}

/// Entries, polled every PAUSE seconds until count entries are found or seconds pass (default SECONDS). Returns the last result.
ClassMethod Wait(since As %String, source As %String = "", type As %String = "", event As %String = "", marker As %String = "", username As %String = "", count As %Integer = 1, seconds As %Numeric = {..#SECONDS}) As %DynamicArray
{
	Set deadline = $ZHorolog + seconds
	For {
		Set entries = ..Entries(since, source, type, event, marker, username)
		If (entries.%Size() >= count) || ($ZHorolog >= deadline) Quit
		Hang ..#PAUSE
	}
	Quit entries
}

}
