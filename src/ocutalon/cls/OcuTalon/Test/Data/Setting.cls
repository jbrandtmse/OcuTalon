/// Tests of OcuTalon.Data.Setting (Story 0.4, AD-19): a seeded product value is read through the 60-second per-process
/// cache, a public key is read uncached from Public.Settings, and Seed writes only an absent product key.
/// The fixture key is zz.<n>, with n from ^OcuTalonTest("Setting","n"), which is never reset. Its row and cache entry
/// are removed after the tests, and the public settings key that a test writes is restored.
Class OcuTalon.Test.Data.Setting Extends %UnitTest.TestCase
{

/// The accessor of the public settings.
Parameter PUBLIC = "OcuTalon.Data.Public.Settings";

/// The public key that a test writes.
Parameter PUBLICKEY = "onlineDemo";

/// The fixture's number.
Property Number As %Integer;

/// The product key of the fixture: each test adds its own suffix.
Property Key As %String;

/// The value of the public key before the tests.
Property SavedPublic As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("Setting", "n"))
	Set ..Key = "zz."_..Number
	Set ..SavedPublic = $ClassMethod(..#PUBLIC, "Get", ..#PUBLICKEY)
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $ClassMethod(..#PUBLIC, "Set", ..#PUBLICKEY, ..SavedPublic)
}

/// The cache lasts 60 seconds.
Method TestCacheSeconds()
{
	Do $$$AssertEquals($Parameter("OcuTalon.Data.Setting", "CACHESECONDS"), 60, "the cache lasts 60 seconds")
}

/// A seeded value is read; a changed row is not seen while the cache entry is under 60 seconds old (59 included), and
/// is once the entry is 61 seconds old.
Method TestSeededValueAndCache()
{
	Set key = ..Key_".cache"
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Seed(key, "first"), "the key is seeded")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(key, "default"), "first", "the seeded value is read")
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	Set row.Value = "second"
	Do $$$AssertStatusOK(row.%Save(), "the row is changed")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(key, "default"), "first", "the old value is still read within 60 seconds")
	Set cached = ^||OcuTalon.Setting(key)
	Set $List(cached, 3) = $ZHorolog - 59
	Set ^||OcuTalon.Setting(key) = cached
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(key, "default"), "first", "the old value is still read when the entry is 59 seconds old")
	Set cached = ^||OcuTalon.Setting(key)
	Set $List(cached, 3) = $ZHorolog - 61
	Set ^||OcuTalon.Setting(key) = cached
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(key, "default"), "second", "the new value is read once the entry is 61 seconds old")
}

/// A second Seed changes nothing and drops the cache entry; an absent key and an empty value give the default.
Method TestSeedOnlyWritesAnAbsentKey()
{
	Set key = ..Key_".seed"
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Seed(key, "first"), "the key is seeded")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(key, "default"), "first", "the seeded value is read")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Seed(key, "second"), "a second Seed succeeds")
	Do $$$AssertTrue('$Data(^||OcuTalon.Setting(key)), "Seed drops the cache entry of its key")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexOpen(key).Value, "first", "the second Seed changed nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(key, "default"), "first", "the seeded value is still read")
	Do $$$AssertTrue($Match(##class(OcuTalon.Data.Setting).KeyIndexOpen(key).UpdatedAt, "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"), "UpdatedAt is a UTC time in the stored form")

	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(..Key_".missing", "default"), "default", "an absent key gives the default")
	Set empty = ..Key_".empty"
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Seed(empty, ""), "an empty value is seeded")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(empty, "default"), "default", "an empty value gives the default")
}

/// An empty key reads as the default and is refused by Seed with an error status.
Method TestEmptyKey()
{
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get("", "default"), "default", "an empty key gives the default")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Data.Setting).Seed("", "x"), "Seed refuses an empty key")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexExists(""), 0, "no row was written for the empty key")
}

/// A public key is read from Public.Settings on every call, and Seed refuses it, naming it.
Method TestPublicKey()
{
	Set key = ..#PUBLICKEY
	Do $$$AssertStatusOK($ClassMethod(..#PUBLIC, "Set", key, "zz"_..Number), "the public key is written")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(key, "default"), $ClassMethod(..#PUBLIC, "Get", key), "Get returns Public.Settings' value")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(key, "default"), "zz"_..Number, "the value is the one written")
	Do $$$AssertStatusOK($ClassMethod(..#PUBLIC, "Set", key, "zy"_..Number), "the public key is written again")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(key, "default"), "zy"_..Number, "a changed public value is read at once")
	Do $$$AssertStatusOK($ClassMethod(..#PUBLIC, "Set", key, ""), "the public key is removed")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(key, "default"), "default", "an unset public key gives the default")

	Set sc = ##class(OcuTalon.Data.Setting).Seed(key, "x")
	Do $$$AssertStatusNotOK(sc, "Seed refuses a public key")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ key, "the error names the key")
	Set sc = ##class(OcuTalon.Data.Setting).Seed("ready", "x")
	Do $$$AssertStatusNotOK(sc, "Seed refuses the readiness key")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexExists(key), 0, "no row was written for the public key")
}

/// Removes the fixture's rows and cache entries.
Method Clean() [ Private ]
{
	For suffix = ".cache", ".seed", ".empty", ".missing" {
		Do ..RemoveRow(..Key_suffix)
	}
}

/// Removes the row of a key and its cache entry.
Method RemoveRow(key As %String) [ Private ]
{
	If ##class(OcuTalon.Data.Setting).KeyIndexExists(key, .id) Do ##class(OcuTalon.Data.Setting).%DeleteId(id)
	Kill ^||OcuTalon.Setting(key)
}

}
