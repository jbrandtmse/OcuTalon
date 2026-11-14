Include Ensemble

/// Decide, the business process that every model use passes through (AD-6, AD-30).
///   - A Request is admitted (Admit): a message of another class gets "not implemented", and a kind, provenance, ItemId, OwnerRef or
///     Input that is missing or unknown gets an error that names the field, before anything is sent. A request of kind tool is the replay
///     of an approved tool call (Approval.HoldResponse sends it): its provenance is user, its ItemId the Ref of the approval request, and it
///     has no Input. It goes to the runner that the approval row names (RunnerFor), with no ReplyClass, no Held probe and no Precheck, because
///     the runner makes no model request for it. The reply of the runner is Conclude's: no FailureText records the outcome act with no
///     reasons, and a FailureText records a fallback with the reason error (none while the approval row is still approved: the run never started). The runner is never sent a tool request again for an item that
///     has a Decision row (below), and a row that names no runner or no source is answered with a fallback (FailUnroutable); the fallback Decision row
///     of an approved row that was closed failed for that reason carries the plain-English reason HELDBEFOREUPDATE as its Reasons.
///   - One decision per item (AD-6): a decide, diagnose or tool request for an item that has a Decision row is answered from the
///     row, and a turn for an item that has one is refused, because the row keeps no reply text.
///   - Otherwise Decide checks its settings (CheckSettings), allocates the DecisionRef, keeps it in the stored property DecisionRef and
///     prechecks the request (Precheck, AD-8, AD-20): no model key (Keys.Absent), the daily cost cap reached (Budget.State), an
///     estimate over DecisionTokenBudget or an estimate over the request-size limit (RequestTokenLimit). A request that fails a precheck
///     is never sent: RecordFallback records it as a fallback decision and the answer is given from OnRequest, with no runner request and
///     no timer. Otherwise Decide sends the request that SentRequest builds, a clone that carries the DecisionRef, to the runner of the
///     kind (RUNNERS) and sets the timer of TimerSeconds (TimerFor), a whole number of seconds from MINTIMER to MAXTIMER (Timeouts.Check, AD-5).
///     A flagged turn that continues its conversation (below) gets Compaction.#SUMMARIZERSECONDS more, so that the runner's compaction has its
///     time (AD-20), and never more than MAXTIMER. RemainingMs and the re-send count from TimerFor of the request as it stands when they weigh
///     it: after a compaction the stored history is short, so a re-send is no longer flagged and counts from TimerSeconds.
///     Besides the runner requests, the timers and the agent steps (below), Decide sends nothing; it answers only its caller.
///   - The estimate and the size limit (AD-8, AD-20, NFR-3): EstimateTokens works out the first model request of the runner of the request
///     in tokens, at StepBuffer.CHARSPERTOKEN characters a token. It adds the system prompt and the tool schemas of the runner's agent
///     class (RequestSize.AgentChars), the stored history of a linked turn that continues its conversation (RequestSize.HistoryChars of the
///     session that the link names, Data.ConversationLink SessionOf) and the input that the runner sends (Adapter.Agent ChatInput). The
///     limit is the RequestTokenLimit setting, a whole number from 1 to MAXREQUESTTOKENS (RequestLimit); an empty value counts as
///     MAXREQUESTTOKENS, and so does any other value, with one warning, so that the limit is never off and never above MAXREQUESTTOKENS. A
///     request whose estimate is above the limit takes the fallback reason too_large, after budget, for every kind and on every re-send,
///     except a turn that is flagged (below) and continues its conversation: the runner compacts such a turn, or starts a fresh session
///     with a seed of at most Compaction.#SEEDCHARS characters in place of the history, so it is judged on the request of the seeded path,
///     the estimate with the history counted as the least of itself and Compaction.#SEEDCHARS (Precheck); the runner itself checks the
///     session as it stands and the fork against the limit and seeds in their place when they pass it. The second-model retry of such a turn
///     is estimated on the clone that carries its seed (below).
///   - The flag (AD-6, AD-20): SentRequest sets Request.Compact to 1 on the clone of a turn whose estimate is above COMPACTTOKENS, and to 0
///     on every other request, whatever the caller set. The runner compacts a flagged turn that continues its conversation before
///     it chats (Adapter.Agent, Story 30.1); every other flagged turn is sent as it is.
///   - The steps (AD-9, AD-30): when the runner's reply arrives in time, and before anything reads it, EmitSteps sends each step record of
///     the reply's Steps to the AgentSteps operation (STEPSITEM) as an OcuTalon.Bridge.Msg.AgentStep, in order, so that the steps sit in
///     the caller's trace session after the runner's reply and before Decide's answer (StepMessages builds the messages). The Positions
///     of a decision run on across its attempts: they start at StepsSent + 1. The reply of a call whose Chat threw carries its steps
///     like any other. A Steps value that does not parse and a send that fails are warnings that name the DecisionRef and never change
///     the answer. An answer from a recorded row, a precheck fallback, a timer that fired and a late reply send no steps. Decide's
///     answer to a turn leaves Steps empty.
///   - The classification (AD-8): Classify picks the one FallbackReason, or "" for a usable reply, from the facts of a request, in AD-8's
///     order: the prechecks (no_key, daily_cap, budget, too_large), a timer that fired (timeout, or rate_limited once Decide has re-sent), the text
///     of a failure (daily_cap, no_key, timeout, rate_limited, unusable for the agent's maximum iterations, otherwise error), the
///     provider's finish reason (refusal, cut_off), an empty text (empty, or unusable when the provider reports no finish reason) and a
///     reply that fails its check (invalid). Its literals are the class parameters DAILYCAPTEXT, NOKEYTEXT, TIMEOUTTEXT, RATELIMITTEXT
///     and ITERATIONCODES, each with its source.
///   - The runner's reply goes to Conclude, with the text of the runner's failure when it failed (OnError keeps a runner's error status,
///     and a call whose Chat threw is answered with a failure Reply that holds FailureText). Conclude works out the facts and calls
///     Classify once. A reply that is usable is checked (CheckReply: one JSON object that the ReplyClass setting of the runner accepts,
///     for decide and diagnose; non-empty text for a turn), except the reply of a model test request of kind decide or diagnose (Settings.IsTest),
///     which is a connection test: any non-empty text is usable, it is never checked against the ReplyClass setting, and its Decision row keeps
///     no reasons, confidence or payload (the Conventions row "Settings model Test"). The model-written text is filtered once by the ReplyFilterClass (the reasons, and the
///     properties that the reply class names in a FILTERED parameter, a dotted name for a property of an object property and a list item by item,
///     which are then checked again; the request is exposed to both checks through ReplyCheck, ended on every exit), the user
///     rule is applied, one Decision row is recorded, the event decision.recorded is fired after the commit (FireEvent) and the answer
///     is built. For a user's decide request an ignore or digest becomes tellnow. A decide or diagnose reply that is invalid because of its check
///     gets one trace warning that names what failed and never the reply (RefusalText: the error code, the reply class's property, the element,
///     the limit and the computed length; no value, no IRIS message text and no field name of the reply).
///   - Any other reply is a fallback (RecordFallback): one Decision row with the outcome tellnow, Fallback true and the reason, and no
///     reasons, confidence or payload, so that no model text is kept; decision.recorded after the commit; and, for daily_cap, the day is
///     marked as capped once (Budget.MarkCapped). A decide or diagnose request is answered with the row's DecisionResponse, and a turn
///     with a new Reply that holds no text, host data, steps or failure text, and the runner's Tainted and ToolsRun when
///     there was a runner reply (and SessionBroken for a user's turn, below), and SessionRotated 0, because a fallback moves no link. A fallback triggers no tool, fix or approval (AD-8, AD-30).
///   - The timer (AD-6, AD-8): the timer of an attempt ends the decision with a fallback, never an error. OnResponse for the key timer
///     records the fallback (RecordFallback) for the stored DecisionRef, with the reason that Classify gives for a timer that fired:
///     timeout, or rate_limited once Decide has re-sent (Resends above 0, because the retries then ran out, FR-4). The timer keeps
///     SetTimer's controlled keys, so the runner request in flight leaves the pending list and the framework discards its late reply:
///     no step is sent for it, and the totals of the row are those of the Usage rows when the timer fired. The runner still writes the
///     Usage row of the late call, under the same DecisionRef, and the day's spend and Usage.Totals count it.
///   - The re-send (AD-8, FR-4, NFR-23): when the runner answers with a Reply and no error status, the FailureText of the Reply gives
///     the reason (Classify) and ResendDelay decides: for rate_limited, with no tool run (Reply.ToolsRun false) and at least 2 seconds of
///     TimerSeconds left, it gives 1, 2, 4 and then 8 seconds of back-off (RESENDFIRST, RESENDMAX), the last one shortened so that the
///     re-send keeps at least 1 second before the timer. Decide then adds the attempt's steps to StepCount, sets a timer with the key
///     resend that cancels nothing, and answers nothing yet. The key resend prechecks the request again (the same token budget as
///     OnRequest, and the same request-size limit; a reason is recorded with RecordFallback, so a daily_cap marks the day), sends the request
///     that SentRequest builds, with the stored DecisionRef, to the same runner, adds 1 to Resends and sets the timer for the whole seconds
///     left. A delay of 0 sends the reply to Conclude, so a tool that ran, an error status (which has no Reply), error, timeout and every
///     other reason fall back at once. Decide never reads a
///     Retry-After: AI Hub's retry block caps it (Timeouts.Derive). A re-send is not a fault and logs no warning.
///   - The row and the answer carry the decision's totals (AD-20): the token counts, the cost and the model are the sums over the
///     Usage rows of its DecisionRef, which the runner wrote for every attempt (Usage.Totals); the step count is StepCount, the steps
///     of the earlier attempts, plus the last reply's; and the duration is the time from the moment Decide began to handle the request
///     to Conclude. CarryTotals copies the eight fields between a row and an answer, so an answer built from a recorded row carries the
///     row's totals. A decision with no Usage row has empty totals, and one with a row of unknown cost has an empty cost.
///   - Busy (AD-6): a turn with provenance user is linked to a conversation, whose lock the runner holds from opening the AI session to
///     saving it (Data.ConversationLink). After CheckSettings and before the DecisionRef and the precheck, OnRequest takes that lock and at
///     once releases it (Held); when it is not taken in the lock's 2 seconds, the answer is Reply.NewBusy(): Busy is 1 and nothing else is
///     set, and nothing else happens: no Decision row, no decision.recorded, no timer, no runner request and no steps. A Reply of the
///     runner whose Busy is 1 (the key reply) is answered the same way, after the steps. A Busy answer is never an error status, a
///     fallback or a row. Untrusted turns, decide and diagnose are never probed. The re-send takes no probe: the runner reopens the saved
///     history of the conversation, which a Chat that failed never saved.
///   - SessionBroken (AD-8): a user's turn whose failure text holds INVALIDINPUTTEXT is answered with a fallback Reply whose SessionBroken
///     is 1 (Broken). The reason stays error, the row is recorded like any fallback, and the runner saved nothing, so the stored history
///     and the link stay as they were. A fallback Reply also carries the runner's Tainted and ToolsRun.
///   - The one arbiter of the conversation link (AD-6, AD-8, DW-729, DW-730): only Decide moves a conversation's link, and only when it accepts a
///     reply as the decision's answer, which is on time and untainted. A runner saves its AI session and names it in the Reply (SessionId, with
///     SessionFrom, the session the link named when it began, and HistoryCount); it never calls Data.ConversationLink Point. Conclude, after it
///     records the Decision row of a linked turn's usable reply and before it answers, calls PointLink, which points the link of (OwnerRef, the first
///     runner) at SessionId by the compare-and-set Point, expecting SessionFrom, and sets the answer's SessionRotated; the answer carries none of the
///     session fields. A fallback, a reply after the timer (the framework discards it), a tainted reply and a reply that the retry replaced move
///     nothing, for a fresh, a compacted, a saved and a retried turn alike. A move that fails or loses its compare-and-set is one warning, and the
///     answer stands.
///   - The second-model retry (AD-6, AD-8): a runner whose RetryItem setting names a retry runner (RetryItemOf) is retried once. When the
///     attempt ends with a reason that Retryable lists (timeout, rate_limited, error, refusal, cut_off, empty, invalid, unusable, no_key), Decide
///     sends a clone of the request, with the same DecisionRef and ItemId and with RetryOf set to the first runner, once, to the retry runner (TryRetry).
///     Never retried: daily_cap, budget and too_large, a reply in which a tool ran (Reply.ToolsRun), a SessionBroken turn, a request of kind tool,
///     a model test request (Settings.IsTest: its ItemId starts with Settings.#TESTITEMPREFIX, so that the answer says whether the first model
///     answered) and the retry itself. A timer that fired leaves it unknown whether a tool ran, so a timed-out turn is not retried (it falls back as in release
///     1), and a timed-out decide or diagnose is retried only when every tool of its agent is read-only code-classified safe and every MCP server that McpServersClass lists says that its tools are read-only (ToolsReadOnly). The
///     timers (AD-8): T1 is TimerFor of the first attempt, kept in FirstSeconds; the retry waits RetrySeconds, the least of TimerSeconds and
///     MAXTIMER - T1, and is sent only when that is at least MINTIMER, so the whole decision stays within MAXTIMER; otherwise the fallback keeps
///     the first reason and carries RETRYSKIPPED as its reasons. The retry takes the precheck of its own runner (Precheck: its key, the daily cap,
///     the budget and the size limit), is never sent again, and its reply is neither weighed for a re-send nor retried; a fallback after it
///     carries its reason. A user's linked turn is sent with no Held probe when it carries RetryOf for the same runner and ItemId (Held), because
///     the retry runs unlocked in a session of its own. The retry of a linked turn that is not fresh is sent as a fresh turn whose SeedText is
///     RetrySeed: Compaction.Seed, which is code and makes no model call, of the first HistoryCount messages that the session named by the first
///     runner's link stored (RequestSize.StoredMessages), the messages that the first attempt began with, or all of them when the first attempt sent
///     no reply or no count; nothing that the first attempt produced goes in (DW-726). A fresh turn keeps its own SeedText. The decision is still one row and one answer: its totals are the sums of the Usage rows
///     of the DecisionRef, its steps continue across the attempts, and its Model is that of the reply that answered.
///   - A RetryOf that a caller sets is never honoured: Held and EstimateTokens do not read it for the request that arrives, and SentRequest
///     clears it on every first send and every re-send. Only the clone that TryRetry builds carries RetryOf.
///   - A request that is refused (Admit, the settings) ends with an error status, and no row is recorded; the late reply of a runner
///     after the timer is discarded by the business process framework.
/// The state of a decision that outlasts one message is stored with the process (AD-5): DecisionRef, Resends, StepCount, StepsSent, RetryRunner and
/// FirstSeconds.
/// None is a setting. The six extension settings name the classes through which the bridge reaches its host (AD-31); the production
/// definition sets all six, and OcuTalon.Bridge.Ext.Accessor reads them in any job. The three budget settings (AD-19, AD-20) are
/// System Default Settings that OcuTalon.Bridge.Budget reads through the same accessor; DecisionTokenBudget and RequestTokenLimit are
/// settings of Decide itself, which Decide reads as they are written now when it runs as its own job (SettingText), so that a change applies to the
/// next decision with no restart. InstanceZone is the instance zone's single source (AD-18): OcuTalon.Bridge.Time reads and writes it. ServiceUser and ToolClassification are read by the gate (OcuTalon.Bridge.Policy.Gate, AD-10) in the runner's job, and ApprovalRole by OcuTalon.Bridge.Approval.Raise (AD-11) in the caller's job. FireEvent delivers every event of the bridge to the host sink. This class names no other OcuTalon package (AD-2).
Class OcuTalon.Bridge.Process.Decide Extends Ens.BusinessProcess
{

Parameter SETTINGS = "HostSinkClass:Extensions,ReplyFilterClass:Extensions,ClassificationClass:Extensions,TurnToolsClass:Extensions,McpServersClass:Extensions,ContentClass:Extensions,TimerSeconds:Bridge,DecisionTokenBudget:Bridge,RequestTokenLimit:Bridge,DailyCostCapUSD:Bridge,GatewaySpendUSD:Bridge,GatewaySpendDate:Bridge,InstanceZone:Bridge,ServiceUser:Bridge,ToolClassification:Bridge,ApprovalRole:Bridge";

/// The runner item of each request kind, as kind:item pairs (AD-6).
Parameter RUNNERS = "decide:TriageAgent,diagnose:DiagnosisAgent,turn:ChatAgent";

/// The longest timer, in seconds (AD-5, AD-8).
Parameter MAXTIMER = 110;

/// The shortest timer, in seconds: (12 - 10) \ 2 is 1, the least whole attempt timeout that Timeouts.Derive gives AI Hub.
Parameter MINTIMER = 12;

/// The request-size limit in tokens, which RequestTokenLimit may not pass and which an empty or invalid RequestTokenLimit counts as: no
/// model request goes over 100,000 tokens, where the price tier changes (NFR-3, AD-19, AD-20).
Parameter MAXREQUESTTOKENS = 100000;

/// The estimate in tokens above which SentRequest flags a turn for compaction (Request.Compact, AD-20).
Parameter COMPACTTOKENS = 40000;

/// The first back-off before a re-send, in seconds; each later one doubles it (ResendDelay).
Parameter RESENDFIRST = 1;

/// The longest back-off before a re-send, in seconds.
Parameter RESENDMAX = 8;

/// The operation that records the agent steps (AD-9).
Parameter STEPSITEM = "AgentSteps";

/// The reasons that Decide retries once on a second model, comma-separated (AD-8). The others (daily_cap, budget, too_large) never are.
Parameter RETRIED = "timeout,rate_limited,error,refusal,cut_off,empty,invalid,unusable,no_key";

/// The reason line of the fallback of a decision whose second-model retry was skipped for lack of time (AD-8, DW-647, veto U-281): plain English for
/// the person, shown in the trace as the reasons of the decision.
Parameter RETRYSKIPPED = "The second model was not tried, because too little time was left within the decision's 110-second limit.";

/// The first reason line of a user's decide request whose outcome was ignore or digest (AD-6).
Parameter USERANSWERED = "The outcome was changed because a message the user writes is always answered.";

/// The reason line of the fallback Decision row of an approved tool call that was held before ToolSource and Runner existed (either one is
/// empty), which is closed failed instead of replayed (FailUnroutable). It is plain English for the person: no class name, no code, no status text.
Parameter HELDBEFOREUPDATE = "This request was held before an update and cannot be run again safely, so please ask again.";

/// The reason line of the fallback Decision row of a replay that failed because no model key is set, before the approved call ran (ConcludeTool):
/// plain English for the person, with the words of the catalog's fallbackReason.noKey and conversation.turnFallback.
Parameter REPLAYNOKEY = "No model key is set, so the approved call did not run. Nothing was changed.";

/// The words of the online demo gateway's HTTP 403 for a reached daily cost cap, which Classify finds in a failure text: daily_cap
/// (source: AD-8; Story 1.6 Task 0 (b) measured the text that AI Hub raises for it). Matched without regard to case.
Parameter DAILYCAPTEXT = "daily cost cap reached";

/// The two pieces of the provider error for a key placeholder whose variable is not set, both held by a failure text: no_key (source:
/// Story 1.2's measurement of "@{env:ANTHROPIC_API_KEY} has no value and no :-fallback was given"). Matched without regard to case.
Parameter NOKEYTEXT = "@{env:|has no value";

/// The words of the AI Hub error for a provider object that cannot be built from the runner's settings (an unknown provider name): the replay fails in
/// BuildAgent, before the call, and ConcludeTool gives it REPLAYPROVIDER (source: Story 30.7 Task 0a measured "ProviderCreateFailed: Failed to create
/// provider 'zznope'" for an unknown provider name). Matched without regard to case.
Parameter PROVIDERTEXT = "Failed to create provider";

/// The reason line of the fallback Decision row of a replay whose provider object could not be built, before the approved call ran (ConcludeTool; owner
/// decision U-214): plain English for the person.
Parameter REPLAYPROVIDER = "The model provider could not be reached, so the approved call did not run. Nothing was changed.";

/// The words of the provider's timeout error: timeout (source: AD-8, S2). Matched without regard to case.
Parameter TIMEOUTTEXT = "operation timed out";

/// The words of the provider's error for HTTP 429 and 529: rate_limited (source: AD-8, S2; Story 0.11 measured the 529 text). Matched
/// without regard to case.
Parameter RATELIMITTEXT = "Rate limit exceeded";

/// The words of the provider's error for a conversation history that it rejects (HTTP 400, "... error: Invalid input: <msg>"), which Broken
/// finds in the failure text of a user's turn: SessionBroken (source: AD-8; Story 0.11 measured the text for a 400). Matched without regard
/// to case.
Parameter INVALIDINPUTTEXT = "Invalid input";

/// The codes of the errors that end a turn in AI Hub's tool loop, comma-separated, each found in a failure text: unusable (source: Story 1.6
/// Task 0 (a), measured on build 154: MaxIterationsReached when the agent's iterations are used up, and LoopDetected when the loop stalls
/// on tool results that bring nothing new). Matched without regard to case.
Parameter ITERATIONCODES = "<%AICore>MaxIterationsReached,<%AICore>LoopDetected";

/// The finish reasons that end a reply normally, comma-separated and in lower case (Classify rule 6): a reply with text and any other
/// non-empty finish reason, refusal and max_tokens apart, is unusable.
Parameter FINISHED = "end_turn,stop_sequence,tool_use,stop";

/// The class that receives the bridge's events; it extends OcuTalon.Bridge.Ext.HostSink.
Property HostSinkClass As %String(MAXLEN = 128) [ InitialExpression = "OcuTalon.Bridge.Ext.HostSink" ];

/// The class that filters model-written text before a result leaves Decide; it extends OcuTalon.Bridge.Ext.ReplyFilter.
Property ReplyFilterClass As %String(MAXLEN = 128) [ InitialExpression = "OcuTalon.Bridge.Ext.ReplyFilter" ];

/// The class that classifies tools beyond code and settings; it extends OcuTalon.Bridge.Ext.Classification.
Property ClassificationClass As %String(MAXLEN = 128) [ InitialExpression = "OcuTalon.Bridge.Ext.Classification" ];

/// The class that gives one request tools of its own; it extends OcuTalon.Bridge.Ext.TurnTools.
Property TurnToolsClass As %String(MAXLEN = 128) [ InitialExpression = "OcuTalon.Bridge.Ext.TurnTools" ];

/// The class that names the MCP servers a runner attaches and receives the report of each attach; it extends OcuTalon.Bridge.Ext.McpServers.
Property McpServersClass As %String(MAXLEN = 128) [ InitialExpression = "OcuTalon.Bridge.Ext.McpServers" ];

/// The class that gives an untrusted turn one image to send with its text and receives each accepted turn reply; it extends OcuTalon.Bridge.Ext.Content.
Property ContentClass As %String(MAXLEN = 128) [ InitialExpression = "OcuTalon.Bridge.Ext.Content" ];

/// How long Decide waits for the runner's reply, in whole seconds from MINTIMER to MAXTIMER (AD-5, AD-8). Timeouts.Apply changes it
/// together with the Config Store entries of the runners.
Property TimerSeconds As %Integer [ InitialExpression = 60 ];

/// The daily cost cap in US dollars; 0 means off. A value that is not a number of 0 or more counts as 0 (OcuTalon.Bridge.Budget).
Property DailyCostCapUSD As %Numeric [ InitialExpression = 0 ];

/// The spend that the online demo's outbound gateway reports for GatewaySpendDate, in US dollars (AD-19, AD-20).
Property GatewaySpendUSD As %Numeric;

/// The instance-zone date, YYYY-MM-DD, that GatewaySpendUSD counts.
Property GatewaySpendDate As %String(MAXLEN = 10);

/// The instance zone (AD-18): an IANA zone name, or empty for the container's TZ. It is read only through OcuTalon.Bridge.Time.Zone and written
/// only through OcuTalon.Bridge.Time.SetZone, never from this property: a job follows the setting as it is written, not as the job started.
Property InstanceZone As %String(MAXLEN = 64);

/// The token budget per decision (AD-19, AD-20, FR-40): a request whose estimate (EstimateTokens) is above it takes the fallback route
/// with the reason budget, and is never sent. 0 means off. A value that is not a whole number of 0 or more counts as 0, and the
/// precheck logs it (AssignOneSetting, OnRequest).
Property DecisionTokenBudget As %Integer [ InitialExpression = 0 ];

/// The IRIS user whose privileges the gate checks for the resources a tool declares (AD-10, AD-24). It is the service user that the installer
/// creates; the bridge cannot read the installer's constant (AD-2), so the name is a host setting. The gate reads it only for a tool that declares
/// resources.
Property ServiceUser As %String(MAXLEN = 160) [ InitialExpression = "OcuTalonService" ];

/// The role a person needs to answer an approval request (AD-11, FR-5, FR-8): Approval.Raise copies it to the row's
/// RequiredRole. OcuTalon seeds OcuTalonUser, as ServiceUser seeds OcuTalonService; the bridge cannot read the installer's constant (AD-2),
/// so the name is a host setting. An empty value refuses Raise.
Property ApprovalRole As %String(MAXLEN = 128) [ InitialExpression = "OcuTalonUser" ];

/// The classification of a developer's own tools (AD-10, AD-31): a JSON array of {"class","tool","classification"[,"readOnly"][,"trustedOutput"]}
/// objects, where class is the tool's implementing class, tool its name, classification safe or risky, and readOnly and trustedOutput are 1 or 0.
/// An empty value is none. The gate reads it after the code of the tool's class and never changes a classification that code gives
/// (OcuTalon.Bridge.Policy.Gate.ClassificationOf). A System Default Settings row holds at most 2,000 characters, about twenty entries; a longer
/// list is set on the Decide item of the production definition.
Property ToolClassification As %String(MAXLEN = "");

/// The request-size limit in tokens (AD-8, AD-19, AD-20, NFR-3): a request whose estimate (EstimateTokens) is above it takes the fallback
/// route with the reason too_large, and is never sent. A whole number from 1 to MAXREQUESTTOKENS is the limit. An empty value counts as
/// MAXREQUESTTOKENS, and so does any other value (0, a value that is not a whole number, or one above MAXREQUESTTOKENS) with one warning
/// that the precheck logs (AssignOneSetting, OnRequest), so the limit is never off and never above MAXREQUESTTOKENS.
Property RequestTokenLimit As %Integer [ InitialExpression = 100000 ];

/// The error status that a runner ended its call with, kept by OnError for OnResponse (the key reply). Not stored.
Property RunnerError As %Status [ InitialExpression = 1, Internal, Transient ];

/// The DecisionRef of this decision, set in OnRequest before the send (AD-20); the timer and the re-sends use it. Not a setting.
Property DecisionRef As %String(MAXLEN = 22);

/// The number of times Decide has sent the request again after a rate limit. Not a setting.
Property Resends As %Integer [ InitialExpression = 0 ];

/// The AgentStepCount of the attempts before the last one. Not a setting.
Property StepCount As %Integer [ InitialExpression = 0 ];

/// The Position of the last step that EmitSteps built for the decision so far (0 for none), so that the Positions of a decision run on
/// across its attempts. Not a setting.
Property StepsSent As %Integer [ InitialExpression = 0 ];

/// The retry runner item that the second-model retry was sent to, or "" until it is sent (TryRetry). A decision is retried at most once. Not a setting.
Property RetryRunner As %String(MAXLEN = 128);

/// T1, the timer in whole seconds of the first attempt as it was set (TimerFor), or "" when no first attempt was sent (a precheck refused it). The
/// retry's timer follows from it (RetrySeconds). Not a setting.
Property FirstSeconds As %Integer;

/// Assigns a setting as Ens.Settings does, except for the five budget and size settings (AD-20, DW-76). A value of DailyCostCapUSD,
/// GatewaySpendUSD or GatewaySpendDate that its property's datatype refuses, and a DecisionTokenBudget or RequestTokenLimit that is not
/// made of digits only, is assigned as "", so that the process can still be saved before OnRequest and the setting counts as off (a
/// RequestTokenLimit, as MAXREQUESTTOKENS). The value as written is still reported: Budget.State names the faults of the cap and of the
/// gateway's spend, and OnRequest gives Precheck the text of a DecisionTokenBudget or RequestTokenLimit that was not assigned.
Method AssignOneSetting(pProperty As %String, pValue As %String, pName As %String) As %Status
{
	Set sc = ##super(pProperty, pValue, pName)
	If $$$ISERR(sc) || '$ListFind($ListBuild("DecisionTokenBudget", "RequestTokenLimit", "DailyCostCapUSD", "GatewaySpendUSD", "GatewaySpendDate"), pProperty) Quit sc
	If $$$ISERR($ClassMethod($ClassName(), pProperty_"IsValid", $Property($this, pProperty))) || ($ListFind($ListBuild("DecisionTokenBudget", "RequestTokenLimit"), pProperty) && (pValue '? 1.N)) {
		Set $Property($this, pProperty) = ""
	}
	Quit sc
}

/// Admits the request, finds the decision that is recorded for its item, prechecks it, or sends it to the runner of its kind and sets
/// the timer. The answer for a recorded decide or diagnose request, and the fallback answer of a request that fails a precheck
/// (Precheck), are given here (response): the second is recorded (RecordFallback) and nothing is sent, no runner request and no timer.
/// Otherwise the answer comes from OnResponse. The settings are checked first, so that a misconfigured Decide stays an error status and
/// is never hidden behind a fallback. The DecisionRef is allocated here and kept in DecisionRef, before the send.
Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set response = ""
	Set sc = ..Admit(request)
	If $$$ISERR(sc) Quit sc
	Set kind = request.Kind
	If ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(request.ItemId, kind, .id) {
		Quit ..ResponseFromId(id, .response)
	}
	Set runner = ..RunnerFor(kind, request)
	Set replyClass = ""
	Set tool = (kind = "tool")
	If (kind '= "turn") && 'tool {
		Set replyClass = ..ReplyClassOf(runner, .sc)
		If $$$ISERR(sc) Quit sc
	}
	Set sc = ..CheckSettings(kind, runner, replyClass, ..ReplyFilterClass, ..TimerSeconds)
	If $$$ISERR(sc) Quit sc
	If 'tool && ..Held(request, runner) {
		Set response = ##class(OcuTalon.Bridge.Msg.Reply).NewBusy()
		Quit $$$OK
	}
	Set decisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..DecisionRef = decisionRef
	If tool && ((runner = "") || ..HeldBeforeUpdate(request)) {
		Set closed = ..FailUnroutable(request)
		Quit ..RecordFallback(request, decisionRef, "error", "", ..HostSinkClass, ..%SessionId, .response, ##class(OcuTalon.Bridge.Time).MsSince(..%TimeCreated), 0, 0, $Select(closed: ..#HELDBEFOREUPDATE, 1: ""))
	}
	Set estimate = 0
	Set reason = $Select(tool: "", 1: ..Precheck(request, runner, ..SettingText("DecisionTokenBudget"), ..SettingText("RequestTokenLimit"), .estimate))
	If reason '= "" {
		Quit ..TryRetry(request, runner, reason, "", .response)
	}
	Set sc = ..SendRequestAsync(runner, ..SentRequest(request, decisionRef, estimate), 1, "reply")
	If $$$ISERR(sc) Quit sc
	Set ..FirstSeconds = ..TimerFor(request, ..Flagged(request, estimate))
	Quit ..SetTimer(..FirstSeconds, "timer")
}

/// 1 when the request is linked to a conversation by the runner's own rule (Adapter.Agent IsLinked: a turn with provenance user) and its
/// conversation lock, (OwnerRef, the runner item), is not taken in the lock's seconds (Data.ConversationLink LOCKSECONDS): an earlier turn,
/// even one that Decide gave up on, still holds the conversation (AD-6). The lock is taken only to probe and released at once. Every other
/// request is never held. The one exception is the second-model retry (AD-6, AD-8): the request is not probed, and the answer is 0, only when it
/// carries RetryOf naming this runner and its ItemId is the non-empty itemId that the caller vouches for, because the retry runs unlocked in a session
/// of its own. OnRequest passes no itemId, so a RetryOf that a client set never skips the probe; TryRetry passes the ItemId of the decision it retries.
ClassMethod Held(request As OcuTalon.Bridge.Msg.Request, runner As %String, itemId As %String = "") As %Boolean
{
	If '##class(OcuTalon.Bridge.Adapter.Agent).IsLinked(request) Quit 0
	If (itemId '= "") && (request.RetryOf = runner) && (request.ItemId = itemId) Quit 0
	If ##class(OcuTalon.Bridge.Data.ConversationLink).Lock(request.OwnerRef, runner) {
		Do ##class(OcuTalon.Bridge.Data.ConversationLink).Unlock(request.OwnerRef, runner)
		Quit 0
	}
	Quit 1
}

/// An error status of the runner's call (the completion key reply) is kept in RunnerError, and OK is returned, so that Ens calls
/// OnResponse next and the failure is classified there (AD-8); the process then ends with the fallback answer. An error of any
/// other call keeps its status.
Method OnError(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, pErrorStatus As %Status, pCompletionKey As %String) As %Status
{
	If pCompletionKey = "reply" {
		Set ..RunnerError = pErrorStatus
		Quit $$$OK
	}
	Quit pErrorStatus
}

/// The completion keys (AD-6, AD-8):
///   - timer: the timer ended the attempt, so the decision is recorded as a fallback for the stored DecisionRef (RecordFallback), with
///     the reason that Classify gives for a timer that fired (timeout, or rate_limited after a re-send; once the retry was sent, always
///     timeout), and the caller is answered, unless the second-model retry applies to the attempt (TryRetry), which is sent instead;
///   - resend: the back-off of a re-send is over (Resend);
///   - reply: the runner answered. The steps are sent first (EmitSteps), so that a reply that is then refused, or a call that failed,
///     still shows its steps in the trace. A Reply whose Busy is 1 is then answered with Reply.NewBusy(), with no row, no event and no
///     re-send. Otherwise Conclude gets the text of the runner's failure: the runner's error status
///     (RunnerError, cut by StepBuffer.Part to Reply.#MAXFAILURE) or the FailureText of its failure Reply. When the runner answered
///     with a Reply and no error status, ResendDelay weighs a re-send first (above); a delay above 0 adds the attempt's steps to
///     StepCount, sets the timer resend and answers nothing yet.
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, pCompletionKey As %String) As %Status
{
	Set kind = request.Kind
	Set runner = ..RunnerFor(kind, request)
	If pCompletionKey = "timer" {
		Set facts = {}
		Do facts.%Set("timedOut", 1, "boolean")
		Do facts.%Set("resends", $Select(..RetryRunner '= "": 0, 1: ..Resends), "number")
		Quit ..TryRetry(request, runner, ..Classify(facts), "", .response, "", 1)
	}
	If pCompletionKey = "resend" Quit ..Resend(request, runner, .response)
	If pCompletionKey '= "reply" Quit $$$ERROR($$$GeneralError, "Decide got a response with the unknown completion key '"_pCompletionKey_"'")
	Do ..EmitSteps(callrequest.DecisionRef, callresponse)
	If $$$ISOK(..RunnerError) && $IsObject(callresponse) && callresponse.%IsA("OcuTalon.Bridge.Msg.Reply") && callresponse.Busy {
		Set response = ##class(OcuTalon.Bridge.Msg.Reply).NewBusy()
		Quit $$$OK
	}
	Set failure = ""
	Set answered = 0
	If $$$ISERR(..RunnerError) {
		Set failure = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Part($SYSTEM.Status.GetErrorText(..RunnerError), ##class(OcuTalon.Bridge.Msg.Reply).#MAXFAILURE)
		Set ..RunnerError = $$$OK
	} ElseIf $IsObject(callresponse) && callresponse.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Set failure = callresponse.FailureText
		Set answered = 1
	}
	If answered && (failure '= "") && (kind '= "tool") && (..RetryRunner = "") {
		Set facts = {}
		Do facts.%Set("failure", failure)
		Set delay = ..ResendDelay(..Classify(facts), callresponse.ToolsRun, ..Resends, ..RemainingMs(request))
		If delay > 0 {
			Set ..StepCount = ..StepCount + callresponse.AgentStepCount
			Quit ..SetTimer(delay, "resend", "")
		}
	}
	Set replyClass = ""
	If (kind '= "turn") && (kind '= "tool") {
		Set replyClass = ..ReplyClassOf($Select(..RetryRunner '= "": ..RetryRunner, 1: runner), .sc)
		If $$$ISERR(sc) Quit sc
	}
	Set retryReason = ""
	Set sc = ..Conclude(request, callrequest.DecisionRef, callresponse, replyClass, ..ReplyFilterClass, ..HostSinkClass, ..%SessionId, .response, ##class(OcuTalon.Bridge.Time).MsSince(..%TimeCreated), failure, ..StepCount, (kind '= "tool") && (..RetryRunner = "") && ..RetryConfigured(runner), .retryReason, runner)
	If $$$ISERR(sc) || (retryReason = "") Quit sc
	Quit ..TryRetry(request, runner, retryReason, callresponse, .response, failure)
}

/// The key resend (AD-8, AD-20): prechecks the request again with the token budget and the request-size limit of OnRequest
/// (SettingText), and records a reason with RecordFallback, so that a daily_cap marks the day. With less than a second of the timer left
/// it records rate_limited at once and sends nothing. A reason that the second-model retry covers goes to TryRetry instead (no_key and rate_limited). Otherwise it sends the request that SentRequest builds, with the stored DecisionRef,
/// to the runner (the key reply), adds 1 to Resends and sets the timer for the whole seconds left, because the framework dropped the
/// first timer's pending entry when the runner's reply arrived.
Method Resend(request As OcuTalon.Bridge.Msg.Request, runner As %String, Output response As %Persistent) As %Status
{
	Set response = ""
	Set elapsed = ##class(OcuTalon.Bridge.Time).MsSince(..%TimeCreated)
	Set reason = ..Precheck(request, runner, ..SettingText("DecisionTokenBudget"), ..SettingText("RequestTokenLimit"), .estimate)
	Set seconds = ..RemainingMs(request, estimate) \ 1000
	If (reason = "") && (seconds < 1) Set reason = "rate_limited"
	If reason '= "" {
		Quit ..TryRetry(request, runner, reason, "", .response)
	}
	Set sc = ..SendRequestAsync(runner, ..SentRequest(request, ..DecisionRef, estimate), 1, "reply")
	If $$$ISERR(sc) Quit sc
	Set ..Resends = ..Resends + 1
	Quit ..SetTimer(seconds, "timer")
}

/// The text that the precheck gets for DecisionTokenBudget or RequestTokenLimit (name). In the item's own job (the job's configuration name is
/// the host's) it is the setting as it is written now (Ext.Accessor.ValueFor), so that a new budget applies to the next decision with no restart
/// (AD-19); when that cannot be read, and in any other process, it is the setting as the process holds it, or as it is written when the process
/// holds none (an invalid value is held as "", AssignOneSetting).
Method SettingText(name As %String) As %String
{
	If (..%ConfigName '= "") && (..%ConfigName = $$$JobConfigName) {
		Set written = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor(name, "", ..%ConfigName, .sc)
		If $$$ISOK(sc) Quit written
	}
	Set value = $Property($this, name)
	If value = "" Set value = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor(name, "", ..%ConfigName)
	Quit value
}

/// The request that goes to a runner, for the first send and for every re-send (AD-6, AD-20): a clone of the request that carries the
/// DecisionRef and the Compact flag, 1 exactly when the request is a turn (any provenance and any SessionMode) and the estimate that the
/// precheck worked out is above COMPACTTOKENS, otherwise 0, whatever the caller set, and an empty RetryOf, whatever the caller set (AD-6: only the
/// retry's clone carries one, RetryRequest). The request itself is not changed.
ClassMethod SentRequest(request As OcuTalon.Bridge.Msg.Request, decisionRef As %String, estimate As %Integer) As OcuTalon.Bridge.Msg.Request
{
	Set clone = request.%ConstructClone()
	Set clone.DecisionRef = decisionRef
	Set clone.Compact = ..Flagged(request, estimate)
	Set clone.RetryOf = ""
	Quit clone
}

/// The request that goes to the retry runner (AD-6, AD-8): SentRequest, with the same DecisionRef and ItemId, and RetryOf set to the first
/// runner. It is the only request that Decide sends with RetryOf. A linked turn that is not fresh is sent fresh, with RetrySeed as its SeedText
/// (reply is the first attempt's Reply, or "" when it sent none), so that the retry runner reads no stored history and nothing that the first attempt
/// produced goes in (DW-726); a fresh turn keeps its own SeedText, and any other request is cloned as it is.
ClassMethod RetryRequest(request As OcuTalon.Bridge.Msg.Request, decisionRef As %String, estimate As %Integer, runner As %String, reply As %RegisteredObject = "") As OcuTalon.Bridge.Msg.Request
{
	Set clone = ..SentRequest(request, decisionRef, estimate)
	Set clone.RetryOf = runner
	If ##class(OcuTalon.Bridge.Adapter.Agent).IsLinked(clone) && (clone.SessionMode '= "fresh") {
		Set clone.SessionMode = "fresh"
		Set clone.SeedText = ..RetrySeed(request, runner, reply)
	}
	Quit clone
}

/// The seed of the second-model retry of a linked turn that is not fresh (AD-6, DW-726): Compaction.Seed of the first HistoryCount messages of the stored
/// history of the session that the link of (OwnerRef, runner) names (RequestSize.StoredMessages), the messages the first attempt began with. All of
/// the stored messages when reply is not a Reply or holds no count, and "" when the link names no session. It reads the database and calls no model.
ClassMethod RetrySeed(request As OcuTalon.Bridge.Msg.Request, runner As %String, reply As %RegisteredObject = "") As %String
{
	Set count = $Select($IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply"): reply.HistoryCount, 1: "")
	Quit ##class(OcuTalon.Bridge.Compaction).Seed(##class(OcuTalon.Bridge.RequestSize).StoredMessages(##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(request.OwnerRef, runner), count))
}

/// 1 when the request is flagged for compaction (AD-6, AD-20): a turn, of any provenance and any SessionMode, whose estimate (EstimateTokens)
/// is above COMPACTTOKENS. It is pure.
ClassMethod Flagged(request As OcuTalon.Bridge.Msg.Request, estimate As %Integer) As %Boolean
{
	Quit $IsObject(request) && (request.Kind = "turn") && (+$Get(estimate) > ..#COMPACTTOKENS)
}

/// The timer of an attempt in whole seconds (AD-5, AD-20): TimerSeconds, plus Compaction.#SUMMARIZERSECONDS (and at most MAXTIMER) for a
/// request that is flagged (compact is 1, see Flagged) and continues its conversation: a linked turn (Adapter.Agent IsLinked) whose
/// SessionMode is not fresh and whose conversation link names an AI session, so that the runner may compact it before it chats. Every
/// other request keeps TimerSeconds. It reads the link and changes nothing.
Method TimerFor(request As OcuTalon.Bridge.Msg.Request, compact As %Boolean) As %Integer
{
	Set seconds = +..TimerSeconds
	If '$Get(compact) || '$IsObject(request) || '##class(OcuTalon.Bridge.Adapter.Agent).IsLinked(request) || (request.SessionMode = "fresh") Quit seconds
	If ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(request.OwnerRef, ..RunnerFor(request.Kind, request)) = "" Quit seconds
	Set seconds = seconds + ##class(OcuTalon.Bridge.Compaction).#SUMMARIZERSECONDS
	Quit $Select(seconds > ..#MAXTIMER: ..#MAXTIMER, 1: seconds)
}

/// 1 when the reason is one that Decide retries once on a second model and nothing forbids it (AD-8): reason is one of RETRIED; no tool ran (toolsRun
/// is 0: Reply.ToolsRun of the attempt's reply); the attempt is not a SessionBroken turn (broken is 0: Broken); and the request is not of kind tool.
/// A timer that fired (timedOut 1) leaves it unknown whether a tool ran, so a turn is not retried then (it falls back as in release 1, lead ruling
/// R2 of Story 17.2), and a decide or diagnose request is retried only when readOnly says that every tool of its agent is read-only, MCP servers included (ToolsReadOnly).
/// It is pure.
ClassMethod Retryable(reason As %String, toolsRun As %Boolean = 0, broken As %Boolean = 0, kind As %String = "", timedOut As %Boolean = 0, readOnly As %Boolean = 1) As %Boolean
{
	If $Get(kind) = "tool" Quit 0
	If '$ListFind($ListFromString(..#RETRIED), $Get(reason)) Quit 0
	If +$Get(toolsRun) || +$Get(broken) Quit 0
	If +$Get(timedOut) Quit ($Get(kind) '= "turn") && +$Get(readOnly)
	Quit 1
}

/// The seconds that the second-model retry waits, or 0 when it is not sent (AD-8, DW-647): T2, the least of timer (TimerSeconds) and MAXTIMER - t1 (T1,
/// the first attempt's timer), when T2 is at least MINTIMER, so that both attempts together stay within MAXTIMER. t1 "" counts as 0 (no first attempt was
/// sent). It is pure.
ClassMethod RetrySeconds(t1 As %Integer, timer As %Integer) As %Integer
{
	Set left = ..#MAXTIMER - +$Get(t1)
	Set seconds = $Select(+$Get(timer) < left: +$Get(timer), 1: left)
	Quit $Select(seconds < ..#MINTIMER: 0, 1: seconds)
}

/// 1 when the runner has a RetryItem setting that is not empty (Ext.Accessor ValueFor), and the retry has not been sent. It judges nothing about the
/// value: RetryItemOf does, only when a retry is considered.
Method RetryConfigured(runner As %String) As %Boolean
{
	If ..RetryRunner '= "" Quit 0
	Set value = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("RetryItem", "", runner, .sc)
	Quit $$$ISOK(sc) && ($ZStrip(value, "<>WC") '= "")
}

/// The retry runner item of the runner for a request of the kind (AD-6, AD-8): the RetryItem setting, when it names an item of the active production that
/// is an enabled agent runner other than the runner itself and, for decide and diagnose, whose ReplyClass passes CheckReplyClass. "" for an empty or unreadable
/// setting, with no warning. Any other value gives "" and one warning that names the setting and what is wrong with it, never an error status (an error would
/// make Decide refuse every request): the request then falls back as in release 1.
ClassMethod RetryItemOf(runner As %String, kind As %String) As %String
{
	Set item = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("RetryItem", "", runner, .sc)
	Set item = $ZStrip(item, "<>WC")
	If $$$ISERR(sc) || (item = "") Quit ""
	Set problem = ""
	Try {
		Set problem = ..RetryItemProblem(runner, kind, item)
	} Catch exception {
		Set problem = "it cannot be checked"
	}
	If problem = "" Quit item
	$$$LOGWARNING(##class(OcuTalon.Bridge.Redact).Text("The setting RetryItem of "_runner_" is '"_$Extract(item, 1, 60)_"': "_problem_", so the second-model retry is not used"))
	Quit ""
}

/// What is wrong with the item as the retry runner of the runner (RetryItemOf), in words, or "": it is the runner itself, it is not an item of the active
/// production, it is not an AgentRunner, it is disabled (a System Default Settings row of Enabled counts), or, for decide and diagnose, its ReplyClass is refused.
ClassMethod RetryItemProblem(runner As %String, kind As %String, item As %String) As %String [ Private ]
{
	If item = runner Quit "it names the runner itself"
	Set production = ##class(Ens.Director).GetActiveProductionName()
	Set config = $Select(production = "": "", 1: ##class(Ens.Config.Production).%OpenId(production))
	If '$IsObject(config) Quit "there is no active production"
	Set found = ""
	For i = 1:1:config.Items.Count() {
		If config.Items.GetAt(i).Name = item Set found = config.Items.GetAt(i)
	}
	If '$IsObject(found) Quit "it is not an item of the production"
	If '##class(%Dictionary.CompiledClass).%ExistsId(found.ClassName) || '$ClassMethod(found.ClassName, "%Extends", "OcuTalon.Bridge.Operation.AgentRunner") Quit "it is not an agent runner"
	Set enabled = $Select(##class(Ens.Config.DefaultSettings).%GetSetting(production, found.Name, found.ClassName, "", "Enabled", .override): override, 1: found.Enabled)
	If 'enabled Quit "it is disabled"
	If (kind '= "decide") && (kind '= "diagnose") Quit ""
	Set replyClass = ..ReplyClassOf(item, .sc)
	If $$$ISOK(sc) Set sc = ..CheckReplyClass(kind, item, replyClass)
	If $$$ISERR(sc) Quit "its ReplyClass is not usable"
	Quit ""
}

/// 1 when every tool of the agent class of the runner is read-only by what code declares (AD-10), so that an attempt in which one ran, and whose outcome
/// is unknown because its timer fired, did not change anything: the AgentClass setting of the runner (Ext.Accessor ValueFor, Adapter target) is a
/// compiled class, ToolsetsReadOnly holds for its TOOLSETS parameter, and every MCP server that the McpServersClass setting lists says that its tools are
/// read-only (McpServersReadOnly; no server leaves it as it was). 0 for anything that cannot be established from code and from the host's answers.
ClassMethod ToolsReadOnly(runner As %String) As %Boolean
{
	Set readOnly = 0
	Try {
		Set agentClass = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("AgentClass", "", runner, .sc, "Adapter")
		If $$$ISERR(sc) || (agentClass = "") || '##class(%Dictionary.CompiledClass).%ExistsId(agentClass) Quit
		Set readOnly = ..ToolsetsReadOnly($Parameter(agentClass, "TOOLSETS"))
		If readOnly Set readOnly = ..McpServersReadOnly()
	} Catch {
		Set readOnly = 0
	}
	Quit readOnly
}

/// 1 when no MCP server is listed, or when every server that the McpServersClass setting of Decide lists (Servers) says that its tools are read-only
/// (ToolsReadOnly of the class, DW-724). 0 for a setting that is not usable, a list that cannot be read or is no array, an entry with no server name,
/// a server that does not say 1, and any exception.
ClassMethod McpServersReadOnly() As %Boolean
{
	Set readOnly = 0
	Try {
		Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("McpServersClass", "", "Decide", .sc)
		If $$$ISERR(sc) Quit
		Set sc = $ClassMethod(class, "Servers", .servers)
		If $$$ISERR(sc) || '$IsObject($Get(servers)) || ('servers.%IsA("%Library.DynamicArray")) Quit
		Set readOnly = 1
		Set iterator = servers.%GetIterator()
		While readOnly && iterator.%GetNext(, .entry) {
			Set server = $Select($IsObject(entry) && entry.%IsA("%Library.DynamicObject") && (entry.%GetTypeOf("server") = "string"): entry.%Get("server"), 1: "")
			If (server = "") || '$ClassMethod(class, "ToolsReadOnly", server) Set readOnly = 0
		}
	} Catch {
		Set readOnly = 0
	}
	Quit readOnly
}

/// 1 when every tool of the toolsets (a TOOLSETS parameter: names, comma-separated, white space and empty names ignored) is read-only by what code
/// declares (AD-10): each name is a compiled toolset class (a name with a colon is a URI, whose tools are unknown, so 0) and each tool that the toolset
/// offers is classified safe with READONLY 1 by its class parameters (StepBuffer ToolParameter), with no Classify method that decides per call (Policy.Gate
/// HookFor). No toolset means no tool, which counts as read-only. 0 for anything that cannot be established from code.
ClassMethod ToolsetsReadOnly(toolsets As %String) As %Boolean
{
	Set readOnly = 0
	Try {
		Set readOnly = 1
		For i = 1:1:$Length(toolsets, ",") {
			Set toolset = $ZStrip($Piece(toolsets, ",", i), "<>W")
			If toolset = "" Continue
			If (toolset [ ":") || '##class(%Dictionary.CompiledClass).%ExistsId(toolset) {
				Set readOnly = 0
				Quit
			}
			Set iterator = $ClassMethod(toolset, "%New").%Discover().%Get("tools").%GetIterator()
			While iterator.%GetNext(, .tool) {
				Set source = tool.provider
				Set name = tool.name
				If (source = "") || (name = "") || (##class(OcuTalon.Bridge.Policy.Gate).HookFor(source, name) '= "") || (##class(OcuTalon.Bridge.Adapter.StepBuffer).ToolParameter(source, name, "CLASSIFICATION") '= "safe") || (##class(OcuTalon.Bridge.Adapter.StepBuffer).ToolParameter(source, name, "READONLY") '= 1) {
					Set readOnly = 0
				}
			}
			If 'readOnly Quit
		}
	} Catch {
		Set readOnly = 0
	}
	Quit readOnly
}

/// The second-model retry (AD-6, AD-8, DW-647; the method is not called Retry, which is a property of Ens.BusinessProcess), or the fallback as release 1 records it. reason is why the attempt is unusable: Classify of a precheck
/// (OnRequest, Resend), of the timer (timedOut 1) or of the reply (Conclude's retryReason); reply is the attempt's Reply, "" when there is none; failure
/// is its failure text. The retry is sent when all of these hold, and otherwise the fallback is recorded with the reason (RecordFallback; the answer is
/// in response):
///   - the request is not of kind tool, is not a model test request (Settings.IsTest), the retry has not been sent, and Retryable accepts the reason (with ToolsRun of the reply, Broken, and for a
///     timer that fired the rule of lead ruling R2);
///   - RetryItemOf names a retry runner;
///   - RetrySeconds of FirstSeconds and TimerSeconds is not 0; when it is, the fallback keeps the reason and carries RETRYSKIPPED as its reasons.
/// The retry is the RetryRequest clone, with the DecisionRef of the decision, sent to the retry runner with the key reply, after the precheck of the
/// retry runner (Precheck, whose reason is the fallback's; a reason of the retry runner, such as no_key, is the last attempt's), with the steps of
/// the reply added to StepCount and a timer of the seconds of the retry, whose controlled keys discard the reply of an attempt whose timer fired. A
/// linked turn goes through Held with the ItemId of the decision first, which skips the probe for it.
Method TryRetry(request As OcuTalon.Bridge.Msg.Request, runner As %String, reason As %String, reply As %RegisteredObject, Output response As %Persistent, failure As %String = "", timedOut As %Boolean = 0) As %Status
{
	Set response = ""
	Set kind = request.Kind
	Set isReply = $IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply")
	Set broken = ..Broken(request, failure)
	Set elapsed = ##class(OcuTalon.Bridge.Time).MsSince(..%TimeCreated)
	Set reasons = ""
	Set retryItem = ""
	If (..RetryRunner = "") && '##class(OcuTalon.Bridge.Settings).IsTest(request) && ..Retryable(reason, isReply && reply.ToolsRun, broken, kind, timedOut) {
		Set retryItem = ..RetryItemOf(runner, kind)
	}
	If (retryItem '= "") && timedOut && '..Retryable(reason, 0, 0, kind, 1, ..ToolsReadOnly(runner)) Set retryItem = ""
	If retryItem '= "" {
		Set seconds = ..RetrySeconds(..FirstSeconds, ..TimerSeconds)
		If seconds = 0 {
			Set retryItem = ""
			Set reasons = ..#RETRYSKIPPED
		}
	}
	If retryItem '= "" {
		Set limit = ..SettingText("RequestTokenLimit")
		Set clone = ..RetryRequest(request, ..DecisionRef, 0, runner, reply)
		If ##class(OcuTalon.Bridge.Adapter.Agent).IsLinked(clone) && ..Held(clone, runner, request.ItemId) {
			Set response = ##class(OcuTalon.Bridge.Msg.Reply).NewBusy()
			Quit $$$OK
		}
		Set precheck = ..Precheck(clone, retryItem, ..SettingText("DecisionTokenBudget"), limit, .estimate)
		If precheck '= "" {
			Quit ..RecordFallback(request, ..DecisionRef, precheck, reply, ..HostSinkClass, ..%SessionId, .response, elapsed, ..StepCount, broken)
		}
		Set clone.Compact = ..Flagged(request, estimate)
		Set sc = ..SendRequestAsync(retryItem, clone, 1, "reply")
		If $$$ISERR(sc) Quit sc
		Set ..RetryRunner = retryItem
		If isReply Set ..StepCount = ..StepCount + reply.AgentStepCount
		Quit ..SetTimer(seconds, "timer")
	}
	Quit ..RecordFallback(request, ..DecisionRef, reason, reply, ..HostSinkClass, ..%SessionId, .response, elapsed, ..StepCount, broken, reasons)
}

/// The milliseconds of the attempt's timer (TimerFor) that are left: the timer x 1000 minus the milliseconds since Decide began (0 at least,
/// and 0 when the start cannot be read). The request is flagged when its estimate is above COMPACTTOKENS; estimate is the one that the
/// precheck just worked out, or "" to work it out here (only a turn has one). Called for a request that is not a tool replay.
Method RemainingMs(request As OcuTalon.Bridge.Msg.Request, estimate As %Integer = "") As %Integer [ Private ]
{
	Set elapsed = ##class(OcuTalon.Bridge.Time).MsSince(..%TimeCreated)
	If elapsed = "" Quit 0
	If (estimate = "") && (request.Kind = "turn") Set estimate = ..EstimateTokens(request, ..RunnerFor(request.Kind, request))
	Set total = ..TimerFor(request, ..Flagged(request, estimate)) * 1000
	Quit $Select(total > elapsed: total - elapsed, 1: 0)
}

/// The seconds of back-off before the next re-send, or 0 for no re-send (AD-8, FR-4, NFR-23). It is pure. A re-send needs all of:
///   - reason is rate_limited (Classify of the failure text of the runner's Reply);
///   - toolsRun is false: a tool that ran may have acted, and the request is never sent again then;
///   - remainingMs, the time left of TimerSeconds, is at least 2000.
/// The delay is the least of RESENDFIRST x 2 to the power of resends (the re-sends so far), RESENDMAX and (remainingMs - 1000) \ 1000, so
/// that the last re-send still has at least a second before the timer.
ClassMethod ResendDelay(reason As %String, toolsRun As %Boolean, resends As %Integer, remainingMs As %Integer) As %Integer
{
	If ($Get(reason) '= "rate_limited") || +$Get(toolsRun) || (+$Get(remainingMs) < 2000) Quit 0
	Set steps = $Select(+$Get(resends) > 10: 10, +$Get(resends) > 0: +resends, 1: 0)
	Set delay = ..#RESENDFIRST * (2 ** steps)
	Set fits = (remainingMs - 1000) \ 1000
	If delay > ..#RESENDMAX Set delay = ..#RESENDMAX
	Quit $Select(delay > fits: fits, 1: delay)
}

/// Sends each step record of the runner's reply to the AgentSteps operation, in order, without waiting for an answer: the sends
/// inherit this process's session and super session, so that the steps sit in the caller's trace session (AD-26). The Positions start
/// after the steps of the earlier attempts of the decision (StepsSent), which then becomes the Position of the last step built, so that
/// no Position repeats, even after a record that StepMessages skipped.
/// A send that fails is a warning that names the step (its Position), the DecisionRef and the codes of its error, never the content (the
/// text of a validation error echoes the value that failed), and so is a Steps value that does not parse; nothing changes the answer.
Method EmitSteps(decisionRef As %String, reply As OcuTalon.Bridge.Msg.Reply)
{
	Try {
		Set messages = ..StepMessages(decisionRef, reply, ..StepsSent)
		If messages.Count() Set ..StepsSent = messages.GetAt(messages.Count()).Position
		For i = 1:1:messages.Count() {
			Set sc = ..SendRequestAsync(..#STEPSITEM, messages.GetAt(i), 0)
			If $$$ISERR(sc) {
				$$$LOGWARNING("Step "_messages.GetAt(i).Position_" of the decision "_decisionRef_" was not sent to "_..#STEPSITEM_" (error codes "_$SYSTEM.Status.GetErrorCodes(sc)_")")
			}
		}
	} Catch exception {
		$$$LOGWARNING("The steps of the decision "_decisionRef_" were not sent: "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
}

/// The AgentStep messages for the step records in the reply's Steps, as a list of messages in the order of the records. Position is the
/// place in the array, from offset + 1 (the steps of the earlier attempts of the decision come first), and DecisionRef is the one given.
/// No Steps, a reply of another class and a Steps value that is not a JSON array give an empty list; the last also logs a warning that
/// names the DecisionRef and not the content. A record that is not an object is skipped with the same warning.
ClassMethod StepMessages(decisionRef As %String, reply As OcuTalon.Bridge.Msg.Reply, offset As %Integer = 0) As %ListOfObjects
{
	Set messages = ##class(%ListOfObjects).%New()
	Try {
		If $IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply") && ($ZStrip(reply.Steps, "*WC") '= "") {
			Set records = ""
			Try {
				Set records = ##class(%Library.DynamicAbstractObject).%FromJSON(reply.Steps)
			} Catch {
				Set records = ""
			}
			If '$IsObject(records) || 'records.%IsA("%Library.DynamicArray") {
				$$$LOGWARNING("The steps of the decision "_decisionRef_" are not a JSON array of step records, so none is sent")
			} Else {
				Set iterator = records.%GetIterator()
				While iterator.%GetNext(.index, .record, .type) {
					If type '= "object" {
						$$$LOGWARNING("Step "_(offset + index + 1)_" of the decision "_decisionRef_" is not a step record, so it is not sent")
						Continue
					}
					Set message = ##class(OcuTalon.Bridge.Msg.AgentStep).%New()
					Set message.DecisionRef = decisionRef
					Set message.Position = offset + index + 1
					Set message.StepKind = $Extract(record.%Get("kind"), 1, 32)
					Set message.Label = $Extract(record.%Get("label"), 1, 1000)
					Set message.Summary = $Extract(record.%Get("summary"), 1, 1000)
					Set message.DurationMs = record.%Get("durationMs")
					Set message.Status = $Extract(record.%Get("status"), 1, 32)
					Set message.EstimatedTokens = record.%Get("estimatedTokens")
					Do messages.Insert(message)
				}
			}
		}
	} Catch exception {
		$$$LOGWARNING("The steps of the decision "_decisionRef_" cannot be read: "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Quit messages
}

/// OK when the message is a Request that Decide serves. A message of another class gives "not implemented"; any other problem is an
/// error that names the field: Kind (not one of Msg.Enum REQUESTKIND), Provenance (not one of PROVENANCE, and for kind tool not user),
/// ItemId (empty, and for kind tool not the Ref of an approval request), OwnerRef, Input (empty once white space and control characters are
/// removed; a request of kind tool needs none), or SessionMode (not empty, which means continue, and not one of Request SESSIONMODES; the
/// match is exact, so Fresh is refused).
ClassMethod Admit(request As %Library.Persistent) As %Status
{
	If '$IsObject(request) || 'request.%IsA("OcuTalon.Bridge.Msg.Request") Quit $$$ERROR($$$NotImplemented)
	Set kinds = ##class(OcuTalon.Bridge.Msg.Enum).#REQUESTKIND
	If '$ListFind($ListFromString(kinds), request.Kind) Quit $$$ERROR($$$GeneralError, "The Kind '"_request.Kind_"' of the request is not one of "_kinds)
	Set provenances = ##class(OcuTalon.Bridge.Msg.Enum).#PROVENANCE
	If '$ListFind($ListFromString(provenances), request.Provenance) Quit $$$ERROR($$$GeneralError, "The Provenance '"_request.Provenance_"' of the request is not one of "_provenances)
	If request.ItemId = "" Quit $$$ERROR($$$GeneralError, "The ItemId of the request is empty")
	If request.OwnerRef = "" Quit $$$ERROR($$$GeneralError, "The OwnerRef of the request is empty")
	If request.Kind = "tool" {
		If request.Provenance '= "user" Quit $$$ERROR($$$GeneralError, "The Provenance '"_request.Provenance_"' of the tool request is not user: only a call that a user approved is replayed")
		If '##class(OcuTalon.Bridge.Approval).IsRef(request.ItemId) Quit $$$ERROR($$$GeneralError, "The ItemId of the tool request is not the Ref of an approval request")
	} ElseIf $ZStrip(request.Input, "*WC") = "" {
		Quit $$$ERROR($$$GeneralError, "The Input of the request is empty, so nothing is sent")
	}
	Set modes = ##class(OcuTalon.Bridge.Msg.Request).#SESSIONMODES
	If (request.SessionMode '= "") && '$ListFind($ListFromString(modes), request.SessionMode) Quit $$$ERROR($$$GeneralError, "The SessionMode '"_request.SessionMode_"' of the request is not empty or one of "_modes)
	Quit $$$OK
}

/// The runner item of the request kind (RUNNERS), or "". For kind tool it is the Runner of the tool_call approval request that the ItemId of the
/// request names (the runner whose job held the call, DW-194), or "" when there is no such row or it names none; a developer's runner item
/// is not in RUNNERS.
ClassMethod RunnerFor(kind As %String, request As OcuTalon.Bridge.Msg.Request = "") As %String
{
	If kind = "tool" {
		If '$IsObject(request) Quit ""
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request.ItemId)
		If '$IsObject(row) || (row.Kind '= "tool_call") Quit ""
		Quit row.Runner
	}
	Set runner = ""
	Set pairs = $ListFromString(..#RUNNERS)
	Set position = 0
	While $ListNext(pairs, position, pair) {
		If $Piece(pair, ":", 1) = kind Set runner = $Piece(pair, ":", 2)
	}
	Quit runner
}

/// 1 when the Ref names an approved tool_call approval request whose ToolSource or Runner is empty: a row held before those columns existed, which
/// names no runner (or no source) that can be trusted to replay it. RunnerFor gives "" only for an empty Runner, so this also catches a row with
/// a Runner and no ToolSource, which must never be sent to a runner.
ClassMethod HeldBeforeUpdate(request As OcuTalon.Bridge.Msg.Request) As %Boolean
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request.ItemId)
	Quit $IsObject(row) && (row.Kind = "tool_call") && (row.State = "approved") && ((row.ToolSource = "") || (row.Runner = ""))
}

/// A tool request that no runner can take (RunnerFor gave "", or HeldBeforeUpdate): an approved tool_call row with an empty ToolSource or Runner
/// (a row held before those columns existed) is closed failed through FinishExecution, so that it does not stay approved for ever, and 1 is
/// returned. A missing row, a fix row and a row in any other state are never changed, and 0 is returned for them and for a close that failed
/// (a warning that names the Ref).
ClassMethod FailUnroutable(request As OcuTalon.Bridge.Msg.Request) As %Boolean
{
	Set closed = 0
	Try {
		If ..HeldBeforeUpdate(request) {
			Set sc = ##class(OcuTalon.Bridge.Approval).FinishExecution(request.ItemId, "failed")
			If $$$ISERR(sc) {
				$$$LOGWARNING("The approved tool call "_request.ItemId_" was held before an update and was not closed as failed: "_$SYSTEM.Status.GetErrorText(sc))
			} Else {
				Set closed = 1
			}
		}
	} Catch exception {
		$$$LOGWARNING("The approved tool call "_request.ItemId_" was held before an update and was not closed as failed: "_exception.DisplayString())
	}
	Quit closed
}

/// The ReplyClass setting of the runner item in the active production (OcuTalon.Bridge.Ext.Accessor.ValueFor), or "" with an error
/// in sc when it cannot be read. An empty value is returned as "" with OK; CheckSettings refuses it.
ClassMethod ReplyClassOf(runner As %String, Output sc As %Status) As %String
{
	Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ReplyClass", "", runner, .sc)
	If $$$ISERR(sc) {
		Set sc = $$$ERROR($$$GeneralError, "The ReplyClass setting of "_runner_" cannot be read: "_$SYSTEM.Status.GetErrorText(sc))
		Quit ""
	}
	Quit class
}

/// OK when the settings allow the request to be sent; otherwise an error that names the setting:
///   - timer (TimerSeconds): a whole number from MINTIMER to MAXTIMER (Timeouts.Check);
///   - filterClass (ReplyFilterClass): passes OcuTalon.Bridge.Ext.Accessor.Check, so that no text is ever recorded unfiltered;
///   - replyClass (the ReplyClass setting of the runner), for kind decide and diagnose: a compiled %JSON.Adaptor class. A
///     runner with no ReplyClass cannot answer these kinds. A turn and a tool request need no ReplyClass.
ClassMethod CheckSettings(kind As %String, runner As %String, replyClass As %String, filterClass As %String, timer As %String) As %Status
{
	Set sc = ##class(OcuTalon.Bridge.Timeouts).Check(timer)
	If $$$ISERR(sc) Quit sc
	Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).Check("ReplyFilterClass", filterClass)
	If $$$ISERR(sc) Quit sc
	Quit ..CheckReplyClass(kind, runner, replyClass)
}

/// OK when the ReplyClass of the runner suits the kind: a turn and a tool request need none; a decide or diagnose request needs a compiled %JSON.Adaptor class.
ClassMethod CheckReplyClass(kind As %String, runner As %String, replyClass As %String) As %Status
{
	If (kind = "turn") || (kind = "tool") Quit $$$OK
	If replyClass = "" {
		Quit $$$ERROR($$$GeneralError, "The runner "_runner_" has no ReplyClass setting, so a "_kind_" request cannot be sent: ReplyClass names the %JSON.Adaptor class that the reply is checked against")
	}
	If '##class(%Dictionary.CompiledClass).%ExistsId(replyClass) || '$ClassMethod(replyClass, "%Extends", "%JSON.Adaptor") {
		Quit $$$ERROR($$$GeneralError, "The ReplyClass setting of "_runner_" names '"_replyClass_"', which is not a compiled %JSON.Adaptor class")
	}
	Quit $$$OK
}

/// Checks the reply text against the class: one JSON object that the class imports (%JSONImport, with exceptions caught) and
/// validates (%ValidateObject). A reply class's %OnValidateObject may read the request through OcuTalon.Bridge.ReplyCheck, which Interpret begins. Only surrounding white space, or one surrounding Markdown code fence, is removed first.
/// payload is the validated object, or "" with an error that names the reply check. cause is the status of the import or the validation before it is
/// wrapped ($$$OK when the reply passes): RefusalText turns it into words that quote nothing of the reply.
ClassMethod CheckReply(text As %String, replyClass As %String, Output payload As %RegisteredObject, Output cause As %Status) As %Status
{
	Set payload = ""
	Set cause = $$$OK
	Try {
		Set object = $ClassMethod(replyClass, "%New")
		Set sc = object.%JSONImport(..Unfenced(text))
		If $$$ISOK(sc) Set sc = object.%ValidateObject()
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		Set cause = sc
		Quit $$$ERROR($$$GeneralError, ..#CHECKFAILED_replyClass_" accepts: "_$Extract($SYSTEM.Status.GetErrorText(sc), 1, 400))
	}
	Set payload = object
	Quit $$$OK
}

/// The words of the errors of a failed reply check (cause, from CheckReply, or the status of the second check), for the warning that Conclude logs. Each part is
/// made only of fixed words, an error code, the name of a compiled property of replyClass, an element position, a numeric limit and a computed length: never a
/// value of the reply, an IRIS message text or a field name taken from the reply. The parts, in DecomposeStatus order and without repeats:
///   - a text over or under its limit (#7201, #7202) and a value outside its limits (#7203, #7204), with a property and a numeric limit, give
///     "<Property>[ element <n>]: <length> > <limit>" (the length of the value, never the value) and "<Property>[ element <n>]: value > <limit>"; the property and
///     the position come from the embedded #5802 (or a #5659) as "<class>:<Property>[(<n>)]", and only a name that replyClass compiles is used;
///   - an import error that names a JSON field (#9406) is traced to the property of replyClass with that field name, and the reply text (a JSON object) is
///     checked the way the property would be: every element of a list, or the value, by the property's own <Property>IsValid check, which gives the forms above;
///     an element of a list that is an object or an array gives "ERROR #9406 on <Property> element <n>"; with no failing check, or a value of another shape (an
///     object or an array for a scalar, no array for a list, a reply that is not a JSON object), "ERROR #9406 on <Property>"; with no such property, "ERROR #9406";
///   - a field that replyClass does not have (#9404) is "ERROR #9404: an unexpected property": the field's name came from the reply, so it is never given;
///   - any other error is "ERROR #<code>" (or "ERROR <code>" for a code of the form "<Domain>Name", else "ERROR"), and " on <Property>[ element <n>]" when a
///     property is known.
/// At most 5 parts are given, then "; and <k> more". With no part, or if anything throws, the text is "an error". text is the reply text that CheckReply checked.
ClassMethod RefusalText(cause As %Status, replyClass As %String, text As %String = "") As %String
{
	Set result = "an error"
	Try {
		Set count = 0
		If $$$ISERR(cause) {
			Do $SYSTEM.Status.DecomposeStatus(cause, .errors)
			For i = 1:1:+$Get(errors) {
				Set code = $Get(errors(i, "code"))
				Set property = ""
				Set position = ""
				If (code = 5659) || (code = 5802) Do ..RefusalProperty(replyClass, $Get(errors(i, "param", 1)), .property, .position)
				If $Data(errors(i, "embeddedstatus")) {
					Kill inner
					Do $SYSTEM.Status.DecomposeStatus(errors(i, "embeddedstatus"), .inner)
					For j = 1:1:+$Get(inner) {
						If $Get(inner(j, "code")) = 5802 {
							Do ..RefusalProperty(replyClass, $Get(inner(j, "param", 1)), .property, .position)
							Quit
						}
					}
				}
				If code = 9406 {
					Do ..RefusalImport(replyClass, $Get(errors(i, "param", 1)), text, .parts, .count)
				} Else {
					Do ..RefusalAdd(..RefusalPart(code, $Get(errors(i, "param", 1)), $Get(errors(i, "param", 2)), property, position), .parts, .count)
				}
			}
		}
		If count > 0 {
			Set shown = $Select(count > ..#MAXREFUSALPARTS: ..#MAXREFUSALPARTS, 1: count)
			Set result = ""
			For i = 1:1:shown Set result = result _ $Select(i > 1: "; ", 1: "") _ parts(i)
			If count > shown Set result = result_"; and "_(count - shown)_" more"
		}
	} Catch exception {
		Set result = "an error"
	}
	Quit result
}

/// The words that begin the message of a failed reply check, before the reply class: CheckReply's error and Judge's problem share them.
Parameter CHECKFAILED = "The reply check failed: the reply is not one JSON object that ";

/// The most parts that RefusalText names before "and <k> more".
Parameter MAXREFUSALPARTS = 5;

/// Adds the part to parts(1..count) unless it is there already.
ClassMethod RefusalAdd(part As %String, ByRef parts, ByRef count) [ Private ]
{
	If $Data(parts("seen", part)) Quit
	Set parts("seen", part) = ""
	Set count = count + 1
	Set parts(count) = part
}

/// The property and the position of "<class>:<Property>" or "<class>:<Property>(<n>)" (the first parameter of #5802 and #5659), each "" unless the
/// property is compiled in replyClass and the position is a whole number.
ClassMethod RefusalProperty(replyClass As %String, field As %String, Output property As %String, Output position As %String) [ Private ]
{
	Set property = ""
	Set position = ""
	Set name = $Piece(field, ":", 2, *)
	If name = "" Quit
	If ($Extract(name, *) = ")") && (name [ "(") {
		Set inner = $Piece($Piece(name, "(", 2, *), ")", 1)
		Set name = $Piece(name, "(", 1)
		If inner '? 1.N Quit
		Set position = +inner
	}
	If '##class(%Dictionary.CompiledProperty).%ExistsId(replyClass_"||"_name) {
		Set position = ""
		Quit
	}
	Set property = name
}

/// 1 when the text is a plain number: digits, with an optional sign and decimal part.
ClassMethod RefusalNumber(value As %String) As %Boolean [ Private ]
{
	Quit value ? .1"-"1.N.1(1".".N)
}

/// The words of one error: see RefusalText.
ClassMethod RefusalPart(code As %String, value As %String, limit As %String, property As %String, position As %String) As %String [ Private ]
{
	Set label = property
	If (label '= "") && (position '= "") Set label = label_" element "_position
	If (label '= "") && ..RefusalNumber(limit) {
		If (code = 7201) || (code = 7202) Quit label_": "_$Length(value)_$Select(code = 7201: " > ", 1: " < ")_limit
		If (code = 7203) || (code = 7204) Quit label_": value"_$Select(code = 7203: " > ", 1: " < ")_limit
	}
	Set text = "ERROR"
	If code ? 1.N {
		Set text = text_" #"_code
		If code = 9404 Quit text_": an unexpected property"
	} ElseIf code ? 1"<"1.AN1">"1.AN {
		Set text = text_" "_code
	}
	If label '= "" Set text = text_" on "_label
	Quit text
}

/// The parts of an import error (#9406) that names the JSON field: see RefusalText.
ClassMethod RefusalImport(replyClass As %String, field As %String, text As %String, ByRef parts, ByRef count) [ Private ]
{
	Set property = ""
	Set collection = ""
	Set type = ""
	Set class = ##class(%Dictionary.CompiledClass).%OpenId(replyClass)
	If $IsObject(class) {
		For i = 1:1:class.Properties.Count() {
			Set candidate = class.Properties.GetAt(i)
			Set name = candidate.Name
			If ($Extract(name) = "%") || candidate.Private || candidate.Internal Continue
			Set included = $ZConvert(candidate.Parameters.GetAt("%JSONINCLUDE"), "L")
			If (included = "none") || (included = "outputonly") Continue
			Set json = candidate.Parameters.GetAt("%JSONFIELDNAME")
			If json = "" Set json = name
			If json = field {
				Set property = name
				Set collection = candidate.Collection
				Set type = candidate.Type
				Quit
			}
		}
	}
	If property = "" {
		Do ..RefusalAdd("ERROR #9406", .parts, .count)
		Quit
	}
	Set found = 0
	Try {
		Set object = {}.%FromJSON(..Unfenced(text))
		If $ClassMethod(type, "%Extends", "%Library.DataType") && object.%IsA("%Library.DynamicObject") {
			Set kind = object.%GetTypeOf(field)
			If (collection = "list") && (kind = "array") {
				Set array = object.%Get(field)
				For k = 1:1:array.%Size() {
					Set elementKind = array.%GetTypeOf(k - 1)
					If (elementKind = "object") || (elementKind = "array") {
						Do ..RefusalAdd("ERROR #9406 on "_property_" element "_k, .parts, .count)
						Set found = found + 1
					} Else {
						Set found = found + ..RefusalCheck(replyClass, property, array.%Get(k - 1), k, .parts, .count)
					}
				}
			} ElseIf (collection = "") && (kind '= "object") && (kind '= "array") && (kind '= "unassigned") {
				Set found = found + ..RefusalCheck(replyClass, property, object.%Get(field), "", .parts, .count)
			}
		}
	} Catch exception {
	}
	If 'found Do ..RefusalAdd("ERROR #9406 on "_property, .parts, .count)
}

/// Checks one value with the property's own <Property>IsValid and adds the parts of its errors; the number of errors.
ClassMethod RefusalCheck(replyClass As %String, property As %String, value As %String, position As %String, ByRef parts, ByRef count) As %Integer [ Private ]
{
	Set sc = $ClassMethod(replyClass, property_"IsValid", value)
	If $$$ISOK(sc) Quit 0
	Do $SYSTEM.Status.DecomposeStatus(sc, .errors)
	For i = 1:1:+$Get(errors) {
		Do ..RefusalAdd(..RefusalPart($Get(errors(i, "code")), $Get(errors(i, "param", 1)), $Get(errors(i, "param", 2)), property, position), .parts, .count)
	}
	Quit +$Get(errors)
}

/// The text without surrounding white space, and without one surrounding Markdown code fence: three backticks and an optional
/// language word on the first line, and three backticks at the end.
ClassMethod Unfenced(text As %String) As %String
{
	Set trimmed = $ZStrip(text, "<>WC")
	Set fence = $Char(96, 96, 96)
	Set length = $Length(trimmed)
	If (length < 6) || ($Extract(trimmed, 1, 3) '= fence) || ($Extract(trimmed, length - 2, length) '= fence) Quit trimmed
	Set inner = $Extract(trimmed, 4, length - 3)
	Set lines = $Length(inner, $Char(10))
	If lines > 1 {
		Set first = $ZStrip($Piece(inner, $Char(10), 1), "<>WC")
		If first ? .(1A,1N,1"-",1"_") Set inner = $Piece(inner, $Char(10), 2, lines)
	}
	Quit $ZStrip(inner, "<>WC")
}

/// The FallbackReason of a request that must not be sent, or "" (AD-8, AD-20). The facts are the model key (Keys.Absent of the runner
/// item: only a key that the bridge can tell is absent, live in this process, blocks a request), the daily cost cap (Budget.State:
/// capped), the estimate of the request (EstimateTokens, worked out once and given back in estimate) against tokenBudget (the
/// DecisionTokenBudget setting as it is) and against requestLimit (the RequestTokenLimit setting as it is), and Classify picks the
/// reason. Each fault that State names (DW-76) is logged as one warning, and so is a tokenBudget that is not
/// a whole number of 0 or more, which counts as 0 (off; empty is 0 too). A requestLimit that is a whole number from 1 to
/// MAXREQUESTTOKENS is the limit; an empty one counts as MAXREQUESTTOKENS, and any other one counts as MAXREQUESTTOKENS and is logged as
/// one warning that names RequestTokenLimit, so the limit is never off and never above MAXREQUESTTOKENS (RequestLimit). One more warning
/// names the runner when the system prompt or the tool schemas of its agent could not be read in full (a part that could not be read counts
/// 0). A turn that is flagged for compaction (Flagged) and continues its conversation is judged for too_large on the request of the
/// runner's seeded path: its characters with the stored history counted as the least of the history and Compaction.#SEEDCHARS (AD-8,
/// AD-20); the runner checks the session as it stands and the fork against the limit itself. The token budget and the estimate that it
/// gives back keep the full estimate. The second-model retry of a linked turn is judged on its clone, which carries its seed (RetryRequest) and is fresh. Nothing is
/// sent or recorded here.
ClassMethod Precheck(request As OcuTalon.Bridge.Msg.Request, runner As %String, tokenBudget As %String, requestLimit As %String = "", Output estimate As %Integer) As %String
{
	Set facts = {}
	Do facts.%Set("noKey", ##class(OcuTalon.Bridge.Keys).Absent(runner), "boolean")
	Set state = ##class(OcuTalon.Bridge.Budget).State(, .faults)
	Do facts.%Set("capped", +state.%Get("capped"), "boolean")
	Set iterator = faults.%GetIterator()
	While iterator.%GetNext(, .fault) {
		$$$LOGWARNING("The daily cost cap may count less than it was set to: "_fault)
	}
	Set budget = 0
	If tokenBudget '= "" {
		If tokenBudget ? 1.N {
			Set budget = +tokenBudget
		} Else {
			$$$LOGWARNING(##class(OcuTalon.Bridge.Redact).Text("The setting DecisionTokenBudget of Decide is '"_$Extract(tokenBudget, 1, 40)_"'; it must be a whole number of 0 or more, so the token budget counts as 0 (off)"))
		}
	}
	Set limit = ..RequestLimit(requestLimit, .limitWarning)
	If limitWarning '= "" $$$LOGWARNING(##class(OcuTalon.Bridge.Redact).Text(limitWarning))
	Set estimate = ..EstimateTokens(request, runner, , .sc, .history, .chars)
	If $$$ISERR(sc) {
		$$$LOGWARNING(##class(OcuTalon.Bridge.Redact).Text("The system prompt or the tool schemas of "_runner_" could not be read in full, so the estimate of the request may count too few tokens: "_$SYSTEM.Status.GetErrorText(sc)))
	}
	Do facts.%Set("overBudget", (budget > 0) && (estimate > budget), "boolean")
	Set bound = estimate
	If ..Flagged(request, estimate) && (history > 0) Set bound = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Tokens(chars - history + $Select(history < ##class(OcuTalon.Bridge.Compaction).#SEEDCHARS: history, 1: ##class(OcuTalon.Bridge.Compaction).#SEEDCHARS))
	Do facts.%Set("tooLarge", bound > limit, "boolean")
	Quit ..Classify(facts)
}

/// The request-size limit in tokens that the text of the RequestTokenLimit setting gives (AD-8, AD-20), for Precheck and for the runner's
/// compaction (Adapter.Agent), so that both read it alike: a whole number from 1 to MAXREQUESTTOKENS is the limit; an empty text counts as
/// MAXREQUESTTOKENS; any other text counts as MAXREQUESTTOKENS too, and warning then holds the text of the warning that names the setting
/// (cut to 40 characters, not redacted: the caller logs it through Redact.Text), otherwise warning is "". It is pure.
ClassMethod RequestLimit(text As %String = "", Output warning As %String) As %Integer
{
	Set warning = ""
	Set limit = ..#MAXREQUESTTOKENS
	If text '= "" {
		If (text ? 1.N) && (+text > 0) && (+text '> ..#MAXREQUESTTOKENS) {
			Set limit = +text
		} Else {
			Set warning = "The setting RequestTokenLimit of Decide is '"_$Extract(text, 1, 40)_"'; it must be a whole number from 1 to "_..#MAXREQUESTTOKENS_", so the request-size limit counts as "_..#MAXREQUESTTOKENS
		}
	}
	Quit limit
}

/// The estimated size in tokens of the first model request that the runner makes for the request (AD-6, AD-20): StepBuffer.Tokens of the
/// sum of three parts, at StepBuffer.CHARSPERTOKEN characters a token, rounded up.
///   1. The agent part: RequestSize.AgentChars of agentClass, the system prompt and the tool schemas of the agent. An empty agentClass
///      means the AgentClass setting of the runner item (Ext.Accessor ValueFor, a setting of the adapter).
///   2. The history: RequestSize.HistoryChars of the session that the conversation link of the request's OwnerRef and the runner names
///      (Data.ConversationLink SessionOf), only for a linked turn (Adapter.Agent IsLinked) whose SessionMode is not fresh. It is 0 for
///      every other request, and for a turn with no link. The second-model retry of such a turn is a fresh turn whose SeedText carries the recap
///      (RetryRequest), so it is counted as part 3. The request's own RetryOf is never read, so a RetryOf that a caller set changes nothing.
///   3. The input: the length of what the runner sends (Adapter.Agent ChatInput), with the seed only on a linked fresh turn.
/// history is the characters of part 2 and chars the characters of the whole sum, which Precheck weighs for a flagged turn. sc is an error
/// when the agent part could not be read in full: the setting cannot be read or the class is unknown (the part counts 0), or its
/// INSTRUCTIONS or a toolset cannot be read (that piece counts 0 and the rest is counted, RequestSize.AgentChars).
ClassMethod EstimateTokens(request As OcuTalon.Bridge.Msg.Request, runner As %String, agentClass As %String = "", Output sc As %Status, Output history As %Integer, Output chars As %Integer) As %Integer
{
	Set sc = $$$OK
	Set chars = 0
	Set history = 0
	If agentClass = "" Set agentClass = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("AgentClass", "", runner, .sc, "Adapter")
	If $$$ISOK(sc) Set chars = ##class(OcuTalon.Bridge.RequestSize).AgentChars(agentClass, .sc)
	Set linked = ##class(OcuTalon.Bridge.Adapter.Agent).IsLinked(request)
	Set fresh = linked && (request.SessionMode = "fresh")
	If linked && 'fresh {
		Set history = ##class(OcuTalon.Bridge.RequestSize).HistoryChars(##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(request.OwnerRef, runner))
	}
	Set chars = chars + history
	Set chars = chars + $Length(##class(OcuTalon.Bridge.Adapter.Agent).ChatInput(request, fresh))
	Quit ##class(OcuTalon.Bridge.Adapter.StepBuffer).Tokens(chars)
}

/// The one classification (AD-8): "" when the request and the reply are usable, otherwise exactly one value of Msg.Enum FALLBACKREASON.
/// It is pure: it reads the facts and nothing else, and a fact that is missing counts as false or empty, so that no facts give "". The facts
/// of a dynamic object:
///   - noKey, capped, overBudget and tooLarge: booleans from the precheck;
///   - timedOut, a boolean, and resends, the number of times Decide sent the request again: the timer of an attempt fired;
///   - failure: the redacted text of a runner failure;
///   - finishReason and text: the runner's Reply;
///   - invalid: a boolean, true when the reply failed its ReplyClass check or nothing was left of it once the filter had run.
/// The first rule that holds wins:
///   1. noKey gives no_key, then capped gives daily_cap, then overBudget gives budget, then tooLarge gives too_large;
///   2. timedOut gives rate_limited when resends is above 0 (the retries ran out, FR-4), else timeout, whatever else the facts hold;
///   3. a failure is matched by its text, without regard to case: DAILYCAPTEXT gives daily_cap; NOKEYTEXT (both pieces) gives no_key;
///      TIMEOUTTEXT gives timeout; RATELIMITTEXT gives rate_limited (OnResponse weighs a re-send before it asks for the reason);
///      one of ITERATIONCODES gives unusable; anything else gives error;
///   4. finishReason refusal gives refusal, and max_tokens gives cut_off, because a cut-off reply is never an answer (NFR-5);
///   5. a text fact that is blank once white space and control characters are removed gives empty when finishReason is not empty,
///      and unusable when it is, because a provider that reports no stop reason cannot tell an empty reply from a refusal or a cut-off
///      (with no text fact at all there is no reply to judge, so the rule does not apply);
///   6. a reply that has text and a finishReason that is not empty, is not refusal or max_tokens and is not one of FINISHED (compared without
///      regard to case) gives unusable, because the bridge cannot tell what the provider's other stop reasons (pause_turn, content_filter,
///      length, SAFETY) mean, and such a reply is never an answer;
///   7. invalid gives invalid.
ClassMethod Classify(facts As %DynamicObject) As %String
{
	If '$IsObject($Get(facts)) Quit ""
	If +facts.%Get("noKey") Quit "no_key"
	If +facts.%Get("capped") Quit "daily_cap"
	If +facts.%Get("overBudget") Quit "budget"
	If +facts.%Get("tooLarge") Quit "too_large"
	If +facts.%Get("timedOut") Quit $Select(+facts.%Get("resends") > 0: "rate_limited", 1: "timeout")
	Set failure = $ZConvert(facts.%Get("failure"), "L")
	If failure '= "" {
		If failure [ $ZConvert(..#DAILYCAPTEXT, "L") Quit "daily_cap"
		If ..HoldsAll(failure, ..#NOKEYTEXT) Quit "no_key"
		If failure [ $ZConvert(..#TIMEOUTTEXT, "L") Quit "timeout"
		If failure [ $ZConvert(..#RATELIMITTEXT, "L") Quit "rate_limited"
		Set iterations = 0
		For i = 1:1:$Length(..#ITERATIONCODES, ",") {
			Set code = $ZConvert($ZStrip($Piece(..#ITERATIONCODES, ",", i), "<>W"), "L")
			If (code '= "") && (failure [ code) Set iterations = 1
		}
		If iterations Quit "unusable"
		Quit "error"
	}
	Set finishReason = facts.%Get("finishReason")
	If finishReason = "refusal" Quit "refusal"
	If finishReason = "max_tokens" Quit "cut_off"
	If facts.%IsDefined("text") && ($ZStrip(facts.%Get("text"), "*WC") = "") Quit $Select(finishReason '= "": "empty", 1: "unusable")
	If facts.%IsDefined("text") && (finishReason '= "") && '$ListFind($ListFromString(..#FINISHED, ","), $ZConvert(finishReason, "L")) Quit "unusable"
	If +facts.%Get("invalid") Quit "invalid"
	Quit ""
}

/// 1 when the failure of a request says that the provider rejected the stored history of the conversation (AD-8): the request is linked to
/// a conversation (the runner's own rule, Adapter.Agent IsLinked: a turn with provenance user, the only kind with a stored history), and the
/// failure text holds INVALIDINPUTTEXT, without regard to case. It is pure, and it does not classify: the reason of such a failure stays what
/// Classify gives (error).
ClassMethod Broken(request As OcuTalon.Bridge.Msg.Request, failure As %String) As %Boolean
{
	If '##class(OcuTalon.Bridge.Adapter.Agent).IsLinked(request) Quit 0
	Quit $ZConvert($Get(failure), "L") [ $ZConvert(..#INVALIDINPUTTEXT, "L")
}

/// 1 when the (lower case) text holds every piece of the pieces, which are separated by | and compared in lower case.
ClassMethod HoldsAll(text As %String, pieces As %String) As %Boolean [ Private ]
{
	Set holds = 1
	For i = 1:1:$Length(pieces, "|") {
		If text '[ $ZConvert($Piece(pieces, "|", i), "L") Set holds = 0
	}
	Quit holds
}

/// Turns the runner's reply into the recorded decision and the answer, in this order:
///   1. works out the facts of Classify: the failure (the text the runner failed with; with none, a reply that is not a Reply is the
///      failure "The runner gave no Reply"), the reply's finishReason and text, and invalid, which is true when the reply fails its check
///      or nothing is left of it once the filter has run. For decide and diagnose, the check is CheckReply against replyClass; for a
///      turn, the text itself. A model test request of kind decide or diagnose (Settings.IsTest) is a connection test: its reply is never
///      checked, filtered or weighed against replyClass, so it is never invalid, and it is usable when its text is not empty once white space and control
///      characters are stripped (Classify still reads the failure, the finish reason and an empty text);
///   2. calls Classify once. A reason goes to RecordFallback, which records the fallback and answers (below); for an invalid decide or diagnose
///      reply, what the check refused (problem, see Interpret: RefusalText's words, never the reply) is first logged, redacted, as one warning in the decision's trace session.
///      With retry 1 (a retry runner is set and not yet used, RetryConfigured) a reason that Retryable accepts for the reply (its ToolsRun, Broken) is not
///      recorded: Conclude records nothing, answers nothing, and gives the reason in retryReason, and the caller sends the retry (TryRetry);
///   3. otherwise, the reply is usable. The reply of a model test request of kind decide or diagnose keeps no model text: its row has the outcome
///      tellnow, Fallback 0 and no reasons, confidence or payload, and steps 4 to 9 follow with those values. Otherwise each model-written text was filtered once with filterClass (each reason; each property that
///      the reply class names in its FILTERED parameter that is not empty, each item of a list, after which the payload is validated again; a
///      turn's reply text),
///      never the code-written line (a turn's filter call also gets the reply's HostData as its second argument, Story 19.4 and AD-31: the decide and diagnose calls get none); each reason is one line of the row: its line breaks (CR LF, CR, LF, vertical tab, form feed, NEL and
///      the Unicode line and paragraph separators) become spaces, and a reason that is blank once trimmed of white space and control
///      characters is dropped; a decision with no reason left, and a turn with no text left, once filtered, are invalid;
///   4. applies the user rule: for a decide request with provenance user, an ignore or digest becomes tellnow, and the first
///      reason line says so (USERANSWERED);
///   5. answers from the row that another call saved first for the item and kind, if there is one, and fires no event;
///   6. saves one Decision row (Record), with the confidence rounded to two decimals, traceSessionId as TraceSessionId and the
///      totals of the decision: the sums of the Usage rows of decisionRef (Usage.Totals), the reply's AgentStepCount added to stepCount
///      (the steps of the earlier attempts) and durationMs (whole milliseconds, "" when unknown);
///   7. for a linked turn, points the conversation link at the session the reply names (PointLink), the one place where a link moves; this is
///      the acceptance of the reply, and only a row that this call saved gets here, so a reply that another call's row superseded moves nothing;
///   8. fires decision.recorded after the save (FireEvent);
///   9. builds the DecisionResponse, or a clone of the Reply with the filtered Text, the DecisionRef, the outcome tellnow, the SessionRotated
///      that PointLink gave and the row's totals (CarryTotals), and with no Steps (Decide sent them), no FailureText and no SessionId,
///      SessionFrom or HistoryCount.
///   10. for a turn, calls Accepted of the ContentClass setting once with the filtered text (Accept) and adds the members it gives to the HostData of
///      the response; a failure there is a warning and the response stays as built.
/// runner is the first runner of the request, the agent of the link (RunnerFor of the request when it is empty).
/// An unusable reply is recorded and answered by RecordFallback; only a filter class that fails its check, a row that cannot be saved
/// and a payload that cannot be exported end with an error status.
ClassMethod Conclude(request As OcuTalon.Bridge.Msg.Request, decisionRef As %String, reply As OcuTalon.Bridge.Msg.Reply, replyClass As %String, filterClass As %String, sinkClass As %String, traceSessionId As %Integer, Output response As %Persistent, durationMs As %Integer = "", failure As %String = "", stepCount As %Integer = 0, retry As %Boolean = 0, Output retryReason As %String, runner As %String = "") As %Status
{
	Set retryReason = ""
	Set response = ""
	Set kind = request.Kind
	Set turn = (kind = "turn")
	Set test = 'turn && ##class(OcuTalon.Bridge.Settings).IsTest(request)
	Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).Check("ReplyFilterClass", filterClass)
	If $$$ISERR(sc) Quit sc
	Set isReply = $IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply")
	If (failure = "") && 'isReply Set failure = "The runner gave no Reply"
	If kind = "tool" Quit ..ConcludeTool(request, decisionRef, reply, sinkClass, traceSessionId, .response, durationMs, failure, stepCount)
	Set facts = {}
	Do facts.%Set("failure", failure)
	Set text = ""
	Set outcome = "tellnow"
	Set reasons = ""
	Set confidence = ""
	Set json = ""
	Set problem = ""
	If isReply {
		Do facts.%Set("finishReason", reply.FinishReason)
		Do facts.%Set("text", reply.Text)
		Set invalid = 0
		If $ZStrip(reply.Text, "*WC") '= "" {
			If turn {
				Set text = $ClassMethod(filterClass, "Filter", reply.Text, reply.HostData)
				If $ZStrip(text, "*WC") = "" Set invalid = 1
			} ElseIf 'test {
				Set invalid = '..Interpret(request, reply.Text, replyClass, filterClass, .outcome, .reasons, .confidence, .json, .sc, .problem)
			}
		}
		Do facts.%Set("invalid", invalid, "boolean")
	}
	If $$$ISERR(sc) Quit sc
	Set reason = ..Classify(facts)
	If reason '= "" {
		If (reason = "invalid") && (problem '= "") $$$LOGWARNING(##class(OcuTalon.Bridge.Redact).Text("The reply check refused the reply of the decision "_decisionRef_": "_problem))
		If retry && ..Retryable(reason, isReply && reply.ToolsRun, ..Broken(request, failure), kind) {
			Set retryReason = reason
			Quit $$$OK
		}
		Quit ..RecordFallback(request, decisionRef, reason, reply, sinkClass, traceSessionId, .response, durationMs, stepCount, ..Broken(request, failure))
	}
	If ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(request.ItemId, kind, .id) {
		Quit ..ResponseFromId(id, .response)
	}
	Set row = ..NewRow(request, decisionRef, reply, traceSessionId, durationMs, stepCount)
	Set row.Outcome = outcome
	Set row.Reasons = reasons
	Set row.Confidence = confidence
	Set row.Fallback = 0
	Set row.FallbackReason = ""
	Set row.Payload = json
	Set sc = ..Record(row, .saved, .response)
	If $$$ISERR(sc) || 'saved Quit sc
	Set rotated = 0
	If turn Do ..PointLink(request, $Select(runner '= "": runner, 1: ..RunnerFor(kind, request)), reply, .rotated, decisionRef)
	Do ..FireEvent(sinkClass, request.OwnerRef, decisionRef)
	If turn {
		Set response = reply.%ConstructClone()
		Set response.Text = text
		Set response.DecisionRef = decisionRef
		Set response.Outcome = outcome
		Set response.Steps = ""
		Set response.FailureText = ""
		Set response.SessionId = ""
		Set response.SessionFrom = ""
		Set response.HistoryCount = ""
		Set response.SessionRotated = rotated
		Do ..CarryTotals(row, response)
		Do ..Accept(request, text, response)
		Quit $$$OK
	}
	Quit ..ResponseFromRow(row, .response)
}

/// Tells the ContentClass setting of the Decide item (Ext.Content, AD-31) of the accepted turn reply, once, after Conclude saved the Decision row, and adds
/// the members that its Accepted gives to the HostData of the response (HostData.Merge). The class is read through Ext.Accessor each time, so the
/// runner and Decide agree. A setting that is not usable, an error status and an exception are one warning that names the DecisionRef and nothing is merged:
/// the reply is never failed by it.
ClassMethod Accept(request As OcuTalon.Bridge.Msg.Request, text As %String, response As OcuTalon.Bridge.Msg.Reply) [ Private ]
{
	Set decisionRef = response.DecisionRef
	Try {
		Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("ContentClass", "", "Decide", .sc)
		If $$$ISOK(sc) Set sc = $ClassMethod(class, "Accepted", request, text, .hostData)
		If $$$ISERR(sc) {
			$$$LOGWARNING("The ContentClass of the decision "_decisionRef_" did not accept the reply, so the reply goes out as it is: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
			Quit
		}
		Set response.HostData = ##class(OcuTalon.Bridge.HostData).Merge(response.HostData, $Get(hostData))
	} Catch exception {
		$$$LOGWARNING("The ContentClass of the decision "_decisionRef_" failed on the reply, so the reply goes out as it is: "_##class(OcuTalon.Bridge.Redact).Text($Extract(exception.DisplayString(), 1, 300)))
	}
}

/// The one place where a conversation link moves (AD-6, AD-8, DW-729, DW-730). Conclude calls it for a linked turn (Adapter.Agent IsLinked) after it
/// saved the Decision row of a usable reply, which is Decide's acceptance of the reply as the decision's answer. runner is the first runner, the agent of
/// the link for both attempts of a decision. When the reply is not tainted and names a saved AI session (SessionId) other than the one the link named
/// when the runner began (SessionFrom), it calls Data.ConversationLink Point as a compare-and-set that expects SessionFrom: the link moves only while
/// it still names that session ("" for no link). rotated says that the conversation now continues in another AI session: 1 when the link moved and
/// either SessionFrom was not empty or the request is a fresh turn, otherwise 0 (a continue turn, the first link of a continue turn, a link that did not
/// move). A reply that names no session, a tainted one, and a session that is its own SessionFrom move nothing. A lost compare-and-set (the link no
/// longer names SessionFrom) and a Point that fails are each one warning that names the runner, the OwnerRef and the DecisionRef (decisionRef, else the
/// request's), never an error of the answer: it stands and rotated is 0. The status is Point's, for a caller that wants it.
ClassMethod PointLink(request As OcuTalon.Bridge.Msg.Request, runner As %String, reply As OcuTalon.Bridge.Msg.Reply, Output rotated As %Boolean, decisionRef As %String = "") As %Status
{
	Set rotated = 0
	If '##class(OcuTalon.Bridge.Adapter.Agent).IsLinked(request) || '$IsObject(reply) || reply.Tainted || (reply.SessionId = "") || (reply.SessionId = reply.SessionFrom) Quit $$$OK
	Set moved = 0
	Set sc = $$$OK
	Try {
		Set sc = ##class(OcuTalon.Bridge.Data.ConversationLink).Point(request.OwnerRef, runner, reply.SessionId, reply.SessionFrom, .moved)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Set ref = $Select(decisionRef '= "": decisionRef, 1: request.DecisionRef)
	If $$$ISERR(sc) {
		$$$LOGWARNING(##class(OcuTalon.Bridge.Redact).Text("The conversation link of "_runner_" for the OwnerRef "_request.OwnerRef_" and the decision "_ref_" is not moved: "_$SYSTEM.Status.GetErrorText(sc)))
	} ElseIf 'moved {
		$$$LOGWARNING("The conversation link of "_runner_" for the OwnerRef "_request.OwnerRef_" and the decision "_ref_" is not moved, because it no longer names the AI session the turn began with")
	}
	Set rotated = $Get(moved) && ((reply.SessionFrom '= "") || (request.SessionMode = "fresh"))
	Quit sc
}

/// Conclude for kind tool: the reply of a replay holds no model text, so nothing is classified, filtered or checked. A failure (the text of the
/// runner's failure, or of a Reply whose FailureText is set) is a fallback with the reason error (RecordFallback), whatever the text says, so
/// that a tool's own error text never marks the day as capped. The one exception is a failure that holds both pieces of NOKEYTEXT in a Reply whose
/// ToolsRun is 0 (the agent could not be built and the call did not run): its reason is no_key (AD-8) and its Reasons is REPLAYNOKEY. A failure that
/// holds PROVIDERTEXT in such a Reply (the provider object could not be built for another reason) keeps the reason error and has the Reasons
/// REPLAYPROVIDER. A failure while the approval row is still approved means the run never started
/// (the row's lock was not taken): no Decision row is recorded, so that a later replay of the row is not answered from a fallback, and the answer
/// is a Reply that holds only the FailureText. Otherwise one Decision row is saved with the outcome act, no reasons, no
/// confidence and no payload, decision.recorded is fired after the save (FireEvent), and the answer is the row's Reply (ResponseFromRow). A
/// row that another call saved first for the item is answered instead and fires nothing.
ClassMethod ConcludeTool(request As OcuTalon.Bridge.Msg.Request, decisionRef As %String, reply As OcuTalon.Bridge.Msg.Reply, sinkClass As %String, traceSessionId As %Integer, Output response As %Persistent, durationMs As %Integer, failure As %String, stepCount As %Integer) As %Status [ Private ]
{
	Set response = ""
	If failure '= "" {
		If ..StillApproved(request.ItemId) {
			Set response = ##class(OcuTalon.Bridge.Msg.Reply).%New()
			Set response.FailureText = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Part(failure, ##class(OcuTalon.Bridge.Msg.Reply).#MAXFAILURE)
			Quit $$$OK
		}
		Set reason = "error"
		Set reasons = ""
		If ..HoldsAll($ZConvert(failure, "L"), ..#NOKEYTEXT) && $IsObject(reply) && (reply.ToolsRun = 0) {
			Set reason = "no_key"
			Set reasons = ..#REPLAYNOKEY
		} ElseIf ..HoldsAll($ZConvert(failure, "L"), ..#PROVIDERTEXT) && $IsObject(reply) && (reply.ToolsRun = 0) {
			Set reasons = ..#REPLAYPROVIDER
		}
		Quit ..RecordFallback(request, decisionRef, reason, reply, sinkClass, traceSessionId, .response, durationMs, stepCount, 0, reasons)
	}
	If ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(request.ItemId, request.Kind, .id) {
		Quit ..ResponseFromId(id, .response)
	}
	Set row = ..NewRow(request, decisionRef, reply, traceSessionId, durationMs, stepCount)
	Set row.Outcome = "act"
	Set row.Reasons = ""
	Set row.Confidence = ""
	Set row.Fallback = 0
	Set row.FallbackReason = ""
	Set row.Payload = ""
	Set sc = ..Record(row, .saved, .response)
	If $$$ISERR(sc) || 'saved Quit sc
	Do ..FireEvent(sinkClass, request.OwnerRef, decisionRef)
	Quit ..ResponseFromRow(row, .response)
}

/// 1 when the Ref names a tool_call approval request that is still approved: no run has started it (StartExecution makes it executing).
ClassMethod StillApproved(ref As %String) As %Boolean [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Quit $IsObject(row) && $$$ISOK(row.%Reload()) && (row.Kind = "tool_call") && (row.State = "approved")
}

/// Checks the text of a decide or diagnose reply against the replyClass (CheckReply) and filters each reason once with filterClass, and
/// then each string property that the reply class names in its FILTERED parameter (comma-separated; none when the parameter is absent; a dotted
/// name such as ItemNoun.One is a property of an object property, skipped when that object is absent; a list of strings is filtered item by item;
/// an empty text is left as it is), once, before the payload is validated again. 1
/// when the reply is a decision: outcome, reasons (one line each, with the code-written line first when the user rule changed the
/// outcome), confidence (two decimals) and json (the payload as JSON, with the filtered properties) are set. 0 when it fails the check,
/// no reason is left of it once filtered, or the payload fails its check again after filtering (invalid). sc is an error only when the payload cannot be exported.
/// problem is "" unless the result is 0; then it says why, in words that quote no content of the reply (RefusalText): "The reply check failed: the reply is not one JSON object that <replyClass> accepts: " and what the first check refused, "No reason is left once the reply filter has run", or "After the reply filter ran: <replyClass> refused the filtered payload: " and what the second check refused. Conclude logs it, redacted, as a warning in the decision's trace session when the fallback is invalid.
/// Both checks run with OcuTalon.Bridge.ReplyCheck begun from the request, so a reply class's %OnValidateObject can read what the request carried; it is ended on every
/// exit, an exception included, and an exception is thrown on.
ClassMethod Interpret(request As OcuTalon.Bridge.Msg.Request, text As %String, replyClass As %String, filterClass As %String, Output outcome As %String, Output reasons As %String, Output confidence As %String, Output json As %String, Output sc As %Status, Output problem As %String) As %Boolean [ Private ]
{
	Set sc = $$$OK
	Set outcome = "tellnow"
	Set reasons = ""
	Set confidence = ""
	Set json = ""
	Set problem = ""
	Do ##class(OcuTalon.Bridge.ReplyCheck).Begin(request)
	Try {
		Set valid = ..Judge(request, text, replyClass, filterClass, .outcome, .reasons, .confidence, .json, .sc, .problem)
	} Catch exception {
		Do ##class(OcuTalon.Bridge.ReplyCheck).End()
		Throw exception
	}
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	Quit valid
}

/// The work of Interpret, run while the ReplyCheck of the request is begun: the reply check, the filtering and the check again, with the same results. A check
/// that fails gives problem the words of RefusalText for the status of the check (CheckReply's cause, or the second check's status), never IRIS's error text.
ClassMethod Judge(request As OcuTalon.Bridge.Msg.Request, text As %String, replyClass As %String, filterClass As %String, Output outcome As %String, Output reasons As %String, Output confidence As %String, Output json As %String, Output sc As %Status, Output problem As %String) As %Boolean [ Private ]
{
	Set sc = $$$OK
	Set outcome = "tellnow"
	Set reasons = ""
	Set confidence = ""
	Set json = ""
	Set problem = ""
	Set checked = ..CheckReply(text, replyClass, .payload, .cause)
	If $$$ISERR(checked) {
		Set problem = ..#CHECKFAILED_replyClass_" accepts: "_..RefusalText(cause, replyClass, text)
		Quit 0
	}
	Set lines = ""
	For i = 1:1:payload.Reasons.Count() {
		Set filtered = $ClassMethod(filterClass, "Filter", payload.Reasons.GetAt(i))
		Do payload.Reasons.SetAt(filtered, i)
		Set line = $ZStrip($Translate($Replace(filtered, $Char(13, 10), " "), $Char(10, 11, 12, 13, 133, 8232, 8233), "       "), "<>WC")
		If line '= "" Set lines = lines _ $ListBuild(line)
	}
	If lines = "" {
		Set problem = "No reason is left once the reply filter has run"
		Quit 0
	}
	Set named = $Parameter(payload, "FILTERED")
	For i = 1:1:$Length(named, ",") {
		Set name = $ZStrip($Piece(named, ",", i), "<>W")
		If name = "" Continue
		Set holder = payload
		For j = 1:1:$Length(name, ".") - 1 {
			Set holder = $Select($IsObject(holder): $Property(holder, $Piece(name, ".", j)), 1: "")
		}
		If '$IsObject(holder) Continue
		Set leaf = $Piece(name, ".", *)
		Set value = $Property(holder, leaf)
		If $IsObject(value) {
			For k = 1:1:value.Count() {
				If value.GetAt(k) '= "" Do value.SetAt($ClassMethod(filterClass, "Filter", value.GetAt(k)), k)
			}
		} ElseIf value '= "" {
			Set $Property(holder, leaf) = $ClassMethod(filterClass, "Filter", value)
		}
	}
	If named '= "" {
		Set checked = payload.%ValidateObject()
		If $$$ISERR(checked) {
			Set problem = "After the reply filter ran: "_replyClass_" refused the filtered payload: "_..RefusalText(checked, replyClass)
			Quit 0
		}
	}
	Set outcome = payload.Outcome
	If (request.Kind = "decide") && (request.Provenance = "user") && ((outcome = "ignore") || (outcome = "digest")) {
		Set outcome = "tellnow"
		Set lines = $ListBuild(..#USERANSWERED) _ lines
	}
	Set reasons = $ListToString(lines, $Char(10))
	Set confidence = $Number(payload.Confidence, 2)
	Set sc = payload.%JSONExportToString(.json)
	Quit 1
}

/// Records an unusable request or reply as a fallback decision and answers it (AD-8, AD-20, AD-26, AD-31). reason is one value of
/// Msg.Enum FALLBACKREASON, and reply is the runner's Reply, or "" when nothing was sent or the runner has not answered (a timer).
/// stepCount is the AgentStepCount of the earlier attempts, which the row adds to the reply's. The Decision row is NewRow with the outcome
/// tellnow, Fallback true and the reason; Confidence and Payload stay empty, and so does Reasons unless the caller passes reasons, a sentence written in code
/// (HELDBEFOREUPDATE) and never model text, so that no model text is kept. A row that another
/// call saved first for the item and kind is answered instead (the row of a turn is refused as ResponseFromRow says), and fires nothing.
/// When this call saved the row, decision.recorded is fired after the save (FireEvent) and, for daily_cap only, the day is marked as
/// capped (Budget.MarkCapped), outside any transaction. The answer to a decide or diagnose request is the DecisionResponse of the row;
/// the answer to a turn is a new Reply, never a clone of the runner's: it holds the DecisionRef, the outcome tellnow, Fallback, the
/// reason, the totals of the row, the runner's Tainted and ToolsRun (a fallback with no runner reply sets neither), SessionRotated 0, because a
/// fallback moves no link (PointLink), SessionBroken when broken is 1 (Broken: the
/// provider rejected the stored history of a user's turn), and no text, host data, steps, failure text or finish reason. Nothing else is
/// sent: a fallback triggers no tool, fix or approval request.
ClassMethod RecordFallback(request As OcuTalon.Bridge.Msg.Request, decisionRef As %String, reason As %String, reply As %RegisteredObject, sinkClass As %String, traceSessionId As %Integer, Output response As %Persistent, durationMs As %Integer = "", stepCount As %Integer = 0, broken As %Boolean = 0, reasons As %String = "") As %Status
{
	Set response = ""
	If ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(request.ItemId, request.Kind, .id) {
		Quit ..ResponseFromId(id, .response)
	}
	Set row = ..NewRow(request, decisionRef, reply, traceSessionId, durationMs, stepCount)
	Set row.Outcome = "tellnow"
	Set row.Reasons = reasons
	Set row.Confidence = ""
	Set row.Fallback = 1
	Set row.FallbackReason = reason
	Set row.Payload = ""
	Set sc = ..Record(row, .saved, .response)
	If $$$ISERR(sc) || 'saved Quit sc
	Do ..FireEvent(sinkClass, request.OwnerRef, decisionRef)
	If reason = "daily_cap" Do ##class(OcuTalon.Bridge.Budget).MarkCapped("", sinkClass)
	If request.Kind '= "turn" Quit ..ResponseFromRow(row, .response)
	Set response = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set response.DecisionRef = decisionRef
	Set response.Outcome = "tellnow"
	Set response.Fallback = 1
	Set response.FallbackReason = reason
	If $IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Set response.Tainted = reply.Tainted
		Set response.ToolsRun = reply.ToolsRun
	}
	Set response.SessionBroken = +broken
	Do ..CarryTotals(row, response)
	Quit $$$OK
}

/// A new Decision row for the request: Ref, Kind, ItemId, OwnerRef, Summary, traceSessionId as TraceSessionId, RecordedAt (now, UTC), the
/// totals of the decision (the sums of the Usage rows of decisionRef, Usage.Totals, except the Model: the Model of the reply that answered, the one
/// of the second model after a retry, when the reply holds one, because the newest Usage row can be a late first attempt's), AgentStepCount (stepCount, the steps of the earlier
/// attempts, plus the reply's, which is 0 when there is none) and durationMs as DurationMs. The caller sets the outcome, the reasons, the
/// confidence, the fallback and the payload.
ClassMethod NewRow(request As OcuTalon.Bridge.Msg.Request, decisionRef As %String, reply As %RegisteredObject, traceSessionId As %Integer, durationMs As %Integer = "", stepCount As %Integer = 0) As OcuTalon.Bridge.Data.Decision
{
	Set row = ##class(OcuTalon.Bridge.Data.Decision).%New()
	Set row.Ref = decisionRef
	Set row.Kind = request.Kind
	Set row.ItemId = request.ItemId
	Set row.OwnerRef = request.OwnerRef
	Set row.Summary = request.Summary
	Set row.TraceSessionId = traceSessionId
	Set row.RecordedAt = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set totals = ##class(OcuTalon.Bridge.Data.Usage).Totals(decisionRef)
	Set row.InputTokens = totals.inputTokens
	Set row.OutputTokens = totals.outputTokens
	Set row.CacheReadTokens = totals.cacheReadTokens
	Set row.CacheWriteTokens = totals.cacheWriteTokens
	Set row.CostUSD = totals.costUSD
	Set row.Model = totals.model
	If $IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply") {
		If reply.Model '= "" Set row.Model = reply.Model
		Set row.AgentStepCount = $Select(+stepCount: stepCount + reply.AgentStepCount, 1: reply.AgentStepCount)
	} Else {
		Set row.AgentStepCount = +stepCount
	}
	Set row.DurationMs = durationMs
	Quit row
}

/// Saves the row. The unique index on ItemId and Kind refuses a row for an item that another call recorded first: then nothing
/// is saved (saved is 0) and response is the answer for the row that won, or the error of ResponseFromRow when that row is a
/// turn's. Any other save error is returned as it is.
ClassMethod Record(row As OcuTalon.Bridge.Data.Decision, Output saved As %Boolean, Output response As %Persistent) As %Status
{
	Set saved = 0
	Set response = ""
	Set sc = row.%Save()
	If $$$ISOK(sc) {
		Set saved = 1
		Quit $$$OK
	}
	If ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(row.ItemId, row.Kind, .id) {
		Quit ..ResponseFromId(id, .response)
	}
	Quit sc
}

/// Fires an event to the host sink: OnEvent(type, ownerRef, payload), by default decision.recorded with {"ref": ref}. Every event
/// of the bridge goes through this method (AD-31). Call it after the change it reports has committed. An error status, an
/// exception and a sink class that fails OcuTalon.Bridge.Ext.Accessor.Check (then no event is sent) are logged as a warning that
/// names the class, the event and the subject, and never fail the caller. 1 when OnEvent returned OK.
///   - type: one of OcuTalon.Bridge.Ext.HostSink EVENTS; empty means decision.recorded;
///   - ref: the subject of the event for the warning: the Ref of the decision, or the day of budget.capped;
///   - payload: the payload object; empty means HostSink.RefPayload(ref).
ClassMethod FireEvent(sinkClass As %String, ownerRef As %String, ref As %String, type As %String = "", payload As %DynamicObject = "") As %Boolean
{
	Set event = $Select(type = "": ##class(OcuTalon.Bridge.Ext.HostSink).#DECISIONRECORDED, 1: type)
	Set delivered = 0
	Try {
		If '$IsObject(payload) Set payload = ##class(OcuTalon.Bridge.Ext.HostSink).RefPayload(ref)
		Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).Check("HostSinkClass", sinkClass)
		If $$$ISOK(sc) {
			Set sc = $ClassMethod(sinkClass, "OnEvent", event, ownerRef, payload)
		}
		If $$$ISOK(sc) {
			Set delivered = 1
		} Else {
			$$$LOGWARNING("The host sink "_sinkClass_" did not take the event "_event_" for "_ref_": "_$SYSTEM.Status.GetErrorText(sc))
		}
	} Catch exception {
		Set delivered = 0
		$$$LOGWARNING("The host sink "_sinkClass_" threw on the event "_event_" for "_ref_": "_exception.DisplayString())
	}
	Quit delivered
}

/// The answer for the Decision row with this id.
ClassMethod ResponseFromId(id As %String, Output response As %Persistent) As %Status
{
	Set response = ""
	Set row = ##class(OcuTalon.Bridge.Data.Decision).%OpenId(id, , .sc)
	If $$$ISERR(sc) Quit sc
	Quit ..ResponseFromRow(row, .response)
}

/// The DecisionResponse for a recorded decide or diagnose row: its Ref as DecisionRef, outcome, reasons, confidence,
/// fallback flag and reason, payload and totals (CarryTotals). The row of a tool request is answered with a Reply instead: DecisionRef, Outcome,
/// Reasons (code-written only, such as HELDBEFOREUPDATE), Fallback, FallbackReason and the totals, and no text, steps or failure text. The row of a
/// turn keeps no reply text, so a turn is refused with an error that names the item and the Ref.
ClassMethod ResponseFromRow(row As OcuTalon.Bridge.Data.Decision, Output response As %Persistent) As %Status
{
	Set response = ""
	If row.Kind = "turn" {
		Quit $$$ERROR($$$GeneralError, "The item "_row.ItemId_" already has the turn decision "_row.Ref_"; the row keeps no reply text, and a second answer would answer the message twice")
	}
	If row.Kind = "tool" {
		Set response = ##class(OcuTalon.Bridge.Msg.Reply).%New()
		Set response.DecisionRef = row.Ref
		Set response.Outcome = row.Outcome
		Set response.Reasons = row.Reasons
		Set response.Fallback = row.Fallback
		Set response.FallbackReason = row.FallbackReason
		Do ..CarryTotals(row, response)
		Quit $$$OK
	}
	Set response = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
	Set response.DecisionRef = row.Ref
	Set response.Outcome = row.Outcome
	Set response.Reasons = row.Reasons
	Set response.Confidence = row.Confidence
	Set response.Fallback = row.Fallback
	Set response.FallbackReason = row.FallbackReason
	Set response.Payload = row.Payload
	Do ..CarryTotals(row, response)
	Quit $$$OK
}

/// Copies the eight total fields (InputTokens, OutputTokens, CacheReadTokens, CacheWriteTokens, CostUSD, Model, AgentStepCount and
/// DurationMs) from a Decision row to an answer, or the other way: both hold them under these names (AD-20, AD-26).
ClassMethod CarryTotals(from As %RegisteredObject, to As %RegisteredObject)
{
	For name = "InputTokens", "OutputTokens", "CacheReadTokens", "CacheWriteTokens", "CostUSD", "Model", "AgentStepCount", "DurationMs" {
		Set $Property(to, name) = $Property(from, name)
	}
}

Storage Default
{
<Data name="DecideDefaultData">
<Subscript>"Decide"</Subscript>
<Value name="1">
<Value>HostSinkClass</Value>
</Value>
<Value name="2">
<Value>ReplyFilterClass</Value>
</Value>
<Value name="3">
<Value>ClassificationClass</Value>
</Value>
<Value name="4">
<Value>TimerSeconds</Value>
</Value>
<Value name="5">
<Value>DailyCostCapUSD</Value>
</Value>
<Value name="6">
<Value>GatewaySpendUSD</Value>
</Value>
<Value name="7">
<Value>GatewaySpendDate</Value>
</Value>
<Value name="8">
<Value>DecisionTokenBudget</Value>
</Value>
<Value name="9">
<Value>DecisionRef</Value>
</Value>
<Value name="10">
<Value>Resends</Value>
</Value>
<Value name="11">
<Value>StepCount</Value>
</Value>
<Value name="12">
<Value>StepsSent</Value>
</Value>
<Value name="13">
<Value>RequestTokenLimit</Value>
</Value>
<Value name="14">
<Value>ServiceUser</Value>
</Value>
<Value name="15">
<Value>ToolClassification</Value>
</Value>
<Value name="16">
<Value>ApprovalRole</Value>
</Value>
<Value name="17">
<Value>RetryRunner</Value>
</Value>
<Value name="18">
<Value>FirstSeconds</Value>
</Value>
<Value name="19">
<Value>InstanceZone</Value>
</Value>
<Value name="20">
<Value>TurnToolsClass</Value>
</Value>
<Value name="21">
<Value>McpServersClass</Value>
</Value>
<Value name="22">
<Value>ContentClass</Value>
</Value>
</Data>
<DefaultData>DecideDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
