---
title: 'Story 1.2: Agent runners send every request under the model rules'
type: 'feature'
created: '2026-10-21'
status: 'done'
baseline_revision: '9c87cfc27d321955dab38c4249e7da0c55be924b'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-5, AD-6, AD-7, AD-8, AD-10, AD-19, AD-22 and AD-29)'
warnings: ['oversized']
deferred:
  - summary: >-
      Nothing sets Reply.ToolsRun: the runner's Answer fills Text, FinishReason, HostData and Tainted only, so the field stays 0 for a turn that ran tools.
    evidence: |-
      AD-6 gives Reply a ToolsRun ("whether any tool ran"); Story 1.7 re-sends after a rate limit only when no tool ran in the failed attempt (ToolsRun), and the evaluation stories score a turn on it. No acceptance criterion of Story 1.2 or 1.5 says who sets it, and this spec's Approach lists only HostData, the taint and FinishReason. AI Hub's %AI.LLM.Response carries the tool-call count, so the runner can set it where Answer builds the Reply.
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls (Answer)
    severity: medium
---

<intent-contract>

## Intent

**Problem:** The three runner items (`TriageAgent`, `DiagnosisAgent`, `ChatAgent`) are stubs that answer "not implemented". Their adapter builds nothing, and nothing composes a session config, so no request can reach a model under the cap, effort, cache and no-sampling rules. Nothing sets the bridge context, and no test shows that a runner exposes no shell, filesystem, SQL or web-search tool.

**Approach:**
- `OcuTalon.Bridge.Adapter.Agent` refuses to start when an AI Hub policy, tool, skill, system-prompt or session-config setting is set, or when its agent class is not on its allow-list. It builds the agent on the first request that needs it, by deferring the base adapter's own `OnInit`.
- One method composes the session config from the agent and the resolved model's `ModelFamily` row.
- The runner answers an `OcuTalon.Bridge.Msg.Request` with a `Reply`. Before `Chat` it sets `OcuTalon.Bridge.Context`. After `Chat` it copies the context's `HostData` and taint onto the reply, and keeps `Response.Extra.finish_reason` as the reply's new `FinishReason`.
- The runner answers a new `ToolInventory` request with its live ToolManager's tool list.
- The bridge installer seeds the model families. The Production step seeds each runner's `Effort` and the agent allow-list.
- Tests prove all of this against the CI mock, against the live items and through the code rules.

## Boundaries & Constraints

**Always:**
- **The model rules.**
  - The cap is 8,000 tokens: session `max_tokens`, or for GPT-5-class models `extra_params.max_completion_tokens`.
  - Effort goes only to Anthropic models, as `extra_params.output_config.effort`, from the runner's `Effort` setting. An empty setting sends no effort.
  - `max_iterations` comes from the agent; Chat's is 4.
  - The cache block is exactly `{"enabled":1,"cache_system_prompt":1,"cache_tool_definitions":1,"min_tokens_for_cache":512}`.
  - No `temperature`, `top_p` or `top_k` at any depth. The adapter clears the built agent's `Temperature`, so AI Hub's `BuildSessionConfig` adds none (AD-7, NFR-1, NFR-2).
- **The model.** It is the adapter's `Model` setting, else the agent's `MODEL`, exactly as `AgentRunner.ResolveModel` resolves it. An empty model or a model that no family row matches fails the request before anything is sent.
- **One composing method.** It builds a new object for every session. Every session the adapter creates or opens gets the object it returns.
- **Building the agent.**
  - The adapter's `OnInit` makes no AI Hub call.
  - The agent is built through the base `EnsLib.AI.Agent.OutboundAdapter.OnInit`, reused rather than copied (Rule 2), on the first `Request` or `ToolInventory` that needs it.
  - A failed build is not kept: the next request tries again, and the item keeps running.
- **The context.** `Context.Begin(request, <the host's %SuperSession>)` runs before `Chat`. After `Chat` the context's `HostData` and `Tainted` go onto the `Reply`. `Context.End()` runs on every path, the error paths included.
- **Settings.**
  - `Effort` and `AgentAllowList` are settings of the adapter.
  - Their values are System Default Settings rows that the Production step writes only when absent (seed values, AD-19). `Effort` comes from the agent class's `EFFORT` parameter. The allow-list is the `AgentClass` values of the production's runner items, in one row for every item.
  - Model-family rows are structural: the bridge installer rewrites its three families at every start and leaves any other row alone.
- **The bridge boundary (AD-2).** No bridge class names another OcuTalon package on a code line.
- **Storage (AD-5).** Storage blocks are compiler-generated and committed, and only appended to.
- **Text in `src/`.** All of it is ASCII. No INSTRUCTIONS block contains `{{`.
- **Test placement.** Tests go under `OcuTalon.Test.Bridge` and `OcuTalon.Test.Agent` (the lane-a shard).
- **Test hygiene.** Each test restores every row, Config Store entry, ModelFamily row, AI session and item state it changes, and restarts every runner it touched.

**Never:**
- No `ConversationLink`, no `%Save` of an AI session by the runner, and no `SessionMode`, `SeedText` or `SystemNote` handling (Story 1.8).
- No `GetStats`, `Usage` row, or token or cost field (Story 1.4).
- No step renderer and no `StepAudit` (Story 1.5). No gate (Epic 3) and no MCP attach (step 4).
- No failure classification, fallback or `Keys.Status` (Story 1.6). Errors come back as the runner's error status, with AI Hub's text.
- No `timeout_ms`, request timeout or retry block (Story 1.7).
- `Decide` and `AgentSteps` stay stubs (Story 1.3).
- No change to `Bridge.Msg.Enum` (Lane B's `Test.Msg.Contracts` pins it).
- No change to the properties of `Data.ModelFamily` (Lane B's `Test.Data.Tables` pins them).
- No change to the production XData.
- No edit to `triage.json`, `diagnosis.json` or `chat.json` (the mock's tests pin their tool names).
- No literal key anywhere, and no `@{env:...:-fallback}` form.
- No edit to a contended Lane B path: `docker/**` (except `merge.cpf`), `ci/**` (except `ci/mock/scenarios/A/`), `OcuTalon.Core`, `.Msg` (except `Msg/Catalog/Watch.cls`), `.Web`, `.Data.Time`, `.Data.Setting`, `.Data.Ownership`, `.Data.Public`, or the Lane B test packages (`Test.Contract` among them). No copy of a private Lane B helper either.
- No new `ci/units.sh` or `src/module.xml` entry.
- No commit and no push.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Triage request (CI mock) | `decide` Request to `TriageAgent`; the entry's key placeholder points at a CI variable (fixture) | The logged request has `model` `claude-haiku-5-5`, `maxTokens` 8000, `request.output_config.effort` `low`, no cache marker (its prefix is below `min_tokens_for_cache`; measured in Task 0 (a)) and no `temperature`, `top_p` or `top_k`, with status 200 and no `rejected`. `Reply.Text` is `triage.json`'s text. [AMENDED 2026-10-21 with AC3; see the Spec Change Log] | No error expected |
| Diagnosis request | `diagnose` Request to `DiagnosisAgent` | Effort `high`; the last tool's `cacheControl` is `{"type":"ephemeral"}` (system plus tools reach the threshold), the system block alone is unmarked (measured); two requests (the fixture tool runs), both accepted. `Reply.Text` is `diagnosis.json`'s final text. [AMENDED 2026-10-21 with AC3] | No error expected |
| Cache over the threshold | A probe agent whose system prompt is over `min_tokens_for_cache` (about 800 tokens, the form Task 0 (a) measured) through the same runner path | `request.system.cacheControl` is `{"type":"ephemeral"}`: the cache block reaches the provider. [ADDED 2026-10-21 with AC3] | No error expected |
| Chat request | `turn` Request (provenance `user`) to `ChatAgent` | No `output_config.effort`, `maxTokens` 8000, no cache marker (below the threshold, measured); every logged request accepted. [AMENDED 2026-10-21 with AC3] AC3 asserts the log only: Chat's answer is recorded by Task 0 (b), not asserted, because `chat.json` calls a tool that Chat gets in a later story. | No error expected from the mock |
| Model change | `DiagnosisAgent`'s `Model` row set to `claude-sonnet-5-5`, then the item restarts | The next request names `claude-sonnet-5-5`, still with 8000 and effort `high` | No error expected |
| GPT-5 family (pure) | Model `gpt-5-mini`, effort `high` | `{"extra_params":{"max_completion_tokens":8000},"cache":{...}}`, with no `max_tokens` and no effort | No error expected |
| Other model (pure) | Model `zz-other-model` | The `default` family: `max_tokens` 8000 and no effort | No error expected |
| No model or no family | The model is empty, or no family row matches | Nothing is sent | An error naming the model, or saying that none resolves |
| Start refusal | Any one of `AuthPolicy`, `AuditPolicy`, `DiscoveryPolicy`, `IrisTools`, `AdditionalTools`, `IrisSkills`, `AdditionalSkills`, `SystemPrompt` set; or `SessionConfigString` other than empty or `{}` | The item does not start. The event log names the setting. | Restored, the item starts again |
| Allow-list | `AgentClass` not on `AgentAllowList`; an empty list; or a class that is not an `%AI.Agent` | The item does not start, naming the class | Same |
| No key (the CI default) | `ANTHROPIC_API_KEY` unset in the container | Every runner runs. A Request gets an error naming `@{env:ANTHROPIC_API_KEY}`; nothing reaches the mock; the item keeps its job. A second request tries the build again. | Error status, never a crash |
| Context probe (in-process) | A probe agent's tool reads the context during `Chat` | It sees every request field plus the `SuperSession`. `Reply.HostData` holds what it wrote, and `Reply.Tainted` is 1. Afterwards `Context.Active()` is 0. | No error expected |
| Stop reasons | `[[mock:refusal]]`, `[[mock:max-tokens]]` | `Reply.FinishReason` is `refusal` or `max_tokens` | No error expected |
| Resumed session (in-process) | A session saved, then opened by a freshly built adapter, then one more `Chat` | The resumed request still has `maxTokens` 8000 and effort `low` | No error expected |
| Foreign message | `Ens.StringRequest` to `TriageAgent` | `#5003: Not implemented`, no response; the job is kept, so Lane B's row 16 stays green | Error status |
| Unbuilt kinds | Kind `tool`, an unknown kind, or an empty `Input` | Nothing is sent | `tool` gets `$$$NotImplemented`; the others get an error naming the kind or the empty input |
| Live inventory | A `ToolInventory` request to each running runner | Triage: none. Diagnosis: exactly `read_failed_messages`, `read_event_log` and `read_item_settings`, each with source `iris` and provider `OcuTalon.Tools.WatchFixture`. Chat: none. | The test fails on any tool whose source is not `iris`, whose provider is not an `OcuTalon.` class, or whose provider's code breaks the scan |

</intent-contract>

## Code Map

- **Bridge (Lane A):**
  - `src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls`:
    - `STUB` at :11 and the stub `OnMessage` at :15-18 go.
    - `ResolveModel` (:25-37) is pinned by `Test/Contract/Ac.cls:336`. Keep it.
  - `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`: the no-op `OnInit` (:7-10). `Test/Bridge/Api.cls:45-53 TestStubAdapter` asserts that the adapter defines its own `OnInit`.
  - `src/bridge/cls/OcuTalon/Bridge/Context.cls`: `Begin(request, superSession)` :45 (the taint starts at 0 and `HostData` empty), `End` :62, `Active` :68, `Current` :74 and `Put` :86. All are pinned by `Ac.cls:315-319`.
  - `src/bridge/cls/OcuTalon/Bridge/Data/ModelFamily.cls`: `Family`, `ModelPrefix`, `CapKey`, `EffortKey`, and the unique `FamilyIndex`. No code seeds it today.
  - `src/bridge/cls/OcuTalon/Bridge/Installer.cls`: `Run` :9, which today only registers the audit events. Lane B's `docker/tests/test-install-start.sh:722-735` loads `src/bridge/cls` alone into a fresh namespace and expects `Run()` to return 1, so the seeding must work there too.
  - `src/bridge/cls/OcuTalon/Bridge/Msg/Reply.cls`: its contract is in `Test/Bridge/Contracts.cls:157-182`. Lane B's `Ac.cls:224` only checks that the named properties exist.
  - `src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls Merge(entry, fields)`: accepts `{"api_key":"@{env:NAME}"}`.
  - `src/bridge/cls/OcuTalon/Bridge/Service/ApprovalStart.cls` (`ApprovalStartIn`): an adapterless stub service with pool 0, enabled. The tests use it as the sender through `Ens.Director.CreateBusinessService` and `SendRequestSync`, as `Core/Commands.cls:30` does with `CommandsIn`.
- **AI Hub (read only):**
  - `irislib/EnsLib/AI/Agent/OutboundAdapter.cls`:
    - Settings :15-121 (`SessionConfigString` :103 defaults to `"{}"`), `SETTINGS` :123, `Agent` :125.
    - `OnInit` :129-144 builds eagerly. In it, `BeforeAgentInit` :146-165 parses the session config and copies `Model`, `SystemPrompt`, `IrisTools` and `IrisSkills` onto the agent; `AfterAgentInit` :179-229 applies the policy, `AdditionalTools` and `AdditionalSkills` settings and then calls `OnAfterAgentInit` :238.
    - `setupProviderFromSettings` :243-297 never reads an entry's `model`.
    - `SendChat` :302 passes no renderer and creates a session from `..SessionConfig`. Do not use it.
  - `irislib/EnsLib/AI/Messages/LLMResponse.cls:19-27`: drops `Extra`, so do not wrap the response in it.
  - `irislib/%AI/Agent.cls`:
    - `Temperature` :113, `MaxIterations` :120, `ToolManager` :144, `%Init` :197.
    - `BuildSessionConfig` :615-635 changes the passed object in place: it adds `temperature`, and `max_iterations` and `cache` when they are absent.
    - `CreateSession(config)` :639.
    - `ResumeSession` :693-705 ignores the config for a session that is already attached, so open with a fresh agent.
    - `OpenSession(id, config)` :709.
    - `Chat(session, input, feedback="")` :728-766.
  - `irislib/%AI/Agent/Session.cls`: the session config is not stored (storage :721-752, `%AttachToAgent` :120), which is why every open needs the config.
  - `irislib/%AI/LLM/Response.cls`: `Content` :14 (a stream when long) and `Extra` :40 (`finish_reason`).
  - `irislib/%AI/ToolMgr.cls`: `%Discover` :460 and `GetToolStatuses` :492.
  - `irislib/%AI/Tools/ShellTools.cls:32-37`, `SQL.cls:30` and `FileSystem.cls:18`: AI Hub's own tools.
- **Ens (read only):**
  - `irislib/Ens/Host.cls`:
    - `initConfig` :477-528 creates the adapter and applies its settings.
    - An instance created outside a running item is a shadow and gets no `OnInit` (:518-519). That is what the in-process tests rely on.
    - `%SuperSession` :58 is set from the request header at :160.
  - `irislib/Ens/BusinessOperation.cls:707`: the default `OnMessage` answers `EnsErrRequestNotHandled`, not 5003.
- **Product (Lane A):**
  - `src/ocutalon/cls/OcuTalon/Agent/{Triage,Diagnosis,Chat}.cls`: keep `MOCKKEY` on one line (`ci/mock/test/constants.test.mjs:46`). Chat declares no `TOOLSETS`.
  - `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls`: `Run` :44, `Start` :55, `NotRunning` :92, `Runners` :121, `SeedModels` :160-174 (the loop to extend), `AgentModel` :176 and `WriteDefault` :199.
  - `src/ocutalon/cls/OcuTalon/Production.cls`: the runners at :24-32 have pool 1 and only `Adapter:AgentClass`. `ApprovalStartIn` is at :23. No edit.
- **Tests (Lane A):**
  - `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`:
    - The `Items` oracle :466-482 marks the three runners `"stub": 1`.
    - `TestStubsAnswer` :130-162 checks the stubs.
    - Lane B's `docker/tests/test-production.sh:155-181` sweep reads `Items()`.
  - `src/ocutalon/cls/OcuTalon/Test/Agent/Models.cls`: `TestModelChange` :98-131, `Running` :135-140 and `Restart` :143-151, both private.
  - `src/ocutalon/cls/OcuTalon/Test/Agent/KeyScan.cls`: the public `Find` :125, the private `GuardReason` :220, `FindRequest` :230 and `Has` :244.
  - `src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls:177 HasTemplateCall`, private: the comment-line rule that the new code scans reuse.
- **Lane B (read only):**
  - `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls` (call only): `CheckBaseUrl` :267, `CheckMockKeyFlag` :274, `LogMark` :365 and `LogSince` :378.
  - `docker/tests/test-production.sh:127-150` (row 16): `TriageAgent` must answer an `Ens.StringRequest` with `#5003: Not implemented` and no response, and keep its job.
  - `docker/tests/lib-live.sh:602-607 item_jobs`: lists jobs through `Ens.Job:Enumerate` (`State` `Alive`, `ConfigName`).
  - `docker/tests/lib-live.sh:633-641 check_no_key` and `ci/compose.ci.yml`: CI starts with no key variable on purpose.
- **The CI mock:**
  - `ci/mock/mock.mjs`:
    - A log entry (:363-379) holds `model`, `maxTokens`, `status`, `rejected`, `scenario` and `headerNames`.
    - `request` (:152-161) holds every top-level body field as sent, so `output_config` is visible there. It also holds `system` as `{chars, cacheControl}`, `tools` as `[{name, cacheControl}]`, and the messages in full.
    - The sampling and cap rejections are at :428-433.
  - `ci/mock/test/constants.test.mjs:82-91`: only `mockkey` scenarios must call `Tools.Names` tools, so a marker scenario may call a test tool.
  - `ci/mock/scenarios/A/refusal.json` and `max-tokens.json`: the stop-reason scenarios.

## Tasks & Acceptance

**Execution:**

**Task 0: measure, and record the results under `## Verification` as measured facts.**
- Use a throwaway of tag `e1s2a`, once the runner compiles.
- **(a)** Read the logged request of one `TriageAgent` and one `DiagnosisAgent` request, and record:
  - `request.system.cacheControl`, the last tool's `cacheControl`, any top-level cache field, and `request.output_config`.
  - If no cache marker shows for a runner, stop with status `blocked` and the condition: "intent gap: AC3's 'its log shows ... the cache settings' is unmeasurable for <runner>, because AI Hub marks no block under `min_tokens_for_cache` 512 (measured: <facts>)". Recommend the amendment: "... the cache settings, where the cached prefix reaches `min_tokens_for_cache`, and the cache block reaches the provider for every runner".
  - **Resolved 2026-10-21:** this stop rule fired on the first implement pass (Triage and Chat unmarked), and the lead amended AC3 (Spec Change Log). Do not halt on it again; record the measured facts and follow the amended AC3.
- **(b)** What `ChatAgent` answers for `chat.json`, whose first reply calls `list_productions`, a tool Chat does not have.
- **(c)** How an `OnInit` refusal shows: the status of `TempStopConfigItem(item, 0)`, `NotRunning()`, and the event-log row's type and text.
- **(d)** The `finish_reason` of a normal reply.
- **(e)** The exact error text of a runner request with no key.
- Make one stack at a time, and run `ci/iris.sh teardown` after.

**The bridge.**
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - **Settings.** Add the settings `Effort` and `AgentAllowList`, a comma-separated list of agent class names.
  - **`OnInit`.** It fails, naming the setting or the class, when:
    - any setting of the refusal row is set (non-empty once white space is removed; `{}` counts as unset for `SessionConfigString`);
    - `AgentClass` is not a compiled `%AI.Agent` subclass;
    - `AgentClass` is not an exact entry of `AgentAllowList` (an empty list refuses every class).

    Otherwise it returns OK without building.
  - **The build.** A build method runs the base `OnInit` once, by deferral, never as a copy. Then it clears `Agent.Temperature`.
  - **The composer.** A class method composes the session config from the agent's `MaxIterations`, the resolved model and the effort:
    - It takes the longest `ModelFamily.ModelPrefix` that the model starts with.
    - It sets 8000 at the family's dot-separated `CapKey`.
    - It sets the effort at `EffortKey` when both are non-empty.
    - It sets `max_iterations` when the agent has one.
    - It sets the cache block.
    - It fails on an empty model or no match.
  - **Sessions.** One method creates a session with the composed object, and one opens a session by id with a newly composed object.
  - **The request.** One method answers a `Request`, given the super session:
    1. It refuses kind `tool` (`$$$NotImplemented`), any kind outside `REQUESTKIND`, and an empty `Input`.
    2. It builds the agent if needed.
    3. It runs `Context.Begin`.
    4. It creates a throwaway session.
    5. It calls `Chat(session, Input)`.
    6. It fills a `Reply`: `Text` from `Content` (a stream read whole), `FinishReason` from `Extra.finish_reason`, and `HostData` and `Tainted` from the context.
    7. It runs `Context.End` on every path.
  - **The inventory.** One method returns `{"tools":[{"name","source","provider","status","reason"}]}` from `Agent.ToolManager.GetToolStatuses()`, after building.
  - Rationale: AD-6, AD-7, AD-10, FR-38.
- `src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls`:
  - Delete `STUB` and the stub handler.
  - `OnMessage` answers `Request` through the adapter with `..%SuperSession`, and `ToolInventory` with an `Ens.StringResponse` holding the JSON. Any other message class gets `$$$NotImplemented` with no response.
  - Update the class comment.
  - Rationale: AD-6, AD-29.
- `src/bridge/cls/OcuTalon/Bridge/Msg/Reply.cls`: append `FinishReason As %String(MAXLEN = 32)` ("the provider's stop reason from `Response.Extra`, empty when it reports none"), and commit the regenerated storage. Rationale: AD-6, AD-8.
- `src/bridge/cls/OcuTalon/Bridge/Msg/ToolInventory.cls` (new): an `Ens.Request` with no properties, which asks a runner for its live ToolManager's tools. Commit its storage. Rationale: AD-10, FR-10.
- `src/bridge/cls/OcuTalon/Bridge/Installer.cls`:
  - `Run()` also upserts by `Family` the rows `anthropic`/`claude-`/`max_tokens`/`extra_params.output_config.effort`, `gpt-5`/`gpt-5`/`extra_params.max_completion_tokens`/"" and `default`/""/`max_tokens`/"".
  - It keeps every other row.
  - Rationale: AD-7, AD-19.

**The product.**
- `src/ocutalon/cls/OcuTalon/Agent/Triage.cls`: add `Parameter EFFORT = "low";`, commented as the seed of the runner's `Effort` setting.
- `src/ocutalon/cls/OcuTalon/Agent/Diagnosis.cls`: add `Parameter EFFORT = "high";`.
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls`: `MaxIterations` 4 on the agent (AI Hub's own property), and no `EFFORT`. Rationale: AD-7, AD-20.
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls`:
  - Extend `SeedModels`' loop (`Runners`, `GetAdapterSettingValue`, `WriteDefault`) to seed `Effort` per runner from `EFFORT` when absent.
  - Seed one `AgentAllowList` row for every item (item `*`) holding the runners' distinct `AgentClass` values, when no runner resolves a value.
  - `Run()` seeds both after `SeedModels` and before `Start`.
  - Rationale: AD-19, AD-23.

**The mock (Lane A's folder).**
- `ci/mock/scenarios/A/context-probe.json` (new): marker `context-probe`. Its replies are a `toolUse` `zz_context_probe {}`, then the text `The probe ran.`.

**Tests.**
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Source.cls` (new helper): the code lines of a class's UDL text, with the comment rule of `Instructions.HasTemplateCall`, and a public match of patterns, case-insensitive. `Test/Agent/Instructions.cls` uses it in place of its private loop (Rule 2).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeAgent.cls`, `ProbeTools.cls` and `ProbeTool.cls` (new fixtures):
  - The agent: an `%AI.Agent` with short INSTRUCTIONS, no `{{`, `MODEL` `claude-haiku-5-5`, and `TOOLSETS` naming the toolset.
  - The toolset: one `<Tool Name="zz_context_probe" Class=... Method=...>` and `DependsOn` the tool.
  - The tool: it reads `Context.Current()`, `Put`s `HostData` as JSON of every field it saw, `Put`s `Tainted` 1, and returns a dynamic object. It makes no `%AI` and no Python call.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/SessionConfig.cls` (new, pure):
  - Every pure matrix row.
  - The exact composed JSON for Triage, Diagnosis and Chat.
  - No `temperature`, `top_p` or `top_k` at any depth, even for an agent whose `Temperature` was set before the build.
  - The installer's three rows exactly; a re-run keeps an extra `ZzFamily` row and rewrites a changed seeded row.
  - It restores the rows.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Runner.cls` (new, in process, needs the mock):
  - **Setup.** The guard is `Mock.CheckBaseUrl` and `CheckMockKeyFlag`, as in KeyScan. The runner host comes from `%New("ZzRunner")` (a shadow). The adapter's properties are set in memory, with `ProviderConfig` inline: `{"model_provider":"anthropic","api_key":"@{env:OCUTALON_MOCK_KEY_HEADER}","base_url":<the mock>}`, plus the mock-key header where a default scenario is used.
  - `TestRefusals`: each setting of the refusal row, the allow-list cases, and `{}` with white space passing. `Agent` is still unbuilt after a passing `OnInit`.
  - `TestBuildRetried`: an unset placeholder variable gives an error twice, and then a valid one builds.
  - `TestContext`: the probe row, through `runner.OnMessage`, after the test sets the shadow host's `%SuperSession` to a fresh value. The request carries a fresh value in every context field.
  - `TestFinishReason`.
  - `TestOpenKeepsConfig`: open through a second runner host.
  - `TestUnbuiltKinds`.
  - Each test deletes its AI sessions.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` (new, static), each check with samples that it flags and passes:
  - `TestCallbackRule`: every compiled `OcuTalon.*` class that extends `%AI.Tool`, `%AI.ToolSet`, an `%AI.Policy` base or `%AI.Shell.StreamRenderer` holds no `%AI` reference on a code line other than its `Class ... Extends` line (the regex of `test-class-rules.sh`), and no `Language = python`, `%SYS.Python` or `$SYSTEM.Python`.
  - `TestOnlyRunnersChat`: no non-test `OcuTalon.*` class other than the runner and its adapter calls `.Chat(`, `.ChatWithContent(`, `.StreamChat(`, `.SendChat(`, `.SendChatWithContent(`, `.RunAgent(` or `.ChatComplete(`.
  - `TestRunnerStartsNoJob`: the runner and the adapter hold no `JOB` command and no `WorkMgr`.
  - `ToolCodeClean(class)`, public, used by the inventory test: no `$ZF(`, no `XECUTE` or `$XECUTE(`, no `$SYSTEM.OBJ.`, no Python, and no `INSERT`, `UPDATE`, `DELETE`, `DROP`, `CREATE`, `ALTER` or `TRUNCATE` inside `&sql(` or at the start of a string literal.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Contracts.cls`: add `FinishReason` to Reply's contract, and add the `ToolInventory` contract.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls`: update `TestStubAdapter`'s header; the runner is no longer a stub.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` (new helper):
  - `Running` and `Restart`, moved from `Models`.
  - `Send(target, message, Output response)` through `ApprovalStartIn`.
  - `PointKeys()` and `RestoreKeys()`: `Merge` each runner's entry to `@{env:OCUTALON_MOCK_KEY_HEADER}` or `@{env:ANTHROPIC_API_KEY}`, then restart the runners.
  - `Jobs(item)`, from `Ens.Job:Enumerate`.
  - `FindRequest` and `Has`, moved from `KeyScan`. `KeyScan` and `Models` call them.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls` (new; live, throwaway only):
  - `TestStartsWithNoKey`: guard that the container has no key, then the no-key row.
  - `TestStartRefused`: a `SystemPrompt` row, then the allow-list without Triage, each with a restart and a restore.
  - `TestRequestsUnderTheModelRules`: the Triage, Diagnosis and Chat rows.
  - `TestToolInventory`.
  - `TestForeignMessage`.
  - `TestPoolIsTheCap`: each runner's alive jobs equal its pool size.
  - `OnAfterOneTest` restores the keys and the rows, and restarts the runners.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Models.cls`: `TestModelChange` also points the keys, sends one `diagnose` Request after the change, and asserts the mock's `model`, `maxTokens` and effort, restoring as now.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`:
  - Set `"stub": 0` on the three runner rows, and update the header.
  - Add `TestSeedEfforts` and `TestSeedAllowList` on the fixture production: an existing row is kept, a class with no `EFFORT` gets no row, and the existing cleanup removes the rows.
- Prove every matrix row with these tests.

**Re-dispatch (cycle iteration 2): continue from the working tree.**
- The working tree already holds a previous pass's uncommitted implementation of this spec, kept on purpose. Verify and correct it against this spec, amended AC3 included, finish what is missing, and never revert it or start over. Task 0 (a)'s stop rule is resolved: do not halt on it.
- `Test.Agent.Runners.AssertRequests` follows the amended AC3 and the matrix: Triage and Chat have no cache marker on the system block or a tool, and their composed config holds the exact cache block; Diagnosis has the last tool's marker; the "Cache over the threshold" row is covered by a test that sends a probe agent with a long system prompt through the runner path and sees the system marker.
- Re-derive the AC3 "cache block omitted" mutation: `BuildSessionConfig` (`irislib/%AI/Agent.cls` about :632-634) sets `cache` from the agent's `CachingEnabled` when the config has no `cache` key, so measure what omitting the block does before naming the mutation. If it changes nothing observable at the mock, pin the block through `Test.Bridge.SessionConfig`'s composed config and say so in the `mutation:` line.
- No lane-a test class and no Rule 19 mutation has run yet: run the ten classes of `## Verification`, one per call, and record one `mutation:` line per AC under `## Verification`.
- Record the previous pass's code-level choices (listed under `## Auto Run Result`) as further items under `## Design Notes` "Decided in-stage", after correcting any of them that you change.

**Acceptance Criteria:**
- **AC1, the start.** Given the runner items with `OcuTalon.Bridge.Adapter.Agent`, when an item starts, then it refuses to start with any refused setting set, or with an `AgentClass` not on `AgentAllowList`, and the event log names why. With no key in the environment it starts and runs, because the agent is built on first use (`Test.Agent.Runners`, `Test.Bridge.Runner`).
- **AC2, the session config.** Given any request, when the runner creates or opens the AI session, then one method composes the config from the agent and the resolved model's `ModelFamily` row. It holds the cap, the effort, `max_iterations` (4 for Chat) and the cache block, never a sampling parameter, and the same composition applies when a session is opened (`Test.Bridge.SessionConfig`, `Test.Bridge.Runner.TestOpenKeepsConfig`).
- **AC3, the integration AC.** Given the CI mock, when each runner sends its default scenario's request, then the mock accepts every request and its log shows `claude-haiku-5-5`, 8000, the effort and the cache settings, which mark every block whose cached prefix reaches `min_tokens_for_cache` (Diagnosis's last tool; a probe agent's long system prompt through the same runner path), while Triage's and Chat's short prefixes stay unmarked and every runner's session carries the cache block [AMENDED 2026-10-21 — see the Spec Change Log]. After `DiagnosisAgent`'s `Model` changes to `claude-sonnet-5-5` and it restarts, its next request names that model. The consumer here is AI Hub's Anthropic provider path, read through the mock's log.
- **AC4, the request.** Given a request reaching a runner, when it calls `Chat`, then the context was set first (request fields, `ThreadSessionId`, `SuperSession`, the taint and `HostData`). `Response.Extra` is kept as `FinishReason`, and afterwards `HostData` and the taint are on the `Reply`. No product class but the runner calls `Chat`, and each runner's pool size is its concurrency cap.
- **AC5, the callback rule.** Given the tool, policy and renderer classes, when `Test.Bridge.CodeRules` runs, then it fails on any `%AI` reference beyond their base classes and on any Python use.
- **AC6, the live inventory.** Given every running runner, when `Test.Agent.Runners.TestToolInventory` inspects its live ToolManager, then no AI Hub shell, filesystem, SQL or web-search tool is registered, and the test fails on any tool that is not an OcuTalon iris tool with clean code.

## Spec Change Log

- 2026-10-21, lead (Epic 1 runner), after the first implement pass's intent-gap HALT at Task 0 (a). Rule 5 apply-and-report amendment (restating an observable so it is measurable; the intent is unchanged), ruled `category=decide`:
  - **Where:** `epics.md`, Story 1.2, the third Given/When/Then (the CI mock), its `Then` line, with an inline `[AMENDED 2026-10-21 — see the story change log]` marker; this spec's AC3, the I/O matrix rows for Triage, Diagnosis and Chat, and a new matrix row "Cache over the threshold".
  - **Original:** "the mock accepts every request, and its log shows the model `claude-haiku-5-5`, the 8,000-token cap, the effort and the cache settings".
  - **Amended:** "the mock accepts every request, and its log shows the model `claude-haiku-5-5`, the 8,000-token cap, the effort and the cache settings, which mark every block whose cached prefix reaches `min_tokens_for_cache` (a shorter prefix is never marked), while every runner's session carries the cache block".
  - **Rationale:** AI Hub applies AD-7's cache block (`min_tokens_for_cache` 512) by marking only a prefix that reaches the threshold. Triage's and Chat's prompts are about 190 to 310 tokens, so the mock's log can never show a marker for them, while every runner's composed session config holds the exact block and a probe prompt of about 800 tokens through the same runner path is marked (Task 0 (a), measured). AD-7's rule and NFR-2 (output caps) are unchanged; no spine edit.
  - **Status:** reset from `blocked` to `in-progress` to re-implement. The halted pass's written implementation stays in the working tree, uncommitted, for this pass to continue from (the lead saved a copy outside git).
- 2026-10-21, implement stage (re-dispatch, cycle iteration 2): added the "Re-dispatch" task block under Tasks & Acceptance and Design Notes 15 to 25, and wrote the measured facts, the review pass and the `mutation:` lines under Verification. The intent contract, the acceptance criteria and the I/O matrix are unchanged.

## Review Triage Log

### 2026-10-21 — Review pass
- verdicts: 43 findings — high 0, medium 4, low 28, false 11, maybe-false 0
- findings (layers in the order they reported: Blind Hunter BH1-10, Edge Case Hunter EC1-12, Verification Gap VG1-13, Intent Alignment IA1-8):
  - `[low]` `[reject]` BH1 `SeedAllowList` seeds all or nothing, so a runner with its own item row leaves the others with an empty list, and a runner or agent class added later never reaches an existing row — the spec fixes this shape ("when no runner resolves a value", one row for every item), the effect fails closed naming the class, and `SeedModels`/`SeedEfforts` seed per runner because their values are per runner; the story that adds a runner or an agent class (13.1 for the example) adds it to the row. `reopen_if`: a product runner item whose class is not in an existing install's row ships.
  - `[low]` `[reject]` BH2 `Effort` is not validated against low/medium/high — the set is the provider's, not ours (a new level would be refused by our own check), the seeds are `low` and `high` from the agent classes, and a bad value comes back as the provider's error status; the settings page (Epic 17) owns choosing the value.
  - `[low]` `[reject]` BH3 `Answer` does not validate `Provenance` — the spec's refusal list is kind, `tool` and empty Input; `Decide` (Story 1.3) is the only sender and fills it from the enumeration, and the gate (Epic 3) is the consumer that must fail closed. `reopen_if`: the gate treats a missing provenance as `user`.
  - `[medium]` `[defer]` BH4 Nothing sets `Reply.ToolsRun` — verified: `Answer` fills `Text`, `FinishReason`, `HostData` and `Tainted` only, no story's acceptance criteria names who sets the field, Story 1.7 and the evaluation stories read it, and `%AI.LLM.Response` carries the tool-call count. Not this story's contract (its Approach lists the fields it copies); recorded under `deferred:` for the lead to route.
  - `[medium]` `[patch]` BH5 `Answer`'s `Catch` (a failure inside `Chat` becomes the error status) has no test — added `Test.Bridge.Runner.TestChatErrorIsStatus` (the mock's `provider-error` marker: error status with AI Hub's text, no response, context over, the next request answered); the mutation that drops the `HandleError` line turns it red.
  - `[low]` `[reject]` BH6 `NewSession`, `OpenSession` and `SessionConfigFor` assume a built agent, and an open of a still-attached session ignores the config — their only callers are `Answer` (builds first) and the tests; the doc comments state both preconditions, and Story 1.8 opens with a freshly built adapter as `TestOpenKeepsConfig` does.
  - `[low]` `[reject]` BH7 The `JOBS` scan misses a `Job` after another command on the line (`If x Job ..Run()`) — the pattern is limited on purpose, to keep `Set text = "the job is kept"` and `Do ..Jobs(item)` passing; widening it adds false positives, and the scan covers two small classes that review reads.
  - `[low]` `[reject]` BH8 `ToolCodeClean` misses `X code`, `ZSYSTEM` and `CPIPE` — it is the second line behind the live inventory (AD-10's registry check), covering the forms a tool author writes; the three omitted forms are not used in a tool method, and a wider list is guesswork.
  - `[low]` `[patch]` BH9 `TestOnlyRunnersChat` skips a class whose source cannot be read — it now collects such classes and asserts none, except the 15 generated process-message stub classes ("is a stub name and can not be opened", measured on the slot); the first version of the check failed on those stubs, which is how they were found (Design Notes 24).
  - `[low]` `[reject]` BH10 `SessionConfig.Upsert` and `Delete` ignore the status of their write — a save of a three-field row cannot fail here, and a failed restore would show in the next class that reads the rows; asserting each write turns two private class methods into instance methods for no reachable failure.
  - `[false]` `[reject]` EC1 `OnInit` throws for a class with no superclass, because `%Extends` would not exist — measured on build 154 (slot): `$ClassMethod(class, "%Extends", "%AI.Agent")` returns 0 without an exception for `OcuTalon.Test.Bridge.Source`, `OcuTalon.Bridge.Installer` and `OcuTalon.Bridge.Context`, which have no superclass, so the refusal names the class.
  - `[low]` `[reject]` EC2 Same as BH2 (an `Effort` outside low/medium/high) — rejected for the reason given there.
  - `[low]` `[reject]` EC3 Two `ModelFamily` rows with one `ModelPrefix` give no defined winner — the unique key is `Family`; the query reads in id order and `>` keeps the first, so the result is stable, and nothing writes a second row for a prefix.
  - `[low]` `[reject]` EC4 A model id in another case or with spaces falls to the default family and loses its effort — the id is sent to the provider as written, so a normalised copy for the family lookup alone would hide a wrong id; the model comes from the settings page's list.
  - `[low]` `[reject]` EC5 `CapKey` and `EffortKey` that overlap or have an empty segment overwrite each other — the rows are the installer's structural rows (AD-19) and no code or setting writes another pair; theoretical.
  - `[low]` `[patch]` EC6 An Input of white space only passes the empty check and is sent — `Answer` now strips white space and control characters before the check (Design Notes 23); `TestUnbuiltKinds` sends `Chr(32,9,13,10)` and the mutation that restores the old check turns it red.
  - `[low]` `[reject]` EC7 A key rotated in the Config Store is not read until the item restarts — by design: settings apply on a restart (Story 17.3), and the failure classes (`no_key`, authentication) are Story 1.6's.
  - `[false]` `[reject]` EC8 `ClearSampling` throws after the agent is kept — the statement is `Set agent.Temperature = ""` on an `%AI.Agent` property; it cannot raise, and the method runs after the build succeeded.
  - `[low]` `[reject]` EC9 Same root cause as BH1 (`SeedAllowList` per runner) — rejected for the reason given there.
  - `[false]` `[reject]` EC10 The new `Restart` can leave an item temp-stopped where the old one always started it — it starts the item whenever the stop call succeeded; a stop call that fails stopped nothing, so no item is left stopped by it.
  - `[low]` `[reject]` EC11 Same root cause as BH7 (the `JOBS` pattern) — rejected for the reason given there.
  - `[low]` `[patch]` EC12 No test pins the call of `ClearSampling` in `BuildAgent` (`TestNoSampling` calls the method itself) — `TestContext` now asserts that the built probe agent's `Temperature` is empty; with the call removed it and `TestCacheOverThreshold` go red (the second through the mock's 400).
  - `[medium]` `[patch]` VG1 `Answer`'s failure path is untested — the same root cause as BH5, fixed by `TestChatErrorIsStatus`.
  - `[low]` `[patch]` VG2 `Inventory`'s `reason` field is never read by a test — `TestToolInventory` now flags a tool whose `reason` is not empty; a fixture tool that fails to add is not built (`GetToolStatuses` listing failed tools is AI Hub's measured behaviour, Design Notes 11).
  - `[low]` `[reject]` VG3 Chat's outcome is not asserted in `TestRequestsUnderTheModelRules` — spec-bound: the Chat matrix row says AC3 asserts the log only, because `chat.json` calls a tool that Chat gets in a later story; Task 0 (b) records the answer.
  - `[low]` `[patch]` VG4 The AC4 and AC5 mutation lines show the regex works, the scans skip unreadable classes and cannot follow calls — the silent skip is fixed with BH9; the transitive blind spot is closed `by-design` (AD-6 fixes a source scan as the mechanism, and the live inventory covers what a scan cannot).
  - `[low]` `[patch]` VG5 The AC1 line "build moved into `OnInit`" never went red at test level — demonstrated: `OnInit` that also builds, with the failure ignored, turns `Runner.TestRefusals` ("has built no agent") red; the line under Verification says so.
  - `[low]` `[patch]` VG6 `TestRefusals` goes red for a dropped refusal only through the count 9 — it now compares `REFUSED` with the nine names; swapping `SystemPrompt` for `ProviderName` turns it red.
  - `[low]` `[reject]` VG7 Sub-behaviours have no `mutation:` line of their own (allow-list match, the 8000 cap and `CapKey`, the `ToolInventory` branch, the seeds, the kind and Input refusals, the pool size) — Rule 19 asks for one demonstrated mutation per acceptance criterion, each of these is pinned by a test that ran green and the AC lines above are red; the one named gap, the `ClearSampling` call, is EC12.
  - `[low]` `[patch]` VG8 `TestOpenKeepsConfig` is green under its own defect if the first session stays open in the process — it now asserts that the saved session is attached to no agent when it is opened; the "passes no config" mutation is red again with the check in place.
  - `[medium]` `[patch]` VG9 `TestStartRefused` passes when the other runners had no job to begin with, and `AssertOthersRun` reads the jobs with no wait — it asserts the other runners' jobs first and waits up to `WAITSECONDS` for them (Design Notes 25).
  - `[low]` `[patch]` VG10 `RunnerFixture.Restart` discards the wait's result — it returns an error status when some item still does not run after `WAITSECONDS` (Design Notes 25).
  - `[low]` `[reject]` VG11 The no-marker assertions of `AssertRequests` go red when a prompt grows past the threshold — by design: the amended AC3 and the matrix pin the measured fact that short prefixes stay unmarked; the cache block itself is pinned by the exact config JSON and the probe's system marker.
  - `[low]` `[reject]` VG12 `entries.%Size() = 0` covers every mock request since the mark, not only the test's own — each stack has one mock and the runners are idle between tests; the window is the test's own in a throwaway.
  - `[low]` `[reject]` VG13 `ContentText`'s stream branch cannot run, because `Response.Content` is a string — the spec's Code Map and Approach read `Content` as a stream when long; the branch is four lines, harmless, and no test can drive it.
  - `[false]` `[reject]` IA1 The seeds are tested on a fixture production, not on `OcuTalon.Production` — descriptive; the product's own rows show on the wire (Triage `low`, Diagnosis `high`) and in the runners starting under the allow-list, in `Runners` and the live scripts, and the Production step is the spec's named unit.
  - `[false]` `[reject]` IA2 The installer's families are tested through `SeedModelFamilies`, not `Run` — descriptive; `Run` calls it, and the live `install-start` (bridge alone, `Run()` returns 1), `audit` and every live runner request need the rows.
  - `[false]` `[reject]` IA3 The nine refusals and the allow-list cases are tested in process, and only two live — descriptive and as the spec plans it ("the live tests cover what the running items do").
  - `[false]` `[reject]` IA4 The no-model failure is tested by clearing the built agent's model, not through an item with no `Model` setting — descriptive; the item case is Story 1.1's `UnresolvedRunners`, and the matrix row asks for nothing sent and an error saying that none resolves.
  - `[false]` `[reject]` IA5 `max_iterations` is asserted through the composed config, and live `Tainted` only at 0 — descriptive and as the matrix plans it (the probe row is in process).
  - `[false]` `[reject]` IA6 The wire's tool names for Diagnosis are not compared with the registry — descriptive; the registry is the spec's surface (AC6) and the wire shows the tools and the last one's marker.
  - `[false]` `[reject]` IA7 `SendChat`, `SendChatWithContent` and `RunAgent` of the base adapter are not overridden — descriptive; `TestOnlyRunnersChat` fences them and the runner calls only `Answer`.
  - `[false]` `[reject]` IA8 The code rules reach beyond the runners, tests are placed in `Test.Install`, helpers moved out of `KeyScan`, and the script texts are copied — descriptive; AC5 names every tool, policy and renderer class, the spec lists each edit, and the copies are Design Notes 18.
- stage read (not a layer finding): two test headers narrated "no longer a stub" (`Test.Bridge.Api`, `Test.Install.Production`); both now state what is pinned (Rule 14).

## Design Notes

**Governing architecture decisions (Rule 6):**
- **AD-2:** no bridge code names an OcuTalon package. So the allow-list seed comes from the product's Production step, and the bridge's own default is empty.
- **AD-5:** the XData holds structure only, values are rows, and storage is append-only (`Reply.FinishReason`, `ToolInventory`).
- **AD-6:**
  - the runner and its adapter: refusals, the allow-list, build on first use, one composing method on create and open, `Response.Extra` kept, the context set before `Chat` and copied after;
  - only runners call `Chat`, and the pool size is the cap;
  - the callback rule.
- **AD-7:** the model from the setting, `ModelFamily`, the cap, effort only for Anthropic models, `max_iterations`, the cache block, no sampling parameters.
- **AD-8:** errors and `finish_reason` are kept for Story 1.6's single classifier; nothing is classified here.
- **AD-10:** no shell, filesystem, SQL or web-search tool; a test inspects every running runner's ToolManager.
- **AD-19:** `Effort` and the allow-list are seed values; model families are structural; the key exists only as a placeholder.
- **AD-22:** tests sit in the areas, and Lane A only adds scenario files.
- **AD-23:** the Production step's order, and a failed start writes no ready marker.
- **AD-29 and AD-33:** the runner leaves the stub set; the footprint.

**Decided in-stage:**
1. **Where the settings live.** `Effort` and `AgentAllowList` are settings of the adapter, because AD-6 gives the refusal and the composition to the adapter.
   - Effort seeds come from an `EFFORT` agent parameter, read only by the seeding (the same single-source rule as `MODEL`, Story 1.1 decision 8).
   - The allow-list seed is the runners' `AgentClass` values, in one item-`*` row, so no class name is hard-coded.
   - An empty list refuses every class (fail closed). Story 13.1's example adds its own agent to the list, as a developer would.
2. **What "set" means.** A setting is set when it is non-empty after white space is removed. `SessionConfigString`'s class default `{}` counts as unset. `ProviderName` is not in the AC's list and is not refused.
3. **The deferred build.** "Build on first use" defers the base `OnInit`, so the base's settings logic is reused, not copied (Rule 2). A failed build is not kept, because a key set later must work after a restart.
4. **The family rows.** There are three rows, and the longest prefix wins. The `default` row sends only `max_tokens`, because AD-7 sends no effort to other families "until a story tests their own field". A model that no row matches, possible only when the table lacks the `default` row, sends nothing.
5. **`max_iterations`.** Only Chat declares it (AD-7 fixes only Chat). Triage and Diagnosis keep AI Hub's unset default. `timeout_ms` bounds them from Story 1.7.
6. **Temperature.** The adapter clears the agent's `Temperature`, so that an allow-listed agent class can never make AI Hub add `temperature`.
7. **Keeping `Response.Extra`.** It is kept as `Reply.FinishReason`: `finish_reason` is the only `Extra` field the spine uses (AD-8), and copying `Extra` whole would put more unfiltered model output into a stored message.
8. **Message classes.** Any message class other than `Request` and `ToolInventory` gets `$$$NotImplemented` (5003). That is the honest answer for a class the runner does not handle, and it keeps Lane B's row 16 green without a contended edit. Kind `tool` gets the same answer until approved-call replay lands (Epic 30). An empty `Input` is refused before sending, because the mock and the provider reject an empty message.
9. **Errors.** A build or `Chat` exception becomes the runner's error status, with AI Hub's text, unredacted. AI Hub's no-key text names only the variable (measured). The redactor is Story 1.5's.
10. **Sessions.** Every request uses a fresh AI session that is never saved. The opening method exists now because AC2 names "opens", and `TestOpenKeepsConfig` pins it for Story 1.8. Story 1.1's note "reuse `KeyScan.Find` for runner-saved sessions" therefore applies from Story 1.8, which is the first story whose runner saves a session.
11. **The inventory.** A live ToolManager lives in the runner's job, so the runner reports it through a `ToolInventory` request, read from `GetToolStatuses()`. That list holds every tool attempted, with `source` and `provider` (measured), so the inventory never depends on the build-time event log. With no key the agent cannot be built, so the inventory test points the keys first.
12. **The key fixture.** CI starts with no key on purpose (`check_no_key`, Story 1.6). The live tests therefore `Merge` each runner's entry to `@{env:OCUTALON_MOCK_KEY_HEADER}`, a non-secret CI-only variable (value `1`), restart, and restore afterwards. This is the product path (entry, `@{config:}`, provider); it changes no Lane B file and writes no literal key. The in-process tests use the same placeholder inline, in memory.
13. **In-process and live tests.** The in-process tests run the real `AgentRunner.OnMessage` on a shadow host. That is the only way to run a probe agent, because a production item's `AgentClass` is fixed in the XData and wins over default rows. The live tests cover everything that the running items do.
14. **The sender.** The live tests send through `ApprovalStartIn`, Lane A's adapterless service, not through Lane B's `CommandsIn`.
15. **How the adapter reuses AI Hub's `OnInit`.** A `Building` flag lets the adapter's own `OnInit` defer to AI Hub's through `##super()` while `BuildAgent` runs it, so the base settings logic is reused and not copied (Rule 2). Outside a build, `OnInit` is `CheckSettings` and calls nothing in AI Hub.
16. **The shape of the adapter's methods.** `Compose(maxIterations, model, effort, Output config)` is a class method that returns a status (so a test can run it with no agent), and `ClearSampling(agent)` is split out so that a pure test shows AI Hub adding nothing once the temperature is cleared. The instance methods are `CheckSettings`, `BuildAgent`, `SessionConfigFor`, `NewSession`, `OpenSession`, `Answer` and `Inventory`.
17. **What white space is.** `$ZStrip(x, "*W")` removes only the space, the tab and the non-breaking space (measured on build 154), not a line feed or a carriage return. A setting that holds only line breaks is treated as unset too, so `CheckSettings` strips `"*WC"` (white space and control characters), and the allow-list entries are trimmed with `"<>WC"`.
18. **`RunnerFixture` and the scan helper.** Besides the spec's helpers, `RunnerFixture` holds `GuardReason` (moved out of `KeyScan`), `Ask`, `Effort`, `CacheMark`, `FindRequests`, `EventMark`, `EventRows`, `WaitAllRun` and `Restart(name, wait)`, and repeats the replies of the Triage and Diagnosis scripts as `TRIAGETEXT` and `DIAGNOSISTEXT`. `Test.Bridge.CodeRules.ToolCodeClean` has the signature `(class, Output problems, text="")`, so that the samples of the scanner tests pass their own text. `Test.Bridge.Runner.NORMALFINISH` is `end_turn` (measured).
19. **The cache over the threshold is shown in process.** A production item's `AgentClass` is fixed in the XData, so the live runners cannot run a long-prompt agent. `Test.Bridge.ProbeLongAgent` (the probe agent with no tool and a system prompt of about 3,200 characters) goes through the real `AgentRunner.OnMessage` in `Runner.TestCacheOverThreshold`, and its logged system block carries the marker. The live test, `Runners.AssertRequests`, follows the amended AC3: no marker on any system block, the marker on Diagnosis's last tool only, and none at all for Triage and Chat.
20. **What omitting the cache block does.** Without a `cache` key, AI Hub's `BuildSessionConfig` sets `cache` to the agent's `CachingEnabled` (`true`), and AI Hub's own default threshold is above 512 tokens. Measured at the mock: the live runners' logs do not change (Diagnosis's last tool is still marked), but the probe's 3,200-character system block loses its marker, so AI Hub's default threshold is evidently above that prefix and below Diagnosis's system-plus-tools prefix (an inference; the default itself was not read). So the block is pinned twice: by the exact composed JSON (`SessionConfig`, `Runner.TestCacheOverThreshold`) and by the probe's marker; `Runners.TestRequestsUnderTheModelRules` alone cannot see it.
21. **The allow-list row restarts the other runners.** The row is for every item, so the production update that follows a restart of Triage gives Diagnosis and Chat new jobs. `Runners.TestStartRefused` therefore asserts that the others keep their jobs for the SystemPrompt row (the item's own) and only that they run with one job each for the allow-list row.
22. **Two hazards found in the tests.** `Ens.Config.Production.findItemByName` is an internal method: called without its `pCommentOrClass` argument it throws inside an open embedded-SQL cursor, and every later `TempStopConfigItem` in that process then reports "Item not found", so `TestPoolIsTheCap` reads `Ens_Config.Item.PoolSize` by SQL. And `OpenSession` returns the session object that is still open in the process, whose agent is attached, so AI Hub ignores the new config: `Runner.TestOpenKeepsConfig` saves the first session in `SaveSession`, lets the first adapter go out of scope, and only then opens it through a second adapter (the first version of the test stayed green when the open passed no config).
23. **White space is empty (review pass).** `Answer` refuses an Input that is empty once white space and control characters are removed (`$ZStrip(x, "<>WC")`), for the reason the spec gives for an empty one: the provider rejects a blank message, and nothing should be sent for it.
24. **The Chat-family scan and generated classes (review pass).** `CodeRules.TestOnlyRunnersChat` asserts that every non-test `OcuTalon.*` class has readable source, so that a class cannot drop out of the scan unseen. The 15 `...MessagesReceived` and `...MessagesSent` classes that the process message tracking generates (measured: "is a stub name and can not be opened") hold no code and are the only exception.
25. **A restart that does not finish is an error (review pass).** `RunnerFixture.Restart` returns an error status when some item still does not run `WAITSECONDS` after the item was started again, instead of returning OK; `Runners.AssertOthersRun` waits for the other runners' jobs the same way, and `TestStartRefused` asserts that the other runners had their job before it changes a row.

**Integration ACs (Rule 1):**
- AC3: the CI mock, standing in for AI Hub's Anthropic provider path, receives each live runner's request and logs the model, the cap, the effort and the cache settings.
- No product consumer calls the runners in this story. The first is Story 1.3 (`Decide`).

**Consumed-by:**
- Story 1.3: `Decide` sends `Request`s to the runners and checks `Reply.Text` against `ReplyClass`.
- Story 1.4: `GetStats` around `Chat` inside the adapter's answering method.
- Story 1.5: `StepRenderer` passed to `Chat`, and `StepAudit` in `OnAfterAgentInit`.
- Story 1.6: classifies the runner's error text and `Reply.FinishReason`.
- Story 1.7: adds `timeout_ms` to the one composing method.
- Story 1.8: `ConversationLink`, the opening method, `%Save` after `Chat`, `SystemNote`, and `KeyScan.Find` on saved sessions.
- Stories 1.9 and 1.10: tools read the context.
- Epic 3: the gate in `OnAfterAgentInit` reads the context.
- Story 13.1: the example's allow-list.
- Story 17.3: model changes take effect through a runner restart.
- Step 4: MCP attach, and the inventory lists it.

**Consumes:**
- Epic 0: `Context`, `Msg.Request` and `Reply`, `Data.ModelFamily`, `ResolveModel`, `ApprovalStartIn`, `Test.Contract.Mock`'s public helpers, and the mock's stop-reason scenarios.
- Story 1.1: the agents, the entries and `ProviderConfig` rows, `Merge`, `Runners`, `SeedModels`, `WriteDefault`, `KeyScan`'s helpers, and `Models.TestModelChange`.

**Extend, don't copy (Rule 2):**
- The build reuses the base `OnInit`.
- The seeds extend `SeedModels`' loop.
- The code scans extend `HasTemplateCall` through `Test.Bridge.Source`.
- `Restart` and `Running` move out of `Models`, and `FindRequest` and `Has` out of `KeyScan`, into `RunnerFixture`.
- The model-change request extends `Models.TestModelChange`.
- Mock logs are read only through `Test.Contract.Mock`'s public `LogMark` and `LogSince`.

**Ledger:** this story's inbox is empty.

**Lane B pieces.** No contended edit is planned. Follow-ons for Lane B, not needed for this story:
- Row 16 of `test-production.sh` may retarget `TriageAgent` to a stub item when Lane B next edits that file.
- Story 11.5's release check should read `STUB` (AD-29), not probe with an `Ens.StringRequest`, because built runners answer a foreign message class with 5003.
- If CI ever gains a dummy key variable, the key fixture can stop pointing the entries.

## Verification

**Targets:**
- **The slot.** `ocutalon-slot-a` only, with MCP `server: ocutalon-slot-a` and `namespace: OCUTALON` on every call, after `iris_server_info` shows build 154. It is used for `iris_doc_load` compiles and process-local measurements only. No lane-a test class runs there.
- **Throwaways.** Everything else runs through `ci/iris.sh` with `OCUTALON_RUN_TAG=e1s2a OCUTALON_LOCK_OWNER='epic=1 stage=implement'` (QA uses `e1s2q`, review `e1s2r`). Make one stack at a time, give each call `timeout: 600000`, and run `ci/iris.sh teardown` with the same tag at the end.
- **Never** `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition` or `ocutalon-slot-b`. No push and no `gh workflow run`.

**Commands:**
- `bash ci/checks.sh` (loop): expected: every block passes (class rules, boundaries, storage), in about 20 s.
- `OCUTALON_RUN_TAG=e1s2a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh build` (loop): expected: exit 0.
- `OCUTALON_RUN_TAG=e1s2a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh class <Class>` (loop), one call per class while iterating. Run it for `OcuTalon.Test.Bridge.SessionConfig`, `.Bridge.Runner`, `.Bridge.CodeRules`, `.Bridge.Contracts`, `.Bridge.Api`, `.Agent.Runners`, `.Agent.Models`, `.Agent.KeyScan`, `.Agent.Instructions` and `.Install.Production`. Expected: `CLASS ... passed`.
- `OCUTALON_RUN_TAG=e1s2a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh shard lane-a` (loop): expected: every class passed, with the only SKIP the existing `TestStepHelpers` one. About 65 s before this story, plus about 60-120 s for the restarts and requests (inference).
- `OCUTALON_RUN_TAG=e1s2a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh teardown` (loop): expected: removes only e1s2a's projects.
- `bash docker/tests/test-mock.sh` (once): expected: all pass with `context-probe.json` added.
- `OCUTALON_RUN_TAG=e1s2a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh shard lane-b` (once): expected: every class passed, `Test.Data.Tables`, `Test.Msg.Contracts`, `Test.Contract.Ac` and `Test.Contract.Mock` among them.
- `... bash ci/iris.sh live production` (once, the same prefix): expected: PASS, with row 16 (TriageAgent answers 5003 and keeps its job), the sweep, and "a runner that resolves no model". About 85 s.
- `... bash ci/iris.sh live install-start` (once): expected: PASS, with the bridge alone in a fresh namespace and `Run()` 1. About 151-196 s.
- `... bash ci/iris.sh live install-upgrade` (once): expected: PASS; the second start keeps the seeds. About 164-172 s.
- `... bash ci/iris.sh live production-restart` (once): expected: PASS. About 87 s.
- `... bash ci/iris.sh live audit` (once): expected: PASS, with the installer re-run. About 76 s.
- `... bash ci/iris.sh live compose-start` (once): expected: PASS (no key, every item runs). About 80 s.
- `... bash ci/iris.sh live demo-path` (once): expected: PASS with `@floor`. About 60 s.
- `... bash ci/iris.sh teardown` (once): expected: removes only e1s2a's projects.

**Shared surfaces:**
- The System Default Settings rows of `OcuTalon.Production`: the new `Effort` rows for `TriageAgent` and `DiagnosisAgent`, and the item-`*` `AgentAllowList` row.
- The `ModelFamily` rows.
- `Reply`'s properties (`Test.Bridge.Contracts`), and the new message class `ToolInventory`.
- The Lane A oracle's stub flags, which Lane B's `test-production.sh` sweep reads.
- The runner's answer to foreign messages (Lane B's row 16).
- The Config Store entries' `api_key`, pointed and restored by the tests.
- Runner jobs, restarted by the tests.
- The mock scenario set (`context-probe.json`).
- The agent classes (`EFFORT`, Chat's `MaxIterations`), which the mock's constants test reads for `MOCKKEY` only.
- Tests updated for the new shape: `Test.Install.Production`, `Test.Bridge.Contracts`, `Test.Bridge.Api`, `Test.Agent.Models`, `Test.Agent.KeyScan` and `Test.Agent.Instructions`.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. The lead runs `shard lane-a` and `shard lane-b` forward, then both with `--reverse`.

**Mutations to demonstrate (Rule 19), one per AC; record each as `mutation: <change> -> <test went red>`:**

| AC | Change | Test that goes red |
| --- | --- | --- |
| AC1 | `SystemPrompt` dropped from the refusals | `Runner.TestRefusals`, `Runners.TestStartRefused` |
| AC1 | The build moved into `OnInit` | `Runners.TestStartsWithNoKey` |
| AC2 | Effort written for the `gpt-5` family | `SessionConfig` |
| AC2 | The open method passes no config | `Runner.TestOpenKeepsConfig` |
| AC3 | The `Effort` setting ignored | `Runners.TestRequestsUnderTheModelRules` |
| AC3 | The cache block omitted (re-derive per the amended AC3: the session config's cache block, and the probe's system marker; see the note on `BuildSessionConfig` under `## Auto Run Result`) | `Runners.TestRequestsUnderTheModelRules`, `SessionConfig` |
| AC3 | The adapter's `Model` ignored in favour of `MODEL` | `Models.TestModelChange` |
| AC4 | `Context.Begin` after `Chat` | `Runner.TestContext` |
| AC4 | `FinishReason` not copied | `Runner.TestFinishReason` |
| AC4 | A `.Chat(` call added to `Agent.Input` | `CodeRules.TestOnlyRunnersChat` |
| AC5 | `##class(%AI.ToolMgr).%New()` added to `WatchFixture` | `CodeRules.TestCallbackRule` |
| AC6 | `,%AI.Tools.SQL` added to Diagnosis's `TOOLSETS` | `Runners.TestToolInventory` |

**Measured in planning (`ocutalon-slot-a`, `OCUTALON`, `iris_server_info` build 154U; process-local, nothing kept):**
- **An unset key variable.** Both `SettingStore.Expand("@{env:<unset>}")` and `%AI.Provider.Create("anthropic", {"api_key":"@{env:<unset>}"})` throw `<%AICore>InternalError: Internal AI-Core error: @{env:<NAME>} has no value and no :-fallback was given`. With no key in the container, a runner can therefore not build its agent: hence decision 12, and a fact for Story 1.6's `no_key`.
- **Creating a session.** With a dummy provider, `OcuTalon.Agent.Triage.%Init()` succeeds, and `CreateSession` accepts both `{"max_tokens":8000,"extra_params":{"output_config":{"effort":"low"}},"cache":{...512}}` and `{"extra_params":{"max_completion_tokens":8000},"max_iterations":4,"cache":{...}}`.
- **Unknown session keys** fail with `<%AICore>JsonError ... unknown field`. The allowed keys are `max_iterations`, `cache`, `tool_catalog`, `temperature`, `max_tokens`, `top_p`, `presence_penalty`, `frequency_penalty`, `stop_sequences`, `response_format`, `extra_params`, `auto_compact_on_token_limit` and `timeout_ms`.
- **A fresh `%AI.ToolMgr`.** Both `%Discover()` and `GetToolStatuses()` give each tool `name`, `source` and `provider`, and the statuses also give `status`.
  - `OcuTalon.Tools.Watch`'s three tools have source `iris`, provider `OcuTalon.Tools.WatchFixture`, and `metadata.origin_class` of the same class.
  - `%AI.Tools.SQL`'s five tools and `%AI.Tools.FileSystem`'s two have source `iris`, their `%AI` class as provider, and empty metadata.
  - `rust:shell` and `rust:filesystem` add `bash`, `list_tasks`, `task_io`, `terminate_task`, `read_file`, `read_directory`, `read_lines`, `glob_files`, `grep_files`, `change_directory` and `get_working_directory`, with source `rust` and provider `builtin`.
  - `rust:web_search` fails to add without `BRAVE_SEARCH_API_KEY`.

**Measured in implementation (Task 0; throwaway of tag `e1s2a`, build 154, the CI mock; two runs, nothing kept):**
- **(a) The cache marker. THE STOP RULE OF TASK 0 (a) FIRED.** The logged requests of the three default scripts, every field as sent (messages left out):
  - **Triage** (system 1245 chars, no tools): `{"max_tokens":8000,"model":"claude-haiku-5-5","output_config":{"effort":"low"},"system":{"chars":1245,"cacheControl":null},"tools":[]}`. No cache marker anywhere.
  - **Diagnosis** (system 758 chars, three tools): `output_config.effort` `high`, `system.cacheControl` `null`, and `tools` `read_event_log` `null`, `read_failed_messages` `null`, `read_item_settings` `{"type":"ephemeral"}`. The marker is on the last tool only, in both of its requests.
  - **Chat** (system 901 chars, no tools): no `output_config`, `system.cacheControl` `null`, `tools` `[]`. No cache marker anywhere.
  - No request holds a top-level cache field: the top-level fields are `max_tokens`, `model`, `messages`, `system`, `tools` and, for Triage and Diagnosis, `output_config`.
  - The composed session config of every runner holds the exact cache block (`{"enabled":1,"cache_system_prompt":1,"cache_tool_definitions":1,"min_tokens_for_cache":512}`). With a system prompt of 3317 chars (about 800 tokens) through the same runner path, `system.cacheControl` is `{"type":"ephemeral"}` and so is the tool (one tool) of a probe agent, and with no tools the system is still marked. So the block reaches the provider, and AI Hub marks a block only when the prefix reaches `min_tokens_for_cache` (Triage's, Chat's and Diagnosis's system prompts are about 190 to 310 tokens). The three product prompts are too short to be marked.
  - Condition and amendment for the owner: "intent gap: AC3's 'its log shows ... the cache settings' is unmeasurable for Triage and Chat, because AI Hub marks no block under `min_tokens_for_cache` 512 (measured: Triage `system.cacheControl` null with no tools; Chat `system.cacheControl` null with no tools; Diagnosis marks its last tool only)". Recommended amendment: "... the cache settings, where the cached prefix reaches `min_tokens_for_cache`, and the cache block reaches the provider for every runner".
- **(b) What ChatAgent answers for `chat.json`.** The Reply has status OK, `Text` `The CI mock looked at the productions.` and `FinishReason` `end_turn`. The mock logged two requests, both 200, and no request offers a tool: Chat has no tool `list_productions`, AI Hub fed that back to the model and the second scripted reply came back as text.
- **(c) How an `OnInit` refusal shows.** `TempStopConfigItem(item, 1)` and `TempStopConfigItem(item, 0)` both return OK with no text. About 1 s later `NotRunning()` is `TriageAgent`, the item has no alive job, and `Ens.Job:Enumerate` shows its last job as `Mode` Background, `Status` `last was: terminated`, `State` Dead, with the refusal as its detail. The event log holds one row of type 2 (error), `ConfigName` `TriageAgent`: `Terminating Job <n> / 'TriageAgent' with Status = ERROR #5001: OcuTalon.Bridge.Adapter.Agent refuses to start: the setting SystemPrompt is set; ...` and, for the allow-list, `... refuses to start: the AgentClass 'OcuTalon.Agent.Triage' is not on the AgentAllowList setting`. The other two runners keep their jobs. A System Default Setting row for item `*` (`AgentAllowList`) is resolved by `GetAdapterSettingValue` for every runner and applied by the running item; with the row deleted or put back and a restart, the item runs again.
- **(d) `finish_reason` of a normal reply:** `end_turn`, for Triage, Diagnosis and Chat.
- **(e) The error of a runner request with no key.** The status code is `<%AICore>ProviderCreateFailed` and the text is `ERROR <%AICore>ProviderCreateFailed: Failed to create provider 'anthropic'    > ERROR <%AICore>InternalError: Internal AI-Core error: @{env:ANTHROPIC_API_KEY} has no value and no :-fallback was given`. The second request gets the same text, nothing reaches the mock, the item keeps its job, and a `ToolInventory` request gets the same error. The event log holds the same text as an error row of the item.
- **Other facts.** After the bridge installer, `ModelFamily` holds `anthropic|claude-|max_tokens|extra_params.output_config.effort`, `default||max_tokens|` and `gpt-5|gpt-5|extra_params.max_completion_tokens|`. After the Production step, the `Effort` rows are `low` (TriageAgent) and `high` (DiagnosisAgent) with none for ChatAgent, and the item-`*` `AgentAllowList` row is `OcuTalon.Agent.Triage,OcuTalon.Agent.Diagnosis,OcuTalon.Agent.Chat`. The live `ToolInventory` answers are `{"tools":[]}` for Triage and Chat, and for Diagnosis the three tools `read_event_log`, `read_failed_messages` and `read_item_settings`, each with source `iris`, provider `OcuTalon.Tools.WatchFixture`, status `available` and reason empty.

**Run in the re-dispatch (cycle iteration 2; throwaways of tag `e1s2a`, one stack at a time, build 154; the dev slot only for compiles):**
- **Task 0 (a), resolved.** The tests follow the amended AC3. The measured facts above stand: Triage and Chat have no cache marker on the system block or a tool, Diagnosis has none on its system block and the marker on its last tool only (both of its requests), and the probe agent's 3,200-character system block through the runner path is marked (`Runner.TestCacheOverThreshold`). Every runner's composed config holds the exact cache block (`SessionConfig.TestAgents`).
- **The cache block omitted, measured.** Without the block AI Hub sets `cache` to `true` from the agent's `CachingEnabled`. The live runners' requests do not change at the mock (`Runners` stays green), but the probe's system block loses its marker (see Design Notes 20).
- **Commands, all green:** `bash ci/checks.sh`; `ci/iris.sh build`; the ten classes one per call (`Bridge.SessionConfig`, `Bridge.Runner`, `Bridge.CodeRules`, `Bridge.Contracts`, `Bridge.Api`, `Agent.Runners`, `Agent.Models`, `Agent.KeyScan`, `Agent.Instructions`, `Install.Production`); `shard lane-a` forward and `--reverse` (the only SKIP is the existing `TestStepHelpers` one); `bash docker/tests/test-mock.sh` (94 tests); `shard lane-b`; `live production`, `install-start`, `install-upgrade`, `production-restart`, `audit`, `compose-start` and `demo-path` (`@floor` passed); `ci/iris.sh teardown` (each run removes its own project; 0 left).
- **Failures the first runs found, now fixed:** `CheckSettings` stripped only `*W` (a line feed counted as a value); `TestPoolIsTheCap` used an internal Ens method with a missing argument (it left a SQL cursor open, which broke the next restarts); the restart helper's allow-list case assumed the other runners keep their jobs; `TestOpenKeepsConfig` did not go red (mutation below), see Design Notes 17, 21 and 22.

**Mutations (Rule 19), each applied to a byte copy, run on a throwaway, restored from the copy (`cmp` identical) with the whole uncommitted tree hashing the same before and after:**
- mutation: `SystemPrompt` dropped from the adapter's `REFUSED` list -> `Test.Bridge.Runner.TestRefusals` red and `Test.Agent.Runners.TestStartRefused` red (TriageAgent with a SystemPrompt row keeps an alive job and logs no refusal). That run was made before the review pass.
- mutation: `SystemPrompt` swapped for `ProviderName` in `REFUSED` (the count stays nine) -> `Test.Bridge.Runner.TestRefusals` red ("exactly the nine settings of the start refusal are refused", which compares the list itself).
- mutation: `OnInit` also builds the agent, with the build's failure ignored so that the stack still starts (`Do ..BuildAgent()` after `CheckSettings`) -> `Test.Bridge.Runner.TestRefusals` red ("has built no agent", three assertions). The plain form (`OnInit` returns the build's status) leaves the stack not ready ("application not healthy after 9m0s": with no key the Production step cannot start the runners), so `Runners.TestStartsWithNoKey` has no stack to run on. The companion mutation `BuildAgent` returns OK after a failed build -> `Runners.TestStartsWithNoKey` red (the error no longer names `@{env:ANTHROPIC_API_KEY}`, six assertions).
- mutation: effort written for the `gpt-5` family (the installer's `gpt-5` row given the effort key) -> `Test.Bridge.SessionConfig` red (`TestFamilies` and `TestInstallerRows`).
- mutation: `OpenSession` passes no config to AI Hub's `OpenSession` -> `Test.Bridge.Runner.TestOpenKeepsConfig` red (no cap of 8000, no effort low), run again after the review pass added its premise check that the saved session is attached to no agent when it is opened. The test was first green under this mutation and was rewritten (Design Notes 22).
- mutation: the `Effort` setting ignored (an empty effort passed to the composer) -> `Test.Agent.Runners.TestRequestsUnderTheModelRules` red (Triage `low`, Diagnosis `high` in both requests).
- mutation: the cache block omitted from the composer -> `Test.Bridge.SessionConfig` red (`TestFamilies`, `TestAgents`, `TestNoSampling`) and `Test.Bridge.Runner.TestCacheOverThreshold` red (the exact block, and the probe's system marker); `Test.Agent.Runners` stays green, because the live prefixes behave the same under AI Hub's default (measured above).
- mutation: the adapter's `Model` replaced by the agent's `MODEL` after the build -> `Test.Agent.Models.TestModelChange` red (both requests name `claude-haiku-5-5`, not `claude-sonnet-5-5`).
- mutation: `Context.Begin` moved after `Chat` -> `Test.Bridge.Runner.TestContext` red (no host data, no taint on the Reply).
- mutation: `FinishReason` not copied onto the Reply -> `Test.Bridge.Runner.TestFinishReason` red (normal, refusal and max_tokens), `TestBuildRetried` red too.
- mutation: a `.Chat(` call added to `Agent.Input` -> `Test.Bridge.CodeRules.TestOnlyRunnersChat` red.
- mutation: `##class(%AI.ToolMgr).%New()` added to `WatchFixture` -> `Test.Bridge.CodeRules.TestCallbackRule` red.
- mutation: `,%AI.Tools.SQL` added to Diagnosis's `TOOLSETS` -> `Test.Agent.Runners.TestToolInventory` red (five SQL tools listed, none of them OcuTalon's).
- mutation: the call of `ClearSampling` removed from `BuildAgent` -> `Test.Bridge.Runner.TestContext` red (the adapter leaves the probe agent's Temperature 0.7: the new assertion that it is cleared fails, and the mock answers 400 "sampling parameters are not allowed") and `TestCacheOverThreshold` red for the same 400. `SessionConfig.TestNoSampling` calls `ClearSampling` itself, so it does not pin the call.
- mutation: the `Set sc = ...HandleError(...)` line removed from the `Catch` of `Answer` -> `Test.Bridge.Runner.TestChatErrorIsStatus` red (a provider failure no longer gives an error status).
- mutation: the white-space test of `Answer`'s Input check removed (back to `Input = ""`) -> `Test.Bridge.Runner.TestUnbuiltKinds` red (an Input of white space is sent to the mock).

**Review pass (2026-10-21; throwaways of tag `e1s2a`):** after the patches, `shard lane-a` passed (19 classes, the only SKIP the existing `TestStepHelpers` one). The `(once)` lines then ran on the final tree, each green: `bash docker/tests/test-mock.sh` (94 tests), `shard lane-b` (24 classes, `Test.Data.Tables`, `Test.Msg.Contracts`, `Test.Contract.Ac` and `Test.Contract.Mock` among them), `live production` (row 16, the sweep and "a runner that resolves no model"), `live install-start`, `live install-upgrade`, `live production-restart`, `live audit`, `live compose-start`, `live demo-path` (`@floor` passed), and, beyond the list, `live storage-roundtrip` (the committed Storage blocks of `Reply` and `ToolInventory` equal the compiler's, AD-5). `bash ci/checks.sh` passed. Every mutation of the review pass was applied to a byte copy, restored from it (`cmp` identical), and the tree's fingerprint was the same before and after.

## Clarification Record

**For the veto window (not blocking; recommended as planned):**
- **Decision 7.** The new stored property `Reply.FinishReason`, a schema append on a Lane A message class.
- **Decision 11.** The new message class `OcuTalon.Bridge.Msg.ToolInventory`, a schema addition.
- **Decision 12.** How the tests supply a credential: the runner entries' `api_key` is pointed at the non-secret CI variable `OCUTALON_MOCK_KEY_HEADER` through `Merge` during a test, and restored after.

**Ruled at spec validation (Epic 1 runner, 2026-10-21, `category=veto`, all kept as planned):** decisions 7 and 11 (inbox U-5; additive schema, only the one `Extra` field AD-8 classifies is stored, and Lane B's `Ac.cls` checks only that named properties exist) and decision 12 (inbox U-6; the product path, no literal key, throwaways only, no Lane B file). The owner may reverse either through the inbox.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The three agent runners are built. The first pass's measured facts (cache markers, `finish_reason`, the no-key error, how an `OnInit` refusal shows) stay under `## Verification`; Task 0 (a)'s stop rule was resolved by the lead's AC3 amendment and did not fire again. This pass continued from that pass's uncommitted implementation and corrected it:
- `Adapter.Agent` strips line breaks as white space in its start refusals.
- `Runners.AssertRequests` follows the amended AC3: no marker on any system block, the marker on Diagnosis's last tool only, none for Triage and Chat.
- The "Cache over the threshold" row is covered by `Runner.TestCacheOverThreshold` with the new `ProbeLongAgent`.
- `Runner.TestOpenKeepsConfig` was rewritten so that it goes red when the open passes no config.
- `Runners.TestPoolIsTheCap` and `Runners.TestStartRefused` were corrected.
- The `Decided in-stage` items 15 to 25 record the code-level choices.

**Files changed (26 source paths, in the tree and committed with this spec).**
- Bridge: `Adapter/Agent.cls` (settings, refusals, deferred build, one composing method, sessions, `Answer`, `Inventory`), `Operation/AgentRunner.cls` (stub removed; answers `Request` and `ToolInventory`, anything else 5003), `Msg/Reply.cls` (`FinishReason`), `Msg/ToolInventory.cls` (new request), `Installer.cls` (seeds the three model families).
- Product: `Agent/Triage.cls` and `Agent/Diagnosis.cls` (`EFFORT`), `Agent/Chat.cls` (`MaxIterations` 4), `Install/Step/Production.cls` (`SeedEfforts`, `SeedAllowList`).
- Mock: `ci/mock/scenarios/A/context-probe.json` (the probe scenario).
- New tests and fixtures: `Test/Bridge/SessionConfig`, `Runner`, `CodeRules`, `Source`, `ProbeAgent`, `ProbeLongAgent`, `ProbeTool`, `ProbeTools`, and `Test/Agent/RunnerFixture`, `Runners`.
- Changed tests: `Test/Bridge/Contracts`, `Test/Bridge/Api`, `Test/Agent/Models`, `Test/Agent/KeyScan`, `Test/Agent/Instructions`, `Test/Install/Production`.

**Review (four layers, 43 findings: high 0, medium 4, low 28, false 11).**
- Patches applied (10 entries, 2 medium and 8 low):
  - medium: a test for `Answer`'s failure path (`TestChatErrorIsStatus`); the other-runner checks of `TestStartRefused` made self-contained.
  - low: `TestToolInventory` reads `reason`; the Chat-family scan asserts every class has source; `TestRefusals` compares the refused list itself; the build-in-`OnInit` mutation shown red at test level; `TestOpenKeepsConfig` asserts its premise; `RunnerFixture.Restart` returns an error when the wait ends unfinished; `TestContext` pins the `ClearSampling` call; white-space Input refused.
  - Also two history-narrating test headers reworded (Rule 14).
- Deferred (1, in the frontmatter `deferred:` list): nothing sets `Reply.ToolsRun`, which Story 1.7 and the evaluation stories read (medium).
- Rejected with their recorded reasons (see the Review Triage Log): the spec-bound seed shape of `SeedAllowList` (BH1, EC9), unvalidated `Effort` (BH2, EC2) and `Provenance` (BH3), the preconditions of `NewSession`/`OpenSession` (BH6), the limits of the `Job` and tool-code scans (BH7, BH8, EC11), test-helper hygiene (BH10), model-family and key-rotation edge cases (EC3, EC4, EC5, EC7), Chat's unasserted answer (VG3, spec-bound), sub-behaviour mutation lines (VG7), the threshold-bound cache assertions (VG11), mock-window and stream-branch remarks (VG12, VG13); three claims were false (EC1 measured, EC8, EC10) and the eight intent-alignment divergences are descriptive.
- Follow-up review recommended: true. Two medium entries were patched. The unverified risk: the live `Runners` tests (`TestStartRefused`, the key pointing) now wait 20 to 30 seconds for the runners' jobs and fail when the wait ends, and they were measured only on the developer machine (ARM, one job at a time); on the x64 CI runner, about three times slower (inference), they could time out.

**Verification.**
- Static: `bash ci/checks.sh`.
- Lane A: `shard lane-a` passed (19 classes, the only SKIP the existing `TestStepHelpers` one) after the patches; `Test.Bridge.Runner` also ran alone, and in each of three mutated runs (six mutations) the named tests went red (Verification, mutation lines).
- The `(once)` lines, on the final tree: `docker/tests/test-mock.sh` (94 tests), `shard lane-b` (24 classes), `live production`, `install-start`, `install-upgrade`, `production-restart`, `audit`, `compose-start`, `demo-path` (`@floor` passed), and `live storage-roundtrip` beyond the list; then `ci/iris.sh teardown` for `e1s2a` (0 left).
- The reverse-order fresh-environment run of the shards is the lead's step; this pass's handoff reported `shard lane-a --reverse` green before the review patches.
- The matrix: all 17 rows are covered by a test that ran green in the shard: rows 1 to 4 by `Runners.TestRequestsUnderTheModelRules` and `Runner.TestCacheOverThreshold`; 5 by `Models.TestModelChange`; 6 to 8 by `SessionConfig.TestFamilies` and `Runner.TestUnbuiltKinds`; 9 and 10 by `Runner.TestRefusals` and `Runners.TestStartRefused`; 11 by `Runners.TestStartsWithNoKey`; 12 by `Runner.TestContext`; 13 by `Runner.TestFinishReason`; 14 by `Runner.TestOpenKeepsConfig`; 15 by `Runners.TestForeignMessage` and Lane B's row 16; 16 by `Runner.TestUnbuiltKinds`; 17 by `Runners.TestToolInventory`.

**Residual risks.**
- `SeedAllowList` writes its row once: a later story that adds a product runner or an agent class must add the class to an existing install's row (the settings page owns it afterwards), or that runner refuses to start naming the class.
- `Reply.ToolsRun` stays 0 until a later story sets it (the deferred item).
- The over-threshold cache marker is shown by a probe agent in process; no live runner has a prompt over the threshold, so the live mock log can only show the marker on Diagnosis's last tool.
- The `(once)` and shard runs were on the developer machine (ARM); CI on the x64 runner is the first run there.
