# Epic 5 Context: OcuTalon watches a production and explains what broke

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A user asks OcuTalon in plain words to watch a production. New failures are picked up within seconds and grouped by the settle rule into one diagnosed incident, which moves through a fixed state table. The heartbeat checks each watched production every minute and records what it found, and asked whether everything is fine, OcuTalon never gives a false all-clear. All of that is built. The one remaining story, 5.10, is the epic's burn-down. It keeps Epic 5's Watch and Checks tests reliable once Epic 8's real heartbeat sends a `Tick` every minute into the same production and tables the tests use.

## Stories

- Story 5.1: Ask OcuTalon to watch a production, and to stop
- Story 5.2: New failures are picked up within seconds
- Story 5.3: Same-cause failures become one incident by the settle rule
- Story 5.4: The diagnosis explains the cause from the failed messages
- Story 5.5: An incident moves through its states and closes
- Story 5.6: The production watch runs on every heartbeat
- Story 5.7: Asked whether everything is fine, OcuTalon never gives a false all-clear
- Story 5.8: Each noticed incident says what broke, with its evidence behind Show details
- Story 5.9: Ask OcuTalon in the chat to dismiss an incident
- Story 5.10: Epic 5 burn-down (DW-289)

## Requirements & Constraints

**DW-289, the one criterion of 5.10**
- A real `HeartbeatIn` Tick runs every due check row and sweeps every quiet incident it finds, wherever they are. So a test that makes a check row due at once, or an incident 16 minutes quiet, can see a real Tick's run or close in the middle of the test.
- The tests named as exposed are `Test.Checks.Runs`, `Test.Checks.Heartbeat`, `Test.Checks.Turns.TestFailingOrdersInTheChat` and any `Test.Watch` fixture that makes check rows.
- Fix it in this epic's own tests, without changing product behaviour:
  - Give fixture check rows a `NextDueAt` that a real Tick does not find due (for example a time in the future) wherever the test does not mean to run them.
  - Give quiet incidents `LastAt` times that a real Tick does not sweep.
- Every test must still prove what it proves now.
- A test that must drive a Tick itself must do so in a way that a real Tick can't change its outcome.
- If a pause hook in Epic 8's heartbeat is still needed after that, leave the residual routed to `burndown` and say so. The orchestrator routes it to an open Epic 8 story.

**Product rules the tests must keep proving**
- The heartbeat runs every due background check once a minute. Minutes missed during a restart are caught up once, not replayed. Each run shows in Visual Trace.
- Each check shows its schedule, last run and last result.
- How an unclosed incident closes on quiet:
  - A resolved incident closes after 15 quiet minutes.
  - An open incident (fallback, no fix, rejected or expired) closes this way only with demo mode off. With demo mode on, it waits for Dismiss.
  - An incident that is awaiting approval or fixing never closes this way.

## Technical Decisions

**Background checks (the conventions 5.10 relies on)**
- `WatchOps` creates and removes a watch's `OcuTalon.Data.BackgroundCheck` row.
- `Checks` (`OcuTalon.Checks.Process`) writes only the run fields: `LastRunAt`, `Result`, `Finding`, `LastRunHeaderId` and `NextDueAt`. It writes them with one SQL `UPDATE` keyed by `Ref`, so a watch that was stopped meanwhile is never re-created.
- **Due rule:** a row is due when `NextDueAt` is empty, or is at most 5 s after the Tick's time. After a run, `NextDueAt` becomes the Tick's time plus 60 s, so missed minutes give one run.
  - (inference, as built) "The Tick's time" is the Tick's `TickAt` when that is a UTC stamp, and otherwise now. So a test Tick with a far-future `TickAt` can run rows whose `NextDueAt` is far in the future, and a real Tick at the real time won't.
- **A run's trace** is its Tick's session in OcuTalon's own namespace.
- **A run's result:**
  - `not_checked`, with a code-written reason, when any part can't be read;
  - otherwise `failed`, when the production isn't running, the session has new failures since the last run, or an `open`, `awaiting_approval` or `fixing` incident is in scope (the session's own, plus `instance` incidents off the online demo);
  - otherwise `passed`.
- **The finding** is joined from `Checks` class parameters, with counts as its only slots. It never holds error, event-log or diagnosis text.
- **Quiet sweep:** before its checks, each Tick sends `closeQuiet` (origin `timer`) for every unclosed incident whose `LastAt` is more than `QUIETSECONDS` (900 s) old. `IncidentManager` decides:
  - `not_quiet` when the incident isn't old enough;
  - `not_allowed` when AD-15's table refuses the move;
  - otherwise `closed`.
  - (inference, as built) Both of these age checks use the clock, not the Tick's `TickAt`. So no fixture time can make an incident quiet for the test's own Tick but not for a real one. This is the hard case.
- The `check` event has one publisher, `Checks`. A run publishes the row after the run.

**The real Tick (Epic 8, Lane B)**
- A Task Manager task calls the adapterless `HeartbeatIn` every minute. It sends one `OcuTalon.Msg.Tick` (the tick time and the previous tick time) to the `Checks` item, and writes the tick time to `StatusMark`. After downtime it sends one catch-up Tick.
- (inference, from Epic 8's branch) `HeartbeatIn` sends the Tick asynchronously, and sends none while `Checks` is a stub. In this worktree `OcuTalon.Schedule.HeartbeatIn` is still a stub, so no real Tick reaches the tests here. The collision starts once Epics 5 and 8 meet on the integration branch, and 5.10 has to be made safe without seeing it locally.
- AD-16 adds more to each Tick later: `Checks` will also send the final `FixResult`s from `OcuTalon.Fix.Run.Sweep()`, from Story 7.5 on.

**Where tests make due rows and quiet incidents** (inference, from the test sources)
- `OcuTalon.Test.Data.Fixture`:
  - `Check(sessionRef, namespace, production, fields)` leaves `NextDueAt` empty, so the row is due at once.
  - `Incident(...)` defaults `LastAt` to 2030, which is never quiet.
  - Both helpers take a `fields` override.
- `WatchOps` sets a new watch's `NextDueAt` to its creation time. That is product behaviour, and `Test.Watch.Ops` and `Test.Watch.Turns` assert it, so a real Tick could rewrite it before they check.
- `Test.Checks.Runs` drives an in-process probe (`Test.Checks.Probe`) over fixture rows in namespace `ZZNS`, with a 2030 Tick time, and runs warm. Its rows with an empty `NextDueAt`, and the quiet incidents in `TestQuietSweep` (`LastAt` now minus 960 s), are still visible to the real `Checks` item.
- `Test.Checks.Heartbeat` and `Test.Checks.Turns` (through `Test.Watch.Case`) send Ticks the way `HeartbeatIn` does, synchronously to the real `Checks` item, with now as the tick time. They run only in fresh throwaways and CI, and assert only on their own rows. `TestQuietClose` needs a real 16-minute-old incident and checks that the test's own Tick sent exactly one `closeQuiet`.
- Two more Lane A tests make due rows:
  - `Test.Watch.Case` and `Test.Watch.Poller` make Orders watch rows through `Fixture.Check`.
  - `Test.Bridge.Gate.TestCheckStatusAnswerIsCodeBuilt` (5.7's pin test for `check_status`) makes `Fixture.Check` rows with no `NextDueAt`. A real Tick would replace their results.

**Conventions**
- Edit Lane A files only: `OcuTalon.Checks`, `.Watch`, `.Tools`, `.Agent`, `.Bridge` and their `OcuTalon.Test.<Area>` packages.
  - Never edit Lane B files: `OcuTalon.Schedule` (`HeartbeatIn`), `Core`, `Live`, `Msg`, `Web`, `web/`, or their tests. A heartbeat pause hook would be Lane B's.
  - (inference) `Test.Data.Fixture` is shared by both lanes. Prefer per-call `fields` to changing its defaults.
- Tests are named `OcuTalon.Test.<Area>.<Subject>`. Times are UTC ISO 8601 to the second. Product code reads the clock only through `OcuTalon.Data.Time`.

## Cross-Story Dependencies

- **Done in Epic 5:** 5.1 to 5.9.
  - 5.10 changes only their tests.
  - The quiet close and the state table come from 5.5, the runs and the sweep from 5.6, and the `check_status` and `Turns` tests from 5.7.
- **Epic 8 (Lane B):**
  - Story 8.1, done on its own branch, makes the real Tick. DW-289 came over from it.
  - Any pause hook still needed afterwards is an Epic 8 residual, routed through `burndown`.
- **Later Lane A work on each Tick:** Story 7.5 (`Fix.Run.Sweep`) and Story 30.4 (finding Items for stopped productions and disabled items). Tests built on these patterns should stay safe for them.
