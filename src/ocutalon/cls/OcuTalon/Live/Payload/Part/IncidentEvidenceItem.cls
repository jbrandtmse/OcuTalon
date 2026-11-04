/// The failures of one item. Lane A.
Class OcuTalon.Live.Payload.Part.IncidentEvidenceItem Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The item's readable name.
Property ItemName As %String(%JSONFIELDNAME = "itemName", MAXLEN = 128);

/// The failures of the item.
Property Count As %Integer(%JSONFIELDNAME = "count");

/// The first failure, UTC to the second.
Property FirstAt As %String(%JSONFIELDNAME = "firstAt", MAXLEN = 20);

/// The last failure, UTC to the second.
Property LastAt As %String(%JSONFIELDNAME = "lastAt", MAXLEN = 20);

}
