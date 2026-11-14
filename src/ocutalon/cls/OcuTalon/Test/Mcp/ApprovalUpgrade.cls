/// An approval request stored before Story 22.4 added ToolFingerprint still reads, shows and resolves (Story 22.4, the Contest Planner's condition 1; AD-11, AD-33). A row of the earlier
/// layout is a fixture row that is saved and whose stored list is then replaced by the 25-element list that the previous build stored for it (written out from that build's slots, which
/// the current node must start with); the new property is then missing from the node, as it is for such a row after the upgrade. Pending requests of a fix (the demo's kind), of a built-in tool call and of a setting, each answered
/// once with approve and once with reject, show: the row opens with ToolFingerprint empty and its other columns as they were; the payload that the rail, the cards and the channels are
/// built from carries its state and tool; Answer resolves it (approved or rejected) and the row, saved again by Answer, still has an empty ToolFingerprint. An approved built-in tool
/// call then starts and finishes its run. The release upgrade harness (release/upgrade-harness.sh) proves the same on a real previous build and is not part of the per-push suite; this
/// class runs on any stack that has the request table. Each test deletes the rows it saved.
Class OcuTalon.Test.Mcp.ApprovalUpgrade Extends %UnitTest.TestCase
{

/// The approver: the README account, which holds OcuTalonUser.
Parameter ANSWERER = "ocutalon";

/// The host sink that records the events and sends no notice.
Parameter SINK = "OcuTalon.Test.Bridge.ProbeSink";

/// The number of elements of a stored request before ToolFingerprint (property 26) was appended: the class slot and the properties of PREVIOUSORDER.
Parameter PREVIOUSLAYOUT = 25;

/// The property of slots 2 to 25 of the previous build's storage (Story 22.4 appended slot 26).
Parameter PREVIOUSORDER = "Ref,Kind,IncidentRef,OwnerRef,State,DryRun,ToolName,ToolArguments,RequiredRole,ResultTarget,TraceRef,RaisedAt,ExpiresAt,AnsweredAction,AnsweredChannel,AnsweredBy,AnsweredAt,Result,FinishedAt,FixKind,FixParameters,FixTargets,ToolSource,Runner";

/// The Refs of the rows that the test saved, as a list.
Property Refs As %List;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Kill ^||ZzProbeSink
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..Refs, position, ref) {
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
		If $IsObject(row) Do ##class(OcuTalon.Bridge.Data.ApprovalRequest).%DeleteId(row.%Id())
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexExists(ref), 0, "the row " _ ref _ " is deleted")
	}
	Set ..Refs = ""
	Kill ^||ZzProbeSink
	Quit $$$OK
}

/// A pending fix, a pending built-in tool call and a pending setting of the earlier layout, each approved on one copy and rejected on another (see the class description).
Method TestPendingRequestsOfTheEarlierLayout()
{
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet(..#ANSWERER, .roles)
	Set holds = $$$ISOK(sc) && ''$ListFind($ListFromString(roles), "OcuTalonUser")
	Do $$$AssertTrue(holds, "the approver " _ ..#ANSWERER _ " holds OcuTalonUser")
	If 'holds Quit
	For kind = "fix", "tool_call", "setting" {
		For action = "approve", "reject" {
			Set label = kind _ " " _ action _ ": "
			Set expected = $Select(action = "approve": "approved", 1: "rejected")
			Set ref = ..LegacyRow(kind, label)
			If ref = "" Continue
			Set row = ..Fresh(ref)
			Do $$$AssertTrue($IsObject(row), label _ "the row opens")
			If '$IsObject(row) Continue
			Do $$$AssertEquals(row.Kind _ "|" _ row.State _ "|" _ row.RequiredRole, kind _ "|pending|OcuTalonUser", label _ "it is pending, for the role that answers")
			Do $$$AssertEquals("[" _ row.ToolFingerprint _ "]", "[]", label _ "its ToolFingerprint is empty")
			Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(row)
			Do $$$AssertEquals(payload.Ref _ "|" _ payload.Kind _ "|" _ payload.State _ "|" _ payload.ToolName, ref _ "|" _ kind _ "|pending|" _ row.ToolName, label _ "the card's payload shows it")
			Set owner = row.OwnerRef
			Kill row
			Set result = ##class(OcuTalon.Bridge.Approval).Answer(ref, action, "web", ..#ANSWERER, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK)
			Do $$$AssertEquals(result, "done", label _ "Answer resolves it")
			Set row = ..Fresh(ref)
			Do $$$AssertEquals(row.State _ "|" _ row.AnsweredAction _ "|" _ row.OwnerRef, expected _ "|" _ action _ "|" _ owner, label _ "it is " _ expected)
			Do $$$AssertEquals("[" _ row.ToolFingerprint _ "]", "[]", label _ "and its ToolFingerprint is still empty")
			Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Approval).FromRow(row).State, expected, label _ "the payload shows the answer")
			If (kind = "tool_call") && (action = "approve") {
				Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).StartExecution(ref), label _ "its run starts")
				Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).FinishExecution(ref, "done", ..#SINK), label _ "and finishes done")
				Set row = ..Fresh(ref)
				Do $$$AssertEquals(row.State _ "|" _ row.Result _ "|" _ "[" _ row.ToolFingerprint _ "]", "done|done|[]", label _ "the row is done with an empty ToolFingerprint")
			}
		}
	}
}

/// A request of the earlier layout reads by SQL and by the Ref with ToolFingerprint empty, next to a request of the
/// new layout that holds one, and the two do not disturb each other.
Method TestEarlierLayoutBesideTheNew()
{
	Set old = ..LegacyRow("tool_call", "old: ")
	If old = "" Quit
	Set row = ##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow("tool_call", "zz_new_layout", "{""id"":""1""}", "mcp:remote:@{config:AI.MCP.OcuTalon_zzupgrade}")
	Set fingerprint = $Translate($Justify("", 64), " ", "c")
	Set row.ToolFingerprint = fingerprint
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.ApprovalRows).Save(row, "pending", 3600, ..#ANSWERER, .new), "a request of the new layout is saved")
	Set ..Refs = ..Refs _ $ListBuild(new)
	Kill seen
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, ToolFingerprint FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE Ref IN (?, ?)", old, new)
	While result.%Next() {
		Set seen(result.%Get("Ref")) = result.%Get("ToolFingerprint")
	}
	Do $$$AssertEquals($Get(seen(old), "<no row>") _ "|" _ $Get(seen(new), "<no row>"), "|" _ fingerprint, "SQL reads the earlier row's ToolFingerprint as empty and the new row's as stored")
	Do $$$AssertEquals(..Fresh(new).ToolFingerprint, fingerprint, "the new row keeps its fingerprint")
	Do $$$AssertEquals("[" _ ..Fresh(old).ToolFingerprint _ "]", "[]", "and the earlier row's is empty")
}

/// Saves a pending request of the kind in the layout of the previous build and returns its Ref ("" with a failed assertion when it cannot). The stored list of the previous build is
/// written out here from PREVIOUSORDER, the property of each slot of that build, and not cut from what the current class stores, so that a change which moves a slot is seen: the
/// current node must start with those same 25 elements. The Ref is tracked for the clean-up.
Method LegacyRow(kind As %String, label As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow(kind)
	If kind = "tool_call" Set row.Runner = "ChatAgent"
	Set sc = ##class(OcuTalon.Test.Bridge.ApprovalRows).Save(row, "pending", 3600, ..#ANSWERER, .ref)
	Do $$$AssertStatusOK(sc, label _ "a pending request is saved")
	If $$$ISERR(sc) Quit ""
	Set ..Refs = ..Refs _ $ListBuild(ref)
	Set id = row.%Id()
	Set node = $Get(^OcuTalonBP.ApprovalD(id))
	Do $$$AssertTrue($ListValid(node) && ($ListLength(node) > ..#PREVIOUSLAYOUT), label _ "the stored node is a list of the new layout (" _ $ListLength(node) _ " elements)")
	If '$ListValid(node) || ($ListLength(node) <= ..#PREVIOUSLAYOUT) Quit ""
	Set legacy = $ListBuild($List(node, 1))
	For i = 1:1:$Length(..#PREVIOUSORDER, ",") {
		Set legacy = legacy _ $ListBuild($Property(row, $Piece(..#PREVIOUSORDER, ",", i)))
	}
	Kill row
	Do $$$AssertEquals($ListLength(legacy), ..#PREVIOUSLAYOUT, label _ "the previous layout has " _ ..#PREVIOUSLAYOUT _ " elements")
	Do $$$AssertTrue($List(node, 1, ..#PREVIOUSLAYOUT) = legacy, label _ "the current node starts with the previous build's elements, in their slots (ToolFingerprint is appended)")
	Set ^OcuTalonBP.ApprovalD(id) = legacy
	Quit ref
}

/// The request of the Ref, read again from the database.
Method Fresh(ref As %String) As OcuTalon.Bridge.Data.ApprovalRequest [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If $IsObject(row) Do row.%Reload()
	Quit row
}

}
