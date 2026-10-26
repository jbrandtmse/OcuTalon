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
- Story 4.6: Simulate incoming email in the simulated mailbox
- Story 4.7: Finish the demo guide

## Requirements & Constraints

- **Demo mode** defaults on for `docker compose up` and off for IPM, and a switch survives restarts and upgrades.
  - **Who may switch:** the terminal command accepts a caller holding `OcuTalonAdmin` or `%All` (a `%All` caller could grant itself the role anyway). Every other caller is refused with a plain-English message, and nothing is submitted. The web endpoints stay `OcuTalonAdmin` only.
  - **Auditing:** every switch is audited and its entry names the person (`ActingUser`). A change whose audit entry can't be written is still refused.
  - **Timing:** a switch applies within 60 s. The page picks it up at its next `/state` load; there is no settings live event.
- **Demo mode off:** no context badge and no demo feature. The demo endpoints answer 404, and nothing routes to the phone. The conversation, rail and history are unchanged. OCUORDERS and the Orders production are removed, except that a foreign OCUORDERS is kept and marked `demoKept`.
- **Nothing canned:** sample emails are inputs decided live, and incident text comes from the real failures. Mocks exist only in CI's configuration, never in the judges' compose file.
- **Simulated devices:**
  - Each carries a visible "Simulated" label and is a real channel: Visual Trace looks the same, and only the channel name differs.
  - The phone shows only the session's notifications, in the paired chat's catalog text: plain text, no Markdown or emoji, instance-zone times with " ET" online. It has no composer.
  - Mailbox emails are untrusted items decided live. Ignore and Digest notify nobody; only Tell now or Act notifies. An email never makes OcuTalon act: on act it gets a read-only untrusted turn in a fresh AI session, and anything more is described to the user as an offer.
  - An empty Subject or Body answers 400 with a plain-English field error and records nothing.
- **Break the feed:**
  - It is active only while the session watches Orders and has no open Orders incident (any variant, until dismissed), none awaiting approval or fixing, and no run under 3 minutes old still waiting for its notice.
  - A press is a production message, never a turn: no `Turn`, no decision, no allowance use. It is audited as an `Action`.
  - Every run opens a new incident with its own approval request.
- **The guide:**
  - A step is done only from real state: 1 an Orders watch; 2 a reminder, pending or fired; 3 the incident, fallback or no-fix notice in the current run; 4 its approval answered; 5 the trace-opened marker.
  - The finish shows only after an approved fix and a resolved incident. After a fallback, no-fix or rejection, the guide keeps the matching step 4 hint and shows no finish text.
  - Run again resets only the guide's markers, never the session's data.
- **Timing:** against the mock, a tell-now notification reaches the phone within 5 s of its decision (built in 4.5), and live updates arrive within 2 s. NFR-7's 60 s from press to notice and the demo-path time budget are measured in the rehearsal, not asserted in CI.

## Technical Decisions

- **Demo mode (4.1, built; U-72 delivered in 4.6 as DW-275).**
  - The value is `demo.mode` ("1"/"0") in `Data.Setting`, read through `Setting.Get` (a 60 s per-process cache).
  - `Core.Admin.SetDemoMode(mode)` checks the value, then the caller's roles through `Admin.Allowed(roles)`. It submits `SetDemoMode` (with `ActingUser`) as origin `system`. `SettingsOps`, the only run-time settings writer, audits, saves, and reruns `Install.Step.Demo.Run()` on every accepted command.
  - **DW-275 changes:** widen `Allowed` to accept `%All`, update `TestAllowed` (three cases: `%All` accepted, `OcuTalonAdmin` accepted, neither refused) and update `live:demo-switch`'s steps 3, 4 and 7.
- **Spine edges and Orders.**
  - Edges: `Core --> Install.Step.Demo.Run()` (only `SettingsOps`, on a switch); `Guide --> Telegram.In.Included()`; and `Demo --> Install.Step.Demo` for its constants (`MODEKEY`, `NAMESPACE`, `PRODUCTION`).
  - Demo, Live and Data have no edge to Core, so `Guide.DemoOn` repeats `Core.Rule.Functions.DemoOn`.
  - `Install.Step.Demo` owns OCUORDERS and the non-autostart Orders production. Only `PartnerTrigger.Send` and the Demo step switch namespace.
  - Orders bodies carry no `SessionRef`; the session's `TraceRef` is their `SuperSession`.
- **How state changes.**
  - State changes only through business services; adapterless ones go through `Ens.Director.CreateBusinessService` and `ProcessInput`, which works from the REST process.
  - A sync send with no answer is an error: `SendRequestSync` returns OK with no response on a timeout, so every synchronous target must answer.
  - REST writes only `GuideState`'s UI markers.
  - `IncidentManager` (Lane A) is the only incident writer. Before an incident's notice sets `NoticedAt`, ownership reads hide it, and only `watch.progress` goes out.
- **The guide (4.2, built).**
  - **Source:** `Demo.Guide.Compute(SessionRef)` is the single source. `/state`'s `guide` (the last key, demo mode only) and `guide.state` carry it; the page never decides any of it.
  - **Payload:** `runEpoch`, `step`, `finished`, `steps`, `breakFeed` (`active`, `reason`, `stage`, `startedAt`), `step4Variant` and `telegramRow`.
    - `step4Variant`: `paired` | `unpaired` | `rejected` | `fallback` | `no_fix`.
    - With variant `rejected`, `fallback` or `no_fix`, a current step 5 becomes step 4.
    - An `expired` incident gives `paired` or `unpaired`; there is no UX text for it, so 4.7 may revisit this.
  - **Current run:** it starts at the epoch's latest run, or at the epoch's start. Steps 3 and 4, the variant and the finish read the newest Orders incident noticed in it.
  - **Publishing:** `Live.Publish.RefreshGuide` is the one `guide.state` publisher and publishes only on a change. It runs after the seven trigger types and on `StatusMonitor.GuideTick()` and marker writes. `phone` and `mailbox` are not triggers.
  - **Markers:** `POST /api/v1/guide/markers` takes `{"marker":"trace_opened"|"run_again"}` and answers 200 with the guide view. It answers 404 with demo mode off and 400 `MESSAGEBADMARKER` for a bad marker. `GuideState` holds `TraceOpened`, `RunEpoch` and `RunStartedAt`.
  - **Telegram:** "Telegram is on" means `Telegram.In.Included()` is 1 and `TelegramState()` is `on`, which stays `off` until Story 10.3. The paired variant needs it.
- **Break the feed (4.3 and 4.4, built).**
  - `POST /api/v1/demo/break-feed` answers 404 (demo mode off), 409 with reason `not_watching` or `incident_in_progress` and its exact hint, or 200 `{"state":"sent","startedAt"}`.
  - The box's stages are `sending`, `waiting`, `still_waiting` (from 90 s), `no_notice` (from 180 s; this frees the control) and `notice_arrived`.
  - The page calls the route through the guide-owned `break-feed-api.ts` (U-84; unified into `ApiClient` later, DW-231 on 10.3). It reads `guide` through the guide-owned type `GuideSnapshot`.
- **Channels.**
  - **Routing:** `Notify` routes a notification to the web chat, to `SimPhoneOut` (demo mode only) and to the paired chat. Kind `allowance` never reaches the phone. Don't change `Notify`.
  - **Rendering:** only `*Out` operations render, through `Msg.Catalog.Render(key, slots, channel)`. The `phone` and `mailbox` channels render the `telegram` text.
  - **Delivery rows:** each `*Out` records its `Delivery` through `Data.Delivery.Record(ownerRef, channel, channelMessageId, approvalRef)`. Never edit `Data/Delivery.cls` (contended, Epic 10).
- **Simulated phone (4.5, built).**
  - **Base class:** `SimPhoneOut` and `WebChatOut` extend the abstract `Channel.Operation`. `IsSession(ownerRef)` acts only when `Session.Recipients` returns exactly that Ref: any other owner logs one warning, writes nothing and returns OK, and the check runs before rendering. `Announce(ownerRef, type, payloadClass, row)` publishes after the commit and warns on failure. `SimMailboxOut` can extend `Channel.Operation` too.
  - **Card kinds:** kinds `tellnow` and `reminder` write a `SimMessage` (Kind `phone`, Direction `out`, the new `Text` column) and its phone `Delivery` row in one transaction (`ChannelMessageId` = the SimMessage `Ref`). The `phone` event `{ref, direction, text, createdAt}` is published after the commit.
  - **Other kinds** record only the `Delivery` row, until Stories 6.3 and 6.4 add Approve and Reject.
  - **Snapshot:** `/state.phone` is present in demo mode only. It holds the newest 100 messages, oldest first, read through `Ownership.RecentPhone`, and sits after `status` and before `guide`.
  - **For the mailbox:** `SimMessage.Text` can hold an email's body.
- **Simulated mailbox (4.6).**
  - **Endpoints:** `POST /api/v1/mailbox/incoming` (From, Subject, Body) and `POST /api/v1/mailbox/samples/:name` (`newsletter`, `partner-notice`, `suspicious-request`) go to `SimMailboxIn`. Both answer 404 with demo mode off.
  - **Arrivals:** `SimMailboxIn` records the arriving `SimMessage` with the item's `ItemId` and publishes `mailbox`. It then sends an `OcuTalon.Msg.Item` (channel `mailbox`, provenance `untrusted`) to `Intake`. The row finds its decision by that `ItemId`, which the decision event carries.
  - **Sent mail:** `SimMailboxOut` records a sent `SimMessage` and its `Delivery` row and publishes `mailbox`. Nothing routes to it in release 1, so its test uses a fixture `Msg.Outbound`.
  - **Publishers:** `mailbox` has two publishers, `SimMailboxIn` for arrivals and `SimMailboxOut` for sent mail.
  - **Ownership:** 4.6 may replace the stub `Channel/SimMailbox/In.cls` in full, by orchestrator ruling. Its entries in `Data/Ownership`, `Test/Data/Ownership` and `Test/Web/Api` are additive only.
- **Audit.**
  - Product code audits only through `Bridge.Audit.Record(type, data)`, with the type's fixed shape and every member set. `Record` redacts itself, so don't redact twice.
  - `Test.Bridge.CodeRules` fails any other audit `Write`.
  - Types used here: `Settings` (demo mode) and `Action` (Break the feed). Tests read entries back with `Test.Bridge.AuditLog`, polling with a timeout.
- **Data and conventions.**
  - **Lane B tables:** `GuideState`, `BreakFeedRun`, `SimMessage`, `Delivery`, `Setting`, `StatusMark` and `Live.Event`.
  - **Other epics' rows** are read only through `Data.Ownership` with the caller's `SessionRef`. No endpoint accepts a `SessionRef` from the client.
  - **Storage:** append-only, with storage blocks committed. A new property is appended, and existing rows read it as "".
  - **Refs and times:** Refs come from `Bridge.Ids.NewRef()`. Times are UTC ISO 8601, rendered only through `Data.Time`.
  - **Live payloads** are full views keyed by `Ref`, published after commit. TS types come from `web/scripts/payloads.mjs` and page texts from `web/scripts/catalog.mjs`.
  - **Don't edit** `web/src/app/api/**` (contended). Read new snapshot keys through a feature-owned type, as `GuideSnapshot` and the phone's `StateSnapshot & { phone?: PhonePayload[] }` do.
- **REST.**
  - Routes sit under `/ocutalon/api/v1`. Errors are `{"error":{"code","message"}}` in plain English.
  - A route answers 501 `not_built` until its story ships, and 404 while demo mode is off.
  - State-changing calls need `application/json`, `X-OcuTalon-Request: 1` and a matching `Origin`.
- **Testing.**
  - **Unit tests:** `%UnitTest` classes live in `OcuTalon.Test.<Area>` (doubles in `OcuTalon.Test.Demo`), in the lane-b shard via `ci/iris.sh`. Probe subclasses override private seams. `Test.Demo.Step` saves and restores `demo.mode`. `Test.Data.Fixture` makes rows and cleans them, including SimMessage and phone `Delivery` rows. `Test.Demo.SimPhoneOut`'s shadow-instance pattern and `Observe` helpers are the model for the mailbox tests.
  - **Demo mode in tests:** every docker stack runs in demo mode, so every notification test session also gets phone rows and a `phone` event. The real `StatusMonitor` ticks every 15 s. A test that needs demo mode off switches it off before creating rows.
  - **Warm stacks:** a running job keeps the old compiled class, so toggle the item or use a fresh stack. Real batches and item swaps run only on lane-b fresh throwaways.
  - **Pinned surfaces:**
    - A route or `/state` key change updates `Test.Web.Api` (`TestStateBody`, `TestRoutes`), `web/e2e/api/api.spec.ts` (`UNBUILT`, exact keys) and `web/e2e/frame/frame.spec.ts` F9.
    - A payload change updates `Test.Live.Payloads` and `payloads.mjs --check`.
    - A table change updates `Test.Data.Tables` and `test-storage.sh`.
    - A stub item made real updates its row in `Test/Core/ProductionItems.cls`.
    - A new e2e folder updates `web/scripts/playwright-projects.test.mjs`.
  - **The switch check:** `live:demo-switch` (`docker/tests/test-demo-switch.sh`) is the destructive check of the real switch. Specs in `web/e2e/demo-switch/` join it without a script edit; each runs 61 s after its switch, because of the cache. Don't edit `docker/tests/test-demo-path.sh` (contended).
  - **Floor specs:** these live in `web/e2e/floor/` and run only in `live:floor`. Device cases are in `devices.spec.ts` (D1-D5b).
  - **Mock:** mailbox tests pick outcomes with `[[mock:<name>]]` markers from `ci/mock/scenarios/B/`. Until Story 1.3 merges, they use Story 2.4's `Decide` double. A keyless throwaway falls back to `tellnow`/`no_key`, so a test that needs real outcomes uses `RunnerFixture.PointKeys` and `RestoreKeys`. Never switch keys on the shared `live:sign-in` stack, which runs near the 10-minute cap.

## UX & Interaction Patterns

- **Layout.**
  - The "Demo guide" region sits between the banners and the rail and chat, with the Break the feed box at its right, over the device column.
  - The "Simulated devices" region sits right of the chat: 352 px wide, 384 px from 1440 px. Under 1024 px it stacks main, devices, rail. At short heights, the phone screen shrinks to the panel's height.
- **The guide.**
  - Steps are buttons and can be selected in any order. The current step has `aria-current="step"`.
  - When a step completes, the guide advances by itself, moves focus to the prompt bar's action, and announces "Step {n} of 5: {step}".
  - Guide prompts are sent verbatim as the user's own chat message with `fromGuide`. Each one is a real turn and counts toward the allowance.
- **The devices.**
  - They are ARIA tabs with automatic activation; the arrows wrap and move from the focused tab. The choice is remembered under `ocutalon.devices.tab`.
  - Tabs never switch by themselves. New content in an unselected tab adds a badge count that is also in the tab's name ("Simulated mailbox, 2 new"); content present at load is never new. A switch the user causes is allowed: Story 4.7's Show me calls `DeviceTabs.select('phone')` and focuses the pending notification (`[data-key]`), never Approve.
  - Badges for the mailbox come from `store.mailboxes`.
  - The amber `app-simulated-label` is static and can't be focused.
  - The phone and the devices region are not live regions and announce nothing.
- **The mailbox (4.6) fills 4.5's header-only tabpanel.** The header is "Simulated mailbox" plus the label, as plain text with no heading; the panel is `tabindex="0"` until it holds focusable content.
  - The sample chips are always visible. Pressing one keeps focus on it and announces the new row.
  - "Simulate an incoming email" replaces the list with the form, focusing From.
  - A row shows an unread dot with a hidden "Unread", then "Deciding…", then the outcome chip, and the decision is announced. Opening a row shows it in place with focus on the subject heading; Back returns focus to the row.
  - Untrusted text renders only as text.
  - Sample texts come exactly from the UX's sample-email table.
- **Shared rules.**
  - The page speaks only through `Announcer`.
  - Focus moves only on the user's action, or through `shared/focus-rule.ts` when an update removed the focused element.
  - Links that leave the page say "(opens in a new tab)".
  - Prompts, hints, box states, empty states, sample emails and the finish text are exact: take them verbatim from the stories and the UX. Use straight ASCII quotes, and style only with DESIGN.md tokens.
  - Floor rules: no `transition`, fixed heights, `sticky` or `IntersectionObserver`, and width queries only through `LAYOUT_QUERIES`.

## Cross-Story Dependencies

- **Story 4.6:**
  - **Provided by 4.5:** the mailbox tabpanel, its badge, `app-simulated-label`, `Channel.Operation` and `SimMessage.Text`.
  - **New route:** it adds its endpoints' demo-off 404 and turns its routes off `UNBUILT`.
  - **Owned item:** DW-275 (U-72's `%All` acceptance in `SetDemoMode`, with its tests).
  - **Shared files:** Epic 16 shares `Test/Data/{Ownership,Tables,Fixture}.cls`, `Test/Web/Api.cls`, `Data/Ownership.cls` and `web/src/app/header/skip-links.ts`. Add entries only; the union happens at the integrate-forward.
- **Story 4.7:**
  - **Uses:** `step4Variant`, `finished`, `runEpoch`, the marker endpoint, 4.5's `DeviceTabs.select`, and `Ownership.RunCost` with `GuideState.RunStartedAt` as its `since`.
  - **DW-146:** check whether trace tabs hold licence connections; if they do, the specs sign their trace tabs out.
  - **DW-215:** keep a resolved incident with a `rejected`, `fallback` or `no_fix` variant out of `finished`, or prove by test that this can't happen.
  - **DW-274:** style `.cdk-visually-hidden`, or load the CDK's a11y styles, so the live announcer's element never lies below the page. Pin it with a short-window floor check that measures after an announcement lands; today D2 only checks that nothing of `app-root` reaches below the window.
- **Not merged here:**
  - Epic 5's Orders watch and `IncidentManager` (`closeForReplay` is 5.5's). Fixture rows and `Test.Demo.IncidentManagerDouble` stand in, and Epic 11 turns the path on end to end.
  - Epic 8's reminders: they are stubs, so tests use fixture `Reminder` rows.
- **Stream tests:** with demo mode on, a session stream gets `guide.state` after any trigger publish that changes its view, and a `phone` event for each card notification. A test that asserts a stream's exact events must expect these or switch demo mode off.
- **Waiting on this epic:**
  - Epic 5: turns the `TraceRef`-tagged failures into the session's incident.
  - Story 6.3: Approve and Reject on the phone. It finds the message with `FindByApproval(approvalRef, "phone", owner)` and edits its `Text` in place, republishing `phone` with the same ref.
  - Story 6.4: the result, fallback and no-fix kinds on the phone.
  - Stories 8.3-8.5: real reminders on the phone.
  - Stories 10.2, 11.2 and 15.2: they switch demo mode from `%All` terminals, which U-72 now accepts.
  - Story 10.3: the real Telegram state and the paired variant.
  - Stories 11.1 and 11.3: the demo path and the 5 s measure.
  - Story 12.6: Telegram's text must equal the phone's.
  - Story 16.9: the allowance count excludes presses.
  - Story 18.1: `SetDemoMode` from `web_admin`.
  - Story 31.3: the bridge link in the finish.
