/// The trace targets of an incident (AD-12). Lane A.
Class OcuTalon.Live.Payload.Part.IncidentTraceTargets Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The trace of the diagnosis.
Property Diagnosis As OcuTalon.Live.Payload.Part.TraceTarget(%JSONFIELDNAME = "diagnosis");

/// The trace of the sample failed message.
Property Sample As OcuTalon.Live.Payload.Part.TraceTarget(%JSONFIELDNAME = "sample");

/// The trace of the first failure.
Property FirstFailure As OcuTalon.Live.Payload.Part.TraceTarget(%JSONFIELDNAME = "firstFailure");

}
