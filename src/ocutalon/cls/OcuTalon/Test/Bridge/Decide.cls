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
///   - TestLostRace: a row that another call saves after Conclude's check for an existing row, and before its own save, answers,
///     with no second row and no event;
///   - TestConcludeChecksFilter: Conclude refuses a filter class that is no ReplyFilter, with no row and no event;
///   - TestUserRule: a user's ignore and digest become tellnow with the code-written line first; a user's act and tellnow and every
///     untrusted outcome stay;
///   - TestConfidence: 0.12 stays 0.12 and 0.123 is recorded as 0.12, and the confidence never changes the outcome;
///   - TestResponseFromRow: the answer for a recorded decide row, and the refusal for a turn row;
///   - TestOnResponseUsesItsSettings and TestOnRequestUsesItsSettings: the business process hands its own ReplyFilterClass,
///     HostSinkClass, TimerSeconds and session to the class methods, on a Decide instance of the test with no production started;
///   - TestRecordedAtIsUtc: RecordedAt is a UTC time whatever the zone of the process.
/// Added by QA (Story 1.3):
///   - TestUserRule also pins that the user rule is for decide requests only (a user's diagnose reply keeps ignore and digest);
///   - TestReplyCheck also refuses a missing, null or wrong-case outcome and a null, string or negative confidence, and accepts
///     the confidences 0 and 1;
///   - TestReasonLines: a line break inside a model reason becomes a space, so that a reason is one line of the row and cannot add
///     a line of its own, such as a forged copy of the code-written line of the user rule; the Payload keeps the reasons as filtered;
///   - TestTurnKeepsReply: the answer to a turn is a clone of the runner's Reply, with only the Text filtered and the DecisionRef and
///     the outcome set; the runner's own Reply is not changed;
///   - TestSaveFailure: a row that cannot be saved for another reason than the (ItemId, Kind) race is no answer: no response, no
///     event, no row;
///   - TestOnRequestAnswersRecorded: OnRequest answers a recorded decide or diagnose item from its row before it checks any
///     setting or sends anything, and refuses a recorded turn naming the item and the Ref.
/// Added by Story 1.4 (AD-20, AD-26, AD-31):
///   - TestTotals: Conclude puts the sums of the Usage rows of its DecisionRef on the Decision row and on the answer, a decide's and a
///     turn's: the four token counts, the cost, the model of the newest row, the step count of the runner's reply and the duration it
///     is given; with no row the token fields, cost and model are empty, and with a row of unknown cost the cost is empty;
///   - TestTurnKeepsReply now takes the totals and the model from the Usage rows, and every other field from the runner's reply;
///   - TestResponseFromRow also pins that an answer built from a recorded row carries the row's totals;
///   - TestFireEventTypes: FireEvent sends decision.recorded with {"ref"} by default, and the given type with the given payload, and logs
///     a failure with the sink, the event and the subject.
/// Added by Story 1.5 (AD-9, AD-26, AD-30):
///   - TestStepMessages: StepMessages builds one AgentStep for each record of the reply's Steps, with the DecisionRef given, the Position
///     of the record in the array, and its kind, label, summary, duration, status and estimate; a reply with no Steps, with white space
///     and with a reply of another class gets none and no warning; Steps that is not a JSON array, and a record that is not an object, get
///     none (or skip the record) and one warning that names the DecisionRef and not the content; Conclude's answer to a turn has no Steps;
///   - TestTurnKeepsReply also pins that the answer to a turn does not carry the runner's Steps, and the runner's own Reply keeps them.
/// Every test removes the Usage rows it made.
Class OcuTalon.Test.Bridge.Decide Extends %UnitTest.TestCase
{

/// A usable reply of Triage's default script.
Parameter DIGEST = "{""outcome"":""digest"",""reasons"":[""The CI mock keeps this item for the digest.""],""confidence"":0.5}";

Parameter FILTER = "OcuTalon.Test.Bridge.ProbeFilter";

Parameter SINK = "OcuTalon.Test.Bridge.ProbeSink";

Parameter REPLYCLASS = "OcuTalon.Bridge.Msg.DecisionPayload";

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

/// The DecisionRefs of the Usage rows that the test made.
Property UsageRefs As %List;

Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Set position = 0
	While $ListNext(..UsageRefs, position, ref) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ?", ref)
	}
	Set ..UsageRefs = ""
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
	Do ..AssertReply("{""reasons"":[""r""],""confidence"":0.5}", 0, "no outcome")
	Do ..AssertReply("{""outcome"":null,""reasons"":[""r""],""confidence"":0.5}", 0, "a null outcome")
	Do ..AssertReply("{""outcome"":""Ignore"",""reasons"":[""r""],""confidence"":0.5}", 0, "an outcome in the wrong case")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[""r""],""confidence"":null}", 0, "a null confidence")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[""r""],""confidence"":""high""}", 0, "a confidence that is a string")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[""r""],""confidence"":-0.1}", 0, "a negative confidence")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[""r""],""confidence"":0}", 1, "a confidence of 0")
	Do ..AssertReply("{""outcome"":""tellnow"",""reasons"":[""r"",""""],""confidence"":1}", 1, "a confidence of 1, and a blank reason beside a real one")

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
	For outcome = "ignore", "digest" {
		Set request = ..NewRequest("diagnose", "user")
		Set json = "{""outcome"":"""_outcome_""",""reasons"":["""_reason_"""],""confidence"":0.4}"
		Set sc = ..Conclude(request, ..NewReply(json), .response)
		Do $$$AssertStatusOK(sc, "a user's diagnose reply of "_outcome_" is recorded")
		Set row = ..RowOf(request.ItemId, "diagnose")
		If '$IsObject(row) || '$IsObject(response) {
			Do $$$AssertTrue(0, "a user's diagnose reply of "_outcome_" is recorded and answered")
			Continue
		}
		Do $$$AssertEquals(row.Outcome_"|"_response.Outcome, outcome_"|"_outcome, "the user rule is for decide requests only: a user's diagnose request keeps "_outcome)
		Do $$$AssertEquals(row.Reasons_"|"_response.Reasons, reason_"|"_reason, "and has no code-written line")
	}
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

	Set request = ..NewRequest("diagnose")
	Set ref = ..NewUsageRef()
	Do ..AddUsage(ref, "claude-haiku-5-5", 3800, 300, 2000, 600, .000365)
	Set reply = ..NewReply(..#DIGEST)
	Set reply.AgentStepCount = 3
	Do $$$AssertStatusOK(..ConcludeWith(request, ref, reply, 987, .made), "a diagnose reply with a Usage row is recorded")
	Set row = ..RowOf(request.ItemId, "diagnose")
	Do $$$AssertEquals(..Totals(row), "3800|300|2000|600|.000365|claude-haiku-5-5|3|987", "its row holds the totals")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.Decide).ResponseFromRow(row, .response), "the answer for the row is built")
	Do $$$AssertEquals(..Totals(response), "3800|300|2000|600|.000365|claude-haiku-5-5|3|987", "and carries the totals of the row")
	Do $$$AssertEquals(..Totals(made), ..Totals(response), "as the answer that Conclude gave does")
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

/// The lost save race: another call saves its row for the item and kind after Conclude's check for an existing row and before
/// Conclude's own save (the stand-in request ProbeRaceRequest saves it when Conclude reads its Summary). Conclude answers with the
/// row that won, records no second row and fires no event.
Method TestLostRace()
{
	Kill ^||ZzProbeSink
	Set template = ..NewRequest("decide")
	Set request = ##class(OcuTalon.Test.Bridge.ProbeRaceRequest).%New()
	Set request.Kind = "decide", request.Provenance = "untrusted", request.ItemId = template.ItemId, request.OwnerRef = "instance", request.Summary = template.Summary
	Set request.Competitor = ..NewRow(template.ItemId, "decide", "act")
	Set request.Competitor.Reasons = "The other call won the race."
	Set request.Competitor.Confidence = 0.31
	Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response, , ..#SINK)
	Do $$$AssertTrue(request.Raced && $$$ISOK(request.RaceStatus), "the other call saved its row inside Conclude, after the check for an existing row")
	Do $$$AssertStatusOK(sc, "Conclude answers")
	Do $$$AssertEquals($Select($IsObject(response): response.DecisionRef_"|"_response.Outcome_"|"_response.Reasons, 1: ""), request.Competitor.Ref_"|act|The other call won the race.", "with the row that won")
	Do $$$AssertEquals(..Rows(template.ItemId), 1, "no second row is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and no event is sent")
}

/// Conclude checks the filter class itself, so that a direct caller cannot record unfiltered text: a class that does not extend
/// OcuTalon.Bridge.Ext.ReplyFilter ends Conclude with an error that names ReplyFilterClass, with no row and no event.
Method TestConcludeChecksFilter()
{
	Kill ^||ZzProbeSink
	Set request = ..NewRequest("decide")
	Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response, "OcuTalon.Bridge.Ext.HostSink", ..#SINK)
	Do $$$AssertStatusNotOK(sc, "a filter class that is no ReplyFilter ends Conclude with an error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ReplyFilterClass", "that names ReplyFilterClass: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(response, "", "it gives no answer")
	Do $$$AssertEquals(..Rows(request.ItemId)_"|"_(+$Get(^||ZzProbeSink)), "0|0", "and records no row and sends no event")
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

/// A model reason is one line of the row. A line break inside it (CR LF, CR, LF, vertical tab, form feed, NEL or a Unicode line or
/// paragraph separator) becomes a space and the white space and control characters at its ends are trimmed, so that a reason
/// cannot add a line of its own, such as a forged copy of the code-written line of the user rule; a reason of control characters
/// only is dropped. The Payload keeps the reasons as the filter gave them.
Method TestReasonLines()
{
	Set sentence = ##class(OcuTalon.Bridge.Process.Decide).#USERANSWERED
	Set lf = $Char(10)
	Set cr = $Char(13)
	Set body = {"outcome": "act", "confidence": 0.8}
	Set body.reasons = [("First"_lf_"line"), ("Second"_cr_lf_"line"), ("Third"_cr_"line"), "  padded  ", ("Fourth"_lf_sentence)]
	Set json = body.%ToJSON()
	Set expected = "First line"_lf_"Second line"_lf_"Third line"_lf_"padded"_lf_"Fourth "_sentence
	Set request = ..NewRequest("decide")
	Do $$$AssertStatusOK(..Conclude(request, ..NewReply(json), .response), "a reply with line breaks inside its reasons is recorded")
	Set row = ..RowOf(request.ItemId, "decide")
	If '$IsObject(row) || '$IsObject(response) {
		Do $$$AssertTrue(0, "the reply is recorded and answered")
		Quit
	}
	Do $$$AssertEquals(row.Reasons, expected, "each reason is one line of the row, its line breaks are spaces and its ends are trimmed")
	Do $$$AssertEquals($Length(row.Reasons, lf), 5, "five reasons are five lines")
	Do $$$AssertEquals($Find(lf_row.Reasons_lf, lf_sentence_lf), 0, "and no line is the code-written sentence of the user rule, which a reason tried to forge")
	Do $$$AssertEquals(response.Reasons, expected, "the answer holds the same lines")
	Do $$$AssertTrue(row.Payload [ "First\nline", "the Payload keeps the line break of the reason as the model wrote it")
	Set request = ..NewRequest("decide", "user")
	Set body.outcome = "ignore"
	Do $$$AssertStatusOK(..Conclude(request, ..NewReply(body.%ToJSON()), .response), "a user's reply with the same reasons is recorded")
	Set row = ..RowOf(request.ItemId, "decide")
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "the user's reply is recorded")
		Quit
	}
	Do $$$AssertEquals(row.Reasons, sentence_lf_expected, "the code-written line is the first of the lines, and only the code wrote it")
	Do $$$AssertEquals($Length(row.Reasons, lf), 6, "one line more than the five reasons")
	Set body = {"outcome": "act", "confidence": 0.8}
	Set body.reasons = [("Fifth"_$Char(8232)_sentence), ("Sixth"_$Char(133)_"line"), ("Seventh"_$Char(11, 12)_"line"), ("Eighth"_$Char(8233)_"line"), ($Char(7, 9))]
	Set request = ..NewRequest("decide")
	Do $$$AssertStatusOK(..Conclude(request, ..NewReply(body.%ToJSON()), .response), "a reply whose reasons hold the other line breaks, and a reason of control characters only, is recorded")
	Set row = ..RowOf(request.ItemId, "decide")
	Set reasons = $Select($IsObject(row): row.Reasons, 1: "")
	Do $$$AssertEquals(reasons, "Fifth "_sentence_lf_"Sixth line"_lf_"Seventh  line"_lf_"Eighth line", "NEL, VT, FF and the Unicode line and paragraph separators are spaces too, and the reason of control characters is dropped")
	Do $$$AssertEquals($Find(lf_reasons_lf, lf_sentence_lf), 0, "so no line is the code-written sentence")
}

/// The answer to a turn is a clone of the runner's Reply: its Text is filtered and its DecisionRef and Outcome are set, and every
/// other field that the runner set (the taint flag of AD-10, the session and tool flags, the host data, the finish reason and the step
/// count) reaches the caller. The totals and the model are those of the decision, the sums of its Usage rows, not the runner's own. The
/// runner's own Reply is not changed.
Method TestTurnKeepsReply()
{
	Set request = ..NewRequest("turn", "user")
	Set ref = ..NewUsageRef()
	Do ..AddUsage(ref, "zz-model-of-the-rows", 777, 88, 9, 10, .0042)
	Set reply = ..NewReply("Everything is fine.", "end_turn")
	Set reply.Tainted = 1
	Set reply.SessionRotated = 1
	Set reply.ToolsRun = 1
	Set reply.HostData = "{""rows"":[1]}"
	Set reply.Model = "claude-haiku-5-5"
	Set reply.InputTokens = 123
	Set reply.OutputTokens = 45
	Set reply.AgentStepCount = 4
	Set reply.Steps = "[{""kind"":""model"",""label"":""Model request 1"",""summary"":""zz"",""durationMs"":1,""status"":""ok"",""estimatedTokens"":2}]"
	Set sc = ..ConcludeWith(request, ref, reply, 250, .response, ..#FILTER)
	Do $$$AssertStatusOK(sc, "a turn reply with the runner's flags and totals is recorded")
	If '$IsObject(response) {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertTrue(response.%IsA("OcuTalon.Bridge.Msg.Reply"), "the answer is a Reply")
	Do $$$AssertEquals(response.Text, "[f] Everything is fine.", "its Text is the filtered text")
	Do $$$AssertEquals(response.Tainted_"|"_response.SessionRotated_"|"_response.ToolsRun, "1|1|1", "the taint, session-rotated and tools-run flags of the runner reach the caller")
	Do $$$AssertEquals(response.HostData_"|"_response.FinishReason, "{""rows"":[1]}|end_turn", "and so do the host data and the finish reason")
	Do $$$AssertEquals(..Totals(response), "777|88|9|10|.0042|zz-model-of-the-rows|4|250", "the totals and the model are those of the Usage rows of the decision, the step count the runner's, the duration the one given")
	Set row = ..RowOf(request.ItemId, "turn")
	Do $$$AssertTrue($IsObject(row), "the turn is recorded")
	If $IsObject(row) {
		Do $$$AssertEquals(response.DecisionRef_"|"_response.Outcome, row.Ref_"|tellnow", "with the DecisionRef of its row and the outcome tellnow")
		Do $$$AssertEquals(..Totals(row), ..Totals(response), "and its row holds the same totals")
	}
	Do $$$AssertEquals(reply.Text_"|"_reply.Outcome_"|"_reply.DecisionRef, "Everything is fine.||", "the runner's own Reply is not changed")
	Do $$$AssertEquals(reply.InputTokens_"|"_reply.OutputTokens_"|"_reply.Model_"|"_reply.AgentStepCount, "123|45|claude-haiku-5-5|4", "not even its totals")
	Do $$$AssertEquals(response.Steps, "", "the answer does not carry the runner's Steps: Decide has sent them as messages")
	Do $$$AssertTrue(reply.Steps [ "Model request 1", "and the runner's own Reply keeps them")
}

/// StepMessages: one AgentStep for each record of the reply's Steps, in order. Steps that is empty, white space or missing gives none
/// and no warning; Steps that is no JSON array, and a record that is no object, give a warning that names the DecisionRef and never the
/// content. The answer to a turn has no Steps.
Method TestStepMessages()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set steps = [{"kind": "model", "label": "Model request 1", "summary": "About 100 tokens sent (an estimate). Reply: 0 characters of text, 1 tool calls.", "durationMs": 1001, "status": "ok", "estimatedTokens": 100}, {"kind": "tool", "label": "Reading the test note", "summary": "zz_steps_note. Inputs: {}. Result: {}. About 1 tokens added to the next request (an estimate).", "durationMs": 252, "status": "error", "estimatedTokens": 1}]
	Set reply = ..NewReply("Everything is fine.")
	Set reply.Steps = steps.%ToJSON()
	Set mark = ..LogMark()
	Set messages = $ClassMethod(decide, "StepMessages", ref, reply)
	Do $$$AssertEquals(messages.Count(), 2, "two records give two messages")
	If messages.Count() = 2 {
		Set first = messages.GetAt(1)
		Set second = messages.GetAt(2)
		Do $$$AssertEquals(first.%ClassName(1), "OcuTalon.Bridge.Msg.AgentStep", "each is an AgentStep")
		Do $$$AssertEquals(first.DecisionRef_"|"_first.Position_"|"_first.StepKind_"|"_first.Label_"|"_first.DurationMs_"|"_first.Status_"|"_first.EstimatedTokens, ref_"|1|model|Model request 1|1001|ok|100", "the first has the DecisionRef, Position 1 and the fields of the first record")
		Do $$$AssertEquals(first.Summary, "About 100 tokens sent (an estimate). Reply: 0 characters of text, 1 tool calls.", "and its summary")
		Do $$$AssertEquals(second.DecisionRef_"|"_second.Position_"|"_second.StepKind_"|"_second.Label_"|"_second.DurationMs_"|"_second.Status_"|"_second.EstimatedTokens, ref_"|2|tool|Reading the test note|252|error|1", "the second has Position 2 and the fields of the second record")
		Do $$$AssertEquals(second.Summary, "zz_steps_note. Inputs: {}. Result: {}. About 1 tokens added to the next request (an estimate).", "and its summary")
	}
	Do $$$AssertEquals(..WarningsOf(mark, ref), 0, "and there is no warning")

	For text = "", " ", $Char(10, 9), "[]" {
		Set reply.Steps = text
		Set messages = $ClassMethod(decide, "StepMessages", ref, reply)
		Do $$$AssertEquals(messages.Count(), 0, "Steps '" _ $Translate(text, $Char(10, 9), "  ") _ "' gives no message")
	}
	Set messages = $ClassMethod(decide, "StepMessages", ref, "")
	Do $$$AssertEquals(messages.Count(), 0, "no reply gives none")
	Set messages = $ClassMethod(decide, "StepMessages", ref, ##class(OcuTalon.Bridge.Msg.AgentStep).%New())
	Do $$$AssertEquals(messages.Count(), 0, "and neither does a message of another class")
	Do $$$AssertEquals(..WarningsOf(mark, ref), 0, "none of them is a problem")

	For text = "{", "[{""kind"":""zzstepcontent""", "{""kind"":""zzstepcontent""}", "zzstepcontent", """zzstepcontent""", "17" {
		Set reply.Steps = text
		Set before = ..WarningsOf(mark, ref)
		Set messages = $ClassMethod(decide, "StepMessages", ref, reply)
		Do $$$AssertEquals(messages.Count(), 0, "Steps '" _ text _ "' gives no message")
		Do $$$AssertEquals(..WarningsOf(mark, ref) - before, 1, "and one warning that names the DecisionRef")
	}
	Do $$$AssertEquals(..LogRowsHolding(mark, "zzstepcontent"), 0, "no warning holds the content of the Steps")

	Set reply.Steps = "[{""kind"":""model"",""label"":""L"",""summary"":""S"",""durationMs"":1,""status"":""ok"",""estimatedTokens"":2}, ""zzstepcontent"", 5, null, {""kind"":""tool"",""label"":""M"",""summary"":""T"",""durationMs"":3,""status"":""ok"",""estimatedTokens"":4}]"
	Set before = ..WarningsOf(mark, ref)
	Set messages = $ClassMethod(decide, "StepMessages", ref, reply)
	Do $$$AssertEquals(messages.Count(), 2, "records that are no object are skipped: two messages")
	If messages.Count() = 2 Do $$$AssertEquals(messages.GetAt(1).Position_"|"_messages.GetAt(2).Position, "1|5", "the Position is the place in the array")
	Do $$$AssertEquals(..WarningsOf(mark, ref) - before, 3, "with one warning for each of them")

	Set request = ..NewRequest("turn", "user")
	Set reply = ..NewReply("Everything is fine.")
	Set reply.Steps = steps.%ToJSON()
	Do $$$AssertStatusOK(..ConcludeWith(request, ..NewUsageRef(), reply, 1, .response), "a turn whose reply has Steps is concluded")
	Do $$$AssertEquals($Select($IsObject(response): response.Steps, 1: "none"), "", "its answer has no Steps")
	Do $$$AssertEquals(reply.Steps, steps.%ToJSON(), "and the runner's Reply keeps them")
}

/// Conclude puts the totals of the decision on the Decision row and on the answer, for a decide and for a turn (AD-20, AD-26): the
/// sums of the Usage rows of its DecisionRef in InputTokens, OutputTokens, CacheReadTokens, CacheWriteTokens and CostUSD, the Model of
/// the newest row, the AgentStepCount of the runner's reply, and the DurationMs it is given. A decision with no Usage row has empty
/// token fields, cost and model, and one with a row of unknown cost has an empty cost. The reply's own totals are never used.
Method TestTotals()
{
	For kind = "decide", "turn" {
		Set request = ..NewRequest(kind, $Select(kind = "turn": "user", 1: "untrusted"))
		Set ref = ..NewUsageRef()
		Do ..AddUsage(ref, "claude-haiku-5-5", 3800, 300, 2000, 600, .000365)
		Do ..AddUsage(ref, "claude-sonnet-5-5", 1200, 50, 0, 100, .0123)
		Do ..AddUsage(..NewUsageRef(), "claude-haiku-5-5", 99999, 99999, 99999, 99999, 9)
		Set reply = ..NewReply($Select(kind = "turn": "Everything is fine.", 1: ..#DIGEST))
		Set reply.AgentStepCount = 5
		Set reply.InputTokens = 1
		Set reply.CostUSD = 1
		Set reply.Model = "zz-model-of-the-reply"
		Do $$$AssertStatusOK(..ConcludeWith(request, ref, reply, 1234, .response), "a "_kind_" with two Usage rows is recorded")
		Set row = ..RowOf(request.ItemId, kind)
		If '$IsObject(row) || '$IsObject(response) {
			Do $$$AssertTrue(0, "the "_kind_" is recorded and answered")
			Continue
		}
		Set expected = "5000|350|2000|700|.012665|claude-sonnet-5-5|5|1234"
		Do $$$AssertEquals(..Totals(row), expected, "the "_kind_" row holds the sums, the model of the newest row, the runner's step count and the duration")
		Do $$$AssertEquals(..Totals(response), expected, "and so does the answer")
	}

	Set request = ..NewRequest("decide")
	Set reply = ..NewReply(..#DIGEST)
	Set reply.AgentStepCount = 5
	Set reply.InputTokens = 1
	Do $$$AssertStatusOK(..ConcludeWith(request, ..NewUsageRef(), reply, 1234, .response), "a decide with no Usage row is recorded")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals(..Totals(row), "||||||5|1234", "its row has empty token fields, cost and model, and the step count and the duration")
	Do $$$AssertEquals(..Totals(response), "||||||5|1234", "and so does the answer")

	Set request = ..NewRequest("turn", "user")
	Do $$$AssertStatusOK(..ConcludeWith(request, ..NewUsageRef(), ..NewReply("Hello."), "", .response), "a turn with no Usage row and no duration is recorded")
	Do $$$AssertEquals(..Totals(..RowOf(request.ItemId, "turn")), "|||||||", "its row has nothing but empty fields")
	Do $$$AssertEquals(..Totals(response), "|||||||", "and so does the answer")

	Set request = ..NewRequest("decide")
	Set ref = ..NewUsageRef()
	Do ..AddUsage(ref, "claude-haiku-5-5", 100, 10, 0, 0, .0001)
	Do ..AddUsage(ref, "zz-unpriced", 200, 20, 5, 6, "")
	Do $$$AssertStatusOK(..ConcludeWith(request, ref, ..NewReply(..#DIGEST), 10, .response), "a decide with a Usage row of unknown cost is recorded")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals(..Totals(row), "300|30|5|6||zz-unpriced||10", "its cost is empty, never the sum of the others, and the other fields are the sums")
	Do $$$AssertEquals(..Totals(response), "300|30|5|6||zz-unpriced||10", "and so is the answer's")
}

/// FireEvent sends decision.recorded with {"ref"} when it is given no type, and the type with the payload it is given; the warning of a
/// sink that fails names the sink, the event and the subject (the day, for budget.capped). It returns 1 when the sink took the event.
Method TestFireEventTypes()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Kill ^||ZzProbeSink
	Do $$$AssertEquals($ClassMethod(decide, "FireEvent", ..#SINK, "ZzOwner", "ref1"), 1, "an event with no type is delivered")
	Set call = $Get(^||ZzProbeSink(1))
	Do $$$AssertEquals($List(call, 1)_"|"_$List(call, 2)_"|"_$List(call, 3), "decision.recorded|ZzOwner|{""ref"":""ref1""}", "it is decision.recorded with the Ref as its payload")
	Do $$$AssertEquals($ClassMethod(decide, "FireEvent", ..#SINK, "ZzOwner", "ref2", "approval.raised"), 1, "an event with a type and no payload is delivered")
	Set call = $Get(^||ZzProbeSink(2))
	Do $$$AssertEquals($List(call, 1)_"|"_$List(call, 3), "approval.raised|{""ref"":""ref2""}", "it has that type and the Ref as its payload")
	Kill ^||ZzProbeSink
	Kill ^OcuTalonBP.UsageCapped("2001-02-03")
	Set payload = ##class(OcuTalon.Bridge.Ext.HostSink).BudgetCappedPayload("2001-02-03")
	Do $$$AssertEquals($ClassMethod(decide, "FireEvent", ..#SINK, "instance", "2001-02-03", "budget.capped", payload), 1, "budget.capped with its payload is delivered")
	Set call = $Get(^||ZzProbeSink(1))
	Do $$$AssertEquals($List(call, 1)_"|"_$List(call, 2)_"|"_$List(call, 3), "budget.capped|instance|{""day"":""2001-02-03""}", "with the owner and the payload it was given")
	Do $$$AssertEquals($List(call, 4)_"|"_$List(call, 5)_"|"_$List(call, 6), "0||0", "outside any transaction, with no ref and no mark")

	For mode = "error", "throw" {
		Kill ^||ZzProbeSink
		Set ^||ZzProbeSink("mode") = mode
		Set mark = ..LogMark()
		Do $$$AssertEquals($ClassMethod(decide, "FireEvent", ..#SINK, "instance", "2001-02-03", "budget.capped", payload), 0, "in "_mode_" mode the event is not delivered")
		Do ..AssertWarning(mark, ..#SINK, "2001-02-03", "budget.capped in "_mode_" mode", "budget.capped")
	}
	Kill ^||ZzProbeSink
	Set mark = ..LogMark()
	Do $$$AssertEquals($ClassMethod(decide, "FireEvent", "OcuTalon.Test.Bridge.ProbeNotASink", "instance", "2001-02-03", "budget.capped", payload), 0, "a class that is no host sink gets no event")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and the probe heard nothing")
	Do ..AssertWarning(mark, "OcuTalon.Test.Bridge.ProbeNotASink", "2001-02-03", "budget.capped to a class that is no sink", "budget.capped")
}

/// A decision whose row cannot be saved is no answer: Conclude ends with the save error, gives no response, fires no event and
/// records no row for the item. Here another row already holds the new Ref (RefIndex is unique); the race on (ItemId, Kind) is
/// TestRecord's.
Method TestSaveFailure()
{
	Kill ^||ZzProbeSink
	Set taken = ..NewRequest("decide")
	Set first = ..NewRow(taken.ItemId, "decide", "act")
	Do $$$AssertStatusOK(first.%Save(), "a row holds a Ref")
	Set request = ..NewRequest("decide")
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, first.Ref, ..NewReply(..#DIGEST), ..#REPLYCLASS, "OcuTalon.Bridge.Ext.ReplyFilter", ..#SINK, 4242, .response)
	Do $$$AssertStatusNotOK(sc, "a decision whose Ref is taken ends with the save error")
	Do $$$AssertEquals(response, "", "it gives no answer")
	Do $$$AssertEquals(..Rows(request.ItemId), 0, "it records no row for the item")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and sends no event")
	Do $$$AssertEquals(..Rows(taken.ItemId), 1, "the row that holds the Ref is as it was")
	Set late = ..NewRow(request.ItemId, "decide", "digest")
	Set late.Ref = first.Ref
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Record(late, .saved, .response)
	Do $$$AssertStatusNotOK(sc, "Record returns the save error when no row of the item and kind exists")
	Do $$$AssertEquals(saved_"|"_response, "0|", "and saved nothing and answered nothing")
}

/// OnRequest answers an item that has a decision from its row, before it checks any setting or sends anything: for a decide request
/// and for a diagnose request (DiagnosisAgent has no ReplyClass until Story 5.4, and an answer from a row needs none). A recorded
/// turn is refused with an error that names the item and the Ref. The process of the test has a ReplyFilterClass that is no
/// filter, so that a request that went on to the settings check would be refused (the last case shows it); no production is
/// started and nothing is sent.
Method TestOnRequestAnswersRecorded()
{
	Set process = ..NewProcess()
	Set process.ReplyFilterClass = "OcuTalon.Test.Bridge.ZzNoSuchFilter"
	Set process.TimerSeconds = 60
	For kind = "decide", "diagnose" {
		Set request = ..NewRequest(kind)
		Set row = ..NewRow(request.ItemId, kind, "act")
		Set row.Reasons = "The recorded reason."
		Set row.Confidence = 0.31
		Set row.Payload = "{""outcome"":""act""}"
		Do $$$AssertStatusOK(row.%Save(), "a "_kind_" row is recorded")
		Set sc = process.OnRequest(request, .response)
		Do $$$AssertStatusOK(sc, "a "_kind_" request for a recorded item is answered, not refused")
		If '$IsObject(response) {
			Do $$$AssertTrue(0, "the "_kind_" answer is a DecisionResponse")
			Continue
		}
		Do $$$AssertEquals(response.DecisionRef_"|"_response.Outcome_"|"_response.Reasons_"|"_response.Confidence_"|"_response.Payload, row.Ref_"|act|The recorded reason.|.31|{""outcome"":""act""}", "from the row: its Ref, outcome, reasons, confidence and Payload")
	}
	Set request = ..NewRequest("turn", "user")
	Set row = ..NewRow(request.ItemId, "turn", "tellnow")
	Do $$$AssertStatusOK(row.%Save(), "a turn row is recorded")
	Set sc = process.OnRequest(request, .response)
	Do $$$AssertStatusNotOK(sc, "a turn request for a recorded item is refused")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ request.ItemId) && (text [ row.Ref), "with an error that names the item and the Ref: "_text)
	Do $$$AssertEquals(response, "", "and gives no answer")
	Set request = ..NewRequest("turn", "user")
	Set sc = process.OnRequest(request, .response)
	Do $$$AssertStatusNotOK(sc, "while a turn request for an item with no decision goes on to the settings check and is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ReplyFilterClass", "for the filter class of this process: "_$SYSTEM.Status.GetErrorText(sc))
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
	Do $SYSTEM.Process.TimeZone($Select(saved = -1: "", 1: saved))
	Do $$$AssertStatusOK(sc, "a decision is recorded in America/New_York")
	Set recorded = ..RowOf(request.ItemId, "decide").RecordedAt
	Do $$$AssertTrue(recorded ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "RecordedAt is a UTC time: "_recorded)
	Do $$$AssertTrue((before ']] recorded) && (recorded ']] after), "and lies between the readings "_before_" and "_after_": "_recorded)
}

/// --- helpers ---
/// A Decide instance for the in-process tests: it is never started or saved. Its settings are those of the Decide item of the
/// active production (Ens.Host's initConfig), so a test sets every setting that it relies on.
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

/// Conclude as the helper above does, for a DecisionRef that the test chose (the Usage rows of the decision carry it) and with the
/// duration that Decide measured. response is the answer.
ClassMethod ConcludeWith(request As OcuTalon.Bridge.Msg.Request, ref As %String, reply As OcuTalon.Bridge.Msg.Reply, durationMs As %Integer, Output response, filter As %String = "OcuTalon.Bridge.Ext.ReplyFilter", sink As %String = "OcuTalon.Bridge.Ext.HostSink") As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ref, reply, ..#REPLYCLASS, filter, sink, 4242, .response, durationMs)
}

/// A new DecisionRef for Usage rows, which the test deletes the rows of afterwards.
Method NewUsageRef() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..UsageRefs = ..UsageRefs _ $ListBuild(ref)
	Quit ref
}

/// Saves a Usage row of the DecisionRef (Test.Agent.RunnerFixture.AddUsage).
Method AddUsage(ref As %String, model As %String, input As %Integer, completion As %Integer, cacheRead As %Integer, cacheWrite As %Integer, cost As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).AddUsage(ref, model, input, completion, cacheRead, cacheWrite, cost), "a Usage row of "_model_" is saved")
}

/// The eight total fields of a Decision row or an answer, in the order of Result: InputTokens, OutputTokens, CacheReadTokens,
/// CacheWriteTokens, CostUSD, Model, AgentStepCount and DurationMs, joined by | (Test.Agent.RunnerFixture.Totals).
ClassMethod Totals(object As %RegisteredObject) As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).Totals(object)
}

/// The number of Decision rows of the item.
ClassMethod Rows(itemId As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The Decision row of the item and kind, or "" (Test.Agent.RunnerFixture.DecisionOf, which needs no production).
ClassMethod RowOf(itemId As %String, kind As %String) As OcuTalon.Bridge.Data.Decision [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(itemId, kind)
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

/// The number of warnings of Decide's StepMessages after the mark that name the DecisionRef.
ClassMethod WarningsOf(mark As %Integer, ref As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Process.Decide", "StepMessages", $ListBuild(ref))
}

/// The number of event-log rows after the mark whose text holds the value (Test.Agent.RunnerFixture.LogRowsHolding).
ClassMethod LogRowsHolding(mark As %Integer, value As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(mark, value)
}

/// The highest id of the event log (Test.Agent.RunnerFixture.EventMark).
ClassMethod LogMark() As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
}

/// Asserts that the event log holds, after the mark, one warning (type 3) of Decide's FireEvent whose text names the class, the
/// Ref and, when given, the event. Outside a production job its ConfigName is empty (measured in Story 1.3).
Method AssertWarning(mark As %Integer, class As %String, ref As %String, label As %String, event As %String = "") [ Private ]
{
	Set found = ##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Process.Decide", "FireEvent", $ListBuild(class, ref, event))
	Do $$$AssertEquals(found, 1, label_": one warning names "_class_" and the Ref")
}

}
