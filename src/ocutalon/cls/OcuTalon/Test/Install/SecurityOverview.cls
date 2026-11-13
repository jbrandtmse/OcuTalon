/// Tests of the security overview generator (Story 14.1; AD-10, AD-16, AD-22, AD-23, AD-24): the tool rows, the fix kind rows, the privilege
/// model against the security records of the instance, the splice of the generated sections and the fixed statement. Nothing here changes a
/// security record or a grant. TestToolsMatchRunners sends a ToolInventory request to every enabled agent runner, so it needs the production of
/// the CI throwaway running (it fails, never skips, when it does not), and it points the runners at the mock's key for the request and puts them back
/// after the test (OnAfterOneTest).
Class OcuTalon.Test.Install.SecurityOverview Extends %UnitTest.TestCase
{

/// The generator under test.
Parameter GENERATOR = "OcuTalon.Install.SecurityOverview";

/// The production whose runners are compared with the rows.
Parameter PRODUCTION = "OcuTalon.Production";

/// The statement of the tools section, word for word (AD-10).
Parameter STATEMENT = "No built-in tool runs operating-system commands, arbitrary ObjectScript or Python, or data-changing SQL, and AI Hub's shell, filesystem, SQL and web-search tools are never registered. The automated tool-inventory test `OcuTalon.Test.Agent.Runners` (`TestToolInventory`) checks this on every running runner.";

/// The runner items of the production, the first runners and their retry runners (Story 17.2), comma-separated.
ClassMethod AllRunners() As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).#RUNNERS_","_##class(OcuTalon.Test.Agent.RunnerFixture).#RETRYRUNNERS
}

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The tool that reaches a request through TurnToolsClass and is no tool of an agent's own tool manager.
Parameter TURNTOOL = "documents";

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark), for the turn that AssertTurnTool sends.
Property SessionMark As %Integer;

/// Puts the keys of the runners back when TestToolsMatchRunners pointed them at the mock, also after a failure.
Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Pointed {
		Set ..Pointed = 0
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys(..AllRunners())
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	}
	Quit $$$OK
}

/// The rows are the 20 built-in tools (the 19 of Story 19.4 and incident_summary of Story 23.6): the 12 of release 1 (Tools.Names RELEASE1), propose_persona (Tools.Names PROPOSEPERSONA, which the spine keeps out of RELEASE1), since Story 17.6, send_digest (Tools.Names DIGESTTOOLS), the four memory tools (Tools.Names MEMORYTOOLS, Story 19.3) and documents (Tools.Names DOCUMENTS, Story 19.4: AI Hub's knowledge base, a row that comes from the product's classification entry and not from a toolset), sorted by name, none of them a fixture or the bridge's example agent, and the
/// classification, the read-only flag and the trusted-output flag of each row are those that the gate gives (Gate.ClassificationOf); for a tool that
/// classifies by its arguments only the two flags are compared, since its classification is decided per call. The test seeds Decide's ToolClassification
/// row through the install step first, so that the gate reads the product's entry, and puts the row back exactly as it found it.
Method TestToolRows()
{
	Set saved = ""
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RememberDefault(.saved, "Decide", "ToolClassification")
	Try {
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).SeedClassification(..#PRODUCTION), "the install step has seeded the ToolClassification row that the gate reads")
		Do ..CheckToolRows()
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the rows are checked without an exception")
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(saved), "the ToolClassification row of Decide is put back exactly as it was found: its value and description, or no row")
}

/// The rows of ToolRows against the gate's classification, flags and the classes of OcuTalon.Tools.
Method CheckToolRows() [ Private ]
{
	Set rows = $ClassMethod(..#GENERATOR, "ToolRows")
	Set released = $ListFromString($Parameter("OcuTalon.Tools.Names", "RELEASE1")) _ $ListBuild($Parameter("OcuTalon.Tools.Names", "PROPOSEPERSONA"), $Parameter("OcuTalon.Tools.Names", "DIGESTTOOLS")) _ $ListFromString($Parameter("OcuTalon.Tools.Names", "MEMORYTOOLS")) _ $ListFromString($Parameter("OcuTalon.Tools.Names", "DOCUMENTS")) _ $ListBuild($Parameter("OcuTalon.Tools.Names", "INCIDENTSUMMARY"), $Parameter("OcuTalon.Tools.Names", "PROPOSEFIX"))
	Do $$$AssertEquals(rows.%Size(), $ListLength(released), "one row per tool of release 1, one for propose_persona, one for send_digest, one for each memory tool, one for documents, one for incident_summary and one for propose_fix")
	Set names = ""
	Set bad = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set names = names _ $ListBuild(row.name)
		If row.name '= ##class(OcuTalon.Tools.Names).#DOCUMENTS {
			If '..StartsWith(row.source, "OcuTalon.Tools.") Set bad = bad _ " " _ row.name _ ":" _ row.source
			If '..StartsWith(row.toolset, "OcuTalon.Tools.") Set bad = bad _ " " _ row.name _ ":" _ row.toolset
		}
		Set facts = ##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(row.source, row.name)
		If '(row.classification [ "per call: ") {
			Set shown = $Select(facts.classification = "": "unclassified", 1: facts.classification)
			Do $$$AssertEquals(row.classification, shown, row.name_": the classification is the gate's")
		}
		Do $$$AssertEquals(row.readOnly, +facts.readOnly, row.name_": the read-only flag is the gate's")
		Do $$$AssertEquals(row.trustedOutput, +facts.trustedOutput, row.name_": the trusted-output flag is the gate's")
	}
	Do $$$AssertEquals(bad, "", "every row is a class of OcuTalon.Tools, so no fixture and no bridge example appears")
	Do $$$AssertEquals($ListToString(names), $ListToString(..Sorted(released)), "the names are those of RELEASE1 and propose_persona, sorted")
}

/// DW-521: recent_activity is one of the 13 rows, with its source, toolset, agent, label, classification and flags, in the table as well.
Method TestRecentActivityRow()
{
	Set row = ..RowOf("recent_activity")
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "the model has a row for recent_activity")
		Quit
	}
	Do $$$AssertEquals(row.source, "OcuTalon.Tools.RecentActivity", "its source class")
	Do $$$AssertEquals(row.toolset, "OcuTalon.Tools.Watching", "its toolset")
	Do $$$AssertEquals(row.agents.%Size(), 1, "one agent holds it")
	Do $$$AssertEquals(row.agents.%Get(0), "OcuTalon.Agent.Chat", "the Chat agent")
	Do $$$AssertEquals(row.label, "Reading recent activity", "its step label")
	Do $$$AssertEquals(row.classification, "safe", "safe")
	Do $$$AssertEquals(row.readOnly, 1, "read-only")
	Do $$$AssertEquals(row.trustedOutput, 1, "with trusted output")
	Do $ClassMethod(..#GENERATOR, "Sections", .sections)
	Set expected = "| `recent_activity` | `OcuTalon.Tools.RecentActivity` | `OcuTalon.Tools.Watching` | `OcuTalon.Agent.Chat` | Reading recent activity | safe | yes | yes | none |"
	Do $$$AssertTrue(..HasLine(sections("tools"), expected), "the table of the tools section holds this row for recent_activity")
}

/// Story 19.4 (AC 6; the Contest Planner's PUBLIC TEXT ruling of 2026-11-07): documents is a row of the table, from the product's classification entry (Install.Step.Production ClassificationEntries)
/// of the class %AI.RAG.KnowledgeBase, with the flags of that entry (safe, read-only, not trusted output), held by the Chat agent, with the generic
/// step label and no resources, and the tools section ends with the fallback sentence RAGSTATEMENT, once, word for word.
Method TestDocumentsRow()
{
	Set row = ..RowOf("documents")
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "the model has a row for documents")
		Quit
	}
	Do $$$AssertEquals(row.source, "%AI.RAG.KnowledgeBase", "its source is AI Hub's knowledge base")
	Do $$$AssertEquals(row.toolset, "OcuTalon.Docs.Store", "its toolset is the class that attaches it")
	Do $$$AssertEquals(row.agents.%Size()_"|"_row.agents.%Get(0), "1|OcuTalon.Agent.Chat", "the Chat agent holds it")
	Do $$$AssertEquals(row.label, "Running a tool", "its step label is the generic one")
	Do $$$AssertEquals(row.classification_"|"_row.readOnly_"|"_row.trustedOutput_"|"_row.resources.%Size(), "safe|1|0|0", "safe, read-only, not trusted output, no resources")
	Do $ClassMethod(..#GENERATOR, "Sections", .sections)
	Set expected = "| `documents` | `%AI.RAG.KnowledgeBase` | `OcuTalon.Docs.Store` | `OcuTalon.Agent.Chat` | Running a tool | safe | yes | no | none |"
	Do $$$AssertTrue(..HasLine(sections("tools"), expected), "the table of the tools section holds this row for documents")
	Set statement = "One tool has no class of its own: `documents`, the search over your added documents that AI Hub's knowledge base gives the Chat agent. AI Hub sends no source class with its calls, so the gate classifies this one tool, and no other, by the bridge's classification setting: safe and read-only, but its output is never trusted, so a turn that searches your documents is treated as holding untrusted content. The gate also limits each search to 5 passages. Any other call that arrives without a source class stays unclassified and counts as risky."
	Do $$$AssertEquals($Parameter(..#GENERATOR, "RAGSTATEMENT"), statement, "the fallback sentence is the ruled text, word for word")
	Do $$$AssertEquals($Length(sections("tools"), statement) - 1, 1, "and the tools section prints it once")
	Do $$$AssertTrue(sections("tools") [ ($Char(10)_$Char(10)_statement_$Char(10)), "on a line of its own after the table")
}

/// Story 40.5 (AC 8): propose_persona is one of the 13 rows, held by the Chat agent through its toolset, with its source, label, classification and flags, in the table as well.
Method TestProposePersonaRow()
{
	Set row = ..RowOf("propose_persona")
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "the model has a row for propose_persona")
		Quit
	}
	Do $$$AssertEquals(row.source, "OcuTalon.Tools.PersonaTools", "its source class")
	Do $$$AssertEquals(row.toolset, "OcuTalon.Tools.Persona", "its toolset")
	Do $$$AssertEquals(row.agents.%Size(), 1, "one agent holds it")
	Do $$$AssertEquals(row.agents.%Get(0), "OcuTalon.Agent.Chat", "the Chat agent")
	Do $$$AssertEquals(row.label, "Suggesting a persona", "its step label")
	Do $$$AssertEquals(row.classification, "safe", "safe")
	Do $$$AssertEquals(row.readOnly, 0, "not read-only")
	Do $$$AssertEquals(row.trustedOutput, 1, "with trusted output")
	Do $ClassMethod(..#GENERATOR, "Sections", .sections)
	Set expected = "| `propose_persona` | `OcuTalon.Tools.PersonaTools` | `OcuTalon.Tools.Persona` | `OcuTalon.Agent.Chat` | Suggesting a persona | safe | no | yes | none |"
	Do $$$AssertTrue(..HasLine(sections("tools"), expected), "the table of the tools section holds this row for propose_persona")
}

/// The toolsets that the generator reads are the toolsets of the Tools area (Install.Step.Tools.Toolsets), which grants the service role, and the
/// catalog holds more than they (the test fixtures), so the scope is a filter and not the whole catalog.
Method TestToolsetScope()
{
	Set catalog = $ClassMethod("%AI.Catalog", "ToolSets", "OcuTalon.%")
	Set scoped = ""
	Set others = 0
	Set iterator = catalog.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If ..StartsWith(entry.name, "OcuTalon.Tools.") {
			Set scoped = scoped _ $ListBuild(entry.name)
		} Else {
			Set others = others + 1
		}
	}
	Set toolsets = ##class(OcuTalon.Install.Step.Tools).Toolsets()
	Do $$$AssertEquals($ListToString(..Sorted(scoped)), $ListToString(..Sorted(toolsets)), "the catalog toolsets of OcuTalon.Tools. are those of Install.Step.Tools.Toolsets")
	Do $$$AssertTrue(others > 0, "control: the catalog holds toolsets outside OcuTalon.Tools. (fixtures), which the rows leave out")
	Set used = ""
	Set rows = $ClassMethod(..#GENERATOR, "ToolRows")
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		If '$ListFind(toolsets, row.toolset) && (row.name '= ##class(OcuTalon.Tools.Names).#DOCUMENTS) Set used = used _ " " _ row.name
	}
	Do $$$AssertEquals(used, "", "every row but documents (AI Hub's knowledge base, which has no toolset) is a tool of one of those toolsets")
	Set agents = $ClassMethod("%AI.Catalog", "Agents", "OcuTalon.%")
	Set outside = 0
	Set iterator = agents.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If '..StartsWith(entry.name, "OcuTalon.Agent.") Set outside = outside + 1
	}
	Do $$$AssertTrue(outside > 0, "control: the catalog holds agents outside OcuTalon.Agent. (the bridge example and fixtures), which no row names")
	Set held = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set agentIterator = row.agents.%GetIterator()
		While agentIterator.%GetNext(, .agent) {
			If '..StartsWith(agent, "OcuTalon.Agent.") Set held = held _ " " _ agent
		}
	}
	Do $$$AssertEquals(held, "", "every agent of a row is a class of OcuTalon.Agent.")
}

/// A tool that classifies by its arguments shows the text of its rule: CLASSIFYRULE<NAME> for a tool with its own hook, else CLASSIFYRULE. A hook
/// with no rule text fails generation with a status that names the tool and the class.
Method TestClassifyHookShowsItsRule()
{
	Set rule = "OcuTalon.Test.Install.ZzOverviewRule"
	Do $$$AssertEquals($ClassMethod(..#GENERATOR, "Classification", rule, "own"), "per call: safe unless the text holds a delete", "a tool with its own hook shows the text of its own rule")
	Do $$$AssertEquals($ClassMethod(..#GENERATOR, "Classification", rule, "plain"), "per call: risky when the request names a production | else safe", "a tool with the class-wide hook shows CLASSIFYRULE")
	Set text = ""
	Try {
		Set shown = $ClassMethod(..#GENERATOR, "Classification", "OcuTalon.Test.Bridge.ZzGateWide", "wide_plain")
		Set text = "<no error>"
	} Catch exception {
		Set text = $SYSTEM.Status.GetErrorText(exception.AsStatus())
	}
	Do $$$AssertNotEquals(text, "<no error>", "a hook with no CLASSIFYRULE text fails generation")
	Do $$$AssertTrue(text [ "wide_plain", "and the status names the tool")
	Do $$$AssertTrue(text [ "OcuTalon.Test.Bridge.ZzGateWide", "and its class")
	Do $$$AssertEquals(..Cell("a | b"), "a \| b", "a vertical bar in a rule is escaped in the table cell")
}

/// The Resources column of a tool row (no shipped tool declares RESOURCES, so the fixture does): the pairs of the tool's own value, else of the class,
/// as resource:permission code spans in the table line; a tool whose own value is empty shows none although the class declares one; a value that is
/// not resource:permission fails generation with a status that names the tool and the class. The read-only and trusted-output flags of a tool that
/// classifies by its arguments are those that the gate gives.
Method TestToolResourcesCell()
{
	Set rule = "OcuTalon.Test.Install.ZzOverviewRule"
	Set agents = ["OcuTalon.Agent.Probe"]
	Set own = $ClassMethod(..#GENERATOR, "ToolRow", rule, "own", "OcuTalon.Tools.Probe", agents)
	Do $$$AssertEquals(own.resources.%Size(), 2, "own: two pairs")
	Set facts = ##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(rule, "own")
	Do $$$AssertEquals(own.readOnly, +facts.readOnly, "own: the read-only flag is the gate's")
	Do $$$AssertEquals(own.trustedOutput, +facts.trustedOutput, "own: the trusted-output flag is the gate's")
	Do $$$AssertEquals($ClassMethod(..#GENERATOR, "Pairs", own.resources), "`ZzOverviewProbe:R`, `%Ens_Portal:U`", "own: its own value outranks the class's")
	Set plain = $ClassMethod(..#GENERATOR, "ToolRow", rule, "plain", "OcuTalon.Tools.Probe", agents)
	Do $$$AssertEquals($ClassMethod(..#GENERATOR, "Pairs", plain.resources), "`ZzOverviewProbe:W`", "plain: the value of the class")
	Set quiet = $ClassMethod(..#GENERATOR, "ToolRow", rule, "quiet", "OcuTalon.Tools.Probe", agents)
	Do $$$AssertEquals($ClassMethod(..#GENERATOR, "Pairs", quiet.resources), "none", "quiet: an empty own value shows none")
	Set text = $ClassMethod(..#GENERATOR, "ToolsText", {"tools": [(own), (quiet)]})
	Do $$$AssertTrue(..HasLine(text, "| `own` | `"_rule_"` | `OcuTalon.Tools.Probe` | `OcuTalon.Agent.Probe` | Probing the overview | per call: safe unless the text holds a delete | no | no | `ZzOverviewProbe:R`, `%Ens_Portal:U` |"), "the table line of own ends with its resources")
	Do $$$AssertTrue(..HasLine(text, "| `quiet` | `"_rule_"` | `OcuTalon.Tools.Probe` | `OcuTalon.Agent.Probe` | Probing the overview | per call: risky when the request names a production \| else safe | no | no | none |"), "and the table line of quiet reads none")
	Set text = ""
	Try {
		Set bad = $ClassMethod(..#GENERATOR, "ToolRow", rule, "bad", "OcuTalon.Tools.Probe", agents)
		Set text = "<no error>"
	} Catch exception {
		Set text = $SYSTEM.Status.GetErrorText(exception.AsStatus())
	}
	Do $$$AssertNotEquals(text, "<no error>", "a RESOURCES value that is not resource:permission fails generation")
	Do $$$AssertTrue(text [ "bad", "and the status names the tool")
	Do $$$AssertTrue(text [ rule, "and its class")
}

/// The fix kinds are every non-abstract class of the package OcuTalon.Fix.Kind, each row has the kind's NAME and RESOURCES, and the table shows
/// repair_resend with %Ens_MessageResend:U and partner_warning (Story 23.5) as risky with no resources ("none").
Method TestFixKindRows()
{
	Set sc = $$GetAllDerivedClasses^%occLibrary("OcuTalon.Fix.Kind", .derived)
	Do $$$AssertStatusOK(sc, "the kinds can be listed")
	Set expected = ""
	Set name = ""
	For {
		Set name = $Order(derived(name))
		Quit:name=""
		If '..StartsWith(name, "OcuTalon.Fix.Kind.") Continue
		If ##class(%Dictionary.CompiledClass).%ExistsId(name) && '$$$comClassKeyGet(name, $$$cCLASSabstract) Set expected = expected _ $ListBuild(name)
	}
	Set kinds = ##class(OcuTalon.Fix.Kind).Classes()
	Do $$$AssertEquals($ListToString(..Sorted(kinds)), $ListToString(..Sorted(expected)), "Fix.Kind.Classes is every non-abstract class of the package OcuTalon.Fix.Kind")
	Set rows = $ClassMethod(..#GENERATOR, "FixKindRows")
	Do $$$AssertEquals(rows.%Size(), $ListLength(kinds), "one row per kind")
	Set names = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set names = names _ $ListBuild(row.class)
		Do $$$AssertEquals(row.name, $Parameter(row.class, "NAME"), row.class_": the NAME")
		Set resources = ""
		Set pairs = row.resources.%GetIterator()
		While pairs.%GetNext(, .pair) {
			Set resources = resources _ $Select(resources = "": "", 1: ",") _ pair.resource_":"_pair.permission
		}
		Do $$$AssertEquals(resources, $Parameter(row.class, "RESOURCES"), row.class_": the RESOURCES")
	}
	Do $$$AssertEquals($ListToString(names), $ListToString(..Sorted(names)), "the rows are sorted by class")
	Do $ClassMethod(..#GENERATOR, "Sections", .sections)
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Do $$$AssertEquals(row.classification, "risky", row.class_": every fix kind is risky")
	}
	Set expectedRows = $ListBuild("| `OcuTalon.Fix.Kind.PartnerWarning` | `partner_warning` | risky | none |", "| `OcuTalon.Fix.Kind.RepairResend` | `repair_resend` | risky | `%Ens_MessageResend:U` |", "| `OcuTalon.Fix.Kind.Reroute` | `reroute` | risky | `%Ens_MessageResend:U` |", "| `OcuTalon.Fix.Kind.ResumeItem` | `resume_item` | risky | `%Ens_ConfigItemRun:U` |", "| `OcuTalon.Fix.Kind.SuspendItem` | `suspend_item` | risky | `%Ens_ConfigItemRun:U` |")
	Set position = 0
	While $ListNext(expectedRows, position, expectedRow) {
		Do $$$AssertTrue(..HasLine(sections("fix-kinds"), expectedRow), "the table holds "_expectedRow)
	}
	Do $$$AssertTrue(..HasLine(sections("fix-kinds"), "| Class | Name | Classification | Resources |"), "and has a Classification column")
	Set sentence = "On the online demo, OcuTalonServiceRole does not hold %Ens_ConfigItemRun:U, so OcuTalon can't suspend or resume items there."
	Do $$$AssertEquals($Parameter(..#GENERATOR, "ONLINESTATEMENT"), sentence, "the online demo sentence is the ruled one, word for word")
	Do $$$AssertTrue(..HasLine(sections("fix-kinds"), sentence), "and the fix kinds section holds it as a line of its own")
}

/// DW-213: the grants that only demo mode adds are listed apart: the service role Read on the OCUORDERS data database, and the trace role Read
/// on its code and data databases. The trace role's SQL SELECT on Ens.MessageHeader is listed in OCUTALON, and in OCUORDERS with demo mode on. The
/// service user holds exactly the service role with login disabled, and /ocutalon and /ocutalon/api, alone of the Web step's applications but for the
/// webhook application /ocutalon/hook (off the online demo, with Web.HOOKROLE and no sign-in), add roles to their requests: the roles of Web.APPLICATIONROLES.
Method TestDemoOnlyGrantsListed()
{
	Set model = $ClassMethod(..#GENERATOR, "Model")
	Set listed = ""
	Set iterator = model.demoOnly.%GetIterator()
	While iterator.%GetNext(, .grant) {
		Set listed = listed _ $Select(listed = "": "", 1: ";") _ grant.role_"|"_grant.resource_"|"_grant.permission
	}
	Do $$$AssertEquals(listed, "OcuTalonServiceRole|%DB_OCUORDERS_DATA|R;OcuTalonTraceViewer|%DB_OCUORDERS_CODE|R;OcuTalonTraceViewer|%DB_OCUORDERS_DATA|R", "the demo-only grants")
	Set sql = ""
	Set iterator = model.sql.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set sql = sql _ $Select(sql = "": "", 1: ";") _ row.role_"|"_row.privilege_"|"_row.object_"|"_row.namespace_"|"_row.when
	}
	Do $$$AssertEquals(sql, "OcuTalonTraceViewer|SELECT|Ens.MessageHeader|OCUTALON|always;OcuTalonTraceViewer|SELECT|Ens.MessageHeader|OCUORDERS|demo mode on", "the SQL privileges")
	Do $$$AssertEquals(model.serviceUser.user, "OcuTalonService", "the service user")
	Do $$$AssertEquals(model.serviceUser.roles.%Size(), 1, "holds one role")
	Do $$$AssertEquals(model.serviceUser.roles.%Get(0), "OcuTalonServiceRole", "the service role")
	Do $$$AssertEquals(model.serviceUser.login, "disabled", "with login disabled")
	Do ..ApplicationsFor(0)
	Do ..ApplicationsFor(1)
	Do $ClassMethod(..#GENERATOR, "Sections", .sections)
	Set text = sections("privileges")
	Do $$$AssertTrue(..HasLine(text, "| `OcuTalonServiceRole` | `%DB_OCUORDERS_DATA` | R |"), "the privilege section lists the service role's demo-only grant")
	Do $$$AssertTrue(..HasLine(text, "| `OcuTalonTraceViewer` | `%DB_OCUORDERS_CODE` | R |"), "and the trace role's OCUORDERS code database")
	Do $$$AssertTrue(..HasLine(text, "| `OcuTalonTraceViewer` | `%DB_OCUORDERS_DATA` | R |"), "and its OCUORDERS data database")
	Do $$$AssertTrue(..HasLine(text, "| `OcuTalonTraceViewer` | SELECT | `Ens.MessageHeader` | OCUORDERS | demo mode on |"), "and its SQL SELECT in OCUORDERS with demo mode on")
	Do $$$AssertTrue(..HasLine(text, "| `OcuTalonService` | `OcuTalonServiceRole` | disabled |"), "and the service user with login disabled")
	Set base = ""
	Set iterator = model.roles.%GetIterator()
	While iterator.%GetNext(, .role) {
		Set grants = role.grants.%GetIterator()
		While grants.%GetNext(, .grant) {
			If ..StartsWith(grant.resource, "%DB_OCUORDERS_") Set base = base _ " " _ role.role_":"_grant.resource
		}
	}
	Do $$$AssertEquals(base, "", "control: the base grants hold no OCUORDERS resource, so the list of demo-only grants is not a repeat")
}

/// The Declared by column: each grant of a role names the installer areas, by their short class names, whose Grants() declare that role and
/// resource, and a role with no resource names the areas that declare the role; the table shows both kinds of row.
Method TestRoleRowsDeclaredBy()
{
	Set sc = ##class(OcuTalon.Install.Registry).Declared("Grants", .entries)
	Do $$$AssertStatusOK(sc, "the declared grants can be read")
	Set n = ""
	For {
		Set n = $Order(entries(n))
		Quit:n=""
		Set grant = entries(n)
		Set areas(grant.role, $Select(grant.resource = "": " ", 1: grant.resource), $Piece(entries(n, "area"), ".", *)) = ""
	}
	Set bad = ""
	Set rows = $ClassMethod(..#GENERATOR, "RoleRows")
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .role) {
		If role.grants.%Size() = 0 {
			If ..List(role.declaredBy, ",") '= ..Areas(.areas, role.role, " ") Set bad = bad _ "; "_role.role_" shows "_..List(role.declaredBy, ",")
			Continue
		}
		Set grants = role.grants.%GetIterator()
		While grants.%GetNext(, .grant) {
			If ..List(grant.declaredBy, ",") '= ..Areas(.areas, role.role, grant.resource) Set bad = bad _ "; "_role.role_" "_grant.resource_" shows "_..List(grant.declaredBy, ",")
		}
	}
	Do $$$AssertEquals(bad, "", "each row names the areas whose Grants() declare it")
	Do $ClassMethod(..#GENERATOR, "Sections", .sections)
	Do $$$AssertTrue(..HasLine(sections("privileges"), "| `OcuTalonServiceRole` | `%Ens_MessageResend` | U | `Fix` |"), "the table names Fix for the service role's resend grant")
	Do $$$AssertTrue(..HasLine(sections("privileges"), "| `OcuTalonAdmin` | none | - | `Users` |"), "and Users for the admin role, which holds no resource")
}

/// Splice replaces the lines between the markers of each key and no other byte: with LF and CRLF line endings, with and without a final newline,
/// and it gives the same text when run again. A marker that is missing, repeated, before its begin marker or out of order gives an error status that
/// names it, with nothing in out. A line that merely holds a marker is not one.
Method TestSplice()
{
	Set lf = $Char(10)
	Set cr = $Char(13)
	Set sections("tools") = "NEW T1"_lf_"NEW T2"_lf
	Set sections("fix-kinds") = "NEW F"_lf
	Set sections("privileges") = "NEW P1"_lf_"NEW P2"_lf_"NEW P3"_lf
	For eol = lf, cr_lf {
		For final = 1, 0 {
			Set label = $Select(eol = lf: "LF", 1: "CRLF")_$Select(final: " with", 1: " without")_" a final newline"
			Set old = ..Doc(eol, final, 0)
			Set new = ..Doc(eol, final, 1)
			Set sc = $ClassMethod(..#GENERATOR, "Splice", old, .out, .sections)
			Do $$$AssertStatusOK(sc, label_": the splice works")
			Do $$$AssertEquals(out, new, label_": only the regions are replaced")
			Do $$$AssertEquals($Extract(out, *), $Select(final: lf, 1: "d"), label_": the end of the text is as it was")
			Do $ClassMethod(..#GENERATOR, "Splice", new, .again, .sections)
			Do $$$AssertEquals(again, new, label_": a second splice changes nothing")
		}
	}
	Set good = ..Doc(lf, 1, 0)
	Set begin = $ClassMethod(..#GENERATOR, "BeginMarker", "fix-kinds")
	Set end = $ClassMethod(..#GENERATOR, "EndMarker", "fix-kinds")
	Set beginTools = $ClassMethod(..#GENERATOR, "BeginMarker", "tools")
	Set beginPrivileges = $ClassMethod(..#GENERATOR, "BeginMarker", "privileges")
	Set endPrivileges = $ClassMethod(..#GENERATOR, "EndMarker", "privileges")
	Do ..AssertRefused($Replace(good, begin, "not a marker"), begin, "a missing begin marker", .sections)
	Do ..AssertRefused($Replace(good, end, "not a marker"), end, "a missing end marker", .sections)
	Do ..AssertRefused(good_beginTools_lf, beginTools, "a repeated begin marker", .sections)
	Do ..AssertRefused(good_endPrivileges_lf, endPrivileges, "a repeated end marker", .sections)
	Do ..AssertRefused($Replace(good, begin, "x "_begin), begin, "a marker with other text on its line", .sections)
	Set swapped = $Replace($Replace($Replace(good, beginPrivileges, "@@"), endPrivileges, beginPrivileges), "@@", endPrivileges)
	Do ..AssertRefused(swapped, endPrivileges, "an end marker before its begin marker", .sections)
	Set moved = beginPrivileges_lf_endPrivileges_lf_beginTools_lf_$ClassMethod(..#GENERATOR, "EndMarker", "tools")_lf_begin_lf_end_lf
	Do ..AssertRefused(moved, beginPrivileges, "a section out of order", .sections)
	Do ..AssertRefused("no markers at all"_lf, beginTools, "a text with no marker", .sections)
}

/// Regenerate reads a file, writes the spliced text to another file and writes nothing when the splice fails: the output of a good file is the bytes
/// of Splice of the same text (hand-written lines kept, the three regions generated), and a file with a missing marker, or no file at all, gives an
/// error status and no output file. The files are made in the temporary folder and removed by the test.
Method TestRegenerate()
{
	Set lf = $Char(10)
	Set good = ##class(%File).TempFilename("md")
	Set goodOut = good_".out"
	Set bad = good_".bad"
	Set badOut = bad_".out"
	Set missing = good_".none"
	Try {
		Set text = ..Doc(lf, 1, 0)
		Do ..WriteFile(good, text)
		Set sc = $ClassMethod(..#GENERATOR, "Regenerate", good, goodOut)
		Do $$$AssertStatusOK(sc, "a file with its three marker pairs is regenerated")
		Set sc = $ClassMethod(..#GENERATOR, "Splice", text, .expected)
		Do $$$AssertStatusOK(sc, "control: the same text can be spliced")
		Do $$$AssertTrue(##class(%File).Exists(goodOut), "the output file exists")
		Do $$$AssertEquals(..ReadFile(goodOut), expected, "its bytes are those of Splice of the same text")
		Do $$$AssertTrue(expected '= text, "control: the regions of the file were replaced")
		Do $$$AssertEquals($Piece(..ReadFile(goodOut), lf, 1, 2), "# Title"_lf_"Hand-written text.  ", "and the hand-written lines are kept")
		Do ..WriteFile(bad, $Replace(text, $ClassMethod(..#GENERATOR, "EndMarker", "fix-kinds"), "not a marker"))
		Set sc = $ClassMethod(..#GENERATOR, "Regenerate", bad, badOut)
		Do $$$AssertStatusNotOK(sc, "a file with a missing marker is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ $ClassMethod(..#GENERATOR, "EndMarker", "fix-kinds"), "and the status names the marker")
		Do $$$AssertEquals(##class(%File).Exists(badOut), 0, "and no output file is written")
		Set sc = $ClassMethod(..#GENERATOR, "Regenerate", missing, badOut)
		Do $$$AssertStatusNotOK(sc, "a file that does not exist is refused")
		Do $$$AssertEquals(##class(%File).Exists(badOut), 0, "and no output file is written for it either")
	} Catch exception {
		Do $$$AssertTrue(0, "TestRegenerate ended with an exception: "_exception.DisplayString())
	}
	For file = good, goodOut, bad, badOut {
		Do ##class(%File).Delete(file)
	}
}

/// The tools section carries the statement word for word, as a line of its own, and the test that it names exists.
Method TestInventoryStatement()
{
	Do $$$AssertEquals($Parameter(..#GENERATOR, "STATEMENT"), ..#STATEMENT, "the generator's statement is the fixed statement, word for word")
	Do $ClassMethod(..#GENERATOR, "Sections", .sections)
	Do $$$AssertTrue(..HasLine(sections("tools"), ..#STATEMENT), "the tools section holds it as a line")
	Do $$$AssertTrue(##class(%Dictionary.CompiledMethod).%ExistsId("OcuTalon.Test.Agent.Runners||TestToolInventory"), "OcuTalon.Test.Agent.Runners has the method TestToolInventory that it names")
	Set sc = ##class(OcuTalon.Install.Step.Production).Runners(..#PRODUCTION, .runners)
	Do $$$AssertStatusOK(sc, "the runners of the production can be listed")
	Set enabled = ""
	For i = 1:1:$Get(runners) {
		If $List(runners(i), 3) Set enabled = enabled _ $ListBuild($List(runners(i), 1))
	}
	Set checked = $ListFromString($Parameter("OcuTalon.Test.Agent.Runners", "INVENTORYRUNNERS"))
	Do $$$AssertEquals($ListToString(..Sorted(checked)), $ListToString(..Sorted(enabled)), "the runners that TestToolInventory checks are every enabled agent runner of the production, the retry runners included, so the statement's every running runner holds")
}

/// The sections are made of ASCII alone, and the check that says so finds a character outside ASCII.
Method TestAscii()
{
	Do $ClassMethod(..#GENERATOR, "Sections", .sections)
	Set key = ""
	For {
		Set key = $Order(sections(key))
		Quit:key=""
		Do $$$AssertEquals($ClassMethod(..#GENERATOR, "NonAscii", sections(key)), "", key_": ASCII only")
		Do $$$AssertTrue($Length(sections(key)) > 100, key_": not empty")
	}
	Do $$$AssertEquals($ClassMethod(..#GENERATOR, "NonAscii", "caf"_$Char(233)), "U+00E9", "control: a character outside ASCII is found")
	Do $$$AssertEquals($ClassMethod(..#GENERATOR, "NonAscii", "plain"_$Char(10, 9)), "", "control: the line feed and the tab are allowed")
}

/// Every enabled agent runner of the production holds exactly the tools that the rows list for its agent: a ToolInventory request to each runner
/// is compared with the rows whose agents hold the runner's AgentClass. The test names the runner and the tool of a difference. A production that
/// does not run fails the test. The one tool that reaches a request through TurnToolsClass (Story 19.5), documents, is no tool of the agent's own tool manager,
/// which the inventory lists: its row is checked against what a local turn of the agent offers (the first model request of a Chat turn through the runner).
Method TestToolsMatchRunners()
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set reason = $ClassMethod(fixture, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set ..Pointed = 1
	Set ..SessionMark = $ClassMethod(fixture, "SessionMark")
	Set sc = $ClassMethod(fixture, "PointKeys", ..AllRunners())
	Do $$$AssertStatusOK(sc, "the entries of the runners, the retry runners included, are pointed at the CI mock key variable")
	If $$$ISERR(sc) Quit
	Do $$$AssertTrue($ClassMethod(fixture, "WaitRecords"), "and every runner has recorded its key state")
	Set sc = ##class(OcuTalon.Install.Step.Production).Runners(..#PRODUCTION, .runners)
	Do $$$AssertStatusOK(sc, "the runners of the production can be listed")
	If $$$ISERR(sc) Quit
	Set rows = $ClassMethod(..#GENERATOR, "ToolRows")
	Set checked = 0
	For i = 1:1:runners {
		Set item = $List(runners(i), 1)
		Set agent = $List(runners(i), 2)
		If '$List(runners(i), 3) Continue
		Set checked = checked + 1
		Set listed = ""
		Set iterator = rows.%GetIterator()
		While iterator.%GetNext(, .row) {
			Set holders = row.agents.%GetIterator()
			While holders.%GetNext(, .holder) {
				If (holder = agent) && (row.name '= ..#TURNTOOL) Set listed = listed _ $ListBuild(row.name)
			}
		}
		Set sc = $ClassMethod(fixture, "Send", item, ##class(OcuTalon.Bridge.Msg.ToolInventory).%New(), .response)
		Do $$$AssertStatusOK(sc, item_" answers the ToolInventory request")
		If '$IsObject(response) || 'response.%IsA("Ens.StringResponse") {
			Do $$$AssertTrue(0, item_" answers with an Ens.StringResponse")
			Continue
		}
		Set held = ""
		Set inventory = {}.%FromJSON(response.StringValue)
		Set iterator = inventory.tools.%GetIterator()
		While iterator.%GetNext(, .tool) {
			Set held = held _ $ListBuild(tool.name)
		}
		Set problems = ""
		Set position = 0
		While $ListNext(held, position, name) {
			If '$ListFind(listed, name) Set problems = problems _ "; "_item_" holds "_name_", which the overview does not list for "_agent
		}
		Set position = 0
		While $ListNext(listed, position, name) {
			If '$ListFind(held, name) Set problems = problems _ "; "_item_" does not hold "_name_", which the overview lists for "_agent
		}
		Do $$$AssertEquals(problems, "", item_" holds the tools that the overview lists for "_agent_": "_$ListToString(..Sorted(held)))
	}
	Do $$$AssertTrue(checked > 0, "at least one enabled agent runner was compared: "_checked)
	Do ..AssertTurnTool(.runners, rows)
}

/// The tool documents reaches a request through TurnToolsClass, so the overview's row for it is checked against a local turn: for each enabled runner whose agent
/// the row lists, a turn (the CI mock's recall-ask) offers the tool in its first model request, and at least one runner is checked.
Method AssertTurnTool(ByRef runners, rows As %DynamicArray) [ Private ]
{
	Set holders = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		If row.name '= ..#TURNTOOL Continue
		Set agents = row.agents.%GetIterator()
		While agents.%GetNext(, .agent) {
			Set holders = holders _ $ListBuild(agent)
		}
	}
	Do $$$AssertTrue($ListLength(holders) > 0, "the overview has a row for " _ ..#TURNTOOL)
	Set checked = 0
	For i = 1:1:runners {
		Set item = $List(runners(i), 1)
		If ('$List(runners(i), 3)) || (item [ "Retry") Continue
		Set agent = $List(runners(i), 2)
		If ($ListFind(holders, agent) = 0) Continue
		Set checked = checked + 1
		Set sc = $ClassMethod("OcuTalon.Test.Agent.RunnerFixture", "Ask", item, "turn", "user", "[[mock:recall-ask]] Where is the build server?", .reply, .requests, .ref)
		Do $$$AssertStatusOK(sc, item _ " answers a local turn")
		Set offered = $Select($IsObject(requests) && (requests.%Size() > 0): $ClassMethod("OcuTalon.Test.Agent.RunnerFixture", "ToolNames", requests.%Get(0)), 1: "")
		Do $$$AssertTrue($ListFind($ListFromString(offered), ..#TURNTOOL) > 0, item _ " offers " _ ..#TURNTOOL _ " to a local turn, as the overview's row for " _ agent _ " says: " _ offered)
	}
	Do $$$AssertTrue(checked > 0, "at least one enabled runner of an agent that holds " _ ..#TURNTOOL _ " was asked: " _ checked)
}

/// The security records of the instance are the model: each listed role holds exactly its resources and permissions (the base grants, and with
/// demo mode on the demo-only ones); the service user holds exactly the service role, with login disabled; the trace role's SQL privileges are
/// the listed SELECT rows; the listed roles are granted no other role and the service user has no escalation role; and each application of the
/// Web step adds exactly the roles listed for it, none when it is not listed. A difference names the role, the resource and the permission,
/// and whether it is extra or missing.
Method TestPrivilegesMatchSecurityRecords()
{
	Set model = $ClassMethod(..#GENERATOR, "Model")
	Set demo = ##class(OcuTalon.Install.Step.Demo).Mode()
	Set iterator = model.roles.%GetIterator()
	While iterator.%GetNext(, .role) {
		Kill expected
		Set grants = role.grants.%GetIterator()
		While grants.%GetNext(, .grant) {
			Set expected(grant.resource) = ..Letters($Get(expected(grant.resource))_grant.permission)
		}
		If demo {
			Set extras = model.demoOnly.%GetIterator()
			While extras.%GetNext(, .extra) {
				If extra.role = role.role Set expected(extra.resource) = ..Letters($Get(expected(extra.resource))_extra.permission)
			}
		}
		Set actual = ..ReadRole(role.role, .granted)
		If actual = "<none>" {
			Do $$$AssertTrue(0, "the role "_role.role_" exists")
			Continue
		}
		Do $$$AssertEquals(..Differences(role.role, .expected, actual), "", role.role_" holds exactly the listed resources (demo mode "_$Select(demo: "on", 1: "off")_")")
		Do $$$AssertEquals(granted, "", role.role_" is granted no other role, whose privileges the overview would not list")
	}
	Set user = model.serviceUser.user
	Do ..ReadUser(user, .exists, .enabled, .roles, .escalation)
	Do $$$AssertTrue(exists, "the service user "_user_" exists")
	Do $$$AssertEquals(roles, ..List(model.serviceUser.roles, ","), user_" holds exactly the service role")
	Do $$$AssertEquals(escalation, "", user_" has no escalation role")
	Do $$$AssertEquals(enabled, 0, user_" has login disabled")
	Set trace = ##class(OcuTalon.Install.Step.Web).#TRACEROLE
	Set sql = ""
	Set rows = model.sql.%GetIterator()
	While rows.%GetNext(, .row) {
		If row.role '= trace Continue
		If (row.when = "demo mode on") && 'demo Continue
		Set sql = sql _ $ListBuild(row.namespace_"|1,"_row.object_"|s")
	}
	Do $$$AssertEquals(..SqlPrivileges(trace), $ListToString(..Sorted(sql), ";"), "the trace role's SQL privileges are the listed SELECT rows")
	Set iterator = model.applications.%GetIterator()
	While iterator.%GetNext(, .app) {
		Set listed(app.name) = ":"_..List(app.roles, ":")
	}
	Set sc = ##class(OcuTalon.Install.Step.Web).Definitions(.apps)
	Do $$$AssertStatusOK(sc, "the applications of the Web step can be listed")
	Set name = ""
	For {
		Set name = $Order(apps(name))
		Quit:name=""
		Do $$$AssertEquals(..MatchRoles(name), $Get(listed(name)), name_$Select($Data(listed(name)): " adds the listed roles to its requests", 1: " adds no role, as it is not listed"))
	}
}

// --- helpers ---

/// The model's applications with the online-demo flag set to the given value: /ocutalon and /ocutalon/api add the roles of Web.APPLICATIONROLES and sign in
/// with a password; /ocutalon/hook adds only the webhook role and signs in with none, and only with the flag off; no other application adds a role. The
/// flag is put back, also after a failure.
Method ApplicationsFor(online As %Boolean) [ Private ]
{
	Set saved = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set error = ""
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", $Select(online: 1, 1: 0))
		Set model = $ClassMethod(..#GENERATOR, "Model")
		Set shown = ""
		Set signIn = ""
		Set iterator = model.applications.%GetIterator()
		While iterator.%GetNext(, .app) {
			Set shown = shown _ $Select(shown = "": "", 1: ";") _ app.name_"=:"_..List(app.roles, ":")
			Set signIn = signIn _ $Select(signIn = "": "", 1: ";") _ app.name_"="_app.signIn
		}
		Set roles = ##class(OcuTalon.Install.Step.Web).#APPLICATIONROLES
		Set hook = $Select(online: "", 1: ";/ocutalon/hook=:"_##class(OcuTalon.Install.Step.Web).#HOOKROLE)
		Set label = $Select(online: "online demo", 1: "local install")
		Do $$$AssertEquals(shown, "/ocutalon="_roles_";/ocutalon/api="_roles_hook, label_": /ocutalon and /ocutalon/api add the roles of Web.APPLICATIONROLES, /ocutalon/hook adds only the webhook role off the online demo, and no other application of the Web step adds a role")
		Do $$$AssertEquals(signIn, "/ocutalon=password;/ocutalon/api=password"_$Select(online: "", 1: ";/ocutalon/hook=none (unauthenticated)"), label_": each application's sign-in is read from its AutheEnabled")
	} Catch exception {
		Set error = exception.DisplayString()
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", saved)
	Do $$$AssertEquals(error, "", "the applications were read without an error")
}

/// The row of the tool in the model, or "".
ClassMethod RowOf(name As %String) As %DynamicObject [ Private ]
{
	Set found = ""
	Set rows = $ClassMethod(..#GENERATOR, "ToolRows")
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		If row.name = name Set found = row
	}
	Quit found
}

/// 1 when the text starts with the prefix.
ClassMethod StartsWith(text As %String, prefix As %String) As %Boolean [ Private ]
{
	Quit ($Extract(text, 1, $Length(prefix)) = prefix)
}

/// 1 when one of the lines of the text is exactly the line.
ClassMethod HasLine(text As %String, line As %String) As %Boolean [ Private ]
{
	Set lf = $Char(10)
	Quit ((lf_text) [ (lf_line_lf))
}

/// The text of a table cell, as the generator makes it.
ClassMethod Cell(text As %String) As %String [ Private ]
{
	Quit $ClassMethod(..#GENERATOR, "Cell", text)
}

/// The items of an array of strings as one list with the separator.
ClassMethod List(array As %DynamicArray, separator As %String) As %String [ Private ]
{
	Set list = ""
	Set iterator = array.%GetIterator()
	While iterator.%GetNext(, .item) {
		Set list = list _ $Select(list = "": "", 1: separator) _ item
	}
	Quit list
}

/// The areas of areas(role, resource, area), comma-separated, in order.
ClassMethod Areas(ByRef areas, role As %String, resource As %String) As %String [ Private ]
{
	Set list = ""
	Set area = ""
	For {
		Set area = $Order(areas(role, resource, area))
		Quit:area=""
		Set list = list _ $Select(list = "": "", 1: ",") _ area
	}
	Quit list
}

/// The list sorted, as a list.
ClassMethod Sorted(list As %List) As %List [ Private ]
{
	Set position = 0
	While $ListNext(list, position, item) {
		Set sorted(item) = ""
	}
	Set result = ""
	Set item = ""
	For {
		Set item = $Order(sorted(item))
		Quit:item=""
		Set result = result _ $ListBuild(item)
	}
	Quit result
}

/// The document of TestSplice: hand-written lines around the three marker pairs, with the line ending, with or without a final newline. filled is
/// 0 for the old content of the regions and 1 for the content that the sections of the test give.
ClassMethod Doc(eol As %String, final As %Boolean, filled As %Boolean) As %String [ Private ]
{
	Set generator = ..#GENERATOR
	Set lines = $ListBuild("# Title", "Hand-written text.  ")
	Set lines = lines _ $ListBuild($ClassMethod(generator, "BeginMarker", "tools"))
	Set lines = lines _ $Select(filled: $ListBuild("NEW T1", "NEW T2"), 1: $ListBuild("old"))
	Set lines = lines _ $ListBuild($ClassMethod(generator, "EndMarker", "tools"), "", "between", $ClassMethod(generator, "BeginMarker", "fix-kinds"))
	Set lines = lines _ $Select(filled: $ListBuild("NEW F"), 1: "")
	Set lines = lines _ $ListBuild($ClassMethod(generator, "EndMarker", "fix-kinds"), $Char(9)_"tabbed", $ClassMethod(generator, "BeginMarker", "privileges"))
	Set lines = lines _ $Select(filled: $ListBuild("NEW P1", "NEW P2", "NEW P3"), 1: $ListBuild("older", "oldest"))
	Set lines = lines _ $ListBuild($ClassMethod(generator, "EndMarker", "privileges"), "end")
	Set text = $ListToString(lines, eol)
	Quit text _ $Select(final: eol, 1: "")
}

/// Asserts that the splice of the text is refused with a status that names the marker, and gives nothing.
Method AssertRefused(text As %String, marker As %String, what As %String, ByRef sections) [ Private ]
{
	Set sc = $ClassMethod(..#GENERATOR, "Splice", text, .out, .sections)
	Do $$$AssertStatusNotOK(sc, what_" is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ marker, what_": the status names the marker")
	Do $$$AssertEquals(out, "", what_": nothing is written")
}

/// Writes the text to the file byte for byte, replacing the file.
ClassMethod WriteFile(file As %String, text As %String) [ Private ]
{
	Do ##class(%File).Delete(file)
	Set stream = ##class(%Stream.FileBinary).%New()
	$$$ThrowOnError(stream.LinkToFile(file))
	$$$ThrowOnError(stream.Write(text))
	$$$ThrowOnError(stream.%Save())
}

/// The bytes of the file.
ClassMethod ReadFile(file As %String) As %String [ Private ]
{
	Set stream = ##class(%Stream.FileBinary).%New()
	$$$ThrowOnError(stream.LinkToFile(file))
	Quit $Select(stream.Size = 0: "", 1: stream.Read(stream.Size))
}

/// The letters R, W and U of a permission, each once, in that order.
ClassMethod Letters(permission As %String) As %String [ Private ]
{
	Quit $Select(permission [ "R": "R", 1: "")_$Select(permission [ "W": "W", 1: "")_$Select(permission [ "U": "U", 1: "")
}

/// The differences between the expected resources of a role (expected(resource) = permission) and its resource list (resource:permission,...), as
/// text that names the role, the resource and the permission of each, or "".
ClassMethod Differences(role As %String, ByRef expected, resources As %String) As %String [ Private ]
{
	Set text = ""
	For i = 1:1:$Length(resources, ",") {
		Set pair = $Piece(resources, ",", i)
		If pair = "" Continue
		Set actual($Piece(pair, ":", 1)) = ..Letters($Piece(pair, ":", 2))
	}
	Set resource = ""
	For {
		Set resource = $Order(actual(resource))
		Quit:resource=""
		If '$Data(expected(resource)) {
			Set text = text _ "; "_role_" holds the extra resource "_resource_":"_actual(resource)
		} ElseIf expected(resource) '= actual(resource) {
			Set text = text _ "; "_role_" holds "_resource_":"_actual(resource)_", listed as "_expected(resource)
		}
	}
	Set resource = ""
	For {
		Set resource = $Order(expected(resource))
		Quit:resource=""
		If '$Data(actual(resource)) Set text = text _ "; "_role_" lacks the listed "_resource_":"_expected(resource)
	}
	Quit text
}

/// The resources of the role as one resource:permission list, or "<none>" when it does not exist; granted is the roles it is granted. Runs in %SYS.
ClassMethod ReadRole(role As %String, Output granted As %String) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set granted = ""
	If '##class(Security.Roles).Exists(role) Quit "<none>"
	Do ##class(Security.Roles).Get(role, .properties)
	Set granted = $Get(properties("GrantedRoles"))
	Quit $Get(properties("Resources"))
}

/// Whether the user exists, whether it is enabled, its roles and its escalation roles. Runs in %SYS.
ClassMethod ReadUser(user As %String, Output exists As %Boolean, Output enabled As %Boolean, Output roles As %String, Output escalation As %String) [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set exists = ''##class(Security.Users).Exists(user)
	Set enabled = ""
	Set roles = ""
	Set escalation = ""
	If 'exists Quit
	Do ##class(Security.Users).Get(user, .properties)
	Set enabled = +$Get(properties("Enabled"))
	Set roles = $Get(properties("Roles"))
	Set escalation = $Get(properties("EscalationRoles"))
}

/// The SQL privileges of the role as Namespace|SQLObject|Privilege, sorted, separated by semicolons. Runs in %SYS.
ClassMethod SqlPrivileges(role As %String) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Namespace, SQLObject, Privilege FROM Security.SQLPrivileges WHERE Grantee = ?", role)
	While result.%Next() {
		Set rows(result.%GetData(1)_"|"_result.%GetData(2)_"|"_result.%GetData(3)) = ""
	}
	Set list = ""
	Set row = ""
	For {
		Set row = $Order(rows(row))
		Quit:row=""
		Set list = list _ $Select(list = "": "", 1: ";") _ row
	}
	Quit list
}

/// The MatchRoles of the web application. Runs in %SYS.
ClassMethod MatchRoles(application As %String) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If '##class(Security.Applications).Exists(application) Quit "<none>"
	Do ##class(Security.Applications).Get(application, .properties)
	Quit $Get(properties("MatchRoles"))
}

}
