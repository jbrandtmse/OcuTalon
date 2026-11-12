/// OcuTalon's minimal MCP client over HTTP (AD-21, AD-31): the part of the MCP wire protocol that OcuTalon speaks itself, with ObjectScript timeouts, so that a
/// server that accepts a connection and never answers cannot hold a runner job (AI Hub's own client has no deadline). Story 22.3 adds tools/call to this class.
///   - Probe sends one JSON-RPC initialize to the server's url and answers "" when the server answers with any HTTP status (a status line within the bound is
///     an answer, even when the body that follows never completes, as an event stream may not), unreachable when it gives no
///     response (a timeout, a refused connection, a failed TLS handshake) and failed when the url is not http:// or https:// with a host. It sends no credential
///     (a server that wants one answers 401, which is an answer), makes no AI Hub or Python call, follows no redirect and is bounded by seconds for the
///     connection, for each write (an https handshake runs in the first write) and for the answer. An https url uses the client SSL configuration of the installer (Install.Step.SSL), which verifies the server.
///   - It never throws and never logs, stores or returns the url, which can name a host that an admin registered: the answer is a code word.
Class OcuTalon.Mcp.Client
{

/// The seconds that Probe waits to open the connection, and again for the answer.
Parameter PROBESECONDS = 2;

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
		If '..Endpoint($Get(url), .server, .port, .https, .path) Quit
		Set request = ##class(%Net.HttpRequest).%New()
		Set request.Server = server
		Set request.Port = port
		Set request.OpenTimeout = seconds
		Set request.Timeout = seconds
		Set request.WriteTimeout = $Select(seconds < 2: 2, 1: seconds)
		Set request.FollowRedirect = 0
		If https {
			Set request.Https = 1
			Set request.SSLConfiguration = ##class(OcuTalon.Install.Step.SSL).#NAME
		}
		Set request.ContentType = "application/json"
		Do request.SetHeader("Accept", "application/json, text/event-stream")
		Set body = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": (..#PROTOCOLVERSION), "capabilities": {}, "clientInfo": {"name": (..#CLIENTNAME), "version": (..#CLIENTVERSION)}}}
		Do request.EntityBody.Write(body.%ToJSON())
		Set sc = request.Post(path)
		Set answer = $Select($IsObject(request.HttpResponse) && (+request.HttpResponse.StatusCode > 0): "", 1: "unreachable")
	} Catch {
		Set answer = "failed"
	}
	Quit answer
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
