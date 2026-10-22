/// The payload of the status live event: one status condition of the closed catalog. Lane B publishes it.
Class OcuTalon.Live.Payload.Status Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The closed catalog of status conditions (AD-12).
Parameter CONDITIONS = "allowance,dailyCap,noModelKey,heartbeatStalled,telegramPaused,resetSoon";

/// One of CONDITIONS.
Property Condition As %String(%JSONFIELDNAME = "condition", MAXLEN = 32);

/// True while the condition holds.
Property Active As %Boolean(%JSONFIELDNAME = "active") [ InitialExpression = 0 ];

/// The condition's slots.
Property Slots As OcuTalon.Live.Payload.Part.StatusSlots(%JSONFIELDNAME = "slots");

/// The active status conditions of a session, as an array of Status payloads. Not computed yet: it answers an empty
/// array. Story 2.10 computes the conditions, here, so that /state and the status monitor share one reader.
ClassMethod Active(sessionRef As %String) As %DynamicArray
{
	Quit []
}

}
