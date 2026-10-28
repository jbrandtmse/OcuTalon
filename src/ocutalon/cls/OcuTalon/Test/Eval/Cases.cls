/// Tests of the recorded cases of eval/ against EvalIn (Story 9.1; AD-22, UX-DR86). WARM-SAFE: they read the repository's eval/
/// folder, which every throwaway stack mounts read-only at EvalIn's FOLDER, and hand each case to a shadow instance of
/// OcuTalon.Test.Eval.ZzIn, the double of EvalIn whose Dispatch sends nothing and records the Item. They start no production and send
/// no message; where eval/ is not mounted (a dev slot) they fail with the reason.
///   - TestRecordedCases: every case of eval/ (a subfolder that holds a case.json) is named for its folder; every case of a kind that holds a
///     recorded Item (item or injection) is sent by EvalIn as the Item that the record says, so a run over the whole folder skips no
///     such case; a case of any other kind (the incident case) is skipped with its kind in the reason;
///   - TestNewsletterCase: eval/mail-newsletter is the item case of Task 5: kind item, not held out, recorded id mail-newsletter,
///     provenance untrusted, channel mailbox, the exact sender, subject and body of the simulated mailbox's newsletter (UX-DR86), and the
///     expectation {"outcome": "ignore"}, an outcome of the product's Msg.Enum.
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

/// --- helpers ---
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
