/// Tests of OcuTalon's own MCP server over real HTTP against the instance's own web server (Story 28.3; AD-21, AD-24; R-28.3-1). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), through
/// Test.Mcp.ServiceCase, which creates and deletes the fixture users and roles. They call GET /mcp/ocutalon/v1/services and POST /mcp/ocutalon/v1/tool_call, signed in with a password in the
/// Authorization header:
///   - TestRefusals (AC 3): an anonymous caller and a wrong password get 401 with the JSON code UNAUTHORIZED; a user who holds OcuTalonUser only, and a user who holds the three database read
///     grants without the resource, get 403; a user who holds OcuTalonMCPClient passes IRIS sign-in and the resource check, which it can do only through the application role (the client role holds
///     no database read), and gets 502 GATEWAY_REQUIRED, so the web server serves no tool directly; no call of any of them runs a tool, which the audit log shows (no served entry).
/// What iris-mcp-server does with the same request is not measured here (Story 28.5).
Class OcuTalon.Test.Mcp.ServiceHttp Extends OcuTalon.Test.Mcp.ServiceCase
{

Parameter BASE = "/mcp/ocutalon/v1/";

/// GET (method GET, to the services path) or POST (to the tool call path, with a tool call body) as the user with the password ("" for no Authorization header); the status, and the body as an
/// object in body (empty for a body that is not JSON).
Method Call(method As %String, user As %String, password As %String, Output body As %DynamicObject) As %Integer [ Private ]
{
	Set body = {}
	Set request = ##class(%Net.HttpRequest).%New()
	Set request.Server = "127.0.0.1"
	Set request.Port = ..#PORT
	Set request.FollowRedirect = 0
	If user '= "" Do request.SetHeader("Authorization", "Basic " _ $SYSTEM.Encryption.Base64Encode(user _ ":" _ password, 1))
	If method = "POST" {
		Set request.ContentType = "application/json"
		Do request.EntityBody.Write({"tool": "check_status", "args": {}}.%ToJSON())
		Set sc = request.Post(..#BASE _ "tool_call")
	} Else {
		Set sc = request.Get(..#BASE _ "services")
	}
	If $SYSTEM.Status.IsError(sc) || '$IsObject(request.HttpResponse) Quit 0
	Try {
		Set text = request.HttpResponse.Data.Read(3000000)
		Set body = ##class(%DynamicAbstractObject).%FromJSON(text)
	} Catch {
		Set body = {}
	}
	Quit request.HttpResponse.StatusCode
}

/// Asserts the status and, when code is given, the JSON code of the body, for both endpoints.
Method AssertBoth(user As %String, password As %String, status As %Integer, code As %String, label As %String) [ Private ]
{
	For method = "GET", "POST" {
		Set got = ..Call(method, user, password, .body)
		Do $$$AssertEquals(got, status, label _ ": " _ method _ " answers " _ status)
		If code '= "" Do $$$AssertEquals(body.%Get("code"), code, label _ ": " _ method _ " answers the code " _ code)
	}
}

Method TestRefusals()
{
	If '..Guard() Quit
	Set resources = $Parameter("OcuTalon.Install.Step.Mcp", "APPROLERESOURCES")
	Set plain = ..NewUser("p", "OcuTalonUser", .plainPassword)
	Do ..NewRole(..#ROLEREADS, resources)
	Set reads = ..NewUser("d", ..#ROLEREADS, .readsPassword)
	Set client = ..NewUser("c", $Parameter("OcuTalon.Install.Step.Mcp", "CLIENTROLE"), .clientPassword)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do ..AssertBoth("", "", 401, "UNAUTHORIZED", "an anonymous caller")
	Do ..AssertBoth(client, "WrongPassword1!", 401, "UNAUTHORIZED", "a wrong password")
	Do ..AssertBoth(plain, plainPassword, 403, "", "a user who holds OcuTalonUser only")
	Do ..AssertBoth(reads, readsPassword, 403, "", "a user with the three database read grants and not the resource")
	Do ..AssertBoth(client, clientPassword, 502, "GATEWAY_REQUIRED", "a user who holds OcuTalonMCPClient")
	Set served = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "MCP", "MCP", "")
	Set ran = 0
	Set iterator = served.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If $IsObject(entry.data) && ($Extract(entry.data.irisUser, 1, $Length(..#USER)) = ..#USER) Set ran = ran + 1
	}
	Do $$$AssertEquals(ran, 0, "no tool ran for any of them: the audit log has no served entry of a fixture user")
}

}
