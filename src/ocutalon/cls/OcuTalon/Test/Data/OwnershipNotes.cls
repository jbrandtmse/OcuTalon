/// Tests of the reads of the daily note in OcuTalon.Data.Ownership (Story 41.3; AD-4, AD-13, AD-21): NoteTurns, NoteDecisions, NoteIncidents, NoteApprovals and
/// NoteReminders, their Rows kinds, and DecisionChannel. Safe on a slot: no production is needed. The sessions and rows are fixtures, and every test removes its own by Ref.
///   - TestIsolation: two sessions read none of each other's rows through any of the kinds, and the owners eval and instance are no session's; an instance incident of a
///     watched production, and its instance approval request, are read on a local install and not on the online demo;
///   - TestRefusals: each kind refuses an empty owner and the owners eval and instance (in any case, with trailing blanks) through Test.Data.OwnershipProbe.Call, with an
///     error status and no row; so does DecisionChannel;
///   - TestWindows: each window includes its from bound and excludes its to bound, and a record outside it is not read; an approval request is placed by AnsweredAt, else RaisedAt;
///   - TestEmptyBounds: a window with an empty bound is an error status and no row;
///   - TestOrder: the rows come by time and then ID;
///   - TestTurnsAndChannel: a refused turn is not one of the turns; a decision's channel is its own usage rows' first that is not empty, and another owner's usage is not read.
Class OcuTalon.Test.Data.OwnershipNotes Extends %UnitTest.TestCase
{

/// The window of the fixtures, UTC: [FROM, TO).
Parameter FROM = "2030-06-15T04:00:00Z";

Parameter TO = "2030-06-16T04:00:00Z";

/// The namespace and production of the instance records of TestIsolation, which no other test class uses.
Parameter WATCHEDNS = "ZZNS";

Parameter WATCHED = "Zz.NotesProduction";

/// The run's number.
Property Number As %Integer;

/// The count of sessions made.
Property Count As %Integer [ InitialExpression = 0 ];

/// The Refs of the fixture rows of the test, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("OwnershipNotes", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $$$OK
}

/// Sessions A and B each own a row of every kind inside the window; each reads only its own through each kind.
Method TestIsolation()
{
	Set a = ..Session(), b = ..Session()
	Set mid = "2030-06-15T10:00:00Z"
	For owner = a, b {
		Set own(owner, "turn") = ..Keep(##class(OcuTalon.Test.Data.Fixture).Turn(owner, mid))
		Set own(owner, "decision") = ..Keep(##class(OcuTalon.Test.Data.Fixture).Decision(owner, "decide", mid))
		Set own(owner, "incident") = ..Keep(##class(OcuTalon.Test.Data.Fixture).Incident(owner, mid))
		Set own(owner, "approval") = ..Keep(##class(OcuTalon.Test.Data.Fixture).Approval(owner, "", "pending", mid))
		Set own(owner, "reminder") = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(owner, mid))
	}
	Set ownership = "OcuTalon.Data.Ownership"
	For owner = a, b {
		Do $$$AssertEquals(..RefsOf($ClassMethod(ownership, "NoteTurns", owner, ..#FROM, ..#TO, .sc)), own(owner, "turn"), "NoteTurns: only the session's own turn")
		Do $$$AssertStatusOK(sc, "NoteTurns is OK")
		Do $$$AssertEquals(..RefsOf($ClassMethod(ownership, "NoteDecisions", owner, ..#FROM, ..#TO, .sc)), own(owner, "decision"), "NoteDecisions: only its own decision")
		Do $$$AssertEquals(..RefsOf($ClassMethod(ownership, "NoteIncidents", owner, ..#FROM, ..#TO, .sc)), own(owner, "incident"), "NoteIncidents: only its own incident")
		Do $$$AssertEquals(..RefsOf($ClassMethod(ownership, "NoteApprovals", owner, ..#FROM, ..#TO, .sc)), own(owner, "approval"), "NoteApprovals: only its own request")
		Do $$$AssertEquals(..RefsOf($ClassMethod(ownership, "NoteReminders", owner, ..#FROM, ..#TO, .sc)), own(owner, "reminder"), "NoteReminders: only its own reminder")
	}
	Set instance = ..Keep(##class(OcuTalon.Test.Data.Fixture).Incident("instance", mid, ..#WATCHEDNS, ..#WATCHED))
	Set request = ..Keep(##class(OcuTalon.Test.Data.Fixture).Approval("instance", instance, "pending", mid))
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Incident("eval", mid, ..#WATCHEDNS, ..#WATCHED))
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder("instance", mid))
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteIncidents(a, ..#FROM, ..#TO)), own(a, "incident"), "an incident of eval or instance (of no watched production) is not one of A's")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteApprovals(a, ..#FROM, ..#TO)), own(a, "approval"), "nor is the instance request of such an incident")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteReminders(a, ..#FROM, ..#TO)), own(a, "reminder"), "a reminder of owner instance is not one of A's")
	Do ..Check(a, ..#WATCHEDNS, ..#WATCHED)
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteIncidents(a, ..#FROM, ..#TO)), own(a, "incident")_","_instance, "on a local install A sees the instance incident of a production its check watches")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteApprovals(a, ..#FROM, ..#TO)), own(a, "approval")_","_request, "and the instance request of that incident")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteIncidents(a, ..#FROM, ..#TO)), own(a, "incident"), "and on the online demo it does not")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteApprovals(a, ..#FROM, ..#TO)), own(a, "approval"), "nor its instance request")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
}

/// Each kind refuses an empty owner and the owners eval and instance, in any case and with trailing blanks.
Method TestRefusals()
{
	Set probe = "OcuTalon.Test.Data.OwnershipProbe"
	Set a = ..Session()
	Set mid = "2030-06-15T10:00:00Z"
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Turn(a, mid))
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder("eval", mid))
	Set kinds = $ListBuild("noteTurns", "noteDecisions", "noteReminders", "noteIncidents", "noteApprovals")
	Set position = 0
	While $ListNext(kinds, position, kind) {
		For owner = "", "eval", "instance", "EVAL", "Instance", "eval ", "EVAL  ", "INSTANCE " {
			If (kind = "noteIncidents") || (kind = "noteApprovals") {
				Set rows = $ClassMethod(probe, "Call", kind, owner, .sc, 1, ..#FROM, ..#TO)
			} Else {
				Set rows = $ClassMethod(probe, "Call", kind, owner, .sc, ..#FROM, ..#TO)
			}
			Do $$$AssertStatusNotOK(sc, kind_": '"_owner_"' is not a session's Ref")
			Do $$$AssertEquals(rows.Count(), 0, kind_": with no rows")
		}
	}
	Set rows = $ClassMethod(probe, "Call", "noteTurns", a, .sc, ..#FROM, ..#TO)
	Do $$$AssertStatusOK(sc, "a session's Ref is accepted")
	Do $$$AssertEquals(rows.Count(), 1, "and gives its row")
	For owner = "", "eval", "instance", "Eval ", "INSTANCE" {
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).DecisionChannel("zzdecision", owner, .sc), "", "DecisionChannel for '"_owner_"' reads nothing")
		Do $$$AssertStatusNotOK(sc, "and says why")
		For read = "NoteTurns", "NoteDecisions", "NoteIncidents", "NoteApprovals", "NoteReminders" {
			Set rows = $ClassMethod("OcuTalon.Data.Ownership", read, owner, ..#FROM, ..#TO, .sc)
			Do $$$AssertStatusNotOK(sc, read_" for '"_owner_"' is an error")
			Do $$$AssertEquals(rows.Count(), 0, "and reads no row")
		}
	}
}

/// Each window includes its from bound and excludes its to bound. For each kind, rows one second before from, at from, one second before to and at to: the middle two are read.
Method TestWindows()
{
	Set a = ..Session()
	Set from = ..#FROM, to = ..#TO
	Set before = ##class(OcuTalon.Data.Time).AddSeconds(from, -1)
	Set last = ##class(OcuTalon.Data.Time).AddSeconds(to, -1)
	Set times = $ListBuild(before, from, last, to)
	Set position = 0
	While $ListNext(times, position, at) {
		Set turn(at) = ..Keep(##class(OcuTalon.Test.Data.Fixture).Turn(a, at))
		Set decision(at) = ..Keep(##class(OcuTalon.Test.Data.Fixture).Decision(a, "decide", at))
		Set incident(at) = ..Keep(##class(OcuTalon.Test.Data.Fixture).Incident(a, at))
		Set approval(at) = ..Keep(##class(OcuTalon.Test.Data.Fixture).Approval(a, "", "pending", at))
		Set reminder(at) = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(a, at))
	}
	Set ownership = "OcuTalon.Data.Ownership"
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteTurns(a, from, to)), turn(from)_","_turn(last), "NoteTurns: from is in, to is out")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteDecisions(a, from, to)), decision(from)_","_decision(last), "NoteDecisions: from is in, to is out")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteIncidents(a, from, to)), incident(from)_","_incident(last), "NoteIncidents: from is in, to is out")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteApprovals(a, from, to)), approval(from)_","_approval(last), "NoteApprovals: from is in, to is out")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteReminders(a, from, to)), reminder(from)_","_reminder(last), "NoteReminders: from is in, to is out")
	// A request is placed by AnsweredAt when it has one: raised in the window and answered after it, and raised before it and answered inside it.
	Set late = ..Keep(##class(OcuTalon.Test.Data.Fixture).Approval(a, "", "approved", "2030-06-15T10:00:00Z", {"AnsweredAction": "approve", "AnsweredAt": (to)}))
	Set early = ..Keep(##class(OcuTalon.Test.Data.Fixture).Approval(a, "", "approved", before, {"AnsweredAction": "approve", "AnsweredAt": "2030-06-15T10:00:00Z"}))
	Set refs = ..RefsOf(##class(OcuTalon.Data.Ownership).NoteApprovals(a, from, to))
	Do $$$AssertEquals(refs, approval(from)_","_early_","_approval(last), "a request answered after the window is out, and one raised before it and answered inside it is in, by its AnsweredAt")
	Do $$$AssertTrue(refs '[ late, "the late one is not read")
}

/// A window with an empty bound is an error status and no row, and so is a bound that is not given.
Method TestEmptyBounds()
{
	Set a = ..Session()
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-06-15T10:00:00Z"))
	For read = "NoteTurns", "NoteDecisions", "NoteIncidents", "NoteApprovals", "NoteReminders" {
		Set rows = $ClassMethod("OcuTalon.Data.Ownership", read, a, "", ..#TO, .sc)
		Do $$$AssertStatusNotOK(sc, read_" with no from is an error")
		Do $$$AssertEquals(rows.Count(), 0, "with no row")
		Set rows = $ClassMethod("OcuTalon.Data.Ownership", read, a, ..#FROM, "", .sc)
		Do $$$AssertStatusNotOK(sc, read_" with no to is an error")
		Do $$$AssertEquals(rows.Count(), 0, "with no row")
	}
}

/// The rows of a kind come by time, and rows of one time by ID.
Method TestOrder()
{
	Set a = ..Session()
	Set first = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(a, "2030-06-15T12:00:00Z"))
	Set second = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(a, "2030-06-15T11:00:00Z"))
	Set third = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(a, "2030-06-15T11:00:00Z"))
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteReminders(a, ..#FROM, ..#TO)), second_","_third_","_first, "by DueAt, then ID")
	Set late = ..Keep(##class(OcuTalon.Test.Data.Fixture).Approval(a, "", "pending", "2030-06-15T12:00:00Z"))
	Set early = ..Keep(##class(OcuTalon.Test.Data.Fixture).Approval(a, "", "approved", "2030-06-15T09:00:00Z", {"AnsweredAction": "approve", "AnsweredAt": "2030-06-15T13:00:00Z"}))
	Set tie = ..Keep(##class(OcuTalon.Test.Data.Fixture).Approval(a, "", "pending", "2030-06-15T12:00:00Z"))
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteApprovals(a, ..#FROM, ..#TO)), late_","_tie_","_early, "requests by AnsweredAt else RaisedAt, then ID")
}

/// A refused turn is not one of the turns; a queued and a running one are. DecisionChannel is the first Channel that is not empty among the decision's own usage rows,
/// and a usage row of another owner is not read.
Method TestTurnsAndChannel()
{
	Set a = ..Session(), b = ..Session()
	Set mid = "2030-06-15T10:00:00Z"
	Set done = ..Keep(##class(OcuTalon.Test.Data.Fixture).Turn(a, mid, "done"))
	Set queued = ..Keep(##class(OcuTalon.Test.Data.Fixture).Turn(a, mid, "queued"))
	Set running = ..Keep(##class(OcuTalon.Test.Data.Fixture).Turn(a, mid, "running"))
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Turn(a, mid, "refused"))
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).NoteTurns(a, ..#FROM, ..#TO)), done_","_queued_","_running, "done, queued and running turns, not the refused one")
	Set decision = ..Keep(##class(OcuTalon.Test.Data.Fixture).Decision(a, "decide", mid))
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).DecisionChannel(decision, a, .sc), "", "a decision with no usage row has no channel")
	Do $$$AssertStatusOK(sc, "and the read is OK")
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(decision, a, {"Channel": ""})
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(decision, a, {"Channel": "mailbox"})
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(decision, a, {"Channel": "web"})
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).DecisionChannel(decision, a, .sc), "mailbox", "the first that is not empty")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).DecisionChannel(decision, b, .sc), "", "another session reads none of those rows")
	Do $$$AssertStatusOK(sc, "and the read is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).DecisionChannel("", a, .sc), "", "an empty decision Ref has no channel")
}

/// --- helpers ---
/// A fixture session, kept for the clean-up. Returns its Ref.
Method Session() As %String [ Private ]
{
	Set ..Count = ..Count + 1
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zznotes" _ ..Number _ "s" _ ..Count)
	Do ..Keep(ref)
	Quit ref
}

/// Records a fixture Ref for the clean-up and returns it.
Method Keep(ref As %String) As %String [ Private ]
{
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ ref
	Quit ref
}

/// A production check of the session on a production.
Method Check(session As %String, namespace As %String, production As %String) [ Private ]
{
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Check(session, namespace, production))
}

/// The Refs of the rows of a list, comma-separated.
Method RefsOf(rows As %ListOfObjects) As %String [ Private ]
{
	Set text = ""
	For i = 1:1:rows.Count() {
		Set text = text _ $Select(text = "": "", 1: ",") _ rows.GetAt(i).Ref
	}
	Quit text
}

}
