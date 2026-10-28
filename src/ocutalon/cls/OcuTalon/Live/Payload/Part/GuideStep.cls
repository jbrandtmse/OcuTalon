/// One step of the demo guide as the server derives it (AD-12): its number and whether it is done. Lane B publishes it in guide.state.
Class OcuTalon.Live.Payload.Part.GuideStep Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The step's number, 1 to 5.
Property Step As %Integer(%JSONFIELDNAME = "step");

/// True when the step is done.
Property Done As %Boolean(%JSONFIELDNAME = "done") [ InitialExpression = 0 ];

}
