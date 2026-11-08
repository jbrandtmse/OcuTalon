/// Tests that a "Remember that ..." chat message gets a usable attention decision (Story 30.9, DW-890; AD-6, AD-7, AD-8, AD-22).
/// THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case. A message goes through WebChatIn to the
/// real Conversation, the real Decide and the real Chat and Triage runners, against the CI mock. The mock's default scripts answer the two
/// forms, so each form's own text reaches the decide as written; the reproduction adds the marker of the scenario remember-no-confidence,
/// whose decide reply has a valid outcome, two reasons and no confidence, which is the shape of the reply that Haiku gave on the demo. Each
/// test uses its own session and countdown key and clears its countdown; the reply check's refusal warnings logged after the test began are
/// removed, and the Decision rows of its turns are removed after it.
///   - TestTypedForm (AC 2): "Remember that the Orders partner contact is Kim." is decided tellnow, with no fallback and a confidence from 0 to 1,
///     in the Decision row and in the decision that the done chat.message shows, and no refusal warning names the decision;
///   - TestPanelForm (AC 2): the same for the text of the guide's Ask it to remember control, as the panel sends it;
///   - TestProbeShapeIsTheDemoWarning (AC 3): a decide reply with no confidence is refused by the reply check and falls back (tellnow, invalid, no
///     confidence), the strip's decision is that fallback, the turn is still done with Chat's reply, and exactly one warning names the decision,
///     with the words that the demo logged;
///   - TestEvalCase (AC 4): eval/user-turn-remember/case.json is the user-turn case of the remember request, with the panel's exact text.
Class OcuTalon.Test.Agent.RememberDecision Extends OcuTalon.Test.Watch.Case
{

Parameter SESSIONPREFIX = "zzremember";

/// The longest to wait for a turn, in seconds.
Parameter WAIT = 90;

/// The typed form, and the text that the guide's Ask it to remember control sends.
Parameter TYPED = "Remember that the Orders partner contact is Kim.";

Parameter PANEL = "Remember that the Results partner's contact is Lee.";

/// The scenario whose decide reply has no confidence.
Parameter SCENARIO = "remember-no-confidence";

/// The warning that the demo logged for the decision, after the decision's Ref.
Parameter DEMOTAIL = ": The reply check failed: the reply is not one JSON object that OcuTalon.Bridge.Msg.DecisionPayload accepts: ERROR #5001";

/// The markers whose countdown a test armed, comma-separated; OnAfterOneTest clears them.
Property Armed As %String(MAXLEN = "");

/// The number of the newest row of the event log before the test, for its warnings.
Property LogMark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Quit ##super(testname)
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Armed, ",") {
		If $Piece(..Armed, ",", i) '= "" Do ##class(OcuTalon.Test.Contract.Mock).Arm($Piece(..Armed, ",", i), "")
	}
	Set ..Armed = ""
	If ..LogMark '= "" Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Conclude", ##class(OcuTalon.Test.Bridge.ReplyCheck).#REFUSED)
	Set ..LogMark = ""
	Quit ##super(testname)
}

Method OnAfterAllTests() As %Status
{
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	Quit ##super()
}

/// AC 2: the typed form gets a usable decision.
Method TestTypedForm()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("typed")
	Set row = ..Ask(session, ..#TYPED, "", "typed", .done)
	If '$IsObject(row) Quit
	Do ..AssertUsable("typed form", row, done)
}

/// AC 2: the text of the panel's control gets a usable decision.
Method TestPanelForm()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("panel")
	Set row = ..Ask(session, ..#PANEL, "", "panel", .done)
	If '$IsObject(row) Quit
	Do ..AssertUsable("panel form", row, done)
}

/// AC 3: a decide reply with a valid outcome, two reasons and no confidence is refused, with the demo's warning.
Method TestProbeShapeIsTheDemoWarning()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("probe")
	Set row = ..Ask(session, ..#TYPED, ..#SCENARIO, "probe", .done)
	If '$IsObject(row) Quit
	Do ..AssertDemoFallback("reply without a confidence", row, done)
}

/// AC 4: the evaluation case of the remember request.
Method TestEvalCase()
{
	Set folder = ##class(%File).NormalizeDirectory(##class(OcuTalon.Eval.In).#FOLDER)
	Do $$$AssertTrue(##class(%File).DirectoryExists(folder), "the repository's eval/ is mounted at "_folder_" (a throwaway or CI stack)")
	If '##class(%File).DirectoryExists(folder) Quit
	Set case = ##class(OcuTalon.Test.Eval.Cases).Read(folder, "user-turn-remember")
	Do $$$AssertTrue($IsObject(case), "eval/user-turn-remember/case.json is in eval/")
	If '$IsObject(case) Quit
	Set productions = ##class(OcuTalon.Test.Eval.Cases).Read(folder, "user-turn-productions")
	Do $$$AssertTrue($IsObject(productions), "and so is the case whose expectation it shares")
	Do $$$AssertEquals(case.name_"|"_case.kind_"|"_case.heldOut, "user-turn-remember|user-turn|0", "it is a user-turn case, named for its folder, and not held out")
	Do $$$AssertEquals(case.turn.%ToJSON(), {"text": (..#PANEL)}.%ToJSON(), "it asks the panel's exact text, and nothing else")
	If $IsObject(productions) Do $$$AssertEquals(case.expectation.%ToJSON(), productions.expectation.%ToJSON(), "its expectation is that of user-turn-productions")
	Do $$$AssertEquals(case.recordedBy, "written for the evaluation set (Story 30.9, DW-890)", "it says it was written for Story 30.9")
	Set description = $ZConvert(case.description, "L")
	Do $$$AssertTrue(description [ "no fallback", "its description names no fallback")
	Do $$$AssertTrue(description [ "a confidence", "and a confidence")
	Set keys = ""
	Set iterator = case.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(keys, "name,kind,heldOut,description,turn,expectation,recordedBy", "it holds the fields of its kind and nothing else")
	Do $$$AssertTrue(##class(OcuTalon.Test.Eval.Cases).Plain(##class(%File).NormalizeFilename("case.json", ##class(%File).SubDirectoryName(folder, "user-turn-remember"))), "its file is plain ASCII")
}

/// --- helpers ---
/// Sends the text through WebChatIn as the session's next message, with the scenario's marker armed at 1 when a scenario is given, and gives
/// the Turn once it is done (or "" with a failed assertion). done is the payload of the done chat.message of the turn.
Method Ask(session As %String, text As %String, scenario As %String, tag As %String, Output done As %DynamicObject) As OcuTalon.Data.Turn [ Private ]
{
	Set done = ""
	Set sent = text
	If scenario '= "" {
		Set marker = scenario_":"_..Number_tag
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).Arm(marker, 1), "the countdown of "_marker_" is armed at 1")
		Set ..Armed = ..Armed_$Select(..Armed = "": "", 1: ",")_marker
		Set sent = text_$Char(10)_"[[mock:"_marker_"]]"
	}
	Set clientId = "zzr"_..Number_tag
	Do $$$AssertStatusOK(..Send(session, clientId, sent, .output), tag_": the message is accepted by WebChatIn")
	Set row = ..WaitDone(session, clientId)
	If $IsObject(row) Set ..ItemIds = ..ItemIds_$ListBuild(row.ItemId)
	If '$IsObject(row) || (row.State '= "done") {
		Do $$$AssertTrue(0, tag_": the Turn is done within "_..#WAIT_" seconds")
		Quit ""
	}
	Do $$$AssertEquals(row.State_"|"_row.FallbackReason_"|"_row.ReplyCatalogKey, "done||", tag_": the Turn is done with Chat's own reply")
	Set end = $ZHorolog + ..#WAIT
	For {
		Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "chat.message")
		Set iterator = events.%GetIterator()
		While iterator.%GetNext(, .event) {
			If (event.payload.ref = row.Ref) && (event.payload.state = "done") Set done = event.payload
		}
		If $IsObject(done) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Do $$$AssertTrue($IsObject(done), tag_": the stream holds the done chat.message of the turn")
	Quit row
}

/// The decide decision of the turn, and the decision that the done chat.message shows, are the same usable tell-now: no fallback and a
/// confidence from 0 to 1. No refusal warning names the decision.
Method AssertUsable(label As %String, row As OcuTalon.Data.Turn, done As %DynamicObject) [ Private ]
{
	Set decision = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(row.ItemId, "decide")
	Do $$$AssertTrue($IsObject(decision), label_": the decide decision is recorded")
	If $IsObject(decision) {
		Do $$$AssertEquals(decision.Ref, row.TriageDecisionRef, label_": it is the decision that the turn names")
		Do $$$AssertEquals(decision.Outcome_"|"_decision.Fallback_"|"_decision.FallbackReason, "tellnow|0|", label_": the Decision row is tellnow, with no fallback")
		Do $$$AssertTrue((decision.Confidence '= "") && (decision.Confidence >= 0) && (decision.Confidence <= 1), label_": the Decision row has a confidence from 0 to 1: "_decision.Confidence)
	}
	If $IsObject(done) {
		Set shown = done.decision
		Do $$$AssertTrue($IsObject(shown), label_": the done chat.message shows a decision")
		If $IsObject(shown) {
			Do $$$AssertEquals(shown.ref, row.TriageDecisionRef, label_": the strip shows the decide decision")
			Do $$$AssertEquals(shown.outcome_"|"_(+shown.fallback)_"|"_shown.fallbackReason, "tellnow|0|", label_": the strip shows tellnow, with no fallback")
			Do $$$AssertEquals(shown.%GetTypeOf("confidence"), "number", label_": the strip shows a confidence")
			Do $$$AssertTrue((shown.confidence >= 0) && (shown.confidence <= 1), label_": and it is from 0 to 1: "_shown.confidence)
		}
	}
	Set start = ##class(OcuTalon.Test.Bridge.ReplyCheck).#REFUSED
	Set start = start_row.TriageDecisionRef
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "Conclude", start)
	Do $$$AssertEquals(count, 0, label_": no refusal warning names the decision: "_text)
}

/// The decide decision of the turn is the fallback of a refused reply, the strip shows it, and exactly one warning names it, with the demo's words.
Method AssertDemoFallback(label As %String, row As OcuTalon.Data.Turn, done As %DynamicObject) [ Private ]
{
	Set decision = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(row.ItemId, "decide")
	Do $$$AssertTrue($IsObject(decision), label_": the decide decision is recorded")
	If $IsObject(decision) {
		Do $$$AssertEquals(decision.Ref, row.TriageDecisionRef, label_": it is the decision that the turn names")
		Do $$$AssertEquals(decision.Outcome_"|"_decision.Fallback_"|"_decision.FallbackReason, "tellnow|1|invalid", label_": the Decision row is the tellnow fallback, invalid")
		Do $$$AssertEquals(decision.Confidence, "", label_": it has no confidence")
	}
	If $IsObject(done) {
		Set shown = done.decision
		Do $$$AssertTrue($IsObject(shown), label_": the done chat.message shows a decision")
		If $IsObject(shown) {
			Do $$$AssertEquals(shown.ref, row.TriageDecisionRef, label_": the strip shows the decide decision")
			Do $$$AssertEquals(shown.outcome_"|"_(+shown.fallback)_"|"_shown.fallbackReason, "tellnow|1|invalid", label_": the strip shows the fallback")
			Do $$$AssertTrue(shown.%GetTypeOf("confidence") '= "number", label_": and no confidence")
		}
	}
	Set start = ##class(OcuTalon.Test.Bridge.ReplyCheck).#REFUSED
	Set start = start_row.TriageDecisionRef
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "Conclude", start)
	Do $$$AssertEquals(count, 1, label_": exactly one warning names the decision")
	Do $$$AssertEquals(text, start_..#DEMOTAIL, label_": and its text is the demo's")
}

}
