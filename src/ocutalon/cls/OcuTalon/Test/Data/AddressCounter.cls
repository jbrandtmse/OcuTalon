/// Tests of Data.AddressCounter (Story 16.3; AD-13, AD-27): Recent counts the rows of an address created in the past hour, 59 minutes
/// old counted and 61 not, and returns the earliest of them; it compares the hash exactly and never reads another address's rows; Add
/// stores the address's SHA-256 and the creation time and never the address; Lock is one per address. The fixture addresses are
/// zz-counter-<n>-<case>, with n from ^OcuTalonTest("AddressCounter","n") (never reset); every row of them is removed before and
/// after each test, whatever its outcome.
Class OcuTalon.Test.Data.AddressCounter Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("AddressCounter", "n"))
	Do ..Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Clean()
	Quit $SYSTEM.Status.OK()
}

/// The window is the past hour: rows 61 minutes and 3601 seconds old are not counted, rows 59 minutes, one minute and no time old are;
/// oldest is the earliest counted CreatedAt, and "" when nothing counts. Another address's rows are never counted, and neither are
/// rows whose hash is the address's own in another case, which share its index entry (SQLUPPER).
Method TestRecentWindow()
{
	Set address = ..Address("window")
	Set hash = ##class(OcuTalon.Data.Session).Hash(address)
	Set count = ##class(OcuTalon.Data.AddressCounter).Recent(address, .oldest)
	Do $$$AssertEquals(count_"|"_oldest, "0|", "no row: count 0 and no oldest")
	Do ..Row(hash, 3660)
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(address, .oldest)_"|"_oldest, "0|", "a row 61 minutes old is not counted")
	Do ..Row(hash, 3601)
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(address), 0, "nor one of 3601 seconds")
	Set recent = ..Row(hash, 3540)
	Set count = ##class(OcuTalon.Data.AddressCounter).Recent(address, .oldest)
	Do $$$AssertEquals(count, 1, "a row 59 minutes old is counted")
	Do $$$AssertEquals(oldest, ##class(OcuTalon.Data.AddressCounter).%OpenId(recent).CreatedAt, "and is the oldest")
	Do ..Row(hash, 60)
	Do ..Row(hash, 0)
	Set count = ##class(OcuTalon.Data.AddressCounter).Recent(address, .oldest)
	Do $$$AssertEquals(count, 3, "three rows in the hour")
	Do $$$AssertEquals(oldest, ##class(OcuTalon.Data.AddressCounter).%OpenId(recent).CreatedAt, "the oldest is the 59-minute row's")

	Set other = ..Address("other")
	Do ..Row(##class(OcuTalon.Data.Session).Hash(other), 10)
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(address), 3, "another address's row is not counted")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(other), 1, "it counts for its own address")
	Do $$$AssertTrue((hash '= $ZConvert(hash, "L")) && (hash '= $ZConvert(hash, "U")), "the hash has letters of both cases")
	Do ..Row($ZConvert(hash, "L"), 10)
	Do ..Row($ZConvert(hash, "U"), 10)
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(address, .oldest), 3, "rows of the hash in another case are not counted")
	Do $$$AssertEquals(oldest, ##class(OcuTalon.Data.AddressCounter).%OpenId(recent).CreatedAt, "and are never the oldest")
	Set upper = ..Address("CASE")
	Set lower = ..Address("case")
	Do ..Row(##class(OcuTalon.Data.Session).Hash(upper), 10)
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(lower), 0, "addresses that differ in case are different addresses")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(upper), 1, "each counts its own row")
}

/// Add stores the SHA-256 of the address (43 characters) and a creation time in the stored form, and neither property holds the
/// address; Lock is taken, and after Unlock another job takes it.
Method TestAddStoresOnlyTheHash()
{
	Set address = ..Address("add")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.AddressCounter).Add(address), "Add")
	Set id = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?", ##class(OcuTalon.Data.Session).Hash(address))
	While result.%Next() {
		Set id = result.%Get("ID")
	}
	Do $$$AssertTrue(id '= "", "one row has the address's hash")
	Set row = ##class(OcuTalon.Data.AddressCounter).%OpenId(id)
	Do $$$AssertEquals(row.AddressHash, ##class(OcuTalon.Data.Session).Hash(address), "it holds the hash")
	Do $$$AssertEquals($Length(row.AddressHash), 43, "of 43 characters")
	Do $$$AssertTrue(row.CreatedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "CreatedAt is a UTC time: "_row.CreatedAt)
	Do $$$AssertTrue((row.AddressHash '= address) && (row.CreatedAt '= address), "no property holds the address")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(address), 1, "the row is counted")

	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Lock(address), 1, "the lock is taken")
	Do ##class(OcuTalon.Data.AddressCounter).Unlock(address)
	Do $$$AssertEquals(..FreeInAnotherJob(address), 1, "and after Unlock another job takes it")
}

/// Lock is exclusive across processes: while this process holds an address's lock, another job cannot take it within the lock's
/// wait, and once Unlock has released it, the job takes it at once. Another address's lock is not affected.
Method TestLockExcludesAnotherJob()
{
	Set address = ..Address("lock")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Lock(address), 1, "the lock is taken")
	Do $$$AssertEquals(..FreeInAnotherJob(address), 0, "another job cannot take it while it is held")
	Do $$$AssertEquals(..FreeInAnotherJob(..Address("lockother")), 1, "but takes another address's lock")
	Do ##class(OcuTalon.Data.AddressCounter).Unlock(address)
	Do $$$AssertEquals(..FreeInAnotherJob(address), 1, "after Unlock another job takes it at once")
}

/// The Purge keeps one hour, whatever daysToKeep says, and leaves another address's recent rows alone.
Method TestPurgeKeepsOneHour()
{
	Set address = ..Address("purge")
	Set hash = ##class(OcuTalon.Data.Session).Hash(address)
	Set old = ..Row(hash, 3700)
	Set recent = ..Row(hash, 3500)
	Set ahead = ..Row(hash, 0)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.AddressCounter).Purge(90), "Purge(90)")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).%ExistsId(old), 0, "the row of 3700 seconds is deleted")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).%ExistsId(recent), 1, "the row of 3500 seconds is kept")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).%ExistsId(ahead), 1, "and a fresh row")
	Set another = ..Row(hash, 7200)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.AddressCounter).Purge(0), "Purge(0)")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).%ExistsId(another), 0, "a row of two hours is deleted")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).%ExistsId(recent), 1, "the recent row is kept")
}

/// (QA) The Purge deletes rows, not addresses (AD-27): of three addresses, the one with an old and a recent row loses only the old one,
/// the one with only old rows loses them all and the one with only recent rows keeps them; the edge of the hour is to the second
/// (3590 seconds kept, 3610 deleted); a second Purge changes nothing; and Recent still counts what is left.
Method TestPurgeIsPerRowNotPerAddress()
{
	Set both = ..Address("purgeA")
	Set oldOnly = ..Address("purgeB")
	Set recentOnly = ..Address("purgeC")
	Set bothHash = ##class(OcuTalon.Data.Session).Hash(both)
	Set bothOld = ..Row(bothHash, 3610)
	Set bothEdge = ..Row(bothHash, 3590)
	Set bothFresh = ..Row(bothHash, 5)
	Set oldA = ..Row(##class(OcuTalon.Data.Session).Hash(oldOnly), 7300)
	Set oldB = ..Row(##class(OcuTalon.Data.Session).Hash(oldOnly), 86400)
	Set recentA = ..Row(##class(OcuTalon.Data.Session).Hash(recentOnly), 100)
	Set recentB = ..Row(##class(OcuTalon.Data.Session).Hash(recentOnly), 1800)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.AddressCounter).Purge(1), "Purge")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).%ExistsId(bothOld), 0, "the old row of the mixed address is deleted")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).%ExistsId(bothEdge), 1, "its row of 3590 seconds is kept")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).%ExistsId(bothFresh), 1, "and its fresh row")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).%ExistsId(oldA) + ##class(OcuTalon.Data.AddressCounter).%ExistsId(oldB), 0, "the old-only address loses every row")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).%ExistsId(recentA) + ##class(OcuTalon.Data.AddressCounter).%ExistsId(recentB), 2, "the recent-only address keeps both")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(both), 2, "Recent counts the mixed address's two rows")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(oldOnly), 0, "and none of the old-only address")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(recentOnly), 2, "and both of the recent-only address")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.AddressCounter).Purge(1), "a second Purge")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(both) + ##class(OcuTalon.Data.AddressCounter).Recent(recentOnly), 4, "changes nothing")
}

/// 1 when a job of its own takes the address's lock (Lock, which waits 5 seconds), 0 when it could not: whether another process
/// holds the lock. The job answers in a global, which this method removes.
ClassMethod FreeInAnotherJob(address As %String) As %Boolean
{
	Set node = $Name(^OcuTalonTest("AddressCounter", "probe", address))
	Kill @node
	Job ..Probe(address)
	Set deadline = $ZHorolog + 20
	While ($Data(@node) = 0) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Set result = $Get(@node, 0)
	Kill @node
	Quit result
}

/// The job of FreeInAnotherJob: takes the address's lock, releases it when it got it and records whether it did.
ClassMethod Probe(address As %String)
{
	Set taken = ##class(OcuTalon.Data.AddressCounter).Lock(address)
	If taken Do ##class(OcuTalon.Data.AddressCounter).Unlock(address)
	Set @$Name(^OcuTalonTest("AddressCounter", "probe", address)) = taken
}

/// A counter row of the hash created the given number of seconds ago; returns its id.
Method Row(hash As %String, secondsAgo As %Integer) As %Integer [ Private ]
{
	Set row = ##class(OcuTalon.Data.AddressCounter).%New()
	Set row.AddressHash = hash
	Set row.CreatedAt = ##class(OcuTalon.Data.AddressCounter).Shift(##class(OcuTalon.Data.Time).NowUtc(), -secondsAgo)
	Do $$$AssertStatusOK(row.%Save(), "a row is saved")
	Quit row.%Id()
}

/// A fixture address of this run.
Method Address(case As %String) As %String [ Private ]
{
	Quit "zz-counter-"_..Number_"-"_case
}

/// Deletes the counter rows of every fixture address of every run, also those whose hash is a fixture hash in another case.
ClassMethod Clean() [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, AddressHash FROM OcuTalon_Data.AddressCounter")
	Kill ids
	While result.%Next() {
		Set ids(result.%Get("ID")) = result.%Get("AddressHash")
	}
	Set max = $Get(^OcuTalonTest("AddressCounter", "n"))
	Set id = ""
	For {
		Set id = $Order(ids(id), 1, hash)
		Quit:id=""
		For n = 1:1:max {
			For case = "window", "other", "CASE", "case", "add", "purge", "purgeA", "purgeB", "purgeC" {
				If $ZConvert(hash, "U") = $ZConvert(##class(OcuTalon.Data.Session).Hash("zz-counter-"_n_"-"_case), "U") Do ##class(OcuTalon.Data.AddressCounter).%DeleteId(id) Quit
			}
		}
	}
}

}
