/// Tests of the incident lifecycle in IncidentManager (Story 5.5; AD-1, AD-4, AD-11, AD-12, AD-15, AD-16, AD-26, AD-27). The tests need no production and no
/// namespace but their own: they drive every message row through OnRequest of a shadow instance of Test.Watch.IncidentProbe in the test process, with real
/// IncidentCommand, ApprovalOutcome and FixResult objects, over fixture sessions, incidents and approval requests of Test.Data.Fixture, and read the rows,
/// the CommandResult, the orders that the probe recorded (Execute, with the session it would go in) and the sessions' streams. They run warm. The fixture
/// incidents are noticed unless a test says otherwise, with LastAt in 2030 (so they are not quiet), and an owner that is a session.
///   - TestDismiss: a noticed open incident and a resolved one are closed by their session (Ok 1, closed, the Ref, Data with the state and no variant; the row has
///     ClosedAt and no variant; one incident event, closed, on the stream); a session that is not a recipient gets not_found with no Data and no change; an
///     incident awaiting approval, fixing, closed or unnoticed gets not_allowed with Data and no change; an unknown verb is unknown_command and a missing
///     incident not_found;
///   - TestInstanceDismiss: an instance incident watched by A and not by C: A closes it (and B, which also watches it, gets the event), C gets not_found;
///   - TestCloseForReplay: closed from resolved only, with no session check;
///   - TestCloseQuiet: closed from resolved, and from a noticed open incident with demo mode off, after more than 15 minutes; not_allowed with demo mode on, while
///     awaiting approval or fixing; not_quiet within 15 minutes, with no change; the item's own reading of the setting demo.mode (the probe's override off) gives
///     the same two answers;
///   - TestApprovalOutcomes: approved starts the fix (fixing, one Execute for the request in the incident's trace session, the probe's own session kept);
///     rejected and expired reopen the incident with that variant when nothing else is pending, and keep it awaiting approval while another request is pending
///     or approved with its outcome on its way; while fixing an outcome changes nothing but the event;
///   - TestFixResults: a final (or interrupted) run resolves the incident, or returns it to awaiting approval while a request is pending, or starts the earliest
///     waiting request; the run's own request never waits for itself, even while its row still reads approved; a progress report changes nothing but the event;
///   - TestRefusedEvents: cancelled, a stale or repeated outcome, a request that is not the incident's, an unknown incident, a FixResult outside fixing and any
///     event on a closed incident change, send and publish nothing and log one info line;
///   - TestEveryChangePublishes: an accepted move publishes exactly one incident event with the row's state on each recipient's stream, a refused one none;
///   - TestRepeatDismiss: the same Dismiss twice closes once and then is not_allowed with state closed;
///   - TestExecuteSendFails: a failed send of the Execute leaves the row as saved, the event published, and logs one warning;
///   - TestPurge: skipped when the namespace already holds a closed incident older than 59 days (Purge would delete a row that the test did not make); else Purge(90) deletes the incident closed 91 days ago with its groups and keeps the one closed 89 days ago, an open one, and a closed one with no
///     ClosedAt; at the cutoff, one closed an hour after it stays and one closed an hour before it goes; 0, "x" and other non-numbers are errors that delete nothing;
///   - TestOnlyTheIncidentsOwnRequestsCount (QA): a pending or approved request of another incident, a Ref with no row and empty entries in RequestRefs are no
///     facts: R1 rejected still reopens the incident, a final run still resolves it, and nothing is executed; a control with its own approved request executes it;
///   - TestRefusedLineNamesIncidentEventAndState (QA): the info line of a refusal names the incident, the event and the state ('none' for no incident);
///   - TestFailedSaveChangesNothing (QA): with the probe's Move failing after it has moved the object (FailMove; a real failed %Save needs a row that another
///     process locks), a Dismiss is failed (Data with the state as stored, one LOGMOVE warning), an outcome and a FixResult are error statuses, and no row changes, no Execute goes out and nothing is published; a
///     control without the failure is accepted. The failed Recipients read of Dismiss stays untested: it needs a process without %All (see Test.Watch.Tell);
///   - TestPurgeFarCutoff (QA): Purge of more days than the calendar has is OK and deletes nothing;
///   - TestExecuteTarget: the item that Execute is sent to is an enabled item of the production, of the class OcuTalon.Fix.Executor;
///   - TestUnknownRequest: a request of a class that the item does not handle is an error status (5001) that names the class, with no answer;
///   - TestFixMessages: the properties and types of Execute and FixResult, the table name FixExecute and that it is not a reserved word.
/// The fixture rows, groups and streams are removed after each test, and so are the log lines that the tests made.
Class OcuTalon.Test.Watch.Lifecycle Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Watch.IncidentProbe";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the incidents of the test being run, comma-separated (their groups are dropped).
Property Incidents As %String(MAXLEN = "");

/// The number of the newest row of the event log when the test began.
Property LogMark As %Integer;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("WatchLifecycle", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Incidents = ""
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Incidents, ",") {
		If $Piece(..Incidents, ",", i) '= "" Do ..DropGroups($Piece(..Incidents, ",", i))
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Set ..Incidents = ""
	Do ..RemoveLogs()
	Quit $$$OK
}

Method TestDismiss()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("dismissa")
	Set b = ..Owner("dismissb")
	Set noFix = ..Incident(a, "open", {"OpenVariant": "no_fix"})
	Set resolved = ..Incident(a, "resolved")
	Set result = ..Command(host, "dismiss", noFix, a)
	Do $$$AssertEquals(..Said(result), "1|closed|"_noFix, "A dismisses the noticed open no_fix incident: Ok, closed, the Ref")
	Do $$$AssertEquals(..Data(result), "closed|", "Data has the state and no variant")
	Do $$$AssertEquals(result.Message, $Parameter(..#PROBE, "MESSAGECLOSED"), "and the message is the parameter's")
	Set row = ..Row(noFix)
	Do $$$AssertEquals(row.state_"|"_row.variant_"|"_(row.closedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z"), "closed||1", "the row is closed with ClosedAt and no variant")
	Do $$$AssertEquals(..Newest(a), "closed", "one incident event, closed, is on A's stream")
	Do $$$AssertEquals(..Count(a), 1, "and only one")
	Set result = ..Command(host, "dismiss", resolved, a)
	Do $$$AssertEquals(..Said(result), "1|closed|"_resolved, "A dismisses the resolved incident")
	Set row = ..Row(resolved)
	Do $$$AssertEquals(row.state_"|"_row.variant_"|"_(row.closedAt '= ""), "closed||1", "its row is closed with ClosedAt")
	Do $$$AssertEquals(..Count(a), 2, "and A's stream holds a second event")

	Set other = ..Incident(a, "open", {"OpenVariant": "no_fix"})
	Set before = ..Snapshot(other)
	Set result = ..Command(host, "dismiss", other, b)
	Do $$$AssertEquals(..Said(result), "0|not_found|", "B, who is not a recipient, gets not_found")
	Do $$$AssertEquals(result.Data, "", "with no Data")
	Do $$$AssertEquals(..Snapshot(other), before, "and nothing changes")
	Set result = ..Command(host, "dismiss", other, "")
	Do $$$AssertEquals(..Said(result), "0|not_found|", "a Dismiss with no session is not_found too")

	Set count = ..Count(a)
	For state = "awaiting_approval", "fixing", "closed" {
		Set refused = ..Incident(a, state, $Select(state = "closed": {"ClosedAt": "2030-01-01T10:00:00Z"}, 1: ""))
		Set before = ..Snapshot(refused)
		Set result = ..Command(host, "dismiss", refused, a)
		Do $$$AssertEquals(..Said(result), "0|not_allowed|", state_": not_allowed")
		Do $$$AssertEquals(..Data(result), state_"|", state_": Data has the state")
		Do $$$AssertEquals(..Snapshot(refused), before, state_": nothing changes")
	}
	Set unnoticed = ..Incident(a, "open", "", 0)
	Set before = ..Snapshot(unnoticed)
	Set result = ..Command(host, "dismiss", unnoticed, a)
	Do $$$AssertEquals(..Said(result)_"|"_..Data(result), "0|not_allowed||open|", "an unnoticed open incident: not_allowed, with the state")
	Do $$$AssertEquals(..Snapshot(unnoticed), before, "and nothing changes")
	Do $$$AssertEquals(..Count(a), count, "none of the refused Dismisses published anything")

	Set result = ..Command(host, "bogus", noFix, a)
	Do $$$AssertEquals(..Said(result)_"|"_result.Data, "0|unknown_command||", "a verb that is not one of VERBS is unknown_command")
	Set result = ..Command(host, "dismiss", ##class(OcuTalon.Bridge.Ids).NewRef(), a)
	Do $$$AssertEquals(..Said(result), "0|not_found|", "an incident that does not exist is not_found")
	Set result = ..Command(host, "dismiss", "", a)
	Do $$$AssertEquals(..Said(result), "0|not_found|", "and so is a missing Ref")
	Set result = ..Command(host, "bogus", ##class(OcuTalon.Bridge.Ids).NewRef(), a)
	Do $$$AssertEquals(..Said(result), "0|unknown_command|", "the verb is checked before the incident")
}

Method TestInstanceDismiss()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("instancea")
	Set b = ..Owner("instanceb")
	Set c = ..Owner("instancec")
	Set production = "Zz.Lifecycle"_..Number_".instance"
	Do ..Watch(a, production)
	Do ..Watch(b, production)
	Set incident = ..Incident("instance", "open", {"OpenVariant": "no_fix"}, 1, production)
	Set recipients = ##class(OcuTalon.Data.Session).Recipients("instance", incident, .sc)
	Do $$$AssertEquals($ListLength(recipients), 2, "two sessions watch the production, and C does not")
	Set result = ..Command(host, "dismiss", incident, c)
	Do $$$AssertEquals(..Said(result), "0|not_found|", "C, who does not watch the production, gets not_found")
	Do $$$AssertEquals(..Row(incident).state, "open", "and the incident is still open")
	Set result = ..Command(host, "dismiss", incident, a)
	Do $$$AssertEquals(..Said(result), "1|closed|"_incident, "A, who watches it, closes it")
	Do $$$AssertEquals(..Row(incident).state, "closed", "the incident is closed")
	Do $$$AssertEquals(..Count(a)_"|"_..Count(b)_"|"_..Count(c), "1|1|0", "A and B, who watch it, each get the event, and C none")
}

Method TestCloseForReplay()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("replay")
	Set resolved = ..Incident(a, "resolved")
	Set result = ..Command(host, "closeForReplay", resolved, "")
	Do $$$AssertEquals(..Said(result)_"|"_..Data(result), "1|closed|"_resolved_"|closed|", "closeForReplay closes a resolved incident, and checks no session")
	Set row = ..Row(resolved)
	Do $$$AssertEquals(row.state_"|"_(row.closedAt '= ""), "closed|1", "the row is closed with ClosedAt")
	For state = "open", "awaiting_approval", "fixing", "closed" {
		Set refused = ..Incident(a, state, $Select(state = "closed": {"ClosedAt": "2030-01-01T10:00:00Z"}, 1: ""))
		Set before = ..Snapshot(refused)
		Set result = ..Command(host, "closeForReplay", refused, "")
		Do $$$AssertEquals(..Said(result)_"|"_..Data(result), "0|not_allowed||"_state_"|", state_": not_allowed with the state")
		Do $$$AssertEquals(..Snapshot(refused), before, state_": nothing changes")
	}
	Set result = ..Command(host, "closeForReplay", ##class(OcuTalon.Bridge.Ids).NewRef(), "")
	Do $$$AssertEquals(..Said(result), "0|not_found|", "an incident that does not exist is not_found")
}

Method TestCloseQuiet()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("quiet")
	Set long = ##class(OcuTalon.Bridge.Time).PlusSeconds(##class(OcuTalon.Data.Time).NowUtc(), -960)
	Set short = ##class(OcuTalon.Bridge.Time).PlusSeconds(##class(OcuTalon.Data.Time).NowUtc(), -840)
	Set resolved = ..Incident(a, "resolved", {"LastAt": (long)})
	Set result = ..Command(host, "closeQuiet", resolved, "")
	Do $$$AssertEquals(..Said(result)_"|"_..Data(result), "1|closed|"_resolved_"|closed|", "16 minutes after the last failure a resolved incident is closed, with no session check")
	Set host.DemoModeIs = 0
	Set open = ..Incident(a, "open", {"LastAt": (long), "OpenVariant": "no_fix"})
	Set result = ..Command(host, "closeQuiet", open, "")
	Do $$$AssertEquals(..Said(result)_"|"_..Data(result), "1|closed|"_open_"|closed|", "a noticed open incident is closed when demo mode is off")
	Set host.DemoModeIs = 1
	Set demo = ..Incident(a, "open", {"LastAt": (long), "OpenVariant": "no_fix"})
	Set before = ..Snapshot(demo)
	Set result = ..Command(host, "closeQuiet", demo, "")
	Do $$$AssertEquals(..Said(result)_"|"_..Data(result), "0|not_allowed||open|no_fix", "and left alone when demo mode is on")
	Do $$$AssertEquals(..Snapshot(demo), before, "nothing changes")
	Set resolvedOnDemo = ..Incident(a, "resolved", {"LastAt": (long)})
	Set result = ..Command(host, "closeQuiet", resolvedOnDemo, "")
	Do $$$AssertEquals(..Said(result), "1|closed|"_resolvedOnDemo, "a resolved incident is closed with demo mode on too")
	Set host.DemoModeIs = 0
	For state = "awaiting_approval", "fixing" {
		Set refused = ..Incident(a, state, {"LastAt": (long)})
		Set before = ..Snapshot(refused)
		Set result = ..Command(host, "closeQuiet", refused, "")
		Do $$$AssertEquals(..Said(result)_"|"_..Data(result), "0|not_allowed||"_state_"|", state_": not_allowed")
		Do $$$AssertEquals(..Snapshot(refused), before, state_": nothing changes")
	}
	For state = "resolved", "open" {
		Set recent = ..Incident(a, state, {"LastAt": (short)})
		Set before = ..Snapshot(recent)
		Set result = ..Command(host, "closeQuiet", recent, "")
		Do $$$AssertEquals(..Said(result)_"|"_..Data(result), "0|not_quiet||"_state_"|", state_" 14 minutes after the last failure: not_quiet")
		Do $$$AssertEquals(..Snapshot(recent), before, state_": nothing changes")
	}
	Do ..RealDemoMode(host, a, long)
	Set closed = ..Incident(a, "closed", {"LastAt": (long), "ClosedAt": "2030-01-01T10:00:00Z"})
	Set result = ..Command(host, "closeQuiet", closed, "")
	Do $$$AssertEquals(..Said(result), "0|not_allowed|", "a closed incident is not_allowed")
	Set unnoticed = ..Incident(a, "open", {"LastAt": (long)}, 0)
	Set result = ..Command(host, "closeQuiet", unnoticed, "")
	Do $$$AssertEquals(..Said(result), "0|not_allowed|", "an unnoticed open incident is not_allowed")
}

Method TestApprovalOutcomes()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("outcomes")
	Set host.%SessionId = 7

	// approved: the fix starts, in the incident's trace session
	Set incident = ..Incident(a, "awaiting_approval", {"TraceHeaderId": 4242})
	Set r1 = ..Request(a, incident, "approved")
	Do ..Link(incident, r1)
	Do $$$AssertStatusOK(..Outcome(host, r1, incident, "approved"), "the approved outcome is handled")
	Set row = ..Row(incident)
	Do $$$AssertEquals(row.state_"|"_row.variant, "fixing|", "approved: the incident is fixing")
	Do $$$AssertEquals(..Orders(host), r1_"@4242", "one Execute for the request, in the incident's trace session")
	Do $$$AssertEquals(host.%SessionId, 7, "and the handler's own session is put back")
	Do $$$AssertEquals(..Count(a), 1, "one incident event")
	Do $$$AssertEquals(..Newest(a), "fixing", "with the state fixing")

	// rejected and expired with nothing else pending
	For outcome = "rejected", "expired" {
		Set incident = ..Incident(a, "awaiting_approval")
		Set r1 = ..Request(a, incident, outcome)
		Do ..Link(incident, r1)
		Set before = ..Count(a)
		Set orders = ..Orders(host)
		Do $$$AssertStatusOK(..Outcome(host, r1, incident, outcome), "the "_outcome_" outcome is handled")
		Set row = ..Row(incident)
		Do $$$AssertEquals(row.state_"|"_row.variant, "open|"_outcome, outcome_": the incident is open with that variant")
		Do $$$AssertEquals(..Orders(host), orders, outcome_": no Execute")
		Do $$$AssertEquals(..Count(a) - before, 1, outcome_": one event")
	}

	// overlap, pending: R2 pending
	Set incident = ..Incident(a, "awaiting_approval", {"TraceHeaderId": 4343})
	Set r1 = ..Request(a, incident, "rejected")
	Set r2 = ..Request(a, incident, "pending")
	Do ..Link(incident, r1_","_r2)
	Set orders = ..Orders(host)
	Do ..Outcome(host, r1, incident, "rejected")
	Set row = ..Row(incident)
	Do $$$AssertEquals(row.state_"|"_row.variant, "awaiting_approval|", "R1 rejected while R2 is pending: the incident stays awaiting_approval")
	Do $$$AssertEquals(..Orders(host), orders, "with no Execute")
	Do ..SetRequest(r2, "approved")
	Do ..Outcome(host, r2, incident, "approved")
	Set row = ..Row(incident)
	Do $$$AssertEquals(row.state_"|"_row.variant, "fixing|", "then R2's approval: the incident is fixing")
	Do $$$AssertEquals(..Orders(host), orders_$Select(orders = "": "", 1: ",")_r2_"@4343", "and R2 is executed")

	// overlap, pending: R2 approved, its outcome not yet here
	Set incident = ..Incident(a, "awaiting_approval", {"TraceHeaderId": 4444})
	Set r1 = ..Request(a, incident, "rejected")
	Set r2 = ..Request(a, incident, "approved")
	Do ..Link(incident, r1_","_r2)
	Set orders = ..Orders(host)
	Do ..Outcome(host, r1, incident, "rejected")
	Set row = ..Row(incident)
	Do $$$AssertEquals(row.state_"|"_row.variant, "awaiting_approval|", "R1 rejected while R2 is approved with its outcome on its way: the incident stays awaiting_approval")
	Do $$$AssertEquals(..Orders(host), orders, "with no Execute")
	Do ..Outcome(host, r2, incident, "approved")
	Set row = ..Row(incident)
	Do $$$AssertEquals(row.state_"|"_row.variant, "fixing|", "then R2's approval arrives: the incident is fixing")
	Do $$$AssertEquals(..Orders(host), orders_$Select(orders = "": "", 1: ",")_r2_"@4444", "and R2 is executed")

	// overlap, fixing: R1 runs; R2 approved, rejected or expired
	Set incident = ..Incident(a, "fixing", {"TraceHeaderId": 4545})
	Set r1 = ..Request(a, incident, "executing")
	Set r2 = ..Request(a, incident, "approved")
	Set r3 = ..Request(a, incident, "rejected")
	Set r4 = ..Request(a, incident, "expired")
	Do ..Link(incident, r1_","_r2_","_r3_","_r4)
	Set orders = ..Orders(host)
	For pair = r2_"|approved", r3_"|rejected", r4_"|expired" {
		Set before = ..Count(a)
		Do $$$AssertStatusOK(..Outcome(host, $Piece(pair, "|", 1), incident, $Piece(pair, "|", 2)), "the "_$Piece(pair, "|", 2)_" outcome of a second request is handled")
		Set row = ..Row(incident)
		Do $$$AssertEquals(row.state_"|"_row.variant, "fixing|", $Piece(pair, "|", 2)_" while fixing: the incident stays fixing")
		Do $$$AssertEquals(..Orders(host), orders, $Piece(pair, "|", 2)_" while fixing: no Execute")
		Do $$$AssertEquals(..Count(a) - before, 1, $Piece(pair, "|", 2)_" while fixing: one event")
	}
}

Method TestFixResults()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("results")
	Set host.%SessionId = 7

	// final: nothing else
	Set incident = ..Incident(a, "fixing", {"TraceHeaderId": 5151})
	Set r1 = ..Request(a, incident, "done")
	Do ..Link(incident, r1)
	Set orders = ..Orders(host)
	Do $$$AssertStatusOK(..Result(host, r1, incident, 1, 0), "the final result is handled")
	Set row = ..Row(incident)
	Do $$$AssertEquals(row.state_"|"_row.variant, "resolved|", "a final run, nothing else: resolved")
	Do $$$AssertEquals(..Orders(host), orders, "with no Execute")
	Do $$$AssertEquals(..Newest(a), "resolved", "and the event says so")

	// interrupted
	Set incident = ..Incident(a, "fixing", {"TraceHeaderId": 5252})
	Set r1 = ..Request(a, incident, "failed")
	Do ..Link(incident, r1)
	Do ..Result(host, r1, incident, 0, 1)
	Set row = ..Row(incident)
	Do $$$AssertEquals(row.state_"|"_row.variant, "resolved|", "an interrupted run (Final 0, Interrupted 1): resolved")

	// the run's own request still reads approved: it does not wait for itself
	Set incident = ..Incident(a, "fixing", {"TraceHeaderId": 5656})
	Set r1 = ..Request(a, incident, "approved")
	Do ..Link(incident, r1)
	Set orders = ..Orders(host)
	Do ..Result(host, r1, incident, 0, 1)
	Set row = ..Row(incident)
	Do $$$AssertEquals(row.state_"|"_row.variant, "resolved|", "a run whose own request still reads approved: resolved, the request does not wait for itself")
	Do $$$AssertEquals(..Orders(host), orders, "and its fix is not sent again")

	// another request pending
	Set incident = ..Incident(a, "fixing", {"TraceHeaderId": 5353})
	Set r1 = ..Request(a, incident, "done")
	Set r2 = ..Request(a, incident, "pending")
	Do ..Link(incident, r1_","_r2)
	Set orders = ..Orders(host)
	Do ..Result(host, r1, incident, 1, 0)
	Set row = ..Row(incident)
	Do $$$AssertEquals(row.state_"|"_row.variant, "awaiting_approval|", "a final run while R2 is pending: awaiting_approval")
	Do $$$AssertEquals(..Orders(host), orders, "with no Execute")

	// two others waiting: the earliest goes
	Set incident = ..Incident(a, "fixing", {"TraceHeaderId": 5454})
	Set r1 = ..Request(a, incident, "done")
	Set r2 = ..Request(a, incident, "approved")
	Set r3 = ..Request(a, incident, "approved")
	Do ..Link(incident, r1_","_r2_","_r3)
	Set orders = ..Orders(host)
	Set before = ..Count(a)
	Do ..Result(host, r1, incident, 1, 0)
	Set row = ..Row(incident)
	Do $$$AssertEquals(row.state_"|"_row.variant, "fixing|", "a final run while R2 and R3 are approved: the incident stays fixing")
	Do $$$AssertEquals(..Orders(host), orders_$Select(orders = "": "", 1: ",")_r2_"@5454", "and only R2, the earliest, is executed")
	Do $$$AssertEquals(..Count(a) - before, 1, "with one event")

	// progress
	Set incident = ..Incident(a, "fixing", {"TraceHeaderId": 5555})
	Set r1 = ..Request(a, incident, "executing")
	Set r2 = ..Request(a, incident, "approved")
	Do ..Link(incident, r1_","_r2)
	Set orders = ..Orders(host)
	Set before = ..Count(a)
	Do ..Result(host, r1, incident, 0, 0)
	Set row = ..Row(incident)
	Do $$$AssertEquals(row.state_"|"_row.variant, "fixing|", "progress: the incident stays fixing")
	Do $$$AssertEquals(..Orders(host), orders, "with no Execute, whatever waits")
	Do $$$AssertEquals(..Count(a) - before, 1, "and one event")
}

Method TestRefusedEvents()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("refused")
	Set other = ..Incident(a, "awaiting_approval")
	Set foreign = ..Request(a, other, "approved")
	Do ..Link(other, foreign)

	// cancelled
	Set incident = ..Incident(a, "awaiting_approval")
	Set r1 = ..Request(a, incident, "cancelled")
	Do ..Link(incident, r1)
	Do ..Refuse(host, a, incident, "cancelled", "outcome", r1, "cancelled")
	// a stale outcome: the row shows the request done
	Set incident = ..Incident(a, "awaiting_approval")
	Set r1 = ..Request(a, incident, "done")
	Do ..Link(incident, r1)
	Do ..Refuse(host, a, incident, "a repeat of approved after the request is done", "outcome", r1, "approved")
	// an outcome that the row does not show
	Set incident = ..Incident(a, "awaiting_approval")
	Set r1 = ..Request(a, incident, "pending")
	Do ..Link(incident, r1)
	Do ..Refuse(host, a, incident, "rejected while the row is pending", "outcome", r1, "rejected")
	// a request that is not in RequestRefs
	Set incident = ..Incident(a, "awaiting_approval")
	Set r1 = ..Request(a, incident, "approved")
	Do ..Refuse(host, a, incident, "a request that is not in RequestRefs", "outcome", r1, "approved")
	// a request of another incident, listed in this one's RequestRefs
	Set incident = ..Incident(a, "awaiting_approval")
	Do ..Link(incident, foreign)
	Do ..Refuse(host, a, incident, "a request of another incident", "outcome", foreign, "approved")
	// a Ref with no row
	Set incident = ..Incident(a, "awaiting_approval")
	Set missing = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Link(incident, missing)
	Do ..Refuse(host, a, incident, "a request with no row", "outcome", missing, "approved")
	// an outcome word that is not approved, rejected or expired
	Set incident = ..Incident(a, "awaiting_approval")
	Set r1 = ..Request(a, incident, "executing")
	Do ..Link(incident, r1)
	Do ..Refuse(host, a, incident, "an outcome that is not approved, rejected or expired", "outcome", r1, "executing")
	// no incident
	Set r1 = ..Request(a, "", "approved")
	Do ..Refuse(host, a, ##class(OcuTalon.Bridge.Ids).NewRef(), "an outcome for an incident that does not exist", "outcome", r1, "approved")
	Do ..Refuse(host, a, "", "an outcome with no incident", "outcome", r1, "approved")
	Do ..Refuse(host, a, ##class(OcuTalon.Bridge.Ids).NewRef(), "a FixResult for an incident that does not exist", "result", r1, 1, 0)

	// a FixResult outside fixing
	For state = "open", "awaiting_approval", "resolved" {
		Set incident = ..Incident(a, state)
		Set r1 = ..Request(a, incident, "done")
		Do ..Link(incident, r1)
		Do ..Refuse(host, a, incident, "a final FixResult while "_state, "result", r1, 1, 0)
		Do ..Refuse(host, a, incident, "a progress FixResult while "_state, "result", r1, 0, 0)
	}
	// a FixResult of a request that is not the incident's
	Set incident = ..Incident(a, "fixing")
	Do ..Link(incident, foreign)
	Do ..Refuse(host, a, incident, "a FixResult of another incident's request", "result", foreign, 1, 0)
	Set r1 = ..Request(a, incident, "done")
	Do ..Refuse(host, a, incident, "a FixResult of a request that is not in RequestRefs", "result", r1, 1, 0)

	// any event on a closed incident
	Set closed = ..Incident(a, "closed", {"ClosedAt": "2030-01-01T10:00:00Z"})
	Set r1 = ..Request(a, closed, "approved")
	Set r2 = ..Request(a, closed, "executing")
	Do ..Link(closed, r1_","_r2)
	Do ..Refuse(host, a, closed, "an approved outcome on a closed incident", "outcome", r1, "approved")
	Do ..Refuse(host, a, closed, "a progress FixResult on a closed incident", "result", r2, 0, 0)
	Do ..Refuse(host, a, closed, "a final FixResult on a closed incident", "result", r2, 1, 0)
	Do $$$AssertEquals(..Count(a), 0, "none of these published anything")
}

Method TestEveryChangePublishes()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("publisha")
	Set b = ..Owner("publishb")
	Set production = "Zz.Lifecycle"_..Number_".publish"
	Do ..Watch(a, production)
	Do ..Watch(b, production)

	// accepted: the dismiss of an instance incident reaches both watchers
	Set incident = ..Incident("instance", "open", {"OpenVariant": "no_fix"}, 1, production)
	Do ..Command(host, "dismiss", incident, a)
	Do $$$AssertEquals(..Count(a)_"|"_..Count(b), "1|1", "a dismiss publishes one event on each recipient's stream")
	Do $$$AssertEquals(..Newest(a)_"|"_..Newest(b), "closed|closed", "with the state of the row")

	// accepted, the state unchanged: a progress report and an outcome while fixing
	Set incident = ..Incident("instance", "fixing", "", 1, production)
	Set r1 = ..Request("instance", incident, "executing")
	Set r2 = ..Request("instance", incident, "rejected")
	Do ..Link(incident, r1_","_r2)
	Do ..Result(host, r1, incident, 0, 0)
	Do $$$AssertEquals(..Count(a)_"|"_..Count(b), "2|2", "a progress report publishes one event on each stream, though the state stays fixing")
	Do ..Outcome(host, r2, incident, "rejected")
	Do $$$AssertEquals(..Count(a)_"|"_..Count(b), "3|3", "so does an outcome")
	Do $$$AssertEquals(..Newest(a)_"|"_..Newest(b), "fixing|fixing", "with the state of the row")
	Do ..Result(host, r1, incident, 1, 0)
	Do $$$AssertEquals(..Newest(a)_"|"_..Newest(b)_"|"_..Count(a), "resolved|resolved|4", "the end of the run publishes the new state")

	// refused: nothing
	Set before = ..Count(a)_"|"_..Count(b)
	Do ..Command(host, "dismiss", ..Incident("instance", "fixing", "", 1, production), a)
	Do ..Result(host, r1, incident, 0, 0)
	Do ..Outcome(host, r2, incident, "rejected")
	Do $$$AssertEquals(..Count(a)_"|"_..Count(b), before, "a refused move publishes nothing")

	// an unnoticed incident has nobody to tell
	Set unnoticed = ..Incident(a, "awaiting_approval", "", 0)
	Set r3 = ..Request(a, unnoticed, "approved")
	Do ..Link(unnoticed, r3)
	Set before = ..Count(a)
	Do ..Outcome(host, r3, unnoticed, "approved")
	Do $$$AssertEquals(..Row(unnoticed).state, "fixing", "an unnoticed incident moves")
	Do $$$AssertEquals(..Count(a), before, "but publishes no incident event")
}

Method TestRepeatDismiss()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("repeat")
	Set incident = ..Incident(a, "open", {"OpenVariant": "no_fix"})
	Set first = ..Command(host, "dismiss", incident, a, "zzkey"_..Number)
	Do $$$AssertEquals(..Said(first), "1|closed|"_incident, "the first Dismiss closes the incident")
	Set closedAt = ..Row(incident).closedAt
	Set second = ..Command(host, "dismiss", incident, a, "zzkey"_..Number)
	Do $$$AssertEquals(..Said(second)_"|"_..Data(second), "0|not_allowed||closed|", "the same Dismiss again is not_allowed, with the state closed")
	Do $$$AssertEquals(..Row(incident).closedAt, closedAt, "ClosedAt is not moved")
	Do $$$AssertEquals(..Count(a), 1, "and only the first published")
}

Method TestExecuteSendFails()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("sendfails")
	Set host.FailExecute = 1
	Set host.%SessionId = 7
	Set incident = ..Incident(a, "awaiting_approval", {"TraceHeaderId": 6161})
	Set r1 = ..Request(a, incident, "approved")
	Do ..Link(incident, r1)
	Do $$$AssertStatusOK(..Outcome(host, r1, incident, "approved"), "the outcome is handled although the send fails")
	Do $$$AssertEquals(..Orders(host), r1_"@6161", "the send was tried once")
	Do $$$AssertEquals(..Row(incident).state, "fixing", "the row stays as saved")
	Do $$$AssertEquals(..Newest(a), "fixing", "and the event was published")
	Do $$$AssertEquals(host.%SessionId, 7, "the handler's own session is put back")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "Execute", $Parameter(..#PROBE, "LOGEXECUTE")_incident), 1, "one warning names the incident")
	Do $$$AssertTrue($Find(text, r1), "and the request: "_text)
}

Method TestPurge()
{
	Set a = ..Owner("purge")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set old = ##class(OcuTalon.Bridge.Time).PlusSeconds(now, -91 * 86400)
	Set young = ##class(OcuTalon.Bridge.Time).PlusSeconds(now, -89 * 86400)
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Incident WHERE State = 'closed' AND ClosedAt < ?", ##class(OcuTalon.Bridge.Time).PlusSeconds(now, -59 * 86400))
	Do rs.%Next()
	If rs.%GetData(1) {
		Do $$$AssertSkipped("The namespace holds a closed incident older than 59 days: Purge would delete a row that this test did not make")
		Quit
	}

	// an incident that is really closed, then aged
	Set closing = ..Incident(a, "resolved")
	Do ..Group(closing, 1)
	Do ..Group(closing, 2)
	Do ..Command(host, "closeForReplay", closing, "")
	Set closedAt = ..Row(closing).closedAt
	Do $$$AssertTrue(closedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "a close sets ClosedAt: "_closedAt)
	Do $$$AssertTrue((closedAt ] ##class(OcuTalon.Bridge.Time).PlusSeconds(now, -60)) && (closedAt '] ##class(OcuTalon.Bridge.Time).PlusSeconds(now, 60)), "which is now")
	Do ..SetClosedAt(closing, old)

	Set young89 = ..Incident(a, "closed", {"ClosedAt": (young)})
	Do ..Group(young89, 1)
	Set openOld = ..Incident(a, "open", {"FirstAt": (old), "LastAt": (old)})
	Do ..Group(openOld, 1)
	Set noClosedAt = ..Incident(a, "closed", {"FirstAt": (old), "LastAt": (old)})
	Do ..Group(noClosedAt, 1)
	Set fixing = ..Incident(a, "fixing", {"FirstAt": (old), "LastAt": (old)})
	Do ..Group(fixing, 1)

	Do $$$AssertStatusOK(##class(OcuTalon.Watch.IncidentManager).Purge(90), "Purge(90) is OK")
	Do $$$AssertEquals(..Exists(closing)_"|"_..Groups(closing), "0|0", "the incident closed 91 days ago and its two groups are gone")
	Do $$$AssertEquals(..Exists(young89)_"|"_..Groups(young89), "1|1", "the one closed 89 days ago stays, with its group")
	Do $$$AssertEquals(..Exists(openOld)_"|"_..Groups(openOld), "1|1", "an old open incident stays")
	Do $$$AssertEquals(..Exists(noClosedAt)_"|"_..Groups(noClosedAt), "1|1", "so does a closed one with no ClosedAt")
	Do $$$AssertEquals(..Exists(fixing)_"|"_..Groups(fixing), "1|1", "and a fixing one")

	// the day boundary: closed an hour after the cutoff of 90 days, and an hour before it
	Set edge = ..Incident(a, "closed", {"ClosedAt": (##class(OcuTalon.Bridge.Time).PlusSeconds(now, -90 * 86400 + 3600))})
	Do ..Group(edge, 1)
	Set past = ..Incident(a, "closed", {"ClosedAt": (##class(OcuTalon.Bridge.Time).PlusSeconds(now, -90 * 86400 - 3600))})
	Do ..Group(past, 1)
	Do $$$AssertStatusOK(##class(OcuTalon.Watch.IncidentManager).Purge(90), "Purge(90) again is OK")
	Do $$$AssertEquals(..Exists(edge), 1, "an incident closed an hour after the cutoff stays")
	Do $$$AssertEquals(..Exists(past)_"|"_..Groups(past), "0|0", "one closed an hour before the cutoff is gone, with its group")

	// a bad number deletes nothing
	Set doomed = ..Incident(a, "closed", {"ClosedAt": (old)})
	Do ..Group(doomed, 1)
	For bad = 0, "x", "", -1, 1.5, "1e2", " 5" {
		Do $$$AssertTrue($SYSTEM.Status.IsError(##class(OcuTalon.Watch.IncidentManager).Purge(bad)), "Purge('"_bad_"') is an error")
	}
	Do $$$AssertEquals(..Exists(doomed)_"|"_..Groups(doomed), "1|1", "and nothing was deleted")
	Do $$$AssertStatusOK(##class(OcuTalon.Watch.IncidentManager).Purge(60), "Purge(60) is OK")
	Do $$$AssertEquals(..Exists(doomed)_"|"_..Groups(doomed)_"|"_..Exists(young89), "0|0|0", "a smaller number of days deletes the closed incidents older than that")
	Do $$$AssertEquals(..Exists(openOld)_"|"_..Exists(noClosedAt)_"|"_..Exists(fixing), "1|1|1", "and still keeps the others")
}

Method TestOnlyTheIncidentsOwnRequestsCount()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("ownrequests")
	Set other = ..Incident(a, "awaiting_approval")
	Set foreignPending = ..Request(a, other, "pending")
	Set foreignApproved = ..Request(a, other, "approved")
	Set missing = ##class(OcuTalon.Bridge.Ids).NewRef()

	// awaiting_approval: the pending request of another incident, and a Ref with no row, are not R1's company
	Set incident = ..Incident(a, "awaiting_approval", {"TraceHeaderId": 7171})
	Set r1 = ..Request(a, incident, "rejected")
	Do ..Link(incident, r1_","_foreignPending_","_foreignApproved_","_missing_",,")
	Set orders = ..Orders(host)
	Do $$$AssertStatusOK(..Outcome(host, r1, incident, "rejected"), "the rejected outcome is handled")
	Set row = ..Row(incident)
	Do $$$AssertEquals(row.state_"|"_row.variant, "open|rejected", "R1 rejected: the pending and approved requests of another incident, a Ref with no row and empty entries do not keep the incident awaiting approval")
	Do $$$AssertEquals(..Orders(host), orders, "and nothing is executed")

	// fixing: the approved request of another incident does not wait for the fix
	Set incident = ..Incident(a, "fixing", {"TraceHeaderId": 7272})
	Set r1 = ..Request(a, incident, "done")
	Do ..Link(incident, r1_","_foreignApproved_","_foreignPending_","_missing)
	Do $$$AssertStatusOK(..Result(host, r1, incident, 1, 0), "the final result is handled")
	Set row = ..Row(incident)
	Do $$$AssertEquals(row.state_"|"_row.variant, "resolved|", "a final run: the requests of another incident do not wait or hold it, so it is resolved")
	Do $$$AssertEquals(..Orders(host), orders, "and the approved request of the other incident is not executed")

	// control: the same requests in the incident's own list do count
	Set incident = ..Incident(a, "fixing", {"TraceHeaderId": 7373})
	Set r1 = ..Request(a, incident, "done")
	Set r2 = ..Request(a, incident, "approved")
	Do ..Link(incident, r1_","_r2)
	Do ..Result(host, r1, incident, 1, 0)
	Do $$$AssertEquals(..Orders(host), orders_$Select(orders = "": "", 1: ",")_r2_"@7373", "control: its own approved request is executed")
}

Method TestRefusedLineNamesIncidentEventAndState()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("refusedline")
	Set closed = ..Incident(a, "closed", {"ClosedAt": "2030-01-01T10:00:00Z"})
	Set r1 = ..Request(a, closed, "approved")
	Do ..Link(closed, r1)
	Do ..Outcome(host, r1, closed, "approved")
	Set text = ..RefusedLine(closed)
	Do $$$AssertTrue($Find(text, closed) && $Find(text, "approved") && $Find(text, "closed"), "an approved outcome on a closed incident: the line names the incident, 'approved' and 'closed': "_text)
	Set awaiting = ..Incident(a, "awaiting_approval")
	Set r2 = ..Request(a, awaiting, "done")
	Do ..Link(awaiting, r2)
	Do ..Result(host, r2, awaiting, 1, 0)
	Set text = ..RefusedLine(awaiting)
	Do $$$AssertTrue($Find(text, awaiting) && $Find(text, "finished") && $Find(text, "awaiting_approval"), "a final FixResult while awaiting approval: the line names the incident, 'finished' and 'awaiting_approval': "_text)
	Set none = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Outcome(host, r2, none, "rejected")
	Set text = ..RefusedLine(none)
	Do $$$AssertTrue($Find(text, none) && $Find(text, "rejected") && $Find(text, "none"), "an outcome for an incident that does not exist: the line names the Ref, 'rejected' and the state 'none': "_text)
}

Method TestFailedSaveChangesNothing()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("failedsave")
	Set host.FailMove = 1
	Set host.%SessionId = 7

	// a command: failed, with the stored state as Data, nothing changed or published, one warning
	Set noFix = ..Incident(a, "open", {"OpenVariant": "no_fix"})
	Set before = ..Snapshot(noFix)
	Set result = ..Command(host, "dismiss", noFix, a)
	Do $$$AssertEquals(..Said(result)_"|"_..Data(result), "0|failed||open|no_fix", "a Dismiss whose save fails is failed, with no Ref, and Data with the state and variant as stored, not as the failed move left the object")
	Do $$$AssertEquals(result.Message, $Parameter(..#PROBE, "MESSAGEFAILED"), "and the message is the parameter's")
	Do $$$AssertEquals(..Snapshot(noFix), before, "the row is as it was")
	Do $$$AssertEquals(..Count(a), 0, "nothing is published")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "Command", $Parameter(..#PROBE, "LOGMOVE")_noFix), 1, "and one warning names the incident")

	// an approval outcome: an error status, and no Execute goes out
	Set incident = ..Incident(a, "awaiting_approval", {"TraceHeaderId": 8181})
	Set r1 = ..Request(a, incident, "approved")
	Do ..Link(incident, r1)
	Set before = ..Snapshot(incident)
	Set orders = ..Orders(host)
	Do $$$AssertTrue($SYSTEM.Status.IsError(..Outcome(host, r1, incident, "approved")), "an approved outcome whose save fails is an error status")
	Do $$$AssertEquals(..Snapshot(incident), before, "the row is as it was")
	Do $$$AssertEquals(..Orders(host), orders, "no Execute is sent for a move that was not saved")
	Do $$$AssertEquals(..Count(a), 0, "and nothing is published")
	Do $$$AssertEquals(host.%SessionId, 7, "the handler's own session is untouched")

	// a result that would start the next fix
	Set fixing = ..Incident(a, "fixing", {"TraceHeaderId": 8282})
	Set done = ..Request(a, fixing, "done")
	Set next = ..Request(a, fixing, "approved")
	Do ..Link(fixing, done_","_next)
	Set before = ..Snapshot(fixing)
	Do $$$AssertTrue($SYSTEM.Status.IsError(..Result(host, done, fixing, 1, 0)), "a final result whose save fails is an error status")
	Do $$$AssertEquals(..Snapshot(fixing), before, "the row is as it was")
	Do $$$AssertEquals(..Orders(host), orders, "and the next request is not executed")

	// control: the same input, with the save working, is accepted
	Set host.FailMove = 0
	Do $$$AssertStatusOK(..Outcome(host, r1, incident, "approved"), "control: the same outcome is handled")
	Do $$$AssertEquals(..Row(incident).state, "fixing", "the incident is fixing")
	Do $$$AssertEquals(..Orders(host), orders_$Select(orders = "": "", 1: ",")_r1_"@8181", "and the Execute goes out")
}

Method TestPurgeFarCutoff()
{
	Set a = ..Owner("purgefar")
	Set old = ##class(OcuTalon.Bridge.Time).PlusSeconds(##class(OcuTalon.Data.Time).NowUtc(), -91 * 86400)
	Set closed = ..Incident(a, "closed", {"ClosedAt": (old)})
	Do ..Group(closed, 1)
	Do $$$AssertStatusOK(##class(OcuTalon.Watch.IncidentManager).Purge(1000000), "a cutoff before the calendar begins is OK, not an error or an exception")
	Do $$$AssertEquals(..Exists(closed)_"|"_..Groups(closed), "1|1", "and deletes nothing")
}

Method TestFixMessages()
{
	Set execute = ##class(%Dictionary.CompiledClass).%OpenId("OcuTalon.Fix.Msg.Execute")
	Set result = ##class(%Dictionary.CompiledClass).%OpenId("OcuTalon.Fix.Msg.FixResult")
	Do $$$AssertTrue($IsObject(execute) && $IsObject(result), "both messages are compiled")
	If '$IsObject(execute) || '$IsObject(result) Quit
	Do $$$AssertEquals(execute.SqlTableName, "FixExecute", "Execute is the table FixExecute")
	Do $$$AssertEquals($SYSTEM.SQL.IsReservedWord("FixExecute"), 0, "which is not a reserved word")
	Do $$$AssertEquals($SYSTEM.SQL.IsReservedWord("Execute"), 1, "as Execute is")
	Do $$$AssertEquals(..Properties("OcuTalon.Fix.Msg.Execute"), "ApprovalRef:%Library.String:22", "Execute carries only the Ref of the request")
	Do $$$AssertEquals(..Properties("OcuTalon.Fix.Msg.FixResult"), "ApprovalRef:%Library.String:22,Completed:%Library.Integer:,FailedAgain:%Library.Integer:,Final:%Library.Boolean:,IncidentRef:%Library.String:22,Interrupted:%Library.Boolean:,Reason:%Library.String:1000,Resent:%Library.Integer:,Skipped:%Library.Integer:,Total:%Library.Integer:", "FixResult has the Refs, the two flags, the five counts and the reason")
	For class = "OcuTalon.Fix.Msg.Execute", "OcuTalon.Fix.Msg.FixResult" {
		Do $$$AssertTrue($ClassMethod(class, "%Extends", "Ens.Request"), class_" is an Ens.Request")
		Do $$$AssertEquals($ClassMethod(class, "%Extends", "OcuTalon.Msg.Command"), 0, class_" is no command")
		Do $$$AssertEquals(##class(%Dictionary.CompiledProperty).%ExistsId(class_"||SessionRef"), 0, class_" has no SessionRef")
	}
	Do $$$AssertEquals(##class(%Dictionary.CompiledProperty).%ExistsId("OcuTalon.Fix.Msg.FixResult||Skipped"), 1, "FixResult has Skipped")
}

/// The item's own reading of the setting demo.mode (the probe's override off): "1" leaves a noticed open incident alone, "0" closes it. The row is put back.
Method RealDemoMode(host As OcuTalon.Test.Watch.IncidentProbe, owner As %String, lastAt As %String)
{
	Set host.DemoModeIs = ""
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Try {
		For mode = 1, 0 {
			Do ##class(OcuTalon.Test.Demo.Step).Put(mode, ##class(OcuTalon.Data.Time).NowUtc())
			Set open = ..Incident(owner, "open", {"LastAt": (lastAt), "OpenVariant": "no_fix"})
			Set result = ..Command(host, "closeQuiet", open, "")
			Do $$$AssertEquals(..Said(result), $Select(mode: "0|not_allowed|", 1: "1|closed|"_open), "with the setting demo.mode "_mode_" the item's own reading "_$Select(mode: "leaves the open incident alone", 1: "closes it"))
		}
	} Catch exception {
		Set error = exception
	}
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(found, value, updatedAt)
	If $Data(error) Throw error
}

Method TestExecuteTarget()
{
	Set production = ##class(Ens.Config.Production).%OpenId($Parameter("OcuTalon.Test.Install.Production", "PRODUCTION"))
	Do $$$AssertTrue($IsObject(production), "the compiled production exists")
	If '$IsObject(production) Quit
	Set name = $Parameter(..#PROBE, "FIXEXECUTOR")
	Set found = ""
	For i = 1:1:production.Items.Count() {
		If production.Items.GetAt(i).Name = name Set found = production.Items.GetAt(i)
	}
	Do $$$AssertTrue($IsObject(found), "the production has the item "_name)
	If '$IsObject(found) Quit
	Do $$$AssertEquals(found.ClassName, "OcuTalon.Fix.Executor", "of the class OcuTalon.Fix.Executor")
	Do $$$AssertEquals(found.Enabled, 1, "and it is enabled")
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
/// A shadow instance of the probe, in this process.
Method Host() As OcuTalon.Test.Watch.IncidentProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	Quit host
}

/// A fixture session; its Ref is the owner of the fixture incidents.
Method Owner(name As %String) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzlife"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The session watches the production (a check row), so that it receives the events of an instance incident of the production.
Method Watch(session As %String, production As %String)
{
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(session, "ZZNS", production)
}

/// A fixture incident of the owner in the state, noticed unless noticed is 0, with the fields after the defaults; its Ref.
Method Incident(owner As %String, state As %String, fields As %DynamicObject = "", noticed As %Boolean = 1, production As %String = "") As %String
{
	If production = "" Set production = "Zz.Lifecycle"_..Number
	Set all = {"State": (state), "OpenVariant": ""}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, $Select(noticed: ##class(OcuTalon.Data.Time).NowUtc(), 1: ""), "ZZNS", production, all)
	Set ..Refs = ..Refs_","_ref
	Set ..Incidents = ..Incidents_","_ref
	Quit ref
}

/// A fixture approval request of the owner for the incident in the state; its Ref.
Method Request(owner As %String, incident As %String, state As %String) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, state)
	Set ..Refs = ..Refs_","_ref
	Quit ref
}

/// Sets the incident's RequestRefs (comma-separated); a save that fails is thrown, so the test fails there.
ClassMethod Link(incident As %String, refs As %String)
{
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.RequestRefs = refs
	$$$ThrowOnError(row.%Save())
}

/// Sets the State of the approval request row; a save that fails is thrown.
ClassMethod SetRequest(ref As %String, state As %String)
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Set row.State = state
	$$$ThrowOnError(row.%Save())
}

/// Sets ClosedAt of the incident; a save that fails is thrown.
ClassMethod SetClosedAt(incident As %String, closedAt As %String)
{
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.ClosedAt = closedAt
	$$$ThrowOnError(row.%Save())
}

/// A group of the incident, saved; the test deletes it afterwards.
Method Group(incident As %String, seq As %Integer)
{
	Set group = ##class(OcuTalon.Data.FailureGroup).%New()
	Set group.IncidentRef = incident
	Set group.Seq = seq
	Set group.ItemName = "ZzItem"
	Set group.ErrorPattern = "Field 'Qty' was empty"
	Set group.Count = 3
	Set group.NoticeCount = 3
	Set group.FirstAt = "2030-01-01T09:00:00Z"
	Set group.LastAt = "2030-01-01T09:30:00Z"
	Do $$$AssertStatusOK(group.%Save(), "a group of the incident is saved")
}

/// Deletes the failure groups of the incident.
ClassMethod DropGroups(incident As %String)
{
	Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident)
	For i = 1:1:groups.Count() {
		Do ##class(OcuTalon.Data.FailureGroup).%DeleteId(groups.GetAt(i).%Id())
	}
}

/// The number of groups of the incident.
ClassMethod Groups(incident As %String) As %Integer
{
	Quit ##class(OcuTalon.Data.FailureGroup).OfIncident(incident).Count()
}

/// 1 when the incident row exists.
ClassMethod Exists(incident As %String) As %Boolean
{
	Quit ##class(OcuTalon.Data.Incident).RefIndexExists(incident)
}

/// An IncidentCommand of the verb for the incident from the session, handled by the probe; the CommandResult.
Method Command(host As OcuTalon.Test.Watch.IncidentProbe, verb As %String, incident As %String, session As %String, key As %String = "") As OcuTalon.Msg.CommandResult
{
	Set command = ##class(OcuTalon.Msg.IncidentCommand).%New()
	Set command.Verb = verb
	Set command.IncidentRef = incident
	Set command.SessionRef = session
	Set command.Origin = "web_user"
	Set command.IdempotencyKey = key
	Set response = ""
	Do $$$AssertStatusOK(host.OnRequest(command, .response), "the "_verb_" command is handled")
	Do $$$AssertTrue($IsObject(response) && response.%IsA("OcuTalon.Msg.CommandResult"), "and answered with a CommandResult")
	Quit response
}

/// An ApprovalOutcome handled by the probe; the status.
Method Outcome(host As OcuTalon.Test.Watch.IncidentProbe, approval As %String, incident As %String, outcome As %String) As %Status
{
	Set message = ##class(OcuTalon.Bridge.Msg.ApprovalOutcome).%New()
	Set message.ApprovalRef = approval
	Set message.IncidentRef = incident
	Set message.Outcome = outcome
	Set response = ""
	Quit host.OnRequest(message, .response)
}

/// A FixResult handled by the probe; the status.
Method Result(host As OcuTalon.Test.Watch.IncidentProbe, approval As %String, incident As %String, final As %Boolean, interrupted As %Boolean) As %Status
{
	Set message = ##class(OcuTalon.Fix.Msg.FixResult).%New()
	Set message.ApprovalRef = approval
	Set message.IncidentRef = incident
	Set message.Final = final
	Set message.Interrupted = interrupted
	Set response = ""
	Quit host.OnRequest(message, .response)
}

/// Hands the probe an ApprovalOutcome (kind outcome; one is the outcome) or a FixResult (kind result; one is Final, two Interrupted) of the request for the
/// incident, and asserts that it was refused: the status is OK, the row is as it was, no Execute was recorded, nothing was published to the owner and one
/// info line was logged.
Method Refuse(host As OcuTalon.Test.Watch.IncidentProbe, owner As %String, incident As %String, label As %String, kind As %String, approval As %String, one As %String = "", two As %String = "")
{
	Set snapshot = ..Snapshot(incident)
	Set orders = ..Orders(host)
	Set events = ..Count(owner)
	Set infos = ..Infos()
	If kind = "outcome" {
		Set sc = ..Outcome(host, approval, incident, one)
	} Else {
		Set sc = ..Result(host, approval, incident, one, two)
	}
	Do $$$AssertStatusOK(sc, label_": handled")
	Do $$$AssertEquals(..Snapshot(incident), snapshot, label_": the row is as it was")
	Do $$$AssertEquals(..Orders(host), orders, label_": nothing is sent")
	Do $$$AssertEquals(..Count(owner), events, label_": nothing is published")
	Do $$$AssertEquals(..Infos() - infos, 1, label_": one info line is logged")
}

/// The CommandResult as "Ok|Outcome|Ref".
ClassMethod Said(result As OcuTalon.Msg.CommandResult) As %String
{
	Quit result.Ok_"|"_result.Outcome_"|"_result.Ref
}

/// The Data of the result as "state|openVariant".
ClassMethod Data(result As OcuTalon.Msg.CommandResult) As %String
{
	If result.Data = "" Quit "<no data>"
	Set data = {}.%FromJSON(result.Data)
	Quit data.state_"|"_data.openVariant
}

/// The incident row as {state, variant, closedAt, noticedAt, requestRefs}, read afresh.
ClassMethod Row(incident As %String) As %DynamicObject
{
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	If '$IsObject(row) Quit {"state": "<gone>", "variant": "", "closedAt": "", "noticedAt": "", "requestRefs": ""}
	Quit {"state": (row.State), "variant": (row.OpenVariant), "closedAt": (row.ClosedAt), "noticedAt": (row.NoticedAt), "requestRefs": (row.RequestRefs)}
}

/// The row as text, to compare before and after.
ClassMethod Snapshot(incident As %String) As %String
{
	Set row = ..Row(incident)
	Quit row.state_"|"_row.variant_"|"_row.closedAt_"|"_row.noticedAt_"|"_row.requestRefs
}

/// The orders that the probe recorded, as "ref@session,..." in order.
ClassMethod Orders(host As OcuTalon.Test.Watch.IncidentProbe) As %String
{
	Set text = ""
	If '$IsObject(host.Executed) Quit text
	For i = 0:1:host.Executed.%Size() - 1 {
		Set order = host.Executed.%Get(i)
		Set text = text_$Select(text = "": "", 1: ",")_order.approvalRef_"@"_order.sessionId
	}
	Quit text
}

/// The number of incident events on the session's stream.
ClassMethod Count(session As %String) As %Integer
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(session, "incident").%Size()
}

/// The state of the newest incident event on the session's stream, "" when there is none.
ClassMethod Newest(session As %String) As %String
{
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "incident")
	If events.%Size() = 0 Quit ""
	Quit events.%Get(events.%Size() - 1).payload.state
}

/// The number of info lines (Type 4) of IncidentManager's refusals in the event log since the test began.
Method Infos() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGREFUSED"))
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The text of the newest info line (Type 4) of a refusal that names the incident, "" when there is none.
Method RefusedLine(incident As %String) As %String
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ? ORDER BY ID DESC", ..LogMark, $Parameter(..#PROBE, "LOGREFUSED")_incident)
	If result.%Next() Quit result.%Get("Text")
	Quit ""
}

/// Removes the lines that the tests made: the warnings of Execute and of a failed save, and the refusals.
Method RemoveLogs()
{
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Execute", $Parameter(..#PROBE, "LOGEXECUTE"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Command", $Parameter(..#PROBE, "LOGMOVE"))
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGREFUSED"))
}

/// The properties that the class declares as "Name:Type:MaxLen,...", sorted by name.
ClassMethod Properties(class As %String) As %String
{
	Set compiled = ##class(%Dictionary.CompiledClass).%OpenId(class)
	For i = 1:1:compiled.Properties.Count() {
		Set property = compiled.Properties.GetAt(i)
		If property.Origin '= class Continue
		Set found(property.Name) = property.Name_":"_property.Type_":"_property.Parameters.GetAt("MAXLEN")
	}
	Set text = ""
	Set name = ""
	For {
		Set name = $Order(found(name), 1, entry)
		Quit:name=""
		Set text = text_$Select(text = "": "", 1: ",")_entry
	}
	Quit text
}

}
