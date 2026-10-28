/// The report of an evaluation run (AD-22, AD-30; SM-1, SM-2, NFR-3, NFR-4). Lane A. It reads the run's OcuTalon.Eval.Data.CaseResult rows and
/// the case files of the folder they came from, and stores nothing: the report is a %DynamicObject and its Markdown text, and Save writes both
/// as files.
///   - Scoring is in Build only. An item or injection row is right when it is decided, is not a fallback, and its Outcome equals the case's
///     expectation.outcome. An incident row is right when it is decided, is not a fallback, and its CauseCategory and ElementAtFault equal the
///     case's expectation.causeCategory and expectation.elementAtFault, ignoring case and leading and trailing spaces; the fix kind is shown and
///     not scored. A share is the right rows over all the run's rows of its kind, so a row still sent counts as not right. SM-1 is met when the
///     items are at least 9 in 10 and SM-2 when the incidents are at least 4 in 5; a kind with no row has a null share and a null met.
///   - The held-out cases are scored again on their own, with no target. A decided tell-now case that got Ignore or Digest is listed apart,
///     and so is every fallback.
///   - Cost and size come from the rows. Every priced decision (the decide or diagnose decision, and the untrusted turn) is listed with its
///     model, which is read from OcuTalon.Bridge.Data.Decision. The mean and the maximum are taken over the priced decisions, and a decision at
///     or above FLAGUSD is flagged. The largest request is the bridge's estimate, and a case over FLAGTOKENS is flagged.
///   - A case that Eval.In.Start skipped is listed with its kind and reason and counts in no score. A skip of a kind that EvalIn does not send yet
///     is notRunYet. A row that cannot be scored (no readable case.json, no expectation, a kind that Build does not score) is listed as unscored.
///   - Problems are the texts that fail a mock run: no row, a row not complete, a skip that is not notRunYet, and a row not scored.
/// The report: {run, folder, builtAt, scores{items, incidents, heldOutItems, heldOutIncidents}, cases[], tellNowMissed[], fallbacks[],
/// notComplete[], unscored[], skipped[], cost{decisions[], priced, meanUSD, maxUSD, maxCase, flagAtUSD, flagged[], unpriced[]},
/// size{largestTokens, largestCase, flagOverTokens, flagged[], unknown[]}}.
Class OcuTalon.Eval.Report
{

/// The kinds of case a case.json may hold, comma-separated.
Parameter CASEKINDS = "item,injection,all-clear,incident";

/// The kinds that are scored by outcome, and count in SM-1's items.
Parameter ITEMKINDS = "item,injection";

/// The kind that is scored by cause category and element at fault, and counts in SM-2's incidents.
Parameter INCIDENTKIND = "incident";

/// SM-1 as a fraction: the share of items that must be right.
Parameter ITEMTARGET = "9/10";

/// SM-2 as a fraction: the share of incidents that must be right.
Parameter INCIDENTTARGET = "4/5";

/// A decision at or above this cost in US dollars is flagged (NFR-4).
Parameter FLAGUSD = 0.001;

/// A request over this many tokens is flagged (NFR-3).
Parameter FLAGTOKENS = 100000;

/// The outcome of a tell-now case.
Parameter TELLNOW = "tellnow";

/// The outcomes that miss a tell-now case.
Parameter MISSEDOUTCOMES = "ignore,digest";

/// The problem of a run with no row.
Parameter PROBLEMNOCASE = "the run sent no case";

/// The problem of a call with no report.
Parameter PROBLEMNOREPORT = "there is no report";

/// Why a row is not complete: it is still sent.
Parameter REASONUNDECIDED = "not decided";

/// Why a row is not complete: it names no decision.
Parameter REASONNODECISION = "no decision";

/// Why a row is not complete: its decision has no cost.
Parameter REASONNOCOST = "no cost";

/// Why a row is not complete: its turn has no cost.
Parameter REASONNOTURNCOST = "no turn cost";

/// Why a row is not complete: it has no request size.
Parameter REASONNOSIZE = "no request size";

/// Why a row is not scored: its case file cannot be read.
Parameter REASONNOCASEFILE = "its case.json is missing or is not a JSON object";

/// Why a row is not scored: its case file lacks a field of the expectation; {field} is the field.
Parameter REASONNOEXPECTATION = "its case.json has no {field} in its expectation";

/// Why a row is not scored: the report does not score its kind; {kind} is the kind.
Parameter REASONKIND = "its kind is '{kind}', which the report does not score";

/// What the text says of a skipped case that EvalIn does not send yet.
Parameter NOTRUNYET = "not run until its story";

/// Builds the report of the run from its rows and the case files below the folder. skipped is the dynamic array of {case, reason} that
/// Eval.In.Start returned, or "" for none. It never throws for a case file it cannot read: the row goes into unscored.
ClassMethod Build(runRef As %String, folder As %String, skipped As %DynamicArray = "") As %DynamicObject
{
	Set folder = ##class(%File).NormalizeDirectory(folder)
	Set report = {"run": (runRef), "folder": (folder), "builtAt": (##class(OcuTalon.Bridge.Time).NowUtc()), "scores": {}, "cases": [], "tellNowMissed": [], "fallbacks": [], "notComplete": [], "unscored": [], "skipped": []}
	Set report.cost = {"decisions": [], "priced": 0, "meanUSD": null, "maxUSD": null, "maxCase": "", "flagAtUSD": null, "flagged": [], "unpriced": []}
	Do report.cost.%Set("flagAtUSD", ..#FLAGUSD, "number")
	Set report.size = {"largestTokens": null, "largestCase": "", "flagOverTokens": null, "flagged": [], "unknown": []}
	Do report.size.%Set("flagOverTokens", ..#FLAGTOKENS, "number")
	Kill tally
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT CaseName, State, DecisionRef, Outcome, Fallback, FallbackReason, CauseCategory, ElementAtFault, FixKind, CostUSD, TurnDecisionRef, TurnCostUSD, LargestRequestTokens FROM OcuTalon_Eval_Data.CaseResult WHERE RunRef = ? ORDER BY CaseName", runRef)
	If result.%SQLCODE < 0 Throw ##class(%Exception.SQL).CreateFromSQLCODE(result.%SQLCODE, result.%Message)
	While result.%Next() {
		Set row = {"case": (result.%Get("CaseName")), "state": (result.%Get("State")), "decisionRef": (result.%Get("DecisionRef")), "outcome": (result.%Get("Outcome")), "fallback": (+result.%Get("Fallback")), "fallbackReason": (result.%Get("FallbackReason")), "causeCategory": (result.%Get("CauseCategory")), "elementAtFault": (result.%Get("ElementAtFault")), "fixKind": (result.%Get("FixKind")), "costUSD": (..Number(result.%Get("CostUSD"))), "turnDecisionRef": (result.%Get("TurnDecisionRef")), "turnCostUSD": (..Number(result.%Get("TurnCostUSD"))), "tokens": (..Number(result.%Get("LargestRequestTokens")))}
		Do ..Complete(report, row, .tally)
		Do ..Score(report, row, folder, .tally)
	}
	Do ..Finish(report, .tally)
	Do ..AddSkipped(report, skipped, folder)
	Quit report
}

/// The texts that fail a mock run, as a dynamic array of strings; empty when the run is clean.
ClassMethod Problems(report As %DynamicObject) As %DynamicArray
{
	Set problems = []
	If '$IsObject(report) {
		Do problems.%Push(..#PROBLEMNOREPORT)
		Quit problems
	}
	If report.cases.%Size() + report.unscored.%Size() = 0 Do problems.%Push(..#PROBLEMNOCASE)
	Set iterator = report.notComplete.%GetIterator()
	While iterator.%GetNext(, .one) {
		Do problems.%Push(one.case_": "_one.reason)
	}
	Set iterator = report.skipped.%GetIterator()
	While iterator.%GetNext(, .one) {
		If 'one.%Get("notRunYet") Do problems.%Push(one.case_": not sent: "_one.reason)
	}
	Set iterator = report.unscored.%GetIterator()
	While iterator.%GetNext(, .one) {
		Do problems.%Push(one.case_": not scored: "_one.reason)
	}
	Quit problems
}

/// The report as Markdown: the title, the scores, the held-out scores, the tell-now cases missed, the fallbacks, the cost (the mean, the
/// maximum, every priced decision with its case, kind, model and cost, the flagged and the unpriced ones), the size, the cases not complete
/// or not scored, the skipped cases and one table row for each scored case. Every free text goes through Cell.
ClassMethod Text(report As %DynamicObject, title As %String = "") As %String
{
	If '$IsObject(report) Quit ""
	Set nl = $Char(10)
	Set text = "# "_..Cell(title)_nl_nl_"Run "_report.run_" over "_..Cell(report.folder)_", built "_report.builtAt_"."_nl_nl
	Set scores = report.scores
	Set text = text_"## Scores"_nl_nl_"| Score | Right | Of | Share | Target | Result |"_nl_"|---|---|---|---|---|---|"_nl
	Set text = text_..ScoreLine("Items (SM-1)", scores.items)_..ScoreLine("Incidents (SM-2)", scores.incidents)
	Set text = text_..ScoreLine("Held-out items", scores.heldOutItems)_..ScoreLine("Held-out incidents", scores.heldOutIncidents)_nl
	Set text = text_"## Tell-now cases decided Ignore or Digest"_nl_nl
	Set text = text_..List(report.tellNowMissed, "{case}: decided {got}")
	Set text = text_nl_"## Fallbacks"_nl_nl
	Set text = text_..List(report.fallbacks, "{case}: {reason} (outcome {outcome})")
	Set cost = report.cost
	Set text = text_nl_"## Cost"_nl_nl_"Priced decisions: "_cost.priced_"."
	If cost.priced {
		Set text = text_" Mean: $"_..Money(cost.meanUSD)_". Maximum: $"_..Money(cost.maxUSD)_" ("_..Cell(cost.maxCase)_")."
	}
	Set text = text_nl_nl_..List(cost.decisions, "{case}, {kind}, {model}: ${costUSD}")
	Set text = text_nl_"Decisions at or above $"_..Money(cost.flagAtUSD)_":"_nl_nl_..List(cost.flagged, "{case}, {kind}, {model}: ${costUSD}")
	Set text = text_nl_"Unpriced decisions:"_nl_nl_..List(cost.unpriced, "{case}, {kind}, {model}")
	Set size = report.size
	Set text = text_nl_"## Request size"_nl_nl
	If size.%GetTypeOf("largestTokens") = "null" {
		Set text = text_"Largest request: not known."
	} Else {
		Set text = text_"Largest request: "_size.largestTokens_" tokens ("_..Cell(size.largestCase)_"), estimated by the bridge."
	}
	Set text = text_nl_nl_"Requests over "_size.flagOverTokens_" tokens:"_nl_nl_..List(size.flagged, "{case}: {tokens} tokens")
	Set text = text_nl_"Requests of unknown size:"_nl_nl_..List(size.unknown, "{case}")
	Set text = text_nl_"## Cases not complete"_nl_nl_..List(report.notComplete, "{case}: {reason}")
	Set text = text_nl_"## Cases not scored"_nl_nl_..List(report.unscored, "{case}: {reason}")
	Set text = text_nl_"## Cases skipped"_nl_nl
	If report.skipped.%Size() = 0 {
		Set text = text_"none"_nl
	} Else {
		Set iterator = report.skipped.%GetIterator()
		While iterator.%GetNext(, .one) {
			Set text = text_"- "_..Cell(one.case)_" ("_$Select(one.kind '= "": ..Cell(one.kind), 1: "kind not known")_"): "_..Cell(one.reason)_$Select(one.%Get("notRunYet"): " ["_..#NOTRUNYET_"]", 1: "")_nl
		}
	}
	Set text = text_nl_"## Cases"_nl_nl_"| Case | Kind | Held out | Expected | Got | Right |"_nl_"|---|---|---|---|---|---|"_nl
	Set iterator = report.cases.%GetIterator()
	While iterator.%GetNext(, .one) {
		Set text = text_"| "_..Cell(one.case)_" | "_..Cell(one.kind)_" | "_$Select(one.%Get("heldOut"): "yes", 1: "no")_" | "_..Cell(..Describe(one.expected))_" | "_..Cell(..Describe(one.got))_" | "_$Select(one.%Get("right"): "yes", 1: "no")_" |"_nl
	}
	Quit text
}

/// Writes <name>.json (the report) and <name>.md (Text) into the directory, which is made when it is missing.
ClassMethod Save(report As %DynamicObject, title As %String, directory As %String, name As %String) As %Status
{
	If '$IsObject(report) Quit $SYSTEM.Status.Error(5001, ..#PROBLEMNOREPORT)
	If (name = "") || (name [ "/") || (name [ "\") Quit $SYSTEM.Status.Error(5001, "The report needs a file name without a path")
	Set directory = ##class(%File).NormalizeDirectory(directory)
	If '##class(%File).DirectoryExists(directory) && '##class(%File).CreateDirectoryChain(directory) {
		Quit $SYSTEM.Status.Error(5001, "The report folder "_directory_" cannot be made")
	}
	Set sc = ..Write(##class(%File).NormalizeFilename(name_".json", directory), report.%ToJSON())
	If $$$ISERR(sc) Quit sc
	Quit ..Write(##class(%File).NormalizeFilename(name_".md", directory), ..Text(report, title))
}

/// A run: Eval.In.Start over the folder and the names, Wait for the seconds, and the report of the run. When Start fails (EvalIn is disabled)
/// the status is its error and report is "".
ClassMethod Run(folder As %String = {##class(OcuTalon.Eval.In).#FOLDER}, names As %String = "", seconds As %Integer = 180, Output report As %DynamicObject) As %Status
{
	Set report = ""
	Set sc = ##class(OcuTalon.Eval.In).Start(folder, names, .runRef, .sent, .skipped)
	If $$$ISERR(sc) Quit sc
	Do ##class(OcuTalon.Eval.In).Wait(runRef, seconds)
	Set report = ..Build(runRef, folder, skipped)
	Quit $$$OK
}

/// --- the parts of Build ---
/// What the row alone says: whether it is complete, its fallback, its decisions' cost and model, and its request size.
ClassMethod Complete(report As %DynamicObject, row As %DynamicObject, ByRef tally) [ Private ]
{
	Set name = row.case
	If row.state '= ##class(OcuTalon.Eval.Data.CaseResult).#DECIDED {
		Do ..NotComplete(report, name, ..#REASONUNDECIDED)
		Quit
	}
	If row.fallback Do report.fallbacks.%Push({"case": (name), "reason": (row.fallbackReason), "outcome": (row.outcome)})
	Set reasons = ""
	If row.decisionRef = "" {
		Set reasons = ..#REASONNODECISION
	} Else {
		Do ..AddDecision(report, name, row.decisionRef, "decide", row.costUSD, .tally)
		If row.costUSD = "" Set reasons = ..#REASONNOCOST
	}
	If row.turnDecisionRef '= "" {
		Do ..AddDecision(report, name, row.turnDecisionRef, "turn", row.turnCostUSD, .tally)
		If row.turnCostUSD = "" Set reasons = reasons_$Select(reasons = "": "", 1: "; ")_..#REASONNOTURNCOST
	}
	If row.tokens = "" {
		Do report.size.unknown.%Push(name)
		If row.decisionRef '= "" Set reasons = reasons_$Select(reasons = "": "", 1: "; ")_..#REASONNOSIZE
	} Else {
		If row.tokens > $Get(tally("size", "max"), -1) Set tally("size", "max") = row.tokens, tally("size", "case") = name
		If row.tokens > ..#FLAGTOKENS Do report.size.flagged.%Push({"case": (name), "tokens": (row.tokens)})
	}
	If reasons '= "" Do ..NotComplete(report, name, reasons)
}

/// Lists one decision of a case: with its cost it is priced and counts in the mean and the maximum, without it it is unpriced.
ClassMethod AddDecision(report As %DynamicObject, name As %String, ref As %String, defaultKind As %String, cost As %String, ByRef tally) [ Private ]
{
	Set decision = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(ref)
	Set entry = {"case": (name), "kind": ($Select($IsObject(decision) && (decision.Kind '= ""): decision.Kind, 1: defaultKind)), "ref": (ref), "model": ($Select($IsObject(decision): decision.Model, 1: ""))}
	If cost = "" {
		Do report.cost.unpriced.%Push(entry)
		Quit
	}
	Do entry.%Set("costUSD", cost, "number")
	Do report.cost.decisions.%Push(entry)
	Set tally("cost", "n") = $Get(tally("cost", "n")) + 1
	Set tally("cost", "sum") = $Get(tally("cost", "sum")) + cost
	If cost > $Get(tally("cost", "max"), -1) Set tally("cost", "max") = cost, tally("cost", "case") = name
	If cost '< ..#FLAGUSD Do report.cost.flagged.%Push(entry)
}

/// Lists a row that is not complete, with the reasons.
ClassMethod NotComplete(report As %DynamicObject, name As %String, reason As %String) [ Private ]
{
	Do report.notComplete.%Push({"case": (name), "reason": (reason)})
}

/// Scores the row against its case file: the case record, the tell-now list and the tallies; or lists the row as unscored.
ClassMethod Score(report As %DynamicObject, row As %DynamicObject, folder As %String, ByRef tally) [ Private ]
{
	Set name = row.case
	Set case = ..ReadCase(folder, name)
	If '$IsObject(case) {
		Do ..Unscored(report, name, ..#REASONNOCASEFILE)
		Quit
	}
	Set kind = ##class(OcuTalon.Eval.In).Scalar(case, "kind")
	Set expectation = case.%Get("expectation")
	If '$IsObject(expectation) || 'expectation.%IsA("%Library.DynamicObject") Set expectation = {}
	Set heldOut = (case.%GetTypeOf("heldOut") = "boolean") && case.%Get("heldOut")
	Set decided = (row.state = ##class(OcuTalon.Eval.Data.CaseResult).#DECIDED) && 'row.fallback
	If $ListFind($ListFromString(..#ITEMKINDS), kind) {
		Set expected = ##class(OcuTalon.Eval.In).Scalar(expectation, "outcome")
		If expected = "" {
			Do ..Unscored(report, name, $Replace(..#REASONNOEXPECTATION, "{field}", "outcome"))
			Quit
		}
		Set got = row.outcome
		Set right = decided && (got = expected)
		Do ..Tally(.tally, "items", right, heldOut, "heldOutItems")
		If decided && (expected = ..#TELLNOW) && $ListFind($ListFromString(..#MISSEDOUTCOMES), got) Do report.tellNowMissed.%Push({"case": (name), "got": (got)})
	} ElseIf kind = ..#INCIDENTKIND {
		Set category = ##class(OcuTalon.Eval.In).Scalar(expectation, "causeCategory")
		Set element = ##class(OcuTalon.Eval.In).Scalar(expectation, "elementAtFault")
		If (category = "") || (element = "") {
			Do ..Unscored(report, name, $Replace(..#REASONNOEXPECTATION, "{field}", $Select(category = "": "causeCategory", 1: "elementAtFault")))
			Quit
		}
		Set expected = {"causeCategory": (category), "elementAtFault": (element), "fixKind": (##class(OcuTalon.Eval.In).Scalar(expectation, "fixKind"))}
		Set got = {"causeCategory": (row.causeCategory), "elementAtFault": (row.elementAtFault), "fixKind": (row.fixKind)}
		Set right = decided && (..Same(row.causeCategory, category)) && (..Same(row.elementAtFault, element))
		Do ..Tally(.tally, "incidents", right, heldOut, "heldOutIncidents")
	} Else {
		Do ..Unscored(report, name, $Replace(..#REASONKIND, "{kind}", $Extract(kind, 1, 40)))
		Quit
	}
	Set entry = {"case": (name), "kind": (kind)}
	Do entry.%Set("heldOut", heldOut, "boolean")
	Do entry.%Set("state", row.state)
	Set entry.expected = expected
	Set entry.got = got
	Do entry.%Set("fallback", row.fallback, "boolean")
	Do entry.%Set("right", right, "boolean")
	Do report.cases.%Push(entry)
}

/// Lists a row that cannot be scored, with the reason.
ClassMethod Unscored(report As %DynamicObject, name As %String, reason As %String) [ Private ]
{
	Do report.unscored.%Push({"case": (name), "reason": (reason)})
}

/// Counts a scored row in its group and, when the case is held out, in the held-out group.
ClassMethod Tally(ByRef tally, group As %String, right As %Boolean, heldOut As %Boolean, heldOutGroup As %String) [ Private ]
{
	Set tally(group, "total") = $Get(tally(group, "total")) + 1
	If right Set tally(group, "right") = $Get(tally(group, "right")) + 1
	If 'heldOut Quit
	Set tally(heldOutGroup, "total") = $Get(tally(heldOutGroup, "total")) + 1
	If right Set tally(heldOutGroup, "right") = $Get(tally(heldOutGroup, "right")) + 1
}

/// The scores, the mean and the maximum cost and the largest request, from the tallies.
ClassMethod Finish(report As %DynamicObject, ByRef tally) [ Private ]
{
	Set report.scores = {"items": (..Share(+$Get(tally("items", "right")), +$Get(tally("items", "total")), ..#ITEMTARGET)), "incidents": (..Share(+$Get(tally("incidents", "right")), +$Get(tally("incidents", "total")), ..#INCIDENTTARGET)), "heldOutItems": (..Share(+$Get(tally("heldOutItems", "right")), +$Get(tally("heldOutItems", "total")))), "heldOutIncidents": (..Share(+$Get(tally("heldOutIncidents", "right")), +$Get(tally("heldOutIncidents", "total"))))}
	Set report.cost.priced = +$Get(tally("cost", "n"))
	If report.cost.priced {
		Do report.cost.%Set("meanUSD", $Number(tally("cost", "sum") / tally("cost", "n"), 6), "number")
		Do report.cost.%Set("maxUSD", tally("cost", "max"), "number")
		Set report.cost.maxCase = tally("cost", "case")
	}
	If $Data(tally("size", "max")) {
		Do report.size.%Set("largestTokens", tally("size", "max"), "number")
		Set report.size.largestCase = tally("size", "case")
	}
}

/// {right, total, share} and, with a target ("a/b"), {target, met}: the share and met are null with no row.
ClassMethod Share(right As %Integer, total As %Integer, target As %String = "") As %DynamicObject [ Private ]
{
	Set score = {"right": (right), "total": (total)}
	If total = 0 {
		Do score.%Set("share", "", "null")
	} Else {
		Do score.%Set("share", $Number(right / total, 4), "number")
	}
	If target = "" Quit score
	Set numerator = $Piece(target, "/", 1), denominator = $Piece(target, "/", 2)
	Do score.%Set("target", numerator / denominator, "number")
	If total = 0 {
		Do score.%Set("met", "", "null")
	} Else {
		Do score.%Set("met", (right * denominator) '< (total * numerator), "boolean")
	}
	Quit score
}

/// Lists the cases that Start skipped, each with the kind its case.json holds, when that can be read.
ClassMethod AddSkipped(report As %DynamicObject, skipped As %DynamicArray, folder As %String) [ Private ]
{
	If '$IsObject(skipped) Quit
	Set iterator = skipped.%GetIterator()
	While iterator.%GetNext(, .one) {
		If '$IsObject(one) Continue
		Set name = one.%Get("case")
		Set case = ..ReadCase(folder, name)
		Set kind = $Select($IsObject(case): ##class(OcuTalon.Eval.In).Scalar(case, "kind"), 1: "")
		Set entry = {"case": (name), "kind": (kind), "reason": (one.%Get("reason"))}
		Do entry.%Set("notRunYet", $ListFind($ListFromString(..#CASEKINDS), kind) && '$ListFind($ListFromString(##class(OcuTalon.Eval.In).#KINDS), kind), "boolean")
		Do report.skipped.%Push(entry)
	}
}

/// The case.json of the case as a dynamic object, or "" when the folder has none, it cannot be read or it is not a JSON object.
ClassMethod ReadCase(folder As %String, name As %String) As %DynamicObject [ Private ]
{
	If (name = "") || (name [ "/") || (name [ "\") || (name = "..") Quit ""
	Set file = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.In).#CASEFILE, ##class(%File).SubDirectoryName(folder, name))
	If '##class(%File).Exists(file) Quit ""
	Set case = ""
	Try {
		Set case = ##class(%DynamicAbstractObject).%FromJSONFile(file)
	} Catch exception {
		Set case = ""
	}
	If '$IsObject(case) || 'case.%IsA("%Library.DynamicObject") Quit ""
	Quit case
}

/// The value as a number, or "" when it is empty: an unknown cost or size stays empty and is never 0.
ClassMethod Number(value As %String) As %String [ Private ]
{
	Quit $Select(value = "": "", 1: +value)
}

/// 1 when the two texts are equal, ignoring case and leading and trailing spaces.
ClassMethod Same(one As %String, other As %String) As %Boolean [ Private ]
{
	Quit $ZConvert($ZStrip(one, "<>W"), "L") = $ZConvert($ZStrip(other, "<>W"), "L")
}

/// --- the parts of Text and Save ---
/// A row of the scores table.
ClassMethod ScoreLine(label As %String, score As %DynamicObject) As %String [ Private ]
{
	Set share = $Select(score.%GetTypeOf("share") = "null": "not measured", 1: ..Percent(score.share, 1))
	Set target = "", result = ""
	If score.%IsDefined("target") {
		Set target = ..Percent(score.target, 0)
		Set result = $Select(score.%GetTypeOf("met") = "null": "not measured", score.%Get("met"): "met", 1: "not met")
	}
	Quit "| "_label_" | "_score.right_" | "_score.total_" | "_share_" | "_target_" | "_result_" |"_$Char(10)
}

/// A bullet for each entry of the array, with {name} in the template replaced by the entry's member (an entry that is a case name stands for
/// {case}); "none" for an empty array.
ClassMethod List(array As %DynamicArray, template As %String) As %String [ Private ]
{
	If array.%Size() = 0 Quit "none"_$Char(10)
	Set text = ""
	Set iterator = array.%GetIterator()
	While iterator.%GetNext(, .one) {
		Set line = template
		If '$IsObject(one) {
			Set line = $Replace(line, "{case}", ..Cell(one))
		} Else {
			Set key = ""
			Set members = one.%GetIterator()
			While members.%GetNext(.key, .value) {
				If $IsObject(value) Continue
				Set shown = value
				If key = "costUSD" Set shown = ..Money(value)
				If (key = "model") && (value = "") Set shown = "model not known"
				Set line = $Replace(line, "{"_key_"}", ..Cell(shown))
			}
		}
		Set text = text_"- "_line_$Char(10)
	}
	Quit text
}

/// The share as a percentage with the decimals.
ClassMethod Percent(share As %Numeric, decimals As %Integer) As %String [ Private ]
{
	Quit $FNumber(share * 100, "", decimals)_"%"
}

/// A cost with a leading 0.
ClassMethod Money(value As %Numeric) As %String [ Private ]
{
	Quit $Select($Extract(value, 1) = ".": "0"_value, 1: value)
}

/// The text for a cell or a bullet: no pipe and no line break.
ClassMethod Cell(value As %String) As %String [ Private ]
{
	Quit $Translate(value, "|"_$Char(10, 13), "/  ")
}

/// An expectation or a result as text: the outcome, or the cause category, element at fault and fix kind.
ClassMethod Describe(value) As %String [ Private ]
{
	If '$IsObject(value) Quit value
	Set text = value.causeCategory_", "_value.elementAtFault
	If value.fixKind '= "" Set text = text_", "_value.fixKind
	Quit text
}

/// Writes the text to the file as UTF-8.
ClassMethod Write(file As %String, text As %String) As %Status [ Private ]
{
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set stream.Filename = file
	Set stream.TranslateTable = "UTF8"
	Set sc = stream.Write(text)
	If $$$ISERR(sc) Quit sc
	Quit stream.%Save()
}

}
