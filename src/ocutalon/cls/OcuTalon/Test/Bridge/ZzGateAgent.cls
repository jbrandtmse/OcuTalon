/// The agent of the gate tests (Story 3.2; AD-6, AD-10): a test fixture, never part of a production. It has the toolset of the gate tests, so
/// that a request with the marker gate-risky, gate-safe or gate-throw makes the CI mock call zz_gate_risky, zz_gate_safe or zz_gate_throw.
/// Test.Bridge.Gate builds it in a shadow runner.
Class OcuTalon.Test.Bridge.ZzGateAgent Extends %AI.Agent
{

/// The model of the agent.
Parameter MODEL = "claude-haiku-5-5";

/// The toolset of the gate tests.
Parameter TOOLSETS = "OcuTalon.Test.Bridge.ZzGateTools";

/// The ceiling on the iterations of one turn: AI Hub's own property, as on OcuTalon.Agent.Chat. The runner puts it in the session config.
Property MaxIterations As %Integer [ InitialExpression = 4 ];

/// The static system prompt. It holds no template token (AD-7).
XData INSTRUCTIONS [ MimeType = text/markdown ]
{
You are a test fixture of OcuTalon. When you are asked to try a gate test tool, call the tool the request names, and then say what happened.
}

}
