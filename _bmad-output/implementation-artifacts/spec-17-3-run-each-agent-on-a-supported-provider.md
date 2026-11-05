---
title: 'Story 17.3: Run each agent on a supported provider'
type: 'feature'
created: '2026-11-05'
status: 'blocked'
baseline_revision: 'cc12bd0ed1ec133415b5446bf653ef975105fc87'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-17-context.md'
warnings: ['oversized']
deferred:
  - 'Test.Web.SettingsApi.TestGetShape (Lane B, Story 33.2, U-177) goes red now that Settings.Providers is built: line 146 asserts the stub shape ("the stub providers are empty"), and its scan for the word api_key finds the key variable names that every row carries (ANTHROPIC_API_KEY lower-cased). Recommended edit by Lane B: assert four rows in table order, and scan the body with the key variable names removed.'
  - 'Resolved (live) through Decide cannot run in a throwaway: the runner jobs and the Decide job have no model key, and a variable that a test sets is set in the test process only (measured: a restarted job does not see it), so no supported provider can have its key set where Decide and the runner read it. TestResolvedLive proves Keys.Absent and Providers.Resolve live in the test process, and the shadow runner proves the adapter; a decide answering through the mock on a resolved provider needs a throwaway whose compose file sets a dummy ANTHROPIC_API_KEY (a new live unit, not ci/compose.ci.yml).'
  - 'The seeded Price row claude-sonnet-5-5 has a cache-read rate of 0.2; Anthropic pricing page of 2026-11-05 lists 0.10 (0.05x input), and the AWS page notes the same 50% cut from 2026-10-07. The new Bedrock Sonnet row carries 0.1; the existing row is not changed here (Test.Bridge.Usage pins it and an admin owns seeded prices).'
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

## Spec Change Log

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

## Design Notes

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

The tags are `e17s3iw` (warm) and `e17s3i` (fresh), one call each, in the foreground, with `timeout: 600000`. Run `ci/warm.sh down` at the end, also after a failure. Slot A gets `iris_doc_load` compile checks only (`server`/`namespace` `OCUTALON` on every call).

**Commands:**
- (once) `OCUTALON_RUN_TAG=e17s3iw ci/warm.sh up`. Expected: a ready stack.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s3iw ci/iris.sh class <C>`, one per call. Expected: `CLASS <C> passed` for:
  - `OcuTalon.Test.Bridge.Providers`, `ModelChange`, `ConfigStore`, `SessionConfig`, `Fallback`, `Decide`, `Keys`, `Usage`, `SettingsStubs`, `Timeouts`, `SecondModel`;
  - `OcuTalon.Test.Install.Provider`;
  - `OcuTalon.Test.Agent.Decide` and `KeyScan`.
- (loop) `bash docker/tests/test-mock.sh`. Expected: pass.
- (once) `bash docker/tests/test-storage.sh`, `test-class-rules.sh`, `test-boundaries.sh`, `test-ci-config.sh` and `test-bridge-example.sh`, one per call. Expected: each passes.
- (once) Fresh: `OCUTALON_RUN_TAG=e17s3i ci/iris.sh live install-start`, then `live production`, then `shard lane-a@Bridge`, `@Agent` and `@Install`, one per call (`--part k/2` near 8 minutes), then `teardown`. Expected: all pass.

**Shared surfaces:**
- the Price rows (`Usage.TestSeedPrices`, the `SettingsStubs` snapshot);
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

## Auto Run Result

Status: blocked
Blocking condition: intent gap

**What happened.** The implementation (the provider table, the two-shape Merge, `Settings.Providers`/`CheckModel`/`SetModel`, resolution in the runner and `Keys`, the `unusable` stop-reason rule, the Provider step, prices and the tests) was written and passed every class of `## Verification` on a warm and a fresh throwaway, with all ten planned mutations shown red (the lines above). The review then found two gaps inside the `<intent-contract>` that the contract cannot settle. The attempted change is saved in `_bmad-output/implementation-artifacts/spec-17-3-attempt-1.patch` (`git apply --check` passes on the baseline `cc12bd0ed1ec133415b5446bf653ef975105fc87`; it creates the 8 new files and edits 16 existing ones, all under `src/` and `ci/mock/`); the code tree is reverted to the baseline. The spec's task ticks, Design Notes (Task 0 measurements and sources) and mutation lines describe the patched state.

**Unresolved questions (the lead's amendment).**
1. IG-1: the matrix row "Resolved (live)" and its AC need a runner job whose environment holds a supported provider's key. No throwaway has one (`ci/compose.ci.yml` sets no model key; a variable set by a test is not seen by a restarted job, measured). Recommended amendment, option A (keeps the AC honest): allow a new live unit in the footprint: `docker/tests/test-provider-resolve.sh`, a small compose override that sets a dummy `ANTHROPIC_API_KEY` for that unit only, and a one-name append of the unit in `ci/units.sh` (an existing group other than `production`/`browser`/`install-*`), reported as a footprint extension, with `Test.Bridge.ModelChange.TestResolvedLive` moved into it so that a decide answers through the mock on `claude-haiku-5-5` and `Keys.Status` is 1 in the job. Option B: change the matrix row and the AC to the in-process proof that exists (`Keys.Absent` and `Providers.Resolve` live, `TestResolvedShadowRunner` for the built agent) and move the decide-through-the-mock proof to the Release check (REL-7); this weakens a stated guarantee, so it is a veto-window item.
2. IG-2: `Test.Web.SettingsApi.TestGetShape` (Lane B) fails once `Settings.Providers()` is built, whatever this story does (it asserts the stub's empty `providers` and scans for the text `api_key`, which every row's `keyVariable` holds). Recommended: the owner of U-177 lets this one assertion pair change with this story (assert four rows in table order, scan the body with the key variable names removed), logged as a footprint extension; or the lead sequences a Lane B edit before this story merges. Add `Test.Web.SettingsApi` to the spec's shared surfaces.

**Patches the re-derivation applies** (all but IG-1 and IG-2 are `patch` rows of the triage log): both Sonnet 5.5 cache-read prices 0.1 and the `Usage` pin (BH-1); `SetModel` appends rollback statuses (BH-6); `ModelChange.TestSetModelFailureRestores` and `ConfigStore.TestRestore` (BH-7); two missing mutation lines (VG-4); the small test hermeticity and wording fixes (VG-5c, 5d, 6a, 6b, 6c, IA-3).

**Deferred.** The frontmatter `deferred:` list still holds the implement pass's three entries; the first two are IG-2 and IG-1 above and the third is BH-1, so the lead should harvest none of them while the spec is `blocked`.

**Slot A.** The implement pass loaded the patched classes into `ocutalon-slot-a` for compile checks. The slot now holds classes that the reverted tree does not have (`OcuTalon.Bridge.Providers`, the `Test.Bridge.{Providers,ModelChange,UnclassifiedStop,ZzProviders,ZzProviderAdapter,ZzProviderRunner}` classes) and patched versions of the 16 edited ones; reload `src/bridge` and `src/ocutalon` from the tree before the next use of the slot.

**Residual state.** No throwaway stack is running (`e17s3iw` and `e17s3i` torn down), lane A's lock folder is empty, HEAD is unchanged, nothing was committed or pushed. The tree holds only this spec and the new patch file, both uncommitted (bookkeeping files for the lead).
