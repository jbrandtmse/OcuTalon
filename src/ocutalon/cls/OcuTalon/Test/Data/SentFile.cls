/// Tests of OcuTalon.Data.SentFile, the table of the files that a person sent (Story 25.3; AD-3, AD-4, AD-27). The rows are made for the SessionRefs ZzSentFileA
/// and ZzSentFileB and removed before each test and after the tests.
///   - TestPut: Put stores the bytes, the name, the media type, the channel and the size, and returns a Ref; Core.Files.Open gives exactly the bytes back;
///   - TestOwnerScoped: Ownership.SentFile finds a row only for its own session, matches the Ref exactly (a case variant is not found) and answers "" for an empty Ref;
///   - TestDropSession: DropSession deletes every row of the session and no other session's, and a call with no SessionRef deletes nothing; Drop deletes one
///     row of the session and leaves another session's row with the same Ref alone;
///   - TestPurgeBoundary: Purge deletes the rows made before now minus daysToKeep days and a row with no time, keeps a row exactly that old and every younger one; its now
///     is in January 2000, so no row that the test did not make (Put always sets CreatedAt) is old enough to be deleted;
///   - TestRegistry: the table sets the DEFAULTGLOBAL of its src/short-names.tsv row, stores its data, index and stream in that global's family and has them in the private
///     database (Test.Data.Tables pins the row itself).
Class OcuTalon.Test.Data.SentFile Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Do ..DeleteFixtures()
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Do ..DeleteFixtures()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..DeleteFixtures()
	Quit $SYSTEM.Status.OK()
}

Method TestPut()
{
	Set bytes = ..Bytes("%PDF-1.4 zz put")
	Set ref = ##class(OcuTalon.Data.SentFile).Put("ZzSentFileA", "telegram", "put.pdf", "application/pdf", bytes, .sc)
	Do $$$AssertStatusOK(sc, "Put stores the file")
	Do $$$AssertEquals($Length(ref), 22, "Put returns a Ref of 22 characters")
	Set row = ##class(OcuTalon.Data.SentFile).RefIndexOpen(ref)
	Do $$$AssertEquals(row.SessionRef_"|"_row.Channel_"|"_row.Name_"|"_row.MediaType_"|"_row.Size, "ZzSentFileA|telegram|put.pdf|application/pdf|15", "the row holds the session, channel, name, media type and size")
	Do $$$AssertTrue(row.CreatedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "CreatedAt is a UTC time")
	Set opened = ##class(OcuTalon.Core.Files).Open(ref, "ZzSentFileA", .sc)
	Do $$$AssertStatusOK(sc, "Open reads")
	Do $$$AssertEquals(opened.Read(100), "%PDF-1.4 zz put", "Open gives exactly the bytes")
}

Method TestOwnerScoped()
{
	Set ref = ..Add("ZzSentFileA", "own.pdf")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).SentFile(ref, "ZzSentFileA").Ref, ref, "the owner finds its file")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).SentFile(ref, "ZzSentFileB"), "", "another session does not find it")
	Set variant = $Translate(ref, "abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
	If variant '= ref Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).SentFile(variant, "ZzSentFileA"), "", "a case variant of the Ref is not found")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).SentFile("", "ZzSentFileA"), "", "an empty Ref finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Open(ref, "ZzSentFileB"), "", "Open of another session's file finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Describe(ref, "ZzSentFileB"), "", "Describe of another session's file finds nothing")
}

Method TestDropSession()
{
	Set a1 = ..Add("ZzSentFileA", "a1.pdf"), a2 = ..Add("ZzSentFileA", "a2.pdf"), b1 = ..Add("ZzSentFileB", "b1.pdf")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.SentFile).DropSession(""), "a call with no SessionRef is OK")
	Do $$$AssertEquals(..Count("ZzSentFileA")_"|"_..Count("ZzSentFileB"), "2|1", "a call with no SessionRef deletes nothing")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.SentFile).Drop(a1, "ZzSentFileB"), "Drop with another session's SessionRef is OK")
	Do $$$AssertEquals(..Count("ZzSentFileA"), 2, "and deletes nothing")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.SentFile).Drop(a1, "ZzSentFileA"), "Drop of the session's file")
	Do $$$AssertEquals(..Count("ZzSentFileA")_"|"_##class(OcuTalon.Data.SentFile).RefIndexExists(a1), "1|0", "deletes that file only")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.SentFile).DropSession("ZzSentFileA"), "DropSession")
	Do $$$AssertEquals(..Count("ZzSentFileA")_"|"_..Count("ZzSentFileB"), "0|1", "deletes the session's files and no other session's")
	Do $$$AssertTrue(##class(OcuTalon.Data.SentFile).RefIndexExists(b1), "the other session's file is still there")
	Do $$$AssertTrue('##class(OcuTalon.Data.SentFile).RefIndexExists(a2), "the session's second file is gone")
}

Method TestPurgeBoundary()
{
	Set now = "2000-01-31T12:00:00Z"
	Set old = ..Add("ZzSentFileA", "old.pdf", "2000-01-01T11:59:59Z")
	Set edge = ..Add("ZzSentFileA", "edge.pdf", "2000-01-01T12:00:00Z")
	Set young = ..Add("ZzSentFileA", "young.pdf", "2000-01-31T11:00:00Z")
	Set none = ..Add("ZzSentFileB", "none.pdf", "")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.SentFile).Purge(30, now), "Purge")
	Do $$$AssertEquals(+##class(OcuTalon.Data.SentFile).RefIndexExists(old), 0, "a row more than 30 days old is deleted")
	Do $$$AssertEquals(+##class(OcuTalon.Data.SentFile).RefIndexExists(none), 0, "a row with no time is deleted")
	Do $$$AssertEquals(+##class(OcuTalon.Data.SentFile).RefIndexExists(edge), 1, "a row exactly 30 days old is kept")
	Do $$$AssertEquals(+##class(OcuTalon.Data.SentFile).RefIndexExists(young), 1, "a younger row is kept")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Data.SentFile).Purge(30, "not a time"), "an unreadable time is an error")
}

Method TestRegistry()
{
	Set private = ##class(%SYS.Namespace).GetGlobalDest($Namespace, "^OcuTalonP.Zz")
	Set class = "OcuTalon.Data.SentFile"
	Do $$$AssertEquals($Parameter(class, "DEFAULTGLOBAL"), "^OcuTalonP.SentFile", "the class sets DEFAULTGLOBAL")
	Set compiled = ##class(%Dictionary.CompiledStorage).%OpenId(class_"||Default")
	Do $$$AssertEquals(compiled.DataLocation, "^OcuTalonP.SentFileD", "data in ^OcuTalonP.SentFileD")
	Do $$$AssertEquals(compiled.StreamLocation, "^OcuTalonP.SentFileS", "streams in ^OcuTalonP.SentFileS")
	For location = compiled.DataLocation, compiled.IndexLocation, compiled.StreamLocation {
		Do $$$AssertEquals(##class(%SYS.Namespace).GetGlobalDest($Namespace, location), private, location_" resolves to the private database")
	}
}

/// Stores a row for the session and returns its Ref; createdAt, when given (an empty one too), replaces the time of the row.
Method Add(session As %String, name As %String, createdAt As %String = "<now>") As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Data.SentFile).Put(session, "web", name, "application/pdf", ..Bytes("%PDF-1.4 zz"), .sc)
	Do $$$AssertStatusOK(sc, name_" is stored")
	If createdAt '= "<now>" {
		Set row = ##class(OcuTalon.Data.SentFile).RefIndexOpen(ref)
		Set row.CreatedAt = createdAt
		Do $$$AssertStatusOK(row.%Save(), name_" is dated")
	}
	Quit ref
}

Method Bytes(text As %String) As %Stream.TmpBinary [ Private ]
{
	Set bytes = ##class(%Stream.TmpBinary).%New()
	Do bytes.Write(text)
	Do bytes.Rewind()
	Quit bytes
}

Method Count(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SentFile WHERE SessionRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

Method DeleteFixtures() [ Private ]
{
	Do ##class(OcuTalon.Data.SentFile).DropSession("ZzSentFileA")
	Do ##class(OcuTalon.Data.SentFile).DropSession("ZzSentFileB")
}

}
