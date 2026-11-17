/// The Slack routes of Settings > Channels (Story 27.3; AD-1, AD-4, AD-13, AD-24), forwarded from OcuTalon.Web.Api's URL map (<Map Prefix="/v1/settings/channels/slack">).
/// Admin only: Api's OnPreDispatch refuses a signed-in user without OcuTalonAdmin with 403 not_admin before the forward, and every route checks it again, a viewer included. On
/// the online demo every route answers 409 not_available with the text settings.slackOffOnDemo before anything is read, handed over or submitted. The class reads no stored
/// row: the state, the list and the roster come from SettingsOps in the production job, as the SecretHandoff uri of one ListSlackLinks answer, taken once.
///   - GET /v1/settings/channels/slack answers 200 {"state": "on" or "off", "path", "links": [{ref, user, member}], "users": [name]} as ListSlackLinks made it. A list that
///     cannot be had, a failed take and an error are 500 server_error.
///   - POST /v1/settings/channels/slack takes exactly {"user": string, "member": string}; any other body is 400 bad_settings with the names of the fields that are missing, extra
///     or of the wrong type, before anything is handed over. The body goes into one SecretHandoff and one LinkSlackMember (origin web_admin, ActingUser the IRIS user of the call,
///     SessionRef the CSP session's) is submitted; the handoff is discarded on every path. done is 200 {"result": "done", "message", "link": {ref, user, member}}; refused is 400
///     bad_slack_link with {fields, reason} and the reason's catalog text as the message (bad_member, member_taken, user_taken with the user's name filled in here,
///     user_unknown, no_workspace); not_available is 409; any other outcome is 500 server_error.
///   - DELETE /v1/settings/channels/slack/<ref> submits one UnlinkSlackMember: done is 200 {"result": "done", "message"}, an unknown Ref 404 not_found, not_available 409 and any
///     other outcome 500 server_error.
/// No member id or user name is in a command, a result, a log line or a global: they reach SettingsOps only through SecretHandoff and the admin's own response.
Class OcuTalon.Web.SlackSettings Extends OcuTalon.Web.Api
{

/// The longest Ref of a link; a longer one names no link.
Parameter REFMAX = 22;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="" Method="GET" Call="List"/>
<Route Url="" Method="POST" Call="Save"/>
<Route Url="/:ref" Method="DELETE" Call="Remove"/>
</Routes>
}

/// 1 when the online-demo flag is set. A test subclass overrides it.
ClassMethod OnlineDemo() As %Boolean [ Private ]
{
	Quit (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
}

/// "" when the route may run, else the refusal that has been written: 403 not_admin for a user who does not hold OcuTalonAdmin now or for a viewer, 409 not_available on the
/// online demo.
ClassMethod Refusal() As %Status [ Private ]
{
	If '..IsAdmin() || ..ViewerOnly() Quit ..Fail(403, "not_admin", ..#MESSAGENOTADMIN)
	If ..OnlineDemo() Quit ..Fail(409, "not_available", ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.slackOffOnDemo"))
	Quit ""
}

/// The text of a catalog key for the web, with the slots given; the plain not-saved text when the key cannot be rendered.
ClassMethod Text(key As %String, slots As %DynamicObject = "") As %String [ Private ]
{
	Set text = ##class(OcuTalon.Msg.Catalog).Render(key, slots, "web", .sc)
	Quit $Select($SYSTEM.Status.IsError(sc) || (text = ""): ..#MESSAGEBADSETTINGS, 1: text)
}

/// GET /v1/settings/channels/slack: see the class description.
ClassMethod List() As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set uri = ""
	Set answer = ""
	Try {
		Set command = ##class(OcuTalon.Msg.Command.ListSlackLinks).%New()
		Set command.SessionRef = sessionRef
		Set sc = ..Submit(command, .result)
		If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
		If '$IsObject(result) Throw ##class(%Exception.General).%New("CommandsIn answered no result")
		If result.Outcome = "not_available" {
			Set answer = ..Fail(409, "not_available", result.Message)
		} ElseIf result.Ok && (result.Outcome = "listed") {
			Set uri = ##class(%DynamicAbstractObject).%FromJSON(result.Data).handoff
			Set sc = ##class(OcuTalon.Core.SecretHandoff).Take(uri, .json, 5)
			Set uri = ""
			If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
			Set body = ##class(%DynamicAbstractObject).%FromJSON(json)
			Kill json
			If '$IsObject(body) || 'body.%IsA("%Library.DynamicObject") Throw ##class(%Exception.General).%New("The Slack list is not an object")
			Set %response.ContentType = ..#CONTENTTYPE
			Write body.%ToJSON()
			Set answer = $SYSTEM.Status.OK()
		} Else {
			Set answer = ..ServerError($SYSTEM.Status.Error(5001, "The Slack list was answered "_result.Outcome))
		}
	} Catch exception {
		Set answer = ..ServerError(exception.AsStatus())
	}
	If uri '= "" Do ##class(OcuTalon.Core.SecretHandoff).Take(uri, .discard, 0)
	Quit answer
}

/// POST /v1/settings/channels/slack: see the class description.
ClassMethod Save() As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	If '..SettingsBody(.body) Quit ..BadSettings([])
	Set bad = ..ShapeFields(body)
	If bad.%Size() Quit ..BadSettings(bad)
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set answer = ""
	Try {
		Set command = ##class(OcuTalon.Msg.Command.LinkSlackMember).%New()
		Set command.ActingUser = $Username
		Set command.SessionRef = sessionRef
		Set sc = ..HandOff(command, {"user": (body.user), "member": (body.member)}.%ToJSON(), .result)
		If $SYSTEM.Status.IsError(sc) {
			Set answer = ..ServerError(sc)
		} Else {
			Set answer = ..Answer(result, body.user, body.member)
		}
	} Catch exception {
		Set answer = ..ServerError(exception.AsStatus())
	}
	Quit answer
}

/// DELETE /v1/settings/channels/slack/:ref: see the class description.
ClassMethod Remove(ref As %String) As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	Set ref = $Get(ref)
	If (ref = "") || ($Length(ref) > ..#REFMAX) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Try {
		Set command = ##class(OcuTalon.Msg.Command.UnlinkSlackMember).%New()
		Set command.LinkRef = ref
		Set command.ActingUser = $Username
		Set command.SessionRef = sessionRef
		Set sc = ..Submit(command, .result)
		If $SYSTEM.Status.IsError(sc) Return ..ServerError(sc)
		If '$IsObject(result) Return ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
		If result.Ok && (result.Outcome = "done") {
			Set %response.ContentType = ..#CONTENTTYPE
			Write {"result": "done", "message": (..Text("settings.slackUnlinked"))}.%ToJSON()
			Return $SYSTEM.Status.OK()
		}
		If result.Outcome = "not_found" Return ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
		If result.Outcome = "not_available" Return ..Fail(409, "not_available", result.Message)
		Return ..ServerError($SYSTEM.Status.Error(5001, "The Slack unlink was answered "_result.Outcome))
	} Catch exception {
		Return ..ServerError(exception.AsStatus())
	}
	Quit $SYSTEM.Status.OK()
}

/// The names of the fields of the body that are wrong, as a dynamic array: user and member must each be present as a string, and any other member is named too.
ClassMethod ShapeFields(body As %DynamicObject) As %DynamicArray [ Private ]
{
	Set bad = []
	If body.%GetTypeOf("user") '= "string" Do bad.%Push("user")
	If body.%GetTypeOf("member") '= "string" Do bad.%Push("member")
	Set iterator = body.%GetIterator()
	While iterator.%GetNext(.name) {
		If (name '= "user") && (name '= "member") Do bad.%Push($Extract(name, 1, 32))
	}
	Quit bad
}

/// The answer from a link's CommandResult: see the class description. user and member are the request's, for the link object of a done answer (the member as SettingsOps stores it:
/// trimmed and upper-cased) and for the user's name in the user_taken text.
ClassMethod Answer(result As OcuTalon.Msg.CommandResult, user As %String, member As %String) As %Status [ Private ]
{
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	Set outcome = result.Outcome
	If result.Ok && (outcome = "done") {
		Try {
			Set ref = ##class(%DynamicAbstractObject).%FromJSON(result.Data).ref
		} Catch exception {
			Return ..ServerError(exception.AsStatus())
		}
		Set link = {"ref": (ref), "user": ($ZStrip(user, "<>W")), "member": ($ZConvert($ZStrip(member, "<>W"), "U"))}
		Set %response.ContentType = ..#CONTENTTYPE
		Write {"result": "done", "message": (..Text("settings.slackLinked")), "link": (link)}.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	If outcome = "refused" {
		Try {
			Set data = ##class(%DynamicAbstractObject).%FromJSON(result.Data)
			Set reason = data.reason
			Set field = data.field
		} Catch {
			Set reason = ""
			Set field = ""
		}
		Set text = $Case($Get(reason),
			"bad_member": ..Text("settings.slackBadMemberId"),
			"member_taken": ..Text("settings.slackMemberTaken"),
			"user_taken": ..Text("settings.slackUserTaken", {"user": ($ZStrip(user, "<>W"))}),
			"user_unknown": ..Text("settings.slackUnknownUser"),
			"no_workspace": ..Text("settings.slackNoWorkspace"),
			: "")
		If text = "" Quit ..ServerError($SYSTEM.Status.Error(5001, "The Slack link was refused for an unknown reason"))
		Quit ..Fail(400, "bad_slack_link", text, , {"fields": ($Select($Get(field) = "": [], 1: [($Get(field))])), "reason": (reason)})
	}
	If outcome = "not_available" Quit ..Fail(409, "not_available", result.Message)
	Quit ..ServerError($SYSTEM.Status.Error(5001, "The Slack link was answered "_outcome))
}

}
