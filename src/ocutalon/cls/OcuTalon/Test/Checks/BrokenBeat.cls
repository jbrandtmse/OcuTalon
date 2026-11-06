/// A Checks.Beat whose snapshot read fails, so that the failed-read path runs (Test.Checks.Snapshot.TestFailedRead). The read named in the process global
/// ^||OcuTalon.BrokenBeat throws, and every read does when it is empty; any other read is Beat's own. Test support only: it has no test.
Class OcuTalon.Test.Checks.BrokenBeat Extends OcuTalon.Checks.Beat
{

ClassMethod Read(what As %String, sessionRef As %String, arg As %String = "") [ Private ]
{
	Set only = $Get(^||OcuTalon.BrokenBeat)
	If (only = "") || (only = what) Throw ##class(%Exception.General).%New("BrokenBeat", 5001, , "The test snapshot cannot read "_what)
	Quit ##super(what, sessionRef, arg)
}

/// The read as Beat does it (the named read is not the broken one), for a test of Beat's own error handling: the read that Beat's own Read throws on.
ClassMethod ReadOf(what As %String, sessionRef As %String, arg As %String = "")
{
	Quit ..Read(what, sessionRef, arg)
}

}
