/// OcuTalon.Mcp.Classification, the ClassificationClass of OcuTalon, and Mcp.Attach.ToolsReadOnly, the McpServersClass answer that Decide reads (Story 22.8; AD-8, AD-10,
/// AD-21, AD-31, DW-724). THESE TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): the fixture servers are made by the add handler of the probe
/// OcuTalon.Test.Mcp.OpsProbe, which creates and removes an IRIS resource in %SYS, and their tool rows by its RecordAttach and its classify handler; they write audit
/// entries and need no production and no mock server. The probe restarts no runner and records the notices it would send. Each test makes its own servers
/// (zzmcpcls<n>...) and its fixture admin session, and OnAfterOneTest removes them whether the test passed or failed and asserts that none is left.
///   - TestSource (matrix row "Removed / unregistered"): only the toolref mcp:remote:@{config:AI.MCP.OcuTalon_<name>} of a name that has an Mcp.Server row is registered;
///     every other form (a URL, stdio, the JSON configuration, another prefix, another case, a bad name, extra text, no source) and a server that was removed answer
///     registered 0, with no classification;
///   - TestClassifications (rows "Read-only", "Risky", "Unclassified", "Not in map"): a read-only row answers {safe, readOnly 1, registered 1} for its fingerprint, a
///     risky one {risky, 0, 1}, and every answer for a registered server also holds its resource, OcuTalon_MCP_<server> (Story 22.3; a server that is not registered has none); no row, an unclassified row and no fingerprint answer none and change nothing (a classified row with no fingerprint stays classified);
///     the answer reads the rows and writes nothing; tool names are case-sensitive;
///   - TestChangedFingerprint (rows "Changed"): a classified row and a different, non-empty fingerprint answer none and clear the row through ClearChanged (the row is
///     unclassified with the new fingerprint, one Tool entry is audited, one notice goes to each admin session); the same call again does nothing more; an unclassified
///     row keeps its fingerprint; an error from the clear is one warning and the answer is the same;
///   - TestChangedFingerprintReal: the same through the real class, whose clear is OcuTalon.Mcp.Ops ClearChanged (the row and the one audit entry);
///   - TestClassifyBase: Classify, which answers for a class source, classifies nothing, and the class extends the bridge's;
///   - TestToolsReadOnly (row "Host ToolsReadOnly"): the answer for an attached server whose tool rows are all read-only, one that has a risky or an unclassified row,
///     a refused tool that is risky, an attached server with no tool row, an unavailable one, one that never attached, an unknown, an invalid and an empty name.
Class OcuTalon.Test.Mcp.Classification Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Mcp.OpsProbe";

Parameter CLASS = "OcuTalon.Mcp.Classification";

Parameter PROBECLASS = "OcuTalon.Test.Mcp.ZzProbeClassification";

Parameter USER = "zzmcpclsadmin";

Parameter URL = "https://example.invalid/mcp";

/// The server names the test made, comma-separated, and the fixture sessions.
Property Names As %String(MAXLEN = "");

Property Admin As %String(MAXLEN = "");

Property Number As %Integer;

Property AuditMark As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^||ZzOps
	Set ..Names = ""
	Set ..Admin = ""
	Set ..Number = $Increment(^OcuTalonTest("McpClassification", "n"))
	Set ..AuditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Clean()
	Do $$$AssertEquals(..Leftovers(), "", "the test leaves no server, tool row, resource or session behind")
	Kill ^||ZzOps
	Quit $$$OK
}

Method TestSource()
{
	Set server = ..Make("a")
	Set prefix = ..Make("")
	Set source = ..Source(server)
	Set class = ..#CLASS
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", source, "zz_a", "fp").registered, 1, "the toolref that the runner attaches for a registered server is registered")
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", ..Source(prefix), "zz_a", "fp").registered, 1, "and so is that of a server whose name is the beginning of another's")
	Set unknown = ..Source("zzmcpcls" _ ..Number _ "none")
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", unknown, "zz_a", "fp").%ToJSON(), {"classification": "", "readOnly": 0, "registered": 0}.%ToJSON(), "the same form for a name with no row is not registered, and has no classification")
	For other = "mcp:remote:http://127.0.0.1:1/mcp", "mcp:stdio:python3 server.py", "{""type"":""mcp:remote"",""url"":""http://127.0.0.1:1/mcp""}", "MCP:remote:@{config:AI.MCP.OcuTalon_" _ server _ "}",
		"mcp:remote:@{config:AI.MCP.Other_" _ server _ "}", "mcp:remote:@{config:AI.MCP.OcuTalon_}", "mcp:remote:@{config:AI.MCP.OcuTalon_1" _ server _ "}", "mcp:remote:@{config:AI.MCP.OcuTalon_" _ server,
		source _ " ", " " _ source, "mcp:remote:@{config:AI.MCP.OcuTalon_" _ server _ "}}", "mcp:remote:@{config:AI.MCP.OcuTalon_" _ server _ "x}", "mcp:docs", "zz", "" {
		Set answer = $ClassMethod(class, "ClassifyMcp", other, "zz_a", "fp")
		Do $$$AssertEquals(answer.%ToJSON(), {"classification": "", "readOnly": 0, "registered": 0}.%ToJSON(), "'" _ other _ "' is not a registered server")
	}
	Set remove = ##class(OcuTalon.Msg.Command.RemoveMcpServer).%New()
	Set remove.Server = server
	Set remove.Origin = "web_admin"
	Set remove.ActingUser = ..#USER
	Set result = ..Run(remove)
	Do $$$AssertEquals(result.Outcome, "removed", "the server is removed through the item")
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", source, "zz_a", "fp").registered, 0, "afterwards its toolref is not registered")
}

Method TestClassifications()
{
	Set server = ..Make("b")
	Set source = ..Source(server)
	Set class = ..#CLASS
	Do ..Attach(server, "zz_none,zz_ro,zz_risky,Foo", "fpn,fpro,fprisky,fpfoo")
	Do ..Classify(server, "zz_ro", "read-only")
	Do ..Classify(server, "zz_risky", "risky")
	Do ..Classify(server, "Foo", "risky")
	Set before = ..ToolRows(server)
	Hang 0.1
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set none = {"classification": "", "readOnly": 0, "registered": 1, "resource": (##class(OcuTalon.Install.Step.Mcp).ResourceOf(server))}.%ToJSON()
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", source, "zz_ro", "fpro").%ToJSON(), {"classification": "safe", "readOnly": 1, "registered": 1, "resource": (##class(OcuTalon.Install.Step.Mcp).ResourceOf(server))}.%ToJSON(), "a read-only row answers safe, readOnly 1, registered 1 and the server's resource")
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", source, "zz_risky", "fprisky").%ToJSON(), {"classification": "risky", "readOnly": 0, "registered": 1, "resource": (##class(OcuTalon.Install.Step.Mcp).ResourceOf(server))}.%ToJSON(), "a risky row answers risky, readOnly 0, registered 1 and the server's resource")
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", source, "zz_none", "fpn").%ToJSON(), none, "an unclassified row answers none")
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", source, "zz_missing", "fpx").%ToJSON(), none, "a tool with no row answers none")
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", source, "zz_ro", "").%ToJSON(), none, "a read-only row with no fingerprint in the map answers none")
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", source, "zz_ro").%ToJSON(), none, "also with no fingerprint argument")
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", source, "foo", "fpfoo").%ToJSON(), none, "tool names are case-sensitive: foo is not Foo")
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", source, "Foo", "fpfoo").classification, "risky", "and Foo is risky")
	Do $$$AssertEquals(..ToolRows(server), before, "the answers wrote no row")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Tool", "Tool", server).%Size(), 0, "and audited nothing")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%Size(), 0, "and sent no notice")
}

Method TestChangedFingerprint()
{
	Set server = ..Make("c")
	Set source = ..Source(server)
	Set class = ..#PROBECLASS
	Set none = {"classification": "", "readOnly": 0, "registered": 1, "resource": (##class(OcuTalon.Install.Step.Mcp).ResourceOf(server))}.%ToJSON()
	Set admin = ..MakeAdmin()
	Set ^||ZzOps("admins") = $ListBuild(admin)
	Do ..Attach(server, "zz_ro,zz_risky,zz_none", "fp1,fp2,fp3")
	Do ..Classify(server, "zz_ro", "read-only")
	Do ..Classify(server, "zz_risky", "risky")
	// the audit entries of the classifications are older than the mark by a few milliseconds at least
	Hang 0.1
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	// an unclassified row is not cleared: ClearChanged is for a classified row
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", source, "zz_none", "other").%ToJSON(), none, "an unclassified row answers none for another fingerprint")
	Do $$$AssertEquals(..ToolRows(server), "zz_none|unclassified|fp3;zz_risky|risky|fp2;zz_ro|read-only|fp1", "and keeps its fingerprint")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%Size(), 0, "with no notice")
	// a changed read-only tool
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", source, "zz_ro", "fp1changed").%ToJSON(), none, "a read-only row and another fingerprint answer none")
	Do $$$AssertEquals(..ToolRows(server), "zz_none|unclassified|fp3;zz_risky|risky|fp2;zz_ro|unclassified|fp1changed", "the row is unclassified, with the new fingerprint")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Tool", "Tool", server)
	Do $$$AssertEquals(entries.%Size(), 1, "one Tool entry is audited")
	If entries.%Size() Do $$$AssertEquals(entries.%Get(0).data.tool _ "|" _ entries.%Get(0).data.classification _ "|" _ entries.%Get(0).data.channel, "zz_ro|unclassified|system", "it says unclassified for zz_ro, on the system channel")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(admin, "mcp.toolChanged"), 1, "the admin session gets one mcp.toolChanged notice")
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", source, "zz_ro", "fp1changed").%ToJSON(), none, "the same call again answers none")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%Size() _ "|" _ ##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Tool", "Tool", server).%Size(), "1|1", "and sends no second notice and audits nothing more")
	// a changed risky tool
	Do $$$AssertEquals($ClassMethod(class, "ClassifyMcp", source, "zz_risky", "fp2changed").%ToJSON(), none, "a risky row and another fingerprint answer none")
	Do $$$AssertEquals(..ToolRows(server), "zz_none|unclassified|fp3;zz_risky|unclassified|fp2changed;zz_ro|unclassified|fp1changed", "and it is cleared too")
	// an error of the clear: one warning, the same answer
	Do ..Classify(server, "zz_ro", "read-only")
	Set logMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set ^||ZzOps("auditError") = 1
	Set answer = $ClassMethod(class, "ClassifyMcp", source, "zz_ro", "fp1again")
	Kill ^||ZzOps("auditError")
	Do $$$AssertEquals(answer.%ToJSON(), none, "a clear that fails answers none too")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(logMark, "could not be cleared"), 1, "with one warning")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(logMark, "fp1again"), 0, "that holds no fingerprint")
}

/// The real class (not the probe subclass): a classified row and another fingerprint answer none, and the clear is OcuTalon.Mcp.Ops ClearChanged's, so the row is
/// unclassified with the new fingerprint and one Tool entry is audited, once for the change. No fixture admin session exists, so no notice is expected here.
Method TestChangedFingerprintReal()
{
	Set server = ..Make("k")
	Set source = ..Source(server)
	Set none = {"classification": "", "readOnly": 0, "registered": 1, "resource": (##class(OcuTalon.Install.Step.Mcp).ResourceOf(server))}.%ToJSON()
	Do ..Attach(server, "zz_ro,zz_other", "fp1,fp2")
	Do ..Classify(server, "zz_ro", "read-only")
	Do ..Classify(server, "zz_other", "risky")
	Hang 0.1
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertEquals($ClassMethod(..#CLASS, "ClassifyMcp", source, "zz_ro", "fp1changed").%ToJSON(), none, "a read-only row and another fingerprint answer none")
	Do $$$AssertEquals(..ToolRows(server), "zz_other|risky|fp2;zz_ro|unclassified|fp1changed", "the row of the changed tool is unclassified with the new fingerprint, and the other row is as it was")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Tool", "Tool", server)
	Do $$$AssertEquals(entries.%Size(), 1, "one Tool entry is audited")
	If entries.%Size() Do $$$AssertEquals(entries.%Get(0).data.tool _ "|" _ entries.%Get(0).data.classification, "zz_ro|unclassified", "it says unclassified for zz_ro")
	Do $$$AssertEquals($ClassMethod(..#CLASS, "ClassifyMcp", source, "zz_ro", "fp1changed").%ToJSON(), none, "the same call again answers none")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Tool", "Tool", server).%Size(), 1, "and audits nothing more")
}

Method TestClassifyBase()
{
	Do $$$AssertTrue($ClassMethod(..#CLASS, "%Extends", "OcuTalon.Bridge.Ext.Classification"), "the class extends the bridge's classification")
	Do $$$AssertEquals($ClassMethod(..#CLASS, "Classify", "OcuTalon.Tools.ReminderTools", "set_reminder"), "", "Classify classifies a class source as nothing, so the built-in tools are classified by their code as before")
	Do $$$AssertEquals($ClassMethod(..#CLASS, "Classify", "mcp:remote:@{config:AI.MCP.OcuTalon_zz}", "zz_a"), "", "also an MCP source")
}

Method TestToolsReadOnly()
{
	Set attach = "OcuTalon.Mcp.Attach"
	Set ok = ..Make("d"), mixed = ..Make("e"), unclassified = ..Make("f"), refused = ..Make("g"), empty = ..Make("h"), down = ..Make("i"), never = ..Make("j")
	Do ..Attach(ok, "zz_a,zz_b", "f1,f2")
	Do ..Classify(ok, "zz_a", "read-only")
	Do ..Classify(ok, "zz_b", "read-only")
	Do ..Attach(mixed, "zz_a,zz_b", "f1,f2")
	Do ..Classify(mixed, "zz_a", "read-only")
	Do ..Classify(mixed, "zz_b", "risky")
	Do ..Attach(unclassified, "zz_a,zz_b", "f1,f2")
	Do ..Classify(unclassified, "zz_a", "read-only")
	Do ..Attach(refused, "zz_a", "f1", "zz_shadow")
	Do ..Classify(refused, "zz_a", "read-only")
	Do ..Classify(refused, "zz_shadow", "risky")
	Do ..Attach(empty, "", "")
	Do ..Attach(down, "zz_a", "f1")
	Do ..Classify(down, "zz_a", "read-only")
	Do ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(down, {"status": "unavailable", "reason": "unreachable", "tools": [], "refused": []})
	Do $$$AssertEquals($ClassMethod(attach, "ToolsReadOnly", ok), 1, "an attached server whose tools are all read-only: 1")
	Do $$$AssertEquals($ClassMethod(attach, "ToolsReadOnly", mixed), 0, "one with a risky tool: 0")
	Do $$$AssertEquals($ClassMethod(attach, "ToolsReadOnly", unclassified), 0, "one with an unclassified tool: 0")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Server).NameIndexOpen(refused).RefusedTools, $ListBuild("zz_shadow"), "control: the refused tool is in the row's RefusedTools")
	Do $$$AssertEquals($ClassMethod(attach, "ToolsReadOnly", refused), 1, "a risky tool that is refused never runs, so it counts for nothing: 1")
	Do $$$AssertEquals($ClassMethod(attach, "ToolsReadOnly", empty), 1, "an attached server with no tool row: 1")
	Do $$$AssertEquals($ClassMethod(attach, "ToolsReadOnly", down), 0, "a server whose last attach was unavailable: 0, although its rows are read-only")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(down, "zz_a").Classification, "read-only", "control: its tool is read-only")
	Do $$$AssertEquals($ClassMethod(attach, "ToolsReadOnly", never), 0, "a server that never attached: 0")
	Do $$$AssertEquals($ClassMethod(attach, "ToolsReadOnly", "zzmcpcls" _ ..Number _ "none"), 0, "an unknown server: 0")
	Do $$$AssertEquals($ClassMethod(attach, "ToolsReadOnly", ""), 0, "an empty name: 0")
	Do $$$AssertEquals($ClassMethod(attach, "ToolsReadOnly", "1bad"), 0, "a name that is none: 0")
	Do $$$AssertEquals($ClassMethod(attach, "ToolsReadOnly", ok _ "; DROP"), 0, "also a name with more text")
	Do $$$AssertEquals(..ToolRows(ok), "zz_a|read-only|f1;zz_b|read-only|f2", "and the asking wrote no row")
}

/// --- helpers ---
/// The name of the test's server with the suffix; Make adds it through the item.
Method Make(suffix As %String) As %String
{
	Set server = "zzmcpcls" _ ..Number _ suffix
	Set ..Names = ..Names _ $Select(..Names = "": "", 1: ",") _ server
	Set command = ##class(OcuTalon.Msg.Command.AddMcpServer).%New()
	Set command.Server = server
	Set command.Url = ..#URL
	Set command.Origin = "web_admin"
	Set command.ActingUser = ..#USER
	Set result = ..Run(command)
	Do $$$AssertEquals(result.Outcome, "added", "the fixture server " _ server _ " is added through the item")
	Quit server
}

/// The toolref that the runner attaches for the server.
Method Source(server As %String) As %String
{
	Quit "mcp:remote:@{config:AI.MCP.OcuTalon_" _ server _ "}"
}

/// Runs the command through a probe whose request header names CommandsIn.
Method Run(command As %RegisteredObject) As OcuTalon.Msg.CommandResult
{
	Set probe = ##class(OcuTalon.Test.Mcp.OpsProbe).Shadow("CommandsIn", .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.MessageHandler(command, .result)
	Do $$$AssertStatusOK(sc, "the command is answered")
	Quit result
}

/// An attach report of the server (attached) with the tools and their fingerprints, comma-separated, and the refused tools, recorded through RecordAttach.
Method Attach(server As %String, tools As %String, fingerprints As %String, refused As %String = "")
{
	Set report = {"status": "attached", "reason": "", "tools": [], "refused": [], "fingerprints": {}}
	For i = 1:1:$Length(tools, ",") {
		Set tool = $Piece(tools, ",", i)
		If tool = "" Continue
		Do report.tools.%Push(tool)
		Do report.fingerprints.%Set(tool, $Piece(fingerprints, ",", i))
	}
	For i = 1:1:$Length(refused, ",") {
		If $Piece(refused, ",", i) '= "" Do report.refused.%Push($Piece(refused, ",", i))
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, report), "the attach report of " _ server _ " is recorded")
}

/// Classifies the tool through the item's classify handler.
Method Classify(server As %String, tool As %String, word As %String)
{
	Set command = ##class(OcuTalon.Msg.Command.ClassifyTool).%New()
	Set command.Server = server
	Set command.Tool = tool
	Set command.Classification = word
	Set command.Origin = "web_admin"
	Set command.ActingUser = ..#USER
	Set result = ..Run(command)
	Do $$$AssertEquals(result.Outcome, "saved", tool _ " of " _ server _ " is " _ word)
}

/// A fixture admin session. Returns its Ref.
Method MakeAdmin() As %String
{
	Set row = ##class(OcuTalon.Data.Session).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.TraceRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Epoch = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.IrisUser = "zzmcpcls" _ ..Number
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.AdminAtSignIn = 1
	Do $$$AssertStatusOK(row.%Save(), "the fixture session is saved")
	Set ..Admin = ..Admin _ $Select(..Admin = "": "", 1: ",") _ row.Ref
	Quit row.Ref
}

/// The tool rows of the server as "tool|classification|fingerprint" joined by ";", in the order of the names.
Method ToolRows(server As %String) As %String
{
	Set text = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Tool, Classification, Fingerprint FROM OcuTalon_Mcp.ToolClassification WHERE Server = ? ORDER BY %EXACT(Tool)", server)
	While result.%Next() {
		Set text = text _ $Select(text = "": "", 1: ";") _ result.%Get("Tool") _ "|" _ result.%Get("Classification") _ "|" _ result.%Get("Fingerprint")
	}
	Quit text
}


/// Removes every fixture this test may have made, each attempted whatever happened before.
Method Clean()
{
	For i = 1:1:$Length(..Names, ",") {
		Set name = $Piece(..Names, ",", i)
		If name = "" Continue
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", name)
		If ##class(OcuTalon.Mcp.Server).NameIndexExists(name, .id) Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
		Do ##class(OcuTalon.Install.Step.Mcp).Revoke(name)
	}
	For i = 1:1:$Length(..Admin, ",") {
		Set ref = $Piece(..Admin, ",", i)
		If ref '= "", ##class(OcuTalon.Data.Session).RefIndexExists(ref, .id) Do ##class(OcuTalon.Data.Session).%DeleteId(id)
	}
}

/// What is left of the fixtures, as a text of places ("" when nothing): a server row, a tool row, a resource or a session.
Method Leftovers() As %String
{
	Set places = ""
	For i = 1:1:$Length(..Names, ",") {
		Set name = $Piece(..Names, ",", i)
		If name = "" Continue
		If ##class(OcuTalon.Mcp.Server).NameIndexExists(name) Set places = places _ $ListBuild(name _ " row")
		If ..ToolRows(name) '= "" Set places = places _ $ListBuild(name _ " tool rows")
		If ..ResourceExists("OcuTalon_MCP_" _ name) Set places = places _ $ListBuild(name _ " resource")
	}
	For i = 1:1:$Length(..Admin, ",") {
		Set ref = $Piece(..Admin, ",", i)
		If ref '= "", ##class(OcuTalon.Data.Session).RefIndexExists(ref) Set places = places _ $ListBuild("a session")
	}
	Quit $ListToString(places, ", ")
}

/// 1 when the resource exists in %SYS.
Method ResourceExists(name As %String) As %Boolean
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ''##class(Security.Resources).Exists(name)
}

}
