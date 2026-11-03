---
title: 'Story 9.1: Evaluation cases run through the product path and reach nobody'
type: 'feature'
created: '2026-10-28'
status: 'done'
baseline_revision: '55df328685cb1fd558626063f788f1edded54daf'
baseline_commit: '55df328685cb1fd558626063f788f1edded54daf'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-9-context.md'
warnings: ['oversized']
deferred:
  - summary: >-
      Test.Core.RoutingProduction's docstring for TestEvalItemWritesNoDeliveryOrEvent says "The stub EvalSink answers an error status, which the route ignores". EvalSink is built now: it finds no sent row for that Item, logs a warning and stores nothing, still answering OK.
    evidence: |-
      Lane B's test passed unchanged in the lane-b shard of this change (64 classes). The spec forbids editing Lane B's tests, so the sentence is left for the lead to route to Lane B.
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Core/RoutingProduction.cls (docstring of TestEvalItemWritesNoDeliveryOrEvent)
    severity: low
  - summary: >-
      Task 11's lint cannot report "ok": true: lint_spine.py reports "ok": false with 8 low "possible unfilled template token" findings on the spine at HEAD and the same 8 after this change.
    evidence: |-
      Run on a copy of the HEAD spine and on the edited spine, both: total_findings 8, all category placeholder, lines 402, 847, 860, 923 and 927 (format-string examples in prose such as {time}, {day}, {what happened}, {reason}, {entry}, {finding} and {n}). The edit of the Tables line adds none. Clearing them means rewording five unrelated lines of the spine, which the task does not name.
    location: >-
      _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (lines 402, 847, 860, 923, 927)
    severity: low
  - summary: >-
      The memlog entry of Task 11 was not appended: this worktree has no .memlog.md, so memlog.py append failed with FileNotFoundError and wrote nothing.
    evidence: |-
      .memlog.md is gitignored (.gitignore:48) and exists only in the main checkout, which this stage must not touch. The lead appends it there: uv run --no-cache _bmad/scripts/memlog.py append --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16 --type decision --text "AD-33: OcuTalon.Eval.Data.CaseResult is Lane A's (Story 9.1)".
    location: >-
      _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/.memlog.md
    severity: low
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

### Review Findings

Code review, 2026-10-28 (story's first review; full-opus tier, four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 23 rows, 9 entries after grouping including one of the reviewer's own (Rule 2); high 0, medium 2, low 7).

- [x] [Review][Patch] The Hermeticity AC's "leaves its rows, its messages and its folders as it found them" had no pin: deleting `Test.Eval.Run`'s case-row, Decision/Usage or folder clean-up shipped green (verification-gap; medium, fix-risk low, in-story) [src/ocutalon/cls/OcuTalon/Test/Eval/Run.cls:199] — fixed: `OnAfterAllTests` ends with `Leftovers`, which fails the class naming any case row, message, Decision or Usage row of the runs, or the fixture folder, still there; mutation line under Verification.
- [x] [Review][Patch] DW-350: `Test.Core.RoutingProduction.TestEvalItemWritesNoDeliveryOrEvent`'s docstring said the stub EvalSink answers an error status (blind-hunter; low) [src/ocutalon/cls/OcuTalon/Test/Core/RoutingProduction.cls:168] — fixed: the one sentence now says EvalSink finds no sent case row, logs a warning, stores nothing and answers OK (the lead-authorized footprint extension; nothing else in the file changed).
- [x] [Review][Patch] `Test.Eval.Cases`'s header said every case folder of `eval/` has a case.json, but it lists only the folders that hold one (edge-case-hunter; low) [src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls:5] — fixed: the two doc comments say what the test checks.
- [x] [Review][Patch] Rule 21's DW-337 record measured four of the six `Test.Eval` classes (blind-hunter + acceptance-auditor; low) [_bmad/custom/skill-rules.md:289] — fixed: appended the fresh six-class figures from this review's `shard lane-a --part 6/10`.
- [x] [Review][Defer] EvalSink completes a row only by the ItemDecision's `ItemId`, which for an evaluation incident is the incident's Ref (AD-30) [src/ocutalon/cls/OcuTalon/Eval/Sink.cls:49] — deferred: DW-353 `routed owner=9-6-…` (medium, in-epic; this spec's Consumed-by gives the RunRef+SourceItemId match to Story 9.6).
- [x] [Review][Defer] Nothing pins `live:cards` to `install-upgrade` [ci/units.sh] — deferred: DW-354 `wontfix-accepted` (low; a pin is a `docker/tests` rule, out of footprint).
- [x] [Review][Defer] No check reads the spine's Tables line [ARCHITECTURE-SPINE.md:1098] — deferred: DW-355 `wontfix-accepted` (low, out of footprint).
- [x] [Review][Defer] AD-22's as-built text lags 9.1 (the lane-a shard list; the item/injection case.json shape) [ARCHITECTURE-SPINE.md:607] — deferred: DW-356 `wontfix-accepted` (low; an AD text edit is the lead's, Rule 20).
- [x] [Review][Defer] Small helpers copied between `Test.Eval` classes (`Table`/`Sink` `NewRun` and `RowOf`, `Run.Kind`/`In.KindReason`, four COUNT helpers) [src/ocutalon/cls/OcuTalon/Test/Eval/Table.cls:175] — deferred: DW-357 `wontfix-accepted` (Rule 2, weak reason: each warm-safe class keeps its own prefix helpers; a shared TestCase base would be a shard class with no test).

Rejected:
- blind-hunter, no fresh run of QA's classes (low): closed by evidence. This review ran `shard lane-a --part 6/10` fresh, and all six `Test.Eval` classes passed with `Install.Audit` and `Install.PrivateData`. The lead's Rule 19 fresh check still runs before push.
- blind-hunter, the triage summary's counts and the Auto Run Result's file list, mutation count and loop commands are stale (low, 2 rows): the fix edits build-auto's record in this spec, not code.
- blind-hunter, `CostUSD` and `TurnCostUSD` come from different sources, and a timed-out call's late Usage row is missed (low):
  - Reading `TurnCostUSD` from the turn Decision row is Task 4 and Design Note 10.
  - The late row needs a real-model timeout and a later re-read, which belongs to Story 9.2's report design.
  - The "label contradicts the code" part is false: `Usage.Totals(DecisionRef)` is the attention decision's own cost.
- blind-hunter + edge-case-hunter, the teardown runs while cases may still be in flight (low, 2 rows): failure path only, and the run is already red on `Open1`/`Open2`. The fix would be a second bounded wait, and `Leftovers` now names anything left.
- edge-case-hunter, `Switch` would start a real run if `Run`'s teardown left `EvalIn` enabled (low): a cascade after a teardown that `Apply` has already reported red; the fix is a guard.
- edge-case-hunter, midnight between the spend mark and `TestUsage` (low): a window of about 7 s a day; the fix is a day guard.
- edge-case-hunter, Design Note 10's list of methods that log errors leaves out `Complete`'s save failure (low): spec text only; the code logs it and `TestSaveFailure` pins it.
- verification-gap, the absence-check helpers (`Run.MaxId`/`CountAbove`, `Switch.Rows`/`Headers`) would pass on a failed query (false): checked on a warm stack. With `Switch.Rows` pointed at a missing table and no guard, `%GetData` raises `<METHOD DOES NOT EXIST>` and `TestStartRefused` errors. The guard patch was reverted.
- acceptance-auditor, the DW-350 docstring edit breaks the Never list and AD-33 (false):
  - The lead authorized that one sentence as a reported footprint extension.
  - Epic 9 runs on runner B, Lane B's runner, so the owning lane edits its own class.
  - It is a docstring only, and AD-33's Prevents line is untouched.
- acceptance-auditor, Task 10 does not list `zz-plain` and still says "each run has one row" (low): a spec edit; Design Note 13 records the change.
- acceptance-auditor, the `ci/units.sh` edit is not declared as a footprint extension (false): Task 7 directs it, and the stage prompt authorizes the `lane-a` areas line.
- acceptance-auditor, Task 11's lint and memlog are unmet (low): already ledgered as DW-351 and DW-352 (`by-design` at harvest).

## Spec Change Log

## Review Triage Log

### 2026-10-28 - Review pass
- verdicts: 34 findings - high 0, medium 3, low 27, false 2, maybe-false 2
- findings:
  - `[low]` `[patch]` Blind Hunter: EvalIn leaves an orphaned `sent` row when `Send` throws after `CaseResult.Open` - real (only the error-status branch removed the row); fixed: `Dispatch` is wrapped so a throw becomes an error status, `ZzIn` can throw, `TestSendFails` covers it (grouped with the Edge Case Hunter's row 13).
  - `[low]` `[reject]` Blind Hunter: failed SQL reads in `Unanswered`, `Pending` and `CaseNames` look like "nothing to do" - needs the SQL engine itself to fail; the fix adds logging branches to three methods.
  - `[low]` `[reject]` Blind Hunter: `Start` on a missing or empty folder returns OK with 0 sent - the product keeps `EvalIn` disabled and the throwaway mounts `eval/`, so a caller meets this only after a misconfiguration the run's `sent` of 0 already shows; the fix adds a guard.
  - `[low]` `[reject]` Blind Hunter: `names` entries are not checked to be plain folder names - `names` comes from test and CI code, not from a user; no reachable harm.
  - `[low]` `[reject]` Blind Hunter: `TestIsolation` could miss re-sessioned messages, un-listed targets and `Live.Event.Stream` - the test does what the spec's Task 10 lists (the seven targets and `*Out`, the four tables above their marks, the payload refs); no re-sessioning hop is shown to exist.
  - `[low]` `[reject]` Blind Hunter: `TestRefuses` and `TestRefusals` check only one warning text and count the rest - each case's reason is asserted in the `skipped` list, and the warning count is asserted; cosmetic.
  - `[low]` `[reject]` Blind Hunter: an Item with blank text, subject and sender counts as sent and Intake refuses it - Design Notes decision 9 chose this (the row stays `sent` and shows in 9.2's "every case completes" check); recorded cases always carry content (grouped with row 12).
  - `[low]` `[reject]` Blind Hunter: `CaseResult.Remove` with an empty case name deletes the whole run - `Open` rejects an empty case name before any `Remove` call, and the run-wide delete is the spec's `Remove(runRef)`.
  - `[low]` `[reject]` Blind Hunter: `EvalSink` matches the row by `ItemId` only - the `ItemId` is a fresh 128-bit Ref that `EvalIn` mints, so no other decision can carry it.
  - `[low]` `[patch]` Blind Hunter: `Test.Eval.In` leaves the `^OcuTalonTest("EvalInTest","n")` counter - real but trivial; fixed: the folder name comes from a `NewRef()` fragment and no global is kept.
  - `[low]` `[patch]` Blind Hunter: the Rule 21 record mixes two measurements of `lane-a` part 3 (125 s before `Test.Eval.In` existed, 119 s after) - real; fixed in the record (final figures re-measured in the (once) shard runs).
  - `[low]` `[reject]` Edge Case Hunter: blank sender, subject and text are sent and Intake refuses them - same root as row 7.
  - `[low]` `[patch]` Edge Case Hunter: `Dispatch` throws after `Open` leaves the case's row - same root as row 1; fixed there.
  - `[low]` `[reject]` Edge Case Hunter: the status of `Remove` after a failed send is discarded - a `Remove` failure needs the SQL engine to fail; no realistic path.
  - `[low]` `[reject]` Edge Case Hunter: `Start` with a missing folder or a `names` of commas only returns a run with 0 cases - same root as row 3.
  - `[low]` `[reject]` Edge Case Hunter: a `names` entry with a separator or `..` - same root as row 4.
  - `[low]` `[reject]` Edge Case Hunter: `Wait` with an empty run Ref returns 0 - `Start` returns an error status and no Ref in that case, and every caller waits on the Ref it got.
  - `[low]` `[reject]` Edge Case Hunter: `Test.Eval.Run.Prepare` leaks rows when `Start` throws after minting the Ref - `Start` returns statuses and does not throw on a path shown; the stack is a throwaway destroyed after the run.
  - `[low]` `[reject]` Edge Case Hunter: the class comment says a case not sent is logged, but a `ProcessInput` error status is only put into `skipped` - the matrix row is about `OnProcessInput`'s reasons, which are logged; the framework error is rare and shown in `skipped`.
  - `[low]` `[defer]` Edge Case Hunter: the stale "stub EvalSink" comment of `Test.Core.RoutingProduction` and the warning row that its test now leaves in the log - the comment is already in `deferred:`; the warning is by design (Design Notes, shared-surface notes) and no assertion reads the log there.
  - `[medium]` `[patch]` Verification Gap: no test distinguishes `CostUSD` read from the Usage rows from `Decision.CostUSD` - confirmed (every Sink test set equal costs); fixed: `TestCostFromUsage` and its mutation line.
  - `[medium]` `[patch]` Verification Gap: `Start` is only run with `sent` 0 or 1 through the production, so `Set sent = 1` and sessions shared between cases ship green - confirmed; fixed: run 2 holds a second sendable case, `TestTwoCases`, and two mutation lines (grouped with row 29).
  - `[false]` `[reject]` Verification Gap: `Switch.TestStartRefused` runs the refusal only when `OCUTALON_EVAL` is not 1 - spec Task 8 says exactly this ("When the variable is 1: ... the class calls no Start"), and CI starts the stack with it at 0, so the refusal branch runs there.
  - `[maybe-false]` `[reject]` Verification Gap: the absence checks run once the rows are decided, so a later hop would not be seen - would need a hop after `Intake.Finish`, which none sends; if true it would be low.
  - `[maybe-false]` `[reject]` Verification Gap: the `Delivery` and `ApprovalRequest` counts are not scoped by owner and could flake on a background writer - the spec's Task 10 says no row above the mark; no writer in a throwaway is shown; if true it would be low.
  - `[low]` `[reject]` Verification Gap: `Test.Eval.Switch` reds if `Test.Eval.Run`'s teardown fails - a failed teardown is itself reported by `Run`; a second red on the same cause.
  - `[low]` `[defer]` Verification Gap, other findings: the stale `RoutingProduction` comment - already in `deferred:` (row 20).
  - `[false]` `[reject]` Intent Alignment 3.1: the live proof enables `EvalIn` with `PutDefault`, not through the install step - AC1 delegates the install-step path to `live production-restart` row 19, which ran green with the built class.
  - `[medium]` `[patch]` Intent Alignment 3.2: two cases under one SuperSession are never sent through the production and no assertion compares `SessionId` across cases - same root as row 22; fixed there.
  - `[low]` `[reject]` Intent Alignment 3.3: the incident cause and fix are exercised only on synthetic rows in `Test.Eval.Sink` - the incident path through `IncidentManager` is Story 9.6's (Never list); the spec's Task 9 asks for exactly this.
  - `[low]` `[reject]` Intent Alignment 3.4: a capped day and `GatewaySpendUSD` are not exercised - the cap and the gateway are the bridge's (Epic 7, contended); the spec asks for the daily spend to be unchanged, which `TestUsage` pins.
  - `[low]` `[reject]` Intent Alignment 3.5: "reaches nobody" is checked at message and table level, not at the network - the spec's Task 10 lists the checks; the mock is the only configured egress.
  - `[low]` `[reject]` Intent Alignment 3.6: the case is written by hand, its expectation `ignore` is not compared with the live `digest`, and the default folder holds nothing outside a throwaway - the spec fixes the case and its expectation (Task 5); scoring is Story 9.2's.
  - `[low]` `[reject]` Intent Alignment 3.7: the `shards` figure predates `Eval` joining `lane-a` - the lead's after-figures are at `98f69be` by the spec; the local cost of `Eval` is in the same record.

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

8. **Task 0 (the switch at run time).** `Ens.Director.UpdateProduction()` after `PutDefault("EvalIn","Enabled",1)` is enough, so `Test.Eval.Run` sets up and restores with it, and checks the director's answer after each update (`Apply`). See the Task 0 result in Verification.
9. **EvalIn, small choices.**
   - The case's name is its folder name, and a name given twice in `names` is sent once.
   - A recorded provenance that is absent counts as untrusted; one that is present and not `untrusted` is refused. The Item's provenance is always `untrusted`.
   - A case whose Item has no text, subject or sender is not refused by EvalIn: Intake refuses it with a warning, and the row stays `sent`, visible to Story 9.2's "every case completes" check.
   - `CaseResult.Remove(runRef, caseName)` takes an optional case name (the failed send deletes its one row), and `CaseResult.Unanswered(runRef)` counts the `sent` rows for `Wait`. `EvalIn.Scalar` is public because `EvalSink` reads the Decision payload with it.
   - The one send is a private `Dispatch` seam, as `SimMailbox.In.Send` is, so that `Test.Eval.In` (warm-safe, with the double `Test.Eval.ZzIn`) checks the Item, the open row, the SuperSession, the refusal reasons and the failed send without a production. The matrix row "Send fails" has no other test.
10. **EvalSink, small choices.**
   - `TurnCostUSD` is the turn Decision row's own `CostUSD` (Decide writes it from `Usage.Totals`, so it is empty when any of the turn's rows is unpriced).
   - An empty `Payload` on a diagnose Decision (a fallback) leaves the cause fields empty and logs nothing; a payload that is not a JSON object is logged as an error (`ReadDiagnosis`). The warnings come from `Complete` and the errors from `OnMessage`, `ReadDiagnosis` and `Largest`.
11. **Test.Eval.Run, small choices.**
   - A case still undecided after the wait is a failure of `TestItemPath` or `TestActTurn`, not a setup failure, so the other tests still read what the runs wrote. Rule 19's mutation "SessionRef is instance" then fails `TestIsolation` and `TestUsage` on their own assertions, not through the guard.
   - `TestUsage` finds the Usage rows by the ItemId that EvalIn opened its rows with, so it needs no completed row; it also checks that each recorded decision has a row of owner `eval`.
   - `OnAfterAllTests` removes the runs' messages itself before the superclass does, because the superclass skips that when `Missing` is set.
12. **Measured shard cost (replaces decision 7's inference).** `Test.Eval` takes 8.5 s in the `lane-a` shard (`Run` 7.1 s, `Sink` 1.2 s, `In` 0.2 s, `Switch` 0.03 s), not 1 to 2 minutes. Rule 21 holds the record.
13. **Review patches (2026-10-28).**
   - `EvalIn.Send` turns an exception from `Dispatch` into an error status, so a send that throws deletes the case's row like one that fails (`ZzIn` throws when `^OcuTalonTest("EvalIn","throw")` holds a text; `TestSendFails` covers it).
   - `Test.Eval.In` names its folder from a `NewRef()` fragment and keeps no counter global.
   - `Test.Eval.Sink.TestCostFromUsage` pins that `CostUSD` is the sum of the Usage rows (the Decision's own cost differs there) and that an unpriced row leaves it empty although the Decision holds a cost.
   - `Test.Eval.Run` run 2 holds a second sendable case, `zz-plain`; `TestTwoCases` pins two trace sessions under the run's one SuperSession, one Item, row and decision each, and `Sent2` is 2.

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

**Owner conditions (2026-10-28, applied by the lead):**
- **U-131 (`CaseResult` kept as ruled: no grants, no purge task).** Condition: `EvalIn` stays off on the demo host and in a judge's install. If that ever changes, a purge task for `OcuTalon.Eval.Data.CaseResult` comes with the change. The default-off state is already pinned on three levels: `Test.Eval.Switch` `TestDefinition` (`OcuTalon.Production` defines `EvalIn` with `Enabled` 0), `Test.Eval.Switch` `TestRow` (the Production install step writes the `EvalIn` row as 1 only for `OCUTALON_EVAL` "1"), and `docker/tests/test-production.sh` row 14 (on a start from the judges' compose file, `CreateBusinessService("EvalIn")` is refused as disabled), which CI's `live production` unit runs.
- **U-130 (the split kept).** The incident-case criterion is Story 9.6, which waits for Epic 7; from Epic 7's merge, 9.6, then 9.5, then Epic 9's close are the critical path to Epic 11.

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
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s1iw ci/iris.sh class OcuTalon.Test.Eval.In` -- expected: passed (the class the implement stage added for the matrix rows "Case not sent" and "Send fails")
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

- mutation: `Production.cls` `EvalIn` `Enabled="false"` changed to `Enabled="true"` -> `Test.Eval.Switch` `TestDefinition` went red ("EvalIn is disabled in the definition"); reverted from a backup (sha identical), warm stack.
- mutation: `Eval/In.cls` `SourceItemId` set to the new `ItemId` -> `Test.Eval.Run` `TestItemPath` went red (the Item's ids, "is not the recorded id", the row's ids and the ItemDecision copy); reverted, warm stack.
- mutation: `Eval/In.cls` `SessionRef` set to `Ownership.#INSTANCE` -> `Test.Eval.Run` on a fresh stack: `TestIsolation` ("no message of the runs is addressed to a router, notice, conversation, digest, approval, incident or Out item") and `TestUsage` ("every one is owned by eval", "the daily spend is as it was before the runs") went red, as did `TestItemPath` and `TestActTurn` (the cases were never decided within the 120 s waits; 247 s in all); reverted.
- mutation: `Eval/Sink.cls` `elementAtFault` read from `cause` -> `Test.Eval.Sink` `TestIncident` ("the element at fault is the payload's, not the cause's") and `TestNoFix` went red; reverted, warm stack.
- mutation: `Eval/In.cls` failed send keeps its row (the `Remove` line deleted) -> `Test.Eval.In` `TestSendFails` went red ("and the row is deleted", "the case is sent when the send works"); reverted, warm stack.
- mutation (review patch): `Eval/Sink.cls` `CostUSD` read from `decision.CostUSD` instead of `Usage.Totals` -> `Test.Eval.Sink` `TestCostFromUsage` went red ("the cost is the sum of the Usage rows" and "an unpriced Usage row makes the cost empty"), every other Sink test staying green; reverted from backup (sha identical), warm stack.
- mutation (review patch): `Eval/In.cls` the Try/Catch around `Dispatch` removed -> `Test.Eval.In` `TestSendFails` went red on its throw case ("and the row is deleted", "the case is sent when the send works"); reverted, warm stack.
- mutation (review patch): `Eval/In.cls` `Start`'s `Set sent = sent + 1` changed to `Set sent = 1` -> `Test.Eval.Run` `TestActTurn` went red ("run 2 sent two cases"); reverted, warm stack.
- mutation (review patch): `Eval/In.cls` `Send` reuses the first case's trace session (a process variable carries `..%SessionId` from one dispatch to the next) -> `Test.Eval.Run` `TestTwoCases` went red ("each is its own trace session: 74 and 74" and, twice, "holds its own ItemDecision for EvalSink"); reverted, warm stack. A first attempt that set `..%SessionId` to the run Ref (not a number) broke every send and showed nothing about sessions, so it was discarded.

**Task 0 result:** `PutDefault("EvalIn","Enabled",1)` followed by `Ens.Director.UpdateProduction()` makes `CreateBusinessService("EvalIn")` succeed, and `RestoreDefault` followed by `UpdateProduction()` makes it refuse again ("Configuration item 'EvalIn' is disabled"). `RestartProduction()` is not needed, and `Test.Eval.Run` uses `UpdateProduction()` for both.
- Probed by hand on the warm throwaway's running production: the update took 0.04 s to enable and 0.01 s to restore, and `NotRunning()` was empty after each.
- Then on fresh throwaways, where `Apply` does exactly this at setup and teardown and asserts the director's answer after each update. The first fresh run passed both steps before it failed on a fixture bug (a `%ConstructClone` call, fixed); the runs after it passed, the last at 7.3 s after an 88 s start.

**Results of the implement stage (2026-10-28; tags `e9s1i` fresh and `e9s1iw` warm; ARM; `LOCK` lines: `LOCK acquired warm-iris project=ocutalon-warm-e9s1iw-1793193441-1212`, and `LOCK acquired` / `LOCK released throwaway-iris` once for every fresh call):**
- `test-storage.sh`, `test-ci-config.sh`, `test-ci-changes.sh` and `ci/checks.sh` (13 blocks) passed.
- Warm: `Test.Eval.Sink` (12 tests of 9 methods), `Test.Eval.Switch`, `Test.Eval.In` and `Test.Install.Production` passed, forward and in reverse order, with `Test.Eval.Run` (warm, 7 s): the stack held no case row, no `eval` Decision or Usage row, no header of `EvalIn`, no AI session, no step, no fixture folder, the EvalIn row 0, EvalIn refused and the keys at the placeholder after them.
- Fresh: `Test.Eval.Run` passed (96 s with the start; 7.3 s of tests). `shard lane-a` parts 1 to 4 passed (346, 149, 125 and 395 s; part 3 again after `Test.Eval.In` was added, 119 s). `shard lane-b` passed (64 classes, 238 s). `live production`, `live production-restart` (row 19 enables and refuses the built `EvalIn`) and `live storage-roundtrip` (80 classes, the compiled `CaseResult` storage equal to the committed one) passed.
- After the review patches (the parent stage; same tags): `test-storage.sh`, `test-ci-config.sh`, `test-ci-changes.sh` and `ci/checks.sh` passed. Warm: `Test.Eval.Sink`, `In`, `Run`, `Switch` and `Test.Install.Production` passed, the four Eval classes also in reverse name order, and the warm stack held no case row, `eval` Decision or Usage row, `EvalIn` header, AI session or fixture folder afterwards, with `EvalIn` refused. Fresh: `Test.Eval.Run` passed in `shard lane-a` part 3 (7.2 s); `shard lane-a` parts 1 to 4 passed (358, 155, 115 and 394 s, stack starts 93, 81, 81 and 81 s); `shard lane-b` passed (64 classes, 229 s); `live production`, `live production-restart` and `live storage-roundtrip` (80 classes) passed. `LOCK` lines: `LOCK acquired warm-iris project=ocutalon-warm-e9s1iw-1793197664-60217`, and `LOCK acquired` / `LOCK released throwaway-iris` once for every fresh call.
- Not done: `lint_spine.py` reports `"ok": false` (8 low findings, the same as at HEAD) and the memlog append could not run in this worktree; both are in `deferred:`.

**DW-337 after figures (the lead fills these):** the `iris (shards)` and `iris (install-upgrade)` job times of CI run 40688986518, or of a later full run, against the before figures in Design Notes. Then the lead adds the minutes to the Rule 21 record from task 12(c).

**DW-337 after figures (lead, 2026-10-28):** CI run 40688986518 on `98f69be` (every group ran: the push changed `ci/`), all six IRIS jobs started 12:34:59Z: `iris (shards)` 26 min 23 s (before: 32 min 36 s to 34 min 15 s), `iris (install-upgrade)` 18 min 27 s (before: 13 min 25 s to 14 min 50 s), `install-fresh` 13 min 35 s, `browser` 23 min 1 s, `image` 21 min 39 s, `production` 9 min 36 s. The longest job is now `shards` at 26 min 23 s, under REL-4's 35 minutes and the 40-minute job limit. The implement stage writes these minutes into the Rule 21 record of task 12(c) with the grouping line.

**QA stage (2026-10-28; tags `e9s1q` fresh and `e9s1qw` warm; `LOCK` lines as before, `LOCK acquired` / `LOCK released throwaway-iris` once for every fresh call and `warm-iris` for the warm stack).** Test files, all uncommitted:
- `src/ocutalon/cls/OcuTalon/Test/Eval/Table.cls` (QA, new, warm-safe): `CaseResult.Open`, `Pending`, `Unanswered`, `Remove` and `EvalIn.Wait` directly (5 tests).
- `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls` (QA, new, warm-safe): the recorded `eval/` cases through the `ZzIn` double (`TestRecordedCases`, `TestNewsletterCase`); it reads the mounted `eval/`, so it needs a throwaway or CI stack.
- `src/ocutalon/cls/OcuTalon/Test/Eval/ZzSink.cls` (QA, new): a double of `EvalSink` whose size read can throw; not a test class (no `Method Test`).
- `src/ocutalon/cls/OcuTalon/Test/Eval/Sink.cls` (QA, extended): `TestCauseOnlyFromDiagnose`, `TestLongValues`, `TestSaveFailure`, `TestNeverThrows`; `Deliver` now calls `DeliverTo`.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Run.cls` (QA, extended): `TestHops` and the `ITEMPATH` parameter (the hops a throwaway run was seen to use: `EvalIn`, `Intake`, `Decide`, `EvalSink`, `TriageAgent`, `ChatAgent`, `AgentSteps`, `Ens.Alarm`).

QA mutations (each applied, observed red, reverted from a backup with the sha identical and `git status --short` unchanged; warm unless noted):
- mutation: `CaseResult.Unanswered` counts every state (the `AND State = ?` dropped) -> `Test.Eval.Table` `TestUnanswered` ("the run has one sent row left") and `TestWait` (the wait ran its full 30 s).
- mutation: `CaseResult.Pending` ignores the state -> `Test.Eval.Table` `TestPending` ("a decided row is no longer pending").
- mutation: `CaseResult.Open`'s check of an empty run, case or ItemId turned off -> `Test.Eval.Table` `TestOpen` (the three refusals and "nothing was stored").
- mutation: `CaseResult.Remove` ignores the case name -> `Test.Eval.Table` `TestRemove`.
- mutation: `EvalIn.Wait` returns 0 whatever is open -> `Test.Eval.Table` `TestWait`.
- mutation (AC4): `EvalSink` reads the payload of a decide Decision too (the `Kind = "diagnose"` test dropped) -> `Test.Eval.Sink` `TestCauseOnlyFromDiagnose` only; every earlier Sink test stayed green.
- mutation (AC4): `EvalSink` keeps `causeCategory` at its full length (the `$Extract` dropped) -> `Test.Eval.Sink` `TestLongValues` (the row cannot be saved and stays sent).
- mutation (AC4): `EvalSink` does not log a failed row save -> `Test.Eval.Sink` `TestSaveFailure`.
- mutation (the Boundaries' "never throws"): the Try/Catch of `EvalSink.OnMessage` removed -> `Test.Eval.Sink` `TestNeverThrows` (the exception reached the test).
- mutation (AC2): `EvalIn` `KINDS` changed from `item,injection` to `injection` -> `Test.Eval.Cases` `TestRecordedCases` ("mail-newsletter: a case of kind item is sent").
- mutation (AC2, Task 5): `eval/mail-newsletter/case.json` expectation `ignore` changed to `digest` -> `Test.Eval.Cases` `TestNewsletterCase`.
- mutation (AC3): `EvalSink` sends the `ItemDecision` on to `FixExecutor` (an item on no refusal list) -> `Test.Eval.Run` `TestHops` ("every message of the runs is between items of the item path" and "EvalSink sends no request"), with `TestIsolation` staying green; fresh stack.
- mutation (AC3, the table checks): `EvalSink` saves a `Delivery` row of owner `eval` -> `Test.Eval.Run` `TestIsolation` ("no Delivery row was written"); fresh stack.
- mutation (AC1, the refusal with `OCUTALON_EVAL` unset): `EvalIn.Start` creates the service as a shadow instance, not through `Ens.Director.CreateBusinessService` -> `Test.Eval.Switch` `TestStartRefused` ("Start is refused", "the error says disabled"); fresh stack.
- mutation (DW-337): `Eval` removed from `lane-a` in `ci/units.sh` -> `bash docker/tests/test-ci-config.sh` (`units` and `test classes` rules red, the five `Test/Eval` classes "in no shard").
- mutation (AC4, the registered table): `CaseResult`'s `DEFAULTGLOBAL` changed to `^OcuTalonP.EvalCaseResults` -> `bash docker/tests/test-storage.sh` (`registry-class`, `datalocation`, `locations`).
- mutation (Hermeticity): `Test.Eval.Run.OnAfterAllTests` no longer restores the `EvalIn` row -> `Test.Eval.Run` itself ("After the production update EvalIn is still enabled", from `OnAfterAllTests`) and then `Test.Eval.Switch` `TestStartRefused` on the same stack; the contaminated warm stack was torn down and a clean one started.
- `mutations_demonstrated=17` (QA's; the implement stage's nine stand).
- mutation (code review, Hermeticity): `Test.Eval.Run.OnAfterAllTests` no longer removes the runs' case rows (the `CaseResult.Remove` loop deleted) -> `Test.Eval.Run` went red from `OnAfterAllTests` ("The clean-up left case rows of run 1, case rows of run 2") with every test method green; reverted from a backup (sha identical, `git status --short` and `git diff --stat` unchanged); fresh stack (tag `e9s1c`). The patched class had passed fresh in `shard lane-a --part 6/10` just before.

Pinned by nothing (observed, not fixed; both need an edit outside this story's footprint):
- DW-337's group of `live:cards`: moving it back from `install-upgrade` to `shards` leaves `test-ci-config.sh` and `test-ci-changes.sh` green. Rule 21's record is the only pin.
- AD-33's spine Tables line: no check reads the spine, so a missing `CaseResult` there would pass every test (it is there, `ARCHITECTURE-SPINE.md:1098`).

QA results: the warm classes `Test.Eval.Cases`, `In`, `Run`, `Sink`, `Switch`, `Table` and `Test.Install.Production` passed forward and in reverse name order in one stack (`Run` warm 6.6 to 7.1 s); then, after a probe by `docker exec ... iris session` on that stack, it held no `CaseResult` row, no `eval` Decision or Usage row, no header from `EvalIn` or to `EvalSink`, no `^OcuTalonTest("EvalIn")` or `("EvalSink")`, `EvalIn` refused and its default row 0 (the one log row, "Host Class OcuTalon.Eval.Sink has been recompiled", is the warm reload's, not a test's). Fresh: `Test.Eval.Run` passed (7.3 s of tests after an 82 s start) on the final tree. `test-ci-config.sh`, `test-ci-changes.sh`, `test-class-rules.sh` and `test-storage.sh` passed; `ci/iris.sh classes lane-a` lists the six `Eval` test classes. Torn down: `e9s1qw` (`ci/warm.sh down`) and `e9s1q` (`ci/iris.sh teardown`), the lane-b lock folder empty.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `EvalIn` and `EvalSink` are built and their stubs are gone. `OcuTalon.Eval.In.Start` creates the disabled-by-default service through the director, mints a run Ref, and sends each recorded item case to `Intake` as an Item owned by `eval` (fresh `ItemId`, `SourceItemId` the recorded id, provenance `untrusted`, the run's Ref as `SuperSession`). `OcuTalon.Eval.Sink` completes one `OcuTalon.Eval.Data.CaseResult` row per case from the `ItemDecision` and the bridge's `Decision` and `Usage` rows, including a diagnose payload's cause and fix. `Test.Eval.Run` proves on the running production, in a throwaway, that two runs reach nobody and leave the daily spend unchanged. DW-337's measured grouping record is in Rule 21 of `_bmad/custom/skill-rules.md`.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Eval/In.cls`: `Start`, `Wait`, `OnProcessInput`, the case refusals and the Item builder.
- `src/ocutalon/cls/OcuTalon/Eval/Sink.cls`: the row completion, the diagnose read, the cost and size reads, the warnings.
- `src/ocutalon/cls/OcuTalon/Eval/Data/CaseResult.cls` (new): Lane A's result table with its committed storage block.
- `src/short-names.tsv`: the `EvalCaseResult` registry row.
- `eval/mail-newsletter/case.json` (new): the first recorded item case.
- `src/ocutalon/cls/OcuTalon/Test/Eval/{Switch,Sink,Run,In,ZzIn}.cls` (new): the switch, the sink rows, the live runs, `EvalIn`'s per-case handling and its test double.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`: the two oracle rows read `"stub": 0` and one docstring sentence.
- `ci/units.sh`: `Eval` joins the `lane-a` areas.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: the Tables line names `CaseResult`; `updated:` is 2026-10-28.
- `_bmad/custom/skill-rules.md`: the appended DW-337 record under Rule 21's "Groups" notes.
- This spec: Task 0 result, mutation lines, Design Notes items 8 to 13, the triage log, `deferred:`.

**Review findings (34 from four layers; see the triage log).** Patches applied (4 entries): a send that throws now deletes the case's row (`EvalIn.Send`, `ZzIn`, `TestSendFails`); `Test.Eval.In` keeps no counter global; `TestCostFromUsage` pins that `CostUSD` is read from the Usage rows; run 2 holds a second sendable case and `TestTwoCases` pins two trace sessions under one SuperSession (this also fixed the Rule 21 record's mixed `lane-a` part-3 figure). Patched by verdict: medium 2 entries (3 findings), low 2 entries. Deferred: the stale "stub EvalSink" comment of `Test.Core.RoutingProduction` (already in `deferred:`). Rejected, with reasons in the log: 23 low findings (silent SQL-failure returns, a missing or empty folder, path-shaped `names`, a blank-content case, `Remove` with an empty case name, the `ItemId`-only match, the breadth of `TestIsolation`, the checks of the warning texts, a re-run of the incident and cap paths that other stories own, and similar), 2 false, 2 maybe-false (low if true).

**Follow-up review recommended: true.** Two medium entries were patched. The unverified risk is the patched `Test.Eval.Run` (the `zz-plain` fixture and the order of the `zz-act`, `zz-plain` sends that `TestTwoCases` assumes) and `TestCostFromUsage`: they ran green and went red under their mutations, but no second independent review has read them.

**Verification.** `test-storage.sh`, `test-ci-config.sh`, `test-ci-changes.sh` and `ci/checks.sh` passed. Warm: `Test.Eval.Sink`, `In`, `Run`, `Switch` and `Test.Install.Production` passed, and the Eval classes also in reverse order. Fresh: `shard lane-a` parts 1 to 4 (358, 155, 115 and 394 s), `shard lane-b` (64 classes, 229 s), `live production`, `live production-restart` (row 19) and `live storage-roundtrip` (80 classes) passed. Nine mutations were applied, observed red and reverted from backup with the tree byte-identical (Verification section). Task 0: `UpdateProduction()` after `PutDefault` is enough to enable and to refuse `EvalIn`. Both runtime tags are torn down and the lane's lock folder is empty. The `LOCK` lines are in the Verification results.

**Residual risks and deviations.**
- `lint_spine.py` reports `"ok": false` (8 low "possible unfilled template token" findings in prose format examples on lines 402, 847, 860, 923 and 927). The spine at `HEAD` gives the same 8, so this change adds none, but Task 11's "must report `"ok": true`" is not met; clearing them rewords five unrelated spine lines, which this stage's footprint does not allow. It is in `deferred:` for the lead.
- The memlog entry for AD-33 was not appended: the worktree has no `.memlog.md` (it is gitignored and lives in the main checkout). The lead appends it there (command in `deferred:`).
- The spine edit makes the planning artifacts newer than `epic-9-context.md`: the lead re-runs the pre-warm before Story 9.2's plan.
- Four class calls of the reverse-order check ran one after another inside one shell command, not one per tool call; they never overlapped.
