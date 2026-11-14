/// Tests of the answer route for an email request (Story 22.7, DW-1262; Story 25.5; AD-11, AD-16): an approve of an email to anyone but the
/// owner's own address is refused to a user who passes the role check but does not hold the role OcuTalonAdmin, and the route says it with the sentence "Only an OcuTalon admin can approve this email."
/// (the catalog's answered.notAdmin). The request is raised by an admin (Raise refuses a requester who is no admin, Story 25.5) and answered by this process's user.
/// THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they need the running OcuTalon.Production. Each test calls Web.Api.AnswerApproval as the REST surface does (the stand-in request with the body,
/// a CSP session bound to a fixture session of this process's user, as Test.Core.AnswersInProduction does), so the answering user is this process's user, who holds %All and not the role OcuTalonAdmin
/// by its whole name. The approving by an admin and the check row by row are Test.Fix.Email's. No mail is sent: no test here approves a request.
///   - TestNonAdminApproveIsRefusedWithTheAdminSentence: an approve of an email request to another address is 403 not_allowed with "Only an OcuTalon admin can approve this email.", the request is still
///     pending and nothing is sent; a request that this user may not answer by the role check has the fallback sentence "Only an approver can answer this request.";
///   - TestRejectIsAnswered: a reject of the same request is 200 and the request is rejected.
Class OcuTalon.Test.Fix.EmailRoute Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzemailroute";

Parameter ADDRESS = "owner@example.test";

Parameter OTHER = "partner@example.test";

Parameter ADDRESSKEY = "email.address";

/// The state to put back: $ListBuild(address row exists, address, onlineDemo), or "" while nothing was changed.
Property Found As %List [ Private ];

/// The sessions whose approval rows a test may have made.
Property Owners As %String(MAXLEN = "") [ Private ];

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	For i = 1:1:$Length(..Owners, ",") {
		If $Piece(..Owners, ",", i) '= "" Do ##class(OcuTalon.Test.Bridge.Approval).TrackOwner($Piece(..Owners, ",", i))
	}
	Set ..Owners = ""
	If $Data(^OcuTalonTest("Approval", "refs")) || $Data(^OcuTalonTest("Approval", "job")) Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
	If ..Found '= "" {
		If $List(..Found, 1) {
			Do ##class(OcuTalon.Data.Setting).Set(..#ADDRESSKEY, $List(..Found, 2))
		} Else {
			Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(..#ADDRESSKEY)
		}
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", $List(..Found, 3))
		Set ..Found = ""
	}
	Quit $$$OK
}

/// 1 when the test may run: the production runs, the mailbox has an address, the online demo is off and this process's user does not hold OcuTalonAdmin by its whole name.
Method Setup() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet($Username, .roles)
	Set admin = $$$ISOK(sc) && ##class(OcuTalon.Core.Admin).Held(roles)
	Do $$$AssertEquals(admin, 0, "this process's user does not hold OcuTalonAdmin by its whole name, so it is an approver and no admin")
	If admin Quit 0
	If ..Found = "" Set ..Found = $ListBuild(##class(OcuTalon.Data.Setting).KeyIndexExists(..#ADDRESSKEY), ##class(OcuTalon.Data.Setting).Get(..#ADDRESSKEY), ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo"))
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do ##class(OcuTalon.Data.Setting).Set(..#ADDRESSKEY, ..#ADDRESS)
	Quit 1
}

/// A fixture session of this process's user (Ownership.SessionRef accepts only a session of the signed-in user).
Method WebSession(name As %String) As %String [ Private ]
{
	Set ref = ..Session(name)
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set row.IrisUser = $Username
	Do $$$AssertStatusOK(row.%Save(), "the fixture session "_name_" belongs to "_$Username)
	Quit ref
}

/// The first role of this process's user, which a fixture request may need so that the user may answer it.
ClassMethod HeldRole() As %String [ Private ]
{
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet($Username, .roles)
	Quit $Piece(roles, ",", 1)
}

/// Raises a request of an email to another address for the session through the real Fix.Kind.Email.Raise, as the README admin (Raise refuses a requester who is no admin), and makes it one that this process's user holds the role of; its Ref.
/// The session belongs to this process's user again when it returns.
Method RaiseFor(owner As %String) As %String [ Private ]
{
	Set ..Owners = ..Owners _ $Select(..Owners = "": "", 1: ",") _ owner
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(owner)
	Set session.IrisUser = ##class(OcuTalon.Test.Bridge.ApprovalRows).#ANSWERER
	Do $$$AssertStatusOK(session.%Save(), "the requester is the README admin")
	Set sc = ##class(OcuTalon.Fix.Kind.Email).Raise({"recipients": [(..#OTHER)], "subject": "Route", "text": "Only an admin approves this."}, owner, ##class(OcuTalon.Bridge.Ids).NewRef(), "", .ref, .refusal)
	Set session.IrisUser = $Username
	Do $$$AssertStatusOK(session.%Save(), "and the session is this process's user's again")
	Kill session
	Do $$$AssertEquals($$$ISOK(sc)_"|"_(ref '= "")_"|"_refusal, "1|1|", "the request is raised")
	If ref = "" Quit ""
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Set row.RequiredRole = ..HeldRole()
	Do $$$AssertStatusOK(row.%Save(), "and needs a role that this user holds")
	Quit ref
}

/// Calls Web.Api.AnswerApproval for the ref as the session's user with the body, and returns what it wrote; status is the response's.
Method Post(session As %String, ref As %String, json As %String, Output status As %String) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", json)
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzEmailRoute"_..Number, 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	Set body = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Api", "AnswerApproval", ref)
	Do $$$AssertStatusOK(sc, "AnswerApproval returns OK")
	Set status = %response.Status
	Quit body
}

/// The state of the request as it is stored now.
Method StateOf(ref As %String) As %String [ Private ]
{
	Kill row
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Quit $Select($IsObject(row): row.State, 1: "")
}

/// An approve of an email to another address by a user who is no admin is 403 with the admin sentence and changes nothing.
Method TestNonAdminApproveIsRefusedWithTheAdminSentence()
{
	If '..Setup() Quit
	Set mine = ..WebSession("a")
	Set ref = ..RaiseFor(mine)
	If ref = "" Quit
	Set body = ..Post(mine, ref, "{""action"":""approve"",""channel"":""web""}", .status)
	Do $$$AssertEquals(status, "403 Forbidden", "an approve of an email to another address is 403")
	Do $$$AssertEquals(body, "{""error"":{""code"":""not_allowed"",""message"":""Only an OcuTalon admin can approve this email.""}}", "with the admin sentence and no payload")
	Do $$$AssertEquals(..StateOf(ref), "pending", "the request is still pending")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(mine, "approval")
	Do $$$AssertEquals(events.%Size(), 1, "and no event was published but the one of the raise")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.state, "pending", "which says pending")
	Set other = ##class(OcuTalon.Test.Data.Fixture).Approval(mine, "", "pending", , {"RequiredRole": "ZzNoSuchRole"})
	Set ..Refs = ..Refs _ "," _ other
	Set body = ..Post(mine, other, "{""action"":""approve"",""channel"":""web""}", .status)
	Do $$$AssertEquals(body, "{""error"":{""code"":""not_allowed"",""message"":""Only an approver can answer this request.""}}", "a request that this user may not answer by the role check has the fallback sentence")
}

/// A reject of the same request by the same user is answered.
Method TestRejectIsAnswered()
{
	If '..Setup() Quit
	Set mine = ..WebSession("a")
	Set ref = ..RaiseFor(mine)
	If ref = "" Quit
	Set body = ..Post(mine, ref, "{""action"":""reject"",""channel"":""web""}", .status)
	Do $$$AssertEquals(status, "200 OK", "a reject of an email to another address is 200")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.result_"|"_answer.approval.state, "done|rejected", "done, with the request rejected")
	Do $$$AssertEquals(..StateOf(ref), "rejected", "the stored request is rejected")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.FixRun WHERE ApprovalRef = ?", ref)
	Do rs.%Next()
	Do $$$AssertEquals(+rs.%GetData(1), 0, "and no run was made for it")
}

}
