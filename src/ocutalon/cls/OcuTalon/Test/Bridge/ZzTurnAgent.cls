/// The agent of the per-request tool tests (Story 19.5): a test fixture, never part of a production. It has the three read-only tools of
/// OcuTalon.Test.Bridge.StepsTools, so that the model requests of a turn offer them beside the tools that a request adds.
Class OcuTalon.Test.Bridge.ZzTurnAgent Extends %AI.Agent
{

Parameter MODEL = "claude-haiku-5-5";

Parameter TOOLSETS = "OcuTalon.Test.Bridge.StepsTools";

Property MaxIterations As %Integer [ InitialExpression = 4 ];

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
You are a test fixture of OcuTalon. When you are asked to run the turn probe, call the tool zz_turn_probe once, and then say that it ran.
}

}
