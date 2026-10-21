/// The payload of the turn.step live event: the current step of a running turn. Lane B publishes it.
Class OcuTalon.Live.Payload.TurnStep Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The decision's Ref.
Property DecisionRef As %String(%JSONFIELDNAME = "decisionRef", MAXLEN = 22);

/// The step, in plain words.
Property Label As %String(%JSONFIELDNAME = "label", MAXLEN = 1000);

}
