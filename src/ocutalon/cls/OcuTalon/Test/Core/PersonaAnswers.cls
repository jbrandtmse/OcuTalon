/// Live tests of the answer path of a proposed persona (Story 40.6; AC1, AC3, AC4; FR-8, AD-11, AD-14, AD-32). THESE TESTS RUN IN THROWAWAY
/// STACKS AND IN CI ONLY (Rule 21), against the CI mock and its dummy token, like OcuTalon.Test.Channel.LiveCase, which they extend: BeginPairing
/// starts TelegramIn and TelegramOut with the Telegram seam on. A proposal is the real one: a ProposePersona submitted through
/// Commands.Submit inside a bridge context of the session (so its origin is tool), carried out by the real SettingsOps item, which raises the
/// request through the bridge, whose hold sends the outcome back to SettingsOps. The sessions belong to this process's user, as a page's session
/// must (Ownership.SessionRef), and the raised request's RequiredRole is set to a role that this user holds (the bridge's own role rule is
/// not under test). The chats are paired through the real /start path, and a Telegram press is a callback_query update that the mock hands to
/// TelegramIn.
///   - TestProposalReachesEveryChannel: the answer, the request's row and DryRun, the web chat's Delivery row with the rendered text and its
///     notification event, the simulated phone's message with the request's Ref, Telegram's text and its Approve and Reject buttons, and the live
///     approval payload's dryRun before and after;
///   - TestWebFirstWins: the web chat approves; a late answer from the phone and a late press from Telegram name the winner and change nothing;
///     the persona is Pirate; every copy shows the winner's status; persona.applied reaches the three channels; the audit holds one answered
///     Approval entry and one Settings persona entry;
///   - TestTelegramFirstRejects: a Telegram rejection wins; the late web and phone answers name Telegram; every copy shows the rejection, the
///     persona is unchanged and no result notice is sent;
///   - TestTelegramFirstApproves (QA): a Telegram approval wins with no toast text (a setting has no count); the late web answer names
///     Telegram; the persona is Pirate; every copy shows the approval; persona.applied reaches the channels; the audit's answered and
///     Settings entries both name the channel telegram;
///   - TestPhoneFirstApproves (QA): the simulated phone's approval wins; the late web answer and the late Telegram press name the phone;
///     the persona is Pirate; every copy shows the approval; persona.applied reaches the web chat and Telegram; the audit's answered and
///     Settings entries name the channel phone;
///   - TestStaleProposal: the persona changed after the proposal; the approval writes nothing, the request is failed and persona.stale reaches
///     the channels;
///   - TestSettingPayload: the live approval payload of a setting row, with object, string and missing old and new values.
/// The fixture chats are 84017734150 to 84017734159 (the QA tests use 84017734154 and 84017734155), and the fixture sessions zzpansw....
Class OcuTalon.Test.Core.PersonaAnswers Extends OcuTalon.Test.Channel.LiveCase
{

/// The fixture chat ids.
Parameter CHATS = "84017734150,84017734151,84017734152,84017734153,84017734154,84017734155,84017734156,84017734157,84017734158,84017734159";

/// The most seconds to wait for an asynchronous step.
Parameter SECONDS = 30;

/// The reason why every test fails, or "".
Property Missing As %String(MAXLEN = 400);

/// 1 while BeginPairing has run and EndPairing has not.
Property Begun As %Boolean [ InitialExpression = 0 ];

/// The Refs of the rows a test made (sessions), comma-separated, for Fixture.Clean.
Property Refs As %String(MAXLEN = "") [ Private ];

/// The Refs of the sessions a test made, comma-separated, whose requests and persona keys Tidy removes.
Property Owners As %String(MAXLEN = "") [ Private ];

/// The presses sent so far, for their ids.
Property Presses As %Integer [ InitialExpression = 0, Private ];

/// The run's number.
Property Number As %Integer [ Private ];

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("PersonaAnswers", "n"))
	Set ..Missing = ..BeginPairing(..#CHATS)
	Set ..Begun = (..Missing = "")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Set sc = $$$OK
	If ..Begun {
		Set ..Begun = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ..EndPairing())
		If '..WaitJobs("TelegramIn", 0) Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "TelegramIn still has a job after the class"))
	}
	Quit sc
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Owners = ""
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Tidy()
	Quit $$$OK
}

/// 1 when the class is set up; otherwise the test fails with the reason.
Method Go() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Do $$$AssertTrue(..HeldRole() '= "", "this process's user "_$Username_" holds a role")
	Quit (..HeldRole() '= "")
}

/// A role that this process's user holds.
ClassMethod HeldRole() As %String [ Private ]
{
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet($Username, .roles)
	Quit $Piece(roles, ",", 1)
}

/// Removes what the test made, on every path: its sessions' pending requests are cancelled and their holds waited out (up to SECONDS),
/// then the requests and persona keys of its sessions are deleted, then the sessions with their rows.
Method Tidy() [ Private ]
{
	Do ##class(OcuTalon.Bridge.Context).End()
	For i = 1:1:$Length(..Owners, ",") {
		Set owner = $Piece(..Owners, ",", i)
		If owner = "" Continue
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE OwnerRef = ? AND State = 'pending'", owner)
		While rs.%Next() {
			Set ref = rs.%Get("Ref")
			Do ##class(OcuTalon.Bridge.Approval).Cancel(ref)
			Set deadline = $ZHorolog + ..#SECONDS
			While (##class(OcuTalon.Bridge.Approval).LiveHold(ref) '= "") && ($ZHorolog < deadline) {
				Hang 0.25
			}
		}
		Do ##class(OcuTalon.Core.SettingsOps).ForgetPerson(owner)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE OwnerRef = ?", owner)
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Set ..Owners = ""
}

/// A fixture session (zzpansw...) of this process's user; its Ref. It is paired by the caller and removed by Tidy.
Method WebSession() As %String [ Private ]
{
	Set ref = ..NewSession("zzpansw")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set row.IrisUser = $Username
	Do $$$AssertStatusOK(row.%Save(), "the fixture session belongs to "_$Username)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	Set ..Owners = ..Owners_$Select(..Owners = "": "", 1: ",")_ref
	Quit ref
}

/// A session paired with the chat through the real /start path, and the confirmation that the chat gets waited for; the session's Ref.
Method Paired(chatId As %String, name As %String) As %String [ Private ]
{
	Set session = ..WebSession()
	Do $$$AssertTrue(..PairChat(chatId, name, session), "chat "_chatId_" is paired with its session")
	Do $$$AssertEquals(..TextsAfter(chatId, 1).%Size(), 1, "the chat got its confirmation")
	Quit session
}

/// The press of the button whose data is data, under a message of the chat; TelegramIn has handled it when this returns.
Method Press(chatId As %String, name As %String, data As %String) [ Private ]
{
	Set ..Presses = ..Presses + 1
	Do ..Send(..ButtonPress(chatId, name, 1, data, "zzpersona"_..Presses))
	Do $$$AssertTrue(..Handled(), "TelegramIn handled the press of "_chatId)
}

/// A ProposePersona with the preset, submitted through Commands.Submit inside a bridge context of the session, as a tool of its turn does.
/// The context ends on every path. The CommandResult is returned.
Method Propose(session As %String, preset As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = session
	Set request.Channel = "system"
	Set command = ##class(OcuTalon.Msg.Command.ProposePersona).%New()
	Set command.SessionRef = session
	Set command.IdempotencyKey = "zzpersona"_..Number_"-"_$Increment(^OcuTalonTest("PersonaAnswers", "key"))
	Set command.Preset = preset
	Set result = ""
	Try {
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, ""), "a context begins for the turn of the session")
		Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "tool", .result)
		Do $$$AssertStatusOK(sc, "the ProposePersona is submitted")
	} Catch ex {
		Do $$$AssertTrue(0, "the proposal threw: "_..Safe(ex))
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	If $IsObject(result) && (result.Ref '= "") {
		Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Bridge_Data.ApprovalRequest SET RequiredRole = ? WHERE Ref = ?", ..HeldRole(), result.Ref)
	}
	Quit result
}

/// The request's row.
ClassMethod Row(ref As %String) As OcuTalon.Bridge.Data.ApprovalRequest [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
}

/// The request's state, read from the table (never from an object that this process holds).
ClassMethod State(ref As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT State FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE Ref = ?", ref)
	Quit $Select(rs.%Next(): rs.%Get("State"), 1: "")
}

/// Waits until the request is in the state, up to SECONDS; the state it has.
Method WaitRequest(ref As %String, state As %String) As %String [ Private ]
{
	Set deadline = $ZHorolog + ..#SECONDS
	For {
		Set now = ..State(ref)
		If (now = state) || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit now
}

/// The three persona values of the session, as preset|language|custom, "(none)" for a key with no row.
ClassMethod Keys(session As %String) As %String [ Private ]
{
	Set values = ""
	For name = "preset", "language", "custom" {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(##class(OcuTalon.Core.SettingsOps).PersonaKey(session, name))
		Set values = values_$Select(name = "preset": "", 1: "|")_$Select($IsObject(row): row.Value, 1: "(none)")
	}
	Quit values
}

/// The web chat's Delivery rows of the session for the request, in order, as "kind:text" joined by ";".
ClassMethod Web(session As %String, ref As %String) As %String [ Private ]
{
	Set text = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Kind, Text FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND Channel = 'web' AND ApprovalRef = ? ORDER BY ID", session, ref)
	While rs.%Next() {
		Set text = text_$Select(text = "": "", 1: ";")_rs.%Get("Kind")_":"_rs.%Get("Text")
	}
	Quit text
}

/// Waits until the web chat has count Delivery rows for the request, up to SECONDS; the rows as Web gives them.
Method WaitWeb(session As %String, ref As %String, count As %Integer) As %String [ Private ]
{
	Set deadline = $ZHorolog + ..#SECONDS
	For {
		Set rows = ..Web(session, ref)
		If (rows '= "") && ($Length(rows, ";") >= count) || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit rows
}

/// The simulated phone's message of the session for the request ("" when it has none).
ClassMethod Phone(session As %String, ref As %String) As OcuTalon.Data.SimMessage [ Private ]
{
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 100)
	Set found = ""
	For i = 1:1:rows.Count() {
		If rows.GetAt(i).ApprovalRef = ref Set found = rows.GetAt(i) Quit
	}
	Quit found
}

/// The texts of the simulated phone's messages of the session, joined by ";".
ClassMethod PhoneTexts(session As %String) As %String [ Private ]
{
	Set text = ""
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 100)
	For i = 1:1:rows.Count() {
		Set text = text_$Select(text = "": "", 1: ";")_rows.GetAt(i).Text
	}
	Quit text
}

/// Waits until the phone has the request's message, up to SECONDS; the message or "".
Method WaitPhone(session As %String, ref As %String) As OcuTalon.Data.SimMessage [ Private ]
{
	Set deadline = $ZHorolog + ..#SECONDS
	For {
		Set message = ..Phone(session, ref)
		If $IsObject(message) || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit message
}

/// Waits until the phone's message of the request has an Answer, up to SECONDS; the Answer.
Method WaitAnswer(session As %String, ref As %String) As %String [ Private ]
{
	Set deadline = $ZHorolog + ..#SECONDS
	For {
		Set message = ..Phone(session, ref)
		Set answer = $Select($IsObject(message): message.Answer, 1: "")
		If (answer '= "") || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit answer
}

/// Waits until the chat has count edits, up to SECONDS; the edits.
Method WaitEdits(chatId As %String, count As %Integer) As %DynamicArray [ Private ]
{
	Set deadline = $ZHorolog + ..#SECONDS
	For {
		Set edits = ..EditsTo(chatId)
		If (edits.%Size() >= count) || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit edits
}

/// A time as the catalog puts it after "Approved from Telegram" and the like: "at 14:15" for a time today, "on Jan 1, 2020 at 00:00" for a
/// dated one, each with " ET" on the online demo.
ClassMethod Shown(utc As %String) As %String [ Private ]
{
	Set clock = ##class(OcuTalon.Data.Time).ForMessage(utc)
	Quit $Select(clock '? 2N1":"2N: "on ", 1: "at ")_clock_$Select(+##class(OcuTalon.Data.Public.Settings).Get("onlineDemo"): " ET", 1: "")
}

/// Calls AnswersIn.FromPage for the request with the action and channel, as the session's page does; the AnswerResult (or "").
Method FromPageAs(session As %String, ref As %String, action As %String, channel As %String) As OcuTalon.Core.Msg.AnswerResult [ Private ]
{
	New %session
	Set %session = ##class(%CSP.Session).%New("ZzPersonaAnswers"_..Number, 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	Set sc = ##class(OcuTalon.Core.AnswersIn).FromPage(ref, action, channel, .result, .answeringRef)
	Do $$$AssertStatusOK(sc, "the "_channel_" answer reaches AnswersIn: "_$Select($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: ""))
	If '$IsObject($Get(result)) Quit ""
	Quit result
}

/// The fields of an AnswerResult as text, for a failed assertion's label.
ClassMethod Said(result As OcuTalon.Core.Msg.AnswerResult) As %String [ Private ]
{
	If '$IsObject(result) Quit "none"
	Quit result.Result_"|"_result.WinnerAction_"|"_result.WinnerChannel_"|"_result.WinnerAt
}

/// The count of entries of the audit type for the marker (a Ref) since the mark whose data.change is the change ("" for any).
ClassMethod Entries(mark As %String, type As %String, marker As %String, change As %String = "") As %DynamicArray [ Private ]
{
	Set found = []
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", type, type, marker)
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If $IsObject(entry.data) && ((change = "") || (entry.data.change = change)) Do found.%Push(entry)
	}
	Quit found
}

/// The DryRun of a proposal from professional, as the row holds it.
ClassMethod DryRun(session As %String, newPreset As %String, newText As %String) As %String [ Private ]
{
	Quit "{""key"":""person."_session_".persona"",""ownerRef"":"""_session_""",""old"":{""preset"":""professional"",""language"":"""",""custom"":"""",""text"":""Professional (default)""},""new"":{""preset"":"""_newPreset_""",""language"":"""",""custom"":"""",""text"":"""_newText_"""}}"
}

/// The text of the approval.persona notice for Professional and Pirate.
ClassMethod ProposalText() As %String [ Private ]
{
	Quit "OcuTalon suggests a new persona for you. Now: Professional (default). Proposed: Pirate. Nothing changes unless you approve."
}

/// AC1: one proposal reaches the web chat, the simulated phone and the paired chat, with the request's Ref, and nothing is written.
Method TestProposalReachesEveryChannel()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734150
		Set session = ..Paired(chatId, "Zqpropose")
		Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set sends = ..CallsOf("sendMessage").%Size()
		Set result = ..Propose(session, "pirate")
		If '$IsObject(result) Quit
		Set ref = result.Ref
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|proposed", "Ok 1, proposed")
		Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).IsRef(ref), "the answer holds the request's Ref")
		Do $$$AssertEquals(result.Message, "OcuTalon suggested a change. It waits for your answer in Approval requests.", "and the pending note")
		Set row = ..Row(ref)
		Do $$$AssertTrue($IsObject(row), "the request exists")
		If '$IsObject(row) Quit
		Do $$$AssertEquals(row.Kind_"|"_row.State_"|"_row.OwnerRef_"|"_row.ResultTarget_"|"_row.TraceRef, "setting|pending|"_session_"|SettingsOps|"_trace, "a pending setting request of the session, for SettingsOps, in its trace")
		Do $$$AssertEquals(row.DryRun, ..DryRun(session, "pirate", "Pirate"), "its DryRun holds the old and new objects")
		Do $$$AssertEquals(..Keys(session), "(none)|(none)|(none)", "no persona key is written")
		Do $$$AssertEquals(..Entries(audit, "Settings", session).%Size(), 0, "and no Settings entry")

		// The web chat.
		Set rows = ..WaitWeb(session, ref, 1)
		Do $$$AssertEquals(rows, "approval:"_..ProposalText(), "the web chat's row is the approval notice with its rendered text")
		Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "notification", 1, ..#SECONDS)
		Do $$$AssertEquals(events.%Size(), 1, "one notification event reaches the stream")
		If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.approvalRef_"|"_events.%Get(0).payload.kind_"|"_events.%Get(0).payload.text, ref_"|approval|"_..ProposalText(), "with the Ref, the kind and the text")

		// The simulated phone.
		Set message = ..WaitPhone(session, ref)
		Do $$$AssertTrue($IsObject(message), "the simulated phone has the request's message")
		If $IsObject(message) Do $$$AssertEquals(message.ApprovalRef_"|"_message.Answer, ref_"|", "with its Ref and no answer yet")

		// Telegram.
		Set calls = ..WaitCalls("sendMessage", sends + 1, ..#SECONDS)
		Do $$$AssertEquals(calls.%Size(), sends + 1, "Telegram gets the notice")
		If calls.%Size() = (sends + 1) Do $$$AssertEquals(calls.%Get(sends).params.text, ..ProposalText(), "with the catalog's text")
		Set keyboard = ..KeyboardTo(chatId)
		Do $$$AssertEquals($Select($IsObject(keyboard): keyboard.%ToJSON(), 1: ""), {"inline_keyboard": [[{"text": "Approve", "callback_data": ("approve:"_ref)}, {"text": "Reject", "callback_data": ("reject:"_ref)}]]}.%ToJSON(), "and the Approve and Reject buttons")

		// The live approval payload.
		Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(row, session)
		Do $$$AssertEquals(payload.Kind_"|"_payload.State_"|"_payload.DryRun.Before_"|"_payload.DryRun.After, "setting|pending|Professional (default)|Pirate", "the live payload's dryRun holds the old and new texts as before and after")
	} Catch ex {
		Do $$$AssertTrue(0, "the proposal test failed: "_..Safe(ex))
	}
}

/// AC3, AC4: the web chat answers first. The phone and Telegram answers are late and name the web chat; the persona is Pirate; every copy
/// shows the winner's status; persona.applied reaches the three channels; the audit holds one answered entry and one Settings entry.
Method TestWebFirstWins()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734151
		Set session = ..Paired(chatId, "Zqwebfirst")
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set sends = ..CallsOf("sendMessage").%Size()
		Set result = ..Propose(session, "pirate")
		If '$IsObject(result) Quit
		Set ref = result.Ref
		Do $$$AssertEquals(result.Outcome, "proposed", "proposed")
		Do $$$AssertTrue($IsObject(..WaitPhone(session, ref)), "the phone has the request")
		Set calls = ..WaitCalls("sendMessage", sends + 1, ..#SECONDS)
		Do $$$AssertEquals(calls.%Size(), sends + 1, "Telegram has the request")
		If calls.%Size() < (sends + 1) Quit
		Set sent = calls.%Get(sends).params.text

		Set won = ..FromPageAs(session, ref, "approve", "web")
		Do $$$AssertEquals($Select($IsObject(won): won.Result, 1: "(none)"), "done", "the web chat's approval is the first answer ["_..Said(won)_"]")
		Do $$$AssertEquals(..WaitRequest(ref, "done"), "done", "the request is done")
		Set row = ..Row(ref)
		Do $$$AssertEquals(row.AnsweredChannel_"|"_row.AnsweredBy_"|"_row.Result, "web|"_$Username_"|done", "answered from the web by the session's user")
		Set at = row.AnsweredAt
		Do $$$AssertEquals(..Keys(session), "pirate||", "the persona is Pirate")

		Set late = ..FromPageAs(session, ref, "approve", "phone")
		Do $$$AssertEquals(late.Result_"|"_late.WinnerAction_"|"_late.WinnerChannel_"|"_late.WinnerAt, "already_answered|approve|web|"_at, "the phone's answer is late and names the web chat ["_..Said(late)_"]")
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(chatId, "Zqwebfirst", "reject:"_ref)
		Set found = ..WaitAnswers(answers, 1)
		Do $$$AssertEquals(found.%Size(), 1, "the press is answered")
		If found.%Size() = 1 {
			Do $$$AssertEquals(found.%Get(0).text, "Already answered: approved from the web chat "_..Shown(at)_".", "with the winner's action, channel and time")
			Do $$$AssertEquals(+found.%Get(0)."show_alert", 1, "as an alert")
		}
		Do $$$AssertEquals(..State(ref), "done", "the late answers changed nothing")

		// Every copy shows the winner's status.
		Set status = "Approved from the web chat "_..Shown(at)_"."
		Set edits = ..WaitEdits(chatId, 1)
		Do $$$AssertEquals(edits.%Size(), 1, "the Telegram copy is edited once")
		If edits.%Size() = 1 Do $$$AssertEquals(edits.%Get(0).text, sent_$Char(10, 10)_status, "with the status as its last line")
		Do $$$AssertEquals(..WaitAnswer(session, ref), status, "the phone copy's Answer is the status")
		Set rows = ..WaitWeb(session, ref, 3)
		Do $$$AssertEquals($Piece(rows, ";", 1), "approval:"_..ProposalText(), "the web chat: the approval notice")
		Do $$$AssertEquals($Piece(rows, ";", 2), "answered:", "then the answered notice (the page draws its status from the request)")
		Do $$$AssertEquals($Piece(rows, ";", 3), "result:Persona updated. It applies from your next message.", "then persona.applied")

		// persona.applied reaches the phone and Telegram.
		Set calls = ..WaitCalls("sendMessage", sends + 2, ..#SECONDS)
		Do $$$AssertEquals(calls.%Size(), sends + 2, "Telegram gets one new message")
		If calls.%Size() = (sends + 2) Do $$$AssertEquals(calls.%Get(sends + 1).params.text, "Persona updated. It applies from your next message.", "persona.applied")
		Set deadline = $ZHorolog + ..#SECONDS
		For {
			If (..PhoneTexts(session) [ "Persona updated. It applies from your next message.") || ($ZHorolog >= deadline) Quit
			Hang 0.25
		}
		Do $$$AssertTrue(..PhoneTexts(session) [ "Persona updated. It applies from your next message.", "persona.applied reaches the phone")

		// The audit.
		Set answered = ..Entries(audit, "Approval", ref, "answered")
		Do $$$AssertEquals(answered.%Size(), 1, "one answered Approval entry names the request")
		If answered.%Size() = 1 Do $$$AssertEquals(answered.%Get(0).data.channel_"|"_answered.%Get(0).data.sessionRef_"|"_answered.%Get(0).data.irisUser, "web|"_session_"|"_$Username, "from the web, for the session, by its user")
		Set settings = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(audit, "OcuTalon", "Settings", "Settings", session, "", 1, ..#SECONDS)
		Do $$$AssertEquals(settings.%Size(), 1, "one Settings entry names the session")
		If settings.%Size() = 1 Do $$$AssertEquals(settings.%Get(0).data.setting_"|"_settings.%Get(0).data.from_"|"_settings.%Get(0).data.to_"|"_settings.%Get(0).data.channel_"|"_settings.%Get(0).data.irisUser, "persona|professional|pirate|web|"_$Username, "persona, professional to pirate, approved from the web by the session's user")
		Do $$$AssertEquals(..Entries(audit, "Approval", ref, "answered").%Size(), 1, "the late answers wrote no answered entry")
	} Catch ex {
		Do $$$AssertTrue(0, "the web-first test failed: "_..Safe(ex))
	}
}

/// AC3, AC4: Telegram rejects first. The web and phone answers are late and name Telegram; every copy shows the rejection; the persona is
/// unchanged; no result notice is sent; the audit holds one answered entry.
Method TestTelegramFirstRejects()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734152
		Set session = ..Paired(chatId, "Zqtgfirst")
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set sends = ..CallsOf("sendMessage").%Size()
		Set result = ..Propose(session, "pirate")
		If '$IsObject(result) Quit
		Set ref = result.Ref
		Do $$$AssertEquals(result.Outcome, "proposed", "proposed")
		Do $$$AssertTrue($IsObject(..WaitPhone(session, ref)), "the phone has the request")
		Set calls = ..WaitCalls("sendMessage", sends + 1, ..#SECONDS)
		Do $$$AssertEquals(calls.%Size(), sends + 1, "Telegram has the request")
		If calls.%Size() < (sends + 1) Quit
		Set sent = calls.%Get(sends).params.text

		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(chatId, "Zqtgfirst", "reject:"_ref)
		Set found = ..WaitAnswers(answers, 1)
		Do $$$AssertEquals(found.%Size(), 1, "the press is answered")
		If found.%Size() = 1 Do $$$AssertEquals($Select(found.%Get(0).%IsDefined("text"): found.%Get(0).text, 1: "(no text)")_"|"_+found.%Get(0)."show_alert", "Rejected. Nothing was changed.|0", "with the rejection's text and no alert")
		Do $$$AssertEquals(..WaitRequest(ref, "rejected"), "rejected", "the request is rejected")
		Set row = ..Row(ref)
		Set at = row.AnsweredAt
		Do $$$AssertEquals(row.AnsweredChannel_"|"_row.AnsweredAction, "telegram|reject", "from Telegram")
		Set web = ..FromPageAs(session, ref, "approve", "web")
		Do $$$AssertEquals(web.Result_"|"_web.WinnerAction_"|"_web.WinnerChannel, "already_answered|reject|telegram", "the web chat's answer is late and names Telegram ["_..Said(web)_"]")
		Set phone = ..FromPageAs(session, ref, "approve", "phone")
		Do $$$AssertEquals(phone.Result_"|"_phone.WinnerAction_"|"_phone.WinnerChannel, "already_answered|reject|telegram", "so is the phone's ["_..Said(phone)_"]")

		Set status = "Rejected from Telegram "_..Shown(at)_". Nothing was changed."
		Set edits = ..WaitEdits(chatId, 1)
		Do $$$AssertEquals(edits.%Size(), 1, "the Telegram copy is edited once")
		If edits.%Size() = 1 Do $$$AssertEquals(edits.%Get(0).text, sent_$Char(10, 10)_status, "with the rejection as its last line")
		Do $$$AssertEquals(..WaitAnswer(session, ref), status, "the phone copy's Answer is the rejection")
		Set rows = ..WaitWeb(session, ref, 2)
		Do $$$AssertEquals($Piece(rows, ";", 2), "answered:", "the web chat has the answered notice")
		Hang 2
		Do $$$AssertEquals(..Web(session, ref), "approval:"_..ProposalText()_";answered:", "and no result notice")
		Do $$$AssertEquals(..Keys(session), "(none)|(none)|(none)", "the persona is unchanged")
		Do $$$AssertEquals(..State(ref), "rejected", "the request stays rejected")
		Do $$$AssertEquals(..Entries(audit, "Approval", ref, "answered").%Size(), 1, "one answered entry")
		Do $$$AssertEquals(..Entries(audit, "Settings", session).%Size(), 0, "and no Settings entry")
	} Catch ex {
		Do $$$AssertTrue(0, "the Telegram-first test failed: "_..Safe(ex))
	}
}

/// AC3, AC4 (QA): Telegram approves first. The press is answered with no text and no alert (a setting has no count, so there is no
/// toast); the late web answer names Telegram; the persona is Pirate; every copy shows the approval; persona.applied reaches the channels;
/// the audit holds one answered entry and one Settings entry, each naming the channel telegram.
Method TestTelegramFirstApproves()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734154
		Set session = ..Paired(chatId, "Zqtgapprove")
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set sends = ..CallsOf("sendMessage").%Size()
		Set result = ..Propose(session, "pirate")
		If '$IsObject(result) Quit
		Set ref = result.Ref
		Do $$$AssertEquals(result.Outcome, "proposed", "proposed")
		Do $$$AssertTrue($IsObject(..WaitPhone(session, ref)), "the phone has the request")
		Set calls = ..WaitCalls("sendMessage", sends + 1, ..#SECONDS)
		Do $$$AssertEquals(calls.%Size(), sends + 1, "Telegram has the request")
		If calls.%Size() < (sends + 1) Quit
		Set sent = calls.%Get(sends).params.text

		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(chatId, "Zqtgapprove", "approve:"_ref)
		Set found = ..WaitAnswers(answers, 1)
		Do $$$AssertEquals(found.%Size(), 1, "the press is answered")
		If found.%Size() = 1 Do $$$AssertEquals($Select(found.%Get(0).%IsDefined("text"): found.%Get(0).text, 1: "(no text)")_"|"_+found.%Get(0)."show_alert", "(no text)|0", "with no text and no alert: a setting has no count to report")
		Do $$$AssertEquals(..WaitRequest(ref, "done"), "done", "the request is done")
		Set row = ..Row(ref)
		Set at = row.AnsweredAt
		Do $$$AssertEquals(row.AnsweredChannel_"|"_row.AnsweredAction_"|"_row.AnsweredBy, "telegram|approve|"_$Username, "approved from Telegram by the session's user")
		Do $$$AssertEquals(..Keys(session), "pirate||", "the persona is Pirate")
		Set web = ..FromPageAs(session, ref, "reject", "web")
		Do $$$AssertEquals(web.Result_"|"_web.WinnerAction_"|"_web.WinnerChannel_"|"_web.WinnerAt, "already_answered|approve|telegram|"_at, "the web chat's answer is late and names Telegram ["_..Said(web)_"]")
		Do $$$AssertEquals(..Keys(session), "pirate||", "the late rejection changed nothing")

		Set status = "Approved from Telegram "_..Shown(at)_"."
		Set edits = ..WaitEdits(chatId, 1)
		Do $$$AssertEquals(edits.%Size(), 1, "the Telegram copy is edited once")
		If edits.%Size() = 1 Do $$$AssertEquals(edits.%Get(0).text, sent_$Char(10, 10)_status, "with the approval as its last line")
		Do $$$AssertEquals(..WaitAnswer(session, ref), status, "the phone copy's Answer is the approval")
		Set rows = ..WaitWeb(session, ref, 3)
		Do $$$AssertEquals($Piece(rows, ";", 2)_"|"_$Piece(rows, ";", 3), "answered:|result:Persona updated. It applies from your next message.", "the web chat: the answered notice, then persona.applied")
		Set calls = ..WaitCalls("sendMessage", sends + 2, ..#SECONDS)
		Do $$$AssertEquals(calls.%Size(), sends + 2, "Telegram gets one new message")
		If calls.%Size() = (sends + 2) Do $$$AssertEquals(calls.%Get(sends + 1).params.text, "Persona updated. It applies from your next message.", "persona.applied")

		Set answered = ..Entries(audit, "Approval", ref, "answered")
		Do $$$AssertEquals(answered.%Size(), 1, "one answered Approval entry names the request")
		If answered.%Size() = 1 Do $$$AssertEquals(answered.%Get(0).data.channel_"|"_answered.%Get(0).data.sessionRef, "telegram|"_session, "from Telegram, for the session")
		Set settings = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(audit, "OcuTalon", "Settings", "Settings", session, "", 1, ..#SECONDS)
		Do $$$AssertEquals(settings.%Size(), 1, "one Settings entry names the session")
		If settings.%Size() = 1 Do $$$AssertEquals(settings.%Get(0).data.setting_"|"_settings.%Get(0).data.from_"|"_settings.%Get(0).data.to_"|"_settings.%Get(0).data.channel_"|"_settings.%Get(0).data.irisUser, "persona|professional|pirate|telegram|"_$Username, "persona, professional to pirate, approved from Telegram")
	} Catch ex {
		Do $$$AssertTrue(0, "the Telegram-first approval test failed: "_..Safe(ex))
	}
}

/// AC3, AC4 (QA): the simulated phone approves first. The late web answer and the late Telegram press name the phone; the persona is Pirate;
/// every copy shows the approval; the audit holds one answered entry and one Settings entry, each naming the channel phone.
Method TestPhoneFirstApproves()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734155
		Set session = ..Paired(chatId, "Zqphapprove")
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set sends = ..CallsOf("sendMessage").%Size()
		Set result = ..Propose(session, "pirate")
		If '$IsObject(result) Quit
		Set ref = result.Ref
		Do $$$AssertEquals(result.Outcome, "proposed", "proposed")
		Do $$$AssertTrue($IsObject(..WaitPhone(session, ref)), "the phone has the request")
		Set calls = ..WaitCalls("sendMessage", sends + 1, ..#SECONDS)
		Do $$$AssertEquals(calls.%Size(), sends + 1, "Telegram has the request")
		If calls.%Size() < (sends + 1) Quit
		Set sent = calls.%Get(sends).params.text

		Set won = ..FromPageAs(session, ref, "approve", "phone")
		Do $$$AssertEquals($Select($IsObject(won): won.Result, 1: "(none)"), "done", "the phone's approval is the first answer ["_..Said(won)_"]")
		Do $$$AssertEquals(..WaitRequest(ref, "done"), "done", "the request is done")
		Set row = ..Row(ref)
		Set at = row.AnsweredAt
		Do $$$AssertEquals(row.AnsweredChannel_"|"_row.AnsweredAction_"|"_row.AnsweredBy, "phone|approve|"_$Username, "approved from the phone by the session's user")
		Do $$$AssertEquals(..Keys(session), "pirate||", "the persona is Pirate")
		Set web = ..FromPageAs(session, ref, "reject", "web")
		Do $$$AssertEquals(web.Result_"|"_web.WinnerAction_"|"_web.WinnerChannel_"|"_web.WinnerAt, "already_answered|approve|phone|"_at, "the web chat's answer is late and names the phone ["_..Said(web)_"]")
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(chatId, "Zqphapprove", "reject:"_ref)
		Set found = ..WaitAnswers(answers, 1)
		Do $$$AssertEquals(found.%Size(), 1, "the press is answered")
		If found.%Size() = 1 {
			Do $$$AssertEquals(found.%Get(0).text, "Already answered: approved from the simulated phone "_..Shown(at)_".", "with the winner's action, channel and time")
			Do $$$AssertEquals(+found.%Get(0)."show_alert", 1, "as an alert")
		}
		Do $$$AssertEquals(..Keys(session), "pirate||", "the late rejections changed nothing")
		Do $$$AssertEquals(..State(ref), "done", "and the request stays done")

		Set status = "Approved from the simulated phone "_..Shown(at)_"."
		Set edits = ..WaitEdits(chatId, 1)
		Do $$$AssertEquals(edits.%Size(), 1, "the Telegram copy is edited once")
		If edits.%Size() = 1 Do $$$AssertEquals(edits.%Get(0).text, sent_$Char(10, 10)_status, "with the approval as its last line")
		Do $$$AssertEquals(..WaitAnswer(session, ref), status, "the phone copy's Answer is the approval")
		Set rows = ..WaitWeb(session, ref, 3)
		Do $$$AssertEquals($Piece(rows, ";", 2)_"|"_$Piece(rows, ";", 3), "answered:|result:Persona updated. It applies from your next message.", "the web chat: the answered notice, then persona.applied")
		Set calls = ..WaitCalls("sendMessage", sends + 2, ..#SECONDS)
		Do $$$AssertEquals(calls.%Size(), sends + 2, "Telegram gets one new message")
		If calls.%Size() = (sends + 2) Do $$$AssertEquals(calls.%Get(sends + 1).params.text, "Persona updated. It applies from your next message.", "persona.applied")

		Set answered = ..Entries(audit, "Approval", ref, "answered")
		Do $$$AssertEquals(answered.%Size(), 1, "one answered Approval entry names the request")
		If answered.%Size() = 1 Do $$$AssertEquals(answered.%Get(0).data.channel_"|"_answered.%Get(0).data.sessionRef, "phone|"_session, "from the phone, for the session")
		Set settings = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(audit, "OcuTalon", "Settings", "Settings", session, "", 1, ..#SECONDS)
		Do $$$AssertEquals(settings.%Size(), 1, "one Settings entry names the session")
		If settings.%Size() = 1 Do $$$AssertEquals(settings.%Get(0).data.setting_"|"_settings.%Get(0).data.from_"|"_settings.%Get(0).data.to_"|"_settings.%Get(0).data.channel_"|"_settings.%Get(0).data.irisUser, "persona|professional|pirate|phone|"_$Username, "persona, professional to pirate, approved from the phone")
	} Catch ex {
		Do $$$AssertTrue(0, "the phone-first approval test failed: "_..Safe(ex))
	}
}

/// AC3: the persona changed after the proposal. Approving it writes nothing: the request is failed, persona.stale reaches the channels
/// after the answered notice and the persona stays as it was.
Method TestStaleProposal()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734153
		Set session = ..Paired(chatId, "Zqstale")
		Set sends = ..CallsOf("sendMessage").%Size()
		Set result = ..Propose(session, "pirate")
		If '$IsObject(result) Quit
		Set ref = result.Ref
		Do $$$AssertEquals(result.Outcome, "proposed", "proposed")
		Do $$$AssertTrue($IsObject(..WaitPhone(session, ref)), "the phone has the request")
		Set calls = ..WaitCalls("sendMessage", sends + 1, ..#SECONDS)
		Do $$$AssertEquals(calls.%Size(), sends + 1, "Telegram has the request")
		Set command = ##class(OcuTalon.Msg.Command.SetPersona).%New()
		Set command.SessionRef = session
		Set command.IdempotencyKey = "zzpersona"_..Number_"-"_$Increment(^OcuTalonTest("PersonaAnswers", "key"))
		Set command.Preset = "kindfriend"
		Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .saved)
		Do $$$AssertStatusOK(sc, "the persona is changed from the page")
		Do $$$AssertEquals($Select($IsObject($Get(saved)): saved.Outcome, 1: "(none)"), "saved", "and saved")
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()

		Set won = ..FromPageAs(session, ref, "approve", "web")
		Do $$$AssertEquals(won.Result, "done", "the approval is the first answer ["_..Said(won)_"]")
		Do $$$AssertEquals(..WaitRequest(ref, "failed"), "failed", "the request is failed: nothing was applied")
		Do $$$AssertEquals(..Keys(session), "kindfriend||", "the persona stays Kind friend")
		Set rows = ..WaitWeb(session, ref, 3)
		Do $$$AssertEquals($Piece(rows, ";", 2)_"|"_$Piece(rows, ";", 3), "answered:|result:Your persona changed after this was suggested. Nothing was changed.", "the web chat: the answered notice, then persona.stale")
		Set calls = ..WaitCalls("sendMessage", sends + 2, ..#SECONDS)
		Do $$$AssertEquals(calls.%Size(), sends + 2, "Telegram gets one new message")
		If calls.%Size() = (sends + 2) Do $$$AssertEquals(calls.%Get(sends + 1).params.text, "Your persona changed after this was suggested. Nothing was changed.", "persona.stale")
		Set deadline = $ZHorolog + ..#SECONDS
		For {
			If (..PhoneTexts(session) [ "Your persona changed after this was suggested.") || ($ZHorolog >= deadline) Quit
			Hang 0.25
		}
		Do $$$AssertTrue(..PhoneTexts(session) [ "Your persona changed after this was suggested.", "persona.stale reaches the phone")
		Do $$$AssertEquals(..Entries(audit, "Settings", session).%Size(), 0, "nothing was audited for the stale approval")
	} Catch ex {
		Do $$$AssertTrue(0, "the stale test failed: "_..Safe(ex))
	}
}

/// The live approval payload of a setting row (Story 40.6): dryRun.before and after are the objects' text, the strings, or "" when old or new
/// is missing; every fix field is empty and eitherWay is false.
Method TestSettingPayload()
{
	Set cases = $ListBuild($ListBuild("objects", "{""key"":""person.K.persona"",""ownerRef"":""K"",""old"":{""preset"":""professional"",""language"":"""",""custom"":"""",""text"":""Professional (default)""},""new"":{""preset"":""language"",""language"":""Spanish"",""custom"":"""",""text"":""Spanish""}}", "Professional (default)", "Spanish"))
	Set cases = cases_$ListBuild($ListBuild("strings", "{""key"":""person.K.persona"",""ownerRef"":""K"",""old"":""Professional"",""new"":""Pirate""}", "Professional", "Pirate"))
	Set cases = cases_$ListBuild($ListBuild("missing", "{""key"":""person.K.persona"",""ownerRef"":""K""}", "", ""))
	Set cases = cases_$ListBuild($ListBuild("one missing", "{""key"":""person.K.persona"",""ownerRef"":""K"",""old"":{""text"":""Pirate""},""new"":{""preset"":""pirate""}}", "Pirate", ""))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).%New()
		Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set row.Kind = "setting"
		Set row.State = "pending"
		Set row.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set row.DryRun = $List(case, 2)
		Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(row)
		Set label = $List(case, 1)
		Do $$$AssertTrue($IsObject(payload.DryRun), label_": the payload has a dry run part")
		If '$IsObject(payload.DryRun) Continue
		Set part = payload.DryRun
		Do $$$AssertEquals(part.Before_"|"_part.After, $List(case, 3)_"|"_$List(case, 4), label_": before and after")
		Do $$$AssertEquals(part.Affected_"|"_part.Resend_"|"_part.LeftOut_"|"_part.Field_"|"_part.Reading_"|"_part.EitherWay_"|"_$IsObject(part.ItemNoun), "|||||0|0", label_": every fix field is empty and eitherWay is false")
	}
}

}
