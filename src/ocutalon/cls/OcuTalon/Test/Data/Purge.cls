Include %cspBuild

/// Tests of the host's purge, OcuTalon.Data.Purge.Run (Story 30.7; AD-27, AD-17, DW-437). THROWAWAY STACKS AND CI ONLY (Rule 21): Retention.Purge and Run
/// delete the Turn, Delivery and Session rows of the whole namespace that are old enough, rows that these tests did not make. Every test works from one
/// clock, Now, and gives Run that clock, so no test waits; every row a test made is removed after the test, also after a failure (Fixture.Clean).
///   - TestTurnsReadNoPurgedDecision (matrix 1 to 3): after Retention.Purge, a turn 91 days old, its deliveries (a Telegram row with its kept text
///     included), decisions and usage and its idle session are gone; a turn 89 days old keeps its decisions and usage, so ShownDecisionRef, Ownership.TurnCost and ChatMessage.FromRow still read them;
///     with one now for both purges, a turn and a delivery at exactly the cutoff stay and those one second before go, and every kept turn's decisions
///     exist after the bridge's purge;
///   - TestSessionKeptWhileActiveOrCurrent (matrix 4 to 6): a session with a Turn, Delivery or Decision at or after the cutoff, or current through a
///     live CSP session, a pairing, an open approval, a watch, a pending reminder, a webhook (Story 35.3), a memory or a document, is kept; one with only an expired store entry, a finished approval
///     or a reminder that is not pending is purged; a young session is kept, whatever its rows;
///   - TestSessionRowsGoWithIt (matrix 23, DW-581): the GuideState, SimMessage, BreakFeedRun and finished Reminder rows and the conversation link of a
///     purged session go with it and the bridge's purge of the same run finds its AI session unlinked; the same rows of a kept session stay, and a
///     memory of a third, kept session is untouched;
///   - TestCurrentSessionLosesNoRows (matrix 23, U-308): a session that is current through an open approval request, a watch or a pending reminder
///     keeps its Session row and all five kinds of rows (GuideState, SimMessage, Reminder, BreakFeedRun and the conversation link), and the AI
///     session of its link stays linked, in a run that purges an idle session beside them;
///   - TestOnlyOwnTablesAndAuditKept (matrix 7): the approval and action entries of the IRIS audit log that name a purged session are still there, and
///     the purge's source names no system namespace, no audit class and no table but the OcuTalon_Data and OcuTalon_Bridge_Data ones, and deletes
///     only from Turn, Delivery, GuideState, SimMessage, Reminder, BreakFeedRun and Session, plus the one DropLinks call;
///   - TestBadArguments (matrix 8): a day count of 0, x, "" or 1.5 and a malformed now give an error status that names OcuTalon.Data.Purge.Run and
///     delete nothing;
///   - TestFarCutoffDeletesNothing: a day count whose cutoff falls before the calendar is OK and deletes nothing;
///   - TestRetentionPassesOneNowHostFirst (matrix 3): Retention.Purge calls the host part first and then the bridge part, both with the one now it took.
Class OcuTalon.Test.Data.Purge Extends %UnitTest.TestCase
{

/// The class under test.
Parameter PURGE = "OcuTalon.Data.Purge";

/// The private CSP session store of the tests.
Parameter STORE = "^OcuTalonTestPurgeStore";

/// One day, in seconds.
Parameter DAY = 86400;

/// The clock of the test: the UTC time at the start of each test.
Property Now As %String;

/// The Refs that the test's fixtures were recorded under, as a comma list.
Property Refs As %String(MAXLEN = "");

/// The owners whose conversation links, and the AI sessions whose rows, the test made, as lists.
Property Owners As %List;

Property AISessions As %List;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Now = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set ..Refs = ""
	Set ..Owners = ""
	Set ..AISessions = ""
	Set store = ..#STORE
	Kill @store
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Memory WHERE Ref %STARTSWITH 'ZzPurge'")
	If result.%SQLCODE < 0 Do $$$AssertEquals(result.%SQLCODE, 0, "the test's memory rows are removed: "_result.%Message)
	Set position = 0
	While $ListNext(..Owners, position, owner) {
		Do ##class(OcuTalon.Bridge.Purge).DropLinks(owner)
	}
	Set position = 0
	While $ListNext(..AISessions, position, id) {
		Do ##class(%AI.Agent.Session).%DeleteId(id)
		Kill ^OcuTalonBP.Unlinked(id)
	}
	Set store = ..#STORE
	Kill @store
	Quit $$$OK
}

/// Matrix 1 to 3 (the U-210 test). The decisions of a kept turn exist after the purge, and its cost is its usage.
Method TestTurnsReadNoPurgedDecision()
{
	Set old = ..Session(91)
	Set kept = ..Session(89)
	Set oldTurn = ..Turn(old, ..Ago(91 * ..#DAY), .oldDecisions)
	Set oldDelivery = ..Track(##class(OcuTalon.Test.Data.Fixture).Delivery(old, {"RecordedAt": (..Ago(91 * ..#DAY))}))
	Set oldTelegram = ..Track(##class(OcuTalon.Test.Data.Fixture).Delivery(old, {"Channel": "telegram", "Kind": "", "Text": "zz kept telegram text", "RecordedAt": (..Ago(91 * ..#DAY))}))
	Set keptTurn = ..Turn(kept, ..Ago(89 * ..#DAY), .keptDecisions)
	Set keptDelivery = ..Track(##class(OcuTalon.Test.Data.Fixture).Delivery(kept, {"RecordedAt": (..Ago(89 * ..#DAY))}))
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Retention).Purge(90), "Retention.Purge(90) is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Turn).RefIndexExists(oldTurn), 0, "the turn 91 days old is gone")
	Do $$$AssertEquals(..DeliveryCount(old), 0, "the deliveries of the turn 91 days old are gone")
	Do $$$AssertEquals(..DeliveryCount(old, oldTelegram), 0, "the Telegram row with its kept text among them")
	Do $$$AssertEquals(..DecisionsExist(oldDecisions), "0|0", "and its two decisions")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.Purge).UsageExists($List(oldDecisions, 1)) _ "|" _ ##class(OcuTalon.Test.Bridge.Purge).UsageExists($List(oldDecisions, 2)), "0|0", "and their usage")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(old), 0, "and the idle session 91 days old")
	Do $$$AssertEquals(##class(OcuTalon.Data.Turn).RefIndexExists(keptTurn), 1, "the turn 89 days old is kept")
	Do $$$AssertEquals(..DeliveryCount(kept), 1, "the delivery 89 days old is kept")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(kept), 1, "and its session")
	Do ..AssertReadable(keptTurn, "the turn 89 days old")
	Do $$$AssertNotEquals(oldDelivery _ keptDelivery, "", "the deliveries were made")

	// Matrix 3: one now for both purges. The session is young, so only the turn and the delivery are in question.
	Set cutoff = ..Cutoff()
	Set young = ..Session(0)
	Set atTurn = ..Turn(young, cutoff, .atDecisions)
	Set beforeTurn = ..Turn(young, ##class(OcuTalon.Bridge.Time).PlusSeconds(cutoff, -1), .beforeDecisions)
	Do ##class(OcuTalon.Test.Data.Fixture).Delivery(young, {"RecordedAt": (cutoff), "ChannelMessageId": "zzat"})
	Do ##class(OcuTalon.Test.Data.Fixture).Delivery(young, {"RecordedAt": (##class(OcuTalon.Bridge.Time).PlusSeconds(cutoff, -1)), "ChannelMessageId": "zzbefore"})
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Purge).Run(90, ..Now), "the bridge's purge at now is OK")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Purge).Run(90, ..Now, ..#STORE), "and the host's purge at the same now")
	Do $$$AssertEquals(##class(OcuTalon.Data.Turn).RefIndexExists(atTurn), 1, "the turn created at the cutoff stays")
	Do $$$AssertEquals(##class(OcuTalon.Data.Turn).RefIndexExists(beforeTurn), 0, "the turn one second before it goes")
	Do $$$AssertEquals(..DeliveryCount(young, "zzat"), 1, "the delivery recorded at the cutoff stays")
	Do $$$AssertEquals(..DeliveryCount(young, "zzbefore"), 0, "the delivery one second before it goes")
	Do $$$AssertEquals(..DecisionsExist(atDecisions), "1|1", "the decisions of the turn at the cutoff exist after the bridge's purge")
	Do $$$AssertEquals(..DecisionsExist(beforeDecisions), "0|0", "and those of the turn one second before it do not")
	Do ..AssertReadable(atTurn, "the turn at the cutoff")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(young), 1, "the young session stays")
}

/// Matrix 4 to 6. One old session per signal; the purge keeps the ones with activity at or after the cutoff and the current ones.
Method TestSessionKeptWhileActiveOrCurrent()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set store = ..#STORE
	Set cutoff = ..Cutoff()
	Set recent = ..Ago(10 * ..#DAY)
	Set keys = ##class(OcuTalon.Data.Ownership).#SESSIONKEY
	// 1: kept
	Set keep("a Turn after the cutoff") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Turn", keep("a Turn after the cutoff"), recent))
	Set keep("a Turn at the cutoff") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Turn", keep("a Turn at the cutoff"), cutoff))
	Set keep("a Delivery after the cutoff") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Delivery", keep("a Delivery after the cutoff"), {"RecordedAt": (recent)}))
	Set keep("a Delivery at the cutoff") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Delivery", keep("a Delivery at the cutoff"), {"RecordedAt": (cutoff)}))
	Set keep("a Decision after the cutoff") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Decision", keep("a Decision after the cutoff"), "decide", recent))
	Set keep("a Decision at the cutoff") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Decision", keep("a Decision at the cutoff"), "decide", cutoff))
	Set keep("a live CSP session") = ..Session(91)
	Set @store@(1) = ..Stored(..Seconds() + 3600)
	Set @store@(1, 0, keys) = keep("a live CSP session")
	Set keep("a pairing") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Pairing", keep("a pairing")))
	Set keep("a pending approval") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Approval", keep("a pending approval"), "", "pending"))
	Set keep("an approved approval") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Approval", keep("an approved approval"), "", "approved"))
	Set keep("an executing approval") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Approval", keep("an executing approval"), "", "executing"))
	Set keep("a watch") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Check", keep("a watch")))
	Set keep("a webhook") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Webhook", keep("a webhook"), "zz purge webhook "_$Random(1000000)))
	Set keep("a pending reminder") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Reminder", keep("a pending reminder"), "2030-01-01T10:00:00Z", "pending"))
	Set keep("a memory") = ..Session(91)
	Do ..Memory(keep("a memory"))
	Set keep("a document") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Document", keep("a document"), "zzpurge.md"))
	// 5: purged
	Set purge("no row at all") = ..Session(91)
	Set purge("only an expired store entry") = ..Session(91)
	Set @store@(2) = ..Stored(..Seconds() - 100)
	Set @store@(2, 0, keys) = purge("only an expired store entry")
	Set purge("only a done approval") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Approval", purge("only a done approval"), "", "done"))
	Set purge("only a failed approval") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Approval", purge("only a failed approval"), "", "failed"))
	Set purge("only a fired reminder") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Reminder", purge("only a fired reminder"), "2030-01-01T10:00:00Z", "fired"))
	Set purge("only a cancelled reminder") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Reminder", purge("only a cancelled reminder"), "2030-01-01T10:00:00Z", "cancelled"))
	Set purge("only a Turn before the cutoff") = ..Session(91)
	Do ..Turn(purge("only a Turn before the cutoff"), ..Ago(91 * ..#DAY), .unused)
	// 6: never by age alone
	Set young = ..Session(0)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Purge).Run(90, ..Now, ..#STORE), "the purge is OK")
	Set name = ""
	For {
		Set name = $Order(keep(name))
		Quit:name=""
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(keep(name)), 1, "a session with "_name_" is kept")
	}
	Set name = ""
	For {
		Set name = $Order(purge(name))
		Quit:name=""
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(purge(name)), 0, "a session with "_name_" is purged")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(young), 1, "a session created after the cutoff with no rows is kept")
}

/// Matrix 23 (DW-581). The rows that only a purged session owns go with it, and its conversation links with them; a kept session's rows stay.
Method TestSessionRowsGoWithIt()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set gone = ..Session(91)
	Set kept = ..Session(91)
	Set third = ..Session(91)
	Do ..Rows(gone)
	Do ..Rows(kept)
	Do ..Track($ClassMethod(fixture, "Reminder", kept, "2030-01-01T10:00:00Z", "pending"))
	Do ..Memory(third)
	Set goneAI = ..Linked(gone)
	Set keptAI = ..Linked(kept)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Retention).Purge(90), "Retention.Purge(90) is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(gone), 0, "the idle session is gone")
	Do $$$AssertEquals(..OwnedRows(gone), "0|0|0|0|0", "and so are its GuideState, SimMessage, fired and cancelled Reminder and BreakFeedRun rows and its link")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(kept), 1, "the session with a pending reminder is kept")
	Do $$$AssertEquals(..OwnedRows(kept), "1|1|3|1|1", "and so are its rows (the pending reminder too) and its link")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(third), 1, "the session with a memory is kept")
	Do $$$AssertEquals(..MemoryCount(third), 1, "and its memory is untouched")
	Do $$$AssertEquals($Data(^OcuTalonBP.Unlinked(goneAI)) > 0, 1, "the bridge's purge of the same run found the purged session's AI session unlinked")
	Do $$$AssertEquals($Data(^OcuTalonBP.Unlinked(keptAI)), 0, "and the kept session's AI session linked")
}

/// Matrix 23, U-308 (owner decision "Keep"). A session that is current through an open approval request, a watch or a pending reminder is never purged, so
/// it loses none of its rows: its GuideState, SimMessage, fired and cancelled Reminder and BreakFeedRun rows and its conversation link all stay and its AI
/// session stays linked. An idle session in the same run goes with its rows, so the run did purge.
Method TestCurrentSessionLosesNoRows()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set gone = ..Session(91)
	Do ..Rows(gone)
	Set goneAI = ..Linked(gone)
	Set kept("an open approval") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Approval", kept("an open approval"), "", "pending"))
	Set kept("a watch") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Check", kept("a watch")))
	Set kept("a pending reminder") = ..Session(91)
	Do ..Track($ClassMethod(fixture, "Reminder", kept("a pending reminder"), "2030-01-01T10:00:00Z", "pending"))
	Set signal = ""
	For {
		Set signal = $Order(kept(signal))
		Quit:signal=""
		Do ..Rows(kept(signal))
		Set keptAI(signal) = ..Linked(kept(signal))
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Retention).Purge(90), "Retention.Purge(90) is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(gone), 0, "the idle session is gone")
	Do $$$AssertEquals(..OwnedRows(gone), "0|0|0|0|0", "with its five kinds of rows")
	Do $$$AssertEquals($Data(^OcuTalonBP.Unlinked(goneAI)) > 0, 1, "and its AI session is found unlinked")
	Set signal = ""
	For {
		Set signal = $Order(kept(signal))
		Quit:signal=""
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(kept(signal)), 1, "the session with "_signal_" is kept")
		Do $$$AssertEquals(..OwnedRows(kept(signal)), "1|1|"_$Select(signal = "a pending reminder": 3, 1: 2)_"|1|1", "and loses none of its GuideState, SimMessage, Reminder and BreakFeedRun rows and its link ("_signal_")")
		Do $$$AssertEquals($Data(^OcuTalonBP.Unlinked(keptAI(signal))), 0, "its AI session stays linked ("_signal_")")
	}
}

/// Matrix 7. The audit entries of a purged session stay; the purge touches only OcuTalon's own tables.
Method TestOnlyOwnTablesAndAuditKept()
{
	Set session = ..Session(91)
	Set marker = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set approval = {"ref": (marker), "kind": "fix", "change": "answered", "from": "pending", "to": "approved", "outcome": "", "target": "", "ownerRef": (session), "irisUser": "zzpurge", "sessionRef": (session), "channel": "web"}
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Audit).Record("Approval", approval), "an Approval entry that names the session is written")
	Set action = {"action": "zz_tool", "target": "zz", "result": "ok", "counts": {}, "approvalRef": (marker), "irisUser": "zzpurge", "sessionRef": (session), "channel": "web"}
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Audit).Record("Action", action), "and an Action entry")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Approval", "Approval", marker).%Size(), 1, "the Approval entry is found before the purge")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", marker).%Size(), 1, "and the Action entry")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Purge).Run(90, ..Now, ..#STORE), "the purge is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(session), 0, "the session is gone")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Approval", "Approval", marker).%Size(), 1, "the Approval entry is still in the IRIS audit log")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Action", "Action", marker).%Size(), 1, "and the Action entry")

	Set source = "OcuTalon.Test.Bridge.Source"
	Do $$$AssertStatusOK($ClassMethod(source, "Text", ..#PURGE, .text), "the purge has source")
	Do $$$AssertEquals($ClassMethod(source, "Matches", text, "%sys(?![a-z])"), 0, "its code names no system namespace")
	Do $$$AssertEquals($ClassMethod(source, "Matches", text, "audit"), 0, "and no audit class or table")
	Set tables = ""
	Set deletes = ""
	Set lines = $ClassMethod(source, "CodeLines", text)
	Set position = 0
	While $ListNext(lines, position, line) {
		Set start = 1
		While $Locate(line, "(?i)\b(?:from|join) [A-Za-z_]+(?:\.[A-Za-z_]+)+", start, after, found) {
			Set tables = tables _ $ListBuild($Piece(found, " ", 2))
			Set start = after
		}
		Set start = 1
		While $Locate(line, "(?i)\bdelete from [A-Za-z_]+(?:\.[A-Za-z_]+)+", start, after, found) {
			Set deletes = deletes _ $ListBuild($Piece(found, " ", 3))
			Set start = after
		}
		Set start = 1
		While $Locate(line, "(?i)##class\([A-Za-z.]+\)\.%DeleteId", start, after, found) {
			Set deletes = deletes _ $ListBuild($Piece($Piece(found, "(", 2), ")", 1))
			Set start = after
		}
		Set start = 1
		While $Locate(line, "##class\([A-Za-z.]+\)\.DropLinks", start, after, found) {
			Set deletes = deletes _ $ListBuild($Piece($Piece(found, "(", 2), ")", 1)_".DropLinks")
			Set start = after
		}
		Set start = 1
		While $Locate(line, "(?i)##class\([%A-Za-z0-9.]+\)", start, after, found) {
			Set class = $Piece($Piece(found, "(", 2), ")", 1)
			Do $$$AssertTrue($ListFind($ListBuild("%SQL.Statement", "OcuTalon.Bridge.Time", "OcuTalon.Bridge.Purge", "OcuTalon.Data.Session", "OcuTalon.Data.Ownership"), class), "the purge calls no class but SQL, Bridge.Time, Bridge.Purge, Data.Session and Data.Ownership: "_class)
			Set start = after
		}
	}
	Do $$$AssertEquals($ClassMethod(source, "Matches", text, "\$(?:classmethod|method|zobjclassmethod|zobjmethod)\(|\bxecute\b"), 0, "and makes no dynamic call, so no other class's method can delete rows")
	Do $$$AssertTrue($ListLength(tables) > 0, "the scan found the tables the purge names")
	Set position = 0
	While $ListNext(tables, position, table) {
		Do $$$AssertTrue($Extract(table, 1, 14) = "OcuTalon_Data." || ($Extract(table, 1, 21) = "OcuTalon_Bridge_Data."), "the table "_table_" is an OcuTalon_Data or OcuTalon_Bridge_Data table")
	}
	Set expected = $ListBuild("OcuTalon_Data.Turn", "OcuTalon_Data.Delivery", "OcuTalon_Data.GuideState", "OcuTalon_Data.SimMessage", "OcuTalon_Data.BreakFeedRun", "OcuTalon_Data.Reminder", "OcuTalon.Bridge.Purge.DropLinks", "OcuTalon.Data.Session")
	Do $$$AssertEquals(..Sorted(deletes), ..Sorted(expected), "it deletes only from Turn, Delivery, GuideState, SimMessage, BreakFeedRun and Reminder (SQL) and Session (%DeleteId), and drops links through DropLinks")
}

/// Matrix 8. A bad day count or a malformed now is an error that names the method, and nothing is deleted.
Method TestBadArguments()
{
	Set old = ..Session(91)
	Set oldTurn = ..Turn(old, ..Ago(91 * ..#DAY), .decisions)
	For days = 0, "x", "", 1.5, -1 {
		Set sc = ##class(OcuTalon.Data.Purge).Run(days, ..Now, ..#STORE)
		Do $$$AssertStatusNotOK(sc, "a day count of '"_days_"' is an error")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Data.Purge.Run", "and it names OcuTalon.Data.Purge.Run")
	}
	For now = "2026-13-45T10:00:00Z", "yesterday", "2026-11-02 10:00:00", "2026-11-02T25:00:00Z" {
		Set sc = ##class(OcuTalon.Data.Purge).Run(90, now, ..#STORE)
		Do $$$AssertStatusNotOK(sc, "a now of '"_now_"' is an error")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Data.Purge.Run", "and it names OcuTalon.Data.Purge.Run")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Turn).RefIndexExists(oldTurn), 1, "the turn is still there")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(old), 1, "and so is the session")
	Do $$$AssertEquals(..DecisionsExist(decisions), "1|1", "and the decisions")
}

/// A day count so large that the cutoff falls before the calendar deletes nothing, and is not an error.
Method TestFarCutoffDeletesNothing()
{
	Set old = ..Session(91)
	Set oldTurn = ..Turn(old, ..Ago(91 * ..#DAY), .decisions)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Purge).Run(1000000, ..Now, ..#STORE), "a day count of 1000000 is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Turn).RefIndexExists(oldTurn), 1, "the old turn is still there")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(old), 1, "and so is the old session")
	Do $$$AssertEquals(..DecisionsExist(decisions), "1|1", "and the decisions")
}

/// Matrix 3, through the Retention area: its Purge calls the host part first and then the bridge part, each with the one now that it took, so that
/// both parts use one cutoff and the links the host part drops are found unlinked by the bridge part of the same run.
Method TestRetentionPassesOneNowHostFirst()
{
	Set source = "OcuTalon.Test.Bridge.Source"
	Do $$$AssertStatusOK($ClassMethod(source, "Text", "OcuTalon.Install.Step.Retention", .text), "the Retention area has source")
	Set lines = $ClassMethod(source, "Lines", text, "purge\)\.run\(")
	Do $$$AssertEquals($ListLength(lines), 2, "its code calls two purges")
	Do $$$AssertTrue($Locate($ListGet(lines, 1), "(?i)OcuTalon\.Data\.Purge\)\.Run\(daysToKeep, now\)"), "the first is the host part, with the now it took")
	Do $$$AssertTrue($Locate($ListGet(lines, 2), "(?i)OcuTalon\.Bridge\.Purge\)\.Run\(daysToKeep, now\)"), "and the second the bridge part, with the same now")
}

/// --- helpers ---
/// The cutoff of a 90-day purge at the clock of the test.
Method Cutoff() As %String
{
	$$$ThrowOnError(##class(OcuTalon.Bridge.Time).DaysCutoff(90, "OcuTalon.Test.Data.Purge", .cutoff, ..Now))
	Quit cutoff
}

/// The UTC time that many seconds before the clock of the test.
Method Ago(seconds As %Integer) As %String
{
	Quit ##class(OcuTalon.Bridge.Time).PlusSeconds(..Now, -seconds)
}

/// The seconds of the clock, as the CSP session store counts them.
ClassMethod Seconds() As %Integer
{
	Set stamp = $ZTimeStamp
	Quit ($Piece(stamp, ",") * 86400 + $Piece(stamp, ",", 2)) \ 1
}

/// The stored list of a CSP session, as the store keeps it, with the timeout at the position sesOldTimeout.
ClassMethod Stored(timeout As %Integer) As %List
{
	Set stored = ""
	For position = 1:1:$$$sesOldTimeout - 1 {
		Set stored = stored_$ListBuild("")
	}
	Quit stored_$ListBuild(timeout)
}

/// Records the Ref for the clean-up and returns it.
Method Track(ref As %String) As %String
{
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ ref
	Quit ref
}

/// A session row created that many days before the clock of the test.
Method Session(days As %Integer) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzpurge")
	Do ..Track(ref)
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set row.CreatedAt = ..Ago(days * ..#DAY)
	$$$ThrowOnError(row.%Save())
	Quit ref
}

/// A turn of the session created at the time, with a triage decision and a reply decision recorded then, and a usage row for each. decisions is
/// the list of the two decisions' Refs.
Method Turn(session As %String, at As %String, Output decisions As %List) As %String
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set triage = ..Track($ClassMethod(fixture, "Decision", session, "triage", at))
	Set reply = ..Track($ClassMethod(fixture, "Decision", session, "reply", at))
	Do ..Track($ClassMethod(fixture, "Usage", triage, session, {"RecordedAt": (at), "InputTokens": 100, "OutputTokens": 10, "CostUSD": 0.001}))
	Do ..Track($ClassMethod(fixture, "Usage", reply, session, {"RecordedAt": (at), "InputTokens": 50, "OutputTokens": 5, "CostUSD": 0.0005}))
	Set ref = ..Track($ClassMethod(fixture, "Turn", session, at))
	Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(ref)
	Set row.TriageDecisionRef = triage
	Set row.TurnDecisionRef = reply
	$$$ThrowOnError(row.%Save())
	Set decisions = $ListBuild(triage, reply)
	Quit ref
}

/// A GuideState, a SimMessage, a fired and a cancelled Reminder and a BreakFeedRun of the session, and its conversation link.
Method Rows(ref As %String)
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Do ..Track($ClassMethod(fixture, "GuideState", ref))
	Do ..Track($ClassMethod(fixture, "SimMessage", ref))
	Do ..Track($ClassMethod(fixture, "Reminder", ref, "2030-01-01T10:00:00Z", "fired"))
	Do ..Track($ClassMethod(fixture, "Reminder", ref, "2030-01-01T10:00:00Z", "cancelled"))
	Do ..Track($ClassMethod(fixture, "BreakFeedRun", ref))
}

/// A conversation link of the owner to a new AI session; the AI session's id.
Method Linked(owner As %String) As %String
{
	Set session = ##class(%AI.Agent.Session).%New()
	Set session.CreatedAt = $Translate($Extract(..Ago(5 * ..#DAY), 1, 19), "T", " ")
	Set session.Model = "zz-purge"
	Do session.ContextData.Write("{""zz"":""purge""}")
	$$$ThrowOnError(session.%Save())
	Set id = session.%Id()
	Set ..AISessions = ..AISessions _ $ListBuild(id)
	Set ..Owners = ..Owners _ $ListBuild(owner)
	$$$ThrowOnError(##class(OcuTalon.Bridge.Data.ConversationLink).Point(owner, "ZzPurgeAgent", id))
	Quit id
}

/// A memory of the session, which the test removes (its Ref starts with ZzPurge).
Method Memory(ref As %String)
{
	Set row = ##class(OcuTalon.Data.Memory).%New()
	Set row.Ref = "ZzPurgeM"_$Increment(^OcuTalonTest("PurgeMemory"))
	Set row.SessionRef = ref
	Set row.Text = "zz memory"
	$$$ThrowOnError(row.%Save())
}

/// The number of memories of the session.
ClassMethod MemoryCount(ref As %String) As %Integer
{
	Quit ..Count("SELECT COUNT(*) FROM OcuTalon_Data.Memory WHERE SessionRef = ?", ref)
}

/// The counts of the session's GuideState, SimMessage, Reminder (fired and cancelled), BreakFeedRun rows and conversation links, as "a|b|c|d|e".
ClassMethod OwnedRows(ref As %String) As %String
{
	Quit ..Count("SELECT COUNT(*) FROM OcuTalon_Data.GuideState WHERE SessionRef = ?", ref) _ "|" _ ..Count("SELECT COUNT(*) FROM OcuTalon_Data.SimMessage WHERE SessionRef = ?", ref) _ "|" _ ..Count("SELECT COUNT(*) FROM OcuTalon_Data.Reminder WHERE SessionRef = ?", ref) _ "|" _ ..Count("SELECT COUNT(*) FROM OcuTalon_Data.BreakFeedRun WHERE SessionRef = ?", ref) _ "|" _ ..Count("SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ConversationLink WHERE OwnerRef = ?", ref)
}

/// The first column of the one row that the query returns for the argument.
ClassMethod Count(sql As %String, arg As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, sql, arg)
	If result.%SQLCODE < 0 Throw ##class(%Exception.General).%New("Purge", 5001, , "SQLCODE "_result.%SQLCODE_" "_result.%Message)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The list with its members in order, to compare lists whatever their order.
ClassMethod Sorted(list As %List) As %String
{
	Kill set
	Set position = 0
	While $ListNext(list, position, member) {
		Set set(member) = ""
	}
	Set text = ""
	Set member = ""
	For {
		Set member = $Order(set(member))
		Quit:member=""
		Set text = text _ member _ ";"
	}
	Quit text
}

/// "1|0" style: whether each of the two decisions of the list exists.
ClassMethod DecisionsExist(decisions As %List) As %String
{
	Quit ##class(OcuTalon.Bridge.Data.Decision).RefIndexExists($List(decisions, 1)) _ "|" _ ##class(OcuTalon.Bridge.Data.Decision).RefIndexExists($List(decisions, 2))
}

/// The number of Delivery rows of the owner, of the one message when channelMessageId is given.
ClassMethod DeliveryCount(owner As %String, channelMessageId As %String = "") As %Integer
{
	If channelMessageId = "" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE OwnerRef = ?", owner)
	} Else {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND ChannelMessageId = ?", owner, channelMessageId)
	}
	If result.%SQLCODE < 0 Throw ##class(%Exception.General).%New("Purge", 5001, , "SQLCODE "_result.%SQLCODE_" "_result.%Message)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// What the readers of a kept turn show (U-210): the shown decision exists, TurnCost is the sum of the turn's two usage rows, and the live payload of
/// the row carries the decision and the cost.
Method AssertReadable(turnRef As %String, label As %String)
{
	Set turn = ##class(OcuTalon.Data.Turn).RefIndexOpen(turnRef)
	Do $$$AssertTrue($IsObject(turn), label_" is there")
	If '$IsObject(turn) Quit
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.Decision).RefIndexExists(turn.ShownDecisionRef()), 1, label_": ShownDecisionRef names an existing decision")
	Set cost = ##class(OcuTalon.Data.Ownership).TurnCost(turnRef, .sc)
	Do $$$AssertStatusOK(sc, label_": TurnCost is read")
	Do $$$AssertEquals(cost.inputTokens _ "|" _ cost.outputTokens, "150|15", label_": TurnCost equals the usage sums, not 0")
	Set payload = ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(turn)
	Do $$$AssertTrue($IsObject(payload.Decision) && (payload.Decision.Ref = turn.ShownDecisionRef()), label_": ChatMessage.FromRow carries the decision")
	Do $$$AssertTrue($IsObject(payload.TurnCost) && (payload.TurnCost.InputTokens = 150), label_": and the cost")
}

}
