/// The recorder of the evaluation set's incidents (AD-22, AD-15; FR-62; Story 9.4). Lane A. It runs outside AI Hub's callbacks, in a throwaway or on an author's
/// instance, never in a flow of the product, and it writes no row of any table.
///   - Capture reads the failures with the given keys from a production through OcuTalon.Watch.Reader.Evidence, the reader that
///     EvidencePack.Build reads, and writes them with Write. Its pack is the evidence pack that Build gives the reader's answer before anything
///     changes it, so that a replay of the written file can be compared with what the diagnosis reads live.
///   - Write puts two files in <folder>/<name>/ and replaces any that is there: snapshot.json, the reader's answer (format
///     ocutalon.readerSnapshot/1) after OcuTalon.Bridge.Redact.Text, with nothing added and nothing dropped, and case.json, the case format of Story 9.1:
///     {name, kind "incident", heldOut, description, snapshot "snapshot.json", expectation {causeCategory, elementAtFault, fixKind}, recordedBy}.
///     Each file is compact JSON followed by one line feed. A pack is never written.
///   - Write refuses with an error status that names the reason, and makes no folder or file, when: the case is not valid (a valid case is a JSON
///     object whose name is lower-case kebab, whose heldOut is a boolean or absent, whose description is not blank, and whose expectation is an
///     object with a causeCategory of DiagnosisPayload CAUSECATEGORIES, an elementAtFault that is not blank and a fixKind that is a string or absent
///     and is not empty exactly when the category is DiagnosisPayload FIXCATEGORY); the folder is blank; the snapshot is not of the format
///     SNAPSHOTFORMAT or holds no failure; the redactor cannot check the text; or the redacted snapshot or the case holds a character that is not
///     ASCII or a local machine path (LOCALPATH).
///   - Capture refuses a case that is not valid before it reads the production, and refuses when the reader's outcome is not read or its answer holds
///     no failure; then Write's refusals apply. A value is refused, never stripped: the author fixes the case.
Class OcuTalon.Eval.Record
{

/// What case.json names as the recorder.
Parameter RECORDEDBY = "OcuTalon.Eval.Record (Story 9.4)";

/// The file of the reader's answer, in the case's folder.
Parameter SNAPSHOTFILE = "snapshot.json";

/// The file of the case, in the case's folder.
Parameter CASEFILE = "case.json";

/// A case name: lower-case kebab, as a regular expression for $Locate.
Parameter NAMEPATTERN = "^[a-z0-9]+(-[a-z0-9]+)*\z";

/// A character that is not ASCII, as a regular expression for $Locate.
Parameter NONASCII = "[^\x00-\x7F]";

/// A local machine path, as a regular expression for $Locate: the patterns of the local_path scan of docker/tests/test-boundaries.sh (a name below a
/// home or volume folder, a temporary folder of the machine, a Windows user folder, whose backslash may be doubled as in JSON). The home folder of
/// the image's own user is allowed.
Parameter LOCALPATH = "/Use[r]s/[A-Za-z0-9]|/Volume[s]/[A-Za-z0-9]|/privat[e]/(tmp|var|etc)/|(?<![A-Za-z0-9_.])/va[r]/folders/[A-Za-z0-9_]|[A-Za-z]:\\\\?Use[r]s\\\\?[A-Za-z0-9]|/hom[e]/(?!irisowner)[A-Za-z]";

/// The refusal texts. NOTHING is followed by the reader's outcome, or by NOFAILURE.
Parameter NOTHING = "nothing to record: ";

Parameter NOFAILURE = "no failure";

Parameter NOTASCII = "a character that is not ASCII";

Parameter NOTLOCAL = "a local machine path";

/// Reads the failures with the keys (comma-separated, h<header id> or l<log id>) of the production's item in the namespace through
/// Reader.Evidence, writes them into the folder as Write does, and gives in pack the evidence pack of the reader's answer (EvidencePack.Build, before
/// any redaction of the file). The reader's outcome must be read and its answer must hold a failure. On any error pack is "", and when it refuses (the
/// refusals of the class description) nothing is written.
ClassMethod Capture(case As %DynamicObject, namespace As %String, production As %String, item As %String, keys As %String, folder As %String, Output pack As %DynamicObject) As %Status
{
	Set pack = ""
	Set sc = $$$OK
	Try {
		Do ..CaseRecord(case)
		Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(namespace, production, item, keys, .snapshot)
		If outcome '= "read" $$$ThrowStatus(..Refusal(..#NOTHING_outcome))
		If snapshot.failures.%Size() = 0 $$$ThrowStatus(..Refusal(..#NOTHING_..#NOFAILURE))
		$$$ThrowOnError(##class(OcuTalon.Watch.EvidencePack).Build(snapshot, .built))
		$$$ThrowOnError(..Write(case, snapshot, folder))
		Set pack = built
	} Catch exception {
		Set pack = ""
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Writes snapshot.json (the snapshot after Redact.Text) and case.json into <folder>/<case name>/, after the checks of the class description. When any
/// check fails the status names the reason and no folder or file is made.
ClassMethod Write(case As %DynamicObject, snapshot As %DynamicObject, folder As %String) As %Status
{
	Set sc = $$$OK
	Try {
		Set record = ..CaseRecord(case)
		If $ZStrip($Get(folder), "*WC") = "" $$$ThrowStatus(..Refusal("the folder is blank"))
		If '$IsObject(snapshot) || ('snapshot.%IsA("%Library.DynamicObject")) || (snapshot.format '= ##class(OcuTalon.Watch.EvidencePack).#SNAPSHOTFORMAT) {
			$$$ThrowStatus(..Refusal("the snapshot is not of the format "_##class(OcuTalon.Watch.EvidencePack).#SNAPSHOTFORMAT))
		}
		If (snapshot.%GetTypeOf("failures") '= "array") || (snapshot.failures.%Size() = 0) $$$ThrowStatus(..Refusal("the snapshot holds no failure"))
		Set snapshotText = ##class(OcuTalon.Bridge.Redact).Text(snapshot.%ToJSON())
		If snapshotText = ##class(OcuTalon.Bridge.Redact).#UNCHECKED $$$ThrowStatus(..Refusal("the snapshot could not be checked by the redactor"))
		Set caseText = record.%ToJSON()
		For label = "snapshot", "case" {
			Set text = $Select(label = "snapshot": snapshotText, 1: caseText)
			If $Locate(text, ..#NONASCII) $$$ThrowStatus(..Refusal("the "_label_" holds "_..#NOTASCII))
			If $Locate(text, ..#LOCALPATH) $$$ThrowStatus(..Refusal("the "_label_" holds "_..#NOTLOCAL))
		}
		Set directory = ##class(%File).SubDirectoryName(##class(%File).NormalizeDirectory(folder), record.name)
		If '##class(%File).CreateDirectoryChain(directory) $$$ThrowStatus($$$ERROR($$$GeneralError, "The folder "_directory_" could not be made"))
		Do ..WriteFile(##class(%File).NormalizeFilename(..#SNAPSHOTFILE, directory), snapshotText)
		Do ..WriteFile(##class(%File).NormalizeFilename(..#CASEFILE, directory), caseText)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The case.json record of the case, or an error (thrown) that names the field that is not valid.
ClassMethod CaseRecord(case As %DynamicObject) As %DynamicObject [ Private ]
{
	If '$IsObject(case) || ('case.%IsA("%Library.DynamicObject")) $$$ThrowStatus(..Refusal("the case is not a JSON object"))
	Set name = ..Text(case, "name")
	If '$Locate(name, ..#NAMEPATTERN) $$$ThrowStatus(..Refusal("the case's name '"_name_"' is not lower-case kebab"))
	If '$ListFind($ListBuild("boolean", "unassigned"), case.%GetTypeOf("heldOut")) $$$ThrowStatus(..Refusal("the case's heldOut is not a boolean"))
	If ..Blank(..Text(case, "description")) $$$ThrowStatus(..Refusal("the case's description is blank"))
	If case.%GetTypeOf("expectation") '= "object" $$$ThrowStatus(..Refusal("the case's expectation is not an object"))
	Set expectation = case.expectation
	Set category = ..Text(expectation, "causeCategory")
	Set categories = ##class(OcuTalon.Watch.Msg.DiagnosisPayload).#CAUSECATEGORIES
	If '$ListFind($ListFromString(categories), category) $$$ThrowStatus(..Refusal("the expectation's causeCategory '"_category_"' is not one of "_categories))
	If ..Blank(..Text(expectation, "elementAtFault")) $$$ThrowStatus(..Refusal("the expectation's elementAtFault is blank"))
	If '$ListFind($ListBuild("string", "unassigned"), expectation.%GetTypeOf("fixKind")) $$$ThrowStatus(..Refusal("the expectation's fixKind is not a string"))
	Set fixKind = ..Text(expectation, "fixKind")
	Set fixCategory = ##class(OcuTalon.Watch.Msg.DiagnosisPayload).#FIXCATEGORY
	If (category = fixCategory) && (fixKind = "") $$$ThrowStatus(..Refusal("the expectation's fixKind is empty for the category "_category))
	If (category '= fixCategory) && (fixKind '= "") $$$ThrowStatus(..Refusal("the expectation's fixKind '"_fixKind_"' is set for the category "_category_", which has no fix"))
	Set record = {"name": (name), "kind": (##class(OcuTalon.Eval.Report).#INCIDENTKIND)}
	Do record.%Set("heldOut", +case.%Get("heldOut"), "boolean")
	Set record.description = case.description
	Set record.snapshot = ..#SNAPSHOTFILE
	Set record.expectation = {"causeCategory": (category), "elementAtFault": (expectation.elementAtFault), "fixKind": (fixKind)}
	Set record.recordedBy = ..#RECORDEDBY
	Quit record
}

/// The member of the object when it is a string, else "".
ClassMethod Text(object As %DynamicObject, key As %String) As %String [ Private ]
{
	Quit $Select(object.%GetTypeOf(key) = "string": object.%Get(key), 1: "")
}

/// 1 when the text is empty once white space and control characters are removed.
ClassMethod Blank(text As %String) As %Boolean [ Private ]
{
	Quit $ZStrip($Get(text), "*WC") = ""
}

/// The error status of a refusal.
ClassMethod Refusal(reason As %String) As %Status [ Private ]
{
	Quit $$$ERROR($$$GeneralError, "OcuTalon.Eval.Record refuses: "_reason)
}

/// Replaces the file with the text and one line feed.
ClassMethod WriteFile(file As %String, text As %String) [ Private ]
{
	If ##class(%File).Exists(file) && '##class(%File).Delete(file) $$$ThrowStatus($$$ERROR($$$GeneralError, "The file "_file_" could not be replaced"))
	Set stream = ##class(%Stream.FileCharacter).%New()
	$$$ThrowOnError(stream.LinkToFile(file))
	$$$ThrowOnError(stream.Write(text_$Char(10)))
	$$$ThrowOnError(stream.%Save())
}

}
