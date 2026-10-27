/// The payload of the guide.state live event: the guide as the server computes it (Demo.Guide.Compute, AD-12). Lane B publishes it.
Class OcuTalon.Live.Payload.GuideState Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The guide run; it rises with Run again.
Property RunEpoch As %Integer(%JSONFIELDNAME = "runEpoch");

/// The current guide step.
Property Step As %Integer(%JSONFIELDNAME = "step");

/// True when the guide is finished.
Property Finished As %Boolean(%JSONFIELDNAME = "finished") [ InitialExpression = 0 ];

/// The five steps in order, each with whether it is done.
Property Steps As list Of OcuTalon.Live.Payload.Part.GuideStep(%JSONFIELDNAME = "steps");

/// Whether Break the feed can be pressed and how the last batch is doing.
Property BreakFeed As OcuTalon.Live.Payload.Part.GuideBreakFeed(%JSONFIELDNAME = "breakFeed");

/// What step 4 shows: paired, unpaired, rejected, fallback or no_fix.
Property Step4Variant As %String(%JSONFIELDNAME = "step4Variant", MAXLEN = 32);

/// True when the guide shows the Telegram row of step 1.
Property TelegramRow As %Boolean(%JSONFIELDNAME = "telegramRow") [ InitialExpression = 0 ];

/// The trace step's target: the trace session of the incident noticed in the current run (AD-26); absent before one.
Property Trace As OcuTalon.Live.Payload.Part.TraceTarget(%JSONFIELDNAME = "trace");

/// The current run's total, only while the guide is finished.
Property Run As OcuTalon.Live.Payload.Part.GuideRun(%JSONFIELDNAME = "run");

}
