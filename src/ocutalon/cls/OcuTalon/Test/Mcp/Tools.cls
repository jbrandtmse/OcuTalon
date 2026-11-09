/// OcuTalon.Mcp.Ops, the part Story 35.1 builds (AD-21, AD-29): the Tools(server) stub that Story 21.4 calls until Story 22.2, and RecordAttach.
///   - TestToolsStub: any server name (a registered one, an unknown one, an empty one) gives OK and an empty %DynamicArray;
///   - TestRecordAttachUnknownServer: a report for a server that has no row, or names none, is an error and writes no row;
///   - TestRecordAttach: the report's status, reason, refused tools and, for an attached server, the time are written to the server's row; a reason that
///     is not a code word of the bridge is stored as empty, so no text of AI Hub reaches the row; an unavailable report keeps the time of the last
///     attach; a report that is no object is an error and changes nothing.
/// The fixture row is zzmcptools, which the test creates and removes itself.
Class OcuTalon.Test.Mcp.Tools Extends %UnitTest.TestCase
{

Parameter SERVER = "zzmcptools";

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

Method TestToolsStub()
{
	Set row = ..Add()
	For server = ..#SERVER, "zzmcpnosuch", "" {
		Kill tools
		Set sc = ##class(OcuTalon.Mcp.Ops).Tools(server, .tools)
		Do $$$AssertStatusOK(sc, "Tools of '"_server_"' is OK")
		Do $$$AssertTrue($IsObject(tools) && tools.%IsA("%Library.DynamicArray"), "and gives a %DynamicArray")
		If $IsObject(tools) Do $$$AssertEquals(tools.%Size(), 0, "which is empty")
	}
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

/// The fixture row, new.
Method Add() As OcuTalon.Mcp.Server [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.Server).%New()
	Set row.Name = ..#SERVER
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(row.%Save(), "the fixture row "_..#SERVER_" is saved")
	Quit row
}

/// Removes the fixture row.
Method Remove() [ Private ]
{
	If ##class(OcuTalon.Mcp.Server).NameIndexExists(..#SERVER, .id) Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
}

/// The number of fixture rows.
Method Count() As %Integer [ Private ]
{
	Quit +##class(OcuTalon.Mcp.Server).NameIndexExists(..#SERVER)
}

}
