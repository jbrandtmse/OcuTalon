/// Tests of the public status class (matrix row 19, the slot A part): the body for the public settings that are set
/// and for none, the busy formula, the route and the authorisation, an error's answer, and the source of the class,
/// which may reference only what AD-3 allows. The tests set the public settings that the body reads. OnBeforeAllTests saves them and
/// OnAfterAllTests restores each one, so the slot's settings are as they were. The HTTP half is test-sign-in.sh's.
Class OcuTalon.Test.Web.Status Extends %UnitTest.TestCase
{

/// The settings that the tests change: the readiness key and the fixed keys that the body reads.
Parameter KEYS = "ready,resetAnchor,resetIntervalHours,lastReset,lastResetKind,connectionCap,connectionReserve";

/// saved(key) = the stored value of each setting before the tests, "" when it was unset.
Property Saved As %String [ MultiDimensional ];

Method OnBeforeAllTests() As %Status
{
	Set position = 0
	Set keys = $ListFromString(..#KEYS)
	While $ListNext(keys, position, key) {
		Set ..Saved(key) = ##class(OcuTalon.Data.Public.Settings).Get(key)
	}
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..Restore()
	Quit $SYSTEM.Status.OK()
}

/// With every setting set, the body has exactly five keys with the stored values; ready is a JSON boolean.
Method TestBodyWithSettings()
{
	Do ##class(OcuTalon.Data.Public.Settings).SetReady()
	Do ..SetAll("2026-01-01T00:00:00Z", 24, "2026-10-18T03:00:00Z", "scheduled", 100000, 2)
	Set body = ##class(OcuTalon.Web.Public.Status).Body()
	Do $$$AssertEquals(..Keys(body), "ready,nextReset,busy,lastReset,lastResetKind", "exactly the five keys")
	Do $$$AssertEquals(body.%GetTypeOf("ready"), "boolean", "ready is a boolean")
	Do $$$AssertEquals(body.ready, 1, "ready is true")
	Do $$$AssertEquals(body.nextReset, ##class(OcuTalon.Data.Public.Settings).NextReset(), "nextReset is the next scheduled reset")
	Do $$$AssertTrue(body.nextReset ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "and a Utc time: "_body.nextReset)
	Do $$$AssertEquals(body.%GetTypeOf("busy"), "boolean", "busy is a boolean")
	Do $$$AssertEquals(body.busy, 0, "busy is false while the connections are far below the cap less the reserve")
	Do $$$AssertEquals(body.lastReset, "2026-10-18T03:00:00Z", "lastReset")
	Do $$$AssertEquals(body.lastResetKind, "scheduled", "lastResetKind")

	Do ##class(OcuTalon.Data.Public.Settings).ClearReady()
	Set body = ##class(OcuTalon.Web.Public.Status).Body()
	Do $$$AssertEquals(body.%GetTypeOf("ready"), "boolean", "ready is a boolean when it is not set")
	Do $$$AssertEquals(body.ready, 0, "ready is false when readiness is cleared")

	Do ##class(OcuTalon.Data.Public.Settings).Set("connectionCap", 8)
	Do ##class(OcuTalon.Data.Public.Settings).Set("connectionReserve", 8)
	Set body = ##class(OcuTalon.Web.Public.Status).Body()
	Do $$$AssertEquals(body.busy, 1, "busy is true when the connections reach the cap less the reserve")
}

/// With no setting, every key is still there: ready false, busy false, and null for the times and the kind.
Method TestBodyWithoutSettings()
{
	Do ##class(OcuTalon.Data.Public.Settings).ClearReady()
	Do ..SetAll("", "", "", "", "", "")
	Set body = ##class(OcuTalon.Web.Public.Status).Body()
	Do $$$AssertEquals(..Keys(body), "ready,nextReset,busy,lastReset,lastResetKind", "exactly the five keys")
	Do $$$AssertEquals(body.ready, 0, "ready is false")
	Do $$$AssertEquals(body.busy, 0, "busy is false without a cap")
	For key = "nextReset", "lastReset", "lastResetKind" {
		Do $$$AssertEquals(body.%GetTypeOf(key), "null", key_" is null")
	}
	Do $$$AssertEquals(body.%ToJSON(), "{""ready"":false,""nextReset"":null,""busy"":false,""lastReset"":null,""lastResetKind"":null}", "the JSON")
}

/// Busy is true when the connections reach the cap less the reserve, and false without a valid cap.
Method TestIsBusy()
{
	Set status = "OcuTalon.Web.Public.Status"
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 6, 8, 2), 1, "6 of 8 less 2 is busy")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 5, 8, 2), 0, "5 of 8 less 2 is not")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 7, 8, 2), 1, "7 is busy")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 9, "", 2), 0, "no cap is not busy")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 9, "x", 2), 0, "a cap that isn't a number is not busy")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 9, 0, 2), 0, "a cap of 0 is not busy")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 9, -3, 0), 0, "a negative cap is not busy")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 1, 1, ""), 1, "no reserve counts as 0")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 0, 1, "x"), 0, "a reserve that isn't a number counts as 0")
	Do $$$AssertEquals($ClassMethod(status, "IsBusy", 8, 8, 8), 1, "a reserve as large as the cap is always busy")
}

/// One route, GET /status; no session; JSON; everyone is authorised; Show writes the body with no-store.
Method TestRouteAndAccess()
{
	Set found = ##class(OcuTalon.Test.Web.Api).Routes("OcuTalon.Web.Public.Status")
	Do $$$AssertEquals($ListToString(found, "|"), "GET /status Show", "exactly one route")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Public.Status", "UseSession"), 0, "no session")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Public.Status", "CONTENTTYPE"), "application/json", "JSON")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Public.Status", "HandleCorsRequest"), 0, "no CORS handling")
	Do $$$AssertTrue($ClassMethod("OcuTalon.Web.Public.Status", "%Extends", "%CSP.REST"), "it is a %CSP.REST class")
	Do $ClassMethod("OcuTalon.Web.Public.Status", "AccessCheck", .authorized)
	Do $$$AssertEquals(authorized, 1, "AccessCheck authorises")

	Do ##class(OcuTalon.Data.Public.Settings).ClearReady()
	Do ..SetAll("", "", "", "", "", "")
	New %request, %response
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/public/")
	Set %response = ##class(%CSP.Response).%New()
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Public.Status", "Show")
	Do $$$AssertStatusOK(sc, "Show returns OK")
	Do $$$AssertEquals(%response.GetHeader("Cache-Control"), "no-store", "Cache-Control: no-store")
	Do $$$AssertEquals(written, ##class(OcuTalon.Web.Public.Status).Body().%ToJSON(), "Show writes the body")
}

/// An error is answered with its status line only: its cause is never written to the anonymous caller.
Method TestErrorSendsNoCause()
{
	New %request, %response
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/public/")
	Set %response = ##class(%CSP.Response).%New()
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Public.Status", "ReportHttpStatusCode", "500 Internal Server Error", $SYSTEM.Status.Error(5001, "zz-the-cause"))
	Do $$$AssertStatusOK(sc, "ReportHttpStatusCode returns OK")
	Do $$$AssertEquals(%response.Status, "500 Internal Server Error", "the status line")
	Do $$$AssertEquals(written, "", "and no body, so the cause is not sent")
}

/// The public classes that the Web step's applications dispatch to before sign-in reference only what AD-3 allows
/// the public package: %CSP, dynamic objects, $SYSTEM.License and $SYSTEM.Status, their own package and
/// OcuTalon.Data.Public.Settings.
Method TestReferencesOnlyThePublicAllowList()
{
	For class = "OcuTalon.Web.Public.Status", "OcuTalon.Web.Public.ApiBase" {
		Set sc = ##class(%Compiler.UDL.TextServices).GetTextAsString($Namespace, class, .text)
		Do $$$AssertStatusOK(sc, "the source of "_class)
		Do $$$AssertTrue($Length(text) > 500, class_" has a source")
		Do $$$AssertEquals(..Outside(text), "", class_" references nothing outside the allow-list")
	}
	Set found = ..Outside("Quit ##Class(OcuTalon.Fix.Executor).Run()_$system.Util.DataDirectory()_$classmethod(a, b)_##class(%CSP.REST).X()_$SYSTEM.License.X()")
	Do $$$AssertEquals(found, " OCUTALON.FIX.EXECUTOR $SYSTEM.UTIL $CLASSMETHOD", "the scan finds a class, a $SYSTEM member and a dynamic call outside the allow-list, whatever their case")
}

/// --- helpers ---
/// The classes and $SYSTEM members that a source references and AD-3 does not allow, and any dynamic dispatch, as a
/// list of names in upper case. ObjectScript is case-insensitive, so the scan is too.
ClassMethod Outside(text As %String) As %String [ Private ]
{
	Set outside = ""
	Set upper = $ZConvert(text, "U")
	Set from = 1
	While $Find(upper, "##CLASS(", from) {
		Set start = $Find(upper, "##CLASS(", from)
		Set name = $Piece($Extract(upper, start, start + 100), ")", 1)
		Set from = start
		If (name = "OCUTALON.DATA.PUBLIC.SETTINGS") || ($Extract(name, 1, 5) = "%CSP.") || ($Extract(name, 1, 20) = "OCUTALON.WEB.PUBLIC.") || (name = "%DYNAMICOBJECT") || (name = "%DYNAMICARRAY") Continue
		Set outside = outside_" "_name
	}
	Set from = 1
	While $Find(upper, "$SYSTEM.", from) {
		Set start = $Find(upper, "$SYSTEM.", from)
		Set name = ..Word(upper, start)
		Set from = start
		If (name = "LICENSE") || (name = "STATUS") Continue
		Set outside = outside_" $SYSTEM."_name
	}
	For dispatch = "$CLASSMETHOD(", "$METHOD(" {
		If $Find(upper, dispatch) Set outside = outside_" "_$Extract(dispatch, 1, *-1)
	}
	Quit outside
}

/// Sets the fixed keys that the body reads.
Method SetAll(anchor As %String, interval As %String, lastReset As %String, kind As %String, cap As %String, reserve As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("resetAnchor", anchor), "resetAnchor is set")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("resetIntervalHours", interval), "resetIntervalHours is set")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("lastReset", lastReset), "lastReset is set")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("lastResetKind", kind), "lastResetKind is set")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("connectionCap", cap), "connectionCap is set")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("connectionReserve", reserve), "connectionReserve is set")
}

/// Puts every setting back as OnBeforeAllTests found it.
Method Restore() [ Private ]
{
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		If key = "ready" {
			If ..Saved(key) '= "" {
				Do ##class(OcuTalon.Data.Public.Settings).SetReady()
			} Else {
				Do ##class(OcuTalon.Data.Public.Settings).ClearReady()
			}
		} Else {
			Do ##class(OcuTalon.Data.Public.Settings).Set(key, ..Saved(key))
		}
	}
}

/// The run of letters of text that starts at position start.
ClassMethod Word(text As %String, start As %Integer) As %String [ Private ]
{
	Set word = ""
	For i = start:1:start + 40 {
		Set char = $Extract(text, i)
		If char '? 1A Quit
		Set word = word_char
	}
	Quit word
}

/// The keys of a dynamic object, as a comma list in order.
ClassMethod Keys(object As %DynamicObject) As %String [ Private ]
{
	Set keys = ""
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Quit keys
}

}
