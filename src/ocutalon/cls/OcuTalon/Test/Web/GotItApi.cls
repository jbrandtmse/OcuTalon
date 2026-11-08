/// Tests of POST /v1/decisions/:ref/got-it (Story 18.4; AD-1, AD-4, AD-12, AD-14, AD-32, AD-33), called with stand-in request and response objects and a
/// CSP session whose OcuTalon.SessionRef is the fixture session (as Test.Web.DismissApi does), through the real production: the route submits through
/// Commands.Submit, CommandsIn sends the GotIt to SessionOps, which marks the notice and sends the handled Notification to Notify, which routes it to
/// WebChatOut and SimPhoneOut. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): where OcuTalon.Production does not run every test fails with
/// that reason, so that a broken stack can never give a green shard. Demo mode is on for the whole run (Notify routes to the phone only then); it is put
/// back, with onlineDemo, in OnAfterAllTests, which also removes the fixture rows, the Handled rows, the events and the sessions' messages. The copies of
/// a notice (the web card and the phone message) are delivered to the Out operations as the production delivers a tell-now Notification; the route and
/// everything after it is the production's. The commands that SessionOps received are counted from the hops CommandsIn to SessionOps of the session's trace.
///   - TestPressUpdatesEveryCopy (AC 4): the press of the session's own tell-now notice is 200 {"result":"done","handledAt"}; one Handled row with the
///     route's channel (web); one more notification event of the card's ref carrying handledAt; one more phone event whose answer is the rendered handled
///     line; Digest.NeedsYou no longer counts the notice; a second press is 200 with the same handledAt and no new event;
///   - TestSecondPressIs200: the second press reaches SessionOps (already_handled) and answers the first handledAt, writes no row and publishes nothing;
///   - TestPhoneBody: exactly {"channel":"phone"} is the phone's press (the Handled row's channel is phone), and any other body is the web's;
///   - TestOtherSessionIs404: another session's tell-now Decision, an unknown Ref and a Ref that is not one are 404 not_found before anything is
///     submitted: no GotIt reaches SessionOps, no row is written and no event is published;
///   - TestDigestDecisionIs404: the session's own Decision that is not tell-now is 404 too, with nothing submitted.
Class OcuTalon.Test.Web.GotItApi Extends %UnitTest.TestCase
{

/// Seconds to wait for the consumers of a handled Notification.
Parameter WAIT = 15;

/// The run's number.
Property Number As %Integer;

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 200);

/// The TraceRefs of the fixture sessions, for the clean-up of the messages.
Property Traces As %DynamicArray;

/// The Refs of the fixture sessions of the run, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

/// The demo.mode row before the tests (Test.Demo.Step.Saved).
Property SavedModeFound As %Boolean;

Property SavedModeValue As %String(MAXLEN = 1000);

Property SavedModeUpdatedAt As %String(MAXLEN = 20);

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("GotItApi", "n"))
	Set ..Traces = []
	Set ..Sessions = ""
	Set ..Missing = ""
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set ..SavedModeFound = found, ..SavedModeValue = value, ..SavedModeUpdatedAt = updatedAt
	If '##class(Ens.Director).IsProductionRunning(.name) || (name '= "OcuTalon.Production") {
		Set ..Missing = "OcuTalon.Production does not run in OCUTALON: this class runs in throwaways and CI only (Rule 21)"
		Quit $SYSTEM.Status.OK()
	}
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, ##class(OcuTalon.Data.Time).NowUtc())
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..SavedModeFound, ..SavedModeValue, ..SavedModeUpdatedAt)
	For i = 1:1:$Length(..Sessions, ",") Do ##class(OcuTalon.Data.Handled).DropSession($Piece(..Sessions, ",", i))
	If ..Missing = "" Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Traces, "OCUTALON")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

/// AC 4: a notice with its web card and its phone message. The press of Got it from the web chat is 200 with handledAt; the Handled row names the web
/// channel; the card's ref gets one more notification event that carries handledAt; the phone message gets one more event whose answer is the handled
/// line the phone renders; the notice no longer counts as needing the user; a second press answers the same handledAt with no new event.
Method TestPressUpdatesEveryCopy()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set decision = ..Notice(session, .card, .message)
	Set hops = ..Hops(trace, "CommandsIn", "SessionOps")
	Set needed = ..NeedsYou(session)
	Do $$$AssertTrue(needed >= 1, "the notice counts as needing the user before the press")
	Set body = ..Call(session, decision, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the answer is 200: "_body)
	Do $$$AssertEquals(response.ContentType, "application/json", "JSON")
	Set handledAt = ##class(OcuTalon.Data.Handled).Marked(decision)
	Do $$$AssertTrue(handledAt '= "", "the notice is marked")
	Do $$$AssertEquals(body, {"result": "done", "handledAt": (handledAt)}.%ToJSON(), "the body is {result: done, handledAt}")
	Do $$$AssertEquals(..HandledRows(decision), 1, "one Handled row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexOpen(decision).Channel_"|"_##class(OcuTalon.Data.Handled).RefIndexOpen(decision).SessionRef, "web|"_session, "with the route's channel and the session")
	Set events = ..WaitEvents(session, "notification", card, 2)
	Do $$$AssertEquals(events.%Size(), 2, "the card's ref has the first event and one more")
	If events.%Size() = 2 {
		Do $$$AssertEquals(events.%Get(0).payload.handledAt, "", "the first has no handledAt")
		Do $$$AssertEquals(events.%Get(1).payload.handledAt_"|"_events.%Get(1).payload.decisionRef, handledAt_"|"_decision, "the second carries handledAt and the notice's Ref")
	}
	Set phones = ..WaitEvents(session, "phone", message, 2)
	Do $$$AssertEquals(phones.%Size(), 2, "the phone message has the first event and one more")
	Set expected = ##class(OcuTalon.Msg.Catalog).Render("handled.marked", {"time": (handledAt)}, "phone")
	If phones.%Size() = 2 Do $$$AssertEquals(phones.%Get(1).payload.answer, expected, "whose answer is the rendered handled line")
	Do $$$AssertEquals(..NeedsYou(session), needed - 1, "the notice no longer counts as needing the user")
	Do $$$AssertEquals(..Hops(trace, "CommandsIn", "SessionOps"), hops + 1, "one GotIt reached SessionOps")
	Set again = ..Call(session, decision, .response)
	Do $$$AssertEquals(response.Status_"|"_again, "200 OK|"_body, "a second press is 200 with the same handledAt")
	Hang 1
	Do $$$AssertEquals(..EventsOf(session, "notification", card).%Size()_"|"_..EventsOf(session, "phone", message).%Size(), "2|2", "and publishes no new event")
	Do $$$AssertEquals(..HandledRows(decision), 1, "and writes no new row")
}

/// The second press reaches SessionOps, which answers already_handled: the route is 200 with the first handledAt, and nothing is written or published.
Method TestSecondPressIs200()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set decision = ..Notice(session, .card, .message)
	Set hops = ..Hops(trace, "CommandsIn", "SessionOps")
	Set first = ..Call(session, decision, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the first press is 200: "_first)
	Do ..WaitEvents(session, "notification", card, 2)
	Do ..WaitEvents(session, "phone", message, 2)
	Set events = ..EventsOf(session, "notification", card).%Size()_"|"_..EventsOf(session, "phone", message).%Size()
	Set marked = ##class(OcuTalon.Data.Handled).Marked(decision)
	Hang 1
	Set second = ..Call(session, decision, .response)
	Do $$$AssertEquals(response.Status_"|"_second, "200 OK|"_first, "the second press is 200 with the first handledAt")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).Marked(decision), marked, "the mark is the first press's")
	Do $$$AssertEquals(..Hops(trace, "CommandsIn", "SessionOps"), hops + 2, "both presses reached SessionOps")
	Hang 1
	Do $$$AssertEquals(..EventsOf(session, "notification", card).%Size()_"|"_..EventsOf(session, "phone", message).%Size(), events, "no new event")
	Do $$$AssertEquals(..HandledRows(decision), 1, "and one Handled row")
}

/// Exactly the body {"channel":"phone"} is the phone's press; an empty body, {}, another channel, an extra member, an array and text that is not JSON are the web's.
Method TestPhoneBody()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set decision = ..Notice(session)
	Set body = ..Call(session, decision, .response, {"channel": "phone"}.%ToJSON())
	Do $$$AssertEquals(response.Status, "200 OK", "the phone's press is 200: "_body)
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexOpen(decision).Channel, "phone", "the Handled row names the phone")
	Set bodies = $ListBuild("", "{}", "{""channel"":""web""}", "{""channel"":""phone"",""x"":1}", "{""channel"":""Phone""}", "[""phone""]", "not json")
	Set position = 0
	While $ListNext(bodies, position, text) {
		Set other = ..Notice(session)
		Set answer = ..Call(session, other, .response, text)
		Do $$$AssertEquals(response.Status, "200 OK", "'"_text_"': 200")
		Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexOpen(other).Channel, "web", "'"_text_"': the Handled row names the web chat")
	}
}

/// AC 4 (Rule 1): what the session can't see is 404 not_found before anything is submitted: another session's tell-now Decision, a Decision that does not exist
/// and a Ref that is not a Ref. No GotIt reaches SessionOps, no Handled row is written and no event is published.
Method TestOtherSessionIs404()
{
	If '..Guard() Quit
	Set mine = ..Session()
	Set theirs = ##class(OcuTalon.Test.Data.Fixture).Session("zzgotitother"_..Number)
	Do ..Keep(theirs)
	Set other = ##class(OcuTalon.Test.Data.Fixture).Decision(theirs, "decide", , {"Outcome": "tellnow"})
	Set cases = $ListBuild($ListBuild("another session's tell-now Decision", other), $ListBuild("an unknown Ref", ##class(OcuTalon.Bridge.Ids).NewRef()), $ListBuild("a Ref that is not one", "zzmissing"_..Number))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $List(case, 1), ref = $List(case, 2)
		Set eventsBefore = ..AllEvents(mine) + ..AllEvents(theirs)
		Set hopsBefore = ..Hops(..TraceOf(mine), "CommandsIn", "SessionOps") + ..Hops(..TraceOf(theirs), "CommandsIn", "SessionOps")
		Set body = ..Call(mine, ref, .response)
		Do $$$AssertEquals(response.Status, "404 Not Found", label_": 404")
		Do $$$AssertEquals(body, ..ErrorBody("not_found", ##class(OcuTalon.Web.Api).#MESSAGENOTFOUND), label_": the not_found body")
		Do $$$AssertEquals(..Hops(..TraceOf(mine), "CommandsIn", "SessionOps") + ..Hops(..TraceOf(theirs), "CommandsIn", "SessionOps"), hopsBefore, label_": no GotIt reached SessionOps")
		Do $$$AssertEquals(..HandledRows(ref), 0, label_": no Handled row")
		Do $$$AssertEquals(..AllEvents(mine) + ..AllEvents(theirs), eventsBefore, label_": no event is published")
	}
}

/// The session's own Decision that is not tell-now (here a digest outcome) is 404 not_found, with nothing submitted or written.
Method TestDigestDecisionIs404()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", , {"Outcome": "digest"})
	Set hopsBefore = ..Hops(..TraceOf(session), "CommandsIn", "SessionOps")
	Set body = ..Call(session, decision, .response)
	Do $$$AssertEquals(response.Status, "404 Not Found", "404")
	Do $$$AssertEquals(body, ..ErrorBody("not_found", ##class(OcuTalon.Web.Api).#MESSAGENOTFOUND), "the not_found body")
	Do $$$AssertEquals(..Hops(..TraceOf(session), "CommandsIn", "SessionOps"), hopsBefore, "no GotIt reached SessionOps")
	Do $$$AssertEquals(..HandledRows(decision), 0, "and no Handled row is written")
}

/// --- helpers ---
/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// The fixture session of the IRIS user who runs the tests (the user that Ownership.SessionRef resolves the CSP session for).
Method Session() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Do ..Keep(ref)
	Quit ref
}

/// Keeps the session's TraceRef and Ref for the clean-up.
Method Keep(ref As %String) [ Private ]
{
	Do ..Traces.%Push(..TraceOf(ref))
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
}

/// The TraceRef of the session.
Method TraceOf(ref As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef
}

/// A tell-now notice of the session: a tell-now Decision, its web card and its phone message, delivered as the production delivers a tell-now Notification.
/// Returns the Decision's Ref (the notice's Ref); card is the web card's ref and message the phone message's Ref.
Method Notice(session As %String, Output card As %String, Output message As %String) As %String [ Private ]
{
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", , {"Outcome": "tellnow"})
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = session
	Set notification.Kind = "tellnow"
	Set notification.DecisionRef = decision
	Set notification.CatalogKey = "notice.tellNow"
	Set notification.Slots = {"whatHappened": "zz notice", "reason": "zz reason."}.%ToJSON()
	Set web = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.WebChat.Out", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of WebChatOut is made")
	Do $$$AssertStatusOK(web.OnNotification(notification, .response), "the web card is delivered")
	Set phone = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.SimPhone.Out", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of SimPhoneOut is made")
	Do $$$AssertStatusOK(phone.OnNotification(notification, .response), "the phone message is delivered")
	Set card = "", message = ""
	Set cards = ##class(OcuTalon.Data.Ownership).RecentNotices(session, 50)
	For i = 1:1:cards.Count() If cards.GetAt(i).DecisionRef = decision Set card = cards.GetAt(i).ChannelMessageId
	Set message = ##class(OcuTalon.Data.Delivery).FindByRef(decision, "phone", session)
	Do $$$AssertTrue((card '= "") && (message '= ""), "the notice has its web card and its phone message")
	Quit decision
}

/// Waits until the session's stream holds at least count events of the type for the ref, or WAIT seconds have passed. Answers the events.
Method WaitEvents(session As %String, type As %String, ref As %String, count As %Integer) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set found = ..EventsOf(session, type, ref)
		If (found.%Size() >= count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// The events of the type on the session's stream whose payload ref is the ref, oldest first.
Method EventsOf(session As %String, type As %String, ref As %String) As %DynamicArray [ Private ]
{
	Set found = []
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, type)
	For i = 0:1:events.%Size() - 1 {
		If events.%Get(i).payload.ref = ref Do found.%Push(events.%Get(i))
	}
	Quit found
}

/// The number of notification and phone events on the session's stream.
Method AllEvents(session As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(session, "notification").%Size() + ##class(OcuTalon.Test.Core.Observe).Events(session, "phone").%Size()
}

/// The number of Handled rows for the Ref.
Method HandledRows(ref As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Data.Handled).RefIndexExists(ref)
}

/// The number of entries that need the session (Digest.NeedsYou).
Method NeedsYou(session As %String) As %Integer [ Private ]
{
	Set result = ##class(OcuTalon.Digest.NeedsYou).List(session, [], .sc)
	Do $$$AssertStatusOK(sc, "NeedsYou is read")
	Quit result.count
}

/// The number of requests from the source item to the target item in the session's trace.
Method Hops(trace As %String, source As %String, target As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, source, target).%Size()
}

/// Calls the route for the notice as the CSP session of the session (a body is the request's content), through Written; response is the %response, and
/// the result is what the route wrote. The call is made with the %request and %response set here.
Method Call(session As %String, ref As %String, Output response, body As %String = "") As %String [ Private ]
{
	New %request, %response, %session
	Set application = "/ocutalon/api/"
	Set %request = $Select(body = "": ##class(OcuTalon.Test.Web.StubRequest).Make(application), 1: ##class(OcuTalon.Test.Web.StubRequest).MakeBody(application, body))
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzGotItApi"_..Number, 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Api", "GotIt", ref)
	Do $$$AssertStatusOK(sc, "GotIt returns OK")
	Set response = %response
	Quit written
}

/// The error body of the route for the code and the message.
Method ErrorBody(code As %String, message As %String) As %String [ Private ]
{
	Quit {"error": {"code": (code), "message": (message)}}.%ToJSON()
}

}
