Include Ensemble

/// Tests of the service SlackIn (Story 27.1; AD-1, AD-14, AD-26; Contest Planner rulings R1, R2, R4, R6, R8 and R9). They need no production: the tests call
/// ProcessInput through OcuTalon.Test.Channel.SlackInProbe, a subclass that records the send to Conversation and the send to Intake instead of making them. The real chain is
/// the job of the live unit slack-hook. The fixture sessions and their links come from Test.Data.Fixture and Data.SlackLink, and the fake SLACK_* values are put in the
/// environment of the process and restored.
///   - TestLinkedDm: a linked member's direct message is one Item (channel slack, provenance user, FromGuide 0, only the text) to Conversation, in the session's thread, and
///     nothing goes to Intake;
///   - TestRetryOnce: R4, the same event id again is OK and sends nothing more, for a turn and for an ignored event;
///   - TestUnlinkedIgnored, TestOtherTeamIgnored (R2), TestBotIdIgnored and TestMessageChangedIgnored (R1), TestOtherEventsIgnored, TestBlankAndNoSender: each leaves one
///     Ignored record with its fixed kind and reason and no Item, in no trace session;
///   - TestLinkWithoutSessionIgnored: (QA) a member whose link row has no session row any more is unlinked: one Ignored (message.im, unlinked), no Item;
///   - TestOffWhenUnset: with either variable empty, or the online demo on, On is 0 and ProcessInput refuses and sends nothing;
///   - TestRefusesOtherInput: an input that is not an Event is refused;
///   - TestFailedSendGivesTheClaimBack: a send that fails or throws is an error status and the claim is given back, so that Slack's retry is processed;
///   - TestFirstTurnStartsTheThread: a day with no thread sends the Item in no session, and Trace.Started records the thread that the send gave; the next turn joins it;
///   - TestTypedApproveApprovesNothing: R6, a linked member's typed approve or yes sends one user Item and leaves the open approval request pending;
///   - TestNotesWorkspace: (Story 27.3) a claimed event notes its team id in ^OcuTalonP.SlackW (a linked, an unlinked and a malformed-text event alike, overwritten only when it differs), a repeat claim
///     notes nothing, an invalid team id is ignored, and with Slack off nothing is noted;
///   - TestSecondTeamChangesNoLink: (Contest Planner ruling 2026-11-16) a workspace is noted and a member linked; an event of a second team from the same member id and one from an
///     unlinked member id are each Ignored (other_team, unlinked), and no link row is created or changed;
///   - TestRecordsHoldNoIds: R8, no log row and no record of the service holds the text, the member id, the team id or the message, and an Ignored holds only three fields.
/// The run's number is n from ^OcuTalonTest("SlackIn","n"); the probe records under ^OcuTalonTest("SlackInProbe", n), which OnAfterAllTests kills.
Class OcuTalon.Test.Channel.SlackIn Extends %UnitTest.TestCase
{

Parameter TEAM = "T0FIXTURE1";

Parameter MEMBER = "U0FIXTURE1";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture sessions of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

Property SavedOnline As %String;

Property SavedSecret As %String;

Property SavedToken As %String;

Property HadSecret As %Boolean;

Property HadToken As %Boolean;

/// The workspace noted before the run, and whether there was one.
Property SavedWorkspace As %String;

Property HadWorkspace As %Boolean;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("SlackIn", "n"))
	Set ..Refs = ""
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..HadSecret = ##class(OcuTalon.Test.Agent.KeyScan).HasEnv("SLACK_SIGNING_SECRET")
	Set ..HadToken = ##class(OcuTalon.Test.Agent.KeyScan).HasEnv("SLACK_BOT_TOKEN")
	Set ..HadWorkspace = ($Data(^OcuTalonP.SlackW) > 0)
	Set ..SavedWorkspace = $Get(^OcuTalonP.SlackW)
	Set ..SavedSecret = $SYSTEM.Util.GetEnviron("SLACK_SIGNING_SECRET")
	Set ..SavedToken = $SYSTEM.Util.GetEnviron("SLACK_BOT_TOKEN")
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	Kill ^OcuTalonP.SlackE
	Kill ^OcuTalonP.SlackW
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SlackLink WHERE TeamId LIKE 'T0FIXTURE%'")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_SIGNING_SECRET", "zz-slackin-secret")
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", "zz-slackin-token")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonP.SlackE
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SlackLink WHERE TeamId LIKE 'T0FIXTURE%'")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	If ..HadWorkspace {
		Set ^OcuTalonP.SlackW = ..SavedWorkspace
	} Else {
		Kill ^OcuTalonP.SlackW
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
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

Method TestLinkedDm()
{
	Set session = ..LinkedSession("dm")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set probe = ..NewProbe()
	Set sc = probe.OnProcessInput(..Event("Ev0LINKED", ..#TEAM, ..#MEMBER, "zz hello from slack"), .out)
	Do $$$AssertStatusOK(sc, "the event is taken")
	Do $$$AssertEquals(..Targets(), "Conversation", "one send, to Conversation, and none to Intake")
	Do $$$AssertEquals(..Call(1, "sessionRef")_"|"_..Call(1, "channel")_"|"_..Call(1, "provenance")_"|"_..Call(1, "fromGuide"), session_"|slack|user|0", "an Item for the member's session, channel slack, provenance user, FromGuide 0")
	Do $$$AssertEquals(..Call(1, "text"), "zz hello from slack", "with the text as sent")
	Do $$$AssertEquals(..Call(1, "sender")_"|"_..Call(1, "subject")_"|"_..Call(1, "fileRef")_"|"_..Call(1, "clientId"), "|||", "and no sender, subject, file or client id")
	Do $$$AssertTrue(..Call(1, "itemId") ? 22(1AN,1"-",1"_"), "with a new ItemId")
	Do $$$AssertEquals(..Call(1, "superSession"), trace, "sent under the session's TraceRef")
	Do $$$AssertEquals(probe.%SessionId_"|"_probe.%SuperSession, "|", "the service's %SessionId and %SuperSession are empty again")
	Do $$$AssertEquals($Get($$$JobSessionId), "", "and the job's session id is cleared")
}

Method TestRetryOnce()
{
	Set session = ..LinkedSession("retry")
	Set probe = ..NewProbe()
	Set event = ..Event("Ev0RETRY", ..#TEAM, ..#MEMBER, "zz once")
	Do $$$AssertStatusOK(probe.OnProcessInput(event, .out), "the first delivery is taken")
	Do $$$AssertStatusOK(probe.OnProcessInput(event, .out), "the retry is answered OK")
	Do $$$AssertEquals(..Targets(), "Conversation", "and only the first is sent")
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	Set other = ..Event("Ev0RETRYIGN", ..#TEAM, "U0NOBODY", "zz ignored once")
	Do probe.OnProcessInput(other, .out)
	Do probe.OnProcessInput(other, .out)
	Do $$$AssertEquals(..Targets(), "Intake", "an ignored event is recorded once as well")
	Do $$$AssertTrue(##class(OcuTalon.Data.SlackLink).ClaimEvent("Ev0FRESH"), "a new event id is claimed")
	Do $$$AssertNotTrue(##class(OcuTalon.Data.SlackLink).ClaimEvent("Ev0FRESH"), "and not a second time")
}

Method TestUnlinkedIgnored()
{
	Do ..LinkedSession("unlinked")
	Set probe = ..NewProbe()
	Do $$$AssertStatusOK(probe.OnProcessInput(..Event("Ev0UNLINKED", ..#TEAM, "U0FIXTURE9", "zz from nobody"), .out), "an unlinked member's event is taken")
	Do $$$AssertEquals(..Targets(), "Intake", "one record, to Intake, and no Item")
	Do $$$AssertEquals(..Call(1, "kind")_"|"_..Call(1, "reason")_"|"_..Call(1, "eventId"), "message.im|unlinked|Ev0UNLINKED", "kind message.im, reason unlinked and the event id")
	Do $$$AssertEquals(..Call(1, "sessionId")_"|"_..Call(1, "superSession"), "|", "in a trace session of its own")
}

Method TestOtherTeamIgnored()
{
	Do ..LinkedSession("team")
	Set probe = ..NewProbe()
	Do probe.OnProcessInput(..Event("Ev0OTHERTEAM", "T0FIXTURE2", ..#MEMBER, "zz same member id, another workspace"), .out)
	Do $$$AssertEquals(..Targets(), "Intake", "R2: the same member id from another workspace sends no Item")
	Do $$$AssertEquals(..Call(1, "kind")_"|"_..Call(1, "reason"), "message.im|other_team", "it is recorded as other_team")
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	Do probe.OnProcessInput(..Event("Ev0OWNTEAM", ..#TEAM, ..#MEMBER, "zz the linked member"), .out)
	Do $$$AssertEquals(..Targets(), "Conversation", "and the linked member of the linked workspace is a turn")
}

Method TestNotesWorkspace()
{
	Do ..LinkedSession("workspace")
	Set probe = ..NewProbe()
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Workspace(), "", "no workspace is noted before the first event")
	Do probe.OnProcessInput(..Event("Ev0WS1", ..#TEAM, "U0FIXTURE9", "zz an unlinked member"), .out)
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Workspace(), ..#TEAM, "an unlinked member's signed event notes its team")
	Do probe.OnProcessInput(..Event("Ev0WS2", "T0FIXTURE2", "U0FIXTURE9", "zz another team"), .out)
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Workspace(), "T0FIXTURE2", "a different team overwrites it")
	Do probe.OnProcessInput(..Event("Ev0WS3", ..#TEAM, ..#MEMBER, "zz the linked member"), .out)
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Workspace(), ..#TEAM, "so does a linked member's turn")
	Kill ^OcuTalonP.SlackW
	Do probe.OnProcessInput(..Event("Ev0WS3", "T0FIXTURE2", ..#MEMBER, "zz a repeat of the claimed event id"), .out)
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Workspace(), "", "a repeat claim notes nothing")
	Do probe.OnProcessInput(..Event("Ev0WS4", "T0-BAD 1", ..#MEMBER, "zz a malformed team"), .out)
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Workspace(), "", "an invalid team id is not noted")
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", "")
	Do probe.OnProcessInput(..Event("Ev0WS5", ..#TEAM, ..#MEMBER, "zz slack is off"), .out)
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Workspace(), "", "with Slack off nothing is noted")
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", "zz-slackin-token")
	Set ^OcuTalonP.SlackW = ..#TEAM
	Set bad = ##class(OcuTalon.Channel.Slack.Event).%New()
	Set bad.EventId = "Ev0WS6"
	Set bad.EnvelopeType = "app_rate_limited"
	Do probe.OnProcessInput(bad, .out)
	Do $$$AssertEquals(##class(OcuTalon.Data.SlackLink).Workspace(), ..#TEAM, "an envelope with no team leaves the noted workspace as it was")
}

/// The ruling on a second workspace: the event is Ignored under R2 and the rows of the link table are exactly as they were (count and every row's team, member and session).
Method TestSecondTeamChangesNoLink()
{
	Set session = ..LinkedSession("secondteam")
	Do ##class(OcuTalon.Data.SlackLink).NoteWorkspace(..#TEAM)
	Set before = ..LinkRows()
	Do $$$AssertTrue(before [ (..#TEAM_"|"_..#MEMBER_"|"_session), "control: the link row is there")
	Set probe = ..NewProbe()
	Do probe.OnProcessInput(..Event("Ev0SECOND1", "T0FIXTURE2", ..#MEMBER, "zz the same member id from a second team"), .out)
	Do $$$AssertEquals(..Targets()_"|"_..Call(1, "kind")_"|"_..Call(1, "reason"), "Intake|message.im|other_team", "the linked member id from a second team is Ignored as other_team, with no Item")
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	Do probe.OnProcessInput(..Event("Ev0SECOND2", "T0FIXTURE2", "U0FIXTURE9", "zz an unlinked member id from a second team"), .out)
	Do $$$AssertEquals(..Targets()_"|"_..Call(1, "kind")_"|"_..Call(1, "reason"), "Intake|message.im|unlinked", "an unlinked member id from a second team is Ignored as unlinked, with no Item")
	Do $$$AssertEquals(..LinkRows(), before, "no link row was created or changed: the rows are exactly as they were")
}

/// Every row of the link table of the fixture workspaces as "team|member|session" lines in the order of their ids.
Method LinkRows() As %String [ Private ]
{
	Set found = ""
	Set id = ""
	For {
		Set id = $Order(^OcuTalonP.SlackLinkD(id))
		Quit:id=""
		Set row = ##class(OcuTalon.Data.SlackLink).%OpenId(id)
		If $IsObject(row) Set found = found_row.TeamId_"|"_row.MemberId_"|"_row.SessionRef_$Char(10)
	}
	Quit found
}

Method TestBotIdIgnored()
{
	Do ..LinkedSession("bot")
	Set probe = ..NewProbe()
	Set event = ..Event("Ev0BOT", ..#TEAM, ..#MEMBER, "zz a bot's message")
	Set event.BotId = "B0FIXTURE1"
	Do probe.OnProcessInput(event, .out)
	Do $$$AssertEquals(..Targets(), "Intake", "R1: a direct message with a bot_id sends no Item")
	Do $$$AssertEquals(..Call(1, "kind")_"|"_..Call(1, "reason"), "message.im|bot", "it is recorded as bot")
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	Set event = ..Event("Ev0BOTMSG", ..#TEAM, ..#MEMBER, "zz our own reply")
	Set event.Subtype = "bot_message"
	Set event.BotId = "B0FIXTURE1"
	Do probe.OnProcessInput(event, .out)
	Do $$$AssertEquals(..Targets()_"|"_..Call(1, "reason"), "Intake|bot", "a bot_message from a bot is bot too")
}

Method TestMessageChangedIgnored()
{
	Do ..LinkedSession("subtype")
	Set probe = ..NewProbe()
	For subtype = "message_changed", "message_deleted", "channel_join", "file_share", "thread_broadcast" {
		Kill ^OcuTalonTest("SlackInProbe", ..Number)
		Set event = ..Event("Ev0"_subtype, ..#TEAM, ..#MEMBER, "zz "_subtype)
		Set event.Subtype = subtype
		Do probe.OnProcessInput(event, .out)
		Do $$$AssertEquals(..Targets()_"|"_..Call(1, "kind")_"|"_..Call(1, "reason"), "Intake|message.im|subtype", "R1: subtype "_subtype_" is recorded as subtype, with no Item")
	}
}

/// (QA) The matrix row "a link whose session row is gone": the member counts as unlinked. The row is made with a %NOCHECK delete (no foreign key action); the test
/// first asserts that the link row is still there, so that the Ignored result cannot come from a missing link.
Method TestLinkWithoutSessionIgnored()
{
	Set session = ..LinkedSession("nosession")
	Set probe = ..NewProbe()
	Do ##class(OcuTalon.Data.Session).RefIndexExists(session, .id)
	Do $$$AssertEquals(##class(%SQL.Statement).%ExecDirect(, "DELETE %NOCHECK FROM OcuTalon_Data.Session WHERE ID = ?", id).%SQLCODE, 0, "the session row is deleted without the foreign key's action")
	Do $$$AssertTrue(##class(OcuTalon.Data.SlackLink).SessionRefIndexExists(session), "and the member's link row is still there")
	Do $$$AssertStatusOK(probe.OnProcessInput(..Event("Ev0NOSESSION", ..#TEAM, ..#MEMBER, "zz linked, but the session is gone"), .out), "the event is taken")
	Do $$$AssertEquals(..Targets()_"|"_..Call(1, "kind")_"|"_..Call(1, "reason")_"|"_..Call(1, "eventId"), "Intake|message.im|unlinked|Ev0NOSESSION", "one Ignored (message.im, unlinked), and no Item")
}

Method TestOtherEventsIgnored()
{
	Do ..LinkedSession("other")
	Set probe = ..NewProbe()
	Set cases = $ListBuild("channel|channel|message.channel|not_im", "group|group|message.channel|not_im", "mpim|mpim|message.channel|not_im", "none||message.other|not_im", "weird|app_home|message.other|not_im")
	Set position = 0
	While $ListNext(cases, position, one) {
		Kill ^OcuTalonTest("SlackInProbe", ..Number)
		Set event = ..Event("Ev0CT"_$Piece(one, "|", 1), ..#TEAM, ..#MEMBER, "zz in a channel")
		Set event.ChannelType = $Piece(one, "|", 2)
		Do probe.OnProcessInput(event, .out)
		Do $$$AssertEquals(..Targets()_"|"_..Call(1, "kind")_"|"_..Call(1, "reason"), "Intake|"_$Piece(one, "|", 3)_"|"_$Piece(one, "|", 4), "a message of channel type '"_$Piece(one, "|", 2)_"'")
	}
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	Set event = ..Event("Ev0MENTION", ..#TEAM, ..#MEMBER, "zz <@U0BOT> hi")
	Set event.EventType = "app_mention"
	Set event.ChannelType = "channel"
	Do probe.OnProcessInput(event, .out)
	Do $$$AssertEquals(..Targets()_"|"_..Call(1, "kind")_"|"_..Call(1, "reason"), "Intake|app_mention|unhandled_type", "an app_mention")
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	Set event = ##class(OcuTalon.Channel.Slack.Event).%New()
	Set event.EventId = "Ev0RATE"
	Set event.EnvelopeType = "app_rate_limited"
	Do probe.OnProcessInput(event, .out)
	Do $$$AssertEquals(..Targets()_"|"_..Call(1, "kind")_"|"_..Call(1, "reason"), "Intake|other|unhandled_type", "an app_rate_limited envelope")
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	Kill ^OcuTalonP.SlackE
	Set event = ..Event("", ..#TEAM, ..#MEMBER, "zz no event id")
	Do probe.OnProcessInput(event, .out)
	Do $$$AssertEquals(..Targets()_"|"_..Call(1, "kind")_"|"_..Call(1, "reason")_"|"_..Call(1, "eventId"), "Intake|other|unhandled_type|", "an envelope with no usable event id is recorded with no id, and never claimed")
	Do $$$AssertEquals($Data(^OcuTalonP.SlackE), 0, "so nothing is claimed")
}

Method TestBlankAndNoSender()
{
	Do ..LinkedSession("blank")
	Set probe = ..NewProbe()
	Set event = ..Event("Ev0BLANK", ..#TEAM, ..#MEMBER, " "_$Char(9, 10)_" ")
	Do probe.OnProcessInput(event, .out)
	Do $$$AssertEquals(..Targets()_"|"_..Call(1, "reason"), "Intake|blank", "text that is blank is recorded as blank")
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	Do probe.OnProcessInput(..Event("Ev0NOSENDER", ..#TEAM, "", "zz no member"), .out)
	Do $$$AssertEquals(..Targets()_"|"_..Call(1, "reason"), "Intake|no_sender", "an event with no member is no_sender")
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	Do probe.OnProcessInput(..Event("Ev0NOTEAM", "", ..#MEMBER, "zz no team"), .out)
	Do $$$AssertEquals(..Targets()_"|"_..Call(1, "reason"), "Intake|no_sender", "and so is one with no team")
}

Method TestOffWhenUnset()
{
	Do ..LinkedSession("off")
	Set probe = ..NewProbe()
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.In).On(), 1, "with both variables set and the demo off Slack is on")
	For name = "SLACK_SIGNING_SECRET", "SLACK_BOT_TOKEN" {
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(name, "")
		Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.In).On(), 0, name_" empty: Slack is off")
		Set sc = probe.OnProcessInput(..Event("Ev0OFF"_name, ..#TEAM, ..#MEMBER, "zz off"), .out)
		Do $$$AssertStatusNotOK(sc, name_" empty: ProcessInput refuses")
		Do $$$AssertEquals(..Targets(), "", name_" empty: and sends nothing")
		Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv(name)
		Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.In).On(), 0, name_" unset: Slack is off")
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(name, "zz-restored")
	}
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.In).On(1), 0, "with the demo flag given as 1 Slack is off")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.In).On(0), 1, "and on as 0")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertEquals(##class(OcuTalon.Channel.Slack.In).On(), 0, "with the online demo's setting on Slack is off")
	Set sc = probe.OnProcessInput(..Event("Ev0DEMO", ..#TEAM, ..#MEMBER, "zz demo"), .out)
	Do $$$AssertStatusNotOK(sc, "and ProcessInput refuses")
	Do $$$AssertEquals(..Targets()_"|"_$Data(^OcuTalonP.SlackE), "|0", "sends nothing and claims nothing")
}

Method TestRefusesOtherInput()
{
	Set probe = ..NewProbe()
	Do $$$AssertStatusNotOK(probe.OnProcessInput("zz text", .out), "a string is refused")
	Do $$$AssertStatusNotOK(probe.OnProcessInput(##class(Ens.StringRequest).%New("zz"), .out), "so is another object")
	Do $$$AssertStatusNotOK(probe.OnProcessInput("", .out), "and an empty input")
	Do $$$AssertEquals(..Targets(), "", "and nothing is sent")
}

Method TestFailedSendGivesTheClaimBack()
{
	Do ..LinkedSession("failed")
	Set probe = ..NewProbe()
	Set probe.FailSend = 1
	Set event = ..Event("Ev0FAIL", ..#TEAM, ..#MEMBER, "zz send fails")
	Do $$$AssertStatusNotOK(probe.OnProcessInput(event, .out), "a send that fails is an error status")
	Do $$$AssertEquals(probe.%SessionId_"|"_probe.%SuperSession, "|", "the service is clean")
	Set probe.FailSend = 0
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	Do $$$AssertStatusOK(probe.OnProcessInput(event, .out), "Slack's retry is taken")
	Do $$$AssertEquals(..Targets(), "Conversation", "and sent: the failed delivery's claim was given back")
	Set probe.ThrowSend = 1
	Set event = ..Event("Ev0THROW", ..#TEAM, ..#MEMBER, "zz send throws")
	Do $$$AssertStatusNotOK(probe.OnProcessInput(event, .out), "a send that throws is an error status")
	Set probe.ThrowSend = 0
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	Do probe.OnProcessInput(event, .out)
	Do $$$AssertEquals(..Targets(), "Conversation", "and its retry is sent")
	Set probe.FailIgnored = 1
	Set event = ..Event("Ev0IGNFAIL", ..#TEAM, "U0NOBODY", "zz nobody")
	Do $$$AssertStatusNotOK(probe.OnProcessInput(event, .out), "an ignored record that cannot be sent is an error status")
	Set probe.FailIgnored = 0
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	Do probe.OnProcessInput(event, .out)
	Do $$$AssertEquals(..Targets(), "Intake", "and its retry is recorded")
}

Method TestFirstTurnStartsTheThread()
{
	Set session = ..LinkedSession("thread")
	Set probe = ..NewProbe()
	Set probe.NewSession = 5150
	Do probe.OnProcessInput(..Event("Ev0THREAD1", ..#TEAM, ..#MEMBER, "zz starts the thread"), .out)
	Do $$$AssertEquals(..Call(1, "sessionId"), "", "the Item is sent in no session")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "5150|"_##class(OcuTalon.Core.Trace).Day(), "and the session it started is recorded for today")
	Do $$$AssertNotTrue(..Locked(session), "the session row's lock that Join kept is released")
	Do $$$AssertEquals($Get($$$JobSessionId), "", "and the job's session id is cleared")
	Kill ^OcuTalonTest("SlackInProbe", ..Number)
	Set probe = ..NewProbe()
	Set probe.NewSession = 6160
	Do probe.OnProcessInput(..Event("Ev0THREAD2", ..#TEAM, ..#MEMBER, "zz joins it"), .out)
	Do $$$AssertEquals(..Call(1, "sessionId"), 5150, "the next turn is sent in that thread")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(session).ThreadSessionId, 5150, "which stays the thread")
}

Method TestTypedApproveApprovesNothing()
{
	Set session = ..LinkedSession("approve")
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval(session)
	Set probe = ..NewProbe()
	For text = "approve", "Approve it", "yes", "reject", "approve "_request {
		Kill ^OcuTalonTest("SlackInProbe", ..Number)
		Do probe.OnProcessInput(..Event("Ev0APPROVE"_$Increment(count), ..#TEAM, ..#MEMBER, text), .out)
		Do $$$AssertEquals(..Targets()_"|"_..Call(1, "provenance")_"|"_..Call(1, "text"), "Conversation|user|"_text, "R6: '"_text_"' is one user Item and nothing else")
	}
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request)
	Do $$$AssertEquals(row.State_"|"_row.AnsweredAt_"|"_row.AnsweredAction_"|"_row.AnsweredChannel, "pending|||", "the open approval request is still pending and unanswered")
}

Method TestRecordsHoldNoIds()
{
	Do ..LinkedSession("ids")
	Set marker = "zzmarker"_..Number
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set probe = ..NewProbe()
	Set team = "T0"_marker, member = "U0"_marker
	Do probe.OnProcessInput(..Event("Ev0IDS1", team, member, "zz text "_marker), .out)
	Set event = ..Event("Ev0IDS2", ..#TEAM, ..#MEMBER, "zz text "_marker)
	Set event.Subtype = "message_changed"
	Do probe.OnProcessInput(event, .out)
	Do probe.OnProcessInput(..Event("Ev0IDS3", ..#TEAM, ..#MEMBER, "zz text "_marker), .out)
	Set held = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ?", mark)
	While result.%Next() {
		Set line = result.%Get("Text")
		If (line [ marker) || (line [ ..#TEAM) || (line [ ..#MEMBER) Set held = held + 1
	}
	Do $$$AssertEquals(held, 0, "R8: no event-log row after the events holds the text, a member id or a team id")
	For n = 1:1:+$Get(^OcuTalonTest("SlackInProbe", ..Number)) {
		If ..Call(n, "target") = "Intake" {
			Set all = ..Call(n, "kind")_"|"_..Call(n, "reason")_"|"_..Call(n, "eventId")
			Do $$$AssertTrue((all '[ marker) && (all '[ ..#MEMBER) && (all '[ ..#TEAM), "an Ignored record holds only its kind, reason and event id")
		}
	}
	Set names = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledProperty WHERE parent = ? AND Origin = ? ORDER BY Name", "OcuTalon.Channel.Slack.Ignored", "OcuTalon.Channel.Slack.Ignored")
	While result.%Next() {
		Set names = names_$Select(names = "": "", 1: ",")_result.%Get("Name")
	}
	Do $$$AssertEquals(names, "EventId,Kind,Reason", "the Ignored class has those three properties of its own and no other")
}

/// --- helpers ---

/// A fixture session, with its member linked in the fixture workspace; the session's Ref.
Method LinkedSession(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzslk"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Do ##class(OcuTalon.Data.SlackLink).Link(..#TEAM, ..#MEMBER, ref, .sc)
	Do $$$AssertStatusOK(sc, "the fixture member is linked to the session")
	Quit ref
}

/// A plain direct message event with the event id, team, member and text.
Method Event(eventId As %String, teamId As %String, memberId As %String, text As %String) As OcuTalon.Channel.Slack.Event [ Private ]
{
	Set event = ##class(OcuTalon.Channel.Slack.Event).%New()
	Set event.EventId = eventId
	Set event.EnvelopeType = "event_callback"
	Set event.EventType = "message"
	Set event.ChannelType = "im"
	Set event.TeamId = teamId
	Set event.MemberId = memberId
	Set event.Text = text
	Quit event
}

/// A shadow instance of the probe, in the run's records.
Method NewProbe() As OcuTalon.Test.Channel.SlackInProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Channel.SlackInProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.RunNumber = ..Number
	Quit probe
}

/// The targets of the recorded calls in order, joined with "|".
Method Targets() As %String [ Private ]
{
	Set found = ""
	For n = 1:1:+$Get(^OcuTalonTest("SlackInProbe", ..Number)) {
		Set found = found_$Select(found = "": "", 1: "|")_..Call(n, "target")
	}
	Quit found
}

/// One field of one recorded call.
Method Call(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("SlackInProbe", ..Number, n, field))
}

/// 1 when a lock is held on the session's row.
Method Locked(sessionRef As %String) As %Boolean [ Private ]
{
	If '##class(OcuTalon.Data.Session).RefIndexExists(sessionRef, .id) Quit 0
	Set held = 0
	Set name = ""
	For {
		Set name = $Order(^$LOCK(name))
		If name = "" Quit
		If name [ ("OcuTalonP.SessionD(" _ id _ ")") {
			Set held = 1
			Quit
		}
	}
	Quit held
}

}
