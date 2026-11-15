/// Checks.Coverage with one seam under test control (test only; Story 22.11, DW-1346). Test.Mcp.SourceRun TestSlowQueueOfThreeNotStale calls Build of this class, so that
/// a source row of another session or test in the install does not change the allowance it checks, while the count of the test's own rows stays Coverage's.
/// It is not an item of any production.
///   - PollingSources is Coverage's own count less ^||SourceRunCoverage("others"), the sources of the install that are not the test's and not stopped, which the test
///     sets just before each Build (0 when it is not set).
Class OcuTalon.Test.Mcp.SourceRunCoverage Extends OcuTalon.Checks.Coverage
{

ClassMethod PollingSources() As %Integer [ Private ]
{
	Quit ##super() - $Get(^||SourceRunCoverage("others"))
}

/// Sets the number of the sources of the install that are not the test's and not stopped, which PollingSources leaves out.
ClassMethod Others(count As %Integer)
{
	Set ^||SourceRunCoverage("others") = +count
}

/// Forgets the number that Others set.
ClassMethod Reset()
{
	Kill ^||SourceRunCoverage
}

}
