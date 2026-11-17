Include Ensemble

/// Tests of the capture of the fallback replies of an eval run, OcuTalon.Test.Eval.CaptureTool (DW-1421; AD-8), and of the silence of Decide.Recheck. The tests seed fallback decisions as a
/// run leaves them (a Decision row, the Request that carries its Ref, the Reply, and the request header and its response header, which are linked by CorrespondingMessageId), run the tool over
/// them only (its refs), and remove every row, header, file and folder they made (OnAfterOneTest). They need the production's runner items and their ReplyClass settings, so they run on a stack, a
/// warm one included, and no model is called.
///   - TestOneReplyPerRule (AC 5): one diagnose reply for each of the 21 rules that a diagnosis can meet, a diagnose reply with no confidence (it passes, DW-1421 C5), a triage reply with no confidence, a reply that passes, a reply that holds no text, a
///     reply with an unknown field, a reply that is not JSON, an over-long elementAtFault (its own length tag) and a mistyped reasons (import refusals, whose field is the JSON name of the compiled property), a reply with an
///     over-long evidence element (cut by the import, so it passes the check),
///     a reply that is valid until the filter blanks its cause, one with no reason left after the filter, a cut_off fallback whose reply would fail the check, a decision with no reply and a second attempt on DiagnosisAgentRetry give the summary's counts (each rule once, cause-blank twice, "passes the check" four times) with the field of each rule,
///     one file for each reply (and summary.json), and each file holds its text, attempt, runner, stage, rule and field;
///   - TestLinesHoldNoReplyText (AC 6): each seeded reply carries a distinct marker, and the CHK lines hold no marker and no 10-character part of one, while the files hold each;
///   - TestRecordsAndLogsNothing (AC 7): Run leaves the event log rows of its job, the Decision and Usage rows and the bridge's Ens message headers as they were, and the source of the tool names no logging, no AI call, no send, no
///     Conclude and no runner item;
///   - TestRecheckIsSilent (DW-1421): Decide.Recheck, for a refused reply, a usable one, one whose evidence elements are cut, one that the filter leaves with no reason and one that the filter makes invalid, changes none of those counts;
///   - TestRuleNames (DW-1421 C1): RuleOf and FieldOf give the rule and the field of a part, the form "ERROR #<code> rule <tag>" included;
///   - TestLengthTagCounted (DW-1421 C1, QA): Run counts a reply refused with "ERROR #7201 rule evidence-too-long" under that rule and the field evidence, in the summary and the
///     reply's file, with no reply text in the CHK lines;
///   - TestNothingIsWrittenAnywhere (DW-1421): Run and Recheck add or remove no row of any persistent table of the product and no non-OcuTalon message header (an alert), and write no audit entry;
///   - TestAttemptsAreNumberedByRequest (DW-1421): the attempts of a decision are numbered by their request headers, whether or not each has an answer in the store, and not by the order of the answers;
///   - TestHostileRepliesStayOffStdout (DW-1421): replies, a case name and a fallback reason that carry line ends, quotes, bars, a fake CHK line, non-ASCII characters and a rule name never put anything but the known CHK lines on stdout, and the files hold each reply byte for byte;
///   - TestRecheckIsUnreachable (DW-1421): no class of the REST, channel, conversation, tool, agent or MCP code names Recheck, and no class but Decide names Recheck of Decide;
///   - TestNoFallbackWritesNoFile (I/O row 8): with no fallback decision among the refs the summary counts nothing and no file is written, summary.json included; an empty folder is an error;
///   - TestUncheckableReplyIsCounted: a reply whose runner has no reply class is counted under "no check", and the other replies of the run are still judged and written.
/// The silence tests count rows (Writes): a write of the call under test changes a count in each of up to three tries, while the production's background work in other jobs, which
/// may land in one try, does not fail them.
Class OcuTalon.Test.Eval.Capture Extends %UnitTest.TestCase
{

Parameter TOOL = "OcuTalon.Test.Eval.CaptureTool";

Parameter DECIDE = "OcuTalon.Bridge.Process.Decide";

Parameter PAYLOAD = "OcuTalon.Test.Watch.Payload";

Parameter CLASS = "OcuTalon.Watch.Msg.DiagnosisPayload";

/// The runner items that the production has for the replies.
Parameter DIAGNOSIS = "DiagnosisAgent";

Parameter RETRY = "DiagnosisAgentRetry";

Parameter TRIAGE = "TriageAgent";

/// The seeded rows, as $ListBuild of the Decision Ref, the Decision's id and the ids of the request and reply headers and bodies, for the clean-up: one element per seeded thing, "kind|id".
Property Made As %List;

/// The refs of the seeded decisions, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The folder of the test.
Property Folder As %String(MAXLEN = 256);

/// The temporary file whose name the folder's name is made from.
Property TempFile As %String(MAXLEN = 256);

/// The seeds, by decision Ref: $ListBuild(marker, text, rule, field).
Property Seeds As %String(MAXLEN = "");

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Made = ""
	Set ..Refs = ""
	Set ..TempFile = ##class(%File).TempFilename()
	Set ..Folder = ##class(%File).NormalizeDirectory(..TempFile_"-capture")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..Made, position, made) {
		Set kind = $Piece(made, "|", 1)
		Set id = $Piece(made, "|", 2)
		If kind = "header" Do ##class(Ens.MessageHeader).%DeleteId(id)
		If kind = "request" Do ##class(OcuTalon.Bridge.Msg.Request).%DeleteId(id)
		If kind = "reply" Do ##class(OcuTalon.Bridge.Msg.Reply).%DeleteId(id)
		If kind = "decision" Do ##class(OcuTalon.Bridge.Data.Decision).%DeleteId(id)
		If kind = "case" Do ##class(OcuTalon.Eval.Data.CaseResult).%DeleteId(id)
	}
	Set ..Made = ""
	If ..Folder '= "" Do ##class(%File).RemoveDirectoryTree(..Folder)
	If ..TempFile '= "" Do ##class(%File).Delete(..TempFile)
	Set ..TempFile = ""
	Quit $$$OK
}

/// The marker of a reply: distinct, and not a part of any name that a CHK line holds.
ClassMethod Marker() As %String [ Private ]
{
	Quit "zzmark"_##class(OcuTalon.Bridge.Ids).NewRef()
}

/// The request whose input is the pack of Test.Watch.Payload that lists a setting change, as the diagnose request carries it.
ClassMethod NewRequest(kind As %String, ref As %String, retryOf As %String = "") As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = "untrusted"
	Set request.ItemId = "zzcapture"
	Set request.OwnerRef = "eval"
	Set request.DecisionRef = ref
	Set request.RetryOf = retryOf
	Set request.Input = ##class(OcuTalon.Watch.EvidencePack).Input($ClassMethod(..#PAYLOAD, "RollbackPack"))
	Quit request
}

/// Saves a fallback Decision row of the kind and reason, and gives its Ref.
Method SeedDecision(kind As %String, reason As %String = "invalid") As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row = ##class(OcuTalon.Bridge.Data.Decision).%New()
	Set row.Ref = ref
	Set row.Kind = kind
	Set row.ItemId = ref
	Set row.OwnerRef = "eval"
	Set row.Outcome = "tellnow"
	Set row.Fallback = 1
	Set row.FallbackReason = reason
	Set row.RecordedAt = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set sc = row.%Save()
	Do $$$AssertStatusOK(sc, "a fallback decision is seeded")
	Set ..Made = ..Made _ $ListBuild("decision|"_row.%Id())
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ ref
	Quit ref
}

/// Seeds the request of one attempt of the decision: the Request body and its header (to the runner). Gives the header's id, which the answer links to.
Method SeedRequest(ref As %String, kind As %String, runner As %String, retryOf As %String = "") As %String
{
	Set request = ..NewRequest(kind, ref, retryOf)
	$$$ThrowOnError(request.%Save())
	Set ..Made = ..Made _ $ListBuild("request|"_request.%Id())
	Set out = ##class(Ens.MessageHeader).%New()
	Set out.SourceConfigName = "Decide"
	Set out.TargetConfigName = runner
	Set out.Type = 1
	Set out.Status = 9
	Set out.MessageBodyClassName = "OcuTalon.Bridge.Msg.Request"
	Set out.MessageBodyId = request.%Id()
	Set out.TimeCreated = ##class(OcuTalon.Bridge.Time).NowUtc()
	$$$ThrowOnError(out.%Save())
	Set ..Made = ..Made _ $ListBuild("header|"_out.%Id())
	Quit out.%Id()
}

/// Seeds the answer to the request header: the Reply body and its response header (linked by CorrespondingMessageId).
Method SeedAnswer(requestHeader As %String, runner As %String, text As %String, failure As %String = "")
{
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = text
	Set reply.FailureText = failure
	Set reply.FinishReason = $Select(failure = "": "end_turn", 1: "")
	$$$ThrowOnError(reply.%Save())
	Set ..Made = ..Made _ $ListBuild("reply|"_reply.%Id())
	Set back = ##class(Ens.MessageHeader).%New()
	Set back.SourceConfigName = runner
	Set back.TargetConfigName = "Decide"
	Set back.Type = 2
	Set back.Status = 9
	Set back.CorrespondingMessageId = requestHeader
	Set back.MessageBodyClassName = "OcuTalon.Bridge.Msg.Reply"
	Set back.MessageBodyId = reply.%Id()
	Set back.TimeCreated = ##class(OcuTalon.Bridge.Time).NowUtc()
	$$$ThrowOnError(back.%Save())
	Set ..Made = ..Made _ $ListBuild("header|"_back.%Id())
}

/// Seeds one attempt of the decision: the request and its answer.
Method SeedReply(ref As %String, kind As %String, runner As %String, text As %String, failure As %String = "", retryOf As %String = "")
{
	Do ..SeedAnswer(..SeedRequest(ref, kind, runner, retryOf), runner, text, failure)
}

/// Seeds every kind of fallback that the tool tells apart (see the class description) and keeps each one's expectation in the array expected(ref, attempt) = $ListBuild(text, marker, runner, rule, field)
/// and the counts in count(rule).
Method SeedAll(Output expected, Output count) [ Private ]
{
	Kill expected, count
	Set pairs = $ListFromString($ClassMethod(..#PAYLOAD, "RuleTags"), ",")
	Set position = 0
	While $ListNext(pairs, position, pair) {
		Set tag = $Piece(pair, ":", 1)
		Set field = $Piece(pair, ":", 2)
		If (tag = "cause-blank") || (tag = "outcome-not-act") || (tag = "confidence-missing") Continue
		Set marker = ..Marker()
		Set reply = $ClassMethod(..#PAYLOAD, "RuleReply", tag)
		Do reply.evidence.%Push(marker)
		Set ref = ..SeedDecision("diagnose")
		Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, reply.%ToJSON())
		Set expected(ref, 1) = $ListBuild(reply.%ToJSON(), marker, ..#DIAGNOSIS, tag, field, "check")
		Set count(tag) = $Get(count(tag)) + 1
	}
	// A second attempt: the first runner's reply and the retry runner's, each with its own rule, in one decision that belongs to a case.
	Set ref = ..SeedDecision("diagnose")
	Set first = $ClassMethod(..#PAYLOAD, "RuleReply", "cause-blank")
	Set marker = ..Marker()
	Do first.evidence.%Push(marker)
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, first.%ToJSON())
	Set expected(ref, 1) = $ListBuild(first.%ToJSON(), marker, ..#DIAGNOSIS, "cause-blank", "cause", "check")
	Set second = $ClassMethod(..#PAYLOAD, "RuleReply", "outcome-not-act")
	Set marker = ..Marker()
	Do second.evidence.%Push(marker)
	Do ..SeedReply(ref, "diagnose", ..#RETRY, second.%ToJSON(), , ..#DIAGNOSIS)
	Set expected(ref, 2) = $ListBuild(second.%ToJSON(), marker, ..#RETRY, "outcome-not-act", "outcome", "check")
	Set count("cause-blank") = 1
	Set count("outcome-not-act") = 1
	Set case = ##class(OcuTalon.Eval.Data.CaseResult).%New()
	Set case.RunRef = "zzcaptureRun"
	Set case.CaseName = "zz-capture-case"
	Set case.DecisionRef = ref
	Set case.State = "decided"
	$$$ThrowOnError(case.%Save())
	Set ..Made = ..Made _ $ListBuild("case|"_case.%Id())
	// A triage reply with no confidence: the parent's rule, against the triage runner's own reply class.
	Set marker = ..Marker()
	Set triage = {"outcome": "act", "reasons": [("Checked "_marker)]}
	Set ref = ..SeedDecision("decide")
	Do ..SeedReply(ref, "decide", ..#TRIAGE, triage.%ToJSON())
	Set expected(ref, 1) = $ListBuild(triage.%ToJSON(), marker, ..#TRIAGE, "confidence-missing", "confidence", "check")
	Set count("confidence-missing") = $Get(count("confidence-missing")) + 1
	// A reply that passes the check now.
	Set marker = ..Marker()
	Set usable = $ClassMethod(..#PAYLOAD, "Usable")
	Do usable.evidence.%Push(marker)
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, usable.%ToJSON())
	Set expected(ref, 1) = $ListBuild(usable.%ToJSON(), marker, ..#DIAGNOSIS, "passes the check", "", "")
	Set count("passes the check") = 1
	// A diagnose reply with no confidence: the parent's rule that a diagnosis never meets (DW-1421 C5), so it passes the check.
	Set marker = ..Marker()
	Set absent = $ClassMethod(..#PAYLOAD, "RuleReply", "confidence-missing")
	Do absent.evidence.%Push(marker)
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, absent.%ToJSON())
	Set expected(ref, 1) = $ListBuild(absent.%ToJSON(), marker, ..#DIAGNOSIS, "passes the check", "", "")
	Set count("passes the check") = $Get(count("passes the check")) + 1
	// A failure reply: no text, a failure text.
	Set marker = ..Marker()
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, "", "The call failed "_marker)
	Set expected(ref, 1) = $ListBuild("", marker, ..#DIAGNOSIS, "no reply text", "", "")
	Set count("no reply text") = 1
	// A reply with a field that the class does not have: the field's name is the marker, and is never in a CHK line.
	Set marker = ..Marker()
	Set odd = $ClassMethod(..#PAYLOAD, "Usable")
	Do odd.%Set(marker, 1)
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, odd.%ToJSON())
	Set expected(ref, 1) = $ListBuild(odd.%ToJSON(), marker, ..#DIAGNOSIS, "unexpected-field", "", "check")
	Set count("unexpected-field") = 1
	// A reply that is not JSON, and begins with its marker (the first characters of a file's text).
	Set marker = ..Marker()
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, marker_" is not JSON")
	Set expected(ref, 1) = $ListBuild(marker_" is not JSON", marker, ..#DIAGNOSIS, "reply-unreadable", "", "check")
	Set count("reply-unreadable") = 1
	// A decision that has no reply in the store.
	Set ref = ..SeedDecision("diagnose", "timer")
	Set expected(ref, 0) = ""
	Set count("no reply") = 1
	// An elementAtFault over the limit: an import-type refusal, whose field is the JSON name of the compiled property that the part names.
	Set marker = ..Marker()
	Set long = $ClassMethod(..#PAYLOAD, "Usable")
	Set long.elementAtFault = $Extract(marker_$Translate($Justify("", 129), " ", "e"), 1, 129)
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, long.%ToJSON())
	Set expected(ref, 1) = $ListBuild(long.%ToJSON(), marker, ..#DIAGNOSIS, "element-at-fault-too-long", "elementAtFault", "check")
	Set count("element-at-fault-too-long") = 1
	// An evidence element over the limit: cut by the import, so the reply passes the check now (element 2, after the pack's own).
	Set marker = ..Marker()
	Set cutReply = $ClassMethod(..#PAYLOAD, "Usable")
	Do cutReply.evidence.%Push($Extract(marker_$Translate($Justify("", 129), " ", "e"), 1, 129))
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, cutReply.%ToJSON())
	Set expected(ref, 1) = $ListBuild(cutReply.%ToJSON(), marker, ..#DIAGNOSIS, "passes the check", "", "")
	Set count("passes the check") = $Get(count("passes the check")) + 1
	// A wrongly typed reasons: an import error that names the property, with no length.
	Set marker = ..Marker()
	Set typed = $ClassMethod(..#PAYLOAD, "Usable")
	Set typed.reasons = marker
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, typed.%ToJSON())
	Set expected(ref, 1) = $ListBuild(typed.%ToJSON(), marker, ..#DIAGNOSIS, "ERROR #9406 on Reasons", "reasons", "check")
	Set count("ERROR #9406 on Reasons") = 1
	// A reply that is valid until the filter blanks its cause: the check after the filter refuses it.
	Set marker = ..Marker()
	Set blanked = $ClassMethod(..#PAYLOAD, "Usable")
	Set blanked.cause = "No problems."
	Do blanked.evidence.%Push(marker)
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, blanked.%ToJSON())
	Set expected(ref, 1) = $ListBuild(blanked.%ToJSON(), marker, ..#DIAGNOSIS, "cause-blank", "cause", "after the filter")
	Set count("cause-blank") = $Get(count("cause-blank")) + 1
	// A reply whose every reason the filter blanks: no reason is left.
	Set marker = ..Marker()
	Set emptied = $ClassMethod(..#PAYLOAD, "Usable")
	Do emptied.reasons.%Set(0, "No issues.")
	Do emptied.evidence.%Push(marker)
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, emptied.%ToJSON())
	Set expected(ref, 1) = $ListBuild(emptied.%ToJSON(), marker, ..#DIAGNOSIS, "no reason left after the filter", "", "no reason left after the filter")
	Set count("no reason left after the filter") = 1
	// A fallback whose reason is not invalid, with a reply that would fail the check: it is not re-checked.
	Set marker = ..Marker()
	Set cut = $ClassMethod(..#PAYLOAD, "RuleReply", "reasons-blank")
	Do cut.evidence.%Push(marker)
	Set ref = ..SeedDecision("diagnose", "cut_off")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, cut.%ToJSON())
	Set expected(ref, 1) = $ListBuild(cut.%ToJSON(), marker, ..#DIAGNOSIS, "passes the check", "", "")
	Set count("passes the check") = $Get(count("passes the check")) + 1
}

/// The text of the file.
ClassMethod FileText(path As %String) As %String [ Private ]
{
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set stream.Filename = path
	Set stream.TranslateTable = "UTF8"
	Quit stream.Read(10000000)
}

/// The names of the *.json files of the folder.
ClassMethod Files(folder As %String) As %List [ Private ]
{
	Set list = ""
	Set files = ##class(%ResultSet).%New("%File:FileSet")
	Do files.Execute(folder, "*.json")
	While files.Next() {
		Set list = list _ $ListBuild(##class(%File).GetFilename(files.Get("Name")))
	}
	Quit list
}

Method TestOneReplyPerRule()
{
	Do ..SeedAll(.expected, .count)
	Set sc = $ClassMethod(..#TOOL, "Run", ..Folder, ..Refs, .summary)
	Do $$$AssertStatusOK(sc, "the capture runs")
	Do $$$AssertEquals(summary.decisions_"|"_summary.decide_"|"_summary.diagnose_"|"_summary.replies_"|"_summary.noReply, "33|1|32|33|1", "33 decisions (1 decide, 32 diagnose), 33 replies and one decision with no reply")
	Do $$$AssertEquals(summary.reasons.%Get("invalid")_"|"_summary.reasons.%Get("timer")_"|"_summary.reasons.%Get("cut_off"), "31|1|1", "the fallback reasons are counted")
	Set found = ""
	Set iterator = summary.rules.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set found(entry.rule) = entry.count_"|"_entry.field
	}
	Set rule = ""
	For {
		Set rule = $Order(count(rule))
		If rule = "" Quit
		Do $$$AssertEquals($Piece($Get(found(rule)), "|", 1), count(rule), "the rule "_rule_" is counted "_count(rule))
	}
	Do $$$AssertEquals(summary.rules.%Size(), ..Count(.count), "and the summary names no other rule")
	Set pairs = $ListFromString($ClassMethod(..#PAYLOAD, "RuleTags"), ",")
	Set position = 0
	While $ListNext(pairs, position, pair) {
		Do $$$AssertEquals($Piece($Get(found($Piece(pair, ":", 1))), "|", 2), $Piece(pair, ":", 2), $Piece(pair, ":", 1)_": the field is "_$Piece(pair, ":", 2))
	}
	Set cases = ""
	Set iterator = summary.cases.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set cases = cases _ $ListBuild(entry.case_"/"_entry.rule_"/"_entry.count)
	}
	Do $$$AssertEquals($ListToString(cases, ";"), "zz-capture-case/cause-blank/1;zz-capture-case/outcome-not-act/1", "the case of the second-attempt decision is counted for each of its rules")
	Set names = ..Files(..Folder)
	Do $$$AssertEquals($ListLength(names), 34, "34 files: one for each reply and summary.json")
	Do $$$AssertEquals(summary.files, 34, "and the summary says so")
	Set ref = ""
	For {
		Set ref = $Order(expected(ref))
		If ref = "" Quit
		Set attempt = ""
		For {
			Set attempt = $Order(expected(ref, attempt))
			If attempt = "" Quit
			If attempt = 0 Continue
			Set name = ""
			Set position = 0
			While $ListNext(names, position, one) {
				If ($Piece(one, "-", 2, $Length(one, "-") - 1) = ref) && ($Piece($Piece(one, ".", 1), "-", $Length(one, "-")) = attempt) Set name = one
			}
			Do $$$AssertTrue(name '= "", "a file for "_ref_" attempt "_attempt)
			If name = "" Continue
			Set file = {}.%FromJSON(..FileText(..Folder_name))
			Set want = expected(ref, attempt)
			Do $$$AssertEquals(file.text, $List(want, 1), "the file's text is the seeded reply: "_$List(want, 4))
			Do $$$AssertEquals(file.runner_"|"_file.attempt_"|"_file.stage_"|"_file.rule_"|"_file.field_"|"_file.decisionRef, $List(want, 3)_"|"_attempt_"|"_$List(want, 6)_"|"_$List(want, 4)_"|"_$List(want, 5)_"|"_ref, "its runner, attempt, stage, rule, field and decision: "_$List(want, 4))
		}
	}
	Do $$$AssertTrue($ListFind(names, "summary.json") > 0, "summary.json is written")
	Set written = {}.%FromJSON(..FileText(..Folder_"summary.json"))
	Do $$$AssertEquals(written.files_"|"_written.replies_"|"_written.decisions, "34|33|33", "and it holds the counts of the folder, itself among its files")
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set stream.Filename = ..Folder_"zz-notes.json"
	Do stream.Write("{}")
	Do $$$AssertStatusOK(stream.%Save(), "a file of another name is put into the folder")
	Set again = $ClassMethod(..#TOOL, "Run", ..Folder, $Piece(..Refs, ",", 1), .summary)
	Do $$$AssertStatusOK(again, "a second run, over one decision, runs")
	Set names = ..Files(..Folder)
	Do $$$AssertEquals($ListLength(names), 3, "it replaces the files of the first run (its one reply and summary.json are left) and keeps the file of another name")
	Do $$$AssertTrue($ListFind(names, "zz-notes.json") > 0, "the file of another name is kept")
}

/// DW-1421 C1 (AC 8): RuleOf and FieldOf of the parts that a refusal gives.
Method TestRuleNames()
{
	Set parts = $ListBuild("ERROR #7201 rule evidence-too-long", "ERROR #5001 rule cause-blank", "ElementAtFault: 129 > 128", "ERROR #9404: an unexpected property", "ERROR #7201 rule Evidence 2", "ERROR #7201 rule element-at-fault-too-long", "ERROR #9404 rule unexpected-field", "ERROR #5035 rule reply-unreadable")
	Set rules = $ListBuild("evidence-too-long", "cause-blank", "ElementAtFault: 129 > 128", "ERROR #9404: an unexpected property", "ERROR #7201 rule Evidence 2", "element-at-fault-too-long", "unexpected-field", "reply-unreadable")
	Set fields = $ListBuild("evidence", "cause", "elementAtFault", "", "", "elementAtFault", "", "")
	For i = 1:1:$ListLength(parts) {
		Set rule = $ClassMethod(..#TOOL, "RuleOf", $List(parts, i))
		Do $$$AssertEquals(rule, $List(rules, i), "the rule of "_$List(parts, i))
		Do $$$AssertEquals($ClassMethod(..#TOOL, "FieldOf", $List(parts, i), rule, ..#CLASS), $List(fields, i), "and its field is "_$Select($List(fields, i) = "": "none", 1: $List(fields, i)))
	}
}

/// DW-1421 C1 (QA): Run counts a reply whose Evidence refusal is the length tag under the rule evidence-too-long and the field evidence, in the summary and in the reply's file,
/// and its CHK lines hold no text of the reply. The reply's second evidence element is a JSON number of 129 digits, which the cut leaves (it is not a string) and the import
/// refuses for its length.
Method TestLengthTagCounted()
{
	Set marker = ..Marker()
	Set digits = $Translate($Justify("", 129), " ", "7")
	Set reply = $ClassMethod(..#PAYLOAD, "Usable")
	Set reply.evidence = [(marker), "x"]
	Set text = $Replace(reply.%ToJSON(), """"_marker_""",""x""", """"_marker_""","_digits)
	Do $$$AssertTrue(text [ digits, "the reply holds the number of 129 digits")
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, text)
	Set sc = $ClassMethod(..#TOOL, "Run", ..Folder, ..Refs, .summary)
	Do $$$AssertStatusOK(sc, "the capture runs")
	Set found = ""
	Set iterator = summary.rules.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set found = found_$Select(found = "": "", 1: ";")_entry.rule_"|"_entry.field_"|"_entry.count
	}
	Do $$$AssertEquals(found, "evidence-too-long|evidence|1", "the summary counts the reply once under evidence-too-long, field evidence")
	Set names = ..Files(..Folder)
	Set name = ""
	Set position = 0
	While $ListNext(names, position, one) {
		If one '= "summary.json" Set name = one
	}
	Do $$$AssertTrue(name '= "", "the reply has its file")
	If name = "" Quit
	Set file = {}.%FromJSON(..FileText(..Folder_name))
	Do $$$AssertEquals(file.stage_"|"_file.rule_"|"_file.field_"|"_file.problem, "check|evidence-too-long|evidence|The reply check failed: the reply is not one JSON object that "_..#CLASS_" accepts: ERROR #7201 rule evidence-too-long", "the file names the stage, the rule, the field and the problem")
	Set lines = $ClassMethod(..#TOOL, "Lines", summary)
	Do $$$AssertTrue((lines '[ marker) && (lines '[ $Extract(digits, 1, 10)), "the CHK lines hold no text of the reply")
	Do $$$AssertTrue(lines [ "evidence-too-long", "and name the rule")
}

Method TestNoFallbackWritesNoFile()
{
	Set sc = $ClassMethod(..#TOOL, "Run", ..Folder, "zzNoSuchRef", .summary)
	Do $$$AssertStatusOK(sc, "the capture runs")
	Do $$$AssertEquals(summary.decisions_"|"_summary.replies_"|"_summary.files, "0|0|0", "no decision, no reply and no file are counted")
	Do $$$AssertEquals($ListLength(..Files(..Folder)), 0, "and no file is written, summary.json included")
	Do $$$AssertEquals($ClassMethod(..#TOOL, "Lines", summary), "CHK|decisions|0|0|0|0|0", "the lines are the count line only")
	Set sc = $ClassMethod(..#TOOL, "Run", "", "zzNoSuchRef", .summary)
	Do $$$AssertTrue($$$ISERR(sc), "an empty folder is an error, not the process's own directory")
}

Method TestUncheckableReplyIsCounted()
{
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", "zzNoSuchRunner", ..Marker()_" is not JSON")
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, ..Marker()_" is not JSON")
	Set sc = $ClassMethod(..#TOOL, "Run", ..Folder, ..Refs, .summary)
	Do $$$AssertStatusOK(sc, "the capture runs")
	Kill found
	Set iterator = summary.rules.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set found(entry.rule) = entry.count
	}
	Do $$$AssertEquals($Get(found("no check")), 1, "the reply of a runner with no reply class is counted under no check")
	Do $$$AssertEquals($Get(found("reply-unreadable")), 1, "and the other reply of the run is judged")
	Do $$$AssertEquals(summary.replies_"|"_summary.files, "2|3", "each reply has its file, and summary.json is written")
}

/// The number of rules in the array count.
ClassMethod Count(ByRef count) As %Integer [ Private ]
{
	Set n = 0
	Set rule = ""
	For {
		Set rule = $Order(count(rule))
		If rule = "" Quit
		Set n = n + 1
	}
	Quit n
}

Method TestLinesHoldNoReplyText()
{
	Do ..SeedAll(.expected, .count)
	Set sc = $ClassMethod(..#TOOL, "Run", ..Folder, ..Refs, .summary)
	Do $$$AssertStatusOK(sc, "the capture runs")
	Set lines = $ClassMethod(..#TOOL, "Lines", summary)
	Do $$$AssertTrue(lines [ "CHK|decisions|33|1|32|33|34", "the lines hold the counts")
	Set files = ""
	Set names = ..Files(..Folder)
	Set position = 0
	While $ListNext(names, position, one) {
		Set files = files _ ..FileText(..Folder_one)
	}
	Set ref = ""
	For {
		Set ref = $Order(expected(ref))
		If ref = "" Quit
		Set attempt = ""
		For {
			Set attempt = $Order(expected(ref, attempt))
			If attempt = "" Quit
			If attempt = 0 Continue
			Set marker = $List(expected(ref, attempt), 2)
			Do $$$AssertTrue(lines '[ marker, "the lines hold no marker of "_$List(expected(ref, attempt), 4))
			Set clean = 1
			For start = 1:1:$Length(marker) - 9 {
				If lines [ $Extract(marker, start, start + 9) Set clean = 0
			}
			Do $$$AssertTrue(clean, "nor any 10 characters of it: "_$List(expected(ref, attempt), 4))
			Do $$$AssertTrue(files [ marker, "while the files hold it: "_$List(expected(ref, attempt), 4))
		}
	}
}

/// The counts that a record, a log or a send of the test's own process would change: the event log rows of this job, the Decision and Usage rows, and the message headers of the bridge's messages
/// and the headers that name no body (the production's own background work, which runs in other jobs, is not counted).
ClassMethod Snap() As %String [ Private ]
{
	Quit "log="_..One("SELECT COUNT(*) FROM Ens_Util.Log WHERE Job = ?", $Job)_";decision="_..One("SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision")_";usage="_..One("SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Usage")_";headers="_..One("SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName %STARTSWITH 'OcuTalon.Bridge.Msg.' OR MessageBodyClassName IS NULL OR MessageBodyClassName = ''")_";"
}

/// The counts of Rows (which = "Rows") or of Snap, as "name=count;" pairs.
ClassMethod Counts(which As %String) As %String [ Private ]
{
	Quit $Select(which = "Rows": ..Rows(), 1: ..Snap())
}

/// The names of the pairs of after whose count is not the one in before.
ClassMethod Moved(before As %String, after As %String) As %List [ Private ]
{
	Set moved = ""
	For i = 1:1:$Length(after, ";") {
		Set pair = $Piece(after, ";", i)
		If (pair '= "") && ((";"_before) '[ (";"_pair_";")) Set moved = moved _ $ListBuild($Piece(pair, "=", 1))
	}
	Quit moved
}

/// The names of the counts (which: "Rows" or "Snap") that a call of the class method with the arguments changes in each of up to three tries, comma-separated; "" when one try
/// changes none. A write of the call changes its count in every try; the production's background work in other jobs that lands in one try is not in every one.
ClassMethod Writes(which As %String, class As %String, method As %String, args...) As %String [ Private ]
{
	Set common = ""
	For try = 1:1:3 {
		Set before = ..Counts(which)
		Do $ClassMethod(class, method, args...)
		Set moved = ..Moved(before, ..Counts(which))
		If try > 1 {
			Set kept = ""
			Set position = 0
			While $ListNext(moved, position, name) {
				If $ListFind(common, name) Set kept = kept _ $ListBuild(name)
			}
			Set moved = kept
		}
		Set common = moved
		If common = "" Quit
	}
	Quit $ListToString(common, ",")
}

ClassMethod One(sql As %String, arg As %String = "") As %String [ Private ]
{
	Set result = $Select(arg = "": ##class(%SQL.Statement).%ExecDirect(, sql), 1: ##class(%SQL.Statement).%ExecDirect(, sql, arg))
	Quit $Select(result.%Next(): +result.%GetData(1), 1: "?")
}

Method TestRecordsAndLogsNothing()
{
	Do ..SeedAll(.expected, .count)
	Set sc = $ClassMethod(..#TOOL, "Run", ..Folder, ..Refs, .summary)
	Do $$$AssertStatusOK(sc, "the capture runs")
	Do $$$AssertTrue(summary.replies > 20, "and it did capture replies")
	Do $$$AssertEquals(..Writes("Snap", ..#TOOL, "Run", ..Folder, ..Refs), "", "the event log, the Decision and Usage rows and the message headers are as they were")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Source).Text(..#TOOL, .text), "the tool has source")
	For name = "$$$LOG", "Ens.Util.Log", "%AI", "Chat", "SendRequest", "Conclude", "Ens.Director", ..#TRIAGE, ..#DIAGNOSIS, "ChatAgent" {
		Do $$$AssertEquals($ListLength(##class(OcuTalon.Test.Bridge.Source).Lines(text, name, 1)), 0, "no code line of the tool names "_name)
	}
}

Method TestRecheckIsSilent()
{
	Set request = ..NewRequest("diagnose", "")
	Set long = $ClassMethod(..#PAYLOAD, "Usable")
	Set long.elementAtFault = $Translate($Justify("", 129), " ", "e")
	Set cut = $ClassMethod(..#PAYLOAD, "Usable")
	Do cut.evidence.%Push($Translate($Justify("", 129), " ", "e"))
	Do cut.evidence.%Push("h3")
	Do cut.evidence.%Push($Translate($Justify("", 200), " ", "e"))
	Set emptied = $ClassMethod(..#PAYLOAD, "Usable")
	Do emptied.reasons.%Set(0, "No issues.")
	Set blanked = $ClassMethod(..#PAYLOAD, "Usable")
	Set blanked.cause = "No problems."
	Set usable = $ClassMethod(..#PAYLOAD, "Usable")
	Set odd = $ClassMethod(..#PAYLOAD, "Usable")
	Do odd.%Set("zzextra", 1)
	For label = "over the limit", "an evidence element cut", "no reason left", "invalid after the filter", "an unknown field", "a usable reply" {
		Set reply = $Case(label, "over the limit": long, "an evidence element cut": cut, "no reason left": emptied, "invalid after the filter": blanked, "an unknown field": odd, : usable)
		Set valid = $ClassMethod(..#DECIDE, "Recheck", request, reply.%ToJSON(), ..#CLASS, "OcuTalon.Checks.ReplyGuard", .problem)
		Do $$$AssertEquals(valid, $Case(label, "a usable reply": 1, "an evidence element cut": 1, : 0), label_": the verdict")
		Do $$$AssertEquals($Select(valid: problem = "", 1: problem '= ""), 1, label_": and the problem")
		Do $$$AssertEquals(..Writes("Snap", ..#DECIDE, "Recheck", request, reply.%ToJSON(), ..#CLASS, "OcuTalon.Checks.ReplyGuard"), "", label_": no event is logged, no Decision or Usage row is saved and no message is sent")
	}
}

/// 1 when a code line of the text names Recheck of the Decide process on a line: ##class(OcuTalon.Bridge.Process.Decide).Recheck, or the class name and Recheck on one line.
ClassMethod NamesDecideRecheck(text As %String) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Test.Bridge.Source).Matches(text, "process\.decide.*recheck|recheck.*process\.decide")
}

/// The non-test OcuTalon classes of the packages, other than the allowed ones, whose code lines match the pattern, as " Class1 Class2"; scanned is the number of classes read.
ClassMethod Offenders(prefixes As %String, pattern As %String, allowed As %String, Output scanned As %Integer) As %String [ Private ]
{
	Set scanned = 0
	Set offending = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'OcuTalon.' AND NOT Name %STARTSWITH 'OcuTalon.Test.'")
	While result.%Next() {
		Set class = result.%GetData(1)
		If $ListFind($ListFromString(allowed), class) Continue
		Set in = (prefixes = "")
		For i = 1:1:$Length(prefixes, ",") If ($Piece(prefixes, ",", i) '= "") && ($Extract(class, 1, $Length($Piece(prefixes, ",", i))) = $Piece(prefixes, ",", i)) Set in = 1
		If 'in Continue
		If $$$ISERR(##class(OcuTalon.Test.Bridge.Source).Text(class, .text)) Continue
		Set scanned = scanned + 1
		If ##class(OcuTalon.Test.Bridge.Source).Matches(text, pattern) Set offending = offending _ " " _ class
	}
	Quit offending
}

Method TestRecheckIsUnreachable()
{
	Set source = "OcuTalon.Test.Bridge.Source"
	Set tab = $Char(9)
	Set pattern = "\brecheck\b"
	Do $$$AssertTrue($ClassMethod(source, "Matches", tab_"Set ok = ##class(OcuTalon.Bridge.Process.Decide).Recheck(r, t, c, f, .p)", pattern), "the scanner flags a call of Recheck")
	Do $$$AssertTrue($ClassMethod(source, "Matches", tab_"Set ok = $ClassMethod(""OcuTalon.Bridge.Process.Decide"", ""Recheck"", r)", pattern), "and the call by name")
	Do $$$AssertTrue('$ClassMethod(source, "Matches", "/// Recheck is for tools"_$Char(10)_tab_"// Do ..Recheck()"_$Char(10)_tab_"Set x = rechecked", pattern), "and passes a comment line and a look-alike")
	Do $$$AssertTrue(..NamesDecideRecheck(tab_"Set ok = ##class(OcuTalon.Bridge.Process.Decide).Recheck(r, t, c, f, .p)"), "the Decide scanner flags the call")
	Do $$$AssertTrue('..NamesDecideRecheck(tab_"Do ##class(OcuTalon.Fix.Kind).Recheck(k)"), "and passes the Recheck of a fix kind")
	// The REST, channel, conversation, tool, agent and MCP code, the only ways into OcuTalon from outside, never name Recheck at all.
	Set offending = ..Offenders("OcuTalon.Web.,OcuTalon.Channel.,OcuTalon.Core.,OcuTalon.Tools.,OcuTalon.Agent.,OcuTalon.Mcp.", pattern, "", .scanned)
	Do $$$AssertTrue(scanned > 30, "the scan read the source of the web, channel, core, tool, agent and MCP classes: "_scanned)
	Do $$$AssertEquals(offending, "", "none of them names Recheck")
	// No class but Decide itself names Recheck of Decide.
	Set offending = ..Offenders("", "process\.decide.*recheck|recheck.*process\.decide", "OcuTalon.Bridge.Process.Decide", .scanned)
	Do $$$AssertTrue(scanned > 100, "the scan read the source of the OcuTalon classes: "_scanned)
	Do $$$AssertEquals(offending, "", "no class but Decide names Recheck of Decide")
}

/// The name of the file of the decision's attempt in the folder's names, or "".
ClassMethod Named(names As %List, ref As %String, attempt As %Integer) As %String [ Private ]
{
	Set position = 0
	While $ListNext(names, position, one) {
		If ($Piece(one, "-", 2, $Length(one, "-") - 1) = ref) && ($Piece($Piece(one, ".", 1), "-", $Length(one, "-")) = attempt) Quit
		Set one = ""
	}
	Quit one
}

/// The attempts of a decision are numbered by their request headers, in header order, whether or not an attempt has an answer in the store, and not by the order of the answers.
///   - the first request has no answer and the retry's reply is the second attempt (file "-2", the retry runner);
///   - the first attempt's answer and a retry request with no answer is one reply, attempt 1;
///   - two requests with no answer count as a decision with no reply;
///   - the first attempt's answer that is stored after the retry's reply is still attempt 1.
Method TestAttemptsAreNumberedByRequest()
{
	Set unanswered = ..SeedDecision("diagnose")
	Do ..SeedRequest(unanswered, "diagnose", ..#DIAGNOSIS)
	Do ..SeedReply(unanswered, "diagnose", ..#RETRY, $ClassMethod(..#PAYLOAD, "RuleReply", "reasons-blank").%ToJSON(), , ..#DIAGNOSIS)
	Set retryless = ..SeedDecision("diagnose")
	Do ..SeedReply(retryless, "diagnose", ..#DIAGNOSIS, $ClassMethod(..#PAYLOAD, "RuleReply", "outcome-not-act").%ToJSON())
	Do ..SeedRequest(retryless, "diagnose", ..#RETRY, ..#DIAGNOSIS)
	Set silent = ..SeedDecision("diagnose")
	Do ..SeedRequest(silent, "diagnose", ..#DIAGNOSIS)
	Do ..SeedRequest(silent, "diagnose", ..#RETRY, ..#DIAGNOSIS)
	Set late = ..SeedDecision("diagnose")
	Set firstHeader = ..SeedRequest(late, "diagnose", ..#DIAGNOSIS)
	Set retryHeader = ..SeedRequest(late, "diagnose", ..#RETRY, ..#DIAGNOSIS)
	Do ..SeedAnswer(retryHeader, ..#RETRY, $ClassMethod(..#PAYLOAD, "RuleReply", "item-noun-blank").%ToJSON())
	Do ..SeedAnswer(firstHeader, ..#DIAGNOSIS, $ClassMethod(..#PAYLOAD, "RuleReply", "cause-blank").%ToJSON())
	Set sc = $ClassMethod(..#TOOL, "Run", ..Folder, ..Refs, .summary)
	Do $$$AssertStatusOK(sc, "the capture runs")
	Do $$$AssertEquals(summary.decisions_"|"_summary.replies_"|"_summary.noReply_"|"_summary.files, "4|4|1|5", "4 decisions, 4 replies, one decision with no reply, 4 files and summary.json")
	Set names = ..Files(..Folder)
	Do $$$AssertEquals($ListLength(names), 5, "5 files in the folder")
	For want = $ListBuild(unanswered, 2, ..#RETRY, "reasons-blank"), $ListBuild(retryless, 1, ..#DIAGNOSIS, "outcome-not-act"), $ListBuild(late, 1, ..#DIAGNOSIS, "cause-blank"), $ListBuild(late, 2, ..#RETRY, "item-noun-blank") {
		Set ref = $List(want, 1)
		Set attempt = $List(want, 2)
		Set name = ..Named(names, ref, attempt)
		Do $$$AssertTrue(name '= "", "a file for attempt "_attempt_" of the decision with the rule "_$List(want, 4))
		If name = "" Continue
		Set file = {}.%FromJSON(..FileText(..Folder_name))
		Do $$$AssertEquals(file.attempt_"|"_file.runner_"|"_file.rule, attempt_"|"_$List(want, 3)_"|"_$List(want, 4), "attempt "_attempt_" is the reply of "_$List(want, 3)_" with the rule "_$List(want, 4))
	}
	Do $$$AssertEquals(..Named(names, unanswered, 1), "", "the first attempt that has no answer has no file")
	Do $$$AssertEquals(..Named(names, retryless, 2), "", "nor has a retry that has no answer")
	Do $$$AssertEquals(..Named(names, silent, 1)_..Named(names, silent, 2), "", "nor has a decision whose two requests have none")
}

/// A text with a line end, a carriage return, a tab, quotes, a back slash, a bar, a line of its own that looks like a CHK line, characters outside ASCII (and one outside the basic plane) and a rule name; label tells the text apart.
ClassMethod Hostile(label As %String) As %String [ Private ]
{
	Quit "first line "_label_$Char(10)_"CHK|file|../../evil.json"_$Char(13, 10)_"""quoted"" 'single' \ back"_$Char(9)_"tab | pipe | "_$Char(233, 252, 26085, 26412, 128512)_" ERROR #5001 rule cause-blank"
}

/// A hostile text that fits the 32 characters of a category or an outcome.
ClassMethod ShortHostile() As %String [ Private ]
{
	Quit "q"""_$Char(10)_"CHK|file|../evil"_$Char(233, 26085)
}

/// AC 6: replies that carry a line end, quotes, a bar, a fake CHK line, non-ASCII characters and the name of a rule - in every field that a reply holds, as a key, as the whole text and in the failure text - and a case name and a
/// fallback reason that carry a line end and a bar too (the tool's own values) never reach the CHK lines: every line is one ASCII CHK line of the known shapes, whose rule names are exactly the expected ones, while the files hold each reply byte for byte.
Method TestHostileRepliesStayOffStdout()
{
	Set hostile = ..Hostile("long")
	Set short = ..ShortHostile()
	Set whole = ..Hostile("whole")
	Set keyed = $ClassMethod(..#PAYLOAD, "Usable")
	Do keyed.%Set(..Hostile("key"), 1)
	Set categorised = $ClassMethod(..#PAYLOAD, "Usable")
	Set categorised.causeCategory = short
	Set reasoned = $ClassMethod(..#PAYLOAD, "Usable")
	Set reasoned.cause = ..Hostile("cause")
	Set reasoned.fixSummary = ..Hostile("summary")
	Do reasoned.reasons.%Set(0, ..Hostile("reason"))
	Set fixed = $ClassMethod(..#PAYLOAD, "Usable")
	Set fixed.fixParameters.field = ..Hostile("field")
	Set triage = {"outcome": (short), "reasons": [(hostile)], "confidence": 0.5}
	Set texts = ""
	Set expected = ""
	For one = $ListBuild(whole, "reply-unreadable", ..#DIAGNOSIS, "diagnose"), $ListBuild(keyed.%ToJSON(), "unexpected-field", ..#DIAGNOSIS, "diagnose"), $ListBuild(categorised.%ToJSON(), "cause-category-unlisted", ..#DIAGNOSIS, "diagnose"), $ListBuild(reasoned.%ToJSON(), "passes the check", ..#DIAGNOSIS, "diagnose"), $ListBuild(fixed.%ToJSON(), "fix-parameters-check", ..#DIAGNOSIS, "diagnose"), $ListBuild(triage.%ToJSON(), "outcome-unlisted", ..#TRIAGE, "decide"), $ListBuild("cause-blank", "reply-unreadable", ..#DIAGNOSIS, "diagnose") {
		Set ref = ..SeedDecision($List(one, 4))
		Do ..SeedReply(ref, $List(one, 4), $List(one, 3), $List(one, 1))
		Set texts = texts _ $ListBuild($List(one, 1))
		Set expected = expected _ $ListBuild($List(one, 2))
	}
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, "", ..Hostile("failure"))
	Set expected = expected _ $ListBuild("no reply text")
	Set ref = ..SeedDecision("diagnose", "in"_$Char(10)_"CHK|file|zzreason.json|v")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, ..Hostile("passes"))
	Set expected = expected _ $ListBuild("passes the check")
	Set case = ##class(OcuTalon.Eval.Data.CaseResult).%New()
	Set case.RunRef = "zzcaptureRun"
	Set case.CaseName = "zz"_$Char(10)_"CHK|file|zzcase.json|x"
	Set case.DecisionRef = ref
	Set case.State = "decided"
	$$$ThrowOnError(case.%Save())
	Set ..Made = ..Made _ $ListBuild("case|"_case.%Id())
	Set sc = $ClassMethod(..#TOOL, "Run", ..Folder, ..Refs, .summary)
	Do $$$AssertStatusOK(sc, "the capture runs")
	Do $$$AssertEquals(summary.decisions_"|"_summary.replies_"|"_summary.files, "9|9|10", "9 decisions, 9 replies and 10 files with summary.json")
	Set lines = $ClassMethod(..#TOOL, "Lines", summary)
	Do $$$AssertTrue($Match(lines, "[\n -~]*"), "the lines are ASCII, with line ends and no other control character")
	Set files = 0
	Set shapes = $ListBuild("decisions", 7, "reason", 4, "rule", 5, "case", 5, "file", 3)
	For i = 1:1:$Length(lines, $Char(10)) {
		Set line = $Piece(lines, $Char(10), i)
		Set kind = $Piece(line, "|", 2)
		Set at = $ListFind(shapes, kind)
		Do $$$AssertTrue(($Piece(line, "|", 1) = "CHK") && (at > 0) && ($Length(line, "|") = $List(shapes, at + 1)), "line "_i_" is one CHK line of the shape of "_kind_": "_$Select($Length(line) > 60: $Extract(line, 1, 60)_"...", 1: line))
		If kind = "file" Set files = files + 1
		If kind = "rule" Set got($Piece(line, "|", 3)) = $Get(got($Piece(line, "|", 3))) + $Piece(line, "|", 5)
	}
	Do $$$AssertEquals(files, summary.files, "one file line for each file of the folder: no line of the text or of the names adds one")
	Set position = 0
	While $ListNext(expected, position, name) {
		Set want(name) = $Get(want(name)) + 1
	}
	Set name = ""
	For {
		Set name = $Order(want(name))
		If name = "" Quit
		Do $$$AssertEquals($Get(got(name)), want(name), "the rule "_name_" is counted in the lines as often as it was seeded")
	}
	Set name = ""
	For {
		Set name = $Order(got(name))
		If name = "" Quit
		Do $$$AssertTrue($Data(want(name)), "and the rule "_name_" is one that was seeded")
	}
	For fragment = "evil", "quoted", "single", "first line", "pipe", "back", "cause-blank", "../" {
		Do $$$AssertTrue(lines '[ fragment, "the lines hold no "_fragment)
	}
	Do $$$AssertTrue((lines [ "zzcase") && (lines [ "zzreason"), "the case name and the fallback reason, which the tool takes from its own rows, are cleaned and not dropped")
	Set names = ..Files(..Folder)
	Set position = 0
	While $ListNext(names, position, one) {
		Do $$$AssertTrue($Match(one, "[A-Za-z0-9._-]+"), "the file name "_one_" is safe to copy")
	}
	Set position = 0
	Set found = 0
	While $ListNext(texts, position, text) {
		Set holds = 0
		Set position2 = 0
		While $ListNext(names, position2, one) {
			If one '= "summary.json" {
				Set file = {}.%FromJSON(..FileText(..Folder_one))
				If file.text = text Set holds = 1
			}
		}
		Do $$$AssertTrue(holds, "a file holds the reply "_$Length(text)_" characters long, byte for byte, with its line ends, quotes and non-ASCII characters")
	}
}

/// The row count of every persistent table of the product (the classes of OcuTalon outside OcuTalon.Test), and of the message headers whose body is not an OcuTalon class or that name no body (an Ens alert, for one): what a record, an alert, a
/// notice or a live event of the product would change, whichever table it went to.
ClassMethod Rows() As %String [ Private ]
{
	Set text = ""
	Set tables = ##class(%SQL.Statement).%ExecDirect(, "SELECT SqlQualifiedNameQ FROM %Dictionary.CompiledClass WHERE Name %STARTSWITH 'OcuTalon.' AND NOT Name %STARTSWITH 'OcuTalon.Test.' AND ClassType = 'persistent' AND Abstract = 0")
	While tables.%Next() {
		Set table = tables.%GetData(1)
		Set text = text _ table _ "=" _ ..One("SELECT COUNT(*) FROM " _ table) _ ";"
	}
	Quit text _ "headers=" _ ..One("SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName IS NULL OR MessageBodyClassName = '' OR NOT MessageBodyClassName %STARTSWITH 'OcuTalon.'") _ ";"
}

/// The number of entries that the product's audit writer made in the IRIS audit log since the mark (OcuTalon.Test.Bridge.AuditLog.Now) for the user of this process.
ClassMethod AuditCount(mark As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, ##class(OcuTalon.Bridge.Audit).#SOURCE, "", "", "", $Username).%Size()
}

/// The Planner's condition (saves nothing, fires nothing, logs nothing): CaptureTool.Run and Decide.Recheck add or remove no row of any persistent table of the product and no alert or other non-OcuTalon
/// message header (row counts: an update in place is the narrower tests' and the code rules' to see), and write no entry of this process's user to the IRIS audit log (the other pins count the event log of the job, Decision, Usage and the bridge's headers). A control entry, written first, shows that the audit reader sees an entry of the product's writer on this stack.
Method TestNothingIsWrittenAnywhere()
{
	Set control = ..Marker()
	Set before = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Audit).Write("Action", {"marker": (control)}, "zzcapture control"), "the control audit entry is written")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(before, "OcuTalon", "", "", control).%Size(), 1, "and the audit reader finds it, so that a count of zero means something")
	Do ..SeedAll(.expected, .count)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set sc = $ClassMethod(..#TOOL, "Run", ..Folder, ..Refs, .summary)
	Do $$$AssertStatusOK(sc, "the capture runs")
	Do $$$AssertTrue(summary.replies > 20, "and it did capture replies")
	Do $$$AssertEquals(..Writes("Rows", ..#TOOL, "Run", ..Folder, ..Refs), "", "Run: no table of the product has a row more or fewer, and no header of another body is made")
	Do $$$AssertEquals(..AuditCount(mark), 0, "Run: no audit entry is written")
	Set request = ..NewRequest("diagnose", "")
	Set long = $ClassMethod(..#PAYLOAD, "Usable")
	Do long.evidence.%Push($Translate($Justify("", 129), " ", "e"))
	Set refused = $ClassMethod(..#PAYLOAD, "Usable")
	Set refused.elementAtFault = $Translate($Justify("", 129), " ", "e")
	Set emptied = $ClassMethod(..#PAYLOAD, "Usable")
	Do emptied.reasons.%Set(0, "No issues.")
	Set blanked = $ClassMethod(..#PAYLOAD, "Usable")
	Set blanked.cause = "No problems."
	Set usable = $ClassMethod(..#PAYLOAD, "Usable")
	For label = "over the limit", "an evidence element cut", "no reason left", "invalid after the filter", "a usable reply" {
		Set reply = $Case(label, "over the limit": refused, "an evidence element cut": long, "no reason left": emptied, "invalid after the filter": blanked, : usable)
		Do $$$AssertEquals(..Writes("Rows", ..#DECIDE, "Recheck", request, reply.%ToJSON(), ..#CLASS, "OcuTalon.Checks.ReplyGuard"), "", "Recheck of "_label_": no table of the product has a row more or fewer, and no header of another body is made")
		Do $$$AssertEquals(..AuditCount(mark), 0, "Recheck of "_label_": no audit entry is written")
	}
}

}
