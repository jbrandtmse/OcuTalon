/// The agent of the tool result tests (Story 1.9; AD-10): a test fixture, never part of a production. It has the two tools of
/// OcuTalon.Test.Tools.ZzResultTools, so that a request with the marker result-cap makes the CI mock call them: the first response asks
/// for a text and an object of 30,000 characters each, and the second for a text of 1,000. Test.Tools.Result builds it in a shadow runner
/// (Test.Bridge.Runner NewRunner).
Class OcuTalon.Test.Tools.ZzResultAgent Extends %AI.Agent
{

/// The model of the agent.
Parameter MODEL = "claude-haiku-5-5";

/// The toolset of the tool result tests.
Parameter TOOLSETS = "OcuTalon.Test.Tools.ZzResultTools";

/// The ceiling on the iterations of one turn: AI Hub's own property, as on OcuTalon.Agent.Chat. The runner puts it in the session config.
Property MaxIterations As %Integer [ InitialExpression = 4 ];

/// The static system prompt. It holds no template token (AD-7).
XData INSTRUCTIONS [ MimeType = text/markdown ]
{
You are a test fixture of OcuTalon. When you are asked to read the results, call the tools zz_result_text and zz_result_object, and then say what they returned.
}

}
