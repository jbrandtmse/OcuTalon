# Epic 39 Context: A heartbeat checks your list and stays quiet unless something needs you

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Each person keeps a short checklist that OcuTalon looks at on a schedule (the agent heartbeat, or beat), with their own interval and active hours. The existing one-minute tick only finds the beats that are due and never calls the model. Each due beat that isn't skipped becomes one attention decision over the checklist and a status snapshot built by code, so a person's beats call the model at most once per interval and only when something may need a decision. Ignore stays silent, a beat never gives an all-clear, and every beat and its cost shows in Visual Trace and on a new Heartbeat checklist card. The owner's hard constraint is that the model is never called every minute.

## Stories

- Story 39.1: Fix the heartbeat's names and contracts
- Story 39.2: Save your heartbeat settings and ask for a beat
- Story 39.3: Beats fall due on the tick, and skip without a model call when they should
- Story 39.4: Each beat carries your checklist and a status snapshot built by code
- Story 39.5: The Heartbeat checklist card, and Run the heartbeat now
- Story 39.6: Evaluation cases for the heartbeat
- Story 39.7: Publish the heartbeat event

## Requirements & Constraints

- **Values, per person:** on/off; a checklist of up to 1,000 characters; an interval of 30, 60, 120, 240, 480 or 1440 minutes (nothing shorter on any install); active hours as quarter-hour `HH:MM` in the instance zone, or both empty for all day. Defaults are on, 30, 08:00 to 20:00 and an empty checklist, so a new person costs nothing until they write one. On the online demo it is off, with a sample checklist that isn't stored until saved, and the values go at sign-out and at the reset.
- **Saving:** refuse `{{`, `@{` and any control character other than a line break, with a plain message and nothing written. Write the audit entry first (never the checklist's text), then the values. A change applies within 60 seconds.
- **Skips, with no model request, checked in this order:** empty checklist; outside active hours; back-off running; day capped; no key; snapshot unchanged since the last Ignore. A skip records its reason and moves the next due time on: to the next active-hours start when outside hours, otherwise by one interval.
- **Run now:** an explicit request, at most once every 2 minutes per session. Active hours and an unchanged snapshot don't hold it back; the other skip rules do. The route answers 409 with `availableAt`, or with the reason.
- **Failure and restart:** a fallback notifies the person as for any item and backs off 4 hours, or one interval if that is longer. A beat missed across a restart runs once. Nothing that decides "due" lives in memory.
- **Snapshot:** the checklist, a "Status at" line, then entry lines for open incidents, watches (production and last check result, with no time), pending approval requests, reminders due before the next beat, and at most 10 decisions since the last beat that made a decision. It stops at 4,000 characters. It never holds model-written text, a diagnosis cause, decision reasons, event-log or message text, keys or OcuTalon's own identities. A decision's code-written `Summary` stays as stored, cut at 80 characters with no message body, and it can quote outside content, so the beat stays untrusted: on Act its turn can only look, notify and save, with no approval request.
- **No all-clear:** a beat has no check row, check result or coverage entry, and no code renders a beat or an Ignore as "everything is fine". Beat reasons pass the all-clear guard.
- **Cost:** each decision must cost under $0.001 on Claude Haiku 5.5, and a default day under $0.03.
- **Model-call tests** use the CI mock's request log and fixed clocks: no request on a tick that isn't a due beat or on a beat unchanged since an Ignore, exactly one on a changed beat, and at most two in an hour on a 30-minute interval.
- **Security overview:** it must say that a beat sends the checklist and snapshot to the model provider at most once per interval. Once the run-now route ships, it must also name a beat the person runs now, with the 2-minute rule and the daily cap. At the epic's close, re-check that its no-names sentence and the snapshot's "never holds" rule still hold.
- **Evaluation record (carried by Story 39.6):** `Eval.Record` accepts an empty `fixKind` only for a `data_format_change` case that expects no repair; every other case still refuses, and tests pin the one acceptance and each refusal. Add one ambiguous-date case whose arrival days match neither reading, expecting no repair proposed.

## Technical Decisions

- **Home lanes:** Lane A owns 39.1, 39.3, 39.4 and 39.6; Lane B owns 39.2, 39.5 and 39.7. Each story keeps its home lane's files. `Checks`, `Checks.Beat`, `HeartbeatBeat`, `BeatNow` and Triage are Lane A. `Msg.Enum`, the command classes, `CommandsIn`, `SettingsOps`, `SessionOps`, `Web.Api`, `web/` and `Live/Publish.cls` are Lane B.
- **Story 39.7** creates `Live/Payload/Heartbeat.cls` and edits `Live/Publish.cls` TYPES, `Test.Live.Payloads` and `web/src/app/live/payloads.ts` (regenerated), all landing together before the event is published, on the base that already holds Epic 7's changes to those files. By ruling it may also edit `Checks/Process.cls` (the publish call) and `Test/Checks/Heartbeat.cls` as footprint extensions; its home stays Lane B.
- **Shared with Epics 40 and 41:** `Agent.Input`, Triage's instructions, `Msg.Enum`, `SettingsOps`, `CommandsIn`, `SessionOps.End`, `Web.Api` and the rail. Each epic appends its own entry.
- **No new scheduler, task or timer.** Beats run from `Checks` on the tick, after the due checks, in their own Try/Catch. Values are read through `Data.Setting.Get`.
- **Settings:** the keys are `person.<SessionRef>.heartbeat.on|interval|from|to|checklist`. `SettingsOps` is the only writer at run time. The `SessionRef` comes only from the server-side session, and an admin gets no right to another person's values.
- **Commands:** `SetHeartbeat` (`On`, `Interval`, `From`, `To`, `Checklist`) goes to `SettingsOps`, and `RunHeartbeat` goes to `Checks` as a `BeatNow`. Both are accepted from origin `web_user` only, and the governance test refuses each from origin `tool`. The routes are `GET`/`PUT /api/v1/heartbeat` and `POST /api/v1/heartbeat/run` (202 or 409).
- **A beat that runs** sends `Intake` one `Msg.Item` asynchronously (provenance `untrusted`, channel `heartbeat`, Subject "Heartbeat check-in") through Epic 30's send seam, in a new trace session under the session's `TraceRef`. A later tick reads its `Decision` by `ItemId` and records the result. On Ignore, the sent key becomes `LastQuietKey`.
- **Snapshot key:** `Beat.Key` is a SHA-256 of the checklist and the entry lines, leaving out the "Status at" line, so no entry line may carry a time that moves every minute.
- **Heartbeat event:** the row's public view on the session's stream, after each committed beat, skip or result. It never carries the `SessionRef`, the checklist's text or a snapshot key.
- **Evaluation:** cases go under `eval/heartbeat-*/` (channel `heartbeat`, provenance `untrusted`, recorded snapshot text) and at least one is held back from prompt work. They run on the mock on every push and on the real model for each release candidate; the existing cost gate covers them.

## UX & Interaction Patterns

- Every card text, the sample checklist and Triage's heartbeat paragraph are fixed in EXPERIENCE.md under Later Steps › Personality. Use them exactly: no text ships that the author hasn't accepted.
- The card is its own component under `web/src/app/rail/heartbeat-card/`, with one slot in `rail-view.ts`. It follows the status rail card pattern and updates from `heartbeat` events without a reload.
- It shows its state, then either the last check-in (time, outcome in the UX's terms, cost and a `TraceLink` link) or the last skip's reason, and today's cost. Edit opens in place, with a counter out of 1,000, and refusals show beside the field. Every control is labelled and works by keyboard.
- The run button is disabled during a cooldown ("You can run it again at {time}."). At the cap or with no key it is unavailable, with the reason as a visible caption. The UX has no text for that unavailable state, so reuse an accepted text or escalate.
- Playwright specs go in `web/e2e/heartbeat-card.spec.ts` and leave the demo-path specs unchanged.

## Cross-Story Dependencies

- **Done:** Stories 39.1, 39.3 and 39.4. The names, stubs, beat logic, snapshot, key and Triage's paragraph are in place. Story 39.6 is being re-planned on the tree merged with Epic 7, to take in the evaluation-record change.
- **Story 39.2** waits on Epic 40: it extends Epic 40's per-person machinery in `SettingsOps`, `SessionOps.End` and `CommandsIn` rather than duplicating it. Beats may send channel `heartbeat` before the `Msg.Enum` append lands. It also owns the security overview's run-now sentence.
- **Story 39.5** needs 39.2's routes, 39.7's event and Epic 31 (the live client and `/state`).
- **Story 39.6** needs 39.3 and 39.4 end to end, and Epic 14 (the security overview).
- **The epic** needs Epics 2, 5 and 8 (`Checks`, the tick, `Intake`) and Epic 30's send seam (Story 30.4).
- **Merge and release:** the epic merges only once `release/1.0.0-rc1` exists. It ships in the first daily release after that, when the Contest Planner's hands-on pass runs each outcome, a quiet beat followed by a skip, and a run-now on the demo host.
