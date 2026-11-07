/// An agent runner whose adapter is OcuTalon.Test.Eval.ZzSmokeAdapter, for Test.Eval.ThinkingSmoke. Nothing else differs from the runner.
Class OcuTalon.Test.Eval.ZzSmokeRunner Extends OcuTalon.Bridge.Operation.AgentRunner
{

Parameter ADAPTER = "OcuTalon.Test.Eval.ZzSmokeAdapter";

/// Answers as the runner does, then accepts the reply of a linked turn as Decide would accept an on-time one (Story 17.8: only Decide moves a link, and this
/// smoke drives the runner without Decide): Test.Bridge.Runner Accept points the link at the session the reply names and sets its SessionRotated.
Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Set sc = ##super(pRequest, .pResponse)
	If $$$ISOK(sc) && $IsObject(pRequest) && pRequest.%IsA("OcuTalon.Bridge.Msg.Request") && $IsObject(pResponse) && pResponse.%IsA("OcuTalon.Bridge.Msg.Reply") && ##class(OcuTalon.Bridge.Adapter.Agent).IsLinked(pRequest) {
		Do ##class(OcuTalon.Test.Bridge.Runner).Accept(pRequest, pResponse, ..%ConfigName)
	}
	Quit sc
}

}
