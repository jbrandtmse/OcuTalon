/// Tests of the use-time role check that Conversation makes for an Item of channel slack (Story 27.3; AD-14, AD-24; Contest Planner ruling (a)): the Item is taken only when its session's
/// IRIS user may chat by web chat's rule (Web.Public.Shell MayChat on the user's recursed role set, read by Bridge.Approval RolesOf). Safe on a slot: no production runs there, so the tests call
/// OnRequest on shadow instances of OcuTalon.Test.Core.ConversationProbe, with real IRIS users that hold real roles (the fixture users are made in %SYS and removed after each test; a role the
/// instance does not have is made and removed with them).
///   - TestViewerOnlyRefused: a viewer-only user's Item makes no Turn, publishes nothing, sends nothing to Decide (no model call, no tool call) or Notify (no reply is sent), writes no Delivery
///     row and leaves exactly one Channel.Slack.Ignored for Intake, with the kind message.im, the reason not_user and no event id;
///   - TestRoleRemovedAfterLinking: a user who holds OcuTalonUser has a turn; after the role is removed, the next Item of the same session is refused with one record and no second Turn;
///   - TestAdminWithUserAllowed: a user with OcuTalonAdmin and OcuTalonUser has a Turn and its Decide request, and no record;
///   - TestAdminOnlyFollowsWebChat: a user with OcuTalonAdmin alone is refused, and the control is web chat's own check on the same roles (HasRole 0, so web chat refuses it);
///     a viewer who also holds OcuTalonAdmin is refused, and a user who holds both OcuTalonUser and OcuTalonViewer is allowed, as web chat decides;
///   - TestUnreadableRolesRefused: a session whose IRIS user has no account, and one with no IRIS user, are refused, and RolesOf answers 0 with no roles for each;
///   - TestRoleReadErrorRefused: a role check that throws (the probe's MayChat seam) refuses the Item of a user who would be allowed, with the same one record;
///   - TestRecordFailureIsOneContentFreeWarning: when the send of the not_user record fails, the Item is still not taken, the status is OK (no retry) and one warning is logged that names
///     no text, user or Ref;
///   - TestOtherChannelsUnchecked: an Item of the web or telegram channel of a viewer-only user is taken as before, with no record.
Class OcuTalon.Test.Core.ConversationNotUser Extends %UnitTest.TestCase
{

/// The first characters of the fixture users' names.
Parameter USER = "ZzConvNU";

/// The roles that the tests hand out.
Parameter ROLES = "OcuTalonUser,OcuTalonAdmin,OcuTalonViewer";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the fixture sessions of the run, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The fixture users, comma-separated.
Property Users As %String(MAXLEN = "");

/// The roles that this run made, comma-separated.
Property MadeRoles As %String;

/// The number of recorded calls that were already looked at.
Property Seen As %Integer;

/// The number of the newest row of the event log when the run began.
Property LogMark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Number = $Increment(^OcuTalonTest("ConversationNotUser", "n"))
	Set ..LogMark = ..LastLog()
	Set ..MadeRoles = ##class(OcuTalon.Test.Install.RolesAssign).EnsureRoles(..#ROLES)
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	For i = 1:1:$Length(..Users, ",") {
		If $Piece(..Users, ",", i) '= "" Do ..DropUser($Piece(..Users, ",", i))
	}
	If ..MadeRoles '= "" Do ##class(OcuTalon.Test.Install.RolesAssign).DropRoles(..MadeRoles)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND SourceClass = ?", ..LogMark, "OcuTalon.Test.Core.ConversationProbe")
	Quit $SYSTEM.Status.OK()
}

Method TestViewerOnlyRefused()
{
	Set session = ..Session("viewer", "OcuTalonViewer", .user)
	Set mark = ..LastLog()
	Set item = ..Item(session, "slack", "zz viewer text zqx")
	Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), "the Item is handled with an OK status")
	Do ..AssertRefused(session, user, "zz viewer text zqx", mark, "a viewer-only user's Item")
}

Method TestRoleRemovedAfterLinking()
{
	Set session = ..Session("removed", "OcuTalonUser", .user)
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, "slack", "zz first"), .response), "a user's first Item is handled")
	Do $$$AssertEquals(..Turns(session).Count(), 1, "it makes a Turn while the user holds OcuTalonUser")
	Do $$$AssertEquals($ListLength(..Sent("Decide", "decide")), 1, "and its decide request goes to Decide")
	Do $$$AssertEquals($ListLength(..Sent("Intake")), 0, "with no record")
	Set mark = ..LastLog()
	Do ..RemoveRole(user, "OcuTalonUser")
	Set before = ..Calls()
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, "slack", "zz second"), .response), "the next Item is handled")
	Do $$$AssertEquals(..Turns(session).Count(), 1, "once the role is removed it makes no second Turn")
	Do $$$AssertEquals(..Calls() - before, 1, "and it makes exactly one send")
	Do $$$AssertEquals($ListLength(..Sent("Decide", "decide")), 1, "which is no further request to Decide")
	Set sent = ..Sent("Intake")
	Do $$$AssertEquals($ListLength(sent), 1, "but one record to Intake")
	Do $$$AssertEquals(..Call($List(sent, 1), "reason"), "not_user", "whose reason is not_user")
	Do $$$AssertEquals(..Warnings(mark), 0, "and nothing is logged")
}

Method TestAdminWithUserAllowed()
{
	Set session = ..Session("adminuser", "OcuTalonAdmin,OcuTalonUser", .user)
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, "slack", "zz admin and user"), .response), "the Item is handled")
	Do $$$AssertEquals(..Turns(session).Count(), 1, "an admin who also holds OcuTalonUser has a Turn")
	Do $$$AssertEquals($ListLength(..Sent("Decide", "decide")), 1, "and its decide request goes to Decide")
	Do $$$AssertEquals($ListLength(..Sent("Intake")), 0, "with no record")
	Set session = ..Session("userviewer", "OcuTalonUser,OcuTalonViewer", .both)
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, "slack", "zz user and viewer"), .response), "an Item of a user who holds both roles is handled")
	Do $$$AssertEquals(..Turns(session).Count(), 1, "a user who holds OcuTalonUser and OcuTalonViewer has a Turn, as web chat lets them chat")
}

Method TestAdminOnlyFollowsWebChat()
{
	Set session = ..Session("adminonly", "OcuTalonAdmin", .user)
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).RolesOf(user, .roles), "the admin-only user's roles are read")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Shell).HasRole(roles), 0, "control: web chat does not let a user with OcuTalonAdmin alone in (neither role that opens the application)")
	Set mark = ..LastLog()
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, "slack", "zz admin only"), .response), "the Item is handled")
	Do ..AssertRefused(session, user, "zz admin only", mark, "an admin-only user's Item, as web chat refuses that user")
	Set session = ..Session("adminviewer", "OcuTalonAdmin,OcuTalonViewer", .viewer)
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).RolesOf(viewer, .roles), "the admin viewer's roles are read")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Shell).ViewerOnly(roles), 1, "control: web chat treats a viewer who is also an admin as a viewer (403 read_only)")
	Do ..Reset()
	Set mark = ..LastLog()
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, "slack", "zz admin viewer"), .response), "an Item of a viewer who holds OcuTalonAdmin is handled")
	Do ..AssertRefused(session, viewer, "zz admin viewer", mark, "a viewer's Item even when the viewer holds OcuTalonAdmin")
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

Method TestOtherChannelsUnchecked()
{
	Set session = ..Session("web", "OcuTalonViewer", .user)
	For channel = "web", "telegram" {
		Set before = ..Turns(session).Count()
		Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, channel, "zz "_channel), .response), channel_": the Item is handled")
		Do $$$AssertEquals(..Turns(session).Count() - before, 1, channel_": it makes a Turn, as before: only channel slack is checked here")
	}
	Do $$$AssertEquals($ListLength(..Sent("Intake")), 0, "and no record is made")
}

/// Asserts the whole of a refusal: no Turn, no event, nothing sent but the one Ignored for Intake with fixed content, no Delivery row, nothing logged, and no record that holds the text, the user or the session.
Method AssertRefused(session As %String, user As %String, text As %String, mark As %Integer, what As %String) [ Private ]
{
	Do $$$AssertEquals(..Turns(session).Count(), 0, what_" makes no Turn")
	Do $$$AssertEquals(..ChatEvents(session), 0, what_" publishes nothing")
	Do $$$AssertEquals($ListLength(..Sent("Decide")), 0, what_" makes no model call and no tool call (nothing goes to Decide)")
	Do $$$AssertEquals($ListLength(..Sent("Notify")), 0, what_" sends no reply (nothing goes to Notify)")
	Do $$$AssertEquals(..Deliveries(session), 0, what_" writes no Delivery row")
	Do $$$AssertEquals(..Calls(), 1, what_" makes exactly one send")
	Set sent = ..Sent("Intake")
	Do $$$AssertEquals($ListLength(sent), 1, what_" leaves one record, for Intake")
	Set n = $ListGet(sent, 1)
	If n = "" Quit
	Do $$$AssertEquals(..Call(n, "class")_"|"_..Call(n, "kind")_"|"_..Call(n, "reason")_"|"_..Call(n, "eventId"), "OcuTalon.Channel.Slack.Ignored|message.im|not_user|", what_": it is a Slack Ignored with the reason not_user and no event id")
	Do $$$AssertEquals(..Warnings(mark), 0, what_" logs no warning")
}

/// A fixture IRIS user that holds the roles (a comma list), and a session of it; the session's Ref, with user its name.
Method Session(name As %String, roles As %String, Output user As %String) As %String [ Private ]
{
	Set user = ..#USER_..Number_name
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Install.RolesAssign).CreateUser(user, roles), "the fixture user "_user_" is made with "_roles)
	Set ..Users = ..Users_$Select(..Users = "": "", 1: ",")_user
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session(user)
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

Method RemoveRole(user As %String, role As %String) [ Private ]
{
	Do ##class(OcuTalon.Test.Install.RolesAssign).RemoveRole(user, role)
}

/// Deletes the IRIS account, when it exists.
ClassMethod DropUser(user As %String)
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(user) Do ##class(Security.Users).Delete(user)
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

/// The number of Delivery rows of the session.
Method Deliveries(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE OwnerRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
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
