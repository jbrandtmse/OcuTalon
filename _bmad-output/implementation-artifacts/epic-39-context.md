# Epic 39 Context: A heartbeat checks your list and stays quiet unless something needs you

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Each person keeps a short plain-text checklist that OcuTalon looks at on a schedule (the "agent heartbeat", or beat). The existing one-minute tick only finds beats that are due and never calls the model. Each due beat becomes one attention decision over the checklist plus a status snapshot built by code, so a person's beats call the model at most once per interval (30 minutes by default and at the shortest), and only when something may need a decision. Ignore stays silent, a beat never gives an all-clear, and every beat and its cost can be seen in Visual Trace and on a new "Heartbeat checklist" rail card with a "Run the heartbeat now" button. The owner's hard constraint: the model is never called every minute.

## Stories

- Story 39.1: Fix the heartbeat's names and contracts (Lane A)
- Story 39.2: Save your heartbeat settings and ask for a beat (Lane B)
- Story 39.3: Beats fall due on the tick, and skip without a model call when they should (Lane A)
- Story 39.4: Each beat carries your checklist and a status snapshot built by code (Lane A)
- Story 39.5: The Heartbeat checklist card, and Run the heartbeat now (Lane B)
- Story 39.6: Evaluation cases for the heartbeat (Lane A)

## Requirements & Constraints

- **Per-person values:** on/off, checklist (max 1,000 chars), interval (30, 60, 120, 240, 480 or 1440 min only; nothing under 30 on any install), active hours (`HH:MM` on the quarter hour, default 08:00-20:00 in the instance zone, or both empty for all day). Defaults: on, 30, 08:00, 20:00, empty checklist, so a new person makes no model call until they write one. Online demo: off by default, sample checklist shown but not stored until saved.
- **Validation:** refuse `{{`, `@{` and any control character except a line break. A refused value returns a plain message and writes nothing. Changes are audited (type `Settings`: IRIS user, `SessionRef`, keys changed, never the checklist text) before the keys are written, and apply within 60 s (the setting cache).
- **Skip rules, in this order, with no model call:** empty checklist; outside active hours; back-off not over; daily cost cap reached; no model key; snapshot key equals the last quiet (Ignore) key. A skip records its reason and moves `NextDueAt` on (to the next active-hours start if outside hours, else one interval).
- **Run now:** explicit request; ignores active hours and an unchanged snapshot, still obeys empty checklist, back-off, cap and key. At most once per 2 minutes per session (refused with outcome `cooldown` and `availableAt`; HTTP 409). Cap reached or no key also gives 409 with the reason.
- **Fallback:** notifies as for any item, then sets back-off to 4 hours or one interval, whichever is longer.
- **Restart:** a beat missed across several intervals runs once. Nothing that decides "due" lives in memory.
- **Snapshot:** max 4,000 chars ending "(more not shown)" when cut; never a diagnosis cause, decision reasons, event-log or message text, keys or identities; empty lines say "none". It counts as untrusted arriving content.
- **No all-clear:** a beat has no `BackgroundCheck` row, check result or coverage entry; no code renders a beat or Ignore as "everything is fine"; its reasons pass the all-clear guard.
- **Cost:** a beat makes at most one Triage decision plus one read-only turn on act; each decision under $0.001 on Claude Haiku 5.5; a default day under $0.03.
- **Tests must pin model calls** via the CI mock's request log: none on a non-due tick, none on an unchanged-since-Ignore beat, exactly one on a changed beat, at most two in an hour of 30-minute ticks. Use fixed clocks; cover each skip reason, a midnight-spanning window, restart catch-up, cooldown and back-off.
- **Security overview** must say a beat sends the checklist and snapshot to the model provider, at most once per interval.

## Technical Decisions

- **No new scheduler/task/timer.** `Checks.Process` calls `OcuTalon.Checks.Beat.RunDue(tickAt)` after the due checks, in its own Try/Catch, and handles `OcuTalon.Checks.Msg.BeatNow` (`SessionRef`, `RequestedAt`). Values are read per tick via `OcuTalon.Data.Setting.Get`.
- **`OcuTalon.Checks.Beat`** (Lane A): `RunDue(tickAt)`, `RunNow(sessionRef)`, `Snapshot(sessionRef, now)`, `Key(snapshot)`. `Key` is SHA-256 of the checklist plus the snapshot's entry lines, excluding the "Status at" line, so two snapshots over the same records at different times match.
- **`OcuTalon.Data.HeartbeatBeat`** (Lane A), one row per session that has had a beat: `SessionRef`, `NextDueAt`, `LastBeatAt`, `LastItemId`, `LastOutcome`, `LastFallback`, `LastCostUSD`, `LastDecisionRef`, `LastTraceSessionId`, `LastSkipAt`, `LastSkipReason`, `LastRunNowAt`, `BackoffUntil`, `LastSnapshotKey`, `LastQuietKey`. Committed storage block, `DEFAULTGLOBAL` under `^OcuTalonP.`, row in `src/short-names.tsv`.
- **A beat that runs** sends `Intake` one `OcuTalon.Msg.Item`: new `ItemId`, provenance `untrusted`, channel `heartbeat`, the person's `SessionRef`, Subject "Heartbeat check-in", Text from `Beat.Snapshot`. Asynchronous, in a new trace session whose `SuperSession` is the session's `TraceRef`. Reuse Epic 30's `Checks`-to-`Intake` send seam (`INTAKE` setting). On the next tick, `Checks` reads the `Decision` (Kind `decide`, same `ItemId`) and records outcome, fallback, cost, decision ref and trace session; on Ignore copies `LastSnapshotKey` to `LastQuietKey`.
- **Skip inputs:** active hours through `Data.Time` (instance zone); cap via `Bridge.Budget.State()`; key via `Bridge.Keys.Status`.
- **Live event:** after every beat, skip or recorded result, `Checks` publishes `heartbeat` (`OcuTalon.Live.Payload.Heartbeat`, Lane A) with the row's public view: on, interval, hours, next due, last result, last skip. Never the `SessionRef`, checklist text or a snapshot key.
- **Settings keys:** `person.<SessionRef>.heartbeat.on|interval|from|to|checklist` in `OcuTalon.Data.Setting`; `SettingsOps` is the only run-time writer; `SessionRef` always from the server-side session; admins get no right to another person's values. `SessionOps.End` deletes a demo session's `person.<SessionRef>.heartbeat.*` keys.
- **Commands (Lane B):** `OcuTalon.Msg.Command.SetHeartbeat` (`On`, `Interval`, `From`, `To`, `Checklist` plus common fields `Origin`, `IdempotencyKey`, `SessionRef`) routed to `SettingsOps`; `RunHeartbeat` routed to `Checks` as `BeatNow`. Both accepted from origin `web_user` only; the governance test refuses each from origin `tool`. `Msg.Enum` CHANNEL gains `heartbeat` appended at the end.
- **REST (session-checked):** `GET`/`PUT /api/v1/heartbeat` (`SettingsOps`; GET returns values or defaults plus the row's public view); `POST /api/v1/heartbeat/run` (202, or 409 with `availableAt` or reason).
- **Triage:** append a static heartbeat paragraph (no `{{`) to `OcuTalon.Agent.Triage`'s `XData INSTRUCTIONS`; a test compares it with the UX source text. Triage has no tools; on act `Intake` runs a read-only untrusted turn and raises no approval request.
- **Ownership (spine AD-33 tables):** `HeartbeatBeat`, `BeatNow`, `Live.Payload.Heartbeat` and the `heartbeat` event are Lane A; the two routes, command classes, `Msg.Enum`, `SettingsOps`, `CommandsIn`, `SessionOps.End`, `Web.Api` and `web/` are Lane B. Story 39.1 verifies (and adds if missing) these rows and the names above in `ARCHITECTURE-SPINE.md`. Shared files with Epics 40/41 (`Agent.Input`, agent instructions, `Msg.Enum`, `SettingsOps`, `CommandsIn`, `SessionOps.End`, `Web.Api`, the rail) take append-only entries.
- **Built in Story 39.1 (done):** `HeartbeatBeat` (the 15 fields, unique `SessionRefIndex`, `^OcuTalonP.HeartbeatBeat`); `Checks.Msg.BeatNow` (`SessionRef`, `RequestedAt`); `Checks.Beat` with do-nothing stubs `RunDue`/`RunNow`/`Snapshot`/`Key` plus parameters `KEYS`, `INTERVALS`, `DEFAULTON`=1, `DEFAULTONDEMO`=0, `DEFAULTINTERVAL`=30, `DEFAULTFROM`, `DEFAULTTO`, `CHECKLISTMAX`=1000 and `SettingKey(sessionRef, name)`. Use these rather than restating literals. `Checks.Process` calls `RunDue` last on a Tick through the private seam `BeatRunDue` and answers `BeatNow` through seam `BeatRunNow`; the test probe `Test.Checks.Probe` overrides both and records `Beats`/`BeatNows`. Nothing new reaches `Intake` yet, and `test-production.sh`'s item list is unchanged. The spine already records the names (verbs, channel value, keys, defaults).
- **Heartbeat live payload not yet created:** `OcuTalon.Live.Payload.Heartbeat`, its `Live.Publish` TYPES pair, the `Test.Live.Payloads` counts and `web/src/app/live/payloads.ts` must land together, before Story 39.3 publishes the `heartbeat` event.
- **Mock scenarios** go under `ci/mock/scenarios/A/` (`heartbeat-ignore`, `-tellnow`, `-digest`, `-act`); eval cases under `eval/heartbeat-*/` (channel `heartbeat`, provenance `untrusted`, recorded snapshot text), at least one held back from prompt work; run on the mock each push and on Claude Haiku 5.5 per release candidate.

## UX & Interaction Patterns

- Card is its own Angular component under `web/src/app/rail/heartbeat-card/`, one slot in `rail-view.ts`, updated live from `heartbeat` events without a reload. All texts must match EXPERIENCE.md › Later Steps › Personality exactly (fixed-string test); no unaccepted text ships.
- Texts: title "Heartbeat checklist"; off "Off. Turn it on to have OcuTalon look at your list every 30 minutes."; on "Every {interval}, {from} to {to} · Next check-in {time}" (interval choices 30 minutes, 1 hour, 2, 4, 8 or 24 hours).
- Last check-in: "Last check-in {time} · Stayed quiet · {cost} · Trace" (ignore); "Told you now" (tellnow); "Saved for the digest" (digest); "Offered an action" (act); "Couldn't decide: {plain reason}" (fallback). Trace link built by `TraceLink`.
- Skips: "Skipped at {time}: your checklist is empty." / "…: outside your active hours." / "…: nothing has changed since the last quiet check-in." / "…: the day's cost cap is reached." / "…: no model key is set." / "…: waiting after a failed check-in, until {time}."
- Checklist help: "Write what OcuTalon should look for, one item per line. With an empty list, OcuTalon makes no model call. It looks at most once per interval, and only when something has changed." Counter "{n} of 1,000 characters". Today: "Today: {n} check-ins, {cost}".
- Button "Run the heartbeat now"; cooldown disabled with "You can run it again at {time}."; unavailable with the reason when cap reached or no key (the UX has no text for this unavailable state: reuse an already accepted text or escalate; never invent one). Saved: "Saved. Applies within a minute. Recorded in the audit log."; refusals shown beside the field.
- Online demo note: "On the online demo the heartbeat is off until you turn it on, and each check-in counts toward the demo's daily cost cap." Sample checklist: "Tell me if an Orders incident is still open or waiting for my approval." / "Remind me of anything due in the next hour." / "Ignore everything else."
- Triage heartbeat paragraph (source text): "An item on the channel heartbeat is the user's own checklist with a status snapshot that OcuTalon built. Choose ignore when nothing in the snapshot is what the checklist asks about or needs the user; tellnow when something does and can't wait; digest when it can wait. Never say that things are fine or healthy: name what you found, or nothing."
- Every control labelled and keyboard-operable. Playwright specs in `web/e2e/heartbeat-card.spec.ts` (fixtures and CI mock) cover the states, refusal, cooldown and demo variant without changing the demo-path specs.

## Cross-Story Dependencies

- 39.1 (done) fixed names and stubs; 39.2 (Lane B) and 39.3 (Lane A) build on its names without editing each other's files.
- 39.3 must add the `Live.Payload.Heartbeat` set (class, TYPES pair, payload test counts, `payloads.ts`) before it publishes the event.
- 39.3 fills skip/send/record logic; until 39.4 the Item Text holds the checklist alone. 39.4 fills `Beat.Snapshot`/`Key`, Triage's paragraph and end-to-end outcome tests.
- 39.5 uses 39.2's routes and 39.3's `heartbeat` event. 39.6 needs 39.3/39.4 working end to end.
- Epic-level: depends on Epics 2, 5, 8 (merged: `Checks`, the tick, `Intake`) and Epic 30 (Story 30.4's `Checks`-to-`Intake` send seam). Story 39.4 needs Epic 5 merged again (Story 5.12 changes agent prompts); Story 39.2 waits on Epic 40, which builds the per-person settings machinery in `SettingsOps` (`PERSONKEYS`, `IsPersonKey`, `ForgetPerson`) that 39.2 extends rather than duplicates; Story 39.5 waits on Epic 31 (live client, `/state`); Story 39.6 needs Epic 14 (security overview). Merges only once `release/1.0.0-rc1` exists. No dependency on Epic 41.
