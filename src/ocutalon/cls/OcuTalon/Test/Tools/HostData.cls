/// Tests of OcuTalon.Tools.HostData, the one place that puts a member into the bridge context's HostData (Story 19.3, QA; AD-31; the home of the merge rule that
/// check_status had, and of the members memories and, from Story 19.4, citations). They need no production, no model and no database row: each test begins a
/// context of its own in this process and ends it, so they run on a slot as well as in a throwaway.
///   - TestPutKeepsTheOtherMembers: a JSON object HostData keeps its other members when one is put, a member put again is replaced in its own place, and the
///     members are dynamic values of any kind (an array, an object, a string);
///   - TestPutOverAnythingElse: an empty HostData, text that is not JSON, JSON that is not an object (an array, a number, a string) and an object that is the
///     literal null become an object that holds the member alone, with no error;
///   - TestGet: the member as the value that was put, "" for a member that is not there, for an empty HostData and for a HostData that is not a JSON object, and
///     Get changes nothing;
///   - TestRemove: Remove takes one member out and keeps the others in their places, and a HostData without the member, or one that is not a JSON object,
///     is left as it is;
///   - TestNoContext: with no context Put is an error status and Get is "", and neither creates a context.
Class OcuTalon.Test.Tools.HostData Extends %UnitTest.TestCase
{

Parameter CLASS = "OcuTalon.Tools.HostData";

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Quit $$$OK
}

/// Begins a context for a user turn of a made-up owner, with the HostData as given.
Method Begin(hostData As %String = "") [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.Channel = "system"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, ""), "a context begins")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Put("HostData", hostData), "with the HostData '" _ hostData _ "'")
}

/// The HostData of the context.
ClassMethod Text() As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Context).Current().HostData
}

Method TestPutKeepsTheOtherMembers()
{
	Do ..Begin("")
	Do $$$AssertStatusOK($ClassMethod(..#CLASS, "Put", "checks", [{"result": "ok"}]), "a member is put into an empty HostData")
	Do $$$AssertEquals(..Text(), "{""checks"":[{""result"":""ok""}]}", "which holds it alone")
	Do $$$AssertStatusOK($ClassMethod(..#CLASS, "Put", "memories", [{"memoryRef": "zz1"}]), "a second member is put")
	Do $$$AssertEquals(..Text(), "{""checks"":[{""result"":""ok""}],""memories"":[{""memoryRef"":""zz1""}]}", "and the first stays, in its place")
	Do $$$AssertStatusOK($ClassMethod(..#CLASS, "Put", "checks", []), "the first is put again")
	Do $$$AssertEquals(..Text(), "{""checks"":[],""memories"":[{""memoryRef"":""zz1""}]}", "and is replaced in its own place, with the other member as it was")
	Do $$$AssertStatusOK($ClassMethod(..#CLASS, "Put", "note", "plain text"), "a string is a member too")
	Do $$$AssertStatusOK($ClassMethod(..#CLASS, "Put", "extra", {"a": 1}), "and so is an object")
	Do $$$AssertEquals(..Text(), "{""checks"":[],""memories"":[{""memoryRef"":""zz1""}],""note"":""plain text"",""extra"":{""a"":1}}", "all four members are there")
}

Method TestPutOverAnythingElse()
{
	For text = "not json at all", "[1,2]", "7", """a string""", "null", "{""broken"":", "  " {
		Do ##class(OcuTalon.Bridge.Context).End()
		Do ..Begin(text)
		Do $$$AssertStatusOK($ClassMethod(..#CLASS, "Put", "memories", [1]), "a member is put over '" _ text _ "'")
		Do $$$AssertEquals(..Text(), "{""memories"":[1]}", "and the HostData becomes an object that holds the member alone")
	}
}

Method TestGet()
{
	Do ..Begin("")
	Do $$$AssertEquals($ClassMethod(..#CLASS, "Get", "memories"), "", "an empty HostData has no member")
	Do $ClassMethod(..#CLASS, "Put", "memories", [{"memoryRef": "zz1"}, {"memoryRef": "zz2"}])
	Do $ClassMethod(..#CLASS, "Put", "checks", [{"result": "ok"}])
	Set before = ..Text()
	Set held = $ClassMethod(..#CLASS, "Get", "memories")
	Do $$$AssertTrue($IsObject(held) && held.%IsA("%Library.DynamicArray"), "a member that was put is given back as the dynamic array")
	Do $$$AssertEquals($Select($IsObject(held): held.%ToJSON(), 1: "none"), "[{""memoryRef"":""zz1""},{""memoryRef"":""zz2""}]", "with its own values, not the other member's")
	Set checks = $ClassMethod(..#CLASS, "Get", "checks")
	Do $$$AssertEquals($Select($IsObject(checks): checks.%ToJSON(), 1: "none"), "[{""result"":""ok""}]", "the other member is given back as it is")
	Do $$$AssertEquals($ClassMethod(..#CLASS, "Get", "citations"), "", "a member that is not there is empty")
	Do $$$AssertEquals(..Text(), before, "and Get changes nothing")
	For text = "not json at all", "[1,2]", "7", """a string""" {
		Do ##class(OcuTalon.Bridge.Context).End()
		Do ..Begin(text)
		Do $$$AssertEquals($ClassMethod(..#CLASS, "Get", "memories"), "", "a HostData of '" _ text _ "' has no member")
		Do $$$AssertEquals(..Text(), text, "and Get leaves it as it is")
	}
}

Method TestRemove()
{
	Do ..Begin("")
	Do $ClassMethod(..#CLASS, "Put", "checks", [{"result": "ok"}])
	Do $ClassMethod(..#CLASS, "Put", "memories", [{"memoryRef": "zz1"}])
	Do $ClassMethod(..#CLASS, "Put", "note", "plain text")
	Do $$$AssertStatusOK($ClassMethod(..#CLASS, "Remove", "memories"), "a member is removed")
	Do $$$AssertEquals(..Text(), "{""checks"":[{""result"":""ok""}],""note"":""plain text""}", "and the others stay, in their places")
	Do $$$AssertStatusOK($ClassMethod(..#CLASS, "Remove", "memories"), "a member that is not there is removed with no error")
	Do $$$AssertEquals(..Text(), "{""checks"":[{""result"":""ok""}],""note"":""plain text""}", "and HostData is as it was")
	For text = "", "not json at all", "[1,2]" {
		Do ##class(OcuTalon.Bridge.Context).End()
		Do ..Begin(text)
		Do $$$AssertStatusOK($ClassMethod(..#CLASS, "Remove", "memories"), "Remove over '" _ text _ "' is no error")
		Do $$$AssertEquals(..Text(), text, "and leaves it as it is")
	}
}

Method TestNoContext()
{
	Do $$$AssertNotTrue(##class(OcuTalon.Bridge.Context).Active(), "this process has no context")
	Do $$$AssertTrue($SYSTEM.Status.IsError($ClassMethod(..#CLASS, "Put", "memories", [1])), "Put is an error status")
	Do $$$AssertEquals($ClassMethod(..#CLASS, "Get", "memories"), "", "Get gives an empty value")
	Do $$$AssertNotTrue(##class(OcuTalon.Bridge.Context).Active(), "and neither made a context")
}

}
