/// Tests that OcuTalon's own MCP server can only offer read-only tools (Story 28.3, R-28.3-1; AD-10, AD-21). They need no production and change no record; the ones that look at the
/// online-demo flag set it for the test and put it back (OnAfterOneTest).
///   - TestShippedSpecification (AC 4): the specification is the toolset OcuTalon.Mcp.ServiceTools, ReadOnlyProblem is "", and the tools are exactly check_status and recent_activity of
///     OcuTalon.Mcp.ServiceRead, each safe, read-only and trusted output by the gate's readers with no Classify or Hold hook; the resource of the service is the installer's;
///   - TestChatDeclarationsAreShared: the classification, read-only and trusted-output flags and the step label of a served tool are the chat tool's own values;
///   - TestOnlyTwoPublicMethods: the only public methods that OcuTalon.Mcp.ServiceRead defines are its two tools;
///   - TestWidenedSpecificationIsRefused: a service whose specification adds a state-changing toolset (Test.Mcp.ZzWideService) has a ReadOnlyProblem that names save_memory, and its
///     OnAuthenticate refuses; the shipped service's OnAuthenticate lets a request through;
///   - TestEachKindOfProblem: ToolProblem names a tool that is outside the provider package, not read-only, risky, unclassified or classified or held by its arguments (Test.Mcp.ZzHookedTools), and says nothing of a safe read-only one;
///   - TestNoUnsafeToolIsOffered: walking every toolset of Install.Step.Tools.Toolsets, every agent's TOOLSETS and OcuTalon.Tools.McpProxy, no tool that is not safe and read-only has
///     the name of a served tool or OcuTalon.Mcp.ServiceRead as its provider;
///   - TestDescriptions: the descriptions of the two tools and of the toolset are the Contest Planner's texts, word for word.
Class OcuTalon.Test.Mcp.ServiceReadOnly Extends %UnitTest.TestCase
{

Parameter SERVICE = "OcuTalon.Mcp.Service";

Parameter READ = "OcuTalon.Mcp.ServiceRead";

Parameter TOOLSET = "OcuTalon.Mcp.ServiceTools";

Parameter WIDE = "OcuTalon.Test.Mcp.ZzWideService";

Parameter LOOSE = "OcuTalon.Test.Mcp.ZzLooseService";

Parameter BUFFER = "OcuTalon.Bridge.Adapter.StepBuffer";

Parameter GATE = "OcuTalon.Bridge.Policy.Gate";

Property OnlineBefore As %String;

Property OnlineSaved As %Boolean [ InitialExpression = 0 ];

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..OnlineSaved {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..OnlineBefore)
		Set ..OnlineSaved = 0
	}
	Quit $$$OK
}

/// Sets the public flag onlineDemo for the test; OnAfterOneTest puts it back.
Method SetOnlineDemo(value As %String) [ Private ]
{
	If '..OnlineSaved {
		Set ..OnlineBefore = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
		Set ..OnlineSaved = 1
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", value), "onlineDemo is set to '" _ value _ "'")
}

/// The tools of the toolset in tools(name) = provider.
ClassMethod ToolsOf(toolset As %String, Output tools) [ Private ]
{
	Kill tools
	Set list = $ClassMethod(toolset, "%New").%Discover().tools
	Set iterator = list.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set tools(tool.name) = tool.provider
	}
}

/// "" when the tool is safe, read-only and has no hook, else the first thing that it is not, by the gate's readers.
ClassMethod Unsafe(provider As %String, name As %String) As %String [ Private ]
{
	If $ClassMethod(..#BUFFER, "ToolParameter", provider, name, "CLASSIFICATION") '= "safe" Quit "not safe"
	If $ClassMethod(..#BUFFER, "ToolParameter", provider, name, "READONLY") '= 1 Quit "not read-only"
	If ($ClassMethod(..#GATE, "HookFor", provider, name, "Classify") '= "") || ($ClassMethod(..#GATE, "HookFor", provider, name, "Hold") '= "") Quit "classified by its arguments"
	Quit ""
}

Method TestShippedSpecification()
{
	Do $$$AssertEquals($Parameter(..#SERVICE, "SPECIFICATION"), ..#TOOLSET, "the specification is the one toolset OcuTalon.Mcp.ServiceTools")
	Do $$$AssertEquals($ClassMethod(..#SERVICE, "GetSpecification"), ..#TOOLSET, "and GetSpecification gives it")
	Do $$$AssertEquals($ClassMethod(..#SERVICE, "ReadOnlyProblem"), "", "no tool of it is a problem")
	Do ..ToolsOf(..#TOOLSET, .tools)
	Set names = ""
	Set name = ""
	For {
		Set name = $Order(tools(name))
		Quit:name=""
		Set names = names _ $Select(names = "": "", 1: ",") _ name
		Do $$$AssertEquals(tools(name), ..#READ, name _ " is a method of OcuTalon.Mcp.ServiceRead")
		Do $$$AssertEquals(..Unsafe(tools(name), name), "", name _ " is safe, read-only and has no hook, by the gate's readers")
		Do $$$AssertEquals($ClassMethod(..#BUFFER, "ToolParameter", tools(name), name, "TRUSTEDOUTPUT"), 1, name _ " is trusted output")
	}
	Do $$$AssertEquals(names, "check_status,recent_activity", "the tools are exactly check_status and recent_activity")
	Do $$$AssertEquals($Parameter(..#SERVICE, "RESOURCE"), $Parameter("OcuTalon.Install.Step.Mcp", "SERVICERESOURCE"), "the resource of the service is the one that the installer makes")
	Do $$$AssertEquals($Parameter(..#SERVICE, "CHANNEL"), "mcp", "the channel of a served call is mcp")
	Do $$$AssertEquals($Parameter(..#READ, "DEMOOFF"), $Parameter(..#SERVICE, "DEMOOFF"), "the tools and the service say the same on the online demo")
}

/// The served tools take their classification from the chat tools' declarations: the parameters of ServiceRead hold the very values of WatchTools and RecentActivity.
Method TestChatDeclarationsAreShared()
{
	For base = "CLASSIFICATION", "READONLY", "TRUSTEDOUTPUT", "STEPLABEL" {
		Do $$$AssertEquals($ClassMethod(..#BUFFER, "ToolParameter", ..#READ, "check_status", base), $ClassMethod(..#BUFFER, "ToolParameter", "OcuTalon.Tools.WatchTools", "check_status", base), "check_status has the chat tool's " _ base)
		Do $$$AssertEquals($ClassMethod(..#BUFFER, "ToolParameter", ..#READ, "recent_activity", base), $ClassMethod(..#BUFFER, "ToolParameter", "OcuTalon.Tools.RecentActivity", "recent_activity", base), "recent_activity has the chat tool's " _ base)
	}
	Do $$$AssertEquals($ClassMethod(..#BUFFER, "ToolParameter", ..#READ, "check_status", "READONLY"), 1, "control: and that is read-only")
}

/// The methods of OcuTalon.Mcp.ServiceRead that are public and defined in it (not inherited) are its two tools.
Method TestOnlyTwoPublicMethods()
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledMethod WHERE parent = ? AND Origin = ? AND Private = 0 ORDER BY Name", ..#READ, ..#READ)
	Set names = ""
	While result.%Next() {
		Set names = names _ $Select(names = "": "", 1: ",") _ result.%GetData(1)
	}
	Do $$$AssertEquals(names, "CheckStatus,RecentActivity", "the public methods of ServiceRead are its two tools")
}

Method TestWidenedSpecificationIsRefused()
{
	Do ..SetOnlineDemo(0)
	Do $$$AssertEquals($ClassMethod(..#SERVICE, "OnAuthenticate", "Basic", ""), 1, "control: the shipped service lets a request through off the online demo")
	Set problem = $ClassMethod(..#WIDE, "ReadOnlyProblem")
	Do $$$AssertTrue(problem [ "save_memory", "the widened specification's problem names save_memory: " _ problem)
	Do $$$AssertTrue(problem [ "No tool is offered.", "and says that no tool is offered")
	Set sc = $ClassMethod(..#WIDE, "OnAuthenticate", "Basic", "")
	Do $$$AssertStatusNotOK(sc, "OnAuthenticate of the widened service refuses")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "save_memory", "and its text names save_memory")
	Do $$$AssertEquals($ClassMethod(..#SERVICE, "ReadOnlyProblem", "OcuTalon.Mcp.ServiceTools"), "", "control: the shipped toolset alone has no problem")
	Do $$$AssertTrue($ClassMethod(..#SERVICE, "ReadOnlyProblem", "OcuTalon.Mcp.ServiceTools,OcuTalon.Tools.Memory") [ "save_memory", "a specification that adds the memory toolset is refused by the class method as well")
	Do $$$AssertTrue($ClassMethod(..#SERVICE, "ReadOnlyProblem", "Zz.NoSuchToolset") [ "could not be read", "a toolset that cannot be read is refused")
}

/// ToolProblem on the chat tools, with OcuTalon.Tools. as the provider package (Test.Mcp.ZzLooseService), so that each kind of problem is the only one.
Method TestEachKindOfProblem()
{
	Set loose = ..#LOOSE
	Do $$$AssertEquals($ClassMethod(loose, "ToolProblem", "OcuTalon.Tools.WatchTools", "check_status"), "", "check_status of the chat toolset is offered when its package is allowed")
	Do $$$AssertEquals($ClassMethod(loose, "ToolProblem", "OcuTalon.Tools.RecentActivity", "recent_activity"), "", "and so is recent_activity")
	Do $$$AssertTrue($ClassMethod(..#SERVICE, "ToolProblem", "OcuTalon.Tools.WatchTools", "check_status") [ "is not a method of a class in OcuTalon.Mcp.", "a provider outside OcuTalon.Mcp. is refused although it is safe and read-only")
	Do $$$AssertTrue($ClassMethod(loose, "ToolProblem", "OcuTalon.Tools.WatchTools", "start_watch") [ "is not read-only", "a safe tool that is not read-only is refused (start_watch)")
	Do $$$AssertTrue($ClassMethod(loose, "ToolProblem", "OcuTalon.Tools.McpCall", "call_mcp_tool") [ "is not classified safe", "a risky tool is refused (call_mcp_tool)")
	Do $$$AssertTrue($ClassMethod(loose, "ToolProblem", "OcuTalon.Tools.Names", "zz_none") [ "is not classified safe", "a tool that declares no classification is refused")
	Do $$$AssertEquals($ClassMethod(loose, "ToolProblem", "OcuTalon.Tools.EmailTools", "send_email") '= "", 1, "a tool that classifies by its arguments is refused (send_email)")
	Set hooked = "OcuTalon.Test.Mcp.ZzHookedTools"
	Do $$$AssertEquals(..Unsafe(hooked, "zz_hooked"), "classified by its arguments", "control: zz_hooked is safe and read-only by its parameters and has a Classify hook")
	Do $$$AssertEquals($ClassMethod(loose, "ToolProblem", hooked, "zz_hooked"), "The tool zz_hooked is classified or held by its arguments.", "a safe, read-only tool with a Classify hook is refused for the hook only")
	Do $$$AssertEquals($ClassMethod(loose, "ToolProblem", hooked, "zz_held"), "The tool zz_held is classified or held by its arguments.", "and so is one with a Hold hook")
}

/// No tool of the product that is not safe and read-only has the name of a served tool, or OcuTalon.Mcp.ServiceRead as its provider.
Method TestNoUnsafeToolIsOffered()
{
	Do ..ToolsOf(..#TOOLSET, .served)
	Set toolsets = ##class(OcuTalon.Install.Step.Tools).Toolsets()
	Set agents = ##class(OcuTalon.Install.SecurityOverview).CatalogClasses("Agents", "OcuTalon.Agent.")
	Set position = 0
	While $ListNext(agents, position, agent) {
		Set listed = $Parameter(agent, "TOOLSETS")
		For i = 1:1:$Length(listed, ",") {
			Set one = $ZStrip($Piece(listed, ",", i), "<>W")
			If (one '= "") && '$ListFind(toolsets, one) Set toolsets = toolsets _ $ListBuild(one)
		}
	}
	If '$ListFind(toolsets, "OcuTalon.Tools.McpProxy") Set toolsets = toolsets _ $ListBuild("OcuTalon.Tools.McpProxy")
	Set walked = 0
	Set unsafe = 0
	Set kinds = ""
	Set clashes = ""
	Set position = 0
	While $ListNext(toolsets, position, toolset) {
		Do ..ToolsOf(toolset, .tools)
		Set name = ""
		For {
			Set name = $Order(tools(name))
			Quit:name=""
			Set walked = walked + 1
			Set why = ..Unsafe(tools(name), name)
			If why = "" Continue
			Set unsafe = unsafe + 1
			If '$Find(kinds, why) Set kinds = kinds _ "|" _ why
			If $Data(served(name)) || (tools(name) = ..#READ) Set clashes = clashes _ " " _ name
		}
	}
	Do $$$AssertTrue(walked > 20, "control: the walk saw the product's tools: " _ walked)
	Do $$$AssertTrue(unsafe > 10, "control: and many of them are not safe and read-only: " _ unsafe)
	Do $$$AssertTrue($Find(kinds, "not read-only") && $Find(kinds, "not safe"), "control: of more than one kind (" _ kinds _ ")")
	Do $$$AssertEquals(clashes, "", "none of them has the name of a served tool or ServiceRead as its provider")
	Do $$$AssertTrue($ListFind(toolsets, "OcuTalon.Tools.Watching") && $ListFind(toolsets, "OcuTalon.Tools.McpProxy"), "control: the walk includes the chat toolsets and the MCP proxy")
}

/// The descriptions are the Planner's texts (P5a, P5b, P5c), word for word.
Method TestDescriptions()
{
	Set status = "Reads the latest results of your OcuTalon background checks, one per watched production and one for the queue-backlog check when you watch queue backlogs. The answer is ok with checks, in a fixed order. Each check has result: passed, failed, not_checked when the last run could not check, or empty when it has not run yet; entry: the name of what is checked, such as Orders production; finding: what the last run found, or why it could not check; and checked: when it last ran, in the instance's time. An empty list means that nothing is watched. When ok is false, the message says why."
	Set activity = "Tells what happened earlier in your OcuTalon session: your recent incidents (the last 24 hours, at most 5, newest first), each with its approvals and the result of its fix. The answer is ok with hours (the window) and incidents. An incident has production: the name to say; item: the production item that failed; count: how many failures; firstFailure and lastFailure: when, in the instance's time; element: the field at fault, empty when it is not known; causeCategory: the kind of cause, such as data_format_change; fixKind: the kind of fix that was proposed, empty when none was; state: open, awaiting_approval, fixing, resolved or closed; and approvals. An approval has answer: waiting, approved, rejected, expired or cancelled; channel: where it was answered, empty when nobody answered it; answered: when it was answered, or when it expired, and empty while it waits; and fix, which is null when no fix ran, otherwise resent (the failed messages sent again), wentThrough (how many of them went through), failedAgain and finished (false while the fix is still running). When incidents is empty, the answer has a message: say plainly that nothing is recorded for the last 24 hours, and never say that everything is fine or that nothing is wrong, because an empty list says nothing about now. When ok is false, the answer has only a message: say that the records could not be read, and say nothing about what happened."
	Set set = "Read-only tools that read your OcuTalon background check results and your recent incidents."
	Do $$$AssertEquals(..Described("CheckStatus"), status, "check_status has the ruled description")
	Do $$$AssertEquals(..Described("RecentActivity"), activity, "recent_activity has the ruled description")
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(..#TOOLSET _ "||Definition")
	Set text = $Select($IsObject(xdata): xdata.Data.Read(5000), 1: "")
	Do $$$AssertTrue(text [ ("<Description>" _ set _ "</Description>"), "the toolset has the ruled description")
	Do $$$AssertEquals($Parameter(..#READ, "NOSESSION"), "OcuTalon has no records for this IRIS user yet. Sign in to OcuTalon once, then ask again.", "NOSESSION is the ruled text")
	Do $$$AssertEquals($Parameter(..#READ, "CHECKSNOTREAD"), "Your background checks could not be read, so nothing is known about them.", "CHECKSNOTREAD is the ruled text")
	Do $$$AssertEquals($Parameter(..#READ, "NOTAUDITED"), "This call could not be written to the audit log, so nothing was read.", "NOTAUDITED is the ruled text")
	Do $$$AssertEquals($Parameter(..#READ, "NONE"), "No incident is recorded for your OcuTalon session in the last 24 hours. This says nothing about what is happening now.", "NONE is the ruled text")
	Do $$$AssertEquals($Parameter(..#READ, "NOTREAD"), "Your incidents could not be read, so nothing is known about what happened earlier.", "NOTREAD is the ruled text")
	Do $$$AssertEquals($Parameter(..#SERVICE, "DEMOOFF"), "OcuTalon's MCP server is off on the online demo.", "DEMOOFF is the ruled text")
}

/// The description of the method of ServiceRead, as the compiled class holds it (the doc comment).
ClassMethod Described(method As %String) As %String [ Private ]
{
	Set row = ##class(%Dictionary.CompiledMethod).%OpenId(..#READ _ "||" _ method)
	Quit $Select($IsObject(row): $ZStrip(row.Description, "<>WC"), 1: "")
}

}
