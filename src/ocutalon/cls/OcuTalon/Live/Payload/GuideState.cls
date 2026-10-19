/// The payload of the guide.state live event: the guide as the server computes it. Lane B publishes it.
Class OcuTalon.Live.Payload.GuideState Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The guide run; it rises with Run again.
Property RunEpoch As %Integer(%JSONFIELDNAME = "runEpoch");

/// The current guide step.
Property Step As %Integer(%JSONFIELDNAME = "step");

/// True when the guide is finished.
Property Finished As %Boolean(%JSONFIELDNAME = "finished") [ InitialExpression = 0 ];

}
