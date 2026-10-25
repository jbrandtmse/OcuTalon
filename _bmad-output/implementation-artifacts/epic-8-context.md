# Epic 8 Context: Heartbeat and reminders, on time and surviving restarts

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 8 builds OcuTalon's clock in `OcuTalon.Schedule`. It runs on runner C, in Lane B's files. A one-minute heartbeat drives the background checks and the page's heartbeat-stalled warning. A user asks for a reminder in plain words, and it fires on time on every channel of their session. The user can list and cancel reminders in the chat, reminders survive restarts and in-place upgrades, and a late reminder says it is late. The demo path's guide step 2 depends on this epic. So does the user's trust: a lost reminder, a late one that doesn't say so, or a check that quietly stops running would break it.

## Stories

- Story 8.1: The heartbeat ticks every minute and catches up once after a restart
- Story 8.2: The heartbeat-stalled warning comes from the real heartbeat
- Story 8.3: A reminder fires on time on every channel
- Story 8.4: Set, list and cancel reminders in plain words
- Story 8.5: Reminders survive restarts and upgrades, and late ones say so

## Requirements & Constraints

- **Heartbeat.** It ticks once a minute, and each tick is a production message that shows in Visual Trace.
  - After downtime the next run sends exactly one tick, flagged as a catch-up and carrying the old previous tick time. It never sends one tick per missed minute, and the Task Manager must not replay missed runs either (a test checks the task's definition).
  - While the production is stopped (during an upgrade, for example), the task ends without an error and sends nothing.
  - A gap of more than one minute is recorded with its start, its end and the minutes missed, so the step-2 digest can count a check that missed a run as not checked.
- **Heartbeat stalled.** The condition is on when the last tick is more than 3 minutes old, with that tick's time as its slot. It is off when the install has never recorded a tick, and it clears within one live update of a real tick.
- **Reminders on time.** A reminder fires within 10 seconds of its due time, and it is marked late only if its waiter woke more than 10 seconds after the due time.
  - A reminder that fell due while IRIS was down fires once, right after the production starts, marked late.
  - A reminder still in the future at a restart fires on time, not late, and its rail countdown shows throughout.
  - No reminder fires twice or before its due time. Each one reaches every channel of its session.
- **Due forms.** A reminder has exactly one of these:
  - `DueAt`, in UTC;
  - `DelaySeconds`, counted from when the command arrives;
  - `LocalDueAt`, with no zone, converted in the instance's zone so that "Thursday at 10" means 10:00 local time, even in a week with a daylight-saving change.

  An empty text, a due time already past, or no due form or more than one is refused with a plain-English reason, and no row or waiter is created.
- **Isolation and repeats.**
  - A list returns only the session's own pending reminders.
  - Cancelling another session's reminder, or one already fired or cancelled, is refused and changes nothing.
  - A command repeated with the same `IdempotencyKey` returns the first result and creates no second row or waiter.
- **Upgrades.** A reminder pending before an in-place upgrade that recompiles `ReminderTimer` still fires.
- **Live updates and text.** Every change reaches the page within one live update (2 seconds), and every text a user sees is plain English from the catalog.
- **How CI tests time.** CI asserts order and outcome only (one notification per channel, and whether it was late), never seconds. The 10-second bound is measured in the clean-machine rehearsal.

## Technical Decisions

- **Ownership.**
  - Lane B's, which this epic may edit: `HeartbeatIn`, `ReminderOps` and `ReminderTimer` (`OcuTalon.Schedule.*`), `StatusMonitor`, `CommandsIn`, `Notify`, `OcuTalon.Install.Step.Schedule`, the `Reminder` and `StatusMark` tables, and the `reminder` and `status` events.
  - Lane A's, which this epic reads but never edits: `Checks`, `BackgroundCheck`, the `check` event, the reminder tools in `OcuTalon.Tools`, Chat (`OcuTalon.Agent`), and the installer core (the step registry and its task step).
  - Epic 0's `Tick` and `StatusMark` may only be appended to.
- **Heartbeat task.** There is one Task Manager task, with a name starting `OcuTalon` and a task class in `OcuTalon.Schedule`.
  - It is declared in `Install.Step.Schedule`'s `Tasks()`. The core's task step creates it once and leaves an existing task alone.
  - It sets `RescheduleOnStart` to 1.
  - Each run calls the adapterless `HeartbeatIn` through `Ens.Director.CreateBusinessService` and `ProcessInput`, and doesn't wait for checks.
  - `HeartbeatIn` sends one `OcuTalon.Msg.Tick` to `Checks`, holding the tick time and the previous tick time in UTC. `Checks` decides which checks are due.
- **Status marks.** These are written only through `StatusMark.Record(mark, value)` and read one at a time through `Get(mark)`.
  - The last tick is the single mark `heartbeatTick`.
  - Each outage of more than one clock minute adds a `heartbeatGap.<start UTC>` row. Its value is JSON `{start, end, missed}`, and it is never purged.
  - The gap family is listed only by `OcuTalon.Schedule.Heartbeat.Gaps(from, to)`, a read-only query.
- **Status condition.** `/state` and `StatusMonitor` (which runs every 15 seconds) compute `heartbeatStalled` on read. `StatusMonitor` publishes a `status` event on the instance stream whenever the condition changes.
- **Commands.** `SetReminder`, `ListReminders` and `CancelReminder` (with `ReminderRef`) are Epic 0 verbs. Each carries `Origin`, `IdempotencyKey` and `SessionRef`.
  - They enter only through `OcuTalon.Core.Commands.Submit`, then `CommandsIn` (origin `tool` only), then `ReminderOps`, which answers with a synchronous `CommandResult`.
  - `Submit` sets `tool` inside a bridge context, so tests submit under one.
  - A tool's key is the turn's `ItemId` plus the tool call's position.
  - The `ListReminders` contract is `CommandResult.Data = {"reminders":[{"ref","text","dueAt"}]}`: pending reminders only, earliest due first, `dueAt` in UTC. Story 1.10's tool and its test double read exactly this shape.
- **A reminder is one `Reminder` row plus one `ReminderTimer`.** The row is the source of truth.
  - The row holds a `Ref` from `OcuTalon.Bridge.Ids.NewRef()`, the `SessionRef`, the text, the due time in UTC, the state (pending, fired or cancelled), `Late`, and the waiter's trace header id.
  - The waiter waits on `SetTimer`. When it wakes, it reads the row under a lock.
    - If the row is still pending, it marks it fired (and late, if it is) and sends one `OcuTalon.Msg.Notification` of kind `reminder`. The notification carries the reminder or late-reminder catalog key, with the text and the UTC slot `dueAt`.
    - Otherwise (the reminder was cancelled, or this waiter is a duplicate) it ends without sending.
- **Frozen classes.** `ReminderTimer` and `ApprovalHold` are the only business processes allowed a timer longer than 2 minutes.
  - `ReminderTimer`'s persistent properties are frozen: append only, with its logic in other classes.
  - Every persistent and message class commits its compiler-generated `Storage` block, which is never edited by hand. CI diffs those blocks against the previous `v*` tag.
- **Reconcile.** The Schedule area's `Reconcile()` runs from the installer's `Reconcile` step at every start. On IPM installs it also runs on every production start, so it must be idempotent.
  - For each pending row whose waiter is gone, it starts a new waiter armed from the row's due time and stores that waiter's trace header id on the row.
  - It leaves fired and cancelled rows alone, and doesn't touch a row whose waiter is still waiting.
- **Live events.** `reminder` events are published by `ReminderOps` (created, cancelled) and `ReminderTimer` (fired).
  - Events go through `OcuTalon.Live.Publish`, only after the change commits and never inside a transaction.
  - The payload is the full public view, keyed by `Ref`, with the trace target as a header id plus a namespace.
  - The rail lists pending reminders by due time.
- **Routing and text.** `Notify` sends a `reminder` notification to the web chat, to the simulated phone in demo mode, and to `TelegramOut` only when Telegram is included and the session is paired.
  - Producers never render text. `*Out` operations render through `OcuTalon.Msg.Catalog.Render`, and Lane B's keys live in `Catalog.Core`.
  - `WebChatOut` keeps the notice card's `DueAt` on its `Delivery` row.
- **Trace.** Each waiter starts its own trace session: it clears `..%SessionId` before it sends and keeps `SuperSession` set to the session's `TraceRef`.
- **Time.** Times are stored as UTC ISO 8601 to the second. `OcuTalon.Data.Time` is the only converter, and the instance's zone is the container's `TZ`.
- **Tests.**
  - `%UnitTest` classes go in `OcuTalon.Test.Schedule.<Subject>`, in shard `lane-b`. A test double there stands in for `Checks` and records each `Tick`.
  - Chat scenarios go in `ci/mock/scenarios/B/`: the guide prompt "Remind me in 1 minute to stretch." (matched when the user message contains its exact text), a `[[mock:<name>]]` marker scenario for "Remind me Thursday at 10 to load the new certificate.", and one that lists and then cancels by `Ref`.
  - Demo-path specs are `web/e2e/demo-path/0<n>-<id>.spec.ts`. An unbuilt part is `notBuilt(title, 'N.M')`.

## UX & Interaction Patterns

- **Reminder row.** It shows the text, the due time, a tabular countdown ("Stretch · in 59 s") and a trace link to the waiting process. It is read-only, with the hint: To cancel, ask: "Cancel my reminder to stretch."
  - When the reminder fires, the row leaves the rail and becomes a notice card. The card shows the catalog text exactly, plus "Due {time} · arrived {time}".
- **Texts.** "Reminder: {text}." When late: "Reminder (late; it was due at {time}): {text}." Message text uses the instance's zone, and the page uses the browser's.
- **Heartbeat-stalled banner.** It is an unclosable warning with no action: "Background checks have paused: the heartbeat last ran at {time}. Watches and reminders may be late until it recovers."
  - The polite announcer reads it once.
  - While the heartbeat is stalled, check rows show "Last run {time} (late)".
  - Focus follows `shared/focus-rule.ts`.
- **Guide step 2.** It sends "Remind me in 1 minute to stretch." word for word, and it is done when a reminder exists. The server computes completion when `reminder` events are published, so this epic writes no guide logic.

## Cross-Story Dependencies

- **Other epics.** Epic 1's set, list and cancel tools (Story 1.10) are the epic-level dependency.
  - Epic 2 has merged and integrated forward. Stories 8.2 and 8.3 use its stalled banner, check and Reminders rows, and `Notify` routing.
  - Stories 8.3 and 8.4 need Epic 4 merged, for the simulated phone and for guide step 2 with the shared B scenario.
  - Story 8.5 follows Stories 8.3 and 8.4.
  - Telegram ships in Epic 12, so until then Telegram routing is checked against a fixture pairing.
- **Turning on demo-path specs.**
  - Story 8.2's assertion that the "Orders production" check row shows a real last run runs against a fixture watch and fixture `Checks` rows. It is turned on for real once Lane A's Epic 5 and this epic have merged on the integration branch and it passes there.
  - Story 8.4 turns on the reminder-step spec once it passes there with the CI mock: Send on guide step 2 shows the reply and a "Stretch" row with its countdown, and the guide marks step 2 done.
- **Epic 16 no longer waits for this epic**, which reverses the October 22 order.
  - Story 16.4's sign-out tests cancel reminders through a recording `ReminderOps` test double until Story 8.4 merges.
  - Story 8.4 turns on the real cancel path there. It also adds a real reminder to 16.4's closed-page case: a reminder set before the CSP session times out fires on time after that session ended.
  - Story 29.4 now waits for this epic, because each session's reminders must stay its own.
- **Upgrade harness.** The full upgrade-in-place harness stays with Lane A's release work.
- **Open issues routed to Story 8.4.** All are in Lane A's Chat, so raise them with Lane A rather than editing its files:
  - Chat's 4-iteration ceiling may be too low for a turn that lists reminders and then cancels several.
  - The key `<ItemId>:<position>` can match an earlier command's result when a turn is run again.
  - Chat's instructions still say "I can't run commands" and name no reminder ability.
