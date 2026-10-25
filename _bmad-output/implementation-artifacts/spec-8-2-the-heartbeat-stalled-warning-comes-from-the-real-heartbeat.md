---
title: 'Story 8.2: The heartbeat-stalled warning comes from the real heartbeat'
type: 'feature'
created: '2026-10-25'
status: 'ready-for-dev'
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
- [ ] Task 0 (implement stage, warm throwaway; record the results under Design Notes, labelled measured or (inference)): (a) confirm that `StatusMonitor`'s job runs `OnProcessInput` at its start and then every `CallInterval` (15 s), and choose the signal that `StallFixture.Hold` waits for before it moves the mark, so that the job's silent first run never swallows the change (candidate: the item's job registration time `$$$EnsJobStatus($$$SystemName, job, $$$eJobRegTime)` at least `CallInterval` + 2 s in the past); (b) record the time from `Hold(240)` to `StatusMonitor`'s publish and from `Tick()` to the clear.
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/Heartbeat.cls` -- add `Parameter STALLSECONDS = 180`, `ClassMethod Reading() As %DynamicObject` (`{"lastTick": StatusMark.Get(TICKMARK), "now": Data.Time.NowUtc()}`) and `ClassMethod Stalled(lastTick As %String, now As %String) As %Boolean` (pure; the matrix); the class doc states the stalled rule -- the heartbeat's own rules stay in its class.
- [ ] `src/ocutalon/cls/OcuTalon/Live/Payload/Status.cls` -- `Computed(keys, budget, heartbeat)`: after `NoModelKey`, insert `..HeartbeatStalled(<heartbeat when given, else Heartbeat.Reading()>)` (the argument's `$Data` decides); add the private `HeartbeatStalled(heartbeat)` beside `DailyCap`; update the class, `Computed` and `Active` doc comments (contract only) -- one computation for `/state` and `StatusMonitor`, with no edit to either shared file.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/StallFixture.cls` (new; no Test methods; the product never refers to it) -- class methods that work across processes (the browser spec calls each one in its own `iris session`), with their state under `^OcuTalonTest("StallFixture")`:
  - `Hold(secondsBack)` suspends the real task (remembering its `Suspended` value the first time), waits (up to 16 s) until the clock second is between 5 and 45, takes and releases `Heartbeat.#LOCK` (10 s) to wait out a run in flight, waits for Task 0 (a)'s signal, then sets the tick mark to now - `secondsBack` (or removes it when `secondsBack` is "") and returns the mark;
  - `InstanceSeq()` is `Live.Publish.LastSeq` of the instance stream;
  - `WaitEvent(after, active, seconds = 30)` returns the Seq of the first `status` event on the instance stream after `after` whose payload is `heartbeatStalled` with that `active`, or 0 (polling every 0.5 s);
  - `Tick()` runs `HeartbeatTask.OnTask()`;
  - `Release()` resumes the task with the remembered value, kills its node and runs `Tick()`.
  One fixture serves the unit test and the browser spec.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/Stalled.cls` (new; needs the running production; throwaways and CI only, like 8.1's `Heartbeat`) -- `OnBeforeAllTests` requires `RunnerFixture.RunningReason()` = ""; `OnAfterOneTest` and `OnAfterAllTests` call `StallFixture.Release()` and delete the `zzstall*` fixture sessions with their events and counters. Methods: `TestStateAndMonitor` (AC 1, the onset and the clear; the only method that stalls, and it waits for its own clear), `TestNoTickIsOff` (AC 1), `TestReading` (after `Hold(100)`, `Reading()` holds the mark and a time within 2 s of now), `TestReleaseLeavesFresh` (after `Hold(100)` and `Release()`, the mark is at most 5 s old, the task's `Suspended` is the value found and the fixture's node is gone).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/HeartbeatLogic.cls` -- add `TestStalled` (every matrix row through `Heartbeat.Stalled`) and `TestStalledCondition` (`Status.Computed` with an injected reading: the order `dailyCap,noModelKey,heartbeatStalled`; the exact exported JSON on and off; a reading of "" or a non-object is off; `ActiveOf` holds it only when on) -- pure, no production.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` -- `Restore()`: after `ResumeTask()`, when `OcuTalon.Production` runs, run one real tick (`HeartbeatTask.OnTask()`) and append its status, so the class ends with a fresh mark; the gap that tick records is the honest one that 8.1 accepted (VG-O7) -- the fresh-mark rule for the classes that read the real heartbeat after it.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Live/Status.cls` -- `TestComputedOrder` passes "" as the heartbeat reading and expects `dailyCap,noModelKey,heartbeatStalled` with actives `110` and `000`; the two fixed-reading `Computed` calls of `TestActive` pass "" (still 2 active and 0 active); its comparison of `Active` with `ActiveOf(Computed(keys, budget))` stays two-argument (both read the real heartbeat) -- shared surface (Rule 19).
- [ ] `web/e2e/heartbeat/heartbeat.spec.ts` (new; project `chromium`, run by `live:sign-in` after `api/`) -- one test, with `test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-GB' })` and a 90 s timeout, as the banners fixture user:
  - seed a production check (`seedCheck`, a unique name, last run 60 s ago, passed), `recordAnnouncements`, sign in, and wait for the loaded page with no `heartbeatStalled` banner and the row's meta "Last run {time} · Passed";
  - `since` = `InstanceSeq()`, `mark` = `Hold(240)`, `seqOn` = `WaitEvent(since, 1, 30)` (not 0); once `data-instance-seq` >= `seqOn`, within 1 s: the banner reads exactly "Background checks have paused: the heartbeat last ran at {mark as the page shows it}. Watches and reminders may be late until it recovers." (the time formatted as `pageTime` formats it), the row reads "Last run {time} (late) · Passed", and the announcer read the banner text once; a `GET /ocutalon/api/v1/state` through the page's own session (`page.request`) answers a `status` array holding `{"condition":"heartbeatStalled","active":true,"slots":{"time":"<mark>"}}`;
  - `Tick()`, then the same `GET` answers no `heartbeatStalled` member; `seqOff` = `WaitEvent(seqOn, 0, 30)` (not 0); once applied, within 1 s the banner is gone and the row reads "Last run {time} · Passed"; the banner text was announced exactly once in the whole test;
  - `finally`: `Release()` and `cleanFixtureRows`.
  This is the real-runtime test (Rule 3); the middle dot is written as an escape (Rule 14).
- [ ] `web/e2e/demo-path/02-watch.spec.ts` -- append one self-contained block at the end, with its own imports under local aliases (`heartbeatTest`, `heartbeatExpect`, `heartbeatSnapshot`, `heartbeatSignIn`), so they never clash with names that lines Epic 4 adds import: a `describe` titled for Story 8.2 with one test whose title differs from the `notBuilt` line's. `heartbeatSnapshot` answers `/state` with the real answer, keeps the real `status` array, and puts one fixture check in `rail.checks` (`ref` `zz-fixture-orders`, `kind` `production`, `displayName` `Orders`, `lastRunAt` 30 s ago, `result` `passed`); `heartbeatSignIn`; then assert that the real `status` holds no `heartbeatStalled`, that the "Orders production" row's meta matches `Last run <time> · Passed` with no "(late)", and that no `heartbeatStalled` banner shows -- AC 3, fixture-backed.

**Acceptance Criteria:**
1. Given the production running, the real task held by `StallFixture` and a fixture session, when the tick mark is set 240 s back, then `Web.Api.StateBody(session).status` holds exactly one `heartbeatStalled` member, `{"condition":"heartbeatStalled","active":true,"slots":{"time":"<mark>"}}`, and `StatusMonitor`'s real job publishes that payload as a `status` event on the instance stream within 30 s. When `StallFixture.Tick()` then writes a real tick, `StateBody` holds no `heartbeatStalled` at once, `StatusMonitor` publishes `{"condition":"heartbeatStalled","active":false}` within 30 s, and no `heartbeatStalled` event lies between that onset and that clear. With no tick mark, `StateBody` holds no `heartbeatStalled`. (FR-32, AD-12, AD-18, AD-33)
2. Given the banners user's page open on the sign-in stack with a seeded production check, when the tick mark is set 4 minutes back and `StatusMonitor`'s next run publishes the condition, then within one live update of the page applying that event the heartbeat-stalled banner shows the tick's time, the check row reads "Last run {time} (late)", the announcer reads the banner once, and `GET /ocutalon/api/v1/state` of that session holds `heartbeatStalled` with the tick's time as its slot; and when a real tick is written, then `/state` holds no `heartbeatStalled` at once, and within one live update of the page applying `StatusMonitor`'s clear, the banner and the "(late)" mark are gone. (FR-32, NFR-9, AD-12, UX-DR99, UX-DR132)
3. Given the demo-path stack (a first start with the CI mock), when step 2's appended Story 8.2 test answers `/state` with a fixture "Orders production" check row, then the row shows "Last run {time} · Passed" with no "(late)" mark and no heartbeat banner, while the real `/state` status holds no `heartbeatStalled`. The existing `notBuilt(..., '8.2')` line stays as it is until the real switch on the integration branch. (FR-33, REL-2, AD-29, UX-DR53)

## Spec Change Log

## Review Triage Log

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

**For the lead (not this story's work):** the real switch of AC 3 has no owning story yet. On the integration branch, once Epics 5 and 8 have merged, someone replaces the `notBuilt(..., '8.2')` line with the real assertion (the guide's watch prompt makes the "Orders production" check, and `Checks` records its last run on real ticks) and drops the fixture block. It needs a ledger entry routed to the owner of that integration.

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
- AC 1: `Heartbeat.STALLSECONDS` set to 300 -> `TestStateAndMonitor` red (no `heartbeatStalled` in `StateBody`, no event). Also: `Stalled` reads an empty `lastTick` as stalled -> `TestNoTickIsOff` red; `HeartbeatStalled` sets the slot to `now` -> the slot assertion red; `Computed` treats an omitted reading as "" -> `TestStateAndMonitor` red.
- Matrix: `>` changed to `>=` -> `HeartbeatLogic.TestStalled` red on the 180 s row.
- AC 2: `Heartbeat.Stalled` always returns 0 -> `heartbeat.spec.ts` red in `live sign-in` (one red run, then green after the revert).
- AC 3: `Heartbeat.Stalled` always returns 1 -> the appended 02-watch test red in `live demo-path`.
- Fresh-mark rule: `StallFixture.Release` without its `Tick()` -> `TestReleaseLeavesFresh` red.

**Shared surfaces:** `Status.Computed`'s list (now three conditions; `Test.Live.Status`, updated); `/state`'s `status` array and the instance stream's `status` events (`Test.Web.Api.TestStateBody`, unchanged and green; `Test.Core.StatusMonitor`, whose probe now reads the real heartbeat; `web/e2e/api/api.spec.ts`, which pins the instance stream at one event and runs before `heartbeat/`; `docker/tests/test-sign-in.sh`'s seeded instance event, written before any spec; the banners specs, which expect only the no-key banner from the snapshot, while the sign-in stack's heartbeat stays fresh); the `heartbeatTick` mark (8.1's `Restore()` and `StallFixture.Release()` leave it fresh); the demo-path step 2 summary (from skipped to partly skipped); `live:sign-in`'s run time; `^OcuTalonTest("StallFixture")`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned only (halt after planning). Baseline: `0818594182c4501edcc71eedc75db5b2a6f668ee` (branch `OCT-epic8`). No IRIS instance was touched and nothing was implemented.
