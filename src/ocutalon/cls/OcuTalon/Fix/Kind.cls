/// The contract of a fix kind (AD-16). A kind is a class under OcuTalon.Fix.Kind that implements DryRun, Recheck and Execute against fixed targets, with a
/// parameter schema. The model picks only the kind (its NAME) and the kind's parameters; the kind validates them (CheckParameters) and does the work in code.
///   - NAME is the kind's name as the diagnosis writes it (fixKind); PARAMETERS the names of its parameters, comma-separated, each a required string that is not blank;
///     RESOURCES the IRIS privileges the kind needs, in the tool form resource:permission[,resource:permission...] (Install.Step.Fix composes them into the
///     service role's grants; the executor checks them before it runs Execute, Story 7.3);
///   - KINDS is the fixed set of kinds that exist, as class names: a class that is not listed is not a kind. A step that adds a kind adds its class here;
///   - Check(name, parameters, fields) is what the reply check of a diagnosis calls: an unknown kind, and a kind the diagnosis may not name (DIAGNOSED 0), is an error, else
///     the kind's CheckParameters, which is given the field names of the sample message as the model saw them;
///   - NOTALLOWED is the plain reason of a run that cannot start because the service user lacks a pair of RESOURCES ("OcuTalon isn't allowed to ... in that
///     production"); FixExecutor gives it as the Reason of the FixResult and the message catalog renders it (Story 7.3);
///   - DryRun works out the targets and the dry run's JSON without changing anything; Recheck and Execute (Story 7.3) take the same first three arguments and
///     each returns not implemented here:
///       Recheck re-reads the targets of the approved request before any copy is made and gives the ids that may still be sent (passed, comma-separated and
///       ascending) and, for every other target, one skipped entry {"id", "reason"}, the reason a plain sentence that names the target. It changes nothing. An
///       error status means that the production could not be read at all;
///       Execute carries the fix out for the targets given (those that passed), one by one, and registers each copy on the run (the FixRun row the executor
///       made for the request). result holds {"resent": the copies made, "skipped": [{"id", "reason"}]} for the targets it left out.
///   - TARGETTYPE is what the targets name: "message" (the default; header ids of the incident's failed messages), "item" (Ens.Config.Item ids of the incident's
///     production, one per item) or "contact" (Fix.PartnerContacts ids of the incident's production, one per recipient) or "recipient" (the positions 1..n of the recipients of an email, which has no incident, Story 22.7); DIAGNOSED is 1 when the diagnosis may name the kind (Watch.Msg.DiagnosisPayload accepts only those) and ASKED is 1 when the user may
///     ask for it in the chat (propose_fix, Story 23.2); NOSTART and NOREAD are the kind's own plain reasons for a run that could not start and for one that could not
///     read the production, where the executor's say resend (empty means the executor's);
///   - DRAFTED is 1 when the kind's text is drafted by the model through IncidentManager before its dry run (the dry run then holds the drafted text); MOVES is 0 when the
///     kind's requests never move the incident's state; NOTSETUP is the plain reason of a kind that can't deliver yet; Ready(incident, .reason) is 1 unless the kind can't run now,
///     and then says why (Story 23.5);
///   - Standing and Failed are the shared reading of an incident's failed messages: Standing is the part of the target test that every message kind shares, and Failed
///     reads the failures of an incident's failure groups, in a request's window (the kinds the diagnosis proposes) or in the groups' whole Seen (a kind the chat asks for).
///   - The result of Execute for a kind whose targets are items is {"changed": the items changed, "skipped": [{"id", "reason"}], "unreached": [{"id", "code"}]}; for a kind
///     whose targets are contacts it is {"deliveries": [{"id", "name", "address"}], "skipped": [{"id", "reason"}]}, and the executor does the delivering.
/// Targets are header ids, comma-separated and ascending (Item ids for TARGETTYPE item, contact ids for TARGETTYPE contact). Lane A.
Class OcuTalon.Fix.Kind [ Abstract ]
{

/// The kind's name, as the diagnosis writes it.
Parameter NAME;

/// The names of the kind's parameters, comma-separated.
Parameter PARAMETERS;

/// The privileges the kind needs, as resource:permission[,resource:permission...] (Consistency Conventions: Tool resources).
Parameter RESOURCES;

/// The plain reason of a run that cannot start without RESOURCES (Story 7.3); empty here.
Parameter NOTALLOWED;

/// What the kind's targets name: "message" (header ids), "item" (Ens.Config.Item ids of the incident's production) or "contact" (Fix.PartnerContacts ids).
Parameter TARGETTYPE = "message";

/// 1 when the diagnosis may name the kind (its fixKind), 0 when only the chat can ask for it.
Parameter DIAGNOSED = 1;

/// 1 when the user may ask for the kind in the chat (propose_fix).
Parameter ASKED = 0;

/// 1 when an online-demo install grants the kind's RESOURCES to the service role (Install.Step.Fix); 0 leaves them off it, so that the kind can't run there (AD-24).
Parameter ONLINEGRANT = 1;

/// The kind's own plain reasons for a run that could not start and for one that could not read the production; empty means the executor's.
Parameter NOSTART;

Parameter NOREAD;

/// 1 when the kind's text is drafted by the model through IncidentManager before its dry run; 0 when its parameters come from the ask.
Parameter DRAFTED = 0;

/// 0 when the kind's requests never move the incident's state: they are told to the sessions, answered and carried out in any state but closed.
Parameter MOVES = 1;

/// The plain reason of a run that can't start because the kind can't deliver yet (Ready); empty for a kind that always can.
Parameter NOTSETUP;

/// The status text of a message that failed, as Reader.Evidence gives it.
Parameter ERRORSTATUS = "Error";

/// The kinds that exist, as class names, comma-separated.
Parameter KINDS = "OcuTalon.Fix.Kind.RepairResend,OcuTalon.Fix.Kind.SuspendItem,OcuTalon.Fix.Kind.ResumeItem,OcuTalon.Fix.Kind.Reroute,OcuTalon.Fix.Kind.PartnerWarning,OcuTalon.Fix.Kind.Email";

/// The classes of KINDS that are compiled and extend this class, as a list.
ClassMethod Classes() As %List
{
	Set classes = ""
	For i = 1:1:$Length(..#KINDS, ",") {
		Set class = $ZStrip($Piece(..#KINDS, ",", i), "<>W")
		If class = "" Continue
		If '##class(%Dictionary.CompiledClass).%ExistsId(class) Continue
		If '$ClassMethod(class, "%Extends", "OcuTalon.Fix.Kind") Continue
		Set classes = classes _ $ListBuild(class)
	}
	Quit classes
}

/// The NAME of each class of Classes, as a list.
ClassMethod Names() As %List
{
	Set names = ""
	Set position = 0
	Set classes = ..Classes()
	While $ListNext(classes, position, class) {
		Set names = names _ $ListBuild($Parameter(class, "NAME"))
	}
	Quit names
}

/// The class of the kind with the name, matched exactly, or "" for an unknown name.
ClassMethod ForName(name As %String) As %String
{
	If $Get(name) = "" Quit ""
	Set position = 0
	Set classes = ..Classes()
	While $ListNext(classes, position, class) {
		If $Parameter(class, "NAME") = name Return class
	}
	Quit ""
}

/// The NAME of each class of Classes that the diagnosis may name (DIAGNOSED 1), as a list.
ClassMethod DiagnosedNames() As %List
{
	Set names = ""
	Set position = 0
	Set classes = ..Classes()
	While $ListNext(classes, position, class) {
		If $Parameter(class, "DIAGNOSED") Set names = names _ $ListBuild($Parameter(class, "NAME"))
	}
	Quit names
}

/// 1 when the name is the NAME of a kind with DIAGNOSED 1, matched exactly.
ClassMethod Diagnosed(name As %String) As %Boolean
{
	Set class = ..ForName($Get(name))
	Quit (class '= "") && ''$Parameter(class, "DIAGNOSED")
}

/// Checks the parameters of the kind with the name. fields is the array of the field names of the sample message (the keys of its body). An error
/// status that says why when the kind is unknown or its CheckParameters refuses.
ClassMethod Check(name As %String, parameters As %DynamicObject, fields As %DynamicArray) As %Status
{
	Set class = ..ForName($Get(name))
	If (class = "") || '$Parameter(class, "DIAGNOSED") Quit $$$ERROR($$$GeneralError, "The fixKind '"_$Get(name)_"' is not one of "_$ListToString(..DiagnosedNames(), ","))
	Quit $ClassMethod(class, "CheckParameters", $Get(parameters), $Get(fields))
}

/// The schema check of the base: parameters is an object whose keys are exactly PARAMETERS, each a string that is not blank. A kind adds its own
/// checks after it. fields is the array of the field names of the sample message.
ClassMethod CheckParameters(parameters As %DynamicObject, fields As %DynamicArray) As %Status
{
	If '$IsObject(parameters) || 'parameters.%IsA("%Library.DynamicObject") {
		Quit $$$ERROR($$$GeneralError, "The parameters of "_..#NAME_" are not a JSON object")
	}
	Set names = $ListFromString(..#PARAMETERS)
	Set iterator = parameters.%GetIterator()
	While iterator.%GetNext(.key) {
		If '$ListFind(names, key) Return $$$ERROR($$$GeneralError, "The parameter '"_key_"' is not one of "_..#PARAMETERS)
	}
	Set position = 0
	While $ListNext(names, position, key) {
		If parameters.%GetTypeOf(key) '= "string" Return $$$ERROR($$$GeneralError, "The parameter '"_key_"' of "_..#NAME_" is required and is a string")
		If $ZStrip(parameters.%Get(key), "*WC") = "" Return $$$ERROR($$$GeneralError, "The parameter '"_key_"' of "_..#NAME_" is blank")
	}
	Quit $$$OK
}

/// "" when the failed message is one of the incident's: its status is still ERRORSTATUS and its scope (FailurePoller Scope of its SuperSession) is the incident's
/// owner; else status or scope, the first test it fails. The part of the target test that every message kind shares.
ClassMethod Standing(failure As %DynamicObject, incident As OcuTalon.Data.Incident) As %String
{
	If failure.status '= ..#ERRORSTATUS Quit "status"
	If ##class(OcuTalon.Watch.FailurePoller).Scope(failure.superSession) '= incident.OwnerRef Quit "scope"
	Quit ""
}

/// Reads the failed messages of the incident's failure groups that are still the incident's own (Standing), once each, through Reader.Evidence. With whole 0 it reads the
/// keys that each group's newest ask covers (FailureGroup.AskedKeys: a diagnosis's request); with whole 1 the groups' whole Seen, and it leaves out a message that an
/// earlier run resent (a chat ask moves no window marks). scoped(id) is the message's body (a dynamic object of its stored datatype properties), classes(id) its body
/// class, arrived(id) its TimeCreated and origin(id) a list of its source, its target, its body class and its SuperSession, all by header id. unlisted is the number of
/// failures that the window (whole 0) or Seen (whole 1) no longer lists and that so can't be read: each counts as affected. An error status that says why when the
/// failures of a window can't all be listed or the production can't be read.
ClassMethod Failed(incident As OcuTalon.Data.Incident, whole As %Boolean, Output scoped, Output unlisted As %Integer, Output classes, Output arrived, Output origin) As %Status
{
	Kill scoped, classes, arrived, origin
	Set unlisted = 0
	Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident.Ref)
	For g = 1:1:groups.Count() {
		Set group = groups.GetAt(g)
		If whole {
			Set listed = 0
			For i = 1:1:$Length(group.Seen, ",") {
				If $Piece(group.Seen, ",", i) '= "" Set listed = listed + 1
			}
			Set dropped = $Select(+group.Count > listed: +group.Count - listed, 1: 0)
			Set known = 1
			Set asked = group.Seen
		} Else {
			Set dropped = group.Unlisted(.known)
			Set asked = group.AskedKeys()
		}
		If 'known Return $$$ERROR($$$GeneralError, "The failed messages of "_group.ItemName_" that this request covers are no longer all listed, so they can't be counted")
		Set unlisted = unlisted + dropped
		Set keys = ""
		For i = 1:1:$Length(asked, ",") {
			Set key = $Piece(asked, ",", i)
			If key ? 1"h".N Set keys = keys _ $Select(keys = "": "", 1: ",") _ key
		}
		If keys = "" Continue
		Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(incident.Namespace, incident.Production, group.ItemName, keys, .snapshot, whole)
		If outcome '= "read" {
			Return $$$ERROR($$$GeneralError, "The failed messages of "_incident.Production_" in "_incident.Namespace_" could not be read: "_$Select(outcome = "unreadable": "the service user cannot read the namespace", outcome = "not_current": "the production is not the one that runs there", 1: outcome))
		}
		For i = 0:1:snapshot.failures.%Size() - 1 {
			Set failure = snapshot.failures.%Get(i)
			If ..Standing(failure, incident) '= "" Continue
			If whole && $IsObject(failure.resentBy) && (failure.resentBy.%Size() > 0) Continue
			Set id = +failure.headerId
			If $Data(scoped(id)) Continue
			Set scoped(id) = $Select($IsObject(failure.body) && failure.body.%IsA("%Library.DynamicObject"): failure.body, 1: {})
			Set classes(id) = failure.bodyClass
			Set arrived(id) = failure.timeCreated
			Set origin(id) = $ListBuild(failure.sourceConfigName, failure.targetConfigName, failure.bodyClass, failure.superSession)
		}
	}
	Quit $$$OK
}

/// 1 when the kind can run now; else 0 and reason says why (a plain sentence), which the executor ends the run with. The base kind always can.
ClassMethod Ready(incident As OcuTalon.Data.Incident, Output reason As %String) As %Boolean
{
	Set reason = ""
	Quit 1
}

/// The display name of the incident's production (Reader.Admits), else its class name (also when the production list can't be read): the name the kinds' reasons give.
ClassMethod ProductionName(incident As OcuTalon.Data.Incident) As %String
{
	Try {
		If ##class(OcuTalon.Watch.Reader).Admits(incident.Namespace, incident.Production, .name) Quit
	} Catch {
	}
	Quit $Select($Get(name) '= "": name, 1: incident.Production)
}

/// The items of the incident's production (Reader.Items) as a dynamic array of {"id", "name", "className", "businessType", "enabled"}. When the production can't be read, an
/// error status whose text is the item kinds' plain reason (SuspendItem NOREAD), which the chat model is given.
ClassMethod ItemsOf(incident As OcuTalon.Data.Incident, Output items As %DynamicArray) As %Status
{
	Set outcome = ##class(OcuTalon.Watch.Reader).Items(incident.Namespace, incident.Production, .items)
	If outcome '= "read" Quit $$$ERROR($$$GeneralError, ##class(OcuTalon.Fix.Kind.SuspendItem).#NOREAD)
	Quit $$$OK
}

/// The item of the name among items (ItemsOf), matched exactly, as the dynamic object ItemsOf gives; "" when there is none.
ClassMethod ItemNamed(items As %DynamicArray, name As %String) As %DynamicObject
{
	Set iterator = items.%GetIterator()
	While iterator.%GetNext(, .item) {
		If "k"_item.name = ("k"_name) Return item
	}
	Quit ""
}

/// The failed messages of the targets (header ids, comma-separated), read again for a re-check, through Reader.Evidence with the flag that adds resentBy: found(id) is the
/// failure as Evidence gives it. An error status that says why when the incident has no failure group or the production can't be read.
ClassMethod Targeted(incident As OcuTalon.Data.Incident, targets As %String, Output found) As %Status
{
	Kill found
	Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident.Ref)
	If groups.Count() = 0 Quit $$$ERROR($$$GeneralError, "The incident "_incident.Ref_" has no failure group to read")
	Set keys = ""
	For i = 1:1:$Length(targets, ",") {
		Set id = $Piece(targets, ",", i)
		If id ? 1.N Set keys = keys _ $Select(keys = "": "", 1: ",") _ "h" _ id
	}
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(incident.Namespace, incident.Production, groups.GetAt(1).ItemName, keys, .snapshot, 1)
	If outcome '= "read" {
		Quit $$$ERROR($$$GeneralError, "The failed messages of "_incident.Production_" in "_incident.Namespace_" could not be read: "_$Select(outcome = "unreadable": "the service user cannot read the namespace", outcome = "not_current": "the production is not the one that runs there", 1: outcome))
	}
	For i = 0:1:snapshot.failures.%Size() - 1 {
		Set failure = snapshot.failures.%Get(i)
		Set found(+failure.headerId) = failure
	}
	Quit $$$OK
}

/// The plain sentence, naming the message, for a target that failed a test every message kind shares: missing, status, scope or resent; "" for any other code.
ClassMethod MessageReason(code As %String, id As %String) As %String
{
	Set name = "message "_id
	If code = "missing" Quit name_" is no longer in the production"
	If code = "status" Quit name_" is no longer in the error status"
	If code = "scope" Quit name_" is not one of this request's failed messages any more"
	If code = "resent" Quit name_" has been resent already"
	Quit ""
}

/// The item noun {"one", "other"} of the incident's failed messages: the incident's own when it has both forms, else the code noun of the body class.
ClassMethod ItemNounOf(incident As OcuTalon.Data.Incident, bodyClass As %String) As %DynamicObject
{
	Set noun = ""
	If incident.ItemNoun '= "" {
		Try {
			Set noun = {}.%FromJSON(incident.ItemNoun)
		} Catch {
			Set noun = ""
		}
	}
	If '$IsObject(noun) || 'noun.%IsA("%Library.DynamicObject") || (noun.one = "") || (noun.other = "") Set noun = {}.%FromJSON(##class(OcuTalon.Watch.ItemNoun).For($Get(bodyClass)))
	Quit noun
}

/// Works out, for the incident's failure group, the header ids to resend (targets: comma-separated, ascending) and the dry run (a dynamic object with
/// the keys of OcuTalon.Bridge.Data.ApprovalRequest DRYRUNKEYS, and the kind's own transient keys such as repair_resend's goodCheck, which are never stored), and changes nothing. An error status that says why when it cannot be worked out.
ClassMethod DryRun(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, Output targets As %String, Output dryRun As %DynamicObject) As %Status
{
	Set targets = ""
	Set dryRun = ""
	Quit $$$ERROR($$$NotImplemented)
}

/// Re-checks the targets of an approved request before any copy is made (see the class description): passed holds the ids that may be sent, comma-separated and
/// ascending, skipped the others as {"id", "reason"} entries. Changes nothing. An error status when the production cannot be read at all. A kind implements it.
ClassMethod Recheck(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output passed As %String, Output skipped As %DynamicArray) As %Status
{
	Set passed = ""
	Set skipped = []
	Quit $$$ERROR($$$NotImplemented)
}

/// Carries the fix out for the targets (those that passed Recheck) and registers each copy on run, the FixRun row of the request (see the class description).
/// result is {"resent", "skipped"}. A kind implements it.
ClassMethod Execute(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output result As %DynamicObject, run As OcuTalon.Data.FixRun = "") As %Status
{
	Set result = ""
	Quit $$$ERROR($$$NotImplemented)
}

}
