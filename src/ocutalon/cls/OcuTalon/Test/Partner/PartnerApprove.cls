/// Tests of who may approve a partner warning to Settings contacts (DW-1415; AD-11, AD-16, AD-17; Fix.Kind.Email MayApprove, the one rule of the email kind): the approval of such a warning sends an email, so only
/// a holder of the role OcuTalonAdmin may approve it, on every path that answers an approval (web and phone through the answer route, Telegram through AnswersIn.FromTelegram, and AnswerOps itself).
/// A refusal is not_allowed with the email kind's own sentence "Only an OcuTalon admin can approve this email." (no new text), leaves the request pending (nothing is sent and no draft is kept), and writes one
/// Action entry whose data holds ids only. A reject is not asked, and a warning of the demo's simulated contact (its dry run says simulated 1, delivered only to the Simulated mailbox) is not asked either.
/// THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they need the running OcuTalon.Production. The fixture rows are pending approval rows of the kind partner_warning (ids in the targets, names and
/// addresses only in the row's dry run, as IncidentManager stores them); the IRIS users are made in %SYS and deleted after each test. A fixture row has no hold, so each real answer waits the 5 seconds of
/// Approval.CompleteHoldTask for a task that never appears and logs one warning, which the tests remove.
///   - TestMayApproveRowByRow: a non-admin is refused a warning to Settings contacts, an admin is allowed, a simulated warning, a request of another fix kind and a row that is no fix request are not asked,
///     a dry run that cannot be read or that does not say simulated 1 is asked, and so are an empty and an unknown user;
///   - TestNonAdminCannotApproveOnTelegram: the press of a chat paired to a non-admin's session is not_allowed {"kind": "email", "admin": true}; the row stays pending; nothing was sent and no draft kept;
///   - TestNonAdminCannotApproveOnTheWebAndPhoneRoutes: the answer route, as this process's user who is no admin, answers 403 not_allowed with the email sentence for the channel web and for the channel phone;
///   - TestAdminCanApprove: an admin's approve is done on web, phone and Telegram, and the rows are approved by the admin;
///   - TestRoleRevokedBeforeTheApprovalIsRefused: an admin who lost the role after the request was raised is refused at approval time;
///   - TestRefusalIsAuditedWithIdsOnly: each refused approve writes one Action entry of the action partner_warning with the outcome refused, the request's Ref, the contact ids, the user, the session and the channel,
///     and holds no name, address or notice;
///   - TestDenyIsUnchanged: a non-admin's reject is done on Telegram and on the route;
///   - TestSimulatedWarningIsApprovedByAnyApprover: a non-admin approves the demo's simulated warning, as before.
Class OcuTalon.Test.Partner.PartnerApprove Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzpartnerapprove";

/// The role that the fixture requests need and the fixture users hold.
Parameter ROLE = "OcuTalonUser";

Parameter ADMIN = "OcuTalonAdmin";

/// The email kind's sentence for a refused approve (Core catalog answered.notAdmin).
Parameter SENTENCE = "Only an OcuTalon admin can approve this email.";

/// A name, an address and a notice that a refusal must never put in an audit entry.
Parameter NAME = "Zz Partner Approver Name";

Parameter ADDRESS = "zz-partner-approver@example.test";

Parameter NOTICE = "Zz partner approve notice text.";

/// The IRIS users that a test made, comma-separated, and the count of chats made.
Property Users As %String(MAXLEN = "") [ Private ];

Property Chats As %Integer [ InitialExpression = 0, Private ];

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..DropUsers()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..DropUsers()
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Type = 3 AND Text %STARTSWITH ?", "OcuTalon.Bridge.Approval: no open task of ")
	Quit ##super()
}

/// A non-admin is refused a warning to Settings contacts and an admin is allowed; the rows that the rule does not ask, and the readings that are not known to be simulated, are as ruled.
Method TestMayApproveRowByRow()
{
	If '..Guard() Quit
	Set plain = ..MakeUser("plain", ..#ROLE)
	Set admin = ..MakeUser("admin", ..#ROLE_","_..#ADMIN)
	If (plain = "") || (admin = "") Quit
	Set owner = ..Session("a")
	Set real = ..Row(owner, 0)
	Do $$$AssertEquals(..May(real, plain), 0, "a non-admin may not approve a warning to Settings contacts")
	Do $$$AssertEquals(..May(real, admin), 1, "an admin may")
	Do $$$AssertEquals(..May(real, ""), 0, "no user: no")
	Do $$$AssertEquals(..May(real, "zzNoSuchUser"_..Number), 0, "an unknown user: no")
	Do $$$AssertEquals(..May(..Row(owner, 1), plain), 1, "the demo's simulated warning is not asked: yes")
	Do $$$AssertEquals(..May(..Row(owner, 0, {"DryRun": "not json"}), plain), 0, "a dry run that cannot be read is not simulated: no")
	Do $$$AssertEquals(..May(..Row(owner, 0, {"DryRun": ("{""notice"":""x""}")}), plain), 0, "a dry run that does not say simulated is not simulated: no")
	Do $$$AssertEquals(..May(..Row(owner, 0, {"FixKind": "repair_resend"}), plain), 1, "a request of another fix kind is not asked: yes")
	Do $$$AssertEquals(..May(..Row(owner, 0, {"Kind": "tool"}), plain), 1, "a row that is no fix request is not asked: yes")
	Set simulated = ..Row(owner, 1)
	Do $$$AssertEquals(##class(OcuTalon.Fix.Kind.Email).AdminRuled(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(real))_"|"_##class(OcuTalon.Fix.Kind.Email).AdminRuled(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(simulated)), "1|0", "AdminRuled names the real warning and not the simulated one")
}

/// A press of a chat of a non-admin's session on Approve is not_allowed with the email kind's refusal slots; the request is still pending and nothing was sent or kept.
Method TestNonAdminCannotApproveOnTelegram()
{
	If '..Guard() Quit
	Set plain = ..MakeUser("plain", ..#ROLE)
	If plain = "" Quit
	Set session = ..SessionOf("a", plain)
	Set chat = ..PairedChat(session)
	Set ref = ..Row(session, 0)
	Do ##class(OcuTalon.Core.AnswersIn).FromTelegram(ref, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "not_allowed|{""kind"":""email"",""admin"":true}", "a non-admin's press is not_allowed, with the email kind's admin refusal")
	Do ..AssertUntouched(ref, "Telegram")
}

/// The answer route, for a user who is no admin, is 403 with the email sentence for the channel web and for the channel phone; the request is still pending and nothing was sent or kept.
Method TestNonAdminCannotApproveOnTheWebAndPhoneRoutes()
{
	If '..Guard() Quit
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet($Username, .roles)
	Set held = $$$ISOK(sc) && ##class(OcuTalon.Core.Admin).Held(roles)
	Do $$$AssertEquals(held, 0, "this process's user does not hold OcuTalonAdmin by its whole name, so it is an approver and no admin")
	If held Quit
	Set mine = ..WebSession("a")
	For channel = "web", "phone" {
		Set ref = ..Row(mine, 0, {"RequiredRole": (..HeldRole())})
		Set body = ..Post(mine, ref, "{""action"":""approve"",""channel"":"""_channel_"""}", .status)
		Do $$$AssertEquals(status, "403 Forbidden", "an approve on the channel "_channel_" is 403")
		Do $$$AssertEquals(body, "{""error"":{""code"":""not_allowed"",""message"":"""_..#SENTENCE_"""}}", "with the email kind's admin sentence and no payload")
		Do ..AssertUntouched(ref, channel)
	}
}

/// An admin's approve is done on the channels web and phone (AnswerOps, as AnswersIn hands it over) and on Telegram; each request is approved by the admin.
Method TestAdminCanApprove()
{
	If '..Guard() Quit
	Set admin = ..MakeUser("admin", ..#ROLE_","_..#ADMIN)
	If admin = "" Quit
	Set session = ..SessionOf("a", admin)
	For channel = "web", "phone" {
		Set ref = ..Row(session, 0)
		Do $$$AssertEquals(..AnswerAs(session, ref, "approve", channel), "done", "an admin's approve on the channel "_channel_" is done")
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
		Do $$$AssertEquals(row.State_"|"_row.AnsweredBy_"|"_row.AnsweredChannel, "approved|"_admin_"|"_channel, "the request is approved by the admin on "_channel)
		Do ..RemoveTaskWarnings(ref)
	}
	Set chat = ..PairedChat(session)
	Set ref = ..Row(session, 0)
	Do ##class(OcuTalon.Core.AnswersIn).FromTelegram(ref, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code, "approved", "an admin's press on Telegram is approved")
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.AnsweredBy_"|"_row.AnsweredChannel, "approved|"_admin_"|telegram", "the request is approved by the admin on Telegram")
	Do ..RemoveTaskWarnings(ref)
}

/// An admin who held the role when the request was raised and lost it before the approval is refused at approval time, on Telegram and through AnswerOps.
Method TestRoleRevokedBeforeTheApprovalIsRefused()
{
	If '..Guard() Quit
	Set admin = ..MakeUser("revoked", ..#ROLE_","_..#ADMIN)
	If admin = "" Quit
	Set session = ..SessionOf("a", admin)
	Set chat = ..PairedChat(session)
	Set first = ..Row(session, 0)
	Set second = ..Row(session, 0)
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(first)
	Do $$$AssertEquals(##class(OcuTalon.Fix.Kind.Email).MayApprove(row, admin), 1, "control: while the role is held the admin may approve")
	Do $$$AssertStatusOK(..SetRoles(admin, ..#ROLE), "the role "_..#ADMIN_" is revoked from the user")
	Do $$$AssertEquals(##class(OcuTalon.Fix.Kind.Email).MayApprove(row, admin), 0, "MayApprove reads the roles as they are now")
	Do ##class(OcuTalon.Core.AnswersIn).FromTelegram(first, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "not_allowed|{""kind"":""email"",""admin"":true}", "the press on Telegram is refused at approval time")
	Do ..AssertUntouched(first, "Telegram")
	Do $$$AssertEquals(..AnswerAs(session, second, "approve", "web"), "not_allowed", "so is the answer that AnswersIn hands to AnswerOps")
	Do ..AssertUntouched(second, "web")
}

/// A refused approve writes one Action entry of the action partner_warning with ids only, on every path; a name, an address or the notice of the row is in none of them.
Method TestRefusalIsAuditedWithIdsOnly()
{
	If '..Guard() Quit
	Set plain = ..MakeUser("plain", ..#ROLE)
	If plain = "" Quit
	Set session = ..SessionOf("a", plain)
	Set chat = ..PairedChat(session)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set telegram = ..Row(session, 0)
	Do ##class(OcuTalon.Core.AnswersIn).FromTelegram(telegram, "approve", chat, .code, .slots)
	Set direct = ..Row(session, 0)
	Do $$$AssertEquals(..AnswerAs(session, direct, "approve", "phone"), "not_allowed", "control: AnswerOps refuses the approve on the channel phone")
	Set mine = ..WebSession("b")
	Set routed = ..Row(mine, 0, {"RequiredRole": (..HeldRole())})
	Do ..Post(mine, routed, "{""action"":""approve"",""channel"":""web""}", .status)
	Do $$$AssertEquals(status, "403 Forbidden", "control: the route refuses the approve on the channel web")
	For path = "telegram|"_telegram_"|"_session_"|"_plain, "phone|"_direct_"|"_session_"|"_plain, "web|"_routed_"|"_mine_"|"_$Username {
		Set channel = $Piece(path, "|", 1), ref = $Piece(path, "|", 2)
		Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", ref, "", 1, 20)
		Do $$$AssertEquals(entries.%Size(), 1, "one Action entry names the request refused on "_channel)
		If entries.%Size() '= 1 Continue
		Set data = entries.%Get(0).data
		Do $$$AssertEquals(data.action_"|"_data.result_"|"_data.approvalRef_"|"_data.channel, "partner_warning|refused|"_ref_"|"_channel, "it names the action, the outcome, the request and the channel "_channel)
		Do $$$AssertEquals(data.irisUser_"|"_data.sessionRef, $Piece(path, "|", 4)_"|"_$Piece(path, "|", 3), "and the user and the session")
		Do $$$AssertEquals(data.target_"|"_data.counts.contacts, "partner contacts (7,8)|2", "and the contact ids and their count")
		Set json = data.%ToJSON()_entries.%Get(0).description
		Do $$$AssertEquals((json [ ..#NAME)_"|"_(json [ ..#ADDRESS)_"|"_(json [ ..#NOTICE), "0|0|0", "and holds no name, address or notice")
	}
	Do ..RemoveTaskWarnings("")
}

/// Deny stays open to whoever may deny today: a non-admin's reject is done on Telegram and on the route, and the requests are rejected.
Method TestDenyIsUnchanged()
{
	If '..Guard() Quit
	Set plain = ..MakeUser("plain", ..#ROLE)
	If plain = "" Quit
	Set session = ..SessionOf("a", plain)
	Set chat = ..PairedChat(session)
	Set ref = ..Row(session, 0)
	Do ##class(OcuTalon.Core.AnswersIn).FromTelegram(ref, "reject", chat, .code, .slots)
	Do $$$AssertEquals(code, "rejected", "a non-admin's press on Reject is rejected")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref).State, "rejected", "and the request is rejected")
	Set mine = ..WebSession("b")
	Set routed = ..Row(mine, 0, {"RequiredRole": (..HeldRole())})
	Set body = ..Post(mine, routed, "{""action"":""reject"",""channel"":""web""}", .status)
	Do $$$AssertEquals(status, "200 OK", "a reject on the route is 200")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(routed).State, "rejected", "and that request is rejected too")
}

/// The demo's simulated warning, which goes only to the Simulated mailbox, is approved by a user who is no admin, as before.
Method TestSimulatedWarningIsApprovedByAnyApprover()
{
	If '..Guard() Quit
	Set plain = ..MakeUser("plain", ..#ROLE)
	If plain = "" Quit
	Set session = ..SessionOf("a", plain)
	Set chat = ..PairedChat(session)
	Set ref = ..Row(session, 1)
	Do ##class(OcuTalon.Core.AnswersIn).FromTelegram(ref, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code, "approved", "a non-admin's press on the simulated warning is approved")
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.AnsweredBy, "approved|"_plain, "the request is approved by the non-admin")
	Do ..RemoveTaskWarnings(ref)
}

/// --- helpers ---
/// 1 when MayApprove allows the user to approve the row.
Method May(ref As %String, user As %String) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Fix.Kind.Email).MayApprove(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref), user)
}

/// A pending fixture request of the kind partner_warning for the session, whose dry run says simulated (0 or 1) and holds the names and addresses as IncidentManager stores them, its targets the ids 7 and 8; fields change the
/// defaults (the role that the fixture users hold is the default). Its Ref, kept for the clean-up.
Method Row(owner As %String, simulated As %Boolean, fields As %DynamicObject = "") As %String [ Private ]
{
	Set all = {"FixKind": "partner_warning", "FixTargets": "7,8", "RequiredRole": (..#ROLE)}
	Do all.%Set("FixParameters", {"text": (..#NOTICE), "to": "7,8"}.%ToJSON())
	Do all.%Set("DryRun", {"notice": (..#NOTICE), "recipients": [{"id": 7, "name": (..#NAME), "address": (..#ADDRESS)}, {"id": 8, "name": (..#NAME_" 2"), "address": ("two."_..#ADDRESS)}], "simulated": (simulated)}.%ToJSON())
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, "", "pending", , all)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// Asserts that the request is still pending and unanswered and that nothing was sent or kept for it: no Delivery row, no run and no executing state.
Method AssertUntouched(ref As %String, path As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.AnsweredAction_"|"_row.AnsweredBy, "pending||", "the request is still pending and unanswered ("_path_")")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT (SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE ApprovalRef = ?) + (SELECT COUNT(*) FROM OcuTalon_Data.FixRun WHERE ApprovalRef = ?)", ref, ref)
	Do rs.%Next()
	Do $$$AssertEquals(+rs.%GetData(1), 0, "and nothing was sent or kept for it: no delivery and no run ("_path_")")
}

/// A fixture session for the IRIS user (its Ref, kept for the clean-up).
Method SessionOf(name As %String, user As %String) As %String [ Private ]
{
	Set ref = ..Session(name)
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set row.IrisUser = user
	Do $$$AssertStatusOK(row.%Save(), "the fixture session "_name_" belongs to "_user)
	Quit ref
}

/// A fixture session of this process's user (Ownership.SessionRef accepts only a session of the signed-in user).
Method WebSession(name As %String) As %String [ Private ]
{
	Quit ..SessionOf(name, $Username)
}

/// A role that this process's user holds.
ClassMethod HeldRole() As %String [ Private ]
{
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet($Username, .roles)
	Quit $Piece(roles, ",", 1)
}

/// A chat row that is on the session (a fixture link), recorded for the clean-up; its ChatRef.
Method PairedChat(session As %String) As %String [ Private ]
{
	Set ..Chats = ..Chats + 1
	Set chat = ##class(OcuTalon.Data.Pairing).RecordChat("74"_..Number_"0"_..Chats, "Dana", .sc)
	Set row = ##class(OcuTalon.Data.Pairing).Chat(chat)
	Set row.SessionRef = session
	Do row.%Save()
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	Quit chat
}

/// Calls Web.Api.AnswerApproval for the ref as the session's user with the body, and returns what it wrote; status is the response's.
Method Post(session As %String, ref As %String, json As %String, Output status As %String) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", json)
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzPartnerApprove"_..Number, 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	Set body = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Api", "AnswerApproval", ref)
	Do $$$AssertStatusOK(sc, "AnswerApproval returns OK")
	Set status = %response.Status
	Quit body
}

/// The answer of AnswersIn's hand-over to AnswerOps for the request, as the production does it (the IRIS user is read from the session's row): AnswerOps' result, or the text of the error status.
Method AnswerAs(sessionRef As %String, ref As %String, action As %String, channel As %String) As %String [ Private ]
{
	Set sc = ##class(Ens.Director).CreateBusinessService("AnswersIn", .service)
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetErrorText(sc)
	Set answer = ##class(OcuTalon.Core.Msg.Answer).%New()
	Set answer.Ref = ref
	Set answer.Action = action
	Set answer.Channel = channel
	Set answer.SessionRef = sessionRef
	Set sc = service.SendRequestSync("AnswerOps", answer, .response, 60)
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetErrorText(sc)
	Quit response.Result
}

/// Makes an IRIS user that holds the roles (a comma-separated list); its name, or "" when it could not be made. DropUsers deletes it.
Method MakeUser(name As %String, roles As %String) As %String [ Private ]
{
	Set user = "zzpapp"_name_..Number
	Set sc = ..CreateUser(user, roles, "Zz-papp-pw-"_$Random(1000000))
	Do $$$AssertStatusOK(sc, "the fixture user "_user_" holds "_roles)
	If $$$ISERR(sc) Quit ""
	Set ..Users = ..Users_$Select(..Users = "": "", 1: ",")_user
	Quit user
}

/// The status of Security.Users.Create for the user with the roles and the password, which the caller never prints. Runs in %SYS.
ClassMethod CreateUser(user As %String, roles As %String, password As %String) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ##class(Security.Users).Create(user, roles, password, "OcuTalon test fixture", "OCUTALON", "", "", 0, 1, "Created by a test; the test deletes it.", 1, "", "", , 1, 1)
}

/// The status of putting exactly the roles (a comma-separated list) on the IRIS user. Runs in %SYS.
ClassMethod SetRoles(user As %String, roles As %String) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set properties("Roles") = roles
	Quit ##class(Security.Users).Modify(user, .properties)
}

/// Deletes the IRIS users that the test made.
Method DropUsers() [ Private ]
{
	For i = 1:1:$Length(..Users, ",") {
		Do ##class(OcuTalon.Test.Install.PasswordGuard).RemoveUser($Piece(..Users, ",", i))
	}
	Set ..Users = ""
}

/// Removes the warning that an answer on a fixture row logs, for a task that never appears ("" removes every one).
Method RemoveTaskWarnings(ref As %String) [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Type = 3 AND Text %STARTSWITH ?", "OcuTalon.Bridge.Approval: no open task of "_ref)
}

}
