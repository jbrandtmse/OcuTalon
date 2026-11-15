# Epic 24 Context: On-call, partner and check settings (step 5)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 5's Lane B features. An admin lists the partner contacts and saves SQL query watches in Settings. Pages reach the on-call person on the channels that person chose, and the backup is paged only when nobody acknowledges in time. The cards show each new step-5 fix with its own dry run, a partner warning's exact text and recipients, and a setting-change cause. Epic 36 (36.1, 36.2, 36.4) fixed the names, contracts and texts; this epic builds on them without redefining them, in Lane B's files only.

## Stories

- Story 24.1: moved to Story 36.2 (step 5 contracts)
- Story 24.2: Set partner contacts and saved SQL query watches in Settings
- Story 24.3: Deliver pages on the on-call channel and stop escalation on acknowledgement
- Story 24.4: Show the new fixes, partner warnings and setting changes on the cards

## Requirements & Constraints

- **On call:** each person is paged by Telegram, by email, or both (both by default). Telegram is used only for a user with a paired chat. The backup is paged after the configured minutes (15 by default). An acknowledgement from any channel stops escalation. IRIS Managed Alerts are never turned off. (FR-28)
- **Partner warnings** go only to admin-configured contacts, and only after approval. The approver sees the exact text and every recipient first. (FR-29)
- **SQL query watch:** runs an admin-saved query as a read-only SQL user and reports when the result changes. Every check shows its schedule, last run and last result. (FR-33)
- **Settings changes** apply within a minute with no restart and are admin-only. Each change gets an IRIS audit entry with time, user and session. No secret or Telegram identity appears in it. (FR-17, FR-9)
- **Timing:** the page updates within 2 s, and other channels show an approval's result within 5 s. (NFR-9)
- **Accessibility:** keyboard alone, every control labelled, WCAG 2.1 AA contrast in both themes. (NFR-25)
- **Online demo:** none of the step-5 sections is offered.
  - Non-admins get 403, and any save answers 409 `not_available`.
  - The sections are absent from `GET /api/v1/settings`, and nothing is written to the partner-contact table.

## Technical Decisions

- **Command path (AD-1):** every state change is a production message submitted through `OcuTalon.Core.Commands.Submit`/`CommandsIn` with an origin. REST code writes no domain tables.
  - `SaveSqlWatch` (`Action` save/remove, `CheckRef`, `Name`, `Query` ≤4000 characters, `IntervalMinutes`) is accepted from `web_admin` only and goes to `WatchOps`.
  - `AckPage` (`Ref`, `Channel` web/phone/telegram) is accepted from `web_user`, `web_admin` and `telegram` and goes to `IncidentManager`.
  - Neither is a tool verb; until Lane A's owners answer them both return `failed` (use fixtures).
- **SecretHandoff (AD-1, AD-19; DW-1254):** partner-contact names and addresses travel the way the on-call body does.
  - The route `Put`s the body into `SecretHandoff`, which keeps it in memory and gives it out once.
  - `SaveSettings.Changes` holds only `{"handoff":"secret://handoff/<name>"}`.
  - Refusals name fields, never values. The from/to values appear only in the IRIS audit entry, and Story 24.2 adds a leak-scan test that pins this.
- **Routes (AD-19, AD-13):** both are admin-only through `OnPreDispatch`.
  - `POST /api/v1/settings/partner-contacts` (kind `contacts`) goes to its own saver in `SettingsOps`.
  - `POST /api/v1/settings/sql-watches` submits `SaveSqlWatch`, not `SaveSettings`.
  - The on-call keys (`oncall.{primary,backup}.{user,email,channels}`, `oncall.escalationMinutes` 1–1440) are read through `Setting.Get`.
- **Partner-contact table (AD-33):** `^OcuTalonP.PartnerContact` holds `Ref`, `Name` (128), `Email` (254), `Productions` (a JSON array of namespace and production), `CreatedAt` and `UpdatedAt` (UTC).
  - Lane B owns it. Only `SettingsOps` writes it, and readers use `PartnerContact.ForProduction(ns, production)`.
  - No purge; removing a contact deletes its row. It is not Lane A's demo fixture `Fix.PartnerContacts`.
- **SQL watch rows (AD-18):** each watch is a `BackgroundCheck` row with `Kind` `sql_query`, owned by the admin's session. It runs as `OcuTalonSqlReader` over a separate xDBC loopback connection. Story 23.8 owns the run and the query and result-hash columns.
- **Page route (AD-14, AD-32):**
  - The notification kind is `page`. In `Notify` it goes only to the chosen channels: the paired Telegram chat through `TelegramOut` (Story 23.4 delivers it) and/or `EmailOut`. Someone with no paired chat, or given only as an address, is paged by email only.
  - `DecisionRef` holds the page's `Ref`. Each `*Out` records it on its `Delivery` row, and `Delivery.FindByRef(pageRef, channel, ownerRef)` finds each copy.
  - On acknowledgement, every copy receives one `handled` notification and shows `handled.marked`.
  - `EmailOut` sends a page only if its `Data.Page` row's `Channels` include `email`, only to that `Role`'s on-call address, once per page. Text: catalog keys `page.onCall|onCallEmail|backup|backupEmail|subject`, plain text.
- **Paging owner (AD-15):** `IncidentManager` with `Data.Page` (Lane A, Story 23.4). **Email never acknowledges, and a reply never counts.** Acknowledgement is **Got it** on the web card or in the paired Telegram chat.
- **Escalation timers (AD-18, AD-5):**
  - `SetReminder` gains `Kind` (`escalation`), `IncidentRef` and `PageRef`.
  - `ReminderOps` accepts an escalation only from origin `system` and stores it with `SessionRef` `instance`. It is hidden from `ListReminders` and live events, and `CancelReminder` from `system` removes it.
  - When due, `ReminderTimer` sends `OcuTalon.Msg.Escalation` to `IncidentManager` asynchronously. The reconciler re-arms timers after a restart, and an overdue one fires at once. `Data.Reminder` appends `Kind`, `IncidentRef` and `PageRef`.
- **Dry runs and payloads (AD-16, AD-12):** no new approval fields.
  - Rollback: `Item`, `Field`, `Before`, `After`.
  - Suspend and resume: `Item`, `Before`, `After`.
  - Reroute: `From`, `To`, `Example`.
  - Partner warning: `Notice`, `Recipients`, `Simulated`.
  - The incident payload adds `SettingChange`, `GapMinutes` and `Page`. TypeScript interfaces come from `OcuTalon.Live.Payload` through `web/scripts/payloads.mjs --check`.
- **Ownership (AD-29, AD-33, AD-17, AD-4):**
  - Lane B owns the `page` kind and its route, the escalation kind, `AckPage`, `SaveSqlWatch`, the on-call keys, the partner-contact table and `Msg.Escalation`.
  - Lane A's `WatchOps`, `IncidentManager` and `TelegramOut` are not edited here. `Bridge.Audit` is the only audit writer, and no Telegram chat id or display name goes into any message, log or audit entry.

## UX & Interaction Patterns

- **Accepted texts:** use only the accepted texts in EXPERIENCE.md › Message Catalog › Settings (step 5), in `web/src/app/settings/settings-view.ts`.
  - The `settings.partner*`, `settings.sqlSection`/`settings.sql*` and `settings.badEmail` keys, plus the step-2 save, confirm, unsaved-changes and "Check every" texts.
  - Tests pin both halves of `settings.partnersHelp`: warnings go only to the listed people, and only after each one is approved.
  - The SQL user may not be described as read-only until Story 23.8 proves it is refused INSERT, UPDATE, DELETE and DDL.
- **Field errors (UX-DR36):** `field-error` sits under its field and is linked by `aria-describedby`. On submit, focus moves to the first error and nothing is saved.
- **Status rail (UX-DR53):** saved watches appear as background-check rows in the admin's rail.
- **Labels (UX-DR130):** every control is labelled, and icon buttons name both the action and its object.
- **Cards (UX-DR146):**
  - Each new fix kind uses the approval card with its own dry run. A rollback shows "Before"/"After" rows in `mono`. While pending, the card shows "Nothing has changed yet."
  - A partner warning shows its full text and every recipient before **Approve**/**Reject**. On the demo the recipients are simulated.
  - A setting-change cause adds "The feed broke four minutes after this setting changed." with the live gap.

## Cross-Story Dependencies

- **Prerequisites:** Epic 36 is merged (contracts, keys, verbs, table, the on-call section from 36.4, payload fields). Story 24.3 also needs Epic 21 (`EmailOut`, the mock mail server).
- **Fixtures stand in for Lane A's work until it merges:**
  - Story 23.8 (`WatchOps`), for 24.2.
  - Story 23.4 (the paging owner, `Data.Page` and Telegram **Got it**), for 24.3.
  - Stories 23.2, 23.3 and 23.5 (the new fix and partner-warning requests), for 24.4.
- **Partner contacts:** they are the only recipients Lane A's Story 23.5 may use.
- **Telegram:** without a bot, use the CI Telegram mock. A real bot is used only in the Contest Planner's hands-on release pass (REL-7).
- **Open points:**
  - DW-1251: AD-14 also lists the user's web chat as a page channel, but on-call settings offer only Telegram and email.
  - Story 24.3's acceptance criterion offers an email reply as an acknowledgement path, but AD-15 forbids it. Follow the spine.
