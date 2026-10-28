/// Tests of the recorded cases of eval/ against EvalIn (Story 9.1; AD-22, UX-DR86). WARM-SAFE: they read the repository's eval/
/// folder, which every throwaway stack mounts read-only at EvalIn's FOLDER, and hand each case to a shadow instance of
/// OcuTalon.Test.Eval.ZzIn, the double of EvalIn whose Dispatch sends nothing and records the Item. They start no production and send
/// no message; where eval/ is not mounted (a dev slot) they fail with the reason.
///   - TestRecordedCases: every case of eval/ (a subfolder that holds a case.json) is named for its folder; every case of a kind that holds a
///     recorded Item (item or injection) is sent by EvalIn as the Item that the record says, so a run over the whole folder skips no
///     such case; a case of any other kind (the incident case) is skipped with its kind in the reason; the catalog key and the slots that the
///     double records (list positions 9 and 10) are the record's (Story 9.3);
///   - TestNewsletterCase: eval/mail-newsletter is the item case of Task 5: kind item, not held out, recorded id mail-newsletter,
///     provenance untrusted, channel mailbox, the exact sender, subject and body of the simulated mailbox's newsletter (UX-DR86), and the
///     expectation {"outcome": "ignore"}, an outcome of the product's Msg.Enum;
///   - TestSampleEmails (Story 9.3): the newsletter and the partner notice are item cases and the suspicious request is an injection case,
///     each in the mailbox channel, untrusted, with the exact sender, subject and body of its SimMailbox.In parameters (UX-DR86);
///   - TestFindingCases (Story 9.3): every case with a catalog key is an untrusted system Item with no sender or subject, a key of
///     Eval.Report FINDINGKEYS (both keys are used), exactly the slots its catalog entry declares, a catalog text that renders, and a text
///     that is the entry's text with the slots filled and the time written in UTC.
Class OcuTalon.Test.Eval.Cases Extends %UnitTest.TestCase
{

/// The double of EvalIn.
Parameter DOUBLE = "OcuTalon.Test.Eval.ZzIn";

/// The Ref of the run of the test.
Property Run As %String(MAXLEN = 22);

/// The newest row of the event log when the test began.
Property Mark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("EvalIn")
	Set ..Run = "zz"_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 20)
	Set ..Mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("EvalIn")
	Do ##class(OcuTalon.Eval.Data.CaseResult).Remove(..Run)
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..Mark, "OnProcessInput", ##class(OcuTalon.Eval.In).#LOGSKIPPED)
	Quit $$$OK
}

/// Every case of eval/ is named for its folder, and every case that holds a recorded Item is sent as that Item. The kinds that hold one (item and
/// injection, as the spec says) are named here, not read from EvalIn's KINDS, so that a change of that parameter is seen.
Method TestRecordedCases()
{
	Set folder = ..Folder()
	Set names = ..Names(folder)
	If names = "" Quit
	Do $$$AssertTrue($ListFind(names, "mail-newsletter"), "eval/ holds the newsletter case")
	Set service = ##class(Ens.Host).GetShadowInstance("class||"_..#DOUBLE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the EvalIn double is made")
	If '$IsObject(service) Quit
	Set service.RunRef = ..Run
	Set position = 0, sendable = 0
	While $ListNext(names, position, name) {
		Set case = ##class(%DynamicAbstractObject).%FromJSONFile(##class(%File).NormalizeFilename("case.json", ##class(%File).SubDirectoryName(folder, name)))
		Do $$$AssertEquals(case.name, name, name_": the case's name is its folder's")
		Do $$$AssertTrue($IsObject(case.expectation), name_": it records an expectation")
		Kill output
		Do $$$AssertStatusOK(service.OnProcessInput(##class(Ens.StringContainer).%New(##class(%File).SubDirectoryName(folder, name)), .output), name_": OnProcessInput answers OK")
		If $ListFind($ListBuild("item", "injection"), case.kind) {
			Set sendable = sendable + 1
			Do $$$AssertEquals(output.StringValue, "", name_": a case of kind "_case.kind_" is sent")
			Set seen = $Get(^OcuTalonTest("EvalIn", "seen", sendable))
			If seen = "" Do $$$AssertTrue(0, name_": the double was given its Item") Continue
			Set record = case.item
			Do $$$AssertEquals($List(seen, 2)_"|"_$List(seen, 3)_"|"_$List(seen, 5), record.itemId_"|eval|untrusted", name_": SourceItemId is the recorded id, owner eval, untrusted")
			Do $$$AssertEquals($List(seen, 4)_"|"_$List(seen, 6)_"|"_$List(seen, 7)_"|"_$List(seen, 8), record.channel_"|"_record.sender_"|"_record.subject_"|"_record.text, name_": channel, sender, subject and text are the record's")
			Do $$$AssertEquals($List(seen, 9)_"|"_$List(seen, 10), record.%Get("catalogKey")_"|"_$Select($IsObject(record.slots): record.slots.%ToJSON(), 1: ""), name_": the catalog key and the slots are the record's")
		} Else {
			Do $$$AssertTrue(output.StringValue [ case.kind, name_": a case of kind "_case.kind_" is skipped with its kind in the reason: "_output.StringValue)
		}
	}
	Do $$$AssertTrue(sendable >= 1, "eval/ holds at least one case that EvalIn sends: "_sendable)
	Do $$$AssertEquals(+$Get(^OcuTalonTest("EvalIn", "seen")), sendable, "and the double was given exactly those Items")
}

/// The newsletter case is the one Task 5 sets out.
Method TestNewsletterCase()
{
	Set folder = ..Folder()
	If folder = "" Quit
	Set file = ##class(%File).NormalizeFilename("case.json", ##class(%File).SubDirectoryName(folder, "mail-newsletter"))
	Do $$$AssertTrue(##class(%File).Exists(file), "eval/mail-newsletter/case.json exists")
	If '##class(%File).Exists(file) Quit
	Set case = ##class(%DynamicAbstractObject).%FromJSONFile(file)
	Do $$$AssertEquals(case.name_"|"_case.kind_"|"_case.heldOut, "mail-newsletter|item|0", "the case is named for its folder, is an item case, and is not held out")
	Do $$$AssertEquals(case.item.itemId_"|"_case.item.channel_"|"_case.item.provenance, "mail-newsletter|mailbox|untrusted", "its recorded id is mail-newsletter, in the mailbox channel, untrusted")
	Do $$$AssertEquals(case.item.sender, ##class(OcuTalon.Channel.SimMailbox.In).#NEWSLETTERFROM, "its sender is the simulated mailbox's newsletter sender")
	Do $$$AssertEquals(case.item.subject, ##class(OcuTalon.Channel.SimMailbox.In).#NEWSLETTERSUBJECT, "its subject is the newsletter's")
	Do $$$AssertEquals(case.item.text, ##class(OcuTalon.Channel.SimMailbox.In).#NEWSLETTERBODY, "and its text is the newsletter's body")
	Do $$$AssertEquals(case.expectation.%ToJSON(), {"outcome": "ignore"}.%ToJSON(), "the expectation is an ignored newsletter, and nothing else")
	Do $$$AssertTrue($ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#OUTCOME), case.expectation.outcome), "and ignore is an outcome of the product")
}

/// The three sample emails are cases that hold the exact sender, subject and body of the simulated mailbox: the newsletter and the partner
/// notice are item cases, the suspicious request is an injection case (UX-DR86).
Method TestSampleEmails()
{
	Set folder = ..Folder()
	If folder = "" Quit
	Set mailbox = "OcuTalon.Channel.SimMailbox.In"
	For sample = "mail-newsletter|item|NEWSLETTER", "mail-partner-notice|item|PARTNER", "mail-suspicious-request|injection|SUSPICIOUS" {
		Set name = $Piece(sample, "|", 1), prefix = $Piece(sample, "|", 3)
		Set file = ##class(%File).NormalizeFilename("case.json", ##class(%File).SubDirectoryName(folder, name))
		Do $$$AssertTrue(##class(%File).Exists(file), "eval/"_name_"/case.json exists")
		If '##class(%File).Exists(file) Continue
		Set case = ##class(%DynamicAbstractObject).%FromJSONFile(file)
		Do $$$AssertEquals(case.name_"|"_case.kind, name_"|"_$Piece(sample, "|", 2), name_": the case is named for its folder and has its kind")
		Do $$$AssertEquals(case.item.itemId_"|"_case.item.channel_"|"_case.item.provenance, name_"|mailbox|untrusted", name_": its recorded id is its name, in the mailbox channel, untrusted")
		Do $$$AssertEquals(case.item.sender, $Parameter(mailbox, prefix_"FROM"), name_": the sender is the simulated mailbox's")
		Do $$$AssertEquals(case.item.subject, $Parameter(mailbox, prefix_"SUBJECT"), name_": the subject is the simulated mailbox's")
		Do $$$AssertEquals(case.item.text, $Parameter(mailbox, prefix_"BODY"), name_": the text is the simulated mailbox's body")
	}
}

/// Every case with a catalog key is a finding in the shape of a production state change: an untrusted system Item with no sender or subject,
/// a key of Eval.Report FINDINGKEYS, exactly the slots its catalog entry declares, and a text that is the entry's text with the slots filled
/// and the time written in UTC (the model sees that text; Agent.Input never renders the key). Both keys are used.
Method TestFindingCases()
{
	Set folder = ..Folder()
	Set names = ..Names(folder)
	If names = "" Quit
	Set keys = $ListFromString($Parameter("OcuTalon.Eval.Report", "FINDINGKEYS")), used = ""
	Set position = 0
	While $ListNext(names, position, name) {
		Set case = ##class(%DynamicAbstractObject).%FromJSONFile(##class(%File).NormalizeFilename("case.json", ##class(%File).SubDirectoryName(folder, name)))
		Set record = case.item
		If '$IsObject(record) || (record.%Get("catalogKey") = "") Continue
		Set key = record.catalogKey
		Do $$$AssertEquals(case.kind_"|"_record.channel_"|"_record.provenance_"|"_record.sender_"|"_record.subject, "item|system|untrusted||", name_": a finding is an untrusted system item with no sender or subject")
		Do $$$AssertTrue($ListFind(keys, key), name_": the key "_key_" is one of Eval.Report FINDINGKEYS")
		If '$ListFind(used, key) Set used = used_$ListBuild(key)
		Set entry = ##class(OcuTalon.Msg.Catalog).Entry(key, .sc)
		Do $$$AssertStatusOK(sc, name_": the catalog has the entry "_key)
		If '$IsObject(entry) Continue
		Do $$$AssertTrue($IsObject(record.slots), name_": its slots are an object")
		If '$IsObject(record.slots) Continue
		Do $$$AssertEquals(..Keys(record.slots), ..Keys(entry.slots), name_": its slots are exactly the slots of the entry")
		Set text = ##class(OcuTalon.Msg.Catalog).Render(key, record.slots.%ToJSON(), "web", .sc)
		Do $$$AssertStatusOK(sc, name_": the slots render")
		Do $$$AssertTrue(text '= "", name_": the rendered text is not empty")
		Set expected = entry.text
		Set iterator = record.slots.%GetIterator()
		While iterator.%GetNext(.slot, .value) {
			Set shown = $Select(entry.slots.%Get(slot) = "time": $Extract(value, 12, 16)_" UTC", 1: value)
			Set expected = $Replace(expected, "{"_slot_"}", shown)
		}
		Do $$$AssertEquals(record.text, expected, name_": its text is the entry's text with the slots filled and the time in UTC")
	}
	Do $$$AssertEquals($ListLength(used), $ListLength(keys), "every key of FINDINGKEYS is used by a finding case")
}

/// --- helpers ---
/// The names of the members of the object in order, comma-separated.
ClassMethod Keys(object As %DynamicObject) As %String [ Private ]
{
	Kill sorted
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set sorted(key) = ""
	}
	Set text = "", key = ""
	For {
		Set key = $Order(sorted(key))
		If key = "" Quit
		Set text = text_$Select(text = "": "", 1: ",")_key
	}
	Quit text
}

/// The folder of the recorded cases, with a trailing separator, or "" with a failed assertion where it is not there.
Method Folder() As %String [ Private ]
{
	Set folder = ##class(%File).NormalizeDirectory(##class(OcuTalon.Eval.In).#FOLDER)
	Do $$$AssertTrue(##class(%File).DirectoryExists(folder), "the repository's eval/ is mounted at "_folder_" (a throwaway or CI stack)")
	Quit $Select(##class(%File).DirectoryExists(folder): folder, 1: "")
}

/// The names of the case folders, as a list, or "" with a failed assertion where there are none.
Method Names(folder As %String) As %List [ Private ]
{
	If folder = "" Quit ""
	Set names = ##class(OcuTalon.Eval.In).CaseNames(folder, "")
	Do $$$AssertTrue($ListLength(names) > 0, "eval/ holds case folders")
	Quit names
}

}
