/// A fixture whose production does not exist, for the tests of what a failed Install leaves behind (Story 9.9; AD-22, CON-3). Install makes the resource,
/// the database, the namespace, the mapping, Interoperability and the grant, as Fixture does, and then fails when it loads the production. It is not a test
/// case (it has no test method), and only Test.Eval.FeedGrant uses it, in a throwaway.
Class OcuTalon.Test.Eval.Feed.BrokenFixture Extends OcuTalon.Test.Eval.Feed.Fixture
{

/// The name of a production class that does not exist.
Parameter PRODUCTION = "OcuTalon.Test.Eval.Feed.NoSuchProduction";

}
