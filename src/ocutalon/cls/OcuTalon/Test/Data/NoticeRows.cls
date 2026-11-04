/// Tests of the rows behind a tell-now notice's Got it (Story 33.2; AD-14, AD-33): OcuTalon.Data.Handled and Delivery.FindByRef. Safe on a
/// slot. The rows of the owners that are fixture sessions go with Test.Data.Fixture.Clean; the rows of the owners instance and eval, and the Handled
/// rows, which only this test makes, are deleted by it. The run's number is n from ^OcuTalonTest("NoticeRows","n") (never reset).
///   - TestHandledMarked: Marked gives the time of the row of a Ref and "" for a Ref that is not marked, for one that differs only in case and
///     for an empty one; a second row for a Ref is refused by the unique index;
///   - TestFindByRef: the newest row of the owner and channel whose DecisionRef is the Ref exactly is found, and no other owner's, channel's or
///     Ref's, a Ref in another case, the owners instance and eval, or an empty value;
///   - TestFindByRefAndByApprovalAreIndependent: a row found by its approval Ref is not found by that Ref as a notice Ref, and the other way round.
Class OcuTalon.Test.Data.NoticeRows Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The IDs of the Delivery rows of the owners instance and eval, comma-separated.
Property Strays As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("NoticeRows", "n"))
	Set ..Refs = ""
	Set ..Strays = ""
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	For i = 1:1:$Length(..Strays, ",") {
		If $Piece(..Strays, ",", i) '= "" Do ##class(OcuTalon.Data.Delivery).%DeleteId($Piece(..Strays, ",", i))
	}
	Do ##class(OcuTalon.Data.Handled).RefIndexDelete("ZzHandled"_..Number_"a")
	Do ##class(OcuTalon.Data.Handled).RefIndexDelete("ZzHandled"_..Number_"b")
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
}

/// Marked gives the HandledAt of the row of a Ref, and "" for a Ref with no row, a Ref in another case and an empty Ref.
Method TestHandledMarked()
{
	Set session = ..Session("handled")
	Set ref = "ZzHandled"_..Number_"a"
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).Marked(ref), "", "a notice that no one handled is not marked")
	Set row = ##class(OcuTalon.Data.Handled).%New()
	Set row.Ref = ref, row.SessionRef = session, row.HandledAt = "2030-04-05T06:07:08Z", row.Channel = "web"
	Do $$$AssertStatusOK(row.%Save(), "the row is saved")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).Marked(ref), "2030-04-05T06:07:08Z", "Marked gives when it was handled")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).Marked($ZConvert(ref, "L")), "", "a Ref in lower case is another Ref")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).Marked($ZConvert(ref, "U")), "", "and so is one in upper case")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).Marked(""), "", "an empty Ref is not marked")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).Marked("ZzHandled"_..Number_"zz"), "", "an unknown Ref is not marked")
	Set second = ##class(OcuTalon.Data.Handled).%New()
	Set second.Ref = ref, second.SessionRef = session, second.HandledAt = "2030-04-05T06:07:09Z", second.Channel = "phone"
	Do $$$AssertStatusNotOK(second.%Save(), "a second row for the Ref is refused by the unique index")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).Marked(ref), "2030-04-05T06:07:08Z", "and the first press stays")
	Set other = ##class(OcuTalon.Data.Handled).%New()
	Set other.Ref = "ZzHandled"_..Number_"b", other.SessionRef = session, other.HandledAt = "2030-04-05T06:07:10Z", other.Channel = "web"
	Do $$$AssertStatusOK(other.%Save(), "a different Ref has its own row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).Marked("ZzHandled"_..Number_"b"), "2030-04-05T06:07:10Z", "with its own time")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexOpen(ref).SessionRef_"|"_##class(OcuTalon.Data.Handled).RefIndexOpen(ref).Channel, session_"|web", "the row keeps the session and the channel")
}

/// FindByRef gives the ChannelMessageId of the newest row of the owner and channel whose DecisionRef is the Ref exactly.
Method TestFindByRef()
{
	Set session = ..Session("find")
	Set other = ..Session("findother")
	Set ref = "ZzN1"_..Number
	Do ##class(OcuTalon.Data.Delivery).Record(session, "telegram", "ZzOld:1", "", "tellnow", "", ref)
	Do ##class(OcuTalon.Data.Delivery).Record(session, "telegram", "ZzNew:2", "", "tellnow", "", ref)
	Do ##class(OcuTalon.Data.Delivery).Record(session, "phone", "ZzPhone", "", "tellnow", "", ref)
	Do ##class(OcuTalon.Data.Delivery).Record(session, "telegram", "ZzOtherNotice", "", "tellnow", "", "ZzN2"_..Number)
	Do ##class(OcuTalon.Data.Delivery).Record(other, "telegram", "ZzTheirs", "", "tellnow", "", ref)
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef(ref, "telegram", session), "ZzNew:2", "the newest row of the owner for the Ref and channel")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef(ref, "phone", session), "ZzPhone", "another channel finds its own row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef("ZzN2"_..Number, "telegram", session), "ZzOtherNotice", "another notice finds its own row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef(ref, "telegram", other), "ZzTheirs", "the other owner finds its own row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef(ref, "web", session), "", "a channel with no row finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef(ref, "web", other), "", "nor for the other owner")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef("ZzN3"_..Number, "telegram", session), "", "an unknown Ref finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef($ZConvert(ref, "L"), "telegram", session), "", "a Ref in another case finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef($ZConvert(ref, "U"), "telegram", session), "", "nor in upper case")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef(ref, "Telegram", session), "", "a channel in another case finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef(ref, "telegram", $ZConvert(session, "L")), "", "an owner in another case finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef(ref, "telegram", ##class(OcuTalon.Bridge.Ids).NewRef()), "", "an unknown owner finds nothing")
	For value = 1, 2, 3 {
		Set noticeRef = $Select(value = 1: "", 1: ref)
		Set channel = $Select(value = 2: "", 1: "telegram")
		Set owner = $Select(value = 3: "", 1: session)
		Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef(noticeRef, channel, owner), "", "an empty "_$Select(value = 1: "Ref", value = 2: "channel", 1: "owner")_" finds nothing")
	}
	For owner = "instance", "eval" {
		Set sc = ##class(OcuTalon.Data.Delivery).Record(owner, "telegram", "Zz"_owner_":9", "", "tellnow", "", ref, , , .stray)
		Do $$$AssertStatusOK(sc, "a row of the owner "_owner_" is recorded")
		If $IsObject($Get(stray)) Set ..Strays = ..Strays_","_stray.%Id()
		Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef(ref, "telegram", owner), "", "but the owner "_owner_" finds nothing")
		Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef(ref, "telegram", $ZConvert(owner, "U")), "", "nor in upper case")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef(ref, "telegram", session), "ZzNew:2", "and the session still finds its newest")
}

/// The approval Ref and the notice Ref are different columns: a row found by one is not found by the other.
Method TestFindByRefAndByApprovalAreIndependent()
{
	Set session = ..Session("indep")
	Do ##class(OcuTalon.Data.Delivery).Record(session, "telegram", "ZzApproval:1", "ZzAp"_..Number, "approval", "", "ZzDe"_..Number)
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef("ZzDe"_..Number, "telegram", session), "ZzApproval:1", "found by its decision Ref")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval("ZzAp"_..Number, "telegram", session), "ZzApproval:1", "and by its approval Ref")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef("ZzAp"_..Number, "telegram", session), "", "the approval Ref is not a notice Ref")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval("ZzDe"_..Number, "telegram", session), "", "nor the notice Ref an approval Ref")
}

/// --- helpers ---
/// A fixture session; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zznot"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

}
