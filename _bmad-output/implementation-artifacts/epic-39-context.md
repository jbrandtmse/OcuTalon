# Epic 39 Context: A heartbeat checks your list and stays quiet unless something needs you

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Each person keeps a short checklist that OcuTalon looks at on a schedule (the agent heartbeat, or beat), with their own interval and active hours. The existing one-minute tick only finds the beats that are due and never calls the model; each due beat that isn't skipped becomes one attention decision over the checklist and a status snapshot built by code. So a person's beats call the model at most once per interval (30 minutes at the shortest) and only when something may need a decision. Ignore stays silent, a beat never gives an all-clear, and every beat and its cost is visible in Visual Trace and on a Heartbeat checklist card. The owner's hard constraint: the model is never called every minute. The epic has been re-opened for one fix-forward story, 39.11: the install's production check must name only items that are meant to run and don't, so an item turned off by default (TelegramIn without a bot) never shows as "not running" and never fails a start, a check or the heartbeat schedule tests.

## Stories

- Story 39.1: Fix the heartbeat's names and contracts
- Story 39.2: Save your heartbeat settings and ask for a beat
- Story 39.3: Beats fall due on the tick, and skip without a model call when they should
- Story 39.4: Each beat carries your checklist and a status snapshot built by code
- Story 39.5: The Heartbeat checklist card, and Run the heartbeat now
- Story 39.6: Evaluation cases for the heartbeat
- Story 39.7: Publish the heartbeat event
- Story 39.8: Run now and a saved heartbeat read what is stored
- Story 39.9: Heartbeat follow-up: today's cost matches its check-ins, and the tidy-ups
- Story 39.10: The heartbeat production test is stable (DW-639)
- Story 39.11: The install's production check doesn't name an item that is turned off by default

## Requirements & Constraints

**The beat (39.1 to 39.9, done), for orientation:**

- **Values, per person:** on/off; a plain-text checklist of at most 1,000 characters; an interval of 30, 60, 120, 240, 480 or 1440 minutes; active hours as quarter-hour `HH:MM` in the instance zone, or all day. Skips (no model request): empty checklist, outside hours, back-off, day capped, no key, snapshot unchanged since the last Ignore. Run now: at most every 2 minutes, inside the daily cap.
- **No all-clear and event privacy:** a beat has no check row, result or coverage entry; the `heartbeat` event never carries the `SessionRef`, the checklist's text or a snapshot key.

**Schedule test diagnostics (39.10, done):** when `OcuTalon.Test.Schedule.Heartbeat`'s "and the production runs every item" pin fails, its message names every missing item and its job's state. The flake's cause was not reproduced then; the fix waited for the next named occurrence.

**The production check (39.11, backlog):**

- The named occurrences all show TelegramIn with its System Default Settings row of Enabled at 0, the production's runtime flag for it at 1, and no job. `Install.Step.Production.NotRunning()` reads only the runtime flag; `Runners()` in the same class already honours the row.
- First (Task 0, before the fix, on lane C's slot or a throwaway stack): measure how Ens comes to hold the runtime flag at 1 while the row says 0, and record what Ens does, with evidence, in the spec's Design Notes. A cause in OcuTalon's own install or update code is reported, and fixed only if it lies inside `Install/Step/Production.cls` and this story's intent; anything wider goes to the Planner first.
- `NotRunning()` must not name an item whose row of Enabled is 0, even with the runtime flag at 1. An enabled item (no row, or a row of 1) with a pool and no live job is still named.
- Each of the two cases gets a pinning test with a demonstrated mutation. No user-facing string changes. Don't delete, weaken or move existing pins, add waits or raise timeouts.

## Technical Decisions

- **Lanes:** Lane A owns `Checks`, `Checks.Beat`, `HeartbeatBeat`, Triage, `Test.Checks` and the installer's core, including `Install.Step.Production` (39.11's home). Lane B owns the command classes, `SettingsOps`, `SessionOps`, web routes, `web/`, `Live/` and `OcuTalon.Test.Schedule` (39.10). A need in another lane's files becomes a sibling story.
- **The Production install step** starts `OcuTalon.Production`, or restarts every item if it is running, and waits until every enabled item runs and every runner resolves a model. It recovers a Troubled production with IRIS's recover and never cleans it or kills application data. An item "runs" when it has a running job (pool 0 for adapterless services, 1 otherwise).
- **Enabled state:** the production class holds structure only (items, classes, pool sizes, enabled flags). Values an install or admin may change live in System Default Settings, so reinstalling the class keeps them. `TelegramIn` and `TelegramOut` are enabled only when Telegram is included and a bot token is set; `EvalIn` only through a System Default Settings row the step writes from `OCUTALON_EVAL` at every start.
- **Warnings:** a step reports a non-fatal condition with `Install.Step.Warn(text)`, which never changes the step's result.
- **Schedule tests' environment:** they act on the running production, the Task Manager and the status marks, so they run only in throwaway compose stacks and CI (the image shard `lane-b`), never on a developer instance, and must leave everything as they found it.
- **No new scheduler, task or timer:** the beat runs from `Checks` on the existing one-minute tick, after the due checks, in its own Try/Catch.

## Cross-Story Dependencies

- **Done:** 39.1 to 39.10. **Backlog:** 39.11, a post-merge fix-forward re-open (Planner-ruled scope, after Story 32.7, which found the cause) with no boundary or dependency change.
- **39.11** depends on no other Epic 39 story. Every DW-639 red that 39.10's diagnostics named points at this check; 39.10's test and message must stay as they are.
- **Epic-level:** relies on Epics 2, 5 and 8 (`Intake`, `Checks`, the tick) and Epic 30's send seam.
