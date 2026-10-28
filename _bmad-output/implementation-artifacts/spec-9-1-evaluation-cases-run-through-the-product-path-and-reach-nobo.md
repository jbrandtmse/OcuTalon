---
title: 'Story 9.1: Evaluation cases run through the product path and reach nobody'
type: 'feature'
created: '2026-10-28'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-9-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `EvalIn` and `EvalSink` are Epic 0 stubs. So no evaluation case can go through the product's intake path, nothing records what a case was decided or what it cost, and nothing proves that an evaluation run reaches nobody. Epic 9 cannot score the product without them.

**Approach:**
- Build `EvalIn`'s item path: a run entry, `Start`, reads recorded item cases from `eval/` and sends each one to `Intake` as an Item owned by `eval`.
- Build `EvalSink`: it completes one Lane A result row per case from the `ItemDecision` and from the bridge's `Decision` and `Usage` rows. That includes an incident case's cause and fix, which it reads from the `Decision` row.
- Prove on the running production that a run reaches nobody and that its usage counts toward no session total and no daily cap.
- DW-337's CI regrouping (`98f69be`) is this story's first change. This story records its measurement.

## Boundaries & Constraints

**Always:**
- **The switch.** The product keeps `EvalIn` disabled. Only `OCUTALON_EVAL=1`, through the existing Production install step, enables it. `Start` reaches `EvalIn` only through `Ens.Director.CreateBusinessService("EvalIn")`, so a disabled `EvalIn` sends nothing.
- **Each case's Item:**
  - a fresh `ItemId` from `OcuTalon.Bridge.Ids.NewRef()`;
  - `SourceItemId` set to the case's recorded `item.itemId`;
  - `SessionRef` set to `OcuTalon.Data.Ownership.#EVAL`;
  - provenance `untrusted`;
  - sent to `Intake`.
- **Trace sessions.** Each case is its own trace session, and every message of the run carries `SuperSession` equal to the run's Ref (AD-26).
- **EvalSink's limits.** `EvalSink` only reads `Decision` and `Usage` rows. It sends nothing and never throws: a failure is logged and the call returns `$$$OK`.
- **The table.** It is Lane A's, under `OcuTalon.Eval`. Its `DEFAULTGLOBAL` comes from `src/short-names.tsv`, its storage block is committed, and the spine's Tables line names it in the same change (AD-3, AD-5, AD-33).
- **No stubs.** `Parameter STUB` is removed from both classes, and their oracle rows say `"stub": 0`.
- **Throwaways only.** Tests that need the running production run only in throwaway stacks. They put the `EvalIn` switch, the runner keys and every row and message they made back as they found them.

**Never:**
- **Contended files.** Never edit:
  - Epic 7's live files: `Watch/IncidentManager.cls`, `Watch/EvidencePack.cls`, `Watch/Notice.cls`, `Watch/Msg/DiagnosisPayload.cls` and `Agent/Diagnosis.cls`;
  - any Lane B class: `Core/*` (`Core/Intake.cls` included), `Msg/*`, Lane B's `Data/*` and the existing `Test/Core/*`;
  - `src/bridge/**`, `ci/mock/**`, `docker/**`, `.github/workflows/ci.yml` and the compose files.
- **Other stories' scope.** Never build:
  - the incident path through `IncidentManager` (Story 9.6);
  - turn cases, `TurnResult` or `check_status`'s eval branch (Story 9.3);
  - scoring, the report or the `lane-a.yml` job (Story 9.2).
- **Never reach anyone.** Never use `EnsLib.Testing.Service` or the production's testing switch. Never reach `OutcomeRouter`, `Notify`, `Conversation`, `DigestStore`, any `*Out` item, approvals or `IncidentManager`.
- **`ci/units.sh`.** Change nothing beyond adding `Eval` to the `lane-a` shard; DW-337's group lines are done.
- **Targets.** Never run a production-starting or destructive test on slot B, or on any target the Verification section doesn't name.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Item case | `EvalIn` enabled; `Start("/opt/ocutalon/eval/", "mail-newsletter", .run, .sent, .skipped)` | `sent` is 1 and `run` is 22 characters. **The row:** one row, `sent` then `decided`. **EvalIn→Intake:** an Item with `SessionRef` `eval`, `SourceItemId` `mail-newsletter` and a new 22-character `ItemId`. **Intake→EvalSink:** the `ItemDecision` copies `SourceItemId`. **The row's fields:** `DecisionRef` is the `decide` Decision (`OwnerRef` `eval`); `Outcome` is `digest`, the mock's default triage; `CostUSD` and `LargestRequestTokens` are above 0 | none expected |
| Act case | A fixture case whose text holds `[[mock:decide-act-low-confidence]]` | **The turn:** Intake's turn request is `Kind` `turn`, provenance `untrusted`, `SessionMode` `fresh`, no `SeedText`, `OwnerRef` `eval`. **The row:** `Outcome` `act`; `TurnDecisionRef` is the (`ItemId`, `turn`) Decision; `TurnCostUSD` is above 0; `LargestRequestTokens` is the largest over both decisions' `Usage` rows | none expected |
| Switch off | The stack's default (`OCUTALON_EVAL` unset or 0) | `Start` returns the Director's error (it names "disabled") | No run Ref, no row, nothing sent |
| Case not sent | **Any of:** a kind that is neither `item` nor `injection` (`orders-date-format` is an incident); no `case.json`, or one that isn't JSON; no `item.itemId`; a recorded provenance other than `untrusted` | The case is listed in `skipped` with its reason and logged as a warning. The other cases still run | No row, nothing sent |
| Send fails | `SendRequestAsync` errors | The case's row is deleted, and the case goes into `skipped` with the error text | — |
| Incident decision | An `ItemDecision` whose `DecisionRef` is a `diagnose` Decision | `CauseCategory`, `ElementAtFault`, `FixKind` and `FixParameters` (a JSON object as text) come from `Decision.Payload`. `Outcome` and `Fallback` come from the message | — |
| No fix / bad payload | A diagnose payload with no fix, or a payload that isn't JSON | `FixKind` and `FixParameters` are empty, or all four cause fields are empty. The row is still `decided` | A bad payload is logged as an error |
| Fallback | An `ItemDecision` with `Fallback` 1 and no `DecisionRef` | `Outcome` `tellnow`, `Fallback` 1 and `FallbackReason` as sent. The cost and size fields are empty | — |
| No open row | An eval `ItemDecision` whose `ItemId` has no `sent` row (an Item that `EvalIn` didn't send, or a second decision for a row already `decided`) | A warning naming `ItemId` and `SourceItemId` | Nothing stored or changed |
| Refused message | Not an `ItemDecision`, or `OwnerRef` isn't `eval` | A warning | Nothing stored |
| Unpriced usage | `Usage.Totals(ref).costUSD` is "" | `CostUSD` is empty, never 0 | — |

</intent-contract>

## Code Map

**Product (this story):**
- `src/ocutalon/cls/OcuTalon/Eval/In.cls`: the stub (`STUB`, `OnProcessInput` returns NotImplemented); build it.
- `src/ocutalon/cls/OcuTalon/Eval/Sink.cls`: the stub; build it.
- `src/ocutalon/cls/OcuTalon/Production.cls:42-43`: `EvalIn` (pool 0, `Enabled="false"`) and `EvalSink` (pool 1, enabled) in Lane A's region. No change.
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls:48,254-264`: `SetEval(EvalEnabled(env))` writes the System Default Setting row `OcuTalon.Production||EvalIn||*||Enabled` at every start. Read only.
- `irislib/Ens/Director.cls:1470`: `CreateBusinessService` refuses a disabled item with `EnsErrConfigDisabled`.

**Lane B, read only:**
- `src/ocutalon/cls/OcuTalon/Core/Intake.cls`:
  - `:125`: it refuses provenance other than `untrusted`;
  - `:142-147`: it keeps a `SuperSession` the header carries;
  - `:185-186`: the act turn is sent with `SessionMode` `fresh` and no `SeedText`;
  - `:216-233`: `Finish` sends the `ItemDecision` to `EvalSink` for owner `eval`, copying `SourceItemId`.
- `src/ocutalon/cls/OcuTalon/Msg/Item.cls`: `ItemId` (22), `SourceItemId` (128), `SessionRef` (the owner), `Channel` (32), `Provenance`, `Text`, `Sender`, `Subject`, `CatalogKey`, `Slots` (JSON). `Msg/ItemDecision.cls`: `ItemId`, `SourceItemId`, `OwnerRef`, `DecisionRef`, `Outcome`, `Fallback`, `FallbackReason`, and so on.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls:44`: `Parameter EVAL = "eval"`.
- `src/ocutalon/cls/OcuTalon/Channel/SimMailbox/In.cls`: the sibling Item builder.
  - `:24` sets channel `mailbox`.
  - `:32-36` hold the exact newsletter sender, subject and body.
  - `:109-124` build the Item.

**Bridge (Epic 7, contended), read only:**
- `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls`:
  - `Ref`, `Kind`, `ItemId`, `OwnerRef`, `Payload` (JSON);
  - `RefIndexOpen(ref)` (`:71`) and `ItemIdKindIndexOpen(itemId, kind)` (`:73`).
- **The diagnose payload keys:** `causeCategory`, `elementAtFault`, `fixKind`, `fixParameters{field, sourceFormat, targetFormat}`. A fallback row's `Payload` is empty.
- `src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls`:
  - `:50` `LargestRequestTokens` (tokens);
  - `:144` `Totals(decisionRef)` returns `{costUSD, rows, …}`, and `costUSD` is "" when a row is unpriced;
  - `DecisionRefIndex`. It has no max of the request size.
- `src/bridge/cls/OcuTalon/Bridge/Ids.cls:7`: `NewRef()` returns 22 characters.
- `src/bridge/cls/OcuTalon/Bridge/Time.cls:18`: `NowUtc()`.
- `src/bridge/cls/OcuTalon/Bridge/Budget.cls`:
  - `:41` `State()` returns `{spent, cap, capped, resetsAt}`;
  - `:141` `UsageSpent` already leaves out `OwnerRef 'eval'`.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls:417-421`: reads the diagnose payload (the sibling of `EvalSink`'s read).

**The tables the isolation test reads:**

| Table | Owner field |
|---|---|
| `Data/Delivery.cls` | `OwnerRef` |
| `Live/Event.cls` | `Stream`, plus `Payload` (`:26`) |
| `Bridge/Data/ApprovalRequest.cls` | `OwnerRef` |
| `Data/Incident.cls` | `OwnerRef` (`:12`) |

`OcuTalon.Msg.Notification` is a message only, with no table.

**Test helpers to extend or call:**
- `Test/Core/InProduction.cls`: the base for tests over the running production. It has `Guard`, `Number`, `Supers` and `OnAfterAllTests` → `Fixture.RemoveMessages` and `Clean`.
- `Test/Agent/RunnerFixture.cls`:
  - `:306` `ReadyReason`;
  - `:456`/`:463` `PointKeys`/`RestoreKeys`;
  - `:670`/`:682`/`:704` `SnapshotDefault`/`PutDefault`/`RestoreDefault`.
- `Test/Data/Fixture.cls`: `:427` `Headers(superSession)` and `:450` `Between(...)`.
- `Test/Core/Observe.cls`: `:64` `WaitProcessed`, and `:88`/`:101` `Warnings`/`RemoveWarnings`.
- `Test/Core/Intake.cls:486-492`: the shadow-instance pattern, `Ens.Host.GetShadowInstance("class||<class>")`.
- `Test/Agent/Decide.cls:166-215`: deletes the Decision and Usage rows by `ItemId`. It is a private instance method, so copy it.
- `ci/mock/scenarios/A/triage.json`: the default triage answer is `digest`.
- `ci/mock/scenarios/A/decide-act-low-confidence.json`: the answer is `act` (the marker reaches the turn too, which answers plain text).
- `Test/Install/Production.cls`:
  - `:13`: the docstring list of items that are built;
  - `:119`: `TestingEnabled` 0;
  - `:477-500`: the `EvalIn` row is saved and restored;
  - `:626-627`: the oracle rows `EvalIn`/`EvalSink` with `"stub": 1`.
- `TestStubsAnswer` pins `+$Parameter(class,"STUB") = row.stub`. `docker/tests/test-production.sh` row 16 and `lib-live.sh check_items_run` read the same oracle.
- `Test/Core/RoutingProduction.cls:171-200`: Lane B's test sends an eval Item through `Intake` to `EvalSink`. It is a shared surface.
- `Test/Data/Tables.cls:68-85`: `TestSqlNames` covers every new persistent class.
- `docker/tests/test-storage.sh`: the registry, prefix and storage rules.
- `docker/tests/test-ci-config.sh:636-649`: the `units` rule (every `Test/<Area>/` sits in one shard).
- `ci/units.sh:17`: the `lane-a` areas.
- `eval/orders-date-format/case.json`: an incident case, which 9.1 does not send.
- `/opt/ocutalon/eval` is mounted read-only in throwaways only (`docker/tests/compose.throwaway.yml`).

## Tasks & Acceptance

**Execution:**

**Task 0 (measurement).** The first fresh run of `OcuTalon.Test.Eval.Run` is the measurement.
- **What it measures:** on a running production whose `EvalIn` row is 0, does `RunnerFixture.PutDefault("EvalIn","Enabled",1)` followed by `Ens.Director.UpdateProduction()` make `CreateBusinessService("EvalIn")` succeed? And does `RestoreDefault` followed by an update make it refuse again?
- **Record** the answer in Verification.
- **If not:** set up and restore with `Ens.Director.RestartProduction()` instead, and record that.

**1. `src/ocutalon/cls/OcuTalon/Eval/Data/CaseResult.cls` (new).** `%Persistent`, with `Parameter DEFAULTGLOBAL = "^OcuTalonP.EvalCaseResult"` and the registry comment.
- **Properties:**
  - `RunRef` (22), `CaseName` (128), `SourceItemId` (128), `ItemId` (22);
  - `State` (32: `sent` or `decided`), `SentAt` and `DecidedAt` (20, UTC);
  - `DecisionRef` (22), `Outcome` (32), `Fallback`, `FallbackReason` (32);
  - `CauseCategory` (64), `ElementAtFault` (128), `FixKind` (32), `FixParameters` (MAXLEN "");
  - `CostUSD` (`%Numeric` SCALE 6), `TurnDecisionRef` (22), `TurnCostUSD`, `LargestRequestTokens` (`%Integer`).
- **Indexes:** `RunCaseIndex On (RunRef, CaseName) [Unique]` and `ItemIdIndex On ItemId`.
- **Class methods:**
  - `Open(runRef, caseName, sourceItemId, itemId) As %Status`, for `EvalIn`;
  - `Pending(itemId)`, the `sent` row or "", for `EvalSink`;
  - `Remove(runRef)`, for tests and later stories.
- **Storage:** the compiler's `Storage` block, committed. No `Purge`: rows exist only where `EvalIn` ran, which is throwaways and CI.
- **Why:** AC4's table.

**2. `src/short-names.tsv`.** Add the row `EvalCaseResult	^OcuTalonP.EvalCaseResult	OcuTalon.Eval.Data.CaseResult	A`, as AD-3's registry requires.

**3. `src/ocutalon/cls/OcuTalon/Eval/In.cls`.** Delete `STUB` and the stub handler.
- **Parameters:** `FOLDER = "/opt/ocutalon/eval/"`, `TARGET = "Intake"`, `KINDS = "item,injection"`, and the refusal texts.
- **Properties:** `RunRef`, which `Start` sets on the instance it created.
- **`ClassMethod Start(folder As %String = {..#FOLDER}, names As %String = "", Output runRef As %String, Output sent As %Integer, Output skipped As %DynamicArray) As %Status`:**
  - `names` is a comma list of case folder names, sent once each. "" means every subfolder that holds `case.json`, in name order.
  - It calls `CreateBusinessService("EvalIn")`. On an error it returns that error with no `runRef`.
  - It mints `runRef` with `NewRef()`.
  - For each case it calls `ProcessInput` with an `Ens.StringContainer` holding the case folder. The output's `StringValue` is "" when the case was sent, or else the reason, and that reason becomes `{case, reason}` in `skipped`.
- **`ClassMethod Wait(runRef As %String, seconds As %Integer) As %Integer`:** polls every 0.25 s and returns how many of the run's rows are still `sent`.
- **`OnProcessInput`:**
  1. Read `case.json`.
  2. Refuse a case as the matrix says.
  3. Build the Item: `ItemId` from `NewRef()`, `SourceItemId` set to `item.itemId`, `SessionRef` set to `Ownership.#EVAL`, `Provenance` `untrusted`, and `Channel`, `Sender`, `Subject`, `Text`, `CatalogKey` and `Slots` (`item.slots` as JSON text) from the record.
  4. `CaseResult.Open` the row.
  5. Set `..%SuperSession = ..RunRef`.
  6. `..SendRequestAsync(..#TARGET, item)` (the service form, with no response). If the send fails, remove the row and return the error as the reason.
- **Why:** AC2 and AC1.

**4. `src/ocutalon/cls/OcuTalon/Eval/Sink.cls`.** Delete `STUB` and the stub handler.
- **`OnMessage`:** refuses as the matrix says, and takes `CaseResult.Pending(ItemId)`.
- **It sets:**
  - `DecisionRef`, `Outcome`, `Fallback` and `FallbackReason` from the message;
  - when `Decision.RefIndexOpen(DecisionRef)` has `Kind` `diagnose`, the four cause fields from `%DynamicObject.%FromJSON(Payload)`;
  - `CostUSD` from `Usage.Totals(DecisionRef).costUSD`;
  - `TurnDecisionRef` and `TurnCostUSD` from `Decision.ItemIdKindIndexOpen(ItemId,"turn")` when that row exists;
  - `LargestRequestTokens` from `SELECT MAX(LargestRequestTokens) FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef IN (?, ?)`;
  - `State` `decided` and `DecidedAt`.
- **Errors:** everything sits in a Try/Catch that logs and returns `$$$OK`.
- **Why:** AC4.

**5. `eval/mail-newsletter/case.json` (new).** The first item case, in the shape set out in Design Notes. Its sender, subject and body are exactly SimMailbox's newsletter constants (UX-DR86), `item.itemId` is `"mail-newsletter"`, and the expectation is `{"outcome": "ignore"}` (UX: "an ignored newsletter"). **Why:** AC2's recorded item case.

**6. `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`.** This is a footprint extension.
- In the Items oracle, change the `EvalIn` and `EvalSink` rows to `"stub": 0`.
- Add one sentence at the end of the `TestStubsAnswer` docstring bullet: `EvalIn` and `EvalSink` are built in Story 9.1.
- Edit nothing else.
- **Why:** `TestStubsAnswer` pins the `STUB` flags.

**7. `ci/units.sh:17`.** Change `lane-a` to `Agent Bridge Checks Install Tools Digest Watch Eval`. **Why:** the `units` rule of `test-ci-config.sh`, and AD-22's lane alignment.

**8. `src/ocutalon/cls/OcuTalon/Test/Eval/Switch.cls` (new; `%UnitTest.TestCase`; read only).**
- `OcuTalon.Production`'s definition has `EvalIn` set to `OcuTalon.Eval.In`, `Enabled` 0 and `PoolSize` 0.
- No item has class `EnsLib.Testing.Service`, and `TestingEnabled` is 0.
- The `EvalIn` row equals `EvalEnabled($SYSTEM.Util.GetEnviron("OCUTALON_EVAL"))`.
- When the variable isn't "1": `Start` returns an error containing "disabled", `runRef` is "", and the class records no new `CaseResult` row.
- When the variable is "1": `CreateBusinessService("EvalIn")` succeeds, and the class calls no `Start`.
- **Why:** AC1.

**9. `src/ocutalon/cls/OcuTalon/Test/Eval/Sink.cls` (new; `%UnitTest.TestCase`; warm-safe).**
- **Setup:** it calls `OnMessage` on a shadow instance of `OcuTalon.Eval.Sink`, with synthetic `CaseResult`, `Decision` (`decide`, `turn`, `diagnose`) and `Usage` rows that it creates and deletes. Their refs are 22-character `NewRef()` values; run Refs and case names start with `zz`.
- **Cases:** every Sink row of the matrix: decide with and without a turn, incident, no fix, bad payload, fallback, no open row, a second decision, refused message, and unpriced.
- **Warnings:** it checks them through `Observe.Warnings` and removes them.
- **Never** goes through `IncidentManager`.
- **Why:** AC4, including the incident case the lead asked for.

**10. `src/ocutalon/cls/OcuTalon/Test/Eval/Run.cls` (new).** It extends `OcuTalon.Test.Core.InProduction` and runs only in throwaways and CI.

`OnBeforeAllTests`:
1. Check `ReadyReason`.
2. `PointKeys`.
3. Snapshot and enable `EvalIn` (Task 0).
4. Take the marks: the largest ID of `Delivery`, `Live.Event`, `ApprovalRequest` and `Incident`, and `Budget.State().spent`.
5. Write the fixture folder under the instance's temp directory. It holds:
   - `zz-act`, the act marker case;
   - the refusal cases `zz-badjson` (a `case.json` that isn't JSON), `zz-noid` (no `item.itemId`) and `zz-user` (provenance `user`);
   - `zz-empty`, a folder with no `case.json`.
6. Run 1: `Start(FOLDER, "mail-newsletter,orders-date-format,zz-missing")`, with explicit names.
7. Run 2: `Start(<fixture>, "")`, which lists every subfolder that holds a case.
8. `Wait` 120 s for each run, and push both run Refs into `Supers`.
9. If any step fails, record it as the reason that `Guard` reports, so that every test fails with it.

Tests (each asserts on these runs only):
- **TestItemPath** (AC2): the item-case matrix row, through `Fixture.Headers(run)` and `Between`. The decide request, from the `Intake`→`Decide` header body, has `Kind` `decide`, provenance `untrusted`, `OwnerRef` `eval` and the Item's `ItemId`. Its `Input` holds the case's sender and subject (`Agent.Input`'s quoted data).
- **TestActTurn**: the act-case matrix row. The turn request's body, opened from its header, shows `fresh` and no `SeedText`.
- **TestRefusals**: each `skipped` list holds exactly the expected cases, with their reasons, and each run has one row.
  - Run 1's: `orders-date-format` (kind `incident`) and `zz-missing` (no `case.json`).
  - Run 2's: `zz-badjson`, `zz-noid` and `zz-user`. `zz-empty` is not listed.
- **TestIsolation** (AC3):
  - No header of either run targets `OutcomeRouter`, `Notify`, `Conversation`, `DigestStore`, `ApprovalHold`, `OcuTalonApprovals`, `IncidentManager` or any item ending in `Out`, and none carries an `OcuTalon.Msg.Notification`.
  - No `Delivery` or `ApprovalRequest` row is above its mark.
  - No `Incident` above its mark has an `OwnerRef` other than `eval`.
  - No `Live.Event` above its mark has a `Payload` that contains a run Ref, `ItemId` or `DecisionRef` of the runs.
- **TestUsage** (AC3):
  - Every `Usage` row of the runs' Decision and turn refs (at least 3) has `OwnerRef` `eval`.
  - Their cost sum is above 0, which makes the next check falsifiable.
  - `Budget.State().spent` equals the mark.

`OnAfterAllTests`:
- `RestoreDefault` and update (Task 0's way), then `RestoreKeys`.
- `CaseResult.Remove` for both runs.
- Delete the runs' Decision and Usage rows by `ItemId`.
- Delete the fixture folder, then call the superclass's `OnAfterAllTests`.

**Why:** AC2 and AC3, and the Rule 1 integration criterion.

**11. The spine** (`_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`), Structural Seed line `:1098` (`**Tables:**`).
- After Lane A's `OcuTalon.Digest.Data.Item` clause, add: `` `OcuTalon.Eval.Data.CaseResult` (an evaluation run's result per case, which `EvalIn` opens and `EvalSink` completes, from Story 9.1) ``.
- Set `updated:` to the day's date.
- `uv run --no-cache _bmad/scripts/memlog.py append --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16 --type decision --text "AD-33: OcuTalon.Eval.Data.CaseResult is Lane A's (Story 9.1)"`.
- Run `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16`; it must report `"ok": true`.
- **Why:** AD-33 requires the update in the same change.

**12. DW-337.** The test-infrastructure change is already made (`98f69be` moved `live:cards` from `shards` to `install-upgrade`).
- (a) Its before figures are in Design Notes, and the lead fills its after figures in Verification.
- (b) The `(once)` checks `bash docker/tests/test-ci-config.sh` and `bash docker/tests/test-ci-changes.sh` pass.
- (c) Append a measured record to Rule 21's "Groups" notes in `_bmad/custom/skill-rules.md`.
  - The record names the grouping: `install-upgrade` is install-upgrade, audit and cards; `shards` is `shard:lane-a` and floor; `lane-a` gains `Eval`.
  - The implement stage writes the grouping line, with the commit `98f69be`.
  - The lead adds the CI minutes once they exist.
- Change nothing else in `ci/units.sh`.

**Acceptance Criteria:**
- **AC1, the switch.** Given `OcuTalon.Production` started with `OCUTALON_EVAL` unset or 0 (the judges' compose file passes no such variable), when its items are listed, then:
  - `EvalIn` (`OcuTalon.Eval.In`, adapterless, pool 0) is disabled;
  - `Start` is refused and sends nothing;
  - no item is `EnsLib.Testing.Service`, and `TestingEnabled` is off (`Test.Eval.Switch`).
  - Recreated with `OCUTALON_EVAL=1`, the start enables `EvalIn`: the existing `test-production-restart.sh` row 19, which `live production-restart` re-runs with the built class.
- **AC2, the item path.** Given `EvalIn` enabled and the recorded item case `eval/mail-newsletter/`, when a run sends it, then:
  - `EvalIn` mints a fresh `ItemId`, sets `SourceItemId` to the recorded id and owner `eval`, and sends the Item to `Intake`;
  - `Intake` renders it with `Agent.Input`, calls `Decide` (`decide`) and, on `act`, runs the read-only untrusted turn in a fresh AI session;
  - its `ItemDecision` reaches `EvalSink` only, with `SourceItemId` copied (`TestItemPath`, `TestActTurn`).
- **AC3, isolation.** Given the completed runs, when the isolation test checks what they wrote, then:
  - there is no `Notification`, `Delivery`, live event or approval request, and no incident owned by a session or `instance`;
  - every `Usage` row has owner `eval`, and the daily spend is unchanged (`TestIsolation`, `TestUsage`).
- **AC4, the result row.** Given `EvalSink`, when it receives an `OcuTalon.Msg.ItemDecision`, then the case's row in `OcuTalon.Eval.Data.CaseResult` holds:
  - the run, the case, `SourceItemId` and `DecisionRef`;
  - the outcome, or, for a `diagnose` decision, the cause category, element at fault, fix kind and fix parameters from the `Decision` row;
  - any fallback reason;
  - the cost and the largest request from the `Usage` rows.

  The table is registered, stored and named in the spine (`Test.Eval.Sink`, `test-storage.sh`, `live storage-roundtrip`).
- **Integration (Rule 1).** Given the running production, when `Intake` (Epic 2, the real item) consumes the Item from `EvalIn`, then its `ItemDecision` makes `EvalSink` complete that case's row with the decide Decision's ref and cost (`TestItemPath`, on the real `Intake`, `Decide` and mock).
- **DW-337.** Given `98f69be`, when the `(once)` checks run, then `test-ci-config.sh` and `test-ci-changes.sh` pass, and Rule 21 holds the measured grouping record.
- **Hermeticity.** Given a fresh throwaway stack, when the tests this story adds or changes (`Test.Eval.Switch`, `.Sink` and `.Run`, and `Test.Install.Production`) run forward and in reverse order, then each one passes. Each also leaves the `EvalIn` row, the runner keys, its rows, its messages and its folders as it found them.

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6):**

| AD | What it governs here |
|---|---|
| AD-22 | The evaluation set, `EvalIn`/`EvalSink`, the switch, no `EnsLib.Testing.Service`, the isolation test, the lane-aligned shard |
| AD-30 | `Intake` → `EvalSink` for owner `eval`, and `EvalSink` reads the incident's cause and fix from the `Decision` row |
| AD-29 | Lane A's `OcuTalon.Eval`, worked by runner B |
| AD-33 | One owner, and the spine's Tables line in the same change |
| AD-3 | `DEFAULTGLOBAL` from the registry |
| AD-5 | Storage committed and append-only; the production class unchanged |
| AD-20 | Owner `eval` counts toward no session total and no daily cap |
| AD-26 | `SuperSession` |
| AD-14 | `SourceItemId` |
| AD-16 | The testing switch stays off |

No AC contradicts an AD.

**Decided in-stage:**
1. **Who writes the row.** `EvalIn` opens each case's row as `sent`, and `EvalSink` completes it by `ItemId`. An `ItemDecision` carries neither the run nor the case name, and an unanswered case stays visible for Story 9.2's "every case completes" check. Both writers are Lane A's, and both go through `CaseResult`'s own methods (AD-33).
2. **The run's trace.** The run's Ref is the `SuperSession` of every message of the run (AD-26's thread, with no session), so the isolation test and the clean-up read the run's headers.
3. **The item case's shape.** It is `case.json` with `name`, `kind` (`item` or `injection`), `heldOut`, `description`, `expectation{outcome}` and `recordedBy`, plus `item{itemId, channel, provenance, sender, subject, text, catalogKey?, slots?}`. The case's recorded id is `item.itemId` (AD-22: "keeping the recorded one"). A hand-written case uses its own name.
4. **Which kinds run.** `EvalIn` sends only kinds that hold a recorded Item. `incident` and the turn kinds are skipped with a reason, not failed, so a run over the whole `eval/` folder works before Stories 9.3 and 9.6.
5. **Cost.** `CostUSD` is the attention decision's own cost (NFR-4: "per decision"). The untrusted turn's cost is kept apart in `TurnCostUSD`, and `LargestRequestTokens` covers both (NFR-3).
6. **The act case.** It is a test-only fixture written by the test, through the existing scenario `decide-act-low-confidence`, so no new mock file is needed.
7. **The shard.** `Test.Eval` joins `lane-a` (AD-22: whole areas aligned with the lanes). It adds about 1 to 2 minutes, measured locally (inference until measured), to the `shards` group that DW-337 just shortened. Rule 21's rule applies: rebalance the groups first if the group nears 35 minutes.

**Integration and linkage (Rules 1 and 2):**
- **Consumes:**
  - `OcuTalon.Core.Intake` (Epic 2: renders, decides and sends the eval `ItemDecision`);
  - `Bridge.Data.Decision` and `Usage`, `Usage.Totals`, `Bridge.Ids.NewRef`, `Bridge.Time.NowUtc` and `Ownership.#EVAL`;
  - for tests, `Budget.State`, and `InProduction`, `RunnerFixture`, `Fixture` and `Observe`.
- **Consumed-by:**
  - **Story 9.2:** the report reads `CaseResult` rows by `RunRef`, and the `lane-a.yml` job calls `Start` and `Wait`.
  - **Story 9.3:** adds turn cases and `TurnResult` to `EvalIn` and `EvalSink`.
  - **Story 9.6:** `IncidentManager` sends incident `ItemDecision`s to `EvalSink`. Their `ItemId` is the incident's Ref, which `EvalIn` cannot know when it opens the row, so 9.6 adds a match by the run and `SourceItemId`.
  - **Story 9.5:** the release-candidate run.

**Siblings (extend, don't copy):**
- **Extended or called:**
  - `Test.Core.InProduction` is extended.
  - `RunnerFixture`, `Fixture` and `Observe` are called.
  - `Usage.Totals` is called for cost.
  - `Test.Install.Production`'s `EvalIn` row restore is the model; the class calls `RunnerFixture`'s generic snapshot instead.
- **Copied, with the reason:**
  - **The diagnose-payload read** copies `IncidentManager.cls:417-421`. The file is contended by Epic 7, and the read is 5 lines.
  - **The `MAX(LargestRequestTokens)` query** is a copy because `Usage.cls` is contended and `Totals` has no maximum.
  - **The Decision and Usage clean-up by `ItemId`** copies `Test.Agent.Decide:166-215`, which is a private instance method.
  - **The Item fields** are built as `SimMailbox.In:109-124` builds them, without calling it. That class is Lane B's channel, with session and mailbox rows, and only the Item's fields are shared.
- `Digest.Data.Item` is the model for a Lane A table.

**Declined DW-110:** 9.1's `EvalIn` sends no `turn` request; the turn cases are Story 9.3's, and its plan must carry `SessionMode` `fresh` with no `SeedText` for each one.
- **Why:** `EvalIn`'s only send is the Item to `Intake`, and the turn cases with their `TurnResult` are Story 9.3's.
- **The item path is already fresh.** Its untrusted act turn goes with `SessionMode` `fresh` and no `SeedText` (Intake.cls:185-186, not changed), and `TestActTurn` pins that for owner `eval`.
- **What Story 9.3's plan must carry:** each turn case's request sets `SessionMode` `fresh` with no `SeedText` (or an `OwnerRef` of its own), with a test that two turn cases of one run share no conversation.

**DW-337 before figures** (lead, from CI):

| Head | Before |
|---|---|
| Epic 6's head `bed6d27` | `shards` took 31 min 52 s |
| `289d47a`, `292205f`, `dc44a8c` | `shards` took 32 min 36 s to 34 min 15 s |

On every recent full run, `install-upgrade` was the shorter of the two install groups:

| Head | `install-upgrade` | `install-fresh` |
|---|---|---|
| `b11b36c` | 13 min 25 s | 13 min 39 s |
| `292205f` | 14 min 50 s | 16 min 24 s |
| `dc44a8c` | 14 min 48 s | 15 min 55 s |

`live:cards` takes about 230 s locally. `test-ci-config.sh` names no pin for the unit's group.

**Footprint extensions:** `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` gets the two oracle rows and one docstring sentence. No contended epic owns it. Epic 7's `FixExecutor` row sits on the next line, so a merge may need a one-line hand merge. Also the spine's Tables line and Rule 21's Groups notes (task 12), both lead-sanctioned.

**Shared-surface notes:**
- `Test.Core.RoutingProduction.TestEvalItemWritesNoDeliveryOrEvent` (Lane B) now meets a built `EvalSink`. It finds no `sent` row, logs a warning and stores nothing, so that test stays hermetic.
- Its docstring's sentence "The stub EvalSink answers an error status" goes stale. Record it under `deferred:` for the lead to route; don't edit it.

**After this change:** the spine edit makes the planning artifacts newer than `epic-9-context.md`, so the lead re-runs the pre-warm before Story 9.2's plan (Rule 20).

## Verification

`<B>` stands for:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=9 stage=implement'
```

QA and review use their own stage name and tags: `e9s1q`/`e9s1qw` and `e9s1c`/`e9s1cw`.

- **Tags:** fresh `e9s1i`, warm `e9s1iw`.
- **Warm stack:** run `<B> OCUTALON_RUN_TAG=e9s1iw ci/warm.sh up` once. At the end, also after a failure, run `<B> OCUTALON_RUN_TAG=e9s1iw ci/warm.sh down` and `<B> OCUTALON_RUN_TAG=e9s1i ci/iris.sh teardown`.
- **One command per call:** each runs as a foreground call with `timeout: 600000`.
- **IRIS MCP:** one `iris_execute_tests` per message. Every call passes `server` `ocutalon-slot-b` and namespace `OCUTALON`; check `iris_server_info` (build 154) first.
- **Slot B** is for loading, compiling and exporting the storage block only, never for running tests.

**Shared surfaces:**
- the Items oracle in `Test.Install.Production`, which `TestStubsAnswer`, `test-production.sh` row 16 and `check_items_run` read;
- `ci/units.sh`'s `lane-a` areas;
- `src/short-names.tsv`;
- the set of persistent classes (`TestSqlNames` and `storage-roundtrip`);
- the `EvalIn` System Default Setting row and the item's runtime enabled state;
- `EvalSink`'s handling of any eval `ItemDecision` (`Test.Core.RoutingProduction`);
- `eval/`'s case folders;
- the spine's Tables line.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `bash docker/tests/test-storage.sh` -- expected: every rule passes, including the `EvalCaseResult` registry row, its prefix and its storage block
- (loop) `bash docker/tests/test-ci-config.sh` -- expected: passes, with `Test/Eval` in shard `lane-a`
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s1iw ci/iris.sh class OcuTalon.Test.Eval.Sink` -- expected: `CLASS … passed`
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s1iw ci/iris.sh class OcuTalon.Test.Eval.Switch` -- expected: passed
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s1iw ci/iris.sh class OcuTalon.Test.Install.Production` -- expected: passed (the stub flags)
- (loop) `<B> OCUTALON_RUN_TAG=e9s1i ci/iris.sh class OcuTalon.Test.Eval.Run` -- expected: passed. It runs fresh because `EvalSink`'s running job must load the new code; its first run is Task 0
- (once) `bash ci/checks.sh` -- expected: every block passes
- (once) `bash docker/tests/test-ci-config.sh` -- expected: passes (DW-337 b)
- (once) `bash docker/tests/test-ci-changes.sh` -- expected: passes (DW-337 b)
- (once) `<B> OCUTALON_RUN_TAG=e9s1i ci/iris.sh shard lane-a --part 1/4`, then `--part 2/4`, `--part 3/4` and `--part 4/4`, each in its own call -- expected: every class passed (about 140 to 390 s each, recorded)
- (once) `<B> OCUTALON_RUN_TAG=e9s1i ci/iris.sh shard lane-b` -- expected: passed (about 130 s), including `RoutingProduction` and `Data.Tables`
- (once) `<B> OCUTALON_RUN_TAG=e9s1i ci/iris.sh live production` -- expected: passes (row 14 still refuses `EvalIn`; row 16 skips the built `EvalSink`)
- (once) `<B> OCUTALON_RUN_TAG=e9s1i ci/iris.sh live production-restart` -- expected: passes (row 19 enables and disables the built `EvalIn`)
- (once) `<B> OCUTALON_RUN_TAG=e9s1i ci/iris.sh live storage-roundtrip` -- expected: passes, the compiled `CaseResult` storage equal to the committed one
- (once, task 11) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: `"ok": true`

**Planned mutations (Rule 19).** The implement stage applies each one, observes red, reverts it and writes the `mutation:` line here:

| AC | Mutation | Expected red |
|---|---|---|
| AC1 | `Production.cls` `EvalIn` `Enabled="true"` | `Test.Eval.Switch` |
| AC2 | `EvalIn` sets `SourceItemId` to the new `ItemId` | `TestItemPath` |
| AC3 | `EvalIn` sets `SessionRef` to `instance` | `TestIsolation` and `TestUsage` |
| AC4 | `EvalSink` reads `elementAtFault` from `cause` | `Test.Eval.Sink`'s incident test |

**Task 0 result:** the implement stage records it here.

**DW-337 after figures (the lead fills these):** the `iris (shards)` and `iris (install-upgrade)` job times of CI run 40688986518, or of a later full run, against the before figures in Design Notes. Then the lead adds the minutes to the Rule 21 record from task 12(c).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
