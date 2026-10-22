/// The runner's adapter with one more method, for Test.Bridge.Runner: StatsOf calls the adapter's private ReadStats, which reads the
/// stats of an AI session and gives "" with a warning when the session cannot be read. Nothing else differs from the adapter.
Class OcuTalon.Test.Bridge.ZzStatsAdapter Extends OcuTalon.Bridge.Adapter.Agent
{

/// ReadStats of the session.
Method StatsOf(session As %RegisteredObject) As %DynamicObject
{
	Quit ..ReadStats(session)
}

}
