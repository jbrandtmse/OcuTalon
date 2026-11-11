/// The release-1 fix kind (AD-16): repair a field of the failed messages that holds a value in the wrong format, and resend them. The model names the field and
/// the two formats (the parameters field, sourceFormat and targetFormat); the formats are those registered in OcuTalon.Fix.Reformat, and the field must be
/// a field of the sample message that the diagnosis was given. This class checks the parameters (CheckParameters), works out the dry run (DryRun), re-checks the
/// approved targets (Recheck) and resends a repaired copy of each target that passes (Execute).
/// The dry run reads the failed messages of the incident's failure groups through OcuTalon.Watch.Reader.Evidence, and the good messages of their sources through Reader.Good (see below), changes nothing and calls no model.
/// It reads the keys that each group's newest ask covers (FailureGroup.AskedKeys: the window that IncidentManager marked before it sent the ask, or the whole
/// Seen of a group with no mark), so that a later request holds only the failures that arrived after the request before it (Story 7.6).
/// A group's Seen keeps only its newest SEENMAX keys, so the failures of its window that Seen no longer lists (FailureGroup.Unlisted) cannot be read: each counts as
/// affected and so as left out, and a window that Seen has cut at its start or its end cannot be counted at all, so it gets no dry run (Story 7.4, DW-318).
/// A message is a target when it is a header of the group's window that is still in the status Error, its scope (OcuTalon.Watch.FailurePoller Scope of its
/// SuperSession) is the incident's owner, and its field reads in the source format. A failed message of the scope whose field does not read (another format,
/// no value, or no body that can be read) is counted as affected and left out.
/// Recheck and Execute (Story 7.3) take their targets from the approved request's row (AD-11), never from the incident's groups. They read each target again
/// through Reader.Evidence (the incident's namespace and production, the first failure group's ItemName, with the resent flag) and compare it with the dry run's
/// test: a target passes only if its header still exists in the status Error, its scope is the incident's owner, no header of its session names it as resent,
/// it still has its body, and the field is a stored datatype property of the body whose value still reads in the source format. Every other target is skipped
/// with one plain reason that names it, and is never acted on. Execute resends a repaired copy of each target that passes through Fix.Executor.Resend, which
/// holds the one namespace switch of the executor; the originals are never changed.
/// Dates that read two ways (DW-644): for a source format that is an order format (MM/DD/YYYY or DD/MM/YYYY), a target value is one-way when it reads only in the
/// source format, and two-way when it also reads in the other order. Evidence says what, if anything, singles out the source reading over the dry run's targets:
/// oneway (any target value is one-way), arrival (every two-way value whose two readings differ matches the source reading: that reading's date is within
/// ARRIVALDAYS days, either way, of the UTC date of its own failed header's TimeCreated), same (every value's two readings are the same date, so nothing is
/// chosen), none (otherwise), or n/a (the source is not an order format). The dry run refuses, with a reason, exactly when the evidence is none. Its example
/// (before and after) is the first one-way target, else the first target whose readings differ, else the first target, so that a raised request's before reads
/// two ways with different readings exactly when every target value does. The stored dry run keeps its keys. Lane A.
/// Good messages (Story 7.9, FR-25): before a fix is offered, the dry run reads, for each distinct source of its targets (SourceConfigName, TargetConfigName, body class
/// and SuperSession of a target, the reference being the lowest target header id of that tuple), the newest GOODMAX messages from that source that went through
/// (OcuTalon.Watch.Reader Good: Completed, no error, requests) and applies the target test and the repair to each in memory (GoodChanges). A good message is changed
/// exactly when its field reads in the source format and the repair gives another text. The dry run is refused (GOODCHANGED, a reason for the log) when any would change.
/// Otherwise the answer also holds goodCheck {"checked", "changed"}: the number read and the number changed, which is 0. goodCheck belongs to the answer only: the stored
/// dry run keeps exactly the keys of DRYRUNKEYS (IncidentManager). The check reads and counts, and never resends or changes a good message.
Class OcuTalon.Fix.Kind.RepairResend Extends OcuTalon.Fix.Kind
{

Parameter NAME = "repair_resend";

Parameter PARAMETERS = "field,sourceFormat,targetFormat";

Parameter RESOURCES = "%Ens_MessageResend:U";

/// The keys of the dry run of this kind: the keys of OcuTalon.Bridge.Data.ApprovalRequest DRYRUNKEYS that a repair and resend fills.
Parameter DRYRUNKEYS = "affected,resend,leftOut,field,before,after,itemNoun";

/// The days, either way, between a reading and the UTC date a message arrived within which the reading matches that arrival (a partner's own date can differ
/// from the UTC date by up to a day either side).
Parameter ARRIVALDAYS = 1;

/// The plain reason of a run that cannot start without RESOURCES (Fix.Executor gives it as the Reason of the FixResult; the catalog renders it after "Nothing was resent: ").
Parameter NOTALLOWED = "OcuTalon isn't allowed to resend messages in that production";

/// The reason of a dry run that has no evidence for the source reading of its dates.
Parameter NOEVIDENCE = "The dates read as valid dates both month first and day first, and nothing shows which: no date has a day above 12, and the dates do not all match, within a day, the day their message arrived";

/// The most good messages the dry run reads for each source of its targets (the newest ones, Reader.Good).
Parameter GOODMAX = 20;

/// The key of the dry run's answer that holds the counts of the good-message check; it is not a key of DRYRUNKEYS and is never stored.
Parameter GOODCHECK = "goodCheck";

/// The reason of a dry run whose repair would also change good messages; {changed} and {checked} are the two counts. It is a reason for the log, never shown.
Parameter GOODCHANGED = "The repair would also change {changed} of the {checked} messages from the same source that went through";

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
/// the incident has no failed message of its scope or the parameters do not pass CheckParameters against the body of the first of them that has one, or when the
/// repair would also change a good message from the source of a target (see the class description). With targets, dryRun also holds GOODCHECK, {"checked", "changed"}
/// (changed is 0 here), which is not a key of DRYRUNKEYS.
ClassMethod DryRun(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, Output targets As %String, Output dryRun As %DynamicObject) As %Status
{
	Set targets = ""
	Set dryRun = ""
	Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident.Ref)
	Set sc = ..Failed(incident, 0, .scoped, .unlisted, .classes, .arrived, .origin)
	If $$$ISERR(sc) Quit sc
	Set (before, after) = ""
	Set haveExample = 0
	Set sourceFormat = parameters.%Get("sourceFormat")
	Set orderFormat = (##class(OcuTalon.Fix.Reformat).OtherOrder(sourceFormat) '= "")
	Set values = []
	Set (oneWayFound, differFound) = 0
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
	Set affected = unlisted
	Set id = ""
	For {
		Set id = $Order(scoped(id))
		Quit:id=""
		Set affected = affected + 1
		If ..Readable(scoped(id), parameters, .current, .repaired) '= "" Continue
		Set targets = targets _ $Select(targets = "": "", 1: ",") _ id
		Do values.%Push({"value": (current), "arrived": ($Get(arrived(id)))})
		If 'haveExample {
			Set haveExample = 1
			Set before = current
			Set after = repaired
		}
		If orderFormat {
			Set twoWay = ##class(OcuTalon.Fix.Reformat).Readings(current, sourceFormat, .daySource, .dayOther)
			If 'twoWay && 'oneWayFound {
				Set oneWayFound = 1
				Set oneWayBefore = current
				Set oneWayAfter = repaired
			} ElseIf twoWay && (daySource '= dayOther) && 'differFound {
				Set differFound = 1
				Set differBefore = current
				Set differAfter = repaired
			}
		}
	}
	If orderFormat {
		If oneWayFound {
			Set before = oneWayBefore, after = oneWayAfter
		} ElseIf differFound {
			Set before = differBefore, after = differAfter
		}
		If ..Evidence(values, sourceFormat) = "none" Quit $$$ERROR($$$GeneralError, ..#NOEVIDENCE)
	}
	Set goodChecked = 0
	If targets '= "" {
		Set references = ""
		For i = 1:1:$Length(targets, ",") {
			Set id = $Piece(targets, ",", i)
			If $Data(reference(origin(id))) Continue
			Set reference(origin(id)) = id
			Set references = references _ $Select(references = "": "", 1: ",") _ id
		}
		Set outcome = ##class(OcuTalon.Watch.Reader).Good(incident.Namespace, incident.Production, groups.GetAt(1).ItemName, references, ..#GOODMAX, .good)
		If outcome '= "read" {
			Quit $$$ERROR($$$GeneralError, "The messages from the same source that went through, in "_incident.Production_" in "_incident.Namespace_", could not be read: "_$Select(outcome = "unreadable": "the service user cannot read the namespace", outcome = "not_current": "the production is not the one that runs there", 1: outcome))
		}
		Set goodChanged = 0
		For i = 0:1:good.%Size() - 1 {
			Set goodChecked = goodChecked + 1
			If ..GoodChanges(good.%Get(i).body, parameters) Set goodChanged = goodChanged + 1
		}
		If goodChanged > 0 Quit $$$ERROR($$$GeneralError, $Replace($Replace(..#GOODCHANGED, "{changed}", goodChanged), "{checked}", goodChecked))
	}
	Set noun = ..ItemNounOf(incident, classes(first))
	Set resend = $Select(targets = "": 0, 1: $Length(targets, ","))
	Set out("affected") = affected
	Set out("resend") = resend
	Set out("leftOut") = affected - resend
	Set out("field") = ..FieldWords(field)
	Set out("before") = before
	Set out("after") = after
	Set dryRun = {}
	Set keyNames = ..#DRYRUNKEYS
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
	If targets '= "" {
		Do dryRun.%Set(..#GOODCHECK, {"checked": (goodChecked), "changed": 0})
	}
	Quit $$$OK
}

/// 1 when the repair would change the message: its body (as Reader.Good reads it) passes the target test (Readable: the field is there and its value reads in the source
/// format) and the repaired value differs from the current one, compared as text. A value that does not read, an empty or missing field and an unreadable body are not
/// changed, and neither is a value that converts to itself (11/11/2026 from MM/DD/YYYY to DD/MM/YYYY). Pure.
ClassMethod GoodChanges(body As %DynamicObject, parameters As %DynamicObject) As %Boolean
{
	If ..Readable($Get(body), parameters, .current, .repaired) '= "" Quit 0
	Quit ($Get(current) '= $Get(repaired))
}

/// What singles out the source reading of the dates of values (see the class description): "n/a" when format is not an order format, "oneway" when any value reads
/// only in format, "arrival" when every value that reads both ways with two different dates matches the format's reading of the arrival, "same" when no value
/// does (every value reads as one date), else "none". values holds {"value", "arrived"} (arrived as Reader.Evidence gives timeCreated: YYYY-MM-DDThh:mm:ssZ, UTC);
/// an empty or malformed arrived never matches. twoWay is the number of values that read both ways. A value that does not read in format is not counted. Pure.
ClassMethod Evidence(values As %DynamicArray, format As %String, Output twoWay As %Integer) As %String
{
	Set twoWay = 0
	If ##class(OcuTalon.Fix.Reformat).OtherOrder($Get(format)) = "" Quit "n/a"
	Set oneWay = 0
	Set differing = 0
	Set unmatched = 0
	If $IsObject($Get(values)) {
		Set iterator = values.%GetIterator()
		While iterator.%GetNext(, .entry) {
			Set value = entry.value
			If '##class(OcuTalon.Fix.Reformat).Reads(value, format) Continue
			If '##class(OcuTalon.Fix.Reformat).Readings(value, format, .daySource, .dayOther) {
				Set oneWay = 1
				Continue
			}
			Set twoWay = twoWay + 1
			If daySource = dayOther Continue
			Set differing = differing + 1
			If '..Matches(daySource, entry.arrived) Set unmatched = unmatched + 1
		}
	}
	If oneWay Quit "oneway"
	If differing = 0 Quit "same"
	Quit $Select(unmatched = 0: "arrival", 1: "none")
}

/// 1 when the day number (a $ZDATEH value) is within ARRIVALDAYS days, either way, of the UTC date of arrived (YYYY-MM-DDThh:mm:ssZ); 0 when arrived is not that.
ClassMethod Matches(day As %Integer, arrived As %String) As %Boolean [ Private ]
{
	Set arrived = $Get(arrived)
	If '$Match(arrived, "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z") Quit 0
	Set arrival = $ZDateH($Extract(arrived, 1, 10), 3, , , , , , , -1)
	If arrival < 0 Quit 0
	Quit $Select($ZAbs(day - arrival) <= ..#ARRIVALDAYS: 1, 1: 0)
}

/// Re-checks the targets (comma-separated header ids, ascending) of an approved request before any copy is made (see the class description). passed holds the
/// ids that still are targets, comma-separated and ascending; skipped the others, each {"id", "reason"} with a plain reason that names the message. It changes
/// nothing. An error status that says why when the parameters do not pass CheckParameters or the failed messages cannot be read at all (the namespace is
/// unreadable, the production is not the one that runs there, or the read threw).
ClassMethod Recheck(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output passed As %String, Output skipped As %DynamicArray) As %Status
{
	Set passed = ""
	Set skipped = []
	Set sc = ..Plan(incident, parameters, targets, .plan, .skipped)
	If $$$ISERR(sc) Quit sc
	Set iterator = plan.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set passed = passed _ $Select(passed = "": "", 1: ",") _ entry.id
	}
	Quit $$$OK
}

/// Resends a repaired copy of each of the targets (those that passed Recheck) through Fix.Executor.Resend and registers each copy on run (see the class
/// description). The targets are read again by the same test as Recheck, so that a value that changed since the re-check is skipped, and the value that is read
/// is the one the copy is checked against at the switch. result is {"resent": the copies made, "skipped": [{"id", "reason"}], "unreached": [{"id", "code"}]}: the targets left out
/// by the test and by the resend because they really changed, in the order they were left out, and the targets the resend never reached (the first copy that erred and every
/// target after it; Executor.Resend), which are in no skipped entry. An error status when the failed messages cannot be read.
ClassMethod Execute(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output result As %DynamicObject, run As OcuTalon.Data.FixRun = "") As %Status
{
	Set result = {"resent": 0, "skipped": [], "unreached": []}
	Set sc = ..Plan(incident, parameters, targets, .plan, .skipped)
	If $$$ISERR(sc) Quit sc
	Set result.skipped = skipped
	If plan.%Size() = 0 Quit $$$OK
	Do ##class(OcuTalon.Fix.Executor).Resend(incident.Namespace, plan, run, .resent, .resendSkipped, .unreached)
	Set result.resent = resent
	Set result.unreached = unreached
	Set iterator = resendSkipped.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Do result.skipped.%Push(entry)
	}
	Quit $$$OK
}

/// The test of Recheck and Execute over the targets: plan holds {"id", "field", "value", "repaired"} for each target that passes (value is what the field holds
/// now, repaired what it becomes), skipped {"id", "reason"} for each that does not, both in target order. An error status when the parameters do not pass
/// CheckParameters, the incident has no failure group or the failed messages cannot be read at all.
ClassMethod Plan(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output plan As %DynamicArray, Output skipped As %DynamicArray) As %Status [ Private ]
{
	Set plan = []
	Set skipped = []
	Set field = $Select($IsObject(parameters): parameters.%Get("field"), 1: "")
	Set sc = ..CheckParameters(parameters, [(field)])
	If $$$ISERR(sc) Quit sc
	Set sc = ..Targeted(incident, targets, .found)
	If $$$ISERR(sc) Quit sc
	For i = 1:1:$Length(targets, ",") {
		Set id = +$Piece(targets, ",", i)
		If '$Data(found(id)) {
			Do skipped.%Push({"id": (id), "reason": (..Reason("missing", id, parameters))})
			Continue
		}
		Set failure = found(id)
		Set code = ..Standing(failure, incident)
		If code = "" Set code = $Select($IsObject(failure.resentBy) && (failure.resentBy.%Size() > 0): "resent", 1: "")
		If code = "" Set code = ..Readable(failure.body, parameters, .current, .repaired)
		If code '= "" {
			Do skipped.%Push({"id": (id), "reason": (..Reason(code, id, parameters))})
			Continue
		}
		Do plan.%Push({"id": (id), "field": (field), "value": (current), "repaired": (repaired)})
	}
	Quit $$$OK
}

/// "" when the field reads in the source format: the body (a dynamic object of the stored datatype properties of the message body, as Reader.Evidence reads
/// it) has members, the field is one of them and its value converts (Fix.Reformat Convert); current is the value and repaired its repair. Else body, field or
/// value, the first test it fails. The part of the target test that DryRun, Recheck and Execute share.
ClassMethod Readable(body As %DynamicObject, parameters As %DynamicObject, Output current As %String, Output repaired As %String) As %String [ Private ]
{
	Set (current, repaired) = ""
	If '$IsObject(body) || 'body.%IsA("%Library.DynamicObject") || (body.%Size() = 0) Quit "body"
	Set field = parameters.%Get("field")
	If 'body.%IsDefined(field) Quit "field"
	Set current = body.%Get(field)
	If $$$ISERR(##class(OcuTalon.Fix.Reformat).Convert(current, parameters.%Get("sourceFormat"), parameters.%Get("targetFormat"), .repaired)) Quit "value"
	Quit ""
}

/// The plain reason, naming the message, that a target is skipped for the code of the test it failed (missing, status, scope, resent, body, field or value).
ClassMethod Reason(code As %String, id As %String, parameters As %DynamicObject) As %String [ Private ]
{
	Set text = ..MessageReason(code, id)
	If text '= "" Quit text
	Set name = "message "_id
	Set words = ..FieldWords(parameters.%Get("field"))
	If code = "body" Quit name_" has no body that can be read any more"
	If code = "field" Quit "the "_words_" is no longer a stored field of "_name
	Quit "the "_words_" of "_name_" no longer reads as "_parameters.%Get("sourceFormat")
}

}
