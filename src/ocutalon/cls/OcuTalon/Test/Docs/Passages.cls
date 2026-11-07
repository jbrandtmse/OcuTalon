/// Tests of the passage splitter and the document name (Story 19.4; AD-21). PURE: no table, no production, safe on a slot.
///   - TestSections: the matrix row "Sections": a Markdown text with an intro and two ## headings splits into passages whose sections are "", the first
///     heading and the second, with no heading line inside a passage and none over MAXPASSAGE characters;
///   - TestPlainText: 5,000 characters of words with no blank line split into passages of at most MAXPASSAGE characters, every section "", cut at word edges;
///   - TestCutOrder: a paragraph that is too long is cut at the last line break that fits, else at the last sentence end, else at the last space, else hard;
///   - TestPacking: paragraphs pack into one passage while they fit, a heading starts a new passage, and the order is kept;
///   - TestHeadings: only a line that starts with ## and a space opens a section (and only for markdown), trailing # characters are dropped, # and ### lines
///     stay passage lines, and the line \## is the escaped passage line ## that opens nothing (DW-832);
///   - TestBlanks: blank text, a heading with no body and CR LF line ends;
///   - TestWrongType: any other content type is an error with no passage;
///   - TestDocumentName: the name of a citation drops one final .md, .markdown, .txt, .pdf or .docx in any case.
Class OcuTalon.Test.Docs.Passages Extends %UnitTest.TestCase
{

Parameter CLASS = "OcuTalon.Docs.Passages";

/// The matrix row "Sections".
Method TestSections()
{
	Set lf = $Char(10)
	Set text = "# T" _ lf _ "an intro" _ lf _ "## Rotating the certificate" _ lf _ "1. Stop it." _ lf _ "2. Swap it." _ lf _ "3. Start it." _ lf _ lf _ "## Clearing the queue" _ lf _ "Resend what failed."
	Do $$$AssertStatusOK($ClassMethod(..#CLASS, "Split", text, "markdown", .passages), "the text is split")
	Do $$$AssertEquals(passages.%Size(), 3, "into three passages")
	If passages.%Size() '= 3 Quit
	Do $$$AssertEquals(passages.%Get(0).section _ "|" _ passages.%Get(0).text, "|# T" _ lf _ "an intro", "the intro has the section empty and keeps the # T line")
	Do $$$AssertEquals(passages.%Get(1).section _ "|" _ passages.%Get(1).text, "Rotating the certificate|1. Stop it." _ lf _ "2. Swap it." _ lf _ "3. Start it.", "the steps have the first heading")
	Do $$$AssertEquals(passages.%Get(2).section _ "|" _ passages.%Get(2).text, "Clearing the queue|Resend what failed.", "the last passage has the second heading")
	Set bad = ""
	Set i = 0
	While i < passages.%Size() {
		If ($Length(passages.%Get(i).text) > $Parameter(..#CLASS, "MAXPASSAGE")) || (passages.%Get(i).text [ (lf _ "## ")) || ($Extract(passages.%Get(i).text, 1, 3) = "## ") Set bad = bad _ " " _ i
		Set i = i + 1
	}
	Do $$$AssertEquals(bad, "", "none is over MAXPASSAGE characters and none holds a heading line")
	Do $$$AssertEquals($Parameter(..#CLASS, "MAXPASSAGE"), 1000, "MAXPASSAGE is 1,000 characters")
}

/// 5,000 characters with no blank line.
Method TestPlainText()
{
	Set text = ""
	For i = 1:1:1000 Set text = text _ "word "
	Do $$$AssertEquals($Length(text), 5000, "the text has 5,000 characters")
	Do $$$AssertStatusOK($ClassMethod(..#CLASS, "Split", text, "text", .passages), "it is split")
	Do $$$AssertTrue(passages.%Size() '< 5, "into at least five passages: " _ passages.%Size())
	Set long = 0, sections = "", words = 0, odd = 0
	Set i = 0
	While i < passages.%Size() {
		Set passage = passages.%Get(i)
		If $Length(passage.text) > 1000 Set long = long + 1
		Set sections = sections _ passage.section
		Set pieces = $Length(passage.text, " ")
		For j = 1:1:pieces {
			Set words = words + 1
			If $Piece(passage.text, " ", j) '= "word" Set odd = odd + 1
		}
		Set i = i + 1
	}
	Do $$$AssertEquals(long, 0, "none is over 1,000 characters")
	Do $$$AssertEquals(sections, "", "every section is empty")
	Do $$$AssertEquals(words _ "|" _ odd, "1000|0", "and every word is whole: the cuts fall between words")
}

Method TestCutOrder()
{
	Set lf = $Char(10)
	Set a = $Translate($Justify("", 99), " ", "a")
	Set text = ""
	For i = 1:1:15 Set text = text _ $Select(i > 1: lf, 1: "") _ a
	Do $ClassMethod(..#CLASS, "Split", text, "text", .passages)
	Do $$$AssertEquals(..Lengths(passages), "999,499", "lines of 99 characters: the cut is at the last line break that fits (ten lines, then five)")
	Set text = ""
	For i = 10:1:89 Set text = text _ "This is sentence " _ i _ ". "
	Do $ClassMethod(..#CLASS, "Split", $ZStrip(text, ">W"), "text", .passages)
	Set bad = "", i = 0
	While i < passages.%Size() {
		Set passage = passages.%Get(i).text
		If ($Extract(passage, 1, 4) '= "This") || ($Extract(passage, $Length(passage)) '= ".") || ($Length(passage) > 1000) Set bad = bad _ " " _ i
		Set i = i + 1
	}
	Do $$$AssertTrue(passages.%Size() '< 2, "one line of sentences gives several passages: " _ passages.%Size())
	Do $$$AssertEquals(bad, "", "each starts with a whole sentence and ends with a full stop, none over 1,000 characters")
	Set text = ""
	For i = 1:1:300 Set text = text _ "word "
	Do $ClassMethod(..#CLASS, "Split", $ZStrip(text, ">W"), "text", .passages)
	Set bad = "", i = 0
	While i < passages.%Size() {
		Set passage = passages.%Get(i).text
		If ($Extract(passage, 1, 4) '= "word") || ($Extract(passage, $Length(passage) - 3, $Length(passage)) '= "word") || ($Length(passage) > 1000) Set bad = bad _ " " _ i
		Set i = i + 1
	}
	Do $$$AssertEquals(bad, "", "a line with no full stop is cut at a space: every passage is whole words")
	Set text = $Translate($Justify("", 2500), " ", "x")
	Do $ClassMethod(..#CLASS, "Split", text, "text", .passages)
	Do $$$AssertEquals(..Lengths(passages), "1000,1000,500", "2,500 characters with no break at all are cut hard at 1,000")
}

Method TestPacking()
{
	Set lf = $Char(10)
	Set a = $Translate($Justify("", 400), " ", "a"), b = $Translate($Justify("", 400), " ", "b"), c = $Translate($Justify("", 400), " ", "c")
	Do $ClassMethod(..#CLASS, "Split", a _ lf _ lf _ b _ lf _ lf _ c, "text", .passages)
	Do $$$AssertEquals(..Lengths(passages), "802,400", "two paragraphs of 400 pack into 802 characters (joined by a blank line), the third starts the next")
	Do $$$AssertEquals(passages.%Get(0).text, a _ lf _ lf _ b, "in order")
	Do $$$AssertEquals(passages.%Get(1).text, c, "and the third is alone")
	Do $ClassMethod(..#CLASS, "Split", "one" _ lf _ lf _ "## S" _ lf _ "two", "markdown", .passages)
	Do $$$AssertEquals(..Compact(passages), "|one;S|two", "a heading starts a new passage even when both would fit")
	Do $ClassMethod(..#CLASS, "Split", "first" _ lf _ lf _ lf _ lf _ "second", "text", .passages)
	Do $$$AssertEquals(..Compact(passages), "|first" _ lf _ lf _ "second", "several blank lines count as one separator")
}

Method TestHeadings()
{
	Set lf = $Char(10)
	Set text = "## Real heading ##" _ lf _ "a" _ lf _ "### Three" _ lf _ "#### Four" _ lf _ "#Tight" _ lf _ "##Tight" _ lf _ "\## Literal heading" _ lf _ "# One"
	Do $ClassMethod(..#CLASS, "Split", text, "markdown", .passages)
	Do $$$AssertEquals(..Compact(passages), "Real heading|a" _ lf _ "### Three" _ lf _ "#### Four" _ lf _ "#Tight" _ lf _ "##Tight" _ lf _ "## Literal heading" _ lf _ "# One", "only ## and a space opens a section; # and ### lines, tight ones and the escaped line stay passage lines (the escape loses its backslash)")
	Do $ClassMethod(..#CLASS, "Split", "## Not a heading" _ lf _ "body", "text", .passages)
	Do $$$AssertEquals(..Compact(passages), "|## Not a heading" _ lf _ "body", "in a text document no line opens a section")
	Do $ClassMethod(..#CLASS, "Split", "## " _ lf _ "body", "markdown", .passages)
	Do $$$AssertEquals(..Compact(passages), "|body", "an empty heading opens the section empty")
	Do $ClassMethod(..#CLASS, "Split", "##   Spaced  " _ lf _ "body", "markdown", .passages)
	Do $$$AssertEquals(..Compact(passages), "Spaced|body", "the heading is trimmed")
	Do $ClassMethod(..#CLASS, "Split", "## A" _ lf _ "x" _ lf _ "## A" _ lf _ "y", "markdown", .passages)
	Do $$$AssertEquals(..Compact(passages), "A|x;A|y", "the same heading twice gives two passages of the same section")
}

Method TestBlanks()
{
	Set lf = $Char(10), cr = $Char(13)
	Do $ClassMethod(..#CLASS, "Split", "", "markdown", .passages)
	Do $$$AssertEquals(passages.%Size(), 0, "empty text has no passage")
	Do $ClassMethod(..#CLASS, "Split", "   " _ lf _ lf _ "  " _ lf, "text", .passages)
	Do $$$AssertEquals(passages.%Size(), 0, "blank text has none")
	Do $ClassMethod(..#CLASS, "Split", "## Only a heading" _ lf _ "## Another", "markdown", .passages)
	Do $$$AssertEquals(passages.%Size(), 0, "headings with no body have none")
	Do $ClassMethod(..#CLASS, "Split", "a" _ cr _ lf _ "b" _ cr _ lf _ cr _ lf _ "c" _ cr _ "d", "text", .passages)
	Do $$$AssertEquals(..Compact(passages), "|a" _ lf _ "b" _ lf _ lf _ "c" _ lf _ "d", "CR LF and CR are line ends")
	Do $ClassMethod(..#CLASS, "Split", "word   " _ lf _ "next   ", "text", .passages)
	Do $$$AssertEquals(..Compact(passages), "|word" _ lf _ "next", "trailing white space is dropped")
}

Method TestWrongType()
{
	For type = "pdf", "docx", "", "html" {
		Set sc = $ClassMethod(..#CLASS, "Split", "text", type, .passages)
		Do $$$AssertStatusNotOK(sc, "'" _ type _ "' is not a type the splitter reads")
		Do $$$AssertEquals(passages.%Size(), 0, "and gives no passage")
	}
}

Method TestDocumentName()
{
	Set class = "OcuTalon.Docs.Store"
	For pair = "Results runbook.md|Results runbook", "Results runbook.MD|Results runbook", "notes.markdown|notes", "notes.Markdown|notes", "a.txt|a", "A.TXT|A", "scan.pdf|scan", "scan.PDF|scan", "report.docx|report", "report.DocX|report", "plain|plain", "a.b|a.b", "a.md.txt|a.md", "a.txt.md|a.txt", ".md|.md", "file.mdx|file.mdx", "x.pdf.docx|x.pdf", "my.notes.md|my.notes", "|" {
		Do $$$AssertEquals($ClassMethod(class, "DocumentName", $Piece(pair, "|", 1)), $Piece(pair, "|", 2), "'" _ $Piece(pair, "|", 1) _ "' is named '" _ $Piece(pair, "|", 2) _ "'")
	}
}

/// The lengths of the passages, comma-separated.
ClassMethod Lengths(passages As %DynamicArray) As %String [ Private ]
{
	Set result = ""
	Set i = 0
	While i < passages.%Size() {
		Set result = result _ $Select(i > 0: ",", 1: "") _ $Length(passages.%Get(i).text)
		Set i = i + 1
	}
	Quit result
}

/// The passages as <section>|<text>, joined by semicolons.
ClassMethod Compact(passages As %DynamicArray) As %String [ Private ]
{
	Set result = ""
	Set i = 0
	While i < passages.%Size() {
		Set result = result _ $Select(i > 0: ";", 1: "") _ passages.%Get(i).section _ "|" _ passages.%Get(i).text
		Set i = i + 1
	}
	Quit result
}

}
