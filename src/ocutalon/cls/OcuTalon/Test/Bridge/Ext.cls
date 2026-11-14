/// Tests of the bridge's extension points and of its per-call context (Story 0.6, matrix rows 2, 6 and 7). Nothing starts
/// a production, and nothing is written to the audit log.
///   - TestAccessorInAnotherJob: a job that did not start the production reads the six extension classes of Decide (Story 19.5 added TurnToolsClass, Story 35.1 McpServersClass, Story 26.3 ContentClass)
///     from the production definition, and gets "" with an error for a bad setting, item, production or class;
///   - TestValueFor: the accessor's general read of a host setting of the Decide item, and its errors (Story 1.4); since Story 1.9 also of a setting of
///     an item's adapter, such as the AgentClass of a runner, when the target is Adapter;
///   - TestExtensionBases: HostSink lists exactly its eight event types, accepts each, builds its three payloads with
///     exactly their keys, and BridgeSink adds nothing and publishes no live event; the reply filter passes
///     text through, ReplyGuard removes a reserved sentence (Story 5.7; Test.Checks.Guard pins the rest), Classification classifies nothing, TurnTools
///     (Story 19.5) gives no tool and McpServers (Story 35.1) names no server and takes any report;
///   - TestWriteDefault (Story 1.7): WriteDefault creates the System Default Settings row of a setting (any class) with the value and the
///     description, changes the row when it exists, and ValueFor reads the value;
///   - TestMcpBases (Story 22.8): the base ClassifyMcp delegates to Classify with readOnly 0 and registered 1 (and gives "" for a source and name Classify does not know),
///     a subclass's Classify is the one it delegates to, and the base McpServers ToolsReadOnly says 0 for any server;
///   - TestContext: no context before Begin; Begin carries the request's fields and the SuperSession into Current and starts the taint, the host data, the
///     characters of the tool results and (Story 1.10) the count of the commands that the tools submit at their start; the
///     process-private context is invisible to another job; Put changes it; End removes it.
/// The run's number is n from ^OcuTalonTest("BridgeExt","n") (never reset); the child jobs report through
/// ^OcuTalonTest("BridgeExt",n,...), which OnBeforeAllTests and OnAfterAllTests delete with the reports of earlier runs.
Class OcuTalon.Test.Bridge.Ext Extends %UnitTest.TestCase
{

/// The production whose definition the accessor reads.
Parameter PRODUCTION = "OcuTalon.Production";

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..CleanRuns()
	Set ..Number = $Increment(^OcuTalonTest("BridgeExt", "n"))
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..CleanRuns()
	Quit $SYSTEM.Status.OK()
}

/// Row 2: from another job, ClassFor gives the host sink, the reply filter, the classification class and the turn tools class that the
/// definition names (the third through the initial value of its setting), and gives "" with an error status for the
/// setting ZzClass, the item Zz<n>, the production Zz<n>.Production, and, for Check, a class that does not extend its
/// base, an empty class and a class that does not exist.
Method TestAccessorInAnotherJob()
{
	Set run = $Name(^OcuTalonTest("BridgeExt", ..Number))
	Kill @run
	Job ##class(OcuTalon.Test.Bridge.Ext).AccessorProbe(..Number, ..#PRODUCTION)
	Do ..WaitFor($Name(@run@("done")), 1, 60)
	Do $$$AssertEquals($Get(@run@("done")), 1, "the job finished")
	Do $$$AssertEquals($Get(@run@("namespace")), $Namespace, "the job ran in this namespace")
	Do $$$AssertEquals($Get(@run@("HostSinkClass")), "OcuTalon.Core.BridgeSink|1", "HostSinkClass is OcuTalon.Core.BridgeSink")
	Do $$$AssertEquals($Get(@run@("ReplyFilterClass")), "OcuTalon.Checks.ReplyGuard|1", "ReplyFilterClass is OcuTalon.Checks.ReplyGuard")
	Do $$$AssertEquals($Get(@run@("ClassificationClass")), "OcuTalon.Mcp.Classification|1", "ClassificationClass is OcuTalon.Mcp.Classification (Story 22.8)")
	Do $$$AssertEquals($Get(@run@("TurnToolsClass")), "OcuTalon.Docs.TurnTools|1", "TurnToolsClass is OcuTalon.Docs.TurnTools")
	Do $$$AssertEquals($Get(@run@("McpServersClass")), "OcuTalon.Mcp.Attach|1", "McpServersClass is OcuTalon.Mcp.Attach")
	Do $$$AssertEquals($Get(@run@("ContentClass")), "OcuTalon.Agent.Content|1", "ContentClass is OcuTalon.Agent.Content (Story 26.3)")
	For case = "setting", "item", "production", "check", "checkEmpty", "checkMissing" {
		Do $$$AssertEquals($Get(@run@(case)), "|0", "the "_case_" case gives an empty class and an error status")
	}
	Do $$$AssertTrue($Get(@run@("checkText")) [ "does not extend", "the error of the check names the problem: "_$Get(@run@("checkText")))
	Do $$$AssertTrue($Get(@run@("checkEmptyText")) [ "names no class", "an empty class is refused as such: "_$Get(@run@("checkEmptyText")))
	Do $$$AssertTrue($Get(@run@("checkMissingText")) [ "is not compiled", "a class that does not exist is refused as such: "_$Get(@run@("checkMissingText")))
	Kill @run
}

/// WriteDefault (the one writer of System Default Settings rows, AD-19): a row of the Decide item of the example production (which no one starts)
/// is created with the value and the description for any host class, ValueFor then reads the value, and a second write changes the same row
/// instead of making another. The row is deleted again.
Method TestWriteDefault()
{
	Set accessor = "OcuTalon.Bridge.Ext.Accessor"
	Set production = "OcuTalon.BridgeExample.Production"
	Set id = production_"||Decide||*||TimerSeconds"
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(id)
	Try {
		Do $$$AssertStatusOK($ClassMethod(accessor, "WriteDefault", production, "Decide", "TimerSeconds", 33, "First write."), "a row is written")
		Do $$$AssertTrue(##class(Ens.Config.DefaultSettings).%ExistsId(id), "it exists, with the host class *")
		Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
		Do $$$AssertEquals(row.ProductionName_"|"_row.ItemName_"|"_row.HostClassName_"|"_row.SettingName_"|"_row.SettingValue_"|"_row.Description, production_"|Decide|*|TimerSeconds|33|First write.", "with the production, the item, the setting, the value and the description")
		Do $$$AssertEquals($ClassMethod(accessor, "ValueFor", "TimerSeconds", production, "Decide"), 33, "ValueFor reads the value")
		Do $$$AssertStatusOK($ClassMethod(accessor, "WriteDefault", production, "Decide", "TimerSeconds", 44, "Second write."), "the row is written again")
		Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
		Do $$$AssertEquals(row.SettingValue_"|"_row.Description, "44|Second write.", "which changed the row")
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Config.DefaultSettings WHERE ProductionName = ? AND ItemName = 'Decide' AND SettingName = 'TimerSeconds'", production)
		Do result.%Next()
		Do $$$AssertEquals(result.%GetData(1), 1, "and made no second row")
		Kill row
		Do $$$AssertStatusNotOK($ClassMethod(accessor, "WriteDefault", production, "Decide", "TimerSeconds", "x", "Not a number."), "a value that the setting's datatype refuses is an error status")
		Set stored = ##class(%SQL.Statement).%ExecDirect(, "SELECT SettingValue FROM Ens_Config.DefaultSettings WHERE ID = ?", id)
		Do stored.%Next()
		Do $$$AssertEquals(stored.%GetData(1), 44, "and the stored row keeps its value")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(id)
	Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%ExistsId(id), 0, "the row is deleted again")
}

/// ValueFor (Story 1.4) reads any host setting of the item, from the item's settings, the System Default Settings and the property's
/// initial value, and gives "" with an error for an item, a setting or a production that is none; ClassFor builds on it.
Method TestValueFor()
{
	Set accessor = "OcuTalon.Bridge.Ext.Accessor"
	Set value = $ClassMethod(accessor, "ValueFor", "ReplyFilterClass", ..#PRODUCTION, , .sc)
	Do $$$AssertStatusOK(sc, "the ReplyFilterClass of Decide is read")
	Do $$$AssertEquals(value, "OcuTalon.Checks.ReplyGuard", "it is the class that the production names")
	Do $$$AssertEquals($ClassMethod(accessor, "ClassFor", "ReplyFilterClass", ..#PRODUCTION), value, "which is what ClassFor gives")
	Set value = $ClassMethod(accessor, "ValueFor", "TimerSeconds", ..#PRODUCTION, , .sc)
	Do $$$AssertStatusOK(sc, "a setting that is no extension class is read too")
	Do $$$AssertTrue(value ? 1.N, "TimerSeconds is a whole number: "_value)
	Set value = $ClassMethod(accessor, "ValueFor", "DailyCostCapUSD", ..#PRODUCTION, , .sc)
	Do $$$AssertStatusOK(sc, "so is DailyCostCapUSD")
	Do $$$AssertTrue($IsValidNum(value, "", 0), "which is a number of 0 or more: "_value)
	Set value = $ClassMethod(accessor, "ValueFor", "ZzNoSuchSetting", ..#PRODUCTION, , .sc)
	Do $$$AssertEquals(value, "", "a setting that does not exist gives an empty value")
	Do $$$AssertStatusNotOK(sc, "and an error status")
	Set value = $ClassMethod(accessor, "ValueFor", "TimerSeconds", ..#PRODUCTION, "ZzNoSuchItem", .sc)
	Do $$$AssertEquals(value, "", "an item that does not exist gives an empty value")
	Do $$$AssertStatusNotOK(sc, "and an error status")
	Set value = $ClassMethod(accessor, "ValueFor", "TimerSeconds", "Zz.NoSuchProduction", , .sc)
	Do $$$AssertEquals(value, "", "a production that does not exist gives an empty value")
	Do $$$AssertStatusNotOK(sc, "and an error status")
	Set value = $ClassMethod(accessor, "ClassFor", "TimerSeconds", ..#PRODUCTION, , .sc)
	Do $$$AssertEquals(value, "", "ClassFor still refuses a setting that is no extension setting")
	Do $$$AssertStatusNotOK(sc, "with an error status")

	// a setting of the adapter: the AgentClass of a runner
	Set value = $ClassMethod(accessor, "ValueFor", "AgentClass", ..#PRODUCTION, "TriageAgent", .sc)
	Do $$$AssertEquals(value, "", "AgentClass is a setting of the adapter, so a read of a host setting does not find it")
	Do $$$AssertStatusNotOK(sc, "and gives an error status")
	For case = $ListBuild("TriageAgent", "OcuTalon.Agent.Triage"), $ListBuild("DiagnosisAgent", "OcuTalon.Agent.Diagnosis"), $ListBuild("ChatAgent", "OcuTalon.Agent.Chat") {
		Set value = $ClassMethod(accessor, "ValueFor", "AgentClass", ..#PRODUCTION, $List(case, 1), .sc, "Adapter")
		Do $$$AssertStatusOK(sc, "with the target Adapter the AgentClass of "_$List(case, 1)_" is read")
		Do $$$AssertEquals(value, $List(case, 2), "it is "_$List(case, 2))
	}
	Set value = $ClassMethod(accessor, "ValueFor", "TimerSeconds", ..#PRODUCTION, "Decide", .sc, "Adapter")
	Do $$$AssertEquals(value, "", "a host setting is not found as a setting of the adapter")
	Do $$$AssertStatusNotOK(sc, "with an error status")
	Set value = $ClassMethod(accessor, "ValueFor", "AgentClass", ..#PRODUCTION, "ZzNoSuchItem", .sc, "Adapter")
	Do $$$AssertEquals(value, "", "an item that does not exist gives an empty value for an adapter setting too")
	Do $$$AssertStatusNotOK(sc, "and an error status")
}

/// The job body of TestAccessorInAnotherJob: reads each case and records the class and 1 for OK, 0 for an error.
ClassMethod AccessorProbe(number As %Integer, production As %String)
{
	Set run = $Name(^OcuTalonTest("BridgeExt", number))
	Try {
		Set @run@("namespace") = $Namespace
		For setting = "HostSinkClass", "ReplyFilterClass", "ClassificationClass", "TurnToolsClass", "McpServersClass", "ContentClass" {
			Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor(setting, production, , .sc)
			Set @run@(setting) = class_"|"_$SYSTEM.Status.IsOK(sc)
		}
		Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("ZzClass", production, , .sc)
		Set @run@("setting") = class_"|"_$SYSTEM.Status.IsOK(sc)
		Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("HostSinkClass", production, "Zz"_number, .sc)
		Set @run@("item") = class_"|"_$SYSTEM.Status.IsOK(sc)
		Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("HostSinkClass", "Zz"_number_".Production", , .sc)
		Set @run@("production") = class_"|"_$SYSTEM.Status.IsOK(sc)
		Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).Check("HostSinkClass", "%Library.String")
		Set @run@("check") = "|"_$SYSTEM.Status.IsOK(sc)
		Set @run@("checkText") = $SYSTEM.Status.GetErrorText(sc)
		Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).Check("HostSinkClass", "")
		Set @run@("checkEmpty") = "|"_$SYSTEM.Status.IsOK(sc)
		Set @run@("checkEmptyText") = $SYSTEM.Status.GetErrorText(sc)
		Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).Check("HostSinkClass", "Zz"_number_".NoSuchClass")
		Set @run@("checkMissing") = "|"_$SYSTEM.Status.IsOK(sc)
		Set @run@("checkMissingText") = $SYSTEM.Status.GetErrorText(sc)
	} Catch exception {
		Set @run@("error") = exception.DisplayString()
	}
	Set @run@("done") = 1
}

/// Row 6: HostSink accepts each of its eight event types and lists exactly those in EVENTS, builds the three payloads
/// with exactly their keys, and BridgeSink extends it, does nothing and writes no live event; the reply filter and
/// ReplyGuard removes a reserved sentence (Story 5.7), Classify returns "", TurnTools gives no tool and McpServers lists no server (Story 35.1) and probes none (Story 22.9).
Method TestExtensionBases()
{
	Set expected = $ListBuild("turn.step", "decision.recorded", "approval.raised", "approval.answered", "approval.expired", "approval.cancelled", "approval.result", "budget.capped")
	Do $$$AssertEquals($ListFromString(##class(OcuTalon.Bridge.Ext.HostSink).#EVENTS), expected, "EVENTS lists exactly the eight event types")
	Set parameters = $ListBuild("TURNSTEP", "DECISIONRECORDED", "APPROVALRAISED", "APPROVALANSWERED", "APPROVALEXPIRED", "APPROVALCANCELLED", "APPROVALRESULT", "BUDGETCAPPED")
	For i = 1:1:8 {
		Do $$$AssertEquals($Parameter("OcuTalon.Bridge.Ext.HostSink", $List(parameters, i)), $List(expected, i), $List(parameters, i)_" is "_$List(expected, i))
	}
	Set before = ..LiveEvents()
	For class = "OcuTalon.Bridge.Ext.HostSink", "OcuTalon.Core.BridgeSink" {
		For i = 1:1:8 {
			Do $$$AssertStatusOK($ClassMethod(class, "OnEvent", $List(expected, i), "zz", {}), class_" accepts "_$List(expected, i))
		}
	}
	Do $$$AssertEquals(..LiveEvents(), before, "BridgeSink writes no live event")
	Do $$$AssertTrue($ClassMethod("OcuTalon.Core.BridgeSink", "%Extends", "OcuTalon.Bridge.Ext.HostSink"), "BridgeSink extends HostSink")
	Do $$$AssertEquals(..Keys(##class(OcuTalon.Bridge.Ext.HostSink).RefPayload("r1")), "ref", "the ref payload has the key ref")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.HostSink).RefPayload("r1").ref, "r1", "and carries the Ref")
	Do $$$AssertEquals(..Keys(##class(OcuTalon.Bridge.Ext.HostSink).TurnStepPayload("d1", "Asked the model")), "decisionRef,label", "the turn.step payload has the keys decisionRef and label")
	Set payload = ##class(OcuTalon.Bridge.Ext.HostSink).TurnStepPayload("d1", "Asked the model")
	Do $$$AssertEquals(payload.decisionRef_"|"_payload.label, "d1|Asked the model", "and carries both")
	Do $$$AssertEquals(..Keys(##class(OcuTalon.Bridge.Ext.HostSink).BudgetCappedPayload("2026-10-19")), "day", "the budget.capped payload has the key day")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.HostSink).BudgetCappedPayload("2026-10-19").day, "2026-10-19", "and carries the day")

	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.ReplyFilter).Filter("text"), "text", "the default filter returns the text")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("Everything I checked passed."), "", "ReplyGuard removes a reserved sentence (Story 5.7; Test.Checks.Guard pins the rest)")
	Do $$$AssertTrue($ClassMethod("OcuTalon.Checks.ReplyGuard", "%Extends", "OcuTalon.Bridge.Ext.ReplyFilter"), "ReplyGuard extends ReplyFilter")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Classification).Classify("OcuTalon.Tools.WatchReads", "read_event_log"), "", "Classify returns an empty string")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Classification).Classify("mcp:docs", "read_event_log", {"a": 1}), "", "also for an MCP source and with arguments")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Ext.TurnTools).Tools("zzowner", "turn", .tools), "TurnTools answers OK")
	Do $$$AssertEquals(tools.Count(), 0, "and gives no tool (Story 19.5)")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Ext.McpServers).Servers(.servers), "McpServers answers OK")
	Do $$$AssertTrue($IsObject(servers) && servers.%IsA("%Library.DynamicArray") && (servers.%Size() = 0), "and names no server (Story 35.1)")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Ext.McpServers).OnAttach("zz", {"status": "attached", "reason": "", "tools": [], "refused": []}), "and takes any report without doing anything")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.McpServers).Probe("zz", "AI.MCP.OcuTalon_zz"), "", "and probes nothing: Probe gives an empty string, which is no probe (Story 22.9)")
	Do $$$AssertTrue($ClassMethod("OcuTalon.Mcp.Attach", "%Extends", "OcuTalon.Bridge.Ext.McpServers"), "OcuTalon.Mcp.Attach extends McpServers")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.McpServers).ProxyToolSet(), "", "and offers no proxy: ProxyToolSet gives an empty string (Story 22.3)")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Attach).ProxyToolSet(), "OcuTalon.Tools.McpProxy", "OcuTalon's class offers the governed proxy toolset")
}

/// Story 22.4 (AD-10, AD-31; condition 4): ServerOf(toolref) of the McpServersClass extension. The bridge's base names no server for any toolref, so the bridge alone holds and replays
/// no MCP call. OcuTalon's class (Mcp.Attach) names the server only for exactly mcp:remote:@{config:AI.MCP.OcuTalon_<name>} with a name that matches the pattern of a server name,
/// and Toolref is its inverse (and gives nothing for a name that does not match). A toolref that the class does not know gets "": the call it classifies is unclassified.
Method TestServerOf()
{
	Set base = "OcuTalon.Bridge.Ext.McpServers"
	Set attach = "OcuTalon.Mcp.Attach"
	Set known = "mcp:remote:@{config:AI.MCP.OcuTalon_zzdocs}"
	Do $$$AssertEquals($ClassMethod(base, "ServerOf", known), "", "the base names no server for a toolref of OcuTalon's form")
	Do $$$AssertEquals($ClassMethod(base, "ServerOf", "") _ $ClassMethod(base, "ServerOf", "mcp:zzserver"), "", "nor for any other")
	Do $$$AssertEquals($ClassMethod(attach, "ServerOf", known), "zzdocs", "OcuTalon's class names the server for the form that it attaches")
	Do $$$AssertEquals($ClassMethod(attach, "Toolref", "zzdocs"), known, "Toolref is the inverse")
	Do $$$AssertEquals($ClassMethod(attach, "ServerOf", $ClassMethod(attach, "Toolref", "Zz_9")), "Zz_9", "also for a name with capitals, digits and an underscore")
	Set unknown = $ListBuild("", "mcp:zzserver", "mcp:remote:@{config:AI.MCP.OcuTalon_}", "mcp:remote:@{config:AI.MCP.OcuTalon_1bad}", "mcp:remote:@{config:AI.MCP.OcuTalon_zz-docs}", "mcp:remote:@{config:AI.MCP.OcuTalon_zzdocs} ", "MCP:remote:@{config:AI.MCP.OcuTalon_zzdocs}", "mcp:remote:@{config:AI.MCP.Other_zzdocs}", "mcp:remote:@{config:AI.MCP.OcuTalon_zzdocs", "iris:Zz.Toolset", "mcp:remote:@{config:AI.MCP.OcuTalon_" _ $Justify("", 41) _ "}")
	Set position = 0
	While $ListNext(unknown, position, text) {
		Do $$$AssertEquals($ClassMethod(attach, "ServerOf", $Translate(text, " ", "a")) _ $ClassMethod(attach, "ServerOf", text), "", "'" _ $Extract(text, 1, 50) _ "' is no toolref of a server")
	}
	Do $$$AssertEquals($ClassMethod(attach, "Toolref", "") _ $ClassMethod(attach, "Toolref", "1x") _ $ClassMethod(attach, "Toolref", "a b") _ $ClassMethod(attach, "Toolref", "zz}"), "", "Toolref gives nothing for a name that does not match")
}

/// Story 22.3: the proxy's pieces in the bridge. The base ClassifyMcp gives no resource (so the bridge alone checks no privilege for an MCP call), and OcuTalon's names the server's
/// resource. SetMcpTools takes the host's names for the servers (a dynamic object of name to toolref) and McpToolref and McpServerOf read them both ways; a member that is not an
/// MCP toolref, or whose name is empty or too long, is left out; a second SetMcpTools replaces them, one without servers clears them, Begin and End end them, and they are not a
/// field. NoteRerouted keeps the server of each rewritten call by tool name, in order (ReroutedServer), and Begin ends the notes. Gate MCPPROXY is Tools.Names CALLMCPTOOL.
Method TestProxyBases()
{
	Set base = "OcuTalon.Bridge.Ext.Classification"
	Do $$$AssertEquals($ClassMethod(base, "ClassifyMcp", "mcp:docs", "x", "fp").%IsDefined("resource"), 0, "the base ClassifyMcp names no resource")
	Do $$$AssertEquals($Parameter("OcuTalon.Bridge.Policy.Gate", "MCPPROXY"), $Parameter("OcuTalon.Tools.Names", "CALLMCPTOOL"), "the gate's name for the proxy is the one of Tools.Names")
	Do $$$AssertEquals($Parameter("OcuTalon.Bridge.Policy.Gate", "MCPLABEL"), "Running {tool} on {server}", "the step label of an MCP call (text 1)")
	Do ##class(OcuTalon.Bridge.Context).End()
	Set context = "OcuTalon.Bridge.Context"
	Do $$$AssertEquals($ClassMethod(context, "McpToolref", "zzs") _ "|" _ $ClassMethod(context, "McpServerOf", "mcp:zzs"), "|", "with no context there is no name and no toolref")
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Try {
		Do $$$AssertStatusOK($ClassMethod(context, "Begin", request), "Begin")
		Set catalog = [{"tool_ref": "mcp:zzs", "name": "a", "description": "A.", "parameters": {}}]
		Do $$$AssertStatusOK($ClassMethod(context, "SetMcpTools", catalog, {"zzs": "mcp:zzs", "Zzt": "MCP:zzt", "zzu": "iris:Zz.Toolset", "zzv": 5, "": "mcp:zzw", "zzx": ("mcp:" _ $Justify("", 401))}), "SetMcpTools takes the servers' names")
		Do $$$AssertEquals($ClassMethod(context, "McpToolref", "zzs") _ "|" _ $ClassMethod(context, "McpToolref", "Zzt"), "mcp:zzs|MCP:zzt", "McpToolref gives the toolref of a name, in any case of its prefix")
		Do $$$AssertEquals($ClassMethod(context, "McpServerOf", "mcp:zzs") _ "|" _ $ClassMethod(context, "McpServerOf", "MCP:zzt"), "zzs|Zzt", "and McpServerOf the name of a toolref")
		Do $$$AssertEquals($ClassMethod(context, "McpToolref", "zzu") _ $ClassMethod(context, "McpToolref", "zzv") _ $ClassMethod(context, "McpToolref", "zzx") _ $ClassMethod(context, "McpToolref", ""), "", "a member that is no MCP toolref, no text, too long or with an empty name is left out")
		Do $$$AssertEquals($ClassMethod(context, "McpServerOf", "iris:Zz.Toolset") _ $ClassMethod(context, "McpServerOf", "mcp:zzw") _ $ClassMethod(context, "McpServerOf", ""), "", "also on the read side: the toolref of the member with an empty name has no server")
		Do $$$AssertEquals($Length($ClassMethod(context, "McpFingerprint", "mcp:zzs", "a")), 64, "the map of the tools is made alongside")
		Do $$$AssertTrue($Parameter(context, "FIELDS") '[ $Parameter(context, "MCPSERVERS"), "the names are not a field")
		Do $$$AssertStatusNotOK($ClassMethod(context, "Put", $Parameter(context, "MCPSERVERS"), "x"), "and Put refuses them")
		Do $$$AssertStatusOK($ClassMethod(context, "SetMcpTools", catalog, {"zzy": "mcp:zzy"}), "a second call")
		Do $$$AssertEquals($ClassMethod(context, "McpToolref", "zzs") _ "|" _ $ClassMethod(context, "McpToolref", "zzy"), "|mcp:zzy", "replaces the names")
		Do $$$AssertStatusOK($ClassMethod(context, "SetMcpTools", catalog), "and one without names")
		Do $$$AssertEquals($ClassMethod(context, "McpToolref", "zzy"), "", "clears them")
		Do $ClassMethod(context, "NoteRerouted", "a", "zzs")
		Do $ClassMethod(context, "NoteRerouted", "a", "zzt")
		Do $ClassMethod(context, "NoteRerouted", "b", "zzs")
		Do $ClassMethod(context, "NoteRerouted", "", "zzs")
		Do $ClassMethod(context, "NoteRerouted", "c", "")
		Do $$$AssertEquals($ClassMethod(context, "ReroutedServer", "a", 1) _ "," _ $ClassMethod(context, "ReroutedServer", "a", 2) _ "," _ $ClassMethod(context, "ReroutedServer", "b", 1), "zzs,zzt,zzs", "the notes of a tool name are kept in order")
		Do $$$AssertEquals($ClassMethod(context, "ReroutedServer", "a", 3) _ $ClassMethod(context, "ReroutedServer", "a", 0) _ $ClassMethod(context, "ReroutedServer", "c", 1) _ $ClassMethod(context, "ReroutedServer", "", 1), "", "a third note, a note 0, an empty server and an empty name give none")
		Do $$$AssertTrue($Parameter(context, "FIELDS") '[ $Parameter(context, "REROUTED"), "the notes are not a field")
		Do $$$AssertStatusOK($ClassMethod(context, "Begin", request), "Begin again")
		Do $$$AssertEquals($ClassMethod(context, "ReroutedServer", "a", 1), "", "ends the notes")
	} Catch exception {
		Do $$$AssertTrue(0, "the proxy bases test threw: " _ exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals($ClassMethod(context, "McpServerOf", "mcp:zzs") _ $ClassMethod(context, "ReroutedServer", "a", 1), "", "End removes them with the context")
}

/// Story 22.8: the base ClassifyMcp answers {"classification": Classify(source, name), "readOnly": 0, "registered": 1} for any source, name and fingerprint,
/// and a subclass that only overrides Classify (the fixture ZzGateClassification) is delegated to; McpServers ToolsReadOnly says 0 for any server, and the
/// OcuTalon class that overrides it (Mcp.Attach) extends the base. The turn's MCP map (Context SetMcpTools, McpFingerprint): an entry whose tool_ref starts mcp:
/// (in any case) gets the 64-character hexadecimal fingerprint of its server (the tool_ref), name, description and parameters; an entry of another tool_ref, with no name,
/// or with parameters that are text and not JSON gets none; a second call replaces the map; there is no map and no fingerprint without a context; Begin and End
/// end the map; and the map is not a field of the context.
Method TestMcpBases()
{
	Set base = "OcuTalon.Bridge.Ext.Classification"
	Set answer = $ClassMethod(base, "ClassifyMcp", "mcp:docs", "read_event_log", "any")
	Do $$$AssertEquals(answer.%ToJSON(), {"classification": "", "readOnly": 0, "registered": 1}.%ToJSON(), "the base ClassifyMcp delegates to Classify, which classifies nothing, and registers every server")
	Do $$$AssertEquals($ClassMethod(base, "ClassifyMcp", "mcp:docs", "read_event_log").%ToJSON(), answer.%ToJSON(), "also with no fingerprint")
	Set fixture = "OcuTalon.Test.Bridge.ZzGateClassification"
	Do $$$AssertEquals($ClassMethod(fixture, "ClassifyMcp", "mcp:zzserver", "zz_mcp_safe", "").%ToJSON(), {"classification": "safe", "readOnly": 0, "registered": 1}.%ToJSON(), "a subclass that overrides Classify only is delegated to: safe, readOnly 0, registered 1")
	Do $$$AssertEquals($ClassMethod(fixture, "ClassifyMcp", "mcp:zzserver", "zz_mcp_other", "").%ToJSON(), answer.%ToJSON(), "and its tools it does not know are unclassified")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.McpServers).ToolsReadOnly("zz"), 0, "the base McpServers says 0 for any server")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.McpServers).ToolsReadOnly(""), 0, "also for none")
	Do $$$AssertTrue($ClassMethod("OcuTalon.Mcp.Classification", "%Extends", base), "OcuTalon.Mcp.Classification extends Classification")

	Do ##class(OcuTalon.Bridge.Context).End()
	Set context = "OcuTalon.Bridge.Context"
	Set catalog = [{"tool_ref": "mcp:remote:zz", "name": "a", "description": "A.", "parameters": {"type": "object"}}]
	Do $$$AssertStatusNotOK($ClassMethod(context, "SetMcpTools", catalog), "SetMcpTools without a context is an error")
	Do $$$AssertEquals($ClassMethod(context, "McpFingerprint", "mcp:remote:zz", "a"), "", "and with no context there is no fingerprint")
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Try {
		Do $$$AssertStatusOK($ClassMethod(context, "Begin", request), "Begin")
		Do $$$AssertEquals($ClassMethod(context, "McpFingerprint", "mcp:remote:zz", "a"), "", "a context starts with no map")
		Set catalog = [
			{"tool_ref": "mcp:remote:zz", "name": "a", "description": "A.", "parameters": {"type": "object", "properties": {"id": {"type": "string"}}}},
			{"tool_ref": "MCP:remote:zz", "name": "b", "description": "B.", "parameters": {}},
			{"tool_ref": "iris:Zz.Toolset", "name": "c", "description": "C.", "parameters": {}},
			{"tool_ref": "mcp:remote:zz", "name": "", "description": "No name.", "parameters": {}},
			{"tool_ref": "mcp:remote:zz", "name": "d", "description": "D.", "parameters": "not json"},
			{"name": "e", "description": "No tool_ref.", "parameters": {}}, "text"]
		Do $$$AssertStatusOK($ClassMethod(context, "SetMcpTools", catalog), "SetMcpTools takes a catalog")
		Set first = $ClassMethod(context, "McpFingerprint", "mcp:remote:zz", "a")
		Do $$$AssertTrue(($Length(first) = 64) && ($Translate(first, "0123456789abcdef") = ""), "an MCP tool has a fingerprint of 64 lower-case hexadecimal characters: " _ first)
		Do $$$AssertEquals(first, $ClassMethod(context, "ToolFingerprint", "mcp:remote:zz", "a", "A.", {"properties": {"id": {"type": "string"}}, "type": "object"}), "it is ToolFingerprint of the tool_ref, the name, the description and the parameters, whatever the order of the keys")
		Do $$$AssertEquals($Length($ClassMethod(context, "McpFingerprint", "MCP:remote:zz", "b")), 64, "a tool_ref that starts MCP: counts in any case")
		Do $$$AssertEquals($ClassMethod(context, "McpFingerprint", "iris:Zz.Toolset", "c"), "", "a tool_ref that does not start mcp: has none")
		Do $$$AssertEquals(..McpKeys(), "MCP:remote:zz|b,mcp:remote:zz|a", "the map holds only the MCP tools with a tool_ref, a name and JSON parameters (no c, d, e or nameless tool)")
		Do $$$AssertEquals($ClassMethod(context, "McpFingerprint", "mcp:remote:zz", "d"), "", "a tool whose parameters are text that is not JSON has none")
		Do $$$AssertEquals($ClassMethod(context, "McpFingerprint", "mcp:remote:other", "a"), "", "a tool is keyed by its server too")
		Do $$$AssertEquals($ClassMethod(context, "McpFingerprint", "mcp:remote:zz", "A"), "", "and by the exact letter case of its name")
		Set node = $Parameter(context, "MCP")
		Set wide = ""
		For i = 1:1:400 Set wide = wide _ $Char(20000 + (i # 7))
		Set longRef = "mcp:remote:@{config:AI.MCP.OcuTalon_" _ $Translate($Justify("", 40), " ", "z") _ "}"
		Do $$$AssertStatusOK($ClassMethod(context, "SetMcpTools", [{"tool_ref": "mcp:remote:zz", "name": ($Justify("", 400)_"x"), "description": "Long.", "parameters": {}}, {"tool_ref": ("mcp:remote:" _ $Justify("", 400)), "name": "a", "description": "Long.", "parameters": {}}, {"tool_ref": (longRef), "name": (wide), "description": "Wide.", "parameters": {}}]), "a catalog of tools whose name or tool_ref is too long to key, alone or together")
		Do $$$AssertEquals($Data(^||OcuTalonBP.Context(node)), 0, "leaves them out of the map, whatever the read side does")
		Do $$$AssertEquals($ClassMethod(context, "McpFingerprint", longRef, wide), "", "and the read side gives none for a pair too long to key together")
		Do $$$AssertStatusOK($ClassMethod(context, "SetMcpTools", [{"tool_ref": "mcp:remote:zz", "name": "a", "description": "A.", "parameters": {"type": "object", "properties": {"id": {"type": "string"}}}}]), "the map is made again")
		Do $$$AssertEquals($ClassMethod(context, "ToolFingerprint", "mcp:remote:zz", "a", "A.", {}) '= $ClassMethod(context, "ToolFingerprint", "mcp:remote:zy", "a", "A.", {}), 1, "another server gives another fingerprint")
		Do $$$AssertEquals($ClassMethod(context, "ToolFingerprint", "mcp:remote:zz", "a", "A.", {}) '= $ClassMethod(context, "ToolFingerprint", "mcp:remote:zz", "b", "A.", {}), 1, "and so does another name")
		Do $$$AssertTrue($Parameter(context, "FIELDS") '[ "mcp", "the map is not a field")
		Do $$$AssertStatusNotOK($ClassMethod(context, "Put", "mcp", "x"), "and Put refuses it")

		Do $$$AssertStatusOK($ClassMethod(context, "SetMcpTools", [{"tool_ref": "mcp:remote:zz", "name": "b", "description": "B.", "parameters": {}}]), "a second SetMcpTools")
		Do $$$AssertEquals($ClassMethod(context, "McpFingerprint", "mcp:remote:zz", "a"), "", "replaces the map")
		Do $$$AssertEquals($Length($ClassMethod(context, "McpFingerprint", "mcp:remote:zz", "b")), 64, "with the new tools")
		Do $$$AssertStatusNotOK($ClassMethod(context, "SetMcpTools", "text"), "a catalog that is no array is an error")
		Do $$$AssertEquals($Length($ClassMethod(context, "McpFingerprint", "mcp:remote:zz", "b")), 64, "which leaves the map as it was")
		Do $$$AssertStatusOK($ClassMethod(context, "Begin", request), "Begin again")
		Do $$$AssertEquals($ClassMethod(context, "McpFingerprint", "mcp:remote:zz", "b"), "", "ends the map")
		Do $$$AssertStatusOK($ClassMethod(context, "SetMcpTools", [{"tool_ref": "mcp:remote:zz", "name": "b", "description": "B.", "parameters": {}}]), "a map is made again")
	} Catch exception {
		Do $$$AssertTrue(0, "the MCP map test threw: " _ exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals($Data(^||OcuTalonBP.Context), 0, "End removes the context, and the map with it")
	Do $$$AssertEquals($ClassMethod(context, "McpFingerprint", "mcp:remote:zz", "b"), "", "so there is no fingerprint")
}

/// The keys of the turn's MCP map (Context node MCP) as "server|name", joined by "," in the order of the global.
ClassMethod McpKeys() As %String [ Private ]
{
	Set node = $Parameter("OcuTalon.Bridge.Context", "MCP")
	Set keys = ""
	Set server = ""
	For {
		Set server = $Order(^||OcuTalonBP.Context(node, server))
		Quit:server=""
		Set name = ""
		For {
			Set name = $Order(^||OcuTalonBP.Context(node, server, name))
			Quit:name=""
			Set keys = keys _ $Select(keys = "": "", 1: ",") _ server _ "|" _ name
		}
	}
	Quit keys
}

/// Row 7: with no context, Active is 0 and Current is empty. After Begin, Active is 1 and Current carries the request's
/// fields and the SuperSession; the taint starts at 0. Another job sees no context. After Put("Tainted", 1), Current
/// is tainted; a name that is not a field is refused. A second Begin replaces the context and starts the taint and the
/// host data again. After End, Active is 0 again.
Method TestContext()
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "no context before Begin")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current(), "", "Current is empty before Begin")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.Context).Put("Tainted", 1), "Put without a context is an error")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.Context).Begin("not a request"), "Begin takes a request")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and starts nothing")

	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.ItemId = "zzitem"_..Number
	Set request.DecisionRef = "zzdec"_..Number
	Set request.OwnerRef = "zzowner"_..Number
	Set request.TraceRef = "zztrace"_..Number
	Set request.Channel = "web"
	Set request.ThreadSessionId = 4000 + ..Number
	Set super = "zzss"_..Number
	Try {
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, super), "Begin")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 1, "the context is active")
		Set current = ##class(OcuTalon.Bridge.Context).Current()
		Do $$$AssertTrue($IsObject(current), "Current is the context")
		Do $$$AssertEquals(current.Kind_"|"_current.Provenance_"|"_current.ItemId_"|"_current.DecisionRef, "turn|user|zzitem"_..Number_"|zzdec"_..Number, "Current carries Kind, Provenance, ItemId and DecisionRef")
		Do $$$AssertEquals(current.OwnerRef_"|"_current.TraceRef_"|"_current.Channel_"|"_current.ThreadSessionId, "zzowner"_..Number_"|zztrace"_..Number_"|web|"_(4000 + ..Number), "Current carries OwnerRef, TraceRef, Channel and ThreadSessionId")
		Do $$$AssertEquals(current.SuperSession, super, "Current carries the SuperSession")
		Do $$$AssertEquals(current.Tainted, 0, "the taint starts at 0")
		Do $$$AssertEquals(current.HostData, "", "and the host data is empty")
		Do $$$AssertEquals(current.ToolResultChars, 0, "and the characters of the tool results start at 0")
		Do $$$AssertEquals(current.CommandCount, 0, "and so does the count of the commands that the tools submit (Story 1.10)")
		Do $$$AssertTrue($ListFind($ListFromString(##class(OcuTalon.Bridge.Context).#FIELDS), "CommandCount"), "CommandCount is a field of the context")
		Do ##class(OcuTalon.Bridge.Context).Put("CommandCount", 3)
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().CommandCount, 3, "Put sets it")
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, super), "Begin again")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().CommandCount, 0, "a context that begins again starts the count at 0 again")

		Set run = $Name(^OcuTalonTest("BridgeExt", ..Number))
		Kill @run
		Job ##class(OcuTalon.Test.Bridge.Ext).ContextProbe(..Number)
		Do ..WaitFor($Name(@run@("done")), 1, 60)
		Do $$$AssertEquals($Get(@run@("done")), 1, "the other job finished")
		Do $$$AssertEquals($Get(@run@("active")), 0, "the other job sees no context")
		Do $$$AssertEquals($Get(@run@("current")), "", "and an empty Current")
		Kill @run

		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Put("Tainted", 1), "Put Tainted")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().Tainted, 1, "Current is tainted")
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Put("HostData", "{""rows"":[]}"), "Put HostData")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, "{""rows"":[]}", "Current carries the host data")
		Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.Context).Put("ZzField", 1), "a name that is not a field is refused")

		Set again = ##class(OcuTalon.Bridge.Msg.Request).%New()
		Set again.OwnerRef = "zzagain"_..Number
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(again, "zzss2"_..Number), "a second Begin replaces the context")
		Set current = ##class(OcuTalon.Bridge.Context).Current()
		Do $$$AssertEquals(current.OwnerRef_"|"_current.SuperSession_"|"_current.ItemId, "zzagain"_..Number_"|zzss2"_..Number_"|", "Current carries only the second request's fields")
		Do $$$AssertEquals(current.Tainted_"|"_current.HostData, "0|", "and the taint and the host data start again")
	} Catch exception {
		Do $$$AssertTrue(0, "the context test threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "no context after End")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current(), "", "Current is empty after End")
}

/// The job body of TestContext: records whether this process has a context.
ClassMethod ContextProbe(number As %Integer)
{
	Set run = $Name(^OcuTalonTest("BridgeExt", number))
	Set @run@("active") = ##class(OcuTalon.Bridge.Context).Active()
	Set @run@("current") = ##class(OcuTalon.Bridge.Context).Current()
	Set @run@("done") = 1
}

/// --- helpers ---
/// Deletes the reports of every run, this one and the runs that failed before: every node under the counter's level
/// except the counter itself.
ClassMethod CleanRuns() [ Private ]
{
	Set run = ""
	For {
		Set run = $Order(^OcuTalonTest("BridgeExt", run))
		Quit:run=""
		If run '= "n" Kill ^OcuTalonTest("BridgeExt", run)
	}
}

/// Waits up to seconds for the global node named by ref to reach count.
ClassMethod WaitFor(ref As %String, count As %Integer, seconds As %Integer) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While (+$Get(@ref) < count) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

/// The keys of a dynamic object as a comma list, in order.
ClassMethod Keys(object As %DynamicObject) As %String [ Private ]
{
	Set keys = ""
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys _ $Select(keys = "": "", 1: ",") _ key
	}
	Quit keys
}

/// The rows of the live event table.
ClassMethod LiveEvents() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Live.Event")
	Do result.%Next()
	Quit result.%GetData(1)
}

}
