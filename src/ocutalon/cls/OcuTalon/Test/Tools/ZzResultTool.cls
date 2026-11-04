/// The tools zz_result_text and zz_result_object of the tool result tests (Story 1.9; AD-10): a test fixture, never part of a production.
/// Both return through OcuTalon.Tools.Result. Text answers a string and Object a dynamic object {"data": <string>} of the asked number of
/// characters of content (Filler: the digits 0 to 9 over and over, so that a cut result shows which characters are kept). Filler is no
/// tool: the toolset names the two tools by their methods. A tool method runs inside AI Hub's callback, so it makes no AI Hub call and no
/// Python call (AD-6).
Class OcuTalon.Test.Tools.ZzResultTool Extends OcuTalon.Tools.Result
{

/// The readable label of the step of every tool of this class (Consistency Conventions: Agent step labels).
Parameter STEPLABEL = "Reading the test results";

/// The classification of the tools for the gate (AD-10): safe, so that the tool result tests keep running them.
Parameter CLASSIFICATION = "safe";

/// Read-only, so that the tools run after a taint, as the two calls of one response do.
Parameter READONLY = 1;

/// A text of chars characters.
ClassMethod Text(chars As %Integer = 0) As %String
{
	Quit ..Return(..Filler(chars))
}

/// A dynamic object whose "data" is a text of chars characters.
ClassMethod Object(chars As %Integer = 0) As %DynamicObject
{
	Quit ..Return({"data": (..Filler(chars))})
}

/// The digits 0 to 9 over and over, chars characters of them.
ClassMethod Filler(chars As %Integer) As %String
{
	Set text = ""
	For i = 1:1:(+chars \ 10) + 1 {
		Set text = text _ "0123456789"
	}
	Quit $Extract(text, 1, +chars)
}

}
