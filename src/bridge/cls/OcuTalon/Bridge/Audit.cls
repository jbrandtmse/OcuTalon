/// The only writer of the IRIS audit log, for the bridge and for OcuTalon (AD-17). It declares OcuTalon's
/// user-defined audit events; OcuTalon.Bridge.Installer registers them, and nothing here changes instance-wide auditing.
///   - Record(type, data) is the writer of product code. Every entry's data has the common members irisUser, sessionRef and channel (COMMON)
///     plus the one fixed set of members of its type (Shape), and no other member; Record refuses any other shape before it writes
///     anything. It builds the description from the shape, never from free text, blanks the from and to of a Settings entry whose setting
///     is sensitive, and writes through Write.
///   - Write is the raw writer under Record: it takes any dynamic object, passes the data's JSON and the description through
///     Redact.Text, and writes the entry. Product code calls Record.
/// An entry is readable in %SYS.Audit by its UTCTimeStamp at once, and by IRIS's audit indexes up to a minute later.
Class OcuTalon.Bridge.Audit
{

/// The source of every OcuTalon audit event.
Parameter SOURCE = "OcuTalon";

/// The event types. Each event is named OcuTalon/<type>/<type>.
Parameter TYPES = "Action,Approval,Pairing,Settings,MCP,Tool";

/// The members that every entry's data has.
Parameter COMMON = "irisUser,sessionRef,channel";

/// The members of each type, besides the common ones. In an Action, counts is an object whose values are numbers ({} when the action counts
/// nothing); in a Tool, readOnly is the number 0 or 1; every other value is a string.
Parameter SHAPEACTION = "action,target,result,counts,approvalRef";

Parameter SHAPEAPPROVAL = "ref,kind,change,from,to,outcome,target,ownerRef";

Parameter SHAPEPAIRING = "change,reason";

Parameter SHAPESETTINGS = "setting,from,to";

Parameter SHAPEMCP = "change,server";

Parameter SHAPETOOL = "source,tool,classification,readOnly";

/// The values of an Approval entry's change, a Pairing entry's change, an MCP entry's change and a Tool entry's classification.
Parameter APPROVALCHANGES = "answered,expired,cancelled,started,finished";

Parameter PAIRINGCHANGES = "linked,unlinked,rejected";

Parameter MCPCHANGES = "added,removed";

Parameter CLASSIFICATIONS = "safe,risky,unclassified";

/// The OwnerRef values that are not a Ref (an Approval entry's ownerRef).
Parameter OWNERNAMES = "instance,eval";

/// The names of the six events, as "OcuTalon/<type>/<type>", in the order of TYPES.
ClassMethod Events() As %List
{
	Set events = ""
	Set types = $ListFromString(..#TYPES)
	Set position = 0
	While $ListNext(types, position, type) {
		Set events = events _ $ListBuild(..#SOURCE_"/"_type_"/"_type)
	}
	Quit events
}

/// The members of the type's data: the type's own members followed by the common ones, as a list. "" for a type that is not in TYPES.
ClassMethod Shape(type As %String) As %List
{
	If '$ListFind($ListFromString(..#TYPES), type) Quit ""
	Quit $ListFromString($Parameter("OcuTalon.Bridge.Audit", "SHAPE" _ $ZConvert(type, "U")) _ "," _ ..#COMMON)
}

/// Writes one audit entry of the type, in the one shape of that type, and returns an error status that names the type and the member, and
/// never the value, when the data has any other shape: nothing is written then. The data is a dynamic object with every member of Shape(type)
/// and no other, each of the JSON type the Parameters above say, and with these values:
///   - irisUser, action, setting, server, source and tool are not empty; channel is one of Msg.Enum CHANNEL;
///   - sessionRef and approvalRef are empty or a 22-character Ref, an Approval's ref is a Ref, and its ownerRef is empty, a Ref, instance or eval;
///   - an Approval's kind is one of Msg.Enum APPROVALKIND, its from and to are of APPROVALSTATE, and its change is one of APPROVALCHANGES;
///   - a Pairing's change is one of PAIRINGCHANGES, an MCP's change one of MCPCHANGES, a Tool's classification one of CLASSIFICATIONS.
/// The description is built from the data: "<action>: <result>" (Action), "Approval <ref> <change>: <to>", "Pairing <change>",
/// "Setting <setting> changed", "MCP server <server> <change>" and "Tool <tool> of <source>: <classification>". A Settings entry whose
/// setting Redact.SensitiveKey flags is written with from and to replaced by Redact REDACTED; the caller's object is not changed.
/// The status is Write's.
ClassMethod Record(type As %String, data As %DynamicObject) As %Status
{
	Set problem = ..Problem(type, data)
	If problem '= "" {
		Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Audit.Record refuses the " _ $Extract(type, 1, 32) _ " entry: " _ problem)
	}
	Set copy = {}.%FromJSON(data.%ToJSON())
	If type = "Settings" && ##class(OcuTalon.Bridge.Redact).SensitiveKey(copy.setting) {
		Set copy.from = ##class(OcuTalon.Bridge.Redact).#REDACTED
		Set copy.to = ##class(OcuTalon.Bridge.Redact).#REDACTED
	}
	Quit ..Write(type, copy, ..Describe(type, copy))
}

/// The reason the data is not an entry of the type, naming the member and never its value, or "" when it is one.
ClassMethod Problem(type As %String, data As %DynamicObject) As %String [ Private ]
{
	If '$ListFind($ListFromString(..#TYPES), type) Quit "it is not an OcuTalon audit type"
	If '$IsObject(data) || ($ClassName(data) '= "%Library.DynamicObject") Quit "the data must be a dynamic object"
	Set members = ..Shape(type)
	Set iterator = data.%GetIterator()
	While iterator.%GetNext(.key) {
		If '$ListFind(members, key) Return "the member '" _ $Extract(key, 1, 32) _ "' is not in the shape"
	}
	Set position = 0
	While $ListNext(members, position, name) {
		Set problem = ..MemberProblem(type, name, data)
		If problem '= "" Return "the member '" _ name _ "' " _ problem
	}
	Quit ""
}

/// What is wrong with one member of the data (its JSON type, then its value), or "".
ClassMethod MemberProblem(type As %String, name As %String, data As %DynamicObject) As %String [ Private ]
{
	Set kind = data.%GetTypeOf(name)
	If kind = "unassigned" Quit "is missing"
	If (type = "Action") && (name = "counts") {
		If kind '= "object" Quit "must be an object"
		Set iterator = data.counts.%GetIterator()
		While iterator.%GetNext(.key, .value, .valueType) {
			If valueType '= "number" Return "must have only numbers as values"
		}
		Quit ""
	}
	If (type = "Tool") && (name = "readOnly") {
		Quit $Select(kind '= "number": "must be the number 0 or 1", (data.readOnly '= 0) && (data.readOnly '= 1): "must be the number 0 or 1", 1: "")
	}
	If kind '= "string" Quit "must be a string"
	Set value = data.%Get(name)
	Set channels = ##class(OcuTalon.Bridge.Msg.Enum).#CHANNEL
	If $ListFind($ListBuild("irisUser", "action", "setting", "server", "source", "tool"), name) {
		Quit $Select(value = "": "must not be empty", 1: "")
	}
	If name = "channel" Quit $Select('$ListFind($ListFromString(channels), value): "must be one of " _ channels, 1: "")
	If (name = "sessionRef") || (name = "approvalRef") {
		Quit $Select((value '= "") && '##class(OcuTalon.Bridge.Approval).IsRef(value): "must be empty or a 22-character Ref", 1: "")
	}
	If name = "ref" Quit $Select('##class(OcuTalon.Bridge.Approval).IsRef(value): "must be a 22-character Ref", 1: "")
	If name = "ownerRef" {
		Quit $Select((value '= "") && '##class(OcuTalon.Bridge.Approval).IsRef(value) && '$ListFind($ListFromString(..#OWNERNAMES), value): "must be empty, a 22-character Ref, " _ ..#OWNERNAMES, 1: "")
	}
	If name = "kind" {
		Set kinds = ##class(OcuTalon.Bridge.Msg.Enum).#APPROVALKIND
		Quit $Select('$ListFind($ListFromString(kinds), value): "must be one of " _ kinds, 1: "")
	}
	If (type = "Approval") && ((name = "from") || (name = "to")) {
		Set states = ##class(OcuTalon.Bridge.Msg.Enum).#APPROVALSTATE
		Quit $Select('$ListFind($ListFromString(states), value): "must be one of " _ states, 1: "")
	}
	If name = "change" {
		Set allowed = $Case(type, "Approval": ..#APPROVALCHANGES, "Pairing": ..#PAIRINGCHANGES, "MCP": ..#MCPCHANGES, : "")
		Quit $Select('$ListFind($ListFromString(allowed), value): "must be one of " _ allowed, 1: "")
	}
	If name = "classification" {
		Quit $Select('$ListFind($ListFromString(..#CLASSIFICATIONS), value): "must be one of " _ ..#CLASSIFICATIONS, 1: "")
	}
	Quit ""
}

/// The description of a valid entry, built from its members.
ClassMethod Describe(type As %String, data As %DynamicObject) As %String [ Private ]
{
	Quit $Case(type,
		"Action": data.action _ ": " _ data.result,
		"Approval": "Approval " _ data.ref _ " " _ data.change _ ": " _ data.to,
		"Pairing": "Pairing " _ data.change,
		"Settings": "Setting " _ data.setting _ " changed",
		"MCP": "MCP server " _ data.server _ " " _ data.change,
		"Tool": "Tool " _ data.tool _ " of " _ data.source _ ": " _ data.classification,
		: "")
}

/// Writes one audit entry of the given type, with the data's JSON as the entry's event data and the description cut at 128 bytes. This is the
/// raw writer under Record: it takes any dynamic object and checks no shape. It passes the data's JSON and the description through
/// Redact.Text first, and cuts the description after that, so a secret is never cut in two before it is recognised.
/// A type that is not in TYPES is refused with an error status that names it. Otherwise the status is a success when IRIS writes the entry.
/// When IRIS writes nothing it returns 0, and the status is an error that says so (measured on build 154: instance-wide auditing is off, or
/// the event is disabled or not registered). The entry is readable in %SYS.Audit by its UTCTimeStamp at once, and by IRIS's audit indexes
/// up to a minute later.
ClassMethod Write(type As %String, data As %DynamicObject, description As %String = "") As %Status
{
	If '$ListFind($ListFromString(..#TYPES), type) {
		Quit $SYSTEM.Status.Error(5001, "'"_type_"' is not an OcuTalon audit type")
	}
	If '$IsObject(data) || ($ClassName(data) '= "%Library.DynamicObject") {
		Quit $SYSTEM.Status.Error(5001, "The audit data must be a dynamic object")
	}
	Set eventData = ##class(OcuTalon.Bridge.Redact).Text(data.%ToJSON())
	Set text = $Extract(##class(OcuTalon.Bridge.Redact).Text(description), 1, 128)
	Set sc = $SYSTEM.Security.Audit(..#SOURCE, type, type, eventData, text)
	If sc = 1 Quit $$$OK
	If $ListValid(sc) Quit sc
	Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Audit.Write: no entry of type " _ type _ " was written: instance-wide auditing is off or the event is disabled or missing")
}

}
