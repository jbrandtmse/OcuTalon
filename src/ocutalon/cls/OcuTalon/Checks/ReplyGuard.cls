/// The reply guard (AD-28, AD-31): the bridge's ReplyFilterClass setting names it, and Decide runs Filter once on every model-written text
/// before a result leaves Decide, so only OcuTalon's own sentence (the catalog text of the key that Checks.Render chose) can say that everything
/// passed. Filter deletes two lists of phrases and keeps the rest of the text:
///   - RESERVED: the reserved sentences about the checks and the system's health.
///   - BANNED: the closed list of phrases that the UX bans from a reply.
/// How a phrase matches: case is ignored; a space in the phrase matches any run of white space (a no-break space included); an apostrophe matches
/// ' or U+2019; and the character before the phrase and the character after it are not a letter or a digit, so a phrase inside a longer word is
/// not a match.
/// How the text is filtered: line by line, the lines split on LF (a CR before an LF stays with the line break). Each match is deleted together
/// with the run of . ! ? , ; : that directly follows it. In a line that had a match, a run of spaces and tabs becomes one space and the line is
/// trimmed; a line left empty is dropped with its line break. A line with no match, and a text with no match at all, come back unchanged byte for
/// byte. The guard never adds or rewrites a word. A text that the guard empties is Decide's existing fallback (invalid), and if anything fails
/// inside Filter it returns "" (fail closed), so that Decide falls back instead of passing the text unfiltered.
Class OcuTalon.Checks.ReplyGuard Extends OcuTalon.Bridge.Ext.ReplyFilter
{

/// The reserved sentences, comma-separated: the catalog sentences of checks.allPassed and checks.everythingElsePassed without their final period,
/// and the Epic 17 sentence about the system's health.
Parameter RESERVED = "Everything I checked passed,Everything else I checked passed,Your IRIS system is healthy";

/// The banned phrases, comma-separated (the UX's closed list).
Parameter BANNED = "all good,everything's fine,everything is fine,no issues,no problems,nothing to worry about";

/// The punctuation that is deleted with the phrase it directly follows.
Parameter PUNCTUATION = ".!?,;:";

/// The text with the reserved sentences and the banned phrases removed (see the class description), or "" when the filter fails.
ClassMethod Filter(text As %String) As %String
{
	Set result = ""
	Try {
		Set result = ..Apply($Get(text))
	} Catch exception {
		Set result = ""
	}
	Quit result
}

/// The filtered text.
ClassMethod Apply(text As %String) As %String [ Private ]
{
	Set regex = ..Pattern()
	If '$Locate(text, regex) Quit text
	Set lf = $Char(10), cr = $Char(13)
	Set count = $Length(text, lf)
	Set out = ""
	For i = 1:1:count {
		Set line = $Piece(text, lf, i)
		Set ending = ""
		If i < count {
			If $Extract(line, $Length(line)) = cr {
				Set line = $Extract(line, 1, $Length(line) - 1)
				Set ending = cr_lf
			} Else {
				Set ending = lf
			}
		}
		If '$Locate(line, regex) {
			Set out = out_line_ending
			Continue
		}
		Set line = $ZStrip(..Replace(..Replace(line, regex, ""), "[ \t]+", " "), "<>W")
		If line '= "" Set out = out_line_ending
	}
	Quit out
}

/// The regular expression of every phrase of RESERVED and BANNED: case-insensitive, no letter or digit before or after, and the punctuation after.
ClassMethod Pattern() As %String [ Private ]
{
	Set phrases = ..#RESERVED_","_..#BANNED
	Set alternatives = ""
	For i = 1:1:$Length(phrases, ",") {
		Set phrase = $Piece(phrases, ",", i)
		If phrase = "" Continue
		Set alternatives = alternatives_$Select(alternatives = "": "", 1: "|")_..Escape(phrase)
	}
	Set edge = "[\p{L}\p{N}]"
	Quit "(?i)(?<!"_edge_")(?:"_alternatives_")(?!"_edge_")["_..#PUNCTUATION_"]*"
}

/// A phrase as a regular expression: a space matches a run of white space, an apostrophe matches ' or U+2019, a letter or digit matches itself
/// and any other character is escaped.
ClassMethod Escape(phrase As %String) As %String [ Private ]
{
	Set out = ""
	For i = 1:1:$Length(phrase) {
		Set char = $Extract(phrase, i)
		If char = " " {
			Set out = out_"\s+"
		} ElseIf char = "'" {
			Set out = out_"['\x{2019}]"
		} ElseIf char ? 1AN {
			Set out = out_char
		} Else {
			Set out = out_"\"_char
		}
	}
	Quit out
}

/// The text with every match of the regular expression replaced by with.
ClassMethod Replace(text As %String, regex As %String, with As %String) As %String [ Private ]
{
	Set position = 1
	Set out = ""
	For {
		Set at = $Locate(text, regex, position, after)
		If at = 0 Quit
		Set out = out_$Extract(text, position, at - 1)_with
		Set position = after
	}
	Quit out_$Extract(text, position, $Length(text))
}

}
