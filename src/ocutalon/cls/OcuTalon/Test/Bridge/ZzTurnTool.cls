/// The tools of the per-request tool tests (Story 19.5; AD-6, AD-10, AD-31): a test fixture, never part of a production. Attached answers the tool
/// zz_turn_set (the toolset that the test adapter attaches when it builds its agent) and Probe the tool zz_turn_probe (the tool that the test TurnToolsClass
/// adds to one request). Both are safe and read-only, and each counts its calls in ^||ZzTurn("ran", <name>). A tool method runs inside AI Hub's callback, so it
/// makes no AI Hub call and no Python call (AD-6).
Class OcuTalon.Test.Bridge.ZzTurnTool Extends %AI.Tool
{

Parameter STEPLABEL = "Reading the turn fixture";

Parameter CLASSIFICATION = "safe";

Parameter READONLY = 1;

ClassMethod Attached(topic As %String = "") As %DynamicObject
{
	Set ^||ZzTurn("ran", "zz_turn_set") = $Get(^||ZzTurn("ran", "zz_turn_set")) + 1
	Quit {"tool": "zz_turn_set", "topic": (topic)}
}

ClassMethod Probe(topic As %String = "") As %DynamicObject
{
	Set ^||ZzTurn("ran", "zz_turn_probe") = $Get(^||ZzTurn("ran", "zz_turn_probe")) + 1
	Quit {"tool": "zz_turn_probe", "topic": (topic)}
}

}
