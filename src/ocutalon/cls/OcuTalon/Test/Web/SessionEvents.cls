/// Tests of the session events of /ocutalon (Story 2.2; AD-4): the sign-in attaches the user's durable session when the
/// user holds the role, does nothing without it, and answers OK even when the attach fails, because an error status from
/// OnLogin neither logs the user out nor shows the sign-in page, and writes a failed attach to the console log (messages.log)
/// as one line that names the error code and no user. The role is passed to AttachFor, which OnLogin calls with
/// Shell.HasRole(). The session row that the test may create for the running user is removed by Test.Data.Fixture.Clean.
/// Story 16.3 adds the online demo's branch (TestFirstSignIn, TestResume, TestUnknownCookie, TestLimit, TestExempt,
/// TestClientAddress, TestFlagOff): each test starts with the flag off, saves and restores onlineDemo, proxyAddress,
/// resetAnchor, resetIntervalHours and the address limit's row, and removes its session rows and counter rows after, also
/// when it failed. The sign-ins are in process, with a stand-in request and response, as the user that runs the tests.
Class OcuTalon.Test.Web.SessionEvents Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do ..DropVisitors()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

/// Saves the settings that the tests change and starts each test with the flag off, no proxy and a four-hour reset.
Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^||SessionEventsSaved, ^||SessionEventsAddresses
	Set settings = "OcuTalon.Data.Public.Settings"
	For key = "onlineDemo", "proxyAddress", "resetAnchor", "resetIntervalHours" {
		Set ^||SessionEventsSaved(key) = $ClassMethod(settings, "Get", key)
	}
	Set limitKey = ##class(OcuTalon.Data.Setting).#ADDRESSLIMITKEY
	Set ^||SessionEventsSaved("limitRow") = $Select(##class(OcuTalon.Data.Setting).KeyIndexExists(limitKey, .id): ##class(OcuTalon.Data.Setting).%OpenId(id).Value, 1: $Char(0))
	Do $ClassMethod(settings, "Set", "onlineDemo", "")
	Do $ClassMethod(settings, "Set", "proxyAddress", "")
	Do $ClassMethod(settings, "Set", "resetAnchor", "2026-10-18T00:00:00Z")
	Do $ClassMethod(settings, "Set", "resetIntervalHours", 4)
	Quit $SYSTEM.Status.OK()
}

/// Puts the settings back, and removes the session rows and the counter rows of the test.
Method OnAfterOneTest(testname As %String) As %Status
{
	Set settings = "OcuTalon.Data.Public.Settings"
	Set key = ""
	For {
		Set key = $Order(^||SessionEventsSaved(key), 1, value)
		Quit:key=""
		If key = "limitRow" Continue
		Do $ClassMethod(settings, "Set", key, value)
	}
	Do ..SetLimit($Get(^||SessionEventsSaved("limitRow")))
	Set address = ""
	For {
		Set address = $Order(^||SessionEventsAddresses(address))
		Quit:address=""
		Do ..DropCounter(address)
	}
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Kill ^||SessionEventsSaved, ^||SessionEventsAddresses
	Quit $SYSTEM.Status.OK()
}

/// The first sign-in of a browser (Story 16.3, matrix row 1): a new row with its own Ref, TraceRef and Epoch, the signed-in user,
/// the CSP session id and only the hash of the new reference; the CSP session holds the Ref and no reference; one cookie holds
/// the reference with the AC's attributes and the expiry of the next reset. The expiry is also fixed for an anchor and a time.
Method TestFirstSignIn()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Set sc = ..SignIn("", "ZzSignInOne", , , .session, .response)
	Do $$$AssertStatusOK(sc, "the sign-in answers OK")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), before + 1, "one row is created")
	Set ref = $Get(session.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY))
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(row), "the CSP session holds the Ref of the new row")
	If '$IsObject(row) Quit
	Do ##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	Do $$$AssertEquals(row.IrisUser, $Username, "the row is the signed-in user's")
	Do $$$AssertEquals(row.CspSessionId, "ZzSignInOne", "it records the CSP session")
	For field = "Ref", "TraceRef", "Epoch" {
		Do $$$AssertTrue($Property(row, field) ? 22(1AN,1"-",1"_"), field_" is 22 base64url characters")
	}
	Do $$$AssertEquals(response.Cookies(1, "n"), "OcuTalonResume", "the cookie's name")
	Set reference = response.Cookies(1, "v")
	Do $$$AssertTrue(reference ? 22(1AN,1"-",1"_"), "the cookie holds 22 base64url characters")
	Do $$$AssertEquals($Order(response.Cookies(1)), "", "and it is the only cookie")
	Do $$$AssertEquals(response.Cookies(1, "p"), "/ocutalon/", "path /ocutalon/")
	Do $$$AssertEquals(response.Cookies(1, "d"), "", "no domain")
	Do $$$AssertEquals(response.Cookies(1, "s"), 1, "Secure")
	Do $$$AssertEquals(response.Cookies(1, "h"), 1, "HttpOnly")
	Do $$$AssertEquals(response.Cookies(1, "ss"), "strict", "SameSite strict")
	Do $$$AssertTrue(response.Cookies(1, "e") ? 3A1", "2N1" "3A1" "4N1" "2N1":"2N1":"2N1" GMT", "it expires at an RFC 1123 date: "_response.Cookies(1, "e"))
	Do $$$AssertEquals(response.Cookies(1, "e"), ##class(OcuTalon.Web.SessionEvents).CookieExpiry(##class(OcuTalon.Data.Public.Settings).NextReset()), "the date is the next reset's")
	Do $$$AssertEquals(row.ResumeHash, ##class(OcuTalon.Data.Session).Hash(reference), "the row keeps the SHA-256 of the reference")
	Do $$$AssertEquals($Length(row.ResumeHash), 43, "of 43 characters")
	Set found = 0
	For field = "Ref", "TraceRef", "IrisUser", "CreatedAt", "Epoch", "ThreadSessionId", "ThreadDay", "ResumeHash", "CspSessionId" {
		If $Property(row, field) = reference Set found = 1
	}
	Do $$$AssertEquals(found, 0, "no property of the row equals the reference")
	Set found = 0
	Set key = ""
	For {
		Set key = $Order(session.Data(key), 1, value)
		Quit:key=""
		If (value = reference) || (key = reference) Set found = 1
	}
	Do $$$AssertEquals(found, 0, "and the CSP session's data holds no reference")
	Do $$$AssertEquals($Data(session.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), 0, "no refusal is recorded")

	Do ##class(OcuTalon.Data.Public.Settings).Set("resetAnchor", "2026-10-18T00:00:00Z")
	Do ##class(OcuTalon.Data.Public.Settings).Set("resetIntervalHours", 4)
	Do $$$AssertEquals(##class(OcuTalon.Web.SessionEvents).CookieExpiry(##class(OcuTalon.Data.Public.Settings).NextReset("2026-10-25T15:20:00Z")), "Sun, 25 Oct 2026 16:00:00 GMT", "the expiry of a fixed anchor and time")
	Do $$$AssertEquals(##class(OcuTalon.Web.SessionEvents).CookieExpiry("2026-12-31T23:59:59Z"), "Thu, 31 Dec 2026 23:59:59 GMT", "a Thursday in December")
	Do $$$AssertEquals(##class(OcuTalon.Web.SessionEvents).CookieExpiry(""), "", "no next reset gives no expiry")
	Do $$$AssertEquals(##class(OcuTalon.Web.SessionEvents).CookieExpiry("soon"), "", "nor does an unreadable time")
	Do ##class(OcuTalon.Data.Public.Settings).Set("resetAnchor", "")
	Do $$$AssertEquals(##class(OcuTalon.Web.SessionEvents).CookieExpiry(##class(OcuTalon.Data.Public.Settings).NextReset()), "", "an unset anchor gives a browser-session cookie")
}

/// A resume (matrix row 3): the cookie of a row of the signed-in user attaches that row to the new CSP session, whatever the row's
/// CSP session id was, and also when it equals the new one; no cookie is set and no counter row is written, at the proxy too. A
/// cookie that opens another user's row gives a fresh row and a cookie.
Method TestResume()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "192.0.2.10")
	Set address = ..Address("resume")
	Do ..SignIn("", "ZzResumeOne", "192.0.2.10", address, .first, .response)
	Set reference = $Get(response.Cookies(1, "v"))
	Set ref = $Get(first.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY))
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(row) && (reference '= ""), "the first sign-in creates a row and a cookie")
	If '$IsObject(row) Quit
	Do ##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	Set rows = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Set counted = ..CounterRows(address)
	Do $$$AssertEquals(counted, 1, "the creation was counted")

	Do $$$AssertStatusOK(..SignIn(reference, "ZzResumeTwo", "192.0.2.10", address, .second, .response), "the resume answers OK")
	Do $$$AssertEquals($Get(second.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)), ref, "the new CSP session holds the row's Ref")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(ref).CspSessionId, "ZzResumeTwo", "the row records the new CSP session")
	Do $$$AssertEquals($Order(response.Cookies("")), "", "no cookie is set")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), rows, "no row is created")
	Do $$$AssertEquals(..CounterRows(address), counted, "and no counter row is written")

	Do $$$AssertStatusOK(..SignIn(reference, "ZzResumeTwo", "192.0.2.10", address, .third, .response), "a resume with a session id equal to the row's answers OK")
	Do $$$AssertEquals($Get(third.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)), ref, "the row is attached again")
	Do $$$AssertEquals($Order(response.Cookies("")), "", "with no cookie")
	Do $$$AssertEquals(..CounterRows(address), counted, "and no counter row")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), rows, "and no row")

	Set foreign = ##class(OcuTalon.Test.Data.Fixture).Session("zzsessionevents"_$Increment(^OcuTalonTest("SessionEvents", "n")))
	Set foreignRow = ##class(OcuTalon.Data.Session).RefIndexOpen(foreign)
	Set other = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set foreignRow.ResumeHash = ##class(OcuTalon.Data.Session).Hash(other)
	Do foreignRow.%Save()
	Do $$$AssertStatusOK(..SignIn(other, "ZzResumeFour", , , .fourth, .response), "another user's cookie answers OK")
	Set freshRef = $Get(fourth.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY))
	Do $$$AssertTrue((freshRef '= "") && (freshRef '= foreign) && (freshRef '= ref), "it gives a fresh row")
	Do ..AdoptRef(freshRef)
	Do $$$AssertEquals($Get(response.Cookies(1, "n")), "OcuTalonResume", "and a cookie")
	Do $$$AssertTrue($Get(response.Cookies(1, "v")) '= other, "with a new reference")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(foreign).CspSessionId, "", "the other user's row is not touched")
}

/// An unknown cookie (matrix row 5): a reference of no row, a malformed value and the reference of a deleted row each give a fresh
/// row, a new cookie with a different value, and a hash that opens only the new row.
Method TestUnknownCookie()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Set deletedRef = ""
	Do ..SignIn("", "ZzUnknownDel", , , .gone, .response)
	Set deletedReference = $Get(response.Cookies(1, "v"))
	Set deletedRef = $Get(gone.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY))
	Do ##class(OcuTalon.Data.Session).%DeleteId(##class(OcuTalon.Data.Session).RefIndexOpen(deletedRef).%Id())
	Set cases = $ListBuild(##class(OcuTalon.Bridge.Ids).NewRef(), "short", "!!!!!!!!!!!!!!!!!!!!!!", ##class(OcuTalon.Bridge.Ids).NewRef()_"x", deletedReference)
	Set position = 0
	While $ListNext(cases, position, cookie) {
		Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
		Do $$$AssertStatusOK(..SignIn(cookie, "ZzUnknown"_position, , , .session, .response), "a cookie of no row answers OK")
		Set ref = $Get(session.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY))
		Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), before + 1, "a fresh row is created")
		Do ..AdoptRef(ref)
		Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
		Do $$$AssertTrue($IsObject(row), "the CSP session holds its Ref")
		Set reference = $Get(response.Cookies(1, "v"))
		Do $$$AssertTrue(reference ? 22(1AN,1"-",1"_"), "a new cookie is set")
		Do $$$AssertTrue(reference '= cookie, "with a different value")
		If $IsObject(row) Do $$$AssertEquals(row.ResumeHash, ##class(OcuTalon.Data.Session).Hash(reference), "the row keeps the new reference's hash")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForResume(deletedReference), "", "the deleted row's hash opens no row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForResume(cookie), "", "nor does the unknown value")
}

/// The limit (matrix row 10): at the proxy, five creations for one address are counted and the sixth is refused with the marker
/// $ListBuild("addressLimit", oldest + 1 hour): no row, no cookie and no Ref in the CSP session. A resume at the limit still works, and
/// the right-most forwarded entry is the address, so a list that ends in another address counts that one.
Method TestLimit()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "192.0.2.10")
	Do ..SetLimit(5)
	Set address = ..Address("limit")
	Set first = ""
	For i = 1:1:5 {
		Do $$$AssertStatusOK(..SignIn("", "ZzLimit"_i, "192.0.2.10", address, .session, .response), "creation "_i_" answers OK")
		Set ref = $Get(session.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY))
		Do $$$AssertTrue(ref '= "", "creation "_i_" gets a session")
		Do ..AdoptRef(ref)
		If i = 1 Set first = $Get(response.Cookies(1, "v"))
	}
	Do $$$AssertEquals(..CounterRows(address), 5, "five counter rows")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.AddressCounter).FreeInAnotherJob(address), 1, "the address's lock is released after the creations")
	Set rows = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Do $$$AssertStatusOK(..SignIn("", "ZzLimit6", "192.0.2.10", address, .refused, .response), "the sixth answers OK")
	Do $$$AssertEquals($Get(refused.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)), "", "it attaches nothing")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), rows, "it creates no row")
	Do $$$AssertEquals($Order(response.Cookies("")), "", "it sets no cookie")
	Do $$$AssertEquals(..CounterRows(address), 5, "and writes no counter row")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.AddressCounter).FreeInAnotherJob(address), 1, "the address's lock is released after the refusal")
	Set marker = $Get(refused.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY))
	Do $$$AssertEquals($List(marker, 1), "addressLimit", "the marker names the state")
	Set oldest = ..OldestCounter(address)
	Do $$$AssertEquals($List(marker, 2), ##class(OcuTalon.Data.AddressCounter).Shift(oldest, 3600), "and the oldest counted creation plus one hour")
	Do $$$AssertTrue($List(marker, 2) ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "as a UTC time")

	Do $$$AssertStatusOK(..SignIn(first, "ZzLimitResume", "192.0.2.10", address, .resumed, .response), "a resume at the limit answers OK")
	Do $$$AssertTrue($Get(resumed.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)) '= "", "it attaches the row")
	Do $$$AssertEquals($Data(resumed.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), 0, "and records no refusal")
	Do $$$AssertEquals(..CounterRows(address), 5, "and counts nothing")

	Set other = ..Address("limitother")
	Do $$$AssertStatusOK(..SignIn("", "ZzLimitList", "192.0.2.10", address_", "_other, .listed, .response), "a forwarded list that ends in another address answers OK")
	Do ..AdoptRef($Get(listed.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)))
	Do $$$AssertTrue($Get(listed.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)) '= "", "it is allowed: the right-most entry counts")
	Do $$$AssertEquals(..CounterRows(other), 1, "and counts the other address")
	Do $$$AssertEquals(..CounterRows(address), 5, "not the first")
}

/// The limit is the setting's value (matrix row 10, AC 5): with 2 the third creation of an address is refused, and with 7 the
/// seventh is allowed and the eighth refused; each refused one records the marker and creates nothing.
Method TestLimitIsTheSetting()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "192.0.2.10")
	For limit = 2, 7 {
		Do ..SetLimit(limit)
		Set address = ..Address("setlimit"_limit)
		For i = 1:1:limit + 1 {
			Do ..SignIn("", "ZzSetLimit"_limit_"x"_i, "192.0.2.10", address, .session, .response)
			Set ref = $Get(session.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY))
			If i <= limit {
				Do $$$AssertTrue(ref '= "", "limit "_limit_": creation "_i_" is allowed")
				Do ..AdoptRef(ref)
			} Else {
				Do $$$AssertEquals(ref, "", "limit "_limit_": creation "_i_" is refused")
				Do $$$AssertEquals($List($Get(session.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), 1), "addressLimit", "limit "_limit_": with the marker")
			}
		}
		Do $$$AssertEquals(..CounterRows(address), limit, "limit "_limit_": that many counter rows")
	}
}

/// Exempt sign-ins (matrix rows 10 and 12): with no proxy set, or from an address that is not the proxy's, six creations that carry
/// a forwarded address are all allowed and write no counter row.
Method TestExempt()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Set address = ..Address("exempt")
	For proxy = "", "192.0.2.10" {
		Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", proxy)
		For i = 1:1:6 {
			Do ..SignIn("", "ZzExempt"_i, "198.51.100.7", address, .session, .response)
			Set ref = $Get(session.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY))
			Do $$$AssertTrue(ref '= "", "proxy '"_proxy_"': sign-in "_i_" gets a session")
			Do ..AdoptRef(ref)
			Do $$$AssertEquals($Data(session.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), 0, "proxy '"_proxy_"': sign-in "_i_" is not refused")
			Do $$$AssertEquals($Get(response.Cookies(1, "n")), "OcuTalonResume", "proxy '"_proxy_"': sign-in "_i_" gets a cookie")
		}
		Do $$$AssertEquals(..CounterRows(address), 0, "proxy '"_proxy_"': no counter row")
	}
}

/// ClientAddress (matrix row 12): behind the proxy the right-most forwarded entry, trimmed, or the proxy's own address with none;
/// anything that is not the proxy's own request, or with no proxy set, is exempt and its forwarded list is ignored.
Method TestClientAddress()
{
	Set class = "OcuTalon.Web.SessionEvents"
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", "192.0.2.10", "a, b", "192.0.2.10", .proxied), "b", "'a, b' gives b")
	Do $$$AssertEquals(proxied, 1, "and the request is proxied")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", "192.0.2.10", " b ", "192.0.2.10", .proxied), "b", "' b ' gives b")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", "192.0.2.10", "a,b,c ", "192.0.2.10", .proxied), "c", "the last of three")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", "192.0.2.10", "", "192.0.2.10", .proxied), "192.0.2.10", "no header gives the proxy's own address")
	Do $$$AssertEquals(proxied, 1, "still proxied")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", "192.0.2.10", "a, ", "192.0.2.10", .proxied), "192.0.2.10", "an empty last entry gives the proxy's own address")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", "203.0.113.5", "a, b", "192.0.2.10", .proxied), "", "not from the proxy: exempt")
	Do $$$AssertEquals(proxied, 0, "not proxied")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", "192.0.2.10", "a, b", "", .proxied), "", "with no proxy set: exempt")
	Do $$$AssertEquals(proxied, 0, "not proxied")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", "", "a", "", .proxied), "", "an empty remote address and no proxy: exempt")
	Do $$$AssertEquals(proxied, 0, "not proxied")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", "192.0.2.100", "a", "192.0.2.10", .proxied), "", "the proxy's address is matched exactly")
	Do $$$AssertEquals(proxied, 0, "not proxied")
}

/// The flag off (matrix row 9): the sign-in attaches the user's one durable session as before, sets no cookie, writes no counter
/// row and no setting row, and the Web step seeds nothing.
Method TestFlagOff()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "192.0.2.10")
	Set counters = ..CounterTotal()
	Set key = ##class(OcuTalon.Data.Setting).#ADDRESSLIMITKEY
	Do ..SetLimit($Char(0))
	Set had = ##class(OcuTalon.Data.Setting).KeyIndexExists(key)
	Do $$$AssertEquals(had, 0, "the limit's row is absent before the flag-off seed")
	Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Set address = ..Address("off")
	Do $$$AssertStatusOK(..SignIn("", "ZzOffOne", "192.0.2.10", address, .first, .response), "the sign-in answers OK")
	Set ref = $Get(first.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY))
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(row), "the user's durable session is attached")
	If $IsObject(row), before = 0 Do ##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	Do $$$AssertEquals($Order(response.Cookies("")), "", "no cookie is set")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), $Select(before = 0: 1, 1: before), "one row for the user")
	Do $$$AssertEquals(row.ResumeHash, "", "it has no resume hash")
	Do $$$AssertStatusOK(..SignIn("", "ZzOffTwo", "192.0.2.10", address, .second, .response), "a second sign-in answers OK")
	Do $$$AssertEquals($Get(second.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)), ref, "it gets the same session")
	Do $$$AssertEquals(..CounterTotal(), counters, "no counter row is written")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexExists(key), had, "no setting row is written")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).SeedSettings(), "the Web step's seed answers OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexExists(key), had, "and seeds nothing")
}

/// The number of nodes of the OCUTALON namespace's globals that sit in the given databases (names, comma-separated) and hold the value in a
/// subscript or in their data: the unit's scan for the resume reference (matrix row 6). It prints and keeps nothing, and answers -1 for an
/// empty value or a database that does not exist, so that an empty search never reads as a clean one. It reads the databases' directories
/// from %SYS, and enumerates the namespace's globals with %SYS.GlobalQuery (system globals included).
ClassMethod ReferenceHits(value As %String, databases As %String = "OCUTALON_DATA,OCUTALON_PRIVATE,OCUTALON_PUBLIC") As %Integer
{
	If value = "" Quit -1
	New $Namespace
	Set home = $Namespace
	Kill directories
	Set $Namespace = "%SYS"
	Set missing = 0
	For i = 1:1:$Length(databases, ",") {
		If $SYSTEM.Status.IsError(##class(Config.Databases).Get($Piece(databases, ",", i), .properties)) {
			Set missing = 1
			Quit
		}
		Set directories(##class(%File).NormalizeDirectory(properties("Directory"))) = ""
	}
	Set $Namespace = home
	If missing || '$Data(directories) Quit -1
	Set hits = 0
	Kill seen
	Set rows = ##class(%ResultSet).%New("%SYS.GlobalQuery:NameSpaceList")
	If $SYSTEM.Status.IsError(rows.Execute(home, "*", 1, , , , 1)) Quit -1
	While rows.Next() {
		Set location = ##class(%File).NormalizeDirectory(rows.Get("Location"))
		If '$Data(directories(location)) Continue
		Set name = $Piece($Piece(rows.Get("Name"), "(", 1), "^", $Length($Piece(rows.Get("Name"), "(", 1), "^"))
		If $Data(seen(location, name)) Continue
		Set seen(location, name) = ""
		Set reference = "^|""^^"_location_"""|"_name
		Set data = ""
		Set has = $Data(@reference, data)
		If ((has = 1) || (has = 11)) && (data [ value) Set hits = hits + 1
		For {
			Set reference = $Query(@reference, 1, data)
			Quit:reference=""
			If (reference [ value) || (data [ value) Set hits = hits + 1
		}
	}
	Quit hits
}

/// The OnLogin work for a sign-in in process: a CSP session with the id, a stand-in request with the cookie, the remote address,
/// the forwarded list and a response; the CSP session and the response come back in session and response. The status is AttachFor's.
Method SignIn(cookie As %String, sessionId As %String, remote As %String = "", forwarded As %String = "", Output session, Output response) As %Status [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/")
	If cookie '= "" Set %request.Cookies("OcuTalonResume", 1) = cookie
	If remote '= "" Set %request.CgiEnvs("REMOTE_ADDR") = remote
	If forwarded '= "" Set %request.CgiEnvs("HTTP_X_FORWARDED_FOR") = forwarded
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New(sessionId, 0)
	Set sc = ##class(OcuTalon.Web.SessionEvents).AttachFor(1)
	Set session = %session
	Set response = %response
	Quit sc
}

/// A client address of this test, unique to the run and to the case, and registered for the clean-up.
Method Address(case As %String) As %String [ Private ]
{
	Set address = "zz-sessionevents-"_$Increment(^OcuTalonTest("SessionEvents", "n"))_"-"_case
	Set ^||SessionEventsAddresses(address) = ""
	Quit address
}

/// The number of counter rows of an address.
ClassMethod CounterRows(address As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?", ##class(OcuTalon.Data.Session).Hash(address))
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The number of counter rows.
ClassMethod CounterTotal() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.AddressCounter")
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The earliest CreatedAt among the counter rows of an address.
ClassMethod OldestCounter(address As %String) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MIN(CreatedAt) FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?", ##class(OcuTalon.Data.Session).Hash(address))
	Do result.%Next()
	Quit result.%GetData(1)
}

/// Deletes the counter rows of an address.
ClassMethod DropCounter(address As %String) [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?", ##class(OcuTalon.Data.Session).Hash(address))
}

/// Deletes the visitor rows (those with a resume hash) of the user that runs the tests: what an earlier run that failed may have left, which
/// would otherwise be found by the flag-off test's lookup by user name. Like the class's other tests, it runs on a throwaway only.
ClassMethod DropVisitors() [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Session WHERE IrisUser = ? AND ResumeHash IS NOT NULL", $Username)
	While result.%Next() {
		Do ##class(OcuTalon.Data.Session).%DeleteId(result.%Get("ID"))
	}
}

/// Records the session row of a Ref for Fixture.Clean.
ClassMethod AdoptRef(ref As %String) [ Private ]
{
	If ref = "" Quit
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	If $IsObject(row) Do ##class(OcuTalon.Test.Data.Fixture).Adopt(row)
}

/// Sets the address limit's row to a value, or removes it for $Char(0), and drops this process's cache entry: the test's own
/// way to fix the limit (the row may exist on a stack that seeded it).
ClassMethod SetLimit(value As %String) [ Private ]
{
	Set key = ##class(OcuTalon.Data.Setting).#ADDRESSLIMITKEY
	Set exists = ##class(OcuTalon.Data.Setting).KeyIndexExists(key, .id)
	If value = $Char(0) {
		If exists Do ##class(OcuTalon.Data.Setting).%DeleteId(id)
	} ElseIf exists {
		Set row = ##class(OcuTalon.Data.Setting).%OpenId(id)
		Set row.Value = value
		Do row.%Save()
	} Else {
		Do ##class(OcuTalon.Data.Setting).Seed(key, value)
	}
	Kill ^||OcuTalon.Setting(key)
}

/// A failed attach (no CSP session) still answers OK and creates no row; without the role nothing is attached or
/// created; with the role the user's durable session is recorded in the CSP session.
Method TestAttachForAlwaysAnswersOK()
{
	New %session
	Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Set %session = ""
	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(1), "a failed attach still answers OK")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), before, "and creates no session row")

	Set %session = ##class(%CSP.Session).%New("ZzSessionEvents", 0)
	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(0), "without the role it answers OK")
	Do $$$AssertEquals($Get(%session.Data("OcuTalon.SessionRef")), "", "attaches nothing")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), before, "and creates no session row")

	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(1), "with the role it answers OK")
	Set ref = $Get(%session.Data("OcuTalon.SessionRef"))
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(row), "and the user's durable session is recorded in the CSP session")
	If $IsObject(row) {
		Do $$$AssertEquals($ZConvert(row.IrisUser, "U"), $ZConvert($Username, "U"), "it is the signed-in user's")
		If before = 0 Do ##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), $Select(before = 0: 1, 1: before), "one row for the user")
}

/// A failed attach is written to the console log as exactly one new line of OcuTalon.Web.SessionEvents, whose text is the
/// fixed sentence and the error code and nothing else, so it holds no user name; an attach that works, and a user without
/// the role, write no such line. The console log folds a message that repeats the one before it, so a line of this test's
/// own is written first and the attach's line is never a repeat.
Method TestFailureIsLoggedWithoutTheUser()
{
	New %session
	Set log = $System.Util.ManagerDirectory()_"messages.log"
	Do $$$AssertTrue(##class(%File).Exists(log), "the console log exists: "_log)
	Set %session = ""
	Do ##class(%SYS.System).WriteToConsoleLog("OcuTalon.Test.Web.SessionEvents: a line that the attach's is not a repeat of", 0, 0)
	Set mark = ##class(%File).GetFileSize(log)
	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(1), "a failed attach answers OK")
	Set lines = ..LinesSince(log, mark)
	Do $$$AssertEquals($ListLength(lines), 1, "and writes one line of OcuTalon.Web.SessionEvents to the console log")
	If $ListLength(lines) = 1 {
		Set text = $Piece($List(lines, 1), "OcuTalon.Web.SessionEvents: ", 2)
		Do $$$AssertEquals(text, "the session could not be attached, error 5001", "the line holds the sentence and the error code only, so no user name")
	}

	Set %session = ##class(%CSP.Session).%New("ZzSessionEventsLog", 0)
	Set mark = ##class(%File).GetFileSize(log)
	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(0), "without the role it answers OK")
	Do $$$AssertEquals($ListLength(..LinesSince(log, mark)), 0, "and writes no line")
	Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(1), "with the role and a CSP session it answers OK")
	Do $$$AssertEquals($ListLength(..LinesSince(log, mark)), 0, "and writes no line")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen($Get(%session.Data("OcuTalon.SessionRef")))
	If before = 0, $IsObject(row) Do ##class(OcuTalon.Test.Data.Fixture).Adopt(row)
}

/// The lines of OcuTalon.Web.SessionEvents that the console log gained after byte offset mark, as a $List of lines.
ClassMethod LinesSince(log As %String, mark As %Integer) As %List [ Private ]
{
	Set stream = ##class(%Stream.FileBinary).%New()
	Do stream.LinkToFile(log)
	Do stream.MoveTo(mark + 1)
	Set text = ""
	While 'stream.AtEnd {
		Set text = text_stream.Read(32000)
	}
	Set lines = ""
	For i = 1:1:$Length(text, $Char(10)) {
		Set line = $Piece(text, $Char(10), i)
		If line [ "OcuTalon.Web.SessionEvents: " Set lines = lines_$ListBuild(line)
	}
	Quit lines
}

}
