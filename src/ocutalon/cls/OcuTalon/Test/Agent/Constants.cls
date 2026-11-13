/// Tests of the constants that the CI mock keys on (Story 0.6, matrix row 11): the agents' mock keys and models, the names
/// of the built-in tools and the first line and keys of the compaction prompt. Nothing is written anywhere and no model is
/// called.
///   - TestAgents: each agent extends %AI.Agent, has MODEL claude-haiku-5-5 and its own MOCKKEY (the template-token check
///     on the INSTRUCTIONS is in OcuTalon.Test.Agent.Instructions);
///   - TestToolNames: the tool names are 22 distinct snake_case values (the twelve release-1 names and ten names of later steps), and
///     RELEASE1 lists exactly the twelve;
///   - TestCompactionPrompt: the prompt is ASCII, starts with the prefix and names the seven keys of the summary.
Class OcuTalon.Test.Agent.Constants Extends %UnitTest.TestCase
{

/// MOCKKEY is triage, diagnosis and chat, one per agent; each agent extends %AI.Agent and has MODEL claude-haiku-5-5.
Method TestAgents()
{
	Set keys = ""
	Set expected = $ListBuild("OcuTalon.Agent.Triage", "triage", "OcuTalon.Agent.Diagnosis", "diagnosis", "OcuTalon.Agent.Chat", "chat")
	For i = 1:2:5 {
		Set class = $List(expected, i)
		Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(class), class_" is compiled")
		Do $$$AssertTrue($ClassMethod(class, "%Extends", "%AI.Agent"), class_" extends %AI.Agent")
		Do $$$AssertEquals($Parameter(class, "MODEL"), "claude-haiku-5-5", class_" has MODEL claude-haiku-5-5")
		Do $$$AssertEquals($Parameter(class, "MOCKKEY"), $List(expected, i + 1), class_" has MOCKKEY "_$List(expected, i + 1))
		Set keys = keys _ $ListBuild($Parameter(class, "MOCKKEY"))
	}
	Do $$$AssertTrue(($List(keys, 1) '= $List(keys, 2)) && ($List(keys, 1) '= $List(keys, 3)) && ($List(keys, 2) '= $List(keys, 3)), "the keys are distinct")
}

/// OcuTalon.Tools.Names holds 22 distinct snake_case values: the 12 of release 1, PROPOSEPERSONA, DIGESTTOOLS (Story 17.6), the four memory names,
/// DOCUMENTS (Story 19.4), INCIDENTSUMMARY (Story 23.6), PROPOSEFIX (Story 23.2) and CALLMCPTOOL (Story 22.3). RELEASE1 lists exactly the 12 of
/// release 1, comma-separated, and none of the ten later names; MEMORYTOOLS lists the four memory names.
Method TestToolNames()
{
	Set statement = ##class(%SQL.Statement).%New()
	Do $$$AssertStatusOK(statement.%Prepare("SELECT Name FROM %Dictionary.CompiledParameter WHERE parent = ? AND Name <> ? AND Name <> ? ORDER BY Name"), "the parameters are listed")
	Set result = statement.%Execute("OcuTalon.Tools.Names", "RELEASE1", "MEMORYTOOLS")
	Set count = 0
	Set names = ""
	While result.%Next() {
		Set value = $Parameter("OcuTalon.Tools.Names", result.%Get("Name"))
		Set count = count + 1
		Do $$$AssertTrue(value ? 1.L.(1"_"1.L), result.%Get("Name")_" is snake_case: "_value)
		Do $$$AssertTrue('$ListFind(names, value), value_" is distinct")
		Set names = names _ $ListBuild(value)
	}
	Do $$$AssertEquals(count, 22, "there are 22 tool names (Story 22.3 adds call_mcp_tool)")
	Set release = $ListFromString($Parameter("OcuTalon.Tools.Names", "RELEASE1"))
	Do $$$AssertEquals($ListLength(release), 12, "RELEASE1 lists 12 names")
	Do $$$AssertEquals($ListFind(release, $Parameter("OcuTalon.Tools.Names", "DIGESTTOOLS")), 0, "and send_digest of step 2 is not among them")
	Set missing = ""
	Set position = 0
	While $ListNext(release, position, name) {
		If '$ListFind(names, name) Set missing = missing _ " " _ name
	}
	Do $$$AssertEquals(missing, "", "every name in RELEASE1 is a parameter")
	Do $$$AssertEquals($Parameter("OcuTalon.Tools.Names", "DIGESTTOOLS"), "send_digest", "the digest tool is send_digest")
	Do $$$AssertEquals($Parameter("OcuTalon.Tools.Names", "INCIDENTSUMMARY"), "incident_summary", "the incident summary tool is incident_summary")
	Do $$$AssertEquals($ListFind(release, $Parameter("OcuTalon.Tools.Names", "INCIDENTSUMMARY")), 0, "and it is not in RELEASE1")
	Do $$$AssertEquals($Parameter("OcuTalon.Tools.Names", "CALLMCPTOOL"), "call_mcp_tool", "the governed MCP proxy tool is call_mcp_tool")
	Do $$$AssertTrue('$ListFind(release, "call_mcp_tool"), "RELEASE1 does not list call_mcp_tool")
	Do $$$AssertEquals($Parameter("OcuTalon.Tools.Names", "PROPOSEFIX"), "propose_fix", "the fix tool is propose_fix")
	Do $$$AssertTrue('$ListFind(release, "propose_fix"), "RELEASE1 does not list propose_fix")
	Do $$$AssertEquals($Parameter("OcuTalon.Tools.Names", "CHECKSTATUS"), "check_status", "the status tool is check_status")
	Do $$$AssertEquals($Parameter("OcuTalon.Tools.Names", "PROPOSEPERSONA"), "propose_persona", "the persona proposal tool is propose_persona")
	Do $$$AssertTrue('$ListFind(release, "propose_persona"), "RELEASE1 does not list propose_persona")
	Do $$$AssertEquals($Parameter("OcuTalon.Tools.Names", "SAVEMEMORY"), "save_memory", "the memory save tool is save_memory")
	Do $$$AssertEquals($Parameter("OcuTalon.Tools.Names", "SEARCHMEMORIES"), "search_memories", "the memory search tool is search_memories")
	Do $$$AssertEquals($Parameter("OcuTalon.Tools.Names", "LISTMEMORIES"), "list_memories", "the memory list tool is list_memories")
	Do $$$AssertEquals($Parameter("OcuTalon.Tools.Names", "FORGETMEMORY"), "forget_memory", "the memory forget tool is forget_memory")
	Do $$$AssertEquals($Parameter("OcuTalon.Tools.Names", "DOCUMENTS"), "documents", "the documents tool is documents")
	Do $$$AssertTrue('$ListFind(release, "documents"), "RELEASE1 does not list documents")
	Do $$$AssertTrue('$ListFind(release, "save_memory") && '$ListFind(release, "search_memories") && '$ListFind(release, "list_memories") && '$ListFind(release, "forget_memory"), "RELEASE1 does not list the memory names")
	Do $$$AssertEquals($Parameter("OcuTalon.Tools.Names", "MEMORYTOOLS"), "save_memory,search_memories,list_memories,forget_memory", "MEMORYTOOLS lists the four memory names")
}

/// Compaction.Prompt() is ASCII, its first line starts with OCUTALON-COMPACTION-V1, and it names the seven keys of the
/// summary: user_goals, constraints, decisions, facts_learned, tool_actions, open_questions and next_steps.
Method TestCompactionPrompt()
{
	Set prompt = ##class(OcuTalon.Bridge.Compaction).Prompt()
	Do $$$AssertTrue(prompt '= "", "the prompt is read")
	Set bad = ""
	For i = 1:1:$Length(prompt) {
		Set code = $Ascii(prompt, i)
		If (code > 126) || ((code < 32) && (code '= 10)) Set bad = bad _ " " _ code
	}
	Do $$$AssertEquals(bad, "", "the prompt holds only ASCII printable characters and line feeds")
	Set first = $Piece(prompt, $Char(10), 1)
	Do $$$AssertEquals($Extract(first, 1, $Length(##class(OcuTalon.Bridge.Compaction).#PREFIX)), ##class(OcuTalon.Bridge.Compaction).#PREFIX, "the first line starts with the prefix")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Compaction).#PREFIX, "OCUTALON-COMPACTION-V1", "the prefix is OCUTALON-COMPACTION-V1")
	Do $$$AssertTrue($Length(prompt, $Char(10)) > 5, "the prompt has several lines")
	For key = "user_goals", "constraints", "decisions", "facts_learned", "tool_actions", "open_questions", "next_steps" {
		Do $$$AssertTrue(prompt [ ("""" _ key _ """"), "the prompt names "_key)
	}
}

}
