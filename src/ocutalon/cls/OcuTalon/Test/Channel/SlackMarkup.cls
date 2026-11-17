/// Tests of Markup (Story 27.2; Contest Planner ruling 3: the decode table is pinned): the plain text of a Slack message text. They need nothing else.
///   - TestEntities: &lt; &gt; &amp; are < > &, & last, so that a typed entity stays as typed, and a text with no markup is unchanged;
///   - TestMentions: <@U..> and <@W..> are @someone, with a label @label, and a label that is an id counts as none;
///   - TestChannels: <#C..> is #channel, with a name #name;
///   - TestSpecial: <!here>, <!channel> and <!everyone>, a subteam with its handle, a date with its fallback, and any other <!...> with none;
///   - TestLinks: <url> is the url, <url|label> is "label (url)", the url alone when the label is the url, and a mail link has no mailto:;
///   - TestStray: a < with no > and a > with no < stay as written, and the token is the last < before the first >;
///   - TestNoIdLeft: a text of every form holds no U, W or C id after it, and the row of the contract (a & b <3 mention link) is exactly its plain text.
Class OcuTalon.Test.Channel.SlackMarkup Extends %UnitTest.TestCase
{

/// The plain text of the Slack text.
ClassMethod Plain(text As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Channel.Slack.Markup).Plain(text)
}

Method TestEntities()
{
	Do $$$AssertEquals(..Plain("a &amp; b"), "a & b", "&amp; is &")
	Do $$$AssertEquals(..Plain("1 &lt; 2 &gt; 0"), "1 < 2 > 0", "&lt; and &gt; are < and >")
	Do $$$AssertEquals(..Plain("&amp;lt;"), "&lt;", "&amp; is decoded last: a typed &lt; stays &lt;")
	Do $$$AssertEquals(..Plain("&amp;amp;"), "&amp;", "and a typed &amp; stays &amp;")
	Do $$$AssertEquals(..Plain("&amp;gt; &amp;"), "&gt; &", "&amp;gt; is &gt;")
	Do $$$AssertEquals(..Plain("no markup at all, just text: 100% & more"), "no markup at all, just text: 100% & more", "a text with no markup but a bare & is unchanged")
	Do $$$AssertEquals(..Plain(""), "", "an empty text is empty")
	Do $$$AssertEquals(..Plain("&lt;@U0X&gt;"), "<@U0X>", "an escaped mention is typed text: it is decoded, not read as a mention")
}

Method TestMentions()
{
	Do $$$AssertEquals(..Plain("hi <@U0ABC123> there"), "hi @someone there", "a member is @someone")
	Do $$$AssertEquals(..Plain("hi <@W0ABC123>"), "hi @someone", "an enterprise member (W) too")
	Do $$$AssertEquals(..Plain("<@U0ABC123|jo> hi"), "@jo hi", "with a label it is @label")
	Do $$$AssertEquals(..Plain("<@U0ABC123|U0ABC123>"), "@someone", "a label that is the id is none")
	Do $$$AssertEquals(..Plain("<@U0ABC123|jo &amp; co>"), "@jo & co", "a label's entities are decoded")
}

Method TestChannels()
{
	Do $$$AssertEquals(..Plain("see <#C0ABC123>"), "see #channel", "a channel is #channel")
	Do $$$AssertEquals(..Plain("see <#C0ABC123|general>"), "see #general", "with a name it is #name")
	Do $$$AssertEquals(..Plain("<#C0ABC123|C0ABC123>"), "#channel", "a name that is the id is none")
}

Method TestSpecial()
{
	Do $$$AssertEquals(..Plain("<!here> <!channel> <!everyone>"), "@here @channel @everyone", "the three special mentions")
	Do $$$AssertEquals(..Plain("<!here|here>"), "@here", "with their label too")
	Do $$$AssertEquals(..Plain("ping <!subteam^S0ABC123|@oncall>"), "ping @oncall", "a subteam is its handle")
	Do $$$AssertEquals(..Plain("ping <!subteam^S0ABC123>"), "ping ", "a subteam with no handle is nothing")
	Do $$$AssertEquals(..Plain("at <!date^1392734382^{date_num} {time}|Feb 18 2014>"), "at Feb 18 2014", "another special is its fallback")
	Do $$$AssertEquals(..Plain("x<!unknown>y"), "xy", "and with no fallback nothing")
}

Method TestLinks()
{
	Do $$$AssertEquals(..Plain("<https://e.x/a>"), "https://e.x/a", "a link is its url")
	Do $$$AssertEquals(..Plain("<https://e.x|e.x>"), "e.x (https://e.x)", "a link with a label is label (url)")
	Do $$$AssertEquals(..Plain("<https://e.x|https://e.x>"), "https://e.x", "a label that is the url gives the url alone")
	Do $$$AssertEquals(..Plain("<https://e.x/?a=1&amp;b=2>"), "https://e.x/?a=1&b=2", "the entities of a url are decoded")
	Do $$$AssertEquals(..Plain("<mailto:bob@e.x>"), "bob@e.x", "a mail link has no mailto:")
	Do $$$AssertEquals(..Plain("<mailto:bob@e.x|bob@e.x>"), "bob@e.x", "also with the address as its label")
	Do $$$AssertEquals(..Plain("<mailto:bob@e.x|Bob>"), "Bob (mailto:bob@e.x)", "a mail link with another label is label (url)")
}

Method TestStray()
{
	Do $$$AssertEquals(..Plain("a < b"), "a < b", "a < that no > closes stays")
	Do $$$AssertEquals(..Plain("a > b"), "a > b", "a > with no < before it stays")
	Do $$$AssertEquals(..Plain("a > b <@U0ABC123>"), "a > b @someone", "and the token after it is still read")
	Do $$$AssertEquals(..Plain("<3 <@U0ABC123>"), "<3 @someone", "the token is the last < before the first >: no id survives an unescaped <")
	Do $$$AssertEquals(..Plain("<not a token>"), "<not a token>", "a token of no known form stays as written")
	Do $$$AssertEquals(..Plain("<>"), "<>", "an empty token stays")
}

Method TestNoIdLeft()
{
	Set text = "a &amp; b &lt;3 <@U0ABC123> <https://e.x|e.x>"
	Do $$$AssertEquals(..Plain(text), "a & b <3 @someone e.x (https://e.x)", "the row of the contract")
	Set all = "<@U0ABC123> <@W0ABC123|W0ABC123> <#C0ABC123> <#C0ABC123|C0ABC123> <!subteam^S0ABC123> <!date^1^x> <@U0ABC123|jo>"
	Set plain = ..Plain(all)
	Do $$$AssertTrue('$Match(plain, ".*[UWCS]0ABC123.*"), "no member, channel or subteam id is left: "_plain)
	Do $$$AssertEquals(plain, "@someone @someone #channel #channel   @jo", "and what is left is the plain text")
}

}
