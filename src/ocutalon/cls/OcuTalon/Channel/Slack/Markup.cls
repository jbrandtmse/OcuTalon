/// Markup, the decoder of the text of a Slack message (Story 27.2; AD-14, AD-24, R8). Slack sends a message's text with its own markup: the characters
/// &, < and > as the entities &amp;, &lt; and &gt;, and a mention, a channel, a special mention or a link as a token between < and >. Plain gives the text that the
/// person typed, as plain text, with no member, channel or subteam id in it:
///   - <@U...|label> and <@W...|label> are @label, and <@U...> and <@W...> are @someone (a label that is itself an id counts as none);
///   - <#C...|name> is #name, and <#C...> is #channel;
///   - <!here>, <!channel> and <!everyone> are @here, @channel and @everyone; <!subteam^...|@handle> is @handle; any other <!...|fallback> is its fallback and any
///     other <!...> is empty;
///   - <url|label> is "label (url)", and just the url when the label is the url; <url> is the url; a mail link that has no label (or the address as its label) is the
///     address without "mailto:";
///   - a < that no > closes, and a token of no known form, stay as written;
///   - then &lt; is <, &gt; is > and &amp; is &, the last one last, so that a typed "&lt;" (sent as &amp;lt;) stays "&lt;".
/// It writes nothing and logs nothing; the text is untrusted and is returned as text only.
Class OcuTalon.Channel.Slack.Markup [ Abstract ]
{

/// What a mention without a usable label reads as.
Parameter SOMEONE = "@someone";

/// What a channel reference without a usable name reads as.
Parameter CHANNEL = "#channel";

/// The special mentions that are written as @ and their name.
Parameter SPECIAL = "here,channel,everyone";

/// A member or channel id: upper-case letters and digits, as Slack writes them.
Parameter IDPATTERN = "^[A-Z0-9]{2,32}$";

/// A link's scheme, as the start of a token that is a link.
Parameter URLPATTERN = "^[A-Za-z][A-Za-z0-9+.-]*:.+";

/// The plain text of a Slack message text (see the class comment).
ClassMethod Plain(text As %String) As %String
{
	Set rest = $Get(text)
	Set plain = ""
	While rest '= "" {
		Set close = $Find(rest, ">")
		If 'close {
			Set plain = plain_rest
			Quit
		}
		// The token is the text between the last < before the first > and that >; a > with no < before it is plain text.
		Set open = 0
		Set from = 1
		For {
			Set at = $Find(rest, "<", from)
			If 'at || (at > (close - 1)) Quit
			Set open = at
			Set from = at
		}
		If open {
			Set plain = plain_$Extract(rest, 1, open - 2)_..Token($Extract(rest, open, close - 2))
		} Else {
			Set plain = plain_$Extract(rest, 1, close - 1)
		}
		Set rest = $Extract(rest, close, *)
	}
	Set plain = $Replace(plain, "&lt;", "<")
	Set plain = $Replace(plain, "&gt;", ">")
	Quit $Replace(plain, "&amp;", "&")
}

/// The plain text of one token (the text between < and >), or the token as written with its brackets when it has no known form. The entities are still encoded.
ClassMethod Token(inner As %String) As %String [ Private ]
{
	Set head = $Piece(inner, "|", 1)
	Set label = $Piece(inner, "|", 2, *)
	Set kind = $Extract(head)
	If kind = "@" {
		Quit $Select(..UsableLabel(label): "@"_label, 1: ..#SOMEONE)
	}
	If kind = "#" {
		Quit $Select(..UsableLabel(label): "#"_label, 1: ..#CHANNEL)
	}
	If kind = "!" {
		Set special = $Extract(head, 2, *)
		If $ListFind($ListFromString(..#SPECIAL), special) Quit "@"_special
		Quit label
	}
	If $Match(head, ..#URLPATTERN) {
		Set address = $Select($ZConvert($Extract(head, 1, 7), "L") = "mailto:": $Extract(head, 8, *), 1: "")
		If (label = "") || (label = head) Quit $Select(address '= "": address, 1: head)
		If (address '= "") && (label = address) Quit address
		Quit label_" ("_head_")"
	}
	Quit "<"_inner_">"
}

/// 1 when the label of a mention or channel is a name to show: not empty and not itself an id.
ClassMethod UsableLabel(label As %String) As %Boolean [ Private ]
{
	Quit (label '= "") && '$Match(label, ..#IDPATTERN)
}

}
