/// Tests of Core.Commands.Submit and of the Lane B stubs of the cross-lane APIs (Story 0.6, matrix rows 8 and 9). No
/// production runs on the slot, so the send at the end of Submit fails there and these tests assert only what Submit decides
/// before it sends: the origin that the command carries, and the refusals.
///   - TestOrigin: outside a bridge context the command carries the origin argument, inside one it carries "tool", and an
///     origin that is not in the enumeration is refused naming it, whatever the payload said;
///   - TestRefusals: an object that is not a command is refused naming the problem;
///   - TestOmittedArguments: a left-out origin or command is an error status, not a thrown error;
///   - TestStubs: Recipients gives "", and TurnCost of an unknown turn gives {} with an error (the totals are tested by
///     Test.Data.Ownership).
/// The run's number is n from ^OcuTalonTest("Commands","n") (never reset); the context of the test process is ended before
/// and after the tests.
Class OcuTalon.Test.Core.Commands Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Number = $Increment(^OcuTalonTest("Commands", "n"))
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Quit $SYSTEM.Status.OK()
}

/// Row 8: a command whose payload says web_admin carries web_user after Submit(command, "web_user") outside a context.
/// Inside a context, whatever the argument, it carries "tool". An origin that is not in Msg.Enum ORIGIN ("zz" or "") is
/// an error that names it, and the command keeps the origin it had. The status of the send is not asserted.
Method TestOrigin()
{
	Set command = ..NewCommand()
	Do $$$AssertEquals(command.Origin, "web_admin", "the payload says web_admin")
	Do ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
	Do $$$AssertEquals(command.Origin, "web_user", "outside a context the origin is the argument, not the payload's")

	Set command = ..NewCommand()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(##class(OcuTalon.Bridge.Msg.Request).%New(), "zzss"_..Number), "a context begins")
	Try {
		Do ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
		Do $$$AssertEquals(command.Origin, "tool", "inside a context the origin is tool, whatever the argument")
		Set command = ..NewCommand()
		Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "zz", .result)
		Do $$$AssertEquals(command.Origin, "tool", "inside a context an origin outside the enumeration is not looked at")
	} Catch exception {
		Do $$$AssertTrue(0, "Submit inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "the context ends")

	For origin = "zz"_..Number, "" {
		Set command = ..NewCommand()
		Set sc = ##class(OcuTalon.Core.Commands).Submit(command, origin, .result)
		Do $$$AssertStatusNotOK(sc, "the origin '"_origin_"' is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ("'"_origin_"'"), "the error names the origin: "_$SYSTEM.Status.GetErrorText(sc))
		Do $$$AssertEquals(command.Origin, "web_admin", "the command keeps the origin it had")
		Do $$$AssertEquals(result, "", "and there is no result")
	}
	For origin = "web_user", "web_admin", "telegram", "tool", "timer", "system" {
		Set command = ..NewCommand()
		Set command.Origin = $Select(origin = "system": "web_user", 1: "system")
		Do ##class(OcuTalon.Core.Commands).Submit(command, origin, .result)
		Do $$$AssertEquals(command.Origin, origin, "the origin "_origin_" is accepted and replaces the payload's")
	}
}

/// An origin that is left out is refused like an empty one: with an error status that names the problem, and the command
/// keeps its origin. A command that is left out is refused too.
Method TestOmittedArguments()
{
	Set command = ..NewCommand()
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, , .result)
	Do $$$AssertStatusNotOK(sc, "an omitted origin is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "is not one of", "the error says why: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(command.Origin, "web_admin", "the command keeps the origin it had")
	Set sc = ##class(OcuTalon.Core.Commands).Submit()
	Do $$$AssertStatusNotOK(sc, "an omitted command is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Msg.Command", "the error names what Submit takes: "_$SYSTEM.Status.GetErrorText(sc))
}

/// An object that is not a command is refused with an error that names the problem; so is a value that is not an object.
/// The test starts with no context, and a refusal leaves none behind.
Method TestRefusals()
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set sc = ##class(OcuTalon.Core.Commands).Submit({"origin": "web_admin"}, "web_user", .result)
	Do $$$AssertStatusNotOK(sc, "a dynamic object is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Msg.Command", "the error names what Submit takes: "_$SYSTEM.Status.GetErrorText(sc))
	Set sc = ##class(OcuTalon.Core.Commands).Submit(##class(OcuTalon.Msg.CommandResult).%New(), "web_user", .result)
	Do $$$AssertStatusNotOK(sc, "a message of another class is refused")
	Set sc = ##class(OcuTalon.Core.Commands).Submit("zz"_..Number, "web_user", .result)
	Do $$$AssertStatusNotOK(sc, "a string is refused")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "no context is left behind")
}

/// Row 9 for Lane B: Recipients gives "", with and without an incident; TurnCost of a turn that does not exist gives {} with an
/// error status, and so does RunCost for a session that is not one.
Method TestStubs()
{
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Recipients("zzowner"_..Number), "", "Recipients gives an empty list")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Recipients("zzowner"_..Number, "zzincident"), "", "also for an incident")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnCost("zzturn"_..Number, .sc).%ToJSON(), "{}", "TurnCost of an unknown turn gives an empty object")
	Do $$$AssertStatusNotOK(sc, "and an error status")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnCost("zzturn"_..Number).%ToJSON(), "{}", "also when the caller passes no status")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RunCost("", "2026-10-19T00:00:00Z", .sc).%ToJSON(), "{}", "RunCost with no session gives an empty object")
	Do $$$AssertStatusNotOK(sc, "and an error status")
}

/// --- helpers ---
/// A ListReminders command whose payload says web_admin.
ClassMethod NewCommand() As OcuTalon.Msg.Command.ListReminders [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.ListReminders).%New()
	Set command.Origin = "web_admin"
	Quit command
}

}
