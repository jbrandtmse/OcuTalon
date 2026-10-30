/// Tests of OcuTalon.Test.Fix.Snapshot.Diff, the oracle of the "nothing changed" tests (Story 7.1): it is given hand-made snapshots, so it needs no production and no
/// Orders namespace. Each kind of difference must give a line, and an allowed change none.
///   - TestEachCategoryIsCompared: a changed, a missing and a new item of the productions, the defaults and the queues, a changed production state, and a namespace that is
///     missing after each give a line;
///   - TestNewHeaders: a new header gives a line, unless its session is one of the allowed sessions of its namespace or the session of a new HeartbeatIn header; a session
///     allowed in another namespace does not allow it; a changed or missing header gives a line;
///   - TestRunningTimersAreNotChanges: in OCUTALON, the request of a timer (a header to Ens.Alarm) that was Created, Queued or Delivered in "before", its completing,
///     and one wake-up header that Ens.Alarm sent in its session give no line. A timer armed after "before" (its request and its wake-up, in a new session or in the
///     session of the earlier timer), a second wake-up in the session (two running timers in one session allow two wake-ups, not three), a wake-up in a session with
///     no running timer, a request in any other status in "before" (Discarded, Suspended, Deferred, Aborted, Error, Completed, or no status), a header to another
///     target, a new header from another source and a changed header in the running timer's session, its request missing after, and the same headers in another
///     namespace give a line each, and the four lines that isolate one condition each are checked by their text;
///   - TestNothingChanged: two equal snapshots give no line.
Class OcuTalon.Test.Fix.SnapshotDiff Extends %UnitTest.TestCase
{

/// A snapshot of one namespace with the given members; an argument that is not given is an empty object.
ClassMethod Taken(headers As %DynamicObject = "", productions As %DynamicObject = "", state As %DynamicObject = "", defaults As %DynamicObject = "", queues As %DynamicObject = "") As %DynamicObject [ Private ]
{
	Quit {"ZZNS": {"headers": ($Select($IsObject(headers): headers, 1: {})), "productions": ($Select($IsObject(productions): productions, 1: {})), "state": ($Select($IsObject(state): state, 1: {})), "defaults": ($Select($IsObject(defaults): defaults, 1: {})), "queues": ($Select($IsObject(queues): queues, 1: {}))}}
}

/// A snapshot of one namespace with the given headers only.
ClassMethod TakenIn(namespace As %String, headers As %DynamicObject) As %DynamicObject [ Private ]
{
	Set taken = {}
	Do taken.%Set(namespace, {"headers": (headers), "productions": {}, "state": {}, "defaults": {}, "queues": {}})
	Quit taken
}

/// The text of a header row as Snapshot.Take keeps it, with the session, the source, the target and the status in their columns.
ClassMethod Row(session As %String, source As %String, target As %String = "x", status As %String = "x") As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 * FROM Ens.MessageHeader")
	Set metadata = rs.%GetMetadata()
	Set columns = rs.%ResultColumnCount
	Set row = ""
	For i = 1:1:columns {
		Set name = $ZConvert(metadata.columns.GetAt(i).colName, "U")
		Set row = row _ $Select(name = "SESSIONID": session, name = "SOURCECONFIGNAME": source, name = "TARGETCONFIGNAME": target, name = "STATUS": status, 1: "x") _ $Char(31)
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
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(was, now, "7", "ZZNS").%Size(), 0, "and none when its session is allowed in its namespace")
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(was, now, "3,7", "ZZNS").%Size(), 0, "also in a list of sessions")
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(was, now, "8", "ZZNS").%Size(), 1, "but not for another session")
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(was, now, "7", "ZZOTHER").%Size(), 1, "nor for the same session number allowed in another namespace")
	Set tick = ..Taken({"1": (..Row(1, "A")), "2": (..Row(7, "HeartbeatIn")), "3": (..Row(7, "B"))})
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(was, tick).%Size(), 0, "the headers of a session that a new HeartbeatIn header started are allowed")
	Set changed = ..Taken({"1": (..Row(2, "A"))})
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(was, changed).%Size(), 1, "a changed header gives a line")
	Do $$$AssertEquals(##class(OcuTalon.Test.Fix.Snapshot).Diff(was, ..Taken()).%Size(), 1, "and a missing header gives a line")
}

/// The lines Diff gives for headers in the namespace, from "before" to "after" (header id: row).
Method Lines(namespace As %String, was As %DynamicObject, now As %DynamicObject) As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Test.Fix.Snapshot).Diff(..TakenIn(namespace, was), ..TakenIn(namespace, now), "", namespace)
}

/// The one line of lines, or all of them as JSON when there is not exactly one.
Method One(lines As %DynamicArray) As %String [ Private ]
{
	Quit $Select(lines.%Size() = 1: lines.%Get(0), 1: lines.%ToJSON())
}

Method TestRunningTimersAreNotChanges()
{
	Set ns = ##class(OcuTalon.Test.Fix.Snapshot).#ALARMIN
	Set alarm = ##class(OcuTalon.Test.Fix.Snapshot).#ALARM
	Set pending = {"1": (..Row(5, "Decide", alarm, 3))}
	Set completed = ..Row(5, "Decide", alarm, 9)
	Set wake = ..Row(5, alarm, "Decide", 1)

	Set lines = ..Lines(ns, pending, {"1": (completed), "2": (wake)})
	Do $$$AssertEquals(lines.%Size(), 0, "a timer that was pending in before completes and wakes its process once: no line "_lines.%ToJSON())

	Set lines = ..Lines(ns, pending, {"1": (completed), "2": (wake), "3": (..Row(9, "Decide", alarm, 3))})
	Do $$$AssertEquals(lines.%Size(), 1, "a timer armed after before, in a new session, gives a line "_lines.%ToJSON())
	Set lines = ..Lines(ns, pending, {"1": (completed), "2": (wake), "3": (..Row(9, "Decide", alarm, 3)), "4": (..Row(9, alarm, "Decide", 1))})
	Do $$$AssertEquals(lines.%Size(), 2, "and so does its wake-up: a line each "_lines.%ToJSON())
	Set lines = ..Lines(ns, pending, {"1": (completed), "2": (wake), "3": (..Row(5, "Decide", alarm, 3))})
	Do $$$AssertEquals(lines.%Size(), 1, "a timer armed after before in the session of the earlier timer gives a line "_lines.%ToJSON())
	Set lines = ..Lines(ns, pending, {"1": (completed), "2": (wake), "3": (..Row(5, alarm, "Decide", 1))})
	Do $$$AssertEquals(lines.%Size(), 1, "a second wake-up in that session gives a line: one per pending request "_lines.%ToJSON())

	Set lines = ..Lines(ns, {"1": (completed)}, {"1": (..Row(5, "Decide", alarm, 8)), "2": (wake)})
	Do $$$AssertEquals(lines.%Size(), 2, "a request that was final in before is not a running timer: its change and a wake-up give a line each "_lines.%ToJSON())
	Set lines = ..Lines(ns, {"1": (..Row(5, "Decide", "Other", 3))}, {"1": (..Row(5, "Decide", "Other", 9)), "2": (wake)})
	Do $$$AssertEquals(lines.%Size(), 2, "a pending header to another target is not a timer "_lines.%ToJSON())
	Set lines = ..Lines(ns, pending, {"1": (completed), "2": (wake), "3": (..Row(5, "Decide", "Other", 1))})
	Do $$$AssertEquals(lines.%Size(), 1, "another new header in the timer's session gives a line "_lines.%ToJSON())
	Set lines = ..Lines(ns, {"1": (..Row(5, "Decide", alarm, 3)), "2": (..Row(6, "A", "B", 2))}, {"1": (completed), "2": (..Row(6, "A", "B", 9)), "3": (wake)})
	Do $$$AssertEquals(lines.%Size(), 1, "a change of another header gives a line while the timer's does not "_lines.%ToJSON())

	Set lines = ..Lines(ns, pending, {"1": (pending.%Get("1")), "2": (..Row(5, "Decide", "Other", 1))})
	Do $$$AssertEquals(..One(lines), ns_" header 2 is new: session 5, from Decide to Other", "a new header from another source in a running timer's session, before its wake-up, gives its line")
	Set lines = ..Lines(ns, pending, {"1": (completed), "2": (..Row(7, alarm, "Decide", 1))})
	Do $$$AssertEquals(..One(lines), ns_" header 2 is new: session 7, from "_alarm_" to Decide", "a wake-up in a session with no running timer gives its line")
	Set lines = ..Lines(ns, {"1": (pending.%Get("1")), "2": (..Row(5, "A", "Decide", 2))}, {"1": (completed), "2": (..Row(5, "A", "Decide", 9)), "3": (wake)})
	Do $$$AssertEquals(..One(lines), ns_" headers 2 changed", "a change of another header in the running timer's session gives its line")
	Set lines = ..Lines(ns, pending, {})
	Do $$$AssertEquals(..One(lines), ns_" headers 1 is missing after", "a running timer's request that is missing after gives its line")

	Set two = {"1": (..Row(5, "Decide", alarm, 3)), "2": (..Row(5, "Decide", alarm, 3))}
	Set twoDone = {"1": (completed), "2": (completed), "3": (wake), "4": (wake)}
	Set lines = ..Lines(ns, two, twoDone)
	Do $$$AssertEquals(lines.%Size(), 0, "two timers pending in one session allow two wake-ups "_lines.%ToJSON())
	Do twoDone.%Set("5", wake)
	Set lines = ..Lines(ns, two, twoDone)
	Do $$$AssertEquals(lines.%Size(), 1, "and not a third "_lines.%ToJSON())

	For status = 1, 2 {
		Set lines = ..Lines(ns, {"1": (..Row(5, "Decide", alarm, status))}, {"1": (completed), "2": (wake)})
		Do $$$AssertEquals(lines.%Size(), 0, "a request in the status "_status_" (Created or Queued) in before is a running timer "_lines.%ToJSON())
	}
	For status = 4, 5, 6, 7, 8, "x" {
		Set lines = ..Lines(ns, {"1": (..Row(5, "Decide", alarm, status))}, {"1": (completed), "2": (wake)})
		Do $$$AssertEquals(lines.%Size(), 2, "a request in the status "_status_" (not Created, Queued or Delivered) in before is not a running timer "_lines.%ToJSON())
	}

	Set lines = ..Lines("ZZNS", pending, {"1": (completed), "2": (wake)})
	Do $$$AssertEquals(lines.%Size(), 2, "the same headers in another namespace give a line each "_lines.%ToJSON())
}

}
