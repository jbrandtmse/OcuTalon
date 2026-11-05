/// The payload of the heartbeat live event: one person's heartbeat, the public view of their HeartbeatBeat row and their settings. Lane A publishes it (Checks,
/// after each commit of the row, AD-12, AD-33). The one exception is a Tick's skip because the checklist is empty, which saves its row and publishes nothing; a run now
/// still publishes. Story 39.2's GET reuses FromRow, so that the event and the GET can't drift. It never holds the SessionRef (the
/// person is the stream), the checklist's text, the snapshot keys, the Item's Id or the decision's Ref, and no rendered text.
Class OcuTalon.Live.Payload.Heartbeat Extends (%RegisteredObject, %JSON.Adaptor)
{

/// True when the person's heartbeat is on.
Property On As %Boolean(%JSONFIELDNAME = "on") [ InitialExpression = 0 ];

/// The minutes between the beats.
Property Interval As %Integer(%JSONFIELDNAME = "interval");

/// The start of the active hours, HH:MM (empty with the end for all day).
Property From As %String(%JSONFIELDNAME = "from", MAXLEN = 5);

/// The end of the active hours, HH:MM.
Property To As %String(%JSONFIELDNAME = "to", MAXLEN = 5);

/// When the next beat is due, UTC to the second.
Property NextDueAt As %String(%JSONFIELDNAME = "nextDueAt", MAXLEN = 20);

/// When the last beat ran, UTC to the second.
Property LastBeatAt As %String(%JSONFIELDNAME = "lastBeatAt", MAXLEN = 20);

/// The outcome of the last beat's decision.
Property LastOutcome As %String(%JSONFIELDNAME = "lastOutcome", MAXLEN = 32);

/// True when the last beat's decision was a fallback.
Property LastFallback As %Boolean(%JSONFIELDNAME = "lastFallback") [ InitialExpression = 0 ];

/// The cost in USD of the last beat's decision.
Property LastCostUSD As %Numeric(%JSONFIELDNAME = "lastCostUSD", SCALE = 6);

/// The last beat's decision trace session id (AD-26).
Property TraceHeaderId As %Integer(%JSONFIELDNAME = "traceHeaderId");

/// The namespace that holds the trace.
Property TraceNamespace As %String(%JSONFIELDNAME = "traceNamespace", MAXLEN = 128);

/// When the last beat was skipped, UTC to the second.
Property LastSkipAt As %String(%JSONFIELDNAME = "lastSkipAt", MAXLEN = 20);

/// Why the last beat was skipped.
Property LastSkipReason As %String(%JSONFIELDNAME = "lastSkipReason", MAXLEN = 32);

/// When the person last asked for a run, UTC to the second.
Property LastRunNowAt As %String(%JSONFIELDNAME = "lastRunNowAt", MAXLEN = 20);

/// No beat runs before this time, UTC to the second.
Property BackoffUntil As %String(%JSONFIELDNAME = "backoffUntil", MAXLEN = 20);

/// The payload for a person: on, interval, from and to are the settings in values (Checks.Beat.Values), and, when row is an object, every row-backed field is the
/// row's own. traceHeaderId is the row's LastTraceSessionId and traceNamespace is the current namespace, both only when that id is set (AD-12, AD-26). With no row
/// (row is "", a person with no beat yet) the payload holds only the settings, and lastFallback is empty so that it is left out of the JSON. The SessionRef,
/// the checklist, the snapshot keys, LastItemId and LastDecisionRef are never copied.
ClassMethod FromRow(row As OcuTalon.Data.HeartbeatBeat, values As %DynamicObject) As OcuTalon.Live.Payload.Heartbeat
{
	Set payload = ..%New()
	Set payload.On = values.on
	Set payload.Interval = values.interval
	Set payload.From = values.from
	Set payload.To = values.to
	If '$IsObject(row) {
		Set payload.LastFallback = ""
		Quit payload
	}
	Set payload.NextDueAt = row.NextDueAt
	Set payload.LastBeatAt = row.LastBeatAt
	Set payload.LastOutcome = row.LastOutcome
	Set payload.LastFallback = row.LastFallback
	Set payload.LastCostUSD = row.LastCostUSD
	If row.LastTraceSessionId '= "" {
		Set payload.TraceHeaderId = row.LastTraceSessionId
		Set payload.TraceNamespace = $Namespace
	}
	Set payload.LastSkipAt = row.LastSkipAt
	Set payload.LastSkipReason = row.LastSkipReason
	Set payload.LastRunNowAt = row.LastRunNowAt
	Set payload.BackoffUntil = row.BackoffUntil
	Quit payload
}

}
