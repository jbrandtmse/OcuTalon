/// End-to-end tests of the online demo's allowance messages over the running production (QA, Story 16.9; AD-14, AD-20, AD-31, AD-32).
/// THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the running OcuTalon.Production, which a slot never has.
/// Where the production does not run, every test fails with that reason, so that a broken start can never give a green shard. The
/// browser unit (live online-allowance) proves the same chains with a page and takes minutes; these cases take seconds, so a mutation of
/// the chain is seen on the warm stack. Both run with the online-demo flag set, which OnBeforeAllTests sets and OnAfterAllTests puts back.
///   - TestARefusedMessageGivesOneWebCard (AC 1 and 3, matrix rows 2 and 3): a message that WebChatIn refuses because the session's hour
///     is used up goes through the real allowance and the real Notify rule: the refused output, a refused Turn and no Item to
///     Conversation; one allowance Delivery row on the web chat with the catalog's text (instance time, "ET", the install link) and no
///     message on the phone; one WebChatIn to Notify header under the session's TraceRef; a second refusal of the window sends nothing
///     more; the chat's cards (Ownership.RecentNotices) hold the one card;
///   - TestARefusalOnAnotherDayNamesTheDay: the same chain with a retryAt a day and a half ahead (any hour): the card reads "on <day> at HH:MM ET";
///   - TestTheDailyCapMessageReachesTheWebChatOnce (AC 5, matrix row 13): budget.capped through the real sink (BridgeSink, with only its
///     read of the sessions cut down to the test's own session) sends the open session with activity the daily-cap message through
///     NoticesIn and Notify: one allowance Delivery row with the catalog's text, DailyCapDay set, and the same event again sends nothing;
///   - TestTheFlagOffSendsNothing (AC 6, matrix rows 6 and 16): with the flag off the same event gives no Delivery row and no daily-cap
///     day, and a call over what would be the limit is allowed with no window and no refused Turn.
/// The guard, the fixture sessions, the run's number (^OcuTalonTest("AllowanceInProduction","n")) and the clean-up are those of
/// Test.Core.InProduction; the turns that TryConsume recorded are adopted for the clean-up. A time in a card's text shows as the clock alone
/// or with its day, whichever the day of the reading makes it (Observe.TimeReads), so no case depends on the time of day.
Class OcuTalon.Test.Core.AllowanceInProduction Extends OcuTalon.Test.Core.InProduction
{

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Kill ^OcuTalonTest("BridgeSinkVisitors")
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	Quit ##super()
}

Method OnBeforeOneTest() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Kill ^OcuTalonTest("BridgeSinkVisitors")
	Quit $SYSTEM.Status.OK()
}

/// A message over the limit goes through the real WebChatIn, allowance, Notify rule and WebChatOut: it is refused with a Turn and no
/// Item, and the session's web chat gets one allowance card and the phone nothing; a second refusal adds no card.
Method TestARefusedMessageGivesOneWebCard()
{
	If '..Guard() Quit
	Set session = ..Session("refused")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set limit = ##class(OcuTalon.Core.Allowance).Limit()
	Do ..Seed(session, limit, 3000)
	Set times = ##class(OcuTalon.Data.Session).RefIndexOpen(session).AllowanceTimes
	Set expected = ##class(OcuTalon.Data.Time).AddSeconds($List(times, 1), 3600)

	Do $$$AssertStatusOK(..Send(session, "zzc"_..Number_"over1", "zz over the limit", .output), "the refused message is answered")
	Set answer = {}.%FromJSON(output)
	Do $$$AssertEquals(answer.accepted_"|"_answer.refused_"|"_answer.retryAt_"|"_answer.limit, "0|1|"_expected_"|"_limit, "as refused, with the retryAt and the limit")
	Do ##class(OcuTalon.Test.Core.Observe).WaitDeliveries(session, 1, ..#WAIT)
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 1, "one Delivery row is recorded")
	If deliveries.Count() = 1 {
		Set delivery = deliveries.GetAt(1)
		Do $$$AssertEquals(delivery.Channel_"|"_delivery.Kind_"|"_delivery.FallbackReason, "web|allowance|", "on the web chat, of kind allowance, with no fallback reason")
		Set form = ##class(OcuTalon.Test.Core.Observe).TimeReads(delivery.Text, "You've used this session's "_limit_" messages for the hour. You can send more ", " ET, or install OcuTalon yourself to keep going: https://github.com/jbrandtmse/OcuTalon#install-it-yourself", expected)
		Do $$$AssertTrue(form '= "", "with the catalog's text, the retryAt in instance time with ET (the clock alone on the day it falls on, with the day on another), and the install link: "_delivery.Text)
	}
	Set cards = ##class(OcuTalon.Data.Ownership).RecentNotices(session, 10)
	Do $$$AssertEquals(cards.Count(), 1, "the chat's cards hold the one allowance card")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "WebChatIn", "Notify", 1, ..#WAIT), "Notify has handled the notice")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "WebChatIn", "Notify")
	Do $$$AssertEquals(sent.%Size(), 1, "one header goes from WebChatIn to Notify")
	If sent.%Size() = 1 Do $$$AssertEquals(sent.%Get(0).bodyClass_"|"_sent.%Get(0).superSession, "OcuTalon.Msg.Notification|"_trace, "its body is the Notification and its SuperSession the session's TraceRef")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "WebChatIn", "Conversation").%Size(), 0, "no Item goes to Conversation")
	Set turns = ##class(OcuTalon.Data.Ownership).Turns(session)
	Do $$$AssertEquals(turns.Count()_"|"_turns.GetAt(1).State_"|"_turns.GetAt(1).ClientId_"|"_turns.GetAt(1).Text, "1|refused||zz over the limit", "the session has one refused Turn, with no ClientId")

	Do $$$AssertStatusOK(..Send(session, "zzc"_..Number_"over2", "zz over the limit again", .output), "a second refusal of the window is answered")
	Do $$$AssertEquals({}.%FromJSON(output).retryAt, expected, "with the same retryAt")
	Hang 3
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 1, "and sends no second card, and no Delivery row of the phone ever follows")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentPhone(session, 10).Count(), 0, "the phone has no message")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "WebChatIn", "Notify").%Size(), 1, "nor a second notice")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Turns(session).Count(), 2, "though it records its own refused Turn")
}

/// A window whose retryAt falls on another day than the reading names the day in its card, whatever the time of day: the oldest entry
/// is 35 hours ahead, so the retryAt is 36 hours ahead, on a later date of the instance zone at any hour (the entries have no upper
/// bound in the window). The card reads "on <day> at HH:MM ET", not "at HH:MM ET".
Method TestARefusalOnAnotherDayNamesTheDay()
{
	If '..Guard() Quit
	Set session = ..Session("otherday")
	Set limit = ##class(OcuTalon.Core.Allowance).Limit()
	Do ..Seed(session, limit, -35 * 3600)
	Set times = ##class(OcuTalon.Data.Session).RefIndexOpen(session).AllowanceTimes
	Set expected = ##class(OcuTalon.Data.Time).AddSeconds($List(times, 1), 3600)

	Do $$$AssertStatusOK(..Send(session, "zzc"_..Number_"day1", "zz over the limit tomorrow", .output), "the refused message is answered")
	Do $$$AssertEquals({}.%FromJSON(output).retryAt, expected, "with the retryAt a day and a half ahead")
	Do ##class(OcuTalon.Test.Core.Observe).WaitDeliveries(session, 1, ..#WAIT)
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 1, "one Delivery row is recorded")
	If deliveries.Count() = 1 {
		Set text = deliveries.GetAt(1).Text
		Set form = ##class(OcuTalon.Test.Core.Observe).TimeReads(text, "You've used this session's "_limit_" messages for the hour. You can send more ", " ET, or install OcuTalon yourself to keep going: https://github.com/jbrandtmse/OcuTalon#install-it-yourself", expected)
		Do $$$AssertEquals(form, "otherday", "the card names the day: "_text)
	}
}

/// budget.capped through the real sink reaches the open session with activity as one daily-cap card on the web chat, with the
/// catalog's text, and the same event again sends nothing; DailyCapDay is the day.
Method TestTheDailyCapMessageReachesTheWebChatOnce()
{
	If '..Guard() Quit
	Set session = ..Visitor("cap")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set day = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Data.Time).NowUtc())
	Set ^OcuTalonTest("BridgeSinkVisitors", "visitors") = $ListBuild(session)
	Do $$$AssertStatusOK(..Sink("budget.capped", "instance", {"day": (day)}), "budget.capped is handled")
	Do ##class(OcuTalon.Test.Core.Observe).WaitDeliveries(session, 1, ..#WAIT)
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 1, "one Delivery row is recorded")
	If deliveries.Count() = 1 {
		Set delivery = deliveries.GetAt(1)
		Do $$$AssertEquals(delivery.Channel_"|"_delivery.Kind_"|"_delivery.FallbackReason, "web|allowance|", "on the web chat, of kind allowance, with no fallback reason")
		Set form = ##class(OcuTalon.Test.Core.Observe).TimeReads(delivery.Text, "The online demo has used today's model allowance. Decisions use fixed rules until ", " ET. You can install OcuTalon yourself to keep going: https://github.com/jbrandtmse/OcuTalon#install-it-yourself", ##class(OcuTalon.Bridge.Time).DayEndUtc(day), 0)
		Do $$$AssertTrue(form '= "", "with the catalog's text, the end of the day in instance time with ET (the clock alone on its own day, with the day on another), and the install link: "_delivery.Text)
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 1, "the chat's cards hold the one daily-cap card")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(session).DailyCapDay, day, "DailyCapDay is the day")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "NoticesIn", "Notify", 1, ..#WAIT), "Notify has handled the notice from NoticesIn")
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "NoticesIn", "Notify")
	Do $$$AssertEquals(sent.%Size(), 1, "one header goes from NoticesIn to Notify")
	If sent.%Size() = 1 Do $$$AssertEquals(sent.%Get(0).superSession, trace, "under the session's TraceRef")

	Do $$$AssertStatusOK(..Sink("budget.capped", "instance", {"day": (day)}), "the same event again is handled")
	Hang 3
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 1, "and sends no second card, and no Delivery row of the phone ever follows")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentPhone(session, 10).Count(), 0, "the phone has no message")
}

/// With the flag off nothing is counted, recorded or sent: the same budget.capped through the real sink sends no card and records no
/// day, and a call over what would be the limit is allowed, with no window and no refused Turn.
Method TestTheFlagOffSendsNothing()
{
	If '..Guard() Quit
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Set session = ..Visitor("off")
	Set day = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Data.Time).NowUtc())
	Set ^OcuTalonTest("BridgeSinkVisitors", "visitors") = $ListBuild(session)
	Do ..Seed(session, ##class(OcuTalon.Core.Allowance).Limit(), 3000)
	Do $$$AssertStatusOK(..Sink("budget.capped", "instance", {"day": (day)}), "budget.capped is handled")
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).TryConsume(session, "web", "zz over what would be the limit", .retryAt, .first), 1, "a message over what would be the limit is allowed")
	Do $$$AssertEquals(retryAt_"|"_first, "|0", "with no retryAt")
	Hang 2
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, "no Delivery row of any kind is recorded for the session")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.DailyCapDay_"|"_row.AllowanceUntil, "|", "no daily-cap day and no window are recorded")
	Set refused = 0
	Set turns = ##class(OcuTalon.Data.Ownership).Turns(session)
	For i = 1:1:turns.Count() {
		If turns.GetAt(i).State = "refused" Set refused = refused + 1
	}
	Do $$$AssertEquals(refused, 0, "and no Turn is refused")
}

/// --- helpers ---
/// OnEvent of the real sink, with only its read of the sessions cut down to the test's own (BridgeSinkVisitorsProbe).
Method Sink(type As %String, owner As %String, payload As %RegisteredObject) As %Status [ Private ]
{
	Quit $ClassMethod("OcuTalon.Test.Core.BridgeSinkVisitorsProbe", "OnEvent", type, owner, payload)
}

/// A fixture session that is open (it has a resume hash) and has a Turn, so that it can be sent the daily-cap message; recorded for
/// the clean-up by Session.
Method Visitor(name As %String) As %String [ Private ]
{
	Set ref = ..Session(name)
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set row.ResumeHash = ##class(OcuTalon.Data.Session).Hash(..#SESSIONPREFIX_..Number_name)
	Do $$$AssertStatusOK(row.%Save(), "the session "_name_" is open")
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Turn(ref)
	Quit ref
}

/// Gives the session count entries in its rolling hour, one second apart, the oldest being oldestAge seconds old; a negative
/// oldestAge puts them ahead of now, which the window keeps too (it has a lower bound only).
Method Seed(ref As %String, count As %Integer, oldestAge As %Integer) [ Private ]
{
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set times = ""
	For i = 0:1:count - 1 Set times = times_$ListBuild(##class(OcuTalon.Data.Time).AddSeconds(now, i - oldestAge))
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set row.AllowanceTimes = times
	Set row.AllowanceUntil = ""
	Do $$$AssertStatusOK(row.%Save(), "the session holds "_count_" entries in its hour")
}

}
