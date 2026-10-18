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

/// Row 11: a key that is not fixed is refused with an error status that names it, nothing is stored,
/// and "ready" cannot be written through Set.
Method TestRefusedKeys()
{
	Set accessor = ..#ACCESSOR
	Do $ClassMethod(accessor, "ClearReady")

	Set sc = $ClassMethod(accessor, "Set", "nosuch", "x")
	Do $$$AssertStatusNotOK(sc, "Set of an unknown key is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "nosuch", "the error names the key")
	Do $$$AssertEquals($ClassMethod(accessor, "Get", "nosuch", .read), "", "nothing was stored under the unknown key")
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
