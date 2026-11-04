/// Tests of the start lock of the Production installer step as ReconcileIn reads it (Story 15.2, QA; AD-5, AD-23). Every production start
/// is reconciled exactly once: a start made by the step holds OcuTalon.Install.Step.Production STARTLOCK, and the item that finds it taken
/// (Starting) never reconciles; one that finds it free does. A lock is per process, so the holder is a job of its own (Hold), and the
/// test waits for the flag the job sets before it acts and for the job's release before it ends. Nothing here starts a production,
/// takes the lock in the test's own process or runs a reconcile.
///   - TestStartingSeesAnotherProcess: Starting() is 1 while another process holds the lock and 0 after it let go, and the probe leaves
///     the lock free (a third process takes it at once);
///   - TestItemDefersToTheStep: ReconcileIn's OnInit sets ByStep while the lock is held, its poll then does nothing (not Done, not
///     Warned, status OK), and the item started with the lock free has ByStep 0.
Class OcuTalon.Test.Install.StartLock Extends %UnitTest.TestCase
{

Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("StartLock", "n"))
	Quit $$$OK
}

/// Lets a holder that is still running go, and removes the flags.
Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..LetGo()
	Kill ^OcuTalonTest("StartLock", ..Number)
	Quit $$$OK
}

Method TestStartingSeesAnotherProcess()
{
	Set step = "OcuTalon.Install.Step.Production"
	Do $$$AssertEquals($ClassMethod(step, "Starting"), 0, "no process holds the start lock, so Starting is 0")
	If '..HoldLock() Quit
	Do $$$AssertEquals($ClassMethod(step, "Starting"), 1, "another process holds the start lock, so Starting is 1")
	Do ..LetGo()
	Do $$$AssertEquals($ClassMethod(step, "Starting"), 0, "the holder let go, so Starting is 0 again")
	Kill ^OcuTalonTest("StartLock", ..Number, "tried")
	Job ##class(OcuTalon.Test.Install.StartLock).TryLock(..Number)::10
	Do $$$AssertTrue($Test, "a job is started that tries the start lock")
	Set end = $ZHorolog + 10
	While '$Data(^OcuTalonTest("StartLock", ..Number, "tried")) && (end > $ZHorolog) {
		Hang 0.1
	}
	Do $$$AssertEquals($Get(^OcuTalonTest("StartLock", ..Number, "tried")), 1, "and the probe left the lock free for a third process")
}

Method TestItemDefersToTheStep()
{
	Set item = "class||OcuTalon.Install.ReconcileIn"
	If '..HoldLock() Quit
	Set held = ##class(Ens.Host).GetShadowInstance(item, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the item is made")
	If '$IsObject(held) Quit
	Do $$$AssertStatusOK(held.OnInit(), "OnInit runs while another process holds the start lock")
	Do $$$AssertEquals(held.ByStep, 1, "the item sees the start of the Production step")
	Set sc = held.OnProcessInput("", .output)
	Do $$$AssertStatusOK(sc, "its poll returns OK")
	Do $$$AssertEquals(held.Done_"|"_held.Warned, "0|0", "and reconciles and warns nothing, however long it waits")
	Set held.Started = $ZHorolog - 500
	Set sc = held.OnProcessInput("", .output)
	Do $$$AssertEquals(held.Done_"|"_held.Warned, "0|0", "also long after it started")

	Do ..LetGo()
	Set free = ##class(Ens.Host).GetShadowInstance(item, .sc)
	Do $$$AssertStatusOK(sc, "a second shadow instance of the item is made")
	If '$IsObject(free) Quit
	Do $$$AssertStatusOK(free.OnInit(), "OnInit runs with the start lock free")
	Do $$$AssertEquals(free.ByStep, 0, "the item then has ByStep 0, so its polls reconcile once the items run")
}

/// Starts the job that holds the start lock and waits until it does. 1 when it does.
Method HoldLock() As %Boolean [ Private ]
{
	Kill ^OcuTalonTest("StartLock", ..Number)
	Job ##class(OcuTalon.Test.Install.StartLock).Hold(..Number)::10
	Set started = $Test
	Do $$$AssertTrue(started, "a job is started that holds the start lock")
	If 'started Quit 0
	Set end = $ZHorolog + 10
	While '$Data(^OcuTalonTest("StartLock", ..Number, "held")) && (end > $ZHorolog) {
		Hang 0.1
	}
	Set held = $Data(^OcuTalonTest("StartLock", ..Number, "held")) > 0
	Do $$$AssertTrue(held, "and it holds it")
	Quit held
}

/// Tells the holder to let go and waits until it has.
Method LetGo() [ Private ]
{
	If '$Data(^OcuTalonTest("StartLock", ..Number, "held")) Quit
	Set ^OcuTalonTest("StartLock", ..Number, "release") = 1
	Set end = $ZHorolog + 30
	While $Data(^OcuTalonTest("StartLock", ..Number, "held")) && (end > $ZHorolog) {
		Hang 0.1
	}
	Do $$$AssertEquals($Data(^OcuTalonTest("StartLock", ..Number, "held")), 0, "the holder lets go")
}

/// The job that holds the start lock until the test sets the flag under release, for at most 30 seconds; the flag under held tells that
/// it does.
ClassMethod Hold(number As %Integer)
{
	Set lock = ##class(OcuTalon.Install.Step.Production).#STARTLOCK
	Lock +@lock:10
	If '$Test Quit
	Set ^OcuTalonTest("StartLock", number, "held") = 1
	Set end = $ZHorolog + 30
	While '$Data(^OcuTalonTest("StartLock", number, "release")) && (end > $ZHorolog) {
		Hang 0.1
	}
	Lock -@lock
	Kill ^OcuTalonTest("StartLock", number, "held")
}

/// The job that tries the start lock at once; the flag under tried is 1 when it gets it, and it lets go again.
ClassMethod TryLock(number As %Integer)
{
	Set lock = ##class(OcuTalon.Install.Step.Production).#STARTLOCK
	Lock +@lock:0
	Set got = $Test
	If got Lock -@lock
	Set ^OcuTalonTest("StartLock", number, "tried") = got
}

}
