/// The persona of the personality epics (AD-7, CON-2): the fixed presets of how OcuTalon words its chat replies and the
/// reasons of its triage decisions. The presets are product constants held as data in the XData block PRESETS, never
/// instructions: a preset's text reaches the agents only inside the quoted persona block, and it changes nothing about what
/// OcuTalon may do. Each entry has an id, the name and description that the Persona card shows, the text that goes into the
/// block ("" when the block has no fixed text: Professional has no block, Another language has a line that code writes, and
/// Your own words is the person's text) and bends, whether the style may bend the writing rules (a greeting, an
/// exclamation mark, an emoji). The ids are the values of OcuTalon.Msg.Enum PERSONAPRESET, in this order.
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

/// The persona block of the person's session as text. This story fixes the name only: it returns "" and reads and writes
/// nothing.
ClassMethod Block(sessionRef As %String) As %String
{
	Quit ""
}

}
