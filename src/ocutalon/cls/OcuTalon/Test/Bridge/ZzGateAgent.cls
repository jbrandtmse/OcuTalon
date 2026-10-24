/// The agent of the gate tests (Story 3.2; AD-6, AD-10): a test fixture, never part of a production. It has the toolset of the gate tests, so
/// that a request with the marker gate-risky, gate-safe, gate-throw, gate-public or gate-admin makes the CI mock call zz_gate_risky, zz_gate_safe,
/// zz_gate_throw, zz_gate_public or zz_gate_admin. The toolset of Story 3.3 (ZzGateInjection) adds the markers gate-read and gate-trusted (one
/// call of zz_gate_read or zz_gate_trusted), gate-taint-then-act (zz_gate_read, then zz_change_endpoint in the next response),
/// gate-taint-parallel (both in one response), suspicious-act (zz_resend_failed, zz_change_endpoint and zz_approve_requests in one response)
/// and recall-tell (Test.Bridge.Conversation's scenario, which tells and calls no tool). Test.Bridge.Gate builds it in a shadow runner, and (TestPrivilegeInProductionRunnerJob) puts it behind
/// the production's ChatAgent item.
Class OcuTalon.Test.Bridge.ZzGateAgent Extends %AI.Agent
{

/// The model of the agent.
Parameter MODEL = "claude-haiku-5-5";

/// The toolsets of the gate tests: the governance sample and the injection tools.
Parameter TOOLSETS = "OcuTalon.Test.Bridge.ZzGateTools,OcuTalon.Test.Bridge.ZzGateInjection";

/// The ceiling on the iterations of one turn: AI Hub's own property, as on OcuTalon.Agent.Chat. The runner puts it in the session config.
Property MaxIterations As %Integer [ InitialExpression = 4 ];

/// The static system prompt. It holds no template token (AD-7).
XData INSTRUCTIONS [ MimeType = text/markdown ]
{
You are a test fixture of OcuTalon. When you are asked to try a gate test tool, call the tool the request names, and then say what happened.
}

}
