/// The buffer of the agent steps of one Chat call (AD-9), in the runner's job. The step renderer and the step audit policy, which AI
/// Hub calls during Chat, append to it; the adapter reads it after Chat, outside every callback, and turns it into the redacted
/// step records that travel on the Reply. It lives in the process-private global ^||OcuTalonBP.Steps, not in a local variable,
/// because a callback of AI Hub may New local variables, in the pattern of OcuTalon.Bridge.Context; it ends with the process, and a
/// job that did not call Start has no buffer, so that every append does nothing.
///   - Start(baseChars) empties the buffer and sets the clock mark. baseChars is the size of what the first request carries before
///     any model text or tool result: the agent's system prompt, its tool catalog and the request's input, in characters.
///   - Mark() moves the clock mark; Model(textLength) appends one model step and Tool(...) appends one tool step, and both move
///     the mark. A model step lasts from the mark to now. Its estimate in characters is baseChars plus the text lengths of the
///     earlier model steps plus the lengths of the arguments and of the results (or the errors) of the earlier tool steps.
///   - Estimates() gives the estimated tokens of the model steps, in order; Records() gives the step records; End() empties the buffer.
/// A count in tokens is the count in characters divided by CHARSPERTOKEN, rounded up. Records() passes every label and every part
/// of a summary through OcuTalon.Bridge.Redact first and cuts it after, so that a cut can never split a secret out of its pattern.
/// The methods that the callbacks call make no AI Hub call and run no Python (AD-6). This class names no other OcuTalon package (AD-2).
Class OcuTalon.Bridge.Adapter.StepBuffer
{

/// Characters per token of an estimate: the rate of the compaction estimate (AD-20).
Parameter CHARSPERTOKEN = 4;

/// The label of a tool whose class declares none (AD-9).
Parameter GENERICLABEL = "Running a tool";

/// The longest tool name, input text, result or error text and label in a record, in characters, a cut part's "..." included.
Parameter MAXNAME = 64;

Parameter MAXINPUTS = 300;

Parameter MAXRESULT = 400;

Parameter MAXLABEL = 200;

/// The longest summary: the MAXLEN of OcuTalon.Bridge.Msg.AgentStep.Summary.
Parameter MAXSUMMARY = 1000;

/// Empties the buffer and starts a call: the base of every estimate and the clock mark.
ClassMethod Start(baseChars As %Integer = 0)
{
	Kill ^||OcuTalonBP.Steps
	Set ^||OcuTalonBP.Steps = 1
	Set ^||OcuTalonBP.Steps("base") = +baseChars
	Set ^||OcuTalonBP.Steps("acc") = 0
	Set ^||OcuTalonBP.Steps("n") = 0
	Set ^||OcuTalonBP.Steps("mark") = $ZHorolog
}

/// 1 when this process has started a call and not ended it.
ClassMethod Active() As %Boolean
{
	Quit $Data(^||OcuTalonBP.Steps) # 2
}

/// Moves the clock mark to now. Does nothing when there is no buffer.
ClassMethod Mark()
{
	If ..Active() Set ^||OcuTalonBP.Steps("mark") = $ZHorolog
}

/// Appends one model step whose reply text is textLength characters long. Does nothing when there is no buffer.
ClassMethod Model(textLength As %Integer = 0)
{
	If '..Active() Quit
	Set now = $ZHorolog
	Set n = ^||OcuTalonBP.Steps("n") + 1
	Set duration = $Number((now - ^||OcuTalonBP.Steps("mark")) * 1000, 0)
	Set ^||OcuTalonBP.Steps(n) = $ListBuild("model", duration, ^||OcuTalonBP.Steps("base") + ^||OcuTalonBP.Steps("acc"), +textLength)
	Set ^||OcuTalonBP.Steps("acc") = ^||OcuTalonBP.Steps("acc") + textLength
	Set ^||OcuTalonBP.Steps("n") = n
	Set ^||OcuTalonBP.Steps("mark") = $ZHorolog
}

/// Appends one tool step with the raw strings. status is ok, error or denied; detail is the error or denial text. Does nothing when
/// there is no buffer. A step is added whole or not at all: an append that raises (a string over the limit) leaves the buffer as it was.
ClassMethod Tool(name As %String = "", toolClass As %String = "", arguments As %String = "", result As %String = "", durationMs As %Integer = 0, status As %String = "ok", detail As %String = "")
{
	If '..Active() Quit
	Set n = ^||OcuTalonBP.Steps("n") + 1
	Set chars = $Length(arguments) + $Length($Select(result '= "": result, 1: detail))
	Set ^||OcuTalonBP.Steps(n) = $ListBuild("tool", +durationMs, chars, name, toolClass, arguments, result, status, detail)
	Set ^||OcuTalonBP.Steps("acc") = ^||OcuTalonBP.Steps("acc") + chars
	Set ^||OcuTalonBP.Steps("n") = n
	Set ^||OcuTalonBP.Steps("mark") = $ZHorolog
}

/// The estimated tokens of the model steps, in order, as a list; empty when there is none or no buffer.
ClassMethod Estimates() As %List
{
	Set estimates = ""
	If '..Active() Quit estimates
	For i = 1:1:+$Get(^||OcuTalonBP.Steps("n")) {
		Set step = ^||OcuTalonBP.Steps(i)
		If $List(step, 1) = "model" Set estimates = estimates _ $ListBuild(..Tokens($List(step, 3)))
	}
	Quit estimates
}

/// The step records in buffer order, as a dynamic array of {"kind","label","summary","durationMs","status","estimatedTokens"}; empty
/// when there is no buffer. Call it after Chat, outside every callback.
///   - A model step: kind model, label "Model request <n>", summary "About <t> tokens sent (an estimate). Reply: <c> characters of
///     text, <k> tool calls.", where k counts the tool steps that follow it before the next model step, status ok.
///   - A tool step: kind tool, the label of its class (LabelFor), summary "<name>. Inputs: <arguments>. Result: <result>." (or "Error:
///     <detail>." or "Denied: <detail>."), then "About <t> tokens added to the next request (an estimate)."; estimatedTokens is the
///     arguments and the result or detail in tokens.
ClassMethod Records() As %DynamicArray
{
	Set records = []
	If '..Active() Quit records
	Set count = +$Get(^||OcuTalonBP.Steps("n"))
	Set models = 0
	For i = 1:1:count {
		Set step = ^||OcuTalonBP.Steps(i)
		Set duration = $List(step, 2)
		Set tokens = ..Tokens($List(step, 3))
		If $List(step, 1) = "model" {
			Set models = models + 1
			Set tools = 0
			For j = i + 1:1:count {
				If $List(^||OcuTalonBP.Steps(j), 1) = "model" Quit
				Set tools = tools + 1
			}
			Set label = ..Part("Model request " _ models, ..#MAXLABEL)
			Set summary = ..Part("About " _ tokens _ " tokens sent (an estimate). Reply: " _ $List(step, 4) _ " characters of text, " _ tools _ " tool calls.", ..#MAXSUMMARY)
			Set status = "ok"
			Set kind = "model"
		} Else {
			Set name = $List(step, 4)
			Set status = $List(step, 8)
			Set detail = ..Part($List(step, 9), ..#MAXRESULT)
			Set outcome = $Select(status = "error": "Error: " _ detail, status = "denied": "Denied: " _ detail, 1: "Result: " _ ..Part($List(step, 7), ..#MAXRESULT))
			Set label = ..Part(..LabelFor($List(step, 5), name), ..#MAXLABEL)
			Set summary = ..Cut(..Part(name, ..#MAXNAME) _ ". Inputs: " _ ..Part($List(step, 6), ..#MAXINPUTS) _ ". " _ outcome _ ". About " _ tokens _ " tokens added to the next request (an estimate).", ..#MAXSUMMARY)
			Set kind = "tool"
		}
		Do records.%Push({"kind": (kind), "label": (label), "summary": (summary), "durationMs": (duration), "status": (status), "estimatedTokens": (tokens)})
	}
	Quit records
}

/// Empties the buffer. Does nothing when there is none.
ClassMethod End()
{
	Kill ^||OcuTalonBP.Steps
}

/// The count in characters as a count in tokens, rounded up.
ClassMethod Tokens(chars As %Integer) As %Integer
{
	Quit (+chars + ..#CHARSPERTOKEN - 1) \ ..#CHARSPERTOKEN
}

/// The readable label of a tool (AD-9; Consistency Conventions: Agent step labels): the class parameter STEPLABEL<NAME> of its class,
/// where NAME is the tool's name in upper case with _ and - removed; else the parameter STEPLABEL; else GENERICLABEL. A class that
/// cannot be read gives GENERICLABEL. It never holds an argument or model text, because it comes from a class parameter only.
ClassMethod LabelFor(toolClass As %String, name As %String) As %String
{
	Set label = ""
	Try {
		If toolClass '= "" {
			Set label = $Parameter(toolClass, "STEPLABEL" _ $ZConvert($Translate(name, "_-"), "U"))
			If label = "" Set label = $Parameter(toolClass, "STEPLABEL")
		}
	} Catch {
		Set label = ""
	}
	Quit $Select(label '= "": label, 1: ..#GENERICLABEL)
}

/// The text with its line breaks and other control characters (the C0 and DEL controls, NEL, and the line and paragraph separators) as
/// spaces, so that a part is one line, then redacted (OcuTalon.Bridge.Redact.Text), then cut (Cut). The spaces come first, so that the
/// redactor sees the text as the step shows it (a control character between a key and its value is a space to it), and redaction comes
/// before the cut, so that a cut can never split a secret out of its pattern.
ClassMethod Part(text As %String, max As %Integer) As %String
{
	Set controls = ""
	For code = 0:1:31 {
		Set controls = controls _ $Char(code)
	}
	Set controls = controls _ $Char(127, 133, 8232, 8233)
	Quit ..Cut(##class(OcuTalon.Bridge.Redact).Text($Translate(text, controls, $Justify("", $Length(controls)))), max)
}

/// The text cut to at most max characters: a text over max keeps its first max - 3 characters and ends in "...".
ClassMethod Cut(text As %String, max As %Integer) As %String
{
	If $Length(text) > max Quit $Extract(text, 1, max - 3) _ "..."
	Quit text
}

}
