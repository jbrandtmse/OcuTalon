/// The singular and plural noun for the items of an incident or a dry run (AD-15). Shared by both lanes, owned by Lane B.
Class OcuTalon.Live.Payload.Part.ItemNoun Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The singular noun.
Property One As %String(%JSONFIELDNAME = "one", MAXLEN = 128);

/// The plural noun.
Property Other As %String(%JSONFIELDNAME = "other", MAXLEN = 128);

}
