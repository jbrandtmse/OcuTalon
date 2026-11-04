/// The runner's adapter with two more methods, for Test.Bridge.Runner: StatsOf calls the adapter's private ReadStats, which reads the
/// stats of an AI session and gives "" with a warning when the session cannot be read, and FailureOf calls its private FailureText, which
/// makes the redacted, cut failure text of a Chat that threw. Nothing else differs from the adapter.
Class OcuTalon.Test.Bridge.ZzStatsAdapter Extends OcuTalon.Bridge.Adapter.Agent
{

/// ReadStats of the session.
Method StatsOf(session As %RegisteredObject) As %DynamicObject
{
	Quit ..ReadStats(session)
}

/// FailureText of the exception, for the request.
Method FailureOf(thrown As %Exception.AbstractException, request As OcuTalon.Bridge.Msg.Request) As %String
{
	Quit ..FailureText(thrown, request)
}

}
