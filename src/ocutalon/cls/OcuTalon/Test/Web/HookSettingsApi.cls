/// Tests of the webhook settings routes (Story 35.3; AD-1, AD-4, AD-13, AD-19), called with stand-in request and response objects through
/// Test.Web.HookSettingsProbe and a CSP session whose OcuTalon.SessionRef is a fixture session. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): the routes go through the real production, Commands.Submit, CommandsIn and the real SettingsOps. Two fixture sessions, A and B, stand for two
/// admins; the roles of the signed-in user come from Test.Web.ApiProbe's seam.
///   - TestCreateAndList: C1 and C4, an admin's create answers 200 with the webhook's {ref, name, path, createdAt}, the row holds a 66-character salt.hash
///     that the secret matches, one Settings audit entry names webhook.<Ref> and the name, and the list shows the webhook, in creation order;
///   - TestFieldRefusals: C2, "@{" in a name or a secret, a name that is blank, over 64 characters or holds a control character, a secret of 15 or 257 characters
///     or with a space, and a name used before in another case, each answer 400 bad_webhook with the field's text and change nothing;
///   - TestRotate: C3, a replacement answers 200, the old secret no longer matches and the new one does, and one Settings entry names webhook.<Ref>.secret;
///   - TestIsolation: session B lists none of A's webhooks, and B's rotation of A's Ref answers 404 and leaves the hash alone;
///   - TestNotAdmin: C5, a user with the OcuTalon user role only gets 403 not_admin from OnPreDispatch and from each route itself;
///   - TestOnlineDemo: C6, with the online-demo flag set an admin gets 409 not_available with the ruled text on every route, and nothing is read or written;
///   - TestBadBodies: C7, a body that is not exactly the shape is 400 bad_webhook with no fields, and nothing is submitted;
///   - TestSecretNeverStored: after a create and a rotation, no message of either verb, no result, no event log row, no audit entry and no node of the webhook
///     globals holds either secret, and the handoff of each command is gone (a Take of its uri fails);
///   - TestHandoffDiscardedOnFailure: when the submit fails or throws, the route answers 500 and the secret's handoff is discarded all the same.
Class OcuTalon.Test.Web.HookSettingsApi Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Web.HookSettingsProbe";

/// The online-demo flag before the tests.
Property SavedOnline As %String;

/// The Refs of the sessions A and B.
Property A As %String;

Property B As %String;

/// The TraceRefs of the fixture sessions, for the clean-up of the messages.
Property Traces As %DynamicArray;

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
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set ..A = ..Session()
	Set ..B = ..Session()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("ApiProbe", "roles")
	Kill ^OcuTalonTest("HookSettingsProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Traces)
	Do ..DropRows()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("ApiProbe", "roles")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $$$OK
}

Method TestCreateAndList()
{
	If '..Guard() Quit
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set secret = "zz-create-secret-"_$Random(1000000)
	Set body = ..Call("Create", {"name": "zz  Orders feed ", "secret": (secret)}.%ToJSON(), ..A, , .response)
	Do $$$AssertEquals(response.Status, "200 OK", "an admin's create answers 200")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.result, "done", "result done")
	Do $$$AssertEquals(answer.message, "Saved. Applies within a minute. Recorded in the audit log.", "with the accepted message")
	Set webhook = answer.webhook
	Do $$$AssertEquals(webhook.name, "zz  Orders feed", "the name is trimmed")
	Do $$$AssertEquals(webhook.path, "/ocutalon/hook/"_webhook.ref, "the path is /ocutalon/hook/<ref>")
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).IsRef(webhook.ref), "the ref is a Ref")
	Do $$$AssertTrue(webhook.createdAt '= "", "and createdAt is set")
	Do $$$AssertEquals(webhook.%Size(), 4, "the webhook has only ref, name, path and createdAt")
	Set row = ##class(OcuTalon.Data.Webhook).Lookup(webhook.ref)
	Do $$$AssertTrue($IsObject(row), "the row is stored")
	Do $$$AssertEquals(row.SessionRef, ..A, "for the CSP session's session")
	Do $$$AssertEquals($Length(row.SecretHash), 66, "the row holds a 66-character salt.hash")
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).Matches(row.SecretHash, secret), "that the secret matches")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", webhook.ref)
	Do $$$AssertEquals(entries.%Size(), 1, "one Settings audit entry names the webhook")
	Do $$$AssertEquals(entries.%Get(0).data.setting, "webhook."_webhook.ref, "the setting is webhook.<Ref>")
	Do $$$AssertEquals(entries.%Get(0).data.to, "zz  Orders feed", "to the name")
	Do $$$AssertEquals(entries.%Get(0).data.sessionRef, ..A, "for the session")
	Do $$$AssertEquals(entries.%Get(0).data.channel, "web", "on the web channel")
	Set second = {}.%FromJSON(..Call("Create", {"name": "zz Second", "secret": (secret_"2")}.%ToJSON(), ..A, , .response)).webhook
	Set list = {}.%FromJSON(..Call("List", , ..A, , .response))
	Do $$$AssertEquals(response.Status, "200 OK", "the list answers 200")
	Do $$$AssertEquals(list.webhooks.%Size(), 2, "with both webhooks")
	Do $$$AssertEquals(list.webhooks.%Get(0).ref, webhook.ref, "in creation order")
	Do $$$AssertEquals(list.webhooks.%Get(1).ref, second.ref, "the second after it")
	Do $$$AssertEquals(list.webhooks.%Get(0).%Size(), 4, "each with only ref, name, path and createdAt")
}

Method TestFieldRefusals()
{
	If '..Guard() Quit
	Set good = "zz-field-secret-0123456789"
	Set before = ..Rows()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set bad = ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.webhookBadName")
	Set badSecret = ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.webhookBadSecret")
	Set expansion = ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.refusedExpansion", "@{")
	Do $$$AssertEquals(expansion, "This can't contain @{, which IRIS would read as a reference to a setting. Nothing was changed.", "the accepted text of a setting reference")
	Do $$$AssertEquals(bad, "Enter a name of 1 to 64 characters. Nothing was changed.", "the accepted text of a bad name")
	Do $$$AssertEquals(badSecret, "Use a secret of 16 to 256 characters: letters, digits and punctuation, with no spaces. Nothing was changed.", "and of a bad secret")
	Set cases = $ListBuild(
		"name@|zz @{x}|"_good_"|name|"_expansion,
		"secret@|zz ok|zz-secret-@{abcdefgh|secret|"_expansion,
		"blank name|   |"_good_"|name|"_bad,
		"empty name||"_good_"|name|"_bad,
		"long name|"_$Translate($Justify("", 65), " ", "n")_"|"_good_"|name|"_bad,
		"control|zz"_$Char(9)_"x|"_good_"|name|"_bad,
		"short secret|zz ok|123456789012345|secret|"_badSecret,
		"long secret|zz ok|"_$Translate($Justify("", 257), " ", "s")_"|secret|"_badSecret,
		"space secret|zz ok|zz-secret with space-0123|secret|"_badSecret)
	Set position = 0
	While $ListNext(cases, position, one) {
		Set label = $Piece(one, "|", 1)
		Set body = ..Call("Create", {"name": ($Piece(one, "|", 2)), "secret": ($Piece(one, "|", 3))}.%ToJSON(), ..A, , .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", label_": 400")
		Set answer = {}.%FromJSON(body)
		Do $$$AssertEquals(answer.error.code, "bad_webhook", label_": bad_webhook")
		Do $$$AssertEquals(answer.error.message, "Couldn't save. Nothing was changed.", label_": the plain message")
		Do $$$AssertEquals(answer.fields.%Get($Piece(one, "|", 4)), $Piece(one, "|", 5), label_": the field's text")
		Do $$$AssertEquals(answer.fields.%Size(), 1, label_": only the refused field")
	}
	Do $$$AssertEquals(..Rows(), before, "nothing is stored")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Settings", "Settings", "webhook.").%Size(), 0, "and nothing is audited")
	Do ..Call("Create", {"name": "zz Taken", "secret": (good)}.%ToJSON(), ..A, , .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the first webhook of the name is saved")
	Set body = ..Call("Create", {"name": "ZZ taken", "secret": (good)}.%ToJSON(), ..A, , .response)
	Do $$$AssertEquals(response.Status, "400 Bad Request", "the same name in another case is refused")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.fields.name, "A webhook called 'ZZ taken' already exists. Nothing was changed.", "with the accepted name-taken text")
	Do $$$AssertEquals(..Rows(), before + 1, "and only the first is stored")
	Set body = ..Call("Create", {"name": "zz Taken B", "secret": (good)}.%ToJSON(), ..B, , .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a name that another session does not use is free, and two sessions may share a secret")
	Set body = ..Call("Create", {"name": "zz taken", "secret": (good)}.%ToJSON(), ..B, , .response)
	Do $$$AssertEquals(response.Status, "400 Bad Request", "names are unique across sessions")
}

Method TestRotate()
{
	If '..Guard() Quit
	Set old = "zz-old-secret-0123456789", new = "zz-new-secret-9876543210"
	Set ref = {}.%FromJSON(..Call("Create", {"name": "zz Rotate", "secret": (old)}.%ToJSON(), ..A, , .response)).webhook.ref
	Set oldHash = ##class(OcuTalon.Data.Webhook).Lookup(ref).SecretHash
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set body = ..Call("Rotate", {"secret": (new)}.%ToJSON(), ..A, ref, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the owner's replacement answers 200")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.result, "done", "result done")
	Do $$$AssertEquals(answer.%Size(), 2, "with only result and message")
	Set row = ##class(OcuTalon.Data.Webhook).Lookup(ref)
	Do $$$AssertTrue(row.SecretHash '= oldHash, "the hash changed")
	Do $$$AssertTrue('##class(OcuTalon.Data.Webhook).Matches(row.SecretHash, old), "the old secret no longer matches")
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).Matches(row.SecretHash, new), "and the new one does")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", ref)
	Do $$$AssertEquals(entries.%Size(), 1, "one Settings audit entry")
	Do $$$AssertEquals(entries.%Get(0).data.setting, "webhook."_ref_".secret", "names webhook.<Ref>.secret")
	Set hash = row.SecretHash
	Set body = ..Call("Rotate", {"secret": "short"}.%ToJSON(), ..A, ref, .response)
	Do $$$AssertEquals(response.Status, "400 Bad Request", "a secret that is too short is refused")
	Do $$$AssertEquals({}.%FromJSON(body).fields.secret, ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.webhookBadSecret"), "with the accepted text")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Lookup(ref).SecretHash, hash, "and the hash is kept")
	Set body = ..Call("Rotate", {"secret": ($Translate($Justify("", 300), " ", "s"))}.%ToJSON(), ..A, ref, .response)
	Do $$$AssertEquals(response.Status, "400 Bad Request", "a secret over 256 characters is refused before any handoff")
	Set body = ..Call("Rotate", {"secret": "zz-secret-@{abcdefgh"}.%ToJSON(), ..A, ref, .response)
	Do $$$AssertEquals(response.Status, "400 Bad Request", "a secret holding @{ is refused")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Lookup(ref).SecretHash, hash, "and the hash is kept")
}

Method TestIsolation()
{
	If '..Guard() Quit
	Set secret = "zz-owner-secret-0123456789"
	Set ref = {}.%FromJSON(..Call("Create", {"name": "zz Mine", "secret": (secret)}.%ToJSON(), ..A, , .response)).webhook.ref
	Set list = {}.%FromJSON(..Call("List", , ..B, , .response))
	Do $$$AssertEquals(list.webhooks.%Size(), 0, "session B lists none of A's webhooks")
	Set hash = ##class(OcuTalon.Data.Webhook).Lookup(ref).SecretHash
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set body = ..Call("Rotate", {"secret": "zz-attacker-secret-01234"}.%ToJSON(), ..B, ref, .response)
	Do $$$AssertEquals(response.Status, "404 Not Found", "B's rotation of A's Ref is 404")
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "not_found", "not_found")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Lookup(ref).SecretHash, hash, "and A's hash is untouched")
	Set body = ..Call("Rotate", {"secret": "zz-attacker-secret-01234"}.%ToJSON(), ..B, ##class(OcuTalon.Bridge.Ids).NewRef(), .response)
	Do $$$AssertEquals(response.Status, "404 Not Found", "an unknown Ref is 404 too")
	Set body = ..Call("Rotate", {"secret": "zz-attacker-secret-01234"}.%ToJSON(), ..B, "abc", .response)
	Do $$$AssertEquals(response.Status, "404 Not Found", "so is a malformed one")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Settings", "Settings", ref).%Size(), 0, "and nothing is audited")
	Set list = {}.%FromJSON(..Call("List", , ..A, , .response))
	Do $$$AssertEquals(list.webhooks.%Size(), 1, "A still lists its webhook")
}

Method TestNotAdmin()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	Set before = ..Rows()
	For url = "/v1/settings/channels/webhooks", "/v1/settings/channels/webhooks/abc/secret" {
		Set written = ..PreDispatch(url, "POST", .continue)
		Do $$$AssertEquals(continue, 0, url_": the dispatch stops")
		Do $$$AssertTrue(written [ """not_admin""", url_": 403 not_admin")
	}
	Set written = ..PreDispatch("/v1/settings/channels/webhooks", "GET", .continue)
	Do $$$AssertEquals(continue, 0, "GET: the dispatch stops")
	Do $$$AssertTrue(written [ """not_admin""", "GET: 403 not_admin")
	If ..Missing '= "" Quit
	Set body = ..Call("List", , ..A, , .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "the list route refuses a non-admin itself")
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "not_admin", "not_admin")
	Set body = ..Call("Create", {"name": "zz User", "secret": "zz-user-secret-0123456789"}.%ToJSON(), ..A, , .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "the create route refuses a non-admin itself")
	Set body = ..Call("Rotate", {"secret": "zz-user-secret-0123456789"}.%ToJSON(), ..A, "abc", .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "and so does the rotation")
	Set ^OcuTalonTest("ApiProbe", "roles") = "%All,OcuTalonUser"
	Set body = ..Call("List", , ..A, , .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "%All is not the admin role")
	Do $$$AssertEquals(..Rows(), before, "nothing is stored")
}

Method TestOnlineDemo()
{
	If '..Guard() Quit
	Set secret = "zz-demo-secret-0123456789"
	Set ref = {}.%FromJSON(..Call("Create", {"name": "zz Demo", "secret": (secret)}.%ToJSON(), ..A, , .response)).webhook.ref
	Set hash = ##class(OcuTalon.Data.Webhook).Lookup(ref).SecretHash
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set before = ..Rows()
	Set commands = ..Columns("OcuTalon_Msg_Command.CreateWebhook")_..Columns("OcuTalon_Msg_Command.SetWebhookSecret")
	Set expected = "Webhooks are off on the online demo, so it has no public webhook address. They work on your own install."
	For route = "List", "Create", "Rotate" {
		Set body = ..Call(route, {"name": "zz Off", "secret": "zz-off-secret-0123456789"}.%ToJSON(), ..A, ref, .response)
		Do $$$AssertEquals(response.Status, "409 Conflict", route_": 409")
		Set answer = {}.%FromJSON(body)
		Do $$$AssertEquals(answer.error.code, "not_available", route_": not_available")
		Do $$$AssertEquals(answer.error.message, expected, route_": with the ruled text")
	}
	Do $$$AssertEquals(..Rows(), before, "nothing is stored")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Lookup(ref).SecretHash, hash, "the row is unchanged")
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).Matches(##class(OcuTalon.Data.Webhook).Lookup(ref).SecretHash, secret), "the old secret still matches")
	Do $$$AssertEquals(..Columns("OcuTalon_Msg_Command.CreateWebhook")_..Columns("OcuTalon_Msg_Command.SetWebhookSecret"), commands, "and no command was submitted")
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	Set body = ..Call("List", , ..A, , .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "a visitor is never an admin, so the demo answers a visitor 403")
}

Method TestBadBodies()
{
	If '..Guard() Quit
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Webhook(..A, "zz Body", "zz-body-secret-0123456789")
	Set before = ..Rows()
	Set commands = ..Columns("OcuTalon_Msg_Command.CreateWebhook")_..Columns("OcuTalon_Msg_Command.SetWebhookSecret")
	Set bodies = $ListBuild("", "[]", """text""", "{}", "{""name"":""zz X""}", "{""secret"":""zz-body-secret-0123456789""}", "{""name"":5,""secret"":""zz-body-secret-0123456789""}", "{""name"":""zz X"",""secret"":5}", "{""name"":""zz X"",""secret"":""zz-body-secret-0123456789"",""extra"":1}", "{""name"":null,""secret"":""zz-body-secret-0123456789""}")
	Set position = 0
	While $ListNext(bodies, position, text) {
		Set body = ..Call("Create", text, ..A, , .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", "create with "_text_" is 400")
		Set answer = {}.%FromJSON(body)
		Do $$$AssertEquals(answer.error.code, "bad_webhook", "bad_webhook")
		Do $$$AssertEquals(answer.fields.%Size(), 0, "with no fields")
	}
	For text = "", "{}", "{""secret"":5}", "{""secret"":""zz-body-secret-0123456789"",""name"":""x""}" {
		Set body = ..Call("Rotate", text, ..A, ref, .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", "rotate with "_text_" is 400")
		Do $$$AssertEquals({}.%FromJSON(body).error.code, "bad_webhook", "bad_webhook")
	}
	Do $$$AssertEquals(..Rows(), before, "nothing is stored")
	Do $$$AssertEquals(..Columns("OcuTalon_Msg_Command.CreateWebhook")_..Columns("OcuTalon_Msg_Command.SetWebhookSecret"), commands, "and nothing was submitted")
}

Method TestSecretNeverStored()
{
	If '..Guard() Quit
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set log = ##class(OcuTalon.Test.Web.WebhookTools).LastLog()
	Set first = "zz-scan-first-"_$Random(100000000)_"-secret"
	Set second = "zz-scan-second-"_$Random(100000000)_"-secret"
	Set ref = {}.%FromJSON(..Call("Create", {"name": "zz Scan", "secret": (first)}.%ToJSON(), ..A, , .response)).webhook.ref
	Do $$$AssertEquals(response.Status, "200 OK", "the create is accepted")
	Do ..Call("Rotate", {"secret": (second)}.%ToJSON(), ..A, ref, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "and so is the rotation")
	Do ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", ref, "", 2)
	Set hash = ##class(OcuTalon.Data.Webhook).Lookup(ref).SecretHash
	For secret = first, second {
		Set label = $Select(secret = first: "the first secret", 1: "the replacing secret")
		Set messages = ..Columns("OcuTalon_Msg_Command.CreateWebhook")_..Columns("OcuTalon_Msg_Command.SetWebhookSecret")_..Columns("OcuTalon_Msg.CommandResult")
		Do $$$AssertTrue(messages '[ secret, label_": no command or result message holds it")
		Do $$$AssertTrue(##class(OcuTalon.Test.Web.WebhookTools).LogText(log) '[ secret, label_": no event log row holds it")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(secret), "", label_": no trace global (message body, header or log row) holds it")
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon")
		Set text = ""
		For i = 0:1:audit.%Size() - 1 {
			Set data = audit.%Get(i).data
			Set text = text_$Select($IsObject(data): data.%ToJSON(), 1: data)_audit.%Get(i).description
		}
		Do $$$AssertTrue(text '[ secret, label_": no audit entry holds it")
		For global = "^OcuTalonP.WebhookD", "^OcuTalonP.WebhookI", "^OcuTalonP.WebhookC", "^OcuTalonP.WebhookS", "^OcuTalonP.SecretHandoff" {
			Do $$$AssertEquals(##class(OcuTalon.Test.Web.WebhookTools).GlobalHolds(global, secret), 0, label_": "_global_" does not hold it")
		}
		Do $$$AssertTrue(messages '[ hash, label_": the hash is in no command or result message either")
		Do $$$AssertTrue(##class(OcuTalon.Test.Web.WebhookTools).LogText(log) '[ hash, label_": nor in the event log")
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Handoff FROM OcuTalon_Msg_Command.CreateWebhook UNION ALL SELECT Handoff FROM OcuTalon_Msg_Command.SetWebhookSecret")
	Set uris = 0
	While result.%Next() {
		Set uri = result.%GetData(1)
		If uri = "" Continue
		Set uris = uris + 1
		Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .gone, 0), "the handoff "_$Extract(uri, 1, 40)_" is gone")
		Do $$$AssertEquals(gone, "", "and held nothing")
	}
	Do $$$AssertTrue(uris >= 2, "both commands carried a handoff uri")
}

Method TestHandoffDiscardedOnFailure()
{
	If '..Guard() Quit
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Webhook(..A, "zz Discard", "zz-discard-secret-0123456789")
	Set before = ..Rows()
	For mode = "fail", "throw" {
		For method = "Create", "Rotate" {
			Kill ^OcuTalonTest("HookSettingsProbe")
			Set ^OcuTalonTest("HookSettingsProbe", "mode") = mode
			Set text = $Select(method = "Create": {"name": "zz Discard two", "secret": "zz-discard-new-secret-01234"}.%ToJSON(), 1: {"secret": "zz-discard-new-secret-01234"}.%ToJSON())
			Set body = ..Call(method, text, ..A, $Select(method = "Rotate": ref, 1: ""), .response)
			Do $$$AssertEquals(response.Status, "500 Internal Server Error", method_" with a submit that "_mode_"s answers 500")
			Set uri = $Get(^OcuTalonTest("HookSettingsProbe", "uri"))
			Do $$$AssertTrue(uri '= "", method_"/"_mode_": the command carried a handoff uri")
			Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), method_"/"_mode_": the handoff is gone")
			Do $$$AssertEquals(left, "", "and held nothing")
		}
	}
	Do $$$AssertEquals(..Rows(), before, "nothing is stored")
}

/// --- helpers ---
/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// A fixture session of the IRIS user who runs the tests (the CSP session resolves to it through its OcuTalon.SessionRef).
Method Session() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Do ..Traces.%Push(##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef)
	Quit ref
}

/// Calls the route method of the probe as the CSP session of the session (body is the request's content, ref the :ref argument); response is the %response.
Method Call(method As %String, body As %String, session As %String, ref As %String = "", Output response) As %String [ Private ]
{
	New %request, %response, %session
	Set application = "/ocutalon/api/"
	Set %request = $Select($Get(body) = "": ##class(OcuTalon.Test.Web.StubRequest).Make(application), 1: ##class(OcuTalon.Test.Web.StubRequest).MakeBody(application, body))
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %response.Status = "200 OK"
	Set %session = ##class(%CSP.Session).%New("ZzHookSettings", 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	If method = "Rotate" {
		Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, method, ref)
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
	Set %session = ##class(%CSP.Session).%New("ZzHookSettings", 0)
	Set %response.ContentType = ""
	Set continue = 1
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Test.Web.ApiProbe", "OnPreDispatch", url, method, .continue)
	Do $$$AssertStatusOK(sc, "OnPreDispatch returns OK")
	Quit written
}

/// The number of webhook rows.
Method Rows() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Webhook")
	Do result.%Next()
	Quit result.%GetData(1)
}

/// All the stored values of the rows of the table, joined (the table name is the test's own constant).
Method Columns(table As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Web.WebhookTools).Columns(table)
}

/// Deletes the webhook rows of the fixture sessions and the counters the routes did not make, so that no test sees another's rows.
Method DropRows() [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Webhook WHERE SessionRef IN (?, ?)", ..A, ..B)
	While result.%Next() {
		Do ##class(OcuTalon.Data.Webhook).%DeleteId(result.%GetData(1))
	}
}

}
