/// Tests of the incident recorder OcuTalon.Eval.Record against a real failure (Story 9.4; AD-22, AD-15). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI
/// ONLY (Rule 21): it needs the Orders production in OCUORDERS, which a slot never has, and the repository's eval/ folder mounted at Eval.In FOLDER.
/// Where either is missing, every test fails with that reason, so that a broken stack can never give a green shard.
/// OnBeforeAllTests holds the Orders WatchMark, installs the evaluation set's test feed (Story 9.9; Test.Eval.Feed.Fixture: the production
/// OcuTalon.Test.Eval.Feed in the namespace EVALFEED) and sends its nine cases, then re-induces each incident of Recipes() (the demo's: a batch of 50
/// orders in MM/DD/YYYY, and the feed's nine), builds the live pack itself from Reader.Evidence and EvidencePack.Build, independently of Eval.Record,
/// and captures the same failures with Eval.Record into a folder of its own below TMP. OnAfterAllTests takes out fixture settings that a test left in
/// the Orders definition, removes the feed, and runs Clean, which releases the mark and deletes its folder and its messages, and returns their status.
/// The tests then read what was kept:
///   - TestCaptureWritesCase: the demo capture's two files, field by field; snapshot.json is the reader's own answer after Redact.Text, with nothing
///     added and nothing dropped; case.json is the committed case except recordedBy; the committed expectation; Eval.Report DEMOCASE names the case;
///   - TestReplayEqualsLive: the pack that Build gives the file just written, and the pack that Capture returned, equal the live pack exactly, for the
///     demo and for each case of the feed; (QA) and the packs replayed are those of the incident cases of eval/, at least 10;
///   - TestCommittedIsCurrent: the incident cases of eval/ and Recipes() are the same set, and the pack of each committed snapshot equals the live pack
///     once VOLATILE (row ids and times, which a re-induced incident cannot repeat) is removed from both;
///   - (QA) TestVolatileIsRowIdsAndTimesOnly: VOLATILE is exactly the six row ids and times, so no field of the evidence is masked in a comparison;
///   - TestFeedCasesRecorded (Story 9.9): the feed has at least 9 cases with unique names, at items of its production, and at least 2 held out; for
///     each, in this run's recording and in the committed snapshot, the source is the feed's, every failure is at the case's item with all the markers
///     of the case in its error, the item's host setting is a loopback address or an example host, and the committed case.json is the case;
///   - TestFeedOnlyInThrowaway: Install of a folder that does not exist is refused and changes nothing, the product's production names no test class,
///     and the feed's production has its testing switch off and no EnsLib.Testing.Service;
///   - TestFeedRemoved: Install over the running feed succeeds and runs, and after the OnAfterAllTests of another instance that holds only the feed no
///     namespace, database, folder, resource, grant, marker, role or web application of the feed is left, the service role's Resources are what they
///     were before the feed, and Reader.Productions lists no feed;
///   - TestNoIncidentMade: the Orders WatchMark was held while the failures were sent, and the recordings made no Orders incident;
///   - TestCleanRemovesBatch: the OnAfterAllTests of a run removes the messages of a batch of one order, its folder, the hold and the fixture settings
///     left in the Orders definition, with an OK status;
///   - TestWriteRedacts and TestWriteRefuses: the redaction and the refusals of Write on synthetic snapshots (no failure is induced), each leaving no
///     folder behind;
///   - TestCaptureRefuses: the refusals of Capture against the Orders production (a production that is not the namespace's own, keys that give no
///     failure, a case that is not valid), each with no pack and no folder;
///   - (QA) TestWriteKeepsCaseFields: Write puts the case in case.json as the recorder's record (heldOut as a JSON boolean, an empty fixKind for a
///     category with no fix, compact JSON and one line feed), leaves the caller's case unchanged, and replaces both files when it writes again;
///   - (QA) TestWriteRefusesMore: Write also refuses a local machine path or a character that is not ASCII in the case's own text, the remaining
///     home and temporary folder patterns, a snapshot that is not an object or whose failures are not a list, and a blank folder, and does not
///     refuse a folder that only looks like a temporary one;
///   - (QA) TestCaptureRefusesBadCaseFirst: Capture refuses a case that is not valid for that reason before it reads the production;
///   - (QA) TestCaptureDropsCredentialSettings: with credential-named settings (and one plain setting) in the definition of the failing Orders item,
///     the snapshot that Capture writes and the pack it returns hold the plain setting and none of the others, by name or by value. The test adds
///     the settings to the saved definition in OCUORDERS and takes them out again.
Class OcuTalon.Test.Eval.Record Extends %UnitTest.TestCase
{

/// The incident cases of the Orders demo that this class re-induces, comma-separated: one recipe in Induce for each. Recipes() adds the cases of the
/// test feed.
Parameter RECIPES = "orders-date-format";

/// The fields of an evidence pack that a re-induced incident cannot repeat (row ids and times), comma-separated. A dotted name is a field of an object
/// field, and a field of every entry of a list.
Parameter VOLATILE = "firstAt,lastAt,sample.headerId,sample.at,trace.headerId,trace.timeCreated";

/// The folder of this class's captures; each run uses a folder of its own below it.
Parameter TMP = "/tmp/zz-eval-record/";

/// The item of the Orders production that the demo failures are at.
Parameter ORDERSITEM = "OrdersFromPartner";

/// The settings that TestCaptureDropsCredentialSettings adds to the definition of the Orders item: four with a credential name (CREDENTIALS) and one plain
/// (NOTE), each with a value of its own.
Parameter CREDENTIALS = "Credentials,SMTPPassword,BotToken,ApiKey";

Parameter NOTE = "ZzFixtureNote";

Parameter SECRET = "zz-fixture-secret-1";

Parameter NOTEVALUE = "zz-fixture-note";

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 400);

/// 1 when OnBeforeAllTests held the Orders failures, so that OnAfterAllTests releases them.
Property Held As %Boolean;

/// 1 when the Orders WatchMark was ahead of now by more than 300 seconds right after OnBeforeAllTests held the failures, before the first order was sent.
Property HoldChecked As %Boolean;

/// 1 from the moment a test puts the fixture settings into the Orders definition until it has taken them out again, so that OnAfterAllTests takes
/// out what a test left.
Property SettingsAdded As %Boolean;

/// 1 from the moment OnBeforeAllTests begins to install the test feed until OnAfterAllTests (or a test) has removed it.
Property FeedInstalled As %Boolean;

/// By the name of each case of the feed, the reference that is the SuperSession of the case's messages.
Property FeedRefs As %DynamicObject;

/// The Resources of the service role before the feed was installed (after a leftover was removed), as the security database holds them.
Property RoleBefore As %String(MAXLEN = 4000);

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
	Set ..SettingsAdded = 0
	Set ..HoldChecked = 0
	Set ..FeedInstalled = 0
	Set ..FeedRefs = {}
	Set ..RoleBefore = ""
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
		If ..Missing = "" Do ..InstallFeed()
		Set recipes = $ListFromString(..Recipes()), position = 0
		While (..Missing = "") && $ListNext(recipes, position, name) {
			Do ..Make(name)
		}
	} Catch exception {
		Set ..Missing = "The incidents could not be recorded: "_exception.DisplayString()
	}
	Quit $$$OK
}

/// Takes the fixture settings out of the Orders definition while SettingsAdded is 1, removes the test feed while FeedInstalled is 1, then runs Clean. The
/// status is theirs, so that a clean-up that fails is reported.
Method OnAfterAllTests() As %Status
{
	Set sc = $$$OK
	If ..SettingsAdded {
		Set sc = ..FixtureSettings(0)
		If $$$ISOK(sc) Set ..SettingsAdded = 0
	}
	If ..FeedInstalled {
		Set feed = ##class(OcuTalon.Test.Eval.Feed.Fixture).Remove()
		If $$$ISOK(feed) Set ..FeedInstalled = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, feed)
	}
	Quit $SYSTEM.Status.AppendStatus(sc, ..Clean(..Refs, ..Folder, ..Held))
}

/// The incident cases that this class re-induces, comma-separated: RECIPES (the demo's) and the cases of the test feed.
ClassMethod Recipes() As %String
{
	Quit ..#RECIPES_","_##class(OcuTalon.Test.Eval.Feed.Fixture).Names()
}

/// Removes a leftover of the test feed (and so its grant), notes the Resources of the service role, installs the feed and sends its cases. FeedInstalled is 1
/// before the install begins, so that OnAfterAllTests removes what a failed install made. A failure is the reason in Missing.
Method InstallFeed() [ Private ]
{
	Set sc = ##class(OcuTalon.Test.Eval.Feed.Fixture).Remove()
	If $$$ISERR(sc) {
		Set ..Missing = "A leftover of the test feed could not be removed: "_$SYSTEM.Status.GetErrorText(sc)
		Quit
	}
	Set ..RoleBefore = ##class(OcuTalon.Test.Eval.Feed.Fixture).RoleResources()
	Set ..FeedInstalled = 1
	Set sc = ##class(OcuTalon.Test.Eval.Feed.Fixture).Install()
	If $$$ISOK(sc) Set sc = ##class(OcuTalon.Test.Eval.Feed.Fixture).Start(.refs)
	If $$$ISERR(sc) {
		Set ..Missing = "The test feed could not be installed and started: "_$SYSTEM.Status.GetErrorText(sc)
		Quit
	}
	Set ..FeedRefs = refs
}

/// Releases the Orders WatchMark when held is 1, deletes the folder with everything in it, and deletes the Orders messages of the batches (the
/// SuperSession references in the array). The status is the release's and the deletion's.
ClassMethod Clean(refs As %DynamicArray, folder As %String, held As %Boolean) As %Status
{
	Set demo = "OcuTalon.Test.Demo.Production"
	Set sc = $$$OK
	If held Set sc = $ClassMethod(demo, "ReleaseFailures")
	If folder '= "" Do ##class(%File).RemoveDirectoryTree(folder)
	If $IsObject(refs) && (refs.%Size() > 0) Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(refs, $Parameter(demo, "NAMESPACE")))
	Quit sc
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

/// Gives where and which the failures of the incident are: the namespace, production and item they are at and the keys of their failed headers (h<id>,
/// ascending). For the demo it sends the failures into the Orders production and keeps the batch's reference in Refs; for a case of the test feed it
/// waits for the failures that OnBeforeAllTests sent. An unknown name is an error.
Method Induce(name As %String, Output namespace As %String, Output production As %String, Output item As %String, Output keys As %String) As %Status
{
	Set keys = ""
	If $IsObject(##class(OcuTalon.Test.Eval.Feed.Fixture).Definition(name)) {
		Set ref = ..FeedRefs.%Get(name)
		If ref = "" Quit $$$ERROR($$$GeneralError, "The test feed sent no batch for the case "_name)
		Quit ##class(OcuTalon.Test.Eval.Feed.Fixture).Keys(name, ref, .namespace, .production, .item, .keys)
	}
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
/// recipe. The live pack is not empty. (QA) The recipes replayed are the incident cases of eval/, at least 10, so that a recipe left out of the loop, or a
/// case with no recipe, fails here too.
Method TestReplayEqualsLive()
{
	If '..Guard() Quit
	Set recipes = $ListFromString(..Recipes()), position = 0, replayed = 0
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
		If $IsObject(replay) && $IsObject(entry.captured) Set replayed = replayed + 1
	}
	Set cases = ..IncidentCases(##class(%File).NormalizeDirectory(##class(OcuTalon.Eval.In).#FOLDER))
	Do $$$AssertTrue($ListLength(cases) >= 10, "eval/ holds at least 10 incident cases: "_$ListLength(cases))
	Do $$$AssertEquals(replayed, $ListLength(cases), "the pack of every incident case of eval/ was replayed and compared: "_replayed_" of "_$ListToString(cases))
}

/// The incident cases of eval/ and Recipes() are the same set, in both directions, so a case with no recipe fails; and for each recipe the pack that Build
/// gives the committed snapshot equals the live pack once VOLATILE is removed from both.
Method TestCommittedIsCurrent()
{
	If '..Guard() Quit
	Set folder = ##class(%File).NormalizeDirectory(##class(OcuTalon.Eval.In).#FOLDER)
	Set recipes = $ListFromString(..Recipes()), cases = ..IncidentCases(folder)
	Set position = 0
	While $ListNext(cases, position, name) {
		Do $$$AssertTrue($ListFind(recipes, name), name_": the incident case has a recipe in Recipes()")
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

/// (QA) What a committed pack may differ in is fixed: VOLATILE is exactly the row ids and times of the pack (firstAt, lastAt, sample.headerId, sample.at,
/// trace.headerId and trace.timeCreated), so that no field of the evidence a diagnosis reads (the error, its pattern, the body, the count, the item, the
/// settings) is ever masked when a committed snapshot is compared with a fresh recording. Widening it is a decision of its own, not a way to make a
/// drifting recording pass.
Method TestVolatileIsRowIdsAndTimesOnly()
{
	Kill wanted, found
	Set paths = $ListFromString("firstAt,lastAt,sample.headerId,sample.at,trace.headerId,trace.timeCreated"), position = 0
	While $ListNext(paths, position, path) {
		Set wanted(path) = ""
	}
	Set paths = $ListFromString(..#VOLATILE), position = 0
	While $ListNext(paths, position, path) {
		Set found(path) = ""
	}
	Set extra = "", missing = "", path = ""
	For {
		Set path = $Order(found(path))
		If path = "" Quit
		If '$Data(wanted(path)) Set extra = extra_" "_path
	}
	For {
		Set path = $Order(wanted(path))
		If path = "" Quit
		If '$Data(found(path)) Set missing = missing_" "_path
	}
	Do $$$AssertEquals(extra, "", "VOLATILE masks no field beyond the row ids and times")
	Do $$$AssertEquals(missing, "", "and it masks every row id and time of the pack")
}

/// The cases of the test feed (Story 9.9): the feed has at least 9 cases with unique names, none of them the demo's, each at an item of the feed's
/// production, and at least 2 held out. For each case, in this run's recording (the reader's answer) and in the committed snapshot.json: the source is the
/// feed's namespace, production and the case's item; it holds as many failures as the case has messages, every one at the case's item with every marker
/// of the case in its error; and the item's HTTPServer setting, where it has one, is a loopback address or an example host. The committed case.json is
/// the case of the definition: name, kind incident, heldOut, description, snapshot.json, expectation and recorder.
Method TestFeedCasesRecorded()
{
	If '..Guard() Quit
	Set fixture = "OcuTalon.Test.Eval.Feed.Fixture"
	Set definitions = $ClassMethod(fixture, "Definitions")
	Set folder = ##class(%File).NormalizeDirectory(##class(OcuTalon.Eval.In).#FOLDER)
	Set items = ..XDataValues($Parameter(fixture, "PRODUCTION"), "<Item Name=""([^""]*)""")
	Do $$$AssertTrue(definitions.%Size() >= 9, "the feed has at least 9 cases: "_definitions.%Size())
	Kill seen
	Set heldOut = 0, repeated = "", strays = "", demo = ""
	Set iterator = definitions.%GetIterator()
	While iterator.%GetNext(, .definition) {
		If $Data(seen(definition.name)) Set repeated = repeated_" "_definition.name
		Set seen(definition.name) = ""
		If definition.name = ##class(OcuTalon.Eval.Report).#DEMOCASE Set demo = demo_" "_definition.name
		If '$ListFind(items, definition.item) Set strays = strays_" "_definition.name
		Set heldOut = heldOut + +definition.heldOut
	}
	Do $$$AssertEquals(repeated, "", "the names of the cases are unique")
	Do $$$AssertEquals(demo, "", "no case is the demo's")
	Do $$$AssertEquals(strays, "", "every case is at an item of the production "_$Parameter(fixture, "PRODUCTION"))
	Do $$$AssertTrue(heldOut >= 2, "at least 2 cases are held out: "_heldOut)
	Set iterator = definitions.%GetIterator()
	While iterator.%GetNext(, .definition) {
		Set name = definition.name
		Set entry = ..Entry(name)
		If $IsObject(entry) {
			Do $$$AssertEquals(entry.error, "", name_": Capture succeeded")
			Do ..AssertFeedSnapshot(name_" (this run)", definition, entry.answer)
		}
		Set file = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.Record).#SNAPSHOTFILE, ##class(%File).SubDirectoryName(folder, name))
		Do $$$AssertTrue(##class(%File).Exists(file), name_": the committed snapshot exists")
		If ##class(%File).Exists(file) {
			Set snapshot = ""
			Do $$$AssertStatusOK(##class(OcuTalon.Watch.EvidencePack).Load(file, .snapshot), name_": the committed snapshot is a reader snapshot")
			If $IsObject(snapshot) Do ..AssertFeedSnapshot(name_" (committed)", definition, snapshot)
		}
		Set committed = ##class(OcuTalon.Test.Eval.Cases).Read(folder, name)
		Do $$$AssertTrue($IsObject(committed), name_": eval/"_name_"/case.json exists")
		If $IsObject(committed) {
			Set expected = {"name": (name), "kind": (##class(OcuTalon.Eval.Report).#INCIDENTKIND)}
			Do expected.%Set("heldOut", +definition.heldOut, "boolean")
			Set expected.description = definition.description
			Set expected.snapshot = ##class(OcuTalon.Eval.Record).#SNAPSHOTFILE
			Set expected.expectation = {"causeCategory": (definition.expectation.causeCategory), "elementAtFault": (definition.expectation.elementAtFault), "fixKind": (definition.expectation.fixKind)}
			Set expected.recordedBy = ##class(OcuTalon.Eval.Record).#RECORDEDBY
			Do $$$AssertEquals(committed.%ToJSON(), expected.%ToJSON(), name_": the committed case.json is the case of the definition")
		}
	}
}

/// The test feed lives only in throwaways (Story 9.9; CON-3): Install of a folder that does not exist (the throwaway's mount of the evaluation set
/// stands in for it) returns the refusal and changes nothing; the compiled definition of the product's production OcuTalon.Production names no class of
/// OcuTalon.Test; and the feed's own production has its testing switch off and no EnsLib.Testing.Service item.
Method TestFeedOnlyInThrowaway()
{
	If '..Guard() Quit
	Set fixture = "OcuTalon.Test.Eval.Feed.Fixture"
	Set before = $ClassMethod(fixture, "Leftovers")
	Set sc = $ClassMethod(fixture, "Install", ..Folder_"not-a-throwaway/")
	Do $$$AssertStatusNotOK(sc, "Install of a folder that does not exist is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ $Parameter(fixture, "REFUSAL"), "with the reason: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals($ClassMethod(fixture, "Leftovers"), before, "and nothing changed: the namespace, database, folder, resource and grant of the feed are as before")
	Set classes = ..XDataValues("OcuTalon.Production", "ClassName=""([^""]*)""")
	Set position = 0, tests = ""
	While $ListNext(classes, position, class) {
		If $Extract(class, 1, $Length("OcuTalon.Test.")) = "OcuTalon.Test." Set tests = tests_" "_class
	}
	Do $$$AssertTrue($ListLength(classes) > 0, "the production of the product names classes: "_$ListLength(classes))
	Do $$$AssertEquals(tests, "", "and none of them is a test class")
	Set feed = $Parameter(fixture, "PRODUCTION")
	Set text = ##class(%Dictionary.XDataDefinition).%OpenId(feed_"||ProductionDefinition").Data.Read(1000000)
	Do $$$AssertTrue(text [ "TestingEnabled=""false""", "the feed's testing switch is off")
	Do $$$AssertNotTrue(text [ "EnsLib.Testing.Service", "and the feed has no EnsLib.Testing.Service")
}

/// Remove leaves nothing (Story 9.9): Install succeeds over the running feed (it removes the leftover first) and the feed runs in its namespace and is
/// listed by Reader.Productions; then the OnAfterAllTests of a second instance of this class that holds only the feed returns OK, and after it no
/// namespace, database, folder, resource, grant, Interoperability marker, Interoperability role or web application of the feed is left, the Resources of
/// the service role are what they were before the feed, Reader.Productions lists no feed, and a further Remove returns OK. The OnAfterAllTests of this
/// instance then has nothing left to remove (FeedInstalled is 0).
Method TestFeedRemoved()
{
	If '..Guard() Quit
	Set fixture = "OcuTalon.Test.Eval.Feed.Fixture"
	Set namespace = $Parameter(fixture, "NAMESPACE")
	Set ..FeedInstalled = 1
	Do $$$AssertStatusOK($ClassMethod(fixture, "Install"), "Install succeeds over the running feed")
	Do $$$AssertTrue($ClassMethod(fixture, "Running"), "and the feed runs in "_namespace)
	Do $$$AssertTrue(..Listed(namespace), "and Reader.Productions lists it while it exists")
	Set closing = ##class(OcuTalon.Test.Eval.Record).%New("")
	Set closing.Refs = []
	Set closing.Folder = ""
	Set closing.Held = 0
	Set closing.SettingsAdded = 0
	Set closing.FeedInstalled = 1
	Do $$$AssertStatusOK(closing.OnAfterAllTests(), "the end of a run that installed the feed")
	Do $$$AssertEquals($ClassMethod(fixture, "Leftovers"), "", "no namespace, database, folder, resource, grant, marker, role or web application of the feed is left")
	Do $$$AssertEquals($ClassMethod(fixture, "RoleResources"), ..RoleBefore, "the Resources of the service role are what they were before the feed")
	Do $$$AssertNotTrue(..Listed(namespace), "Reader.Productions lists no feed")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Remove"), "a further Remove returns OK")
	If $ClassMethod(fixture, "Leftovers") = "" Set ..FeedInstalled = 0
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

/// The OnAfterAllTests of a run deletes the Orders messages of its batches, its folder, the hold and fixture settings that a test left, and returns
/// their status: a batch of one order of the test's own fails at the item, a folder is made, the fixture settings are put into the Orders definition,
/// and after the OnAfterAllTests of another instance of this class that holds that batch, folder, hold and SettingsAdded, the batch has no header, the
/// folder is gone, the mark is at the release time and the definition holds the settings it held before. The test then holds the failures again for
/// the tests after it. Its reference is also kept in Refs, and its own SettingsAdded is 1 until the settings are out, so that this run's
/// OnAfterAllTests cleans up should the test fail halfway.
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
	Set settings = ..DefinedSettings()
	Set ..SettingsAdded = 1
	Do $$$AssertStatusOK(..FixtureSettings(1), "the fixture settings are put into the definition of "_..#ORDERSITEM)
	Set closing = ##class(OcuTalon.Test.Eval.Record).%New("")
	Set closing.Refs = [(ref)]
	Set closing.Folder = folder
	Set closing.Held = 1
	Set closing.SettingsAdded = 1
	Do $$$AssertStatusOK(closing.OnAfterAllTests(), "the end of a run that held the failures, sent a batch and left the fixture settings")
	Do $$$AssertEquals($ClassMethod(demo, "Headers", ref).%Size(), 0, "deleted the headers of the batch")
	Do $$$AssertNotTrue(##class(%File).DirectoryExists(folder), "and the folder")
	Do $$$AssertTrue('$ClassMethod(demo, "MarkIsAhead", 60), "and released the Orders WatchMark")
	Do $$$AssertTrue($ClassMethod(demo, "MarkIsAhead", -30), "to the release time, not left behind")
	Do $$$AssertEquals(..DefinedSettings(), settings, "and took the fixture settings out of the definition")
	Set sc = $Select(..DefinedSettings() = settings: $$$OK, 1: ..FixtureSettings(0))
	If $$$ISOK(sc) Set ..SettingsAdded = 0
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

/// (QA) Write puts the case in case.json as the recorder's record and nothing else: a held-out case keeps heldOut true as a JSON boolean, a case with no
/// heldOut gets false, a category with no fix keeps an empty fixKind, case.json is exactly the record's compact JSON and one line feed, and the case
/// the caller holds is unchanged. A second Write of the case replaces case.json and snapshot.json with the new text instead of adding to them.
Method TestWriteKeepsCaseFields()
{
	If '..Guard() Quit
	Set base = ..Folder_"fields/"
	Set recordedBy = ##class(OcuTalon.Eval.Record).#RECORDEDBY
	Set case = ..SyntheticCase("zz-fields")
	Do case.%Set("heldOut", 1, "boolean")
	Set case.description = "A held-out failure of the connection."
	Set case.expectation.causeCategory = "connection_failure"
	Set case.expectation.elementAtFault = "ZzItem"
	Set case.expectation.fixKind = ""
	Set before = case.%ToJSON()
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Record).Write(case, ..Synthetic(), base), "Write accepts a held-out case whose category has no fix")
	Set directory = ##class(%File).SubDirectoryName(base, "zz-fields")
	Set caseFile = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.Record).#CASEFILE, directory)
	Set snapshotFile = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.Record).#SNAPSHOTFILE, directory)
	Set expected = {"name": "zz-fields", "kind": "incident", "heldOut": true, "description": "A held-out failure of the connection.", "snapshot": "snapshot.json", "expectation": {"causeCategory": "connection_failure", "elementAtFault": "ZzItem", "fixKind": ""}, "recordedBy": (recordedBy)}
	Do $$$AssertEquals(..ReadText(caseFile), expected.%ToJSON()_$Char(10), "case.json is the record as compact JSON and one line feed, with heldOut true and an empty fixKind")
	Do $$$AssertEquals(case.%ToJSON(), before, "the case that the caller holds is unchanged")
	Set second = ..SyntheticCase("zz-fields")
	Do second.%Remove("heldOut")
	Set second.description = "The second recording."
	Set snapshot = ..Synthetic(, "ERROR #5001: The second failure.")
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Record).Write(second, snapshot, base), "a second Write of the same case")
	Set expected = {"name": "zz-fields", "kind": "incident", "heldOut": false, "description": "The second recording.", "snapshot": "snapshot.json", "expectation": {"causeCategory": "data_format_change", "elementAtFault": "OrderDate", "fixKind": "repair_resend"}, "recordedBy": (recordedBy)}
	Do $$$AssertEquals(..ReadText(caseFile), expected.%ToJSON()_$Char(10), "replaced case.json with the record of the second case, heldOut false by default")
	Do $$$AssertEquals(..ReadText(snapshotFile), ##class(OcuTalon.Bridge.Redact).Text(snapshot.%ToJSON())_$Char(10), "and replaced snapshot.json with the second snapshot")
}

/// (QA) Write refuses, with the reason and no file, a local machine path or a character that is not ASCII in the text of the case itself (its description
/// and its elementAtFault), the temporary-folder patterns that TestWriteRefuses leaves out, a snapshot that is not a JSON object, a snapshot whose
/// failures are text and a blank folder; and it does not refuse a folder that only looks like a temporary one.
Method TestWriteRefusesMore()
{
	If '..Guard() Quit
	Set base = ..Folder_"refusesmore/"
	Set notLocal = ##class(OcuTalon.Eval.Record).#NOTLOCAL, notAscii = ##class(OcuTalon.Eval.Record).#NOTASCII
	Set valid = ..SyntheticCase("zz-refused")
	Set case = ..SyntheticCase("zz-refused")
	Set case.description = "Recorded at /Use"_"rs/zzname/x"
	Do ..AssertRefused("a description holding a home folder", case, ..Synthetic(), base, "the case holds "_notLocal)
	Set case = ..SyntheticCase("zz-refused")
	Set case.expectation.elementAtFault = "/hom"_"e/zzname/x"
	Do ..AssertRefused("an elementAtFault holding a home folder", case, ..Synthetic(), base, "the case holds "_notLocal)
	Set case = ..SyntheticCase("zz-refused")
	Set case.expectation.elementAtFault = "Or"_$Char(233)
	Do ..AssertRefused("an elementAtFault holding a character that is not ASCII", case, ..Synthetic(), base, "the case holds "_notAscii)
	For path = "/privat"_"e/var/x", "/privat"_"e/etc/x" {
		Do ..AssertRefused("a body holding "_path, valid, ..Synthetic({"OrderNumber": (path)}), base, "the snapshot holds "_notLocal)
	}
	Set snapshot = ..Synthetic()
	Set snapshot.failures = "none"
	Do ..AssertRefused("a snapshot whose failures are text", valid, snapshot, base, "holds no failure")
	Do ..AssertRefused("a snapshot that is a list", valid, [], base, "not of the format")
	Do ..AssertRefused("a snapshot that is text", valid, "text", base, "not of the format")
	Do ..AssertRefused("a blank folder", valid, ..Synthetic(), " ", "the folder is blank")
	Do $$$AssertNotTrue(##class(%File).DirectoryExists(base), "nothing was written: no folder was made for any refused case")
	Set lookalike = ..Folder_"lookalike/"
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Record).Write(valid, ..Synthetic({"OrderNumber": ("/opt/va"_"r/folders/zz")}), lookalike), "a folder below another one that is named var/folders is not refused")
}

/// (QA) The snapshot that Capture writes has no setting with a credential name: four credential settings and one plain setting are added to the saved
/// definition of the failing Orders item, Capture records the first failure of the batch, and the written file and the returned pack hold the plain
/// setting with its value and none of the others, by name or by value. The settings are taken out again.
Method TestCaptureDropsCredentialSettings()
{
	If '..Guard() Quit
	Set entry = ..Entry("orders-date-format")
	If '$IsObject(entry) Quit
	Set demo = "OcuTalon.Test.Demo.Production"
	Set namespace = $Parameter(demo, "NAMESPACE"), production = $Parameter(demo, "PRODUCTION")
	Set key = "h"_entry.answer.failures.%Get(0).headerId
	Set base = ..Folder_"credentials/"
	Set before = ..DefinedSettings()
	Set ..SettingsAdded = 1
	Try {
		Do $$$AssertStatusOK(..FixtureSettings(1), "the credential settings and a plain one are added to the definition of "_..#ORDERSITEM)
		Set held = ..DefinedSettings()
		Set missing = ""
		Set names = $ListFromString(..#CREDENTIALS_","_..#NOTE), position = 0
		While $ListNext(names, position, name) {
			If $ListFind($ListFromString(held), name) = 0 Set missing = missing_" "_name
		}
		Do $$$AssertEquals(missing, "", "the definition holds all five, so that there is something to leave out: "_held)
		Set sc = ##class(OcuTalon.Eval.Record).Capture(..SyntheticCase("zz-credentials"), namespace, production, ..#ORDERSITEM, key, base, .pack)
		Do $$$AssertStatusOK(sc, "Capture records the failure of an item whose definition holds credential settings")
		Set file = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.Record).#SNAPSHOTFILE, ##class(%File).SubDirectoryName(base, "zz-credentials"))
		Set text = ..ReadText(file)
		Do $$$AssertTrue(text '= "", "snapshot.json was written")
		Set snapshot = ##class(%DynamicAbstractObject).%FromJSON(text)
		Do $$$AssertEquals(snapshot.items.%Size(), 1, "it holds the one item")
		If snapshot.items.%Size() = 1 {
			Set settings = snapshot.items.%Get(0).settings
			Kill sorted
			Set iterator = settings.%GetIterator()
			While iterator.%GetNext(.setting) {
				Set sorted(setting) = ""
			}
			Set kept = "", setting = ""
			For {
				Set setting = $Order(sorted(setting))
				If setting = "" Quit
				Set kept = kept_$Select(kept = "": "", 1: ",")_setting
			}
			Do $$$AssertEquals(kept, "TargetConfigName,"_..#NOTE, "its settings are the item's plain ones, with no credential setting")
			Do $$$AssertEquals(settings.%Get(..#NOTE), ..#NOTEVALUE, "and the plain one keeps its value")
		}
		Set packText = $Select($IsObject(pack): pack.%ToJSON(), 1: "")
		Do $$$AssertTrue(packText '= "", "Capture returned a pack")
		Set names = $ListFromString(..#CREDENTIALS), position = 0
		Set leaked = ""
		While $ListNext(names, position, name) {
			If (text [ (""""_name_"""")) || (packText [ (""""_name_"""")) Set leaked = leaked_" "_name
		}
		Do $$$AssertEquals(leaked, "", "no credential setting is named in the file or the pack")
		Do $$$AssertTrue((text '[ ..#SECRET) && (packText '[ ..#SECRET), "and no credential value is in the file or the pack")
	} Catch exception {
		Do $$$AssertTrue(0, "the credential test threw: "_exception.DisplayString())
	}
	Set sc = ..FixtureSettings(0)
	If $$$ISOK(sc) Set ..SettingsAdded = 0
	Do $$$AssertStatusOK(sc, "the settings are taken out of the definition again")
	Do $$$AssertEquals(..DefinedSettings(), before, "the definition holds the settings it held before")
}

/// (QA) Capture refuses a case that is not valid for that reason before it reads the production: the reason names the case's field also where the
/// production is not the namespace's own and where the keys give no failure, which would be refused for another reason if the production were read first.
Method TestCaptureRefusesBadCaseFirst()
{
	If '..Guard() Quit
	Set base = ..Folder_"badcase/"
	Set demo = "OcuTalon.Test.Demo.Production"
	Set namespace = $Parameter(demo, "NAMESPACE"), production = $Parameter(demo, "PRODUCTION")
	Set sc = ##class(OcuTalon.Eval.Record).Capture(..SyntheticCase("Bad_Name"), namespace, "Zz.NoProduction", ..#ORDERSITEM, "h1", base, .pack)
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertStatusNotOK(sc, "a case whose name is not valid is refused")
	Do $$$AssertTrue((text [ "lower-case kebab") && (text '[ "not_current"), "for its name, and the production was not read: "_text)
	Do $$$AssertEquals(pack, "", "and no pack is returned")
	Set case = ..SyntheticCase("zz-captured")
	Set case.expectation.causeCategory = "weather"
	Set sc = ##class(OcuTalon.Eval.Record).Capture(case, namespace, production, ..#ORDERSITEM, "", base, .pack)
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertStatusNotOK(sc, "a case whose causeCategory is not valid is refused")
	Do $$$AssertTrue((text [ "causeCategory") && (text '[ ##class(OcuTalon.Eval.Record).#NOFAILURE), "for its causeCategory, not for the keys: "_text)
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

/// The names of the incident cases that the folder holds, as a list, in the order of Eval.In CaseNames.
ClassMethod IncidentCases(folder As %String) As %List [ Private ]
{
	Set cases = "", position = 0
	Set names = ##class(OcuTalon.Eval.In).CaseNames(folder, "")
	While $ListNext(names, position, name) {
		Set case = ##class(OcuTalon.Test.Eval.Cases).Read(folder, name)
		If $IsObject(case) && (case.kind = ##class(OcuTalon.Eval.Report).#INCIDENTKIND) Set cases = cases_$ListBuild(name)
	}
	Quit cases
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

/// Asserts the evidence of one case of the test feed in a reader snapshot (this run's answer or the committed file): the source, the failures and
/// their errors, and the host setting of the item (see TestFeedCasesRecorded).
Method AssertFeedSnapshot(label As %String, definition As %DynamicObject, snapshot As %DynamicObject) [ Private ]
{
	Set fixture = "OcuTalon.Test.Eval.Feed.Fixture"
	Set item = definition.item
	Set source = {"namespace": ($Parameter(fixture, "NAMESPACE")), "production": ($Parameter(fixture, "PRODUCTION")), "item": (item)}
	Do $$$AssertEquals(snapshot.source.%ToJSON(), source.%ToJSON(), label_": the source is the feed's item")
	Do $$$AssertEquals(snapshot.failures.%Size(), definition.messages.%Size(), label_": it holds the failures of all the messages")
	Set wrong = ""
	Set iterator = snapshot.failures.%GetIterator()
	While iterator.%GetNext(.i, .failure) {
		If failure.targetConfigName '= item Set wrong = wrong_" "_i_"(item)"
		Set markers = definition.errorHas.%GetIterator()
		While markers.%GetNext(, .marker) {
			If failure.error '[ marker Set wrong = wrong_" "_i_"("_marker_")"
		}
	}
	Do $$$AssertEquals(wrong, "", label_": every failure is at "_item_" and its error holds every marker of the case")
	Set host = "", found = 0
	Set entries = snapshot.items.%GetIterator()
	While entries.%GetNext(, .entry) {
		If entry.name '= item Continue
		Set found = 1
		If entry.settings.%GetTypeOf("HTTPServer") = "string" Set host = entry.settings.HTTPServer
	}
	Do $$$AssertTrue(found, label_": the snapshot holds the item "_item)
	Do $$$AssertTrue((host = "") || (host = "127.0.0.1") || (host = "example.com") || ($Piece(host, ".", $Length(host, ".")) = "example"), label_": the host setting of the item is a loopback address or an example host: "_host)
}

/// The values (the first group of the regular expression) in the saved definition of the production class's ProductionDefinition XData, as a list. It
/// reads the class definition (%Dictionary.XDataDefinition), so that no edit of a saved production definition can sway it.
ClassMethod XDataValues(class As %String, pattern As %String) As %List [ Private ]
{
	Set text = ##class(%Dictionary.XDataDefinition).%OpenId(class_"||ProductionDefinition").Data.Read(1000000)
	Set matcher = ##class(%Regex.Matcher).%New(pattern, text)
	Set values = ""
	While matcher.Locate() {
		Set values = values_$ListBuild(matcher.Group(1))
	}
	Quit values
}

/// 1 when Reader.Productions lists an entry in the namespace.
ClassMethod Listed(namespace As %String) As %Boolean [ Private ]
{
	Set found = 0
	Set iterator = ##class(OcuTalon.Watch.Reader).Productions().%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.namespace = namespace Set found = 1
	}
	Quit found
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

/// Puts the fixture settings into (on) or takes them out of (off) the Orders item in the saved Orders definition of OCUORDERS, and saves it. It first
/// takes out any of them that are there, so that it can be called twice. It calls only Ens classes while it is in OCUORDERS and does not update the
/// running production.
ClassMethod FixtureSettings(on As %Boolean) As %Status [ Private ]
{
	Set demo = "OcuTalon.Test.Demo.Production"
	Set namespace = $Parameter(demo, "NAMESPACE"), productionName = $Parameter(demo, "PRODUCTION"), itemName = ..#ORDERSITEM
	Set names = $ListFromString(..#CREDENTIALS_","_..#NOTE)
	Set secret = ..#SECRET, noteName = ..#NOTE, noteValue = ..#NOTEVALUE
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Set production = ##class(Ens.Config.Production).%OpenId(productionName)
	If '$IsObject(production) Quit $SYSTEM.Status.Error(5001, "There is no definition of "_productionName)
	Set found = 0
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		If item.Name '= itemName Continue
		Set found = 1
		For j = item.Settings.Count():-1:1 {
			If $ListFind(names, item.Settings.GetAt(j).Name) Do item.Settings.RemoveAt(j)
		}
		If on {
			Set position = 0
			While $ListNext(names, position, name) {
				Set setting = ##class(Ens.Config.Setting).%New()
				Set setting.Target = "Host"
				Set setting.Name = name
				Set setting.Value = $Select(name = noteName: noteValue, 1: secret)
				Do item.Settings.Insert(setting)
			}
		}
		Quit
	}
	If 'found Quit $SYSTEM.Status.Error(5001, "The definition has no item "_itemName)
	Quit production.%Save()
}

/// The names of the settings of the Orders item in the saved Orders definition of OCUORDERS, comma-separated and sorted, read from the definition itself.
ClassMethod DefinedSettings() As %String [ Private ]
{
	Set demo = "OcuTalon.Test.Demo.Production"
	Set namespace = $Parameter(demo, "NAMESPACE"), productionName = $Parameter(demo, "PRODUCTION"), itemName = ..#ORDERSITEM
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Set production = ##class(Ens.Config.Production).%OpenId(productionName)
	If '$IsObject(production) Quit "<no definition>"
	Kill names
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		If item.Name '= itemName Continue
		For j = 1:1:item.Settings.Count() Set names(item.Settings.GetAt(j).Name) = ""
		Quit
	}
	Set list = "", name = ""
	For {
		Set name = $Order(names(name))
		If name = "" Quit
		Set list = list_$Select(list = "": "", 1: ",")_name
	}
	Quit list
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
