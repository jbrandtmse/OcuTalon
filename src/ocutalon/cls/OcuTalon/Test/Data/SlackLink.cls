/// Tests of Data.SlackLink (Story 27.1; AD-4, AD-14, AD-27; Contest Planner rulings R2 and R8): the link between a Slack member and a session, and the claims of event ids.
/// Safe on a slot: the rows are fixture sessions (Test.Data.Fixture) and links made through Link, all removed by OnAfterAllTests, and ^OcuTalonP.SlackE is killed before and
/// after every test.
///   - TestSessionForNeedsBothIds: R2, SessionFor answers the session only for the team AND the member of the row, never for the same member id in another team, a
///     member of the same team with another id, or an empty id;
///   - TestLinkRules: Link refuses an empty id, an id that is not letters and digits, an id of more than 32 characters, a session with no row, and a member or a session that
///     is already linked, and none of its error texts holds an id; Unlink removes the session's link and is OK when there is none;
///   - TestLinkGoesWithSession: R8, deleting the session row with %DeleteId (the AD-27 purge's call), through DropEval (an evaluation session) and with an SQL DELETE
///     each deletes its link row, and SessionFor is empty afterwards;
///   - TestLinkWithoutSessionIsNoLink: (QA) a link row whose session row is gone (made with a %NOCHECK delete) gives no session, so the member is unlinked;
///   - TestLinkedInAnotherTeam: the member id of a row in a workspace other than the one asked is found, the row's own workspace and an unknown id are not;
///   - TestLinkReasons: (Story 27.3) Link names why it refused in reason (bad_id, no_session, member_taken, user_taken), is OK with the existing Ref for the same member and session
///     and with "" as the reason for a new link, takes the Ref that the caller made, and no status text holds an id;
///   - TestTaken: Taken answers "", same, member_taken or user_taken from the two unique indexes, the member first, and changes nothing;
///   - TestList: List answers [{ref, sessionRef, member}] in the order of the rows' ids, with no team id;
///   - TestWorkspace: NoteWorkspace holds a valid team id, ignores an invalid or empty one, writes only when the value differs, and Workspace answers it (the value held before the test is put back);
///   - TestClaimEvent: the first claim of an event id wins and a repeat does not, in the same hour and across an hour boundary; a claim is kept for 2 hours and its bucket is
///     deleted at the first claim after that; UnclaimEvent gives one back; an empty or over-long id is never claimed.
Class OcuTalon.Test.Data.SlackLink Extends %UnitTest.TestCase
{

Parameter TEAM = "T0FIXTURE1";

Property Refs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Refs = ""
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonP.SlackE
	Do ..DropFixtureLinks()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonP.SlackE
	Do ..DropFixtureLinks()
	Quit $$$OK
}

/// Deletes the links of the fixture workspaces, so that each test starts with none.
Method DropFixtureLinks() [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SlackLink WHERE TeamId LIKE 'T0FIXTURE%'")
}

Method OnAfterAllTests() As %Status
{
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $$$OK
}

Method TestSessionForNeedsBothIds()
{
	Set session = ..Session("both")
	Set ref = ##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0FIXTURE1", session, .sc)
	Do $$$AssertStatusOK(sc, "the member is linked")
	Do $$$AssertTrue(ref ? 22(1AN,1"-",1"_"), "with a link Ref of 22 characters")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, "U0FIXTURE1"), session, "the team and member of the row give the session")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor("T0FIXTURE2", "U0FIXTURE1"), "", "R2: the same member id in another team gives none")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, "U0FIXTURE2"), "", "another member of the team gives none")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, "u0fixture1"), "", "the ids are compared exactly, so another case gives none")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor("", "U0FIXTURE1")_##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, "")_##class(OcuTalon.Data.SlackLink).SessionFor("", ""), "", "an empty id gives none")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, "U0FIXTURE1"), session, "and the link is unchanged")
}

/// (QA) The matrix row "a link whose session row is gone": SessionFor answers none, so the member counts as unlinked. The foreign key's cascade makes such a row
/// impossible through the product's own deletes, so the test removes the session row with %NOCHECK (no foreign key action) and asserts first that the link row is
/// still there, so that the assertion on SessionFor cannot pass vacuously.
Method TestLinkWithoutSessionIsNoLink()
{
	Set session = ..Session("dangling")
	Do ##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0DANGLE1", session, .sc)
	Do $$$AssertStatusOK(sc, "a member is linked")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, "U0DANGLE1"), session, "and gives the session while it has a row")
	Do ##class(OcuTalon.Data.Session).RefIndexExists(session, .id)
	Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE %NOCHECK FROM OcuTalon_Data.Session WHERE ID = ?", id)
	Do $$$AssertEquals(result.%SQLCODE, 0, "the session row is deleted without the foreign key's action")
	Do $$$AssertNotTrue(##class(OcuTalon.Data.Session).RefIndexExists(session), "the session row is gone")
	Do $$$AssertTrue(##class(OcuTalon.Data.SlackLink).SessionRefIndexExists(session), "and the link row is still there")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, "U0DANGLE1"), "", "so the member's session is none: a link whose session row is gone is no link")
}

Method TestLinkRules()
{
	Set session = ..Session("rules")
	Set other = ..Session("rules2")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link("", "U0FIXTURE1", session, .sc), "", "no team id is refused")
	Do $$$AssertStatusNotOK(sc, "with an error status")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "", session, .sc), "", "no member id is refused")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U-0 1", session, .sc), "", "a member id that is not letters and digits is refused")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, $Translate($Justify("", 33), " ", "U"), session, .sc), "", "a member id of 33 characters is refused")
	Do $$$AssertNotEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, $Translate($Justify("", 32), " ", "U"), session, .sc), "", "and one of 32 is taken")
	Do ##class(OcuTalon.Data.SlackLink).Unlink(session)
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0FIXTURE1", "zzNoSuchSession00000001", .sc), "", "a session with no row is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) '[ "U0FIXTURE1", "and its error text holds no id")
	Set first = ##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0FIXTURE1", session, .sc)
	Do $$$AssertStatusOK(sc, "a free member and session are linked")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0FIXTURE1", other, .sc), "", "a member who is already linked cannot be linked to another session")
	Do $$$AssertTrue(($SYSTEM.Status.GetErrorText(sc) '[ "U0FIXTURE1") && ($SYSTEM.Status.GetErrorText(sc) '[ ..#TEAM), "and the error text holds no id")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0FIXTURE2", session, .sc), "", "a session that already has a member cannot take a second")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link("T0FIXTURE2", "U0FIXTURE1", other, .sc), ##class(OcuTalon.Data.SlackLink).SessionRefIndexOpen(other).Ref, "the same member id in another team is another member")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.SlackLink).Unlink(session), "Unlink removes the session's link")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, "U0FIXTURE1"), "", "so the member is no longer linked")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.SlackLink).Unlink(session), "and Unlink with no link is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor("T0FIXTURE2", "U0FIXTURE1"), other, "the other team's link is untouched")
	Do $$$AssertNotEquals(first, "", "the first link had a Ref")
}

Method TestLinkReasons()
{
	Set session = ..Session("reasons")
	Set other = ..Session("reasons2")
	Set ref = ##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0REASON1", session, .sc, .reason)
	Do $$$AssertStatusOK(sc, "a new link is OK")
	Do $$$AssertEquals(reason, "", "with no reason")
	Do $$$AssertTrue(ref '= "", "and its Ref")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0REASON1", session, .sc, .reason), ref, "the same member and session again answers the existing Ref")
	Do $$$AssertStatusOK(sc, "with an OK status")
	Do $$$AssertEquals(reason, "", "and no reason")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0REASON1", other, .sc, .reason), "", "the member linked to another session is refused")
	Do $$$AssertStatusNotOK(sc, "with an error status")
	Do $$$AssertEquals(reason, "member_taken", "member_taken")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0REASON2", session, .sc, .reason), "", "a session that has another member is refused")
	Do $$$AssertEquals(reason, "user_taken", "user_taken")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0REASON1", session, .sc, .reason, "zzSomeoneElsesRef"), ref, "the same pair keeps its Ref, whatever Ref the caller offers")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U-0 1", other, .sc, .reason), "", "an id that is not letters and digits is refused")
	Do $$$AssertEquals(reason, "bad_id", "bad_id")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link("", "U0REASON3", other, .sc, .reason), "", "an empty team id is refused")
	Do $$$AssertEquals(reason, "bad_id", "bad_id again")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0REASON3", "zzNoSuchSession00000001", .sc, .reason), "", "a session with no row is refused")
	Do $$$AssertEquals(reason, "no_session", "no_session")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0REASON3", "", .sc, .reason), "", "an empty session is refused")
	Do $$$AssertEquals(reason, "no_session", "no_session again")
	Do $$$AssertTrue(($SYSTEM.Status.GetErrorText(sc) '[ "U0REASON3") && ($SYSTEM.Status.GetErrorText(sc) '[ ..#TEAM), "and no status text holds an id")
	Set made = "AAAAAAAAAAAAAAAAAAAAAA"
	Do ##class(OcuTalon.Data.SlackLink).Unlink(session)
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0REASON4", other, .sc, .reason, made), made, "the Ref that the caller made is the link's Ref")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionRefIndexOpen(other).Ref, made, "and it is the row's")
}

Method TestTaken()
{
	Set session = ..Session("taken")
	Set other = ..Session("taken2")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Taken(..#TEAM, "U0TAKEN1", session), "", "nothing stands in the way of a free pair")
	Set ref = ##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0TAKEN1", session, .sc)
	Do $$$AssertStatusOK(sc, "a pair is linked")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Taken(..#TEAM, "U0TAKEN1", session), "same", "the same pair is same")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Taken(..#TEAM, "U0TAKEN1", other), "member_taken", "the member with another session is member_taken")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Taken(..#TEAM, "U0TAKEN2", session), "user_taken", "the session with another member is user_taken")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Taken("T0FIXTURE2", "U0TAKEN1", other), "", "the same member id in another team is free")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Taken(..#TEAM, "U0TAKEN1", ""), "member_taken", "the member is checked first")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Taken("", "", ""), "", "empty ids stand in the way of nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionRefIndexOpen(session).Ref, ref, "and Taken changed nothing")
}

Method TestList()
{
	Set first = ..Session("listA")
	Set second = ..Session("listB")
	Set one = ##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0LISTB01", first, .sc)
	Set two = ##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0LISTA01", second, .sc)
	Set list = ##class(OcuTalon.Data.SlackLink).List()
	Do $$$AssertTrue($IsObject(list) && list.%IsA("%Library.DynamicArray"), "List is a dynamic array")
	Set at = 0, position = ""
	Set iterator = list.%GetIterator()
	While iterator.%GetNext(.index, .row) {
		If row.ref = one Set at(1) = index, found(1) = row
		If row.ref = two Set at(2) = index, found(2) = row
		Do $$$AssertEquals(row.%Size(), 3, "a row has exactly ref, sessionRef and member")
	}
	Do $$$AssertTrue($Data(at(1)) && $Data(at(2)), "both links are listed")
	Do $$$AssertTrue(at(1) < at(2), "in the order of their ids, not of their member ids")
	Do $$$AssertEquals(found(1).sessionRef_"|"_found(1).member, first_"|U0LISTB01", "the first row names its session and member")
	Do $$$AssertEquals(found(2).sessionRef_"|"_found(2).member, second_"|U0LISTA01", "the second row names its")
	Do $$$AssertEquals(list.%ToJSON() [ ..#TEAM, 0, "and no team id is in the list")
}

Method TestWorkspace()
{
	Set held = $Data(^OcuTalonP.SlackW)
	If held Set value = ^OcuTalonP.SlackW
	Try {
		Kill ^OcuTalonP.SlackW
		Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Workspace(), "", "no workspace is noted at first")
		Do ##class(OcuTalon.Data.SlackLink).NoteWorkspace("T0FIXTURE1")
		Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Workspace(), "T0FIXTURE1", "a valid team id is noted")
		Do ##class(OcuTalon.Data.SlackLink).NoteWorkspace("")
		Do ##class(OcuTalon.Data.SlackLink).NoteWorkspace("T0-FIX 1")
		Do ##class(OcuTalon.Data.SlackLink).NoteWorkspace($Translate($Justify("", 33), " ", "T"))
		Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Workspace(), "T0FIXTURE1", "an empty, a malformed and an over-long team id are ignored")
		Do ##class(OcuTalon.Data.SlackLink).NoteWorkspace("T0FIXTURE1")
		Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Workspace(), "T0FIXTURE1", "the same value again is the same")
		Do ##class(OcuTalon.Data.SlackLink).NoteWorkspace("T0FIXTURE2")
		Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Workspace(), "T0FIXTURE2", "a different valid team id overwrites it")
		Do $$$AssertEquals($Order(^OcuTalonP.SlackW("")), "", "and the global holds one value and no subscript")
	} Catch exception {
		Do $$$AssertTrue(0, "the workspace case threw: "_exception.DisplayString())
	}
	If held {
		Set ^OcuTalonP.SlackW = value
	} Else {
		Kill ^OcuTalonP.SlackW
	}
}

Method TestLinkGoesWithSession()
{
	Set session = ..Session("objectdelete")
	Do ##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0DELETE1", session, .sc)
	Do $$$AssertStatusOK(sc, "a member is linked")
	Do $$$AssertTrue(##class(OcuTalon.Data.SlackLink).SessionRefIndexExists(session), "the link row exists")
	Do ##class(OcuTalon.Data.Session).RefIndexExists(session, .id)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Session).%DeleteId(id), "the session row is deleted with %DeleteId, as the AD-27 purge does")
	Do $$$AssertNotTrue(##class(OcuTalon.Data.SlackLink).SessionRefIndexExists(session), "R8: the link row is gone")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, "U0DELETE1"), "", "and so is the member's link")

	Set session = ..Session("sqldelete")
	Do ##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0DELETE2", session, .sc)
	Do ##class(OcuTalon.Data.Session).RefIndexExists(session, .id)
	Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Session WHERE ID = ?", id)
	Do $$$AssertEquals(result.%SQLCODE, 0, "the session row is deleted with SQL")
	Do $$$AssertNotTrue(##class(OcuTalon.Data.SlackLink).SessionRefIndexExists(session), "R8: the link row is gone")

	Set previous = ##class(OcuTalon.Test.Data.Fixture).SetEval("1")
	Set evalSession = ""
	Try {
		Set row = ##class(OcuTalon.Data.Session).ForEval(.sc)
		Do $$$AssertStatusOK(sc, "an evaluation session is made")
		Set evalSession = row.Ref
		Set row = ""
		Do ##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0DELETE3", evalSession, .sc)
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Session).DropEval(evalSession), "the evaluation session is dropped")
		Do $$$AssertNotTrue(##class(OcuTalon.Data.SlackLink).SessionRefIndexExists(evalSession), "R8: DropEval takes the link row with it")
	} Catch exception {
		Do $$$AssertTrue(0, "the evaluation case threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Test.Data.Fixture).SetEval(previous)
}

Method TestLinkedInAnotherTeam()
{
	Set session = ..Session("another")
	Do ##class(OcuTalon.Data.SlackLink).Link(..#TEAM, "U0ANOTHER", session, .sc)
	Do $$$AssertTrue(##class(OcuTalon.Data.SlackLink).LinkedInAnotherTeam("T0FIXTURE2", "U0ANOTHER"), "the member id of a row in another workspace is found")
	Do $$$AssertNotTrue(##class(OcuTalon.Data.SlackLink).LinkedInAnotherTeam(..#TEAM, "U0ANOTHER"), "the row's own workspace is not another")
	Do $$$AssertNotTrue(##class(OcuTalon.Data.SlackLink).LinkedInAnotherTeam("T0FIXTURE2", "U0UNKNOWN"), "and an unknown member id is not found")
	Do $$$AssertNotTrue(##class(OcuTalon.Data.SlackLink).LinkedInAnotherTeam("T0FIXTURE2", ""), "nor an empty one")
}

Method TestClaimEvent()
{
	Do $$$AssertTrue(##class(OcuTalon.Data.SlackLink).ClaimEvent("Ev0A", "2030-01-01T10:30:00Z"), "the first claim wins")
	Do $$$AssertNotTrue(##class(OcuTalon.Data.SlackLink).ClaimEvent("Ev0A", "2030-01-01T10:30:01Z"), "a repeat does not")
	Do $$$AssertTrue(##class(OcuTalon.Data.SlackLink).ClaimEvent("Ev0B", "2030-01-01T10:30:02Z"), "another event id does")
	Do $$$AssertNotTrue(##class(OcuTalon.Data.SlackLink).ClaimEvent("Ev0A", "2030-01-01T11:00:01Z"), "a retry in the next hour is still a repeat")
	Do $$$AssertNotTrue(##class(OcuTalon.Data.SlackLink).ClaimEvent("Ev0A", "2030-01-01T12:29:59Z"), "and so is one 1 hour 59 minutes later")
	Do $$$AssertTrue($Data(^OcuTalonP.SlackE("e", "2030-01-01T10", "Ev0A")) > 0, "the claim is kept in its hour's bucket")
	Do $$$AssertTrue(##class(OcuTalon.Data.SlackLink).ClaimEvent("Ev0A", "2030-01-01T13:00:00Z"), "after 2 hours the event id can be claimed again")
	Do $$$AssertEquals($Data(^OcuTalonP.SlackE("e", "2030-01-01T10")), 0, "and the bucket of the old claims is deleted")
	Do $$$AssertTrue(##class(OcuTalon.Data.SlackLink).ClaimEvent("Ev0C"), "a claim with no time uses the clock")
	Do $$$AssertNotTrue(##class(OcuTalon.Data.SlackLink).ClaimEvent("Ev0C"), "and a repeat of it is refused")
	Do ##class(OcuTalon.Data.SlackLink).UnclaimEvent("Ev0C")
	Do $$$AssertTrue(##class(OcuTalon.Data.SlackLink).ClaimEvent("Ev0C"), "a claim that was given back is won again")
	Do $$$AssertNotTrue(##class(OcuTalon.Data.SlackLink).ClaimEvent(""), "an empty event id is never claimed")
	Do $$$AssertNotTrue(##class(OcuTalon.Data.SlackLink).ClaimEvent($Translate($Justify("", 65), " ", "x")), "nor one of 65 characters")
	Do $$$AssertTrue(##class(OcuTalon.Data.SlackLink).ClaimEvent($Translate($Justify("", 64), " ", "x")), "but one of 64 is")
}

/// A fixture session; its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzslinkrow"_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

}
