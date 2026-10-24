/// The agent runner (AD-6): one business operation per agent, TriageAgent, DiagnosisAgent and ChatAgent, all of this
/// class. Each names its agent class in the AgentClass setting of its adapter, and its pool size is its concurrency cap: the
/// runners are the only code that calls Chat. A Request gets a Reply (the adapter's Answer): the reply of the call, or, when Chat
/// threw, a failure Reply that holds the redacted failure text and the steps of the call, so that Decide classifies the failure and
/// still sends the steps (DW-83). An error before Chat keeps its error status. A turn of a conversation that another turn still holds
/// (the conversation lock, Data.ConversationLink) is answered, after the lock's 2 seconds, with a Reply whose Busy is 1 and nothing
/// else set, and a status OK: Decide relays it as its own Busy answer (AD-6). A ToolInventory request gets
/// an Ens.StringResponse that holds the JSON of the live ToolManager's tools. Any other message class gets "not implemented"
/// and no response. Its ReplyClass setting names the %JSON.Adaptor class that Decide checks the runner's reply against
/// (AD-7); the runner itself never reads it.
Class OcuTalon.Bridge.Operation.AgentRunner Extends Ens.BusinessOperation
{

Parameter ADAPTER = "OcuTalon.Bridge.Adapter.Agent";

Parameter SETTINGS = "ReplyClass:Basic";

Property Adapter As OcuTalon.Bridge.Adapter.Agent;

/// The compiled %JSON.Adaptor class that Decide checks this runner's reply against, for a decide or diagnose request
/// (OcuTalon.Bridge.Msg.DecisionPayload for Triage). Empty for a runner whose reply is text.
Property ReplyClass As %String(MAXLEN = 128);

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Set pResponse = ""
	If $IsObject(pRequest) && pRequest.%IsA("OcuTalon.Bridge.Msg.Request") {
		Set sc = ..Adapter.Answer(pRequest, ..%SuperSession, .reply)
		If $$$ISOK(sc) Set pResponse = reply
		Quit sc
	}
	If $IsObject(pRequest) && pRequest.%IsA("OcuTalon.Bridge.Msg.ToolInventory") {
		Set sc = ..Adapter.Inventory(.inventory)
		If $$$ISOK(sc) Set pResponse = ##class(Ens.StringResponse).%New(inventory.%ToJSON())
		Quit sc
	}
	Quit $$$ERROR($$$NotImplemented)
}

/// The model that the runner item uses (AD-7): the Model setting of its adapter, on the item or in the System Default
/// Settings; when that is empty, the MODEL parameter of the AgentClass setting if that class extends %AI.Agent;
/// otherwise "". An empty production is Ens.Director's active production: the running production, else the suspended
/// one, else the last one used in the namespace. Reads the production definition, so no production needs to be running
/// when the production is named, and calls nothing in AI Hub.
ClassMethod ResolveModel(item As %String, production As %String = "") As %String
{
	If production = "" Set production = ##class(Ens.Director).GetActiveProductionName()
	If production = "" Quit ""
	Set name = production_"||"_item
	Set model = ##class(Ens.Director).GetAdapterSettingValue(name, "Model", .sc)
	If $$$ISOK(sc), model '= "" Quit model
	Set agentClass = ##class(Ens.Director).GetAdapterSettingValue(name, "AgentClass", .sc)
	If $$$ISERR(sc) || (agentClass = "") Quit ""
	If '##class(%Dictionary.CompiledClass).%ExistsId(agentClass) Quit ""
	If '$ClassMethod(agentClass, "%Extends", "%AI.Agent") Quit ""
	Quit $Parameter(agentClass, "MODEL")
}

}
