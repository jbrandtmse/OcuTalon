/// WatchOps, the business operation that starts and stops the watches of a production (AD-1, AD-4, AD-15, AD-18, AD-33). It creates and removes the
/// rows of OcuTalon.Data.BackgroundCheck (the Checks item records each run, AD-18), and it answers every command with an OcuTalon.Msg.CommandResult.
///   - StartWatch: the session is the command's SessionRef (a Session row), and the asking IRIS user is that row's IrisUser, never a field of the
///     message. The production must be an entry of OcuTalon.Watch.Reader, whatever the origin of the command. A session that already watches the
///     production (the natural key: SessionRef, Kind production, Namespace, Production) gets no second row: the answer is already_watching with
///     the existing Ref, so a repeat of a command is harmless. Otherwise one row is written: Kind production, the reader's display name, CreatedAt and
///     NextDueAt the creation time (the same UTC value: NextDueAt makes the first heartbeat run the check, and CreatedAt is where the failures of
///     the watch start, see OcuTalon.Watch.Mark) and an empty Result. The answer is started with the new Ref.
///   - StopWatch: removes the session's own row for the namespace and production, and no other session's. The answer is stopped, or
///     not_watching with Ok 0 when the session had none.
///   - After a started answer (a new row) and after a stopped answer it sends the Checks item one OcuTalon.Checks.Msg.CheckChanged, asynchronously
///     (SendChanged), which Checks publishes as a check event; a stop reads the row's fields before the delete. The other answers send nothing. A
///     failed send logs one Type 3 warning (LOGCHANGED), and the answer stays as it was.
///   - A command for an unknown session answers no_session, and a StartWatch for a production that the reader does not list answers
///     unknown_production (only_orders on the online demo), with Ok 0 and no row.
/// The messages are plain sentences for the model and the caller, never rendered from the catalog (AD-32).
Class OcuTalon.Watch.Ops Extends Ens.BusinessOperation
{

/// The kind of the row.
Parameter KIND = "production";

Parameter MESSAGESTARTED = "The watch was started.";

Parameter MESSAGEALREADY = "The session already watches this production, so nothing was added.";

Parameter MESSAGESTOPPED = "The watch was stopped.";

Parameter MESSAGENOTWATCHING = "The session does not watch this production, so nothing was removed.";

Parameter MESSAGENOSESSION = "The command names no session, so nothing was done.";

Parameter MESSAGEUNKNOWN = "That production is not one that OcuTalon can watch, so nothing was started.";

Parameter MESSAGEONLYORDERS = "On the online demo only the Orders production can be watched, so nothing was started.";

/// The answer when the session's watches are busy (another command holds them) or the row cannot be saved or removed.
Parameter MESSAGEFAILED = "The watch could not be changed just now, so nothing was done.";

/// The configuration item that publishes the change of a check (AD-33).
Parameter CHECKS = "Checks";

Parameter LOGCHANGED = "WatchOps could not tell Checks about the watch ";

XData MessageMap
{
<MapItems>
<MapItem MessageType="OcuTalon.Msg.Command.StartWatch">
<Method>OnStart</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Msg.Command.StopWatch">
<Method>OnStop</Method>
</MapItem>
</MapItems>
}

/// Starts the watch of the command's production for its session, or answers why not (see the class description).
Method OnStart(request As OcuTalon.Msg.Command.StartWatch, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ""
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(request.SessionRef)
	If '$IsObject(session) Quit ..Answer(.response, 0, "no_session", ..#MESSAGENOSESSION)
	If '##class(OcuTalon.Watch.Reader).Admits(request.Namespace, request.Production, .displayName) {
		If ##class(OcuTalon.Watch.Reader).OnlineDemo() Quit ..Answer(.response, 0, "only_orders", ..#MESSAGEONLYORDERS)
		Quit ..Answer(.response, 0, "unknown_production", ..#MESSAGEUNKNOWN)
	}
	Set lock = ..Lock(request.SessionRef)
	If 'lock Quit ..Answer(.response, 0, "failed", ..#MESSAGEFAILED)
	Set sc = $$$OK
	Try {
		Set ref = ..RefOf(request.SessionRef, request.Namespace, request.Production)
		If ref '= "" {
			Set sc = ..Answer(.response, 1, "already_watching", ..#MESSAGEALREADY, ref)
		} Else {
			Set row = ##class(OcuTalon.Data.BackgroundCheck).%New()
			Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
			Set row.SessionRef = request.SessionRef
			Set row.Kind = ..#KIND
			Set row.Namespace = request.Namespace
			Set row.Production = request.Production
			Set row.DisplayName = displayName
			Set row.AskedBy = session.IrisUser
			Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
			Set row.NextDueAt = row.CreatedAt
			Set sc = row.%Save()
			If $$$ISOK(sc) {
				Set sc = ..Answer(.response, 1, "started", ..#MESSAGESTARTED, row.Ref)
				Do ..Changed(row.Ref, row.SessionRef, 0, row.Kind, row.Namespace, row.Production, row.DisplayName)
			} Else {
				Set response = ""
				Set sc = ..Answer(.response, 0, "failed", ..#MESSAGEFAILED)
			}
		}
	} Catch exception {
		Set response = ""
		Set sc = exception.AsStatus()
	}
	Lock -^OcuTalon.Watch(request.SessionRef)
	Quit sc
}

/// Stops the watch of the command's production for its session, or answers that there was none.
Method OnStop(request As OcuTalon.Msg.Command.StopWatch, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ""
	If '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(request.SessionRef)) Quit ..Answer(.response, 0, "no_session", ..#MESSAGENOSESSION)
	Set lock = ..Lock(request.SessionRef)
	If 'lock Quit ..Answer(.response, 0, "failed", ..#MESSAGEFAILED)
	Set sc = $$$OK
	Try {
		Set ref = ..RefOf(request.SessionRef, request.Namespace, request.Production, .id)
		If ref = "" {
			Set sc = ..Answer(.response, 0, "not_watching", ..#MESSAGENOTWATCHING)
		} Else {
			Set row = ##class(OcuTalon.Data.BackgroundCheck).%OpenId(id)
			Set kind = $Select($IsObject(row): row.Kind, 1: ..#KIND)
			Set namespace = $Select($IsObject(row): row.Namespace, 1: request.Namespace)
			Set production = $Select($IsObject(row): row.Production, 1: request.Production)
			Set displayName = $Select($IsObject(row): row.DisplayName, 1: "")
			Set sc = ##class(OcuTalon.Data.BackgroundCheck).%DeleteId(id)
			If $$$ISOK(sc) {
				Set sc = ..Answer(.response, 1, "stopped", ..#MESSAGESTOPPED, ref)
				Do ..Changed(ref, request.SessionRef, 1, kind, namespace, production, displayName)
			} Else {
				Set response = ""
				Set sc = ..Answer(.response, 0, "failed", ..#MESSAGEFAILED)
			}
		}
	} Catch exception {
		Set response = ""
		Set sc = exception.AsStatus()
	}
	Lock -^OcuTalon.Watch(request.SessionRef)
	Quit sc
}

/// Tells the Checks item that a watch was started (stopped 0) or stopped (stopped 1), through SendChanged. A failed send, or an exception, logs one
/// Type 3 warning and changes nothing else.
Method Changed(ref As %String, sessionRef As %String, stopped As %Boolean, kind As %String, namespace As %String, production As %String, displayName As %String) [ Private ]
{
	Try {
		Set message = ##class(OcuTalon.Checks.Msg.CheckChanged).%New()
		Set message.CheckRef = ref
		Set message.SessionRef = sessionRef
		Set message.Stopped = stopped
		Set message.Kind = kind
		Set message.Namespace = namespace
		Set message.Production = production
		Set message.DisplayName = displayName
		Set sc = ..SendChanged(message)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGCHANGED_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
}

/// Sends the message to the Checks item, asynchronously, with no answer wanted (a seam for the tests).
Method SendChanged(message As OcuTalon.Checks.Msg.CheckChanged) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#CHECKS, message)
}

/// The Ref of the session's row for the namespace and production (its id in id), or "" when it has none. The natural key of a watch is
/// SessionRef, Kind, Namespace and Production.
ClassMethod RefOf(sessionRef As %String, namespace As %String, production As %String, Output id As %String) As %String [ Private ]
{
	Set id = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID, Ref FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ? AND Kind = ? AND Namespace = ? AND Production = ? ORDER BY ID", sessionRef, ..#KIND, namespace, production)
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "WatchOps could not read the watches of the session: "_rs.%Message))
	If 'rs.%Next() Quit ""
	Set id = rs.%Get("ID")
	Quit rs.%Get("Ref")
}

/// Takes the lock that serialises the commands of one session; 1 when it is held. The caller releases it.
ClassMethod Lock(sessionRef As %String) As %Boolean [ Private ]
{
	Lock +^OcuTalon.Watch(sessionRef):5
	Quit $Test
}

/// Builds the CommandResult in response and returns OK.
ClassMethod Answer(ByRef response As OcuTalon.Msg.CommandResult, ok As %Boolean, outcome As %String, message As %String, ref As %String = "") As %Status [ Private ]
{
	Set response = ##class(OcuTalon.Msg.CommandResult).%New()
	Set response.Ok = ok
	Set response.Outcome = outcome
	Set response.Message = message
	Set response.Ref = ref
	Quit $$$OK
}

}
