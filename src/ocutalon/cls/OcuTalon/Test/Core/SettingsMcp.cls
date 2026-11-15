/// Tests of the ListMcpServers command in OcuTalon.Core.SettingsOps and of Ownership.PendingToolCalls (Story 21.4; AD-1, AD-21), called on a shadow instance of
/// OcuTalon.Test.Core.SettingsOpsProbe over fixture rows, a fixture Config Store entry and fixture approval rows. Safe on a slot: no production runs. Every test
/// makes its own `zz` servers, rows, entries and approval rows, and removes them again.
///   - TestList: the matrix row "List": the servers in the order of their names with their address, status, tool count, unclassified count and pending count, and the tools
///     array; a server that never attached has an empty status and no tools, a server whose entry is missing has an empty address, and no secret, no secret:// reference and
///     no fingerprint is in the answer;
///   - TestListChanged (Story 21.9): each tool row carries `changed`, a JSON boolean passed through from Mcp.Ops Tools for every status: a classified tool that Lane A's real
///     ClearChanged cleared is true (and sent each admin session one mcp.toolChanged notice), so is one cleared and then refused (the page skips it), a new and a risky tool are
///     false, and a classification save through the real handler makes it false again;
///   - TestListChangedUnavailable (QA): changed passes through for a tool whose server is unavailable, and the tools of two servers come server by server;
///   - TestPendingByToolref: the pending count is by the server's toolref under CancelPending's own predicate: a pending tool_call row whose ToolSource is the toolref in
///     another case is counted (CancelPending would cancel it), and an approved row, a row of another kind and another server's row are not;
///   - TestNameThatToolrefRefuses: PendingToolCalls gives 0 and an error for a name that is no server name;
///   - TestOnlineDemo: with the online-demo flag set ListMcpServers answers not_available with the text settings.mcpOffOnDemo and lists nothing.
Class OcuTalon.Test.Core.SettingsMcp Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Core.SettingsOpsProbe";

Parameter URL = "http://127.0.0.1:9/mcp";

/// The online-demo flag before the tests.
Property SavedOnline As %String;

/// The number of the test, in the names of its servers.
Property Number As %Integer;

/// The names of the test's servers, comma-separated.
Property Names As %String(MAXLEN = "");

/// The Refs of the test's approval rows, comma-separated.
Property Refs As %String(MAXLEN = "");

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe, ^||ZzOps
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set ..Number = $Increment(^OcuTalonTest("SettingsMcp", "n"))
	Set ..Names = ""
	Set ..Refs = ""
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ..Clean()
	Do $$$AssertEquals(..Leftovers(), "", "the test leaves no row, tool row, entry or approval row behind")
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe, ^||ZzOps
	Quit $$$OK
}

Method TestList()
{
	Set a = ..Server("a")
	Set b = ..Server("b")
	Do ..MakeServer(a, "attached", "zz_risky")
	Do ..MakeTool(a, "zz_lookup", "read-only")
	Do ..MakeTool(a, "zz_risky", "risky")
	Do ..MakeTool(a, "zz_new", "unclassified")
	Do ..MakeServer(b, "", "")
	Do ..MakeEntry(a, 1)
	Set result = ..List()
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|listed", "the list is answered listed")
	Set data = {}.%FromJSON(result.Data)
	Set servers = ..Mine(data.servers)
	Do $$$AssertEquals(servers.%Size(), 2, "both servers are listed")
	Do $$$AssertEquals(servers.%Get(0).name_"|"_servers.%Get(1).name, a_"|"_b, "in the order of their names")
	Set one = servers.%Get(0)
	Do $$$AssertEquals(one.status_"|"_one.address_"|"_one.tools_"|"_one.unclassified_"|"_one.pending, "attached|"_..#URL_"|3|1|0", "the attached server: status, address, 3 tools, 1 unclassified, none pending")
	Do $$$AssertEquals(one.%Size(), 6, "with only name, address, status, tools, unclassified and pending")
	Set two = servers.%Get(1)
	Do $$$AssertEquals(two.status_"|"_two.address_"|"_two.tools_"|"_two.unclassified_"|"_two.pending, "||0|0|0", "the server that never attached, with no entry: no status, no address, no tools")
	Set tools = ..Mine(data.tools)
	Do $$$AssertEquals(tools.%Size(), 3, "the tools array holds the attached server's three tools")
	Set text = ""
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set text = text_$ListBuild(tool.server_"|"_tool.name_"|"_tool.classification_"|"_tool.status)
	}
	Do $$$AssertEquals($ListToString(text, ";"), a_"|zz_lookup|read-only|available;"_a_"|zz_new|unclassified|available;"_a_"|zz_risky|risky|refused", "each with its classification and status")
	Do $$$AssertEquals(tools.%Get(0).%Size(), 5, "and only server, name, classification, status and changed")
	Set changed = ""
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set changed = changed_$ListBuild(tool.changed)
	}
	Do $$$AssertEquals($ListToString(changed, ","), "0,0,0", "and no fixture tool has changed")
	Set json = result.Data
	Do $$$AssertEquals(+(json [ "secret://"), 0, "the answer holds no secret:// reference")
	Do $$$AssertEquals(+(json [ "ingerprint"), 0, "and no fingerprint")
	Do $$$AssertEquals(+(json [ "zzfp"), 0, "(the fixture fingerprint is not in it)")
}

Method TestListChanged()
{
	Set a = ..Server("a")
	Do ..MakeServer(a, "attached", "")
	Do ..MakeTool(a, "zz_changed", "read-only")
	Do ..MakeTool(a, "zz_shadow", "read-only")
	Do ..MakeTool(a, "zz_new", "unclassified")
	Do ..MakeTool(a, "zz_risky", "risky")
	// a clear that notifies nobody, then the later attach that refuses the tool (the fixture form: the server row's RefusedTools)
	Set ^||ZzOps("admins") = ""
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).ClearChanged(a, "zz_shadow", "zzfp2_"_..Number), "zz_shadow is cleared")
	Set server = ##class(OcuTalon.Mcp.Server).NameIndexOpen(a)
	Set server.RefusedTools = $ListBuild("zz_shadow")
	Do $$$AssertStatusOK(server.%Save(), "and then reported refused")
	// the change that sends the notice
	Set admin = "zzadmin"_..Number
	Set ^||ZzOps("admins") = $ListBuild(admin)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).ClearChanged(a, "zz_changed", "zzfp2_"_..Number), "zz_changed is cleared")
	Set result = ..List()
	Set tools = ..Mine({}.%FromJSON(result.Data).tools)
	Set text = ""
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set text = text_$ListBuild(tool.name_"|"_tool.classification_"|"_tool.status_"|"_tool.changed)
	}
	Do $$$AssertEquals($ListToString(text, ";"), "zz_changed|unclassified|available|1;zz_new|unclassified|available|0;zz_risky|risky|available|0;zz_shadow|unclassified|refused|1", "the cleared tool is changed, the refused one is passed through as changed, the new and the risky tool are not")
	Do $$$AssertEquals(+(result.Data [ """changed"":true"), 1, "changed is a JSON boolean")
	Do $$$AssertEquals(+(result.Data [ """changed"":1"), 0, "and not a number")
	Set notices = ##class(OcuTalon.Test.Mcp.OpsProbe).Notices()
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(admin, "mcp.toolChanged"), 1, "the same clear sent the admin session one mcp.toolChanged notice")
	Set slots = ""
	Set iterator = notices.%GetIterator()
	While iterator.%GetNext(, .notice) {
		If notice.session = admin Set slots = notice.slots
	}
	Do $$$AssertEquals(+(slots [ "zz_changed"), 1, "whose slots name the tool")
	Do $$$AssertEquals(+(slots [ a), 1, "and the server")
	// a classification save through the real handler resets the flag
	Set command = ##class(OcuTalon.Msg.Command.ClassifyTool).%New()
	Set command.Server = a
	Set command.Tool = "zz_changed"
	Set command.Classification = "risky"
	Set command.Origin = "web_admin"
	Set command.ActingUser = admin
	Set probe = ##class(OcuTalon.Test.Mcp.OpsProbe).Shadow("CommandsIn", .sc)
	Do $$$AssertStatusOK(sc, "the Ops probe is made")
	Set sc = probe.MessageHandler(command, .saved)
	Do $$$AssertStatusOK(sc, "the classify handler runs")
	Do $$$AssertEquals(saved.Ok_"|"_saved.Outcome, "1|saved", "the classification is saved")
	Set tools = ..Mine({}.%FromJSON(..List().Data).tools)
	Set text = ""
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		If tool.name = "zz_changed" Set text = tool.classification_"|"_tool.changed
	}
	Do $$$AssertEquals(text, "risky|0", "after it the tool is risky and changed is false")
}

/// (QA) Two changed tools on two servers, one of which is down: ListMcp passes changed through for an unavailable tool as for every other status (its banner
/// shows), and the tools array lists them server by server, which is the order of the page's banners.
Method TestListChangedUnavailable()
{
	Set a = ..Server("a")
	Set b = ..Server("b")
	Do ..MakeServer(a, "attached", "")
	Do ..MakeServer(b, "unavailable", "")
	Do ..MakeTool(a, "zz_one", "read-only")
	Do ..MakeTool(b, "zz_down", "risky")
	Do ..MakeTool(b, "zz_other", "read-only")
	Set ^||ZzOps("admins") = ""
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).ClearChanged(a, "zz_one", "zzfp2_"_..Number), "zz_one is cleared")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Mcp.OpsProbe).ClearChanged(b, "zz_down", "zzfp2_"_..Number), "zz_down is cleared on the server that is down")
	Set tools = ..Mine({}.%FromJSON(..List().Data).tools)
	Set text = ""
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set text = text_$ListBuild($Extract(tool.server, *)_"|"_tool.name_"|"_tool.classification_"|"_tool.status_"|"_tool.changed)
	}
	Do $$$AssertEquals($ListToString(text, ";"), "a|zz_one|unclassified|available|1;b|zz_down|unclassified|unavailable|1;b|zz_other|read-only|unavailable|0", "both cleared tools are changed, in server order, the unavailable one too, and the tool nobody touched is not")
}

Method TestPendingByToolref()
{
	Set a = ..Server("a")
	Set b = ..Server("b")
	Do ..MakeServer(a, "attached", "")
	Do ..MakeServer(b, "attached", "")
	Set toolref = ##class(OcuTalon.Mcp.Attach).Toolref(a)
	Do ..MakeRow("tool_call", "pending", toolref)
	Do ..MakeRow("tool_call", "pending", $ZConvert(toolref, "U"))
	Do ..MakeRow("tool_call", "approved", toolref)
	Do ..MakeRow("fix", "pending", toolref)
	Do ..MakeRow("tool_call", "pending", ##class(OcuTalon.Mcp.Attach).Toolref(b))
	Set servers = ..Mine({}.%FromJSON(..List().Data).servers)
	Do $$$AssertEquals(servers.%Get(0).name_"|"_servers.%Get(0).pending, a_"|2", "two pending tool_call rows are counted for the first server: the toolref and the toolref in another case")
	Do $$$AssertEquals(servers.%Get(1).name_"|"_servers.%Get(1).pending, b_"|1", "and one for the second: an approved row, a row of another kind and the other server's row are not counted")
	Set count = ##class(OcuTalon.Data.Ownership).PendingToolCalls(a, .sc)
	Do $$$AssertEquals(count_"|"_$SYSTEM.Status.IsOK(sc), "2|1", "PendingToolCalls says the same")
	Set cancelled = ""
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).CancelPending(toolref, , "web", "zzadmin", ##class(OcuTalon.Bridge.Ids).NewRef(), .cancelled), "CancelPending is OK")
	Do $$$AssertEquals(+cancelled, 2, "and cancels exactly the two rows that were counted")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).PendingToolCalls(a), 0, "none is pending afterwards")
}

Method TestNameThatToolrefRefuses()
{
	For name = "", "1bad", "zz bad", "zz;drop" {
		Set count = ##class(OcuTalon.Data.Ownership).PendingToolCalls(name, .sc)
		Do $$$AssertEquals(count_"|"_$SYSTEM.Status.IsError(sc), "0|1", "'"_name_"' gives 0 and an error")
	}
}

Method TestOnlineDemo()
{
	Set a = ..Server("a")
	Do ..MakeServer(a, "attached", "")
	Do ..MakeTool(a, "zz_lookup", "read-only")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set result = ..List()
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_available", "on the online demo the list is not_available")
	Do $$$AssertEquals(result.Message, "MCP servers are off on the online demo: nobody can add one, and OcuTalon reaches none. They work on your own install.", "with the accepted text")
	Do $$$AssertEquals(result.Data, "", "and lists nothing")
}

/// --- helpers ---
/// The name of the test's server with the suffix.
Method Server(suffix As %String) As %String [ Private ]
{
	Set name = "zzmcpl"_..Number_suffix
	Set ..Names = ..Names_$Select(..Names = "": "", 1: ",")_name
	Quit name
}

/// A server row with its attach status and its refused tool (empty for none).
Method MakeServer(name As %String, status As %String, refused As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.Server).%New()
	Set row.Name = name
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.AttachStatus = status
	If refused '= "" Set row.RefusedTools = $ListBuild(refused)
	Do $$$AssertStatusOK(row.%Save(), "the fixture row "_name_" is saved")
}

/// A tool row of the server with the classification.
Method MakeTool(server As %String, tool As %String, classification As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.ToolClassification).%New()
	Set row.Server = server
	Set row.Tool = tool
	Set row.Classification = classification
	Set row.Fingerprint = "zzfp"_..Number
	Set row.ChangedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(row.%Save(), "the fixture tool "_tool_" of "_server_" is saved")
}

/// The Config Store entry of the server, with the address and, when withSecret is 1, a bearer secret:// reference (the wallet key does not exist; the entry is not validated).
Method MakeEntry(server As %String, withSecret As %Boolean) [ Private ]
{
	Set details = {"transport": "remote", "url": (..#URL)}
	If withSecret Set details.auth = {"type": "bearer", "token": ("secret://OcuTalon_MCP_"_server_".Key#token")}
	Do $$$AssertStatusOK(##class(%ConfigStore.DescriptorManager).RebuildRegistry(), "the Config Store registry is rebuilt")
	Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).Create("AI", "MCP", "", "OcuTalon_"_server, details, "", "zz fixture", "%Admin_ConfigStore", "%Admin_ConfigStore", 1, 0), "the fixture entry of "_server_" is made")
}

/// A fixture approval row of the kind, in the state, whose ToolSource is the source.
Method MakeRow(kind As %String, state As %String, source As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow($Select(kind = "tool_call": "tool_call", 1: kind), "zz_lookup", "{}", source)
	Set row.ToolSource = source
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.ApprovalRows).Save(row, state, 3600, , .ref), "a fixture "_state_" "_kind_" row is saved")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
}

/// ListMcpServers through the real handler of a shadow SettingsOps probe.
Method List() As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.ListMcpServers).%New()
	Set command.ActingUser = "zzadmin"
	Set command.Origin = "web_admin"
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

/// The members of the array that belong to the test's servers (name or server in Names), in order, so that servers of other tests on the instance do not matter.
Method Mine(array As %DynamicArray) As %DynamicArray [ Private ]
{
	Set mine = []
	Set iterator = array.%GetIterator()
	While iterator.%GetNext(, .item) {
		Set name = $Select(item.%IsDefined("server"): item.server, 1: item.name)
		If $ListFind($ListFromString(..Names), name) Do mine.%Push(item)
	}
	Quit mine
}

/// Removes every fixture this test may have made, each attempted whatever happened before.
Method Clean() [ Private ]
{
	For i = 1:1:$Length(..Names, ",") {
		Set name = $Piece(..Names, ",", i)
		If name = "" Continue
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", name)
		If ##class(OcuTalon.Mcp.Server).NameIndexExists(name, .id) Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
		If ##class(%ConfigStore.Configuration).Exists("AI.MCP.OcuTalon_"_name) Do ##class(%ConfigStore.Configuration).Delete("AI.MCP.OcuTalon_"_name)
	}
	For i = 1:1:$Length(..Refs, ",") {
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen($Piece(..Refs, ",", i))
		If $IsObject(row) Do ##class(OcuTalon.Bridge.Data.ApprovalRequest).%DeleteId(row.%Id())
	}
}

/// What is left of the fixtures, as a text of places ("" when nothing).
Method Leftovers() As %String [ Private ]
{
	Set places = ""
	For i = 1:1:$Length(..Names, ",") {
		Set name = $Piece(..Names, ",", i)
		If name = "" Continue
		If ##class(OcuTalon.Mcp.Server).NameIndexExists(name) Set places = places_$ListBuild(name_" row")
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", name)
		If result.%Next(), result.%GetData(1) Set places = places_$ListBuild(name_" tool rows")
		If ##class(%ConfigStore.Configuration).Exists("AI.MCP.OcuTalon_"_name) Set places = places_$ListBuild(name_" entry")
	}
	For i = 1:1:$Length(..Refs, ",") {
		If $IsObject(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen($Piece(..Refs, ",", i))) Set places = places_$ListBuild("an approval row")
	}
	Quit $ListToString(places, ", ")
}

}
