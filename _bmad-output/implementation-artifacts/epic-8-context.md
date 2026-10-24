# Epic 8 Context: Heartbeat and reminders, on time and surviving restarts

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 8 builds OcuTalon's clock in the `OcuTalon.Schedule` area. Runner C runs it on its own developer instance, but in Lane B's files. A heartbeat ticks every minute. It drives the background checks and the page's heartbeat-stalled warning. A user can ask for a reminder in plain words, and it fires on time on every channel of their session. Reminders survive restarts and in-place upgrades, a reminder that fires more than 10 seconds after its due time says it is late, and the user can list and cancel reminders in the chat. This matters for two reasons. First, the demo path's step 2 reminder has to arrive while the user waits for the incident. Second, a lost reminder, a reminder that is late without saying so, or a check that quietly stops running would break the user's trust.

## Stories

- Story 8.1: The heartbeat ticks every minute and catches up once after a restart
- Story 8.2: The heartbeat-stalled warning comes from the real heartbeat
- Story 8.3: A reminder fires on time on every channel
- Story 8.4: Set, list and cancel reminders in plain words
- Story 8.5: Reminders survive restarts and upgrades, and late ones say so

## Requirements & Constraints

- **Heartbeat.** It runs once a minute, and each run is a production message you can see in Visual Trace.
  - After downtime, the next run sends one catch-up tick, never one tick per missed minute. The Task Manager must not replay missed runs either, and a test checks this on the task's definition.
  - A gap of more than one minute is recorded with its start, its end and the minutes missed, so the step-2 digest can count those checks as not checked.
  - While the production is stopped (during an upgrade, for example), the task ends without an error and sends nothing.
- **Heartbeat stalled.** The condition is on when the last tick is more than 3 minutes old, and its slot is that tick's time. It is off when the install has never recorded a tick. When a real tick arrives it clears within one live update.
- **Reminders on time.** A reminder fires within 10 seconds of its due time. It counts as late if its waiter wakes more than 10 seconds after the due time.
  - One that fell due while IRIS was down fires once, right after the production starts, and is marked late.
  - One that is still in the future at a restart fires on time and is not marked late.
  - No reminder ever fires twice, and none fires before its due time.
  - CI checks only order and outcome: one notification per channel, and whether it was late. It never asserts seconds. The 10-second bound is measured in the clean-machine rehearsal.
- **Due forms.** A command carries exactly one of:
  - `DueAt`, in UTC;
  - `DelaySeconds`, counted from when the command arrives;
  - `LocalDueAt`, converted in the instance's zone, so "Thursday at 10" means 10:00 local time even in a week with a daylight-saving change.

  An empty text, a due time already past, or no due form or more than one is refused with a plain-English reason. Nothing is created.
- **Isolation and idempotency.**
  - A list returns only the requesting session's pending reminders.
  - Cancelling another session's reminder, or one that already fired or was cancelled, is refused with a plain-English reason and changes nothing.
  - A repeated `IdempotencyKey` returns the first result and creates no second row or waiter.
- **Live updates.** Each change reaches the page within one live update (2 seconds). Every text a user sees is plain English and comes from the catalog.

## Technical Decisions

- **Ownership.** Lane B owns these, so the epic may edit them:
  - `HeartbeatIn`, `ReminderOps` and `ReminderTimer` (`OcuTalon.Schedule.*`);
  - `StatusMonitor`, `CommandsIn` and `Notify`;
  - the `Reminder` and `StatusMark` tables, `Tick`, and the `reminder` payload.

  Lane A owns `Checks` (`OcuTalon.Checks.Process`), `BackgroundCheck`, the `check` event, the reminder tools in `OcuTalon.Tools`, and Chat (`OcuTalon.Agent`). Read those, never edit them. Changes to Epic 0's `Tick` and `StatusMark` are append-only.
- **The heartbeat task.**
  - There is one Task Manager task. Its name starts with `OcuTalon`, and its task class is in `OcuTalon.Schedule`.
  - It is declared in `OcuTalon.Install.Step.Schedule`'s `Tasks()`. The installer core's task step creates it once and leaves an existing task alone.
  - Each run calls the adapterless `HeartbeatIn` through `Ens.Director.CreateBusinessService` and `ProcessInput`, and returns without waiting for any check.
  - `HeartbeatIn` sends one `OcuTalon.Msg.Tick` to `Checks`. The tick carries the tick time and the previous tick time, both in UTC, plus a catch-up flag. `HeartbeatIn` also writes the tick time through `StatusMark.Record`/`Get`.
  - `Checks` decides which checks are due. A check that missed several runs runs once.
- **Status.** `/state` and `StatusMonitor` (which runs every 15 seconds) compute the condition from `StatusMark` when read. `StatusMonitor` publishes a `status` event on the instance stream whenever the condition changes.
- **Commands.** `SetReminder`, `ListReminders` and `CancelReminder` are Epic 0's contracts. They enter only through `OcuTalon.Core.Commands.Submit`, then `CommandsIn`, then `ReminderOps`, which answers with a synchronous `CommandResult`. Inside a bridge context, `Submit` sets origin `tool`, so tests submit under one. Tools never write tables.
- **A reminder is a `Reminder` row plus one waiting `ReminderTimer`.**
  - The row is the source of truth. It holds:
    - a `Ref` from `OcuTalon.Bridge.Ids.NewRef()`;
    - the `SessionRef`, the text and the due time in UTC;
    - the state (pending, fired or cancelled) and `Late`;
    - the waiter's trace header id.
  - `ReminderTimer` waits on `SetTimer`. When it wakes it reads the row under a lock.
    - If the row is still pending, it marks it fired (and late, if it is), then sends one `OcuTalon.Msg.Notification` of kind `reminder`. The notification carries the reminder or late-reminder catalog key, with the text and the due time (UTC ISO 8601) as slots.
    - Otherwise, after a cancel or when it is a duplicate waiter, it ends silently.
- **Frozen classes.** `ReminderTimer` is one of only two business processes allowed a long timer. Keep its persistent properties frozen: append only, with its logic in other classes. Commit its compiler-generated `Storage` block, because CI diffs it against the previous release tag. Never edit storage by hand. The same append-only rule applies to `Reminder`, `StatusMark` and `Tick`.
- **Reconcile.** The Schedule area's `Reconcile()` runs at every start, from the installer's `Reconcile` step, and on every production start for IPM installs, so it must be idempotent.
  - For each pending row whose waiter is gone, it starts a new waiter armed from the row's due time and stores that waiter's trace header id.
  - It leaves fired and cancelled rows alone, and starts nothing for a row whose waiter is still waiting.
- **Live events.**
  - Two publishers send `reminder` events: `ReminderOps` (created, cancelled) and `ReminderTimer` (fired).
  - Events go through `OcuTalon.Live.Publish`, only after the change has committed and never inside an open transaction.
  - The payload is the reminder's full public view, keyed by `Ref`. Its trace target is a header id plus a namespace, and the web layer builds the URL.
- **Routing and text.** Producers never render text.
  - `Notify` sends `reminder` notifications to the web chat, the simulated phone (in demo mode) and the paired Telegram chat.
  - `*Out` operations render through `OcuTalon.Msg.Catalog.Render`.
- **Trace.** Each reminder waiter starts its own trace session: it clears `..%SessionId` before it sends and keeps `SuperSession` set to the session's `TraceRef`.
- **Time.** Times are stored and sent in UTC. `OcuTalon.Data.Time` is the only converter outside the bridge. The instance's zone is the container's `TZ`.
- **Tests.**
  - `%UnitTest` classes go in `OcuTalon.Test.Schedule`, in the `lane-b` shard.
  - A test double in `OcuTalon.Test.Schedule` stands in for `Checks` and records each `Tick`.
  - Chat scenarios go under `ci/mock/scenarios/B/`:
    - the guide prompt "Remind me in 1 minute to stretch.", matched on its exact text;
    - a marker scenario for "Remind me Thursday at 10 to load the new certificate.";
    - a scenario that lists and then cancels by `Ref`.
  - Restart tests restart IRIS in their own compose project.

## UX & Interaction Patterns

- **Reminder row (rail).** It shows the text, the due time, a tabular countdown ("Stretch · in 59 s") and a trace link to the waiting process. It is read-only, with the hint: To cancel, ask: "Cancel my reminder to stretch." When the reminder fires, the row leaves the rail and becomes a notice card. The card shows the catalog text exactly, plus "Due {time} · arrived {time}".
- **Texts.** "Reminder: {text}." When late: "Reminder (late; it was due at {time}): {text}."
- **Heartbeat-stalled banner.** It is a warning with no action, and it can't be closed: "Background checks have paused: the heartbeat last ran at {time}. Watches and reminders may be late until it recovers." The polite announcer reads it once. While the heartbeat is stalled, background check rows show "Last run {time} (late)".
- **Guide step 2.** It sends "Remind me in 1 minute to stretch." word for word, and is done when a reminder exists, pending or fired. Completion is computed on the server when `reminder` events are published, so this epic writes no guide logic.
- **Time zones.** Message text uses the instance's zone, and the page uses the browser's.

## Cross-Story Dependencies

- **Epic 1** provides Chat's set, list and cancel tools (Story 1.10). The `ListReminders` contract both sides use is `CommandResult.Data = {"reminders":[{"ref","text","dueAt"}]}`. It holds the session's pending reminders, earliest due first, with `dueAt` in UTC (DW-135).
- **Story-level waits.**
  - Story 8.1 needs only Epic 1.
  - Stories 8.2 and 8.3 need Epic 2 merged: the stalled banner, the check and Reminders rows, and `Notify`'s routing.
  - Stories 8.3 and 8.4 need Epic 4 merged: the simulated phone, guide step 2 and the shared B scenario.
  - Story 8.5 follows Stories 8.3 and 8.4.
- **Demo-path (REL-2) specs.**
  - Story 8.2's assertion that the "Orders production" check row shows a real last run runs against fixture watch and fixture `Checks` rows. It is turned on for real only once Lane A's Epic 5 (`Checks`, `WatchOps`) and Epic 8 have both merged on the integration branch and it passes there.
  - Story 8.4 turns on the reminder-step spec once it passes on the integration branch with the CI mock.
- **Epic 16.** Epic 8 merges before Epic 16, so Story 16.4's sign-out cancels reminders through the real `ReminderOps`.
- **Telegram** ships in Epic 12. Until then, Telegram routing is checked against a fixture pairing.
- **Upgrade harness.** The full upgrade-in-place harness stays with Lane A's release work. Story 8.5 proves only that a pending reminder fires after `ReminderTimer` is recompiled.
- **Ledger items routed to Story 8.4.** All three touch Lane A's Chat, so raise them with Lane A rather than editing its files:
  - Chat's ceiling of 4 iterations may be too low for a turn that lists reminders and then cancels several (DW-140).
  - The reminder command key is only `<ItemId>:<position>`, so a turn that is run again could get an earlier command's result (DW-141).
  - Chat's instructions still say "I can't run commands" and name no reminder ability, so a live model may refuse a reminder request (DW-142).
