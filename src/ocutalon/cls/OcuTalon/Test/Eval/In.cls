/// Tests of EvalIn's handling of one case (Stories 9.1 and 9.7; AD-14, AD-22, AD-26, AD-30). WARM-SAFE: they call OnProcessInput on a shadow
/// instance of OcuTalon.Test.Eval.ZzIn, a double of EvalIn whose Dispatch, Ask, Deliver and Pause send and wait for nothing and record what they
/// were given, so they start no production and send no message. The case folders are written under the instance's temp directory and removed
/// afterwards. The run Refs and case names start with zz.
///   - TestSendsItem: a case becomes an Item with a new ItemId, SourceItemId set to the recorded item.itemId, owner eval, provenance
///     untrusted and the record's channel, sender, subject, text, catalog key and slots (an object as JSON text); the service's
///     SuperSession is the run's Ref; the case's row is open (state sent) when the Item is dispatched; a recorded provenance of
///     untrusted, or none, is accepted, and the kinds item and injection are sent;
///   - TestRefuses: a folder with no case.json, a case.json that is not a JSON object, a kind that is not sent (none, an incident, a turn), no
///     item.itemId and a recorded provenance other than untrusted are each refused with their reason, logged as a warning, with no row
///     and nothing dispatched;
///   - TestSendFails: a send that fails or throws deletes the case's row and returns the error text as the reason, and the case can be sent again;
///   - TestInputRefused: an input that is not a folder from Start, and a service with no run, are refused;
///   - TestCaseNames: a comma list is trimmed and each name kept once, in order, and no list gives the subfolders that hold a case.json,
///     in name order;
///   - TestSendsTurn (Story 9.7, AC1, DW-110): an all-clear case is a user turn of owner eval: every field of the request is the contract's (a fresh
///     ItemId, Kind turn, Provenance user, SessionMode fresh and no SeedText or SystemNote, the run's Ref as TraceRef and SuperSession, channel web, the
///     service's %SessionId as ThreadSessionId, an Input equal to what Core.Intake.RequestFor gives an Item of the same fields, the Summary cut to 80
///     characters); its TurnResult holds the case's checks as JSON and its row is open when the request is asked; the delivered TurnResult holds the Reply's
///     DecisionRef, ToolsRun and text and the catalog key and rows that Checks.Render gives its HostData checks; a HostData without checks adds none;
///   - TestSendsCommand: a command case keeps no recorded checks, and with no HostData the key and rows stay empty;
///   - TestTurnBusy: a Busy reply is asked again, BUSYWAIT seconds later, with the same ItemId (the numbers are Core.Conversation's); after BUSYMAX + 1
///     asks the case ends as a fallback with the reason rate_limited, with no DecisionRef, and is still delivered; a fallback Reply is delivered as it is, and
///     a TurnResult that cannot be delivered is logged and leaves its row sent;
///   - TestTurnRefuses: a turn case with no turn.text, or an all-clear case whose checks is not an array, is refused with its reason before anything is saved or
///     asked; a Decide that gives no Reply (an error, a timeout, an answer that is not a Reply), or whose call throws, skips the case with a reason (the
///     exception's text for a throw) and leaves no row and no TurnResult, and nothing is delivered; a case whose row cannot be opened (the run has
///     a row of that case already) is skipped with the error text, keeps that row and leaves no TurnResult;
///   - TestSendOrder: the turn kinds come first, then the others, each group in the order of the list.
Class OcuTalon.Test.Eval.In Extends %UnitTest.TestCase
{

/// The double of EvalIn.
Parameter DOUBLE = "OcuTalon.Test.Eval.ZzIn";

/// The folder that holds the cases of the tests, with a trailing separator.
Property Folder As %String(MAXLEN = 500);

/// The Ref of the run of the test.
Property Run As %String(MAXLEN = 22);

/// The newest row of the event log when the test began.
Property Mark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set ..Folder = ##class(%File).NormalizeDirectory("zzevalin"_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 12), ##class(%File).NormalizeDirectory("Temp", $SYSTEM.Util.ManagerDirectory()))
	Do ##class(%File).CreateDirectoryChain(..Folder)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("EvalIn")
	Do ##class(%File).RemoveDirectoryTree(..Folder)
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("EvalIn")
	Set ..Run = "zz"_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 20)
	Set ..Mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Test.Eval.ZzIn).DeleteBodies()
	Kill ^OcuTalonTest("EvalIn")
	Do ##class(OcuTalon.Eval.Data.CaseResult).Remove(..Run)
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..Mark, "OnProcessInput", ##class(OcuTalon.Eval.In).#LOGSKIPPED)
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..Mark, "Converse", ##class(OcuTalon.Eval.In).#LOGNOTDELIVERED)
	Quit $$$OK
}

/// Starts a test's next round: deletes the TurnResult bodies that the double recorded, clears its records and deletes the run's rows.
Method Reset() [ Private ]
{
	Do ##class(OcuTalon.Test.Eval.ZzIn).DeleteBodies()
	Kill ^OcuTalonTest("EvalIn")
	Do ##class(OcuTalon.Eval.Data.CaseResult).Remove(..Run)
}

/// A case becomes the Item the contract says, with its row open at the moment of the send.
Method TestSendsItem()
{
	Set service = ..Service()
	If '$IsObject(service) Quit
	Do ..WriteCase("zz-full", {"name": "zz-full", "kind": "injection", "item": {"itemId": "zz-full-id", "channel": "mailbox", "provenance": "untrusted", "sender": "Sender <sender@example.com>", "subject": "A subject", "text": "The body", "catalogKey": "watch.example", "slots": {"a": 1, "b": "two"}}}.%ToJSON())
	Do $$$AssertEquals(..Process(service, "zz-full"), "", "an injection case with all the fields is sent")
	Do $$$AssertEquals(..Seen(), 1, "one Item was dispatched")
	Set seen = ..SeenAt(1)
	Do $$$AssertEquals($Length($List(seen, 1)), 22, "its ItemId is new and 22 characters")
	Do $$$AssertTrue($List(seen, 1) '= "zz-full-id", "and is not the recorded id")
	Do $$$AssertEquals($List(seen, 2)_"|"_$List(seen, 3)_"|"_$List(seen, 5), "zz-full-id|eval|untrusted", "SourceItemId is the recorded id, the owner is eval, the provenance untrusted")
	Do $$$AssertEquals($List(seen, 4)_"|"_$List(seen, 6)_"|"_$List(seen, 7)_"|"_$List(seen, 8), "mailbox|Sender <sender@example.com>|A subject|The body", "the channel, sender, subject and text are the record's")
	Do $$$AssertEquals($List(seen, 9)_"|"_$List(seen, 10), "watch.example|"_{"a": 1, "b": "two"}.%ToJSON(), "the catalog key is the record's and the slots are the object as JSON text")
	Do $$$AssertEquals($List(seen, 11), ..Run, "the SuperSession of the service is the run's Ref")
	Do $$$AssertEquals($List(seen, 12), 1, "the case's row was open when the Item was dispatched")
	Set row = ##class(OcuTalon.Eval.Data.CaseResult).RunCaseIndexOpen(..Run, "zz-full")
	Do $$$AssertTrue($IsObject(row), "the row stays")
	If $IsObject(row) Do $$$AssertEquals(row.State_"|"_row.SourceItemId_"|"_row.ItemId, "sent|zz-full-id|"_$List(seen, 1), "in state sent, with the Item's ids")

	Set slotsText = "{""x"": 1}"
	Do ..WriteCase("zz-slots", {"kind": "item", "item": {"itemId": "zz-slots-id", "slots": (slotsText)}}.%ToJSON())
	Do $$$AssertEquals(..Process(service, "zz-slots"), "", "an item case with no provenance and slots as text is sent")
	Set seen = ..SeenAt(2)
	Do $$$AssertEquals($List(seen, 5)_"|"_$List(seen, 10)_"|"_$List(seen, 4), "untrusted|{""x"": 1}|", "the provenance is untrusted whatever was recorded, the slots text is kept, and the fields not recorded are empty")
	Do $$$AssertTrue($List(seen, 1) '= $List(..SeenAt(1), 1), "the second case has an ItemId of its own")
}

/// Each way a case is not sent gives its reason, a warning, no row and no send.
Method TestRefuses()
{
	Set service = ..Service()
	If '$IsObject(service) Quit
	Set in = "OcuTalon.Eval.In"
	Do ##class(%File).CreateDirectoryChain(##class(%File).SubDirectoryName(..Folder, "zz-nofile"))
	Do ..WriteCase("zz-notjson", "this is not json")
	Do ..WriteCase("zz-array", "[1, 2]")
	Do ..WriteCase("zz-nokind", {"item": {"itemId": "x"}}.%ToJSON())
	Do ..WriteCase("zz-incident", {"kind": "incident", "item": {"itemId": "x"}}.%ToJSON())
	Do ..WriteCase("zz-turn", {"kind": "turn", "item": {"itemId": "x"}}.%ToJSON())
	Do ..WriteCase("zz-noitem", {"kind": "item"}.%ToJSON())
	Do ..WriteCase("zz-itemtext", {"kind": "item", "item": "x"}.%ToJSON())
	Do ..WriteCase("zz-emptyid", {"kind": "item", "item": {"itemId": ""}}.%ToJSON())
	Do ..WriteCase("zz-user", {"kind": "item", "item": {"itemId": "x", "provenance": "user"}}.%ToJSON())
	Do ..WriteCase("zz-tainted", {"kind": "injection", "item": {"itemId": "x", "provenance": "tainted"}}.%ToJSON())
	Set cases = ""
	For entry = $ListBuild("zz-nofile", $Parameter(in, "REASONNOCASEFILE")), $ListBuild("zz-notjson", $Parameter(in, "REASONNOTJSON")), $ListBuild("zz-array", $Parameter(in, "REASONNOTJSON")), $ListBuild("zz-nokind", ..KindReason("")), $ListBuild("zz-incident", ..KindReason("incident")), $ListBuild("zz-turn", ..KindReason("turn")) {
		Set cases = cases_$ListBuild(entry)
	}
	For entry = $ListBuild("zz-noitem", $Parameter(in, "REASONNOITEMID")), $ListBuild("zz-itemtext", $Parameter(in, "REASONNOITEMID")), $ListBuild("zz-emptyid", $Parameter(in, "REASONNOITEMID")), $ListBuild("zz-user", ..ProvenanceReason("user")), $ListBuild("zz-tainted", ..ProvenanceReason("tainted")) {
		Set cases = cases_$ListBuild(entry)
	}
	Set position = 0
	While $ListNext(cases, position, case) {
		Do $$$AssertEquals(..Process(service, $List(case, 1)), $List(case, 2), $List(case, 1)_": the reason")
	}
	Do $$$AssertEquals(..Seen(), 0, "nothing was dispatched")
	Do $$$AssertEquals(..Rows(), 0, "and no row was made")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..Mark, .text, "OnProcessInput", $Parameter(in, "LOGSKIPPED")), $ListLength(cases), "each case was logged as a warning")
	Do $$$AssertTrue(text [ "zz-tainted", "naming the case: "_text)
}

/// A send that fails or throws deletes the case's row and returns the error text as the reason; the case can then be sent.
Method TestSendFails()
{
	Set service = ..Service()
	If '$IsObject(service) Quit
	Do ..WriteCase("zz-full", {"kind": "item", "item": {"itemId": "zz-full-id", "text": "The body"}}.%ToJSON())
	Set ^OcuTalonTest("EvalIn", "fail") = "the target is not there"
	Set reason = ..Process(service, "zz-full")
	Do $$$AssertTrue(reason [ "the target is not there", "the reason is the error text: "_reason)
	Do $$$AssertEquals(..Seen(), 1, "the send was tried once")
	Do $$$AssertEquals($List(..SeenAt(1), 12), 1, "with the row open")
	Do $$$AssertEquals(..Rows(), 0, "and the row is deleted")
	Kill ^OcuTalonTest("EvalIn", "fail")
	Set ^OcuTalonTest("EvalIn", "throw") = "the send threw"
	Set reason = ..Process(service, "zz-full")
	Do $$$AssertTrue(reason [ "the send threw", "a send that throws gives the exception's text as the reason: "_reason)
	Do $$$AssertEquals(..Seen(), 2, "the send was tried again")
	Do $$$AssertEquals($List(..SeenAt(2), 12), 1, "with the row open")
	Do $$$AssertEquals(..Rows(), 0, "and the row is deleted")
	Kill ^OcuTalonTest("EvalIn", "throw")
	Do $$$AssertEquals(..Process(service, "zz-full"), "", "the case is sent when the send works")
	Do $$$AssertEquals(..Rows(), 1, "and has its row")
}

/// An input that is not a folder from Start, and a service with no run, are refused with the input reason.
Method TestInputRefused()
{
	Set service = ..Service()
	If '$IsObject(service) Quit
	Set reason = ##class(OcuTalon.Eval.In).#REASONINPUT
	Do $$$AssertStatusOK(service.OnProcessInput(##class(Ens.StringRequest).%New("x"), .output), "OnProcessInput answers OK")
	Do $$$AssertEquals(output.StringValue, reason, "an input that is not a string container is refused")
	Do ..WriteCase("zz-full", {"kind": "item", "item": {"itemId": "zz-full-id"}}.%ToJSON())
	Set service.RunRef = ""
	Do $$$AssertStatusOK(service.OnProcessInput(##class(Ens.StringContainer).%New(##class(%File).SubDirectoryName(..Folder, "zz-full")), .output), "OnProcessInput answers OK")
	Do $$$AssertEquals(output.StringValue, reason, "a service with no run is refused")
	Do $$$AssertEquals(..Seen()_"|"_..Rows(), "0|0", "nothing was dispatched and no row was made")
}

/// The case names of a list, and of a folder.
Method TestCaseNames()
{
	Set in = "OcuTalon.Eval.In"
	Set list = $ClassMethod(in, "CaseNames", ..Folder, " zz-b , zz-a,zz-b,, zz-c ")
	Do $$$AssertEquals($ListToString(list, "|"), "zz-b|zz-a|zz-c", "a list is trimmed and each name kept once, in the order given")
	Set listed = ##class(%File).SubDirectoryName(..Folder, "listed")
	For name = "zz-b", "zz-a", "zz-nofile", "zz-c" {
		Set directory = ##class(%File).SubDirectoryName(listed, name)
		Do ##class(%File).CreateDirectoryChain(directory)
		If name '= "zz-nofile" Do ..WriteFile(directory, "{}")
	}
	Do ..WriteFile(listed, "{}")
	Set list = $ClassMethod(in, "CaseNames", listed, "")
	Do $$$AssertEquals($ListToString(list, "|"), "zz-a|zz-b|zz-c", "no list gives the subfolders that hold a case.json, in name order, and not a folder with none or a file")
	Do $$$AssertEquals($ListLength($ClassMethod(in, "CaseNames", ..Folder_"nothing-here/", "")), 0, "a folder that is not there has no cases")
}

/// An all-clear case is a user turn of owner eval in a fresh conversation, asked of Decide with the case's checks recorded; the Reply's fields and the
/// rendered key and rows are delivered in the TurnResult.
Method TestSendsTurn()
{
	Set service = ..Service()
	If '$IsObject(service) Quit
	Set session = 9876501
	Set service.%SessionId = session
	Set checks = [{"result": "failed", "entry": "Orders production", "finding": "a fix waiting for your approval", "checkedAt": "2026-10-16T18:13:00Z"}]
	Do ..WriteCase("zz-clear", {"name": "zz-clear", "kind": "all-clear", "turn": {"text": "Is everything fine?"}, "checks": (checks), "expectation": {"catalogKey": "checks.notEverything"}}.%ToJSON())
	Set hostData = {"checks": [{"result": "passed", "entry": "Results production", "finding": "", "checkedAt": "2026-10-16T18:13:00Z"}, {"result": "failed", "entry": "Orders production", "finding": "a fix waiting for your approval", "checkedAt": "2026-10-16T18:13:00Z"}]}.%ToJSON()
	Set ^OcuTalonTest("EvalIn", "reply", 1) = {"Text": "I read the check results.", "DecisionRef": "zzDecisionRef000000001", "ToolsRun": true, "HostData": (hostData)}.%ToJSON()
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.SessionRef = "eval", item.Channel = "web", item.Provenance = "user", item.Text = "Is everything fine?"
	Set before = ##class(OcuTalon.Core.Intake).RequestFor(item, "turn", ..Run, "").Input
	Do $$$AssertEquals(..Process(service, "zz-clear"), "", "an all-clear case is sent")
	Set after = ##class(OcuTalon.Core.Intake).RequestFor(item, "turn", ..Run, "").Input
	Do $$$AssertEquals(..Asked(), 1, "Decide was asked once")
	Do $$$AssertEquals(..Seen(), 0, "and no Item was dispatched")
	Set asked = ..AskedAt(1)
	Do $$$AssertEquals($List(asked, 1)_"|"_$List(asked, 2)_"|"_$List(asked, 3), "turn|user|eval", "the request is a user turn of owner eval")
	Do $$$AssertEquals($Length($List(asked, 4)), 22, "its ItemId is new and 22 characters")
	Do $$$AssertTrue($List(asked, 4) '= "zz-clear", "and is not the case's name")
	Do $$$AssertTrue(($List(asked, 5) = before) || ($List(asked, 5) = after), "its Input is what Core.Intake.RequestFor gives an Item of the same fields: "_$List(asked, 5))
	Do $$$AssertEquals($Piece($List(asked, 5), $Char(10, 10), 2), "Is everything fine?", "and it holds the case's text after the preamble")
	Do $$$AssertEquals($List(asked, 6)_"|"_$List(asked, 7)_"|"_$List(asked, 8), "Is everything fine?|"_..Run_"|web", "the Summary is the text, the TraceRef the run's Ref and the channel web")
	Do $$$AssertEquals($List(asked, 9), session, "the ThreadSessionId is the service's %SessionId")
	Do $$$AssertEquals($List(asked, 10)_"|"_$List(asked, 11)_"|"_$List(asked, 12), "fresh||", "the SessionMode is fresh, with no SeedText and no SystemNote (DW-110)")
	Do $$$AssertEquals($List(asked, 13)_"|"_$List(asked, 14), "1|"_checks.%ToJSON(), "the TurnResult with the case's checks as JSON exists when Decide is asked")
	Do $$$AssertEquals($List(asked, 15), 1, "and so does the case's open row")
	Do $$$AssertEquals($List(asked, 16), ..Run, "the SuperSession of the service is the run's Ref")
	Do $$$AssertEquals(..Delivered(), 1, "one TurnResult was delivered")
	Set delivered = ..DeliveredAt(1)
	Do $$$AssertEquals($List(delivered, 1), $List(asked, 4), "for the same ItemId")
	Do $$$AssertEquals($List(delivered, 2)_"|"_$List(delivered, 3), "zz-clear|"_checks.%ToJSON(), "with the case's name as SourceItemId and the recorded checks")
	Do $$$AssertEquals($List(delivered, 4)_"|"_$List(delivered, 5)_"|"_$List(delivered, 6), "zzDecisionRef000000001|1|I read the check results.", "and the DecisionRef, ToolsRun and text of the Reply")
	Set rendered = ##class(OcuTalon.Checks.Render).Render(##class(%DynamicAbstractObject).%FromJSON(hostData).checks, .rows)
	Do $$$AssertEquals(rendered, "checks.notEverythingRestPassed", "control: Render gives a key for the HostData rows")
	Do $$$AssertEquals($List(delivered, 7)_"|"_$List(delivered, 8), rendered_"|"_rows.%ToJSON(), "the TurnResult holds that key and the rendered rows")
	Do $$$AssertEquals($List(delivered, 9)_"|"_$List(delivered, 10)_"|"_$List(delivered, 11), "0||"_..Run, "it is no fallback, and the service's SuperSession is the run's Ref")
	Set row = ##class(OcuTalon.Eval.Data.CaseResult).RunCaseIndexOpen(..Run, "zz-clear")
	Do $$$AssertTrue($IsObject(row), "the case has its row")
	If $IsObject(row) Do $$$AssertEquals(row.State_"|"_row.SourceItemId_"|"_row.ItemId, "sent|zz-clear|"_$List(asked, 4), "in state sent, with the case's name as SourceItemId")

	Do ..Reset()
	Set line = $Translate($Justify("", 100), " ", "x")
	Set long = $Char(10)_"   "_line_$Char(10)_"second line"
	Do ..WriteCase("zz-long", {"kind": "all-clear", "turn": {"text": (long)}, "checks": []}.%ToJSON())
	Set other = {"other": 1}.%ToJSON()
	Set ^OcuTalonTest("EvalIn", "reply", 1) = {"Text": "Plain text.", "HostData": (other)}.%ToJSON()
	Do $$$AssertEquals(..Process(service, "zz-long"), "", "a case whose text starts with a blank line is sent")
	Set asked = ..AskedAt(1)
	Do $$$AssertEquals($List(asked, 6), $Extract(line, 1, 80), "the Summary is the first line that is not blank, cut to 80 characters")
	Do $$$AssertEquals($List(asked, 14), "[]", "checks [] are recorded as []")
	Set delivered = ..DeliveredAt(1)
	Do $$$AssertEquals($List(delivered, 7)_"|"_$List(delivered, 8), "|", "a HostData without checks adds no key and no rows")

	Do ..Reset()
	Do ..WriteCase("zz-nocall", {"kind": "all-clear", "turn": {"text": "Is everything fine?"}, "checks": (checks)}.%ToJSON())
	Set ^OcuTalonTest("EvalIn", "reply", 1) = {"Text": "The CI mock looked at the productions.", "DecisionRef": "zzDecisionRef000000005"}.%ToJSON()
	Do $$$AssertEquals(..Process(service, "zz-nocall"), "", "a case whose model never calls check_status is sent")
	Set delivered = ..DeliveredAt(1)
	Do $$$AssertEquals($List(delivered, 3), checks.%ToJSON(), "its recorded checks are kept in the TurnResult")
	Do $$$AssertEquals($List(delivered, 7)_"|"_$List(delivered, 8), "|", "but with no HostData from check_status nothing is rendered: the recorded rows reach the reply only through the tool")
}

/// A command case keeps no recorded checks, and with no HostData the delivered key and rows are empty.
Method TestSendsCommand()
{
	Set service = ..Service()
	If '$IsObject(service) Quit
	Do ..WriteCase("zz-command", {"name": "zz-command", "kind": "command", "turn": {"text": "Please run the command df -h."}, "expectation": {"keyPhrases": ["can't run commands"]}}.%ToJSON())
	Set ^OcuTalonTest("EvalIn", "reply", 1) = {"Text": "I can't run commands.", "DecisionRef": "zzDecisionRef000000002"}.%ToJSON()
	Do $$$AssertEquals(..Process(service, "zz-command"), "", "a command case is sent")
	Set asked = ..AskedAt(1)
	Do $$$AssertEquals($List(asked, 1)_"|"_$List(asked, 2)_"|"_$List(asked, 3)_"|"_$List(asked, 10), "turn|user|eval|fresh", "it is a fresh user turn of owner eval")
	Do $$$AssertTrue($List(asked, 5) [ "Please run the command df -h.", "its Input holds the case's text")
	Do $$$AssertEquals($List(asked, 13)_"|"_$List(asked, 14), "1|", "its TurnResult exists with no recorded checks")
	Set delivered = ..DeliveredAt(1)
	Do $$$AssertEquals($List(delivered, 2)_"|"_$List(delivered, 3)_"|"_$List(delivered, 4)_"|"_$List(delivered, 5)_"|"_$List(delivered, 6), "zz-command||zzDecisionRef000000002|0|I can't run commands.", "the delivered TurnResult holds the reply, ToolsRun 0 and no recorded checks")
	Do $$$AssertEquals($List(delivered, 7)_"|"_$List(delivered, 8)_"|"_$List(delivered, 9), "||0", "and no key, no rows and no fallback")
}

/// A Busy reply is asked again after BUSYWAIT seconds, with the same ItemId, at most BUSYMAX times; then the case ends as a fallback.
Method TestTurnBusy()
{
	Set service = ..Service()
	If '$IsObject(service) Quit
	Set conversation = "OcuTalon.Core.Conversation"
	Set in = "OcuTalon.Eval.In"
	Do $$$AssertEquals($Parameter(in, "BUSYWAIT")_"|"_$Parameter(in, "BUSYMAX"), $Parameter(conversation, "BUSYWAIT")_"|"_$Parameter(conversation, "BUSYMAX"), "the Busy numbers are Conversation's")
	Do ..WriteCase("zz-busy", {"kind": "command", "turn": {"text": "Please run df."}}.%ToJSON())
	Set ^OcuTalonTest("EvalIn", "reply", 1) = "busy", ^OcuTalonTest("EvalIn", "reply", 2) = "busy"
	Set ^OcuTalonTest("EvalIn", "reply", 3) = {"Text": "Third time.", "DecisionRef": "zzDecisionRef000000003"}.%ToJSON()
	Do $$$AssertEquals(..Process(service, "zz-busy"), "", "a case whose Decide is busy twice is sent")
	Do $$$AssertEquals(..Asked(), 3, "Decide was asked three times")
	Do $$$AssertEquals($List(..AskedAt(1), 4)_"|"_$List(..AskedAt(2), 4), $List(..AskedAt(3), 4)_"|"_$List(..AskedAt(3), 4), "with one ItemId")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("EvalIn", "paused"))_"|"_$Get(^OcuTalonTest("EvalIn", "paused", 1))_"|"_$Get(^OcuTalonTest("EvalIn", "paused", 2)), "2|"_$Parameter(in, "BUSYWAIT")_"|"_$Parameter(in, "BUSYWAIT"), "BUSYWAIT seconds apart")
	Do $$$AssertEquals(..Delivered(), 1, "one TurnResult was delivered")
	Set delivered = ..DeliveredAt(1)
	Do $$$AssertEquals($List(delivered, 4)_"|"_$List(delivered, 6)_"|"_$List(delivered, 9), "zzDecisionRef000000003|Third time.|0", "the third reply is the one delivered")

	Do ..Reset()
	For n = 1:1:$Parameter(in, "BUSYMAX") + 1 {
		Set ^OcuTalonTest("EvalIn", "reply", n) = "busy"
	}
	Do $$$AssertEquals(..Process(service, "zz-busy"), "", "a case whose Decide is always busy is sent")
	Do $$$AssertEquals(..Asked(), $Parameter(in, "BUSYMAX") + 1, "Decide was asked BUSYMAX + 1 times")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("EvalIn", "paused")), $Parameter(in, "BUSYMAX"), "with BUSYMAX waits between the asks")
	Do $$$AssertEquals(..Delivered(), 1, "one TurnResult was delivered")
	Set delivered = ..DeliveredAt(1)
	Do $$$AssertEquals($List(delivered, 4)_"|"_$List(delivered, 6)_"|"_$List(delivered, 9)_"|"_$List(delivered, 10), "||1|rate_limited", "it is a fallback with the reason rate_limited, no DecisionRef and no text")

	Do ..Reset()
	Set ^OcuTalonTest("EvalIn", "reply", 1) = {"Fallback": true, "FallbackReason": "timeout", "DecisionRef": "zzDecisionRef000000004"}.%ToJSON()
	Do $$$AssertEquals(..Process(service, "zz-busy"), "", "a case whose Decide gives a fallback Reply is sent")
	Set delivered = ..DeliveredAt(1)
	Do $$$AssertEquals($List(delivered, 4)_"|"_$List(delivered, 6)_"|"_$List(delivered, 9)_"|"_$List(delivered, 10), "zzDecisionRef000000004||1|timeout", "the fallback is delivered as it is")
	Do $$$AssertEquals(..Asked(), 1, "and is not asked again")

	Do ..Reset()
	Set ^OcuTalonTest("EvalIn", "deliverFail") = "EvalSink is not there"
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do $$$AssertEquals(..Process(service, "zz-busy"), "", "a TurnResult that cannot be delivered does not skip the case")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Converse", $Parameter(in, "LOGNOTDELIVERED")), 1, "it is logged as a warning")
	Do $$$AssertTrue(text [ "EvalSink is not there", "with the error: "_text)
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Converse", $Parameter(in, "LOGNOTDELIVERED"))
	Set row = ##class(OcuTalon.Eval.Data.CaseResult).RunCaseIndexOpen(..Run, "zz-busy")
	Do $$$AssertTrue($IsObject(row), "and the row stays")
	If $IsObject(row) Do $$$AssertEquals(row.State, "sent", "in state sent")
}

/// A turn case that cannot be sent is refused with its reason before anything is saved; a Decide that gives no Reply, or whose call throws, skips the
/// case and leaves no row and no TurnResult.
Method TestTurnRefuses()
{
	Set service = ..Service()
	If '$IsObject(service) Quit
	Set in = "OcuTalon.Eval.In"
	Do ..WriteCase("zz-notext", {"kind": "command", "turn": {"text": "  "}}.%ToJSON())
	Do ..WriteCase("zz-noturn", {"kind": "command"}.%ToJSON())
	Do ..WriteCase("zz-turntext", {"kind": "all-clear", "turn": "Is everything fine?", "checks": []}.%ToJSON())
	Do ..WriteCase("zz-nochecks", {"kind": "all-clear", "turn": {"text": "Is everything fine?"}}.%ToJSON())
	Do ..WriteCase("zz-objchecks", {"kind": "all-clear", "turn": {"text": "Is everything fine?"}, "checks": {"result": "passed"}}.%ToJSON())
	Do ..WriteCase("zz-textchecks", {"kind": "all-clear", "turn": {"text": "Is everything fine?"}, "checks": "[]"}.%ToJSON())
	Set cases = $ListBuild($ListBuild("zz-notext", $Parameter(in, "REASONNOTEXT")), $ListBuild("zz-noturn", $Parameter(in, "REASONNOTEXT")), $ListBuild("zz-turntext", $Parameter(in, "REASONNOTEXT")), $ListBuild("zz-nochecks", $Parameter(in, "REASONNOCHECKS")), $ListBuild("zz-objchecks", $Parameter(in, "REASONNOCHECKS")), $ListBuild("zz-textchecks", $Parameter(in, "REASONNOCHECKS")))
	Set position = 0
	While $ListNext(cases, position, case) {
		Do $$$AssertEquals(..Process(service, $List(case, 1)), $List(case, 2), $List(case, 1)_": the reason")
	}
	Set bodies = 0
	Set position = 0
	While $ListNext(cases, position, case) {
		Set bodies = bodies + ..Bodies($List(case, 1))
	}
	Do $$$AssertEquals(..Asked()_"|"_..Delivered()_"|"_..Rows()_"|"_bodies, "0|0|0|0", "Decide was not asked, nothing was delivered, and no row and no TurnResult was saved")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..Mark, .text, "OnProcessInput", $Parameter(in, "LOGSKIPPED")), $ListLength(cases), "each case was logged as a warning")

	Do ..Reset()
	Do ..WriteCase("zz-noreply", {"kind": "all-clear", "turn": {"text": "Is everything fine?"}, "checks": []}.%ToJSON())
	Set forms = $ListBuild($ListBuild("error", "the call to Decide failed"), $ListBuild("throw", "the call to Decide threw"), $ListBuild("none", $Parameter(in, "REASONNOREPLY")), $ListBuild("nonreply", $Parameter(in, "REASONNOREPLY")))
	Set position = 0
	While $ListNext(forms, position, form) {
		Do ..Reset()
		Set ^OcuTalonTest("EvalIn", "reply", 1) = $List(form, 1)
		Set reason = ..Process(service, "zz-noreply")
		Do $$$AssertTrue(reason [ $List(form, 2), $List(form, 1)_": the case is skipped with the reason: "_reason)
		Do $$$AssertEquals(..Asked(), 1, $List(form, 1)_": Decide was asked once")
		Do $$$AssertEquals($List(..AskedAt(1), 13)_"|"_$List(..AskedAt(1), 15), "1|1", $List(form, 1)_": the TurnResult and the row existed when Decide was asked")
		Do $$$AssertEquals(..Delivered()_"|"_..Rows()_"|"_..Bodies("zz-noreply"), "0|0|0", $List(form, 1)_": nothing was delivered, and the row and the TurnResult are deleted")
	}

	Do ..Reset()
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Open(..Run, "zz-noreply", "zz-earlier", "zzearlier"_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 13)), "control: the run already has a row of the case")
	Set reason = ..Process(service, "zz-noreply")
	Do $$$AssertTrue(reason '= "", "a case whose row cannot be opened is skipped with the error text: "_reason)
	Do $$$AssertEquals(..Asked()_"|"_..Delivered()_"|"_..Rows()_"|"_..Bodies("zz-noreply"), "0|0|1|0", "Decide was not asked, nothing was delivered, its TurnResult is deleted, and the row that was there stays")
}

/// The turn kinds are sent first, then the others, each group in the order of the list.
Method TestSendOrder()
{
	Set folder = ##class(%File).SubDirectoryName(..Folder, "ordered")
	For entry = $ListBuild("zz-a", "item"), $ListBuild("zz-b", "all-clear"), $ListBuild("zz-c", "injection"), $ListBuild("zz-d", "command"), $ListBuild("zz-f", "incident") {
		Set directory = ##class(%File).SubDirectoryName(folder, $List(entry, 1))
		Do ##class(%File).CreateDirectoryChain(directory)
		Do ..WriteFile(directory, {"kind": ($List(entry, 2))}.%ToJSON())
	}
	Set directory = ##class(%File).SubDirectoryName(folder, "zz-e")
	Do ##class(%File).CreateDirectoryChain(directory)
	Do ..WriteFile(directory, "this is not json")
	Set in = "OcuTalon.Eval.In"
	Set list = $ClassMethod(in, "CaseNames", folder, "")
	Do $$$AssertEquals($ListToString(list, "|"), "zz-a|zz-b|zz-c|zz-d|zz-e|zz-f", "control: the folder lists its cases in name order")
	Do $$$AssertEquals($ListToString($ClassMethod(in, "SendOrder", folder, list), "|"), "zz-b|zz-d|zz-a|zz-c|zz-e|zz-f", "the all-clear and command cases come first, then the rest, each group in name order; a case whose kind cannot be read goes with the rest")
	Do $$$AssertEquals($ListToString($ClassMethod(in, "SendOrder", folder, $ListBuild("zz-d", "zz-c", "zz-b", "zz-a")), "|"), "zz-d|zz-b|zz-c|zz-a", "a list in another order keeps that order within each group")
	Do $$$AssertEquals($ListLength($ClassMethod(in, "SendOrder", folder, "")), 0, "an empty list gives an empty list")
	Do $$$AssertEquals($ListToString($ClassMethod(in, "SendOrder", folder, $ListBuild("zz-missing", "zz-b")), "|"), "zz-b|zz-missing", "and a case that is not there goes with the rest")
}

/// --- helpers ---
/// A shadow instance of the double, for the run of the test.
Method Service() As OcuTalon.Test.Eval.ZzIn [ Private ]
{
	Set service = ##class(Ens.Host).GetShadowInstance("class||"_..#DOUBLE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the EvalIn double is made")
	If '$IsObject(service) Quit ""
	Set service.RunRef = ..Run
	Quit service
}

/// Hands the case's folder to the service; the reason it was not sent, or "".
Method Process(service As OcuTalon.Test.Eval.ZzIn, name As %String) As %String [ Private ]
{
	Kill output
	Set input = ##class(Ens.StringContainer).%New(##class(%File).SubDirectoryName(..Folder, name))
	Do $$$AssertStatusOK(service.OnProcessInput(input, .output), name_": OnProcessInput answers OK")
	Quit output.StringValue
}

/// Writes the case.json of a case folder.
Method WriteCase(name As %String, text As %String) [ Private ]
{
	Set directory = ##class(%File).SubDirectoryName(..Folder, name)
	Do ##class(%File).CreateDirectoryChain(directory)
	Do ..WriteFile(directory, text)
}

/// Writes the case.json of a folder.
Method WriteFile(directory As %String, text As %String) [ Private ]
{
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set stream.Filename = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.In).#CASEFILE, directory)
	Do stream.Write(text)
	Do $$$AssertStatusOK(stream.%Save(), "the case file is written")
}

/// How many Items the double was given.
ClassMethod Seen() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("EvalIn", "seen"))
}

/// The nth Item the double was given, as a list: ItemId, SourceItemId, SessionRef, Channel, Provenance, Sender, Subject, Text, CatalogKey,
/// Slots, the service's SuperSession and 1 when the case's row was open.
ClassMethod SeenAt(n As %Integer) As %List [ Private ]
{
	Quit $Get(^OcuTalonTest("EvalIn", "seen", n))
}

/// How many requests the double was asked to send to Decide.
ClassMethod Asked() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("EvalIn", "asked"))
}

/// The nth request the double was asked to send, as a list: Kind, Provenance, OwnerRef, ItemId, Input, Summary, TraceRef, Channel, ThreadSessionId,
/// SessionMode, SeedText, SystemNote, 1 when the case's TurnResult existed, its RecordedChecks, 1 when the case's row was open and the service's
/// SuperSession.
ClassMethod AskedAt(n As %Integer) As %List [ Private ]
{
	Quit $Get(^OcuTalonTest("EvalIn", "asked", n))
}

/// How many TurnResults the double was asked to deliver.
ClassMethod Delivered() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("EvalIn", "delivered"))
}

/// The nth TurnResult the double was asked to deliver, as a list: ItemId, SourceItemId, RecordedChecks, DecisionRef, ToolsRun, ReplyText,
/// CatalogKey, CheckRows, Fallback, FallbackReason and the service's SuperSession.
ClassMethod DeliveredAt(n As %Integer) As %List [ Private ]
{
	Quit $Get(^OcuTalonTest("EvalIn", "delivered", n))
}

/// The number of TurnResult bodies whose SourceItemId is the case name.
ClassMethod Bodies(name As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Eval_Msg.TurnResult WHERE SourceItemId = ?", name)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of case rows of the run.
Method Rows() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Eval_Data.CaseResult WHERE RunRef = ?", ..Run)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// EvalIn's reason for a kind that it does not send: the kinds it sends joined with a comma, and with "and" before the last one.
ClassMethod KindReason(kind As %String) As %String [ Private ]
{
	Set kinds = $Parameter("OcuTalon.Eval.In", "KINDS"), count = $Length(kinds, ",")
	Set text = $Replace($Piece(kinds, ",", 1, count - 1), ",", ", ")_" and "_$Piece(kinds, ",", count)
	Quit $Replace($Replace($Parameter("OcuTalon.Eval.In", "REASONKIND"), "{kind}", kind), "{kinds}", text)
}

/// EvalIn's reason for a recorded provenance other than untrusted.
ClassMethod ProvenanceReason(provenance As %String) As %String [ Private ]
{
	Quit $Replace($Parameter("OcuTalon.Eval.In", "REASONPROVENANCE"), "{provenance}", provenance)
}

}
