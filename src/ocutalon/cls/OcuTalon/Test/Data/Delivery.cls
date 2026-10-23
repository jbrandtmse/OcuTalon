/// Tests of OcuTalon.Data.Delivery (Story 2.7; AD-14, AD-33; DW-62): Record keeps a web card with its kind, text, decision, due
/// time and fallback reason, and refuses an empty owner and a channel outside Msg.Enum CHANNEL; FindByApproval finds the owner's
/// newest row by the approval Ref and channel exactly, and nobody else's. Safe on a slot. The rows of the owners that are
/// fixture sessions go with Test.Data.Fixture.Clean; the rows of the owners instance and eval, which only this test makes, are
/// deleted by it. The run's number is n from ^OcuTalonTest("Delivery","n") (never reset).
///   - TestRecordKeepsTheCard: every property of the row, RecordedAt to the second in UTC, and the four leading parameters alone;
///   - TestRecordRefuses: an empty owner and a channel that is not one of the eight, with no row;
///   - TestFindByApproval: an exact match, the newest of two, another owner, another channel, a case-changed Ref, the owners
///     instance and eval, and empty values.
Class OcuTalon.Test.Data.Delivery Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The IDs of the rows of the owners instance and eval, comma-separated.
Property Strays As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("Delivery", "n"))
	Set ..Refs = ""
	Set ..Strays = ""
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	For i = 1:1:$Length(..Strays, ",") {
		If $Piece(..Strays, ",", i) '= "" Do ##class(OcuTalon.Data.Delivery).%DeleteId($Piece(..Strays, ",", i))
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
}

/// Record saves one row with every given value, RecordedAt the time now (UTC to the second) and the row it saved as its output.
/// With the four leading parameters alone the kind, text, decision, due time and fallback reason are empty.
Method TestRecordKeepsTheCard()
{
	Set session = ..Session("record")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = ##class(OcuTalon.Data.Delivery).Record(session, "web", "ZzCard"_..Number, "ZzApproval"_..Number, "reminder", "Reminder: stretch."_$Char(10)_"second line", "ZzDecision"_..Number, "2030-02-03T04:05:06Z", "refusal", .row)
	Do $$$AssertStatusOK(sc, "the card is recorded")
	Do $$$AssertTrue($IsObject(row) && (row.%Id() '= ""), "the saved row is the output")
	Set found = ##class(OcuTalon.Data.Delivery).%OpenId(row.%Id())
	Do $$$AssertEquals(found.OwnerRef_"|"_found.Channel_"|"_found.ChannelMessageId_"|"_found.ApprovalRef, session_"|web|ZzCard"_..Number_"|ZzApproval"_..Number, "the owner, channel, ChannelMessageId and approval Ref")
	Do $$$AssertEquals(found.Kind_"|"_found.DecisionRef_"|"_found.DueAt_"|"_found.FallbackReason, "reminder|ZzDecision"_..Number_"|2030-02-03T04:05:06Z|refusal", "the kind, decision, due time and fallback reason")
	Do $$$AssertEquals(found.Text, "Reminder: stretch."_$Char(10)_"second line", "the whole text")
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertTrue(found.RecordedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "RecordedAt is UTC to the second: "_found.RecordedAt)
	Do $$$AssertTrue((found.RecordedAt '] before) && (after '] found.RecordedAt), "and is the time of the call")
	Set long = $Translate($Justify("", 5000), " ", "x")
	Set sc = ##class(OcuTalon.Data.Delivery).Record(session, "web", "ZzLong"_..Number, "", "tellnow", long, , , , .long2)
	Do $$$AssertStatusOK(sc, "a text of 5000 characters is recorded")
	Do $$$AssertEquals($Length(##class(OcuTalon.Data.Delivery).%OpenId(long2.%Id()).Text), 5000, "whole")

	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(session, "telegram", "ZzChat:7", "ZzApproval2"), "the four leading parameters record a row")
	Set rows = ..RowsOf(session, "telegram")
	Do $$$AssertEquals(rows.Count(), 1, "one row")
	If rows.Count() = 1 {
		Set row = rows.GetAt(1)
		Do $$$AssertEquals(row.ChannelMessageId_"|"_row.ApprovalRef_"|"_row.Kind_"|"_row.Text_"|"_row.DecisionRef_"|"_row.DueAt_"|"_row.FallbackReason, "ZzChat:7|ZzApproval2|||||", "with the rest empty")
	}
	For channel = "web", "phone", "mailbox", "telegram", "email", "webhook", "slack", "system" {
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(session, channel, "ZzCh"_channel_..Number, ""), "the channel "_channel_" is recorded")
	}
	Set sc = ##class(OcuTalon.Data.Delivery).Record("instance", "web", "ZzInst"_..Number, "", , , , , , .inst)
	Do $$$AssertStatusOK(sc, "the owner instance is recorded too")
	If $IsObject($Get(inst)) Set ..Strays = ..Strays_","_inst.%Id()
}

/// Record refuses an empty owner and a channel that is not one of Msg.Enum CHANNEL (any other text, an empty one, a different
/// case), with an error status, no row and "" as the output row.
Method TestRecordRefuses()
{
	Set session = ..Session("refuse")
	Set count = ..Count(session)
	Set sc = ##class(OcuTalon.Data.Delivery).Record("", "web", "ZzNoOwner", "", , , , , , .row)
	Do $$$AssertStatusNotOK(sc, "an empty owner is an error")
	Do $$$AssertEquals($IsObject(row), 0, "with no row")
	For channel = "", "zz", "WEB", "Web", "web ", "chat" {
		Kill row
		Set sc = ##class(OcuTalon.Data.Delivery).Record(session, channel, "ZzBad", "", , , , , , .row)
		Do $$$AssertStatusNotOK(sc, "the channel '"_channel_"' is an error")
		Do $$$AssertEquals($IsObject($Get(row)), 0, "the channel '"_channel_"': no row")
	}
	Do $$$AssertEquals(..Count(session), count, "no row of the session was recorded")
}

/// FindByApproval gives the ChannelMessageId of the newest row of the owner whose approval Ref and channel match exactly. Two
/// rows for (A1, telegram, S) give the newer; another owner's row for the same Ref and channel, a row of another channel and a
/// row of another approval are never found; a Ref that differs only in case is not found, whatever the owner's case; the owners
/// instance and eval, an empty value and an unknown Ref give "".
Method TestFindByApproval()
{
	Set session = ..Session("find")
	Set other = ..Session("findother")
	Set approval = "ZzA1"_..Number
	Do ##class(OcuTalon.Data.Delivery).Record(session, "telegram", "ZzOld:1", approval)
	Do ##class(OcuTalon.Data.Delivery).Record(session, "telegram", "ZzNew:2", approval)
	Do ##class(OcuTalon.Data.Delivery).Record(session, "phone", "ZzPhone", approval)
	Do ##class(OcuTalon.Data.Delivery).Record(session, "telegram", "ZzOther", "ZzA2"_..Number)
	Do ##class(OcuTalon.Data.Delivery).Record(other, "telegram", "ZzTheirs", approval)
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "telegram", session), "ZzNew:2", "the newest row of the owner for the Ref and channel")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "phone", session), "ZzPhone", "another channel finds its own row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval("ZzA2"_..Number, "telegram", session), "ZzOther", "another approval finds its own row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "telegram", other), "ZzTheirs", "the other owner finds its own row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "web", session), "", "a channel with no row finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval("ZzA3"_..Number, "telegram", session), "", "an unknown approval Ref finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval($ZConvert(approval, "L"), "telegram", session), "", "a Ref in another case finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval($ZConvert(approval, "U"), "telegram", session), "", "nor in upper case")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "Telegram", session), "", "a channel in another case finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "telegram", $ZConvert(session, "L")), "", "an owner in another case finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "telegram", $ZConvert(session, "U")), "", "nor in upper case")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "telegram", ##class(OcuTalon.Bridge.Ids).NewRef()), "", "an unknown owner finds nothing")
	For value = 1, 2, 3 {
		Set approvalRef = $Select(value = 1: "", 1: approval)
		Set channel = $Select(value = 2: "", 1: "telegram")
		Set owner = $Select(value = 3: "", 1: session)
		Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approvalRef, channel, owner), "", "an empty "_$Select(value = 1: "approval Ref", value = 2: "channel", 1: "owner")_" finds nothing")
	}
	For owner = "instance", "eval" {
		Set sc = ##class(OcuTalon.Data.Delivery).Record(owner, "telegram", "Zz"_owner_":9", approval, , , , , , .stray)
		Do $$$AssertStatusOK(sc, "a row of the owner "_owner_" is recorded")
		If $IsObject($Get(stray)) Set ..Strays = ..Strays_","_stray.%Id()
		Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "telegram", owner), "", "but the owner "_owner_" finds nothing")
		Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "telegram", $ZConvert(owner, "U")), "", "nor in upper case")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "telegram", session), "ZzNew:2", "and the session still finds its newest")
}

/// --- helpers ---
/// A fixture session; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzdel"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The number of Delivery rows of the owner, whatever their channel (the test reads the table directly, as a test may).
Method Count(owner As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).DeliveryCount(owner)
}

/// The Delivery rows of the owner on the channel, opened.
Method RowsOf(owner As %String, channel As %String) As %ListOfObjects [ Private ]
{
	Set list = ##class(%ListOfObjects).%New()
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND Channel = ? ORDER BY ID", owner, channel)
	While result.%Next() {
		Do list.Insert(##class(OcuTalon.Data.Delivery).%OpenId(result.%Get("ID")))
	}
	Quit list
}

}
