/// Tests of the bridge example's process and service (Story 13.1; AD-2, AD-6, FR-5). Nothing is started, sent or written: the tests
/// build items in memory and read what the example's own class methods make of them. The whole path through a running production is
/// proved by release/standalone-bridge.sh.
///   - TestRequestFor: the decide request of an item holds every field of AD-6, and Decide.Admit accepts it;
///   - TestSummaryOf: the summary is one line of at most 80 characters, from the subject or, with none, the first line of the body;
///   - TestRender: the rendered text keeps the subject, a blank line and the body, so a marker in the body reaches the model;
///   - TestCheck: an item with neither subject nor body is refused, and one with either is accepted;
///   - TestDecidedFor: the decision message copies the six fields.
Class OcuTalon.Test.Bridge.ExampleTriage Extends %UnitTest.TestCase
{

Parameter TRIAGE = "OcuTalon.BridgeExample.Triage";

/// The request has the fields of AD-6, the item's ItemId and Provenance, a code-written summary and the rendered text, and Decide admits it.
Method TestRequestFor()
{
	Set item = ..Item("Printer on fire", "The printer on floor 2 is on fire.", "user")
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = $ClassMethod(..#TRIAGE, "RequestFor", item)
	Do $$$AssertEquals($ClassName(request), "OcuTalon.Bridge.Msg.Request", "RequestFor builds a Request for Decide")
	Do $$$AssertEquals(request.Kind, "decide", "its Kind is decide")
	Do $$$AssertEquals(request.OwnerRef, "instance", "its OwnerRef is instance")
	Do $$$AssertEquals(request.Channel, "system", "its Channel is system")
	Do $$$AssertEquals(request.Provenance, "user", "its Provenance is the item's")
	Do $$$AssertEquals(request.ItemId, item.ItemId, "its ItemId is the item's")
	Do $$$AssertEquals(request.Summary, "Printer on fire", "its Summary is the code-written line")
	Do $$$AssertEquals(request.Input, $ClassMethod(..#TRIAGE, "Render", item), "its Input is the rendered text, never the item")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.Decide).Admit(request), "Decide admits the request")
	Set plain = ..Item("Plain", "Body")
	Set plain.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set plain.Provenance = ""
	Do $$$AssertEquals($ClassMethod(..#TRIAGE, "RequestFor", plain).Provenance, "untrusted", "an item with no Provenance is untrusted")
	Set default = ##class(OcuTalon.BridgeExample.Msg.Item).%New()
	Do $$$AssertEquals(default.Provenance, "untrusted", "and a new item is untrusted by default")
}

/// One line of at most 80 characters; the subject, or the first line of the body that is not blank.
Method TestSummaryOf()
{
	Set long = "Alpha"_$Char(10)_"beta"_$Char(9)_"gamma "_$Translate($Justify("", 90), " ", "x")
	Set summary = $ClassMethod(..#TRIAGE, "SummaryOf", ..Item(long, "Body"))
	Do $$$AssertTrue($Length(summary) <= 80, "a long subject is cut to 80 characters or fewer: "_$Length(summary))
	Do $$$AssertEquals($Extract(summary, 1, 17), "Alpha beta gamma ", "its line break and tab become spaces")
	Do $$$AssertEquals($ZStrip(summary, "*C"), summary, "and it holds no control character")
	Do $$$AssertEquals($ClassMethod(..#TRIAGE, "SummaryOf", ..Item("Short subject", "Body")), "Short subject", "a short subject is kept")
	Set body = $Char(13, 10)_"   "_$Char(10)_"  First real line"_$Char(13, 10)_"Second line"
	Do $$$AssertEquals($ClassMethod(..#TRIAGE, "SummaryOf", ..Item("", body)), "First real line", "with an empty subject the first non-blank line of the body is used")
	Do $$$AssertEquals($ClassMethod(..#TRIAGE, "SummaryOf", ..Item($Char(9)_" ", body)), "First real line", "and so it is with a subject of white space")
	Do $$$AssertEquals($ClassMethod(..#TRIAGE, "SummaryOf", ..Item("", $Justify("", 450)_"Late text")), "Late text", "a line whose text follows more than 400 leading spaces still gives its text")
}

/// The rendered text: "Subject: ", the subject, a blank line and the body; a marker in the body is kept as written.
Method TestRender()
{
	Set item = ..Item("Hello", "Line one"_$Char(10)_"[[mock:bridge-example-digest]]")
	Set text = $ClassMethod(..#TRIAGE, "Render", item)
	Do $$$AssertEquals(text, "Subject: Hello"_$Char(10, 10)_"Line one"_$Char(10)_"[[mock:bridge-example-digest]]", "the text is the subject line, a blank line and the body")
	Do $$$AssertTrue(text [ "[[mock:bridge-example-digest]]", "a marker of the body is kept")
}

/// An item with neither subject nor body is refused with an error that names both; either one alone is enough.
Method TestCheck()
{
	Set class = "OcuTalon.BridgeExample.ItemIn"
	Set sc = $ClassMethod(class, "Check", ..Item("", ""))
	Do $$$AssertStatusNotOK(sc, "an empty item is refused")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ "Subject") && (text [ "Body"), "and the error names Subject and Body")
	Do $$$AssertStatusNotOK($ClassMethod(class, "Check", ..Item($Char(9, 10, 13)_" ", $Char(1)_"  ")), "so is an item of white space and control characters")
	Do $$$AssertStatusOK($ClassMethod(class, "Check", ..Item("Only a subject", "")), "an item with a subject only is accepted")
	Do $$$AssertStatusOK($ClassMethod(class, "Check", ..Item("", "Only a body")), "an item with a body only is accepted")
	Set sc = $ClassMethod(class, "Send", "", "", , .itemId)
	Do $$$AssertStatusNotOK(sc, "Send refuses an empty item before it touches a production")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ "Subject") && (text [ "Body"), "and the error is Check's, which names Subject and Body")
	Do $$$AssertEquals(itemId, "", "and gives no ItemId")
}

/// The decision message copies the item's ItemId, the summary and the four decision fields.
Method TestDecidedFor()
{
	Set item = ..Item("Subject of the item", "Body")
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set response = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
	Set response.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set response.Outcome = "tellnow"
	Set response.Fallback = 1
	Set response.FallbackReason = "timeout"
	Set decided = $ClassMethod(..#TRIAGE, "DecidedFor", item, response)
	Do $$$AssertEquals($ClassName(decided), "OcuTalon.BridgeExample.Msg.Decided", "DecidedFor builds a Decided")
	Do $$$AssertEquals(decided.ItemId, item.ItemId, "it copies the ItemId")
	Do $$$AssertEquals(decided.Summary, "Subject of the item", "it holds the summary of the item")
	Do $$$AssertEquals(decided.DecisionRef, response.DecisionRef, "it copies the DecisionRef")
	Do $$$AssertEquals(decided.Outcome, "tellnow", "it copies the Outcome")
	Do $$$AssertEquals(decided.Fallback, 1, "it copies Fallback")
	Do $$$AssertEquals(decided.FallbackReason, "timeout", "and the FallbackReason")
}

/// --- helpers ---
/// An item in memory.
ClassMethod Item(subject As %String, body As %String, provenance As %String = "untrusted") As OcuTalon.BridgeExample.Msg.Item [ Private ]
{
	Set item = ##class(OcuTalon.BridgeExample.Msg.Item).%New()
	Set item.Subject = subject
	Set item.Body = body
	Set item.Provenance = provenance
	Quit item
}

}
