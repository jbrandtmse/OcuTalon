/// Tests of Data.AddressCounter (Story 16.3; AD-13, AD-27): Recent counts the rows of an address created in the past hour, 59 minutes
/// old counted and 61 not, and returns the earliest of them; it compares the hash exactly and never reads another address's rows; Add
/// stores the address's AddressHash (an HMAC under the instance key, Story 29.5) and the creation time and never the address; Lock is
/// one per address; the key lives only in the private database, is new at each reset and fails closed when it cannot be made. The
/// fixture addresses are zz-counter-<n>-<case>, with n from ^OcuTalonTest("AddressCounter","n") (never reset); every row of them is
/// removed before and after each test, whatever its outcome. The key tests save and restore lastReset and the key node.
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
	Set hash = ##class(OcuTalon.Data.AddressCounter).AddressHash(address)
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
	Do ..Row(##class(OcuTalon.Data.AddressCounter).AddressHash(other), 10)
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(address), 3, "another address's row is not counted")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(other), 1, "it counts for its own address")
	Do $$$AssertTrue((hash '= $ZConvert(hash, "L")) && (hash '= $ZConvert(hash, "U")), "the hash has letters of both cases")
	Do ..Row($ZConvert(hash, "L"), 10)
	Do ..Row($ZConvert(hash, "U"), 10)
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(address, .oldest), 3, "rows of the hash in another case are not counted")
	Do $$$AssertEquals(oldest, ##class(OcuTalon.Data.AddressCounter).%OpenId(recent).CreatedAt, "and are never the oldest")
	Set upper = ..Address("CASE")
	Set lower = ..Address("case")
	Do ..Row(##class(OcuTalon.Data.AddressCounter).AddressHash(upper), 10)
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(lower), 0, "addresses that differ in case are different addresses")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(upper), 1, "each counts its own row")

	Set legacy = ..Address("legacy")
	Do ..Row(##class(OcuTalon.Data.Session).Hash(legacy), 10)
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(legacy), 0, "a row stored as the address's SHA-256 is not counted")
}

/// Add stores the AddressHash of the address (43 characters) and a creation time in the stored form, and neither property holds the
/// address; Lock is taken, and after Unlock another job takes it.
Method TestAddStoresOnlyTheHash()
{
	Set address = ..Address("add")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.AddressCounter).Add(address), "Add")
	Set id = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?", ##class(OcuTalon.Data.AddressCounter).AddressHash(address))
	While result.%Next() {
		Set id = result.%Get("ID")
	}
	Do $$$AssertTrue(id '= "", "one row has the address's hash")
	Set row = ##class(OcuTalon.Data.AddressCounter).%OpenId(id)
	Do $$$AssertEquals(row.AddressHash, ##class(OcuTalon.Data.AddressCounter).AddressHash(address), "it holds the hash")
	Do $$$AssertEquals($Length(row.AddressHash), 43, "of 43 characters")
	Do $$$AssertTrue(row.AddressHash ? 43(1AN,1"-",1"_"), "in base64url")
	Do $$$AssertTrue(row.AddressHash '= ##class(OcuTalon.Data.Session).Hash(address), "not the address's SHA-256")
	Set keyNode = ##class(OcuTalon.Data.AddressCounter).#KEYGLOBAL
	Set expected = $Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.HMACSHA(256, $ZConvert(address, "O", "UTF8"), $List(@keyNode, 2)), 1), "+/=", "-_")
	Do $$$AssertTrue(row.AddressHash = expected, "it is the HMAC-SHA-256 of the UTF-8 address under the node's key")
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

/// The lock is named by the address's AddressHash and not by its plain SHA-256: while this process holds an address's lock, another job
/// cannot take the lock of that name, and takes the lock named by the SHA-256 of the same address at once.
Method TestLockNameIsTheKeyedHash()
{
	Set address = ..Address("lockname")
	Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Lock(address), 1, "the lock is taken")
	Set named = ..NameFreeInAnotherJob(##class(OcuTalon.Data.AddressCounter).AddressHash(address))
	Set plain = ..NameFreeInAnotherJob(##class(OcuTalon.Data.Session).Hash(address))
	Do ##class(OcuTalon.Data.AddressCounter).Unlock(address)
	Do $$$AssertEquals(named, 0, "the lock named by AddressHash is held")
	Do $$$AssertEquals(plain, 1, "the lock named by the plain SHA-256 is not")
}

/// The Purge keeps one hour, whatever daysToKeep says, and leaves another address's recent rows alone.
Method TestPurgeKeepsOneHour()
{
	Set address = ..Address("purge")
	Set hash = ##class(OcuTalon.Data.AddressCounter).AddressHash(address)
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
	Set bothHash = ##class(OcuTalon.Data.AddressCounter).AddressHash(both)
	Set bothOld = ..Row(bothHash, 3610)
	Set bothEdge = ..Row(bothHash, 3590)
	Set bothFresh = ..Row(bothHash, 5)
	Set oldA = ..Row(##class(OcuTalon.Data.AddressCounter).AddressHash(oldOnly), 7300)
	Set oldB = ..Row(##class(OcuTalon.Data.AddressCounter).AddressHash(oldOnly), 86400)
	Set recentA = ..Row(##class(OcuTalon.Data.AddressCounter).AddressHash(recentOnly), 100)
	Set recentB = ..Row(##class(OcuTalon.Data.AddressCounter).AddressHash(recentOnly), 1800)
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

/// The key's home (matrix row 3): the parameter names a global of the private database, the node holds $ListBuild(lastReset, 32 bytes)
/// with no subscripted node, and Key is a private method. Nothing here prints or describes the key.
Method TestKeyIsPrivate()
{
	Set node = ##class(OcuTalon.Data.AddressCounter).#KEYGLOBAL
	Do $$$AssertEquals(node, "^OcuTalonP.AddrCountK", "the key global is the private one")
	Set private = ##class(%SYS.Namespace).GetGlobalDest($Namespace, "^OcuTalonP.Zz")
	Do $$$AssertEquals(##class(%SYS.Namespace).GetGlobalDest($Namespace, node), private, "and resolves where the private records do")
	Set hash = ##class(OcuTalon.Data.AddressCounter).AddressHash(..Address("private"))
	Do $$$AssertEquals($Length(hash), 43, "a use makes the hash")
	Set value = $Get(@node)
	Do $$$AssertTrue($ListValid(value) && ($ListLength(value) = 2), "the node is a list of two")
	Do $$$AssertEquals($List(value, 1), ##class(OcuTalon.Data.Public.Settings).Get("lastReset"), "its marker is lastReset")
	Do $$$AssertEquals($Length($List(value, 2)), 32, "its key is 32 bytes")
	Do $$$AssertEquals($Data(@node), 1, "the node has no descendant, so no subscripted node holds the key")
	Set method = ##class(%Dictionary.CompiledMethod).%OpenId("OcuTalon.Data.AddressCounter||Key")
	Do $$$AssertTrue($IsObject(method) && method.Private, "Key is a private method")
}

/// Two resets, two keys (matrix row 4): the node as a golden copy holds it (none, or the one a copy captured at T1) and a new
/// lastReset written as the Public step writes it. Each reset gives a key that differs from every earlier one and a new hash of one
/// address; the row of T1 no longer counts; an unchanged marker keeps the key and the hash. lastReset and the node are put back
/// whatever happens, and the rows of the test are deleted by id.
Method TestKeyPerReset()
{
	Set node = ##class(OcuTalon.Data.AddressCounter).#KEYGLOBAL
	Set savedNode = $Data(@node)
	Set savedValue = $Get(@node)
	Set savedMark = ##class(OcuTalon.Data.Public.Settings).Get("lastReset")
	Set address = ..Address("reset")
	Set ids = ""
	Try {
		Set t1 = "2026-01-01T00:00:00Z"
		Set t2 = "2026-01-01T04:00:00Z"
		Set t3 = "2026-01-01T08:00:00Z"
		Set t4 = "2026-01-01T12:00:00Z"
		Do ##class(OcuTalon.Data.Public.Settings).Set("lastReset", t1)
		Kill @node
		Set h1 = ##class(OcuTalon.Data.AddressCounter).AddressHash(address)
		Set copy = @node
		Set k1 = $List(copy, 2)
		Do $$$AssertEquals($Length(k1), 32, "the first use after a copy with no node makes a key")
		Do $$$AssertEquals($List(copy, 1), t1, "with the marker T1")
		Do $$$AssertTrue(##class(OcuTalon.Data.AddressCounter).AddressHash(address) = h1, "a second use at the same marker keeps the hash")
		Do $$$AssertTrue($List(@node, 2) = k1, "and the key")
		Do $$$AssertStatusOK(##class(OcuTalon.Data.AddressCounter).Add(address), "a row is added at T1")
		Set ids = ..IdsOf(h1)
		Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(address), 1, "and counts")

		Do ##class(OcuTalon.Data.Public.Settings).Set("lastReset", t2)
		Set @node = copy
		Set h2 = ##class(OcuTalon.Data.AddressCounter).AddressHash(address)
		Set k2 = $List(@node, 2)
		Do $$$AssertTrue(k2 '= k1, "the first reset gives a new key")
		Do $$$AssertTrue(h2 '= h1, "and a new hash of the address")
		Do $$$AssertEquals($List(@node, 1), t2, "with the marker T2")
		Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(address), 0, "the row of T1 no longer counts")

		Do ##class(OcuTalon.Data.Public.Settings).Set("lastReset", t3)
		Set @node = copy
		Set h3 = ##class(OcuTalon.Data.AddressCounter).AddressHash(address)
		Set k3 = $List(@node, 2)
		Do $$$AssertTrue((k3 '= k1) && (k3 '= k2), "the second reset gives a key that differs from both earlier ones")
		Do $$$AssertTrue((h3 '= h1) && (h3 '= h2), "and a hash that differs from both")

		Do ##class(OcuTalon.Data.Public.Settings).Set("lastReset", t4)
		Kill @node
		Set h4 = ##class(OcuTalon.Data.AddressCounter).AddressHash(address)
		Set k4 = $List(@node, 2)
		Do $$$AssertTrue((k4 '= k1) && (k4 '= k2) && (k4 '= k3), "a reset onto a copy with no node gives a fourth key")
		Do $$$AssertTrue((h4 '= h1) && (h4 '= h2) && (h4 '= h3), "and a fourth hash")
	} Catch exception {
		Do $$$AssertFailure("the test raised an error: "_exception.Name)
	}
	Do ..RestoreKey(node, savedNode, savedValue, savedMark)
	For i = 1:1:$Length(ids, ",") {
		If $Piece(ids, ",", i) '= "" Do ##class(OcuTalon.Data.AddressCounter).%DeleteId($Piece(ids, ",", i))
	}
}

/// No key can be made (matrix row 8): while another process holds the key lock and no valid node exists, Lock answers 0 after its wait
/// and no node is made; once the lock is free the next use makes the key. The lock is released and the node restored whatever happens.
Method TestKeyBusyFailsClosed()
{
	Set node = ##class(OcuTalon.Data.AddressCounter).#KEYGLOBAL
	Set savedNode = $Data(@node)
	Set savedValue = $Get(@node)
	Set marker = ##class(OcuTalon.Data.Public.Settings).Get("lastReset")
	Set address = ..Address("busy")
	Set held = 0
	Set closed = ""
	Try {
		Kill @node
		Lock +@node:5
		Set held = $Test
		Do $$$AssertEquals(held, 1, "the test holds the key lock")
		Do $$$AssertEquals(..FreeInAnotherJob(address), 0, "Lock answers 0 while the key lock is held elsewhere")
		Do $$$AssertEquals($Data(@node), 0, "and no node is made")
		Set closed = ..ClosedInAnotherJob(address)
		Do $$$AssertEquals($List(closed, 1), 1, "Add answers an error")
		Do $$$AssertEquals($List(closed, 2), 1, "that names no address")
		Do $$$AssertEquals($List(closed, 3), 0, "and writes no row")
		Do $$$AssertEquals($List(closed, 4), 0, "Recent answers 0")
		Do $$$AssertEquals($List(closed, 5), 1, "Unlock raises nothing")
		Do $$$AssertEquals($Data(@node), 0, "and still no node is made")
		Lock -@node
		Set held = 0
		Do $$$AssertEquals(..FreeInAnotherJob(address), 1, "once the lock is free the next use takes the address's lock")
		Do $$$AssertEquals($Data(@node), 1, "and makes the key")
	} Catch exception {
		Do $$$AssertFailure("the test raised an error: "_exception.Name)
	}
	If held Lock -@node
	Do ..RestoreKey(node, savedNode, savedValue, marker)
}

/// The key is made once (matrix row 4): a process that waited for the key lock while another made the key takes that key and does not
/// make a second one. This process holds the key lock, a job asks for a hash and waits, this process stores a key and releases the
/// lock, and the job's hash is the one under the stored key. The node and lastReset are put back whatever happens.
Method TestKeyMadeOnceUnderContention()
{
	Set node = ##class(OcuTalon.Data.AddressCounter).#KEYGLOBAL
	Set savedNode = $Data(@node)
	Set savedValue = $Get(@node)
	Set marker = ##class(OcuTalon.Data.Public.Settings).Get("lastReset")
	Set address = ..Address("once")
	Set result = $Name(^OcuTalonTest("AddressCounter", "once", address))
	Set held = 0
	Try {
		Kill @node, @result
		Lock +@node:5
		Set held = $Test
		Job ..HashJob(address)
		Hang 1.5
		Do $$$AssertEquals($Data(@result), 0, "the job waits for the key lock")
		Set stored = $Translate($Justify("", 32), " ", "k")
		Set @node = $ListBuild(marker, stored)
		Lock -@node
		Set held = 0
		Set deadline = $ZHorolog + 20
		While ($Data(@result) = 0) && ($ZHorolog < deadline) {
			Hang 0.05
		}
		Do $$$AssertTrue($List(@node, 2) = stored, "the job did not replace the stored key")
		Do $$$AssertTrue($Get(@result) = ##class(OcuTalon.Data.AddressCounter).AddressHash(address), "its hash is the one under the stored key")
	} Catch exception {
		Do $$$AssertFailure("the test raised an error: "_exception.Name)
	}
	If held Lock -@node
	Kill @result
	Do ..RestoreKey(node, savedNode, savedValue, marker)
}

/// The job of TestKeyMadeOnceUnderContention: records the address's hash.
ClassMethod HashJob(address As %String)
{
	Set @$Name(^OcuTalonTest("AddressCounter", "once", address)) = ##class(OcuTalon.Data.AddressCounter).AddressHash(address)
}

/// 1 when a job of its own takes the address-lock global named by the subscript, 0 when it could not within 2 seconds.
ClassMethod NameFreeInAnotherJob(subscript As %String) As %Boolean
{
	Set node = $Name(^OcuTalonTest("AddressCounter", "name"))
	Kill @node
	Job ..NameProbe(subscript)
	Set deadline = $ZHorolog + 20
	While ($Data(@node) = 0) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Set result = $Get(@node, 0)
	Kill @node
	Quit result
}

/// The job of NameFreeInAnotherJob.
ClassMethod NameProbe(subscript As %String)
{
	Lock +^OcuTalon.Data.AddressCounter(subscript):2
	Set taken = $Test
	If taken Lock -^OcuTalon.Data.AddressCounter(subscript)
	Set @$Name(^OcuTalonTest("AddressCounter", "name")) = taken
}

/// A list from a job of its own, started while no key can be had: 1 when Add answered an error, 1 when the error text lacks the address,
/// the number of rows Add wrote, Recent's answer, and 1 when Unlock raised nothing.
ClassMethod ClosedInAnotherJob(address As %String) As %List
{
	Set node = $Name(^OcuTalonTest("AddressCounter", "closed", address))
	Kill @node
	Job ..ClosedProbe(address)
	Set deadline = $ZHorolog + 40
	While ($Data(@node) = 0) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Set result = $Get(@node, $ListBuild(-1, -1, -1, -1, -1))
	Kill @node
	Quit result
}

/// The job of ClosedInAnotherJob.
ClassMethod ClosedProbe(address As %String)
{
	Set before = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.AddressCounter")
	Do before.%Next()
	Set rowsBefore = before.%GetData(1)
	Set sc = ##class(OcuTalon.Data.AddressCounter).Add(address)
	Set after = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.AddressCounter")
	Do after.%Next()
	Set written = after.%GetData(1) - rowsBefore
	Set recent = ##class(OcuTalon.Data.AddressCounter).Recent(address)
	Set quiet = 1
	Try {
		Do ##class(OcuTalon.Data.AddressCounter).Unlock(address)
	} Catch {
		Set quiet = 0
	}
	Set @$Name(^OcuTalonTest("AddressCounter", "closed", address)) = $ListBuild($SYSTEM.Status.IsError(sc), $SYSTEM.Status.GetErrorText(sc) '[ address, written, recent, quiet)
}

/// Puts the key node back as it was (present with its value, or absent) and lastReset to the saved marker.
ClassMethod RestoreKey(node As %String, existed As %Boolean, value As %String, marker As %String) [ Private ]
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("lastReset", marker)
	If existed {
		Set @node = value
	} Else {
		Kill @node
	}
}

/// The ids (comma-separated) of the counter rows of a hash.
ClassMethod IdsOf(hash As %String) As %String [ Private ]
{
	Set ids = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?", hash)
	While result.%Next() {
		Set ids = ids_$Select(ids = "": "", 1: ",")_result.%Get("ID")
	}
	Quit ids
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

/// Deletes the counter rows of every fixture address of every run, also those whose hash is a fixture hash in another case and those
/// stored as the address's plain SHA-256 (rows from before the key), and any row with no hash at all.
ClassMethod Clean() [ Private ]
{
	Kill fixtures
	Set max = $Get(^OcuTalonTest("AddressCounter", "n"))
	For n = 1:1:max {
		For case = "window", "other", "CASE", "case", "add", "purge", "purgeA", "purgeB", "purgeC", "legacy", "private", "reset", "busy", "once", "lockname" {
			Set address = "zz-counter-"_n_"-"_case
			Set hash = ##class(OcuTalon.Data.AddressCounter).AddressHash(address)
			If hash '= "" Set fixtures($ZConvert(hash, "U")) = ""
			Set fixtures($ZConvert(##class(OcuTalon.Data.Session).Hash(address), "U")) = ""
		}
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, AddressHash FROM OcuTalon_Data.AddressCounter")
	Kill ids
	While result.%Next() {
		Set hash = result.%Get("AddressHash")
		If (hash = "") || $Data(fixtures($ZConvert(hash, "U"))) Set ids(result.%Get("ID")) = ""
	}
	Set id = ""
	For {
		Set id = $Order(ids(id))
		Quit:id=""
		Do ##class(OcuTalon.Data.AddressCounter).%DeleteId(id)
	}
}

}
