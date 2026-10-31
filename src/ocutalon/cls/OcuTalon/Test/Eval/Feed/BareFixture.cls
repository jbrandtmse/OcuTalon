/// A fixture that starts no production, for the tests of the feed's grant (Story 9.9; AD-22, CON-3). Install makes the resource, the database, the
/// namespace, the mapping, Interoperability and the grant, as Fixture does, and returns OK without loading or starting the production, so that a test
/// reads the security objects of an installed feed without the seconds that the production takes to start and to stop. It is not a test case (it has no
/// test method), and only Test.Eval.FeedGrant uses it, in a throwaway.
Class OcuTalon.Test.Eval.Feed.BareFixture Extends OcuTalon.Test.Eval.Feed.Fixture
{

/// Starts nothing.
ClassMethod StartProduction() As %Status [ Private ]
{
	Quit $$$OK
}

}
