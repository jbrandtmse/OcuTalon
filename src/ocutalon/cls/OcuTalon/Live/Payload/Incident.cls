/// The payload of the incident live event: the public view of one incident (AD-12, AD-15). Lane A publishes it, through IncidentManager.
Class OcuTalon.Live.Payload.Incident Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The incident's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// The watched production the incident is in, which the result band of a suspend or resume names its item in.
Property Production As %String(%JSONFIELDNAME = "production", MAXLEN = 128);

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

/// The setting change that the diagnosis named as the cause, and the whole minutes from it to the first failure (Story 23.3); both are absent when it named none, and on the
/// online demo.
Property SettingChange As OcuTalon.Live.Payload.Part.SettingChange(%JSONFIELDNAME = "settingChange");

Property GapMinutes As %Integer(%JSONFIELDNAME = "gapMinutes");

/// The page that the incident's first notice sent (Story 23.4): state, when it was sent, and the first acknowledgement's time and channel. Absent when the incident was not paged
/// and on the online demo; it names no person.
Property Page As OcuTalon.Live.Payload.Part.Page(%JSONFIELDNAME = "page");

/// The evidence behind the diagnosis.
Property Evidence As OcuTalon.Live.Payload.Part.IncidentEvidence(%JSONFIELDNAME = "evidence");

/// The trace targets of the incident.
Property TraceTargets As OcuTalon.Live.Payload.Part.IncidentTraceTargets(%JSONFIELDNAME = "traceTargets");

/// The payload for an incident row, with every row-backed field set. IncidentManager and /state both build an incident's
/// payload here, so an event and the snapshot can't drift. The Show-details fields come from rows, by object access only,
/// because /state runs as a user with no SQL grant (AD-13):
///   - groups: one {itemName, count, errorSummary, firstAt} per failure group (FailureGroup.OfIncident), count being the group's live Count;
///   - evidence: sampleHeaderId and sampleError from the row, and items, one {itemName, count, firstAt, lastAt} per group; left absent when the
///     incident has no group and no sample;
///   - traceTargets: diagnosis (the row's TraceHeaderId in the current namespace), sample (SampleHeaderId) and firstFailure (FirstHeaderId), the
///     last two in the watched namespace; each is left out when its id is empty;
///   - requests: one {ref, state, result} for each Ref of the row's RequestRefs whose ApprovalRequest exists and names this incident; result is the stored
///     result of the request's run (Data.FixRun OfRequest: total, resent, completed, failedAgain, skipped, unreached (absent unless the resend stopped partway), interrupted and reason) once that run has ended
///     (EndedAt set), and stays empty for a request with no run and for a run that has not ended;
///   - page (Story 23.4): {state, pagedAt, acknowledgedAt, channel} from the incident's Page rows (Data.Page OfIncident), absent when it has none and on the online demo.
/// A row without any of them gives a payload without the five fields.
ClassMethod FromRow(row As OcuTalon.Data.Incident) As OcuTalon.Live.Payload.Incident
{
	Set payload = ..%New()
	Set payload.Ref = row.Ref
	Set payload.Production = row.Production
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
	Do ..Change(payload, row)
	Do ..Paged(payload, row)
	Do ..Details(payload, row)
	Quit payload
}

/// Fills page from the incident's Page rows, by object access only (Watch.Paging.PagePayload); it stays empty when the incident has none and on the online demo.
ClassMethod Paged(payload As OcuTalon.Live.Payload.Incident, row As OcuTalon.Data.Incident) [ Private ]
{
	Set page = ##class(OcuTalon.Watch.Paging).PagePayload(row.Ref)
	If '$IsObject(page) Quit
	Set part = ##class(OcuTalon.Live.Payload.Part.Page).%New()
	Set part.State = page.state
	Set part.PagedAt = page.pagedAt
	Set part.AcknowledgedAt = page.acknowledgedAt
	Set part.Channel = page.channel
	Set payload.Page = part
}

/// Fills settingChange and gapMinutes from the SettingChange row that the incident names (Incident SettingChangeRef), by object access only; both stay empty when it names none
/// or the row is gone. The values of a secret are blank in the row. The old and new values are shown through Bridge.Redact (the one redactor), so that a token in a URL reaches no
/// person; the SettingChange row keeps the raw values, and an empty value stays empty.
ClassMethod Change(payload As OcuTalon.Live.Payload.Incident, row As OcuTalon.Data.Incident) [ Private ]
{
	If row.SettingChangeRef = "" Quit
	Set change = ##class(OcuTalon.Data.SettingChange).RefIndexOpen(row.SettingChangeRef)
	If '$IsObject(change) Quit
	Set part = ##class(OcuTalon.Live.Payload.Part.SettingChange).%New()
	Set part.Item = change.Item
	Set part.Target = change.Target
	Set part.Setting = change.Setting
	Set part.OldValue = ##class(OcuTalon.Bridge.Redact).Text(change.OldValue)
	Set part.NewValue = ##class(OcuTalon.Bridge.Redact).Text(change.NewValue)
	Set part.Credential = +change.Credential
	Set part.DetectedAt = change.DetectedAt
	Set payload.SettingChange = part
	Set minutes = ##class(OcuTalon.Watch.SettingCause).GapMinutes(change.DetectedAt, row.FirstAt)
	If minutes '= "" Set payload.GapMinutes = minutes
}

/// Fills groups, evidence, traceTargets and requests of the payload from the rows of the incident (see FromRow).
ClassMethod Details(payload As OcuTalon.Live.Payload.Incident, row As OcuTalon.Data.Incident) [ Private ]
{
	Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(row.Ref)
	Set evidence = ##class(OcuTalon.Live.Payload.Part.IncidentEvidence).%New()
	For i = 1:1:groups.Count() {
		Set group = groups.GetAt(i)
		Set line = ##class(OcuTalon.Live.Payload.Part.IncidentGroup).%New()
		Set line.ItemName = group.ItemName
		Set line.Count = group.Count
		Set line.ErrorSummary = group.ErrorSummary
		Set line.FirstAt = group.FirstAt
		Do payload.Groups.Insert(line)
		Set item = ##class(OcuTalon.Live.Payload.Part.IncidentEvidenceItem).%New()
		Set item.ItemName = group.ItemName
		Set item.Count = group.Count
		Set item.FirstAt = group.FirstAt
		Set item.LastAt = group.LastAt
		Do evidence.Items.Insert(item)
	}
	Set evidence.SampleHeaderId = row.SampleHeaderId
	Set evidence.SampleError = row.SampleError
	If (evidence.Items.Count() > 0) || (row.SampleHeaderId '= "") || (row.SampleError '= "") Set payload.Evidence = evidence
	Set targets = ##class(OcuTalon.Live.Payload.Part.IncidentTraceTargets).%New()
	Set targets.Diagnosis = ..Target(row.TraceHeaderId, $Namespace)
	Set targets.Sample = ..Target(row.SampleHeaderId, row.Namespace)
	Set targets.FirstFailure = ..Target(row.FirstHeaderId, row.Namespace)
	If $IsObject(targets.Diagnosis) || $IsObject(targets.Sample) || $IsObject(targets.FirstFailure) Set payload.TraceTargets = targets
	For i = 1:1:$Length(row.RequestRefs, ",") {
		Set ref = $Piece(row.RequestRefs, ",", i)
		If ref = "" Continue
		Set request = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
		If '$IsObject(request) || (request.IncidentRef '= row.Ref) Continue
		Set part = ##class(OcuTalon.Live.Payload.Part.IncidentRequest).%New()
		Set part.Ref = request.Ref
		Set part.State = request.State
		Set part.FixKind = request.FixKind
		Do ..Chosen(part, request)
		Set run = ##class(OcuTalon.Data.FixRun).OfRequest(request.Ref)
		If $IsObject(run) && (run.EndedAt '= "") {
			Set part.Result = ##class(OcuTalon.Live.Payload.Part.IncidentRequestResult).%New()
			Set part.Result.Total = run.Total
			Set part.Result.Resent = run.Resent
			Set part.Result.Completed = run.Completed
			Set part.Result.FailedAgain = run.FailedAgain
			Set part.Result.Skipped = run.Skipped
			Set part.Result.Interrupted = run.Interrupted
			Set part.Result.Unreached = run.Unreached
			Set part.Result.Reason = run.Reason
		}
		Do payload.Requests.Insert(part)
	}
}

/// Fills the item, the count and the after of a request part for the fix kinds the user asks for in the chat and the setting kinds: the item of a suspend or resume, the target item of a reroute and the count of its dry run, and the item and the after of a setting kind's dry run (Story 23.3; the after as Watch.SettingCause ShownAfter gives it, the value of the result notice's {after}, DW-1378). Any other kind, and a request whose parameters or dry run can't be read, leave them empty.
ClassMethod Chosen(part As OcuTalon.Live.Payload.Part.IncidentRequest, request As OcuTalon.Bridge.Data.ApprovalRequest) [ Private ]
{
	If '$ListFind($ListBuild("suspend_item", "resume_item", "reroute", "rollback_setting", "undo_rollback"), request.FixKind) Quit
	Try {
		If (request.FixKind = "rollback_setting") || (request.FixKind = "undo_rollback") {
			Set part.Item = {}.%FromJSON(request.DryRun).%Get("item")
			Set part.After = ##class(OcuTalon.Watch.SettingCause).ShownAfter(request.DryRun)
			Quit
		}
		Set parameters = {}.%FromJSON(request.FixParameters)
		Set part.Item = $Select(request.FixKind = "reroute": parameters.%Get("target"), 1: parameters.%Get("item"))
		If request.FixKind = "reroute" Set part.Count = {}.%FromJSON(request.DryRun).%Get("affected")
	} Catch {
	}
}

/// The trace target of a header id in a namespace; "" when the id is empty.
ClassMethod Target(headerId As %Integer, namespace As %String) As OcuTalon.Live.Payload.Part.TraceTarget [ Private ]
{
	If headerId = "" Quit ""
	Set target = ##class(OcuTalon.Live.Payload.Part.TraceTarget).%New()
	Set target.TraceHeaderId = headerId
	Set target.TraceNamespace = namespace
	Quit target
}

}
