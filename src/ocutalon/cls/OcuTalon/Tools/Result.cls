/// The shared base of OcuTalon's built-in tools (AD-10, NFR-3; Consistency Conventions: Tool results). A tool class extends it and
/// returns only through Return, so that the results of one model step together pass at most STEPTOKENS tokens, which also bounds any
/// single result. The gate runs before a tool and never sees its result, so the cut happens here.
///   - A result that fits the room that is left in the step comes back whole and keeps its type: a dynamic object stays an object, so
///     the model reads it as JSON, and a string stays a string. Never return a pre-encoded JSON string: AI Hub encodes a string again.
///   - A result that does not fit comes back as text: the first characters that fit, a line break and the note (CUTNOTE), which says how
///     many characters are shown of how many. A cut JSON text is no longer an object, so it is text.
///   - A result that arrives when too little room is left for both a piece of it and the note comes back as the note alone, with no
///     characters shown. The note is added to the total, so this is the one way a step's results pass the room, by one note each.
///   - A value whose text cannot be built whole, because it is longer than the longest string, is left out the same way, and the note
///     gives unknown as the total.
/// The total of the model step is the ToolResultChars of the bridge context (OcuTalon.Bridge.Context), which the step renderer sets to 0
/// at every model response. With no context, Return measures against a fresh room and keeps nothing.
/// Only the methods that a concrete class defines are tools, so Return and the other methods of this class are not tools of a class that
/// extends it. A tool method runs inside AI Hub's callback, so this class makes no AI Hub call and no Python call (AD-6): the Class line is
/// the only line that names the AI Hub package.
Class OcuTalon.Tools.Result Extends %AI.Tool [ Abstract ]
{

/// The room of one model step, in tokens (AD-10). The room in characters is STEPTOKENS times the characters per token of the
/// bridge's estimates (StepBuffer CHARSPERTOKEN): 40,000.
Parameter STEPTOKENS = 10000;

/// The note that follows a cut result and stands for a result that is left out: {shown} is the number of characters of the result that
/// are shown, and {total} the number of its characters or unknown. Text for the model, never for the user, in ASCII.
Parameter CUTNOTE = "[cut by OcuTalon: {shown} of {total} characters shown]";

/// Returns the result of a tool: a dynamic object or a string. See the class description for the three outcomes.
///   - Whole: the total of the step plus the length of the text of the value (its JSON, or the string itself) is within the room. The
///     value is returned unchanged and its length is added to the total.
///   - Cut: otherwise, when room is left for at least one character of the text, a string of the largest piece of the text that fits
///     together with a line break and the note, so the piece, the line break and the note are at most what is left. The total becomes
///     the room.
///   - Left out: otherwise the note alone, with 0 characters shown. Its length is added to the total.
ClassMethod Return(value As %Any) As %Any
{
	Set room = ..Room()
	Set active = ##class(OcuTalon.Bridge.Context).Active()
	Set total = 0
	If active Set total = +##class(OcuTalon.Bridge.Context).Current().ToolResultChars
	Set built = 1
	Try {
		Set text = $Select($IsObject(value): value.%ToJSON(), 1: value)
	} Catch {
		Set built = 0
		Set text = ""
	}
	If built {
		Set length = $Length(text)
		If total + length '> room {
			If active Do ##class(OcuTalon.Bridge.Context).Put("ToolResultChars", total + length)
			Quit value
		}
		Set shown = ..ShownChars(room - total, length)
		If shown > 0 {
			If active Do ##class(OcuTalon.Bridge.Context).Put("ToolResultChars", room)
			Quit $Extract(text, 1, shown) _ $Char(10) _ ..Note(shown, length)
		}
		Set note = ..Note(0, length)
	} Else {
		Set note = ..Note(0, "unknown")
	}
	If active Do ##class(OcuTalon.Bridge.Context).Put("ToolResultChars", total + $Length(note))
	Quit note
}

/// The room of one model step in characters: STEPTOKENS times the characters per token of the bridge's estimates.
ClassMethod Room() As %Integer
{
	Quit ..#STEPTOKENS * ##class(OcuTalon.Bridge.Adapter.StepBuffer).#CHARSPERTOKEN
}

/// The note for a result of which shown characters are shown out of total (a number, or unknown).
ClassMethod Note(shown As %Integer, total As %String) As %String
{
	Quit $Replace($Replace(..#CUTNOTE, "{shown}", shown), "{total}", total)
}

/// The largest number of characters k of a text of length characters, at least 1, such that k characters, a line break and the note for
/// k of length fit in what is left of the room (left), or 0 when there is none.
ClassMethod ShownChars(left As %Integer, length As %Integer) As %Integer
{
	Set shown = left - 1 - $Length(..Note(0, length))
	If shown > length Set shown = length
	While (shown > 0) && (shown + 1 + $Length(..Note(shown, length)) > left) {
		Set shown = shown - 1
	}
	Quit $Select(shown > 0: shown, 1: 0)
}

}
