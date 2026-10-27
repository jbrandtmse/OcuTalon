---
title: 'Epic 5 burn-down'
type: 'chore'
created: '2026-10-27'
status: 'done'
baseline_revision: '78c4ad05cc1b57bb449367fb63d6b0d4cb9bb927'
baseline_commit: '78c4ad05cc1b57bb449367fb63d6b0d4cb9bb927'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: 'Contended tests make check rows that are due at once and count stream events that a real Tick adds (the root cause of DW-289, out of footprint)'
    evidence: 'Test.Core.BridgeSink: TestInstanceApprovalReachesEveryWatcher (rows L292-294, untyped Events L587, counts L303-316), TestFailedWatcherReadIsLoud (L330, L344), TestOnlineDemoStillPublishesASessionsOwnRequest (L377, L385, L390), TestApprovalNeverWaitsMoreThanASecond (L403, L430-431). Test.Web.Api.TestStateSections: check2 (L193) stays due, and L253 asserts that it has no run. A real Tick runs these ZZNS rows and publishes a check event on the session stream, or writes a run.'
    location: 'src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls; src/ocutalon/cls/OcuTalon/Test/Web/Api.cls'
    severity: 'med'
    footprint: 'out-of-footprint (contended: Test/Core, Test/Web)'
---

<intent-contract>

## Intent

**Problem:** Once Epic 8's `HeartbeatIn` ticks every minute, a real `Tick` runs every due `BackgroundCheck` row of Kind `production` and sends `closeQuiet` for every unclosed incident more than 900 s old by the clock. Epic 5's tests make such rows and incidents, and assert on what a Tick changes: run fields, `check` events, log lines, incident states and `closeQuiet` counts. So they can flake mid-test (DW-289; occurrence `Test.Checks.Turns.TestFailingOrdersInTheChat`).

**Approach:** Change only the tests, plus one private time seam in `IncidentManager`.
- Every fixture row and incident that a test does not mean a real Tick to touch is out of a real Tick's reach:
  - `Test.Checks.Runs`' probe runs only check rows of its own Kind.
  - `Test.Watch.Case`'s watch rows, and the `Tools` and `Gate` rows, are due a day ahead.
  - Quiet incidents in the in-process probes are quiet only at a probe time in 2030.
- A test that runs a row sends its own Tick at the row's due time.
- Where the product itself makes a row due at once (`WatchOps`), or a quiet incident has to be quiet by the clock (the real `IncidentManager`), the assertions hold whichever Tick acts. A real-shaped Tick, sent as `HeartbeatIn` sends it, proves this in the tests or in one-off interference runs.

## Boundaries & Constraints

**Always:**
- **What each test proves stays the same.** Every assertion keeps its meaning. Where a real Tick can legitimately act (a row that `WatchOps` made, or a quiet close through the real item), the test checks the strict form whenever no Tick acted. When one did, it checks the part that is still true, and it detects that case exactly: only `Checks` writes `LastRunAt`, and every `closeQuiet` is a message header.
- **`Test.Watch.Case`, Rule 2 (extend 5.7's "not due for a day" in `Test.Checks.Turns.TestAllClearOnlyFromCode`):**
  - `Parameter AHEADSECONDS = 86400` and `ClassMethod Ahead()`: now plus `AHEADSECONDS`, UTC.
  - `Watch` sets `NextDueAt` to `Ahead()`.
  - `ClassMethod SendTick(tickAt, async, Output sc) As %Integer`: the one sender.
    - It makes the `HEARTBEAT` service with `Ens.Director.CreateBusinessService`. Synchronously it sends `SendRequestSync` to `CHECKS` (`TICKWAIT`).
    - Asynchronously it sends `SendRequestAsync`, as Epic 8's `HeartbeatIn` does. It then waits, at most `TICKWAIT` seconds, until the Tick's request header in the service's session reaches `Status` 9 (Completed).
    - It returns the service's `%SessionId`, or "" with `sc` set to the error.
  - `Tick(tickAt)` keeps its signature and asserts on `SendTick(tickAt, 0)`.
  - The new `RealTick()` asserts on `SendTick(Data.Time.NowUtc(), 1)` ("the real-shaped Tick is handled"). Waiting means a later synchronous Tick can't overtake it.
  - `Rows(sessionRef, runFields As %Boolean = 1)`: with 0, it leaves out `nextDueAt`, `lastRunAt` and `result`, the fields that `Checks` owns (Conventions "Background checks").
- **`Test.Checks.Probe`:**
  - `Parameter KIND = "zzprobe"`, so its `Due` (through `##super`) runs only rows of that Kind. The real `Checks` runs only `production` rows.
  - `Property QuietAt` and `Property SweptAt` (both transient). `Quiet(now)` records `now` in `SweptAt`, then gives `##super(QuietAt)` when `QuietAt` is set, else `##super(now)`. The `OnlyIncidents` filter is kept.
- **`Watch.IncidentManager`, the one product change:** a private `Method QuietNow() As %String` gives `##class(OcuTalon.Data.Time).NowUtc()`, and `Command`'s quiet check (L616) calls it instead of reading the clock inline. Behaviour is unchanged.
- **`Test.Watch.IncidentProbe`:** `Property QuietNowIs` (transient). `QuietNow()` gives it when it is set, else `##super()`. This is the `DemoModeIs` pattern.
- **Only changed tests are touched.** Unaffected exposures are left as they are (listed under Design Notes).
- Comments state the contract (Rule 14). Times are UTC stamps through `Data.Time` or `Bridge.Time`.

**Never:**
- No edit under `Test/Data/**` (`Fixture` defaults stay; pass `fields`), `Test/{Core,Live,Web,Schedule,Demo}/**`, `Schedule/**`, `Msg/Tick.cls`, `Core/**`, `Install/**`, `web/**`, `ci/**`, `docker/**`, `.github/**`.
- No product change beyond `IncidentManager.QuietNow`. No change to the due rule, the sweep, the `closeQuiet` table or `WatchOps`.
- No pause hook, and no use of Epic 8's `HeartbeatIn` lock or of any Lane B internal.
- No blind retry, no longer waits, no skipped test.

## I/O & Edge-Case Matrix

Each row is an exposed test. It says when a real Tick could reach the test, how the test stays correct, and how that is proved. "RT" is `Case.RealTick()`. "Once" is an interference run under Verification.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| `Checks.Runs` (all tests) | Rows (empty or past `NextDueAt`, and `TestTickWithoutTime`'s Tick at now); a real Tick at any moment | Rows are Kind `zzprobe`, which no real Tick runs. Every assertion is as today. | Once: a real-shaped Tick after the fixtures stays green. Control: the same with `Runs.Watch` back to Kind `production` goes red. |
| `Runs.TestQuietSweep` | Incidents with `LastAt` `TICK`−960 / −840 (2030); `host.QuietAt = TICK` | Five commands as today. `SweptAt` is the clock's now (between the times before and after the Tick, not `TICK`). A real Tick never finds 2030 incidents quiet. | Once (with the run above) |
| `Runs` log counts | Real `Checks` lines with the same method and text start | `Warnings` and `RemoveLogs` use `LOGxxx_<own Ref>`, so only the test's own lines count and only they are removed | Once (with the run above) |
| `Watch.Lifecycle.TestCloseQuiet` and `RealDemoMode` | `host.QuietNowIs = QUIETNOW` (2030); `long`/`short` = −960/−840 from it; plus one resolved incident at clock −840 with `QuietNowIs` "" | Every answer as today. The clock case is `not_quiet`. A real Tick never finds 2030 incidents quiet. | Once: a real-shaped Tick after `resolved` is created, and inside `RealDemoMode`'s mode-0 window. Control: the clock-relative `long` goes red. |
| `Checks.Heartbeat.TestTickRunsTheWatch` | `Watch` row due at `Ahead()` | RT first; the row still has no run. Then `Tick(row.NextDueAt)` and today's assertions: `LastRunAt` is between the clock times before and after that Tick, and `NextDueAt` is the due time plus 60. | RT is in the test |
| `Heartbeat.TestFailingOrders` | The same row; failing orders | RT after `WaitFailed`, with no run. Then `Tick(due)` gives "3 new failures", and `Tick(due+60)` gives "Production stopped". | RT is in the test |
| `Heartbeat.TestQuietClose` | Resolved incidents at clock −960 / −840 | RT between creating them and the test's own Tick. Exactly one `closeQuiet` for the 16-minute Ref, across `Checks`' sessions, sent from a session whose first request is a Tick to `Checks`, with the owner's TraceRef as SuperSession. The test's own Tick sends none. Closed with `ClosedAt`; one `closed` incident event; the 14-minute incident stays `resolved`. | RT is in the test |
| `Heartbeat.TestStartAndStop` | `WatchOps` row due now | If no check event of the Ref carries `lastRunAt`: today's strict form. Otherwise: the first event names the row, every middle event is a run of the Ref, and the last event is the stop. It waits until the stop event (`stopped` true) is there. Log it with `$$$LogMessage`. | Once: RT between start and stop |
| `Checks.Turns.TestFailingOrdersInTheChat` | `Watch` row due at `Ahead()` | RT after `WaitFailed`, with no run; `Tick(due)`; then Ask. The row is not due again during the turn, so `CheckRows` equals the row. | RT is in the test |
| `Watch.Ops.TestStart`; `Watch.Turns.TestStartThroughTheAgent` | `WatchOps` row due now | If `lastRunAt` is "": today's assertions. Otherwise: `createdAt` is the creation time, the `WatchOps` fields are as today, and `lastRunAt` is not before `createdAt`. Log it with `$$$LogMessage`. | Once: RT after `OnStart` / after the turn |
| `Ops.TestStop`; `Ops.TestLockTimeout` | `WatchOps` rows due now; "unchanged" checks | Compare `Rows(b, 0)` / `Rows(held, 0)` | Once: RT between the snapshot and the comparison |
| `Watch.Turns.TestStopLeavesTheOtherSession`; `TestInjectedStop` | `Watch` rows | Due at `Ahead()`, so the full-row comparisons hold as they are | Once: RT after the snapshot |
| `Watch.Tools.TestCheckStatus`; `TestCheckStatusHostData` | `production` fixture rows | `"NextDueAt": (..Ahead())` in their `fields`; answers as today | Once: RT before `CheckStatus` |
| `Bridge.Gate.TestCheckStatusAnswerIsCodeBuilt` | `Zz.G1`–`G5` | `"NextDueAt": (##class(OcuTalon.Test.Watch.Case).Ahead())`, so each result shape stays as made | Once: `##class(OcuTalon.Test.Watch.Case).SendTick(##class(OcuTalon.Data.Time).NowUtc(), 1, .sc)` before `CheckStatus` |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless noted.

- `Checks/Process.cls`, read-only:
  - `Tick` L120: now L122, tick time L123, `Sweep(now)` L125.
  - `Quiet` L173: `State <> closed`, `Settle.Quiet` against the clock.
  - `Due` L204: `Kind = ..#KIND` L208, the due rule L212.
  - `Record` L275 (`NextDueAt` = tick time + 60).
  - `KIND` L53; `LOG*` L95-107 (each names the Ref).
- `Watch/IncidentManager.cls`: `Command` L601, the quiet check L616 (seam); `DemoMode` L574 is the seam's sibling; class doc L52 (`not_quiet`).
- `Watch/Ops.cls` L74-88, read-only: `NextDueAt = CreatedAt`, then `Changed`.
- `Test/Checks/Probe.cls`: class doc L1-13; `Due` L63; `Quiet` L73.
- `Test/Checks/Runs.cls`:
  - class doc L1-27; `TICK` L34.
  - `TestDue` L95 (`unset` L101, other kind L104); `TestTickWithoutTime` L125.
  - `TestNotChecked` L241 (`Warnings` L255, L263); `TestQuietSweep` L303 (L308-309, L336, L342); `TestChanged` L384; `TestRunThrows` L420.
  - Helpers: `Watch` L477; `Incident` L493; `Case` L549 (returns the Ref); `Warnings` L611; `RemoveLogs` L633.
- `Test/Checks/Heartbeat.cls`:
  - class doc L1-13.
  - Tests: `TestTickRunsTheWatch` L21, `TestFailingOrders` L54, `TestQuietClose` L77 (own session's requests L94-99), `TestStartAndStop` L102.
  - Helpers: `Check` L147, `Resolved` L163.
- `Test/Checks/Turns.cls`: class doc L1-13; `TestFailingOrdersInTheChat` L42 (`Watch` L48, `Tick` L51); `TestAllClearOnlyFromCode` L68 (already a day ahead; it stays).
- `Test/Watch/Case.cls`:
  - class doc L3-29 (the Tick bullet L27-28).
  - `HEARTBEAT`/`CHECKS`/`TICKWAIT` L82-87.
  - `Ready` L207 (demo mode on), `Rows` L425, `Watch` L445, `Tick` L454.
- `Test/Watch/Ops.cls`: class doc L1-27; `TestStart` L33 (L55-58); `TestStop` L93 (L102, L117, L123); `TestLockTimeout` L219 (L240, L250).
- `Test/Watch/Turns.cls`: class doc L1-24; `TestStartThroughTheAgent` L29 (L44-45); `TestStopLeavesTheOtherSession` L63; `TestInjectedStop` L113.
- `Test/Watch/Tools.cls`: `TestCheckStatus` L317 (rows L325-329); `TestCheckStatusHostData` L344 (row L371).
- `Test/Watch/Lifecycle.cls`: class doc L1-30 (L12-14); `PROBE` L41; `TestCloseQuiet` L187; `RealDemoMode` L745; `Command` L898.
- `Test/Watch/IncidentProbe.cls`: class doc L1-9; `DemoModeIs` L26; `DemoMode` L52.
- `Test/Bridge/Gate.cls`: `TestCheckStatusAnswerIsCodeBuilt` L335 (rows L352-356).
- Call only, contended:
  - `Test/Data/Fixture.cls`: `Check` L65 (`NextDueAt` empty), `Incident` L81 (`LastAt` 2030), `SessionHeaders`/`HeadersWhere`/`Between` L392-417.
  - `Test/Core/Observe.cls`: `Warnings` L88 and `RemoveWarnings` L101 (`%STARTSWITH`), `Events`.
- Epic 8's real Tick (read on branch `OCT-epic8`; not in this tree): `HeartbeatIn.OnProcessInput` uses `SendRequestAsync(Heartbeat.#TARGET, tick)`, with `TickAt` now. It sends nothing while `Checks` carries `STUB`. It works under the `Heartbeat` LOCK.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls`: add `QuietNow()` and call it at L616; class doc line. This is the only seam (Always).
- `src/ocutalon/cls/OcuTalon/Test/Watch/IncidentProbe.cls`: add `QuietNowIs` and the `QuietNow` override; class doc.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls`: add `AHEADSECONDS`, `Ahead`, `SendTick`, `RealTick` and the `Rows` argument; `Watch` is due at `Ahead()`; `Tick` uses `SendTick`; class doc bullets.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Probe.cls`: add `KIND`, `QuietAt`, `SweptAt` and the `Quiet` change; class doc.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls`:
  - `Watch` sets `Kind` to `$Parameter(..#PROBE, "KIND")`.
  - `TestQuietSweep`: `QuietAt`, `TICK`-relative times, and the `SweptAt` assertion.
  - Ref-filtered `Warnings` (L255 and L263 use the case's and `Zz.Thrown`'s Refs; L336 and L342 use `open` and `awaiting`; L384; L420), and `RemoveLogs` over `..Checks` and `..Incidents`.
  - Class doc: the Kind, and why.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Heartbeat.cls`: the four matrix rows. Add a private helper `QuietRequests(ref)`: the `closeQuiet` request headers from `Checks` to `IncidentManager` whose `OcuTalon.Msg.IncidentCommand` body names the Ref, as `{sessionId, superSession}`. It extends nothing, because `Fixture.HeadersWhere` is contended. Update the class doc.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Turns.cls`: `TestFailingOrdersInTheChat` row; class doc L6-10.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Ops.cls`: `TestStart`, `TestStop` and `TestLockTimeout` rows; class doc.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Turns.cls`: `TestStartThroughTheAgent` row; class doc.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Tools.cls`: the `fields` of the `production` rows in the two tests.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Lifecycle.cls`: add `Parameter QUIETNOW = "2030-06-01T12:00:00Z"`; the `TestCloseQuiet` row (`RealDemoMode` keeps `QuietNowIs`); class doc L5 and L12-14.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Gate.cls`: `NextDueAt` in the five `fields` of `TestCheckStatusAnswerIsCodeBuilt`, and nothing else.

**Acceptance Criteria:**
- **Not due for a real Tick.** Given the check rows of `Test.Checks.Runs`, `Test.Watch.Case.Watch`, `Test.Watch.Tools` and `Test.Bridge.Gate`, when a real-shaped Tick (`TickAt` now, sent asynchronously from `HeartbeatIn` to `Checks`) is handled at any moment of these tests, then it runs none of them, and every assertion of these tests passes unchanged in meaning (the Runs, Tools and Gate interference runs; RT in Heartbeat and in Checks.Turns).
- **Own Tick at the due time.** Given a test that runs its own row, when it ticks, then it sends its Tick at the row's `NextDueAt`, and the run, the finding, the `check` event, `/state` and the chat's `CheckRows` are the ones today's tests assert.
- **Quiet only at the probe's time.** Given the in-process quiet tests (`Runs.TestQuietSweep`, `Lifecycle.TestCloseQuiet`), when a real-shaped Tick is handled mid-test, then it sweeps none of their incidents, and the probes still prove the product's rules. `Checks` hands the sweep the clock's now (`SweptAt`), and `IncidentManager` reads the clock when nothing is fixed (the `not_quiet` clock case).
- **Quiet close through the real item.** Given `Heartbeat.TestQuietClose`, when a real-shaped Tick arrives before the test's own Tick, then exactly one `closeQuiet` for the quiet incident is sent, from a Tick's session, with the owner's TraceRef as SuperSession. The incident is closed with one `closed` event, the 14-minute incident stays `resolved`, and the test's own Tick sends no second `closeQuiet`.
- **Rows that `WatchOps` makes.** Given the tests of rows that `WatchOps` makes due at once, when a Tick runs such a row mid-test, then the test detects it through `lastRunAt` and checks what is still `WatchOps'`. When no Tick ran it, the strict form is checked, as it always is in this worktree. The "unchanged" checks compare `WatchOps'` fields only.
- **Own log lines.** Given `Test.Checks.Runs`, when other `Checks` jobs log lines with the same method and text start, then its counts and removals see only lines that name its own Refs.
- **Fresh environment.** Every test added or changed passes on a fresh environment, in either order (Rule 19; the lead's fresh check).

## Spec Change Log

## Review Triage Log

### 2026-10-27 — Review pass
- verdicts: 25 findings — high 0, medium 0, low 17, false 8, maybe-false 0 (the intent-alignment layer reported readings, not findings)
- findings:
  - `[low]` `[reject]` Blind: `QuietRequests` scans every Checks-to-IncidentManager header with no floor — Heartbeat runs only in throwaway stacks (class doc), where the header count is small; the fix adds a mark and a parameter.
  - `[low]` `[reject]` Blind: `TestStartAndStop`'s ran branch is reached by chance and a run event could follow the stop — the spec makes it a one-off interference run, which stayed green; Checks announces a run before it handles the next message, so a later run event is not shown.
  - `[low]` `[reject]` Blind: `SendTick` waits the full 60 s when the request ends in Error/Discarded — the failure message names the status and the wait only happens when the test is already red.
  - `[low]` `[reject]` Blind: 14-minute incident margin (60 s) equals the `RealTick` wait cap — the spec fixes -960/-840 and a real wait is about a second; the original test had the same margin.
  - `[false]` `[reject]` Blind: the Tick a day ahead runs other tests' rows — the other tests drop their rows in teardown and run one at a time; the old Tick at now ran every due row too.
  - `[false]` `[reject]` Blind: `Lifecycle`, `Tell`, `Poller` still make due-at-once rows — Design Notes list them as left because no assertion in them changes with a Tick.
  - `[low]` `[reject]` Blind: the ran-first branches of `Ops.TestStart` and `Watch.Turns` check little — the spec's matrix gives exactly these checks; a `OnStart` that writes `LastRunAt` is not a plausible regression.
  - `[false]` `[reject]` Blind: `RemoveLogs` removes only registered Refs — the matrix requires it; every row and incident of the test is registered by `Watch`/`Incident`, and the run left no line behind.
  - `[false]` `[reject]` Blind: `TestStartAndStop` lost the exactly-one start event in the ran case — the spec's matrix row gives the weaker form there and keeps the strict one when no Tick ran.
  - `[low]` `[reject]` Blind: long doc lines — the files already carried lines of this length; cosmetic.
  - `[low]` `[reject]` Edge: `SendTick` loop and terminal non-Completed statuses — same as Blind row 3.
  - `[low]` `[reject]` Edge: `Check(ref)` may return no object in the Heartbeat tests — the existing tests read `Check(ref)` the same way and the rows are the test's own.
  - `[low]` `[reject]` Edge: a run event after the stop event in `WaitStopped` — same as Blind row 2.
  - `[false]` `[reject]` Edge: a check event without a payload — every check event carries a payload object (`FromRow`).
  - `[false]` `[reject]` Edge: the Tick at `NextDueAt` runs other rows — same as Blind row 5.
  - `[low]` `[reject]` Edge: a concurrent scheduled Tick could produce a second `closeQuiet` — Epic 8's `HeartbeatIn` is not in this tree and the spec's AC is "exactly one across Checks' sessions"; a closed incident is no longer selected.
  - `[low]` `[reject]` Edge: `QuietRequests` scan unbounded — same as Blind row 1.
  - `[low]` `[reject]` Edge: the ran branch of `Ops.TestStart` does not check Result/NextDueAt — same as Blind row 7.
  - `[low]` `[reject]` Edge: Heartbeat class doc says every own Tick is at a NextDueAt, `TestQuietClose`'s is at now — imprecise wording, no behaviour.
  - `[low]` `[patch]` Verify: Tools and Gate `NextDueAt` rows have no control line — control runs made and recorded in `## Verification` (Tools red; Gate green by design); no code change.
  - `[low]` `[reject]` Verify: the weak ran-branch of `Ops.TestStart`/`Watch.Turns` passes an `OnStart` that stamps `LastRunAt` — spec-bound form, not a plausible regression.
  - `[low]` `[patch]` Verify: no run shows own-log-line isolation — mutation recorded (`LOGQUIET` count without the Ref goes red); no code change.
  - `[low]` `[reject]` Verify: the ran branch of `TestStartAndStop` in a narrow Tick/delete window — same as Blind row 2.
  - `[false]` `[reject]` Verify: `TestNotChecked`'s read-warning count narrowed — the assertion's text and meaning concern the failed incident read, which is the case `reads_unread` names.
  - `[false]` `[reject]` Verify: the `QuietNow` +3600 mutation does not turn `TestQuietClose` red — a documented deviation; the 14-minute pin is the `Process.Tick` sweep mutation, recorded.

## Design Notes

**Governing ADs:**
- AD-18: the heartbeat every minute, the due rule, "missed minutes give one run".
- AD-15 and AD-33: the `closeQuiet` table; `IncidentManager` is the only writer; `Checks` owns the run fields and `WatchOps` the rest of the row (the basis for `Rows(…, 0)`).
- AD-22: tests, throwaways, CI.
- AD-26: the Tick's session is the trace, and the SuperSession is the owner's.
- AD-28: `check_status` reads the rows.
- AD-5: due-ness lives in rows.

Conventions: "Background checks", "Tests", "Times". No AC contradicts an AD.

**Integration ACs, Consumes, Consumed-by.** This story introduces no service. It changes tests and adds one private seam (`IncidentManager.QuietNow`) whose only consumer is `Test.Watch.IncidentProbe`, so Rule 1 does not apply.
- Consumes:
  - 5.6: `Checks.Process`, `Test.Checks.{Runs,Probe,Heartbeat}`;
  - 5.5: `IncidentManager.Command`, `IncidentProbe`, `Lifecycle`;
  - 5.1 and 5.2: `Test.Watch.Case`, `WatchOps`, `Ops`, `Turns`, `Tools`;
  - 5.7: `Test.Checks.Turns`, `Gate.TestCheckStatusAnswerIsCodeBuilt`;
  - Epic 0: `Test.Data.Fixture`, `Msg.Tick`;
  - 8.1 (branch `OCT-epic8`): `HeartbeatIn`'s async Tick, the contract `RealTick` copies.
- Consumed-by:
  - the Epic 5 and Epic 8 integration: these tests stay green when 8.1's real Tick meets them;
  - 7.5 (`Fix.Run.Sweep` on each Tick) and 30.4: later Tick tests reuse `Ahead`, `RealTick` and `SendTick`.

**Extend, don't copy:**
- `RealTick` and `Tick` share `SendTick`.
- `Ahead` extends 5.7's `TestAllClearOnlyFromCode` convention.
- `QuietNowIs` follows `DemoModeIs`.
- The probe's Kind follows `Test.Watch.Tools`' `zzother` row.
- `Rows(…, 0)` extends `Rows`.
- `QuietRequests` is new: its sibling `Fixture.HeadersWhere` is contended and filters by session only.

**Ledger inbox (Rule 17):**
- **DW-289: addressed in full** by the matrix. **No Epic 8 pause hook is needed:** every exposed test stays correct with a real Tick at any moment, so no residual is routed.
  - A fact for the orchestrator: Epic 8's `HeartbeatIn` already waits 5 s for its `Heartbeat` LOCK and sends nothing when it can't take it. No Lane A test relies on that.
- The same root cause reaches contended tests (`Test.Core.BridgeSink`, four methods, and `Test.Web.Api.TestStateSections`). It is recorded under the frontmatter `deferred:` for the lead to harvest as an out-of-footprint occurrence, with no edit here.

**Epic context check:**
- Confirmed from the source:
  - the tick time is `TickAt` when it is a stamp, else now (`Process` L122-123);
  - both age checks read the clock (`Process` L122/L125, `IncidentManager` L616);
  - `HeartbeatIn` sends asynchronously and not to a `STUB` (branch `OCT-epic8`).
- "Where tests make due rows": confirmed, and widened by the sweep to `Ops.TestStop`/`TestLockTimeout`, `Watch.Turns` (three tests), `Watch.Tools` (two tests) and `Lifecycle.TestCloseQuiet`. Corrected: `Gate`'s test already tolerates runs (any code-built text). It is still made not-due, so that each result shape stays exercised.

**Task 0 (plan, slot `ocutalon-slot-a`, build 154, `OCUTALON`, 2026-10-27).** A subclass that overrides a class parameter changes `..#PARAM` both in the methods it inherits and in a `##super` call from its own override (`plain=zzplain`, `sub=super:zzprobe`). The three `ZzE5s10p` classes were made, measured and deleted. This is what lets `Probe.KIND` reach `Process.Due`.

**Decided in-stage:**
- **Kind, not time, for `Runs`.** `TestDue`'s empty-`NextDueAt` row and `TestTickWithoutTime`'s now-time Tick are due for any Tick, so no due time hides them. The Kind filter is the product's own rule. The real Kind `production` is still exercised by `Heartbeat`.
- **A day ahead for `Case` and the fixture rows**, because 5.7 already uses it. A test that runs its row ticks at the row's `NextDueAt`. Runs read failures from `CreatedAt`/`LastRunAt` and the clock (`Mark.Start`), so a future tick time changes only the due fields.
- **The quiet clock pins move but stay:** `SweptAt` in `Runs`, the `not_quiet` clock case in `Lifecycle`, and the clock-relative `Heartbeat.TestQuietClose` end to end.
- **RealTick is in the tests where it is harmless**: the four `Heartbeat`/`Checks.Turns` rows, at their worst moment. So every CI run re-proves the case. It is a one-off run where it would force the run branch, so that the strict branch keeps running normally.
- **The conditional checks of `WatchOps`-made rows.** The product makes them due at once, and only a pause hook could hold a real Tick off. The strict form runs whenever no Tick ran the row, which is every run in this worktree and nearly every run after Epic 8, so a mutation of `NextDueAt` is still caught (Verification). The fallback branch is detected exactly through `lastRunAt` (only `Checks` writes it), never guessed.
- **"Unchanged" means the fields `WatchOps` owns** (Conventions "Background checks"). The `Watch.Turns` rows are due a day ahead, so they keep their full-row comparisons.
- **Left as they are** (the sweep found no assertion that a Tick changes):
  - `Poller` (batches, marks, filtered warnings), `Tell`, `Lifecycle.Watch`;
  - `Tools.Watching`/`UnlistedWatch`, `Diagnose` and `Evidence` (refused with demo mode on, or unnoticed);
  - `Incidents`, `Notices` and `Closing` (typed events; incidents not old);
  - `Lifecycle.TestPurge` (existence only).
- **`RealDemoMode`'s short write of the real `demo.mode`** stays as it is. With `QuietNowIs` its own incidents are not quiet for a real Tick, and tests run one at a time.
- **Inference.** `SendRequestAsync` from a `CreateBusinessService` instance works outside `ProcessInput`, as `Tick`'s synchronous send already does (measured in 5.6), and the async request header of a business process reaches Completed. `RealTick` asserts this itself. If the first run shows another final status, the implement stage records the measured status and waits for that one, a change inside `Case` only.

**Footprint:** every path is in the stated footprint. `Watch/IncidentManager.cls` is the named seam. No contended path is touched, and there is no footprint extension.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/../.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=5 stage=implement'`.
- Run one command per call, each with `timeout: 600000`.
- Never put two IRIS test runs in one message, and chain nothing after a shard part.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e5s10iw ci/warm.sh up`: once per stage. Expected: READY and `RESULT OK`.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s10iw ci/iris.sh class <Class>`, one call per class. Expected: `CLASS … passed`. The classes: `OcuTalon.Test.Checks.Runs`, `OcuTalon.Test.Watch.Lifecycle`, `OcuTalon.Test.Watch.Tell`, `OcuTalon.Test.Watch.Tools`, `OcuTalon.Test.Watch.Ops`, `OcuTalon.Test.Bridge.Gate`.
- (loop) `<lane> OCUTALON_RUN_TAG=e5s10i ci/iris.sh class <Class>`, fresh, one call per class. Expected: passed. The classes: `OcuTalon.Test.Checks.Heartbeat`, `OcuTalon.Test.Checks.Turns`, `OcuTalon.Test.Watch.Turns`.
- (once) **Interference runs.** Insert the injection, run the class, expect green, then revert. `git status --short` and `git diff --stat` must be byte-identical afterwards, and the class green again.
  - Warm: `Runs` (a `##class(OcuTalon.Test.Watch.Case).SendTick(##class(OcuTalon.Data.Time).NowUtc(), 1, .sc)` after the fixtures of `TestDue`, `TestTickWithoutTime`, `TestPassed` and `TestQuietSweep`), `Lifecycle` (after `resolved`; inside the mode-0 window), `Tools`, `Gate` and `Ops` (the matrix's points).
  - Fresh: `Heartbeat` (`TestStartAndStop`) and `Watch.Turns` (three tests).
  - Controls: `Runs` with `Watch` back to Kind `production` goes red (`TestPassed`'s two events); `Lifecycle` with clock-relative `long` goes red. Revert both.
  - Record each run as `interference: <where> → green` or `control: … → red`.
- (once) `<lane> OCUTALON_RUN_TAG=e5s10i ci/iris.sh shard lane-a --part 1/4`, then `--part 2/4`, `--part 3/4` and `--part 4/4`, each in its own call (70 classes, 140-390 s each). Use `--part k/5` if a part passes 480 s. Record each part's time.
- (once) `<lane> OCUTALON_RUN_TAG=e5s10i ci/iris.sh shard lane-b`, about 2 minutes. It holds `Core.CommandsRouting` and `CommandsInProduction` (`IncidentManager`).
- (once) `bash ci/checks.sh`. Expected: all pass.
- (once) `<lane> OCUTALON_RUN_TAG=e5s10iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e5s10i ci/iris.sh teardown`, also after a failure.

**Shared surfaces:**
- `Case.Watch`'s `NextDueAt` (empty becomes a day ahead): every `Case` subclass that calls it (`Poller`, `Diagnose`, `Incidents`, `Notices`, `Turns`, `Checks.Heartbeat`, `Checks.Turns`). None asserts its due time.
- `Case.Tick` keeps its signature. `Case.Rows` has a new optional argument; existing calls are unchanged.
- `IncidentManager.QuietNow`: real behaviour is unchanged (`Heartbeat`, lane-b's `Core.CommandsRouting`).
- `IncidentProbe` (`Lifecycle`, `Tell`): defaults unchanged.
- `Checks.Probe` (`Runs` only).
- The `Ens_Util.Log` lines that `Runs` removes: now only its own.
- No class is added (lane-a stays at 70; `ci/units.sh` is unchanged).
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to apply** (Rule 19). The implement stage applies each one, observes red, reverts byte-identically and records it here.

| AC | Mutation | Expected red |
|---|---|---|
| Not due | `Case.Watch` leaves `NextDueAt` empty | `Heartbeat.TestTickRunsTheWatch` (RT runs the row), `Checks.Turns.TestFailingOrdersInTheChat` |
| Not due (product rule) | `Process.Due` drops `Kind = ?` | `Runs.TestDue` (the other-kind row runs) |
| Own Tick | `Process.Record` sets `NextDueAt` to the tick time plus 120 | `Heartbeat.TestTickRunsTheWatch`, `Runs.TestDue` |
| Quiet only at probe time | `Process.Tick` calls `Sweep(tickAt)` | `Runs.TestQuietSweep` (`SweptAt`) |
| Quiet only at probe time | `IncidentManager.QuietNow` gives now plus 3600 | `Lifecycle.TestCloseQuiet` (the clock case closes), `Heartbeat.TestQuietClose` (the 14-minute incident closes) |
| Quiet close | `Process.Quiet` drops `State <> ?` | `Heartbeat.TestQuietClose` (two `closeQuiet`), `Runs.TestQuietSweep` |
| Quiet close | `Sweep` leaves `%SuperSession` "" | `Heartbeat.TestQuietClose`, `Runs.TestQuietSweep` |
| WatchOps rows | `Ops.OnStart` sets `NextDueAt` to `CreatedAt` plus 3600 | `Ops.TestStart` (strict branch), `Watch.Turns.TestStartThroughTheAgent` |
| WatchOps rows | `Ops.OnStop` also changes another session's `DisplayName` | `Ops.TestStop` |
| Own log lines | `LOGQUIET`'s line leaves out the Ref | `Runs.TestQuietSweep` |

**Recorded runs (implement stage).** Each mutation was applied, the class run, red observed, and the tree restored byte-identically (compared with the stage's backup; `git status` shows only the intended files).
- mutation: `Case.Watch` leaves `NextDueAt` empty -> red: `Heartbeat.TestTickRunsTheWatch` (RT runs the row; also `TestFailingOrders`), `Checks.Turns.TestFailingOrdersInTheChat`.
- mutation: `Process.Due` drops `Kind = ?` -> red: `Runs.TestDue` (the other-kind row runs).
- mutation: `Process.Record` sets `NextDueAt` to the tick time plus 120 -> red: `Heartbeat.TestTickRunsTheWatch` (also `TestFailingOrders`), `Runs.TestDue`.
- mutation: `Process.Tick` calls `Sweep(tickAt)` -> red: `Runs.TestQuietSweep` (`SweptAt`).
- mutation: `IncidentManager.QuietNow` gives now plus 3600 -> red: `Lifecycle.TestCloseQuiet` (the clock case closes). `Heartbeat.TestQuietClose` stays green under this mutation alone: `Checks` selects by its own clock and never sends a command for the 14-minute incident, so `QuietNow` is not reached. The Heartbeat pin for the 14-minute incident is therefore this one: mutation: `Process.Tick` calls `Sweep` with now plus 3600 -> red: `Heartbeat.TestQuietClose` ("none names the 14 minute incident").
- mutation: `Process.Quiet` drops `State <> ?` -> red: `Heartbeat.TestQuietClose` (two `closeQuiet`), `Runs.TestQuietSweep`.
- mutation: `Sweep` leaves `%SuperSession` "" -> red: `Heartbeat.TestQuietClose` (SuperSession), `Runs.TestQuietSweep`.
- mutation: `Ops.OnStart` sets `NextDueAt` to `CreatedAt` plus 3600 -> red: `Ops.TestStart` (strict branch), `Watch.Turns.TestStartThroughTheAgent` (after the test's time comparisons were made string comparisons: the `'<` / `'>` operators compare numerically, so the old forms could not fail).
- mutation: `Ops.OnStop` also changes another session's `DisplayName` -> red: `Ops.TestStop`.
- mutation: `LOGQUIET`'s line leaves out the Ref -> red: `Runs.TestQuietSweep`.
- interference: `Runs` (real-shaped Tick after the fixtures of `TestDue`, `TestTickWithoutTime`, `TestPassed`, `TestQuietSweep`) -> green.
- interference: `Lifecycle` (after `resolved`; inside `RealDemoMode`'s mode-0 window) -> green.
- interference: `Tools` (before `CheckStatus` in both tests), `Gate` (before the rows-of-each-result `CheckStatus`), `Ops` (after the snapshot in `TestStop` and `TestLockTimeout`, after `OnStart` in `TestStart`) -> green.
- interference: `Heartbeat.TestStartAndStop` (RT between start and stop) and `Watch.Turns` (after the snapshot in the two stop tests, after the turn in the start test) -> green.
- control: `Runs.Watch` back to Kind `production`, with the Ticks injected -> red (`TestPassed`, `TestPublishes`, `TestRanLine`, `TestScope`, others).
- control: `Lifecycle` with clock-relative `long`, with the Tick injected -> red (`TestCloseQuiet`, the 16-minute close).
- mutation: `Runs.TestQuietSweep`'s second `Warnings("Sweep", ...)` count loses its Ref (`LOGQUIET` bare instead of `LOGQUIET_<awaiting>`) -> red: `Runs.TestQuietSweep` ("a send that IncidentManager did not answer in time ... logs one warning too": the bare count is 2, the scoped one is 1). Pins the AC "Own log lines"; restored, green again.
- control: `Tools.TestCheckStatus` with `NextDueAt` removed from its rows and a real-shaped Tick (`RealTick`) before `CheckStatus` -> red (`check_status()` and the HostData rows). Restored, green again.
- control: `Gate.TestCheckStatusAnswerIsCodeBuilt` with `NextDueAt` removed from `Zz.G1`-`G5` and a real-shaped Tick before `CheckStatus` -> green, as the spec's Design Notes say (the test accepts any code-built text, so a run does not break it). `NextDueAt` there keeps each result shape as made; it guards no assertion that a Tick could turn red. Restored, green again.
- shards: lane-a parts 1/4 to 4/4 passed (331 s, 153 s, 138 s, 357 s); lane-b passed (114 s); `ci/checks.sh` all pass.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Epic 5's tests no longer depend on the moment a real Tick arrives (DW-289). Fixture rows are of the probe's Kind or due a day ahead; quiet incidents in the in-process probes are quiet only at a fixed 2030 time; tests that run a row send their own Tick at its `NextDueAt`; `RealTick` proves a real-shaped Tick changes none of four tests' rows; tests of rows that `WatchOps` makes due at once hold in the strict form and, when a Tick ran the row, in the form that is still true.

**Files changed** (under `src/ocutalon/cls/OcuTalon/`):
- `Watch/IncidentManager.cls`: private `QuietNow()` seam; `Command`'s quiet check calls it (behaviour unchanged).
- `Test/Watch/Case.cls`: `AHEADSECONDS`, `Ahead`, `SendTick`, `RealTick`, `Rows(ref, runFields)`; `Watch` due at `Ahead()`.
- `Test/Watch/IncidentProbe.cls`: `QuietNowIs` and the `QuietNow` override.
- `Test/Checks/Probe.cls`: Kind `zzprobe`, `QuietAt`, `SweptAt`.
- `Test/Checks/Runs.cls`, `Heartbeat.cls`, `Turns.cls`: Kind-isolated rows, own-Ref log counts, `RealTick` at the worst moment, `QuietRequests`, `WaitStopped`.
- `Test/Watch/Ops.cls`, `Turns.cls`, `Tools.cls`, `Lifecycle.cls`; `Test/Bridge/Gate.cls`: the matrix rows (`Rows(..., 0)`, due-ahead rows, the `lastRunAt` branches, `QUIETNOW`).

**Review.** 25 findings: high 0, medium 0, low 17, false 8. Patches applied: 2 (both spec-only: a mutation line and a control line recorded in `## Verification`; no code changed). Deferred: none new (the plan's entry for the contended `Test.Core.BridgeSink` and `Test.Web.Api` tests stays). Rejected: 23, each with its reason in the triage log. Follow-up review recommended: false (no code patch; patched counts high 0, medium 0).

**Verification performed** (Lane A's variables on every call). Loop sets: `Runs`, `Lifecycle`, `Tell`, `Tools`, `Ops`, `Gate` warm and `Heartbeat`, `Checks.Turns`, `Watch.Turns` fresh passed; `Runs`, `Tools` and `Gate` passed again on the reviewed tree after the review controls. Once lines: ten pinning mutations (nine red as expected, the `QuietNow` +3600 expectation for `TestQuietClose` was wrong and is pinned by the sweep mutation), the interference runs and controls, lane-a parts 1/4-4/4 (331, 153, 138, 357 s), lane-b (114 s) and `ci/checks.sh` all passed. Warm and fresh stacks are torn down and the lane-a lock folder is empty.

**Residual risks.** The `lastRunAt` branches of `Ops.TestStart`, `Watch.Turns.TestStartThroughTheAgent` and `TestStartAndStop` were not observed running (they need a Tick to run a `WatchOps` row mid-test; the strict branches ran). Slot `ocutalon-slot-a` holds copies of classes the implement stage loaded (it was stale before). The contended tests named in `deferred:` still carry the DW-289 root cause.
