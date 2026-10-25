/// Tests of OcuTalon.Core.Admin (Story 4.1; AD-1, AD-19). Safe on a slot: a probe subclass supplies the roles
/// and takes the submit, so nothing reaches the production. The login of a user with the roles of a case and the switch itself
/// run in docker/tests/test-demo-switch.sh.
///   - TestAllowed: the role check is by whole name, and a holder of %All alone is refused;
///   - TestSubmits: an OcuTalonAdmin holder's command is submitted once with the mode and the process's $USERNAME, and its
///     answer is returned and printed;
///   - TestRefused: a caller without OcuTalonAdmin, a holder of %All included, gets the admin-only text and submits nothing;
///   - TestNotRunning: a submit that answers an error status (no production) prints the not-running text;
///   - TestSubmitThrows: a submit that throws prints the text with the error, and a submit with no answer is failed;
///   - TestPrinted: the answer's message is the one line that SetDemoMode prints, for an admin's switch, a refusal and a bad
///     argument;
///   - TestArgumentBeforeRole: a bad argument is invalid whoever types it, and a good one from a caller without the role is refused;
///   - TestInvalidArgument: only 0 and 1 (a number or a string) are arguments; any other prints the invalid text, submits
///     nothing (an OcuTalonAdmin holder's included) and leaves the demo.mode row as it was;
///   - TestErrorText: the error text of a line drops the status's code prefix and its closing full stop.
/// The demo.mode row is saved before the tests and put back after them (Test.Demo.Step).
Class OcuTalon.Test.Core.Admin Extends %UnitTest.TestCase
{

/// 1 when the demo.mode row existed before the tests.
Property Found As %Boolean;

/// The value of the row before the tests.
Property SavedValue As %String(MAXLEN = 1000);

/// The UpdatedAt of the row before the tests.
Property SavedUpdatedAt As %String(MAXLEN = 20);

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set ..Found = found, ..SavedValue = value, ..SavedUpdatedAt = updatedAt
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("AdminProbe")
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..Found, ..SavedValue, ..SavedUpdatedAt)
	Quit $$$OK
}

/// OcuTalonAdmin counts, alone or in a list; %All alone, other roles, an empty list and a longer role name do not.
Method TestAllowed()
{
	For roles = "OcuTalonAdmin", "%All,OcuTalonAdmin", "%Developer,OcuTalonAdmin", "OcuTalonUser,OcuTalonAdmin,%Developer" {
		Do $$$AssertEquals(##class(OcuTalon.Core.Admin).Allowed(roles), 1, roles_" is allowed")
	}
	For roles = "%All", "OcuTalonUser,OcuTalonTraceViewer", "", "OcuTalonAdmins", "xOcuTalonAdmin", "%Developer,%DB_OCUTALON_DATA" {
		Do $$$AssertEquals(##class(OcuTalon.Core.Admin).Allowed(roles), 0, "'"_roles_"' is not allowed")
	}
}

/// 2, "on", "", "01" and no argument give invalid with the text; no header goes to SettingsOps and the row is as it was.
Method TestInvalidArgument()
{
	Do ##class(OcuTalon.Test.Demo.Step).Put("1", "2000-01-01T00:00:00Z")
	Set before = ..Sent("SettingsOps")
	For argument = 2, "on", "", "01", "1 ", -1 {
		Set result = ##class(OcuTalon.Core.Admin).SetDemoMode(argument)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|invalid", "'"_argument_"' is invalid")
		Do $$$AssertEquals(result.Message, "SetDemoMode takes 1 (on) or 0 (off). Nothing was changed.", "'"_argument_"': the text")
	}
	Set result = ##class(OcuTalon.Core.Admin).SetDemoMode()
	Do $$$AssertEquals(result.Outcome, "invalid", "no argument is invalid")
	Do $$$AssertEquals(..Sent("SettingsOps"), before, "no header went to SettingsOps")
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode")
	Do $$$AssertEquals(row.Value_"|"_row.UpdatedAt, "1|2000-01-01T00:00:00Z", "the row is as it was")
	Do ..Reset("OcuTalonAdmin")
	For argument = 2, "on", "", "01" {
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.AdminProbe).SetDemoMode(argument).Outcome, "invalid", "'"_argument_"' from an admin is invalid")
	}
	Do $$$AssertEquals($Get(^OcuTalonTest("AdminProbe", "sent"), 0), 0, "and an admin's bad argument submits nothing")
}

/// ErrorText drops the code prefix of an error status, an Interoperability code included, and the closing full stop.
Method TestErrorText()
{
	Do $$$AssertEquals(##class(OcuTalon.Core.Admin).ErrorText($SYSTEM.Status.Error(5001, "zz plain failed.")), "zz plain failed", "ERROR #5001: and the full stop are dropped")
	Do $$$AssertEquals(##class(OcuTalon.Core.Admin).ErrorText($SYSTEM.Status.Error("<Ens>ErrGeneral", "zz ens failed.")), "zz ens failed", "an Interoperability code is dropped too")
}

/// An OcuTalonAdmin holder (with other roles too): one submit with the mode and $USERNAME, and the CommandResult comes back.
Method TestSubmits()
{
	Do ..Reset("%Developer,OcuTalonAdmin")
	Set result = ##class(OcuTalon.Test.Core.AdminProbe).SetDemoMode(0)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|zzdone", "the submit's answer is returned")
	Do $$$AssertEquals($Get(^OcuTalonTest("AdminProbe", "sent")), 1, "one command was submitted")
	Do $$$AssertEquals($Get(^OcuTalonTest("AdminProbe", "sent", 1, "demoMode")), 0, "with DemoMode 0")
	Do $$$AssertEquals($Get(^OcuTalonTest("AdminProbe", "sent", 1, "actingUser")), $USERNAME, "and ActingUser from $USERNAME")
	Do $$$AssertEquals($Get(^OcuTalonTest("AdminProbe", "sent", 1, "origin")), "system", "from the origin system")
	Set result = ##class(OcuTalon.Test.Core.AdminProbe).SetDemoMode("1")
	Do $$$AssertEquals($Get(^OcuTalonTest("AdminProbe", "sent", 2, "demoMode")), 1, "the string 1 submits DemoMode 1")
}

/// No OcuTalonAdmin, %All alone included: not_allowed with CommandsIn's admin-only text, and nothing is submitted.
Method TestRefused()
{
	For roles = "%Developer,%DB_OCUTALON_CODE,OcuTalonUser", "%All", "" {
		Do ..Reset(roles)
		Set result = ##class(OcuTalon.Test.Core.AdminProbe).SetDemoMode(0)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", "'"_roles_"' is refused")
		Do $$$AssertEquals(result.Message, "Only an OcuTalon admin can change settings. Nothing was changed.", "'"_roles_"': the text")
		Do $$$AssertEquals($Get(^OcuTalonTest("AdminProbe", "sent"), 0), 0, "'"_roles_"': nothing was submitted")
	}
}

/// A submit that answers an error status, as when the production is not running: not_running with its text.
Method TestNotRunning()
{
	Do ..Reset("OcuTalonAdmin")
	Set ^OcuTalonTest("AdminProbe", "answer") = "error"
	Set result = ##class(OcuTalon.Test.Core.AdminProbe).SetDemoMode(1)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_running", "not_running")
	Do $$$AssertEquals(result.Message, "OcuTalon isn't taking commands now: its production isn't running or CommandsIn is disabled. Nothing was changed.", "the text")
}

/// A submit that throws: failed with the error's text between the fixed words, without its number and full stop. A submit that
/// answers OK with no CommandResult is failed with CommandsIn's text.
Method TestSubmitThrows()
{
	Do ..Reset("OcuTalonAdmin")
	Set ^OcuTalonTest("AdminProbe", "answer") = "throw"
	Set result = ##class(OcuTalon.Test.Core.AdminProbe).SetDemoMode(1)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "failed")
	Do $$$AssertEquals(result.Message, "OcuTalon couldn't submit the change: zz submit threw. Nothing was changed.", "the text carries the error")
	Set ^OcuTalonTest("AdminProbe", "answer") = "noresult"
	Set result = ##class(OcuTalon.Test.Core.AdminProbe).SetDemoMode(1)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "no answer is failed")
	Do $$$AssertEquals(result.Message, "Something went wrong inside OcuTalon, so the command may not have finished.", "with CommandsIn's text")
}

/// The answer's message is printed on a line of its own, and nothing else: the admin's switch (the submit's message), a refusal and
/// a bad argument.
Method TestPrinted()
{
	Do ..Reset("OcuTalonAdmin")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.AdminProbe).Capture(1), "zz done"_$Char(10), "an admin's switch prints the message and a line feed")
	Do ..Reset("%All")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.AdminProbe).Capture(1), "Only an OcuTalon admin can change settings. Nothing was changed."_$Char(10), "a refusal prints its line")
	Do $$$AssertEquals($Get(^OcuTalonTest("AdminProbe", "sent"), 0), 0, "and submits nothing")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.AdminProbe).Capture("on"), "SetDemoMode takes 1 (on) or 0 (off). Nothing was changed."_$Char(10), "a bad argument prints its line")
}

/// A bad argument is invalid even for a caller without the role, and nothing is submitted; a good one from that caller is refused.
Method TestArgumentBeforeRole()
{
	Do ..Reset("")
	Set result = ##class(OcuTalon.Test.Core.AdminProbe).SetDemoMode(2)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|invalid", "a bad argument is invalid for a caller without the role")
	Set result = ##class(OcuTalon.Test.Core.AdminProbe).SetDemoMode(0)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", "a good argument is refused for that caller")
	Do $$$AssertEquals($Get(^OcuTalonTest("AdminProbe", "sent"), 0), 0, "nothing was submitted")
}

/// Clears the probe's global and sets the roles that the probe reports.
Method Reset(roles As %String) [ Private ]
{
	Kill ^OcuTalonTest("AdminProbe")
	Set ^OcuTalonTest("AdminProbe", "roles") = roles
}

/// The number of request headers from CommandsIn to the owner item, whatever their session.
ClassMethod Sent(owner As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SourceConfigName = ? AND TargetConfigName = ? AND Type = 1", "CommandsIn", owner)
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
