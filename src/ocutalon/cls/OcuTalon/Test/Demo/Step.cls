/// Tests of the Demo step's decisions (Story 0.10) that create nothing, so they run on a slot and in the lane-b shard. They
/// never call Run, System or Orders and create no namespace:
///   - TestDefaultMode: the seed is 1 where the image's version file exists and 0 where it does not;
///   - TestMode: Mode seeds an absent demo.mode row with the default, reads a present row without touching it, and is on only
///     for the value "1";
///   - TestWithOrders: the OCUORDERS database resources are added with Read, or removed, and nothing else changes;
///   - TestDirectory: both database directories are below the manager directory;
///   - TestPlan: the action for each of the eight combinations of mode, existence and ownership, with the refusal text, or
///     with the same sentence as the kept note where the action is keep;
///   - TestOwned: a namespace that the step did not create is not owned.
/// The demo.mode row is saved in OnBeforeAllTests (absent, or its value and UpdatedAt) and put back in OnAfterAllTests.
Class OcuTalon.Test.Demo.Step Extends %UnitTest.TestCase
{

/// The step under test.
Parameter STEP = "OcuTalon.Install.Step.Demo";

/// 1 when the demo.mode row existed before the tests.
Property Found As %Boolean;

/// The value of the row before the tests.
Property SavedValue As %String(MAXLEN = 1000);

/// The UpdatedAt of the row before the tests.
Property SavedUpdatedAt As %String(MAXLEN = 20);

Method OnBeforeAllTests() As %Status
{
	Do ..Saved(.found, .value, .updatedAt)
	Set ..Found = found, ..SavedValue = value, ..SavedUpdatedAt = updatedAt
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Restore()
	Quit $$$OK
}

/// A present version file gives 1 and an absent one gives 0.
Method TestDefaultMode()
{
	Set file = ##class(%File).TempFilename("txt")
	Do $$$AssertEquals(##class(%File).Exists(file), 1, "the temporary file exists")
	Do $$$AssertEquals($ClassMethod(..#STEP, "DefaultMode", file), 1, "a version file that exists gives 1")
	Do ##class(%File).Delete(file)
	Do $$$AssertEquals($ClassMethod(..#STEP, "DefaultMode", file), 0, "a version file that is absent gives 0")
	Do $$$AssertEquals($ClassMethod(..#STEP, "DefaultMode", file_".none"), 0, "another absent file gives 0")
}

/// Row 18: absent, the row is written with the default and the default is returned; present, the value is returned (on only
/// for "1") and the row is left as it was.
Method TestMode()
{
	Set key = $Parameter(..#STEP, "MODEKEY")
	Do ..Remove()
	Set default = $ClassMethod(..#STEP, "DefaultMode")
	Do $$$AssertEquals($ClassMethod(..#STEP, "Mode"), default, "an absent row gives the default")
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	Do $$$AssertTrue($IsObject(row), "the row is written")
	If $IsObject(row) Do $$$AssertEquals(row.Value, default, "the row holds the default")

	For value = "0", "1", "2", "yes" {
		Do ..Put(value, "2026-01-02T03:04:05Z")
		Do $$$AssertEquals($ClassMethod(..#STEP, "Mode"), $Select(value = "1": 1, 1: 0), "the value '"_value_"' is read")
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		Do $$$AssertEquals(row.Value, value, "the row keeps '"_value_"'")
		Do $$$AssertEquals(row.UpdatedAt, "2026-01-02T03:04:05Z", "the row's UpdatedAt is untouched by a read of '"_value_"'")
	}
}

/// The OCUORDERS resources are added with Read, kept in place, normalized to Read, and removed; the other entries stay.
Method TestWithOrders()
{
	Set code = "%DB_OCUORDERS_CODE"
	Set data = "%DB_OCUORDERS_DATA"
	Set start = "%Ens_Portal:U,%DB_OCUTALON_DATA:R"
	Set added = $ClassMethod(..#STEP, "WithOrders", start, 1)
	Do $$$AssertEquals(added, start_","_code_":R,"_data_":R", "both resources are added with Read")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrders", added, 1), added, "adding again changes nothing")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrders", added, 0), start, "removing gives the start back")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrders", start, 0), start, "removing what is absent changes nothing")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrders", "", 1), code_":R,"_data_":R", "an empty list gets both")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrders", "", 0), "", "an empty list stays empty")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrders", "a:R,"_data_":RW,b:RW", 1), "a:R,"_data_":R,b:RW,"_code_":R", "a listed resource keeps its place and is set to Read")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrders", "a:R,"_code_":R,b:RW,"_data_":RW", 0), "a:R,b:RW", "both are removed whatever their permission")
}

/// Both directories are below the manager directory, in lower case, with the closing slash.
Method TestDirectory()
{
	Set manager = $SYSTEM.Util.ManagerDirectory()
	Do $$$AssertEquals($ClassMethod(..#STEP, "Directory", "OCUORDERS_CODE"), manager_"ocuorders_code/", "the code directory")
	Do $$$AssertEquals($ClassMethod(..#STEP, "Directory", "OCUORDERS_DATA"), manager_"ocuorders_data/", "the data directory")
}

/// Rows 6 and 7: the eight combinations of on, exists and owned.
Method TestPlan()
{
	Set refusal = "Namespace OCUORDERS exists and uses databases that OcuTalon did not create, so the Demo step leaves it alone."
	Set table = $ListBuild("0,0,0,remove", "0,0,1,remove", "0,1,0,keep", "0,1,1,remove", "1,0,0,create", "1,0,1,create", "1,1,0,error", "1,1,1,create")
	Set position = 0
	While $ListNext(table, position, row) {
		Set action = $ClassMethod(..#STEP, "Plan", $Piece(row, ",", 1), $Piece(row, ",", 2), $Piece(row, ",", 3), .sc, .kept)
		Do $$$AssertEquals(action, $Piece(row, ",", 4), "on "_$Piece(row, ",", 1)_", exists "_$Piece(row, ",", 2)_", owned "_$Piece(row, ",", 3)_" is "_$Piece(row, ",", 4))
		If action = "error" {
			Do $$$AssertEquals($SYSTEM.Status.GetErrorText(sc), "ERROR #5001: "_refusal, "the refusal text")
		} Else {
			Do $$$AssertStatusOK(sc, "no refusal for "_$Piece(row, ",", 4))
		}
		Do $$$AssertEquals(kept, $Select(action = "keep": refusal, 1: ""), "kept is the refusal's sentence for keep and empty otherwise")
	}
}

/// A namespace whose databases are not the step's own is not owned, and neither is one that does not exist.
Method TestOwned()
{
	For namespace = "USER", "%SYS", "OCUTALON", "ZZNOSUCHNAMESPACE" {
		Do $$$AssertEquals($ClassMethod(..#STEP, "Owned", namespace), 0, namespace_" is not owned")
	}
}

/// The demo.mode row as it is now, for a later PutBack: found is 1 when the row exists, with its value and UpdatedAt.
/// Shared with the other tests that switch demo mode (Test.Web.Api), like Put, Remove and PutBack.
ClassMethod Saved(Output found As %Boolean, Output value As %String, Output updatedAt As %String)
{
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen($Parameter(..#STEP, "MODEKEY"))
	Set found = $IsObject(row), value = "", updatedAt = ""
	If found Set value = row.Value, updatedAt = row.UpdatedAt
}

/// Deletes the demo.mode row and drops this process's cache entry of it. A failed delete throws its status.
ClassMethod Remove()
{
	Set key = $Parameter(..#STEP, "MODEKEY")
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	If $IsObject(row) $$$ThrowOnError(##class(OcuTalon.Data.Setting).%DeleteId(row.%Id()))
	Kill ^||OcuTalon.Setting(key)
}

/// Writes the demo.mode row with the value and the time, creating it when it is absent, and drops this process's cache
/// entry of it, so that the next Get reads the row. A failed save throws its status.
ClassMethod Put(value As %String, updatedAt As %String)
{
	Set key = $Parameter(..#STEP, "MODEKEY")
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	If '$IsObject(row) {
		Set row = ##class(OcuTalon.Data.Setting).%New()
		Set row.Key = key
	}
	Set row.Value = value
	Set row.UpdatedAt = updatedAt
	$$$ThrowOnError(row.%Save())
	Kill ^||OcuTalon.Setting(key)
}

/// Puts the demo.mode row back as Saved found it: written again when it existed, deleted when it did not.
ClassMethod PutBack(found As %Boolean, value As %String, updatedAt As %String)
{
	If found {
		Do ..Put(value, updatedAt)
	} Else {
		Do ..Remove()
	}
}

/// Puts the row back as OnBeforeAllTests found it.
Method Restore() [ Private ]
{
	Do ..PutBack(..Found, ..SavedValue, ..SavedUpdatedAt)
}

}
