Include Ensemble

/// The adapter of the agent runners (AD-6, AD-7). It extends AI Hub's outbound agent adapter and changes three things.
///   - It refuses to start (OnInit) when a setting would put a policy, a tool, a skill, a system prompt or a session
///     configuration on the agent, or when its agent class is not on its allow-list. OnInit calls nothing in AI Hub, so a runner
///     item starts and keeps running with no model key (FR-38).
///   - It builds the agent on the first request that needs it (BuildAgent), by running AI Hub's own OnInit. A build that fails is
///     not kept, so the next request builds again. The built agent has no Temperature, so that AI Hub adds no temperature to a
///     session.
///   - It composes the session config in one place (Compose) and uses it for every AI session it creates (NewSession) or opens
///     (OpenSession), because a session that is resumed without its config loses the cap and the effort.
/// Answer is the runner's answer to a Request: the context is set before Chat and ended on every path, and the reply holds the
/// text, the provider's stop reason, and the host data and taint that the tools put in the context. Answer also counts the call
/// (AD-6, AD-9, AD-20): it reads the session's GetStats() after the session is created and again after Chat, outside every
/// callback, and RecordUsage writes one Usage row from the difference, priced from Price. That happens after every Chat that
/// returns, whether or not Decide still waits for it, and after a Chat that threw when the difference holds a model request or a
/// token; a call that threw before any request writes nothing. The reply carries the same counts, the cost and the model, the
/// step count (model requests plus tool calls) and the wall time of Chat in milliseconds. A stats, price or save problem is logged
/// as a warning and never changes the answer or its status. Inventory lists the tools of the live ToolManager. This class names no
/// other OcuTalon package (AD-2).
Class OcuTalon.Bridge.Adapter.Agent Extends EnsLib.AI.Agent.OutboundAdapter
{

/// The settings that the adapter adds to AI Hub's.
Parameter SETTINGS = "Effort:Basic,AgentAllowList:Basic";

/// The settings of AI Hub's adapter that must be empty, comma-separated. SessionConfigString may also hold {}.
Parameter REFUSED = "AuthPolicy,AuditPolicy,DiscoveryPolicy,IrisTools,AdditionalTools,IrisSkills,AdditionalSkills,SystemPrompt,SessionConfigString";

/// The output cap of a request, in tokens (AD-7).
Parameter CAP = 8000;

/// The effort to ask of an Anthropic model, as output_config.effort: low, medium or high. Empty sends no effort (AD-7).
Property Effort As %String(MAXLEN = 32);

/// The agent classes that this adapter may run, comma-separated, each an exact class name (AD-6). Empty refuses every class.
Property AgentAllowList As %String(MAXLEN = 2000);

/// 1 while BuildAgent runs AI Hub's OnInit.
Property Building As %Boolean [ InitialExpression = 0, Internal, Private, Transient ];

/// Checks the settings and calls nothing in AI Hub. While BuildAgent runs it, it is AI Hub's OnInit.
Method OnInit() As %Status [ Internal ]
{
	If ..Building Quit ##super()
	Quit ..CheckSettings()
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
/// fails leaves no agent, so that the next call builds again.
Method BuildAgent() As %Status
{
	If $IsObject(..Agent) Quit $$$OK
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
///   - the cache block is always set.
/// No sampling parameter is ever set.
ClassMethod Compose(maxIterations As %Integer, model As %String, effort As %String, Output config As %DynamicObject) As %Status
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

/// The session config for the built agent: Compose for its MaxIterations, its model and the Effort setting. The agent is built.
Method SessionConfigFor(Output config As %DynamicObject) As %Status
{
	Quit ..Compose(..Agent.MaxIterations, ..Agent.Model, ..Effort, .config)
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

/// Opens the saved AI session with the id, with a newly composed config. The agent is built. AI Hub ignores the config of a
/// session that is already attached to the agent, so a caller opens with an adapter whose agent has not attached it.
Method OpenSession(id As %String, Output session As %AI.Agent.Session) As %Status
{
	Set session = ""
	Set sc = ..SessionConfigFor(.config)
	If $$$ISERR(sc) Quit sc
	Try {
		Set session = ..Agent.OpenSession(id, config)
	} Catch exception {
		Set sc = ##class(%AI.System).HandleError(exception, 1)
	}
	Quit sc
}

/// Answers a request with a reply. It refuses kind tool ($$$NotImplemented), any kind that is not a request kind, and an Input
/// that is empty once white space is removed; builds the agent if needed; sets the context with the super session before Chat; chats in a throwaway session; and
/// fills the reply with the text, the provider's finish_reason, the host data and taint of the context, and the usage of the call
/// (RecordUsage, which also writes the Usage row). The context ends on every path. Errors come back as the status, with AI Hub's text.
Method Answer(request As OcuTalon.Bridge.Msg.Request, superSession As %String = "", Output reply As OcuTalon.Bridge.Msg.Reply) As %Status
{
	Set reply = ""
	Set kind = request.Kind
	If kind = "tool" Quit $$$ERROR($$$NotImplemented)
	If '$ListFind($ListFromString(##class(OcuTalon.Bridge.Msg.Enum).#REQUESTKIND), kind) {
		Quit $$$ERROR($$$GeneralError, "The request kind '"_kind_"' is not one of "_##class(OcuTalon.Bridge.Msg.Enum).#REQUESTKIND)
	}
	If $ZStrip(request.Input, "<>WC") = "" Quit $$$ERROR($$$GeneralError, "The request of kind "_kind_" has an empty Input, so nothing is sent")
	Set sc = ..BuildAgent()
	If $$$ISERR(sc) Quit sc
	Set sc = ##class(OcuTalon.Bridge.Context).Begin(request, superSession)
	If $$$ISOK(sc) {
		Try {
			Set sc = ..NewSession(.session)
			If $$$ISOK(sc) {
				Set before = ..ReadStats(session)
				Set response = ""
				Set thrown = ""
				Set started = $ZHorolog
				Try {
					Set response = ..Agent.Chat(session, request.Input)
				} Catch chatException {
					Set thrown = chatException
				}
				Set durationMs = $Number(($ZHorolog - started) * 1000, 0)
				Set after = ..ReadStats(session)
				If '$IsObject(thrown) || ##class(OcuTalon.Bridge.Data.Usage).HasSpend(before, after) {
					Set last = $Select($IsObject(response): response.Usage, 1: "")
					Set row = ..RecordUsage(request, before, after, last)
				} Else {
					Set row = ""
				}
				If $IsObject(thrown) Throw thrown
				Set context = ##class(OcuTalon.Bridge.Context).Current()
				Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
				Set reply.Text = ..ContentText(response.Content)
				Set reply.FinishReason = $Extract(..FinishReason(response.Extra), 1, 32)
				Set reply.HostData = context.HostData
				Set reply.Tainted = context.Tainted
				Do ..CarryUsage(row, before, after, durationMs, reply)
			}
		} Catch exception {
			Set reply = ""
			Set sc = ##class(%AI.System).HandleError(exception, 1)
		}
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	If $$$ISERR(sc) Set reply = ""
	Quit sc
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
/// two readings and the usage of the last response, which is empty when Chat threw) and returns the row. A model with no Price row
/// gets a row with no cost and a warning that names the model. A problem is logged as a warning, never raised: the row is then
/// returned unsaved, or "" when none could be built.
Method RecordUsage(request As OcuTalon.Bridge.Msg.Request, before As %DynamicObject, after As %DynamicObject, last As %DynamicObject) As OcuTalon.Bridge.Data.Usage
{
	Set row = ""
	Try {
		Set model = ..Agent.Model
		Set sc = ##class(OcuTalon.Bridge.Data.Usage).FromStats(request, ..BusinessHost.%ConfigName, model, before, after, last, .row)
		If $$$ISOK(sc) {
			If row.CostUSD = "" $$$LOGWARNING("The usage of the call is recorded with no cost: no Price row has the model '"_model_"'")
			Set sc = row.%Save()
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
