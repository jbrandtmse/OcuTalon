/// The webhook routes of Settings > Channels (Story 35.3; AD-1, AD-4, AD-13, AD-19), forwarded from OcuTalon.Web.Api's URL map
/// (<Map Prefix="/v1/settings/channels/webhooks">). Admin only: Api's OnPreDispatch refuses a signed-in user without OcuTalonAdmin with 403 not_admin before the
/// forward, and every route checks it again. A webhook belongs to the CSP session's own session (the Ref comes from the CSP session, never from the request).
///   - GET /v1/settings/channels/webhooks answers 200 {"webhooks":[{ref, name, path, createdAt}]}, the session's own webhooks in creation order, path being
///     /ocutalon/hook/<ref>; a read that fails is 500 server_error. The rows are read with object access.
///   - POST /v1/settings/channels/webhooks takes exactly {"name": string, "secret": string} and answers 200 {"result":"done","message","webhook":{ref, name, path,
///     createdAt}}. A body of another shape is 400 bad_webhook with fields {}; a name over 1,000 characters or a secret over 256 characters is 400
///     bad_webhook with the field's text; a name or secret that SettingsOps refuses, or a name already used, is 400 bad_webhook with fields {name, secret} (each the
///     field's catalog text) and the message "Couldn't save. Nothing was changed.".
///   - POST /v1/settings/channels/webhooks/<ref>/secret takes exactly {"secret": string} and answers 200 {"result":"done","message"}. A Ref that is unknown or that
///     another session owns is 404 not_found before anything is read from the body or handed over; the refusals are 400 bad_webhook as above.
///   - On the online demo every route answers 409 not_available with the text settings.webhooksOffOnDemo, before anything is read or written.
/// The secret reaches SettingsOps only through OcuTalon.Core.SecretHandoff: Put before the command is submitted, and Discard on every path after it, an error
/// included. The command holds the handoff uri and no secret, no route writes a table (List and the Ref check read Data.Webhook), and no answer, log line or audit entry holds the secret.
/// Any other outcome, an error status and an exception are 500 server_error. Every state-changing call is submitted with origin web_admin.
Class OcuTalon.Web.HookSettings Extends OcuTalon.Web.Api
{

/// The most characters of a name that the route hands on; SettingsOps refuses a name over 64 itself.
Parameter NAMEHANDOFFMAX = 1000;

/// The path of a webhook below the host.
Parameter HOOKPATH = "/ocutalon/hook/";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="" Method="GET" Call="List"/>
<Route Url="" Method="POST" Call="Create"/>
<Route Url="/:ref/secret" Method="POST" Call="Rotate"/>
</Routes>
}

/// 1 when the online-demo flag is set. A test subclass overrides it.
ClassMethod OnlineDemo() As %Boolean [ Private ]
{
	Quit (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
}

/// "" when the route may run, else the refusal that has been written: 403 not_admin for a user without OcuTalonAdmin, 409 not_available on the online demo.
ClassMethod Refusal() As %Status [ Private ]
{
	If '..IsAdmin() Quit ..Fail(403, "not_admin", ..#MESSAGENOTADMIN)
	If ..OnlineDemo() Quit ..Fail(409, "not_available", ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.webhooksOffOnDemo"))
	Quit ""
}

/// GET /v1/settings/channels/webhooks: see the class description.
ClassMethod List() As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set webhooks = []
	Try {
		Set refs = ##class(OcuTalon.Data.Webhook).ForSession(sessionRef)
		Set position = 0
		While $ListNext(refs, position, ref) {
			Set row = ##class(OcuTalon.Data.Webhook).Lookup(ref)
			If $IsObject(row) Do webhooks.%Push(..WebhookObject(row.Ref, row.Name, row.CreatedAt))
		}
	} Catch exception {
		Return ..ServerError(exception.AsStatus())
	}
	Set %response.ContentType = ..#CONTENTTYPE
	Write {"webhooks": (webhooks)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// POST /v1/settings/channels/webhooks: see the class description.
ClassMethod Create() As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	If '..SettingsBody(.body) || (body.%Size() '= 2) || (body.%GetTypeOf("name") '= "string") || (body.%GetTypeOf("secret") '= "string") Quit ..BadWebhook({})
	Set fields = ..ShapeFields(body.name, body.secret)
	If fields.%Size() Quit ..BadWebhook(fields)
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set command = ##class(OcuTalon.Msg.Command.CreateWebhook).%New()
	Set command.Name = body.name
	Set command.ActingUser = $Username
	Set command.SessionRef = sessionRef
	Quit ..Hand(command, body.secret, "create")
}

/// POST /v1/settings/channels/webhooks/:ref/secret: see the class description.
ClassMethod Rotate(ref As %String) As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set row = ##class(OcuTalon.Data.Webhook).Lookup($Get(ref))
	If '$IsObject(row) || (row.SessionRef '= sessionRef) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If '..SettingsBody(.body) || (body.%Size() '= 1) || (body.%GetTypeOf("secret") '= "string") Quit ..BadWebhook({})
	Set fields = ..ShapeFields("", body.secret)
	If fields.%Size() Quit ..BadWebhook(fields)
	Set command = ##class(OcuTalon.Msg.Command.SetWebhookSecret).%New()
	Set command.WebhookRef = row.Ref
	Set command.ActingUser = $Username
	Set command.SessionRef = sessionRef
	Quit ..Hand(command, body.secret, "rotate")
}

/// The field errors of the lengths that the route checks before it hands a secret over: a name over NAMEHANDOFFMAX characters (name "" is not checked) and a
/// secret over Data.Webhook SECRETMAX characters, each as its catalog text.
ClassMethod ShapeFields(name As %String, secret As %String) As %DynamicObject [ Private ]
{
	Set fields = {}
	If $Length(name) > ..#NAMEHANDOFFMAX Do fields.%Set("name", ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.webhookBadName"))
	If $Length(secret) > ##class(OcuTalon.Data.Webhook).#SECRETMAX Do fields.%Set("secret", ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.webhookBadSecret"))
	Quit fields
}

/// Puts the secret into its handoff, sets the uri on the command, submits it (origin web_admin) and answers from its result. The handoff is discarded on
/// every path, an error thrown included, so no event resource outlives the request.
ClassMethod Hand(command As OcuTalon.Msg.Command, secret As %String, kind As %String) As %Status [ Private ]
{
	Set uri = "", answer = ""
	Try {
		Set sc = ##class(OcuTalon.Core.SecretHandoff).Put(secret, .uri)
		If $SYSTEM.Status.IsOK(sc) {
			Set command.Handoff = uri
			Set sc = ..Submit(command, .result)
		}
		If $SYSTEM.Status.IsError(sc) {
			Set answer = ..ServerError(sc)
		} Else {
			Set answer = ..Answer(result, kind)
		}
	} Catch exception {
		Set answer = ..ServerError(exception.AsStatus())
	}
	Do ##class(OcuTalon.Core.SecretHandoff).Discard(uri)
	Quit answer
}

/// Submits the command with origin web_admin and returns its CommandResult in result. A test subclass overrides it.
ClassMethod Submit(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
}

/// The answer from the CommandResult: done is 200 (a create with the webhook's {ref, name, path, createdAt}), refused and name_taken are 400 bad_webhook with
/// the result's fields, not_found is 404, not_available is 409 with the result's message, and every other outcome, and no result, is 500 server_error.
ClassMethod Answer(result As OcuTalon.Msg.CommandResult, kind As %String) As %Status [ Private ]
{
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	Set outcome = result.Outcome
	If result.Ok && (outcome = "done") {
		Set answer = {"result": "done", "message": (result.Message)}
		If kind = "create" {
			Try {
				Set data = ##class(%DynamicAbstractObject).%FromJSON(result.Data)
				Do answer.%Set("webhook", ..WebhookObject(data.ref, data.name, data.createdAt))
			} Catch exception {
				Return ..ServerError(exception.AsStatus())
			}
		}
		Set %response.ContentType = ..#CONTENTTYPE
		Write answer.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	If (outcome = "refused") || (outcome = "name_taken") {
		Try {
			Set fields = ##class(%DynamicAbstractObject).%FromJSON(result.Data).fields
		} Catch {
			Set fields = {}
		}
		Quit ..BadWebhook($Select($IsObject($Get(fields)): fields, 1: {}))
	}
	If outcome = "not_found" Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If outcome = "not_available" Quit ..Fail(409, "not_available", result.Message)
	Quit ..ServerError($SYSTEM.Status.Error(5001, "The webhook save was answered "_outcome))
}

/// {ref, name, path, createdAt}: the public view of a webhook, with no hash and no session.
ClassMethod WebhookObject(ref As %String, name As %String, createdAt As %String) As %DynamicObject [ Private ]
{
	Quit {"ref": (ref), "name": (name), "path": (..#HOOKPATH_ref), "createdAt": (createdAt)}
}

/// 400 bad_webhook with the plain not-saved message and the refused fields, each with its text.
ClassMethod BadWebhook(fields As %DynamicObject) As %Status [ Private ]
{
	Quit ..Fail(400, "bad_webhook", ..#MESSAGEBADSETTINGS, , {"fields": (fields)})
}

}
