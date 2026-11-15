# Epic 23 Context: Deeper IRIS watch (step 5)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Incidents get more governed fixes and better cause-finding: suspend, resume, reroute and setting rollback as approved fixes; failures linked to recent setting changes; the on-call person paged, with escalation to a backup; partner notices sent only after approval; and a code-written summary when every incident closes. Queue backlog and saved SQL query watches report between digests (Could). Nearly all of it has shipped, Story 23.3 (setting-change cause and rollback) included. Two stories are left, both built on Epic 36's step 5 contracts, which have merged. Story 23.4 pages and escalates. Story 23.8 runs a saved SQL query as a read-only SQL user. On an online-demo install, paging, escalation and saved SQL watches never page anyone and never show real people's data. They stay off or read-only there, and a test pins that.

## Stories

- Story 23.2: Suspend, resume and reroute with a dry run (done)
- Story 23.3: Name the setting change behind an incident and offer its rollback (done)
- Story 23.4: Decide when to page the on-call person and when to escalate to the backup
- Story 23.5: Draft partner delay notices that are sent only after approval (done)
- Story 23.6: Write an incident summary when an incident closes (done)
- Story 23.7: Watch queue backlogs between digests (done)
- Story 23.8: Watch a saved SQL query as a read-only SQL user
- Story 23.9: Resume a suspended item after its incident closes (done)
- Story 23.10: Partner notice and summary polish from the 1.0.7 demo pass (done)
- Story 23.11: Say in a partner notice only how the incident ended (done)
- Story 23.12: Take a rejected request off the status rail at once (done)

## Requirements & Constraints

- **Paging (23.4):**
  - An incident's notice, a fallback notice included, pages the on-call person once: one page row and one page notification, however many sessions watch the production.
  - A page needs no approval. It is audited as an action with its target and result. No Telegram chat id or display name goes into any message, log or audit entry.
  - If nobody acknowledges within `oncall.escalationMinutes` (default 15), the backup is paged the same way. The backup's page never escalates.
  - Any acknowledgement stops escalation at once. The page row records when it came and from which channel, and the timer is cancelled. A later acknowledgement changes nothing.
  - When the incident closes before the timer is due, the timer is cancelled. An escalation message that still arrives changes nothing.
  - After any number of restarts, the backup is paged only while the page is unacknowledged and the incident open. Each person is paged at most once per incident.
  - IRIS Managed Alerts keep working. A test finds every alert setting unchanged and an alert still reaching Managed Alerts. No OcuTalon class writes alert configuration.
  - With no on-call person configured, which is always the case on the online demo, nothing is paged and nothing else changes.
  - Tests cover the page, escalation, acknowledgement (a Telegram **Got it** press through the CI mock among them), a close before escalation, and a repeated escalation after a restart.
- **SQL query watch (23.8):**
  - The installer creates the reader user. It has no OcuTalon role and nothing beyond the SQL `SELECT` an admin grants. The security overview lists the user and what it can and can't do.
  - A save accepts a single `SELECT` only, and runs it once as the reader to confirm it works. Any other statement, or one the reader can't run, is refused with a plain reason, and nothing is saved.
  - Due runs go over a separate connection as the reader, never as the production's user. Each run compares a hash of the result with the last run's. The first run sets the baseline with no finding. A changed result is one finding Item, whose content is untrusted and cut to a fixed size, saying so when cut. A failed run counts as not checked and gives its reason.
  - Tests change a stored query at the database level to INSERT, UPDATE, DELETE, DDL or an ungranted table. Each must fail with a privilege error, change no data, and leave the run not checked. The tool inventory still has no tool that runs data-changing SQL.
- **Online-demo safety (both stories):**
  - The online demo never has the on-call keys. The On call settings section answers 409 `not_available` there and is absent from the settings GET. So nothing is ever paged on the demo.
  - `EmailOut` answers `not_available` on the demo.
  - The SQL-watches route answers 409 `not_available` on the demo. `SaveSqlWatch` is accepted only from origin `web_admin`, and no demo visitor is ever an admin, on the page, in the chat or in a paired chat.
  - Each story pins its "off on the demo" behaviour with a test.
- **Texts:** every user-facing text comes from a catalog key the author accepted. Nothing ships text that hasn't been accepted.

## Technical Decisions

- **The paging owner is `IncidentManager`.** It is still the only class that moves incident state. 23.4 builds `OcuTalon.Data.Page`:
  - Columns: `Ref`, `IncidentRef`, `Role` (`oncall`/`backup`), `Person` (an OcuTalon user name or an email address, never a Telegram identity), `Channels`, `SentAt`, `AcknowledgedAt`, `AcknowledgedChannel` and `EscalationRef`.
  - The table commits its storage block. Its rows are purged with their incidents through the Watch area's `Purge(daysToKeep)` (default 90).
  - Page refs come from `NewRef()`.
- **On-call values** are read with `OcuTalon.Data.Setting.Get` from these keys:
  - `oncall.{primary,backup}.user`: a user name with an OcuTalon session, or "".
  - `oncall.{primary,backup}.email`: an address, or "".
  - `oncall.{primary,backup}.channels`: a comma list, default `telegram,email`.
  - `oncall.escalationMinutes`: 1 to 1440, default 15.
  - A role counts as configured when its user or its email is set.
  - The keys are written only by `SettingsOps`, from 36.4's On call section through `SecretHandoff`. Their values appear only in the IRIS audit log.
- **The page notification** has kind `page`, and its `DecisionRef` is the page's `Ref`. Each copy is found with `Delivery.FindByRef(pageRef, channel, ownerRef)`, so `Delivery` gets no new column. On acknowledgement, the owner sends one `handled` notification per session that holds a copy, and each `*Out` edits its copy to `handled.marked`.
- **The incident payload's `Page` field** is {`state` (`paged`/`acknowledged`/`escalated`), `pagedAt`, `acknowledgedAt`, `channel`}.
- **Acknowledgement:** `OcuTalon.Msg.Command.AckPage` (`Ref`, `Channel` `web`/`phone`/`telegram`) arrives through `CommandsIn` from `web_user`, `web_admin` and `telegram`.
  - It copies `GotIt`'s two properties and does not subclass it.
  - Telegram counts only a press from the paired chat that carries the button's unguessable reference.
  - Email never acknowledges, and a reply never counts. A person given only an address is therefore always escalated past.
  - Until 23.4 handles `AckPage`, `IncidentManager` answers it with error 5001.
- **Escalation:** the owner submits `SetReminder` with `Kind` `escalation`, `IncidentRef`, `PageRef` and `DelaySeconds`, from origin `system`, and cancels it with `CancelReminder` from `system`. When it falls due, `ReminderTimer` sends `OcuTalon.Msg.Escalation` (`IncidentRef`, `PageRef`) asynchronously, and the reconciler re-arms it after a restart. Until 24.3 merges, `ReminderOps` answers `not_built` for an escalation and stores nothing, so 23.4 tests against an escalation-timer fixture.
- **Telegram delivery is 23.4's.**
  - The page is plain text from the accepted key, with a **Got it** button. On acknowledgement from any channel, the message is edited in place to "Marked as handled at {time}" and the button is removed.
  - Until 24.3 merges, a page takes the generic `Notify` route, so tests send a fixture notification straight to `TelegramOut`.
- **Reusable from 23.3:**
  - The `minutes` slot type: "less than a minute", "one minute" through "nine minutes", then digits with a thousands separator.
  - The `cause` slot type: a code-written, catalog-rendered cause sentence shown in place of the model's sentence where a key's `{cause}` names a change.
  - The incident move rule: a `MOVES` 0 kind may be asked on a closed incident and never moves its state, and any other state move on a closed incident is refused.
- **SQL watch:**
  - The row is `Kind` `sql_query` in `OcuTalon.Data.BackgroundCheck`, owned by the admin's session and scheduled by `IntervalMinutes`. 23.8 appends the query and result-hash columns.
  - The reader user is `OcuTalonSqlReader`, over a separate xDBC loopback connection. How it connects and how its password is kept are measured and decided in 23.8, and are a veto item.
  - `SaveSqlWatch` (`Action` save/remove, `CheckRef`, `Name`, `Query` of at most 4,000 characters, `IntervalMinutes`) goes to `WatchOps`, which has no `MessageMap` entry for it yet. It is not a tool verb.
  - `Roles.Assign` refuses `OcuTalonSqlReader`, and the forbidden-privilege list still has only 23.3's one rollback exception.
- **Conventions:**
  - Tests go in `OcuTalon.Test.Watch` (23.4) and `OcuTalon.Test.Checks` (23.8). CI mock scenarios go under `ci/mock/scenarios/A/`.
  - Audit goes only through `OcuTalon.Bridge.Audit`.
  - Lane A never edits Lane B's contracts: the `page` kind and its route, the Reminder escalation kind, `AckPage`, `SaveSqlWatch`, the on-call keys, the partner-contact table and `Msg.Escalation`.

## UX & Interaction Patterns

- The Telegram page has no Markdown and no emoji, and the phone shows the same text. A second **Got it** press changes nothing.
- Settings › On call (36.4) shows "OcuTalon doesn't send pages yet…" until `OcuTalon.Data.Page` is compiled. 23.4 must add a test that this line disappears once the table exists.
- The SQL-watch help must not claim the query runs as a read-only user until 23.8's test proves the reader is refused INSERT, UPDATE, DELETE and DDL.

## Cross-Story Dependencies

- Stories 36.1 (spine names), 36.2 (keys, verbs, the escalation kind, `Msg.Escalation`, page key names) and 36.4 and 36.6 (the On call section) have merged.
- Lane B's 24.3 (page routing to Telegram and email, `ReminderTimer` escalation, the web and email acknowledgement paths) has not merged, so 23.4 works against fixtures. DW-1251, about which page route applies, is 24.3's to settle.
- Lane B's 24.2 (the SQL watches settings section) has not merged, so 23.8's test submits `SaveSqlWatch` itself.
- Story 23.8 also relies on Epic 14's security overview.
- Open DW item: DW-1277 belongs to 23.4.
- Gaps:
  - The page texts (`page.onCall`, `page.onCallEmail`, `page.backup`, `page.backupEmail`, `page.subject`) exist only as key names. They are not yet in the UX Message Catalog and must be proposed and accepted.
  - The planning docs don't say whether the online-demo install creates `OcuTalonSqlReader`, or whether `Checks` skips `sql_query` rows on the demo.
