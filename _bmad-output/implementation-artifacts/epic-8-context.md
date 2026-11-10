# Epic 8 Context: Heartbeat and reminders, on time and surviving restarts

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 8 builds OcuTalon's clock in `OcuTalon.Schedule`. It runs on runner C, in Lane B's files. It delivers a heartbeat that ticks every minute and catches up once after a restart, a stalled warning, and reminders asked for in plain words. Stories 8.1 to 8.7 are done and merged. The epic is re-opened for release 1.0.6 (high priority, owner via the Contest Planner) for one story, 8.8. On the 1.0.5 online demo, after an update, the Task Manager task "OcuTalon heartbeat" came back Suspended, and nothing resumed it. With the task Suspended there are no ticks: the "Background checks have paused" banner shows, the digest reports "Not checked: Orders production", and watches never fire. Story 8.8 makes every start resume the task, so FR-32's promise holds after a restart with no hand fix on the host. It changes no product target.

## Stories

- Story 8.1: The heartbeat ticks every minute and catches up once after a restart (done)
- Story 8.2: The heartbeat-stalled warning comes from the real heartbeat (done)
- Story 8.3: A reminder fires on time on every channel (done)
- Story 8.4: Set, list and cancel reminders in plain words (done)
- Story 8.5: Reminders survive restarts and upgrades, and late ones say so (done)
- Story 8.6: Reminders through the chat on the demo path (done)
- Story 8.7: Epic 8 burn-down (done)
- Story 8.8: The heartbeat task resumes itself when it comes back Suspended (DW-1018)

## Requirements & Constraints

- **The heartbeat promise.** A tick runs every minute, and every run shows in Visual Trace. Minutes missed during a restart are caught up once, never replayed. When the last tick is more than 3 minutes old, the page shows it. A check that missed a run counts as not checked in the next digest.
- **Every start path resumes the task.** These are the after-start script's installer steps, an IPM install's steps, and a production start that no installer made, which `ReconcileIn` reconciles.
  - A Suspended task is resumed, and one log line names it.
  - A task that is not Suspended is left exactly as it was, with no line.
  - A missing task is created as today by the Tasks step, and the resume finds nothing to do.
- **No drift.** There is never a second task. The schedule and every other property stay as Story 8.1 declared them.
- **Live proof.** Suspend the task on a running instance, then restart. Within 2 minutes the task runs and a new tick is in `OcuTalon.Data.StatusMark`. That live unit goes in the CI group with the most headroom, never in `production`, `browser`, `install-fresh` or `install-upgrade`. Unit tests in `OcuTalon.Test.Schedule` cover the three cases.
- **Host check.** `release/demo-host-check.sh` prints a FAIL line and exits 1 when the last tick is more than 3 minutes old or the task is Suspended, as it does for any other failed check. It stays read-only and opens no new public read on the host. Its evidence comes the same way `--zone` and `--demo-status` bring theirs, unless the spec gate rules otherwise. `release/demo-host-checks.md` lists the new check.
- **Gates before implementing.**
  - The resume's log line and any new output line of `demo-host-check.sh` are PUBLIC TEXT. They go to the Contest Planner at the spec gate.
  - The `demo-host-check.sh` hunk is a RELEASE TOOL hunk, which the Planner rules on before the story merges.
  - Any new privilege, role, grant or resource the resume needs is named at the spec gate, which opens a veto window. `OcuTalonUser` is never widened.
- **Files in scope:**
  - `OcuTalon.Install.Step.Schedule` and `OcuTalon.Schedule.*`, with their tests under `OcuTalon.Test.Schedule`.
  - One new live script under `docker/tests/`, and Lane B's entries in `ci/units.sh`.
  - `release/demo-host-check.sh`, `release/demo-host-checks.md`, and that script's existing checks under `docker/tests/`.

## Technical Decisions

- **The heartbeat as built.** A Task Manager task calls the adapterless `HeartbeatIn` every minute, and `HeartbeatIn` sends one `Tick` to `Checks`. The task is declared in `OcuTalon.Install.Step.Schedule`'s `Tasks()`, and the installer core's task step (Lane A) creates it. `HeartbeatIn` writes the last tick time and the gaps to `OcuTalon.Data.StatusMark`. `StatusMonitor` checks every 15 s and raises `heartbeatStalled` past 3 minutes. The task does not replay runs that were missed while IRIS was down.
- **The installer leaves an existing task alone.** That matches the seed rule: a value is written only when it is absent. So the fix is a resume of the Suspended flag, not a recreate or an update of the task's definition.
- **Hooks at start.**
  - Each area declares a `Reconcile()` for its own waiters and rows. The `Reconcile` step calls every declaration at every start. On an IPM install, `ReconcileIn` also calls them on every production start, once the items are running.
  - Declarations must be idempotent, because on the Docker path both the step and `ReconcileIn` run them.
  - Lane B's Schedule declaration already re-arms `ReminderTimer`. The resume can sit beside it, or in the Schedule step, as long as all three start paths reach it.
- **Logging.** A step reports a non-fatal condition with `Install.Step.Warn(text)`. The registry writes `WARN <step> <text>` after the step's `STEP` line, in the after-start log only, and the step's result does not change. Where `Warn` is not available on a path, use the equivalent line that path already writes.
- **Evidence.** The fault seen on 1.0.5: Suspended 1, SuspendOnError 0, last run OK. A host-side patch on the demo already resumes the task.
- **Online demo.** The demo host's topology and its read-only check are Lane A release tooling, added in Story 29.3. The host check reads evidence only through channels it already has.

## Cross-Story Dependencies

- Story 8.8 restores Story 8.1's behaviour, so 8.1's single-task and catch-up tests must stay green. Story 8.5's reminder re-arm shares the `Reconcile` path and must also stay green.
- The installer core's task step and `ReconcileIn` are Lane A's. Changing either is a footprint extension and must be reported.
- The wider release-tool story for DW-446 and DW-485 is parked until after voting. Only DW-1018's host-check add-on goes ahead, in this story.
- This epic owns DW-1018 in the ledger. It closes in Story 8.8, and Epic 8 merges after it.
