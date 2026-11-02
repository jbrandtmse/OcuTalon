/// The payload of the breakfeed.progress live event: the state of a Break the feed run. Lane B publishes it.
Class OcuTalon.Live.Payload.BreakFeedProgress Extends (%RegisteredObject, %JSON.Adaptor)
{

/// One of sending, sent.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 32);

/// When the run started, UTC to the second.
Property StartedAt As %String(%JSONFIELDNAME = "startedAt", MAXLEN = 20);

/// The payload of a run: its state and start.
ClassMethod FromRow(run As OcuTalon.Data.BreakFeedRun) As OcuTalon.Live.Payload.BreakFeedProgress
{
	Set payload = ..%New()
	Set payload.State = run.State
	Set payload.StartedAt = run.StartedAt
	Quit payload
}

}
