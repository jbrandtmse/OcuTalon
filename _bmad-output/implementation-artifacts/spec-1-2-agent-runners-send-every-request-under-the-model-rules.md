---
title: 'Story 1.2: Agent runners send every request under the model rules'
type: 'feature'
created: '2026-10-21'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-5, AD-6, AD-7, AD-8, AD-10, AD-19, AD-22 and AD-29)'
warnings: ['oversized']
deferred: []
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
| Triage request (CI mock) | `decide` Request to `TriageAgent`; the entry's key placeholder points at a CI variable (fixture) | The logged request has `model` `claude-haiku-5-5`, `maxTokens` 8000, `request.output_config.effort` `low`, the cache marker on `request.system.cacheControl` (the form Task 0 (a) records) and no `temperature`, `top_p` or `top_k`, with status 200 and no `rejected`. `Reply.Text` is `triage.json`'s text. | No error expected |
| Diagnosis request | `diagnose` Request to `DiagnosisAgent` | Effort `high`; the system marker and the last tool's `cacheControl`; two requests (the fixture tool runs), both accepted. `Reply.Text` is `diagnosis.json`'s final text. | No error expected |
| Chat request | `turn` Request (provenance `user`) to `ChatAgent` | No `output_config.effort`, `maxTokens` 8000, the system marker; every logged request accepted. AC3 asserts the log only: Chat's answer is recorded by Task 0 (b), not asserted, because `chat.json` calls a tool that Chat gets in a later story. | No error expected from the mock |
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

**Acceptance Criteria:**
- **AC1, the start.** Given the runner items with `OcuTalon.Bridge.Adapter.Agent`, when an item starts, then it refuses to start with any refused setting set, or with an `AgentClass` not on `AgentAllowList`, and the event log names why. With no key in the environment it starts and runs, because the agent is built on first use (`Test.Agent.Runners`, `Test.Bridge.Runner`).
- **AC2, the session config.** Given any request, when the runner creates or opens the AI session, then one method composes the config from the agent and the resolved model's `ModelFamily` row. It holds the cap, the effort, `max_iterations` (4 for Chat) and the cache block, never a sampling parameter, and the same composition applies when a session is opened (`Test.Bridge.SessionConfig`, `Test.Bridge.Runner.TestOpenKeepsConfig`).
- **AC3, the integration AC.** Given the CI mock, when each runner sends its default scenario's request, then the mock accepts every request and its log shows `claude-haiku-5-5`, 8000, the effort and the cache settings. After `DiagnosisAgent`'s `Model` changes to `claude-sonnet-5-5` and it restarts, its next request names that model. The consumer here is AI Hub's Anthropic provider path, read through the mock's log.
- **AC4, the request.** Given a request reaching a runner, when it calls `Chat`, then the context was set first (request fields, `ThreadSessionId`, `SuperSession`, the taint and `HostData`). `Response.Extra` is kept as `FinishReason`, and afterwards `HostData` and the taint are on the `Reply`. No product class but the runner calls `Chat`, and each runner's pool size is its concurrency cap.
- **AC5, the callback rule.** Given the tool, policy and renderer classes, when `Test.Bridge.CodeRules` runs, then it fails on any `%AI` reference beyond their base classes and on any Python use.
- **AC6, the live inventory.** Given every running runner, when `Test.Agent.Runners.TestToolInventory` inspects its live ToolManager, then no AI Hub shell, filesystem, SQL or web-search tool is registered, and the test fails on any tool that is not an OcuTalon iris tool with clean code.

## Spec Change Log

## Review Triage Log

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
| AC3 | The cache block omitted | `Runners.TestRequestsUnderTheModelRules` (per Task 0 (a)) |
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

## Clarification Record

**For the veto window (not blocking; recommended as planned):**
- **Decision 7.** The new stored property `Reply.FinishReason`, a schema append on a Lane A message class.
- **Decision 11.** The new message class `OcuTalon.Bridge.Msg.ToolInventory`, a schema addition.
- **Decision 12.** How the tests supply a credential: the runner entries' `api_key` is pointed at the non-secret CI variable `OCUTALON_MOCK_KEY_HEADER` through `Merge` during a test, and restored after.

**Ruled at spec validation (Epic 1 runner, 2026-10-21, `category=veto`, all kept as planned):** decisions 7 and 11 (inbox U-5; additive schema, only the one `Extra` field AD-8 classifies is stored, and Lane B's `Ac.cls` checks only that named properties exist) and decision 12 (inbox U-6; the product path, no literal key, throwaways only, no Lane B file). The owner may reverse either through the inbox.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

The plan stage halted after planning, as the dispatch asked. The spec passed the READY FOR DEVELOPMENT gate on its first check. The epic context `epic-1-context.md` was reused, and Story 1.1's spec (`done`) was loaded for continuity. Nothing was implemented, committed or pushed. The only runtime calls were process-local measurements on `ocutalon-slot-a` (recorded under `## Verification`).
