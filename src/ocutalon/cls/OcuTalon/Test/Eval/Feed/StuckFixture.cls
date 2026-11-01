/// A fixture whose removal fails before it reaches the namespace, for the test that Remove takes the grant back first (Story 9.9; AD-22, AD-24, CON-3).
/// Its RemoveSystem removes nothing and returns an error, as a removal does whose first step fails. It is not a test case (it has no test method), and
/// only Test.Eval.FeedGrant uses it, in a throwaway, before Fixture's own Remove leaves nothing.
Class OcuTalon.Test.Eval.Feed.StuckFixture Extends OcuTalon.Test.Eval.Feed.Fixture
{

/// Removes nothing and fails.
ClassMethod RemoveSystem() As %Status [ Private ]
{
	Quit $$$ERROR($$$GeneralError, "The removal of the test feed stopped before the namespace (StuckFixture)")
}

}
