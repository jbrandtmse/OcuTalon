/// The evidence of an incident: a sample failed message and the failures per item. Lane A.
Class OcuTalon.Live.Payload.Part.IncidentEvidence Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The sample failed message's header id.
Property SampleHeaderId As %Integer(%JSONFIELDNAME = "sampleHeaderId");

/// The sample's error.
Property SampleError As %String(%JSONFIELDNAME = "sampleError", MAXLEN = 1000);

/// The failures per item.
Property Items As list Of OcuTalon.Live.Payload.Part.IncidentEvidenceItem(%JSONFIELDNAME = "items");

}
