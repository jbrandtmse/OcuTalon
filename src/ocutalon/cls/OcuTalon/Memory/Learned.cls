/// The announcement of a learned save (Story 41.15; AD-21, AD-28; Lane A): the code that says, under a reply, that OcuTalon saved a fact it learned
/// from the person's own words. It is pure code: it reads nothing and calls neither AI Hub nor Python. A turn's learned saves are the entries
/// {memoryRef, text} of the Turn's Learned (a JSON array, at most MAXENTRIES), which MemoryTools puts in the HostData member learned; the guarded
/// reply text never holds the line, and the guard never sees it. Every renderer of the line (the chat.message payload for the page, TelegramOut and the
/// eval report) shows exactly what Shown and Lines give, so that they cannot disagree.
///   - Fact(text) is the stored text as the line shows it: one trailing full stop (.) removed, then, when more than FACTMAX characters are left, the
///     first FACTMAX - 1 characters and an ellipsis (U+2026), FACTMAX in all (one fewer when the cut would split a UTF-16 surrogate pair, which stays whole).
///   - Said(replyText) is 1 when the reply already says "I'll remember" or "I will remember", with the reply guard's own matching (ReplyGuard.PatternOf:
///     case ignored, any white space, ' or U+2019, whole words). Such a reply gets no line, so that a learned save is never announced twice.
///   - Shown(learned, replyText) is the entries to show, as [{memoryRef, fact}, ...] in order: none when the reply says it (Said), when learned is not a
///     JSON array, and for an entry that is not an object with a non-empty string memoryRef and a non-empty string text (or whose fact is empty once
///     shaped); at most MAXENTRIES.
///   - Lines(learned, replyText, channel) is one rendering of the catalog key KEY (slot fact) for the channel per entry that Shown gives, as plain
///     text: the line is the text of the catalog, and the fact is the person's own words, so no renderer may treat it as markup. An entry that fails to
///     render is left out, and sc holds the first error.
Class OcuTalon.Memory.Learned
{

/// The catalog key of the line.
Parameter KEY = "memory.learnedSaved";

/// The most entries a turn announces.
Parameter MAXENTRIES = 3;

/// The most characters a fact holds in the line, the ellipsis included.
Parameter FACTMAX = 200;

/// The phrases that make a reply say that it remembers, comma-separated (ReplyGuard.PatternOf's matching).
Parameter SAID = "I'll remember,I will remember";

/// The stored text as the line shows it (see the class description).
ClassMethod Fact(text As %String) As %String
{
	Set text = $Get(text)
	If $Extract(text, $Length(text)) = "." Set text = $Extract(text, 1, $Length(text) - 1)
	If $Length(text) > ..#FACTMAX {
		Set size = ..#FACTMAX - 1
		If ($Ascii(text, size) >= 55296) && ($Ascii(text, size) <= 56319) Set size = size - 1
		Set text = $Extract(text, 1, size)_$Char(8230)
	}
	Quit text
}

/// 1 when the reply text already says "I'll remember" or "I will remember", else 0.
ClassMethod Said(replyText As %String) As %Boolean
{
	Quit $Locate($Get(replyText), ##class(OcuTalon.Checks.ReplyGuard).PatternOf(..#SAID)) > 0
}

/// The entries of learned (a JSON array of {memoryRef, text}) that the line shows, as [{memoryRef, fact}, ...]. See the class description.
ClassMethod Shown(learned As %String, replyText As %String) As %DynamicArray
{
	Set shown = []
	Set learned = $Get(learned)
	If (learned = "") || ..Said($Get(replyText)) Quit shown
	Try {
		Set array = ##class(%DynamicAbstractObject).%FromJSON(learned)
		If $ClassName(array) '= "%Library.DynamicArray" Quit
		For i = 0:1:array.%Size() - 1 {
			If shown.%Size() '< ..#MAXENTRIES Quit
			If array.%GetTypeOf(i) '= "object" Continue
			Set element = array.%Get(i)
			If (element.%GetTypeOf("memoryRef") '= "string") || (element.%GetTypeOf("text") '= "string") Continue
			Set fact = ..Fact(element.text)
			If (element.memoryRef = "") || (fact = "") Continue
			Do shown.%Push({"memoryRef": (element.memoryRef), "fact": (fact)})
		}
	} Catch exception {
		Set shown = []
	}
	Quit shown
}

/// The lines to show under the reply for the channel: one catalog rendering of KEY per entry of Shown. See the class description.
ClassMethod Lines(learned As %String, replyText As %String, channel As %String, Output sc As %Status) As %DynamicArray
{
	Set sc = $$$OK
	Set lines = []
	Set shown = ..Shown($Get(learned), $Get(replyText))
	Set iterator = shown.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set line = ##class(OcuTalon.Msg.Catalog).Render(..#KEY, {"fact": (entry.fact)}, channel, .lineSc)
		If $$$ISERR(lineSc) {
			If $$$ISOK(sc) Set sc = lineSc
			Continue
		}
		Do lines.%Push(line)
	}
	Quit lines
}

}
