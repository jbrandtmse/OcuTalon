Include Ensemble

/// Tests of the capture of the fallback replies of an eval run, OcuTalon.Test.Eval.CaptureTool (DW-1421; AD-8), and of the silence of Decide.Recheck. The tests seed fallback decisions as a
/// run leaves them (a Decision row, the Request that carries its Ref, the Reply, and the request header and its response header, which are linked by CorrespondingMessageId), run the tool over
/// them only (its refs), and remove every row, header, file and folder they made (OnAfterOneTest). They need the production's runner items and their ReplyClass settings, so they run on a stack, a
/// warm one included, and no model is called.
///   - TestOneReplyPerRule (AC 5): one diagnose reply for each of the 22 rules of the reply class and its parent, a triage reply with no confidence, a reply that passes, a reply that holds no text, a
///     reply with an unknown field, a reply that is not JSON, an over-long evidence element and a mistyped reasons (import refusals, whose field is the JSON name of the compiled property),
///     a reply that is valid until the filter blanks its cause, one with no reason left after the filter, a cut_off fallback whose reply would fail the check, a decision with no reply and a second attempt on DiagnosisAgentRetry give the summary's counts (each rule once, confidence-missing, cause-blank and "passes the check" twice) with the field of each rule,
///     one file for each reply (and summary.json), and each file holds its text, attempt, runner, stage, rule and field;
///   - TestLinesHoldNoReplyText (AC 6): each seeded reply carries a distinct marker, and the CHK lines hold no marker and no 10-character part of one, while the files hold each;
///   - TestRecordsAndLogsNothing (AC 7): Run leaves the event log rows of its job, the Decision and Usage rows and the bridge's Ens message headers as they were, and the source of the tool names no logging, no AI call, no send, no
///     Conclude and no runner item;
///   - TestRecheckIsSilent (DW-1421): Decide.Recheck, for a refused reply, a usable one, one that the filter leaves with no reason and one that the filter makes invalid, changes none of those counts;
///   - TestRecheckIsUnreachable (DW-1421): no class of the REST, channel, conversation, tool, agent or MCP code names Recheck, and no class but Decide names Recheck of Decide.
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

/// Seeds one attempt of the decision: the Request body and its header (to the runner), the Reply body and its response header.
Method SeedReply(ref As %String, kind As %String, runner As %String, text As %String, failure As %String = "", retryOf As %String = "")
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
	Set back.CorrespondingMessageId = out.%Id()
	Set back.MessageBodyClassName = "OcuTalon.Bridge.Msg.Reply"
	Set back.MessageBodyId = reply.%Id()
	Set back.TimeCreated = ##class(OcuTalon.Bridge.Time).NowUtc()
	$$$ThrowOnError(back.%Save())
	Set ..Made = ..Made _ $ListBuild("header|"_back.%Id())
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
		If (tag = "cause-blank") || (tag = "outcome-not-act") Continue
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
	Set expected(ref, 1) = $ListBuild(odd.%ToJSON(), marker, ..#DIAGNOSIS, "ERROR #9404: an unexpected property", "", "check")
	Set count("ERROR #9404: an unexpected property") = 1
	// A reply that is not JSON, and begins with its marker (the first characters of a file's text).
	Set marker = ..Marker()
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, marker_" is not JSON")
	Set expected(ref, 1) = $ListBuild(marker_" is not JSON", marker, ..#DIAGNOSIS, "ERROR #5035", "", "check")
	Set count("ERROR #5035") = 1
	// A decision that has no reply in the store.
	Set ref = ..SeedDecision("diagnose", "timer")
	Set expected(ref, 0) = ""
	Set count("no reply") = 1
	// An evidence element over the limit: an import-type refusal, whose field is the JSON name of the compiled property that the part names (element 2, after the pack's own).
	Set marker = ..Marker()
	Set long = $ClassMethod(..#PAYLOAD, "Usable")
	Do long.evidence.%Push($Extract(marker_$Translate($Justify("", 129), " ", "e"), 1, 129))
	Set ref = ..SeedDecision("diagnose")
	Do ..SeedReply(ref, "diagnose", ..#DIAGNOSIS, long.%ToJSON())
	Set expected(ref, 1) = $ListBuild(long.%ToJSON(), marker, ..#DIAGNOSIS, "Evidence element 2: 129 > 128", "evidence", "check")
	Set count("Evidence element 2: 129 > 128") = 1
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
	Do $$$AssertEquals(summary.decisions_"|"_summary.decide_"|"_summary.diagnose_"|"_summary.replies_"|"_summary.noReply, "32|1|31|32|1", "32 decisions (1 decide, 31 diagnose), 32 replies and one decision with no reply")
	Do $$$AssertEquals(summary.reasons.%Get("invalid")_"|"_summary.reasons.%Get("timer")_"|"_summary.reasons.%Get("cut_off"), "30|1|1", "the fallback reasons are counted")
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
	Do $$$AssertEquals($ListLength(names), 33, "33 files: one for each reply and summary.json")
	Do $$$AssertEquals(summary.files, 33, "and the summary says so")
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
	Do $$$AssertEquals(written.files_"|"_written.replies_"|"_written.decisions, "33|32|32", "and it holds the counts of the folder, itself among its files")
	Set again = $ClassMethod(..#TOOL, "Run", ..Folder, ..Refs, .summary)
	Do $$$AssertEquals($ListLength(..Files(..Folder)), 33, "a second run replaces the files of the first")
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
	Do $$$AssertTrue(lines [ "CHK|decisions|32|1|31|32|33", "the lines hold the counts")
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
	Quit ..One("SELECT COUNT(*) FROM Ens_Util.Log WHERE Job = ?", $Job)_"|"_..One("SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision")_"|"_..One("SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Usage")_"|"_..One("SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName %STARTSWITH 'OcuTalon.Bridge.Msg.' OR MessageBodyClassName IS NULL OR MessageBodyClassName = ''")
}

ClassMethod One(sql As %String, arg As %String = "") As %String [ Private ]
{
	Set result = $Select(arg = "": ##class(%SQL.Statement).%ExecDirect(, sql), 1: ##class(%SQL.Statement).%ExecDirect(, sql, arg))
	Quit $Select(result.%Next(): +result.%GetData(1), 1: "?")
}

Method TestRecordsAndLogsNothing()
{
	Do ..SeedAll(.expected, .count)
	Set before = ..Snap()
	Set sc = $ClassMethod(..#TOOL, "Run", ..Folder, ..Refs, .summary)
	Do $$$AssertStatusOK(sc, "the capture runs")
	Do $$$AssertEquals(..Snap(), before, "the event log, the Decision and Usage rows and the message headers are as they were")
	Do $$$AssertTrue(summary.replies > 20, "and it did capture replies")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Source).Text(..#TOOL, .text), "the tool has source")
	For name = "$$$LOG", "Ens.Util.Log", "%AI", "Chat", "SendRequest", "Conclude", "Ens.Director" {
		Do $$$AssertEquals($ListLength(##class(OcuTalon.Test.Bridge.Source).Lines(text, name, 1)), 0, "no code line of the tool names "_name)
	}
}

Method TestRecheckIsSilent()
{
	Set request = ..NewRequest("diagnose", "")
	Set long = $ClassMethod(..#PAYLOAD, "Usable")
	Do long.evidence.%Push($Translate($Justify("", 129), " ", "e"))
	Set emptied = $ClassMethod(..#PAYLOAD, "Usable")
	Do emptied.reasons.%Set(0, "No issues.")
	Set blanked = $ClassMethod(..#PAYLOAD, "Usable")
	Set blanked.cause = "No problems."
	Set usable = $ClassMethod(..#PAYLOAD, "Usable")
	Set odd = $ClassMethod(..#PAYLOAD, "Usable")
	Do odd.%Set("zzextra", 1)
	For label = "over the limit", "no reason left", "invalid after the filter", "an unknown field", "a usable reply" {
		Set reply = $Case(label, "over the limit": long, "no reason left": emptied, "invalid after the filter": blanked, "an unknown field": odd, : usable)
		Set before = ..Snap()
		Set valid = $ClassMethod(..#DECIDE, "Recheck", request, reply.%ToJSON(), ..#CLASS, "OcuTalon.Checks.ReplyGuard", .problem)
		Do $$$AssertEquals(valid, $Case(label, "a usable reply": 1, : 0), label_": the verdict")
		Do $$$AssertEquals($Select(valid: problem = "", 1: problem '= ""), 1, label_": and the problem")
		Do $$$AssertEquals(..Snap(), before, label_": no event is logged, no Decision or Usage row is saved and no message is sent")
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

}
