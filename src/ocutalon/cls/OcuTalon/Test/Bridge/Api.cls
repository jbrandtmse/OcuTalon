/// Tests of the cross-lane API stubs of Lane A (Story 0.6, matrix row 9): each stub answers what the architecture says a
/// caller sees until its owner builds it. A status method returns an error that says it is not implemented yet and names
/// the method; the others return their neutral value. Nothing is written anywhere.
///   - TestApprovalStubs: Raise, Expire, Cancel, StartExecution and FinishExecution; Answer answers not_found with an
///     empty winner;
///   - TestNeutralValues: Keys.Status of an item that is not in the production (Keys.Status is no stub since Story 1.6; Test.Bridge.Keys
///     pins it), Timeouts.Derive of a timer that is refused (Derive is no stub since Story 1.7; Test.Bridge.Timeouts pins it), Agent.Input.Render of an empty Item (which renders "" since Story 1.3) and
///     Checks.Render.Render (Budget.State is no stub since Story 1.4; Test.Bridge.Budget pins it);
///   - TestStubAdapter: the runners' adapter extends AI Hub's outbound agent adapter and overrides its OnInit, which builds
///     the agent at start, so that a runner starts with no model key (the adapter builds the agent on the first request instead),
///     and the runner class carries no STUB.
Class OcuTalon.Test.Bridge.Api Extends %UnitTest.TestCase
{

/// Raise, Expire, Cancel, StartExecution and FinishExecution each return an error status whose text says that the method
/// is not implemented yet and names it. Raise leaves ref empty. Answer returns not_found and an empty winner.
Method TestApprovalStubs()
{
	Set sc = ##class(OcuTalon.Bridge.Approval).Raise(##class(OcuTalon.Bridge.Data.ApprovalRequest).%New(), .ref)
	Do ..AssertNotImplemented(sc, "OcuTalon.Bridge.Approval.Raise")
	Do $$$AssertEquals(ref, "", "Raise leaves the ref empty")
	Do ..AssertNotImplemented(##class(OcuTalon.Bridge.Approval).Expire("zz"), "OcuTalon.Bridge.Approval.Expire")
	Do ..AssertNotImplemented(##class(OcuTalon.Bridge.Approval).Cancel("zz"), "OcuTalon.Bridge.Approval.Cancel")
	Do ..AssertNotImplemented(##class(OcuTalon.Bridge.Approval).StartExecution("zz"), "OcuTalon.Bridge.Approval.StartExecution")
	Do ..AssertNotImplemented(##class(OcuTalon.Bridge.Approval).FinishExecution("zz", "done"), "OcuTalon.Bridge.Approval.FinishExecution")
	Set result = ##class(OcuTalon.Bridge.Approval).Answer("zz", "approve", "web", "zzuser", "zzsession", .winner)
	Do $$$AssertEquals(result, "not_found", "Answer returns not_found")
	Do $$$AssertTrue($IsObject(winner), "and a winner object")
	Do $$$AssertEquals(winner.%ToJSON(), "{}", "which is empty")
}

/// Keys.Status of an item that is not in the production is 0 (Test.Bridge.Keys pins the rest); Timeouts.Derive(111) is {} (the rest of Derive is no stub:
/// Test.Bridge.Timeouts); Agent.Input.Render of an empty Item gives "" (the rule of its renderer: an Item
/// with no text renders nothing); Checks.Render.Render([]) gives "" and rows []. Budget.State is not here: it is implemented
/// (Story 1.4) and Test.Bridge.Budget pins it.
Method TestNeutralValues()
{
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Keys).Status("ZzNoSuchItem"), 0, "Keys.Status of an item that is not in the production is 0")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Timeouts).Derive(111).%ToJSON(), "{}", "Timeouts.Derive of a timer that Check refuses is an empty object")
	Do $$$AssertEquals(##class(OcuTalon.Agent.Input).Render(##class(OcuTalon.Msg.Item).%New()), "", "Agent.Input.Render gives an empty string")
	Set key = ##class(OcuTalon.Checks.Render).Render([], .rows)
	Do $$$AssertEquals(key, "", "Checks.Render.Render gives an empty catalog key")
	Do $$$AssertTrue($IsObject(rows), "and rows")
	Do $$$AssertEquals(rows.%ToJSON(), "[]", "which are empty")
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

/// --- helpers ---
/// Asserts that sc is an error that names the method and says it is not implemented yet.
Method AssertNotImplemented(sc As %Status, method As %String) [ Private ]
{
	Do $$$AssertStatusNotOK(sc, method_" returns an error status")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue(text [ "is not implemented yet", method_" says it is not implemented yet: "_text)
	Do $$$AssertTrue(text [ method, method_" names itself: "_text)
}

}
