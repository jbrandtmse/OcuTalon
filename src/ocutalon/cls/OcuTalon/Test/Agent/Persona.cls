/// Tests of the persona presets (Story 40.1, AD-7): the six presets of OcuTalon.Agent.Persona against a test-held copy of the
/// UX table (EXPERIENCE.md, Personality), the rule that no PRESETS block holds a template token, and Block with no stored rows. Nothing
/// is written anywhere and no model is called.
///   - TestPresets: Presets() and Preset(id) give the six entries in PERSONAPRESET order (compared with Msg.Enum once it
///     has PERSONAPRESET) with exactly the five fields and their JSON types, the UX texts, the bends flag per id, and "" for
///     an unknown or empty id;
///   - TestNoTemplates: no compiled PRESETS block of an OcuTalon class holds {{, @{ or a control character other than a line
///     feed; the scanner flags a sample that breaks the rule, and passes one that keeps it;
///   - TestBlock: Block() returns "" for an empty reference and for a session reference with no stored rows.
Class OcuTalon.Test.Agent.Persona Extends %UnitTest.TestCase
{

/// The UX table as this test holds it, one object per preset. It is named UX so that the PRESETS scan does not take it.
XData UX [ MimeType = application/json ]
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

/// Presets() is the six presets in the order of PERSONAPRESET, each with exactly id, name, description, text and bends equal
/// to the UX table; Preset(id) gives the one with the id, and "" for an unknown or empty id.
Method TestPresets()
{
	Set expected = ..Ux()
	Set actual = ##class(OcuTalon.Agent.Persona).Presets()
	Do $$$AssertEquals(actual.%Size(), 6, "there are 6 presets")
	Do $$$AssertEquals(expected.%Size(), 6, "the UX copy has 6 presets")
	Set ids = ""
	Set fields = $ListBuild("id", "name", "description", "text", "bends")
	For i = 0:1:expected.%Size() - 1 {
		Set want = expected.%Get(i)
		Set got = actual.%Get(i)
		If '$IsObject(got) {
			Do $$$AssertTrue(0, "preset "_i_" is an object")
			Continue
		}
		Set ids = ids _ $ListBuild(got.id)
		Set count = 0
		Set iterator = got.%GetIterator()
		While iterator.%GetNext(.key) {
			Set count = count + 1
			Do $$$AssertTrue($ListFind(fields, key) > 0, want.id_" has no field outside the five: "_key)
		}
		Do $$$AssertEquals(count, 5, want.id_" has exactly 5 fields")
		Set position = 0
		While $ListNext(fields, position, field) {
			Do $$$AssertTrue(got.%IsDefined(field), want.id_" has "_field)
			Do $$$AssertEquals(got.%GetTypeOf(field), want.%GetTypeOf(field), want.id_" "_field_" has the UX table's JSON type")
			Do $$$AssertEquals(got.%Get(field), want.%Get(field), want.id_" "_field_" is the UX table's")
		}
		Set one = ##class(OcuTalon.Agent.Persona).Preset(want.id)
		Do $$$AssertTrue($IsObject(one), "Preset("_want.id_") is an object")
		If $IsObject(one) Do $$$AssertEquals(one.%ToJSON(), got.%ToJSON(), "Preset("_want.id_") is the same entry as in Presets()")
	}
	Do $$$AssertEquals($ListToString(ids), "professional,starship,pirate,kindfriend,language,custom", "the ids are in PERSONAPRESET order")
	Set enum = $Parameter("OcuTalon.Msg.Enum", "PERSONAPRESET")
	If enum = "" Do $$$LogMessage("OcuTalon.Msg.Enum has no PERSONAPRESET yet (Story 40.2), so the ids are not compared with it")
	If enum '= "" Do $$$AssertEquals($ListToString(ids), enum, "the ids are Msg.Enum PERSONAPRESET, in its order")

	Set pirate = ##class(OcuTalon.Agent.Persona).Preset("pirate")
	Do $$$AssertEquals(pirate.id, "pirate", "Preset(pirate) is the pirate")
	Do $$$AssertEquals(pirate.bends, 1, "the pirate bends")
	Set bends = $ListBuild("starship", "pirate", "kindfriend", "custom")
	Set keeps = $ListBuild("professional", "language")
	Set position = 0
	While $ListNext(bends, position, id) {
		Do $$$AssertEquals(##class(OcuTalon.Agent.Persona).Preset(id).bends, 1, id_" bends")
	}
	Set position = 0
	While $ListNext(keeps, position, id) {
		Do $$$AssertEquals(##class(OcuTalon.Agent.Persona).Preset(id).bends, 0, id_" keeps the rules")
	}
	Set position = 0
	Set none = $ListBuild("professional", "language", "custom")
	While $ListNext(none, position, id) {
		Do $$$AssertEquals(##class(OcuTalon.Agent.Persona).Preset(id).text, "", id_" has no text in the block")
	}
	Do $$$AssertEquals(##class(OcuTalon.Agent.Persona).Preset("zorblish"), "", "an unknown id gives an empty string")
	Do $$$AssertEquals(##class(OcuTalon.Agent.Persona).Preset(""), "", "an empty id gives an empty string")
}

/// No compiled PRESETS block of an OcuTalon class holds {{, @{ or a control character other than a line feed, in a key or a
/// value. The scanner flags samples that break the rule, and passes one that keeps it.
Method TestNoTemplates()
{
	Do $$$AssertTrue(..HasBadToken("Hello {{name}}"), "the scanner flags a text with a {{ token")
	Do $$$AssertTrue(..HasBadToken("Hello @{name}"), "and a text with an @{ token")
	Do $$$AssertTrue(..HasBadToken("Hello"_$Char(9)_"name"), "and a text with a tab")
	Do $$$AssertTrue(..HasBadToken("Hello"_$Char(13)_"name"), "and a text with a carriage return")
	Do $$$AssertTrue('..HasBadToken("Hello name."_$Char(10)_"Aye, shipmate! { } @ {"), "and passes a clean text with a line feed and lone braces")

	Set blocks = 0
	Set persona = 0
	Set statement = ##class(%SQL.Statement).%New()
	Do $$$AssertStatusOK(statement.%Prepare("SELECT parent FROM %Dictionary.CompiledXData WHERE Name = 'PRESETS' AND parent %STARTSWITH 'OcuTalon.'"), "the PRESETS blocks are listed")
	Set result = statement.%Execute()
	While result.%Next() {
		Set blocks = blocks + 1
		Set class = result.%GetData(1)
		If class = "OcuTalon.Agent.Persona" Set persona = 1
		Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(class_"||PRESETS")
		Set presets = ##class(%DynamicAbstractObject).%FromJSON(xdata.Data)
		Set entries = 0
		Set outer = presets.%GetIterator()
		While outer.%GetNext(.index, .entry) {
			Set entries = entries + 1
			Set inner = entry.%GetIterator()
			While inner.%GetNext(.key, .value) {
				Do $$$AssertTrue('..HasBadToken(key), class_" entry "_index_" key "_key_" has no template token or control character")
				If entry.%GetTypeOf(key) = "string" Do $$$AssertTrue('..HasBadToken(value), class_" entry "_index_" "_key_" has no template token or control character")
			}
		}
		Do $$$AssertTrue(entries > 0, class_" has entries in its PRESETS: "_entries)
	}
	Do $$$AssertTrue(persona, "OcuTalon.Agent.Persona's PRESETS block is among the blocks scanned: "_blocks)
}

/// Block() with no stored rows: "" for an empty reference, and for a 22-character session reference whose person has no row
/// (Professional has no block). The block's text is tested by OcuTalon.Test.Agent.PersonaBlock.
Method TestBlock()
{
	Do $$$AssertEquals(##class(OcuTalon.Agent.Persona).Block(""), "", "Block of an empty session reference is empty")
	Do $$$AssertEquals(##class(OcuTalon.Agent.Persona).Block("AbCdEf0123456789xyzABC"), "", "Block of a session reference is empty")
}

/// --- helpers ---
/// The UX table of this class as a dynamic array.
ClassMethod Ux() As %DynamicArray [ Private ]
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||UX")
	Quit ##class(%DynamicAbstractObject).%FromJSON(xdata.Data)
}

/// 1 when the text holds {{, @{ or a control character other than a line feed.
ClassMethod HasBadToken(text As %String) As %Boolean [ Private ]
{
	Quit (text [ "{{") || (text [ "@{") || ($ZStrip(text, "*C", "", $Char(10)) '= text)
}

}
