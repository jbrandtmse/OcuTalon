/// A snapshot of what a fix could change in namespaces (Story 7.1; the helper of the "nothing changed" tests; Stories 7.3 and 7.4 reuse it). It has no Test methods.
///   - Take(namespaces) first waits up to WAITQUEUES seconds for every queue of every namespace to be empty, then reads, in each namespace: every Ens.MessageHeader
///     row (all columns) with the stored properties of its body; each production definition (its description, settings, items and their settings), the production's
///     state, and every Ens_Config.DefaultSettings row; and the queue counts (Ens.Queue_Enumerate()). The snapshot is a dynamic object, one member per namespace,
///     each with the members headers, productions, state, defaults and queues, keyed by id or name, whose values are text;
///   - Diff(before, after, allowedSessions) gives one line per changed or missing item, and per new item: a new header is left out when its SessionId is one of
///     allowedSessions (a comma-separated list: the session of the request the test sent, which its answer shares) or when its session is one that a new HeartbeatIn header
///     started (a scheduled tick of the home namespace, with whatever it sends on). The lines are given as a dynamic array of strings, empty when nothing changed.
/// It only reads, and it switches namespace only in a method that calls nothing but Ens, %SQL and dictionary classes there.
Class OcuTalon.Test.Fix.Snapshot
{

/// The longest wait for empty queues, in seconds.
Parameter WAITQUEUES = 10;

/// The source of a scheduled tick, whose new headers Diff allows.
Parameter HEARTBEAT = "HeartbeatIn";

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
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Count FROM Ens.Queue_Enumerate()")
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
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT * FROM Ens.MessageHeader ORDER BY ID")
	Set columns = rs.%ResultColumnCount
	While rs.%Next() {
		Set row = ""
		For i = 1:1:columns Set row = row _ rs.%GetData(i) _ $Char(31)
		Set id = rs.%Get("ID")
		Set bodyClass = rs.%Get("MessageBodyClassName")
		Do taken.headers.%Set(id, $Piece(row, $Char(31), 1, columns) _ $Char(30) _ ..BodyOf(bodyClass, rs.%Get("MessageBodyId")))
	}
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Ens_Config.Production")
	While rs.%Next() {
		Set name = rs.%GetData(1)
		Do taken.productions.%Set(name, ..DefinitionOf(name))
	}
	Set pname = ""
	Set pstate = ""
	Do ##class(Ens.Director).GetProductionStatus(.pname, .pstate)
	Do taken.state.%Set("production", $Get(pname) _ ":" _ $Get(pstate))
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT * FROM Ens_Config.DefaultSettings ORDER BY ID")
	Set columns = rs.%ResultColumnCount
	While rs.%Next() {
		Set row = ""
		For i = 1:1:columns Set row = row _ rs.%GetData(i) _ $Char(31)
		Do taken.defaults.%Set(rs.%Get("ID"), row)
	}
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, Count FROM Ens.Queue_Enumerate()")
	While rs.%Next() {
		Do taken.queues.%Set(rs.%GetData(1), rs.%GetData(2))
	}
	Quit taken
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

/// The definition of the production in the current namespace as text: its description and settings, and each item with its class, pool size, enabled flag and settings.
ClassMethod DefinitionOf(name As %String) As %String [ Private ]
{
	Set production = ##class(Ens.Config.Production).%OpenId(name)
	If '$IsObject(production) Quit ""
	Set text = "description=" _ production.Description
	For i = 1:1:production.Settings.Count() {
		Set setting = production.Settings.GetAt(i)
		Set text = text _ $Char(31) _ "setting " _ setting.Target _ "/" _ setting.Name _ "=" _ setting.Value
	}
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		Set text = text _ $Char(31) _ "item " _ item.Name _ " class=" _ item.ClassName _ " pool=" _ item.PoolSize _ " enabled=" _ item.Enabled _ " category=" _ item.Category
		For j = 1:1:item.Settings.Count() {
			Set setting = item.Settings.GetAt(j)
			Set text = text _ $Char(31) _ "item " _ item.Name _ " setting " _ setting.Target _ "/" _ setting.Name _ "=" _ setting.Value
		}
	}
	Quit text
}

/// One line per difference between the snapshots (see the class description), as a dynamic array of strings.
ClassMethod Diff(before As %DynamicObject, after As %DynamicObject, allowedSessions As %String = "") As %DynamicArray
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
			Do ..DiffCategory(namespace, category, was.%Get(category), now.%Get(category), allowedSessions, lines)
		}
	}
	Quit lines
}

ClassMethod DiffCategory(namespace As %String, category As %String, was As %DynamicObject, now As %DynamicObject, allowedSessions As %String, lines As %DynamicArray) [ Private ]
{
	Set iterator = was.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		If 'now.%IsDefined(key) {
			Do lines.%Push(namespace_" "_category_" "_key_" is missing after")
		} ElseIf now.%Get(key) '= value {
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
			Do lines.%Push(namespace_" header "_key_" is new: session "_session_", from "_..Column(columns, "SourceConfigName")_" to "_..Column(columns, "TargetConfigName"))
		} Else {
			Do lines.%Push(namespace_" "_category_" "_key_" is new")
		}
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
