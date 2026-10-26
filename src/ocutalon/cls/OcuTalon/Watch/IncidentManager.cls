/// IncidentManager, the business process that settles failures into incidents and moves each incident through its states (AD-15). Built in parts
/// during Epic 5. It alone writes OcuTalon.Data.Incident and OcuTalon.Data.FailureGroup, and alone publishes the incident and watch.progress events,
/// through OcuTalon.Live.Publish and only after its own change has committed (AD-12, AD-33). Its item keeps PoolSize 1, so one job serializes every row
/// change. Nothing of what it decides is in memory: the rows and the persisted waiter instances are the state (AD-5).
///   - A FailureBatch (OcuTalon.Watch.Msg.FailureBatch, from FailurePoller) is grouped by production item and error pattern (OcuTalon.Watch.Settle.Pattern),
///     per production and scope (the batch's OwnerRef). A failure joins the newest not-closed incident of its cause, compared exactly; with none, the
///     batch makes an open incident and its group, with its Ref (OcuTalon.Bridge.Ids.NewRef) at the first failure. A failure is held once, by its key
///     (OcuTalon.Watch.Mark.KeyOf) in the group's Seen set (the newest OcuTalon.Watch.Settle SEENMAX keys): a key already held adds no count and no
///     time. Count is the failures held, FirstAt and LastAt the earliest and latest FailedAt. The batch's rows are saved in one transaction.
///   - After the commit, each new incident is announced on its recipients' streams (watch.progress noticed), each new group gets one waiter (a
///     OcuTalon.Watch.Msg.Settle that IncidentManager sends itself, with the session cleared so that the incident has its own trace session, AD-26),
///     and, for an incident that has been noticed (NoticedAt set), the new count goes out as one incident event (Live.Payload.Incident.FromRow) to
///     each recipient. The recipients are those of OcuTalon.Data.Session.Recipients. A failed read of them logs one Type 3 warning and publishes
///     nothing, and never means that nobody watches; a failed publish to a session leaves the other sessions their event and logs one Type 3 warning
///     for the event. The rows stand either way.
///   - The waiter records the incident's trace session (TraceHeaderId), publishes watch.progress settling, and waits with an alarm
///     (Ens.BusinessProcess.SetTimer) for as long as OcuTalon.Watch.Settle.Wait says, at most two minutes per alarm (Settle.Alarm, AD-5). On each wake it re-reads the incident and group rows, so a
///     failure that came meanwhile moves the end. The settle rule ends when the quiet time (setting watch.settleQuietSeconds, 10 by default) has passed
///     since LastAt or the maximum (watch.settleMaxSeconds, 30) since FirstAt, whichever comes first: it sets NoticeCount to Count, once, and completes.
///     A waiter whose incident is gone, closed or settled completes and writes nothing.
///   - At the settle end the waiter diagnoses the incident (Story 5.4, AD-6, AD-15): it builds the evidence pack of the live incident
///     (OcuTalon.Watch.EvidencePack), stores the code noun of the sample's body class (OcuTalon.Watch.ItemNoun) on the row, publishes watch.progress
///     diagnosing after that commit and sends one OcuTalon.Bridge.Msg.Request to the Decide item, asynchronously, with a response required and the
///     completion key diagnose: kind diagnose, provenance untrusted, ItemId the incident's Ref, OwnerRef its owner, TraceRef the waiter's
///     SuperSession, ThreadSessionId the waiter's own session (the incident's TraceHeaderId), a code-written Summary and the pack as Input. It never
///     goes to OutcomeRouter (AD-30). The answer (a DecisionResponse) sets DecisionRef, Fallback and FallbackReason on the row; a usable answer (Fallback
///     0) also sets Cause, CauseCategory, Element, FixSummary and, when the payload gives both forms, ItemNoun, from the checked payload, and a fallback
///     stores none of them (AD-8). An error status from Decide is a refused request: it stores Fallback 1 with the reason error and logs one Type 3
///     warning. The answer is written only to a row that exists, is not closed and has no NoticedAt; otherwise it is dropped without an error.
///   - What the rows keep for the notice and Show details (Story 5.8): each FailureGroup has its Seq (1 for an incident's first group), Count, FirstAt and
///     LastAt (kept by Record like the incident's), NoticeCount (set with the incident's at the settle end, in one transaction) and ErrorSummary
///     (OcuTalon.Watch.ErrorText.Summary of its first failure's text); the Incident has FirstHeaderId (the header id of the earliest failure, empty when
///     that is a log row), SampleHeaderId and SampleError (the live pack's sample, stored at the settle end with the code noun) and RequestRefs (written
///     by the story that raises the requests). The groups of an incident are read only through OcuTalon.Data.FailureGroup.OfIncident.
///   - The notice (Story 5.8; AD-15, AD-32): as soon as Answered or Refused has stored the outcome, Notice acts on the row if it exists, is not closed and
///     has no NoticedAt. OcuTalon.Watch.Notice gives the catalog key, the open variant and the slots (producers never render): a fallback, an unknown cause
///     or a cause with no fix gets a notice; a usable data-format diagnosis (a fix) gets none and no row change, because its notice goes out with the dry
///     run and the approval request. Deliver sets NoticedAt (UTC now), the state and the open variant in one save and, after the commit, sends one
///     OcuTalon.Msg.Notification of kind incident to the Notify item, asynchronously and from the waiter, so that it lies in the incident's trace
///     session (AD-26), and publishes the incident event (Live.Payload.Incident.FromRow) on the stream of each session that Session.Recipients gives; the
///     one read of the recipients serves both (Tell). Nobody to tell (owner eval, or instance on the online demo) sends and publishes nothing, with no
///     warning. A failed read of the recipients logs one Type 3 warning and sends nothing; a failed send leaves the other sessions their notice and
///     event and logs one Type 3 warning for the notice. The row stays noticed either way. The incident's states beyond open are Story 5.5's.
///   - Anything else is still answered "not implemented" (the stub's answer), so the commands and the approval outcomes that Story 5.5 builds are not
///     accepted by mistake.
Class OcuTalon.Watch.IncidentManager Extends Ens.BusinessProcess
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

/// The states and stages that this class writes, from Msg.Enum.
Parameter OPEN = "open";

Parameter CLOSED = "closed";

/// The completion key of the waiter's alarm.
Parameter ALARMKEY = "settle";

/// The completion key of the diagnose request.
Parameter DIAGNOSEKEY = "diagnose";

/// The configuration item that diagnoses (AD-6).
Parameter DECIDE = "Decide";

/// The request kind and provenance of the diagnosis.
Parameter KIND = "diagnose";

Parameter PROVENANCE = "untrusted";

/// The fallback reason of a request that Decide refused (Msg.Enum FALLBACKREASON).
Parameter REFUSEDREASON = "error";

/// The longest summary of a request, in characters (Bridge.Msg.Request).
Parameter SUMMARYMAX = 80;

/// The item that routes a Notification (AD-32), and the kind of an incident notice (Msg.Enum NOTIFICATIONKIND).
Parameter NOTIFY = "Notify";

Parameter NOTICEKIND = "incident";

/// The live event type of an incident's public view.
Parameter INCIDENTEVENT = "incident";

Parameter LOGDIAGNOSE = "IncidentManager could not diagnose incident ";

Parameter LOGNOTICE = "IncidentManager could not notice incident ";

Parameter LOGSEND = "IncidentManager could not send the notice of incident ";

Parameter LOGTELL = "IncidentManager could not tell the sessions of incident ";

Parameter LOGPUBLISH = "IncidentManager could not publish to the sessions of incident ";

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set response = ""
	If $IsObject(request) {
		If request.%IsA("OcuTalon.Watch.Msg.FailureBatch") Quit ..Batch(request)
		If request.%IsA("OcuTalon.Watch.Msg.Settle") Quit ..Begin(request)
	}
	Quit $$$ERROR($$$NotImplemented)
}

/// An answer by the key of the call: the alarm of the waiter has gone off (look at the rows again and end the settle rule or wait on), or Decide has
/// answered the diagnose request (store the diagnosis or its fallback). An error status of Decide was stored by OnError, so no answer comes with it.
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, pCompletionKey As %String) As %Status
{
	If '$IsObject(request) || 'request.%IsA("OcuTalon.Watch.Msg.Settle") Quit $$$OK
	If pCompletionKey = ..#DIAGNOSEKEY {
		If $IsObject($Get(callresponse)) && callresponse.%IsA("OcuTalon.Bridge.Msg.DecisionResponse") Quit ..Answered(request.IncidentRef, callresponse)
		Quit $$$OK
	}
	Quit ..Check(request.IncidentRef)
}

/// An error answer to the diagnose request: Decide refused it, so the incident is stored with the fallback error (Refused). An error with any other
/// key stays an error, so that the framework logs it.
Method OnError(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, pErrorStatus As %Status, pCompletionKey As %String) As %Status
{
	If (pCompletionKey '= ..#DIAGNOSEKEY) || '$IsObject(request) || 'request.%IsA("OcuTalon.Watch.Msg.Settle") Quit pErrorStatus
	Do ..Refused(request.IncidentRef, pErrorStatus)
	Quit $$$OK
}

/// A batch: groups its failures, saves the rows of every cause in one transaction and then tells the sessions and starts the waiters.
Method Batch(batch As OcuTalon.Watch.Msg.FailureBatch) As %Status [ Private ]
{
	Set sc = ..Record(batch, .count, .rows, .added)
	If $$$ISERR(sc) Quit sc
	For i = 1:1:count {
		If added(i) = "new" {
			Set payload = ##class(OcuTalon.Live.Payload.WatchProgress).%New()
			Set payload.Ref = rows(i).Ref
			Set payload.Stage = "noticed"
			Do ..Tell(rows(i), "watch.progress", payload)
		}
	}
	For i = 1:1:count {
		If added(i) = "new" Set sc = $SYSTEM.Status.AppendStatus(sc, ..Start(rows(i).Ref))
	}
	For i = 1:1:count {
		If (added(i) '= "new") && (rows(i).NoticedAt '= "") Do ..Tell(rows(i), "incident", ##class(OcuTalon.Live.Payload.Incident).FromRow(rows(i)))
	}
	Quit sc
}

/// The failures of the batch, grouped by cause, saved as incident and group rows in one transaction. count is the number of causes that gained
/// failures and rows(i) their saved incidents; added(i) is "new" for an incident that this batch made, "more" for one that gained failures.
Method Record(batch As OcuTalon.Watch.Msg.FailureBatch, Output count As %Integer, Output rows, Output added) As %Status [ Private ]
{
	Set count = 0
	Kill rows, added
	Set causes = 0
	For i = 1:1:batch.Failures.Count() {
		Set failure = batch.Failures.GetAt(i)
		Set text = ##class(OcuTalon.Watch.Settle).Pattern(failure.ErrorText)
		Set cause = 0
		For c = 1:1:causes {
			If (itemOf(c) = failure.ItemName) && (patternOf(c) = text) {
				Set cause = c
				Quit
			}
		}
		If 'cause {
			Set causes = causes + 1
			Set cause = causes
			Set itemOf(cause) = failure.ItemName
			Set patternOf(cause) = text
			Set textOf(cause) = failure.ErrorText
			Set keysOf(cause) = ""
		}
		Set key = ##class(OcuTalon.Watch.Mark).KeyOf(failure.Kind, failure.HeaderId, failure.LogId)
		If '$Data(failedAt(cause, key)) {
			Set failedAt(cause, key) = $Select(failure.FailedAt '= "": failure.FailedAt, 1: batch.PolledAt)
			Set keysOf(cause) = keysOf(cause)_$Select(keysOf(cause) = "": "", 1: ",")_key
		}
	}
	Set sc = $$$OK
	Set level = $TLevel
	TSTART
	Try {
		For cause = 1:1:causes {
			Set incident = ..Find(batch, itemOf(cause), patternOf(cause), .group)
			Set new = '$IsObject(incident)
			If new {
				Set incident = ##class(OcuTalon.Data.Incident).%New()
				Set incident.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
				Set incident.OwnerRef = batch.OwnerRef
				Set incident.Namespace = batch.Namespace
				Set incident.Production = batch.Production
				Set incident.State = ..#OPEN
				Set group = ##class(OcuTalon.Data.FailureGroup).%New()
				Set group.IncidentRef = incident.Ref
				Set group.ItemName = itemOf(cause)
				Set group.ErrorPattern = patternOf(cause)
				Set group.Seq = 1
				Set group.ErrorSummary = ##class(OcuTalon.Watch.ErrorText).Summary(textOf(cause))
			}
			Set group.Seen = ##class(OcuTalon.Watch.Settle).Hold(group.Seen, keysOf(cause), .fresh)
			If fresh = "" Continue
			For i = 1:1:$Length(fresh, ",") {
				Set key = $Piece(fresh, ",", i)
				Set at = failedAt(cause, key)
				Set header = $Select($Extract(key) = "h": $Extract(key, 2, *), 1: "")
				If (incident.FirstAt = "") || (incident.FirstAt ] at) || ((incident.FirstAt = at) && (header '= "") && (incident.FirstHeaderId '= "") && (header < incident.FirstHeaderId)) {
					Set incident.FirstAt = at
					Set incident.FirstHeaderId = header
				}
				If (incident.LastAt = "") || (at ] incident.LastAt) Set incident.LastAt = at
				If (group.FirstAt = "") || (group.FirstAt ] at) Set group.FirstAt = at
				If (group.LastAt = "") || (at ] group.LastAt) Set group.LastAt = at
			}
			Set group.Count = group.Count + $Length(fresh, ",")
			Set incident.Count = incident.Count + $Length(fresh, ",")
			$$$ThrowOnError(group.%Save())
			$$$ThrowOnError(incident.%Save())
			Set count = count + 1
			Set rows(count) = incident
			Set added(count) = $Select(new: "new", 1: "more")
		}
		TCOMMIT
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $TLevel > level TROLLBACK 1
	If $$$ISERR(sc) Set count = 0
	Quit sc
}

/// The newest incident of the batch's owner, production and namespace that is not closed and whose group has the item and pattern, compared exactly (the
/// statements only narrow the rows by the collated indexes); "" when there is none. group is that incident's group.
Method Find(batch As OcuTalon.Watch.Msg.FailureBatch, item As %String, pattern As %String, Output group As OcuTalon.Data.FailureGroup) As OcuTalon.Data.Incident [ Private ]
{
	Set group = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Incident WHERE OwnerRef = ? AND Namespace = ? AND Production = ? AND State <> 'closed' ORDER BY ID DESC", batch.OwnerRef, batch.Namespace, batch.Production)
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The incidents could not be read: "_rs.%Message))
	While rs.%Next() {
		Set incident = ##class(OcuTalon.Data.Incident).%OpenId(rs.%GetData(1))
		If '$IsObject(incident) Continue
		If (incident.OwnerRef '= batch.OwnerRef) || (incident.Namespace '= batch.Namespace) || (incident.Production '= batch.Production) || (incident.State = ..#CLOSED) Continue
		Set groups = ..Groups(incident.Ref)
		For i = 1:1:groups.Count() {
			Set candidate = groups.GetAt(i)
			If (candidate.ItemName = item) && (candidate.ErrorPattern = pattern) {
				Set group = candidate
				Quit
			}
		}
		If $IsObject(group) Quit
	}
	Quit $Select($IsObject(group): incident, 1: "")
}

/// The group rows of the incident, in Seq order, as a list of objects (FailureGroup.OfIncident).
ClassMethod Groups(ref As %String) As %ListOfObjects [ Private ]
{
	Quit ##class(OcuTalon.Data.FailureGroup).OfIncident(ref)
}

/// Sends the incident's waiter: a Settle request to this item, started with the session cleared, so that the waiter has a trace session of its own, and
/// with the batch's SuperSession kept. The batch's session is put back afterwards.
Method Start(ref As %String) As %Status [ Private ]
{
	Set request = ##class(OcuTalon.Watch.Msg.Settle).%New()
	Set request.IncidentRef = ref
	Set session = ..%SessionId
	Set ..%SessionId = ""
	Set sc = ..SendRequestAsync(..%ConfigName, request, 0)
	Set ..%SessionId = session
	Quit sc
}

/// The waiter's start: records its own session as the incident's trace session, tells the sessions that the incident is settling and waits.
Method Begin(request As OcuTalon.Watch.Msg.Settle) As %Status [ Private ]
{
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(request.IncidentRef)
	If '..Waiting(incident) Quit $$$OK
	Set incident.TraceHeaderId = ..%SessionId
	Set sc = incident.%Save()
	If $$$ISERR(sc) Quit sc
	Set payload = ##class(OcuTalon.Live.Payload.WatchProgress).%New()
	Set payload.Ref = incident.Ref
	Set payload.Stage = "settling"
	Do ..Tell(incident, "watch.progress", payload)
	Quit ..Check(request.IncidentRef)
}

/// The settle rule at this moment, from the rows: the rule ends (NoticeCount is set to Count, on the incident and on each of its groups, in one transaction)
/// or the waiter waits on for the seconds that are left.
Method Check(ref As %String) As %Status [ Private ]
{
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	If '..Waiting(incident) Quit $$$OK
	Do ##class(OcuTalon.Watch.Settle).Values(.quiet, .max)
	Set seconds = ##class(OcuTalon.Watch.Settle).Wait(incident.FirstAt, incident.LastAt, ##class(OcuTalon.Data.Time).NowUtc(), quiet, max)
	If seconds > 0 Quit ..SetTimer(##class(OcuTalon.Watch.Settle).Alarm(seconds), ..#ALARMKEY)
	Set sc = $$$OK
	Set level = $TLevel
	TSTART
	Try {
		Set groups = ..Groups(incident.Ref)
		For i = 1:1:groups.Count() {
			Set group = groups.GetAt(i)
			Set group.NoticeCount = group.Count
			$$$ThrowOnError(group.%Save())
		}
		Set incident.NoticeCount = incident.Count
		$$$ThrowOnError(incident.%Save())
		TCOMMIT
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $TLevel > level TROLLBACK 1
	If $$$ISERR(sc) Quit sc
	Quit ..Diagnose(incident)
}

/// The diagnosis of the incident whose settle rule has just ended (see the class description): the pack, the code noun and the pack's sample on the row, watch.progress
/// diagnosing after the commit and the request to Decide. A pack that cannot be built, or a request that cannot be sent, is a refused request (Refused).
Method Diagnose(incident As OcuTalon.Data.Incident) As %Status [ Private ]
{
	Set sc = ##class(OcuTalon.Watch.EvidencePack).Build(incident, .pack)
	If $$$ISOK(sc) {
		Set incident.ItemNoun = ##class(OcuTalon.Watch.ItemNoun).For($Select($IsObject(pack.sample): pack.sample.bodyClass, 1: ""))
		Set incident.SampleHeaderId = ""
		Set incident.SampleError = ""
		If $IsObject(pack.sample) {
			Set header = pack.sample.headerId
			If (header '= "") && (header = (header \ 1)) && (header > 0) Set incident.SampleHeaderId = header
			Set incident.SampleError = $Extract(pack.sample.error, 1, 1000)
		}
		Set sc = incident.%Save()
	}
	If $$$ISERR(sc) {
		Do ..Refused(incident.Ref, sc)
		Quit $$$OK
	}
	Set payload = ##class(OcuTalon.Live.Payload.WatchProgress).%New()
	Set payload.Ref = incident.Ref
	Set payload.Stage = "diagnosing"
	Do ..Tell(incident, "watch.progress", payload)
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = ..#KIND
	Set request.Provenance = ..#PROVENANCE
	Set request.ItemId = incident.Ref
	Set request.OwnerRef = incident.OwnerRef
	Set request.TraceRef = ..%SuperSession
	Set request.ThreadSessionId = ..%SessionId
	Set request.Summary = $Extract(incident.NoticeCount_" failures at "_pack.item, 1, ..#SUMMARYMAX)
	Set request.Input = ##class(OcuTalon.Watch.EvidencePack).Input(pack)
	Set sc = ..SendRequestAsync(..#DECIDE, request, 1, ..#DIAGNOSEKEY)
	If $$$ISERR(sc) Do ..Refused(incident.Ref, sc)
	Quit $$$OK
}

/// The answer of Decide to the diagnose request of the incident: DecisionRef, Fallback and FallbackReason go on the row, and, for a usable answer, the
/// cause, its category, the element, the fix summary and the noun of the checked payload; then the notice step (Notice). Written only to a row that exists,
/// is not closed and has no NoticedAt; any other answer is dropped. A payload that cannot be read is a refused request.
Method Answered(ref As %String, answer As OcuTalon.Bridge.Msg.DecisionResponse) As %Status [ Private ]
{
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	If '..Open(incident) Quit $$$OK
	Set incident.Cause = ""
	Set incident.CauseCategory = ""
	Set incident.Element = ""
	Set incident.FixSummary = ""
	If 'answer.Fallback {
		Set sc = $$$OK
		Try {
			Set diagnosis = ##class(%DynamicObject).%FromJSON(answer.Payload)
			Set incident.Cause = diagnosis.cause
			Set incident.CauseCategory = diagnosis.causeCategory
			Set incident.Element = diagnosis.elementAtFault
			Set incident.FixSummary = diagnosis.fixSummary
			If $IsObject(diagnosis.itemNoun) && (diagnosis.itemNoun.one '= "") && (diagnosis.itemNoun.other '= "") {
				Set incident.ItemNoun = {"one": (diagnosis.itemNoun.one), "other": (diagnosis.itemNoun.other)}.%ToJSON()
			}
		} Catch exception {
			Set sc = exception.AsStatus()
		}
		If $$$ISERR(sc) {
			Do ..Refused(ref, sc)
			Quit $$$OK
		}
	}
	Set incident.DecisionRef = answer.DecisionRef
	Set incident.Fallback = +answer.Fallback
	Set incident.FallbackReason = answer.FallbackReason
	Set sc = incident.%Save()
	If $$$ISOK(sc) Do ..Notice(ref)
	Quit sc
}

/// The incident stored as refused: Fallback 1 with the reason error and no diagnosis, and one Type 3 warning with the error (through the redactor), then the
/// notice step (Notice). Written only to a row that exists, is not closed and has no NoticedAt. The warning is logged either way.
Method Refused(ref As %String, error As %Status) [ Private ]
{
	$$$LOGWARNING(..#LOGDIAGNOSE_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(error)))
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	If '..Open(incident) Quit
	Set incident.Cause = ""
	Set incident.CauseCategory = ""
	Set incident.Element = ""
	Set incident.FixSummary = ""
	Set incident.Fallback = 1
	Set incident.FallbackReason = ..#REFUSEDREASON
	Set sc = incident.%Save()
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGDIAGNOSE_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Quit
	}
	Do ..Notice(ref)
}

/// The notice step after the outcome of the diagnosis is stored: acts only on a row that exists, is not closed and has no NoticedAt. The key, the open
/// variant and the slots come from OcuTalon.Watch.Notice. A usable diagnosis with a fix gets nothing here (Notice.Key is empty): the row stays open and
/// unnoticed. Slots that cannot be built, or an error thrown in the step, log one Type 3 warning (the row stays as it was saved: a thrown error after the
/// notice's save leaves it noticed).
Method Notice(ref As %String) [ Private ]
{
	Try {
		Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
		If '..Open(incident) Quit
		Set key = ##class(OcuTalon.Watch.Notice).Key(incident)
		If key = "" Quit
		Set slots = ##class(OcuTalon.Watch.Notice).Slots(incident, , .sc)
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGNOTICE_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
			Quit
		}
		Do ..Deliver(incident, ..#OPEN, ##class(OcuTalon.Watch.Notice).Variant(incident), key, slots)
	} Catch exception {
		$$$LOGWARNING(..#LOGNOTICE_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(exception.AsStatus())))
	}
}

/// Notices the incident: sets NoticedAt (UTC now), the state and the open variant in one save and, after the commit, sends one Notification of kind incident
/// with the catalog key, the slots, the row's DecisionRef and the approval request's Ref (empty for a notice without one) to each recipient session, then
/// publishes the incident event on that session's stream (Tell). The row stays noticed whatever happens to the sends. A save that fails logs one Type 3
/// warning and sends nothing.
Method Deliver(incident As OcuTalon.Data.Incident, state As %String, variant As %String, key As %String, slots As %DynamicObject, approvalRef As %String = "") [ Private ]
{
	Set incident.NoticedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set incident.State = state
	Set incident.OpenVariant = variant
	Set sc = incident.%Save()
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGNOTICE_incident.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Quit
	}
	Set notice = ##class(OcuTalon.Msg.Notification).%New()
	Set notice.Kind = ..#NOTICEKIND
	Set notice.CatalogKey = key
	Set notice.Slots = slots.%ToJSON()
	Set notice.IncidentRef = incident.Ref
	Set notice.DecisionRef = incident.DecisionRef
	Set notice.ApprovalRef = approvalRef
	Do ..Tell(incident, ..#INCIDENTEVENT, ##class(OcuTalon.Live.Payload.Incident).FromRow(incident), notice)
}

/// Sends the notification to the Notify item, asynchronously, with no answer wanted (a seam for the tests).
Method SendNotice(notification As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#NOTIFY, notification, 0)
}

/// 1 when the incident exists, is not closed and has no NoticedAt: its diagnosis may still be written.
ClassMethod Open(incident As OcuTalon.Data.Incident) As %Boolean [ Private ]
{
	Quit $IsObject(incident) && (incident.State '= ..#CLOSED) && (incident.NoticedAt = "")
}

/// 1 when the incident exists, is not closed, has not settled and has a group row: its settle rule still runs.
ClassMethod Waiting(incident As OcuTalon.Data.Incident) As %Boolean [ Private ]
{
	If '$IsObject(incident) || (incident.State = ..#CLOSED) || (incident.NoticeCount '= "") Quit 0
	Quit ..Groups(incident.Ref).Count() > 0
}

/// Publishes the payload as an event of the type on the stream of each session that Session.Recipients gives for the incident and, when a notification is
/// given, first sends a copy of it to each of them (its SessionRef set to the session; one read of the recipients serves both). An error in reading them
/// publishes and sends nothing, and an error in a send or a publish leaves the other sessions their notice and event; each logs one Type 3 warning per event
/// or per notice (with the first failed one's error), and the rows stand. A failed send does not keep the event from its session.
Method Tell(incident As OcuTalon.Data.Incident, type As %String, payload As %RegisteredObject, notification As OcuTalon.Msg.Notification = "") [ Private ]
{
	Set recipients = ##class(OcuTalon.Data.Session).Recipients(incident.OwnerRef, incident.Ref, .sc)
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGTELL_incident.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Quit
	}
	Set failed = ""
	Set unsent = ""
	Set position = 0
	While $ListNext(recipients, position, stream) {
		If $IsObject(notification) {
			Set copy = notification.%ConstructClone()
			Set copy.SessionRef = stream
			Set sc = ..SendNotice(copy)
			If $$$ISERR(sc) && (unsent = "") Set unsent = sc
		}
		Set sc = ##class(OcuTalon.Live.Publish).Publish(stream, type, payload)
		If $$$ISERR(sc) && (failed = "") Set failed = sc
	}
	If unsent '= "" {
		$$$LOGWARNING(..#LOGSEND_incident.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(unsent)))
	}
	If failed '= "" {
		$$$LOGWARNING(..#LOGPUBLISH_incident.Ref_" ("_type_"): "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(failed)))
	}
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
