/// Tests of OcuTalon.Memory.Learned, the announcement of a learned save (Story 41.15; AD-21, AD-28). Pure code, so a plain test case: nothing is stored, no production and no
/// model are needed, and the catalog is read as it is. The expected lines and lengths are written out here, never read from the code under test.
///   - TestFact: one trailing full stop is removed ("Wait.." keeps one), text of 200 characters after that stays whole, 201 is cut to 199 and an ellipsis (U+2026), 200 in all;
///   - TestSaid: "I'll remember" and "I will remember" in any case, with U+2019, any white space and a no-break space, as whole words; "remembered", "We'll remember" and an empty reply are not;
///   - TestShown: bad JSON, JSON that is not an array and an empty value give [], so does a reply that says it, a malformed entry is dropped, at most three entries come back in order, each as {memoryRef, fact};
///   - TestLines: the exact ruled line for the web and for Telegram, a fact with markup kept as characters, a 300-character fact, nothing for a reply that says it.
Class OcuTalon.Test.Memory.Learned Extends %UnitTest.TestCase
{

/// The line of a fact as the ruling words it.
ClassMethod Line(fact As %String) As %String [ Private ]
{
	Quit "I'll remember this: """_fact_""". You can tell me to forget it."
}

/// The JSON array of n entries {memoryRef: "M<i>", text: "Fact <i>."}.
ClassMethod Entries(n As %Integer) As %String [ Private ]
{
	Set array = []
	For i = 1:1:n Do array.%Push({"memoryRef": ("M"_i), "text": ("Fact "_i_".")})
	Quit array.%ToJSON()
}

Method TestFact()
{
	Set learned = "OcuTalon.Memory.Learned"
	Set ellipsis = $Char(8230)
	Do $$$AssertEquals($ClassMethod(learned, "Fact", "Lee is the contact."), "Lee is the contact", "one trailing full stop is removed")
	Do $$$AssertEquals($ClassMethod(learned, "Fact", "Wait.."), "Wait.", "only one of two stops is removed")
	Do $$$AssertEquals($ClassMethod(learned, "Fact", "Lee is the contact"), "Lee is the contact", "a text with no stop is as it is")
	Do $$$AssertEquals($ClassMethod(learned, "Fact", "a.b"), "a.b", "a stop inside the text stays")
	Do $$$AssertEquals($ClassMethod(learned, "Fact", "Lee. "), "Lee. ", "only a stop that ends the text is removed")
	Do $$$AssertEquals($ClassMethod(learned, "Fact", "."), "", "a lone stop leaves nothing")
	Do $$$AssertEquals($ClassMethod(learned, "Fact", ""), "", "an empty text is empty")
	Set long = $Translate($Justify("", 300), " ", "a")
	Set cut = $ClassMethod(learned, "Fact", long)
	Do $$$AssertEquals($Length(cut), 200, "300 characters are cut to 200 in all")
	Do $$$AssertEquals(cut, $Extract(long, 1, 199)_ellipsis, "the first 199 characters and an ellipsis (U+2026)")
	Set exact = $Extract(long, 1, 200)
	Do $$$AssertEquals($ClassMethod(learned, "Fact", exact), exact, "exactly 200 characters stay whole")
	Do $$$AssertEquals($ClassMethod(learned, "Fact", $Extract(long, 1, 200)_"."), exact, "201 characters ending in a stop are 200 once the stop is gone, and stay whole")
	Do $$$AssertEquals($ClassMethod(learned, "Fact", $Extract(long, 1, 201)), $Extract(long, 1, 199)_ellipsis, "201 characters are cut")
	Do $$$AssertEquals($ClassMethod(learned, "Fact", $Extract(long, 1, 201)_"."), $Extract(long, 1, 199)_ellipsis, "202 ending in a stop: the stop goes first, then the cut")
	Set pair = $Char(55357, 56832)
	Do $$$AssertEquals($ClassMethod(learned, "Fact", $Extract(long, 1, 198)_pair_$Extract(long, 1, 20)), $Extract(long, 1, 198)_ellipsis, "a surrogate pair the cut would split is left out whole")
	Do $$$AssertEquals($ClassMethod(learned, "Fact", $Extract(long, 1, 197)_pair_$Extract(long, 1, 20)), $Extract(long, 1, 197)_pair_ellipsis, "a surrogate pair that ends at the cut stays whole")
}

Method TestSaid()
{
	Set learned = "OcuTalon.Memory.Learned"
	Do $$$AssertEquals($ClassMethod(learned, "Said", "I'll remember that Lee is the contact."), 1, "I'll remember")
	Do $$$AssertEquals($ClassMethod(learned, "Said", "I will remember that."), 1, "I will remember")
	Do $$$AssertEquals($ClassMethod(learned, "Said", "Noted. I"_$Char(8217)_"ll remember Lee."), 1, "with a typographic apostrophe (U+2019)")
	Do $$$AssertEquals($ClassMethod(learned, "Said", "I'LL REMEMBER it"), 1, "in any case")
	Do $$$AssertEquals($ClassMethod(learned, "Said", "i Will Remember it"), 1, "in any case, the other phrase")
	Do $$$AssertEquals($ClassMethod(learned, "Said", "I  will"_$Char(10)_"remember it"), 1, "with any white space between the words")
	Do $$$AssertEquals($ClassMethod(learned, "Said", "I will"_$Char(160)_"remember it"), 1, "with a no-break space")
	Do $$$AssertEquals($ClassMethod(learned, "Said", "Sure. I'll remember."), 1, "at the end of the reply, with a stop")
	Do $$$AssertEquals($ClassMethod(learned, "Said", "I'll remembered that"), 0, "not inside a longer word")
	Do $$$AssertEquals($ClassMethod(learned, "Said", "We'll remember that"), 0, "We'll remember is not I'll remember")
	Do $$$AssertEquals($ClassMethod(learned, "Said", "I'll keep that in mind"), 0, "another way to say it is not matched")
	Do $$$AssertEquals($ClassMethod(learned, "Said", "Noted."), 0, "a reply that does not say it")
	Do $$$AssertEquals($ClassMethod(learned, "Said", ""), 0, "an empty reply")
}

Method TestShown()
{
	Set learned = "OcuTalon.Memory.Learned"
	Do $$$AssertEquals($ClassMethod(learned, "Shown", "", "Noted.").%ToJSON(), "[]", "an empty value shows nothing")
	Do $$$AssertEquals($ClassMethod(learned, "Shown", "not json", "Noted.").%ToJSON(), "[]", "bad JSON shows nothing")
	Do $$$AssertEquals($ClassMethod(learned, "Shown", "{""memoryRef"":""M1"",""text"":""x""}", "Noted.").%ToJSON(), "[]", "JSON that is not an array shows nothing")
	Do $$$AssertEquals($ClassMethod(learned, "Shown", "[]", "Noted.").%ToJSON(), "[]", "an empty array shows nothing")
	Do $$$AssertEquals($ClassMethod(learned, "Shown", ..Entries(2), "I'll remember that.").%ToJSON(), "[]", "a reply that says it shows nothing")
	Do $$$AssertEquals($ClassMethod(learned, "Shown", ..Entries(2), "Noted.").%ToJSON(), "[{""memoryRef"":""M1"",""fact"":""Fact 1""},{""memoryRef"":""M2"",""fact"":""Fact 2""}]", "each entry as {memoryRef, fact}, in order, the fact shaped")
	Do $$$AssertEquals($ClassMethod(learned, "Shown", ..Entries(5), "Noted.").%Size(), 3, "at most three entries")
	Do $$$AssertEquals($ClassMethod(learned, "Shown", ..Entries(5), "Noted.").%Get(2).memoryRef, "M3", "the first three, in order")
	Set bad = "[1,""x"",null,{""memoryRef"":""M1""},{""text"":""t""},{""memoryRef"":""M2"",""text"":5},{""memoryRef"":"""",""text"":""t""},{""memoryRef"":""M3"",""text"":""""},{""memoryRef"":""M4"",""text"":"".""},{""memoryRef"":""M5"",""text"":""Kept.""}]"
	Do $$$AssertEquals($ClassMethod(learned, "Shown", bad, "Noted.").%ToJSON(), "[{""memoryRef"":""M5"",""fact"":""Kept""}]", "an entry that is not an object, lacks a text or a ref, or has nothing to show is dropped")
	Do $$$AssertEquals($ClassMethod(learned, "Shown", "[{""memoryRef"":""M1"",""text"":""a""}]", "").%Size(), 1, "a reply of no text says nothing")
}

Method TestLines()
{
	Set learned = "OcuTalon.Memory.Learned"
	Set text = "The Results partner's contact is Lee."
	Set json = [{"memoryRef": "M1", "text": (text)}].%ToJSON()
	For channel = "web", "telegram" {
		Set lines = $ClassMethod(learned, "Lines", json, "Noted.", channel, .sc)
		Do $$$AssertStatusOK(sc, "the line renders for "_channel)
		Do $$$AssertEquals(lines.%Size(), 1, "one line for one entry for "_channel)
		Do $$$AssertEquals(lines.%Get(0), ..Line("The Results partner's contact is Lee"), "the ruled line for "_channel_", one stop removed")
	}
	Set markup = "<b>Lee</b> & <script>x</script>"
	Set lines = $ClassMethod(learned, "Lines", [{"memoryRef": "M1", "text": (markup)}].%ToJSON(), "Noted.", "web", .sc)
	Do $$$AssertEquals(lines.%Get(0), ..Line(markup), "markup stays as the characters it is")
	Set long = $Translate($Justify("", 300), " ", "b")
	Set lines = $ClassMethod(learned, "Lines", [{"memoryRef": "M1", "text": (long)}].%ToJSON(), "Noted.", "telegram", .sc)
	Do $$$AssertEquals(lines.%Get(0), ..Line($Extract(long, 1, 199)_$Char(8230)), "a 300-character fact is cut to 199 and an ellipsis")
	Set lines = $ClassMethod(learned, "Lines", ..Entries(2), "Noted.", "web", .sc)
	Do $$$AssertEquals(lines.%Size()_"|"_lines.%Get(0)_"|"_lines.%Get(1), "2|"_..Line("Fact 1")_"|"_..Line("Fact 2"), "two entries, two lines, in order")
	Set lines = $ClassMethod(learned, "Lines", ..Entries(2), "I will remember both.", "web", .sc)
	Do $$$AssertEquals(lines.%Size(), 0, "a reply that says it gets no line")
	Set lines = $ClassMethod(learned, "Lines", "", "Noted.", "web", .sc)
	Do $$$AssertEquals(lines.%Size()_"|"_$$$ISOK(sc), "0|1", "no entries, no lines, and no error")
}

}
