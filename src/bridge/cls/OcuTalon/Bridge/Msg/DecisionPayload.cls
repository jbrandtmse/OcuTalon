/// The checked decision payload that the triage and diagnosis agents answer with (AD-6, AD-8). Lane A.
/// Import refuses a field of the wrong type, a confidence outside 0 to 1 and a field that is not declared here;
/// %OnValidateObject adds what import does not check: an outcome of Msg.Enum OUTCOME, at least one reason that is
/// not blank, and a confidence that is present. Decide judges a reply by %JSONImport followed by %ValidateObject.
Class OcuTalon.Bridge.Msg.DecisionPayload Extends (%RegisteredObject, %JSON.Adaptor)
{

/// One of Msg.Enum OUTCOME.
Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 32);

/// The reasons, one per list item.
Property Reasons As list Of %String(%JSONFIELDNAME = "reasons", MAXLEN = 1000);

/// The model-reported confidence, 0 to 1 with two decimals.
Property Confidence As %Numeric(%JSONFIELDNAME = "confidence", MAXVAL = 1, MINVAL = 0, SCALE = 2);

/// The checks that the property definitions do not make. A blank reason is one that is empty once white space and
/// control characters are removed.
Method %OnValidateObject() As %Status [ Private, ServerOnly = 1 ]
{
	Set outcomes = ##class(OcuTalon.Bridge.Msg.Enum).#OUTCOME
	If '$ListFind($ListFromString(outcomes), ..Outcome) {
		Quit $$$ERROR($$$GeneralError, "The outcome '"_..Outcome_"' is not one of "_outcomes)
	}
	Set reasons = 0
	For i = 1:1:..Reasons.Count() {
		If $ZStrip(..Reasons.GetAt(i), "*WC") '= "" Set reasons = reasons + 1
	}
	If 'reasons Quit $$$ERROR($$$GeneralError, "The reasons hold no reason that is not blank")
	If ..Confidence = "" Quit $$$ERROR($$$GeneralError, "The confidence is missing")
	Quit $$$OK
}

}
