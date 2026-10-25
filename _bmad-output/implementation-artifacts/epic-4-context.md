# Epic 4 Context: The demo page: guide, simulated phone and mailbox, and Break the feed

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Demo mode turns the signed-in page into the self-guided two-minute demo. It adds a demo guide with one-click prompts, a labelled simulated phone and simulated mailbox that are real production channels, and a Break the feed control. Break the feed makes the simulated partner send the session's 50 orders in a changed date format, and they fail for real in the Orders production. The server derives guide progress and Break the feed availability from what really happened in the session, so the demo claims nothing it didn't do, contains nothing canned, and can be run again. An admin switches demo mode from the terminal. With demo mode off, none of this exists and nothing else changes. This is a Lane B epic that depends on Epic 2.

## Stories

- Story 4.1: Switch demo mode from the terminal
- Story 4.2: Derive the guide state and Break the feed availability on the server
- Story 4.3: Break the feed with a real batch of 50 orders
- Story 4.4: Show the demo guide and the Break the feed box
- Story 4.5: Get notifications on the simulated phone
- Story 4.6: Simulate incoming email in the simulated mailbox
- Story 4.7: Finish the demo guide

## Requirements & Constraints

- **Demo mode.**
  - **Default:** on for a `docker compose up` install and off for an IPM install. It is written as a seed value, so a later switch survives restarts and upgrades.
  - **Switching:** needs the OcuTalon admin role. Without it, the command refuses in plain English and submits nothing. Every switch is audited and takes effect within 60 seconds. The page follows through `/state`.
- **Demo mode off:**
  - The context badge and every demo feature are gone.
  - The demo endpoints answer 404.
  - Nothing routes to the simulated phone.
  - The conversation, rail and history are unchanged.
  - The Orders production stops, and OCUORDERS, its trace application and the trace role's OCUORDERS grants are removed.
  - A foreign OCUORDERS (not OcuTalon's, or holding another production) is never deleted. The step logs a warning, writes the `demoKept` status mark, and the start still succeeds.
- **Nothing canned.**
  - Sample emails are inputs, decided live.
  - Incident text is generated from the real failures.
  - Mocks exist only in CI's configuration, never in the judges' compose file.
- **Simulated devices.**
  - Each carries a visible "Simulated" label.
  - Each is a real channel. Its messages look in Visual Trace exactly like a real channel's, and only the channel name shows that they are simulated.
  - **The phone** shows the session's notifications only, in the same catalog text the paired chat gets: plain text, no Markdown or emoji, times in the instance zone with " ET" on the online demo. It has no composer.
- **Mailbox emails.**
  - They are untrusted items, decided live.
  - Ignore and Digest notify nobody, and an email can never make OcuTalon act.
  - Only Tell now or Act notifies.
- **Break the feed.**
  - **Active:** only while the session watches the Orders production and no Orders incident is open, awaiting approval or fixing. An open incident counts until it is dismissed, whatever its variant. It also stays inactive while a run under 3 minutes old has had no notice.
  - **Presses:** two quick presses send one batch.
  - **Replay rule:** a resolved incident is closed first, so every run opens a new incident with its own approval request.
  - **Isolation:** two concurrent sessions each get exactly 50 failed orders, tagged with their own `TraceRef`, and no shared partner state changes.
  - **What a press is:** a production message, never a turn. It creates no `Turn` row and no decision, and it doesn't count toward the message allowance. It is audited as an `Action`.
- **The guide.**
  - A step is done only from the session's real state:
    - step 1: an Orders watch exists;
    - step 2: a reminder exists, pending or fired;
    - step 3: the incident, fallback or no-fix notice arrived in the current run;
    - step 4: its approval request was answered;
    - step 5: the trace-opened marker is set.
  - **Finish state:** shows only after an approved fix and a resolved incident. After a fallback notice, a no-fix notice or a rejection, the guide keeps the matching step 4 hint.
  - **Run again:** resets the guide's markers only, never the session's data.
- **Timing.**
  - Against the mock, a tell-now notification reaches the simulated phone within 5 seconds of its decision. Story 4.5 turns on this half of Story 2.7's CI check.
  - Live updates arrive within 2 seconds.
  - NFR-7's 60 seconds from the press to the notice, and the demo-path time budget, are measured in the rehearsal, not asserted in CI.

## Technical Decisions

- **Settings.**
  - Demo mode is the product setting `demo.mode` ("1" or "0") in `OcuTalon.Data.Setting`, read through `Setting.Get`, which caches for 60 seconds.
  - The Demo step seeds it to "1" when `/opt/ocutalon/version` exists (OcuTalon's own image), and to "0" otherwise.
  - `SettingsOps` is the only run-time settings writer. Its allow-list holds only demo mode in release 1.
  - `OcuTalon.Core.Admin.SetDemoMode` calls `Commands.Submit` with origin `system`, which sends to `CommandsIn` and then `SettingsOps`. `CommandsIn` refuses demo mode from origin `tool`.
- **`OcuTalon.Install.Step.Demo` (this epic's file, not Epic 3's).**
  - **On:** it creates OCUORDERS, its `OCUORDERS_CODE` and `OCUORDERS_DATA` databases and its mappings (the public package and global included), the trace application `/ocutalon/trace/ocuorders/`, and the trace role's OCUORDERS grants and SQL privileges. It adds the grants back on every start, after the roles step rebuilds the roles.
  - **The Orders production:** the step starts it itself (it is not autostart) and recovers it if it is Troubled. It never stops another production.
  - **When it runs:** in its fixed install position, and again on every demo-mode switch, which reruns only this step.
- **Namespaces.**
  - In `OcuTalon.Demo`, only `PartnerTrigger` and the Demo step switch namespace, each in one `New $NAMESPACE` method.
  - The partner is called as `Partner.Send(count, dateFormat, traceRef, orderDate)`.
  - The Orders items run `PartnerOrdersIn`, then `OrdersFromPartner` (which runs Epic 0's real transform and returns its error unchanged), then `OrdersToWarehouse`.
  - Orders message bodies carry no `SessionRef`. The session's `TraceRef` travels as their `SuperSession`.
- **How state changes.**
  - Changes enter only through business services. Adapterless ones are started with `Ens.Director.CreateBusinessService` and `ProcessInput`.
  - REST code writes only the UI-only markers in `GuideState`.
  - **`BreakFeedIn`, in order:**
    1. takes `LOCK ^OcuTalon.Demo.BreakFeed(SessionRef)`;
    2. checks availability with `Guide.Compute`;
    3. sends `IncidentCommand` `closeForReplay` to `IncidentManager` and waits for its answer;
    4. writes the `BreakFeedRun` row as `sending` and publishes `breakfeed.progress`;
    5. calls `PartnerTrigger`;
    6. marks the run `sent` and publishes again.
  - **Incidents:** `IncidentManager` (Lane A) is the only writer of incidents. Ownership reads hide an incident until its notice sets `NoticedAt`. Before that, only `watch.progress` events go out (`noticed`, `settling`, `diagnosing`, keyed by the incident's `Ref`), and they drive the box's status lines.
  - **The production class:** edit only the Lane B region.
- **The guide.**
  - **The single source:** `OcuTalon.Demo.Guide.Compute(SessionRef)` returns:
    - the current step, the steps' states and the run epoch;
    - the Break the feed state with its hint reason and stage: sending, waiting, still waiting (from 90 s), no notice (from 3 min, which makes the control available again) or notice arrived;
    - step 4's variant: paired, unpaired, rejected, fallback or no fix;
    - the finish condition.

    `/state` includes the result, and the page never decides any of it.
  - **`GuideState`** holds the markers and the run epoch.
  - **Publishing:** the `Live.Publish` hook is the one publisher of `guide.state`. With demo mode on, it recomputes after publishing `chat.message`, `incident`, `approval`, `check`, `reminder`, `pairing` or `breakfeed.progress`, and publishes only on a change. `StatusMonitor`'s 15-second tick does the same for sessions with an open run, and every marker write recomputes.
  - **"Telegram is on"** means `OcuTalon.Channel.Telegram.In.Included()` returns 1 and the recorded Telegram state is `on`, the same source as `/state`'s Telegram block. Until Story 10.3 it counts as off.
- **Channels.**
  - `Notify` routes a notification to the web chat, to `SimPhoneOut` (demo mode only) and to the paired chat. Kind `allowance` never reaches the phone.
  - Producers never render text. Only `*Out` operations do, through `OcuTalon.Msg.Catalog.Render(key, slots, channel)` with the channels `phone` and `mailbox`.
  - Each `*Out` operation:
    - records a `SimMessage` row;
    - records its `Delivery` row through `Data.Delivery.Record(ownerRef, channel, channelMessageId, approvalRef)`;
    - publishes its event: `phone` from `SimPhoneOut`, `mailbox` from `SimMailboxOut`.
  - **`SimMailboxIn`:**
    - records the arriving `SimMessage` with the item's `ItemId`;
    - publishes `mailbox`;
    - sends an `OcuTalon.Msg.Item` (channel `mailbox`, provenance `untrusted`) to `Intake`.

    The mailbox row finds its decision by that `ItemId`, which the decision event carries. In release 1 nothing routes to `SimMailboxOut`, so its test uses a fixture message.
- **Data and conventions.**
  - Lane B owns `GuideState`, `BreakFeedRun`, `SimMessage`, `Delivery`, `Setting`, `StatusMark` and `Live.Event`.
  - Other epics' rows (Lane A's `BackgroundCheck`, `Incident`, `ApprovalRequest`, `Decision` and `Usage`, and Epic 8's `Reminder`) are read only through `OcuTalon.Data.Ownership`, which applies the caller's `SessionRef`. No endpoint accepts a `SessionRef` from the client. The finish state's run total comes from `Ownership.RunCost`.
  - **Storage:** append-only, with each class's storage block committed. A private class sets `DEFAULTGLOBAL` `^OcuTalonP.<Short>` and registers the short name in `src/short-names.tsv`.
  - **Refs and times:** Refs come from `Bridge.Ids.NewRef()` (22 characters, base64url). Times are stored as UTC ISO 8601 and rendered only through `Data.Time`.
  - **Live payloads:** each is the full current view, keyed by `Ref`. They are published after commit, never inside a transaction. Each type has one publisher. The TypeScript types are generated by `web/scripts/payloads.mjs`, and the page's texts by `web/scripts/catalog.mjs`.
  - **Audit:** `OcuTalon.Bridge.Audit` is the only writer: `Settings` for demo mode, `Action` for Break the feed. Each entry names the IRIS user, the `SessionRef` and the channel. Tests read entries back from the IRIS audit log, polling with a timeout.
  - **REST:**
    - Paths are under `/ocutalon/api/v1`. Errors are `{"error":{"code","message"}}` in plain English.
    - A route answers 501 `not_built` until its story ships, and 404 while demo mode is off.
    - An inactive Break the feed answers 409 with its hint. A mailbox field error answers 400.
    - State-changing calls need `application/json`, `X-OcuTalon-Request: 1` and a matching `Origin`.
- **Testing.**
  - **`%UnitTest`:** classes live in `OcuTalon.Test.<Area>`, with doubles in `OcuTalon.Test.Demo`. They run in the `lane-b` shard through `ci/iris.sh`.
  - **Guide tests:** they drive every step and Break the feed state with fixture `BackgroundCheck`, `Reminder`, `Incident`, `ApprovalRequest` and `BreakFeedRun` rows.
  - **The mock:**
    - It matches the two guide prompts by their exact text inside the user message. Their scenarios live under `ci/mock/scenarios/B/`.
    - Mailbox tests pick their outcome with `[[mock:<name>]]` markers.
    - The real `Decide` has merged, so a keyless throwaway falls back to `tellnow`/`no_key`. Tests that need real outcomes point the runners at the mock key with Lane A's `RunnerFixture.PointKeys` and `RestoreKeys`.
    - Never switch keys on the shared `live:sign-in` stack.
  - **Demo-path specs:** `web/e2e/demo-path/0<n>-<id>.spec.ts`. An unbuilt part stays a `notBuilt(title, 'N.M')` call until its story turns it on; a turned-on test that must never skip again carries `@floor`.
  - **Floor specs** (`web/e2e/floor/`) run only in `live:floor`.

## UX & Interaction Patterns

- **Layout.**
  - The "Demo guide" region sits between the banners and the rail and chat. The Break the feed box sits at its right, over the device column.
  - The "Simulated devices" region sits right of the chat, at `device-width`, wider from 1440 px.
  - Under 680 px tall, the guide uses its compact single row. From 1024 to 1279 px wide, steps show numbers. Under 1024 px the page stacks into one column.
- **The guide.**
  - Steps are buttons, selectable in any order. Markers: a check for done, a teal disc for current, a hollow circle for upcoming, and a 2 px bottom bar for the selected step (never a teal ring).
  - The current step has `aria-current="step"`, and each step's name includes its state.
  - When a step completes, the guide advances by itself, moves focus to the prompt bar's action, and announces "Step {n} of 5: {step}".
  - "Hide guide" collapses it to a bar whose "Show guide" button has `aria-expanded`. The choice is remembered per browser.
- **Guide prompts.**
  - Each is sent verbatim as the user's own chat message with `fromGuide`. It shows the display-only caption "From the demo guide".
  - So each is a real turn with a decision and a trace, and it counts toward the allowance.
- **The Break the feed box.**
  - It always shows the "Demo control" label.
  - An inactive button stays focusable with `aria-disabled`, with its visible hint linked by `aria-describedby`.
  - Progress lines never show counts. The box is not a live region.
- **The devices.**
  - **Tabs:** ARIA tabs, moved between with the arrow keys and marked with `aria-selected`. They never switch by themselves: new content puts a badge count in the tab's name. A switch the user causes is allowed, such as the guide's Show me. The selected tab is remembered per browser.
  - **Labels:** the amber "Simulated" label is static and unfocusable.
  - **The phone:** a generic frame, with no clock, carrier, brand or Telegram look. It is not a live region. It doesn't auto-scroll while the user has scrolled up or an approval is pending; the "New messages" pattern applies instead.
- **The mailbox.**
  - The sample chips are always visible. Pressing one keeps focus on it and announces the new row.
  - The compose form replaces the list, with focus on From.
  - **A row:** an unread dot with hidden "Unread". It shows "Deciding…", then the outcome chip, and the decision is announced. It opens in place with focus on the subject heading, and Back returns focus to the row.
  - Untrusted text is rendered only as text.
- **Shared rules.**
  - The page speaks only through `Announcer`.
  - Focus moves only when an update removed the focused element, through `shared/focus-rule.ts`.
  - Links that leave the page say "(opens in a new tab)".
  - Prompts, hints, box states, empty states, sample emails and the finish text are exact texts. Take them from the stories and the UX verbatim.

## Cross-Story Dependencies

- **Order inside the epic.**
  - Story 4.1 comes first: the setting, `SettingsOps`, the badge and the Demo step.
  - Stories 4.2, 4.3 and 4.6 each add the demo-off 404 to the endpoints they build.
  - Story 4.2's `Guide.Compute` and `guide.state` feed Story 4.3's locked check and Stories 4.4 and 4.7's rendering, including step 4's variants and the finish condition.
  - Story 4.5's phone tab is what Story 4.7's Show me selects.
- **Lane A paths not merged yet.**
  - Not merged: the Orders watch and `IncidentManager` (Epic 5) and approvals (Epic 3). Tests use fixture rows and an `IncidentManager` double, and Epic 11 turns the path on end to end.
  - The real reminders arrive with Epic 8, running now on runner C.
- **Running beside Story 8.2.**
  - `StatusMonitor` and `Web.Api` are shared by function. Each epic edits only its own conditions, fields and handlers, and prefers new methods to reshaping shared ones.
  - The B mock scenarios and the demo-path specs 01 to 04 and 06 are this epic's.
- **Waiting on this epic.**
  - Epic 6: incidents and approvals on the phone.
  - Stories 8.3 to 8.5: the phone, and guide step 2.
  - Story 10.2: the README quotes `SetDemoMode`.
  - Story 10.3: tests the Telegram row and the paired step 4.
  - Story 15.2: the IPM seed with demo mode off.
  - Story 31.3: adds the bridge link to the finish state.
- **Ledger items routed here.**
  - **DW-98 (Story 4.3):** with the real batch, assert that a `decision.recorded` and a `turn.step` emitted by the bridge reach the session's stream through `BridgeSink`.
  - **DW-198 (Story 4.4):** fix the WebKit focus-ring margin flake at 1280x600.
  - **DW-146 (Story 4.7):** check whether trace tabs hold licence connections, and if so, sign the specs' trace tabs out.
