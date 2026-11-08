/// Tests of the two precedent reads of OcuTalon.Data.Ownership, Precedents and Precedent (Story 41.2; AD-4, AD-13, AD-21). Safe on a slot: no production is
/// needed. The sessions are fixture rows and the Precedent rows are saved directly; every test removes its own by Ref.
///   - TestIsolation: two sessions read none of each other's rows through either kind, and a row answers in the order newest first;
///   - TestSeededRowsAreInvisible: a seeded row (owner eval) and a row of a session that has an EvalRunRef are never read, through either kind;
///   - TestRefusals: both kinds refuse an empty owner and the owners eval and instance, through Test.Data.OwnershipProbe.Call and the public reads;
///   - TestBounds: Precedents returns at most max rows.
Class OcuTalon.Test.Data.OwnershipPrecedents Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The count of sessions made.
Property Count As %Integer [ InitialExpression = 0 ];

/// The Refs of the fixture rows of the test, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the Precedent rows of the test, comma-separated.
Property Rows As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("OwnershipPrecedents", "n"))
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Rows, ",") {
		Set ref = $Piece(..Rows, ",", i)
		If ref '= "" {
			Set row = ##class(OcuTalon.Data.Precedent).RefIndexOpen(ref)
			If $IsObject(row) Do ##class(OcuTalon.Data.Precedent).%DeleteId(row.%Id())
		}
	}
	Set ..Rows = ""
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Quit $$$OK
}

/// Sessions A and B each own rows; each reads only its own, newest answer first, and a find with the other's Ref answers "".
Method TestIsolation()
{
	Set a = ..Session("a"), b = ..Session("b")
	Set a1 = ..Make(a, "2030-01-01T10:00:00Z"), a2 = ..Make(a, "2030-01-02T10:00:00Z")
	Set b1 = ..Make(b, "2030-01-03T10:00:00Z")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).Precedents(a, , .sc)), a2_","_a1, "A reads its own rows, newest first")
	Do $$$AssertStatusOK(sc, "the read is OK")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).Precedents(b)), b1, "B reads its own row")
	Set found = ##class(OcuTalon.Data.Ownership).Precedent(a1, a, .sc)
	Do $$$AssertEquals(found.Ref, a1, "A finds its own row by its Ref")
	Do $$$AssertStatusOK(sc, "the find is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Precedent(a1, b, .sc), "", "B does not find A's row")
	Do $$$AssertStatusOK(sc, "and the read is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Precedent(b1, a), "", "A does not find B's row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Precedent(a1 _ "x", a), "", "a Ref that names nothing is not found")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Precedent("", a), "", "an empty Ref is not found")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Precedent($ZConvert(a1, "U"), a), "", "a Ref in another letter case is not found")
}

/// A seeded row has the owner eval, and a row that has an EvalRunRef is never a session's; neither is listed or found for a session.
Method TestSeededRowsAreInvisible()
{
	Set a = ..Session("seeded")
	Set mine = ..Make(a, "2030-01-01T10:00:00Z")
	Set seeded = ..Make("eval", "2030-01-02T10:00:00Z", "zzrun")
	Set odd = ..Make(a, "2030-01-03T10:00:00Z", "zzrun")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).Precedents(a)), mine, "A lists only its own unseeded row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Precedent(seeded, a), "", "A does not find a seeded row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Precedent(odd, a), "", "A does not find its own row that has an EvalRunRef")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Precedent(mine, a).Ref, mine, "A finds its own unseeded row")
}

/// Both kinds refuse an empty owner and the owners eval and instance (in any case and with trailing blanks) with an error status and no rows; the public reads
/// do the same for an empty SessionRef.
Method TestRefusals()
{
	Set probe = "OcuTalon.Test.Data.OwnershipProbe"
	Set a = ..Session("refuse")
	Set mine = ..Make(a, "2030-01-01T10:00:00Z")
	Set seeded = ..Make("eval", "2030-01-02T10:00:00Z", "zzrun")
	For kind = "precedents", "precedent" {
		Set argument = $Select(kind = "precedents": 100, 1: seeded)
		For owner = "", "eval", "instance", "EVAL", "Instance", "eval ", "EVAL  " {
			Set rows = $ClassMethod(probe, "Call", kind, owner, .sc, argument)
			Do $$$AssertStatusNotOK(sc, kind_": '"_owner_"' is not a session's Ref")
			Do $$$AssertEquals(rows.Count(), 0, kind_": with no rows")
		}
	}
	Set rows = $ClassMethod(probe, "Call", "precedents", a, .sc, 100)
	Do $$$AssertStatusOK(sc, "a session's Ref is accepted")
	Do $$$AssertEquals(rows.Count(), 1, "and gives its row")
	Set rows = ##class(OcuTalon.Data.Ownership).Precedents("", 100, .sc)
	Do $$$AssertStatusNotOK(sc, "Precedents with an empty SessionRef is an error")
	Do $$$AssertEquals(rows.Count(), 0, "and reads no row")
	Set found = ##class(OcuTalon.Data.Ownership).Precedent(mine, "", .sc)
	Do $$$AssertEquals(found, "", "Precedent with an empty SessionRef finds nothing")
	Do $$$AssertStatusNotOK(sc, "and says why")
	For owner = "eval", "instance" {
		Set found = ##class(OcuTalon.Data.Ownership).Precedent(seeded, owner, .sc)
		Do $$$AssertEquals(found, "", "Precedent for the owner "_owner_" finds nothing")
		Do $$$AssertStatusNotOK(sc, "and says why")
	}
}

/// Precedents returns at most max rows, the newest.
Method TestBounds()
{
	Set a = ..Session("bounds")
	For i = 1:1:4 {
		Set ref(i) = ..Make(a, "2030-01-0"_i_"T10:00:00Z")
	}
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).Precedents(a, 2)), ref(4)_","_ref(3), "max 2: the two newest")
	Do $$$AssertEquals(..RefsOf(##class(OcuTalon.Data.Ownership).Precedents(a, 100)), ref(4)_","_ref(3)_","_ref(2)_","_ref(1), "max 100: all four")
}

/// --- helpers ---
/// A fixture session, recorded for the clean-up. Returns its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Set ..Count = ..Count + 1
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzownprec"_..Number_name_..Count)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// Saves a Precedent row of the owner and records it for the clean-up. Returns its Ref. A run Ref sets EvalRunRef.
Method Make(owner As %String, answeredAt As %String, run As %String = "") As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Precedent).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = owner
	Set row.Channel = "mailbox"
	Set row.MatchKey = "zz.ownprec@example.com"
	Set row.Summary = "zz summary"
	Set row.Outcome = "tellnow"
	Set row.Answer = "noise"
	Set row.AnsweredAt = answeredAt
	Set row.SourceRef = row.Ref
	Set row.EvalRunRef = run
	Do $$$AssertStatusOK(row.%Save(), "a fixture row is saved")
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
