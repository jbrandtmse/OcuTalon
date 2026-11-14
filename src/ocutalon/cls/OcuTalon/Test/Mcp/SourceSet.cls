/// Tests of the source-poll verbs of OcuTalon.Mcp.Ops, SetSourcePoll and RemoveSourcePoll (Story 22.5; AD-1, AD-5, AD-17, AD-18, AD-19, AD-21, AD-25). THESE TESTS RUN IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21): they write audit entries and, for a removed server, change the role OcuTalonServiceRole in %SYS. They use the probe
/// OcuTalon.Test.Mcp.OpsProbe, which restarts no runner, sends no CheckChanged (it records each) and needs no production. Each test makes its own fixtures (the servers
/// zzsrc<n>, their tool rows and a fixture session) and OnAfterOneTest removes them, and the check rows of the session, whether the test passed or failed.
///   - TestSet, TestUpdate: the row of a read-only tool, the Ref kept by an update, one CheckChanged each and the MCP entry source_set (created, updated), which holds no argument;
///   - TestSetRefusedNotReadOnly, TestSetRefused, TestSetLimits: a risky or unclassified tool and each other refusal write no row, no audit entry and no CheckChanged; the
///     limits themselves are accepted;
///   - TestSetRefusedReservedName: the name Mailbox, in any letter case and after the trim, is reserved_name and writes nothing; "My Mailbox" and "Mailboxes" are accepted (DW-1325);
///   - TestRepointMovesCreatedAt, TestSameTargetKeepsCreatedAt: an update of the server, tool or arguments moves CreatedAt to now; one of the interval or of the name's letter
///     case alone keeps it (DW-1328);
///   - TestSetRecheckUnderLock: a tool made risky, or a server removed, while the set waits for the server's lock (the probe's Lock) is refused and writes nothing;
///   - TestRemoveSource: the row, the audit entry source_removed and the CheckChanged with Stopped 1, by another admin too; no row, or another kind, is not_found;
///   - TestServerRemovedRemovesSources: RemoveMcpServer removes the sources of that server (each audited and sent) and no other server's;
///   - TestSourceAuditFails: an audit that fails undoes a set, an update and a remove (not_audited);
///   - TestSendChangedFails: a CheckChanged that cannot be sent is one warning; the set and the removal are still saved, removed, answered and audited;
///   - TestServerRemovedSourceFails: a source whose removal cannot be audited stays and the server's removal stands; the loop goes on to the server's other sources;
///   - TestWatchOpsRemoveSourceKind: Watch.Ops RemoveSource leaves a production or queues row alone, and SourcesOf matches the server's name exactly;
///   - TestOnlineDemoSources: on the online demo (the probe's switch, and the real onlineDemo setting) both verbs are not_allowed and no row is written;
///   - TestCoverageReadsTheSource: Checks.Coverage.Build reads the row that McpOps wrote (with no run it was missed; runs 15 minutes apart pass by its interval), and
///     Live.Payload.Check carries its interval.
Class OcuTalon.Test.Mcp.SourceSet Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Mcp.OpsProbe";

Parameter SENDER = "CommandsIn";

Parameter USER = "zzsrcadmin";

Parameter URL = "https://example.invalid/mcp";

/// The server names the test made, comma-separated, for the clean-up.
Property Names As %String(MAXLEN = "");

/// The Refs of the fixture sessions, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The number of the test, in the names of its servers.
Property Number As %Integer;

/// The mark of the audit log when the test began.
Property AuditMark As %String;

/// What the public online-demo flag held before the test, and 1 once a test has changed it.
Property SavedDemo As %String;

Property DemoSaved As %Boolean [ InitialExpression = 0 ];

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^||ZzOps
	Set ..Names = ""
	Set ..Sessions = ""
	Set ..DemoSaved = 0
	Set ..Number = $Increment(^OcuTalonTest("McpSource", "n"))
	Set ..AuditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..DemoSaved Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedDemo)
	Set ..DemoSaved = 0
	Do ..Clean()
	Do $$$AssertEquals(..Leftovers(), "", "the test leaves no row or session behind")
	Do $ClassMethod("OcuTalon.Test.Digest.CoverageProbe", "Reset")
	Kill ^||ZzOps
	Quit $$$OK
}

/// The row of a read-only tool: every value, the Ref, one CheckChanged and the audit entry.
Method TestSet()
{
	Set server = ..Server("a")
	Do ..MakeRows(server)
	Set session = ..MakeSession()
	Set result = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{""q"": ""mine""}", 15, session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "1|saved|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGESAVED, "the set is answered saved")
	Do $$$AssertEquals($Length(result.Ref), 22, "with the row's Ref")
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(result.Ref)
	Do $$$AssertTrue($IsObject(row), "the row is written")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.Kind _ "|" _ row.SessionRef _ "|" _ row.Server _ "|" _ row.Tool _ "|" _ row.DisplayName _ "|" _ row.AskedBy, "source|" _ session _ "|" _ server _ "|zz_lookup|Jira|" _ ..#USER, "it is a source of the session, with the server, the tool, the name and the acting user")
	Do $$$AssertEquals(row.Arguments _ "|" _ row.IntervalMinutes, "{""q"":""mine""}|15", "the arguments are the normal JSON text, and the interval is kept")
	Do $$$AssertTrue(row.CreatedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "CreatedAt is a UTC time")
	Do $$$AssertEquals(row.NextDueAt, row.CreatedAt, "and the source is due at once")
	Do $$$AssertEquals(row.LastRunAt _ "|" _ row.Result _ "|" _ row.Finding _ "|" _ row.Reported, "|||", "with empty run fields")
	Do $$$AssertEquals(..Rows(session), 1, "one row")
	Set changes = ##class(OcuTalon.Test.Mcp.OpsProbe).Changes()
	Do $$$AssertEquals(changes.%Size(), 1, "one CheckChanged is sent")
	If changes.%Size() = 1 {
		Set one = changes.%Get(0)
		Do $$$AssertEquals(one.ref _ "|" _ one.session _ "|" _ one.stopped _ "|" _ one.kind _ "|" _ one.namespace _ "|" _ one.production _ "|" _ one.displayName, result.Ref _ "|" _ session _ "|0|source|||Jira", "for the row, a start, of the kind source, with no namespace or production")
	}
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server)
	Do $$$AssertEquals(entries.%Size(), 1, "one MCP entry names the server")
	If entries.%Size() = 1 {
		Set data = entries.%Get(0).data
		Do $$$AssertEquals(data.change _ "|" _ data.server _ "|" _ data.tool _ "|" _ data.outcome _ "|" _ data.irisUser _ "|" _ data.channel _ "|" _ data.sessionRef, "source_set|" _ server _ "|zz_lookup|created|" _ ..#USER _ "|web|" _ session, "it says source_set, created, and names the tool, the acting user, the channel and the session")
		Do $$$AssertTrue((data.%ToJSON() _ entries.%Get(0).description) '[ "mine", "and holds no argument")
	}
}

/// A repeat of the name (in any letter case) updates the row and keeps its Ref.
Method TestUpdate()
{
	Set server = ..Server("a")
	Do ..MakeRows(server)
	Set session = ..MakeSession()
	Set first = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{""q"": ""mine""}", 15, session))
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(first.Ref)
	Set created = row.CreatedAt
	Set row.NextDueAt = "2000-01-01T00:00:00Z"
	Set row.Result = "passed"
	Do $$$AssertStatusOK(row.%Save(), "the row is moved to the past, with a result")
	Set second = ..Run(..#SENDER, ..SetCommand(server, "zz_other", "jira", "{""q"": ""changed""}", 30, session))
	Do $$$AssertEquals(second.Ok _ "|" _ second.Outcome _ "|" _ second.Ref, "1|saved|" _ first.Ref, "the update is answered saved with the same Ref")
	Do $$$AssertEquals(..Rows(session), 1, "there is still one row")
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(first.Ref)
	Do $$$AssertEquals(row.DisplayName _ "|" _ row.Tool _ "|" _ row.Arguments _ "|" _ row.IntervalMinutes, "jira|zz_other|{""q"":""changed""}|30", "the values and the name as last given are stored")
	Do $$$AssertEquals(row.CreatedAt _ "|" _ row.Result, created _ "|passed", "CreatedAt and the run fields are kept")
	Do $$$AssertTrue(row.NextDueAt ] "2020-01-01T00:00:00Z", "and the source is due now: " _ row.NextDueAt)
	Set changes = ##class(OcuTalon.Test.Mcp.OpsProbe).Changes()
	Do $$$AssertEquals(changes.%Size(), 2, "one CheckChanged for each set")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server, , 2)
	Set outcomes = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set outcomes = outcomes _ $ListBuild(entry.data.change _ ":" _ entry.data.outcome)
		Do $$$AssertTrue((entry.data.%ToJSON() _ entry.description) '[ "changed", "an entry holds no argument")
	}
	Do $$$AssertEquals($ListToString(outcomes), "source_set:created,source_set:updated", "the audit log holds the creation and the update")
}

/// The classification check: a risky and an unclassified tool are refused and nothing is written.
Method TestSetRefusedNotReadOnly()
{
	Set server = ..Server("a")
	Do ..MakeRows(server)
	Set session = ..MakeSession()
	Set refused = "0|not_read_only|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENOTREADONLY
	For tool = "zz_risky", "zz_new" {
		Set result = ..Run(..#SENDER, ..SetCommand(server, tool, "Jira", "{}", 15, session))
		Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, tool _ " is refused as not read-only")
	}
	Do $$$AssertEquals(..Rows(session), 0, "no row is written")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Changes().%Size(), 0, "no CheckChanged is sent")
	Do $$$AssertEquals(..Entries(server).%Size(), 0, "and no audit entry is written")
}

/// Every other refusal writes no row, no audit entry and no CheckChanged.
Method TestSetRefused()
{
	Set server = ..Server("a")
	Do ..MakeRows(server)
	Set session = ..MakeSession()
	Set tool = "zz_lookup"
	Set wrongSender = "0|not_allowed|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGEADMINONLY
	Set fromTool = "0|not_allowed|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTFROMTOOL
	Set failed = "0|failed|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED
	Set long = $Translate($Justify("", 101), " ", "n")
	// the server and the tool
	Do ..Refuse(..SetCommand("zzsrcnone" _ ..Number, tool, "Jira", "{}", 15, session), ..#SENDER, "0|not_found|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENOSERVER, "an unknown server")
	Do ..Refuse(..SetCommand("x;y", tool, "Jira", "{}", 15, session), ..#SENDER, "0|not_found|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENOSERVER, "a server name that is not a name")
	Do ..Refuse(..SetCommand("", tool, "Jira", "{}", 15, session), ..#SENDER, "0|not_found|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENOSERVER, "an empty server")
	Do ..Refuse(..SetCommand(server, "zz_none", "Jira", "{}", 15, session), ..#SENDER, "0|not_found|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENOTOOL, "an unknown tool")
	Do ..Refuse(..SetCommand(server, "ZZ_LOOKUP", "Jira", "{}", 15, session), ..#SENDER, "0|not_found|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENOTOOL, "a tool name in another letter case")
	// the name
	Set badName = "0|bad_name|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGESOURCENAME
	Do ..Refuse(..SetCommand(server, tool, "", "{}", 15, session), ..#SENDER, badName, "an empty name")
	Do ..Refuse(..SetCommand(server, tool, "   ", "{}", 15, session), ..#SENDER, badName, "a blank name")
	Do ..Refuse(..SetCommand(server, tool, long, "{}", 15, session), ..#SENDER, badName, "a name of 101 characters")
	Do ..Refuse(..SetCommand(server, tool, "Ji" _ $Char(9) _ "ra", "{}", 15, session), ..#SENDER, badName, "a name with a tab")
	Do ..Refuse(..SetCommand(server, tool, "Ji" _ $Char(7) _ "ra", "{}", 15, session), ..#SENDER, badName, "a name with a control character")
	// the arguments
	Set badArguments = "0|bad_arguments|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGESOURCEARGUMENTS
	Set over = "{""a"":""" _ $Translate($Justify("", 3993), " ", "x") _ """}"
	For case = "[1]", "{bad", "5", """text""", "null", "true", "{""k"":""secret://wallet#key""}", "{""k"":""SECRET://wallet#key""}", "{""k"":""Secret://wallet""}", "{""k"":""secret:\/\/wallet""}", "{""k"":""secret://wallet""}", "{""k"":""@{wallet}""}", "{""@{"":1}", over {
		Do ..Refuse(..SetCommand(server, tool, "Jira", case, 15, session), ..#SENDER, badArguments, "the arguments " _ $Extract(case, 1, 30))
	}
	// the interval
	Set badInterval = "0|bad_interval|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGESOURCEINTERVAL
	For case = 4, 1441, 0, -5, "", "abc", 15.5, 100000 {
		Do ..Refuse(..SetCommand(server, tool, "Jira", "{}", case, session), ..#SENDER, badInterval, "the interval '" _ case _ "'")
	}
	// the sender, the origin, the acting user and the session
	Do ..Refuse(..SetCommand(server, tool, "Jira", "{}", 15, session), "SomeoneElse", wrongSender, "a sender other than CommandsIn")
	Do ..Refuse(..SetCommand(server, tool, "Jira", "{}", 15, session, "web_user"), ..#SENDER, wrongSender, "the origin web_user")
	Do ..Refuse(..SetCommand(server, tool, "Jira", "{}", 15, session, "tool"), ..#SENDER, fromTool, "the origin tool")
	Do ..Refuse(..SetCommand(server, tool, "Jira", "{}", 15, session, "web_admin", ""), ..#SENDER, wrongSender, "no acting user")
	Do ..Refuse(..SetCommand(server, tool, "Jira", "{}", 15, "zzNoSuchSession" _ ..Number), ..#SENDER, failed, "an unknown session")
	Do ..Refuse(..SetCommand(server, tool, "Jira", "{}", 15, ""), ..#SENDER, failed, "no session")
	Set ^||ZzOps("demo") = 1
	Do ..Refuse(..SetCommand(server, tool, "Jira", "{}", 15, session), ..#SENDER, "0|not_allowed|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTALLOWED, "the online demo")
	Set ^||ZzOps("demo") = 0
	Do $$$AssertEquals(..Entries(server).%Size(), 0, "no refusal wrote an audit entry")
	Do $$$AssertEquals(..Rows(session), 0, "and none wrote a row")
	// the control: the same command, valid, is carried out
	Set result = ..Run(..#SENDER, ..SetCommand(server, tool, "Jira", "{}", 15, session))
	Do $$$AssertEquals(result.Outcome, "saved", "the same command with valid values is carried out")
}

/// The limits themselves are accepted, and the stored values are the normal ones.
Method TestSetLimits()
{
	Set server = ..Server("a")
	Do ..MakeRows(server)
	Set session = ..MakeSession()
	Set long = $Translate($Justify("", 100), " ", "n")
	Set exact = "{""a"":""" _ $Translate($Justify("", 3992), " ", "x") _ """}"
	Do $$$AssertEquals($Length(exact), 4000, "control: the arguments are 4000 characters")
	Set cases = $ListBuild($ListBuild(long, "{}", 5, long, "{}"), $ListBuild("Five", "", 1440, "Five", "{}"), $ListBuild("Exact", exact, 15, "Exact", exact), $ListBuild("  Trim  ", " { ""q"" : [ 1 , 2 ] } ", 60, "Trim", "{""q"":[1,2]}"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set result = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", $List(case, 1), $List(case, 2), $List(case, 3), session))
		Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "1|saved", "the name '" _ $Extract($List(case, 1), 1, 12) _ "' with interval " _ $List(case, 3) _ " is saved")
		Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(result.Ref)
		If $IsObject(row) Do $$$AssertEquals(row.DisplayName _ "|" _ row.Arguments _ "|" _ row.IntervalMinutes, $List(case, 4) _ "|" _ $List(case, 5) _ "|" _ $List(case, 3), "the stored name, arguments and interval are the normal ones")
	}
	Do $$$AssertEquals(..Rows(session), 4, "four rows")
}

/// The re-check under the server's lock: a tool made risky, or a server removed, after the early check and before the lock is refused, and nothing is written.
Method TestSetRecheckUnderLock()
{
	Set server = ..Server("a")
	Do ..MakeRows(server)
	Set session = ..MakeSession()
	Set ^||ZzOps("beforeLock") = "risky"
	Set result = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{}", 15, session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|not_read_only|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENOTREADONLY, "a tool made risky while the set waits for the lock is refused")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, "zz_lookup").Classification, "risky", "control: the probe made the tool risky")
	Set other = ..Server("b")
	Do ..MakeRows(other)
	Set ^||ZzOps("beforeLock") = "gone"
	Set result = ..Run(..#SENDER, ..SetCommand(other, "zz_lookup", "Jira", "{}", 15, session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|not_found|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENOSERVER, "a server removed while the set waits for the lock is not_found")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Server).NameIndexExists(other), 0, "control: the probe removed the server")
	Do $$$AssertEquals(..Rows(session) _ "|" _ ##class(OcuTalon.Test.Mcp.OpsProbe).Changes().%Size() _ "|" _ ..Entries(server).%Size() _ "|" _ ..Entries(other).%Size(), "0|0|0|0", "no row, CheckChanged or audit entry is written")
}

/// The removal by Ref, from any admin: the row, the audit entry and the CheckChanged with Stopped 1; no row, or another kind, is not_found.
Method TestRemoveSource()
{
	Set server = ..Server("a")
	Do ..MakeRows(server)
	Set session = ..MakeSession()
	Set first = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{""q"": ""mine""}", 15, session))
	Set second = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Other", "{}", 30, session))
	Set other = ..MakeSession()
	Set production = ##class(OcuTalon.Data.BackgroundCheck).%New()
	Set production.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set production.SessionRef = session
	Set production.Kind = "production"
	Set production.Namespace = "ZZNS"
	Set production.Production = "Zz.Production"
	Set production.DisplayName = "Zz production"
	Do $$$AssertStatusOK(production.%Save(), "a production row of the session is saved")
	Do ..Clear()
	Set result = ..Run(..#SENDER, ..RemoveCommand(first.Ref, other, "zzsrcsecond"))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "1|removed|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGESOURCEREMOVED, "another admin's removal is answered removed")
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(first.Ref) _ "|" _ ##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(second.Ref), "0|1", "the row is gone and the other source stays")
	Set changes = ##class(OcuTalon.Test.Mcp.OpsProbe).Changes()
	Do $$$AssertEquals(changes.%Size(), 1, "one CheckChanged is sent")
	If changes.%Size() = 1 {
		Set one = changes.%Get(0)
		Do $$$AssertEquals(one.ref _ "|" _ one.session _ "|" _ one.stopped _ "|" _ one.kind _ "|" _ one.displayName, first.Ref _ "|" _ session _ "|1|source|Jira", "for the removed source, of the owner's session, stopped")
	}
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server, , 3)
	Set changed = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set changed = changed _ $ListBuild(entry.data.change _ ":" _ entry.data.outcome)
		If entry.data.change = "source_removed" Do $$$AssertEquals(entry.data.irisUser _ "|" _ entry.data.sessionRef _ "|" _ entry.data.tool _ "|" _ entry.data.channel, "zzsrcsecond|" _ other _ "|zz_lookup|web", "the removal names the acting admin and the command's session")
	}
	Do $$$AssertEquals($ListToString(changed), "source_set:created,source_set:created,source_removed:removed", "the audit log holds the two sets and the removal")
	Do ..Clear()
	Set count = ..Entries(server).%Size()
	Set missing = "0|not_found|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENOSOURCE
	For ref = first.Ref, "", "zzNoSuchRef", production.Ref {
		Set result = ..Run(..#SENDER, ..RemoveCommand(ref, session))
		Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, missing, "removing '" _ ref _ "' is not_found")
	}
	Do $$$AssertTrue(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(production.Ref), "a row of another kind is not removed")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Changes().%Size() _ "|" _ ..Entries(server).%Size(), "0|" _ count, "and no CheckChanged or audit entry is written")
	Set result = ..Run("SomeoneElse", ..RemoveCommand(second.Ref, session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|not_allowed|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGEADMINONLY, "a removal from another sender is refused")
	Set result = ..Run(..#SENDER, ..RemoveCommand(second.Ref, session, , "tool"))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|not_allowed|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTFROMTOOL, "a removal from a tool is refused")
	Do $$$AssertTrue(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(second.Ref), "the source is still there after the refused removals")
}

/// RemoveMcpServer removes the sources of that server, each audited and sent, after the removal; another server's source stays.
Method TestServerRemovedRemovesSources()
{
	Set server = ..Server("a")
	Set other = ..Server("b")
	Do ..Run(..#SENDER, ..AddCommand(server))
	Do ..MakeTool(server, "zz_lookup", "read-only")
	Do ..MakeRows(other)
	Set session = ..MakeSession()
	Set one = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{}", 15, session))
	Set two = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Wiki", "{}", 20, session))
	Set kept = ..Run(..#SENDER, ..SetCommand(other, "zz_lookup", "Kept", "{}", 25, session))
	Do $$$AssertEquals(one.Outcome _ "|" _ two.Outcome _ "|" _ kept.Outcome, "saved|saved|saved", "control: the three sources are saved")
	Do ..Clear()
	Set admin = ..MakeSession()
	Set result = ..Run(..#SENDER, ..RemoveServerCommand(server, admin))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "1|removed", "the server's removal is answered removed")
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(one.Ref) _ "|" _ ##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(two.Ref) _ "|" _ ##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(kept.Ref), "0|0|1", "its sources are gone and the other server's source stays")
	Set changes = ##class(OcuTalon.Test.Mcp.OpsProbe).Changes()
	Do $$$AssertEquals(changes.%Size(), 2, "one CheckChanged for each removed source")
	Set refs = ""
	Set iterator = changes.%GetIterator()
	While iterator.%GetNext(, .change) {
		Do $$$AssertEquals(change.session _ "|" _ change.stopped _ "|" _ change.kind, session _ "|1|source", "each is a stop of the source of the session")
		Set refs = refs _ $ListBuild(change.ref)
	}
	Do $$$AssertEquals($ListToString($ListBuild($Select($ListFind(refs, one.Ref): "one", 1: ""), $Select($ListFind(refs, two.Ref): "two", 1: ""))), "one,two", "for the two sources of the server")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server, , 6)
	Set changed = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set changed = changed _ $ListBuild(entry.data.change)
		If entry.data.change = "source_removed" Do $$$AssertEquals(entry.data.irisUser _ "|" _ entry.data.sessionRef _ "|" _ entry.data.channel _ "|" _ entry.data.server _ "|" _ entry.data.tool _ "|" _ entry.data.outcome, ..#USER _ "|" _ admin _ "|web|" _ server _ "|zz_lookup|removed", "a cascaded removal names the admin who removed the server, the command's session and channel, the server, the tool and the outcome removed")
	}
	Do $$$AssertEquals($ListToString(changed), "added,source_set,source_set,removed,source_removed,source_removed", "the audit log holds the server's removal, then the removal of each source")
	Do $$$AssertEquals(..Entries(other).%Size(), 1, "the other server has only the entry of its own source")
}

/// An audit entry that cannot be written undoes the set, the update and the removal.
Method TestSourceAuditFails()
{
	Set server = ..Server("a")
	Do ..MakeRows(server)
	Set session = ..MakeSession()
	Set failed = "0|not_audited|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED
	Set ^||ZzOps("auditError") = 1
	Set result = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{""q"":1}", 15, session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, failed, "a set whose audit fails is answered not_audited")
	Do $$$AssertEquals(..Rows(session) _ "|" _ ##class(OcuTalon.Test.Mcp.OpsProbe).Changes().%Size(), "0|0", "it writes no row and sends no CheckChanged")
	Kill ^||ZzOps("auditError")
	Set made = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{""q"":1}", 15, session))
	Do $$$AssertEquals(made.Outcome, "saved", "control: the same set is saved when the audit works")
	Do ..Clear()
	Set ^||ZzOps("auditError") = 1
	Set result = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{""q"":2}", 30, session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, failed, "an update whose audit fails is answered not_audited")
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(made.Ref)
	Do $$$AssertEquals(row.Arguments _ "|" _ row.IntervalMinutes, "{""q"":1}|15", "and the row keeps its values")
	Set result = ..Run(..#SENDER, ..RemoveCommand(made.Ref, session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, failed, "a removal whose audit fails is answered not_audited")
	Do $$$AssertTrue(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(made.Ref), "and the row is still there")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Changes().%Size(), 0, "no CheckChanged is sent for either")
	Kill ^||ZzOps("auditError")
	Set result = ..Run(..#SENDER, ..RemoveCommand(made.Ref, session))
	Do $$$AssertEquals(result.Outcome, "removed", "control: the same removal is carried out when the audit works")
}

/// A CheckChanged that cannot be sent is one warning and changes nothing else: the set and the removal are carried out and answered as when it is sent.
Method TestSendChangedFails()
{
	Set server = ..Server("a")
	Do ..MakeRows(server)
	Set session = ..MakeSession()
	Set ^||ZzOps("changedError") = 1
	Set made = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{}", 15, session))
	Do $$$AssertEquals(made.Ok _ "|" _ made.Outcome _ "|" _ made.Message, "1|saved|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGESAVED, "a set whose CheckChanged fails is still answered saved")
	Do $$$AssertEquals($Length(made.Ref), 22, "with the row's Ref")
	Do $$$AssertTrue(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(made.Ref), "and the row exists")
	Set result = ..Run(..#SENDER, ..RemoveCommand(made.Ref, session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "1|removed|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGESOURCEREMOVED, "a removal whose CheckChanged fails is still answered removed")
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(made.Ref) _ "|" _ ..Rows(session), "0|0", "and the row is gone")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Changes().%Size(), 0, "no CheckChanged was recorded as sent")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server, , 2)
	Set changed = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set changed = changed _ $ListBuild(entry.data.change _ ":" _ entry.data.outcome)
	}
	Do $$$AssertEquals($ListToString(changed), "source_set:created,source_removed:removed", "both changes are audited")
}

/// A source whose removal cannot be audited stays, with the removal of its server standing; the other sources of the server are still removed.
Method TestServerRemovedSourceFails()
{
	Set session = ..MakeSession()
	Set admin = ..MakeSession()
	// every audit of a source removal fails
	Set server = ..Server("a")
	Do ..Run(..#SENDER, ..AddCommand(server))
	Do ..MakeTool(server, "zz_lookup", "read-only")
	Do ..MakeTool(server, "zz_other", "read-only")
	Set one = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{}", 15, session))
	Set two = ..Run(..#SENDER, ..SetCommand(server, "zz_other", "Wiki", "{}", 20, session))
	Do $$$AssertEquals(one.Outcome _ "|" _ two.Outcome, "saved|saved", "control: the two sources are saved")
	Do ..Clear()
	Set ^||ZzOps("sourceAuditError") = "all"
	Set result = ..Run(..#SENDER, ..RemoveServerCommand(server, admin))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "1|removed", "the server's removal is answered removed")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Server).NameIndexExists(server), 0, "the server row is gone")
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(one.Ref) _ "|" _ ##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(two.Ref), "1|1", "both sources stay: their removals are rolled back")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Changes().%Size(), 0, "and no CheckChanged is sent for them")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", server, , 4)
	Set changed = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set changed = changed _ $ListBuild(entry.data.change)
	}
	Do $$$AssertEquals($ListToString(changed), "added,source_set,source_set,removed", "the audit log holds the server's removal and no removal of a source")
	// only the first source's audit fails: the loop goes on to the second
	Kill ^||ZzOps("sourceAuditError"), ^||ZzOps("sourceAudits")
	Set other = ..Server("b")
	Do ..Run(..#SENDER, ..AddCommand(other))
	Do ..MakeTool(other, "zz_lookup", "read-only")
	Do ..MakeTool(other, "zz_other", "read-only")
	Set first = ..Run(..#SENDER, ..SetCommand(other, "zz_lookup", "Jira", "{}", 15, session))
	Set second = ..Run(..#SENDER, ..SetCommand(other, "zz_other", "Wiki", "{}", 20, session))
	Do $$$AssertEquals(first.Outcome _ "|" _ second.Outcome, "saved|saved", "control: the two sources of the second server are saved")
	Do ..Clear()
	Set ^||ZzOps("sourceAuditError") = "first"
	Set result = ..Run(..#SENDER, ..RemoveServerCommand(other, admin))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "1|removed", "the second server's removal is answered removed")
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(first.Ref) _ "|" _ ##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(second.Ref), "1|0", "the first source stays and the second is removed")
	Set changes = ##class(OcuTalon.Test.Mcp.OpsProbe).Changes()
	Do $$$AssertEquals(changes.%Size(), 1, "one CheckChanged is sent")
	If changes.%Size() = 1 Do $$$AssertEquals(changes.%Get(0).ref _ "|" _ changes.%Get(0).stopped, second.Ref _ "|1", "for the second source")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", other, , 5)
	Set changed = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set changed = changed _ $ListBuild(entry.data.change _ ":" _ entry.data.tool)
	}
	Do $$$AssertEquals($ListToString(changed), "added:,source_set:zz_lookup,source_set:zz_other,removed:,source_removed:zz_other", "the second source's removal is audited, the first's is not")
}

/// Watch.Ops RemoveSource removes only a row of the kind source: a production or queues row is answered OK with no fields and stays; SourcesOf matches the server exactly.
Method TestWatchOpsRemoveSourceKind()
{
	Set session = ..MakeSession()
	For kind = "production", "queues" {
		Set row = ##class(OcuTalon.Data.BackgroundCheck).%New()
		Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set row.SessionRef = session
		Set row.Kind = kind
		Set row.DisplayName = "Zz " _ kind
		If kind = "production" {
			Set row.Namespace = "ZZNS"
			Set row.Production = "Zz.Production"
		}
		Do $$$AssertStatusOK(row.%Save(), "a " _ kind _ " row of the session is saved")
		Set sc = ##class(OcuTalon.Watch.Ops).RemoveSource(row.Ref, .fields)
		Do $$$AssertStatusOK(sc, "RemoveSource of the " _ kind _ " row is OK")
		Do $$$AssertEquals(fields, "", "with no fields")
		Do $$$AssertTrue(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(row.Ref), "and the " _ kind _ " row still exists")
	}
	Set server = ..Server("a")
	Do ..MakeRows(server)
	Set made = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{}", 15, session))
	Do $$$AssertEquals(made.Outcome, "saved", "control: a source of the server is saved")
	Set exact = ##class(OcuTalon.Watch.Ops).SourcesOf(server)
	Do $$$AssertEquals(exact.%Size() _ "|" _ exact.%Get(0), "1|" _ made.Ref, "SourcesOf the server's name gives its source")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Ops).SourcesOf($ZConvert(server, "U")).%Size(), 0, "and SourcesOf the same name in another letter case gives none")
}

/// The online demo: both verbs are not_allowed and no row is written, by the probe's switch and by the real setting.
Method TestOnlineDemoSources()
{
	Set server = ..Server("a")
	Do ..MakeRows(server)
	Set session = ..MakeSession()
	Set made = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{}", 15, session))
	Do $$$AssertEquals(made.Outcome, "saved", "control: a source exists before the demo is switched on")
	Do ..Clear()
	Set audited = ..Entries(server).%Size()
	Set refused = "0|not_allowed|" _ ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTALLOWED
	Set ^||ZzOps("demo") = 1
	Set result = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Wiki", "{}", 15, session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "a set on the online demo is refused")
	Set result = ..Run(..#SENDER, ..RemoveCommand(made.Ref, session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "a removal is refused")
	Do $$$AssertEquals(..Rows(session), 1, "no row was written or removed")
	Kill ^||ZzOps("demo")
	Set ..SavedDemo = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..DemoSaved = 1
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set result = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Wiki", "{}", 15, session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "a set is refused while the onlineDemo setting is 1")
	Set result = ..Run(..#SENDER, ..RemoveCommand(made.Ref, session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, refused, "a removal is refused")
	Do $$$AssertEquals(..Rows(session) _ "|" _ ##class(OcuTalon.Test.Mcp.OpsProbe).Changes().%Size() _ "|" _ ..Entries(server).%Size(), "1|0|" _ audited, "no row was written or removed, and nothing was sent or audited")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedDemo)
	Set ..DemoSaved = 0
	Set result = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Wiki", "{}", 15, session))
	Do $$$AssertEquals(result.Outcome, "saved", "with the setting back as it was the same set is carried out")
}

/// The Integration AC: Checks.Coverage.Build reads the row that McpOps wrote, and the check payload carries its interval.
Method TestCoverageReadsTheSource()
{
	Set server = ..Server("a")
	Do ..MakeRows(server)
	Set session = ..MakeSession()
	Set result = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{}", 15, session))
	Do $$$AssertEquals(result.Outcome, "saved", "the source is saved")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set from = ##class(OcuTalon.Data.Time).AddSeconds(now, -600)
	Do $ClassMethod("OcuTalon.Test.Digest.CoverageProbe", "Reset")
	Set sc = $ClassMethod("OcuTalon.Test.Digest.CoverageProbe", "Build", session, from, now, .rows, .lines, .vitals)
	Do $$$AssertStatusOK(sc, "Build is OK")
	Do $$$AssertEquals(rows.%Size(), 6, "the five vital signs and the source")
	Set row = rows.%Get(5)
	Set line = lines.%Get(5)
	Do $$$AssertEquals(row.entry _ "|" _ row.result, "Jira|not_checked", "the source is the entry Jira, and it is not checked: no run was recorded")
	Do $$$AssertEquals(line.key _ "|" _ line.slots.entry, "digest.notCheckedMissed|Jira", "with the line that says the check didn't run")
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(result.Ref)
	Set start = row.CreatedAt
	For minutes = 14, 29, 44 {
		Set insert = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO OcuTalon_Digest_Data.CheckRun (CheckRef, SessionRef, RanAt, Result, Reason, Finding) VALUES (?, ?, ?, ?, ?, ?)", result.Ref, session, ##class(OcuTalon.Data.Time).AddSeconds(start, minutes * 60), "passed", "", "")
		Do $$$AssertTrue(insert.%SQLCODE '< 0, "a passed run " _ minutes _ " minutes after the set is recorded")
	}
	Set sc = $ClassMethod("OcuTalon.Test.Digest.CoverageProbe", "Build", session, start, ##class(OcuTalon.Data.Time).AddSeconds(start, 45 * 60), .rows, .lines, .vitals)
	Do $$$AssertStatusOK(sc, "Build over 45 minutes is OK")
	Do $$$AssertEquals(rows.%Get(5).entry _ "|" _ rows.%Get(5).result _ "|" _ lines.%Get(5).key, "Jira|passed|digest.passed", "runs 15 minutes apart pass by the interval the row was given (15 x 60 + 180 seconds)")
	Set payload = ##class(OcuTalon.Live.Payload.Check).FromRow(##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(result.Ref))
	Do $$$AssertEquals(payload.Kind _ "|" _ payload.IntervalMinutes _ "|" _ payload.DisplayName, "source|15|Jira", "the payload of the row has the kind source and the interval")
	Do $$$AssertStatusOK(payload.%JSONExportToString(.json), "the payload is exported")
	Set exported = {}.%FromJSON(json)
	Do $$$AssertEquals(exported.kind _ "|" _ exported.intervalMinutes, "source|15", "as kind and intervalMinutes")
}

/// The name of the connected mailbox is reserved, in any letter case and after the trim (DW-1325): nothing is written, audited or sent; a name that only contains it is accepted.
Method TestSetRefusedReservedName()
{
	Set server = ..Server("a")
	Do ..MakeRows(server)
	Set session = ..MakeSession()
	Set reserved = "0|reserved_name|That name belongs to the connected mailbox. Choose another name."
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Ops).#MESSAGESOURCERESERVED, "That name belongs to the connected mailbox. Choose another name.", "the message is the approved text")
	Do ..Refuse(..SetCommand(server, "zz_lookup", "Mailbox", "{}", 15, session), ..#SENDER, reserved, "the name Mailbox")
	Do ..Refuse(..SetCommand(server, "zz_lookup", " mailbox ", "{}", 15, session), ..#SENDER, reserved, "the name ' mailbox '")
	Do ..Refuse(..SetCommand(server, "zz_lookup", "MAILBOX", "{}", 15, session), ..#SENDER, reserved, "the name MAILBOX")
	Do $$$AssertEquals(..Entries(server).%Size(), 0, "no refusal wrote an audit entry")
	// the checks before the name answer as they did
	Do ..Refuse(..SetCommand(server, "zz_risky", "Mailbox", "{}", 15, session), ..#SENDER, "0|not_read_only|" _ ##class(OcuTalon.Mcp.Ops).#MESSAGENOTREADONLY, "a risky tool, whatever the name")
	// a name that holds the word is another name
	For name = "My Mailbox", "Mailboxes" {
		Set result = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", name, "{}", 15, session))
		Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "1|saved", name _ " is accepted")
	}
	Do $$$AssertEquals(..Rows(session), 2, "and written")
}

/// An update that changes the server, the tool or the arguments of a source moves its CreatedAt to now (DW-1328); the Ref, the run fields and the interval stay.
Method TestRepointMovesCreatedAt()
{
	Set first = ..Server("a")
	Set second = ..Server("b")
	Do ..MakeRows(first)
	Do ..MakeRows(second)
	Set session = ..MakeSession()
	Set result = ..Run(..#SENDER, ..SetCommand(first, "zz_lookup", "Jira", "{""q"":""mine""}", 15, session))
	Set ref = result.Ref
	Set old = "2000-01-01T00:00:00Z"
	Set steps = $ListBuild($ListBuild("the server", second, "zz_lookup", "{""q"":""mine""}"), $ListBuild("the tool", second, "zz_other", "{""q"":""mine""}"), $ListBuild("the arguments", second, "zz_other", "{""q"":""changed""}"))
	Set ptr = 0
	While $ListNext(steps, ptr, step) {
		Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
		Set row.CreatedAt = old
		Set row.Result = "passed"
		Set row.Reported = "kept"
		Set row.NextDueAt = old
		Do $$$AssertStatusOK(row.%Save(), "the row is moved to the past, with a result")
		Set result = ..Run(..#SENDER, ..SetCommand($List(step, 2), $List(step, 3), "Jira", $List(step, 4), 15, session))
		Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Ref, "1|saved|" _ ref, "a change of " _ $List(step, 1) _ " is saved on the same Ref")
		Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
		Do $$$AssertTrue(row.CreatedAt ] "2020-01-01T00:00:00Z", "a change of " _ $List(step, 1) _ " moves CreatedAt to now: " _ row.CreatedAt)
		Do $$$AssertEquals(row.Result _ "|" _ row.IntervalMinutes _ "|" _ row.Reported, "passed|15|kept", "and keeps the run fields, Reported and the interval")
		Do $$$AssertTrue(row.NextDueAt ] "2020-01-01T00:00:00Z", "and makes the row due now")
	}
	Do $$$AssertEquals(..Rows(session), 1, "there is still one row")
}

/// An update that changes only the interval, or only the letter case of the name, keeps CreatedAt, the Ref and the run fields (DW-1328).
Method TestSameTargetKeepsCreatedAt()
{
	Set server = ..Server("a")
	Do ..MakeRows(server)
	Set session = ..MakeSession()
	Set first = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{""q"":""mine""}", 15, session))
	Set old = "2000-01-01T00:00:00Z"
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(first.Ref)
	Set row.CreatedAt = old
	Set row.Result = "passed"
	Set row.Reported = "kept"
	Do $$$AssertStatusOK(row.%Save(), "the row is moved to the past, with a result")
	Set result = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "Jira", "{""q"":""mine""}", 30, session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Ref, "1|saved|" _ first.Ref, "an update of the interval alone is saved on the same Ref")
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(first.Ref)
	Do $$$AssertEquals(row.CreatedAt _ "|" _ row.Result _ "|" _ row.IntervalMinutes _ "|" _ row.Reported, old _ "|passed|30|kept", "it keeps CreatedAt, the run fields and Reported")
	Set result = ..Run(..#SENDER, ..SetCommand(server, "zz_lookup", "JIRA", "{""q"":""mine""}", 30, session))
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Ref, "1|saved|" _ first.Ref, "an update of the name's letter case alone is saved on the same Ref")
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(first.Ref)
	Do $$$AssertEquals(row.DisplayName _ "|" _ row.CreatedAt _ "|" _ row.Result _ "|" _ row.Reported, "JIRA|" _ old _ "|passed|kept", "it keeps CreatedAt, the run fields and Reported")
	Do $$$AssertEquals(..Rows(session), 1, "there is still one row")
}

/// Runs the command through a probe whose request header names the sender.
Method Run(sender As %String, command As %RegisteredObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set probe = ##class(OcuTalon.Test.Mcp.OpsProbe).Shadow(sender, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.MessageHandler(command, .result)
	Do $$$AssertStatusOK(sc, "the command is delivered by the message map and answered with an OK status")
	Quit result
}

/// Runs the command, and asserts that it is answered as expected ("ok|outcome|message") and that nothing was written, audited or sent so far.
Method Refuse(command As %RegisteredObject, sender As %String, expected As %String, label As %String) [ Private ]
{
	Set result = ..Run(sender, command)
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, expected, label _ " is refused")
	Do $$$AssertEquals(..TotalRows() _ "|" _ ##class(OcuTalon.Test.Mcp.OpsProbe).Changes().%Size(), "0|0", label _ ": no row is written and no CheckChanged is sent")
}

Method SetCommand(server As %String, tool As %String, name As %String, arguments As %String, interval As %String, session As %String, origin As %String = "web_admin", user As %String = {..#USER}) As OcuTalon.Msg.Command.SetSourcePoll [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SetSourcePoll).%New()
	Set command.Server = server
	Set command.Tool = tool
	Set command.Name = name
	Set command.Arguments = arguments
	Set command.IntervalMinutes = interval
	Set command.SessionRef = session
	Set command.Origin = origin
	Set command.ActingUser = user
	Quit command
}

Method RemoveCommand(ref As %String, session As %String, user As %String = {..#USER}, origin As %String = "web_admin") As OcuTalon.Msg.Command.RemoveSourcePoll [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.RemoveSourcePoll).%New()
	Set command.SourceRef = ref
	Set command.SessionRef = session
	Set command.Origin = origin
	Set command.ActingUser = user
	Quit command
}

Method AddCommand(server As %String) As OcuTalon.Msg.Command.AddMcpServer [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.AddMcpServer).%New()
	Set command.Server = server
	Set command.Url = ..#URL
	Set command.Origin = "web_admin"
	Set command.ActingUser = ..#USER
	Quit command
}

Method RemoveServerCommand(server As %String, session As %String = "") As OcuTalon.Msg.Command.RemoveMcpServer [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.RemoveMcpServer).%New()
	Set command.Server = server
	Set command.SessionRef = session
	Set command.Origin = "web_admin"
	Set command.ActingUser = ..#USER
	Quit command
}

/// The name of a server of the test; it is cleaned up after the test.
Method Server(suffix As %String) As %String [ Private ]
{
	Set name = "zzsrc" _ ..Number _ suffix
	If '$ListFind($ListFromString(..Names), name) Set ..Names = ..Names _ $Select(..Names = "": "", 1: ",") _ name
	Quit name
}

/// A server row with no resource, and the tools zz_lookup and zz_other (read-only), zz_risky (risky) and zz_new (unclassified).
Method MakeRows(server As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.Server).%New()
	Set row.Name = server
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(row.%Save(), "the fixture row " _ server _ " is saved")
	Do ..MakeTool(server, "zz_lookup", "read-only")
	Do ..MakeTool(server, "zz_other", "read-only")
	Do ..MakeTool(server, "zz_risky", "risky")
	Do ..MakeTool(server, "zz_new", "unclassified")
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

/// A fixture session; its Ref.
Method MakeSession() As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Session).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.TraceRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Epoch = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.IrisUser = "zzsrc" _ ..Number
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.AdminAtSignIn = 1
	Do $$$AssertStatusOK(row.%Save(), "the fixture session is saved")
	Set ..Sessions = ..Sessions _ $Select(..Sessions = "": "", 1: ",") _ row.Ref
	Quit row.Ref
}

/// The check rows of the session.
Method Rows(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The check rows of every session of the test.
Method TotalRows() As %Integer [ Private ]
{
	Set total = 0
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Set total = total + ..Rows($Piece(..Sessions, ",", i))
	}
	Quit total
}

/// The MCP audit entries that name the server, written since the test began.
Method Entries(server As %String) As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Test.Bridge.AuditLog).Entries(..AuditMark, "OcuTalon", "MCP", "MCP", server)
}

/// Forgets the CheckChanged messages recorded so far.
Method Clear() [ Private ]
{
	Kill ^||ZzOps("changed")
}

/// Removes every fixture this test may have made: the check rows of its sessions, the servers' rows and tool rows (and the resources of a server added), and the
/// sessions. Each removal is attempted whatever happened before.
Method Clean() [ Private ]
{
	For i = 1:1:$Length(..Sessions, ",") {
		Set ref = $Piece(..Sessions, ",", i)
		If ref = "" Continue
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.CheckRun WHERE SessionRef = ?", ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?", ref)
		If ##class(OcuTalon.Data.Session).RefIndexExists(ref, .id) Do ##class(OcuTalon.Data.Session).%DeleteId(id)
	}
	For i = 1:1:$Length(..Names, ",") {
		Set name = $Piece(..Names, ",", i)
		If name = "" Continue
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", name)
		If ##class(OcuTalon.Mcp.Server).NameIndexExists(name, .id) Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
		Do ##class(OcuTalon.Install.Step.Mcp).Revoke(name)
		If ##class(%ConfigStore.Configuration).Exists("AI.MCP.OcuTalon_" _ name) Do ##class(%ConfigStore.Configuration).Delete("AI.MCP.OcuTalon_" _ name)
		If ##class(%Wallet.Secret).Exists("OcuTalon_MCP_" _ name _ ".Key") Do ##class(%Wallet.KeyValue).Delete("OcuTalon_MCP_" _ name _ ".Key")
		If ##class(%Wallet.Collection).Exists("OcuTalon_MCP_" _ name) Do ##class(%Wallet.Collection).Delete("OcuTalon_MCP_" _ name)
	}
}

/// What is left of the fixtures, as a text of places ("" when nothing): a row, a tool row or a session.
Method Leftovers() As %String [ Private ]
{
	Set places = ""
	If ..TotalRows() > 0 Set places = places _ $ListBuild("check rows")
	For i = 1:1:$Length(..Names, ",") {
		Set name = $Piece(..Names, ",", i)
		If name = "" Continue
		If ##class(OcuTalon.Mcp.Server).NameIndexExists(name) Set places = places _ $ListBuild(name _ " row")
		If ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexExists(name, "zz_lookup") Set places = places _ $ListBuild(name _ " tool rows")
	}
	For i = 1:1:$Length(..Sessions, ",") {
		Set ref = $Piece(..Sessions, ",", i)
		If ref '= "", ##class(OcuTalon.Data.Session).RefIndexExists(ref) Set places = places _ $ListBuild("a session")
	}
	Quit $ListToString(places, ", ")
}

}
