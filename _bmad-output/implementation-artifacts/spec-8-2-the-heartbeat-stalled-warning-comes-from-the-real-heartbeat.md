---
title: 'Story 8.2: The heartbeat-stalled warning comes from the real heartbeat'
type: 'feature'
created: '2026-10-25'
status: 'done'
baseline_revision: 'b4a087af362d2c926d75d18448a939b13e237602'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Epic 2's heartbeat-stalled banner and the check rows' "(late)" marks react to a `heartbeatStalled` status condition that nothing computes: `OcuTalon.Live.Payload.Status.Computed` gives only `dailyCap` and `noModelKey`, so `/state` and `StatusMonitor` never report a stalled heartbeat, and a user can't tell when checks and reminders have stopped running, or when they run again (FR-32).

**Approach:** `Status.Computed` gains the `heartbeatStalled` condition, computed from Story 8.1's tick mark (`StatusMark.Get("heartbeatTick")`) and the clock: on when the last tick is more than 180 s old, with that tick's UTC time as its `time` slot; off when no readable tick exists. `/state` (through `Status.Active`) and `StatusMonitor` (every 15 s, publishing each change on the instance stream) already take their conditions from `Computed`, so neither shared file changes, and Epic 2's banner, rail and announcer show the real condition.

## Boundaries & Constraints

**Always:**
- One computation (AD-12): `heartbeatStalled` is built only in `Status.Computed`, after `noModelKey` (catalog order). `Computed(keys, budget, heartbeat)` uses the heartbeat reading it is given (`{"lastTick", "now"}`); when the third argument is omitted it takes `OcuTalon.Schedule.Heartbeat.Reading()` itself, so the two-argument calls of `StatusMonitor` and `Status.Active` get the real reading.
- The stalled rule: `Data.Time.Seconds(now) - Data.Time.Seconds(lastTick) > 180` (`Heartbeat.STALLSECONDS`). An empty or unreadable `lastTick` (HeartbeatIn reads such a mark as no tick, Story 8.1) or `now`, a reading that is not a dynamic object, and a tick later than now are all off. Active: slots `{"time": lastTick}` verbatim. Inactive: no slots, so it exports `{"condition":"heartbeatStalled","active":false}`.
- The tick mark is read only through `StatusMark.Get` (Conventions "Status marks"), and times only through `Data.Time` (AD-18). No schema change: `StatusSlots.Time` already exists (AD-5).
- `StatusMonitor` stays the one publisher of `status` events (AD-33). Its existing change detection publishes the onset and the clear.
- Every test that moves the tick mark or suspends the real task ends, also after a failure, with the task as found and a fresh mark (one real tick through `HeartbeatTask.OnTask()`), so the ambient heartbeat that other tests now read through `Computed` never flips under them. Among this story's tests, only the ones that wait for their own clear set the mark more than 180 s back.
- The banner and "(late)" texts are Epic 2's catalog and rail strings. This story adds no user-facing text.

**Never:**
- No edit to `src/ocutalon/cls/OcuTalon/Core/StatusMonitor*.cls` or `src/ocutalon/cls/OcuTalon/Web/Api.cls` (shared by function with Epic 4, orchestrator ruling), and none to Epic 2's `web/src/app/{banners,rail}/**`, which already react to the condition.
- No change to an existing line of `web/e2e/demo-path/02-watch.spec.ts`. One self-contained block may be appended at its end.
- No edit to `docker/**`, `ci/units.sh` (`Schedule` is already a `lane-b` area), Lane A's `Checks`, `WatchOps` or `BackgroundCheck`, or any other contended path.
- No other publisher of `heartbeatStalled` (not `HeartbeatIn`, not this story's fixture), and no new condition, slot or catalog key.
- No literal non-ASCII character in code (Rule 14), and no local machine path in a tracked file.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Never ticked | no `heartbeatTick` mark (`lastTick` "") | off, no slots | none |
| Fresh | `lastTick` = now - 60 s | off | none |
| Boundary | `lastTick` = now - 180 s | off (not more than 3 minutes) | none |
| Just stalled | `lastTick` = now - 181 s | on, `slots.time` = `lastTick` | none |
| The tests' stall | `lastTick` = now - 240 s | on, `slots.time` = `lastTick` | none |
| Unreadable mark | `lastTick` "garbage" | off | none |
| Clock moved back | `lastTick` later than now | off | none |
| No usable reading | `heartbeat` "" or not an object, or `now` unreadable | off | none |
| Real tick after a stall | the mark becomes now | `/state` is off at once; `StatusMonitor`'s next run publishes `{"condition":"heartbeatStalled","active":false}` | none |
| Restart after a long stop | `StatusMonitor`'s first run after its job starts sees a stale mark | remembered silently (Epic 2's rule); `/state` shows it; the catch-up tick's clear is published | none |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Live/Payload/Status.cls:45-53` `Computed(keys, budget)`: gains the third argument and one inserted line. `:77` `DailyCap` and `:93` `NoModelKey` are the private siblings that `HeartbeatStalled` follows. `:56` `Active` (what `/state` calls) calls `Computed` with two arguments: code unchanged, doc updated. `:26` `Readings` stays the bridge-only reading. Lane B's (the publisher's lane), outside the footprint list and contended by no running epic: a footprint extension.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Part/StatusSlots.cls`: `Time` (UTC, MAXLEN 20) is the slot. Read only.
- `src/ocutalon/cls/OcuTalon/Core/StatusMonitor.cls:25-56`: reads `Readings`, takes `Computed(keys, budget)`, publishes each condition whose exported JSON changed; its first run after the job starts only remembers. Read only.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls:258,293` `StateBody(session, instanceStream)`: `body.status = Status.Active(sessionRef)`. Read only; tests call `StateBody` for `/state`.
- `src/ocutalon/cls/OcuTalon/Schedule/Heartbeat.cls`: 8.1's class (`TICKMARK`, `LOCK`). It gains `STALLSECONDS`, `Reading()` and `Stalled(lastTick, now)`.
- `src/ocutalon/cls/OcuTalon/Schedule/HeartbeatTask.cls` `OnTask()`: a real tick through `CreateBusinessService("HeartbeatIn")`, quiet when the production doesn't run. The fixture's `Tick()` calls it.
- `src/ocutalon/cls/OcuTalon/Data/StatusMark.cls:39` `Get`; `src/ocutalon/cls/OcuTalon/Data/Time.cls:18,27,42` `NowUtc`, `Seconds`, `AddSeconds`. Read only.
- `src/ocutalon/cls/OcuTalon/Live/Publish.cls:32` `LastSeq(stream)` and `#INSTANCE`; `src/ocutalon/cls/OcuTalon/Live/Event.cls:34` `Since(stream, after, max, label)`. Read only.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls:147-184` `Restore()`: restores the found tick mark, then `ResumeTask()` (`:171`). `:676` `HoldTask` and `:692` `ResumeTask` hold the heartbeat lock in the test's own process: the pattern for `StallFixture`, not callable across processes.
- `src/ocutalon/cls/OcuTalon/Test/Live/Status.cls:91-107` `TestComputedOrder` (asserts `dailyCap,noModelKey`) and `:109-127` `TestActive` (asserts 2 active): shared surfaces to update. Epic 2's file, Lane B's, contended by no running epic: a footprint extension.
- `src/ocutalon/cls/OcuTalon/Test/Core/StatusMonitor.cls` with `Test/Core/StatusMonitorProbe.cls`: the probe overrides only `Readings` and `Stream`, so its runs now read the real heartbeat. No edit; it stays hermetic through the fresh-mark rule.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls:139-143` `TestStateBody`: compares `body.status` with `Status.Active` member for member. Stays green, no edit.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` `RunningReason`: Lane A's helper. Reuse it to require a running production; never edit it.
- `web/src/app/rail/rail-view.ts:204-209,308`: "(late)" while `store.status.heartbeatStalled.active` is true. `web/src/app/banners/banner-view.ts:69,148-153`: the `banner.heartbeatStalled` banner with `{time}` from `slots.time`. Read only.
- `web/e2e/support/iris.ts`: `irisScript`/`chk` (`:42,60`), `seedCheck` (`:668`), `cleanFixtureRows` (`:581`), `fixtureUser('BANNERS')`. `web/e2e/support/page.ts:53-84`: `recordAnnouncements`, `announcements`. `web/e2e/support/floor.ts:51`: `rowOf`. `web/e2e/banners/banners.spec.ts:100-110`: `applied`/`turn`, the pattern of waiting for the page's applied Seq and then asserting within one second; `main.main` carries `data-instance-seq` (`web/e2e/live/live.spec.ts:90`).
- `web/e2e/support/api.ts:27` `changeSnapshot(page, change)`; `web/e2e/sign-in/helpers.ts:94` `signInReadme`. The demo-path stack has no fixture user and its specs have no IRIS access (`docker/tests/test-demo-path.sh` header), so the appended block uses only these.
- `web/e2e/demo-path/02-watch.spec.ts`: three `notBuilt` lines (4.7, 4.7, 8.2). Epic 4's while it runs: append only.
- `web/e2e/api/api.spec.ts:121,159` pins the instance stream at one event, seeded by `docker/tests/test-sign-in.sh:161-176`. Playwright runs the files in path order with one worker (`web/playwright.config.ts`), so `api/` runs before `heartbeat/`.
- `ci/units.sh`: `Schedule` is already a `lane-b` area, so a new `Test.Schedule.*` class joins the shard with no edit.

## Tasks & Acceptance

**Execution:**
- [x] Task 0 (implement stage, warm throwaway; record the results under Design Notes, labelled measured or (inference)): (a) confirm that `StatusMonitor`'s job runs `OnProcessInput` at its start and then every `CallInterval` (15 s), and choose the signal that `StallFixture.Hold` waits for before it moves the mark, so that the job's silent first run never swallows the change (candidate: the item's job registration time `$$$EnsJobStatus($$$SystemName, job, $$$eJobRegTime)` at least `CallInterval` + 2 s in the past); (b) record the time from `Hold(240)` to `StatusMonitor`'s publish and from `Tick()` to the clear.
- [x] `src/ocutalon/cls/OcuTalon/Schedule/Heartbeat.cls` -- add `Parameter STALLSECONDS = 180`, `ClassMethod Reading() As %DynamicObject` (`{"lastTick": StatusMark.Get(TICKMARK), "now": Data.Time.NowUtc()}`) and `ClassMethod Stalled(lastTick As %String, now As %String) As %Boolean` (pure; the matrix); the class doc states the stalled rule -- the heartbeat's own rules stay in its class.
- [x] `src/ocutalon/cls/OcuTalon/Live/Payload/Status.cls` -- `Computed(keys, budget, heartbeat)`: after `NoModelKey`, insert `..HeartbeatStalled(<heartbeat when given, else Heartbeat.Reading()>)` (the argument's `$Data` decides); add the private `HeartbeatStalled(heartbeat)` beside `DailyCap`; update the class, `Computed` and `Active` doc comments (contract only) -- one computation for `/state` and `StatusMonitor`, with no edit to either shared file.
- [x] `src/ocutalon/cls/OcuTalon/Test/Schedule/StallFixture.cls` (new; no Test methods; the product never refers to it) -- class methods that work across processes (the browser spec calls each one in its own `iris session`), with their state under `^OcuTalonTest("StallFixture")`:
  - `Hold(secondsBack)` suspends the real task (remembering its `Suspended` value the first time), waits (up to 16 s) until the clock second is between 5 and 45, takes and releases `Heartbeat.#LOCK` (10 s) to wait out a run in flight, waits for Task 0 (a)'s signal, then sets the tick mark to now - `secondsBack` (or removes it when `secondsBack` is "") and returns the mark;
  - `InstanceSeq()` is `Live.Publish.LastSeq` of the instance stream;
  - `WaitEvent(after, active, seconds = 30)` returns the Seq of the first `status` event on the instance stream after `after` whose payload is `heartbeatStalled` with that `active`, or 0 (polling every 0.5 s);
  - `Tick()` runs `HeartbeatTask.OnTask()`;
  - `Release()` resumes the task with the remembered value, kills its node and runs `Tick()`.
  One fixture serves the unit test and the browser spec.
- [x] `src/ocutalon/cls/OcuTalon/Test/Schedule/Stalled.cls` (new; needs the running production; throwaways and CI only, like 8.1's `Heartbeat`) -- `OnBeforeAllTests` requires `RunnerFixture.RunningReason()` = ""; `OnAfterOneTest` and `OnAfterAllTests` call `StallFixture.Release()` and delete the `zzstall*` fixture sessions with their events and counters. Methods: `TestStateAndMonitor` (AC 1, the onset and the clear; the only method that stalls, and it waits for its own clear), `TestNoTickIsOff` (AC 1), `TestReading` (after `Hold(100)`, `Reading()` holds the mark and a time within 2 s of now), `TestReleaseLeavesFresh` (after `Hold(100)` and `Release()`, the mark is at most 5 s old, the task's `Suspended` is the value found and the fixture's node is gone).
- [x] `src/ocutalon/cls/OcuTalon/Test/Schedule/HeartbeatLogic.cls` -- add `TestStalled` (every matrix row through `Heartbeat.Stalled`) and `TestStalledCondition` (`Status.Computed` with an injected reading: the order `dailyCap,noModelKey,heartbeatStalled`; the exact exported JSON on and off; a reading of "" or a non-object is off; `ActiveOf` holds it only when on) -- pure, no production.
- [x] `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` -- `Restore()`: after `ResumeTask()`, when `OcuTalon.Production` runs, run one real tick (`HeartbeatTask.OnTask()`) and append its status, so the class ends with a fresh mark; the gap that tick records is the honest one that 8.1 accepted (VG-O7) -- the fresh-mark rule for the classes that read the real heartbeat after it.
- [x] `src/ocutalon/cls/OcuTalon/Test/Live/Status.cls` -- `TestComputedOrder` passes "" as the heartbeat reading and expects `dailyCap,noModelKey,heartbeatStalled` with actives `110` and `000`; the two fixed-reading `Computed` calls of `TestActive` pass "" (still 2 active and 0 active); its comparison of `Active` with `ActiveOf(Computed(keys, budget))` stays two-argument (both read the real heartbeat) -- shared surface (Rule 19).
- [x] `web/e2e/heartbeat/heartbeat.spec.ts` (new; project `chromium`, run by `live:sign-in` after `api/`) -- one test, with `test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-GB' })` and a 90 s timeout, as the banners fixture user:
  - seed a production check (`seedCheck`, a unique name, last run 60 s ago, passed), `recordAnnouncements`, sign in, and wait for the loaded page with no `heartbeatStalled` banner and the row's meta "Last run {time} · Passed";
  - `since` = `InstanceSeq()`, `mark` = `Hold(240)`, `seqOn` = `WaitEvent(since, 1, 30)` (not 0); once `data-instance-seq` >= `seqOn`, within 1 s: the banner reads exactly "Background checks have paused: the heartbeat last ran at {mark as the page shows it}. Watches and reminders may be late until it recovers." (the time formatted as `pageTime` formats it), the row reads "Last run {time} (late) · Passed", and the announcer read the banner text once; a `GET /ocutalon/api/v1/state` through the page's own session (`page.request`) answers a `status` array holding `{"condition":"heartbeatStalled","active":true,"slots":{"time":"<mark>"}}`;
  - `Tick()`, then the same `GET` answers no `heartbeatStalled` member; `seqOff` = `WaitEvent(seqOn, 0, 30)` (not 0); once applied, within 1 s the banner is gone and the row reads "Last run {time} · Passed"; the banner text was announced exactly once in the whole test;
  - `finally`: `Release()` and `cleanFixtureRows`.
  This is the real-runtime test (Rule 3); the middle dot is written as an escape (Rule 14).
- [x] `web/e2e/demo-path/02-watch.spec.ts` -- append one self-contained block at the end, with its own imports under local aliases (`heartbeatTest`, `heartbeatExpect`, `heartbeatSnapshot`, `heartbeatSignIn`), so they never clash with names that lines Epic 4 adds import: a `describe` titled for Story 8.2 with one test whose title differs from the `notBuilt` line's. `heartbeatSnapshot` answers `/state` with the real answer, keeps the real `status` array, and puts one fixture check in `rail.checks` (`ref` `zz-fixture-orders`, `kind` `production`, `displayName` `Orders`, `lastRunAt` 30 s ago, `result` `passed`); `heartbeatSignIn`; then assert that the real `status` holds no `heartbeatStalled`, that the "Orders production" row's meta matches `Last run <time> · Passed` with no "(late)", and that no `heartbeatStalled` banner shows -- AC 3, fixture-backed.

**Acceptance Criteria:**
1. Given the production running, the real task held by `StallFixture` and a fixture session, when the tick mark is set 240 s back, then `Web.Api.StateBody(session).status` holds exactly one `heartbeatStalled` member, `{"condition":"heartbeatStalled","active":true,"slots":{"time":"<mark>"}}`, and `StatusMonitor`'s real job publishes that payload as a `status` event on the instance stream within 30 s. When `StallFixture.Tick()` then writes a real tick, `StateBody` holds no `heartbeatStalled` at once, `StatusMonitor` publishes `{"condition":"heartbeatStalled","active":false}` within 30 s, and no `heartbeatStalled` event lies between that onset and that clear. With no tick mark, `StateBody` holds no `heartbeatStalled`. (FR-32, AD-12, AD-18, AD-33)
2. Given the banners user's page open on the sign-in stack with a seeded production check, when the tick mark is set 4 minutes back and `StatusMonitor`'s next run publishes the condition, then within one live update of the page applying that event the heartbeat-stalled banner shows the tick's time, the check row reads "Last run {time} (late)", the announcer reads the banner once, and `GET /ocutalon/api/v1/state` of that session holds `heartbeatStalled` with the tick's time as its slot; and when a real tick is written, then `/state` holds no `heartbeatStalled` at once, and within one live update of the page applying `StatusMonitor`'s clear, the banner and the "(late)" mark are gone. (FR-32, NFR-9, AD-12, UX-DR99, UX-DR132)
3. Given the demo-path stack (a first start with the CI mock), when step 2's appended Story 8.2 test answers `/state` with a fixture "Orders production" check row, then the row shows "Last run {time} · Passed" with no "(late)" mark and no heartbeat banner, while the real `/state` status holds no `heartbeatStalled`. The existing `notBuilt(..., '8.2')` line stays as it is until the real switch on the integration branch. (FR-33, REL-2, AD-29, UX-DR53)

## Spec Change Log

## Review Triage Log

### 2026-10-25 - Review pass
- verdicts: 24 findings - high 0, medium 0, low 16, false 8, maybe-false 0
- findings:
  - `[low]` `[patch]` blind: `StallFixture.Hold` clock wait (16 s) is shorter than its worst case (19 s) and ends silently - `WAITCLOCK` raised to 21 and its doc names the worst case.
  - `[low]` `[patch]` blind: `Release` kills the remembered `Suspended` value even when the task save failed - the node is killed only when the save was OK.
  - `[low]` `[reject]` blind: `Restore()` records a gap mark after the gaps were put back - the spec accepts it (VG-O7, Task line for `Restore()`); the class doc now says the closing tick may record a gap mark.
  - `[false]` `[reject]` blind: `Computed`/`Active` read ambient heartbeat state - the spec's decided shape (shared files stay untouched); `TestStateAndMonitor` covers `Active` through `StateBody`, and the fresh-mark rule keeps other classes stable (45-class `lane-b` shard green in both orders).
  - `[false]` `[reject]` blind: the appended 02-watch block, its aliases and mid-file imports - spec-directed (Epic 4's lines, append only); `npm --prefix web run lint` is green.
  - `[low]` `[reject]` blind: `CALLINTERVAL` hard-coded to the production's 15 s - AD-18 fixes it; reading it from the production adds a lookup for a value that cannot change without an AD amendment.
  - `[low]` `[patch]` blind: one-sided "240 s back" assertion in `TestStateAndMonitor` - now `$ZAbs(...) < 5`.
  - `[false]` `[reject]` blind: no test for a stale mark at monitor start - the first-run-remembers rule is Epic 2's and its test is `Test.Core.StatusMonitor`; the matrix row is covered as audited under Design Notes.
  - `[low]` `[patch]` edge: same as the Hold clock wait above - one fix.
  - `[low]` `[reject]` edge: same as `Restore()` gap mark above - one decision.
  - `[false]` `[reject]` edge: `Reading()` throwing aborts `Computed` - `StatusMark.Get` is the project's one reader of marks and its siblings `DailyCap` and `NoModelKey` take readings with no such guard; no failing path was shown.
  - `[false]` `[reject]` edge: a stale mark during a planned stop shows the banner - that is the stalled heartbeat the story reports (matrix row "Restart after a long stop").
  - `[low]` `[reject]` edge: `WaitEvent` reads at most 200 events - the instance stream holds a handful of events on a throwaway.
  - `[false]` `[reject]` edge: imports appended mid-file fail a lint rule - `npm --prefix web run lint` is green, there is no such rule.
  - `[low]` `[reject]` edge: `OnAfterOneTest` of 8.1's class writes no tick - the spec asks for the tick at the end of the class (`Restore()`); the other readers run after the class.
  - `[low]` `[patch]` edge: the class doc says the gap marks are put back, but the closing tick can add one - doc comment amended.
  - `[low]` `[reject]` verification-gap: `Restore()`'s fresh tick has no test or mutation line - it is not an acceptance criterion's pin; a test would have to call `Restore()` mid-class, which kills the class's own fixtures; its effect is exercised by the shard in both orders (`Heartbeat` then `StatusMonitor`, `Api`, `Stalled`).
  - `[low]` `[reject]` verification-gap: `Test.Core.StatusMonitor` reads the ambient heartbeat - the spec's decided cost (no edit to the shared file); a mark moves only with a tick, and the production ticks every minute, so a fresh mark stays fresh.
  - `[low]` `[reject]` verification-gap: `heartbeat.spec.ts` leaves two instance events that `api.spec.ts` only tolerates by run order - decided under Design Notes (one worker, path order, the stack is fresh per run); deleting events would break the stream's counters.
  - `[low]` `[patch]` verification-gap: the spec's `finally` swallows a failed `Release` - the test now throws when `Release` does not answer `1`.
  - `[low]` `[reject]` verification-gap: AC 3 guards only over-reporting and the AC 2 and AC 3 mutation runs are unobserved - the mutations were run in this pass: AC 3 red in `live demo-path`, AC 2 red in `live sign-in` (lines recorded under Verification).
  - `[false]` `[reject]` verification-gap: `Hold`'s return equals `StatusMark.Get` is a near tautology - it is the contract that `Hold` returns the mark; the next assertion does the work.
  - `[low]` `[reject]` verification-gap (other): the `Restore()` gap mark - same decision as above.
  - `[false]` `[reject]` intent-alignment: descriptive report; no divergence to fix. It notes the stall is synthetic (the intent's own test method) and that the unit layer runs on throwaways only (Rule 21).

## Design Notes

**Governing ADs:** AD-12 (the closed status catalog with its slots, computed on read in `/state` and published as `status` events by `StatusMonitor`; full-view payloads, published after commit through `Live.Publish`), AD-18 (`StatusMonitor`, `CallInterval` 15 s, publishes `heartbeatStalled` when the last tick is more than 3 minutes old; the last tick lives in `StatusMark`, read by `StatusMonitor` and `/state`; `Data.Time` is the only converter), AD-33 (`StatusMonitor` is the one `status` publisher; Lane B owns `Status`, `StatusMonitor`, `StatusMark` and `Heartbeat`), AD-5 (no schema change; the monitor's memory is not durable), AD-22 (tests in `OcuTalon.Test.Schedule`, shard `lane-b`, on throwaways; Playwright specs under `web/e2e/`; demo-path `notBuilt`), AD-29 (Lane A's `Checks` and `WatchOps` are not built, so AC 3 uses fixture rows), AD-28 (check rows come only from `Checks`; this story only gives the late mark a real source). Conventions: "Status marks", "Live events", "Announcements and focus", "Times", "Tests".

**Integration ACs:** AC 1: the consumers `StatusMonitor` (the production's real job, publishing on the instance stream) and `/state` (`Web.Api.StateBody`) read the condition. AC 2: the page (Epic 2's banner stack, rail and announcer) reads the real `/state` and instance stream, in a real browser against a real stack.

**Consumes:** `StatusMark.Get` and `Heartbeat.TICKMARK` (Story 8.1); `HeartbeatTask.OnTask` (8.1); `Status.Computed` and `Active`, `StatusMonitor` and `StatusSlots` (Story 2.10); the banner, the rail's "(late)" and the announcer (Stories 2.10, 2.8, 2.12); `Data.Time` (Epic 0); `RunnerFixture.RunningReason` (Lane A, tests only); `Test.Data.Fixture.Check` through `seedCheck` (tests only).

**Consumed-by:** Epic 12's `telegramPaused` and Epic 16's `allowance` and `resetSoon` join `Status.Computed` beside `heartbeatStalled`, in catalog order. The integration switch of AC 3 (after Epics 5 and 8 merge) replaces the fixture block with the real watch.

**Extend, don't copy:** `HeartbeatStalled` follows its siblings `DailyCap` and `NoModelKey` in `Status`; `Stalled`, `Reading` and `STALLSECONDS` extend 8.1's `Heartbeat`. `StallFixture` copies the pattern of 8.1's `Test.Schedule.Heartbeat.HoldTask`/`ResumeTask`, not their code: those hold the heartbeat lock in the test's own process for the class's whole run, while the browser spec calls each step in a separate `iris session`, so the fixture keeps its state in a global and only waits out a run in flight. `Stalled.cls`'s session cleanup follows `Test.Core.StatusMonitor.Clean`. The browser spec follows `banners.spec.ts`'s applied-then-one-second pattern.

**Decided in-stage:**
- The shape the shared-file ruling forces: `Computed` takes the heartbeat reading itself when its third argument is omitted, so `StatusMonitor.cls` and `Web/Api.cls` stay untouched. The cost: `StatusMonitorProbe` can't inject the heartbeat, so `Test.Core.StatusMonitor` relies on the fresh-mark rule. Moving the reading into `StatusMonitor`'s `Readings` seam would be a later refactor, after Epic 4 merges.
- "Within one live update" after a real tick counts from `StatusMonitor`'s publish of the clear (at most 15 s after the tick), as NFR-9 measures from "being sent" and as AC 2's onset clause words it. A 2 s bound from the tick itself would need a second `status` publisher (against AD-33) or a `CallInterval` shorter than AD-18's 15 s.
- An unreadable tick mark is off, as HeartbeatIn reads it, so no banner can read "last ran at ." (only HeartbeatIn writes the mark, from `NowUtc`).
- "More than 3 minutes" is more than 180 whole seconds by `Data.Time.Seconds`.
- AC 2's browser test lives in a new folder, `web/e2e/heartbeat/`, in project `chromium`: the only browser unit whose specs reach IRIS and have fixture users. It reuses the banners fixture user (one worker, so no overlap), so `docker/tests/test-sign-in.sh` (contended) needs no change. It causes two real `status` events on the instance stream; `api.spec`, which pins that stream at one event, runs earlier in Playwright's path order.
- AC 3's block: the existing `notBuilt('the "Orders production" check row shows a real last run', '8.2')` line is kept unchanged (lead ruling: Epic 4's lines while it runs), so it keeps skipping with "Story 8.2 turns this on". The appended test has its own title (Playwright refuses two tests with one title in a file) and its imports use local aliases. Its real part is the server's `/state` status (no `heartbeatStalled`), which the interception passes through untouched.
- `StallFixture.Hold` waits for a clock second between 5 and 45 before it moves the mark, so a Task Manager run dispatched at the minute boundary has finished and can't overwrite the test's mark.
- 8.1's `Restore()` now ends with a real tick, instead of leaving the found mark, which may be minutes old after the class's run.
- Decided in-stage (implement): `StallFixture.WAITCLOCK` is 21 s, not the 16 s that the task line names, because the longest wait from clock second 46 to second 5 of the next minute is 19 s. `Release` kills its node only when the task was put back, so a failed save never loses the found `Suspended` value. `heartbeat.spec.ts` fails the test when `Release` does not answer `1`. The appended 02-watch test skips with "Story 8.2 needs the first-start stack (OCUTALON_URL)..." when `OCUTALON_URL` is unset, because `web/scripts/demo-path-summary.test.mjs` (`npm --prefix web test`) runs the demo-path project without a stack and expects every step to read skipped; with a stack the test runs. That test file is unchanged.
- Matrix coverage (audit): never ticked, `TestNoTickIsOff` and `TestStalled`; fresh, boundary 180 s, 181 s, 240 s, unreadable, clock moved back and no usable reading, `TestStalled` and `TestStalledCondition`; real tick after a stall, `TestStateAndMonitor` and `heartbeat.spec.ts`; restart after a long stop, the first-run rule is Epic 2's `Test.Core.StatusMonitor`, and the catch-up tick's clear is `TestStateAndMonitor`.

**For the lead (not this story's work):** the real switch of AC 3 has no owning story yet. On the integration branch, once Epics 5 and 8 have merged, someone replaces the `notBuilt(..., '8.2')` line with the real assertion (the guide's watch prompt makes the "Orders production" check, and `Checks` records its last run on real ticks) and drops the fixture block. It needs a ledger entry routed to the owner of that integration.

**Task 0 measurements (implement stage, warm throwaway e8s2iw):**
- (a) `StatusMonitor`'s job is found in the platform's job status by `$$$EnsJobStatus($$$SystemName, job, $$$eJobStartConfigName)` = `StatusMonitor`, and its registration time is `$$$eJobRegTime` (UTC, to the millisecond). Measured: one such job, registered when the production started, about 4 minutes before the first call. The signal `StallFixture.Hold` waits for is the newest `StatusMonitor` job registered at least `CALLINTERVAL` + 2 = 17 s ago (`MonitorAge`); a restart of the job registers a new job and so resets the wait. That `OnProcessInput` runs at the job's start and then every 15 s is (inference), from `Ens.InboundAdapter.OnTask` (it calls `ProcessInput` and then sets `%WaitForNextCallInterval`) and the production's `CallInterval` 15; not observed at a job start, because that needs a job restart. The cadence is measured below.
- (b) Measured on one run: `Hold(240)` returned at once (the job was older than 17 s, the clock second inside the window, the lock free); `StatusMonitor` published the onset 4.6 s after `Hold` returned; after `Tick()` its clear was published 15.1 s later (it had just run before the tick, so this is the worst case of a 15 s interval plus the run). Both are inside the 30 s the tests wait. `Test.Schedule.Stalled` takes 17 to 27 s as a class on the warm stack.

**Lead's spec gate (2026-10-25, runner C):**
- Confirmed (ruling, decide): "within one live update" after a real tick counts from `StatusMonitor`'s publish of the clear, as decided in-stage above (NFR-9 measures from "being sent"; AD-33 keeps one `status` publisher; AD-18 fixes the 15 s interval).
- The real switch of AC 3 is filed as DW-202, routed to Story 11.1 (`11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test`, which turns every UJ-1 step spec on); not this story's work.
- Footprint extensions accepted (orchestrator standing ruling: uncontended paths, reported): `Live/Payload/Status.cls`, `Test/Live/Status.cls` (Epic 2's merged files; no running epic's footprint), and the new `web/e2e/heartbeat/heartbeat.spec.ts` (Playwright project `chromium` picks it up with no config change; `docker/tests/test-sign-in.sh` unchanged).
- Runtime: every destructive or production-running check is on lane C throwaways (`ci/iris.sh`, warm and fresh); slot C is read-only for this story.

**Ledger inbox:** none (`LEDGER slice` of this story's key is empty; no `DW-n` to address or decline).

**Footprint extensions to report:** `src/ocutalon/cls/OcuTalon/Live/Payload/Status.cls` and `src/ocutalon/cls/OcuTalon/Test/Live/Status.cls` (both Lane B's, Epic 2's merged files, contended by no running epic), and the new `web/e2e/heartbeat/heartbeat.spec.ts`. No change to `web/src/app/{banners,rail}/**`.

## Verification

Every `ci/iris.sh` and `ci/warm.sh` call carries `L="OCUTALON_LOCK_DIR=<the lane-c lock folder named in the dispatch> OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=8 stage=<stage>'"`, written out in full on each call, one call per tool call, in the foreground with `timeout: 600000`. Tags: fresh `e8s2i` and warm `e8s2iw` for implement; every other stage uses its own tag starting `e8s2`.

**Commands:**
- `(once, first)` `$L OCUTALON_RUN_TAG=e8s2iw ci/warm.sh up` -- expected: the warm stack is ready.
- `(loop)` `$L OCUTALON_WARM=1 OCUTALON_RUN_TAG=e8s2iw ci/iris.sh class OcuTalon.Test.Schedule.HeartbeatLogic` -- expected: `CLASS ... passed`.
- `(loop)` the same command for `OcuTalon.Test.Schedule.Stalled` (about 30 to 60 s) -- expected: passed.
- `(loop)` the same command for `OcuTalon.Test.Live.Status`, then `OcuTalon.Test.Core.StatusMonitor`, then `OcuTalon.Test.Web.Api`, one per call -- expected: passed.
- `(loop)` the same command for `OcuTalon.Test.Schedule.Heartbeat` (140 to 190 s) -- expected: passed.
- `(loop)` `npm --prefix web run lint` -- expected: exit 0.
- `(once)` `$L OCUTALON_RUN_TAG=e8s2i ci/iris.sh build` -- expected: built.
- `(once)` `$L OCUTALON_RUN_TAG=e8s2i ci/iris.sh shard lane-b`, then `shard lane-b --reverse`, then `shard lane-a`, one per call (`lane-b` about 6 minutes fresh) -- expected: every `CLASS` line passed.
- `(once)` `$L OCUTALON_RUN_TAG=e8s2i ci/iris.sh live sign-in` (about 420 s before this story plus about 40 s; its local deadline is 540 s; record the time) -- expected: passed, `heartbeat.spec.ts` included.
- `(once)` `$L OCUTALON_RUN_TAG=e8s2i ci/iris.sh live demo-path` -- expected: passed, with `STEP 2 watch: partly skipped, 1 passed, 3 skipped`.
- `(once)` `npm --prefix web test`, then `bash ci/checks.sh` -- expected: all pass.
- `(once, last, also after a failure)` `$L OCUTALON_RUN_TAG=e8s2iw ci/warm.sh down`, then `$L OCUTALON_RUN_TAG=e8s2i ci/iris.sh teardown`.

**Mutations (Rule 19; record each one here as `mutation: <change> -> <test that went red>`):**
- mutation: `Heartbeat.STALLSECONDS` set to 300 -> `Test.Schedule.Stalled.TestStateAndMonitor` red (no `heartbeatStalled` in `StateBody`) (AC 1; observed on the warm throwaway, reverted byte-identical).
- mutation: `Heartbeat.Stalled` reads an empty `lastTick` as stalled -> `Test.Schedule.Stalled.TestNoTickIsOff` red (AC 1; observed, reverted).
- mutation: `HeartbeatStalled` sets the time slot to `now` -> `TestStateAndMonitor` red on the slot and the onset payload (AC 1; observed, reverted).
- mutation: `Computed` treats an omitted reading as "" -> `TestStateAndMonitor` red (AC 1; observed, reverted).
- mutation: `>` changed to `>=` in `Heartbeat.Stalled` -> `Test.Schedule.HeartbeatLogic.TestStalled` red on the 180 s rows, and `TestStalledCondition` red on the 180 s case (matrix; observed, reverted).
- mutation: `StallFixture.Release` without its `Tick()` -> `Test.Schedule.Stalled.TestReleaseLeavesFresh` red (fresh-mark rule; observed, reverted).
- mutation: `Heartbeat.Stalled` always returns 0 (a `Quit 0` as its first line, ahead of the empty-tick guard) -> `heartbeat.spec.ts` red in `live sign-in` (AC 2; observed in `live sign-in`: only `heartbeat.spec.ts` H1 red, 192 others passed; reverted byte-identical, then green in 439 s).
- mutation: `Heartbeat.Stalled` always returns 1 (a `Quit 1` as its first line, ahead of the empty-tick guard: the demo-path stack has no tick mark yet, so a `Quit 1` after the guard survives) -> the appended 02-watch test red in `live demo-path` (AC 3; observed: `not.toContain` on the real `status` failed; reverted byte-identical, then green).

**Shared surfaces:** `Status.Computed`'s list (now three conditions; `Test.Live.Status`, updated); `/state`'s `status` array and the instance stream's `status` events (`Test.Web.Api.TestStateBody`, unchanged and green; `Test.Core.StatusMonitor`, whose probe now reads the real heartbeat; `web/e2e/api/api.spec.ts`, which pins the instance stream at one event and runs before `heartbeat/`; `docker/tests/test-sign-in.sh`'s seeded instance event, written before any spec; the banners specs, which expect only the no-key banner from the snapshot, while the sign-in stack's heartbeat stays fresh); the `heartbeatTick` mark (8.1's `Restore()` and `StallFixture.Release()` leave it fresh); the demo-path step 2 summary (from skipped to partly skipped); `live:sign-in`'s run time; `^OcuTalonTest("StallFixture")`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `Status.Computed` now computes `heartbeatStalled` (after `noModelKey`) from the tick mark and the clock through new `Heartbeat.Reading()`, `Heartbeat.Stalled()` and `Heartbeat.STALLSECONDS` (180), so `/state` and `StatusMonitor` report the real condition with no edit to either shared file.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Schedule/Heartbeat.cls`: `STALLSECONDS`, `Reading`, `Stalled`, stalled rule in the class doc.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Status.cls`: `Computed(keys, budget, heartbeat)`, private `HeartbeatStalled`, docs.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/StallFixture.cls` (new): cross-process hold, wait, tick and release of the real heartbeat.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/Stalled.cls` (new): AC 1 on the real task, mark and `StatusMonitor` job.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/HeartbeatLogic.cls`: `TestStalled`, `TestStalledCondition`.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls`: `Restore()` ends with one real tick.
- `src/ocutalon/cls/OcuTalon/Test/Live/Status.cls`: fixed-reading calls pass "" and expect three conditions.
- `web/e2e/heartbeat/heartbeat.spec.ts` (new): AC 2 in a real browser.
- `web/e2e/demo-path/02-watch.spec.ts`: one appended block (AC 3, fixture row).

**Review.** 24 findings: patches applied 6 rows in 5 fixes (all low: clock-wait ceiling, which two layers reported, `Release` kills its node only on success, two-sided mark assertion, `finally` fails on a bad release, class doc), deferred 0, rejected 18 with their reasons in the triage log. Patched entries by verdict: low 6, medium 0, high 0.

**Follow-up review recommended:** false.

**Verification performed** (warm `e8s2iw`, lane C): `HeartbeatLogic`, `Stalled` (17-28 s), `Test.Live.Status`, `Test.Core.StatusMonitor`, `Test.Web.Api`, `Test.Schedule.Heartbeat` (140-188 s) passed (after the last patch `Stalled`, `HeartbeatLogic` and `Heartbeat` were re-run, and the lane shards ran every class again); `npm --prefix web run lint` exit 0. Fresh `e8s2i`: build; `shard lane-b` (45 classes, 316 s), `lane-b --reverse` (299 s) and `lane-a` (41 classes, 357 s) all passed; `live sign-in` passed in 439 s with `heartbeat.spec.ts` (the first run failed only on this pass's own `Release` check, which compared "1 " with "1"; fixed with a trim, then green); `live demo-path` passed with `STEP 2 watch: partly skipped, 1 passed, 3 skipped`; `npm --prefix web test` 565 passed (it failed once on the new demo-path test running with no stack, fixed by the skip noted under Design Notes); `bash ci/checks.sh` passed. Mutations: all eight lines under Verification observed red and reverted byte-identical. LOCK lines: `LOCK acquired warm-iris project=ocutalon-warm-e8s2iw-1792933096-64102`, then the fresh `throwaway-iris` locks of the shards and live units, each released. Teardown of `e8s2iw` and `e8s2i` done.

**Residual risks.** The stall is synthetic (task suspended, mark moved back), as the spec's method; `Test.Core.StatusMonitor` and `Test.Web.Api` read the real heartbeat and rely on the fresh-mark rule; `Restore()`'s closing tick may record a gap mark (accepted, VG-O7); `Hold` and `Release` suspend and resume the real task, for throwaways and CI only.

