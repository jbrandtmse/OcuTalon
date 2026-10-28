/// The release-1 fix kind (AD-16): repair a field of the failed messages that holds a value in the wrong format, and resend them. The model names the field and
/// the two formats (the parameters field, sourceFormat and targetFormat); the formats are those registered in OcuTalon.Fix.Reformat, and the field must be
/// a field of the sample message that the diagnosis was given. This class checks the parameters (CheckParameters) and works out the dry run (DryRun); the
/// repair and the resend are Story 7.3's.
/// The dry run reads the failed messages of the incident's failure groups through OcuTalon.Watch.Reader.Evidence only, changes nothing and calls no model.
/// A message is a target when it is a header of a group's Seen that is still in the status Error, its scope (OcuTalon.Watch.FailurePoller Scope of its
/// SuperSession) is the incident's owner, and its field reads in the source format. A failed message of the scope whose field does not read (another format,
/// no value, or no body that can be read) is counted as affected and left out. Lane A.
Class OcuTalon.Fix.Kind.RepairResend Extends OcuTalon.Fix.Kind
{

Parameter NAME = "repair_resend";

Parameter PARAMETERS = "field,sourceFormat,targetFormat";

Parameter RESOURCES = "%Ens_MessageResend:U";

/// The status text of a message that failed, as Reader.Evidence gives it.
Parameter ERRORSTATUS = "Error";

/// The base's schema check, then: the field is a member of fields (exact match), both formats are registered, they are of one family and they differ.
ClassMethod CheckParameters(parameters As %DynamicObject, fields As %DynamicArray) As %Status
{
	Set sc = ##super(parameters, fields)
	If $$$ISERR(sc) Quit sc
	Set field = parameters.%Get("field")
	Set known = 0
	If $IsObject($Get(fields)) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(, .name) {
			If "k"_name = ("k"_field) {
				Set known = 1
				Quit
			}
		}
	}
	If 'known Quit $$$ERROR($$$GeneralError, "The field '"_field_"' is not a field of the sample message")
	Set source = parameters.%Get("sourceFormat")
	Set target = parameters.%Get("targetFormat")
	Set sourceFamily = ##class(OcuTalon.Fix.Reformat).Family(source)
	Set targetFamily = ##class(OcuTalon.Fix.Reformat).Family(target)
	If sourceFamily = "" Quit $$$ERROR($$$GeneralError, "The sourceFormat '"_source_"' is not a registered format")
	If targetFamily = "" Quit $$$ERROR($$$GeneralError, "The targetFormat '"_target_"' is not a registered format")
	If sourceFamily '= targetFamily Quit $$$ERROR($$$GeneralError, "The sourceFormat '"_source_"' and the targetFormat '"_target_"' are not of one family")
	If "k"_source = ("k"_target) Quit $$$ERROR($$$GeneralError, "The sourceFormat and the targetFormat are one format, '"_source_"'")
	Quit $$$OK
}

/// The words of a property name in lower case: split at a change from a lower-case letter or a digit to a capital, and before the last capital of a run of
/// capitals that a lower-case letter follows; _, - and . are spaces. OrderDate gives "order date" and PONumber gives "po number".
ClassMethod FieldWords(name As %String) As %String
{
	Set name = $Get(name)
	Set words = ""
	Set length = $Length(name)
	For i = 1:1:length {
		Set char = $Extract(name, i)
		If "_-." [ char {
			Set words = words _ " "
			Continue
		}
		Set previous = $Select(i > 1: $Extract(name, i - 1), 1: "")
		Set next = $Select(i < length: $Extract(name, i + 1), 1: "")
		If ..Capital(char) && (previous '= "") && (..Lower(previous) || (previous ? 1N) || (..Capital(previous) && ..Lower(next))) {
			Set words = words _ " "
		}
		Set words = words _ char
	}
	Set words = $ZStrip($ZConvert(words, "L"), "<>W")
	While words [ "  " {
		Set words = $Replace(words, "  ", " ")
	}
	Quit words
}

ClassMethod Capital(char As %String) As %Boolean [ Private ]
{
	Quit (char '= "") && ($Ascii(char) > 64) && ($Ascii(char) < 91)
}

ClassMethod Lower(char As %String) As %Boolean [ Private ]
{
	Quit (char '= "") && ($Ascii(char) > 96) && ($Ascii(char) < 123)
}

/// The targets and the dry run for the incident's failure groups (see the class description). targets holds the header ids, ascending; dryRun holds the keys
/// of OcuTalon.Bridge.Data.ApprovalRequest DRYRUNKEYS: affected, resend and leftOut (counts), field (the property name in words), before and after (the
/// first target's value and its repair, or empty when there is none) and itemNoun ({one, other}). An error status when the production cannot be read,
/// the incident has no failed message of its scope or the parameters do not pass CheckParameters against the body of the first of them that has one.
ClassMethod DryRun(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, Output targets As %String, Output dryRun As %DynamicObject) As %Status
{
	Set targets = ""
	Set dryRun = ""
	Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident.Ref)
	Kill scoped
	Set (before, after) = ""
	Set haveExample = 0
	For g = 1:1:groups.Count() {
		Set group = groups.GetAt(g)
		Set keys = ""
		For i = 1:1:$Length(group.Seen, ",") {
			Set key = $Piece(group.Seen, ",", i)
			If key ? 1"h".N Set keys = keys _ $Select(keys = "": "", 1: ",") _ key
		}
		If keys = "" Continue
		Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(incident.Namespace, incident.Production, group.ItemName, keys, .snapshot)
		If outcome '= "read" {
			Return $$$ERROR($$$GeneralError, "The failed messages of "_incident.Production_" in "_incident.Namespace_" could not be read: "_$Select(outcome = "unreadable": "the service user cannot read the namespace", outcome = "not_current": "the production is not the one that runs there", 1: outcome))
		}
		For i = 0:1:snapshot.failures.%Size() - 1 {
			Set failure = snapshot.failures.%Get(i)
			If failure.status '= ..#ERRORSTATUS Continue
			If ##class(OcuTalon.Watch.FailurePoller).Scope(failure.superSession) '= incident.OwnerRef Continue
			Set id = +failure.headerId
			If $Data(scoped(id)) Continue
			Set scoped(id) = $Select($IsObject(failure.body) && failure.body.%IsA("%Library.DynamicObject"): failure.body, 1: {})
			Set classes(id) = failure.bodyClass
		}
	}
	Set first = $Order(scoped(""))
	If first = "" Quit $$$ERROR($$$GeneralError, "The incident has no failed message of its scope to repair")
	Set sample = first
	While (sample '= "") && (scoped(sample).%Size() = 0) {
		Set sample = $Order(scoped(sample))
	}
	Set fields = []
	If sample '= "" {
		Set iterator = scoped(sample).%GetIterator()
		While iterator.%GetNext(.name) {
			Do fields.%Push(name)
		}
	}
	Set sc = ..CheckParameters(parameters, fields)
	If $$$ISERR(sc) Quit sc
	Set field = parameters.%Get("field")
	Set affected = 0
	Set id = ""
	For {
		Set id = $Order(scoped(id))
		Quit:id=""
		Set affected = affected + 1
		Set current = scoped(id).%Get(field)
		If $$$ISERR(##class(OcuTalon.Fix.Reformat).Convert(current, parameters.%Get("sourceFormat"), parameters.%Get("targetFormat"), .repaired)) Continue
		Set targets = targets _ $Select(targets = "": "", 1: ",") _ id
		If 'haveExample {
			Set haveExample = 1
			Set before = current
			Set after = repaired
		}
	}
	Set noun = ""
	If incident.ItemNoun '= "" {
		Try {
			Set noun = {}.%FromJSON(incident.ItemNoun)
		} Catch {
			Set noun = ""
		}
	}
	If '$IsObject(noun) || 'noun.%IsA("%Library.DynamicObject") || (noun.one = "") || (noun.other = "") Set noun = {}.%FromJSON(##class(OcuTalon.Watch.ItemNoun).For(classes(first)))
	Set resend = $Select(targets = "": 0, 1: $Length(targets, ","))
	Set out("affected") = affected
	Set out("resend") = resend
	Set out("leftOut") = affected - resend
	Set out("field") = ..FieldWords(field)
	Set out("before") = before
	Set out("after") = after
	Set dryRun = {}
	Set keyNames = $Parameter("OcuTalon.Bridge.Data.ApprovalRequest", "DRYRUNKEYS")
	For i = 1:1:$Length(keyNames, ",") {
		Set key = $Piece(keyNames, ",", i)
		If key = "itemNoun" {
			Do dryRun.%Set(key, noun)
		} ElseIf $Data(out(key)) {
			Do dryRun.%Set(key, out(key), $Case(key, "affected": "number", "resend": "number", "leftOut": "number", : "string"))
		} Else {
			Return $$$ERROR($$$GeneralError, "The dry run has no value for the key '"_key_"'")
		}
	}
	Quit $$$OK
}

}
