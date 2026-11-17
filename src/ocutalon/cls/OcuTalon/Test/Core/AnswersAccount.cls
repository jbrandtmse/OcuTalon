/// Tests of the account check of an approval answer (DW-1482, in Story 0.38) over real IRIS accounts (Test.Data.Fixture ChatSession and SetAccount; Fixture.Clean removes the accounts after each test, a failed
/// test included), with no production: AnswersAccountProbe runs the real OnProcessInput with the real role check (Bridge.Approval MayAnswer) and the real account check (Core.Access AccountUsable), and the
/// ApprovalDouble behind AnswerOps records what Approval.Answer would have received. Safe on a slot: it creates and removes only its own fixture accounts.
///   - TestTelegramAnswerNeedsUsableAccount (AC1): the Telegram entry (AnswersIn FromTelegram) refuses an approve and a reject of a disabled user and of an expired user who hold the request's RequiredRole:
///     not_allowed with {"kind": "", "account": true}, nothing handed to AnswerOps (so the request is left as it was: the double changes no row); an enabled, unexpired holder (control) is answered, and so is one who expires today;
///   - TestRoleStillRefusesWithoutAccountFlag: an enabled user who lacks the role is refused as before ({"kind": ""} with no account member), so that the account flag names only the account;
///   - TestWebAndPhoneShareTheGate: the one rule 6 refuses a disabled user's web answer and phone answer too (Refusal {"kind": "", "account": true}, nothing sent), and hands over the enabled holder's;
///   - TestAnswerableAndPayload: Live.Payload.Approval Answerable answers 0 with unusable 1 for the disabled and expired holder and 1 for the enabled one, and the payload's answerable follows it.
Class OcuTalon.Test.Core.AnswersAccount Extends %UnitTest.TestCase
{

/// The probe classes.
Parameter PROBE = "OcuTalon.Test.Core.AnswersAccountProbe";

Parameter TELEGRAM = "OcuTalon.Test.Core.AnswersAccountTelegramProbe";

/// The Refs of the run's fixture rows, comma-separated.
Property Refs As %String(MAXLEN = "");

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).End()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).End()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Quit $$$OK
}

Method TestTelegramAnswerNeedsUsableAccount()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set disabled = ..Holder("disabled", .disabledUser)
	Set expired = ..Holder("expired", .expiredUser)
	Set control = ..Holder("control", .controlUser)
	Set today = ..Holder("today", .todayUser)
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", disabledUser, 0, ""), "the first account is disabled")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", expiredUser, 1, -2), "the second account's ExpirationDate is two days ago")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", todayUser, 1, 0), "the fourth account's ExpirationDate is today, the last day it may be used")
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).RolesOf(disabledUser, .roles) && (roles = "OcuTalonUser"), "control: the disabled account still holds the request's role (so it is the account state that refuses it)")
	For action = "approve", "reject" {
		For which = "disabled", "expired" {
			Set session = $Select(which = "disabled": disabled, 1: expired)
			Set request = ..Request(session)
			Set chat = ..Chat(session)
			Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
			Set sc = $ClassMethod(..#TELEGRAM, "FromTelegram", request, action, chat, .code, .slots)
			Do $$$AssertStatusOK(sc, "the "_action_" of the "_which_" user is handled")
			Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "not_allowed|{""kind"":"""",""account"":true}", "the "_action_" of the "_which_" user is not_allowed, for the account")
			Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 0, "nothing was handed to AnswerOps")
		}
	}
	For which = "control", "today" {
		Set session = $Select(which = "control": control, 1: today)
		Set request = ..Request(session)
		Set chat = ..Chat(session)
		Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
		Do $$$AssertStatusOK($ClassMethod(..#TELEGRAM, "FromTelegram", request, "approve", chat, .code, .slots), "the approve of the "_which_" user is handled")
		Do $$$AssertEquals(code, "approved", "the "_which_" user (enabled, not past the expiry) is answered")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 1, "and the answer reached AnswerOps once")
	}
}

Method TestRoleStillRefusesWithoutAccountFlag()
{
	Set session = ..Holder("viewer", .user, "OcuTalonViewer")
	Set request = ..Request(session)
	Set chat = ..Chat(session)
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
	Do $$$AssertStatusOK($ClassMethod(..#TELEGRAM, "FromTelegram", request, "approve", chat, .code, .slots), "the press is handled")
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "not_allowed|{""kind"":""""}", "an enabled user without the role is not_allowed with no account member")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 0, "and nothing was handed over")
}

Method TestWebAndPhoneShareTheGate()
{
	Set disabled = ..Holder("disabled", .disabledUser)
	Set control = ..Holder("control", .controlUser)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Data.Fixture).SetAccount(disabledUser, 0, ""), "the account is disabled")
	For channel = "web", "phone", "telegram" {
		Set request = ..Request(disabled)
		Set probe = ..NewProbe()
		Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
		Do ..Answer(probe, request, "approve", channel, disabled, .output)
		Do $$$AssertEquals(output.Result, "not_allowed", "the "_channel_" answer of a disabled user is not_allowed")
		Do $$$AssertEquals(probe.Refusal.%ToJSON(), "{""kind"":"""",""account"":true}", "with the refusal that names the account")
		Do $$$AssertEquals(probe.Sends_"|"_##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), "0|0", "and nothing was sent")
		Set request = ..Request(control)
		Set probe = ..NewProbe()
		Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
		Do ..Answer(probe, request, "approve", channel, control, .output)
		Do $$$AssertEquals(output.Result_"|"_probe.Sends, "done|1", "the "_channel_" answer of the enabled holder is handed over")
	}
}

Method TestAnswerableAndPayload()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set disabled = ..Holder("disabled", .disabledUser)
	Set expired = ..Holder("expired", .expiredUser)
	Set control = ..Holder("control", .controlUser)
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", disabledUser, 0, ""), "the first account is disabled")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", expiredUser, 1, -2), "the second account is past its expiry")
	For which = "disabled", "expired", "control" {
		Set session = $Select(which = "disabled": disabled, which = "expired": expired, 1: control)
		Set request = ..Request(session)
		Set answerable = ##class(OcuTalon.Live.Payload.Approval).Answerable(request, session, .kind, "OcuTalon.Bridge.Approval", .unusable)
		Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request), session)
		If which = "control" {
			Do $$$AssertEquals(answerable_"|"_unusable_"|"_payload.Answerable, "1|0|1", "the enabled holder: answerable, usable, and the payload says so")
		} Else {
			Do $$$AssertEquals(answerable_"|"_unusable_"|"_kind_"|"_payload.Answerable, "0|1||0", "the "_which_" holder: not answerable, unusable, no kind, and the payload says so")
		}
	}
}

/// A fixture session of a real account that holds the roles (OcuTalonUser by default); its Ref, with user the account's name. Fixture.Clean removes the account and the session.
Method Holder(name As %String, Output user As %String, roles As %String = "OcuTalonUser") As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).ChatSession("zzacct"_name, roles, .user)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A pending fixture request of the session that needs OcuTalonUser, recorded for the clean-up.
Method Request(session As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(session, "", "pending", , {"RequiredRole": "OcuTalonUser"})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The Ref of a Telegram pairing row of the session, recorded for the clean-up.
Method Chat(session As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Pairing(session)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A shadow instance of the probe.
Method NewProbe() As OcuTalon.Test.Core.AnswersAccountProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Quit probe
}

/// Hands the answer to the probe's OnProcessInput; output is the AnswerResult.
Method Answer(probe As OcuTalon.Test.Core.AnswersAccountProbe, ref As %String, action As %String, channel As %String, sessionRef As %String, Output output As OcuTalon.Core.Msg.AnswerResult) As %Status [ Private ]
{
	Set answer = ##class(OcuTalon.Core.Msg.Answer).%New()
	Set answer.Ref = ref
	Set answer.Action = action
	Set answer.Channel = channel
	Set answer.SessionRef = sessionRef
	Quit probe.OnProcessInput(answer, .output)
}

}
