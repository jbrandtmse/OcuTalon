/// The runner's adapter of the step tests of Test.Bridge.Runner (Story 19.5; AD-6, AD-9): the tool manager that serves a request may be a new one that the
/// adapter composed for that request (a TurnToolsClass that gives a tool), so a test cannot read or change the manager of the built agent and expect the request
/// to use it. This adapter extends Govern, which the adapter runs on every manager that serves a request, so that
///   - with the node ^||ZzStepsSecond set, it chains the test-only audit policy OcuTalon.Test.Bridge.StepsSeen after the step audit policy on every manager;
///   - SessionConfigFor notes the size of the JSON of the tool catalog that the request's manager discovers in ^||ZzStepsBase, the figure the runner's base of
///     the step estimates holds.
/// Nothing else differs from the adapter.
Class OcuTalon.Test.Bridge.ZzStepsAdapter Extends OcuTalon.Bridge.Adapter.Agent
{

Method Govern(manager As %AI.ToolMgr) As %Status [ Private ]
{
	Set sc = ##super(manager)
	If $$$ISOK(sc) && $Get(^||ZzStepsSecond) Set sc = manager.SetAuditPolicy(##class(OcuTalon.Test.Bridge.StepsSeen).%New())
	Quit sc
}

Method SessionConfigFor(Output config As %DynamicObject) As %Status
{
	Set sc = ##super(.config)
	If $$$ISOK(sc) Set ^||ZzStepsBase = $Length(..Agent.ToolManager.%Discover().%ToJSON())
	Quit sc
}

}
