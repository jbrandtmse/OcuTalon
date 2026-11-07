/// An agent runner whose adapter is OcuTalon.Test.Bridge.ZzRetryAdapter, for Test.Bridge.Conversation (Story 17.2): a shadow runner that can be a retry runner
/// of the shadow runner ZzRunner, or a first runner whose save waits. Nothing else differs from the runner.
Class OcuTalon.Test.Bridge.ZzRetryRunner Extends OcuTalon.Bridge.Operation.AgentRunner
{

Parameter ADAPTER = "OcuTalon.Test.Bridge.ZzRetryAdapter";

}
