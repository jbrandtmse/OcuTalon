/// Tests of Decide that need no production and no mock (Story 1.3; AD-6, AD-7, AD-20, AD-31): the pure and the in-process rows of
/// the I/O matrix. They drive the class methods that the business process itself calls, in particular Conclude, which OnResponse
/// calls, with the probe filter and the probe sink of this package. Nothing is sent. Every test removes the Decision rows it made
/// and kills the process-private globals ^||ZzProbeFilter and ^||ZzProbeSink.
///   - TestRefusedRequests: Admit gives "not implemented" (5003) for a foreign message class and for kind tool, and an error that
///     names the field for a kind, provenance, ItemId, OwnerRef or Input that is missing or unknown;
///   - TestBadSettings: CheckSettings names TimerSeconds (0, 111, x), ReplyFilterClass (missing, not an extension class) and
///     ReplyClass (missing, not a JSON class; DiagnosisAgent has none);
///   - TestReplyCheck: a JSON object, also inside one code fence, passes; an outcome that is not one of OUTCOME, no reason, a blank
///     reason, no confidence, a confidence over 1, an extra field, text that is not JSON, an array and an empty text fail; and
///     Conclude records nothing for a reply that fails;
///   - TestFilter: the filter runs once on each model-written text (each reason; a turn's text) and not on the code-written line;
///   - TestFilterBlanks: a decision with no reason left once filtered, and a turn with no text left, are refused with no row and no
///     event; a reason that the filter blanks while another stays is dropped from the row;
///   - TestSink: decision.recorded is fired after the commit with the owner and exactly {"ref":<Ref>}; an error, an exception and a
///     sink class that is no extension (also one that has an OnEvent) are logged as a warning and sent no event, and the decision
///     stands;
///   - TestConcurrentSave: a row that another call saved first answers, with no second row and no event, and a turn refuses;
///   - TestRecord: a save refused by the unique index on (ItemId, Kind) answers from the row that won, and a turn row refuses;
///   - TestUserRule: a user's ignore and digest become tellnow with the code-written line first; a user's act and tellnow and every
///     untrusted outcome stay;
///   - TestConfidence: 0.12 stays 0.12 and 0.123 is recorded as 0.12, and the confidence never changes the outcome;
///   - TestResponseFromRow: the answer for a recorded decide row, and the refusal for a turn row;
///   - TestOnResponseUsesItsSettings and TestOnRequestUsesItsSettings: the business process hands its own ReplyFilterClass,
///     HostSinkClass, TimerSeconds and session to the class methods, on a Decide instance of the test with no production started;
///   - TestRecordedAtIsUtc: RecordedAt is a UTC time whatever the zone of the process.
Class OcuTalon.Test.Bridge.Decide Extends %UnitTest.TestCase
{

/// A usable reply of Triage's default script.
Parameter DIGEST = "{""outcome"":""digest"",""reasons"":[""The CI mock keeps this item for the digest.""],""confidence"":0.5}";

Parameter FILTER = "OcuTalon.Test.Bridge.ProbeFilter";

Parameter SINK = "OcuTalon.Test.Bridge.ProbeSink";

Parameter REPLYCLASS = "OcuTalon.Bridge.Msg.DecisionPayload";

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Kill ^||ZzProbeFilter, ^||ZzProbeSink
	Quit $$$OK
}

/// Admit: a message of another class and a request of kind tool give 5003; a kind, provenance, ItemId, OwnerRef or Input that is
/// missing or unknown gives an error that names the field; a usable request is admitted.
Method TestRefusedRequests()
{
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Admit(##class(Ens.StringRequest).%New("x"))
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "a message of another class gets 5003")
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Admit("")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "so does no message at all")
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Admit(..NewRequest("tool"))
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "a request of kind tool gets 5003")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.Decide).Admit(..NewRequest("decide")), "a decide request is admitted")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.Decide).Admit(..NewRequest("turn", "user")), "and so is a user's turn")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.Decide).Admit(..NewRequest("diagnose")), "and a diagnose request")

	Set request = ..NewRequest("zz")
	Do ..AssertNamed(request, "Kind", "a kind outside REQUESTKIND")
	Set request = ..NewRequest("decide", "zz")
	Do ..AssertNamed(request, "Provenance", "a provenance outside PROVENANCE")
	Set request = ..NewRequest("decide")
	Set request.ItemId = ""
	Do ..AssertNamed(request, "ItemId", "an empty ItemId")
	Set request = ..NewRequest("decide")
	Set request.OwnerRef = ""
	Do ..AssertNamed(request, "OwnerRef", "an empty OwnerRef")
	Set request = ..NewRequest("decide")
	Set request.Input = " "_$Char(9, 10, 13)_" "
	Do ..AssertNamed(request, "Input", "an Input of white space only")
	Set request.Input = ""
	Do ..AssertNamed(request, "Input", "an empty Input")
}

/// CheckSettings names the setting: TimerSeconds outside 1 to 110 or not a whole number, a ReplyFilterClass that is missing or
/// does not extend its base, and a ReplyClass that is missing or is not a compiled JSON class. A turn needs no ReplyClass, and
/// DiagnosisAgent names none until Story 5.4.
Method TestBadSettings()
{
	Set filter = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set class = "OcuTalon.Bridge.Process.Decide"
	Do $$$AssertStatusOK($ClassMethod(class, "CheckSettings", "decide", "TriageAgent", ..#REPLYCLASS, filter, 60), "the default settings pass")
	Do $$$AssertStatusOK($ClassMethod(class, "CheckSettings", "decide", "TriageAgent", ..#REPLYCLASS, filter, 1), "a timer of 1 passes")
	Do $$$AssertStatusOK($ClassMethod(class, "CheckSettings", "decide", "TriageAgent", ..#REPLYCLASS, filter, 110), "and so does a timer of 110")
	Do $$$AssertStatusOK($ClassMethod(class, "CheckSettings", "turn", "ChatAgent", "", filter, 60), "a turn needs no ReplyClass")
	For timer = 0, 111, "x", "", "60.5", -1 {
		Set sc = $ClassMethod(class, "CheckSettings", "decide", "TriageAgent", ..#REPLYCLASS, filter, timer)
		Do $$$AssertStatusNotOK(sc, "a timer of '"_timer_"' is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "TimerSeconds", "and the error names TimerSeconds: "_$SYSTEM.Status.GetErrorText(sc))
	}
	For bad = "", "OcuTalon.Test.Bridge.ZzNoSuchFilter", "OcuTalon.Bridge.Ext.HostSink" {
		Set sc = $ClassMethod(class, "CheckSettings", "turn", "ChatAgent", "", bad, 60)
		Do $$$AssertStatusNotOK(sc, "a ReplyFilterClass of '"_bad_"' is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ReplyFilterClass", "and the error names ReplyFilterClass: "_$SYSTEM.Status.GetErrorText(sc))
	}
	For bad = "OcuTalon.Test.Bridge.ZzNoSuchReply", "OcuTalon.Bridge.Ext.ReplyFilter" {
		Set sc = $ClassMethod(class, "CheckSettings", "decide", "TriageAgent", bad, filter, 60)
		Do $$$AssertStatusNotOK(sc, "a ReplyClass of '"_bad_"' is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ReplyClass", "and the error names ReplyClass: "_$SYSTEM.Status.GetErrorText(sc))
	}
	Set sc = $ClassMethod(class, "CheckSettings", "diagnose", "DiagnosisAgent", "", filter, 60)
	Do $$$AssertStatusNotOK(sc, "a diagnose request is refused while DiagnosisAgent has no ReplyClass")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ "DiagnosisAgent") && (text [ "ReplyClass"), "and the error names DiagnosisAgent and ReplyClass: "_text)
	Do $$$AssertEquals($ClassMethod(class, "RunnerFor", "decide"), "TriageAgent", "decide goes to TriageAgent")
	Do $$$AssertEquals($ClassMethod(class, "RunnerFor", "diagnose"), "DiagnosisAgent", "diagnose goes to DiagnosisAgent")
	Do $$$AssertEquals($ClassMethod(class, "RunnerFor", "turn"), "ChatAgent", "and turn goes to ChatAgent")
}

/// CheckReply: one JSON object that DecisionPayload accepts passes, also inside one code fence; every other text fails with an
/// error that names the reply check. Conclude records nothing for a reply that fails.
Method TestReplyCheck()
{
	Set fence = $Char(96, 96, 96)
	Set good = ..#DIGEST
	Do ..AssertReply(good, 1, "valid JSON")
	Do ..AssertReply("  "_$Char(10)_good_$Char(13, 10), 1, "valid JSON in white space")
	Do ..AssertReply(fence_"json"_$Char(10)_good_$Char(10)_fence, 1, "valid JSON inside a json code fence")
	Do ..AssertReply(fence_$Char(13, 10)_good_$Char(13, 10)_fence, 1, "valid JSON inside a plain code fence")
	Do ..AssertReply("{""outcome"":""maybe"",""reasons"":[""r""],""confidence"":0.5}", 0, "an outcome that is not one of OUTCOME")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[],""confidence"":0.5}", 0, "no reason")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":["" "",""""],""confidence"":0.5}", 0, "only blank reasons")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[""r""]}", 0, "no confidence")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[""r""],""confidence"":1.5}", 0, "a confidence over 1")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[""r""],""confidence"":0.5,""extra"":1}", 0, "an extra field")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":""r"",""confidence"":0.5}", 0, "reasons that are a string")
	Do ..AssertReply("Not JSON at all.", 0, "text that is not JSON")
	Do ..AssertReply("[1,2]", 0, "a JSON array")
	Do ..AssertReply(good_" and more text", 0, "JSON followed by text")
	Do ..AssertReply(good_good, 0, "two objects")
	Do ..AssertReply("", 0, "an empty text")
	Do ..AssertReply("   ", 0, "a text of white space")
	Do ..AssertReply(fence_"json"_$Char(10)_good, 0, "a code fence that is not closed")

	Set request = ..NewRequest("decide")
	Set reply = ..NewReply("{""outcome"":""maybe"",""reasons"":[""r""],""confidence"":0.5}")
	Set sc = ..Conclude(request, reply, .response)
	Do $$$AssertStatusNotOK(sc, "Conclude refuses a reply that fails the check")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "reply check", "and the error names the reply check: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(response, "", "it gives no response")
	Do $$$AssertEquals(..Rows(request.ItemId), 0, "and records no row")
	Set sc = ..Conclude(..NewRequest("decide"), ..NewReply(good, "refusal"), .response)
	Do $$$AssertStatusNotOK(sc, "Conclude refuses a reply that the provider ended with a refusal")
	Set sc = ..Conclude(..NewRequest("decide"), ..NewReply(good, "max_tokens"), .response)
	Do $$$AssertStatusNotOK(sc, "and one that it cut off at the output cap")
	Set request = ..NewRequest("turn", "user")
	Set sc = ..Conclude(request, ..NewReply(" "_$Char(10)), .response)
	Do $$$AssertStatusNotOK(sc, "Conclude refuses an empty turn reply")
	Do $$$AssertEquals(..Rows(request.ItemId), 0, "and records no row for it")
}

/// The filter runs once on each model-written text: every reason of a decide reply, and a turn's text. It does not run on the
/// code-written line of the user rule. The row, the Payload and the response hold the filtered text.
Method TestFilter()
{
	Set json = "{""outcome"":""ignore"",""reasons"":[""First reason."",""Second reason.""],""confidence"":0.9}"
	Set request = ..NewRequest("decide")
	Set sc = ..Conclude(request, ..NewReply(json), .response, ..#FILTER)
	Do $$$AssertStatusOK(sc, "an untrusted decide reply is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeFilter), 2, "the filter ran once for each of the two reasons")
	Do $$$AssertEquals($Get(^||ZzProbeFilter(1)), "First reason.", "first on the first reason, as the model wrote it")
	Do $$$AssertEquals($Get(^||ZzProbeFilter(2)), "Second reason.", "then on the second")
	Set expected = "[f] First reason."_$Char(10)_"[f] Second reason."
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals(row.Reasons, expected, "the row holds the filtered reasons, one per line")
	Do $$$AssertEquals(response.Reasons, expected, "and so does the response")
	Do $$$AssertEquals(row.Payload, "{""outcome"":""ignore"",""reasons"":[""[f] First reason."",""[f] Second reason.""],""confidence"":0.9}", "and the Payload")
	Do $$$AssertEquals(response.Payload, row.Payload, "which the response repeats")

	Kill ^||ZzProbeFilter
	Set request = ..NewRequest("decide", "user")
	Set sc = ..Conclude(request, ..NewReply(json), .response, ..#FILTER)
	Do $$$AssertStatusOK(sc, "a user's decide reply is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeFilter), 2, "the filter ran for the two model reasons only, not for the code-written line")
	Do $$$AssertEquals(response.Outcome, "tellnow", "the outcome is tellnow")
	Do $$$AssertEquals(response.Reasons, ##class(OcuTalon.Bridge.Process.Decide).#USERANSWERED_$Char(10)_expected, "the code-written line comes first and is not filtered")

	Kill ^||ZzProbeFilter
	Set request = ..NewRequest("turn", "user")
	Set sc = ..Conclude(request, ..NewReply("Everything is fine."), .response, ..#FILTER)
	Do $$$AssertStatusOK(sc, "a turn reply is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeFilter), 1, "the filter ran once on the text of the turn")
	Do $$$AssertEquals($Get(^||ZzProbeFilter(1)), "Everything is fine.", "on the text as the model wrote it")
	Do $$$AssertEquals(response.Text, "[f] Everything is fine.", "and the answer holds the filtered text")
	Set row = ..RowOf(request.ItemId, "turn")
	Do $$$AssertEquals(row.Outcome, "tellnow", "the turn row is tellnow")
	Do $$$AssertEquals(row.Reasons_row.Confidence_row.Payload, "", "with no reasons, confidence or payload")
	Do $$$AssertEquals(response.DecisionRef, row.Ref, "and the answer carries its Ref")
	Do $$$AssertEquals(response.Outcome, "tellnow", "and the outcome tellnow")
}

/// decision.recorded: one call after the save with the request's OwnerRef and exactly {"ref":<Ref>}, outside any transaction and
/// with the row in place. An error status, an exception and a class that is no host sink are logged as a warning that names the
/// class and the Ref, and never fail Conclude; the row stands and the answer is given.
Method TestSink()
{
	Set request = ..NewRequest("decide")
	Set request.OwnerRef = "ZzOwner"
	Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response, , ..#SINK)
	Do $$$AssertStatusOK(sc, "the decision is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "the sink got one call")
	Set call = $Get(^||ZzProbeSink(1))
	Do $$$AssertEquals($List(call, 1), "decision.recorded", "of decision.recorded")
	Do $$$AssertEquals($List(call, 2), "ZzOwner", "with the OwnerRef of the request")
	Do $$$AssertEquals($List(call, 3), "{""ref"":"""_response.DecisionRef_"""}", "and exactly the Ref of the row as its payload")
	Do $$$AssertEquals($List(call, 4), 0, "outside any transaction")
	Do $$$AssertEquals($List(call, 5), 1, "with the row already saved")

	For mode = "error", "throw" {
		Kill ^||ZzProbeSink
		Set ^||ZzProbeSink("mode") = mode
		Set request = ..NewRequest("decide")
		Set mark = ..LogMark()
		Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response, , ..#SINK)
		Do $$$AssertStatusOK(sc, "in "_mode_" mode the decision is recorded and Conclude is OK")
		Do $$$AssertTrue($IsObject(response) && (response.DecisionRef '= ""), "the answer is given")
		Do $$$AssertEquals(..Rows(request.ItemId), 1, "and the row stands")
		Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "the sink was called once")
		Do ..AssertWarning(mark, ..#SINK, response.DecisionRef, mode)
	}
	For bad = "%Library.String", "OcuTalon.Test.Bridge.ZzNoSuchSink", "OcuTalon.Test.Bridge.ProbeNotASink" {
		Kill ^||ZzProbeSink
		Set request = ..NewRequest("decide")
		Set mark = ..LogMark()
		Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response, , bad)
		Do $$$AssertStatusOK(sc, "with the sink class "_bad_" the decision is recorded and Conclude is OK")
		Do $$$AssertEquals(..Rows(request.ItemId), 1, "and the row stands")
		Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "no event is sent")
		Do ..AssertWarning(mark, bad, response.DecisionRef, "bad class "_bad)
	}
}

/// A row that another call saved first for the item and kind answers, with no second row and no event. The row of a turn has no
/// reply text, so a second turn is refused with an error that names the item and the Ref.
Method TestConcurrentSave()
{
	Kill ^||ZzProbeSink
	Set request = ..NewRequest("decide")
	Set first = ##class(OcuTalon.Bridge.Data.Decision).%New()
	Set first.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set first.Kind = "decide"
	Set first.ItemId = request.ItemId
	Set first.OwnerRef = "instance"
	Set first.Outcome = "act"
	Set first.Reasons = "The first call won."
	Set first.Confidence = 0.31
	Set first.Payload = "{""outcome"":""act""}"
	Do $$$AssertStatusOK(first.%Save(), "another call saved its row first")
	Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response, , ..#SINK)
	Do $$$AssertStatusOK(sc, "Conclude answers")
	Do $$$AssertEquals(response.DecisionRef, first.Ref, "with the row that exists")
	Do $$$AssertEquals(response.Outcome_"|"_response.Reasons_"|"_response.Confidence, "act|The first call won.|.31", "and its outcome, reasons and confidence")
	Do $$$AssertEquals(..Rows(request.ItemId), 1, "no second row is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and no event is sent")

	Set request = ..NewRequest("turn", "user")
	Set row = ##class(OcuTalon.Bridge.Data.Decision).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Kind = "turn"
	Set row.ItemId = request.ItemId
	Set row.OwnerRef = "instance"
	Set row.Outcome = "tellnow"
	Do $$$AssertStatusOK(row.%Save(), "a turn row exists")
	Set sc = ..Conclude(request, ..NewReply("A second answer."), .response, , ..#SINK)
	Do $$$AssertStatusNotOK(sc, "a second turn is refused")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ request.ItemId) && (text [ row.Ref), "with an error that names the item and the Ref: "_text)
	Do $$$AssertEquals(response, "", "and gives no answer")
	Do $$$AssertEquals(..Rows(request.ItemId), 1, "no second row is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and no event is sent")
}

/// The user rule: for a decide request with provenance user, ignore and digest become tellnow, the first reason line is the code-
/// written sentence, and the Payload keeps the model's own outcome. A user's act and tellnow, and every outcome of an untrusted
/// item, stay as the model gave them. Row and answer agree.
Method TestUserRule()
{
	Set sentence = ##class(OcuTalon.Bridge.Process.Decide).#USERANSWERED
	Set reason = "The CI mock gives its reason."
	For provenance = "user", "untrusted" {
		For outcome = "ignore", "digest", "tellnow", "act" {
			Set request = ..NewRequest("decide", provenance)
			Set json = "{""outcome"":"""_outcome_""",""reasons"":["""_reason_"""],""confidence"":0.4}"
			Set sc = ..Conclude(request, ..NewReply(json), .response)
			Set label = provenance_" "_outcome
			Do $$$AssertStatusOK(sc, label_" is recorded")
			Set row = ..RowOf(request.ItemId, "decide")
			Set changed = (provenance = "user") && ((outcome = "ignore") || (outcome = "digest"))
			Set expectedOutcome = $Select(changed: "tellnow", 1: outcome)
			Set expectedReasons = $Select(changed: sentence_$Char(10), 1: "")_reason
			Do $$$AssertEquals(row.Outcome, expectedOutcome, label_": the row holds "_expectedOutcome)
			Do $$$AssertEquals(response.Outcome, expectedOutcome, label_": and so does the answer")
			Do $$$AssertEquals(row.Reasons, expectedReasons, label_": the reasons "_$Select(changed: "start with the code-written line", 1: "are the model's"))
			Do $$$AssertEquals(response.Reasons, expectedReasons, label_": in the answer too")
			Do $$$AssertTrue(row.Payload [ ("""outcome"":"""_outcome_""""), label_": the Payload keeps the model's own outcome")
			Do $$$AssertEquals(row.Confidence, .4, label_": the confidence is the model's")
		}
	}
	Set request = ..NewRequest("turn", "user")
	Do $$$AssertStatusOK(..Conclude(request, ..NewReply("A turn."), .response), "a user's turn is recorded")
	Do $$$AssertEquals(..RowOf(request.ItemId, "turn").Reasons, "", "and the user rule adds no line to its row")
}

/// The confidence is recorded rounded to two decimals, in the row and in the answer, and never changes the outcome: 0.12 stays
/// 0.12, 0.123 becomes 0.12, 0 and 1 stay, and a confidence of 0.12 still acts.
Method TestConfidence()
{
	For confidence = "0.12", "0.123", "0.125", "0", "1" {
		Set request = ..NewRequest("decide")
		Set json = "{""outcome"":""act"",""reasons"":[""r""],""confidence"":"_confidence_"}"
		Set sc = ..Conclude(request, ..NewReply(json), .response)
		Do $$$AssertStatusOK(sc, "a confidence of "_confidence_" is recorded")
		Set expected = $Number(confidence, 2)
		Set row = ..RowOf(request.ItemId, "decide")
		Do $$$AssertEquals(row.Confidence, expected, "the row holds "_expected)
		Do $$$AssertEquals(response.Confidence, expected, "and so does the answer")
		Do $$$AssertEquals(row.Outcome_"|"_response.Outcome, "act|act", "and the outcome stays act")
	}
	Set request = ..NewRequest("decide")
	Do $$$AssertStatusOK(..Conclude(request, ..NewReply("{""outcome"":""act"",""reasons"":[""r""],""confidence"":0.123}"), .response), "0.123 is recorded")
	Do $$$AssertTrue(..RowOf(request.ItemId, "decide").Payload [ "0.123", "the Payload keeps the confidence the model gave")
}

/// ResponseFromRow gives a DecisionResponse with the row's values for a decide row, and refuses a turn row.
Method TestResponseFromRow()
{
	Set request = ..NewRequest("decide")
	Set request.Summary = "A summary line."
	Do $$$AssertStatusOK(..Conclude(request, ..NewReply(..#DIGEST), .made), "a decide reply is recorded")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals(row.Kind_"|"_row.ItemId_"|"_row.OwnerRef_"|"_row.Summary, "decide|"_request.ItemId_"|instance|A summary line.", "the row holds the Kind, ItemId, OwnerRef and Summary of the request")
	Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason, "0|", "and no fallback")
	Do $$$AssertTrue(row.RecordedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "RecordedAt is a UTC time: "_row.RecordedAt)
	Do $$$AssertEquals(row.TraceSessionId, 4242, "TraceSessionId is the session that Conclude was given")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.Decide).ResponseFromRow(row, .response), "the answer for the row is built")
	Do $$$AssertTrue($IsObject(response) && response.%IsA("OcuTalon.Bridge.Msg.DecisionResponse"), "a DecisionResponse")
	Do $$$AssertEquals(response.DecisionRef_"|"_response.Outcome_"|"_response.Reasons_"|"_response.Confidence_"|"_response.Fallback_"|"_response.FallbackReason, row.Ref_"|digest|The CI mock keeps this item for the digest.|.5|0|", "with the values of the row")
	Do $$$AssertEquals(response.Payload, ..#DIGEST, "and its Payload")
	Do $$$AssertEquals(response.DecisionRef, made.DecisionRef, "the answer is the one that Conclude gave")
	Do $$$AssertEquals(response.Payload, made.Payload, "with the same Payload")
	Do $$$AssertEquals(row.Ref ? 22(1AN,1"-",1"_"), 1, "the Ref is 22 characters")

	Set request = ..NewRequest("turn", "user")
	Do $$$AssertStatusOK(..Conclude(request, ..NewReply("Hello."), .made), "a turn is recorded")
	Set row = ..RowOf(request.ItemId, "turn")
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).ResponseFromRow(row, .response)
	Do $$$AssertStatusNotOK(sc, "a turn row gives no answer")
	Do $$$AssertTrue(($SYSTEM.Status.GetErrorText(sc) [ request.ItemId) && ($SYSTEM.Status.GetErrorText(sc) [ row.Ref), "and an error that names the item and the Ref")
}

/// A decision with no reason left once the filter has run, and a turn with no text left, are not answers: Conclude refuses them,
/// records no row and sends no event, for a user's item too. A reason that the filter blanks while another stays is dropped from
/// the row.
Method TestFilterBlanks()
{
	Set json = "{""outcome"":""ignore"",""reasons"":[""Gone {blank}"",""Gone too {blank}""],""confidence"":0.9}"
	For provenance = "untrusted", "user" {
		Kill ^||ZzProbeSink
		Set request = ..NewRequest("decide", provenance)
		Set sc = ..Conclude(request, ..NewReply(json), .response, ..#FILTER, ..#SINK)
		Set label = "a "_provenance_" decide reply whose reasons the filter blanks"
		Do $$$AssertStatusNotOK(sc, label_" is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "no reason is left", "with an error that says so: "_$SYSTEM.Status.GetErrorText(sc))
		Do $$$AssertEquals(response, "", label_" gives no answer")
		Do $$$AssertEquals(..Rows(request.ItemId), 0, label_" records no row")
		Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, label_" sends no event")
	}
	Kill ^||ZzProbeSink
	Set request = ..NewRequest("turn", "user")
	Set sc = ..Conclude(request, ..NewReply("Gone {blank}"), .response, ..#FILTER, ..#SINK)
	Do $$$AssertStatusNotOK(sc, "a turn reply that the filter blanks is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "no text is left", "with an error that says so: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(response, "", "and gives no answer")
	Do $$$AssertEquals(..Rows(request.ItemId), 0, "and records no row")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and sends no event")

	Set request = ..NewRequest("decide")
	Set json = "{""outcome"":""ignore"",""reasons"":[""Kept."",""Gone {blank}""],""confidence"":0.9}"
	Set sc = ..Conclude(request, ..NewReply(json), .response, ..#FILTER)
	Do $$$AssertStatusOK(sc, "a reply with one reason that the filter keeps is recorded")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals(row.Reasons, "[f] Kept.", "and the row holds the reason that is left")
	Do $$$AssertEquals(response.Reasons, "[f] Kept.", "and so does the answer")
}

/// Record saves a row for a new item. A row for an item that another call recorded first is refused by the unique index on
/// (ItemId, Kind): nothing is saved, and the answer is the row that won; for a turn row it is the error that names the item and
/// the Ref.
Method TestRecord()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set request = ..NewRequest("decide")
	Set first = ..NewRow(request.ItemId, "decide", "act")
	Set first.Reasons = "The first call won."
	Set first.Confidence = 0.31
	Do $$$AssertStatusOK($ClassMethod(decide, "Record", first, .saved, .response), "a row for a new item is recorded")
	Do $$$AssertEquals(saved, 1, "and saved")
	Set late = ..NewRow(request.ItemId, "decide", "digest")
	Set sc = $ClassMethod(decide, "Record", late, .saved, .response)
	Do $$$AssertStatusOK(sc, "a row for an item that has one is answered, not failed")
	Do $$$AssertEquals(saved, 0, "and not saved")
	Do $$$AssertTrue($IsObject(response), "the answer is an object")
	If $IsObject(response) {
		Do $$$AssertEquals(response.DecisionRef_"|"_response.Outcome_"|"_response.Reasons_"|"_response.Confidence, first.Ref_"|act|The first call won.|.31", "it is the row that won")
	}
	Do $$$AssertEquals(..Rows(request.ItemId), 1, "and the table holds one row for the item")

	Set request = ..NewRequest("turn", "user")
	Set firstTurn = ..NewRow(request.ItemId, "turn", "tellnow")
	Do $$$AssertStatusOK($ClassMethod(decide, "Record", firstTurn, .saved, .response), "a turn row for a new item is recorded")
	Set lateTurn = ..NewRow(request.ItemId, "turn", "tellnow")
	Set sc = $ClassMethod(decide, "Record", lateTurn, .saved, .response)
	Do $$$AssertStatusNotOK(sc, "a second turn row is refused")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ request.ItemId) && (text [ firstTurn.Ref), "with an error that names the item and the Ref: "_text)
	Do $$$AssertEquals(saved_"|"_response, "0|", "and nothing is saved or answered")
	Do $$$AssertEquals(..Rows(request.ItemId), 1, "and the table holds one row for the turn")
}

/// OnResponse hands the item's own settings to Conclude: a Decide instance whose ReplyFilterClass and HostSinkClass are the probes
/// filters the turn's text once, fires decision.recorded once and records its own session; with the timer's key it ends with an
/// error that holds its TimerSeconds and the runner. No production is started: a turn needs no ReplyClass.
Method TestOnResponseUsesItsSettings()
{
	Set process = ..NewProcess()
	Set process.ReplyFilterClass = ..#FILTER
	Set process.HostSinkClass = ..#SINK
	Set process.%SessionId = 4243
	Set request = ..NewRequest("turn", "user")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ref
	Set sc = process.OnResponse(request, .response, sent, ..NewReply("Everything is fine."), "reply")
	Do $$$AssertStatusOK(sc, "the runner's reply is concluded")
	Do $$$AssertEquals(+$Get(^||ZzProbeFilter), 1, "the filter class of the item ran once")
	Do $$$AssertEquals($Select($IsObject(response): response.Text, 1: ""), "[f] Everything is fine.", "and the answer holds the filtered text")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "the sink class of the item got one call")
	Set row = ..RowOf(request.ItemId, "turn")
	Do $$$AssertTrue($IsObject(row), "a row is recorded")
	If $IsObject(row) {
		Do $$$AssertEquals(row.Ref, ref, "with the DecisionRef of the runner's request")
		Do $$$AssertEquals(row.TraceSessionId, 4243, "and the session of the process")
	}
	Set process.TimerSeconds = 7
	Set sc = process.OnResponse(request, .response, sent, "", "timer")
	Do $$$AssertStatusNotOK(sc, "the timer's key ends with an error")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ "7 seconds") && (text [ "ChatAgent"), "that holds the TimerSeconds of the item and the runner: "_text)
}

/// OnRequest hands the item's own TimerSeconds and ReplyFilterClass to the settings check: a value outside 1 to 110, and a filter
/// class that is no filter, refuse a turn before anything is sent or recorded. No production is started.
Method TestOnRequestUsesItsSettings()
{
	Set process = ..NewProcess()
	Set request = ..NewRequest("turn", "user")
	For timer = 0, 111 {
		Set process.TimerSeconds = timer
		Set sc = process.OnRequest(request, .response)
		Do $$$AssertStatusNotOK(sc, "a TimerSeconds of "_timer_" refuses the request")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "TimerSeconds", "with an error that names it: "_$SYSTEM.Status.GetErrorText(sc))
		Do $$$AssertEquals(response, "", "and gives no answer")
	}
	Set process.TimerSeconds = 60
	Set process.ReplyFilterClass = "OcuTalon.Test.Bridge.ZzNoSuchFilter"
	Set sc = process.OnRequest(request, .response)
	Do $$$AssertStatusNotOK(sc, "a ReplyFilterClass that is no filter refuses the request")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ReplyFilterClass", "with an error that names it: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(..Rows(request.ItemId), 0, "and no row is recorded")
}

/// RecordedAt is a UTC time in the stored form whatever the zone of the process: a row recorded in America/New_York holds a time
/// between two readings that were taken in the process's own zone.
Method TestRecordedAtIsUtc()
{
	Set saved = $SYSTEM.Process.TimeZone()
	Set request = ..NewRequest("decide")
	Try {
		Do $SYSTEM.Process.TimeZone("")
		Set before = ##class(OcuTalon.Bridge.Time).NowUtc()
		Do $SYSTEM.Process.TimeZone("America/New_York")
		Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response)
		Do $SYSTEM.Process.TimeZone("")
		Set after = ##class(OcuTalon.Bridge.Time).NowUtc()
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Do $SYSTEM.Process.TimeZone(saved)
	Do $$$AssertStatusOK(sc, "a decision is recorded in America/New_York")
	Set recorded = ..RowOf(request.ItemId, "decide").RecordedAt
	Do $$$AssertTrue(recorded ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "RecordedAt is a UTC time: "_recorded)
	Do $$$AssertTrue((before ']] recorded) && (recorded ']] after), "and lies between the readings "_before_" and "_after_": "_recorded)
}

/// --- helpers ---
/// A Decide instance for the in-process tests: it is never started or saved, and its settings are the defaults until the test sets
/// them.
ClassMethod NewProcess() As OcuTalon.Bridge.Process.Decide [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Process.Decide).%New("Decide")
}

/// An unsaved Decision row of the item and kind with a new Ref, OwnerRef instance and the outcome.
ClassMethod NewRow(itemId As %String, kind As %String, outcome As %String) As OcuTalon.Bridge.Data.Decision [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.Decision).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Kind = kind
	Set row.ItemId = itemId
	Set row.OwnerRef = "instance"
	Set row.Outcome = outcome
	Quit row
}

/// A request of the kind and provenance with a fresh ItemId, which the test deletes the rows of afterwards.
Method NewRequest(kind As %String, provenance As %String = "untrusted") As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = provenance
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = "instance"
	Set request.Summary = "Test "_request.ItemId
	Set request.Input = "Triage this item."
	Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
	Quit request
}

/// A runner's reply with the text, and the finish reason if one is given.
ClassMethod NewReply(text As %String, finishReason As %String = "") As OcuTalon.Bridge.Msg.Reply [ Private ]
{
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = text
	Set reply.FinishReason = finishReason
	Quit reply
}

/// Conclude for the request, with a Ref of its own, the reply check against DecisionPayload, the filter and the sink (the do-
/// nothing bases by default) and the trace session 4242.
ClassMethod Conclude(request As OcuTalon.Bridge.Msg.Request, reply As OcuTalon.Bridge.Msg.Reply, Output response, filter As %String = "OcuTalon.Bridge.Ext.ReplyFilter", sink As %String = "OcuTalon.Bridge.Ext.HostSink") As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ##class(OcuTalon.Bridge.Ids).NewRef(), reply, ..#REPLYCLASS, filter, sink, 4242, .response)
}

/// The number of Decision rows of the item.
ClassMethod Rows(itemId As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The Decision row of the item and kind, or "".
ClassMethod RowOf(itemId As %String, kind As %String) As OcuTalon.Bridge.Data.Decision [ Private ]
{
	If '##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(itemId, kind, .id) Quit ""
	Quit ##class(OcuTalon.Bridge.Data.Decision).%OpenId(id)
}

/// Asserts that Admit refuses the request with an error that names the field.
Method AssertNamed(request As OcuTalon.Bridge.Msg.Request, field As %String, label As %String) [ Private ]
{
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Admit(request)
	Do $$$AssertStatusNotOK(sc, label_" is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ field, "and the error names "_field_": "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertNotTrue($SYSTEM.Status.GetErrorCodes(sc) = 5003, "and it is not the 'not implemented' error")
}

/// Asserts that CheckReply passes (pass is 1) or fails with an error that names the reply check (pass is 0) for the text.
Method AssertReply(text As %String, pass As %Boolean, label As %String) [ Private ]
{
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).CheckReply(text, ..#REPLYCLASS, .payload)
	If pass {
		Do $$$AssertStatusOK(sc, label_" passes")
		Do $$$AssertTrue($IsObject(payload), label_" gives the payload")
		Quit
	}
	Do $$$AssertStatusNotOK(sc, label_" fails")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "reply check", label_" fails with an error that names the reply check")
	Do $$$AssertEquals(payload, "", label_" gives no payload")
}

/// The highest id of the event log.
ClassMethod LogMark() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// Asserts that the event log holds, after the mark, one warning (type 3) of Decide's FireEvent whose text names the class and the
/// Ref. Outside a production job its ConfigName is empty (measured in Story 1.3).
Method AssertWarning(mark As %Integer, class As %String, ref As %String, label As %String) [ Private ]
{
	Set found = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceClass = ? AND SourceMethod = ?", mark, "OcuTalon.Bridge.Process.Decide", "FireEvent")
	While result.%Next() {
		Set text = result.%GetData(1)
		If (text [ class) && (text [ ref) Set found = found + 1
	}
	Do $$$AssertEquals(found, 1, label_": one warning names "_class_" and the Ref")
}

}
