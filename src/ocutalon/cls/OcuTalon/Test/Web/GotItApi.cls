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
///   - TestSecondPressIs200: the second press reaches SessionOps (already_handled) and answers the first handledAt, writes no row, sends no second handled
///     Notification (the hops SessionOps to Notify) and publishes nothing;
///   - TestPhoneBody: exactly {"channel":"phone"} is the phone's press (the Handled row's channel is phone), and any other body is the web's;
///   - TestOtherSessionIs404: another session's tell-now Decision, an unknown Ref and a Ref that is not one are 404 not_found before anything is
///     submitted: no GotIt reaches SessionOps, no row is written and no event is published;
///   - TestDigestDecisionIs404: the session's own Decision that is not tell-now is 404 too, with nothing submitted;
///   - TestPagePress (Story 24.3a; V3, AC5): the press of the session's own page card is 200 {"result":"done","handledAt"} with Data.Page Marked; the page row is acknowledged with channel web
///     (also for the body {"channel":"phone"}), one AckPage reaches IncidentManager, the page card is published again with handledAt, and a second press is 200 with the same handledAt and
///     changes nothing;
///   - TestPageNotOwnCopyIs404 (V3): another session's page Ref, the Ref of a page row whose person is the session but which has no web copy of it, and a Ref that is neither the session's
///     tell-now Decision nor its own page copy answer 404 not_found, byte-identical to the answer for an unknown Ref, with no AckPage submitted and the page not acknowledged;
///   - TestPageOnlineDemoIs404 (V3): with onlineDemo on, a press of the session's own page copy answers the same 404 and submits nothing.
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

/// The page rows of the run are those of the incidents that start with this, and are deleted in OnAfterAllTests.
Parameter PAGEINCIDENT = "zzgotitpage";

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
	Do ##class(OcuTalon.Test.Watch.Paging).SaveKeys()
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Watch.Paging).PutKeysBack()
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Page WHERE IncidentRef LIKE ?", ..#PAGEINCIDENT_..Number_"%")
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
	Set notices = ..Hops(trace, "SessionOps", "Notify")
	Set again = ..Call(session, decision, .response)
	Do $$$AssertEquals(response.Status_"|"_again, "200 OK|"_body, "a second press is 200 with the same handledAt")
	Do $$$AssertEquals(..Hops(trace, "SessionOps", "Notify"), notices, "SessionOps sends no second handled Notification")
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
	Set notices = ..Hops(trace, "SessionOps", "Notify")
	Do $$$AssertEquals(notices, 1, "the first press sent one handled Notification")
	Hang 1
	Set second = ..Call(session, decision, .response)
	Do $$$AssertEquals(..Hops(trace, "SessionOps", "Notify"), notices, "the second sends none")
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

/// Story 24.3a (V3, AC5): the press of the session's own page card is the same route as a tell-now notice's, and submits AckPage (channel web, whatever the body says) instead of
/// GotIt: 200 with Data.Page Marked, the row acknowledged by the web, one AckPage that reaches IncidentManager (the answer is IncidentManager's), the card published again with
/// handledAt and a second press that is 200 with the first handledAt and changes nothing.
Method TestPagePress()
{
	If '..Guard() Quit
	Set session = ..OwnSession()
	Set trace = ..TraceOf(session)
	Set page = ..PageCopy(session, .card)
	Set hops = ..Hops(trace, "CommandsIn", "IncidentManager")
	Set body = ..Call(session, page, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the answer is 200: "_body)
	Do $$$AssertEquals(response.ContentType, "application/json", "JSON")
	Set handledAt = ##class(OcuTalon.Data.Page).Marked(page)
	Do $$$AssertTrue(handledAt '= "", "the page is acknowledged")
	Do $$$AssertEquals(body, {"result": "done", "handledAt": (handledAt)}.%ToJSON(), "the body is {result: done, handledAt}")
	Set row = ##class(OcuTalon.Data.Page).RefIndexOpen(page)
	Do $$$AssertEquals(row.AcknowledgedChannel, "web", "the page row names the web channel")
	Do $$$AssertEquals(..Hops(trace, "CommandsIn", "IncidentManager"), hops + 1, "one AckPage reached IncidentManager")
	Do $$$AssertEquals(..HandledRows(page), 0, "and no Handled row of a tell-now notice was written")
	Set events = ..WaitEvents(session, "notification", card, 2)
	Do $$$AssertEquals(events.%Size(), 2, "the card's ref has the first event and one more")
	If events.%Size() = 2 {
		Do $$$AssertEquals(events.%Get(0).payload.handledAt, "", "the first has no handledAt")
		Do $$$AssertEquals(events.%Get(1).payload.handledAt_"|"_events.%Get(1).payload.decisionRef_"|"_events.%Get(1).payload.kind, handledAt_"|"_page_"|page", "the second carries handledAt and the page's Ref")
	}
	// the second press comes once WebChatOut has recorded the handled row, which is then the newest web row of the page (Matrix: second press)
	Set end = $ZHorolog + 20
	For {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE DecisionRef = ? AND Channel = 'web' AND Kind = 'handled' AND OwnerRef = ?", page, session)
		Do rs.%Next()
		Set handledRows = +rs.%GetData(1)
		If handledRows || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Do $$$AssertEquals(handledRows, 1, "WebChatOut recorded the handled row of the session's copy")
	Set again = ..Call(session, page, .response)
	Do $$$AssertEquals(response.Status_"|"_again, "200 OK|"_body, "a second press, with the handled row as the newest web row, is 200 with the same handledAt")
	Do $$$AssertEquals(##class(OcuTalon.Data.Page).Marked(page)_"|"_##class(OcuTalon.Data.Page).RefIndexOpen(page).AcknowledgedChannel, handledAt_"|web", "and changes nothing")
	Hang 1
	Do $$$AssertEquals(..EventsOf(session, "notification", card).%Size(), 2, "and publishes no new event")
	// a body that names the phone is still the web's: a page has no phone copy
	Set second = ..PageCopy(session, .secondCard)
	Set phoneBody = ..Call(session, second, .response, {"channel": "phone"}.%ToJSON())
	Do $$$AssertEquals(response.Status, "200 OK", "a press with the phone body is 200: "_phoneBody)
	Do $$$AssertEquals(##class(OcuTalon.Data.Page).RefIndexOpen(second).AcknowledgedChannel, "web", "its channel is web")
}

/// V3: what the session does not hold as its own page copy is 404 not_found, the answer of an unknown Ref byte for byte, before anything is submitted: another session's page,
/// and a page row of the session's person with no web copy.
Method TestPageNotOwnCopyIs404()
{
	If '..Guard() Quit
	Set mine = ..OwnSession()
	Set theirs = ..PageSession("theirs")
	Set unknownBody = ..Call(mine, ##class(OcuTalon.Bridge.Ids).NewRef(), .unknown)
	Do $$$AssertEquals(unknown.Status_"|"_unknownBody, "404 Not Found|"_..ErrorBody("not_found", ##class(OcuTalon.Web.Api).#MESSAGENOTFOUND), "an unknown Ref is the not_found answer")
	Set theirPage = ..PageCopy(theirs, .theirCard)
	Set bare = ..PageRow($Username, "bare")
	Set cases = $ListBuild($ListBuild("another session's page", theirPage), $ListBuild("a page row of the session's person with no web copy", bare))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $List(case, 1), ref = $List(case, 2)
		Set eventsBefore = ..AllEvents(mine) + ..AllEvents(theirs)
		Set hopsBefore = ..Hops(..TraceOf(mine), "CommandsIn", "IncidentManager") + ..Hops(..TraceOf(theirs), "CommandsIn", "IncidentManager")
		Set body = ..Call(mine, ref, .response)
		Do $$$AssertEquals(response.Status_"|"_response.ContentType_"|"_body, unknown.Status_"|"_unknown.ContentType_"|"_unknownBody, label_": the answer is the unknown Ref's, byte for byte")
		Hang 0.5
		Do $$$AssertEquals(..Hops(..TraceOf(mine), "CommandsIn", "IncidentManager") + ..Hops(..TraceOf(theirs), "CommandsIn", "IncidentManager"), hopsBefore, label_": no AckPage was submitted")
		Do $$$AssertEquals(..AllEvents(mine) + ..AllEvents(theirs), eventsBefore, label_": no event is published")
		Do $$$AssertEquals(##class(OcuTalon.Data.Page).Marked(theirPage)_"|"_##class(OcuTalon.Data.Page).Marked(bare), "|", label_": no page is acknowledged")
	}
}

/// V3: on the online demo the press of the session's own page copy is 404, the unknown Ref's answer, with nothing submitted and the page not acknowledged; with the flag off the same
/// press is 200 (the control).
Method TestPageOnlineDemoIs404()
{
	If '..Guard() Quit
	Set session = ..OwnSession()
	Set trace = ..TraceOf(session)
	Set page = ..PageCopy(session, .card)
	Set unknownBody = ..Call(session, ##class(OcuTalon.Bridge.Ids).NewRef(), .unknown)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set hops = ..Hops(trace, "CommandsIn", "IncidentManager")
	Set body = ..Call(session, page, .response)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertEquals(response.Status_"|"_body, unknown.Status_"|"_unknownBody, "the press on the online demo is the unknown Ref's answer")
	Hang 0.5
	Do $$$AssertEquals(..Hops(trace, "CommandsIn", "IncidentManager"), hops, "no AckPage was submitted")
	Do $$$AssertEquals(##class(OcuTalon.Data.Page).Marked(page), "", "and the page is not acknowledged")
	Set body = ..Call(session, page, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "control: the same press with the flag off is 200: "_body)
	Do $$$AssertTrue(##class(OcuTalon.Data.Page).Marked(page) '= "", "and acknowledges the page")
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

/// A fixture session of an IRIS user of its own (another user than the one who runs the tests), which Watch.Paging.SessionOf finds for a page whose person is that user.
Method PageSession(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzgotitpage"_..Number_name)
	Do ..Keep(ref)
	Quit ref
}

/// The signed-in session of a page press: the route takes the session of the IRIS user who is signed in (Ownership.SessionRef), the user who runs the tests, and a page reaches the
/// user's first paired session, else the first session row of the user (Watch.Paging.SessionOf). The stack may hold other session rows of that user, so the session is paired
/// (Fixture.Pairing, removed with the fixture rows), which SessionOf prefers, after the fixture sessions that the earlier tests of the run made for the user are removed, and the test
/// asserts that Watch.Paging.SessionOf names it.
Method OwnSession() As %String [ Private ]
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Sessions)
	Set ..Sessions = ""
	Set ref = ..Session()
	Do ##class(OcuTalon.Test.Data.Fixture).Pairing(ref)
	Do $$$AssertEquals(##class(OcuTalon.Watch.Paging).SessionOf($Username), ref, "Watch.Paging.SessionOf names the paired session of the user who is signed in")
	Quit ref
}

/// A page row (the on-call role) whose Person is the IRIS user, so that Watch.Paging.SessionOf of it is the session of that user. The page's Ref; the row is deleted with the run's rows.
Method PageRow(person As %String, name As %String) As %String [ Private ]
{
	Set page = ##class(OcuTalon.Data.Page).%New()
	Set page.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set page.IncidentRef = ..#PAGEINCIDENT_..Number_name_$Increment(^||GotItApiPage)
	Set page.Role = "oncall"
	Set page.Person = person
	Set page.Channels = "telegram,email"
	Set page.SentAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(page.%Save(), "the page row is made")
	Quit page.Ref
}

/// A page of the session's user and its web card: no backup is set (so the text is page.onCallAlone), the page row's person is the session's IRIS user (which must be the user of
/// this session alone, PageSession makes one, for Watch.Paging.SessionOf to find it) and the card is delivered as the production delivers a page. Returns the page's Ref; card is the card's ref.
Method PageCopy(session As %String, Output card As %String) As %String [ Private ]
{
	Set user = ##class(OcuTalon.Data.Session).RefIndexOpen(session).IrisUser
	For key = "oncall.backup.user", "oncall.backup.email" Do ##class(OcuTalon.Test.Watch.Paging).Write(key, "")
	Set page = ..PageRow(user, "p")
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = session
	Set notification.Kind = "page"
	Set notification.DecisionRef = page
	Set notification.IncidentRef = ##class(OcuTalon.Data.Page).RefIndexOpen(page).IncidentRef
	Set notification.CatalogKey = "page.onCall"
	Set notification.Slots = {"count": 3, "itemNoun": {"one": "message", "other": "messages"}, "production": "Orders", "time": "2030-01-01T02:10:00Z", "minutes": 15, "cause": "The partner sent a bad date."}.%ToJSON()
	Set web = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.WebChat.Out", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of WebChatOut is made")
	Do $$$AssertStatusOK(web.OnNotification(notification, .response), "the page card is delivered")
	Set card = ""
	Set cards = ##class(OcuTalon.Data.Ownership).RecentNotices(session, 50)
	For i = 1:1:cards.Count() If cards.GetAt(i).DecisionRef = page Set card = cards.GetAt(i).ChannelMessageId
	Do $$$AssertTrue(card '= "", "the page has its web card")
	Quit page
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

/// The number of Handled rows for the Ref, counted in the table.
Method HandledRows(ref As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Handled WHERE Ref = ?", ref)
	Do $$$AssertTrue(result.%SQLCODE >= 0, "the Handled rows are counted")
	Quit $Select(result.%Next(): +result.%GetData(1), 1: 0)
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
