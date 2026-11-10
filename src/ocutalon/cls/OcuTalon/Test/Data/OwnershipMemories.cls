/// Tests of the three memory reads of OcuTalon.Data.Ownership, Memories, Memory and MemoryTotal (Story 41.9; AD-4, AD-13, AD-21). Safe on a slot: no production is needed. The sessions
/// are fixture rows and the Data.Memory rows are saved directly with no vector (the reads open rows and never embed); every test removes its own by Ref.
///   - TestIsolation: two sessions read none of each other's memories through the list, the count or a direct Ref; the list is newest SavedAt first;
///   - TestRefusals: the three kinds refuse an empty owner and the owners eval and instance, through Test.Data.OwnershipProbe.Call and the public reads, and an unknown kind
///     and a kind that is SQL text are refused too;
///   - TestBounds: Memories returns at most max rows, the newest, and rows with one SavedAt come later-saved first;
///   - TestRefIsOnlyBound: a Ref that is SQL text, or differs only in letter case, finds nothing.
Class OcuTalon.Test.Data.OwnershipMemories Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The count of sessions made.
Property Count As %Integer [ InitialExpression = 0 ];

/// The Refs of the fixture sessions of the test, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the Data.Memory rows of the test, comma-separated.
Property Rows As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("OwnershipMemories", "n"))
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Rows, ",") {
		Set ref = $Piece(..Rows, ",", i)
		If ref '= "" {
			Set row = ##class(OcuTalon.Data.Memory).RefIndexOpen(ref)
			If $IsObject(row) Do ##class(OcuTalon.Data.Memory).%DeleteId(row.%Id())
		}
	}
	Set ..Rows = ""
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Quit $$$OK
}

/// Sessions A and B each own memories; each lists, counts and finds only its own, newest first, and a find with the other's Ref answers "".
Method TestIsolation()
{
	Set a = ..Session("a"), b = ..Session("b")
	Set a1 = ..Make(a, "2030-01-01T10:00:00Z"), a2 = ..Make(a, "2030-01-02T10:00:00Z")
	Set b1 = ..Make(b, "2030-01-03T10:00:00Z")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).Memories(a, , .sc)), a2_","_a1, "A lists its own memories, newest first")
	Do $$$AssertStatusOK(sc, "the list is OK")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).Memories(b)), b1, "B lists its own memory, and none of A's")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).MemoryTotal(a, .sc), 2, "A's count is its own two")
	Do $$$AssertStatusOK(sc, "the count is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).MemoryTotal(b), 1, "B's count is its own one")
	Set found = ##class(OcuTalon.Data.Ownership).Memory(a1, a, .sc)
	Do $$$AssertEquals(found.Ref, a1, "A finds its own memory by its Ref")
	Do $$$AssertStatusOK(sc, "the find is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Memory(a1, b, .sc), "", "B does not find A's memory by its Ref")
	Do $$$AssertStatusOK(sc, "and the read is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Memory(b1, a), "", "A does not find B's memory by its Ref")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Memory(a1 _ "x", a), "", "a Ref that names nothing is not found")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Memory("", a), "", "an empty Ref is not found")
	Set rows = ##class(OcuTalon.Data.Ownership).Memories(##class(OcuTalon.Bridge.Ids).NewRef(), , .sc)
	Do $$$AssertEquals(rows.Count(), 0, "a session with no memory lists none")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).MemoryTotal("zznosuchsession"_..Number, .sc), 0, "and counts none")
	Do $$$AssertStatusOK(sc, "(a missing session is not an error)")
}

/// Each kind refuses an empty owner and the owners eval and instance (in any case and with trailing blanks) with an error status and no rows; the public reads do the same for
/// an empty SessionRef, and an unknown kind and a kind that is SQL text are refused.
Method TestRefusals()
{
	Set probe = "OcuTalon.Test.Data.OwnershipProbe"
	Set a = ..Session("refuse")
	Set mine = ..Make(a, "2030-01-01T10:00:00Z")
	For kind = "memories", "memory", "memoryTotal" {
		Set argument = $Case(kind, "memories": 20, "memory": mine, : "")
		For owner = "", "eval", "instance", "EVAL", "Instance", "eval ", "EVAL  " {
			Set rows = $ClassMethod(probe, "Call", kind, owner, .sc, argument)
			Do $$$AssertStatusNotOK(sc, kind_": '"_owner_"' is not a session's Ref")
			Do $$$AssertEquals(rows.Count(), 0, kind_": with no rows")
		}
	}
	Set rows = $ClassMethod(probe, "Call", "memories", a, .sc, 20)
	Do $$$AssertStatusOK(sc, "a session's Ref is accepted")
	Do $$$AssertEquals(rows.Count(), 1, "and gives its memory")
	Set rows = $ClassMethod(probe, "Call", "memoryTotal", a, .sc)
	Do $$$AssertEquals(rows.Count()_"|"_rows.GetAt(1).total, "1|1", "the count kind gives one row, {total}, and no memory is opened")
	For kind = "zzkind", "memories' OR '1'='1" {
		Set rows = $ClassMethod(probe, "Call", kind, a, .sc, 20)
		Do $$$AssertStatusNotOK(sc, "'"_kind_"' is not a kind of row")
		Do $$$AssertEquals(rows.Count(), 0, "with no rows")
	}
	Set rows = ##class(OcuTalon.Data.Ownership).Memories("", 20, .sc)
	Do $$$AssertStatusNotOK(sc, "Memories with an empty SessionRef is an error")
	Do $$$AssertEquals(rows.Count(), 0, "and reads no row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).MemoryTotal("", .sc), 0, "MemoryTotal with an empty SessionRef counts none")
	Do $$$AssertStatusNotOK(sc, "and says why")
	Set found = ##class(OcuTalon.Data.Ownership).Memory(mine, "", .sc)
	Do $$$AssertEquals(found, "", "Memory with an empty SessionRef finds nothing")
	Do $$$AssertStatusNotOK(sc, "and says why")
	For owner = "eval", "instance" {
		Set rows = ##class(OcuTalon.Data.Ownership).Memories(owner, 20, .sc)
		Do $$$AssertEquals(rows.Count(), 0, "Memories for the owner "_owner_" reads no row")
		Do $$$AssertStatusNotOK(sc, "and says why")
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).MemoryTotal(owner, .sc), 0, "MemoryTotal for the owner "_owner_" counts none")
		Do $$$AssertStatusNotOK(sc, "and says why")
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Memory(mine, owner, .sc), "", "Memory for the owner "_owner_" finds nothing")
		Do $$$AssertStatusNotOK(sc, "and says why")
	}
}

/// Memories returns at most max rows, the newest, and the count is the whole count.
Method TestBounds()
{
	Set a = ..Session("bounds")
	For i = 1:1:4 {
		Set ref(i) = ..Make(a, "2030-01-0"_i_"T10:00:00Z")
	}
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).Memories(a, 2)), ref(4)_","_ref(3), "max 2: the two newest")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).Memories(a, 100)), ref(4)_","_ref(3)_","_ref(2)_","_ref(1), "max 100: all four")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).MemoryTotal(a), 4, "and the count is four whatever max is")
	Set b = ..Session("ties")
	Set tie(1) = ..Make(b, "2030-02-01T10:00:00Z"), tie(2) = ..Make(b, "2030-02-01T10:00:00Z"), tie(3) = ..Make(b, "2030-02-01T10:00:00Z")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).Memories(b)), tie(3)_","_tie(2)_","_tie(1), "rows saved with one SavedAt come newest first (the later-saved row first)")
}

/// A Ref is only a bound value: SQL text in it finds nothing, and a Ref that differs only in letter case is not the row (Data.Memory Ref is case-sensitive).
Method TestRefIsOnlyBound()
{
	Set a = ..Session("bound")
	Set mine = ..Make(a, "2030-01-01T10:00:00Z")
	Do ..Make(a, "2030-01-02T10:00:00Z")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Memory("x' OR '1'='1", a, .sc), "", "a Ref that is SQL text finds nothing")
	Do $$$AssertStatusOK(sc, "and the read is OK")
	Set variant = $ZConvert(mine, "L")
	If variant = mine Set variant = $ZConvert(mine, "U")
	Do $$$AssertNotEquals(variant, mine, "control: the Ref in another letter case differs")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Memory(variant, a), "", "a Ref in another letter case is not found")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Memory(mine, a).Ref, mine, "control: the exact Ref is found")
}

/// --- helpers ---
/// A fixture session, recorded for the clean-up. Returns its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Set ..Count = ..Count + 1
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzownmem"_..Number_name_..Count)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// Saves a Data.Memory row of the owner and records it for the clean-up. Returns its Ref.
Method Make(owner As %String, savedAt As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Memory).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = owner
	Set row.Text = "zz memory of "_owner
	Set row.SavedAt = savedAt
	Set row.ItemId = "zzownmem"
	Set row.Origin = "tool"
	Do $$$AssertStatusOK(row.%Save(), "a fixture memory is saved")
	Set ..Rows = ..Rows_$Select(..Rows = "": "", 1: ",")_row.Ref
	Quit row.Ref
}

/// The Refs of the rows of a list, comma-separated.
Method RefsOf(rows As %ListOfObjects) As %String [ Private ]
{
	Set text = ""
	For i = 1:1:rows.Count() {
		Set text = text_$Select(text = "": "", 1: ",")_rows.GetAt(i).Ref
	}
	Quit text
}

}
