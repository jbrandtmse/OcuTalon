/// Tests of Data.SlackLink (Story 27.1; AD-4, AD-14, AD-27; Contest Planner rulings R2 and R8): the link between a Slack member and a session, and the claims of event ids.
/// Safe on a slot: the rows are fixture sessions (Test.Data.Fixture) and links made through Link, all removed by OnAfterAllTests, and ^OcuTalonP.SlackE is killed before and
/// after every test.
///   - TestSessionForNeedsBothIds: R2, SessionFor answers the session only for the team AND the member of the row, never for the same member id in another team, a
///     member of the same team with another id, or an empty id;
///   - TestLinkRules: Link refuses an empty id, an id that is not letters and digits, an id of more than 32 characters, a session with no row, and a member or a session that
///     is already linked, and none of its error texts holds an id; Unlink removes the session's link and is OK when there is none;
///   - TestLinkGoesWithSession: R8, deleting the session row with %DeleteId (the AD-27 purge's call), through DropEval (an evaluation session) and with an SQL DELETE
///     each deletes its link row, and SessionFor is empty afterwards;
///   - TestLinkedInAnotherTeam: the member id of a row in a workspace other than the one asked is found, the row's own workspace and an unknown id are not;
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
