/// Tests of the sign-out deletion of a session's memories (Story 19.5; AD-4, AD-21): OcuTalon.Memory.DropSession. Each test makes its own memories for zz-
/// sessions (a SessionRef string needs no Session row) and removes them. THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), on OcuTalon's Docker image: the
/// memories are embedded by the Embedder worker, and they skip elsewhere.
///   - TestDropsOnlyTheSession: the session's memories are gone, from the table and from the search and the list, and another session's stay, found by their
///     search and listed; a second DropSession is OK and changes nothing; an unknown reference and an empty one are OK and change nothing;
///   - TestLockHeld: while another job holds the lock that MemoryOps takes for the session (^OcuTalon.Memory(<session>)), DropSession returns an error status after
///     the 5 seconds of the lock and deletes nothing; once the lock is free it deletes.
Class OcuTalon.Test.Memory.Drop Extends %UnitTest.TestCase
{

Parameter A = "zz-mem-drop-a";

Parameter B = "zz-mem-drop-b";

/// What Fixture.Prepare changed (the worker category and the embedding config), put back in OnAfterAllTests.
Property State As %String [ MultiDimensional ];

Method OnBeforeAllTests() As %Status
{
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit $$$OK
	Set sc = ##class(OcuTalon.Test.Memory.Fixture).Prepare(.state)
	Merge ..State = state
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Merge state = ..State
	If $Data(state) Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
	Quit $$$OK
}

/// Deletes the test's memories, with their index entries.
ClassMethod Clean() [ Private ]
{
	Kill ^IRIS.Temp.ZzMemDrop
	Do ##class(OcuTalon.Test.Memory.Fixture).Purge("zz-mem-drop")
}

/// 1 on the image; otherwise records the skip.
Method OnImage() As %Boolean [ Private ]
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit 1
	Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
	Quit 0
}

/// Stores the memories of the two sessions: three for A and two for B, each with the vector that the product's endpoint gives for its text.
Method Seed() [ Private ]
{
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzMemDropA000000000001", "the Results partner's contact is Lee", now), "A's first memory")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzMemDropA000000000002", "the build server is called ORION-7", now), "A's second")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#A, "zzMemDropA000000000003", "the nightly backup runs at two", now), "A's third")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#B, "zzMemDropB000000000001", "the Results partner's contact is Kim", now), "B's first memory")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(..#B, "zzMemDropB000000000002", "the build server is called ATLAS-2", now), "B's second")
}

/// The number of memories of the session in the table.
ClassMethod Rows(session As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Memory WHERE SessionRef = ?", session)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// The memoryRefs that Search returns for the session, comma-separated, and the Refs that List returns, separated from them by a slash.
ClassMethod Found(session As %String) As %String [ Private ]
{
	Set searched = ""
	Set sc = ##class(OcuTalon.Memory).Search(session, "who is the Results partner contact", 5, .rows)
	If $$$ISOK(sc) {
		For i = 0:1:rows.%Size() - 1 {
			Set searched = searched _ $Select(searched = "": "", 1: ",") _ rows.%Get(i).memoryRef
		}
	}
	Set listed = ""
	Set sc = ##class(OcuTalon.Memory).List(session, .items, .total)
	If $$$ISOK(sc) {
		For i = 0:1:items.%Size() - 1 {
			Set listed = listed _ $Select(listed = "": "", 1: ",") _ items.%Get(i).memoryRef
		}
	}
	Quit searched _ "/" _ listed
}

Method TestDropsOnlyTheSession()
{
	If '..OnImage() Quit
	Do ..Seed()
	Do $$$AssertEquals(..Rows(..#A) _ "|" _ ..Rows(..#B), "3|2", "control: three memories of A and two of B")
	Do $$$AssertTrue($Piece(..Found(..#A), "/", 1) [ "zzMemDropA", "control: a search finds A's memories")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).DropSession(..#A), "DropSession(A) is OK")
	Do $$$AssertEquals(..Rows(..#A) _ "|" _ ..Rows(..#B), "0|2", "A's memories are gone and B's stay")
	Do $$$AssertEquals(..Found(..#A), "/", "a search and the list find none of A's")
	Set found = ..Found(..#B)
	Do $$$AssertTrue(($Piece(found, "/", 1) [ "zzMemDropB000000000001") && ($Piece(found, "/", 1) '[ "zzMemDropA"), "B's search finds B's memory and none of A's: " _ found)
	Do $$$AssertEquals($Length($Piece(found, "/", 2), ","), 2, "and B's list holds both")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).DropSession(..#A), "a second DropSession(A) is OK")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).DropSession("zz-mem-drop-unknown"), "so is an unknown reference")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).DropSession(""), "and an empty one")
	Do $$$AssertEquals(..Rows(..#A) _ "|" _ ..Rows(..#B), "0|2", "none of them changes a row")
}

Method TestLockHeld()
{
	If '..OnImage() Quit
	Do ..Seed()
	Kill ^IRIS.Temp.ZzMemDrop
	Job ##class(OcuTalon.Test.Memory.Drop).Hold(..#A, 12)
	Set deadline = $ZHorolog + 20
	While '$Data(^IRIS.Temp.ZzMemDrop("held")) && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Do $$$AssertEquals($Get(^IRIS.Temp.ZzMemDrop("held")), 1, "another job holds the lock of the session")
	Set began = $ZHorolog
	Set sc = ##class(OcuTalon.Memory).DropSession(..#A)
	Set waited = $ZHorolog - began
	Do $$$AssertStatusNotOK(sc, "DropSession returns an error status")
	Do $$$AssertTrue(waited '< 4.5, "after the lock's 5 seconds: " _ waited)
	Do $$$AssertEquals(..Rows(..#A), 3, "and deletes nothing")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "busy", "the error says that the memories are busy: " _ $SYSTEM.Status.GetErrorText(sc))
	Set deadline = $ZHorolog + 30
	While '$Data(^IRIS.Temp.ZzMemDrop("done")) && ($ZHorolog < deadline) {
		Hang 0.2
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).DropSession(..#A), "once the lock is free DropSession is OK")
	Do $$$AssertEquals(..Rows(..#A) _ "|" _ ..Rows(..#B), "0|2", "and deletes A's memories only")
}

/// The job body of TestLockHeld: holds the lock of MemoryOps for the session for the seconds, and notes it.
ClassMethod Hold(session As %String, seconds As %Integer)
{
	Lock +^OcuTalon.Memory(session):5
	Set ^IRIS.Temp.ZzMemDrop("held") = $Test
	Hang seconds
	Lock -^OcuTalon.Memory(session)
	Set ^IRIS.Temp.ZzMemDrop("done") = 1
}

}
