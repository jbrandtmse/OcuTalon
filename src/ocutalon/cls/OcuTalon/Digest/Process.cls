Include Ensemble

/// The Digest item (AD-1, AD-3, AD-5, AD-18, AD-28, AD-30, AD-32; Lane A): the daily digest of what OcuTalon watched. A business process that handles one
/// message and ends (AD-5) and keeps no private text in its properties (AD-3). It takes four requests:
///   - OcuTalon.Msg.Tick, forwarded by Checks after each tick's checks. The tick's time, tickAt, decides which sessions are due, by AD-18's rule:
///     due is the latest instant at or before tickAt whose clock in the instance zone reads digest.time (Data.Setting, "08:00" when the value cannot be
///     read), computed only through OcuTalon.Data.Time. On the online demo no session is due (AD-18, amended 2026-11-07: a visitor gets a digest only by asking); on a local install a session (every
///     Session row) is due when due is later than its CreatedAt, it has no Sent row of Kind scheduled whose DueAt is at least due, and no Compose body of Kind
///     scheduled whose DueAt is at least due (a digest already queued). The check is made again under Lock +^OcuTalon.Digest.Due(sessionRef), and the
///     Compose is queued inside that lock, so a digest missed while IRIS was down goes once and never twice. After the sessions, the tick sends the
///     digests that missed a channel to that channel again (see the routing below). The tick answers nothing;
///   - OcuTalon.Msg.Command.SendDigest, from CommandsIn (origins tool and web_admin). It has no recipient: the destinations come only from the session's
///     own channels and the digest.channels setting (see the routing below), and nothing here reads a destination from the command, the model or an item.
///     Under the same lock, a command whose
///     IdempotencyKey is not empty and is already held by a Sent row or a Compose body of the session queues nothing; any other queues one Compose
///     (Kind requested, DueAt empty). The answer, at once, is a CommandResult Ok 1, Outcome sending and Message MESSAGESENDING, for a new request and for a
///     repeat. The digest is composed asynchronously, because the command may come from a tool inside a ChatAgent turn, and a digest that asked Decide
///     in that call would wait on ChatAgent itself (a deadlock);
///   - OcuTalon.Digest.Msg.Compose, which Digest sends to itself with no answer wanted. It builds the digest of one session and sends it;
///   - OcuTalon.Eval.Msg.DigestCase, from EvalIn (Story 17.7). The recorded rows of the case, with the owner eval and no session, give the same verdict (see
///     below) as a session's rows. Digest asks for no Rows, Cost or Channels, sends no Notification and writes no Sent row. With saved summaries it makes the
///     one summary request, with OwnerRef eval, and finishes in OnResponse as for a Compose. It sends EvalSink one OcuTalon.Eval.Msg.DigestResult (CatalogKey,
///     AllClear, the named and the checked entries, the Decision and the fallback). Nothing in the message names a session, channel or destination.
/// A Compose is the digest's pending marker, because the lock cannot span the answer of Decide. Its window is fixed when it is queued: WindowStart is the
/// session's newest Sent.SentAt of either kind, or 24 hours before WindowEnd for its first digest; WindowEnd is the time it is queued.
/// The verdict (Verdict) is made from the output rows of Checks.Render, never from the raw results: the named entries (failed, then not checked), the quiet
/// sentence, the failed rows for what needs the user, the healthy sentence (every vital row passed by Render's rule) and AllClear.
/// The composition: one OcuTalon.Msg.Notification of Kind digest for the session, with CatalogKey the key of Checks.Render over the non-vital rows
/// that Checks.Coverage.Build gives (AD-28), DecisionRef the Decision of the model request, and Slots {"parts", "lines", "rows"} (AD-32). parts holds
/// {key, slots} in this order:
///   1. the greeting of the compose hour in the instance zone;
///   2. digest.healthy when the five vital signs passed by Render's rule, else digest.vitalsNotAll;
///   3. digest.checkedQuiet when no entry is named, else digest.checked (each checked entry with "the " before it, except the name of a source row, which stands
///      as the admin typed it, and the connected mailbox, which reads MAILBOXINSENTENCE), then the key of Render (with whatFailed, the entries that did not pass, failed
///      first, for the two keys that name them, the connected mailbox again reading MAILBOXINSENTENCE: Story 22.13), except that when no row failed, at least one is not checked and at least one passed (Render RestKey) the key of Render
///      is replaced by the coverage line of each not-checked row, in row order, then checks.everythingElsePassed (Lead; Story 22.5); with nothing watched
///      (the Mailbox row alone counts as nothing watched), digest.nothingWatched alone. The coverage lines and the lead name the mailbox as the label "Mailbox"
///      (Checks.Coverage ENTRYMAILBOX); only the two sentences, "I checked ..." and "Not everything: ...", say "the mailbox";
///   4. what needs the user (OcuTalon.Digest.NeedsYou): digest.needsYouOne or digest.needsYou, then digest.needsYouMore on overflow; no part for none (a tell-now or act Decision counts only when it was recorded at or after the Compose's WindowStart);
///   5. what was saved for later: digest.savedNone, digest.saved with the summary, or digest.savedNoSummary with the fallback reason;
///   6. digest.cost, the cost of yesterday (OcuTalon.Digest.Cost).
/// The summary is the one model request of the digest, made only when OcuTalon.Digest.Data.Item holds an item of the window: an OcuTalon.Bridge.Msg.Request
/// of Kind turn, provenance untrusted and SessionMode fresh, with no SeedText, sent to Decide asynchronously with an answer wanted and finished in
/// OnResponse (the process never blocks on another item). The reply text, already filtered by the guard, is cut to SUMMARYMAX characters. A fallback,
/// an error, an empty text or no answer gives digest.savedNoSummary, and the fallback is logged as one information line.
/// The routing: Digest hands every composed digest to Notify, once, whatever digest.channels names, and Notify alone routes kind digest, to the channels
/// that digest.channels names and that are available to the session (web, phone when demo mode is on, telegram when the session is paired, and email
/// when its rule says so). Digest knows no channel by name: Channels asks Functions.DigestChannels for the channels Notify's rule will use, only to
/// record them on the Sent row and to find that none is available. When none is, nothing is sent, the Compose ends with an error status carrying
/// MESSAGENOCHANNEL, and the failure shows as that of any other failed Compose.
/// Last, Digest writes one OcuTalon.Digest.Data.Sent row once the digest was handed to Notify (the only writer; handed over means queued, the delivery
/// of each channel is recorded by its item), with Channels the channels Notify routes it to and Failed empty, AllClear 1 only when the CatalogKey is
/// checks.allPassed, the five vital signs passed and nothing needs the user. When Notify did not take it, the handling of the Compose returns an error
/// status, so that Ensemble records it on the header of the Compose and in its trace session; no Sent row follows a digest that Notify did not take.
/// The private seams Rows, Saved, SendSummary, Cost, NeedsYou, Reachable, SendNotice, SendCompose and SendResult are the calls that a test overrides.
Class OcuTalon.Digest.Process Extends Ens.BusinessProcess
{

/// The Message of the CommandResult of an accepted SendDigest (model-facing: the tool result reads it), also for a repeat of the key. It never says that
/// the digest was sent.
Parameter MESSAGESENDING = "The digest is on its way to the user's digest channels. Its delivery is not confirmed yet: tell the user it is on its way, not that it has arrived.";

/// The Outcome of the CommandResult of an accepted SendDigest.
Parameter OUTCOMESENDING = "sending";

/// The item that takes the Compose requests: this one.
Parameter SELF = "Digest";

/// The item that takes the summary request.
Parameter DECIDE = "Decide";

/// The item that routes the digest.
Parameter NOTIFY = "Notify";

/// The item that takes the DigestResult of a digest case.
Parameter EVALSINK = "EvalSink";

/// The seconds to wait for the lock of a session's digest.
Parameter LOCKSECONDS = 5;

/// How the connected mailbox reads inside the digest's two sentences, "I checked ..." and "Not everything: ..." (public text; Story 22.13). Everywhere else it is the label
/// Checks.Coverage ENTRYMAILBOX.
Parameter MAILBOXINSENTENCE = "the mailbox";

/// The setting of the time of day of the scheduled digest, and its value when the setting cannot be read.
Parameter TIMESETTING = "digest.time";

Parameter TIMEDEFAULT = "08:00";

/// The setting of the digest channels (SettingsOps writes it; Notify's rule and Functions.DigestChannels read it). It is not seeded.
Parameter CHANNELSSETTING = "digest.channels";

/// The operator diagnostic of a digest that no channel is reachable for: the Message of the error status of its Compose.
Parameter MESSAGENOCHANNEL = "No digest channel is reachable: none of the saved digest channels is one of this session's channels.";

/// The longest summary, in characters.
Parameter SUMMARYMAX = 240;

/// The window of a session's first digest, in seconds.
Parameter FIRSTWINDOW = 86400;

/// The subject of the item that carries the saved summaries to the model, and the code-written note that goes before it.
Parameter SUBJECT = "Saved for later";

Parameter SYSTEMNOTE = "Summarize the saved items in one or two plain sentences. Don't say whether things are fine.";

/// The channel of the summary request's item.
Parameter CHANNEL = "system";

/// The reason of a summary that came back empty, and of one that came back unusable.
Parameter REASONEMPTY = "empty";

Parameter REASONUNUSABLE = "unusable";

Parameter LOGSKIP = "Digest skipped a session's digest: ";

Parameter LOGNOLOCK = "Digest could not take the lock of a session's digest, so it tries again at the next tick.";

Parameter LOGFELLBACK = "The saved-for-later summary of a digest fell back: ";

/// The seed values of the digest's settings, as {"<setting key>": "<value>"}: the time of the scheduled digest. The digest channels are not seeded.
ClassMethod Seeds() As %DynamicObject
{
	Set seeds = {}
	Do seeds.%Set(..#TIMESETTING, ..#TIMEDEFAULT)
	Quit seeds
}

/// The four requests of the class description.
Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set response = ""
	If $IsObject($Get(request)) {
		If request.%IsA("OcuTalon.Msg.Tick") Quit ..Ticked(request)
		If request.%IsA("OcuTalon.Msg.Command.SendDigest") Quit ..Requested(request, .response)
		If request.%IsA("OcuTalon.Digest.Msg.Compose") Quit ..Composed(request)
		If request.%IsA("OcuTalon.Eval.Msg.DigestCase") Quit ..Evaluated(request)
	}
	Quit $SYSTEM.Status.Error(5001, "Digest does not handle a request of the class '"_$Select($IsObject($Get(request)): $ClassName(request), 1: "none")_"'")
}

/// The answer of the summary request, by its completion key. A failed request is kept by OnError for the call that follows.
Method OnError(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, pErrorStatus As %Status, pCompletionKey As %String) As %Status
{
	If pCompletionKey = "" Quit pErrorStatus
	Set ..CallError = pErrorStatus
	Quit $$$OK
}

/// The answer of the summary request: the digest is finished with the summary, or with the fallback.
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, pCompletionKey As %String) As %Status
{
	Set error = ..CallError
	Set ..CallError = $$$OK
	If '$IsObject($Get(request)) Quit $$$OK
	Set evaluated = request.%IsA("OcuTalon.Eval.Msg.DigestCase")
	If 'evaluated && 'request.%IsA("OcuTalon.Digest.Msg.Compose") Quit $$$OK
	Set sc = $$$OK
	Try {
		Set answer = $Get(callresponse)
		Set summary = "", reason = "", decisionRef = ""
		If $$$ISERR(error) || '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
			Set reason = ..#REASONUNUSABLE
		} Else {
			Set decisionRef = answer.DecisionRef
			If answer.Fallback {
				Set reason = ..Reason(answer.FallbackReason)
			} Else {
				Set summary = $Extract($ZStrip(answer.Text, "<>WC"), 1, ..#SUMMARYMAX)
				If summary = "" Set reason = ..#REASONEMPTY
			}
		}
		If reason '= "" $$$LOGINFO(..#LOGFELLBACK_reason)
		Set sc = $Select(evaluated: ..FinishCase(request, summary, reason, decisionRef), 1: ..Finish(request, summary, reason, decisionRef))
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// A Tick: on a local install the sessions that are due get one Compose each (see the class description); on the online demo (Data.Public.Settings
/// onlineDemo on) no session is due, so none gets a scheduled Compose (AD-18, amended 2026-11-07). A session that fails is one warning and the rest go on.
Method Ticked(tick As OcuTalon.Msg.Tick) As %Status [ Private ]
{
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set tickAt = $Select(tick.TickAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z": tick.TickAt, 1: now)
	Set due = ..DueFor(tickAt)
	If due = "" Quit $SYSTEM.Status.Error(5001, "Digest cannot work out the due time of the tick '"_$Extract(tick.TickAt, 1, 40)_"'")
	Set online = +##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	If online Quit $$$OK
	Set sessions = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, CreatedAt FROM OcuTalon_Data.Session")
	If sessions.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "Digest could not read the sessions: "_sessions.%Message)
	While sessions.%Next() {
		Set ref = sessions.%Get("Ref")
		If '(due ] sessions.%Get("CreatedAt")) Continue
		Try {
			Set sc = ..Schedule(ref, due, now)
		} Catch exception {
			Set sc = exception.AsStatus()
		}
		If $$$ISERR(sc) $$$LOGWARNING(..#LOGSKIP_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
	Quit $$$OK
}

/// The latest instant at or before tickAt whose clock in the instance zone reads digest.time, UTC; "" when tickAt cannot be read.
ClassMethod DueFor(tickAt As %String) As %String
{
	Set time = ..ClockTime()
	Set local = ##class(OcuTalon.Data.Time).ToLocal(tickAt)
	If local = "" Quit ""
	Set day = $ZDateH($Piece(local, "T", 1), 3)
	Set due = ##class(OcuTalon.Data.Time).FromLocal($ZDate(day, 3)_"T"_time_":00")
	If (due = "") || (due ] tickAt) Set due = ##class(OcuTalon.Data.Time).FromLocal($ZDate(day - 1, 3)_"T"_time_":00")
	Quit due
}

/// The time of day of the scheduled digest, hh:mm: the setting, or the default when the setting cannot be read or is not a time of day.
ClassMethod ClockTime() As %String
{
	Set value = ""
	Try {
		Set value = ##class(OcuTalon.Data.Setting).Get(..#TIMESETTING, ..#TIMEDEFAULT)
	} Catch {
		Set value = ""
	}
	Set value = $ZStrip(value, "<>W")
	If (value ? 2N1":"2N) && ($Piece(value, ":", 1) < 24) && ($Piece(value, ":", 2) < 60) Quit value
	Quit ..#TIMEDEFAULT
}

/// Queues the scheduled Compose of the session for the due time when none is due yet, under the session's lock.
Method Schedule(sessionRef As %String, due As %String, now As %String) As %Status [ Private ]
{
	If ..Covered(sessionRef, due) Quit $$$OK
	Lock +^OcuTalon.Digest.Due(sessionRef):..#LOCKSECONDS
	If '$Test {
		$$$LOGWARNING(..#LOGNOLOCK)
		Quit $$$OK
	}
	Set sc = $$$OK
	Try {
		If '..Covered(sessionRef, due) Set sc = ..Queue(sessionRef, "scheduled", due, "", now)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Lock -^OcuTalon.Digest.Due(sessionRef)
	Quit sc
}

/// 1 when a scheduled digest for due or a later time is already sent or queued for the session.
Method Covered(sessionRef As %String, due As %String) As %Boolean [ Private ]
{
	Quit ..Exists("OcuTalon_Digest_Data.Sent,OcuTalon_Digest_Msg.Compose", sessionRef, "Kind = 'scheduled' AND DueAt >= ?", due)
}

/// 1 when the session already has a Sent row or a Compose body that holds the IdempotencyKey.
Method KeyHeld(sessionRef As %String, key As %String) As %Boolean [ Private ]
{
	Quit ..Exists("OcuTalon_Digest_Data.Sent,OcuTalon_Digest_Msg.Compose", sessionRef, "IdempotencyKey = ?", key)
}

/// 1 when one of the tables (comma-separated SQL names) has a row of the session where the condition holds for the value. A read error throws.
Method Exists(tables As %String, sessionRef As %String, condition As %String, value As %String) As %Boolean [ Private ]
{
	For i = 1:1:$Length(tables, ",") {
		Set table = $Piece(tables, ",", i)
		Set found = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM "_table_" WHERE SessionRef = ? AND "_condition, sessionRef, value)
		If found.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "Digest could not read "_table_": "_found.%Message))
		If found.%Next() Return 1
	}
	Quit 0
}

/// Queues one Compose of the session, with its window fixed at now.
Method Queue(sessionRef As %String, kind As %String, dueAt As %String, key As %String, now As %String) As %Status [ Private ]
{
	Set compose = ##class(OcuTalon.Digest.Msg.Compose).%New()
	Set compose.SessionRef = sessionRef
	Set compose.Kind = kind
	Set compose.DueAt = dueAt
	Set compose.IdempotencyKey = key
	Set compose.WindowEnd = now
	Set compose.WindowStart = ..WindowStart(sessionRef, now)
	Quit ..SendCompose(compose)
}

/// The start of the window of a digest queued at now: the session's newest SentAt, or a day before now for its first digest.
Method WindowStart(sessionRef As %String, now As %String) As %String [ Private ]
{
	Set newest = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 SentAt FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ? ORDER BY SentAt DESC, ID DESC", sessionRef)
	If newest.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "Digest could not read the newest digest: "_newest.%Message))
	If newest.%Next() && (newest.%Get("SentAt") '= "") Quit newest.%Get("SentAt")
	Quit ##class(OcuTalon.Data.Time).AddSeconds(now, -..#FIRSTWINDOW)
}

/// A SendDigest: one Compose is queued unless the key was seen, and the answer is Ok at once (see the class description).
Method Requested(command As OcuTalon.Msg.Command.SendDigest, Output response As %Library.Persistent) As %Status [ Private ]
{
	Set response = ""
	Set sessionRef = command.SessionRef
	If '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef)) Quit $SYSTEM.Status.Error(5001, "Digest has no session for the command")
	Lock +^OcuTalon.Digest.Due(sessionRef):..#LOCKSECONDS
	If '$Test Quit $SYSTEM.Status.Error(5001, "Digest could not take the lock of the session's digest")
	Set sc = $$$OK
	Try {
		If (command.IdempotencyKey = "") || '..KeyHeld(sessionRef, command.IdempotencyKey) {
			Set sc = ..Queue(sessionRef, "requested", "", command.IdempotencyKey, ##class(OcuTalon.Data.Time).NowUtc())
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Lock -^OcuTalon.Digest.Due(sessionRef)
	If $$$ISERR(sc) Quit sc
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = 1
	Set result.Outcome = ..#OUTCOMESENDING
	Set result.Message = ..#MESSAGESENDING
	Set response = result
	Quit $$$OK
}

/// A Compose: the digest of one session. With items saved in the window it asks Decide for the summary and finishes in OnResponse; otherwise it finishes
/// at once. The status is the error of the handling, which Ensemble records.
Method Composed(compose As OcuTalon.Digest.Msg.Compose) As %Status [ Private ]
{
	Set ..ItemId = ""
	Set ..CallError = $$$OK
	Set sc = $$$OK
	Try {
		Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(compose.SessionRef)
		If '$IsObject(session) $$$ThrowStatus($SYSTEM.Status.Error(5001, "Digest has no session for the digest"))
		If ..%SuperSession = "" Set ..%SuperSession = session.TraceRef
		If ..Sent(compose) Quit
		Set sc = ..Channels(compose.SessionRef, .channels)
		If $$$ISERR(sc) Quit
		Set sc = ..Saved(compose.SessionRef, compose.WindowStart, compose.WindowEnd, .items)
		If $$$ISERR(sc) Quit
		If items.%Size() = 0 {
			Set sc = ..Finish(compose, "", "", "")
			Quit
		}
		Set request = ..SummaryRequest(items)
		Set ..ItemId = request.ItemId
		Set request.OwnerRef = compose.SessionRef
		Set sc = ..SendSummary(request)
		If $$$ISERR(sc) {
			Set ..ItemId = ""
			$$$LOGINFO(..#LOGFELLBACK_..#REASONUNUSABLE)
			Set sc = ..Finish(compose, "", ..#REASONUNUSABLE, "")
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// A DigestCase: the verdict of its recorded rows, as the owner eval (see the class description). It reads no session and no table of the product, asks for no
/// Rows, Cost or Channels, sends no Notification and writes no Sent row. With saved summaries it asks Decide for the summary and finishes in OnResponse;
/// otherwise it finishes at once.
Method Evaluated(case As OcuTalon.Eval.Msg.DigestCase) As %Status [ Private ]
{
	Set ..ItemId = ""
	Set ..CallError = $$$OK
	Set sc = $$$OK
	Try {
		Set items = ..CaseSaved(case)
		If items.%Size() = 0 {
			Set sc = ..FinishCase(case, "", "", "")
			Quit
		}
		Set request = ..SummaryRequest(items)
		Set ..ItemId = request.ItemId
		Set request.OwnerRef = ##class(OcuTalon.Data.Ownership).#EVAL
		Set sc = ..SendSummary(request)
		If $$$ISERR(sc) {
			Set ..ItemId = ""
			$$$LOGINFO(..#LOGFELLBACK_..#REASONUNUSABLE)
			Set sc = ..FinishCase(case, "", ..#REASONUNUSABLE, "")
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Sends EvalSink the DigestResult of the case: the verdict of its recorded rows, and the summary request's Decision and fallback.
Method FinishCase(case As OcuTalon.Eval.Msg.DigestCase, summary As %String, reason As %String, decisionRef As %String) As %Status [ Private ]
{
	Do ..CaseRows(case, .rows, .vitals)
	Set sc = ..Verdict(##class(OcuTalon.Data.Ownership).#EVAL, rows, vitals, .verdict)
	If $$$ISERR(sc) Quit sc
	Set result = ##class(OcuTalon.Eval.Msg.DigestResult).%New()
	Set result.ItemId = case.ItemId
	Set result.SourceItemId = case.SourceItemId
	Set result.CatalogKey = verdict.checkKey
	Set result.AllClear = verdict.allClear
	Set result.Named = verdict.named.%ToJSON()
	Set result.Checked = verdict.checked.%ToJSON()
	Set result.DecisionRef = decisionRef
	Set result.Fallback = (reason '= "")
	Set result.FallbackReason = $Select(reason '= "": ..Reason(reason), 1: "")
	Quit ..SendResult(result)
}

/// The rows of a digest case: the vital rows followed by the recorded checks, and the vital signs. A recorded value that cannot be read counts as [] or {}.
ClassMethod CaseRows(case As OcuTalon.Eval.Msg.DigestCase, Output rows As %DynamicArray, Output vitals As %DynamicObject) [ Private ]
{
	Set checks = ..CaseJSON(case.RecordedChecks, "%Library.DynamicArray")
	If '$IsObject(checks) Set checks = []
	Set vitals = ..CaseJSON(case.RecordedVitals, "%Library.DynamicObject")
	If '$IsObject(vitals) Set vitals = {}
	If '$IsObject(vitals.%Get("rows")) || 'vitals.%Get("rows").%IsA("%Library.DynamicArray") Do vitals.%Set("rows", [])
	If '$IsObject(vitals.%Get("figures")) || 'vitals.%Get("figures").%IsA("%Library.DynamicObject") Do vitals.%Set("figures", {})
	Set rows = []
	Set iterator = vitals.rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Do rows.%Push(row)
	}
	Set iterator = checks.%GetIterator()
	While iterator.%GetNext(, .row) {
		Do rows.%Push(row)
	}
}

/// The saved summaries of a digest case as an array of {summary}; only the strings of the recorded array that are not blank.
ClassMethod CaseSaved(case As OcuTalon.Eval.Msg.DigestCase) As %DynamicArray [ Private ]
{
	Set items = []
	Set saved = ..CaseJSON(case.RecordedSaved, "%Library.DynamicArray")
	If '$IsObject(saved) Quit items
	For i = 0:1:saved.%Size() - 1 {
		If (saved.%GetTypeOf(i) = "string") && ($ZStrip(saved.%Get(i), "<>WC") '= "") Do items.%Push({"summary": (saved.%Get(i))})
	}
	Quit items
}

/// The JSON text as a value of the class, or "" when the text is empty, is not JSON or is a value of another class.
ClassMethod CaseJSON(text As %String, class As %String) As %DynamicAbstractObject [ Private ]
{
	If text = "" Quit ""
	Set value = ""
	Try {
		Set value = ##class(%DynamicAbstractObject).%FromJSON(text)
	} Catch exception {
		Set value = ""
	}
	If '$IsObject(value) || 'value.%IsA(class) Quit ""
	Quit value
}

/// 1 when the digest of the Compose is already sent: a Sent row holds its key, or is its scheduled digest.
Method Sent(compose As OcuTalon.Digest.Msg.Compose) As %Boolean [ Private ]
{
	If compose.IdempotencyKey '= "" Quit ..Exists("OcuTalon_Digest_Data.Sent", compose.SessionRef, "IdempotencyKey = ?", compose.IdempotencyKey)
	If compose.Kind = "scheduled" Quit ..Exists("OcuTalon_Digest_Data.Sent", compose.SessionRef, "Kind = 'scheduled' AND DueAt >= ?", compose.DueAt)
	Quit 0
}

/// The summary request (AD-30): an untrusted, fresh turn with no seed, whose input is the saved summaries as quoted data. The owner is set by the caller.
Method SummaryRequest(items As %DynamicArray) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set text = ""
	Set iterator = items.%GetIterator()
	While iterator.%GetNext(, .item) {
		Set text = text_$Select(text = "": "", 1: $Char(10))_item.summary
	}
	Set carrier = ##class(OcuTalon.Msg.Item).%New()
	Set carrier.Channel = ..#CHANNEL
	Set carrier.Provenance = "untrusted"
	Set carrier.Subject = ..#SUBJECT
	Set carrier.Text = text
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "untrusted"
	Set request.SessionMode = "fresh"
	Set request.Input = ##class(OcuTalon.Agent.Input).Render(carrier)
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.Summary = ..#SUBJECT
	Set request.Channel = ..#CHANNEL
	Set request.TraceRef = ..%SuperSession
	Set request.ThreadSessionId = ..%SessionId
	Set request.SystemNote = ..#SYSTEMNOTE
	Quit request
}

/// The fallback reason for the raw one: the raw one when it is a value of Msg.Enum FALLBACKREASON, else unusable.
ClassMethod Reason(raw As %String) As %String
{
	Quit $Select($ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#FALLBACKREASON), $Get(raw)): raw, 1: ..#REASONUNUSABLE)
}

/// Builds the digest of the Compose, sends its Notification and writes its Sent row. summary is the model's summary ("" for none), reason the fallback
/// reason when there is none although items were saved, and decisionRef the Decision of the model request. The CatalogKey, the named entries, the
/// quiet sentence, what needs the user, the vital-signs part and AllClear all come from Verdict, as they do for a digest case.
Method Finish(compose As OcuTalon.Digest.Msg.Compose, summary As %String, reason As %String, decisionRef As %String) As %Status [ Private ]
{
	Set sessionRef = compose.SessionRef
	Set at = compose.WindowEnd
	Set sc = ..Channels(sessionRef, .channels)
	If $$$ISERR(sc) Quit sc
	Set sc = ..Rows(sessionRef, compose.WindowStart, at, .rows, .lines, .vitals)
	If $$$ISERR(sc) Quit sc
	Set sc = ..Saved(sessionRef, compose.WindowStart, at, .items)
	If $$$ISERR(sc) Quit sc
	Set sc = ..Verdict(sessionRef, rows, vitals, .verdict, compose.WindowStart)
	If $$$ISERR(sc) Quit sc
	Set needs = verdict.needs
	Set cost = ..Cost(sessionRef, at, .sc)
	If $$$ISERR(sc) Quit sc
	Set checkKey = verdict.checkKey
	Set lead = ..Lead(rows, lines, vitals)
	Set parts = []
	Do parts.%Push({"key": (..Greeting(at)), "slots": {}})
	Do parts.%Push(verdict.vitalsPart)
	If verdict.nothingWatched {
		Do parts.%Push({"key": "digest.nothingWatched", "slots": {}})
	} Else {
		Set named = []
		Set iterator = verdict.checked.%GetIterator()
		While iterator.%GetNext(.position, .entry) {
			Do named.%Push($Select(verdict.sources.%Get(position): entry, entry = ##class(OcuTalon.Checks.Coverage).#ENTRYMAILBOX: ..#MAILBOXINSENTENCE, 1: "the "_entry))
		}
		Do parts.%Push({"key": ($Select(verdict.named.%Size() = 0: "digest.checkedQuiet", 1: "digest.checked")), "slots": {"checked": (..Joined(named))}})
		If lead.%Size() > 0 {
			Set iterator = lead.%GetIterator()
			While iterator.%GetNext(, .line) {
				Do parts.%Push(line)
			}
			Do parts.%Push({"key": (##class(OcuTalon.Checks.Render).#KEYELSEPASSED), "slots": {}})
		} Else {
			Do parts.%Push({"key": (checkKey), "slots": ($Select(verdict.named.%Size() > 0: {"whatFailed": (..Joined(..InSentence(verdict.named)))}, 1: {}))})
		}
	}
	If needs.count > 0 {
		Set what = ""
		Set iterator = needs.names.%GetIterator()
		While iterator.%GetNext(, .name) {
			Set what = what_$Select(what = "": "", 1: "; ")_name
		}
		If needs.count = 1 {
			Do parts.%Push({"key": "digest.needsYouOne", "slots": {"what": (what)}})
		} Else {
			Do parts.%Push({"key": "digest.needsYou", "slots": ({"count": (needs.count), "what": (what)})})
		}
		If needs.more > 0 Do parts.%Push({"key": "digest.needsYouMore", "slots": {"n": (needs.more)}})
	}
	If items.%Size() = 0 {
		Do parts.%Push({"key": "digest.savedNone", "slots": {}})
	} ElseIf summary '= "" {
		Do parts.%Push({"key": "digest.saved", "slots": {"count": (items.%Size()), "summary": (summary)}})
	} Else {
		Do parts.%Push({"key": "digest.savedNoSummary", "slots": {"count": (items.%Size()), "fallbackReason": (..Reason(reason))}})
	}
	Set costSlots = {}
	Do costSlots.%Set("cost", cost, "number")
	Do parts.%Push({"key": "digest.cost", "slots": (costSlots)})
	Set slots = {"parts": (parts), "lines": (lines), "rows": (rows)}.%ToJSON()
	Set sc = ..Deliver(..DigestNotification(sessionRef, checkKey, decisionRef, slots), channels, .delivered, .failed)
	If $ListLength(delivered) = 0 Quit sc
	Set row = ##class(OcuTalon.Digest.Data.Sent).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = sessionRef
	Set row.ItemId = $Select(summary '= "" || (reason '= ""): ..ItemId, 1: "")
	Set row.DecisionRef = decisionRef
	Set row.Kind = compose.Kind
	Set row.DueAt = compose.DueAt
	Set row.WindowStart = compose.WindowStart
	Set row.SentAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.CatalogKey = checkKey
	Set row.Slots = slots
	Set row.AllClear = verdict.allClear
	Set row.IdempotencyKey = compose.IdempotencyKey
	Set row.Channels = $ListToString(delivered)
	Set row.Failed = $ListToString(failed)
	Set saved = row.%Save()
	Quit $Select($$$ISERR(saved): $SYSTEM.Status.AppendStatus(saved, sc), 1: sc)
}

/// The one verdict of a digest, for a session's rows and for a digest case's (the rows after rows' leading vital rows are the watched ones). The check
/// rows come only from Checks.Render, so that no verdict is made from the raw results. verdict is {checkKey, nothingWatched, named, failed, checked,
/// sources, needs, vitalsPart, allClear}:
///   - checkKey is Render's key over the watched rows; with no watched row, or none that Render takes as a result, or only the Mailbox row (Checks.Coverage
///     ENTRYMAILBOX: the connected mailbox is not a watch, AD-28), it is checks.nothingWatched and nothingWatched is 1;
///   - named holds the entries of Render's rows that did not pass, failed first and then not checked, and failed holds the failed rows;
///   - checked holds the entry of each watched row that is a result, in the order of the rows, and sources holds, in the same order, 1 for a row of kind source
///     (the digest.checked list gives its entry as the admin typed it, with no "the " before it) and 0 for any other;
///   - needs is what NeedsYou gives the owner for the failed rows, with the Decisions recorded at or after windowStart ("" for no bound; a digest case passes none);
///   - vitalsPart is digest.healthy only when Render gives checks.allPassed for every vital row, else digest.vitalsNotAll with the entries that did not pass;
///   - allClear is 1 only when checkKey is checks.allPassed, the vital signs passed and nothing needs the owner.
Method Verdict(owner As %String, rows As %DynamicArray, vitals As %DynamicObject, Output verdict As %DynamicObject, windowStart As %String = "") As %Status [ Private ]
{
	Set verdict = ""
	Set watched = []
	For i = vitals.rows.%Size():1:rows.%Size() - 1 {
		Do watched.%Push(rows.%Get(i))
	}
	Set checkKey = ##class(OcuTalon.Checks.Render).Render(watched, .ordered)
	Set named = [], failed = [], checked = [], sources = []
	Set iterator = ordered.%GetIterator()
	While iterator.%GetNext(, .row) {
		If row.result '= "passed" Do named.%Push(row.entry)
		If row.result = "failed" Do failed.%Push(row)
	}
	Set iterator = watched.%GetIterator()
	While iterator.%GetNext(, .row) {
		If ..Entry(row) {
			Do checked.%Push(row.entry)
			Do sources.%Push((row.%GetTypeOf("kind") = "string") && (row.kind = ##class(OcuTalon.Checks.Process).#SOURCEKIND))
		}
	}
	Set nothingWatched = (ordered.%Size() = 0) || ((ordered.%Size() = 1) && (ordered.%Get(0).entry = ##class(OcuTalon.Checks.Coverage).#ENTRYMAILBOX))
	If nothingWatched Set checkKey = "checks.nothingWatched"
	Set sc = $$$OK
	Set needs = ..NeedsYou(owner, failed, .sc, windowStart)
	If $$$ISERR(sc) Quit sc
	Set vitalsPart = ..Vitals(vitals)
	Set verdict = {"checkKey": (checkKey), "named": (named), "failed": (failed), "checked": (checked), "sources": (sources), "needs": (needs), "vitalsPart": (vitalsPart)}
	Do verdict.%Set("nothingWatched", nothingWatched, "boolean")
	Do verdict.%Set("allClear", (checkKey = ##class(OcuTalon.Checks.Render).#KEYALLPASSED) && (vitalsPart.key = "digest.healthy") && (needs.count = 0), "boolean")
	Quit $$$OK
}

/// The entries of names for a sentence: the connected mailbox (Checks.Coverage ENTRYMAILBOX; DW-1325 keeps a source from having that name) reads MAILBOXINSENTENCE, every
/// other entry is unchanged (Story 22.13).
ClassMethod InSentence(names As %DynamicArray) As %DynamicArray [ Private ]
{
	Set sentence = []
	Set iterator = names.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Do sentence.%Push($Select(entry = ##class(OcuTalon.Checks.Coverage).#ENTRYMAILBOX: ..#MAILBOXINSENTENCE, 1: entry))
	}
	Quit sentence
}

/// The lead of the digest's checks part (Story 22.5): when Render RestKey of Render's ordered watched rows (those after the vital rows) is not "", the coverage lines
/// (lines, which parallel rows) of the watched rows that Render classes not_checked, in row order; else []. It never throws, and an error gives [].
Method Lead(rows As %DynamicArray, lines As %DynamicArray, vitals As %DynamicObject) As %DynamicArray [ Private ]
{
	Set lead = []
	Try {
		Set first = vitals.rows.%Size()
		Set watched = []
		For i = first:1:rows.%Size() - 1 {
			Do watched.%Push(rows.%Get(i))
		}
		Do ##class(OcuTalon.Checks.Render).Render(watched, .ordered)
		If ##class(OcuTalon.Checks.Render).RestKey(ordered) = "" Quit
		For i = first:1:rows.%Size() - 1 {
			Set single = []
			Do single.%Push(rows.%Get(i))
			Do ##class(OcuTalon.Checks.Render).Render(single, .one)
			If (one.%Size() = 1) && (one.%Get(0).result = "not_checked") Do lead.%Push(lines.%Get(i))
		}
	} Catch {
		Set lead = []
	}
	Quit lead
}

/// 1 when the row is an object whose entry is a string that is not blank (Render's rule for an element that is a result).
ClassMethod Entry(row) As %Boolean [ Private ]
{
	If '$IsObject(row) || 'row.%IsA("%Library.DynamicObject") Quit 0
	If row.%GetTypeOf("entry") '= "string" Quit 0
	Quit $ZStrip($Translate(row.entry, $Char(160), " "), "<>WC") '= ""
}

/// The Notification of kind digest of the session, with its CatalogKey, DecisionRef and Slots.
ClassMethod DigestNotification(sessionRef As %String, checkKey As %String, decisionRef As %String, slots As %String) As OcuTalon.Msg.Notification [ Private ]
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = sessionRef
	Set notification.Kind = "digest"
	Set notification.CatalogKey = checkKey
	Set notification.DecisionRef = decisionRef
	Set notification.Slots = slots
	Quit notification
}

/// The channels a digest of the session goes to, as a list: the ones that Notify's rule for kind digest sends it to (Reachable). An error status with
/// MESSAGENOCHANNEL when there is none.
Method Channels(sessionRef As %String, Output channels As %List) As %Status [ Private ]
{
	Set channels = ..Reachable(sessionRef)
	If $ListLength(channels) = 0 Quit $SYSTEM.Status.Error(5001, ..#MESSAGENOCHANNEL)
	Quit $$$OK
}

/// Sends the Notification to Notify, once, whatever digest.channels names: Notify alone routes kind digest to the channels that digest.channels names and
/// that are available. delivered and failed are the channels that the send reached and missed (lists): all of them when the Notification went to Notify,
/// none when the send failed; the status is the send's.
Method Deliver(notification As OcuTalon.Msg.Notification, channels As %List, Output delivered As %List, Output failed As %List) As %Status [ Private ]
{
	Set sc = ..SendNotice(notification, ..#NOTIFY)
	Set delivered = $Select($$$ISERR(sc): "", 1: channels)
	Set failed = $Select($$$ISERR(sc): channels, 1: "")
	Quit sc
}

/// The greeting part's key for the compose hour in the instance zone.
ClassMethod Greeting(at As %String) As %String
{
	Set hour = +$Extract(##class(OcuTalon.Data.Time).ToLocal(at), 12, 13)
	Quit $Select(hour < 12: "digest.greetingMorning", hour < 18: "digest.greetingAfternoon", 1: "digest.greetingEvening")
}

/// The vital-signs part: digest.healthy only when Checks.Render gives checks.allPassed for the vital rows and keeps every one of them, else
/// digest.vitalsNotAll naming the entries that did not pass, in Render's order.
ClassMethod Vitals(vitals As %DynamicObject) As %DynamicObject
{
	Set key = ##class(OcuTalon.Checks.Render).Render(vitals.rows, .ordered)
	Set missing = []
	Set iterator = ordered.%GetIterator()
	While iterator.%GetNext(, .row) {
		If row.result '= "passed" Do missing.%Push(row.entry)
	}
	If (key '= ##class(OcuTalon.Checks.Render).#KEYALLPASSED) || (ordered.%Size() '= vitals.rows.%Size()) {
		Quit {"key": "digest.vitalsNotAll", "slots": {"whatFailed": (..Joined(missing))}}
	}
	Set figures = vitals.figures
	If '$IsObject(figures) Set figures = {}
	Quit {"key": "digest.healthy", "slots": {"count": (+figures.upDays), "itemNoun": {"one": "day", "other": "days"}, "databasesFull": (+figures.databasesFull), "licenseUse": (+figures.licenseUse)}}
}

/// The names as one phrase: "a", "a and b", "a, b and c".
ClassMethod Joined(names As %DynamicArray) As %String
{
	Set text = ""
	Set size = names.%Size()
	For i = 0:1:size - 1 {
		Set text = text_$Select(i = 0: "", i = (size - 1): " and ", 1: ", ")_names.%Get(i)
	}
	Quit text
}

/// Coverage.Build over the window (a seam for the tests).
Method Rows(sessionRef As %String, fromUtc As %String, toUtc As %String, Output rows As %DynamicArray, Output lines As %DynamicArray, Output vitals As %DynamicObject) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Checks.Coverage).Build(sessionRef, fromUtc, toUtc, .rows, .lines, .vitals)
}

/// The items saved for later in the window, newest first, as Item.Since gives them but only those recorded at or before until (a seam for the tests).
Method Saved(sessionRef As %String, since As %String, until As %String, Output items As %DynamicArray) As %Status [ Private ]
{
	Set sc = ##class(OcuTalon.Digest.Data.Item).Since(sessionRef, since, .all)
	Set items = []
	If $$$ISERR(sc) Quit sc
	Set iterator = all.%GetIterator()
	While iterator.%GetNext(, .item) {
		If '(item.recordedAt ] until) Do items.%Push(item)
	}
	Quit sc
}

/// The request for the summary: to Decide, asynchronously, with an answer wanted, completed by the key summary (a seam for the tests).
Method SendSummary(request As OcuTalon.Bridge.Msg.Request) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#DECIDE, request, 1, "summary")
}

/// Yesterday's cost for the session (a seam for the tests).
Method Cost(sessionRef As %String, at As %String, Output sc As %Status) As %Numeric [ Private ]
{
	Quit ##class(OcuTalon.Digest.Cost).Yesterday(sessionRef, at, .sc)
}

/// What needs the user (a seam for the tests).
Method NeedsYou(sessionRef As %String, failedRows As %DynamicArray, Output sc As %Status, windowStart As %String = "") As %DynamicObject [ Private ]
{
	Quit ##class(OcuTalon.Digest.NeedsYou).List(sessionRef, failedRows, .sc, windowStart)
}

/// The channels that Notify's rule sends a digest of the session to, in its order (Functions.DigestChannels): the channels that digest.channels names and
/// that are available to the session (a seam for the tests).
Method Reachable(sessionRef As %String) As %List [ Private ]
{
	Quit ##class(OcuTalon.Core.Rule.Functions).DigestChannels(sessionRef)
}

/// The digest's Notification to Notify, asynchronously, with no answer wanted (a seam for the tests).
Method SendNotice(notification As OcuTalon.Msg.Notification, item As %String) As %Status [ Private ]
{
	Quit ..SendRequestAsync(item, notification, 0)
}

/// A Compose to this item, asynchronously, with no answer wanted (a seam for the tests).
Method SendCompose(compose As OcuTalon.Digest.Msg.Compose) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#SELF, compose, 0)
}

/// The DigestResult to EvalSink, asynchronously, with no answer wanted (a seam for the tests).
Method SendResult(result As OcuTalon.Eval.Msg.DigestResult) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#EVALSINK, result, 0)
}

/// The Ref of the item of the summary request; empty before it is made.
Property ItemId As %String(MAXLEN = 22);

/// The error status of the summary request, kept by OnError for the OnResponse call that follows.
Property CallError As %Status [ InitialExpression = {$$$OK} ];

Storage Default
{
<Data name="ProcessDefaultData">
<Subscript>"Process"</Subscript>
<Value name="1">
<Value>ItemId</Value>
</Value>
<Value name="2">
<Value>CallError</Value>
</Value>
</Data>
<DefaultData>ProcessDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
