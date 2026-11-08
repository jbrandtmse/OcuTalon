/// Tests of OcuTalon.Bridge.Citations (Story 19.4; AD-10, AD-31; Conventions "Citations and memories"; DW-720). Safe on a slot: it needs only a bridge context
/// of the test process, no production and no table. Collect is what the step audit policy calls for every executed tool call.
///   - TestFloor: a passage is cited when its score is at or above CITEFLOOR (0.4) and not below it, in the same result;
///   - TestEntries: an entry is {documentRef, document, section, passage, chunkIndex} from the item's text and metadata, in the order of the results;
///   - TestDistinct: a passage (documentRef, chunkIndex) is cited once across the searches of a turn, while the same chunk of another document, or another
///     chunk of the same one, is another passage;
///   - TestCap: there are at most MAXCITATIONS entries, the first ones;
///   - TestMemberAbsent: when nothing clears the floor there is no citations member, and the other members of HostData stay;
///   - TestOtherCallsIgnored: only the documents call of the knowledge base counts: another tool, the same name with an origin_class and a call with no name
///     cite nothing and count no characters;
///   - TestCharsCounted: the characters of every documents result, cited or not, are added to the context's ToolResultChars;
///   - TestMalformed: a result that is not JSON of the knowledge base's shape, and an item without a score, a source or a metadata object, cite nothing and
///     throw nothing, and a missing context is no error.
Class OcuTalon.Test.Bridge.Citations Extends %UnitTest.TestCase
{

Parameter CLASS = "OcuTalon.Bridge.Citations";

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

/// Starts the context of a user's turn.
Method Begin() [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = "instance"
	Set request.TraceRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.Channel = "system"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request), "a context begins")
}

/// One result item of the knowledge base.
ClassMethod Item(source As %String, chunk As %Integer, score As %Double, section As %String = "Rotating the certificate", document As %String = "Results runbook") As %DynamicObject [ Private ]
{
	Quit {"id": (source _ ":" _ chunk), "score": (score), "text": ("Passage " _ chunk _ " of " _ source _ "."), "metadata": {"chunk_index": (chunk), "document": (document), "section": (section), "source": (source)}}
}

/// The result text that the audit policy receives for the items: the array itself (Task 0, M-shape).
ClassMethod Json(items As %DynamicArray) As %String [ Private ]
{
	Quit items.%ToJSON()
}

/// The object form that a direct ExecuteTool returns: {"timing", "value": [...]}.
ClassMethod Wrapped(items As %DynamicArray) As %String [ Private ]
{
	Quit {"timing": 0.4, "value": (items)}.%ToJSON()
}

/// Calls Collect as the audit policy does, for the documents call of the knowledge base (no origin_class) with the result text.
ClassMethod Collect(json As %String, name As %String = "documents", metadata As %DynamicObject = {{"requires_auth": false}}) As %Status [ Private ]
{
	Quit $ClassMethod(..#CLASS, "Collect", {"id": "call_id", "name": (name), "arguments": {"query": "q"}}, metadata, {"result_json": (json)})
}

/// The citations of the context's HostData as a dynamic array, "" when there are none.
ClassMethod Cited() As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Bridge.HostData).Get("citations")
}

/// The chunkIndex of every citation, comma-separated, with the document ref before a colon when it is not zzA.
ClassMethod Refs() As %String [ Private ]
{
	Set cited = ..Cited()
	If '$IsObject(cited) Quit "none"
	Set result = ""
	Set iterator = cited.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set result = result _ $Select(result '= "": ",", 1: "") _ entry.documentRef _ ":" _ entry.chunkIndex
	}
	Quit result
}

Method TestConstants()
{
	Do $$$AssertEquals(+$Parameter(..#CLASS, "CITEFLOOR"), 0.4, "the floor is 0.4, midway between the best unrelated score (0.1132) and the worst relevant one (0.6892), Task 0 M4")
	Do $$$AssertEquals($Parameter(..#CLASS, "MAXCITATIONS"), 5, "at most five citations")
	Do $$$AssertEquals($Parameter(..#CLASS, "MEMBER"), "citations", "in the HostData member citations")
}

Method TestFloor()
{
	Do ..Begin()
	Set items = []
	Do items.%Push(..Item("zzA", 0, 0.9))
	Do items.%Push(..Item("zzA", 1, 0.4))
	Do items.%Push(..Item("zzA", 2, 0.39999))
	Do items.%Push(..Item("zzA", 3, 0.1132))
	Do items.%Push(..Item("zzA", 4, -0.05))
	Do $$$AssertStatusOK(..Collect(..Json(items)), "a result is collected")
	Do $$$AssertEquals(..Refs(), "zzA:0,zzA:1", "the passages at 0.9 and exactly 0.4 are cited, those below 0.4 are not")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Begin()
	Set items = []
	Do items.%Push(..Item("zzA", 0, 0.3081))
	Do items.%Push(..Item("zzA", 1, 0.1747))
	Do ..Collect(..Json(items))
	Do $$$AssertEquals(..Refs(), "none", "a search whose best score is below the floor cites nothing")
}

Method TestWrappedShape()
{
	Do ..Begin()
	Set items = []
	Do items.%Push(..Item("zzA", 1, 0.9))
	Do items.%Push(..Item("zzA", 2, 0.1))
	Do ..Collect(..Wrapped(items))
	Do $$$AssertEquals(..Refs(), "zzA:1", "the object {timing, value} is read as the array is")
}

Method TestEntries()
{
	Do ..Begin()
	Set items = []
	Do items.%Push(..Item("zzB", 3, 0.5, "Clearing the queue", "Other runbook"))
	Do items.%Push(..Item("zzA", 1, 0.7))
	Do ..Collect(..Json(items))
	Set cited = ..Cited()
	Do $$$AssertEquals(cited.%Size(), 2, "two passages are cited")
	Do $$$AssertEquals(cited.%Get(0).%ToJSON(), {"documentRef": "zzB", "document": "Other runbook", "section": "Clearing the queue", "passage": "Passage 3 of zzB.", "chunkIndex": 3}.%ToJSON(), "the first entry has exactly documentRef, document, section, passage and chunkIndex, from the item")
	Do $$$AssertEquals(cited.%Get(1).documentRef _ "|" _ cited.%Get(1).section _ "|" _ cited.%Get(1).chunkIndex, "zzA|Rotating the certificate|1", "and the second follows in the order of the results")
}

Method TestDistinct()
{
	Do ..Begin()
	Set items = []
	Do items.%Push(..Item("zzA", 1, 0.7))
	Do items.%Push(..Item("zzA", 1, 0.6))
	Do ..Collect(..Json(items))
	Do $$$AssertEquals(..Refs(), "zzA:1", "the same passage twice in a result is cited once")
	Set items = []
	Do items.%Push(..Item("zzA", 1, 0.7))
	Do items.%Push(..Item("zzA", 2, 0.7))
	Do items.%Push(..Item("zzB", 1, 0.7))
	Do ..Collect(..Json(items))
	Do $$$AssertEquals(..Refs(), "zzA:1,zzA:2,zzB:1", "and across searches: another chunk of the document and the same chunk of another document are other passages, in order")
}

Method TestCap()
{
	Do ..Begin()
	Set items = []
	For i = 0:1:6 Do items.%Push(..Item("zzA", i, 0.9 - (i / 100)))
	Do ..Collect(..Json(items))
	Do $$$AssertEquals(..Refs(), "zzA:0,zzA:1,zzA:2,zzA:3,zzA:4", "seven passages clear the floor and the first five are cited")
	Set items = []
	Do items.%Push(..Item("zzB", 0, 0.9))
	Do ..Collect(..Json(items))
	Do $$$AssertEquals(..Cited().%Size(), 5, "a later search adds nothing once there are five")
}

Method TestMemberAbsent()
{
	Do ..Begin()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.HostData).Put("memories", [{"memoryRef": "zzm"}]), "HostData already holds a recall's member")
	Set items = []
	Do items.%Push(..Item("zzA", 0, 0.2))
	Do ..Collect(..Json(items))
	Set data = {}.%FromJSON(##class(OcuTalon.Bridge.Context).Current().HostData)
	Do $$$AssertEquals(data.%IsDefined("citations"), 0, "nothing clears the floor, so there is no citations member")
	Do $$$AssertEquals(data.memories.%Size(), 1, "and the other member stays")
	Set items = []
	Do items.%Push(..Item("zzA", 0, 0.8))
	Do ..Collect(..Json(items))
	Set data = {}.%FromJSON(##class(OcuTalon.Bridge.Context).Current().HostData)
	Do $$$AssertEquals(data.%IsDefined("citations") _ "|" _ data.memories.%Size(), "1|1", "a passage that clears it adds the member and keeps the other")
}

Method TestOtherCallsIgnored()
{
	Do ..Begin()
	Set items = []
	Do items.%Push(..Item("zzA", 0, 0.9))
	Set json = ..Json(items)
	Do ..Collect(json, "search_memories", {"origin_class": "OcuTalon.Tools.MemoryTools", "requires_auth": false})
	Do ..Collect(json, "documents", {"origin_class": "OcuTalon.Tools.Zz", "requires_auth": false})
	Do ..Collect(json, "Documents")
	Do ..Collect(json, "")
	Do $$$AssertEquals(..Refs(), "none", "a toolset tool, documents with an origin_class, another case of the name and no name cite nothing")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().ToolResultChars, 0, "and add no characters to the step")
	Do $$$AssertStatusOK($ClassMethod(..#CLASS, "Collect", "", "", ""), "a call that is not an object is no error")
	Do $$$AssertStatusOK($ClassMethod(..#CLASS, "Collect", {"name": "documents"}, "", ""), "nor a call with no metadata and no result")
}

Method TestCharsCounted()
{
	Do ..Begin()
	Set items = []
	Do items.%Push(..Item("zzA", 0, 0.9))
	Set json = ..Json(items)
	Do ..Collect(json)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().ToolResultChars, $Length(json), "the characters of the result are counted")
	Set items = []
	Do items.%Push(..Item("zzA", 5, 0.1))
	Set low = ..Json(items)
	Do ..Collect(low)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().ToolResultChars, $Length(json) + $Length(low), "a result that cites nothing is counted too, and the counts add up")
	Do ..Collect("")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().ToolResultChars, $Length(json) + $Length(low), "an empty result adds nothing")
}

Method TestMalformed()
{
	Do ..Begin()
	Set bad = $ListBuild("not json", "{}", "[]", "{""value"":""x""}", "{""value"":[1,2,""a""]}", "[1,2,""a""]", "[[]]", "[{""score"":0.9,""text"":""t"",""metadata"":{""source"":""zzA"",""chunk_index"":0}}", "{""value"":[{""score"":0.9}]}", "{""value"":[{""score"":""0.9"",""text"":""t"",""metadata"":{""source"":""zzA"",""chunk_index"":0}}]}", "{""value"":[{""score"":0.9,""text"":""t""}]}", "{""value"":[{""score"":0.9,""text"":""t"",""metadata"":{""chunk_index"":0}}]}", "{""value"":[{""score"":0.9,""text"":""t"",""metadata"":""x""}]}", "{""value"":[null]}")
	Set position = 0
	While $ListNext(bad, position, json) {
		Do $$$AssertStatusOK(..Collect(json), "'" _ json _ "' is collected without an error")
	}
	Do $$$AssertEquals(..Refs(), "none", "none of them cites anything")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertStatusOK(..Collect(..Json([])), "with no context Collect still answers OK")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and starts none")
}

}
