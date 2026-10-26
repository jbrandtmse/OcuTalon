# Epic 4 Context: The demo page: guide, simulated phone and mailbox, and Break the feed

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Demo mode turns the signed-in page into the self-guided two-minute demo. It adds a demo guide with one-click prompts and a labelled simulated phone and simulated mailbox that are real production channels. It also adds a Break the feed control that makes the simulated partner send the session's 50 orders in a changed date format, and those orders fail for real in the Orders production. The server works out guide progress and Break the feed availability from what really happened in the session, so the demo claims nothing it didn't do, contains nothing canned, and can be run again. An admin switches demo mode from the terminal; with it off, none of this exists and nothing else changes. Lane B; depends on Epic 2.

## Stories

- Story 4.1: Switch demo mode from the terminal (done)
- Story 4.2: Derive the guide state and Break the feed availability on the server (done)
- Story 4.3: Break the feed with a real batch of 50 orders (done)
- Story 4.4: Show the demo guide and the Break the feed box (done)
- Story 4.5: Get notifications on the simulated phone (done)
- Story 4.6: Simulate incoming email in the simulated mailbox (done)
- Story 4.7: Finish the demo guide

## Requirements & Constraints

- **Demo mode** defaults on for `docker compose up` and off for IPM, and a switch survives restarts and upgrades.
  - **Who may switch:** the terminal command accepts a caller holding `OcuTalonAdmin` or `%All`; every other caller is refused in plain English and nothing is submitted. The web endpoints stay `OcuTalonAdmin` only. Every switch is audited naming the person (`ActingUser`); a change whose audit entry can't be written is refused.
  - **Timing:** a switch applies within 60 s (the `Setting.Get` cache). The page picks it up at its next `/state` load; there is no settings live event.
- **Demo mode off:** no context badge and no demo feature. The demo endpoints answer 404 and nothing routes to the phone. The conversation, rail and history are unchanged.
- **Nothing canned:** sample emails are inputs decided live, and incident text comes from the real failures. Mocks exist only in CI's configuration.
- **Simulated devices** are real channels with a visible "Simulated" label: Visual Trace looks the same, and only the channel name differs. The phone shows only the session's notifications in the paired chat's catalog text and has no composer. An email never makes OcuTalon act; Ignore and Digest notify nobody.
- **Break the feed** is active only while the session watches Orders and has no open Orders incident (any variant, until dismissed), none awaiting approval or fixing, and no run under 3 minutes old still waiting for its notice. A press is a production message, never a turn (no `Turn`, decision or allowance use), audited as an `Action`. Every run opens a new incident with its own approval request.
- **The guide:**
  - A step is done only from real state: 1 an Orders watch; 2 a reminder, pending or fired; 3 the incident, fallback or no-fix notice in the current run; 4 its approval answered; 5 the trace-opened marker.
  - The finish shows only after the run ended with an approved fix and a resolved incident. After a fallback, no-fix or rejection, the guide keeps the matching step 4 hint and shows no finish text.
  - Run again resets only the guide's markers, never the session's data: the existing watch and reminder still count, and steps 3 to 5 wait for the new run.
- **Timing:** NFR-7's 60 s from press to notice and the demo-path time budget are measured in the rehearsal, not asserted in CI.

## Technical Decisions

- **The guide view (4.2, built).** `Demo.Guide.Compute(SessionRef)` is the single source; the page never decides progress.
  - `/state`'s `guide` (the last key, demo mode only) and the `guide.state` event carry `runEpoch`, `step`, `finished`, `steps`, `breakFeed` (`active`, `reason`, `stage`, `startedAt`), `step4Variant` (`paired` | `unpaired` | `rejected` | `fallback` | `no_fix`) and `telegramRow`.
  - `step` is the lowest step not done (5 when all are). With variant `rejected`, `fallback` or `no_fix`, a step of 5 becomes 4, so step 4 stays current.
  - An `expired` request gives `paired` or `unpaired`; there is no UX text for it, and 4.7 may revisit this.
  - The current run starts at the epoch's latest Break the feed run, or at the epoch's start. Steps 3 and 4, the variant and the finish read the newest Orders incident noticed in it. Before `NoticedAt` is set, ownership reads hide an incident.
  - `Live.Publish.RefreshGuide` is the one `guide.state` publisher, publishing only on change, after the seven trigger types, `StatusMonitor.GuideTick()` and marker writes.
  - **Markers:** `POST /api/v1/guide/markers` takes `{"marker":"trace_opened"|"run_again"}` and answers 200 with the guide view; 404 with demo mode off; 400 `MESSAGEBADMARKER` for a bad marker. `GuideState` holds `TraceOpened`, `RunEpoch` and `RunStartedAt`.
  - "Telegram is on" needs `Telegram.In.Included()` = 1 and `TelegramState()` `on`, which stays `off` until Story 10.3, so `paired` can't occur yet.
- **Run cost.** `Data.Ownership.RunCost(sessionRef, since, .sc)` (built) gives the run total; pass `GuideState.RunStartedAt` as `since`. The figures cover the session's decisions and turns. Turns store `DecisionRef`s, never totals.
- **The page's guide parts (4.4, built).** `app-demo-guide` renders steps 1-2, the Telegram row, the frame and the box; for steps 3-5 the prompt bar holds no prompt yet. Step advances move focus to the prompt bar's action (or the `tabindex="-1"` prompt text) and announce "Step {n} of 5: {step}". The box's stages: `sending`, `waiting`, `still_waiting` (from 90 s), `no_notice` (from 180 s; frees the control) and `notice_arrived`. The page reads `guide` through the guide-owned type `GuideSnapshot`. Break-feed calls go through the guide-owned `break-feed-api.ts`; the marker calls belong beside it (DW-231: both move into `ApiClient` in Story 10.3).
- **Devices (4.5 and 4.6, built).**
  - `DeviceTabs` (`web/src/app/devices/device-tabs.ts`, root-provided) holds the `selected` signal; `select('phone')` is Show me's entry point. Phone notifications carry `[data-key]`.
  - `/state` carries, in demo mode only, `phone` (newest 100, oldest first), then `mailbox` (newest 100 emails, oldest first, each the `mailbox` payload plus `decision` once decided), then `guide`.
  - `SimMailboxIn` and `SimMailboxOut` are real; `/mailbox/incoming` and `/mailbox/samples/:name` answer 404 with demo mode off, and a blank subject or body answers 400 `bad_email`.
- **Trace links.** `OcuTalon.Web.TraceLink` builds every trace URL; payloads carry `TraceHeaderId`/`TraceNamespace` and the web layer adds the URL. The incident payload's `TraceTargets` has `diagnosis`, `sample` and `firstFailure`; "Open the trace" uses the incident's trace (the diagnosis session). "See the whole conversation" is "Open my conversation": the newest turn's `traceUrl`, which opens the day's thread. On local installs a trace link shows the sign-in help popover first; the online demo opens signed in.
- **Licence connections (for DW-146).** The Community licence caps the instance at 8 connections. Each Visual Trace window holds one for about two minutes after its last use. Story 2.13's link specs stub their trace tabs to stay green.
- **State and writers.** State changes only through business services. REST writes only `GuideState`'s UI markers. `IncidentManager` (Lane A) is the only incident writer. `IncidentOpenVariant` is `fallback, no_fix, rejected, expired`, stored beside the incident's state.
- **Data and conventions.**
  - Other epics' rows are read only through `Data.Ownership` with the caller's `SessionRef`; no endpoint accepts a `SessionRef` from the client.
  - Storage is append-only (new properties appended; old rows read ""). Refs from `Bridge.Ids.NewRef()`; times UTC ISO 8601, rendered through `Data.Time`.
  - Live payloads are full views keyed by `Ref`, published after commit. TS types come from `web/scripts/payloads.mjs`, page texts from `web/scripts/catalog.mjs`.
  - Don't edit `web/src/app/api/**` (contended); read new snapshot keys through a feature-owned type. Don't edit `Data/Delivery.cls` or `Notify`.
- **REST.** Routes under `/ocutalon/api/v1`; errors `{"error":{"code","message"}}` in plain English. State-changing calls need `application/json`, `X-OcuTalon-Request: 1` and a matching `Origin`.
- **Testing.**
  - `%UnitTest` classes in `OcuTalon.Test.<Area>` (doubles in `OcuTalon.Test.Demo`), lane-b shard via `ci/iris.sh`. `Test.Demo.Step` saves and restores `demo.mode`; `Test.Data.Fixture` makes and cleans rows. Tests drive guide states with fixture `BackgroundCheck`, `Reminder`, `Incident`, `ApprovalRequest` and `BreakFeedRun` rows.
  - Every docker stack runs in demo mode, so notification test sessions also get phone rows, and session streams get `guide.state` after trigger publishes.
  - **Pinned surfaces:** a route or `/state` key change updates `Test.Web.Api`, `web/e2e/api/api.spec.ts` and `frame.spec.ts` F9; a payload change updates `Test.Live.Payloads` and `payloads.mjs --check`; a table change updates `Test.Data.Tables` and `test-storage.sh`; a new e2e folder updates `playwright-projects.test.mjs`.
  - **Demo-path specs** are `web/e2e/demo-path/0<n>-<id>.spec.ts`; an unbuilt part is `notBuilt(title, 'N.M')`, and a turned-on test that must never skip again carries `@floor`. Floor specs live in `web/e2e/floor/` and run only in `live:floor`. Don't edit `docker/tests/test-demo-path.sh` (contended).
  - **Mock:** prompts' scenarios live under `ci/mock/scenarios/B/` (the loader refuses a repeated prompt). A keyless throwaway falls back to `tellnow`/`no_key`; tests needing real outcomes use `RunnerFixture.PointKeys`/`RestoreKeys`. Never switch keys on the shared `live:sign-in` stack, which runs near the 10-minute cap.
  - Warm stacks keep old compiled classes; real batches and item swaps run only on lane-b fresh throwaways.

## UX & Interaction Patterns

- **Step 3:** "Press Break the feed. The partner will send 50 orders in a new date format."; while waiting, "Waiting for OcuTalon. The reminder may arrive first." **Go to Break the feed** focuses the box's button without pressing it.
- **Step 4 prompts by variant:**
  - paired: "Approve the fix in Telegram on your phone, or on the simulated phone."
  - unpaired: "Approve the fix on the simulated phone, or in the chat."
  - rejected: "Rejected. Nothing was changed. Dismiss the incident in the chat, then press Break the feed again."
  - fallback: "OcuTalon couldn't diagnose this run, so there's nothing to approve. Open the trace to see why, or dismiss the incident and press Break the feed again."
  - no fix: "OcuTalon found the cause but has no fix for it, so there's nothing to approve. Open the trace to see why, or dismiss the incident and press Break the feed again."
  - Step 5 stays available after a fallback or no-fix. **Show me** selects the Simulated phone tab and focuses the pending notification's container, never Approve. It is the one tab switch a user may cause.
- **Step 5:** "Open the incident's trace: watch your assistant in Visual Trace like any other feed, with every step it took and the tokens and cost of each decision." **Open the trace** opens the incident's trace link in a new tab and writes `trace_opened`, which completes step 5.
- **Finish state** (replaces the prompt bar; focus moves to its first line):
  - "Done. You saw an AI Hub agent read 50 failed orders and name the cause. Every decision, with its cost, and every step it took landed in Visual Trace, and the fix waited for your approval and was recorded in the audit log."
  - "This run: {n} decisions · {tokens} tokens · {cost} on {model}." in `body-sm`, `ink-muted`, tabular figures (e.g. "This run: 3 decisions · 9,850 tokens · $0.0041 on Claude Haiku 5.5").
  - Links "See the whole conversation in Visual Trace ↗" and "Install OcuTalon yourself ↗", each named as opening a new tab with the ↗ hidden. Leave out "Use the same bridge in your own production ↗" until Story 31.3 adds it.
  - "More to try: simulate an incoming email in the simulated mailbox and see what OcuTalon decides. On your own install, ask it to watch any production."
  - **Run again** (secondary button): the prompt bar replaces the finish state.
- **Break the feed styling:** the secondary style while step 5 is current; back to the attention style once the finish shows.
- **Shared rules.**
  - The page speaks only through `Announcer`. Focus moves only on the user's action, or through `shared/focus-rule.ts` when an update removed the focused element. The phone, mailbox and box are not live regions.
  - Links that leave the page say "(opens in a new tab)" and are always underlined.
  - Texts are exact: take them verbatim from the stories and the UX, with straight ASCII quotes. Style only with DESIGN.md tokens.
  - Floor rules: no `transition`, fixed heights, `sticky` or `IntersectionObserver`, and width queries only through `LAYOUT_QUERIES`.
  - DW-274 is fixed (4.5): `web/src/styles/base.css` styles `.cdk-visually-hidden` from page load, and floor D6 pins it after an announcement lands.

## Cross-Story Dependencies

- **Story 4.7 consumes:**
  - from 4.2: `step4Variant`, `finished`, `runEpoch`, the marker endpoint and `GuideState.RunStartedAt`;
  - from 4.4: the prompt bar's empty step 3-5 entries, the box's button (Go to Break the feed's focus target), `focus-rule` and the step announcements;
  - from 4.5: `DeviceTabs.select('phone')` and the phone's `[data-key]` notifications;
  - from 4.6: the mailbox that the finish's "More to try" line points to.
- **Story 4.7 turns on:** the demo-path `notBuilt(..., '4.7')` parts in `01-page`, `02-watch`, `03-reminder` and `06-trace`. They follow Flow 1's web route with the CI mock, and each is turned on once it passes on the integration branch; the rest stay skipped.
- **DW-146 (4.7):** measure licence and gateway connections on a throwaway with real trace tabs open. If the tabs hold connections, the specs sign their trace tabs out.
- **DW-215 (4.7):** `Guide.Compute` could report `finished` true with step 4 current and a `rejected`, `fallback` or `no_fix` variant, if a resolved incident keeps that `OpenVariant` (unverified until Story 5.5's `IncidentManager`). Make the finish condition exclude such an incident, or prove by test that a resolved incident never keeps one.
- **Not merged here:** Epic 5's Orders watch and `IncidentManager` (`closeForReplay` is 5.5's). Fixture rows and `Test.Demo.IncidentManagerDouble` stand in, and Epic 11 turns the path on end to end. Epic 8's reminders are stubs, so tests use fixture `Reminder` rows.
- **Waiting on this epic:** Epic 5 (the session's incident); Stories 6.3 and 6.4 (Approve, Reject and the result kinds on the phone); 8.3-8.5 (real reminders); 10.3 (the Telegram state, the paired variant, and DW-231's move into `ApiClient`); 11.1 and 11.3 (the demo path and the 5 s measure); 12.6 (Telegram's text equals the phone's); 16.9 (allowances exclude presses); 18.1 (`SetDemoMode` from `web_admin`); 31.3 (the bridge link in the finish).
