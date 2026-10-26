/// The checked payload that the Diagnosis agent answers with (AD-6, AD-7, AD-8, AD-31). It extends OcuTalon.Bridge.Msg.DecisionPayload, so Decide
/// checks a diagnose reply with it as the ReplyClass of DiagnosisAgent: outcome, reasons and confidence are the parent's, and the JSON adds
///   - causeCategory, one of CAUSECATEGORIES, and elementAtFault;
///   - evidence, a list of references of at most MAXEVIDENCE entries;
///   - fixKind, repair_resend or empty, and fixParameters {field, sourceFormat, targetFormat};
///   - cause and fixSummary, the two texts that Decide filters (FILTERED), and itemNoun {one, other}.
/// Import refuses a field that is not declared here. %OnValidateObject adds, after the parent's check: the outcome act; a category of the list; a
/// cause that is not blank; the fixKind repair_resend exactly when the category is data_format_change (then elementAtFault, fixSummary and
/// fixParameters.field are not blank; any other category has no fixKind and no fixParameters); an itemNoun, when given, with neither form blank;
/// and no clock time (h:mm) in cause or fixSummary. Lane A.
Class OcuTalon.Watch.Msg.DiagnosisPayload Extends OcuTalon.Bridge.Msg.DecisionPayload
{

/// The causes that a diagnosis names, comma-separated.
Parameter CAUSECATEGORIES = "data_format_change,connection_failure,setting_change,partner_outage,validation_error,unknown";

/// The fix kinds that a diagnosis names, comma-separated.
Parameter FIXKINDS = "repair_resend";

/// The category that has a fix.
Parameter FIXCATEGORY = "data_format_change";

/// The properties that Decide filters before it records the payload (comma-separated).
Parameter FILTERED = "Cause,FixSummary";

/// The most references in the evidence list.
Parameter MAXEVIDENCE = 20;

/// One of CAUSECATEGORIES.
Property CauseCategory As %String(%JSONFIELDNAME = "causeCategory", MAXLEN = 32);

/// The element of the production that failed: a message field, an item or a setting.
Property ElementAtFault As %String(%JSONFIELDNAME = "elementAtFault", MAXLEN = 128);

/// References to what the diagnosis rests on.
Property Evidence As list Of %String(%JSONFIELDNAME = "evidence", MAXLEN = 32);

/// One of FIXKINDS, or empty.
Property FixKind As %String(%JSONFIELDNAME = "fixKind", MAXLEN = 32);

/// The fix's parameters; present only with a fixKind.
Property FixParameters As OcuTalon.Watch.Msg.FixParameters(%JSONFIELDNAME = "fixParameters");

/// The cause in one plain sentence, without a time.
Property Cause As %String(%JSONFIELDNAME = "cause", MAXLEN = 1000);

/// What the fix does, completing "I can ...".
Property FixSummary As %String(%JSONFIELDNAME = "fixSummary", MAXLEN = 1000);

/// The singular and plural noun of the failed items.
Property ItemNoun As OcuTalon.Live.Payload.Part.ItemNoun(%JSONFIELDNAME = "itemNoun");

/// The checks that the property definitions do not make (see the class description).
Method %OnValidateObject() As %Status [ Private, ServerOnly = 1 ]
{
	Set sc = ##super()
	If $$$ISERR(sc) Quit sc
	If ..Outcome '= "act" Quit $$$ERROR($$$GeneralError, "The outcome of a diagnosis is act, not '"_..Outcome_"'")
	If '$ListFind($ListFromString(..#CAUSECATEGORIES), ..CauseCategory) {
		Quit $$$ERROR($$$GeneralError, "The causeCategory '"_..CauseCategory_"' is not one of "_..#CAUSECATEGORIES)
	}
	If ..Evidence.Count() > ..#MAXEVIDENCE Quit $$$ERROR($$$GeneralError, "The evidence holds more than "_..#MAXEVIDENCE_" references")
	If ..Blank(..Cause) Quit $$$ERROR($$$GeneralError, "The cause is blank")
	If ..CauseCategory = ..#FIXCATEGORY {
		If '$ListFind($ListFromString(..#FIXKINDS), ..FixKind) Quit $$$ERROR($$$GeneralError, "A data_format_change has a fixKind of "_..#FIXKINDS)
		If ..Blank(..ElementAtFault) Quit $$$ERROR($$$GeneralError, "A data_format_change names its elementAtFault")
		If ..Blank(..FixSummary) Quit $$$ERROR($$$GeneralError, "A data_format_change has a fixSummary")
		If '$IsObject(..FixParameters) || ..Blank(..FixParameters.Field) Quit $$$ERROR($$$GeneralError, "A data_format_change has fixParameters with a field")
	} Else {
		If ..FixKind '= "" Quit $$$ERROR($$$GeneralError, "The causeCategory '"_..CauseCategory_"' has no fixKind")
		If $IsObject(..FixParameters) Quit $$$ERROR($$$GeneralError, "The causeCategory '"_..CauseCategory_"' has no fixParameters")
	}
	If $IsObject(..ItemNoun) && (..Blank(..ItemNoun.One) || ..Blank(..ItemNoun.Other)) {
		Quit $$$ERROR($$$GeneralError, "The itemNoun has a blank form")
	}
	If $Locate(..Cause, "[0-9]{1,2}:[0-9]{2}") || $Locate(..FixSummary, "[0-9]{1,2}:[0-9]{2}") {
		Quit $$$ERROR($$$GeneralError, "The cause and the fixSummary hold no time of day")
	}
	Quit $$$OK
}

/// 1 when the text is empty once white space and control characters are removed.
ClassMethod Blank(text As %String) As %Boolean [ Private ]
{
	Quit $ZStrip($Get(text), "*WC") = ""
}

}
