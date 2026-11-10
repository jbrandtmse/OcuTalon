/// Whether a person asked for a memory (AD-6, AD-21; Lane A): the phrase check that OcuTalon.Memory.Ops runs on the person's own text of the turn that
/// saved it. Of(text) gives TOLD when the text holds one of the PHRASES as whole words (the words of a phrase may be separated by any white space), case-folded, with the typographic apostrophe (U+2019) read as an
/// apostrophe, and LEARNED otherwise. It is pure code: it reads nothing and calls neither AI Hub nor Python. It is a class of its own, next to
/// OcuTalon.Tools.Names, because a public method of a tool class would become a tool.
Class OcuTalon.Tools.MemorySource
{

/// The source of a memory that the person asked for.
Parameter TOLD = "told";

/// The source of a memory that the Chat agent saved without being asked.
Parameter LEARNED = "learned";

/// The phrases that make a save told, comma-separated, lower case.
Parameter PHRASES = "remember,keep in mind,note that,don't forget";

/// TOLD when the text holds a phrase of PHRASES as whole words (at the start or the end of the text, or between characters that are not a-z or 0-9),
/// else LEARNED.
ClassMethod Of(text As %String) As %String
{
	Set text = $Replace($ZConvert($Get(text), "L"), $Char(8217), "'")
	Set told = 0
	For index = 1:1:$Length(..#PHRASES, ",") {
		Set told = $Locate(text, "(?<![a-z0-9])"_$Replace($Piece(..#PHRASES, ",", index), " ", "\s+")_"(?![a-z0-9])") > 0
		Quit:told
	}
	Quit $Select(told: ..#TOLD, 1: ..#LEARNED)
}

}
