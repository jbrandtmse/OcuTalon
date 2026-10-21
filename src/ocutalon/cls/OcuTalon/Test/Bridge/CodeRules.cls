/// The code rules of the agent runners and of the code that runs inside AI Hub's callbacks (Story 1.2; AD-6, AD-10). Static: the
/// tests read the source of the compiled OcuTalon classes, drop their comment lines (Test.Bridge.Source), and call nothing in AI Hub.
/// Each scanner is first shown to flag a sample that breaks its rule and to pass one that keeps it.
///   - TestCallbackRule: a tool, toolset, policy or renderer class (a class that extends %AI.Tool, %AI.ToolSet, an %AI.Policy base or
///     %AI.Shell.StreamRenderer) names %AI on no code line except its Class line, and uses no Python, because on build 154 a session
///     call from inside a callback deadlocked the job and a process that runs Python both inside and outside one crashes (AD-6);
///   - TestOnlyRunnersChat: no OcuTalon class outside the Test package, except the runner and its adapter, calls Chat, ChatWithContent,
///     StreamChat, SendChat, SendChatWithContent, RunAgent or ChatComplete (AD-6);
///   - TestRunnerStartsNoJob: the runner and its adapter start no job and use no work manager, because the pool size is the
///     concurrency cap (AD-6);
///   - TestToolCodeScan: ToolCodeClean flags a tool class that runs an operating system command, executes code, loads or compiles
///     classes, uses Python or changes data with SQL (AD-10).
/// ToolCodeClean(class, .problems) is the scan that the live inventory test (Test.Agent.Runners) applies to the provider of each tool.
Class OcuTalon.Test.Bridge.CodeRules Extends %UnitTest.TestCase
{

/// The base classes of the classes that run inside AI Hub's callbacks.
Parameter CALLBACKBASES = "%AI.Tool,%AI.ToolSet,%AI.Policy.Authorization,%AI.Policy.Audit,%AI.Policy.Discovery,%AI.Shell.StreamRenderer";

/// A reference to AI Hub: %AI or EnsLib.AI as a word (the pattern of docker/tests/test-class-rules.sh).
Parameter AIREFERENCE = "(^|[^a-z0-9_])%ai([^a-z0-9]|$)|enslib[._]ai([^a-z0-9]|$)";

/// A use of Python.
Parameter PYTHON = "language\s*=\s*python|%sys\.python|\$system\.python";

/// The calls of the chat family of AI Hub's agent, adapter and provider.
Parameter CHATCALLS = "\.(chat|chatwithcontent|streamchat|sendchat|sendchatwithcontent|runagent|chatcomplete)\(";

/// A job started by a command, or the work manager. The command Job (or J) starts a line or follows a brace or a semicolon.
Parameter JOBS = "(^\s*|[{;]\s*)(job|j)(:[^ ]*)?\s+(\^|\.\.|##|\$|%|[a-z])|workmgr";

/// The classes that may call the chat family: the runner and its adapter.
Parameter CHATTERS = "OcuTalon.Bridge.Operation.AgentRunner,OcuTalon.Bridge.Adapter.Agent";

/// The statements that change data, as a word.
Parameter SQLVERBS = "insert|update|delete|drop|create|alter|truncate";

/// Every tool, toolset, policy and renderer class of OcuTalon refers to %AI only on its Class line, and uses no Python.
Method TestCallbackRule()
{
	Set bad = "Class OcuTalon.Zz.Tool Extends %AI.Tool"_$Char(10)_"{"_$Char(10)_"ClassMethod A()"_$Char(10)_"{"_$Char(10)_$Char(9)_"Set m = ##class(%AI.ToolMgr).%New()"_$Char(10)_"}"_$Char(10)_"}"
	Set bad2 = "Class OcuTalon.Zz.Policy Extends %AI.Policy.Audit"_$Char(10)_"{"_$Char(10)_$Char(9)_"Set a = ##class(EnsLib.AI.Agent.OutboundAdapter).%New()"_$Char(10)_"}"
	Set bad3 = "Class OcuTalon.Zz.Tool Extends %AI.Tool"_$Char(10)_"{"_$Char(10)_"ClassMethod A() [ Language = python ]"_$Char(10)_"{"_$Char(10)_$Char(9)_"return 1"_$Char(10)_"}"_$Char(10)_"}"
	Set bad4 = "Class OcuTalon.Zz.Tool Extends %AI.Tool"_$Char(10)_"{"_$Char(10)_$Char(9)_"Set p = $SYSTEM.Python.Import(""os"")"_$Char(10)_"}"
	Set bad5 = "Class OcuTalon.Zz.Tool Extends %AI.Tool"_$Char(10)_"{"_$Char(10)_$Char(9)_"Set p = ##class(%SYS.Python).Import(""os"")"_$Char(10)_"}"
	Set good = "/// Never calls %AI.ToolMgr."_$Char(10)_"Class OcuTalon.Zz.Tool Extends %AI.Tool"_$Char(10)_"{"_$Char(10)_"ClassMethod A()"_$Char(10)_"{"_$Char(10)_$Char(9)_"// ##class(%AI.ToolMgr).%New()"_$Char(10)_$Char(9)_"; %AI in a comment"_$Char(10)_$Char(9)_"Set text = ""%AIX and MyEnsLib.AIs and BrAIn"""_$Char(10)_$Char(9)_"Quit 1"_$Char(10)_"}"_$Char(10)_"}"
	For sample = bad, bad2, bad3, bad4, bad5 {
		Do $$$AssertTrue(..CallbackProblem(sample) '= "", "the scanner flags a sample that breaks the rule: "_$Extract($Translate(sample, $Char(10, 9), "  "), 1, 100))
	}
	Do $$$AssertEquals(..CallbackProblem(good), "", "and passes a sample that keeps it, comment lines and look-alike words included")

	Set classes = 0
	Set offending = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'OcuTalon.'")
	While result.%Next() {
		Set class = result.%GetData(1)
		If '##class(%Dictionary.CompiledClass).%ExistsId(class) Continue
		If '..IsCallbackClass(class) Continue
		Set classes = classes + 1
		If $$$ISERR(##class(OcuTalon.Test.Bridge.Source).Text(class, .text)) {
			Set offending = offending _ " " _ class _ " (no source)"
			Continue
		}
		Set problem = ..CallbackProblem(text)
		If problem '= "" Set offending = offending _ " " _ class _ " (" _ problem _ ")"
	}
	Do $$$AssertTrue(classes >= 3, "the scan found the tool and toolset classes of OcuTalon: "_classes)
	Do $$$AssertEquals(offending, "", "no tool, toolset, policy or renderer class refers to %AI beyond its Class line, or uses Python")
}

/// No class outside the Test package calls the chat family, except the runner and its adapter.
Method TestOnlyRunnersChat()
{
	Set pattern = ..#CHATCALLS
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"Set r = ..Agent.Chat(session, input)", pattern), "the scanner flags Chat")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"Set r = agent.ChatWithContent(session, content)", pattern), "and ChatWithContent")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"Do agent.StreamChat(session, input, cb)", pattern), "and StreamChat")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"Set sc = ..Adapter.SendChat(text, .r)", pattern), "and SendChat")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"Set sc = adapter.SendChatWithContent(c, .r)", pattern), "and SendChatWithContent")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"Set sc = adapter.RunAgent(goal, .r)", pattern), "and RunAgent")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"Set r = provider.ChatComplete(m, c)", pattern), "and ChatComplete")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"SET R = AGENT.CHAT(S, I)", pattern), "in any case")
	Do $$$AssertTrue('##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"Set channel = msg.ChatRef"_$Char(10)_"/// Calls agent.Chat( in a comment"_$Char(10)_$Char(9)_"; agent.Chat(", pattern), "and passes a property that starts with Chat and comment lines")

	Set scanned = 0
	Set offending = ""
	Set unreadable = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'OcuTalon.' AND NOT Name %STARTSWITH 'OcuTalon.Test.'")
	While result.%Next() {
		Set class = result.%GetData(1)
		If $ListFind($ListFromString(..#CHATTERS), class) Continue
		Set sc = ##class(OcuTalon.Test.Bridge.Source).Text(class, .text)
		If $$$ISERR(sc) {
			If $SYSTEM.Status.GetErrorText(sc) '[ "is a stub name" Set unreadable = unreadable _ " " _ class
			Continue
		}
		Set scanned = scanned + 1
		If ##class(OcuTalon.Test.Bridge.Source).Matches(text, pattern) Set offending = offending _ " " _ class
	}
	Do $$$AssertTrue(scanned > 50, "the scan read the source of the OcuTalon classes: "_scanned)
	Do $$$AssertEquals(unreadable, "", "and every class of the scan has source, except the generated stub classes of the process message tracking, which hold no code")
	Do $$$AssertEquals(offending, "", "no class but the runner and its adapter calls the chat family")
	Set found = 0
	Set position = 0
	Set chatters = $ListFromString(..#CHATTERS)
	While $ListNext(chatters, position, class) {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Source).Text(class, .text), class_" has source")
		If ##class(OcuTalon.Test.Bridge.Source).Matches(text, pattern) Set found = found + 1
	}
	Do $$$AssertEquals(found, 1, "and the scan sees the one class that does call Chat, the adapter")
}

/// The runner and its adapter start no job and use no work manager.
Method TestRunnerStartsNoJob()
{
	Set pattern = ..#JOBS
	Set tab = $Char(9)
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"Job ##class(A.B).Run()", pattern), "the scanner flags the Job command")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"Job ..Run()", pattern), "and Job on a method of the class")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"If x { Job Run^Zz() }", pattern), "and Job inside a block")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"J Run^Zz", pattern), "and its short form")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"Set q = ##class(%SYSTEM.WorkMgr).%New()", pattern), "and the work manager")
	Do $$$AssertTrue('##class(OcuTalon.Test.Bridge.Source).Matches(tab_"Set jobs = ..Jobs(item)"_$Char(10)_"/// Starts no job."_$Char(10)_tab_"// Job ..Run()"_$Char(10)_tab_"Set text = ""the job is kept"""_$Char(10)_tab_"Set n = adapter.Building", pattern), "and passes look-alikes and comment lines")

	Set classes = $ListFromString(..#CHATTERS)
	Set position = 0
	While $ListNext(classes, position, class) {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Source).Text(class, .text), class_" has source")
		Do $$$AssertTrue('##class(OcuTalon.Test.Bridge.Source).Matches(text, pattern), class_" starts no job and uses no work manager")
	}
}

/// ToolCodeClean flags the code of a tool class that runs an operating system command ($ZF), executes code (XECUTE, $XECUTE), uses
/// the class compiler or loader ($SYSTEM.OBJ), uses Python, or changes data with SQL (an INSERT, UPDATE, DELETE, DROP, CREATE, ALTER
/// or TRUNCATE inside embedded SQL or at the start of a string), and passes the fixtures of the product.
Method TestToolCodeScan()
{
	Set tab = $Char(9), lf = $Char(10)
	Set bad = $ListBuild(
		tab_"Set rc = $ZF(-1, ""ls"")",
		tab_"Set rc = $zf(-100, ""/SHELL"", ""ls"")",
		tab_"Xecute code",
		tab_"Set x = $XECUTE(""Quit 1"")",
		tab_"Do $SYSTEM.OBJ.Compile(""A.B"")",
		tab_"Set p = $SYSTEM.Python.Import(""os"")",
		tab_"Set p = ##class(%SYS.Python).Import(""os"")",
		"ClassMethod A() [ Language = python ]",
		tab_"&sql(DELETE FROM A.B WHERE ID = 1)",
		tab_"&sql(INSERT INTO A.B (X) VALUES (1))",
		tab_"&sql("_lf_tab_"  UPDATE A.B SET X = 1"_lf_tab_")",
		tab_"Set st = ""DROP TABLE A.B""",
		tab_"Set st = ""  truncate table A.B""",
		tab_"Set rs = ##class(%SQL.Statement).%ExecDirect(, ""Alter Table A.B ADD C INT"")",
		tab_"Set st = ""CREATE TABLE A.B (X INT)""")
	Set position = 0
	While $ListNext(bad, position, line) {
		Set clean = ..ToolCodeClean("", .problems, line)
		Do $$$AssertEquals(clean, 0, "the scan flags: "_$Translate(line, lf_tab, "  "))
		Do $$$AssertTrue(problems '= "", "and says why: "_problems)
	}
	Set good = "/// Runs $ZF( or XECUTE or DROP in a comment only."_lf_
		"ClassMethod ReadFailedMessages(production As %String = """") As %String"_lf_"{"_lf_
		tab_"// $SYSTEM.OBJ.Load(x)"_lf_
		tab_"; &sql(DELETE FROM A.B)"_lf_
		tab_"Set text = ""{""""items"""":[]}"""_lf_
		tab_"&sql(SELECT ID INTO :id FROM A.B WHERE X = :production)"_lf_
		tab_"Set rs = ##class(%SQL.Statement).%ExecDirect(, ""SELECT COUNT(*) FROM Ens_Util.Log WHERE Text = 'Update the log'"")"_lf_
		tab_"Set created = ""A set was created""  Set x = ""Updated"""_lf_
		tab_"Quit text"_lf_"}"
	Set clean = ..ToolCodeClean("", .problems, good)
	Do $$$AssertEquals(clean, 1, "the scan passes a sample that keeps the rules, with the verbs in comments, as names and inside a longer string: "_problems)
	Do $$$AssertEquals(problems, "", "and has nothing to say")
	Set clean = ..ToolCodeClean("OcuTalon.Tools.WatchFixture", .problems)
	Do $$$AssertEquals(clean, 1, "the Watch fixture is clean: "_problems)
	Set clean = ..ToolCodeClean("OcuTalon.Test.Bridge.ProbeTool", .problems)
	Do $$$AssertEquals(clean, 1, "and so is the probe tool: "_problems)
	Set clean = ..ToolCodeClean("OcuTalon.Zz.NoSuchClass", .problems)
	Do $$$AssertEquals(clean, 0, "a class with no source is not clean")
	Do $$$AssertTrue(problems [ "OcuTalon.Zz.NoSuchClass", "and the problem names it: "_problems)
}

/// 1 when the code of the class passes the rules of a tool class (AD-10): no $ZF, no XECUTE or $XECUTE, no $SYSTEM.OBJ, no Python,
/// and no INSERT, UPDATE, DELETE, DROP, CREATE, ALTER or TRUNCATE inside embedded SQL (&sql) or at the start of a string. problems
/// lists what was found, separated by semicolons; it is empty when the code is clean. A class with no source is not clean. text
/// replaces the source of the class, for the samples of the tests.
ClassMethod ToolCodeClean(class As %String, Output problems As %String, text As %String = "") As %Boolean
{
	Set problems = ""
	If text = "" {
		Set sc = ##class(OcuTalon.Test.Bridge.Source).Text(class, .text)
		If $$$ISERR(sc) || (text = "") {
			Set problems = "the source of "_class_" cannot be read"
			Quit 0
		}
	}
	Set checks = $ListBuild(
		$ListBuild("\$zf\(", "$ZF"),
		$ListBuild("\bxecute\b", "XECUTE"),
		$ListBuild("\$system\.obj\.", "$SYSTEM.OBJ"),
		$ListBuild(..#PYTHON, "Python"),
		$ListBuild("""\s*("_..#SQLVERBS_")\b", "a string that starts with an SQL statement that changes data"))
	Set position = 0
	While $ListNext(checks, position, check) {
		If ##class(OcuTalon.Test.Bridge.Source).Matches(text, $List(check, 1)) Set problems = problems _ $Select(problems = "": "", 1: "; ") _ "uses " _ $List(check, 2)
	}
	Set embedded = ..EmbeddedSql(text)
	For i = 1:1:$Length(embedded, $Char(1)) {
		Set statement = $Piece(embedded, $Char(1), i)
		If $Locate(statement, "(?i)^\s*("_..#SQLVERBS_")\b") Set problems = problems _ $Select(problems = "": "", 1: "; ") _ "runs an embedded SQL statement that changes data"
	}
	Quit problems = ""
}

/// The text of each embedded SQL statement (&sql(...)) in the code lines, separated by $Char(1). A statement ends at the parenthesis
/// that closes the one after &sql.
ClassMethod EmbeddedSql(text As %String) As %String [ Private ]
{
	Set code = ""
	Set lines = ##class(OcuTalon.Test.Bridge.Source).CodeLines(text)
	Set position = 0
	While $ListNext(lines, position, line) {
		Set code = code _ line _ $Char(10)
	}
	Set statements = ""
	Set start = 1
	For {
		Set at = $Locate(code, "(?i)&sql\(", start, end)
		Quit:'at
		Set depth = 1
		Set i = end
		While (i <= $Length(code)) && depth {
			Set char = $Extract(code, i)
			If char = "(" Set depth = depth + 1
			If char = ")" Set depth = depth - 1
			Set i = i + 1
		}
		Set statements = statements _ $Select(statements = "": "", 1: $Char(1)) _ $Extract(code, end, i - 2)
		Set start = i
	}
	Quit statements
}

/// --- helpers ---
/// 1 when the compiled class extends one of the bases of the classes that run in AI Hub's callbacks. A class with no superclass has
/// no %Extends method and is none of them.
ClassMethod IsCallbackClass(class As %String) As %Boolean [ Private ]
{
	If '##class(%Dictionary.CompiledMethod).%ExistsId(class_"||%Extends") Quit 0
	Set is = 0
	Set bases = $ListFromString(..#CALLBACKBASES)
	Set position = 0
	While $ListNext(bases, position, base) {
		If $ClassMethod(class, "%Extends", base) {
			Set is = 1
			Quit
		}
	}
	Quit is
}

/// What a class that runs in a callback may not hold: "" when its code is clean, otherwise the reasons. The Class line is the only
/// code line that may name %AI.
ClassMethod CallbackProblem(text As %String) As %String [ Private ]
{
	Set problems = ""
	Set lines = ##class(OcuTalon.Test.Bridge.Source).CodeLines(text)
	Set refs = 0
	Set position = 0
	While $ListNext(lines, position, line) {
		If $Locate($ZStrip(line, "<W"), "(?i)^class\s") Continue
		If $Locate(line, "(?i)"_..#AIREFERENCE) Set refs = refs + 1
	}
	If refs Set problems = refs_" line(s) refer to %AI"
	If ##class(OcuTalon.Test.Bridge.Source).Matches(text, ..#PYTHON) Set problems = problems _ $Select(problems = "": "", 1: "; ") _ "uses Python"
	Quit problems
}

}
