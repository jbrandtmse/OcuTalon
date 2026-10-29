/// IncidentManager, the business process that settles failures into incidents and moves each incident through its states (AD-15). It alone writes OcuTalon.Data.Incident and OcuTalon.Data.FailureGroup, and alone publishes the incident and watch.progress events,
/// through OcuTalon.Live.Publish and only after its own change has committed (AD-12, AD-33). Its item keeps PoolSize 1, so one job serializes every row
/// change. Nothing of what it decides is in memory: the rows and the persisted waiter instances are the state (AD-5).
///   - A FailureBatch (OcuTalon.Watch.Msg.FailureBatch, from FailurePoller) is grouped by production item and error pattern (OcuTalon.Watch.Settle.Pattern),
///     per production and scope (the batch's OwnerRef). A failure joins the newest not-closed incident of its cause, compared exactly; with none, the
///     batch makes an open incident and its group, with its Ref (OcuTalon.Bridge.Ids.NewRef) at the first failure. A failure is held once, by its key
///     (OcuTalon.Watch.Mark.KeyOf) in the group's Seen set (the newest OcuTalon.Watch.Settle SEENMAX keys): a key already held adds no count and no
///     time. Count is the failures held, FirstAt and LastAt the earliest and latest FailedAt. The batch's rows are saved in one transaction.
///   - After the commit, each new incident is announced on its recipients' streams (watch.progress noticed), each new group gets one waiter (a
///     OcuTalon.Watch.Msg.Settle that IncidentManager sends itself, with the session cleared so that the incident has its own trace session, AD-26; the
///     waiter of a later round is sent in that trace session),
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
///   - The notice (Story 5.8, Story 7.2; AD-15, AD-32): as soon as Answered or Refused has stored the outcome, Notice acts on the row if it exists, is not closed and
///     has no NoticedAt. OcuTalon.Watch.Notice gives the catalog key, the open variant and the slots (producers never render): a fallback, an unknown cause
///     or a cause with no fix gets a notice. A usable data-format diagnosis (a fix) is proposed (Propose): the waiter sends one OcuTalon.Fix.Msg.DryRun
///     (the incident, the fix kind and the parameters of the checked payload) to FixExecutor, asynchronously, with a response required and the completion
///     key dryrun, in the incident's trace session; the kind and the parameters travel in that ask and are read back from it, no column holds them. The
///     answer (Proposed) acts only on an open, unnoticed incident: a refused dry run (a Reason, with one Type 3 warning) or one with nothing to resend
///     (no Targets) gets the no-fix notice (NoFix: incident.noFix, open variant no_fix), and so does a dry run that cannot be asked for (a failed send, an
///     error answer, no fix kind: one Type 3 warning). Otherwise the table accepts raised, the with-fix slots are built (Notice.WithFixSlots with the dry
///     run) and OcuTalon.Bridge.Approval.Raise is called exactly once (RaiseRequest), outside any transaction, with a fix request that holds the incident,
///     its owner, the result target IncidentManager, the waiter's SuperSession as TraceRef when that is a Ref, the dry run's JSON, the fix kind, its
///     parameters and the fixed targets as the dry run gave them; the incident's TraceHeaderId and SuperSession are passed so that the hold joins the
///     incident's trace session. A failed Raise logs one Type 3 warning and takes the no-fix route; slots that cannot be built log one and leave the row
///     unnoticed. The Ref is appended to RequestRefs and Deliver saves it with NoticedAt and the state awaiting_approval in one save; a save that fails
///     cancels the request (CancelRequest), so that nothing stays approvable that no incident lists. The with-fix notice carries the request's Ref as
///     ApprovalRef, and no notification of kind approval is sent for the first request.
///     Deliver sets NoticedAt (UTC now), the state and the open variant in one save and, after the commit, sends one
///     OcuTalon.Msg.Notification of kind incident to the Notify item, asynchronously and from the waiter, so that it lies in the incident's trace
///     session (AD-26), and publishes the incident event (Live.Payload.Incident.FromRow) on the stream of each session that Session.Recipients gives; the
///     one read of the recipients serves both (Tell). Nobody to tell (owner eval, or instance on the online demo) sends and publishes nothing, with no
///     warning. A failed read of the recipients logs one Type 3 warning and sends nothing; a failed send leaves the other sessions their notice and
///     event and logs one Type 3 warning for the notice. The row stays noticed either way. Notice takes the state and the variant from the table.
///   - The states (Story 5.5; AD-15): OcuTalon.Watch.Transitions is the one table, and every input goes through it: the notice step, the IncidentCommand verbs
///     (dismiss, closeForReplay, closeQuiet), ApprovalOutcome (from ApprovalHold) and OcuTalon.Fix.Msg.FixResult (from FixExecutor). The facts that the table
///     needs are read from the rows each time (AD-11): an incident's requests are the entries of RequestRefs whose ApprovalRequest row exists and names the
///     incident. An accepted move saves the new state (Move: state, open variant and, for a close, ClosedAt, in one save) and then, for a noticed incident,
///     publishes the incident event through Tell, even when the state stays the same, because the payload's requests may have changed; when the table says so
///     it then sends one OcuTalon.Fix.Msg.Execute (only the request's Ref) to FixExecutor, asynchronously and in the incident's trace session (AD-26). A failed
///     send logs one Type 3 warning and the row stays as saved. An accepted approved, rejected or expired outcome also sends one Notification of kind answered
///     (answered.approved and answered.rejected with the channel and time of the answer, answered.expired with the request's ExpiresAt; the request's Ref and the
///     incident's; no DecisionRef) to each recipient, through the same Move and Tell as the event, even when the state stays awaiting_approval or fixing, and an
///     approved one before the Execute goes out (Story 7.3). An accepted final or interrupted FixResult (Story 7.3) sends each recipient one Notification of
///     kind result the same way (Notice.ResultKey picks the catalog key by the Result texts convention from the request's state and the result's counts, and
///     Notice.ResultSlots builds the slots, with the item noun of the request's dry run, else the incident's, else the code noun; the request's Ref and the
///     incident's; no DecisionRef); a progress FixResult, a refused one, and one whose slots cannot be built (one Type 3 warning, LOGRESULT) send none. A refused
///     ApprovalOutcome or FixResult writes, sends and publishes nothing and logs one Type 4
///     line; a repeat of an outcome is refused because the request's row does not show it any more.
///   - An IncidentCommand is answered synchronously with a CommandResult (AD-1): unknown_command, not_found (also for a dismiss from a session that is not a
///     recipient of the incident), not_quiet (a closeQuiet within QUIETSECONDS of LastAt, by the clock that QuietNow gives), not_allowed (the table refuses), failed (the recipients or the save could not be read or made;
///     a Type 3 warning is logged) or Ok 1 with the outcome closed;
///     an answer that found the incident for its caller carries the state and open variant as stored as Data (a failed save too, read again from the row; a failed
///     read of the recipients has no caller to tell, like a dismiss from a session that is not a recipient). closeForReplay and closeQuiet check no session: only
///     product code sends them.
///   - Later requests (Story 7.6; AD-15, AD-16): every dry-run ask first records its window on each failure group (AskedFrom := AskedTo, AskedTo := the last
///     key of Seen; Ask saves the marks in one transaction and only then sends), and FixExecutor's dry run reads that window only (FailureGroup.AskedKeys), so a
///     failure is in one request only. A fresh failure that joins a group that has an AskedTo, while the incident is not open-and-noticed, is a later failure:
///     Record sets LaterSince to the earliest of them. When LaterSince goes from empty to set on a noticed incident, Batch starts a later waiter (StartLater: a
///     Settle to this item in the incident's trace session); on an unnoticed one (the first ask is on its way) the raise route starts it after the notice and
///     the no-fix route clears LaterSince. An open, noticed incident only counts. The later waiter (Begin with NoticeCount set, then Later on each alarm,
///     LATERALARMKEY) ends for an incident that is gone, closed or without LaterSince, clears LaterSince of an open one, waits while Settle.Wait says so, re-checks
///     every quiet seconds while an ask is on its way (AskingSince set), and otherwise asks (AskLater): the kind and the parameters are those of the incident's
///     first request, AskingSince takes the round's time from LaterSince and one dry run goes out with LATERDRYRUNKEY. Its answer (Proposed with later 1) acts
///     only on an incident that exists, is not closed and has AskingSince set, and clears AskingSince on every path. A dry run with a Reason, with no Targets, a
///     table that refuses raised (an open incident), a dry run or slots that cannot be used, a Raise that fails and an error answer raise nothing and send
///     nothing (one Type 3 warning with LOGLATER for each error, none for an open incident or an empty Targets). An error (the ask not sent, an error answer, a
///     dry run or slots that cannot be used, a failed Raise, a request cancelled after a failed save) also puts the groups' marks back (AskedTo := AskedFrom), so
///     the round's failures join the next round's window, and a round that gathers meanwhile takes their earlier time; a refused dry run, an empty Targets and an
///     open incident keep the marks, because those failures were judged. Otherwise one request of the incident is raised
///     as for the first (the same kind, its own targets and dry run), appended to RequestRefs, and Move saves the row and sends each recipient one Notification of
///     kind approval with the key incident.laterRequest, the request's Ref as ApprovalRef and the slots of the round (Notice.WithFixSlots with the number of keys
///     of the windows and the round's time), then publishes the incident event. A save that fails cancels the request. Execute goes out for one approved request
///     at a time (the table's rows, Apply).
///   - Purge deletes the incidents closed before a cutoff, with their groups and their fix runs (AD-27).
///   - Any other request class is an error that names the class.
Class OcuTalon.Watch.IncidentManager Extends Ens.BusinessProcess
{

/// The states and stages that this class writes, from Msg.Enum.
Parameter OPEN = "open";

Parameter CLOSED = "closed";

/// An incident has to be quiet for more than this many seconds (since LastAt) before closeQuiet closes it (15 minutes).
Parameter QUIETSECONDS = 900;

/// The configuration item that carries out a fix (AD-16).
Parameter FIXEXECUTOR = "FixExecutor";

/// The approval request states that the facts read (Msg.Enum APPROVALSTATE).
Parameter PENDING = "pending";

Parameter APPROVED = "approved";

/// The answers to an incident command, in plain English (the words that users see are written by the stories that ask).
Parameter MESSAGECLOSED = "The incident was closed.";

Parameter MESSAGENOTFOUND = "There is no such incident, so nothing was changed.";

Parameter MESSAGENOTALLOWED = "The incident cannot be closed in its state, so nothing was changed.";

Parameter MESSAGENOTQUIET = "A failure arrived within the last 15 minutes, so the incident was not closed.";

Parameter MESSAGEUNKNOWN = "That is not an incident command, so nothing was done.";

Parameter MESSAGEFAILED = "The incident could not be changed just now, so nothing was done.";

/// The completion key of the waiter's alarm.
Parameter ALARMKEY = "settle";

/// The completion key of the diagnose request.
Parameter DIAGNOSEKEY = "diagnose";

/// The completion key of the dry run that FixExecutor answers (AD-16).
Parameter DRYRUNKEY = "dryrun";

/// The completion keys of the later waiter's alarm and of the dry run that it asks for (Story 7.6).
Parameter LATERALARMKEY = "laterSettle";

Parameter LATERDRYRUNKEY = "laterDryRun";

/// The item that receives the outcome of an approval request that this class raises (AD-11).
Parameter RESULTTARGET = "IncidentManager";

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

/// The kind of the notification that carries a later request (Msg.Enum NOTIFICATIONKIND; Story 7.6).
Parameter APPROVALKIND = "approval";

/// The kind of the notification that answers a request, and the catalog keys of an approved, a rejected and an expired one (Msg.Enum NOTIFICATIONKIND; Msg.Catalog.Core).
Parameter ANSWEREDKIND = "answered";

Parameter KEYAPPROVED = "answered.approved";

Parameter KEYREJECTED = "answered.rejected";

Parameter KEYEXPIRED = "answered.expired";

/// The kind of the notification that carries the result of a fix run (Msg.Enum NOTIFICATIONKIND; Story 7.3).
Parameter RESULTKIND = "result";

/// The live event type of an incident's public view.
Parameter INCIDENTEVENT = "incident";

Parameter LOGDIAGNOSE = "IncidentManager could not diagnose incident ";

Parameter LOGNOTICE = "IncidentManager could not notice incident ";

Parameter LOGPROPOSE = "IncidentManager could not propose the fix of incident ";

Parameter LOGLATER = "IncidentManager could not raise the later request of incident ";

Parameter LOGSEND = "IncidentManager could not send the notice of incident ";

Parameter LOGRESULT = "IncidentManager could not build the result notice of incident ";

Parameter LOGTELL = "IncidentManager could not tell the sessions of incident ";

Parameter LOGPUBLISH = "IncidentManager could not publish to the sessions of incident ";

Parameter LOGREFUSED = "IncidentManager refused an event of incident ";

Parameter LOGEXECUTE = "IncidentManager could not send the execute order of incident ";

Parameter LOGMOVE = "IncidentManager could not move incident ";

Parameter LOGDISMISS = "IncidentManager could not read the recipients to dismiss incident ";

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set response = ""
	If $IsObject(request) {
		If request.%IsA("OcuTalon.Watch.Msg.FailureBatch") Quit ..Batch(request)
		If request.%IsA("OcuTalon.Watch.Msg.Settle") Quit ..Begin(request)
		If request.%IsA("OcuTalon.Msg.IncidentCommand") Quit ..Command(request, .response)
		If request.%IsA("OcuTalon.Bridge.Msg.ApprovalOutcome") Quit ..Outcome(request)
		If request.%IsA("OcuTalon.Fix.Msg.FixResult") Quit ..Result(request)
	}
	Quit $SYSTEM.Status.Error(5001, "IncidentManager does not handle a request of the class '"_$Select($IsObject(request): $ClassName(request), 1: "none")_"'")
}

/// An answer by the key of the call: the alarm of the waiter has gone off (look at the rows again and end the settle rule or wait on), Decide has
/// answered the diagnose request (store the diagnosis or its fallback), or FixExecutor has answered the dry run (Proposed). The alarm of a later waiter
/// (LATERALARMKEY) goes to Later and the answer to its dry run (LATERDRYRUNKEY) to Proposed with later 1. An error status of Decide or of FixExecutor was
/// handled by OnError, so no answer comes with it.
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, pCompletionKey As %String) As %Status
{
	If '$IsObject(request) || 'request.%IsA("OcuTalon.Watch.Msg.Settle") Quit $$$OK
	If pCompletionKey = ..#DIAGNOSEKEY {
		If $IsObject($Get(callresponse)) && callresponse.%IsA("OcuTalon.Bridge.Msg.DecisionResponse") Quit ..Answered(request.IncidentRef, callresponse)
		Quit $$$OK
	}
	If pCompletionKey = ..#DRYRUNKEY {
		If $IsObject($Get(callresponse)) && callresponse.%IsA("OcuTalon.Fix.Msg.DryRunResult") Quit ..Proposed(request.IncidentRef, $Get(callrequest), callresponse)
		Quit $$$OK
	}
	If pCompletionKey = ..#LATERDRYRUNKEY {
		If $IsObject($Get(callresponse)) && callresponse.%IsA("OcuTalon.Fix.Msg.DryRunResult") Quit ..Proposed(request.IncidentRef, $Get(callrequest), callresponse, 1)
		Quit $$$OK
	}
	If pCompletionKey = ..#LATERALARMKEY Quit ..Later(request.IncidentRef)
	Quit ..Check(request.IncidentRef)
}

/// An error answer to the diagnose request: Decide refused it, so the incident is stored with the fallback error (Refused). An error answer to the dry run
/// takes the no-fix route with one Type 3 warning (Unproposed); an error answer to a later round's dry run raises nothing, with one Type 3 warning
/// (Unproposed with later 1). An error with any other key stays an error, so that the framework logs it.
Method OnError(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, pErrorStatus As %Status, pCompletionKey As %String) As %Status
{
	If '$IsObject(request) || 'request.%IsA("OcuTalon.Watch.Msg.Settle") Quit pErrorStatus
	If pCompletionKey = ..#DRYRUNKEY {
		Do ..Unproposed(request.IncidentRef, $SYSTEM.Status.GetErrorText(pErrorStatus))
		Quit $$$OK
	}
	If pCompletionKey = ..#LATERDRYRUNKEY {
		Do ..Unproposed(request.IncidentRef, $SYSTEM.Status.GetErrorText(pErrorStatus), 1)
		Quit $$$OK
	}
	If pCompletionKey '= ..#DIAGNOSEKEY Quit pErrorStatus
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
		If added(i) = "later" Do ..StartLater(rows(i))
	}
	For i = 1:1:count {
		If (added(i) '= "new") && (rows(i).NoticedAt '= "") Do ..Tell(rows(i), "incident", ##class(OcuTalon.Live.Payload.Incident).FromRow(rows(i)))
	}
	Quit sc
}

/// The failures of the batch, grouped by cause, saved as incident and group rows in one transaction. count is the number of causes that gained
/// failures and rows(i) their saved incidents; added(i) is "new" for an incident that this batch made, "later" for a noticed one whose LaterSince went from
/// empty to set (its later waiter starts), "more" for any other that gained failures. A fresh failure that joins a group that has an AskedTo, while the
/// incident is not open and noticed, is a later failure: LaterSince is the earliest FailedAt of them.
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
			Set later = 0
			If new {
				Set incident = ##class(OcuTalon.Data.Incident).%New()
				Set incident.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
				Set incident.OwnerRef = batch.OwnerRef
				Set incident.Namespace = batch.Namespace
				Set incident.Production = batch.Production
				Do ##class(OcuTalon.Watch.Transitions).Next("", 0, "first", "", .first)
				Set incident.State = first
				Set group = ##class(OcuTalon.Data.FailureGroup).%New()
				Set group.IncidentRef = incident.Ref
				Set group.ItemName = itemOf(cause)
				Set group.ErrorPattern = patternOf(cause)
				Set group.Seq = 1
				Set group.ErrorSummary = ##class(OcuTalon.Watch.ErrorText).Summary(textOf(cause))
			}
			Set group.Seen = ##class(OcuTalon.Watch.Settle).Hold(group.Seen, keysOf(cause), .fresh)
			If fresh = "" Continue
			Set laterWas = incident.LaterSince
			If 'new Set later = (group.AskedTo '= "") && '((incident.State = ..#OPEN) && (incident.NoticedAt '= ""))
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
				If later && ((incident.LaterSince = "") || (incident.LaterSince ] at)) Set incident.LaterSince = at
			}
			Set group.Count = group.Count + $Length(fresh, ",")
			Set incident.Count = incident.Count + $Length(fresh, ",")
			$$$ThrowOnError(group.%Save())
			$$$ThrowOnError(incident.%Save())
			Set count = count + 1
			Set rows(count) = incident
			Set added(count) = $Select(new: "new", (laterWas = "") && (incident.LaterSince '= "") && (incident.NoticedAt '= ""): "later", 1: "more")
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

/// Sends a waiter of the incident: a Settle request to this item, started with the session given (none by default: the waiter has a trace session of its
/// own), and with the batch's SuperSession kept. The batch's session is put back afterwards.
Method Start(ref As %String, session As %String = "") As %Status [ Private ]
{
	Set request = ##class(OcuTalon.Watch.Msg.Settle).%New()
	Set request.IncidentRef = ref
	Set saved = ..%SessionId
	Set ..%SessionId = session
	Set sc = ..SendRequestAsync(..%ConfigName, request, 0)
	Set ..%SessionId = saved
	Quit sc
}

/// Starts the later waiter of the noticed incident, in the incident's trace session (AD-26). A send that fails logs one Type 3 warning and clears LaterSince,
/// so that the failures of the round join the next one.
Method StartLater(incident As OcuTalon.Data.Incident) [ Private ]
{
	Set sc = ..Start(incident.Ref, incident.TraceHeaderId)
	If $$$ISOK(sc) Quit
	$$$LOGWARNING(..#LOGLATER_incident.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	Do ..Unlater(incident)
}

/// The waiter's start: records its own session as the incident's trace session, tells the sessions that the incident is settling and waits. The waiter of
/// an incident whose settle rule has ended (NoticeCount set) is a later waiter (Later).
Method Begin(request As OcuTalon.Watch.Msg.Settle) As %Status [ Private ]
{
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(request.IncidentRef)
	If $IsObject(incident) && (incident.NoticeCount '= "") Quit ..Later(request.IncidentRef)
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

/// The later waiter at this moment, from the rows (the counterpart of Check, ending in a dry run instead of a diagnosis). It ends for an incident that is
/// gone, closed or without LaterSince, and clears LaterSince of an open incident. While Settle.Wait for LaterSince says so it sets an alarm for the seconds that
/// are left; while an ask is on its way (AskingSince set) it re-checks after the quiet time; else it asks (AskLater).
Method Later(ref As %String) As %Status [ Private ]
{
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	If '$IsObject(incident) || (incident.State = ..#CLOSED) || (incident.LaterSince = "") Quit $$$OK
	If incident.State = ..#OPEN {
		Do ..Unlater(incident)
		Quit $$$OK
	}
	Do ##class(OcuTalon.Watch.Settle).Values(.quiet, .max)
	Set seconds = ##class(OcuTalon.Watch.Settle).Wait(incident.LaterSince, incident.LastAt, ##class(OcuTalon.Data.Time).NowUtc(), quiet, max)
	If seconds > 0 Quit ..LaterAlarm(seconds)
	If incident.AskingSince '= "" Quit ..LaterAlarm(quiet)
	Quit ..AskLater(incident)
}

/// Sets the later waiter's alarm (a seam for the tests): Settle.Alarm of the seconds, with the completion key LATERALARMKEY.
Method LaterAlarm(seconds As %Integer) As %Status [ Private ]
{
	Quit ..SetTimer(##class(OcuTalon.Watch.Settle).Alarm(seconds), ..#LATERALARMKEY)
}

/// The ask of a later round: the kind and the parameters are those of the incident's first request. A first request that is missing, is not the incident's or
/// has no fix kind logs one Type 3 warning and clears LaterSince. A round in which no group holds a key after its AskedTo clears LaterSince. Otherwise
/// AskingSince takes the round's time from LaterSince, and Ask moves the marks and sends the dry run with the key LATERDRYRUNKEY; an ask that cannot be made
/// logs one Type 3 warning and clears AskingSince, putting the marks back when they were saved (Unask with unmark 1).
Method AskLater(incident As OcuTalon.Data.Incident) As %Status [ Private ]
{
	Set first = $Piece(incident.RequestRefs, ",", 1)
	Set request = $Select(first = "": "", 1: ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(first))
	If '$IsObject(request) || (request.IncidentRef '= incident.Ref) || (request.FixKind = "") {
		$$$LOGWARNING(..#LOGLATER_incident.Ref_": the first request of the incident has no fix kind")
		Do ..Unlater(incident)
		Quit $$$OK
	}
	If '..Newer(incident) {
		Do ..Unlater(incident)
		Quit $$$OK
	}
	Set incident.AskingSince = incident.LaterSince
	Set incident.LaterSince = ""
	Set sc = ..Ask(incident, request.FixKind, request.FixParameters, ..#LATERDRYRUNKEY)
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGLATER_incident.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Do ..Unask(incident, 1)
		If incident.LaterSince '= "" Do ..Unlater(incident)
	}
	Quit $$$OK
}

/// 1 when a group of the incident holds a key after its AskedTo (a failure that no ask covers yet).
Method Newer(incident As OcuTalon.Data.Incident) As %Boolean [ Private ]
{
	Set found = 0
	Set groups = ..Groups(incident.Ref)
	For i = 1:1:groups.Count() {
		Set group = groups.GetAt(i)
		If ##class(OcuTalon.Watch.Settle).Window(group.Seen, group.AskedTo, $Piece(group.Seen, ",", $Length(group.Seen, ","))) '= "" Set found = 1
	}
	Quit found
}

/// The number of failures that the newest ask of the incident covers: the keys of its groups' windows (FailureGroup.AskedKeys).
Method Windowed(incident As OcuTalon.Data.Incident) As %Integer [ Private ]
{
	Set total = 0
	Set groups = ..Groups(incident.Ref)
	For i = 1:1:groups.Count() {
		Set keys = groups.GetAt(i).AskedKeys()
		If keys '= "" Set total = total + $Length(keys, ",")
	}
	Quit total
}

/// Clears LaterSince of the incident and saves it; a save that fails logs one Type 3 warning.
Method Unlater(incident As OcuTalon.Data.Incident) [ Private ]
{
	Set incident.LaterSince = ""
	Set sc = incident.%Save()
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGLATER_incident.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
}

/// Clears AskingSince of the incident, as the row stands (the incident is read again, so that a change the caller made and did not save is not saved with it).
/// With unmark 1 (a later round that failed: no request holds its window) it also puts each failure group's marks back (AskedTo := AskedFrom), so that the
/// round's failures are newer than every mark again and the next round's window holds them, and a round that gathers meanwhile takes the earlier time
/// (LaterSince := AskingSince when that is earlier); all of it in one transaction. Only a stored AskingSince is undone: the ask's marks were saved with it, and
/// no other ask moves them while it is set. A read or a save that fails logs one Type 3 warning.
Method Unask(incident As OcuTalon.Data.Incident, unmark As %Boolean = 0) [ Private ]
{
	Set level = $TLevel
	Try {
		Set sc = incident.%Reload()
		If $$$ISOK(sc) && (incident.AskingSince '= "") {
			TSTART
			If unmark {
				Set groups = ..Groups(incident.Ref)
				For i = 1:1:groups.Count() {
					Set group = groups.GetAt(i)
					Set group.AskedTo = group.AskedFrom
					$$$ThrowOnError(group.%Save())
				}
				If (incident.LaterSince '= "") && (incident.LaterSince ] incident.AskingSince) Set incident.LaterSince = incident.AskingSince
			}
			Set incident.AskingSince = ""
			$$$ThrowOnError(incident.%Save())
			TCOMMIT
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $TLevel > level TROLLBACK 1
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGLATER_incident.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
}

/// 1 when the incident exists, is not closed and has AskingSince set: a later round's answer may be acted on.
ClassMethod Asking(incident As OcuTalon.Data.Incident) As %Boolean [ Private ]
{
	Quit $IsObject(incident) && (incident.State '= ..#CLOSED) && (incident.AskingSince '= "")
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
	Set fix = ""
	If 'answer.Fallback {
		Set sc = $$$OK
		Try {
			Set diagnosis = ##class(%DynamicObject).%FromJSON(answer.Payload)
			Set incident.Cause = diagnosis.cause
			Set incident.CauseCategory = diagnosis.causeCategory
			Set incident.Element = diagnosis.elementAtFault
			Set incident.FixSummary = diagnosis.fixSummary
			Set fix = {"fixKind": (diagnosis.fixKind), "fixParameters": (diagnosis.fixParameters)}
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
	If $$$ISOK(sc) Do ..Notice(ref, fix)
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
/// variant and the slots come from OcuTalon.Watch.Notice. A usable diagnosis with a fix (Notice.Key is empty) is proposed (Propose) with fix, the
/// {fixKind, fixParameters} of the checked payload: the row stays open and unnoticed until the dry run answers. Slots that cannot be built, or an error
/// thrown in the step, log one Type 3 warning (the row stays as it was saved: a thrown error after the notice's save leaves it noticed).
Method Notice(ref As %String, fix As %DynamicObject = "") [ Private ]
{
	Try {
		Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
		If '..Open(incident) Quit
		Set key = ##class(OcuTalon.Watch.Notice).Key(incident)
		If key = "" {
			Do ..Propose(incident, fix)
			Quit
		}
		Set slots = ##class(OcuTalon.Watch.Notice).Slots(incident, , .sc)
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGNOTICE_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
			Quit
		}
		If '##class(OcuTalon.Watch.Transitions).Next(incident.State, incident.NoticedAt '= "", "notice", {"variant": (##class(OcuTalon.Watch.Notice).Variant(incident))}, .to, .variant) Quit
		Do ..Deliver(incident, to, variant, key, slots)
	} Catch exception {
		$$$LOGWARNING(..#LOGNOTICE_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(exception.AsStatus())))
	}
}

/// Asks FixExecutor for the dry run of the incident's fix: one OcuTalon.Fix.Msg.DryRun with the incident, the fix kind and the parameters as one JSON object,
/// sent asynchronously with a response required and the completion key DRYRUNKEY (Ask records the window first). No fix kind, parameters that are not an
/// object, or an ask that cannot be made takes the no-fix route (NoFix) with one Type 3 warning.
Method Propose(incident As OcuTalon.Data.Incident, fix As %DynamicObject = "") [ Private ]
{
	Set kind = $Select($IsObject(fix): fix.fixKind, 1: "")
	Set parameters = $Select($IsObject(fix): fix.fixParameters, 1: "")
	If (kind = "") || '$IsObject(parameters) || 'parameters.%IsA("%Library.DynamicObject") {
		$$$LOGWARNING(..#LOGPROPOSE_incident.Ref_": the diagnosis has no usable fix kind or parameters")
		Do ..NoFix(incident)
		Quit
	}
	Set sc = ..Ask(incident, kind, parameters.%ToJSON(), ..#DRYRUNKEY)
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGPROPOSE_incident.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Do ..NoFix(incident)
	}
}

/// Asks FixExecutor for the dry run of the fix of the kind and the parameters (JSON text) for the incident, as the first request and each later round do. Every ask
/// first moves each failure group's marks (AskedFrom := AskedTo, AskedTo := the last key of Seen) and saves them with the incident, which carries the changes that
/// the caller made, in one transaction; only then is the ask sent (SendDryRun) with the completion key given. The window of the ask is therefore fixed before
/// FixExecutor reads it, and a failure that joins meanwhile is in the next one. An error is the status of the save or of the send.
Method Ask(incident As OcuTalon.Data.Incident, kind As %String, parameters As %String, key As %String) As %Status [ Private ]
{
	Set ask = ##class(OcuTalon.Fix.Msg.DryRun).%New()
	Set ask.IncidentRef = incident.Ref
	Set ask.FixKind = kind
	Set ask.Parameters = parameters
	Set sc = $$$OK
	Set level = $TLevel
	TSTART
	Try {
		Set groups = ..Groups(incident.Ref)
		For i = 1:1:groups.Count() {
			Set group = groups.GetAt(i)
			Set group.AskedFrom = group.AskedTo
			Set group.AskedTo = $Piece(group.Seen, ",", $Length(group.Seen, ","))
			$$$ThrowOnError(group.%Save())
		}
		$$$ThrowOnError(incident.%Save())
		TCOMMIT
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $TLevel > level TROLLBACK 1
	If $$$ISERR(sc) Quit sc
	Quit ..SendDryRun(ask, key)
}

/// Sends the dry run to the FixExecutor item, asynchronously, with a response required and the completion key given (DRYRUNKEY for the first request; a seam
/// for the tests).
Method SendDryRun(ask As OcuTalon.Fix.Msg.DryRun, key As %String = {..#DRYRUNKEY}) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#FIXEXECUTOR, ask, 1, key)
}

/// An error answer to the dry run of the incident: one Type 3 warning with the error (through the redactor), then the no-fix route for an incident that is
/// still open and unnoticed. The error answer to a later round's dry run (later 1) logs LOGLATER instead, and clears AskingSince of an incident that exists, is
/// not closed and has it set, putting the marks back (Unask with unmark 1); nothing is raised or sent.
Method Unproposed(ref As %String, error As %String, later As %Boolean = 0) [ Private ]
{
	$$$LOGWARNING($Select(later: ..#LOGLATER, 1: ..#LOGPROPOSE)_ref_": "_##class(OcuTalon.Bridge.Redact).Text(error))
	Try {
		Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
		If later {
			If ..Asking(incident) Do ..Unask(incident, 1)
		} ElseIf ..Open(incident) {
			Do ..NoFix(incident)
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGNOTICE_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(exception.AsStatus())))
	}
}

/// The answer of FixExecutor to the dry run (ask is the DryRun that was sent, read back for the fix kind and the parameters): acts only on an incident that
/// is open and unnoticed, else drops it without an error. In this order:
///   1. a Reason takes the no-fix route with one Type 3 warning, and an empty Targets takes it with no warning (NoFix);
///   2. the table must accept raised, else nothing is raised;
///   3. the with-fix slots are built from the dry run (Notice.WithFixSlots), else one Type 3 warning and nothing more;
///   4. the fix request is built and raised once (RaiseRequest) in the incident's trace session; an error is one Type 3 warning and the no-fix route;
///   5. the Ref is appended to RequestRefs and Deliver saves it with NoticedAt and the state, then sends the notice (ApprovalRef = the Ref) and publishes;
///      the later waiter then starts when failures joined after the ask (LaterSince is set);
///   6. a save that fails cancels the request (CancelRequest), so that nothing stays approvable that no incident lists (Deliver logged the warning).
/// With later 1 (the answer to a later round's dry run) it acts only on an incident that exists, is not closed and has AskingSince set, and the same steps
/// run with these differences: a refused answer, a table that refuses raised (the incident is open), unusable slots and a failed Raise raise nothing and
/// clear AskingSince (the no-fix route does not exist for a noticed incident), with one Type 3 warning with LOGLATER for each error and none for an open
/// incident or an empty Targets; the slots are those of the round (Notice.WithFixSlots with the number of keys in the windows and AskingSince as the time);
/// the request is appended and Move saves the row, with AskingSince cleared, and sends each recipient one Notification of kind approval with the key
/// incident.laterRequest and the request's Ref, then publishes the incident event; NoticedAt does not change. A save that fails cancels the request, with one
/// warning, and clears AskingSince. An error (a dry run or slots that cannot be used, a failed Raise, a request cancelled after a failed save, a thrown error
/// before any raise) also puts the marks back (Unask with unmark 1), so the round's failures join the next round; a refused dry run, an empty Targets and an
/// open incident keep them, and so does a request that was raised and could not be cancelled, which still holds the window.
Method Proposed(ref As %String, ask As OcuTalon.Fix.Msg.DryRun, result As OcuTalon.Fix.Msg.DryRunResult, later As %Boolean = 0) As %Status [ Private ]
{
	Set incident = ""
	Set log = $Select(later: ..#LOGLATER, 1: ..#LOGPROPOSE)
	Try {
		Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
		If $Select(later: '..Asking(incident), 1: '..Open(incident)) Quit
		If result.Reason '= "" {
			$$$LOGWARNING(log_ref_": "_##class(OcuTalon.Bridge.Redact).Text(result.Reason))
			Do ..Decline(incident, later)
			Quit
		}
		If result.Targets = "" {
			Do ..Decline(incident, later)
			Quit
		}
		If '##class(OcuTalon.Watch.Transitions).Next(incident.State, later, "raised", , .to, .variant) {
			If later Do ..Unask(incident)
			Quit
		}
		Set dryRun = ""
		Try {
			Set dryRun = {}.%FromJSON(result.DryRun)
		} Catch {
			Set dryRun = ""
		}
		If '$IsObject(dryRun) || 'dryRun.%IsA("%Library.DynamicObject") {
			$$$LOGWARNING($Select(later: ..#LOGLATER, 1: ..#LOGNOTICE)_ref_": the dry run is not one JSON object")
			If later Do ..Unask(incident, 1)
			Quit
		}
		If later {
			Set slots = ##class(OcuTalon.Watch.Notice).WithFixSlots(incident, .sc, dryRun, ..Windowed(incident), incident.AskingSince)
		} Else {
			Set slots = ##class(OcuTalon.Watch.Notice).WithFixSlots(incident, .sc, dryRun)
		}
		If $$$ISERR(sc) {
			$$$LOGWARNING($Select(later: ..#LOGLATER, 1: ..#LOGNOTICE)_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
			If later Do ..Unask(incident, 1)
			Quit
		}
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).%New()
		Set row.Kind = "fix"
		Set row.IncidentRef = incident.Ref
		Set row.OwnerRef = incident.OwnerRef
		Set row.ResultTarget = ..#RESULTTARGET
		Set row.TraceRef = $Select(##class(OcuTalon.Bridge.Approval).IsRef(..%SuperSession): ..%SuperSession, 1: "")
		Set row.DryRun = result.DryRun
		Set row.FixKind = ask.FixKind
		Set row.FixParameters = ask.Parameters
		Set row.FixTargets = result.Targets
		Set sc = ..RaiseRequest(row, .request, incident.TraceHeaderId, ..%SuperSession)
		If $$$ISERR(sc) {
			$$$LOGWARNING(log_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
			Do ..Decline(incident, later, 1)
			Quit
		}
		Set incident.RequestRefs = $Select(incident.RequestRefs = "": request, 1: incident.RequestRefs_","_request)
		If later {
			Set incident.AskingSince = ""
			Set sc = ..Move(incident, to, variant, ..Notification(incident, ..#APPROVALKIND, ##class(OcuTalon.Watch.Notice).#KEYLATER, slots, request))
			If $$$ISERR(sc) {
				$$$LOGWARNING(..#LOGLATER_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
			}
		} Else {
			Set sc = ..Deliver(incident, to, variant, ##class(OcuTalon.Watch.Notice).#KEYWITHFIX, slots, request)
		}
		If $$$ISERR(sc) {
			Set cancelled = ..CancelRequest(request)
			If $$$ISERR(cancelled) {
				$$$LOGWARNING(log_ref_": the request "_request_" could not be cancelled: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(cancelled)))
			}
			If later Do ..Unask(incident, $$$ISOK(cancelled))
		} ElseIf 'later && (incident.LaterSince '= "") {
			Do ..StartLater(incident)
		}
	} Catch exception {
		$$$LOGWARNING(log_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(exception.AsStatus())))
		If later && $IsObject(incident) Do ..Unask(incident, $Get(request) = "")
	}
	Quit $$$OK
}

/// A dry run that raises nothing: the no-fix route for the first request (NoFix), and, for a later round, AskingSince cleared (Unask), with the marks put back when
/// unmark is 1 (an error, not a judged dry run).
Method Decline(incident As OcuTalon.Data.Incident, later As %Boolean, unmark As %Boolean = 0) [ Private ]
{
	If later {
		Do ..Unask(incident, unmark)
	} Else {
		Do ..NoFix(incident)
	}
}

/// Raises the approval request of the row in the incident's trace session (a seam for the tests): OcuTalon.Bridge.Approval.Raise with the session and the
/// SuperSession given. It runs outside any transaction. ref is the new request's Ref.
Method RaiseRequest(row As OcuTalon.Bridge.Data.ApprovalRequest, Output ref As %String, sessionId As %String, superSession As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Approval).Raise(row, .ref, , sessionId, superSession)
}

/// Cancels the request so that nothing stays approvable that no incident lists (a seam for the tests): channel system.
Method CancelRequest(ref As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Approval).Cancel(ref, , "system")
}

/// The no-fix notice of a data-format incident whose fix cannot be proposed: incident.noFix with its slots, the open variant no_fix, from the table. Slots that
/// cannot be built log one Type 3 warning and leave the row unnoticed. The notice clears LaterSince: an open, noticed incident only counts later failures.
Method NoFix(incident As OcuTalon.Data.Incident) [ Private ]
{
	Set key = ##class(OcuTalon.Watch.Notice).#KEYNOFIX
	Set slots = ##class(OcuTalon.Watch.Notice).Slots(incident, , .sc, key)
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGNOTICE_incident.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Quit
	}
	If '##class(OcuTalon.Watch.Transitions).Next(incident.State, 0, "notice", {"variant": (##class(OcuTalon.Watch.Notice).#VARIANTNOFIX)}, .to, .variant) Quit
	Set incident.LaterSince = ""
	Do ..Deliver(incident, to, variant, key, slots)
}

/// Notices the incident: sets NoticedAt (UTC now) and, with Move, the state and the open variant in one save and, after the commit, sends one Notification of
/// kind incident with the catalog key, the slots, the row's DecisionRef and the approval request's Ref (empty for a notice without one) to each recipient
/// session, then publishes the incident event on that session's stream (Tell). The row stays noticed whatever happens to the sends. A save that fails logs one
/// Type 3 warning and sends nothing; the result is Move's status.
Method Deliver(incident As OcuTalon.Data.Incident, state As %String, variant As %String, key As %String, slots As %DynamicObject, approvalRef As %String = "") As %Status [ Private ]
{
	Set incident.NoticedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = ..Move(incident, state, variant, ..Notification(incident, ..#NOTICEKIND, key, slots, approvalRef))
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGNOTICE_incident.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
	Quit sc
}

/// The Notification of the kind with the catalog key, the slots (as JSON), the incident's Ref and DecisionRef and the approval request's Ref (empty for a notice
/// without one). SessionRef is set per recipient by Tell.
Method Notification(incident As OcuTalon.Data.Incident, kind As %String, key As %String, slots As %DynamicObject, approvalRef As %String = "") As OcuTalon.Msg.Notification [ Private ]
{
	Set notice = ##class(OcuTalon.Msg.Notification).%New()
	Set notice.Kind = kind
	Set notice.CatalogKey = key
	Set notice.Slots = slots.%ToJSON()
	Set notice.IncidentRef = incident.Ref
	Set notice.DecisionRef = incident.DecisionRef
	Set notice.ApprovalRef = approvalRef
	Quit notice
}

/// Moves the incident to the state with the open variant: saves the row when the state, the variant or ClosedAt changes (or the caller has changed it; a
/// close sets ClosedAt to UTC now, once) and, after the commit, for a noticed incident, publishes the incident event (Tell) with the notification when one is
/// given, even when the state stays the same, because the payload's requests are read live. The error of a failed save is the result, and nothing is published.
Method Move(incident As OcuTalon.Data.Incident, to As %String, variant As %String, notification As OcuTalon.Msg.Notification = "") As %Status [ Private ]
{
	Set changed = incident.%IsModified() || (incident.State '= to) || (incident.OpenVariant '= variant)
	Set incident.State = to
	Set incident.OpenVariant = variant
	If (to = ..#CLOSED) && (incident.ClosedAt = "") {
		Set incident.ClosedAt = ##class(OcuTalon.Data.Time).NowUtc()
		Set changed = 1
	}
	If changed {
		Set sc = incident.%Save()
		If $$$ISERR(sc) Quit sc
	}
	If incident.NoticedAt '= "" Do ..Tell(incident, ..#INCIDENTEVENT, ##class(OcuTalon.Live.Payload.Incident).FromRow(incident), notification)
	Quit $$$OK
}

/// The event on the incident: the table (OcuTalon.Watch.Transitions) with the facts of the rows (Facts) decides; an accepted move is made (Move) and, when the
/// table says so, the fix of the request goes out (Execute). own is the event's own request (its Ref), "" for an event without one. accepted is 1 for a move
/// that was made, 0 for a refused one (the status is then OK) and for a move that could not be saved (the status is then the error). A notification given
/// goes out with the incident event of an accepted move (Move) and is dropped with a refused one.
Method Apply(incident As OcuTalon.Data.Incident, event As %String, own As %String = "", Output accepted As %Boolean, notification As OcuTalon.Msg.Notification = "") As %Status [ Private ]
{
	Set accepted = 0
	Set facts = ..Facts(incident, event, own, .earliest)
	If '##class(OcuTalon.Watch.Transitions).Next(incident.State, incident.NoticedAt '= "", event, facts, .to, .variant, .execute) Quit $$$OK
	Set sc = ..Move(incident, to, variant, notification)
	If $$$ISERR(sc) Quit sc
	Set accepted = 1
	If execute '= "" Do ..Execute(incident, $Select(execute = ##class(OcuTalon.Watch.Transitions).#OWN: own, 1: earliest))
	Quit $$$OK
}

/// The facts that the table needs, read from the incident's rows (AD-11) as {pending, waiting, demoMode}. The incident's requests are the entries of RequestRefs
/// whose ApprovalRequest row exists and names the incident; the event's own request (own) is not counted. pending: another request is pending, or is approved
/// while the incident is awaiting_approval (its outcome is still on its way). waiting: while the incident is fixing, another request is approved; earliest is
/// the first of them in RequestRefs order. demoMode is read only for a closeQuiet.
Method Facts(incident As OcuTalon.Data.Incident, event As %String, own As %String, Output earliest As %String) As %DynamicObject [ Private ]
{
	Set earliest = ""
	Set pending = 0
	Set waiting = 0
	Set position = 0
	Set refs = $ListFromString(incident.RequestRefs)
	While $ListNext(refs, position, ref) {
		If (ref = "") || (ref = own) Continue
		Set request = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
		If '$IsObject(request) || (request.IncidentRef '= incident.Ref) Continue
		If (request.State = ..#PENDING) || ((request.State = ..#APPROVED) && (incident.State = ##class(OcuTalon.Watch.Transitions).#AWAITING)) Set pending = 1
		If (request.State = ..#APPROVED) && (incident.State = ##class(OcuTalon.Watch.Transitions).#FIXING) {
			Set waiting = 1
			If earliest = "" Set earliest = ref
		}
	}
	Quit {"pending": (pending), "waiting": (waiting), "demoMode": ($Select(event = ##class(OcuTalon.Watch.Transitions).#CLOSEQUIET: ..DemoMode(), 1: 0))}
}

/// 1 when the request is one of the incident's: its Ref is an entry of the incident's RequestRefs and its row exists and names the incident. row is the row.
Method Owns(incident As OcuTalon.Data.Incident, ref As %String, Output row As OcuTalon.Bridge.Data.ApprovalRequest) As %Boolean [ Private ]
{
	Set row = ""
	If (ref = "") || '$ListFind($ListFromString(incident.RequestRefs), ref) Quit 0
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Quit $IsObject(row) && (row.IncidentRef = incident.Ref)
}

/// 1 when demo mode is on (the setting of Install.Step.Demo MODEKEY is "1"): closeQuiet then leaves a noticed open incident alone.
Method DemoMode() As %Boolean [ Private ]
{
	Quit (##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Install.Step.Demo).#MODEKEY) = "1")
}

/// Sends FixExecutor the order to carry out the request's fix (an Execute with only the Ref), asynchronously, with no answer wanted, in the incident's trace
/// session with the SuperSession kept (AD-26). A failed send logs one Type 3 warning and the row stays as saved.
Method Execute(incident As OcuTalon.Data.Incident, approvalRef As %String) [ Private ]
{
	Set order = ##class(OcuTalon.Fix.Msg.Execute).%New()
	Set order.ApprovalRef = approvalRef
	Set session = ..%SessionId
	Set ..%SessionId = incident.TraceHeaderId
	Set sc = ..SendExecute(order)
	Set ..%SessionId = session
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGEXECUTE_incident.Ref_" (request "_approvalRef_"): "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
}

/// Sends the order to the FixExecutor item, asynchronously, with no answer wanted (a seam for the tests).
Method SendExecute(order As OcuTalon.Fix.Msg.Execute) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#FIXEXECUTOR, order, 0)
}

/// The time that closeQuiet's quiet check reads, as a UTC stamp: the clock's now (a seam for the tests).
Method QuietNow() As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Time).NowUtc()
}

/// An incident command (see the class description): the checks in order, then the table. The answer is the CommandResult in response.
Method Command(command As OcuTalon.Msg.IncidentCommand, Output response As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set response = ""
	Set verb = command.Verb
	If '$ListFind($ListFromString(##class(OcuTalon.Msg.IncidentCommand).#VERBS), verb) Quit ..Verdict(.response, 0, "unknown_command", ..#MESSAGEUNKNOWN)
	Set incident = $Select(command.IncidentRef = "": "", 1: ##class(OcuTalon.Data.Incident).RefIndexOpen(command.IncidentRef))
	If '$IsObject(incident) Quit ..Verdict(.response, 0, "not_found", ..#MESSAGENOTFOUND)
	If verb = ##class(OcuTalon.Watch.Transitions).#DISMISS {
		Set recipients = ##class(OcuTalon.Data.Session).Recipients(incident.OwnerRef, incident.Ref, .sc)
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGDISMISS_incident.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
			Quit ..Verdict(.response, 0, "failed", ..#MESSAGEFAILED)
		}
		If (command.SessionRef = "") || '$ListFind(recipients, command.SessionRef) Quit ..Verdict(.response, 0, "not_found", ..#MESSAGENOTFOUND)
	}
	If (verb = ##class(OcuTalon.Watch.Transitions).#CLOSEQUIET) && '##class(OcuTalon.Watch.Settle).Quiet(incident.LastAt, ..QuietNow(), ..#QUIETSECONDS) {
		Quit ..Verdict(.response, 0, "not_quiet", ..#MESSAGENOTQUIET, "", incident)
	}
	Set sc = ..Apply(incident, verb, "", .accepted)
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGMOVE_incident.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Quit ..Verdict(.response, 0, "failed", ..#MESSAGEFAILED, "", $Select($$$ISOK(incident.%Reload()): incident, 1: ""))
	}
	If 'accepted Quit ..Verdict(.response, 0, "not_allowed", ..#MESSAGENOTALLOWED, "", incident)
	Quit ..Verdict(.response, 1, ..#CLOSED, ..#MESSAGECLOSED, incident.Ref, incident)
}

/// Builds the CommandResult; an incident given puts its state and open variant in Data. Always status OK.
Method Verdict(ByRef response As OcuTalon.Msg.CommandResult, ok As %Boolean, outcome As %String, message As %String, ref As %String = "", incident As OcuTalon.Data.Incident = "") As %Status [ Private ]
{
	Set response = ##class(OcuTalon.Msg.CommandResult).%New()
	Set response.Ok = ok
	Set response.Outcome = outcome
	Set response.Message = message
	Set response.Ref = ref
	If $IsObject(incident) Set response.Data = {"state": (incident.State), "openVariant": (incident.OpenVariant)}.%ToJSON()
	Quit $$$OK
}

/// An ApprovalOutcome from ApprovalHold: approved, rejected or expired of one of the incident's requests, as the request's row shows it. Anything else is
/// refused (Drop): another outcome (cancelled included), an unknown incident, a request that is not the incident's, or an outcome that the row does not show
/// (a repeat or a stale one).
Method Outcome(outcome As OcuTalon.Bridge.Msg.ApprovalOutcome) As %Status [ Private ]
{
	Set event = outcome.Outcome
	Set incident = $Select(outcome.IncidentRef = "": "", 1: ##class(OcuTalon.Data.Incident).RefIndexOpen(outcome.IncidentRef))
	If '$IsObject(incident) || '$ListFind($ListBuild("approved", "rejected", "expired"), event) || '..Owns(incident, outcome.ApprovalRef, .row) || (row.State '= event) {
		Do ..Drop(outcome.IncidentRef, event, $Select($IsObject(incident): incident.State, 1: "none"))
		Quit $$$OK
	}
	Quit ..Event(incident, event, outcome.ApprovalRef, ..AnswerNotice(incident, event, row))
}

/// The notification that answers an approved, a rejected or an expired request (kind answered): answered.approved and answered.rejected with the channel and time of
/// the answer, or answered.expired with the request's ExpiresAt, the request's Ref and the incident's, no DecisionRef; "" for any other event. SessionRef is set
/// per recipient by Tell.
Method AnswerNotice(incident As OcuTalon.Data.Incident, event As %String, row As OcuTalon.Bridge.Data.ApprovalRequest) As OcuTalon.Msg.Notification [ Private ]
{
	If (event = "approved") || (event = "rejected") {
		Set key = $Select(event = "approved": ..#KEYAPPROVED, 1: ..#KEYREJECTED)
		Set slots = {"channel": (row.AnsweredChannel), "time": (row.AnsweredAt)}
	} ElseIf event = "expired" {
		Set key = ..#KEYEXPIRED
		Set slots = {"time": (row.ExpiresAt)}
	} Else {
		Quit ""
	}
	Quit ..Compose(incident, ..#ANSWEREDKIND, key, slots, row.Ref)
}

/// The Notification of the kind with the catalog key and the slots (as JSON) for the approval request's Ref and the incident's Ref, with no DecisionRef: the shape
/// of the answered and the result notices. SessionRef is set per recipient by Tell.
Method Compose(incident As OcuTalon.Data.Incident, kind As %String, key As %String, slots As %DynamicObject, approvalRef As %String) As OcuTalon.Msg.Notification [ Private ]
{
	Set notice = ##class(OcuTalon.Msg.Notification).%New()
	Set notice.Kind = kind
	Set notice.CatalogKey = key
	Set notice.Slots = slots.%ToJSON()
	Set notice.IncidentRef = incident.Ref
	Set notice.ApprovalRef = approvalRef
	Quit notice
}

/// A FixResult from FixExecutor: finished when the run ended or was interrupted, progress otherwise, of one of the incident's requests. A finished one carries the
/// result notice (ResultNotice), which goes out with the accepted move.
Method Result(result As OcuTalon.Fix.Msg.FixResult) As %Status [ Private ]
{
	Set final = result.Final || result.Interrupted
	Set event = $Select(final: ##class(OcuTalon.Watch.Transitions).#FINISHED, 1: ##class(OcuTalon.Watch.Transitions).#PROGRESS)
	Set incident = $Select(result.IncidentRef = "": "", 1: ##class(OcuTalon.Data.Incident).RefIndexOpen(result.IncidentRef))
	If '$IsObject(incident) || '..Owns(incident, result.ApprovalRef, .row) {
		Do ..Drop(result.IncidentRef, event, $Select($IsObject(incident): incident.State, 1: "none"))
		Quit $$$OK
	}
	Quit ..Event(incident, event, result.ApprovalRef, $Select(final: ..ResultNotice(incident, row, result), 1: ""))
}

/// The notification of kind result for a final or interrupted FixResult of the request (row): the key from Notice.ResultKey, the slots from Notice.ResultSlots with
/// the item noun of the request's dry run, else the incident's, else the code noun, the request's Ref and the incident's, no DecisionRef. "" with one Type 3
/// warning (LOGRESULT) when the slots cannot be built.
Method ResultNotice(incident As OcuTalon.Data.Incident, row As OcuTalon.Bridge.Data.ApprovalRequest, result As OcuTalon.Fix.Msg.FixResult) As OcuTalon.Msg.Notification [ Private ]
{
	Set key = ##class(OcuTalon.Watch.Notice).ResultKey(row.State, result)
	Set slots = ##class(OcuTalon.Watch.Notice).ResultSlots(key, result, ..Noun(incident, row), .sc)
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGRESULT_incident.Ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Quit ""
	}
	Quit ..Compose(incident, ..#RESULTKIND, key, slots, row.Ref)
}

/// The item noun {"one", "other"} of a request's result: the itemNoun of the request's stored dry run, else the incident's ItemNoun, else the code noun of an
/// empty body class (the first that is an object with both forms).
Method Noun(incident As OcuTalon.Data.Incident, row As OcuTalon.Bridge.Data.ApprovalRequest) As %DynamicObject [ Private ]
{
	For source = 1, 2 {
		Set noun = ""
		Try {
			If source = 1 {
				If row.DryRun '= "" Set noun = {}.%FromJSON(row.DryRun).itemNoun
			} ElseIf incident.ItemNoun '= "" {
				Set noun = {}.%FromJSON(incident.ItemNoun)
			}
		} Catch {
			Set noun = ""
		}
		If $IsObject(noun) && noun.%IsA("%Library.DynamicObject") && (noun.one '= "") && (noun.other '= "") Quit
		Set noun = ""
	}
	If '$IsObject(noun) Set noun = {}.%FromJSON(##class(OcuTalon.Watch.ItemNoun).For(""))
	Quit noun
}

/// An event of a request of the incident: made when the table accepts it, else refused (Drop). A move that cannot be saved is the error status. The
/// notification given goes out with the accepted move only.
Method Event(incident As OcuTalon.Data.Incident, event As %String, own As %String, notification As OcuTalon.Msg.Notification = "") As %Status [ Private ]
{
	Set state = incident.State
	Set sc = ..Apply(incident, event, own, .accepted, notification)
	If $$$ISERR(sc) Quit sc
	If 'accepted Do ..Drop(incident.Ref, event, state)
	Quit $$$OK
}

/// Logs one Type 4 line for an event that was refused: the incident, the event and the state.
Method Drop(ref As %String, event As %String, state As %String) [ Private ]
{
	$$$LOGINFO(..#LOGREFUSED_ref_": "_event_" in the state "_state)
}

/// Deletes the incidents that were closed before the cutoff, with their groups and their fix runs (AD-27), one incident per transaction. The cutoff is now (UTC) moved back
/// daysToKeep whole days; an incident closed at the cutoff stays, and so does every incident that is not closed, a closed one with no ClosedAt included.
/// daysToKeep must be a whole number of at least 1; anything else is an error status and nothing is deleted. The result is OK, or the errors of the
/// incidents that could not be deleted (the others are deleted).
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Set bad = $SYSTEM.Status.Error(5001, "OcuTalon.Watch.IncidentManager.Purge needs a whole number of days, at least 1, not '"_$Extract(daysToKeep, 1, 40)_"'")
	If daysToKeep '? 1.N Quit bad
	If +daysToKeep < 1 Quit bad
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set day = $ZDateH($Piece(now, "T", 1), 3) - daysToKeep
	If day < 0 Quit $$$OK
	Set cutoff = $ZDate(day, 3)_"T"_$Piece(now, "T", 2)
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Incident WHERE State = 'closed' AND ClosedAt < ?", cutoff)
	If rs.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "Reading the closed incidents failed: "_rs.%Message)
	While rs.%Next() {
		Set ids(rs.%GetData(1)) = ""
	}
	Set sc = $$$OK
	Set id = ""
	For {
		Set id = $Order(ids(id))
		Quit:id=""
		Set sc = $SYSTEM.Status.AppendStatus(sc, ..PurgeOne(id, cutoff))
	}
	Quit sc
}

/// Deletes the incident of the ID, its groups and its fix runs (its FixRun rows) in one transaction, when it is still closed with a ClosedAt before the cutoff.
ClassMethod PurgeOne(id As %String, cutoff As %String) As %Status [ Private ]
{
	Set sc = $$$OK
	Set level = $TLevel
	TSTART
	Try {
		Set incident = ##class(OcuTalon.Data.Incident).%OpenId(id)
		If $IsObject(incident) && (incident.State = ..#CLOSED) && (incident.ClosedAt '= "") && (cutoff ] incident.ClosedAt) {
			Set groups = ..Groups(incident.Ref)
			For i = 1:1:groups.Count() {
				$$$ThrowOnError(##class(OcuTalon.Data.FailureGroup).%DeleteId(groups.GetAt(i).%Id()))
			}
			Set runs = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.FixRun WHERE IncidentRef = ?", incident.Ref)
			If runs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The fix runs of the incident "_incident.Ref_" could not be deleted: "_runs.%Message))
			$$$ThrowOnError(##class(OcuTalon.Data.Incident).%DeleteId(id))
		}
		TCOMMIT
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $TLevel > level TROLLBACK 1
	Quit sc
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
