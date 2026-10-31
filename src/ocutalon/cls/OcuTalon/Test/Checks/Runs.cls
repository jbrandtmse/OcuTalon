/// Tests of the runs of Checks, OcuTalon.Checks.Process (Story 5.6; AD-4, AD-12, AD-15, AD-18, AD-26, AD-28, AD-33). The tests need no production and no
/// namespace but their own: they call OnRequest of a shadow instance of Test.Checks.Probe in the test process, with real Tick and CheckChanged objects, over
/// fixture sessions, check rows and incidents of Test.Data.Fixture (on fixture names, in the fixture namespace ZZNS), and read the rows, the sessions'
/// streams, the log and what the probe recorded (its reads and its closeQuiet commands). They run warm. The probe keeps only the rows of the test, so
/// that the rows of a warm stack are never touched. The Tick's time is a fixed time in 2030 (TICK), so that the next due time is easy to read.
/// Nothing here depends on the moment: the fixture rows are of the probe's Kind (zzprobe), which no real Checks runs (it runs the Kind production), so that a
/// Tick from HeartbeatIn at any moment runs none of them; the quiet incidents are quiet only at the probe's QuietAt (TICK), which a Tick that reads the
/// clock never reaches; and the counts and the removals of log lines go by the text that starts with the line's text and the Ref of the test's own row or
/// incident, so that the lines of other Checks jobs are neither counted nor removed.
///   - TestDue (matrix "Due"): rows due 7 minutes before the Tick, with no time, 3 seconds after it and 2 minutes after it: the first three run once each and the
///     fourth does not; each next due time becomes the Tick's time plus 60 seconds; a second Tick with the same time runs none; a due row of another kind never runs;
///   - TestTickWithoutTime (Always, "Times"): a Tick whose TickAt is not a UTC stamp runs the due row at now, and the next due time is a UTC stamp after now;
///   - TestPassed ("Passed"): a running production, a failure of another session only and the unclosed incidents of another session, a resolved one and a
///     closed one: passed, an empty finding, the run time, the probe's session as LastRunHeaderId, and one check event, FromRow, on the session's stream;
///   - TestFailed ("Failed"): every state, 1, 50 and a cut read of new failures, every unclosed incident state (noticed or not), and combinations: failed,
///     with the exact finding;
///   - TestScope ("Scope"): the failures and incidents of A, of B, of instance and untagged failures, on a local install and on the online demo;
///   - TestNotChecked ("Not checked"): a read that throws (one redacted warning, no error text in the finding), unreadable, not_current, the state timeout and
///     unknown, a cut read with none of the session's failures and an incident read that fails: not_checked with the reason, never passed;
///   - TestWindow ("Window"): the first read starts at CreatedAt, the next at the first run's own LastRunAt (kept as text before the second Tick, with a pause of
///     1.1 seconds between the two Ticks, so that the two runs fall in different seconds; DW-414) less 2 seconds, and the limit is 500;
///   - Findings (Story 30.4; AC 1-3; FR-23, AD-14, AD-18, AD-32; the matrix rows 1-11): TestFindingsRule (the pure rule), TestStoppedIsReportedOnce (rows 1-4: one Item for a stop, with
///     its fields, trace and Reported; none while it stays stopped; a new one after a restart; the run time when IRIS gave none), TestSuspendedAndTroubled (row 9),
///     TestDisabledItemsAreReportedOnce (rows 5 and 6), TestFirstRunIsABaseline (row 7), TestNotCheckedReportsNothing (row 8, and a cut read or an unreadable incident table that still compares),
///     TestDeletedMeanwhileSendsNothing (row 10), TestFailedSendIsNeverRetried and TestThrownSendIsNeverRetried (row 11) and TestFindingsRender (each Item's key and slots render to the UX text);
///   - TestStoppedMeanwhile ("Stopped meanwhile"): the row is deleted by the read: nothing is recorded, published or logged and the row stays deleted;
///   - TestQuietSweep ("Quiet close"): one closeQuiet for each unclosed incident whose last failure is more than 15 minutes old, origin timer, no session, the
///     owner's TraceRef as SuperSession (empty for instance), in the process's session, with its own SuperSession put back; none for a recent or a closed
///     one; a failed send, and a send that IncidentManager did not answer in time, each log one warning that names the incident, and the others still go out;
///     the sweep is handed the clock's now (the probe's SweptAt), and the quiet rule runs against TICK;
///   - TestTickSendsTheSweptResults (Story 7.5; AC 2; "Checks sends the results"): the FixResults that Fix.Run Sweep gives (canned by the probe) are each sent to IncidentManager after the
///     quiet sweep, in the trace session of the result's incident (a result whose incident has none keeps the process's session) with the request's TraceRef as the SuperSession, and the
///     process's own session and SuperSession are put back after each send; a send that fails logs one warning that names the request and the next result is still sent; a Sweep that throws logs
///     one warning, and the due checks still run;
///   - TestRunThrows (Always, "A Tick"): a run that throws outside the read logs one warning (LOGRUN) that names the check, records nothing, and the next due row still runs;
///   - TestChanged ("Start and stop"): a CheckChanged for a start publishes FromRow of the row (nothing when the row is gone), one for a stop a payload with
///     stopped true and the message's name, on the message's session stream; a failed publish logs one warning;
///   - TestPublishes: exactly one check event per run, equal to FromRow of the row after the run;
///   - TestRanLine: one Type 4 line per run, naming the check's Ref, its name, the result and the finding;
///   - TestUnknownRequest ("Unknown request"): a request of another class is an error 5001 that names the class.
/// The fixture rows, streams and the log lines that the tests made are removed after each test.
Class OcuTalon.Test.Checks.Runs Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Checks.Probe";

/// The time of the Tick.
Parameter TICK = "2030-06-01T12:00:00Z";

/// The time of the Tick after it.
Parameter NEXT = "2030-06-01T12:01:00Z";

/// The id of the session that the probe runs in.
Parameter SESSIONID = 424242;

/// The run's number.
Property Number As %Integer;

/// A number for the productions of the cases.
Property Cases As %Integer [ InitialExpression = 0 ];

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the checks of the test being run, comma-separated (the probe's Only).
Property Checks As %String(MAXLEN = "");

/// The Refs of the incidents of the test being run, comma-separated (the probe's OnlyIncidents).
Property Incidents As %String(MAXLEN = "");

/// The Refs of the approval requests of the test being run, comma-separated (the Refs that the warnings of the fixes name).
Property Requests As %String(MAXLEN = "");

/// The Ref of the other session of the cases of the test being run, "" before the first needs one.
Property Other As %String;

/// The number of the newest row of the event log when the test began.
Property LogMark As %Integer;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("ChecksRuns", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Checks = ""
	Set ..Incidents = ""
	Set ..Requests = ""
	Set ..Other = ""
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $ClassMethod(..#PROBE, "Reset")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Do $ClassMethod(..#PROBE, "Reset")
	Do ..RemoveLogs()
	Quit $$$OK
}

Method TestDue()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("due")
	Set early = ..Watch(a, "Zz.Due1", {"NextDueAt": "2030-06-01T11:53:00Z"})
	Set unset = ..Watch(a, "Zz.Due2", {"NextDueAt": ""})
	Set slack = ..Watch(a, "Zz.Due3", {"NextDueAt": "2030-06-01T12:00:03Z"})
	Set later = ..Watch(a, "Zz.Due4", {"NextDueAt": "2030-06-01T12:02:00Z"})
	Set other = ..Watch(a, "Zz.Due5", {"Kind": "other", "NextDueAt": ""})
	For production = "Zz.Due1", "Zz.Due2", "Zz.Due3", "Zz.Due4" {
		Do ..Feed(production, "read", "running")
	}
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(..Reads(), "Zz.Due1,Zz.Due2,Zz.Due3", "the rows due 7 minutes ago, with no time, and 3 seconds ahead each ran once, and the one due in 2 minutes did not")
	For ref = early, unset, slack {
		Set row = ..Row(ref)
		Do $$$AssertEquals(row.NextDueAt, ..#NEXT, ..Name(row)_": the next due time is the Tick's time plus 60 seconds")
		Do $$$AssertEquals(row.Result, "passed", ..Name(row)_": passed")
	}
	Set row = ..Row(later)
	Do $$$AssertEquals(row.NextDueAt_"|"_row.LastRunAt_"|"_row.Result, "2030-06-01T12:02:00Z||", "the row due later is untouched")
	Set row = ..Row(other)
	Do $$$AssertEquals(row.LastRunAt_"|"_row.Result, "|", "a due row of another kind is never run")
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(..Reads(), "Zz.Due1,Zz.Due2,Zz.Due3", "a second Tick with the same time runs none of them")
	Do ..Tick(host, "2030-06-01T12:02:00Z")
	Do $$$AssertEquals(..Reads(), "Zz.Due1,Zz.Due2,Zz.Due3,Zz.Due1,Zz.Due2,Zz.Due3,Zz.Due4", "two minutes later it runs the three again, once each however many minutes were missed, and the fourth now")
}

Method TestTickWithoutTime()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("tickat")
	Set ref = ..Watch(a, "Zz.TickAt1", {"NextDueAt": ""})
	Do ..Feed("Zz.TickAt1", "read", "running")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Tick(host, "not a time")
	Do $$$AssertEquals(..Reads(), "Zz.TickAt1", "a Tick with no usable time still runs the due row")
	Set row = ..Row(ref)
	Do $$$AssertTrue(row.NextDueAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "the next due time is a UTC stamp: "_row.NextDueAt)
	Do $$$AssertTrue(row.NextDueAt ] before, "and it is after now: "_row.NextDueAt)
}

Method TestPassed()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("passed")
	Set b = ..Owner("passedB")
	Set production = "Zz.Passed"
	Set ref = ..Watch(a, production)
	Do ..Incident(b, "open", production)
	Do ..Incident(a, "resolved", production)
	Do ..Incident(a, "closed", production, {"ClosedAt": "2030-01-01T10:00:00Z"})
	Do ..Incident(a, "open", "Zz.PassedElsewhere")
	Do ..Feed(production, "read", "running", ..Failures(..TraceOf(b), 2))
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Tick(host, ..#TICK)
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "passed|", "passed, with an empty finding")
	Do $$$AssertTrue('(before ] row.LastRunAt) && '(row.LastRunAt ] after), "LastRunAt is the run time: "_row.LastRunAt)
	Do $$$AssertEquals(row.LastRunHeaderId, ..#SESSIONID, "LastRunHeaderId is the process's session")
	Do $$$AssertEquals(row.NextDueAt, ..#NEXT, "NextDueAt is the Tick's time plus 60 seconds")
	Set events = ..Events(a)
	Do $$$AssertEquals(events.%Size(), 1, "one check event is on the session's stream")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.%ToJSON(), ..ViewOf(ref), "and it is FromRow of the row")
	Do $$$AssertEquals(..Events(b).%Size(), 0, "the other session's stream has none")
}

Method TestFailed()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("failed")
	Do ..Case(host, a, "stopped", {"state": "stopped"}, "failed", "Production stopped")
	Do ..Case(host, a, "suspended", {"state": "suspended"}, "failed", "Production suspended")
	Do ..Case(host, a, "troubled", {"state": "troubled"}, "failed", "Production troubled")
	Do ..Case(host, a, "network stopped", {"state": "network_stopped"}, "failed", "Production not running")
	Do ..Case(host, a, "one failure", {"failures": 1}, "failed", "1 new failure")
	Do ..Case(host, a, "fifty failures", {"failures": 50}, "failed", "50 new failures")
	Do ..Case(host, a, "a cut read", {"failures": 500}, "failed", "At least 500 new failures")
	Do ..Case(host, a, "open", {"incidents": ["open"]}, "failed", "An open incident")
	Do ..Case(host, a, "unnoticed open", {"incidents": ["open!"]}, "failed", "An open incident")
	Do ..Case(host, a, "awaiting", {"incidents": ["awaiting_approval"]}, "failed", "A fix waiting for your approval")
	Do ..Case(host, a, "fixing", {"incidents": ["fixing"]}, "failed", "A fix running")
	Do ..Case(host, a, "resolved and closed", {"incidents": ["resolved", "closed"]}, "passed", "")
	Do ..Case(host, a, "stopped and one failure", {"state": "stopped", "failures": 1}, "failed", "Production stopped, 1 new failure")
	Do ..Case(host, a, "failures and awaiting", {"failures": 50, "incidents": ["awaiting_approval"]}, "failed", "50 new failures, a fix waiting for your approval")
	Do ..Case(host, a, "all three", {"state": "suspended", "failures": 3, "incidents": ["fixing"]}, "failed", "Production suspended, 3 new failures, a fix running")
	Do ..Case(host, a, "the most urgent incident wins", {"incidents": ["open", "fixing", "awaiting_approval"]}, "failed", "A fix waiting for your approval")
	Do ..Case(host, a, "fixing beats open", {"incidents": ["open", "fixing"]}, "failed", "A fix running")
	Do ..Case(host, a, "a cut read and an incident", {"failures": 500, "incidents": ["open"]}, "failed", "At least 500 new failures, an open incident")
}

Method TestScope()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("scopeA")
	Set b = ..Owner("scopeB")
	Set rows = ..Failures(..TraceOf(a), 2)
	Do ..Append(rows, ..Failures(..TraceOf(b), 3))
	Do ..Append(rows, ..Failures("", 4))
	Set production = "Zz.Scope1"
	Set ref = ..Watch(a, production)
	Do ..Feed(production, "read", "running", rows)
	Do ..Tick(host, ..#TICK)
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "failed|6 new failures", "local install: A's 2 and the 4 untagged failures count, and B's 3 do not")
	Set production = "Zz.Scope2"
	Do ..Incident(b, "open", production)
	Set ref = ..Watch(a, production)
	Do ..Feed(production, "read", "running")
	Do ..Tick(host, ..#TICK)
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "passed|", "B's incident does not count")
	Set production = "Zz.Scope3"
	Do ..Incident("instance", "open", production)
	Do ..Incident(a, "fixing", production)
	Set ref = ..Watch(a, production)
	Do ..Feed(production, "read", "running")
	Do ..Tick(host, ..#TICK)
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "failed|A fix running", "A's incident counts, and so does the instance's")
	Set production = "Zz.Scope4"
	Do ..Incident("instance", "open", production)
	Set ref = ..Watch(a, production)
	Do ..Feed(production, "read", "running")
	Do ..Tick(host, ..#TICK)
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "failed|An open incident", "local install: an instance incident alone counts")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1"), "onlineDemo is set")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Reader).OnlineDemo(), 1, "and the reader sees the online demo")
	Do ..Tick(host, ..#NEXT)
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "passed|", "online demo: an instance incident does not count")
	Set ref = ..Watch(a, "Zz.Scope5")
	Do ..Feed("Zz.Scope5", "read", "running", rows)
	Do ..Tick(host, ..#NEXT)
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "failed|2 new failures", "online demo: only A's 2 failures count, not the untagged ones")
}

Method TestNotChecked()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("notchecked")
	Set reads = $Parameter(..#PROBE, "LOGREAD")
	Do ..Case(host, a, "unreadable", {"outcome": "unreadable"}, "not_checked", $Parameter(..#PROBE, "REASONUNREADABLE"))
	Do ..Case(host, a, "not current", {"outcome": "not_current"}, "not_checked", $Parameter(..#PROBE, "REASONNOTCURRENT"))
	Do ..Case(host, a, "timeout", {"state": "timeout", "failures": 2}, "not_checked", $Parameter(..#PROBE, "REASONTIMEOUT"))
	Do ..Case(host, a, "unknown", {"state": "unknown", "incidents": ["open"]}, "not_checked", $Parameter(..#PROBE, "REASONREAD"))
	Do ..Case(host, a, "cut with none of the session's", {"others": 500}, "not_checked", $Parameter(..#PROBE, "REASONTOOMANY"))
	Do ..Case(host, a, "cut with some", {"failures": 1, "others": 499}, "failed", "At least 1 new failures")
	Do ..Case(host, a, "an incident read that fails", {"failUnclosed": 1}, "not_checked", $Parameter(..#PROBE, "REASONREAD"))
	Set host.FailUnclosed = 0
	Do $$$AssertEquals(..Warnings("Run", reads, , ..Checks), 0, "a failed incident read is no failed production read, so it logs no read warning (nor does any case above)")
	Set production = "Zz.Thrown"
	Set ref = ..Watch(a, production)
	Do ..Feed(production, "", "", "", "ERROR #5001: Unable to reach https://zzuser:zzsecretword@orders.example/api with Authorization: Bearer zzTokenValue0123456789")
	Do ..Tick(host, ..#TICK)
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "not_checked|"_$Parameter(..#PROBE, "REASONREAD"), "a read that throws is not_checked, never passed")
	Do $$$AssertEquals(row.NextDueAt, ..#NEXT, "and the check is due again a minute later")
	Do $$$AssertEquals(..Warnings("Run", reads, .text, ..Checks), 1, "one warning is logged")
	Do $$$AssertTrue(text [ ref, "which names the check: "_text)
	Do $$$AssertTrue((text [ "[redacted]") && '(text [ "zzsecretword") && '(text [ "zzTokenValue0123456789"), "and the error is redacted: "_text)
	Do $$$AssertTrue('(row.Finding [ "zzuser") && '(row.Finding [ "5001"), "no error text is in the finding")
}

Method TestWindow()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("window")
	Set production = "Zz.Window"
	Set ref = ..Watch(a, production, {"CreatedAt": "2020-05-01T10:00:00Z"})
	Do ..Feed(production, "read", "running")
	Do ..Tick(host, ..#TICK)
	Set firstRunAt = ..Row(ref).LastRunAt
	Hang 1.1
	Do ..Tick(host, ..#NEXT)
	Set calls = $ClassMethod(..#PROBE, "Calls")
	Do $$$AssertEquals(calls.%Size(), 2, "two runs read")
	If calls.%Size() '= 2 Quit
	Do $$$AssertEquals(calls.%Get(0).from, "2020-05-01 10:00:00.000", "the first run reads from CreatedAt")
	Do $$$AssertEquals(calls.%Get(1).from, ##class(OcuTalon.Watch.Mark).Shift(##class(OcuTalon.Watch.Mark).Normal(firstRunAt), -2), "the next reads from the first run's own time less 2 seconds: "_calls.%Get(1).from)
	Do $$$AssertEquals(calls.%Get(0).limit_"|"_calls.%Get(1).limit, "500|500", "and the limit is 500")
	Do $$$AssertEquals(calls.%Get(0).namespace_"|"_calls.%Get(0).production, "ZZNS|"_production, "of the row's namespace and production")
}

/// The pure rule of Findings (rows 1-9 of the matrix), over previous values written as the row keeps them.
Method TestFindingsRule()
{
	Set none = "{""stopped"":0,""disabled"":[]}"
	Set stopped = "{""stopped"":1,""disabled"":[]}"
	// 1: stopped since the last run
	Set found = ##class(OcuTalon.Checks.Process).Findings(none, "stopped", [], .reported)
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[{""kind"":""stopped""}]|"_stopped, "row 1: stopped since the last run is one stop finding, and stopped is now 1")
	// 2: still stopped
	Set found = ##class(OcuTalon.Checks.Process).Findings(stopped, "stopped", [], .reported)
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[]|"_stopped, "row 2: still stopped reports nothing")
	// 3: restarted, then stopped again
	Set found = ##class(OcuTalon.Checks.Process).Findings(stopped, "running", [], .reported)
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[]|"_none, "row 3: a run that reads running makes stopped 0")
	Set found = ##class(OcuTalon.Checks.Process).Findings(reported, "stopped", [], .reported)
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[{""kind"":""stopped""}]|"_stopped, "row 3: and the next stop is new")
	// 5: items disabled, in the order given, after the stop
	Set found = ##class(OcuTalon.Checks.Process).Findings(none, "stopped", ["A", "B"], .reported)
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[{""kind"":""stopped""},{""kind"":""disabled"",""item"":""A""},{""kind"":""disabled"",""item"":""B""}]|{""stopped"":1,""disabled"":[""A"",""B""]}", "row 5: the stop first, then each newly disabled item in order")
	// 6: still disabled, re-enabled, disabled again
	Set both = "{""stopped"":0,""disabled"":[""A"",""B""]}"
	Set found = ##class(OcuTalon.Checks.Process).Findings(both, "running", ["A", "B"], .reported)
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[]|"_both, "row 6: still disabled reports nothing")
	Set found = ##class(OcuTalon.Checks.Process).Findings(both, "running", ["B"], .reported)
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[]|{""stopped"":0,""disabled"":[""B""]}", "row 6: re-enabled A is dropped from what was reported")
	Set found = ##class(OcuTalon.Checks.Process).Findings(reported, "running", ["A", "B"], .reported)
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[{""kind"":""disabled"",""item"":""A""}]|"_both, "row 6: and A disabled again is new")
	// 7: the first run is a baseline
	Set found = ##class(OcuTalon.Checks.Process).Findings("", "stopped", ["A"], .reported)
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[]|{""stopped"":1,""disabled"":[""A""]}", "row 7: with nothing reported, nothing is found and the state is recorded")
	// 8: a state that was not read
	For state = "timeout", "unknown", "" {
		Set found = ##class(OcuTalon.Checks.Process).Findings(both, state, ["C"], .reported)
		Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[]|"_both, "row 8: the state '"_state_"' reports nothing and leaves what was reported")
	}
	Set found = ##class(OcuTalon.Checks.Process).Findings("", "unknown", ["C"], .reported)
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[]|", "row 8: and an empty Reported stays empty")
	// 9: troubled and network_stopped are not stops, suspended is
	For state = "troubled", "network_stopped" {
		Set found = ##class(OcuTalon.Checks.Process).Findings(stopped, state, [], .reported)
		Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[]|"_none, "row 9: "_state_" reports nothing and makes stopped 0")
		Set found = ##class(OcuTalon.Checks.Process).Findings(none, state, [], .reported)
		Do $$$AssertEquals(found.%ToJSON(), "[]", "row 9: "_state_" after a run that was not stopped is no stop")
	}
	Set found = ##class(OcuTalon.Checks.Process).Findings(none, "suspended", [], .reported)
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[{""kind"":""stopped""}]|"_stopped, "row 9: suspended counts as stopped")
	// a previous value that is not JSON is a baseline
	Set found = ##class(OcuTalon.Checks.Process).Findings("not json", "stopped", [], .reported)
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[]|"_stopped, "a Reported that cannot be read is a baseline")
}

/// Rows 1 to 4: a production found stopped since the last run is one Item to Intake, with the fields, the trace and Reported; it is not sent again while the
/// production stays stopped; a restart makes the next stop new; the run time stands in when IRIS recorded no stop time.
Method TestStoppedIsReportedOnce()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("stopped")
	Set production = "Zz.Stopped"
	Set ref = ..Watch(a, production)
	Set host.%SuperSession = "zzown"
	Do ..Step(host, production, 0, "running")
	Do $$$AssertEquals(..Row(ref).Reported, "{""stopped"":0,""disabled"":[]}", "the baseline run records the state")
	Do $$$AssertEquals(..Items().%Size(), 0, "and sends nothing")
	Do ..Step(host, production, 1, "stopped", [], "2030-06-01 12:00:30.456")
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 1, "row 1: the stop is one Item")
	If items.%Size() = 1 {
		Set item = items.%Get(0)
		Do $$$AssertEquals($Length(item.itemId), 22, "a new Ref as ItemId: "_item.itemId)
		Do $$$AssertEquals(item.sessionRef_"|"_item.channel_"|"_item.provenance_"|"_item.sender_"|"_item.subject, a_"|system|untrusted||", "the row's session as owner, channel system, provenance untrusted")
		Do $$$AssertEquals(item.text, "The Zz "_production_" production stopped.", "the text")
		Do $$$AssertEquals(item.catalogKey_"|"_item.slots, "watch.productionStopped|{""production"":""Zz "_production_""",""time"":""2030-06-01T12:00:30Z""}", "the key and the slots, with IRIS's own stop time")
		Do $$$AssertEquals(item.sessionId_"|"_item.superSession, ..#SESSIONID_"|"_..TraceOf(a), "sent in the Tick's session with the owner's TraceRef as SuperSession")
	}
	Do $$$AssertEquals(host.%SuperSession, "zzown", "the process's own SuperSession is put back")
	Do $$$AssertEquals(..Row(ref).Reported, "{""stopped"":1,""disabled"":[]}", "Reported now holds stopped 1")
	Do ..Step(host, production, 2, "stopped", [], "2030-06-01 12:00:30.456")
	Do ..Step(host, production, 3, "stopped", [], "2030-06-01 12:00:30.456")
	Do $$$AssertEquals(..Items().%Size(), 1, "row 2: two more Ticks with the production still stopped send nothing")
	Do ..Step(host, production, 4, "running")
	Do $$$AssertEquals(..Row(ref).Reported, "{""stopped"":0,""disabled"":[]}", "row 3: a run that reads running makes stopped 0")
	Do ..Step(host, production, 5, "stopped", [], "2030-06-01 12:04:45.000")
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 2, "row 3: and the next stop is a new Item")
	If items.%Size() = 2 Do $$$AssertEquals(..Slot(items.%Get(1).slots, "time"), "2030-06-01T12:04:45Z", "with its own stop time")
	Do ..Step(host, production, 6, "running")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Step(host, production, 7, "stopped")
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 3, "row 4: a stop with no recorded time is an Item too")
	If items.%Size() = 3 {
		Set time = ..Slot(items.%Get(2).slots, "time")
		Do $$$AssertTrue(time ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "whose time is a UTC stamp: "_time)
		Do $$$AssertTrue('(before ] time) && '(time ] after), "and the run time: "_time)
	}
	Do $$$AssertEquals(..Warnings("Record", $Parameter(..#PROBE, "LOGFINDING"), , ..Checks), 0, "no warning was logged")
}

/// Row 9: troubled and network_stopped are not stops (and make stopped 0); suspended counts as stopped.
Method TestSuspendedAndTroubled()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("suspended")
	Set production = "Zz.Suspended"
	Set ref = ..Watch(a, production)
	Do ..Step(host, production, 0, "running")
	Do ..Step(host, production, 1, "troubled")
	Do ..Step(host, production, 2, "network_stopped")
	Do $$$AssertEquals(..Items().%Size(), 0, "troubled and network_stopped send nothing")
	Do ..Step(host, production, 3, "suspended")
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 1, "suspended is one Item")
	If items.%Size() = 1 Do $$$AssertEquals(items.%Get(0).catalogKey, "watch.productionStopped", "a stop")
	Do ..Step(host, production, 4, "troubled")
	Do $$$AssertEquals(..Row(ref).Reported, "{""stopped"":0,""disabled"":[]}", "troubled makes stopped 0")
	Do ..Step(host, production, 5, "stopped")
	Do $$$AssertEquals(..Items().%Size(), 2, "and the next stop is new")
}

/// Rows 5 and 6: each item newly found disabled is its own Item, in order; an item that stays disabled is not sent again; one that is enabled and
/// disabled again is.
Method TestDisabledItemsAreReportedOnce()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("disabled")
	Set production = "Zz.Disabled"
	Set ref = ..Watch(a, production)
	Do ..Step(host, production, 0, "running")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Step(host, production, 1, "running", ["A", "B"])
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 2, "row 5: two Items")
	If items.%Size() = 2 {
		Set time = ..Slot(items.%Get(0).slots, "time")
		Do $$$AssertTrue('(before ] time) && '(time ] after), "the time is the run time: "_time)
		For i = 0, 1 {
			Set item = items.%Get(i)
			Set name = $Char(65 + i)
			Do $$$AssertEquals(item.catalogKey_"|"_item.text, "watch.itemDisabled|The "_name_" in the Zz "_production_" production was disabled.", "item "_name_": the key and the text")
			Do $$$AssertEquals(item.slots, "{""itemName"":"""_name_""",""production"":""Zz "_production_""",""time"":"""_time_"""}", "item "_name_": the slots")
			Do $$$AssertEquals(item.sessionRef_"|"_item.channel_"|"_item.provenance_"|"_item.superSession, a_"|system|untrusted|"_..TraceOf(a), "item "_name_": owner, channel, provenance and trace")
		}
	}
	Do $$$AssertEquals(..Row(ref).Reported, "{""stopped"":0,""disabled"":[""A"",""B""]}", "Reported holds both")
	Do ..Step(host, production, 2, "running", ["A", "B"])
	Do $$$AssertEquals(..Items().%Size(), 2, "row 6: still disabled sends nothing")
	Do ..Step(host, production, 3, "running", ["B"])
	Do $$$AssertEquals(..Items().%Size(), 2, "row 6: A enabled again sends nothing")
	Do ..Step(host, production, 4, "running", ["A", "B"])
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 3, "row 6: and A disabled again is one Item")
	If items.%Size() = 3 Do $$$AssertEquals(..Slot(items.%Get(2).slots, "itemName"), "A", "for A")
}

/// Row 7: the first run of a row with nothing reported only records the state.
Method TestFirstRunIsABaseline()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("baseline")
	Set production = "Zz.Baseline"
	Set ref = ..Watch(a, production)
	Do $$$AssertEquals(..Row(ref).Reported, "", "a row from before the story, or a new watch, has nothing reported")
	Do ..Step(host, production, 0, "stopped", ["A"])
	Do $$$AssertEquals(..Items().%Size(), 0, "the first run sends nothing")
	Do $$$AssertEquals(..Row(ref).Reported, "{""stopped"":1,""disabled"":[""A""]}", "and records the state")
	Do ..Step(host, production, 1, "stopped", ["A"])
	Do $$$AssertEquals(..Items().%Size(), 0, "the next run finds nothing new")
}

/// Row 8: a run that did not read the state reports nothing and leaves Reported; a cut read, which still read the state, compares it.
Method TestNotCheckedReportsNothing()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("unread")
	Set production = "Zz.Unread"
	Set ref = ..Watch(a, production)
	Do ..Step(host, production, 0, "running")
	Set reported = ..Row(ref).Reported
	Set step = 0
	For label = "unreadable", "not_current", "timeout", "unknown", "empty", "throws" {
		Set step = step + 1
		Set spec = {"outcome": "read", "state": "stopped", "disabled": ["A"], "stoppedAt": "2030-06-01 12:00:30.000"}
		If label = "unreadable" Set spec.outcome = "unreadable"
		If label = "not_current" Set spec.outcome = "not_current"
		If label = "timeout" Set spec.state = "timeout"
		If label = "unknown" Set spec.state = "unknown"
		If label = "empty" Set spec.state = ""
		If label = "throws" Set spec.throw = "ERROR #5001: refused"
		Do $ClassMethod(..#PROBE, "Feed", production, spec)
		Do ..Tick(host, ..At(step))
		Do $$$AssertEquals(..Items().%Size()_"|"_..Row(ref).Reported, "0|"_reported, label_": no Item, and Reported is unchanged")
	}
	Do $$$AssertEquals(..Row(ref).Result, "not_checked", "the last of them is not_checked")
	// a read cut at its limit with none of the session's failures: not_checked, but the state was read
	Set other = ..Owner("unreadother")
	Do ..Feed(production, "read", "stopped", ..Failures(..TraceOf(other), 500))
	Do ..Tick(host, ..At(7))
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "not_checked|"_$Parameter(..#PROBE, "REASONTOOMANY"), "a cut read is not_checked")
	Do $$$AssertEquals(..Items().%Size()_"|"_row.Reported, "1|{""stopped"":1,""disabled"":[]}", "but it still reports the stop it read")
	// the incidents cannot be read: not_checked, but the state was read
	Set host.FailUnclosed = 1
	Do ..Step(host, production, 8, "running", ["B"])
	Set host.FailUnclosed = 0
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "not_checked|"_$Parameter(..#PROBE, "REASONREAD"), "an incident read that fails is not_checked")
	Do $$$AssertEquals(..Items().%Size()_"|"_row.Reported, "2|{""stopped"":0,""disabled"":[""B""]}", "but it still reports the item it read as disabled")
}

/// Row 10: the row is deleted during the read: no Item, and nothing recorded.
Method TestDeletedMeanwhileSendsNothing()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("deleted")
	Set production = "Zz.Deleted"
	Set ref = ..Watch(a, production)
	Do ..Step(host, production, 0, "running")
	Do ..Feed(production, "read", "stopped", "", "", ref, ["A"])
	Do ..Tick(host, ..At(1))
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(ref), 0, "the row stays removed")
	Do $$$AssertEquals(..Items().%Size(), 0, "no Item is sent")
}

/// Row 11: a send that fails logs one warning that names the check, the other finding still goes, and neither is sent again.
Method TestFailedSendIsNeverRetried()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("sendfails")
	Set production = "Zz.SendFails"
	Set ref = ..Watch(a, production)
	Set host.%SuperSession = "zzown"
	Do ..Step(host, production, 0, "running")
	Do $ClassMethod(..#PROBE, "FailFindings", "The A in")
	Do ..Step(host, production, 1, "running", ["A", "B"])
	Do $$$AssertEquals(..Items().%Size(), 2, "both findings are tried")
	Do $$$AssertEquals(..Warnings("Record", $Parameter(..#PROBE, "LOGFINDING"), .text, ..Checks), 1, "one warning is logged")
	Do $$$AssertTrue(text [ ref, "which names the check: "_text)
	Do $$$AssertEquals(host.%SuperSession, "zzown", "the SuperSession is put back after a failed send")
	Do $$$AssertEquals(..Row(ref).Reported, "{""stopped"":0,""disabled"":[""A"",""B""]}", "both count as reported")
	Do ..Step(host, production, 2, "running", ["A", "B"])
	Do $$$AssertEquals(..Items().%Size(), 2, "and the next Tick sends neither again")
	Do $$$AssertEquals(..Warnings("Record", $Parameter(..#PROBE, "LOGFINDING"), , ..Checks), 1, "with no new warning")
}

/// Row 11: a send that throws is handled like one that fails: one warning that names the check, the other finding still goes, the SuperSession is put back.
Method TestThrownSendIsNeverRetried()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("sendthrows")
	Set production = "Zz.SendThrows"
	Set ref = ..Watch(a, production)
	Set host.%SuperSession = "zzown"
	Do ..Step(host, production, 0, "running")
	Do $ClassMethod(..#PROBE, "FailFindings", "The A in", 1)
	Do ..Step(host, production, 1, "running", ["A", "B"])
	Do $$$AssertEquals(..Items().%Size(), 2, "both findings are tried, the second after the first threw")
	Do $$$AssertEquals(..Warnings("Record", $Parameter(..#PROBE, "LOGFINDING"), .text, ..Checks), 1, "one warning is logged")
	Do $$$AssertTrue(text [ ref, "which names the check: "_text)
	Do $$$AssertEquals(host.%SuperSession, "zzown", "the SuperSession is put back after a send that threw")
	Do $$$AssertEquals(..Row(ref).Reported, "{""stopped"":0,""disabled"":[""A"",""B""]}", "both count as reported")
	Do ..Step(host, production, 2, "running", ["A", "B"])
	Do $$$AssertEquals(..Items().%Size(), 2, "and the next Tick sends neither again")
}

/// Each Item's key and slots render, through the catalog at a fixed now, to the text of the UX.
Method TestFindingsRender()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("render")
	Set production = "Zz.Render"
	Set ref = ..Watch(a, production)
	Do ..Step(host, production, 0, "running")
	Do ..Step(host, production, 1, "stopped", ["Zz.Door"], "2030-06-01 12:01:20.000")
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 2, "a stop and a disabled item")
	If items.%Size() '= 2 Quit
	Set now = "2030-06-01T12:05:00Z"
	Set clock = ##class(OcuTalon.Data.Time).ForMessage("2030-06-01T12:01:20Z", now)
	Set why = $Char(10)_"Why now: you asked me to watch the Zz "_production_" production."
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).RenderAt(items.%Get(0).catalogKey, items.%Get(0).slots, "web", now, 0), "The Zz "_production_" production stopped at "_clock_"."_why, "the stop renders to the UX text")
	Set clock = ##class(OcuTalon.Data.Time).ForMessage(..Slot(items.%Get(1).slots, "time"), now)
	Set joiner = $Select(clock ? 2N1":"2N: " at ", 1: " on ")
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).RenderAt(items.%Get(1).catalogKey, items.%Get(1).slots, "web", now, 0), "The Zz.Door in the Zz "_production_" production was disabled"_joiner_clock_"."_why, "and so does the disabled item (a time on another day reads 'on {date} at {time}')")
}

Method TestStoppedMeanwhile()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("meanwhile")
	Set production = "Zz.Meanwhile"
	Set ref = ..Watch(a, production)
	Do ..Feed(production, "read", "running", "", "", ref)
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(ref), 0, "the row stays removed: it is never re-created")
	Do $$$AssertEquals(..Events(a).%Size(), 0, "no event is published")
	Do $$$AssertEquals(..Ran(ref), 0, "and no line is logged")
}

Method TestQuietSweep()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("quiet")
	Set long = ##class(OcuTalon.Bridge.Time).PlusSeconds(..#TICK, -960)
	Set short = ##class(OcuTalon.Bridge.Time).PlusSeconds(..#TICK, -840)
	Set resolved = ..Incident(a, "resolved", "Zz.Quiet", {"LastAt": (long)})
	Set open = ..Incident(a, "open", "Zz.Quiet", {"LastAt": (long)})
	Set awaiting = ..Incident(a, "awaiting_approval", "Zz.Quiet", {"LastAt": (long)})
	Set fixing = ..Incident(a, "fixing", "Zz.Quiet", {"LastAt": (long)})
	Set instance = ..Incident("instance", "resolved", "Zz.Quiet", {"LastAt": (long)})
	Set recent = ..Incident(a, "resolved", "Zz.Quiet", {"LastAt": (short)})
	Set closed = ..Incident(a, "closed", "Zz.Quiet", {"LastAt": (long), "ClosedAt": "2030-01-01T10:00:00Z"})
	Set host.%SuperSession = "zzown"
	Set host.QuietAt = ..#TICK
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Tick(host, ..#TICK)
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertTrue('(before ] host.SweptAt) && '(host.SweptAt ] after) && (host.SweptAt '= ..#TICK), "the sweep is handed the clock's now, not the Tick's time: "_host.SweptAt)
	Set sent = host.Quieted
	Do $$$AssertEquals(sent.%Size(), 5, "five commands are sent")
	Set refs = ""
	For i = 0:1:sent.%Size() - 1 {
		Set refs = refs_$Select(refs = "": "", 1: ",")_sent.%Get(i).incidentRef
	}
	Do $$$AssertEquals(refs, resolved_","_open_","_awaiting_","_fixing_","_instance, "one for each unclosed incident whose last failure is 16 minutes old, and none for the recent or the closed one")
	For i = 0:1:sent.%Size() - 1 {
		Set command = sent.%Get(i)
		Set expected = $Select(command.incidentRef = instance: "", 1: ..TraceOf(a))
		Do $$$AssertEquals(command.verb_"|"_command.origin_"|"_command.sessionRef_"|"_command.superSession_"|"_command.sessionId, "closeQuiet|timer||"_expected_"|"_..#SESSIONID, "command "_(i + 1)_": closeQuiet, origin timer, no session, the owner's TraceRef as SuperSession, in the process's session")
	}
	Do $$$AssertEquals(host.%SuperSession, "zzown", "the process's own SuperSession is put back")
	Set host.Quieted = ""
	Set host.FailQuiet = open
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(host.Quieted.%Size(), 5, "with one send failing, all five are still tried")
	Do $$$AssertEquals(..Warnings("Sweep", $Parameter(..#PROBE, "LOGQUIET"), .text, ..Incidents), 1, "and one warning is logged")
	Do $$$AssertTrue(text [ open, "which names the incident: "_text)
	Do $$$AssertEquals(host.%SuperSession, "zzown", "the SuperSession is put back after a failed send too")
	Set host.FailQuiet = ""
	Set host.SilentQuiet = awaiting
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(..Warnings("Sweep", $Parameter(..#PROBE, "LOGQUIET"), , ..Incidents), 2, "a send that IncidentManager did not answer in time (OK, with no answer) logs one warning too")
	Do $$$AssertEquals(..Warnings("Sweep", $Parameter(..#PROBE, "LOGQUIET")_awaiting, .text), 1, "one for it")
	Do $$$AssertTrue(text [ awaiting, "which names its incident: "_text)
}

Method TestTickSendsTheSweptResults()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("fixes")
	Set long = ##class(OcuTalon.Bridge.Time).PlusSeconds(..#TICK, -960)
	Set short = ##class(OcuTalon.Bridge.Time).PlusSeconds(..#TICK, -840)
	Set quiet = ..Incident(a, "resolved", "Zz.Fixes", {"LastAt": (long)})
	Set i1 = ..Incident(a, "fixing", "Zz.Fixes1", {"LastAt": (short), "TraceHeaderId": 4242001})
	Set i2 = ..Incident(a, "fixing", "Zz.Fixes2", {"LastAt": (short), "TraceHeaderId": 4242002})
	Set i3 = ..Incident(a, "fixing", "Zz.Fixes3", {"LastAt": (short)})
	Set trace1 = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set trace2 = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set trace3 = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set r1 = ##class(OcuTalon.Test.Data.Fixture).Approval(a, i1, "failed", , {"TraceRef": (trace1)})
	Set r2 = ##class(OcuTalon.Test.Data.Fixture).Approval(a, i2, "failed", , {"TraceRef": (trace2)})
	Set r3 = ##class(OcuTalon.Test.Data.Fixture).Approval(a, i3, "failed", , {"TraceRef": (trace3)})
	Set ..Refs = ..Refs_","_r1_","_r2_","_r3
	Set ..Requests = r1_","_r2_","_r3
	Set host.QuietAt = ..#TICK
	Set host.%SuperSession = "zzown"
	Set host.Swept = ##class(%ListOfObjects).%New()
	Do host.Swept.Insert(..Result(r1, i1))
	Do host.Swept.Insert(..Result(r2, i2))
	Do host.Swept.Insert(..Result(r3, i3))
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(host.Sent.%Size(), 3, "the three results are each sent")
	If host.Sent.%Size() = 3 {
		Do $$$AssertEquals(host.Sent.%Get(0).approvalRef_"|"_host.Sent.%Get(0).sessionId_"|"_host.Sent.%Get(0).superSession, r1_"|4242001|"_trace1, "the first goes in its incident's trace session with its request's TraceRef")
		Do $$$AssertEquals(host.Sent.%Get(1).approvalRef_"|"_host.Sent.%Get(1).sessionId_"|"_host.Sent.%Get(1).superSession, r2_"|4242002|"_trace2, "the second in its own")
		Do $$$AssertEquals(host.Sent.%Get(2).approvalRef_"|"_host.Sent.%Get(2).sessionId_"|"_host.Sent.%Get(2).superSession, r3_"|"_..#SESSIONID_"|"_trace3, "an incident with no trace session keeps the process's session, with its request's TraceRef")
	}
	Do $$$AssertEquals(host.Order.%Size(), 4, "four sends in all")
	If host.Order.%Size() = 4 Do $$$AssertEquals(host.Order.%Get(0)_","_host.Order.%Get(1)_","_host.Order.%Get(2)_","_host.Order.%Get(3), "quiet:"_quiet_",fix:"_r1_",fix:"_r2_",fix:"_r3, "the quiet sweep comes first, then the fixes in order")
	Do $$$AssertEquals(host.%SessionId_"|"_host.%SuperSession, ..#SESSIONID_"|zzown", "the process's own session and SuperSession are put back")

	// a send that fails: one warning that names the request, and the others still go
	Set host.Sent = ""
	Set host.Order = ""
	Set host.FailFix = r1
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(host.Sent.%Size(), 3, "with the first send failing, all three are still tried")
	Do $$$AssertEquals(..Warnings("Fixes", $Parameter(..#PROBE, "LOGFIX"), .text, ..Requests), 1, "and one warning is logged")
	Do $$$AssertTrue(text [ r1, "which names the request: "_text)
	Do $$$AssertEquals(host.%SessionId_"|"_host.%SuperSession, ..#SESSIONID_"|zzown", "the session and the SuperSession are put back after a failed send too")

	// a Sweep that throws: one warning, and the due checks still run
	Set host.FailFix = ""
	Set host.Sent = ""
	Set host.SweepThrows = "zzchk"_..Number_" sweep refused"
	Set production = "Zz.FixesDue"
	Set ref = ..Watch(a, production)
	Do ..Feed(production, "read", "running")
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals($Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), 0, "a Sweep that throws sends nothing")
	Do $$$AssertEquals(..Fixed(), 1, "and logs one warning")
	Do $$$AssertEquals(..Row(ref).Result, "passed", "the due check still ran")
}

Method TestChanged()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("changed")
	Set production = "Zz.Changed"
	Set ref = ..Watch(a, production)
	Set change = ##class(OcuTalon.Checks.Msg.CheckChanged).%New()
	Set change.CheckRef = ref
	Set change.SessionRef = a
	Set change.Kind = "production"
	Set change.Namespace = "ZZNS"
	Set change.Production = production
	Set change.DisplayName = "Zz "_production
	Do $$$AssertStatusOK(host.OnRequest(change, .response), "a start is answered")
	Do $$$AssertEquals(response, "", "with no response")
	Set events = ..Events(a)
	Do $$$AssertEquals(events.%Size(), 1, "one check event is published")
	If events.%Size() = 1 {
		Do $$$AssertEquals(events.%Get(0).payload.%ToJSON(), ..ViewOf(ref), "it is FromRow of the row")
		Do $$$AssertEquals(events.%Get(0).payload.%IsDefined("traceHeaderId"), 0, "with no run, it has no trace")
	}
	Set gone = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set change.CheckRef = gone
	Do $$$AssertStatusOK(host.OnRequest(change, .response), "a start whose row is gone is answered")
	Do $$$AssertEquals(..Events(a).%Size(), 1, "and publishes nothing")
	Set change.CheckRef = ref
	Set change.Stopped = 1
	Do ##class(OcuTalon.Data.BackgroundCheck).%DeleteId(##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref).%Id())
	Do $$$AssertStatusOK(host.OnRequest(change, .response), "a stop is answered")
	Set events = ..Events(a)
	Do $$$AssertEquals(events.%Size(), 2, "a second event is published")
	If events.%Size() = 2 {
		Set payload = events.%Get(1).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.kind_"|"_payload.namespace_"|"_payload.production_"|"_payload.displayName_"|"_payload.stopped, ref_"|production|ZZNS|"_production_"|Zz "_production_"|1", "with the message's Ref, kind, namespace, production and name, and stopped true")
	}
	Set change.SessionRef = "not a stream"
	Do $$$AssertStatusOK(host.OnRequest(change, .response), "a change for a session that has no stream is answered")
	Do $$$AssertEquals(..Warnings("Announce", $Parameter(..#PROBE, "LOGPUBLISH"), , ref_","_gone), 1, "and one warning is logged for the failed publish")
}

Method TestPublishes()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("publishA")
	Set b = ..Owner("publishB")
	Set one = ..Watch(a, "Zz.Publish1")
	Set two = ..Watch(b, "Zz.Publish2")
	Do ..Feed("Zz.Publish1", "read", "running")
	Do ..Feed("Zz.Publish2", "read", "stopped")
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(..Events(a).%Size()_"|"_..Events(b).%Size(), "1|1", "one check event per run, on the stream of the row's session")
	If ..Events(a).%Size() = 1 Do $$$AssertEquals(..Events(a).%Get(0).payload.%ToJSON(), ..ViewOf(one), "A's is FromRow of the row after the run")
	If ..Events(b).%Size() = 1 Do $$$AssertEquals(..Events(b).%Get(0).payload.%ToJSON(), ..ViewOf(two), "and so is B's")
	Do ..Tick(host, ..#NEXT)
	Do $$$AssertEquals(..Events(a).%Size()_"|"_..Events(b).%Size(), "2|2", "and one more each minute")
	Do ..Tick(host, ..#NEXT)
	Do $$$AssertEquals(..Events(a).%Size()_"|"_..Events(b).%Size(), "2|2", "none for a Tick that runs nothing")
}

Method TestRunThrows()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("throws")
	Set bad = ..Watch(a, "Zz.Throws1")
	Set good = ..Watch(a, "Zz.Throws2")
	Do $ClassMethod(..#PROBE, "Feed", "Zz.Throws1", {"outcome": "read", "state": "running", "rows": "not rows"})
	Do ..Feed("Zz.Throws2", "read", "running")
	Do ..Tick(host, ..#TICK)
	Set row = ..Row(bad)
	Do $$$AssertEquals(row.LastRunAt_"|"_row.Result_"|"_row.NextDueAt, "||", "a run that throws outside the read records nothing")
	Do $$$AssertEquals(..Row(good).Result, "passed", "and the next due row still runs")
	Do $$$AssertEquals(..Warnings("Tick", $Parameter(..#PROBE, "LOGRUN"), .text, ..Checks), 1, "one warning is logged")
	Do $$$AssertTrue(text [ bad, "which names the check: "_text)
}

Method TestRanLine()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("ranline")
	Set one = ..Watch(a, "Zz.Ran1")
	Set two = ..Watch(a, "Zz.Ran2")
	Do ..Feed("Zz.Ran1", "read", "running")
	Do ..Feed("Zz.Ran2", "read", "stopped", ..Failures(..TraceOf(a), 2))
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(..Ran(one), 1, "one Type 4 line for the first run")
	Do $$$AssertEquals(..Ran(two), 1, "and one for the second")
	Do $$$AssertEquals(..RanLine(one), $Parameter(..#PROBE, "LOGRAN")_one_" (Zz Zz.Ran1): passed", "it names the Ref, the name and the result")
	Do $$$AssertEquals(..RanLine(two), $Parameter(..#PROBE, "LOGRAN")_two_" (Zz Zz.Ran2): failed, Production stopped, 2 new failures", "and the finding")
	Do ..Tick(host, ..#NEXT)
	Do $$$AssertEquals(..Ran(one)_"|"_..Ran(two), "2|2", "each run adds one")
}

Method TestUnknownRequest()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set sc = host.OnRequest(##class(Ens.StringRequest).%New(), .response)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5001, "a request of another class is the error 5001, not 5003")
	Do $$$AssertTrue($Find($SYSTEM.Status.GetErrorText(sc), "Ens.StringRequest"), "which names the class: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(response, "", "and gives no answer")
}

/// --- helpers ---
/// A shadow instance of the probe, in this process, with a known session.
Method Host() As OcuTalon.Test.Checks.Probe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	If $IsObject(host) Set host.%SessionId = ..#SESSIONID
	Quit host
}

/// A fixture session; its Ref is the owner of the fixture checks and incidents.
Method Owner(name As %String) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzchk"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The TraceRef of a fixture session.
ClassMethod TraceOf(session As %String) As %String
{
	Quit ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
}

/// A fixture check of the session on the production, of the probe's Kind, created at a fixed time unless fields say otherwise, due at once; its Ref.
Method Watch(session As %String, production As %String, fields As %DynamicObject = "") As %String
{
	Set all = {"Kind": ($Parameter(..#PROBE, "KIND")), "CreatedAt": "2030-05-01T10:00:00Z", "NextDueAt": ""}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, "ZZNS", production, all)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Checks = ..Checks_$Select(..Checks = "": "", 1: ",")_ref
	Quit ref
}

/// A fixture incident of the owner on the production in the state, noticed; its Ref.
Method Incident(owner As %String, state As %String, production As %String, fields As %DynamicObject = "", noticed As %Boolean = 1) As %String
{
	Set all = {"State": (state), "OpenVariant": ""}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, $Select(noticed: ##class(OcuTalon.Data.Time).NowUtc(), 1: ""), "ZZNS", production, all)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Incidents = ..Incidents_$Select(..Incidents = "": "", 1: ",")_ref
	Quit ref
}

/// What Read answers for the production: the outcome, the state, the rows (a dynamic array or ""), the text of the error that it throws instead, the Ref
/// of a row that it deletes first, the names of the disabled items (a dynamic array or "") and the recorded stop time.
Method Feed(production As %String, outcome As %String, state As %String, rows As %DynamicArray = "", throw As %String = "", delete As %String = "", disabled As %DynamicArray = "", stoppedAt As %String = "")
{
	Set spec = {"outcome": (outcome), "state": (state), "throw": (throw), "delete": (delete), "stoppedAt": (stoppedAt)}
	If $IsObject(rows) Do spec.%Set("rows", rows)
	If $IsObject(disabled) Do spec.%Set("disabled", disabled)
	Do $ClassMethod(..#PROBE, "Feed", production, spec)
}

/// The Tick of step n (60 seconds each after the Tick TICK), with the read of the production answering the state, the names of the disabled items and the
/// recorded stop time.
Method Step(host As OcuTalon.Test.Checks.Probe, production As %String, n As %Integer, state As %String, disabled As %DynamicArray = "", stoppedAt As %String = "")
{
	Do ..Feed(production, "read", state, "", "", "", disabled, stoppedAt)
	Do ..Tick(host, ..At(n))
}

/// The time of the Tick of step n: TICK plus n minutes.
ClassMethod At(n As %Integer) As %String
{
	Quit ##class(OcuTalon.Bridge.Time).PlusSeconds(..#TICK, 60 * n)
}

/// The finding Items that the probe sent, in order.
ClassMethod Items() As %DynamicArray
{
	Quit $ClassMethod(..#PROBE, "FindingItems")
}

/// The slot of an Item's JSON slots.
ClassMethod Slot(slots As %String, name As %String) As %String
{
	Quit ##class(%DynamicAbstractObject).%FromJSON(slots).%Get(name)
}

/// count failures of the reader, each in the SuperSession.
ClassMethod Failures(superSession As %String, count As %Integer) As %DynamicArray
{
	Set rows = []
	For i = 1:1:count {
		Do rows.%Push({"kind": "header", "headerId": (i), "superSession": (superSession), "at": "2030-06-01 11:59:59.000", "logId": ""})
	}
	Quit rows
}

/// Appends the rows of other to rows.
ClassMethod Append(rows As %DynamicArray, other As %DynamicArray)
{
	Set iterator = other.%GetIterator()
	While iterator.%GetNext(, .row) {
		Do rows.%Push(row)
	}
}

/// A Tick of the time, handled by the probe.
Method Tick(host As OcuTalon.Test.Checks.Probe, tickAt As %String)
{
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = tickAt
	Set host.Only = ..Checks
	Set host.OnlyIncidents = ..Incidents
	Do $$$AssertStatusOK(host.OnRequest(tick, .response), "the Tick at "_tickAt_" is answered OK")
}

/// One case: a check of the session on a new production, a read made from the spec ({"outcome" (read), "state" (running), "failures" (of the session),
/// "others" (of another session), "incidents" (states of the session's incidents, "!" ends one that is not noticed), "failUnclosed"}), one Tick, and the
/// result and the finding of the row asserted. The Ref of the row.
Method Case(host As OcuTalon.Test.Checks.Probe, session As %String, label As %String, spec As %DynamicObject, result As %String, finding As %String) As %String
{
	Set ..Cases = ..Cases + 1
	Set production = "Zz.Case"_..Number_"n"_..Cases
	Set ref = ..Watch(session, production)
	Set rows = ..Failures(..TraceOf(session), +spec.failures)
	If (..Other = "") && spec.others Set ..Other = ..Owner("caseother")
	Do ..Append(rows, ..Failures($Select(..Other = "": "", 1: ..TraceOf(..Other)), +spec.others))
	Do ..Feed(production, $Select(spec.outcome '= "": spec.outcome, 1: "read"), $Select(spec.state '= "": spec.state, spec.outcome = "": "running", 1: ""), rows)
	Set host.FailUnclosed = +spec.failUnclosed
	If $IsObject(spec.incidents) {
		Set iterator = spec.incidents.%GetIterator()
		While iterator.%GetNext(, .state) {
			Set noticed = ($Extract(state, *) '= "!")
			Do ..Incident(session, $Translate(state, "!"), production, "", noticed)
		}
	}
	Do ..Tick(host, ..#TICK)
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, result_"|"_finding, label_": "_result_", '"_finding_"'")
	Quit ref
}

/// A final FixResult of the request for the incident, as Sweep returns it.
ClassMethod Result(approvalRef As %String, incidentRef As %String) As OcuTalon.Fix.Msg.FixResult
{
	Set result = ##class(OcuTalon.Fix.Msg.FixResult).%New()
	Set result.ApprovalRef = approvalRef
	Set result.IncidentRef = incidentRef
	Set result.Final = 1
	Set result.Total = 3
	Set result.Resent = 3
	Set result.Completed = 3
	Quit result
}

/// The number of warnings since the test began that Tick logged for a Sweep that threw this test's own text.
Method Fixed() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = 'Tick' AND Text %STARTSWITH ? AND Text [ ?", ..LogMark, $Parameter(..#PROBE, "LOGFIXES"), "zzchk"_..Number_" sweep refused")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The check row of the Ref, as stored now (an object that the test opened before is reloaded: Checks changes the row with SQL).
ClassMethod Row(ref As %String) As OcuTalon.Data.BackgroundCheck
{
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
	If $IsObject(row) Do row.%Reload()
	Quit row
}

/// The name of a row for a message.
ClassMethod Name(row As OcuTalon.Data.BackgroundCheck) As %String
{
	Quit row.Production
}

/// The JSON of FromRow of the row of the Ref.
ClassMethod ViewOf(ref As %String) As %String
{
	Do ##class(OcuTalon.Live.Payload.Check).FromRow(..Row(ref)).%JSONExportToString(.json)
	Quit json
}

/// The check events of the session's stream, in order.
ClassMethod Events(session As %String) As %DynamicArray
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(session, "check")
}

/// The productions that the probe read, comma-separated, in order.
Method Reads() As %String
{
	Set calls = $ClassMethod(..#PROBE, "Calls")
	Set reads = ""
	For i = 0:1:calls.%Size() - 1 {
		Set reads = reads_$Select(reads = "": "", 1: ",")_calls.%Get(i).production
	}
	Quit reads
}

/// The number of warnings since the test began that the method logged and that start as given (the line's text and the Ref of the test's own row or
/// incident); text is the newest one's. With refs (comma-separated), start is the line's text alone and the count is over the lines of each of those Refs,
/// so that the count covers all the test's own rows or incidents and no other job's; text is then the newest line of the last Ref in the list that has one.
Method Warnings(method As %String, start As %String, Output text As %String, refs As %String = "") As %Integer
{
	If refs = "" Quit ##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, method, start)
	Set text = ""
	Set count = 0
	For i = 1:1:$Length(refs, ",") {
		Set ref = $Piece(refs, ",", i)
		If ref = "" Continue
		Set n = ##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .line, method, start_ref)
		If n Set count = count + n, text = line
	}
	Quit count
}

/// The number of info lines (Type 4) of runs of the check since the test began.
Method Ran(ref As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGRAN")_ref)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The text of the newest info line (Type 4) of a run of the check, "" when there is none.
Method RanLine(ref As %String) As %String
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ? ORDER BY ID DESC", ..LogMark, $Parameter(..#PROBE, "LOGRAN")_ref)
	If result.%Next() Quit result.%Get("Text")
	Quit ""
}

/// Removes the lines that the tests made about their own rows and incidents: the warnings of the runs and the info lines of the runs, by the Refs of the
/// checks, and the warnings of the sweep, by the Refs of the incidents.
Method RemoveLogs()
{
	For i = 1:1:$Length(..Checks, ",") {
		Set ref = $Piece(..Checks, ",", i)
		If ref = "" Continue
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Run", $Parameter(..#PROBE, "LOGREAD")_ref)
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Tick", $Parameter(..#PROBE, "LOGRUN")_ref)
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Announce", $Parameter(..#PROBE, "LOGPUBLISH")_ref)
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Record", $Parameter(..#PROBE, "LOGFINDING")_ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGRAN")_ref)
	}
	For i = 1:1:$Length(..Incidents, ",") {
		Set ref = $Piece(..Incidents, ",", i)
		If ref = "" Continue
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Sweep", $Parameter(..#PROBE, "LOGQUIET")_ref)
	}
	For i = 1:1:$Length(..Requests, ",") {
		Set ref = $Piece(..Requests, ",", i)
		If ref = "" Continue
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Fixes", $Parameter(..#PROBE, "LOGFIX")_ref)
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = 'Tick' AND Text %STARTSWITH ? AND Text [ ?", ..LogMark, $Parameter(..#PROBE, "LOGFIXES"), "zzchk"_..Number_" sweep refused")
}

}
