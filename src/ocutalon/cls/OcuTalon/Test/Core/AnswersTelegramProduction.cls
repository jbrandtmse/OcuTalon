/// Tests of AnswersIn.FromTelegram over the running production and the real approval API (Story 10.3; AD-1, AD-4, AD-11, AD-17, AD-30;
/// DW-200). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (InProduction). A fixture TelegramIn calls FromTelegram in this process as the
/// Telegram service will: the real AnswersIn service, AnswerOps and Approval.Answer answer. The fixture sessions belong to this
/// process's user and the fixture requests need a role that it holds (as in AnswersInProduction), because the README account is not this
/// process. A fixture row has no hold, so each real answer waits the 5 seconds of Approval.CompleteHoldTask for a task that never
/// appears and logs one warning, which the tests remove.
///   - TestApprovedFromTheChat: the press of the paired chat is approved with the dry run's slots; the row is approved on the channel
///     telegram by the session's IRIS user; the Approval audit entry names the session, the channel telegram and no chat id; the session's
///     stream gets one approval event; no Turn is made;
///   - TestAlreadyAnsweredAndExpired: a second press is already_answered with the winner {action, channel telegram, time}, and a request
///     past its expiry is expired with {time};
///   - TestNotAllowedWithoutTheRole: a session whose user lacks the role gets not_allowed {kind} and the row stays pending;
///   - TestUnpairedAndBadChatsLeaveTheRowPending (DW-200): an unpaired chat is not_paired, and a chat whose row holds a chat id as its
///     SessionRef is not_allowed; both leave the request pending and write no audit entry. AnswersInProduction.TestMalformedSessionRefIsNotAllowed
///     is the other half of DW-200 and stays green.
Class OcuTalon.Test.Core.AnswersTelegramProduction Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzanstgprod";

/// The longest to wait for an event or an audit entry, in seconds.
Parameter EVENTSECONDS = 20;

/// The count of chats made, for their chat ids.
Property Chats As %Integer [ InitialExpression = 0 ];

/// A press from the paired chat on the session's pending request: approved with the count and noun of its dry run. The real Answer
/// records the row as approved on the channel telegram by the session's IRIS user, writes one Approval audit entry (sessionRef the
/// session, channel telegram, no chat id), and the session's stream gets one approval event. No Turn is made.
Method TestApprovedFromTheChat()
{
	If '..Guard() Quit
	Set session = ..WebSession("a")
	Set other = ..WebSession("b")
	Set chat = ..PairedChat(session, .chatId)
	Set request = ..Request(session)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set sc = ##class(OcuTalon.Core.AnswersIn).FromTelegram(request, "approve", chat, .code, .slots)
	Do $$$AssertStatusOK(sc, "the press is handled")
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "approved|{""count"":4,""itemNoun"":{""one"":""order"",""other"":""orders""}}", "approved, with the count and the noun")
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request)
	Do $$$AssertEquals(row.State_"|"_row.AnsweredAction_"|"_row.AnsweredChannel, "approved|approve|telegram", "the row is approved from telegram")
	Do $$$AssertEquals(row.AnsweredBy, $Username, "by the session's IRIS user")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Approval", "Approval", request, "", 1, ..#EVENTSECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one Approval audit entry carries the request")
	If entries.%Size() = 1 {
		Set data = entries.%Get(0).data
		Do $$$AssertEquals(data.sessionRef_"|"_data.channel_"|"_data.irisUser, session_"|telegram|"_$Username, "it names the session, the channel telegram and the user")
		Do $$$AssertTrue((entries.%Get(0).data.%ToJSON() '[ chatId) && (entries.%Get(0).data.%ToJSON() '[ chat), "and holds neither the chat id nor the ChatRef")
	}
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "approval", 1, ..#EVENTSECONDS)
	Do $$$AssertEquals(events.%Size(), 1, "one approval event reaches the session's stream")
	If events.%Size() > 0 Do $$$AssertEquals(events.%Get(0).payload.state_"|"_events.%Get(0).payload.answeredChannel, "approved|telegram", "approved from telegram")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(other, "approval").%Size(), 0, "none reaches another session's")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Turns(session, .sc).Count(), 0, "the answer made no Turn")
	Do ..RemoveTaskWarnings(request)
}

/// A second press is already_answered with the winner's action, channel (telegram) and time; a pending request past its expiry is expired
/// with its ExpiresAt as {time}.
Method TestAlreadyAnsweredAndExpired()
{
	If '..Guard() Quit
	Set session = ..WebSession("a")
	Set chat = ..PairedChat(session)
	Set request = ..Request(session)
	Do ##class(OcuTalon.Core.AnswersIn).FromTelegram(request, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code, "approved", "control: the first press is approved")
	Do ##class(OcuTalon.Core.AnswersIn).FromTelegram(request, "reject", chat, .code, .slots)
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "already_answered|{""action"":""approve"",""channel"":""telegram"",""time"":"""_row.AnsweredAt_"""}", "a second press is already_answered, with the winner")
	Set late = ..Request(session, "pending", {"ExpiresAt": "2020-01-01T00:00:00Z"})
	Do ##class(OcuTalon.Core.AnswersIn).FromTelegram(late, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "expired|{""time"":""2020-01-01T00:00:00Z""}", "a request past its expiry is expired, with its ExpiresAt")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(late).State, "expired", "and the row is expired")
	Do ..RemoveTaskWarnings(request)
}

/// A session whose user lacks the request's role gets not_allowed with the request's kind, and the row stays pending.
Method TestNotAllowedWithoutTheRole()
{
	If '..Guard() Quit
	Set session = ..WebSession("a")
	Set chat = ..PairedChat(session)
	Set request = ..Request(session, "pending", {"RequiredRole": "ZzNoSuchRole"})
	Do ##class(OcuTalon.Core.AnswersIn).FromTelegram(request, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "not_allowed|{""kind"":""fix""}", "not_allowed, with the kind")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request).State, "pending", "and the row is still pending")
}

/// DW-200: a press from an unpaired chat is not_paired, and a press from a chat whose row holds a chat id as its SessionRef is
/// not_allowed. Neither answers the request or writes an Approval audit entry.
Method TestUnpairedAndBadChatsLeaveTheRowPending()
{
	If '..Guard() Quit
	Set session = ..WebSession("a")
	Set request = ..Request(session)
	Set chatId = ..NextChatId()
	Set chat = ##class(OcuTalon.Data.Pairing).RecordChat(chatId, "Dana", .sc)
	Set row = ##class(OcuTalon.Data.Pairing).Chat(chat)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	Set row = ""
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do ##class(OcuTalon.Core.AnswersIn).FromTelegram(request, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "not_paired|{}", "an unpaired chat is not_paired")
	Set row = ##class(OcuTalon.Data.Pairing).Chat(chat)
	Set row.SessionRef = chatId
	Do row.%Save()
	Set row = ""
	Do ##class(OcuTalon.Core.AnswersIn).FromTelegram(request, "approve", chat, .code, .slots)
	Do $$$AssertEquals(code_"|"_slots.%ToJSON(), "not_allowed|{}", "a chat whose row holds the chat id as its session is not_allowed")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request).State, "pending", "the request is still pending")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Approval", "Approval", request).%Size(), 0, "and no Approval audit entry names it")
}

/// --- helpers ---
/// A fixture session of this process's user.
Method WebSession(name As %String) As %String [ Private ]
{
	Set ref = ..Session(name)
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set row.IrisUser = $Username
	Do $$$AssertStatusOK(row.%Save(), "the fixture session "_name_" belongs to "_$Username)
	Quit ref
}

/// A role that this process's user holds.
ClassMethod HeldRole() As %String [ Private ]
{
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet($Username, .roles)
	Quit $Piece(roles, ",", 1)
}

/// The next chat id of the run.
Method NextChatId() As %String [ Private ]
{
	Set ..Chats = ..Chats + 1
	Quit "73"_..Number_"0"_..Chats
}

/// A chat row that is on the session (a fixture link), recorded for the clean-up. Returns its ChatRef, and its chat id in chatId.
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

/// A fixture request of the owner that this process's user may answer; fields change the defaults. Its Ref is kept for the clean-up.
Method Request(owner As %String, state As %String = "pending", fields As %DynamicObject = "") As %String [ Private ]
{
	Set all = {"RequiredRole": (..HeldRole())}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, "", state, , all)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// Removes the warning that an answer on a fixture row logs, for a task that never appears.
Method RemoveTaskWarnings(ref As %String) [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Type = 3 AND Text %STARTSWITH ?", "OcuTalon.Bridge.Approval: no open task of "_ref)
}

}
