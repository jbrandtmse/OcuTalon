Include Ensemble

/// The adapter of the agent runners (AD-6, AD-7). It extends AI Hub's outbound agent adapter and changes four things.
///   - It refuses to start (OnInit) when a setting would put a policy, a tool, a skill, a system prompt or a session
///     configuration on the agent, or when its agent class is not on its allow-list. OnInit calls nothing in AI Hub, so a runner
///     item starts and keeps running with no model key (FR-38). In the item's own job, before it checks the settings, OnInit
///     records whether the item can tell that its key is set (Keys.Record; the resolved provider's configuration when the item resolves to
///     another provider, below), and OnTearDown forgets that record (Keys.Forget), so that
///     Keys.Status is the state that the last start of the item recorded, until the item stops normally. A shadow host, which runs
///     no OnInit of its own, records nothing.
///   - It builds the agent on the first request that needs it (BuildAgent), by running AI Hub's own OnInit. A build that fails is
///     not kept, so the next request builds again. A runner whose entry key is absent and whose model is its agent's default is built on
///     the first supported provider whose key is set, with that provider's default model (Providers.Resolve; AD-7, AD-8): BuildAgent puts
///     the resolved configuration and model in the adapter's own settings before AI Hub's OnInit reads them. Nothing is written. The built agent has no Temperature, so that AI Hub adds no temperature to a
///     session.
///   - It composes the session config in one place (Compose) and uses it for every AI session it creates (NewSession) or opens
///     (OpenSession), because a session that is resumed without its config loses the cap and the effort. The config carries timeout_ms,
///     which Timeouts.Derive gives for the TimerSeconds setting of Decide as it stands when the config is composed (SessionConfigFor). A
///     saved session is opened with the agent's model and system prompt too, because AI Hub resumes a session with the ones it was saved with.
///   - It adds the gate (OcuTalon.Bridge.Policy.Gate) as the authorization policy and the step audit policy to every agent it builds
///     (OnAfterAgentInit), after any policy that a setting names, and refuses the AuthPolicy and AuditPolicy settings (REFUSED), so that
///     the gate decides every tool call and every tool call is a step (AD-6, AD-9, AD-10).
/// Tools of one request (AD-6, AD-10, AD-21, AD-31): the TurnToolsClass setting of the Decide item names a class (Ext.TurnTools) that Answer asks, once for
/// each request of kind turn, decide or diagnose, for the tools of the request's OwnerRef. SessionConfigFor does that in the runner's job, outside every
/// callback, before the AI session is created or opened. When the class gives no tool and no MCP server is attached, the request keeps the agent's own tool
/// manager, which no request ever adds a tool to. Otherwise the adapter composes a new tool manager for the request: the tools of the agent's toolsets, the
/// tools that OnAfterAgentInit attached through Attach, the tools of the class (each answers AddToManager), then the MCP servers, each only when it answers
/// (OfferServers), the gate and the step audit policy (Govern), assigns it to the agent, and
/// keeps the agent's own manager and the tools referenced; Answer puts the agent's own manager back and lets go of the rest on every path when the request
/// ends. When an MCP server is attached, the composed request also gets the turn's MCP map (MapMcpTools, AD-10): right after the manager that serves the request
/// is settled, which is the agent's own manager when the agent declares skills, the adapter lists that manager (%Discover) and keeps, in the context, the
/// fingerprint of each tool whose tool_ref starts mcp: (Context SetMcpTools), so that the gate can tell a tool from the one an admin classified. It then asks
/// ClassifyMcp of the ClassificationClass setting once for each of those tools, outside every callback, so that a host finds a changed tool at the start of the
/// turn and clears it there; the answers are ignored. Each failure is one redacted warning that holds no text of AI Hub, and the request goes on: a tool that is
/// not in the map counts as unclassified. A request is composed at most once, however many session configs it makes (a compaction makes two or three). An agent that declares skills
/// cannot take tools of its own, because UseSkill keeps its catalog on the agent and not on a manager: such a request fails with an error that names the
/// agent, and keeps the agent's own manager when the class gives it none, so that it is offered no MCP tool (one warning for each build). A named class that is missing, or does not extend the base, fails the request with that error. A request of kind tool composes nothing.
/// Bounded MCP (Story 22.9; AD-6, AD-21, AD-31): AI Hub's MCP client has no deadline, and a native call into it cannot be interrupted, so a server that accepts a
/// connection and never answers would hold the job for minutes at the next listing or tool call of any manager that holds it. The agent's own manager therefore
/// never holds an MCP server: a replay, a ToolInventory request and every request that composes nothing run on it and never touch a server. Before every AddTool
/// of a server, at the build and in each request that composes a manager, the adapter asks the McpServersClass Probe (Answers), which is bounded. The build adds the
/// servers, in order, to one manager that only serves the attach reports (AttachOne, ReportOf), and records a server that answered and was added (Record). A request
/// adds a recorded server to its manager only when its probe answers and its AddTool succeeds; otherwise the request goes on without that server, with one warning
/// that holds the server's name and a reason word, the server rests for RESTSECONDS in this job (no probe, no AddTool, no report), and the job reports the server
/// unavailable once (the build's report, or a later one for a server that was attached). The first request after the rest that finds the server again reports it
/// attached, with the build's report builder. A server that stops answering after its probe passed, within the same request, still holds the job until it closes the
/// connection (accepted for this release, AD-21).
/// The governed proxy (Story 22.3; AD-10, AD-21, AD-31): before the tools of the first MCP server whose probe answered are added to a request's manager, the adapter registers
/// the host's proxy toolset on it (the McpServersClass ProxyToolSet, OfferProxy), so that the proxy keeps its name when a server lists a tool of that name (AI Hub keeps the
/// first tool registered under a name), and no agent has it in its own tools. The proxy's name (Policy.Gate MCPPROXY) counts as a built-in name when the host names a
/// proxy: a server's tool of that name is reported refused, as one of the agent's own tools is. A request in which no server's tools were added offers no proxy: when no
/// probe answered, the proxy was never registered; when a probe answered but no server's tools were added after the proxy, the request goes on with a manager composed again
/// that holds no MCP server (ComposeManager), because a manager cannot give a tool up, and so does a request whose proxy toolset cannot be registered (one warning). The gate runs every allowed native MCP call through the proxy and not AI Hub's client. The map of the request also names each recorded server
/// (Context SetMcpTools), so that the gate can name the server in a proxy call and classify a direct call of the proxy as the native call of the same tool.
/// The replay of an approved MCP call (Story 22.4; AD-10, AD-21): the agent's own manager holds no MCP server, so the replay runs the call as the proxy's call on a manager
/// that holds only the host's proxy toolset (ProxyManager, which asks the McpServersClass setting itself, as the agent may have been built before any server existed: governed like every manager of a request, swapped in as the agent's tool manager and put back by RestoreTools,
/// which EndTurnTools shares), never the native tool and never the proxy in an agent's own tools.
/// The skipped request (AD-6, AD-8, AD-20): a request of kind decide, diagnose or turn whose DecisionRef already has a Decision row (Concluded) is
/// skipped, whatever its provenance and whether it is a first attempt, a rate-limit re-send or a second-model retry. Decide records that row when it
/// concludes, and its timer starts when it sends, so a request taken once the row exists (it waited in the runner's queue past its timer, or its retry
/// answered first) would have its answer dropped. The skip builds nothing and makes no model request, tool call, Usage row, AI session, conversation
/// lock or link; it writes one Info row and answers status OK with no reply, which Decide's completed process discards. A request of kind tool (the
/// replay), a request with no DecisionRef and a request whose row does not exist yet are never skipped; a first attempt taken while the second-model
/// retry that its timer sent is still running has no row yet, so it runs. The row is read once, before the build: a request already in Chat when the
/// timer fires runs to its end.
/// Answer is the runner's answer to a Request: the context is set before Chat and ended on every path, and the reply holds the
/// text, the provider's stop reason, and the host data and taint that the tools put in the context.
/// The conversation (AD-6, AD-10): only a turn with provenance user is linked (IsLinked), under the key (OwnerRef, the name of the runner item). AnswerLinked
/// holds the conversation lock (Data.ConversationLink Lock, 2 seconds) from the open or creation of the AI session to its save, and answers a Reply whose
/// Busy is 1 when it cannot take it. It opens the session that the link names with a newly composed config every time, or creates one (a turn with
/// SessionMode fresh starts a new session, seeded with the request's SeedText). SaveLinked saves the session only after a Chat that completed and whose
/// context is not tainted, and names it in the reply: SessionId is the saved session, SessionFrom the session the link named when the turn began, and
/// HistoryCount the messages that session held when it was opened. A Chat that threw, or a tainted one, saves nothing. The runner never moves the link
/// and never calls Data.ConversationLink Point: Decide does, once, when it accepts the reply as the decision's answer (Process.Decide PointLink), so a
/// late, refused or superseded reply moves no link: a new session that it saved stays unlinked until the purge removes it (AD-27), and a continue turn
/// saves into the session it opened, which the link keeps naming. No AI session object outlives a request: Answer clears the agent's Session (ReleaseSession) before the lock is released, so
/// that every linked turn, a re-sent one included, opens the saved history from the database. decide, diagnose and untrusted turns chat in a throwaway
/// session that is never saved or linked. ChatInput composes what Chat gets: the seed of a fresh turn, the system note and the input.
/// The retried turn (AD-6, AD-8): a request with RetryOf is the second-model retry of the attempt of the runner item that RetryOf names, and this
/// runner (the retry runner) answers it only when that item's RetryItem setting names this runner (RetryAllowed); any other RetryOf is an error
/// status, with no Chat. Decide sends the retry of a linked turn as a fresh one, whose SeedText it wrote from the stored messages that the first attempt
/// began with (DW-726). A linked turn with RetryOf takes no conversation lock (AnswerRetried): it chats in a new AI session, seeded through ChatInput with
/// that SeedText, and after a completed, untainted Chat that is not late (RetryIsLate) it saves the session and names it in the reply (SessionId;
/// SessionFrom is the session that the first runner's link names). A retry that is already late when the runner takes it (Decide has already recorded the
/// decision of its DecisionRef, because the retry's timer fired while it waited) is skipped, as below. A retry whose timer fires during its Chat saves no
/// session: its cost is counted and its reply is dropped by Decide (AD-8). The retry runner never links a conversation of its
/// own, and Decide points the first runner's link at the retry's session only when it accepts the reply. The session config of a request with RetryOf
/// takes timeout_ms from Timeouts.RetryTimer of the bridge timer.
/// Compaction (AD-6, AD-20): a request that Decide flags (Compact 1) and that continues a linked conversation is compacted by Compact in
/// AnswerLinked, in the runner's job, under the conversation lock, after the session is opened and before Converse. The runner cuts the
/// stored history so that the last user turn stays whole (Compaction.Cut, CutOf), calls ForkAndSummarize on the session with the
/// compaction prompt and a low-effort summarizer provider (SummarizerProvider), writes one Usage row for the summarizer's request
/// (RecordCompaction), and switches to the fork only after Compaction.Check passes: the fork is saved, every reference to the original
/// is released and the fork is opened again with OpenSession; the link is not touched, and Decide points it at the fork when it accepts the reply. Any
/// exception, a failed check, save or reopen, a summarizer request whose estimate would pass the request-size limit (Decide RequestLimit) and a first
/// request that would still pass it start a fresh AI session seeded with a code-written summary instead (Compaction.Seed), which is saved after a
/// completed, untainted Chat like the session of a fresh turn. A compaction that fails is one warning (CompactWarning), never the reply's FailureText.
/// No callback compacts, and no AI Hub call runs inside one.
/// Converse counts the call (AD-6, AD-9, AD-20): it reads the session's GetStats() after the session is made and again after Chat,
/// outside every callback, and RecordUsage writes one Usage row from the difference, priced from Price. That happens after every Chat
/// that returns, whether or not Decide still waits for it, and after a Chat that threw when the difference holds a model request or a
/// token; a call that threw before any request writes nothing. The reply carries the same counts, the cost and the model, the step
/// count (model requests plus tool calls) and the wall time of Chat in milliseconds. A stats, price or save problem is logged as a
/// warning and never changes the answer or its status. Every reply, a failure reply included, also says whether a tool ran (ToolsRan:
/// AI Hub's tool-call counter went up between the two readings, a step record is of kind tool, or a reading could not be read), because
/// Decide sends a rate-limited attempt again only when no tool ran. Inventory lists the tools of the live ToolManager, which holds no MCP server.
/// Converse also records the agent steps of the call (AD-9): it starts the step buffer right before Chat, with the size of what the
/// first request carries (BaseChars: the system prompt, the tool catalog, the input and, for an opened session, its stored history), and
/// passes the step renderer to Chat; the renderer records one step for every model response and the step
/// audit policy one for every tool call, in the runner's job. After Chat, outside every callback, Converse reads the buffer: the
/// estimated sizes of the model requests go to the Usage row (RecordUsage), and the redacted step records go to the reply (Steps).
/// A Chat that throws is answered with a failure Reply, never an error status (DW-83): FailureText holds the redacted text of AI Hub's
/// error, cut to Reply.#MAXFAILURE (StepBuffer.Part), and the reply carries the buffered steps, the usage, the host data and the taint
/// like any other; its Text and FinishReason are empty, so that Decide classifies the failure and still sends the steps to Visual
/// Trace. A warning names the runner item, the DecisionRef and the FailureText. A failure before Chat (a refused request, BuildAgent,
/// NewSession, OpenSession, Context.Begin) keeps its error status and has no steps. The buffer ends with the context on every path. This
/// class names no other OcuTalon package (AD-2).
Class OcuTalon.Bridge.Adapter.Agent Extends EnsLib.AI.Agent.OutboundAdapter
{

/// The settings that the adapter adds to AI Hub's.
Parameter SETTINGS = "Effort:Basic,AgentAllowList:Basic";

/// The settings of AI Hub's adapter that must be empty, comma-separated. SessionConfigString may also hold {}.
Parameter REFUSED = "AuthPolicy,AuditPolicy,DiscoveryPolicy,IrisTools,AdditionalTools,IrisSkills,AdditionalSkills,SystemPrompt,SessionConfigString";

/// The seconds that a server that failed its probe, or its AddTool, in a request rests in this job before a request asks again.
Parameter RESTSECONDS = 60;

/// The output cap of a request, in tokens (AD-7).
Parameter CAP = 8000;

/// The effort to ask of an Anthropic model, as output_config.effort: low, medium or high. Empty sends no effort (AD-7).
Property Effort As %String(MAXLEN = 32);

/// The agent classes that this adapter may run, comma-separated, each an exact class name (AD-6). Empty refuses every class.
Property AgentAllowList As %String(MAXLEN = 2000);

/// The id of the AI session that the conversation link named when AnswerLinked began, "" for a link that did not exist: the reply's SessionFrom,
/// which Decide's compare-and-set of the link expects. It keeps that value through a compaction fork. Not stored.
Property Expected As %String(MAXLEN = 128) [ Internal, Private, Transient ];

/// 1 while Answer serves a request with RetryOf, so that the session config takes the timeout of the retry runner (SessionConfigFor). Not stored.
Property Retrying As %Boolean [ InitialExpression = 0, Internal, Private, Transient ];

/// 1 while BuildAgent runs AI Hub's OnInit.
Property Building As %Boolean [ InitialExpression = 0, Internal, Private, Transient ];

/// The tools that OnAfterAgentInit attached to the agent (Attach), as specs, so that every composed manager adds them again. Not stored.
Property Attached As %List [ Internal, Private, Transient ];

/// The McpServersClass that AttachServers resolved, the server and config of each recorded MCP spec (McpOf, from the spec: $ListBuild(server, config)),
/// the status of the last report this job made for the spec (McpReported: attached or unavailable) and the $ZHorolog second until which the spec rests (McpRest).
/// SkillsWarned is 1 once the build has warned that the agent's MCP tools are not offered. BuildAgent resets them. Not stored.
Property McpClass As %String(MAXLEN = 255) [ Internal, Private, Transient ];

Property McpOf As %String [ Internal, MultiDimensional, Private, Transient ];

Property McpReported As %String [ Internal, MultiDimensional, Private, Transient ];

Property McpRest As %String [ Internal, MultiDimensional, Private, Transient ];

Property SkillsWarned As %Boolean [ InitialExpression = 0, Internal, Private, Transient ];

/// 1 while Answer serves a request that may take tools of its own (every kind but tool), with its OwnerRef and kind (TurnOwner, TurnKind). Not stored.
Property TurnOpen As %Boolean [ InitialExpression = 0, Internal, Private, Transient ];

Property TurnOwner As %String(MAXLEN = "") [ Internal, Private, Transient ];

Property TurnKind As %String(MAXLEN = 32) [ Internal, Private, Transient ];

/// 1 once the request's tools were asked for, and the status of that (TurnStatus), which every later session config of the request returns again. Not stored.
Property TurnComposed As %Boolean [ InitialExpression = 0, Internal, Private, Transient ];

Property TurnStatus As %Status [ InitialExpression = {$$$OK}, Internal, Private, Transient ];

/// The agent's own tool manager while the manager of the request is assigned, the manager of the request and the tools that were added to it. Not stored.
Property OwnTools As %AI.ToolMgr [ Internal, Private, Transient ];

Property TurnManager As %AI.ToolMgr [ Internal, Private, Transient ];

Property TurnToolList As %ListOfObjects [ Internal, Private, Transient ];

/// Records the key state of the item (RecordKey), checks the settings and calls nothing in AI Hub. While BuildAgent runs it, it is
/// AI Hub's OnInit.
Method OnInit() As %Status [ Internal ]
{
	If ..Building Quit ##super()
	Do ..RecordKey()
	Quit ..CheckSettings()
}

/// Forgets the key state that this job recorded for the item (Keys.Forget), then runs the adapter's own tear-down.
Method OnTearDown() As %Status
{
	If ..IsJob() {
		Try {
			Do ##class(OcuTalon.Bridge.Keys).Forget(..BusinessHost.%ConfigName)
		} Catch {
		}
	}
	Quit ##super()
}

/// Records the key state of the item in its job (Keys.Record, with the ProviderConfig setting, or with the resolved configuration when the
/// item resolves to another provider, Resolved). The outcome never changes the status of OnInit.
Method RecordKey() [ Private ]
{
	If ..IsJob() {
		Try {
			Set text = ..ProviderConfig
			If ..Resolved(.config, .model) '= "" Set text = config.%ToJSON()
			Do ##class(OcuTalon.Bridge.Keys).Record(..BusinessHost.%ConfigName, text)
		} Catch {
		}
	}
}

/// The class that holds the provider table, Providers: a test class overrides it to run the resolution on its own table.
ClassMethod ProvidersClass() As %String
{
	Quit "OcuTalon.Bridge.Providers"
}

/// The provider that this runner resolves to when its own key is absent (Providers.Resolve), or "" for none: config is the in-memory
/// provider configuration and model the provider's default model. The runner's agent class and Model setting are its own, so that a shadow
/// runner resolves too. A runner whose ProviderName setting names a provider never resolves.
Method Resolved(Output config As %DynamicObject, Output model As %String) As %String [ Private ]
{
	Set config = ""
	Set model = ""
	If ..ProviderName '= "" Quit ""
	Quit $ClassMethod(..ProvidersClass(), "Resolve", ..BusinessHost.%ConfigName, "", ..ProviderConfig, .config, .model, ..AgentClass, ..Model)
}

/// 1 when the host of this adapter is an object that is not a shadow host. Ens.Host makes such a host for any %New of an item of the
/// running production that is not made as a shadow (%DoShadowNew), in whatever process; OcuTalon makes one only in the item's own job.
Method IsJob() As %Boolean [ Private ]
{
	Quit $IsObject(..BusinessHost) && '..BusinessHost.%isShadow
}

/// OK, or the error that names the first refused setting, the agent class that is not a compiled %AI.Agent class, or the agent
/// class that is not an exact entry of AgentAllowList. A setting is set when it is not empty once white space (spaces, tabs and
/// line breaks) is removed; SessionConfigString is also unset when it holds {}.
Method CheckSettings() As %Status
{
	Set names = $ListFromString(..#REFUSED)
	Set position = 0
	While $ListNext(names, position, name) {
		Set value = $ZStrip($Property($this, name), "*WC")
		If name = "SessionConfigString", value = "{}" Set value = ""
		If value '= "" {
			Quit
		}
	}
	If value '= "" {
		Quit $$$ERROR($$$GeneralError, "OcuTalon.Bridge.Adapter.Agent refuses to start: the setting "_name_" is set; the runner takes its tools, skills, policies, system prompt and session config from its agent class and the bridge, so none of "_$Translate(..#REFUSED, ",", " ")_" may be set")
	}
	Set class = ..AgentClass
	If (class = "") || '##class(%Dictionary.CompiledClass).%ExistsId(class) || '$ClassMethod(class, "%Extends", "%AI.Agent") {
		Quit $$$ERROR($$$GeneralError, "OcuTalon.Bridge.Adapter.Agent refuses to start: the AgentClass '"_class_"' is not a compiled %AI.Agent class")
	}
	Set allowed = $ListFromString(..AgentAllowList, ",")
	Set position = 0
	While $ListNext(allowed, position, entry) {
		If $ZStrip(entry, "<>WC") = class Quit
	}
	If $ZStrip($Get(entry), "<>WC") '= class {
		Quit $$$ERROR($$$GeneralError, "OcuTalon.Bridge.Adapter.Agent refuses to start: the AgentClass '"_class_"' is not on the AgentAllowList setting"_$Select($ZStrip(..AgentAllowList, "*WC") = "": " (it is empty, and an empty list allows no class)", 1: ""))
	}
	Quit $$$OK
}

/// Builds the agent when it is not built yet, by running AI Hub's OnInit, and clears the agent's Temperature. A build that
/// fails leaves no agent, so that the next call builds again. Before it runs AI Hub's OnInit, a runner whose own key is absent and whose model
/// is its agent's default is given the provider configuration and the model of the provider it resolves to (Resolved), in memory: AI Hub's
/// OnInit reads them from the adapter's settings, and nothing is written.
Method BuildAgent() As %Status
{
	If $IsObject(..Agent) Quit $$$OK
	If ..Resolved(.config, .model) '= "" {
		Set ..ProviderConfig = config.%ToJSON()
		Set ..Model = model
	}
	Set ..Attached = ""
	Set ..McpClass = ""
	Set ..SkillsWarned = 0
	Kill ..McpOf, ..McpReported, ..McpRest
	Set ..Building = 1
	Try {
		Set sc = ..OnInit()
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Set ..Building = 0
	If $$$ISERR(sc) {
		Set ..Agent = ""
		Quit sc
	}
	Do ..ClearSampling(..Agent)
	Quit $$$OK
}

/// AI Hub's hook after the agent is initialized: adds the gate (OcuTalon.Bridge.Policy.Gate) as the authorization policy and the step audit
/// policy (OcuTalon.Bridge.Policy.StepAudit) to the agent's tool manager (AD-6, AD-9, AD-10). AI Hub chains the policies that code adds after
/// those that settings name: every authorization policy must allow a call, and every audit policy is called. The status is the first error.
Method OnAfterAgentInit(ByRef agent As %AI.Agent) As %Status [ Private ]
{
	Set sc = ##super(.agent)
	If $$$ISERR(sc) Quit sc
	Set sc = ..Govern(agent.ToolManager)
	If $$$ISERR(sc) Quit sc
	Quit ..AttachServers(agent)
}

/// Attaches the MCP servers of the McpServersClass setting of Decide (AD-6, AD-21, AD-31) to a manager that serves the reports only, never to the agent's
/// tool manager (Story 22.9), after the gate is set and the agent's own tools are on it, and reports each attach to the class. A class that is missing or does not extend OcuTalon.Bridge.Ext.McpServers fails
/// the build with that error. Each server then goes through AttachOne as mcp:remote:@{config:<config>}, in the order Servers gave, and gets one report
/// (ReportAttach, OnAttach); a server that cannot be attached, and an error from Servers or OnAttach, are logged or reported and never fail the build.
/// A config name that is not AI.MCP. followed by letters, digits and underscores is reported invalid and never attached. A tool of a server that has
/// the name of a tool already on the manager (the agent's own tools), or the name of the host's proxy (Policy.Gate MCPPROXY, when ProxyToolSet names one), never runs: it is
/// listed as refused and not as attached.
/// AI Hub's status text for an unreachable server names the URL and, for an entry with a credential, can hold the credential's value, so the text is
/// read only to choose the reason word and is never logged, stored or put in a report.
Method AttachServers(agent As %AI.Agent) As %Status [ Private ]
{
	Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("McpServersClass", "", "Decide", .sc)
	If $$$ISERR(sc) Quit sc
	Try {
		Set sc = $ClassMethod(class, "Servers", .servers)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) || '$IsObject($Get(servers)) || ('servers.%IsA("%Library.DynamicArray")) {
		$$$LOGWARNING("The MCP servers class "_class_" gave no list of servers, so none is attached: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Quit $$$OK
	}
	If servers.%Size() = 0 Quit $$$OK
	Set ..McpClass = class
	Set builtin = ..WithProxyName(..ToolNames(agent.ToolManager), class)
	Set reporter = ##class(%AI.ToolMgr).%New()
	Set iterator = servers.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set server = $Select($IsObject(entry): entry.%Get("server"), 1: "")
		Set config = $Select($IsObject(entry): entry.%Get("config"), 1: "")
		Try {
			Set report = ..AttachOne(server, config, builtin, reporter)
		} Catch exception {
			Set report = {"status": "unavailable", "reason": "failed", "tools": [], "refused": []}
		}
		Do ..ReportAttach(class, server, report)
	}
	Quit $$$OK
}

/// The report of attaching one server: {"status", "reason", "tools", "refused"} and, for an attached server, "fingerprints" (OcuTalon.Bridge.Ext.McpServers).
/// builtin is the list of the names of the tools on the agent's manager and the proxy's name (WithProxyName). A config that does not match is invalid. Otherwise the server is probed (Answers): a
/// server that does not answer is unavailable with the reason of the probe, one warning that names the server, and no AddTool. The server that answers is added
/// to reporter, the manager that serves the reports only (a failure gives ReasonOf), recorded (Record) and reported by ReportOf.
Method AttachOne(server As %String, config As %String, builtin As %List, reporter As %AI.ToolMgr) As %DynamicObject [ Private ]
{
	Set report = {"status": "unavailable", "reason": "", "tools": [], "refused": []}
	If '$Match(config, "^AI\.MCP\.[A-Za-z0-9_]+$") {
		Set report.reason = "invalid"
		Quit report
	}
	Set spec = "mcp:remote:@{config:"_config_"}"
	Set reason = ..Answers(server, config)
	If reason '= "" {
		$$$LOGWARNING("The MCP server "_$Extract(server, 1, 64)_" is not available ("_reason_"), so its tools are not attached to the agent")
		Set report.reason = reason
		Quit report
	}
	Set sc = reporter.AddTool(spec)
	If $$$ISERR(sc) {
		Set report.reason = ..ReasonOf(sc, config)
		Quit report
	}
	Do ..Record(spec, server, config)
	Set report = ..ReportOf(reporter, spec, builtin)
	Set ..McpReported(spec) = report.status
	Quit report
}

/// The report of the server whose spec the manager holds: the manager's tools whose tool_ref is the spec. A name in builtin goes to refused (AI Hub shadows an MCP
/// tool with the name of a tool already on a manager, so that it never runs); otherwise a tool whose status is available (or empty) goes to tools, with its
/// fingerprint: Context ToolFingerprint of the spec (the toolref under which AI Hub lists the tool, which the turn's map uses as the server too), the tool's name,
/// and the description and the input schema that AI Hub lists for it. A listing that fails gives unavailable with the reason failed. Used by the build and by the
/// request that finds a server again.
Method ReportOf(manager As %AI.ToolMgr, spec As %String, builtin As %List) As %DynamicObject [ Private ]
{
	Set report = {"status": "unavailable", "reason": "", "tools": [], "refused": []}
	Set fingerprints = {}
	Try {
		Set iterator = manager.GetToolStatuses().%GetIterator()
		While iterator.%GetNext(, .tool) {
			If tool.%Get("tool_ref") '= spec Continue
			Set name = tool.%Get("name")
			Set state = tool.%Get("status")
			If $ListFind(builtin, name) {
				Do report.refused.%Push(name)
			} ElseIf (state = "") || (state = "available") {
				Do report.tools.%Push(name)
				Do fingerprints.%Set(name, ##class(OcuTalon.Bridge.Context).ToolFingerprint(spec, name, tool.%Get("description"), tool.%Get("parameters")), "string")
			}
		}
		Set report.fingerprints = fingerprints
		Set report.status = "attached"
	} Catch {
		Set report = {"status": "unavailable", "reason": "failed", "tools": [], "refused": []}
	}
	Quit report
}

/// What the McpServersClass Probe says about the server: "" when it answers, else one word of McpServers REASONS. An exception, and an answer that is neither "" nor
/// such a word, give failed. The class is the one AttachServers resolved.
Method Answers(server As %String, config As %String) As %String [ Private ]
{
	Set answer = "failed"
	Try {
		Set result = $ClassMethod(..McpClass, "Probe", server, config)
		If (result = "") || $ListFind($ListFromString(##class(OcuTalon.Bridge.Ext.McpServers).#REASONS), result) Set answer = result
	} Catch {
		Set answer = "failed"
	}
	Quit answer
}

/// Records the spec of an MCP server that answered and was added, with its server and config, so that every composed manager adds it again (OfferServers).
Method Record(spec As %String, server As %String, config As %String) [ Private ]
{
	Set ..Attached = ..Attached _ $ListBuild(spec)
	Set ..McpOf(spec) = $ListBuild(server, config)
}

/// The reason word for the failed attach of status sc: unreachable when AI Hub could not connect or complete the handshake, failed for anything else
/// (an entry that does not exist, a refusal). The status text is read here and goes nowhere else; the config name in it is ignored, so a name that holds a
/// word of the test below does not change the reason.
ClassMethod ReasonOf(sc As %Status, config As %String) As %String [ Private ]
{
	Set text = $Replace($SYSTEM.Status.GetErrorText(sc), config, "")
	If (text [ "handshake failed") || (text [ "error sending request") || (text [ "onnect") || (text [ "timed out") Quit "unreachable"
	Quit "failed"
}

/// The names of the tools that the manager lists, as a list.
ClassMethod ToolNames(manager As %AI.ToolMgr) As %List [ Private ]
{
	Set names = ""
	Try {
		Set iterator = manager.%Discover().%GetIterator()
		While iterator.%GetNext(, .tool) {
			Set names = names _ $ListBuild(tool.%Get("name"))
		}
	} Catch {
		Set names = ""
	}
	Quit names
}

/// The list of names with the name of the governed proxy (Policy.Gate MCPPROXY) added when the McpServersClass names a proxy toolset (a non-empty ProxyToolSet; the bridge
/// alone names none), so that a server's tool of that name counts as a built-in name. A class that cannot be asked leaves the list as it is.
ClassMethod WithProxyName(names As %List, class As %String) As %List [ Private ]
{
	Try {
		If $ClassMethod(class, "ProxyToolSet") '= "" Set names = names _ $ListBuild(##class(OcuTalon.Bridge.Policy.Gate).#MCPPROXY)
	} Catch {
		Set names = names
	}
	Quit names
}

/// Gives the report of one server to OnAttach of the class. An error status or an exception from the class is one warning, never a failed build.
Method ReportAttach(class As %String, server As %String, report As %DynamicObject) [ Private ]
{
	Try {
		Set sc = $ClassMethod(class, "OnAttach", server, report)
		If $$$ISERR(sc) {
			$$$LOGWARNING("The MCP servers class "_class_" did not take the report for the server "_server_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		}
	} Catch exception {
		$$$LOGWARNING("The MCP servers class "_class_" threw on the report for the server "_server_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
}

/// Adds the tool of the spec (an AI Hub tool URI or JSON configuration) to the tool manager of the agent and records the spec, so that the manager of a
/// request that takes tools of its own adds the tool again. It is the one way OnAfterAgentInit adds a tool of its own to the agent's manager, and never for an
/// MCP server: the agent's own manager holds none (AttachOne, Record).
Method Attach(agent As %AI.Agent, spec As %String) As %Status
{
	Set sc = agent.ToolManager.AddTool(spec)
	If $$$ISOK(sc) Set ..Attached = ..Attached _ $ListBuild(spec)
	Quit sc
}

/// Sets the gate as the authorization policy and the step audit policy on the tool manager (AD-6, AD-9, AD-10): every manager that serves a request is
/// governed, the agent's own and the one composed for a request alike. The status is the first error.
Method Govern(manager As %AI.ToolMgr) As %Status [ Private ]
{
	Set sc = manager.SetAuthPolicy(##class(OcuTalon.Bridge.Policy.Gate).%New())
	If $$$ISERR(sc) Quit sc
	Quit manager.SetAuditPolicy(##class(OcuTalon.Bridge.Policy.StepAudit).%New())
}

/// Clears the sampling parameters of an agent that AI Hub would copy into a session config: its Temperature.
ClassMethod ClearSampling(agent As %AI.Agent)
{
	Set agent.Temperature = ""
}

/// Composes a new session config (AD-7) from the agent's MaxIterations, the model and the effort, and fails when the model is
/// empty or no ModelFamily row matches it. The family is the row with the longest ModelPrefix that the model starts with.
///   - CAP goes to the family's CapKey, a dotted path such as max_tokens or extra_params.max_completion_tokens;
///   - the effort goes to the family's EffortKey when both are not empty;
///   - max_iterations is set when the agent has one;
///   - the cache block is always set;
///   - timeout_ms is set last, when timeoutMs is not empty (Timeouts.Derive gives it from the bridge timer).
/// No sampling parameter is ever set.
ClassMethod Compose(maxIterations As %Integer, model As %String, effort As %String, Output config As %DynamicObject, timeoutMs As %Integer = "") As %Status
{
	Set config = ""
	If model = "" Quit $$$ERROR($$$GeneralError, "No model resolves for this runner, so no request is sent: set the Model setting of the item or give the agent class a MODEL")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ModelPrefix, CapKey, EffortKey FROM OcuTalon_Bridge_Data.ModelFamily")
	If result.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "The ModelFamily table cannot be read: "_result.%Message)
	Set found = 0
	Set best = -1
	While result.%Next() {
		Set prefix = result.%Get("ModelPrefix")
		If $Extract(model, 1, $Length(prefix)) '= prefix Continue
		If $Length(prefix) > best {
			Set best = $Length(prefix)
			Set capKey = result.%Get("CapKey")
			Set effortKey = result.%Get("EffortKey")
			Set found = 1
		}
	}
	If 'found Quit $$$ERROR($$$GeneralError, "No ModelFamily row matches the model '"_model_"', so no request is sent")
	If capKey = "" Quit $$$ERROR($$$GeneralError, "The ModelFamily row of the model '"_model_"' has no CapKey, so no request is sent")
	Set config = {}
	Do ..SetPath(config, capKey, ..#CAP, "number")
	If (effort '= "") && (effortKey '= "") Do ..SetPath(config, effortKey, effort, "string")
	If maxIterations '= "" Do config.%Set("max_iterations", +maxIterations, "number")
	Do config.%Set("cache", {"enabled": 1, "cache_system_prompt": 1, "cache_tool_definitions": 1, "min_tokens_for_cache": 512})
	If timeoutMs '= "" Do config.%Set("timeout_ms", +timeoutMs, "number")
	Quit $$$OK
}

/// Sets the value at a dotted path of the object, making the objects on the way.
ClassMethod SetPath(target As %DynamicObject, path As %String, value, type As %String) [ Private ]
{
	Set count = $Length(path, ".")
	For i = 1:1:count - 1 {
		Set key = $Piece(path, ".", i)
		If target.%GetTypeOf(key) '= "object" Do target.%Set(key, {})
		Set target = target.%Get(key)
	}
	Do target.%Set($Piece(path, ".", count), value, type)
}

/// The session config for the built agent: Compose for its MaxIterations, its model, the Effort setting and the timeout_ms of the
/// bridge timer (TimeoutMs), which is that of the retry runner's timer while a request with RetryOf is served. The agent is built.
Method SessionConfigFor(Output config As %DynamicObject) As %Status
{
	Set sc = ..Compose(..Agent.MaxIterations, ..Agent.Model, ..Effort, .config, ..TimeoutMs(..Retrying))
	If $$$ISERR(sc) Quit sc
	Quit ..ComposeTurnTools()
}

/// Gives the request that Answer serves the tools of its own, once (see the class description): asks the class of the TurnToolsClass setting for the
/// tools of the OwnerRef and, when it gives any or an MCP server is attached, assigns a newly composed tool manager to the agent. Nothing for a request that Answer does not serve
/// (a replay) and for the second and later session configs of a request, which return the status of the first. The agent is built.
Method ComposeTurnTools() As %Status [ Private ]
{
	If '..TurnOpen Quit $$$OK
	If ..TurnComposed Quit ..TurnStatus
	Set ..TurnComposed = 1
	Try {
		Set ..TurnStatus = ..BuildTurnManager()
	} Catch exception {
		Set ..TurnStatus = ##class(%AI.System).HandleError(exception, 1)
	}
	If $$$ISOK(..TurnStatus) && ..HasMcp() Do ..MapMcpTools()
	Quit ..TurnStatus
}

/// 1 when OnAfterAgentInit attached an MCP server (a recorded spec that starts mcp:).
Method HasMcp() As %Boolean [ Private ]
{
	Set found = 0
	Set position = 0
	While 'found && $ListNext(..Attached, position, spec) {
		If $Extract(spec, 1, 4) = "mcp:" Set found = 1
	}
	Quit found
}

/// The turn's MCP map (see the class description): lists the tool manager that serves the request, hands the list to Context SetMcpTools, and asks
/// ClassifyMcp of the ClassificationClass setting once for each MCP tool that the manager lists, with the fingerprint that the map holds for it (none for a tool the map left out). It never throws and never changes the status of the request.
Method MapMcpTools() [ Private ]
{
	Try {
		Set catalog = ..Agent.ToolManager.%Discover()
	} Catch {
		$$$LOGWARNING("The tools of the MCP servers could not be listed for this request, so every MCP tool counts as unclassified in it")
		Return
	}
	Set servers = {}
	Set position = 0
	While $ListNext(..Attached, position, spec) {
		If $Extract(spec, 1, 4) '= "mcp:" Continue
		Set host = $ListGet($Get(..McpOf(spec)), 1)
		If host '= "" Do servers.%Set(host, spec, "string")
	}
	Set sc = ##class(OcuTalon.Bridge.Context).SetMcpTools(catalog, servers)
	If $$$ISERR(sc) {
		$$$LOGWARNING("The MCP map of this request could not be kept, so every MCP tool counts as unclassified in it: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Return
	}
	Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("ClassificationClass", "", "Decide", .sc)
	If $$$ISERR(sc) {
		$$$LOGWARNING("The ClassificationClass setting is not usable, so the MCP tools of this request were not checked for a change: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Return
	}
	Set iterator = catalog.%GetIterator()
	While iterator.%GetNext(, .tool) {
		If '$IsObject(tool) || (tool.%GetTypeOf("tool_ref") '= "string") || (tool.%GetTypeOf("name") '= "string") Continue
		Set server = tool.%Get("tool_ref")
		Set name = tool.%Get("name")
		If $ZConvert($Extract(server, 1, 4), "L") '= "mcp:" Continue
		Try {
			Do $ClassMethod(class, "ClassifyMcp", server, name, ##class(OcuTalon.Bridge.Context).McpFingerprint(server, name))
		} Catch exception {
			$$$LOGWARNING("The check of the MCP tool "_##class(OcuTalon.Bridge.Redact).Text($Extract(name, 1, 64))_" for a change failed: "_##class(OcuTalon.Bridge.Redact).Text($Extract(exception.DisplayString(), 1, 300)))
		}
	}
}

/// The work of ComposeTurnTools; an exception is its caller's to handle.
Method BuildTurnManager() As %Status [ Private ]
{
	Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("TurnToolsClass", "", "Decide", .sc)
	If $$$ISERR(sc) Quit sc
	Set sc = $ClassMethod(class, "Tools", ..TurnOwner, ..TurnKind, .tools)
	If $$$ISERR(sc) Quit sc
	Set count = $Select($IsObject($Get(tools)): tools.Count(), 1: 0)
	Set mcp = ..HasMcp()
	If (count = 0) && 'mcp Quit $$$OK
	If $IsObject(..Agent.AvailableSkills) && (..Agent.AvailableSkills.%Size() > 0) {
		If mcp && '..SkillsWarned {
			Set ..SkillsWarned = 1
			$$$LOGWARNING("The agent "_$ClassName(..Agent)_" declares skills, so the tools of its MCP servers are not offered to its requests")
		}
		If count = 0 Quit $$$OK
		Quit $$$ERROR($$$GeneralError, "The agent "_$ClassName(..Agent)_" declares skills, so a request cannot take tools of its own from "_class_": a skill keeps its tools on the agent's tool manager")
	}
	Set sc = ..ComposeManager(tools, count, mcp, .manager, .proxied)
	If $$$ISERR(sc) Quit sc
	If mcp && 'proxied {
		Set sc = ..ComposeManager(tools, count, 0, .manager, .proxied)
		If $$$ISERR(sc) Quit sc
	}
	Set sc = ..Govern(manager)
	If $$$ISERR(sc) Quit sc
	Set ..OwnTools = ..Agent.ToolManager
	Set ..TurnManager = manager
	Set ..TurnToolList = $Select(count: tools, 1: "")
	Set ..Agent.ToolManager = manager
	Quit $$$OK
}

/// A new tool manager with the tools of the request: the agent's toolsets, the tools attached when the agent was built (not the MCP servers), the tools of the class
/// and, when offer is 1, the MCP servers that answer (OfferServers). proxied is 0 when offer is 1 and a server's probe answered but the host's proxy toolset could not be
/// registered on the manager, or it was registered and no server's tools were added after it (OfferServers), which BuildTurnManager answers with a manager that offers
/// no MCP server; otherwise 1.
Method ComposeManager(tools As %ListOfObjects = "", count As %Integer, offer As %Boolean, Output manager As %AI.ToolMgr, Output proxied As %Boolean) As %Status [ Private ]
{
	Set proxied = 1
	Set sc = $$$OK
	Set manager = ##class(%AI.ToolMgr).%New()
	Set toolsets = ..Agent.ToolSets
	If toolsets = "" Set toolsets = $Parameter(..Agent, "TOOLSETS")
	For i = 1:1:$Length(toolsets, ",") {
		Set name = $ZStrip($Piece(toolsets, ",", i), "<>W")
		If name = "" Continue
		Set sc = manager.RegisterToolSet(name)
		If $$$ISERR(sc) Quit
	}
	If $$$ISERR(sc) Quit sc
	Set position = 0
	While $ListNext(..Attached, position, spec) {
		If $Extract(spec, 1, 4) = "mcp:" Continue
		Set sc = manager.AddTool(spec)
		If $$$ISERR(sc) Quit
	}
	If $$$ISERR(sc) Quit sc
	For i = 1:1:count {
		Set sc = tools.GetAt(i).AddToManager(manager)
		If $$$ISERR(sc) Quit
	}
	If $$$ISERR(sc) Quit sc
	If offer Set proxied = ..OfferServers(manager)
	Quit $$$OK
}

/// Adds the recorded MCP servers to the manager of the request, in the order they were recorded (Story 22.9). A server that is resting is skipped. For the others the
/// McpServersClass Probe is asked (Answers) and then AddTool; a server that fails either is left off with one warning that holds its name and the reason word (never the
/// url or AI Hub's text), rests for RESTSECONDS, and is reported unavailable unless this job's last report for it already says so. A server that is offered again and
/// whose last report here said unavailable is reported attached (ReportOf). Before the tools of the first server whose probe answered are added, the host's governed proxy toolset
/// (the McpServersClass ProxyToolSet, Story 22.3; none for the bridge alone) is registered on the manager, once, so that a server's tool named like the proxy cannot take
/// the name (the names of builtin hold the proxy's name too, WithProxyName, so that tool is reported refused). It gives 0, which BuildTurnManager answers with a manager that
/// holds no MCP server because the manager cannot give a tool up, when that registration fails (one warning that holds a reason word and no AI Hub text) and when it succeeded
/// but no server's tools were added after it, so that a request that offers no MCP tool offers no proxy; otherwise 1. It never throws and never fails the request.
Method OfferServers(manager As %AI.ToolMgr) As %Boolean [ Private ]
{
	Set builtin = ..WithProxyName(..ToolNames(manager), ..McpClass)
	Set proxied = 1
	Set registered = 0
	Set added = 0
	Set position = 0
	While $ListNext(..Attached, position, spec) {
		If $Extract(spec, 1, 4) '= "mcp:" Continue
		If $ZHorolog < +$Get(..McpRest(spec)) Continue
		Set server = $ListGet($Get(..McpOf(spec)), 1)
		Set config = $ListGet($Get(..McpOf(spec)), 2)
		Set reason = ""
		Try {
			Set reason = ..Answers(server, config)
			If reason = "" {
				If 'registered {
					Set registered = 1
					Set proxied = ..OfferProxy(manager)
				}
				If proxied {
					Set sc = manager.AddTool(spec)
					If $$$ISERR(sc) Set reason = ..ReasonOf(sc, config)
				}
			}
		} Catch {
			Set reason = "failed"
		}
		If 'proxied Quit
		If reason '= "" {
			$$$LOGWARNING("The MCP server "_$Extract(server, 1, 64)_" is not available ("_reason_"), so its tools are not offered to this request")
			Set ..McpRest(spec) = $ZHorolog + ..#RESTSECONDS
			If $Get(..McpReported(spec)) '= "unavailable" {
				Set ..McpReported(spec) = "unavailable"
				Do ..ReportAttach(..McpClass, server, {"status": "unavailable", "reason": (reason), "tools": [], "refused": []})
			}
			Continue
		}
		Set added = added + 1
		If $Get(..McpReported(spec)) = "unavailable" {
			Set report = ..ReportOf(manager, spec, builtin)
			Set ..McpReported(spec) = report.status
			Do ..ReportAttach(..McpClass, server, report)
		}
	}
	If registered && 'added Quit 0
	Quit proxied
}

/// Registers the host's governed proxy toolset (McpServersClass ProxyToolSet) on the manager of a request that holds an MCP server. 1 when it is registered and when the
/// host has none (the bridge alone); 0 when the host's class cannot be asked or the toolset cannot be registered. A failure is one warning that holds the class name and no
/// AI Hub text.
Method OfferProxy(manager As %AI.ToolMgr) As %Boolean [ Private ]
{
	Set ok = 1
	Try {
		Set proxy = $ClassMethod(..McpClass, "ProxyToolSet")
		If proxy '= "" {
			Set sc = manager.RegisterToolSet(proxy)
			If $$$ISERR(sc) {
				Set ok = 0
				$$$LOGWARNING("The proxy toolset "_$Extract(proxy, 1, 128)_" of the MCP servers could not be registered on the tools of this request")
			}
		}
	} Catch {
		Set ok = 0
		$$$LOGWARNING("The MCP servers class could not name its proxy toolset, so the tools of its MCP servers are not offered to this request")
	}
	Quit ok
}

/// Builds a new tool manager that holds only the host's proxy toolset (McpServersClass ProxyToolSet), governed as every manager of a request is (Govern): the manager of a source poll
/// (Story 22.11; AD-6, AD-10, AD-21) and the one that ProxyManager swaps in. It needs no agent, no model key and no AI session, and it changes nothing of the adapter: the caller owns the
/// manager and lets go of it. manager is the new manager, or "" with an error status when the host has no proxy toolset (the bridge alone, and the online demo) or the toolset cannot be registered.
Method PollManager(Output manager As %AI.ToolMgr) As %Status
{
	Set manager = ""
	Set proxy = ""
	Try {
		Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("McpServersClass", "", "Decide", .sc)
		If $$$ISOK(sc) Set proxy = $ClassMethod(class, "ProxyToolSet")
	} Catch {
		Set proxy = ""
	}
	If proxy = "" Quit $$$ERROR($$$GeneralError, "The MCP servers class names no proxy toolset, so an MCP call cannot be made")
	Set new = ##class(%AI.ToolMgr).%New()
	Set sc = new.RegisterToolSet(proxy)
	If $$$ISOK(sc) Set sc = ..Govern(new)
	If $$$ISERR(sc) Quit sc
	Set manager = new
	Quit $$$OK
}

/// Swaps in, as the tool manager of the agent, the manager that PollManager builds (the host's proxy toolset only, governed), for the replay of an approved MCP call (Story 22.4); the
/// agent's own manager is kept in OwnTools until RestoreTools. manager is the new manager. The status is an error, and nothing is swapped, when PollManager fails (the host has no proxy
/// toolset: the bridge alone, and the online demo; or the toolset cannot be registered) or the agent is not built.
Method ProxyManager(Output manager As %AI.ToolMgr) As %Status
{
	Set sc = ..PollManager(.new)
	If $$$ISERR(sc) {
		Set manager = ""
		Quit sc
	}
	If '$IsObject(..Agent) {
		Set manager = ""
		Quit $$$ERROR($$$GeneralError, "The agent is not built, so an MCP call cannot be replayed")
	}
	If '$IsObject(..OwnTools) Set ..OwnTools = ..Agent.ToolManager
	Set ..Agent.ToolManager = new
	Set manager = new
	Quit $$$OK
}

/// Puts the agent's own tool manager back after ProxyManager or BuildTurnManager swapped another in, and lets go of the own manager held for it. It does nothing when none was
/// swapped in, and it never throws.
Method RestoreTools()
{
	Try {
		If $IsObject(..OwnTools) && $IsObject(..Agent) Set ..Agent.ToolManager = ..OwnTools
	} Catch {
	}
	Set ..OwnTools = ""
}

/// Ends the tools of the request on every path: puts the agent's own tool manager back (RestoreTools), lets go of the manager of the request and of its tools, and
/// forgets the request's OwnerRef and kind.
Method EndTurnTools() [ Private ]
{
	Do ..RestoreTools()
	Set ..TurnManager = ""
	Set ..TurnToolList = ""
	Set ..TurnOpen = 0
	Set ..TurnOwner = ""
	Set ..TurnKind = ""
	Set ..TurnComposed = 0
	Set ..TurnStatus = $$$OK
}

/// The timeout_ms that Timeouts.Derive gives for the TimerSeconds setting of the Decide item of the active production, as Ext.Accessor
/// ValueFor reads it now, or "" when the setting cannot be read or Timeouts.Check refuses it: the config then carries no timeout_ms.
/// Decide checks its own TimerSeconds (CheckSettings), which it takes when it starts: once it runs with such a value it refuses every
/// request. Timeouts.Apply restarts it with every change, and a row written another way reaches the runners' sessions at once and
/// Decide at its next start. With retry 1 (a request with RetryOf) the timer is Timeouts.RetryTimer of the setting, the timer that the
/// entry of the retry runner derives from (DW-647).
ClassMethod TimeoutMs(retry As %Boolean = 0) As %String
{
	Set timer = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("TimerSeconds", "", "Decide", .sc)
	If $$$ISERR(sc) Quit ""
	If retry Set timer = ##class(OcuTalon.Bridge.Timeouts).RetryTimer(timer)
	Quit ##class(OcuTalon.Bridge.Timeouts).Derive(timer).%Get("timeout_ms")
}

/// Creates an AI session with a newly composed config. The agent is built.
Method NewSession(Output session As %AI.Agent.Session) As %Status
{
	Set session = ""
	Set sc = ..SessionConfigFor(.config)
	If $$$ISERR(sc) Quit sc
	Try {
		Set session = ..Agent.CreateSession(config)
	} Catch exception {
		Set sc = ##class(%AI.System).HandleError(exception, 1)
	}
	Quit sc
}

/// Opens the saved AI session with the id on the runner as it is now (AD-7), with a newly composed config and the agent's model and system
/// prompt, because AI Hub resumes a session with the ones it was saved with and takes neither from the config: the model is set before AI
/// Hub attaches the session (the agent's ResumeSession builds it with the model that it holds), and the system prompt after (the attach
/// restores the prompt of the saved history). The agent is built. AI Hub ignores the config of a session that is already attached to the
/// agent, and %OpenId returns the session object that is still open in the process, so a caller opens with an adapter whose agent has not
/// attached it and that no one else holds: Answer releases every session at the end of a request (ReleaseSession). An id that no saved
/// session has is an error status.
Method OpenSession(id As %String, Output session As %AI.Agent.Session) As %Status
{
	Set session = ""
	Set sc = ..SessionConfigFor(.config)
	If $$$ISERR(sc) Quit sc
	Try {
		Set opened = ##class(%AI.Agent.Session).%OpenId(id, , .sc)
		If '$IsObject(opened) {
			If $$$ISOK(sc) Set sc = $$$ERROR($$$GeneralError, "No saved AI session has the id '"_id_"'")
		} Else {
			Set attach = 'opened.IsAttached()
			If attach Set opened.Model = ..Agent.Model
			Set sc = ..Agent.ResumeSession(opened, config)
			If $$$ISOK(sc) && attach Set opened.SystemPrompt = ..Agent.SystemPrompt
			If $$$ISOK(sc) Set session = opened
		}
	} Catch exception {
		Set sc = ##class(%AI.System).HandleError(exception, 1)
	}
	Quit sc
}

/// Answers a request with a reply. A request with RetryOf that RetryAllowed refuses is an error status that names RetryOf, with no Chat and no
/// context. A request of kind tool is the replay of an approved tool call and is answered by Replay.Run (no model request,
/// no Chat, no conversation link; the context it sets carries the runner item and a grant), unless its Provenance is untrusted: that is the poll of a source (Story 22.11), answered by
/// Poll.Run on the manager that PollManager builds (no model request, no grant, no Decision row). Any other request whose decision Decide has already
/// recorded (Concluded) is skipped: one Info row, status OK and no reply, before the agent is built or the context is set. It refuses any kind that is not a request kind, an Input that is
/// empty once white space is removed, and a linked turn (IsLinked) with an empty OwnerRef, which names OwnerRef; builds the agent if
/// needed; sets the context with the super session before Chat; and answers in one of two ways.
///   - A turn with provenance user is linked to its conversation (AnswerLinked): the runner holds the conversation lock, opens the AI
///     session that Data.ConversationLink names, or creates one, chats in it, and saves it after a completed Chat that is not tainted. A
///     linked turn with RetryOf is the retry of another runner's attempt and takes no lock (AnswerRetried).
///   - Every other request chats in a throwaway session that is never saved or linked.
/// Both chat through Converse, which starts the step buffer (StepBuffer.Start, with BaseChars), passes the step renderer to Chat and
/// fills the reply with the text, the provider's finish_reason, the host data and taint of the context, the usage of the call
/// (RecordUsage, which also writes the Usage row), the redacted step records (Steps) and whether a tool ran (ToolsRun, from ToolsRan).
/// When Chat throws, the reply is a failure reply instead (FailureText holds the redacted error text, and ToolsRun is set as on any
/// reply) and the status is OK. On every path, an exception included, the agent's Session is cleared before the lock of a linked turn is
/// released, and the context and the step buffer end last, so that no AI session object outlives a request. Any other error comes back
/// as the status, with AI Hub's text.
Method Answer(request As OcuTalon.Bridge.Msg.Request, superSession As %String = "", Output reply As OcuTalon.Bridge.Msg.Reply) As %Status
{
	Set reply = ""
	Set kind = request.Kind
	If '$ListFind($ListFromString(##class(OcuTalon.Bridge.Msg.Enum).#REQUESTKIND), kind) {
		Quit $$$ERROR($$$GeneralError, "The request kind '"_kind_"' is not one of "_##class(OcuTalon.Bridge.Msg.Enum).#REQUESTKIND)
	}
	If (request.RetryOf '= "") && '..RetryAllowed(request.RetryOf) {
		Quit $$$ERROR($$$GeneralError, "The RetryOf '"_request.RetryOf_"' of the request does not name an item whose RetryItem setting is "_..BusinessHost.%ConfigName_", so nothing is sent")
	}
	If kind = "tool" {
		If request.Provenance = "untrusted" Quit ##class(OcuTalon.Bridge.Poll).Run($this, request, superSession, .reply)
		Quit ##class(OcuTalon.Bridge.Replay).Run($this, request, superSession, .reply)
	}
	If ..Concluded(request) {
		$$$LOGINFO(..BusinessHost.%ConfigName_" skipped the "_kind_" request of the decision "_request.DecisionRef_": Decide has already recorded that decision, so no model request was made and no tool ran.")
		Quit $$$OK
	}
	If $ZStrip(request.Input, "<>WC") = "" Quit $$$ERROR($$$GeneralError, "The request of kind "_kind_" has an empty Input, so nothing is sent")
	Set linked = ..IsLinked(request)
	If linked && (request.OwnerRef = "") Quit $$$ERROR($$$GeneralError, "The turn of the user has an empty OwnerRef, so it has no conversation to open or link, and nothing is sent")
	Set sc = ..BuildAgent()
	If $$$ISERR(sc) Quit sc
	Set ..Retrying = (request.RetryOf '= "")
	Set sc = ##class(OcuTalon.Bridge.Context).Begin(request, superSession, ..BusinessHost.%ConfigName)
	If $$$ISOK(sc) {
		Set ..TurnOwner = request.OwnerRef
		Set ..TurnKind = kind
		Set ..TurnComposed = 0
		Set ..TurnOpen = 1
		Try {
			If linked && (request.RetryOf '= "") {
				Set sc = ..AnswerRetried(request, .reply)
			} ElseIf linked {
				Set sc = ..AnswerLinked(request, .reply)
			} Else {
				Set sc = ..NewSession(.session)
				If $$$ISOK(sc) Set sc = ..Converse(request, session, ..ChatInput(request, 0), 0, .reply, .completed)
			}
		} Catch exception {
			Set reply = ""
			Set sc = ##class(%AI.System).HandleError(exception, 1)
		}
	}
	Set session = ""
	Set ..Retrying = 0
	Do ..ReleaseSession()
	Do ..EndTurnTools()
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).End()
	If $$$ISERR(sc) Set reply = ""
	Quit sc
}

/// 1 when the runner item retryOf names this runner as its retry runner: the RetryItem setting of that item (Ext.Accessor ValueFor, Host target)
/// is the config name of this item. A setting that cannot be read, an unknown item and any other value are 0. A method of its own so that a
/// test runner, whose host is not an item of the production, can say yes or no.
Method RetryAllowed(retryOf As %String) As %Boolean
{
	Set item = $ZStrip(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("RetryItem", "", retryOf, .sc), "<>WC")
	Quit $$$ISOK(sc) && (item '= "") && (item = ..BusinessHost.%ConfigName)
}

/// 1 when the request is linked to a conversation (AD-6): a turn with provenance user. Every other request runs in a throwaway AI
/// session. It is pure.
ClassMethod IsLinked(request As OcuTalon.Bridge.Msg.Request) As %Boolean
{
	Quit $IsObject(request) && (request.Kind = "turn") && (request.Provenance = "user")
}

/// The answer to a linked turn (AD-6), in these steps; the context is set and the agent is built.
///   1. The lock: Data.ConversationLink Lock of (OwnerRef, the config name of the runner item) waits LOCKSECONDS. When it is not taken,
///      the reply is Reply.NewBusy() with status OK, and nothing else happens: no Chat, no Usage row, no steps.
///   2. The session: a turn with SessionMode fresh, or one whose conversation has no link, gets NewSession. Any other turn opens the AI
///      session that the link names (OpenSession), composing the config as for a new session, with the agent's model and system prompt. A
///      failure keeps its error status. The count of the messages the opened session holds (MessagesIn) is the reply's HistoryCount.
///   2a. The compaction (Compact), for an opened session of a request with Compact 1: the session becomes the reopened fork, or a new session
///      with the seed of the fallback (the turn then runs as a fresh one); or it stays as it is. The link is not touched.
///   3. The call (Converse) with ChatInput, whose seed is sent on a fresh turn only. The reply names the session the link named when the turn
///      began (SessionFrom).
///   4. The save (SaveLinked), after a completed Chat whose context is not tainted: the session is saved and the reply names it (SessionId).
///      Nothing is saved after a Chat that threw or a tainted one. The link stays as it was in every case: Decide moves it.
///   5. On every path, an exception included, the session object is released and the agent's Session cleared (ReleaseSession), and then
///      the lock is released, so that the next request opens the session from the database and a waiting turn finds it saved.
Method AnswerLinked(request As OcuTalon.Bridge.Msg.Request, Output reply As OcuTalon.Bridge.Msg.Reply) As %Status [ Private ]
{
	Set reply = ""
	Set owner = request.OwnerRef
	Set runner = ..BusinessHost.%ConfigName
	If '##class(OcuTalon.Bridge.Data.ConversationLink).Lock(owner, runner) {
		Set reply = ##class(OcuTalon.Bridge.Msg.Reply).NewBusy()
		Quit $$$OK
	}
	Set sc = $$$OK
	Try {
		Set fresh = (request.SessionMode = "fresh")
		Set ..Expected = ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, runner)
		Set id = $Select(fresh: "", 1: ..Expected)
		Set opened = (id '= "")
		Set seed = ""
		Set outcome = ""
		Set count = ""
		If opened {
			Set sc = ..OpenSession(id, .session)
			If $$$ISOK(sc) Set count = ..MessagesIn(session)
			If $$$ISOK(sc) && request.Compact Set sc = ..Compact(request, .session, .seed, .outcome)
			If outcome = "seed" {
				Set fresh = 1
				Set opened = 0
			}
		} Else {
			Set sc = ..NewSession(.session)
		}
		If $$$ISOK(sc) {
			Set sc = ..Converse(request, session, $Select(outcome = "seed": ..ChatInput(request, 1, seed), 1: ..ChatInput(request, fresh)), opened, .reply, .completed)
			If $$$ISOK(sc) && $IsObject(reply) {
				Set reply.SessionFrom = ..Expected
				Set reply.HistoryCount = count
			}
		}
		If $$$ISOK(sc) && completed && 'reply.Tainted Do ..SaveLinked(request, session, reply)
	} Catch exception {
		Set reply = ""
		Set sc = ##class(%AI.System).HandleError(exception, 1)
	}
	Set session = ""
	Do ..ReleaseSession()
	Do ##class(OcuTalon.Bridge.Data.ConversationLink).Unlock(owner, runner)
	Quit sc
}

/// The answer to a linked turn that retries another runner's attempt (RetryOf, AD-6, AD-8); the context is set and the agent is built. It takes no
/// conversation lock, because the first runner's attempt may still hold it. The AI session is a new one that this runner never links:
///   - Converse chats with ChatInput seeded with the SeedText of the request, which Decide wrote (Process.Decide RetrySeed): the recap of the stored
///     messages that the first attempt began with for a continue turn, or the turn's own SeedText for a fresh one. This runner reads no stored history;
///   - the reply names the session that the first runner's link names (SessionFrom), read before the call;
///   - after a Chat that completed and is not tainted, and that is not late (RetryIsLate), the session is saved and the reply names it (SessionId,
///     SaveRetried); a late retry saves nothing. The link is Decide's to move.
/// The request's Compact flag is ignored: the seed is short by construction.
Method AnswerRetried(request As OcuTalon.Bridge.Msg.Request, Output reply As OcuTalon.Bridge.Msg.Reply) As %Status [ Private ]
{
	Set reply = ""
	Set sc = $$$OK
	Try {
		Set from = ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(request.OwnerRef, request.RetryOf)
		Set sc = ..NewSession(.session)
		If $$$ISOK(sc) Set sc = ..Converse(request, session, ..ChatInput(request, 1), 0, .reply, .completed)
		If $$$ISOK(sc) && $IsObject(reply) Set reply.SessionFrom = from
		If $$$ISOK(sc) && completed && 'reply.Tainted Do ..SaveRetried(request, session, reply)
	} Catch exception {
		Set reply = ""
		Set sc = ##class(%AI.System).HandleError(exception, 1)
	}
	Set session = ""
	Do ..ReleaseSession()
	Quit sc
}

/// Saves the AI session of a retried turn and names it in the reply (SessionId), so that Decide can point the link of (OwnerRef, RetryOf) at it when it
/// accepts the reply (AnswerRetried). The link is not touched here. A late retry (RetryIsLate) saves nothing, so the reply names no session and the
/// conversation stays on the session it named. A problem (the save or an exception) is one warning that names the runner item, the OwnerRef and the
/// DecisionRef, and never changes the reply.
Method SaveRetried(request As OcuTalon.Bridge.Msg.Request, session As %AI.Agent.Session, reply As OcuTalon.Bridge.Msg.Reply) [ Private ]
{
	Set sc = $$$OK
	Try {
		If '..RetryIsLate(request) {
			Set sc = session.%Save()
			If $$$ISOK(sc) Set reply.SessionId = session.%Id()
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		$$$LOGWARNING("The AI session of "_..BusinessHost.%ConfigName_" for the OwnerRef "_request.OwnerRef_" and the decision "_request.DecisionRef_" is not saved: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
}

/// 1 when the retry of the request is late (AD-8, DW-725): Decide has already recorded the decision of the request's DecisionRef (Concluded). Decide records
/// it when it concludes, and once the retry is sent it concludes before the retry's reply only when the retry's timer fires, so the user was
/// answered without this retry and its reply is dropped. An on-time retry saves and points before its reply reaches Decide, so no row exists yet.
/// Lateness is read once, before the save: a timer that Decide handles after this check moves nothing back. A retry with no DecisionRef is never late.
/// A retry that is late when the runner takes it never gets here (Answer skips it); this guards the retry whose timer fires during its Chat.
Method RetryIsLate(request As OcuTalon.Bridge.Msg.Request) As %Boolean [ Private ]
{
	Quit ..Concluded(request)
}

/// 1 when Decide has already recorded the decision of the request's DecisionRef: the Decision row of that Ref exists (AD-8, AD-20). Decide allocates the
/// Ref before it sends and writes the row only when it concludes, so a row means that the request's answer would be dropped. A request with no
/// DecisionRef is never concluded. The one source of the skip (Answer) and of the late retry (RetryIsLate).
Method Concluded(request As OcuTalon.Bridge.Msg.Request) As %Boolean [ Private ]
{
	Quit (request.DecisionRef '= "") && ##class(OcuTalon.Bridge.Data.Decision).RefIndexExists(request.DecisionRef)
}

/// The call: chats in the session with the input, passing the step renderer, and returns the reply. A request that ContentFor gives content (an untrusted
/// turn whose ContentClass answers an image) chats through ChatWithContent with the text part and the image part instead, everything else unchanged; a
/// Part error is the error status before the stats are read or any model call is made. An image is content from outside, so a call that sends one taints the turn
/// before the call (Context Tainted 1), and the reply carries it. opened is 1 for a session that was
/// opened from a link, whose stored history the first step's estimate counts (BaseChars). completed is 1 when Chat did not throw. The
/// call is counted (AD-6, AD-9, AD-20): GetStats() is read after the session is made and again after Chat, outside every callback, and
/// RecordUsage writes one Usage row from the difference, priced from Price. That happens after every Chat that returns, whether or not
/// Decide still waits for it, and after a Chat that threw when the difference holds a model request or a token; a call that threw before
/// any request writes nothing. The reply carries the same counts, the cost and the model, the step count (model requests plus tool
/// calls) and the wall time of Chat in milliseconds. A stats or price problem is logged as a warning and never changes the answer or
/// its status. A Chat that throws is answered with a failure Reply, never an error status (DW-83): FailureText holds the redacted text
/// of AI Hub's error, cut to Reply.#MAXFAILURE (StepBuffer.Part), and the reply carries the buffered steps, the usage, the host data
/// and the taint like any other; its Text and FinishReason are empty, so that Decide classifies the failure and still sends the steps
/// to Visual Trace. A warning names the runner item, the DecisionRef and the FailureText. Every reply, a failure reply included, also
/// says whether a tool ran (ToolsRan), because Decide sends a rate-limited attempt again only when no tool ran.
Method Converse(request As OcuTalon.Bridge.Msg.Request, session As %AI.Agent.Session, input As %String, opened As %Boolean, Output reply As OcuTalon.Bridge.Msg.Reply, Output completed As %Boolean) As %Status [ Private ]
{
	Set reply = ""
	Set completed = 0
	Set sc = ..ContentFor(request, input, .content)
	If $$$ISERR(sc) Quit sc
	If $IsObject(content) Do ##class(OcuTalon.Bridge.Context).Put("Tainted", 1)
	Set before = ..ReadStats(session)
	Set response = ""
	Set thrown = ""
	Set failureText = ""
	Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).Start(..BaseChars(input, $Select(opened: session, 1: "")))
	Set started = $ZHorolog
	Try {
		If $IsObject(content) {
			Set response = ..Agent.ChatWithContent(session, content, ##class(OcuTalon.Bridge.Adapter.StepRenderer).%New())
		} Else {
			Set response = ..Agent.Chat(session, input, ##class(OcuTalon.Bridge.Adapter.StepRenderer).%New())
		}
	} Catch chatException {
		Set thrown = chatException
		Set failureText = ..FailureText(chatException, request)
	}
	Set durationMs = $Number(($ZHorolog - started) * 1000, 0)
	Set after = ..ReadStats(session)
	If '$IsObject(thrown) || ##class(OcuTalon.Bridge.Data.Usage).HasSpend(before, after) {
		Set last = $Select($IsObject(response): response.Usage, 1: "")
		Set row = ..RecordUsage(request, before, after, last, ##class(OcuTalon.Bridge.Adapter.StepBuffer).Estimates())
	} Else {
		Set row = ""
	}
	Set context = ##class(OcuTalon.Bridge.Context).Current()
	Set records = ..StepRecords()
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	If $IsObject(thrown) {
		Set reply.FailureText = failureText
	} Else {
		Set reply.Text = ..ContentText(response.Content)
		Set reply.FinishReason = $Extract(..FinishReason(response.Extra), 1, 32)
	}
	Set reply.HostData = context.HostData
	Set reply.Tainted = context.Tainted
	Set reply.Steps = ..StepsJson(records)
	Set reply.ToolsRun = ..ToolsRan(before, after, records)
	Do ..CarryUsage(row, before, after, durationMs, reply)
	Set completed = '$IsObject(thrown)
	Quit $$$OK
}

/// The content that Converse sends with the text of an untrusted turn (AD-6, AD-31): the array of the text part (input) and one image part, or "" when the
/// request gets none and the call is Chat as always. Only a request of kind turn with provenance untrusted asks the ContentClass setting of Decide (read in
/// this job through Ext.Accessor) for its Part, because every such turn chats in a throwaway AI session that is never saved. A setting that is not usable
/// and an error status of Part are the error status, and no model call is made. A stream with no bytes, or no stream, is no content.
Method ContentFor(request As OcuTalon.Bridge.Msg.Request, input As %String, Output content As %DynamicArray) As %Status [ Private ]
{
	Set content = ""
	If (request.Kind '= "turn") || (request.Provenance '= "untrusted") Quit $$$OK
	Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("ContentClass", "", "Decide", .sc)
	If $$$ISERR(sc) Quit sc
	Try {
		Set sc = $ClassMethod(class, "Part", request, .mediaType, .data)
		If $$$ISOK(sc) && $IsObject($Get(data)) && (data.Size > 0) {
			Set content = ##class(%AI.LLM.ContentPart).Build(##class(%AI.LLM.ContentPart).Text(input), ##class(%AI.LLM.ContentPart).ImageData(data, $Get(mediaType)))
		}
	} Catch exception {
		Set content = ""
		Set sc = ##class(%AI.System).HandleError(exception, 1)
	}
	If $$$ISERR(sc) Set content = ""
	Quit sc
}

/// Saves the AI session of a completed, untainted linked turn and names it in the reply (SessionId), for Decide to point the link at when it accepts
/// the reply (AD-6). The link is not touched here, so a reply that Decide does not accept (late, refused, superseded) moves nothing; a session that the
/// turn opened is saved in place and is its own SessionFrom. A problem (the save or an exception) is one warning that names the runner item, the
/// OwnerRef and the DecisionRef, and never changes the reply, whose SessionId is then empty.
Method SaveLinked(request As OcuTalon.Bridge.Msg.Request, session As %AI.Agent.Session, reply As OcuTalon.Bridge.Msg.Reply) [ Private ]
{
	Try {
		Set sc = session.%Save()
		If $$$ISOK(sc) Set reply.SessionId = session.%Id()
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		$$$LOGWARNING("The AI session of "_..BusinessHost.%ConfigName_" for the OwnerRef "_request.OwnerRef_" and the decision "_request.DecisionRef_" is not saved: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
}

/// The number of messages that the opened session holds (GetContext), or "" when they cannot be read: the reply's HistoryCount.
Method MessagesIn(session As %AI.Agent.Session) As %String [ Private ]
{
	Set count = ""
	Try {
		Set count = session.GetContext().%Size()
	} Catch {
		Set count = ""
	}
	Quit count
}

/// The compaction of a conversation that continues (AD-6, AD-20), for the opened session of a request that Decide flagged. It reads the
/// history of the session (GetContext, outside every callback) and leaves one of three outcomes:
///   - "" (the session is untouched): the history holds no message older than the last user turn, and the request as it stands is within the
///     request-size limit; or the history cannot be read (one warning);
///   - "fork": the older messages were summarized (Condense), the fork passed the check and the size guard, and it was saved, the original
///     released and the fork opened again with OpenSession (a newly composed config); session is the reopened fork, and the link is not touched;
///   - "seed": any step failed (one warning that names it, CompactWarning), so session is a new AI session (NewSession) and seed is the
///     code-written summary of the stored user and assistant texts (Compaction.Seed); the caller runs the turn as a fresh one.
/// The status is an error only when the fallback's NewSession fails. Nothing here changes the reply.
Method Compact(request As OcuTalon.Bridge.Msg.Request, ByRef session As %AI.Agent.Session, Output seed As %String, Output outcome As %String) As %Status [ Private ]
{
	Set seed = ""
	Set outcome = ""
	Set context = ""
	Set fork = ""
	Set problem = ""
	Set step = "reading the stored history"
	Try {
		Set context = session.GetContext()
	} Catch exception {
		Set context = ""
		Do ..CompactWarning(request, step, $SYSTEM.Status.GetErrorText(##class(%AI.System).HandleError(exception, 1)), "the turn runs on the history as it is")
	}
	If '$IsObject(context) Quit $$$OK
	Try {
		Set limit = ..RequestTokens()
		Set input = ..ChatInput(request, 0)
		Set step = "the cut"
		Set k = ..CutOf(context, .older)
		If k = 0 {
			Set step = "the size of the request"
			If ..Over(input, session, limit) Set problem = "the stored history passes the request-size limit and holds nothing older than the last user turn to summarize"
		} Else {
			Set problem = ..Condense(request, session, k, older, input, limit, .fork, .step)
			If (problem = "") && $IsObject(fork) {
				Set problem = ..SwitchTo(request, .session, .fork, .step)
				If problem = "" Set outcome = "fork"
			}
		}
	} Catch exception {
		Set problem = $SYSTEM.Status.GetErrorText(##class(%AI.System).HandleError(exception, 1))
	}
	If problem = "" Quit $$$OK
	Set outcome = ""
	Set fork = ""
	Set session = ""
	Do ..ReleaseSession()
	Do ..CompactWarning(request, step, problem, "the conversation continues in a new AI session seeded with a summary")
	Set sc = ..NewSession(.session)
	If $$$ISOK(sc) {
		Set seed = ##class(OcuTalon.Bridge.Compaction).Seed(context)
		Set outcome = "seed"
	}
	Quit sc
}

/// The cut of the history (Compaction.Cut): k, the number of messages to keep whole, and older, the messages before them. A method of its own so
/// that a test can ask for a cut that the rule never gives.
Method CutOf(context As %DynamicArray, Output older As %DynamicArray) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Compaction).Cut(context, .older)
}

/// The request-size limit in tokens: Decide's RequestTokenLimit as Ext.Accessor ValueFor reads it now, normalized by Decide's RequestLimit, which
/// is MAXREQUESTTOKENS when the setting cannot be read.
ClassMethod RequestTokens() As %Integer [ Private ]
{
	Set text = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("RequestTokenLimit", "", "Decide", .sc)
	If $$$ISERR(sc) Set text = ""
	Quit ##class(OcuTalon.Bridge.Process.Decide).RequestLimit(text)
}

/// 1 when the first request of a call with the input in the session (BaseChars) would pass the limit, in tokens.
Method Over(input As %String, session As %AI.Agent.Session, limit As %Integer) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Adapter.StepBuffer).Tokens(..BaseChars(input, session)) > limit
}

/// The summary step of a compaction: asks the summarizer to compress the older messages (ForkAndSummarize, keeping the last k messages whole),
/// writes the Usage row of the request, and checks the fork. Returns "" with the fork when the fork passed Compaction.Check and the size
/// guard, otherwise the text of the problem, and step names the step that failed. No request is made when the summarizer's request, by
/// estimate, would pass the limit. A request that threw is a problem too, and gets its row (output 0).
Method Condense(request As OcuTalon.Bridge.Msg.Request, session As %AI.Agent.Session, k As %Integer, older As %DynamicArray, input As %String, limit As %Integer, Output fork As %AI.Agent.Session, ByRef step As %String) As %String [ Private ]
{
	Set fork = ""
	Set prompt = ##class(OcuTalon.Bridge.Compaction).Prompt()
	Set chars = $Length(prompt) + ##class(OcuTalon.Bridge.Compaction).TranscriptChars(older)
	Set step = "the size of the summarizer's request"
	If ##class(OcuTalon.Bridge.Adapter.StepBuffer).Tokens(chars) > limit Quit "the summarizer's request would pass the request-size limit"
	Set step = "the summarizer's provider"
	Set sc = ..SummarizerProvider(.provider)
	If $$$ISERR(sc) Quit "the provider cannot be built from the settings of the runner"
	Set step = "the summarizer's request"
	Set model = session.Model
	Set thrown = ""
	Try {
		Set fork = session.ForkAndSummarize(provider, "", k, prompt, 0)
	} Catch exception {
		Set fork = ""
		Set thrown = $SYSTEM.Status.GetErrorText(##class(%AI.System).HandleError(exception, 1))
	}
	Set provider = ""
	Set summary = 0
	If $IsObject(fork) {
		Try {
			Set summary = ##class(OcuTalon.Bridge.Compaction).SummaryChars(fork.GetContext())
		} Catch {
			Set summary = 0
		}
	}
	Do ..RecordCompaction(request, model, chars, summary)
	If thrown '= "" Quit thrown
	Set step = "the check of the fork"
	If '..ForkIsSafe(fork) Quit "the fork does not start with a user message, or holds a tool result before its tool call"
	Set step = "the size of the first request"
	If ..Over(input, fork, limit) Quit "the first request would still pass the request-size limit"
	Quit ""
}

/// 1 when the history of the fork passes Compaction.Check.
ClassMethod ForkIsSafe(fork As %AI.Agent.Session) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Compaction).Check(fork.GetContext())
}

/// The switch to a fork that passed (AD-20), in this order: the fork is saved, every reference to the original session is released (the caller's
/// session and the agent's), and the fork is opened again with OpenSession. The link is not touched: Decide points it at the fork when it accepts the
/// reply, and Expected keeps the value the link had when the turn began. Returns "" when all three worked, otherwise the text of the problem, with step
/// naming the one that failed; the fork that was saved stays unlinked and the purge removes it (AD-27).
Method SwitchTo(request As OcuTalon.Bridge.Msg.Request, ByRef session As %AI.Agent.Session, ByRef fork As %AI.Agent.Session, ByRef step As %String) As %String [ Private ]
{
	Set step = "saving the fork"
	Set sc = fork.%Save()
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetErrorText(sc)
	Set forkId = fork.%Id()
	Set fork = ""
	Set session = ""
	Do ..ReleaseSession()
	Set step = "opening the fork again"
	Set sc = ..OpenSession(forkId, .session)
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetErrorText(sc)
	Quit ""
}

/// The provider of the summarizer's request (AD-7, AD-8, AD-19, AD-20): AI Hub's Create with the provider settings of this runner as AI
/// Hub's own adapter expands them (EnsLib.AI.Agent.OutboundAdapter setupProviderFromSettings: ProviderConfig expanded through the
/// setting store, else the agent's PROVIDERCONFIG, which is also the agent's own provider when the runner names none; the agent's APIKEY when
/// the settings hold none; the name from ProviderName, else the settings' model_provider, else the agent's PROVIDER), changed by
/// Compaction.SummarizerSettings. The settings live in this method alone: they
/// are never logged, stored or put in a message, and an error says nothing of them. The agent is built.
Method SummarizerProvider(Output provider As %AI.Provider) As %Status [ Private ]
{
	Set provider = ""
	Set sc = $$$OK
	Try {
		If ..ProviderConfig '= "" {
			Set settings = {}.%FromJSON(##class(%AI.Utils.SettingStore).Expand(..ProviderConfig))
		} Else {
			Set configured = $Parameter(..Agent, "PROVIDERCONFIG")
			If $IsObject(configured) {
				Set settings = configured
			} ElseIf configured '= "" {
				Set settings = {}.%FromJSON(##class(%AI.Utils.SettingStore).Expand(configured))
			} Else {
				Set settings = {}
			}
		}
		Set apiKey = $Parameter(..Agent, "APIKEY")
		If 'settings.%IsDefined("api_key") && (apiKey '= "") Do settings.%Set("api_key", ##class(%AI.Utils.SettingStore).Expand(apiKey))
		Set name = ..ProviderName
		If name = "" {
			If settings.%IsDefined("model_provider") {
				Set name = settings.%Get("model_provider")
			} Else {
				Set name = $Parameter(..Agent, "PROVIDER")
			}
		}
		If name = "" {
			Set sc = $$$ERROR($$$GeneralError, "No provider is named")
		} Else {
			Set provider = ##class(%AI.Provider).Create(name, ##class(OcuTalon.Bridge.Compaction).SummarizerSettings(settings))
		}
	} Catch {
		Set provider = ""
		Set sc = $$$ERROR($$$GeneralError, "The provider cannot be built")
	}
	Quit sc
}

/// Writes the Usage row of the summarizer's request (Usage.FromEstimate; Agent compaction, Estimated 1): the input is the prompt and the
/// transcript of the summarized messages (inputChars) and the output the stored summary (outputChars, 0 when the request threw), priced at
/// the model of the session. A problem is one warning and never changes the compaction.
Method RecordCompaction(request As OcuTalon.Bridge.Msg.Request, model As %String, inputChars As %Integer, outputChars As %Integer) [ Private ]
{
	Try {
		Set sc = ##class(OcuTalon.Bridge.Data.Usage).FromEstimate(request, model, inputChars, outputChars, .row)
		If $$$ISOK(sc) Set sc = row.%Save()
		If $$$ISERR(sc) $$$LOGWARNING("The usage of the compaction request is not recorded: "_##class(OcuTalon.Bridge.Adapter.StepBuffer).Part($SYSTEM.Status.GetErrorText(sc), ##class(OcuTalon.Bridge.Msg.Reply).#MAXFAILURE))
	} Catch exception {
		$$$LOGWARNING("The usage of the compaction request is not recorded: "_##class(OcuTalon.Bridge.Adapter.StepBuffer).Part(exception.DisplayString(), ##class(OcuTalon.Bridge.Msg.Reply).#MAXFAILURE))
	}
}

/// The one warning of a compaction that did not work: the runner item, the OwnerRef, the DecisionRef, the step that failed, what the turn
/// does instead (then) and the redacted text of the problem, cut to Reply.#MAXFAILURE (StepBuffer.Part). It is never the reply's
/// FailureText or a fallback reason (AD-8).
Method CompactWarning(request As OcuTalon.Bridge.Msg.Request, step As %String, text As %String, then As %String) [ Private ]
{
	$$$LOGWARNING("The compaction of the conversation of "_..BusinessHost.%ConfigName_" for the OwnerRef "_request.OwnerRef_" and the decision "_request.DecisionRef_" failed at "_step_" ("_then_"): "_##class(OcuTalon.Bridge.Adapter.StepBuffer).Part(text, ##class(OcuTalon.Bridge.Msg.Reply).#MAXFAILURE))
}

/// Clears the agent's Session, the one reference to an AI session that the adapter holds, so that the session object is freed when the
/// caller lets go of its own, and the next request opens the session from the database. CreateSession and OpenSession set it.
Method ReleaseSession() [ Private ]
{
	Try {
		If $IsObject(..Agent) Set ..Agent.Session = ""
	} Catch {
	}
}

/// Drops the throwaway AI session of a replay (Replay.Run): ReleaseSession, for a caller outside the class.
Method ReleaseThrowaway()
{
	Do ..ReleaseSession()
}

/// What Chat gets as its input (AD-6), for every request: the non-empty parts below, in this order, joined by a blank line
/// ($Char(10, 10)).
///   - the SeedText of the request, only when seeded is 1 (the linked fresh turn: the recap that starts the new session), or the seed
///     argument when it is passed (the compaction fallback: the seed that Compaction.Seed wrote replaces the SeedText);
///   - the SystemNote of the request (code-written text, never a tool result);
///   - the Input of the request.
/// Requests that carry neither a seed nor a note send their Input as it is. It is pure.
ClassMethod ChatInput(request As OcuTalon.Bridge.Msg.Request, seeded As %Boolean = 0, seed As %String) As %String
{
	Set text = ""
	Set blank = $Char(10, 10)
	If seeded {
		Set text = $Select($Data(seed): seed, 1: request.SeedText)
	}
	If request.SystemNote '= "" Set text = text _ $Select(text = "": "", 1: blank) _ request.SystemNote
	If request.Input '= "" Set text = text _ $Select(text = "": "", 1: blank) _ request.Input
	Quit text
}

/// The size of what the first request of the call carries before any model text or tool result, in characters (the base of the step
/// estimates, AD-9): the agent's system prompt, the JSON of its tool catalog (ToolManager.%Discover(), counted as 0 when it fails),
/// the input that Chat gets (ChatInput) and, for a session that was opened from a link, the JSON of its stored history
/// (session.GetContext(), counted as 0 when it fails). Read here, before Chat and outside every callback. The agent is built.
Method BaseChars(input As %String, session As %AI.Agent.Session = "") As %Integer [ Private ]
{
	Set chars = $Length(input)
	Try {
		Set chars = chars + $Length(..Agent.SystemPrompt)
	} Catch {
	}
	Try {
		Set chars = chars + $Length(..Agent.ToolManager.%Discover().%ToJSON())
	} Catch {
	}
	If $IsObject(session) {
		Try {
			Set chars = chars + $Length(session.GetContext().%ToJSON())
		} Catch {
		}
	}
	Quit chars
}

/// The failure text of a Chat that threw: AI Hub's error text (HandleError keeps the <%AICore> code and text), redacted and cut to
/// Reply.#MAXFAILURE by StepBuffer.Part. One warning names the runner item, the DecisionRef and the text. Call it in the Catch of Chat,
/// before any other AI Hub call: HandleError reads AI Hub's last error, which the next failing call replaces.
Method FailureText(thrown As %Exception.AbstractException, request As OcuTalon.Bridge.Msg.Request) As %String [ Private ]
{
	Set text = ""
	Try {
		Set text = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Part($SYSTEM.Status.GetErrorText(##class(%AI.System).HandleError(thrown, 1)), ##class(OcuTalon.Bridge.Msg.Reply).#MAXFAILURE)
	} Catch {
		Set text = "The call failed, and AI Hub's error text cannot be read"
	}
	$$$LOGWARNING("The chat call of "_..BusinessHost.%ConfigName_" failed for the decision "_request.DecisionRef_": "_text)
	Quit text
}

/// The step records of the call (StepBuffer.Records), or "" with a warning when they cannot be read. Call it after Chat, outside every
/// callback. Replay.Run calls it too.
Method StepRecords() As %DynamicArray
{
	Set records = ""
	Try {
		Set records = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Records()
	} Catch exception {
		Set records = ""
		$$$LOGWARNING("The steps of the call are not returned: "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Quit records
}

/// The step records as a JSON array, or "" for records that could not be read (StepRecords). Replay.Run calls it too.
ClassMethod StepsJson(records As %DynamicArray) As %String
{
	Quit $Select($IsObject(records): records.%ToJSON(), 1: "")
}

/// 1 when a tool may have run in the call, otherwise 0 (DW-56). It is pure. A tool ran when:
///   - the total_tool_calls counter of the two GetStats() readings went up (Usage.Delta above 0);
///   - a step record is of kind tool (records, the step records of the call: a dynamic array, ignored when it is not one);
///   - or either reading is not an object, because an unknown counts as a tool that ran, so that Decide never sends again an attempt in
///     which a tool may have run. A call to a tool that does not exist, and one that the gate denied, count too.
ClassMethod ToolsRan(before As %DynamicObject, after As %DynamicObject, records As %DynamicArray) As %Boolean
{
	If '$IsObject($Get(before)) || '$IsObject($Get(after)) Quit 1
	If ##class(OcuTalon.Bridge.Data.Usage).Delta(before, after, "total_tool_calls") > 0 Quit 1
	If '$IsObject($Get(records)) || 'records.%IsA("%Library.DynamicArray") Quit 0
	Set ran = 0
	Set iterator = records.%GetIterator()
	While iterator.%GetNext(, .record, .type) {
		If (type = "object") && (record.%Get("kind") = "tool") Set ran = 1
	}
	Quit ran
}

/// session.GetStats(), or "" with a warning when it throws: AI Hub's counters of the session (total_interactions, total_tool_calls
/// and the token counters). The session is attached.
Method ReadStats(session As %AI.Agent.Session) As %DynamicObject [ Private ]
{
	Set stats = ""
	Try {
		Set stats = session.GetStats()
	} Catch exception {
		Set stats = ""
		$$$LOGWARNING("The usage of the call is not counted: GetStats() of the AI session failed: "_exception.DisplayString())
	}
	Quit stats
}

/// Writes the Usage row of one Chat call (Usage.FromStats from the request, the config name of the runner item, the agent's model, the
/// two readings, the usage of the last response, which is empty when Chat threw, and the estimated sizes of the model requests,
/// a list from StepBuffer.Estimates) and returns the row. A model with no Price row
/// gets a row with no cost and a warning that names the model. A problem is logged as a warning, never raised: the row is then
/// returned unsaved, or "" when none could be built.
Method RecordUsage(request As OcuTalon.Bridge.Msg.Request, before As %DynamicObject, after As %DynamicObject, last As %DynamicObject, estimates As %List = "") As OcuTalon.Bridge.Data.Usage
{
	Set row = ""
	Try {
		Set model = ..Agent.Model
		Set sc = ##class(OcuTalon.Bridge.Data.Usage).FromStats(request, ..BusinessHost.%ConfigName, model, before, after, last, .row, estimates)
		If $$$ISOK(sc) {
			Set sc = row.%Save()
			If $$$ISOK(sc) && (row.CostUSD = "") $$$LOGWARNING("The usage of the call is recorded with no cost: no Price row has the model '"_model_"'")
		}
		If $$$ISERR(sc) $$$LOGWARNING("The usage of the call is not recorded: "_$SYSTEM.Status.GetErrorText(sc))
	} Catch exception {
		$$$LOGWARNING("The usage of the call is not recorded: "_exception.DisplayString())
	}
	Quit row
}

/// Puts the usage of the call on the reply: the counts, the cost and the model of the row, the step count (the requests of the row
/// plus the tool calls between the readings) and the wall time of Chat in milliseconds. Without a row the reply carries the step
/// count and the duration only.
Method CarryUsage(row As OcuTalon.Bridge.Data.Usage, before As %DynamicObject, after As %DynamicObject, durationMs As %Integer, reply As OcuTalon.Bridge.Msg.Reply) [ Private ]
{
	If $IsObject(row) {
		Set reply.InputTokens = row.InputTokens
		Set reply.OutputTokens = row.OutputTokens
		Set reply.CacheReadTokens = row.CacheReadTokens
		Set reply.CacheWriteTokens = row.CacheWriteTokens
		Set reply.CostUSD = row.CostUSD
		Set reply.Model = row.Model
	}
	Set reply.AgentStepCount = ##class(OcuTalon.Bridge.Data.Usage).Delta(before, after, "total_interactions") + ##class(OcuTalon.Bridge.Data.Usage).Delta(before, after, "total_tool_calls")
	Set reply.DurationMs = durationMs
}

/// The text of a response's Content: the string, or a stream read whole.
ClassMethod ContentText(content) As %String [ Private ]
{
	If '$IsObject(content) Quit content
	Set text = ""
	Do content.Rewind()
	While 'content.AtEnd {
		Set text = text _ content.Read(32000)
	}
	Quit text
}

/// The finish_reason of a response's Extra, or "" when it reports none.
ClassMethod FinishReason(extra As %DynamicObject) As %String [ Private ]
{
	If '$IsObject(extra) || (extra.%GetTypeOf("finish_reason") '= "string") Quit ""
	Quit extra.%Get("finish_reason")
}

/// The tools of the live ToolManager as {"tools":[{"name","source","provider","status","reason"}]}, one entry for every tool
/// that was attempted, whatever its status. The agent is built.
Method Inventory(Output inventory As %DynamicObject) As %Status
{
	Set inventory = ""
	Set sc = ..BuildAgent()
	If $$$ISERR(sc) Quit sc
	Try {
		Set tools = []
		Set iterator = ..Agent.ToolManager.GetToolStatuses().%GetIterator()
		While iterator.%GetNext(, .tool) {
			Set entry = {}
			For field = "name", "source", "provider", "status", "reason" {
				Do entry.%Set(field, $Select(tool.%GetTypeOf(field) = "string": tool.%Get(field), 1: ""))
			}
			Do tools.%Push(entry)
		}
		Set inventory = {"tools": (tools)}
	} Catch exception {
		Set inventory = ""
		Set sc = ##class(%AI.System).HandleError(exception, 1)
	}
	Quit sc
}

}
