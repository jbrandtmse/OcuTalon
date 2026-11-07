---
title: 'Story 17.3: Run each agent on a supported provider'
type: 'feature'
created: '2026-11-05'
status: 'done'
baseline_revision: 'cc12bd0ed1ec133415b5446bf653ef975105fc87'
baseline_commit: 'cc12bd0ed1ec133415b5446bf653ef975105fc87'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-17-context.md'
warnings: ['oversized']
deferred:
  - summary: >-
      An instance that already holds the seeded Price row of claude-sonnet-5-5 keeps its cache-read rate 0.2; the seed is now 0.1, and a model change can now select that model.
    evidence: |-
      SeedPrices never overwrites an existing row (AD-19 seed values), so only fresh installs get 0.1. The pricing page of 2026-11-05 lists 0.10 for Claude Sonnet 5.5 cache reads. The effect is an over-stated cost for cache reads of a model that is not the default; changing a stored price on upgrade is a stored-data change (veto window).
    location: >- # optional
      src/bridge/cls/OcuTalon/Bridge/Installer.cls:Prices
    severity: low
  - summary: >-
      A resolved or chosen provider keeps the entry's base_url, custom_headers and tls, so a key of another provider could be sent to an endpoint that was set for the first provider.
    evidence: |-
      Decided in-stage 5: Providers.Resolve and Merge's model shape keep the entry's other fields; OCUTALON_MODEL_BASE_URL (the only writer of base_url, via the Provider step) is set by CI and the online demo, both Anthropic-only, and only Anthropic is supported, so it cannot happen today. It becomes reachable when the Release check (REL-7) flags another provider supported while a base_url is set. A test that sets a base_url on the entry and resolves or chooses another provider would settle it.
    location: >- # optional
      src/bridge/cls/OcuTalon/Bridge/Providers.cls:Resolve; src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls:ModelShape
    severity: medium (unverified)
  - summary: >-
      No throwaway runner job holds a model key, so a decide through a resolved provider and a scan for a key that a job holds are proved in process only.
    evidence: |-
      The CI override sets no model key and a variable that a test sets reaches no job (measured), so resolution is pinned by Keys.Absent, Providers.Resolve, the shadow runner (built agent and session config equal to a direct choice, RecordKey through a forced job) and the live Anthropic-path tests (IG-1 ruled option B, U-288 kept). A live unit with a dummy key variable in its compose file would close it; it needs ci/units.sh and the Release check can decide.
    location: >- # optional
      src/ocutalon/cls/OcuTalon/Test/Bridge/ModelChange.cls:TestResolvedLive, TestNoKeyValueAnywhere
    severity: medium
---

<intent-contract>

## Intent

**Problem:** Every agent runs only on Anthropic. Story 33.1 left `Bridge.Settings` as stubs, and the spine's provider table (AD-7) does not exist yet. A runner whose Anthropic key is missing always falls back with `no_key`, even when another supported provider's key is set. `ConfigStore.Merge` lets any `@{env:NAME}`, a `base_url`, a header or a `secret://` value through (DW-52), and a provider's own stop reason that the bridge does not know counts as an answer.

**Approach:** This story builds four things:
- the fixed provider table `OcuTalon.Bridge.Providers`, with prices for its models;
- the model-change API (`Settings.Providers`, `CheckModel`, `SetModel`, for a first model and a second model), through a `ConfigStore.Merge` that accepts only two fixed shapes;
- provider resolution before `no_key`, in the runner and in `Keys`;
- an `unusable` reason for any stop reason the bridge cannot classify.

All of it applies to the retry runners too.

## Boundaries & Constraints

**Always:**
- **The provider table.** `OcuTalon.Bridge.Providers` is a fixed `XData` table. Its rows are, in this order:
  - `anthropic`: default model `claude-haiku-5-5`; selectable `claude-haiku-5-5` and `claude-sonnet-5-5`; key variable `ANTHROPIC_API_KEY`; supported 1.
  - `openai`: default `gpt-5.4-mini`; selectable `gpt-5.4-mini` and `gpt-5.4`; key variable `OPENAI_API_KEY`; supported 0.
  - `gemini`: default `gemini-3.1-flash-lite`; selectable `gemini-3.1-flash-lite` and `gemini-3.1-pro-preview`; key variable `GEMINI_API_KEY`; supported 0.
  - `bedrock`: default `us.anthropic.claude-haiku-5-5`; selectable `us.anthropic.claude-haiku-5-5` and `us.anthropic.claude-sonnet-5-5`; key variable `AWS_BEARER_TOKEN_BEDROCK` (the region comes from `AWS_REGION`, inside AI Hub); supported 0.

  Every selectable model has a seeded `Bridge.Data.Price` row.
- **The session config, for every listed model (AD-7).** It has:
  - no `temperature`, `top_p` or `top_k`;
  - a cap of 8,000 in the family's key: `extra_params.max_completion_tokens` for `gpt-5*`, otherwise `max_tokens`;
  - effort only for `claude-*` models (the `anthropic` family);
  - the cache block, every time.
- **A key never leaves the environment (AD-19, NFR-11).** A key reaches a provider only as `@{env:<the provider's own variable>}`. No key value is written to an entry, a setting, a saved session, a log or an audit entry, or returned by an API. Only the presence of a key variable is ever read.
- **`ConfigStore.Merge` accepts exactly two shapes.** Anything else is refused with a reason that names the field and never holds a value, and nothing is written. The signature stays `(entry, fields)`.
  - **The timeouts shape.** Only `http_config.request_timeout_secs` (a number) and `http_config.retry` (an object of numbers). `Timeouts.Apply` uses it.
  - **The model-change shape.** Exactly these fields:
    - `model_provider`, a provider of the table;
    - `api_key`, exactly `@{env:<that provider's key variable>}`;
    - optionally `model`, a selectable model of that provider. It is validated and never written (AD-7: an entry never holds a model).
  - An empty object merges nothing and is OK.
- **`SetModel(agent, provider, model, second, .old)`.** `agent` is a first runner item: `TriageAgent`, `DiagnosisAgent` or `ChatAgent`. `CheckModel` passes first, with no write. Then:
  - `second` 0: the agent's entry is merged in the model-change shape, the item's `Model` System Default row is written and read back, and the item alone is restarted.
  - `second` 1: the same, on the retry item `<agent>Retry`. The first runner's `RetryItem` row is then set to `<agent>Retry`. An empty provider and model sets `RetryItem` to "" and leaves the retry item as it is.
  - `old` is `{provider, model}` (plus `retryItem` when `second` is 1). It never holds a key.
  - A failure after the first write puts back what was written.
- **`CheckModel` refuses, with a plain-English reason**, any of these:
  - an argument that holds `@{`;
  - an agent outside the three;
  - a provider that is not in the table, not supported, or whose key variable is not set;
  - a model the provider does not list;
  - an empty provider or model when `second` is 0.
- **Resolution, before `no_key` (AD-7, AD-8).** It applies to any runner item, the retry items included, and only when both hold:
  - the item's entry key is `absent` (`Keys.State`);
  - its resolved `Model` equals its agent class's `MODEL`.

  Then the runner uses the first table row in order that is not the entry's own provider, is supported, and has its key variable set. It runs on that row's default model and an in-memory config: the entry's details with `model_provider` and `api_key` replaced. Nothing is written.
  - `Keys.Record` (and so `Status`) and `Keys.Absent` answer for the resolved provider.
  - An `unknown` key state never resolves, and neither does an admin's model.
  - With no candidate, the runner gets `no_key`, as in release 1.
- **Classify (AD-8).** A reply that has text and a non-empty `finishReason` outside `refusal`, `max_tokens` and the known normal ends (`end_turn`, `stop_sequence`, `tool_use`, `stop`, compared without regard to case) is `unusable`. It is never an answer.
- **The Provider install step keeps a chosen provider.** It keeps an existing entry's `model_provider` and `api_key` when they are a table provider and exactly its own placeholder. Every other field stays structural.
- **Lane and footprint rules.**
  - The bridge names no OcuTalon package (AD-2). Storage is unchanged (AD-5).
  - Source is ASCII, and comments state the contract (Rule 14).
  - Tests use the CI mock on the Anthropic path, in throwaway stacks, with no network.

**Never:**
- A real provider, a real key, network access, or a `supported` flag set to 1 for openai, gemini or bedrock. Those flags belong to the Release check (REL-7).
- `Values()`, `Check`/`Set`, `SetPrice`, `TestRequest` or `TestAnswer` (Story 17.4). They stay stubs.
- Edits to a Lane B class or test (U-177).
- Edits to a contended path: `Core/SettingsOps.cls`, `Web/Api.cls`, `Bridge/Msg/Enum.cls`, `Bridge/Ext/**`, `Test/Contract/Ac.cls` (Epic 34 changes it), `Test/Eval/**`, `ci/units.sh`, `src/short-names.tsv`, the spine.
- Edits to `Bridge.Redact`, `Test.Eval.KeyProof` or `Test.Agent.KeyScan`. They are called, never changed.
- Any destructive run on `ocutalon-slot-a`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Model change | `SetModel("TriageAgent","anthropic","claude-sonnet-5-5",0,.old)` | Entry `AI.LLM.OcuTalonTriage` = `{anthropic, @{env:ANTHROPIC_API_KEY}}` and holds no model. `Model` row is `claude-sonnet-5-5`. Only `TriageAgent` restarts. `old` = `{provider:"anthropic",model:"claude-haiku-5-5"}`. The next decide's mock log model and `Decision.Model` are `claude-sonnet-5-5`. | none |
| Second model | `SetModel("TriageAgent","anthropic","claude-sonnet-5-5",1)`, then `("TriageAgent","","",1)` | `TriageAgentRetry` Model is sonnet, and `TriageAgent.RetryItem` is `TriageAgentRetry`. With `retry-refusal` armed, the retry answers with sonnet. After the clear, `RetryItem` is "" and there is no retry. | none |
| Refused change | Provider `openai` (unsupported); `nope`; model `gpt-5.4` on `anthropic`; agent `TriageAgentRetry`; any value with `@{`; key variable unset | An error with a plain reason. Entries, `Model`/`RetryItem` rows and jobs are unchanged. | error status |
| Merge shapes (DW-52) | Model shape plus each of: `@{env:PATH}` as `api_key`; `base_url`; `http_config.custom_headers`; `secret://x`; `@{config:x}`; `org_id`; unknown provider; model of another provider; `api_key` without `model_provider`. Timeouts shape plus `base_url` | Each refused, naming the field. The entry details are byte-equal before and after. `{model_provider, api_key, model}` valid → OK, and the entry has no `model`. | error status |
| Resolved (AC literal) | In process: shadow runner with `ZzProviders` (anthropic key unset; openai supported, its variable set by `KeyScan.SetEnv`); `Model` default | The built agent's `Provider.Name` is `openai`, `Model` is `gpt-5.4-mini`, and the config has `extra_params.max_completion_tokens` 8000 and no effort. `Keys.Record` state is present. Nothing is sent. | none |
| Resolved (live) | `TriageAgent` and `TriageAgentRetry` entries = `{openai, @{env:OPENAI_API_KEY}}` (unset), `Model` default, restart | `Keys.Status` is 1 and `Keys.Absent` is 0 for both. A decide answers through the mock on `claude-haiku-5-5` with no fallback. | none |
| Admin model | Same entries, `Model` `claude-sonnet-5-5` | No resolution: the decide falls back `no_key` and nothing is sent | fallback |
| No supported key | Every runner's key pointed at an unset variable (`RunnerFixture`) | Every item runs, `Keys.Status` is 0, and a decide falls back `no_key` with no mock request | fallback |
| Unclassified stop | A reply with text and `finishReason` `pause_turn`, `content_filter`, `length` or `SAFETY` | Fallback `unusable`, no answer text; `end_turn`, `tool_use`, `stop`, `STOP` stay usable | fallback |
| Step keeps provider | Entry `{openai, @{env:OPENAI_API_KEY}}`, then the Provider step runs; entry `{openai, @{env:OTHER}}` | The first is kept, and its `http_config` is rewritten. The second gets `{anthropic, @{env:ANTHROPIC_API_KEY}}`. | none |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Settings.cls`: the 33.1 stubs. `Providers` (:23), `CheckModel` (:48) and `SetModel` (:54) are built here. The other methods stay stubs. Its class doc (:1-18) holds the contract.
- `src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls`: `Merge` (:37), the guard `Refusal` (:100), `MergeInto` (:126), `Details` (:64), `EntryOf` (:84) and `KEYPATTERN` (:20). Its doc (:5-9) says that "Merge judges nothing else", which changes.
- `src/bridge/cls/OcuTalon/Bridge/Keys.cls`:
  - `Absent` (:61), `Record` (:85) and `State` (:118, `Private` today);
  - `ApiKeyState` (:149) reads presence only.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - `OnInit`/`RecordKey` (:115/:136) and `BuildAgent` (:170);
  - `Compose` (:212; family by the longest `ModelPrefix`; `CAP`) and `SessionConfigFor` (:262).
  - AI Hub's `setupProviderFromSettings` reads the adapter's in-memory `ProviderConfig` and `Model` (`irislib/EnsLib/AI/Agent/OutboundAdapter.cls:146-170, 243-290`). That is the seam where a resolved config goes in before `##super()` `OnInit`.
- `src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls`: `ResolveModel` (:52) gives the configured model, unchanged (Web/Api shows it). `SETTINGS` (:18).
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: `Classify` (:1205), with its doc at :1195-1204 (rule 5 already gives empty text with no finish reason `unusable`), and `#RUNNERS` (:127).
- `src/bridge/cls/OcuTalon/Bridge/Timeouts.cls`:
  - `Apply` (:93; it merges `{http_config}` into each entry) and `Entries` (:131);
  - `IsRetryItem` / `RETRYSUFFIX`;
  - `Restart(production, runners)` (:183): it always restarts `Decide`, and its error texts say "new timer".
- `src/bridge/cls/OcuTalon/Bridge/Installer.cls`: `ModelFamilies` (:27; `claude-`, `gpt-5`, default; no new row needed), `Prices` (:63, two rows) and `SeedPrices` (:73, seed).
- `src/bridge/cls/OcuTalon/Bridge/Ext/Accessor.cls` (read only, contended): `WriteDefault(production,item,setting,value,description)` and `ValueFor`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls`:
  - `Details` (:100) writes `anthropic` and `KEYPLACEHOLDER` every time;
  - `WriteRunner` (:147) uses `Modify` when the entry exists.
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls` (read only): `SeedModels` (:209) and `WriteDefault`.
- Tests and fixtures:
  - `Test/Bridge/ConfigStore.cls`: Merge mechanics tests on `base_url`, headers and any `@{env:}`, at :62-227. They are rewritten for the two shapes.
  - `Test/Agent/RunnerFixture.cls`: `SetKeys` (:555) writes through `Merge` with arbitrary variables (`PointKeys` = `@{env:OCUTALON_MOCK_KEY_HEADER}`, a non-secret variable that is set); `RUNNERS` (:71) and `Restart` (:115).
  - `Test/Bridge/SettingsStubs.cls`: `TestSettingsStubs` asserts that `Providers` is `[]` and that `CheckModel`/`SetModel` give 5003. `TestNothingWritten` (`CallEverything`) snapshots the entries and Price rows and expects zero `RetryItem` rows.
  - `Test/Bridge/Fallback.cls`: `AssertReason` cases at :53-72. Line 62 (`tool_use` with text is usable) stays green.
  - `Test/Bridge/Decide.cls`: `AssertFallback` (:1494-1511) and `NewReply` (:3888).
  - `Test/Bridge/SessionConfig.cls`: in process, it snapshots and restores the `ModelFamily` rows.
  - `Test/Bridge/Usage.cls`: `TestSeedPrices` covers the two rows.
  - `Test/Install/Provider.cls`: `TestEntries`.
  - `Test/Bridge/SecondModel.cls`: the live `RetryItem` pattern, `OnAfterOneTest` cleanup and `retry-refusal`.
  - `Test/Bridge/Conversation.cls` with `ZzRetryRunner`/`ZzRetryAdapter`: the shadow-runner pattern.
  - `Test/Agent/Decide.cls`: `Prepare`/`Case`/`Arm`/`PointKeys` for live decides.
  - `Test/Agent/KeyScan.cls`: `SetEnv`/`UnsetEnv`/`HasEnv` (python, process only) and `Find(value)`, the stores scan.
  - `Test/Eval/KeyProof.cls`: `GlobalHits(value)` scans every database.
  - `Test/Bridge/Keys.cls`: existing `Absent`/`Status` cases.
- `ci/mock/scenarios.mjs` `STOP_REASONS` (:44) allows `pause_turn`. A one-reply scenario serves that reply every time.

## Tasks & Acceptance

**Execution:**
- [x] **Task 0 (measure).** On a warm throwaway, read-only on slot A, record the results under `## Design Notes`:
  - (a) AI Hub's `Response.Extra.finish_reason` for a mock reply with `stopReason` `pause_turn` and text (a new scenario `unclassified-stop`).
  - (b) Whether a shadow agent built with `model_provider` `openai` and a fake key from `SetEnv` sends nothing (mock log unchanged).
  - (c) Re-confirm each new model id and its list price on the official pricing pages. Record the date. Where a page differs, use the page's value.
- [x] `src/bridge/cls/OcuTalon/Bridge/Providers.cls` (new):
  - `XData Table` (the rows above);
  - `Rows()`, which reads the `XData` of the calling class (`$ClassName()`), so that a test subclass can replace it;
  - `Row(provider)`;
  - `KeySet(provider)`, presence only;
  - the pure `Choose(rows, entryProvider, entryState, isDefault, .provider, .model)`;
  - `Resolve(item, production, providerConfig, .config, .model)`.

  Class doc: AD-7's resolution rule and REL-7's supported flags.
- [x] `src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls`: replace the guard with the two shapes (Always). The model shape takes the variable from `Providers.Row`. `MergeInto` is unchanged. Rewrite the class doc. This closes DW-52.
- [x] `src/bridge/cls/OcuTalon/Bridge/Keys.cls`:
  - make `State` public;
  - in `Absent`, an `absent` state is 0 when `Providers.Resolve` finds a provider.
  - `Record` keeps its signature. The adapter passes it the resolved config's JSON.
- [x] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - add `ProvidersClass()` (default `OcuTalon.Bridge.Providers`), which a Zz adapter overrides;
  - `RecordKey` records the resolved config when `Resolve` finds one;
  - `BuildAgent`, before `##super()` `OnInit`, sets the in-memory `ProviderConfig` (the resolved JSON) and `Model`.

  Nothing is persisted. Update the class doc.
- [x] `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - in `Classify`, add the unknown-finish rule after rule 5, with a `FINISHED` parameter;
  - update the doc list.
- [x] `src/bridge/cls/OcuTalon/Bridge/Timeouts.cls`: give `Restart` an optional `decide` argument (default 1). Make the error texts neutral ("the change applies at the next restart"). `Timeouts` tests still pass (they check the item names).
- [x] `src/bridge/cls/OcuTalon/Bridge/Settings.cls`:
  - build `Providers()` (rows in order, each `{provider, defaultModel, models, keyVariable, keySet, supported}`), `CheckModel` and `SetModel` (Always);
  - update the class doc (which methods are still stubs, and the agent identifiers).
- [x] `src/bridge/cls/OcuTalon/Bridge/Installer.cls`: add `Prices()` seed rows. All have an empty long tier except Bedrock Haiku, which copies the Claude Haiku row:
  - `gpt-5.4-mini` .75/4.5/.075/0;
  - `gpt-5.4` 2.5/15/.25/0;
  - `gemini-3.1-flash-lite` .125/.5/.0125/0;
  - `gemini-3.1-pro-preview` 2/12/.2/0;
  - `us.anthropic.claude-haiku-5-5` (the `claude-haiku-5-5` row);
  - `us.anthropic.claude-sonnet-5-5` (the `claude-sonnet-5-5` row).
- [x] `src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls`: `WriteRunner`/`Details` keep a valid chosen pair (Always). Update the doc.
- [x] `ci/mock/scenarios/A/unclassified-stop.json`: one reply, 200, `stopReason` `pause_turn`, text.
- [x] `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`: `SetKeys` writes the entry's `api_key` through `ConfigStore.Details` plus `%ConfigStore.Configuration.Modify`. Merge now refuses its test placeholders. The API is unchanged.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/ConfigStore.cls`: rewrite the mechanics tests on the timeouts shape (deep merge into `retry`). Add `TestModelChangeShape` (every Merge-shapes row; entry details compared before and after).
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/Providers.cls` (new, in process):
  - `TestTable`: order, values, only anthropic supported, a Price row for every model;
  - `TestChoose`: order, skips the entry's own provider, the unsupported and the unset; no resolution for an admin model, a present key or an unknown key;
  - `TestResolvedShadowRunner`, the "Resolved (AC literal)" row, with `ZzProviders` plus `ZzProviderAdapter`/`ZzProviderRunner` (new, on the `ZzRetry*` pattern) and `KeyScan.SetEnv`/`UnsetEnv`;
  - `TestSettingsProviders`: `Providers()` order, `keySet` and `supported`;
  - `TestCheckModelRefusals`: every refused input, each with nothing written;
  - `TestIntegrationSettingsOps` (Rule 1): Lane B's real `SettingsOps.Values().providers` equals `Settings.Providers()`, four rows with anthropic first.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/ModelChange.cls` (new, live, the `Test.Agent.Decide` `Prepare` pattern). `OnAfterOneTest` restores, in this order:
  - each touched entry's pair, through Merge's model shape (`anthropic`, `@{env:ANTHROPIC_API_KEY}`). This comes first, because the Provider step now keeps a valid `openai` pair;
  - then the Provider step `Run()`;
  - the `Model` and `RetryItem` rows as found, with no `RetryItem` row left;
  - the restarted jobs. Tests:
  - `TestSetModelNextRequest`;
  - `TestSecondModel`;
  - `TestRefusedChangeKeepsEverything`;
  - `TestResolvedLive` (both items; `Keys.Absent` and `Providers.Resolve` live in the test process, not a decide through the mock: see `deferred` in the frontmatter);
  - `TestAdminModelNeverResolves`;
  - `TestNoSupportedKey`;
  - `TestUnclassifiedStopLive`, as Task 0 (a) found: `unusable` if `pause_turn` passes through; otherwise assert fallback with no answer and record the reason;
  - `TestNoKeyValueAnywhere`, after `SetModel` and one linked `ChatAgent` turn: `KeyScan.Find(key)` names no store, `KeyProof.GlobalHits(key)` is 0, and neither `old` nor the status text holds the key. The test fails with a reason when the key variable is empty.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/SessionConfig.cls`: add `TestEveryListedModel` (every selectable model of `Providers.Rows()`: cap key, 8000, effort only for `claude-*`, cache block, no sampling key at any depth).
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/Fallback.cls` and `Test/Bridge/Decide.cls`: the unclassified-stop rows (`Classify`, and `Conclude` for a turn and a decide). `Classify` rows are in `Fallback.cls` (`TestUnclassifiedStop`); the `Conclude` rows are in the new `Test/Bridge/UnclassifiedStop.cls`, because Epic 40 changes `Test/Bridge/Decide.cls` (Spec Change Log).
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/Keys.cls`: `Absent` with resolution (the openai entry with an unset variable: 0, via the real table), and an unknown state never resolves.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/SettingsStubs.cls`: drop the assertions of `Providers`/`CheckModel`/`SetModel`. `CallEverything` calls the remaining stubs plus refused `SetModel` calls. `TestNothingWritten` keeps its snapshot.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/Usage.cls`: `TestSeedPrices` covers every row of `Installer.Prices()`.
- [x] `src/ocutalon/cls/OcuTalon/Test/Install/Provider.cls`: add `TestKeepsChosenProvider` (the matrix row).
- [x] Search `src/ocutalon/cls/OcuTalon/Test` and `docker/tests` for assertions on the count of Price rows, on Merge accepting `base_url`, headers or an arbitrary `@{env:}`, or on `Settings` stub answers, and update them (Rule 19).

**Acceptance Criteria:**
- Given the provider table with Anthropic (Claude Haiku 5.5 default, Claude Sonnet 5.5), OpenAI, Google Gemini and Amazon Bedrock, each with its default model, selectable models, prices and key variable, when a runner composes the session config for every listed model, then the config has no `temperature`, `top_p` or `top_k`, a cap of 8,000 in the family's key, effort only for Anthropic models and the cache block, and the unit tests prove it with no network access.
- Given `SetModel` for an agent's model, when it is applied, then the agent's entry is merged through `ConfigStore.Merge` with the provider and `@{env:<its variable>}`, the runner's `Model` is set, the runner item restarts, and the next model request (mock log) and `Decision.Model` use the new model.
- Given that change and a turn after it, when the stores, every database and the API's answer are scanned for the key's value, then nothing holds it.
- Given no Anthropic key but another supported provider's key, and a runner on its default model, when the runner starts, then it resolves to that provider's default model in table order before `no_key`, `Keys.Status` is 1, and the request is built for that provider. Live on the Anthropic path, a runner whose entry provider has no key resolves to Anthropic and its decisions answer normally.
- Given no supported provider's key at all, when OcuTalon runs, then every runner item starts and every decision falls back with `no_key`.
- Given a reply whose stop reason the bridge cannot classify, when `Decide` concludes, then it is `unusable` and never treated as an answer.
- DW-52: given a model change merged through `ConfigStore.Merge`, when the fields hold anything but the provider, its own key placeholder and a model of that provider (another variable, a `base_url`, a header, a `secret://` value, another `@{` form), then Merge refuses with a plain reason, nothing changes, and a test submits each.
- Given a second model set with `SetModel(..., 1)`, when the first runner's attempt is refused, then the retry runner answers on the second model; and after the clear, no retry is sent.
- Integration (Rule 1): given the built `Settings.Providers()`, when Lane B's unchanged `SettingsOps.Values()` runs, then its `providers` holds the four rows in table order with `keySet` and `supported`.

- [x] [Owner] IG-2: update `src/ocutalon/cls/OcuTalon/Test/Web/SettingsApi.cls` `TestGetShape` exactly as the IG-2 ruling under Design Notes says (shape-only providers assertion; key-value scan with the three planted shapes and the configured key value, built at run time; the U-177 exception comment); demonstrate one mutation per planted shape; nothing else in any Lane B file.
- [x] [Owner] U-288: confirm no text this story adds claims a provider other than Anthropic runs decisions; record the check in `## Decisions` of the review.

### Review Findings

Code review 2026-11-05 (bmad-code-review, full-opus, four layers; baseline `cc12bd0e` plus the uncommitted QA test). 38 rows, 6 entries after grouping (high 0, medium 1, low 5), all patched; 29 rows rejected (below). No `decision-needed`, no new ledger entry (DW-755, DW-757 and DW-758 already hold the deferred items).

- [x] [Review][Patch] A key used as a field name was echoed in Merge's refusal (a Google-shaped name passed the "plain name" test) — `FieldName` now echoes only lower-case entry-style names of at most 32 characters; `TestModelChangeShape` plants a key-shaped name (built at run time) at three depths [src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls:198] (low, fix-risk low: one pattern, every asserted name is lower case)
- [x] [Review][Patch] Rule 19 hermeticity: the live tests read `old.model` and resolution's default from the Model rows as found — `AtDefault(item)` remembers the row and sets it to the agent's `MODEL` in `TestSetModelNextRequest`, `TestSecondModel`, `TestSetModelEveryAgent` and `TestResolvedLive` [src/ocutalon/cls/OcuTalon/Test/Bridge/ModelChange.cls:532] (medium, fix-risk low: test-only, restored by OnAfterOneTest)
- [x] [Review][Patch] `SetModel`'s clear of a second model left its written RetryItem row behind when the read-back failed, against "a failure after the first write puts back what was written" — the clear path now puts the row back; `TestSetModelFailureRestores` adds the failing clear [src/bridge/cls/OcuTalon/Bridge/Settings.cls:138] (low, fix-risk low)
- [x] [Review][Patch] IG-2: the configured-key leg of `TestGetShape` was demonstrated on `KeyShape` while the real body was checked by a separate inline `$Find` — the real body now goes through `KeyShape(body, configuredValues)` too, so the demonstrated path is the used path (in a throwaway no key is set, as the ruling's "if one is set" foresees) [src/ocutalon/cls/OcuTalon/Test/Web/SettingsApi.cls:161] (low, fix-risk low; inside `TestGetShape`, the IG-2 exception)
- [x] [Review][Patch] U-288: the `Providers` class doc called all four rows providers "an agent can run on" — now "can be configured for; an agent runs only on a provider whose supported flag is set" [src/bridge/cls/OcuTalon/Bridge/Providers.cls:1] (low, fix-risk low)
- [x] [Review][Patch] `Test.Bridge.Providers` header said the tests write no row, but `TestTable` seeds missing Price rows — header corrected [src/ocutalon/cls/OcuTalon/Test/Bridge/Providers.cls:1] (low, fix-risk low)

Rejected (one line each):
- Endpoint fields (`base_url`, headers, TLS) kept across a provider change or resolution (BH, EC x3) — already ledgered DW-758 (routed to 17.4); not re-filed. EC's claim that the ConfigStore doc denies it: false, the doc says the entry's other fields stay.
- Installed `claude-sonnet-5-5` row keeps cache-read 0.2 (BH, EC, VG) — already ledgered DW-757.
- No job-side resolution or key scan; the decide halves of `TestAdminModelNeverResolves`/`TestNoSupportedKey` pass on release-1 behaviour (BH, VG x2) — IG-1 ruled (option B, U-288); already ledgered DW-755.
- Case-sensitive `refusal`/`max_tokens`, `length`/`MAX_TOKENS`/`tool_calls` give `unusable` (BH, EC) — by-design until REL-7 flags a provider supported (carried BH-9/EC-6/EC-7).
- `ConfigStore.Restore` is unguarded (BH) — carried BH-2: entries hold placeholders only.
- An admin's explicit choice of the default model can resolve away (BH, EC claim) — by-design: the contract defines "default" as Model = MODEL; Decided in-stage 4 records that the two cannot be told apart.
- The clear needs the retry item's entry; `Entries` validates every runner (BH, EC x2) — carried EC-1/EC-2, wontfix-theoretical (the production installs all six).
- Neither Merge nor the Provider step checks `supported` (BH) — by-design (carried BH-4): `CheckModel` is the supported gate.
- Three tests hold the process's key variable values in `..Env` to put them back (BH) — wontfix-theoretical: the values stay in the test process's memory and no assertion, log or store receives them; real if an assertion text or a global held `..Env`.
- Bedrock Claude profiles get no effort (BH) — by-design, Decided in-stage 9.
- Resolution on an empty or missing entry gives a config without `http_config` (EC) — wontfix-theoretical: every product runner has an installed `@{config:}` entry; real if a runner item had an empty ProviderConfig while Anthropic's key is set (it would then run on AI Hub's default timeouts, still bounded by Decide's timer).
- The entry's own provider is skipped even when its own variable is set under another placeholder (EC) — by-design, Decided in-stage 4 (Merge refuses such an entry and the Provider step rewrites it).
- No lock around `SetModel` (EC) — carried BH-8.
- The second-model rollback's second restart is unpinned (VG, BH) — low, not a two-way door: a job snapshot cannot tell one restart from two; wontfix-accepted, reopen_if=a failed second-model SetModel leaves TriageAgentRetry answering on the refused model.
- `TestGetShape` rewrote its class-doc bullet and leaves a `^OcuTalonTest("SettingsApi","plant")` counter (AA) — the bullet documents `TestGetShape` alone (inside the IG-2 exception); the counter is a test-global uniqueness counter that test-boundaries allows; negligible.
- The Spec Change Log says `deferred` is empty and the footprint note says `SettingsApi` is not edited (AA) — the fix edits the spec under review; noted for the lead.
## Spec Change Log

- 2026-11-05 lead (after code review): the frontmatter `deferred:` entries were harvested into the ledger (DW-757 and DW-758 routed to 17.4; the live key-env gap is an occurrence on DW-755), so any earlier line here saying `deferred` is empty is superseded. `Test/Web/SettingsApi.cls` (Lane B) IS edited, inside `TestGetShape` and its `KeyShape` helper only, under the Contest Planner's one-time U-177 exception (IG-2); this supersedes any footprint note saying it is not edited.

- 2026-11-05 implement (re-dispatch): the queued patches, the IG-1 pin test and the IG-2 edit of `Test.Web.SettingsApi.TestGetShape` are applied; `deferred` is empty (its three entries are settled: IG-2 and IG-1 by the rulings, the Sonnet price by the patch).
- 2026-11-05 lead: IG-2 ruled (one-time U-177 exception) and U-288 kept; attempt-1 patch re-applied; status in-review (re-dispatch protocol, review-step patch path).

- 2026-11-05 lead: IG-1 ruled (option B, veto U-288); IG-2 sent to the orchestrator.

Footprint (Rule 11). No existing file outside Epic 17's footprint was edited, and no contended path. New files: `Bridge/Providers.cls`, `Test/Bridge/Providers.cls`, `Test/Bridge/ModelChange.cls`, `Test/Bridge/UnclassifiedStop.cls`, `Test/Bridge/ZzProviders.cls`, `Test/Bridge/ZzProviderAdapter.cls`, `Test/Bridge/ZzProviderRunner.cls` and `ci/mock/scenarios/A/unclassified-stop.json`. Edited existing files: the bridge classes the spec names (`Settings`, `ConfigStore` (also a new `Restore`), `Keys`, `Adapter.Agent`, `Process.Decide`, `Timeouts`, `Installer`), `Install/Step/Provider.cls`, and the tests the spec names (`Test/Agent/RunnerFixture`, `Test/Bridge/{ConfigStore,SessionConfig,Fallback,Keys,SettingsStubs,Usage}`, `Test/Install/Provider`). `Test/Bridge/Decide.cls` and `Test/Install/Production.cls` were not touched.
- `Test/Web/SettingsApi.cls` (Lane B) asserts the 33.1 stub shape and is not edited (U-177): it fails until Lane B changes it (frontmatter `deferred`).
- The `Conclude` rows of the unclassified stop are in a new class, `Test.Bridge.UnclassifiedStop`, not `Test/Bridge/Decide.cls` (Epic 40 changes it).
- `Test.Bridge.ModelChange` has its own small helpers (`Prepare`, `Ask`, `Arm`, `Remember`) instead of extending `Test.Bridge.SecondModel`: those helpers are private instance methods of a class whose tests would run again in a subclass.
- `Resolve` has two more optional trailing arguments, `agentClass` and `configured`, which the adapter passes (its own `AgentClass` and `Model`), because a shadow runner is no item of the production; with none, `Resolve` reads them from the item. It returns the provider's name, or "".
- Task 0 (c): prices follow the pages where they differ from the spec (Design Notes).

## Review Triage Log

### 2026-11-05 — Review pass
- verdicts: 41 findings — high 2, medium 7, low 30, false 2, maybe-false 0 (IG-1 and IG-2 group rows VG-1, VG-2, VG-5a, VG-5b, VG-7, IA-1 and IA-2; they are not extra findings)
- routing: one `intent_gap` entry (rows IG-1 and IG-2) decides the pass; every other entry is moot until the contract is settled and is recorded with the route it would take (`patch` unless noted). The attempted change is saved in `_bmad-output/implementation-artifacts/spec-17-3-attempt-1.patch` and the code tree is reverted to `baseline_revision`.
- intent gaps (root cause inside `<intent-contract>`):
  - IG-1 `[high]` `[intent_gap]` The matrix row "Resolved (live)" and the AC "live on the Anthropic path ... its decisions answer normally" cannot be verified at the runner-job surface. A runner job reads its key from the instance's own environment, and a variable that a test sets is set in the test process only (Task 0 measurement: a restarted job does not see it). `ci/compose.ci.yml` sets no model key by design, so in every throwaway no supported provider has its key set where `Decide` and the runner jobs read it. The built code resolves in process (`TestResolvedLive`: `Keys.Absent`, `Providers.Resolve`; `TestResolvedShadowRunner`: the built agent), but nothing sends a decide through a resolved runner or runs `RecordKey` in a job (`Keys.Status` 1 for a resolved runner is checked by the test calling `Keys.Record` itself). The only way to observe it is a throwaway whose compose file sets a dummy `ANTHROPIC_API_KEY`, which needs a new live unit (a `docker/tests` script, a compose override and a one-name append of the unit in the contended `ci/units.sh`) and the contract's "Never" lists `ci/units.sh`. The matrix test audit therefore cannot be satisfied inside the contract.
  - IG-2 `[medium]` `[intent_gap]` `Test.Web.SettingsApi.TestGetShape` (Lane B, line 146) asserts the 33.1 stub shape (`json.providers` unassigned, "the stub's providers are empty") and scans the body for `api_key`, which now matches the `ANTHROPIC_API_KEY`-style `keyVariable` field the contract requires of every `Providers()` row. It goes red as soon as `Settings.Providers()` is built, and the contract forbids editing a Lane B test (U-177). The spec's shared-surfaces list missed `Test.Web.SettingsApi`.
- findings (one row per finding, in the order the layers reported them):
  - Blind Hunter
    - `[medium]` `[patch]` BH-1 the two Sonnet 5.5 cache-read prices differ (direct row 0.2, `us.anthropic.claude-sonnet-5-5` 0.1) — real (Installer.Prices; `Usage` pins 0.2); the pricing page of 2026-11-05 says 0.10, so fix: both rows 0.1 and the `Usage` pin, as Task 0 (c) says the page's value wins.
    - `[low]` `[reject]` BH-2 `ConfigStore.Restore` writes back whatever `Details` gave without the Merge shapes — Restore is the rollback of an entry Merge or the installer wrote, entries hold placeholders only (AD-19), and any caller can already call `Modify` directly; a guard adds branches for no reachable harm. Its missing test is VG-3.
    - `[low]` `[reject]` BH-3 `Merge(missing, {})` is OK before the existence check — the contract says an empty object merges nothing and is OK; only the method comment ("the entry does not exist") should say it applies to non-empty fields.
    - `[low]` `[reject]` BH-4 the model shape does not check `supported` — by design (contract: `model_provider` is "a provider of the table"; `CheckModel` is the supported gate), `by-design`.
    - `[low]` `[reject]` BH-5 `SetModel` clear path has no rollback — the only failure is a more specific `RetryItem` row overriding the read-back, and the leftover is an empty system default row; `wontfix-theoretical`.
    - `[low]` `[patch]` BH-6 rollback statuses are swallowed — real (`Settings.cls` lines 148-151): a failed undo leaves a half state with no signal; append the rollback statuses to the returned status.
    - `[medium]` `[patch]` BH-7 the failure and rollback path of `SetModel` and `Restore` have no test — real: the whole `If $$$ISERR(sc)` block can be deleted with every test green (confirmed by VG-3); add `ModelChange.TestSetModelFailureRestores` (a more specific `Model` row makes `WriteRow` fail after the Merge) and `ConfigStore.TestRestore`.
    - `[low]` `[reject]` BH-8 `SetModel` is not serialized — one admin at a time on a settings page; `wontfix-theoretical`.
    - `[low]` `[reject]` BH-9 Classify rule 6 maps `length`, `MAX_TOKENS` and `tool_calls` to `unusable` — spec-bound (matrix row: `length` is `unusable`; the allow-list is the contract's four names), all of them are fallbacks and none is an answer; the per-provider mapping is for REL-7 when a `supported` flag flips. `by-design`.
    - `[low]` `[reject]` BH-10 a resolved runner's model is invisible to `ResolveModel` — Decided in-stage 10 (Lane B's choice), `by-design`.
  - Edge Case Hunter
    - `[low]` `[reject]` EC-1 clearing the second model fails when the retry item has no entry — the retry items are installed with the production; `wontfix-theoretical`.
    - `[low]` `[reject]` EC-2 `Entries` validates every runner through `Timeouts.Entries` — the production's six items always carry entries; `wontfix-theoretical`.
    - `[low]` `[reject]` EC-3 `old` is populated when the clear-path write fails — same unlikely failure as BH-5; `wontfix-theoretical`.
    - `[low]` `[reject]` EC-4 no lock around `SetModel` — as BH-8.
    - `[low]` `[patch]` EC-5 rollback statuses swallowed — same root cause as BH-6.
    - `[low]` `[reject]` EC-6 the `refusal` and `max_tokens` comparisons are case-sensitive while `FINISHED` is not — both outcomes are fallbacks (`cut_off` against `unusable` is a label); Anthropic is the only supported provider and its values are lower case. `wontfix-accepted` `reopen_if=a provider with upper-case finish reasons is flagged supported`.
    - `[low]` `[reject]` EC-7 `tool_calls` and `function_call` are not in `FINISHED` — as BH-9, REL-7.
    - `[false]` `[reject]` EC-8 any numeric `retry` key is merged — the contract says "an object of numbers"; a number cannot carry `@{`.
    - `[low]` `[reject]` EC-9 `Keys.Absent` calls `Resolve` for an item whose `ProviderName` is set — no product item sets `ProviderName`; `wontfix-theoretical`.
    - `[low]` `[reject]` EC-10 `BuildAgent` leaves the resolved config in the adapter when `OnInit` fails — a failed build is retried from the same adapter state, where the resolution reads the same key again; no observable difference.
    - `[low]` `[reject]` EC-11 the Provider step's `base_url` and CA overrides reach a kept non-Anthropic entry — Decided in-stage 5: only CI and the online demo set them and both are Anthropic-only.
    - `[medium]` `[patch]` EC-12 the Sonnet price rows differ — same root cause as BH-1.
  - Verification Gap
    - `[high]` `[intent_gap]` VG-1 `RecordKey`'s resolved branch has no executing test — same root cause as IG-1 (`Keys.Status` for a resolved job runner).
    - `[high]` `[intent_gap]` VG-2 AC4's live half is not verified by any test — IG-1.
    - `[medium]` `[patch]` VG-3 `SetModel` rollback and `ConfigStore.Restore` unpinned — as BH-7.
    - `[low]` `[patch]` VG-4 mutation lines missing for AC4's adapter half (`BuildAgent` not applying the resolved config -> `TestResolvedShadowRunner`) and AC2's Model-row write (`SetModel` not writing the Model row -> `TestSetModelNextRequest`) — write both lines (Rule 19) in the re-derivation.
    - `[medium]` `[intent_gap]` VG-5a the decide halves of `TestAdminModelNeverResolves` and `TestNoSupportedKey` pass on release-1 behaviour (the Decide job has no key anyway) — IG-1; only the `Keys.Absent` halves observe the rule.
    - `[low]` `[intent_gap]` VG-5b `TestNoKeyValueAnywhere` holds its fake key in the test process only, so its scans after the turn cannot see a job-side leak — IG-1.
    - `[low]` `[patch]` VG-5c `TestResolvedShadowRunner`'s "nothing was sent" holds with no request path run — the story's Task 0 (b) measured the send path; word the assertion as the build only and drop the claim.
    - `[low]` `[patch]` VG-5d the `ProviderName` guard of `Resolved` is never executed by a test — one case on `ZzProviderAdapter` with `ProviderName` set.
    - `[low]` `[patch]` VG-6a `Keys.TestAbsentResolves` relies on the `Model` row being the default — set the row at the start of the test.
    - `[low]` `[patch]` VG-6b `Providers.TestTable` relies on seeded Price rows and its doc claims a family cap-key check the code lacks — correct the doc and keep the seed check as the `Installer.SeedPrices` precondition (call it first).
    - `[low]` `[patch]` VG-6c `Install.Provider.TestKeepsChosenProvider` restores by running the step and so depends on the entry state found — record the entry's details first and restore them through `ConfigStore.Restore`.
    - `[medium]` `[intent_gap]` VG-7 `Test.Web.SettingsApi.TestGetShape` goes red — IG-2.
    - `[low]` `[patch]` VG-8 the Sonnet cache-read deferral — BH-1.
  - Intent Alignment
    - `[medium]` `[intent_gap]` IA-1 resolution on the real table in a runner job is not driven end to end — IG-1.
    - `[low]` `[intent_gap]` IA-2 "request built for that provider" is checked as the built agent on `ZzProviders`, never as a request — IG-1 (a request for another provider needs network, so the built agent is the strongest in-process proof).
    - `[low]` `[patch]` IA-3 after `SetModel` the live tests overwrite the key with `PointKeys` (the CI mock variable) — needed so the mock can answer; the final check of the entry `SetModel` wrote is `TestSetModelNextRequest`'s read of the entry before `PointKeys`. Make that read explicit in `TestSecondModel` too.
    - `[low]` `[reject]` IA-4 "the API's answer" is checked at the `SetModel` status and `old`, not through REST — the settings routes are Lane B's (`Web/Api.cls` is contended); `by-design`.
    - `[low]` `[reject]` IA-5 the Lane B integration AC runs `SettingsOps.Values()` in process rather than through REST — `Values()` is what the spec names; `by-design`.
    - `[false]` `[reject]` IA-6 other choices (`Keys.Absent` reads the key in Decide's process; the Bedrock price; booleans) — all recorded under Decided in-stage; the key variable is read in the same instance environment for Decide and the jobs (Task 0 measurement), so no divergence.

### 2026-11-05 — Review pass (re-dispatch)
- verdicts: 45 findings — high 0, medium 3, low 37, false 3, maybe-false 2
- routing: no intent_gap and no bad_spec (the IG-1 and IG-2 rulings settle the contract); patches applied in-pass; three defers (frontmatter `deferred:`). Rows of the first pass that came back unchanged are `carried`.
- findings:
  - Blind Hunter
    - `[low]` `[patch]` Restore's doc says it accepts only what Details gave and the class doc calls Merge the one writer — the claims were wrong; reworded in `ConfigStore` (the unguarded write itself is carried reject BH-2: entries hold placeholders only).
    - `[low]` `[reject]` carried BH-3 `Merge` of an empty object is OK before the entry is read — the contract says an empty object is OK; the Merge doc now says so.
    - `[low]` `[reject]` carried EC-10 `BuildAgent` leaves the resolved config in the adapter when `OnInit` fails — a retry reads the same key again.
    - `[low]` `[patch]` the rollback of `SetModel` restarts the item although it was never restarted — real (a refused change bounced the job); restart only when attempted; `TestSetModelFailureRestores` now asserts the jobs are unchanged.
    - `[low]` `[reject]` carried BH-8 no lock around `SetModel`, and no audit event there — one admin at a time; the settings route audits (Lane B, `SettingsOps`).
    - `[low]` `[defer]` the Sonnet 0.2 to 0.1 seed correction misses instances that hold the row, and the prices of unsupported providers are dated figures — the first is a stored-data change (deferred, low); the second is Task 0 (c)'s documented source.
    - `[low]` `[reject]` carried BH-9 the `FINISHED` list is Anthropic-shaped and `refusal`/`max_tokens` are exact matches — by-design until REL-7 flags a provider supported.
    - `[maybe-false]` `[defer]` a resolved or chosen provider keeps the entry's `base_url`, headers and TLS — cannot happen today (Anthropic only supported; `base_url` set by CI and the online demo only); deferred as medium (unverified) for REL-7.
    - `[low]` `[reject]` `Providers.Rows` re-parses the XData on every call — a small compiled table; a failure needs an uncompiled class.
    - `[low]` `[reject]` Bedrock Claude profiles get no effort — contract: effort for `claude-*` ids; Decided in-stage 9.
    - `[low]` `[reject]` `KeyShape` flags any `sk-` substring — the IG-2 ruling names the `sk-` prefix; the old scan had it too.
  - Edge Case Hunter
    - `[low]` `[reject]` no Try/Catch in `SetModel` — the calls return statuses; an exception needs a fault of the Config Store or the table (`wontfix-theoretical`).
    - `[low]` `[patch]` needless restart in the rollback — same root cause as the second Blind Hunter patch.
    - `[low]` `[reject]` carried BH-8 no lock.
    - `[low]` `[reject]` carried EC-1 clearing needs the retry item's entry.
    - `[low]` `[reject]` carried BH-3 `Merge("missing", {})` is OK.
    - `[low]` `[reject]` the timeouts shape takes any number (negative, fractional) — the contract says "a number"; `Timeouts.Apply` bounds its own values.
    - `[maybe-false]` `[defer]` endpoint fields kept across a provider change — same entry as the Blind Hunter row.
    - `[low]` `[reject]` carried EC-10 resolved config kept after a failed build.
    - `[low]` `[reject]` carried BH-9/EC-7 normal-end names of other providers.
    - `[low]` `[defer]` an installed Sonnet row keeps 0.2 — same entry as the Blind Hunter row.
    - `[low]` `[reject]` `KeepChosen` keeps an unsupported table provider — the contract keeps "a table provider and exactly its own placeholder"; `CheckModel` is the supported gate.
    - `[low]` `[reject]` `MergeInto`'s null branch is dead code — the spec leaves `MergeInto` unchanged; deleting it is not this story's task.
    - `[low]` `[patch]` the Merge doc claimed that no caller can pair a key placeholder with an endpoint — reworded to the fields a caller passes (the entry's other fields stay).
    - `[false]` `[reject]` the new price rows differ from the Tasks text — Task 0 (c) says the page's value wins and the Design Notes record each difference.
    - `[low]` `[reject]` carried BH-5/EC-3 the clear path has no rollback and `old` stays set.
  - Verification Gap
    - `[medium]` `[patch]` `RecordKey`'s resolved branch had no test that executes it — real; `ZzProviderAdapter` gets `ForceJob` and `Providers.TestRecordKeyResolved` runs `OnInit` and reads `Keys.Status` (0, then 1); mutation line written.
    - `[low]` `[patch]` `TestNoKeyValueAnywhere`'s doc overclaimed the turn leg — it now says what the scans prove (nothing holds what the test process holds; a job holds no key in a throwaway).
    - `[medium]` `[defer]` live resolution and a job-side key scan have no test with a key in a job's environment — the IG-1 ruling (option B) accepts the in-process proof; deferred for the Release check.
    - `[low]` `[reject]` carried VG-5a the fallback halves of `TestAdminModelNeverResolves` and `TestNoSupportedKey` pass on release-1 behaviour — the `Absent` halves are the binding ones (IG-1 ruled).
    - `[low]` `[reject]` the retry-item pass of the shadow loop repeats the first — `TestResolvedLive` covers the retry item `TriageAgentRetry` live; the loop name is cosmetic.
    - `[low]` `[patch]` the price rows of the unsupported providers were compared with `Installer.Prices()` itself — independent pins of the four rows added to `TestSeedPrices`; mutation line written.
    - `[low]` `[defer]` the Sonnet seed misses installed rows — same entry as the Blind Hunter row.
    - `[low]` `[reject]` `TestTable` leaves the Price rows that `SeedPrices` created — they are the install's own seed rows.
    - `[low]` `[reject]` `Install.Provider.TestKeepsChosenProvider` and `Keys.TestAbsentResolves` assume the installed entry and an active production — they fail loudly with the reason, as the sibling tests do.
    - `[low]` `[reject]` `TestGetShape` checks a configured key value only when the variable is set — the ruling says "if one is set"; the planted `configured` shape exercises the scan.
    - `[low]` `[reject]` the rewritten ConfigStore tests no longer cover null removal and array replace — `Merge` refuses them (spec); `TestModelChangeShape` covers the refusals.
  - Intent Alignment
    - `[medium]` `[defer]` the matrix row "Resolved (live)" is met in process, not in a job — IG-1 ruled; same entry as the Verification Gap row.
    - `[low]` `[reject]` the decide after `SetModel` is served by an entry that `PointKeys` rewrote — the entry `SetModel` wrote is asserted before `PointKeys` in `TestSetModelNextRequest` and `TestSecondModel` (carried IA-3).
    - `[low]` `[reject]` no test checks the model recorded for a resolved runner — only Anthropic's default can be resolved to today, which equals the default.
    - `[low]` `[reject]` carried BH-5 a failed clear is not rolled back.
    - `[low]` `[reject]` the Provider step's keep is tested for OpenAI only — the code path is the table lookup for any row.
    - `[false]` `[reject]` the Lane B test edit and the Sonnet price are outside the contract text — IG-2 ruled the one edit and Task 0 (c) authorizes the price.
    - `[low]` `[reject]` half-empty second models are refused where the contract is silent — recorded as Decided in-stage 22.
    - `[false]` `[reject]` the new test classes are not registered in `ci/units.sh` — they are in the `Bridge` area that the shards run by area; `test-ci-config.sh` passes.

## Design Notes

**IG-2 ruled by the Contest Planner (owner's delegation, 2026-11-05 ~17:2xZ): a one-time U-177 exception for `Test.Web.SettingsApi.TestGetShape` only.** Conditions: (1) the providers assertion checks the built shape only (non-empty; each row has the built fields), never a row count or a price; (2) the secret scan targets key VALUES and must still fail on each of these planted in the body: an Anthropic-shaped key (`sk-ant-` prefix), an OpenAI-shaped key (`sk-` prefix), a Google-shaped key (`AIza` prefix), and the literal value of any key configured in the test instance if one is set; `keyVariable` names such as `ANTHROPIC_API_KEY` are allowed; each planted shape gets a demonstrated mutation (red), and the planted keys are built at run time (concatenation) so no key-shaped literal sits in the committed file; (3) the test carries a comment marking the U-177 exception and citing this ruling (Contest Planner, 2026-11-05); no other Lane B file changes -- a second Lane B edit is `## Clarification Needed`.
**U-288 (IG-1) KEEP, with a condition:** while only Anthropic is marked supported, no public text (README, bridge guide, settings page, release notes, the bridge's own reason texts) may say another provider runs decisions; check every text this story adds (ledger DW-755 holds the condition for later stories).

**Lead ruling IG-1 (2026-11-05, runner A, veto U-288).** Option B: the "Resolved (live)" row and the resolution AC are met by the in-process proof (`Providers.Resolve`, `Keys.Status`/`Keys.Absent`) plus the shadow-runner proof that the built agent uses the resolved provider; "decisions run normally" is carried by the existing live Anthropic-path tests, since resolution yields the same session config as a direct choice of that provider (pin that equality in process). No new CI unit and no dummy key. IG-2 (the Lane B test `Test.Web.SettingsApi.TestGetShape`) is with the orchestrator (U-177, cross-lane).

**Governing ADs (Rule 6).** No AC contradicts an AD's Rule.
- AD-2: the bridge names no OcuTalon package.
- AD-5: no storage change; the timer stays at or under 110 s.
- AD-6: only runners call Chat.
- AD-7: the provider table, the resolution rule, families, no sampling, and that an entry never holds a model.
- AD-8: reasons; resolution before `no_key`; `unusable` for what cannot be told apart; the retry items.
- AD-19: placeholders only; Merge is the one run-time writer; `Bridge.Settings`; seed values.
- AD-20: prices.
- AD-22: the mock and throwaway stacks.
- AD-29: lanes.

**Ledger (Rule 17).** DW-52 is addressed by the Merge-shapes matrix row, the DW-52 AC and the `ConfigStore` task. The general shape is gone: Merge itself now refuses a `base_url`, a header, `secret://`, a foreign variable and any other `@{`, so no caller can pair a key placeholder with an endpoint.

**Measured on slot A (read-only, `%AI.Provider.%GetProviders()`, build 154, 2026-11-05):**

| Provider | AI Hub's own key variable | Default model | Notes |
| --- | --- | --- | --- |
| `openai` | `OPENAI_API_KEY` | `gpt-5.4` | |
| `gemini` | `GOOGLE_API_KEY` | `gemini-3.1-pro-preview` | The default base URL is the OpenAI-compatible endpoint |
| `bedrock` | `api_key` = bearer token, `AWS_BEARER_TOKEN_BEDROCK` | `us.anthropic.claude-sonnet-5` | `region` is optional and defaults to `AWS_REGION` |
| `anthropic` | `ANTHROPIC_API_KEY` | | |

- The spine's `GEMINI_API_KEY` works unchanged, because the entry passes `api_key` explicitly. The lead may clear AD-7's "(inference; Story 17.3 confirms each)" marker (Rule 20). No AD changes.
- The new model ids and prices come from the official pricing pages (looked up 2026-11-05, labelled as such): `developers.openai.com/api/docs/pricing`, `ai.google.dev/gemini-api/docs/pricing`, and Anthropic's model pages for the Bedrock rows. Task 0 (c) re-confirms them.

**Task 0, measured on the warm throwaway (tag `e17s3iw`, build 154, 2026-11-05).**
- (a) The mock reply with `stopReason` `pause_turn` and text (scenario `unclassified-stop`) reaches the runner's `Reply` with `FinishReason` `pause_turn` and the text, so AI Hub passes the stop reason through unchanged (`ModelChange.TestUnclassifiedStopLive` asserts it). Decide then falls back with `unusable`, and the answer holds no text.
- (b) A shadow agent built with `model_provider` `openai`, a fake key from `KeyScan.SetEnv` and the mock's base URL is built, its session config is composed, and the mock's log is unchanged: nothing is sent (`Providers.TestResolvedShadowRunner` asserts it).
- (c) Prices, from the providers' own pages, looked up 2026-11-05: OpenAI `developers.openai.com/api/docs/pricing`; Gemini `aistudio.google.com/docs/pricing` (the old `ai.google.dev/gemini-api/docs/pricing` redirects there); Anthropic `platform.claude.com/docs/en/about-claude/pricing`; Bedrock `aws.amazon.com/bedrock/pricing/` (it lists no per-token figures for these two models, so the Bedrock rows follow Anthropic's page).
  - `gpt-5.4-mini` 0.75 / 4.5 / 0.075: as planned.
  - `gpt-5.4` 2.5 / 15 / 0.25, **and a long tier above 272,000 tokens: 5 / 22.5** (cached 0.50, which is the input scale that `Price.Cost` applies): the page differs from the plan, so the row has the tier.
  - `gemini-3.1-flash-lite` **0.25 / 1.5 / 0.025** (text; the plan had .125 / .5 / .0125): the page's value.
  - `gemini-3.1-pro-preview` 2 / 12 / 0.2, **and a long tier above 200,000 tokens: 4 / 18** (cached 0.40): the page's value.
  - Claude Haiku 5.5 0.10 / 0.50 / 0.01 / 0.125 with the tier above 100,000 at 0.50 / 2.50: as seeded. Claude Sonnet 5.5 2 / 10 / 2.50 as seeded, but its cache-read rate is **0.10** on the page (0.2 in the seeded row; frontmatter `deferred`); the new Bedrock Sonnet row has 0.1.
  - All eight model ids appear on the pages (the two Bedrock ids are the inference-profile names of the Claude models).
- Also measured: a restarted runner job does not see an environment variable that the test process set (`Keys.Status` stayed absent for an entry that named it), so a variable that a test sets reaches no runner job and not Decide.

**Decided in-stage.**
1. `agent` is the first runner item (`TriageAgent`, `DiagnosisAgent`, `ChatAgent`), as `Keys.Status(agent)` and `Decide.#RUNNERS` name it. The settings page maps its own labels.
2. Merge keeps `(entry, fields)`, because `Test/Contract/Ac.cls` pins it and Epic 34 changes that file. The strictness comes from the shape of the fields. `RunnerFixture` writes its test placeholders directly (a fixture write, not a copy of Merge: Merge refuses them on purpose).
3. The model shape's `model` is validated and never written (AD-7). The runner's `Model` row carries the model.
4. Resolution skips the entry's own provider (the one with no key). Otherwise, in a stack where `ANTHROPIC_API_KEY` is set, every "key absent" test would resolve. "Default" means the resolved `Model` equals the agent's `MODEL`. An admin who explicitly picked that same model cannot be told apart and may resolve.
5. The resolved config keeps `base_url` and `http_config` from the entry. `OCUTALON_MODEL_BASE_URL` is set only by CI and the online demo, both Anthropic-only (AD-19).
6. The Provider step keeps a chosen provider, so that a `SetModel` provider survives a start (AD-19 seed values). Story 17.4's restart AC covers the remaining values.
7. The unknown-finish rule follows AD-8 ("cannot tell apart → unusable"). `stop` is included for providers that report it (inference: no other provider is reachable without network). A provider that reports no finish reason (OpenAI, S2) keeps rule 5: blank text is `unusable`, text is judged by the JSON check or the guard.
8. `second` 1 is built here, so that model changes cover the retry runners (17.2's Consumed-by, the dispatch note). `Values()` stays with 17.4.
9. Each provider's default is its cheap tier (AD-7: "a silent fall back to an expensive default model"). The Bedrock `us.` inference profiles match AI Hub's naming. Bedrock models fall to the `default` family, so they get `max_tokens` and no effort until a story tests their field.
10. `ResolveModel` stays the configured model (Web/Api's state shows it). Showing the resolved model is Lane B's choice.
11. `Restart` gains `decide`, so that `SetModel` restarts only the affected items (AD-19).
12. `SetModel` writes in this order: Merge, the Model row (read back), the item's restart, then the RetryItem row (second model). A failure after the first write puts back the entry (`ConfigStore.Restore`, which writes the details that `Details` read: Merge cannot, because the old pair may not be a valid shape), the rows, and restarts the item again. An empty second model writes the RetryItem row "" and restarts nothing: Decide reads RetryItem live.
13. `Merge` of an empty object returns OK before it reads the entry; a refusal names a field only by a plain name (letters, digits, underscores, dots), so that a value placed in a field name is never echoed.
14. `Providers.Resolve` returns the provider's name; the adapter does not resolve for a runner whose `ProviderName` setting names a provider (AI Hub gives that setting priority over `model_provider`).
15. The live tests set a fake key variable in the test process for `CheckModel` and then point the entry's key at the CI mock key variable again (`PointKeys`), because a runner job never sees the process's variable. `OnAfterOneTest` restores the pair of Anthropic through Merge's model shape, runs the Provider step, and puts the rows back as found.
16. The classification rule is rule 6 of `Classify` (rule 7 is `invalid`); `FINISHED` is a Decide parameter in lower case, compared with the reason lower-cased. `refusal` and `max_tokens` stay exact matches, as before.
17. `Test.Bridge.Keys` unsets every provider's key variable for each test and puts them back, so that its absent-key cases do not depend on a key in the environment.
18. IG-1 pin (lead ruling, option B): `Providers.TestResolvedEqualsDirect` builds a shadow runner that resolves (to OpenAI, and to Anthropic) and one that chose that provider directly (its key variable set, its model set) and requires the same provider, model, provider configuration and session config. The decide through the mock on a resolved provider is not built; no new CI unit, no dummy key.
19. `SetModel` returns the original error with the errors of any rollback step appended, so that a half-restored state is never silent.
20. The seeded Price row of `claude-sonnet-5-5` has cache read 0.1 (the pricing page of 2026-11-05), like the Bedrock Sonnet row; an instance that already holds the row keeps its own (seed values are never overwritten, AD-19).
21. U-288 check: the reason texts this story adds (`Settings.CheckModel`, `ConfigStore.Merge`, `Providers`) say only that a provider is not supported yet or its key is unset; no README, bridge guide, settings page or release note is touched, and no text claims that another provider runs decisions.
22. A second model with only one of provider and model empty is refused (only both empty clear it), because an empty model would write an invalid Model row; the contract lists the empty checks for a first model and the clear for both.
23. `SetModel`'s rollback restarts the item again only when its first restart was attempted; `ConfigStore.Restore` writes the object as it is (the shapes of Merge are not applied to it), and its doc and Merge's say so.

**For the lead (veto window, U-5).**
- The refusal texts are the bridge's status texts, like `Timeouts.Apply`'s. The settings page's wording is Lane B's.
- FR-39's "the README says so" and the provider variables in `.env.example` belong to the Release check, which flips a `supported` flag. A README line now would claim support that does not exist yet.

**Footprint (Rule 11).**
- Extensions, none contended: `Bridge/Providers.cls`, `Bridge/Settings.cls`, `Bridge/Installer.cls`, `Test/Agent/RunnerFixture.cls`, and the new `Test/Bridge` classes.
- Contended paths: none edited.
- Story 30.7: `Redact`, `KeyProof` and `KeyScan` are only called. A future change to `KeyProof.GlobalHits` would reach `TestNoKeyValueAnywhere`. The key-proof test needs no `Redact` change.

**Extend, don't copy (Rule 2).**
- `Settings` reuses `Merge`, `Accessor.WriteDefault`, `Timeouts.Restart`, `ResolveModel` and `Keys`.
- `Providers.Resolve` reuses `Keys.State` and `ConfigStore.Details`.
- The tests reuse `RunnerFixture`, `KeyScan.SetEnv`/`Find`, `KeyProof.GlobalHits`, the `ZzRetry*` shadow pattern and SecondModel's `RetryItem` cleanup.

**Consumes:**
- 33.1's stubs;
- 17.2's retry items, `RetryItem` and `Timeouts`;
- `Installer` families and prices.

**Consumed-by:**
- 17.4: `Values()` reports provider and model per agent, `SetPrice` edits these rows, and its checks reuse `CheckModel`.
- 18.x (Lane B): the Models section calls `Providers`/`CheckModel`/`SetModel` with the item names.
- Release check (REL-7): flips `supported` in the table.

**Integration ACs (Rule 1):** `SettingsOps.Values()` (Lane B) consumes `Settings.Providers()`, and the runners consume `Providers.Resolve` (`TestResolvedLive`).

## Verification

Every `ci/*.sh` call sets these on its command line:
- `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a"`
- `OCUTALON_TEST_WEB_PORT=52801`
- `OCUTALON_LOCK_OWNER='epic=17 stage=<stage>'`

The tags of the re-dispatch are `e17s3jw` (warm) and `e17s3j` (fresh), one call each, in the foreground, with `timeout: 600000`. Run `ci/warm.sh down` at the end, also after a failure. Slot A gets `iris_doc_load` compile checks only (`server`/`namespace` `OCUTALON` on every call).

**Commands:**
- (once) `OCUTALON_RUN_TAG=e17s3iw ci/warm.sh up`. Expected: a ready stack.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s3iw ci/iris.sh class <C>`, one per call. Expected: `CLASS <C> passed` for:
  - `OcuTalon.Test.Bridge.Providers`, `ModelChange`, `ConfigStore`, `SessionConfig`, `Fallback`, `UnclassifiedStop`, `Decide`, `Keys`, `Usage`, `SettingsStubs`, `Timeouts`, `SecondModel`, `CodeRules`, `Conversation`;
  - `OcuTalon.Test.Web.SettingsApi` (Lane B, edited once under IG-2);
  - `OcuTalon.Test.Install.Provider`;
  - `OcuTalon.Test.Agent.Decide` and `KeyScan`.
- (loop) `bash docker/tests/test-mock.sh`. Expected: pass.
- (once) `bash docker/tests/test-storage.sh`, `test-class-rules.sh`, `test-boundaries.sh`, `test-ci-config.sh` and `test-bridge-example.sh`, one per call. Expected: each passes.
- (once) Fresh: `OCUTALON_RUN_TAG=e17s3i ci/iris.sh live install-start`, then `live production`, then `shard lane-a@Bridge`, `@Agent` and `@Install`, one per call (`--part k/2` near 8 minutes), then `teardown`. Expected: all pass.

**Shared surfaces:**
- the Price rows (`Usage.TestSeedPrices`, the `SettingsStubs` snapshot);
- `GET /v1/settings` providers (`Test.Web.SettingsApi.TestGetShape`, now the built shape and a key-value scan);
- the entries' fields and the Merge contract (`Test.Bridge.ConfigStore`, `RunnerFixture`, `Install.Provider`);
- the `Settings` stub answers (`SettingsStubs`);
- `Classify`'s reasons (`Fallback`, `Decide`);
- the `Model`/`RetryItem` rows (`SettingsStubs` expects 0 `RetryItem` rows; `Install.Production`);
- the `ci/mock/scenarios/A` set (`scenarios.test.mjs`, `test-bridge-example.sh`).

Every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19), one per AC, each applied on the warm stack, red observed, reverted, the tree byte-identical after (`git status --short`, `git diff --stat` and `cmp` against the backup), and the class green again on the same stack:**
- mutation: `Compose` always uses `max_tokens` → `SessionConfig.TestEveryListedModel` red. Done: red on the four gpt-5 asserts (cap in `extra_params.max_completion_tokens`, and no other key), green after the revert.
- mutation: `SetModel` skips `Restart` → `ModelChange.TestSetModelNextRequest` red. Done: red on "TriageAgent was restarted" (the same job before and after), green after the revert.
- mutation: `old` gets the key's value → `TestNoKeyValueAnywhere` red. Done: red on "old holds no key" (and on the two `old` shape asserts of `TestSetModelNextRequest` and `TestSecondModel`), green after the revert.
- mutation: `Keys.Absent` ignores `Resolve` → `TestResolvedLive` red. Done: red for both items ("Absent is 0: the runner resolves to Anthropic"), green after the revert.
- mutation: `Choose` does not skip the entry's own provider → `TestNoSupportedKey` and `TestChoose` red. Done: `Providers.TestChoose` red on "the entry's own provider is skipped even when its variable is set", and `ModelChange.TestNoSupportedKey` red for all six items (Absent is 0 instead of 1), green after the revert.
- mutation: the `FINISHED` check dropped → `Fallback`/`Decide` unclassified rows red. Done: `Fallback.TestUnclassifiedStop` and `UnclassifiedStop.TestUnclassifiedStopFallsBack` red for every unclassified reason, green after the revert.
- mutation: the model shape allows `base_url` → `ConfigStore.TestModelChangeShape` red. Done: red from the `base_url` case on (it is written), green after the revert.
- mutation: `second` 1 does not write `RetryItem` → `ModelChange.TestSecondModel` red. Done: red on the RetryItem value, the second model's answer, the one request to each runner and `old.retryItem`, green after the revert.
- mutation: `Settings.Providers` returns `[]` → `Providers.TestIntegrationSettingsOps` red. Done: red on "it holds four rows" and "in table order, Anthropic first" (and `TestSettingsProviders`), green after the revert.
- mutation: the Provider step always writes anthropic → `Install.Provider.TestKeepsChosenProvider` red. Done: red on "the provider and its placeholder are kept" (the `KeepChosen` call removed), green after the revert.
- mutation: `BuildAgent` does not apply the resolved config → `Providers.TestResolvedShadowRunner` and `TestResolvedEqualsDirect` red. Done (re-dispatch, warm): the build fails on the unset entry variable in both, green after the revert.
- mutation: `SetModel` does not write the Model row → `ModelChange.TestSetModelNextRequest` red. Done: red on "the Model row is the new model", "Decision.Model is the new model" and "the mock saw one request, on the new model" (and `TestSecondModel`, `TestSetModelFailureRestores`), green after the revert.
- mutation: `SetModel` does not restore the entry after a failed write → `ModelChange.TestSetModelFailureRestores` red. Done: red on both "as they were" state asserts, green after the revert.
- mutation: `ConfigStore.Restore` writes nothing → `ConfigStore.TestRestore` red. Done: red on "byte-equal to what Details read", green after the revert.
- mutation: the `ProviderName` guard of `Resolved` removed → `Providers.TestResolvedShadowRunner` red. Done: red on "with a ProviderName setting the runner is not resolved", green after the revert.
- mutation: the Bedrock Sonnet row of `Installer.Prices` back to 0.2 → `Usage.TestSeedPrices` red. Done: red on "the Bedrock inference profile of Claude Sonnet 5.5 has the prices of the model itself" (the direct row is pinned at 0.1 by the existing assert), green after the revert.
- mutation (IG-2), one per planted shape, each applied to `KeyShape` in `Test.Web.SettingsApi`, green again after the revert: the `sk-ant-` rule removed → `TestGetShape` red on "a planted anthropic key is found in the body"; the `sk-` rule removed → red on "a planted openai key ..."; the `AIza` rule removed → red on "a planted google key ..."; the configured-value match made to never match → red on "a planted configured key ...".
- mutation: `Settings.Providers` returns `[]` → `Web.SettingsApi.TestGetShape` red too (the built shape asserts "the list is not empty"), as `Providers.TestIntegrationSettingsOps`.
- mutation: `RecordKey` records the entry's own configuration, ignoring `Resolved` → `Providers.TestRecordKeyResolved` red. Done: red on "once OpenAI's key is set the job records the resolved configuration: Status is 1", green after the revert.
- mutation: the rollback of `SetModel` restarts the item whether or not it was restarted → `ModelChange.TestSetModelFailureRestores` red. Done: red on "no item was restarted: the change failed before its restart", green after the revert.
- mutation: the `gpt-5.4` row of `Installer.Prices` with a long-tier output rate of 20 → `Usage.TestSeedPrices` red. Done: red on the independent pin of gpt-5.4 (the self-comparison to `Prices()` stays green), green after the revert.

**QA stage (Story 17.3, warm tags `e17s3qw`; each mutation applied on the warm stack, red observed, reverted byte-identical, `git status --short` and `git diff --stat` unchanged):**
- Test added (QA): `src/ocutalon/cls/OcuTalon/Test/Bridge/ModelChange.cls` `TestSetModelEveryAgent` (QA): the first model, second model and clear on `DiagnosisAgent` and `ChatAgent`, which no other test changed through `SetModel` (only `TriageAgent` was, and `ChatAgent` for a first model in `TestNoKeyValueAnywhere`).
- mutation: `SetModel` always changes the `TriageAgent` item (`item = "TriageAgent"_...`) -> `ModelChange.TestSetModelEveryAgent` red on "DiagnosisAgent: old holds the provider and the model...", "its entry holds the provider and the placeholder, and no model" and "its Model row is the new model" (the mutated run left the throwaway's `TriageAgent` rows changed, so the stack was recreated; green on the fresh stack).
- mutation: `Choose` ignores the key variable being set (AC "no supported key") -> `Providers.TestChoose` red on "with no key set, nothing resolves" and three more.
- mutation: `Choose` ignores `isDefault` (matrix "Admin model") -> `Providers.TestChoose` red on "an admin's model (not the default) never resolves" and `Providers.TestResolvedShadowRunner` red on the admin-model build.
- mutation: `Resolve` treats every model as the default -> `ModelChange.TestAdminModelNeverResolves` red on "Absent is 1: the model that an admin chose is never resolved away" and "Resolve names none".
- mutation: `Choose` ignores the key state (a present, unknown or missing state resolves) -> `Providers.TestChoose` red on "a present key never resolves", "an unknown key state never resolves" and "and neither does a missing state".
- mutation: `CheckModel` skips the key-variable-set refusal (matrix "Refused change", key variable unset) -> `Providers.TestCheckModelRefusals` red on "a supported provider whose key variable is not set is refused".
- mutation: `CheckModel` skips the `supported` refusal (matrix "Refused change", provider `openai`) -> `ModelChange.TestRefusedChangeKeepsEverything` red on "SetModel(TriageAgent, openai, gpt-5.4, 0) is refused", "the entries and the Model and RetryItem rows are as they were" and "no item was restarted" (stack recreated afterwards, green on the fresh stack).
- mutation: `SetModel` does not call `CheckModel` -> `Providers.TestCheckModelRefusals` red on "case 1 ...: old is empty" (the call fails before any write).
- mutation: `Provider.KeepChosen` keeps any placeholder (matrix "Step keeps provider", the second row) -> `Install.Provider.TestKeepsChosenProvider` red on "the pair is Anthropic and its placeholder" and "the entry is exactly the computed one".
- mutation: the model shape accepts any `api_key` (matrix "Merge shapes", another variable) -> `ConfigStore.TestMergeKeyNameCharacters` red on "the api_key of case 1 ... is refused" (and the `TestModelChangeShape` cases of `@{env:PATH}` and another provider's variable).
- mutation: the timeouts shape accepts any `http_config` field (matrix "Merge shapes", timeouts shape plus a field) -> `ConfigStore.TestMergeRefused` red on "case 2 is refused" (and the `TestModelChangeShape` timeouts cases).
- mutation: `Merge` writes the validated `model` into the entry (AD-7) -> `ConfigStore.TestModelChangeShape` red on "and never the model: the runner's Model setting carries it".
- mutation: `Classify` compares the finish reason without lower-casing (matrix "Unclassified stop", `STOP` stays usable) -> `Fallback.TestUnclassifiedStop` red on "the normal end STOP with a text stays usable" and the `End_Turn` and `TOOL_USE` rows.
- Checked green after the mutations on a fresh warm stack: `Test.Bridge.ModelChange`, `Test.Bridge.Providers`; `docker/tests/test-boundaries.sh` and `test-class-rules.sh` pass.

**Code review stage (Story 17.3, warm tag `e17s3cw`; each mutation applied on the warm stack, red observed, reverted byte-identical (`cmp` against the backup, `git diff --stat` unchanged), the class green again on the same stack):**
- mutation: `ConfigStore.FieldName` back to `^[A-Za-z0-9_.]{1,64}\z` (DW-52 AC, a refusal names the field and never holds a value) -> `ConfigStore.TestModelChangeShape` red on "and the reason does not echo its name" at depth 1, 2 and 3.
- mutation: `SetModel`'s clear path without its `PutBack` (Always: a failure after the first write puts back what was written) -> `ModelChange.TestSetModelFailureRestores` red on "and the RetryItem row is put back as it was".
- mutation (IG-2, again after the scan of the real body was moved onto `KeyShape(body, configuredValues)`): the configured-value match of `KeyShape` made to never match -> `Web.SettingsApi.TestGetShape` red on "a planted configured key is found in the body"; the same `KeyShape` path now scans the real body.
- Green after the reverts: `Test.Bridge.{ConfigStore,ModelChange,Providers,SettingsStubs}`, `Test.Web.SettingsApi`; `docker/tests/test-boundaries.sh` and `test-class-rules.sh` pass.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Story 17.3 is complete on the settled contract (IG-1 option B, IG-2 one-time U-177 exception, U-288 kept): the fixed provider table `Bridge.Providers` with prices; the two-shape `ConfigStore.Merge` (DW-52) and `Restore`; `Settings.Providers`/`CheckModel`/`SetModel` for a first and a second model; provider resolution before `no_key` in the adapter and in `Keys`; the `unusable` rule for stop reasons the bridge cannot classify; the Provider install step keeping a chosen provider; and the tests. This pass applied the queued patches (both Sonnet 5.5 cache-read prices 0.1 and their pins, `SetModel` appends rollback statuses, `ModelChange.TestSetModelFailureRestores` and `ConfigStore.TestRestore`, the missing mutation lines, the small test fixes), the IG-1 pin (`Providers.TestResolvedEqualsDirect`) and the IG-2 edit of `Test.Web.SettingsApi.TestGetShape`, then reviewed the diff from the baseline.

**Files changed** (all under `src/` and `ci/mock/`; none contended; no `module.xml`, no `src/ocutalon/csp`):
- Bridge: `Providers.cls` (new), `ConfigStore.cls` (two shapes, `Restore`), `Settings.cls` (`Providers`, `CheckModel`, `SetModel`), `Keys.cls` (`State` public, `Absent` resolves), `Adapter/Agent.cls` (resolution in `BuildAgent` and `RecordKey`, `ProvidersClass`), `Process/Decide.cls` (`Classify` rule 6, `FINISHED`), `Timeouts.cls` (`Restart` takes `decide`), `Installer.cls` (eight price rows).
- Install: `Install/Step/Provider.cls` keeps a chosen provider and its placeholder.
- CI mock: `ci/mock/scenarios/A/unclassified-stop.json`.
- Tests: new `Test/Bridge/{Providers,ModelChange,UnclassifiedStop,ZzProviders,ZzProviderAdapter,ZzProviderRunner}.cls`; changed `Test/Bridge/{ConfigStore,Fallback,Keys,SessionConfig,SettingsStubs,Usage}.cls`, `Test/Agent/RunnerFixture.cls`, `Test/Install/Provider.cls`, and Lane B's `Test/Web/SettingsApi.cls` (one edit under the IG-2 ruling: `TestGetShape` and a private `KeyShape`).

**Review.** 45 findings (high 0, medium 3, low 37, false 3, maybe-false 2). Patched: 1 medium (the unexecuted `RecordKey` resolved branch) and 4 low (the needless rollback restart, three doc claims, the price pins; counted as entries, one entry per root cause). Deferred (frontmatter): the installed Sonnet row (low), the entry's endpoint fields kept across a provider change (medium, unverified; reachable only after REL-7 flags a provider supported), and the missing job-side proof with a key in a job's environment (medium; IG-1 option B). Every rejected finding has its reason in the triage log.

**Follow-up review recommendation:** false. Patched entries by verdict: high 0, medium 1, low 4.

**Verification.** Warm throwaway `e17s3jw` (build 154 image, CI mock), one class per call, all passed: `Test.Bridge.{Providers,ModelChange,ConfigStore,SessionConfig,Fallback,UnclassifiedStop,Decide,Keys,Usage,SettingsStubs,Timeouts,SecondModel,CodeRules,Conversation}`, `Test.Install.Provider`, `Test.Agent.{Decide,KeyScan}` and `Test.Web.SettingsApi`; after the review patches the changed classes ran again (`Providers`, `ModelChange`, `Usage`, `ConfigStore`, `SettingsStubs`). `docker/tests/test-boundaries.sh` (planted key shapes are built at run time and trip nothing), `test-class-rules.sh`, `test-storage.sh`, `test-ci-config.sh` and `test-mock.sh` pass. Every mutation of `## Verification` was applied on the warm stack, shown red, reverted byte-identical (`git diff` hash unchanged) and the class green again. The `(once)` fresh runs (`live install-start`, `live production`, the lane-a shard pieces) were not repeated in this pass: they passed in the first pass and this pass changed tests, docs and the rollback restart only. The warm stack is torn down; lane A's lock folder is empty.

**Decisions.** U-288 check: no text this story adds claims that a provider other than Anthropic runs decisions (the reason texts say a provider "is not supported yet"; no README, guide, settings page or release note is touched). Decided in-stage 18 to 23 are under `## Design Notes`.

**Residual risks.** The two medium defers above. `SeedPrices` leaves an installed Sonnet row at 0.2. `Test.Web.SettingsApi` is Lane B's class: a second edit there needs a new ruling.

**Slot A.** The first pass loaded the patched classes into `ocutalon-slot-a` for compile checks; this pass loaded nothing into it (all runs were on the throwaway). Reload `src/bridge` and `src/ocutalon` from the tree before the next use of the slot.
