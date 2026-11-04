/// The slots of a status condition. Lane B.
Class OcuTalon.Live.Payload.Part.StatusSlots Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The limit that applies.
Property Limit As %Integer(%JSONFIELDNAME = "limit");

/// The cap that applies, in US dollars.
Property Cap As %Numeric(%JSONFIELDNAME = "cap", SCALE = 6);

/// The time that applies, UTC to the second.
Property Time As %String(%JSONFIELDNAME = "time", MAXLEN = 20);

}
