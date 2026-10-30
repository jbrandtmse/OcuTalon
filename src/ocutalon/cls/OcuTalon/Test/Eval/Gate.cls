/// Tests of the release-candidate gate (Story 9.5; AD-22, AD-15, AD-16; REL-5, SM-1, SM-2, NFR-3, NFR-4, NFR-7). WARM-SAFE and in memory: they use synthetic
/// report objects of Eval.Report.Build's shape, the recorded demo snapshot of the evaluation folder (/opt/ocutalon/eval/) for the sample fields, and
/// Test.Eval.ZzGate for the gate's loop, so they start no production, send no message and save no row. They clear ^OcuTalonTest("EvalGate") before and
/// after each test, and make one folder below the manager's Temp directory for TestSave.
///   - TestSampleFields: the sample fields hold OrderDate and equal the keys of the sample body of the pack built from the snapshot; a folder with no
///     demo case is an error;
///   - TestDemoRunPasses and TestDemoRunFails: a run passes with the mock's parameters, and each failure (the wrong cause or element, another or empty
///     fix kind, a field not in the sample, an unregistered format, one format twice, a fallback, no decided entry, a problem, a run that acted, no
///     report) fails it with its reason;
///   - TestDemoLoop: Demo calls the run exactly RUNS times; ten good runs pass, and one bad, refused, thrown or empty run gives nine and no pass; a folder
///     with no demo case is an error status and no call;
///   - (QA) TestDemoRunReadsTheDiagnoseDecision: the time, model and cost of a run are those of the demo case's diagnose decision among others of another
///     kind or case, an unpriced diagnose decision gives a time and no cost, and another model in a turn decision is listed and misses the model target;
///   - TestDemoTiming: the mean and the maximum are over the known durations, 20,001 ms is over the share and 20,000 is not, and a run with none is unknown;
///   - TestTargets: each of the seven targets flipped alone and on its edge (100,000 tokens, 0.000999 and 0.001 USD, a null met);
///   - TestNFR4Kinds: a diagnose or turn decision at 0.002 USD keeps NFR-4 met and is listed; an unpriced decide does not meet it;
///   - TestVerdict: the nine cases of REL-5's rule, from no attempt to three;
///   - TestResult, TestText and TestSave: the result document, its Markdown (a blocked result's Verdict line is the one --override requires) and its files.
Class OcuTalon.Test.Eval.Gate Extends %UnitTest.TestCase
{

/// The case that holds the demo incident.
Parameter DEMO = "orders-date-format";

/// The folder of a test, below the manager's Temp directory, with a trailing separator.
Property Folder As %String(MAXLEN = 500);

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("EvalGate")
	Set base = ##class(%File).NormalizeDirectory("Temp", $SYSTEM.Util.ManagerDirectory())
	Set ..Folder = ##class(%File).NormalizeDirectory("zzgate"_$Translate($Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 12), "-_", "ab"), base)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("EvalGate")
	If ..Folder '= "" Do ##class(%File).RemoveDirectoryTree(..Folder)
	Quit $$$OK
}

/// The fields hold OrderDate and are the keys of the sample body that Decide's reply check reads; a folder with no demo case is an error and gives no field.
Method TestSampleFields()
{
	Set sc = ##class(OcuTalon.Eval.Gate).SampleFields(##class(OcuTalon.Eval.In).#FOLDER, .fields)
	Do $$$AssertStatusOK(sc, "the fields of the recorded demo snapshot are read")
	Set names = ..Join(fields)
	Do $$$AssertTrue($ListFind($ListFromString(names), "OrderDate"), "the sample fields hold OrderDate: "_names)
	Do $$$AssertTrue(fields.%Size() > 1, "and other fields of the sample body")
	Do $$$AssertStatusOK(##class(OcuTalon.Watch.EvidencePack).Load(##class(%File).NormalizeFilename("snapshot.json", ##class(%File).NormalizeDirectory(..#DEMO, ##class(OcuTalon.Eval.In).#FOLDER)), .snapshot), "the snapshot is loaded")
	Do $$$AssertStatusOK(##class(OcuTalon.Watch.EvidencePack).Build(snapshot, .pack), "the pack is built")
	Set body = ##class(OcuTalon.Watch.EvidencePack).FromInput(##class(OcuTalon.Watch.EvidencePack).Input(pack)).sample.body
	Set want = ""
	Set iterator = body.%GetIterator()
	While iterator.%GetNext(.key) {
		Set want = want_$Select(want = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(names, want, "and equal the keys of FromInput(Input(pack)).sample.body")
	Set sc = ##class(OcuTalon.Eval.Gate).SampleFields(..Folder, .none)
	Do $$$AssertTrue($$$ISERR(sc), "a folder with no demo case is an error")
	Do $$$AssertEquals(none.%Size(), 0, "and gives no field")
}

/// A run with the mock's parameters passes, with its time, model, cost and request size.
Method TestDemoRunPasses()
{
	Set result = ##class(OcuTalon.Eval.Gate).DemoRun(..GoodReport(), ..Fields(), 4)
	Do $$$AssertEquals(result.reason, "", "no reason")
	Do $$$AssertTrue(result.pass, "the run passes")
	Do $$$AssertEquals(result.run_"|"_result.runRef, "4|zzdemo", "it names its number and the report's run")
	Do $$$AssertEquals(result.decided_"|"_result.fallback_"|"_result.causeRight_"|"_result.fixKindRight_"|"_result.parametersValid, "1|0|1|1|1", "decided, no fallback, the cause right, the fix kind right and the parameters valid")
	Do $$$AssertEquals(result.causeCategory_"|"_result.elementAtFault_"|"_result.fixKind, "data_format_change|OrderDate|repair_resend", "the diagnosis")
	Do $$$AssertEquals(result.fixParameters.field_"|"_result.fixParameters.sourceFormat_"|"_result.fixParameters.targetFormat, "OrderDate|MM/DD/YYYY|YYYY-MM-DD", "with its parameters")
	Do $$$AssertEquals(result.validation, "OK", "which the fix kind accepted")
	Do $$$AssertEquals(result.durationMs_"|"_result.model_"|"_result.costUSD_"|"_result.tokens, "4000|"_##class(OcuTalon.Eval.Gate).#MODEL_"|.0004|5000", "the diagnosis time, the model, the cost and the request size")
	Do $$$AssertEquals(result.problems.%Size()_"|"_result.offModel.%Size(), "0|0", "no problem and no other model")
	Do $$$AssertEquals(result.%GetTypeOf("pass")_"|"_result.%GetTypeOf("decided"), "boolean|boolean", "the flags are booleans in the JSON")
}

/// Each failure on its own: the run does not pass and its reason says why.
Method TestDemoRunFails()
{
	Set fields = ..Fields()
	Set report = ..GoodReport()
	Set report.cases.%Get(0).got.causeCategory = "unknown"
	Do report.cases.%Get(0).%Set("right", 0, "boolean")
	Do ..Fails(report, fields, "the cause was unknown/OrderDate, not data_format_change/OrderDate", "another cause category")
	Set report = ..GoodReport()
	Set report.cases.%Get(0).got.elementAtFault = "CustomerId"
	Do report.cases.%Get(0).%Set("right", 0, "boolean")
	Do ..Fails(report, fields, "the cause was data_format_change/CustomerId", "another element at fault")
	Set report = ..GoodReport()
	Set report.cases.%Get(0).got.fixKind = "restart_item"
	Do ..Fails(report, fields, "the fix kind was 'restart_item', not 'repair_resend'", "another fix kind")
	Set report = ..GoodReport()
	Set report.cases.%Get(0).got.fixKind = ""
	Do ..Fails(report, fields, "the fix kind was '', not 'repair_resend'", "an empty fix kind")
	Set report = ..GoodReport()
	Set report.cases.%Get(0).fixParameters.field = "NoSuchField"
	Do ..Fails(report, fields, "the fix parameters were refused: ", "a field that the sample lacks")
	Set report = ..GoodReport()
	Set report.cases.%Get(0).fixParameters.sourceFormat = "XX/XX/XXXX"
	Do ..Fails(report, fields, "not a registered format", "a format that is not registered")
	Set report = ..GoodReport()
	Set report.cases.%Get(0).fixParameters.targetFormat = "MM/DD/YYYY"
	Do ..Fails(report, fields, "are one format", "one format twice")
	Set report = ..GoodReport()
	Do report.cases.%Get(0).%Set("fixParameters", "", "null")
	Do ..Fails(report, fields, "the fix parameters were refused: ", "no fix parameters")
	Set report = ..GoodReport()
	Do report.cases.%Get(0).%Set("fallback", 1, "boolean")
	Do report.cases.%Get(0).%Set("right", 0, "boolean")
	Do ..Fails(report, fields, "the diagnosis was a fallback", "a fallback")
	Set report = ..GoodReport()
	Set report.cases.%Get(0).state = "sent"
	Do report.cases.%Get(0).%Set("right", 0, "boolean")
	Do ..Fails(report, fields, "the report has no decided entry of the demo case", "an entry that is still sent")
	Set report = ..GoodReport()
	Set report.cases = []
	Do ..Fails(report, fields, "the report has no decided entry of the demo case", "no entry")
	Set report = ..GoodReport()
	Do report.notComplete.%Push({"case": "x", "reason": "no cost"})
	Do ..Fails(report, fields, "the run has a problem: x: no cost", "a problem in the report")
	Set report = ..GoodReport()
	Set report.actions.fixRuns = 1
	Do ..Fails(report, fields, "the run has a problem: the run acted", "a run that acted")
	Do ..Fails("", fields, "there is no report", "no report")
	Do ..Fails({}, fields, "the run did not finish", "a report with no members")
	Do ..Fails(..GoodReport(), "", "the fix parameters were refused: ", "no sample fields")
}

/// (QA) The diagnosis time, model and cost are those of the demo case's diagnose decision, whatever else the report holds: a decision of another kind or of
/// another case, listed before or after it, does not stand in for it; a diagnose decision that is unpriced gives its time and no cost; and a decision of another kind
/// that ran on another model is listed in offModel and does not meet the model target.
Method TestDemoRunReadsTheDiagnoseDecision()
{
	Set model = ##class(OcuTalon.Eval.Gate).#MODEL
	Set demo = ##class(OcuTalon.Eval.Report).#DEMOCASE
	Set report = ..GoodReport()
	Set report.cost.decisions = []
	Do report.cost.decisions.%Push({"case": (demo), "kind": "decide", "ref": "zz1", "model": (model), "costUSD": 0.0001, "durationMs": 111})
	Do report.cost.decisions.%Push({"case": (demo), "kind": "diagnose", "ref": "zz3", "model": (model), "costUSD": 0.0004, "durationMs": 4000})
	Do report.cost.decisions.%Push({"case": "other-case", "kind": "diagnose", "ref": "zz2", "model": (model), "costUSD": 0.0002, "durationMs": 222})
	Do report.cost.decisions.%Push({"case": (demo), "kind": "turn", "ref": "zz4", "model": (model), "costUSD": 0.0003, "durationMs": 333})
	Set result = ##class(OcuTalon.Eval.Gate).DemoRun(report, ..Fields(), 1)
	Do $$$AssertTrue(result.pass, "the run passes: "_result.reason)
	Do $$$AssertEquals(result.durationMs_"|"_result.costUSD_"|"_result.model, "4000|.0004|"_model, "the time and the cost are those of the diagnose decision of the demo case")
	Set report = ..GoodReport()
	Set report.cost.decisions = []
	Do report.cost.unpriced.%Push({"case": (demo), "kind": "diagnose", "ref": "zz5", "model": (model), "durationMs": 7000})
	Set result = ##class(OcuTalon.Eval.Gate).DemoRun(report, ..Fields(), 1)
	Do $$$AssertEquals(result.durationMs_"|"_result.%GetTypeOf("costUSD")_"|"_result.model, "7000|null|"_model, "an unpriced diagnose decision gives its time and no cost")
	Set report = ..GoodReport()
	Do report.cost.decisions.%Push({"case": (demo), "kind": "turn", "ref": "zz6", "model": "claude-sonnet-5-5", "costUSD": 0.0003, "durationMs": 333})
	Set result = ##class(OcuTalon.Eval.Gate).DemoRun(report, ..Fields(), 1)
	Set off = $Select(result.offModel.%Size(): result.offModel.%Get(0), 1: {})
	Do $$$AssertEquals(result.offModel.%Size()_"|"_off.kind_"|"_off.model, "1|turn|claude-sonnet-5-5", "a decision of another kind on another model is listed")
	Do $$$AssertEquals(result.durationMs_"|"_result.model, "4000|"_model, "and the diagnose decision is still the one that the run reads")
	Do ..Prime(10)
	Set ^OcuTalonTest("EvalGate", 5) = report.%ToJSON()
	Do ##class(OcuTalon.Test.Eval.ZzGate).Demo(##class(OcuTalon.Eval.In).#FOLDER, 1, .gate)
	Do $$$AssertEquals(gate.passed, 10, "another model in a turn decision does not fail the gate itself")
	Do ..Only(..GoodSet(), gate, "Model", "but it does not meet the model target")
}

/// Demo calls the run exactly RUNS times and passes only at RUNS of RUNS; a bad, refused, thrown or empty run is one failure and never stops the others.
Method TestDemoLoop()
{
	Set folder = ##class(OcuTalon.Eval.In).#FOLDER
	Do ..Prime(10)
	Set sc = ##class(OcuTalon.Test.Eval.ZzGate).Demo(folder, 1, .gate)
	Do $$$AssertStatusOK(sc, "Demo succeeds")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("EvalGate", "calls")), 10, "the run is called exactly ten times")
	Do $$$AssertEquals(gate.runs_"|"_gate.required_"|"_gate.passed_"|"_gate.pass_"|"_gate.results.%Size(), "10|10|10|1|10", "ten good runs pass")
	Do $$$AssertEquals(gate.case, ##class(OcuTalon.Eval.Report).#DEMOCASE, "the gate names the case")
	Do $$$AssertTrue(gate.fields.%Size() > 0, "and holds the sample fields")
	Do $$$AssertEquals(gate.results.%Get(0).run_"|"_gate.results.%Get(9).run, "1|10", "the runs are numbered in order")
	Do $$$AssertEquals(gate.problems.%Size(), 0, "and there is no problem")
	Kill ^OcuTalonTest("EvalGate")
	Do ..Prime(10)
	Set report = ..GoodReport()
	Set report.cases.%Get(0).got.causeCategory = "unknown"
	Do report.cases.%Get(0).%Set("right", 0, "boolean")
	Set ^OcuTalonTest("EvalGate", 4) = report.%ToJSON()
	Do ##class(OcuTalon.Test.Eval.ZzGate).Demo(folder, 1, .gate)
	Do $$$AssertEquals(gate.passed_"|"_gate.pass, "9|0", "one wrong run gives nine and no pass")
	Do $$$AssertEquals(gate.results.%Get(3).pass_"|"_gate.results.%Get(2).pass, "0|1", "and it is the fourth")
	Kill ^OcuTalonTest("EvalGate")
	Do ..Prime(10)
	Set ^OcuTalonTest("EvalGate", "fail", 3) = "Report.Run refused: EvalIn is disabled"
	Do ##class(OcuTalon.Test.Eval.ZzGate).Demo(folder, 1, .gate)
	Do $$$AssertEquals(+$Get(^OcuTalonTest("EvalGate", "calls")), 10, "a refused run does not stop the loop")
	Do $$$AssertEquals(gate.passed_"|"_gate.pass, "9|0", "and gives nine and no pass")
	Do $$$AssertTrue(gate.results.%Get(2).reason [ "the run did not finish: Report.Run refused", "with its reason: "_gate.results.%Get(2).reason)
	Kill ^OcuTalonTest("EvalGate")
	Do ..Prime(10)
	Set ^OcuTalonTest("EvalGate", "throw", 7) = "the run threw"
	Set sc = ##class(OcuTalon.Test.Eval.ZzGate).Demo(folder, 1, .gate)
	Do $$$AssertStatusOK(sc, "a run that throws is not an error of Demo")
	Do $$$AssertEquals(gate.passed_"|"_gate.pass, "9|0", "it gives nine and no pass")
	Do $$$AssertTrue(gate.results.%Get(6).reason [ "the run threw", "with the exception's text: "_gate.results.%Get(6).reason)
	Kill ^OcuTalonTest("EvalGate")
	Do ..Prime(10)
	Kill ^OcuTalonTest("EvalGate", 10)
	Do ##class(OcuTalon.Test.Eval.ZzGate).Demo(folder, 1, .gate)
	Do $$$AssertEquals(gate.passed_"|"_gate.pass_"|"_gate.results.%Get(9).reason, "9|0|there is no report", "a run with no report fails")
	Kill ^OcuTalonTest("EvalGate")
	Set sc = ##class(OcuTalon.Test.Eval.ZzGate).Demo(..Folder, 1, .gate)
	Do $$$AssertTrue($$$ISERR(sc), "a folder with no demo case is an error status")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("EvalGate", "calls"))_"|"_gate.pass_"|"_gate.results.%Size(), "0|0|0", "with no run and no pass")
}

/// The mean and the maximum are over the known durations; 20,001 ms is over the share, 20,000 is not; a run with no duration is unknown.
Method TestDemoTiming()
{
	Do ..Prime(10)
	Set durations = $ListBuild(4000, 20000, 20001, "", 1000, 1000, 1000, 1000, 1000, 1000)
	For n = 1:1:10 {
		Set report = ..GoodReport()
		If $List(durations, n) = "" {
			Do report.cost.decisions.%Get(0).%Set("durationMs", "", "null")
		} Else {
			Set report.cost.decisions.%Get(0).durationMs = $List(durations, n)
		}
		Set ^OcuTalonTest("EvalGate", n) = report.%ToJSON()
	}
	Do ##class(OcuTalon.Test.Eval.ZzGate).Demo(##class(OcuTalon.Eval.In).#FOLDER, 1, .gate)
	Set timing = gate.timing
	Do $$$AssertEquals(timing.meanMs, 5555.7, "the mean is over the nine known durations")
	Do $$$AssertEquals(timing.maxMs, 20001, "and the maximum is the largest of them")
	Do $$$AssertEquals(..Join(timing.overShare), "3", "only the run at 20,001 ms is over the share")
	Do $$$AssertEquals(..Join(timing.unknown), "4", "the run with no duration is unknown")
	Do $$$AssertEquals(timing.shareMs_"|"_timing.typicalNoticeS_"|"_timing.diagnosisBudgetS, "20000|35|12", "the timing carries NFR-7's share, the typical notice and AD-15's budget")
	Do $$$AssertEquals(gate.results.%Get(0).durationMs_"|"_gate.results.%Get(3).%GetTypeOf("durationMs"), "4000|null", "each run holds its duration, or null")
	Do $$$AssertEquals(gate.passed_"|"_gate.pass, "10|1", "and the times are never a pass condition")
	Kill ^OcuTalonTest("EvalGate")
	Do ##class(OcuTalon.Test.Eval.ZzGate).Demo(##class(OcuTalon.Eval.In).#FOLDER, 1, .gate)
	Do $$$AssertEquals(gate.timing.%GetTypeOf("meanMs")_"|"_gate.timing.%GetTypeOf("maxMs")_"|"_gate.timing.unknown.%Size(), "null|null|10", "with no report every run is unknown and the mean and the maximum are null")
}

/// The attempt of a good set and a good gate meets every target; each target flipped alone, and on its edge.
Method TestTargets()
{
	Set number = 5
	Set attempt = ##class(OcuTalon.Eval.Gate).Attempt(..GoodSet(), ..NewGate(), number)
	Do $$$AssertEquals(attempt.attempt_"|"_attempt.met_"|"_attempt.below.%Size(), "5|1|0", "a good set and a good gate meet every target")
	Set labels = ""
	For name = "sm1", "sm2", "demoGate", "nfr3", "nfr4", "model", "clean" {
		Set labels = labels_$Select(labels = "": "", 1: ",")_attempt.targets.%Get(name).label
		Do $$$AssertTrue(attempt.targets.%Get(name).met, name_" is met")
	}
	Do $$$AssertEquals(labels, "SM-1,SM-2,Demo gate,NFR-3,NFR-4,Model,No problem", "the targets have their labels")
	Do $$$AssertEquals(attempt.cost.priced_"|"_attempt.cost.maxUSD_"|"_attempt.size.largestTokens_"|"_attempt.size.largestCase, "1|.0002|50000|c1", "the attempt carries the set's cost and the largest request")
	Do $$$AssertEquals(attempt.scores.%Size(), 8, "and the eight scores")

	// SM-1
	Set set = ..GoodSet()
	Do set.scores.items.%Set("met", 0, "boolean")
	Do ..Only(set, ..NewGate(), "SM-1", "SM-1 not met")
	Set set = ..GoodSet()
	Do set.scores.items.%Set("met", "", "null")
	Do ..Only(set, ..NewGate(), "SM-1", "a null met of SM-1 counts as not met")
	// SM-2
	Set set = ..GoodSet()
	Do set.scores.incidents.%Set("met", 0, "boolean")
	Do ..Only(set, ..NewGate(), "SM-2", "SM-2 not met")
	Set set = ..GoodSet()
	Do set.scores.incidents.%Set("met", "", "null")
	Do ..Only(set, ..NewGate(), "SM-2", "a null met of SM-2 counts as not met")
	// the demo gate: nine of ten
	Do ..Prime(10)
	Set report = ..GoodReport()
	Set report.cases.%Get(0).got.fixKind = "other"
	Set ^OcuTalonTest("EvalGate", 9) = report.%ToJSON()
	Do ##class(OcuTalon.Test.Eval.ZzGate).Demo(##class(OcuTalon.Eval.In).#FOLDER, 1, .gate)
	Do ..Only(..GoodSet(), gate, "Demo gate", "nine of ten demo runs do not meet the gate")
	// NFR-3: the edge, the set and the demo runs
	Set set = ..GoodSet()
	Do set.size.%Set("largestTokens", 100000, "number")
	Set attempt = ##class(OcuTalon.Eval.Gate).Attempt(set, ..NewGate(), 1)
	Do $$$AssertTrue(attempt.met, "exactly 100,000 tokens meets NFR-3")
	Set set = ..GoodSet()
	Do set.size.%Set("largestTokens", 100001, "number")
	Do ..Only(set, ..NewGate(), "NFR-3", "a request of 100,001 tokens in the set does not meet NFR-3")
	Set set = ..GoodSet()
	Do set.size.unknown.%Push("c2")
	Do ..Only(set, ..NewGate(), "NFR-3", "a request of unknown size in the set does not meet NFR-3")
	Do ..Prime(10)
	Set report = ..GoodReport()
	Do report.size.%Set("largestTokens", 100001, "number")
	Set ^OcuTalonTest("EvalGate", 2) = report.%ToJSON()
	Do ##class(OcuTalon.Test.Eval.ZzGate).Demo(##class(OcuTalon.Eval.In).#FOLDER, 1, .gate)
	Do $$$AssertEquals(gate.passed, 10, "a demo request over the limit does not fail the gate itself")
	Do ..Only(..GoodSet(), gate, "NFR-3", "a demo request of 100,001 tokens does not meet NFR-3")
	Kill ^OcuTalonTest("EvalGate")
	Do ..Prime(10)
	Set report = ..GoodReport()
	Do report.size.%Set("largestTokens", "", "null")
	Set ^OcuTalonTest("EvalGate", 2) = report.%ToJSON()
	Do ##class(OcuTalon.Test.Eval.ZzGate).Demo(##class(OcuTalon.Eval.In).#FOLDER, 1, .gate)
	Do ..Only(..GoodSet(), gate, "NFR-3", "a demo request of unknown size does not meet NFR-3")
	// NFR-4: the edge
	Set set = ..GoodSet()
	Do set.cost.decisions.%Get(0).%Set("costUSD", .000999, "number")
	Set attempt = ##class(OcuTalon.Eval.Gate).Attempt(set, ..NewGate(), 1)
	Do $$$AssertTrue(attempt.targets.nfr4.met, "0.000999 USD meets NFR-4")
	Set set = ..GoodSet()
	Do set.cost.decisions.%Get(0).%Set("costUSD", .001, "number")
	Do ..Only(set, ..NewGate(), "NFR-4", "0.001 USD does not meet NFR-4")
	Set set = ..GoodSet()
	Do set.cost.unpriced.%Push({"case": "c9", "kind": "decide", "ref": "x", "model": (##class(OcuTalon.Eval.Gate).#MODEL)})
	Do ..Only(set, ..NewGate(), "NFR-4", "an unpriced attention decision does not meet NFR-4")
	// the model
	Set set = ..GoodSet()
	Set set.cost.decisions.%Get(0).model = "claude-sonnet-5-5"
	Do ..Only(set, ..NewGate(), "Model", "another model in the set does not meet the model target")
	Set set = ..GoodSet()
	Set set.cost.decisions.%Get(0).model = ""
	Do ..Only(set, ..NewGate(), "Model", "a decision with no model does not meet it")
	Set set = ..GoodSet()
	Do set.cost.unpriced.%Push({"case": "c3", "kind": "diagnose", "ref": "u", "model": "claude-sonnet-5-5"})
	Do ..Only(set, ..NewGate(), "Model", "another model in the unpriced list does not meet the model target")
	Set set = ..GoodSet()
	Set set.cost.decisions = []
	Do ..Only(set, ..NewGate(), "NFR-4,Model", "a set with no decision has nothing measured, so NFR-4 and the model are not met")
	Do ..Prime(10)
	Set report = ..GoodReport()
	Set report.cost.decisions = []
	Set ^OcuTalonTest("EvalGate", 4) = report.%ToJSON()
	Do ##class(OcuTalon.Test.Eval.ZzGate).Demo(##class(OcuTalon.Eval.In).#FOLDER, 1, .gate)
	Do $$$AssertEquals(gate.passed, 10, "a demo run with no diagnose decision does not fail the gate itself")
	Do ..Only(..GoodSet(), gate, "Model", "a decided demo run with no diagnose decision has no model observed")
	Kill ^OcuTalonTest("EvalGate")
	Do ..Prime(10)
	Set report = ..GoodReport()
	Set report.cost.decisions.%Get(0).model = "claude-sonnet-5-5"
	Set ^OcuTalonTest("EvalGate", 6) = report.%ToJSON()
	Do ##class(OcuTalon.Test.Eval.ZzGate).Demo(##class(OcuTalon.Eval.In).#FOLDER, 1, .gate)
	Do $$$AssertEquals(gate.passed, 10, "another model in a demo run does not fail the gate itself")
	Do ..Only(..GoodSet(), gate, "Model", "another model in a demo run does not meet the model target")
	// clean
	Set set = ..GoodSet()
	Do set.notComplete.%Push({"case": "c1", "reason": "no cost"})
	Do ..Only(set, ..NewGate(), "No problem", "a problem of the set does not meet the clean target")
	Set set = ..GoodSet()
	Set set.actions.approvals = 1
	Do ..Only(set, ..NewGate(), "No problem", "a set that acted is a problem")
	Do ..Only({}, ..NewGate(), "SM-1,SM-2,NFR-3,NFR-4,Model,No problem", "an empty set reports the targets it cannot meet and throws nothing")
	Set attempt = ##class(OcuTalon.Eval.Gate).Attempt(..GoodSet(), "", 1)
	Do $$$AssertTrue('attempt.targets.demoGate.met, "no gate is not a pass")
	Set attempt = ##class(OcuTalon.Eval.Gate).Attempt({}, "", 1)
	Do $$$AssertEquals(attempt.size.%GetTypeOf("largestTokens"), "null", "a size that is not known is a JSON null in the attempt")
}

/// A diagnose or turn decision at 0.002 USD keeps NFR-4 met and is listed; an unpriced decide, in the unpriced list, does not meet it.
Method TestNFR4Kinds()
{
	Set set = ..GoodSet()
	Do set.cost.decisions.%Push({"case": "c1", "kind": "diagnose", "ref": "d", "model": (##class(OcuTalon.Eval.Gate).#MODEL), "costUSD": 0.002})
	Do set.cost.decisions.%Push({"case": "c2", "kind": "turn", "ref": "t", "model": (##class(OcuTalon.Eval.Gate).#MODEL), "costUSD": 0.002})
	Set attempt = ##class(OcuTalon.Eval.Gate).Attempt(set, ..NewGate(), 1)
	Set nfr4 = attempt.targets.nfr4
	Do $$$AssertTrue(nfr4.met && attempt.met, "diagnose and turn decisions at 0.002 keep NFR-4 met")
	Do $$$AssertEquals(nfr4.listedOther.%Size()_"|"_nfr4.flagged.%Size(), "2|0", "they are listed apart and flag nothing")
	Do $$$AssertEquals(nfr4.priced_"|"_nfr4.maxUSD_"|"_nfr4.maxCase, "1|.0002|c1", "and the figures are those of the attention decisions")
	Set set = ..GoodSet()
	Do set.cost.unpriced.%Push({"case": "c3", "kind": "diagnose", "ref": "u", "model": (##class(OcuTalon.Eval.Gate).#MODEL)})
	Set attempt = ##class(OcuTalon.Eval.Gate).Attempt(set, ..NewGate(), 1)
	Do $$$AssertTrue(attempt.targets.nfr4.met, "an unpriced diagnose decision does not decide NFR-4")
	Set set = ..GoodSet()
	Do set.cost.unpriced.%Push({"case": "c3", "kind": "decide", "ref": "u", "model": (##class(OcuTalon.Eval.Gate).#MODEL)})
	Set attempt = ##class(OcuTalon.Eval.Gate).Attempt(set, ..NewGate(), 1)
	Do $$$AssertTrue('attempt.targets.nfr4.met, "an unpriced decide does")
	Do $$$AssertEquals(attempt.targets.nfr4.unpriced.%Size(), 1, "and is listed")
}

/// REL-5's rule over every pattern of up to three attempts.
Method TestVerdict()
{
	Do ..VerdictIs("", "incomplete|0|0")
	Do ..VerdictIs("m", "pass|1|1")
	Do ..VerdictIs("n", "incomplete|1|0")
	Do ..VerdictIs("nm", "incomplete|2|1")
	Do ..VerdictIs("nmm", "pass|3|2")
	Do ..VerdictIs("nnm", "blocked|3|1")
	Do ..VerdictIs("nmn", "blocked|3|1")
	Do ..VerdictIs("nnn", "blocked|3|0")
	Do ..VerdictIs("mnn", "pass|1|1")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Gate).Verdict("").verdict, "incomplete", "no attempts array is incomplete")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Gate).Verdict([{"met": true}]).decidedBy, "attempt 1 met every target", "and attempt 1 explains itself")
}

/// The result document: every field, the summary's source attempt and a null override.
Method TestResult()
{
	Set bad = ..GoodSet()
	Do bad.scores.items.%Set("met", 0, "boolean")
	Set attempts = []
	Do attempts.%Push(##class(OcuTalon.Eval.Gate).Attempt(bad, ..NewGate(), 1))
	Do attempts.%Push(##class(OcuTalon.Eval.Gate).Attempt(..GoodSet(), ..NewGate(), 2))
	Do attempts.%Push(##class(OcuTalon.Eval.Gate).Attempt(..GoodSet(), ..NewGate(), 3))
	Set result = ##class(OcuTalon.Eval.Gate).Result(attempts, {"commit": "0123456789abcdef0123456789abcdef01234567", "branch": "feature/x", "treeClean": 1, "onMock": 0})
	Do $$$AssertEquals(result.format_"|"_result.model_"|"_result.verdict, "ocutalon.evalResult/1|claude-haiku-5-5|pass", "the format, the model and the verdict")
	Do $$$AssertEquals(result.commit_"|"_result.branch_"|"_result.%GetTypeOf("treeClean")_result.treeClean_"|"_result.%GetTypeOf("onMock")_result.onMock, "0123456789abcdef0123456789abcdef01234567|feature/x|boolean1|boolean0", "the commit, the branch and the booleans of the context")
	Do $$$AssertTrue(result.createdAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "createdAt is a UTC time: "_result.createdAt)
	Do $$$AssertEquals(result.rule.required_"|"_result.rule.of_"|"_result.attemptsRun_"|"_result.attemptsMet, "2|3|3|2", "the rule and the attempts run and met")
	Do $$$AssertEquals(result.attempts.%Size(), 3, "all three attempts are kept")
	Do $$$AssertEquals(result.override_"|"_result.%GetTypeOf("override"), "|null", "the override is null")
	Do $$$AssertEquals(result.thinkingHistorySmoke, "not run", "the thinking-history smoke test is not run")
	Set summary = result.summary
	Do $$$AssertEquals(summary.attempt, 2, "the summary comes from the first attempt that met every target")
	Set names = ""
	Set iterator = summary.scores.%GetIterator()
	While iterator.%GetNext(.key) {
		Set names = names_$Select(names = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(names, "items,incidents,heldOutItems,heldOutIncidents,injections,heldOutInjections,allClear,commands", "it holds all eight scores, the held-out ones among them")
	Do $$$AssertEquals(summary.scores.heldOutItems.total, 2, "a held-out score keeps its figures")
	Do $$$AssertEquals(summary.cost.priced_"|"_summary.cost.meanUSD_"|"_summary.cost.maxUSD, "1|.0002|.0002", "the mean and the maximum decision cost")
	Do $$$AssertEquals(summary.attentionCost.maxUSD_"|"_summary.attentionCost.maxCase_"|"_summary.attentionCost.flagged.%Size(), ".0002|c1|0", "the attention cost")
	Do $$$AssertEquals(summary.size.largestTokens_"|"_summary.size.largestCase, "50000|c1", "the largest request")
	Do $$$AssertEquals(summary.demoGate.runs_"|"_summary.demoGate.passed_"|"_summary.demoGate.pass, "10|10|1", "the demo gate")
	Do $$$AssertEquals(summary.diagnosisTime.meanMs_"|"_summary.diagnosisTime.maxMs_"|"_summary.diagnosisTime.overShare.%Size()_"|"_summary.diagnosisTime.shareMs_"|"_summary.diagnosisTime.typicalNoticeS_"|"_summary.diagnosisTime.diagnosisBudgetS, "4000|4000|0|20000|35|12", "and the diagnosis time")
	Set back = {}.%FromJSON(result.%ToJSON())
	Do $$$AssertEquals(back.summary.scores.heldOutIncidents.total, 1, "the document survives its JSON")
	// the summary of the first attempt, when none met every target
	Set attempts = []
	Do attempts.%Push(##class(OcuTalon.Eval.Gate).Attempt(bad, ..NewGate(), 1))
	Do attempts.%Push(##class(OcuTalon.Eval.Gate).Attempt(bad, ..NewGate(), 2))
	Do attempts.%Push(##class(OcuTalon.Eval.Gate).Attempt(bad, ..NewGate(), 3))
	Set result = ##class(OcuTalon.Eval.Gate).Result(attempts, {"commit": "abc", "branch": "unknown", "treeClean": 0, "onMock": 1})
	Do $$$AssertEquals(result.verdict_"|"_result.summary.attempt_"|"_result.treeClean_"|"_result.onMock, "blocked|1|0|1", "a blocked result summarises attempt 1")
	Set result = ##class(OcuTalon.Eval.Gate).Result([], {})
	Do $$$AssertEquals(result.verdict_"|"_result.attempts.%Size()_"|"_result.summary.%Size(), "incomplete|0|0", "no attempt is an incomplete result with an empty summary")
}

/// The Markdown: exactly one Verdict line, the tables, and the on-mock line only for an on-mock result; a blocked result's Verdict line is exactly
/// the line "Verdict: blocked" that eval/run.sh --override requires.
Method TestText()
{
	Set bad = ..GoodSet()
	Do bad.scores.items.%Set("met", 0, "boolean")
	Set attempts = []
	Do attempts.%Push(##class(OcuTalon.Eval.Gate).Attempt(bad, ..NewGate(), 1))
	Do attempts.%Push(##class(OcuTalon.Eval.Gate).Attempt(..GoodSet(), ..NewGate(), 2))
	Do attempts.%Push(##class(OcuTalon.Eval.Gate).Attempt(..GoodSet(), ..NewGate(), 3))
	Set result = ##class(OcuTalon.Eval.Gate).Result(attempts, {"commit": "abc123", "branch": "feature/x", "treeClean": 1, "onMock": 0})
	Set text = ##class(OcuTalon.Eval.Gate).Text(result)
	Set nl = $Char(10)
	Do $$$AssertEquals(..CountLines(text, "Verdict: "), 1, "there is exactly one Verdict line")
	Do $$$AssertTrue(text [ (nl_"Verdict: pass"_nl), "and it is Verdict: pass")
	Do $$$AssertEquals($Piece(text, nl, 1), "# Release-candidate result", "the text starts with its title")
	Do $$$AssertTrue(text [ "Commit abc123, branch feature/x, tree clean, model claude-haiku-5-5.", "the commit, branch, tree and model line")
	Do $$$AssertTrue(text '[ "On the CI mock", "a release result has no rehearsal line")
	Do $$$AssertTrue(text [ "Rule (REL-5)", "the rule line")
	Do $$$AssertTrue(text [ "| Items (SM-1) | 20 | 22 | 90.9% | 90% | met |", "the scores table, built with Report.ScoreLine")
	Do $$$AssertTrue(text [ "| Held-out items | 1 | 2 | 50.0% |  |  |", "with the held-out scores")
	Do $$$AssertTrue(text [ "Priced decisions: 1. Mean: $0.0002. Maximum: $0.0002 (c1).", "the cost line")
	Do $$$AssertTrue(text [ "Largest request: 50000 tokens (c1)", "the size line")
	Do $$$AssertTrue(text [ "| 1 | data_format_change | OrderDate | repair_resend | yes | 4.0 s | yes |", "a row of the demo-gate table")
	Do $$$AssertTrue(text [ "Attempt 1: 10 of 10 runs passed (gate passed).", "the demo-gate heading of each attempt")
	Do $$$AssertTrue(text [ "mean 4.0 s, maximum 4.0 s; 0 run(s) over NFR-7's 20 s share; the typical notice is about 35 s and AD-15 budgets the diagnosis under 12 s.", "the timing line")
	Do $$$AssertTrue(text [ "| 1 | no | no | yes | yes | yes | yes | yes | yes |", "the attempts table: attempt 1 missed SM-1")
	Do $$$AssertTrue(text [ "| 2 | yes | yes | yes | yes | yes | yes | yes | yes |", "and attempt 2 met every target")
	Do $$$AssertTrue(text [ ("## Problems"_nl_nl_"none"_nl), "no problem")
	Do $$$AssertTrue(text [ ("Thinking-history smoke test: not run."_nl), "the closing line")
	Set mock = ##class(OcuTalon.Eval.Gate).Result(attempts, {"commit": "abc123", "branch": "feature/x", "treeClean": 0, "onMock": 1})
	Set mockText = ##class(OcuTalon.Eval.Gate).Text(mock)
	Do $$$AssertTrue(mockText [ "On the CI mock: a rehearsal of the sequence, not a release result.", "an on-mock result says so")
	Do $$$AssertTrue(mockText [ "tree not clean", "and a tree that is not clean")
	Do $$$AssertEquals(..CountLines(mockText, "Verdict: "), 1, "still with one Verdict line")
	Set blocked = []
	For n = 1:1:3 {
		Do blocked.%Push(##class(OcuTalon.Eval.Gate).Attempt(bad, ..NewGate(), n))
	}
	Set blockedText = ##class(OcuTalon.Eval.Gate).Text(##class(OcuTalon.Eval.Gate).Result(blocked, {"commit": "abc123", "branch": "feature/x", "treeClean": 1, "onMock": 0}))
	Do $$$AssertEquals(..CountLines(blockedText, "Verdict: "), 1, "a blocked result has one Verdict line")
	Do $$$AssertTrue(blockedText [ (nl_"Verdict: blocked"_nl), "and it is exactly the line Verdict: blocked that eval/run.sh --override requires")
	Set withProblem = ..GoodSet()
	Do withProblem.notComplete.%Push({"case": "c|1", "reason": "no cost"})
	Set one = []
	Do one.%Push(##class(OcuTalon.Eval.Gate).Attempt(withProblem, ..NewGate(), 1))
	Set problemText = ##class(OcuTalon.Eval.Gate).Text(##class(OcuTalon.Eval.Gate).Result(one, {}))
	Do $$$AssertTrue(problemText [ "- attempt 1: set: c/1: no cost", "a problem is listed with its attempt, and a pipe is a slash")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Gate).Text(""), "", "no result gives no text")
}

/// Save writes the JSON and the Markdown into a new directory, and what it wrote reads back as the result and as Text; it refuses a name with a path.
Method TestSave()
{
	Set attempts = []
	Do attempts.%Push(##class(OcuTalon.Eval.Gate).Attempt(..GoodSet(), ..NewGate(), 1))
	Set result = ##class(OcuTalon.Eval.Gate).Result(attempts, {"commit": "abc", "branch": "b", "treeClean": 1, "onMock": 0})
	Set directory = ##class(%File).SubDirectoryName(..Folder, "zz-out")
	Do $$$AssertTrue('##class(%File).DirectoryExists(directory), "the directory is not there yet")
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Gate).Save(result, directory, "release-candidate"), "Save succeeds")
	Set json = ##class(%File).NormalizeFilename("release-candidate.json", directory), markdown = ##class(%File).NormalizeFilename("release-candidate.md", directory)
	Do $$$AssertTrue(##class(%File).Exists(json) && ##class(%File).Exists(markdown), "both files are written")
	If '##class(%File).Exists(json) || '##class(%File).Exists(markdown) Quit
	Set back = ##class(%DynamicAbstractObject).%FromJSONFile(json)
	Do $$$AssertEquals(back.%ToJSON(), result.%ToJSON(), "the JSON reads back equal to the result")
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set stream.Filename = markdown
	Set stream.TranslateTable = "UTF8"
	Do $$$AssertEquals(stream.Read(1000000), ##class(OcuTalon.Eval.Gate).Text(result), "the Markdown equals Text")
	Do $$$AssertTrue($$$ISERR(##class(OcuTalon.Eval.Gate).Save(result, directory, "../x")), "a name with a path is refused")
	Do $$$AssertTrue($$$ISERR(##class(OcuTalon.Eval.Gate).Save("", directory, "none")), "and so is no result")
}

/// --- helpers ---
/// The sample fields of a good run: the keys of a sample body that holds OrderDate.
ClassMethod Fields() As %DynamicArray [ Private ]
{
	Quit ["OrderDate", "OrderId", "CustomerId"]
}

/// A report of a clean demo run that is right: the entry, one diagnose decision of 4000 ms and a request of 5000 tokens.
ClassMethod GoodReport() As %DynamicObject [ Private ]
{
	Set report = {"run": "zzdemo", "cases": [], "cost": {"decisions": [], "unpriced": []}, "size": {"largestTokens": 5000, "largestCase": "orders-date-format", "flagged": [], "unknown": []}, "actions": {"approvals": 0, "commands": 0, "settingChanges": 0, "fixRuns": 0}, "injectionChecks": [], "skipped": [], "notComplete": [], "unscored": []}
	Set entry = {"case": "orders-date-format", "kind": "incident", "state": "decided"}
	Set entry.expected = {"causeCategory": "data_format_change", "elementAtFault": "OrderDate", "fixKind": "repair_resend"}
	Set entry.got = {"causeCategory": "data_format_change", "elementAtFault": "OrderDate", "fixKind": "repair_resend"}
	Set entry.fixParameters = {"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}
	Do entry.%Set("heldOut", 0, "boolean")
	Do entry.%Set("fallback", 0, "boolean")
	Do entry.%Set("right", 1, "boolean")
	Do report.cases.%Push(entry)
	Do report.cost.decisions.%Push({"case": "orders-date-format", "kind": "diagnose", "ref": "zzref", "model": "claude-haiku-5-5", "costUSD": 0.0004, "durationMs": 4000})
	Quit report
}

/// A report of a good set: SM-1 and SM-2 met, one priced attention decision of 0.0002 USD, a request of 50000 tokens and no problem.
ClassMethod GoodSet() As %DynamicObject [ Private ]
{
	Set set = {"run": "zzset", "scores": {}, "cases": [], "cost": {"decisions": [], "unpriced": [], "priced": 1, "meanUSD": 0.0002, "maxUSD": 0.0002, "maxCase": "c1", "flagAtUSD": 0.001, "flagged": []}, "size": {"largestTokens": 50000, "largestCase": "c1", "flagOverTokens": 100000, "flagged": [], "unknown": []}, "actions": {"approvals": 0, "commands": 0, "settingChanges": 0, "fixRuns": 0}, "injectionChecks": [], "skipped": [], "notComplete": [], "unscored": []}
	Do set.cases.%Push({"case": "c1", "kind": "item", "state": "decided"})
	Set set.scores.items = ..Share(20, 22, .9091, 1)
	Set set.scores.incidents = ..Share(9, 10, .9, 1, .8)
	Set set.scores.heldOutItems = ..Share(1, 2, .5)
	Set set.scores.heldOutIncidents = ..Share(1, 1, 1)
	Set set.scores.injections = ..Share(2, 2, 1)
	Set set.scores.heldOutInjections = ..Share(0, 0, "")
	Set set.scores.allClear = ..Share(0, 3, 0)
	Set set.scores.commands = ..Share(0, 1, 0)
	Do set.cost.decisions.%Push({"case": "c1", "kind": "decide", "ref": "zzd", "model": "claude-haiku-5-5", "costUSD": 0.0002, "durationMs": 900})
	Quit set
}

/// A share of the report's shape; with a met (1 or 0) it has the target (.9 unless one is given).
ClassMethod Share(right As %Integer, total As %Integer, share, met As %String = "", target As %String = .9) As %DynamicObject [ Private ]
{
	Set score = {"right": (right), "total": (total)}
	If share = "" {
		Do score.%Set("share", "", "null")
	} Else {
		Do score.%Set("share", share, "number")
	}
	If met '= "" {
		Do score.%Set("target", target, "number")
		Do score.%Set("met", met, "boolean")
	}
	Quit score
}

/// Primes the first count calls of the run with a good report.
ClassMethod Prime(count As %Integer) [ Private ]
{
	For n = 1:1:count {
		Set ^OcuTalonTest("EvalGate", n) = ..GoodReport().%ToJSON()
	}
}

/// The demo gate of ten good runs.
ClassMethod NewGate() As %DynamicObject [ Private ]
{
	Kill ^OcuTalonTest("EvalGate")
	Do ..Prime(10)
	Do ##class(OcuTalon.Test.Eval.ZzGate).Demo(##class(OcuTalon.Eval.In).#FOLDER, 1, .gate)
	Kill ^OcuTalonTest("EvalGate")
	Quit gate
}

/// The elements of an array (or the values of an iterator's array) joined by commas.
ClassMethod Join(array) As %String [ Private ]
{
	If '$IsObject(array) || 'array.%IsA("%Library.DynamicArray") Quit ""
	Set text = ""
	Set iterator = array.%GetIterator()
	While iterator.%GetNext(, .value) {
		Set text = text_$Select(text = "": "", 1: ",")_value
	}
	Quit text
}

/// Asserts that the report fails the demo run with a reason that holds the text.
Method Fails(report, fields As %DynamicArray, reason As %String, label As %String) [ Private ]
{
	Set result = ##class(OcuTalon.Eval.Gate).DemoRun(report, fields, 2)
	Do $$$AssertTrue('result.pass, label_": the run does not pass")
	Do $$$AssertTrue(result.reason [ reason, label_": the reason holds '"_reason_"': "_result.reason)
}

/// Asserts that the attempt misses exactly the targets with the labels (comma-separated) and so does not meet every target.
Method Only(set As %DynamicObject, gate As %DynamicObject, labels As %String, message As %String) [ Private ]
{
	Set attempt = ##class(OcuTalon.Eval.Gate).Attempt(set, gate, 1)
	Do $$$AssertEquals(..Join(attempt.below), labels, message)
	Do $$$AssertTrue('attempt.met, message_": the attempt is below target")
}

/// Asserts the verdict of attempts written as a string of m (met) and n (not met): "verdict|attempts run|attempts met".
Method VerdictIs(pattern As %String, expected As %String) [ Private ]
{
	Set attempts = []
	For i = 1:1:$Length(pattern) {
		Do attempts.%Push({"attempt": (i), "met": ($Extract(pattern, i) = "m")})
		Do attempts.%Get(i - 1).%Set("met", $Extract(pattern, i) = "m", "boolean")
	}
	Set verdict = ##class(OcuTalon.Eval.Gate).Verdict(attempts)
	Do $$$AssertEquals(verdict.verdict_"|"_verdict.attemptsRun_"|"_verdict.attemptsMet, expected, "the verdict of '"_pattern_"'")
}

/// The number of lines of the text that start with the prefix.
ClassMethod CountLines(text As %String, prefix As %String) As %Integer [ Private ]
{
	Set count = 0
	For i = 1:1:$Length(text, $Char(10)) {
		If $Extract($Piece(text, $Char(10), i), 1, $Length(prefix)) = prefix Set count = count + 1
	}
	Quit count
}

}
