/// One group of failures of an incident. Lane A.
Class OcuTalon.Live.Payload.Part.IncidentGroup Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The group's readable item name.
Property ItemName As %String(%JSONFIELDNAME = "itemName", MAXLEN = 128);

/// The failures in the group.
Property Count As %Integer(%JSONFIELDNAME = "count");

/// A plain summary of the error.
Property ErrorSummary As %String(%JSONFIELDNAME = "errorSummary", MAXLEN = 1000);

/// When the group first failed, UTC to the second.
Property FirstAt As %String(%JSONFIELDNAME = "firstAt", MAXLEN = 20);

}
