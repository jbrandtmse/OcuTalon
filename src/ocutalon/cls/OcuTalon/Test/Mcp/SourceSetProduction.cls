/// The source-poll verbs of OcuTalon.Mcp.Ops through the running production (Story 22.5, QA; AD-1, AD-17, AD-18, AD-21). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): it needs the running OcuTalon.Production and its McpOps item, which a slot never has. Where they do not run, every test fails with that reason, so that a broken
/// start can never give a green shard. Test.Mcp.SourceSet pins the handlers through a probe; this class pins the real path, which the probe cannot: Commands.Submit, the real
/// CommandsIn route and its origin rule, the McpOps job's own message map and its real audit writer, and the answer that goes back to CommandsIn.
/// Each test makes its own fixtures (a server row zzsrcp<n>, its tool rows and a fixture session through Test.Core.InProduction) and OnAfterOneTest removes the source rows,
/// the tool rows, the server row and, with OnAfterAllTests, the sessions, whether the test passed or failed.
///   - TestSetUpdateRemove: a SetSourcePoll from web_admin is carried out by the real McpOps (saved, the row of the session, the MCP entry source_set created with no argument in it),
///     the same name again is an update that keeps the Ref, and a RemoveSourcePoll from another admin's session removes the row (source_removed); each answer is one response header
///     from McpOps to CommandsIn that is not an error, each change sends the Checks item one CheckChanged, and a second removal is not_found;
///   - TestRefusalsAtTheRoute: from web_user and from tool both verbs are refused by CommandsIn and never reach McpOps; a risky tool reaches McpOps and is refused not_read_only;
///     nothing is written, audited or sent to Checks by any of them;
///   - TestOnlineDemoReal: with the real onlineDemo setting on, both verbs that reach the real McpOps are not_allowed, with no row written or removed; the setting is put back.
Class OcuTalon.Test.Mcp.SourceSetProduction Extends OcuTalon.Test.Core.InProduction
{

Parameter USER = "zzsrcpadmin";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

/// The server names the test made, comma-separated, for the clean-up.
Property Names As %String(MAXLEN = "");

/// The number of the test, in the names of its servers.
Property Serial As %Integer;

/// The mark of the audit log when the test began.
Property AuditMark As %String;

/// What the public online-demo flag held before the test, and 1 once a test has changed it.
Property SavedDemo As %String;

Property DemoSaved As %Boolean [ InitialExpression = 0 ];

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Names = ""
	Set ..DemoSaved = 0
	Set ..Serial = $Increment(^OcuTalonTest("McpSourceProduction", "n"))
	Set ..AuditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..DemoSaved Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedDemo)
	Set ..DemoSaved = 0
	Do ..Clean()
	Do $$$AssertEquals(..Leftovers(), "", "the test leaves no source row, tool row or server row behind")
	Quit $SYSTEM.Status.OK()
}

/// Set, update and remove through Commands.Submit with origin web_admin, carried out by the real McpOps item.
Method TestSetUpdateRemove()
{
	If '..Guard() Quit
	If '..McpOpsRuns() Quit
	Set server = ..MakeRows()
	Set admin = ..Session("a")
	Set other = ..Session("b")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(admin).TraceRef
	Set sent = ..Sent()
	Set changes = ..SentToChecks()
	Set result = ..Submit(..SetCommand(server, "zz_lookup", "Jira", "{""q"": ""zzsrcpsecretvalue""}", 15, admin), "web_admin")
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "1|saved|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGESAVED, "the set is carried out by McpOps")
	Do $$$AssertEquals(..Sent(), sent + 1, "the command reached McpOps once")
	Do $$$AssertEquals(..SentToChecks(), changes + 1, "and McpOps sent the Checks item one CheckChanged")
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(result.Ref)
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "the answer's Ref names a row")
		Quit
	}
	Do $$$AssertEquals(row.Kind _ "|" _ row.SessionRef _ "|" _ row.Server _ "|" _ row.Tool _ "|" _ row.DisplayName _ "|" _ row.IntervalMinutes _ "|" _ row.Arguments, "source|" _ admin _ "|" _ server _ "|zz_lookup|Jira|15|{""q"":""zzsrcpsecretvalue""}", "the row is the source of the admin's session, with the arguments as canonical JSON")
	Do $$$AssertEquals(row.AskedBy, ..#USER, "it names the acting user")
	Set answers = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 2, "McpOps", "CommandsIn")
	Do $$$AssertEquals(answers.%Size(), 1, "McpOps answers CommandsIn with one response header")
	If answers.%Size() = 1 Do $$$AssertEquals(answers.%Get(0).isError, 0, "that is not an error")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server)
	Do $$$AssertEquals(entries.%Size(), 1, "one MCP entry names the server")
	If entries.%Size() = 1 {
		Set data = entries.%Get(0).data
		Do $$$AssertEquals(data.change _ "|" _ data.outcome _ "|" _ data.tool _ "|" _ data.irisUser, "source_set|created|zz_lookup|" _ ..#USER, "it says source_set, created, for the tool, by the acting user")
		Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(..AuditMark, "OcuTalon", , , "zzsrcpsecretvalue").%Size(), 0, "no audit entry holds an argument value")
	}
	// the update
	Set update = ..Submit(..SetCommand(server, "zz_lookup", "Jira", "{}", 30, admin), "web_admin")
	Do $$$AssertEquals(update.Ok _ "|" _ update.Outcome _ "|" _ (update.Ref = result.Ref), "1|saved|1", "the same name again is an update that keeps the Ref")
	Kill row
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(result.Ref)
	Do $$$AssertEquals(row.IntervalMinutes _ "|" _ row.Arguments _ "|" _ ..Rows(admin), "30|{}|1", "with the new values and one row")
	Do $$$AssertEquals(..SentToChecks(), changes + 2, "and one more CheckChanged")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server, , 2)
	Do $$$AssertEquals(entries.%Size() _ "|" _ entries.%Get(entries.%Size() - 1).data.outcome, "2|updated", "the second entry says updated")
	// the removal from another admin's session
	Set remove = ..Submit(..RemoveCommand(result.Ref, other), "web_admin")
	Do $$$AssertEquals(remove.Ok _ "|" _ remove.Outcome _ "|" _ remove.Message, "1|removed|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGESOURCEREMOVED, "another admin's removal is carried out")
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(result.Ref), 0, "the row is gone")
	Do $$$AssertEquals(..SentToChecks(), changes + 3, "and one more CheckChanged")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server, , 3)
	Do $$$AssertEquals(entries.%Size() _ "|" _ entries.%Get(entries.%Size() - 1).data.change _ "|" _ entries.%Get(entries.%Size() - 1).data.outcome, "3|source_removed|removed", "the third entry says source_removed")
	Set again = ..Submit(..RemoveCommand(result.Ref, other), "web_admin")
	Do $$$AssertEquals(again.Ok _ "|" _ again.Outcome _ "|" _ again.Message, "0|not_found|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENOSOURCE, "a second removal is not_found")
}

/// The route's origin rule and McpOps' classification rule, over the running production: nothing is written or audited.
Method TestRefusalsAtTheRoute()
{
	If '..Guard() Quit
	If '..McpOpsRuns() Quit
	Set server = ..MakeRows()
	Set admin = ..Session("a")
	Set made = ..Submit(..SetCommand(server, "zz_lookup", "Jira", "{}", 15, admin), "web_admin")
	Do $$$AssertEquals(made.Outcome, "saved", "control: a source exists")
	Set audits = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server).%Size()
	Set sent = ..Sent()
	Set changes = ..SentToChecks()
	Set adminOnly = "0|not_allowed|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGEADMINONLY
	Set fromTool = "0|not_allowed|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTFROMTOOL
	Set result = ..Submit(..SetCommand(server, "zz_lookup", "Wiki", "{}", 15, admin), "web_user")
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, adminOnly, "a SetSourcePoll from web_user is refused")
	Set result = ..Submit(..SetCommand(server, "zz_lookup", "Wiki", "{}", 15, admin), "tool")
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, fromTool, "a SetSourcePoll from tool is refused")
	Set result = ..Submit(..RemoveCommand(made.Ref, admin), "web_user")
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, adminOnly, "a RemoveSourcePoll from web_user is refused")
	Set result = ..Submit(..RemoveCommand(made.Ref, admin), "tool")
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, fromTool, "a RemoveSourcePoll from tool is refused")
	Do $$$AssertEquals(..Sent(), sent, "none of them reached McpOps")
	Set result = ..Submit(..SetCommand(server, "zz_risky", "Wiki", "{}", 15, admin), "web_admin")
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|not_read_only|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENOTREADONLY, "a risky tool reaches McpOps and is refused not_read_only")
	Do $$$AssertEquals(..Sent(), sent + 1, "that one reached McpOps")
	Do $$$AssertEquals(..Rows(admin) _ "|" _ ##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(made.Ref), "1|1", "the source stays and no other row was written")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(..AuditMark, "OcuTalon", "MCP", "MCP", server).%Size(), audits, "no refusal wrote an audit entry")
	Do $$$AssertEquals(..SentToChecks(), changes, "and none sent a CheckChanged")
}

/// The online demo through the real McpOps: both verbs are not_allowed, whatever the session, and nothing is written or removed.
Method TestOnlineDemoReal()
{
	If '..Guard() Quit
	If '..McpOpsRuns() Quit
	Set server = ..MakeRows()
	Set admin = ..Session("a")
	Set made = ..Submit(..SetCommand(server, "zz_lookup", "Jira", "{}", 15, admin), "web_admin")
	Do $$$AssertEquals(made.Outcome, "saved", "control: a source exists before the demo is switched on")
	Set audits = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server).%Size()
	Set ..SavedDemo = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..DemoSaved = 1
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set refused = "0|not_allowed|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTALLOWED
	Set result = ..Submit(..SetCommand(server, "zz_lookup", "Wiki", "{}", 15, admin), "web_admin")
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "a SetSourcePoll is refused while the onlineDemo setting is 1")
	Set result = ..Submit(..RemoveCommand(made.Ref, admin), "web_admin")
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "a RemoveSourcePoll is refused")
	Do $$$AssertEquals(..Rows(admin) _ "|" _ ##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(made.Ref), "1|1", "no row was written or removed")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(..AuditMark, "OcuTalon", "MCP", "MCP", server).%Size(), audits, "and nothing was audited")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedDemo)
	Set ..DemoSaved = 0
	Set result = ..Submit(..SetCommand(server, "zz_lookup", "Wiki", "{}", 15, admin), "web_admin")
	Do $$$AssertEquals(result.Outcome, "saved", "with the setting back as it was the same set is carried out")
}

/// 1 when the production runs the McpOps item; otherwise the test fails with the reason and the answer is 0.
Method McpOpsRuns() As %Boolean [ Private ]
{
	If $ClassMethod(..#FIXTURE, "Jobs", "McpOps") = "" {
		Do $$$AssertTrue(0, "the production has no running McpOps item")
		Quit 0
	}
	Quit 1
}

/// Submits the command through Commands.Submit and CommandsIn with the origin; the answer is the CommandResult (a failed submission is a failed assertion).
Method Submit(command As %RegisteredObject, origin As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, origin, .result)
	Do $$$AssertStatusOK(sc, "the command reaches CommandsIn")
	If '$IsObject(result) Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Quit result
}

/// The requests that McpOps has sent to the Checks item so far (its CheckChanged messages).
Method SentToChecks() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SourceConfigName = ? AND TargetConfigName = ? AND Type = 1", "McpOps", "Checks")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The requests that CommandsIn has sent to McpOps so far.
Method Sent() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SourceConfigName = ? AND TargetConfigName = ? AND Type = 1", "CommandsIn", "McpOps")
	Do result.%Next()
	Quit +result.%GetData(1)
}

Method SetCommand(server As %String, tool As %String, name As %String, arguments As %String, interval As %String, session As %String) As OcuTalon.Msg.Command.SetSourcePoll [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SetSourcePoll).%New()
	Set command.Server = server
	Set command.Tool = tool
	Set command.Name = name
	Set command.Arguments = arguments
	Set command.IntervalMinutes = interval
	Set command.SessionRef = session
	Set command.ActingUser = ..#USER
	Set command.IdempotencyKey = "zzsrcp" _ ..Number _ "-" _ $Increment(^||ZzSrcP)
	Quit command
}

Method RemoveCommand(ref As %String, session As %String) As OcuTalon.Msg.Command.RemoveSourcePoll [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.RemoveSourcePoll).%New()
	Set command.SourceRef = ref
	Set command.SessionRef = session
	Set command.ActingUser = ..#USER
	Set command.IdempotencyKey = "zzsrcp" _ ..Number _ "-" _ $Increment(^||ZzSrcP)
	Quit command
}

/// A server row with no resource and the tools zz_lookup (read-only) and zz_risky (risky), the server's name; it is cleaned up after the test.
Method MakeRows() As %String [ Private ]
{
	Set server = "zzsrcp" _ ..Number _ "n" _ ..Serial
	Set ..Names = ..Names _ $Select(..Names = "": "", 1: ",") _ server
	Set row = ##class(OcuTalon.Mcp.Server).%New()
	Set row.Name = server
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(row.%Save(), "the fixture row " _ server _ " is saved")
	Do ..MakeTool(server, "zz_lookup", "read-only")
	Do ..MakeTool(server, "zz_risky", "risky")
	Quit server
}

Method MakeTool(server As %String, tool As %String, classification As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.ToolClassification).%New()
	Set row.Server = server
	Set row.Tool = tool
	Set row.Classification = classification
	Set row.Fingerprint = "fp"
	Set row.ChangedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(row.%Save(), "the fixture tool " _ tool _ " of " _ server _ " is saved")
}

/// The check rows of the session.
Method Rows(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// Removes the source rows of the test's servers, their tool rows and the servers' rows. Each removal is attempted whatever happened before.
Method Clean() [ Private ]
{
	For i = 1:1:$Length(..Names, ",") {
		Set name = $Piece(..Names, ",", i)
		If name = "" Continue
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.CheckRun WHERE CheckRef IN (SELECT Ref FROM OcuTalon_Data.BackgroundCheck WHERE Server = ?)", name)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.BackgroundCheck WHERE Server = ?", name)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", name)
		If ##class(OcuTalon.Mcp.Server).NameIndexExists(name, .id) Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
	}
}

/// What is left of the fixtures, as a text of places ("" when nothing).
Method Leftovers() As %String [ Private ]
{
	Set places = ""
	For i = 1:1:$Length(..Names, ",") {
		Set name = $Piece(..Names, ",", i)
		If name = "" Continue
		If ##class(OcuTalon.Mcp.Server).NameIndexExists(name) Set places = places _ $ListBuild(name _ " row")
		If ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexExists(name, "zz_lookup") Set places = places _ $ListBuild(name _ " tool rows")
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck WHERE Server = ?", name)
		Do result.%Next()
		If result.%GetData(1) > 0 Set places = places _ $ListBuild(name _ " source rows")
	}
	Quit $ListToString(places, ", ")
}

}
