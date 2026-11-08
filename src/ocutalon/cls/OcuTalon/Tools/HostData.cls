/// The members of the bridge context's HostData (AD-31), the JSON object that a tool may fill and that the reply carries to the host: checks from
/// check_status, memories from search_memories, citations from the documents tool (Story 19.4). HostData is shared by the tools of a turn, so a
/// tool puts one member without losing the others.
///   - Put sets one member. A HostData that is a JSON object keeps its other members; any other HostData (empty, not JSON, or JSON that is not an
///     object) becomes an object that holds the member alone. It returns the status of the context's Put, so it is an error when there is no context.
///   - Get returns the member as a dynamic value, or "" when HostData has no such member or is not a JSON object.
///   - Remove takes one member out and keeps the others; a HostData without the member is left as it is, and the answer is then OK, also with no context.
/// A tool method runs inside AI Hub's callback, so this class makes no AI Hub call and no Python call (AD-6). Story 19.4 moved the bodies into
/// OcuTalon.Bridge.HostData, which the bridge's own policies (OcuTalon.Bridge.Citations) call; each method here delegates to it.
Class OcuTalon.Tools.HostData
{

/// Sets the member of the context's HostData to the value (a dynamic object, array or string), keeping the other members. See the class description.
ClassMethod Put(member As %String, value As %DynamicAbstractObject) As %Status
{
	Quit ##class(OcuTalon.Bridge.HostData).Put(member, value)
}

/// The member of the context's HostData, or "" when there is none. See the class description.
ClassMethod Get(member As %String) As %DynamicAbstractObject
{
	Quit ##class(OcuTalon.Bridge.HostData).Get(member)
}

/// Removes the member from the context's HostData, keeping the other members. See the class description.
ClassMethod Remove(member As %String) As %Status
{
	Quit ##class(OcuTalon.Bridge.HostData).Remove(member)
}

}
