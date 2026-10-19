/// The agent runner (AD-6): one business operation per agent, TriageAgent, DiagnosisAgent and ChatAgent, all of this
/// class. Each names its agent class in the AgentClass setting of its adapter. A stub until Story 1.2: it answers "not
/// implemented", and its adapter starts with no model key.
Class OcuTalon.Bridge.Operation.AgentRunner Extends Ens.BusinessOperation
{

Parameter ADAPTER = "OcuTalon.Bridge.Adapter.Agent";

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Property Adapter As OcuTalon.Bridge.Adapter.Agent;

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

/// The model that the runner item uses (AD-7): the Model setting of its adapter, on the item or in the System Default
/// Settings; when that is empty, the MODEL parameter of the AgentClass setting if that class extends %AI.Agent;
/// otherwise "". An empty production is the active production of the namespace. Reads the production definition, so no
/// production needs to be running when the production is named, and calls nothing in AI Hub.
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
