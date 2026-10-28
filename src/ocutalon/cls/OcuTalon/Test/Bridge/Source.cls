/// The code of a class, for the tests that scan source (Story 1.2; AD-6, AD-7). Text(class) is the UDL text of a compiled class;
/// CodeLines(text) drops the comment lines; Lines and Matches find the code lines that match a pattern, in any case, like
/// ObjectScript class names. A comment line starts, after white space, with //, ///, ;, #; or ##;, as in
/// docker/tests/test-class-rules.sh. A comment after code on the same line is code.
Class OcuTalon.Test.Bridge.Source
{

/// The UDL text of a class in this namespace, lines separated by a line feed. The status is an error when the class has no source.
ClassMethod Text(class As %String, Output text As %String) As %Status
{
	Set text = ""
	Quit ##class(%Compiler.UDL.TextServices).GetTextAsString($Namespace, class, .text, $Char(10))
}

/// The lines of the text that are not comment lines, as a list.
ClassMethod CodeLines(text As %String) As %List
{
	Set lines = ""
	For i = 1:1:$Length(text, $Char(10)) {
		Set line = $Piece(text, $Char(10), i)
		Set start = $ZStrip(line, "<W")
		If ($Extract(start, 1, 2) = "//") || ($Extract(start) = ";") || ($Extract(start, 1, 2) = "#;") || ($Extract(start, 1, 3) = "##;") Continue
		Set lines = lines _ $ListBuild(line)
	}
	Quit lines
}

/// The code lines that match the pattern, in any case, as a list. The pattern is an ICU regular expression, or plain text
/// when literal is 1.
ClassMethod Lines(text As %String, pattern As %String, literal As %Boolean = 0) As %List
{
	Set found = ""
	Set lines = ..CodeLines(text)
	Set position = 0
	While $ListNext(lines, position, line) {
		If literal {
			If $ZConvert(line, "L") [ $ZConvert(pattern, "L") Set found = found _ $ListBuild(line)
		} ElseIf $Locate(line, "(?i)"_pattern) {
			Set found = found _ $ListBuild(line)
		}
	}
	Quit found
}

/// 1 when a code line of the text matches the pattern, in any case. The pattern is an ICU regular expression, or plain text
/// when literal is 1.
ClassMethod Matches(text As %String, pattern As %String, literal As %Boolean = 0) As %Boolean
{
	Quit $ListLength(..Lines(text, pattern, literal)) > 0
}

}
