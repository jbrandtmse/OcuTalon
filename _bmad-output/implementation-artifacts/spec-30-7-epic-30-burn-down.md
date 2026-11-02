---
title: 'Epic 30 burn-down'
type: 'bugfix'
created: '2026-11-02'
status: 'ready-for-dev'
baseline_revision: '0e5d27304acbf24dcc1896176578ec0013d8fda1'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: ['oversized']
deferred:
  - summary: >-
      An answer that outlives TASKSECONDS before its approval task exists leaves the hold waiting on its 24 hour timer: Reconcile pass 1 discards the late task and sends the hold no deferred response (DW-462, rows 18 (b)).
    evidence: |-
      Measured at implementation on build 154U: EnsLib.Workflow.Engine.%CancelRequest discards the task without a deferred response, so the hold never learns of it; the row stays approved until the timer delivers the outcome. Test (b) of TestAnswerBeforeTheTaskExists pins only the documented 5 s contract.
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Approval.cls (CompleteHoldTask, Reconcile pass 1)
    severity: medium
  - summary: >-
      Test.Eval.KeyProof.Walk now runs a list check on every node's data and a subscript decode on every node's reference, which may slow the key-proof global scan on large databases.
    evidence: |-
      Unmeasured. Settle it by timing eval/key-proof.sh's global scan (GlobalHits over all local databases) before and after this story on a throwaway; if the scan grows past its budget, test the cheap substring first (done) and skip the decode for nodes whose first byte cannot start a list.
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Eval/KeyProof.cls (Holds, HoldsSubscript)
    severity: medium (unverified)
  - summary: >-
      Test.Install.Retention failed twice because the two stock Ens purge tasks did not start inside the test's wait, in a run with a second IRIS stack beside it and once in the implement pass.
    evidence: |-
      The OcuTalon purge task's own assertions passed in every run and four other fresh runs of the same tree passed. Settle whether this change contributes by running the class on CI over several pushes (the DW-349 flake class) or on a throwaway beside a loaded machine with and without the diff.
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Install/Retention.cls
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** Epic 30 still owns eight ledger entries:
- The 90-day purge leaves Turn, Delivery and Session rows behind, so a kept turn can read a purged decision (DW-437).
- A replay interrupted by a crash stays `executing` forever (DW-444).
- A replay that fails on the provider does not say why (DW-470).
- `Bridge.Redact` misses two `key_like` shapes (DW-386).
- The key proof misses a key inside a `$List` element (DW-448).
- Approval row 13 flakes on slow runners (DW-462).
- `IncidentManager.Purge` keeps its own copy of the day rule (DW-371).
- `list_productions` cannot say whether a production is running (DW-541).

**Approach:** One small, separable task per entry, in this priority order: DW-437, DW-386, DW-444, DW-470, DW-448, DW-462, DW-371, DW-541. Each task carries its own tests.
- **Independent of 30.1.** Nothing here uses or assumes Story 30.1's code: compaction, `Bridge.Compaction`, `Decide.TimerFor`/`RequestLimit`, `Usage.FromEstimate`, the thinking smoke.
- **Deferrable on its own.** The story lands in commits of its own, so the Contest Planner may move it after the rc1 tag if the forecast slips past 2026-11-03 18:00Z.

## Boundaries & Constraints

**Always:**
- **Purge.** The host purge (`OcuTalon.Data.Purge`) uses the same `now`, and so the same cutoff (`Bridge.Time.DaysCutoff`), as `Bridge.Purge.Run` in one `Retention.Purge` call.
  - Turns go by `CreatedAt < cutoff`, deliveries by `RecordedAt < cutoff`.
  - A Session row goes only when all of these hold:
    - its `CreatedAt` is before the cutoff;
    - no Turn, Delivery or Decision of it is at or after the cutoff;
    - it is not current. Current means any one of: a live CSP session holding its Ref (signed in); a live Telegram pairing; a pending, approved or executing approval request; a BackgroundCheck row (watch); a pending reminder.
  - The checks run again right before each delete.
- **What the purge may touch.** Every delete names an `OcuTalon_Data` table. Nothing touches `%SYS`, an IRIS audit entry, a message or an AI session.
- **Replay lock.** A replay holds `LOCK ^OcuTalon.Bridge.Replay(ref)` from before `StartExecution` until after `FinishExecution`, and releases it on every path.
  - Reconcile closes an executing `tool_call` row only when it can take that lock at once (no live replay). It closes the row through `FinishExecution(ref, "interrupted")` and never re-runs the call (NFR-13).
- **Test data.** Fake secrets are built from fragments at runtime, so no committed file matches `key_like`.
- **SQL.** Every new SQL checks `%SQLCODE`, so `docker/tests/test-class-rules.sh` stays green.
- **Comments.** Comments state the contract only (Rule 14).
- **Stored data.** No stored property is added, renamed or retyped, and no `Storage` block changes.

**Never:**
- No edit to `Data/Session.cls`, `Test/Data/Session.cls`, `Bridge/Msg/Enum.cls`, `Test/Msg/Catalog.cls`, or any other contended path (dispatch list).
- No new catalog key, FallbackReason value or stored column.
- No AD other than AD-27 is amended.
- No purge of `%AI.Agent.Session`, ConversationLink, GuideState, SimMessage or Reminder rows.
- No change to Lane B's `Test.Web.SessionEvents.ReferenceHits`, `Data.Pairing.Purge`, the web chip text, or `ci/mock/scenarios/B/`.
- No real model key, and no destructive or purge run on slot B.

## I/O & Edge-Case Matrix

| # | Scenario | Input / State | Expected Output / Behavior |
|---|---|---|---|
| 1 | DW-437 old turn | Session S1 created 91 d ago, idle, not current. Turn T1 created 91 d ago, with triage and reply Decisions, Usage and a Delivery 91 d old. Run `Retention.Purge(90)` | T1, its Delivery, Decisions and Usage, and S1 are gone |
| 2 | DW-437 kept turn | Session S2. Turn T2 created 89 d ago, with Decisions and Usage 89 d old | T2 kept. `T2.ShownDecisionRef()` names an existing Decision. `Ownership.TurnCost(T2)` equals its Usage sums (not 0). `Live.Payload.ChatMessage.FromRow(T2)` carries the decision and the cost |
| 3 | DW-437 boundary | `Data.Purge.Run(90, now)` with a turn and a delivery at exactly the cutoff, and others 1 s before it | Those at the cutoff stay; those 1 s before go. Every kept turn's decisions exist after `Bridge.Purge.Run(90, now)` with the same `now` |
| 4 | DW-437 cond. 1: activity | Old idle session with one Turn, or one Delivery, or one Decision (`OwnerRef`) at or after the cut | Kept, in each of the three cases |
| 5 | DW-437 cond. 1: current | Old session with no newer rows, kept by exactly one of: a live CSP session in the store holding its Ref; a pairing; an approval (pending, approved, executing); a BackgroundCheck; a pending reminder | Kept, in each case. With only an expired store entry, a done or failed approval, or a fired or cancelled reminder, it is purged |
| 6 | DW-437 never by age alone | Session created after the cut with no rows; and a session created 91 d ago that is current | Both kept |
| 7 | DW-437 cond. 2 | Approval and Action audit entries (via `Bridge.Audit.Record`) whose data names S1's Ref, written before the run | All still found in the IRIS audit log after the run, while S1's rows are gone |
| 8 | DW-437 bad args | `daysToKeep` 0, "x", "" or 1.5; a malformed `now` | Error status naming `OcuTalon.Data.Purge.Run`; nothing deleted |
| 9 | DW-437 task path | The Task Manager runs the OcuTalon purge task with DaysToKeep 60 (`Test.Install.Retention`) | The turn created 61 d ago is gone; the one created 59 d ago is kept |
| 10 | DW-386 shapes | Each of: a `dop_v1_`+hex token; a PEM block, both with an END line and header-only; `sk-ant-...`; a Telegram token with a 10-digit and a 13-digit id. Each inside text and inside a JSON string | Each is replaced by `[redacted]` (a PEM block from BEGIN through its END line, or to the end of the text). A second pass changes nothing |
| 11 | DW-444 dead replay | An executing `tool_call` row and no job holds its replay lock. Run the Reconcile step | Row: `failed`, Result `interrupted`, `FinishedAt` set. `approval.result` fires. Approval audit `finished`/`interrupted`, plus an Action entry `interrupted`. No `tool` request is sent |
| 12 | DW-444 live replay | Another job holds `^OcuTalon.Bridge.Replay(ref)`. Run Reconcile | Row stays executing; no event; no audit entry |
| 13 | DW-444 fix row | An executing `fix` row | Untouched by this pass (`Fix.Run` owns it) |
| 14 | DW-470 no key | Replay of an approved `tool_call` on a runner whose key is unset | Row `failed`. The kind-`tool` Decision row has FallbackReason `no_key` and Reasons = REPLAYNOKEY |
| 15 | DW-470 unreachable | Replay with the provider unreachable (Task 0 measures how this fails) | By the Task 0 rule: Reasons = REPLAYUNREACHABLE, or measured evidence that the tool ran or that the failure text cannot be told apart |
| 16 | DW-470 tool's own error | A tool that fails after it ran | Unchanged: FallbackReason `error`, no sentence |
| 17 | DW-448 `$List` | Key planted as an 8-bit `$List` element, as a 16-bit element (with `$Char(8364)`), and in a nested list | `GlobalHits` counts each |
| 18 | DW-462 | Row 13, with Workflow item re-enable taking any time | Deterministic: the poll completes a task that appears inside the window; a late real task is healed by Reconcile; exactly one approved outcome |
| 19 | DW-541 | `list_productions` with Orders running, then cleanly stopped | Each production carries `state` (`running`, `stopped`, …) from `GetProductionStatus`'s code |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `src/bridge/`, `docker/`, `ci/` or `_bmad-output/`. Lane A unless marked.

**DW-437, purge**
- `Install/Step/Retention.cls:66-69`: `Purge` calls `Bridge.Purge.Run(days)`. This is the hook for a shared `now`.
- `src/bridge/cls/OcuTalon/Bridge/Purge.cls:25-49`: `Run(days, now)` and `DeleteBefore`. It is the sibling model; the bridge must not delete host tables (AD-2).
- `Bridge/Time.cls:124-140`: `DaysCutoff(days, caller, .cutoff, now)`.
- `Install/Registry.cls:20-36,71-90`: areas run alphabetically (Core, Digest, Retention, Watch, Web), and every area runs whatever another returned.
- **Lane B tables:**
  - `Data/Turn.cls:12,24-30,75-79`: `CreatedAt`, the decision refs, `ShownDecisionRef`.
  - `Data/Delivery.cls`: `OwnerRef`, `RecordedAt`.
  - `Data/Session.cls`: `Ref`, `CreatedAt`, `CspSessionId`, `IrisUser`. Epic 31's file: read only.
- **Readers of a kept turn:**
  - `Data/Ownership.cls:68-88` (`TurnCost`; its SQL is at `:728-730`).
  - `Live/Payload/ChatMessage.cls:95` (`SetDecision`, `FromRow`).
- **Timing:** `Decide.cls:1292` stamps the Decision when it is recorded, so a Decision is never earlier than its Turn's `CreatedAt` (`Core/Conversation.cls:184`).
- **Current-session signals:**
  - Signed in: `Ownership.SESSIONKEY` ("OcuTalon.SessionRef") in CSP session data. The store-read precedent is `Web/Public/Status.cls:129-142` `Visitors(store)`: `$ListGet(@store@(id), $$$sesOldTimeout) > now`, then `@store@(id, 0, key)`.
  - Pairing: `Data/Pairing.cls` (`SessionRef`).
  - Approvals: `src/bridge/.../Data/ApprovalRequest.cls` (`OwnerRef`, `State`).
  - Watches: `Data/BackgroundCheck.cls` (`SessionRef`).
  - Reminders: `Data/Reminder.cls` (`SessionRef`, `State` pending).
  - Cross-owner SQL precedent: `Ownership.ActiveVisitors:453-459`.
- **Tests and fixtures:**
  - `Test/Data/Fixture.cls`: `Session :19`, `Turn :32`, `Reminder :50`, `Check :65`, `Approval :102`, `Decision :120`, `Usage :139`, `Delivery :200`, `Pairing :230`, `Clean :331`.
  - `Test/Bridge/AuditLog.cls`: `Now`, `Wait`, `Entries`.
- `Test/Install/Retention.cls`:
  - `Seed :293-354` and `TestOcuTalonPurge :247` (add the turns here).
  - `TestAuditUntouched :262`, the model for row 7.
  - `TestNoSettingRead :146-156`, whose class list gains `OcuTalon.Data.Purge`.
- Spine AD-27: `ARCHITECTURE-SPINE.md:906-915`. Lint baseline: `"ok": false`, 8 low `placeholder` findings (`{time}`, `{day}`, `{what happened}`, `{reason}`, `{entry}`, `{finding}`, `{time}`, `{n}`). The new text has no braces.

**DW-386, redaction**
- `src/bridge/cls/OcuTalon/Bridge/Redact.cls`:
  - `:12-16` the doc;
  - `:25` `REDACTED`;
  - `:90-110,136-175` the JSON passes;
  - `:184` `ReplaceAll`;
  - `:193-202` `PatternList`, which today misses `dop_v1_` and PEM. Its Telegram rule `(?<![0-9])[0-9]{6,12}:…` misses a run of 13 or more digits that `key_like` still flags.
- `docker/tests/lib-keys.sh:15-17` `KEY_LIKE_ERE` (seven alternatives). `ci/mock/mock.mjs:64-73` holds its copy.
- `Test/Bridge/Redact.cls`: the fragment idiom is at `:71-87`, `TestPatterns :58-91`, `TestIdempotent :134` and `Check :275`.

**DW-444 and DW-470, replay**
- `src/bridge/cls/OcuTalon/Bridge/Replay.cls`:
  - `:30-97` `Run`: `StartExecution :42`, then `BuildAgent`, then `ExecuteTool`;
  - `:148-162` `Record`, which writes the Action entry and calls `FinishExecution`;
  - `:174` `ActionEntry`.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`:
  - `:392-408` `StartExecution` and `FinishExecution` (`interrupted` leads to `failed`, the audit and `approval.result`);
  - `:769-840` `Reconcile`, passes 1-3; executing rows are untouched today.
- `Install/Step/Approvals.cls:8-11` calls `Reconcile`, run at start by `Install/Step/Reconcile.cls`.
- `Fix/Run.cls:96,278-299` closes interrupted fix runs at start (the sibling).
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` (Story 30.1's file: separate hunk):
  - `:1100-1125` `ConcludeTool`, which always records `error`;
  - `:141` `HELDBEFOREUPDATE` (the U-170 sentence-in-Reasons precedent);
  - `:148` `NOKEYTEXT`;
  - `:962-990` `Classify`.
- Catalog words reused: `fallbackReason.noKey` "no model key is set" and `conversation.turnFallback` "... Nothing was changed." (`Msg/Catalog/Core.cls:157,227`).
- Public texts on replay: `web/src/app/approvals/approval-view.ts:37,39` (the fix card, "without asking the model again"; fixes use no provider). `README.md:43` is about decisions.
- Tests: `Test/Bridge/Approval.cls` (Reconcile callers are listed in the row 11/12 task), `Test/Bridge/Runner.cls` (replay with `RunnerFixture.PointKeys`).

**DW-448, key proof:** `Test/Eval/KeyProof.cls:252-302` `Walk` (the match is at `:276,283`), `TestGlobalHits :39-66`. No `%Stream` property exists in `src/`. `irislib/%AI/Agent/Session.cls:63` `ContextData` is a compressed `%Stream.GlobalCharacter`, stored in `^AI.Agent.SessionS`.

**DW-462, flake:** `Test/Bridge/Approval.cls:1390-1425`. The race: `CompleteHoldTask` (`Approval.cls:551-573`) polls `TASKSECONDS` (5 s) from the save, while the test's `EnableConfigItem` (`UpdateProduction`, up to 10 s on x64) creates the task later. Nobody then completes it, and the hold waits on its 24 h timer. A test that saves a fake `EnsLib.Workflow.TaskResponse` already exists (`:2376`). Reconcile pass 1 cancels the open task of a non-pending row, which re-arms and delivers.

**DW-371:** `Watch/IncidentManager.cls:1274-1293` (`Purge`, with its hand-made day check and cutoff). The model to copy is `Digest/Data/Item.cls:64-75`. Tests: `Test/Watch/Lifecycle.cls:797-857,970-976`.

**DW-541:**
- `Watch/Reader.cls:68-90` `Productions`, which calls `Current(namespace, .description)`; `Current :255-276` already computes `state` from `GetProductionStatus`.
- `Tools/WatchAnswers.cls:273-289` `Listed` and `Names`. `Names` is shared with the `unknown_production` refusals.
- `Tools/WatchTools.cls:124-127` `ListProductions` (its doc is the tool description).
- Tests: `Test/Watch/Reader.cls` `TestOrdersIsListed` (pins the keys), `TestStoppedProduction :274`; `Test/Watch/Tools.cls:256-270`.

## Tasks & Acceptance

**Execution:**
- [ ] `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: in AD-27's Rule, add one bullet after the `Bridge.Purge` bullet. It reads: "With the same now, `OcuTalon.Data.Purge.Run(daysToKeep, now)` (called by the Retention area after the bridge's purge) deletes Turn rows created before the cutoff and Delivery rows recorded before it. It deletes a Session row created before it only when the session has no Turn, Delivery or Decision at or after the cutoff and is not current (signed in through a live CSP session, a live Telegram pairing, an open approval request, a watch or a pending reminder): never by age alone. It touches only OcuTalon's own tables and never an IRIS audit entry (AD-17). [AMENDED 2026-11-02, Story 30.7, orchestrator ruling U-210]". If the edit is made on a later UTC day, write that day's date in the marker. Write no braces. Set the frontmatter `updated:` to the same date. Then run the lint (Verification). No other AD changes.
- [ ] `Data/Purge.cls` (new; Lane B's Data area, a footprint extension) -- `Run(daysToKeep, now = "", store = "^%cspSession") As %Status` (rows 1-8):
  - Get the cutoff from `Bridge.Time.DaysCutoff` (naming `OcuTalon.Data.Purge.Run`). On an error or an empty cutoff, return.
  - Delete turns, then deliveries, then the qualifying sessions. Select the session IDs first, then check each one again and `%DeleteId` it. Append every error.
  - `store` is the CSP session store, a seam for the tests, as in `Status.Visitors`.
  - Rule 2: the ~10-line SQL delete is a copy of `Digest.Data.Item.Purge`'s form, because the bridge's `DeleteBefore` must not delete host tables (AD-2), and Turn uses `CreatedAt`.
- [ ] `Install/Step/Retention.cls` -- `Purge`:
  - Take `now = Bridge.Time.NowUtc()` once and call `Bridge.Purge.Run(days, now)`, then `Data.Purge.Run(days, now)`.
  - Append the two statuses, so each part runs whatever the other returned.
  - Update the doc. This is the same cut for decisions and turns (row 3).
- [ ] `Test/Data/Purge.cls` (new, lane-b `Data`):
  - `TestTurnsReadNoPurgedDecision` (rows 1-3; the U-210 test): call `Retention.Purge(90)` and `Data.Purge.Run` with an explicit `now`, then assert through `TurnCost`, `ShownDecisionRef` and `ChatMessage.FromRow` for every kept test turn.
  - `TestSessionKeptWhileActiveOrCurrent` (rows 4-6; condition 1): one session per signal, with a private store global for the signed-in case.
  - `TestOnlyOwnTablesAndAuditKept` (row 7; condition 2): the audit entries survive. A static check (`Test.Bridge.Source` `Text`) also shows that `OcuTalon.Data.Purge` names no `%SYS`, no `Audit` and no table outside `OcuTalon_Data`/`OcuTalon_Bridge_Data`, and deletes only from `OcuTalon_Data.Turn`, `Delivery` and `Session`.
  - `TestBadArguments` (row 8).
  - Each test creates and removes its own rows (`Fixture.Clean`), also after a failure.
- [ ] `Test/Install/Retention.cls` -- `Seed`: add turns 61 and 59 days old on the fixture owner. `TestOcuTalonPurge` asserts row 9. Add `OcuTalon.Data.Purge` to `TestNoSettingRead`'s list.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Redact.cls` -- `PatternList` and the doc:
  - add `dop_v1_[A-Fa-f0-9]{20,}`;
  - add a PEM rule from `-----BEGIN [A-Z ]*PRIVATE KEY` through the first `-----END [A-Z ]*PRIVATE KEY-----`, else to the end of the text; it matches across real and `\n` line breaks;
  - widen Telegram to `(?<![0-9])[0-9]{6,}:[A-Za-z0-9_-]{30,}`.
  - The regex source must not itself match `key_like`. -- DW-386.
- [ ] `Test/Bridge/Redact.cls` -- add `TestDigitalOceanToken`, `TestPrivateKey`, `TestAnthropicKey` and `TestTelegramToken`, one per shape (row 10). Each uses fragment-built values, in text and in JSON, through `Check` (idempotent). Extend the header list. -- DW-386.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Replay.cls` -- DW-444:
  - `Run` takes `LOCK +^OcuTalon.Bridge.Replay(ref)` before `StartExecution` and releases it after `Record`/`FinishExecution`, and on every error and exception path.
  - New `CloseInterrupted() As %Status`: for each `Kind='tool_call' AND State='executing'` row, take the lock with timeout 0. If it is taken, open the row, write `ActionEntry(row, "interrupted")` through `Audit.Record("Action", …)`, call `FinishExecution(ref, "interrupted")`, and release the lock. If it is not taken, skip the row.
  - Rule 2: this extends `Record`'s write-then-finish. A lock replaces `Fix.Run`'s production-start comparison, because the row has no start time (that would be a new column) and a test's Reconcile must never close a live replay.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Approval.cls` -- `Reconcile`: add pass 4, `Replay.CloseInterrupted()`, after pass 3, appending its status. Update the class and Reconcile docs. -- DW-444.
- [ ] `Test/Bridge/Approval.cls` -- rows 11-13: the dead and live cases. The live replay is a `StartJob` that holds the replay lock until signalled. Assert no `tool` request header after Reconcile. Before the change, search every test that leaves an executing `tool_call` row and then runs Reconcile (step or method), and fix any that relied on rows staying executing. -- DW-444.
- [ ] Task 0 (DW-470, fresh throwaway, mock only; record the result in `## Design Notes` "Measured at implementation"):
  - Replay a `tool_call` (a) with the runner's key variable unset and (b) with the provider unreachable (the mock stopped, or the runner pointed at a closed port).
  - For each, record the failure text, where it was raised (BuildAgent or ExecuteTool), `ToolsRun`, and whether the tool's code ran.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- `ConcludeTool` only (a separate hunk that uses no 30.1 code; Story 30.1's file). Apply this only when the failure text is a provider failure (`NOKEYTEXT`, or the measured `UNREACHABLETEXT` with its source note, like `TIMEOUTTEXT`) and Task 0 showed that the tool did not run:
  - a. Record the fallback with FallbackReason `no_key` for no key (AD-8's own mapping), else the reason AD-8 gives.
  - b. Set Reasons to the new parameter `REPLAYNOKEY` = "No model key is set, so the approved call did not run. Nothing was changed." or `REPLAYUNREACHABLE` = "The model provider could not be reached, so the approved call did not run. Nothing was changed.", as `HELDBEFOREUPDATE` does.
  - Every other failure is unchanged (row 16).
  - Rule for (b) unreachable: if Task 0 shows that the tool ran, or that the text cannot be told from a tool's own error, write no unreachable sentence. Record the evidence instead, and report it under Auto Run Result.
- [ ] `Test/Bridge/Runner.cls` -- rows 14-16: a no-key replay (`PointKeys` to an unset variable), the unreachable case (per Task 0), and a tool's own error. Assert on the row and on the kind-`tool` Decision row. -- DW-470.
- [ ] `Test/Eval/KeyProof.cls` -- `Walk`: when a node's data or subscript does not hold the value, decode a `$ListValid` non-empty value with `$ListNext`, recursing into nested lists (bound 10), and count a hit. Extend `TestGlobalHits` with row 17. -- DW-448.
- [ ] Measurement (DW-448, fresh throwaway, `e30s7i`):
  - List the compiled message-body classes OCUTALON uses (the distinct `Ens.MessageHeader.MessageBodyClassName` after the class runs, plus every compiled subclass of `Ens.Request`, `Ens.Response` and `Ens.MessageBody` under `OcuTalon`) and their `%Stream` properties (`%Dictionary.CompiledProperty`).
  - **If one can hold a stream:** save one with a fake key past 1,024 characters, show that `Walk` misses it, then decode compressed and split chunks in `Walk` (`$System.Util.Decompress` per chunk when the root header's third piece is greater than 0, joining chunk boundaries) and show that it now finds the key.
  - **If none can:** record the build, the classes and what was stored in Design Notes, for the lead's wontfix-accepted close.
- [ ] `Test/Bridge/Approval.cls` -- `TestAnswerBeforeTheTaskExists` (DW-462, row 18): keep OcuTalonApprovals disabled through the answer job's wait.
  - (a) When the row is approved, save a fake open `TaskResponse` with the hold's subject (`TASKSUBJECT`+ref), as at `:2376`. Assert that the job completes it with `Approve|OcuTalonWorkflow|1|` and returns `done`.
  - (b) Re-enable the item without a time limit and wait up to 60 s for the real task. Assert it is open (Answer has returned). Run `Bridge.Approval.Reconcile()`. Assert the hold ends and exactly one approved outcome is sent.
  - (c) Clean up the fake task.
  - Update the method doc.
  - Two points rest on inference, so check them first:
    - that completing the fake task errors nowhere (the `:2376` precedent);
    - that Reconcile pass 1's cancel ends the hold with the row's outcome (`HoldResponse` re-arm at `Approval.cls:691,715-716`).
  - If (b)'s heal does not happen, change no product code. Report it under Auto Run Result as a product residual, and keep (a) plus a (b) that asserts only the documented 5 s contract (the late task stays open).
- [ ] `Watch/IncidentManager.cls` -- `Purge`: take its cutoff from `Bridge.Time.DaysCutoff(daysToKeep, "OcuTalon.Watch.IncidentManager.Purge", .cutoff)`. On an error or an empty cutoff, return. The rest is unchanged, and so are the error texts. -- DW-371.
- [ ] LAST, separable -- DW-541:
  - `Watch/Reader.cls` `Productions`: pass `.state` to `Current` and add `"state"` to each entry. Update the class doc.
  - `Tools/WatchAnswers.cls` `Listed`: add each entry's `state` to `productions` (`Names` is unchanged).
  - `Tools/WatchTools.cls` `ListProductions`: its doc says each production has its running state.
  - Tests: `Test/Watch/Reader.cls` (`TestOrdersIsListed` expects the keys `displayName,namespace,production,state`; `TestStoppedProduction` asserts `state` is `stopped` while stopped and `running` after the restart) and `Test/Watch/Tools.cls:263` (the expected object gains `"state": "running"`).

**Acceptance Criteria:**
- Given any run of the purge task, when it ends, then no kept Turn row names a Decision that is gone, and no kept Turn reads a TurnCost of 0 because its Usage was purged (DW-437, U-210).
- Given a session that is current or has activity at or after the cutoff, when the purge runs, then its Session row is kept; and given only the age of a session, it is never purged (DW-437, condition 1).
- Given the purge runs, when it ends, then the only rows it deleted are `OcuTalon_Data` Turn, Delivery and Session rows, and every IRIS audit entry for approvals and actions is still present (DW-437, condition 2).
- Given the amended spine, when `lint_spine.py` runs, then the output is the 8 baseline low findings and nothing new (DW-437).
- Given an instance start after a crash in mid-replay, when the Reconcile step runs, then the row ends `failed`/`interrupted` with `approval.result` and the audit entries, and the call never runs again (DW-444).
- Given a replay that fails because no key is set, when the person's views read its failed Decision row, then FallbackReason is `no_key` and the Reasons sentence says that the call did not run and nothing was changed. The unreachable case follows the Task 0 rule (DW-470).
- Given the repository, when `test-boundaries.sh` runs, then `key_like` finds nothing, and no public text claims that a replay works without a provider connection (DW-386, DW-470).
- Given `IncidentManager.Purge(n)`, when it runs, then its cutoff is `Bridge.Time.DaysCutoff`'s, and `Test.Watch.Lifecycle`'s purge tests pass unchanged (DW-371).
- Given the Chat agent calls `list_productions`, when Orders is stopped, then its entry's state is `stopped`, built from IRIS's status code and no other field (DW-541).

## Spec Change Log

- 2026-11-02 (lead, set-aside): DEFERRED by the Contest Planner (reserve lever d1) to after the v1.0.0 tag, first daily release. The implemented and self-reviewed work (finalize commit 0fae3b72) was taken out of the tree by a forward set-aside commit and saved as `_bmad-output/implementation-artifacts/set-aside/30-7-epic-30-burn-down-1.patch` (the source diff from story_base 58dbdd26 plus the AD-27 U-210 spine bullet). Pick-up (doctrine U4): apply the patch with `git apply --3way`, commit, set this spec `in-review` with `baseline_revision` = the commit before the pick-up, then QA and code review. The frontmatter `deferred:` items are harvested to the ledger (owner 30.7). Not yet code-reviewed or QA'd.

## Review Triage Log

### 2026-11-02 — Review pass
- verdicts: 44 findings — high 0, medium 7, low 26, false 8, maybe-false 3
- findings:
  - Blind Hunter
    - `[medium]` `[defer]` TestAnswerBeforeTheTaskExists no longer tests the success path — the spec's two inferences failed on measurement and the spec names this fallback ("keep (a) plus a (b) that asserts only the 5 s contract"); the product residual goes to `deferred:`
    - `[medium]` `[defer]` the 24-hour-hold residual is recorded but not filed — same root cause as above; filed in `deferred:` for the lead's harvest
    - `[low]` `[patch]` Data.Purge.Signed rescans the whole CSP store for every candidate — patched: the SQL checks run first and the store scan last in `Keeps`
    - `[maybe-false]` `[defer]` KeyProof.Walk costs more per node — unmeasured; `deferred:` says what settles it
    - `[low]` `[reject]` Redact misses doo_v1_ and dor_v1_ — the ledger entry and `key_like` name dop_v1_ only; unlikely in this product and the pattern is spec-bound (reopen_if a doo_ or dor_ token is seen)
    - `[low]` `[reject]` session delete not atomic with its checks — the window is a few milliseconds for a session idle 90 days; closing it needs a lock or transaction
    - `[low]` `[reject]` unbatched DELETE statements — the same form as Digest.Data.Item.Purge, which the spec names as the model
    - `[maybe-false]` `[defer]` Retention first-run failure called a flake without evidence — the failing assertions concern the stock tasks, which this diff does not touch; recorded in `deferred:`
    - `[low]` `[reject]` TestOnlyOwnTablesAndAuditKept compares an ordered list — a deliberate strict pin of the three deletes, and its failure message names the list
    - `[low]` `[reject]` CloseInterrupted skips a row on a failed %Reload silently — the row only changed state between the select and the lock; unlikely, and the fix adds a branch
    - `[low]` `[patch]` spec Auto Run Result stale — rewritten at finalize
  - Edge Case Hunter
    - `[low]` `[reject]` $ListGet on a store node that is not a list — Status.Visitors reads the store the same way; unlikely, and the fix adds a guard
    - `[low]` `[patch]` Signed runs first for every candidate — the same root cause as the third Blind row; patched
    - `[low]` `[reject]` activity between the check and the delete — same as the Blind row on atomicity
    - `[low]` `[reject]` Pairing check ignores CodeSessionRef — a pending code is minutes old, so an idle session of 90 days has none; the fix adds a branch and a fixture
    - `[low]` `[reject]` all old sessions collected into an array first — ids and refs only; a first-run backlog is bounded by the table
    - `[low]` `[reject]` single set-based DELETEs — same as the Blind row
    - `[low]` `[reject]` Record then FinishExecution failing repeats the Action entry — Record is the existing write-then-finish; a failed finish is already a logged warning
    - `[false]` `[reject]` re-entrant lock in one process — Reconcile and a replay never run in one process at once: Replay.Run is synchronous and calls neither Reconcile nor CloseInterrupted
    - `[false]` `[reject]` lock release inside a transaction — Replay.Run is entered from a business host's OnMessage, never inside a transaction
    - `[false]` `[reject]` ConcludeTool and a Reply that is not an object — the condition is guarded by $IsObject, and a non-Reply is an error with no sentence by design
    - `[maybe-false]` `[defer]` KeyProof per-node cost — the same root cause as the Blind row; one entry in `deferred:`
    - `[false]` `[reject]` PEM header-only goes to the end of the text — the spec says so (redacts through the first END line, else to the end of the text)
    - `[false]` `[reject]` unreachable provider has no sentence — the Task 0 rule: the replay makes no provider request, so there is nothing to explain
    - `[medium]` `[defer]` (b) never runs Reconcile or asserts the hold ended — the heal does not happen (measured); the residual is in `deferred:`
    - `[medium]` `[defer]` the fake task is never completed — Completing a task nobody requested errors on this build (measured); (a) pins the poll by assignment
    - `[false]` `[reject]` AI sessions of a purged Session remain — the spec forbids touching them (U-210 names three tables) and lists the residual
  - Verification Gap
    - `[medium]` `[patch]` the never-runs-again assertions of TestInterruptedReplayIsClosed could not fail — patched: the row now names the replay tool and the runner, the counters are the tool's own, and a mutation (the row approved) turns the assertions red
    - `[medium]` `[defer]` (b) pins the defect as green — spec-sanctioned fallback; the same deferred entry
    - `[low]` `[reject]` the exception path of Replay.Run's lock release is unpinned — Execute catches its body's exceptions, so the Catch is a safety net no fixture can reach
    - `[low]` `[reject]` condition 2's runtime check cannot fail — IRIS audit entries are written now and cannot be back-dated; the spec names the static scan as the pin
    - `[low]` `[reject]` a leftover executing tool_call row would break the event counts — the spec's search found none; each test removes its rows
    - `[low]` `[reject]` the purge deletes rows the tests did not make — throwaway-only by the class doc and the spec
    - `[low]` `[reject]` the private CSP store has the reader's layout — the precedent is Status.Visitors; the layout is a documented store format
    - `[false]` `[reject]` lint and boundary gates have no pinning test — they are scripts in the spec's Verification, not ACs of code
    - `[low]` `[patch]` stale header line for TestAnswerBeforeTheTaskExists — replaced
    - `[low]` `[patch]` TestExecutingFixIsLeftAlone has no mutation line — mutation run (Kind filter dropped) and the line written
    - `[low]` `[reject]` Retention.Purge's run-whatever-the-other-returned contract is untested — a two-line append of statuses
    - `[low]` `[reject]` Replay.Run's lock-held branch is not asserted — an addition of the implementation beyond the spec's rows; the live-replay row pins Reconcile's side
  - Intent Alignment
    - `[low]` `[reject]` row 14 is tested in two pieces (Decide with a hand-built text, Runner for the real text) — the Runner test pins that the real text holds both NOKEYTEXT pieces and ToolsRun 0, so the pieces compose
    - `[medium]` `[defer]` row 18's heal and single outcome are not delivered — the fallback the spec names; the residual is in `deferred:`
    - `[false]` `[reject]` row 15 resolves to the evidence branch — the spec allows exactly this
    - `[low]` `[reject]` row 11 calls Approval.Reconcile rather than the install step — the step is a one-line call of it
    - `[low]` `[reject]` the default CSP store read is untested — the store is a seam as in Status.Visitors

## Design Notes

**Architecture decisions (Rule 6).**
- AD-27: amended by U-210, the one approved amendment (first task).
- AD-17: the purge touches no audit entry, and the replay closes are audited.
- AD-2: the bridge purges only its own tables; the host purge is the host's.
- AD-11: the reconciler moves a row only through `FinishExecution`.
- AD-16: the `interrupted` result, as for `FixRun`.
- AD-8: the FallbackReason mapping. `no_key` for a missing key is its own rule; the unreachable sentence lives in Reasons, never as a new reason.
- AD-31: `Redact` is the one redactor.
- AD-15: list_productions reads through `Watch.Reader` only.
- AD-4: the Session row and its owned records.
- AD-22: destructive runs happen on throwaways.
- AD-33: see Footprint below. No AD's Rule is contradicted.

**Decided in-stage.**
- **Same `now`.** The host purge is called from `Retention.Purge` with the bridge's `now`, not from the Core area. The registry runs Core before Retention, so separate clocks could keep a turn whose Decision was cut a second later. `Decision.RecordedAt` is never before `Turn.CreatedAt`, so `CreatedAt < cutoff` covers every purged decision.
- **Session age.** A Session also needs `CreatedAt < cutoff`; otherwise a new session with no rows would be "idle".
- **"Signed in"** is a live CSP session whose data holds the row's Ref. This holds for both local and demo rows (`Ownership.SESSIONKEY`).
- **Pairing.** A live Telegram pairing also counts as current, because it keeps a channel open to the session. This keeps more than the ruling requires, never less.
- **Approvals.** Pending, approved and executing count as open.
- **Watches.** Any BackgroundCheck row counts as a watch.
- **DW-444 lock.** Reconcile may close a dead replay on any call, because the replay lock makes a live one untouchable. This meets the candidate fix's reason ("never on a test's call") without a stored start time.
- **DW-470 surface.** The "failed row" is the replay's kind-`tool` fallback Decision row, as U-178 settled for U-170. Story 31.2 (Lane B) shows its Reasons sentence. "Catalog words" means the words of `fallbackReason.noKey` and `conversation.turnFallback`, held as a bridge sentence because the bridge names no host catalog (AD-2).
- **DW-462.** The test fix: the product's 5 s contract is documented, and a task that appears late is healed by Reconcile pass 1.
- **DW-541.** The preferred tool change is small (the state is already read in the same switch), so the chip text stays.

- **Decided at implementation (small ambiguities).**
  - **Purge, pairing.** Any Pairing row whose SessionRef is the session's keeps it. The checks use one SQL read each and a failed read keeps the session and returns its error.
  - **Purge, deletes.** Turn and Delivery go by SQL; a Session goes through `%DeleteId`, so the static check reads both forms (`delete from` and `##class(...).%DeleteId`).
  - **Replay lock.** `Replay.Run` takes the lock with a timeout of 0 and answers a failure Reply (ToolsRun 0) when it is held; the old refusal of a second replay by `StartExecution` is unchanged. `Run` keeps its contract and holds the lock around the new private `Execute` (the old body from `StartExecution` on). `Record` now returns its combined status, which `Run` ignores and `CloseInterrupted` appends.
  - **DW-470 tests.** The Decision row is made by Decide, not by the shadow runner. Rows 14 and 16 are therefore pinned in `Test.Bridge.Decide.TestToolFailureReasons` (a separate method, so `TestToolRequest` is untouched), and the measured runner facts (no-key text, ToolsRun 0, the tool did not run; unreachable provider, tool ran) in `Test.Bridge.Runner.TestReplayWithoutAKey`. No test points the live runners' keys at an unset variable: a live replay would only repeat what these two show.
  - **DW-470 reason rule.** `no_key` and REPLAYNOKEY need both pieces of NOKEYTEXT in the failure text and a Reply with ToolsRun 0; a failure with no Reply, or from a tool that ran, stays `error` with no sentence.
  - **DW-448.** `Walk` also decodes a `$List` subscript (the whole subscript text is decoded, to a depth of 10), because a node's subscript is a string like its data.
  - **DW-541.** The `state` of an entry is the string `Current` already computes (running, stopped, suspended, troubled, network_stopped, timeout or unknown); `Listed` copies it by position from the entries.
  - **DW-462.** See "Measured at implementation": the spec's two inferences did not hold, so the test proves the poll by the task's assignment and (b) asserts only the 5 s contract.

**Measured at implementation.**
- **Task 0 (DW-470), build 154U, mock only, shadow runner ZzRunner with agent ZzReplayAgent:**
  - **(a) key unset** (the placeholder names a variable that is not set): the runner fails in `BuildAgent`, before `ExecuteTool`. FailureText is `ERROR <%AICore>ProviderConfigError: PROVIDERCONFIG is invalid    > ERROR <%AICore>InternalError: Internal AI-Core error: @{env:<NAME>} has no value and no :-fallback was given` (it holds both pieces of NOKEYTEXT), ToolsRun 0, 0 steps, the tool ran 0 times, the row `failed`/`failed`, in 0.1 s.
  - **(b) provider unreachable** (base URL a closed port, key set): the replay does not fail. It makes no provider request, so the tool ran once, ToolsRun 1, FailureText empty, the row `done`/`done`. The same as the control against the mock.
  - **Consequence (the Task 0 rule):** no `REPLAYUNREACHABLE` sentence and no `UNREACHABLETEXT` were written; an unreachable provider fails no replay, so there is nothing to explain. `REPLAYNOKEY` only. For the lead's veto window: no new public text beyond the catalog words of `REPLAYNOKEY`.
- **DW-448, build 154U (IRIS 2026.3.0AI, ARM64 container), warm throwaway after the Approval, Decide, Runner and other classes had run:** the distinct `Ens.MessageHeader.MessageBodyClassName` over 540 headers were 17 classes (Ens.AlarmRequest, Ens.AlarmResponse, Ens.Response, Ens.StringResponse, EnsLib.Workflow.TaskRequest, EnsLib.Workflow.TaskResponse, OcuTalon.Bridge.Msg.AgentStep, ApprovalOutcome, ApprovalStart, Reply, Request, ToolInventory, OcuTalon.Checks.Msg.CheckChanged, OcuTalon.Core.Msg.RunTurns, OcuTalon.Msg.Command.StopWatch, OcuTalon.Msg.CommandResult, OcuTalon.Msg.Tick). Together with every compiled OcuTalon subclass of Ens.Request, Ens.Response and Ens.MessageBody, that is 63 classes with 499 compiled properties (inherited included): none has a `%Stream` property (the control, `%AI.Agent.Session.ContextData`, a `%Stream.GlobalCharacter`, is found by the same scan). **None can hold a stream**, so the compressed and split chunk decoding is not written. For the lead's wontfix-accepted close of the stream half of DW-448; the `$List` half is fixed.
- **DW-462, the two inferences:**
  - Completing a fake task errors: `CompleteTask` returns `ErrProductionMismatchInDeferredResponse` because a task that no request sent has no deferred response token, and the task is not saved as complete (`CompleteHoldTask` logs a warning). Test (a) therefore proves the poll by the task's assignment to OcuTalonWorkflow, which `AssignTask` saves, and by the job returning `done`.
  - Reconcile pass 1 does not end the hold: `EnsLib.Workflow.Engine.%CancelRequest` discards the task and sends no deferred response, so the hold never learns of it (the existing `TestReconcileCancelsOnlyOrphans` deletes the hold by hand for the same reason). No product code was changed, as the spec says; test (b) asserts only the 5 s contract (the late real task stays open, the row stays approved), and cleanup completes the task.
  - **Product residual (for the lead):** an answer that outlives TASKSECONDS before its task exists leaves the hold waiting on the 24 hour timer; Reconcile discards the late task and does not end the hold. At the timer the hold delivers the row's outcome. File it if you see a need.
- **Reconcile callers with an executing tool_call row (the search the DW-444 task asks for):** `Test.Bridge.Approval` (TestHeldRowIsReadUnderTheLock, TestStartExecutionAtOnce: no Reconcile follows), `Test.Bridge.Runner` (the duplicate replay) and `Test.Bridge.Decide` (an executing row that Decide must not close) leave such a row and run no Reconcile; none relied on a row staying executing. The only executing tool_call rows that Reconcile now closes are the new tests' own.
- **Back-dated fixtures and the purge task (shared surface):** only `Test.Install.Retention` runs the task; no other test back-dates a Turn, Delivery or Session by more than 60 days through it.
- **First fresh run of `Test.Install.Retention`:** the two stock `Ens.Util.Tasks.Purge` tasks did not start within the wait (Task Manager history empty, 6 failed methods); the same class passed on the next fresh run (109 s) and on the mutation run. A start-up flake of the stock tasks on a busy machine, not of this change; the OcuTalon purge task test passed in both.

**For the lead (spec gate).**
- **Veto window, public text.** `REPLAYNOKEY` reuses catalog words. `REPLAYUNREACHABLE`'s "could not be reached" is new text that Story 31.2 will show. Recommended wording is above; classify it.
- **Residual (inference).** A purged session's GuideState, SimMessage, fired or cancelled Reminders, BreakFeedRun rows and ConversationLink stay. The links keep their AI sessions. This story deletes none of them (U-210 names three tables); file them if you see a need.
- **Residual (inference).** A hold that sent a replay lost to a crash may stay waiting on key `replay`; Reconcile does not reap it.
- **Public-text check (DW-470).** The lead's 2026-10-31 check found no claim; the implement stage re-runs it (Verification).

**Footprint (AD-33, Rule 11).**
- **Lane B, by the dispatch's allowance:** the new `Data/Purge.cls` and `Test/Data/Purge.cls` (new files), and reads of Turn, Delivery, Session, Pairing and Reminder.
- **Story 30.1 files** (separate hunks; a revert of either story leaves the other compiling): `Bridge/Process/Decide.cls` (`ConcludeTool` and two parameters). If row 14 changes an assertion in `Test/Bridge/Decide.cls` `TestToolRequest`, that hunk stays separate too.
- **Contended edits:** none.

**Integration ACs (Rule 1).**
- The Task Manager's OcuTalon purge task reads the new `Data.Purge` and deletes the 61-day turn (row 9, `Test.Install.Retention`).
- `ChatMessage.FromRow` reads a kept turn's decision and cost (row 2).
- The Reconcile step reads `Replay.CloseInterrupted` (row 11).

**Consumed-by:**
- `Install.Task.Purge` through `Retention`.
- Story 31.2 (the Reasons sentence on the card and notice).
- The Chat agent (`list_productions`'s state).

**Consumes:**
- `Bridge.Time.DaysCutoff`/`NowUtc` (30.2).
- `Bridge.Approval.FinishExecution`/`Reconcile` (30.3).
- `Bridge.Audit.Record`.
- `Watch.Reader.Current`.

**Extend, don't copy (Rule 2).**
- `Data.Purge`'s delete mirrors `Digest.Data.Item.Purge` (reason above).
- Its store read mirrors `Status.Visitors` (6 lines). Status is Lane B's public-status class, and its count is not the per-Ref test that is needed.
- `CloseInterrupted` extends `Replay.Record`/`ActionEntry`.
- `IncidentManager` adopts `DaysCutoff` (DW-371).
- `Listed` extends `Names`' output.
- The Redact tests extend `Check`.

**Ledger inbox (Rule 17).**
- DW-437: addressed (rows 1-9; spine, Purge, Retention and test tasks).
- DW-386: addressed (row 10).
- DW-444: addressed (rows 11-13).
- DW-470: addressed (rows 14-16, Task 0, public-text check).
- DW-448: addressed (row 17 and the measurement).
- DW-462: addressed (row 18).
- DW-371: addressed (the `IncidentManager` task). Its `Data.Pairing.Purge` half is Lane B's and declined here: Declined DW-371 (Pairing half): Lane B's file; the lead re-owns it.
- DW-541: addressed (row 19, last task).

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=30 stage=implement'`, run from the worktree root. The fresh tag is `e30s7i` and the warm tag `e30s7iw`.

How to run:
- One command per tool call, in the foreground, with `timeout: 600000`. Never two IRIS test runs in one message.
- Use throwaways only. Slot B (`ocutalon-slot-b`, `OCUTALON`) is for load and compile only; run no purge there.
- Use warm for in-process classes. Use fresh for production-bound classes (`Test.Bridge.Approval` and `Test.Bridge.Runner`, because Replay and the hold run in production jobs) and for `Test.Install.Retention`, which runs the real tasks.
- Tear down only your own tags, also after a failure.

**Commands:**
- (loop) `bash docker/tests/test-boundaries.sh` and `bash docker/tests/test-class-rules.sh`. Expected: all pass, and `key_like` finds nothing.
- (loop) `<lane> OCUTALON_RUN_TAG=e30s7iw ci/warm.sh up`, once. Then `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e30s7iw ci/iris.sh class <Class>`, one call per class. Expected: `CLASS … passed`. The classes:
  - `OcuTalon.Test.Data.Purge`
  - `OcuTalon.Test.Bridge.Redact`
  - `OcuTalon.Test.Bridge.Purge`
  - `OcuTalon.Test.Eval.KeyProof`
  - `OcuTalon.Test.Watch.Lifecycle`
  - `OcuTalon.Test.Watch.Reader`
  - `OcuTalon.Test.Watch.Tools`
  - `OcuTalon.Test.Data.Ownership`
  - `OcuTalon.Test.Data.PairingRows`
  - `OcuTalon.Test.Install.Registry`
- (loop) `<lane> OCUTALON_RUN_TAG=e30s7i ci/iris.sh class <Class>`, fresh, one call each: `OcuTalon.Test.Bridge.Approval`, `OcuTalon.Test.Bridge.Runner`, `OcuTalon.Test.Install.Retention`, and `OcuTalon.Test.Bridge.Decide` (if `ConcludeTool` changed).
- (once) The Task 0 and DW-448 measurements on `e30s7i` (described in the tasks), with the results recorded in Design Notes.
- (once) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16`. Expected: `"ok": false` with exactly the 8 baseline low `placeholder` findings (by token; the line numbers may shift).
- (once) `git grep -n -i -E "without (asking )?the model|no model|replay|offline" -- README.md web/src src/ocutalon/cls/OcuTalon/Msg/Catalog`. Expected: no text claims a replay works without a provider connection. Record the hits.
- (once) `bash ci/checks.sh`. Expected: every script passes.
- (once) `<lane> OCUTALON_RUN_TAG=e30s7i ci/iris.sh shard lane-a --part k/6` for k = 1 to 6, then `shard lane-b --part k/3` for k = 1 to 3, fresh, one call each. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e30s7iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e30s7i ci/iris.sh teardown`, also after a failure.

**Shared surfaces:**
- The OcuTalon purge task now deletes old Turn, Delivery and Session rows: `Test.Install.Retention` (re-pinned), and any test whose fixtures are back-dated more than 60 days (search for `Utc(6`/`Utc(9` and back-dated `CreatedAt`).
- `Reconcile` gains pass 4: every test that runs Reconcile with an executing `tool_call` row (search `Test/` for `Reconcile` and `executing`).
- `Watch.Reader.Productions` entries (+`state`): `TestOrdersIsListed`. The `list_productions` answer: `Test.Watch.Tools.TestListProductions`.
- `Redact` patterns: callers' tests that pin redacted text (none plant these shapes, per search).
- `TestNoSettingRead`'s class list.
- CI time: no new unit. `Test.Data.Purge` joins lane-b `Data` (+10 s or less, inference).
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations (Rule 19).** Apply each mutation, observe red, revert byte for byte, and record it as `mutation: … → …`.

| AC or row | Mutation | Expected red |
|---|---|---|
| U-210, rows 1-3 | `Retention.Purge` does not call `Data.Purge` | `TestTurnsReadNoPurgedDecision`; `Retention.TestOcuTalonPurge` |
| Row 3 | `Data.Purge` takes its own `now` (+5 s) | the boundary assertion |
| Cond. 1, rows 4-5 | Drop one signal at a time (signed in, pairing, approval, watch, reminder, newer turn, delivery, decision) | `TestSessionKeptWhileActiveOrCurrent` for that signal |
| Cond. 1, row 6 | Drop the `CreatedAt < cutoff` check | the new-session case |
| Cond. 2, row 7 | Add a delete of a table outside `OcuTalon_Data` | `TestOnlyOwnTablesAndAuditKept` (static) |
| Row 10 | Remove each new pattern | that shape's test |
| Rows 11-12 | Pass 4 removed; or the lock check skipped | the dead case; the live case |
| Row 14 | `ConcludeTool` keeps `error` and no sentence | the no-key Runner test |
| Row 17 | The list decode removed | `TestGlobalHits` |
| Row 18 | `CompleteHoldTask` does not poll | `TestAnswerBeforeTheTaskExists` (a) |
| DW-371 | `DaysCutoff` called with `daysToKeep + 1` | `Lifecycle.TestPurge` |
| Row 19 | `state` dropped from `Listed` | `Tools.TestListProductions`; `Reader.TestStoppedProduction` |

**Pinning mutations run (Rule 19)**, each applied, observed red and reverted byte for byte:
- mutation: `Retention.Purge` does not call `Data.Purge` -> `Test.Data.Purge.TestTurnsReadNoPurgedDecision` red (the 91-day turn, its delivery and its session stay) and `Test.Install.Retention.TestOcuTalonPurge` red (the turn created 61 days ago is not gone)
- mutation: the turn delete of `Data.Purge` moved 5 s later (the host cut differing from the bridge's) -> `TestTurnsReadNoPurgedDecision` red (the turn created at the cutoff does not stay) and `TestSessionKeptWhileActiveOrCurrent` red (a Turn at the cutoff)
- mutation: the signed-in check dropped -> `TestSessionKeptWhileActiveOrCurrent` red (a live CSP session); likewise one at a time for the newer Turn, Delivery, Decision, pairing, approval (all three open states), watch and pending reminder, each red for its own case only
- mutation: the `CreatedAt < cutoff` condition of the session select dropped -> `TestSessionKeptWhileActiveOrCurrent` red (the young session with no rows)
- mutation: the Delivery delete aimed at `OcuTalon_Bridge_Data.Usage` -> `TestOnlyOwnTablesAndAuditKept` red (the deletes list) and `TestTurnsReadNoPurgedDecision` red (the delivery stays)
- mutation: the `dop_v1_` pattern removed -> `Test.Bridge.Redact.TestDigitalOceanToken` red; the PEM pattern removed -> `TestPrivateKey` red; the PEM header-only branch removed -> `TestPrivateKey` red (the header-only cases); the Telegram pattern back to 6 to 12 digits -> `TestTelegramToken` red (the 13-digit id); the `sk-ant-` pattern removed -> `TestAnthropicKey` red (upper case)
- mutation: `Reconcile` pass 4 removed -> `Test.Bridge.Approval.TestInterruptedReplayIsClosed` red and `TestLiveReplayIsLeftAlone` red (the closing after release)
- mutation: the lock check of `CloseInterrupted` removed -> `TestLiveReplayIsLeftAlone` red (the live row is closed)
- mutation: the replay lock not released on the normal path of `Replay.Run` -> `Test.Bridge.Runner.TestReplayThroughTheRunner` red (the lock is free after each replay) and `TestReplayWithoutAKey` red
- mutation: `ConcludeTool` keeps `error` and no sentence -> `Test.Bridge.Decide.TestToolFailureReasons` red (the no-key case); `ConcludeTool` ignoring ToolsRun -> `TestToolFailureReasons` red (the tool that ran)
- mutation: the `$List` decoding of `KeyProof.Holds` removed -> `Test.Eval.KeyProof.TestGlobalHits` red
- mutation: `CompleteHoldTask` polls no more -> `Test.Bridge.Approval.TestAnswerBeforeTheTaskExists` red ((a): the job has returned at once and the fake task is not assigned)
- mutation: `DaysCutoff` called with `daysToKeep + 1` in `IncidentManager.Purge` -> `Test.Watch.Lifecycle.TestPurge` red
- mutation: `state` dropped from `Listed` -> `Test.Watch.Tools.TestListProductions` red; `state` dropped from `Reader.Productions` -> `Test.Watch.Reader.TestOrdersIsListed` and `TestStoppedProduction` red

- mutation (review pass): the delivery hold of Reconcile pass 3 also takes executing tool_call rows -> `Test.Bridge.Approval.TestInterruptedReplayIsClosed` red and `TestLiveReplayIsLeftAlone` red (Reconcile returns the hold's refusal)
- mutation (review pass): the fixture of `TestInterruptedReplayIsClosed` made `approved` instead of `executing`, so that the call is replayed -> the same test red on the Result, the Action entry, "no tool request was sent" and "the tool ran 0 times" (the replay-tool row moves the runner's request count and the tool's counter)
- mutation (review pass): the `Kind = 'tool_call'` filter dropped from `Replay.CloseInterrupted` (query and guard) -> `Test.Bridge.Approval.TestExecutingFixIsLeftAlone` red (the fix row is touched and an event fires)

**Runs (build 154U):** fresh `Test.Data.Purge` 0.60 s (new class, lane-b Data); the rest of the loop classes passed, fresh: `Test.Install.Retention` 109 s, `Test.Bridge.Approval` 132 s, `Test.Bridge.Runner` 16 s, `Test.Bridge.Decide` 9 s; warm: `Test.Bridge.Redact`, `Test.Bridge.Purge`, `Test.Eval.KeyProof`, `Test.Watch.Lifecycle`, `Test.Watch.Reader`, `Test.Watch.Tools`, `Test.Data.Ownership`, `Test.Data.PairingRows`, `Test.Install.Registry`. `test-boundaries.sh`, `test-class-rules.sh`, `ci/checks.sh` and the spine lint (the 8 baseline findings) pass. Review pass, same tree after the patches (fresh throwaways, `e30s7i`): `Test.Bridge.Approval` 139.7 s, `Test.Bridge.Runner` 16.0 s, `Test.Bridge.Decide` 9.7 s, `Test.Install.Retention` 112.8 s; warm (`e30s7iw`): `Test.Data.Purge` 0.64 s and the nine other loop classes; `bash ci/checks.sh`, `test-boundaries.sh`, `test-class-rules.sh` and the spine lint (the 8 baseline findings) pass; shards, fresh: `lane-a` parts 1 to 6 of 6 passed (20, 19, 19, 19, 19, 19 classes; 475, 185, 187, 525, 440, 432 s) and `lane-b` parts 1 to 3 of 3 passed (29, 29, 28 classes; 257, 221, 473 s). `Test.Install.Retention` failed twice for one reason, the two stock Ens purge tasks not starting inside the test's wait (once in the implement pass, once in a run with a warm stack beside it), and passed on four other fresh runs, all with the OcuTalon purge task's own assertions green; it is the stock tasks' start under load, not a result of this change `(inference)`.

**Public-text hits** of the grep (README.md lines 43, 104, 177; the catalog's `fallbackReason.noKey` and the no-key banner; `approval-view.ts` lines 37 and 39 for fixes; `catalog.ts`; `guide-view.ts`): none claims that a replay works without a provider connection.

## Auto Run Result

Status: done
Blocking condition: none

- **Summary.** All eight ledger entries of Epic 30 are implemented, each with its own tests:
  - DW-437: `Data.Purge` and the same-`now` call from `Retention.Purge`, with the AD-27 amendment (U-210); the spine lint still shows the 8 baseline findings.
  - DW-386: `Redact` gains `dop_v1_`, PEM private key blocks and Telegram ids of 6 or more digits.
  - DW-444: the replay lock, `Replay.CloseInterrupted` and Reconcile pass 4.
  - DW-470: `ConcludeTool` records `no_key` with `REPLAYNOKEY` when the call did not run.
  - DW-448: `KeyProof.Walk` decodes `$List` values (data and subscripts, nested).
  - DW-462: the test is deterministic; no product code changed.
  - DW-371: `IncidentManager.Purge` takes its cutoff from `DaysCutoff`.
  - DW-541: `state` on `list_productions` entries.
- **Files changed.**
  - Product: `Data/Purge.cls` (new), `Install/Step/Retention.cls`, `Bridge/Replay.cls`, `Bridge/Approval.cls` (Reconcile pass 4), `Bridge/Redact.cls`, `Bridge/Process/Decide.cls` (`ConcludeTool` and `REPLAYNOKEY`, a separate hunk that uses no Story 30.1 code), `Watch/IncidentManager.cls`, `Watch/Reader.cls`, `Tools/WatchAnswers.cls`, `Tools/WatchTools.cls`, and the AD-27 bullet in `ARCHITECTURE-SPINE.md`.
  - Tests: `Test/Data/Purge.cls` (new), `Test/Install/Retention.cls`, `Test/Bridge/{Approval,Decide,Redact,Runner}.cls`, `Test/Eval/KeyProof.cls`, `Test/Watch/{Reader,Tools}.cls`.
- **New test class and its fresh run time:** `OcuTalon.Test.Data.Purge` (lane-b `Data`), 0.60 s on a fresh throwaway, 0.64 s warm. No new shard group is needed.
- **Review.** Four layers ran. Patches applied: 4 (session checks reordered so the store scan runs last; `TestInterruptedReplayIsClosed` moved to a replay-tool row so its "never runs again" assertions can fail; the `TestAnswerBeforeTheTaskExists` header line corrected; mutation lines written for the new pinning tests). Deferred: 3 (see `deferred:`). The rest are logged under Review Triage Log with their reasons.
- **Task 0 and the measurements** are in Design Notes, "Measured at implementation":
  - an unset key fails the replay in `BuildAgent` before the call (the tool did not run), so `REPLAYNOKEY` is written;
  - an unreachable provider fails no replay (a replay makes no provider request, so the tool ran), so `REPLAYUNREACHABLE` is not written and the only new public text is `REPLAYNOKEY`, which reuses the catalog words;
  - no message-body class can hold a `%Stream`, so the stream half of DW-448 (compressed and split chunks) is not written: for the lead's `wontfix-accepted` close, `reopen_if` a message body class gains a stream property;
  - DW-462: both of the spec's inferences failed, so no product code changed; the product residual is in `deferred:`.
- **Follow-up review recommended:** false (no high patched; two medium patched or fewer).
- **Verification.** Every `(loop)` command, and the `(once)` lines (spine lint, public-text grep, `bash ci/checks.sh`, all nine shard parts), passed on the final tree; the run figures are under "Runs". The pinning mutations are listed above, each applied, observed red and reverted byte for byte.
- **Residual risks.**
  - A live purge needs the real CSP session store and run only on throwaways; the signed-in check is pinned against a private store with the layout of `Status.Visitors`.
  - `Test.Install.Retention` can fail when the stock purge tasks do not start in time (see "Runs").
  - A purged session leaves GuideState, SimMessage, fired or cancelled Reminders, BreakFeedRun rows and ConversationLink (declared in the spec; none deleted by design).
  - A replay hold lost to a crash can still wait on key `replay` (declared in the spec).
