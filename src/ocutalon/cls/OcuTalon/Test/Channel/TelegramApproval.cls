/// Live tests of the Telegram approval path (Story 12.7; AC1 to AC4; FR-8, FR-20, AD-11, AD-14, AD-32). THESE TESTS RUN IN THROWAWAY
/// STACKS AND IN CI ONLY (Rule 21), against the CI mock and its dummy token, like OcuTalon.Test.Channel.LiveCase, which they extend:
/// BeginPairing starts TelegramIn and TelegramOut with the Telegram seam on. The requests are OcuTalon.Test.Data.Fixture.Approval rows of
/// sessions that belong to this process's user, with a role that it holds, as OcuTalon.Test.Core.AnswersTelegramProduction makes them (a
/// fixture row has no hold, so each real answer waits 5 seconds for a task that never appears and logs one warning, which every test
/// removes). The chats are paired through the real /start path, and a press is a callback_query update that the mock hands to TelegramIn.
///   - TestApprove: the paired chat's press of approve:<Ref> is answered "Approved. Repairing and resending 50 orders." with no alert; the
///     request is approved on the channel telegram by the session's IRIS user; the audit entry names the channel and holds neither the chat id
///     nor the chat's name; no Turn is made and no chat message is sent;
///   - TestApproveKinds (Story 23.2): the Approve of a suspend, a resume and a reroute is answered "Approved. Suspending {item}.", "Approved. Resuming {item}." and
///     "Approved. Rerouting {count} {itemNoun} to {to}."; Story 23.5: that of a partner delay notice is answered "Approved. Sending the delay notice to the Simulated mailbox.";
///   - TestReject: reject:<Ref> is answered "Rejected. Nothing was changed." and the request is rejected;
///   - TestLate: a press after another channel answered is an alert "Already answered: approved from the web chat at <time>." (the winner's
///     action and channel, also rejected from the simulated phone), and both requests stay as they were;
///   - TestExpired: a press on a request past its expiry is an alert "Expired at <time>. Nothing was changed." and the request becomes
///     expired with no answer and no answered audit entry;
///   - TestNotPairedChat: a press of an unpaired chat, and of a chat paired with another session, is the alert "Only the paired chat can
///     answer this request." and the request stays pending with no audit entry;
///   - TestUnknown: a press for a Ref nobody has, one with no ":" and one with no Ref are the alert "That request is no longer
///     available."; a press with no id gets no answer and one warning;
///   - TestApproveNoDryRun: approving a request with no dry run answers the press with no text and no alert, and approves it; a press on
///     a request whose role the session's user lacks (not_allowed) is answered with no text and no alert, with one warning, and the request
///     stays pending;
///   - TestEveryCopy: an incident notice, its answered notification and its result through Notify: Telegram and the simulated phone both get
///     the notice (Telegram with the buttons), and within 5 seconds the Telegram message is edited with the status and the phone message
///     shows it as its answer; the result follows as one new chat message.
///   - TestPressAnswerFails (QA): when Telegram refuses the answer to a press (a 400), the request is still answered, TelegramIn logs one
///     warning that names no Ref, chat id, name or callback data, and the next press is answered as usual;
/// The fixture chats are 84017734140 to 84017734149, and the fixture sessions zztgappr....
Class OcuTalon.Test.Channel.TelegramApproval Extends OcuTalon.Test.Channel.LiveCase
{

/// The fixture chat ids.
Parameter CHATS = "84017734140,84017734141,84017734142,84017734143,84017734144,84017734145,84017734146,84017734147,84017734148,84017734149";

/// The most seconds between an answered notification and the edited copies.
Parameter FIVE = 5;

/// The reason why every test fails, or "".
Property Missing As %String(MAXLEN = 400);

/// 1 while BeginPairing has run and EndPairing has not.
Property Begun As %Boolean [ InitialExpression = 0 ];

/// The Refs of the rows a test made (requests and sessions), comma-separated, for Fixture.Clean.
Property Refs As %String(MAXLEN = "") [ Private ];

/// The Refs of the requests that were answered for real, comma-separated, for RemoveTaskWarnings.
Property Answered As %String(MAXLEN = "") [ Private ];

/// The presses sent so far, for their ids.
Property Presses As %Integer [ InitialExpression = 0, Private ];

Method OnBeforeAllTests() As %Status
{
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
	Set ..Answered = ""
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
	Quit 1
}

/// Removes what the test made, on every path: the warnings of the real answers, then the requests and the sessions.
Method Tidy() [ Private ]
{
	For i = 1:1:$Length(..Answered, ",") {
		Set ref = $Piece(..Answered, ",", i)
		If ref '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Type = 3 AND Text %STARTSWITH ?", "OcuTalon.Bridge.Approval: no open task of "_ref)
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Set ..Answered = ""
}

/// A fixture session (zztgappr...) of this process's user, which holds the role of the requests; its Ref. It is paired by the caller and
/// removed by Tidy.
Method WebSession() As %String [ Private ]
{
	Set ref = ..NewSession("zztgappr")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set row.IrisUser = $Username
	Do $$$AssertStatusOK(row.%Save(), "the fixture session belongs to "_$Username)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	Quit ref
}

/// A role that this process's user holds.
ClassMethod HeldRole() As %String [ Private ]
{
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet($Username, .roles)
	Quit $Piece(roles, ",", 1)
}

/// A fixture request of the owner that this process's user may answer, with the dry run of 50 orders; fields change the defaults. Its Ref
/// is kept for Tidy.
Method Request(owner As %String, fields As %DynamicObject = "") As %String [ Private ]
{
	Set all = {}
	Do all.%Set("RequiredRole", ..HeldRole())
	Do all.%Set("DryRun", "{""affected"":50,""resend"":50,""leftOut"":0,""field"":""OrderDate"",""before"":""16/10/2026"",""after"":""2026-10-16"",""itemNoun"":{""one"":""order"",""other"":""orders""}}")
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, "", "pending", , all)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Answered = ..Answered_$Select(..Answered = "": "", 1: ",")_ref
	Quit ref
}

/// A session paired with the chat through the real /start path, and the confirmation that the chat gets waited for; the session's Ref.
Method Paired(chatId As %String, name As %String, Output chatRef As %String) As %String [ Private ]
{
	Set session = ..WebSession()
	Do $$$AssertTrue(..PairChat(chatId, name, session), "chat "_chatId_" is paired with its session")
	Do ..ChatRow(chatId, .chatRef)
	Do $$$AssertEquals(..TextsAfter(chatId, 1).%Size(), 1, "the chat got its confirmation")
	Quit session
}

/// The press of the button whose data is data, under a message of the chat; TelegramIn has handled it when this returns.
Method Press(chatId As %String, name As %String, data As %String) [ Private ]
{
	Set ..Presses = ..Presses + 1
	Do ..Send(..ButtonPress(chatId, name, 1, data, "zzapproval"_..Presses))
	Do $$$AssertTrue(..Handled(), "TelegramIn handled the press of "_chatId)
}

/// The request's row.
ClassMethod Row(ref As %String) As OcuTalon.Bridge.Data.ApprovalRequest [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
}

/// The state, answered action and answered channel of the request, as "state|action|channel".
ClassMethod Facts(ref As %String) As %String [ Private ]
{
	Set row = ..Row(ref)
	Quit $Select($IsObject(row): row.State_"|"_row.AnsweredAction_"|"_row.AnsweredChannel, 1: "no row")
}

/// A time as the catalog puts it after "Approved from Telegram" and the like: "at 14:15" for a time today, "on Jan 1, 2020 at 00:00" for a
/// dated one, each with " ET" on the online demo.
ClassMethod Shown(utc As %String) As %String [ Private ]
{
	Set clock = ##class(OcuTalon.Data.Time).ForMessage(utc)
	Quit $Select(clock '? 2N1":"2N: "on ", 1: "at ")_clock_$Select(+##class(OcuTalon.Data.Public.Settings).Get("onlineDemo"): " ET", 1: "")
}

/// The count of TelegramIn warnings since the event mark whose text holds the text, waiting up to 10 seconds for the first.
ClassMethod Warnings(mark As %String, text As %String) As %Integer [ Private ]
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set deadline = $ZHorolog + 10
	For {
		Set told = 0, position = 0
		Set rows = $ClassMethod(fixture, "EventRows", mark, "TelegramIn")
		While $ListNext(rows, position, row) {
			If ($Extract(row, 1, 2) = "3:") && ($Find(row, text) > 0) Set told = told + 1
		}
		If told || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit told
}

/// Asserts one answer of the press: its text (or no text) and its alert.
Method AssertAnswer(answer As %DynamicObject, text As %String, alert As %Boolean, label As %String) [ Private ]
{
	If '$IsObject(answer) {
		Do $$$AssertTrue(0, label_": the press got no answer")
		Quit
	}
	Do $$$AssertEquals($Select(answer.%IsDefined("text"): answer.text, 1: "(no text)"), $Select(text = "": "(no text)", 1: text), label_": the text of the answer")
	Do $$$AssertEquals(+answer."show_alert", +alert, label_": "_$Select(alert: "an alert that stays until it is dismissed", 1: "no alert"))
}

/// AC2: the paired chat's Approve is the request's first answer, from Telegram.
Method TestApprove()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734140
		Set session = ..Paired(chatId, "Zqapprove", .chatRef)
		Set request = ..Request(session)
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Set sends = ..CallsOf("sendMessage").%Size()
		Set turns = ##class(OcuTalon.Data.Ownership).Turns(session, .sc).Count()
		Do ..Press(chatId, "Zqapprove", "approve:"_request)
		Set found = ..WaitAnswers(answers, 1)
		Do $$$AssertEquals(found.%Size(), 1, "one answerCallbackQuery")
		If found.%Size() = 1 {
			Do ..AssertAnswer(found.%Get(0), "Approved. Repairing and resending 50 orders.", 0, "approve")
			Do $$$AssertEquals(found.%Get(0)."callback_query_id", "zzapproval"_..Presses, "of the press")
		}
		Do $$$AssertEquals(..Facts(request), "approved|approve|telegram", "the request is approved on the channel telegram")
		Do $$$AssertEquals(..Row(request).AnsweredBy, $Username, "by the session's IRIS user")
		Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(audit, "OcuTalon", "Approval", "Approval", request, "", 1, 20)
		Do $$$AssertEquals(entries.%Size(), 1, "one Approval audit entry names the request")
		If entries.%Size() = 1 {
			Set data = entries.%Get(0).data
			Do $$$AssertEquals(data.channel_"|"_data.sessionRef_"|"_data.irisUser, "telegram|"_session_"|"_$Username, "it names the channel telegram, the session and its user")
			Set json = entries.%Get(0).data.%ToJSON()_entries.%Get(0).description
			Do $$$AssertEquals(($Find(json, chatId) > 0)_"|"_($Find(json, "Zqapprove") > 0)_"|"_($Find(json, chatRef) > 0), "0|0|0", "and holds neither the chat id, nor the chat's name, nor its Ref")
		}
		Hang 1
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Turns(session, .sc).Count(), turns, "the press made no Turn")
		Do $$$AssertEquals(..CallsOf("sendMessage").%Size(), sends, "and sent no chat message")
	} Catch ex {
		Do $$$AssertTrue(0, "the approve test failed: "_..Safe(ex))
	}
}

/// AC2: the paired chat's Reject is the request's first answer, from Telegram.
Method TestReject()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734141
		Set session = ..Paired(chatId, "Zqreject", .chatRef)
		Set request = ..Request(session)
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(chatId, "Zqreject", "reject:"_request)
		Set found = ..WaitAnswers(answers, 1)
		Do $$$AssertEquals(found.%Size(), 1, "one answerCallbackQuery")
		If found.%Size() = 1 Do ..AssertAnswer(found.%Get(0), "Rejected. Nothing was changed.", 0, "reject")
		Do $$$AssertEquals(..Facts(request), "rejected|reject|telegram", "the request is rejected on the channel telegram")
	} Catch ex {
		Do $$$AssertTrue(0, "the reject test failed: "_..Safe(ex))
	}
}

/// AC4: a press after another channel answered is an alert that names the winner, and changes nothing.
Method TestLate()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734142
		Set session = ..Paired(chatId, "Zqlate", .chatRef)
		Set approved = ..Request(session)
		Set rejected = ..Request(session)
		Set bridge = "OcuTalon.Bridge.Approval"
		Do $$$AssertEquals($ClassMethod(bridge, "Answer", approved, "approve", "web", $Username, session, .winner), "done", "control: the web chat approves the first request")
		Do $$$AssertEquals($ClassMethod(bridge, "Answer", rejected, "reject", "phone", $Username, session, .winner), "done", "control: the simulated phone rejects the second")
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(chatId, "Zqlate", "reject:"_approved)
		Do ..Press(chatId, "Zqlate", "approve:"_rejected)
		Set found = ..WaitAnswers(answers, 2)
		Do $$$AssertEquals(found.%Size(), 2, "two answerCallbackQuery calls")
		If found.%Size() = 2 {
			Do ..AssertAnswer(found.%Get(0), "Already answered: approved from the web chat "_..Shown(..Row(approved).AnsweredAt)_".", 1, "late reject")
			Do ..AssertAnswer(found.%Get(1), "Already answered: rejected from the simulated phone "_..Shown(..Row(rejected).AnsweredAt)_".", 1, "late approve")
		}
		Do $$$AssertEquals(..Facts(approved), "approved|approve|web", "the first request is unchanged")
		Do $$$AssertEquals(..Facts(rejected), "rejected|reject|phone", "and so is the second")
	} Catch ex {
		Do $$$AssertTrue(0, "the late test failed: "_..Safe(ex))
	}
}

/// AC4: a press on a request past its expiry is an alert, and records no answer.
Method TestExpired()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734143
		Set session = ..Paired(chatId, "Zqexpired", .chatRef)
		Set request = ..Request(session, {"ExpiresAt": "2020-01-01T00:00:00Z"})
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(chatId, "Zqexpired", "approve:"_request)
		Set found = ..WaitAnswers(answers, 1)
		Do $$$AssertEquals(found.%Size(), 1, "one answerCallbackQuery")
		If found.%Size() = 1 Do ..AssertAnswer(found.%Get(0), "Expired "_..Shown("2020-01-01T00:00:00Z")_". Nothing was changed.", 1, "expired")
		Do $$$AssertEquals(..Facts(request), "expired||", "the request is expired and holds no answer")
		Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(audit, "OcuTalon", "Approval", "Approval", request)
		Set answeredEntries = 0
		Set iterator = entries.%GetIterator()
		While iterator.%GetNext(, .entry) {
			If $IsObject(entry.data) && (entry.data.change = "answered") Set answeredEntries = answeredEntries + 1
		}
		Do $$$AssertEquals(answeredEntries, 0, "and no answered audit entry is written")
	} Catch ex {
		Do $$$AssertTrue(0, "the expired test failed: "_..Safe(ex))
	}
}

/// AC4: only the session's paired chat can answer its request.
Method TestNotPairedChat()
{
	If '..Go() Quit
	Try {
		Set session = ..WebSession()
		Set request = ..Request(session)
		Set other = ..Paired(84017734145, "Zqother", .otherRef)
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(84017734144, "Zqstranger", "approve:"_request)
		Do ..Press(84017734145, "Zqother", "approve:"_request)
		Set found = ..WaitAnswers(answers, 2)
		Do $$$AssertEquals(found.%Size(), 2, "two answerCallbackQuery calls")
		If found.%Size() = 2 {
			Do ..AssertAnswer(found.%Get(0), "Only the paired chat can answer this request.", 1, "an unpaired chat")
			Do ..AssertAnswer(found.%Get(1), "Only the paired chat can answer this request.", 1, "a chat paired with another session")
		}
		Do $$$AssertEquals(..Facts(request), "pending||", "the request stays pending")
		Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(audit, "OcuTalon", "Approval", "Approval", request).%Size(), 0, "and no audit entry names it")
	} Catch ex {
		Do $$$AssertTrue(0, "the not-paired test failed: "_..Safe(ex))
	}
}

/// AC4: a press for a request nobody has, and a press that is no request at all.
Method TestUnknown()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734146
		Set session = ..Paired(chatId, "Zqunknown", .chatRef)
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Do ..Send(..ButtonPress(chatId, "Zqunknown", 1, "zz", ""))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled a press with no id")
		Do $$$AssertEquals(..Warnings(log, "could not answer a button press: the press has no id."), 1, "one warning says the press with no id was not answered")
		Do ..Press(chatId, "Zqunknown", "approve:"_##class(OcuTalon.Bridge.Ids).NewRef())
		Do ..Press(chatId, "Zqunknown", "zz")
		Do ..Press(chatId, "Zqunknown", "approve:")
		Set found = ..WaitAnswers(answers, 3)
		Do $$$AssertEquals(found.%Size(), 3, "three answerCallbackQuery calls, and none for the press with no id")
		For i = 0:1:found.%Size() - 1 {
			Do ..AssertAnswer(found.%Get(i), "That request is no longer available.", 1, "press "_(i + 1))
			Do $$$AssertTrue(found.%Get(i).%Get("callback_query_id") '= "", "press "_(i + 1)_" answers the id of its own press")
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the unknown test failed: "_..Safe(ex))
	}
}

/// The presses answered with no text: a request with no dry run is approved, and the press is answered with no text and no alert; a
/// request whose role the session's user lacks (not_allowed) stays pending, and the press is answered with no text, no alert and one warning.
Method TestApproveNoDryRun()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734148
		Set session = ..Paired(chatId, "Zqnodry", .chatRef)
		Set request = ..Request(session, {"DryRun": ""})
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(chatId, "Zqnodry", "approve:"_request)
		Set found = ..WaitAnswers(answers, 1)
		Do $$$AssertEquals(found.%Size(), 1, "one answerCallbackQuery")
		If found.%Size() = 1 Do ..AssertAnswer(found.%Get(0), "", 0, "no dry run")
		Do $$$AssertEquals(..Facts(request), "approved|approve|telegram", "the request is approved")
		Set refused = ..Request(session, {"RequiredRole": "ZzNoSuchRole"})
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(chatId, "Zqnodry", "approve:"_refused)
		Set found = ..WaitAnswers(answers, 1)
		Do $$$AssertEquals(found.%Size(), 1, "not_allowed: one answerCallbackQuery")
		If found.%Size() = 1 Do ..AssertAnswer(found.%Get(0), "", 0, "not_allowed")
		Do $$$AssertEquals(..Warnings(log, "may not answer this kind of request"), 1, "not_allowed: one warning")
		Do $$$AssertEquals(..Facts(refused), "pending||", "not_allowed: the request stays pending")
	} Catch ex {
		Do $$$AssertTrue(0, "the no-dry-run test failed: "_..Safe(ex))
	}
}

/// Story 23.2: the paired chat's Approve of a suspend, a resume and a reroute is answered with the kind's own text (press.approvedSuspend, press.approvedResume and press.approvedReroute),
/// not "Repairing and resending".
Method TestApproveKinds()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734150
		Set session = ..Paired(chatId, "Zqkinds", .chatRef)
		Set cases = $ListBuild(
			$ListBuild("suspend_item", "{""item"":""OrdersToWarehouse"",""before"":""enabled"",""after"":""disabled""}", "Approved. Suspending OrdersToWarehouse."),
			$ListBuild("resume_item", "{""item"":""OrdersToWarehouse"",""before"":""disabled"",""after"":""enabled""}", "Approved. Resuming OrdersToWarehouse."),
			$ListBuild("reroute", "{""affected"":50,""resend"":50,""leftOut"":0,""itemNoun"":{""one"":""order"",""other"":""orders""},""from"":""OrdersFromPartner"",""to"":""OrdersForReview"",""example"":""1234""}", "Approved. Rerouting 50 orders to OrdersForReview."),
			$ListBuild("partner_warning", "{""notice"":""Orders failed."",""recipients"":[{""name"":""Results Partner IT"",""address"":""it@results-partner.example""}],""simulated"":1}", "Approved. Sending the delay notice to the Simulated mailbox."))
		Set position = 0
		While $ListNext(cases, position, case) {
			Set request = ..Request(session, {"FixKind": ($List(case, 1)), "DryRun": ($List(case, 2))})
			Set answers = ..CallsOf("answerCallbackQuery").%Size()
			Do ..Press(chatId, "Zqkinds", "approve:"_request)
			Set found = ..WaitAnswers(answers, 1)
			Do $$$AssertEquals(found.%Size(), 1, $List(case, 1)_": one answerCallbackQuery")
			If found.%Size() = 1 Do ..AssertAnswer(found.%Get(0), $List(case, 3), 0, $List(case, 1))
			Do $$$AssertEquals(..Facts(request), "approved|approve|telegram", $List(case, 1)_": the request is approved on the channel telegram")
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the kinds test failed: "_..Safe(ex))
	}
}

/// A failed answerCallbackQuery is one warning that names nothing of the press; the request stays answered and the next press is served.
Method TestPressAnswerFails()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734149
		Set session = ..Paired(chatId, "Zqfails", .chatRef)
		Set first = ..Request(session)
		Set second = ..Request(session)
		Set failed = {"status": 400, "body": {"ok": false, "error_code": 400, "description": "Bad Request: query is too old and response timeout expired or query ID is invalid"}}
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "answerCallbackQuery", "replies": [(failed)]}), "a 400 for the next answerCallbackQuery is queued")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Set log = $ClassMethod(fixture, "EventMark")
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(chatId, "Zqfails", "approve:"_first)
		Set found = ..WaitAnswers(answers, 1)
		Do $$$AssertEquals(found.%Size(), 1, "the press was answered once (and refused)")
		Do $$$AssertEquals(..Facts(first), "approved|approve|telegram", "the request is approved all the same")
		Set told = 0, names = 0
		Set deadline = $ZHorolog + 10
		For {
			Set told = 0, names = 0, position = 0
			Set rows = $ClassMethod(fixture, "EventRows", log, "TelegramIn")
			While $ListNext(rows, position, row) {
				If ($Extract(row, 1, 2) = "3:") && ($Find(row, "could not answer a button press") > 0) Set told = told + 1
				If ($Find(row, first) > 0) || ($Find(row, chatId) > 0) || ($Find(row, "Zqfails") > 0) || ($Find(row, "approve:") > 0) || ($Find(row, chatRef) > 0) Set names = names + 1
			}
			If told || ($ZHorolog >= deadline) Quit
			Hang 0.25
		}
		Do $$$AssertEquals(told, 1, "one warning says the press was not answered")
		Do $$$AssertEquals(names, 0, "and no TelegramIn log text names the Ref, the chat id, the chat's name, its Ref or the callback data")
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(chatId, "Zqfails", "reject:"_second)
		Set found = ..WaitAnswers(answers, 1)
		Do $$$AssertEquals(found.%Size(), 1, "the next press is answered")
		If found.%Size() = 1 Do ..AssertAnswer(found.%Get(0), "Rejected. Nothing was changed.", 0, "the next press")
		Do $$$AssertEquals(..Facts(second), "rejected|reject|telegram", "and its request is rejected")
	} Catch ex {
		Do $$$AssertTrue(0, "the failed-answer test failed: "_..Safe(ex))
	}
}

/// AC2, AC3: through Notify, the Telegram message and the phone message both show who answered within 5 seconds, and the result follows.
Method TestEveryCopy()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734147
		Set session = ..Paired(chatId, "Zqcopy", .chatRef)
		Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
		Set request = ..Request(session)
		Set notice = ..Notification(session, "incident", "incident.withFix", ..FixtureSlots("incident.withFix"), request)
		Set sends = ..CallsOf("sendMessage").%Size()
		Set phones = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 100).Count()
		If '..ToNotify(notice, trace) Quit
		Set calls = ..WaitCalls("sendMessage", sends + 1, 20)
		Do $$$AssertEquals(calls.%Size(), sends + 1, "Telegram gets the notice")
		Set keyboard = ..KeyboardTo(chatId)
		Do $$$AssertEquals($Select($IsObject(keyboard): keyboard.%ToJSON(), 1: ""), {"inline_keyboard": [[{"text": "Approve", "callback_data": ("approve:"_request)}, {"text": "Reject", "callback_data": ("reject:"_request)}]]}.%ToJSON(), "with the buttons")
		Set deadline = $ZHorolog + 20
		For {
			Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 100)
			If (rows.Count() > phones) || ($ZHorolog >= deadline) Quit
			Hang 0.25
		}
		Do $$$AssertEquals(rows.Count(), phones + 1, "and so does the simulated phone")
		Set rows = ""

		Set time = ##class(OcuTalon.Data.Time).NowUtc()
		Set slots = {"channel": "telegram", "time": (time)}
		Set status = "Approved from Telegram "_..Shown(time)_"."
		Set started = $ZHorolog
		If '..ToNotify(..Notification(session, "answered", "answered.approved", slots, request), trace) Quit
		Set edited = 0, answered = 0
		For {
			Set edited = (..EditsTo(chatId).%Size() > 0)
			Set rows = ""
			Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 100)
			Set answered = (rows.Count() > 0) && (rows.GetAt(1).Answer = status)
			If (edited && answered) || ($ZHorolog >= (started + 20)) Quit
			Hang 0.1
		}
		Set seconds = $ZHorolog - started
		Do $$$AssertTrue(edited && answered && (seconds <= ..#FIVE), "within "_..#FIVE_" seconds both copies show who answered (edited "_edited_", phone answered "_answered_", "_$Justify(seconds, 0, 1)_" s; the phone's Answer is '"_$Select(rows.Count() > 0: rows.GetAt(1).Answer, 1: "(no message)")_"', wanted '"_status_"')")
		Set edits = ..EditsTo(chatId)
		Do $$$AssertEquals(edits.%Size(), 1, "the Telegram message is edited once")
		If edits.%Size() = 1 Do $$$AssertEquals(edits.%Get(0).text, calls.%Get(sends).params.text_$Char(10, 10)_status, "with the status as its last line")
		If rows.Count() > 0 Do $$$AssertEquals(rows.GetAt(1).Answer, status, "and the phone message's Answer is the status")

		Set results = ..CallsOf("sendMessage").%Size()
		If '..ToNotify(..Notification(session, "result", "result.allThrough", ..FixtureSlots("result.allThrough"), request), trace) Quit
		Set calls = ..WaitCalls("sendMessage", results + 1, 20)
		Do $$$AssertEquals(calls.%Size(), results + 1, "the result is one new chat message")
		If calls.%Size() = (results + 1) Do $$$AssertEquals(calls.%Get(results).params.text, "All 50 orders went through.", "All 50 orders went through.")
		Do $$$AssertEquals(..EditsTo(chatId).%Size(), 1, "and edits nothing")
	} Catch ex {
		Do $$$AssertTrue(0, "the every-copy test failed: "_..Safe(ex))
	}
}

}
