/// A ReplyGuard whose pattern cannot be built, so that Filter's failure path runs (Test.Checks.Guard.TestFailsClosed). Test support only: it has no test.
Class OcuTalon.Test.Checks.BrokenGuard Extends OcuTalon.Checks.ReplyGuard
{

ClassMethod Pattern() As %String [ Private ]
{
	Throw ##class(%Exception.General).%New("BrokenGuard", 5001, , "The pattern of the test guard cannot be built")
}

}
