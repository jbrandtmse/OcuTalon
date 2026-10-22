---
title: 'Story 1.4: Every turn and decision carries its tokens and cost'
type: 'feature'
created: '2026-10-22'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-2, AD-3, AD-5, AD-6, AD-9, AD-18, AD-19, AD-20, AD-26, AD-31 and AD-33)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** No model call is counted today. The runner writes no `OcuTalon.Bridge.Data.Usage` row, `Price` is empty, and the token, cost, model, step and duration fields of the `Decision` row and of the decision and reply messages stay empty. `OcuTalon.Bridge.Budget.State()` is Epic 0's stub, `OcuTalon.Bridge.Time` has no day boundary, and nothing can mark a day as capped. So Visual Trace shows no cost, and nothing can enforce or report a daily cost cap.

**Approach:**
- **The runner's row.** After every `Chat` call, the runner's adapter writes one `Usage` row from the `GetStats()` delta it read before and after the call, priced from `Price`.
- **Prices.** `OcuTalon.Bridge.Installer` seeds the prices of Claude Haiku 5.5 and Claude Sonnet 5.5.
- **Totals.** `Decide` carries the decision's totals on its row and on its answer: the sums of the `Usage` rows of its `DecisionRef`, plus the step count and the duration.
- **The budget.** `Budget.State()` reports the day's spend, cap, capped flag and reset time. The day ends at local midnight, through `OcuTalon.Bridge.Time`.
- **The day's cap.** A new `Budget.MarkCapped` marks a day as capped once, under a lock, and fires `budget.capped` once. Story 1.6 calls it from its two `daily_cap` paths (Design Notes, decision 1).

## Boundaries & Constraints

**Always:**
- **The Usage row (AD-6, AD-9, AD-20).** Only the runner writes it, through its adapter (`OcuTalon.Bridge.Adapter.Agent.Answer`, the one place that calls `Chat`), never `Decide`.
  - **When.** The adapter reads `session.GetStats()` after it creates the session and again after `Chat`, outside every callback. It writes one row:
    - after every `Chat` that returns, whether or not `Decide` is still waiting;
    - after a `Chat` that throws, when the delta holds a model request or a token. A throw with a zero delta writes nothing.
  - **The fields:**
    - `DecisionRef`, `ItemId`, `Kind`, `OwnerRef` and `Channel` come from the request;
    - `Agent` is the runner item's config name;
    - `Model` is the built agent's model;
    - `RequestCount` is the delta of `total_interactions`;
    - `InputTokens` is the deltas of `total_prompt_tokens`, `total_cache_read_tokens` and `total_cache_creation_tokens` added together;
    - `OutputTokens`, `CacheReadTokens` and `CacheWriteTokens` are the deltas of `total_completion_tokens`, `total_cache_read_tokens` and `total_cache_creation_tokens`;
    - `LargestRequestTokens` is the last request's input from `Response.Usage` (its prompt, cache-read and cache-creation tokens), or "" when `Chat` threw;
    - `CostUSD` comes from `Price`, `Estimated` is 0, and `RecordedAt` is `Bridge.Time.NowUtc()`.
  - **Failures.** A save error, or a `GetStats()` that throws, is logged with `$$$LOGWARNING` and never changes the runner's answer or status.
- **The runner's Reply** carries the same counts and cost as its row, plus the `Model`. It also carries `AgentStepCount`, the delta of `total_interactions` plus the delta of `total_tool_calls`, and `DurationMs`, the wall time of `Chat` in whole milliseconds.
- **The cost (AD-20, FR-2).** `CostUSD` = (prompt × `InputPerMTok` + cache read × `CacheReadPerMTok` + cache write × `CacheWritePerMTok` + output × `OutputPerMTok`) / 1,000,000, rounded to 6 decimals.
  - **The long tier.** When `LongThresholdTokens` is set and the turn's largest request is above it, the whole turn is priced at the long tier:
    - input at `LongInputPerMTok` and output at `LongOutputPerMTok`;
    - each cache rate scaled by `LongInputPerMTok` / `InputPerMTok`.

    The largest request is `LargestRequestTokens`, or `InputTokens` ÷ `RequestCount` when that is "".
  - **No price.** A model with no `Price` row (exact `Model` match) has `CostUSD` "" (unknown, never 0), and the adapter logs one warning naming the model.
- **The seeds (AD-19, FR-2, FR-17).** `Installer.Run()` seeds two rows. Each is written only when no row has its `Model`, so an admin's edit survives every start.

  | Model | Input | Output | Cache read | Cache write | Long tier above | Long input | Long output |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | `claude-haiku-5-5` | 0.10 | 0.50 | 0.01 | 0.125 | 100,000 | 0.50 | 2.50 |
  | `claude-sonnet-5-5` | 2 | 10 | 0.20 | 2.50 | none | none | none |

  Prices are in US dollars per million tokens (decisions 2 and 3).
- **The totals (AD-20, AD-26).** `Conclude` puts these values on the `Decision` row and on its answer (a `DecisionResponse`, or the clone of the runner's `Reply` for a turn), under the names `InputTokens`, `OutputTokens`, `CacheReadTokens`, `CacheWriteTokens`, `CostUSD`, `Model`, `AgentStepCount` and `DurationMs`:
  - the four token sums and `CostUSD`, over the `Usage` rows of its `DecisionRef`;
  - `Model`, from the newest of those rows;
  - `AgentStepCount`, from the runner's `Reply`;
  - `DurationMs`, the whole milliseconds from the moment `Decide` began handling the request (its `%TimeCreated`) to `Conclude`.

  Edge cases:
  - with no rows, the token fields, `CostUSD` and `Model` stay "";
  - when any row's cost is "", the decision's `CostUSD` is "";
  - an answer built from a recorded row carries that row's totals.
- **The budget settings (AD-19, AD-20).**
  - **Declared on `Decide`.** `DailyCostCapUSD` (`%Numeric`, `InitialExpression` 0, meaning off), `GatewaySpendUSD` (`%Numeric`) and `GatewaySpendDate` (`%String(MAXLEN = 10)`, an instance-zone date) are host settings in `Decide`'s `SETTINGS`, in category `Bridge`.
  - **Read through the accessor.** They are read only through `OcuTalon.Bridge.Ext.Accessor.ValueFor`, from the active production's `Decide` item.
  - **Bad values.** A value that is not a number of 0 or more counts as 0.
- **`Budget.State(now = "")` (AD-20).** The arguments:
  - `now` is a UTC time, and "" means `NowUtc()`;
  - `day` = `Bridge.Time.LocalDate(now)`;
  - `from` = `DayStartUtc(day)`;
  - `to` = `DayEndUtc(day)`.

  It returns `{"spent", "cap", "capped", "resetsAt"}`:
  - **spent:** the sum of the `CostUSD` of the `Usage` rows with `RecordedAt` from `from` (inclusive) to `to` (exclusive) and `OwnerRef` other than `eval`. Rows whose cost is "" are skipped. `GatewaySpendUSD` is added when `GatewaySpendDate` = `day`.
  - **cap:** `DailyCostCapUSD`.
  - **capped:** true when `day` is marked, or when cap > 0 and spent ≥ cap.
  - **resetsAt:** `to`.

  `spent` and `cap` are JSON numbers, and `capped` is a JSON boolean.
- **The day's mark (AD-20, AD-31).** `Budget.MarkCapped(day = "", sinkClass = "") As %Boolean`:
  - `day` "" is today in the instance zone, and `sinkClass` "" means `Accessor.ClassFor("HostSinkClass")`.
  - Under `Lock +^OcuTalonBP.UsageCapped(day):5`, it sets `^OcuTalonBP.UsageCapped(day)` = `NowUtc()` when the node is absent.
  - It releases the lock, then fires `budget.capped` with `ownerRef` `instance` and `HostSink.BudgetCappedPayload(day)`, only when this call set the node. It returns 1 then, else 0.
  - A lock it cannot get, and a sink failure, are logged as warnings. The lock failure leaves no mark and fires no event; a sink failure leaves the mark set.
- **The bridge's clock (AD-18).** `OcuTalon.Bridge.Time` gains:
  - `ToLocal(utc)`, with the same contract as `OcuTalon.Data.Time.ToLocal`;
  - `LocalDate(utc)` (`YYYY-MM-DD` in the instance zone);
  - `DayStartUtc(day)` (the UTC time of the first instant of that local date);
  - `DayEndUtc(day)` (the next date's `DayStartUtc`);
  - `MsSince(timestamp)` (whole milliseconds from a UTC `YYYY-MM-DD hh:mm:ss[.fff]` to now).

  Each returns "" for an unreadable input.
- **Events (AD-31).** Every bridge event goes through `Decide.FireEvent`, which gains two trailing optional parameters, `type` (default `decision.recorded`) and `payload` (default `RefPayload(ref)`). It keeps its check and its error handling. Its warning names the sink class, the event and the subject, which is `ref`: the decision's Ref, or the day for `budget.capped`.
- **The bridge boundary (AD-2).** Nothing in `src/bridge/` names another OcuTalon package.
- **Storage (AD-5).** `Decide`'s Storage block gains slots 5 to 7, appended by the compiler. The committed block equals the compiled one.
- **Text.** All text in `src/` and `release/` is ASCII.
- **Tests.** They go under `OcuTalon.Test.Bridge` and `OcuTalon.Test.Agent` (the lane-a shard). Each test that this story adds or changes removes the `Usage` and `Decision` rows, the System Default Settings rows, the `^OcuTalonBP.UsageCapped` nodes and the `^OcuTalonTest` nodes it made.

**Never:**
- **Story 1.6's route.** No fallback route, no precheck (`no_key`, `daily_cap`, `budget`, `too_large`) and no classification of the gateway's 403.
- **Steps and re-sends.** No agent step and no step renderer (Story 1.5). No re-send and no `ToolsRun` (Story 1.7, DW-56).
- **Compaction.** No compaction row (Story 30.1).
- **Pinned shapes.** No change to the properties or indexes of `Usage`, `Price`, `Decision` or any `OcuTalon.Bridge.Msg` class. They are pinned by Lane B's `Test.Data.Tables` and `Test.Contract.Ac`, and by Lane A's `Test.Bridge.Contracts`.
- **No new structures.** No new persistent class, production item or event type.
- **Settings rows.** No System Default Settings row is seeded for the budget settings (Story 3.8 writes them on the online demo).
- **Errors.** No `$$$LOGERROR` in the usage and budget paths.
- **Files left alone.**
  - `Production.cls`, `ci/units.sh`, `Msg.Enum` and `Bridge.Msg.Enum` stay as they are.
  - So do `triage.json`, `chat.json` and the other existing scenario files.
- **No contended edit.** Nothing in `docker/**`, in `ci/**` outside `ci/mock/scenarios/A/`, in `.github/workflows/ci.yml`, or in any Lane B class or test.
- **No key.** No literal key and no `@{env:...:-fallback}`.
- **No commit and no push.**

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Decide, fixed usage | Untrusted `decide` through `Decide`, marker `usage-decide` (one request: input 1,200, output 300, cache read 2,000, cache creation 600, delay 1 s) | 1. **The Usage row:** one row for the request's `DecisionRef`, with `Agent` `TriageAgent`, `Model` `claude-haiku-5-5`, `RequestCount` 1, `InputTokens` 3800, `OutputTokens` 300, `CacheReadTokens` 2000, `CacheWriteTokens` 600, `LargestRequestTokens` 3800, `CostUSD` 0.000365 and `Estimated` 0.<br>2. **The runner's `Reply`:** the same counts, cost and model, `AgentStepCount` 1 and `DurationMs` ≥ 1000.<br>3. **The decision:** the `Decision` row and the `DecisionResponse` hold the same counts, cost and model, `AgentStepCount` 1, and a `DurationMs` of at least the runner's `DurationMs` and under 60,000.<br>4. **Visual Trace:** the `DecisionResponse` XML holds the eight names with these values. | No error expected |
| Turn, two requests | User `turn`, marker `usage-turn`: a `tool_use` reply (input 1,000, output 50, cache creation 512), then text (input 1,100, output 80, cache read 512) | `RequestCount` 2, `InputTokens` 3124, `OutputTokens` 130, `CacheReadTokens` 512, `CacheWriteTokens` 512, `LargestRequestTokens` 1612 and `CostUSD` 0.000344, on the row, the runner's `Reply`, the turn's `Decision` row and its answer. `AgentStepCount` is 2 plus the tool-call count that Task 0 (a) measures (1 expected), on the `Reply`, the row and the answer. | No error expected |
| Late reply | `TimerSeconds` 2, marker `decide-late` | The error (as in Story 1.3) and no `Decision` row. After the late reply, one `Usage` row exists for the `DecisionRef` that the runner's request carried. | Error names the timer |
| Failed turn with spend | User `turn`, marker `tool-loop` (`ChatAgent` reaches `max_iterations` 4) | No `Decision` row. One `Usage` row whose `RequestCount` and `InputTokens` are above 0 (Task 0 (b)). | The runner's error status |
| Failed call, no spend | Pure: `Chat` threw and the `GetStats()` delta is all 0 (measured on the slot: a refused connection) | No row | None |
| Repeat | The same `ItemId` as `decide` again | The answer carries the recorded row's totals, and no new `Usage` row is written. | No error expected |
| Cost (pure) | Haiku rates. Prompt 90,000, read 5,000, write 4,000, output 2,000 | 1. **Largest 100,000:** 0.01055.<br>2. **Largest 100,001:** 0.05275.<br>3. **Largest "", prompt 92,000, `RequestCount` 1:** 0.05375 (the average is above the threshold). With `RequestCount` 2: 0.01075.<br>4. **Sonnet, prompt 1,000, read 1,000, output 1,000:** 0.0122.<br>5. **Model `zz-unpriced`:** "". | Unpriced: warning |
| Seeds | `Installer.Run()`: the rows absent; then Haiku's `InputPerMTok` edited to 0.2 and `Run()` again | 1. **First run:** both rows hold the table's values.<br>2. **Second run:** the edited value stays, and a deleted Sonnet row is created again. | No error expected |
| Totals (in process) | `Conclude` with two fixture `Usage` rows for its ref (models `claude-haiku-5-5`, then `claude-sonnet-5-5`), `durationMs` 1234, and a runner reply with `AgentStepCount` 5 | 1. **The values:** the row and the answer hold the sums, `Model` `claude-sonnet-5-5`, 5 and 1234, for a decide and for a turn.<br>2. **No rows:** the token fields, cost and model are "".<br>3. **A row of unknown cost:** the decision's cost is "". | No error expected |
| State, off | No budget setting, no mark; `now` = 2001-02-04T12:00:00Z (a day with no row), zone unset | `{"spent":0,"cap":0,"capped":false,"resetsAt":"2001-02-05T00:00:00Z"}` | No error expected |
| State, a day in New York | Process zone `America/New_York`, `now` 2025-03-09T12:00:00Z, fixture rows at the times below | 1. **Rows counted:** `2025-03-09T05:00:00Z` and `2025-03-10T03:59:59Z`.<br>2. **Rows not counted:** `2025-03-09T04:59:59Z` and `2025-03-10T04:00:00Z` (outside the day), an `eval` row and a row of unknown cost.<br>3. **resetsAt:** `2025-03-10T04:00:00Z`. | No error expected |
| State, cap and gateway | The New York day's rows. SDS rows `DailyCostCapUSD` = that day's spend, then the spend plus 1. `GatewaySpendUSD` 2 with `GatewaySpendDate` = `day`, then the day before. `DailyCostCapUSD` `x` and -1 | 1. **The cap:** capped at spend = cap, and not capped below it.<br>2. **The gateway's spend:** added only on its own date.<br>3. **A bad cap:** `x` and -1 count as 0, so the cap is off. | No error expected |
| Bridge.Time vs Data.Time | UTC instants every 30 minutes from 2025-03-08T00:00Z to 2025-03-11T00:00Z and from 2025-11-01T00:00Z to 2025-11-04T00:00Z, in `America/New_York`, `Asia/Kolkata` and an unset zone | 1. **The conversion:** `Bridge.Time.ToLocal` = `Data.Time.ToLocal`, and `LocalDate` = its date part.<br>2. **The day bounds:** `DayStartUtc` of 2025-03-09, 03-10, 11-02 and 11-03 in New York is 05:00Z, 04:00Z, 04:00Z and 05:00Z. So 2025-03-09 lasts 23 h and 2025-11-02 lasts 25 h.<br>3. **Midnight:** `Data.Time.ToLocal(DayStartUtc(d))` = `d`T00:00:00, and one second earlier is the day before at 23:59:59.<br>4. **Havana:** in `America/Havana`, 2025-03-09 starts at local 01:00 (05:00Z). | No error expected |
| Mark once | `MarkCapped("2001-02-03", probe sink)` twice, then `State(<2001-02-03T12:00:00Z>)` with no cap and no spend | 1. **First call:** returns 1. The probe sees one `budget.capped`, `ownerRef` `instance`, payload exactly `{"day":"2001-02-03"}`, and the mark already set during the call.<br>2. **Second call:** returns 0 and sends no event.<br>3. **State:** `capped` true. | No error expected |
| Mark under the lock | The test holds `^OcuTalonBP.UsageCapped(day)`'s lock; a child job calls `MarkCapped(day)` | 1. **While the lock is held:** after 2 s the node is still absent and the child has not returned.<br>2. **After release:** the test sets the node and releases the lock, and the child returns 0. | No error expected |
| Mark, sink fails | The probe sink in error and in throw mode | 1 is returned, the mark is set, and `State` reports capped. | A warning names the sink, the event and the day |
| The bridge alone | `release/standalone-bridge.sh` (Story 1.3's run) | 1. **The prices:** after `Installer.Run()` both `Price` rows exist.<br>2. **The decision:** its row has `Model` `claude-haiku-5-5`, `InputTokens` above 0 and `CostUSD` above 0, with one `Usage` row for its Ref whose `Agent` is `TriageAgent`. | The script fails, naming the check |

</intent-contract>

## Code Map

- **The bridge (Lane A):**
  - **`src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:**
    - `Answer` (:185-217) holds the only `Chat` call (:201), in a `Try` (:198-212). `NewSession` is at :153, and the agent's model is `..Agent.Model` (:149).
    - `Test.Bridge.CodeRules` allows `Chat`, `CreateSession` and `OpenSession` only here (`TestOnlyRunnersChat`, `TestSessionsOnlyThroughTheComposer`) and no `Job` or `WorkMgr` (`TestRunnerStartsNoJob`).
    - `GetStats()` is an instance method of `%AI.Agent.Session` (`irislib/%AI/Agent/Session.cls:274`). It needs an attached session.
  - `src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls`: `OnMessage` (:20-34) stays as it is. The runner's config name is `..BusinessHost.%ConfigName` from the adapter.
  - **`src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:**
    - `SETTINGS` (:23) and the properties (:35-44).
    - `OnResponse` (:74-88), which calls `Conclude` (:87).
    - `Conclude` (:225-293): the row is built at :268-281 and the turn's clone at :285-290.
    - `Record` (:298), `FireEvent` (:316-335), `ResponseFromRow` (:349-364).
    - The Storage block (:366-385) holds slots 1 to 4. Lane B's `docker/tests/test-storage-roundtrip.sh:74-137` compares it with the compiled block and uses this file as its control (slot 3).
    - `%TimeCreated` (`Ens.DataType.UTC`, ms) is on `irislib/Ens/BusinessProcess.cls:103`, and `OnError` is at :875.
  - **The data classes:** `Usage.cls` (16 properties; `DecisionRefIndex` and `OwnerRefIndex`), `Price.cls` (8 properties; `ModelIndex` unique) and `Decision.cls` (the totals properties at :44-66). Lane B's `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls:157-257` pins every property and index of all three, so methods only may be added.
  - `src/bridge/cls/OcuTalon/Bridge/Msg/Result.cls`: the totals fields (:23-45), shared by `Reply` and `DecisionResponse`. `Test.Bridge.Contracts.TestNewBusy` (:27-29) needs `NewBusy`'s totals to stay "".
  - `src/bridge/cls/OcuTalon/Bridge/Budget.cls`: the stub `State` (:8-11). `Test.Contract.Ac:320` pins `State()` and allows trailing optional parameters (:138-163).
  - `src/bridge/cls/OcuTalon/Bridge/Time.cls`: `NowUtc` (:8-11).
  - `src/bridge/cls/OcuTalon/Bridge/Installer.cls`: `Run` (:10-18) and `SeedModelFamilies` (:33-53), a structural rewrite. `docker/tests/test-audit.sh:106-111` needs `Run()` to return 1.
  - **`src/bridge/cls/OcuTalon/Bridge/Ext/`:**
    - `Accessor.ClassFor` (:16-33) reads `Ens.Director.GetHostSettingValue`, which falls back from an item setting to a System Default Settings row to the property's `InitialExpression` (`irislib/Ens/Config/Item.cls:306-342`). `Ac:328-329` pins `ClassFor` and `Check`.
    - `HostSink.cls`: `BUDGETCAPPED` (:25) and `BudgetCappedPayload(day)` (:50). `Test.Bridge.Ext:96-116` pins them.
- **Lane B, read and call only:**
  - `src/ocutalon/cls/OcuTalon/Data/Time.cls`: `ToLocal` (:22-28), the contract `Bridge.Time.ToLocal` copies, and `Zone` (:52).
  - `src/short-names.tsv`, checked by `docker/tests/test-storage.sh:76-166`. A plain global needs no row, and a row needs a class whose `DEFAULTGLOBAL` matches. `docker/merge.cpf:12` maps `OcuTalonBP.*` to the private database.
- **The mock (Lane A's folder `ci/mock/scenarios/A/`; the code is Lane B's):**
  - **Default usage.** The default usage (`ci/mock/mock.mjs:324-329`) is `input_tokens` = ceil(raw body length / 4), `output_tokens` = ceil(content JSON length / 4), and both cache counts 0.
  - **Reply fields.** A reply's fields are `status`, `headers`, `delayMs`, `stopReason`, `text`, `toolUse` and `body` (`scenarios.mjs:26`). There is no usage field.
  - **Exact usage.** Only a `body` reply (a full Messages object, sent as written) sets exact usage, cache fields included. A `body` cannot take `stopReason`.
  - **The rules for a new file.** It is a marker scenario (`constants.test.mjs:70-80` allows a `mockkey` only for an agent's `MOCKKEY`). Its name equals its file name, it is kebab-case and unique, and `[[mock:<name>:<key>]]` isolates a test.
  - **The log.** The log records requests only, never the response or its usage (`mock.mjs:363-379`).
  - **Scenarios used here.** `decide-late` (delay 6 s), `tool-loop` (one `toolUse` reply, repeated) and `provider-error` (500) already exist.
- **Tests and fixtures (Lane A):**
  - **`src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls`:**
    - `OnAfterOneTest` (:56) deletes the `Decision` rows by `ItemId`.
    - Tests: `TestRepeat` (:186), `TestUnusableEndsWithError` (:297), `TestTimer` (:323-345) and `TestTraceFields` (:369-395).
    - Helpers: `Run` (:415) and `Case` (:426).
    - The keys are pointed once for the class (Story 1.3, decision 26).
  - **`src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`:**
    - Requests: `NewRequest` (:129), `Send` (:118), `Ask` (:147).
    - Lookups: `DecisionOf` (:168), `Headers` (:175), `SessionOf` (:186), `HeaderMark` and `SessionSince` (:195-203).
    - Keys and events: `PointKeys` and `RestoreKeys` (:212-219), `EventMark` and `EventRows` (:97-106).
  - `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls` `WriteDefault(production, item, setting, value, description)` (:270-286): the System Default Settings writer that `Test.Agent.Decide.TestTimer` uses.
  - **`src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls`:**
    - Tests: `TestTurnKeepsReply` (:598-629) asserts the clone keeps the runner's totals ("123|45"), and `TestResponseFromRow` is at :370.
    - Helpers: `NewProcess` (:716) makes an unstarted `%New("Decide")` that reads the active production's settings; the `Conclude` helper is at :758; `AssertWarning` (:810-813) filters on `SourceMethod` `FireEvent`.
    - The time-zone save and restore is at :694-706: `$SYSTEM.Process.TimeZone()`, with -1 restored as "".
  - `src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeSink.cls`: `record`, `error` and `throw` modes in `^||ZzProbeSink`.
  - `src/ocutalon/cls/OcuTalon/Test/Bridge/Ext.cls:10-11, 25-63`: child jobs that report through `^OcuTalonTest("BridgeExt", n, ...)`.
  - `src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls:36`: pins `State()`'s stub JSON.
  - `src/ocutalon/cls/OcuTalon/Test/Bridge/Example.cls:95-101`: `TestDecideDefaults`.
  - `src/ocutalon/cls/OcuTalon/Test/Bridge/Runner.cls`: in-process runner tests on the shadow host `ZzRunner`, through the real `OnMessage`.
  - `src/ocutalon/cls/OcuTalon/Test/Agent/Render.cls:17-35`: zone switching with `$SYSTEM.Process.TimeZone(<zone>)`.
  - `ci/units.sh:14-18`: the lane-a shard is the areas `Agent`, `Bridge` and `Install`, and new test classes are found by glob.
- **CI (Lane A):** `release/standalone-bridge.sh` (173 lines). The decide check is at :126-143, in `check_session` blocks of `CHK|` lines.

## Tasks & Acceptance

**Execution:**

**Task 0: measure, and record the facts under `## Verification` (Measured in implementation).**
- Use the slot for process-local facts and a throwaway of tag `e1s4a` for the rest.
- **(a) Through the mock**, for `usage-decide`, `usage-turn` and `chat.json`: the `GetStats()` keys and values before and after `Chat`, and `Response.Usage`'s keys and values.
  - Expected: `prompt_tokens` = the body's `input_tokens`, which excludes the cache counts (S2); `total_interactions` = the request count; and the count in `total_tool_calls` of `usage-turn`'s call of a tool that `ChatAgent` does not have (1 expected), which sets that row's expected `AgentStepCount`.
- **(b)** `GetStats()` after `Chat` throws: for `provider-error` (500), and for `tool-loop` on `ChatAgent` (the maximum-iterations error, `RequestCount` expected 4, inference).
- **(c)** A `body` reply of type `tool_use` drives AI Hub's tool loop as `toolUse` does.
- **(d)** The `cache_control` blocks the mock logs carry no `ttl`, so every cache write is a 5-minute write.
- **(e)** `Decide`'s `%TimeCreated` is set when `OnResponse` runs, in UTC to the millisecond. If it is empty, use `..%PrimaryRequestHeader.TimeCreated` and record that.
- **(f)** `GetHostSettingValue` of `Decide`'s three new settings with no row gives 0, "" and "" with OK. A System Default Settings row takes effect at the next read, with no restart.
- **(g)** The XML form of `CostUSD` and the integers in an exported `DecisionResponse`.
- If a fact contradicts this spec in a way that changes an AC, stop with status `blocked` and the condition `intent gap: <the AC>, measured <fact>`.

**The bridge.**
- **`src/bridge/cls/OcuTalon/Bridge/Time.cls`**: add `ToLocal`, `LocalDate`, `DayStartUtc`, `DayEndUtc` and `MsSince` (Boundaries). `DayStartUtc` is `$ZDateTime($ZDateH(day,3)_",0",-3)`, formatted like `NowUtc` (measured below). Rationale: AD-2, AD-18.
- **`src/bridge/cls/OcuTalon/Bridge/Data/Price.cls`**: add the pure instance method `Cost(prompt, cacheRead, cacheWrite, output, largest, requestCount)` and the class method `CostFor(model, ...)`, which opens `ModelIndex` and gives "" when there is no row. No property or index change. Rationale: AD-20, FR-2.
- **`src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls`**: add three class methods. No property or index change. Rationale: AD-20.
  - `FromStats(request, agent, model, before, after, last, Output row)` builds the unsaved row from the two stats objects and the last `Response.Usage`;
  - `HasSpend(before, after)` is 1 when the delta holds a request or a token;
  - `Totals(decisionRef)` gives `{inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens, costUSD, model, rows}` by SQL, with "" values for an empty ref or no rows.
- **`src/bridge/cls/OcuTalon/Bridge/Installer.cls`**: add `Prices()`, a `$ListBuild` per row of the Boundaries table, in the same shape as `ModelFamilies()`. Add `SeedPrices()`, which creates only the absent rows, and call it from `Run()` after `SeedModelFamilies()`. Update the comments. Rationale: AD-19, AD-20, FR-2.
- **`src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`**: in `Answer`, read `GetStats()` after `NewSession` and again after `Chat` (inner `Try`), with `$ZHorolog` around `Chat`.
  - Write the row through a new `RecordUsage` method: after a return, or after a throw when `Usage.HasSpend` is 1.
  - Copy the counts, cost, model, `AgentStepCount` and `DurationMs` onto the `Reply`.
  - A `GetStats()`, price or save problem is a `$$$LOGWARNING`.
  - Keep the context's begin and end and the error statuses as they are, and update the class comment.

  Rationale: AD-6, AD-9, AD-20.
- **`src/bridge/cls/OcuTalon/Bridge/Ext/Accessor.cls`**: add `ValueFor(setting, production = "", item = "Decide", Output sc) As %String`, which gives any host setting's value. `ClassFor` calls it and then `Check`. Update the class comment. Rationale: AD-19, AD-31.
- **`src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`**: Rationale: AD-5, AD-19, AD-20, AD-26, AD-31.
  - **Settings.** Add the three budget settings to `SETTINGS` and as properties (Boundaries).
  - **`OnResponse`** passes `Bridge.Time.MsSince(..%TimeCreated)` to `Conclude`.
  - **`Conclude`** gains the trailing parameter `durationMs = ""`. Before `Record`, it copies `Usage.Totals(decisionRef)`, the reply's `AgentStepCount` and `durationMs` onto the row. The turn's clone and the `DecisionResponse` take the row's totals.
  - **The copy helper.** A new `CarryTotals(from, to)` copies the eight fields between a row and a `Result`. `ResponseFromRow` uses it, so a recorded answer carries its totals.
  - **`FireEvent`** gains `type` and `payload` (Boundaries).
  - Update the class comment.
  - The compiler appends slots 5 to 7 to the Storage block, and the committed block is the compiled one.
- **`src/bridge/cls/OcuTalon/Bridge/Budget.cls`**: implement `State(now = "")` and add `MarkCapped(day = "", sinkClass = "")` (Boundaries). The settings are read through `Accessor.ValueFor`, and the event goes through `Decide.FireEvent`. Use `Include Ensemble` for the warnings, and replace the class comment. Rationale: AD-2, AD-20, AD-31.

**The mock (Lane A's folder).** Two new marker files, each reply with status 200 and a `body` in the Messages shape (`id`, `type` `message`, `role` `assistant`, `model` `claude-haiku-5-5`, `content`, `stop_reason`, `stop_sequence` null, `usage`). Rationale: AD-22.
- **`ci/mock/scenarios/A/usage-decide.json`**:
  - `delayMs` 1000;
  - `content`: one text block, `{"outcome":"digest","reasons":["The CI mock reports a fixed usage."],"confidence":0.5}`;
  - `stop_reason` `end_turn`;
  - `usage`: `input_tokens` 1200, `output_tokens` 300, `cache_read_input_tokens` 2000, `cache_creation_input_tokens` 600.
- **`ci/mock/scenarios/A/usage-turn.json`**:
  - **Reply 1:** a `tool_use` block (`id` `toolu_usage_turn_1`, `name` `list_productions`, `input` `{}`), `stop_reason` `tool_use`, and usage 1000, 50, 0 and 512.
  - **Reply 2:** text "The CI mock reports the usage of two requests.", `end_turn`, and usage 1100, 80, 512 and 0.

**CI (Lane A).**
- **`release/standalone-bridge.sh`**: add one `check_session` after the decide check for "The bridge alone": both `Price` rows exist; the decision row's `Model`, `InputTokens` > 0 and `CostUSD` > 0; and one `Usage` row for its Ref with `Agent` `TriageAgent`. Update the header comment. Rationale: AD-2, AD-31, FR-5.

**Tests.**
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Usage.cls`** (new; pure, plus its own rows): it deletes its rows and restores the `Price` rows it changed.
  - `TestCost`: the "Cost" row;
  - `TestFromStats`: a non-zero `before`, the four sums, `RequestCount`, `LargestRequestTokens` from `last` and "" without it, the request fields, `Estimated` 0 and `RecordedAt` in UTC;
  - `TestHasSpend`;
  - `TestSeedPrices`: the "Seeds" row;
  - `TestTotals`: `Usage.Totals`.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Budget.cls`** (new; in process): the State rows, "Mark once", "Mark under the lock" and "Mark, sink fails".
  - **Settings rows.** It writes them with `Install.Step.Production.WriteDefault` for the active production, and restores any value that was there.
  - **The child job.** `MarkInJob(day, run)` is a class method that reports through `^OcuTalonTest("BridgeBudget", run, ...)`, as `Test.Bridge.Ext` does.
  - **The time zone.** It is saved and restored as in `Test.Bridge.Decide`.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Time.cls`** (new; pure): the "Bridge.Time vs Data.Time" row, plus `MsSince` against a timestamp 250 ms old.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeSink.cls`**: in `record` mode, also keep whether `^OcuTalonBP.UsageCapped(payload.day)` exists during the call, when the payload has a `day`.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls`**:
  - add `TestTotals` (the "Totals (in process)" row);
  - change `TestTurnKeepsReply`: the totals and the model now come from the decision's `Usage` rows, every other field from the runner's `Reply`;
  - extend `TestResponseFromRow` (the row's totals are carried);
  - add `TestFireEventTypes` (`budget.capped` through `FireEvent`, with its payload and owner);
  - update the header and remove the `Usage` rows it made.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls`**:
  - add `TestUsageDecide` and `TestUsageTurn` (the matrix rows, including the XML values) and `TestCostOfFailedTurn` ("Failed turn with spend");
  - extend `TestTimer` (the late row) and `TestRepeat` (the totals are carried, and no new `Usage` row);
  - `OnAfterOneTest` also deletes the `Usage` rows of its `ItemIds`;
  - update the header.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls`**: `TestNeutralValues` no longer checks `Budget.State`, which is no longer a stub (`Test.Bridge.Budget` pins it), and its comments say so.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Example.cls`**: `TestDecideDefaults` also asserts that `DailyCostCapUSD` is 0 and the two gateway settings are "".
- Prove every matrix row with these tests and the script.

**Acceptance Criteria:**
- **AC1, the runner's usage row.**
  - **Given** a runner's `Chat` call that completes, through the running production and the mock,
  - **when** it returns, also after `Decide`'s timer has fired,
  - **then:**
    - the runner writes one `Usage` row from the `GetStats()` delta around the call, with `DecisionRef`, `ItemId`, `Kind`, `OwnerRef`, `RecordedAt` in UTC, the agent, channel, model, request count, the four token counts with input = prompt + cache read + cache write, `LargestRequestTokens`, cost and `Estimated` false;
    - a call that throws after spending tokens is counted too.

  (`Test.Agent.Decide.TestUsageDecide`, `TestUsageTurn`, `TestTimer`, `TestCostOfFailedTurn`; `Test.Bridge.Usage.TestFromStats`, `TestHasSpend`)
- **AC2, the cost and the prices.**
  - **Given** the usage a provider reports,
  - **when** its cost is computed,
  - **then** each tier is priced at its own rate from `Price`, the long tier applies above 100,000 tokens, and a unit test matches hand-computed costs at every tier;
  - **and** `Installer.Run()` seeds Claude Haiku 5.5 and Claude Sonnet 5.5 as the Boundaries table gives, and leaves an edited row alone.

  (`Test.Bridge.Usage.TestCost`, `TestSeedPrices`)
- **AC3, the totals (Integration AC).**
  - **Given** a decision or a turn,
  - **when** `Decide` records it,
  - **then:**
    - its `Decision` row and its answer carry the sums of its `Usage` rows in `InputTokens`, `OutputTokens`, `CacheReadTokens`, `CacheWriteTokens` and `CostUSD`, with `Model`, `AgentStepCount` and `DurationMs`;
    - Visual Trace's XML of the decision message shows them under those names, and the runner's `Reply` shows its own part;
    - a decide's `CostUSD` on its row is the per-decision cost that the NFR-4 measurement reads.

  The consumer is `Decide`: it reads the runner's rows in the running production and produces the totals. With the bridge alone, the example's decision carries its cost too.

  (`Test.Agent.Decide.TestUsageDecide`, `TestUsageTurn`, `TestRepeat`; `Test.Bridge.Decide.TestTotals`, `TestTurnKeepsReply`; `release/standalone-bridge.sh`)
- **AC4, the budget's state and the day.**
  - **Given** `DailyCostCapUSD` (0 means off), `GatewaySpendUSD` and `GatewaySpendDate` read through the accessor,
  - **when** `Budget.State()` is called,
  - **then:**
    - it returns spent, cap, capped and resetsAt in UTC;
    - the day ends at midnight in the instance zone through `Bridge.Time`;
    - owner `eval` is never counted;
    - a test compares `Bridge.Time` with `Data.Time` across both 2025 daylight-saving changes.

  (`Test.Bridge.Budget`, `Test.Bridge.Time`)
- **AC5, the day's cap, once** (the mechanism; Story 1.6 calls it from its two paths, Design Notes, decision 1).
  - **Given** a day that a `daily_cap` path marks twice,
  - **when** `Budget.MarkCapped` runs,
  - **then:**
    - the day is marked once, under a lock;
    - `budget.capped` fires once after the mark, with `ownerRef` `instance` and payload `{day}`;
    - `Budget.State()` reports capped from then on, even with the spend under the cap.

  (`Test.Bridge.Budget`)

## Spec Change Log

- 2026-10-22, lead (Epic 1 runner), at the spec gate. Two Rule 5 amendments of `epics.md` (unattended rulings, `category=veto`); this spec already follows both, so no section of it changed:
  - **U-16, Story 1.4's last criterion** (`epics.md`, Story 1.4, the `daily_cap` Given/When/Then, with an inline `[AMENDED 2026-10-22 …]` marker; Story 1.6 gains a `[MOVED 2026-10-22 from Story 1.4 …]` bullet under its precheck criterion).
    - **Original:** "**Given** the first decision of the day that falls back with `daily_cap`, from the precheck or from the gateway's HTTP 403 "daily cost cap reached" **When** the bridge records it **Then** it marks the day as capped once, under a lock, so `Budget.State()` reports the cap reached from then on even when the gateway refused first, and fires the HostSink event `budget.capped` once that day, with `ownerRef` `instance` and payload `{day}` (the instance-zone date); a test forces both paths through the mock and finds one event".
    - **Amended:** the criterion pins `Budget.MarkCapped` (one caller or several at once: one mark, one event); the two triggers and the both-paths mock test are Story 1.6's, which already owns the `daily_cap` precheck and the 403's classification.
  - **U-17, Story 1.4's seed clause** (`epics.md`, Story 1.4, the `Installer` seed `And` line, with an inline marker).
    - **Original:** "cache writes at 1.25 times (5-minute) or 2 times (1-hour) the input price".
    - **Amended:** "cache writes at 1.25 times the input price (the 5-minute tier, the only one AI Hub writes)".
    - **Rationale:** AI Hub's cache config has no TTL key and `GetStats()` reports no TTL split, so no token could be priced at a 1-hour rate; Epic 0's merged `Price` schema holds one cache-write rate per model (pinned by Lane B's `Test.Data.Tables`), which is read as AD-19's "cache-write tiers". The spine is unchanged.

## Review Triage Log

## Design Notes

**The architecture decisions that govern this story (Rule 6):**
- **AD-2:** `Budget` and `Time` stay inside the bridge, and the standalone path prices and counts too.
- **AD-3:** the mark lives in a private `^OcuTalonBP.` global.
- **AD-5:** the append-only storage of `Decide`. The budget values live in System Default Settings, not in the production class.
- **AD-6:** the runner reads `GetStats()` around `Chat`, and only the adapter calls `Chat`.
- **AD-9:** tokens per turn, never per step. `Response.Usage` covers the last request only.
- **AD-18:** `Bridge.Time` and the daylight-saving comparison.
- **AD-19:** the prices in `Price`, `Decide`'s three budget settings, and seed against structural.
- **AD-20:** the row, the totals, `Budget.State()` and the day's mark.
- **AD-26:** the totals' field names in Visual Trace.
- **AD-31:** `budget.capped`, after the mark, wrapped, never failing its caller.
- **AD-33:** no new item, table or event type.

**Departures from an AD's wording.** Decisions 2 and 5 depart from wording in AD-19 and AD-20, for reasons the lead may rule. No acceptance criterion contradicts an AD's Rule.

**Decided in-stage:**
1. **The split of AC5 (said plainly for the lead).** The story's fifth criterion begins "the first decision of the day that falls back with `daily_cap`, from the precheck or from the gateway's HTTP 403", and ends "a test forces both paths through the mock and finds one event". Both paths are Story 1.6's: its precheck and its classification of the 403. The lead's story boundaries give the prechecks to Story 1.6, and no fallback exists before it.
   - **This story** builds and pins the mechanism: `MarkCapped`, its lock, its once-a-day event, and `State`'s capped flag from the mark.
   - **Story 1.6 receives** the two calls and the live both-paths test. It calls `MarkCapped` once its `daily_cap` decision is recorded, on both paths, and the live test finds one event.
   - So that clause moves to Story 1.6. The lead rules it (veto window, item 7). The recommended bullet for Story 1.6 is: "Its `daily_cap` precheck and its classification of the gateway's 403 call `Budget.MarkCapped` once the fallback decision is recorded; a test forces both paths through the mock and finds one `budget.capped` event (Story 1.4, decision 1)".
   - **If the lead rules against the move,** the alternative is staging in this story: a `daily_cap` check in `OnRequest` that ends with an error, and an `OnError` hook on the 403's text, both calling `MarkCapped`. Story 1.6 would turn both into fallbacks.
2. **Only the 5-minute cache-write rate is stored (for the lead).**
   - **What can be stored.** `Price` has one cache-write column, pinned by Lane B's `Test.Data.Tables:242-257`.
   - **No consumer of a 1-hour rate.** AI Hub's cache config has no TTL key (`irislib/%AI/Provider.cls:133-138`), so every cache write is a 5-minute write (Task 0 (d) confirms). `GetStats()` reports `total_cache_creation_tokens` with no TTL split (measured below). So a 1-hour rate, 2 times the input price, would have no tokens to price.
   - **What is seeded.** The column holds 1.25 times the input price. AD-19's "cache-write tiers" is then one tier.
   - **Recommended amendment** (Rule 5, apply and report): AC2's seed clause becomes "cache writes at 1.25 times the input price (AI Hub writes 5-minute cache entries only)".
   - **The alternative** is a `CacheWrite1hPerMTok` property with a Lane B oracle change (orchestrator).
3. **Claude Sonnet 5.5's other rates (for the lead).** The PRD gives only $2 and $10.
   - **Cache rates.** The cache rates are stated as multiples of "the input price", so they are applied to Sonnet too: 0.20 and 2.50.
   - **No long tier.** The PRD states none for Sonnet, so none is seeded, and its base rates apply at every size. An admin can edit the prices (FR-17, step 2).
4. **The long tier, per turn.** `GetStats()` gives no per-request tokens (S4). So when the turn's largest request is above the threshold, the whole turn is priced at the long tier, which never under-counts against a cap.
   - The cache rates scale with the input price, as the addendum says: "the whole request costs five times as much".
   - When the largest request is unknown (a call that threw), the average request (`InputTokens` ÷ `RequestCount`), a lower bound, decides.
5. **`LargestRequestTokens` is measured.** It is the last request's input from `Response.Usage`, read after `Chat`, outside any callback. In AI Hub's loop each request resends the whole history, so the last request is the largest (inference: the platform reports no per-request size to check it against).
   - This is the AD-20 field "the largest estimated request size". A measured size replaces an estimate.
   - Story 1.5's step estimates stay in the steps (AD-20: the in-loop size is estimated "for the step record only").
6. **Which calls get a row.** A returned `Chat` always gets a row. A thrown one gets a row when it spent anything (Story 1.6's maximum-iterations error spends up to four requests). A call that threw before any request gets none (measured below: all zeros).
7. **Unknown cost is "", never 0.** It covers an unpriced model, and a decision with any row of unknown cost. `State` cannot count such a row. The installer prices the two models it ships.
8. **What the totals are made of.**
   - **From the rows.** The tokens and the cost are sums of `Usage` rows. `Usage` has no step or duration column (pinned), so those two come from elsewhere.
   - **`AgentStepCount`** comes from the runner's `Reply`. It counts model requests plus tool calls, which is what Story 1.5 will emit as steps.
   - **`DurationMs`** is `Decide`'s elapsed time, which the timer bounds.
   - **`Model`** is the newest row's model.
9. **The runner's `Reply` carries its own part** (one `Chat`), and `Decide`'s answer carries the whole decision. So Visual Trace shows both the decision's total and the parts it is summed from. A repeated item's answer carries the recorded row's totals: the answer is that decision.
10. **`Agent`** is the runner's config name (`TriageAgent`, or `ZzRunner` in `Test.Bridge.Runner`), which fits `MAXLEN` 32. Compaction's rows (Story 30.1) use `compaction`.
11. **Prices are seed values.** AD-19 and FR-17 say an admin edits them, and the epics say "earlier rows keep their cost". The model families stay structural.
12. **No seed row for `DailyCostCapUSD`.** Its `InitialExpression` 0 reads the same, and `GetHostSettingValue` falls back to it (Code Map). Story 3.8 writes the three rows on the online demo, and `SettingsOps` owns the value from step 2.
13. **Bad values fail open on the cap.** A `DailyCostCapUSD` that is not a number of 0 or more counts as 0, because a cap of "x" has no meaning. The online demo's start values come from its own deployment (Story 3.8).
14. **The mark is the plain global `^OcuTalonBP.UsageCapped(day)` = the UTC time.**
    - **No table.** A table would need a Lane B registry row (`Test.Data.Tables.TestEveryTableIsRegistered`) and an AD-33 table entry.
    - **Precedent.** A companion global of a registered short name, like Lane B's `^OcuTalonP.LiveEventC` (`Live/Publish.cls:4`), stays in the private database through the `OcuTalonBP.*` mapping.
    - **Registration.** `test-storage.sh` needs no row for it. The `short-names.tsv` convention is kept, because the global belongs to the `Usage` short name.
    - **Retention.** One node is written per capped day. Story 30.2's purge of `Usage` covers the nodes.
15. **The lock** waits 5 seconds (the lock test holds it for 2). The event fires after the lock is released, because AD-31's `BridgeSink` waits on no lock for longer than one second.
16. **`State` scans `Usage` by `RecordedAt`.** There is no index on it: `Test.Data.Tables` pins `Usage`'s indexes, so adding one is a Lane B change. Release 1's volumes are small (an online-demo reset erases the rows). So a full scan is accepted, and recorded under Residual risks.
17. **Test hooks.** `State(now)` and `MarkCapped(day, sinkClass)` take trailing optional parameters, so the tests fix the clock, the day and the sink. `Test.Contract.Ac` allows trailing optional parameters (:138-163).
18. **The live tests extend `Test.Agent.Decide`,** so the keys are pointed once, as Story 1.3's decision 26 does. `Usage.HasSpend` and the cost are pinned in process.
19. **Fixed usage needs `body` replies.** The mock's default usage depends on the raw request length, which the log does not record. So the two new scenarios fix every count. Task 0 (c) checks the `tool_use` body.

**Integration ACs (Rule 1):**
- **AC3, live.** `Decide` reads the runner's `Usage` rows (a real instance, the running production and the mock) and puts the totals on the `Decision` row and the decision message.
- **AC3, the bridge alone.** The example's runner, priced from the installer's seeds, records the decision's cost.
- **No consumer in this story** reads `Budget.State()` or `MarkCapped`. The first are Story 1.6 (the `daily_cap` precheck and the 403, decision 1) and Lane B's Story 2.10 (`dailyCap` in `/state` and `StatusMonitor`).

**Consumed-by:**
- **Story 1.5:** `AgentStepCount` against its emitted steps (decision 8), and its estimates beside `LargestRequestTokens` (decision 5).
- **Story 1.6:** `Budget.State()` in its precheck, `MarkCapped` on both paths and the both-paths test (decision 1), and the totals of a fallback decision (none when nothing was sent).
- **Story 1.7:** several `Usage` rows per `DecisionRef` across re-sends (`Totals` sums them), `AgentStepCount` across attempts, and the `total_tool_calls` delta for `ToolsRun` (DW-56).
- **Story 1.9:** `LargestRequestTokens`, and the totals for the token budget per decision.
- **Story 2.6:** `TurnCost` and `RunCost` sum `Usage` rows, and "Decision details" shows the totals.
- **Story 2.10:** `Budget.State()` for `dailyCap`.
- **Story 3.8:** writes the three budget settings on the online demo.
- **Story 9.2:** the per-decision cost for NFR-4.
- **Story 16.6:** the online demo's cap.
- **Story 30.1:** `compaction` rows with `Estimated` true, summed by `Totals`.
- **Story 30.2:** the purge of `Usage` rows and of the marks.

**Consumes:**
- **Story 1.2:** `Answer` and the session composer.
- **Story 1.3:** `Conclude`, `Record`, `FireEvent`, `ResponseFromRow`, `Bridge.Time.NowUtc`, `RunnerFixture`, `ProbeSink` and the scenarios `decide-late` and `tool-loop`.
- **Epic 0:** `Usage`, `Price`, `Decision`, `Result`, `HostSink.BudgetCappedPayload`, `Accessor` and `Budget.State()`'s signature.
- **Lane B:** `Data.Time` (tests only), the mock, `ci/iris.sh` and `lib-live.sh`, all read-only.

**Extend, don't copy (Rule 2):**
- **The event.** `FireEvent` is extended for every event, so `budget.capped` reuses its check and its warning.
- **The settings reader.** `Accessor.ValueFor` is the general read, and `ClassFor` builds on it.
- **The response.** `CarryTotals` serves both `Conclude` and `ResponseFromRow`.
- **The seeds.** `SeedPrices` follows `SeedModelFamilies`' shape, with a reason to differ: prices are seed values, families are structural.
- **The tests.** `Test.Agent.Decide` and `RunnerFixture` are extended, `Test.Bridge.Budget`'s child job follows `Test.Bridge.Ext`'s, and its settings rows use `Install.Step.Production.WriteDefault`.
- **Forced copy:** `Bridge.Time.ToLocal` copies `Data.Time.ToLocal`'s two lines (AD-2 and AD-18 name the pair), and `Test.Bridge.Time` pins that they agree.

**Ledger:** this story's inbox is empty.

## Verification

**Targets:**
- **The slot.** `ocutalon-slot-a` only, with MCP `server: ocutalon-slot-a` and `namespace: OCUTALON` on every call, after `iris_server_info` shows build 154. It is used for `iris_doc_load` compiles and process-local facts only, and no test class runs there.
- **Throwaways.**
  - Everything else goes through `ci/iris.sh` or the script, with `OCUTALON_RUN_TAG=e1s4a OCUTALON_LOCK_OWNER='epic=1 stage=implement'`. QA uses `e1s4q` and review `e1s4r`.
  - One stack at a time, one command per call, each with `timeout: 600000`.
  - Run `ci/iris.sh teardown` with the same tag at the end.
- **Never** `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition` or `ocutalon-slot-b`. No push and no `gh workflow run`. Never read `.env`.

**Commands** (each prefixed with `OCUTALON_RUN_TAG=e1s4a OCUTALON_LOCK_OWNER='epic=1 stage=implement'` where it starts a stack):
- **(loop)** `bash ci/checks.sh`. Expected: every block passes, including storage (`Decide`'s slots, no `short-names.tsv` change), class-rules (bridge-refs, unchecked-prepare) and boundaries (ASCII). About 20 s.
- **(loop)** `bash ci/iris.sh build`. Expected: exit 0.
- **(loop)** `bash ci/iris.sh class <Class>`, one call per class, for:
  - `OcuTalon.Test.Bridge.Usage`, `.Bridge.Budget`, `.Bridge.Time`, `.Bridge.Decide` and `.Agent.Decide`;
  - `.Bridge.Runner`, `.Agent.Runners`, `.Bridge.Api` and `.Bridge.Example`;
  - `.Bridge.Ext`, `.Bridge.Contracts` and `.Bridge.CodeRules`.

  Expected: `CLASS ... passed`.
- **(loop)** `bash release/standalone-bridge.sh`. Expected: every check `PASS` (the new cost check included), and exit 0.
- **(loop)** `bash ci/iris.sh shard lane-a`. Expected: every class passed, and the only SKIP is the existing `TestStepHelpers` one.
- **(loop)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s4a`'s projects.
- **(once)** `bash docker/tests/test-mock.sh`. Expected: all pass with the two new scenario files.
- **(once)** `bash ci/iris.sh shard lane-b`. Expected: every class passed, among them:
  - `Test.Data.Tables` (`Usage`, `Price` and `Decision` unchanged, and `Decide`'s new SQL names);
  - `Test.Contract.Ac` (the `State`, `ClassFor` and `Check` signatures).
- **(once)** `bash ci/iris.sh live storage-roundtrip`. Expected: PASS. `Decide`'s committed block, with slots 5 to 7, equals the compiler's.
- **(once)** `bash ci/iris.sh live production` and then `live production-restart`, one per call. Expected: PASS, with every item running and a clean start.
- **(once)** `bash ci/iris.sh live install-start`, then `live install-upgrade`, then `live audit`, one per call. Expected: PASS. Row 5's `Run()` gives 1 with the prices seeded, the upgrade keeps the `Price` rows, and the audit events are as before.
- **(once)** `bash ci/iris.sh live compose-start` and then `live demo-path`, one per call. Expected: PASS (with no key; `@floor`).
- **(once)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s4a`'s projects.

**Shared surfaces:**
- **Runner rows.** Every runner `Chat` now writes a `Usage` row (`Test.Agent.Decide`, `Test.Agent.Runners` and `Test.Bridge.Runner` make them). Only `Test.Bridge.Budget` sums them, on fixture days of 2025 and 2001 that no real row reaches.
- **`Price` rows,** which `Installer.Run()` seeds and `Test.Bridge.Usage` edits and restores.
- **`Decide`'s settings and Storage block,** read by `test-storage-roundtrip.sh`, `Test.Bridge.Example.TestDecideDefaults` and `Test.Data.Tables.TestSqlNames`. The XData is unchanged, so `Test.Install.Production` is unchanged.
- **The totals on `Reply` and `DecisionResponse`:** `Test.Bridge.Decide.TestTurnKeepsReply` is updated. `Test.Bridge.Contracts.TestNewBusy` stays.
- **`Budget.State()`'s output:** `Test.Bridge.Api.TestNeutralValues` is updated.
- **The System Default Settings rows** of `Decide`'s budget settings, written and restored by `Test.Bridge.Budget`.
- **The mark global** `^OcuTalonBP.UsageCapped`, and `^OcuTalonTest("BridgeBudget")`.
- **The mock's scenario set:** two new marker files.
- **The method signatures** of `Conclude` and `FireEvent`, which gain trailing optional parameters, so the positional calls in `Test.Bridge.Decide` still work.
- **`release/standalone-bridge.sh`**.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. The lead runs `shard lane-a` and `shard lane-b` forward, then both with `--reverse`.

**Mutations to demonstrate (Rule 19)**, one or more per AC. Record each as `mutation: <change> -> <test went red>`.

| AC | Change | Test that goes red |
| --- | --- | --- |
| AC1 | `InputTokens` = the prompt delta only | `Bridge.Usage.TestFromStats`, `Agent.Decide.TestUsageDecide` |
| AC1 | The row written by `Conclude` instead of the runner | `Agent.Decide.TestTimer` (no late row), `TestCostOfFailedTurn` |
| AC1 | The row written only when `Chat` returns | `Agent.Decide.TestCostOfFailedTurn` |
| AC1 | The delta ignores `before` | `Bridge.Usage.TestFromStats` |
| AC2 | The cache write priced at the input rate | `Bridge.Usage.TestCost` |
| AC2 | `>` replaced by `>=` at the long-tier threshold | `Bridge.Usage.TestCost` (largest 100,000) |
| AC2 | `SeedPrices` rewrites an existing row | `Bridge.Usage.TestSeedPrices` |
| AC3 | `Conclude` leaves the row's totals empty | `Bridge.Decide.TestTotals`, `Agent.Decide.TestUsageDecide` |
| AC3 | The totals taken from the runner's reply, not the rows | `Bridge.Decide.TestTotals` (two rows) |
| AC3 | `ResponseFromRow` without `CarryTotals` | `Agent.Decide.TestRepeat`, `Bridge.Decide.TestResponseFromRow` |
| AC3 | `DurationMs` not set | `Agent.Decide.TestUsageDecide` |
| AC4 | `eval` rows counted | `Bridge.Budget` (the New York day) |
| AC4 | The day bounded at UTC midnight | `Bridge.Budget` (the New York day), `Bridge.Time` |
| AC4 | The gateway's spend added on any date | `Bridge.Budget` (cap and gateway) |
| AC5 | The `$Data` check under the lock removed | `Bridge.Budget` (mark once: a second event) |
| AC5 | The `Lock` removed | `Bridge.Budget` (mark under the lock) |
| AC5 | The event fired before the node is set | `Bridge.Budget` (the probe sees no mark) |
| AC5 | `State` ignores the mark | `Bridge.Budget` (mark once: State) |

**Measured in planning** (`ocutalon-slot-a`, `OCUTALON`, `iris_server_info` build 154U; process-local, nothing kept):
- **`GetStats()` on a fresh session** has exactly these keys, all 0: `current_context_tokens`, `model_context_size` (200000), `total_cache_creation_tokens`, `total_cache_read_tokens`, `total_completion_tokens`, `total_interactions`, `total_llm_duration_ms`, `total_prompt_tokens`, `total_reasoning_tokens`, `total_tool_calls` and `total_tool_duration_ms`. So there is no split of cache writes by TTL.
- **A `Chat` that throws before any reply** still allows a `GetStats()` read, and every value stays 0. The throw was a refused connection to `127.0.0.1:9`, which raised `<%AICore>ProviderError ... error sending request`.
- **Local to UTC.** `$ZDateTime($ZDateH(d,3)_",0",-3)` converts local midnight to UTC (`$ZDateTimeH(h,-3)` converts the other way). In `America/New_York`:
  - 2025-03-09 → 05:00Z, 2025-03-10 → 04:00Z, 2025-11-02 → 04:00Z and 2025-11-03 → 05:00Z;
  - `Data.Time.ToLocal` of each gives `d`T00:00:00.
- **A midnight that does not exist.** In `America/Havana` (2025-03-09) and `America/Santiago` (2025-09-07), the same form gives the day's first instant, local 01:00.
- **Other zones.** `Asia/Kolkata` 2025-03-09 → 2025-03-09T05:30Z in the other direction, and an unset zone is UTC.
- **Timestamps.** `$ZDateTimeH("<YYYY-MM-DD hh:mm:ss.fff>",3)` keeps the milliseconds: a 250 ms `Hang` measured 258 ms.
- **Rounding.** `$Number(0.0003441249,6)` is .000344, and `+"abc"` is 0.

**Residual risks:**
- `State` scans the whole `Usage` table (decision 16).
- The "largest request is the last" claim is an inference (decision 5).

## Clarification Record

**For the veto window** (not blocking; recommended as planned):
- **`Decide`'s three budget settings:** new stored properties of the business process (slots 5 to 7, appended by the compiler), a schema append.
- **The day's mark** `^OcuTalonBP.UsageCapped(day)` (decision 14): new stored data in the private database.
- **What the rows hold:**
  - the runner now writes `Usage` rows, also for a thrown call that spent tokens (decision 6);
  - a `Decision` row carries the totals, with "" for an unknown cost (decision 7);
  - the two `Price` rows are seeded (decisions 2, 3 and 11).

**For the lead (ruling recommended, not blocking):**
- **Decision 1:** AC5's two triggers and its both-paths live test move to Story 1.6 (veto window, item 7). No release gate depends on which of these two Epic 1 stories carries them. The bullet for Story 1.6 and the staging alternative are in decision 1.
- **Decision 2:** the 1-hour cache-write rate is not stored, against AC2's seed clause and AD-19's "cache-write tiers", because Lane B's pin of `Price` allows one column and no consumer exists. The amendment and the alternative are in decision 2.
- **Decision 3:** Sonnet's cache rates are inferred and no long tier is seeded for it.

**Ruled at spec validation** (Epic 1 runner, 2026-10-22, unattended; the owner may reverse a veto ruling through the inbox):
- **Decision 1 (AC5's triggers and both-paths test move to Story 1.6):** `category=veto`, kept as planned (inbox U-16). `epics.md` is amended: Story 1.4's last criterion pins `MarkCapped`, and Story 1.6's precheck criterion gains the bullet that both `daily_cap` paths call it, with the both-paths mock test. The staging alternative is the reversal.
- **Decision 2 (only the 5-minute cache-write rate):** `category=veto`, kept as planned (inbox U-17). `epics.md`'s seed clause is amended (Rule 5, apply and report); AD-19's "cache-write tiers" is read as Epic 0's merged one-column schema, and the spine is not edited. The reviewer reviews against this ruling.
- **Decision 3 (Sonnet's derived cache rates, no long tier for it) and the stored-data items above** (`Decide`'s three budget settings, `^OcuTalonBP.UsageCapped`, the `Usage` and `Decision` row contents, the two seeded `Price` rows): `category=veto`, kept as planned (inbox U-18). A Sonnet long tier is moot while Story 1.9 refuses requests over 100,000 tokens.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
