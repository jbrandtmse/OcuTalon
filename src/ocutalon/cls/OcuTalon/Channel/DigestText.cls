/// The text of a digest for a channel (Story 17.10; AD-32). It is the shared rendering code of the *Out operations (OcuTalon.Channel.Telegram.Out,
/// OcuTalon.Channel.WebChat.Out, OcuTalon.Channel.SimPhone.Out and, from Story 21.7, OcuTalon.Channel.Email.Out), and only they call it: producers never render. Text(slots, channel) is the
/// rendering through OcuTalon.Msg.Catalog.Render, for the channel, of every {key, slots} of the Slots' parts and lines, and nothing else is added:
///   - the pieces go in this order: the parts up to the first one whose key is one of AFTERLINES, then one coverage line for each element of lines, then
///     the rest of the parts; when no part has such a key, the lines go last;
///   - each piece is on a line of its own, joined with a line feed, with no Markdown, no title and no empty line;
///   - a piece that cannot be rendered, and Slots that are not an object with an array of parts and an array of lines, are an error status and the text "".
Class OcuTalon.Channel.DigestText [ Abstract ]
{

/// The catalog keys of the parts of a digest that follow the coverage lines: the needs-you parts, the saved-for-later parts and the cost.
Parameter AFTERLINES = "digest.needsYou,digest.needsYouOne,digest.needsYouMore,digest.saved,digest.savedNone,digest.savedNoSummary,digest.cost";

/// The text of a digest (see the class comment): the rendering of every part and line for the channel, one on each line. The coverage lines go before the first part
/// whose key is one of AFTERLINES, or at the end when there is none. The status is an error, and the text "", when the Slots cannot be read or a
/// piece cannot be rendered.
ClassMethod Text(slots As %String, channel As %String, Output sc As %Status) As %String
{
	Set sc = $$$OK
	Set text = ""
	Try {
		Set slots = ##class(%DynamicAbstractObject).%FromJSON(slots)
		If '$IsObject(slots) || (slots.%GetTypeOf("parts") '= "array") || (slots.%GetTypeOf("lines") '= "array") {
			$$$ThrowStatus($SYSTEM.Status.Error(5001, "the digest's Slots have no parts or no lines"))
		}
		Set done = 0
		Set iterator = slots.parts.%GetIterator()
		While iterator.%GetNext(, .part) {
			If 'done && $ListFind($ListFromString(..#AFTERLINES), part.key) {
				Set text = text_..Pieces(slots.lines, text, channel)
				Set done = 1
			}
			Set text = text_$Select(text = "": "", 1: $Char(10))_..Piece(part, channel)
		}
		If 'done Set text = text_..Pieces(slots.lines, text, channel)
	} Catch exception {
		Set sc = exception.AsStatus()
		Set text = ""
	}
	Quit text
}

/// The renderings of the {key, slots} elements of an array, each on a line of its own, with a line break before the first when the text before it is not empty.
ClassMethod Pieces(elements As %DynamicArray, before As %String, channel As %String) As %String [ Private ]
{
	Set text = ""
	Set iterator = elements.%GetIterator()
	While iterator.%GetNext(, .element) {
		Set text = text_$Select((text = "") && (before = ""): "", 1: $Char(10))_..Piece(element, channel)
	}
	Quit text
}

/// The catalog text of one {key, slots} element for the channel; a render error is thrown.
ClassMethod Piece(element As %DynamicObject, channel As %String) As %String [ Private ]
{
	Set text = ##class(OcuTalon.Msg.Catalog).Render(element.key, element.slots, channel, .sc)
	If $SYSTEM.Status.IsError(sc) $$$ThrowStatus(sc)
	Quit text
}

}
