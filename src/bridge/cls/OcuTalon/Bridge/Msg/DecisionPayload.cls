/// The checked decision payload that the triage and diagnosis agents answer with (AD-6, AD-8). Lane A.
/// Import refuses a field of the wrong type, a confidence outside 0 to 1 and a field that is not declared here;
/// %OnValidateObject adds what import does not check: an outcome of Msg.Enum OUTCOME, at least one reason that is
/// not blank, and a confidence that is present unless CONFIDENCEREQUIRED is 0. Decide judges a reply by %JSONImport followed by %ValidateObject.
/// Each rule of %OnValidateObject has a fixed tag, the second parameter of its error and the name that RefusalText of Decide shows for it when REFUSALRULES lists it (DW-1421).
/// Each limited field has a length tag, field-too-long, that Decide shows for a text over its limit (DW-1421).
Class OcuTalon.Bridge.Msg.DecisionPayload Extends (%RegisteredObject, %JSON.Adaptor)
{

/// 1 when a reply must carry a confidence (the rule confidence-missing); 0 here and on DiagnosisPayload (DW-1421 C5): a reply without one is accepted and has none, never 0, and a
/// confidence that is given must still be from 0 to 1 (confidence-out-of-range). Triage became 0 by the Contest Planner's triage-accept ruling (Nov 17): a reply that left out its
/// confidence is used instead of being replaced by a Tell now fallback.
Parameter CONFIDENCEREQUIRED = 0;

/// The fixed name of each rule of %OnValidateObject and the JSON field it reads, as tag:field, comma-separated, then the length tag of each limited field (field-too-long) and the range tag
/// (confidence-out-of-range), which no rule raises; a subclass lists these first, then its own. A tag that ends in -out-of-range is the range tag of a field with a MINVAL or MAXVAL, which no rule raises.
/// A tag is lower-case letters and hyphens, with no digit. Decide shows a tag in a refusal only when the reply class lists it here, and never a value of the reply.
Parameter REFUSALRULES = "outcome-unlisted:outcome,reasons-blank:reasons,confidence-missing:confidence,outcome-too-long:outcome,reasons-too-long:reasons,confidence-out-of-range:confidence";

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
		Quit $$$ERROR($$$GeneralError, "The outcome '"_..Outcome_"' is not one of "_outcomes, "outcome-unlisted")
	}
	Set reasons = 0
	For i = 1:1:..Reasons.Count() {
		If $ZStrip(..Reasons.GetAt(i), "*WC") '= "" Set reasons = reasons + 1
	}
	If 'reasons Quit $$$ERROR($$$GeneralError, "The reasons hold no reason that is not blank", "reasons-blank")
	If (..Confidence = "") && $Parameter($this, "CONFIDENCEREQUIRED") Quit $$$ERROR($$$GeneralError, "The confidence is missing", "confidence-missing")
	Quit $$$OK
}

}
