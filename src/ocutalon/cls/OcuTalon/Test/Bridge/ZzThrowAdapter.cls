/// The runner's adapter whose Converse raises, for Test.Bridge.Conversation: an exception inside the linked turn, after the AI session is made and
/// before any call, that Converse's own Try does not hold. Nothing else differs from the adapter.
Class OcuTalon.Test.Bridge.ZzThrowAdapter Extends OcuTalon.Bridge.Adapter.Agent
{

/// Raises, with the text "Converse raised".
Method Converse(request As OcuTalon.Bridge.Msg.Request, session As %AI.Agent.Session, input As %String, opened As %Boolean, Output reply As OcuTalon.Bridge.Msg.Reply, Output completed As %Boolean) As %Status [ Private ]
{
	Set reply = ""
	Set completed = 0
	Throw ##class(%Exception.General).%New("ZzThrow", 5001, "Converse", "Converse raised")
}

}
