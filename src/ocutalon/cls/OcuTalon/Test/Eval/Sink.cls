/// Tests of EvalSink and the result table it completes (Story 9.1; AD-3, AD-5, AD-14, AD-20, AD-22, AD-30, AD-33). WARM-SAFE: they call
/// OnMessage on a shadow instance of OcuTalon.Eval.Sink with synthetic OcuTalon.Eval.Data.CaseResult rows opened as EvalIn opens
/// them, and synthetic Decision (decide, turn, diagnose) and Usage rows. They start no production, send no message and go through
/// no IncidentManager. Every Ref is a 22-character OcuTalon.Bridge.Ids.NewRef(); the run Refs and case names start with zz.
///   - TestDecide and TestDecideWithTurn: the row is completed with the message's DecisionRef, outcome and fallback fields, the cost of
///     the decision's Usage rows and the largest request over its rows only; with a turn Decision the turn's Ref and cost are added and
///     the largest request is taken over both decisions;
///   - TestIncident: a diagnose Decision gives the cause category, element at fault, fix kind and fix parameters (a JSON object as
///     text) from its payload, and the outcome and fallback fields still come from the message;
///   - TestNoFix and TestBadPayload: a payload with no fix leaves the fix empty; a payload that is not a JSON object leaves the four
///     cause fields empty and is logged as an error, and the row is decided either way;
///   - TestFallback: an ItemDecision with Fallback 1 and no DecisionRef leaves the cost and size fields empty;
///   - TestNoOpenRow: an ItemDecision for an ItemId with no sent row, and a second decision for a decided row, log a warning that names
///     the ItemId and the SourceItemId and store or change nothing;
///   - TestRefused: a message that is not an ItemDecision, and one whose owner is not eval, log a warning and store nothing;
///   - TestUnpriced: a cost that is not known is empty, never 0.
///   - TestCostFromUsage: the cost is read from the Usage rows, not from the Decision's own cost field;
///   - TestCauseOnlyFromDiagnose, TestLongValues, TestSaveFailure and TestNeverThrows: only a diagnose Decision's payload gives the
///     cause and the fix; values longer than the row's properties are cut and the row is still decided; a row that cannot be saved
///     stays sent and the failure is logged; an exception inside the completion is logged and the call still answers OK.
/// Every call answers OK with no response.
Class OcuTalon.Test.Eval.Sink Extends %UnitTest.TestCase
{

/// The start of every run Ref the tests make.
Parameter RUNPREFIX = "zz";

/// The start of every case name the tests make.
Parameter CASEPREFIX = "zz-sink-";

/// The method of EvalSink that logs the warnings.
Parameter WARNER = "Complete";

/// The class that Deliver makes a shadow instance of.
Parameter SINK = "OcuTalon.Eval.Sink";

/// The double whose size read can throw.
Parameter DOUBLE = "OcuTalon.Test.Eval.ZzSink";

/// The Refs of the Decision rows (and their Usage rows) that the test made, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the runs that the test made, comma-separated.
Property Runs As %String(MAXLEN = "");

/// The newest row of the event log when the test began.
Property Mark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Eval_Data.CaseResult WHERE RunRef %STARTSWITH ? AND CaseName %STARTSWITH ?", ..#RUNPREFIX, ..#CASEPREFIX)
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = "", ..Runs = ""
	Set ..Mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("EvalSink")
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	For i = 1:1:$Length(..Runs, ",") {
		If $Piece(..Runs, ",", i) '= "" Do ##class(OcuTalon.Eval.Data.CaseResult).Remove($Piece(..Runs, ",", i))
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type IN (2, 3) AND SourceClass IN (?, ?)", ..Mark, ..#SINK, ..#DOUBLE)
	Quit $$$OK
}

/// A decide Decision with two Usage rows is completed: the message's fields, the cost of the rows added up, and the largest of their
/// requests, not the last one's and not another decision's.
Method TestDecide()
{
	Set run = ..NewRun()
	Set itemId = ..Open(run, "decide", "source-decide")
	Set decision = ..Decision(itemId, "decide", {"CostUSD": (0.0005), "Outcome": "digest"})
	Do ..Usage(decision, 0.0002, 3400)
	Do ..Usage(decision, 0.0003, 1200)
	Set other = ..Decision(##class(OcuTalon.Bridge.Ids).NewRef(), "decide", {"Outcome": "digest"})
	Do ..Usage(other, 0.0009, 99999)
	Set before = ##class(OcuTalon.Bridge.Time).NowUtc()
	Do ..Deliver(..Message(itemId, "source-decide", decision, "digest"))
	Set after = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set row = ..RowOf(run, "decide")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State, "decided", "the row is decided")
	Do $$$AssertEquals(row.RunRef_"|"_row.CaseName_"|"_row.SourceItemId_"|"_row.ItemId, run_"|"_..#CASEPREFIX_"decide|source-decide|"_itemId, "the run, the case, the SourceItemId and the ItemId are the ones EvalIn opened")
	Do $$$AssertEquals(row.DecisionRef, decision, "the DecisionRef is the decide Decision's")
	Do $$$AssertEquals(row.Outcome, "digest", "the outcome is the message's")
	Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason, "0|", "it is not a fallback")
	Do $$$AssertEquals(+row.CostUSD, 0.0005, "the cost is the sum of the decision's Usage rows")
	Do $$$AssertEquals(row.LargestRequestTokens, 3400, "the largest request is the largest of the decision's Usage rows")
	Do $$$AssertEquals(row.TurnDecisionRef_"|"_row.TurnCostUSD, "|", "there is no turn")
	Do $$$AssertEquals(row.CauseCategory_row.ElementAtFault_row.FixKind_row.FixParameters, "", "a decide Decision gives no cause or fix")
	Do $$$AssertTrue(row.DecidedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "DecidedAt is UTC to the second: "_row.DecidedAt)
	Do $$$AssertTrue((before '] row.DecidedAt) && (row.DecidedAt '] after), "and lies between the clock before the call ("_before_") and after it ("_after_")")
}

/// An act with a turn Decision: the turn's Ref and cost are kept apart, and the largest request is the largest over both decisions.
Method TestDecideWithTurn()
{
	Set run = ..NewRun()
	Set itemId = ..Open(run, "turn", "source-turn")
	Set decision = ..Decision(itemId, "decide", {"CostUSD": (0.0004), "Outcome": "act"})
	Do ..Usage(decision, 0.0004, 5000)
	Set turn = ..Decision(itemId, "turn", {"CostUSD": (0.0007), "Outcome": "tellnow"})
	Do ..Usage(turn, 0.0003, 2000)
	Do ..Usage(turn, 0.0004, 9000)
	Do ..Deliver(..Message(itemId, "source-turn", decision, "act"))
	Set row = ..RowOf(run, "turn")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State_"|"_row.Outcome_"|"_row.DecisionRef, "decided|act|"_decision, "the row is decided with the act and the decide Decision")
	Do $$$AssertEquals(+row.CostUSD, 0.0004, "CostUSD is the attention decision's own cost, not the turn's")
	Do $$$AssertEquals(row.TurnDecisionRef, turn, "TurnDecisionRef is the turn Decision's Ref")
	Do $$$AssertEquals(+row.TurnCostUSD, 0.0007, "TurnCostUSD is the turn Decision's cost")
	Do $$$AssertEquals(row.LargestRequestTokens, 9000, "the largest request is taken over both decisions' Usage rows")
}

/// An incident decision: the diagnose Decision's payload gives the cause and the fix, the message gives the outcome and fallback fields.
Method TestIncident()
{
	Set run = ..NewRun()
	Set itemId = ..Open(run, "incident", "source-incident")
	Set payload = {"outcome": "act", "reasons": ["The order date arrives as MM/DD/YYYY."], "confidence": 0.9, "causeCategory": "data_format_change", "elementAtFault": "OrderDate", "evidence": [], "fixKind": "repair_resend", "fixParameters": {"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}, "cause": "The partner sends the order date in another format.", "fixSummary": "repair the order dates and resend the orders"}
	Set decision = ..Decision(itemId, "diagnose", {"Outcome": "act", "Payload": (payload.%ToJSON()), "CostUSD": (0.0006)})
	Do ..Usage(decision, 0.0006, 7000)
	Do ..Deliver(..Message(itemId, "source-incident", decision, "act"))
	Set row = ..RowOf(run, "incident")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State_"|"_row.DecisionRef_"|"_row.Outcome_"|"_row.Fallback, "decided|"_decision_"|act|0", "the row is decided with the diagnose Decision and the message's outcome")
	Do $$$AssertEquals(row.CauseCategory, "data_format_change", "the cause category is the payload's")
	Do $$$AssertEquals(row.ElementAtFault, "OrderDate", "the element at fault is the payload's, not the cause's")
	Do $$$AssertEquals(row.FixKind, "repair_resend", "the fix kind is the payload's")
	Do $$$AssertEquals(row.FixParameters, payload.fixParameters.%ToJSON(), "the fix parameters are the payload's object, as text")
	Do $$$AssertEquals(+row.CostUSD, 0.0006, "the cost is the diagnosis's")
	Do $$$AssertEquals(row.LargestRequestTokens, 7000, "and so is the largest request")
}

/// A diagnosis with no fix leaves the fix empty and keeps the cause.
Method TestNoFix()
{
	Set run = ..NewRun()
	Set itemId = ..Open(run, "nofix", "source-nofix")
	Set payload = {"outcome": "act", "reasons": ["The partner is down."], "confidence": 0.8, "causeCategory": "partner_outage", "elementAtFault": "OrdersOut", "evidence": [], "cause": "The partner's endpoint does not answer."}
	Set decision = ..Decision(itemId, "diagnose", {"Outcome": "act", "Payload": (payload.%ToJSON())})
	Do ..Deliver(..Message(itemId, "source-nofix", decision, "act"))
	Set row = ..RowOf(run, "nofix")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State, "decided", "the row is decided")
	Do $$$AssertEquals(row.CauseCategory_"|"_row.ElementAtFault, "partner_outage|OrdersOut", "the cause is kept")
	Do $$$AssertEquals(row.FixKind_row.FixParameters, "", "the fix kind and the fix parameters are empty")
}

/// A payload that is not a JSON object leaves the four cause fields empty, logs an error, and the row is still decided.
Method TestBadPayload()
{
	Set payloads = $ListBuild("this is not json {", "[1, 2]", "42")
	Set position = 0
	While $ListNext(payloads, position, text) {
		Set label = "payload '"_text_"': "
		Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
		Set run = ..NewRun()
		Set name = "bad"_position
		Set itemId = ..Open(run, name, "source-"_name)
		Set decision = ..Decision(itemId, "diagnose", {"Outcome": "act", "Payload": (text)})
		Do ..Deliver(..Message(itemId, "source-"_name, decision, "act"))
		Set row = ..RowOf(run, name)
		If '$IsObject(row) Continue
		Do $$$AssertEquals(row.State_"|"_row.DecisionRef_"|"_row.Outcome, "decided|"_decision_"|act", label_"the row is decided with the message's fields")
		Do $$$AssertEquals(row.CauseCategory_row.ElementAtFault_row.FixKind_row.FixParameters, "", label_"the four cause fields are empty")
		Set errors = ..Errors(mark, "ReadDiagnosis", ##class(OcuTalon.Eval.Sink).#LOGPAYLOAD_decision)
		Do $$$AssertEquals(errors, 1, label_"one error names the decision")
	}
}

/// A fallback with no DecisionRef keeps the message's fallback fields and leaves the cost and size empty; a diagnose fallback with an
/// empty payload leaves the cause empty and logs no error.
Method TestFallback()
{
	Set run = ..NewRun()
	Set itemId = ..Open(run, "fallback", "source-fallback")
	Set message = ..Message(itemId, "source-fallback", "", "tellnow")
	Set message.Fallback = 1
	Set message.FallbackReason = "unusable"
	Do ..Deliver(message)
	Set row = ..RowOf(run, "fallback")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State_"|"_row.Outcome_"|"_row.Fallback_"|"_row.FallbackReason, "decided|tellnow|1|unusable", "the row holds the message's fallback fields")
	Do $$$AssertEquals(row.DecisionRef_row.CostUSD_row.TurnDecisionRef_row.TurnCostUSD_row.LargestRequestTokens, "", "the Ref, the costs and the size are empty")

	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set itemId = ..Open(run, "diagnose-fallback", "source-diagnose-fallback")
	Set decision = ..Decision(itemId, "diagnose", {"Outcome": "tellnow", "Fallback": 1, "FallbackReason": "timeout"})
	Set message = ..Message(itemId, "source-diagnose-fallback", decision, "tellnow")
	Set message.Fallback = 1
	Set message.FallbackReason = "timeout"
	Do ..Deliver(message)
	Set row = ..RowOf(run, "diagnose-fallback")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State_"|"_row.DecisionRef_"|"_row.Fallback_"|"_row.FallbackReason, "decided|"_decision_"|1|timeout", "a diagnose fallback is decided with its Ref")
	Do $$$AssertEquals(row.CauseCategory_row.ElementAtFault_row.FixKind_row.FixParameters_row.CostUSD_row.LargestRequestTokens, "", "its cause, fix, cost and size are empty")
	Do $$$AssertEquals(..Errors(mark, "ReadDiagnosis", ##class(OcuTalon.Eval.Sink).#LOGPAYLOAD), 0, "an empty payload is no error")
}

/// An ItemDecision with no sent row, and a second decision for a decided row, log a warning that names the ItemId and SourceItemId
/// and store or change nothing.
Method TestNoOpenRow()
{
	Set start = ##class(OcuTalon.Eval.Sink).#LOGNOROW
	Set unknown = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set rows = ..CountRows()
	Do ..Deliver(..Message(unknown, "source-unknown", "", "digest"))
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, ..#WARNER, start)
	Do $$$AssertEquals(count, 1, "an ItemId EvalIn did not send logs one warning")
	Do $$$AssertTrue((text [ unknown) && (text [ "source-unknown"), "it names the ItemId and the SourceItemId: "_text)
	Do $$$AssertEquals(..CountRows(), rows, "and no row is stored")

	Set run = ..NewRun()
	Set itemId = ..Open(run, "twice", "source-twice")
	Set decision = ..Decision(itemId, "decide", {"Outcome": "digest"})
	Do ..Deliver(..Message(itemId, "source-twice", decision, "digest"))
	Set first = ..RowOf(run, "twice")
	If '$IsObject(first) Quit
	Set decidedAt = first.DecidedAt
	Hang 1.1
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set second = ..Decision(##class(OcuTalon.Bridge.Ids).NewRef(), "decide", {"Outcome": "tellnow"})
	Set message = ..Message(itemId, "source-twice", second, "tellnow")
	Set message.Fallback = 1
	Do ..Deliver(message)
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, ..#WARNER, start)
	Do $$$AssertEquals(count, 1, "a second decision for a decided row logs one warning")
	Do $$$AssertTrue((text [ itemId) && (text [ "source-twice"), "it names the ItemId and the SourceItemId: "_text)
	Set row = ..RowOf(run, "twice")
	Do $$$AssertEquals(row.State_"|"_row.DecisionRef_"|"_row.Outcome_"|"_row.Fallback_"|"_row.DecidedAt, "decided|"_decision_"|digest|0|"_decidedAt, "the decided row is unchanged")
}

/// A message that is not an ItemDecision, and an ItemDecision whose owner is not eval, are refused with a warning; the open row stays sent.
Method TestRefused()
{
	Set start = ##class(OcuTalon.Eval.Sink).#LOGREFUSED
	Set run = ..NewRun()
	Set itemId = ..Open(run, "refused", "source-refused")
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..Deliver(##class(Ens.StringRequest).%New("not a decision"))
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, ..#WARNER, start), 1, "a message that is not an ItemDecision logs one warning")
	Do $$$AssertTrue(text [ "not an ItemDecision", "and says why: "_text)

	Set decision = ..Decision(itemId, "decide", {"Outcome": "digest"})
	For owner = "instance", ##class(OcuTalon.Bridge.Ids).NewRef(), "" {
		Set label = "owner '"_$Select(owner = "": "(none)", $Length(owner) = 22: "a session", 1: owner)_"': "
		Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
		Set message = ..Message(itemId, "source-refused", decision, "digest")
		Set message.OwnerRef = owner
		Do ..Deliver(message)
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, ..#WARNER, start), 1, label_"one warning")
		Do $$$AssertTrue((text [ "not eval") && (text [ itemId), label_"it names the owner problem and the ItemId: "_text)
		Set row = ..RowOf(run, "refused")
		If '$IsObject(row) Continue
		Do $$$AssertEquals(row.State_"|"_row.DecisionRef_"|"_row.Outcome_"|"_row.DecidedAt, "sent|||", label_"the row is still sent and holds nothing")
	}
}

/// A cost that is not known is empty, never 0: one unpriced Usage row makes the decision's cost empty, and a turn Decision with no cost
/// leaves the turn's cost empty.
Method TestUnpriced()
{
	Set run = ..NewRun()
	Set itemId = ..Open(run, "unpriced", "source-unpriced")
	Set decision = ..Decision(itemId, "decide", {"Outcome": "act"})
	Do ..Usage(decision, 0.0002, 1000)
	Do ..Usage(decision, "", 2000)
	Set turn = ..Decision(itemId, "turn", {"Outcome": "tellnow"})
	Do ..Usage(turn, "", 4000)
	Do ..Deliver(..Message(itemId, "source-unpriced", decision, "act"))
	Set row = ..RowOf(run, "unpriced")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State, "decided", "the row is decided")
	Do $$$AssertEquals(row.CostUSD, "", "one unpriced Usage row makes the cost empty, not 0")
	Do $$$AssertEquals(row.TurnDecisionRef_"|"_row.TurnCostUSD, turn_"|", "the turn's cost is empty, not 0")
	Do $$$AssertEquals(row.LargestRequestTokens, 4000, "the size is still read")
}

/// The cost of the attention decision is read from its Usage rows, not from the Decision's own CostUSD: a Decision whose cost differs
/// from the sum of its Usage rows gives the sum, and a Decision that holds a cost but has an unpriced Usage row gives an empty cost.
/// The turn's cost is the turn Decision's own.
Method TestCostFromUsage()
{
	Set run = ..NewRun()
	Set itemId = ..Open(run, "costsource", "source-costsource")
	Set decision = ..Decision(itemId, "decide", {"CostUSD": (0.0090), "Outcome": "act"})
	Do ..Usage(decision, 0.0002, 1000)
	Do ..Usage(decision, 0.0003, 2000)
	Set turn = ..Decision(itemId, "turn", {"CostUSD": (0.0011), "Outcome": "tellnow"})
	Do ..Usage(turn, 0.0004, 3000)
	Do ..Deliver(..Message(itemId, "source-costsource", decision, "act"))
	Set row = ..RowOf(run, "costsource")
	If $IsObject(row) {
		Do $$$AssertEquals(+row.CostUSD, 0.0005, "the cost is the sum of the Usage rows, not the Decision's own 0.0090")
		Do $$$AssertEquals(+row.TurnCostUSD, 0.0011, "the turn's cost is the turn Decision's own, not its Usage rows' 0.0004")
	}

	Set unpricedItemId = ..Open(run, "costunpriced", "source-costunpriced")
	Set unpriced = ..Decision(unpricedItemId, "decide", {"CostUSD": (0.0090), "Outcome": "digest"})
	Do ..Usage(unpriced, 0.0002, 1000)
	Do ..Usage(unpriced, "", 2000)
	Do ..Deliver(..Message(unpricedItemId, "source-costunpriced", unpriced, "digest"))
	Set row = ..RowOf(run, "costunpriced")
	If $IsObject(row) Do $$$AssertEquals(row.CostUSD, "", "an unpriced Usage row makes the cost empty although the Decision holds a cost")
}

/// Only a diagnose Decision's payload gives the cause and the fix. A decide Decision whose payload holds the same keys leaves the four
/// cause fields empty (the row is still decided with the message's fields).
Method TestCauseOnlyFromDiagnose()
{
	Set payload = {"outcome": "act", "causeCategory": "data_format_change", "elementAtFault": "OrderDate", "fixKind": "repair_resend", "fixParameters": {"field": "OrderDate"}}.%ToJSON()
	Set run = ..NewRun()
	Set itemId = ..Open(run, "kindguard", "source-kindguard")
	Set decision = ..Decision(itemId, "decide", {"Outcome": "act", "Payload": (payload)})
	Set turn = ..Decision(itemId, "turn", {"Outcome": "tellnow", "Payload": (payload)})
	Do ..Usage(decision, 0.0001, 100)
	Do ..Deliver(..Message(itemId, "source-kindguard", decision, "act"))
	Set row = ..RowOf(run, "kindguard")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State_"|"_row.DecisionRef_"|"_row.Outcome_"|"_row.TurnDecisionRef, "decided|"_decision_"|act|"_turn, "the row is decided with the decide Decision and the turn")
	Do $$$AssertEquals(row.CauseCategory_row.ElementAtFault_row.FixKind_row.FixParameters, "", "a decide Decision's payload is not read for a cause or a fix")
}

/// A payload is a model's words. Values longer than the row's properties are cut to their length, and the row is still decided
/// (a row that kept the long value could not be saved and would stay sent).
Method TestLongValues()
{
	Set category = $Translate($Justify("", 100), " ", "c"), element = $Translate($Justify("", 200), " ", "e"), kind = $Translate($Justify("", 50), " ", "k")
	Set run = ..NewRun()
	Set itemId = ..Open(run, "long", "source-long")
	Set payload = {"outcome": "act", "causeCategory": (category), "elementAtFault": (element), "fixKind": (kind), "fixParameters": {"field": "OrderDate"}}
	Set decision = ..Decision(itemId, "diagnose", {"Outcome": "act", "Payload": (payload.%ToJSON())})
	Do ..Deliver(..Message(itemId, "source-long", decision, "act"))
	Set row = ..RowOf(run, "long")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State_"|"_row.DecisionRef, "decided|"_decision, "the row is decided")
	Do $$$AssertEquals(row.CauseCategory, $Extract(category, 1, 64), "the cause category is cut to 64 characters")
	Do $$$AssertEquals(row.ElementAtFault, $Extract(element, 1, 128), "the element at fault is cut to 128 characters")
	Do $$$AssertEquals(row.FixKind, $Extract(kind, 1, 32), "the fix kind is cut to 32 characters")
	Do $$$AssertEquals(row.FixParameters, payload.fixParameters.%ToJSON(), "and the fix parameters are the payload's object")
}

/// A row that cannot be saved (an outcome longer than the row's property) stays sent, the failure is logged as one error, and the
/// call answers OK with no response.
Method TestSaveFailure()
{
	Set run = ..NewRun()
	Set itemId = ..Open(run, "savefail", "source-savefail")
	Set decision = ..Decision(itemId, "decide", {"Outcome": "digest"})
	Set message = ..Message(itemId, "source-savefail", decision, "digest")
	Set message.Outcome = $Translate($Justify("", 40), " ", "o")
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..Deliver(message)
	Set row = ..RowOf(run, "savefail")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State_"|"_row.DecisionRef_"|"_row.Outcome_"|"_row.DecidedAt, "sent|||", "the row is left as it was: sent, with nothing of the decision")
	Do $$$AssertEquals(..Errors(mark, ..#WARNER, ##class(OcuTalon.Eval.Sink).#LOGFAILED), 1, "one error says that the row could not be completed")
}

/// OnMessage never throws. An exception inside the completion (the double's size read throws) is logged as one error that carries
/// the exception's text, the call answers OK with no response, and the row stays sent.
Method TestNeverThrows()
{
	Set run = ..NewRun()
	Set itemId = ..Open(run, "throws", "source-throws")
	Set decision = ..Decision(itemId, "decide", {"Outcome": "digest"})
	Do ..Usage(decision, 0.0001, 100)
	Set ^OcuTalonTest("EvalSink", "throw") = "the size read broke"
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..DeliverTo(..#DOUBLE, ..Message(itemId, "source-throws", decision, "digest"))
	Kill ^OcuTalonTest("EvalSink")
	Set row = ..RowOf(run, "throws")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State_"|"_row.DecisionRef_"|"_row.Outcome, "sent||", "the row is left as it was")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND SourceMethod = ? AND Text %STARTSWITH ? AND Text [ ?", mark, "OnMessage", ##class(OcuTalon.Eval.Sink).#LOGFAILED, "the size read broke")
	Do result.%Next()
	Do $$$AssertEquals(+result.%GetData(1), 1, "one error carries the exception's text")
	Kill ^OcuTalonTest("EvalSink", "throw")
	Do ..DeliverTo(..#DOUBLE, ..Message(itemId, "source-throws", decision, "digest"))
	Set row = ..RowOf(run, "throws")
	If $IsObject(row) Do $$$AssertEquals(row.State_"|"_row.DecisionRef_"|"_+row.LargestRequestTokens, "decided|"_decision_"|100", "the double is EvalSink itself when it does not throw")
}

/// --- helpers ---
/// A new run Ref that starts with zz, kept for the clean-up.
Method NewRun() As %String [ Private ]
{
	Set run = ..#RUNPREFIX_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 20)
	Set ..Runs = ..Runs_$Select(..Runs = "": "", 1: ",")_run
	Quit run
}

/// Opens the row of a case of the run as EvalIn does, with a new ItemId, and returns the ItemId.
Method Open(run As %String, name As %String, sourceItemId As %String) As %String [ Private ]
{
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Open(run, ..#CASEPREFIX_name, sourceItemId, itemId), name_": the row is opened")
	Quit itemId
}

/// A Decision row of the owner eval for the item, kept for the clean-up; fields (property names and values) are set after the defaults.
/// Returns its Ref.
Method Decision(itemId As %String, kind As %String, fields As %DynamicObject) As %String [ Private ]
{
	Do fields.%Set("ItemId", itemId)
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Decision("eval", kind, , fields)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A Usage row of the owner eval for the decision, with a cost (empty for an unpriced row) and a largest request.
Method Usage(decisionRef As %String, cost As %String, largest As %Integer) As %String [ Private ]
{
	Set fields = {"LargestRequestTokens": (largest)}
	If cost '= "" Do fields.%Set("CostUSD", cost)
	Quit ##class(OcuTalon.Test.Data.Fixture).Usage(decisionRef, "eval", fields)
}

/// An ItemDecision of the owner eval.
Method Message(itemId As %String, sourceItemId As %String, decisionRef As %String, outcome As %String) As OcuTalon.Msg.ItemDecision [ Private ]
{
	Set message = ##class(OcuTalon.Msg.ItemDecision).%New()
	Set message.ItemId = itemId
	Set message.SourceItemId = sourceItemId
	Set message.OwnerRef = "eval"
	Set message.Channel = "mailbox"
	Set message.DecisionRef = decisionRef
	Set message.Outcome = outcome
	Quit message
}

/// Hands the message to EvalSink's OnMessage on a shadow instance: it answers OK with no response.
Method Deliver(message As %Library.Persistent) [ Private ]
{
	Do ..DeliverTo(..#SINK, message)
}

/// Hands the message to OnMessage on a shadow instance of the class (EvalSink or its double): it answers OK with no response.
Method DeliverTo(class As %String, message As %Library.Persistent) [ Private ]
{
	Set sink = ##class(Ens.Host).GetShadowInstance("class||"_class, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of "_class_" is made")
	If '$IsObject(sink) Quit
	Kill response
	Do $$$AssertStatusOK(sink.OnMessage(message, .response), "OnMessage answers OK")
	Do $$$AssertEquals($Get(response), "", "and gives no response")
}

/// The row of the case of the run, opened afresh, or "" with a failed assertion.
Method RowOf(run As %String, name As %String) As OcuTalon.Eval.Data.CaseResult [ Private ]
{
	Set row = ##class(OcuTalon.Eval.Data.CaseResult).RunCaseIndexOpen(run, ..#CASEPREFIX_name)
	Do $$$AssertTrue($IsObject(row), name_": the row exists")
	Quit row
}

/// The number of case rows.
ClassMethod CountRows() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Eval_Data.CaseResult")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of errors that the method of EvalSink logged after the row mark, with a text that starts as given.
ClassMethod Errors(mark As %Integer, method As %String, start As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND SourceMethod = ? AND Text %STARTSWITH ?", mark, method, start)
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
