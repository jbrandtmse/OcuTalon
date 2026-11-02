/// Tests of POST /v1/session/end on the online demo (Story 16.4; AD-1, AD-4, AD-13), called with stand-in request, response and CSP session
/// objects (as Test.Web.PairingApi does) through the real production: the route submits an EndSession through Commands.Submit (origin
/// web_user), CommandsIn sends it to the real SessionOps, which cancels the session's reminder through the real ReminderOps. THIS CLASS RUNS
/// IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): where OcuTalon.Production does not run every test fails with that reason, so that a broken
/// stack can never give a green shard. The public setting onlineDemo is set to 1 for each test and put back in OnAfterAllTests; the fixture
/// rows, the reminders and the sessions' messages are removed. The flag-off route's answer is also Test.Web.Api.TestEndSession's.
/// Guard, Call and the clean-up are copies of Test.Web.PairingApi's private helpers, because they are private to that story's class.
///   - TestEndRoute: a CSP session attached to a visitor's row, which has a pending real reminder: 204 with no body, the resume cookie is
///     expired (name OcuTalonResume, empty value, an RFC 1123 date in the past, path /ocutalon/, no domain, Secure, HttpOnly, SameSite
///     Strict), the CSP session is logged out and ends, one EndSession goes from CommandsIn to SessionOps in the session's SuperSession, and
///     the reminder is cancelled;
///   - TestFailedEndKeepsTheSession: a session whose End fails (the test holds its pending reminder row open) is 500 server_error, with no
///     cookie, no logout and the CSP session not ending; once the row is free, the same call ends it;
///   - TestNoAttachedSession: a CSP session with no OcuTalon session is a sign-out alone, 204, with no cookie and no command to SessionOps;
///   - TestFailedEndKeepsTheResume: after the failed sign-out the session's resume reference (the cookie's value) still resumes the
///     session, and after the successful one it resumes nothing (the reference helpers are Test.Core.SessionOpsProduction's);
///   - TestEndRouteOffTheOnlineDemo: with the flag 0 the route only signs out: 204, the logout, no cookie, no command to SessionOps and
///     the attached session's reminder still pending.
Class OcuTalon.Test.Web.SessionEndApi Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 200);

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the reminders that the run made, comma-separated.
Property Reminders As %String(MAXLEN = "");

/// The TraceRefs of the fixture sessions, for the clean-up of the messages.
Property Traces As %DynamicArray;

/// The session that the stand-in CSP session is bound to.
Property Current As %String;

/// The public setting onlineDemo before the run.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("SessionEndApi", "n"))
	Set ..Traces = []
	Set ..Refs = ""
	Set ..Reminders = ""
	Set ..Missing = ""
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	If '##class(Ens.Director).IsProductionRunning(.name) || (name '= "OcuTalon.Production") {
		Set ..Missing = "OcuTalon.Production does not run in OCUTALON: this class runs in throwaways and CI only (Rule 21)"
	}
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	For i = 1:1:$Length(..Reminders, ",") {
		If $Piece(..Reminders, ",", i) '= "" Do ##class(OcuTalon.Test.Schedule.ReminderFixture).Remove($Piece(..Reminders, ",", i))
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	If ..Missing = "" Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Traces, "OCUTALON")
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
}

/// The online demo's sign-out for a visitor's session that has a pending real reminder: 204 with no body, the expired resume cookie with
/// the exact attributes of the sign-in's cookie, the CSP session logged out and to end, one EndSession from CommandsIn to SessionOps, and
/// the reminder cancelled.
Method TestEndRoute()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set reminder = ..Remind(session)
	Set body = ..Call(.response, .endSession, .loggedOut)
	Do $$$AssertEquals(response.Status_"|"_body, "204 No Content|", "204 with no body")
	Do $$$AssertEquals(response.Cookies(1, "n")_"|"_response.Cookies(1, "v"), "OcuTalonResume|", "the cookie OcuTalonResume is set to the empty value")
	Do $$$AssertEquals($Order(response.Cookies(1)), "", "and it is the only cookie")
	Set expires = response.Cookies(1, "e")
	Do $$$AssertTrue(expires ? 3A1", "2N1" "3A1" "4N1" "2N1":"2N1":"2N1" GMT", "it expires at an RFC 1123 date: "_expires)
	Do $$$AssertTrue(##class(OcuTalon.Data.Public.Settings).ToSeconds(##class(OcuTalon.Data.Time).NowUtc()) > ##class(OcuTalon.Data.Public.Settings).ToSeconds(..IsoOf(expires)), "in the past")
	Do $$$AssertEquals(response.Cookies(1, "p")_"|"_response.Cookies(1, "d")_"|"_response.Cookies(1, "s")_"|"_response.Cookies(1, "h")_"|"_response.Cookies(1, "ss"), "/ocutalon/||1|1|strict", "path /ocutalon/, no domain, Secure, HttpOnly, SameSite Strict")
	Do $$$AssertEquals(loggedOut_"|"_endSession, "1|1", "the CSP session is logged out and is to end")
	Do $$$AssertEquals(..Hops(trace, "CommandsIn", "SessionOps"), 1, "one EndSession went from CommandsIn to SessionOps, in the session's SuperSession")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(reminder)
	Do $$$AssertEquals(row.State, "cancelled", "the reminder is cancelled")
	Set row = ""
}

/// A session whose End fails: the test holds its pending reminder row open (concurrency 4), so ReminderOps answers failed and End answers
/// failed. The route is 500 server_error (the cause is logged, not sent), with no cookie and no logout, and the CSP session does not end.
/// Once the row is free, the same call is 204.
Method TestFailedEndKeepsTheSession()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set reminder = ..Remind(session)
	Set held = ##class(OcuTalon.Data.Reminder).RefIndexOpen(reminder, 4)
	Do $$$AssertTrue($IsObject(held), "the test holds the reminder's row")
	Set body = ..Call(.response, .endSession, .loggedOut)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("server_error", ##class(OcuTalon.Web.Api).#MESSAGESERVERERROR), "500 server_error")
	Do $$$AssertEquals($Order(response.Cookies("")), "", "no cookie is set")
	Do $$$AssertEquals(loggedOut_"|"_endSession, "0|0", "the CSP session is not logged out and does not end")
	Set held = ""
	Do $$$AssertEquals(##class(OcuTalon.Data.Reminder).RefIndexOpen(reminder).State, "pending", "and the reminder, read from its stored row, is still pending")
	Set body = ..Call(.response, .endSession, .loggedOut)
	Do $$$AssertEquals(response.Status_"|"_loggedOut_"|"_endSession, "204 No Content|1|1", "with the row free, the same call is 204 and signs out")
	Do $$$AssertEquals(##class(OcuTalon.Data.Reminder).RefIndexOpen(reminder).State, "cancelled", "and the reminder is cancelled")
}

/// The sign-out that fails leaves the session resumable and the one that succeeds does not (AD-4): the session's row holds the hash of a
/// resume reference, as the sign-in's cookie does. While the test holds the pending reminder's row the route is 500, and the reference still
/// opens the session (Session.ForResume, which the sign-in's resume uses); with the row free the same call is 204, and the reference opens
/// nothing.
Method TestFailedEndKeepsTheResume()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set reference = ##class(OcuTalon.Test.Core.SessionOpsProduction).NewReference(session, .sc)
	Do $$$AssertStatusOK(sc, "the session holds the hash of a resume reference")
	Set reminder = ..Remind(session)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SessionOpsProduction).Resumes(reference), session, "control: the reference resumes the session before the sign-out")
	Set held = ##class(OcuTalon.Data.Reminder).RefIndexOpen(reminder, 4)
	Do $$$AssertTrue($IsObject(held), "the test holds the reminder's row")
	Set body = ..Call(.response, .endSession, .loggedOut)
	Do $$$AssertEquals(response.Status, "500 Internal Server Error", "the sign-out is 500")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SessionOpsProduction).Resumes(reference), session, "and the reference still resumes the session")
	Set held = ""
	Set body = ..Call(.response, .endSession, .loggedOut)
	Do $$$AssertEquals(response.Status, "204 No Content", "with the row free, the same call is 204")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SessionOpsProduction).Resumes(reference), "", "and the reference resumes nothing")
}

/// Off the online demo (the flag 0, as on a local install) the route is the sign-out alone, as before Story 16.4: 204 with no body and the
/// CSP session logged out, while no cookie is set, no command goes to SessionOps and the attached session's pending reminder stays pending.
Method TestEndRouteOffTheOnlineDemo()
{
	If '..Guard() Quit
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set reminder = ..Remind(session)
	Set body = ..Call(.response, .endSession, .loggedOut)
	Do $$$AssertEquals(response.Status_"|"_body, "204 No Content|", "204 with no body")
	Do $$$AssertEquals(loggedOut_"|"_endSession, "1|1", "the CSP session is logged out and is to end")
	Do $$$AssertEquals($Order(response.Cookies("")), "", "no cookie is set")
	Hang 1
	Do $$$AssertEquals(..Hops(trace, "CommandsIn", "SessionOps"), 0, "no command went to SessionOps")
	Do $$$AssertEquals(##class(OcuTalon.Data.Reminder).RefIndexOpen(reminder).State, "pending", "and the session's reminder is still pending")
}

/// A CSP session that no OcuTalon session resolves for (the attach failed at sign-in): the route signs it out and answers 204, with no
/// cookie and no command to SessionOps.
Method TestNoAttachedSession()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set body = ..Call(.response, .endSession, .loggedOut, 1)
	Do $$$AssertEquals(response.Status_"|"_body, "204 No Content|", "204 with no body")
	Do $$$AssertEquals(loggedOut_"|"_endSession, "1|1", "the CSP session is logged out and is to end")
	Do $$$AssertEquals($Order(response.Cookies("")), "", "and no cookie is set")
	Hang 1
	Do $$$AssertEquals(..Hops(trace, "CommandsIn", "SessionOps"), 0, "no command went to SessionOps")
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
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Do ..Traces.%Push(..TraceOf(ref))
	Set ..Current = ref
	Quit ref
}

/// The TraceRef of the session.
Method TraceOf(ref As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef
}

/// A real reminder of the session, due in an hour (ReminderFixture.Set); recorded for the clean-up. Returns its Ref.
Method Remind(session As %String) As %String [ Private ]
{
	Set made = ##class(OcuTalon.Test.Schedule.ReminderFixture).Set(session, "zz session end "_..Number, 3600)
	Do $$$AssertEquals(made.ok_"|"_made.outcome, "1|set", "a real reminder is set")
	Set ..Reminders = ..Reminders_$Select(..Reminders = "": "", 1: ",")_made.ref
	Quit made.ref
}

/// Calls the route as the CSP session of the current session, through Written; response is the %response and the result what the route
/// wrote. endSession is the CSP session's EndSession flag after the call, and loggedOut the number of OnLogout calls that the stand-in
/// session saw. With noSession the CSP session holds no OcuTalon session.
Method Call(Output response, Output endSession As %Boolean, Output loggedOut As %Integer, noSession As %Boolean = 0) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", "POST")
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzSessionEnd"_..Number, 0)
	Set %session.EventClass = "OcuTalon.Test.Web.LogoutProbe"
	Kill ^||OcuTalonLogoutProbe
	If 'noSession Set %session.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY) = ..Current
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Api", "EndSession")
	Do $$$AssertStatusOK(sc, "EndSession returns OK")
	Set response = %response
	Set endSession = +%session.EndSession
	Set loggedOut = +$Get(^||OcuTalonLogoutProbe)
	Kill ^||OcuTalonLogoutProbe
	Quit written
}

/// The error body of the route for the code and the message.
Method ErrorBody(code As %String, message As %String) As %String [ Private ]
{
	Quit {"error": {"code": (code), "message": (message)}}.%ToJSON()
}

/// The UTC time YYYY-MM-DDThh:mm:ssZ of an RFC 1123 date ("Thu, 01 Jan 1970 00:00:00 GMT"), "" when it is not one.
Method IsoOf(date As %String) As %String [ Private ]
{
	Set month = $ListFind($ListFromString(##class(OcuTalon.Data.Time).#MONTHS), $Piece(date, " ", 3))
	If 'month Quit ""
	Quit $Piece(date, " ", 4)_"-"_$Extract(100 + month, 2, 3)_"-"_$Piece(date, " ", 2)_"T"_$Piece(date, " ", 5)_"Z"
}

/// The number of requests from the source item to the target item in the trace session of the session.
Method Hops(trace As %String, source As %String, target As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, source, target).%Size()
}

}
