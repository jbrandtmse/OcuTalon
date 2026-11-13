/// The generator of docs/security-overview.md (AD-10, AD-16, AD-22, AD-23, AD-24): the lists of the built-in tools, of the fix kinds and of
/// the privileges that OcuTalon's roles and service user hold, written from the product itself, so that the document cannot drift from what
/// ships and what the installer grants. It changes no security record, grant or role: it reads and lists.
///   - Model builds the facts as one object: the tools (read through %AI.Catalog with the pattern OcuTalon.%, kept to the agents of
///     OcuTalon.Agent. and the toolsets of OcuTalon.Tools., the scope of Install.Step.Tools.Toolsets; each toolset is expanded with
///     %Discover, because the catalog cannot expand toolsets, plus one row for each entry of the product's classification (Install.Step.Production ClassificationEntries) that names AI Hub's knowledge base, RagRows),
///     the fix kinds, the roles as Install.Step.Roles.Compose composes them
///     from the Grants() of the areas, the grants that only demo mode adds (Install.Step.Demo WithOrdersData and WithOrders), the SQL
///     privileges of the trace role, the service user and the application roles of the web applications;
///   - Sections renders the facts as the Markdown of the keys tools, fix-kinds and privileges, in a sorted and deterministic order, in ASCII; the tools section ends
///     with the sentence RAGSTATEMENT about the one tool that has no class of its own (Story 19.4), the fix-kinds section with the sentence ONLINESTATEMENT about the online demo's service role (Story 23.2),
///     and the privileges section has the sentence MCPSTATEMENT after the Roles table, about the resource that each MCP server has (Story 22.6), built from the installer's own names
///     (Install.Step.Mcp RESOURCEPREFIX and PERMISSION, Install.Step.Users SERVICEROLE), so that it cannot drift from the grant;
///   - Splice replaces the text between the markers of each key in a document and nothing else; Regenerate does that for a file.
/// A tool value is read only through the readers that the gate and the installer use (StepBuffer.ToolParameter and LabelFor,
/// Gate.HookFor and Resources). A tool that classifies by its arguments (it has a Classify or Classify<NAME> method) shows the text of its
/// CLASSIFYRULE<NAME> or CLASSIFYRULE parameter, and generation fails naming the tool when that text is missing. Every method that reads
/// the product throws a status when it cannot, and Regenerate and Splice return it. Run in the namespace OCUTALON.
Class OcuTalon.Install.SecurityOverview [ DependsOn = (OcuTalon.Install.Step.Mcp, OcuTalon.Install.Step.Users) ]
{

/// The keys of the generated sections, in the order of the document.
Parameter KEYS = "tools,fix-kinds,privileges";

/// The text that starts a marker line: the begin marker is this, a space, BEGIN GENERATED, the key and the owner text; the end marker has no owner text.
Parameter OWNERTEXT = "written by OcuTalon.Install.SecurityOverview, do not edit";

/// The fixed statement of the tools section (AD-10), word for word.
Parameter STATEMENT = "No built-in tool runs operating-system commands, arbitrary ObjectScript or Python, or data-changing SQL, and AI Hub's shell, filesystem, SQL and web-search tools are never registered. The automated tool-inventory test `OcuTalon.Test.Agent.Runners` (`TestToolInventory`) checks this on every running runner.";

/// The sentence after the tools table (Story 19.4, the Contest Planner's PUBLIC TEXT ruling of 2026-11-07), word for word: the one tool that has no class of
/// its own, AI Hub's knowledge base over the added documents, which the gate classifies by the bridge's classification setting.
Parameter RAGSTATEMENT = "One tool has no class of its own: `documents`, the search over your added documents that AI Hub's knowledge base gives the Chat agent. AI Hub sends no source class with its calls, so the gate classifies this one tool, and no other, by the bridge's classification setting: safe and read-only, but its output is never trusted, so a turn that searches your documents is treated as holding untrusted content. The gate also limits each search to 5 passages. Any other call that arrives without a source class stays unclassified and counts as risky.";

/// The sentence after the fix kinds table, word for word: an online-demo install leaves the item kinds' resource off the service role (Install.Step.Fix Grants), so
/// the item kinds can run on a local install only. The privileges tables below list the role's grants for a local install.
Parameter ONLINESTATEMENT = "On the online demo, OcuTalonServiceRole does not hold %Ens_ConfigItemRun:U, so OcuTalon can't suspend or resume items there.";

/// The sentence after the Roles table (Story 22.6), word for word: the resource that each registered MCP server has and the service role's permission on it, as Install.Step.Mcp
/// grants them, and the demo, where no server can be added. Its names come from the installer, so the sentence follows the grant.
Parameter MCPSTATEMENT = {"Each MCP server that an admin adds has its own resource, `"_##class(OcuTalon.Install.Step.Mcp).#RESOURCEPREFIX_"<server>`, with no public permission, and `"_##class(OcuTalon.Install.Step.Users).#SERVICEROLE_"` holds "_##class(OcuTalon.Install.Step.Mcp).#PERMISSION_" on it until the server is removed. The gate checks it before every call of that server's tools. On the online demo there is none."};

/// The class of the product's classification entries that name AI Hub's knowledge base, the toolset that attaches it and the agent that holds it.
Parameter RAGCLASS = "%AI.RAG.KnowledgeBase";

Parameter RAGTOOLSET = "OcuTalon.Docs.Store";

Parameter RAGAGENT = "OcuTalon.Agent.Chat";

/// The pattern with which the catalog is read.
Parameter CATALOGPATTERN = "OcuTalon.%";

/// The package of the product's own agents.
Parameter AGENTPACKAGE = "OcuTalon.Agent.";

/// The package of the installer's areas, whose prefix is left off the area names in the privilege lists.
Parameter AREAPREFIX = "OcuTalon.Install.Step.";

/// The classification of every fix kind in the document (AD-16): a fix changes something, so it always waits for one approval with a dry run.
Parameter FIXCLASSIFICATION = "risky";

/// The namespace of the product, where the trace role is granted SQL SELECT on Ens.MessageHeader.
Parameter HOMENAMESPACE = "OCUTALON";

/// The SQL object that the trace role may read.
Parameter SQLOBJECT = "Ens.MessageHeader";

/// The facts of the document as {"tools","fixKinds","roles","demoOnly","sql","serviceUser","applications"}:
///   - tools: one {"name","source","toolset","agents","label","classification","readOnly","trustedOutput","resources"} per tool, sorted by name;
///     agents is the array of the agent classes that hold the tool's toolset, resources the array of {"resource","permission"};
///   - fixKinds: one {"class","name","classification","resources"} per kind of Fix.Kind.Classes, sorted by class; every fix kind is risky (FIXCLASSIFICATION): it waits for an approval with a dry run;
///   - roles: one {"role","declaredBy","grants"} per role, sorted by role, where grants is the array of {"resource","permission","declaredBy"}
///     sorted by resource and declaredBy the short names of the areas whose Grants() declare it;
///   - demoOnly: the {"role","resource","permission"} that demo mode adds to the service role and the trace role;
///   - sql: the {"role","privilege","object","namespace","when"} of the trace role, when being always or demo mode on;
///   - serviceUser: {"user","roles","login"};
///   - applications: one {"name","signIn","roles"} per web application of Install.Step.Web.Definitions whose MatchRoles adds roles to its requests,
///     sorted by name, where signIn is "password" or "none (unauthenticated)" (its AutheEnabled, 32 or 64) and roles is the array of those roles.
/// Throws a status when a fact cannot be read.
ClassMethod Model() As %DynamicObject
{
	Quit {
		"tools": (..ToolRows()),
		"fixKinds": (..FixKindRows()),
		"roles": (..RoleRows()),
		"demoOnly": (..DemoOnlyRows()),
		"sql": (..SqlRows()),
		"serviceUser": (..ServiceUser()),
		"applications": (..Applications())
	}
}

/// The tool rows of Model.
ClassMethod ToolRows() As %DynamicArray
{
	Do ..RagRows(.ragRows)
	Set toolsets = ..CatalogClasses("ToolSets", ##class(OcuTalon.Install.Step.Tools).#TOOLPACKAGE)
	Set agents = ..CatalogClasses("Agents", ..#AGENTPACKAGE)
	Set position = 0
	While $ListNext(agents, position, agent) {
		Set listed = $Parameter(agent, "TOOLSETS")
		For i = 1:1:$Length(listed, ",") {
			Set toolset = $ZStrip($Piece(listed, ",", i), "<>W")
			If toolset '= "" Set holders(toolset, agent) = ""
		}
	}
	Set position = 0
	While $ListNext(toolsets, position, toolset) {
		Set holding = []
		Set agent = ""
		For {
			Set agent = $Order(holders(toolset, agent))
			Quit:agent=""
			Do holding.%Push(agent)
		}
		Set tools = $ClassMethod(toolset, "%New").%Discover().tools
		Set iterator = tools.%GetIterator()
		While iterator.%GetNext(, .tool) {
			Set rows(tool.name _ $Char(1) _ toolset) = ..ToolRow(tool.provider, tool.name, toolset, holding)
		}
	}
	Merge rows = ragRows
	Set result = []
	Set key = ""
	For {
		Set key = $Order(rows(key))
		Quit:key=""
		Do result.%Push(rows(key))
	}
	Quit result
}

/// The rows of the tools that have no class of their own (Story 19.4): one for each entry of the product's classification (Install.Step.Production
/// ClassificationEntries, the entries that the install step seeds into Decide's ToolClassification row) whose class is RAGCLASS, so that the document cannot
/// drift from what ships and does not depend on a row that an administrator may have changed. The name and the source are the entry's, the toolset is the class
/// that attaches the tool (RAGTOOLSET), the agent is RAGAGENT, the step label is the one LabelFor gives, the classification and the flags are the entry's, and
/// there are no resources. The rows are in ragRows, under the keys of ToolRows.
ClassMethod RagRows(Output ragRows) [ Private ]
{
	Kill ragRows
	Set entries = ##class(OcuTalon.Install.Step.Production).ClassificationEntries()
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.class '= ..#RAGCLASS Continue
		Set agents = []
		Do agents.%Push(..#RAGAGENT)
		Set ragRows(entry.tool _ $Char(1) _ ..#RAGTOOLSET) = {
			"name": (entry.tool),
			"source": (entry.class),
			"toolset": (..#RAGTOOLSET),
			"agents": (agents),
			"label": ($ClassMethod("OcuTalon.Bridge.Adapter.StepBuffer", "LabelFor", entry.class, entry.tool)),
			"classification": (entry.classification),
			"readOnly": (+entry.readOnly),
			"trustedOutput": (+entry.trustedOutput),
			"resources": ([])
		}
	}
}

/// The row of one tool: its values are read with the readers of the gate and the installer.
ClassMethod ToolRow(source As %String, name As %String, toolset As %String, agents As %DynamicArray) As %DynamicObject
{
	Set buffer = "OcuTalon.Bridge.Adapter.StepBuffer"
	Quit {
		"name": (name),
		"source": (source),
		"toolset": (toolset),
		"agents": (agents),
		"label": ($ClassMethod(buffer, "LabelFor", source, name)),
		"classification": (..Classification(source, name)),
		"readOnly": (+($ClassMethod(buffer, "ToolParameter", source, name, "READONLY") = 1)),
		"trustedOutput": (+($ClassMethod(buffer, "ToolParameter", source, name, "TRUSTEDOUTPUT") = 1)),
		"resources": (##class(OcuTalon.Bridge.Policy.Gate).Resources($ClassMethod(buffer, "ToolParameter", source, name, "RESOURCES"), source_" "_name))
	}
}

/// The classification of a tool as the document shows it: the CLASSIFICATION parameter (safe or risky), "unclassified" when the tool declares none,
/// or "per call: " and the text of CLASSIFYRULE<NAME> or CLASSIFYRULE for a tool that has a Classify method. Throws a status that names the tool when
/// a Classify method has no rule text.
ClassMethod Classification(source As %String, name As %String) As %String
{
	Set buffer = "OcuTalon.Bridge.Adapter.StepBuffer"
	Set hook = ##class(OcuTalon.Bridge.Policy.Gate).HookFor(source, name)
	If hook '= "" {
		Set rule = $ClassMethod(buffer, "ToolParameter", source, name, "CLASSIFYRULE")
		If $ZStrip(rule, "<>WC") = "" {
			$$$ThrowStatus($SYSTEM.Status.Error(5001, "The tool "_name_" of "_source_" classifies by "_hook_" but declares no CLASSIFYRULE text"))
		}
		Quit "per call: "_$ZStrip(rule, "<>WC")
	}
	Set value = $ClassMethod(buffer, "ToolParameter", source, name, "CLASSIFICATION")
	Quit $Select(value = "": "unclassified", 1: value)
}

/// The sorted class names of a %AI.Catalog method (Agents, ToolSets) for the pattern OcuTalon.%, kept to the classes that start with the package.
ClassMethod CatalogClasses(method As %String, package As %String) As %List
{
	Set list = ""
	Set entries = $ClassMethod("%AI.Catalog", method, ..#CATALOGPATTERN)
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If $Extract(entry.name, 1, $Length(package)) = package Set names(entry.name) = ""
	}
	Set name = ""
	For {
		Set name = $Order(names(name))
		Quit:name=""
		Set list = list _ $ListBuild(name)
	}
	Quit list
}

/// The fix kind rows of Model.
ClassMethod FixKindRows() As %DynamicArray
{
	Set classes = ##class(OcuTalon.Fix.Kind).Classes()
	Set position = 0
	While $ListNext(classes, position, class) {
		Set rows(class) = {"class": (class), "name": ($Parameter(class, "NAME")), "classification": (..#FIXCLASSIFICATION), "resources": (##class(OcuTalon.Bridge.Policy.Gate).Resources($Parameter(class, "RESOURCES"), class))}
	}
	Set result = []
	Set class = ""
	For {
		Set class = $Order(rows(class))
		Quit:class=""
		Do result.%Push(rows(class))
	}
	Quit result
}

/// The role rows of Model, from the composed grants and the areas that declare them.
ClassMethod RoleRows() As %DynamicArray
{
	$$$ThrowOnError(##class(OcuTalon.Install.Step.Roles).Compose(.composed))
	$$$ThrowOnError(##class(OcuTalon.Install.Registry).Declared("Grants", .entries))
	Set n = ""
	For {
		Set n = $Order(entries(n))
		Quit:n=""
		Set grant = entries(n)
		Set area = $Piece(entries(n, "area"), ..#AREAPREFIX, 2)
		If area = "" Set area = entries(n, "area")
		Set declared(grant.role, ..ResourceKey(grant.resource), area) = ""
	}
	Set result = []
	Set role = ""
	For {
		Set role = $Order(composed(role))
		Quit:role=""
		Set grants = []
		Set resource = ""
		For {
			Set resource = $Order(composed(role, resource))
			Quit:resource=""
			Do grants.%Push({"resource": (resource), "permission": (composed(role, resource)), "declaredBy": (..Keys(.declared, role, ..ResourceKey(resource)))})
		}
		Do result.%Push({"role": (role), "declaredBy": (..Keys(.declared, role, ..ResourceKey(""))), "grants": (grants)})
	}
	Quit result
}

/// The subscript under which the declaration of a resource is kept: the resource, or a character that no resource holds for the declaration of a
/// role alone, because a subscript cannot be null.
ClassMethod ResourceKey(resource As %String) As %String [ Private ]
{
	Quit $Select(resource = "": $Char(1), 1: resource)
}

/// The subscripts below declared(role, resource key) as a dynamic array.
ClassMethod Keys(ByRef declared, role As %String, resource As %String) As %DynamicArray [ Private ]
{
	Set keys = []
	Set key = ""
	For {
		Set key = $Order(declared(role, resource, key))
		Quit:key=""
		Do keys.%Push(key)
	}
	Quit keys
}

/// The grants that only demo mode adds, as the Demo step composes them for the roles with nothing else: the service role gets Read on the data
/// database of OCUORDERS (WithOrdersData), the trace role Read on both databases (WithOrders).
ClassMethod DemoOnlyRows() As %DynamicArray
{
	Set demo = "OcuTalon.Install.Step.Demo"
	Set result = []
	Set lists(##class(OcuTalon.Install.Step.Users).#SERVICEROLE) = $ClassMethod(demo, "WithOrdersData", "", 1)
	Set lists(##class(OcuTalon.Install.Step.Web).#TRACEROLE) = $ClassMethod(demo, "WithOrders", "", 1)
	Set role = ""
	For {
		Set role = $Order(lists(role))
		Quit:role=""
		Set pairs = ##class(OcuTalon.Bridge.Policy.Gate).Resources(lists(role), role)
		Set iterator = pairs.%GetIterator()
		While iterator.%GetNext(, .pair) {
			Do result.%Push({"role": (role), "resource": (pair.resource), "permission": (pair.permission)})
		}
	}
	Quit result
}

/// The SQL privileges of the trace role: SELECT on Ens.MessageHeader in OCUTALON always (the Web step), and in OCUORDERS with demo mode on (the Demo step).
ClassMethod SqlRows() As %DynamicArray
{
	Set role = ##class(OcuTalon.Install.Step.Web).#TRACEROLE
	Quit [
		{"role": (role), "privilege": "SELECT", "object": (..#SQLOBJECT), "namespace": (..#HOMENAMESPACE), "when": "always"},
		{"role": (role), "privilege": "SELECT", "object": (..#SQLOBJECT), "namespace": (##class(OcuTalon.Install.Step.Demo).#NAMESPACE), "when": "demo mode on"}
	]
}

/// The service user: its name, the roles it holds (exactly the service role) and its login, which is disabled.
ClassMethod ServiceUser() As %DynamicObject
{
	Quit {"user": (##class(OcuTalon.Install.Step.Users).#SERVICEUSER), "roles": [(##class(OcuTalon.Install.Step.Users).#SERVICEROLE)], "login": "disabled"}
}

/// The web applications of the Web step (Install.Step.Web.Definitions) that add roles to their requests, how each signs its users in, and those roles: an
/// application whose MatchRoles is not empty. Throws a status that names the application when its MatchRoles is not of the form :role[:role...], which
/// adds the roles to every request of the application; a match role would make that claim untrue.
ClassMethod Applications() As %DynamicArray
{
	$$$ThrowOnError(##class(OcuTalon.Install.Step.Web).Definitions(.apps))
	Set result = []
	Set name = ""
	For {
		Set name = $Order(apps(name))
		Quit:name=""
		Set matched = $Get(apps(name, "MatchRoles"))
		If matched = "" Continue
		If ($Extract(matched) '= ":") || (matched [ ",") {
			$$$ThrowStatus($SYSTEM.Status.Error(5001, "The web application "_name_" has the MatchRoles "_matched_", which is not of the form :role[:role...]"))
		}
		Set roles = []
		For i = 2:1:$Length(matched, ":") {
			If $Piece(matched, ":", i) '= "" Do roles.%Push($Piece(matched, ":", i))
		}
		Do result.%Push({"name": (name), "signIn": ($Select($Get(apps(name, "AutheEnabled")) = 64: "none (unauthenticated)", 1: "password")), "roles": (roles)})
	}
	Quit result
}

/// sections(key) = the Markdown of each key of KEYS: lines that each end in a line feed, in ASCII. Throws a status that names the key when a
/// section holds a character outside ASCII.
ClassMethod Sections(Output sections)
{
	Kill sections
	Set model = ..Model()
	Set sections("tools") = ..ToolsText(model)
	Set sections("fix-kinds") = ..FixKindsText(model)
	Set sections("privileges") = ..PrivilegesText(model)
	Set key = ""
	For {
		Set key = $Order(sections(key))
		Quit:key=""
		Set code = ..NonAscii(sections(key))
		If code '= "" {
			$$$ThrowStatus($SYSTEM.Status.Error(5001, "The "_key_" section holds the character "_code_", which is not ASCII"))
		}
	}
}

/// "" when the text holds only the line feed, the tab and the printable ASCII characters; else the code of the first other character.
ClassMethod NonAscii(text As %String) As %String
{
	Set allowed = $Char(9, 10)
	For code = 32:1:126 {
		Set allowed = allowed _ $Char(code)
	}
	Set rest = $Translate(text, allowed)
	If rest = "" Quit ""
	Quit "U+"_$Translate($Justify($ZHex($Ascii(rest)), 4), " ", 0)
}

/// The tools section.
ClassMethod ToolsText(model As %DynamicObject) As %String
{
	Set text = "## Built-in tools"_$Char(10)_$Char(10)_..#STATEMENT_$Char(10)_$Char(10)
	Set text = text_"| Tool | Source class | Toolset | Agents | Step label | Classification | Read-only | Trusted output | Resources |"_$Char(10)
	Set text = text_"| --- | --- | --- | --- | --- | --- | --- | --- | --- |"_$Char(10)
	Set iterator = model.tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set text = text_"| "_..Code(tool.name)_" | "_..Code(tool.source)_" | "_..Code(tool.toolset)_" | "_..CodeList(tool.agents)_" | "_..Cell(tool.label)_" | "_..Cell(tool.classification)_" | "_..YesNo(tool.readOnly)_" | "_..YesNo(tool.trustedOutput)_" | "_..Pairs(tool.resources)_" |"_$Char(10)
	}
	Quit text_$Char(10)_..#RAGSTATEMENT_$Char(10)_$Char(10)
}

/// The fix kinds section: the table and the sentence about the online demo.
ClassMethod FixKindsText(model As %DynamicObject) As %String
{
	Set text = "## Fix kinds"_$Char(10)_$Char(10)
	Set text = text_"| Class | Name | Classification | Resources |"_$Char(10)_"| --- | --- | --- | --- |"_$Char(10)
	Set iterator = model.fixKinds.%GetIterator()
	While iterator.%GetNext(, .kind) {
		Set text = text_"| "_..Code(kind.class)_" | "_..Code(kind.name)_" | "_..Cell(kind.classification)_" | "_..Pairs(kind.resources)_" |"_$Char(10)
	}
	Quit text_$Char(10)_..#ONLINESTATEMENT_$Char(10)_$Char(10)
}

/// The privileges section: the roles, the grants that only demo mode adds, the SQL privileges, the service user and the application roles.
ClassMethod PrivilegesText(model As %DynamicObject) As %String
{
	Set lf = $Char(10)
	Set text = "## Privileges"_lf_lf_"### Roles"_lf_lf
	Set text = text_"| Role | Resource | Permission | Declared by |"_lf_"| --- | --- | --- | --- |"_lf
	Set iterator = model.roles.%GetIterator()
	While iterator.%GetNext(, .role) {
		If role.grants.%Size() = 0 {
			Set text = text_"| "_..Code(role.role)_" | none | - | "_..CodeList(role.declaredBy)_" |"_lf
			Continue
		}
		Set grants = role.grants.%GetIterator()
		While grants.%GetNext(, .grant) {
			Set text = text_"| "_..Code(role.role)_" | "_..Code(grant.resource)_" | "_grant.permission_" | "_..CodeList(grant.declaredBy)_" |"_lf
		}
	}
	Set text = text_lf_..#MCPSTATEMENT_lf_lf_"### With demo mode on"_lf_lf_"| Role | Resource | Permission |"_lf_"| --- | --- | --- |"_lf
	Set iterator = model.demoOnly.%GetIterator()
	While iterator.%GetNext(, .grant) {
		Set text = text_"| "_..Code(grant.role)_" | "_..Code(grant.resource)_" | "_grant.permission_" |"_lf
	}
	Set text = text_lf_"### SQL privileges"_lf_lf_"| Role | Privilege | Object | Namespace | When |"_lf_"| --- | --- | --- | --- | --- |"_lf
	Set iterator = model.sql.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set text = text_"| "_..Code(row.role)_" | "_row.privilege_" | "_..Code(row.object)_" | "_row.namespace_" | "_row.when_" |"_lf
	}
	Set text = text_lf_"### Service user"_lf_lf_"| User | Roles | Login |"_lf_"| --- | --- | --- |"_lf
	Set text = text_"| "_..Code(model.serviceUser.user)_" | "_..CodeList(model.serviceUser.roles)_" | "_model.serviceUser.login_" |"_lf
	Set text = text_lf_"### Application roles"_lf_lf_"| Web application | Sign-in | Roles added to its requests |"_lf_"| --- | --- | --- |"_lf
	Set iterator = model.applications.%GetIterator()
	While iterator.%GetNext(, .app) {
		Set text = text_"| "_..Code(app.name)_" | "_app.signIn_" | "_..CodeList(app.roles)_" |"_lf
	}
	Quit text_lf
}

/// The text as one table cell: line breaks become spaces and a vertical bar is escaped.
ClassMethod Cell(text As %String) As %String
{
	Quit $Replace($ZStrip($Translate(text, $Char(13, 10), "  "), "<>W"), "|", "\|")
}

/// The text as a code span in a cell.
ClassMethod Code(text As %String) As %String
{
	Quit "`"_..Cell(text)_"`"
}

/// The code spans of an array of strings, comma-separated, or "none" for an empty array.
ClassMethod CodeList(list As %DynamicArray) As %String
{
	Set text = ""
	Set iterator = list.%GetIterator()
	While iterator.%GetNext(, .item) {
		Set text = text _ $Select(text = "": "", 1: ", ") _ ..Code(item)
	}
	Quit $Select(text = "": "none", 1: text)
}

/// An array of {"resource","permission"} as resource:permission code spans, comma-separated, or "none".
ClassMethod Pairs(pairs As %DynamicArray) As %String
{
	Set text = ""
	Set iterator = pairs.%GetIterator()
	While iterator.%GetNext(, .pair) {
		Set text = text _ $Select(text = "": "", 1: ", ") _ ..Code(pair.resource_":"_pair.permission)
	}
	Quit $Select(text = "": "none", 1: text)
}

ClassMethod YesNo(flag As %Boolean) As %String
{
	Quit $Select(flag: "yes", 1: "no")
}

/// The begin marker line of a key.
ClassMethod BeginMarker(key As %String) As %String
{
	Quit "<!-- BEGIN GENERATED "_key_": "_..#OWNERTEXT_" -->"
}

/// The end marker line of a key.
ClassMethod EndMarker(key As %String) As %String
{
	Quit "<!-- END GENERATED "_key_" -->"
}

/// The text with the lines between the two marker lines of each key of KEYS replaced by the section of the key, and every other byte as it was,
/// the line endings and the final newline included: a region is written with the line ending of its begin marker line (a carriage return
/// before the line feed, when the marker line has one). A marker is a whole line. A marker that is missing or repeated, an end marker before its
/// begin marker, or a key whose begin marker comes before the end marker of the key before it, gives an error status that names the marker, and
/// out is empty. sections is given by the caller or, when it is not defined, made by Sections.
ClassMethod Splice(text As %String, Output out As %String, ByRef sections) As %Status
{
	Set out = ""
	Try {
		If '$Data(sections) Do ..Sections(.sections)
		Set lf = $Char(10)
		Set cr = $Char(13)
		Set count = $Length(text, lf)
		Set keys = $ListFromString(..#KEYS)
		For i = 1:1:count {
			Set lines(i) = $Piece(text, lf, i)
			Set line = lines(i)
			If $Extract(line, *) = cr Set line = $Extract(line, 1, *-1)
			Set position = 0
			While $ListNext(keys, position, key) {
				If line = ..BeginMarker(key) Set found("begin", key) = $Get(found("begin", key)) + 1, at("begin", key) = i
				If line = ..EndMarker(key) Set found("end", key) = $Get(found("end", key)) + 1, at("end", key) = i
			}
		}
		Set previous = 0
		Set position = 0
		While $ListNext(keys, position, key) {
			For kind = "begin", "end" {
				Set marker = $Select(kind = "begin": ..BeginMarker(key), 1: ..EndMarker(key))
				If '$Get(found(kind, key)) $$$ThrowStatus($SYSTEM.Status.Error(5001, "The marker '"_marker_"' is missing"))
				If found(kind, key) > 1 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The marker '"_marker_"' is repeated"))
			}
			If at("end", key) < at("begin", key) $$$ThrowStatus($SYSTEM.Status.Error(5001, "The marker '"_..EndMarker(key)_"' comes before '"_..BeginMarker(key)_"'"))
			If at("begin", key) < previous $$$ThrowStatus($SYSTEM.Status.Error(5001, "The marker '"_..BeginMarker(key)_"' is out of order: it comes before the end marker of the section before it"))
			Set previous = at("end", key)
		}
		Set result = ""
		Set next = 1
		Set position = 0
		While $ListNext(keys, position, key) {
			For i = next:1:at("begin", key) {
				Set result = result _ lines(i) _ lf
			}
			Set eol = $Select($Extract(lines(at("begin", key)), *) = cr: cr, 1: "")
			Set body = sections(key)
			For i = 1:1:$Length(body, lf) - 1 {
				Set result = result _ $Piece(body, lf, i) _ eol _ lf
			}
			Set next = at("end", key)
		}
		For i = next:1:count {
			Set result = result _ lines(i) _ $Select(i < count: lf, 1: "")
		}
		Set out = result
		Set sc = $SYSTEM.Status.OK()
	} Catch exception {
		Set out = ""
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Reads inFile, replaces its generated sections (Splice) and writes the result to outFile, byte for byte outside the sections. Nothing is written
/// when the splice or a read fails. The status is that of the failure.
ClassMethod Regenerate(inFile As %String, outFile As %String) As %Status
{
	Set io = $IO
	Try {
		Set stream = ##class(%Stream.FileBinary).%New()
		$$$ThrowOnError(stream.LinkToFile(inFile))
		If stream.Size < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The file "_inFile_" cannot be read"))
		Set text = $Select(stream.Size = 0: "", 1: stream.Read(stream.Size))
		Kill stream
		Set sc = ..Splice(text, .out)
		If $$$ISOK(sc) {
			Open outFile:("WNSK\RAW\"):5
			If '$Test $$$ThrowStatus($SYSTEM.Status.Error(5001, "The file "_outFile_" cannot be written"))
			Use outFile
			Write out
			Close outFile
			Use io
		}
	} Catch exception {
		Close outFile
		Use io
		Set sc = exception.AsStatus()
	}
	Quit sc
}

}
