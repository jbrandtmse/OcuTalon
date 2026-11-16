# Epic 24 Context: On-call, partner and check settings (step 5)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 5's Lane B features. An admin lists partner contacts and saves SQL query watches in Settings. Pages reach the on-call person on the channels that person chose, and the backup is paged only when nobody acknowledges in time. The cards show each new step-5 fix with its own dry run, a partner warning's exact text and recipients, and a setting-change cause. Epic 36 (Stories 36.1, 36.2 and 36.4) already fixed the names, contracts, on-call section and texts. This epic builds on them without redefining them and edits only Lane B's files.

## Stories

- Story 24.1: moved to Story 36.2 (step 5 contracts)
- Story 24.2: Set partner contacts in Settings (its SQL watch half was split off to 24.5)
- Story 24.3: Deliver pages on the on-call channel and stop escalation on acknowledgement
- Story 24.4: Show the new fixes, partner warnings and setting changes on the cards
- Story 24.5: Set saved SQL query watches in Settings

## Requirements & Constraints

- **Paging:** a person is paged by Telegram, by email, or both (both by default). Telegram works only for a user whose session has a paired chat. A person without one, or a person given only as an email address, is paged by email. The backup is paged after the configured minutes (15 by default). Any acknowledgement stops escalation. IRIS Managed Alerts are never turned off.
- **Partner warnings** go only to contacts an admin configured, and only after approval. The approver sees the exact text and every recipient first.
- **SQL query watch:** runs a query an admin saved, on its schedule, and reports when the result changes. Each check shows its schedule, last run and last result, and appears in the saving admin's status rail. The help text may claim "read-only" only after Story 23.8 proves the reader user is refused writes and DDL.
- **Settings:**
  - Changes apply within a minute with no restart and are admin-only. Non-admins get 403 `not_admin`.
  - An invalid field is a field error, and nothing is saved.
  - Every change gets an IRIS audit entry.
- **Online demo:** none of the step-5 Settings sections is offered.
  - The page hides them, and saves answer 409 `not_available` before the body is read.
  - They are absent from `GET /api/v1/settings`.
- **Timing and access:** the web page updates within 2 s, and other channels show an approval's answer or result within 5 s. The web app works by keyboard alone, every control has a label, and contrast meets WCAG 2.1 AA in both themes.
- **Privacy:** no Telegram chat id or display name appears in any message, log or audit entry. No contact value appears in a command, result, log or trace.

## Technical Decisions

- **Command path (AD-1):** every state change is a production message submitted through `CommandsIn` with an origin. `AckPage` (`Ref`, `Channel`) is accepted from `web_user`, `web_admin` and `telegram` and goes to `IncidentManager`. `SaveSqlWatch` (`Action` save/remove, `CheckRef`, `Name`, `Query` ≤4000, `IntervalMinutes`) is accepted from `web_admin` only and goes to `WatchOps`. Neither is a tool verb.
- **Secrets and contact data (AD-1, AD-19):**
  - Partner-contact names and addresses travel through `OcuTalon.Core.SecretHandoff`, in memory only and taken once, as the on-call section's values do. `SaveSettings.Changes` holds only `{"handoff": uri}`.
  - Audit entries for partner contacts name only `partnerContact.<Ref>` and which fields changed, never a value. A leak-scan test pins this.
- **Partner-contact table:** Lane B's `^OcuTalonP.PartnerContact` (`Ref`, `Name` ≤128, `Email` ≤254, `Productions` as a JSON array, timestamps).
  - Only `SettingsOps` writes it. It is configuration with no purge.
  - The outside reader is `PartnerContact.ForProduction(namespace, production)`.
  - The Settings section shows only while Lane A's `Fix.PartnerContacts` has `TABLE = 1` (Story 23.13).
  - `POST /api/v1/settings/partner-contacts` answers 200, 400, 403, 409 or 500.
- **SQL watches route:** `POST /api/v1/settings/sql-watches` submits `SaveSqlWatch` to `WatchOps`, not `SaveSettings`, and shows the synchronous result. A refusal is shown as a field error. The row is `Kind` `sql_query` and is owned by the admin's session. It runs as the IRIS user `OcuTalonSqlReader` over a separate loopback connection (AD-18).
- **Page route (AD-14, AD-32):**
  - Notification kind `page`, routed by `OcuTalon.Core.Rule.Notify`, goes only to the paged person's chosen channels. The spine lists those as the user's web chat, the paired Telegram chat (`TelegramOut`; delivery and **Got it** are Lane A's Story 23.4) and `EmailOut`.
  - The `DecisionRef` is the page's `Ref`. `Delivery.FindByRef` finds each copy, so no new column is needed.
  - On acknowledgement the paging owner sends one `handled` Notification per session holding a copy. Each `*Out` edits its copy to `handled.marked`.
  - A chat that is no longer paired gets nothing. The page is reported to the owner as undelivered, with a plain reason.
  - Producers never render text. Only `*Out` operations render, through `Catalog.Render`.
- **EmailOut's page send:** only for a `Data.Page` row whose `Channels` include `email`. It goes to exactly the on-call key's address for the page's Role (`oncall.primary.email` or `oncall.backup.email`), read at send time. At most one email goes per page, claimed by a `Delivery` row. It answers `not_available` on the online demo and uses only the CI mock in tests.
- **Acknowledgement:** per the spine, an email page carries no acknowledgement, and a reply never counts, because email is untrusted. This conflicts with the story's example of acknowledging by email reply; DW-1251 tracks settling AD-14's route.
- **Paging owner and table:** `IncidentManager` (Lane A) owns `OcuTalon.Data.Page` (`Role` oncall/backup, `Person` as a user name or address, `Channels`, `AcknowledgedAt`/`Channel`, `EscalationRef`). The on-call keys are `oncall.{primary,backup}.{user,email,channels}` and `oncall.escalationMinutes` (1 to 1440), read through `Setting.Get`.
- **Escalation timers (AD-5, AD-18):**
  - `SetReminder` gains `Kind` (`escalation`), `IncidentRef` and `PageRef`. `Data.Reminder` adds the same columns.
  - `ReminderOps` accepts an escalation only from origin `system`, with `DelaySeconds`. It uses `SessionRef` `instance` and never appears in `ListReminders` or a live event. `CancelReminder` from `system` removes it.
  - At the due time `ReminderTimer` sends `OcuTalon.Msg.Escalation` (`IncidentRef`, `PageRef`) to `IncidentManager` asynchronously. The startup reconciler re-arms it, and a timer that fell due during downtime fires right after the restart.
- **Cards (AD-12, AD-16):**
  - There are no new approval fields. The dry runs use: rollback `Item`/`Field`/`Before`/`After`; suspend and resume `Item`/`Before`/`After`; reroute `From`/`To`/`Example`; partner warning `Notice`/`Recipients`/`Simulated`.
  - The incident payload adds `SettingChange` {item, target, setting, oldValue, newValue, credential, detectedAt}, `GapMinutes` and `Page` {state, pagedAt, acknowledgedAt, channel}.
  - The TypeScript interfaces must match `OcuTalon.Live.Payload`. A page raises no approval.
- **Lanes and ownership (AD-29, AD-33):** Lane B never edits Lane A's files. Use fixtures for Lane A producers until they merge. Tests go in `OcuTalon.Test.Schedule` and `OcuTalon.Test.Channel`, with Playwright specs under `web/e2e/`. Runners without a bot use the CI Telegram mock.

## UX & Interaction Patterns

- **Settings texts:** the on-call, partner-contact and SQL-watch texts come from the Message Catalog's Settings (step 5) list, verbatim. Tests must pin both halves of `settings.partnersHelp`: warnings go only to the people listed, and only after each is approved. Removing a contact asks to confirm, with its name and address.
- **Fix approval cards:** reroute, suspend, resume and rollback use the approval request card with their own dry run block. Before and After are text-labelled rows in `mono`, and "Nothing has changed yet." shows while the request is pending. Button names include the action and its object. The phone and Telegram show the same catalog text as plain text, with inline **Approve** and **Reject**.
- **Partner warning card:** the exact text and every recipient appear in full before the buttons. On the demo the recipients are simulated contacts.
- **Setting-change cause:** the cause line adds the live gap sentence ("The feed broke four minutes after this setting changed."). The evidence panel lists the item, setting, old and new values, and time.
- **Answered statuses:** "Approved from {channel} at {time}", "Rejected … Nothing was changed.", "Expired … Nothing was changed.", and "Recorded in the IRIS audit log." after every result. An undo arrives as its own approval card in the same incident. A handled page shows "Marked as handled at {time}".

## Cross-Story Dependencies

- Builds on Epic 36: Story 36.1's paging contract and payload fields, Story 36.2's verbs, keys, tables and routes, and Story 36.4's on-call section and SecretHandoff pattern.
- Story 24.2's section appears only after Lane A's Story 23.13 sets `TABLE = 1`.
- Story 24.3 needs Epic 21 (`EmailOut`). Its paging owner and Telegram **Got it** are Lane A's Story 23.4; use a fixture paging owner until 23.4 merges.
- Story 24.4 uses fixture requests until Lane A's Stories 23.2, 23.3 (fixes and setting change) and 23.5 (partner warning) merge.
- Story 24.5 starts only after Lane A's Story 23.8 (`WatchOps` handles `SaveSqlWatch`) merges.
- Epic 25's settings work follows this epic.
