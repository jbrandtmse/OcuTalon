/// Tests of how Core.Commands.Submit meets the bridge context (Story 0.6, matrix row 8, AD-1): the context belongs to one
/// process, so Submit sets the origin "tool" only in the process that has a context, and it leaves that context as it found it.
/// No production runs on the slot, so the send at the end of Submit fails there; these tests assert the origin that the command
/// carries and the state of the context, never the status of the send.
///   - TestContextIsPerProcess: while this process holds a context, a second job without one submits with the origin of its
///     caller; a second job that begins its own context submits with "tool"; after it ends that context it submits with the
///     origin of its caller again; this process keeps its context throughout;
///   - TestSubmitLeavesTheContext: after a Submit inside a context, the context is still active and holds the fields, the
///     taint and the host data it held before, and a refused Submit changes nothing either.
/// The run's number is n from ^OcuTalonTest("CommandsContext","n") (never reset); the child job reports through
/// ^OcuTalonTest("CommandsContext",n,...), which OnBeforeAllTests and OnAfterAllTests delete with the reports of earlier runs.
Class OcuTalon.Test.Core.CommandsContext Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..CleanRuns()
	Set ..Number = $Increment(^OcuTalonTest("CommandsContext", "n"))
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..CleanRuns()
	Quit $SYSTEM.Status.OK()
}

/// A job that has no context submits with the origin it names while this process holds one; a job that begins its own
/// context submits with "tool"; once that job ends its context it submits with the origin it names again.
Method TestContextIsPerProcess()
{
	Set super = "zzss"_..Number
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(##class(OcuTalon.Bridge.Msg.Request).%New(), super), "this process begins a context")
	Set run = $Name(^OcuTalonTest("CommandsContext", ..Number))
	Kill @run
	Try {
		Job ##class(OcuTalon.Test.Core.CommandsContext).SubmitProbe(..Number)
		Do ..WaitFor($Name(@run@("done")), 1, 60)
		Do $$$AssertEquals($Get(@run@("done")), 1, "the job finished")
		Do $$$AssertEquals($Get(@run@("error")), "", "the job threw nothing")
		Do $$$AssertEquals($Get(@run@("active")), 0, "the job starts with no context")
		Do $$$AssertEquals($Get(@run@("plain")), "web_user", "a job with no context submits with the origin it names, whatever this process holds")
		Do $$$AssertEquals($Get(@run@("own")), "tool", "a job with a context of its own submits with tool")
		Do $$$AssertEquals($Get(@run@("afterEnd")), "web_admin", "the same job submits with the origin it names once its context has ended")
		Do $$$AssertEquals($Get(@run@("refused")), 1, "and an origin outside the enumeration is refused there")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 1, "this process still holds its context")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().SuperSession, super, "and it is the one it began")
	} Catch exception {
		Do $$$AssertTrue(0, "the test threw: "_exception.DisplayString())
	}
	Kill @run
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "the context ends")
}

/// Submit changes nothing in the context of its process, for an accepted origin and for a refused one.
Method TestSubmitLeavesTheContext()
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.OwnerRef = "zzowner"_..Number
	Set request.ItemId = "zzitem"_..Number
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "zzss"_..Number), "a context begins")
	Do ##class(OcuTalon.Bridge.Context).Put("Tainted", 1)
	Do ##class(OcuTalon.Bridge.Context).Put("HostData", "{""rows"":[]}")
	Try {
		Set before = ..Snapshot()
		Set command = ##class(OcuTalon.Msg.Command.ListReminders).%New()
		Set command.Origin = "web_admin"
		Do ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
		Do $$$AssertEquals(command.Origin, "tool", "Submit inside the context sets tool")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 1, "the context is still active after Submit")
		Do $$$AssertEquals(..Snapshot(), before, "and holds every field, the taint and the host data it held")
		Do ##class(OcuTalon.Core.Commands).Submit("not a command", "web_user", .result)
		Do $$$AssertEquals(..Snapshot(), before, "a refused Submit leaves the context alone too")
	} Catch exception {
		Do $$$AssertTrue(0, "the test threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
}

/// The job body of TestContextIsPerProcess. It reports the origin that a command carries after Submit, in three states of
/// its own context: none, begun and ended.
ClassMethod SubmitProbe(number As %Integer)
{
	Set run = $Name(^OcuTalonTest("CommandsContext", number))
	Try {
		Set @run@("active") = ##class(OcuTalon.Bridge.Context).Active()
		Set command = ..NewCommand()
		Do ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
		Set @run@("plain") = command.Origin
		Do ##class(OcuTalon.Bridge.Context).Begin(##class(OcuTalon.Bridge.Msg.Request).%New(), "zzchild"_number)
		Set command = ..NewCommand()
		Do ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
		Set @run@("own") = command.Origin
		Do ##class(OcuTalon.Bridge.Context).End()
		Set command = ..NewCommand()
		Do ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
		Set @run@("afterEnd") = command.Origin
		Set command = ..NewCommand()
		Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "zz"_number, .result)
		Set @run@("refused") = ($SYSTEM.Status.IsError(sc) && (command.Origin = "web_admin"))
	} Catch exception {
		Set @run@("error") = exception.DisplayString()
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Set @run@("done") = 1
}

/// --- helpers ---
/// A ListReminders command whose payload says web_admin.
ClassMethod NewCommand() As OcuTalon.Msg.Command.ListReminders [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.ListReminders).%New()
	Set command.Origin = "web_admin"
	Quit command
}

/// Every field of the current context as one line.
ClassMethod Snapshot() As %String [ Private ]
{
	Set context = ##class(OcuTalon.Bridge.Context).Current()
	If '$IsObject(context) Quit "<none>"
	Set text = ""
	For i = 1:1:$Length(##class(OcuTalon.Bridge.Context).#FIELDS, ",") {
		Set name = $Piece(##class(OcuTalon.Bridge.Context).#FIELDS, ",", i)
		Set text = text _ name _ "=" _ $Property(context, name) _ ";"
	}
	Quit text
}

/// Deletes the reports of every run, this one and the runs that failed before: every node under the counter's level except
/// the counter itself.
ClassMethod CleanRuns() [ Private ]
{
	Set run = ""
	For {
		Set run = $Order(^OcuTalonTest("CommandsContext", run))
		Quit:run=""
		If run '= "n" Kill ^OcuTalonTest("CommandsContext", run)
	}
}

/// Waits up to seconds for the global node named by ref to reach count.
ClassMethod WaitFor(ref As %String, count As %Integer, seconds As %Integer) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While (+$Get(@ref) < count) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

}
