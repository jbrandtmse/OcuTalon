/// Whether Break the feed can be pressed, and how the last batch is doing (AD-12). Lane B publishes it in guide.state.
Class OcuTalon.Live.Payload.Part.GuideBreakFeed Extends (%RegisteredObject, %JSON.Adaptor)
{

/// True when Break the feed can be pressed.
Property Active As %Boolean(%JSONFIELDNAME = "active") [ InitialExpression = 0 ];

/// Why it can't be pressed: not_watching or incident_in_progress; empty when it can.
Property Reason As %String(%JSONFIELDNAME = "reason", MAXLEN = 32);

/// How the current run's batch is doing: sending, waiting, still_waiting, no_notice or notice_arrived; empty when the
/// current guide run has no batch.
Property Stage As %String(%JSONFIELDNAME = "stage", MAXLEN = 32);

/// When the current run's batch started, UTC to the second; empty with no stage.
Property StartedAt As %String(%JSONFIELDNAME = "startedAt", MAXLEN = 20);

}
