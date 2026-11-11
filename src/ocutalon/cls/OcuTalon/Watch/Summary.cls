/// The summary of a closed incident (Story 23.6; AD-4, AD-15, AD-20, AD-32). Pure code, no model request: Build composes the summary from the incident's own rows
/// and IncidentManager, the one writer of the Incident row, stores it in the same save that closes the incident. Text reads it back for the *Out operations and the
/// incident_summary tool. Build renders nothing, writes nothing and sends nothing (producers never render, AD-32).
///   - The summary is {"parts": [{"key", "slots"}], "lines": []}, the shape of OcuTalon.Channel.DigestText, so that it is rendered there, one catalog key (prefix
///     summary.) per line, through Msg.Catalog.Render. The parts, in this order:
///       summary.title                                     the failed count, the item noun and the production (its display name, as the watch cards name it;
///                                                         else its class name)
///       the timeline, sorted by time (ties keep the order below): summary.firstFailure (FirstAt), summary.noticed (NoticedAt); for each request of the incident
///         (RequestRefs, rows that name the incident): summary.requested (RaisedAt, the dry run's resend count; left out when the dry run holds no count; for a fix the user asked for in the chat summary.requestedSuspend, summary.requestedResume or summary.requestedReroute, Story 23.2, and summary.requestedPartner with the number of recipients for a partner delay notice, Story 23.5), its answer (summary.approved or summary.rejected at
///         AnsweredAt, with ...By and the user when the install is local and AnsweredBy is known; summary.expired at ExpiresAt; none for a pending or cancelled
///         request) and, for its FixRun (but a delay notice's, which has its end line only), summary.fixStarted (StartedAt) and summary.fixEnded (EndedAt, with the counts) or summary.fixInterrupted (EndedAt, with
///         the resent count; a run of a kind whose targets are items ends with summary.itemSuspended, summary.itemResumed or summary.itemNotChanged instead of summary.fixEnded, and a
///         run of a kind whose targets are contacts with summary.partnerSent, summary.partnerKept (the run failed with the kind's NOTSETUP reason) or summary.partnerNotSent); the closing, summary.closedDismiss, summary.closedReplay or summary.closedQuiet at the close time
///       summary.noCause (a fallback incident; the reason) or summary.cause and summary.element (omitted when empty; the element also when it is only a period,
///         which the catalog would drop before its own period and then refuse as empty)
///       summary.evidence (the first evidence line of the diagnosis payload; omitted when there is none), summary.sampleError (the first sentence of the sample
///         error, at most the length of an incident notice's error summary; omitted when empty)
///       summary.fix (the fix summary) when a fix of a kind the diagnosis proposes ran, summary.noFixRan when no run of any kind ran
///       summary.groups (every failure group, with its count at the close; left out when the incident has none) for a fallback incident or an incident whose fix
///         did not run
///       summary.messages (failed = the incident's Count; resent, completed, failed again and skipped summed over the incident's FixRuns of kinds whose targets are messages)
///       A run of a delay notice is not a fix of the failure: it adds no summary.fix and does not make summary.noFixRan go away.
///       summary.cost, or summary.costUnknown when a usage row of the incident's diagnosis decision has no cost (Usage.Totals; an incident without usage rows costs 0)
///   - The channel of an answer is the name the README gives it ("the web chat", "the Simulated phone", "Telegram", "the Simulated mailbox"), never an internal id; an answer from a channel
///     that has no name here gets no answer line, because the summary cannot say where it came from. The answerer is named only on a local install (onlineDemo 0).
///   - Slots hold the model's cause, evidence and fix and the sample error as plain strings; the catalog adds no markup and the channels show them literally.
/// Build gives "" with an error status in sc when the summary cannot be built (an event that does not close, a row that cannot be read, a slot that cannot be made);
/// IncidentManager then closes the incident without a summary.
Class OcuTalon.Watch.Summary [ Abstract ]
{

/// The catalog keys of the closing lines, by the event that closed the incident.
Parameter CLOSINGKEYS = "dismiss=summary.closedDismiss,closeForReplay=summary.closedReplay,closeQuiet=summary.closedQuiet";

/// How each channel reads in a summary line.
Parameter CHANNELNAMES = "web=the web chat,phone=the Simulated phone,telegram=Telegram,mailbox=the Simulated mailbox";

/// The request states whose answer is approved.
Parameter APPROVEDSTATES = "approved,executing,done,failed";

/// The summary of the incident as a dynamic object {parts, lines}, or "" with the reason in sc. event is the close event (dismiss, closeForReplay or closeQuiet),
/// closedAt the close time (UTC) and onlineDemo 1 on the online demo, where no line names a user.
ClassMethod Build(incident As OcuTalon.Data.Incident, event As %String, closedAt As %String, onlineDemo As %Boolean, Output sc As %Status) As %DynamicObject
{
	Set sc = $$$OK
	Set summary = ""
	Try {
		Set closing = ..Lookup(..#CLOSINGKEYS, event)
		If closing = "" $$$ThrowStatus($SYSTEM.Status.Error(5001, "The event '"_$Get(event)_"' does not close an incident"))
		If '..IsTime(closedAt) $$$ThrowStatus($SYSTEM.Status.Error(5001, "The close time '"_$Get(closedAt)_"' is not a UTC time"))
		Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident.Ref)
		Set common = ##class(OcuTalon.Watch.Notice).Common(incident, .sc)
		$$$ThrowOnError(sc)
		Set parts = []
		Do parts.%Push(..Part("summary.title", {"count": (+incident.Count), "itemNoun": (common.itemNoun), "production": (..ProductionName(incident))}))
		Set seq = 0
		Do ..Event(.timeline, .seq, incident.FirstAt, "summary.firstFailure", {"time": (incident.FirstAt)})
		Do ..Event(.timeline, .seq, incident.NoticedAt, "summary.noticed", {"time": (incident.NoticedAt)})
		Set ran = 0
		Set diagnosed = 0
		Set resent = 0, completed = 0, failedAgain = 0, skipped = 0
		Set position = 0
		Set refs = $ListFromString(incident.RequestRefs)
		While $ListNext(refs, position, ref) {
			If ref = "" Continue
			Set request = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
			If '$IsObject(request) || (request.IncidentRef '= incident.Ref) Continue
			Do ..RequestEvents(incident, request, onlineDemo, .timeline, .seq)
			Set run = ##class(OcuTalon.Data.FixRun).OfRequest(request.Ref)
			If '$IsObject(run) Continue
			Do ..RunEvents(run, request, .timeline, .seq)
			Set class = ##class(OcuTalon.Fix.Kind).ForName(request.FixKind)
			If (class '= "") && ($Parameter(class, "TARGETTYPE") = "contact") Continue
			Set ran = 1
			If (class '= "") && ($Parameter(class, "TARGETTYPE") = "item") Continue
			If (class = "") || $Parameter(class, "DIAGNOSED") Set diagnosed = 1
			Set resent = resent + run.Resent
			Set completed = completed + run.Completed
			Set failedAgain = failedAgain + run.FailedAgain
			Set skipped = skipped + run.Skipped
		}
		Do ..Event(.timeline, .seq, closedAt, closing, {"time": (closedAt)})
		Set key = ""
		For {
			Set key = $Order(timeline(key), 1, line)
			Quit:key=""
			Do parts.%Push(line)
		}
		If incident.Fallback {
			Do parts.%Push(..Part("summary.noCause", {"fallbackReason": (##class(OcuTalon.Watch.Notice).Reason(incident))}))
		} Else {
			If ..Clean(incident.Cause) '= "" Do parts.%Push(..Part("summary.cause", {"cause": (..Clean(incident.Cause))}))
			Set element = ..Clean(incident.Element)
			If (element '= "") && (..Shown(element) '= ".") Do parts.%Push(..Part("summary.element", {"element": (element)}))
		}
		Set evidence = ..Evidence(incident.DecisionRef)
		If evidence '= "" Do parts.%Push(..Part("summary.evidence", {"evidence": (evidence)}))
		Set sample = ..Clean(##class(OcuTalon.Watch.ErrorText).Summary(incident.SampleError))
		If sample '= "" Do parts.%Push(..Part("summary.sampleError", {"error": (sample)}))
		If diagnosed && 'incident.Fallback {
			If ..Clean(incident.FixSummary) '= "" Do parts.%Push(..Part("summary.fix", {"fix": (..Clean(incident.FixSummary))}))
		}
		If 'ran {
			Do parts.%Push(..Part("summary.noFixRan", {}))
		}
		If (incident.Fallback || 'ran) && (groups.Count() > 0) {
			Set lines = ##class(OcuTalon.Watch.Notice).Groups(incident, groups, .sc, 1)
			$$$ThrowOnError(sc)
			Do parts.%Push(..Part("summary.groups", {"groups": (lines)}))
		}
		Set messages = {}
		Do messages.%Set("failed", +incident.Count, "number")
		Do messages.%Set("resent", resent, "number")
		Do messages.%Set("completed", completed, "number")
		Do messages.%Set("failedAgain", failedAgain, "number")
		Do messages.%Set("skipped", skipped, "number")
		Do parts.%Push(..Part("summary.messages", messages))
		Do parts.%Push(..Cost(incident.DecisionRef))
		Set summary = {"parts": (parts), "lines": []}
	} Catch exception {
		Set sc = exception.AsStatus()
		Set summary = ""
	}
	Quit summary
}

/// The stored summary of the incident (its Ref) rendered for the channel (web, phone or telegram) through DigestText.Text: one catalog line per part. "" with an
/// error status when the incident does not exist, has no summary or a part cannot be rendered.
ClassMethod Text(incidentRef As %String, channel As %String, Output sc As %Status) As %String
{
	Set sc = $$$OK
	Set incident = $Select($Get(incidentRef) = "": "", 1: ##class(OcuTalon.Data.Incident).RefIndexOpen(incidentRef))
	If '$IsObject(incident) {
		Set sc = $SYSTEM.Status.Error(5001, "There is no incident to summarize")
		Quit ""
	}
	If incident.Summary = "" {
		Set sc = $SYSTEM.Status.Error(5001, "The incident "_incident.Ref_" has no summary")
		Quit ""
	}
	Quit ##class(OcuTalon.Channel.DigestText).Text(incident.Summary, channel, .sc)
}

/// The lines of a request: raised, then its answer.
ClassMethod RequestEvents(incident As OcuTalon.Data.Incident, request As OcuTalon.Bridge.Data.ApprovalRequest, onlineDemo As %Boolean, ByRef timeline, ByRef seq As %Integer) [ Private ]
{
	Set noun = ##class(OcuTalon.Watch.Notice).Noun(incident, request.DryRun)
	Set count = ..Resend(request)
	Set parameters = ..Parameters(request)
	If request.FixKind = "suspend_item" {
		Do ..Event(.timeline, .seq, request.RaisedAt, "summary.requestedSuspend", {"time": (request.RaisedAt), "item": (parameters.%Get("item"))})
	} ElseIf request.FixKind = "resume_item" {
		Do ..Event(.timeline, .seq, request.RaisedAt, "summary.requestedResume", {"time": (request.RaisedAt), "item": (parameters.%Get("item"))})
	} ElseIf request.FixKind = "reroute" {
		If count '= "" Do ..Event(.timeline, .seq, request.RaisedAt, "summary.requestedReroute", {"time": (request.RaisedAt), "count": (count), "itemNoun": (noun), "to": (parameters.%Get("target"))})
	} ElseIf request.FixKind = "partner_warning" {
		Do ..Event(.timeline, .seq, request.RaisedAt, "summary.requestedPartner", {"time": (request.RaisedAt), "count": ($Length(request.FixTargets, ","))})
	} ElseIf count '= "" {
		Do ..Event(.timeline, .seq, request.RaisedAt, "summary.requested", {"time": (request.RaisedAt), "count": (count), "itemNoun": (noun)})
	}
	Set state = request.State
	If state = "expired" {
		Do ..Event(.timeline, .seq, request.ExpiresAt, "summary.expired", {"time": (request.ExpiresAt)})
		Quit
	}
	If (state '= "rejected") && '$ListFind($ListFromString(..#APPROVEDSTATES), state) Quit
	Set channel = ..Lookup(..#CHANNELNAMES, request.AnsweredChannel)
	If channel = "" Quit
	Set approved = (state '= "rejected")
	Set slots = {"time": (request.AnsweredAt), "channel": (channel)}
	Set key = $Select(approved: "summary.approved", 1: "summary.rejected")
	If 'onlineDemo && (..Clean(request.AnsweredBy) '= "") {
		Do slots.%Set("user", ..Clean(request.AnsweredBy))
		Set key = key_"By"
	}
	Do ..Event(.timeline, .seq, request.AnsweredAt, key, slots)
}

/// The lines of a fix run: started, then ended or interrupted when it has ended. The end of a run of a kind whose targets are items says what happened to the item
/// (suspended, resumed or not changed), not the message counts. A run of a kind whose targets are contacts is not a fix: it has no started or interrupted line, only its end, which
/// says whether the notice was sent, kept as a draft or not sent.
ClassMethod RunEvents(run As OcuTalon.Data.FixRun, request As OcuTalon.Bridge.Data.ApprovalRequest, ByRef timeline, ByRef seq As %Integer) [ Private ]
{
	Set class = ##class(OcuTalon.Fix.Kind).ForName(request.FixKind)
	If (class '= "") && ($Parameter(class, "TARGETTYPE") = "contact") {
		If run.EndedAt = "" Quit
		Set key = $Select(+run.Completed > 0: "summary.partnerSent", (request.State = "failed") && (run.Reason = $Parameter(class, "NOTSETUP")): "summary.partnerKept", 1: "summary.partnerNotSent")
		Do ..Event(.timeline, .seq, run.EndedAt, key, {"time": (run.EndedAt)})
		Quit
	}
	Do ..Event(.timeline, .seq, run.StartedAt, "summary.fixStarted", {"time": (run.StartedAt)})
	If run.EndedAt = "" Quit
	If +run.Interrupted > 0 {
		Do ..Event(.timeline, .seq, run.EndedAt, "summary.fixInterrupted", {"time": (run.EndedAt), "resent": (+run.Resent)})
		Quit
	}
	If (class '= "") && ($Parameter(class, "TARGETTYPE") = "item") {
		Set item = ..Parameters(request).%Get("item")
		Set key = $Select(+run.Completed > 0: $Select($Parameter(class, "ENABLE"): "summary.itemResumed", 1: "summary.itemSuspended"), 1: "summary.itemNotChanged")
		Do ..Event(.timeline, .seq, run.EndedAt, key, {"time": (run.EndedAt), "item": (item)})
		Quit
	}
	Set slots = {"time": (run.EndedAt)}
	Do slots.%Set("resent", +run.Resent, "number")
	Do slots.%Set("completed", +run.Completed, "number")
	Do slots.%Set("failedAgain", +run.FailedAgain, "number")
	Do slots.%Set("skipped", +run.Skipped, "number")
	Do ..Event(.timeline, .seq, run.EndedAt, "summary.fixEnded", slots)
}

/// The request's FixParameters as a dynamic object; {} when they are not one.
ClassMethod Parameters(request As OcuTalon.Bridge.Data.ApprovalRequest) As %DynamicObject [ Private ]
{
	Set parameters = {}
	Try {
		Set parsed = {}.%FromJSON(request.FixParameters)
		If $IsObject(parsed) && parsed.%IsA("%Library.DynamicObject") Set parameters = parsed
	} Catch {
		Set parameters = {}
	}
	Quit parameters
}

/// The number of messages the request's dry run said it would resend (resend, else affected); "" when the dry run holds neither as a whole number.
ClassMethod Resend(request As OcuTalon.Bridge.Data.ApprovalRequest) As %String [ Private ]
{
	Set count = ""
	Try {
		Set dryRun = {}.%FromJSON(request.DryRun)
		For name = "resend", "affected" {
			Set value = dryRun.%Get(name)
			If (count = "") && (value ? 1.N) Set count = +value
		}
	} Catch {
		Set count = ""
	}
	Quit count
}

/// Adds the part to the timeline, under its time and the next sequence number, when the time is a UTC time; a line without a time is left out.
ClassMethod Event(ByRef timeline, ByRef seq As %Integer, time As %String, key As %String, slots As %DynamicObject) [ Private ]
{
	If '..IsTime(time) Quit
	Set seq = seq + 1
	Set timeline(time_"#"_$Translate($Justify(seq, 4), " ", "0")) = ..Part(key, slots)
}

/// One part {key, slots}.
ClassMethod Part(key As %String, slots As %DynamicObject) As %DynamicObject [ Private ]
{
	Quit {"key": (key), "slots": (slots)}
}

/// The cost part of the diagnosis decision: summary.cost with the sum of its usage rows (0 when it has none), or summary.costUnknown when a row has no cost.
ClassMethod Cost(decisionRef As %String) As %DynamicObject [ Private ]
{
	Set totals = ##class(OcuTalon.Bridge.Data.Usage).Totals(decisionRef)
	If totals.rows = 0 Quit ..Part("summary.cost", {"cost": 0})
	If totals.costUSD = "" Quit ..Part("summary.costUnknown", {})
	Quit ..Part("summary.cost", {"cost": (totals.costUSD)})
}

/// The first evidence line of the diagnosis payload of the decision, trimmed; "" when the decision, its payload or its evidence cannot be read.
ClassMethod Evidence(decisionRef As %String) As %String [ Private ]
{
	Set line = ""
	Set decision = $Select(decisionRef = "": "", 1: ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(decisionRef))
	If '$IsObject(decision) || (decision.Payload = "") Quit ""
	Try {
		Set lines = {}.%FromJSON(decision.Payload).evidence
		If $IsObject(lines) && lines.%IsA("%Library.DynamicArray") {
			Set iterator = lines.%GetIterator()
			While iterator.%GetNext(, .item) {
				Set line = ..Clean(item)
				If line '= "" Quit
			}
		}
	} Catch {
		Set line = ""
	}
	Quit line
}

/// The production as the title names it: the display name that Watch.Reader gives it (the Description of the production, as in the watch cards and the
/// incident_summary tool), else its class name when the production is not listed or the list cannot be read.
ClassMethod ProductionName(incident As OcuTalon.Data.Incident) As %String [ Private ]
{
	Set display = ""
	Try {
		If '##class(OcuTalon.Watch.Reader).Admits(incident.Namespace, incident.Production, .display) Set display = ""
	} Catch {
		Set display = ""
	}
	Quit $Select(..Shown(display) '= "": display, 1: incident.Production)
}

/// The value of a name in a map written "name=value,name=value"; "" when the name is not in it.
ClassMethod Lookup(map As %String, name As %String) As %String [ Private ]
{
	Set found = ""
	If $Get(name) '= "" {
		For i = 1:1:$Length(map, ",") {
			Set pair = $Piece(map, ",", i)
			If $Piece(pair, "=", 1) = name Set found = $Piece(pair, "=", 2, *) Quit
		}
	}
	Quit found
}

/// 1 when the text is a UTC time like 2026-10-16T18:12:00Z.
ClassMethod IsTime(text As %String) As %Boolean [ Private ]
{
	Quit $Get(text) ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z"
}

/// A row's text as the slot takes it: trimmed; "" when there is none, or when nothing of it would show (the renderer drops invisible and control characters and
/// refuses a slot left empty, which would make the whole summary unreadable).
ClassMethod Clean(value As %String) As %String [ Private ]
{
	Set value = $ZStrip($Get(value), "<>W")
	Quit $Select(..Shown(value) = "": "", 1: value)
}

/// What of the text would show: the text without its whitespace and without the characters the renderer drops (invisible and control characters).
ClassMethod Shown(value As %String) As %String [ Private ]
{
	Quit $ZStrip($Translate($Get(value), $Char(133, 160, 1564, 5760, 6158, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8203, 8206, 8207, 8232, 8233, 8234, 8235, 8236, 8237, 8238, 8239, 8287, 8288, 8289, 8290, 8291, 8292, 8294, 8295, 8296, 8297, 12288, 65279, 65529, 65530, 65531)), "*CW")
}

}
