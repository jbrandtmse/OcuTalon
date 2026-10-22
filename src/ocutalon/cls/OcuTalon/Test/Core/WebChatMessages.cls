/// Tests of WebChatIn, the service through which a posted message enters the production (Story 2.4; AD-1, AD-14, AD-20,
/// AD-30). Safe on a slot: no production runs there, so the tests call OnProcessInput on a shadow instance of
/// OcuTalon.Test.Core.WebChatInProbe, which records the allowance calls and the sends instead of making them. The real
/// Interoperability path is the job of OcuTalon.Test.Core.ConversationProduction.
///   - TestBuildsItem: a message asks the allowance and then sends Conversation an Item with the fields of the message, a new
///     ItemId and the session's TraceRef as its SuperSession;
///   - TestRepeatClientId: a clientId that the session already has (a done or a queued turn) is a duplicate that sends nothing,
///     and another session with that clientId gets its own Item;
///   - TestRefusalQueuesNothing: a refusal sends nothing and answers an error status;
///   - TestSendFailureAnswersError: a send that fails answers an error status with no output;
///   - TestBadPostRefused: a Post with no session, clientId or text, a session with no row, and any other input are errors that
///     send nothing;
///   - TestRunTurnsForwarded: a RunTurns request goes to Conversation as it is;
///   - TestAllowanceAllowsWithFlagOff: the allowance allows every message while the online-demo flag is off.
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
	Do ##class(OcuTalon.Test.Data.Fixture).Turn(a, , "done", "zz done", "zzc"_..Number_"done")
	Do ##class(OcuTalon.Test.Data.Fixture).Turn(a, , "queued", "zz queued", "zzc"_..Number_"queued")
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

/// A refusal of the allowance sends nothing and answers an error status; the allowance is asked with the session, the channel
/// and the text.
Method TestRefusalQueuesNothing()
{
	Set session = ..Session("refuse")
	Set probe = ..NewProbe()
	Set probe.Refuse = 1
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"refuse", "zz refused", 0), .output)
	Do $$$AssertStatusNotOK(sc, "a refusal is an error status")
	Do $$$AssertEquals(..Calls(), 1, "only the allowance was asked")
	Do $$$AssertEquals(..Call(1, "target")_"|"_..Call(1, "sessionRef")_"|"_..Call(1, "channel")_"|"_..Call(1, "text"), "allowed|"_session_"|web|zz refused", "with the session, the channel and the text")
	Do $$$AssertEquals(output, "", "and the output is empty")
	Set probe = ..NewProbe()
	Set sc = probe.OnProcessInput(..Post(session, "zzc"_..Number_"refuse", "zz refused", 0), .output)
	Do $$$AssertStatusOK(sc, "the same message is accepted when the allowance allows it")
	Do $$$AssertEquals(output, "{""accepted"":1,""duplicate"":0}", "as a new message, not a duplicate: the refusal left no turn")
	Do $$$AssertEquals(..Sends(), 1, "and it is sent")
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
		Do $$$AssertEquals(..Sends(), 0, case_": nothing is sent")
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

/// --- helpers ---
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
