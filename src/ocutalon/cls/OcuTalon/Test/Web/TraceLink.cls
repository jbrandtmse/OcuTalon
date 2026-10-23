/// Tests of Web.TraceLink, the one builder of Visual Trace URLs (Story 2.9; AD-12, AD-24, AD-26). Safe on a slot: TraceLink runs
/// no SQL, and the tests set the signed-in user's Visual Trace settings through Visual Trace's own setters and the demo.mode row,
/// and put both back.
///   - TestPage: PAGE is ceil(position / page size) for the viewer's page size, 40 and then 10, and absent without a position;
///   - TestShowEventsOff: with events hidden the position without events decides the page;
///   - TestNamespaces: each namespace's own trace application, OCUORDERS only in demo mode, and none for another namespace or
///     for an empty header id;
///   - TestNested: Add gives every object that has a target its own traceUrl, at any depth and in arrays, from that object's own
///     positions, and changes no other object;
///   - TestViewer: the defaults (40, events on) when nothing is set or the settings cannot be read, and the viewer's own
///     settings when they are, read once per namespace for a request.
/// The user's own ^EnsPortal.Settings($Username,"VisualTrace") node is saved before the tests (in a process-private global) and
/// put back after them, and a user who had none has none again; the demo.mode row goes through Test.Demo.Step's helpers.
Class OcuTalon.Test.Web.TraceLink Extends %UnitTest.TestCase
{

/// The path of the main trace application and the page.
Parameter MAIN = "/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=";

/// The path of the demo trace application and the page.
Parameter DEMO = "/ocutalon/trace/ocuorders/EnsPortal.VisualTrace.zen?SESSIONID=";

/// 1 when the user had Visual Trace settings before the tests.
Property SavedFound As %Boolean;

/// 1 when the demo.mode row existed before the tests, and its value and UpdatedAt.
Property SavedModeFound As %Boolean;

Property SavedModeValue As %String(MAXLEN = 1000);

Property SavedModeUpdatedAt As %String(MAXLEN = 20);

Method OnBeforeAllTests() As %Status
{
	Kill ^||OcuTalonTest.TraceLink
	Set ..SavedFound = $Data(^EnsPortal.Settings($Username, "VisualTrace")) \ 10
	If ..SavedFound Merge ^||OcuTalonTest.TraceLink = ^EnsPortal.Settings($Username, "VisualTrace")
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set ..SavedModeFound = found, ..SavedModeValue = value, ..SavedModeUpdatedAt = updatedAt
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Kill ^EnsPortal.Settings($Username, "VisualTrace")
	If ..SavedFound Merge ^EnsPortal.Settings($Username, "VisualTrace") = ^||OcuTalonTest.TraceLink
	Kill ^||OcuTalonTest.TraceLink
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..SavedModeFound, ..SavedModeValue, ..SavedModeUpdatedAt)
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^EnsPortal.Settings($Username, "VisualTrace")
	Do ##class(OcuTalon.Test.Demo.Step).Put(0, ##class(OcuTalon.Data.Time).NowUtc())
	Quit $SYSTEM.Status.OK()
}

/// PAGE is the position divided by the viewer's page size, rounded up: 40, 41, 80 and 81 are pages 1, 2, 2 and 3 at 40 items a
/// page, and 4, 5, 8 and 9 at 10. A header with no position has no PAGE.
Method TestPage()
{
	Do ..Sizes(40, $ListBuild(40, 41, 80, 81), $ListBuild(1, 2, 2, 3))
	Do ..Sizes(10, $ListBuild(40, 41, 80, 81), $ListBuild(4, 5, 8, 9))
	Do ..Sizes(40, $ListBuild(1, 39), $ListBuild(1, 1))
	Do ##class(EnsPortal.VisualTrace).SetItemsPerPage(40)
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7001, "OCUTALON", , , .viewer), ..#MAIN_7001, "a header with no position has no PAGE")
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7001, "OCUTALON", "", "", .viewer), ..#MAIN_7001, "an empty position has none either")
}

/// With "Show events" off the position without events decides the page: 50 with events and 30 without, at 40 a page, is page 1;
/// with events on it is page 2. Without the position for the viewer's choice there is no PAGE.
Method TestShowEventsOff()
{
	Do ##class(EnsPortal.VisualTrace).SetItemsPerPage(40)
	Do ##class(EnsPortal.VisualTrace).SetShowEvents(0)
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7002, "OCUTALON", 50, 30, .viewer), ..#MAIN_7002_"&PAGE=1", "events off: the position without events, 30, is page 1")
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7002, "OCUTALON", 50, "", .viewer), ..#MAIN_7002, "events off and no position without events: no PAGE")
	Do ##class(EnsPortal.VisualTrace).SetShowEvents(1)
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7002, "OCUTALON", 50, 30, .viewer), ..#MAIN_7002_"&PAGE=2", "events on: the position with events, 50, is page 2")
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7002, "OCUTALON", "", 30, .viewer), ..#MAIN_7002, "events on and no position with events: no PAGE")
}

/// OCUTALON is the main trace application. ocuorders, in any case, is the demo application while demo mode is on, and has no
/// URL while it is off. Another namespace, and an empty header id, have none.
Method TestNamespaces()
{
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7003, "OCUTALON", , , .viewer), ..#MAIN_7003, "OCUTALON")
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7003, "ocutalon", , , .viewer), ..#MAIN_7003, "ocutalon, in any case")
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7003, "ocuorders", , , .viewer), "", "ocuorders without demo mode has none")
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, ##class(OcuTalon.Data.Time).NowUtc())
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7003, "ocuorders", , , .viewer), ..#DEMO_7003, "ocuorders with demo mode on")
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7003, "OCUORDERS", , , .viewer), ..#DEMO_7003, "OCUORDERS too")
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7003, "ZZNS", , , .viewer), "", "another namespace has none")
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7003, "", , , .viewer), "", "an empty namespace has none")
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url("", "OCUTALON", , , .viewer), "", "an empty header id has none")
	Do ##class(OcuTalon.Test.Demo.Step).Put(0, ##class(OcuTalon.Data.Time).NowUtc())
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7003, "ocuorders", , , .viewer), "", "ocuorders with demo mode off has none")
}

/// Add gives each object with a traceHeaderId and a traceNamespace its own traceUrl, from its own positions: a chat message and
/// its decision (which has none), an incident's trace targets, objects of an array, and a root array. The key stays absent for
/// a namespace without an application and for an empty header id, and an object with no target is not changed.
Method TestNested()
{
	Do ##class(EnsPortal.VisualTrace).SetItemsPerPage(40)
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Set body = {
		"chat": [
			{"type": "chat.message", "payload": {"ref": "a", "traceHeaderId": 8001, "traceNamespace": "OCUTALON", "traceItemIndex": 41, "traceItemIndexNoEvents": 30, "decision": {"ref": "d", "traceHeaderId": 8002, "traceNamespace": "OCUTALON"}}},
			{"type": "chat.message", "payload": {"ref": "b", "traceHeaderId": 8003, "traceNamespace": "ZZNS", "traceItemIndex": 5}},
			{"type": "chat.message", "payload": {"ref": "c", "text": "no target"}},
			{"type": "incident", "payload": {"ref": "i", "traceTargets": {"sample": {"traceHeaderId": 8004, "traceNamespace": "OCUTALON"}, "diagnosis": {"traceHeaderId": "", "traceNamespace": "OCUTALON"}}}}
		],
		"rail": {"decisions": [{"ref": "e", "traceHeaderId": 8005, "traceNamespace": "OCUTALON"}]},
		"user": "zz"
	}
	Set plain = {"ref": "c", "text": "no target"}.%ToJSON()
	Do ##class(OcuTalon.Web.TraceLink).Add(body, .viewer)
	Set message = body.chat.%Get(0).payload
	Do $$$AssertEquals(message.traceUrl, ..#MAIN_8001_"&PAGE=2", "a chat message: its URL with the page of its position")
	Do $$$AssertEquals(message.decision.traceUrl, ..#MAIN_8002, "its decision, nested: its own URL, with no PAGE")
	Do $$$AssertEquals(body.chat.%Get(1).payload.%IsDefined("traceUrl"), 0, "a target in a namespace without an application has no traceUrl key")
	Do $$$AssertEquals(body.chat.%Get(2).payload.%ToJSON(), plain, "an object with no target is unchanged")
	Set targets = body.chat.%Get(3).payload.traceTargets
	Do $$$AssertEquals(targets.sample.traceUrl, ..#MAIN_8004, "an incident's trace target: its own URL")
	Do $$$AssertEquals(targets.diagnosis.%IsDefined("traceUrl"), 0, "a target with an empty header id has none")
	Do $$$AssertEquals(body.rail.decisions.%Get(0).traceUrl, ..#MAIN_8005, "an object in a nested array: its own URL")
	Do $$$AssertEquals(body.%IsDefined("traceUrl")_body.chat.%Get(3).payload.%IsDefined("traceUrl")_body.chat.%Get(0).%IsDefined("traceUrl"), "000", "the objects that wrap a target get none")
	Set list = [{"traceHeaderId": 8006, "traceNamespace": "OCUTALON", "traceItemIndex": 81}, 5, "text", [{"traceHeaderId": 8007, "traceNamespace": "OCUTALON"}]]
	Do ##class(OcuTalon.Web.TraceLink).Add(list, .viewer)
	Do $$$AssertEquals(list.%Get(0).traceUrl, ..#MAIN_8006_"&PAGE=3", "a root array: the object in it gets its URL")
	Do $$$AssertEquals(list.%Get(3).%Get(0).traceUrl, ..#MAIN_8007, "and an array nested in it")
}

/// With nothing set the viewer's page size is 40 and events are on; the settings of the user are the viewer's, read in the
/// namespace, once per request; and settings that cannot be read, here those of a namespace that does not exist, are 40 and on.
Method TestViewer()
{
	Set namespace = $Namespace
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Web.TraceLink).Read(namespace)), "40,1", "with nothing set: 40 and on")
	Do ##class(EnsPortal.VisualTrace).SetItemsPerPage(10)
	Do ##class(EnsPortal.VisualTrace).SetShowEvents(0)
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Web.TraceLink).Read(namespace)), "10,0", "the user's settings: 10 and off")
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Web.TraceLink).Read("ZZNOSUCHNAMESPACE")), "40,1", "a read that throws: 40 and on")
	Do $$$AssertEquals($Namespace, namespace, "and the caller is still in its namespace")
	Set ^EnsPortal.Settings($Username, "VisualTrace", "ItemsPerPage") = "many"
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Web.TraceLink).Read(namespace)), "40,0", "a page size that is not a number: 40")
	Do ##class(EnsPortal.VisualTrace).SetItemsPerPage(10)
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7004, "OCUTALON", 11, 11, .viewer), ..#MAIN_7004_"&PAGE=2", "the viewer's own page size, 10: position 11 is page 2")
	Do ##class(EnsPortal.VisualTrace).SetItemsPerPage(25)
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7004, "OCUTALON", 11, 11, .viewer), ..#MAIN_7004_"&PAGE=2", "the settings are read once for a viewer: the page size is still 10")
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Do $$$AssertEquals(##class(OcuTalon.Web.TraceLink).Url(7004, "OCUTALON", 11, 11, .viewer), ..#MAIN_7004_"&PAGE=1", "and a new viewer reads 25: position 11 is page 1")
}

/// --- helpers ---
/// For the page size, the positions with events and the pages expected: the URL of header 7000 + n for each position.
Method Sizes(size As %Integer, positions As %List, pages As %List) [ Private ]
{
	Do ##class(EnsPortal.VisualTrace).SetItemsPerPage(size)
	Do ##class(EnsPortal.VisualTrace).SetShowEvents(1)
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	For i = 1:1:$ListLength(positions) {
		Set position = $List(positions, i)
		Set url = ##class(OcuTalon.Web.TraceLink).Url(7000 + i, "OCUTALON", position, 1, .viewer)
		Do $$$AssertEquals(url, ..#MAIN_(7000 + i)_"&PAGE="_$List(pages, i), "size "_size_", position "_position_": page "_$List(pages, i))
	}
}

}
