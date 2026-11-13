/// Tests of the cross-lane API stubs of Lane A that are left (Story 0.6, matrix row 9): each stub answers what the architecture says a
/// caller sees until its owner builds it. No Approval stub is left (Story 3.5 built the last of them; Test.Bridge.Approval pins the
/// API). Nothing is written anywhere, except the approval rows of TestMayAnswer, which the test deletes by Ref (after a failure too), the fixture session that owns one of
/// them (Test.Data.Fixture.Session, removed by Fixture.Clean with its stream), and its ^OcuTalonTest("BridgeApi", "n") counter.
///   - TestNeutralValues: Keys.Status of an item that is not in the production (Keys.Status is no stub since Story 1.6; Test.Bridge.Keys
///     pins it), Timeouts.Derive of a timer that is refused (Derive is no stub since Story 1.7; Test.Bridge.Timeouts pins it), Agent.Input.Render of an empty Item (which renders "" since Story 1.3);
///     Checks.Render is no stub since Story 5.7 (Test.Checks.Render pins it), and neither is Budget.State since Story 1.4 (Test.Bridge.Budget pins it);
///   - TestStubAdapter: the runners' adapter extends AI Hub's outbound agent adapter and overrides its OnInit, which builds
///     the agent at start, so that a runner starts with no model key (the adapter builds the agent on the first request instead),
///     and the runner class carries no STUB;
///   - TestMayAnswer: Approval.MayAnswer is the interim rule of Story 37.1 until Story 26.4: 1 when the user holds the row's RequiredRole, 0 for a user
///     without it, a role nobody holds, an unknown or malformed Ref and an empty user, with kind empty, 1 for an answered and expired row (state and expiry
///     are Answer's), and it writes nothing and publishes no event;
///   - TestRoleStubs: Install.Step.Roles.Assign and Holders are stubs until Story 26.4: 5003, changed 0, users [], and no role changes;
///   - TestReadFileStub: Agent.Input.ReadFile is a stub until Stories 26.2 and 26.3: 5003 and {}.
Class OcuTalon.Test.Bridge.Api Extends %UnitTest.TestCase
{

/// The Refs of the approval rows that a test saved, comma-separated; OnAfterOneTest deletes them.
Property Refs As %String(MAXLEN = "");

/// The Refs of the fixture sessions that a test made, comma-separated (Test.Data.Fixture.Session); OnAfterOneTest deletes them.
Property Sessions As %String(MAXLEN = "");

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Refs, ",") {
		Set ref = $Piece(..Refs, ",", i)
		If ref = "" Continue
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
		If $IsObject(row) Do ##class(OcuTalon.Bridge.Data.ApprovalRequest).%DeleteId(row.%Id())
	}
	Set ..Refs = ""
	If ..Sessions '= "" {
		Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Sessions)
		Set ..Sessions = ""
	}
	Quit $$$OK
}

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

/// The rows of the matrix for Approval.MayAnswer: the README account holds OcuTalonUser (the role of a saved fixture row), OcuTalonWorkflow holds no
/// role of it, a row whose RequiredRole nobody holds is answered 0, and an unknown Ref, a malformed Ref and an empty user are answered 0, each with kind
/// "". A row already answered and past its expiry is still answered 1 for the holder (Answer decides state and expiry). The row's State, AnsweredBy and
/// AnsweredAt and the table's row count are the same after every call, no audit entry names either row, no event reaches the stream of the session that
/// owns the first row, and no call throws.
Method TestMayAnswer()
{
	Set user = ##class(OcuTalon.Test.Bridge.ApprovalRows).#ANSWERER
	Set row = ##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow("tool_call")
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session(user)
	Set ..Sessions = session
	Set row.OwnerRef = session
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.ApprovalRows).Save(row, "pending", , , .ref), "a pending row is saved")
	Set ..Refs = ref
	Set other = ##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow("tool_call")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.ApprovalRows).Save(other, "pending", , , .nobodyRef), "a second pending row is saved")
	Set ..Refs = ..Refs_","_nobodyRef
	Set nobody = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(nobodyRef)
	Set nobody.RequiredRole = "ZzNobody"_$Increment(^OcuTalonTest("BridgeApi", "n"))
	Do $$$AssertStatusOK(nobody.%Save(), "its RequiredRole is a role that nobody holds")
	Set done = ##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow("tool_call")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.ApprovalRows).Save(done, "approved", -60, , .doneRef), "an answered row past its expiry is saved")
	Set ..Refs = ..Refs_","_doneRef
	Do $$$AssertStatusOK($SYSTEM.Security.GetUserRecursedRoleSet("OcuTalonWorkflow", .workflowRoles), "the user OcuTalonWorkflow exists")
	Do $$$AssertTrue(..RowCount() >= 3, "the approval rows are counted")
	Set before = ..RowFacts(ref)_"|"_..RowFacts(nobodyRef)_"|"_..RowCount()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()

	Set kind = "zz"
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).MayAnswer(ref, user, .kind), 1, "the README account holds the role of the row")
	Do $$$AssertEquals(kind, "", "kind is empty for the holder")
	Set kind = "zz"
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).MayAnswer(doneRef, user, .kind), 1, "an answered row past its expiry still answers 1 for the holder")
	Do $$$AssertEquals(kind, "", "kind is empty for that row")
	Set kind = "zz"
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).MayAnswer(ref, "OcuTalonWorkflow", .kind), 0, "OcuTalonWorkflow does not hold it")
	Do $$$AssertEquals(kind, "", "kind is empty for a user without the role")
	Set kind = "zz"
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).MayAnswer(nobodyRef, user, .kind), 0, "a role that nobody holds answers 0")
	Do $$$AssertEquals(kind, "", "kind is empty for that row")
	Set kind = "zz"
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).MayAnswer(##class(OcuTalon.Bridge.Ids).NewRef(), user, .kind), 0, "a well-formed Ref with no row answers 0")
	Do $$$AssertEquals(kind, "", "kind is empty when no row has the Ref")
	Set kind = "zz"
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).MayAnswer("x", user, .kind), 0, "a malformed Ref answers 0")
	Do $$$AssertEquals(kind, "", "kind is empty for a malformed Ref")
	Set kind = "zz"
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).MayAnswer(ref, "", .kind), 0, "an empty user answers 0")
	Do $$$AssertEquals(kind, "", "kind is empty for an empty user")
	Set kind = "zz"
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).MayAnswer("", user, .kind), 0, "an empty Ref answers 0")
	Do $$$AssertEquals(kind, "", "kind is empty for an empty Ref")
	Do $$$AssertEquals(..RowFacts(ref)_"|"_..RowFacts(nobodyRef)_"|"_..RowCount(), before, "no state, answer field or row count changed")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, , , , ref).%Size() + ##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, , , , nobodyRef).%Size(), 0, "and no audit entry names either row")
	Do $$$AssertEquals(##class(OcuTalon.Live.Event).Since(session, 0).%Size(), 0, "and no event reached the stream of the row's owner")
}

/// The State, AnsweredBy and AnsweredAt of the row of the Ref, read again from the database.
ClassMethod RowFacts(ref As %String) As %String
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If '$IsObject(row) || $$$ISERR(row.%Reload()) Quit "<no row>"
	Quit row.State_"/"_row.AnsweredBy_"/"_row.AnsweredAt
}

/// The number of rows of the approval table.
ClassMethod RowCount() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ApprovalRequest")
	If result.%Next() Quit result.%GetData(1)
	Quit -1
}

/// Assign answers 5003 and sets changed to 0 for a grant and for a removal, Holders answers 5003 and sets users to [], and the recursed role set of the
/// README account is the same before and after.
Method TestRoleStubs()
{
	Set user = ##class(OcuTalon.Test.Bridge.ApprovalRows).#ANSWERER
	Do $$$AssertStatusOK($SYSTEM.Security.GetUserRecursedRoleSet(user, .before), "the roles of the README account are read")
	Set changed = 1
	Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(user, "OcuTalonApprover", 1, .changed)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "Assign of a grant answers 'not implemented'")
	Do $$$AssertEquals(changed, 0, "and changes nothing")
	Set changed = 1
	Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(user, "%All", 0, .changed)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "Assign of a removal answers 'not implemented'")
	Do $$$AssertEquals(changed, 0, "and changes nothing")
	Set users = "zz"
	Set sc = ##class(OcuTalon.Install.Step.Roles).Holders(.users)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "Holders answers 'not implemented'")
	Do $$$AssertEquals(users.%ToJSON(), "[]", "and lists nobody")
	Do $$$AssertStatusOK($SYSTEM.Security.GetUserRecursedRoleSet(user, .after), "the roles of the README account are read again")
	Do $$$AssertEquals(after, before, "the roles of the README account are the same")
}

/// ReadFile of an Item with a file answers 5003 and {}.
Method TestReadFileStub()
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.FileRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SessionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.FileMediaType = "application/pdf"
	Set result = "zz"
	Set sc = ##class(OcuTalon.Agent.Input).ReadFile(item, .result)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "ReadFile answers 'not implemented'")
	Do $$$AssertEquals(result.%ToJSON(), "{}", "and the result is empty")
}

}
