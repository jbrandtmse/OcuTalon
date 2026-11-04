# Epic 39 Context: A heartbeat checks your list and stays quiet unless something needs you

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A person keeps a short checklist that OcuTalon looks at on a schedule (the agent heartbeat, or beat), with an interval and active hours of their own. The existing one-minute tick only finds due beats and never calls the model; each due beat that isn't skipped becomes one attention decision over the checklist and a code-built status snapshot, so a person's beats call the model at most once per interval and only when something may need a decision. Ignore stays silent, a beat never gives an all-clear, and every beat and its cost shows in Visual Trace and on a new Heartbeat checklist card. The owner's hard constraint: the model is never called every minute.

## Stories

- Story 39.1: Fix the heartbeat's names and contracts
- Story 39.2: Save your heartbeat settings and ask for a beat
- Story 39.3: Beats fall due on the tick, and skip without a model call when they should
- Story 39.4: Each beat carries your checklist and a status snapshot built by code
- Story 39.5: The Heartbeat checklist card, and Run the heartbeat now
- Story 39.6: Evaluation cases for the heartbeat
- Story 39.7: Publish the heartbeat event

## Requirements & Constraints

- **Values, per person:** on/off; checklist up to 1,000 characters; interval of 30, 60, 120, 240, 480 or 1440 minutes (nothing shorter on any install); active hours as quarter-hour `HH:MM` in the instance zone, or both empty for all day. Defaults: on, 30, 08:00 to 20:00, empty checklist, so a new person costs nothing until they write one. Online demo: off, with a sample checklist that isn't stored until saved; values go at sign-out and the reset.
- **Saving:** refuse `{{`, `@{` and control characters other than a line break, with a plain message and nothing written. Audit first (never the checklist's text), then write; a change applies within 60 seconds.
- **Skips, in this order, with no model request:** empty checklist; outside active hours; back-off running; day capped; no key; snapshot unchanged since the last Ignore. A skip records its reason and moves the next due time on (the next active-hours start when outside hours, otherwise one interval).
- **Run now:** an explicit request, at most every 2 minutes per session. Active hours and an unchanged snapshot don't hold it back; the other skip rules do. The route answers 409 with `availableAt` or the reason.
- **Failure and restart:** a fallback notifies as for any item and backs off 4 hours, or one interval if longer. A beat missed across a restart runs once. Nothing that decides "due" lives in memory.
- **Snapshot:** the checklist, a "Status at" line, then entry lines for open incidents, watches, pending approval requests, reminders due before the next beat, and at most 10 decisions since the last beat that made a decision. A watch's line holds its production and last check result, and no time: the run time moves every minute, so it would change the key at every beat and the unchanged skip could never fire.
- **Snapshot limits:** it counts as untrusted arriving content and stops at 4,000 characters. It holds no model-written text, diagnosis cause, decision reasons, event-log or message text, keys or identities. A decision's code-written `Summary` stays as stored, and that can quote outside content.
- **No all-clear:** a beat has no check row, check result or coverage entry, and no code renders a beat or an Ignore as "everything is fine". Reasons pass the all-clear guard.
- **Cost:** each decision under $0.001 on Claude Haiku 5.5; a default day under $0.03. Act leads only to one read-only turn, with no approval request.
- **Tests pin the model calls** through the CI mock's request log, with fixed clocks: none on a non-due tick or an unchanged-since-Ignore beat, exactly one on a changed beat, at most two in an hour on a 30-minute interval.
- **Security overview** must say a beat sends the checklist and snapshot to the model provider, at most once per interval.

## Technical Decisions

- **Home lanes:** A for 39.1, 39.3, 39.4 and 39.6; B for 39.2, 39.5 and 39.7. Each story keeps its home lane's files. `Checks`, `Checks.Beat`, `HeartbeatBeat`, `BeatNow` and Triage are Lane A; `Msg.Enum`, the command classes, `CommandsIn`, `SettingsOps`, `SessionOps`, `Web.Api`, `web/` and `Live/Publish.cls` are Lane B.
- **Story 39.7 moved to Lane B** by orchestrator ruling, so it may create `Live/Payload/Heartbeat.cls` and edit `Live/Publish.cls` TYPES, `Test.Live.Payloads` and `web/src/app/live/payloads.ts`. All four land together, before the event is published. The ownership tables still list the payload and event as Lane A; the ruling governs. The publish call itself is `Checks`', a Lane A file the ruling doesn't name, so 39.7's spec must settle where it goes.
- **Shared files:** `Agent.Input`, Triage's instructions, `Msg.Enum`, `SettingsOps`, `CommandsIn`, `SessionOps.End`, `Web.Api` and the rail are shared with Epics 40 and 41. Each epic appends its own entry.
- **No new scheduler, task or timer.** Beats run from `Checks` on the tick, after the due checks, in their own Try/Catch. Values are read through `Data.Setting.Get`.
- **Settings:** keys `person.<SessionRef>.heartbeat.*`. `SettingsOps` is the only run-time writer, the `SessionRef` comes only from the server-side session, and an admin gets no right to another person's values.
- **Commands:** `SetHeartbeat` goes to `SettingsOps` and `RunHeartbeat` to `Checks` as a `BeatNow`, both from origin `web_user` only, and the governance test refuses each from origin `tool`.
- **A beat that runs** sends `Intake` one `Msg.Item` asynchronously (provenance `untrusted`, channel `heartbeat`) through Epic 30's send seam, in a new trace session under the session's `TraceRef`. A later tick reads its `Decision` by `ItemId` and records the result; on Ignore the sent key becomes `LastQuietKey`.
- **Snapshot key:** `Beat.Key` is a SHA-256 of the checklist and the entry lines, leaving out the "Status at" line. The same records at different times match; a change to an entry line or the checklist changes it.
- **Skip inputs:** hours through `Data.Time`, the cap through `Bridge.Budget.State()`, the key through `Bridge.Keys.Status`.
- **Heartbeat event:** the row's public view on the session's stream, after each committed beat, skip or result. Never the `SessionRef`, checklist text or a snapshot key.
- **Triage** gets a static heartbeat paragraph (no `{{`), and a test compares it with its UX source.
- **Test data:** mock scenarios under `ci/mock/scenarios/A/`; evaluation cases under `eval/heartbeat-*/`, at least one held back from prompt work, run on the mock each push and on the real model per release candidate.

## UX & Interaction Patterns

- Every card text, the sample checklist and Triage's paragraph are fixed in EXPERIENCE.md's Personality section under Later Steps. Use them exactly; no text ships that the author hasn't accepted.
- The card is its own component under `web/src/app/rail/heartbeat-card/`, with one slot in `rail-view.ts`. It follows the status rail section pattern and updates from `heartbeat` events without a reload.
- It shows state, the last check-in (time, outcome, cost, `TraceLink` link) or the last skip's reason, and today's cost. Edit opens in place; refusals show beside the field. Controls are labelled and work by keyboard.
- The run button is disabled during a cooldown, and unavailable with its reason at the cap or with no key, the reason as a visible caption. The UX has no text for that unavailable state: reuse an accepted text or escalate.
- Playwright specs live in `web/e2e/heartbeat-card.spec.ts` and leave the demo-path specs unchanged.

## Cross-Story Dependencies

- 39.1 and 39.3 are done: the names, stubs and beat logic are in place. Until 39.4 the Item's text is the checklist alone; 39.4 fills the snapshot, the key's input and Triage's paragraph.
- 39.2 is held for Epic 40 by runner ruling: it extends Epic 40's per-person machinery in `SettingsOps` rather than duplicating it. Beats may therefore send channel `heartbeat` before the `Msg.Enum` append.
- 39.7 follows 39.3 and no longer waits on Epic 31. 39.5 needs 39.2's routes and 39.7's event, and also Epic 31 (live client, `/state`). 39.6 needs 39.3 and 39.4 end to end, and Epic 14 (security overview).
- The epic needs Epics 2, 5 and 8 (`Checks`, the tick, `Intake`) and Epic 30 (Story 30.4's send seam). 39.4 needs Epic 5 merged again (Story 5.12 changes the prompts).
- It merges only once `release/1.0.0-rc1` exists, and ships in the first daily release after that, when the Contest Planner's hands-on pass runs each outcome.
