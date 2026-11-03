/// Tests of the constants that the CI mock keys on (Story 0.6, matrix row 11): the agents' mock keys and models, the names
/// of the built-in tools and the first line and keys of the compaction prompt. Nothing is written anywhere and no model is
/// called.
///   - TestAgents: each agent extends %AI.Agent, has MODEL claude-haiku-5-5 and its own MOCKKEY (the template-token check
///     on the INSTRUCTIONS is in OcuTalon.Test.Agent.Instructions);
///   - TestToolNames: the twelve release-1 tool names are distinct snake_case values, and RELEASE1 lists exactly them;
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

/// OcuTalon.Tools.Names holds 12 distinct snake_case values, and RELEASE1 lists exactly them, comma-separated.
Method TestToolNames()
{
	Set statement = ##class(%SQL.Statement).%New()
	Do $$$AssertStatusOK(statement.%Prepare("SELECT Name FROM %Dictionary.CompiledParameter WHERE parent = ? AND Name <> ? ORDER BY Name"), "the parameters are listed")
	Set result = statement.%Execute("OcuTalon.Tools.Names", "RELEASE1")
	Set count = 0
	Set names = ""
	While result.%Next() {
		Set value = $Parameter("OcuTalon.Tools.Names", result.%Get("Name"))
		Set count = count + 1
		Do $$$AssertTrue(value ? 1.L.(1"_"1.L), result.%Get("Name")_" is snake_case: "_value)
		Do $$$AssertTrue('$ListFind(names, value), value_" is distinct")
		Set names = names _ $ListBuild(value)
	}
	Do $$$AssertEquals(count, 12, "there are 12 tool names")
	Set release = $ListFromString($Parameter("OcuTalon.Tools.Names", "RELEASE1"))
	Do $$$AssertEquals($ListLength(release), 12, "RELEASE1 lists 12 names")
	Set missing = ""
	Set position = 0
	While $ListNext(release, position, name) {
		If '$ListFind(names, name) Set missing = missing _ " " _ name
	}
	Do $$$AssertEquals(missing, "", "every name in RELEASE1 is a parameter")
	Do $$$AssertEquals($Parameter("OcuTalon.Tools.Names", "CHECKSTATUS"), "check_status", "the status tool is check_status")
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
