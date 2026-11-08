/// Splits a document's text into passages, each under the section it belongs to (AD-21, Story 19.4; Lane A). A pure function of the text and the content
/// type: no SQL, no global, no AI Hub call and no Python, so DocumentOps, the tests and Story 19.7 (extracted text) share one splitter.
///   - markdown, pdf and docx: the text that Docs.Extract writes for a PDF (a ## Page n line for each page) or a Word file (a ## line for each Heading 1) is read as
///     Markdown, so a PDF is sectioned by its page lines and a Word file by its Heading 1 lines. A line that starts with the two characters ## and a space opens a
///     section. The heading (trimmed, trailing # characters removed, and cut to at most MAXSECTION characters) is the section of every passage up to the next such
///     line, and the heading line is not passage text. Text before the first one has the section "". A line of one # or of three or more # is an ordinary line. A
///     line that starts with a backslash and then ## and a space (the escape that Docs.Extract uses for a file's own ## lines, DW-832) is the passage line without
///     the backslash and opens nothing.
///   - text: one section "" and no line opens a section.
///   - Within a section, the paragraphs (separated by blank lines) are packed into passages of at most MAXPASSAGE characters, joined by a blank line. A
///     paragraph longer than MAXPASSAGE is cut at the last line break that fits, else at the last sentence end (a full stop and a space), else at the last
///     space, else hard at MAXPASSAGE. A passage that is blank is dropped. A passage holds no heading line.
/// Each passage of the result is a dynamic object {"text","section"}; the passage's position in the array is its chunk_index.
Class OcuTalon.Docs.Passages
{

/// The most characters of a passage (about 250 word pieces, under the 256 that the embedding model reads).
Parameter MAXPASSAGE = 1000;

/// The most characters of a section's name: a longer heading is cut, so that every search result, which repeats the section in its metadata, fits the room
/// the gate keeps for one search (Policy.Gate RAGRESULTMAX, NFR-3).
Parameter MAXSECTION = 100;

/// The content types the splitter reads; any other type is an error. pdf and docx are read as markdown (MARKDOWNTYPES).
Parameter TYPES = "markdown,text,pdf,docx";

/// The content types whose lines ## open a section.
Parameter MARKDOWNTYPES = "markdown,pdf,docx";

/// Splits text (a document of the content type markdown, text, pdf or docx) into passages (a dynamic array of {"text","section"}).
ClassMethod Split(text As %String, contentType As %String, Output passages As %DynamicArray) As %Status
{
	Set passages = []
	If ($ListFind($ListFromString(..#TYPES), contentType) = 0) {
		Quit $SYSTEM.Status.Error(5001, "The splitter reads markdown, text, pdf and docx, not '"_contentType_"'")
	}
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set markdown = ($ListFind($ListFromString(..#MARKDOWNTYPES), contentType) > 0)
		Set text = $Replace($Replace(text, $Char(13, 10), $Char(10)), $Char(13), $Char(10))
		Set section = ""
		Set block = ""
		Set position = 1
		Set length = $Length(text)
		While position '> (length + 1) {
			Set end = $Find(text, $Char(10), position)
			If end = 0 {
				Set line = $Extract(text, position, length)
				Set position = length + 2
			} Else {
				Set line = $Extract(text, position, end - 2)
				Set position = end
			}
			If markdown && ($Extract(line, 1, 3) = "## ") {
				Do ..Flush(block, section, passages)
				Set block = ""
				Set section = ..Heading($Extract(line, 4, *))
				Continue
			}
			If markdown && ($Extract(line, 1, 4) = "\## ") Set line = $Extract(line, 2, *)
			Set block = block _ line _ $Char(10)
		}
		Do ..Flush(block, section, passages)
	} Catch exception {
		Set passages = []
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The section name of a heading line's text: trimmed, trailing # characters removed, trimmed again, and cut to at most MAXSECTION characters.
ClassMethod Heading(text As %String) As %String
{
	Set heading = $ZStrip(text, "<>W")
	While heading '= "" {
		If $Extract(heading, $Length(heading)) '= "#" Quit
		Set heading = $Extract(heading, 1, $Length(heading) - 1)
	}
	Quit $ZStrip($Extract($ZStrip(heading, "<>W"), 1, ..#MAXSECTION), ">W")
}

/// Packs the paragraphs of one section's lines (block, every line ended by a line feed) into passages and adds them to passages.
ClassMethod Flush(block As %String, section As %String, passages As %DynamicArray) [ Private ]
{
	If $ZStrip(block, "*WC") = "" Quit
	Set current = ""
	Set paragraph = ""
	Set position = 1
	Set length = $Length(block)
	While position '> length {
		Set end = $Find(block, $Char(10), position)
		Set line = $Extract(block, position, end - 2)
		Set position = end
		If $ZStrip(line, "<>W") = "" {
			Do ..Pack(paragraph, section, passages, .current)
			Set paragraph = ""
		} Else {
			Set paragraph = paragraph _ $Select(paragraph = "": "", 1: $Char(10)) _ $ZStrip(line, ">W")
		}
	}
	Do ..Pack(paragraph, section, passages, .current)
	Do ..Emit(current, section, passages)
}

/// Adds one paragraph to the passage being built (current), emitting the passage first when the paragraph does not fit.
ClassMethod Pack(paragraph As %String, section As %String, passages As %DynamicArray, ByRef current As %String) [ Private ]
{
	If paragraph = "" Quit
	If $Length(paragraph) > ..#MAXPASSAGE {
		Do ..Emit(current, section, passages)
		Set current = ""
		Set rest = paragraph
		While $Length(rest) > ..#MAXPASSAGE {
			Set cut = ..CutAt(rest)
			Do ..Emit($Extract(rest, 1, cut), section, passages)
			Set rest = $ZStrip($Extract(rest, cut + 1, *), "<WC")
		}
		Set current = rest
		Quit
	}
	If current = "" {
		Set current = paragraph
	} ElseIf ($Length(current) + 2 + $Length(paragraph)) '> ..#MAXPASSAGE {
		Set current = current _ $Char(10, 10) _ paragraph
	} Else {
		Do ..Emit(current, section, passages)
		Set current = paragraph
	}
}

/// The number of characters of text (longer than MAXPASSAGE) that make the next passage: up to the last line break that fits, else up to the last
/// sentence end (the full stop stays), else up to the last space, else MAXPASSAGE.
ClassMethod CutAt(text As %String) As %Integer [ Private ]
{
	Set window = $Extract(text, 1, ..#MAXPASSAGE + 1)
	Set start = ..LastStart(window, $Char(10), ..#MAXPASSAGE + 1)
	If start > 0 Quit start - 1
	Set start = ..LastStart(window, ". ", ..#MAXPASSAGE)
	If start > 0 Quit start
	Set start = ..LastStart(window, " ", ..#MAXPASSAGE + 1)
	If start > 0 Quit start - 1
	Quit ..#MAXPASSAGE
}

/// The position of the last occurrence of needle in window that starts after the first character and at or before last, else 0.
ClassMethod LastStart(window As %String, needle As %String, last As %Integer) As %Integer [ Private ]
{
	Set result = 0
	Set position = 1
	For {
		Set found = $Find(window, needle, position)
		If found = 0 Quit
		Set start = found - $Length(needle)
		If start > last Quit
		If start > 1 Set result = start
		Set position = start + 1
	}
	Quit result
}

/// Adds a passage with the section, unless its text is blank.
ClassMethod Emit(text As %String, section As %String, passages As %DynamicArray) [ Private ]
{
	Set text = $ZStrip(text, "<>WC")
	If text = "" Quit
	Do passages.%Push({"text": (text), "section": (section)})
}

}
