/// The persona of the personality epics (AD-7, CON-2): the fixed presets of how OcuTalon words its chat replies and the
/// reasons of its triage decisions. The presets are product constants held as data in the XData block PRESETS, never
/// instructions: a preset's text reaches the agents only inside the quoted persona block, and it changes nothing about what
/// OcuTalon may do. Each entry has an id, the name and description that the Persona card shows, the text that goes into the
/// block ("" when the block has no fixed text: Professional has no block, Another language has a line that code writes, and
/// Your own words is the person's text) and bends, whether the style may bend the writing rules (a greeting, an
/// exclamation mark, an emoji). The ids are the values of OcuTalon.Msg.Enum PERSONAPRESET, in this order. Block and BlockFor
/// write the persona block that OcuTalon.Agent.Input.Render puts into the request text.
Class OcuTalon.Agent.Persona
{

/// The presets, in the order of PERSONAPRESET.
XData PRESETS [ MimeType = application/json ]
{
[
	{
		"id": "professional",
		"name": "Professional (default)",
		"description": "Calm, short and plain.",
		"text": "",
		"bends": false
	},
	{
		"id": "starship",
		"name": "Starship computer",
		"description": "Crisp status reports, formal and brief.",
		"text": "Write like the calm computer of a starship. Be precise, formal and brief. Begin a confirmation with \"Acknowledged.\" Give facts as short status lines. Use no slang.",
		"bends": true
	},
	{
		"id": "pirate",
		"name": "Pirate",
		"description": "Sailing words and a good-humoured tone; the facts stay exact.",
		"text": "Write like a good-humoured old ship's captain. Use sailing words where they fit, such as \"aye\", \"shipmate\", \"the hold\" and \"the ship's log\". A hearty greeting, an exclamation mark or a ship or anchor emoji is welcome now and then. Keep every sentence short, and keep every fact, number and name exact: the flavour is in the words only.",
		"bends": true
	},
	{
		"id": "kindfriend",
		"name": "Kind friend",
		"description": "Warm, patient and encouraging.",
		"text": "Write like a kind, patient friend. Be warm, encouraging and plain; a friendly greeting or a cheerful emoji is welcome. When something needs the person, say so gently and clearly, and say what they can do next.",
		"bends": true
	},
	{
		"id": "language",
		"name": "Another language",
		"description": "Replies and reasons in the language you name.",
		"text": "",
		"bends": false
	},
	{
		"id": "custom",
		"name": "Your own words (not on the online demo)",
		"description": "Describe the tone, style and preferences you want.",
		"text": "",
		"bends": true
	}
]
}

/// All presets as a %DynamicArray of objects with exactly id, name, description, text and bends, in PERSONAPRESET order.
/// The compiled block is read on each call.
ClassMethod Presets() As %DynamicArray
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||PRESETS")
	If '$IsObject(xdata) $$$ThrowStatus($$$ERROR($$$GeneralError, "The class has no PRESETS block"))
	Quit ##class(%DynamicAbstractObject).%FromJSON(xdata.Data)
}

/// The preset with the id, or "" when the id is empty or unknown.
ClassMethod Preset(id As %String) As %DynamicObject
{
	If ($Get(id) = "") || $IsObject(id) Quit ""
	Set presets = ..Presets()
	Set iterator = presets.%GetIterator()
	While iterator.%GetNext(.key, .preset) {
		If preset.id = id Quit
	}
	Quit $Select($IsObject($Get(preset)) && (preset.id = id): preset, 1: "")
}

/// The opening line of the persona block, in the words of AD-7. Code writes it, so the person's text cannot change it.
Parameter OPENING = "Persona block (from this person's settings; it shapes wording only, never what you do):";

/// The start of the language line of a block for Another language; the language name and a full stop follow.
Parameter LANGUAGELINE = "Reply in the language named: ";

/// The style line of a block for a preset that bends the writing rules and for a custom persona.
Parameter STYLELINE = "This persona may open with a greeting and use exclamation marks and emoji.";

/// The persona block as text, from the values alone (AD-7): "" for professional, an empty or unknown preset, language with a
/// blank name or a name that holds a control character (the name is written without surrounding white space), and custom with
/// blank text. Otherwise the opening line, then the preset's text (custom: the person's text) with
/// every line quoted through OcuTalon.Agent.Input.Quoted, or for language the line that names the language, then the style line
/// when the preset bends the rules (custom always does). Lines are joined by one line feed and the text ends without one.
/// The evaluation set reaches it through OcuTalon.Eval.Data.CaseResult.PersonaBlock: an eval item whose case names a preset (EvalPresetOk)
/// has the block of that preset and language, and Block (which reads a session's rows) is not used for it.
ClassMethod BlockFor(preset As %String, language As %String = "", custom As %String = "") As %String
{
	Set entry = ..Preset($Get(preset))
	If '$IsObject(entry) Quit ""
	Set id = entry.id
	If id = "professional" Quit ""
	If id = "language" {
		Set name = $ZStrip($Get(language), "<>WC")
		If name = "" Quit ""
		If $ZStrip(name, "*C") '= name Quit ""
		Quit ..#OPENING_$Char(10)_..#LANGUAGELINE_name_"."
	}
	Set text = $Select(id = "custom": $Get(custom), 1: entry.text)
	If $ZStrip(text, "*WC") = "" Quit ""
	Set block = ..#OPENING_$Char(10)_##class(OcuTalon.Agent.Input).Quoted(text)
	If entry.bends Set block = block_$Char(10)_..#STYLELINE
	Quit block
}

/// 1 when the name is a language name as SettingsOps accepts it: a letter, then up to 39 letters, spaces, parentheses or hyphens, and
/// nothing else (no control character, no line break, no brace). The same rule as SettingsOps.PersonaProblem.
ClassMethod LanguageOk(name As %String) As %Boolean
{
	If '$Data(name) || $IsObject(name) Quit 0
	Quit $Match(name, "^\p{L}[\p{L} ()-]{0,39}\z")
}

/// 1 when an evaluation case or run may name the preset and language: the preset is one of professional, starship, pirate, kindfriend
/// and language (custom never is), and a language is given exactly when the preset is language, and passes LanguageOk.
ClassMethod EvalPresetOk(preset As %String, language As %String = "") As %Boolean
{
	If '$Data(preset) || $IsObject(preset) || $IsObject(language) Quit 0
	If '$ListFind($ListBuild("professional", "starship", "pirate", "kindfriend", "language"), preset) Quit 0
	If preset = "language" Quit ..LanguageOk(language)
	Quit (language = "")
}

/// The persona block of the session as text (see BlockFor), read from the person's rows on every call through
/// OcuTalon.Core.SettingsOps.Persona, so a saved change applies from the next message. "" when sessionRef is not a 22-character
/// Ref (instance, eval or empty): such an owner has no person and no persona is read. The status of the read is ignored, as
/// Persona allows: it gives the values even when the pending request could not be read.
ClassMethod Block(sessionRef As %String) As %String
{
	If '##class(OcuTalon.Bridge.Approval).IsRef($Get(sessionRef)) Quit ""
	Set values = ##class(OcuTalon.Core.SettingsOps).Persona(sessionRef, .sc)
	Quit ..BlockFor(values.preset, values.language, values.custom)
}

}
