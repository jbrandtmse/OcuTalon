---
title: 'Story 17.4: Apply model, price, budget and zone changes through the bridge'
type: 'feature'
created: '2026-11-05'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-17-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/33-1-task0-zone-measurement.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 33.1 left the rest of `OcuTalon.Bridge.Settings` as stubs: `Values`, `Check`/`Set`, `SetPrice`, `TestRequest` and `TestAnswer`. It also left `Bridge.Time`'s `Zone`/`SetZone`/`Apply` as stubs. So an admin cannot change:
- the token budget per decision, the daily cost cap or the instance zone;
- a model's prices;
- and cannot test a model.

`Lane B`'s `SettingsOps` already calls `Values`, `Check`, `Set` and `Time.Zone`, and its budget and time-zone routes answer 501. `Decide` also reads `DecisionTokenBudget` from its in-memory property, so a new budget would apply only after a restart.

**Approach:** Build the remaining bridge settings APIs and the run-time zone, the way the spine fixes them (AD-18, AD-19, AD-20):
- the allow-list values apply at the next decision with no restart. `Decide` reads the budget as written; `Budget` already reads the cap live; `Time.Apply` switches the process zone.
- prices change only later usage rows;
- the model test is one request of the agent's own kind, through `Decide`, on the chosen (first) model;
- a provider change drops endpoint fields that belong to another provider (DW-758).

## Boundaries & Constraints

**Always:**
- **The allow-list.**
  - `Check(name, value)` and `Set(name, value, .old)` accept only these three names:
    - `DecisionTokenBudget`: a whole number from 0 to `Decide.#MAXREQUESTTOKENS` (100000). 0 is off.
    - `DailyCostCapUSD`: a number from 0 to 10000 with at most two decimals. 0 is off, the local default.
    - `InstanceZone`: "" for the container's `TZ`, or an IANA name of at most 64 characters that matches the spine's pattern (letters, digits, `/`, `_`, `-`, `+`, no `..`) and names a file, not a folder, under `/usr/share/zoneinfo/`.
  - Any other name is refused, `TimerSeconds` included (the bridge timer stays at or under 110 s; only `Timeouts.Apply` changes it).
  - A value that holds `@{` is refused, and so is any value off these bounds. The reason is plain English and never echoes the value. A refusal writes nothing.
- **Set**
  - It writes the `Decide` System Default Settings row:
    - for the two numbers, as their canonical number text (`7.50` is stored as `7.5`) through `Settings.WriteRow` (write, then read back);
    - for `InstanceZone`, only through `Time.SetZone`.
  - `old` is the value it replaced, as a scalar string. `SettingsOps` audits it and may hand it back to `Set` to put the value back, so every `old` passes `Check`.
- **Values()** returns:
  - `DecisionTokenBudget`, `DailyCostCapUSD` and `InstanceZone` as strings, read the way `Decide`, `Budget` and `Time.Zone()` read them;
  - `agents`: for each first runner item (`TriageAgent`, `DiagnosisAgent`, `ChatAgent`), `{provider, model, secondProvider, secondModel}`. Here:
    - `model` is `AgentRunner.ResolveModel` of the item;
    - each provider is the provider-table row that lists the model;
    - the second pair is "" when `RetryItem` is "".

  It never reads a Config Store entry and never holds a key.
- **Applied within a minute, with no restart, in the jobs that use the values:**
  - `Decide` prechecks with `DecisionTokenBudget` (and `RequestTokenLimit`) as written now when it runs as its own production job. An instance in another process keeps its property.
  - `Budget.State()` reads the cap as today.
  - `Bridge.Time.ToLocal`, `LocalDate`, `DayStartUtc` and `DayEndUtc` call `Apply()` first. So the cap's day ends at midnight in the new zone.
- **The daily cap's mark.**
  - A `Set` of `DailyCostCapUSD` that leaves the cap off (0) or above the day's spend removes today's capped mark (`Budget.Unmark`), so cost fallbacks stop from the next decision.
  - A cap at or below the spend leaves the mark.
  - `Budget.State`'s rule is unchanged (AD-20).
- **The zone (AD-18).**
  - `InstanceZone` is a `Decide` host setting (category Bridge). It is read only through `Time.Zone()` (`Ext.Accessor.ValueFor`; "" when unreadable) and written only through `Time.SetZone(name)`, which refuses what `Check` refuses.
  - `Apply()` keeps, process-private:
    - the name it last applied;
    - the inherited zone, which `$SYSTEM.Process.TimeZone(name)` returns at the first apply (`-1` is "").
  - It calls `Process.TimeZone` only on a change, and puts the inherited zone back when the name becomes "".
  - A process that never applied a zone and reads "" does nothing.
  - Never `$ZTIMEZONE`, never Python.
- **SetPrice(model, prices, .old).**
  - It changes only an existing `Bridge.Data.Price` row.
  - `prices` holds one or more of these keys:
    - `input`, `output`, `cacheRead`, `cacheWrite`, `longInput` and `longOutput`: numbers from 0 to 10000 with at most 4 decimals (the `SCALE`);
    - `longThresholdTokens`: a whole number from 0 to 10,000,000.
  - Keys that are left out keep their values.
  - These are refused: an unknown key, a value with `@{`, a negative or non-numeric value, and an empty object.
  - `old` is all seven values as they were.
  - Cost is fixed when a `Usage` row is written (`Usage.FromStats`), so earlier rows keep their cost, and totals stay the sums of their rows.
- **The model test.**
  - `TestRequest(agent, .request)` takes a first runner item and builds one `Bridge.Msg.Request`:
    - of that runner's kind (`Decide.#RUNNERS`);
    - `Provenance` `untrusted`, `OwnerRef` `instance`, `Channel` `system`, `SessionMode` `fresh`;
    - `ItemId` `test.` plus 17 characters of `Ids.NewRef()` (a `.` never occurs in a `NewRef`);
    - `Input` the code-written `TESTINPUT` and `Summary` `TESTSUMMARY`.
  - `Decide` never sends the second-model retry for a request that `Settings.IsTest(request)` names. Re-sends on a rate limit still go to the same model.
  - `TestAnswer(response, durationMs)` returns `{answered, seconds, reason}`:
    - `answered` is a boolean: true only for a reply that is not a fallback and not busy;
    - `seconds` is `durationMs` / 1000, to one decimal;
    - `reason` is "" when answered, the response's `FallbackReason` when there is one, and otherwise `error` (no response, busy, no reason).
  - The test's usage rows have owner `instance`. No sampling key is set, and no key is returned.
- **DW-758, the endpoint fields.** `base_url`, `http_config.custom_headers` and `http_config.tls` belong to the entry's `model_provider`.
  - A `ConfigStore.Merge` in the model shape that changes the provider removes them.
  - `Providers.Resolve` builds the resolved provider's in-memory config without them.
  - The Provider install step writes the endpoint overrides only on an `anthropic` entry (AD-19's overrides are the Anthropic endpoints of CI and the online demo).
  - One helper, `ConfigStore.DropEndpoint(details)`, does it for all three.
- **Seed values.** Every value this story accepts survives a restart and an upgrade:
  - no install step writes `DecisionTokenBudget` or `InstanceZone`;
  - `Public` seeds `DailyCostCapUSD` locally only when it is absent;
  - `SeedPrices` skips existing rows;
  - `SeedModels` skips existing rows.
- **General rules.**
  - The bridge names no OcuTalon package (AD-2).
  - Storage is append-only: `Decide`'s compiler-generated `Storage` block gains the `InstanceZone` slot (AD-5).
  - Source is ASCII, and comments state contracts (Rule 14).
  - Tests use the CI mock on the Anthropic path, in throwaway stacks.

**Never:**
- Edits to a Lane B class or test (U-177): `Core/SettingsOps.cls`, `Data/Time.cls`, `Test/Core/**`, `Test/Web/**`, `Test/Data/**`.
- Edits to these contended paths:
  - `Test/Bridge/Decide.cls` (Epic 40), `Test/Contract/Ac.cls` (Epic 34) and `Bridge/Ext/**`;
  - `Bridge/Msg/Enum.cls`, `ci/units.sh`, `src/short-names.tsv` and the spine.
- A real provider, a real key or network access. A `supported` flag set for a provider other than anthropic. Any text that says a provider other than Anthropic runs decisions (U-288, DW-755).
- A change to the timer rules of AD-8 or to `Timeouts.RetryTimer` (DW-647 is declined; see Design Notes). A correction of stored Price rows on upgrade (DW-757 is declined; see Design Notes).
- `Data.Time` calling `Apply` (Story 18.2, Lane B).
- Any destructive run on `ocutalon-slot-a`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Budget lowered | `Set("DecisionTokenBudget","1",.old)`, then a decide (no restart) | `old` is the earlier text (`"0"`). `Values().DecisionTokenBudget` is `"1"`. The next decide is a `budget` fallback and the mock saw no request. After `Set(...,"0")` the next one answers. | none |
| Cap below spend, then off | A fixture Usage row of today costs 1; `Set("DailyCostCapUSD","0.5")`; decide; `Set(...,"0")`; decide | `Budget.State()` reports cap 0.5 and capped. The decide is a `daily_cap` fallback and marks the day. After the cap is turned off the mark is gone, State's `capped` is false, and the next decide answers. | none |
| Cap raised | Capped and marked at 0.5; `Set(...,"5")` (above the spend) | Unmarked; the next decide answers | none |
| Refused value | Each name with `@{env:X}`, `-1`, `1.5` (budget), `100001`, `7.555`, `10000.01`, `abc`, `Mars/Olympus`, `America` (a folder), `../etc`, a name of 65 characters; names `TimerSeconds`, `Nope` | An error with a plain reason that holds no value. The `Decide` rows, the capped mark and the process zone are unchanged. | error status |
| Zone and the cap's day | Zone A `Pacific/Pago_Pago`, zone B `Pacific/Kiritimati`. A fixture Usage row (cost 1) at a UTC time inside A's today and outside B's. Cap 0.5. `SetZone(A)`: decide. `SetZone(B)`: decide. | The decide in A is `daily_cap`. The decide in B answers (the row is not in B's day). `State().resetsAt` is `DayEndUtc` in each zone. | none |
| DST comparison, changed zone | `SetZone("America/New_York")`, then the half-hourly walk across the 2025 changes | `Bridge.Time.ToLocal` and `LocalDate` equal `Data.Time.ToLocal` at every instant (290). After `SetZone("")` the inherited zone is back. | none |
| Price edit | `SetPrice("claude-haiku-5-5", {"input":0.2,"output":1},.old)` between two decides | The earlier rows keep their `CostUSD`. The later rows are priced at 0.2 and 1. Each `Decision.CostUSD` equals the sum of its rows. `old` holds the seven earlier values. | none |
| Price refused | Unknown model; `{}`; `{"input":-1}`; `{"input":"@{x}"}`; `{"input":0.12345}`; `{"bogus":1}` | An error with a plain reason. The row is byte-equal before and after. | error status |
| Model test | `TestRequest(a,.r)` for each of the three agents, sent to `Decide` synchronously, then `TestAnswer(resp, ms)` | `{answered: true, seconds: >0, reason: ""}`. One mock request for the `DecisionRef`, with no `temperature`, `top_p` or `top_k`. Its Usage rows have `OwnerRef` `instance`. The answer and `r` hold no key. | none |
| Model test, failing model with a second model | `SetModel("TriageAgent","anthropic","claude-sonnet-5-5",1)`, the mock armed to refuse, then the test | `{answered: false, reason: "refusal"}` and exactly one mock request (no retry). The same request with an ordinary `ItemId` is retried, as in Story 17.2. | none |
| DW-758 | An entry `{anthropic, placeholder, base_url, custom_headers, tls}`. (1) Merge `{openai,@{env:OPENAI_API_KEY}}`. (2) Resolve from that entry with `ZzProviders`. (3) The Provider step with an openai entry and `OCUTALON_MODEL_BASE_URL` set. (4) Merge `{anthropic,...}` onto an anthropic entry. | (1) to (3): no `base_url`, `custom_headers` or `tls`; `request_timeout_secs` and `retry` kept. (4): the endpoint fields are kept. | none |
| DW-727 | `Timeouts.Apply(60)` | The first runners' entries derive from 60 (attempt 25). The retry entries derive from `RetryTimer(60)` = 50 (attempt 20). `Apply(100)` still gives the retry entries 12 (the existing pin). | none |
| Restart keeps values | Set all three values, `SetPrice`, `SetModel(...,0)`; then `Bridge.Installer.Run()`, `Install.Step.Public.Run()`, `Install.Step.Provider.Run()` and the Production step's model seeding | Every value, the price row, the entry's provider pair and the Model row are unchanged | none |

</intent-contract>

## Code Map

**Bridge (Lane A, Epic 17 footprint, not contended)**
- `src/bridge/cls/OcuTalon/Bridge/Settings.cls`:
  - stubs: `Values` (:54), `Check` (:60), `Set` (:66), `SetPrice` (:167), `TestRequest` (:174), `TestAnswer` (:181);
  - the class doc (:1-25) is the contract; rewrite its "still stubs" sentence;
  - reuse: `CheckModel`'s reason style (:79-104), `Agents()` (:187), `WriteRow` (:218, Private today), `RowState`/`PutBack` (:230/:238).
- `src/bridge/cls/OcuTalon/Bridge/Time.cls`:
  - stubs `Zone`/`SetZone`/`Apply` (:24-39); the class doc (:14-18) says they are stubs;
  - `ToLocal`, `LocalDate`, `DayStartUtc`, `DayEndUtc` (:49-91) gain `Do ..Apply()` first.
- `src/bridge/cls/OcuTalon/Bridge/Budget.cls`:
  - `State` (:41) is unchanged;
  - `MarkCapped` (:104) is the model for `Unmark(day)`: the same lock, killing `^OcuTalonBP.UsageCapped(day)`.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - `SETTINGS` (:135) and the properties (:214-253): add `InstanceZone`;
  - `SettingText` (:446-451): property first today, which is why `Test.Agent.Decide.TestPrechecks` restarts Decide (:1286-1288);
  - `TryRetry` (:646-685): the retry gate at :655;
  - `#RUNNERS` (:138), `#MAXREQUESTTOKENS` (:148);
  - `Admit` (~:780-800) checks `Kind`, `Provenance` and `OwnerRef`, never `Channel`;
  - the `Storage` block's last slot is `FirstSeconds` (Value 18, :1779).
- `src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls`: `Merge` (:40-66; the model shape removes `model` at :59), `ModelShape` (:172), `Details` (:96).
- `src/bridge/cls/OcuTalon/Bridge/Providers.cls`:
  - `Resolve` (:104-140) copies the entry's details and replaces only `model_provider`/`api_key` (:128-130);
  - add `ProviderOf(model)` for `Values`.
- `src/bridge/cls/OcuTalon/Bridge/Data/Price.cls` (read only): properties (:10-31; `SCALE = 4`), `ModelIndex`, and `Cost` (it guards a zero input rate, :47).
- `src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls` (read only): cost is fixed at write time (`FromStats` :129, `FromEstimate` :153); `Totals(decisionRef)` (:178).
- `src/bridge/cls/OcuTalon/Bridge/Timeouts.cls` (read only): `Apply` already merges `Derive(RetryTimer(timer))` into the retry entries (:126). `RetryTimer` (:47).
- `src/bridge/cls/OcuTalon/Bridge/Ext/Accessor.cls` (read only, contended):
  - `ValueFor(setting, production, item="Decide", .sc, target="Host")` gives "" on any error;
  - `WriteDefault(production, item, setting, value, description)`.
- `src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls` (read only): `ResolveModel(item, production)` (:52).

**Install (Lane A)**
- `src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls`:
  - `Details` (:102) writes `base_url` (:105), `custom_headers` with the mock key (:107-110) and `tls` (:113);
  - `KeepChosen` (:151) keeps a valid chosen pair;
  - `WriteRunner` (:164).
- Read only:
  - `Install/Step/Public.cls` `RunLocal` (:76-83) seeds `DailyCostCapUSD` 0 only when nothing resolves it;
  - `Install/Step/Production.cls` `SeedModels` (:209);
  - `Bridge/Installer.cls` `SeedPrices` (:84) skips existing rows.

**Lane B callers (read only, U-177)**
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls`:
  - `Values()` (:253) passes `bridge` through and adds `instanceZone` from `Time.Zone()`;
  - `BridgeCurrent` (:455-460) reads `Values().%Get(name)` (`InstanceZone` from `Time.Zone()`) and compares strings (:388);
  - `Check`/`Set` (:463-472): 5003 means `not_built`, any other error means `refused`, and the reason is discarded;
  - `old` goes to the audit entry as `from` (a string, :99, :411) and back to `Set` in `PutBack` (:437);
  - Sections `budgets` and `time-zone` (:185-205).
- `Web/Api.cls`: `POST /v1/settings/budgets` (:159) and `/time-zone` (:162) go through `SaveSection` (:738), a `SaveSettings` command with origin `web_admin`.

**Tests and fixtures to extend**
- `Test/Bridge/SettingsStubs.cls` (Lane A):
  - `TestSettingsStubs` (:15-35), `TestNothingWritten`/`CallEverything` (:37-81, snapshot `State` :85-103) and `TestTimeStubs` (:46-59) assert the stubs;
  - it keeps the "no RetryItem row anywhere" assertion, which `SecondModel` (:5) relies on.
- `Test/Bridge/Time.cls`:
  - `TestAgreesWithDataTime` (:33-61) sets `Process.TimeZone` itself; 290 instants per zone (:53);
  - the scanner `TestZoneCase` (:285-304) and `TestZoneHooksCallSuper` (:312-335).
- `Test/Bridge/ZoneCase.cls`: saves and restores the process zone (:13-35).
- `Test/Bridge/Budget.cls`:
  - in process; `Put` (:623); `TestMarkOnce` (:297-326) pins the mark with cap 0, which stays (State unchanged).
- `Test/Bridge/Timeouts.cls`:
  - `TestApplyRetryEntries` (:362-398) pins `Apply(100)`, giving retry entries 12;
  - `TestRetryTimer` (:311).
- `Test/Bridge/Usage.cls`:
  - `TestFromStats` (:91), `TestTotals` (:288);
  - `Snapshot`/`Remove`/`Restore` of Price rows (:381-395).
- `Test/Bridge/ConfigStore.cls`, `Test/Bridge/Providers.cls` (`TestResolvedShadowRunner`, `TestResolvedEqualsDirect`) and `Test/Install/Provider.cls` (`TestKeepsChosenProvider`).
- `Test/Bridge/ModelChange.cls`:
  - extends `Test.Core.InProduction`;
  - `OnAfterOneTest` restore order (:96-146), `Prepare` (:504), `Remember` (:523), `AtDefault`.
- `Test/Agent/Decide.cls`: `Prepare` (:1460), `Case` (:1486), `Arm` (:1600), `Put` (:1623); `TestPrechecks` (:1278) is the budget and cap pattern.
- `Test/Agent/RunnerFixture.cls`:
  - `NewRequest` (:333; owner `instance` by default), `Run`/`Send` (:319-326, :435-441), `Ask` (:351);
  - `UsageIds` (:1174), `AddUsage` (:1186), `Totals` (:1204);
  - `PutDefault`/`RememberDefault`/`RestoreDefaults` (:737-803), `UseTimer`/`RestoreTimer` (:809/:822), `Restart` (:118).
- `Test.Contract.Mock`: `Arm(marker, remaining)` (:439), `LogMark`/`LogSince` (:471/:484).
  - The mock answers an unmarked request by its `x-ocutalon-mockkey` default:
    - `scenarios/A/triage.json`;
    - `diagnosis.json` (a `read_failed_messages` call, then act);
    - `chat.json`.
  - Markers available to `Arm`: `refusal`, `provider-error`, `usage-decide`, `usage-turn`, and others.
- `SecondModel.AssertAnswered` (:702-705): the SQL sum of a `DecisionRef`'s Usage rows. Extend it with `CostUSD`.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0 (measure)**, on the warm throwaway; slot A is read-only. Record the results under `## Design Notes`.
  - (a) In a running `Decide` job, the job's own config name (`$$$JobConfigName`) equals `..%ConfigName`. In the test process, a `Test.Bridge.ZzDecide` built with `%New("Decide")` gets "".
  - (b) With `InstanceZone` declared on `Decide`, `Accessor.ValueFor("InstanceZone")` behaves as follows, in a `Decide` job and in the test process:
    - it reads a newly written row;
    - with no row, it reads "" with an OK status.
  - (c) For each of the three agents, the request that `TestRequest` builds:
    - passes `Admit`;
    - answers through the mock's per-agent default with no fallback. If `diagnosis.json` does not answer an `instance`/`untrusted` request, choose an existing one-reply scenario for `Mock.Arm` and record it.
  - (d) The value that `$SYSTEM.Process.TimeZone(name)` returns at the first apply in a job with `TZ` unset, and with `TZ=America/New_York`.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - add `Property InstanceZone As %String(MAXLEN = 64)` and `InstanceZone:Bridge` in `SETTINGS`;
  - `SettingText` returns `Ext.Accessor.ValueFor(name, "", ..%ConfigName)` when the process is the item's own job (Task 0 (a)) and that read is OK; otherwise it returns today's property-first value;
  - `TryRetry` sends no retry when `Settings.IsTest(request)` (the gate at :655);
  - update the class doc (the retry list, the settings);
  - commit the compiler-generated `Storage` block with the new slot (AD-5; never hand-edit it).
- [ ] `src/bridge/cls/OcuTalon/Bridge/Time.cls`:
  - `CheckZone(name)`: the pure refusal;
  - `Zone()`: `ValueFor("InstanceZone")`, "" on error;
  - `SetZone(name)`: `CheckZone`, then `Settings.WriteRow` on `Decide`;
  - `Apply()`: the Always rule. Its process-private state is in `^||OcuTalon.Bridge.Time`;
  - call `Apply()` first in `ToLocal`, `LocalDate`, `DayStartUtc` and `DayEndUtc`;
  - rewrite the class doc.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Budget.cls`: add `Unmark(day)`. It works under `MarkCapped`'s lock, returns 1 when it removed the mark, and never throws. Update the class doc.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Settings.cls`:
  - build `Values`, `Check`, `Set`, `SetPrice`, `TestRequest`, `TestAnswer` and `IsTest(request)` (Always);
  - add the parameters `TESTITEMPREFIX` (`test.`), `TESTINPUT` and `TESTSUMMARY` (texts under Design Notes);
  - make `WriteRow` callable by `Time.SetZone` (drop `Private`);
  - `Set("DailyCostCapUSD")` calls `Budget.Unmark` when the new cap is 0 or above `Budget.State().spent`;
  - rewrite the class doc (nothing is a stub now).
- [ ] `src/bridge/cls/OcuTalon/Bridge/Providers.cls`:
  - add `ProviderOf(model)` (the row that lists the model, or "");
  - `Resolve` calls `ConfigStore.DropEndpoint` on the copied details (DW-758);
  - update the doc.
- [ ] `src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls`:
  - add `DropEndpoint(details)`, which removes `base_url`, `http_config.custom_headers` and `http_config.tls`;
  - `Merge` in the model shape calls it when the entry's `model_provider` differs from the new one (DW-758);
  - update the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls`: after `KeepChosen`, a details object whose `model_provider` is not `anthropic` goes through `ConfigStore.DropEndpoint` (DW-758). Update the doc.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/ZoneCase.cls`:
  - `OnBeforeOneTest` remembers and deletes the active production's `InstanceZone` row of `Decide`, and clears `^||OcuTalon.Bridge.Time`;
  - `OnAfterOneTest` puts the row back as it was, clears the process state, then restores the process zone as today;
  - every subclass stays hermetic against a stray zone row (Rule 19).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Time.cls`:
  - add `TestAgreesWithDataTimeInstanceZone`, the "DST comparison, changed zone" row, by `SetZone` and not `Process.TimeZone`;
  - add `TestApplyRule`: no apply while never applied and ""; an apply on a change only; the inherited zone put back on "".
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/SettingsValues.cls` (new, in process, extends `ZoneCase`). Every test restores what it wrote, with the `RunnerFixture` default helpers and the Price snapshot of `Usage`.
  - `TestCheckRefusals`: the "Refused value" row, nothing written;
  - `TestSetAndValues`: each name; `old`; canonical text; `Values` keys and types; the `agents` shape from `ResolveModel`/`ProviderOf`; no `sk-`, `AIza` or `@{` in the JSON;
  - `TestPutBack`: `Set(name, old)` restores each value;
  - `TestUnmark`;
  - `TestSetPrice` and `TestSetPriceRefused`, the price rows;
  - `TestRequestShape` (each agent: kind, provenance, owner, channel, mode, `ItemId` form, `IsTest`; an unknown agent refused);
  - `TestAnswerShapes` (an answer, a fallback, `Busy`, "", rounding).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/SettingsApply.cls` (new, live; on the `ModelChange`/`Agent.Decide` pattern; hooks call `##super`):
  - `TestBudgetNextDecision`, `TestCapBelowSpendThenOff`, `TestCapRaised`, `TestZoneMovesTheCapDay`;
  - `TestPriceAppliesToLaterRows`;
  - `TestModelTestEachAgent`, `TestModelTestNotRetried`;
  - `TestRestartKeepsValues`;
  - `TestIntegrationSettingsOps` (Rule 1): submit `SaveSettings` (slug `budgets` `{DecisionTokenBudget: 1, DailyCostCapUSD: "0.5"}`, then `time-zone` `{InstanceZone: "Pacific/Kiritimati"}`) through `OcuTalon.Core.Commands.Submit` with origin `web_admin`, as `Web/Api.SaveSection` does. Then:
    - the result is done;
    - `SettingsOps.Values()` shows the three values;
    - one `Settings` audit entry per value, with `from` = `old`;
    - the next decide falls back with `budget`;
    - set everything back the same way.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/SettingsStubs.cls`: replace the stub assertions with the refusal contract, keeping the class name so that its references stand.
  - `CallEverything` makes only refused calls (`@{`, off the allow-list, unknown model or agent, bad zone);
  - `TestNothingWritten` keeps its snapshot, 0 `InstanceZone` rows and 0 `RetryItem` rows;
  - `TestTimeStubs` becomes "a refused `SetZone` writes nothing and leaves the zone".
  - Rewrite the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Timeouts.cls`: in `TestApplyRetryEntries`, add `Apply(60)`, the "DW-727" row: the first entries get attempt 25 and the retry entries attempt 20.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/ConfigStore.cls`: add `TestProviderChangeDropsEndpoint`, legs (1) and (4) of the DW-758 row.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Providers.cls`: leg (2) in `TestResolvedShadowRunner`. Update `TestResolvedEqualsDirect` so that both configs hold no endpoint field.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/Provider.cls`: leg (3) in `TestKeepsChosenProvider`.
- [ ] Search `src/ocutalon/cls/OcuTalon/Test` (Lane A areas) and `docker/tests` for assertions on the shared surfaces in `## Verification` and update the Lane A ones (Rule 19). Report every Lane B assertion that turns red under Design Notes; never edit it.

**Acceptance Criteria:**
- Given the bridge APIs that `SettingsOps` calls, when a value is submitted, then each API checks it and refuses a value holding `@{` or off the allow-list with a plain-English reason, changing nothing. The checks are:
  - a supported provider whose key is set, and a model of the table (17.3's `CheckModel`);
  - a non-negative price;
  - a budget or cap within the bounds;
  - a known zone.
- Given accepted values, when the install steps run again (a restart or an upgrade), then every value is kept, and no API changes the bridge timer.
- Given a price edit, when later model requests are recorded, then their usage rows use the new rates, earlier rows keep their cost, and each decision's total equals the sum of its rows.
- Given a local install with the cap off, when an admin lowers the token budget or sets a cap below the day's spend through `Set`, then the next decision, with no restart, takes the `budget` or `daily_cap` precheck fallback, and `Budget.State()` reports the new cap. Turning the cap off again stops cost fallbacks from the next decision.
- Given **Test** for an agent, when the model test runs through `Decide`, then:
  - one request goes to that agent's chosen model, never retried on the second model;
  - `TestAnswer` gives the seconds taken, or a fallback reason;
  - the usage is recorded under `instance`;
  - no sampling parameter is sent, and no key is returned.
- Given a zone saved through `Set("InstanceZone")`, when the next conversion runs in any job, then `Bridge.Time` uses the new zone with no restart, the cap's day ends at midnight in it, and the DST comparison with `Data.Time` passes with a changed zone.
- DW-727: given `Timeouts.Apply(T)`, when the entries are merged, then the retry runners' entries hold exactly `Derive(Timeouts.RetryTimer(T))`, pinned at T = 60 and T = 100.
- DW-758: given a provider change or a resolution to another provider, when the entry or the in-memory config is built, then no `base_url`, header or TLS block of another provider remains, the timeouts stay, and a restart does not put them back.
- Integration (Rule 1): given Lane B's unchanged `SettingsOps`, when a `SaveSettings` for `budgets` and `time-zone` is submitted as the web route does, then the result is done, the values are applied and audited with `from` = `old`, and the next decision uses them.
- [Owner] U-288: no text this story adds claims a provider other than Anthropic runs decisions. Record the check in the review's `## Decisions`.

## Spec Change Log

- 2026-11-05 lead spec gate: rulings U-292, U-293 (veto), DW-647 by-design, DW-758 convention; two items with the orchestrator.

## Review Triage Log

## Design Notes

**Lead rulings at the spec gate (2026-11-05, runner A).** (1) The model Test request's two texts are accepted as written (veto U-292). (2) DW-757: the one-time correction is ruled IN (veto U-293): `SeedPrices` corrects the `claude-sonnet-5-5` row's cache-read to 0.10 only when the row still holds exactly the old seeded values; an edited row is never touched; earlier `Usage` rows keep their cost. Turn the declined DW-757 into a Tasks & Acceptance item with a pinning test (edited row untouched; never-edited row corrected; fresh install 0.10) and a mutation. (3) DW-647 is closed by-design at the spec gate (AD-8's timer split stands; the 110 s limit holds); keep the DW-727 test. (4) DW-758's convention (endpoint overrides belong to Anthropic entries only) is written into the spine's Conventions by the lead. (5) WITH THE ORCHESTRATOR before implement: the two Lane B tests (`Test.Web.SettingsApi.TestBridgeRoutesAre501`, `Test.Core.SettingsSave.TestBridgeStub`; U-177) and the AD-8 addition (a model Test request is never retried on the second model). Implement does not start until both are ruled.

**Governing ADs (Rule 6).**
- AD-2: the bridge names no OcuTalon package.
- AD-5: the `Decide` storage is appended; the timer stays at or under 110 s.
- AD-6: the model test goes through `Decide`; only runners call `Chat`.
- AD-8: the retry, with the test not retried (see "For the lead"), and the timers. DW-647 is declined.
- AD-18: the zone source, `Zone`/`SetZone`/`Apply` and the DST test.
- AD-19: the allow-list, the seed values, the bridge settings APIs, the placeholders only, and the endpoint overrides (DW-758).
- AD-20: prices fixed at write time, totals as sums, the cap's day, and the mark.
- AD-22: the mock and throwaways.
- AD-29: lanes.

Two points touch an AD's Rule, and both go to the lead rather than being settled here:
- The model test's exclusion from the second-model retry extends AD-8's never-retried list. FR-39 and this story's AC require it. It is planned and built, and it stays open to the lead's veto (see "For the lead").
- DW-647 would need AD-8's timer formulas amended, so it is declined.

No other AC touches an AD's Rule.

**Ledger inbox (Rule 17).**
- **DW-727**, addressed. `Timeouts.Apply` already gives the retry entries `Derive(RetryTimer(T))` (`Timeouts.cls:126`), and the spine says so (AD-8, amended 2026-11-05). The Apply(60) row and its AC pin the unclamped formula beside the existing Apply(100) clamp pin.
- **Declined DW-647**: making T2 agree with the retry entry's worst case needs an AD-8 amendment (veto window U-9), which this story may not decide. AD-8 fixes both formulas: T2 = min(T, 110 - TimerFor), and the retry entries use `Derive(max(12, min(T, 110 - T)))`. Only `ChatAgentRetry` is affected, because only a turn is flagged; decide and diagnose have T1 = T. At T = 60 a flagged turn gets T2 = 30, while the entry's attempt is 20 s and its worst case 42 s. They agree only for T <= 45. The options for the lead:
  - **(a)** `ChatAgentRetry`'s entry derives from the least T2 of any turn: `max(12, min(T, 110 - min(110, T + SUMMARIZERSECONDS)))`, so 30 at T = 60. Every chat retry then has 10-second attempts, which can cut a long reply that would have fit in T2 = 50.
  - **(b)** Close as by-design. The 110-second bound holds, and a retry that outlives T2 is counted for cost and dropped (AD-8).

  Recommended: (b), because (a) shortens every chat retry to cover a rare one.
- **Declined DW-757** (a stored-data change, veto window U-3; recorded for the lead and not built). `Price` has no "edited" mark, so a never-edited seeded row cannot be told apart from an edit. The options:
  - **(a)** `SeedPrices` corrects a `claude-sonnet-5-5` row whose seven values all equal the earlier seed (cache read 0.2) to the current seed, once. An admin's identical edit would be "corrected" to the right value, which is harmless.
  - **(b)** Leave it. `SetPrice`, this story's price edit, is the admin's remedy once Story 18.3's page offers it.

  Recommended: (a), as a small follow-up if the lead approves.
- **DW-758**, addressed: the Always rule, the matrix row and its AC. The step half is a convention (the endpoint overrides belong to Anthropic entries). See "For the lead".

**Decided in-stage.**
1. **`Values()`** returns strings, which `SettingsOps.BridgeCurrent` compares as strings, plus `agents`. Each provider comes from the table by the model (`ProviderOf`), not from the entry: a web request's process may not read Config Store entries (AD-19: only production jobs do), and `SetModel` keeps the two consistent.
2. **Bounds.** The budget is 0 to 100000, because no request goes over `MAXREQUESTTOKENS`. The cap is 0 to 10000 dollars with two decimals, a sanity ceiling (inference: no local install needs more). Prices are 0 to 10000 per million tokens with 4 decimals (`SCALE = 4`), and the threshold is 0 to 10,000,000. Stored numbers are canonical text.
3. **`InstanceZone`** becomes a `Decide` property and `SETTINGS` entry. AD-18 names it "`Decide`'s host setting", and Story 33.1's probe declared it the same way. The appended storage slot follows the precedent of Story 17.2 (`RetryRunner`, `FirstSeconds`).
4. **The token budget applies with no restart.** `Decide` reads it as written in its own job, the pattern of the cap (`Budget`) and of the zone (AD-18: "never the item's in-memory property"). An instance in another process keeps its property, so `Test.Bridge.Decide` (contended, Epic 40) is untouched. Story 18.3's "through `Ens.Director.UpdateProduction`" is then not needed for the budget (Consumed-by).
5. **The mark.** `Set` of the cap removes today's mark when the cap goes off or above the spend. `State`'s rule (mark OR spend >= cap) stays, because AD-20 needs the mark for the online demo gateway's 403. The residual is a decision in flight that marks the day just after the cap was turned off: it stays capped until midnight, a window of milliseconds between the precheck and `RecordFallback`.
6. **`SetPrice`**:
   - edits existing rows only (every selectable model has one);
   - merges the given keys and refuses an empty object;
   - uses camelCase keys, because no Lane B caller exists yet (Story 18.3 adopts them).
7. **The model test.**
   - `agent` is the first runner item (17.3, Decided 1).
   - `Channel` is `system`, from the bridge enum.
   - The `ItemId` prefix marks a test without a new `Request` property, which would be a storage change.
   - Re-sends on a rate limit stay, because they go to the same model.
8. **`TestAnswer`'s `seconds`** has one decimal, because Story 18.3 shows "Answered in 1.2 s". A busy reply or a missing response gives `error`.
9. **`Apply`'s process state** is a process-private global. `ZoneCase` clears it and the zone row around each test.
10. **`SettingsStubs`** keeps its name (the refusal contract) so that references, and the shard's class list, stand.
11. **`Settings.WriteRow`** loses `Private` so that `Time.SetZone` reuses it (extend, don't copy).

**For the lead (veto window).**
- **AD-8 extension (U-9; Rule 20 spine write).** A model test is never retried on the second model. FR-39 says the button "checks that the chosen model answers", and the AC says "one minimal request". AD-8's retry would let the second model answer for the first, and `Decide` keeps no first-attempt reason that `TestAnswer` could report. If vetoed, `TestAnswer` can only say whether the retry runner answered (`Usage.Agent`), with no reason.
- **New texts visible in Visual Trace (U-5).**
  - `TESTINPUT`: "This is a connection test from the OcuTalon settings page. Nothing needs to be done: reply as briefly as you can."
  - `TESTSUMMARY`: "Model test from Settings".

  The refusal texts are bridge status texts, in `CheckModel`'s style. `SettingsOps` discards them, and its page shows only field names (Lane B words the page).
- **DW-758's step rule (Rule 20 candidate, an AD-19 convention).** The endpoint overrides are written only on an `anthropic` entry, and a resolution to Anthropic from another provider's entry uses Anthropic's default endpoint. Today this cannot happen: only Anthropic is supported, and resolution needs `ANTHROPIC_API_KEY`, which CI never sets.

**Needs the orchestrator (U-177, Lane B tests).** Building `Check`/`Set` makes two Lane B tests go red. Worse, each writes live bridge values into the shared throwaway and never puts them back: a 7.50 cap, a 5000 budget and the zone `Europe/Paris`, which then moves every `Bridge.Time` conversion of later tests.
- `Test.Web.SettingsApi.TestBridgeRoutesAre501` (:287-290; it expects 501 for `budgets` and `time-zone`);
- `Test.Core.SettingsSave.TestBridgeStub` (:303-312; it runs the real `SettingsOps` shadow and expects `not_built`).

They need a Lane B change in the same merge window (assert done and put the values back) or a one-time U-177 exception like IG-2. Until then, the implement stage runs these two classes last on its warm stack and tears the stack down after them. The `ZoneCase` change keeps Lane A's zone tests hermetic regardless.

**Data.Time (Story 18.2, Lane B).** `Data.Time` does not call `Apply` yet, so the process zone switches only in a job that has called `Bridge.Time`; after that, `Data.Time` in the same job follows. Story 18.2 makes every job follow. The test of a production job's zone (`test-production.sh`, DW-12) is unaffected while no `InstanceZone` row exists.

**Story 30.7:** nothing it plans is touched (no purge, `Redact`, `KeyProof` or approvals).

**Footprint (Rule 11).**
- Every edited file is in Epic 17's footprint (bridge `Settings`, `Time`, `Budget`, `ConfigStore`, `Providers`, `Process/Decide`; `Install/Step/Provider`; their Lane A tests).
- New files: `Test/Bridge/SettingsValues.cls` and `Test/Bridge/SettingsApply.cls`.
- No contended path is edited; `Test/Bridge/ZoneCase.cls` is Lane A's and not contended.

**Extend, don't copy (Rule 2).**
- `Set` reuses `WriteRow`.
- `SetZone` reuses `Settings.WriteRow`.
- `Unmark` mirrors `MarkCapped`'s lock.
- `DropEndpoint` is one helper for `Merge`, `Resolve` and the step.
- `TestRequest` follows `RunnerFixture.NewRequest`'s fields.
- The live tests reuse `ModelChange`'s restore order, `RunnerFixture`'s defaults and `Mock.Arm`/`LogSince`.

**Integration ACs (Rule 1).**
- `SettingsOps` (Lane B, unchanged) consumes `Values`/`Check`/`Set`/`Time.Zone` (`TestIntegrationSettingsOps`), and `Decide`'s precheck consumes the values (the live tests).
- No consumer of `SetPrice`, `TestRequest` or `TestAnswer` exists in this story. The first will be Story 18.3.

**Consumes:**
- 33.1's stubs and zone measurement;
- 17.3's `Providers`, `CheckModel`, `SetModel`, `ConfigStore` and `Restore`;
- 17.2's `Timeouts.RetryTimer` and the retry.

**Consumed-by:**
- 18.3 (Lane B): the Models section with prices, **Test** ("Answered in {seconds} s" / "Didn't answer: {reason}"), the second model and Budgets;
- 18.2 (Lane B): `Data.Time` calls `Apply` and reads `Zone()`;
- 17.6: the digest's cost day and time through the instance zone.

## Verification

Every `ci/*.sh` call sets these on its command line, one call per tool call, in the foreground with `timeout: 600000`:
- `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a"`
- `OCUTALON_TEST_WEB_PORT=52801`
- `OCUTALON_LOCK_OWNER='epic=17 stage=<stage>'`

The tags are `e17s4iw` (warm) and `e17s4i` (fresh). Run `ci/warm.sh down` at the end, also after a failure. Slot A gets `iris_doc_load` compile checks only, with `server` `ocutalon-slot-a` and `namespace` `OCUTALON` on every call. Run one `iris_execute_tests` call per message.

**Commands:**
- (once) `OCUTALON_RUN_TAG=e17s4iw ci/warm.sh up`. Expected: a ready stack.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s4iw ci/iris.sh class <C>`, one class per call. Expected `CLASS <C> passed` for:
  - `OcuTalon.Test.Bridge.SettingsValues`, `SettingsApply`, `SettingsStubs`, `Time`, `Budget`, `Timeouts`, `ConfigStore`, `Providers`, `ModelChange`, `SecondModel`, `Usage`, `Keys`, `Decide`, `CodeRules`;
  - `OcuTalon.Test.Install.Provider`;
  - `OcuTalon.Test.Agent.Decide`.
- (once) The Lane B classes, last on the warm stack: `OcuTalon.Test.Core.SettingsSave`, `Test.Core.SettingsAudit`, `Test.Web.SettingsApi`, `Test.Web.Api`, `Test.Data.Time` and `Test.Contract.Ac`. Expected: all pass except `SettingsApi.TestBridgeRoutesAre501` and `SettingsSave.TestBridgeStub`, until the orchestrator rules (Design Notes). Then `ci/warm.sh down`.
- (once) `bash docker/tests/test-storage.sh` (the `Decide` slot), then `test-class-rules.sh`, `test-boundaries.sh` and `test-ci-config.sh`, one per call. Expected: each passes.
- (once) Fresh: `OCUTALON_RUN_TAG=e17s4i ci/iris.sh live install-start`, then `live install-upgrade`, then `live production`, then `shard lane-a@Bridge`, `@Install` and `@Agent`, one per call (`--part k/n` near 8 minutes), then `teardown`. Expected: all pass.

**Shared surfaces:**
- `Decide`'s `SETTINGS` and `Storage` (`test-storage.sh`, `Install.Production`);
- the `Bridge.Settings` and `Time` stub answers (`SettingsStubs`; Lane B `SettingsApi.TestBridgeRoutesAre501`, `SettingsSave.TestBridgeStub`);
- the `InstanceZone` row and process zone (every `ZoneCase` subclass, `test-production.sh`);
- `Decide`'s token-budget read (`Agent.Decide.TestPrechecks`, `SecondModel.TestNeverRetried`, the in-process `Bridge.Decide`);
- the capped mark (`Budget`, `test-online-demo.sh`, `test-online-allowance.sh`);
- the entries' endpoint fields (`ConfigStore`, `Providers`, `ModelChange`, `Install.Provider`);
- the Price rows (`Usage.TestSeedPrices`, the `SettingsStubs` snapshot);
- the retry gate (`SecondModel`);
- the mock log.

Every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19), one per AC.** Apply each on the warm stack, observe red, revert, confirm the tree is byte-identical (`git status --short`, `git diff --stat`), and see the class green again:
- `Check` accepts any `DailyCostCapUSD` → `SettingsValues.TestCheckRefusals` red.
- `Settings.Set` skips the `Decide` row write → `SettingsApply.TestRestartKeepsValues` and `TestBudgetNextDecision` red.
- `SetPrice` re-prices existing Usage rows (or writes nothing) → `TestPriceAppliesToLaterRows` red.
- `SettingText` back to property-first → `TestBudgetNextDecision` red.
- `Set` of the cap skips `Unmark` → `TestCapBelowSpendThenOff` red.
- The `IsTest` gate removed from `TryRetry` → `TestModelTestNotRetried` red.
- `TestRequest` sets owner `""` → `TestModelTestEachAgent` red.
- `Apply()` made a no-op → `Time.TestAgreesWithDataTimeInstanceZone` and `SettingsApply.TestZoneMovesTheCapDay` red.
- `Timeouts.Apply` gives the retry entries `Derive(timer)` → `Timeouts.TestApplyRetryEntries` red at T = 60.
- `Merge` does not call `DropEndpoint` → `ConfigStore.TestProviderChangeDropsEndpoint` red; the same for `Resolve` → `Providers` red; the same for the step → `Install.Provider` red.
- `Values()` reads `DecisionTokenBudget` from the wrong item → `TestIntegrationSettingsOps` red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
