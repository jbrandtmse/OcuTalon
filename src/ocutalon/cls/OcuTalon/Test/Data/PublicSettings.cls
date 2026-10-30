/// Tests of the public-settings accessor and of the Public step's use of it (AD-19).
/// Every key the tests touch is saved in OnBeforeAllTests and restored in OnAfterAllTests, through the accessor.
Class OcuTalon.Test.Data.PublicSettings Extends %UnitTest.TestCase
{

/// The accessor under test.
Parameter ACCESSOR = "OcuTalon.Data.Public.Settings";

/// saved(key) = the value held before the tests; saved("ready") = the readiness.
Property Saved As %String [ MultiDimensional ];

Method OnBeforeAllTests() As %Status
{
	Set keys = $ListFromString($Parameter(..#ACCESSOR, "KEYS"))_$ListBuild("ready")
	Set position = 0
	While $ListNext(keys, position, key) {
		Set ..Saved(key) = $ClassMethod(..#ACCESSOR, "Get", key)
	}
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Set sc = $SYSTEM.Status.OK()
	Set key = ""
	For {
		Set key = $Order(..Saved(key), 1, value)
		Quit:key=""
		If key = "ready" {
			Set one = $Select(value = "": $ClassMethod(..#ACCESSOR, "ClearReady"), 1: $ClassMethod(..#ACCESSOR, "SetReady"))
		} Else {
			Set one = $ClassMethod(..#ACCESSOR, "Set", key, value)
		}
		If $$$ISERR(one) Set sc = $SYSTEM.Status.AppendStatus(sc, one)
	}
	Quit sc
}

/// A fixed key is stored, read back, and removed with "".
Method TestFixedKeysRoundTrip()
{
	Set keys = $ListFromString($Parameter(..#ACCESSOR, "KEYS"))
	Do $$$AssertEquals($Parameter(..#ACCESSOR, "KEYS"), "onlineDemo,demoUser,demoPassword,readonlyUser,readonlyPassword,resetIntervalHours,resetAnchor,lastReset,lastResetKind,proxyAddress,connectionCap,connectionReserve,messageAllowance", "the fixed keys are the contract's thirteen")
	Set position = 0
	While $ListNext(keys, position, key) {
		Do $$$AssertStatusOK($ClassMethod(..#ACCESSOR, "Set", key, "value of "_key), "Set "_key)
		Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", key, .sc), "value of "_key, "Get "_key)
		Do $$$AssertStatusOK(sc, "Get "_key_" status")
		Do $$$AssertStatusOK($ClassMethod(..#ACCESSOR, "Set", key, ""), "remove "_key)
		Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", key), "", key_" is gone")
	}
}

/// Row 11: a key that is not fixed is refused by Set and Get with an error status that names it, Get gives "",
/// and "ready" cannot be written through Set.
Method TestRefusedKeys()
{
	Set accessor = ..#ACCESSOR
	Do $ClassMethod(accessor, "ClearReady")

	Set sc = $ClassMethod(accessor, "Set", "nosuch", "x")
	Do $$$AssertStatusNotOK(sc, "Set of an unknown key is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "nosuch", "the error names the key")
	Do $$$AssertEquals($ClassMethod(accessor, "Get", "nosuch", .read), "", "Get of an unknown key returns """"")
	Do $$$AssertStatusNotOK(read, "Get of an unknown key gives an error status")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(read) [ "nosuch", "the Get error names the key")

	Set sc = $ClassMethod(accessor, "Set", "ready", 1)
	Do $$$AssertStatusNotOK(sc, "Set of ready is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ready", "the error names ready")
	Do $$$AssertEquals($ClassMethod(accessor, "Get", "ready"), "", "readiness was not stored by Set")

	Do $$$AssertStatusNotOK($ClassMethod(accessor, "Set", "onlineDemo,demoUser", "x"), "two names in one key are refused")
	Do $$$AssertStatusNotOK($ClassMethod(accessor, "Set", "", "x"), "an empty key is refused")
	Do $$$AssertStatusNotOK($ClassMethod(accessor, "Set", "OnlineDemo", "x"), "key names are case-sensitive")
}

/// Readiness is cleared and set only by ClearReady and SetReady.
Method TestReadiness()
{
	Set accessor = ..#ACCESSOR
	Do $$$AssertStatusOK($ClassMethod(accessor, "SetReady"), "SetReady")
	Do $$$AssertEquals($ClassMethod(accessor, "Get", "ready", .sc), 1, "ready is 1")
	Do $$$AssertStatusOK(sc, "Get ready status")
	Do $$$AssertStatusOK($ClassMethod(accessor, "ClearReady"), "ClearReady")
	Do $$$AssertEquals($ClassMethod(accessor, "Get", "ready"), "", "ready is cleared")
	Do $$$AssertStatusOK($ClassMethod(accessor, "ClearReady"), "ClearReady again")
}

/// Row 12: the next reset is the first anchor + k * interval hours that is later than now.
Method TestNextReset()
{
	Set accessor = ..#ACCESSOR
	Do $ClassMethod(accessor, "Set", "resetAnchor", "2026-10-18T00:00:00Z")
	Do $ClassMethod(accessor, "Set", "resetIntervalHours", 4)
	Do $$$AssertEquals($ClassMethod(accessor, "NextReset", "2026-10-17T23:00:00Z"), "2026-10-18T00:00:00Z", "before the anchor: the anchor")
	Do $$$AssertEquals($ClassMethod(accessor, "NextReset", "2026-10-18T00:00:00Z"), "2026-10-18T04:00:00Z", "at the anchor: the next slot")
	Do $$$AssertEquals($ClassMethod(accessor, "NextReset", "2026-10-18T05:30:00Z"), "2026-10-18T08:00:00Z", "inside a slot")
	Do $$$AssertEquals($ClassMethod(accessor, "NextReset", "2026-10-19T23:59:59Z"), "2026-10-20T00:00:00Z", "across a day")
	Do $$$AssertEquals($ClassMethod(accessor, "NextReset", "2026-10-18T03:59:59Z"), "2026-10-18T04:00:00Z", "one second before a slot")
	Do $$$AssertEquals($ClassMethod(accessor, "NextReset", "2026-10-18T04:00:00Z"), "2026-10-18T08:00:00Z", "on a slot")

	Set now = $ClassMethod(accessor, "NextReset")
	Do $$$AssertTrue(now ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "without now, the answer is a UTC time: "_now)
	Do $$$AssertTrue(now ] $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T")_"Z", "without now, the answer is in the future")

	Do $ClassMethod(accessor, "Set", "resetIntervalHours", 0.5)
	Do $$$AssertEquals($ClassMethod(accessor, "NextReset", "2026-10-18T00:10:00Z"), "2026-10-18T00:30:00Z", "a fractional interval")

	For interval = "", 0, -4, "abc", "4h" {
		Do $ClassMethod(accessor, "Set", "resetIntervalHours", interval)
		Do $$$AssertEquals($ClassMethod(accessor, "NextReset", "2026-10-18T05:30:00Z"), "", "interval '"_interval_"' gives no reset")
	}

	Do $ClassMethod(accessor, "Set", "resetIntervalHours", 4)
	Do $ClassMethod(accessor, "Set", "resetAnchor", "")
	Do $$$AssertEquals($ClassMethod(accessor, "NextReset", "2026-10-18T05:30:00Z"), "", "no anchor gives no reset")
	Do $ClassMethod(accessor, "Set", "resetAnchor", "not a time")
	Do $$$AssertEquals($ClassMethod(accessor, "NextReset", "2026-10-18T05:30:00Z"), "", "an unreadable anchor gives no reset")
	Do $ClassMethod(accessor, "Set", "resetAnchor", "2026-10-18T00:00:00Z")
	Do $$$AssertEquals($ClassMethod(accessor, "NextReset", "not a time"), "", "an unreadable now gives no reset")
}

/// Row 1 (DW-235): the one UTC helper. ToSeconds accepts exactly YYYY-MM-DDThh:mm:ssZ with a real date and time and gives "" for
/// anything else without throwing; FromSeconds round-trips it; Shift moves a time and gives "" for an unreadable one. The two old
/// callers, AddressCounter.Shift and SessionEvents.CookieExpiry, hold no $ZDateTimeH of their own.
Method TestUtcHelper()
{
	Set accessor = ..#ACCESSOR
	For time = "2026-10-18T00:00:00Z", "2026-12-31T23:59:59Z", "2028-02-29T12:30:45Z" {
		Set seconds = $ClassMethod(accessor, "ToSeconds", time)
		Do $$$AssertTrue(seconds ? 1.N, "ToSeconds reads "_time)
		Do $$$AssertEquals($ClassMethod(accessor, "FromSeconds", seconds), time, "the round trip of "_time)
	}
	Do $$$AssertEquals($ClassMethod(accessor, "ToSeconds", "2026-10-18T00:00:01Z") - $ClassMethod(accessor, "ToSeconds", "2026-10-18T00:00:00Z"), 1, "one second apart")
	For bad = "", "2026-10-18T00:00:00", "2026-10-18T00:00:00.5Z", "2026-02-30T00:00:00Z", "2026-10-18T25:00:00Z", "2026-10-18 00:00:00Z", "x", "2026-10-18T00:00:00Zx" {
		Set error = "", result = "x"
		Try {
			Set result = $ClassMethod(accessor, "ToSeconds", bad)
		} Catch exception {
			Set error = exception.DisplayString()
		}
		Do $$$AssertEquals(error, "", "ToSeconds does not throw for '"_bad_"'")
		Do $$$AssertEquals(result, "", "ToSeconds gives nothing for '"_bad_"'")
		Do $$$AssertEquals($ClassMethod(accessor, "Shift", bad, 60), "", "Shift gives nothing for '"_bad_"'")
	}
	Do $$$AssertEquals($ClassMethod(accessor, "Shift", "2026-10-18T00:00:00Z", 86400), "2026-10-19T00:00:00Z", "Shift by a day")
	Do $$$AssertEquals($ClassMethod(accessor, "Shift", "2026-12-31T23:59:59Z", 1), "2027-01-01T00:00:00Z", "Shift across a year")
	Do $$$AssertEquals($ClassMethod(accessor, "Shift", "2026-10-18T00:00:00Z", -1), "2026-10-17T23:59:59Z", "Shift back")
	Do $$$AssertEquals($ClassMethod(accessor, "Shift", "2026-10-18T00:00:00Z", 0), "2026-10-18T00:00:00Z", "Shift by nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Shift("2026-10-18T00:00:00Z", -3600), "2026-10-17T23:00:00Z", "AddressCounter.Shift delegates")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Shift("nonsense", 5), "", "AddressCounter.Shift of an unreadable time")
	Do $$$AssertEquals(##class(OcuTalon.Web.SessionEvents).CookieExpiry("2026-10-25T20:00:00Z"), "Sun, 25 Oct 2026 20:00:00 GMT", "CookieExpiry keeps its date form")
	Do $$$AssertEquals(##class(OcuTalon.Web.SessionEvents).CookieExpiry("2026-10-25T20:00:00"), "", "CookieExpiry of a time without the Z")
	For method = "OcuTalon.Data.AddressCounter||Shift", "OcuTalon.Web.SessionEvents||CookieExpiry" {
		Set definition = ##class(%Dictionary.MethodDefinition).%OpenId(method)
		Do $$$AssertTrue($IsObject(definition), method_" is defined")
		Set code = $ZConvert(definition.Implementation.Read(32000), "U")
		Do $$$AssertTrue(code '[ "$ZDATETIMEH", method_" has no $ZDateTimeH of its own")
		Do $$$AssertTrue(code '[ "$ZDTH", method_" has no $ZDTH of its own")
		Do $$$AssertTrue(code [ "SETTINGS", method_" reads Public.Settings")
	}
}

/// Row 2: the schedule reads only the anchor and the interval, so the last reset and its kind never move it; SecondsToReset and
/// ResetSoon count to the next slot, and 300 s ahead is still soon.
Method TestSecondsToResetAndResetSoon()
{
	Set accessor = ..#ACCESSOR
	Do $ClassMethod(accessor, "Set", "resetAnchor", "2026-10-18T00:00:00Z")
	Do $ClassMethod(accessor, "Set", "resetIntervalHours", 4)
	Do $ClassMethod(accessor, "Set", "lastReset", "2026-10-18T05:13:00Z")
	Do $ClassMethod(accessor, "Set", "lastResetKind", "unscheduled")
	Do $$$AssertEquals($ClassMethod(accessor, "NextReset", "2026-10-18T05:30:00Z"), "2026-10-18T08:00:00Z", "an unscheduled reset leaves the schedule")
	Do $ClassMethod(accessor, "Set", "lastReset", "")
	Do $ClassMethod(accessor, "Set", "lastResetKind", "")
	Do $$$AssertEquals($ClassMethod(accessor, "NextReset", "2026-10-18T05:30:00Z"), "2026-10-18T08:00:00Z", "with no last reset, the same")
	Do $$$AssertEquals($Parameter(accessor, "RESETSOONSECONDS"), 300, "reset soon is 300 s")

	Do $$$AssertEquals($ClassMethod(accessor, "SecondsToReset", "2026-10-18T07:55:00Z"), 300, "300 s left")
	Do $$$AssertEquals($ClassMethod(accessor, "ResetSoon", "2026-10-18T07:55:00Z"), 1, "300 s left is soon")
	Do $$$AssertEquals($ClassMethod(accessor, "SecondsToReset", "2026-10-18T07:54:59Z"), 301, "301 s left")
	Do $$$AssertEquals($ClassMethod(accessor, "ResetSoon", "2026-10-18T07:54:59Z"), 0, "301 s left is not soon")
	Do $$$AssertEquals($ClassMethod(accessor, "SecondsToReset", "2026-10-18T07:59:59Z"), 1, "one second left")
	Do $$$AssertEquals($ClassMethod(accessor, "ResetSoon", "2026-10-18T07:59:59Z"), 1, "one second left is soon")
	Do $$$AssertEquals($ClassMethod(accessor, "SecondsToReset", "2026-10-18T08:00:00Z"), 14400, "at the reset: the next slot")
	Do $$$AssertEquals($ClassMethod(accessor, "ResetSoon", "2026-10-18T08:00:00Z"), 0, "at the reset, the next one is far")
	Do $$$AssertEquals($ClassMethod(accessor, "SecondsToReset", "not a time"), "", "an unreadable now")
	Do $$$AssertEquals($ClassMethod(accessor, "ResetSoon", "not a time"), 0, "an unreadable now is not soon")

	Set now = $ZDateTime($ZTimeStamp, 3, 1)
	Set now = $Translate(now, " ", "T")_"Z"
	Do $ClassMethod(accessor, "Set", "resetAnchor", $ClassMethod(accessor, "Shift", now, 120))
	Do $$$AssertEquals($ClassMethod(accessor, "ResetSoon"), 1, "without now: a reset 120 s away is soon")
	Do $ClassMethod(accessor, "Set", "resetAnchor", $ClassMethod(accessor, "Shift", now, 3600))
	Do $$$AssertEquals($ClassMethod(accessor, "ResetSoon"), 0, "without now: a reset an hour away is not")

	Do $ClassMethod(accessor, "Set", "resetAnchor", "")
	Do $$$AssertEquals($ClassMethod(accessor, "SecondsToReset", "2026-10-18T07:55:00Z"), "", "no anchor: no seconds")
	Do $$$AssertEquals($ClassMethod(accessor, "ResetSoon", "2026-10-18T07:55:00Z"), 0, "no anchor: not soon")
}

/// The Public step writes the online-demo flag from the environment, and Ready() stores readiness.
Method TestPublicStep()
{
	Set accessor = ..#ACCESSOR
	Do $ClassMethod(accessor, "ClearReady")
	Do $ClassMethod(accessor, "Set", "onlineDemo", 1)
	If $SYSTEM.Util.GetEnviron("OCUTALON_ONLINE_DEMO") = 1 {
		Do $$$AssertSkipped("OCUTALON_ONLINE_DEMO is 1 in this process: the flag-off case cannot be observed")
	} Else {
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Public).Run(), "the Public step runs")
		Do $$$AssertEquals($ClassMethod(accessor, "Get", "onlineDemo"), 0, "onlineDemo is 0 without OCUTALON_ONLINE_DEMO")
	}
	Do $$$AssertEquals($ClassMethod(accessor, "Get", "ready"), "", "the step leaves readiness cleared")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Public).Ready(), "Ready")
	Do $$$AssertEquals($ClassMethod(accessor, "Get", "ready"), 1, "Ready stores readiness")
}

}
