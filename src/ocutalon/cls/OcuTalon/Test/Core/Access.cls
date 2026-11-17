/// Tests of OcuTalon.Core.Access, the one rule of who may chat through a channel that has no web session (Story 0.38; AD-3, AD-14, AD-24; DW-1284, DW-1465, DW-1466), over real IRIS
/// accounts that hold real roles and a real account state (Test.Data.Fixture ChatSession and SetAccount, which Fixture.Clean removes after the run, a failed test included). No mock of the
/// role or account read: only AccessProbe's throw seam, inside the %SYS switch. Safe on a slot: it creates and removes only its own fixture accounts.
///   - TestRolesMayChat: RolesMayChat answers 1 for a list that holds OcuTalonUser by its whole name and 0 for a viewer, OcuTalonAdmin alone, %All alone, a name that only contains the role
///     name, and no role; Test.Web.ViewerApi TestMayChatIsTheRuleOfWebChat pins it to web chat's gate;
///   - TestAccountState: MayChat answers 1 for an enabled, unexpired account that holds OcuTalonUser (control) and for one that expires in 30 days, and 0 for a disabled one, one whose
///     ExpirationDate was yesterday or two days ago (and 1 for one that expires today, the last day it may be used), a viewer-only one, an admin-only one, an account that does not exist, and an empty user; and a call writes nothing to the account;
///   - TestAccountUsable (DW-1482): AccountUsable, the account's state alone with no role asked, answers 1 for an enabled, unexpired account (also one that expires in 30 days, today, or never) and for a viewer-only one,
///     and 0 for a disabled one, one past its expiry (yesterday, two days ago), an account that does not exist, an empty user and no argument, and writes nothing; and MayChat asks it (a probe whose AccountUsable
///     answers 0 makes MayChat 0 for an account that would be allowed, after one call);
///   - TestNamespaceIsRestored: the read of the account runs in %SYS and the caller's namespace is its own again after the call, on the normal path and when the read throws;
///   - TestErrorInTheReadMayNotChat: an error inside the read answers 0 for an account that would be allowed, and does not throw;
///   - TestNoWebReference: the source of Core.Access, Core.Conversation, Channel.Email.In and Channel.Telegram.In, read from the class dictionary, names no OcuTalon.Web class, and the scan
///     finds one in a sample (Core does not depend on the web packages, DW-1466).
Class OcuTalon.Test.Core.Access Extends %UnitTest.TestCase
{

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^||AccessProbe
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Kill ^||AccessProbe
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
}

Method TestRolesMayChat()
{
	Set access = "OcuTalon.Core.Access"
	Do $$$AssertEquals($ClassMethod(access, "RolesMayChat", "OcuTalonUser"), 1, "OcuTalonUser alone may chat")
	Do $$$AssertEquals($ClassMethod(access, "RolesMayChat", "OcuTalonAdmin,OcuTalonUser"), 1, "OcuTalonAdmin and OcuTalonUser may chat")
	Do $$$AssertEquals($ClassMethod(access, "RolesMayChat", "OcuTalonUser,OcuTalonViewer"), 1, "OcuTalonUser and OcuTalonViewer may chat")
	Do $$$AssertEquals($ClassMethod(access, "RolesMayChat", "%All,OcuTalonUser"), 1, "%All with OcuTalonUser may chat")
	Do $$$AssertEquals($ClassMethod(access, "RolesMayChat", "OcuTalonViewer"), 0, "OcuTalonViewer alone may not")
	Do $$$AssertEquals($ClassMethod(access, "RolesMayChat", "OcuTalonAdmin"), 0, "OcuTalonAdmin alone may not")
	Do $$$AssertEquals($ClassMethod(access, "RolesMayChat", "OcuTalonAdmin,OcuTalonViewer"), 0, "a viewer who is also an admin may not")
	Do $$$AssertEquals($ClassMethod(access, "RolesMayChat", "%All"), 0, "%All alone may not")
	Do $$$AssertEquals($ClassMethod(access, "RolesMayChat", "OcuTalonUserX,XOcuTalonUser"), 0, "a name that only contains the role's name is not the role")
	Do $$$AssertEquals($ClassMethod(access, "RolesMayChat", ""), 0, "no role may not")
	Do $$$AssertEquals($ClassMethod(access, "RolesMayChat"), 0, "no argument may not")
}

Method TestAccountState()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set user = ..Account("ok", "OcuTalonUser")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(user), 1, "control: an enabled, unexpired account that holds OcuTalonUser may chat")
	Set before = ..Properties(user)
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(user), 1, "and again")
	Do $$$AssertEquals(..Properties(user), before, "asking writes nothing: the account's properties are as they were")
	Set disabled = ..Account("disabled", "OcuTalonUser")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", disabled, 0, ""), "the account is disabled")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(disabled), 0, "a disabled account may not chat")
	Set expired = ..Account("expired", "OcuTalonUser")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", expired, 1, -2), "the account's ExpirationDate is two days ago")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(expired), 0, "an account past its expiry may not chat")
	Set later = ..Account("later", "OcuTalonUser")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", later, 1, 30), "the account's ExpirationDate is in 30 days")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(later), 1, "control: an account that expires in 30 days may chat")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", later, 1, ""), "the expiry is cleared")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(later), 1, "an account with no expiry may chat")
	Set today = ..Account("today", "OcuTalonUser")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", today, 1, 0), "the account's ExpirationDate is today, the last day it may be used")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(today), 1, "an account whose ExpirationDate is today may still chat")
	Set yesterday = ..Account("yesterday", "OcuTalonUser")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", yesterday, 1, -1), "the account's ExpirationDate is yesterday")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(yesterday), 0, "an account whose ExpirationDate was yesterday may not chat")
	Set never = ..Account("never", "OcuTalonUser")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", never, 1, -2, 1), "the account never expires, and a date two days ago is given")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(never), 1, "an account that never expires may chat: IRIS keeps no expiry date for it and lets it sign in")
	Set viewer = ..Account("viewer", "OcuTalonViewer")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(viewer), 0, "a viewer-only account may not chat although it is usable")
	Set admin = ..Account("admin", "OcuTalonAdmin")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(admin), 0, "an admin-only account may not chat although it is usable")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(user_"nobody"), 0, "an account that does not exist may not chat")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(""), 0, "an empty user may not chat")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(), 0, "and no argument may not chat")
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).RolesOf(disabled, .roles) && (roles = "OcuTalonUser"), "control: the disabled account still holds OcuTalonUser (so it is the account state that refuses it)")
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).RolesOf(expired, .roles) && (roles = "OcuTalonUser"), "and so does the expired one")
}

Method TestAccountUsable()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set access = "OcuTalon.Core.Access"
	Set user = ..Account("au", "OcuTalonUser")
	Set before = ..Properties(user)
	Do $$$AssertEquals($ClassMethod(access, "AccountUsable", user), 1, "control: an enabled, unexpired account is usable")
	Do $$$AssertEquals(..Properties(user), before, "asking writes nothing")
	Set viewer = ..Account("auviewer", "OcuTalonViewer")
	Do $$$AssertEquals($ClassMethod(access, "AccountUsable", viewer), 1, "a usable account is usable whatever its roles: no chat role is asked")
	Set disabled = ..Account("audisabled", "OcuTalonUser")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", disabled, 0, ""), "the account is disabled")
	Do $$$AssertEquals($ClassMethod(access, "AccountUsable", disabled), 0, "a disabled account is not usable")
	Set expired = ..Account("auexpired", "OcuTalonUser")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", expired, 1, -2), "the account's ExpirationDate is two days ago")
	Do $$$AssertEquals($ClassMethod(access, "AccountUsable", expired), 0, "an account past its expiry is not usable")
	Set yesterday = ..Account("auyesterday", "OcuTalonUser")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", yesterday, 1, -1), "the account's ExpirationDate is yesterday")
	Do $$$AssertEquals($ClassMethod(access, "AccountUsable", yesterday), 0, "an account whose ExpirationDate was yesterday is not usable")
	Set today = ..Account("autoday", "OcuTalonUser")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", today, 1, 0), "the account's ExpirationDate is today")
	Do $$$AssertEquals($ClassMethod(access, "AccountUsable", today), 1, "an account whose ExpirationDate is today is usable")
	Set later = ..Account("aulater", "OcuTalonUser")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", later, 1, 30), "the account's ExpirationDate is in 30 days")
	Do $$$AssertEquals($ClassMethod(access, "AccountUsable", later), 1, "an account that expires in 30 days is usable")
	Set never = ..Account("aunever", "OcuTalonUser")
	Do $$$AssertStatusOK($ClassMethod(fixture, "SetAccount", never, 1, -2, 1), "the account never expires")
	Do $$$AssertEquals($ClassMethod(access, "AccountUsable", never), 1, "an account that never expires is usable")
	Do $$$AssertEquals($ClassMethod(access, "AccountUsable", user_"nobody"), 0, "an account that does not exist is not usable")
	Do $$$AssertEquals($ClassMethod(access, "AccountUsable", ""), 0, "an empty user is not usable")
	Do $$$AssertEquals($ClassMethod(access, "AccountUsable"), 0, "and no argument is not usable")
	Do $$$AssertEquals($ClassMethod(access, "MayChat", user), 1, "control: MayChat of the usable account that holds OcuTalonUser is 1")
	Set ^||AccessProbe("mode") = "account"
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.AccessProbe).MayChat(user), 0, "MayChat is 0 when AccountUsable is 0, for an account that would be allowed")
	Do $$$AssertEquals($Get(^||AccessProbe("accountCalls")), 1, "after one call of AccountUsable: MayChat uses it")
	Do $$$AssertEquals($Data(^||AccessProbe("namespace")), 0, "and the read of the account did not run")
}

Method TestNamespaceIsRestored()
{
	Set user = ..Account("ns", "OcuTalonUser")
	Set here = $Namespace
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.AccessProbe).MayChat(user), 1, "the probe's read of an allowed account answers 1")
	Do $$$AssertEquals($Get(^||AccessProbe("namespace")), "%SYS", "the read ran in %SYS")
	Do $$$AssertEquals($Namespace, here, "the caller's namespace is its own again")
	Kill ^||AccessProbe
	Set ^||AccessProbe("mode") = "throw"
	Set answer = ##class(OcuTalon.Test.Core.AccessProbe).MayChat(user)
	Do $$$AssertEquals($Get(^||AccessProbe("namespace")), "%SYS", "the read that throws ran in %SYS too")
	Do $$$AssertEquals($Namespace, here, "the caller's namespace is its own again after an error in the read")
	Do $$$AssertEquals(answer, 0, "and the answer is 0")
}

Method TestErrorInTheReadMayNotChat()
{
	Set user = ..Account("throws", "OcuTalonUser")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.AccessProbe).MayChat(user), 1, "control: the probe's real read allows the account")
	Set ^||AccessProbe("mode") = "throw"
	Set threw = 0
	Try {
		Set answer = ##class(OcuTalon.Test.Core.AccessProbe).MayChat(user)
	} Catch exception {
		Set threw = 1
	}
	Do $$$AssertEquals(threw, 0, "an error inside the read is not thrown to the caller")
	Do $$$AssertEquals($Get(answer), 0, "an error inside the read answers 0, fail closed, for an account that would be allowed")
}

Method TestNoWebReference()
{
	Set classes = $ListBuild("OcuTalon.Core.Access", "OcuTalon.Core.Conversation", "OcuTalon.Channel.Email.In", "OcuTalon.Channel.Telegram.In")
	Set position = 0
	While $ListNext(classes, position, class) {
		Set sc = ##class(%Compiler.UDL.TextServices).GetTextAsString($Namespace, class, .text)
		Do $$$AssertStatusOK(sc, "the source of "_class_" is read")
		Do $$$AssertTrue($Length(text) > 500, class_" has a source")
		Do $$$AssertEquals($Find($ZConvert(text, "L"), "ocutalon.web."), 0, class_" names no OcuTalon.Web class")
	}
	Do $$$AssertTrue($Find($ZConvert("Quit ##class(OcuTalon.Web.Public.Shell).HasRole(roles)", "L"), "ocutalon.web.") > 0, "the scan finds a web class in a sample")
}

/// The account's properties that a write would change, as one text, read in %SYS.
ClassMethod Properties(user As %String) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill properties
	Set sc = ##class(Security.Users).Get(user, .properties)
	Quit $Get(properties("Enabled"))_"|"_$Get(properties("ExpirationDate"))_"|"_$Get(properties("Roles"))_"|"_$Get(properties("Password"))_"|"_$Get(properties("FullName"))_"|"_$Get(properties("ChangePassword"))
}

/// A fixture session of a real account with the roles, recorded for the clean-up; returns the account's name.
Method Account(name As %String, roles As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).ChatSession("zzaccess"_name, roles, .user)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit user
}

}
