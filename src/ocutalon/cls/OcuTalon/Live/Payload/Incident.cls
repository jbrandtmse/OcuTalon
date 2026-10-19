/// The payload of the incident live event: the public view of one incident (AD-12, AD-15). Lane A publishes it, through IncidentManager.
Class OcuTalon.Live.Payload.Incident Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The incident's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// One of Msg.Enum INCIDENTSTATE.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 32);

/// One of Msg.Enum INCIDENTOPENVARIANT.
Property OpenVariant As %String(%JSONFIELDNAME = "openVariant", MAXLEN = 32);

/// The failure count.
Property Count As %Integer(%JSONFIELDNAME = "count");

/// The failure count at the notice.
Property NoticeCount As %Integer(%JSONFIELDNAME = "noticeCount");

/// When the first failure arrived, UTC to the second.
Property FirstAt As %String(%JSONFIELDNAME = "firstAt", MAXLEN = 20);

/// When the last failure arrived, UTC to the second.
Property LastAt As %String(%JSONFIELDNAME = "lastAt", MAXLEN = 20);

/// The item noun, singular and plural.
Property ItemNoun As OcuTalon.Live.Payload.Part.ItemNoun(%JSONFIELDNAME = "itemNoun");

/// The diagnosed cause.
Property Cause As %String(%JSONFIELDNAME = "cause", MAXLEN = 1000);

/// A one-line summary of the proposed fix.
Property FixSummary As %String(%JSONFIELDNAME = "fixSummary", MAXLEN = 1000);

/// The category of the cause.
Property CauseCategory As %String(%JSONFIELDNAME = "causeCategory", MAXLEN = 32);

/// The element that failed.
Property Element As %String(%JSONFIELDNAME = "element", MAXLEN = 128);

/// True when the result took the fallback route (AD-8).
Property Fallback As %Boolean(%JSONFIELDNAME = "fallback") [ InitialExpression = 0 ];

/// One of Msg.Enum FALLBACKREASON. Empty when Fallback is false.
Property FallbackReason As %String(%JSONFIELDNAME = "fallbackReason", MAXLEN = 32);

/// The diagnosis decision's Ref.
Property DecisionRef As %String(%JSONFIELDNAME = "decisionRef", MAXLEN = 22);

/// The failure groups, for the fallback and no-fix notices.
Property Groups As list Of OcuTalon.Live.Payload.Part.IncidentGroup(%JSONFIELDNAME = "groups");

/// The incident's approval requests.
Property Requests As list Of OcuTalon.Live.Payload.Part.IncidentRequest(%JSONFIELDNAME = "requests");

/// The evidence behind the diagnosis.
Property Evidence As OcuTalon.Live.Payload.Part.IncidentEvidence(%JSONFIELDNAME = "evidence");

/// The trace targets of the incident.
Property TraceTargets As OcuTalon.Live.Payload.Part.IncidentTraceTargets(%JSONFIELDNAME = "traceTargets");

/// The payload for an incident row, with every row-backed field set. groups, requests, evidence and traceTargets
/// are left absent for the caller to fill. IncidentManager and /state both build an incident's payload here, so an
/// event and the snapshot can't drift.
ClassMethod FromRow(row As OcuTalon.Data.Incident) As OcuTalon.Live.Payload.Incident
{
	Set payload = ..%New()
	Set payload.Ref = row.Ref
	Set payload.State = row.State
	Set payload.OpenVariant = row.OpenVariant
	Set payload.Count = row.Count
	Set payload.NoticeCount = row.NoticeCount
	Set payload.FirstAt = row.FirstAt
	Set payload.LastAt = row.LastAt
	Set payload.Cause = row.Cause
	Set payload.FixSummary = row.FixSummary
	Set payload.CauseCategory = row.CauseCategory
	Set payload.Element = row.Element
	Set payload.Fallback = row.Fallback
	Set payload.FallbackReason = row.FallbackReason
	Set payload.DecisionRef = row.DecisionRef
	If row.ItemNoun '= "" {
		Try {
			Set noun = ##class(%DynamicObject).%FromJSON(row.ItemNoun)
			Set payload.ItemNoun = ##class(OcuTalon.Live.Payload.Part.ItemNoun).%New()
			Set payload.ItemNoun.One = noun.one
			Set payload.ItemNoun.Other = noun.other
		} Catch {
			Set payload.ItemNoun = ""
		}
	}
	Quit payload
}

}
