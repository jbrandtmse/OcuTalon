/// A runner adapter that counts the throwaway-session calls of a replay (Story 30.3; AD-6, DW-452): a test fixture, never part of a production.
/// Test.Bridge.Runner puts it in a shadow runner's Adapter property, so the real Answer and Replay.Run use it. It changes nothing: each override
/// notes what it saw in the process-private ^||ZzSpy and then calls the adapter's own method. ^||ZzSpy("new") and ^||ZzSpy("release") count the
/// calls; ^||ZzSpy("ranAtNew") and ^||ZzSpy("ranAtRelease") hold the runs of zz_replay_send when each call came (so the order is read from data, not
/// from the source text); ^||ZzSpy("heldBefore") and ^||ZzSpy("heldAfter") are 1 while the agent holds an AI session just before and just after the release.
Class OcuTalon.Test.Bridge.ZzSpyAdapter Extends OcuTalon.Bridge.Adapter.Agent
{

Method NewSession(Output session As %AI.Agent.Session) As %Status
{
	Set count = $Increment(^||ZzSpy("new"))
	Set ^||ZzSpy("ranAtNew") = ##class(OcuTalon.Test.Bridge.ZzReplayTool).Ran("zz_replay_send")
	Set sc = ##super(.session)
	Set ^||ZzSpy("heldAfterNew") = $IsObject(..Agent) && $IsObject(..Agent.Session)
	Quit sc
}

Method ReleaseThrowaway()
{
	Set count = $Increment(^||ZzSpy("release"))
	Set ^||ZzSpy("ranAtRelease") = ##class(OcuTalon.Test.Bridge.ZzReplayTool).Ran("zz_replay_send")
	Set ^||ZzSpy("heldBefore") = $IsObject(..Agent) && $IsObject(..Agent.Session)
	Do ##super()
	Set ^||ZzSpy("heldAfter") = $IsObject(..Agent) && $IsObject(..Agent.Session)
}

}
