/// The partner-contacts route of Settings (Story 24.2; AD-1, AD-4, AD-13, AD-19), forwarded from OcuTalon.Web.Api's URL map (<Map Prefix="/v1/settings/partner-contacts">). It is
/// OcuTalon.Web.OnCallSettings with its own slug and off-on-demo text, so it checks, hands off, submits and answers exactly as that route does. Admin only: Api's OnPreDispatch
/// refuses a signed-in user without OcuTalonAdmin with 403 not_admin before the forward, and the route checks it again.
///   - POST /v1/settings/partner-contacts takes one contact's change, a JSON object: {action, ref, name, email, productions} for action save (ref "" for a new contact; productions is
///     [{namespace, production}]) or {action, ref} for action remove. It answers as every settings save does (Api's Answer): 200 {"result":"done","sections"} with the sections read
///     fresh, or 400 bad_settings with the names of the refused fields (name, email, productions) or none for a body of the wrong shape, or 500 server_error. SettingsOps validates every
///     value and decides what is saved.
///   - On the online demo it answers 409 not_available with SettingsOps' MESSAGEPARTNERSOFF before the body is read: nothing is offered, submitted or written.
/// The route does not read the TABLE switch of OcuTalon.Fix.PartnerContacts: only the page's section is shown by it.
/// The body holds a contact's name and address, which Visual Trace would show to any account with the trace role, so the command never holds it: the body goes to OcuTalon.Core.SecretHandoff
/// before the submit, the SaveSettings command's Changes is exactly {"handoff": uri}, and the handoff is discarded on every path. No refusal, log line or message holds a name or an address; a 200's sections hold the stored contacts only while the section is shown.
Class OcuTalon.Web.PartnerSettings Extends OcuTalon.Web.OnCallSettings
{

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="" Method="POST" Call="Save"/>
</Routes>
}

/// The slug of the partner-contacts section.
ClassMethod Slug() As %String
{
	Quit "partner-contacts"
}

/// The accepted text of the 409 not_available that the online demo gets: settings.partnersOffOnDemo.
ClassMethod OffText() As %String
{
	Quit ##class(OcuTalon.Core.SettingsOps).#MESSAGEPARTNERSOFF
}

}
