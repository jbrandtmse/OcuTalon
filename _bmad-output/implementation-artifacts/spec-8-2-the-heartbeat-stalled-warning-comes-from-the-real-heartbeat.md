---
title: 'Story 8.2: The heartbeat-stalled warning comes from the real heartbeat'
type: 'feature'
created: '2026-10-25'
status: 'done'
baseline_revision: '9d8834dd000e3a6963d3c68796049da2dae06b75'
baseline_commit: '9d8834dd000e3a6963d3c68796049da2dae06b75'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
warnings: [oversized]
deferred:
  - summary: >-
      Any spec that seeds a production check row with no NextDueAt can have the row run by a real heartbeat tick (the minute task, or a fixture that calls HeartbeatTask) since Story 5.6, which overwrites its last run, result and finding.
    evidence: |-
      Checks.Process.Due runs every production row whose NextDueAt is empty or at most 5 s after the tick. Story 8.2's H1 was red on the merged tree for this reason and now seeds NextDueAt an hour ahead through the new optional seedCheck field nextDueAt. Callers of seedCheck that seed without it: web/e2e/answers/close-loop.spec.ts, web/e2e/banners/banners.spec.ts, web/e2e/floor/focus.spec.ts, web/e2e/floor/guide.spec.ts, web/e2e/rail/rail.spec.ts, web/e2e/trace/links.spec.ts and the helper in web/e2e/support/floor.ts. Specs that call OcuTalon.Test.Data.Fixture.Check directly with no NextDueAt: web/e2e/session/session.spec.ts (lines 68 and 303; S1 compares the whole rail before and after, so a tick between its two reads changes the row) and web/e2e/demo-path/04-incident.spec.ts (line 61, a row on the real OCUORDERS production, where a real run may be what that spec wants). The Story 8.2 block of web/e2e/demo-path/02-watch.spec.ts is not affected: its row exists only in the intercepted /state answer, never in the database.
    location: >-
      web/e2e (the files named in the evidence; other epics' specs, not changed by this story)
    severity: medium
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

- [x] [CI] web: Unit tests (`npm --prefix web test`, `web/scripts/demo-path-summary.test.mjs` "skip every unbuilt part with a story, so that each step reads skipped") red on the story commit ffd7530: that test runs `playwright test --project=demo-path` with no stack and no browser installed (the hosted `web` job installs none), and the appended Story 8.2 test in `web/e2e/demo-path/02-watch.spec.ts` calls `heartbeatTest.skip(!process.env['OCUTALON_URL'], ...)` inside its body, after the `page` fixture has launched a browser, so the launch fails and Playwright exits 1 -- https://github.com/jbrandtmse/OcuTalon/actions/runs/40206917294 (job web, 121209725059) -- the fix must skip without starting any fixture when `OCUTALON_URL` is unset (for example the same `heartbeatTest.skip(...)` as the first statement of the story's own `describe` callback, not inside the test body), changing only the story's appended block (no existing line of the file above it), keep the skip text starting "Story 8.2" (the demo-path summary reads it), and prove it: `PLAYWRIGHT_BROWSERS_PATH=/nonexistent-e8 node --test --test-name-pattern='skip every unbuilt part' web/scripts/demo-path-summary.test.mjs` red before, green after (lead reproduced the red locally), then `npm --prefix web test` green and `live demo-path` still runs the test (passes) on the stack.

**Acceptance Criteria:**
1. Given the production running, the real task held by `StallFixture` and a fixture session, when the tick mark is set 240 s back, then `Web.Api.StateBody(session).status` holds exactly one `heartbeatStalled` member, `{"condition":"heartbeatStalled","active":true,"slots":{"time":"<mark>"}}`, and `StatusMonitor`'s real job publishes that payload as a `status` event on the instance stream within 30 s. When `StallFixture.Tick()` then writes a real tick, `StateBody` holds no `heartbeatStalled` at once, `StatusMonitor` publishes `{"condition":"heartbeatStalled","active":false}` within 30 s, and no `heartbeatStalled` event lies between that onset and that clear. With no tick mark, `StateBody` holds no `heartbeatStalled`. (FR-32, AD-12, AD-18, AD-33)
2. Given the banners user's page open on the sign-in stack with a seeded production check, when the tick mark is set 4 minutes back and `StatusMonitor`'s next run publishes the condition, then within one live update of the page applying that event the heartbeat-stalled banner shows the tick's time, the check row reads "Last run {time} (late)", the announcer reads the banner once, and `GET /ocutalon/api/v1/state` of that session holds `heartbeatStalled` with the tick's time as its slot; and when a real tick is written, then `/state` holds no `heartbeatStalled` at once, and within one live update of the page applying `StatusMonitor`'s clear, the banner and the "(late)" mark are gone. (FR-32, NFR-9, AD-12, UX-DR99, UX-DR132)
3. Given the demo-path stack (a first start with the CI mock), when step 2's appended Story 8.2 test answers `/state` with a fixture "Orders production" check row, then the row shows "Last run {time} · Passed" with no "(late)" mark and no heartbeat banner, while the real `/state` status holds no `heartbeatStalled`. The existing `notBuilt(..., '8.2')` line stays as it is until the real switch on the integration branch. (FR-33, REL-2, AD-29, UX-DR53)

- [x] [CI] browser: `live:sign-in` red on `af61733`, the first push of Epic 8's merged tree (merge `8d5f805` brought in Epic 5's Story 5.6, "the production watch runs on every heartbeat"). `web/e2e/heartbeat/heartbeat.spec.ts:89` H1 fails at line 124 ("and so is the late mark"): expected `/^Last run (?:\S.* at )?18:43 · Passed$/`, received "Last run 18:44 · No read access to its namespace · Trace (opens in a new tab)" -- https://github.com/jbrandtmse/OcuTalon/actions/runs/40692572200 (job `iris (browser)`). Cause, read from the code: `StallFixture.Tick()` runs the real `HeartbeatTask`, whose tick now goes to `OcuTalon.Checks.Process`. That runs every `BackgroundCheck` row of Kind production whose `NextDueAt` is empty or at most 5 s after the tick (`Due()`). H1's seeded row (`seedCheck`, namespace `ZZNS`) has no `NextDueAt`, so the real tick ran it, recorded a new `LastRunAt` and the namespace finding, and the row no longer reads H1's seeded run. The real minute task can do the same to the row before the stall.
  The fix keeps H1's intent (the banner and the late mark follow the real heartbeat and clear on a real tick) and makes its fixture row not due for the whole case: seed it with a `NextDueAt` well after the case (for example now plus one hour). Either H1 sets it right after `seedCheck` in the spec itself, or `seedCheck` gains an optional `nextDueAt` field (`web/e2e/support/iris.ts`, additive, with no change for other callers). Never edit `src/ocutalon/cls/OcuTalon/{Checks,Watch,Agent,Tools,Fix}/**` or `src/bridge/**`.
  Check this story's other test that seeds or asserts a check row's last run (`web/e2e/demo-path/02-watch.spec.ts`, the Story 8.2 block) for the same hazard, and fix it the same way if it applies. Do not change other epics' specs; report the general hazard (any spec that seeds a production check row with no `NextDueAt` can be run by the real minute tick since Story 5.6) under `deferred:`.
  Prove it on the merged tree, after `ci/iris.sh build`: the part of `live sign-in` that holds `heartbeat.spec.ts` red before the fix (or, if the red does not reproduce, the mutation "H1 seeds no `NextDueAt`" with a `Tick` makes it red) and green after; then the other part, and `live demo-path` if `02-watch.spec.ts` changed. Each changed pinning assertion gets its `mutation:` line.

### Review Findings

Code review 2026-10-25 (first review; tier full-opus, layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor): 31 rows, 13 entries after grouping, 9 rows rejected. Each entry: severity | fix-risk | footprint | disposition. Rule 3 (H1 is the real-runtime test), Rule 1, Rule 5, Rule 6 (AD-12, AD-18, AD-33 matched) and Rule 14 checked with no finding.

- [x] [Review][Patch] `TestMonitorStartsOnStaleMark` set the real mark 240 s back without waiting for the production's own StatusMonitor, so an onset that job published and its later clear could land in `TestStateAndMonitor`'s window before the onset (an order-dependent red), and the class doc called `TestStateAndMonitor` the only test that stalls [src/ocutalon/cls/OcuTalon/Test/Schedule/Stalled.cls:99] -- med | low (test only) | in-story | fixed: it takes `since` before `Hold` and ends with `RealClear(since)`, which waits for that job's clear when it published an onset; class doc corrected.
- [x] [Review][Patch] `heartbeat.spec.ts` released the heartbeat only in the test body's `finally`, which Playwright abandons on a timeout (it runs afterEach and teardown in their own slot and does not await the body), so the sign-in stack could keep the task suspended and the mark 240 s back for every later spec; a failed `Release` there also replaced the body's error [web/e2e/heartbeat/heartbeat.spec.ts:82] -- med | low | in-story | fixed: `Release` and `cleanFixtureRows` run in `test.afterEach`; header comment corrected.
- [x] [Review][Patch] Rule 2: `heartbeat.spec.ts` re-declared `mainOf`, `rowOf`, `unique` and a banner locator that `web/e2e/support/floor.ts` exports [web/e2e/heartbeat/heartbeat.spec.ts:5] -- med | low | in-story | fixed: it imports `banner`, `mainOf`, `rowOf` and `unique` from `../support/floor`.
- [x] [Review][Defer] `heartbeat.spec.ts` leaves two instance-stream `status` events, and `api.spec.ts` (a Shared surface) still pins the instance stream at one event, green only because `api/` runs before `heartbeat/` [web/e2e/api/api.spec.ts:121] -- med | low | out-of-footprint | deferred: DW-204 `routed owner=burndown` (api.spec is outside Epic 8's footprint and this story's accepted extensions).
- [x] [Review][Patch] the status of `Tick()` was thrown away in `heartbeat.spec.ts`, so a failed tick surfaced as a misleading `/state` assertion [web/e2e/heartbeat/heartbeat.spec.ts:117] -- low | low | in-story | fixed: the tick must answer `1`.
- [x] [Review][Patch] AC 2's banner text (the 10 s default) and announcer (5 s) bounds were looser than "within one live update" [web/e2e/heartbeat/heartbeat.spec.ts:110] -- low | low | in-story | fixed: the banner text within `ONE_UPDATE_MS`, the announcer within `ANNOUNCED_MS` (2 s: NFR-9's one live update, which covers the announce queue's 1 s gap after a text; 1 s would race that gap).
- [x] [Review][Patch] the exact "Last run {time}" assertions fail on a run that straddles midnight in Asia/Kolkata (18:30Z), where the rail's `pageWhen` puts a day before the time [web/e2e/heartbeat/heartbeat.spec.ts:51] -- low | low | in-story | fixed: `lastRun(ranAt, late)` allows an optional "<day> at " and still pins the time, the "(late)" mark and the result.
- [x] [Review][Patch] the AC 3 test's describe, title and message claimed a fresh heartbeat, while the demo-path stack may not have ticked yet (off as never ticked) [web/e2e/demo-path/02-watch.spec.ts:19] -- low | low | in-story (the appended block) | fixed: they now say the real status holds no heartbeatStalled; no existing line of the file changed.
- [x] [Review][Patch] `StallFixture.MonitorAge` converted the job's registration time by hand (`$$$timeUTCtoUTCH`, `$ZTimeStamp`) against the Always line "times only through Data.Time" [src/ocutalon/cls/OcuTalon/Test/Schedule/StallFixture.cls:135] -- low (UTC arithmetic on a platform timestamp, no zone conversion, so no AD-18 mismatch) | low | in-story | fixed: the time is read to the second and counted through `Data.Time.Seconds`.
- [x] [Review][Patch] `Stalled.OnAfterOneTest` only released, while the Task line also has it delete the zzstall sessions [src/ocutalon/cls/OcuTalon/Test/Schedule/Stalled.cls:38] -- low | low | in-story | fixed: it also runs `Clean()`; class doc updated.
- [x] [Review][Patch] `StallFixture`'s `WAITCLOCK` doc read as one ceiling for the clock, lock and monitor waits [src/ocutalon/cls/OcuTalon/Test/Schedule/StallFixture.cls:30] -- low | low | in-story | fixed: each wait parameter has its own doc line.
- [x] [Review][Defer] the fixture's ticks after `Hold` record synthetic `heartbeatGap.<mark>` marks that no test removes [src/ocutalon/cls/OcuTalon/Test/Schedule/StallFixture.cls:98] -- low | low | in-story | deferred: DW-205 `wontfix-theoretical` (throwaways only; `HeartbeatLogic.TestGaps` compares only 2001 gaps and `Test.Schedule.Heartbeat` saves and restores gaps); real once a reader of `Heartbeat.Gaps` runs unfiltered on such a stack.
- [x] [Review][Defer] Rule 2: `Stalled.ClearOf` and `Clean` copy `Test.Core.StatusMonitor`'s (the per-class idiom of six test classes); the Design Notes name the sibling but give no reason [src/ocutalon/cls/OcuTalon/Test/Schedule/Stalled.cls:202] -- low | med (unifying edits siblings outside the footprint) | in-story | deferred: DW-206 `wontfix-accepted`, reopen_if a change to the event table or its counter has to be repeated in each copy.

Rejected:
- `false` the 02-watch skip text is read by the demo-path summary as owned by Story 8.2: the summary fails a skip whose text names no "Story n.m" (`web/scripts/demo-path-summary.mjs:20,126`), so the wording is forced, and the test skips only in runs with no stack.
- `low` the Design Notes matrix audit and the earlier triage entry predate QA's `TestMonitorStartsOnStaleMark`: the fix edits the spec under review; QA's mutation line is a valid pin of the "Restart after a long stop" row.
- `low` `Release` and `Restore()` answer OK when `OnTask` ticks nothing: that needs a stopped or quiescent production or a 5 s lock hold while the tests run on a running production; `TestReleaseLeavesFresh` pins the fresh mark.
- `false` a `Hold` that throws is run three times by `irisScript`: `Write` prints `CHK|mark|` before the `<UNDEFINED>` on `value`, so a CHK line exists and nothing is retried; the empty mark fails the format assertion.
- `low` `Test.Live.Status.TestActive`'s last comparison reads the real heartbeat on both sides (two rows): a disagreement needs an already stalled heartbeat crossing 180 s between two back-to-back reads; the two-argument comparison is the spec's decided shape and the condition is pinned in `HeartbeatLogic` and `Stalled`.
- `false` `MonitorSettled` with a monitor whose earlier runs all threw: such a monitor is broken, and the test failing loudly (no onset) is correct.
- `false` `$Data(heartbeat)` = 10 by reference gives `<UNDEFINED>`: no caller passes the reading by reference; `StatusMonitor` and `Active` omit it and the tests pass values.
- `false` "a lastTick that is not a string: off" cannot fail: it pins the outcome, and the never-ticked mutation (an empty tick read as stalled) turns it red; the type guard is defensive and harmless.

Re-review (rework iteration 1), 2026-10-25 (tier full-opus, layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; diff `018f9b9..HEAD`, the `[CI]` item): 10 rows, 2 entries after grouping, 7 rows rejected; the acceptance-auditor found nothing. Checklist: (1) `[CI]` fixed. The skip is the first statement of the story's `describe` callback, so Playwright marks the group skipped as the file loads and no fixture starts. The skip text is unchanged and starts "Story 8.2". `git diff b4a087a` on the file shows additions after line 6 only. After the patch below, `PLAYWRIGHT_BROWSERS_PATH=/nonexistent-e8 node --test --test-name-pattern='skip every unbuilt part' web/scripts/demo-path-summary.test.mjs` is green (the `(rework 1)` mutation was re-observed red, `1 !== 0`, and reverted byte-identical), `npm --prefix web run lint` exits 0 and `npm --prefix web test` passes 565. (2) DW-204 stays `routed owner=burndown`, unchanged. Rule 3: the rework changes a test only, so it is exempt; AC 2's real-runtime test is still `heartbeat.spec.ts`, unchanged. Rules 1, 2, 5, 6 (AD-22, AD-29) and 14 checked with no finding.

- [x] [Review][Patch] the appended block's doc comment did not say why the skip sits at `describe` level, so a tidy-up that moved it back into the test would stay green locally and go red only in the hosted web job [web/e2e/demo-path/02-watch.spec.ts:17] -- low | low (comment only) | in-story (the appended block) | fixed: the doc comment says the block needs the first-start stack and, without it, skips as it is declared, before any fixture starts.
- [x] [Review][Defer] `demo-path-summary.test.mjs`'s `playwrightEnv()` leaves the machine's browsers usable, so the test that pins the skip-before-fixture rule is green wherever Chromium is installed and red only in the browserless hosted job (that is how ffd7530 passed 565 locally and failed CI) [web/scripts/demo-path-summary.test.mjs:332] -- med | low (one environment line) | out-of-footprint (`web/scripts/**`, Epic 2's) | deferred: DW-210 `routed owner=8-4-set-list-and-cancel-reminders-in-plain-words` (the next story to add a demo-path test that runs only on a stack, 03-reminder).

Rejected (re-review):
- `low` the rework triage tally says "low 5, false 0" while its list holds 4 low and 1 false: this is build-auto's triage log, so the fix edits the spec under review; cosmetic.
- `low` the rework triage log rejects "the describe-level skip hides a missing stack" because "`live demo-path` asserts `1 passed`", and that check does not exist (blind-hunter, edge-case-hunter, verification-gap). `docker/tests/test-demo-path.sh:53-58` checks only the exit codes of Playwright and the summary, and `web/scripts/demo-path-summary.mjs:30,67-74` accepts any skip text that starts "Story n.m". A stack run in which this test skipped would print `STEP 2 watch: skipped, 0 passed` and still pass; the "1 passed" was read from the log. The record is corrected here rather than in the triage log.
- `low` AC 3's test could skip on the stack with every check green (verification-gap, filed as a defer): that needs a code change to the skip condition (the stack sets `OCUTALON_URL`, which is also step 1's `baseURL`), and the fix would add a pass-count check to the demo-path unit or summary, outside the footprint. Closed `wontfix-theoretical`: it becomes real once a demo-path spec skips on a condition that a stack run can meet. Story 11.1 (DW-202) turns step 2 on for real.
- `low` the spec's Verification commands still list only `npm --prefix web test`, which cannot catch this regression: the fix is a spec edit. The root cause is DW-210, and the `(rework 1)` mutation line carries the browserless command.
- `low` "Verification performed" still says "all eight lines", and the `(rework 1)` mutation line sits above the `(QA)` and `(review)` lines: the Auto Run Result is build-auto's contract (a spec edit), and the line is labelled.

## Spec Change Log

- 2026-10-25, rework iteration 1 (trigger ci): the lead re-opened the spec for one `[CI]` item (the hosted web job's unit tests, run 40206917294).
- 2026-10-28, rework iteration 2 (trigger ci): the lead re-opened the spec for one `[CI]` item (H1 red in `live:sign-in` on the merged tree `af61733`, run 40692572200: the real tick now runs H1's due fixture check row, Story 5.6).

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

### 2026-10-25 - Review pass (rework 1, the `[CI]` item)
- verdicts: 5 findings - high 0, medium 0, low 5, false 0, maybe-false 0
- findings:
  - `[low]` `[reject]` blind: the describe-level skip hides a missing stack in CI - the skip is what the `[CI]` item asks for and it was already conditional on `OCUTALON_URL`; `live demo-path` asserts `1 passed` for this test on the stack, so a stack that loses the variable reads as `0 passed` there.
  - `[low]` `[reject]` blind: no reason for the move, doc comment and skip text wording - cosmetic; the move is the item's stated fix and the skip text must keep its "Story 8.2" start.
  - `[low]` `[reject]` verification-gap: `demo-path-summary.test.mjs` pins skip-before-fixture only where no browser is installed - the fix is in `web/scripts/**`, outside this item's allowed files; the hosted `web` job installs no browser, so CI catches a regression; `reopen_if` = a regression of this shape reaches CI again.
  - `[low]` `[patch]` verification-gap: the skip placement has no `mutation:` line - mutation applied (skip moved back into the body), red observed, reverted byte-identical; line written under `## Verification`.
  - `[false]` `[reject]` edge-case-hunter: no findings (empty list); intent-alignment: descriptive report, reading B implemented, no divergence to fix.

### 2026-10-28 - Review pass (rework 2, the H1 `[CI]` item)
- verdicts: 16 findings - high 0, medium 3, low 6, false 7, maybe-false 0
- findings:
  - `[false]` `[reject]` blind: the spec is not closed out for rework 2 (the `[CI]` box, an Auto Run Result paragraph, Shared surfaces) - the box and the paragraph are written at finalize, after the review; `seedCheck`'s additive field is not a surface other tests assert on, and a real tick reaching Checks is the Story 5.6 fact that the item itself names.
  - `[medium]` `[patch]` blind: the `deferred:` entry lists only `seedCheck` callers - `web/e2e/session/session.spec.ts:68` and `:303` and `web/e2e/demo-path/04-incident.spec.ts:61` call `Fixture.Check` directly with no `NextDueAt` (grep confirmed); the entry now names them, with why each is exposed, in the step's `summary`/`evidence`/`location`/`severity` shape.
  - `[low]` `[patch]` blind: the rework-2 mutation line is argued, not observed - the red was observed on throwaway `e8s2i3b` (95 passed, 1 failed, 312 s, `red-run.log`); the line now says so and names the green tags.
  - `[low]` `[reject]` blind: `nextDueAt` is accepted by `publishCheck`'s type and silently dropped - the doc says "seedCheck only", and `ref` already works the other way round in the same interface (publish only, ignored by `seedCheck`); no caller passes it to `publishCheck`, and the fix is a type split.
  - `[low]` `[reject]` edge-case-hunter: same `publishCheck` claim as the row above - same reason.
  - `[false]` `[reject]` edge-case-hunter: a Playwright host clock an hour away from the IRIS clock makes the row due - IRIS runs in a compose project on the host that runs Playwright, so the clock is one kernel clock, and every other time these specs seed (`lastRunAt`, `dueAt`) assumes it.
  - `[low]` `[reject]` edge-case-hunter: an empty or malformed `nextDueAt` makes the row due - the only caller passes `inMs(...)`; a format check in a test helper guards a state nobody can reach, and "" is the due state a caller could mean.
  - `[medium]` `[patch]` edge-case-hunter: the deferred entry omits the direct `Fixture.Check` seeds - same root cause and fix as the second row.
  - `[false]` `[reject]` edge-case-hunter: the `[CI]` item is still unchecked - set at finalize.
  - `[low]` `[reject]` verification-gap: H1's check that the tick did not run the row is observed only when the page applies StatusMonitor's clear, so a clear published within about 2 s of the tick can let the one-second late-mark assertion pass before the `check` event is applied - real but narrow (the monitor's phase is uniform over 15 s, so the regression still goes red in most runs, as the pre-fix run did) and met only if someone later drops `nextDueAt`; the proposed second assertion after the 1.5 s wait changes the pinning test and needs a second mutation and green run of the half for a guard on a fixture parameter.
  - `[medium]` `[patch]` verification-gap (other): the deferred entry names `seedCheck` callers only - same root cause and fix as the second row.
  - `[low]` `[patch]` verification-gap (other): the `seedCheck`-ignores-`nextDueAt` variant was not run alone - it sends the same seed script as the pre-fix tree (`properties()` drops an undefined value), so the observed red covers it; the mutation line says so.
  - `[false]` `[reject]` verification-gap (other): the bookkeeping is incomplete (the box, the Auto Run Result paragraph, the single `live sign-in` line under Verification) - the first two are finalize's; the command list is the story's earlier list, and this pass runs only the `[CI]` item's proof (lead's override).
  - `[false]` `[reject]` intent-alignment: the cause lies outside the intent (Story 5.6's due-row rule) - descriptive; the `[CI]` item is the spec's own amendment for it, and no `.cls` file changed.
  - `[false]` `[reject]` intent-alignment: the case exercises "a real tick clears the banner" with the row arranged not to run - descriptive; AC 2 pins the banner and the late mark, which follow the heartbeat, not what Checks writes into a row.
  - `[false]` `[reject]` intent-alignment: `web/e2e/support/iris.ts` is a shared file outside the original contract - the `[CI]` item names it, the change is additive and no other caller changes.

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

- (rework 1) mutation: the `heartbeatTest.skip(...)` of the appended block moved back into the test body -> `web/scripts/demo-path-summary.test.mjs` "skip every unbuilt part" red under `PLAYWRIGHT_BROWSERS_PATH=/nonexistent-e8` (`1 !== 0`, the hosted web job's failure; observed, reverted byte-identical, green again). The test depends on the browsers being absent, so the override is part of the command.

- (QA) mutation: `Computed` treats an omitted reading as "" -> `Test.Schedule.Stalled.TestMonitorStartsOnStaleMark` red (no clear published after the tick, no member in `/state`; matrix row "Restart after a long stop"; observed on warm `e8s2qw`, reverted byte-identical, class green again on the same stack).
- (review) mutation: the same `Computed` change -> `TestMonitorStartsOnStaleMark` red again after the review added `RealClear` ("while /state shows it", "the run after the tick publishes one event"; observed on warm `e8s2cw`, reverted byte-identical, class green again on the same stack in 24 s).
- (review) mutation: `Heartbeat.Stalled` always returns 0 (`Quit 0` as its first line) -> `heartbeat.spec.ts` H1 red in `live sign-in` after the review's rework of the spec (afterEach release, floor helpers, `lastRun`, tighter bounds): H1 failed at "StatusMonitor published the onset within 30 s", 192 passed, 1 skipped (a `notBuilt` line); reverted byte-identical; the same tree unmutated passed 193 in 456 s (AC 2).

- (rework 2) mutation: H1 seeds no `NextDueAt` (the tree at 9d8834d, before the fix, is exactly that mutation, and `seedCheck` ignoring `nextDueAt` sends the same seed script) -> `heartbeat.spec.ts` H1 red in `live sign-in --part 2/2` at "and so is the late mark" (observed on a lane-C throwaway, tag `e8s2i3b`, 312 s: 1 failed, 95 passed; the received meta carried a new last-run time and the namespace finding instead of the seeded run, because the real tick ran the due row); the fix was applied after that run, so there is nothing to revert; the tree with `nextDueAt` is green (tag `e8s2i3c`, part 2/2: 96 passed; tag `e8s2i3d`, part 1/2: 126 passed).

**QA additions:** `src/ocutalon/cls/OcuTalon/Test/Schedule/Stalled.cls` (QA): `TestMonitorStartsOnStaleMark` -- a `Test.Core.StatusMonitorProbe` on a private stream whose first run finds the mark 240 s back remembers it silently, `/state` shows it, and the run after a real tick publishes `{"condition":"heartbeatStalled","active":false}` once. It ends through `OnAfterOneTest` (`Release`), so the mark is fresh. No other file added; all other ACs and matrix rows already had pinning tests with observed mutations.

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

**Rework iteration 1 (the `[CI]` item).** Moved `heartbeatTest.skip(!process.env['OCUTALON_URL'], ...)` from the test body to the first statement of the story's `describe` callback in `web/e2e/demo-path/02-watch.spec.ts` (appended block only; skip text unchanged), so the run skips before the `page` fixture starts. Verified: the reproduction command red before (`1 !== 0`) and green after; `npm --prefix web run lint` exit 0 (it includes `tsc -p tsconfig.e2e.json`); `npm --prefix web test` 565 passed; one fresh `live demo-path` (lane C, tag `e8s2r`, torn down) passed with `STEP 2 watch: partly skipped, 1 passed, 3 skipped`. Review: 5 findings, patches 1 (low: the `mutation:` line), rejected 4 with reasons in the triage log; patched by verdict: low 1, medium 0, high 0. Follow-up review recommended: false (no `high` patched).

**Rework iteration 2 (the H1 `[CI]` item).** `seedCheck` (`web/e2e/support/iris.ts`) gained an optional `nextDueAt` field (written as `NextDueAt`; no change for callers that omit it), and H1 in `web/e2e/heartbeat/heartbeat.spec.ts` seeds its check with `nextDueAt` one hour ahead, so neither its `StallFixture.Tick()` nor the minute task runs the row since Story 5.6. `02-watch.spec.ts` is not affected (its row exists only in the intercepted `/state` answer) and is unchanged. The general hazard, with the callers found by `grep` (seven `seedCheck` users and three direct `Fixture.Check` seeds), is in `deferred:`. Verified (lane C throwaways, each torn down): `ci/iris.sh build`; `live sign-in --part 2/2` on the unmodified tree red at H1's late-mark assertion (`e8s2i3b`, 1 failed, 95 passed); with the fix `--part 2/2` 96 passed (`e8s2i3c`) and `--part 1/2` 126 passed (`e8s2i3d`); `npm --prefix web run lint` exit 0; `bash ci/checks.sh` and `bash docker/tests/test-boundaries.sh` passed. Review: 16 findings, patches 2 entries (a medium: the `deferred:` entry named only `seedCheck` callers; a low: the `mutation:` line said argued, not observed), rejected 11 rows with reasons in the triage log; patched by verdict: medium 1, low 1, high 0. Follow-up review recommended: false (no `high` patched).

**Verification performed** (warm `e8s2iw`, lane C): `HeartbeatLogic`, `Stalled` (17-28 s), `Test.Live.Status`, `Test.Core.StatusMonitor`, `Test.Web.Api`, `Test.Schedule.Heartbeat` (140-188 s) passed (after the last patch `Stalled`, `HeartbeatLogic` and `Heartbeat` were re-run, and the lane shards ran every class again); `npm --prefix web run lint` exit 0. Fresh `e8s2i`: build; `shard lane-b` (45 classes, 316 s), `lane-b --reverse` (299 s) and `lane-a` (41 classes, 357 s) all passed; `live sign-in` passed in 439 s with `heartbeat.spec.ts` (the first run failed only on this pass's own `Release` check, which compared "1 " with "1"; fixed with a trim, then green); `live demo-path` passed with `STEP 2 watch: partly skipped, 1 passed, 3 skipped`; `npm --prefix web test` 565 passed (it failed once on the new demo-path test running with no stack, fixed by the skip noted under Design Notes); `bash ci/checks.sh` passed. Mutations: all eight lines under Verification observed red and reverted byte-identical. LOCK lines: `LOCK acquired warm-iris project=ocutalon-warm-e8s2iw-1792933096-64102`, then the fresh `throwaway-iris` locks of the shards and live units, each released. Teardown of `e8s2iw` and `e8s2i` done.

**Residual risks.** The stall is synthetic (task suspended, mark moved back), as the spec's method; `Test.Core.StatusMonitor` and `Test.Web.Api` read the real heartbeat and rely on the fresh-mark rule; `Restore()`'s closing tick may record a gap mark (accepted, VG-O7); `Hold` and `Release` suspend and resume the real task, for throwaways and CI only.

