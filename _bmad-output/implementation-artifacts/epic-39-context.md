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
- Story 39.8: Run now and a saved heartbeat read what is stored
- Story 39.9: Heartbeat follow-up: today's cost matches its check-ins, and the tidy-ups

## Requirements & Constraints

- **Values, per person:** on/off; a plain-text checklist of at most 1,000 characters; an interval of 30, 60, 120, 240, 480 or 1440 minutes (nothing under 30 on any install); active hours as quarter-hour `HH:MM` in the instance zone, or both empty for all day. Defaults: on, 30, 08:00 to 20:00, empty checklist (so a new person makes no model call until they write one). On the online demo: off by default, with a sample checklist that isn't stored until saved; values go at sign-out and at the reset.
- **Saving:** refuse any value holding `{{`, `@{` or a control character other than a line break (emoji and other printable characters are fine), with a plain message and nothing written. Audit first (type `Settings`: IRIS user, `SessionRef`, keys changed, never the checklist's text), then write the keys. A change applies within 60 seconds (the settings cache).
- **Saved values must take effect:** a run-now reads the stored values, not the Checks process's 60-second cache, so a save followed at once by Run now is never refused as empty; a tick still reads through the cache. A shorter saved interval reschedules: from the first tick that reads it, the next beat is due at `LastBeatAt` plus the new interval, or at once if that has passed. A longer interval keeps the stored `NextDueAt` until the next beat, which then uses it.
- **Skips (no model request), checked in order:** empty checklist; outside active hours; back-off running; day capped; no key; snapshot unchanged since the last Ignore. A skip records its reason and moves the next due time: to the next active-hours start when outside hours, otherwise one interval on.
- **Run now:** an explicit request, at most once every 2 minutes per session, inside the daily cap. Active hours and an unchanged snapshot don't hold it back; the other skip rules do. The route answers 202, or 409 with `availableAt` during the cooldown, or 409 with the reason when capped, keyless or empty.
- **Failure and restart:** a fallback notifies as for any item and sets a back-off of 4 hours (or one interval if longer). A beat missed across a restart runs once. Nothing that decides "due" lives in memory.
- **No all-clear:** a beat is not a background check: no check row, result or coverage entry, and no code renders a beat or an Ignore as "everything is fine". Its reasons pass the guard like any model text.
- **Event privacy:** the `heartbeat` event never carries the `SessionRef`, the checklist's text or a snapshot key. A tick's empty-checklist skip saves its row but publishes nothing; a run-now always publishes.
- **Cost:** each beat decision under $0.001 on Claude Haiku 5.5; a default day under $0.03.
- **Security overview:** must say a beat sends the checklist and a status snapshot to the model provider at most once per interval; once the run-now route ships, it must also name a beat the person runs now (2-minute rule, daily cap).
- **Today line must add up (follow-up):** on the 1.0.2 online demo the card showed "Last check-in … · $0.0003" with "Today: 1 check-in, $0.0006" (after a Watch, an incident approval, a save with heartbeat on, then a run-now that decided Act with read-only checks). First record, with evidence, exactly what Today's total sums (a second beat or decision, the notice, the run-now turn, or something else); then make the count and the total agree, or make the line say what it sums. Any change of shown text is public text and must be ruled before it is committed. A regression test reproduces the one-check-in, double-cost case.
- **"Every hour":** a 60-minute interval reads "Every hour, {from} to {to}" (or "Every hour" all day), never "Every 1 hour"; every other interval reads exactly as before ("Every 30 minutes", "Every 2 hours", …). Pin it with a fixed-strings test; amend EXPERIENCE.md in place, with a marker, if it quotes the old form.
- **Test hygiene:** the security-overview check duplicated in `docker/tests/test-heartbeat-overview.sh` and `docker/tests/test-triage-heartbeat.sh` moves into one shared helper, with each script still checking exactly what it checks today (no pin deleted or weakened). `OcuTalon.Test.Web.GuideApi`'s `TestOnlyTheMarkerChanges` and `TestRunAgain` print both fingerprints when they fail on a fingerprint; fix the race only if its cause is plain and in Epic 39's code, otherwise record the residual.
- **Tests:** each behaviour change is pinned with fixed clocks and the CI mock's request log, with a demonstrated mutation.

## Technical Decisions

- **Lanes:** Lane A: 39.1, 39.3, 39.4, 39.6, 39.8, 39.9 (`Checks`, `Checks.Beat`, `HeartbeatBeat`, `BeatNow`, Triage, `Test.Checks`). Lane B: 39.2, 39.5, 39.7 (command classes, `Msg.Enum`, `CommandsIn`, `SettingsOps`, `SessionOps`, web routes, `web/`, `Live/Publish.cls`, `Live/Payload/Heartbeat.cls`). Each story keeps its home lane's files; a need in the other lane's files becomes a sibling story.
- **No new scheduler, task or timer.** Beats run from `Checks` on the tick, after the due checks, in their own Try/Catch. Values are read via `OcuTalon.Data.Setting.Get` (60-second per-process cache).
- **Settings keys:** `person.<SessionRef>.heartbeat.on|interval|from|to|checklist` in `OcuTalon.Data.Setting`. `SettingsOps` is the only run-time writer. The `SessionRef` comes only from the server-side session, never the client; an admin gets no right to another person's values.
- **Commands:** `OcuTalon.Msg.Command.SetHeartbeat` (`On`, `Interval`, `From`, `To`, `Checklist`, plus `Origin`, `IdempotencyKey`, `SessionRef`) routes to `SettingsOps`; `RunHeartbeat` routes to `Checks` as `OcuTalon.Checks.Msg.BeatNow`. Both accepted from origin `web_user` only; the governance test refuses each from origin `tool`. `Msg.Enum` CHANNEL has `heartbeat` appended at the end.
- **Routes (session-checked):** `GET`/`PUT /api/v1/heartbeat` (values plus the `HeartbeatBeat` row's public view; defaults when unset) and `POST /api/v1/heartbeat/run`. `SessionOps.End` deletes a demo session's `person.<SessionRef>.heartbeat.*` keys.
- **A running beat** sends `Intake` one `Msg.Item` asynchronously (new `ItemId`, provenance `untrusted`, channel `heartbeat`, Subject "Heartbeat check-in", Text from `Beat.Snapshot`) in its own trace session with `SuperSession` = the session's `TraceRef`. The next tick reads its `Decision` (Kind `decide`) by `ItemId` and records outcome, fallback, cost, decision ref and trace session; on Ignore, `LastSnapshotKey` is copied to `LastQuietKey`.
- **Outcomes:** Triage (no tools) decides. Ignore records only. Digest, Tell now and Act go as for any untrusted item; Act runs one read-only untrusted turn and raises no approval request.
- **Snapshot key:** `Beat.Key` is a SHA-256 of the checklist and entry lines, excluding the "Status at" line, so no entry line may carry a time that moves every beat.
- **Storage:** persistent classes are append-only with committed storage blocks; `HeartbeatBeat` lives under `^OcuTalonP.`.

## UX & Interaction Patterns

- All card texts, the skip texts, the sample checklist and Triage's heartbeat paragraph are fixed in EXPERIENCE.md under Later Steps > Personality ("Heartbeat checklist" card). Use them exactly; ship no text the author hasn't accepted. The cost-cap skip now reads "Skipped at {time}: today's cost limit has been reached.", matching the "today's cost limit" wording of the card's Run line and the catalog.
- The card is its own component under `web/src/app/rail/heartbeat-card/` with one slot in `rail-view.ts`, and updates from `heartbeat` events without a reload.
- It shows off/on with interval, hours and next check-in ("Every {interval}, {from} to {to} · Next check-in {time}"; 60 minutes reads "Every hour"); the last check-in (time, outcome in the UX's terms, cost, a `TraceLink` trace link) or the last skip's reason; and today's count and cost ("Today: {n} check-ins, {cost}").
- Edit opens in place: checklist with a "{n} of 1,000 characters" counter, interval (30 minutes up only), active hours, on/off, Save. On save show "Saved. Applies within a minute. Recorded in the audit log." or the refusal beside the field. Every control labelled and keyboard-operable.
- "Run the heartbeat now": disabled during cooldown with "You can run it again at {time}."; unavailable with the reason at the cap or with no key (reuse an accepted text; escalate if none fits).
- Online demo: off, sample checklist shown, plus the online-demo note. The unsaved sample isn't stored, so a run on it would be refused as empty: the card saves the sample before offering Run now, or keeps Run unavailable until a save.
- Playwright specs in `web/e2e/heartbeat-card.spec.ts` (fixtures and CI mock) cover the states, the refusal, the cooldown and the demo variant. They leave the demo-path specs unchanged, except the rail's section count in `web/e2e/demo-path/01-page.spec.ts`: seven headings, Heartbeat checklist before Persona, so Persona stays last.

## Cross-Story Dependencies

- **Done:** 39.1 to 39.8; the epic merged and was on the 1.0.2 online demo. **Backlog:** 39.9 (Lane A), a post-merge fix-forward re-open with no boundary or dependency change.
- **Story 39.9** builds on 39.5's card (its Today and schedule lines) and the beat recording of 39.3 and 39.8. Split rule: if the test-hygiene groups (shared overview helper, GuideApi fingerprints) would miss the 1.0.3 merge line, they split off as Story 39.10; the Today-cost fix and "Every hour" stay in 39.9.
- **Epic-level:** relies on Epics 2, 5 and 8 (`Intake`, `Checks`, the tick) and Epic 30's send seam (Story 30.4).
- **Release check:** the hands-on pass with real keys runs one beat of each outcome, sees a quiet beat followed by a skip while nothing changes, and does a run-now on the demo host; 39.9 targets the 1.0.3 merge line.
