/// The code rules of the agent runners and of the code that runs inside AI Hub's callbacks (Story 1.2; AD-6, AD-10). Static: the
/// tests read the source of the compiled OcuTalon classes, drop their comment lines (Test.Bridge.Source), and call nothing in AI Hub.
/// Each scanner is first shown to flag a sample that breaks its rule and to pass one that keeps it.
///   - TestCallbackRule: a tool, toolset, policy or renderer class (a class that extends %AI.Tool, %AI.ToolSet, an %AI.Policy base or
///     %AI.Shell.StreamRenderer), and a class whose methods they call (CALLBACKHELPERS: the step buffer), names %AI on no code line except
///     its Class line, and uses no Python, because on build 154 a session
///     call from inside a callback deadlocked the job and a process that runs Python both inside and outside one crashes (AD-6);
///   - TestOnlyRunnersChat: no OcuTalon class outside the Test package, except the runner and its adapter, calls Chat, ChatWithContent,
///     StreamChat, StreamChatWithContent, SendChat, SendChatWithContent, RunAgent, ChatComplete, StreamChatComplete or an agent's Run
///     (AD-6);
///   - TestRunnerStartsNoJob: the runner and its adapter start no job and use no work manager, because the pool size is the
///     concurrency cap (AD-6);
///   - TestToolCodeScan: ToolCodeClean flags a tool class that runs an operating system command, executes code, loads or compiles
///     classes, uses Python or changes data with SQL (AD-10);
///   - TestSessionsOnlyThroughTheComposer: no OcuTalon class outside the Test package, except the adapter, creates, resumes or opens
///     an AI session on an agent, or calls AI Hub's adapter methods that create one from its SessionConfig setting, so that every
///     session gets the config that the adapter composes (AD-7);
///   - TestOnlyTheRunnerWritesLinks (Story 1.8; AD-6, AD-33): no OcuTalon class outside the Test package, except ConversationLink, the adapter and
///     Decide, names the link class (as a class, as the table, or by the globals that hold its rows and its lock); Decide calls Lock and Unlock of it
///     and nothing else, a system method such as %New or %DeleteId included; the adapter, the only caller of Point and SessionOf, calls those two and
///     Lock and Unlock; no line of either names the link class, its table or its globals outside such a call; and Point is the only writer of the
///     link class;
///   - TestSourceHelper: the helper that the scans share (Test.Bridge.Source) drops comment lines in each of their forms, keeps a
///     line with a trailing comment, and matches in any case, also as plain text.
/// ToolCodeClean(class, .problems) is the scan that the live inventory test (Test.Agent.Runners) applies to the provider of each tool.
Class OcuTalon.Test.Bridge.CodeRules Extends %UnitTest.TestCase
{

/// The base classes of the classes that run inside AI Hub's callbacks.
Parameter CALLBACKBASES = "%AI.Tool,%AI.ToolSet,%AI.Policy.Authorization,%AI.Policy.Audit,%AI.Policy.Discovery,%AI.Shell.StreamRenderer";

/// The classes that extend none of those bases but whose methods the callbacks call: the step buffer, which the step renderer and the
/// step audit policy append to (AD-9).
Parameter CALLBACKHELPERS = "OcuTalon.Bridge.Adapter.StepBuffer";

/// A reference to AI Hub: %AI or EnsLib.AI as a word (the pattern of docker/tests/test-class-rules.sh).
Parameter AIREFERENCE = "(^|[^a-z0-9_])%ai([^a-z0-9]|$)|enslib[._]ai([^a-z0-9]|$)";

/// A use of Python.
Parameter PYTHON = "language\s*=\s*python|%sys\.python|\$system\.python";

/// The calls of the chat family of AI Hub's agent, adapter and provider, and Run of an agent, which calls Chat. Run is matched only
/// on an object named agent, because many classes have a method Run.
Parameter CHATCALLS = "\.(chat|chatwithcontent|streamchat|streamchatwithcontent|sendchat|sendchatwithcontent|runagent|chatcomplete|streamchatcomplete)\(|agent\.run\(";

/// A job started by a command, or the work manager. The command Job (or J) starts a line or follows a brace or a semicolon.
Parameter JOBS = "(^\s*|[{;]\s*)(job|j)(:[^ ]*)?\s+(\^|\.\.|##|\$|%|[a-z])|workmgr";

/// The classes that may call the chat family: the runner and its adapter.
Parameter CHATTERS = "OcuTalon.Bridge.Operation.AgentRunner,OcuTalon.Bridge.Adapter.Agent";

/// The calls that create, resume or open an AI session on an agent: CreateSession, ResumeSession and %InitWithSession of any object,
/// OpenSession of any object but the adapter, %AI.Agent.Session's Create, and SendChat, SendChatWithContent and RunAgent of AI Hub's
/// adapter, which create a session from its SessionConfig setting. The adapter's own methods NewSession and OpenSession are not
/// these calls.
Parameter SESSIONCALLS = "\.(createsession|resumesession|%initwithsession|sendchat|sendchatwithcontent|runagent)\(|(?<!adapter)\.opensession\(|%ai\.agent\.session\)\.create\(";

/// The class that may make sessions: the adapter, which composes their config.
Parameter SESSIONMAKERS = "OcuTalon.Bridge.Adapter.Agent";

/// A reference to the conversation link: the class (as a class or as the table OcuTalon_Bridge_Data.ConversationLink), or a global that holds its rows
/// or its lock (^OcuTalonBP.ConvLink..., ^OcuTalonBP.Conv).
Parameter LINKREFERENCE = "conversationlink|ocutalonbp\.conv";

/// The classes that may name the link class: the link itself, the adapter (which opens and writes links) and Decide (which probes the lock).
Parameter LINKNAMERS = "OcuTalon.Bridge.Data.ConversationLink,OcuTalon.Bridge.Adapter.Agent,OcuTalon.Bridge.Process.Decide";

/// A call of a method of the link class, as ##class(...ConversationLink).Method(, a system method (%New, %OpenId, %DeleteId) included.
Parameter LINKCALL = "conversationlink\)?\.[%\w]+\(";

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
	Set helpers = 0
	Set offending = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'OcuTalon.'")
	While result.%Next() {
		Set class = result.%GetData(1)
		If '##class(%Dictionary.CompiledClass).%ExistsId(class) Continue
		If '..IsCallbackClass(class) Continue
		Set classes = classes + 1
		If $ListFind($ListFromString(..#CALLBACKHELPERS), class) Set helpers = helpers + 1
		If $$$ISERR(##class(OcuTalon.Test.Bridge.Source).Text(class, .text)) {
			Set offending = offending _ " " _ class _ " (no source)"
			Continue
		}
		Set problem = ..CallbackProblem(text)
		If problem '= "" Set offending = offending _ " " _ class _ " (" _ problem _ ")"
	}
	Do $$$AssertTrue(classes >= 3, "the scan found the tool and toolset classes of OcuTalon: "_classes)
	Do $$$AssertEquals(helpers, $ListLength($ListFromString(..#CALLBACKHELPERS)), "and every class of CALLBACKHELPERS, which the callbacks call")
	Do $$$AssertEquals(offending, "", "no tool, toolset, policy or renderer class, nor a class that they call, refers to %AI beyond its Class line, or uses Python")
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
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"Set r = agent.StreamChatWithContent(s, c, cb)", pattern), "and StreamChatWithContent")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"Set r = provider.StreamChatComplete(m, c)", pattern), "and StreamChatComplete")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"Set r = ..Agent.Run(session, goal)", pattern), "and Run of an agent")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"SET R = AGENT.CHAT(S, I)", pattern), "in any case")
	Do $$$AssertTrue('##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"Set channel = msg.ChatRef"_$Char(10)_"/// Calls agent.Chat( in a comment"_$Char(10)_$Char(9)_"; agent.Chat("_$Char(10)_$Char(9)_"Set sc = ##class(OcuTalon.Install.Step.Production).Run()", pattern), "and passes a property that starts with Chat, comment lines and Run of another class")

	Set offending = ..Offenders(pattern, ..#CHATTERS, .scanned, .unreadable)
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

/// No class outside the Test package, except the adapter, creates, resumes or opens an AI session on an agent: every session that
/// the runner uses is made by the adapter, which gives it the composed config (the cap, the effort, max_iterations and the cache
/// block). The scanner is first shown to flag the calls and to pass the adapter's own methods and look-alikes.
Method TestSessionsOnlyThroughTheComposer()
{
	Set pattern = ..#SESSIONCALLS
	Set tab = $Char(9)
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"Set session = agent.CreateSession(config)", pattern), "the scanner flags CreateSession")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"Set session = ..Agent.ResumeSession(id)", pattern), "and ResumeSession")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"Set session = ..Agent.OpenSession(id, config)", pattern), "and OpenSession of the adapter's agent")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"Set session = agent.OpenSession(id)", pattern), "and OpenSession of any other agent")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"Set sc = agent.%InitWithSession(session)", pattern), "and %InitWithSession")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"Set s = ##class(%AI.Agent.Session).Create(p, m)", pattern), "and the Create of %AI.Agent.Session")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"Set sc = ..Adapter.SendChat(text, .r)", pattern), "and SendChat of AI Hub's adapter, which creates a session from its SessionConfig")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"Set sc = ..Adapter.SendChatWithContent(c, .r)", pattern), "and SendChatWithContent")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"Set sc = ..Adapter.RunAgent(goal, .r)", pattern), "and RunAgent")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(tab_"SET S = AGENT.CREATESESSION({})", pattern), "in any case")
	Do $$$AssertTrue('##class(OcuTalon.Test.Bridge.Source).Matches(tab_"Set sc = ..Adapter.NewSession(.session)"_$Char(10)_tab_"Set sc = ..Adapter.OpenSession(id, .session)"_$Char(10)_tab_"Set createsession = 1"_$Char(10)_"/// Calls agent.CreateSession( in a comment"_$Char(10)_tab_"; ..Agent.OpenSession(id, c)", pattern), "and passes the adapter's own methods, a variable and comment lines")

	Set offending = ..Offenders(pattern, ..#SESSIONMAKERS, .scanned, .unreadable)
	Do $$$AssertTrue(scanned > 50, "the scan read the source of the OcuTalon classes: "_scanned)
	Do $$$AssertEquals(unreadable, "", "and every class of the scan has source, except the generated stub classes of the process message tracking, which hold no code")
	Do $$$AssertEquals(offending, "", "no class but the adapter creates, resumes or opens an AI session on an agent")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Source).Text(..#SESSIONMAKERS, .text), ..#SESSIONMAKERS_" has source")
	Do $$$AssertTrue($ListLength(##class(OcuTalon.Test.Bridge.Source).Lines(text, pattern)) > 0, "and the scan sees the calls of the adapter, the one class that makes sessions")
}

/// Only the runner writes conversation links (AD-6, AD-33). No class outside the Test package, except ConversationLink, the adapter and Decide, names the
/// link class, its table or the globals of its rows and its lock. Decide calls Lock and Unlock of the class and nothing else (it takes the lock only to
/// probe it); the adapter calls Point, SessionOf, Lock and Unlock and nothing else; and Point is the only method of ConversationLink that saves or
/// deletes a row. The scanners are first shown to flag samples and to pass look-alikes and comment lines.
Method TestOnlyTheRunnerWritesLinks()
{
	Set pattern = ..#LINKREFERENCE
	Set tab = $Char(9)
	Set source = "OcuTalon.Test.Bridge.Source"
	Do $$$AssertTrue($ClassMethod(source, "Matches", tab_"Set sc = ##class(OcuTalon.Bridge.Data.ConversationLink).Point(owner, agent, id)", pattern), "the scanner flags a call of Point")
	Do $$$AssertTrue($ClassMethod(source, "Matches", tab_"&sql(DELETE FROM OcuTalon_Bridge_Data.ConversationLink WHERE OwnerRef = :owner)", pattern), "and the table in embedded SQL")
	Do $$$AssertTrue($ClassMethod(source, "Matches", tab_"Set rs = ##class(%SQL.Statement).%ExecDirect(, ""UPDATE OcuTalon_Bridge_Data.ConversationLink SET SessionId = ?"", id)", pattern), "and the table in a statement")
	Do $$$AssertTrue($ClassMethod(source, "Matches", tab_"Lock +^OcuTalonBP.Conv(owner, agent):2", pattern), "and the lock name")
	Do $$$AssertTrue($ClassMethod(source, "Matches", tab_"Set ^OcuTalonBP.ConvLinkD(1) = $ListBuild("""", owner, agent, id)", pattern), "and the global of the rows")
	Do $$$AssertTrue($ClassMethod(source, "Matches", tab_"SET LINK = ##CLASS(OCUTALON.BRIDGE.DATA.CONVERSATIONLINK).%NEW()", pattern), "in any case")
	Do $$$AssertTrue('$ClassMethod(source, "Matches", "/// Maps (OwnerRef, agent) to an AI session: ConversationLink"_$Char(10)_tab_"// ##class(OcuTalon.Bridge.Data.ConversationLink).Point(a, b, c)"_$Char(10)_tab_"; Lock +^OcuTalonBP.Conv(a, b)"_$Char(10)_tab_"Set text = ""the conversation is linked to a session"""_$Char(10)_tab_"Set x = ^OcuTalonBP.UsageCapped(day)"_$Char(10)_tab_"Set sc = ##class(OcuTalon.Bridge.Data.Usage).Totals(ref)", pattern), "and passes comment lines and look-alikes")

	Set calls = ..#LINKCALL
	Set sample = tab_"Set free = ##class(OcuTalon.Bridge.Data.ConversationLink).Lock(owner, agent)"_$Char(10)_tab_"Do ##class(OcuTalon.Bridge.Data.ConversationLink).Unlock(owner, agent)"_$Char(10)_tab_"// ##class(OcuTalon.Bridge.Data.ConversationLink).Point(a, b, c)"_$Char(10)_tab_"Set id = ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, agent)"
	Do $$$AssertEquals($ListToString(..LinkCalls(sample, calls), ","), "Lock,Unlock,SessionOf", "the call scanner lists the methods called, once each, comment lines left out")
	Do $$$AssertEquals($ListToString(..LinkCalls(tab_"Set x = 1", calls), ","), "", "and none for a class that does not name the link class")
	Do $$$AssertEquals($ListToString(..LinkCalls(tab_"Set link = ##class(OcuTalon.Bridge.Data.ConversationLink).%OpenId(id)"_$Char(10)_tab_"Do ##class(OcuTalon.Bridge.Data.ConversationLink).%DeleteId(id)", calls), ","), "%OpenId,%DeleteId", "and it lists the system methods, which write and delete rows")
	Set mentions = tab_"Set free = ##class(OcuTalon.Bridge.Data.ConversationLink).Lock(owner, agent)"_$Char(10)_tab_"// ##class(OcuTalon.Bridge.Data.ConversationLink).Point(a, b, c)"_$Char(10)_tab_"Set sc = ##class(OcuTalon.Bridge.Data.Usage).Totals(ref)"
	Do $$$AssertEquals(..LinkMentions(mentions, calls), 0, "a line that calls a method of the link class, a comment line and a look-alike are no stray mention")
	Do $$$AssertEquals(..LinkMentions(tab_"Set sc = $ClassMethod(""OcuTalon.Bridge.Data.ConversationLink"", ""Point"", a, b, c)", calls), 1, "a class name in a string is a stray mention")
	Do $$$AssertEquals(..LinkMentions(tab_"&sql(DELETE FROM OcuTalon_Bridge_Data.ConversationLink WHERE OwnerRef = :owner)", calls), 1, "and so is the table in embedded SQL")

	Set offending = ..Offenders(pattern, ..#LINKNAMERS, .scanned, .unreadable)
	Do $$$AssertTrue(scanned > 50, "the scan read the source of the OcuTalon classes: "_scanned)
	Do $$$AssertEquals(unreadable, "", "and every class of the scan has source, except the generated stub classes of the process message tracking, which hold no code")
	Do $$$AssertEquals(offending, "", "no class but ConversationLink, the adapter and Decide names the link class, its table or its globals")

	Do $$$AssertStatusOK($ClassMethod(source, "Text", "OcuTalon.Bridge.Process.Decide", .decide), "Decide has source")
	Do $$$AssertEquals($ListToString(..LinkCalls(decide, calls), ","), "Lock,Unlock", "Decide calls Lock and Unlock of the link class and nothing else")
	Do $$$AssertEquals(..LinkMentions(decide, calls), 0, "and its code names the link class nowhere but in those calls")
	Do $$$AssertEquals($ClassMethod(source, "Matches", decide, "ocutalonbp\.conv"), 0, "nor the globals of its rows and its lock")
	Do $$$AssertStatusOK($ClassMethod(source, "Text", "OcuTalon.Bridge.Adapter.Agent", .adapter), "the adapter has source")
	Set used = ..LinkCalls(adapter, calls)
	Do $$$AssertEquals($ListLength(used), 4, "the adapter calls four methods of the link class")
	For method = "Point", "SessionOf", "Lock", "Unlock" {
		Do $$$AssertTrue($ListFind(used, method), "the adapter calls "_method)
	}
	Do $$$AssertEquals(..LinkMentions(adapter, calls), 0, "and its code names the link class nowhere but in those calls")
	Do $$$AssertEquals($ClassMethod(source, "Matches", adapter, "ocutalonbp\.conv"), 0, "nor the globals of its rows and its lock")
	Do $$$AssertStatusOK($ClassMethod(source, "Text", "OcuTalon.Bridge.Data.ConversationLink", .link), "the link class has source")
	Do $$$AssertEquals($ListLength($ClassMethod(source, "Lines", link, "\.%save\(")), 1, "the link class saves a row in one place")
	Do $$$AssertEquals($ListToString(..LinkMethodsSaving(link), ","), "Point", "which is Point")
	Do $$$AssertEquals($ClassMethod(source, "Matches", link, "%delete|&sql\("), 0, "and it deletes none and runs no embedded SQL")
}

/// The helper that the scans share. A comment line is a line that starts, after white space, with //, ///, ;, #; or ##;; the scans
/// read every other line, one with a trailing comment included. A match is made in any case, and as plain text when asked for, so
/// that a pattern such as {{ needs no escape.
Method TestSourceHelper()
{
	Set tab = $Char(9), lf = $Char(10)
	Set text = "Code one"_lf_"/// doc"_lf_tab_"// comment"_lf_tab_"; comment"_lf_" #; comment"_lf_tab_"##; comment"_lf_"Code two ; with a trailing comment"_lf_tab_"//"_lf_"Code three"
	Set lines = ##class(OcuTalon.Test.Bridge.Source).CodeLines(text)
	Do $$$AssertEquals($ListToString(lines, "|"), "Code one|Code two ; with a trailing comment|Code three", "the comment lines of every form are dropped and the other lines kept")
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Test.Bridge.Source).Lines(text, "^code (one|three)$")), 2, "Lines gives the code lines that match, in any case")
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Test.Bridge.Source).Lines(text, "comment")), 1, "and finds a word in a trailing comment but not in a comment line")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("Set x = ""{{ a }}""", "{{", 1), "a plain-text match needs no escape")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("SET X = 1", "set x", 1), "and is made in any case")
	Do $$$AssertTrue('##class(OcuTalon.Test.Bridge.Source).Matches(tab_"// {{ a }}", "{{", 1), "and skips a comment line")
	Do $$$AssertTrue('##class(OcuTalon.Test.Bridge.Source).Matches("Set x = 1", "(", 1), "a plain-text match of a regular expression character is not an error")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("Set x = 1", "SET\s+X"), "a pattern is a regular expression, made in any case")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Test.Bridge.Source).Text("OcuTalon.Zz.NoSuchClass", .none), "the source of a class that does not exist is an error")
	Do $$$AssertEquals(none, "", "with no text")
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
		tab_"Do ##class(%SYSTEM.OBJ).Load(""a.xml"", ""ck"")",
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

/// 1 when the code of the class passes the rules of a tool class (AD-10): no $ZF, no XECUTE or $XECUTE, no $SYSTEM.OBJ (also as
/// ##class(%SYSTEM.OBJ)), no Python,
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
		$ListBuild("[$%]system\.obj\b", "$SYSTEM.OBJ"),
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
/// The distinct names of the methods that the code lines of the text call on the link class (pattern is LINKCALL), in the order found, as a list.
ClassMethod LinkCalls(text As %String, pattern As %String) As %List [ Private ]
{
	Set names = ""
	Set lines = ##class(OcuTalon.Test.Bridge.Source).CodeLines(text)
	Set position = 0
	While $ListNext(lines, position, line) {
		Set start = 1
		For {
			Set at = $Locate(line, "(?i)"_pattern, start, end, found)
			Quit:'at
			Set name = $Piece($Piece(found, ".", $Length(found, ".")), "(", 1)
			If '$ListFind(names, name) Set names = names _ $ListBuild(name)
			Set start = end
		}
	}
	Quit names
}

/// The number of code lines of the text that name the link class (any case) and hold no call of one of its methods (pattern is LINKCALL): a
/// class name in a string, the table in a statement, anything that would reach the link without a call the scan lists.
ClassMethod LinkMentions(text As %String, pattern As %String) As %Integer [ Private ]
{
	Set count = 0
	Set lines = ##class(OcuTalon.Test.Bridge.Source).CodeLines(text)
	Set position = 0
	While $ListNext(lines, position, line) {
		If $Locate(line, "(?i)conversationlink") && '$Locate(line, "(?i)"_pattern) Set count = count + 1
	}
	Quit count
}

/// The names of the methods of the link class whose code holds a save, as a list: the method headings are found in the UDL text, and a
/// method holds the lines up to the next heading.
ClassMethod LinkMethodsSaving(text As %String) As %List [ Private ]
{
	Set methods = ""
	Set current = ""
	Set lines = ##class(OcuTalon.Test.Bridge.Source).CodeLines(text)
	Set position = 0
	While $ListNext(lines, position, line) {
		If $Locate(line, "(?i)^(class)?method\s+\w+") {
			Set heading = $ZStrip(line, "<W")
			Set current = $Piece($Piece(heading, " ", 2), "(", 1)
		}
		If (current '= "") && $Locate(line, "(?i)\.%save\(") && '$ListFind(methods, current) Set methods = methods _ $ListBuild(current)
	}
	Quit methods
}

/// The non-test OcuTalon classes other than the allowed ones (a comma-separated list) whose code lines match the pattern, as
/// " Class1 Class2". scanned is the number of classes read, and unreadable the classes that have no source, except the generated
/// stub classes of the process message tracking ("is a stub name and can not be opened"), which hold no code.
ClassMethod Offenders(pattern As %String, allowed As %String, Output scanned As %Integer, Output unreadable As %String) As %String [ Private ]
{
	Set scanned = 0
	Set offending = ""
	Set unreadable = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'OcuTalon.' AND NOT Name %STARTSWITH 'OcuTalon.Test.'")
	While result.%Next() {
		Set class = result.%GetData(1)
		If $ListFind($ListFromString(allowed), class) Continue
		Set sc = ##class(OcuTalon.Test.Bridge.Source).Text(class, .text)
		If $$$ISERR(sc) {
			If $SYSTEM.Status.GetErrorText(sc) '[ "is a stub name" Set unreadable = unreadable _ " " _ class
			Continue
		}
		Set scanned = scanned + 1
		If ##class(OcuTalon.Test.Bridge.Source).Matches(text, pattern) Set offending = offending _ " " _ class
	}
	Quit offending
}

/// 1 when the compiled class extends one of the bases of the classes that run in AI Hub's callbacks. A class with no superclass has
/// no %Extends method and is none of them.
ClassMethod IsCallbackClass(class As %String) As %Boolean [ Private ]
{
	If $ListFind($ListFromString(..#CALLBACKHELPERS), class) Quit 1
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
