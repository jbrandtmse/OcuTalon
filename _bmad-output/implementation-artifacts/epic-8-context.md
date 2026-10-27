# Epic 8 Context: Heartbeat and reminders, on time and surviving restarts

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 8 builds OcuTalon's clock in `OcuTalon.Schedule`. It runs on runner C, in Lane B's files. The one-minute heartbeat and its stalled warning are done. Reminders remain: a user asks for one in plain words, and it fires on time on every channel of their session. They can list and cancel reminders in the chat. A reminder survives restarts and in-place upgrades, and says so when it arrives late. Guide step 2 of the demo path depends on this. A lost reminder, or a late one that doesn't say so, would break the user's trust.

## Stories

- Story 8.1: The heartbeat ticks every minute and catches up once after a restart (done)
- Story 8.2: The heartbeat-stalled warning comes from the real heartbeat (done)
- Story 8.3: A reminder fires on time on every channel
- Story 8.4: Set, list and cancel reminders in plain words
- Story 8.5: Reminders survive restarts and upgrades, and late ones say so

## Requirements & Constraints

- **On time.** A reminder fires within 10 s of its due time and never before it, with one notification per channel. It is marked late only if its waiter woke more than 10 s after the due time. CI checks order and outcome only (one notification per channel, late or not), never seconds. The 10 s limit is measured in the clean-machine rehearsal.
- **Due forms.** A reminder has exactly one of:
  - `DueAt`, in UTC;
  - `DelaySeconds`, counted from when the command arrives;
  - `LocalDueAt`, with no zone, converted in the instance's zone, so "Thursday at 10" fires at 10:00 local time even in a daylight-saving week.

  The command is refused, with a plain-English reason the tool passes back, if the text is empty, the due time has passed, or it has no due form or more than one. A refusal creates no row and no waiter.
- **Isolation and repeats.** A list returns only the caller's session's pending reminders. A cancel naming another session's reminder, or one already fired or cancelled, is refused and changes nothing. A command repeated with the same `IdempotencyKey` returns the first result and creates no second row or waiter.
- **Restarts.**
  - A reminder that fell due while IRIS was down fires once, right after the production starts, marked late.
  - A reminder still in the future fires on time, not late, and its rail countdown shows the whole time.
  - No reminder fires twice, even when an old waiter and a re-armed one both wake.
- **Visibility.** Every change reaches the page within one live update. A pending reminder shows in Visual Trace as a waiting process. Every text the user sees comes from the catalog.

## Technical Decisions

- **Ownership.**
  - Lane B's, editable here: `ReminderOps`, `ReminderTimer`, the `Reminder` table, the `reminder` event and its payload, `CommandsIn`, `Notify`, `WebChatOut`, `SimPhoneOut`, `Catalog.Core`, `Install.Step.Schedule`, the mock's behaviour and `ci/mock/scenarios/B/`.
  - Lane A's, read only: the reminder tools in `OcuTalon.Tools` (Story 1.10), Chat (`OcuTalon.Agent`), the installer core and its `Reconcile` step, and `release/`.
- **Command path.**
  - Each verb carries `Origin`, `IdempotencyKey` and `SessionRef`: `SetReminder`, `ListReminders`, and `CancelReminder`, which also takes a `ReminderRef`.
  - Commands go only through `OcuTalon.Core.Commands.Submit`, then `CommandsIn` (which accepts these verbs from origin `tool` only), then `ReminderOps`, which answers with a synchronous `CommandResult`. `Submit` forces origin `tool` inside a bridge context, so tests submit under one.
  - A tool's key is the turn's `ItemId` plus the call's position. `SetReminder` answers with the reminder's `Ref` and due time.
  - `ListReminders` answers `CommandResult.Data = {"reminders":[{"ref","text","dueAt"}]}`: pending reminders only, earliest due first, `dueAt` in UTC. Story 1.10's tool and its test double read exactly this shape (DW-135).
- **A reminder is one `Reminder` row plus one `ReminderTimer`.**
  - The row is the source of truth. It holds the `Ref` (from `OcuTalon.Bridge.Ids.NewRef()`), `SessionRef`, the text, the due time in UTC, the state (pending, fired or cancelled), `Late`, and the waiter's trace header id, which the rail's trace link uses.
  - The waiter waits on `SetTimer`. When it wakes, it reads the row under a lock.
    - If the row is still pending, it marks it fired (and late, if it is) and sends one `OcuTalon.Msg.Notification` of kind `reminder`.
    - Otherwise (the reminder was cancelled, or this waiter is a duplicate) it ends without sending.
  - Each waiter runs in its own trace session: it clears `..%SessionId` before sending and keeps `SuperSession` set to the session's `TraceRef`.
- **Frozen waiter.**
  - `ReminderTimer` and `ApprovalHold` are the only processes allowed a timer longer than 2 minutes.
  - `ReminderTimer`'s persistent properties are frozen: append only, with its logic in other classes. `ApprovalHold` follows the same pattern, storing only its row's `Ref`.
  - Every persistent and message class commits its compiler-generated `Storage` block, which is never edited by hand. CI diffs those blocks against the previous `v*` tag.
- **Reconcile.** The Schedule area's `Reconcile()` declaration runs at every start and, on IPM installs, at every production start, so it must be idempotent.
  - For each pending row whose waiter is gone, it starts a new waiter armed from the row's due time and stores that waiter's trace header id on the row.
  - It leaves fired and cancelled rows alone, and doesn't touch a row whose waiter is still waiting.
- **Notification and text.**
  - Producers never render text. The keys are `reminder.due` ("Reminder: {text}.") and `reminder.late` ("Reminder (late; it was due at {time}): {text}."), both in `Catalog.Core`. `*Out` operations render through `Catalog.Render`.
  - Every reminder notification carries the due time as the UTC slot `dueAt`, which `WebChatOut` keeps on its `Delivery` row for the notice card.
- **Routing.** Epics 2 and 4 already built `Notify`. It sends a `reminder` notification to `WebChatOut`, to `SimPhoneOut` in demo mode, and to `TelegramOut` only when Telegram is included and the session is paired. Until Epic 12, check that last route against a fixture pairing, with `^OcuTalonTest("TelegramIncluded")` set.
- **Live events.**
  - `ReminderOps` publishes `reminder` events when a reminder is created or cancelled, and `ReminderTimer` publishes one when it fires.
  - Events go through `OcuTalon.Live.Publish`, only after the change commits. The payload is the full public view, keyed by `Ref`.
  - In demo mode, `Publish` recomputes the guide after each `reminder` event, so this epic writes no guide logic.
- **Time.** `OcuTalon.Data.Time` is the only converter. The instance zone is the container's `TZ`. Message text uses the instance's zone, and the page uses the browser's.
- **Mock.**
  - Story 4.4's `ci/mock/scenarios/B/guide-reminder.json` already answers "Remind me in 1 minute to stretch." (`set_reminder`, `delaySeconds` 60). The mock's loader refuses a repeated prompt, so Story 8.4 extends that file instead of adding a second one (DW-232).
  - The Thursday case is a `[[mock:<name>]]` marker scenario. The cancel case lists, then cancels by `Ref`.
- **Tests.**
  - `%UnitTest` classes go in `OcuTalon.Test.Schedule.<Subject>`, in shard `lane-b`, and run in throwaways or CI. Restart cases restart IRIS in their own compose project.
  - The reminder step's demo-path spec is `web/e2e/demo-path/03-reminder.spec.ts`, which has a `notBuilt(..., '8.4')` line.

## UX & Interaction Patterns

- **Rail row.** It shows the text, the due time, a tabular countdown ("Stretch · in 59 s") and a trace link to the waiting process. It is read-only, with the hint: To cancel, ask: "Cancel my reminder to stretch."
- **When it fires.** The row leaves the rail and becomes a notice card in the chat. The card shows the catalog text exactly, plus "Due {time} · arrived {time}". The simulated phone shows the same text the paired chat gets.
- **Guide step 2.** It sends "Remind me in 1 minute to stretch." word for word, and it is done when the session has a reminder, pending or fired. In the demo, the reminder lands during step 3's wait.

## Cross-Story Dependencies

- **Merged.**
  - Epic 1: the set, list and cancel tools.
  - Epic 2: the rail rows, notice cards and `Notify`.
  - Epic 4: the simulated phone, `Notify`'s demo routing, guide step 2 and `guide-reminder.json`. Its guide tests use fixture `Reminder` rows (`Test.Data.Fixture`), and they must stay green.
- **Order.** Story 8.5 follows Stories 8.3 and 8.4.
- **Heartbeat tests.** A test that suspends the heartbeat task or moves its tick mark must end with the task as it found it and a fresh real tick, because `/state` and `StatusMonitor` read the real heartbeat. This matters for 8.5's restarts.
- **Story 16.4 is not built yet.**
  - Its sign-out (`SessionOps.End`) is planned to cancel the session's reminders through a recording `ReminderOps` test double until Story 8.4 merges.
  - Its closed-page case expects a reminder to fire on time after the CSP session has ended.
  - Under ruling U-107, Story 8.4 delivers the real cancel path with its own tests, and the 16.4 side goes to the orchestrator when 8.4 is planned.
  - Story 29.4 waits for this epic.
- **Reminder-step spec.**
  - When it passes on the integration branch with the CI mock, pressing Send on step 2 shows the reply and a "Stretch" row with its countdown, and the guide marks step 2 done. Story 8.2's matching real switch went to Story 11.1 (DW-202).
  - Skip before any browser fixture starts. Under DW-210, `demo-path-summary.test.mjs`'s `playwrightEnv()` leaves local browsers usable, so a late skip stays green locally and fails only the browserless hosted `web` job. Check with `PLAYWRIGHT_BROWSERS_PATH=/nonexistent`.
- **Upgrades.** The full upgrade harness stays with Lane A's release work.
- **Other ledger items routed to 8.4.** DW-140 and DW-142 are in Lane A's Chat.
  - DW-140: Chat's 4-iteration ceiling may be too low for a turn that lists and then cancels several reminders.
  - DW-141: the `<ItemId>:<position>` key can match an earlier command's result when a turn is run again.
  - DW-142: Chat's instructions still say "I can't run commands" and name no reminder ability.
