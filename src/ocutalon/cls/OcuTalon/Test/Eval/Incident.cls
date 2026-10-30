/// Tests of the evaluation incident (Story 9.6; AD-22, AD-30, AD-6). WARM-SAFE: no production runs. A shadow instance of OcuTalon.Test.Eval.ZzIncident (the
/// probe of IncidentManager with the two sends of the evaluation branch recorded) is handed OcuTalon.Eval.Msg.IncidentCase messages that carry the demo
/// incident's recorded snapshot (/opt/ocutalon/eval/orders-date-format/snapshot.json) or a bad one, and the answers of Decide are made by the test. The read
/// tests begin a bridge context from a request, save IncidentCase bodies whose SourceItemId starts with zz-incident-, and call the tool methods of
/// OcuTalon.Tools.WatchReads in this process. Every test asserts that none of the sends the branch must never make was recorded (the probe's Sent, DryRuns,
/// Raised, Executed, Started, Alarms and Cancelled) and that the number of Incident, FailureGroup, ApprovalRequest, FixRun and Live.Event rows is unchanged.
///   - TestRequest: the request to Decide has kind diagnose, provenance untrusted, the case's Ref as ItemId, owner eval, the SuperSession as TraceRef, the
///     session as ThreadSessionId, the code-written Summary, and as Input the EvidencePack.Input of the pack that Build gives the snapshot; nothing goes
///     to EvalSink yet;
///   - TestUsableAnswers: a usable answer with a fix, and one with no fix (empty fixKind), each give EvalSink exactly one ItemDecision, with the Ref as
///     ItemId, the case's name as SourceItemId, owner eval, no Channel and the answer's DecisionRef and Outcome;
///   - TestFallbackAnswer: an answer with Fallback 1 gives an ItemDecision with Fallback 1, its reason and its DecisionRef, and no warning;
///   - TestRefused, TestBadSnapshot, TestSendFails, TestNotDecisionResponse: each ends the case as a fallback ItemDecision (error, tellnow, no DecisionRef)
///     with one Type 3 warning, and the handler answers OK;
///   - TestEmptyRef: an IncidentCase with no Ref is an error that names IncidentRef, and nothing is sent; TestEvalSendFails: a failed send to EvalSink logs
///     one Type 3 warning;
///   - TestToolsEval: in the context of owner eval and the Ref of a saved IncidentCase, the three read tools give what EvidencePack gives for its snapshot
///     (the count of the failures and at most five of them, at most twenty log rows, the item and its settings) and the settings hold no credential;
///   - TestToolsNotEval: another owner, an unknown ItemId, no ItemId, no context, a snapshot of another format and a body that is not JSON each give
///     {"items":[]};
///   - TestToolsOwnerGuard: with an IncidentCase of the call's ItemId saved, a session's Ref as a chat turn sets it, the same Ref and the owner instance in
///     the context of a tool call, and the owners Eval, EVAL, eval with a space on either side and an empty owner each give {"items":[]}, never the snapshot,
///     while owner eval gets it;
///   - TestToolsLiveWins: for owner eval, with a live incident (its own throwaway row) in scope and an IncidentCase of the same ItemId saved, the three tools
///     give the answers of EvidencePack for the live incident and not those for the snapshot;
///   - TestToolsWriteNothing: around eval-branch calls of the three tools, the rows of the message, session and watch tables and the contents of the
///     ^OcuTalon* globals (all but the test scratch ^OcuTalonTest and the bridge's caches ^OcuTalonBP*), are as they were.
Class OcuTalon.Test.Eval.Incident Extends %UnitTest.TestCase
{

/// The recorded snapshot of the demo incident in a throwaway stack.
Parameter SNAPSHOT = "/opt/ocutalon/eval/orders-date-format/snapshot.json";

/// The start of the SourceItemId of the IncidentCase bodies of these tests.
Parameter PREFIX = "zz-incident-";

/// The tool class.
Parameter TOOLS = "OcuTalon.Tools.WatchReads";

/// The number of the newest row of the event log when the test began.
Property LogMark As %Integer;

/// The Refs of the fixture rows that a test made.
Property Refs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ..Sweep()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Sweep()
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Refs = ""
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "EvalRefused", $Parameter("OcuTalon.Watch.IncidentManager", "LOGEVAL"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "EvalDeliver", $Parameter("OcuTalon.Watch.IncidentManager", "LOGEVAL"))
	Do ..Sweep()
	Quit $$$OK
}

/// The request to Decide is the one the live path sends, for owner eval.
Method TestRequest()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set text = ..Text()
	If text = "" Quit
	Set case = ..Case(text)
	Set counts = ..Counts()
	Do $$$AssertStatusOK(host.CaseRequest(case, .response), "an IncidentCase is taken")
	Do $$$AssertEquals(response, "", "and gives no response")
	Do $$$AssertEquals(..Size(host.Asked), 1, "one request is sent to Decide")
	Do $$$AssertEquals(..Size(host.Delivered), 0, "and none to EvalSink before the answer")
	If ..Size(host.Asked) = 1 {
		Set asked = host.Asked.%Get(0)
		Do $$$AssertStatusOK(##class(OcuTalon.Watch.EvidencePack).Build({}.%FromJSON(text), .pack), "the pack of the snapshot is built")
		Do $$$AssertEquals(asked.kind_"|"_asked.provenance_"|"_asked.itemId_"|"_asked.ownerRef, "diagnose|untrusted|"_case.IncidentRef_"|eval", "kind diagnose, provenance untrusted, the case's Ref as ItemId, owner eval")
		Do $$$AssertEquals(asked.traceRef_"|"_asked.threadSessionId, host.%SuperSession_"|7", "the SuperSession as TraceRef and the session as ThreadSessionId")
		Do $$$AssertEquals(asked.summary, "50 failures at OrdersFromPartner", "the Summary is the code-written count and item")
		Do $$$AssertEquals(asked.input, ##class(OcuTalon.Watch.EvidencePack).Input(pack), "the Input is EvidencePack.Input of the pack that Build gives the snapshot")
		Do $$$AssertTrue(asked.input '= text, "and not the raw snapshot text")
	}
	Do ..AssertNothingElse(host, counts)
}

/// A usable answer, with a fix and with none, gives one ItemDecision and nothing else.
Method TestUsableAnswers()
{
	Set text = ..Text()
	If text = "" Quit
	For kind = "fix", "nofix" {
		Set host = ..Host()
		If '$IsObject(host) Quit
		Set case = ..Case(text)
		Set counts = ..Counts()
		Do host.CaseRequest(case)
		Set answer = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
		Set answer.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set answer.Outcome = "act"
		Set answer.Fallback = 0
		Set payload = {"outcome": "act", "causeCategory": "data_format_change", "elementAtFault": "OrderDate", "cause": "the date format changed"}
		If kind = "fix" {
			Do payload.%Set("fixKind", "repair_resend")
			Do payload.%Set("fixParameters", {"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"})
		} Else {
			Do payload.%Set("fixKind", "")
		}
		Set answer.Payload = payload.%ToJSON()
		Do $$$AssertStatusOK(host.CaseAnswer(case, answer), kind_": the answer is taken")
		Do $$$AssertEquals(..Size(host.Delivered), 1, kind_": exactly one ItemDecision goes to EvalSink")
		If ..Size(host.Delivered) = 1 {
			Set sent = host.Delivered.%Get(0)
			Do $$$AssertEquals(sent.itemId_"|"_sent.sourceItemId_"|"_sent.ownerRef_"|"_sent.channel, case.IncidentRef_"|orders-date-format|eval|", kind_": the Ref as ItemId, the case's name, owner eval and no Channel")
			Do $$$AssertEquals(sent.decisionRef_"|"_sent.outcome_"|"_sent.fallback_"|"_sent.fallbackReason, answer.DecisionRef_"|act|0|", kind_": the DecisionRef, the outcome and no fallback")
			Do $$$AssertEquals(sent.summary, "50 failures at OrdersFromPartner", kind_": the Summary of the request")
		}
		Do ..AssertNothingElse(host, counts)
	}
}

/// A fallback answer of Decide is passed on as it is.
Method TestFallbackAnswer()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set text = ..Text()
	If text = "" Quit
	Set case = ..Case(text)
	Set counts = ..Counts()
	Do host.CaseRequest(case)
	Set answer = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
	Set answer.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set answer.Outcome = "tellnow"
	Set answer.Fallback = 1
	Set answer.FallbackReason = "timeout"
	Do $$$AssertStatusOK(host.CaseAnswer(case, answer), "the answer is taken")
	Do $$$AssertEquals(..Size(host.Delivered), 1, "one ItemDecision goes to EvalSink")
	If ..Size(host.Delivered) = 1 {
		Set sent = host.Delivered.%Get(0)
		Do $$$AssertEquals(sent.decisionRef_"|"_sent.outcome_"|"_sent.fallback_"|"_sent.fallbackReason, answer.DecisionRef_"|tellnow|1|timeout", "with Fallback 1, its reason, its outcome and its DecisionRef")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .warning, "EvalRefused", $Parameter("OcuTalon.Watch.IncidentManager", "LOGEVAL")), 0, "and no warning is logged")
	Do ..AssertNothingElse(host, counts)
}

/// Decide refuses the request.
Method TestRefused()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set text = ..Text()
	If text = "" Quit
	Set case = ..Case(text)
	Set counts = ..Counts()
	Do host.CaseRequest(case)
	Do $$$AssertStatusOK(host.CaseRefuse(case, $SYSTEM.Status.Error(5001, "The request is refused: no runner")), "the error answer is taken, so the framework logs nothing more")
	Do ..AssertFallback(host, case, "no runner")
	Do ..AssertNothingElse(host, counts)
}

/// A snapshot that does not give a pack never reaches Decide.
Method TestBadSnapshot()
{
	Set text = ..Text()
	If text = "" Quit
	Set empty = {}.%FromJSON(text)
	Set empty.failures = []
	Set texts = $ListBuild("this is not json", "[]", "{""format"": ""zz.other/1"", ""failures"": []}", empty.%ToJSON(), "")
	Set position = 0
	While $ListNext(texts, position, bad) {
		Set host = ..Host()
		If '$IsObject(host) Quit
		Set case = ..Case(bad)
		Set counts = ..Counts()
		Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
		Do $$$AssertStatusOK(host.CaseRequest(case, .response), "'"_$Extract(bad, 1, 30)_"': the case is taken")
		Do $$$AssertEquals(..Size(host.Asked), 0, "nothing is sent to Decide")
		Do ..AssertFallback(host, case, "", mark)
		Do ..AssertNothingElse(host, counts)
	}
}

/// The send to Decide fails.
Method TestSendFails()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set text = ..Text()
	If text = "" Quit
	Set case = ..Case(text)
	Set counts = ..Counts()
	Set host.FailDiagnose = 1
	Do $$$AssertStatusOK(host.CaseRequest(case), "the case is taken")
	Do $$$AssertEquals(..Size(host.Asked), 1, "the send was tried once")
	Do ..AssertFallback(host, case, "send to Decide is refused")
	Do ..AssertNothingElse(host, counts)
}

/// Decide answers with something that is not a DecisionResponse.
Method TestNotDecisionResponse()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set text = ..Text()
	If text = "" Quit
	Set case = ..Case(text)
	Set counts = ..Counts()
	Do host.CaseRequest(case)
	Do $$$AssertStatusOK(host.CaseAnswer(case, ##class(Ens.StringResponse).%New("not a decision")), "the answer is taken")
	Do ..AssertFallback(host, case, "not a DecisionResponse")
	Do ..AssertNothingElse(host, counts)
	Set again = ..Host()
	Do again.CaseRequest(case)
	Do $$$AssertStatusOK(again.CaseAnswer(case, ""), "an empty answer is taken")
	Do $$$AssertEquals(..Size(again.Delivered), 1, "and it also ends the case as a fallback")
}

/// A case with no Ref is an error and sends nothing.
Method TestEmptyRef()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set text = ..Text()
	If text = "" Quit
	Set case = ..Case(text)
	Set case.IncidentRef = ""
	Set counts = ..Counts()
	Set sc = host.CaseRequest(case, .response)
	Do $$$AssertTrue($$$ISERR(sc), "the case is an error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "IncidentRef", "which names the missing Ref: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(response, "", "and gives no response")
	Do $$$AssertEquals(..Size(host.Asked)_"|"_..Size(host.Delivered), "0|0", "nothing is sent")
	Do ..AssertNothingElse(host, counts)
}

/// A send to EvalSink that fails logs one warning.
Method TestEvalSendFails()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set text = ..Text()
	If text = "" Quit
	Set case = ..Case(text)
	Set counts = ..Counts()
	Do host.CaseRequest(case)
	Set host.FailEval = 1
	Set answer = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
	Set answer.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set answer.Outcome = "act"
	Do $$$AssertStatusOK(host.CaseAnswer(case, answer), "the answer is taken")
	Do $$$AssertEquals(..Size(host.Delivered), 1, "the send was tried once")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .warning, "EvalDeliver", $Parameter("OcuTalon.Watch.IncidentManager", "LOGEVAL")_case.IncidentRef), 1, "and one Type 3 warning names the case")
	Do $$$AssertTrue(warning [ "refused", "with the error: "_warning)
	Do ..AssertNothingElse(host, counts)
}

/// The read tools answer from the snapshot of the case whose Ref is the ItemId, for owner eval.
Method TestToolsEval()
{
	Set text = ..Text()
	If text = "" Quit
	Set snapshot = {}.%FromJSON(text)
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Save(ref, text, "a")
	Do ..Begin("eval", ref)
	Set pack = "OcuTalon.Watch.EvidencePack"
	Set result = $ClassMethod(..#TOOLS, "ReadFailedMessages")
	Do $$$AssertEquals(result.%ToJSON(), $ClassMethod(pack, "FailedMessages", snapshot).%ToJSON(), "read_failed_messages gives what EvidencePack gives for the snapshot")
	Do $$$AssertEquals(result.count_"|"_result.items.%Size(), "50|5", "the count of the failures and at most five of them")
	If result.items.%Size() > 0 {
		Do $$$AssertEquals(result.items.%Get(0).headerId_"|"_result.items.%Get(0).item, snapshot.failures.%Get(0).headerId_"|OrdersFromPartner", "the first is the first recorded failure")
		Do $$$AssertEquals(result.items.%Get(0).body.OrderDate, snapshot.failures.%Get(0).body.OrderDate, "with its body")
	}
	Set result = $ClassMethod(..#TOOLS, "ReadEventLog")
	Do $$$AssertEquals(result.%ToJSON(), $ClassMethod(pack, "EventLog", snapshot).%ToJSON(), "read_event_log gives what EvidencePack gives for the snapshot")
	Do $$$AssertEquals(result.items.%Size(), $Parameter(pack, "MAXLOG"), "at most twenty rows")
	Set result = $ClassMethod(..#TOOLS, "ReadItemSettings")
	Do $$$AssertEquals(result.%ToJSON(), $ClassMethod(pack, "ItemSettings", snapshot).%ToJSON(), "read_item_settings gives what EvidencePack gives for the snapshot")
	Do $$$AssertEquals(result.item, "OrdersFromPartner", "the item of the first failure")

	Set newer = ..Newer(snapshot)
	Do ..Save(ref, newer.%ToJSON(), "b")
	Set result = $ClassMethod(..#TOOLS, "ReadItemSettings")
	Do $$$AssertTrue(result.settings.%ToJSON() '[ "zz-credential-value", "the newest case of the Ref is read, and no credential setting is in the answer: "_result.settings.%ToJSON())
	Do $$$AssertEquals(result.settings.%Get("ZzPlain"), "plain-value", "the newest case of the Ref is the one read, and a plain setting is kept")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Sweep()
	Do $$$AssertEquals(..Bodies(), 0, "the IncidentCase bodies of the test are deleted")
}

/// Every other state gives {"items": []}.
Method TestToolsNotEval()
{
	Set text = ..Text()
	If text = "" Quit
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Save(ref, text, "c")
	Do ..Begin("instance", ref)
	Do ..AssertEmpty("another owner")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Begin("Eval", ref)
	Do ..AssertEmpty("an owner that only looks like eval")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Begin("eval", ##class(OcuTalon.Bridge.Ids).NewRef())
	Do ..AssertEmpty("an ItemId with no IncidentCase")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Begin("eval", "")
	Do ..AssertEmpty("no ItemId")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..AssertEmpty("no context")
	Set other = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set wrong = {}.%FromJSON(text)
	Set wrong.format = "zz.other/1"
	Do ..Save(other, wrong.%ToJSON(), "d")
	Do ..Begin("eval", other)
	Do ..AssertEmpty("a snapshot of another format")
	Do ##class(OcuTalon.Bridge.Context).End()
	Set bad = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Save(bad, "this is not json", "e")
	Do ..Begin("eval", bad)
	Do ..AssertEmpty("a body that is not JSON")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(##class(OcuTalon.Watch.EvidencePack).EvalSnapshot(), "", "and EvalSnapshot itself gives no snapshot with no context")
	Do ..Begin("eval", ref)
	Do $$$AssertTrue($IsObject(##class(OcuTalon.Watch.EvidencePack).EvalSnapshot()), "while it gives the snapshot for owner eval and a saved case")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Sweep()
	Do $$$AssertEquals(..Bodies(), 0, "the IncidentCase bodies of the test are deleted")
}

/// With an IncidentCase of the call's ItemId saved, no owner but exactly eval reaches the recorded snapshot: a session's Ref as a chat turn sets it, the same
/// Ref and the owner instance in the context of a tool call, and owners that only look like eval each get {"items":[]}.
Method TestToolsOwnerGuard()
{
	Set text = ..Text()
	If text = "" Quit
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Save(ref, text, "g")
	Set session = "zz"_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 20)
	Set cases = $ListBuild($ListBuild("a session's Ref in a chat turn", "turn", "user", session))
	Set cases = cases_$ListBuild($ListBuild("a session's Ref in a tool call", "tool", "untrusted", session))
	Set cases = cases_$ListBuild($ListBuild("the owner instance in a chat turn", "turn", "user", "instance"))
	Set cases = cases_$ListBuild($ListBuild("the owner instance in a tool call", "tool", "untrusted", "instance"))
	Set cases = cases_$ListBuild($ListBuild("the owner Eval", "diagnose", "untrusted", "Eval"))
	Set cases = cases_$ListBuild($ListBuild("the owner EVAL", "diagnose", "untrusted", "EVAL"))
	Set cases = cases_$ListBuild($ListBuild("the owner eval and a space", "diagnose", "untrusted", "eval "))
	Set cases = cases_$ListBuild($ListBuild("the owner a space and eval", "diagnose", "untrusted", " eval"))
	Set cases = cases_$ListBuild($ListBuild("the owner evaluation", "diagnose", "untrusted", "evaluation"))
	Set cases = cases_$ListBuild($ListBuild("an empty owner", "diagnose", "untrusted", ""))
	Set position = 0
	While $ListNext(cases, position, case) {
		Do ##class(OcuTalon.Bridge.Context).End()
		Do ..Begin($List(case, 4), ref, $List(case, 2), $List(case, 3))
		Do $$$AssertEquals(##class(OcuTalon.Watch.EvidencePack).EvalSnapshot(), "", $List(case, 1)_": EvalSnapshot gives no snapshot")
		Do ..AssertEmpty($List(case, 1))
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Begin("eval", ref, "diagnose", "untrusted")
	Do $$$AssertTrue($IsObject(##class(OcuTalon.Watch.EvidencePack).EvalSnapshot()), "while owner eval, with the same case saved, gets the snapshot")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Sweep()
	Do $$$AssertEquals(..Bodies(), 0, "the IncidentCase bodies of the test are deleted")
}

/// With a live incident in scope, owner eval gets the live answers, though an IncidentCase of the same ItemId is saved.
Method TestToolsLiveWins()
{
	Set text = ..Text()
	If text = "" Quit
	Set snapshot = {}.%FromJSON(text)
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident("eval")
	Set ..Refs = ref
	Do ..Save(ref, text, "l")
	Set live = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(live), "a live incident of owner eval is saved")
	If '$IsObject(live) Quit
	Do ..Begin("eval", ref)
	Do $$$AssertTrue($IsObject(##class(OcuTalon.Watch.EvidencePack).Scope()), "EvidencePack.Scope finds it")
	Set pack = "OcuTalon.Watch.EvidencePack"
	For tool = "ReadFailedMessages:FailedMessages", "ReadEventLog:EventLog", "ReadItemSettings:ItemSettings" {
		Set answer = $ClassMethod(..#TOOLS, $Piece(tool, ":", 1))
		Set liveAnswer = $ClassMethod(pack, $Piece(tool, ":", 2), live)
		Set recorded = $ClassMethod(pack, $Piece(tool, ":", 2), snapshot)
		Do $$$AssertEquals(answer.%ToJSON(), liveAnswer.%ToJSON(), $Piece(tool, ":", 1)_" answers the live incident's answer")
		Do $$$AssertTrue(answer.%ToJSON() '= recorded.%ToJSON(), $Piece(tool, ":", 1)_" does not answer the recorded snapshot's: "_answer.%ToJSON())
	}
	Set answer = $ClassMethod(..#TOOLS, "ReadFailedMessages")
	Do $$$AssertEquals(answer.count, live.NoticeCount, "the count is the incident's, not the snapshot's "_snapshot.failures.%Size())
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Sweep()
}

/// The eval branch of the three tools writes nothing: no row in the tables and no change in the globals that the branch could touch.
Method TestToolsWriteNothing()
{
	Set text = ..Text()
	If text = "" Quit
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Save(ref, text, "w")
	Do ..Begin("eval", ref)
	Set before = ..Footprint()
	Do $$$AssertTrue(($Length(..Globals(), ",") > 1) && (before '[ "[error") && (before '[ "[none]"), "the footprint reads every table and some ^OcuTalon* globals: "_before)
	Set taken = 0
	For tool = "ReadFailedMessages", "ReadEventLog", "ReadItemSettings" {
		Set answer = $ClassMethod(..#TOOLS, tool)
		If answer.%ToJSON() '= "{""items"":[]}" Set taken = taken + 1
	}
	Set after = ..Footprint()
	Do $$$AssertEquals(taken, 3, "all three tools took the eval branch")
	Do $$$AssertEquals(after, before, "and no row and no node of any ^OcuTalon* global changed")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Sweep()
}

/// --- helpers ---
/// A shadow instance of the double, in this process, with a SuperSession and a session of its own.
Method Host() As OcuTalon.Test.Eval.ZzIncident
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Eval.ZzIncident", .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the double is made")
	If $IsObject(host) {
		Set host.%SessionId = 7
		Set host.%SuperSession = ##class(OcuTalon.Bridge.Ids).NewRef()
	}
	Quit host
}

/// The text of the demo incident's recorded snapshot, or "" with the failure reported.
Method Text() As %String
{
	Set sc = ##class(OcuTalon.Watch.EvidencePack).Load(..#SNAPSHOT, .snapshot)
	Do $$$AssertStatusOK(sc, "the recorded snapshot of the demo incident is read")
	Quit $Select($$$ISOK(sc): snapshot.%ToJSON(), 1: "")
}

/// An IncidentCase of the snapshot text, not saved: a fresh Ref and the demo incident's name.
Method Case(text As %String) As OcuTalon.Eval.Msg.IncidentCase
{
	Set case = ##class(OcuTalon.Eval.Msg.IncidentCase).%New()
	Set case.IncidentRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set case.SourceItemId = "orders-date-format"
	Set case.Snapshot = text
	Quit case
}

/// The ItemDecision of the case ended as a fallback: error, tellnow, no DecisionRef, and one Type 3 warning that names the case (and holds the text, if given).
Method AssertFallback(host As OcuTalon.Test.Eval.ZzIncident, case As OcuTalon.Eval.Msg.IncidentCase, text As %String, mark As %Integer = {..LogMark})
{
	Do $$$AssertEquals(..Size(host.Delivered), 1, "one ItemDecision goes to EvalSink")
	If ..Size(host.Delivered) = 1 {
		Set sent = host.Delivered.%Get(0)
		Do $$$AssertEquals(sent.itemId_"|"_sent.sourceItemId_"|"_sent.ownerRef_"|"_sent.channel, case.IncidentRef_"|orders-date-format|eval|", "with the Ref as ItemId, the case's name, owner eval and no Channel")
		Do $$$AssertEquals(sent.decisionRef_"|"_sent.outcome_"|"_sent.fallback_"|"_sent.fallbackReason, "|tellnow|1|error", "a fallback of reason error, outcome tellnow and no DecisionRef")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .warning, "EvalRefused", $Parameter("OcuTalon.Watch.IncidentManager", "LOGEVAL")_case.IncidentRef), 1, "and one Type 3 warning names the case")
	If text '= "" Do $$$AssertTrue(warning [ text, "holding the error: "_warning)
}

/// Asserts that no send the branch must never make was recorded, and that the rows of the live path are as they were.
Method AssertNothingElse(host As OcuTalon.Test.Eval.ZzIncident, counts As %String)
{
	Set sends = ""
	For name = "Sent", "DryRuns", "Raised", "Executed", "Started", "Alarms", "Cancelled" {
		If ..Size($Property(host, name)) Set sends = sends_" "_name
	}
	Do $$$AssertEquals(sends, "", "no notice, dry run, request, order, waiter, alarm or cancel was recorded")
	Do $$$AssertEquals(..Counts(), counts, "and the Incident, FailureGroup, ApprovalRequest, FixRun and Live.Event rows are as they were")
}

/// The number of elements of a dynamic array, 0 for what is not one (a probe property nothing was recorded in).
ClassMethod Size(array) As %Integer [ Private ]
{
	Quit $Select($IsObject(array): array.%Size(), 1: 0)
}

/// The numbers of rows of the tables that the live path writes, separated with a bar.
ClassMethod Counts() As %String [ Private ]
{
	Set counts = ""
	For table = "OcuTalon_Data.Incident", "OcuTalon_Data.FailureGroup", "OcuTalon_Bridge_Data.ApprovalRequest", "OcuTalon_Data.FixRun", "OcuTalon_Live.Event" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_table)
		Do result.%Next()
		Set counts = counts_$Select(counts = "": "", 1: "|")_+result.%GetData(1)
	}
	Quit counts
}

/// Begins the bridge context of a request of the kind and provenance (a diagnose request by default) for the owner and ItemId.
Method Begin(owner As %String, itemId As %String, kind As %String = "diagnose", provenance As %String = "untrusted") [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = provenance
	Set request.ItemId = itemId
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = owner
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, ""), "a context begins for the diagnosis of '"_owner_"'")
}

/// Saves an IncidentCase body of the Ref with the snapshot text; the tag keeps the SourceItemIds of one test apart.
Method Save(ref As %String, text As %String, tag As %String) [ Private ]
{
	Set body = ##class(OcuTalon.Eval.Msg.IncidentCase).%New()
	Set body.IncidentRef = ref
	Set body.SourceItemId = ..#PREFIX_tag
	Set body.Snapshot = text
	Do $$$AssertStatusOK(body.%Save(), "an IncidentCase is saved for the Ref '"_ref_"'")
}

/// A copy of the snapshot whose item has a credential setting and a plain one.
ClassMethod Newer(snapshot As %DynamicObject) As %DynamicObject [ Private ]
{
	Set copy = {}.%FromJSON(snapshot.%ToJSON())
	Set iterator = copy.items.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.name '= "OrdersFromPartner" Continue
		Do entry.settings.%Set("Credentials", "zz-credential-value")
		Do entry.settings.%Set("ZzPlain", "plain-value")
	}
	Quit copy
}

/// Asserts that the three tools give {"items":[]}.
Method AssertEmpty(label As %String) [ Private ]
{
	For tool = "ReadFailedMessages", "ReadEventLog", "ReadItemSettings" {
		Set result = $ClassMethod(..#TOOLS, tool)
		Do $$$AssertEquals($Select($IsObject(result): result.%ToJSON(), 1: result), "{""items"":[]}", label_": "_tool_" gives {""items"":[]}")
	}
}

/// What the eval branch must leave alone, as one text: the numbers of rows of the message, session and watch tables (the message tables only for the
/// product's own classes, so that the engine's traffic does not count), and the count and checksum of the nodes of every ^OcuTalon* global except the test
/// scratch ^OcuTalonTest and the bridge's caches ^OcuTalonBP.*, which the running production's Decide job writes.
ClassMethod Footprint() As %String [ Private ]
{
	Set out = ""
	Set queries = $ListBuild("SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName %STARTSWITH 'OcuTalon.'", "SELECT COUNT(*) FROM Ens.MessageBody WHERE %CLASSNAME %STARTSWITH 'OcuTalon.'")
	Set tables = $ListBuild("OcuTalon_Eval_Msg.IncidentCase", "OcuTalon_Data.Session", "OcuTalon_Data.Turn", "OcuTalon_Live.Event", "OcuTalon_Data.Incident", "OcuTalon_Data.FailureGroup", "OcuTalon_Data.BackgroundCheck")
	Set position = 0
	While $ListNext(tables, position, table) {
		Set queries = queries_$ListBuild("SELECT COUNT(*) FROM "_table)
	}
	Set position = 0
	While $ListNext(queries, position, query) {
		Set result = ##class(%SQL.Statement).%ExecDirect(, query)
		Set out = out_$Select(result.%SQLCODE < 0: "[error "_result.%SQLCODE_"]", result.%Next(): +result.%GetData(1), 1: "[none]")_"|"
	}
	Set names = ..Globals()
	For i = 1:1:$Length(names, ",") - 1 {
		Set name = $Piece(names, ",", i)
		Set out = out_name_"="_..Nodes("^"_name)_"|"
	}
	Quit out
}

/// The names of the ^OcuTalon* globals that hold data in this namespace (mappings included), without the caret and without OcuTalonTest and OcuTalonBP*, each
/// followed by a comma.
ClassMethod Globals() As %String [ Private ]
{
	Set names = ""
	Set statement = ##class(%SQL.Statement).%New()
	If $$$ISERR(statement.%PrepareClassQuery("%SYS.GlobalQuery", "NameSpaceList")) Quit names
	Set result = statement.%Execute($Namespace, "OcuTalon*", 0)
	While result.%Next() {
		Set name = result.%GetData(1)
		If (name '= "OcuTalonTest") && ($Extract(name, 1, 10) '= "OcuTalonBP") Set names = names_name_","
	}
	Quit names
}

/// The count of the nodes with data of the global and a checksum of their subscripts and values, as count:checksum.
ClassMethod Nodes(root As %String) As %String [ Private ]
{
	Set count = 0
	Set sum = 0
	If $Data(@root) # 2 {
		Set count = 1
		Set sum = $ZCRC(root_$Char(0)_@root, 7)
	}
	Set prefix = root_"("
	Set node = root
	For {
		Set node = $Query(@node)
		If (node = "") || ($Extract(node, 1, $Length(prefix)) '= prefix) Quit
		Set count = count + 1
		Set sum = sum + $ZCRC(node_$Char(0)_$Get(@node), 7)
	}
	Quit count_":"_sum
}

/// The number of IncidentCase bodies of these tests.
ClassMethod Bodies() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Eval_Msg.IncidentCase WHERE SourceItemId %STARTSWITH ?", ..#PREFIX)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// Deletes the IncidentCase bodies of these tests.
ClassMethod Sweep() [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Eval_Msg.IncidentCase WHERE SourceItemId %STARTSWITH ?", ..#PREFIX)
	Set ids = ""
	While result.%Next() {
		Set ids = ids_$ListBuild(result.%Get("ID"))
	}
	Set position = 0
	While $ListNext(ids, position, id) {
		Do ##class(OcuTalon.Eval.Msg.IncidentCase).%DeleteId(id)
	}
}

}
