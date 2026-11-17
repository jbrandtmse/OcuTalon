/// The checked payload that the Diagnosis agent answers with (AD-6, AD-7, AD-8, AD-31). It extends OcuTalon.Bridge.Msg.DecisionPayload, so Decide
/// checks a diagnose reply with it as the ReplyClass of DiagnosisAgent: outcome, reasons and confidence are the parent's (the confidence may be left out, CONFIDENCEREQUIRED is 0, and the decision then has none), and the JSON adds
///   - causeCategory, one of CAUSECATEGORIES, and elementAtFault;
///   - evidence, a list of at most MAXEVIDENCE references, each at most 128 characters: %JSONImport cuts a longer one (Cut) and counts the cuts in evidenceCut;
///   - fixKind, repair_resend or empty, and fixParameters {field, sourceFormat, targetFormat};
///   - cause and fixSummary, and itemNoun {one, other}.
/// Decide filters every text of the model that the payload holds (FILTERED, AD-31). Import refuses a field that is not declared here.
/// %OnValidateObject adds, after the parent's check: the outcome act; a category of the list; a cause that is not blank; the fixKind repair_resend
/// exactly when the category is data_format_change (then elementAtFault, fixSummary and fixParameters.field are not blank; any other category has no
/// fixKind, no fixParameters and no fixSummary), except that a data_format_change may carry no fix at all, when fixKind, fixParameters and fixSummary are all
/// absent or blank (a diagnosis that cannot tell which way a date reads, DW-644): it then still names its elementAtFault, and any one of the three alone is
/// refused. It also requires an itemNoun, when given, with neither form blank, and no clock time (h:mm, an hour of 0 to 23 and
/// minutes of 00 to 59, not part of a longer number or an address such as 10.0.0.5:1972) in cause or fixSummary (two rules, one for each). The fix kind is one that OcuTalon.Fix.Kind
/// names (AD-16), and its check of the fix parameters is the last: the fields it is given are the keys of the sample body of the evidence pack that the
/// request carried, read through OcuTalon.Bridge.ReplyCheck, which Decide begins before it checks a reply. With no check begun, or an input that is not a
/// pack with a sample body, no fix is accepted (fail closed); the check's refusal is wrapped in the rule fix-parameters-check, with its own reason embedded. A setting_change may name the kind that Fix.Kind DiagnosedFor lists for it (rollback_setting): with no
/// fixParameters and no fixSummary, and an elementAtFault that names a setting in the pack's settingChanges (Listed); the kind's own check is then its dry run's.
/// Each rule of %OnValidateObject, the parent's three (a diagnosis never meets confidence-missing) and this class's nineteen, has a fixed tag as the second parameter of its error and the tag and its field are listed in
/// REFUSALRULES: Decide's RefusalText shows "ERROR #5001 rule <tag>" for a listed tag and never a value of the reply (DW-1421). The tags are internal names, in no text a user reads.
/// A tag that ends in -too-long is a length tag, one for each limited field: the parent's outcome-too-long and reasons-too-long, and this class's evidence-too-long, cause-category-too-long, element-at-fault-too-long,
/// fix-kind-too-long, cause-too-long and fix-summary-too-long. Decide's RefusalText shows "ERROR #7201 rule <tag>" for a text over the limit of that field, with no position, length or limit. The parent's
/// confidence-out-of-range is the range tag of the confidence. No tag holds a digit. evidence-too-long is the one
/// for an Evidence reference over 128 characters that the check still meets: after a reply filter that lengthens a text, a number element of more than 128 digits (the cut leaves an element
/// that is not a string), and a long reference of the reply as it came when the import refuses the list for another element. A reply that carries evidenceCut is refused, as an
/// unexpected property. Lane A.
Class OcuTalon.Watch.Msg.DiagnosisPayload Extends OcuTalon.Bridge.Msg.DecisionPayload
{

/// The causes that a diagnosis names, comma-separated.
Parameter CAUSECATEGORIES = "data_format_change,connection_failure,setting_change,partner_outage,validation_error,unknown";

/// The category whose fix is the data-format repair; a fixKind of any other category is the one that Fix.Kind DiagnosedFor lists for it (a setting_change may name rollback_setting).
Parameter FIXCATEGORY = "data_format_change";

/// The properties that Decide filters before it records the payload (comma-separated; a dotted name is a property of an object property, and a
/// list is filtered item by item): every text of the model that the payload holds.
Parameter FILTERED = "Cause,FixSummary,ElementAtFault,Evidence,ItemNoun.One,ItemNoun.Other,FixParameters.Field,FixParameters.SourceFormat,FixParameters.TargetFormat";

/// A clock time (h:mm) in a text, as a regular expression: not preceded by a digit, a dot or a colon, and not followed by a digit.
Parameter CLOCKTIME = "(?<![0-9.:])([01]?[0-9]|2[0-3]):[0-5][0-9](?![0-9])";

/// The fixed name of each rule of %OnValidateObject and the JSON field it reads, as tag:field, comma-separated: the parent's list (its rules, its length tags and its range tag), then this class's own rules in rule order,
/// then this class's length tags, which no %OnValidateObject rule raises (see the class description).
Parameter REFUSALRULES = "outcome-unlisted:outcome,reasons-blank:reasons,confidence-missing:confidence,outcome-too-long:outcome,reasons-too-long:reasons,confidence-out-of-range:confidence,outcome-not-act:outcome,cause-category-unlisted:causeCategory,evidence-over-max:evidence,cause-blank:cause,format-no-fix-element-blank:elementAtFault,format-fix-kind-unlisted:fixKind,format-fix-element-blank:elementAtFault,format-fix-summary-blank:fixSummary,format-fix-field-blank:fixParameters.field,rollback-fix-parameters:fixParameters,rollback-fix-summary:fixSummary,rollback-element-unlisted:elementAtFault,fix-kind-not-for-category:fixKind,fix-parameters-not-for-category:fixParameters,fix-summary-not-for-category:fixSummary,item-noun-blank:itemNoun,time-of-day-in-cause:cause,time-of-day-in-fix-summary:fixSummary,fix-parameters-check:fixParameters,evidence-too-long:evidence,cause-category-too-long:causeCategory,element-at-fault-too-long:elementAtFault,fix-kind-too-long:fixKind,cause-too-long:cause,fix-summary-too-long:fixSummary";

/// A diagnosis may leave out its confidence: it is only shown, so a reply without one is accepted, its decision stores none and nothing is shown, never 0 (DW-1421 C5).
Parameter CONFIDENCEREQUIRED = 0;

/// The fewest characters that a cut at a word boundary keeps: when the text before the last space at or before EVIDENCEMAX is shorter, once its trailing white space is removed, Cut cuts mid-word (DW-1421 round 3).
Parameter EVIDENCEFLOOR = 64;

/// The most references in the evidence list.
Parameter MAXEVIDENCE = 20;

/// The most characters of an evidence reference after the cut: the MAXLEN of Evidence.
Parameter EVIDENCEMAX = 128;

/// One of CAUSECATEGORIES.
Property CauseCategory As %String(%JSONFIELDNAME = "causeCategory", MAXLEN = 32);

/// The element of the production that failed: a message field, an item or a setting.
Property ElementAtFault As %String(%JSONFIELDNAME = "elementAtFault", MAXLEN = 128);

/// References to what the diagnosis rests on, each at most 128 characters (%JSONImport cuts a longer one, see the class description).
Property Evidence As list Of %String(%JSONFIELDNAME = "evidence", MAXLEN = 128);

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

/// The number of evidence references that %JSONImport cut to 128 characters (see the class description); empty when none was cut. Code-written, never model text; exported, never imported.
Property EvidenceCut As %Integer(%JSONFIELDNAME = "evidenceCut", %JSONINCLUDE = "OUTPUTONLY", MINVAL = 1);

/// The import of the inherited method, after every string reference of the evidence list that is over EVIDENCEMAX characters is cut (Cut); the number of cuts is EvidenceCut, set when the import
/// succeeds and more than 0 were cut. Nothing else of the reply is changed, the caller's input is never changed, and the text of a reference is never logged. The reply may not name evidenceCut: the
/// field is refused as an unexpected property, as an input field of the class that is not declared. An input that does not parse, or is not a JSON object, gives the inherited status.
Method %JSONImport(input, %mappingName As %String = "") As %Status [ ServerOnly = 1 ]
{
	Set ..EvidenceCut = ""
	Try {
		If $IsObject(input) && input.%IsA("%Library.DynamicAbstractObject") {
			Set object = ##class(%Library.DynamicAbstractObject).%FromJSON(input.%ToJSON())
		} Else {
			Set object = ##class(%Library.DynamicAbstractObject).%FromJSON(input)
		}
	} Catch {
		Return ##super(input, %mappingName)
	}
	If '$IsObject(object) || 'object.%IsA("%Library.DynamicObject") Return ##super(input, %mappingName)
	If object.%GetTypeOf("evidenceCut") '= "unassigned" Return $$$ERROR($$$JSONImportBadField, "evidenceCut", $Select(%mappingName = "": "class base", 1: %mappingName))
	Set cut = 0
	If object.%GetTypeOf("evidence") = "array" {
		Set evidence = object.evidence
		For i = 0:1:evidence.%Size() - 1 {
			If (evidence.%GetTypeOf(i) = "string") && ($Length(evidence.%Get(i)) > ..#EVIDENCEMAX) {
				Do evidence.%Set(i, ..Cut(evidence.%Get(i)))
				Set cut = cut + 1
			}
		}
	}
	Set sc = ##super(object, %mappingName)
	If $$$ISOK(sc) && (cut > 0) Set ..EvidenceCut = cut
	Quit sc
}

/// The text of an evidence reference over EVIDENCEMAX characters, cut: at most EVIDENCEMAX characters, ending in U+2026. The head is the text before the last space at a position of 2 to EVIDENCEMAX, with
/// trailing white space removed, when it keeps at least EVIDENCEFLOOR characters; otherwise (no such space, a shorter head, or a blank one) it is the first EVIDENCEMAX - 1 characters (less one, when the cut would end on the first half of a surrogate pair).
ClassMethod Cut(text As %String) As %String [ Private ]
{
	Set head = ""
	For position = ..#EVIDENCEMAX:-1:2 {
		If $Extract(text, position) = " " {
			Set head = $ZStrip($Extract(text, 1, position - 1), ">W")
			Quit
		}
	}
	If $Length(head) < ..#EVIDENCEFLOOR {
		Set head = $Extract(text, 1, ..#EVIDENCEMAX - 1)
		Set last = $Ascii(head, ..#EVIDENCEMAX - 1)
		If (last >= 55296) && (last <= 56319) Set head = $Extract(head, 1, ..#EVIDENCEMAX - 2)
	}
	Quit head_$Char(8230)
}

/// The checks that the property definitions do not make (see the class description).
Method %OnValidateObject() As %Status [ Private, ServerOnly = 1 ]
{
	Set sc = ##super()
	If $$$ISERR(sc) Quit sc
	If ..Outcome '= "act" Quit $$$ERROR($$$GeneralError, "The outcome of a diagnosis is act, not '"_..Outcome_"'", "outcome-not-act")
	If '$ListFind($ListFromString(..#CAUSECATEGORIES), ..CauseCategory) {
		Quit $$$ERROR($$$GeneralError, "The causeCategory '"_..CauseCategory_"' is not one of "_..#CAUSECATEGORIES, "cause-category-unlisted")
	}
	If ..Evidence.Count() > ..#MAXEVIDENCE Quit $$$ERROR($$$GeneralError, "The evidence holds more than "_..#MAXEVIDENCE_" references", "evidence-over-max")
	If ..Blank(..Cause) Quit $$$ERROR($$$GeneralError, "The cause is blank", "cause-blank")
	If (..CauseCategory = ..#FIXCATEGORY) && (..FixKind = "") && '$IsObject(..FixParameters) && ..Blank(..FixSummary) {
		If ..Blank(..ElementAtFault) Quit $$$ERROR($$$GeneralError, "A data_format_change names its elementAtFault", "format-no-fix-element-blank")
	} ElseIf ..CauseCategory = ..#FIXCATEGORY {
		If '$ListFind(##class(OcuTalon.Fix.Kind).DiagnosedFor(..#FIXCATEGORY), ..FixKind) Quit $$$ERROR($$$GeneralError, "A data_format_change has a fixKind of "_$ListToString(##class(OcuTalon.Fix.Kind).DiagnosedFor(..#FIXCATEGORY), ","), "format-fix-kind-unlisted")
		If ..Blank(..ElementAtFault) Quit $$$ERROR($$$GeneralError, "A data_format_change names its elementAtFault", "format-fix-element-blank")
		If ..Blank(..FixSummary) Quit $$$ERROR($$$GeneralError, "A data_format_change has a fixSummary", "format-fix-summary-blank")
		If '$IsObject(..FixParameters) || ..Blank(..FixParameters.Field) Quit $$$ERROR($$$GeneralError, "A data_format_change has fixParameters with a field", "format-fix-field-blank")
	} ElseIf (..FixKind '= "") && $ListFind(##class(OcuTalon.Fix.Kind).DiagnosedFor(..CauseCategory), ..FixKind) {
		If $IsObject(..FixParameters) Quit $$$ERROR($$$GeneralError, "The fixKind '"_..FixKind_"' has no fixParameters", "rollback-fix-parameters")
		If '..Blank(..FixSummary) Quit $$$ERROR($$$GeneralError, "The fixKind '"_..FixKind_"' has no fixSummary", "rollback-fix-summary")
		If '..Listed(..ElementAtFault) Quit $$$ERROR($$$GeneralError, "The fixKind '"_..FixKind_"' needs an elementAtFault that names a setting in the evidence pack's settingChanges", "rollback-element-unlisted")
	} Else {
		If ..FixKind '= "" Quit $$$ERROR($$$GeneralError, "The causeCategory '"_..CauseCategory_"' has no fixKind", "fix-kind-not-for-category")
		If $IsObject(..FixParameters) Quit $$$ERROR($$$GeneralError, "The causeCategory '"_..CauseCategory_"' has no fixParameters", "fix-parameters-not-for-category")
		If '..Blank(..FixSummary) Quit $$$ERROR($$$GeneralError, "The causeCategory '"_..CauseCategory_"' has no fixSummary", "fix-summary-not-for-category")
	}
	If $IsObject(..ItemNoun) && (..Blank(..ItemNoun.One) || ..Blank(..ItemNoun.Other)) {
		Quit $$$ERROR($$$GeneralError, "The itemNoun has a blank form", "item-noun-blank")
	}
	If $Locate(..Cause, ..#CLOCKTIME) Quit $$$ERROR($$$GeneralError, "The cause and the fixSummary hold no time of day", "time-of-day-in-cause")
	If $Locate(..FixSummary, ..#CLOCKTIME) Quit $$$ERROR($$$GeneralError, "The cause and the fixSummary hold no time of day", "time-of-day-in-fix-summary")
	If (..FixKind '= "") && (##class(OcuTalon.Fix.Kind).ForName(..FixKind) '= "") && ($Parameter(##class(OcuTalon.Fix.Kind).ForName(..FixKind), "TARGETTYPE") = "setting") Quit $$$OK
	If ..FixKind '= "" {
		Set sc = ..CheckFix()
		If $$$ISERR(sc) Quit $SYSTEM.Status.EmbedStatus($$$ERROR($$$GeneralError, "The fix kind's check of the fixParameters failed", "fix-parameters-check"), sc)
	}
	Quit $$$OK
}

/// 1 when the name is the setting of a change that the pack of the request lists (settingChanges), read through OcuTalon.Bridge.ReplyCheck like the sample's fields; 0 with no
/// pack, so that a fix on a setting is never accepted without evidence (fail closed).
Method Listed(name As %String) As %Boolean [ Private ]
{
	If ..Blank(name) Quit 0
	Set pack = ##class(OcuTalon.Watch.EvidencePack).FromInput(##class(OcuTalon.Bridge.ReplyCheck).Value("Input"))
	If '$IsObject(pack) || '$IsObject(pack.settingChanges) Quit 0
	Set iterator = pack.settingChanges.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If $IsObject(entry) && (entry.setting = name) Return 1
	}
	Quit 0
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
