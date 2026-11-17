/// Tests of the ListSlackLinks, LinkSlackMember and UnlinkSlackMember commands in OcuTalon.Core.SettingsOps (Story 27.3; AD-1, AD-17, AD-24; Contest Planner rulings R2, R8, R10),
/// called on a shadow instance of OcuTalon.Test.Core.SettingsOpsProbe, whose audit write is a recording seam, with the user name and member id in a real SecretHandoff. Safe on a
/// slot: no production runs. The workspace global, the Slack environment variables and the online-demo flag are saved before the run and put back after it; the fixture sessions
/// and the links of the fixture workspaces T0SLKOPS* are removed after every test.
///   - TestListThroughHandoff: the list leaves only as the uri in Data, state is the answer of SlackIn On (on with both variables, off without either), links name the user and member,
///     users are the roster, and the handoff is taken once;
///   - TestLinkAuditsFirst: a link whose audit write fails answers not_audited and stores no row; one that is audited writes one entry (slackLink.<Ref>, from "" to the user) before the row,
///     and the same pair again is done with the existing Ref and audited as a link;
///   - TestLinkReasons: a malformed member (bad_member), a user with no session (user_unknown), no noted workspace (no_workspace), a member linked to another user (member_taken) and a user
///     with another member (user_taken) are refused with their reason and field, with no audit entry and no new row;
///   - TestLinkRefusesUsersWhoMayNotChat, TestListOffersOnlyUsersWhoMayChat (Contest Planner ruling (a)): a user with a session who may not chat by web chat's rule (a viewer, a user with OcuTalonAdmin and neither chat role,
///     a viewer who is also an admin, an account that does not exist) is refused user_unknown with no audit entry and no row, an admin who also holds OcuTalonUser is linked, and the
///     users that the list offers are only those who may chat, read from their live roles;
///   - TestFailedAfterAudit: a link that loses its member or its user to another link after its audit entry is refused with the reason, writes the reversing entry (from the user to
///     "") and makes no row of its own;
///   - TestLinkGuards: an admin session with no row (no_session) and a handoff that is gone, not JSON or not {user, member} (failed) change nothing and write no audit entry;
///   - TestLinkTargetsForUserSession: a user with two session rows is linked to the oldest;
///   - TestUnlink, TestUnlinkUnknownRef, TestNotAudited: an unlink audits (from the user to "") and removes the row; an unknown or empty Ref is not_found with no audit; a failed audit write
///     changes nothing, for a link and for an unlink;
///   - TestOnlineDemo: each verb answers not_available with the text settings.slackOffOnDemo, a link's handoff is taken (nothing is left behind), nothing is audited and no row is made;
///   - TestNoIdsInRecords: R8, the member id and the team id are in no audit entry, CommandResult, command property, log row or traced message, and the user's name is in the audit entry only
///     (the result of a link and of an unlink holds none);
///   - TestWebAdminOnly: every origin but web_admin is not_allowed for each verb, with no audit entry and no row.
Class OcuTalon.Test.Core.SettingsSlack Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Core.SettingsSlackProbe";

Parameter TEAM = "T0SLKOPS01";

Parameter MEMBER = "U0SLKOPS01";

Parameter USERONE = "zzslkusrone";

Parameter USERTWO = "zzslkusrtwo";

/// The saved online-demo flag, workspace and Slack variables.
Property SavedOnline As %String;

Property HadWorkspace As %Boolean;

Property SavedWorkspace As %String;

Property HadSecret As %Boolean;

Property HadToken As %Boolean;

Property SavedSecret As %String;

Property SavedToken As %String;

/// The Refs of the fixture sessions of the test, comma-separated, and of the admin's session.
Property Refs As %String(MAXLEN = "");

Property Admin As %String;

/// The IRIS accounts that the test made for its fixture sessions, comma-separated, and the roles that this run made.
Property Users As %String(MAXLEN = "");

Property MadeRoles As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..HadWorkspace = ($Data(^OcuTalonP.SlackW) > 0)
	Set ..SavedWorkspace = $Get(^OcuTalonP.SlackW)
	Set ..HadSecret = ##class(OcuTalon.Test.Agent.KeyScan).HasEnv("SLACK_SIGNING_SECRET")
	Set ..HadToken = ##class(OcuTalon.Test.Agent.KeyScan).HasEnv("SLACK_BOT_TOKEN")
	Set ..SavedSecret = $SYSTEM.Util.GetEnviron("SLACK_SIGNING_SECRET")
	Set ..SavedToken = $SYSTEM.Util.GetEnviron("SLACK_BOT_TOKEN")
	Set ..MadeRoles = ##class(OcuTalon.Test.Install.RolesAssign).EnsureRoles("OcuTalonUser,OcuTalonAdmin,OcuTalonViewer")
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^OcuTalonTest("SettingsSlackProbe"), ^||OcuTalonSettingsOpsProbe
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_SIGNING_SECRET", "zz-slackops-secret")
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", "zz-slackops-token")
	Set ^OcuTalonP.SlackW = ..#TEAM
	Do ..DropLinks()
	Set ..Refs = ""
	Set ..Users = ""
	Set ..Admin = ..Session("zzslkadmin", "OcuTalonAdmin")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^OcuTalonTest("SettingsSlackProbe"), ^||OcuTalonSettingsOpsProbe
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ..DropLinks()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	For i = 1:1:$Length(..Users, ",") {
		If $Piece(..Users, ",", i) '= "" Do ##class(OcuTalon.Test.Core.ConversationNotUser).DropUser($Piece(..Users, ",", i))
	}
	Set ..Users = ""
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If ..MadeRoles '= "" Do ##class(OcuTalon.Test.Install.RolesAssign).DropRoles(..MadeRoles)
	If ..HadWorkspace {
		Set ^OcuTalonP.SlackW = ..SavedWorkspace
	} Else {
		Kill ^OcuTalonP.SlackW
	}
	If ..HadSecret {
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_SIGNING_SECRET", ..SavedSecret)
	} Else {
		Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv("SLACK_SIGNING_SECRET")
	}
	If ..HadToken {
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", ..SavedToken)
	} Else {
		Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv("SLACK_BOT_TOKEN")
	}
	Quit $$$OK
}

Method TestListThroughHandoff()
{
	Set one = ..Session(..#USERONE)
	Set two = ..Session(..#USERTWO)
	Set result = ..Link(..#USERONE, ..#MEMBER)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a member is linked")
	Set list = ..ListResult()
	Do $$$AssertEquals(list.Ok_"|"_list.Outcome, "1|listed", "the list is Ok and listed")
	Set data = {}.%FromJSON(list.Data)
	Do $$$AssertEquals(data.%Size(), 1, "its Data holds one member")
	Do $$$AssertTrue(data.%GetTypeOf("handoff") = "string", "the handoff uri")
	Do $$$AssertTrue((list.Data '[ ..#USERONE) && (list.Data '[ ..#MEMBER) && (list.Message = ""), "and no name or id is in the result")
	Set sc = ##class(OcuTalon.Core.SecretHandoff).Take(data.handoff, .text, 0)
	Do $$$AssertStatusOK(sc, "the handoff is taken")
	Set body = {}.%FromJSON(text)
	Do $$$AssertEquals(body.state, "on", "Slack is on with both variables set")
	Do $$$AssertEquals(body.path, "/ocutalon/hook/slack/events", "the route's path is given")
	Set mine = ..Mine(body.links)
	Do $$$AssertEquals(mine.%Size(), 1, "the fixture's link is listed once")
	Do $$$AssertEquals(mine.%Get(0).user_"|"_mine.%Get(0).member, ..#USERONE_"|"_..#MEMBER, "with its user and member")
	Do $$$AssertEquals(mine.%Get(0).ref, ##class(OcuTalon.Data.SlackLink).MemberIndexOpen(..#TEAM, ..#MEMBER).Ref, "and its Ref")
	Do $$$AssertEquals(mine.%Get(0).%Size(), 3, "and nothing else of the row")
	Set users = ""
	Set iterator = body.users.%GetIterator()
	While iterator.%GetNext(, .name) { Set users = users_","_name }
	Do $$$AssertTrue((users [ (","_..#USERONE)) && (users [ (","_..#USERTWO)), "the users offered are the roster: both sessions' users")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(data.handoff, .again, 0), "and a second take of the handoff finds nothing")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 1, "no audit entry but the link's was written")
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", "")
	Set body = ..ListBody()
	Do $$$AssertEquals(body.state, "off", "with the bot token empty Slack is off, as SlackIn On says")
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", "zz-slackops-token")
	Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv("SLACK_SIGNING_SECRET")
	Set body = ..ListBody()
	Do $$$AssertEquals(body.state, "off", "with the signing secret unset Slack is off")
	Do $$$AssertEquals(..Mine(body.links).%Size(), 1, "and the links are listed all the same")
	Do $$$AssertEquals(one_two '= "", 1, "the fixture sessions exist")
}

Method TestLinkAuditsFirst()
{
	Set one = ..Session(..#USERONE)
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "error"
	Set result = ..Link(..#USERONE, ..#MEMBER)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "a link whose audit write fails is not_audited")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, ..#MEMBER), "", "and stores no row, so the audit entry comes before the row")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 1, "after one audit attempt")

	Kill ^OcuTalonTest("SettingsOpsProbe")
	Set result = ..Link(..#USERONE, ..#MEMBER)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a link that is audited is done")
	Set ref = {}.%FromJSON(result.Data).ref
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, ..#MEMBER), one, "the member is linked to the user's session")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).MemberIndexOpen(..#TEAM, ..#MEMBER).Ref, ref, "under the Ref that the result names")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 1, "with one audit entry")
	Set entry = {}.%FromJSON(^OcuTalonTest("SettingsOpsProbe", "calls", 1, "data"))
	Do $$$AssertEquals(entry.setting_"|"_entry.from_"|"_entry.to, "slackLink."_ref_"||"_..#USERONE, "which names slackLink.<Ref>, from nothing to the user")
	Do $$$AssertEquals(entry.irisUser_"|"_entry.sessionRef_"|"_entry.channel, "zzadmin|"_..Admin_"|web", "and the admin, the admin's session and the web channel")

	Set result = ..Link(..#USERONE, ..#MEMBER)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the same pair again is done")
	Do $$$AssertEquals({}.%FromJSON(result.Data).ref, ref, "with the existing Ref")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 2, "and audited as a link")
	Set again = {}.%FromJSON(^OcuTalonTest("SettingsOpsProbe", "calls", 2, "data"))
	Do $$$AssertEquals(again.setting_"|"_again.from_"|"_again.to, "slackLink."_ref_"||"_..#USERONE, "with the same setting, from nothing to the user")
	Set rows = ..RowCount()
	Do $$$AssertEquals(rows, 1, "and one row")
	Set result = ..Link($ZConvert(..#USERONE, "U"), " "_$ZConvert(..#MEMBER, "L")_" ")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a user in another case and a member trimmed and in lower case are the same pair")
	Do $$$AssertEquals({}.%FromJSON(result.Data).ref, ref, "again with the existing Ref")
	Set entry = {}.%FromJSON(^OcuTalonTest("SettingsOpsProbe", "calls", 3, "data"))
	Do $$$AssertEquals(entry.to, ..#USERONE, "and the audit names the user as the session row holds it")
}

Method TestLinkReasons()
{
	Set one = ..Session(..#USERONE)
	Set two = ..Session(..#USERTWO)
	Do ..AssertRefused(..Link(..#USERONE, "X123"), "bad_member", "member", "a member that does not start with U or W")
	Do ..AssertRefused(..Link(..#USERONE, "U1"), "bad_member", "member", "a member of 2 characters")
	Do ..AssertRefused(..Link(..#USERONE, "U"_$Translate($Justify("", 32), " ", "A")), "bad_member", "member", "a member of 33 characters")
	Do ..AssertRefused(..Link(..#USERONE, "U01 AB"), "bad_member", "member", "a member with a space inside")
	Do ..AssertRefused(..Link(..#USERONE, ""), "bad_member", "member", "an empty member")
	Do ..AssertRefused(..Link("", ""), "bad_member", "member", "an empty user and an empty member")
	Do ..AssertRefused(..Link("zzslknosuchuser", ..#MEMBER), "user_unknown", "user", "a user with no session row")
	Do ..AssertRefused(..Link("", ..#MEMBER), "user_unknown", "user", "an empty user")
	Kill ^OcuTalonP.SlackW
	Do ..AssertRefused(..Link(..#USERONE, ..#MEMBER), "no_workspace", "", "no noted workspace")
	Set ^OcuTalonP.SlackW = ..#TEAM
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 0, "no refusal so far wrote an audit entry")
	Do $$$AssertEquals(..RowCount(), 0, "and none made a row")
	Set result = ..Link(..#USERONE, ..#MEMBER)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a free pair is linked")
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Do ..AssertRefused(..Link(..#USERTWO, ..#MEMBER), "member_taken", "member", "a member linked to another user")
	Do ..AssertRefused(..Link(..#USERONE, "U0SLKOPS02"), "user_taken", "user", "a user whose session has another member")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 0, "neither wrote an audit entry")
	Do $$$AssertEquals(..RowCount(), 1, "nor made a row")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, ..#MEMBER), one, "and the first link is as it was")
	Do $$$AssertEquals(two '= "", 1, "the second session exists")
}

Method TestLinkRefusesUsersWhoMayNotChat()
{
	Do ..Session("zzslkviewer", "OcuTalonViewer")
	Set adminonly = ..Session("zzslkadminonly", "OcuTalonAdmin")
	Set adminviewer = ..Session("zzslkadminviewer", "OcuTalonAdmin,OcuTalonViewer")
	Set nobody = ##class(OcuTalon.Test.Data.Fixture).Session("zzslknoaccount")
	Set ..Refs = ..Refs_","_nobody
	Do ..AssertRefused(..Link("zzslkviewer", ..#MEMBER), "user_unknown", "user", "a viewer-only user")
	Do ..AssertRefused(..Link("zzslkadminonly", ..#MEMBER), "user_unknown", "user", "a user with OcuTalonAdmin and neither chat role, as web chat refuses that user")
	Do ..AssertRefused(..Link("zzslkadminviewer", ..#MEMBER), "user_unknown", "user", "a viewer who also holds OcuTalonAdmin")
	Do ..AssertRefused(..Link("zzslknoaccount", ..#MEMBER), "user_unknown", "user", "a session whose IRIS user has no account (its roles cannot be read)")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 0, "no refusal wrote an audit entry")
	Do $$$AssertEquals(..RowCount(), 0, "and none made a row")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Workspace(), ..#TEAM, "the workspace is untouched")
	Do ..Session("zzslkadminuser", "OcuTalonAdmin,OcuTalonUser")
	Set result = ..Link("zzslkadminuser", ..#MEMBER)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "an admin who also holds OcuTalonUser is linked")
}

Method TestListOffersOnlyUsersWhoMayChat()
{
	Do ..Session("zzslkviewer", "OcuTalonViewer")
	Do ..Session("zzslkadminonly", "OcuTalonAdmin")
	Do ..Session(..#USERONE, "OcuTalonUser")
	Do ..Session("zzslkadminuser", "OcuTalonAdmin,OcuTalonUser")
	Set body = ..ListBody()
	Set users = ""
	Set iterator = body.users.%GetIterator()
	While iterator.%GetNext(, .name) { Set users = users_","_name }
	Do $$$AssertTrue((users [ (","_..#USERONE)) && (users [ ",zzslkadminuser"), "the users offered include the user and the admin who holds the user role")
	Do $$$AssertTrue((users '[ ",zzslkviewer") && (users '[ ",zzslkadminonly"), "and neither the viewer-only user nor the admin-only user")
	Do ##class(OcuTalon.Test.Install.RolesAssign).RemoveRole(..#USERONE, "OcuTalonUser")
	Set body = ..ListBody()
	Set users = ""
	Set iterator = body.users.%GetIterator()
	While iterator.%GetNext(, .name) { Set users = users_","_name }
	Do $$$AssertTrue(users '[ (","_..#USERONE), "a user whose user role was removed is offered no more")
}

Method TestFailedAfterAudit()
{
	Set one = ..Session(..#USERONE)
	Set two = ..Session(..#USERTWO)
	Set ^OcuTalonTest("SettingsSlackProbe", "race") = ..#TEAM_"|"_..#MEMBER_"|"_two
	Set result = ..Link(..#USERONE, ..#MEMBER)
	Do ..AssertRefused(result, "member_taken", "member", "a member that another link took after the audit entry")
	Do ..AssertReversed(..#USERONE, "the member race")
	Do $$$AssertEquals(..RowCount(), 1, "and only the other link's row exists")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, ..#MEMBER), two, "which is as it was made")
	Do ..DropLinks()
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Set ^OcuTalonTest("SettingsSlackProbe", "race") = ..#TEAM_"|U0SLKOPS02|"_one
	Set result = ..Link(..#USERONE, ..#MEMBER)
	Do ..AssertRefused(result, "user_taken", "user", "a user whose session another link took after the audit entry")
	Do ..AssertReversed(..#USERONE, "the user race")
	Do $$$AssertEquals(..RowCount(), 1, "and only the other link's row exists")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, ..#MEMBER), "", "none for this member")
}

Method TestLinkGuards()
{
	Do ..Session(..#USERONE)
	Set command = ##class(OcuTalon.Msg.Command.LinkSlackMember).%New()
	Set command.Handoff = ..Handoff(..#USERONE, ..#MEMBER)
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = "AAAAAAAAAAAAAAAAAAAAAA"
	Set command.Origin = "web_admin"
	Set result = ..Carry(command)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|no_session", "an admin session with no row is no_session")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(command.Handoff, .left, 0), "and its handoff was taken")
	For text = "not json", "[1,2]", "{""user"": 5, ""member"": 7}" {
		Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put(text, .uri), "a handoff of "_text_" is put")
		Set command = ##class(OcuTalon.Msg.Command.LinkSlackMember).%New()
		Set command.Handoff = uri
		Set command.ActingUser = "zzadmin"
		Set command.SessionRef = ..Admin
		Set command.Origin = "web_admin"
		Set result = ..Carry(command)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "a handoff of "_text_" is failed")
	}
	Set command = ##class(OcuTalon.Msg.Command.LinkSlackMember).%New()
	Set command.Handoff = "zz-no-such-handoff"
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = ..Admin
	Set command.Origin = "web_admin"
	Set result = ..Carry(command)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "a handoff that names nothing is failed")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 0, "none wrote an audit entry")
	Do $$$AssertEquals(..RowCount(), 0, "and none made a row")
}

Method TestLinkTargetsForUserSession()
{
	Set first = ..Session("zzslkdual")
	Set second = ..Session("zzslkdual")
	Do $$$AssertNotEquals(first, second, "a user has two session rows")
	Set result = ..Link("zzslkdual", ..#MEMBER)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the link is done")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, ..#MEMBER), first, "and goes to the oldest session row, the one Session ForUser answers")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForUser("zzslkdual").Ref, first, "control: ForUser answers the same row")
}

Method TestUnlink()
{
	Set one = ..Session(..#USERONE)
	Set ref = {}.%FromJSON(..Link(..#USERONE, ..#MEMBER).Data).ref
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Set result = ..Unlink(ref)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "an unlink of the Ref is done")
	Do $$$AssertEquals(result.Message_"|"_result.Data, "|", "with no message or data")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, ..#MEMBER), "", "the member is no longer linked")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).RefIndexExists(ref), 0, "and the row is gone")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(one), 1, "the session stays")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 1, "with one audit entry")
	Set entry = {}.%FromJSON(^OcuTalonTest("SettingsOpsProbe", "calls", 1, "data"))
	Do $$$AssertEquals(entry.setting_"|"_entry.from_"|"_entry.to, "slackLink."_ref_"|"_..#USERONE_"|", "from the user to nothing")
	Do $$$AssertEquals(entry.irisUser_"|"_entry.sessionRef, "zzadmin|"_..Admin, "by the admin, in the admin's session")
}

Method TestUnlinkUnknownRef()
{
	Do ..Session(..#USERONE)
	Do ..Link(..#USERONE, ..#MEMBER)
	Kill ^OcuTalonTest("SettingsOpsProbe")
	For ref = "AAAAAAAAAAAAAAAAAAAAAA", "", "x" {
		Set result = ..Unlink(ref)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", "an unlink of '"_ref_"' is not_found")
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 0, "with no audit entry")
	Do $$$AssertEquals(..RowCount(), 1, "and the link stays")
}

Method TestNotAudited()
{
	Do ..Session(..#USERONE)
	Set ref = {}.%FromJSON(..Link(..#USERONE, ..#MEMBER).Data).ref
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "error"
	Set result = ..Unlink(ref)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "an unlink whose audit write fails is not_audited")
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, ..#MEMBER) '= "", 1, "and the member stays linked")
	Do ##class(OcuTalon.Data.SlackLink).Unlink(##class(OcuTalon.Data.SlackLink).SessionFor(..#TEAM, ..#MEMBER))
	Set result = ..Link(..#USERONE, "U0SLKOPS03")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "a link whose audit write fails is not_audited too")
	Do $$$AssertEquals(..RowCount(), 0, "and makes no row")
	Do $$$AssertEquals(result.Message, ##class(OcuTalon.Core.SettingsOps).#MESSAGESECTIONNOTAUDITED, "with the not-audited text")
}

Method TestOnlineDemo()
{
	Do ..Session(..#USERONE)
	Set ref = {}.%FromJSON(..Link(..#USERONE, ..#MEMBER).Data).ref
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Set text = ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.slackOffOnDemo")
	Do $$$AssertTrue(text [ "Slack is off on the online demo", "control: the off text is the catalog's")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set uri = ..Handoff(..#USERTWO, "U0SLKOPS02")
	Set command = ##class(OcuTalon.Msg.Command.LinkSlackMember).%New()
	Set command.Handoff = uri
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = ..Admin
	Set command.Origin = "web_admin"
	Set result = ..Carry(command)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|not_available|"_text, "a link on the online demo is not_available with the off text")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), "and its handoff was taken, so none is left")
	Set result = ..Unlink(ref)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|not_available|"_text, "an unlink is not_available with the off text")
	Set result = ..ListResult()
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|not_available|"_text, "so is the list")
	Do $$$AssertEquals(result.Data, "", "with nothing handed over")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 0, "no audit entry was written")
	Do $$$AssertEquals(..RowCount(), 1, "and no row was made or removed")
}

Method TestNoIdsInRecords()
{
	Set after = ..LastHeader()
	Do ..Session(..#USERONE)
	Do ..Session(..#USERTWO)
	Set seen = ""
	Set result = ..Link(..#USERONE, ..#MEMBER)
	Set seen = seen_..Dump(result)
	Set ref = {}.%FromJSON(result.Data).ref
	Set seen = seen_..Dump(..Link(..#USERTWO, ..#MEMBER))
	Set seen = seen_..Dump(..Link(..#USERONE, "U0SLKOPS02"))
	Set seen = seen_..Dump(..Link(..#USERONE, "nonsense"))
	Set seen = seen_..Dump(..ListResult())
	Set unlinked = ..Unlink(ref)
	Set seen = seen_..Dump(unlinked)
	Set seen = seen_..Dump(..Unlink(ref))
	Do $$$AssertEquals(result.Data, {"ref": (ref)}.%ToJSON(), "control: a link's Data is its Ref and nothing else")
	For id = ..#MEMBER, ..#TEAM, "U0SLKOPS02" {
		Do $$$AssertTrue(seen '[ id, "no CommandResult holds "_id)
		Do $$$AssertEquals(..AuditHits(id), 0, "no audit entry holds "_id)
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Text [ ?", id)
		Do rs.%Next()
		Do $$$AssertEquals(rs.%GetData(1), 0, "no log row holds "_id)
		Do $$$AssertEquals(##class(OcuTalon.Test.Eval.KeyProof).TraceHits(id, after, .places, .stats, $Namespace), 0, "no traced message holds "_id)
	}
	Do $$$AssertTrue(seen '[ ..#USERONE, "the user's name is in no CommandResult")
	Do $$$AssertTrue(..AuditHits(..#USERONE) > 0, "but it is in the audit entry")
	Set command = ##class(OcuTalon.Msg.Command.LinkSlackMember).%New()
	Set command.Handoff = ..Handoff(..#USERONE, ..#MEMBER)
	Do $$$AssertTrue((command.Handoff '[ ..#MEMBER) && (command.Handoff '[ ..#USERONE) && (command.Handoff '[ ..#TEAM), "a command holds only the handoff's uri")
	Do ##class(OcuTalon.Core.SecretHandoff).Discard(command.Handoff)
}

Method TestWebAdminOnly()
{
	Do ..Session(..#USERONE)
	Set ref = {}.%FromJSON(..Link(..#USERONE, ..#MEMBER).Data).ref
	Kill ^OcuTalonTest("SettingsOpsProbe")
	For origin = "web_user", "tool", "telegram", "system", "timer", "slack" {
		Set command = ##class(OcuTalon.Msg.Command.LinkSlackMember).%New()
		Set command.Handoff = ..Handoff(..#USERTWO, "U0SLKOPS02")
		Set command.ActingUser = "zzadmin"
		Set command.SessionRef = ..Admin
		Set command.Origin = origin
		Set result = ..Carry(command)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", "a link from "_origin_" is not_allowed")
		Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(command.Handoff, .left, 0), "and its handoff was taken")
		Set command = ##class(OcuTalon.Msg.Command.UnlinkSlackMember).%New()
		Set command.LinkRef = ref
		Set command.ActingUser = "zzadmin"
		Set command.SessionRef = ..Admin
		Set command.Origin = origin
		Set result = ..Carry(command)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", "an unlink from "_origin_" is not_allowed")
		Set command = ##class(OcuTalon.Msg.Command.ListSlackLinks).%New()
		Set command.SessionRef = ..Admin
		Set command.Origin = origin
		Set result = ..Carry(command)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "0|not_allowed|", "a list from "_origin_" is not_allowed, with nothing handed over")
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 0, "no audit entry was written")
	Do $$$AssertEquals(..RowCount(), 1, "and the link is as it was")
}

/// --- helpers ---
/// A fixture session of the IRIS user, who has a real account holding the roles (a comma list, the user role by default) unless the test made it already; its Ref. The Refs and the
/// accounts are kept for the cleanup.
Method Session(user As %String, roles As %String = "OcuTalonUser") As %String [ Private ]
{
	If '..Account(user) {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Install.RolesAssign).CreateUser(user, roles), "the account "_user_" is made with "_roles)
		Set ..Users = ..Users_$Select(..Users = "": "", 1: ",")_user
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session(user)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// 1 when the test has made the account already.
Method Account(user As %String) As %Boolean [ Private ]
{
	Quit (","_..Users_",") [ (","_user_",")
}

/// A handoff of {user, member}; its uri.
Method Handoff(user As %String, member As %String) As %String [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put({"user": (user), "member": (member)}.%ToJSON(), .uri), "the user and member are put into a handoff")
	Quit uri
}

/// A LinkSlackMember of the user and the member from the admin's session; returns the CommandResult.
Method Link(user As %String, member As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.LinkSlackMember).%New()
	Set command.Handoff = ..Handoff(user, member)
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = ..Admin
	Set command.Origin = "web_admin"
	Quit ..Carry(command)
}

/// An UnlinkSlackMember of the Ref; returns the CommandResult.
Method Unlink(ref As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.UnlinkSlackMember).%New()
	Set command.LinkRef = ref
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = ..Admin
	Set command.Origin = "web_admin"
	Quit ..Carry(command)
}

/// A ListSlackLinks from the admin's session; returns the CommandResult.
Method ListResult() As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.ListSlackLinks).%New()
	Set command.SessionRef = ..Admin
	Set command.Origin = "web_admin"
	Quit ..Carry(command)
}

/// The body that a list's handoff holds.
Method ListBody() As %DynamicObject [ Private ]
{
	Set result = ..ListResult()
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Take({}.%FromJSON(result.Data).handoff, .text, 0), "the list's handoff is taken")
	Quit {}.%FromJSON(text)
}

/// The links of a list whose member is the fixture's, so that links of other fixtures in the namespace are not counted.
Method Mine(links As %DynamicArray) As %DynamicArray [ Private ]
{
	Set mine = []
	Set iterator = links.%GetIterator()
	While iterator.%GetNext(, .one) {
		If one.member = ..#MEMBER Do mine.%Push(one)
	}
	Quit mine
}

/// Asserts that the two audit entries of a link that failed after its audit write are the link's (from nothing to the user) and its reversal (from the user to nothing), under
/// one setting.
Method AssertReversed(user As %String, what As %String) [ Private ]
{
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 2, what_": two audit entries, the link's and its reversal")
	Set first = {}.%FromJSON(^OcuTalonTest("SettingsOpsProbe", "calls", 1, "data"))
	Set second = {}.%FromJSON(^OcuTalonTest("SettingsOpsProbe", "calls", 2, "data"))
	Do $$$AssertEquals(first.from_"|"_first.to, "|"_user, what_": the first entry is from nothing to the user")
	Do $$$AssertEquals(second.from_"|"_second.to, user_"|", what_": the second is from the user to nothing")
	Do $$$AssertEquals(second.setting, first.setting, what_": under the same setting")
}

/// Asserts that the result is a refusal with the reason and field, and that it came with no message text and no names.
Method AssertRefused(result As OcuTalon.Msg.CommandResult, reason As %String, field As %String, what As %String) [ Private ]
{
	Set data = {}.%FromJSON(result.Data)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_data.reason_"|"_data.field, "0|refused|"_reason_"|"_field, what_" is refused as "_reason)
}

Method Carry(command As OcuTalon.Msg.Command) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

/// The rows of the link table in the fixture workspace.
Method RowCount() As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SlackLink WHERE TeamId LIKE 'T0SLKOPS%'")
	Do rs.%Next()
	Quit rs.%GetData(1)
}

Method DropLinks() [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SlackLink WHERE TeamId LIKE 'T0SLKOPS%'")
}

/// Everything a CommandResult holds, as one string.
Method Dump(result As OcuTalon.Msg.CommandResult) As %String [ Private ]
{
	Quit result.Ok_"|"_result.Outcome_"|"_result.Message_"|"_result.Data_$Char(10)
}

/// The number of recorded audit entries that hold the text.
Method AuditHits(text As %String) As %Integer [ Private ]
{
	Set hits = 0
	For n = 1:1:+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")) {
		If $Get(^OcuTalonTest("SettingsOpsProbe", "calls", n, "data")) [ text Set hits = hits + 1
	}
	Quit hits
}

/// The highest id of an Interoperability message header, so that a scan looks only at the messages made after it.
Method LastHeader() As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens.MessageHeader")
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

}
