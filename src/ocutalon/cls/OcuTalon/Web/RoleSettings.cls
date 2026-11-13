/// The Roles routes of Settings (Story 25.4; AD-1, AD-4, AD-13, AD-19, AD-24), forwarded from OcuTalon.Web.Api's URL map (<Map Prefix="/v1/settings/roles">). Admin only:
/// Api's OnPreDispatch refuses a signed-in user without OcuTalonAdmin with 403 not_admin before the forward, and every route checks it again. On the online demo every
/// route answers 409 not_available with MESSAGEROLESOFF before anything is read, handed over or submitted.
///   - GET /v1/settings/roles submits one ListRoles (origin web_admin, SessionRef the CSP session's) and answers 200 {"users":[{user, roles, managed}]}: every IRIS user who holds an OcuTalon role,
///     sorted by name without regard to case, roles the user's OcuTalon roles sorted, managed true for an account OcuTalon manages. The list reaches this process
///     only as the SecretHandoff uri in the result, taken once with Take. A ListRoles that is not available is 409, one that is not built 501, and any other
///     outcome, a failed take and an error 500 server_error.
///   - POST /v1/settings/roles takes exactly {"user": string, "role": string, "grant": boolean}; any other body is 400 bad_settings with the
///     names of the fields that are missing, extra or of the wrong type, before anything is handed over. The body goes into one SecretHandoff, and one SaveSettings
///     (slug roles, origin web_admin, Changes exactly {"handoff": uri}, ActingUser the IRIS user of the call, SessionRef the CSP session's) is submitted. The handoff is
///     discarded on every path, an error thrown included. done is 200 {"result":"done","changed"}, refused 400 bad_settings with {fields, reason} and the reason's
///     text as the message (role, user_unknown, user_system or user_managed), not_available 409, not_built 501, and any other outcome 500 server_error.
/// No other user's name is in a command, a result, a log line or a global: the names reach only IRIS's audit entry and the admin's response.
Class OcuTalon.Web.RoleSettings Extends OcuTalon.Web.Api
{

/// The answer on the online demo (409 not_available).
Parameter MESSAGEROLESOFF = "Roles can't be changed on the online demo.";

/// The message of a refusal by reason.
Parameter MESSAGEREASONROLE = "Only the approver and viewer roles can be changed here.";

Parameter MESSAGEREASONUNKNOWN = "There is no IRIS user with that name.";

Parameter MESSAGEREASONMANAGED = "OcuTalon manages this account, so its roles can't be changed here.";

Parameter MESSAGEREASONSYSTEM = "This is an IRIS system account, so its roles can't be changed here.";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="" Method="GET" Call="List"/>
<Route Url="" Method="POST" Call="Save"/>
</Routes>
}

/// 1 only when the install's roles class declares STEP6ROLES as exactly 1, which the story that creates the step 6 roles adds; the argument is the test seam.
ClassMethod RolesReady(roleClass As %String = "OcuTalon.Install.Step.Roles") As %Boolean
{
	Quit ($Parameter(roleClass, "STEP6ROLES") = 1)
}

/// 1 when the online-demo flag is set. A test subclass overrides it.
ClassMethod OnlineDemo() As %Boolean [ Private ]
{
	Quit (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
}

/// "" when the route may run, else the refusal that has been written: 403 not_admin for a user without OcuTalonAdmin or for a viewer, 409 not_available on the online demo.
ClassMethod Refusal() As %Status [ Private ]
{
	If '..IsAdmin() || ..ViewerOnly() Quit ..Fail(403, "not_admin", ..#MESSAGENOTADMIN)
	If ..OnlineDemo() Quit ..Fail(409, "not_available", ..#MESSAGEROLESOFF)
	Quit ""
}

/// GET /v1/settings/roles: see the class description.
ClassMethod List() As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set uri = ""
	Set answer = ""
	Try {
		Set command = ##class(OcuTalon.Msg.Command.ListRoles).%New()
		Set command.SessionRef = sessionRef
		Set sc = ..Submit(command, .result)
		If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
		If '$IsObject(result) Throw ##class(%Exception.General).%New("CommandsIn answered no result")
		If result.Outcome = "not_available" {
			Set answer = ..Fail(409, "not_available", ..#MESSAGEROLESOFF)
		} ElseIf result.Outcome = "not_built" {
			Set answer = ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
		} ElseIf result.Ok && (result.Outcome = "done") {
			Set uri = ##class(%DynamicAbstractObject).%FromJSON(result.Data).handoff
			Set sc = ##class(OcuTalon.Core.SecretHandoff).Take(uri, .json, 5)
			Set uri = ""
			If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
			Set users = ##class(%DynamicAbstractObject).%FromJSON(json)
			Set %response.ContentType = ..#CONTENTTYPE
			Write {"users": (users)}.%ToJSON()
			Set answer = $SYSTEM.Status.OK()
		} Else {
			Set answer = ..ServerError($SYSTEM.Status.Error(5001, "The list of roles was answered "_result.Outcome))
		}
	} Catch exception {
		Set answer = ..ServerError(exception.AsStatus())
	}
	If uri '= "" Do ##class(OcuTalon.Core.SecretHandoff).Take(uri, .discard, 0)
	Quit answer
}

/// POST /v1/settings/roles: see the class description.
ClassMethod Save() As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	If '..SettingsBody(.body) Quit ..BadSettings([])
	Set bad = ..ShapeFields(body)
	If bad.%Size() Quit ..BadSettings(bad)
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set uri = ""
	Set answer = ""
	Try {
		Set handed = {"user": (body.user), "role": (body.role)}
		Do handed.%Set("grant", body.grant, "boolean")
		Set sc = ..Offer(handed.%ToJSON(), .uri)
		If $SYSTEM.Status.IsOK(sc) {
			Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
			Set command.Slug = "roles"
			Set command.Changes = {"handoff": (uri)}.%ToJSON()
			Set command.ActingUser = $Username
			Set command.SessionRef = sessionRef
			Set sc = ..Submit(command, .result)
		}
		If $SYSTEM.Status.IsError(sc) {
			Set answer = ..ServerError(sc)
		} Else {
			Set answer = ..Answer(result)
		}
	} Catch exception {
		Set answer = ..ServerError(exception.AsStatus())
	}
	Do ##class(OcuTalon.Core.SecretHandoff).Discard(uri)
	Quit answer
}

/// The names of the fields of the body that are wrong, as a dynamic array: user (a string), role (a string) and grant (a boolean) must each be present with its type, and
/// any other member is named too. An empty or over-long user name is a string: Install.Step.Roles Refusal answers user_unknown for it.
ClassMethod ShapeFields(body As %DynamicObject) As %DynamicArray [ Private ]
{
	Set bad = []
	Set user = body.%GetTypeOf("user")
	If user '= "string" Do bad.%Push("user")
	If body.%GetTypeOf("role") '= "string" Do bad.%Push("role")
	If body.%GetTypeOf("grant") '= "boolean" Do bad.%Push("grant")
	Set iterator = body.%GetIterator()
	While iterator.%GetNext(.name) {
		If (name '= "user") && (name '= "role") && (name '= "grant") Do bad.%Push($Extract(name, 1, 32))
	}
	Quit bad
}

/// Offers the text to SecretHandoff and returns its uri. A test subclass overrides it.
ClassMethod Offer(text As %String, Output uri As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.SecretHandoff).Put(text, .uri)
}

/// Submits the command with origin web_admin and returns its CommandResult in result. A test subclass overrides it.
ClassMethod Submit(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
}

/// The answer from a save's CommandResult: see the class description.
ClassMethod Answer(result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	Set outcome = result.Outcome
	If result.Ok && (outcome = "done") {
		Try {
			Set changed = ##class(%DynamicAbstractObject).%FromJSON(result.Data).changed
		} Catch exception {
			Return ..ServerError(exception.AsStatus())
		}
		Set answer = {"result": "done"}
		Do answer.%Set("changed", changed, "boolean")
		Set %response.ContentType = ..#CONTENTTYPE
		Write answer.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	If outcome = "refused" {
		Try {
			Set data = ##class(%DynamicAbstractObject).%FromJSON(result.Data)
			Set fields = data.fields
			Set reason = data.reason
		} Catch {
			Set fields = []
			Set reason = ""
		}
		Set extra = {"fields": ($Select($IsObject($Get(fields)): fields, 1: [])), "reason": ($Get(reason))}
		Quit ..Fail(400, "bad_settings", ..ReasonMessage($Get(reason)), , extra)
	}
	If outcome = "not_available" Quit ..Fail(409, "not_available", ..#MESSAGEROLESOFF)
	If outcome = "not_built" Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
	Quit ..ServerError($SYSTEM.Status.Error(5001, "The roles change was answered "_outcome))
}

/// The text of a refusal reason, or the plain not-saved message for a reason that this class does not know.
ClassMethod ReasonMessage(reason As %String) As %String [ Private ]
{
	Quit $Case(reason, "role": ..#MESSAGEREASONROLE, "user_unknown": ..#MESSAGEREASONUNKNOWN, "user_managed": ..#MESSAGEREASONMANAGED, "user_system": ..#MESSAGEREASONSYSTEM, : ..#MESSAGEBADSETTINGS)
}

}
