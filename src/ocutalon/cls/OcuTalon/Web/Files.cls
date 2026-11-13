/// The files route of /ocutalon/api (Story 25.3; AD-1, AD-4, AD-13, AD-14, AD-21), forwarded from OcuTalon.Web.Api's URL map
/// (<Map Prefix="/v1/files">), so the role check, the admin check and the browser envelope run again in the forwarded dispatch:
///   - POST /v1/files takes {"clientId","name","content"}: the page's id for the message, the file's name and its bytes in base64. The body is parsed from
///     the request stream, never through a string (a 10 MB file is a 14 MB body), by Web.Documents' ParseBody; any other key of the body (a sessionRef
///     included) is ignored. In order:
///       1. On the online demo (setting onlineDemo 1) the answer is 409 not_available with Core.Files' off text, before the body is read; nothing is
///          stored or counted.
///       2. A body over BODYMAX, this route's own bound, is 413 body_too_large before it is parsed.
///       3. A body that is not an object with a string clientId of 1 to 128 characters, a string name of 1 to 255 characters that is not blank and holds
///          no control character, and a string content of valid base64 is 400 bad_file with no reason.
///       4. Core.Files.Store, under the CSP session's Ref, checks the size (reason too_large), no bytes (empty) and the bytes' signature and the name's
///          extension (wrong_type); a refusal is 400 bad_file with the reason and the size in bytes beside the error, and stores nothing. The type is never
///          read from the name alone or from a declared type.
///       5. A stored file goes to WebChatIn (Web.Api's Post) as a Channel.WebChat.Post with no text and the file's Ref, name, media type and size, which sends
///          Conversation an Item of provenance untrusted (AD-14).
///       6. When WebChatIn did not send the Item (a clientId that the session already used, or a refusal) or failed, the stored file is deleted again.
///       7. 202 {"clientId","file":{"ref","name","mediaType","size"}}; for a clientId already used, 202 {"clientId"}. A failure is 500 server_error.
///   - No other route exists: every other method on /v1/files, and every path below it, is 404 not_found. No route serves a stored file's bytes back
///     (Core.Files.Open is a class call and nothing else), and the route logs nothing about a file.
/// The route does not read the capability flag filesReadable, which only hides the page's controls. No call takes a SessionRef from the client.
Class OcuTalon.Web.Files Extends OcuTalon.Web.Api [ DependsOn = OcuTalon.Web.Documents ]
{

/// The largest request body of POST /v1/files, in bytes: Web.Documents' BODYMAX, the base64 of a 10 MB file plus the JSON around it.
Parameter BODYMAX = {##class(OcuTalon.Web.Documents).#BODYMAX};

/// The message of the 400 bad_file and of the 413 body_too_large.
Parameter MESSAGEBADFILE = "OcuTalon can read PDF, Word (.docx), JPEG and PNG files up to 10 MB.";

Parameter HTTP413TOOLARGE = "413 Content Too Large";

/// The longest clientId, as for a message.
Parameter CLIENTIDMAX = 128;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="" Method="POST" Call="Send"/>
</Routes>
}

/// The request body this class's POST route takes, checked again here by the inherited OnPreDispatch with the path after the Map's prefix, ""
/// (Web.BodyLimit); the same number as BODYMAX, which Test.Web.FilesApi pins, and as Web.Api's entry for /v1/files.
XData BodyBounds [ MimeType = application/json ]
{
[
{"method": "POST", "url": "", "bytes": 13985112}
]
}

/// POST /v1/files: see the class description.
ClassMethod Send() As %Status
{
	If ..OnlineDemo() Quit ..Fail(409, "not_available", ##class(OcuTalon.Core.Files).#TEXTOFFONDEMO)
	Set content = %request.Content
	If $IsObject(content) && (content.Size > ..#BODYMAX) Quit ..BodyTooLarge()
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '..FileBody(content, .clientId, .name, .bytes) Quit ..Fail(400, "bad_file", ..#MESSAGEBADFILE)
	Set size = bytes.Size
	Set code = ##class(OcuTalon.Core.Files).Store(sessionRef, "web", name, bytes, .file, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If code '= "" Quit ..Fail(400, "bad_file", ..#MESSAGEBADFILE, , {"reason": (code), "size": (size)})
	Set post = ##class(OcuTalon.Channel.WebChat.Post).%New()
	Set post.SessionRef = sessionRef
	Set post.ClientId = clientId
	Set post.FileRef = file.ref
	Set post.FileName = file.name
	Set post.FileMediaType = file.mediaType
	Set post.FileSize = file.size
	Set duplicate = 0
	Try {
		Set sc = ..Post(post, .output)
		If $SYSTEM.Status.IsOK(sc) Set sc = ..Outcome(output, .duplicate)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) || duplicate {
		Do ##class(OcuTalon.Core.Files).Discard(file.ref, sessionRef)
		If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	}
	Set %response.ContentType = ..#CONTENTTYPE
	Set %response.Status = ..#HTTP202ACCEPTED
	If duplicate {
		Write {"clientId": (clientId)}.%ToJSON()
	} Else {
		Write {"clientId": (clientId), "file": (file)}.%ToJSON()
	}
	Quit $SYSTEM.Status.OK()
}

/// Reads WebChatIn's answer: OK when it sent the Item (duplicate 0) or found the clientId already used (duplicate 1); an error for any other answer,
/// a refusal included.
ClassMethod Outcome(answerText As %String, Output duplicate As %Boolean) As %Status [ Private ]
{
	Set duplicate = 0
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set answer = ##class(%DynamicAbstractObject).%FromJSON(answerText)
		If 'answer.%IsA("%Library.DynamicObject") || (answer.accepted '= 1) {
			Set sc = $SYSTEM.Status.Error(5001, "WebChatIn did not accept the message")
		} Else {
			Set duplicate = (answer.duplicate = 1)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// 1 with the fields of the body when it is valid, as the class description says; otherwise 0 with the fields empty. The body is read from its stream.
ClassMethod FileBody(content As %Stream.Object, Output clientId As %String, Output name As %String, Output bytes As %Stream.Object) As %Boolean [ Private ]
{
	Set clientId = ""
	If '##class(OcuTalon.Web.Documents).ParseBody(content, .name, .bytes, .body) Quit 0
	If $ZStrip(name, "<>W") = "" Quit 0
	If $ZStrip(name, "*C") '= name Quit 0
	If body.%GetTypeOf("clientId") '= "string" Quit 0
	Set id = body.clientId
	If ($Length(id) < 1) || ($Length(id) > ..#CLIENTIDMAX) Quit 0
	Set clientId = id
	Quit 1
}

/// 1 when the online-demo flag is set. A test subclass overrides it.
ClassMethod OnlineDemo() As %Boolean [ Private ]
{
	Quit (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
}

/// Every other method on a URL of this class has no route (the class description): 404 not_found, with no Allow header.
ClassMethod Http405(pSupportedVerbs As %String = "") As %Status
{
	Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
}

/// The 413 body_too_large.
ClassMethod BodyTooLarge() As %Status [ Private ]
{
	Set %response.ContentType = ..#CONTENTTYPE
	Set %response.Status = ..#HTTP413TOOLARGE
	Write ..ErrorBody("body_too_large", ..#MESSAGEBADFILE).%ToJSON()
	Quit $SYSTEM.Status.OK()
}

}
