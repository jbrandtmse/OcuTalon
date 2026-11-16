# Epic 24 Context: On-call, partner and check settings (step 5)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 5's Lane B features. An admin lists partner contacts and saves SQL query watches in Settings. Pages reach the on-call person on the channels that person chose, and the backup is paged only when nobody acknowledges in time. Every setting value OcuTalon shows has its secrets redacted, and the cards show each step-5 fix with its own dry run, a partner warning's exact text and recipients, a setting-change cause, and a rollback's undo even on a closed incident. Epic 36 (Stories 36.1, 36.2 and 36.4) already fixed the names, contracts, on-call section and texts. This epic builds on them without redefining them and works in Lane B's files, apart from the redaction edits granted to 24.4a.

## Stories

- Story 24.1: moved to Story 36.2 (step 5 contracts)
- Story 24.2: Set partner contacts in Settings (its SQL watch half moved to 24.5)
- Story 24.3: Deliver pages on the on-call channel and stop escalation on acknowledgement
- Story 24.4a: Show setting values redacted everywhere, and the setting change in the evidence panel
- Story 24.4b: Show the new fixes, partner warnings and the closed-card undo on the cards
- Story 24.5: Set saved SQL query watches in Settings

## Requirements & Constraints

- **Paging:**
  - A person is paged by Telegram, by email, or both (both by default). Telegram reaches only a user whose session has a paired chat. A person without one, or one given only as an email address, is paged by email.
  - The backup is paged after the configured minutes (15 by default). Any acknowledgement stops escalation, and a second one changes nothing. IRIS Managed Alerts are never turned off.
- **Partner warnings** go only to contacts an admin configured, and only after approval. The approver sees the exact text and every recipient first.
- **SQL query watch:** runs a query an admin saved, on its schedule, and reports when the result changes. Each check shows its schedule, last run and last result, and appears in the saving admin's status rail. Removal stops the check and drops it from the list and rail within one live update. The help text may claim "read-only" only after Story 23.8 proves the reader user is refused writes and DDL.
- **Settings:** changes apply within a minute and are admin-only (non-admins get 403). An invalid field is a field error, and nothing is saved. Every change is audited.
- **Online demo:** none of the step-5 Settings sections is offered. The page hides them, and saves answer 409 `not_available` before the body is read. Of the step-5 fixes, only reroute is offered there.
- **Redaction:** a secret in a setting's before, after, old or new value (for example a URL with a token) never reaches a card, the phone, Telegram, a notice or the trace. A plain value shows unchanged.
- **Timing and access:** every copy of a request updates within 5 s. The web app works by keyboard alone, every control has a label, and contrast meets WCAG 2.1 AA in both themes.
- **Privacy:** no Telegram chat id or display name appears in any message, log or audit entry. No contact value appears in a command, result, log or trace.

## Technical Decisions

- **Command path (AD-1):** every state change is a production message submitted through `CommandsIn` with an origin. Neither command below is a tool verb.
  - `AckPage` (`Ref`, `Channel` web/phone/telegram) is accepted from `web_user`, `web_admin` and `telegram` and goes to `IncidentManager`.
  - `SaveSqlWatch` (`Action` save/remove, `CheckRef`, `Name`, `Query` ≤4000, `IntervalMinutes`) is accepted from `web_admin` only and goes to `WatchOps`.
- **Contact data and audit (AD-1, AD-17, AD-19):**
  - Partner-contact values travel through `OcuTalon.Core.SecretHandoff`, in memory only and taken once, as the on-call section's do. The traced message holds only the handoff uri.
  - A partner contact's audit entry names only `partnerContact.<Ref>` and which fields changed, never a value. A leak-scan test covers the audit rows.
- **Partner-contact table (AD-33):** Lane B's `^OcuTalonP.PartnerContact` (`Ref`, `Name` ≤128, `Email` ≤254, `Productions` as a JSON array, UTC timestamps).
  - Only `SettingsOps` writes it, and nothing is written on the online demo.
  - The outside reader is `PartnerContact.ForProduction(namespace, production)`.
  - The section shows only while Lane A's `Fix.PartnerContacts` has `TABLE = 1`.
  - `POST /api/v1/settings/partner-contacts` answers 200, 400, 403, 409 or 500.
- **SQL watches (AD-18):**
  - `POST /api/v1/settings/sql-watches` submits `SaveSqlWatch` to `WatchOps`, not `SaveSettings`, and shows the synchronous result. A refusal shows as a field error.
  - The row is `Kind` `sql_query`, owned by the admin's session. It runs as `OcuTalonSqlReader` over a separate loopback connection, and its results are untrusted content. On the online demo no `sql_query` row runs.
- **Page route (AD-14, AD-32):**
  - Kind `page`, routed by `OcuTalon.Core.Rule.Notify`, goes only to the person's chosen channels. AD-14 lists those as the user's web chat, the paired Telegram chat (`TelegramOut`; its delivery and **Got it** are Lane A's Story 23.4) and `EmailOut`.
  - The `DecisionRef` is the page's `Ref`. `Delivery.FindByRef` finds each copy, so no new column is needed.
  - On acknowledgement the paging owner sends one `handled` Notification per session holding a copy, and each `*Out` edits its copy to `handled.marked`.
  - A chat that is no longer paired gets nothing, and the page is reported to the owner as undelivered with a plain reason.
  - Only `*Out` operations render text, through `Catalog.Render`.
- **EmailOut's page send:** only for a `Data.Page` row whose `Channels` include `email`. It goes to exactly `oncall.primary.email` or `oncall.backup.email` for the page's Role, read at send time. At most one email is sent per page, claimed by a `Delivery` row. It answers `not_available` on the online demo and uses only the CI mock in tests.
- **Email acknowledgement:** per AD-15, an email page carries no acknowledgement, and a reply never counts, because email is untrusted. This conflicts with Story 24.3's example of a reply to the page email; DW-1251 tracks settling AD-14's page route.
- **Paging owner (AD-15):** Lane A's `IncidentManager` owns `OcuTalon.Data.Page` (`Role`, `Person`, `Channels`, `AcknowledgedAt`/`AcknowledgedChannel`, `EscalationRef`). The on-call keys are `oncall.{primary,backup}.{user,email,channels}` and `oncall.escalationMinutes`, read through `Setting.Get`.
- **Escalation timers (AD-5, AD-18):**
  - `SetReminder` and `Data.Reminder` gain `Kind` (`escalation`), `IncidentRef` and `PageRef`.
  - `ReminderOps` accepts an escalation only from origin `system`, with `DelaySeconds`. It uses `SessionRef` `instance` and never appears in `ListReminders` or a live event. `CancelReminder` from `system` removes it.
  - At the due time `ReminderTimer` sends `OcuTalon.Msg.Escalation` to `IncidentManager` asynchronously. The reconciler re-arms it, and a timer that fell due during downtime fires right after the restart.
- **Redaction (AD-16, AD-19):**
  - `OcuTalon.Bridge.Redact.Text` runs on the server for every display of a setting value: Approval and Incident payloads and the setting notices' slots. There is no web redactor. `Redact.Text` also catches a bare `key=`.
  - `Fix.Executor` offers the raw before/after to `SecretHandoff`. It sends `DryRunResult` with redacted values plus the handoff reference.
  - `IncidentManager` takes the entry before any early exit and stores the raw values in `ApprovalRequest.DryRun`. A detached job discards an untaken entry after 60 s. If the entry is missing, the dry run is refused with `NOSTART`.
  - The stored dry run and the value a rollback writes stay raw, so a rollback or undo restores the value byte for byte.
- **Cards (AD-12, AD-16):**
  - No new approval fields. The dry runs use: rollback `Item`/`Field`/`Before`/`After`; suspend and resume `Item`/`Before`/`After`; reroute `From`/`To`/`Example`; partner warning `Notice`/`Recipients`/`Simulated`.
  - The incident payload adds `SettingChange` {item, target, setting, oldValue, newValue, credential, detectedAt}, `GapMinutes` and `Page` {state, pagedAt, acknowledgedAt, channel}.
  - The TypeScript interfaces must match `OcuTalon.Live.Payload`. A page raises no approval.
- **Setting changes and rollback (AD-15, AD-16):**
  - The evidence pack holds at most 10 changes, values cut at 500 characters, credential values blank and no author. The gap sentence is code-written (`incident.settingChangeCause`).
  - `undo_rollback` moves no state and may be asked on a closed incident. An undo is offered once, only while the rollback is the setting's latest change, and cannot itself be undone.
- **Lanes and tests (AD-29, AD-33):**
  - Lane B never edits Lane A's files, except 24.4a's granted redaction edits. Use fixtures for Lane A producers until they merge.
  - Tests go in `OcuTalon.Test.Schedule` and `OcuTalon.Test.Channel`, with Playwright specs under `web/e2e/`. Runners without a bot use the CI Telegram mock.

## UX & Interaction Patterns

- **Settings texts:** the partner-contact and SQL-watch texts come verbatim from the Message Catalog's Settings (step 5) list. Tests pin both halves of `settings.partnersHelp`: warnings go only to the people listed, and only after each is approved. Removing a contact asks to confirm, naming the contact and address.
- **Fix approval cards:** reroute, suspend, resume and rollback use the approval request card with their own dry run.
  - Before and After are text-labelled rows in `mono`, and "Nothing has changed yet." shows while the request is pending.
  - Button names include the action and its object. The phone and Telegram show the same catalog text as plain text, with inline **Approve** and **Reject**.
- **Partner warning card:** the exact text and every recipient appear in full before the buttons. On the demo the recipients are simulated contacts.
- **Setting-change cause:** the cause line adds the live gap sentence ("The feed broke four minutes after this setting changed."). The evidence panel lists the item, setting, old and new values (redacted), and time.
- **Answered statuses:**
  - "Approved from {channel} at {time}", "Rejected from {channel} at {time}. Nothing was changed.", "Expired at {time}. Nothing was changed.", and "Recorded in the IRIS audit log." after every result.
  - An undo arrives as its own approval request card in the same incident.
  - A closed incident card draws only a rollback's undo request card asked after the close, never another kind. The rail's "Show in the chat" jumps to that card.
  - A handled page shows "Marked as handled at {time}". Someone paged by email can't press Got it, so the backup is also paged after the configured minutes.

## Cross-Story Dependencies

- Builds on Epic 36: Story 36.1's paging contract and payload fields, Story 36.2's verbs, keys, tables and routes, and Story 36.4's on-call section and SecretHandoff pattern.
- Stories 24.2 and 24.4a are done. 24.2's section appears only after Lane A's Story 23.13 sets `TABLE = 1`.
- Story 24.3 needs Epic 21 (`EmailOut`). Its paging owner and Telegram **Got it** are Lane A's Story 23.4; use a fixture paging owner until 23.4 merges.
- Story 24.4b follows 24.4a. It uses fixture requests until Lane A's Stories 23.2 and 23.3 (fixes, rollback) and 23.5 (partner warning) merge.
- Story 24.5 starts only after Lane A's Story 23.8 (`WatchOps` handles `SaveSqlWatch`) merges.
- Step 5's release is checked by the Contest Planner's hands-on pass.
