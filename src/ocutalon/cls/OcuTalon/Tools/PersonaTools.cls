/// The method behind OcuTalon.Tools.Persona (AD-1, AD-4, AD-6, AD-7, AD-9, AD-10, AD-32): the propose_persona tool of the Chat agent. The tool
/// submits Epic 40's ProposePersona command through OcuTalon.Tools.CommandCall and returns the owner's answer, so it never reads or writes a
/// persona itself: SettingsOps owns the persona and every check of a value (an unknown preset, a language name that is not a name, text that
/// is too long, custom text on the online demo).
/// The session comes from the bridge context of the call, never from an argument. A call that is not a session's turn answers NOSESSION and
/// submits nothing. On the online demo the answer is not_available with the owner's own message, and nothing is submitted.
/// The presets are professional, starship, pirate, kindfriend, language and custom. The language argument is used only for the preset language and
/// the custom argument only for the preset custom. The answer proposed means that a request now waits for the person and nothing has changed.
/// The tool declares, by one naming rule (the tool's name in upper case with _ and - removed), its step label (STEPLABEL<NAME>, AD-9) and its
/// classification for the gate (CLASSIFICATION<NAME>: safe; READONLY<NAME> and TRUSTEDOUTPUT<NAME>: 1 or 0, AD-10). It is safe and trusted
/// output, because its answer is built in code from the owner's CommandResult, and not read-only, because it asks for a change: the gate denies
/// it in an untrusted or tainted turn, so only a turn that began with the person's own message can propose a persona.
/// It extends OcuTalon.Tools.Result and returns only through Return. A tool method runs inside AI Hub's callback, so it makes no AI Hub call and
/// no Python call (AD-6). The description of a tool is its method's doc comment, and an argument's DESCRIPTION is what the model reads about it:
/// they are text for the model, never shown to the user as written.
Class OcuTalon.Tools.PersonaTools Extends OcuTalon.Tools.Result
{

Parameter STEPLABELPROPOSEPERSONA = "Suggesting a persona";

Parameter CLASSIFICATIONPROPOSEPERSONA = "safe";

Parameter READONLYPROPOSEPERSONA = 0;

Parameter TRUSTEDOUTPUTPROPOSEPERSONA = 1;

/// Suggests a new persona, which is how you talk, to the user in this conversation. Use it when the user asks to change how you talk, or agrees to a change you offered. The preset is one of professional, starship, pirate, kindfriend, language or custom. Give language only with the preset language, and custom only with the preset custom. Nothing changes when you call this tool: it asks the user, who answers the request in their approval requests. When the answer says proposed, tell the user in one short sentence that a request now waits for them and that nothing has changed yet. When it is not ok, the message says why, in plain English, so tell the user.
ClassMethod ProposePersona(preset As %String(DESCRIPTION = "The persona to suggest: one of professional, starship, pirate, kindfriend, language or custom."), language As %String(DESCRIPTION = "Only for the preset language: the name of the language, such as Spanish. Leave it out for any other preset.") = "", custom As %String(DESCRIPTION = "Only for the preset custom: the user's own words for how you should talk. Leave it out for any other preset.") = "") As %DynamicObject
{
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Session()
	If $IsObject(refusal) Quit ..Return(refusal)
	If ##class(OcuTalon.Watch.Reader).OnlineDemo() {
		Quit ..Return({"ok": false, "outcome": "not_available", "message": (##class(OcuTalon.Core.CommandsIn).#MESSAGENOTALLOWED)})
	}
	Set command = ##class(OcuTalon.Msg.Command.ProposePersona).%New()
	Set command.Preset = preset
	Set command.Language = language
	Set command.Custom = custom
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Run(command, .result)
	If $IsObject(refusal) Quit ..Return(refusal)
	Set answer = ##class(OcuTalon.Tools.CommandCall).Answer(result)
	Set answer.outcome = $Select(result.Ok: "proposed", 1: result.Outcome)
	Quit ..Return(answer)
}

}
