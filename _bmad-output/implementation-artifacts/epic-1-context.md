# Epic 1 Context: Every item gets an attention decision you can audit and afford

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Build the bridge's decision core (Lane A) on Epic 0's merged contracts and stubs. It has three declarative AI Hub agents on Claude Haiku 5.5, one agent-runner operation per agent on AI Hub's own adapter, and the `Decide` process. `Decide` gives every item exactly one recorded attention decision with outcome, reasons, confidence, four token counts and cost. It records every model request and tool call as an agent step in Visual Trace, and it takes a fixed fallback route that never acts whenever a reply is unusable. Conversations survive restarts, and the product starts safely with no model key. Every later epic (approvals, watch, fixes, the chat page, evaluation) calls models only through this pipeline, and the separable bridge must also run alone, in a production that has none of OcuTalon's channels or web app.

## Stories

- Story 1.1: Every agent runs on Claude Haiku 5.5 through the Config Store
- Story 1.2: Agent runners send every request under the model rules
- Story 1.3: Decide records exactly one attention decision per item
- Story 1.4: Every turn and decision carries its tokens and cost
- Story 1.5: Every model request and tool call is an agent step in Visual Trace
- Story 1.6: An unusable reply takes the fallback route, and OcuTalon starts with no key
- Story 1.7: Timeouts and rate limits end every decision on time
- Story 1.8: Conversations survive restarts
- Story 1.9: No model request goes over 100,000 tokens (size check, `too_large` and the tool-result cap only; compaction moved to Story 30.1)
- Story 1.10: The chat agent sets, lists and cancels reminders
- Story 1.12: Items saved for the digest are kept for it
- (Story 1.11 moved whole to Story 30.2.)

## Requirements & Constraints

- **Model rules.** Every agent defaults to `claude-haiku-5-5`. No request ever sets `temperature`, `top_p` or `top_k`. The output cap is 8,000 tokens and never goes below 4,000. Every test runs against the CI mock, which rejects sampling parameters and caps under 4,000.
- **Caching.** Every runner's session carries the full cache block, but AI Hub marks a block only where its cached prefix reaches `min_tokens_for_cache` (512 tokens). A shorter prefix is never marked, so a test expects a cache marker in the mock's log only where the prefix reaches that threshold, and proves the block itself from each runner's session config.
- **Keys.** The model key comes only from the environment through a placeholder that only AI Hub's provider resolves. Its value must never appear in a Config Store entry, a saved AI session, a production setting, the event log, an agent step, a log line or an error detail. With no key, every item still runs, nothing in the production fails, and every decision falls back with `no_key`.
- **One decision per item.** A decision is unique on (item, kind), and a repeated request returns the recorded decision without calling the model. Outcomes are ignore, digest, tell now and act. Confidence is recorded but never changes the outcome. When the user wrote the item, an ignore or digest answer becomes tell now, and the reasons say why.
- **Fallback.** An unusable reply is never treated as an answer. It is recorded as tell now, with the fallback flag and its reason. It triggers no tool, fix or approval, and Visual Trace flags it. On a chat turn the fallback is a reply only. CI forces every fallback reason through mock scenarios.
- **On time.** Every decision and turn finishes, or falls back, within `Decide`'s timer. A rate-limited attempt (HTTP 429 or 529) is re-sent with back-off until the timer fires only when no tool ran in it, as `Reply.ToolsRun` reports; when a tool ran it falls back at once, and an `error` always falls back at once.
- **Cost honesty.** Tokens and cost are recorded per turn and per decision, never per step. A model-request step carries only an estimated request size, labelled as an estimate.
- **Size.** No request goes over 100,000 input tokens: one that would is never sent and falls back with `too_large`. Together, all the tool results of one model step pass at most 10,000 tokens to the model, and each cut result says it was cut.
- **Prompt safety.** The user's own text always reaches the model as a user-role message, never inside a tool result. Untrusted content is quoted data, labelled with where it came from. Every request starts with a preamble that states the local time and zone.
- **No shell.** AI Hub's shell, filesystem, SQL and web-search tools are never registered. No tool runs operating-system commands, arbitrary code or SQL that changes data, and a test inspects each live ToolManager to prove it.
- **Durability.** AI sessions, conversation links and digest items survive a restart, and live in the private database.

## Technical Decisions

- **The pipeline.** A caller sends to `OcuTalon.Bridge.Process.Decide`, which sends to a runner and answers only its caller; besides that answer it sends only agent steps, to `AgentSteps`. The runners are `TriageAgent`, `DiagnosisAgent` and `ChatAgent`, all of class `OcuTalon.Bridge.Operation.AgentRunner`, on the adapter `OcuTalon.Bridge.Adapter.Agent` (a subclass of `EnsLib.AI.Agent.OutboundAdapter`). `Decide`:
  - allocates the `DecisionRef`;
  - prechecks `no_key`, `daily_cap`, `budget` and `too_large`;
  - sends asynchronously under `SetTimer` (60 seconds by default, never more than 110);
  - validates the reply against the runner's `ReplyClass`;
  - runs the `ReplyFilterClass` on model-written text before anything is recorded;
  - records the `Decision` row, including its `TraceSessionId`;
  - after commit, fires the HostSink event `decision.recorded` with the `Ref` only. An `OnEvent` failure is logged and never fails `Decide`.
- **The runners.** Only runners call `Chat`, and each runner's pool size is its concurrency cap. A runner refuses to start if any AI Hub policy, tool, skill or system-prompt setting, or its own session-config setting, is set, or if its agent class isn't on its allow-list. It builds the agent on first use, so it starts with no key. It always adds the gate and `OcuTalon.Bridge.Policy.StepAudit` in `OnAfterAgentInit`. It passes the same code-built session config when it creates a session and on every `OpenSession`, `%Save`s a session only after a completed `Chat`, and keeps `Response.Extra`. Before `Chat` it sets `OcuTalon.Bridge.Context`, and afterwards it copies `HostData` and the taint onto the `Reply`.
- **The callback rule (build 154 deadlocks otherwise).** Renderer, policy and tool classes make no `%AI` call beyond their base classes and run no Python. A test enforces this.
- **Agents and configuration.** The agents are `%AI.Agent` subclasses with static `XData INSTRUCTIONS`, `TOOLSETS` and `MODEL`, and they keep Epic 0's `MOCKKEY`. No INSTRUCTIONS block contains `{{`, and nothing calls `%AI.Utils.Template`.
  - The model comes from the runner's `Model` setting, seeded only when absent. Any model in a Config Store entry is ignored, and the start fails if any runner resolves no model.
  - `ProviderConfig` is `@{config:OcuTalon<Agent>}`. Only the `Provider` install step writes the `AI.LLM.OcuTalon<Agent>` entries, and never a model in them.
  - The `x-ocutalon-mockkey` header is added only when `OCUTALON_MOCK_KEY_HEADER=1`.
  - At run time an entry changes only through the bridge's merge method, which never writes a key. The affected runners then restart.
- **The session config** is built in code from `OcuTalon.Bridge.Data.ModelFamily` and never stored: the cap, the effort for Anthropic models, `max_iterations`, the cache block and `timeout_ms`, which comes from `Timeouts.Derive`. The retry block in `http_config` is always written in full, never in part.
- **Classifying failures.** One method classifies every failure in the fixed order: precheck, then timeout, then `rate_limited` and `error`, then `refusal`, `cut_off`, `empty` and `invalid`. Every provider failure arrives as `<%AICore>ProviderError` and is classified by its text. A cut-off or refusal is read from `finish_reason`, which only the Anthropic provider reports; anything the platform can't tell apart is `unusable`. A late reply is never passed on, but its `Usage` row is still written.
- **Usage and cost.** After every `Chat` the runner writes one `OcuTalon.Bridge.Data.Usage` row from the `GetStats()` delta around the call. Input tokens are prompt plus cache-read plus cache-write. Each tier is priced from `OcuTalon.Bridge.Data.Price`, which `OcuTalon.Bridge.Installer` seeds. Decision and turn totals are sums of these rows, carried in plainly named fields. `OcuTalon.Bridge.Budget.State()` never counts owner `eval`, and the bridge's day ends at local midnight through `OcuTalon.Bridge.Time`.
- **Agent steps.** `OcuTalon.Bridge.Adapter.StepRenderer` records one step per model request. `StepAudit` records each tool step, labelled by the tool's class parameter, never by its arguments or model text. Steps are buffered in the runner's job, passed through `OcuTalon.Bridge.Redact`, returned with the reply and emitted in order in the caller's trace session.
- **Conversations.** `OcuTalon.Bridge.Data.ConversationLink` is written only by the runner, and only for user `turn`s. Every other request uses a throwaway AI session. While a conversation lock is held, `Decide` waits 2 seconds, then answers `Busy` (no text, no decision, not an error and not a fallback). A rejected stored history sets `SessionBroken` and is never repaired in place.
- **Tools.** A tool returns a dynamic object or plain text through `OcuTalon.Tools.Result`. It takes no session argument: the session comes from the bridge context. It changes state only through `OcuTalon.Core.Commands.Submit`, with an idempotency key made of the turn's item and the call's position, and never writes domain tables itself.
- **The bridge boundary.** `OcuTalon.Bridge` references no other OcuTalon package, and a CI check enforces this. The bridge reaches its host only through `Decide`'s extension-class settings, read through `Ext.Accessor.ClassFor`. Bridge storage globals are `^OcuTalonBP.<Short>` and product ones `^OcuTalonP.<Short>`, each registered in `src/short-names.tsv`, with the compiler-generated `Storage` blocks committed and append-only.
- **Tests.** `%UnitTest` classes go under `OcuTalon.Test.Agent`, `.Bridge` and `.Tools`, in the `lane-a` shard. Lane A extends the mock only by adding scenario files under `ci/mock/scenarios/A/`, picked by a `[[mock:<name>]]` marker or by the agent's `MOCKKEY`; new mock behaviour has to be asked of Lane B. The standalone-bridge job in `.github/workflows/lane-a.yml` loads `src/bridge/` alone and runs `OcuTalon.BridgeExample`.

## UX & Interaction Patterns

- Chat's voice is plain English in the first person, with no greeting, exclamation mark, emoji or hype word, and no class name, error code or stack trace unless the user asks. Asked to run a command, Chat replies exactly "I can't run commands. I can check productions, read failed messages and propose fixes that wait for your approval." and calls no tool.
- Each bridge fallback reason maps to exactly one of the UX catalog's 11 reasons. `invalid`, `unusable` and replies from a provider that reports no stop reason map to the generic "the model's reply couldn't be used". The bridge never renders user-facing text itself; the catalog does.
- In Visual Trace, a decision message shows `Outcome`, `Reasons`, `Confidence`, `Fallback` and `FallbackReason`, and a turn's steps sit in its thread beside its decision and reply.

## Cross-Story Dependencies

- **Epic 0 dependencies.** Epic 1 implements Epic 0's signatures: `OcuTalon.Agent.Input`, `Bridge.Context`, `Budget.State`, `Keys.Status`, `Timeouts.Derive` and the Config Store merge method. Keep `OcuTalon.Test.Contract.Ac`'s signature oracle green. It also builds on Epic 0's message and data classes, the extension bases with do-nothing defaults, the implemented `Commands.Submit`, the stub production items and the CI mock.
- **Inside the epic.**
  - Stories 1.1 and 1.2 come before Story 1.3, which the later stories build on.
  - Story 1.7 adds `Derive`'s values to Story 1.1's `Provider` step (the request timeout and retry block) and to Story 1.2's session config (`timeout_ms`).
  - Story 1.7's re-send rule reads `Reply.ToolsRun`, but the runner's answer from Story 1.2 fills only `Text`, `FinishReason`, `HostData` and `Tainted`, so a turn that ran tools reports `ToolsRun` 0. Story 1.7 has to make the runner set it.
  - Story 1.10's tools return through Story 1.9's `Tools.Result` cap.
- **Other epics.**
  - Until a dependency merges, its stand-in is used:
    - until Story 5.4, Diagnosis uses a fixture `OcuTalon.Tools.Watch`;
    - until Story 5.7, the reply guard stub passes text through;
    - until Story 2.6, the HostSink stub does nothing;
    - until Story 2.7, the digest tests send `DigestStore` fixture `ItemDecision`s;
    - the reminder tools are tested against a `CommandsIn` test double, because Lane B's `ReminderOps` handles the real verbs;
    - until Epic 3's gate lands, the reminder tools run as safe tools.
  - Two Epic 30 stories take over parts of this epic: Story 30.1 reads Story 1.9's compaction flag, and Story 30.2 owns the purge tasks.
  - Lane B's `SettingsOps` calls the merge method.
  - Lane B owns `OcuTalon.Core`, `.Msg`, `.Schedule`, `.Data.Time` and the rest of `ci/`. Ask Lane B for changes there rather than editing them.
