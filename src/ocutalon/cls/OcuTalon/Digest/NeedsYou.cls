/// What needs the user, for a digest (AD-14, AD-20, FR-35; Story 17.6). List gives the entries in this order, each named by text that code wrote:
///   1. the failed rows of the checks that the digest covers, each "<entry>: <finding>" (the entry alone when the finding is empty);
///   2. the session's decide Decisions (Ownership.Decisions) whose Outcome is tellnow or act and whose Ref is not marked handled (Data.Handled Marked),
///      newest first, each named by its Summary;
///   3. the session's incidents (Ownership.Incidents) that are awaiting approval, each named by the Summary of its diagnose Decision (the Decision
///      that Incident.DecisionRef points at), or by its Production when that is empty.
/// A Decision whose Ref is an awaiting incident's DecisionRef, or whose ItemId is that incident's Ref, is the incident's own and appears once, as the
/// incident. An entry with no name is left out.
/// The result is {"count", "names", "more"}: count is the number of entries, names holds at most NEEDSYOUMAX names, and more is count minus the names
/// kept. When there are more entries than NEEDSYOUMAX, the newest are kept and the oldest dropped (the time of a row is its checkedAt, of a Decision its
/// RecordedAt, of an incident its NoticedAt), and the names kept stay in the order above. Lane A; it reads through the ownership API and writes nothing.
Class OcuTalon.Digest.NeedsYou
{

/// The most entries that are named.
Parameter NEEDSYOUMAX = 5;

/// The most Decisions that are read.
Parameter DECISIONMAX = 1000;

/// The outcomes of a Decision that leave the user something to do.
Parameter OUTCOMES = "tellnow,act";

/// The entries that need the session (see the class description), given its failed rows (a %DynamicArray of {result, entry, finding, checkedAt}). The
/// status is an error when a record cannot be read; the result is then empty and must not be used.
ClassMethod List(sessionRef As %String, failedRows As %DynamicArray, Output sc As %Status) As %DynamicObject
{
	Set sc = $$$OK
	Set result = {"count": 0, "names": [], "more": 0}
	Try {
		Set count = 0
		If $IsObject($Get(failedRows)) {
			Set iterator = failedRows.%GetIterator()
			While iterator.%GetNext(, .row) {
				Set entry = row.entry
				Set name = $Select(row.finding '= "": entry_": "_row.finding, 1: entry)
				Do ..Add(.entries, .count, name, row.checkedAt)
			}
		}
		Set incidents = ##class(OcuTalon.Data.Ownership).Incidents(sessionRef, .sc)
		If $$$ISERR(sc) Quit
		For i = 1:1:incidents.Count() {
			Set incident = incidents.GetAt(i)
			If incident.State '= ##class(OcuTalon.Watch.Transitions).#AWAITING Continue
			If incident.DecisionRef '= "" Set owned("decision", incident.DecisionRef) = ""
			Set owned("item", incident.Ref) = ""
			Set summary = ""
			Set diagnosis = $Select(incident.DecisionRef '= "": ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(incident.DecisionRef), 1: "")
			If $IsObject(diagnosis) Set summary = diagnosis.Summary
			Set incidentNames(i) = $Select(summary '= "": summary, 1: incident.Production)
			Set incidentTimes(i) = incident.NoticedAt
		}
		Set decisions = ##class(OcuTalon.Data.Ownership).Decisions(sessionRef, ..#DECISIONMAX, .sc)
		If $$$ISERR(sc) Quit
		For i = 1:1:decisions.Count() {
			Set decision = decisions.GetAt(i)
			If '$ListFind($ListFromString(..#OUTCOMES), decision.Outcome) Continue
			If $Data(owned("decision", decision.Ref)) || ((decision.ItemId '= "") && $Data(owned("item", decision.ItemId))) Continue
			If ##class(OcuTalon.Data.Handled).Marked(decision.Ref) '= "" Continue
			Do ..Add(.entries, .count, decision.Summary, decision.RecordedAt)
		}
		Set i = ""
		For {
			Set i = $Order(incidentNames(i))
			Quit:i=""
			Do ..Add(.entries, .count, incidentNames(i), incidentTimes(i))
		}
		Set result = ..Bound(.entries, count)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) Quit {"count": 0, "names": [], "more": 0}
	Quit result
}

/// Adds one entry to entries, in the order of the call, unless it has no name. count is the number of entries.
ClassMethod Add(ByRef entries, ByRef count As %Integer, name As %String, time As %String) [ Private ]
{
	If $ZStrip(name, "<>WC") = "" Quit
	Set count = count + 1
	Set entries(count) = $ListBuild(name, time)
}

/// The result for the entries: every name while they fit, otherwise the NEEDSYOUMAX newest, in the order of the entries.
ClassMethod Bound(ByRef entries, count As %Integer) As %DynamicObject [ Private ]
{
	Set names = []
	If count <= ..#NEEDSYOUMAX {
		For i = 1:1:count {
			Do names.%Push($List(entries(i), 1))
		}
		Quit {"count": (count), "names": (names), "more": 0}
	}
	For i = 1:1:count {
		Set byTime($Select($List(entries(i), 2) '= "": $List(entries(i), 2), 1: " "), i) = ""
	}
	Set kept = 0
	Set time = ""
	For {
		Set time = $Order(byTime(time), -1)
		Quit:time=""
		Set i = ""
		For {
			Set i = $Order(byTime(time, i), -1)
			Quit:i=""
			If kept < ..#NEEDSYOUMAX {
				Set keep(i) = ""
				Set kept = kept + 1
			}
		}
	}
	For i = 1:1:count {
		If $Data(keep(i)) Do names.%Push($List(entries(i), 1))
	}
	Quit {"count": (count), "names": (names), "more": (count - kept)}
}

}
