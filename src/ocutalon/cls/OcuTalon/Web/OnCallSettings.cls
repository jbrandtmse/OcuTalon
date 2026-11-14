/// The on-call route of Settings (Story 36.4; AD-1, AD-4, AD-13, AD-19), forwarded from OcuTalon.Web.Api's URL map (<Map Prefix="/v1/settings/on-call">). Admin only:
/// Api's OnPreDispatch refuses a signed-in user without OcuTalonAdmin with 403 not_admin before the forward, and the route checks it again.
///   - POST /v1/settings/on-call takes the section's body, a JSON object of primaryPerson, primaryUser, primaryEmail, primaryChannels, backupPerson, backupUser,
///     backupEmail, backupChannels and escalationMinutes, and answers as every settings save does (Api's Answer): 200 {"result":"done","sections"} with the
///     sections read fresh, or 400 bad_settings with the names of the refused fields, or 500 server_error. A body that is not a JSON object is 400 bad_settings with
///     no field. SettingsOps validates every value and decides what is saved.
///   - On the online demo it answers 409 not_available with SettingsOps' MESSAGEONCALLOFF before the body is read: nothing is offered, submitted or written.
/// The body holds contact data that Visual Trace would show to any account with the trace role, so the command never holds it: the route offers the body to
/// OcuTalon.Core.SecretHandoff (Put) before the submit, the SaveSettings command's Changes is exactly {"handoff": uri}, and the handoff is discarded on every
/// path after the offer, an error included. No answer, log line or message holds an on-call value. The command is submitted with origin web_admin.
Class OcuTalon.Web.OnCallSettings Extends OcuTalon.Web.Api
{

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="" Method="POST" Call="Save"/>
</Routes>
}

/// 1 when the online-demo flag is set.
ClassMethod OnlineDemo() As %Boolean [ Private ]
{
	Quit (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
}

/// "" when the route may run, else the refusal that has been written: 403 not_admin for a user without OcuTalonAdmin, 409 not_available on the online demo.
ClassMethod Refusal() As %Status [ Private ]
{
	If '..IsAdmin() Quit ..Fail(403, "not_admin", ..#MESSAGENOTADMIN)
	If ..OnlineDemo() Quit ..Fail(409, "not_available", ##class(OcuTalon.Core.SettingsOps).#MESSAGEONCALLOFF)
	Quit ""
}

/// POST /v1/settings/on-call: see the class description.
ClassMethod Save() As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	If '..SettingsBody(.body) Quit ..BadSettings([])
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = "on-call"
	Set command.ActingUser = $USERNAME
	Set command.SessionRef = sessionRef
	Quit ..Hand(command, body)
}

/// Offers the body to its handoff (Offer), sets the uri as the command's only change, submits the command and answers from its result. The handoff is discarded on every
/// path, an error thrown included, so that no event resource outlives the request.
ClassMethod Hand(command As OcuTalon.Msg.Command.SaveSettings, body As %DynamicObject) As %Status [ Private ]
{
	Set uri = "", answer = ""
	Try {
		Set sc = ..Offer(body.%ToJSON(), .uri)
		If $SYSTEM.Status.IsOK(sc) {
			Set command.Changes = {"handoff": (uri)}.%ToJSON()
			Set sc = ..Submit(command, .result)
		}
		If $SYSTEM.Status.IsError(sc) {
			Set answer = ..ServerError(sc)
		} ElseIf $IsObject(result) && (result.Outcome = "not_available") {
			Set answer = ..Fail(409, "not_available", ##class(OcuTalon.Core.SettingsOps).#MESSAGEONCALLOFF)
		} Else {
			Set answer = ..Answer(result, "")
		}
	} Catch exception {
		Set answer = ..ServerError(exception.AsStatus())
	}
	Do ##class(OcuTalon.Core.SecretHandoff).Discard(uri)
	Quit answer
}

/// Offers the text to SecretHandoff (Put) and returns its uri. A test subclass overrides it.
ClassMethod Offer(text As %String, Output uri As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.SecretHandoff).Put(text, .uri)
}

/// Submits the command with origin web_admin and returns its CommandResult in result. A test subclass overrides it.
ClassMethod Submit(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
}

}
