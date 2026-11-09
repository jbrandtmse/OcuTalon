/// Tests of the session events of /ocutalon (Story 2.2; AD-4): the sign-in attaches the user's durable session when the
/// user holds the role, does nothing without it, and answers OK even when the attach fails, because an error status from
/// OnLogin neither logs the user out nor shows the sign-in page, and writes a failed attach to the console log (messages.log)
/// as one line that names the error code and no user. The role is passed to AttachFor, which OnLogin calls with
/// Shell.HasRole(). The session row that the test may create for the running user is removed by Test.Data.Fixture.Clean.
/// Story 16.3 adds the online demo's branch (TestFirstSignIn, TestResume, TestUnknownCookie, TestLimit, TestLimitIsTheSetting,
/// TestExempt, TestClientAddress, TestFlagOff, TestNoRoleOnTheOnlineDemo, and QA's TestTamperedCookie,
/// TestFlagOffIgnoresTheCookie and TestClientAddressEdges) and Story 29.7's TestVisitorMarker (the counted visitor's marker, set only on a
/// proxied attach, and OWNCONNECTIONS = 0): each test starts with the flag off, saves and restores onlineDemo, proxyAddress,
/// resetAnchor, resetIntervalHours and the address limit's row, and removes its session rows and counter rows after, also
/// when it failed. The sign-ins are in process, with a stand-in request and response, as the user that runs the tests.
/// Story 31.1's TestSignOutMark covers OnLogout: it raises the session's sign-out mark by one off the online demo, changes no field
/// of the session row (every stored property of Data.Session, derived from its definition) and always answers OK; on the online
/// demo it sets no mark node at all.
/// Story 35.2's TestAdminAtSignIn covers the admin flag of the sign-in: AttachFor(1, 1) sets Session.AdminAtSignIn and lists the Ref in
/// Ownership.AdminSessions, an attach with no flag keeps it, AttachFor(1, 0) clears it, and no other stored property changes.
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
	Kill ^||SessionEventsSaved, ^||SessionEventsAddresses, ^||SessionEventsAdminWas
	Set settings = "OcuTalon.Data.Public.Settings"
	For key = "onlineDemo", "proxyAddress", "resetAnchor", "resetIntervalHours", "connectionCap", "connectionReserve" {
		Set ^||SessionEventsSaved(key) = $ClassMethod(settings, "Get", key)
	}
	Set limitKey = ##class(OcuTalon.Data.Setting).#ADDRESSLIMITKEY
	Set ^||SessionEventsSaved("limitRow") = $Select(##class(OcuTalon.Data.Setting).KeyIndexExists(limitKey, .id): ##class(OcuTalon.Data.Setting).%OpenId(id).Value, 1: $Char(0))
	Do $ClassMethod(settings, "Set", "onlineDemo", "")
	Do $ClassMethod(settings, "Set", "proxyAddress", "")
	Do $ClassMethod(settings, "Set", "resetAnchor", "2026-10-18T00:00:00Z")
	Do $ClassMethod(settings, "Set", "resetIntervalHours", 4)
	Do $ClassMethod(settings, "Set", "connectionCap", "")
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
	If $Data(^||SessionEventsAdminWas) Do ..SignIn("", "ZzAdminRestore", "", "", , , 1, ^||SessionEventsAdminWas)
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Kill ^||SessionEventsSaved, ^||SessionEventsAddresses, ^||SessionEventsAdminWas
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
	Do $$$AssertStatusOK(foreignRow.%Save(), "the other user's row takes a resume hash")
	Set opened = ##class(OcuTalon.Data.Session).ForResume(other)
	Do $$$AssertEquals($Select($IsObject(opened): opened.Ref, 1: ""), foreign, "and its reference opens it")
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
	Set unknown = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set cases = $ListBuild(unknown, "short", "!!!!!!!!!!!!!!!!!!!!!!", ##class(OcuTalon.Bridge.Ids).NewRef()_"x", deletedReference)
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
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForResume(unknown), "", "nor does the unknown value")
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

/// The busy refusal (Story 16.5, row 5): with the demo busy (a reserve larger than the cap forces it), a proxied sign-in records the marker
/// $ListBuild("busy") and nothing else: no session row, no Ref in the CSP session, no cookie, no counter row, no lock afterwards. A
/// valid resume cookie does not attach its row either: the row's CSP session is unchanged.
Method TestBusyRefusal()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "192.0.2.10")
	Set address = ..Address("busy")
	Do $$$AssertStatusOK(..SignIn("", "ZzBusyFirst", "192.0.2.10", address, .first, .response), "a sign-in while the demo is not busy answers OK")
	Set ref = $Get(first.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY))
	Do ..AdoptRef(ref)
	Set cookie = $Get(response.Cookies(1, "v"))
	Do $$$AssertTrue((ref '= "") && (cookie '= ""), "it gets a session and a cookie")
	Do $$$AssertEquals($Data(first.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), 0, "and no refusal")
	Do $$$AssertEquals(..CounterRows(address), 1, "it is counted once")

	Do ..ForceBusy()
	Set rows = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Do $$$AssertStatusOK(..SignIn("", "ZzBusyNew", "192.0.2.10", address, .refused, .response), "a proxied sign-in while busy answers OK")
	Do $$$AssertEquals($Get(refused.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), $ListBuild("busy"), "the marker is $ListBuild(""busy"")")
	Do $$$AssertEquals($Get(refused.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)), "", "it attaches nothing")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), rows, "it creates no row")
	Do $$$AssertEquals($Order(response.Cookies("")), "", "it sets no cookie")
	Do $$$AssertEquals(..CounterRows(address), 1, "it writes no counter row")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.AddressCounter).FreeInAnotherJob(address), 1, "no lock is held afterwards")

	Do $$$AssertStatusOK(..SignIn(cookie, "ZzBusyCookie", "192.0.2.10", address, .resumed, .response), "a proxied sign-in with a valid cookie while busy answers OK")
	Do $$$AssertEquals($Get(resumed.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), $ListBuild("busy"), "its marker is busy too")
	Do $$$AssertEquals($Get(resumed.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)), "", "the cookie's row is not attached")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(ref).CspSessionId, "ZzBusyFirst", "the cookie's row keeps its CSP session")
	Do $$$AssertEquals($Order(response.Cookies("")), "", "and no cookie is set")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.AddressCounter).FreeInAnotherJob(address), 1, "no lock is held after the cookie case either")

	Do ##class(OcuTalon.Data.Public.Settings).Set("connectionCap", "")
	Do $$$AssertStatusOK(..SignIn("", "ZzBusyAfter", "192.0.2.10", address, .after, .response), "with no cap a proxied sign-in answers OK")
	Do ..AdoptRef($Get(after.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)))
	Do $$$AssertTrue($Get(after.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)) '= "", "and is let in")
}

/// A request that is not proxied is exempt from the busy refusal (Story 16.5, row 7): with the demo busy, a sign-in with no proxy set,
/// and one from a remote other than the proxy, each creates a row and sets the cookie and records no refusal.
Method TestBusyExempt()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do ..ForceBusy()
	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "")
	Do $$$AssertStatusOK(..SignIn("", "ZzBusyNoProxy", "192.0.2.10", "", .one, .response), "with no proxy set a sign-in while busy answers OK")
	Do ..AdoptRef($Get(one.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)))
	Do $$$AssertTrue($Get(one.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)) '= "", "it is attached: a new row")
	Do $$$AssertTrue($Get(response.Cookies(1, "v")) '= "", "and the cookie is set")
	Do $$$AssertEquals($Data(one.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), 0, "with no marker")

	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "192.0.2.10")
	Do $$$AssertStatusOK(..SignIn("", "ZzBusyOther", "192.0.2.77", ..Address("busyother"), .two, .response), "a remote other than the proxy, while busy, answers OK")
	Do ..AdoptRef($Get(two.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)))
	Do $$$AssertTrue($Get(two.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)) '= "", "it is attached: a new row")
	Do $$$AssertTrue($Get(response.Cookies(1, "v")) '= "", "and the cookie is set")
	Do $$$AssertEquals($Data(two.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), 0, "with no marker")
}

/// The busy check comes before the resume and the counter (Story 16.5, row 8): at an address with five counter rows (the default
/// limit), a busy sign-in is refused as "busy", not "addressLimit", and the counter rows stay five; with a resumable cookie the
/// row is still not attached.
Method TestBusyBeforeTheCounter()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "192.0.2.10")
	Do ..SetLimit(5)
	Set address = ..Address("busycounter")
	Set cookie = ""
	For i = 1:1:5 {
		Do $$$AssertStatusOK(..SignIn("", "ZzBusyCounter"_i, "192.0.2.10", address, .made, .response), "creation "_i_" answers OK")
		Do ..AdoptRef($Get(made.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)))
		If i = 1 Set cookie = $Get(response.Cookies(1, "v")), ref = $Get(made.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY))
	}
	Do $$$AssertEquals(..CounterRows(address), 5, "five counter rows")
	Do ..ForceBusy()
	Do $$$AssertStatusOK(..SignIn("", "ZzBusySixth", "192.0.2.10", address, .sixth, .response), "the sixth, while busy, answers OK")
	Do $$$AssertEquals($Get(sixth.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), $ListBuild("busy"), "its marker is busy, not addressLimit")
	Do $$$AssertEquals(..CounterRows(address), 5, "the counter rows are unchanged")
	Do $$$AssertStatusOK(..SignIn(cookie, "ZzBusyResume", "192.0.2.10", address, .resumed, .response), "a resumable cookie, while busy, answers OK")
	Do $$$AssertEquals($Get(resumed.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), $ListBuild("busy"), "its marker is busy")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(ref).CspSessionId, "ZzBusyCounter1", "the cookie's row is not attached")
	Do $$$AssertEquals(..CounterRows(address), 5, "and the counter rows are still five")
}

/// (QA) A local install is never refused as busy (Story 16.5, AC 2 and 6): with the flag off or unset, a proxy set and the cap forced
/// busy, a proxied sign-in attaches the user's one durable session as before, sets no cookie, writes no counter row and records no
/// refusal.
Method TestFlagOffIgnoresBusy()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "192.0.2.10")
	Do ..ForceBusy()
	Set counters = ..CounterTotal()
	Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	For flag = "", "0" {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", flag)
		Set address = ..Address("busyoff")
		Do $$$AssertStatusOK(..SignIn("", "ZzBusyOff"_flag, "192.0.2.10", address, .session, .response), "flag '"_flag_"': a proxied sign-in while busy answers OK")
		Set ref = $Get(session.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY))
		Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
		Do $$$AssertTrue($IsObject(row), "flag '"_flag_"': the user's durable session is attached")
		If $IsObject(row), before = 0 Do ##class(OcuTalon.Test.Data.Fixture).Adopt(row)
		Do $$$AssertEquals($Data(session.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), 0, "flag '"_flag_"': no refusal is recorded")
		Do $$$AssertEquals($Order(response.Cookies("")), "", "flag '"_flag_"': no cookie is set")
		Do $$$AssertEquals(..CounterRows(address), 0, "flag '"_flag_"': no counter row for the address")
	}
	Do $$$AssertEquals(..CounterTotal(), counters, "no counter row is written")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), $Select(before = 0: 1, 1: before), "the user keeps one row")
}

/// The visitor marker (Story 29.7, matrix row 10): a proxied create and a proxied resume set Shell.VISITORKEY to 1 in the CSP session's
/// data. It is not set on a sign-in that is not proxied, a busy refusal, an address-limit refusal, with the flag off, or for a user without
/// the role. The new session leaves no own connection out (OWNCONNECTIONS is 0).
Method TestVisitorMarker()
{
	Set key = ##class(OcuTalon.Web.Public.Shell).#VISITORKEY
	Set sessionKey = ##class(OcuTalon.Data.Ownership).#SESSIONKEY
	Do $$$AssertEquals(##class(OcuTalon.Web.SessionEvents).#OWNCONNECTIONS, 0, "the busy check leaves no own connection out")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "192.0.2.10")
	Set address = ..Address("marker")
	Do $$$AssertStatusOK(..SignIn("", "ZzMarkerCreate", "192.0.2.10", address, .created, .response), "a proxied create answers OK")
	Set ref = $Get(created.Data(sessionKey))
	Do ..AdoptRef(ref)
	Do $$$AssertTrue(ref '= "", "it attaches a row")
	Do $$$AssertEquals($Get(created.Data(key)), 1, "a proxied create sets the marker to 1")
	Set cookie = $Get(response.Cookies(1, "v"))
	Do $$$AssertStatusOK(..SignIn(cookie, "ZzMarkerResume", "192.0.2.10", address, .resumed, .response), "a proxied resume answers OK")
	Do $$$AssertEquals($Get(resumed.Data(sessionKey)), ref, "it attaches the cookie's row")
	Do $$$AssertEquals($Get(resumed.Data(key)), 1, "a proxied resume sets the marker to 1")

	Do $$$AssertStatusOK(..SignIn("", "ZzMarkerOther", "192.0.2.77", ..Address("markerother"), .other, .response), "a request from a remote other than the proxy answers OK")
	Do ..AdoptRef($Get(other.Data(sessionKey)))
	Do $$$AssertTrue($Get(other.Data(sessionKey)) '= "", "it is let in")
	Do $$$AssertEquals($Data(other.Data(key)), 0, "a sign-in that is not proxied is not marked")
	Do $$$AssertStatusOK(..SignIn(cookie, "ZzMarkerResumeDirect", "192.0.2.77", address, .direct, .response), "a resume that is not proxied answers OK")
	Do $$$AssertEquals($Get(direct.Data(sessionKey)), ref, "it attaches the cookie's row")
	Do $$$AssertEquals($Data(direct.Data(key)), 0, "a resume that is not proxied is not marked")
	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "")
	Do $$$AssertStatusOK(..SignIn("", "ZzMarkerNoProxy", "192.0.2.10", ..Address("markernoproxy"), .noproxy, .response), "a sign-in with no proxy set answers OK")
	Do ..AdoptRef($Get(noproxy.Data(sessionKey)))
	Do $$$AssertTrue($Get(noproxy.Data(sessionKey)) '= "", "it is let in")
	Do $$$AssertEquals($Data(noproxy.Data(key)), 0, "and is not marked either")
	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "192.0.2.10")

	Do ..ForceBusy()
	Do $$$AssertStatusOK(..SignIn("", "ZzMarkerBusy", "192.0.2.10", ..Address("markerbusy"), .busy, .response), "a busy refusal answers OK")
	Do $$$AssertEquals($Get(busy.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), $ListBuild("busy"), "it records the busy refusal")
	Do $$$AssertEquals($Data(busy.Data(key)), 0, "a busy refusal is not marked")
	Do ##class(OcuTalon.Data.Public.Settings).Set("connectionCap", "")

	Do ..SetLimit(1)
	Set limited = ..Address("markerlimit")
	Do $$$AssertStatusOK(..SignIn("", "ZzMarkerLimitOne", "192.0.2.10", limited, .first, .response), "the first creation of a limited address answers OK")
	Do ..AdoptRef($Get(first.Data(sessionKey)))
	Do $$$AssertEquals($Get(first.Data(key)), 1, "and is marked")
	Do $$$AssertStatusOK(..SignIn("", "ZzMarkerLimitTwo", "192.0.2.10", limited, .second, .response), "the second answers OK")
	Do $$$AssertEquals($List($Get(second.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), 1), "addressLimit", "it records the address-limit refusal")
	Do $$$AssertEquals($Data(second.Data(key)), 0, "an address-limit refusal is not marked")

	Do $$$AssertStatusOK(..SignIn("", "ZzMarkerNoRole", "192.0.2.10", ..Address("markernorole"), .norole, .response, 0), "a user without the role answers OK")
	Do $$$AssertEquals($Data(norole.Data(key)), 0, "a user without the role is not marked")

	Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertStatusOK(..SignIn("", "ZzMarkerFlagOff", "192.0.2.10", ..Address("markeroff"), .off, .response), "with the flag off a proxied sign-in answers OK")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen($Get(off.Data(sessionKey)))
	If $IsObject(row), before = 0 Do ##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	Do $$$AssertEquals($Data(off.Data(key)), 0, "with the flag off nothing is marked")
}

/// Forces the busy state: a reserve larger than the cap is always busy, whatever the connections are.
Method ForceBusy() [ Private ]
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("connectionCap", 1)
	Do ##class(OcuTalon.Data.Public.Settings).Set("connectionReserve", 9)
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

/// The admin flag of the sign-in (Story 35.2): a sign-in with admin 1 sets the row's AdminAtSignIn and the Ref is in AdminSessions; an
/// attach with no flag (a first API call) keeps it; a sign-in with admin 0 clears it and the Ref leaves AdminSessions; the flag write
/// changes no other stored property.
Method TestAdminAtSignIn()
{
	Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	If before > 0 {
		Set found = ##class(%SQL.Statement).%ExecDirect(, "SELECT AdminAtSignIn FROM OcuTalon_Data.Session WHERE IrisUser = ?", $Username)
		If found.%Next() Set ^||SessionEventsAdminWas = +found.%GetData(1)
	}
	Do $$$AssertStatusOK(..SignIn("", "ZzAdminZero", "", "", .zero, , 1, 0), "a sign-in without the admin role answers OK")
	Set ref = $Get(zero.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY))
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(row), "the user's durable session is attached")
	If $IsObject(row), before = 0 Do ##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(ref).AdminAtSignIn, 0, "a non-admin's row holds 0")
	Do $$$AssertEquals($ListFind(##class(OcuTalon.Data.Ownership).AdminSessions(.sc), ref), 0, "and its Ref is not in AdminSessions")
	Do $$$AssertStatusOK(sc, "the read of AdminSessions answers OK")
	Set plain = ..RowText(ref)
	Do $$$AssertStatusOK(..SignIn("", "ZzAdminOne", "", "", .one, , 1, 1), "a sign-in with the admin role answers OK")
	Do $$$AssertEquals($Get(one.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)), ref, "it gets the same session")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(ref).AdminAtSignIn, 1, "an admin's row holds 1")
	Do $$$AssertTrue($ListFind(##class(OcuTalon.Data.Ownership).AdminSessions(.sc), ref) > 0, "and its Ref is in AdminSessions")
	Do $$$AssertEquals(..RowText(ref), $Replace(plain, "|AdminAtSignIn=0", "|AdminAtSignIn=1"), "no other stored property changed")
	Do $$$AssertStatusOK(..SignIn("", "ZzAdminKeep", "", "", .keep), "an attach with no flag answers OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(ref).AdminAtSignIn, 1, "and keeps the flag the latest sign-in set")
	New %session
	Set %session = ##class(%CSP.Session).%New("ZzAdminDirect", 0)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Ownership).Attach($Username), "Ownership.Attach with no flag answers OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(ref).AdminAtSignIn, 1, "and leaves the flag as it was")
	Do $$$AssertStatusOK(..SignIn("", "ZzAdminDown", "", "", .down, , 1, 0), "a later sign-in without the role answers OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(ref).AdminAtSignIn, 0, "clears the flag")
	Do $$$AssertEquals($ListFind(##class(OcuTalon.Data.Ownership).AdminSessions(.sc), ref), 0, "and the Ref leaves AdminSessions")
	Do $$$AssertStatusOK(sc, "that read of AdminSessions answers OK")
	Do $$$AssertEquals(..RowText(ref), plain, "the row is as it was before the admin sign-in")
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

/// (QA) A tampered or malformed cookie is never an error and never a resume (matrix row 5, AC 3): every decoration of a REAL reference
/// (one character changed, a character added, one removed, padding, white space, a line feed, a NUL, the other case, standard base64
/// letters, a wide character) answers OK, writes no log line, creates a fresh row with a new cookie, never touches the real row, and
/// opens no row through ForResume; at the end the real reference still resumes its row. A value of 4000 characters and one of no
/// permitted character behave the same.
Method TestTamperedCookie()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Set sessionKey = ##class(OcuTalon.Data.Ownership).#SESSIONKEY
	Do ..SignIn("", "ZzTamperOrig", , , .original, .response)
	Set reference = $Get(response.Cookies(1, "v"))
	Set ref = $Get(original.Data(sessionKey))
	Do $$$AssertTrue((reference '= "") && (ref '= ""), "the real session and its cookie exist")
	If (reference = "") || (ref = "") Quit
	Do ..AdoptRef(ref)
	Set first = $Extract(reference, 1)
	Set cases = $ListBuild($Select(first = "A": "B", 1: "A")_$Extract(reference, 2, 22), reference_"=", reference_"x", $Extract(reference, 1, 21), $Extract(reference, 2, 22), reference_$Char(10), " "_reference, reference_" ", reference_$Char(0), $Extract(reference, 1, 21)_$Char(233), $Extract(reference, 1, 21)_$Char(25991), $Extract(reference, 1, 20)_"+/", $Extract(reference, 1, 21)_"=", $ZConvert(reference, "U"), $ZConvert(reference, "L"), $Translate(reference, "-_", "+/"), $Translate($Justify("", 4000), " ", "A"), $Translate($Justify("", 22), " ", "!"))
	Set log = $System.Util.ManagerDirectory()_"messages.log"
	Set mark = ##class(%File).GetFileSize(log)
	Set position = 0
	Set n = 0
	While $ListNext(cases, position, cookie) {
		If cookie = reference Continue
		Set n = n + 1
		Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForResume(cookie), "", "case "_n_": the value opens no row")
		Do $$$AssertStatusOK(..SignIn(cookie, "ZzTamper"_n, , , .session, .response), "case "_n_": the sign-in answers OK")
		Set fresh = $Get(session.Data(sessionKey))
		Do $$$AssertTrue((fresh '= "") && (fresh '= ref), "case "_n_": a fresh session, not the real one")
		Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), before + 1, "case "_n_": exactly one row is created")
		Do ..AdoptRef(fresh)
		Set newReference = $Get(response.Cookies(1, "v"))
		Do $$$AssertTrue((newReference ? 22(1AN,1"-",1"_")) && (newReference '= cookie) && (newReference '= reference), "case "_n_": a new cookie with a new value")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(ref).CspSessionId, "ZzTamperOrig", "case "_n_": the real row is not touched")
	}
	Do $$$AssertTrue(n >= 15, "at least fifteen distinct values were tried: "_n)
	Do $$$AssertEquals($ListLength(..LinesSince(log, mark)), 0, "none wrote a line of OcuTalon.Web.SessionEvents to the console log")
	Do $$$AssertStatusOK(..SignIn(reference, "ZzTamperBack", , , .back, .response), "the real reference signs in")
	Do $$$AssertEquals($Get(back.Data(sessionKey)), ref, "and resumes its row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(ref).CspSessionId, "ZzTamperBack", "which records the new CSP session")
	Do $$$AssertEquals($Order(response.Cookies("")), "", "with no cookie")
}

/// (QA) A local (flag off) sign-in never reads the resume cookie (matrix row 9, AC 4): with a cookie that opens a visitor row of the
/// same user, it still attaches the user's one durable session (the first row of the user), records nothing on the visitor's row, sets
/// no cookie and writes no counter row, also at the proxy.
Method TestFlagOffIgnoresTheCookie()
{
	Set sessionKey = ##class(OcuTalon.Data.Ownership).#SESSIONKEY
	Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Do ..SignIn("", "ZzOffCookieD", , , .durable, .response)
	Set durableRef = $Get(durable.Data(sessionKey))
	Do $$$AssertTrue(durableRef '= "", "the flag-off sign-in attaches the user's durable session")
	If durableRef = "" Quit
	If before = 0 Do ..AdoptRef(durableRef)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do ..SignIn("", "ZzOffCookieV", , , .visitor, .response)
	Set visitorRef = $Get(visitor.Data(sessionKey))
	Set reference = $Get(response.Cookies(1, "v"))
	Do $$$AssertTrue((visitorRef '= "") && (visitorRef '= durableRef) && (reference '= ""), "the flag-on sign-in makes a visitor row of the same user with a cookie")
	If (visitorRef = "") || (reference = "") Quit
	Do ..AdoptRef(visitorRef)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "192.0.2.10")
	Set address = ..Address("offcookie")
	Set rows = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Set counters = ..CounterTotal()
	Do $$$AssertStatusOK(..SignIn(reference, "ZzOffCookieOff", "192.0.2.10", address, .local, .response), "the flag-off sign-in with the visitor's cookie answers OK")
	Do $$$AssertEquals($Get(local.Data(sessionKey)), durableRef, "it attaches the user's durable session, not the visitor's row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(visitorRef).CspSessionId, "ZzOffCookieV", "the visitor's row is not touched")
	Do $$$AssertEquals($Order(response.Cookies("")), "", "no cookie is set")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), rows, "no row is created")
	Do $$$AssertEquals(..CounterTotal(), counters, "no counter row is written")
	Do $$$AssertEquals($Data(local.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), 0, "and no refusal is recorded")
}

/// (QA) ClientAddress's edges (matrix row 12, AC 5): behind the proxy, tabs and runs of spaces around the right-most
/// entry are stripped, IPv6 entries and long lists give the right-most entry whole, a header of commas or white space gives the proxy's
/// own address; a request that is not the proxy's is exempt however long its list is.
Method TestClientAddressEdges()
{
	Set class = "OcuTalon.Web.SessionEvents"
	Set proxy = "192.0.2.10"
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", proxy, "a,"_$Char(9)_"b"_$Char(9), proxy, .proxied), "b", "a tab-padded entry gives b")
	Do $$$AssertEquals(proxied, 1, "proxied")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", proxy, "a ,   b", proxy, .proxied), "b", "a run of spaces before the entry is stripped")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", proxy, "2001:db8::1, 2001:db8::2", proxy, .proxied), "2001:db8::2", "an IPv6 entry is kept whole")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", proxy, "a, b, c, d, e", proxy, .proxied), "e", "the last of five entries")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", proxy, "203.0.113.9, 198.51.100.4", proxy, .proxied), "198.51.100.4", "an address the client put first is not the one counted")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", proxy, ",", proxy, .proxied), proxy, "a header of one comma gives the proxy's own address")
	Do $$$AssertEquals(proxied, 1, "still proxied")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", proxy, "   ", proxy, .proxied), proxy, "a header of spaces gives the proxy's own address")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", "203.0.113.5", "a, b, c, d, e", proxy, .proxied), "", "not from the proxy: a long list is ignored")
	Do $$$AssertEquals(proxied, 0, "not proxied")
	Do $$$AssertEquals($ClassMethod(class, "ClientAddress", proxy_" ", "a, b", proxy, .proxied), "", "a remote address that only starts with the proxy's is not the proxy")
	Do $$$AssertEquals(proxied, 0, "not proxied")
}

/// The number of nodes of every global of the given databases (names, comma-separated) that hold the value in a subscript or in their data:
/// the unit's scan for the resume reference (matrix row 6) and for the raw and encoded references (row 13). It is the key proof's walk
/// (Eval.KeyProof.GlobalHits), which also reads the value inside an element of a $List (8-bit, 16-bit or nested); no stream decode is
/// needed, because no message body holds a global stream (Eval.KeyProof.TestNoMessageBodyHoldsAGlobalStream). It prints and keeps nothing,
/// and answers -1 for an empty value, an empty list of databases (which the key proof's walk would read as every database) or a database
/// that does not exist, so that an empty search never reads as a clean one.
ClassMethod ReferenceHits(value As %String, databases As %String = "OCUTALON_DATA,OCUTALON_PRIVATE,OCUTALON_PUBLIC") As %Integer
{
	If $ZStrip(databases, "<>W") = "" Quit -1
	Quit ##class(OcuTalon.Test.Eval.KeyProof).GlobalHits(value, databases)
}

/// The number of messages of the Interoperability namespace (every one when it is empty) after the header id whose header or body holds the
/// value: the key proof's trace search (Eval.KeyProof.TraceHits), and for a message that it cannot export as XML (a body with a serial
/// property that is not XML-enabled) a second reader that opens the header and the body and reads the body without XML (the abstract tree
/// of %ZEN.Auxiliary.altJSONProvider). A message that neither reader can read, a body with a character stream property (the tree provider
/// gives up on it) and a namespace that cannot be visited all give -1, and so does an empty value: no message is skipped. The second reader reads what the tree projects: the
/// public properties whose names hold no "%"; it leaves out private, %-named and multidimensional properties and reads a binary stream
/// property and a $List value as empty (the bodies that reach it today, Watch.Msg.FailureBatch and its Failure parts, hold none of those).
/// places and stats are the key proof's, with stats.unreadable left holding what neither reader could read and stats.fallback naming the
/// messages that the second reader covered. When the second reader runs, the count is of the places the key proof recorded (at most its
/// limit) plus the hits of the second reader: it is exact as zero or not zero.
ClassMethod MessageHits(value As %String, after As %Integer = 0, namespace As %String = "", Output places As %DynamicArray, Output stats As %DynamicObject) As %Integer
{
	Set hits = ##class(OcuTalon.Test.Eval.KeyProof).TraceHits(value, after, .places, .stats, namespace)
	If (hits '= -1) || (value = "") || 'stats.unreadable.%Size() Quit hits
	Set listed = stats.unreadable
	Set stats.unreadable = [], stats.fallback = []
	Set hits = places.%Size()
	For i = 0:1:listed.%Size() - 1 {
		Set entry = listed.%Get(i)
		Set space = $Piece(entry, ":", 1), id = $Piece(entry, ":", 2, 99)
		If (space = "") || (id '? 1.N) || (entry [ " (") {
			Do stats.unreadable.%Push(entry)
			Continue
		}
		Try {
			If ..MessageHolds(space, id, value) {
				Set hits = hits + 1
				If places.%Size() < ##class(OcuTalon.Test.Eval.KeyProof).#MAXPLACES Do places.%Push(entry)
			}
			Do stats.fallback.%Push(entry)
		} Catch exception {
			Do stats.unreadable.%Push(entry_" ("_$Extract($SYSTEM.Status.GetErrorText(exception.AsStatus()), 1, 120)_")")
		}
	}
	If stats.unreadable.%Size() Quit -1
	Quit hits
}

/// 1 when the header of the message or its body holds the value, 0 when not; it throws when either cannot be read. The header is read as XML
/// and the body as a tree of its properties (the second reader of MessageHits, with the limits that MessageHits names): a body whose tree
/// cannot be built (one with a character stream property) throws.
ClassMethod MessageHolds(namespace As %String, headerId As %Integer, value As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = namespace
	Set header = ##class(Ens.MessageHeader).%OpenId(headerId, , .sc)
	If '$IsObject(header) Throw ##class(%Exception.StatusException).CreateFromStatus($Select($SYSTEM.Status.IsError(sc): sc, 1: $SYSTEM.Status.Error(5001, "the header could not be opened")))
	Set stream = ##class(%Stream.TmpCharacter).%New()
	Set sc = header.XMLExportToStream(.stream)
	If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Set found = ..StreamHolds(stream, value)
	If 'found && (header.MessageBodyId '= "") {
		Set body = $ClassMethod(header.MessageBodyClassName, "%OpenId", header.MessageBodyId, , .sc)
		If '$IsObject(body) Throw ##class(%Exception.StatusException).CreateFromStatus($Select($SYSTEM.Status.IsError(sc): sc, 1: $SYSTEM.Status.Error(5001, "the body could not be opened")))
		Set tree = ##class(%ZEN.Auxiliary.altJSONProvider).%ObjectToAET(body)
		If '$IsObject(tree) Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "the body could not be read as a tree"))
		Set found = (tree.%ToJSON() [ value)
	}
	Quit found
}

/// 1 when the stream holds the value, reading it in chunks that overlap by the value's length less one.
ClassMethod StreamHolds(stream As %Stream.Object, value As %String) As %Boolean [ Private ]
{
	Do stream.Rewind()
	Set tail = "", keep = $Length(value) - 1
	While 'stream.AtEnd {
		Set size = 32000
		Set chunk = tail_stream.Read(.size)
		If chunk [ value Quit
		Set tail = $Select(keep > 0: $Extract(chunk, $Select($Length(chunk) > keep: $Length(chunk) - keep + 1, 1: 1), *), 1: "")
	}
	Quit $Get(chunk) [ value
}

/// ReferenceHits reads a value that only sits inside a 16-bit element of a $List value, as the key proof's walk does (DW-474, DW-450):
/// the node is in the default globals database of the namespace (^OcuTalonTest has no mapping), an empty value gives -1 and so do a database
/// that does not exist and an empty list of databases. The node is killed after the test.
Method TestReferenceHitsReadsLists()
{
	Set value = "referencehits-"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set number = $Job_$Random(1000000000)
	Kill ^OcuTalonTest("ReferenceHits", number)
	Try {
		Set ^OcuTalonTest("ReferenceHits", number) = $ListBuild("zz", $Char(8364)_value)
		Do $$$AssertTrue(##class(OcuTalon.Test.Web.SessionEvents).ReferenceHits(value, "OCUTALON_DATA") >= 1, "a value held only inside a 16-bit $List element is found")
		Do $$$AssertEquals(##class(OcuTalon.Test.Web.SessionEvents).ReferenceHits(value_"-nobody", "OCUTALON_DATA"), 0, "a value nobody holds gives 0")
		Do $$$AssertEquals(##class(OcuTalon.Test.Web.SessionEvents).ReferenceHits("", "OCUTALON_DATA"), -1, "an empty value gives -1")
		Do $$$AssertEquals(##class(OcuTalon.Test.Web.SessionEvents).ReferenceHits(value, "ZZNONE"), -1, "a database that does not exist gives -1")
		Do $$$AssertEquals(##class(OcuTalon.Test.Web.SessionEvents).ReferenceHits(value, ""), -1, "an empty list of databases gives -1, and not a scan of every database")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the scan runs without an exception")
	}
	Kill ^OcuTalonTest("ReferenceHits", number)
}

/// MessageHits finds a value held by a body that cannot be exported as XML (a serial property that is not XML-enabled), and one held by the
/// header of such a message, through its second reader, and counts them with the messages that the key proof's search reads: the key
/// proof's own search gives -1 for the same messages (so the case is not vacuous), a value nobody holds gives 0, an empty value gives -1 and
/// a mark after the messages finds none. The lists are checked for the test's own messages only, since the production may write others.
Method TestMessageHitsReadsWhatXmlCannot()
{
	Set value = "messagehits-"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set bodyId = "", otherId = "", headerId = "", inHeaderId = "", plainId = ""
	Try {
		Set mark = +$Order(^Ens.MessageHeaderD(""), -1)
		For which = 1, 2 {
			Set body = ##class(OcuTalon.Test.Web.NoXmlBody).%New()
			Set body.Label = "zz"
			Set part = ##class(OcuTalon.Test.Web.NoXmlPart).%New()
			Set part.Text = $Select(which = 1: "inside "_value, 1: "inside zz")
			Do body.Parts.Insert(part)
			Do $$$AssertStatusOK(body.%Save(), "the body is saved")
			If which = 1 { Set bodyId = body.%Id() } Else { Set otherId = body.%Id() }
		}
		Do $$$AssertTrue(..SaveHeader("OcuTalon.Test.Web.NoXmlBody", bodyId, "ZzMessageHits", .headerId), "the header of the body that holds the value is saved")
		Do $$$AssertTrue(..SaveHeader("OcuTalon.Test.Web.NoXmlBody", otherId, "ZzMessageHits-"_value, .inHeaderId), "the header that holds the value over a body that does not is saved")
		Do $$$AssertTrue(..SaveHeader("", "", "ZzMessageHits-"_value, .plainId), "the plain header is saved")
		Set named = $Namespace_":"_headerId, inHeader = $Namespace_":"_inHeaderId
		Do $$$AssertTrue(##class(OcuTalon.Test.Eval.KeyProof).TraceHits(value, mark, , .keyStats, $Namespace) = -1, "the key proof's search cannot read the bodies")
		Do $$$AssertTrue(..Names(keyStats.unreadable, named) && ..Names(keyStats.unreadable, inHeader), "and names both headers")
		Set hits = ..MessageHits(value, mark, $Namespace, .places, .stats)
		Do $$$AssertEquals(hits, 3, "the body that XML cannot export, the header of such a message and the plain header that hold the value are all found")
		Do $$$AssertEquals(stats.unreadable.%Size(), 0, "nothing is left unreadable")
		Do $$$AssertTrue(..Names(stats.fallback, named) && ..Names(stats.fallback, inHeader), "the second reader covered both messages")
		Do $$$AssertTrue(..Names(places, named) && ..Names(places, inHeader), "and both are among the places")
		Do $$$AssertEquals(..MessageHits(value_"-nobody", mark, $Namespace), 0, "a value nobody holds gives 0")
		Do $$$AssertEquals(..MessageHits(value, plainId, $Namespace), 0, "a message at or before the mark is not scanned")
		Do $$$AssertEquals(..MessageHits("", mark, $Namespace), -1, "an empty value gives -1")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the search runs without an exception")
	}
	For id = headerId, inHeaderId, plainId {
		If id '= "" Do ##class(Ens.MessageHeader).%DeleteId(id)
	}
	For id = bodyId, otherId {
		If id '= "" Do ##class(OcuTalon.Test.Web.NoXmlBody).%DeleteId(id)
	}
}

/// A message that neither reader can read (its body does not exist) makes MessageHits give -1, even when the other messages hold the value,
/// and names the message in stats.unreadable, and not the readable header that holds the value. The list is checked for the test's own
/// messages only, since the production may write others.
Method TestMessageHitsUnreadableByBoth()
{
	Set value = "messagehits-"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set headerId = "", plainId = ""
	Try {
		Set mark = +$Order(^Ens.MessageHeaderD(""), -1)
		Do $$$AssertTrue(..SaveHeader("OcuTalon.Test.Web.NoXmlBody", "zz-no-such-body", "ZzMessageHits", .headerId), "the header of the missing body is saved")
		Do $$$AssertTrue(..SaveHeader("", "", "ZzMessageHits-"_value, .plainId), "the plain header is saved")
		Set hits = ..MessageHits(value, mark, $Namespace, , .stats)
		Do $$$AssertEquals(hits, -1, "a body that cannot be read by either reader gives -1")
		Do $$$AssertTrue(..Names(stats.unreadable, $Namespace_":"_headerId), "and its header is named")
		Do $$$AssertTrue('..Names(stats.unreadable, $Namespace_":"_plainId), "and the readable header is not")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the search runs without an exception")
	}
	If headerId '= "" Do ##class(Ens.MessageHeader).%DeleteId(headerId)
	If plainId '= "" Do ##class(Ens.MessageHeader).%DeleteId(plainId)
}

/// 1 when the list of a search's places or stats names the message <namespace>:<header id>, alone or with its reason in brackets (the key
/// proof's own helper, ListHas, is private to it and Lane A's: DW-888).
ClassMethod Names(list As %DynamicArray, message As %String) As %Boolean [ Private ]
{
	Set found = 0
	If '$IsObject(list) Quit found
	For i = 0:1:list.%Size() - 1 {
		Set entry = list.%Get(i)
		If (entry = message) || ($Extract(entry, 1, $Length(message) + 2) = (message_" (")) Set found = 1
	}
	Quit found
}

/// Saves a message header for the message tests of MessageHits and answers its id in headerId.
ClassMethod SaveHeader(bodyClass As %String, bodyId As %String, source As %String, Output headerId As %String) As %Boolean [ Private ]
{
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.MessageBodyClassName = bodyClass
	Set header.MessageBodyId = bodyId
	Set header.SourceConfigName = source
	Set header.TargetConfigName = "ZzMessageHits"
	Set header.Type = 1
	Set sc = header.%Save()
	Set headerId = $Select($SYSTEM.Status.IsOK(sc): header.%Id(), 1: "")
	Quit $SYSTEM.Status.IsOK(sc)
}

/// The online demo's sign-in of a user without the OcuTalon user role (matrix row 9's no-role contract): behind the proxy, with a visitor's
/// cookie and a forwarded address, it answers OK and attaches, creates, sets, counts and records nothing, writes no console line and
/// leaves the visitor's row untouched.
Method TestNoRoleOnTheOnlineDemo()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "192.0.2.10")
	Set sessionKey = ##class(OcuTalon.Data.Ownership).#SESSIONKEY
	Do ..SignIn("", "ZzNoRoleVisitor", , , .visitor, .response)
	Set visitorRef = $Get(visitor.Data(sessionKey))
	Set reference = $Get(response.Cookies(1, "v"))
	Do $$$AssertTrue((visitorRef '= "") && (reference '= ""), "a visitor's row and cookie exist")
	If (visitorRef = "") || (reference = "") Quit
	Do ..AdoptRef(visitorRef)
	Set address = ..Address("norole")
	Set rows = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Set log = $System.Util.ManagerDirectory()_"messages.log"
	Set mark = ##class(%File).GetFileSize(log)
	Do $$$AssertStatusOK(..SignIn(reference, "ZzNoRole", "192.0.2.10", address, .session, .response, 0), "the no-role sign-in answers OK")
	Do $$$AssertEquals($Get(session.Data(sessionKey)), "", "it attaches nothing")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), rows, "it creates no row")
	Do $$$AssertEquals($Order(response.Cookies("")), "", "it sets no cookie")
	Do $$$AssertEquals(..CounterRows(address), 0, "it writes no counter row")
	Do $$$AssertEquals($Data(session.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), 0, "it records no refusal")
	Do $$$AssertEquals($ListLength(..LinesSince(log, mark)), 0, "it writes no console line")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(visitorRef).CspSessionId, "ZzNoRoleVisitor", "and the visitor's row is not touched")
}

/// (QA) No key can be made (Story 29.5, matrix row 8, integration): while another job holds the address key's lock and no valid key
/// exists, a proxied creation is refused as the counter's "busy" error (logged by code only) and creates no session row, no Ref, no
/// cookie, no counter row and no key; once the lock is free, the next creation is let in and counted. The test sets the limit to 5,
/// waits for the holder's signal before it signs in, deletes its counter row while the key it was counted under is in place, and
/// puts the key node back whatever happens.
Method TestNoKeyRefusesTheCreation()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do ##class(OcuTalon.Data.Public.Settings).Set("proxyAddress", "192.0.2.10")
	Do ..SetLimit(5)
	Set node = ##class(OcuTalon.Data.AddressCounter).#KEYGLOBAL
	Set savedNode = $Data(@node)
	Set savedValue = $Get(@node)
	Set address = ..Address("nokey")
	Set flag = $Name(^OcuTalonTest("SessionEvents", "keyholder"))
	Kill @flag
	Try {
		Kill @node
		Job ..KeyHolder(node, flag)
		Set deadline = $ZHorolog + 20
		While ($Get(@flag) = "") && ($ZHorolog < deadline) {
			Hang 0.05
		}
		Do $$$AssertEquals($Get(@flag), "held", "another job holds the key lock")
		Set rows = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
		Set total = ..CounterTotal()
		Set log = $System.Util.ManagerDirectory()_"messages.log"
		Do ##class(%SYS.System).WriteToConsoleLog("OcuTalon.Test.Web.SessionEvents: a line that the attach's is not a repeat of", 0, 0)
		Set mark = ##class(%File).GetFileSize(log)
		Do $$$AssertStatusOK(..SignIn("", "ZzNoKey", "192.0.2.10", address, .refused, .response), "the creation answers OK")
		Do $$$AssertEquals($Get(refused.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)), "", "it attaches nothing")
		Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), rows, "it creates no row")
		Do $$$AssertEquals($Order(response.Cookies("")), "", "it sets no cookie")
		Do $$$AssertEquals(..CounterTotal(), total, "it writes no counter row")
		Do $$$AssertEquals($Data(@node), 0, "it makes no key")
		Do $$$AssertEquals($Data(refused.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY)), 0, "it records no refusal marker")
		Set lines = ..LinesSince(log, mark)
		Do $$$AssertEquals($ListLength(lines), 1, "it logs one line")
		If $ListLength(lines) = 1 Do $$$AssertEquals($Piece($List(lines, 1), "OcuTalon.Web.SessionEvents: ", 2), "the session could not be attached, error 5001", "the line holds the sentence and the error code only")
		Set @flag = "release"
		Set deadline = $ZHorolog + 20
		While ($Get(@flag) '= "done") && ($ZHorolog < deadline) {
			Hang 0.05
		}
		Do $$$AssertEquals($Get(@flag), "done", "the holder released the key lock")
		Do $$$AssertStatusOK(..SignIn("", "ZzNoKeyAfter", "192.0.2.10", address, .after, .response), "once the lock is free the creation answers OK")
		Do ..AdoptRef($Get(after.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)))
		Do $$$AssertTrue($Get(after.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)) '= "", "and is let in")
		Do $$$AssertEquals(..CounterRows(address), 1, "and counted")
		Do ..DropCounter(address)
		Do $$$AssertEquals(..CounterTotal(), total, "and its counter row is deleted under the key it was counted with")
	} Catch exception {
		Do $$$AssertFailure("the test raised an error: "_exception.Name)
	}
	If ($Get(@flag) '= "") && ($Get(@flag) '= "done") {
		Set @flag = "release"
		Set deadline = $ZHorolog + 20
		While ($Get(@flag) '= "done") && ($ZHorolog < deadline) {
			Hang 0.05
		}
	}
	Kill @flag
	Do ..DropCounter(address)
	If savedNode {
		Set @node = savedValue
	} Else {
		Kill @node
	}
}

/// The job of TestNoKeyRefusesTheCreation: holds the key lock, signals "held" (or "failed"), keeps it until the flag says "release" (at
/// most 30 seconds), releases it and signals "done".
ClassMethod KeyHolder(node As %String, flag As %String)
{
	Lock +@node:10
	Set held = $Test
	Set @flag = $Select(held: "held", 1: "failed")
	Set deadline = $ZHorolog + 30
	While ($Get(@flag) '= "release") && ($ZHorolog < deadline) {
		Hang 0.05
	}
	If held Lock -@node
	Set @flag = "done"
}

/// The OnLogin work for a sign-in in process: a CSP session with the id, a stand-in request with the cookie, the remote address,
/// the forwarded list and a response; the CSP session and the response come back in session and response. hasRole is AttachFor's
/// argument (the user holds the OcuTalon user role by default). The status is AttachFor's.
Method SignIn(cookie As %String, sessionId As %String, remote As %String = "", forwarded As %String = "", Output session, Output response, hasRole As %Boolean = 1, admin As %String = "") As %Status [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/")
	If cookie '= "" Set %request.Cookies("OcuTalonResume", 1) = cookie
	If remote '= "" Set %request.CgiEnvs("REMOTE_ADDR") = remote
	If forwarded '= "" Set %request.CgiEnvs("HTTP_X_FORWARDED_FOR") = forwarded
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New(sessionId, 0)
	Set sc = ##class(OcuTalon.Web.SessionEvents).AttachFor(hasRole, admin)
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
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?", ##class(OcuTalon.Data.AddressCounter).AddressHash(address))
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
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MIN(CreatedAt) FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?", ##class(OcuTalon.Data.AddressCounter).AddressHash(address))
	Do result.%Next()
	Quit result.%GetData(1)
}

/// Deletes the counter rows of an address.
ClassMethod DropCounter(address As %String) [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?", ##class(OcuTalon.Data.AddressCounter).AddressHash(address))
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

/// OnLogout (Story 31.1, DW-457; U-209): with a CSP session that names a session row and the online demo off it answers OK and
/// raises the row's sign-out mark by exactly 1, and every stored field of the row stays as it was (the fields are derived from
/// the class's stored properties, so a field added later is compared too; the Epoch is also asserted on its own). With the
/// online demo on it answers OK and sets no mark node, for a session that never signed out as for one that did; with no ref in
/// the CSP session it answers OK and the mark is unchanged; a broken CSP session still answers OK. The online-demo setting is
/// put back and every mark node the test made is killed, also after a failure.
Method TestSignOutMark()
{
	New %session
	Set markGlobal = ##class(OcuTalon.Data.Session).#MARKGLOBAL
	Set ref = ..MarkedFixture()
	Set other = ..MarkedFixture()
	Set fresh = ..MarkedFixture()
	Set fields = ..StoredFields()
	For name = "Epoch", "Ref", "CspSessionId", "ResumeHash", "AllowanceTimes", "ThreadSessionId", "DailyCapDay" {
		Do $$$AssertTrue($ListFind(fields, name) > 0, "the stored fields compared include "_name)
	}
	Set before = ..RowText(ref)
	Set epochBefore = ##class(OcuTalon.Data.Session).RefIndexOpen(ref).Epoch
	Set otherBefore = ##class(OcuTalon.Data.Session).SignOuts(other)
	Set freshBefore = ..RowText(fresh)
	Set %session = ##class(%CSP.Session).%New("ZzSignOutMark", 0)
	Set %session.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY) = ref
	Set resumeHash = "|ResumeHash="_##class(OcuTalon.Data.Session).Hash(ref)
	Set cspSessionId = "|CspSessionId=zz"_ref
	Try {
		Do $$$AssertNotEquals(epochBefore, "", "the session has an Epoch to compare")
		Do $$$AssertTrue(before [ resumeHash, "the row text holds the resume hash")
		Do $$$AssertTrue(before [ cspSessionId, "and the CSP session id")
		Do $$$AssertTrue(before [ "|AllowanceTimes=2001-01-01T00:00:01Z~2001-01-01T00:00:02Z", "and the allowance list by its elements")
		Do $$$AssertEquals($Data(@markGlobal@(fresh)), 0, "a session that never signed out has no mark node to begin with")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).SignOuts(ref), 0, "the session has no mark to begin with")
		Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).OnLogout(), "OnLogout answers OK")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).SignOuts(ref), 1, "and raises the mark by 1")
		Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).OnLogout(), "a second sign-out answers OK")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).SignOuts(ref), 2, "and raises it by 1 again")
		Do $$$AssertEquals($Get(@markGlobal@(ref)), 2, "and the mark is the node that MARKGLOBAL names")
		Do $$$AssertEquals(..RowText(ref), before, "the row's fields are unchanged")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(ref).Epoch, epochBefore, "and the Epoch is unchanged")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).SignOuts(other), otherBefore, "another session's mark is unchanged")

		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
		Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).OnLogout(), "on the online demo it answers OK")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).SignOuts(ref), 2, "and the marked session's count is unchanged")
		Set %session.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY) = fresh
		Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).OnLogout(), "for a session that never signed out it answers OK")
		Do $$$AssertEquals($Data(@markGlobal@(fresh)), 0, "and sets no mark node")
		Do $$$AssertEquals(..RowText(fresh), freshBefore, "and its row's fields are unchanged")
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")

		Kill %session.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY)
		Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).OnLogout(), "with no ref in the CSP session it answers OK")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).SignOuts(ref), 2, "and changes no mark")

		Set %session = ""
		Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).OnLogout(), "with no CSP session it answers OK")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).SignOuts(ref), 2, "and changes no mark")
	} Catch exception {
		Do $$$AssertEquals(exception.DisplayString(), "", "the checks ran without an error")
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	For node = ref, other, fresh {
		Kill @markGlobal@(node)
	}
}

/// OnLogout wakes the session's WebSocket (Story 31.1, U-174: "so that its socket wakes at once"): after a sign-out a wait on the
/// session's wake resource returns signalled, and it does not when the online demo is on, when the CSP session names no ref, or
/// when another session signs out. The resource is created and cleared here and deleted after, also after a failure.
Method TestSignOutWakesTheSocket()
{
	New %session
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set other = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set name = ##class(OcuTalon.Live.Publish).WakeName(ref)
	Set key = ##class(OcuTalon.Data.Ownership).#SESSIONKEY
	Set %session = ##class(%CSP.Session).%New("ZzSignOutWake", 0)
	Try {
		Do $SYSTEM.Event.Create(name)
		Do $SYSTEM.Event.Clear(name)
		Do $$$AssertEquals($SYSTEM.Event.Wait(name, 0.1), 0, "nothing is queued to begin with")

		Set %session.Data(key) = other
		Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).OnLogout(), "another session signs out")
		Do $$$AssertEquals($SYSTEM.Event.Wait(name, 0.1), 0, "and does not wake this session's socket")

		Set %session.Data(key) = ref
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
		Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).OnLogout(), "on the online demo it answers OK")
		Do $$$AssertEquals($SYSTEM.Event.Wait(name, 0.1), 0, "and wakes nothing")
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")

		Kill %session.Data(key)
		Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).OnLogout(), "with no ref it answers OK")
		Do $$$AssertEquals($SYSTEM.Event.Wait(name, 0.1), 0, "and wakes nothing")

		Set %session.Data(key) = ref
		Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).OnLogout(), "the session signs out")
		Do $$$AssertEquals($SYSTEM.Event.Wait(name, 0.1), 1, "and its socket's wake resource is signalled")
	} Catch exception {
		Do $$$AssertEquals(exception.DisplayString(), "", "the checks ran without an error")
	}
	Do $SYSTEM.Event.Delete(name)
	Kill ^OcuTalonP.SessionM(ref), ^OcuTalonP.SessionM(other)
}

/// A session row of the running user with every stored field set to a value of its own (including the resume hash, the CSP
/// session id and the allowance list), so that a comparison of the fields can fail on each; its Ref. The days and times are in
/// 2001, a date that no writer of these fields stores (they store today's), so a write of today's values changes the row.
ClassMethod MarkedFixture() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set row.ThreadSessionId = 7
	Set row.ThreadDay = "2001-01-01"
	Set row.ResumeHash = ##class(OcuTalon.Data.Session).Hash(ref)
	Set row.CspSessionId = "zz"_ref
	Set row.AllowanceTimes = $ListBuild("2001-01-01T00:00:01Z", "2001-01-01T00:00:02Z")
	Set row.AllowanceUntil = "2001-01-01T01:00:00Z"
	Set row.DailyCapDay = "2001-01-01"
	Set sc = row.%Save()
	If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Quit ref
}

/// The names of the stored properties of OcuTalon.Data.Session as a $List: not transient, not calculated, and not a %-name.
ClassMethod StoredFields() As %List [ Private ]
{
	Set names = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledProperty WHERE parent = ? AND Transient = 0 AND Calculated = 0 AND SUBSTRING(Name, 1, 1) <> '%' ORDER BY Name", "OcuTalon.Data.Session")
	While result.%Next() {
		Set names = names_$ListBuild(result.%Get("Name"))
	}
	Quit names
}

/// The stored fields of a session row as one text, to see that nothing changed; a list property is compared by its elements.
ClassMethod RowText(ref As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set fields = ..StoredFields()
	Set text = ""
	For i = 1:1:$ListLength(fields) {
		Set name = $List(fields, i)
		Set type = ##class(%Dictionary.CompiledProperty).%OpenId("OcuTalon.Data.Session||"_name).Type
		Set value = $Property(row, name)
		If $Piece(type, ".", $Length(type, ".")) = "List", $ListValid(value) Set value = $ListToString(value, "~")
		Set text = text_"|"_name_"="_value
	}
	Quit text
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
