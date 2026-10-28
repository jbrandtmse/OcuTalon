/// Tests of the evaluation report (Story 9.2; AD-22, AD-30, AD-33; SM-1, SM-2, NFR-3, NFR-4). WARM-SAFE: they build reports from synthetic
/// OcuTalon.Eval.Data.CaseResult rows, synthetic case files in a folder below the manager's Temp directory and synthetic Decision rows. They
/// start no production and send no message. The run Refs start with zz, the case names with zz-rep-, and every test removes its rows, its
/// Decision rows and its folder.
///   - TestItems, TestInjection, TestFallback and TestUndecided: an item or injection row is right when it is decided, is not a fallback and
///     got the expected outcome; a fallback is listed apart and a row still sent counts in the total and is not right;
///   - TestIncidents: an incident is right on its cause category and element at fault together, the element ignoring case and spaces, and
///     the fix kind is shown and not scored;
///   - TestShares: SM-1 and SM-2 are met at 9 of 10 items and 8 of 10 incidents and not met below, and a kind with no row is not measured;
///   - TestHeldOut: the held-out rows are also counted on their own, in items and in incidents;
///   - TestTellNowMissed: a tell-now case decided Ignore or Digest is listed, one decided Act is not;
///   - TestCost: every priced decision is listed with its kind and model, the mean and the maximum are taken over the priced ones, the
///     decisions at or above 0.001 are flagged and an unpriced one is listed apart and is a problem;
///   - TestSize: the largest request has its case, the cases over 100,000 tokens are flagged and an empty size is unknown and a problem;
///   - TestSkipped, TestUnscored, TestEmptyRun and TestOtherRun: a skipped case is listed and scored in nothing, and only a skip of a kind
///     that EvalIn does not send yet is no problem; a row with no readable case file, no expectation or a kind that is not scored is
///     listed as unscored; a run with no row is a problem; the rows of another run are not in the report;
///   - TestIncomplete: a decided row that lacks a decision (a fallback included), a cost, a turn cost or a request size is listed once with its
///     reasons joined by "; " and is a problem, and its priced and unpriced decisions and unknown size are listed;
///   - TestText, TestTextSections and TestSave: the Markdown holds the scores, a flagged decision, a tell-now case missed and a skip with its
///     reason, and the sections for a scored incident, a fallback, an unpriced decision, an unknown size, a row not complete, a row not
///     scored and a skip reason with a pipe and a line break; Save writes the JSON and the Markdown, which read back equal to the report and
///     to Text;
///   - TestRunRefused: Run returns the error of a disabled EvalIn and no report.
Class OcuTalon.Test.Eval.Report Extends %UnitTest.TestCase
{

/// The start of every run Ref the tests make.
Parameter RUNPREFIX = "zz";

/// The start of every case name the tests make.
Parameter CASEPREFIX = "zz-rep-";

/// The production that TestRunRefused needs.
Parameter PRODUCTION = "OcuTalon.Production";

/// The Refs of the Decision rows that the test made, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the runs that the test made, comma-separated.
Property Runs As %String(MAXLEN = "");

/// The folder of the case files of the test, with a trailing separator.
Property Folder As %String(MAXLEN = 500);

/// Every Decision Ref, run Ref and folder that any test of the class made, for the check at the end of the class.
Property AllRefs As %String(MAXLEN = "");

Property AllRuns As %String(MAXLEN = "");

Property AllFolders As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Eval_Data.CaseResult WHERE RunRef %STARTSWITH ? AND CaseName %STARTSWITH ?", ..#RUNPREFIX, ..#CASEPREFIX)
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = "", ..Runs = ""
	Set base = ##class(%File).NormalizeDirectory("Temp", $SYSTEM.Util.ManagerDirectory())
	Set ..Folder = ##class(%File).NormalizeDirectory("zzreport"_$Translate($Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 12), "-_", "ab"), base)
	Set ..AllFolders = ..AllFolders_$Select(..AllFolders = "": "", 1: "|")_..Folder
	If '##class(%File).CreateDirectoryChain(..Folder) Quit $SYSTEM.Status.Error(5001, "The case folder "_..Folder_" cannot be made")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	For i = 1:1:$Length(..Runs, ",") {
		If $Piece(..Runs, ",", i) '= "" Do ##class(OcuTalon.Eval.Data.CaseResult).Remove($Piece(..Runs, ",", i))
	}
	If ..Folder '= "" Do ##class(%File).RemoveDirectoryTree(..Folder)
	Quit $$$OK
}

/// The class leaves nothing: no case row of a run it made, no Decision row it made and none of its folders. The status names what is left.
Method OnAfterAllTests() As %Status
{
	Set left = ""
	For i = 1:1:$Length(..AllRuns, ",") {
		Set run = $Piece(..AllRuns, ",", i)
		If run = "" Continue
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Eval_Data.CaseResult WHERE RunRef = ?", run)
		Do result.%Next()
		If +result.%GetData(1) Set left = left_", case rows of the run "_run
	}
	For i = 1:1:$Length(..AllRefs, ",") {
		Set ref = $Piece(..AllRefs, ",", i)
		If (ref '= "") && ##class(OcuTalon.Bridge.Data.Decision).RefIndexExists(ref) Set left = left_", the Decision row "_ref
	}
	For i = 1:1:$Length(..AllFolders, "|") {
		Set folder = $Piece(..AllFolders, "|", i)
		If (folder '= "") && ##class(%File).DirectoryExists(folder) Set left = left_", the folder "_folder
	}
	Quit $Select(left = "": $$$OK, 1: $SYSTEM.Status.Error(5001, "The class left"_$Extract(left, 2, *)))
}

/// Two decided rows: one got digest and expected digest, the other got digest and expected ignore.
Method TestItems()
{
	Set right = ..N("right"), wrong = ..N("wrong")
	Do ..ItemCase(right, "digest")
	Do ..ItemCase(wrong, "ignore")
	Set run = ..NewRun()
	Do ..Row(run, right, {"Outcome": "digest"})
	Do ..Row(run, wrong, {"Outcome": "digest"})
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder)
	Do $$$AssertEquals(..Line(report.scores.items), "1 of 2 share .5 met 0", "one of two items is right, and SM-1 is not met")
	Do $$$AssertEquals(report.scores.items.%GetTypeOf("met"), "boolean", "met is a boolean")
	Do $$$AssertEquals(+report.scores.items.target, .9, "the target is SM-1's 90%")
	Do $$$AssertEquals(..Rights(report), right_":1;"_wrong_":0", "the first row is right and the second is not")
	Do $$$AssertEquals(..Line(report.scores.incidents), "0 of 0 share null met null", "an item-only run has no incident")
	Do $$$AssertEquals(report.cases.%Get(1).expected_"|"_report.cases.%Get(1).got, "ignore|digest", "a case shows its expected and its got outcome")
	Do $$$AssertEquals(report.skipped.%Size()_"|"_report.notComplete.%Size()_"|"_report.unscored.%Size()_"|"_report.tellNowMissed.%Size()_"|"_report.fallbacks.%Size(), "0|0|0|0|0", "nothing else is listed")
	Do $$$AssertEquals(report.run_"|"_report.folder, run_"|"_..Folder, "the report names the run and the folder")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Report).Problems(report).%Size(), 0, "and the run has no problem")
}

/// An injection case is scored like an item and counts in SM-1's items.
Method TestInjection()
{
	Set item = ..N("item"), injection = ..N("injection")
	Do ..ItemCase(item, "digest")
	Do ..ItemCase(injection, "ignore", 0, "injection")
	Set run = ..NewRun()
	Do ..Row(run, item, {"Outcome": "digest"})
	Do ..Row(run, injection, {"Outcome": "ignore"})
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder)
	Do $$$AssertEquals(..Line(report.scores.items), "2 of 2 share 1 met 1", "the injection case counts in the items")
	Do $$$AssertEquals(report.cases.%Get(0).case_"|"_report.cases.%Get(0).kind, injection_"|injection", "and shows its kind")
}

/// A fallback is not right even when its tell-now outcome is the expected one; it is listed with its reason and is not a tell-now case missed.
Method TestFallback()
{
	Set name = ..N("fallback")
	Do ..ItemCase(name, "tellnow")
	Set run = ..NewRun()
	Do ..Row(run, name, {"Outcome": "tellnow", "Fallback": 1, "FallbackReason": "timeout"})
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder)
	Do $$$AssertEquals(..Line(report.scores.items), "0 of 1 share 0 met 0", "the fallback is not right")
	Do $$$AssertEquals(report.cases.%Get(0).%Get("fallback")_"|"_report.cases.%Get(0).%Get("right"), "1|0", "the case shows the fallback")
	Do $$$AssertEquals(report.fallbacks.%Size(), 1, "one fallback is listed")
	Do $$$AssertEquals(report.fallbacks.%Get(0).case_"|"_report.fallbacks.%Get(0).reason, name_"|timeout", "with its case and reason")
	Do $$$AssertEquals(report.tellNowMissed.%Size(), 0, "it is not a tell-now case missed")
	Do $$$AssertEquals(report.notComplete.%Size(), 0, "it is complete: it has its decision, cost and size")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Report).Problems(report).%Size(), 0, "and a fallback is no problem of its own")
}

/// A row still sent counts in the total and is not right; the report says it is not decided, and that is a problem.
Method TestUndecided()
{
	Set done = ..N("done"), open = ..N("open")
	Do ..ItemCase(done, "digest")
	Do ..ItemCase(open, "ignore")
	Set run = ..NewRun()
	Do ..Row(run, done, {"Outcome": "digest"})
	Do ..Row(run, open, {"State": "sent", "DecisionRef": "", "CostUSD": "", "LargestRequestTokens": ""})
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder)
	Do $$$AssertEquals(..Line(report.scores.items), "1 of 2 share .5 met 0", "the row still sent is counted and is not right")
	Do $$$AssertEquals(..Rights(report), done_":1;"_open_":0", "only the decided row is right")
	Do $$$AssertEquals(report.notComplete.%Size(), 1, "one row is not complete")
	Do $$$AssertEquals(report.notComplete.%Get(0).case_"|"_report.notComplete.%Get(0).reason, open_"|not decided", "it says the row is not decided")
	Do $$$AssertEquals(..Texts(##class(OcuTalon.Eval.Report).Problems(report)), open_": not decided", "and that is the problem")
	Do $$$AssertEquals(report.size.unknown.%Size(), 0, "a row not decided has no size to report")
}

/// Two incident rows with the right category: the element ` orderdate ` matches OrderDate ignoring case and spaces, CustomerId does not; the
/// fix kind is shown, not scored. A second run: the right element with another category is wrong, and a missing fix kind does not make a
/// right row wrong.
Method TestIncidents()
{
	Set a = ..N("a"), b = ..N("b"), c = ..N("c"), d = ..N("d")
	For name = a, b, c, d {
		Do ..IncidentCase(name, "data_format_change", "OrderDate", "repair_resend")
	}
	Set run = ..NewRun()
	Do ..Row(run, a, {"Outcome": "", "CauseCategory": "data_format_change", "ElementAtFault": " orderdate ", "FixKind": "repair_resend"})
	Do ..Row(run, b, {"Outcome": "", "CauseCategory": "data_format_change", "ElementAtFault": "CustomerId", "FixKind": "repair_resend"})
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder)
	Do $$$AssertEquals(..Line(report.scores.incidents), "1 of 2 share .5 met 0", "one of two incidents is right, and SM-2 is not met")
	Do $$$AssertEquals(+report.scores.incidents.target, .8, "the target is SM-2's 80%")
	Do $$$AssertEquals(..Rights(report), a_":1;"_b_":0", "the element decides, not the category alone")
	Do $$$AssertEquals(..Line(report.scores.items), "0 of 0 share null met null", "an incident-only run has no item")
	Set first = report.cases.%Get(0)
	Do $$$AssertEquals(first.expected.causeCategory_"|"_first.expected.elementAtFault_"|"_first.expected.fixKind, "data_format_change|OrderDate|repair_resend", "an incident shows its expected cause, element and fix")
	Do $$$AssertEquals(first.got.causeCategory_"|"_first.got.elementAtFault_"|"_first.got.fixKind, "data_format_change| orderdate |repair_resend", "and what the row holds")
	Set second = ..NewRun()
	Do ..Row(second, c, {"Outcome": "", "CauseCategory": "connection_failure", "ElementAtFault": "OrderDate", "FixKind": ""})
	Do ..Row(second, d, {"Outcome": "", "CauseCategory": "data_format_change", "ElementAtFault": "OrderDate", "FixKind": ""})
	Set report = ##class(OcuTalon.Eval.Report).Build(second, ..Folder)
	Do $$$AssertEquals(..Rights(report), c_":0;"_d_":1", "the category must match too, and the fix kind is not scored")
}

/// SM-1 is met at 9 of 10 items and not at 8 of 9; SM-2 is met at 8 of 10 incidents and not at 7 of 10; a kind with no row is not measured.
Method TestShares()
{
	Do ..ShareCases(10)
	Set report = ##class(OcuTalon.Eval.Report).Build(..ItemRun(9, 10), ..Folder)
	Do $$$AssertEquals(..Line(report.scores.items), "9 of 10 share .9 met 1", "9 of 10 items meet SM-1")
	Do $$$AssertEquals(..Line(report.scores.incidents), "0 of 0 share null met null", "no incident is not measured")
	Set report = ##class(OcuTalon.Eval.Report).Build(..ItemRun(8, 9), ..Folder)
	Do $$$AssertEquals(..Line(report.scores.items), "8 of 9 share .8889 met 0", "8 of 9 items do not meet SM-1")
	Set report = ##class(OcuTalon.Eval.Report).Build(..IncidentRun(8, 10), ..Folder)
	Do $$$AssertEquals(..Line(report.scores.incidents), "8 of 10 share .8 met 1", "8 of 10 incidents meet SM-2")
	Do $$$AssertEquals(..Line(report.scores.items), "0 of 0 share null met null", "no item is not measured")
	Set report = ##class(OcuTalon.Eval.Report).Build(..IncidentRun(7, 10), ..Folder)
	Do $$$AssertEquals(..Line(report.scores.incidents), "7 of 10 share .7 met 0", "7 of 10 incidents do not meet SM-2")
}

/// A held-out item and incident are counted in the items and incidents and again in the held-out scores, which have no target.
Method TestHeldOut()
{
	Set one = ..N("one"), two = ..N("two"), three = ..N("three"), four = ..N("four"), five = ..N("five"), six = ..N("six")
	Do ..ItemCase(one, "digest", 1)
	Do ..ItemCase(two, "digest", 1)
	Do ..ItemCase(three, "digest", 0)
	Do ..IncidentCase(four, "data_format_change", "OrderDate", "repair_resend", 1)
	Do ..IncidentCase(five, "data_format_change", "OrderDate", "repair_resend", 1)
	Do ..IncidentCase(six, "data_format_change", "OrderDate", "repair_resend", 0)
	Set run = ..NewRun()
	Do ..Row(run, one, {"Outcome": "digest"})
	Do ..Row(run, two, {"Outcome": "ignore"})
	Do ..Row(run, three, {"Outcome": "digest"})
	Do ..Row(run, four, {"Outcome": "", "CauseCategory": "data_format_change", "ElementAtFault": "OrderDate"})
	Do ..Row(run, five, {"Outcome": "", "CauseCategory": "unknown", "ElementAtFault": "OrderDate"})
	Do ..Row(run, six, {"Outcome": "", "CauseCategory": "data_format_change", "ElementAtFault": "OrderDate"})
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder)
	Do $$$AssertEquals(..Line(report.scores.heldOutItems), "1 of 2 share .5 met -", "the held-out items are one right of two, with no target")
	Do $$$AssertEquals(..Line(report.scores.items), "2 of 3 share .6667 met 0", "and all three rows are also in the items")
	Do $$$AssertEquals(..Line(report.scores.heldOutIncidents), "1 of 2 share .5 met -", "the held-out incidents are one right of two, with no target")
	Do $$$AssertEquals(..Line(report.scores.incidents), "2 of 3 share .6667 met 0", "and all three rows are also in the incidents")
	Set clean = ..NewRun()
	Do ..Row(clean, three, {"Outcome": "digest"})
	Set report = ##class(OcuTalon.Eval.Report).Build(clean, ..Folder)
	Do $$$AssertEquals(..Line(report.scores.heldOutItems), "0 of 0 share null met -", "a run with no held-out case has none to score")
}

/// Three rows expect tell-now: the two decided Ignore and Digest are listed, the one decided Act is not; a case that expects another
/// outcome is not listed, and neither is a tell-now case decided tell-now.
Method TestTellNowMissed()
{
	For short = "ignored", "digested", "acted", "told", "other" {
		Do ..ItemCase(..N(short), $Select(short = "other": "digest", 1: "tellnow"))
	}
	Set run = ..NewRun()
	Do ..Row(run, ..N("ignored"), {"Outcome": "ignore"})
	Do ..Row(run, ..N("digested"), {"Outcome": "digest"})
	Do ..Row(run, ..N("acted"), {"Outcome": "act"})
	Do ..Row(run, ..N("told"), {"Outcome": "tellnow"})
	Do ..Row(run, ..N("other"), {"Outcome": "ignore"})
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder)
	Do $$$AssertEquals(..Names(report.tellNowMissed, "case"), ..N("digested")_","_..N("ignored"), "the tell-now cases decided Ignore and Digest are listed, in case order")
	Do $$$AssertEquals(..Names(report.tellNowMissed, "got"), "digest,ignore", "with what they got")
}

/// The priced decisions are listed with their kind and model; the mean is over them, the maximum has its case, only the decision at 0.001 is
/// flagged and the unpriced one is listed apart and is a problem.
Method TestCost()
{
	Set a = ..N("a"), b = ..N("b"), c = ..N("c"), d = ..N("d")
	For name = a, b, c, d {
		Do ..ItemCase(name, "digest")
	}
	Set decideA = ..Decision("decide", "claude-haiku-5-5"), turnA = ..Decision("turn", "claude-sonnet-5-5")
	Set decideB = ..Decision("decide", "claude-haiku-5-5"), decideC = ..Decision("decide", "claude-haiku-5-5"), decideD = ..Decision("decide", "claude-haiku-5-5")
	Set run = ..NewRun()
	Do ..Row(run, a, {"DecisionRef": (decideA), "CostUSD": (0.0002), "TurnDecisionRef": (turnA), "TurnCostUSD": (0.0004)})
	Do ..Row(run, b, {"DecisionRef": (decideB), "CostUSD": (0.001)})
	Do ..Row(run, c, {"DecisionRef": (decideC), "CostUSD": (0.000999)})
	Do ..Row(run, d, {"DecisionRef": (decideD), "CostUSD": ""})
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder)
	Set cost = report.cost
	Do $$$AssertEquals(cost.priced_"|"_cost.decisions.%Size(), "4|4", "four decisions are priced")
	Do $$$AssertEquals(+cost.meanUSD, .00065, "the mean is 0.00065")
	Do $$$AssertEquals(+cost.maxUSD_"|"_cost.maxCase, ".001|"_b, "the maximum is 0.001, with its case")
	Do $$$AssertEquals(+cost.flagAtUSD, .001, "the flag is at 0.001")
	Do $$$AssertEquals(..Names(cost.flagged, "case"), b, "only the decision at 0.001 is flagged")
	Do $$$AssertEquals(..Names(cost.unpriced, "case"), d, "the unpriced decision is listed apart")
	Do $$$AssertEquals(..Names(cost.decisions, "case"), a_","_a_","_b_","_c, "the decide and the turn of the first case, then the others, are listed")
	Do $$$AssertEquals(..Names(cost.decisions, "kind"), "decide,turn,decide,decide", "with the kind of their Decision rows")
	Do $$$AssertEquals(..Names(cost.decisions, "model"), "claude-haiku-5-5,claude-sonnet-5-5,claude-haiku-5-5,claude-haiku-5-5", "and their models")
	Do $$$AssertEquals(..Names(cost.decisions, "ref"), decideA_","_turnA_","_decideB_","_decideC, "and their Refs")
	Do $$$AssertEquals(..Texts(##class(OcuTalon.Eval.Report).Problems(report)), d_": no cost", "the unpriced decision is the problem")
	Set only = ..NewRun()
	Do ..Row(only, d, {"DecisionRef": (decideD), "CostUSD": ""})
	Set report = ##class(OcuTalon.Eval.Report).Build(only, ..Folder)
	Do $$$AssertEquals(report.cost.priced_"|"_report.cost.%GetTypeOf("meanUSD")_"|"_report.cost.%GetTypeOf("maxUSD"), "0|null|null", "with no priced decision the mean and the maximum are null")
}

/// The largest request is the 100,001-token one and only it is flagged; a request of 100,000 is not; an empty size is unknown and a problem.
Method TestSize()
{
	Set a = ..N("a"), b = ..N("b"), c = ..N("c")
	For name = a, b, c {
		Do ..ItemCase(name, "digest")
	}
	Set run = ..NewRun()
	Do ..Row(run, a, {"LargestRequestTokens": 100000})
	Do ..Row(run, b, {"LargestRequestTokens": 100001})
	Do ..Row(run, c, {"LargestRequestTokens": ""})
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder)
	Set size = report.size
	Do $$$AssertEquals(size.largestTokens_"|"_size.largestCase, "100001|"_b, "the largest request is 100001 tokens, with its case")
	Do $$$AssertEquals(+size.flagOverTokens, 100000, "the flag is over 100000")
	Do $$$AssertEquals(..Names(size.flagged, "case")_"|"_..Names(size.flagged, "tokens"), b_"|100001", "only the request over 100000 is flagged")
	Do $$$AssertEquals(..Names(size.unknown, ""), c, "the empty size is unknown")
	Do $$$AssertEquals(..Texts(##class(OcuTalon.Eval.Report).Problems(report)), c_": no request size", "and is the problem")
	Set none = ..NewRun()
	Do ..Row(none, c, {"LargestRequestTokens": ""})
	Set report = ##class(OcuTalon.Eval.Report).Build(none, ..Folder)
	Do $$$AssertEquals(report.size.%GetTypeOf("largestTokens"), "null", "with no known size the largest request is null")
}

/// Start's skipped list: the incident is not run yet and is no problem; the item with no itemId and the case file that cannot be read are
/// problems; none is scored.
Method TestSkipped()
{
	Set ok = ..N("ok"), incident = ..N("incident"), noId = ..N("noid"), bad = ..N("bad"), gone = ..N("gone")
	Do ..ItemCase(ok, "digest")
	Do ..IncidentCase(incident, "data_format_change", "OrderDate", "repair_resend")
	Do ..ItemCase(noId, "digest")
	Do ..WriteCase(bad, "this is not json")
	Set run = ..NewRun()
	Do ..Row(run, ok, {"Outcome": "digest"})
	Set skipped = [{"case": (incident), "reason": "its kind is 'incident', and only the kinds item and injection hold a recorded Item"}, {"case": (noId), "reason": "it has no item.itemId"}, {"case": (bad), "reason": "case.json is not a JSON object"}, {"case": (gone), "reason": "the folder has no case.json"}]
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder, skipped)
	Do $$$AssertEquals(report.skipped.%Size(), 4, "all four skipped cases are listed")
	Do $$$AssertEquals(..Names(report.skipped, "case"), incident_","_noId_","_bad_","_gone, "in the order Start gave")
	Do $$$AssertEquals(..Names(report.skipped, "kind"), "incident,item,,", "with the kind of the case file, when it can be read")
	Do $$$AssertEquals(..Booleans(report.skipped, "notRunYet"), "1,0,0,0", "only the incident is a kind EvalIn does not send yet")
	Do $$$AssertEquals(report.skipped.%Get(1).reason, "it has no item.itemId", "each keeps its reason")
	Do $$$AssertEquals(..Line(report.scores.items), "1 of 1 share 1 met 1", "no skipped case is in a score")
	Do $$$AssertEquals(..Line(report.scores.incidents), "0 of 0 share null met null", "the incident case is not scored")
	Do $$$AssertEquals(..Texts(##class(OcuTalon.Eval.Report).Problems(report)), noId_": not sent: it has no item.itemId"_$Char(10)_bad_": not sent: case.json is not a JSON object"_$Char(10)_gone_": not sent: the folder has no case.json", "the other three are the problems, and the incident is none")
	Set clean = ##class(OcuTalon.Eval.Report).Build(run, ..Folder, [{"case": (incident), "reason": "its kind is 'incident'"}])
	Do $$$AssertEquals(##class(OcuTalon.Eval.Report).Problems(clean).%Size(), 0, "a run that skipped only the incident has no problem")
}

/// A row whose case file is gone, one whose kind is all-clear and one with no expectation are listed as unscored with a reason, count in no
/// score and are problems.
Method TestUnscored()
{
	Set gone = ..N("gone"), clear = ..N("clear"), bare = ..N("bare"), bareIncident = ..N("bareinc"), other = ..N("other")
	Do ..WriteCase(clear, {"name": (clear), "kind": "all-clear", "heldOut": false, "expectation": {"catalogKey": "check.allPassed"}}.%ToJSON())
	Do ..WriteCase(bare, {"name": (bare), "kind": "item", "heldOut": false, "expectation": {}}.%ToJSON())
	Do ..WriteCase(bareIncident, {"name": (bareIncident), "kind": "incident", "heldOut": false, "expectation": {"causeCategory": "unknown"}}.%ToJSON())
	Do ..WriteCase(other, {"name": (other), "kind": "chat", "heldOut": false, "expectation": {}}.%ToJSON())
	Set run = ..NewRun()
	For name = gone, clear, bare, bareIncident, other {
		Do ..Row(run, name, {"Outcome": "digest"})
	}
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder)
	Do $$$AssertEquals(..Names(report.unscored, "case"), bare_","_bareIncident_","_clear_","_gone_","_other, "the five rows are unscored, in case order")
	Set reasons = ..Names(report.unscored, "reason", "|")
	Do $$$AssertEquals($Piece(reasons, "|", 1), "its case.json has no outcome in its expectation", "an item with no outcome says so")
	Do $$$AssertEquals($Piece(reasons, "|", 2), "its case.json has no elementAtFault in its expectation", "an incident with no element says so")
	Do $$$AssertEquals($Piece(reasons, "|", 3), "its kind is 'all-clear', which the report does not score", "the all-clear case is not scored yet")
	Do $$$AssertEquals($Piece(reasons, "|", 4), "its case.json is missing or is not a JSON object", "a case file that is gone says so")
	Do $$$AssertEquals($Piece(reasons, "|", 5), "its kind is 'chat', which the report does not score", "and a kind that is none of the case kinds")
	Do $$$AssertEquals(report.cases.%Size(), 0, "no case is scored")
	Do $$$AssertEquals(..Line(report.scores.items)_"|"_..Line(report.scores.incidents), "0 of 0 share null met null|0 of 0 share null met null", "and none is in a score")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Report).Problems(report).%Size(), 5, "each is a problem, and the run is not empty")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Report).Problems(report).%Get(0), bare_": not scored: its case.json has no outcome in its expectation", "the problem names the case and the reason")
}

/// A run with no row is the problem that the run sent no case.
Method TestEmptyRun()
{
	Set run = ..NewRun()
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder)
	Do $$$AssertEquals(report.cases.%Size()_"|"_report.unscored.%Size(), "0|0", "the report holds no case")
	Do $$$AssertEquals(..Line(report.scores.items), "0 of 0 share null met null", "and no score")
	Do $$$AssertEquals(..Texts(##class(OcuTalon.Eval.Report).Problems(report)), "the run sent no case", "the run sent no case is the problem")
	Do $$$AssertEquals(report.cost.priced_"|"_report.size.%GetTypeOf("largestTokens"), "0|null", "with no cost or size")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Report).Problems("").%Get(0), "there is no report", "and no report is a problem")
}

/// The rows of another run are not in the report.
Method TestOtherRun()
{
	Set mine = ..N("mine"), other = ..N("other")
	Do ..ItemCase(mine, "digest")
	Do ..ItemCase(other, "ignore")
	Set first = ..NewRun(), second = ..NewRun()
	Do ..Row(first, mine, {"Outcome": "digest"})
	Do ..Row(second, other, {"Outcome": "digest", "CostUSD": 0.002, "LargestRequestTokens": 200000})
	Set report = ##class(OcuTalon.Eval.Report).Build(first, ..Folder)
	Do $$$AssertEquals(..Rights(report), mine_":1", "only the rows of the run are scored")
	Do $$$AssertEquals(report.cost.priced_"|"_report.cost.flagged.%Size()_"|"_report.size.flagged.%Size(), "1|0|0", "and only its cost and size are in the report")
}

/// The Markdown holds the title, the score lines, the tell-now case missed, a flagged decision with its model, the size with its words and a
/// skipped case with its reason.
Method TestText()
{
	Set a = ..N("a"), b = ..N("b"), incident = ..N("incident"), bad = ..N("bad")
	Do ..ItemCase(a, "digest")
	Do ..ItemCase(b, "tellnow")
	Do ..IncidentCase(incident, "data_format_change", "OrderDate", "repair_resend")
	Do ..WriteCase(bad, "this is not json")
	Set run = ..NewRun()
	Do ..Row(run, a, {"Outcome": "digest"})
	Do ..Row(run, b, {"Outcome": "ignore", "DecisionRef": (..Decision("decide", "claude-sonnet-5-5")), "CostUSD": (0.002), "LargestRequestTokens": 4321})
	Set reason = "its kind is 'incident', and only the kinds item and injection hold a recorded Item"
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder, [{"case": (incident), "reason": (reason)}, {"case": (bad), "reason": "case.json is not a JSON object"}])
	Set text = ##class(OcuTalon.Eval.Report).Text(report, "Evaluation of the set")
	Do $$$AssertEquals($Piece(text, $Char(10), 1), "# Evaluation of the set", "the text starts with the title")
	Do $$$AssertTrue(text [ "| Items (SM-1) | 1 | 2 | 50.0% | 90% | not met |", "the items line: right, of, share, target and result")
	Do $$$AssertTrue(text [ "| Incidents (SM-2) | 0 | 0 | not measured | 80% | not measured |", "the incidents line says not measured")
	Do $$$AssertTrue(text [ "| Held-out items | 0 | 0 | not measured |", "the held-out line has no target")
	Do $$$AssertTrue(text [ ("- "_b_": decided ignore"), "the tell-now case missed is listed")
	Do $$$AssertTrue(text [ ("- "_b_", decide, claude-sonnet-5-5: $0.002"), "the flagged decision is listed with its case, kind, model and cost")
	Do $$$AssertTrue(text [ "Priced decisions: 2.", "the priced decisions are counted")
	Do $$$AssertTrue(text [ ("Maximum: $0.002 ("_b_")."), "and the maximum has its case")
	Do $$$AssertTrue(text [ ("Largest request: 4321 tokens ("_b_"), estimated by the bridge."), "the largest request says it is estimated by the bridge")
	Do $$$AssertTrue(text [ ("- "_incident_" (incident): "_reason_" [not run until its story]"), "the incident skip says it is not run until its story")
	Do $$$AssertTrue(text [ ("- "_bad_" (kind not known): case.json is not a JSON object"), "the unreadable skip has its reason and no such note")
	Do $$$AssertTrue(text [ ("| "_a_" | item | no | digest | digest | yes |"), "the case table has a row for each case")
	Do $$$AssertTrue(text [ ("| "_b_" | item | no | tellnow | ignore | no |"), "with what was expected and what was got")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Report).Text("", "x"), "", "no report has no text")
}

/// The sections that TestText does not reach: a scored incident row with its category, element and fix kind, a fallback, an unpriced
/// decision, a request of unknown size, a row not complete, a row not scored, and a skip reason with a pipe and a line break.
Method TestTextSections()
{
	Set incident = ..N("incident"), fallback = ..N("fallback"), unpriced = ..N("unpriced"), nosize = ..N("nosize"), nodecision = ..N("nodecision"), gone = ..N("gone"), skip = ..N("skip")
	Set nl = $Char(10)
	Do ..IncidentCase(incident, "data_format_change", "OrderDate", "repair_resend")
	For name = fallback, unpriced, nosize, nodecision {
		Do ..ItemCase(name, "digest")
	}
	Set run = ..NewRun()
	Do ..Row(run, incident, {"Outcome": "", "CauseCategory": "data_format_change", "ElementAtFault": "ORDERDATE", "FixKind": "repair_resend"})
	Do ..Row(run, fallback, {"Outcome": "tellnow", "Fallback": 1, "FallbackReason": "timeout"})
	Do ..Row(run, unpriced, {"Outcome": "digest", "DecisionRef": (..Decision("decide", "claude-haiku-5-5")), "CostUSD": ""})
	Do ..Row(run, nosize, {"Outcome": "digest", "LargestRequestTokens": ""})
	Do ..Row(run, nodecision, {"Outcome": "digest", "DecisionRef": "", "CostUSD": "", "LargestRequestTokens": ""})
	Do ..Row(run, gone, {"Outcome": "digest"})
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder, [{"case": (skip), "reason": ("line one | line two"_nl_"line three")}])
	Set text = ##class(OcuTalon.Eval.Report).Text(report, "Sections")
	Do $$$AssertTrue(text [ "| Incidents (SM-2) | 1 | 1 | 100.0% | 80% | met |", "the incidents line counts the scored incident")
	Do $$$AssertTrue(text [ ("| "_incident_" | incident | no | data_format_change, OrderDate, repair_resend | data_format_change, ORDERDATE, repair_resend | yes |"), "the incident row has the category, element and fix kind that were expected and got")
	Do $$$AssertTrue(text [ ("- "_fallback_": timeout (outcome tellnow)"), "the fallback is listed with its reason and outcome")
	Do $$$AssertTrue(text [ ("Unpriced decisions:"_nl_nl_"- "_unpriced_", decide, claude-haiku-5-5"_nl), "the unpriced decision is listed with its case, kind and model")
	Do $$$AssertTrue(text [ ("Requests of unknown size:"_nl_nl_"- "_nodecision_nl_"- "_nosize_nl), "the requests of unknown size are listed")
	Do $$$AssertTrue(text [ ("- "_nosize_": no request size"_nl), "the row with no request size is not complete, with its reason")
	Do $$$AssertTrue(text [ ("- "_nodecision_": no decision"_nl), "and so is the row with no decision")
	Do $$$AssertTrue(text [ ("- "_gone_": "_$Parameter("OcuTalon.Eval.Report", "REASONNOCASEFILE")_nl), "the row with no case file is listed as not scored, with its reason")
	Do $$$AssertTrue(text [ ("- "_skip_" (kind not known): line one / line two line three"_nl), "a skip reason has no pipe and no line break")
}

/// A decided row that lacks a decision (a fallback included), a cost, a turn cost or a request size is listed once, with its reasons joined
/// by "; ", and is a problem; its decisions are priced or unpriced and its unknown size is listed. A complete row is none of these.
Method TestIncomplete()
{
	Set a = ..N("a"), b = ..N("b"), c = ..N("c"), d = ..N("d"), e = ..N("e")
	For name = a, b, c, d, e {
		Do ..ItemCase(name, "digest")
	}
	Set run = ..NewRun()
	Do ..Row(run, a, {"Outcome": "tellnow", "Fallback": 1, "FallbackReason": "no answer", "DecisionRef": "", "CostUSD": "", "LargestRequestTokens": ""})
	Do ..Row(run, b, {"Outcome": "act", "TurnDecisionRef": (..Decision("turn", "claude-haiku-5-5")), "TurnCostUSD": ""})
	Do ..Row(run, c, {"Outcome": "digest", "CostUSD": "", "LargestRequestTokens": ""})
	Do ..Row(run, d, {"Outcome": "digest", "TurnDecisionRef": (..Decision("turn", "claude-haiku-5-5")), "TurnCostUSD": 0.0003})
	Do ..Row(run, e, {"Outcome": "digest"})
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder)
	Do $$$AssertEquals(report.notComplete.%Size(), 3, "three rows are not complete, one entry for each")
	Do $$$AssertEquals(..Names(report.notComplete, "case")_"|"_..Names(report.notComplete, "reason", ";"), a_","_b_","_c_"|no decision;no turn cost;no cost; no request size", "each with its reasons, joined by a semicolon and a space")
	Do $$$AssertEquals(..Texts(##class(OcuTalon.Eval.Report).Problems(report)), a_": no decision"_$Char(10)_b_": no turn cost"_$Char(10)_c_": no cost; no request size", "and each is a problem, the fallback with no decision included")
	Do $$$AssertEquals(..Names(report.fallbacks, "case"), a, "the fallback with no decision is also listed apart")
	Do $$$AssertEquals(..Names(report.size.unknown, ""), a_","_c, "the rows with no request size are unknown")
	Do $$$AssertEquals(report.cost.priced_"|"_..Names(report.cost.unpriced, "case"), "4|"_b_","_c, "four decisions are priced, and the unpriced turn and decide are listed apart")
}

/// Save writes the JSON and the Markdown, makes the directory, and what it wrote reads back as the report and as Text.
Method TestSave()
{
	Set name = ..N("saved")
	Do ..ItemCase(name, "digest")
	Set run = ..NewRun()
	Do ..Row(run, name, {"Outcome": "digest", "DecisionRef": (..Decision("decide", "claude-haiku-5-5")), "CostUSD": (0.00065)})
	Set report = ##class(OcuTalon.Eval.Report).Build(run, ..Folder)
	Set directory = ##class(%File).NormalizeDirectory("zz-out", ..Folder)
	Do $$$AssertTrue('##class(%File).DirectoryExists(directory), "the report directory is not there yet")
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Report).Save(report, "A title", directory, "set"), "Save succeeds")
	Set json = ##class(%File).NormalizeFilename("set.json", directory), markdown = ##class(%File).NormalizeFilename("set.md", directory)
	Do $$$AssertTrue(##class(%File).Exists(json) && ##class(%File).Exists(markdown), "both files are written")
	If '##class(%File).Exists(json) || '##class(%File).Exists(markdown) Quit
	Set back = ##class(%DynamicAbstractObject).%FromJSONFile(json)
	Do $$$AssertEquals(back.%ToJSON(), report.%ToJSON(), "the JSON reads back equal to the report")
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set stream.Filename = markdown
	Set stream.TranslateTable = "UTF8"
	Do $$$AssertEquals(stream.Read(1000000), ##class(OcuTalon.Eval.Report).Text(report, "A title"), "the Markdown equals Text")
	Do $$$AssertTrue($$$ISERR(##class(OcuTalon.Eval.Report).Save(report, "A title", directory, "../set")), "a name with a path is refused")
	Do $$$AssertTrue($$$ISERR(##class(OcuTalon.Eval.Report).Save("", "A title", directory, "none")), "and so is no report")
}

/// Run returns the error of a disabled EvalIn and no report. Where EvalIn is enabled (OCUTALON_EVAL=1) the test calls no Run.
Method TestRunRefused()
{
	Set running = ##class(Ens.Director).IsProductionRunning(.name) && ($Get(name) = ..#PRODUCTION)
	Do $$$AssertTrue(running, ..#PRODUCTION_" runs: this test runs in throwaways and CI only (Rule 21)")
	If 'running Quit
	If $$$ISOK(##class(Ens.Director).CreateBusinessService("EvalIn", .service)) {
		Do $$$AssertTrue($IsObject(service) && service.%IsA("OcuTalon.Eval.In"), "EvalIn is enabled here and is an OcuTalon.Eval.In, so Run is not refused and the test calls none")
		Quit
	}
	Set report = "x"
	Set sc = ##class(OcuTalon.Eval.Report).Run(, , 1, .report)
	Do $$$AssertTrue($$$ISERR(sc), "Run is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "disabled", "the error says disabled: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(report, "", "and there is no report")
}

/// --- helpers ---
/// The name of a case of the test.
ClassMethod N(short As %String) As %String [ Private ]
{
	Quit ..#CASEPREFIX_short
}

/// A new run Ref that starts with zz, kept for the clean-up.
Method NewRun() As %String [ Private ]
{
	Set run = ..#RUNPREFIX_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 20)
	Set ..Runs = ..Runs_$Select(..Runs = "": "", 1: ",")_run
	Set ..AllRuns = ..AllRuns_$Select(..AllRuns = "": "", 1: ",")_run
	Quit run
}

/// Writes the case.json of the case folder.
Method WriteCase(name As %String, text As %String) [ Private ]
{
	Set directory = ##class(%File).SubDirectoryName(..Folder, name)
	Do $$$AssertTrue(##class(%File).CreateDirectoryChain(directory), name_": the case folder is made")
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set stream.Filename = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.In).#CASEFILE, directory)
	Do stream.Write(text)
	Do $$$AssertStatusOK(stream.%Save(), name_": the case file is written")
}

/// An item (or other outcome) case that expects the outcome.
Method ItemCase(name As %String, expected As %String, heldOut As %Boolean = 0, kind As %String = "item") [ Private ]
{
	Set case = {"name": (name), "kind": (kind)}
	Do case.%Set("heldOut", heldOut, "boolean")
	Set case.expectation = {"outcome": (expected)}
	Set case.item = {"itemId": (name), "channel": "mailbox", "provenance": "untrusted"}
	Do ..WriteCase(name, case.%ToJSON())
}

/// An incident case that expects the cause category, element at fault and fix kind.
Method IncidentCase(name As %String, category As %String, element As %String, fix As %String = "", heldOut As %Boolean = 0) [ Private ]
{
	Set case = {"name": (name), "kind": "incident"}
	Do case.%Set("heldOut", heldOut, "boolean")
	Set case.expectation = {"causeCategory": (category), "elementAtFault": (element), "fixKind": (fix)}
	Set case.snapshot = "snapshot.json"
	Do ..WriteCase(name, case.%ToJSON())
}

/// Opens the row of the case as EvalIn does and completes it as EvalSink does: decided, with a decision, a cost of 0.0002 and a request of
/// 1000 tokens, unless fields (property names and values) say otherwise.
Method Row(run As %String, name As %String, fields As %DynamicObject) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Open(run, name, "source-"_name, ##class(OcuTalon.Bridge.Ids).NewRef()), name_": the row is opened")
	Set row = ##class(OcuTalon.Eval.Data.CaseResult).RunCaseIndexOpen(run, name)
	If '$IsObject(row) Quit
	Set row.State = "decided"
	Set row.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.CostUSD = 0.0002
	Set row.LargestRequestTokens = 1000
	Set iterator = fields.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		Set $Property(row, key) = value
	}
	Do $$$AssertStatusOK(row.%Save(), name_": the row is saved")
}

/// A Decision row of the owner eval with the model, kept for the clean-up. Returns its Ref.
Method Decision(kind As %String, model As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Decision("eval", kind, , {"Model": (model)})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..AllRefs = ..AllRefs_$Select(..AllRefs = "": "", 1: ",")_ref
	Quit ref
}

/// Writes the case files i1 to i<count> (items that expect digest) and c1 to c<count> (incidents that expect data_format_change and OrderDate).
Method ShareCases(count As %Integer) [ Private ]
{
	For i = 1:1:count {
		Do ..ItemCase(..N("i"_i), "digest")
		Do ..IncidentCase(..N("c"_i), "data_format_change", "OrderDate", "repair_resend")
	}
}

/// A run of item rows i1 to i<total>, the first <right> of them right. Returns the run.
Method ItemRun(right As %Integer, total As %Integer) As %String [ Private ]
{
	Set run = ..NewRun()
	For i = 1:1:total {
		Do ..Row(run, ..N("i"_i), {"Outcome": ($Select(i '> right: "digest", 1: "ignore"))})
	}
	Quit run
}

/// A run of incident rows c1 to c<total>, the first <right> of them right. Returns the run.
Method IncidentRun(right As %Integer, total As %Integer) As %String [ Private ]
{
	Set run = ..NewRun()
	For i = 1:1:total {
		Do ..Row(run, ..N("c"_i), {"Outcome": "", "CauseCategory": "data_format_change", "ElementAtFault": ($Select(i '> right: "OrderDate", 1: "CustomerId"))})
	}
	Quit run
}

/// A score as text: "<right> of <total> share <share> met <met>", with null for a share or met that is null and - for no met.
ClassMethod Line(score As %DynamicObject) As %String [ Private ]
{
	Set share = $Select(score.%GetTypeOf("share") = "null": "null", 1: score.share)
	Set met = $Select(score.%GetTypeOf("met") = "null": "null", score.%IsDefined("met"): score.%Get("met"), 1: "-")
	Quit score.right_" of "_score.total_" share "_share_" met "_met
}

/// The scored cases as "<case>:<right>" joined by semicolons.
ClassMethod Rights(report As %DynamicObject) As %String [ Private ]
{
	Set text = ""
	Set iterator = report.cases.%GetIterator()
	While iterator.%GetNext(, .one) {
		Set text = text_$Select(text = "": "", 1: ";")_one.case_":"_one.%Get("right")
	}
	Quit text
}

/// The member of each entry of the array, joined by the separator (a comma by default); with no key, the entries themselves.
ClassMethod Names(array As %DynamicArray, key As %String, separator As %String = ",") As %String [ Private ]
{
	Set text = ""
	Set iterator = array.%GetIterator()
	While iterator.%GetNext(, .one) {
		Set text = text_$Select(text = "": "", 1: separator)_$Select(key = "": one, 1: $Select($IsObject(one): one.%Get(key), 1: ""))
	}
	Quit text
}

/// The boolean member of each entry of the array as 1 or 0, joined by commas.
ClassMethod Booleans(array As %DynamicArray, key As %String) As %String [ Private ]
{
	Set text = ""
	Set iterator = array.%GetIterator()
	While iterator.%GetNext(, .one) {
		Set text = text_$Select(text = "": "", 1: ",")_(+one.%Get(key))
	}
	Quit text
}

/// The strings of the array joined by line breaks.
ClassMethod Texts(array As %DynamicArray) As %String [ Private ]
{
	Set text = ""
	Set iterator = array.%GetIterator()
	While iterator.%GetNext(, .one) {
		Set text = text_$Select(text = "": "", 1: $Char(10))_one
	}
	Quit text
}

}
