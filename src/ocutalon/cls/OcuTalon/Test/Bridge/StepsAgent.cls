/// The agent of the step tests (Story 1.5; AD-6, AD-9): a test fixture, never part of a production. It has the three read-only tools of
/// OcuTalon.Test.Bridge.StepsTools, so that a request with the marker steps-two-tools, steps-secrets or steps-secrets-text makes the CI
/// mock call them. The marker steps-loop calls zz_steps_note again and again until the agent's MaxIterations ends the turn, and the
/// marker cut-off-tool answers a tool call that the provider cut at the output cap (Story 1.6).
/// Test.Agent.Steps points the stored configuration of ChatAgent at it for its own run, and Test.Bridge.Runner builds it in a shadow
/// runner.
Class OcuTalon.Test.Bridge.StepsAgent Extends %AI.Agent
{

/// The model of the agent.
Parameter MODEL = "claude-haiku-5-5";

/// The toolset of the step tests.
Parameter TOOLSETS = "OcuTalon.Test.Bridge.StepsTools";

/// The ceiling on the iterations of one turn: AI Hub's own property, as on OcuTalon.Agent.Chat. The runner puts it in the session
/// config.
Property MaxIterations As %Integer [ InitialExpression = 4 ];

/// The static system prompt. It holds no template token (AD-7).
XData INSTRUCTIONS [ MimeType = text/markdown ]
{
You are a test fixture of OcuTalon. When you are asked to read the note and the card, call the tool zz_steps_note, then the tool zz_steps_card, and then say what they said.
}

}
