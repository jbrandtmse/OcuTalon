/// Tests of the documents half of the reply filter (Story 19.4; AD-28, AD-31; DW-720; the Contest Planner's ruling Q1). A reply that carries citations never says
/// "None of your documents cover that." (UX-DR144), and a reply that carries none may say it.
///   - TestSentence: the sentence is pinned word for word;
///   - TestStripWithCitations (Q1 a): Docs.Reply.Apply removes every occurrence of the sentence from a reply whose HostData holds a non-empty citations array, with
///     ReplyGuard's matching rule (case, word edges, the punctuation after it, spaces collapsed, an emptied line dropped);
///   - TestKeepWithoutCitations (Q1 b): a reply that is only the sentence, and every reply whose HostData is empty, not JSON, not an object or without a non-empty
///     citations array, is returned as it is;
///   - TestGuardChain: ReplyGuard.Filter applies its own phrases, then the documents rule, and still fails closed; with one argument it behaves as before;
///   - TestConclude (Q1 a to c): through Decide.Conclude with ReplyGuard as the reply filter, the text that leaves Decide never holds the sentence next to
///     citations, the citations stay in the answer's HostData untouched (Q1 c), a reply that is only the sentence next to citations takes Decide's invalid
///     path (a fallback with no text), and a reply with no citations shows the sentence unchanged.
/// OnAfterOneTest deletes the Decision rows of the test's ItemIds.
Class OcuTalon.Test.Docs.Reply Extends %UnitTest.TestCase
{

Parameter CLASS = "OcuTalon.Docs.Reply";

Parameter GUARD = "OcuTalon.Checks.ReplyGuard";

Parameter NONE = "None of your documents cover that.";

/// The ItemIds of the turns that the test concluded.
Property ItemIds As %List;

Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Quit $$$OK
}

/// The HostData of a reply with one citation.
ClassMethod Cited() As %String [ Private ]
{
	Quit "{""citations"":[{""documentRef"":""zzdoc1"",""document"":""Results runbook"",""section"":""Rotating the certificate"",""passage"":""Stop the sender."",""chunkIndex"":1}]}"
}

Method TestSentence()
{
	Do $$$AssertEquals($Parameter(..#CLASS, "NONE"), ..#NONE, "the sentence is None of your documents cover that., word for word")
}

Method TestStripWithCitations()
{
	Set lf = $Char(10)
	Set cited = ..Cited()
	Set cases = $ListBuild($ListBuild("Stop the sender. " _ ..#NONE, "Stop the sender."), $ListBuild("Line one." _ lf _ ..#NONE _ lf _ "Line three.", "Line one." _ lf _ "Line three."), $ListBuild("none of YOUR documents cover that!", ""), $ListBuild("Steps  here.  " _ ..#NONE _ "  More.", "Steps here. More."), $ListBuild(..#NONE _ " Ok. " _ ..#NONE, "Ok."), $ListBuild(..#NONE, ""), $ListBuild("None of your documents cover that", ""), $ListBuild("x" _ ..#NONE, "x" _ ..#NONE), $ListBuild("None of your documents cover thats.", "None of your documents cover thats."), $ListBuild("Plain text with no sentence.", "Plain text with no sentence."), $ListBuild("None of your documents cover this.", "None of your documents cover this."), $ListBuild("None  of" _ lf _ "your documents cover that.", "None  of" _ lf _ "your documents cover that."), $ListBuild("Two lines." _ lf _ "None of your" _ $Char(9) _ "documents cover that." _ lf, "Two lines." _ lf))
	Set position = 0
	While $ListNext(cases, position, case) {
		Do $$$AssertEquals($ClassMethod(..#CLASS, "Apply", $List(case, 1), cited), $List(case, 2), "with citations '" _ $Translate($List(case, 1), lf _ $Char(9), "/ ") _ "' gives '" _ $Translate($List(case, 2), lf, "/") _ "'")
	}
	Do $$$AssertEquals($ClassMethod(..#CLASS, "Apply", "Steps. " _ ..#NONE, "{""memories"":[],""citations"":[{""documentRef"":""zz""}]}"), "Steps.", "citations among other members of HostData count")
}

Method TestKeepWithoutCitations()
{
	Set text = "Stop the sender. " _ ..#NONE
	For hostData = "", "{}", "{""citations"":[]}", "not json", "{""memories"":[{""memoryRef"":""zz""}]}", "[1]", "{""citations"":""x""}", "{""citations"":{""a"":1}}", "{""citations"":null}", "  ", "{""citations"":[" {
		Do $$$AssertEquals($ClassMethod(..#CLASS, "Apply", text, hostData), text, "HostData '" _ hostData _ "' leaves the text alone")
		Do $$$AssertEquals($ClassMethod(..#CLASS, "Apply", ..#NONE, hostData), ..#NONE, "and a reply that is only the sentence is shown unchanged")
	}
	Do $$$AssertEquals($ClassMethod(..#CLASS, "Apply", ..#NONE), ..#NONE, "also with no second argument")
	Do $$$AssertEquals($ClassMethod(..#CLASS, "HasCitations", ..Cited()), 1, "control: the citations of Cited are seen")
}

Method TestGuardChain()
{
	Set cited = ..Cited()
	Set guard = ..#GUARD
	Do $$$AssertEquals($ClassMethod(guard, "Filter", "Fine. " _ ..#NONE _ " All good.", cited), "Fine.", "the guard removes its own banned phrase and the documents sentence")
	Do $$$AssertEquals($ClassMethod(guard, "Filter", "Fine. " _ ..#NONE _ " All good."), "Fine. " _ ..#NONE, "with one argument it removes only its own phrases, as before")
	Do $$$AssertEquals($ClassMethod(guard, "Filter", "Fine. " _ ..#NONE _ " All good.", ""), "Fine. " _ ..#NONE, "and so with an empty second argument")
	Do $$$AssertEquals($ClassMethod(guard, "Filter", ..#NONE, cited), "", "a reply that is only the sentence, next to citations, comes back empty (Decide's invalid path)")
	Do $$$AssertEquals($ClassMethod(guard, "Filter", ..#NONE, "{""memories"":[]}"), ..#NONE, "and next to no citation it is unchanged")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Test.Checks.BrokenGuard", "Filter", "Fine.", cited), "", "a guard that fails inside still fails closed with the second argument")
}

/// Concludes a turn of the owner with the reply text and HostData through ReplyGuard; response is Decide's answer.
Method Conclude(text As %String, hostData As %String, Output response As %Persistent) As %Status [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = "instance"
	Set request.Summary = "Test " _ request.ItemId
	Set request.Input = "How do I rotate the Results certificate?"
	Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = text
	Set reply.HostData = hostData
	Quit ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ##class(OcuTalon.Bridge.Ids).NewRef(), reply, "OcuTalon.Bridge.Msg.DecisionPayload", ..#GUARD, "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
}

Method TestConclude()
{
	Set cited = ..Cited()
	Set sc = ..Conclude("Stop the sender, install the certificate and send a test result. " _ ..#NONE, cited, .response)
	Do $$$AssertStatusOK(sc, "a reply that cites a document and says the sentence is recorded")
	Do $$$AssertEquals(response.Text, "Stop the sender, install the certificate and send a test result.", "the text that leaves Decide has no sentence")
	Do $$$AssertEquals(response.HostData, cited, "and the citations stay, byte for byte (Q1 c)")
	Do $$$AssertEquals(response.Fallback, 0, "it is no fallback")
	Set sc = ..Conclude(..#NONE, cited, .response)
	Do $$$AssertStatusOK(sc, "a reply that is only the sentence next to citations is recorded")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback _ "|" _ response.FallbackReason _ "|" _ response.Text, 1: "none"), "1|invalid|", "as a fallback with the reason invalid and no text")
	Set sc = ..Conclude(..#NONE, "", .response)
	Do $$$AssertStatusOK(sc, "a reply that is only the sentence and cites nothing is recorded")
	Do $$$AssertEquals(response.Text _ "|" _ response.Fallback, ..#NONE _ "|0", "and shows the sentence unchanged (Q1 b)")
	Set sc = ..Conclude("Stop the sender. " _ ..#NONE, "{""memories"":[{""memoryRef"":""zz""}]}", .response)
	Do $$$AssertEquals(response.Text, "Stop the sender. " _ ..#NONE, "citations are what counts: a recall's memories do not strip the sentence")
}

}
