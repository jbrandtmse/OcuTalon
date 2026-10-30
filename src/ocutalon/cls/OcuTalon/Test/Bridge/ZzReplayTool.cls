/// The tools of the replay tests (Story 30.3; AD-6, AD-10): a test fixture, never part of a production, and never in the package OcuTalon.Tools.
/// Both tools are risky in code, so the gate holds a call of either. A run of zz_replay_send is counted in ^OcuTalonTest("Replay","ran",<the tool's
/// name>), the job-independent counter that the tests read from the runner's job, and answers {"note":"ZZ-REPLAY-RESULT-5182"} (NOTE), the marker
/// that must reach no column, no reply and no event. zz_replay_throw raises an error when it runs, after it has been counted. A tool method runs
/// inside AI Hub's callback, so it makes no AI Hub call and no Python call (AD-6).
Class OcuTalon.Test.Bridge.ZzReplayTool Extends %AI.Tool
{

/// The text that zz_replay_send answers; no test row, reply or event may hold it.
Parameter NOTE = "ZZ-REPLAY-RESULT-5182";

Parameter CLASSIFICATIONZZREPLAYSEND = "risky";

Parameter CLASSIFICATIONZZREPLAYTHROW = "risky";

/// Risky: counts the run and answers the marker. The arguments are read and dropped.
ClassMethod Send(a As %String = "", b As %Integer = "") As %DynamicObject
{
	Do ..Mark("zz_replay_send")
	Quit {"note": (..#NOTE)}
}

/// Risky: counts the run and raises an error.
ClassMethod Throws() As %DynamicObject
{
	Do ..Mark("zz_replay_throw")
	$$$ThrowStatus($SYSTEM.Status.Error(5001, "ZZ-REPLAY-THROW"))
}

/// Records that the tool ran in ^OcuTalonTest("Replay","ran",name), which counts the runs.
ClassMethod Mark(name As %String) [ Private ]
{
	Set count = $Increment(^OcuTalonTest("Replay", "ran", name))
}

/// The number of runs of the tool since the counter was last killed.
ClassMethod Ran(name As %String) As %Integer
{
	Quit +$Get(^OcuTalonTest("Replay", "ran", name))
}

}
