/// The contract of a fix kind (AD-16). A kind is a class under OcuTalon.Fix.Kind that implements DryRun, Recheck and Execute against fixed targets, with a
/// parameter schema. The model picks only the kind (its NAME) and the kind's parameters; the kind validates them (CheckParameters) and does the work in code.
///   - NAME is the kind's name as the diagnosis writes it (fixKind); PARAMETERS the names of its parameters, comma-separated, each a required string that is not blank;
///     RESOURCES the IRIS privileges the kind needs, in the tool form resource:permission[,resource:permission...] (Install.Step.Fix composes them into the
///     service role's grants; the executor checks them before it runs);
///   - KINDS is the fixed set of kinds that exist, as class names: a class that is not listed is not a kind. A step that adds a kind adds its class here;
///   - Check(name, parameters, fields) is what the reply check of a diagnosis calls: an unknown kind is an error, else the kind's CheckParameters, which is given
///     the field names of the sample message as the model saw them;
///   - DryRun works out the targets and the dry run's JSON without changing anything; Recheck (Story 7.3) and Execute (Story 7.3) take the same first three arguments.
///     Each returns not implemented here.
/// Targets are header ids, comma-separated and ascending. Lane A.
Class OcuTalon.Fix.Kind [ Abstract ]
{

/// The kind's name, as the diagnosis writes it.
Parameter NAME;

/// The names of the kind's parameters, comma-separated.
Parameter PARAMETERS;

/// The privileges the kind needs, as resource:permission[,resource:permission...] (Consistency Conventions: Tool resources).
Parameter RESOURCES;

/// The kinds that exist, as class names, comma-separated.
Parameter KINDS = "OcuTalon.Fix.Kind.RepairResend";

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

/// Checks the parameters of the kind with the name. fields is the array of the field names of the sample message (the keys of its body). An error
/// status that says why when the kind is unknown or its CheckParameters refuses.
ClassMethod Check(name As %String, parameters As %DynamicObject, fields As %DynamicArray) As %Status
{
	Set class = ..ForName($Get(name))
	If class = "" Quit $$$ERROR($$$GeneralError, "The fixKind '"_$Get(name)_"' is not one of "_$ListToString(..Names(), ","))
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

/// Works out, for the incident's failure group, the header ids to resend (targets: comma-separated, ascending) and the dry run (a dynamic object with
/// exactly the keys of OcuTalon.Bridge.Data.ApprovalRequest DRYRUNKEYS), and changes nothing. An error status that says why when it cannot be worked out.
ClassMethod DryRun(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, Output targets As %String, Output dryRun As %DynamicObject) As %Status
{
	Set targets = ""
	Set dryRun = ""
	Quit $$$ERROR($$$NotImplemented)
}

/// Story 7.3: re-checks the targets before the run: passed holds the ids that may be sent, skipped the ones that are left out, each with its reason.
ClassMethod Recheck(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output passed As %String, Output skipped As %DynamicArray) As %Status
{
	Set passed = ""
	Set skipped = []
	Quit $$$ERROR($$$NotImplemented)
}

/// Story 7.3: carries the fix out for the targets; result is the run's counts.
ClassMethod Execute(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output result As %DynamicObject) As %Status
{
	Set result = ""
	Quit $$$ERROR($$$NotImplemented)
}

}
