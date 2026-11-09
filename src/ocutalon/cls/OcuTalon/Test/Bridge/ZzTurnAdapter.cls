/// The runner's adapter of the per-request tool tests (Story 19.5; AD-6, AD-31): it attaches the toolset OcuTalon.Test.Bridge.ZzTurnToolset in
/// OnAfterAgentInit, through Attach, and notes in ^||ZzTurn("config", n) what each session config it composes finds: the class of the authorization and of
/// the audit policy of the agent's tool manager, whether that manager is not the one the agent was built with (the manager of the request), and the names of
/// the tools it discovers, then the names of those whose source is mcp. AttachedCount gives the number of specs that Attach has recorded (AttachedSpecs, the specs), and TwoConfigs composes the session config twice for one request (ComposeTwice, for an agent that is built already).
/// While the node ^OcuTalonTest("TurnTools", "fail") is 1, SessionConfigFor fails after the adapter's composition has run, so that the request ends in an error
/// with the request's manager assigned. Nothing else differs from the adapter.
Class OcuTalon.Test.Bridge.ZzTurnAdapter Extends OcuTalon.Bridge.Adapter.Agent
{

Method OnAfterAgentInit(ByRef agent As %AI.Agent) As %Status [ Private ]
{
	Set sc = ##super(.agent)
	If $$$ISERR(sc) Quit sc
	Set ^||ZzTurn("built") = agent.ToolManager.%token
	Quit ..Attach(agent, "iris:OcuTalon.Test.Bridge.ZzTurnToolset")
}

/// The number of specs that Attach has recorded for the agent.
Method AttachedCount() As %Integer
{
	Quit $ListLength(..Attached)
}

/// The specs that Attach has recorded for the agent, as a list.
Method AttachedSpecs() As %List
{
	Quit ..Attached
}

/// Composes the session config twice for one request of the kind turn of the owner, as a request that compacts its history does, and ends the request's
/// tools. The status is the first error.
Method TwoConfigs(owner As %String) As %Status
{
	Set sc = ..BuildAgent()
	If $$$ISERR(sc) Quit sc
	Quit ..ComposeTwice(owner)
}

/// TwoConfigs for the agent that is already built: the tools attached when it was built are not attached again.
Method ComposeTwice(owner As %String) As %Status
{
	Set ..TurnOwner = owner
	Set ..TurnKind = "turn"
	Set ..TurnComposed = 0
	Set ..TurnOpen = 1
	Set sc = ..SessionConfigFor(.first)
	If $$$ISOK(sc) Set sc = ..SessionConfigFor(.second)
	Do ..EndTurnTools()
	Quit sc
}

Method SessionConfigFor(Output config As %DynamicObject) As %Status
{
	Set sc = ##super(.config)
	If $$$ISOK(sc) && ($Get(^OcuTalonTest("TurnTools", "fail")) = 1) Quit $$$ERROR($$$GeneralError, "ZzTurnAdapter fails the session config after the composition")
	If $$$ISOK(sc) {
		Set manager = ..Agent.ToolManager
		Set names = "", mcp = ""
		Set tools = manager.%Discover()
		For i = 0:1:tools.%Size() - 1 {
			Set names = names _ $Select(names = "": "", 1: ",") _ tools.%Get(i).name
			If tools.%Get(i).source = "mcp" Set mcp = mcp _ $Select(mcp = "": "", 1: ",") _ tools.%Get(i).name
		}
		Set n = $Increment(^||ZzTurn("config"))
		Set ^||ZzTurn("config", n) = manager.AuthPolicy.%ClassName(1) _ "|" _ manager.AuditPolicy.%ClassName(1) _ "|" _ (manager.%token '= ^||ZzTurn("built")) _ "|" _ names _ "|" _ mcp
	}
	Quit sc
}

}
