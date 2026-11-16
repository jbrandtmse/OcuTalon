# Epic 24 Context: On-call, partner and check settings (step 5)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 5's Lane B features. An admin configures who is paged and through which channels, lists partner contacts and saves SQL query watches in Settings. Pages reach the on-call person on the channels that person chose, and the backup is woken only when nobody acknowledges in time. Every setting value OcuTalon shows has its secrets redacted, and the cards show each step-5 fix with its own dry run. Epic 36 already fixed the names, contracts, on-call section and texts. This epic builds on them without redefining them, in Lane B's files. Stories 24.2, 24.4a and 24.4b are done. Stories 24.3 and 24.5 remain.

## Stories

- Story 24.1: moved to Story 36.2 (step 5 contracts)
- Story 24.2: Set partner contacts in Settings (its SQL watch half moved to 24.5) (done)
- Story 24.3: Deliver pages on the on-call channel and stop escalation on acknowledgement
- Story 24.4a: Show setting values redacted everywhere, and the setting change in the evidence panel (done)
- Story 24.4b: Show the new fixes, partner warnings and the closed-card undo on the cards (done)
- Story 24.5: Set saved SQL query watches in Settings

## Requirements & Constraints

- **Paging:**
  - Each person is paged by Telegram, by email, or both (both by default). Telegram reaches only a user whose session has a paired chat at send time.
  - The backup is paged after `oncall.escalationMinutes` (15 by default). Any acknowledgement stops escalation, every copy then shows "Marked as handled at {time}", and a second acknowledgement changes nothing. IRIS Managed Alerts are never turned off.
  - A Telegram chat that is no longer paired gets nothing, and the page is reported to the paging owner as undelivered with a plain reason.
- **SQL query watches:** an admin saves a named query with a schedule. The watch runs on that schedule and reports when the result changes. The list shows each watch's schedule, last run and last result, and each watch appears as a background check in the saving admin's status rail. Removing a watch stops the check, and it leaves the list and the rail within one live update. A refusal is a field error, and nothing is saved.
- **Settings:** admin-only (403 otherwise). On the online demo, step-5 sections are hidden and saves answer 409 `not_available` before the body is read. Changes apply within a minute and are audited.
- **Privacy:** no Telegram chat id or display name appears in any message, log or audit entry. No on-call value (user name or address) appears in a production message, a log line or a trace. Page `Slots` carry none.
- **Access and timing:** every copy updates within 5 s. The UI works by keyboard alone, every control has a label, and contrast meets WCAG 2.1 AA in both themes.

## Technical Decisions

- **Commands (AD-1):** every state change goes through `CommandsIn` with an origin. Neither command below is a tool verb.
  - `AckPage` (`Ref` = page Ref, `Channel` `web`/`phone`/`telegram`) is accepted from `web_user`, `web_admin` and `telegram`. It goes to `IncidentManager`, which answers `handled`, `already_handled` or `not_found`.
  - `SaveSqlWatch` (`Action` save/remove, `CheckRef`, `Name`, `Query` ≤4000, `IntervalMinutes`) is accepted from `web_admin` only and goes to `WatchOps`. It is refused from every other origin.
- **Paging owner (AD-15, Lane A, done in 23.4):**
  - `IncidentManager` owns `OcuTalon.Data.Page` (`Ref`, `IncidentRef`, `Role` oncall/backup, `Person` = user name or address, `Channels`, `SentAt`, `AcknowledgedAt`, `AcknowledgedChannel`, `EscalationRef`).
  - It sends the `page` Notification with `DecisionRef` = the page's `Ref`. The keys are `page.onCall`, `page.onCallAlone`, `page.backup` and so on.
  - An address-only person's Notification has `SessionRef` `instance`, which 24.3 routes to `EmailOut`.
  - On acknowledgement it sends one `handled` Notification per session that holds a copy.
- **Page route (AD-14, AD-32):**
  - `OcuTalon.Core.Rule.Notify` routes kind `page` only to the person's chosen channels. Until 24.3, a page takes the generic route.
  - Each `*Out` records its `Delivery` row with `DecisionRef` = the page's Ref. `Delivery.FindByRef(pageRef, channel, ownerRef)` finds each copy, so `Delivery` gets no new column. Each `*Out` edits its copy to `handled.marked`.
  - Only `*Out` operations render text, through the catalog, as plain text. `TelegramOut`'s delivery and its **Got it** button belong to Lane A (23.4).
- **EmailOut page send:**
  - It handles a `page` Notification only when its `DecisionRef` is a `Data.Page` row whose `Channels` include `email`.
  - It sends to exactly `oncall.primary.email` (Role `oncall`) or `oncall.backup.email` (Role `backup`), read at send time, and never to an address taken from the text or the slots.
  - At most one email goes out per page row, claimed by a `Delivery` row of channel `email`.
  - It answers `not_available` on the online demo and sends nowhere but the CI mock in tests. The email carries no acknowledgement.
- **Escalation timers (AD-5, AD-18):**
  - `SetReminder` and `Data.Reminder` gain `Kind` (`escalation`), `IncidentRef` and `PageRef`.
  - `ReminderOps` accepts an escalation only from origin `system`, with `DelaySeconds`. The row has `SessionRef` `instance` and never appears in `ListReminders` or a live event. `CancelReminder` from `system` removes it.
  - At the due time, `ReminderTimer` and `Schedule.Reminder.Wake` send `OcuTalon.Msg.Escalation` to `IncidentManager` asynchronously instead of a Notification. The reconciler re-arms it, and a timer that fell due during downtime fires right after the restart.
  - Until 24.3, `ReminderOps` answers any kind other than "" or `reminder` with `not_built`.
- **On-call keys (AD-19):** `oncall.{primary,backup}.{user,email,channels}` and `oncall.escalationMinutes`, read through `Setting.Get`. Channels is a comma list in the order `telegram,email`. `telegram` is valid only for a user whose session is paired.
- **SQL watches (AD-18, AD-1):**
  - `POST /api/v1/settings/sql-watches` submits `SaveSqlWatch` through `Commands.Submit` to `WatchOps`, not `SaveSettings`, and shows the synchronous result.
  - Each watch is a `BackgroundCheck` row of `Kind` `sql_query`, owned by the admin's session and scheduled by `IntervalMinutes`.
  - The query runs as `OcuTalonSqlReader` over a separate JDBC loopback, and its results are untrusted content.
  - The online demo never runs one.
- **Redaction (AD-16):** every display of a setting value passes `OcuTalon.Bridge.Redact.Text` on the server. There is no web redactor.
- **Lanes and tests (AD-29, AD-33):**
  - Lane B never edits Lane A's files.
  - Tests go in `OcuTalon.Test.Schedule` and `OcuTalon.Test.Channel`, with Playwright specs under `web/e2e/` and a mock mail server.
  - A runner without a bot uses the CI Telegram mock.

## UX & Interaction Patterns

- **Settings texts:** On call, Partner contacts and SQL query watches use the Message Catalog's Settings (step 5) texts verbatim.
  - SQL keys: `settings.sqlSection`, `sqlHelp` ("OcuTalon runs each query on its schedule and tells you when the result changes."), `sqlName`, `sqlQuery` ("Query (one SELECT statement)"), `sqlMinutes`, `sqlSave`, `sqlRemove`, `sqlColumns` (Schedule / Last run / Last result), `sqlBadName` and `sqlOffOnDemo`.
  - The help may claim "read-only" only after 23.8's test proves the reader user is refused writes and DDL.
- **Saving:** each section saves on its own and confirms "Saved. Applies within a minute. Recorded in the audit log." Leaving with unsaved changes asks first.
- **Got it and handled pages:** **Got it** on the web card or the phone marks a page handled, and every copy reads "Marked as handled at {time}".
  - Someone paged by email can't press Got it, so the backup is also paged after the configured minutes.
  - A page raises no approval.

## Cross-Story Dependencies

- Builds on Epic 36 (done): 36.1's paging contract and payload fields, 36.2's verbs, keys and routes, and 36.4's On call section.
- **Story 24.3:**
  - It needs Epic 21's `EmailOut`, whose stories are all done.
  - Lane A's paging owner, Story 23.4, is done, so test against the real `IncidentManager` or a fixture that sends the same message.
  - It must settle DW-1251, AD-14's page route. The ledger's recommended reading is that a user always gets the web chat copy plus the chosen channels, and that email-only means no Telegram copy. Amend the spine bullet to match.
- **Story 24.5:** it starts only after Lane A's Story 23.8, which makes `WatchOps` handle `SaveSqlWatch`, merges. 23.8 is still backlog.
- Step 5's release is checked by the Contest Planner's hands-on pass, with real keys and Telegram.
