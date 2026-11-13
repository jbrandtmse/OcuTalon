/// Tests of the MCP settings routes (Story 21.4; AD-1, AD-4, AD-13, AD-19, AD-21), called with stand-in request and response objects through
/// Test.Web.McpSettingsProbe and a CSP session whose OcuTalon.SessionRef is a fixture session. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): the routes go through the real production, Commands.Submit, CommandsIn, the real McpOps and the real SettingsOps. The roles of the signed-in
/// user come from Test.Web.ApiProbe's seam. Every test makes its own `zz` servers, rows, entries and wallet objects and removes them again.
///   - TestAddListClassifyRemove: an admin's add answers 200 added, McpOps' job writes the entry (a bearer secret:// reference) and the wallet key, GET lists the server
///     with its address and no secret, a classification answers 200 saved and shows in the list, and the remove answers 200 removed and drops the row, entry, key and
///     collection; the secret is in no message, log row, audit entry, trace global or ^OcuTalon* global, and the handoff is gone;
///   - TestAddRefusals: every refused add (a bad or long name, an address that is not https:// or loopback, user information, @{ in a value, a secret that is not a
///     string, is too long or has a space or a control character, a plain http:// address to another computer with and without a secret) answers 400 bad_mcp_server
///     with its fields, offers nothing to the handoff, submits nothing and writes nothing; a name that exists is mapped to its field after the handoff is discarded;
///   - TestAddressWithQuery (ruling B2, T12): an address that holds a ? or a # (a query string or a fragment) is refused by the route (400 bad_mcp_server, the field address, the
///     text of Mcp.Ops MESSAGEQUERY, with and without a secret, nothing offered, submitted or written) and by McpOps itself (bad_address with the same text, nothing written or audited,
///     the handoff untaken); a plain http:// address to another computer that also holds a ? keeps the address text;
///   - TestBadBodies, TestClassifyErrors, TestRemoveUnknown: the shapes and the 400 and 404 answers of classify and remove, with nothing submitted;
///   - TestNotAdmin: a user without OcuTalonAdmin gets 403 not_admin from OnPreDispatch and from each route, and nothing is offered or submitted;
///   - TestOnlineDemo: with the online-demo flag set every route answers 409 not_available with the accepted text before it reads the body, and nothing is offered,
///     submitted or written;
///   - TestHandoffDiscardedOnFailure: when the submit fails or throws, the add answers 500 and the secret's handoff is discarded all the same.
Class OcuTalon.Test.Web.McpSettingsApi Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Web.McpSettingsProbe";

Parameter URL = "http://127.0.0.1:9/mcp";

Parameter TEXT = "Couldn't save. Nothing was changed.";

Parameter OFFTEXT = "MCP servers are off on the online demo: nobody can add one, and OcuTalon reaches none. They work on your own install.";

/// The online-demo flag before the tests.
Property SavedOnline As %String;

/// The Ref of the fixture session.
Property A As %String;

/// The TraceRefs of the fixture session, for the clean-up of the messages.
Property Traces As %DynamicArray;

/// The number of the test, in the names of its servers, and their names (comma-separated).
Property Number As %Integer;

Property Names As %String(MAXLEN = "");

/// The reason why the tests fail, or empty.
Property Missing As %String(MAXLEN = 200);

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..Missing = ""
	If '##class(Ens.Director).IsProductionRunning(.name) || (name '= "OcuTalon.Production") {
		Set ..Missing = "OcuTalon.Production does not run in OCUTALON: this class runs in throwaways and CI only (Rule 21)"
	}
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Set ..Traces = []
	Set ..Names = ""
	Set ..Number = $Increment(^OcuTalonTest("McpSettingsApi", "n"))
	Kill ^OcuTalonTest("McpSettingsProbe")
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set ..A = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Do ..Traces.%Push(##class(OcuTalon.Data.Session).RefIndexOpen(..A).TraceRef)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("ApiProbe", "roles")
	Kill ^OcuTalonTest("McpSettingsProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Traces)
	Do ..Clean()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do $$$AssertEquals(..Leftovers(), "", "the test leaves no row, entry, key or collection behind")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("ApiProbe", "roles")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $$$OK
}

Method TestAddListClassifyRemove()
{
	If '..Guard() Quit
	Set server = ..Server("a")
	Set name = "AI.MCP.OcuTalon_"_server
	Set collection = "OcuTalon_MCP_"_server
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set log = ##class(OcuTalon.Test.Web.WebhookTools).LastLog()
	Set secret = ..NewSecret()
	Set body = ..Call("Add", {"name": (server), "address": (..#URL), "secret": (secret)}.%ToJSON(), , , .response)
	Do $$$AssertEquals(response.Status, "200 OK", "an admin's add answers 200")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.result_"|"_answer.message, "added|"_##class(OcuTalon.Mcp.Ops).#MESSAGEADDED, "added, with McpOps' message")
	Do $$$AssertEquals(answer.%Size(), 2, "and only result and message")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("McpSettingsProbe", "handoffs")), 1, "the secret was offered once")
	Do $$$AssertTrue(##class(OcuTalon.Mcp.Server).NameIndexExists(server), "the row is written")
	Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).GetDetails(name, .details, 0, 0), "the entry is read without resolving its secret")
	Do $$$AssertEquals(details.url_"|"_details.auth.type_"|"_details.auth.token, ..#URL_"|bearer|secret://"_collection_".Key#token", "McpOps' job wrote the address and the bearer reference")
	Do $$$AssertEquals(##class(%Wallet.Secret).Exists(collection_".Key"), 1, "and the wallet key")
	Do $$$AssertEquals(+(##class(%Wallet.KeyValue).GetSecretValue(collection_".Key") [ secret), 1, "which holds the secret")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "MCP", "MCP", server).%Size(), 1, "one MCP audit entry names the server")
	// the list
	Set body = ..Call("List", , , , .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the list answers 200")
	Set row = ..ServerOf(body, server)
	Do $$$AssertTrue($IsObject(row), "the server is listed")
	If $IsObject(row) Do $$$AssertEquals(row.address_"|"_row.status_"|"_row.tools_"|"_row.unclassified_"|"_row.pending, ..#URL_"||0|0|0", "with its address, no status yet and no tools")
	Do $$$AssertEquals(+(body [ secret), 0, "the list holds no secret")
	Do $$$AssertEquals(+(body [ "secret://"), 0, "and no secret:// reference")
	// a classification of a tool row that a runner would have written
	Set tool = ##class(OcuTalon.Mcp.ToolClassification).%New()
	Set tool.Server = server
	Set tool.Tool = "zz_lookup"
	Set tool.Classification = "unclassified"
	Set tool.Fingerprint = "zzfp"
	Set tool.ChangedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(tool.%Save(), "a fixture tool row is saved")
	Kill tool
	Set body = ..Call("Classify", {"server": (server), "tool": "zz_lookup", "classification": "read-only"}.%ToJSON(), , , .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a classification answers 200")
	Do $$$AssertEquals(body, {"result": "saved", "message": "Saved"}.%ToJSON(), "saved")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_lookup").Classification, "read-only", "the row is read-only")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Tool", "Tool", server).%Size(), 1, "and one Tool audit entry names the server")
	Set row = ..ServerOf(..Call("List", , , , .response), server)
	If $IsObject(row) Do $$$AssertEquals(row.tools_"|"_row.unclassified, "1|0", "the list counts one tool and no unclassified")
	Set listed = {}.%FromJSON(..Call("List", , , , .response)).tools
	Set found = ""
	Set iterator = listed.%GetIterator()
	While iterator.%GetNext(, .item) {
		If item.server = server Set found = item.name_"|"_item.classification_"|"_item.status
	}
	Do $$$AssertEquals(found, "zz_lookup|read-only|available", "and the tools array shows it")
	// the remove
	Set body = ..Call("Remove", , , server, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the remove answers 200")
	Do $$$AssertEquals(body, {"result": "removed", "message": (##class(OcuTalon.Mcp.Ops).#MESSAGEREMOVED)}.%ToJSON(), "removed")
	Do $$$AssertEquals(..Leftovers(), "", "the row, the tool rows, the entry, the key and the collection are gone")
	Do $$$AssertEquals($IsObject(..ServerOf(..Call("List", , , , .response), server)), 0, "and the list has no server")
	// the secret is nowhere
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", , , secret).%Size(), 0, "no OcuTalon audit entry holds the secret")
	Do $$$AssertTrue(##class(OcuTalon.Test.Web.WebhookTools).LogText(log) '[ secret, "no event log row holds it")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(secret), "", "no trace global (message body, header or log row) holds it")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).Leaks(secret), "", "and no ^OcuTalon* global holds it")
	Do $$$AssertTrue(##class(OcuTalon.Test.Web.WebhookTools).Columns("OcuTalon_Msg_Command.AddMcpServer") '[ secret, "the stored AddMcpServer messages do not hold it")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Handoff FROM OcuTalon_Msg_Command.AddMcpServer WHERE Server = ?", server)
	Set uris = 0
	While result.%Next() {
		Set uri = result.%GetData(1)
		Set uris = uris + 1
		Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .gone, 0), "the handoff is gone")
		Do $$$AssertEquals(gone, "", "and held nothing")
	}
	Do $$$AssertEquals(uris, 1, "the command carried one handoff uri")
	Kill secret
}

Method TestAddRefusals()
{
	If '..Guard() Quit
	Set refusedMarker = ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.refusedExpansion", "@{")
	Set name = ##class(OcuTalon.Mcp.Ops).#MESSAGENAME
	Set address = ##class(OcuTalon.Mcp.Ops).#MESSAGEADDRESS
	Set secretText = ##class(OcuTalon.Web.McpSettings).#MESSAGESECRET
	Set ok = ..#URL
	Set good = ..Server("r")
	Set long = $Translate($Justify("", 4097), " ", "a")
	Set cases = ""
	Set cases = cases_$ListBuild(..Case("a name that starts with a digit", {"name": "1bad", "address": (ok)}, {"name": (name)}))
	Set cases = cases_$ListBuild(..Case("a name of 41 characters", {"name": ($Translate($Justify("", 41), " ", "a")), "address": (ok)}, {"name": (name)}))
	Set cases = cases_$ListBuild(..Case("a name with a space", {"name": "a b", "address": (ok)}, {"name": (name)}))
	Set cases = cases_$ListBuild(..Case("an empty name", {"name": "", "address": (ok)}, {"name": (name)}))
	Set cases = cases_$ListBuild(..Case("@{ in the name", {"name": "a@{env:X}", "address": (ok)}, {"name": (refusedMarker)}))
	Set cases = cases_$ListBuild(..Case("a name that ends with a line feed", {"name": (good_$Char(10)), "address": (ok)}, {"name": (name)}))
	Set cases = cases_$ListBuild(..Case("an http address to another computer", {"name": (good), "address": "http://192.0.2.7/mcp"}, {"address": (address)}))
	Set cases = cases_$ListBuild(..Case("the same with a secret (the secret never goes out over plain HTTP)", {"name": (good), "address": "http://192.0.2.7/mcp", "secret": "zz-plain-secret-0123456789"}, {"address": (address)}))
	Set cases = cases_$ListBuild(..Case("user information", {"name": (good), "address": "https://user:pw@example.com/mcp"}, {"address": (address)}))
	Set cases = cases_$ListBuild(..Case("another scheme", {"name": (good), "address": "ftp://example.com/mcp"}, {"address": (address)}))
	Set cases = cases_$ListBuild(..Case("an empty address", {"name": (good), "address": ""}, {"address": (address)}))
	Set cases = cases_$ListBuild(..Case("@{ in the address", {"name": (good), "address": "https://example.com/@{env:X}"}, {"address": (refusedMarker)}))
	Set cases = cases_$ListBuild(..Case("an address of 2,001 characters", {"name": (good), "address": ("https://example.com/"_$Translate($Justify("", 1981), " ", "a"))}, {"address": (address)}))
	Set cases = cases_$ListBuild(..Case("a secret that is not a string", {"name": (good), "address": (ok), "secret": 5}, {"secret": (secretText)}))
	Set cases = cases_$ListBuild(..Case("a null secret", {"name": (good), "address": (ok), "secret": null}, {"secret": (secretText)}))
	Set cases = cases_$ListBuild(..Case("a secret of 4,097 characters", {"name": (good), "address": (ok), "secret": (long)}, {"secret": (secretText)}))
	Set cases = cases_$ListBuild(..Case("a secret with a space", {"name": (good), "address": (ok), "secret": "ab cd"}, {"secret": (secretText)}))
	Set cases = cases_$ListBuild(..Case("a secret with a control character", {"name": (good), "address": (ok), "secret": ("ab"_$Char(9)_"cd")}, {"secret": (secretText)}))
	Set cases = cases_$ListBuild(..Case("a secret with a character that is not ASCII", {"name": (good), "address": (ok), "secret": ("caf"_$Char(233))}, {"secret": (secretText)}))
	Set cases = cases_$ListBuild(..Case("@{ in the secret", {"name": (good), "address": (ok), "secret": "zz@{env:X}"}, {"secret": (refusedMarker)}))
	Set cases = cases_$ListBuild(..Case("a bad name, address and secret together", {"name": "1bad", "address": "ftp://x", "secret": "a b"}, {"name": (name), "address": (address), "secret": (secretText)}))
	Set before = ..Rows()
	Set wallet = ..Wallet()
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $List(case, 1)
		Set expected = $List(case, 3)
		Kill ^OcuTalonTest("McpSettingsProbe")
		Set body = ..Call("Add", $List(case, 2), , , .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", label_": 400")
		Set answer = {}.%FromJSON(body)
		Do $$$AssertEquals(answer.error.code_"|"_answer.error.message, "bad_mcp_server|"_..#TEXT, label_": bad_mcp_server with the plain message")
		Do $$$AssertEquals(answer.fields.%ToJSON(), expected, label_": the fields are as expected")
		Do $$$AssertEquals(+$Get(^OcuTalonTest("McpSettingsProbe", "handoffs")), 0, label_": nothing was offered to the handoff")
		Do $$$AssertEquals(+$Get(^OcuTalonTest("McpSettingsProbe", "submits")), 0, label_": nothing was submitted")
		Do $$$AssertEquals(+(body [ "zz-plain-secret"), 0, label_": the answer does not echo the secret")
	}
	Do $$$AssertEquals(..Rows(), before, "no row was written")
	Do $$$AssertEquals(..Wallet(), wallet, "and the wallet is unchanged")
	Do $$$AssertEquals(..Leftovers(), "", "no entry, key or collection was written")
	// a name that exists: McpOps refuses it, after the handoff was made, and the route discards the handoff
	Do ..MakeRow(good)
	Kill ^OcuTalonTest("McpSettingsProbe")
	Set body = ..Call("Add", {"name": (good), "address": (ok), "secret": "zz-exists-secret-0123456789"}.%ToJSON(), , , .response)
	Do $$$AssertEquals(response.Status, "400 Bad Request", "a name that exists is 400")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.error.code_"|"_answer.fields.name, "bad_mcp_server|"_##class(OcuTalon.Mcp.Ops).#MESSAGEEXISTS, "bad_mcp_server with the field name and McpOps' text")
	Do $$$AssertEquals(answer.fields.%Size(), 1, "and no other field")
	Set uri = $Get(^OcuTalonTest("McpSettingsProbe", "uri"))
	Do $$$AssertTrue(uri '= "", "the command carried a handoff uri")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), "which is discarded")
	Do $$$AssertEquals(left, "", "and held nothing")
	Do $$$AssertEquals(..Wallet(), wallet, "nothing was written to the wallet")
	Do $$$AssertEquals(##class(%ConfigStore.Configuration).Exists("AI.MCP.OcuTalon_"_good), 0, "and no entry")
}

/// Ruling B2 (T12): the route and McpOps both refuse an address with a ? or a # before anything is offered or written. mutation: the check skipped in
/// Web.McpSettings AddFields -> the route cases red; skipped in Mcp.Ops OnAdd -> the McpOps cases red.
Method TestAddressWithQuery()
{
	If '..Guard() Quit
	Set query = ##class(OcuTalon.Mcp.Ops).#MESSAGEQUERY
	Set address = ##class(OcuTalon.Mcp.Ops).#MESSAGEADDRESS
	Do $$$AssertEquals(query, "An MCP server's address can't hold a query string (the part after ?). Put a key in Secret instead. Nothing was changed.", "T12's text, word for word")
	Set good = ..Server("q")
	Set secret = ..NewSecret()
	Set before = ..Rows()
	Set wallet = ..Wallet()
	Set messages = ..Messages()
	// the route
	Set urls = $ListBuild("https://example.com/mcp?token=abc", "https://example.com/mcp#frag", "https://example.com/mcp?", "https://example.com/mcp#", "http://127.0.0.1:9/mcp?x=1", "https://example.com:8443/a?b=c")
	Set position = 0
	While $ListNext(urls, position, url) {
		For withSecret = 0, 1 {
			Set body = {"name": (good), "address": (url)}
			If withSecret Set body.secret = secret
			Kill ^OcuTalonTest("McpSettingsProbe")
			Set text = ..Call("Add", body.%ToJSON(), , , .response)
			Set label = "the route, '"_url_"'"_$Select(withSecret: " with a secret", 1: "")
			Do $$$AssertEquals(response.Status, "400 Bad Request", label_": 400")
			Set answer = {}.%FromJSON(text)
			Do $$$AssertEquals(answer.error.code_"|"_answer.error.message, "bad_mcp_server|"_..#TEXT, label_": bad_mcp_server with the plain message")
			Do $$$AssertEquals(answer.fields.%ToJSON(), {"address": (query)}.%ToJSON(), label_": the field address with T12")
			Do $$$AssertEquals(+$Get(^OcuTalonTest("McpSettingsProbe", "handoffs")), 0, label_": nothing was offered to the handoff")
			Do $$$AssertEquals(+$Get(^OcuTalonTest("McpSettingsProbe", "submits")), 0, label_": nothing was submitted")
			Do $$$AssertEquals(+(text [ secret), 0, label_": the answer does not echo the secret")
		}
	}
	// a plain http:// address to another computer keeps its own refusal, whatever follows the path
	Kill ^OcuTalonTest("McpSettingsProbe")
	Set text = ..Call("Add", {"name": (good), "address": "http://192.0.2.7/mcp?token=abc", "secret": (secret)}.%ToJSON(), , , .response)
	Do $$$AssertEquals({}.%FromJSON(text).fields.%ToJSON(), {"address": (address)}.%ToJSON(), "an http address to another computer with a query keeps the address text")
	// McpOps itself, with the route's check out of the way: each address is refused with the same text, the handoff is not taken and nothing is written or audited
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set position = 0
	While $ListNext(urls, position, url) {
		Set command = ##class(OcuTalon.Msg.Command.AddMcpServer).%New()
		Set command.Server = good
		Set command.Url = url
		Set command.Origin = "web_admin"
		Set command.ActingUser = "zzadmin"
		Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put(secret, .uri), "McpOps, '"_url_"': a secret is offered")
		Set command.Handoff = uri
		Set probe = ##class(OcuTalon.Test.Mcp.OpsProbe).Shadow("CommandsIn", .sc)
		Do $$$AssertStatusOK(sc, "the probe of McpOps is made")
		Set sc = probe.MessageHandler(command, .result)
		Do $$$AssertStatusOK(sc, "the command is delivered")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|bad_address|"_query, "McpOps, '"_url_"': refused as bad_address with T12")
		Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .kept, 0), "McpOps did not take the handoff")
		Do $$$AssertEquals(kept, secret, "it still held the secret")
		Kill kept
		Do ##class(OcuTalon.Core.SecretHandoff).Discard(uri)
	}
	Do $$$AssertEquals(..Rows(), before, "no row was written")
	Do $$$AssertEquals(..Wallet(), wallet, "the wallet is unchanged")
	Do $$$AssertEquals(..Leftovers(), "", "no entry, key or collection was written")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "MCP", "MCP", good).%Size(), 0, "no audit entry was written")
	Do $$$AssertEquals(..Messages(), messages, "and no command of the route was stored")
	Kill secret
}

Method TestBadBodies()
{
	If '..Guard() Quit
	Set before = ..Rows()
	Set bodies = $ListBuild("", "[]", """text""", "{}", "{""name"":""zzx""}", "{""address"":""https://example.com""}", "{""name"":5,""address"":""https://example.com""}", "{""name"":""zzx"",""address"":5}", "{""name"":null,""address"":""https://example.com""}", "{""name"":""zzx"",""address"":""https://example.com"",""extra"":1}", "{""name"":""zzx"",""address"":""https://example.com"",""secret"":""a1"",""extra"":1}")
	Set position = 0
	While $ListNext(bodies, position, text) {
		Kill ^OcuTalonTest("McpSettingsProbe")
		Set body = ..Call("Add", text, , , .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", "add with "_text_" is 400")
		Set answer = {}.%FromJSON(body)
		Do $$$AssertEquals(answer.error.code, "bad_mcp_server", "bad_mcp_server")
		Do $$$AssertEquals(answer.fields.%Size(), 0, "with no fields")
		Do $$$AssertEquals(+$Get(^OcuTalonTest("McpSettingsProbe", "handoffs"))+$Get(^OcuTalonTest("McpSettingsProbe", "submits")), 0, "and nothing was offered or submitted")
	}
	Set bodies = $ListBuild("", "[]", "{}", "{""server"":""zzx"",""tool"":""t""}", "{""server"":""zzx"",""tool"":""t"",""classification"":5}", "{""server"":5,""tool"":""t"",""classification"":""risky""}", "{""server"":""zzx"",""tool"":""t"",""classification"":""risky"",""extra"":1}", "{""server"":""zzx"",""tool"":""t"",""classification"":""safe""}", "{""server"":""zzx"",""tool"":""t"",""classification"":""Risky""}")
	Set position = 0
	While $ListNext(bodies, position, text) {
		Kill ^OcuTalonTest("McpSettingsProbe")
		Set body = ..Call("Classify", text, , , .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", "classify with "_text_" is 400")
		Set answer = {}.%FromJSON(body)
		Do $$$AssertEquals(answer.error.code_"|"_answer.error.message, "bad_classification|"_##class(OcuTalon.Mcp.Ops).#MESSAGECLASSIFICATION, "bad_classification with McpOps' text")
		Do $$$AssertEquals(+$Get(^OcuTalonTest("McpSettingsProbe", "submits")), 0, "and nothing was submitted")
	}
	Do $$$AssertEquals(..Rows(), before, "no row was written")
}

Method TestClassifyErrors()
{
	If '..Guard() Quit
	Set server = ..Server("c")
	Do ..MakeRow(server)
	Set tool = ##class(OcuTalon.Mcp.ToolClassification).%New()
	Set tool.Server = server
	Set tool.Tool = "zz_lookup"
	Set tool.Classification = "unclassified"
	Set tool.Fingerprint = "zzfp"
	Set tool.ChangedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(tool.%Save(), "a fixture tool row is saved")
	Kill tool
	For case = {"server": (server), "tool": "zz_missing", "classification": "risky"}, {"server": "zzmcpnone", "tool": "zz_lookup", "classification": "risky"}, {"server": "1bad", "tool": "zz_lookup", "classification": "risky"}, {"server": (server), "tool": "", "classification": "risky"} {
		Set body = ..Call("Classify", case.%ToJSON(), , , .response)
		Do $$$AssertEquals(response.Status, "404 Not Found", case.%ToJSON()_" is 404")
		Do $$$AssertEquals({}.%FromJSON(body).error.code, "not_found", "not_found")
	}
	Do $$$AssertEquals(##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_lookup").Classification, "unclassified", "the tool is still unclassified")
	Set body = ..Call("Classify", {"server": (server), "tool": "zz_lookup", "classification": "unclassified"}.%ToJSON(), , , .response)
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|"_{"result": "saved", "message": "Saved"}.%ToJSON(), "unclassified is a classification too")
}

Method TestRemoveUnknown()
{
	If '..Guard() Quit
	Set before = ..Rows()
	For name = ..Server("n"), "1bad", "a"_$Translate($Justify("", 50), " ", "b") {
		Set body = ..Call("Remove", , , name, .response)
		Do $$$AssertEquals(response.Status, "404 Not Found", "a remove of '"_$Extract(name, 1, 12)_"' is 404")
		Do $$$AssertEquals({}.%FromJSON(body).error.code, "not_found", "not_found")
	}
	Do $$$AssertEquals(..Rows(), before, "no row changed")
}

Method TestNotAdmin()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	Set before = ..Rows()
	For route = "GET|/v1/settings/mcp", "POST|/v1/settings/mcp/servers", "DELETE|/v1/settings/mcp/servers/zz", "POST|/v1/settings/mcp/classify" {
		Set written = ..PreDispatch($Piece(route, "|", 2), $Piece(route, "|", 1), .continue)
		Do $$$AssertEquals(continue, 0, route_": the dispatch stops")
		Do $$$AssertTrue(written [ """not_admin""", route_": 403 not_admin")
	}
	If ..Missing '= "" Quit
	For roles = "OcuTalonUser", "%All,OcuTalonUser" {
		Set ^OcuTalonTest("ApiProbe", "roles") = roles
		Set body = ..Call("List", , , , .response)
		Do $$$AssertEquals(response.Status, "403 Forbidden", "the list route refuses "_roles_" itself")
		Do $$$AssertEquals({}.%FromJSON(body).error.code, "not_admin", "not_admin")
		Set body = ..Call("Add", {"name": "zzx", "address": (..#URL), "secret": "zz-user-secret"}.%ToJSON(), , , .response)
		Do $$$AssertEquals(response.Status, "403 Forbidden", "so does add")
		Set body = ..Call("Remove", , , "zzx", .response)
		Do $$$AssertEquals(response.Status, "403 Forbidden", "remove")
		Set body = ..Call("Classify", {"server": "zzx", "tool": "t", "classification": "risky"}.%ToJSON(), , , .response)
		Do $$$AssertEquals(response.Status, "403 Forbidden", "and classify")
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("McpSettingsProbe", "handoffs"))+$Get(^OcuTalonTest("McpSettingsProbe", "submits")), 0, "nothing was offered or submitted")
	Do $$$AssertEquals(..Rows(), before, "nothing is stored")
}

Method TestOnlineDemo()
{
	If '..Guard() Quit
	Set server = ..Server("d")
	Do ..MakeRow(server)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set before = ..Rows()
	Set commands = ..Messages()
	Set wallet = ..Wallet()
	Set good = {"name": "zzmcpdemo", "address": (..#URL), "secret": "zz-demo-secret-0123456789"}.%ToJSON()
	For route = "List", "Add", "Remove", "Classify" {
		// a body that no route could read as a request: the answer comes before the body is read
		For text = good, "not json", "" {
			Set body = ..Call(route, text, , server, .response)
			Do $$$AssertEquals(response.Status, "409 Conflict", route_" with '"_$Extract(text, 1, 12)_"': 409")
			Set answer = {}.%FromJSON(body)
			Do $$$AssertEquals(answer.error.code_"|"_answer.error.message, "not_available|"_..#OFFTEXT, route_": not_available with the accepted text")
		}
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("McpSettingsProbe", "handoffs"))+$Get(^OcuTalonTest("McpSettingsProbe", "submits")), 0, "nothing was offered or submitted")
	Do $$$AssertEquals(..Messages(), commands, "and no command message was stored")
	Do $$$AssertEquals(..Rows(), before, "no row changed")
	Do $$$AssertEquals(..Wallet(), wallet, "and the wallet is unchanged")
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	Set body = ..Call("List", , , , .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "a visitor is never an admin, so the demo answers a visitor 403")
}

Method TestHandoffDiscardedOnFailure()
{
	If '..Guard() Quit
	Set before = ..Rows()
	For mode = "fail", "throw" {
		Kill ^OcuTalonTest("McpSettingsProbe")
		Set ^OcuTalonTest("McpSettingsProbe", "mode") = mode
		Set body = ..Call("Add", {"name": (..Server("f")), "address": (..#URL), "secret": "zz-discard-secret-0123456789"}.%ToJSON(), , , .response)
		Do $$$AssertEquals(response.Status, "500 Internal Server Error", "an add with a submit that "_mode_"s answers 500")
		Do $$$AssertEquals({}.%FromJSON(body).error.code, "server_error", "server_error")
		Set uri = $Get(^OcuTalonTest("McpSettingsProbe", "uri"))
		Do $$$AssertTrue(uri '= "", mode_": the command carried a handoff uri")
		Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), mode_": the handoff is gone")
		Do $$$AssertEquals(left, "", "and held nothing")
	}
	Do $$$AssertEquals(..Rows(), before, "nothing is stored")
}

/// --- helpers ---
/// A refused add: the label, the request body as JSON text and the fields expected in the answer as JSON text.
Method Case(label As %String, body As %DynamicObject, fields As %DynamicObject) As %List [ Private ]
{
	Quit $ListBuild(label, body.%ToJSON(), fields.%ToJSON())
}

/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// The name of the test's server with the suffix.
Method Server(suffix As %String) As %String [ Private ]
{
	Set name = "zzmcpapi"_..Number_suffix
	Set ..Names = ..Names_$Select(..Names = "": "", 1: ",")_name
	Quit name
}

/// A random secret of 24 letters and digits.
Method NewSecret() As %String [ Private ]
{
	Quit "zzApi"_$Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(18)), "+/=", "AAA")
}

/// A server row with no resource, for a test that needs a name that exists.
Method MakeRow(server As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.Server).%New()
	Set row.Name = server
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(row.%Save(), "the fixture row "_server_" is saved")
}

/// The member of the list answer's servers with the name, or "".
Method ServerOf(body As %String, name As %String) As %DynamicObject [ Private ]
{
	Set found = ""
	Set servers = {}.%FromJSON(body).servers
	Set iterator = servers.%GetIterator()
	While iterator.%GetNext(, .server) {
		If server.name = name Set found = server
	}
	Quit found
}

/// Calls the route method of the probe as the CSP session of the fixture session (body is the request's content, name the :server argument); response is the %response.
Method Call(method As %String, body As %String, session As %String = "", name As %String = "", Output response) As %String [ Private ]
{
	New %request, %response, %session
	Set application = "/ocutalon/api/"
	Set %request = $Select($Get(body) = "": ##class(OcuTalon.Test.Web.StubRequest).Make(application), 1: ##class(OcuTalon.Test.Web.StubRequest).MakeBody(application, body))
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %response.Status = "200 OK"
	Set %session = ##class(%CSP.Session).%New("ZzMcpSettings", 0)
	Set %session.Data("OcuTalon.SessionRef") = $Select(session '= "": session, 1: ..A)
	If method = "Remove" {
		Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, method, name)
	} Else {
		Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, method)
	}
	Do $$$AssertStatusOK(sc, method_" returns OK")
	Set response = %response
	Quit written
}

/// Runs OnPreDispatch of Web.Api's probe for the URL and method with a stand-in request; returns what it wrote. continue is the dispatch flag it left.
Method PreDispatch(url As %String, method As %String, Output continue) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", method, "application/json", 1, "http://localhost", "localhost")
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New("ZzMcpSettings", 0)
	Set %response.ContentType = ""
	Set continue = 1
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Test.Web.ApiProbe", "OnPreDispatch", url, method, .continue)
	Do $$$AssertStatusOK(sc, "OnPreDispatch returns OK")
	Quit written
}

/// The number of rows of OcuTalon.Mcp.Server.
Method Rows() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Mcp.Server")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// All the stored values of the four command tables that this class's routes submit, as one text, to show that nothing was submitted.
Method Messages() As %String [ Private ]
{
	Set text = ""
	For table = "AddMcpServer", "RemoveMcpServer", "ClassifyTool", "ListMcpServers" {
		Set text = text_##class(OcuTalon.Test.Web.WebhookTools).Columns("OcuTalon_Msg_Command."_table)
	}
	Quit text
}

/// The wallet's collections and secrets as one text, "SQLCODE <code>" when the extents cannot be read.
Method Wallet() As %String [ Private ]
{
	Set ids = ""
	For table = "Collection", "Secret" {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT %ID FROM %Wallet."_table_" ORDER BY 1")
		If rs.%SQLCODE < 0 Quit
		While rs.%Next() { Set ids = ids_$ListBuild(table_":"_rs.%GetData(1)) }
	}
	If rs.%SQLCODE < 0 Quit "SQLCODE "_rs.%SQLCODE
	Quit $ListToString(ids, ";")
}

/// Removes every fixture the test may have made: rows, tool rows, resources, entries, wallet keys and collections, each attempted whatever happened before.
Method Clean() [ Private ]
{
	For i = 1:1:$Length(..Names, ",") {
		Set name = $Piece(..Names, ",", i)
		If name = "" Continue
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", name)
		If ##class(OcuTalon.Mcp.Server).NameIndexExists(name, .id) Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
		Do ##class(OcuTalon.Install.Step.Mcp).Revoke(name)
		If ##class(%ConfigStore.Configuration).Exists("AI.MCP.OcuTalon_"_name) Do ##class(%ConfigStore.Configuration).Delete("AI.MCP.OcuTalon_"_name)
		If ##class(%Wallet.Secret).Exists("OcuTalon_MCP_"_name_".Key") Do ##class(%Wallet.KeyValue).Delete("OcuTalon_MCP_"_name_".Key")
		If ##class(%Wallet.Collection).Exists("OcuTalon_MCP_"_name) Do ##class(%Wallet.Collection).Delete("OcuTalon_MCP_"_name)
	}
}

/// What is left of the test's servers as a text of places ("" when nothing): a row, tool rows, an entry, a wallet key or a collection.
Method Leftovers() As %String [ Private ]
{
	Set places = ""
	For i = 1:1:$Length(..Names, ",") {
		Set name = $Piece(..Names, ",", i)
		If name = "" Continue
		If ##class(OcuTalon.Mcp.Server).NameIndexExists(name) Set places = places_$ListBuild(name_" row")
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", name)
		If result.%Next(), result.%GetData(1) Set places = places_$ListBuild(name_" tool rows")
		If ##class(%ConfigStore.Configuration).Exists("AI.MCP.OcuTalon_"_name) Set places = places_$ListBuild(name_" entry")
		If ##class(%Wallet.Secret).Exists("OcuTalon_MCP_"_name_".Key") Set places = places_$ListBuild(name_" key")
		If ##class(%Wallet.Collection).Exists("OcuTalon_MCP_"_name) Set places = places_$ListBuild(name_" collection")
	}
	Quit $ListToString(places, ", ")
}

}
