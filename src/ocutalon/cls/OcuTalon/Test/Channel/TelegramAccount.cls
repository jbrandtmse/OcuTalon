Include Ensemble

/// Tests of the account check of a Telegram press (DW-1482, in Story 0.38) over real IRIS accounts (Test.Data.Fixture ChatSession and SetAccount; Fixture.Clean removes the accounts and rows after each test, a failed
/// test included), with no production and no Bot API call: OcuTalon.Test.Channel.TelegramInProbe with Account 1 runs the real Press and GotIt of TelegramIn, with the real role and account checks of AnswersIn
/// behind the ApprovalDouble, and records what the press would have submitted, answered and sent to Intake. Safe on a slot.
///   - TestApproveRefusedForUnusableAccount (AC1): the Approve and the Reject pressed by a paired chat whose session's user is disabled, and by one whose account is past its expiry, both holding the request's
///     RequiredRole, hand nothing to AnswerOps, leave the request pending, are answered with no text and no alert (the existing not_allowed handling) and leave one Channel.Refused {telegram, not_user} to
///     Intake; the Approve of an enabled, unexpired holder (control) is handed over, answered, and leaves no Refused;
///   - TestGotItRefusedForUnusableAccount (AC2): the Got it pressed under a tell-now notice, and under a page, by the same two users, submits neither GotIt nor AckPage (nothing is marked handled and nothing is
///     resent), is answered as today (no text, no alert) and leaves one Channel.Refused {telegram, not_user}; the enabled holder's press submits GotIt (AckPage for the page) and leaves no Refused;
///   - TestOtherPressesLeaveNoRefused: a Got it press of a chat whose Delivery row is another chat's, and a role refusal of an enabled user, leave no Channel.Refused (only the account check records one).
Class OcuTalon.Test.Channel.TelegramAccount Extends %UnitTest.TestCase
{

/// The run's number, the subscript of the probe's record.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("TelegramAccount", "n"))
	Set ..Refs = ""
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("TelegramInProbe", ..Number)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Tidy()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Tidy()
	Quit $$$OK
}

Method TestApproveRefusedForUnusableAccount()
{
	Set disabled = ..Holder("disabled", .disabledUser)
	Set expired = ..Holder("expired", .expiredUser)
	Set control = ..Holder("control", .controlUser)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Data.Fixture).SetAccount(disabledUser, 0, ""), "the first account is disabled")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Data.Fixture).SetAccount(expiredUser, 1, -2), "the second account's ExpirationDate is two days ago")
	For action = "approve", "reject" {
		For which = "disabled", "expired" {
			Kill ^OcuTalonTest("TelegramInProbe", ..Number)
			Set session = $Select(which = "disabled": disabled, 1: expired)
			Set request = ..Request(session)
			Set chat = ..Chat(session)
			Set probe = ..NewProbe()
			Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
			Do probe.RunPress(chat, {"id": "zz1", "data": (action_":"_request)})
			Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 0, "the "_action_" of the "_which_" user sends nothing to AnswerOps")
			Do $$$AssertEquals(..Targets(), "answer,Intake", "one record goes to Intake and the press is answered once")
			Do $$$AssertEquals(..Field("answer", "text")_"|"_..Field("answer", "alert"), "|0", "the answer has no text and no alert, as every not_allowed has")
			Do $$$AssertEquals(..Field("Intake", "class")_"|"_..Field("Intake", "channel")_"|"_..Field("Intake", "reason"), "OcuTalon.Channel.Refused|telegram|not_user", "the record is a Channel.Refused {telegram, not_user}")
		}
	}
	Kill ^OcuTalonTest("TelegramInProbe", ..Number)
	Set request = ..Request(control)
	Set probe = ..NewProbe()
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
	Do probe.RunPress(..Chat(control), {"id": "zz2", "data": ("approve:"_request)})
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 1, "control: the approve of the enabled holder reaches AnswerOps once")
	Do $$$AssertEquals(..Targets(), "answer", "and is answered, with no Refused")
}

Method TestGotItRefusedForUnusableAccount()
{
	Set disabled = ..Holder("disabled", .disabledUser)
	Set expired = ..Holder("expired", .expiredUser)
	Set control = ..Holder("control", .controlUser)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Data.Fixture).SetAccount(disabledUser, 0, ""), "the first account is disabled")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Data.Fixture).SetAccount(expiredUser, 1, -2), "the second account's ExpirationDate is two days ago")
	For kind = "tellnow", "page" {
		For which = "disabled", "expired", "control" {
			Kill ^OcuTalonTest("TelegramInProbe", ..Number)
			Set session = $Select(which = "disabled": disabled, which = "expired": expired, 1: control)
			Set chat = ..Chat(session)
			Set decision = ##class(OcuTalon.Bridge.Ids).NewRef()
			Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Delivery(session, {"Channel": "telegram", "ChannelMessageId": (chat_":7"), "DecisionRef": (decision), "Kind": (kind)})
			Set probe = ..NewProbe()
			Do probe.RunPress(chat, {"id": "zz3", "data": ("gotit:"_decision)})
			If which = "control" {
				Do $$$AssertEquals(..Targets(), "submit,answer", "control ("_kind_"): the enabled holder's press submits one command and is answered, with no Refused")
				Do $$$AssertEquals(..Field("submit", "class")_"|"_..Field("submit", "ref"), $Select(kind = "page": "OcuTalon.Msg.Command.AckPage", 1: "OcuTalon.Msg.Command.GotIt")_"|"_decision, "the command is "_$Select(kind = "page": "AckPage", 1: "GotIt")_" for the notice's Ref")
			} Else {
				Do $$$AssertEquals(..Targets(), "Intake,answer", "the "_which_" user's press of "_kind_" submits neither GotIt nor AckPage, leaves one record to Intake and is answered")
				Do $$$AssertEquals(..Field("answer", "text")_"|"_..Field("answer", "alert"), "|0", "the answer has no text and no alert, as today")
				Do $$$AssertEquals(..Field("Intake", "class")_"|"_..Field("Intake", "channel")_"|"_..Field("Intake", "reason"), "OcuTalon.Channel.Refused|telegram|not_user", "the record is a Channel.Refused {telegram, not_user}")
			}
		}
	}
}

Method TestOtherPressesLeaveNoRefused()
{
	Set control = ..Holder("control", .controlUser)
	Set other = ..Holder("other", .otherUser)
	Set chat = ..Chat(control)
	Set otherChat = ..Chat(other)
	Set decision = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Delivery(other, {"Channel": "telegram", "ChannelMessageId": (otherChat_":7"), "DecisionRef": (decision)})
	Set probe = ..NewProbe()
	Do probe.RunPress(chat, {"id": "zz4", "data": ("gotit:"_decision)})
	Do $$$AssertEquals(..Targets(), "answer", "a Got it press for a notice that is not this session's submits nothing and leaves no Refused")
	Kill ^OcuTalonTest("TelegramInProbe", ..Number)
	Set viewer = ..Holder("viewer", .viewerUser, "OcuTalonViewer")
	Set request = ..Request(viewer)
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
	Do probe.RunPress(..Chat(viewer), {"id": "zz5", "data": ("approve:"_request)})
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 0, "an enabled user without the role sends nothing")
	Do $$$AssertEquals(..Targets(), "answer", "and the role refusal leaves no Refused (only the account check records one)")
}

/// What the test made, removed on every path.
Method Tidy() [ Private ]
{
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).End()
	Kill ^OcuTalonTest("TelegramInProbe", ..Number)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
}

/// The targets of the probe's records, in order, comma-separated.
Method Targets() As %String [ Private ]
{
	Set list = ""
	For i = 1:1:+$Get(^OcuTalonTest("TelegramInProbe", ..Number)) {
		Set list = list_$Select(list = "": "", 1: ",")_$Get(^OcuTalonTest("TelegramInProbe", ..Number, i, "target"))
	}
	Quit list
}

/// The field of the first record of the target.
Method Field(target As %String, name As %String) As %String [ Private ]
{
	For i = 1:1:+$Get(^OcuTalonTest("TelegramInProbe", ..Number)) {
		If $Get(^OcuTalonTest("TelegramInProbe", ..Number, i, "target")) = target Quit
	}
	Quit $Get(^OcuTalonTest("TelegramInProbe", ..Number, i, name))
}

/// A shadow instance of the probe with the press seams on.
Method NewProbe() As OcuTalon.Test.Channel.TelegramInProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Channel.TelegramInProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.RunNumber = ..Number
	Set probe.Account = 1
	Quit probe
}

/// A fixture session of a real account that holds the roles (OcuTalonUser by default); its Ref, with user the account's name.
Method Holder(name As %String, Output user As %String, roles As %String = "OcuTalonUser") As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).ChatSession("zztgacct"_name, roles, .user)
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

}
