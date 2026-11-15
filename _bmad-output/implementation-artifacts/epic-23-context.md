# Epic 23 Context: Deeper IRIS watch (step 5)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Incidents get more governed fixes and better cause-finding. The fixes are suspend, resume, reroute and setting rollback. Failures are linked to recent setting changes, the on-call person is paged with escalation to a backup, partner notices go out only after approval, and every incident closes with a summary written by code. Queue backlog and saved SQL query watches report between digests (Could). Most of this has shipped. The three stories left build on Epic 36's step 5 contracts, which have all merged: 23.3 (setting-change cause and rollback), 23.4 (paging and escalation) and 23.8 (a SQL query watch run as a read-only SQL user). On an online-demo install, paging, escalation and saved SQL watches never page anyone and never show real people's data. They are off or read-only there.

## Stories

- Story 23.2: Suspend, resume and reroute with a dry run (done)
- Story 23.3: Name the setting change behind an incident and offer its rollback
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

- **Setting-change cause (23.3):**
  - The evidence pack lists `SettingChange` rows from the 24 hours before the first failure, newest first, with credentials removed. It is cut to the pack's size limit and says so when cut.
  - No change from before the production's first snapshot is listed, and nothing ever says who made a change.
  - The notice names the change and gives the gap, computed by code in whole minutes ("The feed broke four minutes after this setting changed.").
  - The evaluation set gains at least two setting-change incidents, scored on every run.
- **Rollback (23.3):**
  - It has a dry run (Before is the current value, After is the value it restores) and runs only after approval.
  - Before running, the executor checks again that the current value still equals the change's new value. If it doesn't, the rollback is skipped and reported.
  - Undo is one approved action that restores the value the rollback replaced.
- **Paging (23.4):**
  - An incident's notice, a fallback notice included, pages the on-call person once. That means one page row and one page notification, however many sessions watch.
  - A page needs no approval, is audited with its target and result, and never puts a Telegram identity in a message, log or audit entry.
  - Escalation to the backup comes after the configured minutes (default 15), and the backup's page doesn't escalate further.
  - An acknowledgement from any channel stops escalation at once. A later acknowledgement changes nothing.
  - An incident that closes before the timer is due cancels it, and an escalation message that still arrives changes nothing.
  - Each person is paged at most once per incident, across any number of restarts (nothing is lost on restart).
  - IRIS Managed Alerts stay untouched, and no OcuTalon class writes alert configuration.
  - With no on-call person configured, nothing is paged.
- **SQL query watch (23.8):**
  - The installer creates the reader user with no OcuTalon role and nothing beyond the SQL `SELECT` an admin grants. The security overview lists the user and what it can and can't do.
  - A save accepts one `SELECT` only and runs it once as the reader to confirm it works. Any other statement, or one the reader can't run, is refused with a plain reason and nothing is saved.
  - Runs compare a hash of the result. The first run sets the baseline, a changed result becomes one finding Item, and a failed run counts as not checked and gives its reason.
  - Finding content is untrusted and cut to a fixed size, saying so when cut.
  - Tests prove that INSERT, UPDATE, DELETE, DDL and ungranted tables fail with a privilege error and change no data. The tool inventory still has no tool that runs data-changing SQL.
- **Online-demo safety:**
  - Setting history is off on the online demo, and `rollback_setting` is not granted there (ONLINESHARED).
  - The demo never has on-call keys, so it never pages. `EmailOut` answers `not_available`.
  - The on-call and SQL-watch settings routes answer 409 `not_available` there.
  - `SaveSqlWatch` is accepted only from `web_admin`, and no demo visitor is an admin.
- **Texts:** every user-facing text uses a catalog key, and no story ships a text the author hasn't accepted.

## Technical Decisions

- **Setting history (AD-15, built by 36.1):**
  - `OcuTalon.Watch.SettingHistory` is the only writer of `OcuTalon.Data.SettingSnapshot` and `SettingChange`. A `SettingChange` row has `Item`, `Target` (Host/Adapter), `Setting`, `OldValue`, `NewValue`, `Source` (production/default/class), `Credential` and `DetectedAt`.
  - `OldValue` and `NewValue` are cut at 2,000 characters with no marker, but the snapshot keeps the whole value. Rollback must allow for this.
  - A change row with `Credential` 1 has blank values and must never be offered for rollback. The secret hash never leaves `SettingSnapshot` (pinned by `Test.Watch.SettingSecret`).
  - A change's time is known only to within the check interval, and its author is never known.
- **`rollback_setting` (AD-16, AD-24; DW-1225 makes these 23.3's):**
  - Its parameter is `change` (a `SettingChange` `Ref`) from the pack's window, on the failing item, its adapter or the defaults that apply to it.
  - Resource `%Ens_ProductionConfig:W`, `ONLINEGRANT` 0. 23.3 grants it to `OcuTalonServiceRole`, and the online-demo install leaves the grant out.
  - 23.3 also adds the single forbidden-privilege test exception, the security overview's `ONLINESTATEMENT` change and overview sentence, and the installer composing the grant.
  - The fix runs from `FixExecutor`'s one namespace-switching method. The executor checks the grant first.
  - The `Ens.Config.*` classes check no resource, so a write likely needs WRITE on the target database, and System Default Setting writes may need `%Ens_SystemDefaultConfig`. This is an inference, and 23.3 measures it.
  - Dry run: the approval payload's existing `Item`, `Field`, `Before` and `After`, with no new field.
  - `result.settingRestored` keeps its undo sentence only if 23.3 builds and tests the undo.
- **Catalog keys (`Msg.Catalog.Watch`):**
  - 23.3: `incident.rollbackRequest`, `incident.settingChangeCause`, `result.settingRestored`, `result.settingChangedSince`, `summary.requestedRollback`, `summary.settingRestored`, and the reasons NOTALLOWED and ONLINESHARED.
  - Pages: `page.onCall`, `page.onCallEmail`, `page.backup`, `page.backupEmail` and `page.subject`.
  - Reused: `handled.marked`, `button.gotIt`, `result.*`, `summary.*`.
- **`incident` payload, step 5 fields:**
  - `SettingChange` {`item`, `target`, `setting`, `oldValue`, `newValue`, `credential`, `detectedAt`} and `GapMinutes` (23.3).
  - `Page` {`state` (paged/acknowledged/escalated), `pagedAt`, `acknowledgedAt`, `channel`} (23.4).
- **Paging (AD-15, AD-14, AD-18, AD-29):**
  - The paging owner is `IncidentManager`. 23.4 builds `OcuTalon.Data.Page` with `Ref`, `IncidentRef`, `Role` (oncall/backup), `Person` (a user name or an email address, never a Telegram identity), `Channels`, `SentAt`, `AcknowledgedAt`, `AcknowledgedChannel` and `EscalationRef`. The table commits its storage block and is purged with its incidents through the Watch area's `Purge(daysToKeep)`.
  - On-call values are read with `Setting.Get` from these keys: `oncall.{primary,backup}.{user,email,channels}` and `oncall.escalationMinutes` (1 to 1440, default 15). A role counts as configured when its user or its email is set.
  - The page notification has kind `page`, and its `DecisionRef` is the page's `Ref` (from `NewRef()`). Each copy is found with `Delivery.FindByRef(pageRef, channel, ownerRef)`.
  - On acknowledgement, the paging owner sends one `handled` notification per session that holds a copy, and each `*Out` edits its copy to `handled.marked`.
  - `AckPage` (`Ref`, `Channel` web/phone/telegram) arrives from `web_user`, `web_admin` and `telegram` through `CommandsIn`. Telegram acknowledgements count only from the paired chat, by an unguessable button reference. Email never acknowledges, and an email reply never counts.
  - Escalation: `SetReminder` takes `Kind` `escalation`, `IncidentRef`, `PageRef` and `DelaySeconds`, from origin `system`. It is cancelled with `CancelReminder` from `system`. When due, `ReminderTimer` sends `OcuTalon.Msg.Escalation` (`IncidentRef`, `PageRef`).
  - Before Story 24.3, `ReminderOps` answers `not_built` and Notify routes `page` generically. 23.4's tests use an escalation-timer fixture and a fixture notification sent straight to `TelegramOut`. 23.4 owns the `TelegramOut` delivery and the Got it handling.
  - `EmailOut` sends a page only to the on-call key's address for the page's role, read at send time, once per page row. That is Story 24.3's.
- **SQL watch (AD-18):**
  - The row is `Kind` `sql_query` in `OcuTalon.Data.BackgroundCheck`, owned by the admin's session and scheduled by `IntervalMinutes`. 23.8 adds the query and result-hash columns.
  - The user is `OcuTalonSqlReader`, over a separate xDBC loopback connection, never as the production's user. 23.8 measures how it connects and how the password is kept (a veto item).
  - `SaveSqlWatch` (`Action` save/remove, `CheckRef`, `Name`, `Query` of at most 4,000 characters, `IntervalMinutes`) goes to `WatchOps`, which has no `MessageMap` entry yet.
  - `Roles.Assign` refuses the reader user, and it never holds an approver or viewer role.
- **Conventions:**
  - Tests live in `OcuTalon.Test.Watch` (23.3, 23.4) and `OcuTalon.Test.Checks` (23.8). CI mock scenarios go under `ci/mock/scenarios/A/`, and the Telegram mock covers Got it.
  - Audit goes only through `OcuTalon.Bridge.Audit`. `IncidentManager` is the only one that moves incident state.
  - Lane A never edits Lane B's contracts: the `page` kind and route, the Reminder escalation kind, `AckPage`, `SaveSqlWatch`, the on-call keys, the partner-contact table and `Msg.Escalation`.

## UX & Interaction Patterns

- Rollback uses the approval request card with its own dry-run block: a "Before" row and an "After" row, and "Nothing has changed yet." while the request is pending.
- The Telegram page is plain text with no Markdown or emoji, and the phone shows the same text. It has a **Got it** button. When anyone acknowledges, from any channel, the message is edited in place to "Marked as handled at {time}" and the button is removed.
- Settings › On call (36.4) shows "OcuTalon doesn't send pages yet…" until `OcuTalon.Data.Page` is compiled. 23.4 must test that the line disappears once the table exists (DW-1277).
- A person given only an email address can't press Got it, so the backup is always paged after the escalation minutes (DW-1250; the help text was accepted).
- The SQL watch help must not claim the query runs as a read-only user until 23.8's test proves that INSERT, UPDATE, DELETE and DDL are refused.
- The guide describes suspend, resume and rollback only as working "on your own install". On the demo, only reroute is offered.

## Cross-Story Dependencies

- Story 36.1 (setting history and spine names), 36.2 (keys, verbs, the escalation kind, `Msg.Escalation`) and 36.4 and 36.6 (the On call section) have all merged.
- Epic 24 is still in backlog:
  - Story 24.2 (the SQL watch settings section) will submit `SaveSqlWatch`. Until then, 23.8's test submits the command itself.
  - Story 24.3 (channel routing, the `ReminderTimer` escalation, email pages) has not merged. 23.4 works against its fixtures.
- Story 23.8 also relies on Epic 14's security overview listing the read-only SQL user.
- Open DW items: DW-1225 is 23.3's, and DW-1277 is 23.4's.
- Gaps:
  - The page and rollback texts are named as keys but are not yet in the UX Message Catalog. They must be proposed and accepted before they ship.
  - The planning docs don't say whether the online-demo install creates `OcuTalonSqlReader` at all.
