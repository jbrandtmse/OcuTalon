/// The code rules of the agent runners and of the code that runs inside AI Hub's callbacks (Story 1.2; AD-6, AD-10). Static: the
/// tests read the source of the compiled OcuTalon classes, drop their comment lines (Test.Bridge.Source), and call nothing in AI Hub.
/// Each scanner is first shown to flag a sample that breaks its rule and to pass one that keeps it.
///   - TestCallbackRule: a tool, toolset, policy or renderer class (a class that extends %AI.Tool, %AI.ToolSet, an %AI.Policy base or
///     %AI.Shell.StreamRenderer, or an extension base whose subclass the gate calls: the host sink and the classification extension), and a class whose
///     methods they call (CALLBACKHELPERS: the step buffer, the context, the classes that the reminder tools call and the classes that the gate calls, Approval.Raise's included), names %AI on no code
///     line except its Class line, and uses no Python, because on build 154 a session
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
///     Decide, names the link class (as a class, as the table, or by the globals that hold its rows and its lock); Decide calls Lock, Unlock and
///     SessionOf of it (Story 1.9: SessionOf only reads) and nothing else, a system method such as %New or %DeleteId included, and never Point; the
///     adapter, the only caller of Point, calls Point, SessionOf, Lock and Unlock, and Point in one place; no line of either names the link class more often than it calls one of its methods, and none names its
///     table or its globals; and Point is the only writer of the link class, which runs no SQL and touches no global directly;
///   - TestToolsReturnThroughResult (Story 1.9; AD-10, Consistency Conventions: Tool results): every product tool provider (a class of OcuTalon.Tools that
///     extends %AI.Tool, is not a toolset and is not Result) extends OcuTalon.Tools.Result, and none of its code lines quits or returns a value other than
///     the call ..Return(, or passes that call, on the same line, a JSON text built beforehand (%ToJSON, a conversion to JSON, a JSON literal), so no tool returns a literal or
///     a pre-encoded JSON string. The scanner is first shown to flag samples that break the rule and to pass plain text;
///   - TestToolsHaveStepLabels (Story 1.10, DW-85; AD-9, Consistency Conventions: Agent step labels): every tool that a class of OcuTalon.Tools offers,
///     a toolset's or a provider's (Result left out), has a step label of its own: StepBuffer.LabelFor of its provider and name, which reads the class
///     parameter STEPLABEL<NAME> or STEPLABEL, is not the generic label. The scanner is first shown to flag the probe tool, which declares none, and to
///     pass the labelled sample of the step tests; no two tools of the package share one label, and the watch fixture's three labels are the ones that the
///     veto window kept (QA);
///   - TestToolsLeaveRemindersToTheirOwner (Story 1.10; AD-1, AD-33): no class of OcuTalon.Tools names the Reminder class, its table or its globals, the
///     schedule package or ReminderOps: a tool changes a reminder only by submitting a command. The scanner is first shown to flag samples that break
///     the rule and to pass look-alikes and comment lines;
///   - TestNoToolReachesAGovernanceCommand (Story 3.3; AD-1, AD-10, NFR-14): every class of OcuTalon.Tools passes ToolCodeClean, which flags answering an
///     approval request, classifying a tool, changing a setting, adding an MCP server, pairing a chat and a command class outside TOOLVERBS
///     (TestToolCodeScan holds the samples), and every toolset of Triage, Diagnosis and Chat is a class of OcuTalon.Tools;
///   - TestSourceHelper: the helper that the scans share (Test.Bridge.Source) drops comment lines in each of their forms, keeps a
///     line with a trailing comment, and matches in any case, also as plain text.
/// ToolCodeClean(class, .problems) is the scan that the live inventory test (Test.Agent.Runners) applies to the provider of each tool. Since Story 1.10 the
/// classes that the reminder tools call inside AI Hub's callback (CommandCall, the redactor, Commands, CommandsIn and Data.Time) are scanned by the callback rule
/// too (CALLBACKHELPERS), and since Story 3.6 so are the classes that Approval.Raise runs there for a held call (Approval, Service.ApprovalStart, Ids and Time).
Class OcuTalon.Test.Bridge.CodeRules Extends %UnitTest.TestCase
{

/// The base classes of the classes that run inside AI Hub's callbacks: AI Hub's, and the extension bases (AD-31) whose subclass the gate calls inside
/// the callback (the host sink for turn.step, and the classification extension), so that every sink and classification class is scanned.
Parameter CALLBACKBASES = "%AI.Tool,%AI.ToolSet,%AI.Policy.Authorization,%AI.Policy.Audit,%AI.Policy.Discovery,%AI.Shell.StreamRenderer,OcuTalon.Bridge.Ext.HostSink,OcuTalon.Bridge.Ext.Classification";

/// The classes that extend none of those bases but whose methods the callbacks call: the step buffer, which the step renderer and the
/// step audit policy append to (AD-9), the context, which the gate, the step renderer and the tools read and put (AD-6, AD-10), and, since the reminder
/// tools (Story 1.10), the helper that submits their commands, the redactor that cleans its warnings, the one way to submit a command, the service that
/// receives it and the converter of times, and, since the gate (Story 3.2), the classes that it calls inside the callback: the settings accessor, Decide
/// (FireEvent) and OcuTalon's sink (also scanned as a host sink, CALLBACKBASES), and, since the gate holds a risky call (Story 3.6), the classes that
/// Approval.Raise runs inside the callback: the approval API, the service that starts the hold, the reference generator and the clock.
Parameter CALLBACKHELPERS = "OcuTalon.Bridge.Adapter.StepBuffer,OcuTalon.Bridge.Context,OcuTalon.Tools.CommandCall,OcuTalon.Bridge.Redact,OcuTalon.Core.Commands,OcuTalon.Core.CommandsIn,OcuTalon.Data.Time,OcuTalon.Bridge.Ext.Accessor,OcuTalon.Bridge.Process.Decide,OcuTalon.Core.BridgeSink,OcuTalon.Bridge.Approval,OcuTalon.Bridge.Service.ApprovalStart,OcuTalon.Bridge.Ids,OcuTalon.Bridge.Time";

/// The Reminder table and its owner (AD-33): the class, its table, its globals, the schedule package and the reminder operations. A tool never names one.
Parameter REMINDERREFERENCE = "ocutalon[._]data[._]reminder|ocutalonp\.reminder|ocutalon\.schedule|ocutalon_schedule|reminderops";

/// What no tool names (Story 3.3; AD-1, AD-10, NFR-14), as one regular expression, matched in any case on the code lines: answering or raising an approval
/// request (the Approval API and the other bridge classes of approvals, ApprovalStartIn, the table or globals, AnswersIn, EnsLib.Workflow), classifying a tool
/// (the names ToolClassification and ClassificationClass), changing a setting (SettingsOps, the Setting table or globals, Accessor.WriteDefault, Timeouts.Apply
/// and Restart, the writers of the public settings, every Ens.Director method that changes a production, and the creation or deletion of an Ens.Config
/// object: reading one is not flagged), adding an MCP server (OcuTalon.Mcp, McpOps), pairing a chat (SessionOps, the Pairing table or globals) and a command
/// class outside the package OcuTalon.Msg.Command (IncidentCommand).
Parameter GOVERNANCE = "ocutalon[._]bridge[._](\w+[._])?approval|ocutalonbp\.approval|approvalstartin|answersin|enslib[._]workflow|toolclassification|classificationclass|settingsops|ocutalon[._]data[._]setting|ocutalonp\.(setting|pairing)|accessor\W{1,4}writedefault\b|ocutalon[._]bridge[._]timeouts\W{1,4}(apply|restart)\b|public[._]settings\W{1,4}(set|setready|clearready)\b|ens\.director\W{1,6}(updateproduction|startproduction|stopproduction|restartproduction|recoverproduction|cleanproduction|deleteproduction|killproductionglobals|moveensruntimetoenssuspended|actualizeproductiondifferences|enableconfigitem|tempstopconfigitem|restartautoaddeditem|setautostart\w*|(set|remove)productionshutdowngroup|systemstart|systemstop|set\w*settingvalue)\b|ens\.config\.\w+\W{1,4}(%new|%deleteid|%delete|%deleteextent|%killextent)\b|ocutalon[._]mcp|mcpops|sessionops|ocutalon[._]data[._]pairing|msg[._]\w+command\b";

/// The command classes that a tool may submit (AD-1: the verbs that CommandsIn accepts from origin tool and that exist): any other
/// OcuTalon.Msg.Command.<Verb> in tool code is a governance command (Pair, Unpair, SetDemoMode, EndSession). Story 19.3's memory verbs join when they exist.
Parameter TOOLVERBS = "SetReminder,ListReminders,CancelReminder,StartWatch,StopWatch,Dismiss";

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

/// A call of ..Return( whose argument, on the same line, is a JSON text that was built beforehand: it holds a call of %ToJSON or the literal "JSON" (a
/// conversion to a JSON string), or it is a string literal of a JSON object or array: an empty one, an object whose first name is quoted, or an array whose
/// first member is a quoted string or an object. A literal that starts with a bracket and a word, such as "[reminder set]", is plain text. AI Hub encodes a
/// string result again, so the model would get a JSON string literal; a dynamic object is what the tool has to pass (AD-10).
Parameter PREENCODED = "(?i)\.\.Return\((.*(\.%ToJSON\s*\(|""JSON"")|\s*""(\{\s*(""""|\})|\[\s*(""""|\{|\])))";

/// The classes that may name the link class: the link itself, the adapter (which opens and writes links) and Decide (which probes the lock and reads the
/// session that a link names).
Parameter LINKNAMERS = "OcuTalon.Bridge.Data.ConversationLink,OcuTalon.Bridge.Adapter.Agent,OcuTalon.Bridge.Process.Decide";

/// A call of a method of the link class, as ##class(...ConversationLink).Method(, a system method (%New, %OpenId, %DeleteId) included.
Parameter LINKCALL = "conversationlink\)?\.[%\w]+\(";

/// A line that deletes a row, runs SQL or writes a global directly, which the link class never holds: a delete or kill, a dynamic or embedded
/// statement ($SYSTEM.SQL, %ExecDirect, %Prepare, an Execute, &sql), a Kill or Merge of a global (K and M too), a Set of a global (S too, with a
/// condition, or after other targets of the same Set) and $Increment of a global.
Parameter LINKWRITES = "%delete|%killextent|%execdirect|%prepare|&sql\(|\$system\.sql|\.%?execute\(|\bkill\b|\b(k|m|merge)\s+\^|\b(s|set)\b(:\S+)?\s+([^\s,=]+\s*=\s*[^,]+,\s*)*\^|\$i(ncrement)?\(\s*\^";

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
	Set listed = $ListFromString(..#CALLBACKHELPERS)
	For raiseClass = "OcuTalon.Bridge.Approval", "OcuTalon.Bridge.Service.ApprovalStart", "OcuTalon.Bridge.Ids", "OcuTalon.Bridge.Time" {
		Do $$$AssertTrue($ListFind(listed, raiseClass) > 0 && ..IsCallbackClass(raiseClass), "Approval.Raise runs " _ raiseClass _ " inside the callback, so it is in CALLBACKHELPERS and scanned")
	}
	Do $$$AssertTrue(..IsCallbackClass("OcuTalon.Bridge.Ext.Classification") && ..IsCallbackClass("OcuTalon.Test.Bridge.ProbeSink"), "an extension base and a subclass of one are scanned")
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
/// probe it); the adapter calls Point, SessionOf, Lock and Unlock and nothing else, and Point in one place; and Point is the only method of
/// ConversationLink that saves or deletes a row. The scanners are first shown to flag samples and to pass look-alikes and comment lines.
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
	Do $$$AssertEquals(..LinkMentions(tab_"If ##class(OcuTalon.Bridge.Data.ConversationLink).Lock(o, a) { Set sc = $ClassMethod(""OcuTalon.Bridge.Data.ConversationLink"", ""Point"", o, a, id) }", calls), 1, "a stray mention on a line that also calls a method of the link class is flagged")
	Do $$$AssertEquals(..LinkMentions(tab_"If ##class(OcuTalon.Bridge.Data.ConversationLink).Lock(o, a) { Do ##class(OcuTalon.Bridge.Data.ConversationLink).Unlock(o, a) }", calls), 0, "and a line with two calls is no stray mention")
	Set writes = ..#LINKWRITES
	For sample = "Do ##class(OcuTalon.Bridge.Data.ConversationLink).%DeleteId(id)", "Do $SYSTEM.SQL.Execute(""DELETE FROM OcuTalon_Bridge_Data.ConversationLink"")", "Set rs = statement.%Execute(id)", "&sql(DELETE FROM OcuTalon_Bridge_Data.ConversationLink)", "Kill ^OcuTalonBP.ConvLinkD", "K ^OcuTalonBP.ConvLinkD(1)", "Merge ^OcuTalonBP.ConvLinkD(2) = ^OcuTalonBP.ConvLinkD(1)", "S ^OcuTalonBP.ConvLinkD(1) = 1", "Set:x ^OcuTalonBP.ConvLinkD(1) = 1", "Set x = 1, ^OcuTalonBP.ConvLinkD(1) = 2", "If $Increment(^OcuTalonBP.ConvLinkD)" {
		Do $$$AssertTrue($ClassMethod(source, "Matches", tab_sample, writes), "the write scanner flags: "_sample)
	}
	Do $$$AssertTrue('$ClassMethod(source, "Matches", tab_"Set link.SessionId = sessionId"_$Char(10)_tab_"Lock +^OcuTalonBP.Conv(ownerRef, agent):seconds"_$Char(10)_tab_"Lock -^OcuTalonBP.Conv(ownerRef, agent)"_$Char(10)_tab_"Quit link.%Save()", writes), "and passes the link class's own Set, Lock and save")

	Set offending = ..Offenders(pattern, ..#LINKNAMERS, .scanned, .unreadable)
	Do $$$AssertTrue(scanned > 50, "the scan read the source of the OcuTalon classes: "_scanned)
	Do $$$AssertEquals(unreadable, "", "and every class of the scan has source, except the generated stub classes of the process message tracking, which hold no code")
	Do $$$AssertEquals(offending, "", "no class but ConversationLink, the adapter and Decide names the link class, its table or its globals")

	Do $$$AssertStatusOK($ClassMethod(source, "Text", "OcuTalon.Bridge.Process.Decide", .decide), "Decide has source")
	Set used = ..LinkCalls(decide, calls)
	Do $$$AssertEquals($ListLength(used), 3, "Decide calls three methods of the link class and nothing else")
	For method = "Lock", "Unlock", "SessionOf" {
		Do $$$AssertTrue($ListFind(used, method), "Decide calls "_method)
	}
	Do $$$AssertEquals($ListFind(used, "Point"), 0, "and never Point: it only reads the link")
	Do $$$AssertEquals(..LinkMentions(decide, calls), 0, "and its code names the link class nowhere but in those calls")
	Do $$$AssertEquals($ClassMethod(source, "Matches", decide, "ocutalonbp\.conv"), 0, "nor the globals of its rows and its lock")
	Do $$$AssertStatusOK($ClassMethod(source, "Text", "OcuTalon.Bridge.Adapter.Agent", .adapter), "the adapter has source")
	Set used = ..LinkCalls(adapter, calls)
	Do $$$AssertEquals($ListLength(used), 4, "the adapter calls four methods of the link class")
	For method = "Point", "SessionOf", "Lock", "Unlock" {
		Do $$$AssertTrue($ListFind(used, method), "the adapter calls "_method)
	}
	Do $$$AssertEquals($ListLength($ClassMethod(source, "Lines", adapter, "conversationlink\)\.point\(")), 1, "and it calls Point in one place, the save of a linked turn")
	Do $$$AssertEquals(..LinkMentions(adapter, calls), 0, "and its code names the link class nowhere but in those calls")
	Do $$$AssertEquals($ClassMethod(source, "Matches", adapter, "ocutalonbp\.conv"), 0, "nor the globals of its rows and its lock")
	Do $$$AssertStatusOK($ClassMethod(source, "Text", "OcuTalon.Bridge.Data.ConversationLink", .link), "the link class has source")
	Do $$$AssertEquals($ListLength($ClassMethod(source, "Lines", link, "\.%save\(")), 1, "the link class saves a row in one place")
	Do $$$AssertEquals($ListToString(..LinkMethodsSaving(link), ","), "Point", "which is Point")
	Do $$$AssertEquals($ClassMethod(source, "Matches", link, writes), 0, "and it deletes none, runs no SQL and touches no global directly")
}

/// Every product tool provider returns only through OcuTalon.Tools.Result (Story 1.9; AD-10, Consistency Conventions: Tool results). A provider is a class of the
/// package OcuTalon.Tools that extends %AI.Tool, is not a toolset and is not Result itself. ToolProblem names what breaks the rule: the class does not
/// extend Result, or a code line quits or returns a value other than the call ..Return(. The scanner is first shown to flag a sample that returns a literal, one
/// that returns a pre-encoded JSON string through a variable, one that uses Return, and one that does not extend Result, and to pass a sample that returns
/// through ..Return( with comment lines, a bare Quit and look-alike words in strings.
Method TestToolsReturnThroughResult()
{
	Set tab = $Char(9), lf = $Char(10)
	Set head = "Class OcuTalon.Tools.Zz Extends OcuTalon.Tools.Result"_lf_"{"_lf_"ClassMethod A() As %DynamicObject"_lf_"{"_lf
	Set tail = lf_"}"_lf_"}"
	Set literal = head_tab_"Quit ""{""""items"""":[]}"""_tail
	Set encoded = head_tab_"Set text = {""items"": []}.%ToJSON()"_lf_tab_"Quit text"_tail
	Set returns = head_tab_"Return {""items"": []}"_tail
	Set conditional = head_tab_"Quit:production="""" {""items"": []}"_tail
	Set good = "/// Never Quit ""x"" in a comment."_lf_head_tab_"// Quit ""{}"""_lf_tab_"If production = ""x"" Quit"_lf_tab_"Set title = ""Return of the tool and Quit 1"""_lf_tab_"Quit ..Return({""items"": []})"_tail
	Set commented = head_tab_"Quit ""x"" // note"_tail
	Set bare = head_tab_"If production = ""x"" { Quit }"_lf_tab_"Quit   // nothing more to do"_lf_tab_"Quit ..Return({""items"": []}) ; the answer"_tail
	Set viaToJson = head_tab_"Quit ..Return({""items"": []}.%ToJSON())"_tail
	Set viaVariable = head_tab_"Set object = {""items"": []}"_lf_tab_"Quit ..Return(object.%ToJSON()) // the answer"_tail
	Set viaLiteral = head_tab_"Quit ..Return(""{""""items"""":[]}"")"_tail
	Set viaConvert = head_tab_"Quit ..Return($ZConvert(text, ""O"", ""JSON""))"_tail
	Set viaShapes = head_tab_"If a Quit ..Return(""[]"")"_lf_tab_"If b Quit ..Return(""{}"")"_lf_tab_"If c Quit ..Return(""[{""""a"""":1}]"")"_lf_tab_"Quit ..Return(""{ """"a"""": 1 }"")"_tail
	Set plain =head_tab_"Quit ..Return(""[reminder set]"")"_lf_tab_"Quit ..Return(""The JSON of the item is shown below."")"_lf_tab_"Quit ..Return($ZConvert(text, ""L""))"_tail
	Do $$$AssertTrue(..ToolProblem(1, literal) '= "", "the scanner flags a tool that returns a literal")
	Do $$$AssertTrue(..ToolProblem(1, viaToJson) '= "", "and one that passes ..Return( the JSON text of an object")
	Do $$$AssertTrue(..ToolProblem(1, viaVariable) '= "", "also through a variable and with a comment after it")
	Do $$$AssertTrue(..ToolProblem(1, viaLiteral) '= "", "and one that passes ..Return( a JSON literal")
	Do $$$AssertTrue(..ToolProblem(1, viaConvert) '= "", "and one that passes ..Return( a conversion to a JSON string")
	Do $$$AssertTrue(..ToolProblem(1, viaShapes) [ "4 line(s) pass a pre-encoded JSON text", "and each of an empty array, an empty object, an array of objects and an object with space after its brace: "_..ToolProblem(1, viaShapes))
	Do $$$AssertEquals(..ToolProblem(1, plain), "", "but not plain text: a literal that starts with a bracket, a text that mentions JSON and a text conversion")
	Do $$$AssertTrue(..ToolProblem(1, commented) '= "", "also when a comment follows the literal")
	Do $$$AssertTrue(..ToolProblem(1, encoded) '= "", "and one that returns a pre-encoded JSON string through a variable")
	Do $$$AssertTrue(..ToolProblem(1, returns) '= "", "and one that uses Return")
	Do $$$AssertTrue(..ToolProblem(1, conditional) '= "", "and one that returns a value on a condition")
	Do $$$AssertTrue(..ToolProblem(0, good) '= "", "and a class that does not extend Result, though its code is clean")
	Do $$$AssertEquals(..ToolProblem(1, good), "", "and passes a tool that returns through ..Return(, with comment lines, a bare Quit and look-alike words in strings")
	Do $$$AssertEquals(..ToolProblem(1, bare), "", "also a bare Quit in a block on one line, a bare Quit with a trailing comment and a return through ..Return( with one")

	Set providers = 0
	Set offending = ""
	Set found = ""
	Set classes = ..ToolClasses(0)
	Set position = 0
	While $ListNext(classes, position, class) {
		Set providers = providers + 1
		Set found = found _ $ListBuild(class)
		If $$$ISERR(##class(OcuTalon.Test.Bridge.Source).Text(class, .text)) {
			Set offending = offending _ " " _ class _ " (no source)"
			Continue
		}
		Set problem = ..ToolProblem(..ClassExtends(class, "OcuTalon.Tools.Result"), text)
		If problem '= "" Set offending = offending _ " " _ class _ " (" _ problem _ ")"
	}
	Do $$$AssertTrue(providers '< 1, "the scan found the tool providers of OcuTalon.Tools: "_$ListToString(found, ","))
	Do $$$AssertTrue($ListFind(found, "OcuTalon.Tools.WatchFixture"), "the Watch fixture is one of them")
	Do $$$AssertTrue($ListFind(found, "OcuTalon.Tools.ReminderTools"), "and so is the class of the reminder tools")
	Do $$$AssertEquals(offending, "", "every one extends OcuTalon.Tools.Result and returns only through ..Return(")
}

/// Every tool that a class of OcuTalon.Tools offers has a step label of its own (Story 1.10, DW-85; AD-9). For each class of the package that extends
/// %AI.Tool, Result left out, toolsets and providers alike, the tools that its discovery lists (each with its provider and its name) get a label from
/// StepBuffer.LabelFor that is not the generic one. The scanner is first shown to flag the probe tool, whose tool declares no label, and to pass the labelled
/// sample of the step tests, whose class declares STEPLABEL; the watch fixture's three tools are scanned like the others.
Method TestToolsHaveStepLabels()
{
	Set probe = ..UnlabelledTools("OcuTalon.Test.Bridge.ProbeTool")
	Do $$$AssertEquals($ListToString(probe), "Probe", "the scanner flags the probe tool, which declares no step label")
	Do $$$AssertEquals($ListLength(..UnlabelledTools("OcuTalon.Test.Bridge.StepsNote")), 0, "and passes the sample whose class declares STEPLABEL")
	Do $$$AssertEquals($ListLength(..UnlabelledTools("OcuTalon.Test.Bridge.StepsTools")), 0, "also through a toolset")

	Set classes = ..ToolClasses(1)
	Do $$$AssertTrue($ListFind(classes, "OcuTalon.Tools.Watch") && $ListFind(classes, "OcuTalon.Tools.WatchFixture") && $ListFind(classes, "OcuTalon.Tools.Reminders") && $ListFind(classes, "OcuTalon.Tools.ReminderTools"), "the scan finds the watch and the reminder tools: "_$ListToString(classes, ","))
	Set tools = 0
	Set offending = ""
	Set shared = ""
	Set position = 0
	While $ListNext(classes, position, class) {
		Set iterator = $ClassMethod(class, "%New").%Discover().tools.%GetIterator()
		While iterator.%GetNext(, .tool) {
			Set tools = tools + 1
			Set label = ##class(OcuTalon.Bridge.Adapter.StepBuffer).LabelFor(tool.provider, tool.name)
			// A toolset names a tool set_reminder and its provider's own discovery names it SetReminder: the same tool, by the rule of the label.
			Set key = tool.provider _ "|" _ $ZConvert($Translate(tool.name, "_-"), "U")
			If $Data(labelOf(label)) && (labelOf(label) '= key) Set shared = shared _ " '" _ label _ "' (" _ labelOf(label) _ " and " _ key _ ")"
			Set labelOf(label) = key
		}
		Set bad = ..UnlabelledTools(class)
		If $ListLength(bad) Set offending = offending _ " " _ class _ " (" _ $ListToString(bad, ",") _ ")"
	}
	Do $$$AssertTrue(tools '< 12, "the scan found the tools of OcuTalon.Tools: "_tools)
	Do $$$AssertEquals(offending, "", "every one has a step label of its own")
	Do $$$AssertEquals(shared, "", "and no two tools share a label, so that each label is its tool's own: "_shared)
	Set names = "OcuTalon.Tools.Names"
	Set watch = "OcuTalon.Tools.WatchFixture"
	Set step = "OcuTalon.Bridge.Adapter.StepBuffer"
	Do $$$AssertEquals($ClassMethod(step, "LabelFor", watch, $Parameter(names, "READFAILEDMESSAGES")), "Reading the failed messages", "the watch fixture's labels are the ones that the veto window kept: read_failed_messages")
	Do $$$AssertEquals($ClassMethod(step, "LabelFor", watch, $Parameter(names, "READEVENTLOG")), "Reading the event log", "read_event_log")
	Do $$$AssertEquals($ClassMethod(step, "LabelFor", watch, $Parameter(names, "READITEMSETTINGS")), "Reading the item settings", "and read_item_settings")
}

/// No tool touches a reminder itself (Story 1.10; AD-1, AD-33): no class of the package OcuTalon.Tools names the Reminder class, its table, its globals, the
/// schedule package or ReminderOps (the owner's), so a tool changes a reminder only by submitting a command. The scanner is first shown to flag a class
/// reference, the table in a statement, the global, the schedule package and ReminderOps, and to pass look-alikes, the command classes and comment lines.
Method TestToolsLeaveRemindersToTheirOwner()
{
	Set pattern = ..#REMINDERREFERENCE
	Set tab = $Char(9), lf = $Char(10)
	Set source = "OcuTalon.Test.Bridge.Source"
	Do $$$AssertTrue($ClassMethod(source, "Matches", tab_"Set row = ##class(OcuTalon.Data.Reminder).%New()", pattern), "the scanner flags the Reminder class")
	Do $$$AssertTrue($ClassMethod(source, "Matches", tab_"Set rs = ##class(%SQL.Statement).%ExecDirect(, ""SELECT Ref FROM OcuTalon_Data.Reminder WHERE State = 'pending'"")", pattern), "and its table in a statement")
	Do $$$AssertTrue($ClassMethod(source, "Matches", tab_"Set due = $Get(^OcuTalonP.ReminderD(1))", pattern), "and its global")
	Do $$$AssertTrue($ClassMethod(source, "Matches", tab_"Do ##class(OcuTalon.Schedule.ReminderOps).Cancel(ref)", pattern), "and the schedule package")
	Do $$$AssertTrue($ClassMethod(source, "Matches", tab_"Set sc = $ClassMethod(""OcuTalon.Schedule.Checks"", ""Run"")", pattern), "also in a string")
	Do $$$AssertTrue($ClassMethod(source, "Matches", tab_"SET R = ##CLASS(OCUTALON.DATA.REMINDER).%OPENID(1)", pattern), "in any case")
	Do $$$AssertTrue('$ClassMethod(source, "Matches", "/// Never reads OcuTalon.Data.Reminder or OcuTalon_Data.Reminder"_lf_tab_"// ##class(OcuTalon.Schedule.ReminderOps).Cancel(ref)"_lf_tab_"; ^OcuTalonP.ReminderD"_lf_tab_"Set command = ##class(OcuTalon.Msg.Command.SetReminder).%New()"_lf_tab_"Set text = ""A reminder is set by the owner""", pattern), "and passes the command classes, a text about reminders and comment lines")

	Set scanned = 0
	Set offending = ""
	Set unreadable = ""
	Set classes = ..ToolClasses(1, 1)
	Set position = 0
	While $ListNext(classes, position, class) {
		If $$$ISERR($ClassMethod(source, "Text", class, .text)) {
			Set unreadable = unreadable _ " " _ class
			Continue
		}
		Set scanned = scanned + 1
		If $ClassMethod(source, "Matches", text, pattern) Set offending = offending _ " " _ class
	}
	Do $$$AssertTrue(scanned '< 7, "the scan read the classes of OcuTalon.Tools: "_scanned)
	Do $$$AssertEquals(unreadable, "", "and every one has source")
	Do $$$AssertEquals(offending, "", "no class of OcuTalon.Tools names the Reminder class, its table or globals, the schedule package or ReminderOps")
	Do $$$AssertStatusOK($ClassMethod(source, "Text", "OcuTalon.Tools.ReminderTools", .tools), "the reminder tools have source")
	Do $$$AssertTrue($ClassMethod(source, "Matches", tools, "msg\.command\.(setreminder|listreminders|cancelreminder)"), "and they name the command classes, which is how they change a reminder")
}

/// No tool reaches a governance command (Story 3.3; AD-1, AD-10, NFR-14): every class of OcuTalon.Tools passes ToolCodeClean, which flags the
/// governance references of GOVERNANCE and every command class outside TOOLVERBS, and every toolset of Triage, Diagnosis and Chat is a class of
/// OcuTalon.Tools. The scan's samples are in TestToolCodeScan.
Method TestNoToolReachesAGovernanceCommand()
{
	Set scanned = 0
	Set offending = ""
	Set classes = ..ToolClasses(1, 1)
	Set position = 0
	While $ListNext(classes, position, class) {
		Set scanned = scanned + 1
		If '..ToolCodeClean(class, .problems) Set offending = offending _ " " _ class _ " (" _ problems _ ")"
	}
	Do $$$AssertTrue(scanned '< 7, "the sweep read the classes of OcuTalon.Tools: "_scanned)
	Do $$$AssertEquals(offending, "", "no class of OcuTalon.Tools names a governance reference or a command class outside the tool verbs")
	Set toolsets = 0
	For agent = "OcuTalon.Agent.Triage", "OcuTalon.Agent.Diagnosis", "OcuTalon.Agent.Chat" {
		Set list = $ListFromString($Parameter(agent, "TOOLSETS"))
		Set position = 0
		While $ListNext(list, position, entry) {
			Set toolsets = toolsets + 1
			Do $$$AssertTrue($Extract(entry, 1, $Length("OcuTalon.Tools.")) = "OcuTalon.Tools.", agent_" has the toolset "_entry_", a class of OcuTalon.Tools")
			Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(entry), "which is compiled")
		}
	}
	Do $$$AssertTrue(toolsets '< 2, "the agents have toolsets (Diagnosis and Chat): "_toolsets)
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
		tab_"Set st = ""CREATE TABLE A.B (X INT)""",
		tab_"Do ##class(OcuTalon.Bridge.Approval).Raise(""tool_call"")",
		tab_"Set rs = ##class(%SQL.Statement).%ExecDirect(, ""SELECT Ref FROM OcuTalon_Bridge_Data.ApprovalRequest"")",
		tab_"Set open = $Get(^OcuTalonBP.ApprovalD(1))",
		tab_"Set sc = ##class(OcuTalon.Core.AnswersIn).Answer(ref, ""approve"")",
		tab_"Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(id)",
		tab_"Do ##class(OcuTalon.Test.Agent.RunnerFixture).PutDefault(""Decide"", ""ToolClassification"", ""[]"")",
		tab_"Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor(""ClassificationClass"")",
		tab_"Do ##class(OcuTalon.Core.SettingsOps).Put(""Decide"", ""Model"", ""x"")",
		tab_"Set row = ##class(OcuTalon.Data.Setting).%New()",
		tab_"Do ##class(Ens.Director).UpdateProduction()",
		tab_"Do ##class(Ens.Director).StartProduction(""A.B"")",
		tab_"Do ##class(Ens.Director).StopProduction()",
		tab_"Do ##class(Ens.Director).RestartProduction()",
		tab_"Do ##class(Ens.Director).EnableConfigItem(""Decide"", 0)",
		tab_"Do ##class(Ens.Director).SetAutoStart(""A.B"", 1)",
		tab_"Do ##class(Ens.Director).SetItemSettingValue(""Decide"", ""Adapter"", ""x"", ""y"")",
		tab_"Do ##class(Ens.Director).CleanProduction()",
		tab_"Set item = ##class(Ens.Config.Item).%New()",
		tab_"Do ##class(Ens.Config.Item).%DeleteId(id)",
		tab_"Do ##class(Ens.Config.Production).%Delete(oid)",
		tab_"Do ##class(Ens.Config.DefaultSettings).%KillExtent()",
		tab_"Set server = ##class(OcuTalon.Mcp.Server).%New()",
		tab_"Do ##class(OcuTalon.Core.McpOps).Add(""x"")",
		tab_"Do ##class(OcuTalon.Core.SessionOps).Pair(code)",
		tab_"Set row = ##class(OcuTalon.Data.Pairing).%OpenId(1)",
		tab_"Set command = ##class(OcuTalon.Msg.Command.Pair).%New()",
		tab_"Set command = ##class(OcuTalon.Msg.Command.Unpair).%New()",
		tab_"Set command = ##class(OcuTalon.Msg.Command.SetDemoMode).%New()",
		tab_"Set command = ##class(OcuTalon.Msg.Command.EndSession).%New()",
		tab_"Do ##class(Ens.Director).TempStopConfigItem(""Decide"", 1)",
		tab_"Do ##class(Ens.Director).SystemStop()",
		tab_"Do ##class(Ens.Director).SetAutoStartRecommendedPriority(1)",
		tab_"Do ##class(Ens.Director).RemoveProductionShutdownGroup(""A.B"")",
		tab_"Do ##class(Ens.Config.Item).%DeleteExtent()",
		tab_"Set value = $Get(^OcuTalonP.SettingD(1))",
		tab_"Kill ^OcuTalonP.PairingD(1)",
		tab_"Set hold = ##class(OcuTalon.Bridge.Process.ApprovalHold).%New()",
		tab_"Set sc = ##class(Ens.Director).CreateBusinessService(""ApprovalStartIn"", .service)",
		tab_"Do ##class(OcuTalon.Bridge.Ext.Accessor).WriteDefault(""A.B"", ""Decide"", ""Model"", ""x"", """")",
		tab_"Do ##class(OcuTalon.Bridge.Timeouts).Restart(""A.B"", runners)",
		tab_"Do ##class(OcuTalon.Data.Public.Settings).Set(""onlineDemo"", 1)",
		tab_"Set command = ##class(OcuTalon.Msg.IncidentCommand).%New()")
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
	Set governed = "/// Never names OcuTalon.Bridge.Approval or SettingsOps or Ens.Director UpdateProduction."_lf_
		tab_"// ##class(OcuTalon.Msg.Command.Pair).%New()"_lf_
		tab_"Set command = ##class(OcuTalon.Msg.Command.SetReminder).%New()"_lf_
		tab_"Set command = ##class(OcuTalon.Msg.Command.ListReminders).%New()"_lf_
		tab_"Set command = ##class(OcuTalon.Msg.Command.CancelReminder).%New()"_lf_
		tab_"Set command = ##class(OcuTalon.Msg.Command.StartWatch).%New()"_lf_
		tab_"Set command = ##class(OcuTalon.Msg.Command.setreminder).%New()"_lf_
		tab_"&sql(SELECT Ref INTO :ref FROM OcuTalon_Msg_Command_SetReminder WHERE X = :y)"_lf_
		tab_"Set value = ##class(Ens.Director).GetItemSettingValue(""Decide"", ""Host"", ""Model"", .value)"_lf_
		tab_"Set sc = ##class(Ens.Director).CreateBusinessService(""CommandsIn"", .service)"_lf_
		tab_"Set item = ##class(Ens.Config.Item).%OpenId(id)"_lf_
		tab_"Set priority = ##class(Ens.Director).GetAutoStartRecommendedPriority()"_lf_
		tab_"Set demo = ##class(OcuTalon.Data.Public.Settings).Get(""onlineDemo"")"_lf_
		tab_"Set text =""Say that you approve it, and that the setting is ToolOption or a classification word"""_lf_
		tab_"Set result = ##class(OcuTalon.Msg.CommandResult).%New()"
	Set clean = ..ToolCodeClean("", .problems, governed)
	Do $$$AssertEquals(clean, 1, "and one that submits the tool commands, creates a business service, reads an Ens.Config object, says approve in a string and has the governance names in comments: "_problems)
	Do $$$AssertEquals(problems, "", "and has nothing to say")
	Set clean = ..ToolCodeClean("OcuTalon.Tools.WatchFixture", .problems)
	Do $$$AssertEquals(clean, 1, "the Watch fixture is clean: "_problems)
	Set clean = ..ToolCodeClean("OcuTalon.Test.Bridge.ProbeTool", .problems)
	Do $$$AssertEquals(clean, 1, "and so is the probe tool: "_problems)
	Set clean = ..ToolCodeClean("OcuTalon.Tools.ReminderTools", .problems)
	Do $$$AssertEquals(clean, 1, "and the class of the reminder tools, descriptions included: "_problems)
	Set clean = ..ToolCodeClean("OcuTalon.Tools.CommandCall", .problems)
	Do $$$AssertEquals(clean, 1, "and the helper that submits their commands: "_problems)
	Set clean = ..ToolCodeClean("OcuTalon.Zz.NoSuchClass", .problems)
	Do $$$AssertEquals(clean, 0, "a class with no source is not clean")
	Do $$$AssertTrue(problems [ "OcuTalon.Zz.NoSuchClass", "and the problem names it: "_problems)
}

/// 1 when the code of the class passes the rules of a tool class (AD-10): no $ZF, no XECUTE or $XECUTE, no $SYSTEM.OBJ (also as
/// ##class(%SYSTEM.OBJ)), no Python,
/// and no INSERT, UPDATE, DELETE, DROP, CREATE, ALTER or TRUNCATE inside embedded SQL (&sql) or at the start of a string, no governance reference
/// (GOVERNANCE) and no command class outside TOOLVERBS (Story 3.3). problems
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
		$ListBuild("""\s*("_..#SQLVERBS_")\b", "a string that starts with an SQL statement that changes data"),
		$ListBuild(..#GOVERNANCE, "a governance reference (an approval, a classification, a setting, an MCP server, a pairing or a command outside the tool verbs)"))
	Set position = 0
	While $ListNext(checks, position, check) {
		If ##class(OcuTalon.Test.Bridge.Source).Matches(text, $List(check, 1)) Set problems = problems _ $Select(problems = "": "", 1: "; ") _ "uses " _ $List(check, 2)
	}
	Set verbs = $ListFromString($ZConvert(..#TOOLVERBS, "L"))
	Set lines = ##class(OcuTalon.Test.Bridge.Source).CodeLines(text)
	Set position = 0
	While $ListNext(lines, position, line) {
		Set start = 1
		For {
			Set at = $Locate(line, "(?i)msg[._]command[._]\w+", start, end, found)
			Quit:'at
			Set dotted = $Translate(found, "_", ".")
			Set verb = $Piece(dotted, ".", $Length(dotted, "."))
			If '$ListFind(verbs, $ZConvert(verb, "L")) Set problems = problems _ $Select(problems = "": "", 1: "; ") _ "names the command class " _ verb _ ", which is not a tool verb"
			Set start = end
		}
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

/// The number of code lines of the text that name the link class (any case) more often than they call one of its methods (pattern is LINKCALL): a
/// class name in a string, the table in a statement, anything that would reach the link without a call the scan lists, also on a line that calls a
/// method as well.
ClassMethod LinkMentions(text As %String, pattern As %String) As %Integer [ Private ]
{
	Set count = 0
	Set lines = ##class(OcuTalon.Test.Bridge.Source).CodeLines(text)
	Set position = 0
	While $ListNext(lines, position, line) {
		Set named = $Length($ZConvert(line, "L"), "conversationlink") - 1
		Set called = 0
		Set start = 1
		For {
			Set at = $Locate(line, "(?i)"_pattern, start, end)
			Quit:'at
			Set called = called + 1
			Set start = end
		}
		If named > called Set count = count + 1
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
		If $Locate(line, "(?i)^(class)?method\s+[%\w]+") {
			Set heading = $ZStrip(line, "<W")
			Set current = $Piece($Piece(heading, " ", 2), "(", 1)
		}
		If (current '= "") && $Locate(line, "(?i)\.%save\(") && '$ListFind(methods, current) Set methods = methods _ $ListBuild(current)
	}
	Quit methods
}

/// What breaks the rule of a tool provider (AD-10): "" when it extends Result (extendsResult is 1), no code line of the text quits or returns a value other
/// than the call ..Return(, and no call of ..Return( passes a JSON text built beforehand (PREENCODED), otherwise the reasons separated by semicolons. A string literal is blanked first, so a word inside a string is no command, and a
/// trailing comment is dropped; a Quit with no value, also one that ends a block on its line, is fine.
ClassMethod ToolProblem(extendsResult As %Boolean, text As %String) As %String [ Private ]
{
	Set problems = ""
	If 'extendsResult Set problems = "does not extend OcuTalon.Tools.Result"
	Set returned = 0
	Set encoded = 0
	Set lines = ##class(OcuTalon.Test.Bridge.Source).CodeLines(text)
	Set position = 0
	While $ListNext(lines, position, line) {
		Set code = ..WithoutStrings(line)
		Set comment = $Locate(code, "(^|\s)(//|;|#;)")
		If comment Set code = $Extract(code, 1, comment - 1)
		If $Locate(code, "(?i)(^|[\s{;])(quit|return)(:\S+)?\s+(?!\.\.return\()[^\s}]") Set returned = returned + 1
		If $Locate(line, ..#PREENCODED) Set encoded = encoded + 1
	}
	If returned Set problems = problems _ $Select(problems = "": "", 1: "; ") _ returned _ " line(s) quit or return a value other than ..Return("
	If encoded Set problems = problems _ $Select(problems = "": "", 1: "; ") _ encoded _ " line(s) pass a pre-encoded JSON text to ..Return("
	Quit problems
}

/// The line with the text of each string literal removed: only the quotes stay, so that a word inside a string is not read as code.
ClassMethod WithoutStrings(line As %String) As %String [ Private ]
{
	Set out = ""
	Set inside = 0
	For i = 1:1:$Length(line) {
		Set char = $Extract(line, i)
		If char = """" {
			Set inside = 'inside
			Set out = out _ char
		} ElseIf 'inside {
			Set out = out _ char
		}
	}
	Quit out
}

/// The compiled classes of the package OcuTalon.Tools that extend %AI.Tool, OcuTalon.Tools.Result left out, in the order of their names, as a list: the tool
/// providers and the toolsets (toolsets 1), or the providers only (toolsets 0). A toolset is a class that extends %AI.ToolSet. With all 1, every compiled
/// class of the package instead, a helper and Result included: the sweeps of the package's code use it. Test.Bridge.Gate uses this inventory for the
/// governance test of the built-in tools.
ClassMethod ToolClasses(toolsets As %Boolean = 1, all As %Boolean = 0) As %List
{
	Set classes = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'OcuTalon.Tools.' ORDER BY Name")
	While result.%Next() {
		Set class = result.%GetData(1)
		If '##class(%Dictionary.CompiledClass).%ExistsId(class) Continue
		If all {
			Set classes = classes _ $ListBuild(class)
			Continue
		}
		If class = "OcuTalon.Tools.Result" Continue
		If '..ClassExtends(class, "%AI.Tool") Continue
		If 'toolsets && ..ClassExtends(class, "%AI.ToolSet") Continue
		Set classes = classes _ $ListBuild(class)
	}
	Quit classes
}

/// The names of the tools of the class that have the generic step label, as a list: its discovery gives each tool with its provider and its name, and
/// StepBuffer.LabelFor reads the label of that pair.
ClassMethod UnlabelledTools(class As %String) As %List [ Private ]
{
	Set bad = ""
	Set iterator = $ClassMethod(class, "%New").%Discover().tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		If ##class(OcuTalon.Bridge.Adapter.StepBuffer).LabelFor(tool.provider, tool.name) = ##class(OcuTalon.Bridge.Adapter.StepBuffer).#GENERICLABEL Set bad = bad _ $ListBuild(tool.name)
	}
	Quit bad
}

/// 1 when the compiled class extends the base. A class with no superclass has no %Extends method and extends none.
ClassMethod ClassExtends(class As %String, base As %String) As %Boolean [ Private ]
{
	If '##class(%Dictionary.CompiledMethod).%ExistsId(class_"||%Extends") Quit 0
	Quit ''$ClassMethod(class, "%Extends", base)
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

/// 1 when the class is one of CALLBACKHELPERS, or is or extends one of CALLBACKBASES, the bases of the classes that run in AI Hub's callbacks
/// (a class of no superclass, such as a host sink, included); a class that %Extends cannot be asked of is none of them.
ClassMethod IsCallbackClass(class As %String) As %Boolean [ Private ]
{
	If $ListFind($ListFromString(..#CALLBACKHELPERS), class) Quit 1
	Set is = 0
	Set bases = $ListFromString(..#CALLBACKBASES)
	Set position = 0
	While $ListNext(bases, position, base) {
		Try {
			Set is = ''$ClassMethod(class, "%Extends", base)
		} Catch {
			Set is = 0
		}
		If is Quit
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
