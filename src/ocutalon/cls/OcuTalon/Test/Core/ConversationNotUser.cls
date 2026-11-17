/// Tests of the use-time check that Conversation makes for an Item of channel slack or telegram (Stories 27.3 and 0.38; AD-14, AD-24; DW-1284, DW-1465; Contest Planner rulings): the Item is taken
/// only when its session's IRIS user may chat now (Core.Access MayChat: web chat's rule on the user's recursed role set, read by Bridge.Approval RolesOf, and an account that is Enabled and not
/// past its expiry). Safe on a slot: no production runs there, so the tests call OnRequest on shadow instances of OcuTalon.Test.Core.ConversationProbe, with real IRIS accounts that hold real
/// roles and a real account state (Test.Data.Fixture ChatSession and SetAccount; Fixture.Clean drops the accounts with the rows, a failed test included). No Delivery row can be written here (only the
/// channel Out operations write one): live:slack-hook phase 7 pins that. A refusal is always one Channel.Refused {channel, not_user} for Intake and nothing else (AssertRefused).
///   - TestViewerOnlyRefused: a viewer-only user's slack Item makes no Turn, publishes nothing, sends nothing to Decide (no model call, no tool call) or Notify (no reply is sent)
///     and leaves exactly one Channel.Refused for Intake, with the channel slack and the reason not_user;
///   - TestRoleRemovedAfterLinking: a user who holds OcuTalonUser has a turn; after the role is removed, the next Item of the same session is refused with one record and no second Turn;
///   - TestAdminWithUserAllowed: a user with OcuTalonAdmin and OcuTalonUser has a Turn and its Decide request, and no record, and a user who holds both OcuTalonUser and OcuTalonViewer
///     has a Turn, as web chat decides;
///   - TestAdminOnlyFollowsWebChat: a user with OcuTalonAdmin alone is refused, and the control is web chat's own check on the same roles (HasRole 0, so web chat refuses it);
///     a viewer who also holds OcuTalonAdmin is refused, as web chat decides;
///   - TestDisabledRefused, TestExpiredRefused (Story 0.38, DW-1465): an Item of a slack and of a telegram session whose OcuTalonUser account is disabled, or whose ExpirationDate was two days ago,
///     is refused as above (the account still holds the role, so it is the account state that refuses it), and the same Item of an enabled account is taken (control);
///   - TestTelegramViewerRefused, TestTelegramRoleRemovedAfterPairing, TestTelegramAdminWithUserAllowed, TestTelegramAdminOnlyFollowsWebChat: the same pins for channel telegram, the record naming telegram;
///   - TestRefusedFileIsDiscarded: a telegram file Item of a user who may no longer chat is refused as above, its stored file is discarded at once, and nothing reads it (no ReadFile call, no Turn);
///   - TestUnreadableRolesRefused: a session whose IRIS user has no account, and one with no IRIS user, are refused, and RolesOf answers 0 with no roles for each;
///   - TestRoleReadErrorRefused: a role check that throws (the probe's MayChat seam) refuses the Item of a user who would be allowed, with the same one record;
///   - TestRecordFailureIsOneContentFreeWarning: when the send of the not_user record fails, the Item is still not taken, the status is OK (no retry) and one warning is logged that names
///     no text, user or Ref;
///   - TestOtherChannelsUnchecked: an Item of the web channel of a viewer-only user is taken as before, with no record.
Class OcuTalon.Test.Core.ConversationNotUser Extends %UnitTest.TestCase
{

/// The first characters of the names that the fixture accounts are made from.
Parameter USER = "zzconvnu";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the fixture sessions of the run, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The number of recorded calls that were already looked at.
Property Seen As %Integer;

/// The number of the newest row of the event log when the run began.
Property LogMark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Number = $Increment(^OcuTalonTest("ConversationNotUser", "n"))
	Set ..LogMark = ..LastLog()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Kill ^OcuTalonTest("ConversationProbeMayChat")
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND SourceClass = ?", ..LogMark, "OcuTalon.Test.Core.ConversationProbe")
	Quit $SYSTEM.Status.OK()
}

Method TestViewerOnlyRefused()
{
	Do ..ViewerRefused("slack")
}

Method TestTelegramViewerRefused()
{
	Do ..ViewerRefused("telegram")
}

Method TestRoleRemovedAfterLinking()
{
	Do ..RoleRemoved("slack")
}

Method TestTelegramRoleRemovedAfterPairing()
{
	Do ..RoleRemoved("telegram")
}

Method TestAdminWithUserAllowed()
{
	Do ..AdminWithUser("slack")
}

Method TestTelegramAdminWithUserAllowed()
{
	Do ..AdminWithUser("telegram")
}

Method TestAdminOnlyFollowsWebChat()
{
	Do ..AdminOnly("slack")
}

Method TestTelegramAdminOnlyFollowsWebChat()
{
	Do ..AdminOnly("telegram")
}

Method TestDisabledRefused()
{
	Do ..AccountRefused("slack", "disabled")
	Do ..Reset()
	Do ..AccountRefused("telegram", "disabled")
}

Method TestExpiredRefused()
{
	Do ..AccountRefused("slack", "expired")
	Do ..Reset()
	Do ..AccountRefused("telegram", "expired")
}

Method TestUnreadableRolesRefused()
{
	Set name = ..#USER_..Number_"nobody"
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session(name)
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_session
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_session
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).RolesOf(name, .roles)_"|"_roles, "0|", "an IRIS user with no account has no roles read")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).RolesOf("", .roles)_"|"_roles, "0|", "and neither has an empty user")
	Set mark = ..LastLog()
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, "slack", "zz nobody"), .response), "an Item of a session whose user has no account is handled")
	Do ..AssertRefused(session, name, "zz nobody", mark, "an Item whose user's roles cannot be read")
	Set none = ##class(OcuTalon.Test.Data.Fixture).Session("")
	Set ..Sessions = ..Sessions_","_none
	Set ..Refs = ..Refs_","_none
	Do ..Reset()
	Set mark = ..LastLog()
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(none, "slack", "zz no user"), .response), "an Item of a session with no IRIS user is handled")
	Do ..AssertRefused(none, "", "zz no user", mark, "an Item of a session that names no user")
}

Method TestRoleReadErrorRefused()
{
	Set session = ..Session("readerror", "OcuTalonUser", .user)
	Set mark = ..LastLog()
	Set ^OcuTalonTest("ConversationProbeMayChat") = "throw"
	Set status = ..NewProbe().OnRequest(..Item(session, "slack", "zz read error"), .response)
	Kill ^OcuTalonTest("ConversationProbeMayChat")
	Do $$$AssertStatusOK(status, "an Item whose role check throws is handled with an OK status")
	Do ..AssertRefused(session, user, "zz read error", mark, "an Item of a user who would be allowed, when the roles cannot be read")
}

Method TestRecordFailureIsOneContentFreeWarning()
{
	Set session = ..Session("sendfails", "OcuTalonViewer", .user)
	Set mark = ..LastLog()
	Set probe = ..NewProbe()
	Set probe.FailTarget = "Intake"
	Set status = probe.OnRequest(..Item(session, "slack", "zz send fails text"), .response)
	Do $$$AssertStatusOK(status, "a failed send of the record is not an error of the Item (it is not retried)")
	Do $$$AssertEquals(..Turns(session).Count(), 0, "the Item is still not taken")
	Do $$$AssertEquals(..Warnings(mark), 1, "one warning is logged")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceClass = ?", mark, "OcuTalon.Test.Core.ConversationProbe")
	Do result.%Next()
	Set text = result.%GetData(1)
	Do $$$AssertEquals(text, ##class(OcuTalon.Core.Conversation).#LOGNOTUSER, "it is the fixed text")
	Do $$$AssertTrue((text '[ "zz send fails text") && (text '[ user) && (text '[ session), "and it holds no text, user name or Ref")
}

/// A telegram file Item of a user whose account may no longer chat (the race after TelegramIn's check): it is refused as any refusal, its stored file is discarded at once and nothing reads it:
/// the probe's ReadFile is never called and no Turn is made. The control is the same file of a user who may chat, which is read.
Method TestRefusedFileIsDiscarded()
{
	Set session = ..Session("filerace", "OcuTalonUser", .user)
	Set file = ##class(OcuTalon.Test.Data.Fixture).SentFile(session, "zz-race.pdf")
	Do $$$AssertTrue($IsObject(##class(OcuTalon.Data.SentFile).RefIndexOpen(file)), "the stored file exists")
	Do ..RemoveRole(user, "OcuTalonUser")
	Set mark = ..LastLog()
	Set item = ..FileItem(session, file)
	Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), "the file Item is handled")
	Do ..AssertRefused(session, user, "", mark, "a file Item of a user who may no longer chat", "telegram")
	Do $$$AssertEquals($IsObject(##class(OcuTalon.Data.SentFile).RefIndexOpen(file)), 0, "its stored file is discarded at once")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("ConversationProbe", ..Number, "readcalls")), 0, "and nothing read it")
}

Method TestOtherChannelsUnchecked()
{
	Set session = ..Session("web", "OcuTalonViewer", .user)
	Set before = ..Turns(session).Count()
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, "web", "zz web"), .response), "web: the Item is handled")
	Do $$$AssertEquals(..Turns(session).Count() - before, 1, "web: it makes a Turn, as before: only channels slack and telegram are checked here")
	Do $$$AssertEquals($ListLength(..Sent("Intake")), 0, "and no record is made")
}

/// A viewer-only user's Item of the channel is refused (see the class comment).
Method ViewerRefused(channel As %String) [ Private ]
{
	Set session = ..Session("viewer"_channel, "OcuTalonViewer", .user)
	Set mark = ..LastLog()
	Set item = ..Item(session, channel, "zz viewer text zqx")
	Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), channel_": the Item is handled with an OK status")
	Do ..AssertRefused(session, user, "zz viewer text zqx", mark, channel_": a viewer-only user's Item", channel)
}

/// A user who holds OcuTalonUser has a turn; once the role is removed the next Item is refused with one record and no second Turn.
Method RoleRemoved(channel As %String) [ Private ]
{
	Set session = ..Session("removed"_channel, "OcuTalonUser", .user)
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, channel, "zz first"), .response), channel_": a user's first Item is handled")
	Do $$$AssertEquals(..Turns(session).Count(), 1, channel_": it makes a Turn while the user holds OcuTalonUser")
	Do $$$AssertEquals($ListLength(..Sent("Decide", "decide")), 1, channel_": and its decide request goes to Decide")
	Do $$$AssertEquals($ListLength(..Sent("Intake")), 0, channel_": with no record")
	Set mark = ..LastLog()
	Do ..RemoveRole(user, "OcuTalonUser")
	Set before = ..Calls()
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, channel, "zz second"), .response), channel_": the next Item is handled")
	Do $$$AssertEquals(..Turns(session).Count(), 1, channel_": once the role is removed it makes no second Turn")
	Do $$$AssertEquals(..Calls() - before, 1, channel_": and it makes exactly one send")
	Do $$$AssertEquals($ListLength(..Sent("Decide", "decide")), 1, channel_": which is no further request to Decide")
	Set sent = ..Sent("Intake")
	Do $$$AssertEquals($ListLength(sent), 1, channel_": but one record to Intake")
	Do $$$AssertEquals(..Call($List(sent, 1), "channel")_"|"_..Call($List(sent, 1), "reason"), channel_"|not_user", channel_": whose channel is its own and whose reason is not_user")
	Do $$$AssertEquals(..Warnings(mark), 0, channel_": and nothing is logged")
}

/// An admin who also holds OcuTalonUser has a Turn, and so does a user who holds OcuTalonUser and OcuTalonViewer (web chat's rule).
Method AdminWithUser(channel As %String) [ Private ]
{
	Set session = ..Session("adminuser"_channel, "OcuTalonAdmin,OcuTalonUser", .user)
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, channel, "zz admin and user"), .response), channel_": the Item is handled")
	Do $$$AssertEquals(..Turns(session).Count(), 1, channel_": an admin who also holds OcuTalonUser has a Turn")
	Do $$$AssertEquals($ListLength(..Sent("Decide", "decide")), 1, channel_": and its decide request goes to Decide")
	Do $$$AssertEquals($ListLength(..Sent("Intake")), 0, channel_": with no record")
	Set session = ..Session("userviewer"_channel, "OcuTalonUser,OcuTalonViewer", .both)
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, channel, "zz user and viewer"), .response), channel_": an Item of a user who holds both roles is handled")
	Do $$$AssertEquals(..Turns(session).Count(), 1, channel_": a user who holds OcuTalonUser and OcuTalonViewer has a Turn, as web chat lets them chat")
}

/// A user with OcuTalonAdmin alone, and a viewer who is also an admin, are refused, as web chat refuses them; the control is web chat's own check on the same roles.
Method AdminOnly(channel As %String) [ Private ]
{
	Set session = ..Session("adminonly"_channel, "OcuTalonAdmin", .user)
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).RolesOf(user, .roles), channel_": the admin-only user's roles are read")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Shell).HasRole(roles), 0, channel_": control: web chat does not let a user with OcuTalonAdmin alone in (neither role that opens the application)")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).RolesMayChat(roles), 0, channel_": and Core.Access agrees")
	Set mark = ..LastLog()
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, channel, "zz admin only"), .response), channel_": the Item is handled")
	Do ..AssertRefused(session, user, "zz admin only", mark, channel_": an admin-only user's Item, as web chat refuses that user", channel)
	Set session = ..Session("adminviewer"_channel, "OcuTalonAdmin,OcuTalonViewer", .viewer)
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).RolesOf(viewer, .roles), channel_": the admin viewer's roles are read")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Shell).ViewerOnly(roles), 1, channel_": control: web chat treats a viewer who is also an admin as a viewer (403 read_only)")
	Do ..Reset()
	Set mark = ..LastLog()
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, channel, "zz admin viewer"), .response), channel_": an Item of a viewer who holds OcuTalonAdmin is handled")
	Do ..AssertRefused(session, viewer, "zz admin viewer", mark, channel_": a viewer's Item even when the viewer holds OcuTalonAdmin", channel)
}

/// An OcuTalonUser account that is enabled (control) has its Item taken; once it is disabled ("disabled") or its ExpirationDate is two days ago ("expired") the next Item is refused, although
/// the account still holds the role (RolesOf reads it).
Method AccountRefused(channel As %String, state As %String) [ Private ]
{
	Set session = ..Session(state_channel, "OcuTalonUser", .user)
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, channel, "zz usable"), .response), channel_" "_state_": the Item of the usable account is handled")
	Do $$$AssertEquals(..Turns(session).Count(), 1, channel_" "_state_": control: it makes a Turn while the account is usable")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Data.Fixture).SetAccount(user, $Select(state = "disabled": 0, 1: 1), $Select(state = "expired": -2, 1: "")), channel_" "_state_": the account is "_state)
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).RolesOf(user, .roles) && (roles = "OcuTalonUser"), channel_" "_state_": the account still holds OcuTalonUser")
	Set mark = ..LastLog()
	Set before = ..Calls()
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, channel, "zz after the change"), .response), channel_" "_state_": the next Item is handled")
	Do $$$AssertEquals(..Turns(session).Count(), 1, channel_" "_state_": it makes no second Turn")
	Do $$$AssertEquals(..Calls() - before, 1, channel_" "_state_": and it makes exactly one send")
	Set sent = ..Sent("Intake")
	Do $$$AssertEquals($ListLength(sent), 1, channel_" "_state_": one record, for Intake")
	Do $$$AssertEquals(..Call($List(sent, 1), "class")_"|"_..Call($List(sent, 1), "channel")_"|"_..Call($List(sent, 1), "reason"), "OcuTalon.Channel.Refused|"_channel_"|not_user", channel_" "_state_": a Channel.Refused of its channel with the reason not_user")
	Do $$$AssertEquals($ListLength(..Sent("Notify")), 0, channel_" "_state_": and no reply is sent")
	Do $$$AssertEquals(..Warnings(mark), 0, channel_" "_state_": nothing is logged")
}

/// Asserts the whole of a refusal: no Turn, no event, nothing sent but the one Channel.Refused for Intake, every field of which is fixed (so it holds no text, user or session), and nothing logged.
Method AssertRefused(session As %String, user As %String, text As %String, mark As %Integer, what As %String, channel As %String = "slack") [ Private ]
{
	Do $$$AssertEquals(..Turns(session).Count(), 0, what_" makes no Turn")
	Do $$$AssertEquals(..ChatEvents(session), 0, what_" publishes nothing")
	Do $$$AssertEquals($ListLength(..Sent("Decide")), 0, what_" makes no model call and no tool call (nothing goes to Decide)")
	Do $$$AssertEquals($ListLength(..Sent("Notify")), 0, what_" sends no reply (nothing goes to Notify)")
	Do $$$AssertEquals(..Calls(), 1, what_" makes exactly one send")
	Set sent = ..Sent("Intake")
	Do $$$AssertEquals($ListLength(sent), 1, what_" leaves one record, for Intake")
	Set n = $ListGet(sent, 1)
	If n = "" Quit
	Do $$$AssertEquals(..Call(n, "class")_"|"_..Call(n, "channel")_"|"_..Call(n, "reason"), "OcuTalon.Channel.Refused|"_channel_"|not_user", what_": it is a Channel.Refused of channel "_channel_" with the reason not_user")
	Do $$$AssertEquals(..Warnings(mark), 0, what_" logs no warning")
}

/// A fixture session of a real IRIS account that holds the roles (a comma list; Fixture.ChatSession); the session's Ref, with user the account's name.
Method Session(name As %String, roles As %String, Output user As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).ChatSession(..#USER_..Number_name, roles, .user)
	Do $$$AssertTrue(##class(OcuTalon.Test.Data.Fixture).AccountExists(user), "the fixture user "_user_" is made with "_roles)
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

Method RemoveRole(user As %String, role As %String) [ Private ]
{
	Do ##class(OcuTalon.Test.Install.RolesAssign).RemoveRole(user, role)
}

/// Forgets the calls recorded so far, so that the next Item's sends are counted alone.
Method Reset() [ Private ]
{
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
}

/// A shadow instance of the probe, in the run's records.
Method NewProbe() As OcuTalon.Test.Core.ConversationProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.ConversationProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.RunNumber = ..Number
	Quit probe
}

/// An Item of the channel: user provenance, a new ItemId and ClientId.
Method Item(session As %String, channel As %String, text As %String) As OcuTalon.Msg.Item [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SessionRef = session
	Set item.Channel = channel
	Set item.Provenance = "user"
	Set item.Text = text
	If channel '= "slack" Set item.ClientId = "zzc"_..Number_$Increment(^OcuTalonTest("ConversationNotUser", "c"))
	Quit item
}

/// A telegram file Item of the session for the stored file (Core.Files.Describe gives its ref, name, media type and size): untrusted, with the four file fields.
Method FileItem(session As %String, file As %String) As OcuTalon.Msg.Item [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SessionRef = session
	Set item.Channel = "telegram"
	Set item.Provenance = "untrusted"
	Do ##class(OcuTalon.Core.Files).SetItem(item, ##class(OcuTalon.Core.Files).Describe(file, session))
	Quit item
}

Method Calls() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("ConversationProbe", ..Number))
}

Method Call(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("ConversationProbe", ..Number, n, field))
}

/// The numbers of the calls to the target, as a list; with kind only the Decide requests of that kind.
Method Sent(target As %String, kind As %String = "") As %List [ Private ]
{
	Set list = ""
	For n = 1:1:..Calls() {
		If ..Call(n, "target") '= target Continue
		If (kind '= "") && (..Call(n, "kind") '= kind) Continue
		Set list = list_$ListBuild(n)
	}
	Quit list
}

/// The session's turns, as Ownership reads them.
Method Turns(session As %String) As %ListOfObjects [ Private ]
{
	Set turns = ##class(OcuTalon.Data.Ownership).Turns(session, .sc)
	Do $$$AssertStatusOK(sc, "the turns are read")
	Quit turns
}

/// The number of chat.message events in the session's stream.
Method ChatEvents(session As %String) As %Integer [ Private ]
{
	Set count = 0
	Set events = ##class(OcuTalon.Live.Event).Since(session, 0, 200, "session")
	Set iterator = events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If event.type = "chat.message" Set count = count + 1
	}
	Quit count
}

/// The number of the newest row of the event log, 0 when it is empty.
Method LastLog() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of warnings that the probe logged after the row mark.
Method Warnings(mark As %Integer) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceClass = ?", mark, "OcuTalon.Test.Core.ConversationProbe")
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
