/// Tests of the settings routes of the REST surface (Story 33.2; AD-1, AD-4, AD-13, AD-19), called with stand-in request and response objects
/// and a CSP session whose OcuTalon.SessionRef is the fixture session (as Test.Web.DismissApi does). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI
/// ONLY (Rule 21): the saves go through the real production, Commands.Submit, CommandsIn and the real SettingsOps, and where
/// OcuTalon.Production does not run those tests fail with that reason, so that a broken stack can never give a green shard. The roles of the
/// signed-in user are set through Test.Web.ApiProbe's roles seam. The one demo mode save made through the production keeps the stack's own mode (the Demo step then
/// changes nothing); the mapping of every outcome to its answer is tested on Answer.
///   - TestNonAdminIs403Everywhere: with the OcuTalon user role only, or with %All, GET /v1/settings, each of the seven POST routes, POST
///     /v1/settings/daily-digest/send and POST /v1/settings/models/test (each also written
///     with another case, a trailing slash and a query) answer 403 not_admin and stop the dispatch, before the browser envelope, whatever the
///     headers, while an admin passes to the envelope check and a path that is not a settings path is not asked for the role;
///   - TestGetShape: the body is SettingsOps.Values, its providers and its prices (Story 18.3: one entry of input, output, cacheRead and cacheWrite for each model
///     of a supported provider that has a Price row, and for no other) are asserted by their built shape, and it holds no key value (a scan that is shown to find a planted
///     Anthropic-shaped, OpenAI-shaped and Google-shaped key and a configured key value; the names of the key variables are allowed);
///   - TestSaveThresholds: an admin's save through the production answers 200, writes the rows with the audit entries, and the page's GET and
///     Setting.Get in a process whose cache entry has expired show the saved values, and the production is not restarted (its start time stays);
///     the command is the CSP session's, not the body's;
///   - TestRefusedSaves: a refused value, a field that is not the section's, "@{" and a body that is not an object answer 400 bad_settings with the
///     ruled text and the fields, and change nothing;
///   - TestBridgeRoutesAre501 (U-177 exception, Contest Planner, 2026-11-05): budgets and time-zone reach the built bridge settings and are saved, applied and put back, a
///     value off the allow-list is 400 with nothing changed; an unbuilt route's call is 501 (the models route is built, Story 18.3, and the channels route, Story 21.2);
///   - TestModelsSaveRoute (Story 18.3): POST /v1/settings/models answers 200 done for a body equal to the current values (nothing changes), and 400 bad_settings with
///     the offending names for a body that is not the shape or names a model that no provider lists;
///   - TestModelTestRoute (Story 18.3; AC 2): an admin's POST /v1/settings/models/test for each agent answers 200 with {"answered", "seconds", "reason"} through
///     the production (on a stack with no model key the test answers false with the reason no_key), a body that is not exactly {"agent": string} and an agent that
///     TestRequest refuses are 400 bad_settings with the field agent, and a user who is not an admin is 403 not_admin;
///   - TestSendDigest (Story 18.2; AC 3): an admin's POST /v1/settings/daily-digest/send answers 202 {"result":"sending"} with no body read, and the
///     production records one requested Sent row (empty DueAt) for the CSP session's Ref; a second press, with a fresh key, records a second;
///   - TestSaveDemoModeAudited: an admin's demo mode save (the stack's own mode) answers 200 and writes one entry with the call's user, the CSP session's Ref and the channel web;
///   - TestDemoModeBodies: a demo mode body that is not exactly {demoMode: true or false} is 400 with nothing submitted;
///   - TestChannelsRoute (Story 21.2): POST /v1/settings/channels on the online demo is 409 not_available with nothing offered or submitted, a password over 256
///     characters, a password that is not a JSON string (a number, an object) and a body that is not an object are 400 with nothing offered or submitted, a value with @{ or an unknown field is 400 through the production with the offered
///     password withdrawn, a command that the production does not take is 500 with the offered password withdrawn, and the password is in no answer, log row, ^OcuTalon* global or SaveSettings message;
///     Story 21.14: an address or user name that is a number, an object or 257 characters is 400 naming it with nothing offered or submitted, and a body refused after the take (an incoming
///     with @{) leaves a SaveSettings message whose address and user are hand-off references and whose incoming is plain, with neither value in any trace global or log row and the references taken back;
///   - TestAnswerMapping: each outcome of a save has its status, code and text;
///   - TestStateHasAdmin: the snapshot's admin follows the role.
Class OcuTalon.Test.Web.SettingsApi Extends %UnitTest.TestCase
{

/// The probe that carries the roles seam.
Parameter PROBE = "OcuTalon.Test.Web.ApiProbe";

/// The pattern of a hand-off reference.
Parameter REFERENCE = "^secret://handoff/[0-9A-F]{32}$";

/// The keys that the tests write.
Parameter KEYS = "digest.time,digest.channels,checks.thresholds.diskFreePercent,checks.thresholds.journalFreePercent,checks.thresholds.licenseUsePercent,checks.thresholds.queueMessages,checks.thresholds.queueWaitMinutes";

/// The seven POST routes with their slugs.
Parameter SLUGS = "models,budgets,channels,daily-digest,time-zone,check-thresholds,demo-mode";

/// The run's number.
Property Number As %Integer;

/// The reason why the tests that need the production fail, or empty.
Property Missing As %String(MAXLEN = 200);

/// The TraceRefs of the fixture sessions, for the clean-up of the messages.
Property Traces As %DynamicArray;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("SettingsApi", "n"))
	Set ..Traces = []
	Set ..Missing = ""
	Kill ^OcuTalonTest("ApiProbe", "roles")
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Set ^OcuTalonTest("SettingsApi", "saved", key) = $ListBuild(row.Value, row.UpdatedAt)
	}
	If '##class(Ens.Director).IsProductionRunning(.name) || (name '= "OcuTalon.Production") {
		Set ..Missing = "OcuTalon.Production does not run in OCUTALON: this class runs in throwaways and CI only (Rule 21)"
	}
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("ApiProbe", "roles")
	Do ..Clear()
	Quit $SYSTEM.Status.OK()
}

/// Deletes the rows of the model test presses after TestModelTestRoute, also when it failed.
Method OnAfterOneTest(testname As %String) As %Status
{
	If (testname = "TestModelTestRoute") && (..Missing = "") Do ..DropTestRows()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("ApiProbe", "roles")
	Do ..Clear()
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		If $Data(^OcuTalonTest("SettingsApi", "saved", key), saved) {
			Set row = ##class(OcuTalon.Data.Setting).%New()
			Set row.Key = key, row.Value = $List(saved, 1), row.UpdatedAt = $List(saved, 2)
			Do row.%Save()
		}
		Kill ^||OcuTalon.Setting(key)
	}
	Kill ^OcuTalonTest("SettingsApi", "saved")
	Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Traces, "OCUTALON")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

/// A user without OcuTalonAdmin is refused on all eleven settings calls before the envelope, the body and the route.
Method TestNonAdminIs403Everywhere()
{
	Set wanted = {"error": {"code": "not_admin", "message": "Only OcuTalon admins can open settings."}}.%ToJSON()
	Set urls = $ListBuild("GET|/v1/settings")
	Set slugs = $ListFromString(..#SLUGS)
	Set position = 0
	While $ListNext(slugs, position, slug) {
		Set urls = urls_$ListBuild("POST|/v1/settings/"_slug)
	}
	Set urls = urls_$ListBuild("POST|/v1/settings/daily-digest/send", "POST|/v1/settings/models/test", "POST|/v1/settings/channels/sign-in")
	Do $$$AssertEquals($ListLength(urls), 11, "all eleven calls are tried (Story 21.3 adds the mail sign-in)")
	Set odd = $ListBuild("GET|/v1/Settings", "GET|/v1/settings/", "GET|/v1/settings?x=1", "POST|/v1/SETTINGS/check-thresholds", "POST|/v1/settings/zz-unknown", "DELETE|/v1/settings")
	For roles = "OcuTalonUser", "%All,OcuTalonUser", "OcuTalonUser,OcuTalonAdministrator", "OcuTalonUser,XOcuTalonAdmin" {
		Set ^OcuTalonTest("ApiProbe", "roles") = roles
		Set all = urls_odd
		Set position = 0
		While $ListNext(all, position, row) {
			Set method = $Piece(row, "|", 1), url = $Piece(row, "|", 2)
			Set label = method_" "_url_" with roles "_roles
			Set body = ..PreDispatch(url, method, "text/plain", "", "", "h:1", .response, .continue)
			Do $$$AssertEquals(response.Status, "403 Forbidden", label_": 403")
			Do $$$AssertEquals(body, wanted, label_": not_admin with the ruled text")
			Do $$$AssertEquals(continue, 0, label_": the dispatch stops")
		}
	}
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set body = ..PreDispatch("/v1/settings/check-thresholds", "POST", "application/json", 1, "http://h:1", "h:1", .response, .continue)
	Do $$$AssertEquals(continue, 1, "an admin with the whole envelope goes on to the route")
	Do $$$AssertEquals(body, "", "and nothing is written")
	Set body = ..PreDispatch("/v1/settings/check-thresholds", "POST", "text/plain", "", "", "h:1", .response, .continue)
	Do $$$AssertEquals(continue_"|"_response.Status, "0|403 Forbidden", "an admin without the envelope is stopped by the envelope check")
	Do $$$AssertEquals($Piece(body, """", 6), "not_json", "with the envelope's code, not not_admin")
	Set body = ..PreDispatch("/v1/settings", "GET", "", "", "", "h:1", .response, .continue)
	Do $$$AssertEquals(continue, 1, "an admin's GET goes on")
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	Set body = ..PreDispatch("/v1/state", "GET", "", "", "", "h:1", .response, .continue)
	Do $$$AssertEquals(continue, 1, "a path that is not a settings path is not asked for the admin role")
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonAdmin"
	Set body = ..PreDispatch("/v1/settings", "GET", "", "", "", "h:1", .response, .continue)
	Do $$$AssertEquals(continue_"|"_$Piece(body, """", 6), "0|no_role", "an admin without the user role is still no_role, first")
}

/// GET /v1/settings is SettingsOps.Values as JSON, with the sections, the bridge values, the providers and the zone, and no key material.
Method TestGetShape()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set body = ..Call("Settings", "", ..Session(), .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "200 JSON")
	Set json = {}.%FromJSON(body)
	Set keys = ""
	Set iterator = json.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(keys, "sections,bridge,providers,instanceZone,prices", "the keys")
	Do $$$AssertEquals(json.sections.%Get("check-thresholds").%ToJSON(), "{""diskFreePercent"":10,""journalFreePercent"":10,""licenseUsePercent"":90,""queueMessages"":100,""queueWaitMinutes"":10}", "the thresholds")
	Do $$$AssertEquals(json.sections.%Get("daily-digest").channels, "web,phone,telegram", "the digest channels")
	Set channels = json.sections.channels
	Set members = ""
	Set iterator = channels.%GetIterator()
	While iterator.%GetNext(.key) {
		Set members = members_$Select(members = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(members, "address,incoming,outgoing,user,passwordSet,signIn,clientId,clientSecretSet,signedIn", "the channels section holds the address, both servers, the user, passwordSet and the sign-in members, nothing else (Stories 21.6 and 21.3)")
	Do $$$AssertEquals(channels.%GetTypeOf("outgoing")_"|"_channels.%GetTypeOf("passwordSet")_"|"_channels.%GetTypeOf("signIn")_"|"_channels.%GetTypeOf("clientId")_"|"_channels.%GetTypeOf("clientSecretSet")_"|"_channels.%GetTypeOf("signedIn"), "string|boolean|string|string|boolean|boolean", "the outgoing server, signIn and clientId are strings; passwordSet, clientSecretSet and signedIn booleans")
	Do $$$AssertEquals(json.sections.%Get("demo-mode").%GetTypeOf("demoMode"), "boolean", "demoMode is a boolean")
	// U-177 exception: this Lane B test is edited by Lane A's Story 17.3 once, as ruled by the Contest Planner (2026-11-05). The providers are asserted by their built shape only.
	Do $$$AssertEquals(json.providers.%GetTypeOf(0), "object", "the providers are built: the first row is an object")
	Do $$$AssertTrue(json.providers.%Size() > 0, "and the list is not empty")
	Do ..AssertPrices(json)
	Set configuredValues = ""
	Set iterator = json.providers.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set fields = ""
		Set names = row.%GetIterator()
		While names.%GetNext(.name) {
			Set fields = fields_$Select(fields = "": "", 1: ",")_name
		}
		Do $$$AssertEquals(fields, "provider,defaultModel,models,keyVariable,keySet,supported", "a provider row holds these fields: "_row.provider)
		Do $$$AssertEquals(row.%GetTypeOf("keySet")_"|"_row.%GetTypeOf("supported"), "boolean|boolean", "with keySet and supported as booleans: "_row.provider)
		Set configured = $SYSTEM.Util.GetEnviron(row.keyVariable)
		If configured '= "" Set configuredValues = configuredValues_$ListBuild(configured)
	}
	Set lower = $Replace($Replace($ZConvert(body, "L"), "clientsecretset", ""), """signin"":""password""", "")
	For word = "secret", "apikey", """password""", "token_value" {
		Do $$$AssertTrue(lower '[ word, "the body holds no '"_word_"' (the channels' passwordSet and clientSecretSet are booleans, and signIn names a method, not a password or a secret)")
	}
	Do $$$AssertEquals(..KeyShape(body, configuredValues), "", "the body holds no value shaped like a key and no key value configured in a key variable (the names of the key variables are allowed)")

	// the scan fails on each shape of key value planted in the body; the keys are built here, so that no key-shaped text sits in this file
	Set configuredFake = "zz-configured-"_$Increment(^OcuTalonTest("SettingsApi", "plant"))
	Set planted = $ListBuild(
		$ListBuild("anthropic", "sk-"_"ant-"_"api03-zzplanted0001"),
		$ListBuild("openai", "sk-"_"proj-zzplanted0002"),
		$ListBuild("google", "AI"_"za"_"SyZzPlanted0003"),
		$ListBuild("configured", configuredFake))
	Set position = 0
	While $ListNext(planted, position, one) {
		Do $$$AssertEquals(..KeyShape(body_" "_$List(one, 2)_" ", $ListBuild(configuredFake)), $List(one, 1), "a planted "_$List(one, 1)_" key is found in the body")
	}
}

/// The body's prices (Story 18.3): one entry for each model of a supported provider that has a Price row, and for no other model; each entry has input, output,
/// cacheRead and cacheWrite, as numbers equal to the row's prices.
Method AssertPrices(json As %DynamicObject) [ Private ]
{
	Do $$$AssertEquals(json.%GetTypeOf("prices"), "object", "prices is an object")
	Set expected = ""
	Set providers = ##class(OcuTalon.Bridge.Providers).Rows().%GetIterator()
	While providers.%GetNext(, .row) {
		If '+row.%Get("supported") Continue
		Set models = row.%Get("models").%GetIterator()
		While models.%GetNext(, .model) {
			If ##class(OcuTalon.Bridge.Data.Price).ModelIndexExists(model) Set expected = expected_$ListBuild(model)
		}
	}
	Set found = ""
	Set iterator = json.prices.%GetIterator()
	While iterator.%GetNext(.model, .one) {
		Set found = found_$ListBuild(model)
		Set names = ""
		Set members = one.%GetIterator()
		While members.%GetNext(.name, , .type) {
			Set names = names_$Select(names = "": "", 1: ",")_name_":"_type
		}
		Do $$$AssertEquals(names, "input:number,output:number,cacheRead:number,cacheWrite:number", "the price entry of "_model_" has these members, as numbers")
		Set row = ##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen(model)
		If $IsObject(row) Do $$$AssertEquals(one.input_"|"_one.output_"|"_one.cacheRead_"|"_one.cacheWrite, +row.InputPerMTok_"|"_+row.OutputPerMTok_"|"_+row.CacheReadPerMTok_"|"_+row.CacheWritePerMTok, "and the prices of its row: "_model)
	}
	Do $$$AssertEquals($ListToString(found), $ListToString(expected), "one entry for each model of a supported provider that has a Price row, and no other")
	Do $$$AssertTrue($ListLength(expected) > 0, "control: the stack has Price rows for the supported provider's models")
}

/// The shape of key value that the text holds, or "": anthropic (sk-ant- prefix), openai (sk- prefix), google (AIza prefix) or configured (one of the values in the list).
/// The names of the key variables (ANTHROPIC_API_KEY and the others) are no key values and are not found.
ClassMethod KeyShape(text As %String, configured As %List) As %String [ Private ]
{
	If $Find(text, "sk-"_"ant-") Quit "anthropic"
	If $Find(text, "sk-") Quit "openai"
	If $Find(text, "AI"_"za") Quit "google"
	Set found = 0
	Set position = 0
	While 'found && $ListNext(configured, position, value) {
		If (value '= "") && $Find(text, value) Set found = 1
	}
	Quit $Select(found: "configured", 1: "")
}

/// An admin's save of two thresholds through the production: 200 {"result":"done","sections"}, the two rows, the GET at once, and Setting.Get in a
/// process whose cache entry has expired, with no restart of the production. The body's sessionRef is not accepted.
Method TestSaveThresholds()
{
	If '..Guard() Quit
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set session = ..Session()
	Set started = $Get(^Ens.Runtime("StartTime"))
	Do $$$AssertTrue(started '= "", "control: the running production has a start time")
	Set since = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set body = ..Call("SaveCheckThresholds", {"diskFreePercent": 17, "journalFreePercent": 10, "licenseUsePercent": 90, "queueMessages": 321, "queueWaitMinutes": 10}.%ToJSON(), session, .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "200 JSON: "_body)
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.result, "done", "result done")
	Do $$$AssertEquals(answer.sections.%Get("check-thresholds").diskFreePercent_"|"_answer.sections.%Get("check-thresholds").queueMessages, "17|321", "the answer carries the saved sections")
	Do $$$AssertEquals(..Row("checks.thresholds.diskFreePercent")_"|"_..Row("checks.thresholds.queueMessages"), "17|321", "the two rows are written")
	Do $$$AssertEquals(..Row("checks.thresholds.journalFreePercent")_..Row("checks.thresholds.licenseUsePercent")_..Row("checks.thresholds.queueWaitMinutes"), "", "and no other")
	Do $$$AssertEquals($Get(^Ens.Runtime("StartTime")), started, "no restart: the production's start time is the same after the save")
	Set body = ..Call("Settings", "", session, .response)
	Do $$$AssertEquals({}.%FromJSON(body).sections.%Get("check-thresholds").diskFreePercent, 17, "GET /v1/settings shows the new value at once")
	Set ^||OcuTalon.Setting("checks.thresholds.queueMessages") = $ListBuild("100", 0, $ZHorolog - 61)
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get("checks.thresholds.queueMessages"), "321", "Setting.Get in a process whose cache entry is 61 seconds old reads the new value")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(since, "OcuTalon", "Settings", "", $Username, "", 2, 180)
	Do $$$AssertTrue(entries.%Size() >= 2, "two Settings entries name the IRIS user of the call")
	For i = 0:1:entries.%Size() - 1 {
		If entries.%Get(i).data.setting [ "checks.thresholds" Do $$$AssertEquals(entries.%Get(i).data.sessionRef_"|"_entries.%Get(i).data.channel, session_"|web", "an entry has the CSP session's Ref and the channel web")
	}
	Set body = ..Call("SaveCheckThresholds", {"diskFreePercent": 18, "journalFreePercent": 10, "licenseUsePercent": 90, "queueMessages": 321, "queueWaitMinutes": 10, "sessionRef": "zzother"}.%ToJSON(), session, .response)
	Do $$$AssertEquals(response.Status, "400 Bad Request", "a sessionRef in the body is an unknown field: 400")
	Do $$$AssertEquals(..Row("checks.thresholds.diskFreePercent"), "17", "and nothing changed")
	Set body = ..Call("SaveCheckThresholds", {"diskFreePercent": 17, "journalFreePercent": 10, "licenseUsePercent": 90, "queueMessages": 321, "queueWaitMinutes": 10}.%ToJSON(), session, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the same values again are 200")
	Set body = ..Call("SaveDailyDigest", {"time": "06:45", "channels": "phone,web"}.%ToJSON(), session, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the digest section saves too: "_body)
	Do $$$AssertEquals(..Row("digest.time")_"|"_..Row("digest.channels"), "06:45|web,phone", "the digest keys are written")
	// Story 21.7 (QA): the route accepts email, stored last, and refuses a list that holds a name of no channel with the field named and nothing changed.
	Set body = ..Call("SaveDailyDigest", {"time": "06:45", "channels": "email,web"}.%ToJSON(), session, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a save that names email is 200: "_body)
	Do $$$AssertEquals(..Row("digest.channels"), "web,email", "and stores the channels in their fixed order, email last")
	Do $$$AssertEquals({}.%FromJSON(..Call("Settings", "", session, .response)).sections.%Get("daily-digest").channels, "web,email", "GET /v1/settings shows the stored value at once")
	For channels = "web,sms,email", "email,email", "Email", "email;web" {
		Set body = ..Call("SaveDailyDigest", {"time": "06:45", "channels": (channels)}.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""channels""]}", "the channels '"_channels_"' are refused with the field named")
		Do $$$AssertEquals(..Row("digest.channels"), "web,email", "'"_channels_"' changed nothing")
	}
}

/// An admin's POST /v1/settings/daily-digest/send answers 202 {"result":"sending"}, and the production records one requested Sent row of the CSP
/// session (the digest is composed and sent by the Digest item, whose answer the route does not wait for). Each press has a key of its own, so a
/// second press records a second row.
Method TestSendDigest()
{
	If '..Guard() Quit
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set session = ..Session()
	Do $$$AssertEquals(..Sent(session), 0, "control: the session has no digest yet")
	Set body = ..Call("SendDigest", "{""ignored"": true}", session, .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType_"|"_body, "202 Accepted|application/json|{""result"":""sending""}", "the press is 202 sending: "_body)
	Do $$$AssertEquals(..WaitSent(session, 1), 1, "the production records one requested Sent row for the CSP session")
	Set row = ##class(%SQL.Statement).%ExecDirect(, "SELECT Kind, DueAt, IdempotencyKey FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ?", session)
	Do $$$AssertTrue(row.%Next(), "the row can be read")
	Set first = row.%Get("IdempotencyKey")
	Do $$$AssertEquals(row.%Get("Kind")_"|"_row.%Get("DueAt"), "requested|", "it is a requested digest with no due time")
	Do $$$AssertEquals($Extract(first, 1, $Length("web-digest-")), "web-digest-", "its key is the route's own")
	Set body = ..Call("SendDigest", "", session, .response)
	Do $$$AssertEquals(response.Status_"|"_body, "202 Accepted|{""result"":""sending""}", "a second press is 202 too")
	Do $$$AssertEquals(..WaitSent(session, 2), 2, "and records a second row, so its key is a fresh one")
	Do $ClassMethod("OcuTalon.Test.Digest.ProcessProbe", "Clean", session)
}

/// The number of Sent rows of the session.
Method Sent(session As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ?", session)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// The number of Sent rows of the session once there are count of them, or after 40 seconds.
Method WaitSent(session As %String, count As %Integer) As %Integer [ Private ]
{
	Set end = $ZHorolog + 40
	For {
		Set found = ..Sent(session)
		If (found >= count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// An admin's demo mode save through the production, with the mode the stack already has: 200 and one Settings entry with the IRIS user of the call,
/// the CSP session's Ref and the channel web. The value is the stack's own (read from the row, past this process's cache), so the Demo step that
/// follows the write leaves the stack as it was.
Method TestSaveDemoModeAudited()
{
	If '..Guard() Quit
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set session = ..Session()
	Kill ^||OcuTalon.Setting("demo.mode")
	Set mode = ##class(OcuTalon.Data.Setting).Get("demo.mode")
	Set on = (mode = 1)
	Set existed = ##class(OcuTalon.Data.Setting).KeyIndexExists("demo.mode")
	Set since = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set body = ..Call("SaveDemoMode", "{""demoMode"": "_$Select(on: "true", 1: "false")_"}", session, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a demo mode save is 200: "_body)
	Do $$$AssertEquals({}.%FromJSON(body).sections.%Get("demo-mode").demoMode, on, "the answer shows the mode")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(since, "OcuTalon", "Settings", "", $Username, "", 1, 180)
	If 'existed Do ##class(OcuTalon.Data.Setting).KeyIndexDelete("demo.mode") Kill ^||OcuTalon.Setting("demo.mode")
	Do $$$AssertEquals(entries.%Size(), 1, "one Settings entry names the IRIS user of the call")
	If entries.%Size() < 1 Quit
	Set data = entries.%Get(0).data
	Do $$$AssertEquals(data.setting_"|"_data.sessionRef_"|"_data.channel, "demo.mode|"_session_"|web", "it is for demo.mode, with the CSP session's Ref and the channel web")
}

/// A refused value, a field that is not the section's, "@{" and a body that is not an object: 400 bad_settings with the ruled text and the fields.
Method TestRefusedSaves()
{
	If '..Guard() Quit
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set session = ..Session()
	Set text = "Couldn't save. Nothing was changed."
	Set good = "{""diskFreePercent"": 10, ""journalFreePercent"": 10, ""licenseUsePercent"": 90, ""queueMessages"": 100, ""queueWaitMinutes"": 10}"
	Set cases = $ListBuild($ListBuild("a non-number", "{""diskFreePercent"": ""abc"", ""journalFreePercent"": 10, ""licenseUsePercent"": 90, ""queueMessages"": 100, ""queueWaitMinutes"": 10}", "[""diskFreePercent""]"), $ListBuild("out of range", "{""diskFreePercent"": 10, ""journalFreePercent"": 101, ""licenseUsePercent"": 90, ""queueMessages"": 100, ""queueWaitMinutes"": 10}", "[""journalFreePercent""]"), $ListBuild("@{", "{""diskFreePercent"": 10, ""journalFreePercent"": 10, ""licenseUsePercent"": 90, ""queueMessages"": 100, ""queueWaitMinutes"": ""@{env:KEY}""}", "[""queueWaitMinutes""]"), $ListBuild("a missing field", "{""diskFreePercent"": 10}", "[""journalFreePercent"",""licenseUsePercent"",""queueMessages"",""queueWaitMinutes""]"), $ListBuild("an extra field", "{""diskFreePercent"": 11, ""journalFreePercent"": 10, ""licenseUsePercent"": 90, ""queueMessages"": 100, ""queueWaitMinutes"": 10, ""zz"": 1}", "[]"), $ListBuild("an array", "[1]", "[]"), $ListBuild("text", "not json", "[]"), $ListBuild("an empty body", "", "[]"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $List(case, 1)
		Set body = ..Call("SaveCheckThresholds", $List(case, 2), session, .response)
		Do $$$AssertEquals(response.Status_"|"_response.ContentType, "400 Bad Request|application/json", label_": 400 JSON")
		Do $$$AssertEquals(body, "{""error"":{""code"":""bad_settings"",""message"":"""_text_"""},""fields"":"_$List(case, 3)_"}", label_": bad_settings, the ruled text and the fields")
		Do $$$AssertEquals(..Rows(), 0, label_": nothing is written")
	}
	Set body = ..Call("SaveDailyDigest", "{""time"": ""25:00"", ""channels"": ""web""}", session, .response)
	Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""time""]}", "the digest time is refused and named")
	Do $$$AssertEquals(..Rows(), 0, "nothing is written")
}

/// U-177 one-time exception (Contest Planner ruling of 2026-11-05, Story 17.4, IG-2's conditions): this Lane B test asserts the built behaviour of the bridge settings. The
/// budgets and time-zone routes reach the real SettingsOps and Bridge.Settings through the production: an accepted value is saved (200 done) and applied, and a value
/// that is off the allow-list is 400 bad_settings with the field named and nothing changed. Models and channels are still 501 not_built. The test puts back every value
/// that it wrote, and a check at its end re-reads the token budget, the daily cap and the zone and finds the originals.
Method TestBridgeRoutesAre501()
{
	If '..Guard() Quit
	Set bridge = "OcuTalon.Bridge.Settings"
	Set originals = ..BridgeValues()
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set session = ..Session()
	Try {
		Set body = ..Call("SaveBudgets", {"DecisionTokenBudget": 5000, "DailyCostCapUSD": "7.50"}.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status_"|"_{}.%FromJSON(body).result, "200 OK|done", "budgets: 200 done")
		Do $$$AssertEquals(..BridgeValues(), "5000|7.5|"_$Piece(originals, "|", 3), "and the budget and the cap are applied")
		Set body = ..Call("SaveTimeZone", {"InstanceZone": "Europe/Paris"}.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status_"|"_{}.%FromJSON(body).result, "200 OK|done", "time-zone: 200 done")
		Do $$$AssertEquals($Piece(..BridgeValues(), "|", 3), "Europe/Paris", "and the zone is applied")
		Set applied = ..BridgeValues()
		Set body = ..Call("SaveBudgets", {"DecisionTokenBudget": 100001, "DailyCostCapUSD": "7.50"}.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""DecisionTokenBudget""]}", "a budget above the bound is 400 bad_settings and names the field")
		Set body = ..Call("SaveBudgets", {"DecisionTokenBudget": 5000, "DailyCostCapUSD": "7.555"}.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""DailyCostCapUSD""]}", "and so is a cap of three decimals")
		Set body = ..Call("SaveTimeZone", {"InstanceZone": "Mars/Olympus"}.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""InstanceZone""]}", "and a zone that no file backs")
		Do $$$AssertEquals(..BridgeValues(), applied, "nothing changed after the refusals")
		Set wanted = {"error": {"code": "not_built", "message": "This part of OcuTalon isn't built yet."}}.%ToJSON()
		Set body = ..Call("NotBuilt", "{}", session, .response)
		Do $$$AssertEquals(response.Status_"|"_body, "501 Not Implemented|"_wanted, "an unbuilt route: 501 not_built")
		Set body = ..Call("SaveBudgets", {"DecisionTokenBudget": "@{env:KEY}", "DailyCostCapUSD": "7.50"}.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""DecisionTokenBudget""]}", "a value with @{ is refused before the bridge is asked")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do $ClassMethod(bridge, "Set", "DecisionTokenBudget", $Piece(originals, "|", 1))
	Do $ClassMethod(bridge, "Set", "DailyCostCapUSD", $Piece(originals, "|", 2))
	Do $ClassMethod(bridge, "Set", "InstanceZone", $Piece(originals, "|", 3))
	Do ##class(OcuTalon.Bridge.Time).Apply()
	Do $$$AssertEquals(..BridgeValues(), originals, "the token budget, the daily cap and the zone are the originals again")
}

/// POST /v1/settings/models/test (Story 18.3; AC 2). An admin's test of each agent goes through the production (Commands.Submit, CommandsIn, SettingsOps, Decide) and
/// answers 200 with {"answered", "seconds", "reason"}: answered is a boolean, seconds a number and reason a string, and when the stack has no model key (a throwaway) the
/// answer is "answered":false with the reason no_key. A body that is not exactly {"agent": string}, an agent name that is too long and an agent that TestRequest refuses are
/// 400 bad_settings with the field agent and nothing sent to Decide, and a user without the admin role is 403 not_admin before the route.
Method TestModelTestRoute()
{
	If '..Guard() Quit
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set session = ..Session()
	Set keyed = ..ModelKeySet()
	Set agents = $ListBuild("TriageAgent", "DiagnosisAgent", "ChatAgent")
	Set position = 0
	While $ListNext(agents, position, agent) {
		Set body = ..Call("TestModel", {"agent": (agent)}.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", agent_": 200 JSON: "_body)
		Set answer = {}.%FromJSON(body)
		Set names = ""
		Set iterator = answer.%GetIterator()
		While iterator.%GetNext(.name, , .type) {
			Set names = names_$Select(names = "": "", 1: ",")_name_":"_type
		}
		Do $$$AssertEquals(names, "answered:boolean,seconds:number,reason:string", agent_": the three members of the answer")
		If 'keyed Do $$$AssertEquals(answer.answered_"|"_answer.reason, "0|no_key", agent_": a stack with no model key answers false with the reason no_key")
		Do $$$AssertTrue($ZConvert(body, "L") '[ "api_key", agent_": and the answer holds no key")
	}
	Set cases = $ListBuild("{}", "[""TriageAgent""]", "{""agent"": 5}", "{""agent"": null}", "{""agent"": ""TriageAgent"", ""x"": 1}", "{""Agent"": ""TriageAgent""}", "{""agent"": ""NoSuchAgent""}", "{""agent"": ""@{env:X}""}", "{""agent"": """_$Translate($J("", 33), " ", "a")_"""}", "not json", "")
	Set position = 0
	While $ListNext(cases, position, text) {
		Set before = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
		Set body = ..Call("TestModel", text, session, .response)
		Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""agent""]}", "'"_text_"': 400 bad_settings naming agent")
		Do $$$AssertEquals($Piece(body, """", 6), "bad_settings", "'"_text_"': with the code")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionSince(before, "Decide"), "", "'"_text_"': nothing was sent to Decide")
	}
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	Set body = ..PreDispatch("/v1/settings/models/test", "POST", "application/json", 1, "http://h:1", "h:1", .response, .continue)
	Do $$$AssertEquals(response.Status_"|"_continue_"|"_$Piece(body, """", 6), "403 Forbidden|0|not_admin", "a user without the admin role is 403 not_admin")
}

/// POST /v1/settings/models (Story 18.3): a body equal to the current values is 200 done and changes nothing; a body that is not the shape, and one that names a model that
/// no supported provider lists, are 400 bad_settings with the offending names.
Method TestModelsSaveRoute()
{
	If '..Guard() Quit
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set session = ..Session()
	Set values = ##class(OcuTalon.Core.SettingsOps).Values()
	Set same = {"agents": (values.bridge.agents), "prices": (values.prices)}
	Set before = same.%ToJSON()
	Set body = ..Call("SaveModels", before, session, .response)
	Do $$$AssertEquals(response.Status_"|"_{}.%FromJSON(body).result, "200 OK|done", "the current values are saved as they are: 200 done")
	Do $$$AssertEquals({"agents": (##class(OcuTalon.Core.SettingsOps).Values().bridge.agents), "prices": (##class(OcuTalon.Core.SettingsOps).Values().prices)}.%ToJSON(), before, "and nothing changed")
	Set body = ..Call("SaveModels", "{}", session, .response)
	Do $$$AssertEquals(response.Status_"|"_$Piece(body, """", 6), "400 Bad Request|bad_settings", "{} is 400 bad_settings")
	Set body = ..Call("SaveModels", "[1]", session, .response)
	Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[]}", "an array is 400 with no field")
	Set extra = {}.%FromJSON(before)
	Do extra.prices.%Set("zz-not-a-model", {"input": 1, "output": 1, "cacheRead": 1, "cacheWrite": 1})
	Set body = ..Call("SaveModels", extra.%ToJSON(), session, .response)
	Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""prices.zz-not-a-model""]}", "a model that no supported provider lists is named")
	Do $$$AssertEquals({"agents": (##class(OcuTalon.Core.SettingsOps).Values().bridge.agents), "prices": (##class(OcuTalon.Core.SettingsOps).Values().prices)}.%ToJSON(), before, "and nothing changed")
}

/// 1 when a supported provider has its key variable set in this process (a throwaway has none).
Method ModelKeySet() As %Boolean [ Private ]
{
	Set set = 0
	Set providers = ##class(OcuTalon.Bridge.Settings).Providers().%GetIterator()
	While providers.%GetNext(, .row) {
		If row.supported && row.keySet Set set = 1
	}
	Quit set
}

/// Deletes the Decision rows of model test requests (ItemId test.%) with their Usage and agent steps.
Method DropTestRows() [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT ItemId FROM OcuTalon_Bridge_Data.Decision WHERE ItemId LIKE 'test.%'")
	While result.%Next() {
		Set itemId = result.%GetData(1)
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).DeleteSteps(itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId LIKE 'test.%'")
}

/// A demo mode body that is not exactly {demoMode: true or false} is 400 with the field named when it is the field's value, and nothing is submitted.
Method TestDemoModeBodies()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set session = ..Session()
	Set before = ##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode")
	Set was = $Select($IsObject(before): before.Value, 1: "")
	Kill before
	Set cases = $ListBuild($ListBuild("{}", "[""demoMode""]"), $ListBuild("{""demoMode"": 1}", "[""demoMode""]"), $ListBuild("{""demoMode"": ""true""}", "[""demoMode""]"), $ListBuild("{""demoMode"": null}", "[""demoMode""]"), $ListBuild("{""demoMode"": true, ""x"": 1}", "[]"), $ListBuild("[true]", "[]"), $ListBuild("true", "[]"), $ListBuild("", "[]"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set body = ..Call("SaveDemoMode", $List(case, 1), session, .response)
		Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|"_$List(case, 2)_"}", "'"_$List(case, 1)_"': 400 bad_settings")
		Do $$$AssertEquals($Piece(body, """", 6), "bad_settings", "'"_$List(case, 1)_"': with the code")
	}
	Set after = ##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode")
	Do $$$AssertEquals($Select($IsObject(after): after.Value, 1: ""), was, "demo mode did not change")
}

/// POST /v1/settings/channels (Stories 21.2 and 21.6, with the outgoing server): on the online demo it answers 409 not_available with the accepted sentence before the body is read, and offers and
/// submits nothing; a password over 256 characters is 400 bad_settings naming password with nothing offered; a refused body (a value with @{, an unknown
/// field, a bad address, no object) is 400 through the production with nothing written and the offered password withdrawn; and a body that holds the
/// password never answers it. The number of hand-off resources is the same after every call.
Method TestChannelsRoute()
{
	If '..Guard() Quit
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set session = ..Session()
	Set was = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set before = ..Handoffs()
	Set rows = ..SaveSettingsRows()
	Set secret = "zzchannelspw"_$Job_$Random(100000)
	Set address = "zzchan"_..Number_"x"_$Random(1000000)_"@example.com", user = "zzchanuser"_..Number_"x"_$Random(1000000)
	Set ok = {"address": (address), "incoming": "pop.example.com", "outgoing": "smtp.example.com", "user": (user), "password": (secret)}
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Set body = ..Call("SaveChannels", ok.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status_"|"_body, "409 Conflict|{""error"":{""code"":""not_available"",""message"":""Email can't be connected on the online demo. Nothing was changed.""}}", "the online demo: 409 not_available with the accepted sentence")
		Do $$$AssertEquals(..Handoffs()_"|"_..SaveSettingsRows(), before_"|"_rows, "nothing was offered and nothing submitted")
		Do $$$AssertEquals(body [ secret, 0, "and the answer does not hold the password")
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
		Set long = {"address": "zzchannels@example.com", "incoming": "pop.example.com", "user": "zzchannels", "password": ($Translate($Justify("", 257), " ", "p"))}
		Set body = ..Call("SaveChannels", long.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""password""]}", "a password of 257 characters: 400 bad_settings naming password")
		Do $$$AssertEquals(..Handoffs()_"|"_..SaveSettingsRows(), before_"|"_rows, "nothing was offered and nothing submitted")
		For type = "number", "object" {
			Set odd = {}.%FromJSON(ok.%ToJSON())
			If type = "number" {
				Do odd.%Set("password", 98765432123, "number")
			} Else {
				Do odd.%Set("password", {"p": "zzpw98765432123"})
			}
			Set body = ..Call("SaveChannels", odd.%ToJSON(), session, .response)
			Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""password""]}", "a password that is a JSON "_type_": 400 bad_settings naming password")
			Do $$$AssertEquals(..Handoffs()_"|"_..SaveSettingsRows(), before_"|"_rows, type_": nothing was offered and nothing submitted")
			Do $$$AssertEquals(..SaveSettingsHold("98765432123"), 0, type_": no SaveSettings message holds the value")
		}
		Set body = ..Call("SaveChannels", "[1]", session, .response)
		Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[]}", "a body that is not an object: 400 bad_settings, no field")
		Do $$$AssertEquals(..Handoffs()_"|"_..SaveSettingsRows(), before_"|"_rows, "nothing was offered and nothing submitted")
		For field = "address", "incoming", "outgoing", "user" {
			Set bad = {}.%FromJSON(ok.%ToJSON())
			Do bad.%Set(field, "x@{y", "string")
			Set body = ..Call("SaveChannels", bad.%ToJSON(), session, .response)
			Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""" _field_ """]}", "a "_field_" with @{: 400 naming it")
			Do $$$AssertEquals(..Handoffs(), before, field_": the offered password was withdrawn")
			Do $$$AssertEquals(body [ secret, 0, field_": the answer does not hold the password")
		}
		// Story 21.14: the address and the user name are checked like the secrets, and the stored message holds only their references
		Set rows = ..SaveSettingsRows()
		For name = "address", "user" {
			For type = "number", "object", "long" {
				Set odd = {}.%FromJSON(ok.%ToJSON())
				If type = "number" {
					Do odd.%Set(name, 98765432123, "number")
				} ElseIf type = "object" {
					Do odd.%Set(name, {"p": "zzval98765432123"})
				} Else {
					Do odd.%Set(name, $Translate($Justify("", 257), " ", "a"), "string")
				}
				Set body = ..Call("SaveChannels", odd.%ToJSON(), session, .response)
				Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""" _name_ """]}", "a "_name_" that is a "_type_": 400 bad_settings naming it")
				Do $$$AssertEquals(..Handoffs()_"|"_..SaveSettingsRows(), before_"|"_rows, name_" "_type_": nothing was offered and nothing submitted")
				Do $$$AssertEquals(..SaveSettingsHold("98765432123")_..SaveSettingsHold("zzval98765432123"), "00", name_" "_type_": no SaveSettings message holds the value")
			}
		}
		Set held = {}.%FromJSON(ok.%ToJSON())
		Do held.%Set("incoming", "x@{y", "string")
		Set body = ..Call("SaveChannels", held.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""incoming""]}", "a body refused after the take: 400 naming incoming")
		Do $$$AssertEquals(..Handoffs(), before, "the references were taken back")
		Set stored = ##class(OcuTalon.Test.Core.SecretHandoff).NewestChanges()
		Do $$$AssertEquals(stored.%GetTypeOf("address")_"|"_stored.%GetTypeOf("user"), "string|string", "the stored message has an address and a user")
		Do $$$AssertTrue($Match(stored.address, ..#REFERENCE) && $Match(stored.user, ..#REFERENCE), "and they are references of the hand-off")
		Do $$$AssertEquals(stored.incoming_"|"_stored.outgoing, "x@{y|smtp.example.com", "while incoming and outgoing are plain")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(address)_##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(user), "", "no trace global holds the address or the user name")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("Ens_Util.Log", "Text", address)_##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("Ens_Util.Log", "Text", user), "00", "no log row holds them")
		Do $$$AssertEquals(body [ address, 0, "and the answer does not hold the address")
		Set rows = ..SaveSettingsRows()
		Set clientSecret = "zzclientsecret"_$Job_$Random(100000)
		Set long = {"address": "zzchannels@example.com", "incoming": "pop.example.com", "user": "zzchannels", "signIn": "google", "clientId": "zz-id.example", "clientSecret": ($Translate($Justify("", 257), " ", "c"))}
		Set body = ..Call("SaveChannels", long.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""clientSecret""]}", "a client secret of 257 characters: 400 bad_settings naming clientSecret")
		Do $$$AssertEquals(..Handoffs()_"|"_..SaveSettingsRows(), before_"|"_rows, "nothing was offered and nothing submitted")
		Set odd = {}.%FromJSON(long.%ToJSON())
		Do odd.%Set("clientSecret", 98765432123, "number")
		Set body = ..Call("SaveChannels", odd.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""clientSecret""]}", "a client secret that is a JSON number: 400 naming clientSecret")
		Do $$$AssertEquals(..SaveSettingsHold("98765432123"), 0, "no SaveSettings message holds the value")
		Set odd = {}.%FromJSON(long.%ToJSON())
		Do odd.%Set("clientSecret", clientSecret, "string")
		Do odd.%Set("origin", "http://zz.example", "string")
		Set body = ..Call("SaveChannels", odd.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""origin""]}", "a body that names the origin is refused naming origin")
		Do $$$AssertEquals(..Handoffs()_"|"_..SaveSettingsRows(), before_"|"_rows, "nothing was offered and nothing submitted")
		Do $$$AssertEquals(body [ clientSecret, 0, "and the answer does not hold the client secret")
		Set refused = {"address": "zzchannels@example.com", "incoming": "pop.example.com", "user": "zzchannels", "signIn": "google", "clientId": "zz id.example", "clientSecret": (clientSecret)}
		Set body = ..Call("SaveChannels", refused.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", "a provider body with a bad client ID goes to the production and is refused")
		Do $$$AssertEquals(..Handoffs(), before, "the offered client secret was taken or withdrawn")
		Do $$$AssertEquals(body [ clientSecret, 0, "and the answer does not hold it")
		Set ^OcuTalonTest("ApiProbe", "submit") = "fail"
		Set both = {}.%FromJSON(ok.%ToJSON())
		Do both.%Set("clientSecret", clientSecret, "string")
		Set body = ..Call("SaveChannels", both.%ToJSON(), session, .response)
		Kill ^OcuTalonTest("ApiProbe", "submit")
		Do $$$AssertEquals(response.Status, "500 Internal Server Error", "a command that the production does not take: 500 server_error")
		Do $$$AssertEquals(..Handoffs(), before, "both offered secrets were withdrawn, though nothing took them")
		Do $$$AssertEquals(body [ secret, 0, "and the answer does not hold the password")
		Do $$$AssertEquals(body [ clientSecret, 0, "or the client secret")
		Do $$$AssertEquals(..SaveSettingsHold(clientSecret), 0, "and no SaveSettings message holds the client secret")
		Set bad = {}.%FromJSON(ok.%ToJSON())
		Do bad.%Set("extra", 1, "number")
		Set body = ..Call("SaveChannels", bad.%ToJSON(), session, .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", "an unknown field: 400")
		Do $$$AssertEquals(..Handoffs(), before, "the offered password was withdrawn")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("Ens_Util.Log", "Text", secret)_##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("Ens_Util.Log", "Text", clientSecret), "00", "no log row holds the password or the client secret")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).Leaks(clientSecret), "", "no ^OcuTalon* global holds the client secret")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(clientSecret), "", "no trace global holds the client secret")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).Leaks(secret), "", "no ^OcuTalon* global holds it")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(secret), "", "no trace global holds it")
		Do $$$AssertEquals(..SaveSettingsHold(secret), 0, "and no SaveSettings message holds it")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", was)
}

/// POST /v1/settings/channels/sign-in (Story 21.3): on the online demo it is 409 not_available before the body is read; the body is exactly {"action": "start" or "check"}
/// (anything else is 400 bad_settings naming action, and nothing is submitted); the command carries the action, the request's origin, the IRIS user and the session; started and
/// checked are 200 with the CommandResult's Data; a client that is not registered is 400 naming signIn; any other outcome, an error status or no result is 500.
/// The origin that a sign-in start sends is the scheme (https only on a secure connection) and the Host header of the request.
Method TestSignInOrigin()
{
	If '..Guard() Quit
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set session = ..Session()
	Set was = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
		For secure = 0, 1 {
			Kill ^OcuTalonTest("ApiProbe", "signin")
			New %request, %response, %session
			Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", "POST", "application/json", "", "", "zz-host.example:52773", secure)
			Set stream = ##class(%CSP.CharacterStream).%New()
			Do stream.Write("{""action"": ""start""}")
			Do stream.Rewind()
			Set %request.Content = stream
			Set %response = ##class(%CSP.Response).%New()
			Set %response.ContentType = ""
			Set %session = ##class(%CSP.Session).%New("ZzSettingsApi"_..Number, 0)
			Set %session.Data("OcuTalon.SessionRef") = session
			Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, "SignInMail")
			Do $$$AssertStatusOK(sc, "SignInMail returns OK")
			Do $$$AssertEquals($Piece($Get(^OcuTalonTest("ApiProbe", "signin")), "|", 2), $Select(secure: "https", 1: "http")_"://zz-host.example:52773", "the origin sent is the scheme of the connection and the Host header (secure "_secure_")")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", was)
}

Method TestSignInRoute()
{
	If '..Guard() Quit
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set session = ..Session()
	Set was = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Kill ^OcuTalonTest("ApiProbe", "signin")
		Set body = ..Call("SignInMail", "{""action"": ""start""}", session, .response)
		Do $$$AssertEquals(response.Status_"|"_body, "409 Conflict|{""error"":{""code"":""not_available"",""message"":""Email can't be connected on the online demo. Nothing was changed.""}}", "the online demo: 409 not_available with the accepted sentence")
		Do $$$AssertEquals($Data(^OcuTalonTest("ApiProbe", "signin")), 0, "and nothing was submitted")
		Set body = ..Call("SignInMail", "not json", session, .response)
		Do $$$AssertEquals(response.Status, "409 Conflict", "the online demo answers before it reads the body")
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
		For text = "[1]", "not json", "{}", "{""action"": 5}", "{""action"": ""revoke""}", "{""action"": ""Start""}", "{""action"": ""start"", ""extra"": 1}", "{""action"": null}" {
			Set body = ..Call("SignInMail", text, session, .response)
			Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""action""]}", text_": 400 bad_settings naming action")
		}
		Do $$$AssertEquals($Data(^OcuTalonTest("ApiProbe", "signin")), 0, "no bad body was submitted")
		Set body = ..Call("SignInMail", "{""action"": ""start""}", session, .response)
		Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""started"",""url"":""https://zz.example/start""}", "start: 200 started with the address")
		Set seen = ^OcuTalonTest("ApiProbe", "signin")
		Do $$$AssertEquals($Piece(seen, "|", 1)_"|"_$Piece(seen, "|", 3)_"|"_$Piece(seen, "|", 4), "start|"_$Username_"|"_session, "the command names the action, the IRIS user of the call and the session")
		Do $$$AssertTrue($Piece(seen, "|", 2) [ "://", "and the request's origin")
		Set ^OcuTalonTest("ApiProbe", "signinResult") = "1|checked|{""signedIn"":true}"
		Set body = ..Call("SignInMail", "{""action"": ""check""}", session, .response)
		Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""checked"",""signedIn"":true}", "check: 200 checked with signedIn a boolean")
		Set ^OcuTalonTest("ApiProbe", "signinResult") = "0|refused|{""fields"":[""signIn""]}"
		Set body = ..Call("SignInMail", "{""action"": ""start""}", session, .response)
		Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""signIn""]}", "a client that is not registered: 400 naming signIn")
		Set ^OcuTalonTest("ApiProbe", "signinResult") = "0|not_available|"
		Set body = ..Call("SignInMail", "{""action"": ""start""}", session, .response)
		Do $$$AssertEquals(response.Status, "409 Conflict", "not_available from SettingsOps: 409")
		For answer = "fail", "none", "0|failed|", "1|other|" {
			Set ^OcuTalonTest("ApiProbe", "signinResult") = answer
			Set body = ..Call("SignInMail", "{""action"": ""check""}", session, .response)
			Do $$$AssertEquals(response.Status, "500 Internal Server Error", "the answer '"_answer_"': 500 server_error")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Kill ^OcuTalonTest("ApiProbe", "signin"), ^OcuTalonTest("ApiProbe", "signinResult")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", was)
}

/// The number of hand-off resources that exist.
ClassMethod Handoffs() As %Integer [ Private ]
{
	Set count = 0
	Set list = $SYSTEM.Event.List()
	Set position = 0
	While $ListNext(list, position, name) {
		If name [ ##class(OcuTalon.Core.SecretHandoff).#RESOURCE Set count = count + 1
	}
	Quit count
}

/// The number of SaveSettings messages that the production has stored.
ClassMethod SaveSettingsRows() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Msg_Command.SaveSettings")
	If result.%SQLCODE < 0 Quit -1
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// 1 when a stored SaveSettings message holds the text in its Changes.
ClassMethod SaveSettingsHold(text As %String) As %Boolean [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Msg_Command.SaveSettings WHERE Changes [ ?", text)
	If result.%SQLCODE < 0 Quit 1
	Do result.%Next()
	Quit (+result.%GetData(1) > 0)
}

/// Every outcome of a save has its status, code and text.
Method TestAnswerMapping()
{
	Set cases = $ListBuild($ListBuild(1, "done", "", "", "200 OK", "done"), $ListBuild(1, "on", "", "on", "200 OK", "done"), $ListBuild(1, "off_kept", "", "off", "200 OK", "done"), $ListBuild(0, "refused", "{""fields"":[""a"",""b""]}", "", "400 Bad Request", "bad_settings"), $ListBuild(0, "refused", "", "", "400 Bad Request", "bad_settings"), $ListBuild(0, "not_built", "", "", "501 Not Implemented", "not_built"), $ListBuild(0, "not_available", "", "", "409 Conflict", "not_available"), $ListBuild(0, "step_failed", "", "on", "409 Conflict", "demo_step_failed"), $ListBuild(0, "step_failed", "", "", "500 Internal Server Error", "server_error"), $ListBuild(0, "not_audited", "", "on", "500 Internal Server Error", "server_error"), $ListBuild(0, "failed", "", "", "500 Internal Server Error", "server_error"), $ListBuild(0, "unknown_command", "", "", "500 Internal Server Error", "server_error"), $ListBuild(0, "zz_other", "", "", "500 Internal Server Error", "server_error"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set result = ##class(OcuTalon.Msg.CommandResult).%New()
		Set result.Ok = $List(case, 1), result.Outcome = $List(case, 2), result.Data = $List(case, 3), result.Message = "developer text that no user sees"
		Set body = ..Answer(result, $List(case, 4), .response)
		Set label = $List(case, 2)_" ("_$List(case, 4)_")"
		Do $$$AssertEquals(response.Status, $List(case, 5), label_": the status")
		If $List(case, 1) {
			Do $$$AssertEquals({}.%FromJSON(body).result, "done", label_": result done")
		} Else {
			Do $$$AssertEquals($Piece(body, """", 6), $List(case, 6), label_": the code")
			Do $$$AssertTrue(body '[ "developer text", label_": the developer text is never sent")
		}
	}
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Outcome = "refused", result.Data = "{""fields"":[""a"",""b""]}"
	Set body = ..Answer(result, "", .response)
	Do $$$AssertEquals(body, "{""error"":{""code"":""bad_settings"",""message"":""Couldn't save. Nothing was changed.""},""fields"":[""a"",""b""]}", "a refusal carries the ruled text and its fields")
	Set result.Outcome = "step_failed"
	Set body = ..Answer(result, "off", .response)
	Do $$$AssertEquals(body, "{""error"":{""code"":""demo_step_failed"",""message"":""Demo mode is set to off, but the switch didn't finish. OcuTalon tries again at its next start.""}}", "a Demo step that failed has the ruled text, never 'Nothing was changed.'")
}

/// The snapshot's admin follows the role and comes right after user.
Method TestStateHasAdmin()
{
	Set session = ##class(OcuTalon.Data.Session).ForUser("zzsettingsapi"_..Number, .sc)
	Do $$$AssertStatusOK(sc, "the fixture session")
	For case = "OcuTalonUser|0", "OcuTalonUser,OcuTalonAdmin|1", "OcuTalonUser,%All|0" {
		Set ^OcuTalonTest("ApiProbe", "roles") = $Piece(case, "|", 1)
		Set body = $ClassMethod(..#PROBE, "StateBody", session)
		Do $$$AssertEquals(body.%GetTypeOf("admin"), "boolean", $Piece(case, "|", 1)_": admin is a boolean")
		Do $$$AssertEquals(body.admin + 0, +$Piece(case, "|", 2), $Piece(case, "|", 1)_": admin follows the role")
		Set keys = ""
		Set iterator = body.%GetIterator()
		While iterator.%GetNext(.key) {
			Set keys = keys_$Select(keys = "": "", 1: ",")_key
			If key = "admin" Quit
		}
		Do $$$AssertTrue(keys [ "rail,user,admin", "admin comes right after user: "_keys)
	}
}

/// --- helpers ---
/// The token budget, the daily cap and the zone that the bridge holds, as "<budget>|<cap>|<zone>" (Bridge.Settings.Values and Bridge.Time.Zone).
ClassMethod BridgeValues() As %String [ Private ]
{
	Set values = ##class(OcuTalon.Bridge.Settings).Values()
	Quit values.%Get("DecisionTokenBudget")_"|"_values.%Get("DailyCostCapUSD")_"|"_##class(OcuTalon.Bridge.Time).Zone()
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

/// The fixture session of the IRIS user who runs the tests (the user that Ownership.SessionRef resolves the CSP session for).
Method Session() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Do ..Traces.%Push(##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef)
	Quit ref
}

/// Runs OnPreDispatch of the probe for the URL and method with a stand-in request; returns what it wrote. continue is the dispatch flag it left.
Method PreDispatch(url As %String, method As %String, contentType As %String, header As %String, origin As %String, host As %String, Output response, Output continue) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", method, contentType, header, origin, host)
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New("ZzSettingsApi"_..Number, 0)
	Set %response.ContentType = ""
	Set continue = 1
	Set sc = ##class(OcuTalon.Test.Web.Api).Capture(.capture)
	If $SYSTEM.Status.IsOK(sc) {
		Try {
			Set sc = $ClassMethod(..#PROBE, "OnPreDispatch", url, method, .continue)
		} Catch exception {
			Set sc = exception.AsStatus()
		}
	}
	Set written = ##class(OcuTalon.Test.Web.Api).Collect(.capture)
	Set response = %response
	Do $$$AssertStatusOK(sc, "OnPreDispatch returns OK")
	Quit written
}

/// Calls the route method of the probe as the CSP session of the session (body is the request's content); response is the %response.
Method Call(method As %String, body As %String, session As %String = "", Output response) As %String [ Private ]
{
	New %request, %response, %session
	Set application = "/ocutalon/api/"
	Set %request = $Select(body = "": ##class(OcuTalon.Test.Web.StubRequest).Make(application), 1: ##class(OcuTalon.Test.Web.StubRequest).MakeBody(application, body))
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzSettingsApi"_..Number, 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, method)
	Do $$$AssertStatusOK(sc, method_" returns OK")
	Set response = %response
	Quit written
}

/// The HTTP answer to a CommandResult through Answer; response is the %response.
Method Answer(result As OcuTalon.Msg.CommandResult, word As %String, Output response) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/api/")
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzSettingsApi"_..Number, 0)
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, "AnswerFor", result, word)
	Set response = %response
	Quit written
}

/// Deletes the rows of the keys.
Method Clear() [ Private ]
{
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(key)
		Kill ^||OcuTalon.Setting(key)
	}
}

/// The stored value of the key, "" when there is no row.
Method Row(key As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	Quit $Select($IsObject(row): row.Value, 1: "")
}

/// The number of rows of the keys.
Method Rows() As %Integer [ Private ]
{
	Set count = 0
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		If ##class(OcuTalon.Data.Setting).KeyIndexExists(key) Set count = count + 1
	}
	Quit count
}

}
