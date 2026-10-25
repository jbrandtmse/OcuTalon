/// The agent of the context probe (Story 1.2; AD-6, AD-7): a test fixture, never part of a production. It has the toolset of the
/// probe, so that a request with the marker context-probe makes the CI mock call the tool zz_context_probe. Its Temperature is set
/// before the build, to show that the runner's adapter clears it.
Class OcuTalon.Test.Bridge.ProbeAgent Extends %AI.Agent
{

/// The model of the agent.
Parameter MODEL = "claude-haiku-5-5";

/// The toolset of the probe.
Parameter TOOLSETS = "OcuTalon.Test.Bridge.ProbeTools";

/// A temperature that would reach the provider, if the adapter did not clear it.
Property Temperature As %Float [ InitialExpression = 0.7 ];

/// The static system prompt. It holds no template token (AD-7).
XData INSTRUCTIONS [ MimeType = text/markdown ]
{
You are a test fixture of OcuTalon. When you are asked to run the probe, call the tool zz_context_probe once, and then say that the probe ran.
}

}
