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
///   - Story 23.9 (AC5; DW-1068, second half): TestSuspendedByOcuTalonIsNotReported (the suspend's incident is resolved, so it holds the item), TestSuspendedHoldersAndReleased (Fix.Run Suspended's holders and released: the
///     newest changing run decides, an item of a closed incident is released and leaves names and fresh, a resume or another incident's suspend moves the hold), TestReleasedFindings (the pure rule of
///     Findings for released) and TestDismissedSuspendIsReportedOnce (a dismissed incident's suspend is reported once, at the suspend's end, and then no more);
///   - Findings, QA (Story 30.4): TestAnUnreadFirstRunLeavesTheBaselineForTheFirstRead (rows 7 and 8: a first run that cannot read leaves Reported empty, and the first read is the baseline) and
///     TestEachRowRemembersItsOwnReport (two watches of one production: each Item to its own session and trace, and a run records its own row only);
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
///   - TestTickRunsTheBeatsLast (Story 39.1; matrix row 1): the probe's BeatRunDue is called once with the Tick's time, after the quiet sweep's send and the due row's read, and the
///     row still runs (passed); nothing is added to the probe's Order;
///   - TestBeatsThatFailAreLogged (rows 2 and 3): a RunDue that throws, and one that answers an error status, each log one warning (LOGBEAT) that holds the test's marker, and the Tick still answers OK;
///   - TestTickSendsTheBeats (Story 39.3; AC 2): with the probe made to run the real Beat for a person, the Tick sends the beat's Item (channel heartbeat, untrusted) after the due row's read,
///     in a trace session of its own (the process's session is cleared for the send) with the TraceRef of the person's session as SuperSession, and puts the process's own session back;
///   - TestBeatSendFailureIsLogged (Story 39.3): a send of a beat that fails logs one warning (LOGBEATSEND) that names the ItemId and not the SessionRef, and the Tick answers OK;
///   - TestBeatNow (rows 4 and 5, Story 39.3): a BeatNow is answered OK with a CommandResult that holds the outcome of RunNow, RunNow is called once with the request's SessionRef and the
///     request's time (the current time when RequestedAt is not a UTC stamp), and no send, no row read and no RunDue is made; a RunNow that throws logs one warning (LOGBEATNOW) that holds the
///     marker and not the SessionRef, and so does a RunNow that answers an error status, and the outcome is then failed;
///   - TestBeatNowRunsOnce (Story 39.3; AC 4): a BeatNow sends one Item and answers sent with the ItemId as Ref; a second one within two minutes answers cooldown with availableAt and sends nothing;
///   - TestTickSendsTheItemsOfAFailedRunDue (Story 39.3): a RunDue that returns an Item together with an error status logs one warning, and the Item is still sent;
///   - TestBeatNowSendFailureAnswersFailed (Story 39.3): a BeatNow whose send fails answers failed with no Ref and logs one warning that names the ItemId and not the SessionRef;
///   - TestBeatsRunWhateverEarlierStepsDo (Story 39.1): a Sweep that throws and a due row that throws do not stop RunDue, and the Tick answers OK; a Tick whose TickAt is not a UTC stamp gives
///     RunDue the Tick's own current time (a UTC stamp), never the bad text; a CheckChanged calls neither RunDue nor RunNow;
///   - TestTickPublishesTheBeats (Story 39.7; AC 1-3): with the probe made to run the real Beat, a Tick publishes one heartbeat event for each committed row, FromRow of the row, on the
///     person's stream and in commit order: a beat that runs, a skip (a back-off; the skip for an empty checklist is saved and publishes none), a recorded result (with a fallback's back-off and the decision's trace), and a recorded ignore then the
///     unchanged skip of one person (two events, in that order); a Tick that commits nothing publishes nothing, and no event holds the SessionRef or the checklist;
///   - TestTickPublishesEachCommitInOrder (Story 39.7; AC 1): a pending ignore and the beat due at the same Tick commit twice, so two events go out, the recorded ignore
///     first and the unchanged skip second, the second FromRow of the row;
///   - TestBeatNowPublishes (Story 39.7): a BeatNow publishes its run now, held or sent, with lastRunNowAt; a cooldown publishes nothing, or only the result of a pending decision;
///   - TestBeatPublishFailureIsLogged (Story 39.7; AC 2): a publish that fails and one that throws each log one warning (LOGBEATPUBLISH) without the SessionRef, as it is and in upper
///     case and without a secret in the error text, the Tick answers OK, the Item is still sent, the events go out only after the sends and the other people's events are still
///     published, and a BeatNow whose publish fails still answers sent and publishes only after its Item is sent; the warnings counted and removed are those that hold the probe's own error text;
///   - TestPublishedEventsHoldNoRefChecklistOrKey (Story 39.7, QA; AC 2): every event of a recorded ignore with the unchanged skip, a beat with its recorded fallback, a run now
///     that is sent, and a run now that is held holds none of the SessionRef (in any case), the checklist, the Item's Id, the decision's Ref and the snapshot keys of the row, and only keys of the view;
///   - TestOffPersonsRecordedResultIsPublishedWithTheirSettings (Story 39.7, QA; AC 1, AC 3): an off person's recorded decision is published with off, the interval, the hours, the cost
///     and the trace of the person's own settings and decision, and a later Tick publishes nothing for them;
///   - TestBeatPublishesWhatRunDueCommittedBeforeAnError (Story 39.7): the view of a beat that committed before RunDue answered an error status is published;
///   - TestBeatLogsAreRedacted: a secret in the error text of a RunDue or a RunNow is redacted from the LOGBEAT and LOGBEATNOW line, which still holds the text before it, and a
///     SessionRef in the error text of a RunNow, in any case, is left out, whether RunNow answers it or throws it;
///   - TestBeatNowKeepsEachSession: two BeatNows of two sessions call RunNow twice, in order, each with its own SessionRef, and a repeated BeatNow is not collapsed;
///   - TestCheckNow (Story 5.15; matrix "Check now runs", "Empty NextDueAt"): a CheckNow runs only the owner's rows of the request's production, each once: its run
///     fields are set, NextDueAt is left as it was (also when it is empty), one check event (FromRow) and one LOGRAN line; the owner's other production and another
///     session's row are unchanged; nothing is quieted, no fix result is sent, no beat runs and nothing goes to Digest;
///   - TestCheckNowScope ("Scope"): the owner a session, instance on a local install, instance on the online demo, eval, an empty owner and another namespace;
///   - TestCheckNowFailures ("Read fails / no row"): a read of the rows that throws logs one LOGNOW warning that names the incident and changes nothing, no matching
///     row logs nothing, and a row whose run throws logs LOGRUN while the next row still runs;
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

/// The text of the probe's PublishBeat error, which no real publish gives: the LOGBEATPUBLISH lines that hold it are the probe's.
Parameter BEATPUBLISHREFUSED = "The heartbeat event is refused for ";

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

/// The ItemIds of the beats of the test being run, comma-separated (the warnings of their sends name them).
Property BeatItems As %String(MAXLEN = "");

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
	Set ..BeatItems = ""
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $ClassMethod(..#PROBE, "Reset")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	For i = 1:1:$Length(..Refs, ",") {
		If $Piece(..Refs, ",", i) '= "" Do ##class(OcuTalon.Test.Checks.Beat).Forget($Piece(..Refs, ",", i))
	}
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
/// production stays stopped; a restart makes the next stop new; the run time stands in when IRIS recorded no stop time (AD-15: a change's time is known only to
/// within the check interval).
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
		Do $$$AssertEquals(item.sessionId_"|"_item.superSession, "|"_..TraceOf(a), "sent in a trace session of its own (AD-26: the process's session is cleared for the send) with the owner's TraceRef as SuperSession: "_item.sessionId_"|"_item.superSession)
	}
	Do $$$AssertEquals(host.%SessionId_"|"_host.%SuperSession, ..#SESSIONID_"|zzown", "the process's own session and SuperSession are put back")
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

/// Rows 5 and 6: each item newly found disabled is its own Item, in order, whose time is the run time (IRIS records none; AD-15); an item that stays disabled
/// is not sent again; one that is enabled and disabled again is.
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

/// Story 23.2 (AC5): the pure rule with the items that OcuTalon suspended: such an item is in what is reported but gets no finding, an item disabled by anyone else still does.
Method TestSuspendedItemsGetNoFinding()
{
	Set none = "{""stopped"":0,""disabled"":[]}"
	Set found = ##class(OcuTalon.Checks.Process).Findings(none, "running", ["A", "B"], .reported, $ListBuild("A"))
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[{""kind"":""disabled"",""item"":""B""}]|{""stopped"":0,""disabled"":[""A"",""B""],""ours"":[""A""]}", "A, suspended by OcuTalon, is reported and recorded in ours but gets no finding; B does")
	Set found = ##class(OcuTalon.Checks.Process).Findings(none, "running", ["A", "B"], .reported)
	Do $$$AssertEquals(found.%Size(), 2, "with no suspended item both get one")
	Set found = ##class(OcuTalon.Checks.Process).Findings(none, "running", ["A"], .reported, $ListBuild("C", "A"))
	Do $$$AssertEquals(found.%Size(), 0, "a list of several suspended items is read whole")
	// a foreign enable, then a foreign disable, of the item that OcuTalon suspended
	Set sighted = "{""stopped"":0,""disabled"":[""A"",""B""],""ours"":[""A""]}"
	Set found = ##class(OcuTalon.Checks.Process).Findings(sighted, "running", ["B"], .reported, $ListBuild("A"))
	Do $$$AssertEquals(found.%Size()_"|"_reported, "0|{""stopped"":0,""disabled"":[""B""],""ours"":[""A""]}", "A enabled by anyone else sends nothing and stays in ours while suspended lists it")
	Set found = ##class(OcuTalon.Checks.Process).Findings(reported, "running", ["A", "B"], .reported, $ListBuild("A"))
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[{""kind"":""disabled"",""item"":""A""}]|{""stopped"":0,""disabled"":[""A"",""B""],""ours"":[""A""]}", "and A disabled by anyone else afterwards is one finding")
	Set found = ##class(OcuTalon.Checks.Process).Findings(reported, "running", ["A", "B"], .reported, $ListBuild("A"))
	Do $$$AssertEquals(found.%Size(), 0, "which is reported once")
	// a foreign enable, then a second suspend by OcuTalon (fresh: its run ended since the previous run)
	Set found = ##class(OcuTalon.Checks.Process).Findings(sighted, "running", ["B"], .reported, $ListBuild("A"))
	Set found = ##class(OcuTalon.Checks.Process).Findings(reported, "running", ["A", "B"], .reported, $ListBuild("A"), $ListBuild("A"))
	Do $$$AssertEquals(found.%Size()_"|"_reported, "0|{""stopped"":0,""disabled"":[""A"",""B""],""ours"":[""A""]}", "A enabled by anyone else and then suspended again by OcuTalon gets no finding")
	// OcuTalon suspends, resumes (the name leaves suspended), and suspends again
	Set found = ##class(OcuTalon.Checks.Process).Findings(sighted, "running", ["B"], .reported)
	Do $$$AssertEquals(found.%Size()_"|"_reported, "0|{""stopped"":0,""disabled"":[""B""]}", "a resume ends ours")
	Set found = ##class(OcuTalon.Checks.Process).Findings(reported, "running", ["A", "B"], .reported, $ListBuild("A"))
	Do $$$AssertEquals(found.%Size()_"|"_reported, "0|{""stopped"":0,""disabled"":[""A"",""B""],""ours"":[""A""]}", "and a second suspend by OcuTalon gets no finding")
	// a baseline records ours
	Set found = ##class(OcuTalon.Checks.Process).Findings("", "running", ["A", "B"], .reported, $ListBuild("A"))
	Do $$$AssertEquals(found.%Size()_"|"_reported, "0|{""stopped"":0,""disabled"":[""A"",""B""],""ours"":[""A""]}", "a baseline records the disabled names that suspended lists as ours")
	Set found = ##class(OcuTalon.Checks.Process).Findings("", "running", ["A", "B"], .reported)
	Do $$$AssertEquals(reported, "{""stopped"":0,""disabled"":[""A"",""B""]}", "and no ours key when there is none")
}

/// Story 23.2 (AC5, Integration): Checks reads Fix.Run Suspended. An item that OcuTalon suspended (a done suspend_item that changed it) is not reported as disabled while its incident is not
/// closed; once a resume_item changed it again, the same item disabled by anyone else is reported.
Method TestSuspendedByOcuTalonIsNotReported()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("suspended")
	Set production = "Zz.Suspended"
	Set ref = ..Watch(a, production)
	Do ..Step(host, production, 0, "running")
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(a, , "ZZNS", production, {"State": "resolved", "OpenVariant": ""})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_incident
	Do ..Done(a, incident, "suspend_item", "A")
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Fix.Run).Suspended("ZZNS", production)), "A", "Fix.Run Suspended names A")
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Fix.Run).Suspended("ZZNS", "Zz.Other")), 0, "and nothing for another production")
	Do ##class(OcuTalon.Fix.Run).Suspended("ZZNS", production, "2000-01-01T00:00:00Z", .fresh)
	Do $$$AssertEquals($ListToString(fresh), "A", "A's suspend ended after a previous run of 2000, so it is fresh")
	Do ##class(OcuTalon.Fix.Run).Suspended("ZZNS", production, "2999-01-01T00:00:00Z", .fresh)
	Do $$$AssertEquals($ListLength(fresh), 0, "and not after one of 2999")
	Do ##class(OcuTalon.Fix.Run).Suspended("ZZNS", production, "", .fresh)
	Do $$$AssertEquals($ListLength(fresh), 0, "and none is fresh with no previous run")
	Do ..Done(a, incident, "suspend_item", "C", 0)
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Fix.Run).Suspended("ZZNS", production)), "A", "a suspend that changed nothing (C was already disabled) does not name C")
	Do ..Step(host, production, 1, "running", ["A", "B"])
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 1, "A, which OcuTalon suspended, sends no Item; B sends one")
	If items.%Size() = 1 Do $$$AssertEquals(..Slot(items.%Get(0).slots, "itemName"), "B", "for B")
	Do $$$AssertEquals(..Row(ref).Reported, "{""stopped"":0,""disabled"":[""A"",""B""],""ours"":[""A""]}", "Reported holds both and records A as ours")
	Do ..Done(a, incident, "resume_item", "A")
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Fix.Run).Suspended("ZZNS", production)), 0, "a resume that changed A ends the suspension")
	Do ..Step(host, production, 2, "running", ["B"])
	Do $$$AssertEquals(..Items().%Size(), 1, "A resumed sends nothing")
	Do ..Step(host, production, 3, "running", ["A", "B"])
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 2, "and A disabled by anyone else afterwards is one Item")
	If items.%Size() = 2 Do $$$AssertEquals(..Slot(items.%Get(1).slots, "itemName"), "A", "for A")
}

/// Story 23.9 (AC5, AC6; Integration): Fix.Run Suspended gives holders (each item that is suspended now, with the incident of the run that suspended it) and released (each item whose
/// current suspension is a run of a closed incident, with that run's EndedAt). A released item is not in names or fresh. The newest changing run decides: a resume ends the suspension,
/// a later suspend by another incident moves the holder, a run that changed nothing does neither. Holds is 1 for the holder of an item only.
Method TestSuspendedHoldersAndReleased()
{
	Set a = ..Owner("holders")
	Set production = "Zz.Holders"
	Set first = ##class(OcuTalon.Test.Data.Fixture).Incident(a, , "ZZNS", production, {"State": "resolved", "OpenVariant": ""})
	Set second = ##class(OcuTalon.Test.Data.Fixture).Incident(a, , "ZZNS", production, {"State": "resolved", "OpenVariant": ""})
	Set other = ##class(OcuTalon.Test.Data.Fixture).Incident(a, , "ZZNS", "Zz.HoldersOther", {"State": "resolved", "OpenVariant": ""})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_first_","_second_","_other
	Do ..Done(a, first, "suspend_item", "A")
	Do ..Done(a, first, "suspend_item", "B")
	Do ..Done(a, second, "suspend_item", "C", 0)
	Set names = ##class(OcuTalon.Fix.Run).Suspended("ZZNS", production, "2000-01-01T00:00:00Z", .fresh, .holders, .released)
	Do $$$AssertEquals($ListToString(names)_"|"_$ListToString(fresh), "A,B|A,B", "two items suspended for a resolved incident are named and fresh")
	Do $$$AssertEquals(holders.%ToJSON(), "{""A"":"""_first_""",""B"":"""_first_"""}", "and the incident holds both (a run that changed nothing holds nothing)")
	Do $$$AssertEquals(released.%ToJSON(), "{}", "and nothing is released")
	Set firstRow = ##class(OcuTalon.Data.Incident).RefIndexOpen(first)
	Set secondRow = ##class(OcuTalon.Data.Incident).RefIndexOpen(second)
	Set otherRow = ##class(OcuTalon.Data.Incident).RefIndexOpen(other)
	Do $$$AssertEquals(##class(OcuTalon.Fix.Run).Holds(firstRow)_"|"_##class(OcuTalon.Fix.Run).Holds(secondRow)_"|"_##class(OcuTalon.Fix.Run).Holds(otherRow), "1|0|0", "Holds is 1 for the holder only, and 0 for an incident of another production")
	// a suspend of A by the second incident moves the hold
	Do ..Done(a, second, "suspend_item", "A")
	Do ##class(OcuTalon.Fix.Run).Suspended("ZZNS", production, , , .holders)
	Do $$$AssertEquals(holders.%ToJSON(), "{""A"":"""_second_""",""B"":"""_first_"""}", "a later suspend of A by the second incident moves its hold to that incident (the newest run decides)")
	Do $$$AssertEquals(##class(OcuTalon.Fix.Run).Holds(firstRow)_"|"_##class(OcuTalon.Fix.Run).Holds(secondRow), "1|1", "the first still holds B, the second holds A")
	// a resume of A (through the first incident) ends the suspension
	Do ..Done(a, first, "resume_item", "A")
	Do ##class(OcuTalon.Fix.Run).Suspended("ZZNS", production, , , .holders)
	Do $$$AssertEquals(holders.%ToJSON(), "{""B"":"""_first_"""}", "a resume that changed A ends it: A has no holder")
	Do $$$AssertEquals(##class(OcuTalon.Fix.Run).Holds(secondRow), 0, "and the second incident holds nothing")
	// a resume that changed nothing ends nothing
	Do ..Done(a, second, "resume_item", "B", 0)
	Do ##class(OcuTalon.Fix.Run).Suspended("ZZNS", production, , , .holders)
	Do $$$AssertEquals(holders.%ToJSON(), "{""B"":"""_first_"""}", "a resume that changed nothing leaves the hold")
	// the first incident closes: B is released, at the end of its suspending run
	Set firstRow.State = "closed"
	Do $$$AssertStatusOK(firstRow.%Save(), "the first incident is closed")
	Set names = ##class(OcuTalon.Fix.Run).Suspended("ZZNS", production, "2000-01-01T00:00:00Z", .fresh, .holders, .released)
	Set ended = ..EndOfSuspend(first, "B")
	Do $$$AssertTrue(ended '= "", "the suspending run of B has an EndedAt")
	Do $$$AssertEquals($ListLength(names)_"|"_$ListLength(fresh)_"|"_released.%ToJSON(), "0|0|{""B"":"""_ended_"""}", "B, whose incident is closed, is released with its run's EndedAt and leaves names and fresh")
	Do $$$AssertEquals(holders.%ToJSON(), "{""B"":"""_first_"""}", "and the holder is still told")
}

/// Story 23.9 (AC5): the pure rule of Findings for released. An item that suspended does not list, that is in the previous ours and disabled, and that released lists, is one finding with the
/// suspend's time, and it leaves ours; every other name follows the plain rule.
Method TestReleasedFindings()
{
	Set sighted = "{""stopped"":0,""disabled"":[""A"",""B""],""ours"":[""A""]}"
	Set released = {"A": "2030-01-01T10:00:00Z", "B": "2030-01-01T11:00:00Z"}
	Set found = ##class(OcuTalon.Checks.Process).Findings(sighted, "running", ["A", "B"], .reported, "", "", released)
	Do $$$AssertEquals(found.%ToJSON()_"|"_reported, "[{""kind"":""disabled"",""item"":""A"",""at"":""2030-01-01T10:00:00Z""}]|{""stopped"":0,""disabled"":[""A"",""B""]}", "A, in the previous ours and released, is one finding at the suspend's time and leaves ours; B, which was never ours, is not reported")
	Set found = ##class(OcuTalon.Checks.Process).Findings(reported, "running", ["A", "B"], .reported, "", "", released)
	Do $$$AssertEquals(found.%Size()_"|"_reported, "0|{""stopped"":0,""disabled"":[""A"",""B""]}", "and the next run reports nothing")
	Set found = ##class(OcuTalon.Checks.Process).Findings(sighted, "running", ["B"], .reported, "", "", released)
	Do $$$AssertEquals(found.%Size()_"|"_reported, "0|{""stopped"":0,""disabled"":[""B""]}", "an item that is enabled now sends nothing and leaves ours")
	Set found = ##class(OcuTalon.Checks.Process).Findings(sighted, "running", ["A", "B"], .reported, $ListBuild("A"), "", {})
	Do $$$AssertEquals(found.%Size()_"|"_reported, "0|{""stopped"":0,""disabled"":[""A"",""B""],""ours"":[""A""]}", "with an empty released the rule is unchanged")
	Set found = ##class(OcuTalon.Checks.Process).Findings("", "running", ["A"], .reported, "", "", released)
	Do $$$AssertEquals(found.%Size()_"|"_reported, "0|{""stopped"":0,""disabled"":[""A""]}", "a baseline reports nothing")
	Set found = ##class(OcuTalon.Checks.Process).Findings(sighted, "timeout", ["A"], .reported, "", "", released)
	Do $$$AssertEquals(found.%Size()_"|"_reported, "0|"_sighted, "a state that was not read reports nothing and keeps Reported")
}

/// Story 23.9 (AC5; DW-1068, second half; Integration): an item that OcuTalon suspended is not reported while its incident is not closed; after the user dismisses the incident the next run sends
/// exactly one Item for it, with the suspend's end as the time, and takes it out of ours; the run after that sends none. An item that a resume enabled sends none.
Method TestDismissedSuspendIsReportedOnce()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("dismissed")
	Set production = "Zz.Dismissed"
	Set ref = ..Watch(a, production)
	Do ..Step(host, production, 0, "running")
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(a, , "ZZNS", production, {"State": "resolved", "OpenVariant": ""})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_incident
	Do ..Done(a, incident, "suspend_item", "A", 1, "2030-04-30T08:15:42Z")
	Do ..Done(a, incident, "suspend_item", "B")
	Do ..Step(host, production, 1, "running", ["A", "B"])
	Do $$$AssertEquals(..Items().%Size(), 0, "A and B, suspended by OcuTalon for a resolved incident, send nothing")
	Do $$$AssertEquals(..Row(ref).Reported, "{""stopped"":0,""disabled"":[""A"",""B""],""ours"":[""A"",""B""]}", "and both are ours")
	Do ..Done(a, incident, "resume_item", "B")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.State = "closed"
	Do $$$AssertStatusOK(row.%Save(), "the user dismisses the incident")
	Set ended = ..EndOfSuspend(incident, "A")
	Do $$$AssertEquals(ended, "2030-04-30T08:15:42Z", "the suspend of A ended at a time of its own, not the run's")
	Do ..Step(host, production, 2, "running", ["A"])
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 1, "the next run sends one Item, for A (B was resumed and sends none)")
	If items.%Size() = 1 {
		Do $$$AssertEquals(..Slot(items.%Get(0).slots, "itemName"), "A", "for A")
		Do $$$AssertEquals(..Slot(items.%Get(0).slots, "time"), ended, "with the end of the suspend as the time")
		Do $$$AssertEquals(items.%Get(0).catalogKey, "watch.itemDisabled", "under watch.itemDisabled")
	}
	Do $$$AssertEquals(..Row(ref).Reported, "{""stopped"":0,""disabled"":[""A""]}", "A has left ours")
	Do ..Step(host, production, 3, "running", ["A"])
	Do $$$AssertEquals(..Items().%Size(), 1, "the run after that sends none")
}

/// The EndedAt of the incident's done suspend_item run for the item (the first one), "" when there is none.
ClassMethod EndOfSuspend(incident As %String, item As %String) As %String
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT r.EndedAt, a.FixParameters FROM OcuTalon_Data.FixRun r JOIN OcuTalon_Bridge_Data.ApprovalRequest a ON a.Ref = r.ApprovalRef WHERE r.IncidentRef = ? AND a.FixKind = 'suspend_item' ORDER BY r.ID", incident)
	Set ended = ""
	While rs.%Next() {
		If {}.%FromJSON(rs.%GetData(2)).item = item {
			Set ended = rs.%GetData(1)
			Quit
		}
	}
	Quit ended
}

/// A done request of the kind for the item of the incident, with a run that changed it (completed 1) or skipped it (completed 0); the run ends at endedAt when that is given, else now.
Method Done(owner As %String, incident As %String, kind As %String, item As %String, completed As %Integer = 1, endedAt As %String = "") [ Private ]
{
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, "done", , {"FixKind": (kind), "FixParameters": ({"item": (item)}.%ToJSON()), "FixTargets": "1"})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_request
	Set fields = {"Total": 1, "Completed": (completed), "Skipped": (1 - completed)}
	If endedAt '= "" Do fields.%Set("EndedAt", endedAt)
	Do ##class(OcuTalon.Test.Data.Fixture).FixRun(incident, request, fields)
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

/// Each Item's key and slots render, through the catalog at a fixed now, to the text of the UX, without " ET" on a local install and with it on the online demo (DW-469): a stop
/// with IRIS's stop time, a disabled item, and a stop with no readable stop time, which takes the time of the run.
Method TestFindingsRender()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("render")
	Set production = "Zz.Render"
	Set ref = ..Watch(a, production)
	Do ..Step(host, production, 0, "running")
	Do ..Step(host, production, 1, "stopped", ["Zz.Door"], "2030-06-01 12:01:20.000")
	Do ..Step(host, production, 2, "running")
	Do ..Step(host, production, 3, "stopped")
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 3, "a stop, a disabled item and a stop with no stop time")
	If items.%Size() '= 3 Quit
	Set now = "2030-06-01T12:05:00Z"
	Set why = $Char(10)_"Why now: you asked me to watch the Zz "_production_" production."
	Do $$$AssertEquals(..Slot(items.%Get(0).slots, "time"), "2030-06-01T12:01:20Z", "the first stop has IRIS's stop time")
	Set runTime = ..Slot(items.%Get(2).slots, "time")
	Do $$$AssertTrue(runTime ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "and the stop with none has the time of its run, a UTC stamp: "_runTime)
	Do $$$AssertTrue(runTime '= "2030-06-01T12:01:20Z", "which is not the first stop's")
	For online = 0, 1 {
		Set suffix = $Select(online: " ET", 1: "")
		Set label = $Select(online: "on the online demo", 1: "on a local install")
		For n = 0, 2 {
			Set clock = ##class(OcuTalon.Data.Time).ForMessage(..Slot(items.%Get(n).slots, "time"), now)
			Set joiner = $Select(clock ? 2N1":"2N: " at ", 1: " on ")
			Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).RenderAt(items.%Get(n).catalogKey, items.%Get(n).slots, "web", now, online), "The Zz "_production_" production stopped"_joiner_clock_suffix_"."_why, "the stop "_$Select(n = 0: "with a stop time", 1: "with none")_" renders to the UX text "_label)
		}
		Set clock = ##class(OcuTalon.Data.Time).ForMessage(..Slot(items.%Get(1).slots, "time"), now)
		Set joiner = $Select(clock ? 2N1":"2N: " at ", 1: " on ")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).RenderAt(items.%Get(1).catalogKey, items.%Get(1).slots, "web", now, online), "The Zz.Door in the Zz "_production_" production was disabled"_joiner_clock_suffix_"."_why, "and so does the disabled item "_label_" (a time on another day reads 'on {date} at {time}')")
	}
}

/// (QA) Row 7 with row 8: a row with nothing reported whose first run did not read the production keeps Reported empty, so that its first run that does read is
/// still the baseline (it sends nothing, even for a stopped production), and only a later change is reported.
Method TestAnUnreadFirstRunLeavesTheBaselineForTheFirstRead()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("lateBaseline")
	Set production = "Zz.LateBaseline"
	Set ref = ..Watch(a, production)
	Do ..Feed(production, "unreadable", "")
	Do ..Tick(host, ..At(0))
	Do $$$AssertEquals(..Row(ref).Result_"|"_..Row(ref).Reported_"|"_..Items().%Size(), "not_checked||0", "the first run could not read: nothing reported, nothing sent")
	Do ..Step(host, production, 1, "stopped", ["A"])
	Do $$$AssertEquals(..Items().%Size()_"|"_..Row(ref).Reported, "0|{""stopped"":1,""disabled"":[""A""]}", "the first run that reads is the baseline: no Item, the state recorded")
	Do ..Step(host, production, 2, "stopped", ["A"])
	Do $$$AssertEquals(..Items().%Size(), 0, "and a run that finds the same state sends nothing")
	Do ..Step(host, production, 3, "stopped", ["A", "B"])
	Do $$$AssertEquals(..Items().%Size()_"|"_..Slot(..Items().%Get(0).slots, "itemName"), "1|B", "only the change after the baseline is reported")
}

/// (QA) Reported is the row's own: a run records its row by Ref, so that a second watch on the same production, whose Tick did not run, keeps what it reported;
/// each watch's Item goes to its own session with its own trace.
Method TestEachRowRemembersItsOwnReport()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set one = ..Owner("rowOne")
	Set two = ..Owner("rowTwo")
	Set production = "Zz.OwnReport"
	Set refOne = ..Watch(one, production)
	Set refTwo = ..Watch(two, production)
	Do ..Step(host, production, 0, "running")
	Do ..Step(host, production, 1, "stopped")
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 2, "both watches report the stop")
	If items.%Size() = 2 {
		Set owners = $ListBuild(items.%Get(0).sessionRef, items.%Get(1).sessionRef)
		Do $$$AssertTrue($ListFind(owners, one) && $ListFind(owners, two), "each to its own session")
		For i = 0, 1 {
			Do $$$AssertEquals(items.%Get(i).superSession, ..TraceOf(items.%Get(i).sessionRef), "with the trace of that session")
		}
	}
	// only the first watch runs while the production runs again; the second keeps its report
	Set ..Checks = refOne
	Do ..Step(host, production, 2, "running")
	Do $$$AssertEquals(..Row(refOne).Reported_"|"_..Row(refTwo).Reported, "{""stopped"":0,""disabled"":[]}|{""stopped"":1,""disabled"":[]}", "the run recorded its own row only")
	Set ..Checks = refOne_","_refTwo
	Do ..Step(host, production, 3, "stopped")
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 3, "the next stop is new for the watch that saw it end, and not for the other")
	If items.%Size() = 3 Do $$$AssertEquals(items.%Get(2).sessionRef, one, "it goes to the first watch's session")
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

Method TestTickRunsTheBeatsLast()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("beatlast")
	Set long = ##class(OcuTalon.Bridge.Time).PlusSeconds(..#TICK, -960)
	Set quiet = ..Incident(a, "resolved", "Zz.BeatLast", {"LastAt": (long)})
	Set production = "Zz.BeatLastDue"
	Set ref = ..Watch(a, production)
	Do ..Feed(production, "read", "running")
	Set host.QuietAt = ..#TICK
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(..Row(ref).Result, "passed", "the due row still runs")
	Do $$$AssertEquals($Select($IsObject(host.Beats): host.Beats.%Size(), 1: 0), 1, "RunDue is called once")
	If $IsObject(host.Beats) && (host.Beats.%Size() = 1) {
		Set beat = host.Beats.%Get(0)
		Do $$$AssertEquals(beat.tickAt, ..#TICK, "with the Tick's time")
		Do $$$AssertEquals(beat.reads, 1, "after the due row's read")
		Do $$$AssertEquals(beat.sends, 1, "and after every send (the quiet sweep's)")
	}
	Do $$$AssertEquals(host.Order.%Size(), 1, "the beat adds nothing to Order")
	Do $$$AssertEquals(..Reads(), production, "and the row was read once")
}

Method TestBeatsThatFailAreLogged()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("beatfail")
	Set production = "Zz.BeatFailDue"
	Set ref = ..Watch(a, production)
	Do ..Feed(production, "read", "running")

	// RunDue throws
	Set marker = "zzchk"_..Number_" beat refused"
	Set host.BeatThrows = marker
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(..Beaten(marker, .text), 1, "a RunDue that throws logs one warning that holds the marker")
	Do $$$AssertEquals(..Row(ref).Result, "passed", "the due row ran before it")

	// RunDue answers an error status
	Set host.BeatThrows = ""
	Set host.BeatError = marker
	Do ..Tick(host, ..At(1))
	Do $$$AssertEquals(..Beaten(marker, .text), 2, "a RunDue that answers an error status logs one more")
	Do $$$AssertEquals(host.Beats.%Size(), 2, "RunDue was called on each Tick")
}

Method TestBeatNow()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("beatnow")
	Set production = "Zz.BeatNowDue"
	Set ref = ..Watch(a, production)
	Do ..Feed(production, "read", "running")
	Set host.BeatNowOutcome = "empty"
	Set request = ##class(OcuTalon.Checks.Msg.BeatNow).%New()
	Set request.SessionRef = a
	Set request.RequestedAt = ..#TICK
	Set response = "x"
	Set sc = host.OnRequest(request, .response)
	Do $$$AssertStatusOK(sc, "a BeatNow is answered OK")
	Do $$$AssertTrue($IsObject(response) && response.%IsA("OcuTalon.Msg.CommandResult"), "with a CommandResult")
	If $IsObject(response) Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref_"|"_response.Data_"|"_response.Message, "0|empty|||", "that holds the outcome of RunNow and nothing else")
	Do $$$AssertEquals($Select($IsObject(host.BeatNows): host.BeatNows.%Size(), 1: 0), 1, "RunNow is called once")
	If $IsObject(host.BeatNows) && (host.BeatNows.%Size() = 1) Do $$$AssertEquals(host.BeatNows.%Get(0).sessionRef_"|"_host.BeatNows.%Get(0).now, a_"|"_..#TICK, "with the request's SessionRef and time")
	Do $$$AssertEquals($Select($IsObject(host.Beats): host.Beats.%Size(), 1: 0), 0, "RunDue is not called")
	Do $$$AssertEquals($Select($IsObject(host.Order): host.Order.%Size(), 1: 0), 0, "nothing is sent")
	Do $$$AssertEquals(..Reads(), "", "and no row is read")

	// a request with no time is run at the current time
	Set request.RequestedAt = "not a stamp"
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(host.OnRequest(request, .response), "a BeatNow with a bad time is answered OK")
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	If host.BeatNows.%Size() = 2 {
		Set given = host.BeatNows.%Get(1).now
		Do $$$AssertTrue(given ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "RunNow gets a UTC stamp: "_given)
		Do $$$AssertTrue('(before ] given) && '(given ] after), "that is the current time: "_given)
	}

	// RunNow throws
	Set request.RequestedAt = ..#TICK
	Set marker = "zzchk"_..Number_" beatnow refused"
	Set host.BeatNowThrows = marker
	Set sc = host.OnRequest(request, .response)
	Do $$$AssertStatusOK(sc, "a RunNow that throws still answers OK")
	Do $$$AssertEquals(..Beaten("zzchk"_..Number_" beatnow ", .text, "BeatNow"), 1, "and logs one warning")
	Do $$$AssertTrue(text [ marker, "which holds the marker: "_text)
	Do $$$AssertNotTrue(text [ a,"and not the SessionRef")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|failed", "the outcome is failed")

	// RunNow answers an error status
	Set host.BeatNowThrows = ""
	Set marker = "zzchk"_..Number_" beatnow failed"
	Set host.BeatNowError = marker
	Set sc = host.OnRequest(request, .response)
	Do $$$AssertStatusOK(sc, "a RunNow that answers an error status still answers OK")
	Do $$$AssertEquals(..Beaten("zzchk"_..Number_" beatnow ", .text, "BeatNow"), 2, "and logs one more warning")
	Do $$$AssertTrue(text [ marker, "which holds the marker: "_text)
	Do $$$AssertNotTrue(text [ a,"and not the SessionRef")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|failed", "the outcome is failed")
}

Method TestTickSendsTheBeats()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("beatsend")
	Set production = "Zz.BeatSendDue"
	Set ref = ..Watch(a, production)
	Do ..Feed(production, "read", "running")
	Do ..Beating(a, "check the orders")
	Set host.BeatSessions = a
	Do ..Tick(host, ..#TICK)
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 1, "the Tick sends the one beat's Item")
	If items.%Size() = 1 {
		Set item = items.%Get(0)
		Do $$$AssertEquals(item.channel_"|"_item.provenance_"|"_item.sessionRef_"|"_item.subject, "heartbeat|untrusted|"_a_"|Heartbeat check-in", "an untrusted Item of the heartbeat channel for the person")
		Set local = ##class(OcuTalon.Data.Time).ToLocal(..#TICK)
		Set head = $Piece(item.text, $Char(10), 1, 3)
		Do $$$AssertEquals(head, "check the orders"_$Char(10, 10)_"Status at "_$Extract(local, 1, 10)_" "_$Extract(local, 12, 16)_" (built by OcuTalon):", "whose text is the checklist, a blank line and the status line at the Tick's local time")
		Do $$$AssertEquals(item.sessionId, "", "in a trace session of its own: the process's session is cleared for the send")
		Do $$$AssertEquals(item.superSession, ..TraceOf(a), "with the TraceRef of the person's session as SuperSession")
		Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(a)
		Do $$$AssertTrue($IsObject(row) && (row.LastItemId = item.itemId), "the row was saved with the Item's ItemId")
	}
	Do $$$AssertEquals(host.%SessionId_"|"_host.%SuperSession, ..#SESSIONID_"|", "the process's own session and SuperSession are put back")
	Do $$$AssertEquals($Select($IsObject(host.Beats): host.Beats.%Size(), 1: 0), 1, "RunDue is called once")
	If $IsObject(host.Beats) && (host.Beats.%Size() = 1) Do $$$AssertEquals(host.Beats.%Get(0).reads, 1, "after the due row's read")
	Do $$$AssertEquals(..Row(ref).Result, "passed", "the due row still runs")
	Do $$$AssertEquals(host.Order.%Size(), 1, "and the Item is the only send")
}

Method TestBeatSendFailureIsLogged()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("beatfailsend")
	Set text = "zzchk"_..Number_" beat text"
	Do ..Beating(a, text)
	Set host.BeatSessions = a
	Do $ClassMethod(..#PROBE, "FailFindings", text)
	Do ..Tick(host, ..#TICK)
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 1, "the send was tried")
	If items.%Size() '= 1 Quit
	Set ..BeatItems = items.%Get(0).itemId
	Do $$$AssertEquals(..Warnings("Tick", $Parameter(..#PROBE, "LOGBEATSEND")_..BeatItems, .line), 1, "a send that fails logs one warning that names the ItemId")
	Do $$$AssertTrue(line [ "is refused", "and holds the error text: "_line)
	Do $$$AssertNotTrue((line [ a) || (line [ $ZConvert(a, "U")), "but not the SessionRef that the error names, in any case: "_line)
}

Method TestTickPublishesTheBeats()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set tail = ##class(OcuTalon.Bridge.Time).PlusSeconds(..#TICK, 1800)
	Set a = ..Owner("pubbeat")
	Set b = ..Owner("pubskip")
	Set c = ..Owner("pubquiet")
	Set d = ..Owner("pubresult")
	Set e = ..Owner("pubempty")
	Do ..Beating(a, "check the orders zzsecret"_..Number)
	Do ..Beating(b, "check the orders")
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(b)
	Set row.BackoffUntil = ##class(OcuTalon.Bridge.Time).PlusSeconds(..#TICK, 600)
	Do $$$AssertStatusOK(row.%Save(), "B is in a back-off")
	Do ..Beating(e, "")
	Do ..Beating(c, "check the orders")
	Do ##class(OcuTalon.Data.Setting).Set($ClassMethod("OcuTalon.Checks.Beat", "SettingKey", c, "on"), 0)
	Do ..Beating(d, "check the queue")
	Set host.BeatSessions = a_","_b_","_c_","_d_","_e
	Do ..Tick(host, ..#TICK)

	// a beat that runs
	Set events = ..BeatEvents(a)
	Do $$$AssertEquals(events.%Size(), 1, "a beat that runs publishes one event on the person's stream")
	If events.%Size() = 1 {
		Do $$$AssertEquals(events.%Get(0).payload.%ToJSON(), ..BeatViewOf(a), "which is FromRow of the row and the settings")
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.lastBeatAt_"|"_payload.nextDueAt_"|"_payload.%IsDefined("lastOutcome")_"|"_payload.on_"|"_payload.interval, ..#TICK_"|"_tail_"|0|1|30", "with the beat's time, the schedule, no result, on and the interval")
		Do $$$AssertTrue((events.%Get(0).payload.%ToJSON() '[ a) && (events.%Get(0).payload.%ToJSON() '[ "zzsecret"), "and neither the SessionRef nor the checklist")
	}

	// a skip
	Set events = ..BeatEvents(b)
	Do $$$AssertEquals(events.%Size(), 1, "a skip publishes one event")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.lastSkipAt_"|"_payload.lastSkipReason_"|"_payload.nextDueAt_"|"_payload.%IsDefined("lastBeatAt"), ..#TICK_"|backoff|"_tail_"|0", "with the skip's time and reason and the moved schedule")
		Do $$$AssertEquals(payload.%ToJSON(), ..BeatViewOf(b), "and it is FromRow of the row")
	}

	// a skip for an empty checklist: saved, and no event
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(e)
	Do $$$AssertEquals(row.LastSkipAt_"|"_row.LastSkipReason_"|"_row.NextDueAt, ..#TICK_"|empty|"_tail, "a Tick's skip for an empty checklist is saved with its reason and the moved schedule")
	Do $$$AssertEquals(..BeatEvents(e).%Size(), 0, "and publishes no event")

	// nothing committed: an off person with nothing pending
	Do $$$AssertEquals(..BeatEvents(c).%Size(), 0, "an off person with nothing pending publishes nothing")

	// a person whose beat is pending, then its decision is recorded by the next Tick (a fallback)
	Set itemD = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(d).LastItemId
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(d, "decide", , {"Outcome": "tellnow", "Fallback": 1, "CostUSD": 0.0025, "TraceSessionId": 4242, "ItemId": (itemD)})
	Set ..Refs = ..Refs_","_decision
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(decision, d, {"ItemId": (itemD), "Kind": "decide", "Channel": "heartbeat", "CostUSD": 0.0025})
	Do ..Tick(host, ..#NEXT)
	Set events = ..BeatEvents(d)
	Do $$$AssertEquals(events.%Size(), 2, "the next Tick records the result and publishes one more event")
	If events.%Size() = 2 {
		Set payload = events.%Get(1).payload
		Do $$$AssertEquals(payload.lastOutcome_"|"_payload.lastFallback_"|"_payload.lastCostUSD_"|"_payload.traceHeaderId_"|"_payload.traceNamespace, "tellnow|1|.0025|4242|"_$Namespace, "with the outcome, the fallback, the cost and the decision's trace")
		Do $$$AssertEquals(payload.backoffUntil, ##class(OcuTalon.Bridge.Time).PlusSeconds(..#NEXT, 14400), "and the back-off a fallback sets")
		Do $$$AssertEquals(payload.%ToJSON(), ..BeatViewOf(d), "and it is FromRow of the row")
	}
	Do $$$AssertEquals(..BeatEvents(a).%Size()_"|"_..BeatEvents(b).%Size()_"|"_..BeatEvents(c).%Size()_"|"_..BeatEvents(e).%Size(), "1|1|0|0", "the others, not due, publish nothing more")
	Do ..Tick(host, ..#NEXT)
	Do $$$AssertEquals(..BeatEvents(d).%Size(), 2, "and a Tick that commits nothing publishes nothing")
}

/// A pending ignore and the beat that is due at the same Tick: two commits, so two events, the recorded ignore first.
Method TestTickPublishesEachCommitInOrder()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("pubtwo")
	Do ..Beating(a, "check the orders")
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(a)
	Set row.LastItemId = "zzitem"_..Number
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(a, "decide", , {"Outcome": "ignore", "Summary": "Heartbeat check-in", "ItemId": (row.LastItemId)})
	Set ..Refs = ..Refs_","_decision
	Do ##class(OcuTalon.Checks.Beat).Snapshot(a, ..#TICK, .whole)
	Set row.LastSnapshotKey = ##class(OcuTalon.Checks.Beat).Key(whole)
	Do $$$AssertStatusOK(row.%Save(), "the pending beat is saved with the key of the snapshot")
	Set host.BeatSessions = a
	Do ..Tick(host, ..#TICK)
	Set events = ..BeatEvents(a)
	Do $$$AssertEquals(events.%Size(), 2, "two commits publish two events")
	If events.%Size() = 2 {
		Set first = events.%Get(0).payload
		Set second = events.%Get(1).payload
		Do $$$AssertEquals(first.lastOutcome_"|"_first.%IsDefined("lastSkipAt"), "ignore|0", "the first holds the recorded ignore and no skip")
		Do $$$AssertEquals(second.lastOutcome_"|"_second.lastSkipReason_"|"_second.lastSkipAt, "ignore|unchanged|"_..#TICK, "the second holds the unchanged skip")
		Do $$$AssertEquals(second.%ToJSON(), ..BeatViewOf(a), "and is FromRow of the row")
	}
}

Method TestBeatNowPublishes()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("pubnow")
	Set b = ..Owner("pubnowheld")
	Do ..Beating(a, "check the orders")
	Do ..Beating(b, "")
	Set host.BeatSessions = a_","_b
	Set response = ..BeatNowOf(host, a, ..#TICK)
	Do $$$AssertEquals(response.Outcome, "sent", "the run now is sent")
	Set events = ..BeatEvents(a)
	Do $$$AssertEquals(events.%Size(), 1, "a run now that is sent publishes one event")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.lastRunNowAt_"|"_payload.lastBeatAt, ..#TICK_"|"_..#TICK, "with lastRunNowAt and the beat's time")
		Do $$$AssertEquals(payload.%ToJSON(), ..BeatViewOf(a), "and it is FromRow of the row")
		Do $$$AssertTrue(payload.%ToJSON() '[ a, "without the SessionRef")
	}

	// held
	Set response = ..BeatNowOf(host, b, ..#TICK)
	Do $$$AssertEquals(response.Outcome, "empty", "a run now with an empty checklist is held")
	Set events = ..BeatEvents(b)
	Do $$$AssertEquals(events.%Size(), 1, "and publishes one event")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.lastRunNowAt_"|"_payload.%IsDefined("lastSkipAt"), ..#TICK_"|0", "with lastRunNowAt and no skip")
		Do $$$AssertEquals(payload.%ToJSON(), ..BeatViewOf(b), "and it is FromRow of the row")
	}

	// the cooldown
	Set soon = ##class(OcuTalon.Bridge.Time).PlusSeconds(..#TICK, 30)
	Set response = ..BeatNowOf(host, a, soon)
	Do $$$AssertEquals(response.Outcome, "cooldown", "a second run now within two minutes is a cooldown")
	Do $$$AssertEquals(..BeatEvents(a).%Size(), 1, "and publishes nothing")

	// the cooldown with a pending decision: only the result
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(a, "decide", , {"Outcome": "ignore", "ItemId": (##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(a).LastItemId)})
	Set ..Refs = ..Refs_","_decision
	Set response = ..BeatNowOf(host, a, soon)
	Do $$$AssertEquals(response.Outcome, "cooldown", "a run now on the cooldown with a pending decision is still a cooldown")
	Set events = ..BeatEvents(a)
	Do $$$AssertEquals(events.%Size(), 2, "and publishes the recorded result")
	If events.%Size() = 2 {
		Set payload = events.%Get(1).payload
		Do $$$AssertEquals(payload.lastOutcome_"|"_payload.lastRunNowAt, "ignore|"_..#TICK, "with lastRunNowAt unchanged")
	}
}

Method TestBeatPublishFailureIsLogged()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("pubfailerr")
	Set b = ..Owner("pubfailthrow")
	Set c = ..Owner("pubfailok")
	Do ..Beating(a, "check the orders")
	Do ..Beating(b, "check the orders")
	Do ..Beating(c, "check the orders")
	Set host.BeatSessions = a_","_b_","_c
	Set host.BeatPublishError = a
	Set host.BeatPublishThrows = b
	Set secret = "sk-"_"ant-api03-QaSecretQaSecretQaSecret123456"
	Set host.BeatPublishSecret = secret
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(..Items().%Size(), 3, "the Tick still sends the three Items")
	Set after = ""
	Set iterator = host.BeatPublishedAfter.%GetIterator()
	While iterator.%GetNext(, .kept) {
		Set after = after_$Select(after = "": "", 1: ",")_kept
	}
	Do $$$AssertEquals(after, "3,3,3", "and publishes only after all three are sent")
	Do $$$AssertEquals(..BeatEvents(a).%Size()_"|"_..BeatEvents(b).%Size()_"|"_..BeatEvents(c).%Size(), "0|0|1", "and the third person's event is still published")
	Do $$$AssertEquals(..BeatPublishWarnings(.line), 2, "a publish that fails and one that throws each log one warning")
	Do $$$AssertTrue(line [ "is refused", "which holds the error text: "_line)

	// a BeatNow whose publish fails still answers sent
	Set d = ..Owner("pubfailnow")
	Do ..Beating(d, "check the orders")
	Set host.BeatSessions = host.BeatSessions_","_d
	Set host.BeatPublishError = d
	Set response = ..BeatNowOf(host, d, ..At(1))
	Do $$$AssertEquals(response.Outcome, "sent", "a BeatNow whose publish fails still answers sent")
	Do $$$AssertEquals(host.BeatPublishedAfter.%Get(host.BeatPublishedAfter.%Size() - 1)_"|"_..Items().%Size(), "4|4", "and publishes only after its Item is sent")
	Do $$$AssertEquals(..BeatPublishWarnings(.line), 3, "and logs one more warning")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = 'AnnounceBeat' AND Text %STARTSWITH ? AND Text [ ? ORDER BY ID", ..LogMark, $Parameter(..#PROBE, "LOGBEATPUBLISH"), ..#BEATPUBLISHREFUSED)
	While result.%Next() {
		Set text = result.%Get("Text")
		Do $$$AssertNotTrue((text [ a) || (text [ $ZConvert(a, "U")) || (text [ b) || (text [ $ZConvert(b, "U")) || (text [ d) || (text [ $ZConvert(d, "U")), "no warning names a SessionRef, in any case: "_text)
		Do $$$AssertNotTrue(text [ "QaSecret", "and none holds the secret: "_text)
	}
}

/// The views that RunDue made before it answered an error status are still published.
Method TestBeatPublishesWhatRunDueCommittedBeforeAnError()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("pubaftererr")
	Do ..Beating(a, "check the orders")
	Set host.BeatSessions = a
	Set host.BeatError = "zzchk"_..Number_" beat refused"
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(..BeatEvents(a).%Size(), 1, "a Tick whose RunDue answers an error status still publishes the committed beat")
}

/// Story 39.7 (QA; AC 2): every heartbeat event that a real Tick or BeatNow publishes, whichever way its row was committed (a recorded ignore and the unchanged skip of
/// one Tick, a beat and its recorded fallback, a run now that is sent, a run now that is held), holds none of the SessionRef (in any case), the checklist,
/// the Item's Id, the decision's Ref and the two snapshot keys that the row holds then, and no key outside the view's. TestTickPublishesTheBeats and
/// TestBeatNowPublishes look for the SessionRef and the checklist in a beat's event only.
Method TestPublishedEventsHoldNoRefChecklistOrKey()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set checklist = "check the orders zzleak"_..Number
	Set a = ..Owner("leaktwo")
	Set f = ..Owner("leakfall")
	Set n = ..Owner("leaknow")
	Set h = ..Owner("leakheld")
	Do ..Beating(a, checklist)
	Do ..Beating(f, checklist)
	Do ..Beating(n, checklist)
	Do ..Beating(h, "")

	// a: a pending ignore and a due beat at one Tick (two commits)
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(a)
	Set row.LastItemId = "zzleakitem"_..Number
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(a, "decide", , {"Outcome": "ignore", "Summary": "Heartbeat check-in", "ItemId": (row.LastItemId)})
	Set ..Refs = ..Refs_","_decision
	Do ##class(OcuTalon.Checks.Beat).Snapshot(a, ..#TICK, .whole)
	Set row.LastSnapshotKey = ##class(OcuTalon.Checks.Beat).Key(whole)
	Do $$$AssertStatusOK(row.%Save(), "A's pending beat is saved with the key of the snapshot")
	Set host.BeatSessions = a_","_f_","_n_","_h
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(..NoLeaks(a, checklist, 6), 2, "A's recorded ignore and unchanged skip hold the SessionRef, the checklist, the Item's Id, the decision's Ref and both keys of the row: none")

	// f: its beat's fallback is recorded by the next Tick
	Set itemF = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(f).LastItemId
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(f, "decide", , {"Outcome": "tellnow", "Fallback": 1, "CostUSD": 0.0025, "TraceSessionId": 4242, "ItemId": (itemF)})
	Set ..Refs = ..Refs_","_decision
	Do ..Tick(host, ..#NEXT)
	Do $$$AssertEquals(..NoLeaks(f, checklist, 5), 2, "F's beat and its recorded fallback hold none of them")

	// n: a run now that is sent; h: a Tick's skip for its empty checklist (no event), then a run now that is held
	Do $$$AssertEquals(..BeatNowOf(host, n, ..At(5)).Outcome, "sent", "N's run now is sent")
	Do $$$AssertEquals(..NoLeaks(n, checklist, 4), 2, "N's beat and its run now hold none of them")
	Do $$$AssertEquals(..BeatNowOf(host, h, ..At(5)).Outcome, "empty", "H's run now is held")
	Do $$$AssertEquals(..NoLeaks(h, "", 1), 1, "H's held run now (its Tick skip published none) holds no SessionRef")
}

/// Story 39.7 (QA; AC 1, AC 3): an off person's recorded decision is published with the person's own settings (off, the interval and the hours) and the result's cost and
/// trace, and a later Tick, which has nothing to commit for an off person with nothing pending, publishes nothing. No token of the row is in the event.
Method TestOffPersonsRecordedResultIsPublishedWithTheirSettings()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("offsettings")
	Do ..Beating(a, "check the orders")
	For pair = "on=0", "interval=60", "from=07:30", "to=21:15" {
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set($ClassMethod("OcuTalon.Checks.Beat", "SettingKey", a, $Piece(pair, "=", 1)), $Piece(pair, "=", 2)), "the setting "_$Piece(pair, "=", 1)_" is written")
	}
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(a)
	Set row.LastItemId = "zzoffitem"_..Number
	Do $$$AssertStatusOK(row.%Save(), "the pending beat is saved")
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(a, "decide", , {"Outcome": "ignore", "CostUSD": 0.0031, "TraceSessionId": 4243, "ItemId": (row.LastItemId)})
	Set ..Refs = ..Refs_","_decision
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(decision, a, {"ItemId": (row.LastItemId), "Kind": "decide", "Channel": "heartbeat", "CostUSD": 0.0031})
	Set host.BeatSessions = a
	Do ..Tick(host, ..#TICK)
	Set events = ..BeatEvents(a)
	Do $$$AssertEquals(events.%Size(), 1, "an off person's recorded decision publishes one event")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.%IsDefined("on")_"|"_payload.on_"|"_payload.interval_"|"_payload.from_"|"_payload.to, "1|0|60|07:30|21:15", "with off, the interval and the hours of the person's settings")
		Do $$$AssertEquals(payload.lastOutcome_"|"_payload.lastCostUSD_"|"_payload.traceHeaderId_"|"_payload.traceNamespace, "ignore|.0031|4243|"_$Namespace, "and the result, its cost and its trace")
		Do $$$AssertEquals(payload.nextDueAt_"|"_payload.%IsDefined("lastBeatAt")_"|"_payload.%IsDefined("lastSkipAt"), ..#TICK_"|0|0", "with the schedule as it was, no beat and no skip")
		Do $$$AssertEquals(payload.%ToJSON(), ..BeatViewOf(a), "and it is FromRow of the row")
	}
	Do ..Tick(host, ..#NEXT)
	Do $$$AssertEquals(..NoLeaks(a, "check the orders", 4), 1, "a later Tick publishes nothing more for an off person with nothing pending, and no token of the row is in the event")
}

/// The number of heartbeat events on the person's stream. Each holds none of the SessionRef, the checklist, the Item's Id, the decision's Ref and the snapshot keys
/// of the row as stored now (compared without regard to case), and only the keys of the view. tokens is the number of those values that the row holds, which the
/// test states, so that a row without them can't make the check empty.
Method NoLeaks(session As %String, checklist As %String, tokens As %Integer) As %Integer [ Private ]
{
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(session)
	Set values = $ListBuild(session)
	If checklist '= "" Set values = values_$ListBuild(checklist)
	For name = "LastItemId", "LastDecisionRef", "LastSnapshotKey", "LastQuietKey" {
		If $Property(row, name) '= "" Set values = values_$ListBuild($Property(row, name))
	}
	Do $$$AssertEquals($ListLength(values), tokens, "the row holds "_tokens_" values to look for")
	Set allowed = $ListFromString("on,interval,from,to,nextDueAt,lastBeatAt,lastOutcome,lastFallback,lastCostUSD,traceHeaderId,traceNamespace,lastSkipAt,lastSkipReason,lastRunNowAt,backoffUntil")
	Set events = ..BeatEvents(session)
	For i = 0:1:events.%Size() - 1 {
		Set payload = events.%Get(i).payload
		Set json = $ZConvert(payload.%ToJSON(), "U")
		Set position = 0
		While $ListNext(values, position, value) {
			Do $$$AssertTrue(json '[ $ZConvert(value, "U"), "event "_(i + 1)_" does not hold "_value)
		}
		Set iterator = payload.%GetIterator()
		While iterator.%GetNext(.key) {
			Do $$$AssertTrue($ListFind(allowed, key) > 0, "event "_(i + 1)_" holds only keys of the view: "_key)
		}
	}
	Quit events.%Size()
}

Method TestBeatNowRunsOnce()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("beatonce")
	Do ..Beating(a, "check the orders")
	Set host.BeatSessions = a
	Set request = ##class(OcuTalon.Checks.Msg.BeatNow).%New()
	Set request.SessionRef = a
	Set request.RequestedAt = ..#TICK
	Do $$$AssertStatusOK(host.OnRequest(request, .response), "the BeatNow is answered OK")
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 1, "one Item is sent")
	If items.%Size() '= 1 Quit
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref_"|"_response.Data, "1|sent|"_items.%Get(0).itemId_"|", "the answer is sent, with the ItemId as Ref")
	Do $$$AssertEquals(items.%Get(0).sessionId_"|"_items.%Get(0).superSession, "|"_..TraceOf(a), "in a trace session of its own, with the TraceRef of the person's session as SuperSession")
	Set request.RequestedAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(..#TICK, 30)
	Do $$$AssertStatusOK(host.OnRequest(request, .response), "a second BeatNow is answered OK")
	Do $$$AssertEquals(..Items().%Size(), 1, "and sends nothing")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref_"|"_response.Data, "0|cooldown||"_{"availableAt": (##class(OcuTalon.Bridge.Time).PlusSeconds(..#TICK, 120))}.%ToJSON(), "the answer is cooldown, with the time it may run again")
}

Method TestTickSendsTheItemsOfAFailedRunDue()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("beatpartial")
	Do ..Beating(a, "check the orders")
	Set host.BeatSessions = a
	Set marker = "zzchk"_..Number_" beat refused with an item"
	Set host.BeatError = marker
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(..Beaten(marker, .text), 1, "a RunDue that answers an error status logs one warning")
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 1, "and the Item that it returned with the error is still sent")
	If items.%Size() = 1 {
		Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(a)
		Do $$$AssertTrue($IsObject(row) && (row.LastItemId = items.%Get(0).itemId), "which is the Item of the saved pending row")
	}
}

Method TestBeatNowSendFailureAnswersFailed()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("beatnowfail")
	Set text = "zzchk"_..Number_" beatnow text"
	Do ..Beating(a, text)
	Set host.BeatSessions = a
	Do $ClassMethod(..#PROBE, "FailFindings", text)
	Set request = ##class(OcuTalon.Checks.Msg.BeatNow).%New()
	Set request.SessionRef = a
	Set request.RequestedAt = ..#TICK
	Do $$$AssertStatusOK(host.OnRequest(request, .response), "a BeatNow whose send fails is answered OK")
	Set items = ..Items()
	Do $$$AssertEquals(items.%Size(), 1, "the send was tried")
	If items.%Size() '= 1 Quit
	Set ..BeatItems = items.%Get(0).itemId
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref_"|"_response.Data, "0|failed||", "the answer is failed, with no Ref")
	Do $$$AssertEquals(..Warnings("BeatNow", $Parameter(..#PROBE, "LOGBEATSEND")_..BeatItems, .line), 1, "and one warning names the ItemId")
	Do $$$AssertTrue(line [ "is refused", "and holds the error text: "_line)
	Do $$$AssertNotTrue((line [ a) || (line [ $ZConvert(a, "U")), "but not the SessionRef that the error names, in any case: "_line)
}

Method TestBeatsRunWhateverEarlierStepsDo()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("beatearly")

	// a Sweep that throws and a due row that throws: RunDue still runs once
	Set host.SweepThrows = "zzchk"_..Number_" sweep refused"
	Set bad = ..Watch(a, "Zz.BeatEarlyBad")
	Do $ClassMethod(..#PROBE, "Feed", "Zz.BeatEarlyBad", {"outcome": "read", "state": "running", "rows": "not rows"})
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(..Fixed(), 1, "the Sweep's failure was logged")
	Do $$$AssertEquals(..Warnings("Tick", $Parameter(..#PROBE, "LOGRUN"), .text, ..Checks), 1, "and so was the row's")
	Do $$$AssertEquals($Select($IsObject(host.Beats): host.Beats.%Size(), 1: 0), 1, "RunDue is still called once")
	If $IsObject(host.Beats) && (host.Beats.%Size() = 1) Do $$$AssertEquals(host.Beats.%Get(0).tickAt, ..#TICK, "with the Tick's time")

	// a TickAt that is not a UTC stamp: the current time, a UTC stamp, goes to RunDue
	Set host.SweepThrows = ""
	Set host.Beats = ""
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = "not a stamp"
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(host.OnRequest(tick, .response), "a Tick with a bad TickAt is answered OK")
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertEquals($Select($IsObject(host.Beats): host.Beats.%Size(), 1: 0), 1, "RunDue is called once")
	If $IsObject(host.Beats) && (host.Beats.%Size() = 1) {
		Set given = host.Beats.%Get(0).tickAt
		Do $$$AssertTrue(given ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "it gets a UTC stamp: "_given)
		Do $$$AssertTrue('(before ] given) && '(given ] after), "that is the current time: "_given)
	}

	// a CheckChanged is no beat
	Set host.Beats = ""
	Set change = ##class(OcuTalon.Checks.Msg.CheckChanged).%New()
	Set change.CheckRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set change.SessionRef = a
	Set change.Kind = "production"
	Do $$$AssertStatusOK(host.OnRequest(change, .response), "a CheckChanged is answered OK")
	Do $$$AssertEquals($Select($IsObject(host.Beats): host.Beats.%Size(), 1: 0)_"|"_$Select($IsObject(host.BeatNows): host.BeatNows.%Size(), 1: 0), "0|0", "and calls neither RunDue nor RunNow")
}

Method TestBeatLogsAreRedacted()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("beatredact")
	Set secret = "sk-"_"ant-api03-QaSecretQaSecretQaSecret123456"

	// RunDue throws, and then answers an error status
	Set marker = "zzchk"_..Number_" beat refused"
	Set host.BeatThrows = marker_" "_secret
	Do ..Tick(host, ..#TICK)
	Do $$$AssertEquals(..Beaten(marker, .text), 1, "a RunDue that throws logs one warning that holds the text before the secret")
	Do $$$AssertNotTrue(text [ "QaSecret", "and not the secret: "_text)
	Set host.BeatThrows = ""
	Set host.BeatError = marker_" "_secret
	Do ..Tick(host, ..At(1))
	Do $$$AssertEquals(..Beaten(marker, .text), 2, "a RunDue that answers an error status logs one more")
	Do $$$AssertNotTrue(text [ "QaSecret", "without the secret: "_text)

	// RunNow throws, and then answers an error status
	Set request = ##class(OcuTalon.Checks.Msg.BeatNow).%New()
	Set request.SessionRef = a
	Set marker = "zzchk"_..Number_" beatnow refused"
	Set host.BeatNowThrows = marker_" "_secret
	Do $$$AssertStatusOK(host.OnRequest(request, .response), "a RunNow that throws is answered OK")
	Do $$$AssertEquals(response.Outcome, "failed", "with the outcome failed")
	Do $$$AssertEquals(..Beaten(marker, .text, "BeatNow"), 1, "and logs one warning")
	Do $$$AssertTrue(text [ marker, "that holds the text before the secret: "_text)
	Do $$$AssertNotTrue(text [ "QaSecret", "and not the secret: "_text)
	Set host.BeatNowThrows = ""
	Set host.BeatNowError = marker_" "_secret
	Do $$$AssertStatusOK(host.OnRequest(request, .response), "a RunNow that answers an error status is answered OK")
	Do $$$AssertEquals(..Beaten(marker, .text, "BeatNow"), 2, "and logs one more warning")
	Do $$$AssertNotTrue(text [ "QaSecret", "without the secret: "_text)
	Set upper = $ZConvert(a, "U")
	Set host.BeatNowError = "zzchk"_..Number_" beatnow names "_a_" twice "_a_" and as a %Save error does "_upper
	Do $$$AssertStatusOK(host.OnRequest(request, .response), "a RunNow whose error names the SessionRef is answered OK")
	Do $$$AssertEquals(..Beaten("zzchk"_..Number_" beatnow names ", .text, "BeatNow"), 1, "and logs one warning")
	Do $$$AssertNotTrue((text [ a) || (text [ upper), "that does not name the SessionRef, in any case: "_text)
	Set host.BeatNowError = ""
	Set host.BeatNowThrows = "zzchk"_..Number_" beatnow throws "_a_" and as a %Save error does "_upper
	Do $$$AssertStatusOK(host.OnRequest(request, .response), "a RunNow that throws an error that names the SessionRef is answered OK")
	Do $$$AssertEquals(..Beaten("zzchk"_..Number_" beatnow throws ", .text, "BeatNow"), 1, "and logs one warning")
	Do $$$AssertNotTrue((text [ a) || (text [ upper), "that does not name the SessionRef either: "_text)
}

Method TestBeatNowKeepsEachSession()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("beatnowa")
	Set b = ..Owner("beatnowb")
	For ref = a, b, a {
		Set request = ##class(OcuTalon.Checks.Msg.BeatNow).%New()
		Set request.SessionRef = ref
		Set request.RequestedAt = ..#TICK
		Do $$$AssertStatusOK(host.OnRequest(request, .response), "a BeatNow of "_ref_" is answered OK")
	}
	Set calls = $Select($IsObject(host.BeatNows): host.BeatNows.%Size(), 1: 0)
	Do $$$AssertEquals(calls, 3, "RunNow is called for each request, a repeat included")
	If calls = 3 Do $$$AssertEquals(host.BeatNows.%Get(0).sessionRef_"|"_host.BeatNows.%Get(1).sessionRef_"|"_host.BeatNows.%Get(2).sessionRef, a_"|"_b_"|"_a, "in order, each with its own SessionRef")
	If calls = 3 Do $$$AssertEquals(host.BeatNows.%Get(0).now_"|"_host.BeatNows.%Get(1).now_"|"_host.BeatNows.%Get(2).now, ..#TICK_"|"_..#TICK_"|"_..#TICK, "and the request's time")
	Do $$$AssertEquals($Select($IsObject(host.Beats): host.Beats.%Size(), 1: 0), 0, "and RunDue is never called")
}

Method TestCheckNow()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("nowA")
	Set b = ..Owner("nowB")
	Set later = "2030-06-02T12:00:00Z"
	Set one = ..Watch(a, "Zz.Now1", {"NextDueAt": (later)})
	Set two = ..Watch(a, "Zz.Now2", {"NextDueAt": (later)})
	Set theirs = ..Watch(b, "Zz.Now1", {"NextDueAt": (later)})
	Set unset = ..Watch(a, "Zz.Now3", {"NextDueAt": ""})
	For production = "Zz.Now1", "Zz.Now2", "Zz.Now3" {
		Do ..Feed(production, "read", "running")
	}
	// what a Tick would do besides the due checks: quiet an incident, send a fix result, run the beats
	Set quiet = ..Incident(a, "resolved", "Zz.NowQuiet", {"LastAt": (##class(OcuTalon.Bridge.Time).PlusSeconds(..#TICK, -960))})
	Set host.QuietAt = ..#TICK
	Set host.Swept = ##class(%ListOfObjects).%New()
	Do host.Swept.Insert(..Result(##class(OcuTalon.Bridge.Ids).NewRef(), quiet))
	Do ..Now(host, "ZZNS", "Zz.Now1", a, quiet)
	Set row = ..Row(one)
	Do $$$AssertNotEquals(row.LastRunAt, "", "A's row on the production ran")
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "passed|", "with the result of a run")
	Do $$$AssertEquals(row.LastRunHeaderId, ..#SESSIONID, "in the process's session")
	Do $$$AssertEquals(row.NextDueAt, later, "and NextDueAt is as it was")
	Do $$$AssertEquals(..Reads(), "Zz.Now1", "the production was read once")
	Set events = ..Events(a)
	Do $$$AssertEquals(events.%Size(), 1, "one check event is published")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.%ToJSON(), ..ViewOf(one), "it is FromRow of the row")
	Do $$$AssertEquals(..Ran(one), 1, "and one LOGRAN line is logged")
	Set other = ..Row(two)
	Do $$$AssertEquals(other.LastRunAt_"|"_other.Result_"|"_other.NextDueAt, "||"_later, "A's other production is unchanged")
	Set theirRow = ..Row(theirs)
	Do $$$AssertEquals(theirRow.LastRunAt_"|"_theirRow.Result_"|"_theirRow.NextDueAt, "||"_later, "B's row on the same production is unchanged")
	Do $$$AssertEquals(..Events(b).%Size(), 0, "and publishes nothing on B's stream")
	Do $$$AssertEquals(..Size(host.Quieted)_"|"_..Size(host.Sent)_"|"_..Size(host.Order)_"|"_..Size(host.Beats), "0|0|0|0", "nothing was quieted, no fix result sent, no beat run and nothing sent")

	// an empty NextDueAt stays empty
	Do ..Now(host, "ZZNS", "Zz.Now3", a, quiet)
	Set row = ..Row(unset)
	Do $$$AssertEquals(row.Result_"|"_row.NextDueAt, "passed|", "a row with no NextDueAt runs and still has none")

	// the same request on a Tick probe: nothing goes to Digest
	Kill ^||TickProbe
	Set shadow = ..Host("OcuTalon.Test.Digest.TickProbe")
	If '$IsObject(shadow) Quit
	Do ..Now(shadow, "ZZNS", "Zz.Now1", a, quiet)
	Do $$$AssertEquals($Get(^||TickProbe("digest")), "", "a CheckNow forwards nothing to Digest")
	Do ..Tick(shadow, ..#TICK)
	Do $$$AssertEquals($Get(^||TickProbe("digest")), 1, "where a Tick does")
	Kill ^||TickProbe
}

Method TestCheckNowScope()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("scopeNowA")
	Set b = ..Owner("scopeNowB")
	Do ..ScopeCase(host, a, b, "session", "ZZNS", a, "A")
	Do ..ScopeCase(host, a, b, "session B", "ZZNS", b, "B")
	Do ..ScopeCase(host, a, b, "instance", "ZZNS", "instance", "A,B")
	Do ..ScopeCase(host, a, b, "eval", "ZZNS", "eval", "")
	Do ..ScopeCase(host, a, b, "empty owner", "ZZNS", "", "")
	Do ..ScopeCase(host, a, b, "another namespace", "ZZELSE", a, "")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1"), "onlineDemo is set")
	Do ..ScopeCase(host, a, b, "instance on the online demo", "ZZNS", "instance", "")
	Do ..ScopeCase(host, a, b, "session on the online demo", "ZZNS", a, "A")
}

Method TestCheckNowFailures()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("nowFail")
	Set incident = ..Incident(a, "resolved", "Zz.NowFail1")
	Set ref = ..Watch(a, "Zz.NowFail1")
	Do ..Feed("Zz.NowFail1", "read", "running")

	// the read of the rows throws
	Set host.FailWatching = 1
	Do ..Now(host, "ZZNS", "Zz.NowFail1", a, incident)
	Do $$$AssertEquals(..Warnings("Now", $Parameter(..#PROBE, "LOGNOW"), .text, ..Incidents), 1, "a read of the rows that throws logs one warning")
	Do $$$AssertTrue(text [ incident, "which names the incident: "_text)
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.LastRunAt_"|"_row.Result, "|", "the row is unchanged")
	Do $$$AssertEquals(..Events(a).%Size()_"|"_..Ran(ref), "0|0", "nothing is published or logged as run")

	// no row matches
	Set host.FailWatching = 0
	Do ..Now(host, "ZZNS", "Zz.NowNone", a, incident)
	Do $$$AssertEquals(..Warnings("Now", $Parameter(..#PROBE, "LOGNOW"), , ..Incidents), 1, "no matching row adds no warning")
	Do $$$AssertEquals(..Reads(), "", "and reads nothing")

	// a run that throws does not stop the next row of the same request (instance: both sessions' rows)
	Set b = ..Owner("nowFailB")
	Set bad = ..Watch(a, "Zz.NowFail2")
	Set good = ..Watch(b, "Zz.NowFail2")
	Do ..Feed("Zz.NowFail2", "read", "running")
	Set host.RunThrows = bad
	Do ..Now(host, "ZZNS", "Zz.NowFail2", "instance", incident)
	Set host.RunThrows = ""
	Do $$$AssertEquals(..Warnings("Now", $Parameter(..#PROBE, "LOGRUN"), .text, bad), 1, "a run that throws logs one LOGRUN warning")
	Do $$$AssertTrue(text [ bad, "which names the check: "_text)
	Set row = ..Row(bad)
	Do $$$AssertEquals(row.LastRunAt_"|"_row.Result, "|", "and records nothing")
	Do $$$AssertEquals(..Row(good).Result, "passed", "the next row of the same request still runs")
}

/// One CheckNow for the production, handled by the host over the test's rows (the probe keeps only those); the status is asserted OK and the answer empty.
Method Now(host As OcuTalon.Test.Checks.Probe, namespace As %String, production As %String, owner As %String, incident As %String)
{
	Set request = ##class(OcuTalon.Checks.Msg.CheckNow).%New()
	Set request.Namespace = namespace
	Set request.Production = production
	Set request.OwnerRef = owner
	Set request.IncidentRef = incident
	Set host.Only = ..Checks
	Set host.OnlyIncidents = ..Incidents
	Kill response
	Do $$$AssertStatusOK(host.OnRequest(request, .response), "the CheckNow for "_production_" is answered OK")
	Do $$$AssertEquals($Get(response), "", "with no response")
}

/// A case of the scope: A's and B's rows on a new production, a row of A's in another namespace (C) and a row of the session eval (E, as an evaluation run's watch), a
/// CheckNow for the namespace from the owner, and the rows that ran asserted (A, B, comma-separated; none for ""). C and E must never run.
Method ScopeCase(host As OcuTalon.Test.Checks.Probe, a As %String, b As %String, label As %String, namespace As %String, owner As %String, expected As %String)
{
	Set ..Cases = ..Cases + 1
	Set production = "Zz.NowScope"_..Cases
	Set ra = ..Watch(a, production)
	Set rb = ..Watch(b, production)
	Set rc = ..Watch(a, production, {"Namespace": "ZZOTHER"})
	Set re = ..Watch("eval", production)
	Do ..Feed(production, "read", "running")
	Do ..Now(host, namespace, production, owner, "")
	Set ran = ""
	If ..Row(ra).LastRunAt '= "" Set ran = ran_$Select(ran = "": "", 1: ",")_"A"
	If ..Row(rb).LastRunAt '= "" Set ran = ran_$Select(ran = "": "", 1: ",")_"B"
	If ..Row(rc).LastRunAt '= "" Set ran = ran_$Select(ran = "": "", 1: ",")_"C"
	If ..Row(re).LastRunAt '= "" Set ran = ran_$Select(ran = "": "", 1: ",")_"E"
	Do $$$AssertEquals(ran, expected, label_": the rows that ran")
}

/// The number of entries of a probe's recorded array, 0 while nothing was recorded.
ClassMethod Size(list As %DynamicArray) As %Integer
{
	Quit $Select($IsObject(list): list.%Size(), 1: 0)
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
/// A shadow instance of the probe (or of a class that extends it), in this process, with a known session.
Method Host(class As %String = {..#PROBE}) As OcuTalon.Test.Checks.Probe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_class, .sc)
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

/// The number of warnings since the test began that Tick (LOGBEAT), or BeatNow (LOGBEATNOW) when method is "BeatNow", logged for a beat that failed with
/// a text holding the marker; text is the newest one's.
Method Beaten(marker As %String, Output text As %String, method As %String = "Tick") As %Integer
{
	Set start = $Parameter(..#PROBE, $Select(method = "BeatNow": "LOGBEATNOW", 1: "LOGBEAT"))
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = ? AND Text %STARTSWITH ? AND Text [ ? ORDER BY ID", ..LogMark, method, start, marker)
	Set count = 0
	Set text = ""
	While result.%Next() {
		Set count = count + 1
		Set text = result.%Get("Text")
	}
	Quit count
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

/// The number of the probe's own LOGBEATPUBLISH warnings since the test began (their error text is the probe's, so a real Checks job's are neither counted nor
/// removed), and the text of the last one.
Method BeatPublishWarnings(Output text As %String) As %Integer [ Private ]
{
	Set text = ""
	Set count = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = 'AnnounceBeat' AND Text %STARTSWITH ? AND Text [ ? ORDER BY ID", ..LogMark, $Parameter(..#PROBE, "LOGBEATPUBLISH"), ..#BEATPUBLISHREFUSED)
	While result.%Next() {
		Set count = count + 1
		Set text = result.%Get("Text")
	}
	Quit count
}

/// The heartbeat events of the session's stream, in order.
ClassMethod BeatEvents(session As %String) As %DynamicArray
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(session, "heartbeat")
}

/// The JSON of Heartbeat.FromRow of the person's row as stored now and the person's settings.
ClassMethod BeatViewOf(session As %String) As %String
{
	Do ##class(OcuTalon.Live.Payload.Heartbeat).FromRow(##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(session), ##class(OcuTalon.Checks.Beat).Values(session)).%JSONExportToString(.json)
	Quit json
}

/// A BeatNow of the session at the time, handled by the probe; the answer.
Method BeatNowOf(host As OcuTalon.Test.Checks.Probe, session As %String, at As %String) As OcuTalon.Msg.CommandResult
{
	Set request = ##class(OcuTalon.Checks.Msg.BeatNow).%New()
	Set request.SessionRef = session
	Set request.RequestedAt = at
	Do $$$AssertStatusOK(host.OnRequest(request, .response), "the BeatNow at "_at_" is answered OK")
	Quit response
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

/// The session's row, due at TICK (a real Tick does not reach it), then all-day heartbeat settings with the checklist (the beat then runs at any tick time, whatever
/// the instance zone is).
Method Beating(session As %String, checklist As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).%New()
	Set row.SessionRef = session
	Set row.NextDueAt = ..#TICK
	Do $$$AssertStatusOK(row.%Save(), "the person's row is made")
	For name = "from", "to", "checklist" {
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set($ClassMethod("OcuTalon.Checks.Beat", "SettingKey", session, name), $Select(name = "checklist": checklist, 1: "")), "the setting "_name_" is written")
	}
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
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Now", $Parameter(..#PROBE, "LOGRUN")_ref)
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Announce", $Parameter(..#PROBE, "LOGPUBLISH")_ref)
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Record", $Parameter(..#PROBE, "LOGFINDING")_ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGRAN")_ref)
	}
	For i = 1:1:$Length(..Incidents, ",") {
		Set ref = $Piece(..Incidents, ",", i)
		If ref = "" Continue
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Sweep", $Parameter(..#PROBE, "LOGQUIET")_ref)
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Now", $Parameter(..#PROBE, "LOGNOW")_ref)
	}
	For i = 1:1:$Length(..Requests, ",") {
		Set ref = $Piece(..Requests, ",", i)
		If ref = "" Continue
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Fixes", $Parameter(..#PROBE, "LOGFIX")_ref)
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = 'Tick' AND Text %STARTSWITH ? AND Text [ ?", ..LogMark, $Parameter(..#PROBE, "LOGFIXES"), "zzchk"_..Number_" sweep refused")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = 'AnnounceBeat' AND Text %STARTSWITH ? AND Text [ ?", ..LogMark, $Parameter(..#PROBE, "LOGBEATPUBLISH"), ..#BEATPUBLISHREFUSED)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = 'Tick' AND Text %STARTSWITH ? AND Text [ ?", ..LogMark, $Parameter(..#PROBE, "LOGBEAT"), "zzchk"_..Number_" beat refused")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = 'BeatNow' AND Text %STARTSWITH ? AND Text [ ?", ..LogMark, $Parameter(..#PROBE, "LOGBEATNOW"), "zzchk"_..Number_" beatnow ")
	For i = 1:1:$Length(..BeatItems, ",") {
		If $Piece(..BeatItems, ",", i) '= "" Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Tick", $Parameter(..#PROBE, "LOGBEATSEND")_$Piece(..BeatItems, ",", i))
		If $Piece(..BeatItems, ",", i) '= "" Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "BeatNow", $Parameter(..#PROBE, "LOGBEATSEND")_$Piece(..BeatItems, ",", i))
	}
}

}
