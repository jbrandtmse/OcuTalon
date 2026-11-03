/// The compaction prompt (AD-20): the text that asks the summarizing request to compress a conversation, with every
/// tool result kept verbatim. The runner does the compaction, so the prompt belongs to the bridge. Its first word,
/// PREFIX, is the constant that the CI mock keys on to recognize a compaction request.
/// The class also holds the pure rules of the runner's compaction (Adapter.Agent, AD-6, AD-20). They take the dynamic arrays and objects
/// of a session's history (the array that GetContext() gives: messages with a role and a content, an assistant message's tool_calls and a
/// tool message's tool_call_id) and make no AI Hub call:
///   - Cut: where the summarized part of a history ends, so that the last user turn is kept whole;
///   - Check: whether the history of a fork starts with a user message and keeps every tool result after its tool call;
///   - Seed: the code-written summary of the stored user and assistant texts, for the fresh session of the fallback;
///   - TranscriptChars and SummaryChars: the sizes that the Usage row of the summarizer's request is estimated from;
///   - SummarizerSettings: the provider settings of the summarizer.
Class OcuTalon.Bridge.Compaction
{

/// The first word of the prompt.
Parameter PREFIX = "OCUTALON-COMPACTION-V1";

/// The seconds that Decide adds to the timer of a flagged turn that continues its conversation, for the summarizer's request, and the
/// request timeout and attempt timeout of the summarizer (AD-8, AD-20).
Parameter SUMMARIZERSECONDS = 20;

/// The most exchanges (a user text and the assistant texts after it) that a seed holds: the newest ones.
Parameter SEEDTURNS = 20;

/// The longest text of one side of an exchange in a seed, the cut mark included.
Parameter SEEDPART = 2000;

/// The longest seed, in characters. It is also the most that Decide counts of a stored history after compaction (Process.Decide Precheck).
Parameter SEEDCHARS = 80000;

/// The first line of a seed.
Parameter SEEDHEAD = "This conversation so far, as recorded (the user's messages and the assistant's replies, the oldest left out when it is long):";

/// The start of the user's side of an exchange in a seed.
Parameter SEEDUSER = "User: ";

/// The start of the assistant's side of an exchange in a seed.
Parameter SEEDREPLY = "Assistant: ";

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

/// Where the summarized part of the history ends (AD-20): k is the number of messages from the newest user message that is not a tool
/// result to the end of the context, which a summary keeps whole (ForkAndSummarize's preserveRecent), and older holds the messages
/// before it, as a dynamic array. k is 0 and older empty when there is no such user message, or when only system messages come before it,
/// because there is then nothing to summarize. A context that is not an array gives 0.
ClassMethod Cut(context As %DynamicArray, Output older As %DynamicArray) As %Integer
{
	Set older = []
	If '$IsObject($Get(context)) Quit 0
	Set size = context.%Size()
	Set start = -1
	For i = size - 1:-1:0 {
		If ..IsUser(context.%Get(i)) {
			Set start = i
			Quit
		}
	}
	If start < 0 Quit 0
	Set other = 0
	For i = 0:1:start - 1 {
		If ..Role(context.%Get(i)) '= "system" {
			Set other = 1
			Quit
		}
	}
	If 'other Quit 0
	For i = 0:1:start - 1 {
		Do older.%Push(context.%Get(i))
	}
	Quit size - start
}

/// 1 when the history of a fork is safe to continue (AD-20): its first message that is not a system message is a user message that is not
/// a tool result, and every tool result follows the tool call that it answers (a result whose call comes later, or that has no call, fails).
/// A history with no message but system ones fails. It is pure.
ClassMethod Check(context As %DynamicArray) As %Boolean
{
	If '$IsObject($Get(context)) Quit 0
	Kill calls
	Set started = 0
	For i = 0:1:context.%Size() - 1 {
		Set message = context.%Get(i)
		If '$IsObject(message) Return 0
		Set role = ..Role(message)
		If 'started && (role '= "system") {
			Set started = 1
			If '..IsUser(message) Return 0
		}
		If role = "assistant" {
			Set ids = ..CallIds(message)
			For j = 1:1:$ListLength(ids) {
				If $List(ids, j) '= "" Set calls($List(ids, j)) = 1
			}
		}
		If ..IsResult(message) {
			Set ids = ..ResultIds(message)
			If ids = "" Return 0
			For j = 1:1:$ListLength(ids) {
				If ($List(ids, j) = "") || '$Data(calls($List(ids, j))) Return 0
			}
		}
	}
	Quit started
}

/// The code-written summary of the stored conversation for the fresh AI session of the fallback (AD-20): SEEDHEAD, then one line for each
/// stored user text (SEEDUSER) and assistant text (SEEDREPLY), oldest first, of the newest SEEDTURNS exchanges. Each text is cut to SEEDPART
/// characters (the last of them the cut mark), the oldest lines are left out until the seed is at most SEEDCHARS, and no tool call, tool
/// result or system message is quoted. "" for a history with no user or assistant text. It is pure.
ClassMethod Seed(context As %DynamicArray) As %String
{
	If '$IsObject($Get(context)) Quit ""
	Kill lines
	Set count = 0
	Set exchange = 0
	For i = 0:1:context.%Size() - 1 {
		Set message = context.%Get(i)
		Set role = ..Role(message)
		If ..IsResult(message) || ((role '= "user") && (role '= "assistant")) Continue
		Set text = ..TextOf(message)
		If $ZStrip(text, "*WC") = "" Continue
		If role = "user" Set exchange = exchange + 1
		Set count = count + 1
		Set lines(count) = $Select(role = "user": ..#SEEDUSER, 1: ..#SEEDREPLY) _ ..CutText(text)
		Set lines(count, "x") = exchange
	}
	If count = 0 Quit ""
	Set first = 1
	Set firstExchange = exchange - ..#SEEDTURNS + 1
	While (first '> count) && (lines(first, "x") < firstExchange) {
		Set first = first + 1
	}
	Set total = $Length(..#SEEDHEAD)
	For i = first:1:count {
		Set total = total + 1 + $Length(lines(i))
	}
	While (first '> count) && (total > ..#SEEDCHARS) {
		Set total = total - 1 - $Length(lines(first))
		Set first = first + 1
	}
	If first > count Quit ""
	Set seed = ..#SEEDHEAD
	For i = first:1:count {
		Set seed = seed _ $Char(10) _ lines(i)
	}
	Quit seed
}

/// The size of the transcript that the summarizer is asked to compress, in characters: the length of the JSON of the summarized messages
/// (Cut's older). 0 for anything that is not an array.
ClassMethod TranscriptChars(older As %DynamicArray) As %Integer
{
	If '$IsObject($Get(older)) Quit 0
	Quit $Length(older.%ToJSON())
}

/// The size of the summary that a fork stores, in characters: the text of the system messages at the head of its history (the summary, and
/// the action log when tools ran). 0 for anything that is not an array.
ClassMethod SummaryChars(context As %DynamicArray) As %Integer
{
	If '$IsObject($Get(context)) Quit 0
	Set chars = 0
	For i = 0:1:context.%Size() - 1 {
		Set message = context.%Get(i)
		If ..Role(message) '= "system" Quit
		Set chars = chars + $Length(..TextOf(message))
	}
	Quit chars
}

/// The provider settings of the summarizer (AD-7, AD-8, AD-20): a copy of the runner's settings with three overrides and nothing else
/// changed, so that no sampling parameter is added. The overrides are extra_config.output_config.effort low, the only way that an effort
/// reaches the summarizer; http_config.request_timeout_secs SUMMARIZERSECONDS; and the whole retry block of http_config with no retries
/// (max_retries 0, attempt_timeout_secs SUMMARIZERSECONDS, initial_backoff_ms 500, max_backoff_ms 2000), never a part of it, because AI Hub
/// waits for a Retry-After for as long as 30 seconds with a missing or partial block. The settings argument is not changed.
ClassMethod SummarizerSettings(settings As %DynamicObject) As %DynamicObject
{
	Set copy = $Select($IsObject($Get(settings)): {}.%FromJSON(settings.%ToJSON()), 1: {})
	Set extra = copy."extra_config"
	If '$IsObject(extra) Set extra = {}
	Set output = extra."output_config"
	If '$IsObject(output) Set output = {}
	Do output.%Set("effort", "low")
	Do extra.%Set("output_config", output)
	Do copy.%Set("extra_config", extra)
	Set http = copy."http_config"
	If '$IsObject(http) Set http = {}
	Do http.%Set("request_timeout_secs", ..#SUMMARIZERSECONDS, "number")
	Set retry = {}
	Do retry.%Set("max_retries", 0, "number")
	Do retry.%Set("attempt_timeout_secs", ..#SUMMARIZERSECONDS, "number")
	Do retry.%Set("initial_backoff_ms", 500, "number")
	Do retry.%Set("max_backoff_ms", 2000, "number")
	Do http.%Set("retry", retry)
	Do copy.%Set("http_config", http)
	Quit copy
}

/// The role of a message, or "" when it is not an object.
ClassMethod Role(message) As %String [ Private ]
{
	If '$IsObject(message) Quit ""
	Quit message.%Get("role")
}

/// 1 when the message answers a tool call: a tool message, or one whose content holds a tool_result block.
ClassMethod IsResult(message) As %Boolean [ Private ]
{
	If '$IsObject(message) Quit 0
	If message.%Get("role") = "tool" Quit 1
	Quit ..BlockIds(message, "tool_result", "tool_use_id") '= ""
}

/// 1 when the message is a user message that is not a tool result.
ClassMethod IsUser(message) As %Boolean [ Private ]
{
	Quit (..Role(message) = "user") && '..IsResult(message)
}

/// The ids of the tool calls of an assistant message, as a list: its tool_calls and the tool_use blocks of its content.
ClassMethod CallIds(message) As %List [ Private ]
{
	Set ids = ..BlockIds(message, "tool_use", "id")
	If message.%GetTypeOf("tool_calls") = "array" {
		Set iterator = message."tool_calls".%GetIterator()
		While iterator.%GetNext(, .call) {
			If $IsObject(call) && (call.%Get("id") '= "") Set ids = ids _ $ListBuild(call.%Get("id"))
		}
	}
	Quit ids
}

/// The ids of the calls that a result message answers, as a list: its tool_call_id, or the tool_use_id of each of its tool_result blocks.
/// A result that names none gives "" (which fails Check).
ClassMethod ResultIds(message) As %List [ Private ]
{
	If message.%Get("role") = "tool" Quit $Select(message.%Get("tool_call_id") = "": "", 1: $ListBuild(message.%Get("tool_call_id")))
	Quit ..BlockIds(message, "tool_result", "tool_use_id")
}

/// The values of the key of every content block of the type, as a list.
ClassMethod BlockIds(message, type As %String, key As %String) As %List [ Private ]
{
	Set ids = ""
	If message.%GetTypeOf("content") '= "array" Quit ids
	Set iterator = message.content.%GetIterator()
	While iterator.%GetNext(, .block) {
		If $IsObject(block) && (block.%Get("type") = type) Set ids = ids _ $ListBuild(block.%Get(key))
	}
	Quit ids
}

/// The text of a message: its string content, or its text blocks put together.
ClassMethod TextOf(message) As %String [ Private ]
{
	If '$IsObject(message) Quit ""
	Set type = message.%GetTypeOf("content")
	If type = "string" Quit message.content
	If type '= "array" Quit ""
	Set text = ""
	Set iterator = message.content.%GetIterator()
	While iterator.%GetNext(, .block) {
		If $IsObject(block) && (block.%GetTypeOf("text") = "string") Set text = text _ block.text
	}
	Quit text
}

/// The text cut to SEEDPART characters; a longer text ends with the cut mark.
ClassMethod CutText(text As %String) As %String [ Private ]
{
	If $Length(text) > ..#SEEDPART Quit $Extract(text, 1, ..#SEEDPART - 1) _ $Char(8230)
	Quit text
}

}
