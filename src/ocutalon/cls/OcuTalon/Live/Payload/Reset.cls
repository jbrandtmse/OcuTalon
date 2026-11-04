/// The payload of the reset live event: the reset schedule. Lane B publishes it.
Class OcuTalon.Live.Payload.Reset Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The next scheduled reset, UTC to the second.
Property NextReset As %String(%JSONFIELDNAME = "nextReset", MAXLEN = 20);

}
