/// The base of the test classes that change the process zone (Story 1.10; DW-32). It saves the zone of the process before every test and puts it
/// back after every test, so that a test can set any zone, "no zone" included, and no test leaves one for the next. A class that extends it keeps
/// no copy of its own, and a class that overrides a hook calls ##super(testname).
///   - CurrentZone: the zone of the process, -1 for none;
///   - PutZone(saved): puts back a zone that CurrentZone gave, -1 as "no zone" (an empty zone), which the process takes as none.
/// It is abstract and holds no Test method, so ci/iris.sh runs no class of it.
Class OcuTalon.Test.Bridge.ZoneCase Extends %UnitTest.TestCase [ Abstract ]
{

/// The zone of the process before the test: -1 for none.
Property SavedZone As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SavedZone = ..CurrentZone()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..PutZone(..SavedZone)
	Quit $$$OK
}

/// The zone of the process: its name, or -1 when the process has none.
ClassMethod CurrentZone() As %String
{
	Quit $SYSTEM.Process.TimeZone()
}

/// Puts the zone of the process back as CurrentZone gave it: -1 becomes "", which is no zone.
ClassMethod PutZone(saved As %String)
{
	Do $SYSTEM.Process.TimeZone($Select(saved = -1: "", 1: saved))
}

}
