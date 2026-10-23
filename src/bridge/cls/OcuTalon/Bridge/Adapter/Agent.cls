Include Ensemble

/// The adapter of the agent runners (AD-6, AD-7). It extends AI Hub's outbound agent adapter and changes four things.
///   - It refuses to start (OnInit) when a setting would put a policy, a tool, a skill, a system prompt or a session
///     configuration on the agent, or when its agent class is not on its allow-list. OnInit calls nothing in AI Hub, so a runner
///     item starts and keeps running with no model key (FR-38).
///   - It builds the agent on the first request that needs it (BuildAgent), by running AI Hub's own OnInit. A build that fails is
///     not kept, so the next request builds again. The built agent has no Temperature, so that AI Hub adds no temperature to a
///     session.
///   - It composes the session config in one place (Compose) and uses it for every AI session it creates (NewSession) or opens
///     (OpenSession), because a session that is resumed without its config loses the cap and the effort. The config carries timeout_ms,
///     which Timeouts.Derive gives for the TimerSeconds setting of Decide as it stands when the config is composed (SessionConfigFor).
///   - It adds the step audit policy to every agent it builds (OnAfterAgentInit), after any policy that a setting names, and refuses
///     the AuditPolicy setting (REFUSED), so that every tool call is a step (AD-6, AD-9).
/// Answer is the runner's answer to a Request: the context is set before Chat and ended on every path, and the reply holds the
/// text, the provider's stop reason, and the host data and taint that the tools put in the context.
/// The conversation (AD-6, AD-10): only a turn with provenance user is linked (IsLinked), under the key (OwnerRef, the name of the runner
/// item). AnswerLinked holds the conversation lock (Data.ConversationLink Lock, 2 seconds) from the open or creation of the AI session
/// to its save, and answers a Reply whose Busy is 1 when it cannot take it. It opens the session that the link names with a newly
/// composed config every time, or creates and links one (and a turn with SessionMode fresh moves the link to a new session, seeded with
/// the request's SeedText). SaveLinked saves the session, and points the link at it, only after a Chat that completed and whose context
/// is not tainted; a Chat that threw, or a tainted one, saves nothing and leaves the link as it was. No AI session object outlives a
/// request: Answer clears the agent's Session (ReleaseSession) before the lock is released, so that every linked turn, a re-sent one
/// included, opens the saved history from the database. decide, diagnose and untrusted turns chat in a throwaway session that is never
/// saved or linked. ChatInput composes what Chat gets: the seed of a fresh turn, the system note and the input.
/// Converse counts the call (AD-6, AD-9, AD-20): it reads the session's GetStats() after the session is made and again after Chat,
/// outside every callback, and RecordUsage writes one Usage row from the difference, priced from Price. That happens after every Chat
/// that returns, whether or not Decide still waits for it, and after a Chat that threw when the difference holds a model request or a
/// token; a call that threw before any request writes nothing. The reply carries the same counts, the cost and the model, the step
/// count (model requests plus tool calls) and the wall time of Chat in milliseconds. A stats, price or save problem is logged as a
/// warning and never changes the answer or its status. Every reply, a failure reply included, also says whether a tool ran (ToolsRan:
/// AI Hub's tool-call counter went up between the two readings, a step record is of kind tool, or a reading could not be read), because
/// Decide sends a rate-limited attempt again only when no tool ran. Inventory lists the tools of the live ToolManager.
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

/// AI Hub's hook after the agent is initialized: adds the step audit policy (OcuTalon.Bridge.Policy.StepAudit) to the agent's tool
/// manager (AD-6, AD-9). AI Hub chains the policies that code adds after those that settings name, and calls every audit policy.
Method OnAfterAgentInit(ByRef agent As %AI.Agent) As %Status [ Private ]
{
	Set sc = ##super(.agent)
	If $$$ISERR(sc) Quit sc
	Quit agent.ToolManager.SetAuditPolicy(##class(OcuTalon.Bridge.Policy.StepAudit).%New())
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
/// bridge timer (TimeoutMs). The agent is built.
Method SessionConfigFor(Output config As %DynamicObject) As %Status
{
	Quit ..Compose(..Agent.MaxIterations, ..Agent.Model, ..Effort, .config, ..TimeoutMs())
}

/// The timeout_ms that Timeouts.Derive gives for the TimerSeconds setting of the Decide item of the active production, as Ext.Accessor
/// ValueFor reads it now, or "" when the setting cannot be read or Timeouts.Check refuses it: the config then carries no timeout_ms.
/// Decide checks its own TimerSeconds (CheckSettings), which it takes when it starts: once it runs with such a value it refuses every
/// request. Timeouts.Apply restarts it with every change, and a row written another way reaches the runners' sessions at once and
/// Decide at its next start.
ClassMethod TimeoutMs() As %String
{
	Set timer = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("TimerSeconds", "", "Decide", .sc)
	If $$$ISERR(sc) Quit ""
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

/// Opens the saved AI session with the id, with a newly composed config. The agent is built. AI Hub ignores the config of a
/// session that is already attached to the agent, and the open returns the session object that is still open in the process, so a
/// caller opens with an adapter whose agent has not attached it and that no one else holds: Answer releases every session at the end of
/// a request (ReleaseSession).
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

/// Answers a request with a reply. It refuses kind tool ($$$NotImplemented), any kind that is not a request kind, an Input that is
/// empty once white space is removed, and a linked turn (IsLinked) with an empty OwnerRef, which names OwnerRef; builds the agent if
/// needed; sets the context with the super session before Chat; and answers in one of two ways.
///   - A turn with provenance user is linked to its conversation (AnswerLinked): the runner holds the conversation lock, opens the AI
///     session that Data.ConversationLink names, or creates one, chats in it, and saves it after a completed Chat that is not tainted.
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
	If kind = "tool" Quit $$$ERROR($$$NotImplemented)
	If '$ListFind($ListFromString(##class(OcuTalon.Bridge.Msg.Enum).#REQUESTKIND), kind) {
		Quit $$$ERROR($$$GeneralError, "The request kind '"_kind_"' is not one of "_##class(OcuTalon.Bridge.Msg.Enum).#REQUESTKIND)
	}
	If $ZStrip(request.Input, "<>WC") = "" Quit $$$ERROR($$$GeneralError, "The request of kind "_kind_" has an empty Input, so nothing is sent")
	Set linked = ..IsLinked(request)
	If linked && (request.OwnerRef = "") Quit $$$ERROR($$$GeneralError, "The turn of the user has an empty OwnerRef, so it has no conversation to open or link, and nothing is sent")
	Set sc = ..BuildAgent()
	If $$$ISERR(sc) Quit sc
	Set sc = ##class(OcuTalon.Bridge.Context).Begin(request, superSession)
	If $$$ISOK(sc) {
		Try {
			If linked {
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
	Do ..ReleaseSession()
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).End()
	If $$$ISERR(sc) Set reply = ""
	Quit sc
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
///      session that the link names (OpenSession), composing the config as for a new session. A failure keeps its error status.
///   3. The call (Converse) with ChatInput, whose seed is sent on a fresh turn only.
///   4. The save (SaveLinked), after a completed Chat whose context is not tainted: the session is saved and the link points at it.
///      Nothing is saved after a Chat that threw or a tainted one, and the link stays as it was.
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
		Set id = $Select(fresh: "", 1: ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, runner))
		Set opened = (id '= "")
		If opened {
			Set sc = ..OpenSession(id, .session)
		} Else {
			Set sc = ..NewSession(.session)
		}
		If $$$ISOK(sc) Set sc = ..Converse(request, session, ..ChatInput(request, fresh), opened, .reply, .completed)
		If $$$ISOK(sc) && completed && 'reply.Tainted Do ..SaveLinked(request, session, fresh, reply)
	} Catch exception {
		Set reply = ""
		Set sc = ##class(%AI.System).HandleError(exception, 1)
	}
	Set session = ""
	Do ..ReleaseSession()
	Do ##class(OcuTalon.Bridge.Data.ConversationLink).Unlock(owner, runner)
	Quit sc
}

/// The call: chats in the session with the input, passing the step renderer, and returns the reply. opened is 1 for a session that was
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
	Set before = ..ReadStats(session)
	Set response = ""
	Set thrown = ""
	Set failureText = ""
	Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).Start(..BaseChars(input, $Select(opened: session, 1: "")))
	Set started = $ZHorolog
	Try {
		Set response = ..Agent.Chat(session, input, ##class(OcuTalon.Bridge.Adapter.StepRenderer).%New())
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

/// Saves the AI session of a completed, untainted linked turn and points the link at it (AD-6). The reply's SessionRotated is set to 1
/// when the turn was fresh and the link now names the new session, whether Point created the link or moved it; it stays 0 for a
/// continue turn. A problem (the save, the link or an exception) is one warning that names the runner item, the OwnerRef and the
/// DecisionRef, and never changes the reply, whose SessionRotated is then 0.
Method SaveLinked(request As OcuTalon.Bridge.Msg.Request, session As %AI.Agent.Session, fresh As %Boolean, reply As OcuTalon.Bridge.Msg.Reply) [ Private ]
{
	Try {
		Set sc = session.%Save()
		If $$$ISOK(sc) Set sc = ##class(OcuTalon.Bridge.Data.ConversationLink).Point(request.OwnerRef, ..BusinessHost.%ConfigName, session.%Id())
		If $$$ISOK(sc) && fresh Set reply.SessionRotated = 1
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		$$$LOGWARNING("The AI session of "_..BusinessHost.%ConfigName_" for the OwnerRef "_request.OwnerRef_" and the decision "_request.DecisionRef_" is not saved or linked: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
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

/// What Chat gets as its input (AD-6), for every request: the non-empty parts below, in this order, joined by a blank line
/// ($Char(10, 10)).
///   - the SeedText of the request, only when seeded is 1 (the linked fresh turn: the recap that starts the new session);
///   - the SystemNote of the request (code-written text, never a tool result);
///   - the Input of the request.
/// Requests that carry neither a seed nor a note send their Input as it is. It is pure.
ClassMethod ChatInput(request As OcuTalon.Bridge.Msg.Request, seeded As %Boolean = 0) As %String
{
	Set text = ""
	Set blank = $Char(10, 10)
	If seeded && (request.SeedText '= "") Set text = request.SeedText
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
/// callback.
Method StepRecords() As %DynamicArray [ Private ]
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

/// The step records as a JSON array, or "" for records that could not be read (StepRecords).
ClassMethod StepsJson(records As %DynamicArray) As %String [ Private ]
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
