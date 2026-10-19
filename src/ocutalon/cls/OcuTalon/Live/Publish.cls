/// The only writer of OcuTalon.Live.Event rows (AD-12). Lane B.
/// Publish allocates the next Seq of a stream under the stream's lock, which is held across the allocation, the
/// insert and the commit, so a stream's rows have no gaps and commit in Seq order. The counter is
/// ^OcuTalonP.LiveEventC(stream): the purge deletes rows and never the counter, so Seq never restarts.
Class OcuTalon.Live.Publish
{

/// The event table: type:payload class, where the class is OcuTalon.Live.Payload.<Class>. Each type has one publisher
/// (the spine's event table); web/scripts/payloads.mjs reads this list.
Parameter TYPES = "chat.message:ChatMessage,notification:Notification,phone:Phone,mailbox:Mailbox,decision:Decision,approval:Approval,turn.step:TurnStep,reminder:Reminder,pairing:Pairing,status:Status,reset:Reset,breakfeed.progress:BreakFeedProgress,guide.state:GuideState,incident:Incident,watch.progress:WatchProgress,check:Check";

/// The stream of the instance-wide events.
Parameter INSTANCE = "instance";

/// Seconds to wait for the stream's lock.
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

/// 1 when stream is the instance stream or a 22-character reference.
ClassMethod IsStream(stream As %String) As %Boolean
{
	Quit (stream = ..#INSTANCE) || (stream ? 22(1AN,1"-",1"_"))
}

/// Publishes payload, the full current view of one entity, as the next event of stream. type must be in the event
/// table and payload an object of that type's class. seq is the new event's number. Refused inside an open
/// transaction: a nested commit would release the lock before the outer commit. On failure nothing is written
/// and the counter is unchanged.
ClassMethod Publish(stream As %String, type As %String, payload As %RegisteredObject, Output seq As %Integer) As %Status
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
		Lock +^OcuTalonP.LiveEventC(stream):..#LOCKWAIT
		If '$Test {
			Set sc = $SYSTEM.Status.Error(5001, "The stream '"_stream_"' is busy: its lock wasn't free in "_..#LOCKWAIT_" seconds")
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
	Quit sc
}

}
