/// The agent of the replay tests (Story 30.3; AD-6, AD-10): a test fixture, never part of a production. It has the toolset of the replay tests only
/// (a new tool on ZzGateAgent would change the gate tests' agent). Test.Bridge.Runner builds it in a shadow runner, and Test.Bridge.Approval puts it
/// behind the production's ChatAgent item for the live replay tests (RunnerFixture UseAgent). The replay makes no model request, so it has no
/// scripted marker.
Class OcuTalon.Test.Bridge.ZzReplayAgent Extends %AI.Agent
{

/// The model of the agent.
Parameter MODEL = "claude-haiku-5-5";

/// The toolset of the replay tests.
Parameter TOOLSETS = "OcuTalon.Test.Bridge.ZzReplayTools";

/// The ceiling on the iterations of one turn: AI Hub's own property, as on OcuTalon.Agent.Chat.
Property MaxIterations As %Integer [ InitialExpression = 4 ];

/// The static system prompt. It holds no template token (AD-7).
XData INSTRUCTIONS [ MimeType = text/markdown ]
{
You are a test fixture of OcuTalon. You never call a tool yourself: the tools of this agent are replayed by the bridge.
}

}
