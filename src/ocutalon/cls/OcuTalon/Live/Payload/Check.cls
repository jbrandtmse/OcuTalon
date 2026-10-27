/// The payload of the check live event: one background check. Lane A publishes it.
Class OcuTalon.Live.Payload.Check Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The check's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// The kind of check.
Property Kind As %String(%JSONFIELDNAME = "kind", MAXLEN = 32);

/// The namespace of the watched production.
Property Namespace As %String(%JSONFIELDNAME = "namespace", MAXLEN = 128);

/// The watched production class.
Property Production As %String(%JSONFIELDNAME = "production", MAXLEN = 128);

/// The production's display name.
Property DisplayName As %String(%JSONFIELDNAME = "displayName", MAXLEN = 128);

/// True only in the last event of a check whose watch was stopped; the page drops it.
Property Stopped As %Boolean(%JSONFIELDNAME = "stopped") [ InitialExpression = 0 ];

/// When the check runs next, UTC to the second.
Property NextDueAt As %String(%JSONFIELDNAME = "nextDueAt", MAXLEN = 20);

/// When the check last ran, UTC to the second.
Property LastRunAt As %String(%JSONFIELDNAME = "lastRunAt", MAXLEN = 20);

/// One of Msg.Enum CHECKRESULT.
Property Result As %String(%JSONFIELDNAME = "result", MAXLEN = 32);

/// What the last run found.
Property Finding As %String(%JSONFIELDNAME = "finding", MAXLEN = 1000);

/// The check's trace session id (AD-26): the heartbeat Tick's session of its latest run.
Property TraceHeaderId As %Integer(%JSONFIELDNAME = "traceHeaderId");

/// The namespace that holds the trace: OcuTalon's own, where the run's session is.
Property TraceNamespace As %String(%JSONFIELDNAME = "traceNamespace", MAXLEN = 128);

/// The payload for a check row, with every row-backed field set. Checks and /state both build a check's payload here, so an event and the
/// snapshot can't drift. stopped is false: only the last event of a stopped watch carries it. The trace is the latest run's, which is the
/// session of the heartbeat Tick in this namespace (AD-26, UX-DR139), so when LastRunHeaderId is set traceHeaderId is that id and
/// traceNamespace is $Namespace, and a row with no run carries neither.
ClassMethod FromRow(row As OcuTalon.Data.BackgroundCheck) As OcuTalon.Live.Payload.Check
{
	Set payload = ..%New()
	Set payload.Ref = row.Ref
	Set payload.Kind = row.Kind
	Set payload.Namespace = row.Namespace
	Set payload.Production = row.Production
	Set payload.DisplayName = row.DisplayName
	Set payload.Stopped = 0
	Set payload.NextDueAt = row.NextDueAt
	Set payload.LastRunAt = row.LastRunAt
	Set payload.Result = row.Result
	Set payload.Finding = row.Finding
	If row.LastRunHeaderId '= "" {
		Set payload.TraceHeaderId = row.LastRunHeaderId
		Set payload.TraceNamespace = $Namespace
	}
	Quit payload
}

}
