/// Tests of the step buffer, the step renderer and the step audit policy (Story 1.5; AD-6, AD-9), pure: nothing is sent, no production runs
/// and no model is called. The renderer and the policy are called as AI Hub calls them, with the dynamic objects it gives (measured in
/// Task 0 of the story), and the records are read from the buffer. Every fake secret is built from fragments, so that no file holds a
/// key-like string.
///   - TestRenderer: Start(400), a model response of 20 characters, a tool call with arguments of 40 and a result of 60, and another
///     response give the estimates 100 and 130 tokens (the base, then the base plus what the callbacks got), the durations come from the
///     clock (a model step lasts from the mark that the step before it moved, a tool step included), OnBegin returns an empty string, and
///     with no Start nothing is recorded;
///   - TestAppendRaises: an append that raises (a string over the limit of a string) leaves the buffer as it was, so that its estimates
///     and its records can still be read;
///   - TestAgentStepsOperation: the AgentSteps operation answers an AgentStep with OK and no response, and any other message class with
///     "not implemented" (5003) and no response;
///   - TestRecords: the shape and the wording of the records: a model step counts the tool steps after it and has the status ok; a tool
///     step has the label of its class, the name, the inputs and the result, an estimate of its own and its duration; an error and a
///     denial have their own wording; a step buffer that ended has no records;
///   - TestLabels: the label of a tool is the parameter STEPLABEL<NAME> of its class, else STEPLABEL, else "Running a tool", for the name
///     with _ and - removed and in upper case; a class that does not exist and an empty class give the generic label;
///   - TestAudit: %LogExecution records the arguments as a string and as an object, the class from the metadata, the result_json, the
///     duration, ok and error with the error's own text without its code, and %LogDenial the status denied with the text; a call, a
///     metadata or a result that is not an object raises nothing, returns OK and still records the step;
///   - TestRedactThenCut: a result of 2,000 characters with a key that crosses the cut gives a summary with no part of the key, and
///     every part and the summary stay within their limits.
Class OcuTalon.Test.Bridge.Steps Extends %UnitTest.TestCase
{

Parameter BUFFER = "OcuTalon.Bridge.Adapter.StepBuffer";

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do $ClassMethod(..#BUFFER, "End")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do $ClassMethod(..#BUFFER, "End")
	Quit $$$OK
}

/// The renderer and the policy fill the buffer: two model responses with a tool call between them. The estimate of a request is the base
/// plus the model texts and the tool arguments and results before it, in tokens, rounded up: 400 characters are 100 tokens, 520 are 130.
Method TestRenderer()
{
	Set buffer = ..#BUFFER
	Set renderer = ##class(OcuTalon.Bridge.Adapter.StepRenderer).%New()
	Set audit = ##class(OcuTalon.Bridge.Policy.StepAudit).%New()
	Do renderer.OnMessage({"value": (..Chars(20))})
	Do audit.%LogExecution(..Call("zz_x", ..Chars(40)), ..Meta("OcuTalon.Test.Bridge.StepsNote"), ..Result(..Chars(60)), 250, 1)
	Do $$$AssertEquals($ClassMethod(buffer, "Active"), 0, "with no Start there is no buffer")
	Set records = $ClassMethod(buffer, "Records")
	Do $$$AssertEquals(records.%Size(), 0, "and nothing is recorded")
	Do $$$AssertEquals($ClassMethod(buffer, "Estimates"), "", "and there is no estimate")
	Do $ClassMethod(buffer, "Model", 5)
	Do $ClassMethod(buffer, "Tool", "a", "b", "c", "d", 1, "ok", "")
	Do $$$AssertEquals($ClassMethod(buffer, "Active"), 0, "a direct append does nothing either")

	Do $ClassMethod(buffer, "Start", 400)
	Do $$$AssertEquals($ClassMethod(buffer, "Active"), 1, "Start makes a buffer")
	Do $$$AssertEquals(renderer.OnBegin(), "", "OnBegin returns an empty string, so that the renderer writes nothing and gets no progress calls")
	Hang 0.25
	Do renderer.OnMessage({"value": (..Chars(20))})
	Do $$$AssertEquals($ListToString($ClassMethod(buffer, "Estimates")), "100", "the first model step estimates the base: 400 characters are 100 tokens")
	Hang 0.25
	Do audit.%LogExecution(..Call("zz_x", ..Chars(40)), ..Meta("OcuTalon.Test.Bridge.StepsNote"), ..Result(..Chars(60)), 250, 1)
	Do renderer.OnMessage({"value": (..Chars(5))})
	Do $$$AssertEquals($ListToString($ClassMethod(buffer, "Estimates")), "100,130", "the second adds the 20 characters of text and the 40 and 60 of the tool call: 520 characters are 130 tokens")
	Set records = $ClassMethod(buffer, "Records")
	Do $$$AssertEquals(records.%Size(), 3, "the buffer holds three steps")
	If records.%Size() '= 3 Quit
	Do $$$AssertEquals(records.%Get(0).kind_"|"_records.%Get(1).kind_"|"_records.%Get(2).kind, "model|tool|model", "a model step, a tool step and a model step")
	Do $$$AssertEquals(records.%Get(0).estimatedTokens_"|"_records.%Get(2).estimatedTokens, "100|130", "the records carry the estimates")
	Do $$$AssertEquals(records.%Get(1).estimatedTokens, 25, "and the tool step estimates what it adds: 100 characters are 25 tokens")
	Do $$$AssertTrue(records.%Get(0).durationMs '< 200, "the first model step lasts from the mark that OnBegin set to its message, by the clock: " _ records.%Get(0).durationMs)
	Do $$$AssertTrue(records.%Get(0).durationMs < 5000, "and not longer than it took")
	Do $$$AssertEquals(records.%Get(1).durationMs, 250, "the tool step has the duration that AI Hub measured")
	Do $$$AssertTrue(records.%Get(2).durationMs < 200, "the second model step lasts from the end of the tool step, not from the first model step, which was 0.25 s earlier: " _ records.%Get(2).durationMs)

	Do renderer.OnMessage({"value": ""})
	Do renderer.OnMessage({})
	Do renderer.OnMessage("")
	Do renderer.OnEnd()
	Do renderer.OnFeedback()
	Do renderer.OnChunk("text")
	Set records = $ClassMethod(buffer, "Records")
	Do $$$AssertEquals(records.%Size(), 6, "a response with no text, one with no value and one that is no object are steps with 0 characters, and the other callbacks record nothing")
	If records.%Size() '= 6 Quit
	Do $$$AssertEquals(records.%Get(5).estimatedTokens, 132, "each estimates the 400 characters of the base and the 125 of the texts and the tool call before it: 525 characters are 132 tokens")

	Do $ClassMethod(buffer, "End")
	Do $$$AssertEquals($ClassMethod(buffer, "Active"), 0, "End empties the buffer")
	Set records = $ClassMethod(buffer, "Records")
	Do $$$AssertEquals(records.%Size(), 0, "and there are no records")
	Do $ClassMethod(buffer, "End")
}

/// An append that raises (strings over the limit of a string) leaves the buffer as it was: no step is half added, so the estimates and
/// the records can still be read and the next append counts nothing of the failed one.
Method TestAppendRaises()
{
	Set buffer = ..#BUFFER
	Do $ClassMethod(buffer, "Start", 40)
	Do $ClassMethod(buffer, "Model", 8)
	Set huge = $Justify("", 2000000)
	Set raised = 0
	Try {
		Do $ClassMethod(buffer, "Tool", "zz_x", "OcuTalon.Test.Bridge.StepsNote", huge, huge, 1, "ok", huge)
	} Catch {
		Set raised = 1
	}
	Do $$$AssertTrue(raised, "an append whose strings pass the limit of a string raises")
	Do $$$AssertEquals($ListToString($ClassMethod(buffer, "Estimates")), "10", "the estimates are still read: the base of 40 characters is 10 tokens")
	Set records = $ClassMethod(buffer, "Records")
	Do $$$AssertEquals(records.%Size(), 1, "and so are the records: the failed append added no step")
	Do $ClassMethod(buffer, "Model", 0)
	Do $$$AssertEquals($ListToString($ClassMethod(buffer, "Estimates")), "10,12", "and the next append counts nothing of it: 40 and 8 characters are 12 tokens")
}

/// The AgentSteps operation answers an AgentStep with OK and no response, and any other message class with "not implemented" (5003) and
/// no response. It carries no STUB.
Method TestAgentStepsOperation()
{
	Set class = "OcuTalon.Bridge.Operation.Steps"
	Set host = ##class(Ens.Host).GetShadowInstance("class||" _ class, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of AgentSteps is made")
	If '$IsObject(host) Quit
	Kill response
	Set sc = host.OnMessage(##class(OcuTalon.Bridge.Msg.AgentStep).%New(), .response)
	Do $$$AssertStatusOK(sc, "an AgentStep gets OK")
	Do $$$AssertTrue('$IsObject($Get(response)), "and no response")
	Kill response
	Set sc = host.OnMessage(##class(Ens.StringRequest).%New("x"), .response)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "any other message class gets 'not implemented' (5003)")
	Do $$$AssertTrue('$IsObject($Get(response)), "and no response")
	Do $$$AssertEquals(+$Parameter(class, "STUB"), 0, "the class carries no STUB")
}

/// The records of a buffer: a model step counts the tool steps that follow it before the next model step; a tool step, an error and a
/// denial have their own wording; every record has the six fields.
Method TestRecords()
{
	Set buffer = ..#BUFFER
	Do $ClassMethod(buffer, "Start", 0)
	Do $ClassMethod(buffer, "Model", 12)
	Do $ClassMethod(buffer, "Tool", "zz_steps_note", "OcuTalon.Test.Bridge.StepsNote", "{""topic"":""status""}", "{""note"":""All systems normal."",""topic"":""status""}", 254, "ok", "")
	Do $ClassMethod(buffer, "Tool", "zz_steps_card", "OcuTalon.Test.Bridge.StepsCard", "{""owner"":""locked""}", "", 3, "error", "The card of locked is locked")
	Do $ClassMethod(buffer, "Tool", "zz_gone", "OcuTalon.Test.Bridge.StepsNote", "{}", "", 0, "denied", "Not allowed")
	Do $ClassMethod(buffer, "Model", 0)
	Do $ClassMethod(buffer, "Model", 7)
	Set records = $ClassMethod(buffer, "Records")
	Do $$$AssertEquals(records.%Size(), 6, "six steps")
	If records.%Size() '= 6 Quit
	Set iterator = records.%GetIterator()
	While iterator.%GetNext(.position, .record) {
		Set names = ""
		Set field = ""
		For field = "kind", "label", "summary", "durationMs", "status", "estimatedTokens" {
			Set names = names _ $Select(record.%IsDefined(field): field _ ",", 1: "")
		}
		Do $$$AssertEquals(names, "kind,label,summary,durationMs,status,estimatedTokens,", "record " _ (position + 1) _ " has its six fields")
		Do $$$AssertEquals(record.%GetTypeOf("durationMs") _ "|" _ record.%GetTypeOf("estimatedTokens"), "number|number", "record " _ (position + 1) _ ": the duration and the estimate are numbers")
	}
	Set model = records.%Get(0)
	Do $$$AssertEquals(model.label, "Model request 1", "the first model step")
	Do $$$AssertEquals(model.summary, "About 0 tokens sent (an estimate). Reply: 12 characters of text, 3 tool calls.", "counts the three tool steps after it")
	Do $$$AssertEquals(model.status, "ok", "and is ok")
	Set note = records.%Get(1)
	Do $$$AssertEquals(note.label, "Reading the test note", "the note step has the label of its class")
	Do $$$AssertEquals(note.summary, "zz_steps_note. Inputs: {""topic"":""status""}. Result: {""note"":""All systems normal."",""topic"":""status""}. About 17 tokens added to the next request (an estimate).", "the summary: name, inputs, result and the estimate")
	Do $$$AssertEquals(note.durationMs_"|"_note.status_"|"_note.estimatedTokens, "254|ok|17", "its duration, status and estimate")
	Set card = records.%Get(2)
	Do $$$AssertEquals(card.label, "Reading the test card", "the card step has the label of its tool")
	Do $$$AssertEquals(card.summary, "zz_steps_card. Inputs: {""owner"":""locked""}. Error: The card of locked is locked. About 12 tokens added to the next request (an estimate).", "an error step: the error text takes the place of the result and counts for the estimate")
	Do $$$AssertEquals(card.status, "error", "with the status error")
	Set denied = records.%Get(3)
	Do $$$AssertEquals(denied.summary, "zz_gone. Inputs: {}. Denied: Not allowed. About 4 tokens added to the next request (an estimate).", "a denied step: the denial's text")
	Do $$$AssertEquals(denied.status_"|"_denied.durationMs, "denied|0", "with the status denied")
	Set second = records.%Get(4)
	Do $$$AssertEquals(second.label_"|"_second.summary, "Model request 2|About 34 tokens sent (an estimate). Reply: 0 characters of text, 0 tool calls.", "the second model step: the texts and tool steps before it are in its estimate, none of its own tool steps")
	Do $$$AssertEquals(records.%Get(5).label, "Model request 3", "and the third")
	Do $$$AssertEquals($ListToString($ClassMethod(buffer, "Estimates")), "0,34,34", "the estimates of the model steps, in order")
	Do $$$AssertEquals($ClassMethod(buffer, "Tokens", 0)_"|"_$ClassMethod(buffer, "Tokens", 1)_"|"_$ClassMethod(buffer, "Tokens", 4)_"|"_$ClassMethod(buffer, "Tokens", 5), "0|1|1|2", "a count of characters is a count of tokens at 4 a token, rounded up")
}

/// The label of a tool.
Method TestLabels()
{
	Set buffer = ..#BUFFER
	Set card = "OcuTalon.Test.Bridge.StepsCard"
	Set note = "OcuTalon.Test.Bridge.StepsNote"
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", card, "zz_steps_card"), "Reading the test card", "STEPLABEL<NAME> of the class: the name in upper case, with _ removed")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", card, "zz-steps-card"), "Reading the test card", "and with - removed")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", card, "ZZ_Steps_Card"), "Reading the test card", "and in any case")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", note, "zz_steps_note"), "Reading the test note", "else STEPLABEL of the class")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", note, "zz_other"), "Reading the test note", "for any tool of the class")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", "OcuTalon.Test.Bridge.ProbeTool", "zz_context_probe"), "Running a tool", "else the generic label")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", card, "zz_other"), "Running a tool", "a tool of a class that has only the label of another tool gets the generic label")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", "OcuTalon.Test.Bridge.ZzNoSuchTool", "x"), "Running a tool", "a class that does not exist")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", "", "x"), "Running a tool", "and an empty class")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", "%Library.String", "x"), "Running a tool", "and a class with no label parameter")
}

/// %LogExecution and %LogDenial record the steps, whatever they are given.
Method TestAudit()
{
	Set buffer = ..#BUFFER
	Set audit = ##class(OcuTalon.Bridge.Policy.StepAudit).%New()
	Do $ClassMethod(buffer, "Start", 0)
	Set stringCall = {"id": "c1", "name": "zz_steps_card"}
	Do stringCall.%Set("arguments", "{""owner"":""ops""}")
	Set objectCall = {"id": "c2", "name": "zz_steps_card", "arguments": {"owner": "ops"}}
	Set meta = ..Meta("OcuTalon.Test.Bridge.StepsCard")
	Set result = ..Result("{""card"":""On call: ops""}")
	Do $$$AssertEquals(audit.%LogExecution(stringCall, meta, result, 7, 1), 1, "%LogExecution returns OK")
	Do $$$AssertEquals(audit.%LogExecution(objectCall, meta, result, 8, 1), 1, "also for the arguments as an object")
	Set error = $SYSTEM.Status.Error(5001, "The card of locked is locked")
	Do $$$AssertEquals(audit.%LogExecution(stringCall, meta, "", 9, error), 1, "also for an error status and a result that is null")
	Set denial = $SYSTEM.Status.Error(5001, "This tool needs an approval")
	Do $$$AssertEquals(audit.%LogDenial(objectCall, meta, denial), 1, "%LogDenial returns OK")
	Set records = $ClassMethod(buffer, "Records")
	Do $$$AssertEquals(records.%Size(), 4, "four steps are recorded")
	If records.%Size() '= 4 Quit
	Do $$$AssertEquals(records.%Get(0).summary, "zz_steps_card. Inputs: {""owner"":""ops""}. Result: {""card"":""On call: ops""}. About 10 tokens added to the next request (an estimate).", "the arguments as a string are the JSON")
	Do $$$AssertEquals(records.%Get(1).summary, records.%Get(0).summary, "and the arguments as an object give the same JSON")
	Do $$$AssertEquals(records.%Get(0).label_"|"_records.%Get(0).status_"|"_records.%Get(0).durationMs, "Reading the test card|ok|7", "the label is that of the class from the metadata, the status ok and the duration")
	Do $$$AssertEquals(records.%Get(2).status_"|"_records.%Get(2).durationMs, "error|9", "an error status is recorded as error")
	Do $$$AssertEquals(records.%Get(2).summary, "zz_steps_card. Inputs: {""owner"":""ops""}. Error: The card of locked is locked. About 11 tokens added to the next request (an estimate).", "with the error's own text, not its code or the word ERROR")
	Do $$$AssertEquals(records.%Get(3).status_"|"_records.%Get(3).durationMs, "denied|0", "a denial is recorded as denied")
	Do $$$AssertEquals(records.%Get(3).summary, "zz_steps_card. Inputs: {""owner"":""ops""}. Denied: This tool needs an approval. About 11 tokens added to the next request (an estimate).", "with the text of the denial")

	Do $ClassMethod(buffer, "Start", 0)
	Set raised = ""
	Try {
		Set rc = audit.%LogExecution("", "", "", 3, 1)
		Set rc2 = audit.%LogExecution(5, {}, "x", "", 1)
		Set rc3 = audit.%LogDenial("", "", "")
		Set rc4 = audit.%LogExecution({"name": 7, "arguments": 8}, 9, {"result_json": {"a": 1}}, "abc", 1)
	} Catch exception {
		Set raised = exception.DisplayString()
		Set rc = ""
		Set rc2 = ""
		Set rc3 = ""
		Set rc4 = ""
	}
	Do $$$AssertEquals(raised, "", "a call, a metadata and a result that are not objects raise nothing")
	Do $$$AssertEquals(rc_"|"_rc2_"|"_rc3_"|"_rc4, "1|1|1|1", "and every call returns OK")
	Set records = $ClassMethod(buffer, "Records")
	Do $$$AssertEquals(records.%Size(), 4, "each still records its step")
	If records.%Size() '= 4 Quit
	Do $$$AssertEquals(records.%Get(0).summary, ". Inputs: . Result: . About 0 tokens added to the next request (an estimate).", "with empty strings for what it could not read")
	Do $$$AssertEquals(records.%Get(0).label_"|"_records.%Get(0).status_"|"_records.%Get(0).durationMs, "Running a tool|ok|3", "the generic label")
	Do $$$AssertEquals(records.%Get(2).status, "denied", "a denial with nothing readable is still a denial")
	Do $$$AssertEquals(records.%Get(3).summary, "7. Inputs: 8. Result: {""a"":1}. About 2 tokens added to the next request (an estimate).", "a number is read as text, an object where text is expected is JSON, and a duration that is no number is 0")
}

/// A result of 2,000 characters with a key that crosses the cut at 400 characters: the redactor runs first, so no part of the key is in
/// the summary; every part is within its limit and the summary within 1,000 characters.
Method TestRedactThenCut()
{
	Set buffer = ..#BUFFER
	Set audit = ##class(OcuTalon.Bridge.Policy.StepAudit).%New()
	Set key = ##class(OcuTalon.Test.Bridge.StepsNote).Secret("apiKey", "result")
	Set text = ..Chars(392) _ key _ ..Chars(1500)
	Do $$$AssertEquals($Length(text), 392 + $Length(key) + 1500, "the result is over 1,900 characters, and the key starts at character 393")
	Do $ClassMethod(buffer, "Start", 0)
	Do audit.%LogExecution(..Call("zz_steps_note", "{}"), ..Meta("OcuTalon.Test.Bridge.StepsNote"), ..Result(text), 1, 1)
	Set records = $ClassMethod(buffer, "Records")
	Set summary = records.%Get(0).summary
	Do $$$AssertNotTrue(summary [ $Extract(key, 1, 4), "no part of the key is in the summary: the first four characters are not")
	Do $$$AssertNotTrue(summary [ $Extract(key, 1, 7), "nor the first seven")
	Do $$$AssertTrue(summary [ (..Chars(392) _ "[reda..."), "the redacted text is what is cut: 392 characters, then the marker cut after 5 characters, and the cut ends in ...")
	Do $$$AssertTrue($Length(summary) '> 1000, "the summary is within 1,000 characters: " _ $Length(summary))

	Set long = $Translate($Justify("", 200), " ", "n")
	Set huge = ##class(OcuTalon.Test.Bridge.StepsNote).Secret("password", "arg")
	Do $ClassMethod(buffer, "Start", 0)
	Set call = ..Call(long, $Translate($Justify("", 5000), " ", "i"))
	Do audit.%LogExecution(call, ..Meta("OcuTalon.Test.Bridge.StepsNote"), ..Result($Translate($Justify("", 5000), " ", "r")), 1, 1)
	Do audit.%LogExecution(call, ..Meta("OcuTalon.Test.Bridge.StepsNote"), "", 1, $SYSTEM.Status.Error(5001, $Translate($Justify("", 5000), " ", "e")))
	Set records = $ClassMethod(buffer, "Records")
	Set result = records.%Get(0).summary
	Do $$$AssertTrue($Length(result) '> 1000, "a tool step with a name of 200 characters, inputs of 5,000 and a result of 5,000 has a summary within 1,000: " _ $Length(result))
	Do $$$AssertEquals($Piece(result, ". Inputs: ", 1), $Extract(long, 1, 61) _ "...", "the name is cut to 64 characters, ending in ...")
	Set inputs = $Piece($Piece(result, ". Inputs: ", 2), ". Result: ", 1)
	Do $$$AssertEquals($Length(inputs), 300, "the inputs are cut to 300 characters")
	Do $$$AssertEquals($Extract(inputs, 298, 300), "...", "ending in ...")
	Set outcome = $Piece($Piece(result, ". Result: ", 2), ". About ", 1)
	Do $$$AssertEquals($Length(outcome), 400, "the result is cut to 400 characters")
	Set errorSummary = records.%Get(1).summary
	Set detail = $Piece($Piece(errorSummary, ". Error: ", 2), ". About ", 1)
	Do $$$AssertEquals($Length(detail), 400, "and so is an error text")
	Do $$$AssertEquals($Length($ClassMethod(buffer, "Part", $Translate($Justify("", 300), " ", "l"), 200)), 200, "a part is cut to its limit")
	Do $$$AssertEquals($Extract($ClassMethod(buffer, "Part", $Translate($Justify("", 300), " ", "l"), 200), 198, 200), "...", "and ends in ...")
	Do $$$AssertEquals($ClassMethod(buffer, "Part", "short", 200), "short", "a short part is not cut")
	Do $$$AssertEquals($ClassMethod(buffer, "Part", "line" _ $Char(13, 10) _ "break", 200), "line  break", "and a line break becomes spaces: a part is one line")
	Do $$$AssertEquals($ClassMethod(buffer, "Part", "esc" _ $Char(27, 0, 133, 8232) _ "end", 200), "esc    end", "and so do the other control characters: the escape, the null, the next-line and the line separator")
	Do $$$AssertEquals($ClassMethod(buffer, "Part", "a password=" _ huge, 200), "a password=[redacted]", "a part passes the redactor")
}

/// --- helpers ---
/// n characters of text.
ClassMethod Chars(n As %Integer) As %String [ Private ]
{
	Quit $Translate($Justify("", n), " ", "a")
}

/// A call as AI Hub gives it to the audit policy: {"id","name","arguments"} with the arguments as a JSON string.
ClassMethod Call(name As %String, arguments As %String) As %DynamicObject [ Private ]
{
	Set call = {"id": "toolu_zz_1", "name": (name)}
	Do call.%Set("arguments", arguments)
	Quit call
}

/// The metadata of a tool: its requirements, origin_class and requires_auth.
ClassMethod Meta(class As %String) As %DynamicObject [ Private ]
{
	Quit {"ReadOnly": "1", "origin_class": (class), "requires_auth": false}
}

/// The result of a tool: {"tool_name","result_json","display_text"}.
ClassMethod Result(json As %String) As %DynamicObject [ Private ]
{
	Set result = {"tool_name": "zz_x", "display_text": null}
	Do result.%Set("result_json", json)
	Quit result
}

}
