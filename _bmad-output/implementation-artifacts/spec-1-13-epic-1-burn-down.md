---
title: 'Story 1.13: Epic 1 burn-down'
type: 'bugfix'
created: '2026-10-24'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-2, AD-3, AD-5, AD-6, AD-8, AD-19, AD-20, AD-22, AD-24, AD-28 and AD-33, and the Logging and errors and Tests rows of Consistency Conventions)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem (DW-149):**
- **A missing key reads as present in a web request.** Epic 2's `/ocutalon/api` `/state` runs with only the API application's roles (`APPLICATIONROLES` of `Install/Step/Web.cls`: the code, data and private database roles, no `%Admin_ConfigStore`). There, `OcuTalon.Bridge.Keys.Status(agent)` reads the runner's ProviderConfig, `ConfigStore.Details` is refused, and `Present` falls back to `%ConfigStore.Configuration.Exists`, which answers 1 for anyone. `Status`'s own `Catch` also answers 1. So a keyless start shows no "no model key" banner: a false all-clear.
- **Every call costs a refusal and a warning.** Each refused read writes one `%System/%Security/AccessDenied` audit row, so three per `/state`. `Budget.State()`'s `Usage` SELECT has no SQL privilege there, so it logs a warning on every call.

**Approach:**
- **The production records the state.** Each runner records, in its own job at start, whether it can tell that its key is set (`present`, `absent` or `unknown`). It removes the record when it stops.
- **`Keys.Status(agent)` reads only that record,** in every process. A web request never reads the Config Store, and never sees a key or a setting. Only `present` reads 1.
- **`Decide` keeps today's rule** through a new live read, `Keys.Absent(agent)`: only a key that the bridge can tell is absent blocks a request.
- **`Budget.State()` degrades quietly.** A refused `Usage` SELECT becomes one fault line, with no warning.
- **Lane B needs no change.** `/state` keeps calling `Keys.Status(agent)` and `Budget.State()`.

## Boundaries & Constraints

**Always:**
- **One judgement (AD-6, AD-19).** `Keys` has one private method, `State(providerConfig) As %String`, that returns `present`, `absent` or `unknown` and never throws:

  | providerConfig (white space and control characters stripped) | State |
  | --- | --- |
  | empty | `absent` |
  | `@{config:<name>}` in a process without `%Admin_ConfigStore:USE` (`$SYSTEM.Security.Check`) | `unknown`, and the Config Store is not called |
  | `@{config:<name>}`, `ConfigStore.Details` OK | the entry's `api_key`, judged as below |
  | `@{config:<name>}`, `Details` fails and `Exists` of the full name is 0 | `absent` |
  | `@{config:<name>}`, `Details` fails and `Exists` is 1 | `unknown` |
  | a JSON object | its `api_key`, judged as below |
  | anything else: not JSON, a JSON array, unparseable, `@{config:}` | `unknown` |
  | any exception | `unknown` |

  - **The `api_key` judgement:** unassigned, null, or a string that is empty after stripping gives `absent`. Exactly one `@{env:NAME}` (`ConfigStore` `KEYPATTERN`) gives `present` when `NAME` is not empty in this process, and `absent` when it is.
  - **Any other value** (a literal, another placeholder form, a non-string) gives `unknown`. A literal key is outside AD-19.
- **The public `Keys` API** (each method returns 0 or 1, or nothing, never a value, and never throws):
  - **`Present(providerConfig)`:** 1 exactly when `State` is `present`.
  - **`Absent(agent)`** (new; Decide's read, live in the caller's process). It is 1 when there is no active production, `agent` is empty, the item is not found (`$$$EnsErrConfigItemNotFound`), or `State` of the item's ProviderConfig adapter setting (`Ens.Director.GetAdapterSettingValue`) is `absent`. It is 0 for `present`, for `unknown`, for any other read error and for any exception: today's `'Status`, exactly.
  - **`Record(item, providerConfig)`** (new): `Set ^OcuTalonBP.KeyState(item) = $ListBuild(State(providerConfig), $Job)`. An empty `item` does nothing. A failure kills the node.
  - **`Forget(item)`** (new): kills the node only when its job is `$Job`, so a job never removes another job's record.
  - **`Status(agent)`:** 1 exactly when `$ListGet($Get(^OcuTalonBP.KeyState(agent)))` is `present`. Otherwise 0: no record, `absent`, `unknown`, an empty agent or any error.
    - Its implementation reads that node and nothing else. It calls no class method, reads no setting, no Config Store and no environment variable.
    - Its name and signature stay (`Test.Contract.Ac`).
  - **No key value anywhere.** The record holds only the state word and a job number. No method returns, logs, stores or raises a key value.
- **The runner records at start (AD-6, FR-38).** `OcuTalon.Bridge.Adapter.Agent.OnInit`, in its branch that is not building, first calls `Keys.Record(..BusinessHost.%ConfigName, ..ProviderConfig)`. It does this only when `..BusinessHost` is an object whose `%isShadow` is false.
  - The record comes before `CheckSettings`, so a start that is refused records too. Its outcome never changes `OnInit`'s status, and `OnInit` still calls nothing in AI Hub.
  - A new `OnTearDown` calls `Keys.Forget(..BusinessHost.%ConfigName)` under the same guard, then returns `##super()`.
- **Decide (AD-8, AD-20).** In `Precheck`, the `noKey` fact is `##class(OcuTalon.Bridge.Keys).Absent(runner)`, and the doc says so. Nothing else in `Decide` changes.
- **Budget (AD-20; DW-76's fault list).** In `UsageSpent`, a SELECT that fails with the SQLCODE of a missing SQL privilege (Task 0 (b); expected -99):
  - logs no warning, and no spend from the `Usage` rows is counted;
  - makes `State` put this line first in `faults`: "The Usage rows of the day cannot be read in this process, which holds no SQL privilege on them, so their spend is not counted", redacted like the other lines;
  - means `UnpricedModels` is not run.

  Any other SQL error keeps today's warning. The rest of `State` is unchanged: the gateway spend, the cap, the mark and `capped`.
- **Tests (Rule 19).** Every test creates and removes what it asserts on:
  - its fixture users (prefix `ZzWebStatus`), deleted by prefix in `OnBeforeAllTests` and `OnAfterAllTests`;
  - its fixture records (`ZzKeysItem<n>`);
  - the `AccessDenied` event flag, put back as it was found;
  - the runner entries, put back with `RunnerFixture.RestoreKeys`, after which `KeysAre` of the Provider step's placeholder must hold, or `OnAfterAllTests` returns an error.

  Live tests first check `RunnerFixture.RunningReason()` and `WaitAllRun()`. They need the running production of a throwaway, and no model mock. Classes that change security objects say "THROWAWAY STACKS AND CI ONLY" in their header.
- **Text.** All new text is ASCII (Rule 14), and comments state the contract only.

**Never:**
- **Lane B's files.** None of these changes: `OcuTalon.Web.*` (`Web/Api.cls` and Epic 2's `/state`), `Install/Step/Web.cls` (read only: its `APPLICATIONROLES`), `Install/Step/Demo.cls`, `OcuTalon.Core.*`, `.Msg.*`, `.Data.*`, `.Live.*`, `Test/{Core,Web,Data,Live,Demo,Contract,Msg}/**`, `ci/**` (`ci/units.sh` included) and `docker/tests/**`.
- **No new privilege (AD-19, AD-24; veto window).** No role, grant, resource, application role, privileged routine application, SQL grant, `ALLOW_UNCHECKED` entry or Config Store `ReadResource` change.
  - No unchecked prepare, embedded SQL, object access or global scan of `Usage` to get around the SQL privilege.
  - No read of the Config Store from a process that cannot read it.
- **No other behaviour change.** `Precheck`'s outcomes (Story 1.6), `MarkCapped`, `budget.capped`, AD-20's day-cap sequencing, `ConfigStore` and `Production.cls` all stay as they are.
- **No key, no commit and no push.**

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Missing key, web roles (live; the pinning row; DW-149) | `ANTHROPIC_API_KEY` unset; the entries at the Provider step's placeholder; the runners restarted (`RestoreKeys`). A job logs in (`$SYSTEM.Security.Login(user)`, one argument) as a fixture user whose roles are exactly `APPLICATIONROLES`. It calls `Keys.Status` for `TriageAgent`, `DiagnosisAgent` and `ChatAgent`, `Keys.Present(<TriageAgent's ProviderConfig text>)`, `Budget.State(, .faults)`, and then, as the control, `%ConfigStore.Configuration.GetDetails(<TriageAgent's entry>)` | 1. **Controls:** in the job, `$SYSTEM.Security.Check("%Admin_ConfigStore", "USE")` is 0, `$Roles` is the three roles (Task 0 (a)), and the control `GetDetails` fails.<br>2. **The read:** `Status` is exactly 0 for each runner, and `Present` is 0.<br>3. **No audit refusal:** once the control's row is readable, the fixture user has exactly one `%System/%Security/AccessDenied` row since the mark, the control's.<br>4. **Budget:** `State` has `spent`, `cap`, `capped` and `resetsAt`; `faults` holds the Usage line; there is no `Ens_Util.Log` warning of `OcuTalon.Bridge.Budget` since the mark. The test process's own `State` has no Usage line. | none; a job that throws reports `error` |
| Present key, web roles (live) | `PointKeys` (`OCUTALON_MOCK_KEY_HEADER`, set in CI; runners restarted); the same job | `Status` is exactly 1 for each runner. | none |
| A stopped runner (live, in process) | `PointKeys`; `TriageAgent` stopped (`Ens.Director.TempStopConfigItem(<production>\|\|TriageAgent, 1)`) until `RunnerFixture.Jobs` lists no job of it, then started again (`TempStopConfigItem(..., 0)`) and `WaitAllRun` | While it is stopped, `Status(TriageAgent)` is 0 and the other two are 1. After the start it is 1 again. | none |
| Recorded state (in process) | `Record(ZzKeysItem<n>, c)` for each `c`: `{"api_key":"@{env:PATH}"}`, `{"api_key":"@{env:ZZOCUTALONNOSUCHVAR}"}`, `{}`, `@{config:ZzNoSuchEntry}`, `{"api_key":"literal-value"}` and `not json`; then `Forget`; a fixture item that was never recorded; and `""` | 1. **Status:** 1, then 0, 0, 0, 0 and 0; after `Forget` 0; never recorded 0; `""` 0. Each result is exactly 0 or 1.<br>2. **Another job's Forget:** a job's `Forget` of a record that this process wrote leaves it, and `Status` stays 1.<br>3. **No value logged:** no event-log row since the mark holds `PATH`'s value. | none |
| Status reads only the record (static) | the implementation of `OcuTalon.Bridge.Keys`'s `Status` (`%Dictionary.CompiledMethod`), through `Test.Bridge.Source.CodeLines` | It names `^OcuTalonBP.KeyState` and has no `##class(` and no `..` call. | n/a |
| Decide's live read (in process) | `TriageAgent`'s ProviderConfig row (`PutDefault`, no restart) set in turn to: `{"api_key":"@{env:PATH}"}`, `{"api_key":"@{env:ZZOCUTALONNOSUCHVAR}"}`, `{}`, `@{config:ZzNoSuchEntry}`, `{"api_key":"literal-value"}` and `not json` | 1. **Absent:** 0, 1, 1, 1, 0 and 0.<br>2. **Precheck:** `Decide.Precheck(<a decide request>, "TriageAgent", 0)` is `no_key` exactly where `Absent` is 1.<br>3. **Status unchanged:** `Status(TriageAgent)` keeps the value it had before the row changed.<br>4. **Missing names:** `Absent("ZzNoSuchItem")` and `Absent("")` are 1. | none |
| Present (in process) | Test.Bridge.Keys' cases of `Present`, `TestPresentForms` and `TestPresentEntry` | As today, except that each form now judged `unknown` gives 0: a literal (inline or in an entry), `not json`, the non-placeholder strings, `5`, an object, `[]`, `{` and `@{config:}`. | none |

</intent-contract>

## Code Map

- **The defect (Lane A):**
  - `src/bridge/cls/OcuTalon/Bridge/Keys.cls`:
    - `:3-10`: the class doc ("an entry that cannot be read ... counts as present");
    - `:18-37`, `Status`: `present = 1` at `:20` and in the `Catch` at `:33-35`, and `GetAdapterSettingValue` at `:26`;
    - `:48-71`, `Present`: the `Exists` fallback at `:61`;
    - `:74-83`, `KeyPresent`: the `api_key` judgement to keep.
  - `src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls`:
    - `:64-80`, `Details`: it calls `Exists` and then `GetDetails(fqn, .read, 0, 0)`;
    - `:84-89`, `EntryOf`; `:92-96`, `FullName`; `:20`, `KEYPATTERN`. All unchanged.
- **Why the web read fails (read only):** `irissys/%SYS/ConfigStore/Configuration.cls`:
  - `:245-258`, `Exists`: it runs under a temporary security role, so it answers 1 for anyone;
  - `:215-230`, `Get`: it calls `CheckPermission(fqn, "READ")`;
  - `:1209-1263`, `CheckPermission`: it checks `$SYSTEM.Security.Check("%Admin_ConfigStore","USE")` first, and on a refusal calls `AuditAccessDenied` (`:1260`, `:1624-1626`), which writes `%System/%Security/AccessDenied`.
- **Budget:** `src/bridge/cls/OcuTalon/Bridge/Budget.cls`:
  - `:16-31`: the doc of `State` and its fault order;
  - `:32-82`: `State`;
  - `:126-138`: `UsageSpent`, with the warning at `:131`;
  - `:161-175`: `UnpricedModels`, with the warning at `:166`;
  - `:147-150`: `Fault`.
- **Decide:** `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - `:560-569`: the doc of `Precheck` ("the model key (Keys.Status of the runner item)");
  - `:572`: the `noKey` fact.
- **The runner adapter:** `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - `:3-6`: the doc bullet "OnInit calls nothing in AI Hub ... (FR-38)";
  - `:68-72`: `OnInit` (the `Building` branch is AI Hub's `OnInit`);
  - `:77-106`: `CheckSettings`. There is no `OnTearDown` today.
- **The Ens host lifecycle (read only):** `irislib/Ens/Host.cls`:
  - `:518-521`: a shadow host runs no `OnInit`; otherwise the host's `OnInit`, then `Adapter.OnInit()`;
  - `:529-548`: `%OnClose` (not a shadow) calls `Adapter.OnTearDown()` before the host's;
  - `:55`: `%isShadow`.

  Also `irislib/Ens/Adapter.cls:11`, `BusinessHost`, and `irislib/EnsLib/AI/Agent/OutboundAdapter.cls:53`, `ProviderConfig`. The property is the raw setting text; only `setupProviderFromSettings` (`:243-250`) expands it.
- **The production:** `src/ocutalon/cls/OcuTalon/Production.cls:24-33`, the three runners, `PoolSize="1"`.
- **The request's roles (Lane B, read only):**
  - `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls:32-34`: `APPLICATIONROLES` = `":%DB_OCUTALON_CODE:%DB_OCUTALON_DATA:%DB_OCUTALON_PRIVATE"`, `MatchRoles` form;
  - `docker/merge.cpf:10-12`: `^OcuTalonBP.*` maps to `OCUTALON_PRIVATE`, and other globals (`^OcuTalonTest`) go to `OCUTALON_DATA`.
- **The Provider step's names:** `src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls:32`, `KEYPLACEHOLDER` (`@{env:ANTHROPIC_API_KEY}`), and `:44`, `MOCKKEYVARIABLE`.
- **Logging in as another user:** `irislib/%SYSTEM/Security.cls:144-158`, `Login`. The one-argument form needs Write on IRISSYS's resource and no password.
- **Test helpers to reuse:** `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`:
  - `RunningReason` `:81`, `Restart` `:103-110` (`TempStopConfigItem`), `WaitAllRun` `:112` and `Jobs` `:122`;
  - `EventMark` `:134` and `LogRowsHolding` `:142`;
  - `PointKeys` `:408`, `RestoreKeys` `:415` and `KeysAre` `:422`: each restarts the three runners, and `KeysAre` checks the entries;
  - `SnapshotDefault`, `PutDefault` and `RestoreDefault` `:622-666`;
  - `WarningRows(mark, item, class)` `:977`.
- **Patterns to follow:**
  - A job and its report: `Test/Core/CommandsContext.cls:36-55` (Lane B, read only) and `Test/Bridge/Budget.cls:567` (`MarkInJob`).
  - `%SYS` work in a test: `Test/Install/Users.cls:130-205` (`New $Namespace`, `Security.Users`, delete by prefix).
  - Audit latency: `Bridge/Audit.cls:29-30` (about a minute until a row is readable).
  - A static scan: `Test/Bridge/Source.cls:1-47` (`CodeLines`, `Matches`).
- **Tests that pin today's behaviour and must stay green, or change as named:**
  - `src/ocutalon/cls/OcuTalon/Test/Bridge/Keys.cls`:
    - `TestPresent` `:56-75` (`literal-value` and `not json` become 0);
    - `TestPresentForms` `:78-96` (every "counts as present" form becomes 0);
    - `TestPresentEntry` `:99-124` (the literal entry becomes 0);
    - `TestStatus` `:127-145` (kept: the Provider step's entries make `Present` binary);
    - `TestStatusReadsProviderConfig` `:150-170` (replaced by `TestAbsentReadsProviderConfig`).
  - `Test/Agent/Runners.cls`: `TestStartsWithNoKey` `:138-190` and `TestKeysAreRead` `:377-400` (`Status` 0 after `RestoreKeys` and 1 after `PointKeys`; both restart the runners), unchanged.
  - `Test/Bridge/Decide.cls:1449-1500`, `TestPrecheckOrder`: `Put` of the ProviderConfig with no restart, then `Precheck`. It pins Decide's live read, unchanged.
  - `Test/Bridge/Runner.cls:105-160`: `OnInit()` of an adapter whose host is a shadow (`NewRunner` `:968`, config name `ZzRunner`). It must record nothing.
  - `Test/Bridge/Api.cls:38`: `Status("ZzNoSuchItem")` is 0.
  - `Test/Contract/Ac.cls:320-321` (Lane B): the `Budget.State` and `Keys.Status` signatures.
- **The bridge alone:** `release/standalone-bridge.sh`. The example's `Decide` judges its inline placeholder through `Absent`, as before.

## Tasks & Acceptance

**Execution:**

**Task 0: measure, and record the facts under `## Verification` (Measured in implementation).**
- **The targets.** Throwaway tag `e1s13a`, built from the tree before any edit. The privileges of a web request cannot be measured on a slot. Slot A (`ocutalon-slot-a`, namespace `OCUTALON`, after `iris_server_info` shows build 154) is for compiles only.
- **(a) The fixture job.** A user created with exactly the three roles of `APPLICATIONROLES`. A job started by a test-class method calls the one-argument `$SYSTEM.Security.Login(<user>)`. Measure:
  - that it returns 1;
  - `$USERNAME`, `$Roles` and `$Namespace` after it;
  - `$SYSTEM.Security.Check("%Admin_ConfigStore","USE")`;
  - that the job can write `^OcuTalonTest` and read `^OcuTalonBP.UsageCapped` and `Ens.Director.GetActiveProductionName()`.
- **(b) Today's code in that job** (this is also the red of the pinning row). Measure:
  - `Keys.Status` of the three runners with no key: expected 1 each;
  - whether `%System/%Security/AccessDenied` is enabled by default, the rows per call, and how long a row takes to be readable in `%SYS.Audit`;
  - whether `$SYSTEM.Security.Check` writes any audit row;
  - for `Budget.State`: the SQLCODE and `%Message` of the `Usage` SELECT (expected -99), the warnings per call, whether the refused SELECT writes an audit row, and whether the three `Decide` settings are read (no setting fault).
- **(c) The runner job** (a temporary probe, never committed). In `Adapter.Agent.OnInit`, `..ProviderConfig` is the raw setting text (`@{config:OcuTalonTriage}`) and `..BusinessHost.%ConfigName` is the item's name. `TempStopConfigItem(<item>, 1)` runs the adapter's `OnTearDown` in the item's job.
- **Stop:** if a fact contradicts an AC, stop with status `blocked` and the condition `intent gap: <the AC>, measured <fact>`.

**The fix (Lane A, `src/bridge/`):**
- `src/bridge/cls/OcuTalon/Bridge/Keys.cls`: `State` (private), `Present`, `Status`, `Absent`, `Record` and `Forget`, as in Boundaries. The judgement of `api_key` stays one private helper (today's `KeyPresent`, reshaped to give the state). The class doc states the contract: who records, who reads, and that `Status` reads only the record. Rationale: AD-2, AD-6, AD-19, AD-20, AD-28; DW-149.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`: `OnInit` records, a new `OnTearDown` forgets, and the header bullet says so. Rationale: AD-6, FR-38.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: `noKey` is `Keys.Absent(runner)`, and the `Precheck` doc follows. Rationale: AD-8, AD-20; Story 1.6.
- `src/bridge/cls/OcuTalon/Bridge/Budget.cls`: the refused `Usage` read is a fault line with no warning, and the `State` doc lists the line. Rationale: AD-20; DW-149.

**Tests (Lane A):**
- `src/ocutalon/cls/OcuTalon/Test/Bridge/WebStatus.cls` (new, live; THROWAWAY STACKS AND CI ONLY):
  - **The tests:** `TestMissingReadsMissing`, `TestPresentReadsPresent` and `TestStoppedRunnerReadsMissing`, the first three matrix rows.
  - **`TestMissingReadsMissing` also:** fails, as `Test.Agent.Runners.TestStartsWithNoKey` does, when `ANTHROPIC_API_KEY` is set. It turns `%System/%Security/AccessDenied` on for its run when it is off, and puts the flag back. It waits up to 120 s for the control's audit row.
  - **`Probe(number, user, entry, configText)`:** the job's class method. It logs in, then writes `login`, `user`, `roles`, `canReadEntries`, `status(<runner>)`, `present`, `budget`, `faults`, `job`, `controlRefused` and `done` under `^OcuTalonTest("WebStatus", number)`, or `error` if it throws. The parent waits up to 60 s.
  - **The helpers:** the fixture user from `##class(OcuTalon.Install.Step.Web).#APPLICATIONROLES` (parsed, not copied), the `AccessDenied` count in `%SYS.Audit`, and the event flag.
  - **The header** says what each test pins.

  Rationale: Rule 19; DW-149.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Keys.cls`:
  - the `unknown` expectations of `TestPresent`, `TestPresentForms` and `TestPresentEntry`;
  - `TestStatus` restated: `Status` is the runner's record, which equals `Present` of the Provider step's entries;
  - `TestAbsentReadsProviderConfig`, replacing `TestStatusReadsProviderConfig`: the "Decide's live read" row;
  - new `TestRecord` (the "Recorded state" row, with a job method `ForgetInJob`) and `TestStatusReadsOnlyTheRecord` (the static row);
  - the header follows.

  Rationale: Rule 19.

**Acceptance Criteria:**
- **AC1, a missing key reads missing in a web request (DW-149; Integration AC: the running production's runner items record their key state, and a process with only the API application's roles reads it through `Keys.Status(agent)`; AD-19, AD-20, AD-28, the no-false-all-clear non-negotiable).**
  - **Given** no model key configured, and a process that holds only `APPLICATIONROLES`,
  - **when** it asks `OcuTalon.Bridge.Keys.Status(agent)` for each runner,
  - **then:**
    - each answer is exactly 0;
    - the process attempts no Config Store read, so it writes no `AccessDenied` audit row for it;
    - it reads no key or setting value.

  (`Test.Bridge.WebStatus.TestMissingReadsMissing`, `Test.Bridge.Keys.TestStatusReadsOnlyTheRecord`)
- **AC2, the web read follows the real state.**
  - **Given** the runners' entries naming a variable that is set,
  - **when** that process asks again,
  - **then:**
    - each answer is exactly 1;
    - a runner that stops reads 0 until it runs again.

  (`Test.Bridge.WebStatus.TestPresentReadsPresent`, `TestStoppedRunnerReadsMissing`)
- **AC3, a state that cannot be known never passes as OK.**
  - **Given** a runner's recorded state,
  - **when** `Status` reads it,
  - **then:**
    - it is 1 only for `present`; `unknown`, `absent` and no record are 0;
    - a refused or failed read is `unknown`, never `present`.

  (`Test.Bridge.Keys.TestRecord`, `TestPresentForms`)
- **AC4, Decide keeps Story 1.6's precheck.**
  - **Given** a runner's ProviderConfig,
  - **when** `Decide` prechecks a request,
  - **then:**
    - the result is `no_key` exactly when the bridge can tell, live, that the key is absent;
    - a form it cannot judge never blocks.

  (`Test.Bridge.Keys.TestAbsentReadsProviderConfig`, `Test.Bridge.Decide.TestPrecheckOrder` unchanged)
- **AC5, Budget.State in the web request.**
  - **Given** a process without the `Usage` SQL privilege,
  - **when** it calls `Budget.State(, .faults)`,
  - **then:**
    - it returns the four fields;
    - it logs no warning;
    - it names the uncounted `Usage` spend in one fault line, which a process with the privilege does not get.

  (`Test.Bridge.WebStatus.TestMissingReadsMissing`)
- DW-149: In a request without %Admin_ConfigStore (Epic 2's /state), Keys.Status reads a missing model key as present (Status sets present=1 in its Catch; Keys.Present falls back to %ConfigStore.Configuration.Exists when ConfigStore.Details fails), so a keyless start shows no "no model key" banner; Budget.State's Usage SELECT has no SQL grant there and logs a warning per call (ledger; routed by burndown 2026-10-24, orchestrator ruling). **Addressed by AC1 to AC5.**

## Spec Change Log

## Review Triage Log

## Design Notes

**The architecture decisions that govern this story (Rule 6):**
- **AD-2:** `Keys`, `Budget`, `Decide` and the adapter name no other OcuTalon package. The tests may read `Install.Step.Web` and `Install.Step.Provider` parameters.
- **AD-3:** the record is a bridge global, `^OcuTalonBP.KeyState`, in the private database, which the web roles hold. Its home is the same as `^OcuTalonBP.UsageCapped`'s. It is not a persistent class, so it needs no `short-names.tsv` row and no storage block.
- **AD-5:** every runner start rewrites the record, so nothing depends on it surviving.
- **AD-6:** the runner's `OnInit` still calls nothing in AI Hub, and a start with no key still runs.
- **AD-8:** the precheck order and `no_key` are unchanged.
- **AD-19:** only production jobs read the entries, and the web request no longer tries. Entries keep `%Admin_ConfigStore`.
- **AD-20:** `/state` and `StatusMonitor` still read key presence only through `Keys.Status(agent)`, and the cap only through `Budget.State()`.
- **AD-22:** the tests are `OcuTalon.Test.Bridge.*`, shard `lane-a`, in throwaways.
- **AD-24:** no role or privilege changes. The fixture user is a test object in a throwaway.
- **AD-28:** no false all-clear, because `unknown` is never OK.
- **AD-33:** the record has one writer, `Keys.Record`, called only by the runner adapter.

No AC contradicts an AD's Rule, and no NFR is involved.

**Decided in-stage:**
1. **The read is a status the production records** (the orchestrator's second example).
   - **Why not the alternatives:** a privileged read for the web needs a privilege or a privileged routine application (veto, and the orchestrator recommends against it), and any Config Store read from the web is refused and audited.
   - **Why the runner's start:** a runner applies a Config Store or ProviderConfig change only when it restarts (AD-19: `SettingsOps` restarts the runners), and a key only changes with a restart of IRIS. So the record is what the runner actually uses.
2. **`Status` reads only the record, in every process.** So `StatusMonitor` (in the production) and `/state` (in the web) agree by construction.
   - **The cost:** `Status` no longer follows a setting changed without a restart, and a stopped or never-started runner reads 0, so the banner can show while the runners are down. That is the safe direction: a state that cannot be known is not OK.
3. **`Decide` keeps the live judgement through `Absent`.** Story 1.6's decisions 7, 20 and 23 now describe `Absent`: only a key it can tell is absent blocks, and a form it cannot judge never does.
4. **`present` means one `@{env:NAME}` whose variable is set.** A literal key or another form is `unknown`, so `Status` shows the banner for a configuration AD-19 does not allow, and `Decide` still tries it.
   - **`Present` is realigned to `Status`'s meaning,** so that no public `Keys` method reads a refused read as present. Its only callers are tests.
5. **The record is written before `CheckSettings`, and only in a real job (not a shadow host).** A refused start still records what it would use. `Test.Bridge.Runner`'s direct `OnInit()` calls write nothing.
6. **`Forget` removes only its own job's record.** A new job that starts before the old one has torn down keeps its record.
7. **The guard on the Config Store read.** `State` makes no Config Store call in a process without `%Admin_ConfigStore:USE`, the resource every OcuTalon entry keeps (AD-19). So no `Keys` method can write an audit refusal there.
8. **Budget degrades,** as the ruling allows.
   - **The cost:** in the web, `spent` leaves out the `Usage` rows, so `capped` comes from the day's mark or the gateway spend. `/state`'s `dailyCap` can therefore trail `StatusMonitor`'s by one decision: the first `daily_cap` fallback marks the day (AD-20).
   - **What is kept:** other SQL errors still warn.
9. **The pinning context** is a job logged in (one-argument `Login`) as a fixture user with exactly `APPLICATIONROLES`, read from Lane B's parameter. This is the "exact equivalent" the ruling allows; a real request would also add the user's own roles, none of which holds `%Admin_ConfigStore`.
10. **The no-key case is the keyless start itself:** the Provider step's entries with `ANTHROPIC_API_KEY` unset. When the variable is set, the test fails with the reason, as `TestStartsWithNoKey` does.
11. **The audit evidence has a positive control.** One refusal of the job's own proves that the event is on, that the context really lacks the privilege, and that the rows have become readable. So "exactly one row" can fail.
12. **A new test class.** `Test.Bridge.Keys` stays in process, and `WebStatus` holds the user, the job, the audit and the runner restarts.

**Known residual (for the lead):** a runner job killed without teardown (an IRIS crash) leaves its record. Until that runner starts again, `Status` reads the old state. This is real only if the key is removed meanwhile and that runner is left stopped while the production is active. `reopen_if`: a release lets a runner stay disabled across an IRIS restart, or AD-5 is read to allow runtime state in IRISTEMP.

**Integration ACs (Rule 1):**
- **AC1 and AC2:** the running production's runner items write the record through the adapter, and a process with the web roles reads `Keys.Status`. The effect is 0 for a keyless start and 1 after `PointKeys`.
- **AC4:** `Decide` reads `Keys.Absent`. The effect is a `no_key` fallback (`Test.Agent.Runners.TestStartsWithNoKey`, `Test.Bridge.Decide`).

**Consumed-by:**
- **Story 2.10 (Lane B):** `/state` and `StatusMonitor` call `Keys.Status(agent)` for the three runners and `Budget.State()`, unchanged.
- **`Decide`'s precheck (this epic):** `Keys.Absent`.
- **Story 11.5:** the release check, through the same reads.

**Consumes:**
- **Story 1.6:** `Keys`, the precheck and `RunnerFixture.PointKeys`/`RestoreKeys`/`KeysAre`.
- **Stories 1.4 and 1.6:** `Budget.State` and its faults.
- **Story 1.1:** the Provider step's entries.
- **Story 0.3:** `Install.Step.Web.APPLICATIONROLES`.

**Extend, don't copy (Rule 2):**
- **Extended, not copied:**
  - one judgement (`State`) serves `Present`, `Absent` and `Record`, and today's `KeyPresent` is reshaped, not copied;
  - `Absent` is today's `Status` body;
  - the job and report follow `Test.Core.CommandsContext` and `Test.Bridge.Budget.MarkInJob`;
  - the runner helpers are `RunnerFixture`'s.
- **New on purpose:** the fixture user and the audit count. `Test.Install.Users`' helpers are private to the Users step's own fixtures, and no sibling creates a user with given roles or counts audit rows.

**Ledger (Rule 17):** DW-149 is this story's only inbox entry, and AC1 to AC5 address it.

**For the lead (rulings recommended, not blocking):**
- **The routed note for Epic 2 (Lane B), for the orchestrator:** "`/state` needs no change. It keeps calling `Keys.Status(agent)` for the three runners and `Budget.State()`.
  - After Story 1.13, `Status` reads the key state each runner recorded at its start, with no Config Store read and no audit. It is 1 only when a running runner could tell that its key is set, so 0 means missing or not known: show the banner. That includes while the runners are stopped.
  - In a request, `Budget.State()` counts no `Usage` spend, logs nothing, and names that in `faults`. Its `capped` comes from the day's mark and the gateway spend, so `dailyCap` can trail `StatusMonitor`'s by one decision."
- **The spine (optional, Rule 20 light path):** AD-20's "Status reads" bullet could add that `Keys.Status` reads the runners' recorded state, and that `Decide`'s precheck reads `Keys.Absent`. Nothing in this story depends on it.
- **The veto window:** nothing of this story is in it.
  - No privilege, role or grant changes.
  - The new global is runtime state that each runner start rewrites, not a change to how stored data is kept, like `UsageCapped` in Story 1.6.
  - No public text is added.
- **CI time:** `WebStatus` restarts the runners four times and waits up to 120 s for one audit row, about 2 to 4 minutes on the x64 runner `(inference)`. The `shards` group stays under the `install` group, so REL-4 holds.

## Verification

**Targets:**
- **The slot.** `ocutalon-slot-a` only (MCP `server: ocutalon-slot-a`, `namespace: OCUTALON`, after `iris_server_info` shows build 154), for `iris_doc_load` compiles. No test class runs there.
- **Throwaways.**
  - Everything else runs through `ci/iris.sh` with `OCUTALON_RUN_TAG=e1s13a OCUTALON_LOCK_OWNER='epic=1 stage=implement' OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-a OCUTALON_TEST_WEB_PORT=52801`.
  - QA uses `e1s13q` (`stage=qa`), and review uses `e1s13r` (`stage=code-review`).
  - One stack at a time, one command per call, each with `timeout: 600000`.
- **Never** `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition`, `ocutalon-slot-b` or `ocutalon-slot-c`. No push, no `gh workflow run`, and never read `.env`.

**Commands** (each with the variables above):
- **(loop)** `bash ci/checks.sh`. Expected: every block passes, among them `class-rules` (`bridge-refs`, `unchecked-prepare` with no new entry), `ci-config` and `boundaries`. About 20 s.
- **(loop)** `bash ci/iris.sh build`. Expected: exit 0.
- **(loop)** `bash ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Bridge.WebStatus`, `OcuTalon.Test.Bridge.Keys`, `OcuTalon.Test.Bridge.Budget`, `OcuTalon.Test.Bridge.Decide`, `OcuTalon.Test.Bridge.Runner` and `OcuTalon.Test.Agent.Runners`. Expected: `CLASS ... passed`.
- **(loop)** `bash ci/iris.sh teardown`. Expected: only `e1s13a`'s projects are removed.
- **(once)** `bash ci/iris.sh shard lane-a`. Expected: every class passes, `Test.Bridge.WebStatus` included. The only SKIP is the existing `TestStepHelpers`.
- **(once)** `bash ci/iris.sh shard lane-b`. Expected: every class passes, `Test.Contract.Ac` (signatures) included.
- **(once)** `bash ci/iris.sh live production`. Expected: PASS for every row, row 14 (a start with no key writes no error) included.
- **(once)** `bash ci/iris.sh live production-restart`. Expected: PASS.
- **(once)** `bash ci/iris.sh live demo-path`. Expected: PASS, with `@floor` passed.
- **(once)** `release/standalone-bridge.sh`, with the variables above. Expected: its checks pass unchanged, and the example decision is not a fallback.
- **(once)** `bash ci/iris.sh teardown`. Expected: nothing of `e1s13a` is left.

**Shared surfaces:**
- **What `Keys.Status` means:**
  - `Test.Bridge.Keys`' `Status`-equals-`Present` assertions (`TestStatus`) and `TestStatusReadsProviderConfig` (replaced);
  - `Test.Agent.Runners` `TestStartsWithNoKey` and `TestKeysAreRead` (unchanged, because they restart the runners);
  - `Test.Bridge.Api:38`, and `Test.Contract.Ac`'s signature;
  - Epic 2's Story 2.10.
- **`Keys.Present`'s matrix:** `Test.Bridge.Keys` `TestPresent`, `TestPresentForms` and `TestPresentEntry`. The `unknown` forms become 0.
- **Decide's key fact:**
  - `Test.Bridge.Decide` (`TestPrecheckOrder`, `TestResendPrecheck`, the `no_key` cases at `:2060-2081`);
  - `Test.Agent.Decide`;
  - `release/standalone-bridge.sh`.

  All unchanged.
- **The runner adapter's start and stop:**
  - `Test.Bridge.Runner` (`OnInit()` on a shadow host writes nothing);
  - every live test that restarts runners (`RunnerFixture.Restart`, `PointKeys`, `RestoreKeys`, `UseAgent`, `UseTimer`) now rewrites the record.
- **`Budget.State`'s faults:** `Test.Bridge.Budget.TestFaults` (a process with the privilege: no new line), and `Decide`'s logging of faults.
- **Security and audit state of the throwaway:**
  - the fixture users `ZzWebStatus*` (created and deleted);
  - one `AccessDenied` audit row per run, from the control;
  - the `%System/%Security/AccessDenied` flag, put back. `Test.Install.Users` cleans only `ZzUsers*`.
- **The new global `^OcuTalonBP.KeyState`.** No other test reads it.
- **Lane A's test packages:** `Test.Bridge.Time.TestZoneCase` scans them. The new class calls no process time zone.
- **The search:** search the test trees for `Keys).Status`, `"Status"`, `Present`, `Bridge.Keys`, `noKey`, `cannot be summed`, `Adapter.Agent`, `OnInit()` and `OnTearDown`.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. The lead runs `shard lane-a` and `shard lane-b` forward, then both with `--reverse`.

**Mutations to demonstrate (Rule 19),** at least one per AC. Record each as `mutation: <change> -> <test went red>`.

| AC | Change | Test that goes red |
| --- | --- | --- |
| AC1 | `Status` is put back to Story 1.6's body (a live read) | `WebStatus.TestMissingReadsMissing` (1 for each runner, and three more `AccessDenied` rows) |
| AC1 | `State` without the privilege guard | `WebStatus.TestMissingReadsMissing` (a second `AccessDenied` row, from `Present`) |
| AC1 | `Status` also calls `..Absent(agent)` | `Keys.TestStatusReadsOnlyTheRecord` |
| AC2 | the adapter's `OnInit` records nothing | `WebStatus.TestPresentReadsPresent` |
| AC2 | the adapter has no `OnTearDown` | `WebStatus.TestStoppedRunnerReadsMissing` |
| AC2 | `Forget` kills the node whatever its job | `Keys.TestRecord` (the job's `Forget`) |
| AC3 | the `api_key` judgement gives `present` for any other value | `Keys.TestRecord` (the literal), `Keys.TestPresentForms` |
| AC3 | `State`'s `Catch` gives `present` | `Keys.TestPresentForms` (`{`) |
| AC4 | `noKey` is `'Keys.Status(runner)` | `Bridge.Decide.TestPrecheckOrder`, `Keys.TestAbsentReadsProviderConfig` |
| AC4 | `Absent` counts `unknown` as absent | `Keys.TestAbsentReadsProviderConfig` (`not json`) |
| AC5 | `UsageSpent` warns on the privilege error again | `WebStatus.TestMissingReadsMissing` (a Budget warning) |
| AC5 | the fault line is not added | `WebStatus.TestMissingReadsMissing` |

**Lead's rulings at the spec gate (2026-10-24, Epic 1 runner, unattended):**
- **Veto window, kept as planned:** the recorded key state `^OcuTalonBP.KeyState(item)` (inbox U-48 or the next id the inbox gave; see the cycle log), and Status 0 while a runner is stopped or unreadable, so the no-key banner shows then (unknown is never OK).
- **Decided:** `Budget.State` degrades quietly in a request without the grant; `Keys.Present`'s new meaning; no spine edit here (AD-20's wording is left for the orchestrator).
- **Task 0's stop conditions stand:** in particular, if the web roles cannot read the recorded state, HALT (a key that is set must read as present to the web request).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
