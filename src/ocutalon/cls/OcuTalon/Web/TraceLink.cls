/// The one builder of Visual Trace URLs (AD-12, AD-24, AD-26). Lane B. A payload object that carries traceHeaderId and
/// traceNamespace gets a traceUrl when the REST surface serves it (Add); Url builds one.
///   - The URL is the path of the namespace's own trace application, then EnsPortal.VisualTrace.zen?SESSIONID=<header id>,
///     and, when the position of the header in its session is known, &PAGE=<ceil(position / page size)>. The page size and
///     whether events are shown are the viewer's own Visual Trace settings, read through Visual Trace's own getters in the
///     target's namespace (Viewer keeps them for the request, once per namespace); a setting that cannot be read is 40 and on.
///     The position is the one for the viewer's choice: the index with events when they are shown, otherwise the one without;
///   - OCUTALON has the application /ocutalon/trace/ocutalon/ and OCUORDERS the application /ocutalon/trace/ocuorders/ while
///     demo mode is on. Any other namespace, and an empty header id, has no URL;
///   - TraceLink runs no SQL and reads no Ens table (Viewer's one read is the demo.mode setting, through Data.Setting), and its URLs
///     are paths on the page's own origin.
Class OcuTalon.Web.TraceLink
{

/// The page size of Visual Trace when the viewer's setting cannot be read: Visual Trace's own default.
Parameter PAGESIZE = 40;

/// The trace application of the main namespace and, while demo mode is on, of the demo namespace, as a namespace (upper case)
/// and the path of its application.
Parameter MAINNAMESPACE = "OCUTALON";

Parameter MAINAPPLICATION = "/ocutalon/trace/ocutalon/";

Parameter DEMONAMESPACE = "OCUORDERS";

Parameter DEMOAPPLICATION = "/ocutalon/trace/ocuorders/";

/// The page, with its session parameter.
Parameter PAGE = "EnsPortal.VisualTrace.zen?SESSIONID=";

/// The viewer of one request: whether demo mode is on (viewer("demo")); Url adds the page size and the choice to show events
/// of each namespace it needs. Called once per request.
ClassMethod Viewer(Output viewer)
{
	Kill viewer
	Set viewer("demo") = (##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Install.Step.Demo).#MODEKEY) = "1")
}

/// The URL of the header's trace in the namespace, "" when there is none. index and indexNoEvents are the header's position in
/// its session's item list with the events shown and hidden; PAGE is added only when the one for the viewer's choice is known.
ClassMethod Url(headerId As %String, namespace As %String, index As %Integer = "", indexNoEvents As %Integer = "", ByRef viewer) As %String
{
	If headerId = "" Quit ""
	Set upper = $ZConvert(namespace, "U")
	Set application = $Case(upper, ..#MAINNAMESPACE: ..#MAINAPPLICATION, ..#DEMONAMESPACE: $Select($Get(viewer("demo")): ..#DEMOAPPLICATION, 1: ""), : "")
	If application = "" Quit ""
	Set url = application_..#PAGE_headerId
	If (index = "") && (indexNoEvents = "") Quit url
	If '$Data(viewer("ns", upper), settings) {
		Set settings = ..Read(upper)
		Set viewer("ns", upper) = settings
	}
	Set position = $Select($List(settings, 2): index, 1: indexNoEvents)
	If position = "" Quit url
	Quit url_"&PAGE="_(position \ $List(settings, 1) + (position # $List(settings, 1) > 0))
}

/// Adds traceUrl to every object of the dynamic object or array, at any depth, that has a traceHeaderId and a traceNamespace and
/// whose Url is not empty. The position comes from the object's own traceItemIndex and traceItemIndexNoEvents.
ClassMethod Add(json As %DynamicAbstractObject, ByRef viewer)
{
	If '$IsObject($Get(json)) Quit
	Set children = 0
	Set iterator = json.%GetIterator()
	While iterator.%GetNext(, .value) {
		If $IsObject(value) {
			Set children = children + 1
			Set children(children) = value
		}
	}
	If json.%IsA("%Library.DynamicObject") {
		Set headerId = json.%Get("traceHeaderId")
		Set namespace = json.%Get("traceNamespace")
		If (headerId '= "") && (namespace '= "") {
			Set url = ..Url(headerId, namespace, json.%Get("traceItemIndex"), json.%Get("traceItemIndexNoEvents"), .viewer)
			If url '= "" Set json.traceUrl = url
		}
	}
	For i = 1:1:children Do ..Add(children(i), .viewer)
}

/// The viewer's page size and whether events are shown in the namespace, as $ListBuild(size, show), from Visual Trace's own
/// getters run there; 40 and on when they cannot be read (no such namespace, no access, a setting that is not a number).
ClassMethod Read(namespace As %String) As %List
{
	New $NAMESPACE
	Set size = ..#PAGESIZE
	Set show = 1
	Try {
		Set $NAMESPACE = namespace
		Set read = ##class(EnsPortal.VisualTrace).GetItemsPerPage() \ 1
		Set shown = ##class(EnsPortal.VisualTrace).GetShowEvents()
		If read >= 1 Set size = read
		Set show = (+shown '= 0)
	} Catch {
		Set size = ..#PAGESIZE
		Set show = 1
	}
	Quit $ListBuild(size, show)
}

}
