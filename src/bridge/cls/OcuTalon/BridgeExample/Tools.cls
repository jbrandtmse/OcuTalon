Include Ensemble

/// The tools of the bridge example's agent (AD-2, AD-6, AD-9, AD-10, FR-5): three tools of a developer's own, to show that the bridge governs
/// them. example_count_items only reads, example_forward_item changes something and example_archive_item changes something too. A tool holds
/// no classification of its own: no CLASSIFICATION, READONLY, TRUSTEDOUTPUT or RESOURCES parameter and no Classify method. The developer
/// classifies the tools in the ToolClassification setting of Decide, a System Default Settings row for this production, and the bridge
/// holds every call that is risky, or that no entry classifies, as an approval request until a person with the approval role answers it.
/// Each tool declares only its step label (STEPLABEL<NAME>, the tool's name in upper case with _ and - removed), which holds no argument and no
/// model text. A tool method runs inside AI Hub's callback, so it makes no AI Hub call and no Python call, and it returns a dynamic object.
/// The two tools that change something change nothing in the system: they write one line to the event log, so that a reader can count how
/// often each one ran. A public method of a tool class becomes a tool, so the class has no other public method.
Class OcuTalon.BridgeExample.Tools Extends %AI.Tool
{

/// The step labels of the three tools (AD-9).
Parameter STEPLABELEXAMPLECOUNTITEMS = "Counting the example's items";

Parameter STEPLABELEXAMPLEFORWARDITEM = "Forwarding the item";

Parameter STEPLABELEXAMPLEARCHIVEITEM = "Archiving the item";

/// Counts the items that the example has received so far. It only reads, and answers the number as items. Use it when the number of
/// items helps you decide.
ClassMethod CountItems() As %DynamicObject
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_BridgeExample_Msg.Item")
	Set count = 0
	If result.%Next() Set count = +result.%GetData(1)
	Quit {"items": (count)}
}

/// Forwards the item to a team, such as operations. This changes something, so a person may have to approve the call before it runs. It
/// answers forwarded 1 when it ran.
ClassMethod ForwardItem(team As %String(DESCRIPTION = "The team to forward the item to, such as operations.") = "") As %DynamicObject
{
	$$$LOGINFO("ExampleTools: example_forward_item ran")
	Quit {"forwarded": 1}
}

/// Archives the item. This changes something, so a person may have to approve the call before it runs. It answers archived 1 when it ran.
ClassMethod ArchiveItem() As %DynamicObject
{
	$$$LOGINFO("ExampleTools: example_archive_item ran")
	Quit {"archived": 1}
}

}
