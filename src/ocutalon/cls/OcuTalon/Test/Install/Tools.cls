/// Tests of the Tools area and of the reader of the tool parameters (Story 3.1; AD-24, Consistency Conventions: Tool resources): the grammar of
/// RESOURCES, the grants of a toolset, the suffix rule of StepBuffer.ToolParameter, and the real declarations. They change no role, user or
/// resource: the Roles step's use of the declarations is tested in OcuTalon.Test.Install.Registry.
Class OcuTalon.Test.Install.Tools Extends %UnitTest.TestCase
{

/// The area under test.
Parameter AREA = "OcuTalon.Install.Step.Tools";

/// The fixture toolset and its tool class (alpha, beta and gamma).
Parameter TOOLSET = "OcuTalon.Test.Install.ZzGrantToolset";

Parameter TOOLS = "OcuTalon.Test.Install.ZzGrantTools";

/// The grammar: pairs of resource:permission, the permission made of R, W and U; an empty value is no pair.
Method TestParse()
{
	Set pairs = $ClassMethod(..#AREA, "Parse", "ZzRes:R", "zz")
	Do $$$AssertTrue(pairs.%IsA("%Library.DynamicArray"), "a dynamic array")
	Do $$$AssertEquals(pairs.%Size(), 1, "one pair")
	Do $$$AssertEquals(pairs.%Get(0).resource, "ZzRes", "the resource")
	Do $$$AssertEquals(pairs.%Get(0).permission, "R", "the permission")

	Set pairs = $ClassMethod(..#AREA, "Parse", "ZzA:R,%ZzB_c:WU,ZzD:RWU", "zz")
	Do $$$AssertEquals(pairs.%Size(), 3, "three pairs")
	Do $$$AssertEquals(pairs.%Get(1).resource_":"_pairs.%Get(1).permission, "%ZzB_c:WU", "the second pair keeps its resource and its two letters")
	Do $$$AssertEquals(pairs.%Get(2).permission, "RWU", "and the third its three")

	Set pairs = $ClassMethod(..#AREA, "Parse", "", "zz")
	Do $$$AssertTrue(pairs.%IsA("%Library.DynamicArray"), "an empty value gives a dynamic array")
	Do $$$AssertEquals(pairs.%Size(), 0, "with no pair")
}

/// Every malformed form throws a status that names the place given and the pair: no colon, an empty or spaced resource, an empty permission,
/// a letter other than R, W and U (also in lower case), a second colon and an empty pair.
Method TestParseMalformed()
{
	Set list = $ListBuild("ZzNoColon", ":R", "ZzRes:", "ZzRes:X", "ZzRes:RX", "ZzRes:r", "ZzRes:R:W", "ZzRes:R,", ",ZzRes:R", "ZzA:R,,ZzB:U", "Zz Res:R", " ", "ZzRes:R, ZzB:U")
	Set position = 0
	While $ListNext(list, position, value) {
		Set text = ..Thrown(value, "OcuTalon.Zz.Tool zz_tool")
		Do $$$AssertNotEquals(text, "<no error>", "'"_value_"' throws")
		Do $$$AssertTrue(text [ "OcuTalon.Zz.Tool zz_tool", "and the error names the class and the tool for '"_value_"'")
	}
	Do $$$AssertEquals(..Thrown("ZzRes:R", "OcuTalon.Zz.Tool zz_tool"), "<no error>", "control: a good value does not throw")
}

/// The grants of the fixture toolset: the role alone, then the pair of each tool, once. alpha's own value, beta's fallback to the class's
/// value and gamma's empty value are told apart in TestToolParameter; here they are one set.
Method TestGrantsOf()
{
	Set role = $Parameter("OcuTalon.Install.Step.Users", "SERVICEROLE")
	Set grants = $ClassMethod(..#AREA, "GrantsOf", $ListBuild(..#TOOLSET))
	Do $$$AssertTrue(grants.%IsA("%Library.DynamicArray"), "a dynamic array")
	Do $$$AssertEquals(..Sorted(grants), role_"|ZzOcuTalonGrantProbe|R,"_role_"|ZzOcuTalonGrantProbe|U,"_role_"||", "alpha's U, beta's R and the role alone; gamma declares nothing")
	Set grants = $ClassMethod(..#AREA, "GrantsOf", $ListBuild(..#TOOLSET, ..#TOOLSET))
	Do $$$AssertEquals(grants.%Size(), 3, "a pair is listed once, whatever the number of tools that declare it")
	Set grants = $ClassMethod(..#AREA, "GrantsOf", "")
	Do $$$AssertEquals(..Sorted(grants), role_"||", "no toolset gives the role alone")
}

/// The suffix rule: the parameter of the tool's own name (upper case, with _ and - removed) wins even when it is empty, else the class's
/// parameter, else "". A class that does not exist, an empty class and an empty base give "".
Method TestToolParameter()
{
	Set buffer = "OcuTalon.Bridge.Adapter.StepBuffer"
	Do $$$AssertEquals($ClassMethod(buffer, "ToolParameter", ..#TOOLS, "alpha", "RESOURCES"), "ZzOcuTalonGrantProbe:U", "alpha: its own value")
	Do $$$AssertEquals($ClassMethod(buffer, "ToolParameter", ..#TOOLS, "beta", "RESOURCES"), "ZzOcuTalonGrantProbe:R", "beta: the value of the class")
	Do $$$AssertEquals($ClassMethod(buffer, "ToolParameter", ..#TOOLS, "gamma", "RESOURCES"), "", "gamma: its own empty value wins over the class's")
	Do $$$AssertEquals($ClassMethod(buffer, "ToolParameter", ..#TOOLS, "delta", "RESOURCES"), "ZzOcuTalonGrantProbe:R", "a tool the class does not name: the value of the class")
	Do $$$AssertEquals($ClassMethod(buffer, "ToolParameter", ..#TOOLS, "al_pha", "RESOURCES"), "ZzOcuTalonGrantProbe:U", "_ is removed from the name")
	Do $$$AssertEquals($ClassMethod(buffer, "ToolParameter", ..#TOOLS, "AL-pha", "RESOURCES"), "ZzOcuTalonGrantProbe:U", "and - too, in any case")
	Do $$$AssertEquals($ClassMethod(buffer, "ToolParameter", ..#TOOLS, "alpha", "STEPLABEL"), "Probing the grants", "another base: the class's label")
	Do $$$AssertEquals($ClassMethod(buffer, "ToolParameter", "OcuTalon.Tools.ReminderTools", "set_reminder", "RESOURCES"), "", "a class that declares none gives nothing")
	Do $$$AssertEquals($ClassMethod(buffer, "ToolParameter", "OcuTalon.Tools.ReminderTools", "set_reminder", "STEPLABEL"), "Setting a reminder", "a parameter of the tool's own name")
	Do $$$AssertEquals($ClassMethod(buffer, "ToolParameter", "OcuTalon.Test.Install.ZzNoSuchTools", "alpha", "RESOURCES"), "", "a class that does not exist")
	Do $$$AssertEquals($ClassMethod(buffer, "ToolParameter", "", "alpha", "RESOURCES"), "", "an empty class")
	Do $$$AssertEquals($ClassMethod(buffer, "ToolParameter", ..#TOOLS, "alpha", ""), "", "an empty base")
}

/// The step label of the reminder tools is what it was before the reader was shared, an empty label of a tool's own still falls back to the
/// class's, and the generic label still stands for a class with none.
Method TestLabelForIsUnchanged()
{
	Set buffer = "OcuTalon.Bridge.Adapter.StepBuffer"
	Set reminders = "OcuTalon.Tools.ReminderTools"
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", reminders, "set_reminder"), "Setting a reminder", "set_reminder")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", reminders, "list_reminders"), "Listing your reminders", "list_reminders")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", reminders, "cancel_reminder"), "Cancelling a reminder", "cancel_reminder")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", reminders, "no_such_tool"), $Parameter(buffer, "GENERICLABEL"), "a tool of the class without a label of its own: the generic label")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", ..#TOOLS, "alpha"), "Probing the grants", "a class label serves every tool of the class")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", ..#TOOLS, "gamma"), "Probing the grants", "an empty label of the tool's own falls back to the class's label")
	Do $$$AssertEquals($ClassMethod(buffer, "LabelFor", "OcuTalon.Test.Install.ZzNoSuchTools", "alpha"), $Parameter(buffer, "GENERICLABEL"), "a class that does not exist: the generic label")
}

/// The real declarations: Grants does not throw, every entry is for the service role, the role alone is declared, and the toolsets are the
/// built-in ones of OcuTalon.Tools, sorted, and no test toolset.
Method TestRealDeclarations()
{
	Set role = $Parameter("OcuTalon.Install.Step.Users", "SERVICEROLE")
	Do $$$AssertEquals(role, "OcuTalonServiceRole", "the service role")
	Set thrown = ""
	Try {
		Set grants = $ClassMethod(..#AREA, "Grants")
	} Catch exception {
		Set thrown = $SYSTEM.Status.GetErrorText(exception.AsStatus())
	}
	Do $$$AssertEquals(thrown, "", "Grants does not throw")
	If thrown '= "" Quit
	Set alone = 0
	Set iterator = grants.%GetIterator()
	While iterator.%GetNext(.key, .entry) {
		Do $$$AssertEquals(entry.role, role, "entry "_key_" is for the service role")
		If entry.resource = "" Set alone = alone + 1
	}
	Do $$$AssertEquals(alone, 1, "the role alone is declared once")

	Set toolsets = $ClassMethod(..#AREA, "Toolsets")
	Do $$$AssertTrue($ListFind(toolsets, "OcuTalon.Tools.Reminders") > 0, "the reminder toolset is one")
	Do $$$AssertTrue($ListFind(toolsets, "OcuTalon.Tools.Watch") > 0, "the watch toolset is one")
	Set previous = ""
	Set clean = 1
	Set position = 0
	While $ListNext(toolsets, position, toolset) {
		If previous ]] toolset Set clean = 0
		Set previous = toolset
		If $Extract(toolset, 1, 15) '= "OcuTalon.Tools." Set clean = 0
		If '$ClassMethod(toolset, "%Extends", "%AI.ToolSet") Set clean = 0
	}
	Do $$$AssertTrue(clean, "every toolset is a toolset of OcuTalon.Tools, and they are sorted")
	Do $$$AssertEquals($ListFind(toolsets, ..#TOOLSET), 0, "the test toolset is not one")
}

/// --- fixtures ---
/// The text of the error that Parse throws for the value, or "<no error>".
ClassMethod Thrown(value As %String, where As %String) As %String [ Private ]
{
	Set text = "<no error>"
	Try {
		Do $ClassMethod(..#AREA, "Parse", value, where)
	} Catch exception {
		Set text = $SYSTEM.Status.GetErrorText(exception.AsStatus())
	}
	Quit text
}

/// The entries of the grants as role|resource|permission, sorted, as a comma list.
ClassMethod Sorted(grants As %DynamicArray) As %String [ Private ]
{
	Set iterator = grants.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set sorted(entry.role_"|"_entry.resource_"|"_entry.permission) = ""
	}
	Set result = ""
	Set line = ""
	For {
		Set line = $Order(sorted(line))
		Quit:line=""
		Set result = result_$Select(result = "": "", 1: ",")_line
	}
	Quit result
}

}
