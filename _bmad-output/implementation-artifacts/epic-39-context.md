# Epic 39 Context: A heartbeat checks your list and stays quiet unless something needs you

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Each person keeps a short checklist that OcuTalon looks at on a schedule (the agent heartbeat, or beat), with their own interval and active hours. The existing one-minute tick only finds the beats that are due and never calls the model; each due beat that isn't skipped becomes one attention decision over the checklist and a status snapshot built by code. So a person's beats call the model at most once per interval (30 minutes at the shortest) and only when something may need a decision. Ignore stays silent, a beat never gives an all-clear, and every beat and its cost is visible in Visual Trace and on a Heartbeat checklist card. The owner's hard constraint: the model is never called every minute.

## Stories

- Story 39.1: Fix the heartbeat's names and contracts
- Story 39.2: Save your heartbeat settings and ask for a beat
- Story 39.3: Beats fall due on the tick, and skip without a model call when they should
- Story 39.4: Each beat carries your checklist and a status snapshot built by code
- Story 39.5: The Heartbeat checklist card, and Run the heartbeat now
- Story 39.6: Evaluation cases for the heartbeat
- Story 39.7: Publish the heartbeat event

## Requirements & Constraints

- **Values, per person:** on/off; a plain-text checklist of at most 1,000 characters; an interval of 30, 60, 120, 240, 480 or 1440 minutes (nothing under 30 on any install); active hours as quarter-hour `HH:MM` in the instance zone, or both empty for all day. Defaults: on, 30, 08:00 to 20:00, empty checklist (so a new person makes no model call until they write one). On the online demo: off by default, with a sample checklist that isn't stored until saved; values go at sign-out and at the reset.
- **Saving:** refuse any value holding `{{`, `@{` or a control character other than a line break (emoji and other printable characters are fine), with a plain message and nothing written. Audit first (type `Settings`: IRIS user, `SessionRef`, keys changed, never the checklist's text), then write the keys. A change applies within 60 seconds (the settings cache).
- **Skips (no model request), checked in order:** empty checklist; outside active hours; back-off running; day capped; no key; snapshot unchanged since the last Ignore. A skip records its reason and moves the next due time: to the next active-hours start when outside hours, otherwise one interval on.
- **Run now:** an explicit request, at most once every 2 minutes per session, inside the daily cap. Active hours and an unchanged snapshot don't hold it back; the other skip rules do. The route answers 202, or 409 with `availableAt` during the cooldown, or 409 with the reason when capped or keyless.
- **Failure and restart:** a fallback notifies as for any item and sets a back-off of 4 hours (or one interval if longer). A beat missed across a restart runs once. Nothing that decides "due" lives in memory.
- **No all-clear:** a beat is not a background check: no check row, result or coverage entry, and no code renders a beat or an Ignore as "everything is fine". Its reasons pass the guard like any model text.
- **Event privacy:** the `heartbeat` event never carries the `SessionRef`, the checklist's text or a snapshot key. A tick's empty-checklist skip saves its row but publishes nothing; a run-now always publishes.
- **Cost:** each beat decision under $0.001 on Claude Haiku 5.5; a default day under $0.03.
- **Security overview:** must say a beat sends the checklist and a status snapshot to the model provider at most once per interval; once the run-now route ships, it must also name a beat the person runs now (2-minute rule, daily cap).

## Technical Decisions

- **Lanes:** Lane A: 39.1, 39.3, 39.4, 39.6 (`Checks`, `Checks.Beat`, `HeartbeatBeat`, `BeatNow`, Triage). Lane B: 39.2, 39.5, 39.7 (command classes, `Msg.Enum`, `CommandsIn`, `SettingsOps`, `SessionOps`, web routes, `web/`, `Live/Publish.cls`, `Live/Payload/Heartbeat.cls`). Each story keeps its home lane's files.
- **No new scheduler, task or timer.** Beats run from `Checks` on the tick, after the due checks, in their own Try/Catch. Values are read via `OcuTalon.Data.Setting.Get`.
- **Settings keys:** `person.<SessionRef>.heartbeat.on|interval|from|to|checklist` in `OcuTalon.Data.Setting`. `SettingsOps` is the only run-time writer. The `SessionRef` comes only from the server-side session, never the client; an admin gets no right to another person's values.
- **Commands:** `OcuTalon.Msg.Command.SetHeartbeat` (`On`, `Interval`, `From`, `To`, `Checklist`, plus `Origin`, `IdempotencyKey`, `SessionRef`) routes to `SettingsOps`; `RunHeartbeat` routes to `Checks` as `OcuTalon.Checks.Msg.BeatNow` (`SessionRef`, `RequestedAt`). Both accepted from origin `web_user` only; the governance test refuses each from origin `tool`. `Msg.Enum` CHANNEL gains `heartbeat` appended at the end.
- **Routes (session-checked):** `GET`/`PUT /api/v1/heartbeat` (values plus the `HeartbeatBeat` row's public view; defaults when unset) and `POST /api/v1/heartbeat/run`. `SessionOps.End` deletes a demo session's `person.<SessionRef>.heartbeat.*` keys.
- **A running beat** sends `Intake` one `Msg.Item` asynchronously (new `ItemId`, provenance `untrusted`, channel `heartbeat`, Subject "Heartbeat check-in", Text from `Beat.Snapshot`) in its own trace session with `SuperSession` = the session's `TraceRef`. The next tick reads its `Decision` (Kind `decide`) by `ItemId` and records outcome, fallback, cost, decision ref and trace session; on Ignore, `LastSnapshotKey` is copied to `LastQuietKey`.
- **Outcomes:** Triage (no tools) decides. Ignore records only. Digest, Tell now and Act go as for any untrusted item; Act runs one read-only untrusted turn and raises no approval request.
- **Snapshot key:** `Beat.Key` is a SHA-256 of the checklist and entry lines, excluding the "Status at" line, so no entry line may carry a time that moves every beat.
- **Storage:** persistent classes are append-only with committed storage blocks (AD-5); `HeartbeatBeat` lives under `^OcuTalonP.`.

## UX & Interaction Patterns

- All card texts, the sample checklist and Triage's heartbeat paragraph are fixed in EXPERIENCE.md under Later Steps > Personality ("Heartbeat checklist" card). Use them exactly; ship no text the author hasn't accepted.
- The card is its own component under `web/src/app/rail/heartbeat-card/` with one slot in `rail-view.ts`, and updates from `heartbeat` events without a reload.
- It shows off/on with interval, hours and next check-in; the last check-in (time, outcome in the UX's terms, cost, a `TraceLink` trace link) or the last skip's reason; and today's count and cost.
- Edit opens in place: checklist with a "{n} of 1,000 characters" counter, interval (30 minutes up only), active hours, on/off, Save. On save show "Saved. Applies within a minute. Recorded in the audit log." or the refusal beside the field. Every control labelled and keyboard-operable.
- "Run the heartbeat now": disabled during cooldown with "You can run it again at {time}."; unavailable with the reason at the cap or with no key. The UX gives no text for that unavailable state: reuse an accepted text or escalate.
- Online demo: off, sample checklist shown, plus the online-demo note.
- Playwright specs in `web/e2e/heartbeat-card.spec.ts` (fixtures and CI mock) cover the states, the refusal, the cooldown and the demo variant, and leave the demo-path specs unchanged.

## Cross-Story Dependencies

- **Done:** 39.1, 39.3, 39.4, 39.6 and 39.7 (names, stubs, beat logic, snapshot, key, Triage paragraph, eval cases, the `heartbeat` event and payload). **Remaining:** 39.2 and 39.5 (both Lane B).
- **Story 39.2** builds on 39.1's names. Epic 40 (done) already put the persona area on the same per-person settings path (`SettingsOps`, `CommandsIn`, `SessionOps.End`, web routes); add the heartbeat area beside it rather than a parallel path. It also owns the security overview's run-now sentence.
- **Story 39.5** needs 39.2's routes, 39.7's event, and Epic 31's live client and `/state` (Story 31.1 is done).
- **Epic-level:** relies on Epics 2, 5 and 8 (`Intake`, `Checks`, the tick) and Epic 30's send seam (Story 30.4).
- **Merge and release:** the epic merges only once `release/1.0.0-rc1` exists, and ships in the first daily release after. That release's hands-on pass with real keys runs one beat of each outcome, sees a quiet beat followed by a skip while nothing changes, and does a run-now on the demo host.
