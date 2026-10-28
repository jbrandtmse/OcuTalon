/// Tests of the evaluation runs through the running production (Story 9.1; AD-14, AD-16, AD-20, AD-22, AD-26, AD-30; CON-3).
/// THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), FRESH: they need OcuTalon.Production running with the CI mock, and EvalSink's running
/// job must hold the code under test. Where that is missing every test fails with the reason (Guard).
/// OnBeforeAllTests does the whole setup, and the tests only read what the two runs left:
///   - it points the runner keys at the mock, switches EvalIn on (the System Default Setting row, applied with UpdateProduction), takes
///     the marks of the tables that a run must not write and of the daily spend, and writes a fixture folder with the act case, a plain
///     case and the cases that EvalIn must refuse;
///   - run 1: Start over the repository's eval/ with the names mail-newsletter, orders-date-format and zz-missing;
///   - run 2: Start over the fixture folder with no names, which lists every subfolder that holds a case.json;
///   - it waits up to WAITRUN seconds for each run; a case still undecided is a failure of TestItemPath or TestActTurn, and the other
///     tests still read what the runs wrote.
/// The tests:
///   - TestItemPath (AC2): the newsletter case goes EvalIn to Intake as an Item of owner eval with the recorded id as SourceItemId and a
///     new ItemId, Intake asks Decide for a decide with the quoted mail, and EvalSink completes the row with the Decision's Ref and cost;
///   - TestActTurn: an act runs the read-only untrusted turn in a fresh AI session (SessionMode fresh, no SeedText), and the row holds
///     the turn's Decision and cost and the largest request over both decisions;
///   - TestTwoCases: the two sendable cases of run 2 are two trace sessions under the run's one SuperSession, each with its own Item, row
///     and decision;
///   - TestRefusals: each run lists the cases it did not send with their reasons, and makes a row for each case it sent;
///   - TestIsolation (AC3): no message of the runs reaches a router, a notice, a conversation, the digest, an approval, the incident
///     manager or any item ending in Out, and no Delivery, ApprovalRequest, live event or incident of another owner is written;
///   - TestUsage (AC3): every Usage row of the runs' items has owner eval, their cost is above 0, and the daily spend is unchanged;
///   - TestHops (AC3): the messages of the runs go from and to the items of the item path only, EvalIn sends only to Intake, and
///     EvalSink sends nothing.
/// OnAfterAllTests puts the EvalIn row, the runner keys, the case rows, the Decision, Usage and step rows, the AI sessions, the messages
/// and the fixture folder back as it found them, and fails the class when a case row, message, Decision or Usage row of the runs, or the
/// fixture folder, is still there.
Class OcuTalon.Test.Eval.Run Extends OcuTalon.Test.Core.InProduction
{

/// The item that sends the cases, and the one that completes them.
Parameter EVALIN = "EvalIn";

/// The seconds to wait for a run's cases to be decided.
Parameter WAITRUN = 120;

/// The cases of run 1: a recorded item case, a recorded incident case that EvalIn does not send, and a case that does not exist.
Parameter RUN1CASES = "mail-newsletter,orders-date-format,zz-missing";

/// The reasons that stay in the message of Missing at most.
Parameter MISSINGMAX = 200;

/// The items that a message of a run may come from or go to: the item path and nothing else (Task 10's list of items that must not
/// be reached is the denial; this is the permission, so an item that is not on it is a new hop that this story did not allow). They
/// are the ones a throwaway run was observed to use: EvalIn, Intake and EvalSink, Decide with the two agent runners it calls (the
/// attention decision's TriageAgent and the untrusted turn's ChatAgent), AgentSteps (which records their steps) and the Ens.Alarm
/// timer. None of them sends to a person.
Parameter ITEMPATH = "EvalIn,Intake,Decide,EvalSink,TriageAgent,ChatAgent,AgentSteps,Ens.Alarm";

/// 1 when the runner keys were pointed at the mock and must be put back.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// 1 when the EvalIn row was changed and must be put back.
Property Switched As %Boolean [ InitialExpression = 0 ];

/// 1 when EvalIn could be created before the test changed anything.
Property WasEnabled As %Boolean [ InitialExpression = 0 ];

/// The EvalIn row as it was found (RunnerFixture.SnapshotDefault).
Property Saved As %List;

/// The saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

/// The newest row of the event log when the test began.
Property LogMark As %Integer;

/// The folder of the fixture cases, with a trailing separator; empty when none was made.
Property Folder As %String(MAXLEN = 500);

/// The Refs of the two runs.
Property Run1 As %String(MAXLEN = 22);

Property Run2 As %String(MAXLEN = 22);

/// How many cases each run sent.
Property Sent1 As %Integer;

Property Sent2 As %Integer;

/// How many cases of each run were still undecided after the wait.
Property Open1 As %Integer;

Property Open2 As %Integer;

/// What each run did not send: a dynamic array of {"case","reason"}.
Property Skipped1 As %DynamicArray;

Property Skipped2 As %DynamicArray;

/// The largest ID of each table a run must not write, and the daily spend, when the test began.
Property Marks As %DynamicObject;

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	If ..Missing '= "" Quit sc
	Try {
		Set reason = ..Prepare()
	} Catch exception {
		Set reason = "the setup failed: "_exception.DisplayString()
	}
	If reason '= "" Set ..Missing = $Extract(reason, 1, ..#MISSINGMAX)
	Quit $$$OK
}

/// The setup; the reason it failed, or "". Each step that changes something records it first, so that OnAfterAllTests puts it back.
Method Prepare() As %String [ Private ]
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set reason = $ClassMethod(fixture, "ReadyReason")
	If reason '= "" Quit reason
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ..SessionMark = $ClassMethod(fixture, "SessionMark")
	Set ..Pointed = 1
	Set sc = $ClassMethod(fixture, "PointKeys")
	If $$$ISERR(sc) Quit "pointing the runner keys at the mock failed: "_$SYSTEM.Status.GetErrorText(sc)
	Set created = ##class(Ens.Director).CreateBusinessService(..#EVALIN, .service)
	Kill service
	Set ..WasEnabled = $$$ISOK(created)
	Set ..Saved = $ClassMethod(fixture, "SnapshotDefault", ..#EVALIN, "Enabled")
	Set ..Switched = 1
	Set sc = $ClassMethod(fixture, "PutDefault", ..#EVALIN, "Enabled", 1)
	If $$$ISERR(sc) Quit "switching EvalIn on failed: "_$SYSTEM.Status.GetErrorText(sc)
	Set sc = ..Apply(1)
	If $$$ISERR(sc) Quit "switching EvalIn on failed: "_$SYSTEM.Status.GetErrorText(sc)
	Set ..Marks = {"delivery": (..MaxId("OcuTalon_Data.Delivery")), "event": (..MaxId("OcuTalon_Live.Event")), "approval": (..MaxId("OcuTalon_Bridge_Data.ApprovalRequest")), "incident": (..MaxId("OcuTalon_Data.Incident")), "spent": (+##class(OcuTalon.Bridge.Budget).State().spent)}
	Set reason = ..WriteFixture()
	If reason '= "" Quit reason

	Set sc = ##class(OcuTalon.Eval.In).Start(##class(OcuTalon.Eval.In).#FOLDER, ..#RUN1CASES, .run, .sent, .skipped)
	If $$$ISERR(sc) Quit "run 1 did not start: "_$SYSTEM.Status.GetErrorText(sc)
	Set ..Run1 = run, ..Sent1 = sent, ..Skipped1 = skipped
	Do ..Supers.%Push(run)
	Set sc = ##class(OcuTalon.Eval.In).Start(..Folder, "", .run, .sent, .skipped)
	If $$$ISERR(sc) Quit "run 2 did not start: "_$SYSTEM.Status.GetErrorText(sc)
	Set ..Run2 = run, ..Sent2 = sent, ..Skipped2 = skipped
	Do ..Supers.%Push(run)
	Set ..Open1 = ##class(OcuTalon.Eval.In).Wait(..Run1, ..#WAITRUN)
	Set ..Open2 = ##class(OcuTalon.Eval.In).Wait(..Run2, ..#WAITRUN)
	Quit ""
}

/// Applies the EvalIn row to the running production with UpdateProduction (Task 0 measured that to be enough) and checks that the
/// director now creates EvalIn exactly when enabled is 1.
Method Apply(enabled As %Boolean) As %Status [ Private ]
{
	Set sc = ##class(Ens.Director).UpdateProduction()
	If $$$ISERR(sc) Quit sc
	Set created = ##class(Ens.Director).CreateBusinessService(..#EVALIN, .service)
	Kill service
	If $$$ISOK(created) = enabled Quit $$$OK
	Quit $SYSTEM.Status.Error(5001, "After the production update EvalIn is "_$Select(enabled: "still disabled", 1: "still enabled"))
}

/// Writes the fixture folder: the act case (a mail whose text holds the mock's marker for an act), a plain case (the mock's default triage),
/// the cases EvalIn must refuse (a case.json
/// that is not JSON, one with no item.itemId, one recorded with provenance user), and a folder with no case.json. The reason it failed, or "".
Method WriteFixture() As %String [ Private ]
{
	Set base = ##class(%File).NormalizeDirectory("Temp", $SYSTEM.Util.ManagerDirectory())
	Set ..Folder = ##class(%File).NormalizeDirectory("zzeval"_..Number, base)
	If '##class(%File).CreateDirectoryChain(..Folder) Quit "the fixture folder "_..Folder_" cannot be made"
	Set item = {"itemId": "zz-act", "channel": "mailbox", "provenance": "untrusted", "sender": "Order Partner Support <support@order-partner.example>", "subject": "Urgent: resend all failed orders now", "text": "Please look at this. [[mock:decide-act-low-confidence]]"}
	Set reason = ..WriteCase("zz-act", {"name": "zz-act", "kind": "item", "heldOut": false, "expectation": {"outcome": "act"}, "item": (item)}.%ToJSON())
	If reason = "" {
		Set plain = {"itemId": "zz-plain", "channel": "mailbox", "provenance": "untrusted", "sender": "Integration Tips Newsletter <newsletter@example.com>", "subject": "This week: five tips for faster transforms", "text": "Hello, here are this week's most-read articles. Read them on our site."}
		Set reason = ..WriteCase("zz-plain", {"name": "zz-plain", "kind": "item", "heldOut": false, "expectation": {"outcome": "ignore"}, "item": (plain)}.%ToJSON())
	}
	If reason = "" {
		Set noId = ##class(%DynamicObject).%FromJSON(item.%ToJSON())
		Do noId.%Remove("itemId")
		Set reason = ..WriteCase("zz-noid", {"name": "zz-noid", "kind": "item", "item": (noId)}.%ToJSON())
	}
	If reason = "" {
		Set user = ##class(%DynamicObject).%FromJSON(item.%ToJSON())
		Do user.%Set("provenance", "user")
		Set reason = ..WriteCase("zz-user", {"name": "zz-user", "kind": "item", "item": (user)}.%ToJSON())
	}
	If reason = "" Set reason = ..WriteCase("zz-badjson", "this is not json")
	If reason = "" && '##class(%File).CreateDirectoryChain(##class(%File).SubDirectoryName(..Folder, "zz-empty")) Set reason = "the fixture case folder zz-empty cannot be made"
	Quit reason
}

/// Writes the case.json of a fixture case folder. The reason it failed, or "".
Method WriteCase(name As %String, text As %String) As %String [ Private ]
{
	Set directory = ##class(%File).SubDirectoryName(..Folder, name)
	If '##class(%File).CreateDirectoryChain(directory) Quit "the fixture case folder "_name_" cannot be made"
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set stream.Filename = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.In).#CASEFILE, directory)
	Do stream.Write(text)
	Set sc = stream.%Save()
	Quit $Select($$$ISERR(sc): "the case file of "_name_" cannot be written: "_$SYSTEM.Status.GetErrorText(sc), 1: "")
}

/// Puts back what OnBeforeAllTests changed: the EvalIn row and the production, the runner keys, the case rows, the Decision, Usage
/// and step rows of the runs' items, the AI sessions, the warnings, the fixture folder and the runs' messages, then checks that none
/// of the runs' case rows, messages, Decision or Usage rows or fixture folder is left (Leftovers); then the superclass runs. The status
/// is the error of the step that could not put its part back, or names what is left.
Method OnAfterAllTests() As %Status
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set sc = $$$OK
	If ..Switched {
		Set ..Switched = 0
		Do $ClassMethod(fixture, "RestoreDefault", ..Saved)
		Set sc = $$$ADDSC(sc, ..Apply(..WasEnabled))
	}
	If ..Pointed {
		Set ..Pointed = 0
		Set sc = $$$ADDSC(sc, $ClassMethod(fixture, "RestoreKeys"))
	}
	Set items = ""
	For number = 1, 2 {
		Set run = $Property($This, "Run"_number)
		If run = "" Continue
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ItemId FROM OcuTalon_Eval_Data.CaseResult WHERE RunRef = ?", run)
		While result.%Next() {
			Set items = items_$ListBuild(result.%Get("ItemId"))
		}
	}
	Set position = 0
	While $ListNext(items, position, itemId) {
		Do $ClassMethod(fixture, "DeleteSteps", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	For number = 1, 2 {
		Set run = $Property($This, "Run"_number)
		If run '= "" Do ##class(OcuTalon.Eval.Data.CaseResult).Remove(run)
	}
	If ..SessionMark '= "" Do $ClassMethod(fixture, "DropSince", ..SessionMark)
	If ..LogMark '= "" Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "OnProcessInput", ##class(OcuTalon.Eval.In).#LOGSKIPPED)
	If ..Folder '= "" Do ##class(%File).RemoveDirectoryTree(..Folder)
	Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Supers)
	Try {
		Set sc = $$$ADDSC(sc, ..Leftovers(items))
	} Catch exception {
		Set sc = $$$ADDSC(sc, exception.AsStatus())
	}
	Set super = ##super()
	Quit $$$ADDSC(sc, super)
}

/// OK when the clean-up left nothing of the runs; otherwise an error that names what is left: a run's case rows or messages, the
/// Decision or Usage rows of an Item of the runs, or the fixture folder.
Method Leftovers(items As %List) As %Status [ Private ]
{
	Set left = ""
	For number = 1, 2 {
		Set run = $Property($This, "Run"_number)
		If run = "" Continue
		If ..Count("OcuTalon_Eval_Data.CaseResult", "RunRef", run) Set left = left_", case rows of run "_number
		If ##class(OcuTalon.Test.Data.Fixture).Headers(run).%Size() Set left = left_", messages of run "_number
	}
	Set position = 0
	While $ListNext(items, position, itemId) {
		If ..Count("OcuTalon_Bridge_Data.Decision", "ItemId", itemId) + ..Count("OcuTalon_Bridge_Data.Usage", "ItemId", itemId) Set left = left_", Decision or Usage rows of the Item "_itemId
	}
	If (..Folder '= "") && ##class(%File).DirectoryExists(..Folder) Set left = left_", the fixture folder "_..Folder
	Quit $Select(left = "": $$$OK, 1: $SYSTEM.Status.Error(5001, "The clean-up left"_$Extract(left, 2, *)))
}

/// The number of rows of the table whose column holds the value. A query that fails throws.
ClassMethod Count(table As %String, column As %String, value As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_table_" WHERE "_column_" = ?", value)
	If result.%SQLCODE < 0 Throw ##class(%Exception.SQL).CreateFromSQLCODE(result.%SQLCODE, result.%Message)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The newsletter case of run 1 goes through the product's path and its row is completed from the Decision and Usage rows.
Method TestItemPath()
{
	If '..Guard() Quit
	Do $$$AssertEquals(..Sent1, 1, "run 1 sent one case")
	Do $$$AssertEquals(..Open1, 0, "and every case of run 1 was decided within "_..#WAITRUN_" seconds")
	Do $$$AssertEquals($Length(..Run1), 22, "run 1 has a 22-character Ref")
	Set rows = ..RowsOf(..Run1)
	Do $$$AssertEquals(rows.%Size(), 1, "run 1 has one row")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(..Run1)
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "EvalIn", "Intake")
	Do $$$AssertEquals(sent.%Size(), 1, "EvalIn sent one Item to Intake")
	Set row = ##class(OcuTalon.Eval.Data.CaseResult).RunCaseIndexOpen(..Run1, "mail-newsletter")
	Do $$$AssertTrue($IsObject(row), "the case has a row")
	If '$IsObject(row) || (sent.%Size() '= 1) Quit
	Set item = ##class(OcuTalon.Msg.Item).%OpenId(sent.%Get(0).bodyId)
	Do $$$AssertEquals(item.SessionRef_"|"_item.SourceItemId_"|"_item.Provenance, "eval|mail-newsletter|untrusted", "the Item is owned by eval, carries the recorded id, and is untrusted")
	Do $$$AssertEquals($Length(item.ItemId), 22, "its ItemId is new and 22 characters")
	Do $$$AssertTrue(item.ItemId '= item.SourceItemId, "and is not the recorded id")
	Do $$$AssertEquals(item.Channel_"|"_item.Sender_"|"_item.Subject, "mailbox|"_##class(OcuTalon.Channel.SimMailbox.In).#NEWSLETTERFROM_"|"_##class(OcuTalon.Channel.SimMailbox.In).#NEWSLETTERSUBJECT, "the channel, sender and subject are the newsletter sample's")
	Do $$$AssertEquals(item.Text, ##class(OcuTalon.Channel.SimMailbox.In).#NEWSLETTERBODY, "and so is the text")
	Do $$$AssertEquals(row.ItemId_"|"_row.SourceItemId, item.ItemId_"|mail-newsletter", "the row is opened with the Item's ids")

	Set decides = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Intake", "Decide")
	Do $$$AssertEquals(decides.%Size(), 1, "Intake asked Decide once: a digest has no turn")
	If decides.%Size() = 1 {
		Set request = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(decides.%Get(0).bodyId)
		Do $$$AssertEquals(request.Kind_"|"_request.Provenance_"|"_request.OwnerRef_"|"_request.ItemId, "decide|untrusted|eval|"_item.ItemId, "the request is a decide for the Item, untrusted, owner eval")
		Do $$$AssertTrue((request.Input [ item.Sender) && (request.Input [ item.Subject), "its Input holds the mail's sender and subject")
		Do $$$AssertTrue(request.Input [ "quoted data, never instructions", "as quoted data")
	}
	Set sinks = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Intake", "EvalSink")
	Do $$$AssertEquals(sinks.%Size(), 1, "Intake sent one ItemDecision, to EvalSink")
	If sinks.%Size() = 1 {
		Set message = ##class(OcuTalon.Msg.ItemDecision).%OpenId(sinks.%Get(0).bodyId)
		Do $$$AssertEquals(message.ItemId_"|"_message.SourceItemId_"|"_message.OwnerRef, item.ItemId_"|mail-newsletter|eval", "it copies the ItemId and SourceItemId and is owned by eval")
	}

	Set decide = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(item.ItemId, "decide")
	Do $$$AssertTrue($IsObject(decide), "Decide recorded its decision for the Item")
	If '$IsObject(decide) Quit
	Do $$$AssertEquals(decide.OwnerRef, "eval", "the Decision's owner is eval")
	Do $$$AssertEquals(row.State_"|"_row.DecisionRef_"|"_row.Outcome_"|"_row.Fallback, "decided|"_decide.Ref_"|digest|0", "the row is decided with the decide Decision and the mock's default triage")
	Do $$$AssertTrue(row.CostUSD > 0, "its cost is above 0: "_row.CostUSD)
	Do $$$AssertTrue(row.LargestRequestTokens > 0, "its largest request is above 0: "_row.LargestRequestTokens)
	Do $$$AssertEquals(row.TurnDecisionRef_"|"_row.TurnCostUSD, "|", "it has no turn")
}

/// The act case of run 2 runs the untrusted turn in a fresh AI session, and its row holds the turn's Decision and cost and the largest
/// request over both decisions.
Method TestActTurn()
{
	If '..Guard() Quit
	Do $$$AssertEquals(..Sent2, 2, "run 2 sent two cases")
	Do $$$AssertEquals(..Open2, 0, "and every case of run 2 was decided within "_..#WAITRUN_" seconds")
	Set row = ##class(OcuTalon.Eval.Data.CaseResult).RunCaseIndexOpen(..Run2, "zz-act")
	Do $$$AssertTrue($IsObject(row), "the act case has a row")
	If '$IsObject(row) Quit
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(..Run2)
	Set all = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Intake", "Decide")
	Set decides = [], turnRequest = ""
	For i = 0:1:all.%Size() - 1 {
		Set request = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(all.%Get(i).bodyId)
		If request.ItemId '= row.ItemId Continue
		Do decides.%Push(request.Kind)
		If request.Kind = "turn" Set turnRequest = request
	}
	Do $$$AssertEquals(all.%Size(), 3, "Intake asked Decide three times in run 2: the decide and the turn of the act case, and the decide of the plain case")
	Do $$$AssertEquals(decides.%Size(), 2, "two of them are for the act case: the decide and the turn")
	Do $$$AssertTrue($IsObject(turnRequest), "one of them is a turn request")
	If $IsObject(turnRequest) {
		Do $$$AssertEquals(turnRequest.Kind_"|"_turnRequest.Provenance_"|"_turnRequest.SessionMode_"|"_turnRequest.OwnerRef, "turn|untrusted|fresh|eval", "the turn is untrusted, in a fresh session, for the owner eval")
		Do $$$AssertEquals(turnRequest.SeedText, "", "and has no SeedText")
		Do $$$AssertEquals(turnRequest.ItemId, row.ItemId, "for the Item of the case")
	}
	Set decide = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(row.ItemId, "decide")
	Set turn = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(row.ItemId, "turn")
	Do $$$AssertTrue($IsObject(decide) && $IsObject(turn), "Decide recorded a decide and a turn Decision for the Item")
	If '$IsObject(decide) || '$IsObject(turn) Quit
	Do $$$AssertEquals(row.State_"|"_row.DecisionRef_"|"_row.Outcome_"|"_row.Fallback, "decided|"_decide.Ref_"|act|0", "the row is decided with the decide Decision and the act")
	Do $$$AssertEquals(row.TurnDecisionRef, turn.Ref, "TurnDecisionRef is the turn Decision's Ref")
	Do $$$AssertTrue(row.TurnCostUSD > 0, "TurnCostUSD is above 0: "_row.TurnCostUSD)
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(LargestRequestTokens) FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef IN (?, ?)", decide.Ref, turn.Ref)
	Do result.%Next()
	Do $$$AssertTrue(result.%GetData(1) > 0, "the Usage rows of both decisions have a largest request: "_result.%GetData(1))
	Do $$$AssertEquals(row.LargestRequestTokens, result.%GetData(1), "LargestRequestTokens is the largest over both decisions")
}

/// Each run lists the cases it did not send, with their reasons, and made one row.
Method TestRefusals()
{
	If '..Guard() Quit
	Set in = "OcuTalon.Eval.In"
	Do $$$AssertEquals(..Reasons(..Skipped1), "orders-date-format|"_..Kind("incident")_";zz-missing|"_$Parameter(in, "REASONNOCASEFILE"), "run 1 skipped the incident case and the case that is not there")
	Do $$$AssertEquals(..Reasons(..Skipped2), "zz-badjson|"_$Parameter(in, "REASONNOTJSON")_";zz-noid|"_$Parameter(in, "REASONNOITEMID")_";zz-user|"_$Replace($Parameter(in, "REASONPROVENANCE"), "{provenance}", "user"), "run 2 skipped the three refused cases and does not list the folder with no case.json")
	Do $$$AssertEquals(..RowsOf(..Run1).%Size(), 1, "run 1 made one row")
	Do $$$AssertEquals(..RowsOf(..Run2).%Size(), 2, "run 2 made two rows")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Eval_Data.CaseResult WHERE (RunRef = ? OR RunRef = ?) AND CaseName IN ('orders-date-format', 'zz-missing', 'zz-badjson', 'zz-noid', 'zz-user', 'zz-empty')", ..Run1, ..Run2)
	Do result.%Next()
	Do $$$AssertEquals(+result.%GetData(1), 0, "no skipped case has a row")
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(..Run1), 1, "EvalIn", "Intake")
	Do $$$AssertEquals(sent.%Size(), 1, "run 1 sent one message")
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(..Run2), 1, "EvalIn", "Intake")
	Do $$$AssertEquals(sent.%Size(), 2, "run 2 sent two messages")
	Set mark = ..LogMark
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "OnProcessInput", $Parameter(in, "LOGSKIPPED")), 5, "each of the five cases not sent was logged as a warning")
}

/// The two sendable cases of run 2 are two trace sessions under the run's one SuperSession, each with its own Item, row and decision.
Method TestTwoCases()
{
	If '..Guard() Quit
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set sent = $ClassMethod(fixture, "Between", $ClassMethod(fixture, "Headers", ..Run2), 1, "EvalIn", "Intake")
	Do $$$AssertEquals(sent.%Size(), 2, "EvalIn sent two Items to Intake in run 2")
	If sent.%Size() '= 2 Quit
	Set first = sent.%Get(0), second = sent.%Get(1)
	Do $$$AssertEquals(first.superSession_"|"_second.superSession, ..Run2_"|"_..Run2, "both carry the run's Ref as the SuperSession")
	Do $$$AssertTrue((first.sessionId '= "") && (second.sessionId '= "") && (first.sessionId '= second.sessionId), "each is its own trace session: "_first.sessionId_" and "_second.sessionId)
	Do $$$AssertTrue((first.sessionId '= ..Run2) && (second.sessionId '= ..Run2), "and neither is the run's Ref")
	For header = first, second {
		Set decisions = $ClassMethod(fixture, "Between", $ClassMethod(fixture, "SessionHeaders", header.sessionId), 1, "Intake", "EvalSink")
		Do $$$AssertEquals(decisions.%Size(), 1, "the trace session "_header.sessionId_" holds its own ItemDecision for EvalSink")
	}
	Set one = ##class(OcuTalon.Msg.Item).%OpenId(first.bodyId), two = ##class(OcuTalon.Msg.Item).%OpenId(second.bodyId)
	Do $$$AssertTrue(one.ItemId '= two.ItemId, "the Items have ItemIds of their own")
	Do $$$AssertEquals(one.SourceItemId_"|"_two.SourceItemId, "zz-act|zz-plain", "and the recorded ids of the two cases, in name order")
	Set plain = ##class(OcuTalon.Eval.Data.CaseResult).RunCaseIndexOpen(..Run2, "zz-plain")
	Do $$$AssertTrue($IsObject(plain), "the plain case has a row")
	If '$IsObject(plain) Quit
	Do $$$AssertEquals(plain.State_"|"_plain.Outcome_"|"_plain.ItemId, "decided|digest|"_two.ItemId, "decided as a digest, for its own Item")
	Do $$$AssertTrue(plain.CostUSD > 0, "with a cost above 0: "_plain.CostUSD)
	Do $$$AssertEquals(plain.TurnDecisionRef, "", "and no turn")
}

/// No message of the runs reaches anyone, and no table that a user sees is written.
Method TestIsolation()
{
	If '..Guard() Quit
	Set bad = "", notices = 0, checked = 0
	For run = ..Run1, ..Run2 {
		Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(run)
		Set iterator = headers.%GetIterator()
		While iterator.%GetNext(, .header) {
			Set checked = checked + 1
			Set target = header.target
			If $ListFind($ListFromString("OutcomeRouter,Notify,Conversation,DigestStore,ApprovalHold,OcuTalonApprovals,IncidentManager"), target) || ($Length(target) > 3 && ($Extract(target, $Length(target) - 2, $Length(target)) = "Out")) {
				Set bad = bad_" "_target
			}
			If header.bodyClass = "OcuTalon.Msg.Notification" Set notices = notices + 1
		}
	}
	Do $$$AssertTrue(checked > 6, "the runs sent messages (a control): "_checked)
	Do $$$AssertEquals(bad, "", "no message of the runs is addressed to a router, notice, conversation, digest, approval, incident or Out item")
	Do $$$AssertEquals(notices, 0, "and none carries a Notification")
	Do $$$AssertEquals(..CountAbove("OcuTalon_Data.Delivery", ..Marks.delivery, ""), 0, "no Delivery row was written")
	Do $$$AssertEquals(..CountAbove("OcuTalon_Bridge_Data.ApprovalRequest", ..Marks.approval, ""), 0, "no approval request was written")
	Do $$$AssertEquals(..CountAbove("OcuTalon_Data.Incident", ..Marks.incident, "(OwnerRef IS NULL OR OwnerRef <> 'eval')"), 0, "no incident of a session or instance was written")
	Set refs = ..Refs()
	Do $$$AssertTrue($ListLength(refs) >= 6, "the runs have refs to look for (a control): "_$ListLength(refs))
	Set found = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Payload FROM OcuTalon_Live.Event WHERE ID > ?", ..Marks.event)
	While result.%Next() {
		Set payload = result.%Get("Payload")
		Set position = 0
		While $ListNext(refs, position, ref) {
			If $Find(payload, ref) Set found = found + 1
		}
	}
	Do $$$AssertEquals(found, 0, "no live event holds a Ref of the runs")
}

/// The messages of the runs come from and go to the items of the item path only. This is the allowance behind TestIsolation's list of
/// refused targets: a hop to an item that is on neither list fails here. EvalIn sends only to Intake, EvalSink sends nothing, and the
/// control is that the two hops of the path were seen.
Method TestHops()
{
	If '..Guard() Quit
	Kill pairs, requests
	Set total = 0
	For run = ..Run1, ..Run2 {
		Set iterator = ##class(OcuTalon.Test.Data.Fixture).Headers(run).%GetIterator()
		While iterator.%GetNext(, .header) {
			Set total = total + 1
			Set pairs(header.source_">"_header.target) = ""
			If header.type = 1 Set requests(header.source_">"_header.target) = ""
		}
	}
	Set outside = "", list = "", pair = ""
	For {
		Set pair = $Order(pairs(pair))
		If pair = "" Quit
		Set list = list_$Select(list = "": "", 1: ", ")_pair
		Set source = $Piece(pair, ">", 1), target = $Piece(pair, ">", 2)
		If '$ListFind($ListFromString(..#ITEMPATH), source) || '$ListFind($ListFromString(..#ITEMPATH), target) Set outside = outside_" "_pair
	}
	Do $$$AssertTrue(total > 6, "the runs sent messages (a control): "_total)
	Do $$$AssertTrue($Data(pairs("EvalIn>Intake")) && $Data(pairs("Intake>EvalSink")), "the two hops of the path were seen (a control): "_list)
	Do $$$AssertEquals(outside, "", "every message of the runs is between items of the item path: "_list)
	Set fromIn = "", fromSink = ""
	Set pair = ""
	For {
		Set pair = $Order(requests(pair))
		If pair = "" Quit
		If $Piece(pair, ">", 1) = "EvalIn" Set fromIn = fromIn_" "_pair
		If $Piece(pair, ">", 1) = "EvalSink" Set fromSink = fromSink_" "_pair
	}
	Do $$$AssertEquals(fromIn, " EvalIn>Intake", "EvalIn sends requests only to Intake")
	Do $$$AssertEquals(fromSink, "", "EvalSink sends no request")
}

/// Every Usage row of the runs' items is owned by eval (the rows are found by the ItemId that EvalIn opened its rows with, so a run that
/// EvalSink did not complete is checked too), the decisions that EvalSink recorded have rows, their cost is above 0, and the daily spend
/// is unchanged.
Method TestUsage()
{
	If '..Guard() Quit
	Set rows = 0, others = 0, cost = 0, decisions = 0, uncovered = 0
	For number = 1, 2 {
		Set cases = ..RowsOf($Property($This, "Run"_number))
		Set iterator = cases.%GetIterator()
		While iterator.%GetNext(, .case) {
			Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT OwnerRef, CostUSD FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", case.itemId)
			While result.%Next() {
				Set rows = rows + 1
				If result.%Get("OwnerRef") '= "eval" Set others = others + 1
				Set cost = cost + result.%Get("CostUSD")
			}
			For ref = case.decisionRef, case.turnDecisionRef {
				If ref = "" Continue
				Set decisions = decisions + 1
				Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ? AND OwnerRef = 'eval'", ref)
				Do result.%Next()
				If 'result.%GetData(1) Set uncovered = uncovered + 1
			}
		}
	}
	Do $$$AssertEquals(decisions, 4, "EvalSink recorded four decisions: three decide and one turn")
	Do $$$AssertEquals(uncovered, 0, "and each has a Usage row of the owner eval")
	Do $$$AssertTrue(rows >= 3, "the runs' items have at least three Usage rows: "_rows)
	Do $$$AssertEquals(others, 0, "every one is owned by eval")
	Do $$$AssertTrue(cost > 0, "their cost is above 0, so the next check can fail: "_cost)
	Do $$$AssertEquals(+##class(OcuTalon.Bridge.Budget).State().spent, ..Marks.spent, "the daily spend is as it was before the runs")
}

/// --- helpers ---
/// The rows of the run, as a dynamic array of {"caseName","itemId","decisionRef","turnDecisionRef"}, in ID order.
Method RowsOf(run As %String) As %DynamicArray [ Private ]
{
	Set rows = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT CaseName, ItemId, DecisionRef, TurnDecisionRef FROM OcuTalon_Eval_Data.CaseResult WHERE RunRef = ? ORDER BY ID", run)
	While result.%Next() {
		Do rows.%Push({"caseName": (result.%Get("CaseName")), "itemId": (result.%Get("ItemId")), "decisionRef": (result.%Get("DecisionRef")), "turnDecisionRef": (result.%Get("TurnDecisionRef"))})
	}
	Quit rows
}

/// The run Refs, and the ItemId, DecisionRef and TurnDecisionRef of every row of the runs, as a list.
Method Refs() As %List [ Private ]
{
	Set refs = $ListBuild(..Run1, ..Run2)
	For number = 1, 2 {
		Set iterator = ..RowsOf($Property($This, "Run"_number)).%GetIterator()
		While iterator.%GetNext(, .case) {
			For ref = case.itemId, case.decisionRef, case.turnDecisionRef {
				If ref '= "" Set refs = refs_$ListBuild(ref)
			}
		}
	}
	Quit refs
}

/// A skipped list as "case|reason" entries joined by semicolons.
ClassMethod Reasons(skipped As %DynamicArray) As %String [ Private ]
{
	Set text = ""
	For i = 0:1:skipped.%Size() - 1 {
		Set text = text_$Select(text = "": "", 1: ";")_skipped.%Get(i).case_"|"_skipped.%Get(i).reason
	}
	Quit text
}

/// EvalIn's reason for a kind that holds no recorded Item.
ClassMethod Kind(kind As %String) As %String [ Private ]
{
	Quit $Replace($Replace($Parameter("OcuTalon.Eval.In", "REASONKIND"), "{kind}", kind), "{kinds}", $Replace($Parameter("OcuTalon.Eval.In", "KINDS"), ",", " and "))
}

/// The largest ID of the table, or 0.
ClassMethod MaxId(table As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM "_table)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of rows of the table with an ID above the mark, that also meet the condition (an SQL condition, or "" for none).
ClassMethod CountAbove(table As %String, mark As %Integer, condition As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_table_" WHERE ID > ?"_$Select(condition '= "": " AND "_condition, 1: ""), mark)
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
