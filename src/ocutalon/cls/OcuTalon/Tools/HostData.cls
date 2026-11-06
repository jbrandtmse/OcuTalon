/// The members of the bridge context's HostData (AD-31), the JSON object that a tool may fill and that the reply carries to the host: checks from
/// check_status, memories from search_memories, citations from the documents tool (Story 19.4). HostData is shared by the tools of a turn, so a
/// tool puts one member without losing the others.
///   - Put sets one member. A HostData that is a JSON object keeps its other members; any other HostData (empty, not JSON, or JSON that is not an
///     object) becomes an object that holds the member alone. It returns the status of the context's Put, so it is an error when there is no context.
///   - Get returns the member as a dynamic value, or "" when HostData has no such member or is not a JSON object.
/// A tool method runs inside AI Hub's callback, so this class makes no AI Hub call and no Python call (AD-6).
Class OcuTalon.Tools.HostData
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
