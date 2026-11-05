/// The size limit on a request body, shared by every route of a web dispatch class whose OnPreDispatch asks for it (Story 11.22; AD-13;
/// today OcuTalon.Web.Api). OnPreDispatch of the dispatch
/// class asks TooLarge before the route is matched, so a body over the limit is refused with 413 body_too_large before any route reads or
/// parses it. The limit is MAXBYTES (256 KB) for every route; a body of exactly MAXBYTES is accepted.
///
/// A route that takes larger bodies declares its own bound by appending XData BodyBounds to its dispatch class, a JSON array with one entry
/// per route, no change to this class or to OnPreDispatch:
///
///     XData BodyBounds [ MimeType = application/json ]
///     {
///     [{"method": "POST", "url": "/v1/documents", "bytes": 14680064}]
///     }
///
/// url is the path as that class's OnPreDispatch receives it, written as in its UrlMap (":name" stands for one path segment), and method
/// is the HTTP method. A route behind a <Map Prefix="..." Forward="..."/> is checked once in the class that holds the Map, with the full
/// path (for example "/v1/documents"), and again in the forwarded class when it extends OcuTalon.Web.Api, with the rest of the path after
/// the prefix (for example ""). The forwarded class inherits its superclass's XData, so it declares the route in an XData BodyBounds of
/// its own, and the class that holds the Map declares the full path. Only a bound larger than
/// MAXBYTES takes effect, and only for the route and method it names; every other route keeps MAXBYTES. The declaration is read only when
/// a body is over MAXBYTES. A declaration that is missing, is not valid JSON or is not an array means MAXBYTES, and an entry that is
/// malformed is skipped.
Class OcuTalon.Web.BodyLimit
{

/// The bytes a body may have on a route that declares no bound of its own: 256 KB.
Parameter MAXBYTES = 262144;

/// The status line of a refused body.
Parameter HTTP413CONTENTTOOLARGE = "413 Content Too Large";

/// The message of the refusal (the error code is body_too_large).
Parameter MESSAGEBODYTOOLARGE = "OcuTalon refused this request because its body is larger than it accepts.";

/// The size in bytes of the body of the current request (%request.Content, already received and not read), 0 when there is none.
ClassMethod Size() As %Integer
{
	Set content = %request.Content
	If '$IsObject(content) Quit 0
	Quit +content.Size
}

/// The bytes a body of the route (url as the dispatch class receives it, method the HTTP method) may have in the dispatch class: MAXBYTES,
/// or the larger bound that the class declares for the route in XData BodyBounds.
ClassMethod Bound(class As %String, url As %String, method As %String) As %Integer
{
	Set bound = ..#MAXBYTES
	Try {
		Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(class _ "||BodyBounds")
		If '$IsObject(xdata) Quit
		Set list = ##class(%DynamicAbstractObject).%FromJSON(xdata.Data)
		If list.%ClassName(1) '= "%Library.DynamicArray" Quit
		Set path = $Piece($Get(url), "?", 1)
		Set iterator = list.%GetIterator()
		While iterator.%GetNext(, .entry) {
			If '$IsObject(entry) || (entry.%ClassName(1) '= "%Library.DynamicObject") Continue
			If (entry.%GetTypeOf("method") '= "string") || (entry.%GetTypeOf("url") '= "string") || (entry.%GetTypeOf("bytes") '= "number") Continue
			If $ZConvert(entry.method, "U") '= $ZConvert($Get(method), "U") Continue
			If '..Matches(entry.url, path) Continue
			If (entry.bytes = (entry.bytes \ 1)) && (entry.bytes > bound) Set bound = entry.bytes
		}
	} Catch {
		Set bound = ..#MAXBYTES
	}
	Quit bound
}

/// 1 when the body of the current request is over the bound of the route in the dispatch class.
ClassMethod TooLarge(class As %String, url As %String, method As %String) As %Boolean
{
	Set size = ..Size()
	If size <= ..#MAXBYTES Quit 0
	Quit size > ..Bound(class, url, method)
}

/// 1 when the path is the pattern, a route url of the UrlMap form in which ":name" matches one non-empty segment.
ClassMethod Matches(pattern As %String, path As %String) As %Boolean [ Private ]
{
	If $Length(pattern, "/") '= $Length(path, "/") Quit 0
	Set matches = 1
	For i = 1:1:$Length(pattern, "/") {
		Set wanted = $Piece(pattern, "/", i)
		Set got = $Piece(path, "/", i)
		If ($Extract(wanted) = ":") && ($Length(wanted) > 1) {
			If got = "" Set matches = 0
		} ElseIf wanted '= got {
			Set matches = 0
		}
		If 'matches Quit
	}
	Quit matches
}

}
