/// Tests of EvalIn's handling of one case (Story 9.1; AD-14, AD-22, AD-26, AD-30). WARM-SAFE: they call OnProcessInput on a shadow
/// instance of OcuTalon.Test.Eval.ZzIn, a double of EvalIn whose Dispatch sends nothing and records the Item it was given, so they start
/// no production and send no message. The case folders are written under the instance's temp directory and removed afterwards. The
/// run Refs and case names start with zz.
///   - TestSendsItem: a case becomes an Item with a new ItemId, SourceItemId set to the recorded item.itemId, owner eval, provenance
///     untrusted and the record's channel, sender, subject, text, catalog key and slots (an object as JSON text); the service's
///     SuperSession is the run's Ref; the case's row is open (state sent) when the Item is dispatched; a recorded provenance of
///     untrusted, or none, is accepted, and the kinds item and injection are sent;
///   - TestRefuses: a folder with no case.json, a case.json that is not a JSON object, a kind that is neither item nor injection, no
///     item.itemId and a recorded provenance other than untrusted are each refused with their reason, logged as a warning, with no row
///     and nothing dispatched;
///   - TestSendFails: a send that fails or throws deletes the case's row and returns the error text as the reason, and the case can be sent again;
///   - TestInputRefused: an input that is not a folder from Start, and a service with no run, are refused;
///   - TestCaseNames: a comma list is trimmed and each name kept once, in order, and no list gives the subfolders that hold a case.json,
///     in name order.
Class OcuTalon.Test.Eval.In Extends %UnitTest.TestCase
{

/// The double of EvalIn.
Parameter DOUBLE = "OcuTalon.Test.Eval.ZzIn";

/// The folder that holds the cases of the tests, with a trailing separator.
Property Folder As %String(MAXLEN = 500);

/// The Ref of the run of the test.
Property Run As %String(MAXLEN = 22);

/// The newest row of the event log when the test began.
Property Mark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set ..Folder = ##class(%File).NormalizeDirectory("zzevalin"_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 12), ##class(%File).NormalizeDirectory("Temp", $SYSTEM.Util.ManagerDirectory()))
	Do ##class(%File).CreateDirectoryChain(..Folder)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("EvalIn")
	Do ##class(%File).RemoveDirectoryTree(..Folder)
	Quit $$$OK
}

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

/// A case becomes the Item the contract says, with its row open at the moment of the send.
Method TestSendsItem()
{
	Set service = ..Service()
	If '$IsObject(service) Quit
	Do ..WriteCase("zz-full", {"name": "zz-full", "kind": "injection", "item": {"itemId": "zz-full-id", "channel": "mailbox", "provenance": "untrusted", "sender": "Sender <sender@example.com>", "subject": "A subject", "text": "The body", "catalogKey": "watch.example", "slots": {"a": 1, "b": "two"}}}.%ToJSON())
	Do $$$AssertEquals(..Process(service, "zz-full"), "", "an injection case with all the fields is sent")
	Do $$$AssertEquals(..Seen(), 1, "one Item was dispatched")
	Set seen = ..SeenAt(1)
	Do $$$AssertEquals($Length($List(seen, 1)), 22, "its ItemId is new and 22 characters")
	Do $$$AssertTrue($List(seen, 1) '= "zz-full-id", "and is not the recorded id")
	Do $$$AssertEquals($List(seen, 2)_"|"_$List(seen, 3)_"|"_$List(seen, 5), "zz-full-id|eval|untrusted", "SourceItemId is the recorded id, the owner is eval, the provenance untrusted")
	Do $$$AssertEquals($List(seen, 4)_"|"_$List(seen, 6)_"|"_$List(seen, 7)_"|"_$List(seen, 8), "mailbox|Sender <sender@example.com>|A subject|The body", "the channel, sender, subject and text are the record's")
	Do $$$AssertEquals($List(seen, 9)_"|"_$List(seen, 10), "watch.example|"_{"a": 1, "b": "two"}.%ToJSON(), "the catalog key is the record's and the slots are the object as JSON text")
	Do $$$AssertEquals($List(seen, 11), ..Run, "the SuperSession of the service is the run's Ref")
	Do $$$AssertEquals($List(seen, 12), 1, "the case's row was open when the Item was dispatched")
	Set row = ##class(OcuTalon.Eval.Data.CaseResult).RunCaseIndexOpen(..Run, "zz-full")
	Do $$$AssertTrue($IsObject(row), "the row stays")
	If $IsObject(row) Do $$$AssertEquals(row.State_"|"_row.SourceItemId_"|"_row.ItemId, "sent|zz-full-id|"_$List(seen, 1), "in state sent, with the Item's ids")

	Set slotsText = "{""x"": 1}"
	Do ..WriteCase("zz-slots", {"kind": "item", "item": {"itemId": "zz-slots-id", "slots": (slotsText)}}.%ToJSON())
	Do $$$AssertEquals(..Process(service, "zz-slots"), "", "an item case with no provenance and slots as text is sent")
	Set seen = ..SeenAt(2)
	Do $$$AssertEquals($List(seen, 5)_"|"_$List(seen, 10)_"|"_$List(seen, 4), "untrusted|{""x"": 1}|", "the provenance is untrusted whatever was recorded, the slots text is kept, and the fields not recorded are empty")
	Do $$$AssertTrue($List(seen, 1) '= $List(..SeenAt(1), 1), "the second case has an ItemId of its own")
}

/// Each way a case is not sent gives its reason, a warning, no row and no send.
Method TestRefuses()
{
	Set service = ..Service()
	If '$IsObject(service) Quit
	Set in = "OcuTalon.Eval.In"
	Do ##class(%File).CreateDirectoryChain(##class(%File).SubDirectoryName(..Folder, "zz-nofile"))
	Do ..WriteCase("zz-notjson", "this is not json")
	Do ..WriteCase("zz-array", "[1, 2]")
	Do ..WriteCase("zz-nokind", {"item": {"itemId": "x"}}.%ToJSON())
	Do ..WriteCase("zz-incident", {"kind": "incident", "item": {"itemId": "x"}}.%ToJSON())
	Do ..WriteCase("zz-turn", {"kind": "turn", "item": {"itemId": "x"}}.%ToJSON())
	Do ..WriteCase("zz-noitem", {"kind": "item"}.%ToJSON())
	Do ..WriteCase("zz-itemtext", {"kind": "item", "item": "x"}.%ToJSON())
	Do ..WriteCase("zz-emptyid", {"kind": "item", "item": {"itemId": ""}}.%ToJSON())
	Do ..WriteCase("zz-user", {"kind": "item", "item": {"itemId": "x", "provenance": "user"}}.%ToJSON())
	Do ..WriteCase("zz-tainted", {"kind": "injection", "item": {"itemId": "x", "provenance": "tainted"}}.%ToJSON())
	Set cases = ""
	For entry = $ListBuild("zz-nofile", $Parameter(in, "REASONNOCASEFILE")), $ListBuild("zz-notjson", $Parameter(in, "REASONNOTJSON")), $ListBuild("zz-array", $Parameter(in, "REASONNOTJSON")), $ListBuild("zz-nokind", ..KindReason("")), $ListBuild("zz-incident", ..KindReason("incident")), $ListBuild("zz-turn", ..KindReason("turn")) {
		Set cases = cases_$ListBuild(entry)
	}
	For entry = $ListBuild("zz-noitem", $Parameter(in, "REASONNOITEMID")), $ListBuild("zz-itemtext", $Parameter(in, "REASONNOITEMID")), $ListBuild("zz-emptyid", $Parameter(in, "REASONNOITEMID")), $ListBuild("zz-user", ..ProvenanceReason("user")), $ListBuild("zz-tainted", ..ProvenanceReason("tainted")) {
		Set cases = cases_$ListBuild(entry)
	}
	Set position = 0
	While $ListNext(cases, position, case) {
		Do $$$AssertEquals(..Process(service, $List(case, 1)), $List(case, 2), $List(case, 1)_": the reason")
	}
	Do $$$AssertEquals(..Seen(), 0, "nothing was dispatched")
	Do $$$AssertEquals(..Rows(), 0, "and no row was made")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..Mark, .text, "OnProcessInput", $Parameter(in, "LOGSKIPPED")), $ListLength(cases), "each case was logged as a warning")
	Do $$$AssertTrue(text [ "zz-tainted", "naming the case: "_text)
}

/// A send that fails or throws deletes the case's row and returns the error text as the reason; the case can then be sent.
Method TestSendFails()
{
	Set service = ..Service()
	If '$IsObject(service) Quit
	Do ..WriteCase("zz-full", {"kind": "item", "item": {"itemId": "zz-full-id", "text": "The body"}}.%ToJSON())
	Set ^OcuTalonTest("EvalIn", "fail") = "the target is not there"
	Set reason = ..Process(service, "zz-full")
	Do $$$AssertTrue(reason [ "the target is not there", "the reason is the error text: "_reason)
	Do $$$AssertEquals(..Seen(), 1, "the send was tried once")
	Do $$$AssertEquals($List(..SeenAt(1), 12), 1, "with the row open")
	Do $$$AssertEquals(..Rows(), 0, "and the row is deleted")
	Kill ^OcuTalonTest("EvalIn", "fail")
	Set ^OcuTalonTest("EvalIn", "throw") = "the send threw"
	Set reason = ..Process(service, "zz-full")
	Do $$$AssertTrue(reason [ "the send threw", "a send that throws gives the exception's text as the reason: "_reason)
	Do $$$AssertEquals(..Seen(), 2, "the send was tried again")
	Do $$$AssertEquals($List(..SeenAt(2), 12), 1, "with the row open")
	Do $$$AssertEquals(..Rows(), 0, "and the row is deleted")
	Kill ^OcuTalonTest("EvalIn", "throw")
	Do $$$AssertEquals(..Process(service, "zz-full"), "", "the case is sent when the send works")
	Do $$$AssertEquals(..Rows(), 1, "and has its row")
}

/// An input that is not a folder from Start, and a service with no run, are refused with the input reason.
Method TestInputRefused()
{
	Set service = ..Service()
	If '$IsObject(service) Quit
	Set reason = ##class(OcuTalon.Eval.In).#REASONINPUT
	Do $$$AssertStatusOK(service.OnProcessInput(##class(Ens.StringRequest).%New("x"), .output), "OnProcessInput answers OK")
	Do $$$AssertEquals(output.StringValue, reason, "an input that is not a string container is refused")
	Do ..WriteCase("zz-full", {"kind": "item", "item": {"itemId": "zz-full-id"}}.%ToJSON())
	Set service.RunRef = ""
	Do $$$AssertStatusOK(service.OnProcessInput(##class(Ens.StringContainer).%New(##class(%File).SubDirectoryName(..Folder, "zz-full")), .output), "OnProcessInput answers OK")
	Do $$$AssertEquals(output.StringValue, reason, "a service with no run is refused")
	Do $$$AssertEquals(..Seen()_"|"_..Rows(), "0|0", "nothing was dispatched and no row was made")
}

/// The case names of a list, and of a folder.
Method TestCaseNames()
{
	Set in = "OcuTalon.Eval.In"
	Set list = $ClassMethod(in, "CaseNames", ..Folder, " zz-b , zz-a,zz-b,, zz-c ")
	Do $$$AssertEquals($ListToString(list, "|"), "zz-b|zz-a|zz-c", "a list is trimmed and each name kept once, in the order given")
	Set listed = ##class(%File).SubDirectoryName(..Folder, "listed")
	For name = "zz-b", "zz-a", "zz-nofile", "zz-c" {
		Set directory = ##class(%File).SubDirectoryName(listed, name)
		Do ##class(%File).CreateDirectoryChain(directory)
		If name '= "zz-nofile" Do ..WriteFile(directory, "{}")
	}
	Do ..WriteFile(listed, "{}")
	Set list = $ClassMethod(in, "CaseNames", listed, "")
	Do $$$AssertEquals($ListToString(list, "|"), "zz-a|zz-b|zz-c", "no list gives the subfolders that hold a case.json, in name order, and not a folder with none or a file")
	Do $$$AssertEquals($ListLength($ClassMethod(in, "CaseNames", ..Folder_"nothing-here/", "")), 0, "a folder that is not there has no cases")
}

/// --- helpers ---
/// A shadow instance of the double, for the run of the test.
Method Service() As OcuTalon.Test.Eval.ZzIn [ Private ]
{
	Set service = ##class(Ens.Host).GetShadowInstance("class||"_..#DOUBLE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the EvalIn double is made")
	If '$IsObject(service) Quit ""
	Set service.RunRef = ..Run
	Quit service
}

/// Hands the case's folder to the service; the reason it was not sent, or "".
Method Process(service As OcuTalon.Test.Eval.ZzIn, name As %String) As %String [ Private ]
{
	Kill output
	Set input = ##class(Ens.StringContainer).%New(##class(%File).SubDirectoryName(..Folder, name))
	Do $$$AssertStatusOK(service.OnProcessInput(input, .output), name_": OnProcessInput answers OK")
	Quit output.StringValue
}

/// Writes the case.json of a case folder.
Method WriteCase(name As %String, text As %String) [ Private ]
{
	Set directory = ##class(%File).SubDirectoryName(..Folder, name)
	Do ##class(%File).CreateDirectoryChain(directory)
	Do ..WriteFile(directory, text)
}

/// Writes the case.json of a folder.
Method WriteFile(directory As %String, text As %String) [ Private ]
{
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set stream.Filename = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.In).#CASEFILE, directory)
	Do stream.Write(text)
	Do $$$AssertStatusOK(stream.%Save(), "the case file is written")
}

/// How many Items the double was given.
ClassMethod Seen() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("EvalIn", "seen"))
}

/// The nth Item the double was given, as a list: ItemId, SourceItemId, SessionRef, Channel, Provenance, Sender, Subject, Text, CatalogKey,
/// Slots, the service's SuperSession and 1 when the case's row was open.
ClassMethod SeenAt(n As %Integer) As %List [ Private ]
{
	Quit $Get(^OcuTalonTest("EvalIn", "seen", n))
}

/// The number of case rows of the run.
Method Rows() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Eval_Data.CaseResult WHERE RunRef = ?", ..Run)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// EvalIn's reason for a kind that holds no recorded Item.
ClassMethod KindReason(kind As %String) As %String [ Private ]
{
	Quit $Replace($Replace($Parameter("OcuTalon.Eval.In", "REASONKIND"), "{kind}", kind), "{kinds}", $Replace($Parameter("OcuTalon.Eval.In", "KINDS"), ",", " and "))
}

/// EvalIn's reason for a recorded provenance other than untrusted.
ClassMethod ProvenanceReason(provenance As %String) As %String [ Private ]
{
	Quit $Replace($Parameter("OcuTalon.Eval.In", "REASONPROVENANCE"), "{provenance}", provenance)
}

}
