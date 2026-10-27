# Epic 8 Context: Heartbeat and reminders, on time and surviving restarts

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 8 builds OcuTalon's clock in `OcuTalon.Schedule`. It runs on runner C, in Lane B's files. The one-minute heartbeat, its stalled warning and the firing of a reminder at its UTC due time on every channel are done. What remains is the rest of the reminder lifecycle:
- the commands the chat agent's tools send: set by a relative or local time, plain-English refusals, list, cancel and repeats;
- reminders set and cancelled through the chat on the demo path (guide step 2);
- surviving restarts and in-place upgrades, saying so when a reminder arrives late.

A lost reminder, a duplicate, or a late one that doesn't say so would break the user's trust.

## Stories

- Story 8.1: The heartbeat ticks every minute and catches up once after a restart (done)
- Story 8.2: The heartbeat-stalled warning comes from the real heartbeat (done)
- Story 8.3: A reminder fires on time on every channel (done)
- Story 8.4: Set, list and cancel reminders in plain words (the command side)
- Story 8.6: Reminders through the chat on the demo path (the chat side, split from 8.4)
- Story 8.5: Reminders survive restarts and upgrades, and late ones say so

Build order: 8.4, then 8.6, then 8.5, so the demo path comes first.

## Requirements & Constraints

- **On time.** A reminder fires within 10 s of its due time and never before it, with one notification per channel. It is late only if its waiter woke more than 10 s after the due time (exactly 10 s is on time). CI asserts order and outcome only, never seconds. The 10 s bound is measured in the clean-machine rehearsal.
- **Due forms.** A `SetReminder` carries exactly one of:
  - `DueAt` in UTC (built in 8.3);
  - `DelaySeconds`, counted from when the command arrives;
  - `LocalDueAt` with no zone, read in the instance's zone, so "Thursday at 10" fires at 10:00 local time, even in a daylight-saving week.
- **Refusals.** Empty or blank text, a past due time, or no due form or more than one is refused with a plain-English reason that the tool passes back. A refusal creates no row, no waiter and no event.
- **Isolation and repeats.** A list returns only the caller's session's pending reminders. A cancel naming another session's reminder, or one already fired or cancelled, is refused and changes nothing, and it never reveals another session's reminder. A command repeated with the same `IdempotencyKey` returns the first result and creates no second row or waiter.
- **Restarts.**
  - A reminder that fell due while IRIS was down fires once, right after the production starts, marked late.
  - A reminder still in the future fires on time, not late, and the rail shows its countdown throughout.
  - No reminder ever fires twice, even when an old waiter and a re-armed one both wake.
- **Visibility.** Every change reaches the page within one live update. A pending reminder shows in Visual Trace as a waiting process. Every text the user sees comes from the catalog.

## Technical Decisions

- **Ownership.**
  - Epic 8 may edit: `ReminderOps`, `ReminderTimer`, `Schedule.Reminder`, `ReminderStart`, the `Reminder` table, the `reminder` event and its payload, `Install.Step.Schedule`, `ci/mock/scenarios/B/` and `Test/Schedule/**`.
  - Lane B's but contended with other running epics, so edit them only under an orchestrator ruling: `CommandsIn`, `Commands`, `Notify`, `WebChatOut`, `SimPhoneOut`, `Production.cls`, the catalog classes, `web/src/**`, `ci/mock/mock.mjs` and `scenarios.mjs`, `Test/Data/Fixture.cls`, and `Ownership.Reminders`.
  - Lane A's, read only: the reminder tools in `OcuTalon.Tools` (Story 1.10), `Agent/**` including `Agent/Chat.cls`, `Test/Tools/**`, `Test/Agent/**`, `Test/Bridge/**`, `src/bridge/**`, the installer core and its `Reconcile` step, and `release/`.
- **Shared files, as ruled.**
  - `Test/Data/Tables.cls` XData `Contracts` and the stub rows of `Test/Core/CommandsInProduction.cls` are shared by entry: Epic 8 edits only its own entries, and an integrate-forward conflict there is a plain union. 8.4 removes only the `SetReminder|ReminderOps|web_user` stub entry and `ReminderOps` from the stub-owner sentences. Epic 5 makes the same kind of edit, so expect a union.
  - In `docker/tests/test-production.sh` row 17, 8.4 changes only the two expected lines (`not_built` becomes `refused`) and the matching header phrase.
  - The header comment of `docker/tests/test-demo-path.sh` is 8.6's, once it turns spec 03 on.
  - Every such edit is reported as a footprint extension.
- **Command path.** Commands go only through `OcuTalon.Core.Commands.Submit`, then `CommandsIn`, then `ReminderOps`, which answers with a synchronous `CommandResult` (`Ok`, `Outcome`, `Ref`, `DueAt`, `Message`, `Data`).
  - `CommandsIn` accepts the three reminder verbs only from origin `tool`. `Submit` forces `tool` inside a bridge context, so tests submit under one.
  - A tool's key is the turn's `ItemId` plus the call's position (DW-141: a re-run turn can reuse it for a different call).
  - Story 1.10's set tool sends only `DelaySeconds` or `LocalDueAt`, never `DueAt`. Its list tool reads exactly `Data = {"reminders":[{"ref","text","dueAt"}]}`: pending reminders, earliest due first, `dueAt` in UTC (DW-135).
  - The tools pass `Message` to the model unchanged, and the user never sees it as written.
- **As built in 8.3.**
  - `ReminderOps` carries out only a set with a UTC `DueAt`. It answers every other form and verb `$$$NotImplemented`, which `CommandsIn` turns into `not_built`. It keeps `STUB = 1`, and its oracle row in `Test/Core/ProductionItems.cls` stays `stub: 1` until 8.4 deletes both.
  - The set saves the row, then starts the waiter synchronously (`ReminderStart`, 10 s limit). The waiter writes its own start header id to `Reminder.TraceHeaderId` before it answers. A failed start deletes the row and answers `failed`. The answer for a set reminder is `set`, with the message "The reminder is set."
  - `ReminderTimer` is frozen. It stores only `Ref`, and `OnRequest` and `OnResponse` call `Schedule.Reminder.Start` and `Wake`.
  - When it wakes, the waiter opens the row under an exclusive lock and:
    - ends without sending if the row is not pending;
    - sets the timer again if it woke early;
    - if the row is busy, logs a warning and tries again in 1 s;
    - otherwise marks the row fired and saves it, sends one `reminder` Notification, releases the lock, and publishes the fired event.

    A failed send is logged and never retried.
  - Each waiter runs in its own trace session. The starter clears `..%SessionId`, sets `..%SuperSession` to the session's `TraceRef`, and restores both afterwards. The job's session id doesn't move.
- **The `Reminder` row is the source of truth.** It holds `Ref` (from `Bridge.Ids.NewRef()`), `SessionRef`, `Text`, `DueAt` (UTC), `State` (pending, fired or cancelled), `Late`, `CreatedAt` and `TraceHeaderId`.
  - Ruled for 8.4: the row gains `IdempotencyKey` and `CancelKey` (`%String(MAXLEN=128)`, no index).
  - Storage is append-only. Every persistent and message class commits its compiler-generated `Storage` block and never edits it by hand. CI diffs those blocks against the previous `v*` tag.
  - Only `ReminderTimer` and `ApprovalHold` may hold a timer longer than 2 minutes.
- **Reconcile.** The Schedule area's `Reconcile()` runs at every start, so it must be idempotent. For each pending row whose waiter is gone, it starts a new waiter armed from the row's due time, and the waiter stores its new header id. It leaves fired and cancelled rows alone, and starts nothing for a row whose waiter is still waiting.
- **Notification and text.** Producers never render text. `Kind` is `reminder`, with key `reminder.due` ("Reminder: {text}.", slots `text` and `dueAt`) or `reminder.late` ("Reminder (late; it was due at {time}): {text}.", slots `time`, `text` and `dueAt`). Both keys are in `Catalog.Core`. `WebChatOut` keeps `dueAt` on the card's `Delivery` row.
- **Routing.** `Notify` sends a reminder to `WebChatOut`, to `SimPhoneOut` in demo mode, and to `TelegramOut` only when Telegram is included and the session is paired. `TelegramOut` is a disabled stub until Epic 12, so test that route on `Notify`'s rule, with a fixture pairing and `^OcuTalonTest("TelegramIncluded")`.
- **Live events.** `ReminderOps` publishes `reminder` created and cancelled, and `ReminderTimer` publishes fired. Events go only through `Live.Publish`, after the commit and never inside a transaction. The payload is `Payload.Reminder.FromRow`, the full view keyed by `Ref`. In demo mode `Publish` recomputes the guide itself.
- **Time.** `OcuTalon.Data.Time` is the only converter, and `Bridge.Time` is the bridge's twin. The instance zone is the container's `TZ`, but throwaways run in UTC, so pin daylight-saving cases in-process with the zone set. Measured on build 154: a spring-forward gap time reads one hour later, a fall-back overlap time takes its first instant, and an impossible date throws.
- **Mock.**
  - Story 4.4's `B/guide-reminder.json` answers "Remind me in 1 minute to stretch." with `set_reminder` (text `stretch`, `delaySeconds` 60), then a text reply. `Test.Demo.GuidePrompts` and `guide-view.test.mjs` pin it.
  - The loader refuses a repeated prompt, so 8.6 extends that file and adds no second one (DW-232).
  - The mock replays fixed tool inputs. It can't compute "next Thursday" or carry a `Ref` from an earlier tool result. The Thursday and cancel cases are `[[mock:<name>]]` marker scenarios.
- **Tests.**
  - `%UnitTest` classes go in `OcuTalon.Test.Schedule.<Subject>`, shard `lane-b`. They run only on throwaways or CI. Each test creates and removes what it asserts on, and ends every waiter it started. Restart cases restart IRIS in their own compose project.
  - A warm stack picks up a changed class that a production item runs only after that item restarts.
  - The framework deletes a completed `ReminderTimer` instance, so wait for "no live instance".
  - `live:sign-in` ran about 506 s against its 540 s local deadline after 8.3 (CI allows 1200 s).
  - No committed file may hold a local absolute path, or CI's `test-boundaries.sh` fails.

## UX & Interaction Patterns

- **Rail row.** It shows the text, the due time, a tabular countdown ("Stretch · in 59 s") and a trace link to the waiting process. It is read-only, with the hint: To cancel, ask: "Cancel my reminder to stretch." When none is pending, the rail reads "None pending."
- **When it fires.** The row leaves the rail and becomes a notice card in the chat, showing the catalog text exactly plus "Due {time} · arrived {time}". The simulated phone shows the same text as the paired chat.
- **Guide step 2.** It sends "Remind me in 1 minute to stretch." word for word. It is done when the session has a reminder, pending or fired. The reminder lands during step 3's wait ("The reminder may arrive first."). Rehearsal measurement may later shorten the prompt to "in 30 seconds".

## Cross-Story Dependencies

- **Merged.** Epic 1 (the set, list and cancel tools), Epic 2 (rail rows, notice cards, `Notify`) and Epic 4 (simulated phone, demo routing, guide step 2, `guide-reminder.json`). Epic 4's guide tests use fixture `Reminder` rows and must stay green.
- **Within the epic.**
  - 8.4's cancel relies on 8.3's rule that a waiter whose row is no longer pending sends nothing, and on the same row lock.
  - 8.6 needs 8.4's `DelaySeconds` set, list and cancel.
  - 8.5 re-arms through `ReminderStart` and `ReminderTimer`, and reuses 8.3's late key. It leaves cancelled rows and the key properties alone.
  - DW-296: a caller holding a `Reminder` row lock for 10 s or more, or across a waiter's start, leaves that waiter unarmed. 8.5's `Reconcile` must not do it.
- **Demo-path spec 03** (`web/e2e/demo-path/03-reminder.spec.ts`). Its `notBuilt(..., '8.4')` line predates the split, and Story 8.6 turns it on once it passes on the integration branch with the CI mock. Under DW-210, skip before any browser fixture starts: `demo-path-summary.test.mjs`'s `playwrightEnv()` leaves local browsers usable, so a late skip fails only the browserless hosted `web` job. Check with `PLAYWRIGHT_BROWSERS_PATH=/nonexistent`.
- **Story 16.4 is not built.** Under DW-291, its sign-out test uses 8.4's real cancel path: one `CancelReminder` per pending `Ref`, with no cancel-by-session entry point. Its closed-page case expects a reminder to fire after the CSP session ended. Epic 8 touches nothing of Epic 16. Story 29.4 waits for this epic.
- **Heartbeat tests.** A test that suspends the heartbeat task or moves its tick mark must end with the task as it found it and a fresh real tick, because `/state` and `StatusMonitor` read the real heartbeat. This matters for 8.5's restarts.
- **Routed elsewhere.**
  - DW-142 (Chat's instructions still refuse commands and name no reminder ability) goes to Story 11.1.
  - DW-140 (Chat's 4-iteration ceiling) goes to Story 11.6.
  - Epic 8 never edits `Agent/Chat.cls`. Lane A's release work keeps the full upgrade harness.
- **Ledger owned here.** 8.4 owns DW-135 and DW-141; 8.6 owns DW-210 and DW-232.
