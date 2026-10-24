/// AgentSteps, the business operation that records the agent steps of a turn for Visual Trace (AD-6, AD-9, AD-33). Decide sends one
/// OcuTalon.Bridge.Msg.AgentStep for each step of a turn, in order, in the caller's trace session; the message in Visual Trace is
/// the record, so the operation answers an AgentStep with OK and no response. Any other message class gets "not implemented".
Class OcuTalon.Bridge.Operation.Steps Extends Ens.BusinessOperation
{

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Set pResponse = ""
	If $IsObject(pRequest) && pRequest.%IsA("OcuTalon.Bridge.Msg.AgentStep") Quit $$$OK
	Quit $$$ERROR($$$NotImplemented)
}

}
