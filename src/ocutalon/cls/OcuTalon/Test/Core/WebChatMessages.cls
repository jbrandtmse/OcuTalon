/// Tests of WebChatIn, the service through which a posted message enters the production (Story 2.4; AD-1, AD-14, AD-20,
/// AD-30). Safe on a slot: no production runs there, so the tests call OnProcessInput on a shadow instance of
/// OcuTalon.Test.Core.WebChatInProbe, which records the allowance calls and the sends instead of making them. The real
/// Interoperability path is the job of OcuTalon.Test.Core.ConversationProduction.
///   - TestBuildsItem: a message asks the allowance and then sends Conversation an Item with the fields of the message, a new
///     ItemId and the session's TraceRef as its SuperSession;
///   - TestRepeatClientId: a clientId that the session already has (a done or a queued turn) is a duplicate that sends nothing,
///     and another session with that clientId gets its own Item;
///   - TestRefusalQueuesNothing (Story 16.9): a refusal with a retryAt sends no Item and answers an OK status with the refused
///     output; the first refusal of a window sends Notify the one allowance notice, in a session of its own under the TraceRef, and
///     a later refusal sends nothing;
///   - TestRefusalWithNoRetryAtIsAnError: a refusal with no retryAt (a lock that was busy) is an error status and sends nothing;
///   - TestFailedNoticeStillRefuses: a notice that fails to send is one warning, and the refusal stands;
///   - TestFailedSendGivesTheMessageBack: a send that fails or throws calls the allowance's Refund for the session once, and an
///     accepted message or a refusal calls it never;
///   - TestFailedSendRefundsTheRealAllowance: with the flag set, the service's own Refund takes the failed message's entry out of the
///     session's AllowanceTimes;
///   - TestSendFailureAnswersError: a send that fails answers an error status with no output;
///   - TestBadPostRefused: a Post with no session, clientId or text, a session with no row, and any other input are errors that
///     ask the allowance nothing and send nothing;
///   - TestRunTurnsForwarded: a RunTurns request goes to Conversation as it is;
///   - TestAllowanceAllowsWithFlagOff: the allowance allows every message while the online-demo flag is off;
///   - TestAllowedAsksTheAllowance: the service's one allowance call returns what Core.Allowance.TryConsume answers for the
///     session, the channel and the text, which no run can show while TryConsume allows everything;
///   - TestJoinsTodaysThread, TestFirstTurnStartsTheThread (Story 2.9; AD-26): a session whose row holds today's thread sends its
///     Item in that thread, and a session with none sends it in a session of its own and records the session the send gave;
///   - TestJoinFailureStillSends, TestFailedSendRecordsNoThread, TestThrownSendRecordsNoThread: a lock that stays busy still
///     sends the message, in its own session, with one warning and no thread recorded, and a send that fails or throws records no
///     thread and leaves the row's lock free for another job;
///   - TestStartedFailureStillAccepts: a thread that cannot be recorded after a good send is one warning, and the message is
///     accepted;
///   - TestRefusedAndDuplicateMessagesTouchNoThread (QA): a message that the allowance refuses, and a repeat of a clientId, are
///     answered before the thread is joined, so they take no lock on the session's row and record no thread;
///   - TestYesterdaysThreadIsNotJoined (QA): a row whose thread is from an earlier day sends the Item in no session and records
///     the session that the send gave, with today's date.
/// The fixture sessions come from Test.Data.Fixture. The run's number is n from ^OcuTalonTest("WebChatMessages","n") (never
/// reset); the probe records under ^OcuTalonTest("WebChatIn", n), which OnAfterAllTests deletes. onlineDemo is put back.
Class OcuTalon.Test.Core.WebChatMessages Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("WebChatMessages", "n"))
	Set ..Refs = ""
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("WebChatIn", ..Number)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $SYSTEM.Status.OK()
}

/// A message asks the allowance (channel web) and then sends one Item to Conversation: a new ItemId, the session's SessionRef,
/// web, user, the text as it was written, FromGuide and the ClientId. The service's SuperSession is the session's TraceRef when
/// it sends. The output says the message was accepted and is not a duplicate.
Method TestBuildsItem()
{
	Set session = ..Session("builds")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set text = "  zz hello"_$Char(10)_"there  "
	Set probe = ..NewProbe()
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"a", text, 1), .output)
	Do $$$AssertStatusOK(sc, "the message is accepted")
	Do $$$AssertEquals(output, "{""accepted"":1,""duplicate"":0}", "the output says accepted, not a duplicate")
	Do $$$AssertEquals(..Calls(), 2, "the allowance is asked and one request is sent")
	Do $$$AssertEquals(..Call(1, "target"), "allowed", "the allowance comes first")
	Do $$$AssertEquals(..Call(1, "sessionRef")_"|"_..Call(1, "channel")_"|"_..Call(1, "text"), session_"|web|"_text, "for the session, on the web channel, with the text")
	Do $$$AssertEquals(..Call(2, "target")_"|"_..Call(2, "class"), "Conversation|OcuTalon.Msg.Item", "an Item goes to Conversation")
	Do $$$AssertTrue(..Call(2, "itemId") ? 22(1AN,1"-",1"_"), "with a new ItemId: "_..Call(2, "itemId"))
	Do $$$AssertEquals(..Call(2, "sessionRef")_"|"_..Call(2, "channel")_"|"_..Call(2, "provenance"), session_"|web|user", "the session's Ref, web, user")
	Do $$$AssertEquals(..Call(2, "text"), text, "the text as it was written")
	Do $$$AssertEquals(..Call(2, "fromGuide")_"|"_..Call(2, "clientId"), "1|zzc"_..Number_"a", "FromGuide and the ClientId")
	Do $$$AssertEquals(..Call(2, "superSession"), trace, "sent with the session's TraceRef as the SuperSession")
	Set first = ..Call(2, "itemId")
	Set probe = ..NewProbe()
	Do $$$AssertStatusOK(probe.OnProcessInput(..Post(session, "zzc"_..Number_"b", "zz again", 0), .output), "a second message is accepted")
	Do $$$AssertTrue(..Call(4, "itemId") '= first, "its ItemId is new")
	Do $$$AssertEquals(..Call(4, "fromGuide"), 0, "and FromGuide is false")
}

/// A clientId that the session already has a turn for, done or queued, is accepted as a duplicate: nothing is sent, not even
/// to the allowance. Another session with that clientId gets its own Item.
Method TestRepeatClientId()
{
	Set a = ..Session("repeata")
	Set b = ..Session("repeatb")
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Turn(a, , "done", "zz done", "zzc"_..Number_"done")
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Turn(a, , "queued", "zz queued", "zzc"_..Number_"queued")
	For which = "done", "queued" {
		Set probe = ..NewProbe()
		Kill ^OcuTalonTest("WebChatIn", ..Number)
		Set sc = probe.OnProcessInput(..Post(a, "zzc"_..Number_which, "zz text", 0), .output)
		Do $$$AssertStatusOK(sc, "a repeat of a "_which_" turn is accepted")
		Do $$$AssertEquals(output, "{""accepted"":1,""duplicate"":1}", "and says it is a duplicate")
		Do $$$AssertEquals(..Calls(), 0, "nothing is sent, and the allowance is not asked")
	}
	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Set sc = ..NewProbe().OnProcessInput(..Post(b, "zzc"_..Number_"done", "zz text", 0), .output)
	Do $$$AssertStatusOK(sc, "another session's message with the same clientId is accepted")
	Do $$$AssertEquals(output, "{""accepted"":1,""duplicate"":0}", "as its own message")
	Do $$$AssertEquals(..Calls(), 2, "and sent")
	Do $$$AssertEquals(..Call(2, "sessionRef")_"|"_..Call(2, "clientId"), b_"|zzc"_..Number_"done", "an Item for that session")
}

/// A refusal of the allowance with a retryAt (Story 16.9) queues nothing: the allowance is asked with the session, the channel and
/// the text, no Item is sent, and the answer is OK with the refused output. The first refusal of a window sends Notify one
/// allowance Notification, in a session of its own under the session's TraceRef, with the limit, the retryAt and the install link;
/// a later refusal of the window sends no notice.
Method TestRefusalQueuesNothing()
{
	Set session = ..Session("refuse")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set probe = ..NewProbe()
	Set probe.Refuse = 1
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"refuse", "zz refused", 0), .output)
	Do $$$AssertStatusOK(sc, "a refusal with a retryAt is answered, not failed")
	Set answer = {}.%FromJSON(output)
	Do $$$AssertEquals(answer.accepted_"|"_answer.duplicate_"|"_answer.refused_"|"_answer.retryAt_"|"_answer.limit, "0|0|1|2030-01-01T00:00:00Z|"_##class(OcuTalon.Core.Allowance).Limit(), "the output says refused, with the retryAt and the limit")
	Do $$$AssertEquals(answer.%GetTypeOf("limit"), "number", "the limit is a number")
	Do $$$AssertEquals(..Calls(), 2, "the allowance was asked and one notice was sent")
	Do $$$AssertEquals(..Sends(), 0, "no Item reaches Conversation")
	Do $$$AssertEquals(..Call(1, "target")_"|"_..Call(1, "sessionRef")_"|"_..Call(1, "channel")_"|"_..Call(1, "text"), "allowed|"_session_"|web|zz refused", "the allowance was asked with the session, the channel and the text")
	Do $$$AssertEquals(..Call(2, "target")_"|"_..Call(2, "class"), "Notify|OcuTalon.Msg.Notification", "the notice goes to Notify")
	Do $$$AssertEquals(..Call(2, "sessionRef")_"|"_..Call(2, "kind")_"|"_..Call(2, "catalogKey"), session_"|allowance|conversation.sessionAllowance", "for the session, kind allowance, the session allowance key")
	Set slots = {}.%FromJSON(..Call(2, "slots"))
	Do $$$AssertEquals(slots.limit_"|"_slots.time_"|"_slots.readmeLink, ##class(OcuTalon.Core.Allowance).Limit()_"|2030-01-01T00:00:00Z|"_##class(OcuTalon.Core.Allowance).#INSTALLLINK, "with the limit, the retryAt and the install link as slots")
	Do $$$AssertEquals(..Call(2, "sessionId")_"|"_..Call(2, "superSession"), "|"_trace, "in a session of its own, under the session's TraceRef")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "|", "and no thread was joined or recorded")

	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Set probe = ..NewProbe()
	Set probe.Refuse = 1
	Set probe.FirstRefusal = 0
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"refuse", "zz refused again", 0), .output)
	Do $$$AssertStatusOK(sc, "a later refusal of the window is answered the same way")
	Do $$$AssertEquals({}.%FromJSON(output).refused, 1, "as refused")
	Do $$$AssertEquals(..Calls(), 1, "only the allowance was asked: no notice is sent again")

	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Set probe = ..NewProbe()
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"refuse", "zz refused", 0), .output)
	Do $$$AssertStatusOK(sc, "the same message is accepted when the allowance allows it")
	Do $$$AssertEquals(output, "{""accepted"":1,""duplicate"":0}", "as a new message, not a duplicate: the refusal left no turn")
	Do $$$AssertEquals(..Sends(), 1, "and it is sent")
}

/// A refusal with no retryAt, which is what TryConsume answers for a lock that stayed busy or an exception, is an error status
/// with no output: nothing is sent, not even a notice.
Method TestRefusalWithNoRetryAtIsAnError()
{
	Set session = ..Session("busy")
	Set probe = ..NewProbe()
	Set probe.RefuseBusy = 1
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"busy", "zz busy", 0), .output)
	Do $$$AssertStatusNotOK(sc, "a refusal with no retryAt is an error status")
	Do $$$AssertEquals(output, "", "with no output")
	Do $$$AssertEquals(..Calls(), 1, "only the allowance was asked: nothing is sent")
}

/// A notice that cannot be sent is logged as one warning, and the refusal stands: the answer is still the refused output.
Method TestFailedNoticeStillRefuses()
{
	Set session = ..Session("nonotice")
	Set mark = ..LastLog()
	Set probe = ..NewProbe()
	Set probe.Refuse = 1
	Set probe.FailNotice = 1
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"nonotice", "zz refused", 0), .output)
	Do $$$AssertStatusOK(sc, "the refusal is answered")
	Do $$$AssertEquals({}.%FromJSON(output).refused, 1, "as refused")
	Do $$$AssertEquals(..Call(2, "target"), "Notify", "the notice was tried")
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Notify", ##class(OcuTalon.Channel.WebChat.In).#LOGNOTICE)
	Do $$$AssertEquals(count, 1, "one warning is logged: "_text)
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Notify", ##class(OcuTalon.Channel.WebChat.In).#LOGNOTICE)
}

/// A message that was allowed and then could not be sent (the send fails or throws) gives its entry back: the allowance's Refund
/// is called once for the session, after the send, and the answer is the error. An accepted message and a refused one call it never.
Method TestFailedSendGivesTheMessageBack()
{
	Set session = ..Session("refund")
	For how = "FailSend", "ThrowSend" {
		Kill ^OcuTalonTest("WebChatIn", ..Number)
		Set probe = ..NewProbe()
		Set $Property(probe, how) = 1
		Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_how, "zz send fails", 0), .output)
		Do $$$AssertStatusNotOK(sc, how_": the answer is the error")
		Do $$$AssertEquals(..Call(1, "target")_"|"_..Call(2, "target")_"|"_..Call(3, "target")_"|"_..Call(3, "sessionRef"), "allowed|Conversation|refund|"_session, how_": Refund follows the failed send, for the session")
		Do $$$AssertEquals(..Calls(), 3, how_": and nothing else")
	}
	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Do $$$AssertStatusOK(..NewProbe().OnProcessInput(..Post(session, "zzc"_..Number_"fine", "zz fine", 0), .output), "an accepted message")
	Do $$$AssertEquals(..Calls(), 2, "gives nothing back")
	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Set probe = ..NewProbe()
	Set probe.Refuse = 1
	Do $$$AssertStatusOK(probe.OnProcessInput(..Post(session, "zzc"_..Number_"nope", "zz refused", 0), .output), "a refusal")
	Do $$$AssertEquals(..Calls(), 2, "gives nothing back either: the allowance and the notice only")
}

/// The service's own Refund gives the entry back through Core.Allowance.Refund: with the flag set, a message that the real allowance
/// let through and whose send then fails leaves the session's AllowanceTimes as it was before the message.
Method TestFailedSendRefundsTheRealAllowance()
{
	Set session = ..Session("realrefund")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Set row.AllowanceTimes = $ListBuild(now, now)
	Do $$$AssertStatusOK(row.%Save(), "the session has two messages in the hour")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set probe = ..NewProbe()
	Set probe.FailSend = 1
	Set probe.RealRefund = 1
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"realrefund", "zz send fails", 0), .output)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertStatusNotOK(sc, "the send fails: the answer is the error")
	Do $$$AssertEquals(..Call(3, "target"), "refund", "the service gave the message back")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals($ListLength(row.AllowanceTimes), 2, "and the real allowance has the two messages of before: the entry of the failed one is gone")
}

/// A send to Conversation that fails answers an error status with no output, after the allowance was asked.
Method TestSendFailureAnswersError()
{
	Set session = ..Session("sendfail")
	Set probe = ..NewProbe()
	Set probe.FailSend = 1
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"sendfail", "zz send fails", 0), .output)
	Do $$$AssertStatusNotOK(sc, "a send that fails is an error status")
	Do $$$AssertEquals(output, "", "with no output")
	Do $$$AssertEquals(..Call(1, "target")_"|"_..Call(2, "target"), "allowed|Conversation", "after the allowance was asked and the send was tried")
}

/// A Post with no session, no clientId, no text, or only spaces for text, a session with no row, and any other input are errors
/// that send nothing.
Method TestBadPostRefused()
{
	Set session = ..Session("bad")
	Set cases = $ListBuild("no session", "no clientId", "no text", "text of spaces", "a session with no row")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set post = ..Post(session, "zzc"_..Number_"bad", "zz text", 0)
		If case = "no session" Set post.SessionRef = ""
		If case = "no clientId" Set post.ClientId = ""
		If case = "no text" Set post.Text = ""
		If case = "text of spaces" Set post.Text = " "_$Char(9)_$Char(10)
		If case = "a session with no row" Set post.SessionRef = "zzunknownsession"_..Number
		Kill ^OcuTalonTest("WebChatIn", ..Number)
		Set sc = ..NewProbe().OnProcessInput(post, .output)
		Do $$$AssertStatusNotOK(sc, case_": an error status")
		Do $$$AssertEquals(output, "", case_": no output")
		Do $$$AssertEquals(..Calls(), 0, case_": the allowance is not asked and nothing is sent")
	}
	For other = "", "zz a string", ##class(Ens.StringRequest).%New("zz") {
		Kill ^OcuTalonTest("WebChatIn", ..Number)
		Set sc = ..NewProbe().OnProcessInput(other, .output)
		Do $$$AssertStatusNotOK(sc, "an input that is neither a message nor a RunTurns request is an error")
		Do $$$AssertEquals(..Calls(), 0, "and nothing is sent")
	}
}

/// A RunTurns request goes to Conversation as it is, with its SessionRef, empty or not, and the allowance is not asked.
Method TestRunTurnsForwarded()
{
	Set session = ..Session("runturns")
	For ref = "", session {
		Kill ^OcuTalonTest("WebChatIn", ..Number)
		Set run = ##class(OcuTalon.Core.Msg.RunTurns).%New()
		Set run.SessionRef = ref
		Do $$$AssertStatusOK(..NewProbe().OnProcessInput(run, .output), "a RunTurns request for '"_ref_"' is accepted")
		Do $$$AssertEquals(..Calls(), 1, "one request is sent")
		Do $$$AssertEquals(..Call(1, "target")_"|"_..Call(1, "class")_"|"_..Call(1, "sessionRef"), "Conversation|OcuTalon.Core.Msg.RunTurns|"_ref, "to Conversation, unchanged")
	}
}

/// While the online-demo flag is off, TryConsume allows every message: 60 calls in a row, each with an empty retryAt and
/// firstRefusal 0.
Method TestAllowanceAllowsWithFlagOff()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Set refused = 0
	For i = 1:1:60 {
		Set retryAt = "zz", firstRefusal = "zz"
		If '##class(OcuTalon.Core.Allowance).TryConsume("zzsession", "web", "zz message "_i, .retryAt, .firstRefusal) || (retryAt '= "") || (firstRefusal '= 0) Set refused = refused + 1
	}
	Do $$$AssertEquals(refused, 0, "60 messages are all allowed, with no retryAt and no first refusal")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).TryConsume("zzsession", "web", "zz", .retryAt, .firstRefusal), 1, "and so is a message with the flag set to 0")
}

/// The service's Allowed seam, which the probe replaces, is one call: it returns what Core.Allowance.TryConsume answers for the
/// session, the channel and the text, with retryAt and firstRefusal passed through. While TryConsume allows every message no run
/// can show the hop, so the source of the method is read (Story 16.9 adds the count that makes it observable).
Method TestAllowedAsksTheAllowance()
{
	Set method = ##class(%Dictionary.MethodDefinition).%OpenId("OcuTalon.Channel.WebChat.In||Allowed")
	If '$IsObject(method) {
		Do $$$AssertTrue(0, "WebChatIn has the method Allowed")
		Quit
	}
	Set code = ""
	Do method.Implementation.Rewind()
	While 'method.Implementation.AtEnd {
		Set code = code_method.Implementation.Read(30000)
	}
	Do $$$AssertEquals($ZStrip(code, "*WC"),"Quit##class(OcuTalon.Core.Allowance).TryConsume(sessionRef,channel,text,.retryAt,.firstRefusal)", "Allowed returns the answer of TryConsume for the session, the channel and the text")
}

/// A session whose row holds today's thread sends its Item in that thread: the probe sees the thread as the service's
/// %SessionId and the session's TraceRef as its SuperSession, and the row stays as it was.
Method TestJoinsTodaysThread()
{
	Set session = ..Session("today")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Set trace = row.TraceRef
	Set row.ThreadSessionId = 4242
	Set row.ThreadDay = ##class(OcuTalon.Core.Trace).Day()
	Do $$$AssertStatusOK(row.%Save(), "the session has today's thread")
	Set probe = ..NewProbe()
	Set probe.NewSession = 9999
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"today", "zz in the thread", 0), .output)
	Do $$$AssertStatusOK(sc, "the message is accepted")
	Do $$$AssertEquals(..Calls(), 2, "the allowance is asked and one request is sent")
	Do $$$AssertEquals(..Call(2, "sessionId")_"|"_..Call(2, "superSession"), "4242|"_trace, "the Item is sent in the thread, with the TraceRef as SuperSession")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "4242|"_##class(OcuTalon.Core.Trace).Day(), "and the row is unchanged")
}

/// A session with no thread sends its Item in no session (the framework starts one) and records the session that the send gave,
/// with today's date.
Method TestFirstTurnStartsTheThread()
{
	Set session = ..Session("first")
	Set probe = ..NewProbe()
	Set probe.NewSession = 5150
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"first", "zz starts the thread", 0), .output)
	Do $$$AssertStatusOK(sc, "the message is accepted")
	Do $$$AssertEquals(..Call(2, "sessionId"), "", "the Item is sent with no session of the thread")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "5150|"_##class(OcuTalon.Core.Trace).Day(), "and the session it started is recorded for today")
	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Set probe = ..NewProbe()
	Set probe.NewSession = 6160
	Do $$$AssertStatusOK(probe.OnProcessInput(..Post(session, "zzc"_..Number_"second", "zz joins it", 0), .output), "the next message is accepted")
	Do $$$AssertEquals(..Call(2, "sessionId"), 5150, "and joins that thread")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(session).ThreadSessionId, 5150, "which stays the thread")
}

/// A row lock that stays busy for longer than Join waits sends the message all the same, in a session of its own, with one
/// warning that starts with ERRORJOIN, and records no thread.
Method TestJoinFailureStillSends()
{
	Set session = ..Session("busy")
	Set id = ##class(OcuTalon.Data.Session).RefIndexOpen(session).%Id()
	Set key = "webchat"_..Number
	Kill ^OcuTalonTest("Trace", "job", key)
	Job ##class(OcuTalon.Test.Core.Trace).Hold(id, key)
	Set deadline = $ZHorolog + 60
	While '$Data(^OcuTalonTest("Trace", "job", key, "ready")) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Do $$$AssertEquals($Get(^OcuTalonTest("Trace", "job", key, "ready")), 1, "another job holds the row's lock")
	Set mark = ..LastLog()
	Set probe = ..NewProbe()
	Set probe.NewSession = 5150
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"busy", "zz busy lock", 0), .output)
	Set ^OcuTalonTest("Trace", "job", key, "release") = 1
	While '$Data(^OcuTalonTest("Trace", "job", key, "done")) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Do $$$AssertStatusOK(sc, "the message is accepted")
	Do $$$AssertEquals(output, "{""accepted"":1,""duplicate"":0}", "as a new message")
	Do $$$AssertEquals(..Sends(), 1, "and sent")
	Do $$$AssertEquals(..Call(2, "sessionId"), "", "in a session of its own")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "|", "and no thread is recorded")
	Set count = ..Warnings(mark, ##class(OcuTalon.Channel.WebChat.In).#ERRORJOIN, .text)
	Do $$$AssertEquals(count, 1, "one warning is logged: "_text)
	Do ..RemoveWarnings(mark, ##class(OcuTalon.Channel.WebChat.In).#ERRORJOIN)
	Kill ^OcuTalonTest("Trace", "job", key)
}

/// A send that fails records no thread, even when the framework had started a session, and leaves the row's lock free for
/// another job: the next message starts the thread.
Method TestFailedSendRecordsNoThread()
{
	Set session = ..Session("failed")
	Set id = ##class(OcuTalon.Data.Session).RefIndexOpen(session).%Id()
	Set probe = ..NewProbe()
	Set probe.FailSend = 1
	Set probe.NewSession = 5150
	Set mark = ..LastLog()
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"failed", "zz send fails", 0), .output)
	Do $$$AssertStatusNotOK(sc, "the failed send is an error status")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "|", "and no thread is recorded")
	Do $$$AssertEquals(..Warnings(mark, ##class(OcuTalon.Channel.WebChat.In).#ERRORJOIN), 0, "the thread was joined without a warning")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Trace).LockFree(id), 1, "and the row's lock is free for another job")
	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Set probe = ..NewProbe()
	Set probe.NewSession = 6160
	Do $$$AssertStatusOK(probe.OnProcessInput(..Post(session, "zzc"_..Number_"failed", "zz tries again", 0), .output), "the same message goes through when it is sent again")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.ThreadSessionId, 6160, "and starts the thread")
}

/// A send that throws is the same: an error status, no thread recorded, and the row's lock free for another job.
Method TestThrownSendRecordsNoThread()
{
	Set session = ..Session("thrown")
	Set id = ##class(OcuTalon.Data.Session).RefIndexOpen(session).%Id()
	Set probe = ..NewProbe()
	Set probe.ThrowSend = 1
	Set probe.NewSession = 5150
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"thrown", "zz send throws", 0), .output)
	Do $$$AssertStatusNotOK(sc, "the thrown send is an error status")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "|", "and no thread is recorded")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Trace).LockFree(id), 1, "and the row's lock is free for another job")
}

/// A thread that cannot be recorded after a good send (the session's row is gone) is one warning that starts with ERRORSTARTED,
/// and the message, which was sent, is accepted.
Method TestStartedFailureStillAccepts()
{
	Set session = ..Session("dropped")
	Set id = ##class(OcuTalon.Data.Session).RefIndexOpen(session).%Id()
	Set mark = ..LastLog()
	Set probe = ..NewProbe()
	Set probe.NewSession = 5150
	Set probe.DropRow = 1
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"dropped", "zz row gone", 0), .output)
	Do ##class(OcuTalon.Data.Session).%UnlockId(id)
	Do $$$AssertStatusOK(sc, "the message is accepted")
	Do $$$AssertEquals(output, "{""accepted"":1,""duplicate"":0}", "as a new message")
	Do $$$AssertEquals(..Sends(), 1, "and was sent")
	Set count = ..Warnings(mark, ##class(OcuTalon.Channel.WebChat.In).#ERRORSTARTED, .text)
	Do $$$AssertEquals(count, 1, "one warning is logged: "_text)
	Do ..RemoveWarnings(mark, ##class(OcuTalon.Channel.WebChat.In).#ERRORSTARTED)
}

/// A message that the allowance refuses, and a repeat of a clientId that the session has a turn for, are answered before the
/// thread is joined: the row's lock is free for another job afterwards (a second job is the only one that can tell, a lock being
/// held per process), no thread is recorded, and no warning about the thread is logged.
Method TestRefusedAndDuplicateMessagesTouchNoThread()
{
	Set session = ..Session("untouched")
	Set id = ##class(OcuTalon.Data.Session).RefIndexOpen(session).%Id()
	Set mark = ..LastLog()
	Set probe = ..NewProbe()
	Set probe.Refuse = 1
	Set probe.NewSession = 5150
	Do $$$AssertStatusOK(probe.OnProcessInput(..Post(session, "zzc"_..Number_"untouchedrefused", "zz refused", 0), .output), "a refused message is answered")
	Do $$$AssertEquals({}.%FromJSON(output).refused, 1, "as refused")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Trace).LockFree(id), 1, "the row's lock is free for another job")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "|", "and no thread is recorded")

	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Turn(session, , "done", "zz done", "zzc"_..Number_"untouchedrepeat")
	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Set probe = ..NewProbe()
	Set probe.NewSession = 5150
	Do $$$AssertStatusOK(probe.OnProcessInput(..Post(session, "zzc"_..Number_"untouchedrepeat", "zz again", 0), .output), "a repeat of a clientId is accepted")
	Do $$$AssertEquals(output, "{""accepted"":1,""duplicate"":1}", "as a duplicate")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Trace).LockFree(id), 1, "the row's lock is free for another job")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "|", "and no thread is recorded")
	Do $$$AssertEquals(..Warnings(mark, ##class(OcuTalon.Channel.WebChat.In).#ERRORJOIN), 0, "neither message logged a warning about the thread")
}

/// The row holds a thread from an earlier day: the Item is sent in no session (the framework starts one), the row then holds the
/// session that the send gave with today's date, and the next message joins that thread, not the old one.
Method TestYesterdaysThreadIsNotJoined()
{
	Set session = ..Session("yesterday")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Set row.ThreadSessionId = 4242
	Set row.ThreadDay = $ZDate($ZDateH(##class(OcuTalon.Core.Trace).Day(), 3) - 1, 3)
	Do $$$AssertStatusOK(row.%Save(), "the session has yesterday's thread")
	Set probe = ..NewProbe()
	Set probe.NewSession = 7001
	Do $$$AssertStatusOK(probe.OnProcessInput(..Post(session, "zzc"_..Number_"yesterday1", "zz new day", 0), .output), "the message is accepted")
	Do $$$AssertEquals(..Call(2, "sessionId"), "", "the Item is sent in no session: it starts today's thread")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "7001|"_##class(OcuTalon.Core.Trace).Day(), "and the row holds the session it started, for today")
	Kill ^OcuTalonTest("WebChatIn", ..Number)
	Set probe = ..NewProbe()
	Set probe.NewSession = 7002
	Do $$$AssertStatusOK(probe.OnProcessInput(..Post(session, "zzc"_..Number_"yesterday2", "zz same day", 0), .output), "the next message is accepted")
	Do $$$AssertEquals(..Call(2, "sessionId"), 7001, "and joins today's thread")
}

/// --- helpers ---
/// The number of the newest row of the event log (Observe.LastLog).
Method LastLog() As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).LastLog()
}

/// The number of warnings that start with the text, logged after the row mark by the service's Accept; text is the newest one's
/// (Observe.Warnings).
Method Warnings(mark As %Integer, start As %String, Output text As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Accept", start)
}

/// Removes the warnings that start with the text, logged after the row mark by the service's Accept (Observe.RemoveWarnings).
Method RemoveWarnings(mark As %Integer, start As %String) [ Private ]
{
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Accept", start)
}

/// A fixture session; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzwebchat"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A shadow instance of the probe, in the run's records.
Method NewProbe() As OcuTalon.Test.Core.WebChatInProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.WebChatInProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.RunNumber = ..Number
	Quit probe
}

/// A message of the page.
Method Post(session As %String, clientId As %String, text As %String, fromGuide As %Boolean) As OcuTalon.Channel.WebChat.Post [ Private ]
{
	Set post = ##class(OcuTalon.Channel.WebChat.Post).%New()
	Set post.SessionRef = session
	Set post.ClientId = clientId
	Set post.Text = text
	Set post.FromGuide = fromGuide
	Quit post
}

/// The number of calls the probe recorded.
Method Calls() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("WebChatIn", ..Number))
}

/// The number of requests the probe recorded as sent to Conversation.
Method Sends() As %Integer [ Private ]
{
	Set count = 0
	For n = 1:1:..Calls() {
		If ..Call(n, "target") = "Conversation" Set count = count + 1
	}
	Quit count
}

/// One field of one recorded call.
Method Call(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("WebChatIn", ..Number, n, field))
}

}
