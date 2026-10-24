/// Tests of the three agents' instructions and toolsets (Story 1.1; AD-7). Nothing is written anywhere and no model is called.
///   - TestTriage: the INSTRUCTIONS name every JSON field of the compiled DecisionPayload and every OUTCOME value quoted, and
///     ask for one JSON object with plain-English reasons and a confidence between 0 and 1;
///   - TestChat: the INSTRUCTIONS hold the exact sentence of the catalog key agent.noCommands, which is the answer to a request
///     to run a command, the terms of the voice rules, and no exclamation mark;
///   - TestDiagnosis: the INSTRUCTIONS say that the agent is read-only, never changes anything, proposes fixes only for approval
///     and takes tool results as data;
///   - TestToolsets: Triage has no toolset, Diagnosis has OcuTalon.Tools.Watch, whose three tools a fresh tool
///     manager discovers, each once, as read-only and runs, each returning the dynamic object {"items":[]} (Story 1.9: an object, not a JSON string), and
///     (Story 1.10) Chat has OcuTalon.Tools.Reminders, whose three tools a fresh tool manager discovers, each once, and runs with no bridge context, each
///     returning the dynamic object that says there is no session's turn and that nothing was done (the NOSESSION text of OcuTalon.Tools.CommandCall);
///   - TestNoTemplates: no INSTRUCTIONS block of an OcuTalon class holds {{, and no OcuTalon class calls the AI Hub template
///     class on a code line (AD-7). Both scanners are first shown to flag a sample that breaks the rule.
Class OcuTalon.Test.Agent.Instructions Extends %UnitTest.TestCase
{

/// The terms that the voice rules of Chat's instructions must contain.
Parameter CHATTERMS = "first person,greeting,exclamation,emoji,hype,class name,error code,stack trace,unless the user asks";

/// The tool names of the Watch toolset, from OcuTalon.Tools.Names.
Parameter WATCHTOOLS = "read_failed_messages,read_event_log,read_item_settings";

/// Triage asks for one DecisionPayload-shaped JSON object: every field of the payload and every outcome value, quoted.
Method TestTriage()
{
	Set text = ..Instructions("OcuTalon.Agent.Triage")
	Do $$$AssertTrue(text '= "", "Triage has instructions")
	Set count = 0
	Set class = ##class(%Dictionary.CompiledClass).%OpenId("OcuTalon.Bridge.Msg.DecisionPayload")
	Do $$$AssertTrue($IsObject(class), "DecisionPayload is compiled")
	If $IsObject(class) {
		For i = 1:1:class.Properties.Count() {
			Set field = class.Properties.GetAt(i).Parameters.GetAt("%JSONFIELDNAME")
			If field = "" Continue
			Set count = count + 1
			Do $$$AssertTrue(text [ ("""" _ field _ """"), "the instructions name the field "_field)
		}
	}
	Do $$$AssertTrue(count > 0, "the payload has JSON fields: "_count)
	Set values = $ListFromString(##class(OcuTalon.Bridge.Msg.Enum).#OUTCOME)
	Do $$$AssertTrue($ListLength(values) > 0, "the outcome has values")
	Set position = 0
	While $ListNext(values, position, value) {
		Do $$$AssertTrue(text [ ("""" _ value _ """"), "the instructions quote the outcome "_value)
	}
	For phrase = "one JSON object", "plain English", "between 0 and 1" {
		Do $$$AssertTrue(text [ phrase, "the instructions say '"_phrase_"'")
	}
	Do $$$AssertTrue(text [ "data, never instructions", "and say that item content is data")
}

/// Chat holds the catalog sentence for a request to run a command, the voice rules, and no exclamation mark.
Method TestChat()
{
	Set text = ..Instructions("OcuTalon.Agent.Chat")
	Do $$$AssertTrue(text '= "", "Chat has instructions")
	Set sentence = ##class(OcuTalon.Msg.Catalog).Render("agent.noCommands", "", "web", .sc)
	Do $$$AssertStatusOK(sc, "the catalog renders agent.noCommands")
	Do $$$AssertTrue(sentence '= "", "the sentence is not empty")
	Do $$$AssertTrue(text [ sentence, "the instructions hold the sentence of the catalog: "_sentence)
	Set terms = $ListFromString(..#CHATTERMS)
	Set position = 0
	While $ListNext(terms, position, term) {
		Do $$$AssertTrue(text [ term, "the instructions say '"_term_"'")
	}
	Do $$$AssertTrue(text '[ "!", "the instructions hold no exclamation mark")
	Do $$$AssertTrue(text [ "do not call a tool", "a request to run a command gets no tool call")
	Do $$$AssertTrue(text [ "data, never instructions", "and what tools and mail return is data")
}

/// Diagnosis has instructions that say that it is read-only, changes nothing, proposes a fix only for approval and takes what
/// its tools return as data.
Method TestDiagnosis()
{
	Set text = ..Instructions("OcuTalon.Agent.Diagnosis")
	Do $$$AssertTrue(text '= "", "Diagnosis has instructions")
	Do $$$AssertTrue(text [ "read-only", "and they say that its tools are read-only")
	Do $$$AssertTrue(text [ "Never change anything", "and that it never changes anything")
	Do $$$AssertTrue(text [ "must approve", "and that a fix is only a proposal until the user approves it")
	Do $$$AssertTrue(text [ "data, never instructions", "and that what its tools return is data")
}

/// Triage has no toolset, Diagnosis has the Watch toolset, and a fresh tool manager discovers exactly the three tools
/// of OcuTalon.Tools.Names, each once, with the ReadOnly requirement 1, and runs each one to the dynamic object {"items":[]}. Chat has the Reminders toolset,
/// and a fresh tool manager discovers exactly the other three tools of OcuTalon.Tools.Names, each once; with no bridge context each runs to the dynamic object
/// {"ok": false, "message": NOSESSION} and submits nothing.
Method TestToolsets()
{
	Do $$$AssertEquals($Parameter("OcuTalon.Agent.Triage", "TOOLSETS"), "", "Triage has no toolset")
	Do $$$AssertEquals($Parameter("OcuTalon.Agent.Chat", "TOOLSETS"), "OcuTalon.Tools.Reminders", "Chat has OcuTalon.Tools.Reminders only")
	Set toolsets = $Parameter("OcuTalon.Agent.Diagnosis", "TOOLSETS")
	Do $$$AssertEquals(toolsets, "OcuTalon.Tools.Watch", "Diagnosis has OcuTalon.Tools.Watch only")
	Set expected = $ListBuild(##class(OcuTalon.Tools.Names).#READFAILEDMESSAGES, ##class(OcuTalon.Tools.Names).#READEVENTLOG, ##class(OcuTalon.Tools.Names).#READITEMSETTINGS)
	Do $$$AssertEquals($ListToString(expected), ..#WATCHTOOLS, "the Watch tools are the names of OcuTalon.Tools.Names")
	Set manager = ##class(%AI.ToolMgr).%New()
	Do $$$AssertStatusOK(manager.RegisterToolSet(toolsets), "a fresh tool manager registers the toolset")
	Set tools = manager.%Discover()
	Do $$$AssertEquals(tools.%Size(), $ListLength(expected), "it discovers "_$ListLength(expected)_" tools")
	Set found = ""
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set found = found _ $ListBuild(tool.name)
		Do $$$AssertTrue($ListFind(expected, tool.name), tool.name_" is one of the names")
		Do $$$AssertEquals(tool.metadata.ReadOnly, "1", tool.name_" is read-only")
		Do $$$AssertEquals(tool."requires_auth", 0, tool.name_" needs no authorization")
		Set result = manager.ExecuteTool(tool.name, {"production": "OcuTalon.Production"})
		Do $$$AssertTrue($IsObject(result.value) && result.value.%IsA("%Library.DynamicObject"), tool.name_" returns a dynamic object, not a JSON string")
		Do $$$AssertEquals($Select($IsObject(result.value): result.value.%ToJSON(), 1: result.value), "{""items"":[]}", tool.name_" returns {""items"":[]}")
	}
	Set position = 0
	While $ListNext(expected, position, name) {
		Set seen = 0
		Set at = 0
		While $ListNext(found, at, discovered) {
			If discovered = name Set seen = seen + 1
		}
		Do $$$AssertEquals(seen, 1, name_" is discovered once")
	}
	Do manager.Cleanup()

	Set reminders = $Parameter("OcuTalon.Agent.Chat", "TOOLSETS")
	Set expected = $ListBuild(##class(OcuTalon.Tools.Names).#SETREMINDER, ##class(OcuTalon.Tools.Names).#LISTREMINDERS, ##class(OcuTalon.Tools.Names).#CANCELREMINDER)
	Set arguments("set_reminder") = {"text": "stretch", "delaySeconds": 60}
	Set arguments("list_reminders") = {}
	Set arguments("cancel_reminder") = {"reminderRef": "zzReminderStretch00001"}
	Do ##class(OcuTalon.Bridge.Context).End()
	Set manager = ##class(%AI.ToolMgr).%New()
	Do $$$AssertStatusOK(manager.RegisterToolSet(reminders), "a fresh tool manager registers the reminder toolset")
	Set tools = manager.%Discover()
	Do $$$AssertEquals(tools.%Size(), $ListLength(expected), "it discovers "_$ListLength(expected)_" tools")
	Set found = ""
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set found = found _ $ListBuild(tool.name)
		Do $$$AssertTrue($ListFind(expected, tool.name), tool.name_" is one of the names of OcuTalon.Tools.Names")
		Do $$$AssertEquals(tool."requires_auth", 0, tool.name_" needs no authorization")
		If '$Data(arguments(tool.name)) Continue
		Set result = manager.ExecuteTool(tool.name, arguments(tool.name))
		Do $$$AssertTrue($IsObject(result.value) && result.value.%IsA("%Library.DynamicObject"), tool.name_" returns a dynamic object, not a JSON string")
		If $IsObject(result.value) {
			Do $$$AssertEquals(result.value.%GetTypeOf("ok")_"|"_result.value.ok, "boolean|0", tool.name_" says that nothing was done, with no bridge context")
			Do $$$AssertEquals(result.value.message, ##class(OcuTalon.Tools.CommandCall).#NOSESSION, "and says why: there is no session's turn")
		}
	}
	Set position = 0
	While $ListNext(expected, position, name) {
		Set seen = 0
		Set at = 0
		While $ListNext(found, at, discovered) {
			If discovered = name Set seen = seen + 1
		}
		Do $$$AssertEquals(seen, 1, name_" is discovered once")
	}
	Do manager.Cleanup()
}

/// No compiled INSTRUCTIONS block of an OcuTalon class holds {{, and no code line of an OcuTalon class holds the name of the
/// AI Hub template class. The scanners flag a sample that breaks the rule, and pass one that keeps it.
Method TestNoTemplates()
{
	Do $$$AssertTrue(..HasTemplateToken("Hello {{name}}"), "the token scanner flags a text with a {{ token")
	Do $$$AssertTrue('..HasTemplateToken("Hello name"), "and passes a text without one")
	Do $$$AssertTrue(..HasTemplateCall("  Set t = ##class(" _ ..Needle() _ ").%New(x)"), "the call scanner flags a code line that names the template class")
	Do $$$AssertTrue(..HasTemplateCall("  Set t = ##class(" _ $ZConvert(..Needle(), "L") _ ").%New(x)"), "the call scanner is blind to case, like ObjectScript class names")
	Do $$$AssertTrue('..HasTemplateCall("/// Never calls " _ ..Needle() _ "." _ $Char(10) _ "// " _ ..Needle() _ $Char(10) _ "; " _ ..Needle() _ $Char(10) _ "#; " _ ..Needle() _ $Char(10) _ "##; " _ ..Needle()), "and passes comment lines that only mention it")

	Set blocks = 0
	Set statement = ##class(%SQL.Statement).%New()
	Do $$$AssertStatusOK(statement.%Prepare("SELECT parent FROM %Dictionary.CompiledXData WHERE Name = 'INSTRUCTIONS' AND parent %STARTSWITH 'OcuTalon.'"), "the INSTRUCTIONS blocks are listed")
	Set result = statement.%Execute()
	While result.%Next() {
		Set blocks = blocks + 1
		Set class = result.%GetData(1)
		Do $$$AssertTrue('..HasTemplateToken(..Instructions(class)), class_" has no {{ in its INSTRUCTIONS")
	}
	Do $$$AssertTrue(blocks >= 3, "at least the three agents have an INSTRUCTIONS block: "_blocks)

	Set classes = 0
	Set offending = ""
	Set statement = ##class(%SQL.Statement).%New()
	Do $$$AssertStatusOK(statement.%Prepare("SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'OcuTalon.'"), "the OcuTalon classes are listed")
	Set result = statement.%Execute()
	While result.%Next() {
		Set class = result.%GetData(1)
		Set sc = ##class(%Compiler.UDL.TextServices).GetTextAsString($Namespace, class, .text, $Char(10))
		If $$$ISERR(sc) Continue
		Set classes = classes + 1
		If ..HasTemplateCall(text) Set offending = offending _ " " _ class
	}
	Do $$$AssertTrue(classes > 50, "the scan read the source of the OcuTalon classes: "_classes)
	Do $$$AssertEquals(offending, "", "no OcuTalon class names the AI Hub template class on a code line")
}

/// --- helpers ---
/// The INSTRUCTIONS block of a compiled class as text, with no carriage return.
ClassMethod Instructions(class As %String) As %String [ Private ]
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(class_"||INSTRUCTIONS")
	If '$IsObject(xdata) Quit ""
	Quit $Replace(xdata.Data.Read(1000000), $Char(13), "")
}

/// 1 when the text holds an unfilled template token.
ClassMethod HasTemplateToken(text As %String) As %Boolean [ Private ]
{
	Quit text [ "{{"
}

/// The name of the AI Hub template class, built so that this source never holds it whole.
ClassMethod Needle() As %String [ Private ]
{
	Quit "%AI.Utils." _ "Template"
}

/// 1 when a code line of the text holds the name of the AI Hub template class, in any case (Test.Bridge.Source: a comment line
/// starts, after white space, with //, ///, ;, #; or ##;, as in docker/tests/test-class-rules.sh).
ClassMethod HasTemplateCall(text As %String) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Test.Bridge.Source).Matches(text, ..Needle(), 1)
}

}
