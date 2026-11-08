/// The TurnToolsClass of the per-request tool tests (Story 19.5; AD-31): a test fixture, never part of a production. Tools gives one holder when the node
/// ^OcuTalonTest("TurnTools", "give") is 1, whose AddToManager registers the toolset OcuTalon.Test.Bridge.ZzTurnProbeTools (the tool zz_turn_probe), and none
/// otherwise. It notes each call in ^||ZzTurn("calls") (the process-private node of the test), with the OwnerRef and the kind of the last one.
Class OcuTalon.Test.Bridge.ZzTurnTools Extends (OcuTalon.Bridge.Ext.TurnTools, %RegisteredObject)
{

ClassMethod Tools(ownerRef As %String, kind As %String, Output tools As %ListOfObjects) As %Status
{
	Set tools = ##class(%ListOfObjects).%New()
	Set ^||ZzTurn("calls") = $Get(^||ZzTurn("calls")) + 1
	Set ^||ZzTurn("last") = ownerRef _ "|" _ kind
	If $Get(^OcuTalonTest("TurnTools", "give")) = 1 Do tools.Insert(..%New())
	Quit $$$OK
}

/// Adds the tool of the request, as AI Hub's knowledge base adds its own.
Method AddToManager(manager As %AI.ToolMgr) As %Status
{
	Quit manager.RegisterToolSet("OcuTalon.Test.Bridge.ZzTurnProbeTools")
}

}
