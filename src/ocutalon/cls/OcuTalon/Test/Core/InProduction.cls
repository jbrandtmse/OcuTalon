/// The base of the test classes that run over the running production. THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21):
/// they need the running OcuTalon.Production, which a slot never has. Where it does not run, every test fails with that reason
/// (Guard), so that a broken start can never give a green shard. Each fixture session comes from Session: its Ref is kept for
/// the clean-up and its TraceRef is a SuperSession of the run. OnAfterAllTests ends the context of the test process, removes
/// the run's headers, bodies and event-log rows by those SuperSessions (Fixture.RemoveMessages) and removes the fixture rows
/// (Fixture.Clean). The run's number is n from ^OcuTalonTest(<the last piece of the class name>, "n") (never reset). It has no
/// Test methods.
Class OcuTalon.Test.Core.InProduction Extends %UnitTest.TestCase [ Abstract ]
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The start of the user name of each fixture session; the run's number and the test's name follow it.
Parameter SESSIONPREFIX = "zzprod";

/// The run's number.
Property Number As %Integer;

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 200);

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the fixture sessions of the run, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The SuperSessions of the run's messages.
Property Supers As %DynamicArray;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Number = $Increment(^OcuTalonTest($Piece($ClassName($This), ".", *), "n"))
	Set ..Refs = ""
	Set ..Sessions = ""
	Set ..Supers = []
	Set ..Missing = ""
	If '##class(Ens.Director).IsProductionRunning(.name) {
		Set ..Missing = "No production runs in "_$Namespace_": this class runs in throwaways and CI only (Rule 21)"
	} ElseIf name '= ..#PRODUCTION {
		Set ..Missing = "The production that runs is "_name_", not "_..#PRODUCTION
	}
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	If ..Missing = "" Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Supers)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
}

/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// A fixture session; its Ref is kept for the clean-up, and its TraceRef is a SuperSession of the run.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session(..#SESSIONPREFIX_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Do ..Supers.%Push(##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef)
	Quit ref
}

}
