/// Tests of the incident recorder OcuTalon.Eval.Record against a real failure (Story 9.4; AD-22, AD-15). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI
/// ONLY (Rule 21): it needs the Orders production in OCUORDERS, which a slot never has, and the repository's eval/ folder mounted at Eval.In FOLDER.
/// Where either is missing, every test fails with that reason, so that a broken stack can never give a green shard.
/// OnBeforeAllTests holds the Orders WatchMark, then re-induces each incident of RECIPES (the demo's: a batch of 50 orders in MM/DD/YYYY), builds the live
/// pack itself from Reader.Evidence and EvidencePack.Build, independently of Eval.Record, and captures the same failures with Eval.Record into a folder
/// of its own below TMP. OnAfterAllTests runs Clean: it deletes its messages and its folder and releases the mark. The tests then read what was kept:
///   - TestCaptureWritesCase: the demo capture's two files, field by field; snapshot.json is the reader's own answer after Redact.Text, with nothing
///     added and nothing dropped; case.json is the committed case except recordedBy; the committed expectation; Eval.Report DEMOCASE names the case;
///   - TestReplayEqualsLive: the pack that Build gives the file just written, and the pack that Capture returned, equal the live pack exactly;
///   - TestCommittedIsCurrent: the incident cases of eval/ and RECIPES are the same set, and the pack of each committed snapshot equals the live pack
///     once VOLATILE (row ids and times, which a re-induced incident cannot repeat) is removed from both;
///   - TestNoIncidentMade: the Orders WatchMark was held while the failures were sent, and the recordings made no Orders incident;
///   - TestCleanRemovesBatch: Clean removes the messages of a batch of one order, its folder and the hold;
///   - TestWriteRedacts, TestWriteRefuses and TestCaptureRefuses: the redaction and the refusals of the recorder on synthetic snapshots (no failure is
///     induced), each leaving no folder behind.
Class OcuTalon.Test.Eval.Record Extends %UnitTest.TestCase
{

/// The incident cases that this class re-induces, comma-separated: one recipe in Induce for each.
Parameter RECIPES = "orders-date-format";

/// The fields of an evidence pack that a re-induced incident cannot repeat (row ids and times), comma-separated. A dotted name is a field of an object
/// field, and a field of every entry of a list.
Parameter VOLATILE = "firstAt,lastAt,sample.headerId,sample.at,trace.headerId,trace.timeCreated";

/// The folder of this class's captures; each run uses a folder of its own below it.
Parameter TMP = "/tmp/zz-eval-record/";

/// The item of the Orders production that the demo failures are at.
Parameter ORDERSITEM = "OrdersFromPartner";

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 400);

/// 1 when OnBeforeAllTests held the Orders failures, so that OnAfterAllTests releases them.
Property Held As %Boolean;

/// 1 when the Orders WatchMark was ahead of now by more than 300 seconds right after OnBeforeAllTests held the failures, before the first order was sent.
Property HoldChecked As %Boolean;

/// The references that the batches of this run used.
Property Refs As %DynamicArray;

/// The run's folder below TMP.
Property Folder As %String(MAXLEN = 200);

/// The time when the recordings began (UTC, YYYY-MM-DDThh:mm:ssZ).
Property Start As %String;

/// By the name of each recipe: {error, live, captured, answer}, the text of Capture's error status ("" when it succeeded), the live pack, the pack that
/// Capture returned and the reader's answer that the live pack was built from.
Property Recorded As %DynamicObject;

Method OnBeforeAllTests() As %Status
{
	Set ..Refs = []
	Set ..Recorded = {}
	Set ..Missing = ""
	Set ..Held = 0
	Set ..HoldChecked = 0
	Set ..Start = ""
	Set ..Folder = ##class(%File).NormalizeDirectory(##class(%File).SubDirectoryName(..#TMP, ##class(OcuTalon.Bridge.Ids).NewRef()))
	Try {
		Set demo = "OcuTalon.Test.Demo.Production"
		If '##class(%File).DirectoryExists(##class(OcuTalon.Eval.In).#FOLDER) {
			Set ..Missing = "The repository's eval/ is not mounted at "_##class(OcuTalon.Eval.In).#FOLDER_": this class runs in throwaways and CI only (Rule 21)"
		} ElseIf '##class(%SYS.Namespace).Exists($Parameter(demo, "NAMESPACE")) {
			Set ..Missing = $Parameter(demo, "NAMESPACE")_" does not exist: this class runs in throwaways and CI only (Rule 21)"
		} ElseIf '$ClassMethod(demo, "Running") {
			Set ..Missing = "The Orders production does not run in "_$Parameter(demo, "NAMESPACE")
		}
		If ..Missing = "" {
			Do ##class(%File).RemoveDirectoryTree(..#TMP)
			Set sc = $ClassMethod(demo, "HoldFailures")
			If $$$ISERR(sc) {
				Set ..Missing = "The Orders failures could not be held: "_$SYSTEM.Status.GetErrorText(sc)
			} Else {
				Set ..Held = 1
				Set ..HoldChecked = $ClassMethod(demo, "MarkIsAhead", 300)
				Set ..Start = ##class(OcuTalon.Data.Time).NowUtc()
			}
		}
		Set recipes = $ListFromString(..#RECIPES), position = 0
		While (..Missing = "") && $ListNext(recipes, position, name) {
			Do ..Make(name)
		}
	} Catch exception {
		Set ..Missing = "The incidents could not be recorded: "_exception.DisplayString()
	}
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean(..Refs, ..Folder, ..Held)
	Quit $$$OK
}

/// Deletes the Orders messages of the batches (the SuperSession references in the array), releases the Orders WatchMark when held is 1, and deletes
/// the folder with everything in it.
ClassMethod Clean(refs As %DynamicArray, folder As %String, held As %Boolean)
{
	Set demo = "OcuTalon.Test.Demo.Production"
	If $IsObject(refs) && (refs.%Size() > 0) Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(refs, $Parameter(demo, "NAMESPACE"))
	If held Do $ClassMethod(demo, "ReleaseFailures")
	If folder '= "" Do ##class(%File).RemoveDirectoryTree(folder)
}

/// Induces the incident, builds the live pack and captures the same failures with Eval.Record; keeps the three in Recorded. A fault ends the
/// recordings, with the reason in Missing.
Method Make(name As %String) [ Private ]
{
	Set sc = ..Induce(name, .namespace, .production, .item, .keys)
	If $$$ISERR(sc) {
		Set ..Missing = "The incident "_name_" could not be induced: "_$SYSTEM.Status.GetErrorText(sc)
		Quit
	}
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(namespace, production, item, keys, .snapshot)
	If outcome '= "read" {
		Set ..Missing = "The reader's outcome for "_name_" is "_outcome_", not read"
		Quit
	}
	Set sc = ##class(OcuTalon.Watch.EvidencePack).Build(snapshot, .live)
	If $$$ISERR(sc) {
		Set ..Missing = "The live pack of "_name_" could not be built: "_$SYSTEM.Status.GetErrorText(sc)
		Quit
	}
	Set committed = ##class(OcuTalon.Test.Eval.Cases).Read(##class(%File).NormalizeDirectory(##class(OcuTalon.Eval.In).#FOLDER), name)
	If '$IsObject(committed) {
		Set ..Missing = "eval/"_name_"/case.json does not exist"
		Quit
	}
	Set case = {"name": (name), "description": (committed.description), "expectation": (committed.expectation)}
	Do case.%Set("heldOut", +committed.heldOut, "boolean")
	Set sc = ##class(OcuTalon.Eval.Record).Capture(case, namespace, production, item, keys, ..Folder, .captured)
	Do ..Recorded.%Set(name, {"error": ($Select($$$ISOK(sc): "", 1: $SYSTEM.Status.GetErrorText(sc))), "live": (live), "captured": ($Select($IsObject(captured): captured, 1: "")), "answer": (snapshot)})
}

/// Sends the failures of the incident into the Orders production and gives where and which they are: the namespace, production and item they are at and
/// the keys of their failed headers (h<id>, ascending). The batch's reference is kept in Refs. An unknown name is an error.
Method Induce(name As %String, Output namespace As %String, Output production As %String, Output item As %String, Output keys As %String) As %Status
{
	Set keys = ""
	If name '= "orders-date-format" Quit $$$ERROR($$$GeneralError, "No recipe induces the incident "_name)
	Set demo = "OcuTalon.Test.Demo.Production"
	Set namespace = $Parameter(demo, "NAMESPACE")
	Set production = $Parameter(demo, "PRODUCTION")
	Set item = ..#ORDERSITEM
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Refs.%Push(ref)
	Set text = $ClassMethod(demo, "Send", 50, "MM/DD/YYYY", ref, "2026-10-16")
	If text '= "" Quit $$$ERROR($$$GeneralError, "The batch was not sent: "_text)
	Set count = $ClassMethod(demo, "WaitCount", ref, item, 8, 50)
	If count '= 50 Quit $$$ERROR($$$GeneralError, "The batch has "_count_" failures at "_item_", not 50")
	Set headers = $ClassMethod(demo, "Headers", ref)
	For i = 0:1:headers.%Size() - 1 {
		Set header = headers.%Get(i)
		If (header.target = item) && (header.status = 8) Set keys = keys_$Select(keys = "": "", 1: ",")_"h"_header.id
	}
	If $Length(keys, ",") '= 50 Quit $$$ERROR($$$GeneralError, "The batch has "_$Length(keys, ",")_" failed headers at "_item_", not 50")
	Quit $$$OK
}

/// The files of the demo capture, field by field: the snapshot is the reader's answer (the source, 50 failures at OrdersFromPartner with the changed
/// date and the transform's error, event-log rows, the item with no credential setting, and a trace), case.json is the committed case except recordedBy,
/// the committed expectation is the demo's, and Eval.Report DEMOCASE names the case.
Method TestCaptureWritesCase()
{
	If '..Guard() Quit
	Set name = "orders-date-format"
	Set entry = ..Entry(name)
	If '$IsObject(entry) Quit
	Do $$$AssertEquals(entry.error, "", name_": Capture succeeded")
	Set directory = ##class(%File).SubDirectoryName(..Folder, name)
	Set snapshotFile = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.Record).#SNAPSHOTFILE, directory)
	Set caseFile = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.Record).#CASEFILE, directory)
	Do $$$AssertTrue(##class(%File).Exists(snapshotFile) && ##class(%File).Exists(caseFile), name_": snapshot.json and case.json were written")
	Do $$$AssertStatusOK(##class(OcuTalon.Watch.EvidencePack).Load(snapshotFile, .snapshot), "the snapshot is a reader snapshot")
	If '$IsObject(snapshot) Quit
	Set demo = "OcuTalon.Test.Demo.Production"
	Do $$$AssertEquals(snapshot.source.%ToJSON(), {"namespace": ($Parameter(demo, "NAMESPACE")), "production": ($Parameter(demo, "PRODUCTION")), "item": (..#ORDERSITEM)}.%ToJSON(), "the source is the Orders production's item")
	Do $$$AssertEquals(snapshot.failures.%Size(), 50, "the snapshot holds the 50 failures, not fewer")
	Set wrong = ""
	For i = 0:1:snapshot.failures.%Size() - 1 {
		Set failure = snapshot.failures.%Get(i)
		If (failure.targetConfigName '= ..#ORDERSITEM) || (failure.status '= "Error") || (failure.body.OrderDate '? 2N1"/"2N1"/"4N) || (failure.error '[ "not in the expected format") Set wrong = wrong_" "_i
	}
	Do $$$AssertEquals(wrong, "", "every failure is at "_..#ORDERSITEM_" with the order date as MM/DD/YYYY and the transform's error")
	Do $$$AssertTrue(snapshot.eventLog.%Size() > 0, "the snapshot holds event-log rows: "_snapshot.eventLog.%Size())
	Do $$$AssertEquals(snapshot.items.%Size(), 1, "the snapshot holds the one item")
	If snapshot.items.%Size() = 1 {
		Set item = snapshot.items.%Get(0)
		Do $$$AssertEquals(item.name, ..#ORDERSITEM, "and it is "_..#ORDERSITEM)
		Set flagged = ""
		Set iterator = item.settings.%GetIterator()
		While iterator.%GetNext(.setting) {
			If ##class(OcuTalon.Watch.Reader).CredentialName(setting) Set flagged = flagged_" "_setting
		}
		Do $$$AssertEquals(flagged, "", "with no credential-type setting")
	}
	Do $$$AssertTrue(snapshot.trace.%Size() > 0, "the snapshot holds a trace: "_snapshot.trace.%Size())
	Set text = ..ReadText(snapshotFile)
	Do $$$AssertTrue(($Length(text, $Char(10)) = 2) && ($Extract(text, *) = $Char(10)), "snapshot.json is one line of compact JSON and a line feed")
	Do $$$AssertTrue(text = (##class(OcuTalon.Bridge.Redact).Text(entry.answer.%ToJSON())_$Char(10)), "snapshot.json is the reader's own answer after Redact.Text, with nothing added and nothing dropped")
	Set written = ##class(%DynamicAbstractObject).%FromJSONFile(caseFile)
	Set committed = ##class(OcuTalon.Test.Eval.Cases).Read(##class(%File).NormalizeDirectory(##class(OcuTalon.Eval.In).#FOLDER), name)
	Do $$$AssertEquals(written.recordedBy, ##class(OcuTalon.Eval.Record).#RECORDEDBY, "case.json names the recorder")
	Do written.%Remove("recordedBy")
	Do committed.%Remove("recordedBy")
	Do $$$AssertEquals(written.%ToJSON(), committed.%ToJSON(), "case.json is the committed case except recordedBy")
	Do $$$AssertEquals(committed.expectation.%ToJSON(), {"causeCategory": "data_format_change", "elementAtFault": "OrderDate", "fixKind": "repair_resend"}.%ToJSON(), "the committed expectation is a data-format change at OrderDate, fixed by repair and resend")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Report).#DEMOCASE, name, "Eval.Report DEMOCASE names the demo incident")
	Do $$$AssertTrue(##class(OcuTalon.Test.Eval.Cases).Plain(snapshotFile) && ##class(OcuTalon.Test.Eval.Cases).Plain(caseFile), "both files are plain ASCII")
}

/// The pack that Build gives the file just written, and the pack that Capture returned, equal the live pack exactly (no field is masked), for each
/// recipe. The live pack is not empty.
Method TestReplayEqualsLive()
{
	If '..Guard() Quit
	Set recipes = $ListFromString(..#RECIPES), position = 0
	While $ListNext(recipes, position, name) {
		Set entry = ..Entry(name)
		If '$IsObject(entry) Continue
		Do $$$AssertEquals(entry.error, "", name_": Capture succeeded")
		Set live = entry.live
		Do $$$AssertTrue(live.count > 0, name_": the live pack counts failures: "_live.count)
		Do $$$AssertTrue($IsObject(live.sample) && ($IsObject(live.settings)) && (live.trace.%Size() > 0), name_": the live pack holds a sample, settings and a trace")
		If name = "orders-date-format" Do $$$AssertEquals(live.count_"|"_live.sample.body.OrderDate_"|"_live.item, "50|10/16/2026|"_..#ORDERSITEM, name_": the live pack is the 50 failures of the changed date")
		Set file = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.Record).#SNAPSHOTFILE, ##class(%File).SubDirectoryName(..Folder, name))
		Do $$$AssertStatusOK(##class(OcuTalon.Watch.EvidencePack).Load(file, .snapshot), name_": the file is a reader snapshot")
		If '$IsObject(snapshot) Continue
		Do $$$AssertStatusOK(##class(OcuTalon.Watch.EvidencePack).Build(snapshot, .replay), name_": Build reads the file")
		If $IsObject(replay) Do ..AssertSamePack(name_": the pack of the written file equals the live pack", replay, live)
		If $IsObject(entry.captured) Do ..AssertSamePack(name_": the pack that Capture returned equals the live pack", entry.captured, live)
		Do $$$AssertTrue($IsObject(entry.captured), name_": Capture returned a pack")
	}
}

/// The incident cases of eval/ and RECIPES are the same set, in both directions, so a case with no recipe fails; and for each recipe the pack that Build
/// gives the committed snapshot equals the live pack once VOLATILE is removed from both.
Method TestCommittedIsCurrent()
{
	If '..Guard() Quit
	Set folder = ##class(%File).NormalizeDirectory(##class(OcuTalon.Eval.In).#FOLDER)
	Set recipes = $ListFromString(..#RECIPES), cases = ""
	Set names = ##class(OcuTalon.Eval.In).CaseNames(folder, ""), position = 0
	While $ListNext(names, position, name) {
		Set case = ##class(OcuTalon.Test.Eval.Cases).Read(folder, name)
		If $IsObject(case) && (case.kind = ##class(OcuTalon.Eval.Report).#INCIDENTKIND) Set cases = cases_$ListBuild(name)
	}
	Set position = 0
	While $ListNext(cases, position, name) {
		Do $$$AssertTrue($ListFind(recipes, name), name_": the incident case has a recipe in RECIPES")
	}
	Set position = 0
	While $ListNext(recipes, position, name) {
		Do $$$AssertTrue($ListFind(cases, name), name_": the recipe has an incident case in eval/")
		Set entry = ..Entry(name)
		Set file = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.Record).#SNAPSHOTFILE, ##class(%File).SubDirectoryName(folder, name))
		Do $$$AssertTrue(##class(%File).Exists(file), name_": the committed snapshot exists")
		If '$IsObject(entry) || '##class(%File).Exists(file) Continue
		Do $$$AssertStatusOK(##class(OcuTalon.Watch.EvidencePack).Load(file, .snapshot), name_": the committed snapshot is a reader snapshot")
		If '$IsObject(snapshot) Continue
		Do $$$AssertStatusOK(##class(OcuTalon.Watch.EvidencePack).Build(snapshot, .committed), name_": Build reads the committed snapshot")
		If '$IsObject(committed) Continue
		Set stable = ..Stable(committed)
		Do $$$AssertTrue($IsObject(stable.sample) && (stable.count > 0) && (stable.item '= "") && (stable.errorPattern '= ""), name_": what VOLATILE leaves of the committed pack is not empty")
		Do ..AssertSamePack(name_": the committed snapshot's pack equals the live pack apart from VOLATILE", stable, ..Stable(entry.live))
	}
}

/// Re-inducing the incidents made no Orders incident: the Orders WatchMark was held ahead before the first order was sent (HoldChecked), FailurePoller
/// polled while the failures were held, and no incident of Orders began since the recordings did.
Method TestNoIncidentMade()
{
	If '..Guard() Quit
	Set demo = "OcuTalon.Test.Demo.Production"
	Do $$$AssertTrue(..HoldChecked, "the Orders WatchMark was held ahead before the first order was sent")
	Do $$$AssertTrue($ClassMethod(demo, "AwaitPolls", 1) >= 1, "FailurePoller polled while the recordings were held")
	Do $$$AssertEquals($ClassMethod(demo, "IncidentsSince", ..Start), 0, "no Orders incident was made by the recordings")
}

/// Clean, which OnAfterAllTests runs, deletes the Orders messages of a batch, its folder and the hold: a batch of one order of the test's own fails at
/// the item, a folder of the run is made, and after Clean(refs, folder, 1) the batch has no header, the folder is gone and the mark is at the release
/// time. The test then holds the failures again for the tests after it. Its reference is also kept in Refs, so that OnAfterAllTests deletes the batch
/// should the test fail halfway.
Method TestCleanRemovesBatch()
{
	If '..Guard() Quit
	Set demo = "OcuTalon.Test.Demo.Production"
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Refs.%Push(ref)
	Set sent = $ClassMethod(demo, "Send", 1, "MM/DD/YYYY", ref, "2026-10-16")
	Do $$$AssertEquals(sent, "", "a batch of one order is sent")
	Do $$$AssertEquals($ClassMethod(demo, "WaitCount", ref, ..#ORDERSITEM, 8, 1), 1, "and it fails at "_..#ORDERSITEM)
	Set folder = ..Folder_"clean/"
	Do $$$AssertTrue(##class(%File).CreateDirectoryChain(folder), "a folder of the run exists")
	Do $$$AssertTrue($ClassMethod(demo, "Headers", ref).%Size() > 0, "and the batch has headers")
	Do ..Clean([(ref)], folder, 1)
	Do $$$AssertEquals($ClassMethod(demo, "Headers", ref).%Size(), 0, "Clean deleted the headers of the batch")
	Do $$$AssertNotTrue(##class(%File).DirectoryExists(folder), "and the folder")
	Do $$$AssertTrue('$ClassMethod(demo, "MarkIsAhead", 60), "and released the Orders WatchMark")
	Do $$$AssertTrue($ClassMethod(demo, "MarkIsAhead", -30), "to the release time, not left behind")
	Do $$$AssertStatusOK($ClassMethod(demo, "HoldFailures"), "the failures are held again for the other tests")
}

/// A snapshot whose body holds a password and whose error holds a token is written with [redacted] in their place and neither secret; the written
/// file ends in a line feed; the snapshot the caller holds is unchanged; and the pack of the written file equals the pack of the raw snapshot.
Method TestWriteRedacts()
{
	If '..Guard() Quit
	Set raw = ..Synthetic({"OrderNumber": "PO-1", "Password": "zz-secret-1"}, "ERROR #5001: The call failed. token=zzsecret0123456789")
	Set before = raw.%ToJSON()
	Set folder = ..Folder_"redacts/"
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Record).Write(..SyntheticCase("zz-redacts"), raw, folder), "Write accepts the snapshot")
	Set file = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.Record).#SNAPSHOTFILE, ##class(%File).SubDirectoryName(folder, "zz-redacts"))
	Set text = ..ReadText(file)
	Do $$$AssertTrue(text [ ##class(OcuTalon.Bridge.Redact).#REDACTED, "the file holds [redacted]")
	Do $$$AssertTrue(text '[ "zz-secret-1", "the file does not hold the password")
	Do $$$AssertTrue(text '[ "zzsecret0123456789", "the file does not hold the token")
	Do $$$AssertTrue(($Length(text, $Char(10)) = 2) && ($Extract(text, *) = $Char(10)), "the file is one line and a line feed")
	Do $$$AssertEquals(raw.%ToJSON(), before, "the snapshot of the caller is unchanged")
	Do $$$AssertStatusOK(##class(OcuTalon.Watch.EvidencePack).Load(file, .snapshot), "the file is a reader snapshot")
	Do $$$AssertStatusOK(##class(OcuTalon.Watch.EvidencePack).Build(raw, .rawPack), "Build reads the raw snapshot")
	If '$IsObject(snapshot) || '$IsObject(rawPack) Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Watch.EvidencePack).Build(snapshot, .replay), "Build reads the written file")
	If '$IsObject(replay) Quit
	Do $$$AssertEquals(replay.sample.body.Password, ##class(OcuTalon.Bridge.Redact).#REDACTED, "the pack holds the password as [redacted]")
	Do ..AssertSamePack("the pack of the written file equals the pack of the raw snapshot", replay, rawPack)
}

/// Each snapshot or case that may not be written is refused with its reason, and nothing is written: a local machine path, a character that is not ASCII,
/// a case that is not valid, a snapshot that is not a reader snapshot or holds no failure, and a snapshot that the redactor cannot check (nested deeper
/// than Redact MAXDEPTH). The home folder of the image's own user is allowed.
Method TestWriteRefuses()
{
	If '..Guard() Quit
	Set base = ..Folder_"refuses/"
	Set notLocal = ##class(OcuTalon.Eval.Record).#NOTLOCAL, notAscii = ##class(OcuTalon.Eval.Record).#NOTASCII
	Set valid = ..SyntheticCase("zz-refused")
	For path = "/Use"_"rs/zzname/x", "/hom"_"e/zzname/x", "C:\Use"_"rs\zzname", "/Volume"_"s/Zz/x", "/privat"_"e/tmp/x", "/va"_"r/folders/zz/x" {
		Do ..AssertRefused("a body holding "_path, valid, ..Synthetic({"OrderNumber": (path)}), base, notLocal)
		Do ..AssertRefused("an error holding "_path, valid, ..Synthetic(, "ERROR #5001: Cannot open "_path), base, notLocal)
	}
	Do ..AssertRefused("a body holding a character that is not ASCII", valid, ..Synthetic({"OrderNumber": ("caf"_$Char(233))}), base, notAscii)
	Set case = ..SyntheticCase("zz-refused")
	Set case.description = "caf"_$Char(233)
	Do ..AssertRefused("a description holding a character that is not ASCII", case, ..Synthetic(), base, notAscii)
	For name = "Bad_Name", "BadName", "-x", "x-", "a--b", "" {
		Do ..AssertRefused("the name '"_name_"'", ..SyntheticCase(name), ..Synthetic(), base, "lower-case kebab")
	}
	Set case = ..SyntheticCase("zz-refused")
	Set case.expectation.causeCategory = "weather"
	Do ..AssertRefused("an unknown causeCategory", case, ..Synthetic(), base, "causeCategory")
	Set case = ..SyntheticCase("zz-refused")
	Set case.expectation.elementAtFault = "  "
	Do ..AssertRefused("a blank elementAtFault", case, ..Synthetic(), base, "elementAtFault")
	Set case = ..SyntheticCase("zz-refused")
	Set case.description = " "
	Do ..AssertRefused("a blank description", case, ..Synthetic(), base, "description")
	Set case = ..SyntheticCase("zz-refused")
	Do case.%Set("heldOut", "yes")
	Do ..AssertRefused("a heldOut that is not a boolean", case, ..Synthetic(), base, "heldOut")
	Set case = ..SyntheticCase("zz-refused")
	Set case.expectation.causeCategory = "connection_failure"
	Set case.expectation.fixKind = "repair_resend"
	Do ..AssertRefused("a fixKind for a category with no fix", case, ..Synthetic(), base, "has no fix")
	Set case = ..SyntheticCase("zz-refused")
	Set case.expectation.causeCategory = ##class(OcuTalon.Watch.Msg.DiagnosisPayload).#FIXCATEGORY
	Set case.expectation.fixKind = ""
	Do ..AssertRefused("no fixKind for a category with a fix", case, ..Synthetic(), base, "fixKind is empty")
	Do ..AssertRefused("a case that is not an object", [], ..Synthetic(), base, "not a JSON object")
	Set snapshot = ..Synthetic()
	Set snapshot.format = "other/1"
	Do ..AssertRefused("a snapshot of another format", valid, snapshot, base, "not of the format")
	Set snapshot = ..Synthetic()
	Set snapshot.failures = []
	Do ..AssertRefused("a snapshot with no failure", valid, snapshot, base, "holds no failure")
	Set deep = {"v": "x"}
	For i = 1:1:##class(OcuTalon.Bridge.Redact).#MAXDEPTH + 10 {
		Set deep = {"n": (deep)}
	}
	Do ..AssertRefused("a body that the redactor cannot check (nested deeper than "_##class(OcuTalon.Bridge.Redact).#MAXDEPTH_")", valid, ..Synthetic(deep), base, "could not be checked")
	Do $$$AssertNotTrue(##class(%File).DirectoryExists(base), "nothing was written: no folder was made for any refused case")
	Set allowed = ..Folder_"allowed/"
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Record).Write(valid, ..Synthetic({"OrderNumber": ("/hom"_"e/irisowner/x")}), allowed), "the home folder of the image's user is not refused")
	Do $$$AssertTrue(##class(%File).Exists(##class(%File).NormalizeFilename(##class(OcuTalon.Eval.Record).#SNAPSHOTFILE, ##class(%File).SubDirectoryName(allowed, "zz-refused"))), "and its snapshot was written")
}

/// Capture refuses a production that is not the namespace's own (not_current) and keys that give no failure, each with its reason, returns no pack and
/// writes nothing.
Method TestCaptureRefuses()
{
	If '..Guard() Quit
	Set base = ..Folder_"captures/"
	Set demo = "OcuTalon.Test.Demo.Production"
	Set namespace = $Parameter(demo, "NAMESPACE"), production = $Parameter(demo, "PRODUCTION")
	Set valid = ..SyntheticCase("zz-captured")
	Set nothing = ##class(OcuTalon.Eval.Record).#NOTHING
	Set sc = ##class(OcuTalon.Eval.Record).Capture(valid, namespace, "Zz.NoProduction", ..#ORDERSITEM, "h1", base, .pack)
	Do $$$AssertStatusNotOK(sc, "a production that is not the namespace's own is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ (nothing_"not_current"), "with the reader's outcome: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(pack, "", "and no pack is returned")
	Set sc = ##class(OcuTalon.Eval.Record).Capture(valid, namespace, production, ..#ORDERSITEM, "", base, .pack)
	Do $$$AssertStatusNotOK(sc, "keys that give no failure are refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ (nothing_##class(OcuTalon.Eval.Record).#NOFAILURE), "with the reason: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(pack, "", "and no pack is returned")
	Set case = ..SyntheticCase("Bad_Name")
	Set sc = ##class(OcuTalon.Eval.Record).Capture(case, namespace, production, ..#ORDERSITEM, "h1", base, .pack)
	Do $$$AssertStatusNotOK(sc, "a case that is not valid is refused")
	Do $$$AssertEquals(pack, "", "and no pack is returned")
	Do $$$AssertNotTrue(##class(%File).DirectoryExists(base), "nothing was written")
}

/// --- helpers ---
/// The recording of the recipe, or "" with a failed assertion.
Method Entry(name As %String) As %DynamicObject [ Private ]
{
	Set entry = ..Recorded.%Get(name)
	Do $$$AssertTrue($IsObject(entry), name_": the incident was recorded in OnBeforeAllTests")
	Quit $Select($IsObject(entry): entry, 1: "")
}

/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// Asserts that Write refuses the case and snapshot with a status whose text holds the reason.
Method AssertRefused(label As %String, case As %DynamicAbstractObject, snapshot As %DynamicObject, base As %String, reason As %String) [ Private ]
{
	Set sc = ##class(OcuTalon.Eval.Record).Write(case, snapshot, base)
	Do $$$AssertStatusNotOK(sc, label_": Write refuses")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ reason, label_": the reason holds '"_reason_"': "_$SYSTEM.Status.GetErrorText(sc))
}

/// Asserts that the two packs are the same JSON text, naming the fields that differ when they are not.
Method AssertSamePack(label As %String, left As %DynamicObject, right As %DynamicObject) [ Private ]
{
	Set same = (left.%ToJSON() = right.%ToJSON())
	Do $$$AssertTrue(same, label_$Select(same: "", 1: ": differs at"_..Differences(left, right, "")))
}

/// The fields at which the two dynamic objects or arrays differ, each preceded by a space: a path (a dot and a name or position for each level), with
/// "(type)" when the JSON types differ.
ClassMethod Differences(left As %DynamicAbstractObject, right As %DynamicAbstractObject, path As %String) As %String [ Private ]
{
	Set text = ""
	Set iterator = left.%GetIterator()
	While iterator.%GetNext(.key, .value, .type) {
		If type '= right.%GetTypeOf(key) {
			Set text = text_" "_path_"."_key_"(type)"
		} ElseIf $IsObject(value) {
			Set text = text_..Differences(value, right.%Get(key), path_"."_key)
		} ElseIf value '= right.%Get(key) {
			Set text = text_" "_path_"."_key
		}
	}
	Set iterator = right.%GetIterator()
	While iterator.%GetNext(.key) {
		If left.%GetTypeOf(key) = "unassigned" Set text = text_" "_path_"."_key_"(missing)"
	}
	Quit text
}

/// A copy of the pack without the fields of VOLATILE.
ClassMethod Stable(pack As %DynamicObject) As %DynamicObject [ Private ]
{
	Set copy = ##class(%DynamicAbstractObject).%FromJSON(pack.%ToJSON())
	Set paths = $ListFromString(..#VOLATILE), position = 0
	While $ListNext(paths, position, path) {
		Do ..Drop(copy, path)
	}
	Quit copy
}

/// Removes the field at the dotted path from the node; a list is searched entry by entry.
ClassMethod Drop(node As %DynamicAbstractObject, path As %String) [ Private ]
{
	If node.%IsA("%Library.DynamicArray") {
		Set iterator = node.%GetIterator()
		While iterator.%GetNext(, .value) {
			If $IsObject(value) Do ..Drop(value, path)
		}
		Quit
	}
	Set head = $Piece(path, ".", 1)
	Set rest = $Piece(path, ".", 2, *)
	If rest = "" {
		Do node.%Remove(head)
	} ElseIf $IsObject(node.%Get(head)) {
		Do ..Drop(node.%Get(head), rest)
	}
}

/// The text of the file.
ClassMethod ReadText(file As %String) As %String [ Private ]
{
	Set stream = ##class(%Stream.FileCharacter).%New()
	If $$$ISERR(stream.LinkToFile(file)) Quit ""
	Quit stream.Read(1000000)
}

/// A valid case for the name: not held out, a data-format change at OrderDate with repair and resend.
ClassMethod SyntheticCase(name As %String) As %DynamicObject [ Private ]
{
	Set case = {"name": (name), "description": "A synthetic case for the recorder's tests.", "expectation": {"causeCategory": "data_format_change", "elementAtFault": "OrderDate", "fixKind": "repair_resend"}}
	Do case.%Set("heldOut", 0, "boolean")
	Quit case
}

/// A reader snapshot of one failure at ZzItem with the given body and error.
ClassMethod Synthetic(body As %DynamicObject = "", error As %String = "ERROR #5001: The call failed.") As %DynamicObject [ Private ]
{
	If '$IsObject(body) Set body = {"OrderNumber": "PO-1"}
	Set failure = {"headerId": "7", "sessionId": 7, "superSession": "zzsuper", "timeCreated": "2026-10-28T10:00:00Z", "timeProcessed": "2026-10-28T10:00:01Z", "sourceConfigName": "ZzSource", "targetConfigName": "ZzItem", "bodyClass": "Zz.Body", "bodyId": "1", "status": "Error"}
	Do failure.%Set("isError", 0, "boolean")
	Set failure.error = error
	Set failure.body = body
	Quit {"format": "ocutalon.readerSnapshot/1", "source": {"namespace": "ZZNS", "production": "Zz.Production", "item": "ZzItem"}, "failures": [(failure)], "eventLog": [], "items": [{"name": "ZzItem", "className": "Zz.Operation", "enabled": 1, "poolSize": 1, "settings": {"Host": "partner.example.com"}}], "trace": []}
}

}
