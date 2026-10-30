Include Ensemble

/// A snapshot of what a fix could change in namespaces (Story 7.1; the helper of the "nothing changed" tests; Stories 7.3 and 7.4 reuse it). It has no Test methods.
///   - Take(namespaces) first waits up to WAITQUEUES seconds for every queue of every namespace to be empty, then reads, in each namespace: every Ens.MessageHeader
///     row (all columns) with the stored properties of its body; each production definition (its XML export: the production's attributes and settings, and every
///     item with its attributes and settings), the production's state, and every Ens_Config.DefaultSettings row; and the queue counts (Ens.Queue_Enumerate()). The
///     snapshot is a dynamic object, one member per namespace, each with the members headers, productions, state, defaults and queues, keyed by id or name, whose
///     values are text. A query that fails throws, so that no category is missed silently;
///   - Diff(before, after, allowedSessions, allowedIn) gives one line per changed or missing item, and per new item: a new header is left out when its namespace is
///     allowedIn (the namespace Diff runs in, by default) and its SessionId is one of allowedSessions (a comma-separated list: the session of the request the test
///     sent, which its answer shares), or when its session is one that a new HeartbeatIn header of its namespace started (a scheduled tick, with whatever it sends on).
///     The lines are given as a dynamic array of strings, empty when nothing changed.
///   - A timer that was already running when "before" was taken is no change of the fix: in ALARMIN, a header whose target is ALARM and whose status in "before" was
///     Created, Queued or Delivered is the request of a timer that an earlier session armed (a SetTimer of one of OcuTalon's processes, such as a Decide call's), and
///     it still fires after that session has ended. Diff leaves out any change of that request (it completes, or ends in another final status) and, for each such
///     request, one new header that ALARM sent in the same session (the wake-up). A timer armed after "before" (its request is new), a running timer's request that
///     is missing after, and every other header still count.
/// It only reads. It switches namespace in QueuedIn and TakeIn, which call Ens, %SQL and dictionary classes there and open each header's body through its own class.
Class OcuTalon.Test.Fix.Snapshot
{

/// The longest wait for empty queues, in seconds.
Parameter WAITQUEUES = 10;

/// The source of a scheduled tick, whose new headers Diff allows.
Parameter HEARTBEAT = "HeartbeatIn";

/// The config name that timers are sent to, and that sends their wake-ups.
Parameter ALARM = "Ens.Alarm";

/// The only namespace in which Diff leaves out the firing of a timer that was already running (OcuTalon's own, whose processes arm timers).
Parameter ALARMIN = "OCUTALON";

/// The snapshot of the namespaces (a list of names).
ClassMethod Take(namespaces As %List, Output snapshot As %DynamicObject)
{
	Set snapshot = {}
	Set end = $ZHorolog + ..#WAITQUEUES
	Set position = 0
	While $ListNext(namespaces, position, namespace) {
		While ..QueuedIn(namespace) && ($ZHorolog < end) {
			Hang 0.25
		}
	}
	Set position = 0
	While $ListNext(namespaces, position, namespace) {
		Do snapshot.%Set(namespace, ..TakeIn(namespace))
	}
}

/// The number of messages queued in the namespace.
ClassMethod QueuedIn(namespace As %String) As %Integer [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Set total = 0
	Set rs = ..Query("SELECT ""Count"" FROM Ens.Queue_Enumerate()")
	While rs.%Next() {
		Set total = total + rs.%GetData(1)
	}
	Quit total
}

/// What the namespace holds, as the members headers, productions, state, defaults and queues.
ClassMethod TakeIn(namespace As %String) As %DynamicObject [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Set taken = {"headers": {}, "productions": {}, "state": {}, "defaults": {}, "queues": {}}
	Set rs = ..Query("SELECT * FROM Ens.MessageHeader ORDER BY ID")
	Set columns = rs.%ResultColumnCount
	While rs.%Next() {
		Set row = ""
		For i = 1:1:columns Set row = row _ rs.%GetData(i) _ $Char(31)
		Set id = rs.%Get("ID")
		Set bodyClass = rs.%Get("MessageBodyClassName")
		Do taken.headers.%Set(id, $Piece(row, $Char(31), 1, columns) _ $Char(30) _ ..BodyOf(bodyClass, rs.%Get("MessageBodyId")))
	}
	Set rs = ..Query("SELECT Name FROM Ens_Config.Production")
	While rs.%Next() {
		Set name = rs.%GetData(1)
		Do taken.productions.%Set(name, ..DefinitionOf(name))
	}
	Set pname = ""
	Set pstate = ""
	Do ##class(Ens.Director).GetProductionStatus(.pname, .pstate)
	Do taken.state.%Set("production", $Get(pname) _ ":" _ $Get(pstate))
	Set rs = ..Query("SELECT * FROM Ens_Config.DefaultSettings ORDER BY ID")
	Set columns = rs.%ResultColumnCount
	While rs.%Next() {
		Set row = ""
		For i = 1:1:columns Set row = row _ rs.%GetData(i) _ $Char(31)
		Do taken.defaults.%Set(rs.%Get("ID"), row)
	}
	Set rs = ..Query("SELECT Name, ""Count"" FROM Ens.Queue_Enumerate()")
	While rs.%Next() {
		Do taken.queues.%Set(rs.%GetData(1), rs.%GetData(2))
	}
	Quit taken
}

/// The result of the query in the current namespace; an SQL error is thrown.
ClassMethod Query(sql As %String) As %SQL.StatementResult [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
	If rs.%SQLCODE < 0 Throw ##class(%Exception.SQL).CreateFromSQLCODE(rs.%SQLCODE, rs.%Message)
	Quit rs
}

/// The stored datatype properties of a message body, as name=value pairs in the order of the class, or "" when the body cannot be read.
ClassMethod BodyOf(bodyClass As %String, bodyId As %String) As %String [ Private ]
{
	If (bodyClass = "") || (bodyId = "") || '##class(%Dictionary.CompiledClass).%ExistsId(bodyClass) Quit ""
	If '$ClassMethod(bodyClass, "%Extends", "%Library.Persistent") Quit ""
	Set text = ""
	Try {
		Set object = $ClassMethod(bodyClass, "%OpenId", bodyId)
		If $IsObject(object) {
			Set props = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, Type FROM %Dictionary.CompiledProperty WHERE parent = ? AND Private = 0 AND Calculated = 0 AND Transient = 0 AND MultiDimensional = 0 AND Relationship = 0 ORDER BY SequenceNumber", bodyClass)
			While props.%Next() {
				Set name = props.%Get("Name")
				If ##class(%Dictionary.CompiledProperty).%OpenId(bodyClass_"||"_name).Collection '= "" Continue
				Set type = ##class(%Dictionary.CompiledClass).%OpenId(props.%Get("Type"))
				If '$IsObject(type) || (type.ClassType '= "datatype") Continue
				Set text = text _ name _ "=" _ $Property(object, name) _ $Char(31)
			}
		}
	} Catch {
		Set text = "unreadable"
	}
	Quit text
}

/// The definition of the production in the current namespace as text: its XML export, or "unreadable" when it cannot be exported.
ClassMethod DefinitionOf(name As %String) As %String [ Private ]
{
	Set production = ##class(Ens.Config.Production).%OpenId(name)
	If '$IsObject(production) Quit ""
	If $$$ISERR(production.XMLExportToString(.xml)) Quit "unreadable"
	Quit xml
}

/// One line per difference between the snapshots (see the class description), as a dynamic array of strings.
ClassMethod Diff(before As %DynamicObject, after As %DynamicObject, allowedSessions As %String = "", allowedIn As %String = {$Namespace}) As %DynamicArray
{
	Set lines = []
	Set iterator = before.%GetIterator()
	While iterator.%GetNext(.namespace, .was) {
		Set now = after.%Get(namespace)
		If '$IsObject(now) {
			Do lines.%Push(namespace_" is missing after")
			Continue
		}
		For category = "headers", "productions", "state", "defaults", "queues" {
			Do ..DiffCategory(namespace, category, was.%Get(category), now.%Get(category), $Select(namespace = allowedIn: allowedSessions, 1: ""), lines)
		}
	}
	Quit lines
}

ClassMethod DiffCategory(namespace As %String, category As %String, was As %DynamicObject, now As %DynamicObject, allowedSessions As %String, lines As %DynamicArray) [ Private ]
{
	Kill pending, wakeups
	If (category = "headers") && (namespace = ..#ALARMIN) Do ..PendingTimers(was, .pending, .wakeups)
	Set iterator = was.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		If 'now.%IsDefined(key) {
			Do lines.%Push(namespace_" "_category_" "_key_" is missing after")
		} ElseIf now.%Get(key) '= value {
			If $Data(pending(key)) Continue
			Do lines.%Push(namespace_" "_category_" "_key_" changed")
		}
	}
	Kill allowed
	If category = "headers" {
		Set iterator = now.%GetIterator()
		While iterator.%GetNext(.key, .value) {
			If was.%IsDefined(key) Continue
			If ..Column($Piece(value, $Char(30), 1), "SourceConfigName") = ..#HEARTBEAT Set allowed(..Column($Piece(value, $Char(30), 1), "SessionId")) = ""
		}
	}
	Set iterator = now.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		If was.%IsDefined(key) Continue
		If category = "headers" {
			Set columns = $Piece(value, $Char(30), 1)
			Set session = ..Column(columns, "SessionId")
			If $ListFind($ListFromString(allowedSessions), session) || $Data(allowed(session)) Continue
			If (..Column(columns, "SourceConfigName") = ..#ALARM) && ($Get(wakeups(session)) > 0) {
				Set wakeups(session) = wakeups(session) - 1
				Continue
			}
			Do lines.%Push(namespace_" header "_key_" is new: session "_session_", from "_..Column(columns, "SourceConfigName")_" to "_..Column(columns, "TargetConfigName"))
		} Else {
			Do lines.%Push(namespace_" "_category_" "_key_" is new")
		}
	}
}

/// The timers that were running in "before": pending(header id) for each request to ALARM whose status was Created, Queued or Delivered (any other value, final or
/// not a status, is no running timer), and wakeups(session), the number of such requests of the session (each may be followed by one wake-up header from ALARM).
ClassMethod PendingTimers(was As %DynamicObject, ByRef pending, ByRef wakeups) [ Private ]
{
	Set iterator = was.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		Set columns = $Piece(value, $Char(30), 1)
		If ..Column(columns, "TargetConfigName") '= ..#ALARM Continue
		If '$ListFind($ListBuild($$$eMessageStatusCreated, $$$eMessageStatusQueued, $$$eMessageStatusDelivered), +..Column(columns, "Status")) Continue
		Set pending(key) = ""
		Set session = ..Column(columns, "SessionId")
		If session = "" Continue
		Set wakeups(session) = $Get(wakeups(session)) + 1
	}
}

/// A column of a header row as Take keeps it (the values of SELECT * joined by the unit separator): looked up by the column's place in Ens.MessageHeader's SQL
/// columns.
ClassMethod Column(columns As %String, name As %String) As %String [ Private ]
{
	If '$Data(^||ZzSnapshotColumns) {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 * FROM Ens.MessageHeader")
		Set metadata = rs.%GetMetadata()
		For i = 1:1:rs.%ResultColumnCount Set ^||ZzSnapshotColumns($ZConvert(metadata.columns.GetAt(i).colName, "U")) = i
		Set ^||ZzSnapshotColumns = 1
	}
	Set i = +$Get(^||ZzSnapshotColumns($ZConvert(name, "U")))
	If 'i Quit ""
	Quit $Piece(columns, $Char(31), i)
}

}
