# Epic 39 Context: A heartbeat checks your list and stays quiet unless something needs you

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Each person keeps a short checklist that OcuTalon looks at on a schedule (the agent heartbeat, or beat), with their own interval and active hours. The existing one-minute tick only finds the beats that are due and never calls the model; each due beat that isn't skipped becomes one attention decision over the checklist and a status snapshot built by code. So a person's beats call the model at most once per interval (30 minutes at the shortest) and only when something may need a decision. Ignore stays silent, a beat never gives an all-clear, and every beat and its cost is visible in Visual Trace and on a Heartbeat checklist card. The owner's hard constraint: the model is never called every minute. The epic's last story makes the heartbeat schedule tests pass every time on a correct tree, so a red on CI's image shard means a real defect.

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

## Requirements & Constraints

**The beat (39.1 to 39.9, all done):**

- **Values, per person:** on/off; a plain-text checklist of at most 1,000 characters; an interval of 30, 60, 120, 240, 480 or 1440 minutes (nothing under 30); active hours as quarter-hour `HH:MM` in the instance zone, or both empty for all day. Defaults: on, 30, 08:00 to 20:00, empty checklist. Online demo: off by default, sample checklist not stored until saved; values go at sign-out and at the reset.
- **Saving:** refuse `{{`, `@{` or a control character other than a line break, with nothing written; audit first (never the checklist's text), then write. A tick reads through the 60-second settings cache; a run-now reads stored values.
- **Skips (no model request), in order:** empty checklist; outside active hours; back-off; day capped; no key; snapshot unchanged since the last Ignore. Run now: at most once every 2 minutes per session, inside the daily cap; 202, or 409 with `availableAt` or the reason.
- **Failure and restart:** a fallback sets a back-off of 4 hours (or one interval if longer); a beat missed across a restart runs once; nothing that decides "due" lives in memory.
- **No all-clear and event privacy:** a beat has no check row, result or coverage entry; the `heartbeat` event never carries the `SessionRef`, the checklist's text or a snapshot key.
- **Cost:** each beat decision under $0.001 on Claude Haiku 5.5; a default day under $0.03.

**Stable schedule test (39.10):**

- `OcuTalon.Test.Schedule.Heartbeat` (the one-minute tick task's tests, Story 8.1, not the agent beat) intermittently fails `TestAfterAllTestsNothingSaved` at "and the production runs every item" (`Install.Step.Production.NotRunning()` not empty) in CI's image shard lane-b; three heads in about six hours, each green on one rerun.
- First confirm the cause with evidence: the old code must fail under a repeat or load run.
- The fix is test-only unless the cause is in the product; a product cause is ruled before any product code changes.
- The fixed test passes 20 of 20 runs under the same load. No pin is deleted or weakened, and raising a timeout is not a fix.
- A red on 39.10's own head is a real failure, not a flake.
- Pin each behaviour change with a demonstrated mutation.

## Technical Decisions

- **Lanes:** Lane A: 39.1, 39.3, 39.4, 39.6, 39.8, 39.10 (`Checks`, `Checks.Beat`, `HeartbeatBeat`, `BeatNow`, Triage, `Test.Checks`, and for 39.10 the `Test.Schedule.Heartbeat` test). Lane B: 39.2, 39.5, 39.7 (command classes, `Msg.Enum`, `SettingsOps`, `SessionOps`, web routes, `web/`, `Live/`). 39.9 ran across both lanes on one runner. A need in another lane's files becomes a sibling story.
- **No new scheduler, task or timer.** A Task Manager task calls the adapterless `HeartbeatIn` every minute, which sends a `Tick` to `Checks`; beats run from `Checks` on that tick, after the due checks, in their own Try/Catch.
- **Settings keys:** `person.<SessionRef>.heartbeat.on|interval|from|to|checklist` in `OcuTalon.Data.Setting`; `SettingsOps` is the only run-time writer; the `SessionRef` comes only from the server-side session.
- **A running beat** sends `Intake` one untrusted `Msg.Item` on channel `heartbeat` in its own trace session; the next tick reads its `decide` decision by `ItemId` and records outcome, fallback, cost and trace. Act runs one read-only untrusted turn and raises no approval request.
- **Schedule tests' environment:** they act on the running `OcuTalon.Production`, the Task Manager and the status marks, so they run only in throwaway compose stacks and CI, never on a developer instance. `%UnitTest` classes run sharded by whole area through `ci/iris.sh`; Schedule is in the `lane-b` shard. The class's after-test hooks must leave the task, `HeartbeatIn`, the production (running with every item) and the marks as they found them.
- **Storage:** persistent classes are append-only with committed storage blocks.

## UX & Interaction Patterns

- All card and skip texts are fixed in EXPERIENCE.md under the "Heartbeat checklist" card; ship no text the author hasn't accepted. Any change of shown text is public text and is ruled before it is committed.
- The card (`web/src/app/rail/heartbeat-card/`) shows the schedule line ("Every {interval}, {from} to {to} · Next check-in {time}"; 60 minutes reads "Every hour"), the last check-in or skip, and "Today: {n} check-ins, {cost}", whose count and total agree. It updates from `heartbeat` events without a reload.
- 39.10 changes no shown text.

## Cross-Story Dependencies

- **Done:** 39.1 to 39.9 (39.9 merged; it fixed the Today total, the "Every hour" line and the shared overview helper, and added fingerprint diagnostics to GuideApi). **Backlog:** 39.10, a post-merge fix-forward re-open with no boundary or dependency change.
- **Story 39.10** depends on no other Epic 39 story. It touches the tick task's tests from Epic 8 (Story 8.1) and the production start check in `Install.Step.Production` (Lane A); any product change there is ruled first.
- **Epic-level:** relies on Epics 2, 5 and 8 (`Intake`, `Checks`, the tick) and Epic 30's send seam (Story 30.4).
