/// OcuTalon.Mcp.Ops, the reads and the attach report (AD-21, AD-29): Tools(server), which Story 21.4 calls, and RecordAttach.
///   - TestTools: an unknown server and an empty name are an error; a registered server gives its tool rows as {"name", "classification", "status"}, sorted by name
///     (capital letters before small ones), with the status refused for a name in RefusedTools, else unavailable while the last attach was unavailable, else
///     available; a registered server with no tool rows gives an empty array; the tools of another server are not listed;
///   - TestRecordAttachUnknownServer: a report for a server that has no row, or names none, is an error and writes no row;
///   - TestRecordAttach: the report's status, reason, refused tools and, for an attached server, the time are written to the server's row; a reason that
///     is not a code word of the bridge is stored as empty, so no text of AI Hub reaches the row; an unavailable report keeps the time of the last
///     attach; a report that is no object is an error and changes nothing.
/// The fixture rows are the server zzmcptools and its tool rows, and a second server's, which the test creates and removes itself.
Class OcuTalon.Test.Mcp.Tools Extends %UnitTest.TestCase
{

Parameter SERVER = "zzmcptools";

Parameter OTHER = "zzmcptoolsb";

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ..Remove()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Remove()
	Quit $$$OK
}

Method TestTools()
{
	For server = "zzmcpnosuch", "" {
		Kill tools
		Do $$$AssertStatusNotOK(##class(OcuTalon.Mcp.Ops).Tools(server, .tools), "Tools of '" _ server _ "' is an error")
	}
	Do ..Add()
	Kill tools
	Do $$$AssertStatusOK(##class(OcuTalon.Mcp.Ops).Tools(..#SERVER, .tools), "Tools of a registered server is OK")
	Do $$$AssertTrue($IsObject(tools) && tools.%IsA("%Library.DynamicArray"), "and gives a %DynamicArray")
	If $IsObject(tools) Do $$$AssertEquals(tools.%Size(), 0, "which is empty while the server has no tool rows")
	Do ..Tool(..#SERVER, "zz_lookup", "read-only")
	Do ..Tool(..#SERVER, "Zz_Upper", "risky")
	Do ..Tool(..#SERVER, "zz_delete_ticket", "unclassified")
	Do ..Tool(..#SERVER, "zz_shadow", "unclassified")
	Do ..Tool(..#OTHER, "zz_other", "risky")
	Do $$$AssertEquals(..Listed(), "Zz_Upper|risky|available;zz_delete_ticket|unclassified|available;zz_lookup|read-only|available;zz_shadow|unclassified|available", "the rows of the server, sorted by name, all available while no attach was recorded")
	Set row = ##class(OcuTalon.Mcp.Server).NameIndexOpen(..#SERVER)
	Set row.AttachStatus = "attached"
	Set row.RefusedTools = $ListBuild("zz_shadow")
	Do row.%Save()
	Do $$$AssertEquals(..Listed(), "Zz_Upper|risky|available;zz_delete_ticket|unclassified|available;zz_lookup|read-only|available;zz_shadow|unclassified|refused", "a refused tool is refused")
	Set row.AttachStatus = "unavailable"
	Set row.RefusedTools = ""
	Do row.%Save()
	Do $$$AssertEquals(..Listed(), "Zz_Upper|risky|unavailable;zz_delete_ticket|unclassified|unavailable;zz_lookup|read-only|unavailable;zz_shadow|unclassified|unavailable", "every tool is unavailable while the last attach was")
	Set row.RefusedTools = $ListBuild("zz_shadow")
	Do row.%Save()
	Do $$$AssertEquals(..Listed(), "Zz_Upper|risky|unavailable;zz_delete_ticket|unclassified|unavailable;zz_lookup|read-only|unavailable;zz_shadow|unclassified|refused", "and a refused one stays refused")
}

Method TestRecordAttachUnknownServer()
{
	Set report = {"status": "attached", "reason": "", "tools": ["zz_lookup"], "refused": []}
	Set sc = ##class(OcuTalon.Mcp.Ops).RecordAttach(..#SERVER, report)
	Do $$$AssertStatusNotOK(sc, "a report for a server with no row is an error")
	Do $$$AssertEquals(..Count(), 0, "and writes no row")
	Set sc = ##class(OcuTalon.Mcp.Ops).RecordAttach("", report)
	Do $$$AssertStatusNotOK(sc, "a report that names no server is an error and writes no row")
}

Method TestRecordAttach()
{
	Do ..Add()
	Set server = ..#SERVER
	Do $$$AssertStatusOK(##class(OcuTalon.Mcp.Ops).RecordAttach(server, {"status": "attached", "reason": "", "tools": ["zz_lookup", "zz_delete_ticket"], "refused": ["zz_steps_note"]}), "an attached report is recorded")
	Set row = ##class(OcuTalon.Mcp.Server).NameIndexOpen(server)
	Do $$$AssertEquals(row.AttachStatus _ "|" _ row.AttachReason _ "|" _ $ListToString(row.RefusedTools), "attached||zz_steps_note", "the row holds the status, no reason and the refused tool")
	Do $$$AssertTrue(row.AttachedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "and the time of the attach, UTC to the second")
	Set attachedAt = row.AttachedAt
	Do $$$AssertStatusOK(##class(OcuTalon.Mcp.Ops).RecordAttach(server, {"status": "unavailable", "reason": "unreachable", "tools": [], "refused": []}), "an unavailable report is recorded")
	Set row = ##class(OcuTalon.Mcp.Server).NameIndexOpen(server)
	Do $$$AssertEquals(row.AttachStatus _ "|" _ row.AttachReason _ "|" _ $ListToString(row.RefusedTools) _ "|" _ (row.AttachedAt = attachedAt), "unavailable|unreachable||1", "the row holds the status and the reason, no refused tool, and keeps the time of the last attach")
	Do $$$AssertStatusOK(##class(OcuTalon.Mcp.Ops).RecordAttach(server, {"status": "unavailable", "reason": "Failed to add tool spec 'mcp:remote:http://example.invalid/'", "tools": [], "refused": []}), "a report whose reason is text is recorded")
	Set row = ##class(OcuTalon.Mcp.Server).NameIndexOpen(server)
	Do $$$AssertEquals(row.AttachReason, "", "with the reason stored as empty, since only the bridge's code words are kept")
	Do $$$AssertStatusOK(##class(OcuTalon.Mcp.Ops).RecordAttach(server, {"status": "odd", "reason": "failed"}), "a report with an unknown status is recorded")
	Set row = ##class(OcuTalon.Mcp.Server).NameIndexOpen(server)
	Do $$$AssertEquals(row.AttachStatus _ "|" _ row.AttachReason, "|failed", "with the status stored as empty")
	Set before = row.AttachStatus _ "|" _ row.AttachReason _ "|" _ row.AttachedAt
	Do $$$AssertStatusNotOK(##class(OcuTalon.Mcp.Ops).RecordAttach(server, ""), "a report that is no object is an error")
	Set row = ##class(OcuTalon.Mcp.Server).NameIndexOpen(server)
	Do $$$AssertEquals(row.AttachStatus _ "|" _ row.AttachReason _ "|" _ row.AttachedAt, before, "and changes nothing")
}

/// The tool rows that Tools gives for the fixture server, as "name|classification|status" joined by ";".
Method Listed() As %String [ Private ]
{
	Set text = ""
	Do ##class(OcuTalon.Mcp.Ops).Tools(..#SERVER, .tools)
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set text = text _ $Select(text = "": "", 1: ";") _ tool.name _ "|" _ tool.classification _ "|" _ tool.status
	}
	Quit text
}

/// A tool row of the server, made as the fixture; the server's own row is made too when it is the second fixture server.
Method Tool(server As %String, name As %String, classification As %String) [ Private ]
{
	If (server = ..#OTHER) && '##class(OcuTalon.Mcp.Server).NameIndexExists(server) {
		Set other = ##class(OcuTalon.Mcp.Server).%New()
		Set other.Name = server
		Set other.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
		Do $$$AssertStatusOK(other.%Save(), "the second fixture row " _ server _ " is saved")
	}
	Set row = ##class(OcuTalon.Mcp.ToolClassification).%New()
	Set row.Server = server
	Set row.Tool = name
	Set row.Classification = classification
	Set row.Fingerprint = "fp"
	Do $$$AssertStatusOK(row.%Save(), "the fixture tool " _ name _ " is saved")
}

/// The fixture row, new.
Method Add() As OcuTalon.Mcp.Server [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.Server).%New()
	Set row.Name = ..#SERVER
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(row.%Save(), "the fixture row "_..#SERVER_" is saved")
	Quit row
}

/// Removes the fixture rows: the tool rows and the rows of both fixture servers.
Method Remove() [ Private ]
{
	For server = ..#SERVER, ..#OTHER {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", server)
		If ##class(OcuTalon.Mcp.Server).NameIndexExists(server, .id) Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
	}
}

/// The number of fixture rows of the server: its row and its tool rows.
Method Count() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", ..#SERVER)
	Do result.%Next()
	Quit +##class(OcuTalon.Mcp.Server).NameIndexExists(..#SERVER) + result.%GetData(1)
}

}
