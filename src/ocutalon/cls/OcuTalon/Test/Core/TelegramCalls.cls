/// Tests of the direct calls that Lane A's TelegramIn will make into Lane B's classes (Story 10.3; AD-1, AD-14, AD-20, AD-26; FR-20, FR-40):
/// a fixture TelegramIn calls Allowance.TryConsume and Trace.Join with the channel telegram, and records and finds a Delivery by a
/// <ChatRef>:<message id>. Story 16.9 adds the refusals of TryConsume; this story proves the allowed path. Safe on a slot. The sessions are
/// fixture sessions, removed after the run with their deliveries.
///   - TestTryConsumeAllowsATelegramMessage: TryConsume(session, telegram, text) is 1 with retryAt empty and firstRefusal 0, again and for a
///     session that has no row (it gates nothing yet);
///   - TestJoinGivesTheSameThread: once the session's thread is started, Join gives that positive id twice, as it does for the web chat;
///   - TestDeliveryIsFoundByItsOwner: a delivery recorded with the channel telegram and <ChatRef>:42 is found for its approval, channel and
///     owner, and not for another session, another channel or a case-changed Ref.
Class OcuTalon.Test.Core.TelegramCalls Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("TelegramCalls", "n"))
	Set ..Refs = ""
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
}

/// A message from the paired chat is allowed below the limit: 1, no retry time and no first refusal (the refusal at the limit is
/// Test.Core.Allowance's).
Method TestTryConsumeAllowsATelegramMessage()
{
	Set session = ..Session("consume")
	For i = 1:1:2 {
		Set allowed = ##class(OcuTalon.Core.Allowance).TryConsume(session, "telegram", "hello", .retryAt, .firstRefusal)
		Do $$$AssertEquals(allowed_"|"_retryAt_"|"_firstRefusal, "1||0", "call "_i_": allowed, retryAt empty, no first refusal")
	}
	Set allowed = ##class(OcuTalon.Core.Allowance).TryConsume(##class(OcuTalon.Bridge.Ids).NewRef(), "telegram", "hello", .retryAt, .firstRefusal)
	Do $$$AssertEquals(allowed_"|"_retryAt_"|"_firstRefusal, "1||0", "a session with no row is allowed too: the allowance records nothing for it")
}

/// Join gives the thread of the session's day: the same positive id twice once the thread is started, and "" with an OK status before.
Method TestJoinGivesTheSameThread()
{
	Set session = ..Session("join")
	Set none = ##class(OcuTalon.Core.Trace).Join(session, .sc)
	Do $$$AssertEquals(none, "", "a session with no thread gets none")
	Do $$$AssertStatusOK(sc, "with an OK status")
	Set id = 900000 + ..Number
	Do $$$AssertStatusOK(##class(OcuTalon.Core.Trace).Started(session, id), "the session's thread for the day is started")
	Set first = ##class(OcuTalon.Core.Trace).Join(session, .sc)
	Set second = ##class(OcuTalon.Core.Trace).Join(session, .sc)
	Do $$$AssertEquals(first_"|"_second, id_"|"_id, "Join gives the same positive id twice")
	Do $$$AssertStatusOK(sc, "with an OK status")
}

/// A telegram delivery <ChatRef>:42 is found by its approval, channel and owner only.
Method TestDeliveryIsFoundByItsOwner()
{
	Set session = ..Session("deliver")
	Set other = ..Session("deliverother")
	Set chat = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set approval = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(session, "telegram", chat_":42", approval), "the delivery is recorded")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "telegram", session), chat_":42", "found for its owner as <ChatRef>:42")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "telegram", other), "", "not for another session")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "web", session), "", "not on another channel")
	Set changed = $Select($ZConvert(approval, "U") '= approval: $ZConvert(approval, "U"), 1: $ZConvert(approval, "L"))
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(changed, "telegram", session), "", "not for a case-changed approval Ref")
}

/// A fixture session of the name, recorded for the clean-up. Returns its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zztgcalls"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

}
