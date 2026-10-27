/// Tests of the cross-lane API stubs of Lane A that are left (Story 0.6, matrix row 9): each stub answers what the architecture says a
/// caller sees until its owner builds it. No Approval stub is left (Story 3.5 built the last of them; Test.Bridge.Approval pins the
/// API). Nothing is written anywhere.
///   - TestNeutralValues: Keys.Status of an item that is not in the production (Keys.Status is no stub since Story 1.6; Test.Bridge.Keys
///     pins it), Timeouts.Derive of a timer that is refused (Derive is no stub since Story 1.7; Test.Bridge.Timeouts pins it), Agent.Input.Render of an empty Item (which renders "" since Story 1.3);
///     Checks.Render is no stub since Story 5.7 (Test.Checks.Render pins it), and neither is Budget.State since Story 1.4 (Test.Bridge.Budget pins it);
///   - TestStubAdapter: the runners' adapter extends AI Hub's outbound agent adapter and overrides its OnInit, which builds
///     the agent at start, so that a runner starts with no model key (the adapter builds the agent on the first request instead),
///     and the runner class carries no STUB.
Class OcuTalon.Test.Bridge.Api Extends %UnitTest.TestCase
{

/// Keys.Status of an item that is not in the production is 0 (Test.Bridge.Keys pins the rest); Timeouts.Derive(111) is {} (the rest of Derive is no stub:
/// Test.Bridge.Timeouts); Agent.Input.Render of an empty Item gives "" (the rule of its renderer: an Item
/// with no text renders nothing). Checks.Render is no stub since Story 5.7 (Test.Checks.Render pins it), and Budget.State is not here: it is implemented
/// (Story 1.4) and Test.Bridge.Budget pins it.
Method TestNeutralValues()
{
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Keys).Status("ZzNoSuchItem"), 0, "Keys.Status of an item that is not in the production is 0")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Timeouts).Derive(111).%ToJSON(), "{}", "Timeouts.Derive of a timer that Check refuses is an empty object")
	Do $$$AssertEquals(##class(OcuTalon.Agent.Input).Render(##class(OcuTalon.Msg.Item).%New()), "", "Agent.Input.Render gives an empty string")
}

/// The runners' adapter is a subclass of AI Hub's outbound agent adapter whose OnInit is its own (AI Hub's builds the agent
/// at start and needs a model key), and the runner item names it as its adapter. The runner class carries no STUB.
Method TestStubAdapter()
{
	Set adapter = "OcuTalon.Bridge.Adapter.Agent"
	Do $$$AssertTrue($ClassMethod(adapter, "%Extends", "EnsLib.AI.Agent.OutboundAdapter"), "the adapter extends AI Hub's outbound agent adapter")
	Set method = ##class(%Dictionary.CompiledMethod).%OpenId(adapter_"||OnInit")
	Do $$$AssertTrue($IsObject(method), "OnInit is compiled in the adapter")
	If $IsObject(method) Do $$$AssertEquals(method.Origin, adapter, "OnInit is the adapter's own, not AI Hub's")
	Do $$$AssertEquals($Parameter("OcuTalon.Bridge.Operation.AgentRunner", "ADAPTER"), adapter, "the runner item names the adapter")
	Do $$$AssertEquals($Parameter("OcuTalon.Bridge.Operation.AgentRunner", "STUB"), "", "and the runner class carries no STUB")
}

}
