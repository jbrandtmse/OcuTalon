/// A fixture for a stack where the evaluation set is not mounted, for the test that the folder given to Install can only narrow its guard (Story 9.9;
/// AD-22, CON-3). Its Mount is a folder that does not exist. It is not a test case (it has no test method), and only Test.Eval.FeedGrant uses it, in a
/// throwaway.
Class OcuTalon.Test.Eval.Feed.UnmountedFixture Extends OcuTalon.Test.Eval.Feed.Fixture
{

/// A folder that does not exist.
ClassMethod Mount() As %String
{
	Quit "/tmp/zz-eval-feed-unmounted/"
}

}
