/// OcuTalon's minimal MCP client over HTTP (AD-21, AD-31): the part of the MCP wire protocol that OcuTalon speaks itself, with ObjectScript timeouts, so that a
/// server that accepts a connection and never answers cannot hold a runner job (AI Hub's own client has no deadline). Story 22.3 adds tools/list and tools/call.
///   - Probe sends one JSON-RPC initialize to the server's url and answers "" when the server answers with any HTTP status (a status line within the bound is
///     an answer, even when the body that follows never completes, as an event stream may not), unreachable when it gives no
///     response (a timeout, a refused connection, a failed TLS handshake) and failed when the url is not http:// or https:// with a host. It sends no credential
///     (a server that wants one answers 401, which is an answer), makes no AI Hub or Python call, follows no redirect and is bounded by seconds for the
///     connection, for each write (an https handshake runs in the first write) and for the answer. An https url uses the client SSL configuration of the installer (Install.Step.SSL), which verifies the server.
///   - ListTool and CallTool (Story 22.3) speak to a server with the credential header of its entry. ListTool sends initialize (keeping the Mcp-Session-Id header that
///     the server answers), the notification that the client is initialized, and tools/list, page after page (nextCursor, at most MAXPAGES pages), until it finds the tool by its
///     name; CallTool sends one tools/call with the session. Each request is bounded by its own limit (PROBESECONDS, and CALLSECONDS for tools/call), follows no redirect,
///     verifies the server's certificate for https (the installer's client SSL configuration) and takes the answer as a JSON body or as a text/event-stream body (the first
///     JSON-RPC message of the stream that answers the request). Each answers "" or a reason word: unreachable (no connection or no answer), timeout (the connection was made
///     and no answer came in time), failed (an HTTP status that is not 2xx, an error object, an answer that is not JSON-RPC, a tool result with isError true, a body over MAXBODY
///     characters or an unusable url or header) and, for ListTool, notfound (the server lists no tool of that name).
///   - Every method shares Open, which builds the request: the same timeouts, no redirect and the same SSL configuration for Probe, ListTool and CallTool.
///   - The header is "" (none) or {"name", "value"}: the one request header that carries the credential. It is resolved by the caller, in memory, and goes into the request
///     only. None of the methods throws, logs, stores or returns the url, the header or any text of the server: the answer is a code word.
Class OcuTalon.Mcp.Client
{

/// The seconds that Probe waits to open the connection, and again for the answer; also the limit of the initialize, the notification and each tools/list of ListTool.
Parameter PROBESECONDS = 2;

/// The seconds that CallTool waits for the answer (a tool may take a while); the connection and an https handshake are bounded by PROBESECONDS.
Parameter CALLSECONDS = 20;

/// The most pages of tools/list that ListTool reads while it looks for a tool.
Parameter MAXPAGES = 10;

/// The most characters of an answer body that is read; a longer body is a failure.
Parameter MAXBODY = 1000000;

/// The protocol version that Probe's initialize asks for.
Parameter PROTOCOLVERSION = "2025-03-26";

/// The name and version that Probe's initialize gives for this client.
Parameter CLIENTNAME = "ocutalon";

Parameter CLIENTVERSION = "1";

/// Sends one unauthenticated initialize to the url. "" when the server answers with any HTTP status (the status line counts, whether or not the body then
/// arrives), unreachable when no status comes within seconds (or the connection cannot be made), failed when the url is not usable. It never throws.
ClassMethod Probe(url As %String, seconds As %Integer = {..#PROBESECONDS}) As %String
{
	Set answer = "failed"
	Try {
		If '..Open($Get(url), seconds, .request, .path) Quit
		Set body = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": (..InitializeParams())}
		Do request.EntityBody.Write(body.%ToJSON())
		Set sc = request.Post(path)
		Set answer = $Select($IsObject(request.HttpResponse) && (+request.HttpResponse.StatusCode > 0): "", 1: "unreachable")
	} Catch {
		Set answer = "failed"
	}
	Quit answer
}

/// Finds the tool of the name on the server (see the class description): "" and its definition (the server's tools/list entry: name, description, inputSchema) when
/// it is listed, else a reason word. session gets the Mcp-Session-Id that initialize answered ("" when there is none), which CallTool takes. It never throws.
ClassMethod ListTool(url As %String, header As %DynamicObject = "", tool As %String, Output definition As %DynamicObject, ByRef session As %String) As %String
{
	Set definition = ""
	Set session = ""
	Set answer = "failed"
	Try {
		Set answer = ..Exchange($Get(url), header, .session, "initialize", ..InitializeParams(), ..#PROBESECONDS, .result)
		If answer '= "" Quit
		Set answer = ..Exchange(url, header, .session, "notifications/initialized", {}, ..#PROBESECONDS, , 1)
		If answer '= "" Quit
		Set answer = "notfound"
		Set cursor = ""
		For page = 1:1:..#MAXPAGES {
			Set found = ..Exchange(url, header, .session, "tools/list", $Select(cursor = "": {}, 1: {"cursor": (cursor)}), ..#PROBESECONDS, .result)
			If found '= "" {
				Set answer = found
				Quit
			}
			If result.%GetTypeOf("tools") '= "array" {
				Set answer = "failed"
				Quit
			}
			Set iterator = result.tools.%GetIterator()
			While iterator.%GetNext(, .entry, .type) {
				If (type = "object") && (entry.%GetTypeOf("name") = "string") && (entry.name = tool) {
					Set definition = entry
					Set answer = ""
					Quit
				}
			}
			If $IsObject(definition) Quit
			Set cursor = $Select(result.%GetTypeOf("nextCursor") = "string": result.nextCursor, 1: "")
			If cursor = "" Quit
		}
	} Catch {
		Set definition = ""
		Set answer = "failed"
	}
	Quit answer
}

/// Calls the tool with the arguments (a dynamic object) on the server with one tools/call, within CALLSECONDS, and keeps the session that ListTool gave. "" and the
/// result of the server (its content list and flags) when the server answers a result that is not an error; otherwise a reason word, and result is "": an HTTP status
/// that is not 2xx, an error object and a result with isError true are failed, so no text of a failing server is returned. It never throws.
ClassMethod CallTool(url As %String, header As %DynamicObject = "", tool As %String, arguments As %DynamicObject, Output result As %DynamicObject, session As %String = "") As %String
{
	Set result = ""
	Set answer = "failed"
	Try {
		Set params = {"name": (tool), "arguments": ($Select($IsObject($Get(arguments)): arguments, 1: {}))}
		Set answer = ..Exchange($Get(url), header, session, "tools/call", params, ..#CALLSECONDS, .reply)
		If answer '= "" Quit
		If reply.%GetTypeOf("isError") = "boolean" && (reply.isError = 1) {
			Set answer = "failed"
			Quit
		}
		Set result = reply
	} Catch {
		Set result = ""
		Set answer = "failed"
	}
	Quit answer
}

/// The request to the url (the one setup of Probe, ListTool and CallTool): 1 with request, a %Net.HttpRequest with the limit of seconds for the answer and for each write
/// (an https handshake runs in the first write) and of connect seconds for the connection (seconds when it is not given: a refused connection is tried until then), no redirect, the installer's client SSL configuration for https (which verifies the server's
/// certificate), the JSON content type and the Accept header of the transport, and path, the path with its query; 0 for a url that is not usable.
ClassMethod Open(url As %String, seconds As %Integer, Output request As %Net.HttpRequest, Output path As %String, connect As %Integer = "") As %Boolean
{
	Set request = ""
	If connect = "" Set connect = seconds
	If '..Endpoint($Get(url), .server, .port, .https, .path) Quit 0
	Set request = ##class(%Net.HttpRequest).%New()
	Set request.Server = server
	Set request.Port = port
	Set request.OpenTimeout = connect
	Set request.Timeout = seconds
	Set request.WriteTimeout = $Select(connect < 2: 2, 1: connect)
	Set request.FollowRedirect = 0
	If https {
		Set request.Https = 1
		Set request.SSLConfiguration = ##class(OcuTalon.Install.Step.SSL).#NAME
	}
	Set request.ContentType = "application/json"
	Do request.SetHeader("Accept", "application/json, text/event-stream")
	Quit 1
}

/// The params of an initialize request.
ClassMethod InitializeParams() As %DynamicObject [ Private ]
{
	Quit {"protocolVersion": (..#PROTOCOLVERSION), "capabilities": {}, "clientInfo": {"name": (..#CLIENTNAME), "version": (..#CLIENTVERSION)}}
}

/// One JSON-RPC request (or notification, when notification is 1) of the method to the server: "" with result, the result object of the answer, or a reason word (see
/// the class description). session is sent as the Mcp-Session-Id header when it is not empty, and is set from the answer to an initialize. The header is put on the
/// request after a check that it holds no control character. A notification needs a 2xx status and no body.
ClassMethod Exchange(url As %String, header As %DynamicObject, ByRef session As %String, method As %String, params As %DynamicObject, seconds As %Integer, Output result As %DynamicObject, notification As %Boolean = 0) As %String [ Private ]
{
	Set result = ""
	Set answer = "failed"
	Try {
		If '..Open(url, seconds, .request, .path, $Select(seconds > ..#PROBESECONDS: ..#PROBESECONDS, 1: seconds)) Quit
		If '..SetCredential(request, header) Quit
		If $Get(session) '= "" {
			If $ZStrip(session, "*C") '= session Quit
			Do request.SetHeader("Mcp-Session-Id", session)
		}
		Set body = {"jsonrpc": "2.0", "method": (method), "params": (params)}
		If 'notification Do body.%Set("id", 1, "number")
		Do request.EntityBody.Write($ZConvert(body.%ToJSON(), "O", "UTF8"))
		Set sc = request.Post(path)
		Set response = request.HttpResponse
		If $SYSTEM.Status.IsError(sc) && (('$IsObject(response)) || (+response.StatusCode = 0)) {
			Set answer = $Select($SYSTEM.Status.GetErrorCodes(sc) [ 5922: "timeout", 1: "unreachable")
			Quit
		}
		If '$IsObject(response) || (response.StatusCode < 200) || (response.StatusCode > 299) Quit
		If method = "initialize" Set session = ..SessionOf(response)
		If notification {
			Set answer = ""
			Quit
		}
		Set answer = ..Decode(response, .result)
	} Catch {
		Set result = ""
		Set answer = "failed"
	}
	If answer '= "" Set result = ""
	Quit answer
}

/// Puts the credential header on the request: 1 when there is none ("") or when it is {"name", "value"} with a name of token characters and a value without a
/// control character; 0 otherwise, and then nothing is sent.
ClassMethod SetCredential(request As %Net.HttpRequest, header As %DynamicObject) As %Boolean [ Private ]
{
	If '$IsObject($Get(header)) Quit 1
	If (header.%GetTypeOf("name") '= "string") || (header.%GetTypeOf("value") '= "string") Quit 0
	Set name = header.name
	Set value = header.value
	If '$Match(name, "^[A-Za-z0-9!#$%&'*+.^_`|~-]{1,64}$") || (value = "") || ($ZStrip(value, "*C") '= value) Quit 0
	Do request.SetHeader(name, value)
	Quit 1
}

/// The session id of the server's answer to an initialize (its Mcp-Session-Id header), or "" for a server that has none or whose id holds a control character.
ClassMethod SessionOf(response As %Net.HttpResponse) As %String [ Private ]
{
	Set id = $ZStrip(response.GetHeader("MCP-SESSION-ID"), "<>W")
	Quit $Select($ZStrip(id, "*C") = id: id, 1: "")
}

/// The result of the JSON-RPC answer in the response, which is a JSON body or a text/event-stream body: "" with result, or failed when the body is longer than MAXBODY, is
/// not JSON-RPC, answers another id than 1, holds an error object or holds no result object.
ClassMethod Decode(response As %Net.HttpResponse, Output result As %DynamicObject) As %String [ Private ]
{
	Set result = ""
	Set text = ..BodyOf(response)
	If text = "" Quit "failed"
	If $ZConvert($Piece(response.ContentType, ";", 1), "L") = "text/event-stream" {
		Set message = ..FirstMessage(text)
	} Else {
		Set message = ..Parse(text)
	}
	If '$IsObject(message) || (message.%GetTypeOf("error") '= "unassigned") || (message.%GetTypeOf("result") '= "object") || (message.%Get("id") '= 1) Quit "failed"
	Set result = message.result
	Quit ""
}

/// The text of the response body (UTF-8 decoded), or "" when there is none or it is longer than MAXBODY.
ClassMethod BodyOf(response As %Net.HttpResponse) As %String [ Private ]
{
	Set data = response.Data
	If '$IsObject(data) Quit $Select($Length(data) > ..#MAXBODY: "", 1: data _ "")
	If data.Size > ..#MAXBODY Quit ""
	Set text = data.Read(..#MAXBODY)
	If data.%ClassName(1) '[ "Character" Set text = $ZConvert(text, "I", "UTF8")
	Quit text
}

/// The JSON object in the text, or "" for text that is not a JSON object.
ClassMethod Parse(text As %String) As %DynamicObject [ Private ]
{
	Set message = ""
	Try {
		Set value = {}.%FromJSON(text)
		If $IsObject(value) && (value.%ClassName(1) = "%Library.DynamicObject") Set message = value
	} Catch {
		Set message = ""
	}
	Quit message
}

/// The first JSON-RPC message of a text/event-stream body that answers the request (id 1): the data lines of each event (a line that starts data:, without that and one
/// space after it), joined by line feeds, are the message; an event ends at an empty line or at the end of the body.
ClassMethod FirstMessage(text As %String) As %DynamicObject [ Private ]
{
	Set found = ""
	Set data = ""
	Set lines = $Length(text, $Char(10))
	For i = 1:1:lines + 1 {
		Set line = $Select(i > lines: "", 1: $ZStrip($Piece(text, $Char(10), i), ">", $Char(13)))
		If line '= "" {
			If $Extract(line, 1, 5) = "data:" {
				Set value = $Extract(line, 6, *)
				If $Extract(value) = " " Set value = $Extract(value, 2, *)
				Set data = data _ $Select(data = "": "", 1: $Char(10)) _ value
			}
			Continue
		}
		If data '= "" {
			Set message = ..Parse(data)
			Set data = ""
			If $IsObject(message) && (message.%Get("id") = 1) {
				Set found = message
				Quit
			}
		}
	}
	Quit found
}

/// Splits an http:// or https:// url into the host (a name, an IPv4 address or a bracketed IPv6 address such as [::1]), the port (the scheme's default
/// when none), whether it is https and the path with its query (a query straight after the host gets the path /, and a fragment is dropped, as a client
/// sends none). 1 when it has a host and no user information, else 0 and the outputs are empty.
ClassMethod Endpoint(url As %String, Output server As %String, Output port As %Integer, Output https As %Boolean, Output path As %String) As %Boolean
{
	Set server = "", port = "", https = 0, path = ""
	Set scheme = $ZConvert($Piece(url, "://", 1), "L")
	If ($Length(url, "://") < 2) || '$ListFind($ListBuild("http", "https"), scheme) Quit 0
	Set rest = $Piece(url, "://", 2, *)
	Set cut = $Locate(rest, "[/?#]")
	Set authority = $Select(cut: $Extract(rest, 1, cut - 1), 1: rest)
	Set tail = $Piece($Select(cut: $Extract(rest, cut, *), 1: ""), "#", 1)
	If $Extract(tail) = "?" Set tail = "/" _ tail
	If '$Match(authority, "^([A-Za-z0-9][A-Za-z0-9._-]*|\[[0-9A-Fa-f:.]+\])(:[0-9]{1,5})?$") Quit 0
	If '$Match(tail, "^(/[^\s\p{Cc}#]*)?$") Quit 0
	Set bracket = ($Extract(authority) = "[")
	Set host = $Select(bracket: $Piece(authority, "]", 1) _ "]", 1: $Piece(authority, ":", 1))
	Set given = $Select(bracket: $Extract($Piece(authority, "]", 2), 2, *), 1: $Piece(authority, ":", 2))
	Set number = $Select(given '= "": +given, scheme = "https": 443, 1: 80)
	If (number < 1) || (number > 65535) Quit 0
	Set server = host
	Set port = number
	Set https = (scheme = "https")
	Set path = tail
	Quit 1
}

}
