/// The loopback mock MCP server of the tests (Story 35.1; AD-21, AD-22): a minimal MCP server over streamable HTTP that a test starts, points an
/// MCP Config Store entry at, and stops. It is a test fixture and never part of a production; Epic 22 reuses it. It is not a test case.
///   - Start(port, extra, header, expected) opens a listener in a job of its own on 127.0.0.1 only and on a free port (port, a port of 53200 to 53999
///     that is not in use) and answers once the listener is open. The listener is the %IO.ServerSocket one, whose Open with a timeout ignores the
///     interface it is given when its ConnectionQueueSize is above 0 and its KeepAliveInterval is not -1 (the defaults); the mock sets
///     KeepAliveInterval to -1 and ConnectionQueueSize to BACKLOG, so that connections that arrive while the single job answers another wait in the
///     listener's queue and are not refused. With ConnectionQueueSize 5 a run of OcuTalon.Test.Mcp.Loopback was green (measured), so the loopback-only
///     bind holds (evidence 35-1-task0-mcp-attach.md). That the queue guards against connections refused under CI load is (inference): no run under
///     load was made.
///   - The tools it lists are zz_lookup (readOnlyHint true) and zz_delete_ticket (destructiveHint true), and one more tool of the same shape for each
///     name in the list extra, so that a test can offer a tool with the name of a tool the agent already has. Calling a tool answers a text.
///   - It answers initialize, notifications (202 with no body), tools/list and tools/call with plain application/json replies, which AI Hub's client
///     accepts. It keeps no session.
///   - When header names a header, every request is checked against expected, and the log records only whether it matched. The value is passed to the job
///     and compared there: it is never stored, logged or returned.
///   - Requests(port) is the log of the requests the mock answered, in order, as {"method", "tool", "auth"}: auth is none when no header is checked,
///     and matched, mismatch or absent otherwise. Calls(port, tool) counts the tools/call requests for a tool.
///   - Describe(port, text) sets the description that the mock lists for zz_lookup (its input schema stays), so that a test can change the tool between
///     two builds; Stop(port) clears it. Without it the description is "Looks up a ticket.".
///   - Stop(port) ends the listener and its job and leaves the log; Forget(port) removes the log. A test calls both in its teardown, so that no job and no
///     node outlive it. The state is under ^IRIS.Temp.OcuTalonMcpMock(port).
Class OcuTalon.Test.Mcp.Mock
{

/// The only interface the listener binds to.
Parameter INTERFACE = "127.0.0.1";

/// The range of the ports that Start tries: FIRSTPORT to FIRSTPORT + PORTCOUNT - 1.
Parameter FIRSTPORT = 53200;

Parameter PORTCOUNT = 800;

/// The most seconds Start waits for the listener of one try.
Parameter OPENWAIT = 8;

/// The length of the listener's queue of connections that wait to be accepted.
Parameter BACKLOG = 5;

/// The most seconds Stop waits for the job to end before it ends the job.
Parameter STOPWAIT = 8;

/// Starts a mock. port is the port the listener is open on. extra is a list of tool names, header the name of the header to check and expected its
/// value (empty to check none). Returns an error when no port of the range could be opened.
ClassMethod Start(Output port As %Integer, extra As %List = "", header As %String = "", expected As %String = "") As %Status
{
	Set port = 0
	For attempt = 1:1:20 {
		Set candidate = ..#FIRSTPORT + $Random(..#PORTCOUNT)
		Kill ^IRIS.Temp.OcuTalonMcpMock(candidate)
		Job ..Serve(candidate, extra, header, expected):(:::):10
		If '$Test Continue
		Set job = $ZChild
		Set state = ..WaitFor(candidate, "ready,failed", ..#OPENWAIT)
		If state = "ready" {
			Set ^IRIS.Temp.OcuTalonMcpMock(candidate, "job") = job
			Set port = candidate
			Quit
		}
		Do ..End(candidate, job)
		Kill ^IRIS.Temp.OcuTalonMcpMock(candidate)
	}
	If port = 0 Quit $$$ERROR($$$GeneralError, "The mock MCP server found no free port to listen on")
	Quit $$$OK
}

/// Ends the listener of the mock on the port and its job, and leaves the log. It does nothing for a port with no mock.
ClassMethod Stop(port As %Integer)
{
	If '$Data(^IRIS.Temp.OcuTalonMcpMock(port)) Quit
	Set job = $Get(^IRIS.Temp.OcuTalonMcpMock(port, "job"))
	Do ..End(port, job)
}

/// Sets the description that the mock on the port lists for zz_lookup, until Stop.
ClassMethod Describe(port As %Integer, text As %String)
{
	Set ^IRIS.Temp.OcuTalonMcpMock(port, "description") = text
}

/// Removes the log of the port.
ClassMethod Forget(port As %Integer)
{
	Kill ^IRIS.Temp.OcuTalonMcpMock(port)
}

/// The requests the mock answered on the port, in order, as a %DynamicArray of {"method", "tool", "auth"}.
ClassMethod Requests(port As %Integer) As %DynamicArray
{
	Set requests = []
	Set n = ""
	For {
		Set n = $Order(^IRIS.Temp.OcuTalonMcpMock(port, "req", n), 1, entry)
		Quit:n=""
		Do requests.%Push({"method": ($List(entry, 1)), "tool": ($List(entry, 2)), "auth": ($List(entry, 3))})
	}
	Quit requests
}

/// The number of tools/call requests for the tool that the mock on the port answered.
ClassMethod Calls(port As %Integer, tool As %String) As %Integer
{
	Set count = 0
	Set iterator = ..Requests(port).%GetIterator()
	While iterator.%GetNext(, .request) {
		If (request.method = "tools/call") && (request.tool = tool) Set count = count + 1
	}
	Quit count
}

/// 1 while the job of the mock on the port is alive.
ClassMethod Running(port As %Integer) As %Boolean
{
	Set job = $Get(^IRIS.Temp.OcuTalonMcpMock(port, "job"))
	Quit $Select(job = "": 0, 1: ##class(%SYS.ProcessQuery).%ExistsId(job))
}

/// Asks the job to stop, waits for it, and ends it when it did not.
ClassMethod End(port As %Integer, job As %String) [ Private ]
{
	Set ^IRIS.Temp.OcuTalonMcpMock(port, "stop") = 1
	Set state = ..WaitFor(port, "stopped,failed", ..#STOPWAIT)
	If (state = "") && (job '= "") && ##class(%SYS.ProcessQuery).%ExistsId(job) Do $SYSTEM.Process.Terminate(job)
	Kill ^IRIS.Temp.OcuTalonMcpMock(port, "job"), ^IRIS.Temp.OcuTalonMcpMock(port, "stop"), ^IRIS.Temp.OcuTalonMcpMock(port, "description")
}

/// The state of the mock on the port once it is one of the states (comma-separated), or "" after the seconds.
ClassMethod WaitFor(port As %Integer, states As %String, seconds As %Integer) As %String [ Private ]
{
	Set until = $ZHorolog + seconds
	Set list = $ListFromString(states)
	Set state = ""
	While $ZHorolog < until {
		Set state = $Get(^IRIS.Temp.OcuTalonMcpMock(port, "state"))
		If $ListFind(list, state) Quit
		Hang 0.05
	}
	Quit $Select($ListFind(list, state): state, 1: "")
}

/// The job: the listener and its accept loop. It runs until the stop node is set.
ClassMethod Serve(port As %Integer, extra As %List, header As %String, expected As %String)
{
	Set socket = ##class(%IO.ServerSocket).%New()
	Set socket.LocalInterface = ..#INTERFACE
	Set socket.ConnectionQueueSize = ..#BACKLOG
	Set socket.KeepAliveInterval = -1
	Set timeout = 5
	If 'socket.Open(port, .timeout, .sc) {
		Set ^IRIS.Temp.OcuTalonMcpMock(port, "state") = "failed"
		Quit
	}
	Set ^IRIS.Temp.OcuTalonMcpMock(port, "state") = "ready"
	While '$Get(^IRIS.Temp.OcuTalonMcpMock(port, "stop")) {
		Set timeout = 1
		If 'socket.Listen(.timeout, .sc) Continue
		Try {
			Do ..Connection(socket, port, extra, header, expected)
		} Catch exception {
			Set ^IRIS.Temp.OcuTalonMcpMock(port, "error") = exception.Name
		}
		Do socket.Disconnect()
	}
	Do socket.Close()
	Set ^IRIS.Temp.OcuTalonMcpMock(port, "state") = "stopped"
}

/// Answers the one request of a connection and closes it (Connection: close), so that a client that keeps its connection never holds the single job away
/// from the next client.
ClassMethod Connection(socket As %IO.ServerSocket, port As %Integer, extra As %List, header As %String, expected As %String) [ Private ]
{
	Set cr = $Char(13)
	Set timeout = 3
	Set line = $ZStrip(socket.ReadLine(8000, .timeout, .sc), "<>", cr)
	If line = "" Quit
	Set length = 0
	Set auth = $Select(header = "": "none", 1: "absent")
	For {
		Set timeout = 3
		Set field = $ZStrip(socket.ReadLine(8000, .timeout, .sc), "<>", cr)
		If field = "" Quit
		Set name = $ZConvert($Piece(field, ":", 1), "L")
		If name = "content-length" Set length = +$ZStrip($Piece(field, ":", 2, *), "<>W")
		If (header '= "") && (name = $ZConvert(header, "L")) {
			Set auth = $Select($ZStrip($Piece(field, ":", 2, *), "<>W") = expected: "matched", 1: "mismatch")
		}
	}
	Set body = ""
	While $Length(body) < length {
		Set timeout = 3
		Set body = body _ socket.Read(length - $Length(body), .timeout, .sc)
		If timeout = 0 Quit
	}
	Set reply = ..Reply(body, extra, port, .method, .tool, .code)
	Set ^IRIS.Temp.OcuTalonMcpMock(port, "req", $Increment(^IRIS.Temp.OcuTalonMcpMock(port, "req"))) = $ListBuild(method, tool, auth)
	Do socket.Write("HTTP/1.1 " _ code _ $Char(13, 10) _ "Content-Type: application/json" _ $Char(13, 10) _ "Content-Length: " _ $Length(reply) _ $Char(13, 10) _ "Connection: close" _ $Char(13, 10) _ $Char(13, 10) _ reply)
	Do socket.Flush()
}

/// The reply to one JSON-RPC body, with the method and the tool name of the request and the status line code.
ClassMethod Reply(body As %String, extra As %List, port As %Integer, Output method As %String, Output tool As %String, Output code As %String) As %String [ Private ]
{
	Set method = "", tool = "", code = "200 OK"
	Set request = ""
	Try {
		Set request = ##class(%DynamicAbstractObject).%FromJSON(body)
	} Catch {
		Set request = ""
	}
	If '$IsObject(request) Quit ""
	Set method = request.%Get("method")
	Set id = request.%Get("id")
	If $Extract(method, 1, 14) = "notifications/" {
		Set code = "202 Accepted"
		Quit ""
	}
	If method = "initialize" {
		Set answer = {"jsonrpc": "2.0", "id": (id), "result": {"protocolVersion": "2025-03-26", "capabilities": {"tools": {}}, "serverInfo": {"name": "zz-mock", "version": "1"}}}
		Quit answer.%ToJSON()
	}
	If method = "tools/list" {
		Set tools = []
		Set lookup = $Get(^IRIS.Temp.OcuTalonMcpMock(port, "description"), "Looks up a ticket.")
		Do tools.%Push({"name": "zz_lookup", "description": (lookup), "inputSchema": {"type": "object", "properties": {"id": {"type": "string"}}}, "annotations": {"readOnlyHint": true}})
		Do tools.%Push({"name": "zz_delete_ticket", "description": "Deletes a ticket.", "inputSchema": {"type": "object", "properties": {"id": {"type": "string"}}}, "annotations": {"destructiveHint": true}})
		Set position = 0
		While $ListNext(extra, position, name) {
			Do tools.%Push({"name": (name), "description": "Another tool of the mock.", "inputSchema": {"type": "object", "properties": {}}})
		}
		Set answer = {"jsonrpc": "2.0", "id": (id), "result": {"tools": (tools)}}
		Quit answer.%ToJSON()
	}
	If method = "tools/call" {
		Set tool = request.%Get("params").%Get("name")
		Set answer = {"jsonrpc": "2.0", "id": (id), "result": {"content": [{"type": "text", "text": ("The mock ran " _ tool)}]}}
		Quit answer.%ToJSON()
	}
	Set answer = {"jsonrpc": "2.0", "id": (id), "error": {"code": -32601, "message": "The mock has no such method"}}
	Quit answer.%ToJSON()
}

}
