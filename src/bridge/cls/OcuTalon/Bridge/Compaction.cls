/// The compaction prompt (AD-20): the text that asks the summarizing request to compress a conversation, with every
/// tool result kept verbatim. The runner does the compaction, so the prompt belongs to the bridge. Its first word,
/// PREFIX, is the constant that the CI mock keys on to recognize a compaction request.
Class OcuTalon.Bridge.Compaction
{

/// The first word of the prompt.
Parameter PREFIX = "OCUTALON-COMPACTION-V1";

/// The prompt, one line per line of text.
XData Prompt [ MimeType = text/plain ]
{
OCUTALON-COMPACTION-V1 You are a compression engine for an IRIS operations assistant's conversation.
Given the full transcript, including tool calls and tool outputs, return ONLY one valid JSON object, with no code fences and exactly these keys:
"user_goals": a string with the user's active goals;
"constraints": an array of strings;
"decisions": an array of strings: answers and decisions already given;
"facts_learned": an array of strings, one per tool result, each naming the tool, its tool call id, its arguments and every value it returned, e.g. "GetX (toolu_123) itemName=A returned count 5, id 77";
"tool_actions": an array of objects {"tool": the tool name (required), "input_summary": string, "result_summary": string, "state_change": string}, one per tool call;
"open_questions": an array of strings;
"next_steps": an array of strings.
Never drop a tool result: copy every number, name, id, date and error text a tool returned verbatim.
}

/// The prompt text: the lines of the Prompt block joined by a line feed, with no trailing line feed.
ClassMethod Prompt() As %String
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||Prompt")
	If '$IsObject(xdata) Quit ""
	Set text = ""
	Set stream = xdata.Data
	Do stream.Rewind()
	While 'stream.AtEnd {
		Set text = text _ $Select(text = "": "", 1: $Char(10)) _ stream.ReadLine()
	}
	Quit text
}

}
