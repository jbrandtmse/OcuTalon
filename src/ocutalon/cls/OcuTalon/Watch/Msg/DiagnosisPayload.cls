/// The checked payload that the Diagnosis agent answers with (AD-6, AD-7, AD-8, AD-31). It extends OcuTalon.Bridge.Msg.DecisionPayload, so Decide
/// checks a diagnose reply with it as the ReplyClass of DiagnosisAgent: outcome, reasons and confidence are the parent's, and the JSON adds
///   - causeCategory, one of CAUSECATEGORIES, and elementAtFault;
///   - evidence, a list of references of at most MAXEVIDENCE entries;
///   - fixKind, repair_resend or empty, and fixParameters {field, sourceFormat, targetFormat};
///   - cause and fixSummary, and itemNoun {one, other}.
/// Decide filters every text of the model that the payload holds (FILTERED, AD-31). Import refuses a field that is not declared here.
/// %OnValidateObject adds, after the parent's check: the outcome act; a category of the list; a cause that is not blank; the fixKind repair_resend
/// exactly when the category is data_format_change (then elementAtFault, fixSummary and fixParameters.field are not blank; any other category has no
/// fixKind, no fixParameters and no fixSummary); an itemNoun, when given, with neither form blank; and no clock time (h:mm, an hour of 0 to 23 and
/// minutes of 00 to 59, not part of a longer number or an address such as 10.0.0.5:1972) in cause or fixSummary. The fix kind is one that OcuTalon.Fix.Kind
/// names (AD-16), and its check of the fix parameters is the last: the fields it is given are the keys of the sample body of the evidence pack that the
/// request carried, read through OcuTalon.Bridge.ReplyCheck, which Decide begins before it checks a reply. With no check begun, or an input that is not a
/// pack with a sample body, no fix is accepted (fail closed). Lane A.
Class OcuTalon.Watch.Msg.DiagnosisPayload Extends OcuTalon.Bridge.Msg.DecisionPayload
{

/// The causes that a diagnosis names, comma-separated.
Parameter CAUSECATEGORIES = "data_format_change,connection_failure,setting_change,partner_outage,validation_error,unknown";

/// The category that has a fix.
Parameter FIXCATEGORY = "data_format_change";

/// The properties that Decide filters before it records the payload (comma-separated; a dotted name is a property of an object property, and a
/// list is filtered item by item): every text of the model that the payload holds.
Parameter FILTERED = "Cause,FixSummary,ElementAtFault,Evidence,ItemNoun.One,ItemNoun.Other,FixParameters.Field,FixParameters.SourceFormat,FixParameters.TargetFormat";

/// A clock time (h:mm) in a text, as a regular expression: not preceded by a digit, a dot or a colon, and not followed by a digit.
Parameter CLOCKTIME = "(?<![0-9.:])([01]?[0-9]|2[0-3]):[0-5][0-9](?![0-9])";

/// The most references in the evidence list.
Parameter MAXEVIDENCE = 20;

/// One of CAUSECATEGORIES.
Property CauseCategory As %String(%JSONFIELDNAME = "causeCategory", MAXLEN = 32);

/// The element of the production that failed: a message field, an item or a setting.
Property ElementAtFault As %String(%JSONFIELDNAME = "elementAtFault", MAXLEN = 128);

/// References to what the diagnosis rests on.
Property Evidence As list Of %String(%JSONFIELDNAME = "evidence", MAXLEN = 32);

/// The NAME of a kind of OcuTalon.Fix.Kind (repair_resend), or empty.
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
		If ##class(OcuTalon.Fix.Kind).ForName(..FixKind) = "" Quit $$$ERROR($$$GeneralError, "A data_format_change has a fixKind of "_$ListToString(##class(OcuTalon.Fix.Kind).Names(), ","))
		If ..Blank(..ElementAtFault) Quit $$$ERROR($$$GeneralError, "A data_format_change names its elementAtFault")
		If ..Blank(..FixSummary) Quit $$$ERROR($$$GeneralError, "A data_format_change has a fixSummary")
		If '$IsObject(..FixParameters) || ..Blank(..FixParameters.Field) Quit $$$ERROR($$$GeneralError, "A data_format_change has fixParameters with a field")
	} Else {
		If ..FixKind '= "" Quit $$$ERROR($$$GeneralError, "The causeCategory '"_..CauseCategory_"' has no fixKind")
		If $IsObject(..FixParameters) Quit $$$ERROR($$$GeneralError, "The causeCategory '"_..CauseCategory_"' has no fixParameters")
		If '..Blank(..FixSummary) Quit $$$ERROR($$$GeneralError, "The causeCategory '"_..CauseCategory_"' has no fixSummary")
	}
	If $IsObject(..ItemNoun) && (..Blank(..ItemNoun.One) || ..Blank(..ItemNoun.Other)) {
		Quit $$$ERROR($$$GeneralError, "The itemNoun has a blank form")
	}
	If $Locate(..Cause, ..#CLOCKTIME) || $Locate(..FixSummary, ..#CLOCKTIME) {
		Quit $$$ERROR($$$GeneralError, "The cause and the fixSummary hold no time of day")
	}
	If ..FixKind '= "" Quit ..CheckFix()
	Quit $$$OK
}

/// The fix kind's check of the fix parameters against the fields of the sample message that the request's evidence pack holds (see the class description).
Method CheckFix() As %Status [ Private ]
{
	Set fields = []
	Set sample = ##class(OcuTalon.Watch.EvidencePack).FromInput(##class(OcuTalon.Bridge.ReplyCheck).Value("Input"))
	If $IsObject(sample) && $IsObject(sample.sample) && $IsObject(sample.sample.body) && sample.sample.body.%IsA("%Library.DynamicObject") {
		Set iterator = sample.sample.body.%GetIterator()
		While iterator.%GetNext(.name) {
			Do fields.%Push(name)
		}
	}
	Set parameters = ""
	If $IsObject(..FixParameters) {
		Set sc = ..FixParameters.%JSONExportToString(.json)
		If $$$ISERR(sc) Quit sc
		Set parameters = {}.%FromJSON(json)
	}
	Quit ##class(OcuTalon.Fix.Kind).Check(..FixKind, parameters, fields)
}

/// 1 when the text is empty once white space and control characters are removed.
ClassMethod Blank(text As %String) As %Boolean [ Private ]
{
	Quit $ZStrip($Get(text), "*WC") = ""
}

}
