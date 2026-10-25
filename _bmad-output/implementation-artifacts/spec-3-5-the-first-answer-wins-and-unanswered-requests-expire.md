---
title: 'Story 3.5: The first answer wins, and unanswered requests expire'
type: 'feature'
created: '2026-10-24'
status: 'done'
baseline_revision: 'd94f26dcba3d540458c94a17e1d5b6a0b339c8ca'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-11, the HostSink contract of AD-31, the waiter bullet of AD-5, the FixExecutor bullets of AD-16, the "cancelled request sends no ApprovalOutcome" sentence of AD-15, the "Ending an online-demo session" bullet of AD-4, AD-26, and the Consistency Conventions row "Approval requests")'
warnings: ['oversized']
deferred:
  - summary: >-
      A pending approval row can lose its hold (a task completed outside Answer, the timer's Expire failing on the lock or a save, a past-expiry Answer on a row whose hold is gone), and then no timer fires and no ApprovalOutcome is sent until the next Reconcile.
    evidence: |-
      Approval.HoldResponse sends nothing for a task whose action does not match the row (matrix row 14 pins it), and the framework clears the leftover timer after a TaskResponse. Story 3.4's hold ended on a direct completion the same way. A late Answer still expires the row (step 4), so the request cannot be approved late; only the expired outcome to ResultTarget is missing. Reachable by a worklist user completing the task directly, or by a lock timeout on the timer's Expire.
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Approval.cls (HoldResponse)
    severity: medium
---

<intent-contract>

## Intent

**Problem:** Story 3.4 holds an approval request in IRIS Workflow, but nothing can answer, expire or cancel it: `Answer`, `Expire`, `Cancel`, `StartExecution` and `FinishExecution` are still Epic 0's stubs, and `ApprovalHold`'s response handler changes nothing. So a request stays pending forever, two answers cannot be told apart, and no outcome reaches its `ResultTarget`.

**Approach:**
- Build the five state methods of `OcuTalon.Bridge.Approval`, each under the row's lock, along AD-11's one path.
- `Answer` records the first answer and completes the hold's Workflow task as `OcuTalonWorkflow`; every later answer gets `already_answered` with the winner.
- The hold acts only on what the row shows: on the timer it expires the row, and it sends `ApprovalOutcome` to the row's `ResultTarget` on approval (fix only), rejection or expiry.
- Each state change reports its HostSink event from the job that made it (AD-31).

## Boundaries & Constraints

**Always:**
- **New constant** `TASKSECONDS = 5`: how long `Answer` and `Cancel` wait for the hold's Workflow task to exist (the Workflow operation creates it asynchronously after the hold sends it). The five state methods take `LOCK +^OcuTalon.Bridge.Approval(<Ref>)` with a wait of `LOCKSECONDS + TASKSECONDS`, the longest any of them holds it. Raise keeps its `LOCKSECONDS`.
- **The hold's task** is the newest open task (`TaskStatus_IsComplete = 0`, highest ID) whose `%Subject` is `TASKSUBJECT` plus the Ref. Completing it means `AssignTask(WORKFLOWUSER)`, then `CompleteTask(<action>)`: `Approve` or `Reject` for an answer, and no action for a cancel (Workflow status `Cancelled`). One private helper does this for `Answer` and `Cancel`, polling up to `TASKSECONDS`. A task that does not appear, or fails to complete, is logged as a warning that names the Ref. The row's change stands.
- **`Answer(ref, action, channel, irisUser, sessionRef, Output winner, sinkClass = "")`** returns one of `done`, `already_answered`, `expired`, `not_found` and `not_allowed`. The Epic 0 arguments keep their names and order. `winner` is `{}` except for `already_answered`. Under the lock, it checks in this order:
  1. No row with the Ref, or a `cancelled` row: `not_found`.
  2. `action` is not `approve` or `reject`, or `channel` is not one of `Msg.Enum` `CHANNEL`, or `irisUser` does not hold the row's `RequiredRole`: `not_allowed`. "Holds" means the role is in `$SYSTEM.Security.GetUserRecursedRoleSet(irisUser)`. An error from that call, or an empty `RequiredRole`, holds nobody.
  3. An `expired` row: `expired`. An `approved`, `rejected`, `executing`, `done` or `failed` row: `already_answered`, with `winner` `{"action","channel","at"}` taken from `AnsweredAction`, `AnsweredChannel` and `AnsweredAt`.
  4. A `pending` row whose `ExpiresAt` is now or past (`Time.SecondsUntil` 0 or less, or unreadable): the row becomes `expired` with no answer fields, and the result is `expired`.
  5. Otherwise it sets `AnsweredAction` (the action as given), `AnsweredChannel`, `AnsweredBy` (`irisUser`), `AnsweredAt` (`Time.NowUtc()`) and `State` `approved` or `rejected`, and saves. Then it completes the hold's task with `Approve` or `Reject`, and returns `done`.
  - A lock that is not taken, or a save that fails, records nothing, logs a warning that names the Ref, and returns `not_found`.
  - `sessionRef` is accepted for Story 3.7's audit entry and is not stored (no column holds it).
- **`Expire(ref, sinkClass = "")`**: under the lock, a `pending` row becomes `expired`. A missing row, or a row in any other state, is an error that names the Ref and the state. It never compares the clock (DW-186). Its callers decide that the time is up: the hold's timer, which is set from `ExpiresAt` in whole seconds rounded down, and `Answer`'s step 4.
- **`Cancel(ref, sinkClass = "")`**: under the lock, a `pending` row becomes `cancelled`, and then the hold's task is completed with no action, so the hold ends. Any other state is an error that names it. A cancelled request never gets an `ApprovalOutcome` (AD-15).
- **`StartExecution(ref)`**: under the lock, an `approved` row whose `ExpiresAt` is still ahead (`SecondsUntil` above 0) becomes `executing`. The check and the change happen together. A row past its expiry stays `approved` and gets an error that says so. Any other state is an error that names it.
- **`FinishExecution(ref, result, sinkClass = "")`**:
  - `result` must be `done`, `failed` or `interrupted`; any other value is an error that names it, and nothing is locked.
  - Under the lock, an `executing` row becomes `done` (result `done`) or `failed` (`failed`, `interrupted`). An `approved` row whose run could not start becomes `failed`, but only with result `failed`.
  - It sets `Result` to the given result and `FinishedAt` to now. Every other case is an error that names the state and the result.
- **A missing row** is an error that names the Ref, for `Expire`, `Cancel`, `StartExecution` and `FinishExecution` alike. **A refusal changes no field and fires no event.**
- **Events (AD-31).** Each event fires after the unlock, through `Decide.FireEvent`, from the job that made the change. It carries the row's `OwnerRef` and `HostSink.RefPayload(ref)`, and its sink is `sinkClass`, else `Accessor.ValueFor("HostSinkClass")`.
  - `Answer` fires `approval.answered` for `done`, and `approval.expired` when its step 4 expired the row.
  - `Expire` fires `approval.expired`. When the hold's timer calls it, that job is the hold's.
  - `Cancel` fires `approval.cancelled`, and `FinishExecution` fires `approval.result`.
  - `StartExecution` fires nothing, because AD-31 has no event type for `executing`.
- **`Approval.HoldResponse(hold, response, completionKey)`**:
  1. For key `expiry`, it first calls `Expire(hold.Ref)`. That method refuses a row that is no longer pending, which is expected here; any other failure is logged as a warning.
  2. It reads the row. With no row, it does nothing.
  3. For key `task`, the outcome is `approved` when the TaskResponse's `%Action` is `Approve` and the row is `approved`, and `rejected` when the action is `Reject` and the row is `rejected`. Anything else gives no outcome, so a task completed outside `Answer`, or cancelled by `Cancel`, sends nothing.
  4. For key `expiry`, the outcome is the row's state when that is `expired`, `approved` or `rejected`. So an answer whose task `Answer` could not complete is delivered at the latest when the timer fires.
  5. An `approved` `tool_call` sends nothing: that is Story 30.3's replay, and until then the call runs nothing. Any other outcome, when the row has a `ResultTarget`, is sent with `hold.SendRequestAsync(ResultTarget, <ApprovalOutcome>, 0)`. An empty `ResultTarget` sends nothing.
  6. A failed send is logged as an error that names the Ref and the target, and the method still returns OK, so the hold ends. It fires no event.
- **`OcuTalon.Bridge.Msg.ApprovalOutcome`** (new, `Ens.Request`, Lane A): `ApprovalRef` (`%String(MAXLEN = 22)`), `IncidentRef` (`%String(MAXLEN = 22)`) and `Outcome` (`%String(MAXLEN = 32)`, one of `approved`, `rejected` or `expired`). It has the compiler's committed storage block.
- `Approval` and the message make no `%AI` call and run no Python (AD-6), and they name no other OcuTalon package (AD-2).
- **Tests run on throwaway stacks only, through `ci/iris.sh`.**
  - Each test tracks every Ref it raises or saves under `^OcuTalonTest("Approval","refs")`, and every lock it holds and job it starts.
  - Cleanup ends them, also after a failed earlier run, and enables `OcuTalonApprovals` again with `ApprovalStartIn` and `ApprovalHold`.
  - It restores Decide's `HostSinkClass` and the `ApprovalRole` row, and creates no IRIS user or role.
  - A test that expects an `ApprovalOutcome` waits, on a deadline, until the target has handled it. The stub `IncidentManager` logs one error per outcome, so no late error lands in another test's window.

**Never:**
- No change to `Raise`, `Hold`, `StartHold`, `LiveHold`, `Reconcile`, or `ApprovalHold`'s properties and methods. Only `ApprovalHold`'s class comment changes. No new `ApprovalRequest` column (AD-33, `Test/Data/**` is contended).
- No audit entry (Story 3.7), no call from the gate (Story 3.6), and no replay or `tool` request (Story 30.3).
- No new HostSink event type, and no `Answer` result outside the five.
- No edit to `src/ocutalon/cls/OcuTalon/Test/Agent/**` (reuse `RunnerFixture` as it is), to `Production.cls`, or to a contended path (`Core/**`, `Channel/**`, `Watch/**` is Epic 5's, `Web/**`, `Live/**`, `Test/{Core,Web,Data,Live,Schedule}/**`, `docker/**`, `docs/**`, `web/**`, `.github/**`, `BridgeExample/**`).
- No test run, Workflow change or setting change on `ocutalon-slot-a`. No absolute local path in a tracked file. No sleep race: concurrency goes through a held lock.

## I/O & Edge-Case Matrix

Terms used in the table:
- **Rows:** a tool_call row and a fix row are as in Story 3.4 (`NewRow`; the fix row's `ResultTarget` is `IncidentManager`). A **targeted tool_call row** also has `ResultTarget` `IncidentManager`.
- **The answerer** is the README account `ocutalon` (`Install.Step.Users` `USER`). On a flag-off throwaway it holds `OcuTalonUser` (measured).
- **The sink:** `ProbeSink` passed as `sinkClass`. **The shared sink** is ProbeSink's shared mode, with Decide's `HostSinkClass` set to ProbeSink (`RunnerFixture.UseItemSetting`), for events fired in the hold's job.
- **The outcome:** an `ApprovalOutcome` header from `ApprovalHold` to the row's `ResultTarget`, in the hold's session with SuperSession `TraceRef`. Its body has `ApprovalRef` = the Ref, the row's `IncidentRef`, and `Outcome`.
- **The gate:** the test holds `LOCK +^OcuTalon.Bridge.Approval(Ref)` and starts two jobs. It releases the lock once `%SYS.LockQuery:Detail` lists both jobs as waiters (measured).
- **A fixture row:** a row the test saves directly in a given state, with no hold and no task. `RequiredRole` is `OcuTalonUser` and `ExpiresAt` is 1 h ahead unless the row says otherwise. An answered state has its `Answered*` fields set.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Approve a fix | Raised fix row, task open; `Answer(ref,"approve","web",<answerer>,<new Ref>,.winner,<sink>)` | `done`, `winner` `{}`. <br>The row is `approved`, with `AnsweredAction` `approve`, `AnsweredChannel` `web`, `AnsweredBy` the answerer, and `AnsweredAt` within 5 s of now. <br>The task is complete with `%Action` `Approve` and `%UserName` `OcuTalonWorkflow`, and has no worklist item. <br>The sink got exactly one call: `approval.answered`, with the OwnerRef, `{"ref"}` and the row's State `approved`. <br>The hold ends, and exactly one outcome `approved` is sent. | -- |
| 2 | Reject | (a) A raised fix row; (b) a raised tool_call row with no `ResultTarget`. Each is answered `reject`. | (a) `done`, the row is `rejected`, and one outcome `rejected` is sent. (b) `done`, the row is `rejected`, the hold ends, and no outcome is sent. | -- |
| 3 | Approved tool call | Raised targeted tool_call rows: the first approved, the second rejected | First: `done`, `approved`, and the hold ends. Besides its TaskRequest and AlarmRequest, the hold sent no request: no outcome and nothing to `Decide`. Second: one outcome `rejected`. | -- |
| 4 | Two answers at once | Raised fix row, task open; the shared sink. Through the gate, job A answers `approve`/`web` and job B answers `reject`/`telegram`. | Exactly one job gets `done`. The other gets `already_answered`, with `winner` equal to the row's action, channel and `AnsweredAt`. The row's state matches the winner. The task was completed once, with the winner's action. Exactly one `approval.answered` is recorded, and exactly one outcome, the winner's, is sent. | -- |
| 5 | Refused answers | Raised fix row, task open: <br>(a) an unknown Ref; <br>(b) irisUser `OcuTalonWorkflow` (no roles), `""`, or `ZzNoSuchUser<n>`; <br>(c) action `maybe`, or channel `fax`; <br>(d) a request raised with the `ApprovalRole` setting `ZzApprover<n>`, answered by the answerer | (a) `not_found`; (b) to (d) `not_allowed`. Each gives `winner` `{}`. The row is unchanged and pending, the task is still open, and the sink got no call. | -- |
| 6 | Timer expires | Fix row raised and aged (`ExpiresAt` 1 minute ago), its hold deleted, the shared sink, then `Install.Step.Reconcile.Run()` | Within 15 s the row is `expired` with no answer fields. Exactly one outcome `expired` is sent from the new hold's session. The shared sink has exactly one `approval.expired`, with the OwnerRef and `{"ref"}`. The hold has ended and no task is open. A later `Answer` returns `expired`. | -- |
| 7 | Answer past expiry, timer not fired | Raised fix row (its live hold's timer is about 24 h away), then aged to `ExpiresAt` 1 minute ago; `Answer` approve | `expired`, `winner` `{}`. The row is `expired` with no answer fields. The sink got one call, `approval.expired`, with State `expired`. The task is still open and no outcome has been sent yet. A second `Answer` gives `expired` again, with no new call. `StartExecution` and `Cancel` are refused. | -- |
| 8 | DW-186: expiry needs no clock | Raised fix row with `ExpiresAt` still 30 s ahead; `Expire(ref,<sink>)` | OK. The row is `expired`, and the sink got one `approval.expired` with State `expired`. A second `Expire` is an error that names `expired`. | Expire never compares the clock. |
| 9 | Cancel | Raised fix row, task open; `Cancel(ref,<sink>)` | OK. The row is `cancelled` with no answer fields. The task is complete with `%Status` `Cancelled` and has no worklist item. The hold ends and no outcome is sent. The sink got one `approval.cancelled`, with State `cancelled`. A later `Answer` gives `not_found`, and a second `Cancel` is an error that names `cancelled`. | -- |
| 10 | Every other transition refused | Fixture rows in each of the 8 states, and an `approved` row past its expiry; each call alone: `Answer` approve and reject, `Expire`, `Cancel`, `StartExecution`, and `FinishExecution` done, failed, interrupted and `x` | Allowed changes: <br>- `Expire` on a pending row gives `expired`, with event `approval.expired`; <br>- `StartExecution` on an unexpired approved row gives `executing`, with no event; <br>- `FinishExecution` on an executing row gives `done` (result done) or `failed` (failed or interrupted), and on an approved row with result failed gives `failed`; each sets `Result` and `FinishedAt` and fires `approval.result`. <br>`Answer` gives `already_answered` on approved, rejected, executing, done and failed rows; `expired` on an expired row; and `not_found` on a cancelled row. <br>Every other pair is an error that names the Ref and the state. On every refusal, all of the row's columns are unchanged and the sink got no call. | -- |
| 11 | Start at once | An approved fixture row; through the gate, two jobs call `StartExecution` | Exactly one returns OK. The other returns an error that names `executing`. The row is `executing`. | -- |
| 12 | Re-armed request | Fix row raised and aged (`ExpiresAt` 1 h ahead), its hold deleted, `Reconcile` run, then `Answer` approve | `done`. The new task is completed and the discarded one is untouched. The new hold ends, and one outcome `approved` is sent from its session, which differs from the first session. | -- |
| 13 | Answer before the task exists | `OcuTalonApprovals` disabled, then the fix row raised (no task exists). A job calls `Answer` approve. Once the row shows `approved`, the test enables `OcuTalonApprovals` again. | The job gets `done`. The task appears and is completed with `Approve` by `OcuTalonWorkflow`. The hold ends, and one outcome `approved` is sent. | -- |
| 14 | Hold acts only on the row | Raised fix row; its task completed directly with `Approve` (row still pending) | The hold ends. No outcome is sent, and the row is still `pending` with no answer fields. | -- |
| 15 | Timer delivers an undelivered answer | Fix row raised, aged (`ExpiresAt` 1 minute ago), its hold deleted. The test holds the row's lock while `Reconcile` re-arms it (a 1 s timer), writes the answer on the row as `Answer` would (approved, web, the answerer, now) without completing the task, then releases. | Within 15 s the hold has ended and one outcome `approved` is sent. The row is still `approved`. `StartExecution` is refused for being past its expiry, and the row stays `approved`. | -- |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` -- the API to build.
  - Parameters (:14-36): add `TASKSECONDS`.
  - Patterns to reuse: Raise (:54-75) is the lock-then-event pattern (`LOCK +...:<seconds>`, `$Test`, `Try`, unlock, `Decide.FireEvent` after it, with the sink from `sinkClass` or `ValueFor("HostSinkClass")`). `Hold` (:225-244) sends with `hold.SendRequestAsync`. `Reconcile` (:282) holds the task SQL (`EnsLib_Workflow.TaskResponse`, `TaskStatus_IsComplete`), and `%Subject` is usable in SQL (3.4's Task 0).
  - The stubs to replace: `Answer` (:184-192), `Expire` (:194), `Cancel` (:200), `StartExecution` (:206) and `FinishExecution` (:213). `HoldResponse` (:246-251) is a no-op today.
  - The class comment (:1-10) still says Story 3.6 builds the execution methods; it changes.
- `src/bridge/cls/OcuTalon/Bridge/Process/ApprovalHold.cls` -- `OnResponse` (:15-18) passes `callresponse` and the key to `HoldResponse`. The class comment (:1-3) changes, nothing else. `Test.Bridge.Approval` `TestHoldIsFrozen` pins it.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` -- read only. The answer columns are at :50-60, `Result` at :63, `FinishedAt` at :66 and `RefIndex` at :68.
- `src/bridge/cls/OcuTalon/Bridge/Msg/ApprovalStart.cls` -- the shape of `Msg/ApprovalOutcome.cls` (new). `Msg/Enum.cls` has `APPROVALSTATE` (:18) and `CHANNEL` (:24).
- `src/bridge/cls/OcuTalon/Bridge/Ext/HostSink.cls` -- the event parameters (:18-26) and `RefPayload` (:41). `Process/Decide.cls:927` has `FireEvent`. `Time.cls` has `NowUtc` (:18) and `SecondsUntil` (:105), whole seconds rounded down and negative in the past.
- IRIS (`irislib/`), read only:
  - `EnsLib/Workflow/Engine.cls`: `CompleteTask` (:199-245) with no action sets `%Action` and `%Status` to `Cancelled` and still sends the deferred response to the hold. `%CancelRequest` (:735-784) sends none.
  - `EnsLib/Workflow/TaskResponse.cls`: the instance methods `AssignTask` (:195) and `CompleteTask` (:240).
  - `Ens/BusinessProcess.cls`: `SendRequestAsync` (:160). On a timer (:360-420) the framework calls `OnTimeout`, runs the controlled requests' `%OnTimeout` (`TaskRequest.%OnTimeout` cancels the task, `EnsLib/Workflow/TaskRequest.cls:61`), then `OnResponse` with key `expiry`. After a TaskResponse, a timer that is all that is left is cleared.
  - `%SYSTEM/Security.cls:327`: `GetUserRecursedRoleSet`. Reading another user than `$USERNAME` needs `%Admin_Secure:USE`.
  - `%SYS/LockQuery.cls:777`: the `Detail` query, with `WaiterPID`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Approval.cls` -- extend it.
  - The class comment (:1-38) changes.
  - Setup and teardown: `OnBeforeOneTest` and `OnAfterOneTest` (:72-97).
  - Raising and tracking: `NewRow` (:692), `Raise` (:710) and `AssertSink` (:774).
  - Reading the hold: `HoldMessages` (:799), `TaskIds` (:840), `WaitTask` (:864), `WaitHoldGone` (:876), `WorklistUsers` (:895), `TaskState` (:1039) and `StartsSince` (:998).
  - Changing state: `Complete` (:906) completes a task directly, `Age` (:968) and `Settle` (:1030).
  - The job pattern: `HoldLockInJob` (:660) and `TestLockHeld` (:345).
  - Cleanup: `Clean` (:1087) enables the items, releases lock jobs and removes refs; `Remove` (:1114).
  - `TestReconcilePastExpiry` (:507) now also sees the row expire.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` -- reuse it, without editing it:
  - `ReadyReason` (:306) and `HeaderMark` (:437);
  - `UseItemSetting` and `RestoreItemSetting` (:617-634), as `Test.Bridge.Gate:526` uses them for Decide's `HostSinkClass`;
  - `SinkCalls` (:781) reads the shared sink.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeSink.cls:18-34` -- each call's `$ListBuild` gains an eighth element.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls:17-27` -- `TestApprovalStubs` goes. The class comment is at :1-11.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Contracts.cls` -- the oracle `XData Contracts` (:94; the `ApprovalStart` entry is at :192) and the class comment (:1-4).
- Read only:
  - `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls:307-312` -- the signature oracle matches each signature by prefix (:155-159), so trailing optional arguments keep it green (lane-b).
  - `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls:21,27` -- the README account and its roles.
  - `src/ocutalon/cls/OcuTalon/Production.cls:37` and `Watch/IncidentManager.cls` -- `IncidentManager` is Epic 5's stub business process, which answers `NotImplemented`.

## Tasks & Acceptance

**Execution:**
- [ ] `src/bridge/cls/OcuTalon/Bridge/Msg/ApprovalOutcome.cls` (new) -- the message as in Boundaries. Commit the compiler's storage block, compiled on slot A with `iris_doc_load` (`server: ocutalon-slot-a`, `namespace: OCUTALON`). Why: AC 5, AD-11, AD-5.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Approval.cls`:
  - add `TASKSECONDS`, the five state methods, `HoldResponse`, and the private helpers: one state change under the lock, the hold's task completion and the outcome send;
  - rewrite the class comment and each method's comment as contracts.
  - Why: AC 1 to 5, DW-186.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Process/ApprovalHold.cls` -- the class comment only: the hold answers, expires and delivers through `Approval`. Why: Rule 14.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeSink.cls` -- add an eighth element to each call: the `State` of the `ApprovalRequest` with the payload's ref at the moment of the call ("" when none). Update the comment. Why: the events fire after the change (AC 1, 3, 4).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Approval.cls`:
  - the tests, one per matrix row: `TestAnswerApprovesAFix` (1), `TestAnswerRejects` (2), `TestApprovedToolCallRunsNothing` (3), `TestTwoAnswersAtOnce` (4), `TestAnswerRefusals` (5), `TestTimerExpires` (6), `TestAnswerPastExpiry` (7), `TestExpireDoesNotWaitForTheClock` (8, DW-186), `TestCancel` (9), `TestEveryOtherTransitionIsRefused` (10), `TestStartExecutionAtOnce` (11), `TestAnswerReArmed` (12), `TestAnswerBeforeTheTaskExists` (13), `TestHoldActsOnlyOnTheRowsAnswer` (14) and `TestTimerDeliversAnUndeliveredAnswer` (15);
  - the helpers:
    - the answerer, asserted to hold `OcuTalonUser` first;
    - a fixture row, and a text of all its columns;
    - the outcomes of a Ref, and the wait until the target has handled them;
    - the requests the hold sent in its session;
    - one job body that calls `Answer` or `StartExecution` and records its result, `winner` and `done` under `^OcuTalonTest("Approval","job",<n>)`;
    - the gate wait on `%SYS.LockQuery:Detail`;
  - `Clean`:
    - also enables `OcuTalonApprovals`;
    - waits for every job's `done`;
    - releases any row lock the test process holds (tracked under `^OcuTalonTest("Approval","held")`);
    - kills `^OcuTalonTest("ProbeSink")`.
  - `OnAfterOneTest` restores Decide's `HostSinkClass` when a test swapped it.
  - `TestReconcilePastExpiry` also asserts the row is `expired`.
  - The class comment names what each test pins.
  - Why: rows 1 to 15, Rule 19.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls` -- delete `TestApprovalStubs` and rewrite the class comment: no Approval stub is left. `src/ocutalon/cls/OcuTalon/Test/Bridge/Contracts.cls` -- the oracle gains `OcuTalon.Bridge.Msg.ApprovalOutcome` (`super` `Ens.Request`, the three properties), and the class comment changes. Why: shared surfaces.

**Acceptance Criteria:**
- Given a pending request held in Workflow, when `OcuTalon.Bridge.Approval.Answer(Ref, Action, Channel, IrisUser, SessionRef)` is called by an IRIS user who holds the row's required role, then:
  - under `LOCK ^OcuTalon.Bridge.Approval(Ref)` it records the action, the channel, the IRIS user and the time on the row;
  - it assigns and completes the Workflow task as `OcuTalonWorkflow`, also for a re-armed request and for an answer that arrives before the task exists;
  - it returns `done` synchronously;
  - `HostSinkClass` receives `approval.answered` with the `Ref` once, after the change.
  - Rows 1, 12 and 13 hold (FR-8, AD-11, AD-31).
- Given two answers from different channels at the same moment, when both reach `Answer`, then exactly one returns `done` and the other `already_answered` with the winning action, channel and time. An unknown `Ref` returns `not_found`, and an IRIS user without the row's required role gets `not_allowed`. Rows 4 and 5 hold (FR-8, AD-11, UX-DR75, UX-DR76).
- Given a request past its expiry time, when its timer fires or an answer arrives before the timer has fired, then:
  - the row becomes `expired` and the answer gets `expired`;
  - the request can no longer be approved or started;
  - the expiry does not depend on the clock being past `ExpiresAt` when the timer fires (DW-186).
  - Rows 6 to 8 hold (FR-8, AD-11, UX-DR76, UX-DR153).
- Given an approval row, when anything changes its state, then:
  - it changes only through `Answer`, `Expire`, `Cancel`, `StartExecution` and `FinishExecution`, each under the lock, along `pending` to `approved`, `rejected`, `expired` or `cancelled`, `approved` to `executing` to `done` or `failed`, and `approved` to `failed`;
  - `StartExecution` succeeds only on an approved, unexpired row that is not already executing, checked and set atomically;
  - every other transition is refused and changes nothing;
  - `Cancel` moves a pending request to `cancelled` and ends its hold.
  - Rows 9 to 11 hold (AD-11, AD-16, AD-4).
- Given a `TaskResponse` or the expiry timer reaches `ApprovalHold`, when it handles the response, then:
  - it acts only if the row already shows that answer (or, on the timer, the row's own answer or expiry);
  - on approval of a fix, on rejection and on expiry it sends `ApprovalOutcome` to the row's `ResultTarget`;
  - an approved `tool_call` gets neither an outcome nor a replay and runs nothing, and a rejection runs nothing;
  - `HostSinkClass` receives `approval.answered`, `approval.expired` or `approval.cancelled` with the `Ref`, from the job that changed the row.
  - Rows 1 to 3, 6, 9, 14 and 15 hold (FR-8, NFR-13, AD-11, AD-31).
- Given `ApprovalHold` and the new message, when `Test.Bridge.Approval` `TestHoldIsFrozen`, `bash ci/checks.sh` (storage) and `live storage-roundtrip` run, then the hold still stores exactly `Ref` with one-line methods, and `Msg.ApprovalOutcome` has its committed compiler block (AD-5).
- Given the fresh `shard lane-a`, `shard lane-b`, `live production-restart`, `live storage-roundtrip` and `live demo-path`, when they run, then every class and unit passes.

## Spec Change Log

- 2026-10-25, lead spec gate: AD-11 and AD-31 are not amended. The plan's Rule 20 points went into the spine as planned: the Consistency Conventions row "Approval requests" now records the events and where they fire, `Answer`'s order, results and winner, the lock-timeout and cancelled-row `not_found`, `Expire` never comparing the clock, `StartExecution`'s expiry check and the hold's delivery rules; the Structural Seed's cross-area table lists `OcuTalon.Bridge.Msg.ApprovalOutcome`. Ruled in the veto window: the new stored message class `ApprovalOutcome`, and `not_found` for an `Answer` whose lock cannot be taken (AD-11's five results have no "busy"; it records nothing, so a retry is safe). Both kept as planned. The Cross-epic line now names the `AnswersIn` constraint for Lane B.

## Review Triage Log

### 2026-10-24 — Review pass
- verdicts: 30 findings — high 0, medium 7, low 19, false 4, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind Hunter: an exception in `CompleteHoldTask` after the save makes `Answer` return `not_found` with no event — the SQL and the poll loop sat outside the Try; fixed: the whole body is inside Try/Catch and logs a warning, so the saved answer stands.
  - `[low]` `[reject]` Blind Hunter: `Answer` and `Cancel` hold the row lock while polling for the task — the spec's design (`LOCKSECONDS + TASKSECONDS` in Boundaries); the wait is long only when the task is absent.
  - `[medium]` `[defer]` Blind Hunter: a task completed outside `Answer` leaves a pending row with no hold, no timer and no outcome until the next Reconcile — real, but Story 3.4's hold ended the same way and matrix row 14 pins that no outcome follows; in the spec's `deferred:` list.
  - `[false]` `[reject]` Blind Hunter: the timer fallback misses a row that has left `approved` — checked: only `FixExecutor` (Stories 7.3 to 7.5) moves an approved row on, it starts from the outcome this handling sends, and `StartExecution` refuses a row past its expiry, which is when the fallback fires.
  - `[low]` `[reject]` Blind Hunter: `HoldsRole` returns 0 without a log when the privilege is missing — the spec says an error holds nobody and records the privilege in its Cross-epic note; a warning would log for every unknown user, and the fix adds a branch.
  - `[low]` `[reject]` Blind Hunter: `WaitOutcomes` counts an Error header as handled — the stub `IncidentManager` answers `NotImplemented` (spec), so Error is the expected status until Story 5.5.
  - `[low]` `[reject]` Blind Hunter: no tests for the lock not taken, a failing save, an absent task, an inherited role or an empty `ResultTarget` on a fix — logged defensive branches; each wait test adds 5 to 7 s to a 500 s shard line, and a role set that includes an inherited role is the call the implementation makes; the fix is more than a direct correction.
  - `[low]` `[reject]` Blind Hunter: `TestAnswerBeforeTheTaskExists` depends on the task appearing within 5 s — measured at planning: 0.03 s after the item is enabled.
  - `[low]` `[reject]` Blind Hunter: `HoldTask` filters on `%Subject` with no index — the query repeats only while the task is absent, the table holds approval tasks, and `Reconcile` (Story 3.4) runs the same SQL.
  - `[low]` `[reject]` Blind Hunter: `ApprovalOutcome.Outcome` has no `VALUELIST` — the spec fixes `%String(MAXLEN = 32)` and the oracle pins that type; `HoldResponse` is the only writer.
  - `[low]` `[reject]` Blind Hunter: `Move` has nine positional arguments — developer-only; each of its five calls is pinned by a test that goes red on a wrong slot (the recorded mutations); a refactor is more than a direct correction.
  - `[low]` `[patch]` Edge Case Hunter: same cause as the first Blind finding (`AnswerLocked` after `CompleteHoldTask` throws): fixed with it.
  - `[low]` `[patch]` Edge Case Hunter: same cause (`Move` for `Cancel` returns an error after the row became `cancelled`, with no event): fixed with it.
  - `[false]` `[reject]` Edge Case Hunter: a row that moves past `approved` before the hold handles the task response — same refutation as the fourth Blind finding.
  - `[medium]` `[defer]` Edge Case Hunter: the timer's `Expire` can fail on the lock timeout or a save while the row is pending, then the hold ends with no timer — grouped with the third Blind finding; in the `deferred:` list.
  - `[medium]` `[defer]` Edge Case Hunter: a task completed outside `Answer` while the row is pending clears the timer (row 14 asserts this) — same entry as the third Blind finding.
  - `[medium]` `[defer]` Edge Case Hunter: a past-expiry `Answer` on a row whose hold is already gone sends no `expired` outcome — same entry; a hold is gone while its row is pending only in the cases above.
  - `[low]` `[reject]` Edge Case Hunter: `HoldsRole` hides a privilege failure — same as the fifth Blind finding.
  - `[low]` `[reject]` Edge Case Hunter: `HoldTask` ignores a failing SQL status — an SQL error on a system table is not reachable; the outcome would be the same warning after the poll; the fix adds a branch.
  - `[medium]` `[patch]` Verification Gap: the time assertions pass on an empty `AnsweredAt` or `FinishedAt` — fixed: `JustNow` checks the format first, and `TestTwoAnswersAtOnce` checks the winner's time; the mutations 'no `AnsweredAt`' and 'no `FinishedAt`' are red.
  - `[medium]` `[patch]` Verification Gap: 'StartExecution fires no event' could not fail, because the test used the real sink — fixed: `TestEveryOtherTransitionIsRefused` sets Decide's `HostSinkClass` to ProbeSink; the mutation 'StartExecution passes an event' is red.
  - `[low]` `[reject]` Verification Gap: nothing pins that the event fires after the unlock — AD-31 requires it after the change, which `AssertEvent` pins (state and transaction level); a lock probe needs a ProbeSink element beyond the spec, and no consumer calls back into the approval locks.
  - `[medium]` `[patch]` Verification Gap: the negative 'no outcome is sent' checks read after `WaitHoldGone`, while the hold's `OnResponse` can still run — fixed: `WaitHoldSettled` waits until every message to the hold in its session is past delivered, and the four tests call it first.
  - `[low]` `[reject]` Verification Gap: failure paths of `Answer`, `HoldResponse` and `CompleteHoldTask` have no test — same entry as the seventh Blind finding.
  - `[low]` `[patch]` Verification Gap: AC 6's storage clause and AC 7 have no `mutation:` line — closed in-pass: a property added to `Msg.ApprovalOutcome` without its Storage block turns `live storage-roundtrip` red (line written); AC 7 is an aggregate of shard runs, not a test.
  - `[low]` `[reject]` Verification Gap: `TestAnswerBeforeTheTaskExists` can fail on a loaded runner — same entry as the eighth Blind finding.
  - `[low]` `[reject]` Verification Gap: that test fires an event at the real sink and asserts nothing about it — the test pins the task, the hold and the outcome; rows 1 and 4 pin the event.
  - `[low]` `[reject]` Verification Gap: the shared-sink counts could take calls from other jobs — `Clean` leaves no pending rows and `Reconcile` runs only where a test calls it; the class passed on a warm and a fresh stack.
  - `[false]` `[reject]` Verification Gap: `TestTimerExpires` checks the event count and not the job — only the hold calls `Expire` on the timer, so one event with the row's state is the hold's; no other path can produce it in that test.
  - `[false]` `[reject]` Intent Alignment Auditor: a descriptive report with no defect; its divergences are the spec's own seams (`sinkClass`, the lock gate, a fixture row for row 15) and choices (`approval.result` from `FinishExecution`, `interrupted`), all in the spec's Boundaries and Design Notes.

## Design Notes

**Architecture decisions:**
- **AD-11:** the five state methods, the one path, the lock, `Answer`'s results, and the hold that acts only on what the row shows. Prevents: two answers acting, approval state beside Workflow, and the inbox as a second way to answer.
- **AD-31:** each event fires after the unlock, from the job that made the change, through `FireEvent`.
- **AD-16:** `StartExecution` checks and sets atomically, and `FinishExecution` handles `interrupted` and the approved run that could not start.
- **AD-15:** a cancelled request sends no `ApprovalOutcome`.
- **AD-4:** `Cancel` is the call that `SessionOps.End` makes.
- **AD-5:** `ApprovalHold` stays frozen, with its logic in `Approval`, and the new message is append-only with a committed block.
- **AD-26:** the outcome goes in the hold's session with the `TraceRef` tag.
- **AD-6:** no `%AI` call. **AD-2:** the bridge names no OcuTalon package. **AD-22:** tests run on throwaways. **AD-29 and AD-33:** these files are Lane A's.
- **AC 5 and AD-31.** AC 5 lists the HostSink events in the hold's step. AD-31's Rule says each event fires "after commit, in the job that changed state". The reading that keeps both is the one planned here. The hold fires `approval.expired` itself when its timer expires the row, because that job changed it. `Answer` and `Cancel` fire theirs in their callers' jobs, so the HostSink has the event by the time the hold handles the response. No AC contradicts an AD's Rule.

**Measured at planning** (warm throwaway `e3s5pw`, build 154, `iris session` as `irisowner`; torn down afterwards):
- `GetUserRecursedRoleSet("ocutalon")` gives `OcuTalonAdmin,OcuTalonTraceViewer,OcuTalonUser`.
  - For `OcuTalonWorkflow` it gives OK with no role.
  - For `ZzNoSuchUser` it gives error #838 ("does not exist"), and for `""` error #5813.
- With `OcuTalonApprovals` disabled (the call took 0.06 s), Raise of a fix row returned OK in 0.04 s.
  - The TaskRequest header waited `Queued` (status 2), and after 2 s no task existed.
  - `EnableConfigItem(...,1)` took 0.01 s, and the open task appeared 0.03 s later.
- `AssignTask("OcuTalonWorkflow")` then `CompleteTask("")` left the task with `%Action` and `%Status` `Cancelled` and `%UserName` `OcuTalonWorkflow`.
  - Its TaskResponse reached `ApprovalHold` (header completed), and the hold ended in 0.05 s.
  - The row stayed pending under 3.4's no-op handler.
- While the probe process held `^OcuTalon.Bridge.Approval("zzprobe")`, a job waiting on the parent lock showed in `%SYS.LockQuery:Detail`: `LockString` was that node, `WaiterPID` the job and `WaiterMode` X. `%SYS.ProcessQuery` gave its `State` as `LOCKW`, the fallback for the gate.
- An `Ens.StringRequest` sent asynchronously with no response to the stub `IncidentManager` reached header status 8 (Error) in 0.03 s. The event log got one Type 2 row: `ErrBPTerminated ... Not implemented`.

**Decided in-stage** (small and reversible; inside AD-11, AD-31 and the ACs):
- **Answer records first, then completes the task.** The row is the truth: the first answer wins the moment it is saved.
  - The task is created asynchronously by the Workflow operation, after Raise and after a re-arm. So `Answer` waits up to `TASKSECONDS` for it.
  - If the task never comes, or fails to complete, the answer still stands (`done`, with a warning). The hold then delivers it when its timer fires (row 15).
  - A fix delivered that late is refused by `StartExecution`, because its row is past its expiry. FixExecutor then closes it as `failed` with a plain reason, so nobody is told "approved" for a fix that silently never runs.
- **One lock wait for the five methods**, `LOCKSECONDS + TASKSECONDS` (7 s): `Answer` and `Cancel` can hold the lock while they wait for a task. A lock that is still not taken means a stuck holder. The status methods return an error that names the lock. `Answer` records nothing and returns `not_found` with a warning, because its five results have no "busy", and adding one would amend AD-11.
- **A cancelled request answers `not_found`.** It was withdrawn (an MCP server removed, or a session ended), so a late press finds no request to answer. `already_answered` would need a winner it does not have.
- **`not_allowed` covers a malformed action or channel too.** It answers nothing, which fails closed. The role check reads the role set (`GetUserRecursedRoleSet`), because `OcuTalonUser` holds no resource that `CheckUserPermission` could test (`Install.Step.Users` `Grants`). `%All` is no shortcut. Story 26.4 replaces the check with approver-role resources.
- **The order is not found, not allowed, then state.** A user without the role learns nothing about who answered.
- **`Expire` never compares the clock** (DW-186). Its only callers are the hold's timer, set from `ExpiresAt`, and `Answer`'s own past-expiry step. Expiring early is the safe direction.
- **`StartExecution` reads "unexpired" as "now is before `ExpiresAt`".** "Approved" already excludes the state `expired`, so the AC's separate "unexpired" only has a meaning as the clock. This keeps a late-delivered approval from running by surprise.
- **`FinishExecution` fires `approval.result`** for done and failed (AD-11: "every change is ... reported through the HostSink"). `StartExecution` fires nothing, because AD-31's list has no type for `executing`. Story 30.3 then gets its `approval.result` from `FinishExecution`.
- **On an approved row, `FinishExecution` accepts only `failed`.** A run that never started can be neither done nor interrupted.
- **`Answer` past expiry leaves the task alone.** The hold's timer is due within about a second and sends the `expired` outcome itself. Cancelling the task would end the hold without that outcome.
- **The outcome carries `ApprovalRef`, `IncidentRef` and `Outcome`**, as `Fix.Msg.FixResult` carries both refs (AD-16). The receiver still reads everything else from the row.
- **The send is asynchronous with no response.** A failed send is logged as an error and the hold still ends: the row already holds the truth. An empty `ResultTarget` sends nothing. That applies to the gate's tool calls when Story 3.6 gives them none.
- **`sinkClass` is a trailing optional argument** of `Answer`, `Expire`, `Cancel` and `FinishExecution`, as on Raise. The contract oracle matches prefixes.
- **The newest open task of the Ref is the hold's task.** `Reconcile` discards orphans at every start.
- **Test hygiene:**
  - The tests answer as the README account, which is the local install's real approver, rather than creating a user.
  - Concurrency goes through a lock the test holds, released once `%SYS.LockQuery` shows both jobs waiting. The outcome assertions hold in any order, and the gate proves both answers were in flight at once.
  - `TestTimerDeliversAnUndeliveredAnswer` holds the row's lock, so the re-armed hold's `Expire` cannot run before the test has written the answer.

**Decided in-stage (implement):**
- No test keeps an `ApprovalRequest` object across a hold's change: a held object shows a stale `State` when the hold's job changes the row. `TestReconcilePastExpiry` drops its object and polls the state (`WaitState`).
- A hold counts as gone while its `OnResponse` still runs, so a test that needs the timer's change polls the row state; the outcome tests wait on the outcome itself.
- The gate (`WaitWaiters`) accepts a job as waiting when `%SYS.LockQuery:Detail` lists it or `%SYS.ProcessQuery` gives its `State` as `LOCKW`. In build 154 `Detail` listed no waiter row for an exact-node wait, so the `LOCKW` check carries it.
- `TestEveryOtherTransitionIsRefused` skips `Answer` and `Cancel` on a pending fixture row (it has no task, so each would wait the full `TASKSECONDS`); rows 1 and 9 pin those two.
- `FinishExecution(ref, "failed")` on an approved row ignores the clock: an approved row past its expiry still becomes `failed`.
- The state methods' error texts are the implementation's wording ("it is <state> and only <from> can become <to>", "past its expiry"); the tests match those phrases.

**For the lead (veto window; Rule 20, the plan does not write the spine):**
- **Stored data:** the new message class `OcuTalon.Bridge.Msg.ApprovalOutcome` (`ApprovalRef`, `IncidentRef`, `Outcome`). No `ApprovalRequest` column changes, and `ApprovalHold` is unchanged.
- **Privileges:** no grant changes.
  - `Answer` reads the answering user's role set, which needs `%Admin_Secure:USE` for another user than the job's own.
  - Production jobs meet that requirement. This is an inference from Story 3.2's DW-173 runner-job test, where `CheckUserPermission` has the same requirement.
  - A CSP job reads its own user's role set.
  - So Lane B's `AnswersIn` gets `not_allowed` if it calls `Answer` from a CSP job for a user other than `$USERNAME`.
- **Spine, Rule 20.** Consider extending the Consistency Conventions row "Approval requests" with:
  - where each event fires;
  - `Answer`'s order, its results and the winner shape, with `not_found` for a cancelled request and for a lock that is not taken;
  - `Expire` never comparing the clock;
  - `StartExecution` needing a row before its `ExpiresAt`;
  - the hold's delivery rules, the timer fallback included;
  - `ApprovalOutcome`'s fields.
  - Also add `OcuTalon.Bridge.Msg.ApprovalOutcome` (sent by `ApprovalHold` to `ResultTarget`; Lane A; Story 3.5) to the Structural Seed's cross-area table (AD-33).

**Cross-epic:** Epic 13's example production has no approval items and its agent has no tools; the bridge's public surface only gains trailing optional arguments and `Msg.ApprovalOutcome`. Lane B's `AnswersIn` (Epic 6): `Answer` reads the answering user's recursed role set, which a CSP job can do only for its own `$USERNAME`; called from a CSP job for another user it answers `not_allowed` (fail closed), so `AnswersIn` either passes the signed-in user or calls from a production job (inference from 3.2's DW-173 measurement).

**Rule 2 (extend, don't copy):**
- The state methods follow Raise's lock-then-event shape, and share one private state-change helper and one task helper. `Answer` past expiry and `Expire` use the same helper.
- `HoldResponse` uses `Hold`'s `SendRequestAsync`. `Msg.ApprovalOutcome` follows `Msg.ApprovalStart`.
- The tests extend `Test.Bridge.Approval`'s helpers (`NewRow`, `Raise`, `WaitTask`, `WaitHoldGone`, `Complete`, `Age`, `Settle`, `TaskIds`, `Clean`, `Remove`).
- The one job body follows `HoldLockInJob`. `ProbeSink` gains one element, and `RunnerFixture` is reused as it is.

**Integration ACs:**
- The Workflow operation `OcuTalonApprovals` and `ApprovalHold`, both real production items: `Answer`'s task completion reaches the hold, which reads the row and sends `ApprovalOutcome` to the real `ResultTarget` item `IncidentManager` (rows 1, 12 and 13).
- The host sink receives each event (rows 1 and 6 to 10).
- No consumer of the outcome's content or of the methods' results is built in this story. The first are Story 5.5 (`IncidentManager` on `ApprovalOutcome`) and Story 6.2 (`AnswersIn`).

**Consumed-by:**
- **Story 3.6:** the gate raises `tool_call` requests, and its NFR-13 tests use `Answer` and `Expire` to show that a rejected or expired request runs nothing. `Approval` joins `CodeRules`' `CALLBACKHELPERS`.
- **Story 3.7:** audits every change of the five methods, `Answer`'s `sessionRef` included.
- **Story 5.5:** `IncidentManager` handles `ApprovalOutcome`.
- **Story 6.2 and Story 12.7 (Lane B):** `AnswersIn` maps the five results and `winner`.
- **Stories 16.4 and 22.4:** `SessionOps.End` and `McpOps` call `Cancel`.
- **Stories 7.3 to 7.5:** `FixExecutor` calls `StartExecution` and `FinishExecution`.
- **Story 30.3:** the replay, through `StartExecution`, `FinishExecution` and `approval.result`.
- **Lane B's `BridgeSink` (Stories 2.6 and 2.8):** publishes the approval events.
- **Story 26.4:** replaces the role check.

**Consumes:**
- From Story 3.4: `Raise`, `Hold`, `StartHold`, `LiveHold`, `Reconcile` and the constants;
- `Ids`, `Time` and `Msg.Enum` (Epic 0);
- `Accessor.ValueFor` and `Decide.FireEvent` (Stories 0.6 and 1.3);
- `Install.Step.Reconcile` (Story 0.2);
- `RunnerFixture` and `ProbeSink` (Epic 1).

**Footprint:** every edit is in `src/bridge/**` (not `BridgeExample`) and `src/ocutalon/cls/OcuTalon/Test/Bridge/**`. No footprint extension, and no contended path is edited.

**Ledger inbox:** DW-186 is addressed by Boundaries ("`Expire` never compares the clock"), matrix row 8 and its pinning test.

**Shard time:** the fifteen tests add about 20 to 40 s to the fresh `lane-a` shard (inference). They are about thirteen raises with their holds, three Reconciles (two with a 1 s timer), one Decide setting swap and restore, one disable and enable of `OcuTalonApprovals` (0.01 s measured), four jobs, and the outcome waits (0.03 s measured). That puts the shard at about 420 to 440 s against 396 s after 3.4, under the 500 s line. No split.

## Verification

**Targets:**
- `ocutalon-slot-a` is for `iris_doc_load` compiles only (the storage block of `Msg.ApprovalOutcome`). Pass `server: ocutalon-slot-a` and `namespace: OCUTALON` on every MCP call, after `iris_server_info` shows build 154.
- Everything else runs through `ci/iris.sh` and `ci/warm.sh`. Never `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition`, slot B or slot C. No push, and never read `.env`.
- Run every command from the worktree root, in the foreground with `timeout: 600000`, one per call, with the lane-A variables on the line.
- The tags: fresh `e3s5i` and warm `e3s5iw` (implement); `e3s5q` and `e3s5qw` (QA); `e3s5r` and `e3s5rw` (review). Each stage puts its own tags and its own stage name in `OCUTALON_LOCK_OWNER`.

**Commands:**
- (loop) `bash ci/checks.sh` -- expected: every block passes, including `boundaries` (AD-2), `class-rules` and `storage`. About 20 s.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s5iw bash ci/warm.sh up` -- expected: a ready warm stack (about 60 s). Run it once at the stage's start.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_WARM=1 OCUTALON_RUN_TAG=e3s5iw bash ci/iris.sh class <Class>`, one call per class -- expected: `CLASS ... passed` after a `WARM reloaded` line. The classes:
  - `OcuTalon.Test.Bridge.Approval`, `OcuTalon.Test.Bridge.Api` and `OcuTalon.Test.Bridge.Contracts`;
  - `OcuTalon.Test.Bridge.Decide`, `OcuTalon.Test.Bridge.Budget` and `OcuTalon.Test.Bridge.Gate`, which read `ProbeSink`'s calls.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s5iw bash ci/warm.sh down` -- at the stage's end, and after a failure.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s5i bash ci/iris.sh shard lane-a` -- expected: every class passes, `Test.Bridge.Approval` included. About 420 to 440 s; run it alone in its call.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s5i bash ci/iris.sh shard lane-b` -- expected: every class passes, `Test.Contract.Ac` included (the signature prefixes). About 75 s.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s5i bash ci/iris.sh live production-restart` -- expected: PASS (every start ends OK, `Reconcile` included).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s5i bash ci/iris.sh live storage-roundtrip` -- expected: PASS (the compiled block of `Msg.ApprovalOutcome` equals the committed one).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s5i bash ci/iris.sh live demo-path` -- expected: PASS (UJ-1 is unchanged).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s5i bash ci/iris.sh teardown` -- expected: nothing tagged `e3s5i` is left.

**Shared surfaces:**
- **The Approval stubs are gone:** `Test.Bridge.Api` `TestApprovalStubs` is deleted.
- **`ProbeSink`'s call list** gains an eighth element. `Test.Bridge.Decide`, `Test.Bridge.Budget`, `Test.Bridge.Gate` and `Test.Bridge.Approval` read elements 1 to 7 by position. The shared list (`RunnerFixture.SinkCalls`) is unchanged.
- **The bridge message oracle** gains `Msg.ApprovalOutcome`: `Test.Bridge.Contracts`.
- **The hold now acts:**
  - 3.4's tests that complete a task directly on a pending row (`Remove`, `TestRestartKeepsTheHold`, `TestReconcileReArms`) still see the hold end with no outcome (row 14);
  - `TestReconcilePastExpiry`'s row now expires.
- **Decide's `HostSinkClass`** is swapped to `ProbeSink` for row 6 and restored.
- **`OcuTalonApprovals`** is disabled for row 13 and restored. `Clean` re-enables it.
- **The event log** gets one `IncidentManager` error per outcome. The tests wait for each to be handled before they end.
- Search the test trees for `Approval).Answer`, `.Expire(`, `.Cancel(`, `StartExecution`, `FinishExecution`, `not implemented yet (Story 3`, `ProbeSink`, `OcuTalonApprovals` and `HoldResponse`.
- **Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to record** (Rule 19; record each as `mutation: ... -> ...` here):

| AC | Pinning test | Mutation that must turn it red |
| --- | --- | --- |
| AC 1 | `TestAnswerApprovesAFix` | `AnsweredBy` is `$USERNAME` instead of `irisUser`; or the task is completed without `AssignTask`; or `approval.answered` fires before the save (the sink sees `pending`) |
| AC 1 | `TestAnswerBeforeTheTaskExists` | `Answer` looks for the task once, with no wait |
| AC 1 | `TestAnswerReArmed` | `Answer` completes the oldest task of the Ref, open or not |
| AC 2 | `TestTwoAnswersAtOnce` | `Answer` reads and checks the row's state before it takes the lock (both jobs get `done`) |
| AC 2 | `TestAnswerRefusals` | `Answer` checks the constant `OcuTalonUser` instead of the row's `RequiredRole` (case d); or skips the role check |
| AC 3 | `TestTimerExpires` | `HoldResponse` ignores the key `expiry` |
| AC 3 | `TestAnswerPastExpiry` | `Answer` does not compare `ExpiresAt` |
| AC 3 (DW-186) | `TestExpireDoesNotWaitForTheClock` | `Expire` refuses while `SecondsUntil(ExpiresAt)` is above 0 |
| AC 4 | `TestEveryOtherTransitionIsRefused` | `Cancel` accepts an approved row; or `FinishExecution` accepts `done` on an approved row; or `StartExecution` ignores `ExpiresAt` |
| AC 4 | `TestStartExecutionAtOnce` | `StartExecution` reads the state before it takes the lock |
| AC 4 | `TestCancel` | `Cancel` completes no task (the hold stays live) |
| AC 5 | `TestHoldActsOnlyOnTheRowsAnswer` | `HoldResponse` sends the TaskResponse's action without reading the row |
| AC 5 | `TestApprovedToolCallRunsNothing` | `HoldResponse` drops the `tool_call` check |
| AC 5 | `TestTimerDeliversAnUndeliveredAnswer` | on the timer, the hold sends only an `expired` outcome |
| AC 6 | `TestHoldIsFrozen` (Story 3.4) | a second stored property on `ApprovalHold`, or logic in `OnResponse` |

**Mutations observed red** (implement stage, warm `e3s5iw`; each applied alone to the tree, `Test.Bridge.Approval` run, then reverted byte-identical):
- mutation: `AnsweredBy` set to `$USERNAME` instead of `irisUser` -> red: `TestAnswerApprovesAFix` (the row holds the action, channel and user).
- mutation: `task.AssignTask(..#WORKFLOWUSER)` replaced by `$$$OK` (task completed without an assign) -> red: `TestAnswerApprovesAFix`, `TestAnswerBeforeTheTaskExists`, `TestAnswerReArmed`, `TestTwoAnswersAtOnce`.
- mutation: `approval.answered` fired before the row is saved (a `Fire` call ahead of `AnswerLocked`) -> red: `TestAnswerApprovesAFix` ("call 1 came after the change: the row was approved"; the sink sees `pending`), and the event-count asserts of five more tests.
- mutation: `CompleteHoldTask` looks for the task once, `While 0` instead of the poll loop -> red: `TestAnswerBeforeTheTaskExists`.
- mutation: `HoldTask` takes the oldest task of the Ref, open or not (`ORDER BY ID ASC`, no `TaskStatus_IsComplete` filter) -> red: `TestAnswerReArmed`.
- mutation: `Answer` opens the row before it takes the lock and `AnswerLocked` uses that stale object -> red: `TestTwoAnswersAtOnce` (both jobs `done`).
- mutation: the role check uses the constant `OcuTalonUser` instead of the row's `RequiredRole` -> red: `TestAnswerRefusals` (case d); and with the role check dropped -> red: `TestAnswerRefusals` (cases b to d).
- mutation: `HoldResponse` ignores the key `expiry` (`If 0` for the Expire block) -> red: `TestTimerExpires`, `TestReconcilePastExpiry`.
- mutation: `Answer` does not compare `ExpiresAt` (`If 0` for the past-expiry step) -> red: `TestAnswerPastExpiry`.
- mutation: `Expire` refuses while `SecondsUntil(ExpiresAt)` is above 0 -> red: `TestExpireDoesNotWaitForTheClock`, `TestEveryOtherTransitionIsRefused`.
- mutation: `Cancel` accepts an approved row (`pending,approved`) -> red: `TestEveryOtherTransitionIsRefused`.
- mutation: `FinishExecution` accepts `done` on an approved row -> red: `TestEveryOtherTransitionIsRefused`.
- mutation: `StartExecution` ignores `ExpiresAt` (`ahead` 0) -> red: `TestEveryOtherTransitionIsRefused`, `TestTimerDeliversAnUndeliveredAnswer`.
- mutation: the state is read before the lock is taken (stale row object in `Move`) -> red: `TestStartExecutionAtOnce` (both jobs OK).
- mutation: `Cancel` completes no task (`cancelTask` 0) -> red: `TestCancel` (the task stays open, the hold does not end).
- mutation: `HoldResponse` sends the TaskResponse's action without reading the row (`If action = "Approve"`) -> red: `TestHoldActsOnlyOnTheRowsAnswer`.
- mutation: `HoldResponse` drops the `tool_call` check -> red: `TestApprovedToolCallRunsNothing`.
- mutation: on the timer the hold sends only an `expired` outcome (`If row.State = "expired"`) -> red: `TestTimerDeliversAnUndeliveredAnswer`.
- mutation: logic added to `ApprovalHold.OnResponse` (an extra line before the call) -> red: `TestHoldIsFrozen`.
- mutation: `StartExecution` passes an event (`approval.answered`) to `Move` -> red: `TestEveryOtherTransitionIsRefused` ("approved + start: no event fires"; Decide's `HostSinkClass` is ProbeSink in that test).
- mutation: `AnswerLocked` does not set `AnsweredAt` -> red: `TestAnswerApprovesAFix`, `TestTwoAnswersAtOnce` (the time is empty).
- mutation: `MoveLocked` does not set `FinishedAt` -> red: `TestEveryOtherTransitionIsRefused` (every finish case).
- mutation: a property is added to `Msg.ApprovalOutcome` without its Storage block -> red: `live storage-roundtrip` ("the exported Storage block differs from the committed one"); `bash ci/checks.sh` storage does not compile, so it stays green (AC 6's storage clause is pinned by the live script only).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The five state methods of `OcuTalon.Bridge.Approval` (`Answer`, `Expire`, `Cancel`, `StartExecution`, `FinishExecution`) are built on one lock-then-event path, with `TASKSECONDS = 5`, the hold's task completion and the `sinkClass` trailing argument. `HoldResponse` acts only on what the row shows, delivers `ApprovalOutcome` to the row's `ResultTarget`, and falls back to the timer for an answer whose task could not be completed. `Msg.ApprovalOutcome` is new, with its committed storage block. `ApprovalHold` changed only in its class comment.

**Files changed.**
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`: the state methods, helpers, `HoldResponse`, class comment.
- `src/bridge/cls/OcuTalon/Bridge/Msg/ApprovalOutcome.cls` (new): the outcome message.
- `src/bridge/cls/OcuTalon/Bridge/Process/ApprovalHold.cls`: class comment only.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Approval.cls`: the fifteen matrix tests, helpers (`JustNow`, `WaitHoldSettled`, the gate, the job body), `Clean` and `OnAfterOneTest`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeSink.cls`: the eighth call element (the row's State).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls`: `TestApprovalStubs` removed.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Contracts.cls`: the oracle gains `ApprovalOutcome`.
- This spec: mutation lines, Decided in-stage, triage log, deferred list.

**Review.** 30 findings (medium 7, low 19, false 4). Patches applied: `CompleteHoldTask` catches its own exceptions (three findings, one cause); time assertions now check the stamp's format (`JustNow`); the transition matrix runs under the shared sink so "StartExecution fires no event" can fail; negative outcome checks wait for the hold's `OnResponse` to return (`WaitHoldSettled`); two `mutation:` lines for the storage clause. Deferred: one entry, a pending row that loses its hold (medium). Rejected findings and their reasons are in the Review Triage Log.

**Follow-up review recommended: true.** Three medium entries were patched, all in test code. The unverified risk is `WaitHoldSettled`: it relies on the message headers to the hold leaving statuses 1 to 3 once `OnResponse` returns, which passed on the warm and the fresh stack but was not shown to remove the race under load.

**Verification.**
- `bash ci/checks.sh`: all scripts passed.
- Warm `e3s5iw`, one class per call: `Test.Bridge.Approval` (24 s, run after the last patch), `Api`, `Contracts`, `Decide`, `Budget` and `Gate` passed.
- Fresh `e3s5i`: `shard lane-a` passed (44 classes, 447 s), `shard lane-b` passed (24 classes, 76 s, `Test.Contract.Ac` included), `live production-restart`, `live storage-roundtrip` and `live demo-path` passed (the demo path ran 1 of 6 steps, the rest skipped as before: 12 skipped, 0 failed).
- 23 mutations applied and observed red, each reverted byte-identical (the `mutation:` lines under `## Verification`).
- Teardown of `e3s5i` and `e3s5iw`: nothing tagged is left.

**Residual risks.**
- `WaitHoldSettled` (above).
- `TestAnswerBeforeTheTaskExists` assumes the task appears within `TASKSECONDS` (measured 0.03 s); a very slow runner could flake.
- The deferred pending-row-without-hold case.
- `Answer` reads the answerer's role set, which a CSP job can do only for its own user (Cross-epic note for Lane B's `AnswersIn`).
- The fresh `lane-a` shard took 447 s, against the 500 s line.
