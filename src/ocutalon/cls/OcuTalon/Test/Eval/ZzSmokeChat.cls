/// The chat agent of the thinking-history smoke test (Test.Eval.ThinkingSmoke; Story 30.1, AD-20) with the reminder tools alone: OcuTalon.Agent.Chat without
/// the watch tools, so that the tool list of the second turn differs from the first's. Nothing else differs from Chat. A test fixture, never part of a
/// production.
Class OcuTalon.Test.Eval.ZzSmokeChat Extends OcuTalon.Agent.Chat
{

Parameter TOOLSETS = "OcuTalon.Tools.Reminders";

}
