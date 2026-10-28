/// EvalIn, the adapterless service that sends the recorded item cases of eval/ through the product's own path (AD-22, AD-30). Lane A.
/// The product keeps it disabled; the Production install step enables it only when OCUTALON_EVAL is 1, and Start reaches it only through
/// Ens.Director.CreateBusinessService, so a disabled EvalIn sends nothing. It uses neither EnsLib.Testing.Service nor the production's
/// testing switch, and it sends only to Intake.
///   - Start is the run entry: it creates the service, mints the run's Ref and sends each named case, or each case folder under the
///     folder, once. It returns the run's Ref, how many cases were sent, and the cases that were not, each with its reason.
///   - A case is a folder with a case.json (the shape of the eval/ cases): name, kind, heldOut, description, expectation and
///     recordedBy, and for a kind of item or injection an item {itemId, channel, provenance, sender, subject, text, catalogKey, slots}.
///     A case that is not sent is logged as a warning and goes into the skipped list with its reason: a kind that holds no recorded
///     Item (an incident, a turn kind), no case.json or one that is not a JSON object, no item.itemId, or a recorded provenance
///     other than untrusted. The other cases still run.
///   - A sent case is an OcuTalon.Msg.Item with a fresh ItemId (OcuTalon.Bridge.Ids.NewRef), SourceItemId set to the recorded
///     item.itemId, owner eval (OcuTalon.Data.Ownership EVAL), provenance untrusted, and the channel, sender, subject, text, catalog key
///     and slots of the record. Before the send EvalIn opens the case's OcuTalon.Eval.Data.CaseResult row, which EvalSink completes;
///     a send that fails deletes the row and skips the case with the error text.
///   - The trace: each case is its own trace session, and every message of the run carries the run's Ref as its SuperSession (AD-26).
/// Wait polls the rows of a run until none is still sent, or the seconds have passed.
Class OcuTalon.Eval.In Extends Ens.BusinessService
{

/// The folder of the recorded cases in a throwaway stack: the repository's eval/ mounted read-only.
Parameter FOLDER = "/opt/ocutalon/eval/";

/// The item that takes every Item.
Parameter TARGET = "Intake";

/// The kinds of case that hold a recorded Item, comma-separated.
Parameter KINDS = "item,injection";

/// The name of the file that holds a case.
Parameter CASEFILE = "case.json";

Parameter REASONINPUT = "EvalIn takes the folder of a case from Start and nothing else.";

Parameter REASONNOCASEFILE = "the folder has no case.json";

Parameter REASONNOTJSON = "case.json is not a JSON object";

Parameter REASONKIND = "its kind is '{kind}', and only the kinds {kinds} hold a recorded Item";

Parameter REASONNOITEMID = "it has no item.itemId";

Parameter REASONPROVENANCE = "its recorded provenance is '{provenance}', not untrusted";

/// The start of the warning for a case that is not sent; the case's name and its reason follow it.
Parameter LOGSKIPPED = "EvalIn did not send the case ";

/// The Ref of the run that this service instance sends; Start sets it.
Property RunRef As %String(MAXLEN = 22);

/// Starts a run: creates EvalIn, mints the run's Ref and sends each case once.
///   - folder holds the case folders. names is a comma-separated list of case folder names; "" means every subfolder that holds a
///     case.json, in name order.
///   - runRef is the run's Ref, 22 characters, "" when the run did not start. sent is the number of cases sent. skipped is a dynamic
///     array of {"case", "reason"} for each case that was not sent.
///   - The status is the director's error when EvalIn cannot be created, which a disabled EvalIn is (the text says disabled); then
///     nothing was sent and there is no run Ref. Otherwise OK.
ClassMethod Start(folder As %String = {..#FOLDER}, names As %String = "", Output runRef As %String, Output sent As %Integer, Output skipped As %DynamicArray) As %Status
{
	Set runRef = "", sent = 0, skipped = []
	Set sc = ##class(Ens.Director).CreateBusinessService("EvalIn", .service)
	If $$$ISERR(sc) Quit sc
	If '$IsObject(service) || 'service.%IsA("OcuTalon.Eval.In") Quit $SYSTEM.Status.Error(5001, "The item EvalIn is not an OcuTalon.Eval.In")
	Set folder = ##class(%File).NormalizeDirectory(folder)
	Set list = ..CaseNames(folder, names)
	Set service.RunRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set runRef = service.RunRef
	Set position = 0
	While $ListNext(list, position, name) {
		Set input = ##class(Ens.StringContainer).%New(##class(%File).SubDirectoryName(folder, name))
		Kill output
		Set sc = service.ProcessInput(input, .output)
		Set reason = $Select($$$ISERR(sc): $SYSTEM.Status.GetOneStatusText(sc), $IsObject($Get(output)): output.StringValue, 1: "")
		If reason = "" {
			Set sent = sent + 1
		} Else {
			Do skipped.%Push({"case": (name), "reason": (reason)})
		}
	}
	Quit $SYSTEM.Status.OK()
}

/// Waits, polling every 0.25 seconds and for at most the seconds, until none of the run's rows is still sent. Returns how many are.
ClassMethod Wait(runRef As %String, seconds As %Integer) As %Integer
{
	Set end = $ZHorolog + seconds
	For {
		Set open = ##class(OcuTalon.Eval.Data.CaseResult).Unanswered(runRef)
		If (open = 0) || ($ZHorolog '< end) Quit
		Hang 0.25
	}
	Quit open
}

/// The case folder names to send, as a list: the names given, each once, in the order given, or, with no names, every subfolder of the
/// folder that holds a case.json, in name order.
ClassMethod CaseNames(folder As %String, names As %String) As %List
{
	Set list = ""
	If $ZStrip(names, "*W") '= "" {
		For i = 1:1:$Length(names, ",") {
			Set name = $ZStrip($Piece(names, ",", i), "<>W")
			If (name '= "") && '$ListFind(list, name) Set list = list_$ListBuild(name)
		}
		Quit list
	}
	Set rows = ##class(%ResultSet).%New("%File:FileSet")
	If $$$ISERR(rows.Execute(folder, "*", "Name", 1)) Quit ""
	While rows.Next() {
		If rows.Get("Type") '= "D" Continue
		Set name = rows.Get("ItemName")
		If ##class(%File).Exists(##class(%File).NormalizeFilename(..#CASEFILE, ##class(%File).SubDirectoryName(folder, name))) Set list = list_$ListBuild(name)
	}
	Quit list
}

/// Sends the case in the folder; pOutput is an Ens.StringContainer whose StringValue is "" when the case was sent, and otherwise the
/// reason it was not.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ##class(Ens.StringContainer).%New("")
	If '$IsObject($Get(pInput)) || 'pInput.%IsA("Ens.StringContainer") || (..RunRef = "") {
		Set pOutput.StringValue = ..#REASONINPUT
		Quit $$$OK
	}
	Set folder = pInput.StringValue
	Set name = ##class(%File).GetFilename($ZStrip(folder, ">", "/"))
	Set reason = ""
	Try {
		Set reason = ..Send(folder, name)
	} Catch exception {
		Set reason = exception.DisplayString()
	}
	If reason '= "" $$$LOGWARNING(..#LOGSKIPPED_name_": "_reason)
	Set pOutput.StringValue = reason
	Quit $$$OK
}

/// The steps for one case; the reason it was not sent, or "" when it was.
Method Send(folder As %String, name As %String) As %String [ Private ]
{
	Set file = ##class(%File).NormalizeFilename(..#CASEFILE, folder)
	If '##class(%File).Exists(file) Quit ..#REASONNOCASEFILE
	Set case = ""
	Try {
		Set case = ##class(%DynamicAbstractObject).%FromJSONFile(file)
	} Catch exception {
		Set case = ""
	}
	If '$IsObject(case) || 'case.%IsA("%Library.DynamicObject") Quit ..#REASONNOTJSON
	Set kind = ..Scalar(case, "kind")
	If '$ListFind($ListFromString(..#KINDS), kind) Quit $Replace($Replace(..#REASONKIND, "{kind}", $Extract(kind, 1, 40)), "{kinds}", $Replace(..#KINDS, ",", " and "))
	Set record = case.item
	If '$IsObject(record) || 'record.%IsA("%Library.DynamicObject") || (..Scalar(record, "itemId") = "") Quit ..#REASONNOITEMID
	Set provenance = ..Scalar(record, "provenance")
	If (provenance '= "") && (provenance '= "untrusted") Quit $Replace(..#REASONPROVENANCE, "{provenance}", $Extract(provenance, 1, 40))
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SourceItemId = ..Scalar(record, "itemId")
	Set item.SessionRef = ##class(OcuTalon.Data.Ownership).#EVAL
	Set item.Channel = ..Scalar(record, "channel")
	Set item.Provenance = "untrusted"
	Set item.Sender = ..Scalar(record, "sender")
	Set item.Subject = ..Scalar(record, "subject")
	Set item.Text = ..Scalar(record, "text")
	Set item.CatalogKey = ..Scalar(record, "catalogKey")
	Set item.Slots = $Select($IsObject(record.slots): record.slots.%ToJSON(), 1: ..Scalar(record, "slots"))
	Set sc = ##class(OcuTalon.Eval.Data.CaseResult).Open(..RunRef, name, item.SourceItemId, item.ItemId)
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetOneStatusText(sc)
	Set ..%SuperSession = ..RunRef
	Try {
		Set sc = ..Dispatch(item)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		Do ##class(OcuTalon.Eval.Data.CaseResult).Remove(..RunRef, name)
		Quit $SYSTEM.Status.GetOneStatusText(sc)
	}
	Quit ""
}

/// The one send of the class: the Item to the target item, asynchronously, with no answer. Private; a test subclass overrides it.
Method Dispatch(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#TARGET, item)
}

/// The text of a string, number or boolean member of a JSON object; "" for a member that is missing, null, an object or an array. EvalSink
/// reads a Decision payload with it too.
ClassMethod Scalar(object As %DynamicObject, key As %String) As %String
{
	Set type = object.%GetTypeOf(key)
	Quit $Select((type = "string") || (type = "number") || (type = "boolean"): object.%Get(key), 1: "")
}

}
