/// The payload of the watch.progress live event: how far an incident has come before its notice (AD-15). Lane A publishes it, through IncidentManager.
Class OcuTalon.Live.Payload.WatchProgress Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The stages before the notice (AD-15).
Parameter STAGES = "noticed,settling,diagnosing";

/// The incident's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// One of STAGES.
Property Stage As %String(%JSONFIELDNAME = "stage", MAXLEN = 32);

}
