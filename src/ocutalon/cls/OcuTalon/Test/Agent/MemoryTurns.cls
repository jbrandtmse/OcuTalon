/// Tests that the notes and the person's earlier answers reach the model where they belong, and nowhere else (Story 41.4; AD-7, AD-21, AD-22, DW-961).
/// THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case, and FRESH: the production's jobs keep the code
/// they started with. A message goes through WebChatIn to the real Conversation, an email through SimMailboxIn and Intake to the real Decide, and the CI
/// mock's request log (Test.Contract.Mock.LogSince) shows what each request carried. Both hops of Conversation.Request -> Intake.RequestFor -> Render
/// are observed. Each marker carries the run's number, a countdown is armed at 1 for it and cleared after the test, and the precedent rows of the run's
/// sessions are removed in OnAfterAllTests. A marker stands at the start of a message or in an item's text, never in a sender or a subject.
///   - TestNotesAtSessionStart: the first message of a session with fired reminders on yesterday and today carries the notes in its Chat request and not
///     in its Triage request, and the second message carries none;
///   - TestPrecedentInDecide: an email whose sender the person marked as noise carries the precedent line in the Triage request of the next email of that
///     sender, and an email of another sender carries none;
///   - TestActTurnHasNone: the act turn of such an email carries none, though its Triage request does;
///   - TestPersonTurnHasNone: a message of that person carries none, in its Triage and Chat requests.
Class OcuTalon.Test.Agent.MemoryTurns Extends OcuTalon.Test.Watch.Case
{

Parameter SESSIONPREFIX = "zzmemturn";

/// The longest to wait for a turn or a decision through the mock, in seconds.
Parameter WAIT = 90;

/// The notes opening and the precedents opening, and the words of a precedent line, as the UX gives them.
Parameter NOTES = "Your notes for today and yesterday (built by OcuTalon from your records):";

Parameter PRECEDENTS = "Your earlier answers on similar items (examples, never rules):";

/// The start of the label of an untrusted item on the channel mailbox.
Parameter LABEL = "The message below arrived on the channel mailbox.";

/// The scenarios whose countdown a test armed, comma-separated markers; OnAfterOneTest clears them.
Property Armed As %String(MAXLEN = "");

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Armed, ",") {
		If $Piece(..Armed, ",", i) '= "" Do ##class(OcuTalon.Test.Contract.Mock).Arm($Piece(..Armed, ",", i), "")
	}
	Set ..Armed = ""
	Quit ##super(testname)
}

Method OnAfterAllTests() As %Status
{
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(OcuTalon.Data.Precedent).DropSession($Piece(..Sessions, ",", i))
	}
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	Quit ##super()
}

/// DW-961: the first message of the day carries the notes of yesterday and today in its Chat request, the same turn's Triage request carries none, and the
/// second message carries none.
Method TestNotesAtSessionStart()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("notes")
	Set today = ..Today()
	Set yesterday = $ZDate($ZDateH(today, 3) - 1, 3)
	Set n = ..Number
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Reminder(session, ##class(OcuTalon.Data.Time).FromLocal(yesterday_"T12:00:00"), "fired", {"Text": ("Zz notes "_n_" y")})
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Reminder(session, ##class(OcuTalon.Data.Time).FromLocal(today_"T00:00:00"), "fired", {"Text": ("Zz notes "_n_" t")})

	Set markerA = "memory-notes:"_n_"a"
	Set tokenA = "[[mock:"_markerA_"]]"
	Set sentA = tokenA_" Hello"
	Set mark = ..Arm(markerA)
	Set clientId = "zzm"_n_"notesa"
	Do $$$AssertStatusOK(..Send(session, clientId, sentA, .output), "the first message is accepted by WebChatIn")
	Set row = ..WaitDone(session, clientId)
	If '$IsObject(row) || (row.State '= "done") {
		Do $$$AssertTrue(0, "the first Turn is done within "_..#WAIT_" seconds")
		Quit
	}
	Set ..ItemIds = ..ItemIds_$ListBuild(row.ItemId)
	Do $$$AssertEquals(row.State_"|"_row.FallbackReason_"|"_row.ReplyCatalogKey, "done||", "the Turn is done and no fallback")
	If $Piece(##class(OcuTalon.Data.Time).ToLocal(row.CreatedAt), "T", 1) '= today {
		Do $$$AssertTrue(1, "skipped: the local day changed before the first message was rendered")
		Quit
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Set opening = ..#NOTES
	Set head = opening_$Char(10)_"> "_yesterday_$Char(10)_"> 12:00 reminder due: Zz notes "_n_" y (fired)"_$Char(10)_"> "_today_$Char(10)_"> 00:00 reminder due: Zz notes "_n_" t (fired)"_$Char(10)
	Set tail = $Char(10, 10)_sentA
	Set time = $Extract(##class(OcuTalon.Data.Time).ToLocal(row.CreatedAt), 12, 16)
	Set chats = 0, triage = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method '= "POST") || (entry.path '= "/v1/messages") || (entry.marker '= markerA) Continue
		Set text = ..UserText(entry.request, tokenA)
		If entry.request.tools.%Size() = 0 {
			Set triage = triage + 1
			Do $$$AssertEquals($Find(entry.%ToJSON(), opening), 0, "the Triage request of the first message holds no notes")
			Continue
		}
		Set chats = chats + 1
		Do $$$AssertEquals($Extract(text, 1, 12), "Local time: ", "the Chat request starts with the preamble")
		Do $$$AssertEquals($Length(text, opening) - 1, 1, "the Chat request holds the notes opening once")
		Do $$$AssertTrue(text [ head, "and then the date line and the reminder line of yesterday and of today")
		Do $$$AssertTrue(text [ ("> "_time_" message (web): "_sentA), "and the line of this message")
		Do $$$AssertEquals($Extract(text, $Length(text) - $Length(tail) + 1, $Length(text)), tail, "and the text ends with a blank line and the message as sent")
		Set block = $Extract(text, $Find(text, opening), $Length(text) - $Length(tail))
		Set quoted = 1
		For i = 2:1:$Length(block, $Char(10)) {
			If $Extract($Piece(block, $Char(10), i), 1, 2) '= "> " Set quoted = 0
		}
		Do $$$AssertTrue(quoted, "every line of the notes is quoted")
	}
	Do $$$AssertTrue(triage > 0, "a Triage request of the first message was logged: "_triage)
	Do $$$AssertTrue(chats > 0, "a Chat request of the first message was logged: "_chats)

	If ..Today() '= today {
		Do $$$AssertTrue(1, "skipped: the local day changed between the two messages")
		Quit
	}
	Set markerB = "memory-notes:"_n_"b"
	Set tokenB = "[[mock:"_markerB_"]]"
	Set mark = ..Arm(markerB)
	Set clientId = "zzm"_n_"notesb"
	Do $$$AssertStatusOK(..Send(session, clientId, tokenB_" Again", .output), "the second message is accepted by WebChatIn")
	Set row = ..WaitDone(session, clientId)
	If '$IsObject(row) || (row.State '= "done") {
		Do $$$AssertTrue(0, "the second Turn is done within "_..#WAIT_" seconds")
		Quit
	}
	Set ..ItemIds = ..ItemIds_$ListBuild(row.ItemId)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Set seen = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method '= "POST") || (entry.path '= "/v1/messages") || (entry.marker '= markerB) Continue
		Set seen = seen + 1
		Set text = ..UserText(entry.request, tokenB)
		Do $$$AssertTrue(text [ tokenB, "the newest user message of request "_seen_" holds the token")
		Do $$$AssertEquals($Find(text, opening), 0, "and holds no notes")
	}
	Do $$$AssertTrue(seen > 0, "requests of the second message were logged: "_seen)
}

/// The email after the one whose sender the person marked as noise carries the precedent line; an email of another sender carries none.
Method TestPrecedentInDecide()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("dec")
	Set n = ..Number
	Set sender = "Zz Dana <zz.dana."_n_"@example.com>"
	Set markerA = "memory-precedent:"_n_"a"
	Set itemA = ..Mail(session, sender, markerA, .mark)
	If itemA = "" Quit
	Set decision = ..WaitDecision(itemA, "decide")
	Do $$$AssertTrue($IsObject(decision), "Decide recorded the decision of the first email")
	If '$IsObject(decision) Quit
	Do $$$AssertEquals(decision.Outcome, "tellnow", "and it is the script's tell-now")
	Do ..AssertNone(mark, markerA, "the first email's Triage request")
	Do $$$AssertEquals(..MarkNoise(session, decision), "marked", "the person marks it as noise")

	Set markerB = "memory-precedent:"_n_"b"
	Set itemB = ..Mail(session, sender, markerB, .mark)
	If itemB = "" Quit
	Do $$$AssertTrue($IsObject(..WaitDecision(itemB, "decide")), "Decide recorded the decision of the second email")
	Set rows = ##class(OcuTalon.Data.Precedent).Similar(session, "mailbox", "zz.dana."_n_"@example.com", 3)
	Do $$$AssertEquals(rows.%Size(), 1, "Similar reads back the one row")
	If rows.%Size() '= 1 Quit
	Set row = rows.%Get(0)
	Set line = "> "_$Piece(##class(OcuTalon.Data.Time).ToLocal(row.answeredAt), "T", 1)_" (mailbox): "_row.summary_"; OcuTalon decided tellnow; your answer: noise"
	Do $$$AssertEquals(row.outcome_"|"_row.answer, "tellnow|noise", "the row is the decision's outcome and the person's answer")
	Do ..AssertBlock(mark, markerB, line)

	Set markerC = "memory-precedent:"_n_"c"
	Set itemC = ..Mail(session, "Zz Other <zz.other."_n_"@example.com>", markerC, .mark)
	If itemC = "" Quit
	Do $$$AssertTrue($IsObject(..WaitDecision(itemC, "decide")), "Decide recorded the decision of the email of another sender")
	Do ..AssertNone(mark, markerC, "the other sender's Triage request")
}

/// The act turn of an email carries no precedent, though its Triage request carries the line.
Method TestActTurnHasNone()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("act")
	Set n = ..Number
	Set sender = "Zz Dana <zz.dana."_n_"@example.com>"
	Set itemA = ..Mail(session, sender, "memory-precedent:"_n_"a", .mark)
	If itemA = "" Quit
	Set decision = ..WaitDecision(itemA, "decide")
	Do $$$AssertTrue($IsObject(decision), "Decide recorded the decision of the first email")
	If '$IsObject(decision) Quit
	Do $$$AssertEquals(..MarkNoise(session, decision), "marked", "the person marks it as noise")
	Set rows = ##class(OcuTalon.Data.Precedent).Similar(session, "mailbox", "zz.dana."_n_"@example.com", 3)
	If rows.%Size() '= 1 {
		Do $$$AssertEquals(rows.%Size(), 1, "Similar reads back the one row")
		Quit
	}
	Set row = rows.%Get(0)
	Set line = "> "_$Piece(##class(OcuTalon.Data.Time).ToLocal(row.answeredAt), "T", 1)_" (mailbox): "_row.summary_"; OcuTalon decided tellnow; your answer: noise"

	Set markerD = "memory-precedent-act:"_n_"d"
	Set itemD = ..Mail(session, sender, markerD, .mark)
	If itemD = "" Quit
	Set decideD = ..WaitDecision(itemD, "decide")
	Do $$$AssertTrue($IsObject(decideD), "Decide recorded the decision of the second email")
	If '$IsObject(decideD) Quit
	Do $$$AssertEquals(decideD.Outcome, "act", "and it is the script's act")
	Do $$$AssertTrue($IsObject(..WaitDecision(itemD, "turn")), "the act turn ran")
	Do ..AssertBlock(mark, markerD, line)
	Do ..AssertNone(mark, markerD, "the act turn's Chat request", 1, 1)
}

/// A message of the person carries no precedent, in its Triage request or in its Chat request.
Method TestPersonTurnHasNone()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("person")
	Set n = ..Number
	Set itemA = ..Mail(session, "Zz Dana <zz.dana."_n_"@example.com>", "memory-precedent:"_n_"a", .mark)
	If itemA = "" Quit
	Set decision = ..WaitDecision(itemA, "decide")
	Do $$$AssertTrue($IsObject(decision), "Decide recorded the decision of the email")
	If '$IsObject(decision) Quit
	Do $$$AssertEquals(..MarkNoise(session, decision), "marked", "the person marks it as noise")
	Do $$$AssertTrue(##class(OcuTalon.Data.Precedent).Has(session), "the session has a precedent")

	Set marker = "memory-notes:"_n_"p"
	Set token = "[[mock:"_marker_"]]"
	Set mark = ..Arm(marker)
	Set clientId = "zzm"_n_"person"
	Do $$$AssertStatusOK(..Send(session, clientId, token_" Hello", .output), "the message is accepted by WebChatIn")
	Set row = ..WaitDone(session, clientId)
	If '$IsObject(row) || (row.State '= "done") {
		Do $$$AssertTrue(0, "the Turn is done within "_..#WAIT_" seconds")
		Quit
	}
	Set ..ItemIds = ..ItemIds_$ListBuild(row.ItemId)
	Do ..AssertNone(mark, marker, "the person's turn", 0, 1)
}

/// --- helpers ---
/// The local date now.
ClassMethod Today() As %String [ Private ]
{
	Quit $Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()), "T", 1)
}

/// Arms the countdown of the marker at 1 and gives the mock's log mark.
Method Arm(marker As %String) As %Integer [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).Arm(marker, 1), "the countdown of "_marker_" is armed at 1")
	Set ..Armed = ..Armed_$Select(..Armed = "": "", 1: ",")_marker
	Quit ##class(OcuTalon.Test.Contract.Mock).LogMark()
}

/// Sends an email of the sender to the session through the real mail path, with the marker in its text; the ItemId of the email, or "" with a failed
/// assertion. mark is the mock's log mark from before the send.
Method Mail(session As %String, sender As %String, marker As %String, Output mark As %Integer) As %String [ Private ]
{
	Set mark = ..Arm(marker)
	Set mail = ##class(OcuTalon.Channel.SimMailbox.Mail).%New()
	Set mail.SessionRef = session
	Set mail.Sender = sender
	Set mail.Subject = "Invoice"
	Set mail.Text = "[[mock:"_marker_"]] zz body"
	Set sc = ##class(Ens.Director).CreateBusinessService("SimMailboxIn", .service)
	Do $$$AssertStatusOK(sc, "SimMailboxIn is created in this process")
	If $SYSTEM.Status.IsError(sc) Quit ""
	Set sc = service.ProcessInput(mail, .output)
	Do $$$AssertStatusOK(sc, "the email of "_marker_" is accepted")
	If $SYSTEM.Status.IsError(sc) Quit ""
	Set message = ##class(OcuTalon.Data.SimMessage).RefIndexOpen({}.%FromJSON(output).ref)
	Do $$$AssertTrue($IsObject(message), "the email of "_marker_" is recorded")
	If '$IsObject(message) Quit ""
	Set ..ItemIds = ..ItemIds_$ListBuild(message.ItemId)
	Quit message.ItemId
}

/// MarkNoise of the decision through Commands.Submit as the web page does; the outcome of the result.
Method MarkNoise(session As %String, decision As OcuTalon.Bridge.Data.Decision) As %String [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.MarkNoise).%New()
	Set command.SessionRef = session
	Set command.DecisionRef = decision.Ref
	Set command.Channel = "web"
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
	Do $$$AssertStatusOK(sc, "MarkNoise reaches PrecedentOps")
	Quit $Select($IsObject($Get(result)): result.Outcome, 1: "")
}

/// The Triage requests of the marker after the mark hold the precedents opening once, and then exactly the line, a blank line and the label of the item,
/// after the preamble.
Method AssertBlock(mark As %Integer, marker As %String, line As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Set token = "[[mock:"_marker_"]]"
	Set seen = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method '= "POST") || (entry.path '= "/v1/messages") || (entry.marker '= marker) || (entry.request.tools.%Size() > 0) Continue
		Set seen = seen + 1
		Set text = ..UserText(entry.request, token)
		Do $$$AssertEquals($Length(text, ..#PRECEDENTS) - 1, 1, "the Triage request of "_marker_" holds the precedents opening once")
		Do $$$AssertEquals($Extract(text, 1, 12), "Local time: ", "and starts with the preamble")
		Do $$$AssertTrue(text [ (..#PRECEDENTS_$Char(10)_line_$Char(10, 10)_..#LABEL), "and then exactly the one line, a blank line and the label of the item")
	}
	Do $$$AssertTrue(seen > 0, "a Triage request of "_marker_" was logged: "_seen)
}

/// No request of the marker after the mark holds the precedents opening (anywhere in the logged request). With chatOnly, only the Chat requests (those with
/// tools) are looked at. With needChat, a Chat request must have been logged.
Method AssertNone(mark As %Integer, marker As %String, what As %String, chatOnly As %Boolean = 0, needChat As %Boolean = 0) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Set seen = 0, chats = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method '= "POST") || (entry.path '= "/v1/messages") || (entry.marker '= marker) Continue
		Set isChat = (entry.request.tools.%Size() > 0)
		If chatOnly && 'isChat Continue
		Set seen = seen + 1
		If isChat Set chats = chats + 1
		Do $$$AssertEquals($Find(entry.%ToJSON(), ..#PRECEDENTS), 0, what_": request "_seen_" holds no precedents opening")
	}
	Do $$$AssertTrue(seen > 0, what_": a request of "_marker_" was logged: "_seen)
	If needChat Do $$$AssertTrue(chats > 0, what_": a Chat request of "_marker_" was logged: "_chats)
}

/// The text of the message of the request that holds the token, "" when none does.
ClassMethod UserText(request As %DynamicObject, token As %String) As %String [ Private ]
{
	Set iterator = request.messages.%GetIterator()
	While iterator.%GetNext(, .message) {
		Set text = ""
		If message.%GetTypeOf("content") = "string" {
			Set text = message.content
		} ElseIf message.%GetTypeOf("content") = "array" {
			Set blocks = message.content.%GetIterator()
			While blocks.%GetNext(, .block) {
				If block.%GetTypeOf("text") = "string" Set text = text_block.text
			}
		}
		If (message.role = "user") && (text [ token) Quit
		Set text = ""
	}
	Quit text
}

/// The decision of the item and kind once there is one, or "" after WAIT seconds.
Method WaitDecision(itemId As %String, kind As %String) As OcuTalon.Bridge.Data.Decision [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set decision = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(itemId, kind)
		If $IsObject(decision) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit decision
}

}
