/// The trace thread of a session and the position of an Item in Visual Trace (AD-26, AD-4). Lane B. None of its methods sends a
/// message or throws.
///   - A session has one trace thread a day: the SessionId of the first Item header of the instance-zone local day (Day),
///     kept on the Session row as ThreadSessionId and ThreadDay. Join gives a channel service that id, so that the Items of
///     a day are one Visual Trace session. When the day has no thread yet, Join returns "" and keeps the row's lock, so that
///     two first messages of a day cannot both start a thread; the service sends its message in a session of its own and
///     then calls Started with the id the send gave, which records it and releases the lock. Only channel services call
///     Join; the other code of a turn joins the thread through the bridge context's ThreadSessionId;
///   - Position works out where a header lands in the item list that Visual Trace draws for the header's session, with the
///     event-log and rule-log rows shown and hidden. It ports the counting of EnsPortal.SVG.VisualTrace.BuildTraceInfo and
///     InjectEvents without the drawing: the session's headers in ID order up to the header, and, before each header, the
///     event-log (Ens_Util.Log) and rule-log (Ens_Rule.Log) rows that sort before it (an earlier time, or the same time and a
///     lower MessageId), each counted only when its host is the source or target of an earlier header; a row that fails that
///     test is passed over for good. The I/O-log rows, ACK rows and internal items are not counted: Visual Trace reads the
///     I/O log with a statement that the trace role may not run (it holds SELECT on Ens.MessageHeader alone), so the page of a
///     trace user draws none of those rows, and no OcuTalon message is an EDI document or an internal item. Every read
///     prepares with the privilege check, so Position runs only in production jobs and tests.
Class OcuTalon.Core.Trace
{

/// Seconds Join waits for the Session row's lock.
Parameter LOCKWAIT = 2;

Parameter ERRORNOSESSION = "The session has no session row, so it has no trace thread.";

Parameter ERRORBUSY = "The session's row is busy: its lock wasn't free in the time allowed.";

Parameter ERRORTIME = "The time is not a UTC time, so the day of the thread is unknown.";

Parameter ERRORHEADER = "There is no message header to find in the trace.";

Parameter ERRORREAD = "The read of the trace failed: ";

/// The session's thread for the day of now (a UTC time, by default the current time). The row is read from disk once the lock
/// is held, so a Session object the caller opened before is refreshed, not trusted. When the Session row holds a thread
/// for that day it is released and returned. Otherwise "" is returned with sc OK and the row's lock KEPT: the caller sends its
/// message and calls Started, whatever the send did. When there is no Session row, the time is unreadable or the lock is not
/// free within LOCKWAIT seconds, "" is returned with an error sc and the lock is not held.
ClassMethod Join(sessionRef As %String, Output sc As %Status, now As %String = "") As %Integer
{
	Set sc = $SYSTEM.Status.OK()
	Set thread = ""
	Set id = ""
	Set locked = 0
	Try {
		Set day = ..Day(now)
		If day = "" {
			Set sc = $SYSTEM.Status.Error(5001, ..#ERRORTIME)
			Quit
		}
		If (sessionRef = "") || '##class(OcuTalon.Data.Session).RefIndexExists(sessionRef, .id) {
			Set sc = $SYSTEM.Status.Error(5001, ..#ERRORNOSESSION)
			Quit
		}
		If $SYSTEM.Status.IsError(##class(OcuTalon.Data.Session).%LockId(id, 0, ..#LOCKWAIT)) {
			Set sc = $SYSTEM.Status.Error(5001, ..#ERRORBUSY)
			Quit
		}
		Set locked = 1
		Set session = ##class(OcuTalon.Data.Session).%OpenId(id, , .sc)
		If $SYSTEM.Status.IsError(sc) Quit
		If '$IsObject(session) {
			Set sc = $SYSTEM.Status.Error(5001, ..#ERRORNOSESSION)
			Quit
		}
		Set sc = session.%Reload()
		If $SYSTEM.Status.IsError(sc) Quit
		If (session.ThreadDay = day) && (session.ThreadSessionId '= "") {
			Set thread = session.ThreadSessionId
			Do ..Release(id)
			Set locked = 0
		}
	} Catch exception {
		Set sc = exception.AsStatus()
		Set thread = ""
	}
	If locked && $SYSTEM.Status.IsError(sc) Do ..Release(id)
	Quit thread
}

/// Records sessionId as the session's thread for the day of now, on the row as read from disk, and releases the lock that Join
/// kept. An empty sessionId records nothing. A session with no row, or a time that cannot be read, is an error status and
/// records nothing; a row that is gone leaves no id to unlock, so a lock Join kept on it stays with the process.
ClassMethod Started(sessionRef As %String, sessionId As %Integer, now As %String = "") As %Status
{
	Set sc = $SYSTEM.Status.OK()
	Set id = ""
	Try {
		If (sessionRef '= "") && ##class(OcuTalon.Data.Session).RefIndexExists(sessionRef, .id) {
			If sessionId '= "" {
				Set day = ..Day(now)
				Set session = ##class(OcuTalon.Data.Session).%OpenId(id, , .sc)
				If $SYSTEM.Status.IsOK(sc) && $IsObject(session) Set sc = session.%Reload()
				If $SYSTEM.Status.IsOK(sc) {
					If (day = "") || '$IsObject(session) {
						Set sc = $SYSTEM.Status.Error(5001, $Select(day = "": ..#ERRORTIME, 1: ..#ERRORNOSESSION))
					} Else {
						Set session.ThreadSessionId = sessionId
						Set session.ThreadDay = day
						Set sc = session.%Save()
					}
				}
			}
		} Else {
			Set id = ""
			If sessionId '= "" Set sc = $SYSTEM.Status.Error(5001, ..#ERRORNOSESSION)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If id '= "" Do ..Release(id)
	Quit sc
}

/// The instance-zone local date, YYYY-MM-DD, of a UTC time (YYYY-MM-DDThh:mm:ssZ; by default the current time), "" for a time
/// that cannot be read. Data.Time.ToLocal is the one zone conversion.
ClassMethod Day(now As %String = "") As %String
{
	Quit $Extract(##class(OcuTalon.Data.Time).ToLocal($Select(now = "": ##class(OcuTalon.Data.Time).NowUtc(), 1: now)), 1, 10)
}

/// Releases the lock on the Session row.
ClassMethod Release(id As %String) [ Private ]
{
	Do ##class(OcuTalon.Data.Session).%UnlockId(id)
}

/// The position of the header in the item list of its session, 1-based, with the event-log and rule-log rows shown
/// (withEvents) and hidden (withoutEvents). An unknown header or a failed read is an error status and leaves both empty.
ClassMethod Position(headerId As %String, Output withEvents As %Integer, Output withoutEvents As %Integer) As %Status
{
	Set (withEvents, withoutEvents) = ""
	Kill headers, events
	Try {
		Set sc = ..ReadHeaders(headerId, .sessionId, .headers)
		If $SYSTEM.Status.IsOK(sc) Set sc = ..ReadEvents(sessionId, .headers, .events)
		If $SYSTEM.Status.IsOK(sc) {
			Set with = ..Count(headerId, .headers, .events, 1)
			Set without = ..Count(headerId, .headers, .events, 0)
			If (with = "") || (without = "") {
				Set sc = $SYSTEM.Status.Error(5001, ..#ERRORHEADER)
			} Else {
				Set withEvents = with
				Set withoutEvents = without
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
		Set (withEvents, withoutEvents) = ""
	}
	Quit sc
}

/// The session of the header, and the session's headers in ID order up to it: headers = the count, headers(i) = $ListBuild(ID,
/// TimeCreated, SourceConfigName, TargetConfigName).
ClassMethod ReadHeaders(headerId As %String, Output sessionId As %String, Output headers) As %Status [ Private ]
{
	Set sessionId = ""
	Set headers = 0
	If headerId '? 1.N Quit $SYSTEM.Status.Error(5001, ..#ERRORHEADER)
	Set sc = ..Open("SELECT SessionId FROM Ens.MessageHeader WHERE %ID = ?", .result, headerId)
	If $SYSTEM.Status.IsError(sc) Quit sc
	If 'result.%Next() Quit $SYSTEM.Status.Error(5001, ..#ERRORHEADER)
	Set sessionId = result.%Get("SessionId")
	If sessionId = "" Quit $SYSTEM.Status.Error(5001, ..#ERRORHEADER)
	Set sc = ..Open("SELECT %ID AS ID, TimeCreated, SourceConfigName, TargetConfigName FROM Ens.MessageHeader WHERE SessionId = ? AND %ID <= ? ORDER BY %ID", .result, sessionId, headerId)
	If $SYSTEM.Status.IsError(sc) Quit sc
	While result.%Next() {
		Set headers = headers + 1
		Set headers(headers) = $ListBuild(result.%Get("ID"), result.%Get("TimeCreated"), result.%Get("SourceConfigName"), result.%Get("TargetConfigName"))
	}
	Quit $SYSTEM.Status.OK()
}

/// The event-log and rule-log rows of the session in one array, keyed as Visual Trace keys them: events(time_"#"_messageId,
/// rowId) = host. A row with no host at all is left out. An event's host is its ConfigName, else its SourceClass; a rule row's is
/// its ConfigName, else the SourceConfigName of the session's first header; a rule row with no CurrentHeaderId is keyed by the
/// session's id. A rule row is set after the event rows, so it replaces an event row with the same key.
ClassMethod ReadEvents(sessionId As %String, ByRef headers, Output events) As %Status [ Private ]
{
	Kill events
	Set sc = ..Open("SELECT %ID AS ID, TimeLogged, ConfigName, MessageId, SourceClass FROM Ens_Util.Log WHERE SessionId = ?", .result, sessionId)
	If $SYSTEM.Status.IsError(sc) Quit sc
	While result.%Next() {
		Set host = result.%Get("ConfigName")
		If host = "" Set host = result.%Get("SourceClass")
		If host = "" Continue
		Set events(result.%Get("TimeLogged")_"#"_result.%Get("MessageId"), result.%Get("ID")) = host
	}
	Set first = ""
	For i = 1:1:headers {
		If $List(headers(i), 1) = sessionId Set first = $List(headers(i), 3)
	}
	Set sc = ..Open("SELECT %ID AS ID, TimeExecuted, ConfigName, CurrentHeaderId FROM Ens_Rule.Log WHERE SessionId = ?", .result, sessionId)
	If $SYSTEM.Status.IsError(sc) Quit sc
	While result.%Next() {
		Set host = result.%Get("ConfigName")
		If host = "" Set host = first
		If host = "" Continue
		Set message = result.%Get("CurrentHeaderId")
		If message = "" Set message = sessionId
		Set events(result.%Get("TimeExecuted")_"#"_message, result.%Get("ID")) = host
	}
	Quit $SYSTEM.Status.OK()
}

/// The statement's result for the arguments, prepared with the privilege check.
ClassMethod Open(sql As %String, Output result As %SQL.StatementResult, args...) As %Status [ Private ]
{
	Set result = ""
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare(sql)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set result = statement.%Execute(args...)
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, ..#ERRORREAD_result.%Message)
	Quit $SYSTEM.Status.OK()
}

/// The header's place in the drawn list, "" when the header is not among the headers. Visual Trace draws the headers in ID
/// order; before each header it draws, while they sort before it, the event and rule rows whose host is on the diagram (the
/// source or target of an earlier header). With withEvents 0 no event or rule row is drawn.
ClassMethod Count(headerId As %String, ByRef headers, ByRef events, withEvents As %Boolean) As %Integer [ Private ]
{
	Kill hosts
	Set cursor = $Select(withEvents: $Order(events("")), 1: "")
	Set n = 0
	Set id = ""
	For i = 1:1:headers {
		Set id = $List(headers(i), 1)
		Set created = $List(headers(i), 2)
		Do ..Inject(id, created, .events, .cursor, .hosts, .n)
		Set n = n + 1
		If +id = +headerId Quit
		If $List(headers(i), 3) '= "" Set hosts($List(headers(i), 3)) = ""
		If $List(headers(i), 4) '= "" Set hosts($List(headers(i), 4)) = ""
	}
	Quit $Select(+id = +headerId: n, 1: "")
}

/// Draws, for the header with this ID and TimeCreated, the event and rule rows that sort before it, from the cursor (the key of
/// the next row, time_"#"_messageId): a row is before the header when its time is earlier, or the same and its MessageId is
/// lower. A row is drawn when its host is on the diagram and is passed over otherwise. n grows by one for each row drawn.
ClassMethod Inject(id As %String, created As %String, ByRef events, ByRef cursor, ByRef hosts, ByRef n) [ Private ]
{
	For {
		Set eventTime = $Piece(cursor, "#", 1)
		Set eventMessage = $Piece(cursor, "#", 2)
		If eventTime = "" Quit
		If (eventTime ] created) || ((eventTime = created) && (eventMessage >= id)) Quit
		Set row = ""
		For {
			Set row = $Order(events(cursor, row), 1, host)
			Quit:row=""
			If $Data(hosts(host)) Set n = n + 1
		}
		Set cursor = $Order(events(cursor))
	}
}

}
