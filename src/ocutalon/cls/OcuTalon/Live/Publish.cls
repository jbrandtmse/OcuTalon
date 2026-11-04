Include Ensemble

/// The only writer of OcuTalon.Live.Event rows (AD-12). Lane B.
/// Publish allocates the next Seq of a stream under the stream's lock, which is held across the allocation, the
/// insert and the commit, so a stream's rows have no gaps and commit in Seq order. The counter is
/// ^OcuTalonP.LiveEventC(stream): the purge deletes rows and never the counter, so Seq never restarts.
/// guide.state has one publisher, RefreshGuide (AD-12, AD-33): while demo mode is on, Publish calls it after it has committed and
/// unlocked an event of a GUIDETRIGGERS type on a session's stream, and the StatusMonitor tick and the guide marker endpoint call
/// it too. A refresh that fails is logged and never changes what Publish answers.
/// Waking: after each committed event, and after its lock is released, Publish signals the stream's $SYSTEM.Event resource (WakeName),
/// which the live WebSocket (Web.Live) waits on beside its other stream's. A signal wakes one waiter or queues one wakeup, and a resource
/// that nobody created is ignored. The resource is a name only: no global is ever set under it. A refused publish signals nothing.
Class OcuTalon.Live.Publish
{

/// The event table: type:payload class, where the class is OcuTalon.Live.Payload.<Class>. Each type has one publisher
/// (the spine's event table); web/scripts/payloads.mjs reads this list.
Parameter TYPES = "chat.message:ChatMessage,notification:Notification,phone:Phone,mailbox:Mailbox,decision:Decision,approval:Approval,turn.step:TurnStep,reminder:Reminder,pairing:Pairing,status:Status,reset:Reset,breakfeed.progress:BreakFeedProgress,guide.state:GuideState,incident:Incident,watch.progress:WatchProgress,check:Check";

/// The stream of the instance-wide events.
Parameter INSTANCE = "instance";

/// The event types after which Publish refreshes the session's guide.
Parameter GUIDETRIGGERS = "chat.message,incident,approval,check,reminder,pairing,breakfeed.progress";

Parameter LOGGUIDE = "Live.Publish could not refresh the guide: ";

/// Seconds to wait for the stream's lock, unless the caller names a shorter or longer wait.
Parameter LOCKWAIT = 5;

/// The full name of the payload class of a type, "" when the type is not in the event table.
ClassMethod PayloadClass(type As %String) As %String
{
	Set pairs = $ListFromString(..#TYPES)
	Set position = 0
	While $ListNext(pairs, position, pair) {
		If $Piece(pair, ":", 1) = type Return "OcuTalon.Live.Payload."_$Piece(pair, ":", 2)
	}
	Quit ""
}

/// The number of the last event committed on a stream, 0 when there is none. It waits, under a shared lock, for an
/// open Publish of the stream to commit, so a page that takes this number as its cursor never skips an event; it
/// throws when the lock isn't free in LOCKWAIT seconds.
ClassMethod LastSeq(stream As %String) As %Integer
{
	If '..IsStream(stream) Quit 0
	Lock +^OcuTalonP.LiveEventC(stream)#"S":..#LOCKWAIT
	If '$Test Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "The stream '"_stream_"' is busy: its lock wasn't free in "_..#LOCKWAIT_" seconds"))
	Set seq = +$Get(^OcuTalonP.LiveEventC(stream))
	Lock -^OcuTalonP.LiveEventC(stream)#"SI"
	Quit seq
}

/// The name of the $SYSTEM.Event resource that a stream's waiters wait on and Publish signals. It is a resource name only: the
/// global it spells is never set.
ClassMethod WakeName(stream As %String) As %String
{
	Quit $Name(^OcuTalonP.LiveWake(stream))
}

/// Wakes one waiter on the stream's resource, or queues one wakeup for the next to wait. A resource that no process created is
/// ignored.
ClassMethod Wake(stream As %String)
{
	Try {
		Do $SYSTEM.Event.Signal(..WakeName(stream))
	} Catch {
	}
}

/// 1 when stream is the instance stream or a 22-character reference.
ClassMethod IsStream(stream As %String) As %Boolean
{
	Quit (stream = ..#INSTANCE) || (stream ? 22(1AN,1"-",1"_"))
}

/// Publishes payload, the full current view of one entity, as the next event of stream. type must be in the event
/// table and payload an object of that type's class. seq is the new event's number. Refused inside an open
/// transaction: a nested commit would release the lock before the outer commit. lockWait is the seconds to wait for the
/// stream's lock (LOCKWAIT by default). On failure nothing is written and the counter is unchanged.
ClassMethod Publish(stream As %String, type As %String, payload As %RegisteredObject, Output seq As %Integer, lockWait As %Integer = {..#LOCKWAIT}) As %Status
{
	Set seq = 0
	If $TLevel > 0 Quit $SYSTEM.Status.Error(5001, "Live events can't be published inside an open transaction")
	Set class = ..PayloadClass(type)
	If class = "" Quit $SYSTEM.Status.Error(5001, "'"_type_"' is not a live event type")
	If '$IsObject(payload) || ($ClassName(payload) '= class) Quit $SYSTEM.Status.Error(5001, "The payload of '"_type_"' must be an object of class "_class)
	If '..IsStream(stream) Quit $SYSTEM.Status.Error(5001, "The stream must be instance or a 22-character reference")

	Set sc = $SYSTEM.Status.OK()
	Set locked = 0
	Try {
		Lock +^OcuTalonP.LiveEventC(stream):lockWait
		If '$Test {
			Set sc = $SYSTEM.Status.Error(5001, "The stream '"_stream_"' is busy: its lock wasn't free in "_lockWait_" seconds")
		} Else {
			Set locked = 1
			TSTART
			Set next = $Get(^OcuTalonP.LiveEventC(stream)) + 1
			Set ^OcuTalonP.LiveEventC(stream) = next
			Set sc = payload.%JSONExportToString(.json)
			If $SYSTEM.Status.IsOK(sc) {
				Set event = ##class(OcuTalon.Live.Event).%New()
				Set event.Seq = next
				Set event.Stream = stream
				Set event.Ts = ##class(OcuTalon.Data.Time).NowUtc()
				Set event.Type = type
				Set event.Payload = json
				Set sc = event.%Save()
			}
			If $SYSTEM.Status.IsOK(sc) {
				TCOMMIT
				Set seq = next
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $TLevel > 0 TROLLBACK
	If locked Lock -^OcuTalonP.LiveEventC(stream)
	If $SYSTEM.Status.IsOK(sc) Do ..Wake(stream)
	If $SYSTEM.Status.IsOK(sc) && (stream '= ..#INSTANCE) && $ListFind($ListFromString(..#GUIDETRIGGERS), type) {
		Set refresh = ..RefreshGuide(stream, , lockWait)
		If $SYSTEM.Status.IsError(refresh) {
			$$$LOGWARNING(..#LOGGUIDE_$SYSTEM.Status.GetOneStatusText(refresh))
		}
	}
	Quit sc
}

/// Recomputes the guide of the session (Demo.Guide.Compute) and publishes it as a guide.state event when its JSON differs from
/// the payload of the stream's latest guide.state event; a stream with no such event is compared with Demo.Guide.Blank().
/// It acts only while demo mode is on and only when sessionRef is exactly the Ref of a Session row; otherwise it does nothing
/// and guide stays empty. It holds the session's guide lock (Data.GuideState.Lock) while it computes, compares and publishes,
/// so that the last refresh publishes the newest view. guide is the computed view, published or not. lockWait is the seconds
/// it waits for the guide lock and for the stream's lock (LOCKWAIT by default); Publish passes its caller's, so a caller
/// that bounds its wait (BridgeSink's one second, AD-31) bounds the refresh too. An error status says that the refresh
/// failed (a lock wasn't free, a read failed or the publish was refused); nothing is published then.
ClassMethod RefreshGuide(sessionRef As %String, Output guide As %RegisteredObject, lockWait As %Integer = {..#LOCKWAIT}) As %Status
{
	Set guide = ""
	If '##class(OcuTalon.Demo.Guide).DemoOn() Quit $SYSTEM.Status.OK()
	If '..IsStream(sessionRef) || (sessionRef = ..#INSTANCE) Quit $SYSTEM.Status.OK()
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef)
	If '$IsObject(session) || (session.Ref '= sessionRef) Quit $SYSTEM.Status.OK()
	If '##class(OcuTalon.Data.GuideState).Lock(sessionRef, lockWait) Quit $SYSTEM.Status.Error(5001, "The guide of the session is busy: its lock wasn't free in "_lockWait_" seconds")
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set guide = ##class(OcuTalon.Demo.Guide).Compute(sessionRef)
		Set sc = guide.%JSONExportToString(.json)
		If $SYSTEM.Status.IsOK(sc) {
			Set last = ##class(OcuTalon.Data.Ownership).LastEvent(sessionRef, "guide.state", .sc)
		}
		If $SYSTEM.Status.IsOK(sc) {
			If $IsObject(last) {
				Set base = last.Payload
			} Else {
				Set sc = ##class(OcuTalon.Demo.Guide).Blank().%JSONExportToString(.base)
			}
		}
		If $SYSTEM.Status.IsOK(sc) && (json '= base) {
			Set sc = ..Publish(sessionRef, "guide.state", guide, , lockWait)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Do ##class(OcuTalon.Data.GuideState).Unlock(sessionRef)
	Quit sc
}

}
