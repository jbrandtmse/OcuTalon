# Epic 5 Context: OcuTalon watches a production and explains what broke

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A user asks OcuTalon in plain words to watch a production. New failures are picked up within seconds, grouped by the settle rule into one incident, and diagnosed into a plain-English cause, the element at fault and a proposed fix, with the evidence behind it. The incident then moves through fixed states, and OcuTalon never gives a false all-clear. Stories 5.1 to 5.14 are done. Epic 5 is re-opened under SC-5 for one fix-forward story, 5.15 (DW-851), which ships in 1.0.5 and merges only after the 1.0.4 cut. The status answer (`check_status`) and the rail's Background checks both read the production watch's last check, which runs only on the one-minute heartbeat. So after an approved fix finishes, both keep reporting the failures, and the fix as waiting for approval, for up to a minute, while the incident card already reads Resolved. The Contest Planner chose this fix: when an incident resolves, or its fix is rejected, the watch of that production runs its check once, straight away, through the existing check path.

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
- Story 5.10: Epic 5 burn-down
- Story 5.11: The demo guide's tests hold now that incidents are real
- Story 5.12: A correct diagnosis is never refused for an over-long evidence reference
- Story 5.13: Ask OcuTalon what happened earlier, and it tells you from its own records
- Story 5.14: Several incidents at once are each diagnosed inside their timer
- Story 5.15: After an incident resolves, the status answer and the rail say so within seconds

## Requirements & Constraints

Story 5.15 is the only open story.

- **When the re-check fires.** It fires when `IncidentManager` applies a final fix run that moves the incident to `resolved` (all through or partly through), or a rejection of its fix request. At that point the watch of that production runs its check once, without waiting for the next heartbeat.
- **The existing check path, unchanged.** The re-check is the `Checks` item's normal run of the `BackgroundCheck` row: the same read, scope, findings and result rules, the same record, the same `check` event and the same log line.
- **What must show it.** The next `check_status` read and the rail's Background checks both show the re-check's result, so a fix that cleared the failures reads `passed` (or whatever the check finds) within seconds.
- **Which watches.** Re-check only the watches whose scope includes the incident:
  - a session-scoped incident: that session's watch of that production;
  - an `instance` incident: each watching session's watch, as `Session.Recipients(ownerRef, incidentRef)` resolves them.
  - Never re-check a watch of another production, or a watch belonging to a session that does not see the incident.
- **Unchanged:**
  - the check's rules: the read, scope, findings, result, and the FINDING* and REASON* texts;
  - its schedule: the heartbeat, INTERVALSECONDS, DUESLACKSECONDS, and how a scheduled run sets `NextDueAt`;
  - the `Checks` item's PoolSize 1;
  - the user-facing strings: add none.
- **What the re-check must not do.**
  - It never runs the quiet sweep (`closeQuiet`), the fix sweep (`Fix.Run.Sweep`) or the agent heartbeat's beats.
  - If it fails, or finds no row, it logs at most one warning and changes nothing else.
- **Tests:**
  - a resolved fix, then the next status read shows the post-resolve check;
  - the same for a rejected fix;
  - a mutation that removes the re-check turns a test red (Rule 19);
  - the story's tests pass on a fresh environment, in both forward and reversed order.
- **Footprint.** Stay in Lane A's Watch area: `IncidentManager`, the `Checks` process and its messages, and their tests. The spec lists every file. CI is green on every workflow, using the CI mock only (no real model key).
- **Out of scope:**
  - treating a check result older than the resolution as stale (the other option, not chosen);
  - any change to the text of the status answer or the rail;
  - the expired-request path, unless the spec shows it moves the incident the same way. In the transition table, an expiry with no other request pending goes to `open` (expired), the same move as a rejection.

## Technical Decisions

- **One owner each.**
  - `IncidentManager` (`OcuTalon.Watch.IncidentManager`) is the only writer of `Incident` and `FailureGroup` rows, and the only publisher of `incident` events.
  - `Checks` (`OcuTalon.Checks.Process`) owns the runs of `BackgroundCheck` rows and is the only publisher of the `check` event.
  - So `IncidentManager` must ask `Checks` to run the re-check. It cannot run the check or publish the `check` event itself.
  - Precedent: `WatchOps` sends `OcuTalon.Checks.Msg.CheckChanged` so that `Checks` publishes a watch the moment it starts or stops. A new message type goes into the spine's contract table in the same change.
- **What a check run writes.** Each run records its last run, its result (`passed`; `failed` with the finding; or `not_checked` with the reason), the time and the latest run's trace header id. Beside that `BackgroundCheck` update, it inserts one `OcuTalon.Digest.Data.CheckRun` row, which is what the digest's coverage reads. A production watch's check covers four things: the running state, new errors, the open incident and the latest run time, all read through `Watch.Reader`. A reader error or timeout gives `not_checked`.
- **The Tick does more than checks.** On each heartbeat `Tick`, `Checks` runs the due checks. It also sends `closeQuiet` for incidents whose last failure is more than 15 minutes old, sends the final `FixResult`s that `Fix.Run.Sweep()` returns, runs the due agent-heartbeat beats and forwards the Tick to `Digest`. A re-check must take none of these paths.
- **Transitions.** These are the moves 5.15 hooks:
  - `fixing` → `resolved` on a final `FixResult` (interrupted runs included), when no approved request is waiting. If a later request is pending, the move goes to `awaiting_approval` instead.
  - `awaiting_approval` → `open` (rejected) when the rejected request was the only one pending. A rejection while another request is pending stays `awaiting_approval`.
  - A `FixResult` that arrives late reaches `IncidentManager` from `Checks`' sweep, not from `FixExecutor`.
- **Scope (AD-4).** A failure tagged with a session's `TraceRef` belongs to that session. Untagged failures have scope `instance`, which never arises on the online demo.
- **The status answer and the all-clear (AD-28).** The read-only `check_status` tool returns the session's latest check results, and only `Checks.Render` chooses the all-clear key. The reply guard still runs exactly once.
- **Test hygiene (DW-289).** A real `HeartbeatIn` Tick every minute runs any due check row and sweeps quiet incidents in the middle of a test. Fixture check rows need a future `NextDueAt` unless the test means to run them, and a test must not let a real Tick change its outcome.
- **Ownership and tests.** Epic 5 is Lane A. Tests are `%UnitTest` classes named `OcuTalon.Test.<Area>`, for example `OcuTalon.Test.Checks` and `OcuTalon.Test.Watch`.

## UX & Interaction Patterns

- The incident card, the status answer and the rail's Background checks row must never contradict one another after a fix or a rejection. The row shows each check's name, schedule, last run, result and trace target, and the rail's text does not change.

## Cross-Story Dependencies

- 5.15 builds on:
  - 5.5 (the transition table in `IncidentManager`);
  - 5.6 (the `Checks` runs, the `check` event and `CheckChanged`);
  - 5.7 (`check_status` and `Checks.Render`);
  - 5.10 (DW-289's test hygiene);
  - Epic 7 (`FixExecutor`'s final `FixResult` and the approval outcomes from `ApprovalHold`).
- It ships in release 1.0.5, after the 1.0.4 cut.
