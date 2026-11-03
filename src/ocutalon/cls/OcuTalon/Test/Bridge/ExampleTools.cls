/// Tests of the bridge example's tools (Story 13.2; AD-2, AD-6, AD-9, AD-10, AD-31; FR-5). Nothing is started or sent: the tests read the compiled
/// tool and toolset classes and call the tool methods. The governance of the tools through a running production (the hold, the answers, the
/// replay, rejection, expiry, the untrusted denial and the audit) is proved by release/standalone-bridge.sh in a namespace of its own.
///   - TestToolSet: the agent names the toolset, whose discovery lists exactly the three tools, each a method of OcuTalon.BridgeExample.Tools;
///   - TestLabels: each tool has its own step label, never the generic one;
///   - TestNoCodeClassification: no tool classifies itself in code (no CLASSIFICATION, READONLY, TRUSTEDOUTPUT or RESOURCES parameter and no
///     Classify method), so the developer's ToolClassification setting alone classifies it;
///   - TestAgentInstructions: the agent's instructions name the three tools, say that a call may be held or denied and must not be repeated,
///     keep the answer as the one JSON object, and no longer say that the agent has no tools;
///   - TestTools: each method returns its dynamic object, and the two that change something write their one event-log line.
Class OcuTalon.Test.Bridge.ExampleTools Extends %UnitTest.TestCase
{

Parameter TOOLS = "OcuTalon.BridgeExample.Tools";

Parameter TOOLSET = "OcuTalon.BridgeExample.ToolSet";

Parameter AGENT = "OcuTalon.BridgeExample.Agent";

/// The agent's TOOLSETS names the toolset, and its discovery lists exactly the three tools once each, with the tools class as the provider.
Method TestToolSet()
{
	Do $$$AssertEquals($Parameter(..#AGENT, "TOOLSETS"), ..#TOOLSET, "the example agent's TOOLSETS is the example's toolset")
	Set tools = $ClassMethod(..#TOOLSET, "%New").%Discover().tools
	Do $$$AssertEquals(tools.%Size(), 3, "the toolset offers three tools")
	Set found = ""
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set found = found _ $ListBuild(tool.name)
		Do $$$AssertEquals(tool.provider, ..#TOOLS, tool.name_" is a method of "_..#TOOLS)
		Do $$$AssertEquals(tool.metadata."origin_class", ..#TOOLS, tool.name_" says that it originates in "_..#TOOLS)
		Do $$$AssertTrue(tool.description '= "", tool.name_" has a description for the model")
	}
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Test.Agent.Runners).Sorted(found)), "example_archive_item,example_count_items,example_forward_item", "the tools are the three of the example, each once")
	Set own = $ClassMethod(..#TOOLS, "%New").%Discover().tools
	Do $$$AssertEquals(own.%Size(), 3, ..#TOOLS_" offers its three methods and nothing else")
	Set definition = ##class(%Dictionary.ClassDefinition).%OpenId(..#TOOLSET)
	Do $$$AssertEquals(definition.DependsOn, ..#TOOLS, "the toolset depends on the tool class")
	For method = "CountItems", "ForwardItem", "ArchiveItem" {
		Set return = ##class(%Dictionary.CompiledMethod).%OpenId(..#TOOLS_"||"_method).ReturnType
		Do $$$AssertTrue(return [ "DynamicObject", method_" returns a dynamic object: "_return)
	}
}

/// Each tool's label is its own class parameter, and none is the generic label (AD-9).
Method TestLabels()
{
	Set want("example_count_items") = "Counting the example's items"
	Set want("example_forward_item") = "Forwarding the item"
	Set want("example_archive_item") = "Archiving the item"
	Set name = ""
	For {
		Set name = $Order(want(name))
		Quit:name=""
		Set label = ##class(OcuTalon.Bridge.Adapter.StepBuffer).LabelFor(..#TOOLS, name)
		Do $$$AssertEquals(label, want(name), name_" has its own step label")
		Do $$$AssertNotEquals(label, ##class(OcuTalon.Bridge.Adapter.StepBuffer).#GENERICLABEL, name_" does not have the generic label")
		Do $$$AssertEquals($Parameter(..#TOOLS, "STEPLABEL"_$ZConvert($Translate(name, "_-"), "U")), want(name), name_"'s label is the class parameter STEPLABEL"_$ZConvert($Translate(name, "_-"), "U"))
	}
}

/// The tools hold no classification of their own (AD-10, AD-31): the gate finds no Classify method and no CLASSIFICATION, READONLY,
/// TRUSTEDOUTPUT or RESOURCES parameter for any of them, so only the ToolClassification setting of Decide can classify a tool.
Method TestNoCodeClassification()
{
	For name = "example_count_items", "example_forward_item", "example_archive_item" {
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Policy.Gate).HookFor(..#TOOLS, name), "", name_" has no Classify method")
		For base = "CLASSIFICATION", "READONLY", "TRUSTEDOUTPUT", "RESOURCES" {
			Do $$$AssertEquals(##class(OcuTalon.Bridge.Adapter.StepBuffer).ToolParameter(..#TOOLS, name, base), "", name_" declares no "_base)
		}
	}
	Set compiled = ##class(%Dictionary.CompiledClass).%OpenId(..#TOOLS)
	Set bad = ""
	For i = 1:1:compiled.Parameters.Count() {
		Set parameter = compiled.Parameters.GetAt(i).Name
		If (parameter [ "CLASSIFICATION") || (parameter [ "READONLY") || (parameter [ "TRUSTEDOUTPUT") || (parameter [ "RESOURCES") Set bad = bad _ $Select(bad = "": "", 1: ",") _ parameter
	}
	Do $$$AssertEquals(bad, "", "and the class declares no parameter of that kind at all")
}

/// The agent's instructions tell it about its tools (Story 13.2): the three tool names, that a tool may be held or denied and that such a
/// call is never repeated, and that the answer stays the one JSON object. The old sentence "You have no tools" is gone.
Method TestAgentInstructions()
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(..#AGENT_"||INSTRUCTIONS")
	Do $$$AssertTrue($IsObject(xdata), "the agent has instructions")
	If '$IsObject(xdata) Quit
	Set text = $Replace(xdata.Data.Read(1000000), $Char(13), "")
	Do $$$AssertTrue(text '[ "You have no tools", "they no longer say that the agent has no tools")
	For phrase = "example_count_items", "example_forward_item", "example_archive_item", "held for a person's approval or denied", "Never repeat a call that was held or denied", "the one JSON object" {
		Do $$$AssertTrue(text [ phrase, "the instructions say '"_phrase_"'")
	}
	Do $$$AssertTrue(text '[ "{{", "and they hold no template token")
}

/// Each method returns its dynamic object, and forward and archive write their one line to the event log. The test deletes the rows it wrote.
Method TestTools()
{
	Set count = $ClassMethod(..#TOOLS, "CountItems")
	Do $$$AssertEquals($ClassName(count), "%Library.DynamicObject", "CountItems returns a dynamic object")
	Do $$$AssertEquals(count.%GetTypeOf("items"), "number", "whose items is a number")
	Do $$$AssertTrue(count.items >= 0, "that is not negative: "_count.items)
	Set last = ..LastLogId()
	Set forwarded = $ClassMethod(..#TOOLS, "ForwardItem", "operations")
	Do $$$AssertEquals(forwarded.%ToJSON(), "{""forwarded"":1}", "ForwardItem answers forwarded 1")
	Do $$$AssertEquals(..LogLines(last, "ExampleTools: example_forward_item ran"), 1, "and writes its one line")
	Do $$$AssertEquals(..LogLines(last, "ExampleTools: example_archive_item ran"), 0, "and not the other tool's")
	Set forwarded = $ClassMethod(..#TOOLS, "ForwardItem")
	Do $$$AssertEquals(forwarded.%ToJSON(), "{""forwarded"":1}", "ForwardItem needs no team")
	Set archived = $ClassMethod(..#TOOLS, "ArchiveItem")
	Do $$$AssertEquals(archived.%ToJSON(), "{""archived"":1}", "ArchiveItem answers archived 1")
	Do $$$AssertEquals(..LogLines(last, "ExampleTools: example_archive_item ran"), 1, "and writes its one line")
	Do $$$AssertEquals(..LogLines(last, "ExampleTools: example_forward_item ran"), 2, "while the two ForwardItem calls wrote two")
	Do ..DeleteLines(last)
	Do $$$AssertEquals(..LogLines(last, "ExampleTools: example_forward_item ran")+..LogLines(last, "ExampleTools: example_archive_item ran"), 0, "the test's rows are deleted")
}

/// The highest id of the event log.
ClassMethod LastLogId() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The rows after id whose text is exactly the line.
ClassMethod LogLines(after As %Integer, line As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Text = ?", after, line)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// Deletes the tools' rows after id.
ClassMethod DeleteLines(after As %Integer) [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens_Util.Log WHERE ID > ? AND Text %STARTSWITH ?", after, "ExampleTools: ")
	While result.%Next() {
		Do ##class(Ens.Util.Log).%DeleteId(result.%GetData(1))
	}
}

}
