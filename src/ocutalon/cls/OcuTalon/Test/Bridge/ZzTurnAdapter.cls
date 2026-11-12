/// The runner's adapter of the per-request tool tests (Story 19.5; AD-6, AD-31): it attaches the toolset OcuTalon.Test.Bridge.ZzTurnToolset in
/// OnAfterAgentInit, through Attach, and notes in ^||ZzTurn("config", n) what each session config it composes finds: the class of the authorization and of
/// the audit policy of the agent's tool manager, whether that manager is not the one the agent was built with (the manager of the request), and the names of
/// the tools it discovers, then the names of those whose source is mcp. AttachedCount gives the number of specs that Attach has recorded (AttachedSpecs, the specs), and TwoConfigs composes the session config twice for one request (ComposeTwice, for an agent that is built already).
/// OpenTurn composes the session config once for a request of the kind turn of the owner and leaves the request's tools in place, with the context that the caller began
/// (Story 22.8): CallTool then runs a tool of the request's tool manager through the gate, and CloseTurn ends the request's tools. CallTool answers <OK> for a call
/// that ran and the text of the error status of AI Hub for a call that did not (a denial of the gate carries its sentence).
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

/// Opens the tools of a request of the kind turn of the owner (see the class description) for the agent that is built already. The status is that of the composition.
Method OpenTurn(owner As %String) As %Status
{
	Set ..TurnOwner = owner
	Set ..TurnKind = "turn"
	Set ..TurnComposed = 0
	Set ..TurnOpen = 1
	Quit ..SessionConfigFor(.config)
}

/// Builds the turn's MCP map and runs the turn-start check (MapMcpTools) on the manager that the agent has now, with the context that the caller began.
Method MapOwn()
{
	Do ..MapMcpTools()
}

/// Runs the tool of the request's tool manager with the arguments: <OK> when it ran, else the text of the error.
Method CallTool(name As %String, arguments As %DynamicObject = {{}}) As %String
{
	Try {
		Do ..Agent.ToolManager.ExecuteTool(name, arguments)
		Return "<OK>"
	} Catch exception {
		Return $SYSTEM.Status.GetErrorText(##class(%AI.System).HandleError(exception, 1))
	}
}

/// Ends the tools of the request that OpenTurn composed.
Method CloseTurn()
{
	Do ..EndTurnTools()
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
