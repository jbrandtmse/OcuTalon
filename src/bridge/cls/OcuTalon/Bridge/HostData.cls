/// The members of the bridge context's HostData (AD-31), the JSON object that a tool may fill and that the reply carries to the host: checks from
/// check_status, memories from search_memories, citations from the documents search (OcuTalon.Bridge.Citations, Story 19.4). HostData is shared by the tools
/// and policies of a turn, so one puts a member without losing the others. OcuTalon.Tools.HostData delegates here (Story 19.4 moved the bodies here,
/// because the bridge's own policies call them and a bridge class cannot name a host class).
///   - Put sets one member. A HostData that is a JSON object keeps its other members; any other HostData (empty, not JSON, or JSON that is not an
///     object) becomes an object that holds the member alone. It returns the status of the context's Put, so it is an error when there is no context.
///   - Get returns the member as a dynamic value, or "" when HostData has no such member or is not a JSON object.
///   - Merge returns a HostData JSON text with the members of a dynamic object set (pure: it needs no context, so Decide can use it). A member
///     replaces one of the same name and the other members stay. A json that is empty or not a JSON object counts as an empty object, and an empty
///     or non-object members returns json unchanged.
///   - Remove takes one member out and keeps the others; a HostData without the member is left as it is, and the answer is then OK, also with no context.
/// It runs inside AI Hub's callbacks, so it makes no AI Hub call and no Python call (AD-6).
Class OcuTalon.Bridge.HostData
{

/// Sets the member of the context's HostData to the value (a dynamic object, array or string), keeping the other members. See the class description.
ClassMethod Put(member As %String, value As %DynamicAbstractObject) As %Status
{
	Set data = ..Object()
	Do data.%Set(member, value)
	Quit ##class(OcuTalon.Bridge.Context).Put("HostData", data.%ToJSON())
}

/// The member of the context's HostData, or "" when there is none. See the class description.
ClassMethod Get(member As %String) As %DynamicAbstractObject
{
	Quit ..Object().%Get(member)
}

/// Removes the member from the context's HostData, keeping the other members. See the class description.
ClassMethod Remove(member As %String) As %Status
{
	Set data = ..Object()
	If 'data.%IsDefined(member) Quit $$$OK
	Do data.%Remove(member)
	Quit ##class(OcuTalon.Bridge.Context).Put("HostData", data.%ToJSON())
}

/// The JSON text of json (a HostData value) with each member of members set. See the class description.
ClassMethod Merge(json As %String, members As %DynamicObject) As %String
{
	If '$IsObject(members) || 'members.%IsA("%Library.DynamicObject") || (members.%Size() = 0) Quit json
	Set data = {}
	If json '= "" {
		Try {
			Set parsed = {}.%FromJSON(json)
			If $IsObject(parsed) && parsed.%IsA("%Library.DynamicObject") Set data = parsed
		} Catch exception {
			Set data = {}
		}
	}
	Set iterator = members.%GetIterator()
	While iterator.%GetNext(.name, .value, .type) {
		If (type = "object") || (type = "array") {
			Do data.%Set(name, value)
		} Else {
			Do data.%Set(name, value, type)
		}
	}
	Quit data.%ToJSON()
}

/// The context's HostData as a dynamic object: the JSON object it holds, else an empty object.
ClassMethod Object() As %DynamicObject [ Private ]
{
	Set data = {}
	Set context = ##class(OcuTalon.Bridge.Context).Current()
	If $IsObject(context) && (context.HostData '= "") {
		Try {
			Set parsed = {}.%FromJSON(context.HostData)
			If $IsObject(parsed) && parsed.%IsA("%Library.DynamicObject") Set data = parsed
		} Catch exception {
			Set data = {}
		}
	}
	Quit data
}

}
