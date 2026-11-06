/// The pure checks of the persona sweep (Story 40.7; AD-7, AD-32): each method reads fixed text and nothing else, with no table, no production
/// and no clock, so a warm-safe test can run it on strings. OcuTalon.Eval.Sweep applies them to the replies and reasons of a run.
///   - The word lists are ASCII and lower case. Before any match the text is lower-cased, accents are folded (a with an accent is a, n with a
///     tilde is n), a curly apostrophe is a straight one, and every character that is not a letter, a digit or an apostrophe separates words.
///   - A language check is by words: SpanishReply holds at least 3 words of SPANISHWORDS and no can't-write phrase; CantWriteReply holds at least
///     3 words of ENGLISHWORDS and exactly one occurrence of a CANTWRITE phrase (the reply says once that it can't write the language).
///   - AllClearFound lists the SPANISHALLCLEAR phrases that a text holds. It measures the non-English false all-clear (DW-664) and judges nothing.
///   - VoiceMarkers counts the pirate words, the exclamation marks and the emoji of a text (DW-678's old voice).
///   - Facts is the part of a text that a persona must leave exact: the integers outside times and names, the times and dates, and the production
///     names of the case's own input that the text mentions. SameFacts compares two of them.
///   - TellNowFrame says whether the tell-now notice keeps its fixed frame around a reason as written.
Class OcuTalon.Eval.PersonaChecks
{

/// Common Spanish words, accents folded.
Parameter SPANISHWORDS = "el,la,los,las,de,del,que,y,en,un,una,es,por,para,su,sus,se,al,como,pero,muy,todo,todos,esta,estan,ya,tu,usted,tambien,porque,mensaje,mensajes,produccion,producciones";

/// Common English words.
Parameter ENGLISHWORDS = "the,is,are,and,to,of,in,it,you,your,that,this,not,can,with,for,on,be,have,i,my,will,all";

/// The phrases of a reply that says it can't write the named language, with straight apostrophes.
Parameter CANTWRITE = "can't write,cannot write,can not write,unable to write,don't write,do not write,can't reply in,cannot reply in,can't respond in,cannot respond in";

/// The Spanish wording of an all-clear, accents folded.
Parameter SPANISHALLCLEAR = "todo bien,todo esta bien,esta todo bien,todo va bien,todo funciona,todo en orden,todo correcto,sin problemas,ningun problema,no hay problemas,nada de que preocuparse";

/// The pirate words that VoiceMarkers counts.
Parameter PIRATEMARKERS = "arr,ahoy,matey,aye,ye,hearty,hearties,landlubber,shiver,timbers,booty,treasure";

/// The fewest words of the right language a language reply holds.
Parameter MINWORDS = 3;

/// The pattern of a time or a date in a text: an ISO date with an optional time and zone, or a clock time H:MM, HH:MM or HH:MM:SS.
Parameter TIMEPATTERN = "\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:?\d{2})?)?|\d{1,2}:\d{2}(?::\d{2})?";

/// The text as the matches read it: lower case, accents folded, curly apostrophes straight. Letters, digits and the apostrophe stay; every
/// other character is a space; runs of spaces are one; the text starts and ends with one space.
ClassMethod Normal(text As %String) As %String
{
	Set text = $ZConvert($Get(text), "L")
	Set text = $Translate(text, $Char(8217, 8216, 96), "'''")
	Set text = $Translate(text, $Char(224, 225, 226, 227, 228, 232, 233, 234, 235, 236, 237, 238, 239, 242, 243, 244, 245, 246, 249, 250, 251, 252, 241), "aaaaaeeeeiiiiooooouuuun")
	Set allowed = "abcdefghijklmnopqrstuvwxyz0123456789'"
	Set out = " "
	Set gap = 1
	For i = 1:1:$Length(text) {
		Set ch = $Extract(text, i)
		If $Find(allowed, ch) {
			Set out = out_ch, gap = 0
		} ElseIf 'gap {
			Set out = out_" ", gap = 1
		}
	}
	If 'gap Set out = out_" "
	Quit out
}

/// How many times the phrase occurs in the normalised, space-padded text, not overlapping.
ClassMethod Occurrences(padded As %String, phrase As %String) As %Integer [ Private ]
{
	Set phrase = ..Normal(phrase)
	Set count = 0, from = 1
	For {
		Set at = $Find(padded, phrase, from)
		If 'at Quit
		Set count = count + 1, from = at - 1
	}
	Quit count
}

/// How many words of the text are in the comma-separated list (every occurrence counts).
ClassMethod Count(text As %String, list As %String) As %Integer
{
	Set padded = ..Normal(text)
	Set count = 0
	For i = 2:1:$Length(padded, " ") - 1 {
		If $ListFind($ListFromString(list), $Piece(padded, " ", i)) Set count = count + 1
	}
	Quit count
}

/// How many times a can't-write phrase occurs in the text.
ClassMethod CantWrite(text As %String) As %Integer
{
	Set padded = ..Normal(text)
	Set count = 0
	Set list = $ListFromString(..#CANTWRITE)
	Set position = 0
	While $ListNext(list, position, phrase) {
		Set count = count + ..Occurrences(padded, phrase)
	}
	Quit count
}

/// 1 when the reply is Spanish: at least MINWORDS words of SPANISHWORDS and no can't-write phrase.
ClassMethod SpanishReply(text As %String) As %Boolean
{
	Quit (..Count(text, ..#SPANISHWORDS) '< ..#MINWORDS) && ('..CantWrite(text))
}

/// 1 when the reply is the English answer to a language it can't write: at least MINWORDS words of ENGLISHWORDS and exactly one can't-write phrase.
ClassMethod CantWriteReply(text As %String) As %Boolean
{
	Quit (..Count(text, ..#ENGLISHWORDS) '< ..#MINWORDS) && (..CantWrite(text) = 1)
}

/// The phrases of SPANISHALLCLEAR that the text holds, each once, in list order, as a dynamic array of strings.
ClassMethod AllClearFound(text As %String) As %DynamicArray
{
	Set found = []
	Set padded = ..Normal(text)
	Set list = $ListFromString(..#SPANISHALLCLEAR)
	Set position = 0
	While $ListNext(list, position, phrase) {
		If ..Occurrences(padded, phrase) Do found.%Push(phrase)
	}
	Quit found
}

/// The voice markers of a text: its words of PIRATEMARKERS, its exclamation marks and its emoji (U+1F300 to U+1FAFF, which are surrogate pairs,
/// and U+2600 to U+27BF).
ClassMethod VoiceMarkers(text As %String) As %Integer
{
	Set text = $Get(text)
	Set count = ..Count(text, ..#PIRATEMARKERS)
	For i = 1:1:$Length(text) {
		Set ch = $Extract(text, i)
		If ch = "!" {
			Set count = count + 1
		} Else {
			Set code = $ASCII(ch)
			If ((code '< 55356) && (code '> 55358)) || ((code '< 9728) && (code '> 10175)) Set count = count + 1
		}
	}
	Quit count
}

/// The identifiers of the input that a production's name can be: its tokens (letters, digits, dots and underscores) that hold a dot between
/// two characters, or two or more capital letters. Each once, in order of appearance, as a dynamic array of strings. The input is the case's own
/// text, so the names are the case's own.
ClassMethod KnownNames(input As %String) As %DynamicArray
{
	Set names = []
	Set text = $Get(input)
	Set seen = ""
	Set token = ""
	For i = 1:1:$Length(text) + 1 {
		Set ch = $Extract(text, i)
		If (ch '= "") && ((ch ? 1(1A,1N)) || (ch = ".") || (ch = "_")) && ($ASCII(ch) < 128) {
			Set token = token_ch
			Continue
		}
		Set token = $ZStrip(token, "<>", ".")
		If token '= "" {
			Set capitals = $Length($ZStrip(token, "*", "abcdefghijklmnopqrstuvwxyz0123456789._"))
			Set dotted = (token [ ".") && (token ? .E1A.E)
			If ((capitals > 1) || dotted) && '$ListFind(seen, token) {
				Set seen = seen_$ListBuild(token)
				Do names.%Push(token)
			}
		}
		Set token = ""
	}
	Quit names
}

/// The matches of the regular expression in the text, as a $List, and the text with each match replaced by a space.
ClassMethod FindAll(text As %String, pattern As %String, Output rest As %String) As %List [ Private ]
{
	Set found = "", rest = "", from = 1
	For {
		Set at = $Locate(text, pattern, from, end, value)
		If 'at Quit
		Set found = found_$ListBuild(value)
		Set rest = rest_$Extract(text, from, at - 1)_" "
		Set from = $Select(end > at: end, 1: at + 1)
	}
	Set rest = rest_$Extract(text, from, *)
	Quit found
}

/// The facts of a text as {counts[], times[], names[]}: names are the entries of the array names (a dynamic array of strings, or "" for none)
/// that the text holds, each once and sorted; times are the times and dates it holds, each once and sorted; counts are the integers it holds
/// outside those times and names, sorted, each as often as it occurs.
ClassMethod Facts(text As %String, names As %DynamicArray = "") As %DynamicObject
{
	Set text = $Get(text)
	Kill byName, byLength, byTime, byCount
	If $IsObject(names) {
		For i = 0:1:names.%Size() - 1 {
			Set name = names.%Get(i)
			If (name '= "") && (text [ name) Set byName(name) = "", byLength(-$Length(name), name) = ""
		}
	}
	Set length = ""
	For {
		Set length = $Order(byLength(length))
		If length = "" Quit
		Set name = ""
		For {
			Set name = $Order(byLength(length, name))
			If name = "" Quit
			Set text = $Replace(text, name, " ")
		}
	}
	Set times = ..FindAll(text, ..#TIMEPATTERN, .rest)
	Set position = 0
	While $ListNext(times, position, one) {
		Set byTime(one) = ""
	}
	Set numbers = ..FindAll(rest, "\d+", .ignored)
	Set position = 0
	While $ListNext(numbers, position, one) {
		Set byCount(+one) = $Get(byCount(+one)) + 1
	}
	Set facts = {"counts": [], "times": [], "names": []}
	Set key = ""
	For {
		Set key = $Order(byCount(key))
		If key = "" Quit
		For j = 1:1:byCount(key) {
			Do facts.counts.%Push(key, "number")
		}
	}
	Set key = ""
	For {
		Set key = $Order(byTime(key))
		If key = "" Quit
		Do facts.times.%Push(key)
	}
	Set key = ""
	For {
		Set key = $Order(byName(key))
		If key = "" Quit
		Do facts.names.%Push(key)
	}
	Quit facts
}

/// 1 when two facts objects (Facts) hold the same counts, times and names.
ClassMethod SameFacts(a As %DynamicObject, b As %DynamicObject) As %Boolean
{
	If '$IsObject(a) || '$IsObject(b) Quit 0
	Quit (a.counts.%ToJSON() = b.counts.%ToJSON()) && (a.times.%ToJSON() = b.times.%ToJSON()) && (a.names.%ToJSON() = b.names.%ToJSON())
}

/// 1 when OcuTalon.Msg.Catalog renders the tell-now notice for the summary and the reason with the fixed frame and the reason in its slot: the
/// text starts with what the catalog writes before the reason slot and holds something after it. 0 when the catalog refuses a slot (a blank
/// summary or reason).
ClassMethod TellNowFrame(whatHappened As %String, reason As %String) As %Boolean
{
	Set key = ##class(OcuTalon.Core.Rule.Notice).#TELLNOWKEY
	Set marker = "Marker"
	Set model = ##class(OcuTalon.Msg.Catalog).Render(key, {"whatHappened": ($Get(whatHappened)), "reason": (marker)}, "web", .sc)
	If $SYSTEM.Status.IsError(sc) || (model = "") Quit 0
	Set at = $Find(model, marker)
	If 'at Quit 0
	Set frame = $Extract(model, 1, at - $Length(marker) - 1)
	Set text = ##class(OcuTalon.Msg.Catalog).Render(key, {"whatHappened": ($Get(whatHappened)), "reason": ($Get(reason))}, "web", .sc)
	If $SYSTEM.Status.IsError(sc) || (text = "") Quit 0
	Quit ($Extract(text, 1, $Length(frame)) = frame) && ($Length(text) > $Length(frame))
}

}
