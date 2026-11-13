/// The documents routes of /ocutalon/api (Story 34.2; AD-1, AD-4, AD-13, AD-21), forwarded from OcuTalon.Web.Api's URL map
/// (<Map Prefix="/v1/documents">), so the role check, the admin check and the browser envelope run again in the forwarded dispatch:
///   - GET /v1/documents lists the session's documents through Ownership.Documents (its own on the online demo, the instance's on a local
///     install), newest first: 200 {"documents":[Live.Payload.Document.FromRow ...]}; a failed read is 500 server_error.
///   - POST /v1/documents takes {"name","content"}: the file's name and its bytes in base64. The body is parsed from the request stream,
///     never through a string (a 10 MB file is a 14 MB body). A body over BODYMAX, this route's own bound, is 413 body_too_large before it
///     is parsed. Then, before any command: a body that is not an object with a string name of 1 to 255 characters
///     and a string content of valid base64 is 400 bad_document with no reason; a name whose extension is not in EXTENSIONS is 400
///     bad_document with reason wrong_type; no bytes is reason empty; more than FILEMAX bytes (10,485,760) is reason too_large. A refused
///     file writes no row and submits nothing. An accepted file is stored as an OcuTalon.Data.Upload row of the CSP session, just before the
///     submit, and submits one AddDocument (Name, the ContentType of the extension, the row's Ref as UploadRef, the CSP session's Ref)
///     through Commands.Submit with origin web_user, and Ok is 200 {"result":"done","ref"}; the upload row is deleted again when the submit
///     fails or the owner does not answer Ok (DocumentOps takes it with Upload.Take). not_built is 501 not_built (also while DocumentOps is
///     not running, when nothing is stored or submitted); any other outcome or status is 500 server_error. DocumentOps (Lane A) checks the
///     file again, finds an unreadable one and writes the row (AD-21).
///   - GET /v1/documents/:ref reads one document's text for the Documents page: 200 {"ref","name","text"}, the text as the file was read
///     (Document.Text), through Ownership.Document, so that a ref the session can't see answers 404 not_found exactly like a missing one,
///     with no text; a failed read is 500 server_error. It submits and publishes nothing.
///   - DELETE /v1/documents/:ref answers 404 not_found first for a ref the session can't see (Ownership.Document), nothing submitted;
///     otherwise it submits one RemoveDocument with origin web_user: Ok is 200 {"result":"done"}, not_found 404, not_built 501, any
///     other outcome or status 500.
/// Every call of the four routes first sweeps the uploads that nobody took and that are more than an hour old (Upload.Purge, with no SQL);
/// a failed sweep never fails the call.
/// No call takes a SessionRef from the client, and the routes publish nothing: DocumentOps is the one publisher of the document event (AD-33).
Class OcuTalon.Web.Documents Extends OcuTalon.Web.Api
{

/// The largest file, in bytes: 10 MB (FR-54). It applies to every type.
Parameter FILEMAX = 10485760;

/// The largest request body of POST /v1/documents, in bytes: FILEMAX in base64 (4 characters for each 3 bytes, rounded up: 13,981,016)
/// plus 4,096 for the JSON around it (the name at its longest with every character escaped, and the keys).
Parameter BODYMAX = 13985112;

/// The extension (lower case, with its dot) of each accepted file name, and the ContentType it maps to.
Parameter EXTENSIONS = ".md:markdown,.markdown:markdown,.txt:text,.pdf:pdf,.docx:docx";

/// The origin of the commands the routes submit (AD-1): the person at the page.
Parameter ORIGIN = "web_user";

/// The production item that carries out both commands (AD-21): Lane A's DocumentOps, disabled until Story 19.4.
Parameter OWNER = "DocumentOps";

/// The refusal reasons of the route (the web app has the text of each); DocumentOps adds unreadable, not_built and failed.
Parameter REASONWRONGTYPE = "wrong_type";

Parameter REASONTOOLARGE = "too_large";

Parameter REASONEMPTY = "empty";

/// The message of the 400 bad_document and of the 413 body_too_large.
Parameter MESSAGEBADDOCUMENT = "OcuTalon can add Markdown, plain-text, PDF and Word (.docx) files up to 10 MB.";

Parameter HTTP413TOOLARGE = "413 Content Too Large";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="" Method="GET" Call="List"/>
<Route Url="" Method="POST" Call="Add"/>
<Route Url="/:ref" Method="GET" Call="Text"/>
<Route Url="/:ref" Method="DELETE" Call="Remove"/>
</Routes>
}

/// The request body this class's POST route takes, checked again here by the inherited OnPreDispatch with the path after the Map's prefix, ""
/// (Web.BodyLimit); the same number as BODYMAX, which Test.Web.DocumentsApi TestBodyBounds pins, and as Web.Api's entry for /v1/documents.
XData BodyBounds [ MimeType = application/json ]
{
[
{"method": "POST", "url": "", "bytes": 13985112}
]
}

/// GET /v1/documents: the session's documents, newest first.
ClassMethod List() As %Status
{
	Do ..Sweep()
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set rows = ##class(OcuTalon.Data.Ownership).Documents(sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set documents = []
	Set sc = $SYSTEM.Status.OK()
	Try {
		For i = 1:1:rows.Count() Do documents.%Push(..PayloadObject(##class(OcuTalon.Live.Payload.Document).FromRow(rows.GetAt(i))))
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set %response.ContentType = ..#CONTENTTYPE
	Write {"documents": (documents)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// POST /v1/documents: see the class description.
ClassMethod Add() As %Status
{
	Do ..Sweep()
	Set content = %request.Content
	If $IsObject(content) && (content.Size > ..#BODYMAX) Quit ..BodyTooLarge()
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '..ParseBody(content, .name, .bytes) Quit ..Fail(400, "bad_document", ..#MESSAGEBADDOCUMENT)
	Set contentType = ..ContentTypeOf(name)
	If contentType = "" Quit ..Refuse(..#REASONWRONGTYPE)
	If bytes.Size = 0 Quit ..Refuse(..#REASONEMPTY)
	If bytes.Size > ..#FILEMAX Quit ..Refuse(..#REASONTOOLARGE)
	Set command = ##class(OcuTalon.Msg.Command.AddDocument).%New()
	Set command.Name = name
	Set command.ContentType = contentType
	Set command.SessionRef = sessionRef
	Set sc = ..Dispatch(command, .result, .bytes)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	If result.Ok {
		Set %response.ContentType = ..#CONTENTTYPE
		Write {"result": "done", "ref": (result.Ref)}.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	If result.Outcome = "not_built" Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
	Quit ..ServerError($SYSTEM.Status.Error(5001, "The addition was answered "_result.Outcome))
}

/// GET /v1/documents/:ref: see the class description.
ClassMethod Text(ref As %String) As %Status
{
	Do ..Sweep()
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set row = ##class(OcuTalon.Data.Ownership).Document(ref, sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(row) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set sc = ..TextBody(row, .body)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set %response.ContentType = ..#CONTENTTYPE
	Do body.OutputToDevice()
	Quit $SYSTEM.Status.OK()
}

/// The JSON body {"ref","name","text"} of the document in body, read in full before anything is written, so that a failed read writes nothing.
ClassMethod TextBody(row As OcuTalon.Data.Document, Output body As %Stream.TmpCharacter) As %Status [ Private ]
{
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set answer = {"ref": (row.Ref), "name": (row.Name)}
		Do row.Text.Rewind()
		Do answer.%Set("text", row.Text, "stream")
		Set body = ##class(%Stream.TmpCharacter).%New()
		Do answer.%ToJSON(body)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// DELETE /v1/documents/:ref: see the class description.
ClassMethod Remove(ref As %String) As %Status
{
	Do ..Sweep()
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set row = ##class(OcuTalon.Data.Ownership).Document(ref, sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(row) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set command = ##class(OcuTalon.Msg.Command.RemoveDocument).%New()
	Set command.DocumentRef = row.Ref
	Set command.SessionRef = sessionRef
	Kill row
	Set sc = ..Dispatch(command, .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	If result.Ok {
		Set %response.ContentType = ..#CONTENTTYPE
		Write {"result": "done"}.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	If result.Outcome = "not_built" Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
	If result.Outcome = "not_found" Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Quit ..ServerError($SYSTEM.Status.Error(5001, "The removal was answered "_result.Outcome))
}

/// Hands the command to its owner. While the owner item is not running (DocumentOps is disabled until Story 19.4) nothing is stored or submitted and the
/// answer is a CommandResult with Ok 0 and the outcome not_built: a send to a disabled item is queued and waits for CommandsIn's whole timeout,
/// longer than the web server waits, so the page would wait in vain. When bytes are given (an AddDocument) they are stored as an
/// OcuTalon.Data.Upload row just before the submit, the command carries the row's Ref as UploadRef (a message body holds no global stream), and
/// the row is deleted again when the submit fails or the owner does not answer Ok; an Ok answer leaves it to the owner, which takes it. Passed by
/// reference, bytes is released once stored, so the caller does not hold the file while the submit waits.
ClassMethod Dispatch(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult, ByRef bytes As %Stream.Object = "") As %Status [ Private ]
{
	If '..OwnerRunning() {
		Set result = ##class(OcuTalon.Msg.CommandResult).%New()
		Set result.Ok = 0
		Set result.Outcome = "not_built"
		Set result.Message = ..#MESSAGENOTBUILT
		Quit $SYSTEM.Status.OK()
	}
	Set upload = ""
	If $IsObject(bytes) {
		Set upload = ##class(OcuTalon.Data.Upload).Put(command.SessionRef, bytes, .sc)
		If $SYSTEM.Status.IsError(sc) Quit sc
		Set $Property(command, "UploadRef") = upload
		Set bytes = ""
	}
	Set result = ""
	Try {
		Set sc = ..Submit(command, .result)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If (upload '= "") && ($SYSTEM.Status.IsError(sc) || '$IsObject(result) || 'result.Ok) Do ##class(OcuTalon.Data.Upload).Drop(upload, command.SessionRef)
	Quit sc
}

/// Deletes the uploads that nobody took within the hour (Upload.Purge); the status is ignored, because the sweep is housekeeping and a failed
/// one must not fail the call.
ClassMethod Sweep() [ Private ]
{
	Try {
		Do ##class(OcuTalon.Data.Upload).Purge(0, ..SweepNow())
	} Catch {
	}
}

/// The time the sweep measures its hour from: "" is the current time (a test subclass overrides it).
ClassMethod SweepNow() As %String [ Private ]
{
	Quit ""
}

/// 1 when the owner item is enabled in the running production (a test subclass overrides it).
ClassMethod OwnerRunning() As %Boolean [ Private ]
{
	Quit (+$Get(^Ens.Runtime("ConfigItem", ..#OWNER, "IsEnabled")) '= 0)
}

/// The one submit of the class: the command through Commands.Submit with origin ORIGIN, web_user (a test subclass overrides it).
ClassMethod Submit(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.Commands).Submit(command, ..#ORIGIN, .result)
}

/// Reads the request body from its stream, never through a string: 1 with the file's name and its decoded bytes (a binary stream) when
/// the body is an object with a string name of 1 to 255 characters and a string content of valid base64, otherwise 0. body is the parsed object
/// when the answer is 1 (for a route that reads more keys, OcuTalon.Web.Files), else "".
ClassMethod ParseBody(content As %Stream.Object, Output name As %String, Output bytes As %Stream.Object, Output body As %DynamicObject) As %Boolean
{
	Set name = "", bytes = "", body = ""
	If '$IsObject(content) Quit 0
	Try {
		Set parsed = ##class(%DynamicAbstractObject).%FromJSON(..Characters(content))
		If '$IsObject(parsed) || 'parsed.%IsA("%Library.DynamicObject") Quit
		Set body = parsed
		If (body.%GetTypeOf("name") '= "string") || (body.%GetTypeOf("content") '= "string") Quit
		Set fileName = body.name
		If ($Length(fileName) < 1) || ($Length(fileName) > 255) Quit
		Set decoded = body.%Get("content", , "stream<base64")
		If '$IsObject(decoded) {
			If decoded '= "" Quit
			Set decoded = ##class(%Stream.TmpBinary).%New()
		}
		Set name = fileName, bytes = decoded
	} Catch {
		Set name = "", bytes = ""
	}
	If name = "" Set body = ""
	Quit (name '= "")
}

/// The request body as a character stream, positioned at its start, without a string: a character stream is itself; a binary one, the bytes
/// the CSP server received (UTF-8, as the page sends JSON), is decoded piece by piece, never cutting a multi-byte character.
ClassMethod Characters(content As %Stream.Object) As %Stream.Object [ Private ]
{
	Do content.Rewind()
	If content.IsCharacter() Quit content
	Set text = ##class(%Stream.TmpCharacter).%New()
	Set rest = ""
	While 'content.AtEnd {
		Set raw = rest_content.Read(32000)
		Set whole = ..WholeBytes(raw)
		Do text.Write($ZConvert($Extract(raw, 1, whole), "I", "UTF8"))
		Set rest = $Extract(raw, whole + 1, *)
	}
	If rest '= "" Do text.Write($ZConvert(rest, "I", "UTF8"))
	Do text.Rewind()
	Quit text
}

/// How many leading bytes of the UTF-8 text end on a whole character: all of them unless the last character is cut short.
ClassMethod WholeBytes(raw As %String) As %Integer [ Private ]
{
	Set length = $Length(raw)
	Set whole = length
	For back = 1:1:3 {
		If back > length Quit
		Set byte = $Ascii(raw, length - back + 1)
		If byte < 128 Quit
		If byte >= 192 {
			Set need = $Select(byte >= 240: 4, byte >= 224: 3, 1: 2)
			If need > back Set whole = length - back
			Quit
		}
	}
	Quit whole
}

/// The ContentType of a file name by its extension, in any case, or "" when the extension is not accepted.
ClassMethod ContentTypeOf(name As %String) As %String
{
	Set dot = $Length(name, ".")
	If dot < 2 Quit ""
	Set extension = "." _ $ZConvert($Piece(name, ".", dot), "L")
	Set position = 0, contentType = ""
	Set list = $ListFromString(..#EXTENSIONS)
	While $ListNext(list, position, pair) {
		If $Piece(pair, ":", 1) = extension Set contentType = $Piece(pair, ":", 2)
	}
	Quit contentType
}

/// The 400 bad_document with the reason (wrong_type, too_large or empty) beside the error.
ClassMethod Refuse(reason As %String) As %Status [ Private ]
{
	Quit ..Fail(400, "bad_document", ..#MESSAGEBADDOCUMENT, , {"reason": (reason)})
}

/// The 413 body_too_large.
ClassMethod BodyTooLarge() As %Status [ Private ]
{
	Set %response.ContentType = ..#CONTENTTYPE
	Set %response.Status = ..#HTTP413TOOLARGE
	Write ..ErrorBody("body_too_large", ..#MESSAGEBADDOCUMENT).%ToJSON()
	Quit $SYSTEM.Status.OK()
}

}
