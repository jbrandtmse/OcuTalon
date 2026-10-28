/// Tests of OcuTalon.Test.Fix.Snapshot.Diff, the oracle of the "nothing changed" tests (Story 7.1): it is given hand-made snapshots, so it needs no production and no
/// Orders namespace. Each kind of difference must give a line, and an allowed change none.
///   - TestEachCategoryIsCompared: a changed, a missing and a new item of the productions, the defaults and the queues, a changed production state, and a namespace that is
///     missing after each give a line;
///   - TestNewHeaders: a new header gives a line, unless its session is one of the allowed sessions or the session of a new HeartbeatIn header; a changed or missing header gives a line;
///   - TestNothingChanged: two equal snapshots give no line.
Class OcuTalon.Test.Fix.SnapshotDiff Extends %UnitTest.TestCase
{

/// A snapshot of one namespace with the given members; an argument that is not given is an empty object.
ClassMethod Taken(headers As %DynamicObject = "", productions As %DynamicObject = "", state As %DynamicObject = "", defaults As %DynamicObject = "", queues As %DynamicObject = "") As %DynamicObject [ Private ]
{
	Quit {"ZZNS": {"headers": ($Select($IsObject(headers): headers, 1: {})), "productions": ($Select($IsObject(productions): productions, 1: {})), "state": ($Select($IsObject(state): state, 1: {})), "defaults": ($Select($IsObject(defaults): defaults, 1: {})), "queues": ($Select($IsObject(queues): queues, 1: {}))}}
}

/// The text of a header row as Snapshot.Take keeps it, with the session and the source in their columns.
ClassMethod Row(session As %String, source As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 * FROM Ens.MessageHeader")
	Set metadata = rs.%GetMetadata()
	Set columns = rs.%ResultColumnCount
	Set row = ""
	For i = 1:1:columns {
		Set name = $ZConvert(metadata.columns.GetAt(i).colName, "U")
		Set row = row _ $Select(name = "SESSIONID": session, name = "SOURCECONFIGNAME": source, 1: "x") _ $Char(31)
	}
	Quit row _ $Char(30)
}

Method TestNothingChanged()
{
	Set one = ..Taken({"1": "a"}, {"P": "d"}, {"production": "P:1"}, {"1": "r"}, {"Q": 0})
	Set two = ..Taken({"1": "a"}, {"P": "d"}, {"production": "P:1"}, {"1": "r"}, {"Q": 0})
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(one, two).%Size(), 0, "two equal snapshots give no line")
}

Method TestEachCategoryIsCompared()
{
	Set base = ..Taken("", {"P": "d"}, {"production": "P:1"}, {"1": "r"}, {"Q": 0})
	Set cases = [
		{"label": "a production definition changed", "after": (..Taken("", {"P": "e"}, {"production": "P:1"}, {"1": "r"}, {"Q": 0}))},
		{"label": "a production is missing", "after": (..Taken("", {}, {"production": "P:1"}, {"1": "r"}, {"Q": 0}))},
		{"label": "a production is new", "after": (..Taken("", {"P": "d", "R": "d"}, {"production": "P:1"}, {"1": "r"}, {"Q": 0}))},
		{"label": "the production state changed", "after": (..Taken("", {"P": "d"}, {"production": "P:2"}, {"1": "r"}, {"Q": 0}))},
		{"label": "a default setting changed", "after": (..Taken("", {"P": "d"}, {"production": "P:1"}, {"1": "s"}, {"Q": 0}))},
		{"label": "a default setting is new", "after": (..Taken("", {"P": "d"}, {"production": "P:1"}, {"1": "r", "2": "r"}, {"Q": 0}))},
		{"label": "a queue count changed", "after": (..Taken("", {"P": "d"}, {"production": "P:1"}, {"1": "r"}, {"Q": 1}))},
		{"label": "a queue is new", "after": (..Taken("", {"P": "d"}, {"production": "P:1"}, {"1": "r"}, {"Q": 0, "R": 1}))},
		{"label": "the namespace is missing", "after": {}}
	]
	Set iterator = cases.%GetIterator()
	While iterator.%GetNext(, .case) {
		Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(base, case.after).%Size(), 1, case.label_": one line")
	}
}

Method TestNewHeaders()
{
	Set was = ..Taken({"1": (..Row(1, "A"))})
	Set row = ..Row(7, "A")
	Set now = ..Taken({"1": (..Row(1, "A")), "2": (row)})
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(was, now).%Size(), 1, "a new header in a session that nobody allowed gives a line")
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(was, now, "7").%Size(), 0, "and none when its session is allowed")
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(was, now, "3,7").%Size(), 0, "also in a list of sessions")
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(was, now, "8").%Size(), 1, "but not for another session")
	Set tick = ..Taken({"1": (..Row(1, "A")), "2": (..Row(7, "HeartbeatIn")), "3": (..Row(7, "B"))})
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(was, tick).%Size(), 0, "the headers of a session that a new HeartbeatIn header started are allowed")
	Set changed = ..Taken({"1": (..Row(2, "A"))})
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(was, changed).%Size(), 1, "a changed header gives a line")
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(was, ..Taken()).%Size(), 1, "and a missing header gives a line")
}

}
