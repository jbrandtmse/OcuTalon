---
title: 'Story 1.1: Every agent runs on Claude Haiku 5.5 through the Config Store'
type: 'feature'
created: '2026-10-21'
status: 'done'
baseline_revision: '9808cd92ac6f427bbb800ab463641c26e361e31b'
baseline_commit: '9808cd92ac6f427bbb800ab463641c26e361e31b'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-7, AD-19, AD-22 and AD-23)'
warnings: ['oversized']
deferred:
  - summary: >-
      Merge accepts any @{env:NAME} placeholder, any base_url, any header and any secret:// reference, so the caller that takes fields from a user must validate them.
    evidence: |-
      Merge refuses only an api_key that is not one @{env:NAME} placeholder and any other @{ (AD-19, decision 10, veto U-2). A call such as {"api_key":"@{env:SOME_OTHER_VARIABLE}","base_url":"http://other.invalid/v1/"} passes, a secret:// string passes, and AI Hub's @{config:} lookup resolves both (%AI.Utils.ConfigStore.Lookup reads with resolveSecrets 1). Story 17.3's model-change API is the first caller that may pass user input.
    location: >-
      src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls:Merge
    severity: medium
  - summary: >-
      ci/checks.sh fails its boundaries block on _bmad-output/implementation-artifacts/cycle-log-epic-1.md:1, which holds a local path.
    evidence: |-
      The line is in the runner's bookkeeping commit 9808cd9 (state=/Users/.../.coordination/unattended), so it is outside this story's diff; test-boundaries.sh scans every tracked file for local paths, so the hosted checks job goes red on the next push until the log line is changed.
    location: >-
      _bmad-output/implementation-artifacts/cycle-log-epic-1.md:1
    severity: medium
---

<intent-contract>

## Intent

**Problem:** The three agents are stubs with only a model and a mock key, the `Provider` install step does nothing, the Config Store merge method returns "not implemented", and no runner has a `Model` or `ProviderConfig` setting. So no agent can reach Claude Haiku 5.5 from the key in `.env`, and the CI mock cannot pick an agent's default script (DW-39).

**Approach:**
- Give each agent static instructions and toolsets. Diagnosis gets a read-only fixture `OcuTalon.Tools.Watch`.
- The `Provider` step writes one `AI.LLM.OcuTalon<Agent>` entry per runner. Each entry holds the provider, the key placeholder and the endpoint overrides, and never a model or a key. After the entry, the step writes each runner's `ProviderConfig` setting as `@{config:OcuTalon<Agent>}`.
- The `Production` step seeds each runner's `Model` when it is absent.
- Implement the bridge merge method.
- Prove with tests that a key in the environment ends up stored nowhere.

## Boundaries & Constraints

**Always:**
- **The key.** The key is only ever the literal placeholder `@{env:ANTHROPIC_API_KEY}`, resolved inside AI Hub's provider. No OcuTalon code reads the key's value, logs it or writes it.
- **Entry names and their order.**
  - Entries are named `AI.LLM.OcuTalon<last part of the agent class name>`.
  - They keep the default `%Admin_ConfigStore` read and edit resources.
  - `RebuildRegistry()` runs first, on every run of the step.
  - An entry that exists is modified, never created again.
  - Each entry is written before its runner's `ProviderConfig` row.
- **Settings.** `Model` and `ProviderConfig` are System Default Settings rows of the form (`OcuTalon.Production`, `<item>`, `*`, `<setting>`). The production XData stays as it is (AD-5, AD-29).
- **The mock key header.** The step adds `x-ocutalon-mockkey`, carrying the agent class's `MOCKKEY`, only when `OCUTALON_MOCK_KEY_HEADER` is exactly the string `1` (owner value 11, DW-39).
- **The bridge boundary (AD-2).** `OcuTalon.Bridge.ConfigStore` names no other OcuTalon package on a code line.
- **Text in `src/`.** All of it is ASCII, and no INSTRUCTIONS block contains `{{`.
- **Test placement and hygiene.** Tests go under `OcuTalon.Test.Agent`, `.Bridge` and `.Install` (the lane-a shard). Each test restores every row, entry, environment variable and session it changes or creates.

**Never:**
- No `model` in any entry.
- No request setting `temperature`, `top_p` or `top_k`.
- No call to `%AI.Utils.Template`.
- No `GetDetails` call with `resolveSecrets` = 1.
- Merge never restarts an item.
- Runners keep `STUB`, and the adapter's `OnInit` stays a no-op (Story 1.2).
- The step writes neither the timeout values from `Timeouts.Derive` nor a retry block (Story 1.7).
- No edit to a contended Lane B path. That covers `docker/**`, `ci/**` except `ci/mock/scenarios/A/`, `OcuTalon.Core`, `OcuTalon.Msg` except `Msg/Catalog/Watch.cls`, and the Lane B test packages. The one exception is the orchestrator's granted fixture edit inside the "a runner that resolves no model" check of `docker/tests/test-production.sh` (the task "The Lane B fixture"); nothing else in that file or in `docker/**` changes.
- No new `ci/units.sh` or `module.xml` entry. Areas are discovered automatically.
- No commit and no push.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Judges' install | No override variables are set | The entry is exactly `{"model_provider":"anthropic","api_key":"@{env:ANTHROPIC_API_KEY}"}`. It has no `base_url` and no `http_config`. | No error expected |
| CI (DW-39) | `OCUTALON_MODEL_BASE_URL=http://mock:8080/v1/` and `OCUTALON_MOCK_KEY_HEADER=1` | The entry also has `base_url` and `http_config.custom_headers` = `{"x-ocutalon-mockkey":"<MOCKKEY>"}`: `triage`, `diagnosis` or `chat`, one per entry | No error expected |
| Base URL alone (DW-39) | Base URL set; the flag is unset, `0`, `true` or ` 1` | `base_url` only, with no custom header. Online-demo traffic never carries the header; the existing `test-compose-file.sh` keeps the flag in `ci/compose.ci.yml` only. | No error expected |
| Flag alone | The flag is `1` and no base URL is set | The header is added and there is no `base_url`. This follows owner value 11, which turns on the flag alone. | No error expected |
| CA file | `OCUTALON_EXTRA_CA_FILE` names an existing file | `http_config.tls` = `{"ca_certificates":["<path>"],"accept_invalid_certs":false,"accept_invalid_hostnames":false}` | A missing file makes the step fail naming the variable and the path. Nothing is written. |
| Bad base URL | The base URL is not `http(s)://...`, or does not end in `/v1/` | — | The step fails naming the variable. Nothing is written. |
| Re-run or stale entry | The entry exists and holds a `model`, an old `base_url`, an old header or a typed key | It is modified, not created. Its details become exactly the computed object, so stale fields are gone. | A `Create` would fail with "already exists" |
| Model seed | A runner has no `Model` from its item or from any default row | The row (`OcuTalon.Production`, item, `*`, `Model`) is written with the agent class's `MODEL` (`claude-haiku-5-5`) | An existing row, for example one set to sonnet, is kept as it is |
| No model anywhere | The agent class has no `MODEL` and there is no row | No row is written. `Start` fails naming the runner, and no ready marker is written. | The status names the runner |
| Merge | An existing entry, merged with `{"base_url":"x","http_config":{"custom_headers":{"a":"1"}}}` | Only the given fields change. Nested objects merge, other `http_config` keys stay, and a JSON `null` removes a field. | No error expected |
| Merge with a placeholder | `{"api_key":"@{env:OPENAI_API_KEY}"}` | Accepted, because it is the form Story 17.3 sends | No error expected |
| Merge refused | `api_key` is not exactly one `@{env:NAME}`; `@{` appears in any other string; the entry is missing; or `fields` is not an object | — | An error says why, and the entry stays unchanged |
| Key in environment | A fake key is in the process environment. The step re-runs, and then one chat goes to the mock through TriageAgent's `ProviderConfig`. | The mock logs `keyLength` = the fake key's length, the header, `selectedBy` = `mockkey`, `scenario` = `triage` and `model` = `claude-haiku-5-5`. The key is in no entry, session, setting row, item setting or event-log row. | No error expected |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Agent/{Triage,Diagnosis,Chat}.cls`: 11-line stubs. Keep `Parameter MOCKKEY = "<key>";` on one line, because `ci/mock/test/constants.test.mjs:46` parses that line.
- `irislib/%AI/Agent.cls`: the agent base class.
  - `:18 MODEL` and `:31 TOOLSETS` are class parameters (TOOLSETS is a comma list); `:42 XData INSTRUCTIONS` is markdown.
  - `:388-395`: `{{` in the instructions triggers `%AI.Utils.Template`.
  - `CreateSession`, `Chat` and `%Init` are used exactly as in `Test/Contract/Mock.cls:130-172`.
- Toolset references:
  - `irislib/%AI/ToolSet.cls` and `irislib/%AI/Tools/ShellTools.cls:27-39`: the `XData Definition` form.
  - `irislib/%AI/Tools/SQL.cls`: an `%AI.Tool` class.
  - `irislib/%AI/Policy/Authorization.cls:65`: the `<Requirement Name="ReadOnly" Value="1"/>` metadata. The S4 spike's `<Tool Name Class Method>` form compiled and ran.
  - `irislib/%AI/ToolMgr.cls:441 RegisterToolSet` and `:460 %Discover`.
- `irislib/%SYS/ConfigStore/Configuration.cls`: the Config Store entry methods.
  - `Create :148` (fails if the entry exists), `Exists :245`, and `Modify :284`, which replaces the details whole.
  - `GetDetails(fqn,.d,0,0) :413`. Never pass `resolveSecrets` = 1.
  - `Query List :1285`.
  - Every change is written to the audit log with the details (`:1569`), so a literal key would leak there too.
- Descriptor references:
  - `irislib/%SYS/ConfigStore/DescriptorManager.cls:180 RebuildRegistry()`. Without it, `Create` fails on a fresh instance with #26414 (S5).
  - `irislib/%AI/ConfigStore/LLMDescriptor.cls`: `:22` requires `model_provider`, `:17` accepts unknown fields, and `:95` requires `api_key` for anthropic.
- Expansion:
  - `irislib/%AI/Utils/SettingStore.cls:73 Expand` makes a single pass, so the `@{env:}` inside an entry stays unresolved. `:57` is `RegisterDefaults`.
  - `irislib/%AI/Utils/ConfigStore.cls:44-52`: `@{config:X}` becomes `AI.LLM.X` and is read with `checkValid` = 0.
- `irislib/EnsLib/AI/Agent/OutboundAdapter.cls`: `:53 ProviderConfig` (ExpandableJSON), `:61 Model`, and `:243-297 setupProviderFromSettings`. That last method is the read path the key-scan test reproduces: expand the setting, `%FromJSON`, then `%AI.Provider.Create(model_provider, config)`.
- Production settings:
  - `irislib/Ens/Director.cls:1750 GetAdapterSettingValue` (item value, then the default rows) and `:2467 TempStopConfigItem(name,1)` then `(name,0)`. S5 used this to restart one item.
  - `irislib/Ens/Config/DefaultSettings.cls:200-213`: the match order; a `*` class matches both lookups.
  - `irislib/Ensemble.inc:155 $$$ConfigSetting(item,"Adapter",name)`: the runtime value a job applies (`Ens/Host.cls:509`).
- `src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls`: the `Merge` stub. Its signature is pinned by `Test/Contract/Ac.cls:323`; keep it.
- `src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls:28-38 ResolveModel`: unchanged, and `STUB` stays.
- `src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls`: an empty stub. `Install/Registry.cls:10-13` runs Provider 9th, before Production (12th).
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls`: `Run :40`, `Start :48` (fails on unresolved runners at `:81-84`), `UnresolvedRunners :115-129` and `SetEval :137-153` (the one System Default Settings row writer today).
- `src/ocutalon/cls/OcuTalon/Production.cls`: the runners carry only `Adapter:AgentClass`. No edit.
- Text sources:
  - `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls:44-48 agent.noCommands`, rendered by `Msg/Catalog.cls:51 Render`.
  - `Bridge/Msg/DecisionPayload.cls` (`%JSONFIELDNAME` `outcome`, `reasons`, `confidence`) and `Bridge/Msg/Enum.cls OUTCOME`.
  - `Tools/Names.cls` (`READFAILEDMESSAGES`, `READEVENTLOG`, `READITEMSETTINGS`).
- `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls` (Lane B; call it, do not edit or copy it): `CheckBaseUrl :267`, `LogMark :365`, `LogSince :378`, and the log fields `keyLength`, `headerNames`, `selectedBy`, `scenario` and `model`.
- The CI mock:
  - `ci/mock/scenarios/A/triage.json`: the default script picked by `x-ocutalon-mockkey`.
  - `ci/mock/mock.mjs:396-399`: `x-api-key`, and 401 without one.
  - `ci/compose.ci.yml:14-19`: the base URL, the flag `"1"`, and no key.
- `ci/units.sh:12-21`: lane-a covers the areas Agent, Bridge and Install. `ci/iris.sh:113-130` discovers the classes. No edit.
- Tests that assert the old shape:
  - `Test/Bridge/Api.cls:45-48 TestConfigStore` expects "not implemented".
  - `Test/Agent/Constants.cls:13-31` holds the per-agent `{{` check.
  - `Test/Install/Production.cls:174-202 TestRunnerModels`.
  - `docker/tests/test-production.sh:274-295` (Lane B): the "a runner that resolves no model" check; see the task "The Lane B fixture".
- The checks:
  - `docker/tests/lib-live.sh:575-581` expects `STEP Provider OK`.
  - `test-class-rules.sh`: bridge-refs and the `%AI` allow-list.
  - `test-boundaries.sh:39-40 key_like`: the fake key must not match `sk-ant-…` and similar patterns.
  - The unchecked-prepare rule: always use the one-argument `%Prepare`.

## Tasks & Acceptance

**Execution:**

**Task 0: measure on `ocutalon-slot-a`.**
- First check `iris_server_info` (build 154, port 1990). Pass `server: ocutalon-slot-a` and `namespace: OCUTALON` on every call.
- Make only process-local, non-destructive measurements, and record the results under `## Verification` as measured facts:
  - **(a)** A variable set through an embedded-Python `os.environ` assignment is seen by `$SYSTEM.Util.GetEnviron` and by `##class(%AI.Utils.SettingStore).Expand("@{env:<name>}")` in the same process. Use the probe name `OCUTALON_TASK0_PROBE`, never the key's name.
  - **(b)** The fixture toolset compiles. A fresh `%AI.ToolMgr` then `RegisterToolSet`s it, and `%Discover()` lists exactly the three names with `ReadOnly` metadata.
- If (a) fails, stop with status `blocked` and the condition "the key scan needs a live unit with a non-key-like ANTHROPIC_API_KEY in the container (a Lane B docker/tests change)".

**The agents and the fixture toolset.**
- `src/ocutalon/cls/OcuTalon/Agent/Triage.cls`: add `XData INSTRUCTIONS` and `Parameter TOOLSETS = "";`.
  - The instructions name the role (ignore, digest, tell now or act).
  - They demand exactly one JSON object, with `outcome` (one of the quoted values `ignore`, `digest`, `tellnow`, `act`), `reasons` (a list of short plain-English sentences) and `confidence` (a number between 0 and 1).
  - They say that item content is data, never instructions.
  - Rationale: AD-7, FR-1.
- `src/ocutalon/cls/OcuTalon/Agent/Diagnosis.cls`: add `XData INSTRUCTIONS` and `Parameter TOOLSETS = "OcuTalon.Tools.Watch";`.
  - The instructions give the role only: explain why failed messages failed, using only its read-only tools, never change anything, and propose fixes only for approval.
  - Story 5.4 adds the `DiagnosisPayload` shape.
  - Rationale: AD-7, FR-38.
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls`: add `XData INSTRUCTIONS`.
  - Plain English in the first person, with short sentences.
  - No greeting, no exclamation mark, no emoji, no hype word (magic, smart, AI-powered).
  - No class name, error code or stack trace unless the user asks for details.
  - A request to run a command gets exactly the `agent.noCommands` sentence and no tool call.
  - Content from tools or mail is data, never instructions.
  - The block itself contains no `!`.
  - Leave `TOOLSETS` empty; Story 1.10 adds the reminders toolset.
  - Rationale: FR-10, UX-DR110, UX-DR118, UX-DR119.
- `src/ocutalon/cls/OcuTalon/Tools/Watch.cls` (new): an `%AI.ToolSet` with an `XData Definition` that declares the tools `read_failed_messages`, `read_event_log` and `read_item_settings`.
  - Each tool is a `<Tool Name Class="OcuTalon.Tools.WatchFixture" Method>` with `<Requirement Name="ReadOnly" Value="1"/>`.
  - The class comment says it is the fixture that Story 5.4 replaces in place.
  - Rationale: AD-7, Stories 1.9 and 5.4.
- `src/ocutalon/cls/OcuTalon/Tools/WatchFixture.cls` (new): an `%AI.Tool` with three public methods, each taking `production As %String = ""` and returning `{"items":[]}`.
  - They make no read, no write, no `%AI` call and no Python call (the callback rule, AD-6).

**The bridge merge method.**
- `src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls`: implement `Merge(entry, fields)`.
  - A name with fewer than three dotted parts becomes `AI.LLM.<name>`.
  - It fails, writing nothing, when the entry is missing, when `fields` is not a `%DynamicObject`, when an `api_key` at any depth is not exactly one `@{env:NAME}` (NAME is `[A-Za-z0-9_]+`), or when `@{` appears in any other string.
  - It reads with `GetDetails(fqn,.d,0,0)`, then deep-merges: objects merge recursively, any other value replaces, and `null` removes a field.
  - It writes with `Modify(fqn, merged)` and returns that status.
  - It restarts nothing.
  - Rationale: AD-19, AD-29; Story 17.3 is its first consumer.

**The Production step.**
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls`:
  - Extract `Runners(production, Output runners)`, which gives each runner item of class `RUNNERCLASS` with its `AgentClass` and its effective `Enabled`. `UnresolvedRunners` uses it.
  - Generalize `SetEval`'s row code into `WriteDefault(production, item, setting, value, description) As %Status`. `SetEval` calls it.
  - Add `SeedModels(production)`. For each runner whose `Ens.Director.GetAdapterSettingValue(production_"||"_item,"Model")` is empty and whose agent class has a non-empty `MODEL`, it writes the `Model` row with that value.
  - `Run()` calls `SeedModels(..#PRODUCTION)` after `SetEval` and before `Start`.
  - Rationale: AD-7, AD-19 (the Model setting is a seed value), AD-23.

**The Provider step.**
- `src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls`: implement `Run()` and the pure method `Details(agentClass, baseUrl, caFile, mockKeyFlag) As %DynamicObject`. The matrix rows define `Details`.
  - `Run()` calls `##class(%ConfigStore.DescriptorManager).RebuildRegistry()` first. It then validates the base URL and the CA file, and reads the runners through `Production.Runners`.
  - For each runner it:
    - writes the entry (`Modify` with the whole object if the entry `Exists`, else `Create("AI","LLM","",name,details,...)`);
    - checks that the entry `Exists`, failing and naming the entry if not;
    - writes `ProviderConfig` = `@{config:OcuTalon<Agent>}` through `WriteDefault`, with a description saying the step writes it at every start.
  - Rationale: AD-7, AD-19, DW-39.

**Tests.**
- `src/ocutalon/cls/OcuTalon/Test/Install/Provider.cls` (new):
  - `TestDetails`: every matrix row on the pure builder, including DW-39's base-URL-alone and flag-value rows, and that no output ever has `model` or anything but the literal placeholder.
  - `TestEntries`: the after-start entries equal `Details(...)` for this environment, and each runner's `ProviderConfig` row equals `@{config:OcuTalon<Agent>}`.
  - `TestRerun`: snapshot the Triage entry, then add stale fields (a `model` and an old `base_url`) directly with `%ConfigStore.Configuration.Modify`. `Run()` returns OK, where a `Create` would fail, and the details are exact again. Then restore.
  - `TestEntryBeforeSetting`: snapshot, delete the Triage entry and its row, `Run()`, and both are back; then restore.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`:
  - Move the real-production half of `TestRunnerModels` to `Test.Agent.Models` and keep the fixture half.
  - Add `TestSeedModels` on the fixture production. `ZzAgentModel` gets a row with `claude-haiku-5-5`; `ZzModelSet` and an existing row are left alone; `ZzNoModel` gets no row. The class's existing ZzProd cleanup removes the rows.
  - Add `WriteDefault` to `TestStepHelpers`, and update the header.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls` (new):
  - `TestTriage`: the INSTRUCTIONS name every `%JSONFIELDNAME` of the compiled `DecisionPayload` and every `OUTCOME` value quoted, and contain "one JSON object", "plain English" and "between 0 and 1".
  - `TestChat`: the block contains the exact sentence of the AC, which equals `Msg.Catalog.Render("agent.noCommands","","web",.sc)`. It contains the terms "first person", "greeting", "exclamation", "emoji", "hype", "class name", "error code", "stack trace" and "unless the user asks". It contains no `!`.
  - `TestDiagnosis`: the block is non-empty and says read-only.
  - `TestToolsets`: Triage's toolsets are `""` and Diagnosis's are `OcuTalon.Tools.Watch`. The ToolMgr discovers exactly the three `Tools.Names` values, each `ReadOnly` = 1, and executing each returns `{"items":[]}`.
  - `TestNoTemplates`: no compiled `OcuTalon.*` INSTRUCTIONS XData contains `{{`. No `OcuTalon.*` class's UDL text holds the needle `"%AI.Utils."_"Template"` on a code line; comment lines starting `//`, `///`, `;` or `#;` are skipped, as in `test-class-rules.sh`.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Constants.cls`: drop the per-agent `{{` assertion and its helper, now covered by `TestNoTemplates`, and update the header.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Models.cls` (new; throwaway only):
  - `TestRunnersResolve`: the moved half, plus each runner's `Model` row exists with `claude-haiku-5-5`, and `Production.UnresolvedRunners("OcuTalon.Production")` = "". This is the step's own check, as the AC asks.
  - `TestModelChange`: set DiagnosisAgent's `Model` row to `claude-sonnet-5-5` (one change) and restart that item with `TempStopConfigItem` 1 then 0. `ResolveModel` and `$$$ConfigSetting("DiagnosisAgent","Adapter","Model")` are then sonnet, and the item's job is alive. Then restore haiku, restart, and assert the restored values.
- `src/ocutalon/cls/OcuTalon/Test/Agent/KeyScan.cls` (new; throwaway only):
  - The guard is `Test.Contract.Mock.CheckBaseUrl` plus flag `1`; otherwise the test fails with the reason.
  - The fake key is `"ocutalon-keyscan-"_##class(OcuTalon.Bridge.Ids).NewRef()`. Set it through a Python class method and restore the previous value afterwards.
  - Re-run `Provider.Run()`.
  - Build the provider the adapter's way from TriageAgent's `ProviderConfig` setting. Run a `Triage` agent with `Model` = `ResolveModel`, `CreateSession({"max_tokens":8000})` and one `Chat` whose text carries a reference, then `%Save` the session.
  - Assert the mock log (via `LogMark` and `LogSince`) as in the matrix row.
  - The public `Find(value) As %List` names every store that holds the value:
    - each `AI.LLM` entry named `OcuTalon*`, from `List` plus `GetDetails(…,0,0)`;
    - each saved `%AI.Agent.Session`, opened and `Export()`ed (`ContextData` is compressed);
    - every `Ens.Config.DefaultSettings` row;
    - every item setting of `OcuTalon.Production`;
    - `Ens_Util.Log.Text`.
  - Assert `Find` on the fake key is empty. Delete the test's session.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ConfigStore.cls` (new):
  - The tests use their own entry `AI.LLM.OcuTalonZzMerge<n>`, created after `RebuildRegistry` and deleted at the end.
  - `TestMerge`, `TestMergeRefused` (the entry is unchanged after each refusal), `TestMergePlaceholder` and `TestMissingEntry`.
  - `TestExpansionSeesMerge`: `Expand("@{config:OcuTalonZzMerge<n>}")` shows the merged and untouched fields, with `api_key` still the literal placeholder.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls`: remove `TestConfigStore` and its header line, because the merge is no longer a stub.

**The Lane B fixture (orchestrator ruling of 2026-10-21; a footprint extension of this story).**
- `docker/tests/test-production.sh`, inside the check "a runner that resolves no model" (lines 274-295) only. Nothing else in the file changes.
  - Before `Start(15)`, delete the seeded TriageAgent `Model` default row: `Do ##class(Ens.Config.DefaultSettings).%DeleteId("OcuTalon.Production||TriageAgent||*||Model")`. You may add one CHK line for the delete (for example `CHK|row-deleted|1`, asserting the row no longer exists), and the check's expected-output block gains that line.
  - After the class is restored, re-seed the row before the healthy start: run the Production step (`##class(OcuTalon.Install.Step.Production).Run()`, which seeds then starts) in place of `Start(30)`, or restore the row and keep `Start(30)`. Either way `start-ok` still proves the healthy path.
  - Keep the meaning of the four existing CHK lines: `fixture`, `start-unresolved` (the start fails naming `TriageAgent`), `restored` and `start-ok`. The check must still prove that a runner resolving no model fails the start.
  - Rationale: AD-7 and AD-19 (the `Model` setting wins over the class parameter). The orchestrator's grant: integrate-forward conflicts on this file are a plain union.

**Acceptance Criteria:**
- Given the package compiles, when the agent classes are inspected, then Triage, Diagnosis and Chat extend `%AI.Agent` with a non-empty `XData INSTRUCTIONS`, `MODEL` = `claude-haiku-5-5` and their Epic 0 `MOCKKEY`, Triage has no toolset, and Diagnosis has only `OcuTalon.Tools.Watch`, whose three tools are read-only. A test in `OcuTalon.Test.Agent` fails on a `{{` in any INSTRUCTIONS block and on any OcuTalon reference to `%AI.Utils.Template`.
- Given the Triage and Chat instructions, when `Test.Agent.Instructions` reads them, then Triage asks for one `DecisionPayload`-shaped JSON object, and Chat states the voice rules and the exact catalog sentence for a request to run a command, with no tool call.
- Given a fresh start in CI, when the after-start log is read, then it shows `STEP Provider OK` before `STEP Production OK`, with `RebuildRegistry` run first. The three entries exist with no model, and each runner's `ProviderConfig` is `@{config:OcuTalon<Agent>}`.
- Given the runners `TriageAgent`, `DiagnosisAgent` and `ChatAgent`, when the Production step starts the production, then each `Model` row has been seeded with `claude-haiku-5-5` only where absent, every runner resolves it, and `Test.Agent.Models` runs the step's own unresolved-runner check.
- Given DiagnosisAgent's `Model` changed to `claude-sonnet-5-5`, when that item restarts, then it resolves sonnet and its job applies sonnet.
- Given a fake key in the environment, when a request goes from TriageAgent's `ProviderConfig` to the mock and the session is saved, then the mock saw a key of the fake key's length, and `KeyScan.Find` finds the key in no entry, saved session, setting or event-log row. This is the integration AC: the consumer is AI Hub's provider.
- Given an existing entry, when `Merge` runs, then only the given fields change, and a literal key or a non-key `@{` is refused. This is the integration AC: the consumer is AI Hub's `@{config:}` expansion.

### Review Findings

Code review, 2026-10-21. Tier full-opus, with four layers: blind-hunter, edge-case-hunter, verification-gap and acceptance-auditor. The layers reported 34 rows and the reviewer added 2. They group into 14 entries (high 0, medium 4, low 10), and 17 rows were rejected. Fix-risk and footprint are given with each entry.

- [x] [Review][Patch] The model tests in `Test.Install.Production` depend on method order. `TestSeedModels` leaves `ZzAgentModel`'s row at `claude-sonnet-5-5`, so `TestRunnerModels`' haiku assertion and `TestSeedModels`' "no Model row" precondition hold only because `TestRunnerModels` sorts first. Medium, Rule 19 hermeticity. Fix-risk low (cleanup lines in a test); in-story. [src/ocutalon/cls/OcuTalon/Test/Install/Production.cls:207]
- [x] [Review][Patch] `Test.Agent.Models.TestAppliedAtStart` pins the order "seed before start" only when it runs before `TestModelChange`, and only against the state the after-start left. It is to become self-contained: delete the three rows, call the step's `Run()`, then assert. Decision 24 then no longer applies. Medium, Rule 19. Fix-risk low (the live production check calls the same `Run()`); in-story. [src/ocutalon/cls/OcuTalon/Test/Agent/Models.cls:38]
- [x] [Review][Patch] Rule 2 copies. `Test.Install.ProviderEnv`'s `EntryJson`, `Row` and `Restore` copy `Test.Install.Provider`'s `EntryJson`, `Row`, `RestoreEntry` and `RestoreRow`, and that `RestoreRow` copies `Install.Step.Production.WriteDefault`. Medium. Fix-risk low (test helpers with the same behaviour); in-story. [src/ocutalon/cls/OcuTalon/Test/Install/ProviderEnv.cls:284]
- [x] [Review][Patch] The Provider step keeps whatever read and edit resources an existing entry has, though the entries keep the default `%Admin_ConfigStore` ones (Always). `TestEntries` checks them with a contains test. Low. Fix-risk low (two arguments on two calls); in-story. [src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls:130]
- [x] [Review][Patch] The Lane B line `CHK|row-deleted|1` prints 1 whether or not the start seeded the row. Low. Fix-risk low (one line inside the granted check); in-story (grant). [docker/tests/test-production.sh:292]
- [x] [Review][Patch] No test shows that the running runners apply their `ProviderConfig`. Low. Fix-risk low; in-story. [src/ocutalon/cls/OcuTalon/Test/Agent/Models.cls:44]
- [x] [Review][Patch] `TestApplyCaFile`'s precondition `before '= ""` cannot fail, because `State()` always starts with a line feed. Low. Fix-risk low; in-story. [src/ocutalon/cls/OcuTalon/Test/Install/Provider.cls:144]
- [x] [Review][Patch] `TestDetails`' `checked = 8` counts loop passes, so it cannot fail. Low. Fix-risk low; in-story. [src/ocutalon/cls/OcuTalon/Test/Install/Provider.cls:73]
- [x] [Review][Patch] `KeyScan`'s class comment says `Find` names every store that holds the value, but it scans the five stores AC6 names, not the audit log, the journal or the runtime settings. Low. The gap in the scan is theoretical while no writer can put a key into an entry. Fix-risk low (comment); in-story. [src/ocutalon/cls/OcuTalon/Test/Agent/KeyScan.cls:13]
- [x] [Review][Patch] `SeedModels`' comment says a runner whose class has no `MODEL` fails the start, but only an enabled one does. Low. Fix-risk low (comment); in-story. [src/ocutalon/cls/OcuTalon/Install/Step/Production.cls:159]
- [x] [Review][Patch] The Provider step's comments say a bad override writes nothing, but `RebuildRegistry` has already run by then; what holds is that no entry or row is written. Low. Fix-risk low (comment); in-story. [src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls:15]
- [x] [Review][Patch] `URLPATTERN`'s comment says nothing in a base URL can carry a credential, but a path segment can. Low. Fix-risk low (comment); in-story. [src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls:43]
- [x] [Review][Defer] `KeyScan.FindRequest` and `Has` copy `Test.Contract.Mock`'s private `Find` and `Has`, though the Code Map says to call Mock and not copy it. Medium, Rule 2. Fix-risk low; out-of-footprint (Lane B must make the two helpers public). [src/ocutalon/cls/OcuTalon/Test/Agent/KeyScan.cls:225] — deferred: DW-54, `escalated owner=burndown`, for the decision sheet.
- [x] [Review][Defer] `Merge` accepts a `model` field, which AD-7 says no entry holds. Low: the runtime ignores the field and the next start removes it. [src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls:33] — deferred: same root cause as DW-52 (Merge judges only `api_key` and `@{`, and its caller validates the rest); an `occurrence=` line was appended.

**Rejected (17):**
- BH `TestTriage` skips a `DecisionPayload` property that has no `%JSONFIELDNAME`. Low: unlikely, and the fix adds branches. The payload is a frozen Epic 0 contract that `Test.Contract.Ac` pins.
- BH: the Provider tests assume that item = `<Agent>Agent`. Low, theoretical: the production is fixed, and the spec names the runners.
- EH `Merge` accepts an entry of any area. Spec-bound: the spec's name rule and decision 17.
- EH: there is no lock between `GetDetails` and `Modify`. Theoretical: `SettingsOps` is the one run-time writer.
- EH: a `Merge` change reverts at the next start. Spec-bound (by-design): decision 4 and AD-19.
- EH: the seeded `Model` is not refreshed when an agent's `MODEL` changes in a later release. Spec-bound: under AD-19 a seed is written only when absent, and `SettingsOps` owns it after that.
- EH: when a later runner fails, the earlier entries are already rewritten. False: those entries hold this environment's correct values, the step fails, and no ready marker is written.
- EH: two agent classes that share their last name part share one entry. Theoretical: the production has three distinct classes.
- EH: `OCUTALON_EXTRA_CA_FILE` can name a directory. Low: unlikely, and the fix adds a guard; only CI and the demo deployment set the variable.
- EH: the `$ZHorolog` deadline in `Models.Restart` does not time out across midnight. Low, theoretical: it needs a wait that straddles midnight and an item that never runs, and the same pattern is the project's convention (`Production.Start`, the Demo step, Lane B tests).
- EH: the `List` query of `KeyScan.FindEntries` would drop an entry the user cannot read. Theoretical: the tests run with `%All`.
- EH: `TestNoTemplates` misses a reference built in a macro or a string. Low: unlikely, and the fix adds complexity; `test-class-rules.sh`' `%AI` allow-list also guards.
- EH: the real-production asserts were removed from `Test.Install.Production`. Spec-bound: the task moves them to `Test.Agent.Models`, which runs in the lane-a shard.
- VG: decision 15 still gives the old base-URL pattern. Rejected because the fix would edit the spec under review; decision 22 supersedes it.
- VG: AC1's template-call clause has only a mutation of the scanner. Rule 19 asks one mutation per AC, and AC1 has two against the code under test.
- AA: AD-19's "the registry marks every value" is built nowhere. False: the project marks each value's class in the writing step's class comment (Roles, Web, Users, Tasks, Public, `Bridge.Installer`), and this story's steps follow that.
- AA: the spec record contradicts itself on `boundaries`. Rejected because the fix would edit the spec; DW-53 fixed the log line, and QA's later results supersede the earlier ones.

**Rule checks.**
- Rule 3 is met. `Test.Agent.KeyScan` sends a real HTTP request through AI Hub's provider to the CI mock and asserts status 200, the headers and the key's length, and `live install-start` and `live production` run the real start.
- Rule 6: no AD mismatch was found. The resources finding is the spec's Always, not an AD Rule, and AD-19's structural and seed classes hold.
- Rule 1: the Integration ACs are AC6 and AC7.
- Rule 5: there is no NFR workaround.

**Results after the patches (tag `e1s1r`, one stack at a time, teardown left nothing).**
- `bash ci/checks.sh`: all 12 blocks passed.
- `ci/iris.sh build`: done.
- `shard lane-a`: 15 of 15 classes passed. The one SKIP is the existing `TestStepHelpers` skip (Story 0.6).
- `live production`: passed, with the check "a runner that resolves no model" printing `CHK|row-deleted|1|1`.
- Compiles on `ocutalon-slot-a` (build 154U) used `iris_doc_load` with flags `ck` only.
- The two mutations are recorded under `## Verification`.

## Spec Change Log

- 2026-10-21, lead (Epic 1 runner), after the plan's intent-gap HALT: applied the orchestrator's ruling. Added the task "The Lane B fixture", the narrowed exception on the contended-path "Never" line, the mutation row for `start-unresolved`, and the veto-window rulings on decisions 10 and 13 (U-2, U-3); status reset to `ready-for-dev` (no re-plan: the rest of the plan met the READY-FOR-DEVELOPMENT standard).
- 2026-10-21, implement pass: recorded Task 0's measured facts, the mutation lines and decisions 14 to 25 in the sections outside the intent contract. No change to the intent, the tasks or the acceptance criteria.

## Review Triage Log

### 2026-10-21 - Review pass
- verdicts: 58 findings - high 0, medium 8, low 48, false 2, maybe-false 0
- findings:
  - `[medium]` `[patch]` BH: `TestBadOverrides` asserts `before '= ""`, which `State()` makes always true - `State()` starts every line with a line feed and the entry name; patched to assert each entry and row is non-empty, and the mutation "checks no longer stop Apply" went red on the 'writes nothing' lines.
  - `[low]` `[patch]` BH: `TestToolsets` counts names without tallying each, and Chat's empty toolset is unasserted - patched with a per-name tally and a Chat assertion; mutation Chat TOOLSETS set went red.
  - `[low]` `[patch]` BH: `TestDiagnosis` pins only 'read-only' - patched with 'Never change anything', 'must approve' and 'data, never instructions'; mutation (sentence reworded) went red.
  - `[medium]` `[defer]` BH: `Merge` judges only the field named `api_key` and `@{`, so a placeholder can name any variable, `base_url` is unchecked and a literal credential in a header passes - the rule is AD-19's and decision 10's (veto U-2); the exposure exists only when a caller passes user input, so the validation is Story 17.3's (deferred item, shared with the `secret://` finding); the overclaiming class comment was replaced.
  - `[low]` `[reject]` BH: `Merge` is not limited to AI.LLM names - the spec fixes the rule (fewer than three dotted parts become AI.LLM.<name>) and lists the refusals; the caller is trusted bridge code, and an area check would add a guard the spec does not ask for.
  - `[low]` `[patch]` BH: the base-URL pattern accepts a user name, a query and a fragment, and the error echoes the value - patched (pattern, error text, tests); mutation went red.
  - `[low]` `[reject]` BH: `WriteRunner`'s skip-or-fail branches are untested, and two runners with one last class-name part would share an entry - the branches are decision 16, not an AC, and a test needs a public `WriteRunner` or a production argument; the production has three distinct classes and the name rule is the spec's (wontfix-theoretical).
  - `[low]` `[reject]` BH: `SeedModels` has no test for a disabled runner with a MODEL or a default row of another specificity - the matrix row is covered by `TestSeedModels` (item setting, `*` row, kept row); `getModifiedSettingValue` resolves rows by the item's class; a runner without a row still resolves through its class MODEL.
  - `[low]` `[reject]` BH: the spec record contradicts itself (status, Auto Run Result, red `boundaries`, the SKIP) - Auto Run Result is rewritten at finalize; the `boundaries` failure is the HEAD commit's cycle log, untouched by this diff; the SKIP is Story 0.6's, recorded under Results.
  - `[false]` `[reject]` BH: `Restart` can return before the restart took effect - `TempStopConfigItem` runs `UpdateProduction` (pDoUpdate 1, `Ens/Director.cls` TempStopConfigItem) with the production-update timeout, so it is synchronous; a missed deadline fails the next `NotRunning` assertion; green in every run.
  - `[medium]` `[defer]` EH: a merged string starting `secret://` passes the `@{` scan and AI Hub's `@{config:}` lookup resolves it (`%AI.Utils.ConfigStore.Lookup` reads with resolveSecrets 1) - same root cause as the Merge finding above: AD-19 has MCP entries hold `secret://` through the same method, so the refusal belongs to the Story 17.3 API for LLM entries.
  - `[low]` `[reject]` EH: no area or type check on the entry name - duplicate of the Merge-scope finding above.
  - `[low]` `[reject]` EH: no lock between `GetDetails` and `Modify` - only the install step and the admin API write entries; concurrent writers are theoretical (wontfix-theoretical).
  - `[low]` `[reject]` EH: the Provider step rewrites an entry whole, so a Merge change reverts at the next start - spec-bound: decision 4 and AD-19's structural values; Story 17.3 must make `model_provider` and `api_key` seed values (by-design).
  - `[low]` `[reject]` EH: an error status from `GetAdapterSettingValue` is treated as absent in `SeedModels` - `Runners` lists the items of the opened production, and the lookup errors only for a missing item or production (wontfix-theoretical).
  - `[low]` `[patch]` EH: the URL pattern accepts user name, query and fragment, and the error echoes the value - same root cause as the base-URL finding above; patched.
  - `[low]` `[reject]` EH: the CA path is not checked for being absolute, non-empty or readable - the matrix row says 'names an existing file' and fails on a missing one; stricter guards go beyond the row.
  - `[low]` `[reject]` EH: two runners with one last class-name part share an entry - duplicate of the collision finding above (wontfix-theoretical).
  - `[low]` `[reject]` EH: an enabled runner with an unusable class found mid-loop leaves earlier entries rewritten - they hold their correct values, the step fails and writes no ready marker; harmless.
  - `[low]` `[reject]` EH: `KeyScan` list fetch errors end the scan without 'could not be read' - local tables; the controls show each store is read (wontfix-theoretical).
  - `[low]` `[reject]` EH: a class whose source cannot be read is skipped by the template scan - the scan asserts more than 50 sources were read; one unreadable compiled class is theoretical.
  - `[low]` `[patch]` EH: the template-call scanner is case-sensitive - patched with a case-blind compare and a test row; mutation went red.
  - `[medium]` `[defer]` EH (claim): only the field named `api_key` is guarded, so the class comment overclaimed - comment replaced with the exact contract (patched); the validation is the deferred Story 17.3 item.
  - `[low]` `[patch]` EH (claim): `##;` comment lines are not skipped as in `test-class-rules.sh` - patched with the case fix.
  - `[low]` `[patch]` EH (claim): the Lane B `start-ok` proves only `IsOK(Run())`, so decision 21 overclaimed - decision 21 reworded; the grant allows one added CHK line, not a second; the seed is pinned by `Test.Agent.Models`.
  - `[low]` `[patch]` EH (claim): the toolset tally lets a duplicate plus a missing name pass - duplicate of the tally finding above; patched.
  - `[medium]` `[patch]` VG: the CA-file override never goes through `Apply`/`Run` - added `TestApplyCaFile` (stored entry equals `Details` for the file, tls block, flags false, entries put back); mutation went red.
  - `[low]` `[reject]` VG: `WriteRunner`'s skip-or-fail branch is untested - duplicate of the branches finding above.
  - `[medium]` `[patch]` VG: the seed-before-start order is unpinned - `TestAppliedAtStart` added; the first attempt, inside `TestRunnersResolve`, stayed green under the swap because `TestModelChange` updates the production first, so it moved to a method that sorts first; mutation went red.
  - `[low]` `[patch]` VG: the Lane B `start-ok` does not prove the re-seed - duplicate of the decision-21 finding above; reworded.
  - `[low]` `[patch]` VG: `Merge`'s `resolveSecrets` 0 is unpinned - added `TestKeepsSecretReference` (an unresolvable `secret://` field survives a merge); mutation (resolveSecrets 1) went red.
  - `[low]` `[patch]` VG: Chat having no toolset is unasserted - duplicate of the tally finding above; patched.
  - `[low]` `[reject]` VG: seeding a disabled runner that has a MODEL is unpinned - the runner still resolves through its class MODEL; closing it needs another fixture runner.
  - `[low]` `[reject]` VG: `Find`'s unreadable-store path is never exercised - it needs a seam that fakes an unreadable store, which the spec does not ask for.
  - `[medium]` `[patch]` VG (Rule 19): the `before '= ""` assertion cannot fail - duplicate of the first finding above; patched.
  - `[low]` `[reject]` VG (Rule 19): `+$Get(none) = 0` can pass if `Runners` never sets the array - the preceding assertion proves the error; harmless.
  - `[low]` `[reject]` VG (Rule 19): AC1 lacks mutation lines for the template half, Triage's empty toolset, ReadOnly and non-empty instructions - Rule 19 asks one demonstrated mutation per AC, and AC1 has two.
  - `[low]` `[patch]` VG (Rule 19): AC3's `TestEntryBeforeSetting` line recorded its red in the start log, not in the test - closed in this pass: the mutation 'row first while the production runs' turned the test red, and the line is rewritten; `TestBadOverrides` has its line too.
  - `[low]` `[reject]` VG (Rule 19): AC5's 'job applies sonnet' clause has no line - the AC's line (`ResolveModel` ignores the setting) is recorded; the clause is asserted in the same test.
  - `[low]` `[reject]` VG (Rule 19): AC7's `TestExpansionSeesMerge`, `TestMergePlaceholder`, `TestMissingEntry` and the non-`api_key` refusals have no lines - one mutation per AC is recorded (`TestMerge`, `TestMergeRefused`).
  - `[low]` `[reject]` VG (Rule 19): `Test.Install.Provider` relies on the entries the start wrote - spec-bound: `TestEntries` is defined as the after-start entries; the class header says throwaway only (by-design).
  - `[low]` `[reject]` VG (Rule 19): `Test.Agent.Models` needs the seeded rows and restarts a live item - spec-bound, throwaway only (by-design).
  - `[low]` `[reject]` VG (Rule 19): `Test.Agent.KeyScan` needs the CI mock and rewrites the instance-wide entries - spec-bound; it fails with the reason where the mock is missing (by-design).
  - `[low]` `[reject]` VG (Rule 19): `TestDetails` calls `KeyScan.SetEnv` - Rule 2 prefers the one helper to a copy.
  - `[low]` `[patch]` VG (other): decision 21 says the Lane B `start-ok` proves the re-seed - duplicate of the decision-21 finding above; reworded.
  - `[low]` `[reject]` VG (other): the command expects 'no SKIP' and the shard prints one - the SKIP is Story 0.6's `TestStepHelpers` (Rule 21 notes in specs 0.10 and 0.12 record it); recorded under Results.
  - `[medium]` `[defer]` VG (other): `ci/checks.sh` `boundaries` is red on `cycle-log-epic-1.md:1` - the line is the lead's bookkeeping commit (a local path), outside this diff and outside this story's paths; deferred out-of-footprint so the lead fixes its log before CI runs the `checks` job.
  - `[false]` `[reject]` VG (other): the `SeedModels` comment says 'any specificity' but only the director's lookup is used - `GetItemSettingValue` passes the item's class to `getModifiedSettingValue`, which reads System Default Settings by that class and by `*`, so the claim holds.
  - `[low]` `[reject]` IA: entry shapes are asserted at `Details`, and the stored shapes only for the CI environment - `TestEntries` compares stored entries with `Details`; the CA shape is now stored by `TestApplyCaFile`; the judges' shape has no stack without the mock override.
  - `[low]` `[reject]` IA: the key comes from the test process, not `.env` through the container - spec-bound: Task 0 and decision 13; the runner's own use of the key is Story 1.2.
  - `[low]` `[reject]` IA: `KeyScan` sets `agent.Model` by hand - spec-bound: the task says `Model` = `ResolveModel`.
  - `[low]` `[reject]` IA: the no-sampling-parameters Never is enforced by the mock - the story builds no request of its own; the mock rejects the three fields.
  - `[low]` `[reject]` IA: Diagnosis and Chat keys are exercised as header values only - the matrix row sends one chat through Triage's `ProviderConfig`.
  - `[low]` `[reject]` IA: instructions and toolsets are read as class text and parameters - AD-7 makes them declarative; the tool manager is run on the parameter.
  - `[low]` `[patch]` IA: the entry-before-row order is observed in the start log, not in `TestEntryBeforeSetting` - closed by the mutation recorded under Verification (the test goes red with row-first while the production runs).
  - `[low]` `[reject]` IA: seeding decides through the director's resolver, and 'no ready marker' is unchecked - the Registry stops at its first failing step (its own test); the resolver is decision 8.
  - `[low]` `[reject]` IA: `Merge` is tested on throwaway entries only - spec-bound: the tests use their own entry; 'never restarts' holds by absence of a restart call.
  - `[low]` `[reject]` IA: the diff makes `Apply`, `CheckBaseUrl`, `CheckCaFile`, `EntryName`, `Runners`, `SeedModels`, `AgentModel`, `WriteDefault` and the `KeyScan` helpers public - decisions 14 and 20 record why.

## Design Notes

**Governing architecture decisions (Rule 6):**
- AD-2: the bridge boundary. `ConfigStore` names no product package.
- AD-5: the XData holds structure only; values are default rows.
- AD-6: the runner starts with no key; the callback rule for tool classes.
- AD-7: the declarative agents; the model is the runner's `Model`, defaulting to `MODEL`; the entry carries no model.
- AD-19: entries, the placeholder, the overrides, the order, the merge method, and structural versus seed values.
- AD-22: the mock picks a script by `MOCKKEY`; tests live under `OcuTalon.Test.<Area>`.
- AD-23: the step order; a failed step writes no ready marker.
- AD-29: the merge method is a cross-lane API; the lane regions; the footprint.
- AD-33: one owner per class.

**Decided in-stage:**
1. `TOOLSETS` and `MODEL` are class parameters, because that is how `%AI.Agent` declares them; only INSTRUCTIONS is an XData block.
2. "The provider" means the descriptor's required field `model_provider`.
3. `ProviderConfig` and `Model` are default rows, not XData. A row is written after its entry, and the `*` class matches both the director's lookup and the job's.
4. Every field the step writes is structural in release 1 and is rewritten whole at every start. A stale model, URL, header or typed key therefore disappears. Story 17.3, the first story that changes a provider at run time, must make `model_provider` and `api_key` seed values here, or the next start reverts its change.
5. `base_url` and `http_config` are omitted when no override applies, so AI Hub's defaults reach api.anthropic.com. Story 1.7 then always writes `http_config`.
6. The header is added whenever the flag is exactly `1`, whatever the base URL. That is owner value 11's sole condition.
7. A malformed base URL, or a CA file that is missing, fails the start naming the variable, rather than failing every request later.
8. The seed value is the agent's `MODEL` parameter, so there is one source of truth. "Absent" means no item value and no default row of any specificity.
9. The runners come from the production definition, and each entry name is `OcuTalon` plus the last part of the agent class name.
10. `Merge` accepts `api_key` only as one `@{env:NAME}` placeholder (Story 17.3 sends one) and refuses `@{` anywhere else, matching AD-19's rule for admin values. It never resolves secrets.
11. Diagnosis's instructions give only the role in this story; its payload shape comes with Story 5.4, which has not built `DiagnosisPayload` yet.
12. The fixture tool methods live in the companion `%AI.Tool` class `WatchFixture`, the layout the S4 spike proved.
13. The key scan sets a fake key that does not look like a key, through embedded Python, in the test process only. No callback runs there, and Task 0 measures that it works.
14. `Provider.Run()` reads the three environment variables and calls `Provider.Apply(baseUrl, caFile, mockKeyFlag)`, which does the work, so that a bad base URL and a missing CA file are tested without changing the process environment. `CheckBaseUrl`, `CheckCaFile` and `EntryName` are public for the same reason.
15. A base URL is valid when it matches `^(?i:https?)://[^/\s]+/([^\s]*/)?v1/\z`: the scheme in any case, a host, any path without white space, and the last segment `/v1/`. An empty value is no override.
16. The Provider step writes an entry and a row for every runner whose AgentClass is a compiled `%AI.Agent` subclass, enabled or not. A runner with no usable class is skipped when disabled and fails the step by name when enabled. `SeedModels` seeds every runner whose class has a MODEL, enabled or not.
17. `Merge` also refuses `@{` in a field name and in an array element, refuses an `api_key` that is null, not a string or not exactly one placeholder, replaces arrays whole, adds a nested object that the entry lacks (a null inside it removes nothing), and names the path of the refused field and never its value. A short name and its full name `AI.LLM.<name>` name the same entry; an empty name names no entry.
18. `Create` gives each entry a description that says the step writes it at every start; `Modify` leaves the description as it is.
19. `OcuTalon.Tools.Watch` declares `DependsOn = OcuTalon.Tools.WatchFixture`, because the toolset's generator reads the methods that its tools name when the module compiles from scratch.
20. `Test.Agent.KeyScan.SetEnv`, `UnsetEnv` and `HasEnv` are public, and `Test.Install.Provider.TestDetails` calls them to show that a key in the environment changes nothing in the details. `KeyScan.Find` lists a store that cannot be read as "could not be read", so that an unreadable store never counts as clean, and the test shows that Find sees an entry, a session, a setting row, an item setting and an event-log row by searching for values that they hold.
21. Triage declares `Parameter TOOLSETS = ""`; Chat declares none and inherits the empty one, as the task says. The Lane B fixture runs the Production step's `Run()` for the healthy start; that check proves the healthy path (`start-ok`) and not the seeding, which `Test.Agent.Models` pins (`TestAppliedAtStart`, `TestRunnersResolve`).
22. A base URL is also refused when it holds a user name, a query or a fragment (`@`, `?`, `#`), and the error names the variable and never holds the value, so a URL that carries a credential is neither stored in an entry nor written to the install log.
23. `Merge` guards only the field named `api_key` and the `@{` marker. It does not judge which variable a placeholder names, `base_url`, headers, `secret://` references or a literal credential in another field, because AD-19 lets the same method edit entries that hold `secret://` references legitimately. The class comment says so, and validating values that come from a user is Story 17.3's (deferred item).
24. `Test.Agent.Models.TestAppliedAtStart` sorts before `TestModelChange` on purpose: that test updates the production and refreshes every item, which would hide a seed written after the start. The test passes in either order and pins the order only when it runs first.
25. `Test.Bridge.ConfigStore.TestKeepsSecretReference` pins the Never "no `GetDetails` with `resolveSecrets` = 1" at `Merge`: a resolving read of an unresolvable `secret://` reference fails.

**Integration ACs (Rule 1):**
- The key-scan test: AI Hub's provider reads the entry and the `ProviderConfig` setting, and the mock records the header, the base URL and the resolved key's length.
- The Production step's check reads the seeded `Model` rows.
- `@{config:}` expansion reads a merged entry.

**Consumed-by:**
- Story 1.2: the runner builds the agent from `ProviderConfig` and `Model`. It reuses `KeyScan.Find` for runner-saved sessions.
- Story 1.6: `Keys.Status` reads the placeholder the entries name.
- Story 1.7: adds the timeout and the full retry block to `Details`, keeping the rest.
- Story 1.9: Diagnosis offers the fixture's tools.
- Story 1.10: Chat's toolset.
- Story 5.4: replaces `Tools.Watch`, `WatchFixture` and the Diagnosis instructions in place.
- Story 17.3: the model-change API merges through `Merge`; see decision 4.
- Lane B Story 18.3: `SettingsOps` calls Story 17.3's API and restarts the runners.

**Consumes:**
- Epic 0: `AgentRunner.ResolveModel`, the Production step, the registry order, `Test.Contract.Mock`'s public helpers, `ci/mock/scenarios/A/triage.json`, the CI override's variables, `Msg.Catalog.Render` with `agent.noCommands`, `DecisionPayload`, `Enum.OUTCOME` and `Tools.Names`.

**Extend, don't copy (Rule 2):**
- `WriteDefault` generalizes `SetEval`.
- `Runners` is extracted from `UnresolvedRunners`.
- The runner-resolve test is moved, not copied.
- The `{{` check moves into one scan.
- The mock log is read through `Test.Contract.Mock`'s helpers.
- Two copies are deliberate:
  - The header rule mirrors `Test.Contract.Mock.CustomHeaders`. Product code may not call a test class, and the rule is one condition long; Lane B may later delegate its helper to `Provider.Details`.
  - The "only `1`" flag rule repeats `Production.EvalEnabled`'s one line, because a shared helper would only rename a tested method.

**Ledger:** DW-39 is addressed by the Provider step task and the matrix rows CI, base URL alone and flag alone.

**Lane B piece (resolved by the orchestrator's ruling of 2026-10-21, `category=decide`):** the check "a runner that resolves no model" in `docker/tests/test-production.sh:274-295` goes red once `Model` is seeded, and no Lane A design keeps it green without breaking AD-7's rule that the setting wins over the class parameter. The orchestrator granted Lane A the fixture edit inside that check only, as a footprint extension of this story; no Lane B epic in flight plans that file, and an integrate-forward conflict on it is a plain union. See the task "The Lane B fixture" and `## Clarification Record`.

**Veto-window rulings (recorded by the runner at spec validation, kept as planned):**
- Decision 10, Merge's key rule: kept (inbox U-2). It tightens AD-19 (only a placeholder can reach `api_key`, never a literal key or a nested `@{`).
- Decision 13, the key scan's fake key: kept (inbox U-3). The value is non-key-like (`test-boundaries.sh`'s `key_like` does not match it), lives only in the test process's environment, and is restored afterwards.

## Verification

**Targets:**
- **The slot.** Only `ocutalon-slot-a`, through MCP `server: ocutalon-slot-a` and `namespace: OCUTALON`, after `iris_server_info` shows build 154. It is used for `iris_doc_load` compiles and Task 0 only, and no lane-a test class runs there.
- **Throwaways.** Everything else runs in throwaways through `ci/iris.sh`, as `OCUTALON_RUN_TAG=e1s1a OCUTALON_LOCK_OWNER='epic=1 stage=implement'` (QA uses `e1s1q`, review `e1s1r`), one stack at a time, and one call each with `timeout: 600000`.
- **Never** `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition` or `ocutalon-slot-b`. No push and no `gh workflow run`.

**Commands:**
- `bash ci/checks.sh` (loop): expected: every block PASS (class-rules bridge-refs, the `%AI` allow-list and unchecked-prepare; boundaries ASCII and keys; storage), in about 20 s.
- `OCUTALON_RUN_TAG=e1s1a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh build` (loop): expected: exit 0.
- `OCUTALON_RUN_TAG=e1s1a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh shard lane-a` (loop): expected: every `CLASS` line passed, including the five new classes, with no SKIP and exit 0, in about 61 s. Use `ci/iris.sh class <Class>` for one class while iterating.
- `OCUTALON_RUN_TAG=e1s1a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh teardown` (loop): expected: removes only e1s1a's projects.
- `bash docker/tests/test-mock.sh` (once): expected: the mock's node tests pass, still reading each agent's one-line `MOCKKEY`.
- `OCUTALON_RUN_TAG=e1s1a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh shard lane-b` (once): expected: all classes passed, `Test.Contract.Mock` included.
- `OCUTALON_RUN_TAG=e1s1a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh live install-start` (once): expected: PASS. `STEP Provider OK` on a fresh volume pins `RebuildRegistry` first. About 151 s.
- `OCUTALON_RUN_TAG=e1s1a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh live install-upgrade` (once): expected: PASS. The second start modifies the entries. About 164 s.
- `OCUTALON_RUN_TAG=e1s1a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh live compose-start` (once): expected: PASS (about 80 s).
- `OCUTALON_RUN_TAG=e1s1a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh live production` (once): expected: PASS, including the "a runner that resolves no model" check with the task "The Lane B fixture" applied. About 83 s.
- `OCUTALON_RUN_TAG=e1s1a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh live production-restart` (once): expected: PASS (about 87 s).
- `OCUTALON_RUN_TAG=e1s1a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh live demo-path` (once): expected: PASS, with the `@floor` test passed (about 60 s).
- `OCUTALON_RUN_TAG=e1s1a OCUTALON_LOCK_OWNER='epic=1 stage=implement' bash ci/iris.sh teardown` (once): expected: removes only e1s1a's projects.

**Shared surfaces:**
- The System Default Settings rows of `OcuTalon.Production`: new `Model` and `ProviderConfig` rows for the three runners.
- The instance-wide Config Store entries `AI.LLM.OcuTalonTriage`, `AI.LLM.OcuTalonDiagnosis` and `AI.LLM.OcuTalonChat`.
- The agents' INSTRUCTIONS and TOOLSETS, which the mock's constants test reads.
- The toolset inventory (`OcuTalon.Tools.Watch`).
- The stub list in `Test.Bridge.Api`.
- Tests updated for the new shape: `Test.Bridge.Api`, `Test.Agent.Constants`, `Test.Install.Production`, and Lane B's `docker/tests/test-production.sh` (the "a runner that resolves no model" check only, per the orchestrator's grant).

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. The lead runs `shard lane-a` and `shard lane-b` forward, then both with `--reverse`.

**Mutations to demonstrate (Rule 19):** one per AC. Record each as `mutation: <change> -> <test went red>`.

| Change | Test that goes red |
| --- | --- |
| Diagnosis `TOOLSETS` set to `""` | `TestToolsets` |
| `{{x}}` added to Chat's INSTRUCTIONS | `TestNoTemplates` |
| `confidence` dropped from Triage's INSTRUCTIONS | `TestTriage` |
| The refusal sentence reworded | `TestChat` |
| The header added for the base URL alone | `TestDetails` (DW-39) |
| `api_key` read from `GetEnviron` | `TestDetails` and `KeyScan` |
| `Create` used instead of `Modify` | `TestRerun` |
| The row written before the entry | `TestEntryBeforeSetting` |
| `RebuildRegistry` removed | `live install-start` |
| An existing `Model` row overwritten | `TestSeedModels` |
| `SeedModels` not called | `TestRunnersResolve` |
| `ResolveModel` ignores the setting | `TestModelChange` |
| `Merge` replaces the entry | `TestMerge` |
| `Merge` accepts a literal `api_key` | `TestMergeRefused` |
| `Start` no longer fails on an unresolved runner | `live production`, its `start-unresolved` line |

**Measured facts (Task 0, `ocutalon-slot-a`, namespace `OCUTALON`, `iris_server_info` showed build 154U; process-local only):**
- (a) Passed. After `Set os = ##class(%SYS.Python).Import("os")` and `os.environ.__setitem__("OCUTALON_TASK0_PROBE", ...)`, both `$SYSTEM.Util.GetEnviron("OCUTALON_TASK0_PROBE")` and `##class(%AI.Utils.SettingStore).Expand("@{env:OCUTALON_TASK0_PROBE}")` returned the value in the same process. After `os.environ.pop`, `GetEnviron` returned "". The key scan therefore needs no Lane B change.
- (b) Passed. `OcuTalon.Tools.Watch` and `WatchFixture` compile together on the slot. A fresh `%AI.ToolMgr` accepts `RegisterToolSet("OcuTalon.Tools.Watch")`, and `%Discover()` lists exactly `read_event_log`, `read_failed_messages` and `read_item_settings`, each with `metadata.ReadOnly` = `"1"` and `requires_auth` false. `ExecuteTool` returns `{"timing":...,"value":"{\"items\":[]}"}`. A first IPM compile in a throwaway showed that `Watch` must declare `DependsOn = OcuTalon.Tools.WatchFixture`: its generator reads the methods that the tools name.

**Mutations demonstrated (Rule 19).** Each was applied to the code under test, run in a throwaway of tag `e1s1a`, and reverted; after each revert `git status --short`, `git diff` and the hashes of the untracked files were identical to their values before the mutation.
- mutation: Diagnosis `TOOLSETS` set to "" -> `Test.Agent.Instructions.TestToolsets` went red ("Diagnosis has OcuTalon.Tools.Watch only" and the discovery of the three tools)
- mutation: `{{x}}` added to Chat's INSTRUCTIONS -> `Test.Agent.Instructions.TestNoTemplates` went red ("OcuTalon.Agent.Chat has no {{ in its INSTRUCTIONS")
- mutation: `"confidence"` renamed in Triage's INSTRUCTIONS -> `Test.Agent.Instructions.TestTriage` went red ("the instructions name the field confidence")
- mutation: "I can't run commands." reworded to "I cannot run commands." in Chat's INSTRUCTIONS -> `Test.Agent.Instructions.TestChat` went red ("the instructions hold the sentence of the catalog")
- mutation: header added for the base URL alone (condition `(flag = "1") || (baseUrl '= "")`) -> `Test.Install.Provider.TestDetails` went red (the eight base-URL-alone assertions)
- mutation: `api_key` taken from `GetEnviron("ANTHROPIC_API_KEY")` when it is set -> `Test.Install.Provider.TestDetails` went red ("a key in the environment", "and the details hold no key") and `Test.Agent.KeyScan` went red ("the expansion leaves the key as the placeholder", "the fake key is in no entry, saved session, setting or event-log row"). The form that always reads the variable fails the fresh start instead (the descriptor requires an api_key), so the conditional form kept the stack up.
- mutation: `Create` used instead of `Modify` -> `Test.Install.Provider.TestRerun` went red ("Run() modifies the existing entries => ERROR #26415: Configuration already exists: AI.LLM.OcuTalonTriage"); `TestEntryBeforeSetting` and `KeyScan` went red as well
- mutation: the ProviderConfig row written before its entry, while the production runs (in a fresh start the row-first order fails the after-start log instead: `STEP Provider FAILED ... SettingLookupFailed: SettingStore lookup failed for @{config:OcuTalonTriage}`, and the stack never becomes ready) -> `Test.Install.Provider.TestEntryBeforeSetting` went red ("Run() writes both again => SettingLookupFailed", "the entry is back", "and so is the row")
- mutation: `RebuildRegistry()` removed -> `live install-start` went red (`STEP Provider FAILED ... ERROR #26414: No descriptor found for AI.LLM`, "the first start did not end ready")
- mutation: guard removed so that SeedModels overwrites an existing `Model` row -> `Test.Install.Production.TestSeedModels` went red ("the existing row is kept as it is")
- mutation: `SeedModels` not called by `Run()` -> `Test.Agent.Models.TestRunnersResolve` went red ("TriageAgent has a Model row", and the same for the other two runners); `TestModelChange` went red as well
- mutation: `ResolveModel` ignores the setting -> `Test.Agent.Models.TestModelChange` went red ("ResolveModel gives claude-sonnet-5-5"); `Test.Install.Production.TestRunnerModels` and `TestSeedModels` went red as well
- mutation: `Merge` writes `fields` instead of the merged details -> `Test.Bridge.ConfigStore.TestMerge` went red ("Required field missing: model_provider")
- mutation: `Merge` accepts a literal `api_key` (the api_key branch of the refusal scan switched off) -> `Test.Bridge.ConfigStore.TestMergeRefused` went red ("case 1 is refused" and the cases after it)
- mutation: `Start` no longer fails on an unresolved runner -> `live production` went red, on the `start-unresolved` line (wanted `CHK|start-unresolved|1|1`)

**Mutations of the review pass (Rule 19; same method, each reverted with the `git diff` hash against the baseline identical).**
- mutation: `Apply` passes "" for the CA file to `WriteRunner` -> `Test.Install.Provider.TestApplyCaFile` went red ("OcuTalonTriage is the entry of Details for the file")
- mutation: the base-URL pattern allows a user name, a query and a fragment, and the error text echoes the URL -> `Test.Install.Provider.TestBadOverrides` went red (the user-name, query and fragment URLs "is refused", and "and not the URL")
- mutation: the base URL and CA file checks no longer stop `Apply` before the writes -> `Test.Install.Provider.TestBadOverrides` went red (both "and writes nothing" lines); `TestEntries` went red after it, on the entries it left
- mutation: `Production.Run()` seeds the models after `Start` -> `Test.Agent.Models.TestAppliedAtStart` went red (the three runners "applies claude-haiku-5-5 as started"); the same assertion inside `TestRunnersResolve` had stayed green, because `TestModelChange` updates the production first
- mutation: Chat gets `TOOLSETS = "OcuTalon.Tools.Watch"` -> `Test.Agent.Instructions.TestToolsets` went red ("Chat has no toolset")
- mutation: Diagnosis's "Never change anything." reworded to "Change nothing." -> `Test.Agent.Instructions.TestDiagnosis` went red ("and that it never changes anything")
- mutation: the template-call scanner compares in the case of the source -> `Test.Agent.Instructions.TestNoTemplates` went red ("the call scanner is blind to case")
- mutation: `Merge` reads with `resolveSecrets` 1 -> `Test.Bridge.ConfigStore.TestKeepsSecretReference` went red ("Merge reads it without resolving the reference => ERROR #26220: Error using secret ...")

**Tests added by QA (Rule 8: each sits directly in an area folder of the lane-a shard, so `ci/iris.sh` discovers it; no `ci/units.sh` edit).**
- (QA) `src/ocutalon/cls/OcuTalon/Test/Install/ProviderEnv.cls` (new; throwaway only): `Provider.Run()` from the process environment, one test per matrix row (judges' install, flag alone, base URL alone with the flag unset, `0`, `true`, ` 1` and `1 `, CI, CA file, bad base URL and missing CA file through `Run()`), with the expected entries written out as JSON text, plus the descriptions of a created entry and of the rows. Each test puts the three variables, the entries and the rows back and asserts that it did.
- (QA) `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` (a test and a helper added): `TestSeedSpecificity` and `DeleteModelRows`, on the existing fixture production.
- (QA) `src/ocutalon/cls/OcuTalon/Test/Bridge/ConfigStore.cls` (two tests added): `TestMergeRefusedAmongValidFields` and `TestMergeKeyNameCharacters`.

**Mutations of the QA pass (Rule 19; each applied to the code under test, run in a throwaway of tag `e1s1q`, reverted with `git checkout` of that file, and the hash of the tree without the lead's cycle log identical before and after).**
- mutation: `Apply` defaults an empty base URL to the mock's URL (AC3, the judges' install and the flag-alone rows) -> `Test.Install.ProviderEnv.TestJudgesInstall` went red (the three entries), as did `TestFlagAlone` and `TestCaFileFromEnvironment`; every other class of the lane-a shard stayed green, `Test.Install.Provider` and `Test.Agent.KeyScan` included, because the CI environment always sets the base URL
- mutation: `Run()` reads the CA file from the variable `OCUTALON_EXTRA_CA_FILES` (AC3, the CA-file row) -> `Test.Install.ProviderEnv.TestCaFileFromEnvironment` went red (the entries of both runs) and `TestBadEnvironment` went red ("Run() fails for a CA file that does not exist"); every other class stayed green
- mutation: the description of `Create` in `WriteRunner` emptied (the Provider task's description clause) -> `Test.Install.ProviderEnv.TestDescriptions` went red ("the entry that was created says that the step writes it at every start")
- mutation: `SeedModels` takes the item's own `Model` setting and the row (production, item, any class, `Model`) as the only evidence of a model (AC4, the Model seed row, "any default row") -> `Test.Install.Production.TestSeedSpecificity` went red for the row of the adapter class, the row for every item of that class, the row for every item and class, and the row named `Adapter:Model` ("is the only row, so the runner is not seeded"); `TestSeedModels` and `Test.Agent.Models` stayed green
- mutation: `Merge`'s refusal scan stops after the first key of an object (AC7, "Merge refused") -> `Test.Bridge.ConfigStore.TestMergeRefusedAmongValidFields` went red in all ten cases (refused field after valid ones, the entry changed); `TestMergeRefused` stayed green, because each of its cases puts the refused field first
- mutation: the placeholder pattern of `Merge` allows `.` and `-` in the variable name (AC7, "not exactly one `@{env:NAME}`") -> `Test.Bridge.ConfigStore.TestMergeKeyNameCharacters` went red (`@{env:A-B}` and `@{env:A.B}` were accepted); `TestMergeRefused` stayed green

**Mutations of the code review (Rule 19).** Method: tag `e1s1r`, one build for both mutations, one class per throwaway. Each mutation was reverted by copying the saved files back. Before and after, `git status --short`, the hash of `git diff` without the lead's cycle log, and the hash of the untracked file were identical.
- mutation: `Production.Run()` seeds the models after `Start` (AC4) -> `Test.Agent.Models.TestAppliedAtStart` went red ("TriageAgent applies claude-haiku-5-5 as the step started it", and the same for DiagnosisAgent and ChatAgent); its ProviderConfig assertions stayed green. The test now deletes the three rows and runs the step itself, so this line holds in either method order. It replaces the review pass's line for `TestAppliedAtStart`, and decision 24 no longer applies.
- mutation: the Provider step's `Modify` keeps the entry's resources (the Always rule on the default `%Admin_ConfigStore` read and edit resources) -> `Test.Install.Provider.TestRerun` went red ("and the read and edit resources are the default again").

**Results on the unmutated tree (final pass, after the last patch; tag `e1s1a`, one stack at a time, `ci/iris.sh teardown` left nothing):** `bash ci/checks.sh`: every block passes except `boundaries`, whose one failure is `_bmad-output/implementation-artifacts/cycle-log-epic-1.md:1`, a local path in the HEAD commit's cycle log (outside this story; deferred). `ci/iris.sh build`: exit 0. `shard lane-a`, forward (65 s) and `--reverse` (74 s): 14 of 14 classes passed, the five new ones and `Test.Bridge.ConfigStore` included; the one SKIP is `Test.Install.Production.TestStepHelpers`' existing skip of the `NotRunning` check while the production runs (Story 0.6; the "no SKIP" in the command holds only when that production does not run). Once: `bash docker/tests/test-mock.sh` 94 of 94; `shard lane-b` 24 of 24, `Test.Contract.Mock` included (forward only; the lead runs `--reverse`); `live install-start` 94 PASS (about 196 s), `install-upgrade` 34 PASS (about 172 s), `compose-start` 36 PASS (about 74 s), `production` 23 PASS (the check "a runner that resolves no model" with its five values), `production-restart` 15 PASS, `demo-path` passed with the `@floor` test (about 64 s, `FIRST-START engine=aarch64 build=0s ready=56s`). Task 0 and the slot: only process-local calls and `iris_doc_load` compiles on `ocutalon-slot-a`.

**Results of the QA pass (tag `e1s1q`, one stack at a time, `ci/iris.sh teardown` removed nothing left over).** `bash ci/checks.sh`: all 12 blocks passed, `boundaries` included. `ci/iris.sh build`: exit 0. `shard lane-a` forward (63 s) and `--reverse` (58 s): 15 of 15 classes passed, `Test.Install.ProviderEnv` among them; the one SKIP is the existing `TestStepHelpers` skip (Story 0.6). Compiles on `ocutalon-slot-a` (build 154U) with `iris_doc_load` flags `ck` only; no test ran there.

## Clarification Record

**Resolved 2026-10-21 by the orchestrator's ruling (`category=decide`, logged in `cycle-log-parallel.md`):** option (a), the fixture edit is granted to Lane A as a footprint extension of this story, inside the "a runner that resolves no model" check only (the task "The Lane B fixture"). The plan's question, kept as asked:

**The blocking question.** The question concerns the contended path `docker/tests/test-production.sh`, which belongs to Lane B.

- **What breaks.** The AC seeds `OcuTalon.Production||<runner>||*||Model` = `claude-haiku-5-5` at the first start. The live check at lines 274-295 then loads an `OcuTalon.Agent.Triage` with no `MODEL` and expects `##class(OcuTalon.Install.Step.Production).Start(15)` to fail naming TriageAgent. The seeded row now resolves TriageAgent, so `live:production` goes red. The `production` group runs on every push.
- **Why Lane A cannot fix it alone.** No Lane A design avoids this without contradicting AD-7 and AD-19, under which the `Model` setting wins over the class parameter.
- **The change needed.** Inside that check, before `Start(15)`, delete the row: `Do ##class(Ens.Config.DefaultSettings).%DeleteId("OcuTalon.Production||TriageAgent||*||Model")`. Optionally, call `Production.Run()` instead of `Start(30)` after the class is restored, so the row is re-seeded. That is about 2 lines.
- **Recommendation.** The orchestrator grants Lane A this one edit as a footprint extension of Story 1.1, adds it as a task, and sets this spec to `ready-for-dev`. Everything else in this spec is complete.

**For the veto window (not blocking).** These choices cover how a credential is handled; recommended as planned:
- Decision 10, Merge's key rule.
- Decision 13, the fake key in the test process's environment.

## Auto Run Result

Status: done
Blocking condition: none

**Implemented.** Story 1.1: the three agents have static instructions and toolsets (Diagnosis gets the read-only fixture `OcuTalon.Tools.Watch` with `WatchFixture`); the Provider step writes one `AI.LLM.OcuTalon<Agent>` entry per runner (placeholder key, no model, overrides from the environment, including DW-39's mock-key header only for `OCUTALON_MOCK_KEY_HEADER=1`) and then each runner's `ProviderConfig` row; the Production step seeds each runner's `Model` row where absent; `OcuTalon.Bridge.ConfigStore.Merge` is implemented; tests prove that a key in the environment is stored nowhere.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Agent/{Triage,Diagnosis,Chat}.cls`: INSTRUCTIONS and TOOLSETS.
- `src/ocutalon/cls/OcuTalon/Tools/{Watch,WatchFixture}.cls` (new): the read-only fixture toolset.
- `src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls`: `Run`, `Apply`, `Details`, the override checks, `WriteRunner`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls`: `Runners`, `WriteDefault`, `SeedModels`, `AgentModel`; `Run` seeds before `Start`.
- `src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls`: `Merge`.
- `src/ocutalon/cls/OcuTalon/Test/Agent/{Instructions,Models,KeyScan}.cls`, `Test/Bridge/ConfigStore.cls`, `Test/Install/Provider.cls` (new); `Test/Agent/Constants.cls`, `Test/Bridge/Api.cls`, `Test/Install/Production.cls` (updated for the new shape).
- `docker/tests/test-production.sh`: the granted Lane B fixture edit inside the check "a runner that resolves no model" only (deletes the seeded row, one added CHK line, `Run()` for the healthy start).
- This spec: Task 0 facts, mutation lines, decisions 14 to 25, the triage log, the deferred list.

**Review.** Four layers reported 58 findings: high 0, medium 8, low 48, false 2. Patches applied (18 rows, 9 root causes): the always-true precondition in `TestBadOverrides`; the toolset tally and Chat's empty toolset; Diagnosis's instruction assertions; the base-URL pattern (no user name, query or fragment) and an error text without the value; `TestApplyCaFile`; `TestAppliedAtStart` (the seed-before-start order); `TestKeepsSecretReference` (`resolveSecrets` 0); the case-blind template scan with `##;` comments; the corrected class comment of `Merge` and decision 21. Deferred (2 items): the validation of values a user supplies, owned by Story 17.3 (`Merge` judges only `api_key` and `@{`), and the red `boundaries` check on the lead's cycle log. Rejected: 36 rows, each with its reason in the triage log (spec-bound, theoretical or guard-only lows, and the 2 false).

**Follow-up review recommended: true.** Three medium entries were patched. The unverified risk: `TestAppliedAtStart` pins the seed order only when it runs before `TestModelChange` (it does, by name; the class passes in either order but then pins nothing), and the stricter base-URL pattern was exercised against the mock's URL and the test rows only, not against an operator's real proxy address.

**Verification.** See the Results paragraph under `## Verification`: `ci/checks.sh` red only on the pre-existing cycle-log line; `build`, `shard lane-a` forward and reversed, `shard lane-b`, `test-mock.sh`, and the six live units all passed; 23 mutations demonstrated, each reverted with the tree hash unchanged.

**Residual risks.**
- `ci/checks.sh` `boundaries` fails on `cycle-log-epic-1.md:1` (the lead's bookkeeping commit holds a local path), so the hosted `checks` job goes red on the next push until the lead changes that line.
- `Merge` leaves the choice of key variable, `base_url`, headers and `secret://` references to its caller (Story 17.3).
- `shard lane-b --reverse` was not run in this pass (the lead's fresh-environment check).
