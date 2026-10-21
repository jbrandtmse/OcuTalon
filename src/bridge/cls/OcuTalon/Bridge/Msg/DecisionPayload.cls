/// The checked decision payload that the triage and diagnosis agents answer with (AD-6, AD-8). Lane A.
Class OcuTalon.Bridge.Msg.DecisionPayload Extends (%RegisteredObject, %JSON.Adaptor)
{

/// One of Msg.Enum OUTCOME.
Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 32);

/// The reasons, one per list item.
Property Reasons As list Of %String(%JSONFIELDNAME = "reasons", MAXLEN = 1000);

/// The model-reported confidence, 0 to 1 with two decimals.
Property Confidence As %Numeric(%JSONFIELDNAME = "confidence", MAXVAL = 1, MINVAL = 0, SCALE = 2);

}
