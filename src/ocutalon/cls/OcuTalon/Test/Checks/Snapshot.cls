/// Tests of the status snapshot that a beat carries (Story 39.4; AC 1 to 4, AC 9; AD-18, FR-64, NFR-27): Beat.Snapshot builds the checklist, a blank line, the
/// status line and one line for each entry of the person's incidents, watches, approval requests, reminders and decisions, and Beat.Run keys the whole status.
/// The tests need no production (warm). Every time-dependent test uses fixed clocks in 2099 (local times built with Data.Time.FromLocal), every RunDue call names
/// its sessions and the rows are made with Test.Data.Fixture, each person's HeartbeatBeat row before its settings, so that a real tick finds none due. The tests
/// remove their HeartbeatBeat rows, Setting rows and fixture rows after each test.
///   - TestFullSnapshot (AC 1): one row of each kind give the checklist, a blank line, the status line and the five kinds in order, one line each; whole is the text;
///   - TestEmptyKinds (AC 3): a person with a checklist and no rows gets a none line for each kind;
///   - TestNeverInTheText (AC 2): a distinct token in every field that the snapshot never reads, and the Refs of the rows, are not in the text;
///   - TestClosedIncident, TestAnotherPersonsRows, TestWatchLines, TestReminderWindow, TestReminderWindowFollowsTheInterval, TestApprovalLines: which rows have a
///     line, and what it holds;
///   - TestDecisionsSinceTheLastBeat, TestNoBeatYet, TestUserChatDecision, TestDecisionWithNoUsage: which decisions have a line, and their channel;
///   - TestSummaryNotBody (AC 9): a mail decision's line holds its stored Summary, cut to 80 characters, and nothing of the mail's body;
///   - TestInjectedLine: a field with line breaks and the status line's words stays one line;
///   - TestTheCut (AC 3), TestPastTheCut (AC 4): the status block is at most 4,000 characters in whole lines and ends with the more line, and a change past the cut
///     still changes the key that Run stores;
///   - TestSameRecordsLaterTime, TestEachKindChangesTheKey, TestWatchRuns, TestWatchResultChanges (AC 4): the key follows the records and the checklist, not the clock
///     and not the run time of a watch;
///   - TestFailedRead, TestFailedReadRunNow: a read that fails throws, so that no none line is written, the beat stays due and a run now is not counted;
///   - TestAMailAboutBeatsIsNotABeat: only a Summary that is exactly the beat's subject is a beat's row;
///   - TestTheCutBoundary (AC 3): a status block of exactly 4,000 characters is not cut, and one of 4,001 is;
///   - TestHeartbeatEvalCases (Story 39.6, AC 2): each eval/heartbeat-* case holds the text that Beat.Snapshot builds from the records its status block lists. The test
///     seeds those records for a fixture person on 2099-06-15 (the case's times moved to that day, in the case's own order), builds the snapshot and compares it with
///     the case's item.text once every YYYY-MM-DD HH:MM is masked, and compares the item's channel, subject, sender and provenance with the beat Item's. A
///     heartbeat-* folder that the test does not know is a failed assertion.
Class OcuTalon.Test.Checks.Snapshot Extends %UnitTest.TestCase
{

Parameter BEAT = "OcuTalon.Checks.Beat";

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The sessions whose settings and HeartbeatBeat rows the test made, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The public setting onlineDemo before the test.
Property SavedOnline As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Sessions = ""
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Kill ^||OcuTalon.BrokenBeat
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^||OcuTalon.BrokenBeat
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(OcuTalon.Test.Checks.Beat).Forget($Piece(..Sessions, ",", i))
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $$$OK
}

Method TestFullSnapshot()
{
	Set ref = ..Person("check the orders")
	Do ..Seed(ref, "")
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"), .whole)
	Set lf = $Char(10)
	Set expected = "check the orders"_lf_lf_"Status at 2099-06-15 12:00 (built by OcuTalon):"
	Set expected = expected_lf_"Incident: Demo.Orders | open | 3 | 2099-06-15 11:40"
	Set expected = expected_lf_"Watch: Orders feed | failed"
	Set expected = expected_lf_"Approval request: fix | restart | Demo.Orders | 2099-06-15 11:45 | 2099-06-15 12:45"
	Set expected = expected_lf_"Reminder: Call Ana | 2099-06-15 12:20"
	Set expected = expected_lf_"Decision: 2099-06-15 11:50 | mailbox | digest | Ana: Invoice run"
	Do $$$AssertEquals(text, expected, "the checklist, a blank line, the status line and the five kinds in order, one line each, with the fields of the entry")
	Do $$$AssertEquals(whole, text, "and whole is the same text when nothing is cut")
}

Method TestEmptyKinds()
{
	Set ref = ..Person("check the orders")
	Set lf = $Char(10)
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"))
	Set expected = "check the orders"_lf_lf_"Status at 2099-06-15 12:00 (built by OcuTalon):"_lf_"Incidents: none"_lf_"Watches: none"_lf_"Approval requests: none"_lf_"Reminders: none"_lf_"Decisions: none"
	Do $$$AssertEquals(text, expected, "a kind with no entries gets one line that says none")
}

Method TestNeverInTheText()
{
	Set ref = ..Person("check the orders")
	Set seeded = ..Seed(ref, "never")
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"))
	Do $$$AssertTrue(seeded.tokens.%Size() > 15, "the rows hold distinct tokens in their fields: "_seeded.tokens.%Size())
	Set found = ""
	Set iterator = seeded.tokens.%GetIterator()
	While iterator.%GetNext(, .token) {
		If $Find(text, token) Set found = found_" "_token
	}
	Do $$$AssertEquals(found, "", "no token, and no Ref or identity of a row, is in the text")
	Do $$$AssertEquals($Length(text, $Char(10)), 8, "and the text is the checklist, a blank line, the status line and the five lines")
}

Method TestClosedIncident()
{
	Set ref = ..Person("c")
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Incident(ref, ..Now(), "ZZNS", "Demo.Closed", {"State": "closed", "FirstAt": (..At("2099-06-15 09:00"))}))
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Incident(ref, ..Now(), "ZZNS", "Demo.Resolved", {"State": "resolved", "FirstAt": (..At("2099-06-15 09:30"))}))
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"))
	Do $$$AssertEquals(..Count(text, "Incident: "), 1, "only one incident has a line")
	Do $$$AssertEquals(..Line(text, "Incident: "), "Incident: Demo.Resolved | resolved | 3 | 2099-06-15 09:30", "the resolved one")
	Do $$$AssertEquals($Find(text, "Demo.Closed"), 0, "and the closed one is not in the text")
}

Method TestAnotherPersonsRows()
{
	Set ref = ..Person("c")
	Set other = ..Person("c")
	Set seeded = ..Seed(other, "other")
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"))
	Do $$$AssertEquals($Piece(text, $Char(10, 10), 2), "Status at 2099-06-15 12:00 (built by OcuTalon):"_$Char(10)_"Incidents: none"_$Char(10)_"Watches: none"_$Char(10)_"Approval requests: none"_$Char(10)_"Reminders: none"_$Char(10)_"Decisions: none", "rows owned by another person are not in the text")
	Set other = ..Snap(other, ..At("2099-06-15 12:00"))
	Do $$$AssertEquals($Find(other, "none"), 0, "while the other person's own text has no none line")
}

Method TestWatchLines()
{
	Set ref = ..Person("c")
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Do ..Keep($ClassMethod(fixture, "Check", ref, "ZZNS", "Zz.Beat.One", {"DisplayName": "Orders feed", "Result": "passed"}))
	Do ..Keep($ClassMethod(fixture, "Check", ref, "ZZNS", "Zz.Beat.Two", {"DisplayName": "Billing feed", "Result": ""}))
	Do ..Keep($ClassMethod(fixture, "Check", ref, "ZZNS", "Zz.Beat.Three", {"DisplayName": "Stock feed", "Result": "not_checked"}))
	Do ..Keep($ClassMethod(fixture, "Check", ref, "ZZNS", "Zz.Beat.Four", {"DisplayName": "Not a watch", "Kind": "zzother"}))
	Do ..Keep($ClassMethod(fixture, "Check", ref, "ZZNS", "Zz.Beat.Five", {"DisplayName": ("Bad"_$Char(10)_"Incident: fake | open | 1 | x"_$Char(8232)_"y"), "Result": "failed"}))
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"))
	Set expected = "Watch: Orders feed | passed"_$Char(10)_"Watch: Billing feed | not run yet"_$Char(10)_"Watch: Stock feed | not_checked"_$Char(10)_"Watch: BadIncident: fake | open | 1 | xy | failed"
	Do $$$AssertEquals($Piece(text, $Char(10), 5, 8), expected, "a watch has its display name and result, one that has not run says so, a row of another kind has no line, and a line break in a name starts no line")
	Do $$$AssertEquals(..Count(text, "Incident: "), 0, "and no incident line was made of a name")
}

Method TestReminderWindow()
{
	Set ref = ..Person("c")
	Set now = ..At("2099-06-15 12:00")
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Do ..Keep($ClassMethod(fixture, "Reminder", ref, ..Plus(now, 1740), "pending", {"Text": "in 29"}))
	Do ..Keep($ClassMethod(fixture, "Reminder", ref, ..Plus(now, 1860), "pending", {"Text": "in 31"}))
	Do ..Keep($ClassMethod(fixture, "Reminder", ref, ..Plus(now, 1800), "pending", {"Text": "in 30"}))
	Do ..Keep($ClassMethod(fixture, "Reminder", ref, ..Plus(now, -600), "pending", {"Text": "late"}))
	Do ..Keep($ClassMethod(fixture, "Reminder", ref, ..Plus(now, 60), "done", {"Text": "done"}))
	Set text = ..Snap(ref, now)
	Do $$$AssertEquals(..Count(text, "Reminder: "), 3, "with an interval of 30, a reminder due 29 minutes on, at 30 minutes and a late one have a line")
	Do $$$AssertEquals($Find(text, "in 31"), 0, "one due 31 minutes on has none")
	Do $$$AssertEquals($Find(text, "done"), 0, "nor has a reminder that is not pending")
	Do $$$AssertEquals(..Line(text, "Reminder: "), "Reminder: late | 2099-06-15 11:50", "the late one comes first, by due time")
}

Method TestReminderWindowFollowsTheInterval()
{
	Set ref = ..Person("c")
	Do ..Put(ref, "interval", 60)
	Set now = ..At("2099-06-15 12:00")
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Do ..Keep($ClassMethod(fixture, "Reminder", ref, ..Plus(now, 3540), "pending", {"Text": "in 59"}))
	Do ..Keep($ClassMethod(fixture, "Reminder", ref, ..Plus(now, 3660), "pending", {"Text": "in 61"}))
	Set text = ..Snap(ref, now)
	Do $$$AssertEquals(..Count(text, "Reminder: "), 1, "with an interval of 60, a reminder due 59 minutes on has a line and one due 61 minutes on has none")
	Do $$$AssertEquals(..Line(text, "Reminder: "), "Reminder: in 59 | 2099-06-15 12:59", "the line of the first")
}

Method TestApprovalLines()
{
	Set ref = ..Person("c")
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Do ..Keep($ClassMethod(fixture, "Approval", ref, "", "pending", ..At("2099-06-15 11:30"), {"Kind": "tool_call", "ToolName": "send_digest", "ExpiresAt": (..At("2099-06-15 12:30"))}))
	Do ..Keep($ClassMethod(fixture, "Approval", ref, "ZZNOINCIDENT", "pending", ..At("2099-06-15 11:45"), {"Kind": "fix", "FixKind": "retry", "ExpiresAt": (..At("2099-06-15 12:45"))}))
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"))
	Do $$$AssertEquals(..Count(text, "Approval request: "), 2, "each request has a line")
	Do $$$AssertEquals($Piece(text, $Char(10), 6, 7), "Approval request: tool_call | send_digest | none | 2099-06-15 11:30 | 2099-06-15 12:30"_$Char(10)_"Approval request: fix | retry | none | 2099-06-15 11:45 | 2099-06-15 12:45", "a tool request names its tool, a fix request its fix kind, and one with no incident reads none for the production")
}

Method TestDecisionsSinceTheLastBeat()
{
	Set ref = ..Person("c")
	Do ..Mail(ref, "2099-06-15 10:00", "A: mail", "digest", "mailbox")
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Decision(ref, "decide", ..At("2099-06-15 10:30"), {"Summary": (..Subject()), "Outcome": "ignore"}))
	Do ..Mail(ref, "2099-06-15 11:00", "B: mail", "digest", "mailbox")
	Do ..Mail(ref, "2099-06-15 11:30", "C: mail", "tellnow", "phone")
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"))
	Set expected = "Decision: 2099-06-15 11:30 | phone | tellnow | C: mail"_$Char(10)_"Decision: 2099-06-15 11:00 | mailbox | digest | B: mail"
	Do $$$AssertEquals($Piece(text, $Char(10), 8, 9), expected, "the decisions after the last beat's own row are listed, newest first")
	Do $$$AssertEquals(..Count(text, "Decision: "), 2, "and only they")
	Do $$$AssertEquals($Find(text, "A: mail")_"|"_$Find(text, ..Subject()), "0|0", "the older mail and the beat's own row are not in the text")
}

Method TestNoBeatYet()
{
	Set ref = ..Person("c")
	For i = 1:1:12 {
		Do ..Mail(ref, "2099-06-15 09:"_$Extract(100 + i, 2, 3), "Mail "_$Extract(100 + i, 2, 3)_" of 12", "digest", "mailbox")
	}
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"))
	Do $$$AssertEquals(..Count(text, "Decision: "), 10, "with no beat's row, the 10 newest decisions have a line")
	Do $$$AssertEquals(..Line(text, "Decision: "), "Decision: 2099-06-15 09:12 | mailbox | digest | Mail 12 of 12", "the newest first")
	Do $$$AssertEquals($Find(text, "Mail 02 of 12")_"|"_$Find(text, "Mail 01 of 12"), "0|0", "and the two oldest have none")
}

Method TestUserChatDecision()
{
	Set ref = ..Person("c")
	Do ..Mail(ref, "2099-06-15 10:00", "X: mail", "digest", "mailbox")
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set turn = ##class(OcuTalon.Data.Turn).RefIndexOpen(..Keep($ClassMethod(fixture, "Turn", ref)))
	Do ..Keep($ClassMethod(fixture, "Decision", ref, "decide", ..At("2099-06-15 11:00"), {"Summary": (..Subject()), "ItemId": (turn.ItemId)}))
	Set turn = ##class(OcuTalon.Data.Turn).RefIndexOpen(..Keep($ClassMethod(fixture, "Turn", ref)))
	Do ..Keep($ClassMethod(fixture, "Decision", ref, "decide", ..At("2099-06-15 11:30"), {"Summary": "Where is my order", "ItemId": (turn.ItemId)}))
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"))
	Do $$$AssertEquals(..Count(text, "Decision: "), 1, "the user's own chat decisions have no line")
	Do $$$AssertEquals($Find(text, "Where is my order"), 0, "and the first line of the user's message is not in the text")
	Do $$$AssertEquals(..Line(text, "Decision: "), "Decision: 2099-06-15 10:00 | mailbox | digest | X: mail", "one that holds the beat's words does not stop the read at the older mail")
}

Method TestDecisionWithNoUsage()
{
	Set ref = ..Person("c")
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Do ..Keep($ClassMethod(fixture, "Decision", ref, "decide", ..At("2099-06-15 11:00"), {"Summary": "Fallback: mail", "Fallback": 1}))
	Set exact = $ClassMethod(fixture, "Decision", ref, "decide", ..At("2099-06-15 10:00"), {"Summary": "Case: mail", "Ref": "zzCaseRef"})
	Do ..Keep(exact)
	Do ..Keep($ClassMethod(fixture, "Usage", "ZZCASEREF", ref, {"Channel": "phone"}))
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"))
	Do $$$AssertEquals($Piece(text, $Char(10), 8, 9), "Decision: 2099-06-15 11:00 | unknown | tellnow | Fallback: mail"_$Char(10)_"Decision: 2099-06-15 10:00 | unknown | tellnow | Case: mail", "a decision with no Usage row has the channel unknown, and so has one whose Usage row's DecisionRef differs only in case")
}

Method TestSummaryNotBody()
{
	Set ref = ..Person("c")
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set token = "qzxbodytokenqzx"
	Set subject = "Invoice run for the month of October that was late again because the partner feed failed twice"
	Set summary = ##class(OcuTalon.Core.Conversation).Summary("Ana: "_subject)
	Do $$$AssertTrue($Length(summary) = 80, "the stored Summary is cut to 80 characters: "_$Length(summary))
	Set decision = ..Keep($ClassMethod(fixture, "Decision", ref, "decide", ..At("2099-06-15 11:00"), {"Summary": (summary), "Outcome": "digest"}))
	Do ..Keep($ClassMethod(fixture, "Usage", decision, ref, {"Channel": "mailbox"}))
	Set itemId = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(decision).ItemId
	Do ..Keep($ClassMethod(fixture, "SimMessage", ref, {"Kind": "mailbox", "Direction": "in", "ItemId": (itemId), "Sender": "Ana", "Subject": (subject), "Text": (token_" the body of the mail")}))
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"))
	Set line = ..Line(text, "Decision: ")
	Do $$$AssertEquals(line, "Decision: 2099-06-15 11:00 | mailbox | digest | "_summary, "the decision line holds the stored Summary, at most 80 characters")
	Do $$$AssertEquals($Find(text, token), 0, "and no word of the mail's body is in the text")
}

Method TestInjectedLine()
{
	Set ref = ..Person("c")
	Set injected = "Call"_$Char(10)_"Status at 1 (built by OcuTalon):"_$Char(8232)_"more"_$Char(13, 11, 12, 133, 8233, 1)_"end"
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(ref, ..At("2099-06-15 12:20"), "pending", {"Text": (injected)}))
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"))
	Do $$$AssertEquals(..Count(text, "Reminder: "), 1, "a reminder text with line breaks is one line")
	Do $$$AssertEquals(..Line(text, "Reminder: "), "Reminder: CallStatus at 1 (built by OcuTalon):moreend | 2099-06-15 12:20", "which starts Reminder: and holds the text without its line breaks and control characters")
	Do $$$AssertEquals(..Count(text, "Status at "), 1, "and no line of its own starts like the status line")
	Do $$$AssertEquals($Length(text, $Char(10)), 8, "the text has the checklist, a blank line, the status line and the five lines")
}

Method TestTheCut()
{
	Set checklist = $Translate($Justify("", 1000), " ", "x")
	Set ref = ..Person(checklist)
	Do ..Reminders(ref, 60, "2099-06-15 12:10")
	Set lf = $Char(10)
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"), .whole)
	Do $$$AssertEquals($Extract(text, 1, 1002), checklist_lf_lf, "the checklist is whole, then a blank line")
	Set block = $Extract(text, 1003, *)
	Set all = $Extract(whole, 1003, *)
	Do $$$AssertTrue($Length(all) > 4000, "the whole status passes 4,000 characters: "_$Length(all))
	Do $$$AssertTrue($Length(block) '> 4000, "the status block is at most 4,000 characters: "_$Length(block))
	Set count = $Length(block, lf)
	Do $$$AssertEquals($Piece(block, lf, count), "(more not shown)", "it ends with the more line")
	Set same = 1
	For i = 1:1:count - 1 {
		If $Piece(block, lf, i) '= $Piece(all, lf, i) Set same = 0
	}
	Do $$$AssertTrue(same, "and keeps whole lines of the status, in order")
	Set kept = $Piece(block, lf, 1, count - 1)
	Do $$$AssertTrue($Length(kept) + 1 + $Length($Piece(all, lf, count)) + 1 + $Length("(more not shown)") > 4000, "with as many lines as fit")
	Do $$$AssertEquals($Piece(text, $Char(10, 10), 1), checklist, "and the checklist's 1,000 characters are all there")
}

Method TestPastTheCut()
{
	Set ref = ..Person("check the orders")
	Do ..Reminders(ref, 60, "2099-06-15 12:10")
	Set noon = ..At("2099-06-15 12:00")
	Do ..Beating(ref, noon)
	Do $$$AssertStatusOK($ClassMethod(..#BEAT, "RunDue", noon, .first, ref, 0, 1), "RunDue is OK")
	Do $$$AssertEquals(first.Count(), 1, "the first beat runs")
	If first.Count() '= 1 Quit
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(ref)
	Set key = row.LastSnapshotKey
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(ref, ..At("2099-06-15 12:50"), "pending", {"Text": "the last reminder"}))
	Set later = ..Plus(noon, 1800)
	Do $$$AssertStatusOK($ClassMethod(..#BEAT, "RunDue", later, .second, ref, 0, 1), "RunDue is OK again")
	Do $$$AssertEquals(second.Count(), 1, "the next beat runs: the snapshot is not the quiet one")
	If second.Count() '= 1 Quit
	Do $$$AssertEquals($Find(second.GetAt(1).Text, "the last reminder"), 0, "the new reminder is past the cut, so the text does not show it")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "Key", second.GetAt(1).Text), $ClassMethod(..#BEAT, "Key", first.GetAt(1).Text), "and the key of the text is the same")
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(ref)
	Do $$$AssertNotTrue(row.LastSnapshotKey = key, "but the key that Run stores differs, because it keys the whole status")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "Key", ..Snap(ref, later, .whole)), $ClassMethod(..#BEAT, "Key", ..Snap(ref, noon)), "the cut text of both beats has the same key")
	Do $$$AssertEquals(row.LastSnapshotKey, $ClassMethod(..#BEAT, "Key", whole), "and the stored one is that of the uncut status")
}

Method TestSameRecordsLaterTime()
{
	Set ref = ..Person("check the orders")
	Do ..Seed(ref, "", "2099-06-15 23:20")
	Set early = ..At("2099-06-15 23:00")
	Set later = ..Plus(early, 25200)
	Set first = ..Snap(ref, early)
	Set second = ..Snap(ref, later)
	Set lf = $Char(10)
	Do $$$AssertEquals($Piece(first, lf, 3), "Status at 2099-06-15 23:00 (built by OcuTalon):", "the status line is the first time")
	Do $$$AssertEquals($Piece(second, lf, 3), "Status at 2099-06-16 06:00 (built by OcuTalon):", "and the second, over local midnight")
	Do $$$AssertEquals($Piece(first, lf, 4, 8), $Piece(second, lf, 4, 8), "the entry lines are the same")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "Key", first), $ClassMethod(..#BEAT, "Key", second), "and so is the key")
}

Method TestEachKindChangesTheKey()
{
	Set ref = ..Person("check the orders")
	Set seeded = ..Seed(ref, "")
	Set now = ..At("2099-06-15 12:00")
	Set keys = $ListBuild($ClassMethod(..#BEAT, "Key", ..Snap(ref, now)))
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(seeded.incident)
	Set row.Count = 4
	Do row.%Save()
	Do ..Differs(ref, now, .keys, "an incident's count")
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(seeded.check)
	Set row.Result = "passed"
	Do row.%Save()
	Do ..Differs(ref, now, .keys, "a watch's result")
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(seeded.approval)
	Set row.ExpiresAt = ..At("2099-06-15 13:45")
	Do row.%Save()
	Do ..Differs(ref, now, .keys, "an approval request's expiry")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(seeded.reminder)
	Set row.Text = "Call Ben"
	Do row.%Save()
	Do ..Differs(ref, now, .keys, "a reminder's text")
	Set row = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(seeded.decision)
	Set row.Outcome = "tellnow"
	Do row.%Save()
	Do ..Differs(ref, now, .keys, "a decision's outcome")
	Do ..Put(ref, "checklist", "check the billing")
	Do ..Differs(ref, now, .keys, "the checklist")
}

Method TestWatchRuns()
{
	Set ref = ..Person("check the orders")
	Set noon = ..At("2099-06-15 12:00")
	Set watch = ..Keep(##class(OcuTalon.Test.Data.Fixture).Check(ref, "ZZNS", "Zz.Beat.Runs", {"DisplayName": "Orders feed", "Result": "passed", "LastRunAt": (..At("2099-06-15 11:58"))}))
	Set first = ..Snap(ref, noon)
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(watch)
	Set row.LastRunAt = ..At("2099-06-15 12:01")
	Do $$$AssertStatusOK(row.%Save(), "the watch has run again")
	Set second = ..Snap(ref, noon)
	Do $$$AssertEquals(second, first, "a watch that runs again with the same result gives the same text: its line holds no time")
	Do $$$AssertEquals(..Line(second, "Watch: "), "Watch: Orders feed | passed", "the line is the display name and the result")
	Do ..Beating(ref, noon)
	Do $$$AssertStatusOK($ClassMethod(..#BEAT, "RunDue", noon, .items, ref, 0, 1), "RunDue is OK")
	Do $$$AssertEquals(items.Count(), 1, "the first beat runs")
	If items.Count() '= 1 Quit
	Set key = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(ref).LastSnapshotKey
	Do ..Settled(ref, items.GetAt(1).ItemId)
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(watch)
	Set row.LastRunAt = ..At("2099-06-15 12:29")
	Do $$$AssertStatusOK(row.%Save(), "the watch has run again")
	Do $$$AssertStatusOK($ClassMethod(..#BEAT, "RunDue", ..Plus(noon, 1800), .items, ref, 0, 1), "RunDue is OK at the next due time")
	Do $$$AssertEquals(items.Count(), 0, "the beat after an ignore, with the watch run again and the same result, sends nothing")
	Set beat = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(ref)
	Do $$$AssertEquals(beat.LastSkipReason_"|"_beat.LastQuietKey, "unchanged|"_key, "it is skipped as unchanged")
}

Method TestWatchResultChanges()
{
	Set ref = ..Person("check the orders")
	Set noon = ..At("2099-06-15 12:00")
	Set watch = ..Keep(##class(OcuTalon.Test.Data.Fixture).Check(ref, "ZZNS", "Zz.Beat.Changes", {"DisplayName": "Orders feed", "Result": "passed"}))
	Do ..Beating(ref, noon)
	Do $$$AssertStatusOK($ClassMethod(..#BEAT, "RunDue", noon, .items, ref, 0, 1), "RunDue is OK")
	Do $$$AssertEquals(items.Count(), 1, "the first beat runs")
	If items.Count() '= 1 Quit
	Set key = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(ref).LastSnapshotKey
	Do ..Settled(ref, items.GetAt(1).ItemId)
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(watch)
	Set row.Result = "failed"
	Do row.%Save()
	Do $$$AssertStatusOK($ClassMethod(..#BEAT, "RunDue", ..Plus(noon, 1800), .items, ref, 0, 1), "RunDue is OK at the next due time")
	Do $$$AssertEquals(items.Count(), 1, "a watch that went from passed to failed makes the beat run")
	Set beat = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(ref)
	Do $$$AssertNotTrue(beat.LastSnapshotKey = key, "with another key")
}

Method TestFailedRead()
{
	Set ref = ..Person("check the orders")
	Do ..Seed(ref, "")
	Set noon = ..At("2099-06-15 12:00")
	Set reads = $ListBuild("incidents", "checks", "approvals", "reminders", "decisions", "incident", "turn", "channel")
	Set position = 0
	While $ListNext(reads, position, what) {
		Set ^||OcuTalon.BrokenBeat = what
		Set threw = 0
		Try {
			Set text = ##class(OcuTalon.Test.Checks.BrokenBeat).Snapshot(ref, noon)
		} Catch exception {
			Set threw = 1
		}
		Do $$$AssertTrue(threw, "a failed read of "_what_" makes Snapshot throw, not write a none line")
	}
	Set ^||OcuTalon.BrokenBeat = "none-such"
	Set threw = 0
	Try {
		Do ##class(OcuTalon.Test.Checks.BrokenBeat).ReadOf("no-such-read", ref)
	} Catch exception {
		Set threw = 1
	}
	Do $$$AssertTrue(threw, "and Beat's own Read throws on an error status, which it never answers as nothing")
	Kill ^||OcuTalon.BrokenBeat
	Do ..Beating(ref, noon)
	Set sc = ##class(OcuTalon.Test.Checks.BrokenBeat).RunDue(noon, .items, ref, 0, 1)
	Do $$$AssertStatusNotOK(sc, "RunDue answers an error status")
	Set message = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue($Find(message, "1 heartbeat beat failed"), "which counts the failure: "_message)
	Do $$$AssertTrue($Piece(message, "error codes ", 2) ? 1.N, "and holds its error code")
	Do $$$AssertEquals($Find(message, ref)_"|"_$Find(message, "none"), "0|0", "and no SessionRef and no snapshot text")
	Do $$$AssertEquals(items.Count(), 0, "no Item is made")
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(ref)
	Do $$$AssertEquals(row.NextDueAt_"|"_row.LastItemId_"|"_row.LastBeatAt, noon_"||", "and the beat stays due, with nothing recorded")
}

Method TestFailedReadRunNow()
{
	Set ref = ..Person("check the orders")
	Set noon = ..At("2099-06-15 12:00")
	Set ^||OcuTalon.BrokenBeat = "decisions"
	Set threw = 0
	Try {
		Set sc = ##class(OcuTalon.Test.Checks.BrokenBeat).RunNow(ref, noon, .item, .outcome, .availableAt, 0, 1)
	} Catch exception {
		Set threw = 1
	}
	Kill ^||OcuTalon.BrokenBeat
	Do $$$AssertTrue(threw, "a run now whose snapshot read fails throws, with no none line and no Item")
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(ref)
	Do $$$AssertEquals(row.LastRunNowAt_"|"_row.LastItemId_"|"_row.LastBeatAt_"|"_row.LastSkipReason_"|"_row.NextDueAt, "||||2099-12-31T00:00:00Z", "and writes nothing: the request is not counted")
	Set sc = $ClassMethod(..#BEAT, "RunNow", ref, noon, .item, .outcome, .availableAt, 0, 1)
	Do $$$AssertStatusOK(sc, "so that the same request a moment later is OK")
	Do $$$AssertEquals(outcome, "sent", "and is sent, not held back by the cooldown of a request that failed")
}

Method TestAMailAboutBeatsIsNotABeat()
{
	Set ref = ..Person("c")
	Do ..Mail(ref, "2099-06-15 10:00", "A: older mail", "digest", "mailbox")
	Do ..Mail(ref, "2099-06-15 10:30", "Ana: "_..Subject(), "digest", "mailbox")
	Do ..Mail(ref, "2099-06-15 11:00", $ZConvert(..Subject(), "L"), "digest", "mailbox")
	Do ..Mail(ref, "2099-06-15 11:30", ..Subject()_" again", "tellnow", "mailbox")
	Set text = ..Snap(ref, ..At("2099-06-15 12:00"))
	Do $$$AssertEquals(..Count(text, "Decision: "), 4, "a mail whose Summary only holds the beat's words, or differs in case, is no beat's row: all four have a line")
	Do $$$AssertEquals(..Line(text, "Decision: "), "Decision: 2099-06-15 11:30 | mailbox | tellnow | Heartbeat check-in again", "the newest first")
	Do $$$AssertTrue($Find(text, "Decision: 2099-06-15 10:00 | mailbox | digest | A: older mail"), "and the read goes on to the older mail")
}

Method TestTheCutBoundary()
{
	Set ref = ..Person("check the orders")
	Do ..Reminders(ref, 25, "2099-06-15 12:10")
	Set lf = $Char(10)
	Set noon = ..At("2099-06-15 12:00")
	Set short = $Piece(..Snap(ref, noon), lf_lf, 2)
	// one more reminder, whose line makes the block exactly 4,000 characters: "Reminder: {text} | {time}" holds 29 characters besides the text
	Set size = 4000 - $Length(short) - 1 - 29
	Do $$$AssertTrue(size > 0, "the 25 reminders leave room for one more line: "_size)
	If size '> 0 Quit
	Set reminder = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(ref, ..At("2099-06-15 12:10"), "pending", {"Text": ($Translate($Justify("", size), " ", "x"))}))
	Set text = ..Snap(ref, noon, .whole)
	Set block = $Piece(text, lf_lf, 2)
	Do $$$AssertEquals($Length(block), 4000, "the status block is exactly 4,000 characters")
	Do $$$AssertEquals(text, whole, "and exactly 4,000 is not cut")
	Do $$$AssertEquals($Find(block, "(more not shown)"), 0, "so it has no more line")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(reminder)
	Set row.Text = row.Text_"x"
	Do $$$AssertStatusOK(row.%Save(), "the last reminder is one character longer")
	Set text = ..Snap(ref, noon, .whole)
	Set block = $Piece(text, lf_lf, 2)
	Do $$$AssertEquals($Length($Piece(whole, lf_lf, 2)), 4001, "the whole status is 4,001 characters")
	Do $$$AssertTrue($Length(block) '> 4000, "and the block is cut to at most 4,000: "_$Length(block))
	Do $$$AssertEquals($Piece(block, lf, $Length(block, lf)), "(more not shown)", "ending with the more line")
	Do $$$AssertEquals($Find(block, "xxxxxxxxxx"), 0, "which has dropped the whole line that went over")
}

/// One more key step: the key of the snapshot differs from every earlier key (keys, a list that grows).
Method Differs(ref As %String, now As %String, ByRef keys As %List, what As %String) [ Private ]
{
	Set key = $ClassMethod(..#BEAT, "Key", ..Snap(ref, now))
	Do $$$AssertEquals($ListFind(keys, key), 0, "a change to "_what_" changes the key")
	Set keys = keys_$ListBuild(key)
}

/// The snapshot of the person on 2099-06-15 equals the text of each eval/heartbeat-* case (the records its status block lists are seeded with the case's
/// times moved to that day), once every YYYY-MM-DD HH:MM is masked; the case's Item is the beat Item: its channel, subject, sender and provenance. A
/// heartbeat-* folder with no seeding here fails the test.
Method TestHeartbeatEvalCases()
{
	Set folder = ##class(%File).NormalizeDirectory(##class(OcuTalon.Eval.In).#FOLDER)
	Do $$$AssertTrue(##class(%File).DirectoryExists(folder), "the repository's eval/ is mounted at "_folder_" (a throwaway or CI stack)")
	If '##class(%File).DirectoryExists(folder) Quit
	Set prefix = $Parameter(..#BEAT, "STATUSPREFIX"), suffix = $Parameter(..#BEAT, "STATUSSUFFIX")
	Set known = $ListBuild("heartbeat-nothing-changed", "heartbeat-incident-open", "heartbeat-injected-decision")
	Set names = ##class(OcuTalon.Eval.In).CaseNames(folder, "")
	Set seen = "", lf = $Char(10)
	Set position = 0
	While $ListNext(names, position, name) {
		If $Extract(name, 1, 10) '= "heartbeat-" Continue
		Do $$$AssertTrue($ListFind(known, name), name_": the test knows which records the case lists")
		If '$ListFind(known, name) Continue
		Set seen = seen_$ListBuild(name)
		Set case = ##class(OcuTalon.Test.Eval.Cases).Read(folder, name)
		Do $$$AssertTrue($IsObject(case), name_": the case is read")
		If '$IsObject(case) Continue
		Set item = case.item
		Set beat = ##class(OcuTalon.Msg.Item).%New()
		Do $$$AssertEquals(item.channel_"|"_item.subject_"|"_item.sender_"|"_item.provenance, $Parameter(..#BEAT, "CHANNEL")_"|"_..Subject()_"|"_beat.Sender_"|untrusted", name_": its Item has the channel, subject, sender and provenance of the beat's")
		Set text = item.text
		Set cut = $Find(text, lf_lf)
		Do $$$AssertTrue(cut > 0, name_": the text is the checklist, a blank line and the status block")
		If 'cut Continue
		Set checklist = $Extract(text, 1, cut - 3)
		Set block = $Extract(text, cut, *)
		Set first = $Piece(block, lf, 1)
		Do $$$AssertTrue(($Extract(first, 1, $Length(prefix)) = prefix) && ($Extract(first, *-$Length(suffix)+1, *) = suffix), name_": the block starts with the status line")
		Set anchor = $Extract(first, $Length(prefix) + 1, $Length(prefix) + 10)
		Set ref = ..Person(checklist)
		Do ..SeedBlock(ref, block, anchor)
		Set moved = ..Moved($Extract(first, $Length(prefix) + 1, $Length(prefix) + 16), anchor)
		Set snapshot = ..Snap(ref, ..At(moved))
		Do $$$AssertEquals(..Masked(snapshot), ..Masked(text), name_": the snapshot of the records the case lists is the case's text, with the times masked")
	}
	Set position = 0
	While $ListNext(known, position, name) {
		Do $$$AssertTrue($ListFind(seen, name), name_": the case is in eval/")
	}
}

/// Seeds the records that the lines of the status block list for the person: an incident, a watch, a pending approval request of the incident of the
/// production it names, a reminder or a decision. A line that says none seeds nothing. The times are those of the block moved to 2099-06-15 (Moved);
/// anchor is the day of the block's status line.
Method SeedBlock(ref As %String, block As %String, anchor As %String) [ Private ]
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set lf = $Char(10)
	For i = 2:1:$Length(block, lf) {
		Set line = $Piece(block, lf, i)
		Set label = $Piece(line, ": ", 1)
		Set fields = $ListFromString($Piece(line, ": ", 2, 999), " | ")
		Set wanted = $Case(label, "Incident": 4, "Watch": 2, "Approval request": 5, "Reminder": 2, "Decision": 4, : 0)
		If wanted && ($ListLength(fields) '= wanted) {
			Do $$$AssertTrue(0, "the line has the "_wanted_" fields of its kind: "_line)
			Continue
		}
		If label = "Incident" {
			Set production = $List(fields, 1)
			Set incident(production) = ..Keep($ClassMethod(fixture, "Incident", ref, ..Now(), "ZZNS", production, {"State": ($List(fields, 2)), "Count": ($List(fields, 3)), "FirstAt": (..At(..Moved($List(fields, 4), anchor)))}))
		} ElseIf label = "Watch" {
			Do ..Keep($ClassMethod(fixture, "Check", ref, "ZZNS", "OcuTalon.Demo.Orders.Production", {"DisplayName": ($List(fields, 1)), "Result": ($List(fields, 2))}))
		} ElseIf label = "Approval request" {
			Set production = $List(fields, 3)
			Do $$$AssertTrue($Data(incident($Get(production))), "the approval request names the production of an incident of the block: "_production)
			Do ..Keep($ClassMethod(fixture, "Approval", ref, $Get(incident(production)), "pending", ..At(..Moved($List(fields, 4), anchor)), {"Kind": ($List(fields, 1)), "FixKind": ($List(fields, 2)), "ExpiresAt": (..At(..Moved($List(fields, 5), anchor)))}))
		} ElseIf label = "Reminder" {
			Do ..Keep($ClassMethod(fixture, "Reminder", ref, ..At(..Moved($List(fields, 2), anchor)), "pending", {"Text": ($List(fields, 1))}))
		} ElseIf label = "Decision" {
			Do ..Mail(ref, ..Moved($List(fields, 1), anchor), $List(fields, 4), $List(fields, 3), $List(fields, 2))
		} Else {
			Do $$$AssertTrue($ListFind($ListBuild("Incidents", "Watches", "Approval requests", "Reminders", "Decisions"), label) && ($List(fields, 1) = "none"), "the line seeds nothing, so it says none: "_line)
		}
	}
}

/// The time YYYY-MM-DD HH:MM (or its first 10 characters, a day) moved by the same number of days that takes the day anchor to 2099-06-15.
ClassMethod Moved(stamp As %String, anchor As %String) As %String [ Private ]
{
	Set days = $ZDateH($Extract(stamp, 1, 10), 3) - $ZDateH(anchor, 3)
	Quit $ZDate($ZDateH("2099-06-15", 3) + days, 3)_$Extract(stamp, 11, *)
}

/// The text with every YYYY-MM-DD HH:MM replaced by a mask.
ClassMethod Masked(text As %String) As %String [ Private ]
{
	Quit ##class(%Regex.Matcher).%New("\d{4}-\d{2}-\d{2} \d{2}:\d{2}", text).ReplaceAll("YYYY-MM-DD HH:MM")
}

/// Makes the person's HeartbeatBeat row due at the UTC time (before the settings, so that a real tick leaves it).
Method Beating(ref As %String, due As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(ref)
	If '$IsObject(row) {
		Set row = ##class(OcuTalon.Data.HeartbeatBeat).%New()
		Set row.SessionRef = ref
	}
	Set row.NextDueAt = due
	Do $$$AssertStatusOK(row.%Save(), "the person's row is due")
}

/// The person's decision for the beat Item, as Decide records an ignore: Kind decide, the Item's id, the beat's own Summary.
Method Settled(ref As %String, itemId As %String) [ Private ]
{
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Decision(ref, "decide", ##class(OcuTalon.Data.Time).NowUtc(), {"ItemId": (itemId), "Outcome": "ignore", "Summary": (..Subject())}))
}

/// One row of each kind for the person, as the Full snapshot test lists them (now is 12:00 on 2099-06-15; the reminder is due at remind, local, 12:20 by
/// default). With a name, every field that the snapshot never reads holds a token of its own. It answers {incident, check, approval, reminder, decision, tokens},
/// the Refs and the list of the tokens, which also holds the Refs, the ItemIds and the TraceRef of the person.
Method Seed(ref As %String, name As %String, remind As %String = "2099-06-15 12:20") As %DynamicObject [ Private ]
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set tokens = []
	Set incident = {"State": "open", "Count": 3, "FirstAt": (..At("2099-06-15 11:40"))}
	Set check = {"DisplayName": "Orders feed", "Result": "failed", "LastRunAt": (..At("2099-06-15 11:59"))}
	Set approval = {"Kind": "fix", "FixKind": "restart", "ExpiresAt": (..At("2099-06-15 12:45"))}
	Set reminder = {"Text": "Call Ana"}
	Set decision = {"Summary": "Ana: Invoice run", "Outcome": "digest"}
	If name '= "" {
		Do ..Tokened(incident, tokens, name, "Cause,SampleError,FixSummary,Element")
		Do ..Tokened(check, tokens, name, "Finding,AskedBy,Reported")
		Do ..Tokened(approval, tokens, name, "DryRun,ToolArguments,FixParameters,FixTargets,AnsweredBy,RequiredRole")
		Do ..Tokened(reminder, tokens, name, "IdempotencyKey,CancelKey")
		Do ..Tokened(decision, tokens, name, "Reasons,Payload")
	}
	Set result = {"tokens": (tokens)}
	Set result.incident = ..Keep($ClassMethod(fixture, "Incident", ref, ..Now(), "ZZNS", "Demo.Orders", incident))
	Set result.check = ..Keep($ClassMethod(fixture, "Check", ref, "ZZNS", "Demo.Orders", check))
	Set result.approval = ..Keep($ClassMethod(fixture, "Approval", ref, result.incident, "pending", ..At("2099-06-15 11:45"), approval))
	Set result.reminder = ..Keep($ClassMethod(fixture, "Reminder", ref, ..At(remind), "pending", reminder))
	Set result.decision = ..Keep($ClassMethod(fixture, "Decision", ref, "decide", ..At("2099-06-15 11:50"), decision))
	Do ..Keep($ClassMethod(fixture, "Usage", result.decision, ref, {"Channel": "mailbox"}))
	If name '= "" {
		Do tokens.%Push(result.incident)
		Do tokens.%Push(result.check)
		Do tokens.%Push(result.approval)
		Do tokens.%Push(result.reminder)
		Do tokens.%Push(result.decision)
		Do tokens.%Push(##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(result.decision).ItemId)
		Do tokens.%Push(ref)
		Do tokens.%Push(##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef)
	}
	Quit result
}

/// Sets each of the fields (comma-separated) of the object to a token of its own, and adds the token to tokens. The token holds the name of the person and of
/// the field, so that no two are alike.
Method Tokened(object As %DynamicObject, tokens As %DynamicArray, name As %String, fields As %String) [ Private ]
{
	For i = 1:1:$Length(fields, ",") {
		Set field = $Piece(fields, ",", i)
		Set token = "qzx"_name_field_"qzx"
		Do object.%Set(field, token)
		Do tokens.%Push(token)
	}
}

/// A decision of Kind decide for a mail Item with a Usage row of the channel, recorded at the local time.
Method Mail(ref As %String, local As %String, summary As %String, outcome As %String, channel As %String) [ Private ]
{
	Set decision = ..Keep(##class(OcuTalon.Test.Data.Fixture).Decision(ref, "decide", ..At(local), {"Summary": (summary), "Outcome": (outcome)}))
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Usage(decision, ref, {"Channel": (channel)}))
}

/// Reminders of the person, count of them, each with a text of 100 characters of its own, all due at the local time.
Method Reminders(ref As %String, count As %Integer, local As %String) [ Private ]
{
	For i = 1:1:count {
		Set text = "R"_$Extract(1000 + i, 2, 4)_" "_$Translate($Justify("", 95), " ", "r")
		Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(ref, ..At(local), "pending", {"Text": (text)}))
	}
}

/// A fixture person with its HeartbeatBeat row, due far ahead and made before the settings, so that no real tick runs it, and its five settings written (on, 30
/// minutes, all day, the checklist); its Ref. The row and the settings are removed after the test.
Method Person(checklist As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzsnap"_$Increment(^OcuTalonTest("ChecksSnapshot", "n")))
	Do ..Keep(ref)
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Do ..Beating(ref, "2099-12-31T00:00:00Z")
	For name = "on", "interval", "from", "to", "checklist" {
		Do ..Put(ref, name, $Case(name, "on": 1, "interval": 30, "checklist": checklist, : ""))
	}
	Quit ref
}

/// Writes the person's setting.
Method Put(ref As %String, name As %String, value As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set($ClassMethod(..#BEAT, "SettingKey", ref, name), value), "the setting "_name_" is written")
}

/// Records the Ref of a fixture row for the clean-up, and gives it back.
Method Keep(ref As %String) As %String [ Private ]
{
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The snapshot of the person at the UTC time; whole is the text without the cut.
Method Snap(ref As %String, now As %String, Output whole As %String) As %String [ Private ]
{
	Quit $ClassMethod(..#BEAT, "Snapshot", ref, now, .whole)
}

/// The UTC time of a local time, YYYY-MM-DD HH:MM, in the instance zone.
ClassMethod At(local As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Time).FromLocal($Piece(local, " ", 1)_"T"_$Piece(local, " ", 2)_":00")
}

/// The UTC time that many seconds after at.
ClassMethod Plus(at As %String, seconds As %Integer) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Time).AddSeconds(at, seconds)
}

/// The time now, UTC.
ClassMethod Now() As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Time).NowUtc()
}

/// The subject of a beat's Item, which is the Summary of a beat's decision.
ClassMethod Subject() As %String [ Private ]
{
	Quit $Parameter("OcuTalon.Checks.Beat", "SUBJECT")
}

/// The number of lines of the text that start with the prefix.
ClassMethod Count(text As %String, prefix As %String) As %Integer [ Private ]
{
	Set count = 0
	For i = 1:1:$Length(text, $Char(10)) {
		If $Extract($Piece(text, $Char(10), i), 1, $Length(prefix)) = prefix Set count = count + 1
	}
	Quit count
}

/// The first line of the text that starts with the prefix, or "".
ClassMethod Line(text As %String, prefix As %String) As %String [ Private ]
{
	For i = 1:1:$Length(text, $Char(10)) {
		Set line = $Piece(text, $Char(10), i)
		If $Extract(line, 1, $Length(prefix)) = prefix Quit
	}
	Quit $Select($Extract($Get(line), 1, $Length(prefix)) = prefix: line, 1: "")
}

}
