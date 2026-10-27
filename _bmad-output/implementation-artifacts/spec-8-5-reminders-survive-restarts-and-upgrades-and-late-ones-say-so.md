---
title: 'Story 8.5: Reminders survive restarts and upgrades, and late ones say so'
type: 'feature'
created: '2026-10-27'
status: 'done'
baseline_revision: '65bba951189b2a468cd30e8b61b4f44e9c1e2d07'
baseline_commit: '65bba951189b2a468cd30e8b61b4f44e9c1e2d07'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** A pending reminder's waiter (`ReminderTimer`) can be gone at a start: the instance crashed between `ReminderOps` saving the row and starting the waiter, or the waiter was lost some other way. Nothing re-arms it today. The Schedule area declares no `Reconcile()`, so the installer's Reconcile step skips reminders and such a reminder is silently lost (FR-6, NFR-16). Nothing proves either that a reminder survives an IRIS restart or an in-place upgrade, or that one which fell due while IRIS was down arrives marked late.

**Approach:**
- **Reconcile.** The Schedule area declares `Reconcile()`, which the installer's Reconcile step already calls at every start, after the Production step. For each pending `Reminder` row with no live `ReminderTimer`, it starts a new waiter through `HeartbeatIn`, the Schedule area's adapterless service. The start uses the frozen `ReminderStart`/`ReminderTimer` path of Story 8.3. The new waiter is armed from the row's `DueAt` and stores its own start header id on the row.
- **No other waiter logic changes.** A waiter that survived the restart wakes on its own. A wake-up that fell due while IRIS was down fires right after the production starts, late, because `Ens.Alarm` restores its alarms (measured in planning). When two waiters exist, the second finds the row no longer pending and sends nothing (8.3's `Wake`).
- **Tests.** A new live unit restarts IRIS in its own compose project, once plainly and once as an in-place upgrade that recompiles `ReminderTimer`. It asserts order and outcome only. Unit tests in `Test.Schedule.Reminders` pin the re-arm rules and the two-waiter case.

## Boundaries & Constraints

**Always:**
- **The row is the truth (AD-5, AD-18).** `ReminderTimer`, `ReminderStart` and `Schedule.Reminder.Start`/`Wake` stay exactly as Stories 8.3 and 8.4 built them. The waiter's persistent properties and storage are frozen. Every changed persistent or message class keeps its committed, compiler-generated `Storage` block, and this story changes none.
- **`Reminder.Reconcile(only = "", Output skipped)`**, idempotent, in this order:
  - With no production running, it answers OK and does nothing (the next start reconciles, as `Conversation.Reconcile` does).
  - It reads the pending rows with one SQL statement and opens no row with a lock. `only`, a comma-separated list of Refs, limits the pass to those rows. The area's declaration passes none.
  - It skips a row that has a live waiter. A live waiter is a `ReminderTimer` instance with that `Ref` that is not completed, not terminated, and still waits for at least one response (the rule of `Bridge.Approval.IsLive`).
  - It skips a row whose `SessionRef` names no `Session` row, and adds its Ref to `skipped`.
  - It re-arms every other row through `Reminder.Rearm(ref)`.
  - It tries every row. A failed start becomes an error naming the Ref, and the errors combine into the returned status, as `Bridge.Approval.Reconcile` does.
  - It never touches a fired or cancelled row, never writes the row itself, and publishes no event.
- **The re-arm enters through a business service (AD-1).** `Rearm(ref)` makes `HeartbeatIn` with `Ens.Director.CreateBusinessService` and calls `ProcessInput` with a `ReminderStart` for the Ref.
  - `HeartbeatIn` handles a `ReminderStart` input before, and apart from, its heartbeat lock and tick.
  - It clears `..%SessionId` and sets `..%SuperSession` to the TraceRef of the row's session (AD-26). It then sends the start synchronously to `ReminderTimer` with `ReminderOps`' `STARTSECONDS` (10). No answer is an error naming the Ref.
  - The new waiter's start header is the first header of its own trace session, and the waiter writes that header's id to `TraceHeaderId` (8.3's `Start`).
- **The declaration.** `Install.Step.Schedule.Reconcile()` calls `Reminder.Reconcile()` and reports each skipped Ref with `Install.Step.Warn` (a `WARN Reconcile` line in the after-start log; the step stays OK). It returns `Reconcile`'s status.
- **No lock across a start (DW-296).** Reconcile and `Rearm` take no row lock. The waiter's own `Start` takes it, in `ReminderTimer`'s job.
- **Callers.** `Reconcile` and `Rearm` are called only from jobs that are not production jobs (the installer and the tests), so they keep no job session id. Lane A's `Approval.StartHold` shows the save and restore that a production-job caller would need (Consumed-by, Story 15.2).
- **Tests.** Unit tests go in `OcuTalon.Test.Schedule.Reminders` (shard `lane-b`; throwaways and CI only).
  - Each creates and removes everything it asserts on and ends every waiter it started.
  - At clean-up a Ref has at most one live waiter.
  - Each calls `Reconcile` only with its own Refs.
- **Restart cases.** They restart IRIS only in their own compose project (`docker/tests/test-reminder-restart.sh`, unit `live:reminder-restart`, group `production`). They assert order and outcome, never a seconds bound (NFR-10).

**Never:**
- Don't change `ReminderTimer`, `ReminderStart`'s properties, `Reminder.Start`/`Wake`, `ReminderOps`, the catalog, any message, payload or live-event shape, or `Production.cls`.
- No new production item, table, index, catalog key or public text, and no second publisher of `reminder` (AD-33).
- Don't edit Lane A's files (`src/bridge/**`, `Agent/**`, `Tools/**`, `Test/{Tools,Agent,Bridge,Install}/**`), the installer core (`Install/Registry.cls`, `Install/Step.cls`, `Install/Step/Reconcile.cls`, `Install/Step/Production.cls`) or anything of Epic 16.
- Don't edit any contended path beyond what `## Clarification Needed` asks the orchestrator to allow.
- No IRIS restart anywhere but a throwaway project. No local absolute path in a committed file. No literal non-ASCII character in code (Rule 14).
- The full upgrade harness of FR-60 (a release tag, a version-to-version upgrade) is Lane A's release work, not this story's.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Waiter gone | a pending row with no live `ReminderTimer` (never started, or its waiter ended), the session exists, the production runs | One new waiter: start header from `HeartbeatIn` to `ReminderTimer` (body `ReminderStart`, the Ref), the first header of its own session, `SuperSession` = the session's TraceRef. An `Ens.Alarm` request is pending in that session. `TraceHeaderId` = that header (a new id). State and `DueAt` are unchanged. No event | A failed start or no answer within 10 s: an error naming the Ref in the returned status; the other rows are still tried |
| Waiter waiting | a pending row with a live waiter | Nothing is started; `TraceHeaderId` and its `ReminderStart` headers are unchanged | none |
| Fired or cancelled | a row in either state | Untouched; no waiter, no start header | none |
| Session gone | a pending row whose `SessionRef` names no `Session` row | Not started; its Ref is in `skipped`; the declaration writes `WARN Reconcile ...` naming it; the step stays OK | warning |
| No production | Reconcile with no production running | OK; nothing done | none |
| Run again | Reconcile twice | The second run starts nothing | none |
| Fell due while down, waiter survived | IRIS stopped past `DueAt`, then started | The old waiter wakes on the restored alarm right after the production starts and fires once: `Late` 1, `reminder.late` with `{"time","text","dueAt"}`, `time` = `dueAt`. Web card "Reminder (late; it was due at hh:mm): text." and one phone message | none |
| Fell due while down, waiter gone | as above, with no waiter | The re-armed waiter's timer is 1 s; it fires once, late, as above | none |
| Future across a restart or upgrade | pending, due after the start | The waiter survives (same `TraceHeaderId`, still waiting). The rail lists the row with its `dueAt` until it fires. It fires once, not late, `reminder.due`, never before `DueAt` | none |
| Two waiters | an old and a re-armed waiter of one row both wake | The first marks it fired and sends; the second finds it not pending and ends. One notification per channel, one fired event | none |

</intent-contract>

## Code Map

Product, Epic 8's (paths under `src/ocutalon/cls/OcuTalon/`):
- `Schedule/Reminder.cls`. It gains `Reconcile`, `LiveWaiter`, `Rearm` and `StartFrom`.
  - `Start` `:95-112` already writes `TraceHeaderId` from `timer.%PrimaryRequestHeader` and arms `SetTimer(SecondsUntil(DueAt))`, at least 1 s. For a non-pending row it only replies.
  - `Wake` `:115-152` already ends without sending for a non-pending row (`:126`), under `RefIndexOpen(ref, 4)`.
  - `IsLate` `:69` and `Notification` `:79` already give `reminder.late` with `time`. Class doc `:3-15`.
- `Schedule/HeartbeatIn.cls`. `OnProcessInput` `:15-33` ignores its input today, and the Task Manager calls it with none. The tick path, under `Heartbeat LOCK` `:18-20`, stays as it is.
- `Schedule/ReminderOps.cls`, read only:
  - `STARTSECONDS` `:35` and `TIMERITEM` `:38`, to reuse;
  - `StartWaiter` `:273-284` and `SendIn` `:289-304`: the BO's start, which saves and restores its own session (a BO keeps its command's session; a BS call does not need that);
  - `EndWaiter` `:243-262`.
- `Schedule/ReminderStart.cls`: `Ref` only. Only its doc names a second sender.
- `Install/Step/Schedule.cls`: today `Tasks()` only. Its class doc says it "only declares".

Installer core (Lane A's, read only):
- `Install/Registry.cls`:
  - `Order()` `:14`: `... "Production", "Reconcile", ...`, so Reconcile runs after the production starts;
  - `Areas()` `:20` finds every `Install.Step.<name>` subclass;
  - `CallAreas` `:78` calls each area's method and combines the failures by area.
- `Install/Step.cls`: `Reconcile()` default `:30`, `Warn` `:52`, `TakeWarnings` `:58`. `Install/Step/Reconcile.cls`: `Run()` calls `CallAreas("Reconcile")`.
- `Install/Step/Production.cls:1-21`: never sets autostart on the Docker path. It starts the production, or restarts every item, and recovers a Troubled one (`:67-74`).

Siblings to mirror (read only):
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`:
  - `LiveHold` `:621` and `IsLive` `:631`: the liveness rule;
  - `Reconcile` `:645-680`: reads pending rows by SQL, tries every row, `Combine` `:695`;
  - `StartHold` `:131-162`: the job-session restore for production-job callers.
- `Install/Step/Approvals.cls`: the one-line declaration.
- `Core/Conversation.cls:660-666` `Reconcile`: the `IsProductionRunning` guard, then `CreateBusinessService` and `ProcessInput` of an existing service. `Install/Step/Web.cls:79-84` declares it.
- `irislib/Ens/Alarm.cls` (reference only):
  - `OnInit` restores `^Ens.Alarm` and the suspended alarms at every start of the item;
  - `CheckAlarmTasks` answers a past wake time at once;
  - `SuspendAlarms` runs at production stop.
  - `AddAlarm` stores the wake time as absolute UTC seconds.

Tests, Epic 8's:
- `Test/Schedule/Reminders.cls` (base `Test.Core.InProduction`):
  - class doc `:3-31`; `OnAfterOneTest` `:51` (`ReminderFixture.Remove` of `..Reminders`); `SetReminder` `:64`; `Timers`/`IsWaiting`/`WaitEnded` `:72-89`;
  - `CreatedSeconds` `:90`, `Route` `:98`, `Keep` `:262`, `EventStates` `:269`, `RequestsBetween` `:275`, `Rows` `:281`;
  - `TestFiresOnEveryChannel` `:196`, the pattern for channel checks.
- `Test/Schedule/ReminderFixture.cls`:
  - `Set` `:64`, `Cancel` `:49`, `Remove` `:94-133` (it deletes only the `TraceHeaderId` session's headers), `Timers` `:190`, `IsWaiting` `:201`, `WaitEnded` `:210` and `RemoveSession` `:226`.
  - Remove is used by `Reminders`, `ReminderChat` and the browser specs `web/e2e/reminder/*.spec.ts` and `demo-path/03-reminder.spec.ts`.
- `Test/Data/Fixture.cls` (contended, call only):
  - `Session` `:19`;
  - `Reminder(sessionRef, dueAt, state, fields)` `:50`: a row with no waiter;
  - `SessionHeaders`, `Between`, `States`, `Clean` `:331`.
- `Test/Core/Observe.cls`: `Events` `:46`, `WaitProcessed` `:64`, `DeliveryRows` `:16`.
- `Web/Api.cls:478` `StateBody(session)`, rail at `:600-611` (`rail.reminders[]`: `ref`, `dueAt`, `state`, trace fields when `TraceHeaderId` is set).

Live tests and CI:
- `docker/tests/test-production-restart.sh`: the restart sibling.
  - `restart_snapshot` `:67-75`.
  - Row 20 (`:119-235`): seeds `Fixture.Reminder(s)` at `:130` and requires the rail to be identical after a kill at `:182-195`. See Clarification Needed Q1.
- `docker/tests/lib-live.sh`:
  - `live_start` `:57`, `live_add_file` `:151`, `dc` `:243`, `wait_until` `:286`, `iris_script` `:307`;
  - `started_at` `:335`, `start_log` `:345`, `wait_started_ready` `:372`, `check_session` `:479`, `log_steps` `:584`;
  - `live_pop_file` `:610`, `check_clean_start` `:660`.
- `docker-compose.dev.yml` and `docker/after-start.cos`: `OCUTALON_DEV=1` makes the start run `zpm load` of the image's package (`STEP package loaded (dev)`), the load an upgrade runs.
- `ci/units.sh`: `production` group `:32`; `NO_WEB_BUNDLE_UNITS` `:73`. `ci/iris.sh` `live_known` `:360` takes any unit of a group. `docker/tests/test-ci-config.sh` checks that every `docker/tests/test-*.sh` is in one group or list.
- `.github/workflows/ci.yml:100`: CI's `OCUTALON_LIVE_DEADLINE` is 1200 s; the local default is 540 s.
- `docker/tests/test-storage.sh`: the `storage` rule (a committed block) and `release-diff` (`PASS release-diff: no release tag yet`; no `v*` tag exists).
- Stays green with no edit: `Test/Install/Registry.cls:221-238` `TestReconcileStep` (lane-a). It now also runs the Schedule declaration, which only re-arms waiterless pending rows left in that stack.

## Tasks & Acceptance

**Execution:**
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/Reminder.cls` -- add the four methods below and extend the class doc to the re-arm (contract only) -- AC 1, AC 4.
  - `LiveWaiter(ref) As %String`: the id of a live `ReminderTimer` with the Ref, or "". It mirrors `Approval.LiveHold`/`IsLive` over `OcuTalon_Schedule.ReminderTimer`.
  - `Rearm(ref) As %Status`: `CreateBusinessService("HeartbeatIn")`, then `ProcessInput` of a new `ReminderStart` with the Ref. The service is closed before it returns.
  - `StartFrom(service, start, Output output) As %Status [ Internal ]`: the start that `HeartbeatIn` makes.
    - It reads the row's `SessionRef` by SQL, then the `Session` row's TraceRef. No session is an error naming the Ref.
    - It sets `service.%SessionId = ""` and `service.%SuperSession` = TraceRef.
    - It sends `SendRequestSync(ReminderOps.#TIMERITEM, start, .output, ReminderOps.#STARTSECONDS)`. No object answer is an error "ReminderTimer did not answer the start of <ref> within 10 seconds".
  - `Reconcile(only = "", Output skipped As %List) As %Status`: the Always rules, in their order. One `SELECT Ref, SessionRef FROM OcuTalon_Data.Reminder WHERE State = 'pending' ORDER BY DueAt, ID`, collected and closed before the first start. Then, per row, `LiveWaiter`, the session check and `Rearm`. The errors combine like `Approval.Combine`.
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/HeartbeatIn.cls` -- at the top of `OnProcessInput`, before the lock: `If $IsObject(pInput) && pInput.%IsA("OcuTalon.Schedule.ReminderStart") Quit ##class(OcuTalon.Schedule.Reminder).StartFrom($this, pInput, .pOutput)`. Add a class-doc line: it is also the Schedule area's way in for the re-arm (AD-1). The tick path is unchanged -- the AD-1 entry for code outside the production.
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/ReminderStart.cls` -- doc only: `ReminderOps` or `HeartbeatIn` (the re-arm) sends it. No property or storage change.
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Schedule.cls` -- add `ClassMethod Reconcile() As %Status`. It calls `##class(OcuTalon.Schedule.Reminder).Reconcile("", .skipped)`, writes `..Warn("the reminder " _ ref _ " has no session, so no waiter was started for it")` per skipped Ref, and returns the status. Update the class doc ("declares the heartbeat task and re-arms the reminders") -- AC 1, AD-23.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderFixture.cls` -- add two helpers and extend `Remove` -- so a re-armed reminder leaves nothing behind.
  - `StartHeaders(ref) As %DynamicArray`: the `ReminderStart` headers whose body has the Ref, oldest first, as `{id, sessionId, superSession, source, target, status}`.
  - `WaitingCount(ref) As %Integer`: `Timers` plus `IsWaiting`.
  - `Remove` also deletes the headers of the session of every `StartHeaders(ref)` entry through `RemoveSession`, besides the `TraceHeaderId` session. Update its doc.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/Reminders.cls` -- add the four tests below and extend the class doc. Waiterless rows come from `Test.Data.Fixture.Reminder` (with `{"Text": <unique>}`), each Ref kept for `ReminderFixture.Remove` (`Keep`) and for `Fixture.Clean` (`..Refs`) -- AC 1, AC 2, AC 4 and the matrix.
  - `TestReconcileRearmsOnlyLostWaiters` (AC 1). In one fixture session:
    - `lost`: pending, no waiter, due in 15 s, made last so that the 15 s count from just before the call;
    - `ended`: set through the product, due in 90 s, cancelled through `ReminderFixture.Cancel` (its waiter ends at once, `WaitEnded`), then put back to `State` pending and `CancelKey` "" with its old `TraceHeaderId`;
    - `live`: set through the product, due in 90 s;
    - `fired` and `cancelled`: rows in those states, no waiter.

    `Reminder.Reconcile(<the five Refs>, .skipped)` is OK with `skipped` empty. Then:
    - `lost` and `ended` each have `WaitingCount` 1.
    - For each, `TraceHeaderId` is the id of its last `StartHeaders` entry: source `HeartbeatIn`, target `ReminderTimer`, `sessionId` = its id, `superSession` = the session's TraceRef. For `ended` that id differs from the old one. `RequestsBetween(id, "ReminderTimer", "Ens.Alarm")` is 1. Both rows are still pending with the same `DueAt`.
    - `live` has the same `TraceHeaderId`, one `StartHeaders` entry (source `ReminderOps`) and `WaitingCount` 1.
    - `fired` and `cancelled` are unchanged, with no `ReminderTimer` and no start header.
    - The session's `reminder` event count is unchanged by the call.
    - A second call starts nothing: the `StartHeaders` counts and `WaitingCount`s are the same.
    - Then `lost` fires through its re-armed waiter (wait until no waiter, at most `FIRESECONDS`): fired, `Late` 0, one `ReminderTimer` to `Notify` request in its new session, created no earlier than `DueAt`, and one web card `Reminder: <text>.`.
  - `TestReconcileFiresLateWhenDueWhileDown` (AC 2, re-arm path). A pending row with no waiter, due 30 s ago. `Reconcile(<its Ref>)`, then wait until no waiter. Then:
    - fired, `Late` 1;
    - one Notification with `reminder.late` and `Slots` exactly `{"time":<dueAt>,"text":<text>,"dueAt":<dueAt>}`;
    - Notify to `WebChatOut` 1 and to `SimPhoneOut` 1, processed (demo mode is the stack's default, asserted on);
    - one web `Delivery` whose `Text` = `Catalog.RenderAt("reminder.late", slots, "web", ...)` and starts with `Reminder (late; it was due at `;
    - one `SimMessage` with the phone rendering;
    - `EventStates` ends `fired` with `late` true.
  - `TestTwoWaitersFireOnce` (AC 4). A reminder set through the product, due in 8 s (waiter A). Then `Reminder.Rearm(<its Ref>)` (waiter B, past the liveness check), so `WaitingCount` is 2. Wait until none waits (at most `FIRESECONDS`). Then:
    - fired, `Late` 0;
    - exactly one `ReminderTimer` to `Notify` request across both waiter sessions (`StartHeaders`);
    - one web card and one `SimMessage`;
    - `EventStates` is `pending,fired`.
  - `TestReconcileSkipsReminderWithoutSession` (matrix). A pending row whose `SessionRef` is a fresh Ref with no `Session` row. `Reconcile(<its Ref>, .skipped)` is OK and `skipped` = `$ListBuild(ref)`. No `ReminderTimer`, no start header, and the row is unchanged.
- [ ] `docker/tests/test-reminder-restart.sh` (new; unit `live:reminder-restart`; label `t85r`) -- the restart and upgrade cases (AC 1, 2, 3, 5, 6). It follows `test-production-restart.sh`'s structure and lib-live's helpers. Header: what it pins and needs (contract only).
  1. **First start.** `dc up -d --build`, then `wait_started_ready 400`.
  2. **Seed** one `Fixture.Session` S through `iris_script`, then the reminders below. Record each Ref, `DueAt`, `TraceHeaderId` and `StartHeaders` count. Give every reminder a distinct text and `DueAt`.
     - R_due: `ReminderFixture.Set(S, ..., 30)`;
     - R_far: `Set(S, ..., 86400)`;
     - R_lostdue: `Fixture.Reminder(S, now+30 s)`, no waiter;
     - R_lost: `Fixture.Reminder(S, now+86410 s)`, no waiter;
     - R_fired and R_cancelled: `Fixture.Reminder` in those states;
     - R_orphan: `Fixture.Reminder(<a Ref with no session>, now+86420 s)`.
     - Check `StateBody(S).rail.reminders` lists R_due, R_far, R_lostdue and R_lost with their `dueAt`.
  3. **Restart 1, plain.** `dc stop iris`. Precondition: the stop ended before R_due's `DueAt`; otherwise FAIL naming it. Wait until 15 s past R_due's `DueAt`, then `dc start iris` and `wait_started_ready 300`. Record the restart's seconds and the container's `StartedAt`. Checks, polled for at most 60 s for the firing outcome:
     - R_due: fired, `Late` 1. Exactly one `ReminderTimer` to `Notify` request for it, created at or after `StartedAt`, with `reminder.late` and `time` = `dueAt`. Exactly one web card with the late text (the literal prefix and `Catalog.Render`), one `SimMessage` with the phone text, and the card in `StateBody(S).chat`.
     - R_lostdue: fired the same way, through a start header from `HeartbeatIn`.
     - R_far: pending, same `TraceHeaderId`, one start header (`ReminderOps`), `WaitingCount` 1, and in the rail with the same `dueAt`.
     - R_lost: pending, with a new `TraceHeaderId` whose header is from `HeartbeatIn` in its own session under S's TraceRef, `WaitingCount` 1, and in the rail with `traceUrl` to that id.
     - R_fired and R_cancelled: unchanged, no waiter, no start header.
     - R_orphan: pending, no waiter. The after-start log has `STEP Reconcile OK` and a `WARN Reconcile` line naming it.
  4. **Set R_future** with `ReminderFixture.Set(S, ..., F2)`, where F2 = max(90, 4 x restart-1 seconds + 60). Record its `DueAt` and `TraceHeaderId`, and check that the rail lists it with that `dueAt`. Record `ReminderTimer`'s compiled `TimeChanged`.
  5. **Restart 2, upgrade in place.** `live_add_file` an override that sets `OCUTALON_DEV: "1"`, then `dc up -d` and `wait_started_ready 400`. Then:
     - The log has `STEP package loaded (dev)`, and `TimeChanged` is later, so `ReminderTimer` was recompiled.
     - Precondition: IRIS's `NowUtc` is before R_future's `DueAt`; otherwise FAIL naming F2 and both restart times.
     - R_future, R_far and R_lost are pending with unchanged `TraceHeaderId`s and unchanged start-header counts, `WaitingCount` 1 each, and in the rail.
  6. **R_future fires.** Wait for it at most until `DueAt` + 60 s. Fired, `Late` 0, one `Notify` request in the session of the `TraceHeaderId` recorded when it was set (its pre-upgrade waiter), created no earlier than `DueAt`, `reminder.due`. One card `Reminder: <text>.`, one `SimMessage`, and it has left the rail.
  7. **End.** `check_clean_start`: no error or alert in the event log. One PASS or FAIL line per check; exit 0 only when all pass. The trap tears the project down.
- [ ] `ci/units.sh` -- the `production` group becomes `live:production live:production-restart live:reminder-restart` (Lane B's group entry). Add `live:reminder-restart` to `NO_WEB_BUNDLE_UNITS` only if Q2 allows it -- AC 6 in CI.
- [ ] `docker/tests/test-production-restart.sh` -- ONLY as Q1's ruling allows. Recommended: line 130's `$ClassMethod(F,"Reminder",s)` becomes `$ClassMethod("OcuTalon.Test.Schedule.ReminderFixture","Set",s,"zz restart snapshot",86400).ref`, and the row-20 header phrase "a pending reminder" becomes "a pending reminder set through ReminderOps" -- keeps row 20 green now that Reconcile re-arms a waiterless pending row.

**Acceptance Criteria:**
1. **Reconcile re-arms only what is gone.**
   - Given the Schedule area's `Reconcile()` declaration and pending, fired and cancelled `Reminder` rows, when the installer's Reconcile step runs at a start (or `Reminder.Reconcile` with the rows' Refs), then for each pending row whose `ReminderTimer` is gone it starts one new waiter, armed from the row's `DueAt`, whose start header (from `HeartbeatIn`, the first header of its own session under the session's TraceRef) is stored as the row's `TraceHeaderId`.
   - It leaves fired and cancelled rows alone and starts nothing for a row whose waiter is still waiting. A second run starts nothing.
   - At a real start, the rail of `/state` (`StateBody`) lists the re-armed reminder with its trace link to the new header. (FR-6, NFR-16, AD-1, AD-5, AD-23, AD-26)
2. **Fell due while down.** Given a reminder whose due time passes while IRIS is stopped, when IRIS starts again, then it fires once, right after the production starts, marked late: `Late` 1, one `reminder.late` Notification with `time` = its due time, one web card "Reminder (late; it was due at hh:mm): text." and one phone message. This holds whether its old waiter survived or Reconcile re-armed it. (FR-34, NFR-16, UX-DR112)
3. **Future across a restart.**
   - Given a reminder still in the future when IRIS restarts, when its due time arrives after the start, then it fires once, not late, `reminder.due`, never before `DueAt`, through the waiter that survived.
   - The rail listed it with its `dueAt`, which is the page's countdown, before and after the restart until it fired. (FR-6, FR-34, NFR-16, UX-DR54)
4. **Two waiters, one notification.** Given an old and a re-armed waiter of one reminder, when both wake and read the row under its lock, then only the first sends. The second ends without sending: one notification per channel and one fired event. (FR-34, AD-5)
5. **Upgrade in place.**
   - Given an in-place upgrade that reloads the package and recompiles `ReminderTimer` (its compiled time changes), when a reminder that was pending before it comes due, then it fires on time from its pre-upgrade waiter.
   - `ReminderTimer` still holds only `Ref` in its committed `Storage` block, and `test-storage.sh` passes (`storage`, and `release-diff`: no release tag yet). The full FR-60 harness is Lane A's release work. (NFR-17, AD-5)
6. **CI.** Given the restart cases, when CI runs the IRIS groups on the IRIS runner, then `live:reminder-restart` in the `production` group restarts IRIS in its own compose project and asserts order and outcome (one notification per channel, late or not), never seconds. (NFR-10, NFR-16, AD-22)

## Spec Change Log

- 2026-10-27 (lead, after the plan's intent-gap HALT): the orchestrator allowed Q1 and Q2; the lead applied Q3 (AC 6 reworded). Recorded under Design Notes; Clarification Needed removed; status set to `ready-for-dev` (the plan was otherwise complete and measured).

## Review Triage Log

### 2026-10-27 — Review pass
- verdicts: the layers reported 27 findings (Blind 10, Edge 14, Verification-gap 3 gaps and the Rule 19 notes, Intent alignment 1 descriptive report); grouped by root cause below — high 0, medium 7 patched plus 1 rejected as spec-bound, low 5 patched plus 8 rejected, false 0, maybe-false 0
- findings:
  - `[medium]` `[patch]` Blind: R_due 30 s ahead may pass before `dc stop` on a slow runner; Edge: same; Verification-gap: same window — R_due 60 s and R_lostdue 65 s ahead in the live script.
  - `[medium]` `[patch]` Blind: `due_epoch` read after the seeding call makes the "stopped before due" check lenient — the host clock is read before the call for that check and after it for the wait.
  - `[medium]` `[patch]` Edge: the "no waiter left" read of R_future is a single sample taken as soon as the card shows — the script waits for the waiter to end first.
  - `[medium]` `[patch]` Edge: F2 sized from restart 1 can be passed by the slower upgrade restart on a runner — F2 is 6 x restart 1 + 60 s, at least 120 s.
  - `[medium]` `[patch]` Verification-gap: the live "fired once" check is sampled at the first match — R_due and R_lostdue are checked again before `check_clean_start`.
  - `[medium]` `[patch]` Blind, Edge, Verification-gap: `TestReconcileWithoutProductionDoesNothing` leaves the production stopped if its start fails — `OnAfterOneTest` starts it if it is not running.
  - `[medium]` `[patch]` Verification-gap: the re-arm failure path has no test — `TestRearmWithoutSessionFails` (red when `StartFrom` returns OK for a missing session).
  - `[low]` `[patch]` Verification-gap: `LiveWaiter`'s three-clause rule is pinned only at its extremes — `TestLiveWaiterRule` (red when `LiveWaiter` answers any instance).
  - `[low]` `[patch]` Edge, Blind-adjacent: `Rearm`'s doc says the job's session ids are not touched, but `ProcessInput` clears `$$$JobSessionId` — the doc now says so.
  - `[low]` `[patch]` Edge: `TestTwoWaitersFireOnce` sets 8 s, which a loaded host can use up before the second waiter is counted — 15 s.
  - `[low]` `[patch]` Verification-gap (Rule 19): AC 2 (surviving waiter) and AC 5 (upgrade) have no live mutation line — both applied to `live:reminder-restart`, red, reverted; lines in Verification.
  - `[low]` `[patch]` Verification-gap: matrix row "No production" had no covering test — `TestReconcileWithoutProductionDoesNothing` (added at the Matrix Test Audit), with its mutation.
  - `[medium]` `[reject]` Edge, Blind: one failed re-arm makes the Reconcile step fail and one row can keep the instance from becoming ready, and many rows take up to 10 s each — spec-bound: the contract says the errors combine into the returned status and the declaration returns it (Design Notes 3 treats only a session-less row as a warning).
  - `[low]` `[reject]` Blind, Edge: `LiveWaiter` and `StartHeaders` ignore SQL errors — a failed read means a second harmless waiter (AC 4); the fix adds a branch.
  - `[low]` `[reject]` Blind, Edge: `StartFrom` takes an empty `TraceRef` and reads the row again — every Session row has a TraceRef, and the race is a deleted row between two reads, which ends as a start error naming the Ref.
  - `[low]` `[reject]` Edge: `IsProductionRunning` may be wrong while the state changes — spec-bound: the contract mirrors `Conversation.Reconcile`; the next start reconciles.
  - `[low]` `[reject]` Edge: a waiter with a lost alarm counts as live — spec-bound (the `Approval.IsLive` rule), and Design Notes 2 records it.
  - `[low]` `[reject]` Edge: a `ReminderStart` left in the queue after a crash can overwrite `TraceHeaderId` — `Start`/`Wake` are frozen by the contract, and two waiters are harmless by AC 4.
  - `[low]` `[reject]` Edge: the production-restart row 20 reminder is not removed by `Fixture.Clean` — Q1 allows only the seed line to change, and the row lives in a throwaway project.
  - `[low]` `[reject]` Edge: restart-2 "keeps its waiter" checks pass if both reads are empty — the next check (`pending1|pending1|pending1`) fails on an empty read.
  - `[low]` `[reject]` Blind: no log of how many reminders were re-armed; `check_rail`'s "-" mode is a tautology; no test for the two-waiter trace-link effect; CI group docs and timings not updated — not defects (the "-" mode greps the Ref and dueAt, and fails when either is missing); the group timings are the lead's bookkeeping (`_bmad/` is owner-only).
  - `[low]` `[reject]` Intent alignment (descriptive): the unit tests call `Reminder.Reconcile` directly and the declaration and the restart outcomes are pinned by the live unit — the spec puts them there (AC 1, 2, 3, 5, 6); no divergence from the intent.

## Design Notes

**Rulings in force (recorded by the lead, 2026-10-27):**
- **Q1, ALLOWED (orchestrator, decide):** in `docker/tests/test-production-restart.sh` change only row 20's seed line, to `ReminderFixture.Set(s, "zz restart snapshot", 86400)` (a real waiter), and the matching row-20 header phrase. Nothing else in the file. Reported as a footprint extension.
- **Q2, ALLOWED (orchestrator, decide):** append `live:reminder-restart` to `NO_WEB_BUNDLE_UNITS` in `ci/units.sh`; the list is shared by entry (add Epic 8's name only, change nothing else). Epic 10's branch edits the same line: a plain union at integrate-forward. Reported as a footprint extension.
- **Q3 (lead, Rule 5 tier 1, applied):** AC 6 in `epics.md` now reads "When CI runs the Schedule area's restart unit on the IRIS runner" (with an AMENDED marker).
- **AD-18 note (Decided 1):** not written; the design complies with AD-1 as it stands, and a runner never amends an AD.

**Governing ADs:**
- AD-1: the re-arm enters the production through a business service (`HeartbeatIn`, `CreateBusinessService` and `ProcessInput`).
- AD-5: the row is the truth; the frozen waiter (only `Ref`, logic in `Schedule.Reminder`); append-only storage with committed blocks; the startup reconciler re-arms a pending row whose process is gone, from the row's times.
- AD-18: a `Reminder` row plus one `ReminderTimer` on `SetTimer`; late beyond 10 s; the row keeps its waiter's header id; `Data.Time` only.
- AD-22: Schedule tests in `lane-b` on throwaways; restart cases in their own compose project; the CI groups.
- AD-23: the after-start order (Production, then Reconcile); each area declares `Reconcile()`; `Install.Step.Warn` for a non-fatal condition; a failed step stops the ready marker.
- AD-26: each waiter has its own trace session under the session's TraceRef.
- AD-32: `reminder.late` with its `time` slot; producers never render.
- AD-12 and AD-33: Reconcile publishes no event; `reminder` keeps its two publishers.
- AD-29: Lane B's files only.
- AD-4 is not involved: Reconcile is the system's own pass over its table, as `Approval.Reconcile`'s is, and no caller names a target.

Conventions: "Times", "Identifiers", "Live events".

**Measured in planning** (throwaway `e8s5plan`, build 154, developer machine, lane C, torn down; a scratch script on lib-live). One session had:
- R1, set through the product, due in 45 s;
- R2, set through the product, due in 1200 s;
- R3, a pending fixture row with no waiter.

Results:
- **Clean stop past a due time.** `docker compose stop iris` took 2 s; IRIS stayed down until 20 s past R1's due time, and `dc start` reached ready in 13 s. After the start, `^Ens.Suspended` named `OcuTalon.Production`, so the Production step had recovered it.
  - R1 fired at production start, before the after-start log ended, from its old waiter: the `Notify` header was in its original session. It was `Late` 1, `reminder.late` with `time` = `dueAt`, one web card "Reminder (late; it was due at 20:48): zz due while down." and one phone delivery.
  - So a waiter survives a restart by itself, and `Ens.Alarm` fires a wake-up that fell due while IRIS was down as soon as the production starts. Reconcile runs after the Production step, by the registry's fixed order.
- **R2 survived every restart.** It stayed pending with its `TraceHeaderId`, one waiting waiter and its alarm in `^Ens.Alarm`, across the stop, a dev reload and a `docker kill` (13 s to ready).
- **R3 stayed waiterless.** With no Schedule `Reconcile` it would be lost silently.
- **The dev reload.** A recreate with `OCUTALON_DEV=1` logged `STEP package loaded (dev)`, moved `ReminderTimer`'s compiled `TimeChanged`, and reached ready in 41 s.
- **The steps.** `STEP Reconcile` took 0.1 s. No error or warning from `ReminderTimer`, `Ens.Alarm`, `Notify` or `ReminderOps` was in the event log. The whole script took 247 s.

**Decided in-stage:**
1. **The re-arm goes through `HeartbeatIn`, the Schedule area's existing adapterless service.** AD-1 requires a business service for code outside the production. The precedent is `Conversation.Reconcile`, which enters through `WebChatIn` with a second input type. A new `ReminderStartIn` item would add a production item, a spine table row (AD-33) and edits to `Production.cls` and the oracle, for the same effect. The re-armed waiter's trace session starts with `HeartbeatIn -> ReminderTimer`, which AD-26 allows ("its own trace session"). For the lead (Rule 20, optional): AD-18 could record that `HeartbeatIn` is also the Schedule area's entry for the re-arm.
2. **The liveness rule is `Approval.IsLive`'s:** not completed, not terminated, at least one pending response.
   - A waiter that is mid-wake when Reconcile reads it can look gone. Reconcile then starts a second waiter, which is harmless: both run in the single `ReminderTimer` job, and the later one finds the row fired (AC 4). So the live unit never asserts on R_due's start headers.
   - Not covered: a live instance whose alarm an administrator's production clean wiped. `CleanProduction` kills `^Ens.Suspended`, which holds the suspended alarms (inference from `Ens.Director`). AD-23's Production step only recovers and never cleans, so this is outside restarts and upgrades.
3. **A row whose session is gone is skipped with a warning, not a failure.** A failure would stop the ready marker at every start for good (a poison row), and the reminder has no session to deliver to. Any other failed start fails the step, naming the Ref, as `Approval.Reconcile` does.
4. **Reconcile publishes no event.** The row's state and due time do not change, so the rail does not either. Only its trace target changes, and `/state` carries that. `reminder` keeps its two publishers (AD-33's event table).
5. **The `only` filter** keeps the unit tests hermetic: they never re-arm another test's rows. The live unit drives the real, unfiltered step.
6. **The restart cases live in a new live unit.** A `%UnitTest` cannot restart its own IRIS. Restart 1 is plain (`dc stop`/`start`). Restart 2 is an in-place upgrade by `OCUTALON_DEV=1`, the same `zpm load` an upgrade start runs, with the recompile observed. A version-to-version upgrade is Lane A's FR-60 harness.
   - F2 adapts to the machine: 6 x restart 1 + 60 s, at least 120 s (implement stage; it was 4 x + 60 s, at least 90 s), because the upgrade restart runs about 3 times as long as the plain one (42 s against 13 s measured) and a slower runner stretches both.
   - Measured at implement: 319 s on the developer machine (restart 1 13 s, restart 2 42 s; inside the 540 s local deadline), with R_due 60 s and R_lostdue 65 s after seeding. Expected about 9 to 12 min on the runner (inference: 2.4 to 3.9 times the ARM figures), under CI's 1200 s.
7. **Group `production`.** On Story 8.4's run (40544926928) it was the shortest IRIS job, 9 min 46 s, against `image`'s 24 min 44 s. With the unit, about 19 min (inference), so REL-4's 35-minute wall clock is unchanged.
8. **"The rail showed it with its countdown throughout"** is read from `StateBody(S).rail.reminders`, the snapshot the page loads, at each point. The countdown is the page's rendering of `dueAt`, which 8.3's `reminder.spec.ts` pins in a browser. The live sign-in stack cannot restart itself, so no browser spans a restart.
10. **Decided in the implement stage** (review round 1; reversible inside the story, no AD touched). The live script seeds R_due 60 s and R_lostdue 65 s ahead (the plan said 30 and 35), because the pre-stop checks run as separate `iris_script` sessions and a runner 2.4 to 3.9 times slower could pass R_due's due time before `dc stop`. The "stopped before it was due" check reads the host clock before the seeding call and the wait until past due reads it after. R_due and R_lostdue are checked once more at the end, so a second firing after the later restart is seen. After R_future fires the script waits for its waiter to end before it reads the row. `TestTwoWaitersFireOnce` sets its reminder 15 s ahead (it was 8 s) so that waiter A has not fired when the second waiter's start answers on a loaded host. `Reminders.OnAfterOneTest` starts the production again if a test left it stopped. Three tests were added: `TestRearmWithoutSessionFails`, `TestLiveWaiterRule` and `TestReconcileWithoutProductionDoesNothing` (the matrix row "No production").
9. **No live sign-in or demo-path run.** This story changes no spec. `ReminderFixture.Remove`'s change is additive, and the shard's `Reminders` and `ReminderChat` exercise it.

**Ledger inbox:** none (dispatch). DW-296 (terminal, context) is respected by design: Reconcile and `Rearm` take no row lock, so no waiter's `Start` waits on one.

**Integration ACs:**
- The installer's Reconcile step (`Install.Step.Reconcile` through `Registry.CallAreas`, Epic 0) calls `Install.Step.Schedule.Reconcile()` at every start. The observable effect is a re-armed waiter whose header id the rail's trace link carries, and a fired reminder (`live:reminder-restart`, AC 1 and AC 2).
- `HeartbeatIn` gets a `ReminderStart` from `Rearm` and starts the waiter, whose session Visual Trace reads (AC 1).
- `Notify`, `WebChatOut` and `SimPhoneOut` deliver the late Notification of a re-armed or surviving waiter (AC 2).

**Consumes:** `Install.Registry`/`Install.Step` (Story 0.2); `Schedule.Reminder.Start`/`Wake`, `ReminderStart`, `ReminderTimer`, `ReminderOps` constants (8.3, 8.4); `HeartbeatIn` (8.1); `Ens.Alarm` (platform). Tests only: `Test.Core.InProduction`, `Test.Data.Fixture`, `Test.Core.Observe`, `ReminderFixture`, lib-live.

**Consumed-by:**
- Story 15.2 (IPM install, production autostart): AD-23's "on every production start, the Reconcile declarations run once the items are running" will call this declaration. A caller from a production job must save and restore the job's session ids around `Rearm`, as `Approval.StartHold` does.
- Story 16.4: its closed-page case (a reminder fires after the CSP session ended) needs nothing more.
- Stories 11.1 and 29.4: UJ-1 end to end, and the load test.

**Extend, don't copy:**
- `Reminder.Reconcile`/`LiveWaiter` mirror `Bridge.Approval.Reconcile`/`LiveHold`/`IsLive`. The Lane A bridge class is specific to its own table and hold class, so the rule is written again (about 10 lines) rather than shared.
- The re-arm reuses 8.3's `ReminderStart`, `Reminder.Start` and `ReminderOps`' `STARTSECONDS`/`TIMERITEM`. `StartFrom` is not `ReminderOps.StartWaiter`: that one is private to the BO and restores the BO's own session, which a business-service call has no need of.
- The declaration copies `Install.Step.Approvals`' one-line pattern, plus the warning.
- The new tests extend `Test.Schedule.Reminders` itself, not a new class, so they reuse its private helpers (`Keep`, `EventStates`, `RequestsBetween`, `CreatedSeconds`) without copying them.
- `ReminderFixture.StartHeaders` and `WaitingCount` extend the fixture beside `Timers`/`IsWaiting`.
- The live unit follows `test-production-restart.sh` and lib-live. Its rail reader returns `rail.reminders` only, unlike that script's local `restart_snapshot`. The `OCUTALON_DEV` override is a one-line `live_add_file`, as `test-install-upgrade.sh` adds its context file.

**Footprint extensions to report:** the new `docker/tests/test-reminder-restart.sh` (a new file in a contended folder), `ci/units.sh` (the group entry, and Q2), and `docker/tests/test-production-restart.sh` (Q1, only as ruled).

## Verification

**Shared values.**
- `<L>` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=8 stage=<stage>'`. Write it out in full on each call.
- Each call is its own foreground tool call with `timeout: 600000`, one test class or unit per call, never two IRIS test calls in one message.
- Tags: implement uses `e8s5i` (fresh) and `e8s5iw` (warm); other stages use `e8s5<stage>` and `e8s5<stage>w`.

**Commands:**
- `(once, first)` `<L> OCUTALON_RUN_TAG=e8s5iw ci/warm.sh up`. Expected: ready.
- `(loop)` After a warm reload of `Schedule/Reminder.cls`, restart the `ReminderTimer` item. `HeartbeatIn` is adapterless and needs no restart.
  ```
  P=$(OCUTALON_RUN_TAG=e8s5iw ci/warm.sh status | sed -n 's/.*project=\([^ ]*\).*/\1/p') && printf '%s\n' 'Do ##class(Ens.Director).EnableConfigItem("ReminderTimer",0,1)' 'Do ##class(Ens.Director).EnableConfigItem("ReminderTimer",1,1)' 'Halt' | docker exec -i "$(docker ps -q --filter label=com.docker.compose.project=$P --filter label=com.docker.compose.service=iris)" iris session IRIS -U OCUTALON
  ```
  Expected: no error.
- `(loop)` `<L> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e8s5iw ci/iris.sh class OcuTalon.Test.Schedule.Reminders`. Expected: `CLASS ... passed` (about 40 to 60 s more than before, inference).
- `(loop)` The same warm command, one per call, for `OcuTalon.Test.Schedule.ReminderLogic`, `OcuTalon.Test.Schedule.Heartbeat` (about 150 to 210 s), `OcuTalon.Test.Schedule.HeartbeatLogic`, `OcuTalon.Test.Schedule.ReminderChat` and `OcuTalon.Test.Install.Registry`. Expected: each passed.
- `(loop)` `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-storage.sh`, `bash docker/tests/test-boundaries.sh` and `bash docker/tests/test-class-rules.sh`. Expected: all pass.
- `(once)` `<L> OCUTALON_RUN_TAG=e8s5i ci/iris.sh live reminder-restart`. Record the total and both restart times. Expected: every check PASS, about 4.5 min.
- `(once, only after Q1's edit)` `<L> OCUTALON_RUN_TAG=e8s5i ci/iris.sh live production-restart`. Expected: passed, row 20 included.
- `(once)` One per call: `<L> OCUTALON_RUN_TAG=e8s5i ci/iris.sh build`, then `shard lane-b`, `shard lane-b --reverse` and `shard lane-a` (about 7 min each). Expected: every `CLASS` passed.
- `(once)` `bash ci/checks.sh`. Expected: pass.
- `(once, last, also after a failure)` `<L> OCUTALON_RUN_TAG=e8s5iw ci/warm.sh down`, then `<L> OCUTALON_RUN_TAG=e8s5i ci/iris.sh teardown`.

**Mutations (Rule 19).** Apply each, observe red, revert, and confirm the tree is byte-identical (`git status --short`, `git diff --stat`). Record each as `mutation: <change> -> <red test>`.
- AC 1:
  - `Reminder.Reconcile` skips the `LiveWaiter` check -> `Reminders.TestReconcileRearmsOnlyLostWaiters` (`live` gets a second start header);
  - `Install.Step.Schedule` without `Reconcile()` -> `live:reminder-restart` (R_lost not re-armed, R_lostdue never fires).
- AC 2: `Reminder.IsLate` returns 0 -> `Reminders.TestReconcileFiresLateWhenDueWhileDown` (`reminder.due`, no late text).
- AC 3: `Reminder.Start` arms `SecondsUntil(dueAt) + 15` -> `live:reminder-restart` (R_future fires late).
- AC 4: `Reminder.Wake` ignores `State` (the non-pending check made `If 0`) -> `Reminders.TestTwoWaitersFireOnce` (two `Notify` requests, two cards).
- AC 5: `ReminderTimer`'s `Storage Default` block removed -> `bash docker/tests/test-storage.sh` (`FAIL storage`).
- AC 6: `live:reminder-restart` removed from the `production` group -> `bash docker/tests/test-ci-config.sh` (a test script in no group or list).

**Mutations observed (implement stage).** Each applied, red observed, restored from a backup byte-identical (`cmp`, `git status --short`).
- mutation: `Reminder.Reconcile` skips the `LiveWaiter` check -> red `Reminders.TestReconcileRearmsOnlyLostWaiters` (`live` keeps no header id, gets a second start header).
- mutation: `Install.Step.Schedule` without `Reconcile()` -> red `live:reminder-restart` (R_lostdue never fires, R_lost not re-armed; 7 checks).
- mutation: `Reminder.IsLate` returns 0 -> red `Reminders.TestReconcileFiresLateWhenDueWhileDown` (`and late`).
- mutation: `Reminder.Start` arms `SecondsUntil(dueAt) + 15` -> red `live:reminder-restart` (R_future fires late).
- mutation: `Reminder.Wake` ignores `State` (check made `If 0`) -> red `Reminders.TestTwoWaitersFireOnce` (two `Notify` requests, two cards).
- mutation: `ReminderTimer`'s `Storage Default` block removed -> red `bash docker/tests/test-storage.sh` (`FAIL storage`).
- mutation: `Reminder.Reconcile`'s no-production guard (`If '..IsProductionRunning() Quit $$$OK`) made `If 0` -> red `Reminders.TestReconcileWithoutProductionDoesNothing` (`Reconcile is OK`: HeartbeatIn is not registered to run); matrix row "No production".
- mutation: `Reminder.LiveWaiter` answers any ReminderTimer with the Ref (the three clauses dropped) -> red `Reminders.TestLiveWaiterRule` (`none of the three is a live waiter`).
- mutation: `Reminder.StartFrom` answers OK for a missing session -> red `Reminders.TestRearmWithoutSessionFails` (`Rearm fails`, `its error names the Ref`).
- mutation (AC 2, a surviving waiter and a re-armed one, live): `Reminder.IsLate` returns 0 -> red `live:reminder-restart` (`R_due (its waiter survived): not fired once`, `R_lostdue (no waiter): not fired once`).
- mutation (AC 5, the upgrade, live): the script's `OCUTALON_DEV` override set to `"0"` -> red `live:reminder-restart` (`no STEP package loaded (dev)`, `ReminderTimer's compiled time did not move`).
- mutation: `live:reminder-restart` removed from the `production` group -> red `bash docker/tests/test-ci-config.sh` (`FAIL units`, `FAIL inputs`).

**Shared surfaces:**
- the Reconcile step at every start, which now re-arms every waiterless pending reminder:
  - `test-production-restart.sh` row 20's fixture reminder (Q1);
  - `Test.Install.Registry.TestReconcileStep`, which runs every area's Reconcile in the lane-a stack (it only re-arms leftovers);
  - possible `WARN Reconcile` lines in the after-start log, which `log_steps` and `expected_run` ignore;
- `HeartbeatIn`'s input (a `ReminderStart` branch; the tick path and `Test.Schedule.Heartbeat` are unchanged);
- `ReminderFixture.Remove`, used by `Reminders`, `ReminderChat` and the browser reminder specs, which now also removes re-armed waiter sessions;
- the `production` group's units and run time, and `NO_WEB_BUNDLE_UNITS` (Q2);
- the throwaways' `ReminderTimer` instances, `Ens.Alarm` alarms and reminder `Delivery` and `SimMessage` rows (each test removes its own; the live unit's project is torn down);
- the heartbeat across the live unit's stops (one catch-up tick, not asserted).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The Schedule area re-arms reminders at every start. `Reminder.Reconcile(only, .skipped)` starts one new waiter, through `HeartbeatIn` and `Reminder.Rearm`/`StartFrom`, for each pending row with no live `ReminderTimer`; it skips a row with a live waiter, reports a row whose session is gone, takes no lock, writes no row and publishes no event. `Install.Step.Schedule.Reconcile()` calls it and warns for each skipped Ref. A new live unit, `live:reminder-restart` (group `production`), restarts IRIS plainly and as an in-place upgrade in its own project and asserts order and outcome.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Schedule/Reminder.cls`: `LiveWaiter`, `Rearm`, `StartFrom`, `Reconcile`, `Combine`, the `STARTITEM` parameter and the class doc.
- `src/ocutalon/cls/OcuTalon/Schedule/HeartbeatIn.cls`: a `ReminderStart` input is sent on before the lock and the tick.
- `src/ocutalon/cls/OcuTalon/Schedule/ReminderStart.cls`: doc only.
- `src/ocutalon/cls/OcuTalon/Install/Step/Schedule.cls`: the `Reconcile()` declaration.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderFixture.cls`: `StartHeaders`, `WaitingCount`, and `Remove` also removes re-armed waiters' sessions.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/Reminders.cls`: seven new tests and an `OnAfterOneTest` that restarts a stopped production.
- `docker/tests/test-reminder-restart.sh` (new): the restart and upgrade unit.
- `docker/tests/test-production-restart.sh`: row 20's seed line and header phrase only (Q1).
- `ci/units.sh`: the `production` group entry and `NO_WEB_BUNDLE_UNITS` (Q2).

**Review (round 1).** Patches applied: 12 (7 medium, 5 low). Deferred: none. Rejected: 9 grouped rows (about 15 findings), each with its reason in the Review Triage Log. Follow-up review recommended: false.

**Verification.**
- Warm stack, one class per call, all passed: `Reminders` (63 s with the 7 new tests), `ReminderLogic`, `Heartbeat` (152 s), `HeartbeatLogic`, `ReminderChat`, `Install.Registry`. `test-ci-config.sh`, `test-storage.sh` (`release-diff`: no release tag yet), `test-boundaries.sh`, `test-class-rules.sh` pass.
- Fresh stack, once after the last patch: `live reminder-restart` passed in 319 s (restart 1 13 s, restart 2 42 s, 38 checks); `live production-restart` passed, row 20 included; `shard lane-b` 65 classes 436 s; `shard lane-b --reverse` 65 classes 490 s; `shard lane-a` 47 classes 426 s; `bash ci/checks.sh` passed. Warm and fresh stacks torn down, no leftovers.
- Mutations: eleven observed red and restored byte-identical (listed in Verification).

**Residual risks.** CI is slower than the developer machine: the live unit's seeding margins (R_due 60 s, F2 at least 120 s) are sized for a runner 2.4 to 3.9 times slower (inference); its CI time (about 9 to 12 min) is unmeasured until the first CI run. A waiter that is mid-wake when Reconcile reads it can get a second, harmless waiter (Design Notes 2).
