/// The answers of the watch tools for the model (AD-10, AD-32): the shaping that OcuTalon.Tools.WatchTools leaves to a helper, because a tool
/// provider returns only through Return. The answers carry the outcome and the values to say, never the sentence.
///   - Resolve turns the name of a call into the one production it names, or into the refusal answer that Decide gives: unknown_production (the name,
///     the list of the names that can be watched and each one's name and namespace), only_orders (the README link, on the online demo) or ambiguous
///     (each match's name and namespace). Nothing is submitted for a refusal.
///   - ResolveStop is Resolve for stop_watch: the session's own watches come first (read through the ownership API, DW-222), so that a watch on a
///     production that the reader no longer lists can still be stopped. One own match is the one; several are ambiguous; none falls back to Resolve.
///   - Submitted is the answer of a command that the owner answered: CommandCall.Answer with the owner's outcome and the production's display name.
///   - Listed is the answer of list_productions.
///   - Joined joins names with ", " and with " and " before the last one.
/// A tool method runs inside AI Hub's callback, so this class makes no AI Hub call and no Python call (AD-6).
Class OcuTalon.Tools.WatchAnswers
{

/// The kind of a watch row of a production (the Kind of its BackgroundCheck).
Parameter KIND = "production";

/// The list of the answer unknown_production when no production can be watched at all.
Parameter NOPRODUCTIONS = "no productions";

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

/// The answer for the model to a command that the owner answered: CommandCall.Answer, with the outcome of the owner's result and the
/// production's display name.
ClassMethod Submitted(result As OcuTalon.Msg.CommandResult, match As %DynamicObject) As %DynamicObject
{
	Set answer = ##class(OcuTalon.Tools.CommandCall).Answer(result)
	Set answer.outcome = result.Outcome
	Set answer.production = match.displayName
	Quit answer
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
