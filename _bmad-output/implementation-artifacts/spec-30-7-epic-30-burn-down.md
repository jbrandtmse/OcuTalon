---
title: 'Epic 30 burn-down'
type: 'bugfix'
created: '2026-11-02'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/set-aside/30-7-epic-30-burn-down-1.patch'
warnings: ['oversized']
deferred: []
---

<intent-contract>
## Intent

**Problem:** Epic 30 still owns thirteen ledger entries (re-opened 2026-11-08, SC-5, built now and merged after the 1.0.4 cut):
- The 90-day purge leaves Turn, Delivery and Session rows behind, so a kept turn can read a purged decision (DW-437, owner decision U-210), and a purged session's other rows stay (DW-581).
- A replay interrupted by a crash stays `executing` forever (DW-444), and the approval hold waiting on it is never ended (DW-582); an answer that outlives `TASKSECONDS` before its task exists leaves the hold on its 24-hour timer (DW-588).
- A replay that fails because the provider or the tool's server cannot be reached, or because no key is set, does not say why (DW-470, owner decision U-214).
- No test pins that a several-ref `cancel_reminder`'s IdempotencyKeys are each accepted once and refused on a repeat (DW-584, owner decision U-215).
- Approval row 13 flakes on slow runners (DW-462); `Test.Install.Retention` failed twice when the stock purge tasks did not start inside its wait (DW-590, unverified).
- `IncidentManager.Purge` keeps its own copy of the day rule (DW-371, Lane A half).
- `list_productions` cannot say whether a production is running (DW-541).
- `Test.Bridge.Gate`'s untrusted-turn row can no longer fail for `cancel_reminder` (DW-495).
- The key proof's `$List` decode (Story 30.8) may slow the global scan on large databases (DW-589, unmeasured).

**Approach:** One small, separable task per entry, each with its own tests, in this priority order: DW-437 (with DW-581), DW-444 with DW-582 and DW-588, DW-470, DW-584, DW-462, DW-590, DW-371, DW-541, DW-495, DW-589.
- **Reuse the set-aside work.** `_bmad-output/implementation-artifacts/set-aside/30-7-epic-30-burn-down-1.patch` (story_base 58dbdd26, build 0fae3b72, implemented and self-reviewed on 2026-11-02) is reference material: its hunks for Data/Purge, Test/Data/Purge, Install/Step/Retention, Replay, Decide (ConcludeTool), Test/Bridge/Runner and Decide, Test/Bridge/Approval, Watch/Reader, Watch/IncidentManager, Tools/WatchAnswers, Tools/WatchTools, Test/Watch/Reader and Test/Watch/Tools applied cleanly on 2e78a4f7; its Bridge/Approval and Test/Install/Retention hunks conflict with later changes and are merged by hand; its Redact, Test/Bridge/Redact and Test/Eval/KeyProof hunks are void (Story 30.8 delivered DW-386 and DW-448). Its AD-27 spine bullet is written again by this story.
- **Owner decisions (apply exactly):**
  - **U-210** (at=2026-11-02T09:22:13Z#641, kept): keep the 90-day retention purge with two conditions. (1) A Session row is purged only when the session has no Turn, Delivery or Decision newer than the 90-day cut AND it is not a current session (signed in, or with an open approval request, watch or reminder); never by age alone. (2) The purge touches only OcuTalon's own tables: the IRIS audit log entries for approvals and actions are never purged by this story. One test for each condition, next to the TurnCost/ShownDecisionRef test. The AD-27 retention extension marker is fine.
  - **U-214** (at=2026-11-02T13:19:05Z#650, kept with one condition): the failed row's sentence names what actually failed. If the replay path really needs the model provider (for example the AI Hub provider object or its key) and cannot reach it: "The model provider could not be reached, so the approved call did not run. Nothing was changed." If what is unreachable is the tool's own server (an MCP server or tool set): "The tool's server could not be reached, so the approved call did not run. Nothing was changed." The story's test names which endpoint it checks, and the wording follows it. The no-key case reuses U-170's no_key wording plus "Nothing was changed.".
  - **U-215** (at=2026-11-02T13:19:05Z#651, kept): AD-1's wording is the as-built rule (the command's position in the turn), marked and linted by the lead on 2026-11-08, with no code change; the approved-call replay uses the stored commands, so positions are stable and exactly-once holds. One test that the several-ref `cancel_reminder`'s keys `:2`, `:3` and `:4` are each accepted once and refused on a repeat.
- **Independent and separable.** The story lands in commits of its own; nothing here uses Epic 19's unmerged work.

## Boundaries & Constraints

**Always:**
- **Purge.** The host purge (`OcuTalon.Data.Purge`) uses the same `now`, and so the same cutoff (`Bridge.Time.DaysCutoff`), as `Bridge.Purge.Run` in one `Retention.Purge` call.
  - Turns go by `CreatedAt < cutoff`, deliveries by `RecordedAt < cutoff`.
  - A Session row goes only when all of these hold: its `CreatedAt` is before the cutoff; no Turn, Delivery or Decision of it is at or after the cutoff; it is not current. Current means any one of: a live CSP session holding its Ref (signed in); a live Telegram pairing; a pending, approved or executing approval request; a BackgroundCheck row (watch); a pending reminder. The checks run again right before each delete.
  - DW-581: when a session row goes, the rows keyed only by that session go in the same pass (its GuideState, SimMessage, finished Reminder and BreakFeedRun rows, and its ConversationLink, so the bridge's own purge then frees the AI sessions); Memory rows are not touched (Epic 19's `Memory.DropSession`). This is a retention change ruled by the runner as a veto item.
- **What the purge may touch.** Every delete names an `OcuTalon_Data` table, or the bridge's ConversationLink through the bridge's own API. Nothing touches `%SYS`, an IRIS audit entry, a message or an AI session directly.
- **Replay lock.** A replay holds `LOCK ^OcuTalon.Bridge.Replay(ref)` from before `StartExecution` until after `FinishExecution`, and releases it on every path. Reconcile closes an executing `tool_call` row only when it can take that lock at once (no live replay), through `FinishExecution(ref, "interrupted")`, never re-runs the call (NFR-13), and ends the hold that waits on it with that result (DW-582).
- **Failure sentences.** Exactly the owner's U-214 strings and the no_key sentence; which one applies is decided from what the code observed (the step that failed), never from a guess; Task 0 measures on the slot or a throwaway which step needs which endpoint (bridge `BuildAgent`/`NewSession`: the provider; `ExecuteTool` of an MCP tool: the tool's server). A tool's own error after it ran is unchanged.
- **Test data.** Fake secrets are built from fragments at runtime, so no committed file matches `key_like`.
- **SQL.** Every new SQL checks `%SQLCODE`, so `docker/tests/test-class-rules.sh` stays green.
- **Comments.** Comments state the contract only (Rule 14).
- **Stored data.** No stored property is added, renamed or retyped, and no `Storage` block changes.
- **Contended paths.** `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`, `Test/Bridge/Decide.cls` and `Test/Bridge/Gate.cls` are also changed by Epic 19 (unmerged): this story's hunks there are separate, self-contained hunks (new parameters, `ConcludeTool`, new test methods or one row) that the lead clears with the orchestrator before the implement stage.

**Never:**
- No edit to `Data/Session.cls`, `Test/Data/Session.cls`, `Bridge/Msg/Enum.cls`, `Test/Msg/Catalog.cls`, `Agent/Chat.cls`, Memory or Docs code, Settings (`Data/Setting`, `Core/SettingsOps`), `release/**`, `eval/run.sh`, or any other contended path.
- No new catalog key, FallbackReason value or stored column.
- No AD other than AD-27 (and the lead's AD-1 marker) is amended.
- No change to Lane B's `Test.Web.SessionEvents`, `Data.Pairing.Purge`, the web chip text, or `ci/mock/scenarios/B/`.
- No new or changed user-facing string beyond the owner's U-214 strings without the lead's PUBLIC TEXT gate.
- No real model key or bot, and no destructive or purge run on slot B (throwaways only).

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
| 10 | (void) | DW-386 was delivered by Story 30.8 | No row of this story |
| 11 | DW-444 dead replay | An executing `tool_call` row and no job holds its replay lock. Run the Reconcile step | Row: `failed`, Result `interrupted`, `FinishedAt` set. `approval.result` fires. Approval audit `finished`/`interrupted`, plus an Action entry `interrupted`. No `tool` request is sent |
| 12 | DW-444 live replay | Another job holds `^OcuTalon.Bridge.Replay(ref)`. Run Reconcile | Row stays executing; no event; no audit entry |
| 13 | DW-444 fix row | An executing `fix` row | Untouched by this pass (`Fix.Run` owns it) |
| 14 | DW-470 no key | Replay of an approved `tool_call` on a runner whose key is unset | Row `failed`. The kind-`tool` Decision row has FallbackReason `no_key` and Reasons = REPLAYNOKEY ("No model key is set, so the approved call did not run. Nothing was changed.") |
| 15 | DW-470 provider unreachable (U-214) | Replay whose provider object cannot be built or reached (the step Task 0 measured as needing the model provider; the test names that endpoint) | Row `failed`; FallbackReason an existing value (the plan picks it from `Bridge.Msg.Enum`; no new value); Reasons = "The model provider could not be reached, so the approved call did not run. Nothing was changed." |
| 15b | DW-470 tool server unreachable (U-214) | Replay of an approved MCP tool call whose server cannot be reached (the test names that server) | Row `failed`; Reasons = "The tool's server could not be reached, so the approved call did not run. Nothing was changed." |
| 16 | DW-470 tool's own error | A tool that fails after it ran | Unchanged: FallbackReason `error`, no sentence |
| 17 | (void) | DW-448 was delivered by Story 30.8 | No row of this story |
| 18 | DW-462 | Row 13, with Workflow item re-enable taking any time | Deterministic: the poll completes a task that appears inside the window; a late real task is healed by Reconcile; exactly one approved outcome |
| 19 | DW-541 | `list_productions` with Orders running, then cleanly stopped | Each production carries `state` (`running`, `stopped`, …) from `GetProductionStatus`'s code |
| 20 | DW-582 hold of an interrupted replay | An executing `tool_call` row whose hold waits on the replay result; Reconcile closes it interrupted | The hold ends with the interrupted result once; no second outcome |
| 21 | DW-588 late task | An answer that outlives `TASKSECONDS` before its task exists | The hold is answered (not left on its 24-hour timer); exactly one outcome |
| 22 | DW-584 (U-215) | A several-ref `cancel_reminder` from one tool call submits keys `<ItemId>:2`, `:3`, `:4`; each is re-submitted | Each key accepted once; each repeat refused (no second effect) |
| 23 | DW-581 | A purged session with GuideState, SimMessage, a finished Reminder, a BreakFeedRun and a ConversationLink | All go with the session; a kept session's rows stay; Memory rows untouched |
| 24 | DW-495 | `Test.Bridge.Gate` untrusted-turn row for `cancel_reminder` | Sends a valid `reminderRefs` shape so the "its method did not run" check can fail |
| 25 | DW-590 / DW-589 | Retention test wait; key-proof scan time | Deterministic wait on the stock tasks (or measured evidence); scan timed before/after on a throwaway and closed with the numbers |

</intent-contract>

## Code Map

Re-derived on 2026-11-08 against `76c31e50` (OCT-epic30). Paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `src/bridge/`, `ci/`, `docker/` or `_bmad-output/`. "Patch" is `_bmad-output/implementation-artifacts/set-aside/30-7-epic-30-burn-down-1.patch`; its line numbers are given as `patch:N`.

**The set-aside patch on the current head** (checked with `git apply --check --include=<path>`, no tree change):
- Applies cleanly: `Data/Purge.cls` (new, patch:231-376), `Test/Data/Purge.cls` (new, patch:962-1297), `Install/Step/Retention.cls` (patch:377-410), `src/bridge/cls/OcuTalon/Bridge/Replay.cls` (patch:120-230), `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` (patch:46-85), `Test/Bridge/Runner.cls` (patch:819-961), `Test/Bridge/Decide.cls` (patch:669-735), `Test/Bridge/Approval.cls` (patch:411-668), `Watch/Reader.cls`, `Watch/IncidentManager.cls`, `Tools/WatchAnswers.cls`, `Tools/WatchTools.cls`, `Test/Watch/Reader.cls`, `Test/Watch/Tools.cls` (patch:1434-1589).
- Conflicts: `src/bridge/cls/OcuTalon/Bridge/Approval.cls` (patch:1-45; the file gained the `setting` kind in Story 40.5) and `Test/Install/Retention.cls` (patch:1392-1433; Story 17.5 added the Digest CheckRun and Sent rows).
- Void: `Bridge/Redact.cls`, `Test/Bridge/Redact.cls`, `Test/Eval/KeyProof.cls` (Story 30.8). The spine hunk (patch:1590-1610) is rewritten by this story.

**DW-437 / DW-581, the purge**
- `Install/Step/Retention.cls:64-69` `Purge` is `Quit ##class(OcuTalon.Bridge.Purge).Run(daysToKeep)` today.
- `src/bridge/cls/OcuTalon/Bridge/Purge.cls`: `Run(daysToKeep, now)` `:27`; `Sessions` `:54-104` reads every `ConversationLink.SessionId`, marks an AI session that no link names in `^OcuTalonBP.Unlinked` and deletes it on a later run once the mark is a day old. It is the only bridge class besides Decide that names `ConversationLink`.
- `src/bridge/cls/OcuTalon/Bridge/Data/ConversationLink.cls`: keyed `(OwnerRef, Agent)`, holds `SessionId`; its one writer is `Point` (`:54`). No API drops a session's links.
- `src/bridge/cls/OcuTalon/Bridge/Time.cls:203` `DaysCutoff(daysToKeep, caller, Output cutoff, now = "")`; `:164` `PlusSeconds`.
- Tables (SQL names) and columns the purge reads or deletes: `OcuTalon_Data.Turn` (`SessionRef`, `CreatedAt`; `Data/Turn.cls:12,30`), `OcuTalon_Data.Delivery` (`OwnerRef`, `RecordedAt`; `Data/Delivery.cls:12,24`; Telegram rows keep redacted `Text`, `Channel/Telegram/Out.cls:294,303`), `OcuTalon_Data.Session` (`Ref`, `CreatedAt`; `Data/Session.cls:26,35`; Epic 31's file, read only), `OcuTalon_Data.GuideState` (`SessionRef`, unique), `OcuTalon_Data.SimMessage` (`SessionRef`), `OcuTalon_Data.Reminder` (`SessionRef`, `State` pending, fired or cancelled; `Data/Reminder.cls:20-21`), `OcuTalon_Data.BreakFeedRun` (`SessionRef`), `OcuTalon_Data.Pairing` (`SessionRef`, `:27`), `OcuTalon_Data.BackgroundCheck` (`SessionRef`, `:14`), `OcuTalon_Data.Memory` (`SessionRef`; Lane A, Epic 19; never written here), `OcuTalon_Data.Document` (`OwnerRef`: the session on the online demo, `instance` on a local install), `OcuTalon_Bridge_Data.Decision` (`OwnerRef`, `RecordedAt`; `:18,69`), `OcuTalon_Bridge_Data.ApprovalRequest` (`OwnerRef`, `State`; states in `Msg/Enum.cls:24`).
- Signed in: `Data/Ownership.cls:51` `SESSIONKEY` "OcuTalon.SessionRef"; the store read precedent `Web/Public/Status.cls:129-142` (`$ListGet(@store@(id), $$$sesOldTimeout) > now`, `$$$sesOldTimeout` = 3, `irislib/%cspBuild.inc:156`).
- The sibling list of a session's rows: `Core/SessionOps.cls:283-301` `End` (an online-demo sign-out).
- Readers of a kept turn: `Data/Ownership.cls` `TurnCost`; `Data/Turn.cls:75` `ShownDecisionRef`; `Live/Payload/ChatMessage.cls:66` `FromRow`.
- The daily digest (Epic 17) records a `digest` Delivery for every session that has not ended each day (`Digest/Process.cls:205-210`, `Channel/WebChat/Out.cls:61-62`), so such a session always has a Delivery newer than the cut.
- Fixtures: `Test/Data/Fixture.cls:22-251` (Session, Turn, Reminder, Check, Approval, Decision, Usage, Delivery, Pairing) and `Clean :369`; `Test/Bridge/AuditLog.cls` `Now`, `Entries`, `Wait`; `Test/Bridge/Source.cls` `Text`, `CodeLines`, `Matches`; `Test/Bridge/Purge.cls:331` `UsageExists`.
- `Test/Install/Retention.cls` (831 lines): header doc `:19`; `TestNoSettingRead` list `:152`; `TestOcuTalonPurge :247-262` (`inc59` at `:254`, `item61` at `:255`, CheckRun/Sent asserts `:257-260`); `TestAuditUntouched :266`; `Seed :297` (owner fixtures end at `:331`, `// 9:` at `:332`); `RunTasks :367`, `RunAndWait :388` (`%SYS.Task.RunNow`), `WaitRun :405-419` (polls `%SYS_Task.History` up to `RUNSECONDS` 180, re-calls RunNow every `RETRYSECONDS` 60 while `RunningJobNumber` is empty), `Runs :791`. Story 30.2's AC 2 requires that the Task Manager runs all three tasks.
- `Data/Delivery.cls:29` the `Text` doc: "The rendered text of a web notice card, exactly as it was sent; empty for any other row." (Lane B's class; see Declined DW-437 doc line.)

**DW-444 / DW-582 / DW-588 / DW-462, replay and holds**
- `src/bridge/cls/OcuTalon/Bridge/Replay.cls` (unchanged since Story 30.3): `Run :30-97`; `StartExecution` at `:42` (a refusal calls `CloseUnstarted` and answers `Failure`, ToolsRun 0); `BuildAgent` `:56`, `NewSession` `:57`, `Context.Begin`/`Grant` `:58-59` (a failure here leaves `executed` 0, so ToolsRun 0); `ExecuteTool` `:65`; `Record :148-169`; `ActionEntry`.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`: class doc Reconcile bullet `:28-31`; `TASKSECONDS` `:62`; `AnswerLocked` calls `CompleteHoldTask` under the row lock `:385`; `StartExecution :436-439`; `FinishExecution :446-452` (`interrupted` leaves `failed`, audits, fires `approval.result`); `HoldTask :597-602`; `CompleteHoldTask :607-629` (polls TASKSECONDS, then only warns); `Arm` (sends the `TaskRequest` with key `task`); `HoldResponse :716` (key `replay` does nothing but warn on a still-approved row; key `task` reads `%Action` of an `EnsLib.Workflow.TaskResponse`); `Replay :788-804` (`SendRequestAsync(DECIDEITEM, request, 1, "replay")`); `LiveHold :808`; `IsLive :818`; Reconcile doc `:825-834`; `Reconcile :835` (pass 1 `:838-853`, pass 2 `:854-868`, `Quit ..ReconcileDeliveries(sc)` `:869`; `:855-857` returns early when the pending rows cannot be read); `ReconcileDeliveries :873-896`; `OwnedByLiveHold :906-915`.
- Setting rows go `executing` too (`Core/SettingsOps.cls:568-590`), so a closer must filter `Kind = 'tool_call'`.
- Ens behaviour (code read, inference until Task 0b): a business process keeps each awaited response as an `Ens.BP.MasterPendingResponse` (`RequestHeaderId`, `CompletionKey`, `IsTimer`; `irislib/Ens/BP/MasterPendingResponse.cls:17-23`); `Ens.Host.SendDeferredResponse(headerId_"|"_productionName, response)` (`irislib/Ens/Host.cls:679-709`) enqueues a response for any request header that has a return queue; a response that is not in the pending list, or reaches a completed process, is discarded (`irislib/Ens/BusinessProcess.cls:294,322`). `EnsLib.Workflow.Engine.%CancelRequest` discards a task with no deferred response; `CompleteTask` of a real task sends its response (`irislib/EnsLib/Workflow/Engine.cls:201-245,564`).
- After a restart Ens restores Decide's timer and re-queues a runner's in-flight request (`irislib/Ens/Alarm.cls:181-227`, `Director.cls:1993-1995`, `Job.cls:416-419,741-779`; inference), so a re-delivered replay can find its row `executing`.
- Reconcile runs at every production start: `Install/ReconcileIn.cls:2-10,94`, `Install/Step/Reconcile.cls:5-7` -> `Install/Step/Approvals.cls:8-11`. No existing test leaves an executing `tool_call` row and then runs Reconcile (`Test/Bridge/Approval.cls:1353,1378`, `Runner.cls:1071`, `Decide.cls:421`, `Gate.cls:1830`, `Test/Data/Ownership.cls:1138` leave such rows; none reconciles).
- `Test/Bridge/Approval.cls` (3339 lines; about 140 s of its own run time): `TestAnswerBeforeTheTaskExists :1410-1451`; ClassMethod helpers callable from another class: `HoldLockInJob :1507`, `TaskIds :2388`, `TaskCount :2406`, `WaitTask :2412`, `WaitHoldGone :2460`, `WaitNode :2470`, `Prop :3030`, `TaskFacts :3063`, `StartJob :3243`, `Clean :2684`; instance helpers: `Ready :2207`, `Answerer :2991`, `UseReplayAgent :2837`, `RunnerRequests :2940`, `AssertOneOutcome :3114`. `Test/Bridge/ApprovalRows.cls` is the shared fixture of approval rows (`NewRow`, `Save`).
- `Test/Bridge/Runner.cls`: `UNSETVARIABLE :112`; `TestReplayThroughTheRunner :998`; `ApprovedRow :1199`; `NewRunner :1261`; `ProviderConfig :1275`; `Guard :1301`.

**DW-470, the failure sentence (U-214)**
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: `HELDBEFOREUPDATE :178` (the sentence-in-Reasons precedent); `NOKEYTEXT :186` ("@{env:|has no value", unchanged); `Retryable :529-531` (kind tool is never retried); `Classify :1245` (no_key `:1256`); `Conclude :1329-1412` (Epic 19's turn-filter call at `:1355`); `ConcludeTool` doc `:1435-1441`, body `:1442-1467`; `StillApproved :1470`; `RecordFallback :1581` (`..., broken, reasons`).
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`: `BuildAgent :197-219` (cached after the first build, `:199`; AI Hub `OnInit` -> `%CreateProvider` builds the provider object from the settings, no request: `irislib/EnsLib/AI/Agent/OutboundAdapter.cls:129-152,243-261`, `irislib/%AI/Agent.cls:197-231,264-284`); `NewSession :308-319` (in memory).
- No MCP path exists in the product: no `call_mcp_tool` or MCP client in `src/`; the gate only recognises `mcp:` toolrefs (`Policy/Gate.cls:91-92,412-414`); Epic 22 is backlog; `ci/mock` is the model mock only. Held `tool_call`s today come from developer or extension tools (fixture `Test/Bridge/ZzReplayTool.cls`).
- Who reads a Decision's Reasons: `Live/Payload/Decision.cls:88` (verbatim, to the web's decision strip and rail); `Core/BridgeSink.cls:313-330` shows a reason in the result notice only when it is a `HeldReasons` line (`HELDBEFOREUPDATE`; Lane B's file, unchanged).

**DW-584 (U-215)**
- Keys: `Tools/CommandCall.cls:41-44` (`ItemId_":"_(CommandCount+1)`); a `list_reminders` in the same turn takes `:1`.
- The owner's repeat check: `Schedule/ReminderOps.cls:176-182` (`Cancel` -> `KeyedRow("CancelKey", ...)` `:225-237`): the same key and Ref answers the first result with no second effect; the same key for another Ref is refused `reused_key`.
- Tests: `Test/Schedule/Reminders.cls:664` `TestSeveralCancelsFromOneToolCall` (the model; helpers `Guard`, `Session`, `SetReminder`, `EventStates`, `RequestsBetween`, `WaitEnded`; `Test/Schedule/ReminderFixture.cls` `Begin`); `Test/Schedule/ReminderChat.cls:380` `TestCancelAllThroughChat` (keys `:2`-`:4`, no repeat).

**DW-495:** `Test/Bridge/Gate.cls:2014` (the row `{"reminderRef":"x"}` in `AssertSafeReadOnlyOnly :1957`; loop `:2025-2029`); `RunDenied :2465`; `Tools/ReminderTools.cls:82,87` (`reminderRefs`; BADREFS before `Run`); `READONLYCANCELREMINDER :51`. Epic 19's regions: `TestTaintFollowsTrustedOutput :1299` and `FreeIncident :2182`.

**DW-371:** `Watch/IncidentManager.cls:1290-1319` `Purge` (own day check and cutoff); model `Digest/Data/Item.cls:64-75`; tests `Test/Watch/Lifecycle.cls:797` `TestPurge`, `:970` `TestPurgeFarCutoff`.

**DW-541:** `Watch/Reader.cls:96` `Productions` (the `Current` call `:113`; `Current :511`, `state` its 12th parameter, set at `:530` from the `$$$eProductionState*` codes only); `Tools/WatchAnswers.cls:263` `Listed` (`Names` stays `{name, namespace}` for `unknown_production` and `ambiguous`); `Tools/WatchTools.cls:121-122` `ListProductions` doc (the tool description the model reads; `TRUSTEDOUTPUT`/`READONLY` `:68-70`); `Test/Watch/Reader.cls:60-70`, `Test/Watch/Tools.cls:263`.

**DW-589:** `Test/Eval/KeyProof.cls:348-427` (`Walk`, `Holds`, `HoldsSubscript`, `LISTDEPTH` `:39`); the scan runs from the frozen `eval/run.sh:503-510`.

**Spine:** `ARCHITECTURE-SPINE.md` AD-27 `:950-959` (the `Bridge.Purge` bullet `:956`); frontmatter `updated: '2026-11-07'`. Lint baseline: `"ok": false`, 10 low `placeholder` findings (`{time}`, `{old}`, `{new}`, `{day}`, `{what happened}`, `{reason}`, `{entry}`, `{finding}`, `{time}`, `{n}`).

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (measure first, on the warm throwaway `e30s7iw`, mock only, no real key; record each result under Design Notes "Measured at implementation"):
  - 0a (U-214). With the shadow runner of `Test.Bridge.Runner` (`ZzRunner`, agent `ZzReplayAgent`), replay an approved `tool_call` (i) with the key placeholder naming an unset variable, (ii) with a `ProviderConfig` whose provider object cannot be built for another reason (an unknown provider name, then a missing Config Store entry), and (iii) with the key set and the base URL a closed port. For each record the step that failed (`BuildAgent`, `NewSession`, `Context`, `ExecuteTool` or none), FailureText, ToolsRun, whether the tool's code ran, and the row's end state. Expected from the 2026-11-02 run and the code read: (i) fails in `BuildAgent`, both `NOKEYTEXT` pieces, ToolsRun 0; (iii) does not fail.
  - 0b (Ens). (1) A request sent to a disabled production item waits on that item's queue (the hold's replay is not answered while the runner it names is disabled). (2) `Ens.Host.SendDeferredResponse` on the `RequestHeaderId` of a live hold's pending response with key `task` (body `Ens.StringResponse`, value `Approve`) and with key `replay` (body a failure `OcuTalon.Bridge.Msg.Reply`) reaches `HoldResponse` with that key once, and a later answer to the same request is discarded. (3) Whether the Workflow operation, once enabled again, still creates the task of a `TaskRequest` whose header was answered that way (the late task), and that Reconcile pass 1 then cancels it with no response to anyone.
  - If 0b (1) or (2) does not hold, change no product code for DW-582 or DW-588, keep the patch's DW-462 test and Task 1's tests, and end the implement stage `blocked` with the measured facts (an intent gap: rows 20 and 21 need another mechanism).
- [ ] Task 1 -- apply the reusable hunks: `git apply --3way --include=<path> ... _bmad-output/implementation-artifacts/set-aside/30-7-epic-30-burn-down-1.patch` for exactly the 14 clean files of the Code Map (excluding the void files, the two conflicting files and the spine). Then merge by hand:
  - `src/bridge/cls/OcuTalon/Bridge/Approval.cls` (patch:1-45): keep "or setting" in the class doc `:28-31` and append the patch's sentence about closing an executing tool_call; Reconcile doc `:825-834` says four passes and that pass 4 fires `approval.result`; replace `:869` with `Set sc = ..ReconcileDeliveries(sc)` then `Quit $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Bridge.Replay).CloseInterrupted())`. The early return at `:855-857` stays (it already skips pass 3).
  - `Test/Install/Retention.cls` (patch:1392-1433): the header doc line `:19` as the patch; `"OcuTalon.Data.Purge", ` after `"OcuTalon.Bridge.Purge", ` in the `:152` list, keeping the Digest CheckRun and Sent entries; the patch's `turn61`/`turn59` assertions after `:254`, keeping `:257-260`; the patch's four turn lines in `Seed` after `:331`.
  - Then compile, and run the loop classes of Verification once before any new change (green on the merged patch is the base the next tasks extend).
- [ ] `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- AD-27: add this one bullet after the `Bridge.Purge` bullet (`:956`), verbatim: "With the same now, `OcuTalon.Data.Purge.Run(daysToKeep, now)`, which the Retention area calls just before the bridge's purge, deletes Turn rows created before the cutoff and Delivery rows recorded before it, Telegram rows with their kept text included. It deletes a Session row created before the cutoff only when the session has no Turn, Delivery or Decision at or after the cutoff, holds no memory or document, and is not current (signed in through a live CSP session, a live Telegram pairing, a pending, approved or executing approval request, a watch, or a pending reminder): never by age alone. With the session go its GuideState, SimMessage, BreakFeedRun and finished Reminder rows, and its conversation links through `OcuTalon.Bridge.Purge.DropLinks`, so that the bridge's purge frees their AI sessions; memories and documents are never deleted by it. It touches only OcuTalon's own tables and never an IRIS audit entry (AD-17). [AMENDED 2026-11-08, Story 30.7, owner decision U-210 (kept)]". Set the frontmatter `updated:` to `2026-11-08`. No other AD changes. Then the memlog append and the lint (Verification). -- DW-437, DW-581.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Purge.cls` -- new `ClassMethod DropLinks(ownerRef As %String) As %Status`: deletes every `ConversationLink` row whose `OwnerRef` is the argument (any agent), checking `%SQLCODE`; an empty argument, `instance` or `eval` is an error naming `OcuTalon.Bridge.Purge.DropLinks` and deletes nothing; it names no OcuTalon package (AD-2). Update the class doc (links are dropped only here and by `Point`'s owner). Test: `Test/Bridge/Purge.cls` new `TestDropLinks` (two agents' links of one owner go, another owner's link stays, `""`, `instance` and `eval` are refused with nothing deleted). -- DW-581.
- [ ] `Data/Purge.cls` (from Task 1) -- extend `Run` (rows 1-8, 23):
  - `Keeps(ref, ...)` also keeps a session that has an `OcuTalon_Data.Memory` row (`SessionRef`) or an `OcuTalon_Data.Document` row (`OwnerRef`) of it; these two reads run with the other SQL checks, before the store scan.
  - For each session that goes, after the re-check and before `%DeleteId`: delete its `OcuTalon_Data.GuideState`, `OcuTalon_Data.SimMessage`, `OcuTalon_Data.BreakFeedRun` rows and its `OcuTalon_Data.Reminder` rows in State fired or cancelled (SQL, `%SQLCODE` checked), then call `##class(OcuTalon.Bridge.Purge).DropLinks(ref)`. When any of these fails, the Session row stays (a later run retries it) and the error is appended.
  - Nothing reads or writes `OcuTalon.Data.Setting`, Memory or Document beyond the two existence reads; the word "audit" stays out of the class text (the static check scans it).
  - Update the class doc to the AD-27 bullet's contract.
- [ ] `Install/Step/Retention.cls` -- `Purge` (from Task 1): take `now = Bridge.Time.NowUtc()` once, call `Data.Purge.Run(days, now)` first, then `Bridge.Purge.Run(days, now)`, appending the two statuses so each part runs whatever the other returned; doc updated (one cut for decisions and turns; links dropped before the bridge looks for unlinked AI sessions). -- row 3.
- [ ] `Test/Data/Purge.cls` (from Task 1) -- extend:
  - `TestTurnsReadNoPurgedDecision` (rows 1-3): add a 91-day Telegram `Delivery` with a kept `Text` (U-218), gone after the run; the 89-day turn's readers are unchanged.
  - `TestSessionKeptWhileActiveOrCurrent` (rows 4-6): add a kept case for a Memory row and one for a Document owned by the session; keep every existing case.
  - New `TestSessionRowsGoWithIt` (row 23): an idle 91-day session with a GuideState, a SimMessage, a fired and a cancelled Reminder, a BreakFeedRun and a ConversationLink (inserted by the fixture), and a kept session with the same rows: after `Retention.Purge(90)` the first session's rows and link are gone, the kept session's stay, and a Memory row of a third, kept session is untouched.
  - `TestOnlyOwnTablesAndAuditKept` (row 7): the static list of deleted tables becomes Turn, Delivery, GuideState, SimMessage, Reminder, BreakFeedRun and Session, plus the one call `OcuTalon.Bridge.Purge).DropLinks`; still no `%SYS`, no audit name, no table outside `OcuTalon_Data`/`OcuTalon_Bridge_Data`.
  - Each test removes its own rows (`Fixture.Clean` plus the new tables' rows and links), also after a failure.
- [ ] `Test/Install/Retention.cls` -- DW-590 (after Task 1's merge): `WaitRun` becomes start-aware for every task: it waits up to `RUNSECONDS` for the start (`LastStarted` after the mark or `RunningJobNumber` set), re-calling `RunNow` every `RETRYSECONDS` while not started, then up to a new `FINISHSECONDS` (300) for the History row; a timeout's failure text names the task, the phase (start or finish) and the seconds waited. The Task Manager still runs all three tasks (Story 30.2 AC 2). Update the header doc.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Approval.cls` -- DW-588, DW-582:
  - New `ClassMethod AnswerHold(ref As %String, completionKey As %String, response As %Persistent) As %Boolean [ Internal ]`: for `LiveHold(ref)`, finds its one non-timer pending response with that `CompletionKey`, and sends `response` to it with `Ens.Host.SendDeferredResponse(<RequestHeaderId>_"|"_<the running production's name>, response)`; returns 1 when sent, 0 when there is no such hold or response; never raises (a failure is a warning that names the Ref).
  - `CompleteHoldTask`: when no open task appears within TASKSECONDS, it calls `AnswerHold(ref, "task", <Ens.StringResponse whose StringValue is the action, "" for a cancel>)`; the warning becomes "OcuTalon.Bridge.Approval: no open task of <ref> appeared in <n> seconds, so the answer went to its hold directly" (or the old text when `AnswerHold` returns 0). A late task that appears afterwards stays open until Reconcile pass 1 cancels it (its hold is no longer live).
  - `HoldResponse`, key `task`: the action is `%Action` of an `EnsLib.Workflow.TaskResponse` or `StringValue` of an `Ens.StringResponse`; everything else is unchanged (the hold still acts only on what the row shows).
  - Docs of `CompleteHoldTask`, `HoldResponse` and `Arm` (its "delivered when the timer fires" sentence) updated.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Replay.cls` (from Task 1) -- DW-444, DW-582:
  - `CloseInterrupted`: after `FinishExecution(ref, "interrupted")` of a row, calls `Approval.AnswerHold(ref, "replay", <a failure Reply: FailureText "the replay was interrupted", ToolsRun 0>)`, so a hold still waiting on that replay ends once.
  - `Run` (the private `Execute` of the patch): when `StartExecution` refuses and the reloaded row is a `tool_call` in State `executing`, the job holds the replay lock, so no replay is alive: it closes the row with `Record(row, ref, "interrupted")` and answers the failure Reply (ToolsRun 0). The call never runs.
  - Docs updated (steps 1 and 3 of the class doc; `CloseInterrupted`).
- [ ] `Test/Bridge/Interrupted.cls` (new, `OcuTalon.Test.Bridge.Interrupted`, Lane A, area Bridge) -- rows 11-13 and 20; production-bound (warm or CI):
  - Move here from `Test/Bridge/Approval.cls` (Task 1) the patch's `TestInterruptedReplayIsClosed`, `TestLiveReplayIsLeftAlone`, `TestExecutingFixIsLeftAlone` and their helpers (`ReplayRow`, `HoldReplayLockInJob`); `TestExecutingFixIsLeftAlone` also holds an executing `setting` row, untouched.
  - New `TestHoldOfAnInterruptedReplayEnds` (row 20): raise and approve a `tool_call` whose `Runner` is a runner item the test disables first (0b(1)); once its hold waits on `replay`, the test calls `StartExecution(ref)` (the crashed replay) and `Bridge.Approval.Reconcile()`. Asserts: the row is `failed` with Result `interrupted`; the hold ends within 10 s of Reconcile and before Decide's timer; one `approval.result`; one Approval `finished`/`interrupted` and one Action `interrupted` entry; the tool ran 0 times. After the item is enabled again the queued request is refused by `StartExecution`: still one `approval.result`, the tool still ran 0 times.
  - Reuse `Test.Bridge.Approval`'s ClassMethod helpers by `##class(...)` and `ApprovalRows`; an instance helper the new class needs (`UseReplayAgent`, `RunnerRequests`, `AssertOneOutcome`) may become a ClassMethod or move to `ApprovalRows` with no change of behaviour. Each test removes its rows, holds, tasks and queued requests, and re-enables every item it disabled, also after a failure.
- [ ] `Test/Bridge/Approval.cls` -- rows 18 and 21 (DW-462, DW-588): rewrite `TestAnswerBeforeTheTaskExists`, replacing the patch's version and dropping its fake-task helpers (`FakeHoldTask`, `RemoveFakeTasks`, and `RealOpenTask`/`AssignedTo` if no longer used), in two cases:
  - (a) late task: keep `OcuTalonApprovals` disabled until the answer job has returned `done|`; assert the hold receives the answer (one `approved` outcome, `AssertOneOutcome`; `WaitHoldGone(ref, 15)` is 1); then enable the item and, as Task 0b (3) measured, either wait up to 60 s for the late task and assert it is open, or assert that none appears; run `Bridge.Approval.Reconcile()`; assert no open task of the Ref remains and still exactly one outcome.
  - (b) task inside the window: enable the item while the answer job waits (as today); whichever comes first, the poll completing the task (`Approve|OcuTalonWorkflow|1|`) or the direct answer, the hold ends and exactly one `approved` outcome is sent; then `Reconcile()` leaves no open task of the Ref. The test asserts no timing. Remove the moved DW-444 tests from this class. Search the class for assertions on the old "so none was completed" warning and update them. Header lines updated.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` (contended; from Task 1) -- `ConcludeTool` and parameters only:
  - Keep the patch's rule: a failure whose text holds both `NOKEYTEXT` pieces, from a Reply with ToolsRun 0 whose row is no longer approved, is recorded with FallbackReason `no_key` and Reasons `REPLAYNOKEY` = "No model key is set, so the approved call did not run. Nothing was changed." (row 14).
  - Add, only when Task 0a (ii) shows a provider-object failure in `BuildAgent` or `NewSession` that is not a missing key: parameter `PROVIDERTEXT` (the measured piece of that error text, with its source note, like `TIMEOUTTEXT`) and `REPLAYPROVIDER` = "The model provider could not be reached, so the approved call did not run. Nothing was changed."; such a failure with ToolsRun 0 is recorded with FallbackReason `error` and Reasons `REPLAYPROVIDER` (row 15). When Task 0a finds no such failure, neither parameter is written and the evidence is recorded.
  - No tool's-server sentence (row 15b; see Design Notes). Every other failure is unchanged: `error`, no sentence (row 16).
- [ ] `Test/Bridge/Decide.cls` (contended; from Task 1) -- `TestToolFailureReasons` (placed after `TestToolRequest`, `:406`): add the provider-object case when `REPLAYPROVIDER` exists, and a context failure (ToolsRun 0, a bridge text) that stays `error` with no sentence. -- rows 14-16.
- [ ] `Test/Bridge/Runner.cls` (from Task 1) -- `TestReplayWithoutAKey`: keep the unset-key and closed-port halves (the closed port runs the tool once); add the provider-object case of 0a (ii) asserting the step's FailureText and ToolsRun 0 (the test's doc names the endpoint: the AI Hub provider object that the runner's `BuildAgent` builds from its `ProviderConfig`); new `TestReplayOfADeadExecutingRow`: an executing row whose replay lock is free, replayed through the runner, ends `failed`/`interrupted` with one Action `interrupted` entry, ToolsRun 0, and the tool ran 0 times. -- rows 11, 14, 15.
- [ ] `Test/Schedule/Reminders.cls` (Lane B test; footprint extension) -- new `TestToolCallKeysAfterAList` (row 22, U-215), modelled on `TestSeveralCancelsFromOneToolCall`: under one bridge context, `ReminderTools.ListReminders()` then `CancelReminder([r1, r2, r3])`: each row cancelled with CancelKey `<item>:2`, `:3`, `:4`, three cancelled events and one trigger each. The same turn again (same ItemId): each answer equals its first, no new event, no new trigger (the owner ignores the repeat, AD-1). A third run with `[extra, r2, r3]`: key `:2` is refused `reused_key` and `extra` stays pending. No product code change.
- [ ] `Test/Bridge/Gate.cls` (contended) -- one row only: `:2014` becomes `$ListBuild("OcuTalon.Tools.Reminders", "cancel_reminder", "{""reminderRefs"":[""x""]}")`. -- row 24, DW-495.
- [ ] DW-371 and DW-541: delivered by Task 1's hunks (`Watch/IncidentManager.cls`, `Watch/Reader.cls`, `Tools/WatchAnswers.cls`, `Tools/WatchTools.cls`, `Test/Watch/Reader.cls`, `Test/Watch/Tools.cls`); confirm each against the Code Map anchors, change nothing else. -- row 19.
- [ ] DW-589 and the Delivery doc line: no code (Design Notes).

**Acceptance Criteria:**
- Given a run of the purge task, when it ends, then no kept Turn names a Decision that is gone and no kept Turn's `TurnCost` reads 0 because its Usage was purged, and every Delivery recorded before the cut, Telegram rows with kept text included, is gone (DW-437, U-210, U-218).
- Given a session that has activity at or after the cut, is current, or holds a memory or a document, when the purge runs, then its Session row and all its rows are kept; and a session is never purged by its age alone (DW-437, condition 1).
- Given a session that the purge deletes, when the run ends, then its GuideState, SimMessage, finished Reminder and BreakFeedRun rows and its conversation links are gone, and the same run's bridge purge no longer finds a link naming its AI sessions (DW-581).
- Given the purge runs, when it ends, then it deleted only `OcuTalon_Data` rows of the seven named tables and conversation links through `Bridge.Purge.DropLinks`, and every IRIS audit entry for approvals and actions is still present (DW-437, condition 2).
- Given the amended spine, when `lint_spine.py` runs, then its output is the 10 baseline low findings and nothing new.
- Given an instance start after a crash mid-replay, when the Reconcile step runs or the replay is re-delivered, then the row ends `failed`/`interrupted` once, with one `approval.result` and the audit entries, the hold that waited on it ends, and the call never runs again (DW-444, DW-582).
- Given an answer recorded before its approval task exists, when TASKSECONDS pass, then the hold gets the answer at once and sends exactly one outcome, and a task that appears later changes nothing (DW-588, DW-462).
- Given a replay that fails before the tool ran because no key is set (or, per Task 0a, because the provider object cannot be built), when the person's views read its failed Decision row, then the Reasons line is the owner-ruled sentence for that endpoint; and no public text claims that a replay works without a provider connection (DW-470, U-214).
- Given one `cancel_reminder` call with three refs after a list, when each key is sent again, then each key acted once and a repeat has no second effect, and a key reused for another reminder is refused (DW-584, U-215).
- Given `Test.Bridge.Gate`'s untrusted-turn rows, when `cancel_reminder` is made read-only by a mutation, then the row reports that its method ran (DW-495).
- Given `IncidentManager.Purge(n)`, when it runs, then its cutoff is `Bridge.Time.DaysCutoff`'s and `Test.Watch.Lifecycle`'s purge tests pass unchanged (DW-371).
- Given the Chat agent calls `list_productions`, when Orders is stopped, then its entry's `state` is `stopped`, built from IRIS's status code alone (DW-541).

## Spec Change Log

- 2026-11-08 (lead, SC-5 re-open, runner B): the set-aside patch did not apply on 2e78a4f7 (`git apply --3way` exit 1: Bridge/Approval, Test/Install/Retention, Redact, Test/Bridge/Redact, Test/Eval/KeyProof and the spine conflicted), so per doctrine U4 the story is re-planned (status draft, review_loop_iteration 0) with the patch kept as reference. The intent now carries the owner decisions U-210, U-214 and U-215, drops DW-386 and DW-448 (Story 30.8), and adds DW-495, DW-581, DW-582, DW-584, DW-588, DW-589 and DW-590; the deferred: list was removed (already harvested as DW-588 to DW-590). The I/O matrix rows 10 and 17 are void (30.8), and row 15 follows U-214.

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

**Architecture decisions (Rule 6).** AD-27 (the one amendment, the U-210 bullet; marker `[AMENDED 2026-11-08, Story 30.7, owner decision U-210 (kept)]`); AD-1 (U-215: the keys as built, the lead's 2026-11-08 marker; no change); AD-2 (the bridge names no OcuTalon package; the host calls `Bridge.Purge.DropLinks`, never the reverse); AD-4 (the Session row and the records it owns); AD-8 (`no_key` for a missing key, `error` for anything else; a sentence lives in Reasons, never as a new reason); AD-10 (the replay through the full policy chain; replay is for MCP and developer tools); AD-11 (rows change only through the Approval API; `interrupted` leaves `failed`; the hold acts only on what the row shows); AD-15 (`list_productions` reads through `Watch.Reader`); AD-16 (`interrupted`, as for `FixRun`); AD-17 (no audit entry is purged; every close is audited); AD-22 (destructive and purge runs on throwaways); AD-31 (the HostSink and `approval.result`); AD-33 (one owner per table; see Footprint). No AC contradicts an AD's Rule.

**Decided in-stage (unattended; each small and reversible inside this story).**
- **Activity counts every Delivery,** the daily digest's included, exactly as U-210 words condition 1. A session that still gets the digest is therefore kept; in practice the session purge removes signed-out online-demo sessions and others that receive nothing. Excluding digest rows would delete sessions U-210's wording keeps, so it is not done.
- **A memory or a document keeps its session.** The intent forbids touching Memory, and both `Memory.DropSession` and `Docs.DropSession` are stubs, so purging such a session would strand the person's rows under a Ref nobody holds. This keeps more than the ruling requires, never less (as the pairing signal does). Two existence reads, no write.
- **DW-581's list is the parenthetical list** (GuideState, SimMessage, finished Reminder, BreakFeedRun, ConversationLink), as DW-581 and veto U-308 name them. Other rows keyed by a session (below, "For the lead") are not deleted, because deleting them is a retention change no ruling covers.
- **The host purge runs first** in `Retention.Purge`, with the bridge's `now`, so the links it drops are found unlinked by the same run's `Bridge.Purge` (a day sooner). The cut is the same either way: the session check reads only rows at or after the cutoff.
- **`DropLinks` lives on `Bridge.Purge`,** the one bridge class besides Decide that already names `ConversationLink`, so the link table keeps one owner (AD-33) and the host never deletes a bridge table by SQL.
- **DW-582 and DW-588 share one mechanism:** `Approval.AnswerHold` sends a deferred response to the live hold's pending request (`task` or `replay`), so no stored column, no new message class and no Workflow task subclass is needed. The `task` answer is an `Ens.StringResponse` rather than a hand-made `TaskResponse`, so no stray Workflow task row appears.
- **The re-delivered replay closes its row.** After a restart Ens re-queues the runner's request; `Run` holds the replay lock, so a row it finds `executing` has no live replay and is closed `interrupted` there. Pass 4 closes the rows that no re-delivery reaches. Each row is closed once, by whichever comes first, through `FinishExecution`.
- **DW-444 on any Reconcile call** stays safe without a start-only path: the replay lock makes a live replay untouchable (row 12), which is the reason the candidate fix asked for "never on a test's call".
- **U-214, the endpoints.** The replay needs the model provider only as the provider object that `BuildAgent` builds from the runner's settings; it sends no request to the provider (2026-11-02, closed port: the tool ran; code read above). So the no-key sentence applies to a missing key, the provider sentence only to a provider object that cannot be built for another reason (Task 0a (ii)), and a closed or unreachable provider fails no replay, so it has no sentence. The tool's-server sentence has no case: the product has no MCP client or MCP replay path yet (Epic 22), and a developer tool's own error after it ran stays unchanged (intent). The tests name their endpoint: the AI Hub provider object of the runner's `BuildAgent`.
- **U-215, "refused on a repeat"** is pinned as the owner ignoring a repeat (AD-1: the first result, no second effect), plus the refusal `reused_key` for a key reused for another reminder; that is the as-built rule U-215 keeps with no code change.
- **DW-590** keeps the real Task Manager runs (Story 30.2 AC 2) and makes the wait start-aware, so a slow start and a slow run are told apart in the failure text.
- **Test placement.** The DW-444 and DW-582 tests go to a new class, `Test.Bridge.Interrupted`, because `Test.Bridge.Approval` already takes about 140 s and must fit one command.

**Measured at implementation.** Empty until Task 0 runs; Task 0a and 0b record their results here.

**PUBLIC TEXT (for the lead's gate before implement).**
- Public (a person reads it), new:
  - `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`, parameter `REPLAYNOKEY`: "No model key is set, so the approved call did not run. Nothing was changed." (intent row 14). It is the Reasons line of the replay's failed Decision row, shown verbatim in the web's decision strip and rail (`Live/Payload/Decision.cls:88`); the result notice shows only `HeldReasons` lines (Lane B's `BridgeSink`, unchanged), so it does not appear there.
  - Same file, parameter `REPLAYPROVIDER`, only if Task 0a (ii) finds its case: "The model provider could not be reached, so the approved call did not run. Nothing was changed." (U-214, verbatim). Same readers.
  - No other public text: no catalog key, web text, Telegram text, chip text or `ci/mock/scenarios/B/` change. The U-214 tool's-server sentence is not written (no case, above).
- Model text (the model reads it; not public):
  - `Tools/WatchTools.cls` `ListProductions` doc, the tool description. Now: "Lists the productions that can be watched: each one's name and namespace. Use it to answer which productions OcuTalon can watch. It starts nothing." New (patch): "Lists the productions that can be watched: each one's name and namespace, and its running state (running, stopped and so on). Use it to answer which productions OcuTalon can watch, and whether each is running. It starts nothing."
  - The new `state` member of each `list_productions` entry, one of `running`, `stopped`, `suspended`, `troubled`, `network_stopped`, `timeout`, `unknown`.
- Operator text (Event Log or Task Manager status, read by an admin): the `Data.Purge` and `DropLinks` error statuses (from `DaysCutoff`, naming the method, as `Digest.Data.Item.Purge`'s); the new warning "OcuTalon.Bridge.Approval: no open task of <ref> appeared in <n> seconds, so the answer went to its hold directly"; the `AnswerHold` failure warning naming the Ref; the internal FailureText "the replay was interrupted" (never a Reasons line).

**Contended hunks (Epic 19, unmerged; for the lead to clear).**
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: (1) new parameters `REPLAYNOKEY` (and, per Task 0a, `PROVIDERTEXT`, `REPLAYPROVIDER`) after `HELDBEFOREUPDATE`/`NOKEYTEXT` (`:178-186`); (2) `ConcludeTool` doc and body (`:1435-1467`). Epic 19's change is `Conclude`'s turn-filter call at `:1355`, untouched.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls`: (1) one header doc line (`:9`); (2) new method `TestToolFailureReasons` after `TestToolRequest` (`:406`, before `:412`). Nothing near `:1320-1340`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Gate.cls`: one changed row at `:2014` in `AssertSafeReadOnlyOnly`. Nothing near `TestTaintFollowsTrustedOutput` (`:1299`) or `FreeIncident` (`:2182`).

**Footprint (AD-33, Rule 11).** Lane A (Epic 30): the bridge files, `Install/Step/Retention.cls`, Watch, Tools and their tests. Footprint extensions to report: `Data/Purge.cls` and `Test/Data/Purge.cls` (new, Lane B's Data area, by the dispatch's allowance: SQL deletes of other tables' rows, none of their classes edited) and one method in `Test/Schedule/Reminders.cls` (Lane B's test class). Not touched: `Data/Session.cls`, `Data/Delivery.cls`, `Agent/Chat.cls`, Memory, Docs, Settings, `Core/BridgeSink.cls`, `Test/Web/SessionEvents.cls`, `web/`, `ci/mock/scenarios/B/`, `release/**`, `eval/run.sh`.

**Integration ACs (Rule 1).**
- The Task Manager's OcuTalon purge task reads `Data.Purge` through `Retention.Purge`: the 61-day turn is gone, the 59-day one stays (row 9, `Test.Install.Retention`).
- `Data.Purge` reads `Bridge.Purge.DropLinks`: a purged session's links are gone after `Retention.Purge` and a kept session's stay (row 23, `Test.Data.Purge`).
- `ChatMessage.FromRow` and `Ownership.TurnCost` read a kept turn's decision and cost (row 2).
- The Reconcile step reads `Replay.CloseInterrupted`, and the hold reads `Approval.AnswerHold`'s response: the row is closed and the hold ends (rows 11, 20, `Test.Bridge.Interrupted`); the answering job's `CompleteHoldTask` reaches the hold the same way (row 21, `Test.Bridge.Approval`).

**Consumed-by:** `Install.Task.Purge` (through `Retention.Purge`); the Reconcile step (`Install.Step.Approvals`); `ApprovalHold` (the deferred answers); Story 31.2, Lane B (the Reasons sentence on its card); the Chat agent (`list_productions`'s `state`).

**Consumes:** `Bridge.Time.DaysCutoff`/`NowUtc` (30.2); `Bridge.Purge.Run` (30.2); `Bridge.Approval.StartExecution`/`FinishExecution`/`Reconcile`/`LiveHold` (30.3); `Bridge.Audit.Record`; `Ens.Host.SendDeferredResponse`; `Watch.Reader.Current`; `Tools.CommandCall` and `Schedule.ReminderOps` (U-215 test).

**Extend, don't copy (Rule 2).**
- `Data.Purge`'s deletes follow `Digest.Data.Item.Purge`'s form (a copy, because the bridge's `DeleteBefore` must not delete host tables, AD-2, and Turn uses `CreatedAt`); its store read follows `Web/Public/Status.cls` `Visitors` (6 lines: Status is Lane B's public-status class and counts, while the purge needs a per-Ref test); its list of a session's rows follows `SessionOps.End`.
- `Bridge.Purge.DropLinks` extends `Bridge.Purge` (its SQL delete form).
- `Replay.CloseInterrupted` and the re-delivery close extend `Replay.Record`/`ActionEntry`.
- `Approval.AnswerHold` is one helper with two callers (`CompleteHoldTask`, `CloseInterrupted`).
- `IncidentManager.Purge` adopts `DaysCutoff` (DW-371); `WatchAnswers.Listed` extends `Names`' output.
- `TestToolFailureReasons` extends `TestToolRequest`'s helpers; `Test.Bridge.Interrupted` reuses `Test.Bridge.Approval`'s ClassMethods and `ApprovalRows`; `TestToolCallKeysAfterAList` follows `TestSeveralCancelsFromOneToolCall`.

**Ledger inbox (Rule 17).**
- DW-437: addressed (rows 1-9; spine, `Data.Purge`, `Retention`, tests; U-218's Telegram row in row 1's test). Declined DW-437 (the `Data/Delivery.cls` Text doc line): Lane B owns the class and the dispatch allows no edit there; the line (`:29`) should say that Telegram rows keep their sent text too.
- DW-581: addressed (row 23; `DropLinks`, the session's rows).
- DW-444: addressed (rows 11-13; pass 4 and the re-delivery close).
- DW-582: addressed (row 20; `AnswerHold` from `CloseInterrupted`).
- DW-588: addressed (row 21; `AnswerHold` from `CompleteHoldTask`).
- DW-462: addressed (row 18; the rewritten test no longer depends on when the task appears).
- DW-470: addressed (rows 14-16; Task 0a; U-214 as decided above).
- DW-584: addressed (row 22; `Test.Schedule.Reminders`).
- DW-495: addressed (row 24; the one Gate row).
- DW-590: addressed (the start-aware wait in `Test.Install.Retention`).
- DW-371: addressed (`IncidentManager.Purge`, Task 1). Declined DW-371 (the `Data.Pairing.Purge` half): Lane B's file; it keeps its own ledger owner.
- DW-541: addressed (row 19, Task 1; preferred fix, so the chip text stays).
- DW-589: closed by measurement, no code. The key-proof global scan, from CI logs: before Story 30.8 8.1 s and 10.1 s (runs 41495443772 and 41495053476, about 4.24 million nodes; the whole key proof 16 s and 20 s); after it 56.8 s, 52.7 s and 56.1 s (runs 41526116657, 41540068521, 42456641444, 4.26 to 4.73 million nodes; 59 to 65 s). That is about 2 to 12 microseconds a node, about +45 s for each evaluation job. Each figure is the scan's own `PASS key proof globals: ... ; N s` line, on the throwaway stack of CI's evaluation job (intent row 25). Recommended for the lead: `wontfix-accepted`, reopen_if the evaluation job's key-proof step passes 120 s or the job nears its timeout. Declined DW-589 (code change): the cost is known and small against the job, and `eval/run.sh` is frozen.

**Lead spec gate (2026-11-08, runner B).** Rulings (decide): (1) intent row 15b has no reachable case on this head (no MCP replay path; Epic 22): the U-214 tool's-server sentence is not written, and the provider sentence only for a provider object that fails to build for a reason other than a missing key (Task 0a), since U-214's condition is that the wording follows the endpoint that actually failed; (2) U-215's "refused on a repeat" is pinned as AD-1's "its owner ignores a repeat" (the first result, no second effect), plus `reused_key`; (3) U-210 condition 1 counts every Delivery, the daily digest's included (owner wording kept; reported to the orchestrator). PUBLIC TEXT: only owner-ruled sentences (U-214 verbatim; the no-key sentence is U-170's no_key wording plus "Nothing was changed.", which U-214 keeps): no `PUBLIC TEXT:` gate needed. Contended hunks: cleared with the orchestrator before the implement stage (see the cycle log).

**For the lead.**
- Rows keyed by a purged session that stay (inference from the table survey; no ruling covers them): `Handled`, `HeartbeatBeat`, `OcuTalon_Digest_Data` Item, CheckRun and the newest Sent row, the `person.<Ref>.*` Setting rows (AD-27 forbids a purge reading `Data.Setting`), the globals `^OcuTalonP.SessionM(<ref>)` and `^OcuTalonP.LiveEventC(<ref>)`, and memories and documents (which keep their session here). File them if you see a need.
- A `setting` row left `executing` by a crash is not closed by anything (as `fix` rows are by `Fix.Run`); pass 4 leaves it alone by design (Kind filter). File it if you see a need.
- The `REPLAYNOKEY` sentence meets DW-596's reopen_if (Lane B's `BridgeSink.HeldReasons` shows only `HELDBEFOREUPDATE` in the result notice).
- **Row 15b has no reachable case on this head.** The product has no MCP client or MCP replay path (no `call_mcp_tool` in `src/`, the gate only recognises `mcp:` toolrefs, Epic 22 is backlog), so no test can name a tool's server and the U-214 tool's-server sentence is not written; a developer tool's error after it ran stays row 16 (unchanged, no sentence). This follows the dispatch's rule for the provider sentence (not used when the replay never needs that endpoint). If you want it built ahead of Epic 22, that is a scope call for the owner; the sentence then belongs with the first MCP replay.
- `shards-5` (Test.Bridge) is the tightest group: about 1,950 s by the `ci/units.sh` notes (inference) plus `Test.Bridge.Interrupted` (about 40 s, inference) and the small Runner and Decide additions; the lead re-measures it on the first CI run.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=30 stage=implement'`, run from the epic worktree root (QA and review put their own stage name in `OCUTALON_LOCK_OWNER` and their own tag letter after `e30s7`). The fresh tag is `e30s7i`, the warm tag `e30s7iw`. Waiting on lane B's lock is normal.

How to run:
- One command per tool call, in the foreground, `timeout: 600000`, sized to finish in about 150 s; never two IRIS test runs in one message; one `iris_execute_tests` call per message, with `server` and `namespace` on every IRIS MCP call.
- Throwaways only for purge, replay and production-bound classes. Slot B (`ocutalon-slot-b`, `OCUTALON`) is for loading and compiling and for non-destructive in-process classes; no purge, Reconcile or item toggling there.
- Warm for every repeated class run; a change to the image or the mock refuses the warm run (`ci/warm.sh down`, then `up`). Tear down only your own tags, also after a failure.

**Commands:**
- (loop) `bash docker/tests/test-boundaries.sh` and `bash docker/tests/test-class-rules.sh`, one call each -- expected: pass; `key_like` finds nothing; every new SQL checks `%SQLCODE`.
- (loop) `<lane> OCUTALON_RUN_TAG=e30s7iw ci/warm.sh up` once, then one call per class: `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e30s7iw ci/iris.sh class <Class>` -- expected: `CLASS <Class> passed`. Classes: `OcuTalon.Test.Data.Purge`, `OcuTalon.Test.Bridge.Purge`, `OcuTalon.Test.Bridge.Interrupted`, `OcuTalon.Test.Bridge.Runner`, `OcuTalon.Test.Bridge.Decide`, `OcuTalon.Test.Schedule.Reminders`, `OcuTalon.Test.Bridge.Gate`, `OcuTalon.Test.Watch.Lifecycle`, `OcuTalon.Test.Watch.Reader`, `OcuTalon.Test.Watch.Tools`, `OcuTalon.Test.Data.Ownership`, `OcuTalon.Test.Install.Registry`.
- (loop) the same warm form for `OcuTalon.Test.Bridge.Approval` (about 140 s of its own time on 2026-11-02) and `OcuTalon.Test.Install.Retention` (about 110 s), each in its own call -- expected: passed. A call that would not return inside about 150 s is not retried in the background: the class is left to CI (`shards-5`, `shards`) and the stage says so under Auto Run Result.
- (once) Task 0a and 0b on `e30s7iw` (tasks above), results under "Measured at implementation".
- (once) `uv run --no-cache _bmad/scripts/memlog.py append --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16 --type decision --text "AD-27: the host purge of turns, deliveries and idle sessions with their rows (U-210 kept, DW-581), Story 30.7"`, then `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: `"ok": false` with exactly the 10 baseline low `placeholder` findings (by token; line numbers may shift).
- (once) `git grep -n -i -E "without (asking )?the model|no model|replay|offline|provider" -- README.md docs web/src src/ocutalon/cls/OcuTalon/Msg/Catalog` -- expected: no text claims that a replay works without a provider connection; record the hits.
- (once) `bash ci/checks.sh` -- expected: every script passes.
- (once) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e30s7iw ci/iris.sh shard lane-a --part k/n` and `shard lane-b --part k/n`, one part per call, with `n` chosen so that each part finishes in about 150 s -- expected: passed. The fresh forward and reverse shards are the lead's fresh check (Rule 19) and CI's.
- (once) `<lane> OCUTALON_RUN_TAG=e30s7iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e30s7i ci/iris.sh teardown`, also after a failure.

**CI groups of the new tests (`ci/units.sh`):** `Test.Data.Purge` (new) and the new method of `Test.Schedule.Reminders`: lane-b (`Data`, `Schedule`) in `image` (about 1,740 s); `Test.Bridge.Interrupted` (new), `Test.Bridge.Purge`, `Runner`, `Decide`, `Gate`, `Approval`: `shard:lane-a@Bridge,Agent` in `shards-5` (about 1,950 s, the tightest; see "For the lead"); `Test.Install.Retention`, `Test.Watch.*`: `shards` (about 1,830 s). Each stays under 35 minutes with this story's additions (inference until CI measures them). No new group and no `ci/units.sh` change.

**Shared surfaces:**
- The OcuTalon purge task now deletes Turn, Delivery, Session, GuideState, SimMessage, finished Reminder and BreakFeedRun rows and conversation links: `Test.Install.Retention` and any test whose fixtures are back-dated past 60 days (search `Test/` for back-dated `CreatedAt`, `RecordedAt`, `Utc(6`, `Utc(9`).
- Reconcile gains pass 4 and `CompleteHoldTask` answers the hold directly: every test that runs Reconcile with an executing `tool_call` row (none today, search `Test/` for `Reconcile` and `executing`), and every test that asserts the old "so none was completed" warning or a hold left waiting after a late task.
- `HoldResponse`'s `task` key also takes `Ens.StringResponse`.
- `Watch.Reader.Productions` entries (+`state`): `TestOrdersIsListed`; the `list_productions` answer: `Test.Watch.Tools`.
- `TestNoSettingRead`'s class list; `TestOnlyOwnTablesAndAuditKept`'s list of deletes.
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations (Rule 19), one per AC; apply, observe red, revert byte for byte (`git status --short`, `git diff --stat` unchanged), record as `mutation: ... -> ...`:**

| AC | Mutation | Expected red |
|---|---|---|
| Kept turns read no purged decision (rows 1-3) | `Retention.Purge` does not call `Data.Purge` | `Test.Data.Purge.TestTurnsReadNoPurgedDecision`; `Test.Install.Retention.TestOcuTalonPurge` |
| Condition 1 (rows 4-6) | drop the Memory read from `Keeps` (then each other signal, one at a time) | `TestSessionKeptWhileActiveOrCurrent`, that signal's case |
| DW-581 (row 23) | `Data.Purge` skips the `DropLinks` call | `TestSessionRowsGoWithIt` (the link stays) |
| Condition 2 (row 7) | add a delete of a table outside the seven | `TestOnlyOwnTablesAndAuditKept` |
| Spine lint | a brace in the new bullet | the lint shows an 11th finding |
| DW-444/DW-582 (rows 11, 20) | `CloseInterrupted` skips `AnswerHold` | `Test.Bridge.Interrupted.TestHoldOfAnInterruptedReplayEnds` (the hold does not end in 10 s) |
| DW-444 re-delivery | `Run` does not close an executing row it finds | `Test.Bridge.Runner.TestReplayOfADeadExecutingRow` |
| DW-588/DW-462 (rows 18, 21) | `CompleteHoldTask` does not call `AnswerHold` | `Test.Bridge.Approval.TestAnswerBeforeTheTaskExists` (no outcome before the late task) |
| DW-470 (rows 14-16) | `ConcludeTool` keeps `error` and no sentence for the no-key text | `Test.Bridge.Decide.TestToolFailureReasons` |
| DW-584 (row 22) | delete the `KeyedRow` block of `ReminderOps.Cancel` (`:176-182`) | `Test.Schedule.Reminders.TestToolCallKeysAfterAList` |
| DW-495 (row 24) | `Parameter READONLYCANCELREMINDER = 1` | `Test.Bridge.Gate` untrusted and tainted rows, with "its method ran" in the failure |
| DW-371 | `DaysCutoff` called with `daysToKeep + 1` in `IncidentManager.Purge` | `Test.Watch.Lifecycle.TestPurge` |
| DW-541 (row 19) | `state` dropped from `Listed` | `Test.Watch.Tools.TestListProductions` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

- Re-planned on `76c31e50` (2026-11-08). The intent contract is unchanged. Task 1 reuses the set-aside patch's 14 clean files and merges `Bridge/Approval.cls` and `Test/Install/Retention.cls` by hand; the later tasks add DW-581, DW-582, DW-584, DW-588, DW-495, DW-590, U-214's endpoints (Task 0a) and the Ens checks (Task 0b). DW-589 is closed by CI numbers with no code.
- For the lead's gate: PUBLIC TEXT, Contended hunks, the footprint extensions and "For the lead" are under Design Notes.
