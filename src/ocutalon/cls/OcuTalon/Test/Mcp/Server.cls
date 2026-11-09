/// OcuTalon.Mcp.Server and OcuTalon.Mcp.Attach.Servers, the table of registered MCP servers and the list the runners read from it (Story 35.1; AD-21, AD-33):
///   - TestName: a name is a letter followed by up to 39 letters, digits or underscores, since AI.MCP.OcuTalon_<Name> is a Config Store name and the
///     bridge puts it into @{config:...}; a name that breaks the pattern (empty, a digit first, a dash, a space, a dot, a closing brace, 41 characters) is
///     refused on save and writes no row, and the 40-character name is saved;
///   - TestNameIsUnique: a second row with the name of a saved row is refused and the table still holds one row of that name;
///   - TestServers: Attach.Servers gives one {"server", "config"} for each row in the order of the names, the config being AI.MCP.OcuTalon_<Name>, and
///     the row's report fields play no part in it.
/// The fixture rows are named zzmcpsv..., which the test creates and removes itself.
Class OcuTalon.Test.Mcp.Server Extends %UnitTest.TestCase
{

Parameter PREFIX = "zzmcpsv";

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ..Remove()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Remove()
	Do $$$AssertEquals(..Count(), 0, "the test leaves no fixture row behind")
	Quit $$$OK
}

Method TestName()
{
	Set prefix = ..#PREFIX
	Set long = $Translate($Justify("", 33), " ", "a")
	Set bad = $ListBuild("", "9" _ prefix, prefix _ "-a", prefix _ " a", prefix _ ".a", prefix _ "}", prefix _ long _ "a")
	Set pointer = 0
	While $ListNext(bad, pointer, name) {
		Set row = ..New(name)
		Set sc = row.%Save()
		Do $$$AssertStatusNotOK(sc, "the name '" _ name _ "' is refused")
		Do $$$AssertEquals(..Named(name), 0, "and writes no row")
	}
	For name = prefix, prefix _ "_A9", prefix _ long {
		Set row = ..New(name)
		Do $$$AssertStatusOK(row.%Save(), "the name '" _ name _ "' (" _ $Length(name) _ " characters) is saved")
	}
}

Method TestNameIsUnique()
{
	Set name = ..#PREFIX _ "u"
	Do $$$AssertStatusOK(..New(name).%Save(), "the first row is saved")
	Set sc = ..New(name).%Save()
	Do $$$AssertStatusNotOK(sc, "a second row with the same name is refused")
	Do $$$AssertEquals(..Count(), 1, "and the table holds one row of that name")
}

Method TestServers()
{
	Set prefix = ..#PREFIX
	Set second = ..New(prefix _ "b")
	Set second.AttachStatus = "unavailable"
	Set second.AttachReason = "unreachable"
	Do $$$AssertStatusOK(second.%Save(), "the second row is saved first")
	Set first = ..New(prefix _ "a")
	Set first.AttachStatus = "attached"
	Do $$$AssertStatusOK(first.%Save(), "and the first row after it")
	Do $$$AssertStatusOK(##class(OcuTalon.Mcp.Attach).Servers(.servers), "Servers answers")
	Do $$$AssertTrue($IsObject(servers) && servers.%IsA("%Library.DynamicArray"), "with a %DynamicArray")
	If '$IsObject(servers) Quit
	Set found = ""
	Set iterator = servers.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If $Extract(entry.server, 1, $Length(prefix)) = prefix {
			Set found = found _ $ListBuild(entry.server _ "=" _ entry.config _ "|" _ entry.%Size())
		}
	}
	Do $$$AssertEquals($ListToString(found, ","), prefix _ "a=AI.MCP.OcuTalon_" _ prefix _ "a|2," _ prefix _ "b=AI.MCP.OcuTalon_" _ prefix _ "b|2", "one {server, config} for each row, in the order of the names, whatever the row reported")
}

/// A new row, not saved.
Method New(name As %String) As OcuTalon.Mcp.Server [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.Server).%New()
	Set row.Name = name
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit row
}

/// Removes the fixture rows.
Method Remove() [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.Server WHERE Name %STARTSWITH '" _ ..#PREFIX _ "' OR Name = '9" _ ..#PREFIX _ "' OR Name IS NULL OR Name = ''")
}

/// The number of rows with exactly this name.
Method Named(name As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Mcp.Server WHERE Name = ?", name)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of fixture rows.
Method Count() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Mcp.Server WHERE Name %STARTSWITH '" _ ..#PREFIX _ "'")
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
