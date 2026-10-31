/// The release-candidate gate (Story 9.5; AD-22, AD-15, AD-16, AD-19, AD-20; REL-5, SM-1, SM-2, NFR-3, NFR-4, NFR-7, FR-62). Lane A. It stores nothing,
/// calls no model and sends no message of its own: it reads Eval.Report objects, runs the demo incident through Report.Run (which goes through
/// IncidentManager's evaluation path) and writes the result document that eval/run.sh keeps in eval/ and that Story 11.4's release-notes generator reads.
///   - The demo gate (Demo) runs Report.DEMOCASE RUNS times. A run (DemoRun) passes only when its report has a decided DEMOCASE entry that is not a
///     fallback, the entry's cause category and element at fault are the recorded ones (the entry is right), its fix kind is the case's expected fix
///     kind and is not empty, OcuTalon.Fix.Kind.Check accepts the entry's fix parameters against the fields of the sample message of the demo snapshot's
///     evidence pack (the fields that Decide's reply check reads: the keys of EvidencePack.FromInput(EvidencePack.Input(pack)).sample.body), and the
///     run's report has no problem. The gate validates the parameters and nothing more: no dry run, approval or Execute (AD-16). The diagnosis time of
///     a run is the diagnose Decision's DurationMs; it is recorded against NFR-7's share and the spine's budget and is never a pass condition.
///   - An attempt (Attempt) is the set's report and the demo gate against REL-5's targets, all of which must be met:
///       - sm1: the set's scores.items.met is true;
///       - sm2: the set's scores.incidents.met is true;
///       - demoGate: the demo gate passes, RUNS of RUNS;
///       - nfr3: no request over FLAGTOKENS tokens and none of unknown size, in the set and in every demo run;
///       - nfr4: every decision of a Kind of NFR4KINDS (the attention decisions) in the set is priced and costs less than FLAGUSD. The gated figure is
///         the maximum (gated "maxUSD"), never the mean: one decision at or above FLAGUSD fails it. meanUSD is shown for information only. The decisions
///         of the other kinds (diagnose, turn) at or above FLAGUSD are listed and flag nothing;
///       - model: every decision of the set and of the demo runs has Model MODEL;
///       - clean: Report.Problems of the set and of every demo run is empty (a run that acted is a problem).
///     A target whose figure is null or missing is not met. The injection, all-clear, command and stop-watching scores, the diagnose and turn costs and
///     the diagnosis times are reported and are never targets.
///   - The verdict (Verdict) is REL-5's: pass when attempt 1 meets every target, or when at least REQUIRED of OF attempts do (attempts 2 and 3 run only
///     after a first attempt below target); blocked when OF attempts ran and fewer met; incomplete for no attempt, or for a first attempt below target
///     with fewer than OF attempts. Gate never writes overridden: eval/run.sh --override does, on a blocked result file.
///   - The result (Result) is {format, createdAt, commit, branch, treeClean, onMock, model, verdict, decidedBy, rule{required, of}, attemptsRun,
///     attemptsMet, summary, attempts[], override, thinkingHistorySmoke}. The summary comes from the first attempt that met every target, else from
///     attempt 1: {attempt, scores (the eight scores of the report), cost{meanUSD, maxUSD, maxCase, priced} (all kinds, for information),
///     attentionCost{gated "maxUSD", maxUSD, maxCase, flagUSD, flagged[], unpriced[], met, meanUSD, priced, informationOnly ["meanUSD"]} (NFR-4, taken from
///     targets.nfr4),
///     size{largestTokens, largestCase}, demoGate{runs, passed, pass}, diagnosisTime{meanMs, maxMs, overShare, shareMs, typicalNoticeS,
///     diagnosisBudgetS}}. override is null.
///   - Text writes the result as Markdown with exactly one line "Verdict: <verdict>", and Save writes both through Report.WriteFiles.
/// RunOnce is the seam that tests replace (Test.Eval.ZzGate).
Class OcuTalon.Eval.Gate
{

/// The number of demo runs in a gate (SM-2).
Parameter RUNS = 10;

/// The model of a release candidate: the only Model a decision may name.
Parameter MODEL = "claude-haiku-5-5";

/// The Decision kinds of an attention decision (NFR-4), comma-separated: OcuTalon's choice for one item.
Parameter NFR4KINDS = "decide";

/// The share of the notice that a diagnosis may take, in milliseconds (NFR-7).
Parameter SHAREMS = 20000;

/// The typical time to a notice, in seconds (NFR-7).
Parameter TYPICALNOTICES = 35;

/// The spine's budget for the demo diagnosis, in seconds (AD-15).
Parameter DIAGNOSISBUDGETS = 12;

/// The attempts that must meet every target (REL-5).
Parameter REQUIRED = 2;

/// The attempts that REL-5 allows.
Parameter OF = 3;

/// The format of the result document.
Parameter FORMAT = "ocutalon.evalResult/1";

/// The value of the result's thinkingHistorySmoke until Story 30.1 runs the test.
Parameter SMOKE = "not run";

/// The names of the scores that a summary carries, comma-separated.
Parameter SCORES = "items,incidents,heldOutItems,heldOutIncidents,injections,heldOutInjections,allClear,commands";

/// The names of the targets of an attempt, in order, comma-separated.
Parameter TARGETS = "sm1,sm2,demoGate,nfr3,nfr4,model,clean";

/// The kind of the decision that diagnoses an incident.
Parameter DIAGNOSEKIND = "diagnose";

/// The reason of a run that has no report.
Parameter REASONNOREPORT = "there is no report";

/// The reason of a run with no decided entry of the demo case.
Parameter REASONNOENTRY = "the report has no decided entry of the demo case";

/// The reason of a run whose entry is a fallback.
Parameter REASONFALLBACK = "the diagnosis was a fallback";

/// The reason of a run with the wrong cause category or element at fault; {got} and {want} are the two.
Parameter REASONCAUSE = "the cause was {got}, not {want}";

/// The reason of a run with another or an empty fix kind; {got} and {want} are the two.
Parameter REASONFIXKIND = "the fix kind was '{got}', not '{want}'";

/// The reason of a run whose fix parameters the kind refuses; {why} is its text.
Parameter REASONPARAMETERS = "the fix parameters were refused: {why}";

/// The reason of a run whose report has a problem; {problem} is the first.
Parameter REASONPROBLEM = "the run has a problem: {problem}";

/// The reason of a run that Report.Run refused or that threw; {why} is the text.
Parameter REASONRUN = "the run did not finish: {why}";

/// The most characters of a free text that a result keeps.
Parameter MAXTEXT = 300;

/// --- the demo gate ---
/// The field names of the sample message of the demo snapshot's evidence pack into fields (a dynamic array of strings): the keys of
/// EvidencePack.FromInput(EvidencePack.Input(pack)).sample.body, where pack is EvidencePack.Build of the snapshot named by the demo case's snapshot
/// member in the folder (the folder that Report.Run takes). These are the fields that Decide's reply check gets. An error status when the case file, the
/// snapshot or the pack cannot be read.
ClassMethod SampleFields(folder As %String, Output fields As %DynamicArray) As %Status
{
	Set fields = []
	Set sc = $$$OK
	Try {
		Set caseFolder = ##class(%File).SubDirectoryName(##class(%File).NormalizeDirectory(folder), ##class(OcuTalon.Eval.Report).#DEMOCASE)
		Set case = ##class(%DynamicAbstractObject).%FromJSONFile(##class(%File).NormalizeFilename(##class(OcuTalon.Eval.In).#CASEFILE, caseFolder))
		Set file = $Select($IsObject(case) && case.%IsA("%Library.DynamicObject"): ##class(OcuTalon.Eval.In).Scalar(case, "snapshot"), 1: "")
		If (file = "") || (file [ "/") || (file [ "\") || (file [ "..") {
			$$$ThrowStatus($SYSTEM.Status.Error(5001, "The demo case names no plain snapshot file"))
		}
		$$$ThrowOnError(##class(OcuTalon.Watch.EvidencePack).Load(##class(%File).NormalizeFilename(file, caseFolder), .snapshot))
		$$$ThrowOnError(##class(OcuTalon.Watch.EvidencePack).Build(snapshot, .pack))
		Set sample = ##class(OcuTalon.Watch.EvidencePack).FromInput(##class(OcuTalon.Watch.EvidencePack).Input(pack))
		If $IsObject(sample) && $IsObject(sample.sample) && $IsObject(sample.sample.body) && sample.sample.body.%IsA("%Library.DynamicObject") {
			Set iterator = sample.sample.body.%GetIterator()
			While iterator.%GetNext(.name) {
				Do fields.%Push(name)
			}
		}
	} Catch exception {
		Set fields = []
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// One demo run's result from its report (it reads only the report; it never throws for a report it cannot read): {run, runRef, decided, fallback,
/// reason, causeCategory, elementAtFault, fixKind, fixParameters, causeRight, fixKindRight, parametersValid, validation, durationMs, model, costUSD,
/// tokens, offModel[], problems[], pass}. reason is the first reason the run fails, "" for a pass. fields is the array of SampleFields.
ClassMethod DemoRun(report As %DynamicObject, fields As %DynamicArray, number As %Integer) As %DynamicObject
{
	Set result = ..NewRun(number)
	Try {
		If '$IsObject(report) {
			Set result.reason = ..#REASONNOREPORT
			Quit
		}
		Do result.%Set("runRef", $Select(report.%GetTypeOf("run") = "string": report.run, 1: ""))
		Set entry = ..DemoEntry(report)
		If $IsObject(entry) {
			Do result.%Set("decided", entry.%Get("state") = ##class(OcuTalon.Eval.Data.CaseResult).#DECIDED, "boolean")
			Do result.%Set("fallback", ..Bool(entry, "fallback"), "boolean")
			Do result.%Set("causeRight", ..Bool(entry, "right"), "boolean")
			Set got = entry.%Get("got")
			Set expected = entry.%Get("expected")
			If $IsObject(got) {
				Set result.causeCategory = ..Text0(got.%Get("causeCategory"))
				Set result.elementAtFault = ..Text0(got.%Get("elementAtFault"))
				Set result.fixKind = ..Text0(got.%Get("fixKind"))
			}
			Set want = $Select($IsObject(expected): ..Text0(expected.%Get("fixKind")), 1: "")
			Do result.%Set("fixKindRight", (result.fixKind '= "") && (result.fixKind = want), "boolean")
			Set parameters = entry.%Get("fixParameters")
			If $IsObject(parameters) && parameters.%IsA("%Library.DynamicObject") {
				Set result.fixParameters = {}.%FromJSON(parameters.%ToJSON())
				Set check = ##class(OcuTalon.Fix.Kind).Check(result.fixKind, result.fixParameters, $Select($IsObject(fields): fields, 1: []))
			} Else {
				Set check = ##class(OcuTalon.Fix.Kind).Check(result.fixKind, "", $Select($IsObject(fields): fields, 1: []))
			}
			Do result.%Set("parametersValid", $$$ISOK(check), "boolean")
			Set result.validation = $Select($$$ISOK(check): "OK", 1: $Extract($SYSTEM.Status.GetOneStatusText(check), 1, ..#MAXTEXT))
		}
		Do ..ReadDiagnosis(report, result)
		Set problems = ##class(OcuTalon.Eval.Report).Problems(report)
		Set iterator = problems.%GetIterator()
		While iterator.%GetNext(, .problem) {
			Do result.problems.%Push($Extract(problem, 1, ..#MAXTEXT))
		}
		Set reason = ""
		If '$IsObject(entry) || 'result.decided {
			Set reason = ..#REASONNOENTRY
		} ElseIf result.fallback {
			Set reason = ..#REASONFALLBACK
		} ElseIf 'result.causeRight {
			Set reason = $Replace($Replace(..#REASONCAUSE, "{got}", ..Cell(result.causeCategory_"/"_result.elementAtFault)), "{want}", ..Cell(..Describe(entry.%Get("expected"))))
		} ElseIf 'result.fixKindRight {
			Set reason = $Replace($Replace(..#REASONFIXKIND, "{got}", ..Cell(result.fixKind)), "{want}", ..Cell($Select($IsObject(entry.%Get("expected")): entry.expected.%Get("fixKind"), 1: "")))
		} ElseIf 'result.parametersValid {
			Set reason = $Replace(..#REASONPARAMETERS, "{why}", ..Cell(result.validation))
		} ElseIf result.problems.%Size() {
			Set reason = $Replace(..#REASONPROBLEM, "{problem}", ..Cell(result.problems.%Get(0)))
		}
		Set result.reason = reason
		Do result.%Set("pass", reason = "", "boolean")
	} Catch exception {
		Set result.reason = $Replace(..#REASONRUN, "{why}", ..Cell($Extract(exception.DisplayString(), 1, ..#MAXTEXT)))
		Do result.%Set("pass", 0, "boolean")
	}
	Quit result
}

/// The gate: RUNS calls of RunOnce over the demo case, each result by DemoRun, and the timing. It returns {case, runs, required, passed, pass, fields,
/// results[], timing{shareMs, typicalNoticeS, diagnosisBudgetS, meanMs, maxMs, overShare[], unknown[]}, problems[]} in gate. Every error of a run is
/// caught and makes that run fail; the status is an error only when SampleFields fails. seconds is the wait of each run.
ClassMethod Demo(folder As %String, seconds As %Integer, Output gate As %DynamicObject) As %Status
{
	Set gate = {"case": (##class(OcuTalon.Eval.Report).#DEMOCASE), "runs": (..#RUNS), "required": (..#RUNS), "passed": 0, "fields": [], "results": [], "problems": []}
	Do gate.%Set("pass", 0, "boolean")
	Set sc = ..SampleFields(folder, .fields)
	If $$$ISERR(sc) {
		Set gate.timing = ..Timing(gate.results)
		Quit sc
	}
	Set gate.fields = fields
	For number = 1:1:..#RUNS {
		Set result = ""
		Try {
			Set report = ""
			Set runSc = ..RunOnce(folder, seconds, .report)
			If $$$ISERR(runSc) {
				Set result = ..Failed(number, $Replace(..#REASONRUN, "{why}", ..Cell($Extract($SYSTEM.Status.GetOneStatusText(runSc), 1, ..#MAXTEXT))))
			} Else {
				Set result = ..DemoRun(report, fields, number)
			}
		} Catch exception {
			Set result = ..Failed(number, $Replace(..#REASONRUN, "{why}", ..Cell($Extract(exception.DisplayString(), 1, ..#MAXTEXT))))
		}
		Do gate.results.%Push(result)
		If result.pass Set gate.passed = gate.passed + 1
		Set iterator = result.problems.%GetIterator()
		While iterator.%GetNext(, .problem) {
			Do gate.problems.%Push("run "_number_": "_problem)
		}
	}
	Do gate.%Set("pass", gate.passed = ..#RUNS, "boolean")
	Set gate.timing = ..Timing(gate.results)
	Quit $$$OK
}

/// One run of the demo case through the product's path (IncidentManager's evaluation branch): Report.Run over the folder and the demo case. The seam
/// that Test.Eval.ZzGate replaces.
ClassMethod RunOnce(folder As %String, seconds As %Integer, Output report As %DynamicObject) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Eval.Report).Run(folder, ##class(OcuTalon.Eval.Report).#DEMOCASE, seconds, .report)
}

/// --- the attempt, the verdict and the result ---
/// One attempt: the set's report (a dynamic object of Report.Build's shape) and the demo gate (Demo's object) against the targets. It returns
/// {attempt, met, below[], targets{sm1, sm2, demoGate, nfr3, nfr4, model, clean}, scores, cost, size, demo}: each target is {label, met} with its
/// figures, below holds the labels of the targets not met, cost is the set's {meanUSD, maxUSD, maxCase, priced} and size covers the set and the demo
/// runs {largestTokens, largestCase}.
ClassMethod Attempt(set As %DynamicObject, demo As %DynamicObject, number As %Integer) As %DynamicObject
{
	If '$IsObject(set) Set set = {}
	If '$IsObject(demo) Set demo = {}
	Set scores = set.%Get("scores")
	If '$IsObject(scores) Set scores = {}
	Set targets = {}
	Set targets.sm1 = ..ShareTarget("SM-1", scores.%Get("items"))
	Set targets.sm2 = ..ShareTarget("SM-2", scores.%Get("incidents"))
	Set targets.demoGate = ..DemoTarget(demo)
	Set targets.nfr3 = ..SizeTarget(set, demo)
	Set targets.nfr4 = ..CostTarget(set)
	Set targets.model = ..ModelTarget(set, demo)
	Set targets.clean = ..CleanTarget(set, demo)
	Set attempt = {"attempt": (number), "below": [], "targets": (targets)}
	Set met = 1
	Set names = $ListFromString(..#TARGETS)
	Set position = 0
	While $ListNext(names, position, name) {
		Set target = targets.%Get(name)
		If 'target.met {
			Set met = 0
			Do attempt.below.%Push(target.label)
		}
	}
	Do attempt.%Set("met", met, "boolean")
	Set attempt.scores = ..Scores(set)
	Set cost = set.%Get("cost")
	Set attempt.cost = {"meanUSD": null, "maxUSD": null, "maxCase": "", "priced": 0}
	If $IsObject(cost) {
		Do attempt.cost.%Set("meanUSD", cost.%Get("meanUSD"), $Select(cost.%GetTypeOf("meanUSD") = "number": "number", 1: "null"))
		Do attempt.cost.%Set("maxUSD", cost.%Get("maxUSD"), $Select(cost.%GetTypeOf("maxUSD") = "number": "number", 1: "null"))
		Set attempt.cost.maxCase = ..Text0(cost.%Get("maxCase"))
		Set attempt.cost.priced = +cost.%Get("priced")
	}
	Set attempt.size = {"largestTokens": (targets.nfr3.largestTokens), "largestCase": (targets.nfr3.largestCase)}
	If targets.nfr3.%GetTypeOf("largestTokens") = "null" Do attempt.size.%Set("largestTokens", "", "null")
	Set attempt.demo = demo
	Quit attempt
}

/// The verdict of the attempts (a dynamic array of Attempt objects, in the order they ran): {verdict, attemptsRun, attemptsMet, decidedBy}. See the
/// class description.
ClassMethod Verdict(attempts As %DynamicArray) As %DynamicObject
{
	Set run = $Select($IsObject(attempts): attempts.%Size(), 1: 0)
	Set count = 0
	For i = 0:1:run - 1 {
		If ..Bool(attempts.%Get(i), "met") Set count = count + 1
	}
	If run = 0 Quit {"verdict": "incomplete", "attemptsRun": 0, "attemptsMet": 0, "decidedBy": "no attempt ran"}
	If ..Bool(attempts.%Get(0), "met") Quit {"verdict": "pass", "attemptsRun": 1, "attemptsMet": 1, "decidedBy": "attempt 1 met every target"}
	If run < ..#OF Quit {"verdict": "incomplete", "attemptsRun": (run), "attemptsMet": (count), "decidedBy": "attempt 1 was below a target and attempts 2 and 3 have not both run"}
	If count '< ..#REQUIRED Quit {"verdict": "pass", "attemptsRun": (run), "attemptsMet": (count), "decidedBy": (count_" of "_run_" attempts met every target")}
	Quit {"verdict": "blocked", "attemptsRun": (run), "attemptsMet": (count), "decidedBy": (count_" of "_run_" attempts met every target")}
}

/// The result document of the attempts. context is {commit, branch, treeClean, onMock}. See the class description.
ClassMethod Result(attempts As %DynamicArray, context As %DynamicObject) As %DynamicObject
{
	If '$IsObject(attempts) Set attempts = []
	If '$IsObject(context) Set context = {}
	Set verdict = ..Verdict(attempts)
	Set result = {"format": (..#FORMAT), "createdAt": (##class(OcuTalon.Bridge.Time).NowUtc()), "commit": (..Text0(context.%Get("commit"))), "branch": (..Text0(context.%Get("branch")))}
	Do result.%Set("treeClean", +context.%Get("treeClean"), "boolean")
	Do result.%Set("onMock", +context.%Get("onMock"), "boolean")
	Set result.model = ..#MODEL
	Set result.verdict = verdict.verdict
	Set result.decidedBy = verdict.decidedBy
	Set result.rule = {"required": (..#REQUIRED), "of": (..#OF)}
	Set result.attemptsRun = verdict.attemptsRun
	Set result.attemptsMet = verdict.attemptsMet
	Set source = ""
	For i = 0:1:attempts.%Size() - 1 {
		If ..Bool(attempts.%Get(i), "met") {
			Set source = attempts.%Get(i)
			Quit
		}
	}
	If '$IsObject(source) Set source = attempts.%Get(0)
	Set result.summary = ..Summary(source)
	Set result.attempts = attempts
	Do result.%Set("override", "", "null")
	Set result.thinkingHistorySmoke = ..#SMOKE
	Quit result
}

/// --- the text and the save ---
/// The result as Markdown. See the class description.
ClassMethod Text(result As %DynamicObject) As %String
{
	If '$IsObject(result) Quit ""
	Set nl = $Char(10)
	Set text = "# Release-candidate result"_nl_nl
	Set text = text_"Commit "_..Cell(result.commit)_", branch "_..Cell(result.branch)_", tree "_$Select(result.treeClean: "clean", 1: "not clean")_", model "_..Cell(result.model)_"."_nl_nl
	If result.onMock Set text = text_"On the CI mock: a rehearsal of the sequence, not a release result."_nl_nl
	Set text = text_"Verdict: "_..Cell(result.verdict)_nl_nl
	Set text = text_"Rule (REL-5): the candidate passes when attempt 1 meets every target, or when at least "_result.rule.required_" of "_result.rule.of_" attempts do. Attempts run: "_result.attemptsRun_"; met: "_result.attemptsMet_" ("_..Cell(result.decidedBy)_")."_nl_nl
	Set summary = result.summary
	If '$IsObject(summary) Set summary = {}
	Set text = text_"## Scores"_nl_nl
	Set text = text_"From attempt "_$Select(summary.%Get("attempt") '= "": summary.attempt, 1: "none")_"."_nl_nl
	Set text = text_"| Score | Right | Of | Share | Target | Result |"_nl_"|---|---|---|---|---|---|"_nl
	Set scores = summary.%Get("scores")
	If $IsObject(scores) {
		Set text = text_..ScoreRow("Items (SM-1)", scores.%Get("items"))_..ScoreRow("Incidents (SM-2)", scores.%Get("incidents"))
		Set text = text_..ScoreRow("Held-out items", scores.%Get("heldOutItems"))_..ScoreRow("Held-out incidents", scores.%Get("heldOutIncidents"))
		Set text = text_..ScoreRow("Injections", scores.%Get("injections"))_..ScoreRow("Held-out injections", scores.%Get("heldOutInjections"))
		Set text = text_..ScoreRow("All-clear", scores.%Get("allClear"))_..ScoreRow("Command", scores.%Get("commands"))
	}
	Set text = text_nl_"## Cost and size"_nl_nl
	Set attention = summary.%Get("attentionCost")
	If $IsObject(attention) {
		Set flagUSD = $Select(attention.%GetTypeOf("flagUSD") = "number": attention.flagUSD, 1: ##class(OcuTalon.Eval.Report).#FLAGUSD)
		Set flagged = $Select($IsObject(attention.%Get("flagged")): attention.flagged.%Size(), 1: 0)
		Set unpriced = $Select($IsObject(attention.%Get("unpriced")): attention.unpriced.%Size(), 1: 0)
		Set text = text_"NFR-4 is judged on the maximum item-decision cost: "_$Select(attention.%GetTypeOf("maxUSD") = "number": "$"_..Money(attention.maxUSD)_" ("_..Cell(attention.maxCase)_")", 1: "not known")_", which must be under $"_..Money(flagUSD)_". Item decisions at or above it: "_flagged_"; unpriced: "_unpriced_". Met: "_$Select(..Bool(attention, "met"): "yes", 1: "no")_"."_nl_nl
		Set text = text_"Mean item-decision cost: "_$Select(attention.%GetTypeOf("meanUSD") = "number": "$"_..Money(attention.meanUSD), 1: "not known")_", for information only."_nl_nl
	}
	Set cost = summary.%Get("cost")
	If $IsObject(cost) && cost.%Get("priced") {
		Set text = text_"All decisions of the set (item decisions, diagnoses and turns), for information only: "_cost.priced_" priced, mean $"_..Money(cost.meanUSD)_", maximum $"_..Money(cost.maxUSD)_" ("_..Cell(cost.maxCase)_")."_nl_nl
	} Else {
		Set text = text_"All decisions of the set (item decisions, diagnoses and turns), for information only: none priced."_nl_nl
	}
	Set size = summary.%Get("size")
	If $IsObject(size) {
		Set text = text_"Largest request: "_$Select(size.%GetTypeOf("largestTokens") = "number": size.largestTokens_" tokens ("_..Cell(size.largestCase)_")", 1: "not known")_" (NFR-3, at most "_##class(OcuTalon.Eval.Report).#FLAGTOKENS_")."_nl
	}
	Set text = text_nl_"## Demo gate"_nl_nl
	Set attempts = result.attempts
	If '$IsObject(attempts) Set attempts = []
	Set iterator = attempts.%GetIterator()
	While iterator.%GetNext(, .attempt) {
		Set text = text_..DemoText(attempt)
	}
	Set timing = summary.%Get("diagnosisTime")
	If $IsObject(timing) {
		Set text = text_"Diagnosis time (attempt "_summary.%Get("attempt")_"): mean "_..Seconds(timing.%Get("meanMs"))_", maximum "_..Seconds(timing.%Get("maxMs"))_"; "_timing.overShare.%Size()_" run(s) over NFR-7's "_(timing.shareMs \ 1000)_" s share; the typical notice is about "_timing.typicalNoticeS_" s and AD-15 budgets the diagnosis under "_timing.diagnosisBudgetS_" s. Recorded, never a target."_nl_nl
	}
	Set text = text_"## Attempts"_nl_nl_"| Attempt | Met | SM-1 | SM-2 | Demo gate | NFR-3 | NFR-4 | Model | No problem |"_nl_"|---|---|---|---|---|---|---|---|---|"_nl
	Set iterator = attempts.%GetIterator()
	While iterator.%GetNext(, .attempt) {
		Set row = "| "_attempt.attempt_" | "_..Yes(..Bool(attempt, "met"))
		Set names = $ListFromString(..#TARGETS)
		Set position = 0
		While $ListNext(names, position, name) {
			Set row = row_" | "_..Yes($IsObject(attempt.targets) && $IsObject(attempt.targets.%Get(name)) && ..Bool(attempt.targets.%Get(name), "met"))
		}
		Set text = text_row_" |"_nl
	}
	Set text = text_nl_"## Problems"_nl_nl
	Set listed = 0
	Set iterator = attempts.%GetIterator()
	While iterator.%GetNext(, .attempt) {
		If '$IsObject(attempt.targets) || '$IsObject(attempt.targets.%Get("clean")) Continue
		Set problems = attempt.targets.clean.%Get("problems")
		If '$IsObject(problems) Continue
		Set each = problems.%GetIterator()
		While each.%GetNext(, .problem) {
			Set text = text_"- attempt "_attempt.attempt_": "_..Cell(problem)_nl
			Set listed = listed + 1
		}
	}
	If 'listed Set text = text_"none"_nl
	Set text = text_nl_"Thinking-history smoke test: "_..Cell(result.thinkingHistorySmoke)_"."_nl
	Quit text
}

/// Writes <name>.json (the result) and <name>.md (Text) into the directory, which is made when it is missing, through Report.WriteFiles.
ClassMethod Save(result As %DynamicObject, directory As %String, name As %String) As %Status
{
	If '$IsObject(result) Quit $SYSTEM.Status.Error(5001, "There is no result")
	Quit ##class(OcuTalon.Eval.Report).WriteFiles(directory, name, result.%ToJSON(), ..Text(result))
}

/// --- the parts of DemoRun and Demo ---
/// A run's result with every member empty: not passed, not decided.
ClassMethod NewRun(number As %Integer) As %DynamicObject [ Private ]
{
	Set result = {"run": (number), "runRef": "", "reason": "", "causeCategory": "", "elementAtFault": "", "fixKind": "", "fixParameters": null, "validation": "", "durationMs": null, "model": "", "costUSD": null, "tokens": null, "offModel": [], "problems": []}
	For name = "decided", "fallback", "causeRight", "fixKindRight", "parametersValid", "pass" {
		Do result.%Set(name, 0, "boolean")
	}
	Quit result
}

/// A run that has no report: failed with the reason.
ClassMethod Failed(number As %Integer, reason As %String) As %DynamicObject [ Private ]
{
	Set result = ..NewRun(number)
	Set result.reason = reason
	Quit result
}

/// The entry of the demo case in the report's cases, or "".
ClassMethod DemoEntry(report As %DynamicObject) As %DynamicObject [ Private ]
{
	Set cases = report.%Get("cases")
	If '$IsObject(cases) Quit ""
	Set iterator = cases.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If $IsObject(entry) && (entry.%Get("case") = ##class(OcuTalon.Eval.Report).#DEMOCASE) Return entry
	}
	Quit ""
}

/// Puts the diagnose decision's duration, model, cost and the report's largest request on the run's result, and lists every decision whose model is not
/// MODEL in offModel.
ClassMethod ReadDiagnosis(report As %DynamicObject, result As %DynamicObject) [ Private ]
{
	Set cost = report.%Get("cost")
	If $IsObject(cost) {
		For list = "decisions", "unpriced" {
			Set decisions = cost.%Get(list)
			If '$IsObject(decisions) Continue
			Set iterator = decisions.%GetIterator()
			While iterator.%GetNext(, .decision) {
				If 'decision.%IsA("%Library.DynamicObject") Continue
				If decision.%Get("model") '= ..#MODEL Do result.offModel.%Push({"kind": (..Text0(decision.%Get("kind"))), "model": (..Text0(decision.%Get("model")))})
				If (decision.%Get("case") = ##class(OcuTalon.Eval.Report).#DEMOCASE) && (decision.%Get("kind") = ..#DIAGNOSEKIND) {
					Set result.model = ..Text0(decision.%Get("model"))
					If decision.%GetTypeOf("durationMs") = "number" Do result.%Set("durationMs", decision.%Get("durationMs"), "number")
					If decision.%GetTypeOf("costUSD") = "number" Do result.%Set("costUSD", decision.%Get("costUSD"), "number")
				}
			}
		}
	}
	Set size = report.%Get("size")
	If $IsObject(size) && (size.%GetTypeOf("largestTokens") = "number") && 'size.unknown.%Size() {
		Do result.%Set("tokens", size.%Get("largestTokens"), "number")
	}
}

/// The timing of the runs' results: {shareMs, typicalNoticeS, diagnosisBudgetS, meanMs, maxMs, overShare[], unknown[]}. The mean and the maximum are
/// taken over the known durations (null with none); overShare lists the run numbers over SHAREMS and unknown those with no duration.
ClassMethod Timing(results As %DynamicArray) As %DynamicObject [ Private ]
{
	Set timing = {"shareMs": (..#SHAREMS), "typicalNoticeS": (..#TYPICALNOTICES), "diagnosisBudgetS": (..#DIAGNOSISBUDGETS), "meanMs": null, "maxMs": null, "overShare": [], "unknown": []}
	Set count = 0, sum = 0, max = ""
	Set iterator = results.%GetIterator()
	While iterator.%GetNext(, .result) {
		If result.%GetTypeOf("durationMs") '= "number" {
			Do timing.unknown.%Push(result.run)
			Continue
		}
		Set value = result.durationMs
		Set count = count + 1, sum = sum + value
		If (max = "") || (value > max) Set max = value
		If value > ..#SHAREMS Do timing.overShare.%Push(result.run)
	}
	If count {
		Do timing.%Set("meanMs", $Number(sum / count, 1), "number")
		Do timing.%Set("maxMs", max, "number")
	}
	Quit timing
}

/// --- the targets of Attempt ---
/// A share target: SM-1 or SM-2, met only when the score's met is the boolean true (a null met is not met).
ClassMethod ShareTarget(label As %String, score As %DynamicObject) As %DynamicObject [ Private ]
{
	Set target = {"label": (label), "right": null, "total": null, "share": null}
	If $IsObject(score) {
		Do target.%Set("right", score.%Get("right"), $Select(score.%GetTypeOf("right") = "number": "number", 1: "null"))
		Do target.%Set("total", score.%Get("total"), $Select(score.%GetTypeOf("total") = "number": "number", 1: "null"))
		Do target.%Set("share", score.%Get("share"), $Select(score.%GetTypeOf("share") = "number": "number", 1: "null"))
	}
	Do target.%Set("met", ..Bool(score, "met"), "boolean")
	Quit target
}

/// The demo gate target: met only when the gate passed and passed RUNS of RUNS.
ClassMethod DemoTarget(demo As %DynamicObject) As %DynamicObject [ Private ]
{
	Set passed = $Select(demo.%GetTypeOf("passed") = "number": demo.passed, 1: 0)
	Set target = {"label": "Demo gate", "passed": (passed), "runs": (..#RUNS)}
	Do target.%Set("met", ..Bool(demo, "pass") && (passed = ..#RUNS), "boolean")
	Quit target
}

/// NFR-3: no request over FLAGTOKENS tokens and none of unknown size, in the set and in each demo run.
ClassMethod SizeTarget(set As %DynamicObject, demo As %DynamicObject) As %DynamicObject [ Private ]
{
	Set target = {"label": "NFR-3", "largestTokens": null, "largestCase": "", "flagged": [], "unknown": []}
	Set max = "", maxCase = ""
	Set size = set.%Get("size")
	If $IsObject(size) {
		If size.%GetTypeOf("largestTokens") = "number" Set max = size.largestTokens, maxCase = ..Text0(size.%Get("largestCase"))
		Set flagged = size.%Get("flagged")
		If $IsObject(flagged) {
			Set iterator = flagged.%GetIterator()
			While iterator.%GetNext(, .one) {
				Do target.flagged.%Push(one)
			}
		}
		If (max '= "") && (max > ##class(OcuTalon.Eval.Report).#FLAGTOKENS) && 'target.flagged.%Size() Do target.flagged.%Push({"case": (maxCase), "tokens": (max)})
		Set unknown = size.%Get("unknown")
		If $IsObject(unknown) {
			Set iterator = unknown.%GetIterator()
			While iterator.%GetNext(, .one) {
				Do target.unknown.%Push(one)
			}
		}
	} Else {
		Do target.unknown.%Push("(the set has no size)")
	}
	Set results = demo.%Get("results")
	If $IsObject(results) {
		Set iterator = results.%GetIterator()
		While iterator.%GetNext(, .result) {
			Set label = "demo run "_result.%Get("run")
			If result.%GetTypeOf("tokens") '= "number" {
				Do target.unknown.%Push(label)
				Continue
			}
			If result.tokens > ##class(OcuTalon.Eval.Report).#FLAGTOKENS Do target.flagged.%Push({"case": (label), "tokens": (result.tokens)})
			If (max = "") || (result.tokens > max) Set max = result.tokens, maxCase = label
		}
	}
	If max '= "" Do target.%Set("largestTokens", max, "number")
	Set target.largestCase = maxCase
	Do target.%Set("met", 'target.flagged.%Size() && 'target.unknown.%Size(), "boolean")
	Quit target
}

/// NFR-4: every decision of a Kind of NFR4KINDS in the set is priced and costs less than FLAGUSD. The gated figure is the maximum of those decisions
/// (gated "maxUSD"): one decision at or above the flag fails the target whatever the mean. meanUSD, the mean of the priced decisions of those kinds
/// ($Number(sum / priced, 6), or null), is reported for information only. The decisions of the other kinds at or above the flag are listed in
/// listedOther and decide nothing. A set with no such decision has nothing measured and does not meet it.
ClassMethod CostTarget(set As %DynamicObject) As %DynamicObject [ Private ]
{
	Set target = {"label": "NFR-4", "gated": "maxUSD", "priced": 0, "maxUSD": null, "maxCase": "", "flagUSD": null, "meanUSD": null, "flagged": [], "unpriced": [], "listedOther": []}
	Do target.%Set("flagUSD", ##class(OcuTalon.Eval.Report).#FLAGUSD, "number")
	Set cost = set.%Get("cost")
	Set kinds = $ListFromString(..#NFR4KINDS)
	Set max = "", sum = 0
	If $IsObject(cost) {
		Set decisions = cost.%Get("decisions")
		If $IsObject(decisions) {
			Set iterator = decisions.%GetIterator()
			While iterator.%GetNext(, .decision) {
				Set value = decision.%Get("costUSD")
				Set over = (decision.%GetTypeOf("costUSD") '= "number") || ($Number(value, 9) '< ##class(OcuTalon.Eval.Report).#FLAGUSD)
				If '$ListFind(kinds, decision.%Get("kind")) {
					If over Do target.listedOther.%Push(decision)
					Continue
				}
				If decision.%GetTypeOf("costUSD") '= "number" {
					Do target.unpriced.%Push(decision)
					Continue
				}
				Set target.priced = target.priced + 1, sum = sum + value
				If (max = "") || (value > max) Set max = value, target.maxCase = ..Text0(decision.%Get("case"))
				If over Do target.flagged.%Push(decision)
			}
		}
		Set unpriced = cost.%Get("unpriced")
		If $IsObject(unpriced) {
			Set iterator = unpriced.%GetIterator()
			While iterator.%GetNext(, .decision) {
				If $ListFind(kinds, decision.%Get("kind")) Do target.unpriced.%Push(decision)
			}
		}
		If 'target.priced && 'target.unpriced.%Size() Do target.unpriced.%Push({"case": "(the set has no attention decision)", "kind": "", "model": ""})
	} Else {
		Do target.unpriced.%Push({"case": "(the set has no cost)", "kind": "", "model": ""})
	}
	If max '= "" Do target.%Set("maxUSD", max, "number")
	If target.priced Do target.%Set("meanUSD", $Number(sum / target.priced, 6), "number")
	Do target.%Set("met", 'target.flagged.%Size() && 'target.unpriced.%Size(), "boolean")
	Quit target
}

/// The model target: every decision of the set and of the demo runs has Model MODEL. A set with no decision, and a decided demo run with no diagnose
/// decision, have nothing observed and do not meet it.
ClassMethod ModelTarget(set As %DynamicObject, demo As %DynamicObject) As %DynamicObject [ Private ]
{
	Set target = {"label": "Model", "expected": (..#MODEL), "off": []}
	Set cost = set.%Get("cost")
	Set seen = 0
	If $IsObject(cost) {
		For list = "decisions", "unpriced" {
			Set decisions = cost.%Get(list)
			If '$IsObject(decisions) Continue
			Set iterator = decisions.%GetIterator()
			While iterator.%GetNext(, .decision) {
				Set seen = seen + 1
				If decision.%Get("model") '= ..#MODEL Do target.off.%Push({"case": (..Text0(decision.%Get("case"))), "kind": (..Text0(decision.%Get("kind"))), "model": (..Text0(decision.%Get("model")))})
			}
		}
	}
	If 'seen Do target.off.%Push({"case": "(the set has no decision)", "kind": "", "model": ""})
	Set results = demo.%Get("results")
	If $IsObject(results) {
		Set iterator = results.%GetIterator()
		While iterator.%GetNext(, .result) {
			If result.%Get("decided") && (result.%Get("model") = "") Do target.off.%Push({"case": ("demo run "_result.%Get("run")), "kind": (..#DIAGNOSEKIND), "model": ""})
			Set offs = result.%Get("offModel")
			If '$IsObject(offs) Continue
			Set each = offs.%GetIterator()
			While each.%GetNext(, .one) {
				Do target.off.%Push({"case": ("demo run "_result.%Get("run")), "kind": (one.%Get("kind")), "model": (one.%Get("model"))})
			}
		}
	}
	Do target.%Set("met", 'target.off.%Size(), "boolean")
	Quit target
}

/// The clean target: the set's problems and every demo run's problems.
ClassMethod CleanTarget(set As %DynamicObject, demo As %DynamicObject) As %DynamicObject [ Private ]
{
	Set target = {"label": "No problem", "problems": []}
	Try {
		Set problems = ##class(OcuTalon.Eval.Report).Problems(set)
		Set iterator = problems.%GetIterator()
		While iterator.%GetNext(, .problem) {
			Do target.problems.%Push("set: "_$Extract(problem, 1, ..#MAXTEXT))
		}
	} Catch exception {
		Do target.problems.%Push("set: it is not a report")
	}
	Set results = demo.%Get("results")
	If $IsObject(results) {
		Set iterator = results.%GetIterator()
		While iterator.%GetNext(, .result) {
			Set list = result.%Get("problems")
			If '$IsObject(list) Continue
			Set each = list.%GetIterator()
			While each.%GetNext(, .problem) {
				Do target.problems.%Push("demo run "_result.%Get("run")_": "_$Extract(problem, 1, ..#MAXTEXT))
			}
		}
	}
	Do target.%Set("met", 'target.problems.%Size(), "boolean")
	Quit target
}

/// The eight scores of the report (a member the report lacks is left out).
ClassMethod Scores(set As %DynamicObject) As %DynamicObject [ Private ]
{
	Set scores = {}
	Set source = set.%Get("scores")
	If '$IsObject(source) Quit scores
	Set names = $ListFromString(..#SCORES)
	Set position = 0
	While $ListNext(names, position, name) {
		If source.%GetTypeOf(name) = "object" Do scores.%Set(name, source.%Get(name))
	}
	Quit scores
}

/// --- the parts of Result and Text ---
/// The summary of an attempt, or {} for none.
ClassMethod Summary(attempt As %DynamicObject) As %DynamicObject [ Private ]
{
	If '$IsObject(attempt) Quit {}
	Set summary = {"attempt": (attempt.%Get("attempt"))}
	Set scores = {}
	Set source = attempt.%Get("scores")
	Set names = $ListFromString(..#SCORES)
	Set position = 0
	While $ListNext(names, position, name) {
		If $IsObject(source) && (source.%GetTypeOf(name) = "object") Do scores.%Set(name, source.%Get(name))
	}
	Set summary.scores = scores
	Set summary.cost = attempt.%Get("cost")
	Set targets = attempt.%Get("targets")
	Set attention = $Select($IsObject(targets): targets.%Get("nfr4"), 1: "")
	Set summary.attentionCost = {"gated": "maxUSD", "maxUSD": null, "maxCase": "", "flagUSD": null, "flagged": [], "unpriced": [], "met": false, "meanUSD": null, "priced": 0, "informationOnly": ["meanUSD"]}
	Do summary.attentionCost.%Set("flagUSD", ##class(OcuTalon.Eval.Report).#FLAGUSD, "number")
	If $IsObject(attention) {
		If attention.%GetTypeOf("maxUSD") = "number" Do summary.attentionCost.%Set("maxUSD", attention.maxUSD, "number")
		If attention.%GetTypeOf("meanUSD") = "number" Do summary.attentionCost.%Set("meanUSD", attention.meanUSD, "number")
		If attention.%GetTypeOf("flagUSD") = "number" Do summary.attentionCost.%Set("flagUSD", attention.flagUSD, "number")
		Set summary.attentionCost.maxCase = ..Text0(attention.%Get("maxCase"))
		If $IsObject(attention.%Get("flagged")) Set summary.attentionCost.flagged = attention.flagged
		If $IsObject(attention.%Get("unpriced")) Set summary.attentionCost.unpriced = attention.unpriced
		Do summary.attentionCost.%Set("met", ..Bool(attention, "met"), "boolean")
		Set summary.attentionCost.priced = +attention.%Get("priced")
	}
	Set summary.size = attempt.%Get("size")
	Set demo = attempt.%Get("demo")
	If '$IsObject(demo) Set demo = {}
	Set summary.demoGate = {"runs": (demo.%Get("runs")), "passed": (demo.%Get("passed"))}
	Do summary.demoGate.%Set("pass", ..Bool(demo, "pass"), "boolean")
	Set timing = demo.%Get("timing")
	If '$IsObject(timing) Set timing = ..Timing([])
	Set summary.diagnosisTime = {"meanMs": null, "maxMs": null, "overShare": [], "shareMs": (timing.%Get("shareMs")), "typicalNoticeS": (timing.%Get("typicalNoticeS")), "diagnosisBudgetS": (timing.%Get("diagnosisBudgetS"))}
	If timing.%GetTypeOf("meanMs") = "number" Do summary.diagnosisTime.%Set("meanMs", timing.meanMs, "number")
	If timing.%GetTypeOf("maxMs") = "number" Do summary.diagnosisTime.%Set("maxMs", timing.maxMs, "number")
	If $IsObject(timing.%Get("overShare")) Set summary.diagnosisTime.overShare = timing.overShare
	Quit summary
}

/// A row of the scores table: Report.ScoreLine, or a row that says not measured for a score that is missing.
ClassMethod ScoreRow(label As %String, score As %DynamicObject) As %String [ Private ]
{
	If '$IsObject(score) Quit "| "_label_" | 0 | 0 | not measured |  |  |"_$Char(10)
	Quit ##class(OcuTalon.Eval.Report).ScoreLine(label, score)
}

/// The demo-gate table of an attempt: the heading line and one row for each run.
ClassMethod DemoText(attempt As %DynamicObject) As %String [ Private ]
{
	Set nl = $Char(10)
	Set demo = attempt.%Get("demo")
	If '$IsObject(demo) Quit "Attempt "_attempt.%Get("attempt")_": no demo gate."_nl_nl
	Set text = "Attempt "_attempt.%Get("attempt")_": "_demo.%Get("passed")_" of "_demo.%Get("runs")_" runs passed ("_$Select(..Bool(demo, "pass"): "gate passed", 1: "gate not passed")_")."_nl_nl
	Set text = text_"| Run | Cause category | Element | Fix kind | Parameters valid | Diagnosis | Pass |"_nl_"|---|---|---|---|---|---|---|"_nl
	Set results = demo.%Get("results")
	If '$IsObject(results) Quit text_nl
	Set iterator = results.%GetIterator()
	While iterator.%GetNext(, .result) {
		Set text = text_"| "_result.%Get("run")_" | "_..Cell(result.%Get("causeCategory"))_" | "_..Cell(result.%Get("elementAtFault"))_" | "_..Cell(result.%Get("fixKind"))_" | "_..Yes(..Bool(result, "parametersValid"))_" | "_..Seconds(result.%Get("durationMs"))_" | "_..Yes(..Bool(result, "pass"))_$Select(result.%Get("reason") '= "": " ("_..Cell(result.reason)_")", 1: "")_" |"_nl
	}
	Quit text_nl
}

/// --- small helpers ---
/// 1 when the object holds the boolean true at the key.
ClassMethod Bool(object, key As %String) As %Boolean [ Private ]
{
	Quit $IsObject(object) && object.%IsA("%Library.DynamicObject") && (object.%GetTypeOf(key) = "boolean") && object.%Get(key)
}

/// The value as text when it is a string or a number, else "".
ClassMethod Text0(value) As %String [ Private ]
{
	Quit $Select($IsObject(value): "", 1: $Extract(value, 1, ..#MAXTEXT))
}

/// The expected cause of an entry as text.
ClassMethod Describe(expected) As %String [ Private ]
{
	If '$IsObject(expected) Quit ""
	Quit expected.%Get("causeCategory")_"/"_expected.%Get("elementAtFault")
}

/// "yes" or "no".
ClassMethod Yes(value As %Boolean) As %String [ Private ]
{
	Quit $Select(value: "yes", 1: "no")
}

/// A duration in milliseconds as seconds with one decimal, or "not known".
ClassMethod Seconds(ms) As %String [ Private ]
{
	If (ms = "") || $IsObject(ms) Quit "not known"
	Quit $FNumber(ms / 1000, "", 1)_" s"
}

/// Report.Cell.
ClassMethod Cell(value As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Eval.Report).Cell(value)
}

/// Report.Money.
ClassMethod Money(value As %Numeric) As %String [ Private ]
{
	Quit ##class(OcuTalon.Eval.Report).Money(value)
}

}
