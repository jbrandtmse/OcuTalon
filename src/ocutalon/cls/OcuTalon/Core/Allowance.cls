Include Ensemble

/// The online demo's allowances (AD-20, FR-40). Story 16.9. With the online-demo flag set (Data.Setting onlineDemo = 1), and only
/// then:
///   - TryConsume counts each session's messages over a rolling WINDOW of 3600 seconds, whatever their channel (web chat, guide
///     prompts, Telegram), against Limit() (the public setting messageAllowance, 50). A channel service calls it synchronously
///     before it queues a message; Conversation never does. The times of the accepted messages are the Session row's
///     AllowanceTimes, oldest first, and every write to them takes the row's lock (Core.Trace's pattern: %LockId, %OpenId,
///     %Reload, %Save, %UnlockId), so a burst cannot pass the limit;
///   - a refused message is recorded by TryConsume itself as a Turn in the state refused: its channel and text, a new Ref and
///     ItemId, no ClientId and no decision. Nothing queues it, the chat never shows it and no recap includes it. The window of a
///     refusal runs from its first refusal until its retryAt (the Session row's AllowanceUntil); the first refusal of a window is
///     flagged, and the channel service sends the one allowance Notice then;
///   - MailAllowed holds the simulated mailbox to EMAILLIMIT incoming emails over the same window, samples included;
///   - Refund gives back the entry of a message whose send failed. Until says when a window ends. Notice and DailyCapNotice build the
///     two allowance notifications (kind allowance, which goes to the web chat and the paired chat only, AD-14).
/// With the flag off (a local or IPM install) nothing is counted, recorded or refused. None of these methods publishes an event.
Class OcuTalon.Core.Allowance
{

/// The rolling window, in seconds, of both limits.
Parameter WINDOW = 3600;

/// Seconds to wait for the Session row's lock.
Parameter LOCKWAIT = 5;

/// The incoming simulated emails a session may send in the window, samples included.
Parameter EMAILLIMIT = 20;

/// The messages a session may send in the window when messageAllowance is not a whole number of 1 or more.
Parameter DEFAULTLIMIT = 50;

/// The README section that both allowance messages point to (the install-it-yourself section).
Parameter INSTALLLINK = "https://github.com/jbrandtmse/OcuTalon#install-it-yourself";

/// The state of a Turn that an allowance refused.
Parameter REFUSED = "refused";

Parameter LOGREFUND = "Allowance could not give back a message's entry: ";

/// Asks to consume one message of the session's allowance. Returns 1 when the message may be queued; retryAt is then "" and
/// firstRefusal 0, and now is appended to the session's AllowanceTimes. Returns 0 when it may not:
///   - the session has Limit() entries in the past WINDOW seconds: retryAt is the UTC time when the oldest entry that blocks
///     leaves the window, firstRefusal is 1 when no window of the session was open (AllowanceUntil not later than now) and the
///     row's AllowanceUntil becomes retryAt, and a refused Turn is recorded, both saves in one transaction;
///   - the row's lock is not free within LOCKWAIT seconds, or anything throws: retryAt is "", nothing is recorded and the caller
///     answers an error.
/// With the flag off, and for a session that has no row (the channel services check the row first), it returns 1 and records
/// nothing. It never throws.
ClassMethod TryConsume(sessionRef As %String, channel As %String, text As %String, Output retryAt As %String, Output firstRefusal As %Boolean) As %Boolean
{
	Set retryAt = ""
	Set firstRefusal = 0
	If ..Off() Quit 1
	Set id = ""
	If ($Get(sessionRef) = "") || '##class(OcuTalon.Data.Session).RefIndexExists(sessionRef, .id) Quit 1
	If $SYSTEM.Status.IsError(##class(OcuTalon.Data.Session).%LockId(id, 0, ..#LOCKWAIT)) Quit 0
	Set allowed = 0
	Set level = $TLevel
	Set session = ""
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set session = ##class(OcuTalon.Data.Session).%OpenId(id, , .sc)
		If $SYSTEM.Status.IsOK(sc) && $IsObject(session) Set sc = session.%Reload()
		If $SYSTEM.Status.IsError(sc) || '$IsObject(session) Quit
		Set now = ##class(OcuTalon.Data.Time).NowUtc()
		Set limit = ..Limit()
		Set times = ..Kept(session.AllowanceTimes, now, limit)
		If $ListLength(times) < limit {
			Set session.AllowanceTimes = times_$ListBuild(now)
			Set sc = session.%Save()
			If $SYSTEM.Status.IsOK(sc) Set allowed = 1
			Quit
		}
		Set until = ##class(OcuTalon.Data.Time).AddSeconds($List(times, 1), ..#WINDOW)
		If until = "" Quit
		Set first = '(session.AllowanceUntil ] now)
		TStart
		Set sc = ..Refused(session.Ref, channel, text, now)
		If $SYSTEM.Status.IsOK(sc) && first {
			Set session.AllowanceTimes = times
			Set session.AllowanceUntil = until
			Set sc = session.%Save()
		}
		If $SYSTEM.Status.IsOK(sc) {
			TCommit
			Set retryAt = until
			Set firstRefusal = first
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) || (('allowed) && (retryAt = "")) {
		While $TLevel > level {
			TRollback 1
		}
		Set retryAt = ""
		Set firstRefusal = 0
		Set allowed = 0
		If $IsObject(session) Do ..Forget(session)
	}
	Do ##class(OcuTalon.Data.Session).%UnlockId(id)
	Quit allowed
}

/// The Turn that records a refused message: state refused, the channel and the text, a new Ref and ItemId, now as CreatedAt, no
/// ClientId, no decision. Saved by the caller's transaction.
ClassMethod Refused(sessionRef As %String, channel As %String, text As %String, now As %String) As %Status [ Private ]
{
	Set turn = ##class(OcuTalon.Data.Turn).%New()
	Set turn.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set turn.SessionRef = sessionRef
	Set turn.State = ..#REFUSED
	Set turn.Channel = channel
	Set turn.Text = text
	Set turn.CreatedAt = now
	Set turn.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Quit turn.%Save()
}

/// The entries of the list that are inside the window that ends at now (later than now minus WINDOW seconds), oldest first and at
/// most limit of them (the newest); an entry that is not a UTC time is dropped.
ClassMethod Kept(times As %List, now As %String, limit As %Integer) As %List [ Private ]
{
	Set cutoff = ##class(OcuTalon.Data.Time).Seconds(now) - ..#WINDOW
	Set kept = ""
	Set position = 0
	While $ListNext($Get(times), position, entry) {
		Set seconds = ##class(OcuTalon.Data.Time).Seconds(entry)
		If (seconds '= "") && (seconds > cutoff) Set kept = kept_$ListBuild(entry)
	}
	Set count = $ListLength(kept)
	If count > limit Set kept = $List(kept, count - limit + 1, count)
	Quit kept
}

/// Takes the unsaved changes of the row back after a failure: reloads it from disk. It never throws.
ClassMethod Forget(session As OcuTalon.Data.Session) [ Private ]
{
	Try {
		Do session.%Reload()
	} Catch {
	}
}

/// Gives back the newest entry of the session's AllowanceTimes: the message was allowed, and then its send failed. With the flag
/// off, for a session that has no row, or with no entry, it does nothing. It never throws; a failure is logged as a warning.
ClassMethod Refund(sessionRef As %String)
{
	If ..Off() Quit
	Set id = "", locked = 0
	Try {
		If ($Get(sessionRef) = "") || '##class(OcuTalon.Data.Session).RefIndexExists(sessionRef, .id) Quit
		Set sc = ##class(OcuTalon.Data.Session).%LockId(id, 0, ..#LOCKWAIT)
		If $SYSTEM.Status.IsOK(sc) {
			Set locked = 1
			Set session = ##class(OcuTalon.Data.Session).%OpenId(id, , .sc)
			If $SYSTEM.Status.IsOK(sc) && $IsObject(session) Set sc = session.%Reload()
			If $SYSTEM.Status.IsOK(sc) && $IsObject(session) && ($ListLength(session.AllowanceTimes) > 0) {
				Set times = session.AllowanceTimes
				Set count = $ListLength(times)
				Set session.AllowanceTimes = $Select(count = 1: "", 1: $List(times, 1, count - 1))
				Set sc = session.%Save()
			}
		}
		If $SYSTEM.Status.IsError(sc) $$$LOGWARNING(..#LOGREFUND_$SYSTEM.Status.GetOneStatusText(sc))
	} Catch exception {
		Try {
			$$$LOGWARNING(..#LOGREFUND_exception.DisplayString())
		} Catch {
		}
	}
	If locked Do ##class(OcuTalon.Data.Session).%UnlockId(id)
}

/// The messages a session may send in the window: the public setting messageAllowance when it is a whole number of 1 or more,
/// otherwise DEFAULTLIMIT (50).
ClassMethod Limit() As %Integer
{
	Set value = ##class(OcuTalon.Data.Setting).Get("messageAllowance")
	If (value ? 1.N) && (+value >= 1) Quit +value
	Quit ..#DEFAULTLIMIT
}

/// The UTC time when the session's allowance window ends: its AllowanceUntil when that is later than now (by default the
/// current time), otherwise "". It does not look at the flag. A session with no row gives "". A failed read throws.
ClassMethod Until(sessionRef As %String, now As %String = "") As %String
{
	If $Get(sessionRef) = "" Quit ""
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef, , .sc)
	If '$IsObject(session) {
		If $SYSTEM.Status.IsError(sc) && '$SYSTEM.Status.Equals(sc, 5770) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
		Quit ""
	}
	Set sc = session.%Reload()
	If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	If now = "" Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Quit $Select(session.AllowanceUntil ] now: session.AllowanceUntil, 1: "")
}

/// The one-time notice of a session whose allowance is used up: a Notification of kind allowance with the catalog key
/// conversation.sessionAllowance and the slots limit, time (retryAt, UTC) and readmeLink (INSTALLLINK). The channel service
/// whose call was refused sends it (AD-20, AD-32); it renders nothing.
ClassMethod Notice(sessionRef As %String, retryAt As %String) As OcuTalon.Msg.Notification
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = sessionRef
	Set notification.Kind = "allowance"
	Set notification.CatalogKey = "conversation.sessionAllowance"
	Set slots = {}
	Do slots.%Set("limit", ..Limit(), "number")
	Set slots.time = retryAt
	Set slots.readmeLink = ..#INSTALLLINK
	Set notification.Slots = slots.%ToJSON()
	Quit notification
}

/// The daily-cap message of a session: a Notification of kind allowance with the catalog key conversation.dailyCap and the slots
/// time (resetsAt, UTC) and readmeLink (INSTALLLINK). BridgeSink sends it (AD-20, AD-31).
ClassMethod DailyCapNotice(sessionRef As %String, resetsAt As %String) As OcuTalon.Msg.Notification
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = sessionRef
	Set notification.Kind = "allowance"
	Set notification.CatalogKey = "conversation.dailyCap"
	Set slots = {}
	Set slots.time = resetsAt
	Set slots.readmeLink = ..#INSTALLLINK
	Set notification.Slots = slots.%ToJSON()
	Quit notification
}

/// 1 when the session may simulate one more incoming email at now (UTC): always with the flag off, otherwise when it has fewer
/// than EMAILLIMIT incoming emails (samples included, outgoing ones never) after now minus WINDOW seconds
/// (Ownership.IncomingMail). The caller holds the session row's lock across this call and the save of its email. When it is 0,
/// retryAt is the UTC time when the oldest of them leaves the window. sc is an error status when the count could not be read,
/// and the result is then 0 with retryAt "".
ClassMethod MailAllowed(sessionRef As %String, now As %String, Output retryAt As %String, Output sc As %Status) As %Boolean
{
	Set retryAt = ""
	Set sc = $SYSTEM.Status.OK()
	If ..Off() Quit 1
	Set count = ##class(OcuTalon.Data.Ownership).IncomingMail(sessionRef, ##class(OcuTalon.Data.Time).AddSeconds(now, -..#WINDOW), .oldest, .sc)
	If $SYSTEM.Status.IsError(sc) Quit 0
	If count < ..#EMAILLIMIT Quit 1
	Set retryAt = ##class(OcuTalon.Data.Time).AddSeconds(oldest, ..#WINDOW)
	Quit 0
}

/// 1 when the online-demo flag is not set: then no allowance applies.
ClassMethod Off() As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Data.Setting).Get("onlineDemo") '= 1
}

}
