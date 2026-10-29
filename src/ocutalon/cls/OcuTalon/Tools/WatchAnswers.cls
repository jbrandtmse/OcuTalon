/// The answers of the watch tools for the model (AD-10, AD-32): the shaping that OcuTalon.Tools.WatchTools leaves to a helper, because a tool
/// provider returns only through Return. The answers carry the outcome and the values to say, never the sentence.
///   - Resolve turns the name of a call into the one production it names, or into the refusal answer that Decide gives: unknown_production (the name,
///     the list of the names that can be watched and each one's name and namespace), only_orders (the README link, on the online demo) or ambiguous
///     (each match's name and namespace). Nothing is submitted for a refusal.
///   - ResolveStop is Resolve for stop_watch: the session's own watches come first (read through the ownership API, DW-222), so that a watch on a
///     production that the reader no longer lists can still be stopped. One own match is the one; several are ambiguous; none falls back to Resolve.
///   - Submitted is the answer of a command that the owner answered: CommandCall.Answer with the owner's outcome and the production's display name.
///   - ResolveIncident is the resolution of dismiss_incident: the session's noticed open or resolved incidents (read through the ownership API) are the
///     candidates and its awaiting_approval or fixing ones the busy ones, each as an entry {"ref", "production", "state", "openVariant", "since", "count"}
///     built in code from the row. The incident argument picks a candidate by its ref, the production argument keeps the candidates that Reader.Matches
///     keeps, and without either all are kept. One match is the one; several are ambiguous; none is unknown_incident; no candidate at all is no_incident.
///     Nothing is submitted for a refusal, and no text of the incident from outside the instance (cause, element, fix summary, sample error) is read.
///   - Dismissed is the answer of the Dismiss that the owner answered: CommandCall.Answer with the owner's outcome, the entry's production and ref, and the
///     state and openVariant that the owner's Data holds.
///   - CheckResults is the source of the results that check_status gives for a session: the session's own Kind production
///     watches (read through the ownership API, by ID), each as {"result", "entry" (ENTRY with the display name), "finding", "checkedAt"} copied from
///     the row's Result, Finding and LastRunAt, so the tool never decides a result (AD-28). Rows of another Kind are left out. A read that fails
///     answers {"ok": false, "message": CHECKSNOTREAD}. It refuses the owner eval (CHECKSNOTREAD), as before.
///   - EvalCheckResults is the eval branch of check_status (Story 9.7, AD-22): it answers 1, with the case's recorded rows in results, only when
///     the bridge context's OwnerRef is exactly eval (as the request and the session carry it, never a tool argument) and the newest
///     OcuTalon.Eval.Msg.TurnResult of the context's ItemId has RecordedChecks that parse as a JSON array. For every other call, and when
///     it cannot read the table, it answers 0 and results is []. It reads the table with SQL, so that no class of the evaluation set joins the
///     callback, and it never throws.
///   - PutChecks sets the results as the checks member of the bridge context's HostData (a JSON object keeps its other members and loses an
///     earlier checks; any other HostData becomes {"checks": results}), which Conversation hands to Checks.Render.
///   - Checked is the answer of check_status for the model: {"ok": true, "checks": [{"result", "entry", "finding", "checked"}]}, where checked is the
///     time in the instance zone (Data.Time.ForMessage; the UTC time never reaches the model).
///   - Listed is the answer of list_productions.
///   - Joined joins names with ", " and with " and " before the last one.
/// A tool method runs inside AI Hub's callback, so this class makes no AI Hub call and no Python call (AD-6).
Class OcuTalon.Tools.WatchAnswers
{

/// The kind of a watch row of a production (the Kind of its BackgroundCheck).
Parameter KIND = "production";

/// The list of the answer unknown_production when no production can be watched at all.
Parameter NOPRODUCTIONS = "no productions";

/// The answer when the session's incidents cannot be read: nothing is dismissed.
Parameter INCIDENTSNOTREAD = "The incidents of this conversation could not be read, so nothing was dismissed.";

/// The entry of a check result: the display name of the watch is {name}.
Parameter ENTRY = "{name} production";

/// The answer when the session's background checks cannot be read: nothing is known about them.
Parameter CHECKSNOTREAD = "The background checks of this conversation could not be read, so nothing is known about them.";

/// The states of the incidents that dismiss_incident can close, and the states in which an incident is busy and cannot be dismissed (AD-15).
Parameter DISMISSABLE = "open,resolved";

Parameter BUSY = "awaiting_approval,fixing";

/// Resolves the name through the reader: "" and the one matching entry in match, or the refusal answer for the model (see Decide) and nothing to
/// submit. The list of the productions is read only when it is needed for the answer.
ClassMethod Resolve(name As %String, namespace As %String, Output match As %DynamicObject) As %DynamicObject
{
	Set matches = ##class(OcuTalon.Watch.Reader).Find($Get(name), $Get(namespace))
	Set onlineDemo = ##class(OcuTalon.Watch.Reader).OnlineDemo()
	Set productions = $Select((matches.%Size() = 0) && 'onlineDemo: ##class(OcuTalon.Watch.Reader).Productions(), 1: [])
	Quit ..Decide($Get(name), matches, onlineDemo, productions, .match)
}

/// Resolves the name of a stop_watch call: the entries are the Kind production watches of the session (OcuTalon.Data.Ownership.Checks, the
/// sanctioned read of a session's own records), matched with the reader's rule (Reader.Matches). One match: "" and the entry in match. Several:
/// the ambiguous answer of Decide. None, or watches that cannot be read: Resolve, as for start_watch.
ClassMethod ResolveStop(name As %String, namespace As %String, sessionRef As %String, Output match As %DynamicObject) As %DynamicObject
{
	Set match = ""
	Set checks = ##class(OcuTalon.Data.Ownership).Checks($Get(sessionRef), .sc)
	If $$$ISERR(sc) Quit ..Resolve($Get(name), $Get(namespace), .match)
	Set entries = []
	For i = 1:1:checks.Count() {
		Set check = checks.GetAt(i)
		If check.Kind '= ..#KIND Continue
		Do entries.%Push({"namespace": (check.Namespace), "production": (check.Production), "displayName": (check.DisplayName)})
	}
	Set matches = ##class(OcuTalon.Watch.Reader).Matches(entries, $Get(name), $Get(namespace))
	If matches.%Size() = 0 Quit ..Resolve($Get(name), $Get(namespace), .match)
	Quit ..Decide($Get(name), matches, 0, [], .match)
}

/// The decision on the matches of a name (pure). One match: "" and the entry in match. Several: {"ok": false, "outcome": "ambiguous", "name", "matches":
/// [{"name", "namespace"}, ...]}. None on the online demo: {"ok": false, "outcome": "only_orders", "readmeLink"}. None otherwise: {"ok": false,
/// "outcome": "unknown_production", "name", "list" (Joined), "productions": [{"name", "namespace"}, ...]} of the productions that can be watched.
ClassMethod Decide(name As %String, matches As %DynamicArray, onlineDemo As %Boolean, productions As %DynamicArray, Output match As %DynamicObject) As %DynamicObject
{
	Set match = ""
	If matches.%Size() = 1 {
		Set match = matches.%Get(0)
		Quit ""
	}
	If matches.%Size() > 1 {
		Quit {"ok": false, "outcome": "ambiguous", "name": (name), "matches": (..Names(matches))}
	}
	If onlineDemo {
		Quit {"ok": false, "outcome": "only_orders", "readmeLink": (##class(OcuTalon.Tools.WatchTools).#READMELINK)}
	}
	Set names = ..Names(productions)
	Quit {"ok": false, "outcome": "unknown_production", "name": (name), "list": (..Joined(names)), "productions": (names)}
}

/// Resolves the incident of a dismiss_incident call for the session. "" and the one matching entry in match, or the refusal answer for the model and
/// nothing to submit: {"ok": false, "message": INCIDENTSNOTREAD} when the incidents cannot be read, {"ok": false, "outcome": "no_incident", "others": [busy]}
/// when no incident can be dismissed, {"ok": false, "outcome": "ambiguous", "incidents": [matches]} for several matches and {"ok": false, "outcome":
/// "unknown_incident", "incidents": [candidates], "others": [busy]} for none. An entry is {"ref", "production" (the display name of the session's own
/// watch of the production, else the row's production), "state", "openVariant", "since", "count"}.
ClassMethod ResolveIncident(production As %String, incident As %String, sessionRef As %String, Output match As %DynamicObject) As %DynamicObject
{
	Set match = ""
	Set rows = ##class(OcuTalon.Data.Ownership).Incidents($Get(sessionRef), .sc)
	If $$$ISERR(sc) || '$IsObject(rows) Quit {"ok": false, "message": (..#INCIDENTSNOTREAD)}
	Do ..WatchNames($Get(sessionRef), .names)
	Set candidates = [], busy = []
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		Set state = row.State
		Set display = $Get(names(row.Namespace, row.Production))
		Set entry = {"ref": (row.Ref), "production": ($Select(display '= "": display, 1: row.Production)), "state": (state), "openVariant": (row.OpenVariant), "since": (##class(OcuTalon.Data.Time).ForMessage(row.FirstAt)), "count": (+row.Count)}
		If $ListFind($ListFromString(..#DISMISSABLE), state) {
			Do candidates.%Push({"namespace": (row.Namespace), "production": (row.Production), "displayName": (entry.production), "entry": (entry)})
		} ElseIf $ListFind($ListFromString(..#BUSY), state) {
			Do busy.%Push(entry)
		}
	}
	If candidates.%Size() = 0 Quit {"ok": false, "outcome": "no_incident", "others": (busy)}
	Set matched = []
	If $Get(incident) '= "" {
		Set iterator = candidates.%GetIterator()
		While iterator.%GetNext(, .candidate) {
			If candidate.entry.ref = incident Do matched.%Push(candidate)
		}
	} ElseIf $ZStrip($Get(production), "<>W") '= "" {
		Set matched = ##class(OcuTalon.Watch.Reader).Matches(candidates, production)
	} Else {
		Set matched = candidates
	}
	If matched.%Size() = 1 {
		Set match = matched.%Get(0).entry
		Quit ""
	}
	If matched.%Size() > 1 Quit {"ok": false, "outcome": "ambiguous", "incidents": (..Entries(matched))}
	Quit {"ok": false, "outcome": "unknown_incident", "incidents": (..Entries(candidates)), "others": (busy)}
}

/// The answer for the model to the Dismiss that the owner answered: CommandCall.Answer with the owner's outcome, the production and the ref of the
/// entry, and, when the owner's Data is a JSON object with a string state, that state and the open variant (an empty one when the Data has none).
ClassMethod Dismissed(result As OcuTalon.Msg.CommandResult, entry As %DynamicObject) As %DynamicObject
{
	Set answer = ##class(OcuTalon.Tools.CommandCall).Answer(result)
	Set answer.outcome = result.Outcome
	Set answer.production = entry.production
	Set answer.ref = entry.ref
	Try {
		Set data = {}.%FromJSON(result.Data)
		If $IsObject(data) && data.%IsA("%Library.DynamicObject") && (data.%GetTypeOf("state") = "string") {
			Set answer.state = data.state
			Set answer.openVariant = $Select(data.%GetTypeOf("openVariant") = "string": data.openVariant, 1: "")
		}
	} Catch exception {
	}
	Quit answer
}

/// The answer entries of the matching entries, in order.
ClassMethod Entries(matched As %DynamicArray) As %DynamicArray [ Private ]
{
	Set entries = []
	Set iterator = matched.%GetIterator()
	While iterator.%GetNext(, .candidate) {
		Do entries.%Push(candidate.entry)
	}
	Quit entries
}

/// The display names of the session's own watches of productions: names(namespace, production) is the display name. A read that fails gives none.
ClassMethod WatchNames(sessionRef As %String, ByRef names) [ Private ]
{
	Kill names
	Set checks = ##class(OcuTalon.Data.Ownership).Checks(sessionRef, .sc)
	If $$$ISERR(sc) || '$IsObject(checks) Quit
	For i = 1:1:checks.Count() {
		Set check = checks.GetAt(i)
		If (check.Kind = ..#KIND) && (check.DisplayName '= "") && '$Data(names(check.Namespace, check.Production)) Set names(check.Namespace, check.Production) = check.DisplayName
	}
}

/// The answer for the model to a command that the owner answered: CommandCall.Answer, with the outcome of the owner's result and the
/// production's display name.
ClassMethod Submitted(result As OcuTalon.Msg.CommandResult, match As %DynamicObject) As %DynamicObject
{
	Set answer = ##class(OcuTalon.Tools.CommandCall).Answer(result)
	Set answer.outcome = result.Outcome
	Set answer.production = match.displayName
	Quit answer
}

/// The results of the session's production watches for check_status: "" and the results in results ([{"result", "entry", "finding", "checkedAt"}, ...], by
/// ID, copied from the rows), or {"ok": false, "message": CHECKSNOTREAD} when they cannot be read (results is then []).
ClassMethod CheckResults(sessionRef As %String, Output results As %DynamicArray) As %DynamicObject
{
	Set results = []
	Set checks = ##class(OcuTalon.Data.Ownership).Checks($Get(sessionRef), .sc)
	If $$$ISERR(sc) || '$IsObject(checks) Quit {"ok": false, "message": (..#CHECKSNOTREAD)}
	For i = 1:1:checks.Count() {
		Set check = checks.GetAt(i)
		If check.Kind '= ..#KIND Continue
		Do results.%Push({"result": (check.Result), "entry": ($Replace(..#ENTRY, "{name}", check.DisplayName)), "finding": (check.Finding), "checkedAt": (check.LastRunAt)})
	}
	Quit ""
}

/// The eval branch of check_status: 1 and the case's recorded rows in results ([{"result", "entry", "finding", "checkedAt"}, ...], as the case
/// recorded them) when the context's OwnerRef is exactly eval and the newest TurnResult of the context's ItemId has RecordedChecks that
/// parse as a JSON array (an empty array is a case with nothing watched). Otherwise 0 and []: another owner, no context, no ItemId, no
/// TurnResult, RecordedChecks that are empty or not an array, or a table that cannot be read.
ClassMethod EvalCheckResults(context As OcuTalon.Bridge.Context, Output results As %DynamicArray) As %Boolean
{
	Set results = []
	Set found = 0
	Try {
		If $IsObject(context) && (context.OwnerRef = ##class(OcuTalon.Data.Ownership).#EVAL) && (context.ItemId '= "") {
			Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT RecordedChecks FROM OcuTalon_Eval_Msg.TurnResult WHERE ItemId = ? ORDER BY ID DESC", context.ItemId)
			If (result.%SQLCODE '< 0) && result.%Next() {
				Set recorded = result.%Get("RecordedChecks")
				If recorded '= "" {
					Set parsed = ##class(%DynamicAbstractObject).%FromJSON(recorded)
					If $IsObject(parsed) && parsed.%IsA("%Library.DynamicArray") {
						Set results = parsed
						Set found = 1
					}
				}
			}
		}
	} Catch exception {
		Set results = [], found = 0
	}
	Quit found
}

/// Sets the results as the checks member of the bridge context's HostData. A HostData that is a JSON object keeps its other members; any other
/// HostData (empty, not JSON, or not an object) becomes {"checks": results}. Returns the status of the context's Put.
ClassMethod PutChecks(results As %DynamicArray) As %Status
{
	Set data = {}
	Set context = ##class(OcuTalon.Bridge.Context).Current()
	If $IsObject(context) && (context.HostData '= "") {
		Try {
			Set parsed = {}.%FromJSON(context.HostData)
			If $IsObject(parsed) && parsed.%IsA("%Library.DynamicObject") Set data = parsed
		} Catch exception {
			Set data = {}
		}
	}
	Do data.%Set("checks", results)
	Quit ##class(OcuTalon.Bridge.Context).Put("HostData", data.%ToJSON())
}

/// The answer of check_status for the model: {"ok": true, "checks": [{"result", "entry", "finding", "checked"}, ...]} for the results, where checked is
/// Data.Time.ForMessage of the result's checkedAt (empty before the first run).
ClassMethod Checked(results As %DynamicArray) As %DynamicObject
{
	Set checks = []
	Set iterator = results.%GetIterator()
	While iterator.%GetNext(, .result) {
		Do checks.%Push({"result": (result.result), "entry": (result.entry), "finding": (result.finding), "checked": (##class(OcuTalon.Data.Time).ForMessage(result.checkedAt))})
	}
	Quit {"ok": true, "checks": (checks)}
}

/// The answer of list_productions: {"ok": true, "list": the joined names, "productions": [{"name", "namespace"}, ...]} for the entries of the reader.
ClassMethod Listed(entries As %DynamicArray) As %DynamicObject
{
	Set productions = ..Names(entries)
	Quit {"ok": true, "list": (..Joined(productions)), "productions": (productions)}
}

/// The entries as [{"name", "namespace"}].
ClassMethod Names(entries As %DynamicArray) As %DynamicArray
{
	Set names = []
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Do names.%Push({"name": (entry.displayName), "namespace": (entry.namespace)})
	}
	Quit names
}

/// The names of the entries, joined with ", " and with " and " before the last one; NOPRODUCTIONS when there are none. A name that two
/// namespaces share is said once.
ClassMethod Joined(names As %DynamicArray) As %String
{
	Set list = ""
	Set count = 0
	Set iterator = names.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If $Data(seen(entry.name)) Continue
		Set seen(entry.name) = ""
		Set count = count + 1
		Set item(count) = entry.name
	}
	If count = 0 Quit ..#NOPRODUCTIONS
	For i = 1:1:count {
		Set list = list_$Select(i = 1: "", i = count: " and ", 1: ", ")_item(i)
	}
	Quit list
}

}
