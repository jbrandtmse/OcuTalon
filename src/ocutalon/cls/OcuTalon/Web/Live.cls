/// The live-events WebSocket of local and IPM installs (AD-12, AD-13, Story 31.1). Lane B. It is the second live path, beside
/// polling GET /api/v1/events, which stays the contract: the socket only delivers sooner, and every frame is the body that
/// /events answers, {epoch, events}, from Api.EventsBody, so the page applies it with the same idempotent apply.
///   - The shell forwards GET /ocutalon/OcuTalon.Web.Live.cls to Accept, which runs the socket in synchronous mode. A request
///     without a session never gets here: the shell answers it with the sign-in page.
///   - OnPreServer makes every check before Server() runs (Refusal): the user role, not the online demo (an open socket keeps its
///     CSP session and a licence connection alive with no timeout, S13), an Origin equal to the request's own, the OcuTalon session
///     of the CSP session (Ownership.SessionRef, never request input; AD-4) and the cursors after and afterInstance. A refused
///     socket gets no frame and nothing is logged.
///   - Server waits on the $SYSTEM.Event resource of the session and of the instance stream, which Live.Publish signals after each
///     commit (WakeName), 0.25 seconds on each, and compares each stream's committed head (Publish.LastSeq) with its cursor at every
///     loop, so a missed wakeup costs at most one loop. Next decides each loop: end, send, heartbeat or wait.
///   - The socket ends when the session's sign-out mark (Data.Session.SignOuts) differs from its value at the open, so no frame
///     follows a sign-out, and at a fixed LIFETIME as a backstop; the page reconnects through the checks.
/// The socket writes no table and no global. It never deletes its wake resources, which other sockets of the stream may wait on.
Class OcuTalon.Web.Live Extends %CSP.WebSocket
{

/// Seconds of quiet after which a heartbeat frame {epoch, events: []} is sent.
Parameter HEARTBEAT = 25;

/// Seconds after which the server ends every socket.
Parameter LIFETIME = 60;

/// Seconds of one wait on a wake resource.
Parameter SLICE = 0.25;

/// The OcuTalon session of the CSP session.
Property SessionRef As %String;

/// The client's cursor on the session's stream, then the highest Seq sent on it.
Property After As %Integer;

/// The same for the instance stream.
Property AfterInstance As %Integer;

/// The stream served as the instance stream: Live.Publish's unless a test names another.
Property InstanceStream As %String [ InitialExpression = {##class(OcuTalon.Live.Publish).#INSTANCE} ];

/// The session's sign-out mark when the socket opened.
Property Mark As %Integer;

/// $ZHorolog when the socket opened.
Property StartedAt As %Numeric;

/// $ZHorolog of the last frame.
Property SentAt As %Numeric;

/// Seconds the socket lives: LIFETIME unless a test names another.
Property Lifetime As %Numeric [ InitialExpression = {..#LIFETIME} ];

/// The shell's route target. A request that is no upgrade (no WebSocket id) is answered 404 with no body, as the shell answers a
/// path it does not serve; an upgrade runs the socket.
ClassMethod Accept() As %Status
{
	If $Get(%request.CgiEnvs("HTTP_WEBSOCKET_ID")) = "" {
		Set %response.Status = "404 Not Found"
		Quit $SYSTEM.Status.OK()
	}
	Do ##class(%Library.Device).ReDirectIO(0)
	Quit ..Page()
}

/// "" when the socket may open, otherwise the code of the first check that fails, in this order: no_role (hasRole is 0),
/// online_demo (onlineDemo is 1), wrong_origin (origin is not the request's own scheme and host, the browser-envelope rule of
/// Api.EnvelopeError, and an empty origin fails), no_session (sessionRef is empty) and bad_cursor (after or afterInstance is not
/// 1 to 15 digits). The codes are internal and never sent.
ClassMethod Refusal(hasRole As %Boolean, onlineDemo As %String, origin As %String, host As %String, secure As %Boolean, sessionRef As %String, after As %String, afterInstance As %String) As %String
{
	If 'hasRole Quit "no_role"
	If onlineDemo = 1 Quit "online_demo"
	If ##class(OcuTalon.Web.Api).EnvelopeError("POST", "application/json", 1, origin, host, secure) '= "" Quit "wrong_origin"
	If sessionRef = "" Quit "no_session"
	If '(after ? 1.15N) || '(afterInstance ? 1.15N) Quit "bad_cursor"
	Quit ""
}

/// Every check, before Server(): see Admit.
Method OnPreServer() As %Status
{
	Quit ..Admit(##class(OcuTalon.Web.Public.Shell).HasRole())
}

/// The checks of OnPreServer for a user who holds the role (hasRole 1) or not (0). A refusal returns an error status, which gives the
/// client no frame. Otherwise it keeps the cursors, the session, the sign-out mark and the times, creates the two wake resources and
/// drops queued wakeups.
Method Admit(hasRole As %Boolean) As %Status
{
	Set sc = $SYSTEM.Status.OK()
	Set ref = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Set ref = ""
	Set after = $Get(%request.Data("after", 1))
	Set afterInstance = $Get(%request.Data("afterInstance", 1))
	Set refusal = ..Refusal(hasRole, ##class(OcuTalon.Data.Setting).Get("onlineDemo"), $Get(%request.CgiEnvs("HTTP_ORIGIN")), $Get(%request.CgiEnvs("HTTP_HOST")), %request.Secure, ref, after, afterInstance)
	If refusal '= "" Quit $SYSTEM.Status.Error(5001, "The live socket was refused")
	Set ..SessionRef = ref
	Set ..After = after
	Set ..AfterInstance = afterInstance
	Set ..Mark = ##class(OcuTalon.Data.Session).SignOuts(ref)
	Set ..StartedAt = $ZHorolog
	Set ..SentAt = ..StartedAt
	For name = ##class(OcuTalon.Live.Publish).WakeName(ref), ##class(OcuTalon.Live.Publish).WakeName(..InstanceStream) {
		Do $SYSTEM.Event.Create(name)
		Do $SYSTEM.Event.Clear(name)
	}
	Quit $SYSTEM.Status.OK()
}

/// The loop's decision, in this order: "end" when the sign-out mark changed since the open (markNow differs from markAtOpen), "end"
/// when the lifetime has passed since startedAt, "send" when a stream is ahead of its cursor, "heartbeat" when HEARTBEAT seconds
/// have passed since the last frame (sentAt), otherwise "wait". now, startedAt and sentAt are $ZHorolog values.
ClassMethod Next(markAtOpen As %Integer, markNow As %Integer, startedAt As %Numeric, now As %Numeric, sentAt As %Numeric, ahead As %Boolean, lifetime As %Numeric) As %String
{
	If markNow '= markAtOpen Quit "end"
	If (now - startedAt) >= lifetime Quit "end"
	If ahead Quit "send"
	If (now - sentAt) >= ..#HEARTBEAT Quit "heartbeat"
	Quit "wait"
}

/// The socket: decides each loop (Next), sends frames, waits on the wake resources and ends on a close frame or a failed write.
Method Server() As %Status
{
	Try {
		Set sessionWake = ##class(OcuTalon.Live.Publish).WakeName(..SessionRef)
		Set instanceWake = ##class(OcuTalon.Live.Publish).WakeName(..InstanceStream)
		For {
			Set sessionHead = ..Head(..SessionRef)
			Set instanceHead = ..Head(..InstanceStream)
			Set ahead = (sessionHead > ..After) || (instanceHead > ..AfterInstance)
			Set action = ..Next(..Mark, ##class(OcuTalon.Data.Session).SignOuts(..SessionRef), ..StartedAt, $ZHorolog, ..SentAt, ahead, ..Lifetime)
			If action = "end" Quit
			If action = "send" {
				If $SYSTEM.Status.IsError(..Send(sessionHead, instanceHead)) Quit
				Continue
			}
			If action = "heartbeat", $SYSTEM.Status.IsError(..Heartbeat()) Quit
			If ..Pause(sessionWake, instanceWake) Quit
		}
	} Catch exception {
	}
	Do ..EndServer()
	Quit $SYSTEM.Status.OK()
}

/// The committed head of a stream, 0 when it cannot be read now (the stream counts as not ahead and is read again next loop).
Method Head(stream As %String) As %Integer [ Private ]
{
	Set head = 0
	Try {
		Set head = ##class(OcuTalon.Live.Publish).LastSeq(stream)
	} Catch {
		Set head = 0
	}
	Quit head
}

/// The next frame: the body of /events for the cursors, {epoch, events}, with each cursor moved to the highest Seq of its stream in
/// it. "" when there is nothing to send because the purge removed the events that the heads count, in which
/// case the cursors move to the heads that were read (sessionHead, instanceHead) so that the loop does not spin.
Method Frame(sessionHead As %Integer, instanceHead As %Integer) As %DynamicObject
{
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(..SessionRef)
	If '$IsObject(session) Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "The session could not be opened"))
	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, ..After, ..AfterInstance, ..InstanceStream)
	Set events = body.events
	If events.%Size() = 0 {
		If sessionHead > ..After Set ..After = sessionHead
		If instanceHead > ..AfterInstance Set ..AfterInstance = instanceHead
		Quit ""
	}
	Set iterator = events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If event.stream = "instance" {
			If event.seq > ..AfterInstance Set ..AfterInstance = event.seq
		} ElseIf event.seq > ..After {
			Set ..After = event.seq
		}
	}
	Quit body
}

/// Writes the next frame, if there is one, and notes the time. An error status says that the socket must end.
Method Send(sessionHead As %Integer, instanceHead As %Integer) As %Status [ Private ]
{
	Set body = ..Frame(sessionHead, instanceHead)
	If body = "" Quit $SYSTEM.Status.OK()
	Set ..SentAt = $ZHorolog
	Quit ..Write(body.%ToJSON())
}

/// A frame with no events, which keeps the connection alive and applies nothing.
Method Heartbeat() As %Status [ Private ]
{
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(..SessionRef)
	If '$IsObject(session) Quit $SYSTEM.Status.Error(5001, "The session could not be opened")
	Set ..SentAt = $ZHorolog
	Quit ..Write({"epoch": (session.Epoch), "events": []}.%ToJSON())
}

/// One SLICE on the session's resource, then one on the instance's unless the session's was signalled, and a look at the client:
/// 1 when the client closed the socket or the connection failed, 0 otherwise.
Method Pause(sessionWake As %String, instanceWake As %String) As %Boolean [ Private ]
{
	If ..Wait(sessionWake) < 1 Do ..Wait(instanceWake)
	Set length = 32656
	Do ..Read(.length, .sc, 0)
	If $SYSTEM.Status.IsOK(sc) Quit 0
	Quit '$SYSTEM.Status.Equals(sc, 7950)
}

/// Waits one SLICE on a resource and answers the wait's code (1 signalled, 0 timed out). A resource that was deleted meanwhile is
/// created again.
Method Wait(name As %String) As %Integer [ Private ]
{
	Set result = $SYSTEM.Event.Wait(name, ..#SLICE)
	If result < 0 Do $SYSTEM.Event.Create(name)
	Quit result
}

}
