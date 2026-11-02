/// Tests of AnswersIn.FromTelegram, the Telegram entry, with no production (Story 10.3; AD-1, AD-4, AD-11, AD-30; DW-200): the class
/// method runs on Test.Core.AnswersTelegramProbe, whose Deliver hands the answer to the real OnProcessInput of AnswersInProbe and
/// the ApprovalDouble, so that the double records what Approval.Answer would have received. Safe on a slot. Every test uses fixture
/// sessions, chat rows and approval requests of its own and removes them.
///   - TestApprovedAndRejected: a press from the paired chat on the session's visible request gives approved with the dry run's slots
///     {count, itemNoun}, or rejected with none; Answer gets the channel telegram, the session's Ref and the session's request Ref, never
///     the ChatRef or the chat id (DW-200), and the IRIS user is the session's;
///   - TestOtherAnswers: already_answered {action, channel, time}, expired {time} and not_allowed {kind} carry their slots;
///   - TestNoPairing: an unknown ChatRef, a code row's Ref, a case-changed ChatRef and an unpaired chat are not_paired with no hand-over;
///   - TestBadSessionRefIsNotAllowed (DW-200): a chat row whose SessionRef is not a Ref answers not_allowed with {} and hands nothing over;
///   - TestNotVisibleAndUnknown: another session's request is not_visible; an unknown, a cancelled and a malformed Ref, another
///     session's Ref in the wrong case, and the action maybe are unknown, and the malformed Refs and the bad actions hand nothing over;
///   - TestToolCallHasNoSlots: a tool-call request without a dry run is approved with {};
///   - TestHandOverErrorIsReturned: an error status of the hand-over is returned as it is, with the code unknown.
Class OcuTalon.Test.Core.AnswersTelegram Extends %UnitTest.TestCase
{

/// The probe class, whose Deliver stands in for the service.
Parameter PROBE = "OcuTalon.Test.Core.AnswersTelegramProbe";

/// The fixture owner of the sessions, and the start of the chat ids.
Parameter USER = "zzanstg";

/// The run's number.
Property Number As %Integer;

/// The count of chats made, for their chat ids.
Property Chats As %Integer [ InitialExpression = 0 ];

/// The Refs of the run's fixture rows, comma-separated.
Property Refs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Number = $Increment(^OcuTalonTest("AnswersTelegram", "n"))
	Set ..Refs = ""
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Reset()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ..Reset()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Reset()
	Quit $$$OK
}

/// A press from the paired chat on the session's own pending request: approve gives approved with count and itemNoun from the dry run,
/// reject gives rejected with {}. Approval.Answer is called once, with the request's Ref, the action, the channel telegram, the
/// session's IRIS user and the session's Ref, and never the ChatRef or the chat id.
Method TestApprovedAndRejected()
{
	Set session = ..Session("a")
	Set chat = ..PairedChat(session, .chatId)
	Set request = ..Request(session)
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
	Set sc = ..Press(request, "approve", chat, .code, .slots)
	Do $$$AssertStatusOK(sc, "the press is handled")
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "approved|{""count"":4,""itemNoun"":{""one"":""order"",""other"":""orders""}}", "approved, with the count and the noun")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 1, "Answer is called once")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "ref")_"|"_##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "action")_"|"_##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "channel"), request_"|approve|telegram", "with the request's Ref, the action and the channel telegram")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "sessionRef"), session, "and the paired session's Ref (DW-200)")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "irisUser"), ..User("a"), "and the session's IRIS user")
	For name = "ref", "action", "channel", "irisUser", "sessionRef" {
		Set value = ##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, name)
		Do $$$AssertTrue((value '= chat) && (value '= chatId), "the "_name_" is neither the ChatRef nor the chat id")
	}
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
	Do $$$AssertStatusOK(..Press(request, "reject", chat, .code, .slots), "a reject is handled")
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "rejected|{}", "rejected, with no slots")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "action")_"|"_##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "sessionRef"), "reject|"_session, "with the action reject and the session's Ref")
}

/// already_answered carries the winner {action, channel, time}, expired the request's ExpiresAt as {time}, and not_allowed (the session's
/// user lacks the role) the request's kind as {kind}.
Method TestOtherAnswers()
{
	Set session = ..Session("a")
	Set chat = ..PairedChat(session)
	Set request = ..Request(session)
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("already_answered", "{""action"":""reject"",""channel"":""web"",""at"":""2030-01-01T14:15:00Z""}")
	Do ..Press(request, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "already_answered|{""action"":""reject"",""channel"":""web"",""time"":""2030-01-01T14:15:00Z""}", "already_answered, with the winner")
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("expired")
	Do ..Press(request, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "expired|{""time"":""2030-01-02T09:00:00Z""}", "expired, with the request's ExpiresAt")
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("not_allowed")
	Do ..Press(request, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "not_allowed|{""kind"":""fix""}", "not_allowed, with the kind")
}

/// A chat with no live pairing is not_paired with {} and AnswersIn is not called: an unknown ChatRef, a code row's Ref, a case-changed
/// ChatRef, an empty one and a chat row with no session.
Method TestNoPairing()
{
	Set session = ..Session("a")
	Set paired = ..PairedChat(session)
	Set request = ..Request(session)
	Set unpaired = ##class(OcuTalon.Data.Pairing).RecordChat(..NextChatId(), "Sam", .sc)
	Do ..KeepChat(unpaired)
	Do ##class(OcuTalon.Data.Pairing).StoreCode(session, ##class(OcuTalon.Data.Pairing).HashCode("zz"_..Number), "2030-01-01T00:00:00Z")
	Set codeRow = ##class(OcuTalon.Data.Pairing).ForCode(##class(OcuTalon.Data.Pairing).HashCode("zz"_..Number))
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Adopt(codeRow)
	Set changed = $Select($ZConvert(paired, "U") '= paired: $ZConvert(paired, "U"), 1: $ZConvert(paired, "L"))
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
	For ref = ##class(OcuTalon.Bridge.Ids).NewRef(), codeRow.Ref, changed, "", unpaired {
		Do $$$AssertStatusOK(..Press(request, "approve", ref, .code, .slots), "the press is handled")
		Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "not_paired|{}", "not_paired")
	}
	Do $$$AssertEquals(..Delivers(), 0, "AnswersIn was not called")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 0, "and neither was Answer")
}

/// DW-200: a chat row whose SessionRef is not a Ref (such as the chat id itself) answers not_allowed with {}, hands nothing over, and
/// the request stays pending.
Method TestBadSessionRefIsNotAllowed()
{
	Set session = ..Session("a")
	Set request = ..Request(session)
	Set chatId = ..NextChatId()
	Set chat = ##class(OcuTalon.Data.Pairing).RecordChat(chatId, "Dana", .sc)
	Do ..KeepChat(chat)
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
	For bad = chatId, "not-a-session-ref", "!"_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 21), $Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 21) {
		Set row = ##class(OcuTalon.Data.Pairing).Chat(chat)
		Set row.SessionRef = bad
		Do row.%Save()
		Set row = ""
		Do $$$AssertStatusOK(..Press(request, "approve", chat, .code, .slots), "the press is handled")
		Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "not_allowed|{}", "a SessionRef of "_$Length(bad)_" characters is not_allowed")
	}
	Do $$$AssertEquals(..Delivers(), 0, "AnswersIn was not called")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 0, "Answer was never called")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request).State, "pending", "and the request is still pending")
}

/// Another session's request is not_visible; an unknown Ref, a cancelled request and a malformed Ref are unknown, and so is the action
/// maybe; a malformed Ref and a bad action never reach AnswersIn. All with {}, and no row changes.
Method TestNotVisibleAndUnknown()
{
	Set mine = ..Session("a")
	Set theirs = ..Session("b")
	Set chat = ..PairedChat(mine)
	Set theirRequest = ..Request(theirs)
	Set cancelled = ..Request(mine, "cancelled")
	Set mineRequest = ..Request(mine)
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
	Do ..Press(theirRequest, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "not_visible|{}", "another session's request is not_visible")
	Do ..Press(##class(OcuTalon.Bridge.Ids).NewRef(), "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "unknown|{}", "an unknown Ref is unknown")
	Do ..Press(cancelled, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "unknown|{}", "a cancelled request is unknown")
	Set changed = $Select($ZConvert(theirRequest, "L") '= theirRequest: $ZConvert(theirRequest, "L"), 1: $ZConvert(theirRequest, "U"))
	Do $$$AssertNotEquals(changed, theirRequest, "control: the changed Ref differs from the real one")
	Do ..Press(changed, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "unknown|{}", "another session's Ref in the wrong case is unknown, not not_visible")
	Do $$$AssertEquals(..Delivers(), 4, "those four were handed to AnswersIn")
	Do ..Press("zz-short", "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "unknown|{}", "a malformed Ref is unknown")
	Do ..Press("", "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "unknown|{}", "an empty Ref is unknown")
	For action = "maybe", "", "Approve", "approve,reject" {
		Do ..Press(mineRequest, action, chat, .code, .slots)
		Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "unknown|{}", "the action '"_action_"' is unknown")
	}
	Do $$$AssertEquals(..Delivers(), 4, "and those were not handed over")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 0, "Answer was never called")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(theirRequest).State_"|"_##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(mineRequest).State_"|"_##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(cancelled).State, "pending|pending|cancelled", "no request changed")
}

/// A tool-call request has no dry run: approved with {}.
Method TestToolCallHasNoSlots()
{
	Set session = ..Session("a")
	Set chat = ..PairedChat(session)
	Set request = ..Request(session, "pending", {"Kind": "tool_call", "DryRun": "", "ToolName": "zz_tool"})
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
	Do ..Press(request, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "approved|{}", "approved, with no slots")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "sessionRef"), session, "Answer got the session's Ref")
}

/// An error status of the hand-over is returned as it is, and the code is unknown.
Method TestHandOverErrorIsReturned()
{
	Set session = ..Session("a")
	Set chat = ..PairedChat(session)
	Set request = ..Request(session)
	Set ^OcuTalonTest("AnswersTelegramProbe", "fail") = 1
	Set sc = ..Press(request, "approve", chat, .code, .slots)
	Do $$$AssertStatusNotOK(sc, "the status is the error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "zz deliver failed", "the same error: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "unknown|{}", "the code is unknown, with no slots")
}

/// --- helpers ---
/// Calls FromTelegram on the probe class.
Method Press(ref As %String, action As %String, chat As %String, Output code As %String, Output slots As %DynamicObject) As %Status [ Private ]
{
	Quit $ClassMethod(..#PROBE, "FromTelegram", ref, action, chat, .code, .slots)
}

/// The number of times that the probe's Deliver ran.
Method Delivers() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("AnswersTelegramProbe", "delivers"))
}

/// Ends the double's run and clears the probe's counters.
Method Reset() [ Private ]
{
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).End()
	Kill ^OcuTalonTest("AnswersTelegramProbe")
}

/// The IRIS user of the fixture session of the name.
Method User(name As %String) As %String [ Private ]
{
	Quit ..#USER_..Number_name
}

/// A fixture session of the name, recorded for the clean-up. Returns its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session(..User(name))
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The next chat id of the run.
Method NextChatId() As %String [ Private ]
{
	Set ..Chats = ..Chats + 1
	Quit "72"_..Number_"0"_..Chats
}

/// Records the chat row for the clean-up.
Method KeepChat(chat As %String) [ Private ]
{
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_##class(OcuTalon.Test.Data.Fixture).Adopt(##class(OcuTalon.Data.Pairing).Chat(chat))
}

/// A chat row that is on the session (a fixture link, not SessionOps'), recorded for the clean-up. Returns its ChatRef, and its chat id
/// in chatId.
Method PairedChat(session As %String, Output chatId As %String) As %String [ Private ]
{
	Set chatId = ..NextChatId()
	Set chat = ##class(OcuTalon.Data.Pairing).RecordChat(chatId, "Dana", .sc)
	Set row = ##class(OcuTalon.Data.Pairing).Chat(chat)
	Set row.SessionRef = session
	Do row.%Save()
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	Quit chat
}

/// A fixture approval request of the owner, recorded for the clean-up; fields change the defaults (a fix with a dry run of 4 orders).
Method Request(owner As %String, state As %String = "pending", fields As %DynamicObject = "") As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, "", state, , fields)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

}
