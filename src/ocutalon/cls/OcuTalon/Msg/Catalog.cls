/// The one renderer of the message catalog (AD-32). Producers never render text: they set a catalog key and JSON slots, and
/// every text made from the catalog is rendered here.
/// The texts live in the XData block Entries of OcuTalon.Msg.Catalog.Core (Lane B) and OcuTalon.Msg.Catalog.Watch (Lane A),
/// one JSON object whose names are the keys <prefix>.<name>. An entry is
///   {"text": the text, "web": the page wording when it differs, "slots": {"<name>": "<type>"}, "source": ..., "gap": ...}
/// and its text holds {name} placeholders for exactly its declared slots. The slot types:
///   time           UTC YYYY-MM-DDThh:mm:ssZ, shown through Data.Time.ForMessage, with " ET" on the online demo;
///   count          a JSON integer of 0 or more, as digits;
///   noun           {"one": ..., "other": ...}, the form for the entry's count slot: one when it is 1, else other;
///   text           a string written by code;
///   sentence       a plain sentence written by the model, with no time;
///   channel        web, phone or telegram, as "the web chat", "the simulated phone" or "Telegram";
///   fallbackReason a Msg.Enum FALLBACKREASON value, as the text of its fallbackReason.* key;
///   groups         a non-empty array of {itemName, count, errorSummary, firstAt}, one line per group;
///   cost           US dollars of 0 or more, as the UX's Formats rule says.
/// A string slot is trimmed, loses its control characters (the bidirectional controls, the zero-width space and the other
/// invisible format characters that Clean lists among them; the zero-width joiner and non-joiner stay), and has each whitespace
/// run, line breaks and Unicode spaces included, collapsed to one space. Where the text continues with a period, one trailing
/// period of the value goes, and a value left empty by that is an error; a value that ends with "?", "!" or U+2026 there keeps
/// its mark and the text's period goes. The text is filled in one pass, so a slot's value
/// is never read as a placeholder or a line, and nothing is escaped: the output is plain text for Telegram and for Angular's
/// text binding. A slot that the entry does not declare is ignored.
/// The channels are web, phone, mailbox and telegram; the others of Msg.Enum CHANNEL are refused until their step adds them.
/// The web channel uses the entry's web text where it has one. When a dated time follows "at " in a text, that "at" becomes "on".
/// Render and RenderAt return the whole text, or "" with an error status in plain English that names the key and the slot or
/// channel; there is never a partial text. They are pure: they write no global, no log line and no row.
Class OcuTalon.Msg.Catalog
{

/// The catalog classes, each holding the XData block Entries.
Parameter CLASSES = "OcuTalon.Msg.Catalog.Core,OcuTalon.Msg.Catalog.Watch";

/// The channels that Render serves.
Parameter CHANNELS = "web,phone,mailbox,telegram";

/// How a channel slot reads in message text (Voice and Tone, Formats).
Parameter CHANNELNAMES = "web=the web chat,phone=the simulated phone,telegram=Telegram";

/// Each Msg.Enum FALLBACKREASON value with the suffix of its fallbackReason.* catalog key.
Parameter REASONKEYS = "no_key=noKey,daily_cap=dailyCap,budget=budget,too_large=tooLarge,timeout=timeout,rate_limited=rateLimited,error=error,refusal=refusal,cut_off=cutOff,empty=empty,invalid=generic,unusable=generic";

/// One line of a groups slot.
Parameter GROUPLINE = "{itemName}: {count}, '{errorSummary}', first at {firstAt}";

/// The text of a catalog key for a channel, filled from slots (JSON text or a %DynamicObject, "" for none), with the current
/// time and the online-demo flag. Returns "" with an error in sc when the text cannot be made.
ClassMethod Render(key As %String, slots As %String, channel As %String, Output sc As %Status) As %String
{
	Set sc = $$$OK
	Try {
		Set text = ..RenderAt($Get(key), $Get(slots), $Get(channel), ##class(OcuTalon.Data.Time).NowUtc(), ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo"), .sc)
	} Catch exception {
		Set sc = exception.AsStatus()
		Set text = ""
	}
	Quit text
}

/// Render with the clock (UTC, "" for the current time) and the online-demo flag given, so that a test fixes both.
ClassMethod RenderAt(key As %String, slots As %String, channel As %String, now As %String, onlineDemo As %Boolean, Output sc As %Status) As %String
{
	Set sc = $$$OK
	Try {
		Set text = ..Build(key, slots, channel, now, $Select(+$Get(onlineDemo): 1, 1: 0))
	} Catch exception {
		Set sc = exception.AsStatus()
		Set text = ""
	}
	Quit text
}

/// The entry of a catalog key, as a dynamic object with the field "class" added (the catalog class that holds it). The
/// XData blocks are read on every call and never cached, so a recompiled class is seen at once. Returns "" with an error in
/// sc for an unknown key.
ClassMethod Entry(key As %String, Output sc As %Status) As %DynamicObject
{
	Set sc = $$$OK
	Try {
		Set entry = ..Find(key)
	} Catch exception {
		Set sc = exception.AsStatus()
		Set entry = ""
	}
	Quit entry
}

ClassMethod Build(key As %String, slots, channel As %String, now As %String, onlineDemo As %Boolean) As %String [ Private ]
{
	Set context = "Catalog key '"_key_"'"
	If '$ListFind($ListFromString(..#CHANNELS), channel) {
		Do ..Fail(context_": the channel '"_channel_"' is not rendered; the channels are "_$Replace(..#CHANNELS, ",", ", "))
	}
	If now = "" Set now = ##class(OcuTalon.Data.Time).NowUtc()
	If ##class(OcuTalon.Data.Time).ToLocal(now) = "" Do ..Fail(context_": the clock '"_now_"' is not a UTC time like 2026-10-16T18:20:00Z")
	Set entry = ..Find(key)
	Set values = ..ParseSlots(context, slots)
	Set field = $Select((channel = "web") && entry.%IsDefined("web"): "web", 1: "text")
	If (entry.%GetTypeOf(field) '= "string") || (entry.%Get(field) = "") Do ..Fail(context_": the entry has no '"_field_"' text")
	If entry.%GetTypeOf("slots") '= "object" Do ..Fail(context_": the entry declares no slots object")
	Quit ..Fill(context, entry.%Get(field), entry.slots, values, now, onlineDemo)
}

/// The text with each {name} replaced by the formatted slot, in one pass over the text.
ClassMethod Fill(context As %String, template As %String, types As %DynamicObject, values As %DynamicObject, now As %String, onlineDemo As %Boolean) As %String [ Private ]
{
	Set out = ""
	Set position = 1
	Set length = $Length(template)
	While position <= length {
		Set open = $Find(template, "{", position)
		If open = 0 {
			Set out = out_$Extract(template, position, length)
			Quit
		}
		Set close = $Find(template, "}", open)
		If close = 0 Do ..Fail(context_": the text has a '{' without a '}'")
		Set out = out_$Extract(template, position, open - 2)
		Set name = $Extract(template, open, close - 2)
		Set piece = ..SlotText(context, name, types, values, now, onlineDemo, $Extract(template, close), .dated, .ended)
		Set size = $Length(out)
		If dated && ($Extract(out, size - 2, size) = "at ") && ((size = 3) || ($Extract(out, size - 3) = " ")) {
			Set out = $Extract(out, 1, size - 3)_"on "
		}
		Set out = out_piece
		Set position = close + ended
	}
	Quit out
}

/// The text of one slot by its declared type; dated is 1 for a time that carries a weekday or a date, and ended is 1 when the
/// following period of the text is to be skipped, because the value already ends its sentence with "?", "!" or U+2026.
ClassMethod SlotText(context As %String, name As %String, types As %DynamicObject, values As %DynamicObject, now As %String, onlineDemo As %Boolean, following As %String, Output dated As %Boolean, Output ended As %Boolean) As %String [ Private ]
{
	Set dated = 0
	Set ended = 0
	If 'types.%IsDefined(name) Do ..Fail(context_": the text uses {"_name_"}, which the entry does not declare as a slot")
	Set type = types.%Get(name)
	If type = "time" {
		Set utc = ..Value(context, name, values, "string")
		If utc '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" Do ..Fail(context_": the slot '"_name_"' is not a UTC time like 2026-10-16T18:12:00Z")
		Set formatted = ##class(OcuTalon.Data.Time).ForMessage(utc, now)
		If formatted = "" Do ..Fail(context_": the slot '"_name_"' is not a valid time")
		Set dated = (formatted '? 2N1":"2N)
		Quit formatted_$Select(onlineDemo: " ET", 1: "")
	}
	If type = "count" Quit ..Count(context, name, values)
	If (type = "text") || (type = "sentence") {
		Set value = ..Clean(..Value(context, name, values, "string"))
		If value = "" Do ..Fail(context_": the slot '"_name_"' is empty")
		Set last = $Extract(value, $Length(value))
		If (following = ".") && (last = ".") {
			Set value = $Extract(value, 1, $Length(value) - 1)
			If value = "" Do ..Fail(context_": the slot '"_name_"' is empty")
		}
		If (following = ".") && ((last = "?") || (last = "!") || (last = $Char(8230))) Set ended = 1
		Quit value
	}
	If type = "noun" Quit ..Noun(context, name, types, values)
	If type = "channel" {
		Set value = ..Value(context, name, values, "string")
		Set display = ..Lookup(..#CHANNELNAMES, value)
		If display = "" Do ..Fail(context_": the slot '"_name_"' is '"_value_"', which is not a channel with a name (web, phone or telegram)")
		Quit display
	}
	If type = "fallbackReason" {
		Set value = ..Value(context, name, values, "string")
		Set suffix = ..Lookup(..#REASONKEYS, value)
		If suffix = "" Do ..Fail(context_": the slot '"_name_"' is '"_value_"', which is not a fallback reason")
		Quit ..Find("fallbackReason."_suffix).text
	}
	If type = "cost" Quit ..Cost(context, name, values)
	If type = "groups" Quit ..Groups(context, name, values, now, onlineDemo)
	Do ..Fail(context_": the slot '"_name_"' has the unknown type '"_type_"'")
}

/// The form of a noun slot for the entry's count slot, with both forms checked.
ClassMethod Noun(context As %String, name As %String, types As %DynamicObject, values As %DynamicObject) As %String [ Private ]
{
	If 'types.%IsDefined("count") || (types.%Get("count") '= "count") Do ..Fail(context_": the slot '"_name_"' is a noun, so the entry needs a count slot")
	Set count = ..Count(context, "count", values)
	Set forms = ..Value(context, name, values, "object")
	Set where = context_", slot '"_name_"'"
	For form = "one", "other" {
		Set noun(form) = ..Clean(..Value(where, form, forms, "string"))
		If noun(form) = "" Do ..Fail(where_": the form '"_form_"' is empty")
	}
	Quit noun($Select(count = 1: "one", 1: "other"))
}

/// One line per group, from GROUPLINE, in the order of the array.
ClassMethod Groups(context As %String, name As %String, values As %DynamicObject, now As %String, onlineDemo As %Boolean) As %String [ Private ]
{
	Set groups = ..Value(context, name, values, "array")
	If groups.%Size() = 0 Do ..Fail(context_": the slot '"_name_"' has no groups")
	Set types = {"itemName": "text", "count": "count", "errorSummary": "text", "firstAt": "time"}
	Set lines = ""
	Set iterator = groups.%GetIterator()
	While iterator.%GetNext(.index, .group) {
		Set where = context_", group "_(index + 1)_" of '"_name_"'"
		If groups.%GetTypeOf(index) '= "object" Do ..Fail(where_" is not an object")
		Set lines = lines_$Select(index = 0: "", 1: $Char(10))_..Fill(where, ..#GROUPLINE, types, group, now, onlineDemo)
	}
	Quit lines
}

/// US dollars by the UX's Formats rule: "<$0.0001" under $0.0001, four decimals under $0.01, three under $1, else two. The
/// tier is the one of the amount as shown, so 0.99996 is "$1.00" and 0.009996 is "$0.010".
ClassMethod Cost(context As %String, name As %String, values As %DynamicObject) As %String [ Private ]
{
	Set value = ..Value(context, name, values, "number")
	If value < 0 Do ..Fail(context_": the slot '"_name_"' is a negative amount")
	If value < 0.0001 Quit "<$0.0001"
	Set places = $Select(value < 0.01: 4, value < 1: 3, 1: 2)
	If (places = 4) && ($FNumber(value, "", 4) >= 0.01) Set places = 3
	If (places = 3) && ($FNumber(value, "", 3) >= 1) Set places = 2
	Quit "$"_$FNumber(value, "", places)
}

/// The slot as a whole number of 0 or more.
ClassMethod Count(context As %String, name As %String, values As %DynamicObject) As %Integer [ Private ]
{
	Set value = ..Value(context, name, values, "number")
	If (value < 0) || (value '= (value \ 1)) Do ..Fail(context_": the slot '"_name_"' is not a whole number of 0 or more")
	Quit value
}

/// The value of a slot whose JSON type is wanted (string, number, object or array).
ClassMethod Value(context As %String, name As %String, values As %DynamicObject, wanted As %String) As %String [ Private ]
{
	If 'values.%IsDefined(name) Do ..Fail(context_": the slot '"_name_"' is missing")
	Set actual = values.%GetTypeOf(name)
	If actual '= wanted Do ..Fail(context_": the slot '"_name_"' must be "_$Select(wanted = "string": "a string", wanted = "number": "a number", wanted = "array": "an array", 1: "an object")_", not "_actual)
	Quit values.%Get(name)
}

/// A string slot: whitespace, line breaks and Unicode spaces become one space; the other control characters, the bidirectional
/// controls (U+061C, U+200E, U+200F, U+202A to U+202E, U+2066 to U+2069), the zero-width space, the Mongolian vowel separator,
/// the word joiner, the invisible operators U+2061 to U+2064, the interlinear annotation marks and the byte order mark go; the
/// zero-width joiner and non-joiner stay; and the ends are trimmed.
ClassMethod Clean(value As %String) As %String [ Private ]
{
	Set value = $Translate(value, $Char(9, 10, 11, 12, 13, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288), $Justify("", 24))
	Set value = $Translate(value, $Char(1564, 6158, 8203, 8206, 8207, 8234, 8235, 8236, 8237, 8238, 8288, 8289, 8290, 8291, 8292, 8294, 8295, 8296, 8297, 65279, 65529, 65530, 65531))
	Set value = $ZStrip(value, "*C")
	Quit $ZStrip($ZStrip(value, "<>W"), "=W")
}

/// The value of a name in a map written "name=value,name=value"; "" when the name is not in it.
ClassMethod Lookup(map As %String, name As %String) As %String [ Private ]
{
	Set found = ""
	If name '= "" {
		For i = 1:1:$Length(map, ",") {
			Set pair = $Piece(map, ",", i)
			If $Piece(pair, "=", 1) = name Set found = $Piece(pair, "=", 2, *) Quit
		}
	}
	Quit found
}

/// The slots as a dynamic object: an object as it is, JSON text parsed, "" as {}.
ClassMethod ParseSlots(context As %String, slots) As %DynamicObject [ Private ]
{
	If $IsObject(slots) {
		If 'slots.%IsA("%Library.DynamicObject") Do ..Fail(context_": the slots must be a JSON object")
		Quit slots
	}
	Set json = $ZStrip(slots, "<>W")
	If json = "" Quit {}
	Try {
		Set values = ##class(%DynamicAbstractObject).%FromJSON(json)
	} Catch {
		Do ..Fail(context_": the slots are not valid JSON")
	}
	If '$IsObject(values) || 'values.%IsA("%Library.DynamicObject") Do ..Fail(context_": the slots must be a JSON object")
	Quit values
}

/// The entry of a key from the first catalog class that holds it; throws when there is none.
ClassMethod Find(key As %String) As %DynamicObject [ Private ]
{
	If $IsObject(key) || (key = "") Do ..Fail("The catalog key is empty or is not a string")
	Set entry = ""
	Set classes = $ListFromString(..#CLASSES)
	Set position = 0
	While $ListNext(classes, position, class) {
		Set entries = ..ReadEntries(class)
		If entries.%IsDefined(key) {
			Set entry = entries.%Get(key)
			Do entry.%Set("class", class)
			Quit
		}
	}
	If '$IsObject(entry) Do ..Fail("There is no catalog key '"_key_"' in "_$Replace(..#CLASSES, ",", " or "))
	Quit entry
}

/// The XData block Entries of a catalog class as a dynamic object; throws when the class has no such block or it is not JSON.
ClassMethod ReadEntries(class As %String) As %DynamicObject [ Private ]
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(class_"||Entries")
	If '$IsObject(xdata) Do ..Fail("The catalog class "_class_" has no Entries block")
	Try {
		Set entries = ##class(%DynamicAbstractObject).%FromJSON(xdata.Data)
	} Catch {
		Do ..Fail("The Entries block of "_class_" is not valid JSON")
	}
	Quit entries
}

/// Throws an error status with the message.
ClassMethod Fail(message As %String) [ Private ]
{
	$$$ThrowStatus($$$ERROR($$$GeneralError, message))
}

}
