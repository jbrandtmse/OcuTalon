# Epic 36 Context: Step 5's contracts: setting history, and the on-call person in Settings

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Fix step 5's cross-lane names in the spine so Lane A's Epic 23 and Lane B's Epic 24 can build without waiting on each other. Story 36.1 (Lane A, done) built per-production setting history and named step 5's Lane A contracts. Story 36.2 (Lane B, done) named step 5's Lane B contracts in the spine and created them as code. Story 36.4 (Lane B, next) builds the Settings section where an admin picks the on-call person, the backup, each person's paging channels and the time before escalation. Story 36.3 (Lane B, last) links Epic 22's worked Jira example from the admin docs once Epic 22 merges. The epic only groups the stories for merging: each story keeps its home lane's files.

## Stories

- Story 36.1: Record the setting history of each watched production (done)
- Story 36.2: Fix Lane B's step 5 contracts: paging, escalation and the SQL query watch verb (done)
- Story 36.4: Set the on-call person and backup in Settings
- Story 36.3: Link the worked Jira example from the admin docs

## Requirements & Constraints

- **Paging channels (decided):** by default a page goes to the on-call person and the backup by both Telegram and email; each person can choose Telegram, email or both. Telegram reaches only a user whose session has a paired chat (the bot can't message anyone first), so a person with no paired chat, or given only as an email address, is paged by email. An acknowledgement on any channel stops escalation; email never acknowledges. Escalation to the backup defaults to 15 minutes. IRIS Managed Alerts are never turned off.
- **On-call section (36.4):** each choice is an OcuTalon user or an email address. Escalation time defaults to 15 and must be a whole number of minutes (1 to 1440). An invalid email or time gets a field error, focus moves to the first error, nothing is saved. Server failure: "Couldn't save. Nothing was changed." Good save: "Saved. Applies within a minute. Recorded in the audit log." Leaving with unsaved changes asks first. `Setting.Get` returns the new values within a minute, `SettingsOps` is the only writer, and the IRIS audit log holds an entry with the admin's IRIS user and session. Non-admins get 403 and nothing changes. Tests: `OcuTalon.Test.Core` plus a Playwright spec under `web/e2e/` (save, correct, save again; stored values, audit entries and page states match; keyboard-operable, every control labelled).
- **Audit of contact data (ruled, binding on 36.4):** on-call saves are audited WITH from/to values (names and addresses), ONLY in the IRIS audit log; they appear in no other log, trace, digest, notice or eval output. ONE leak-scan test in 36.4 pins it (24.2 does the same for partner contacts).
- **Online demo:** no on-call configuration ever. Visitors get 403 (no admin); even an admin's save answers 409 `not_available` with `settings.onCallOffOnDemo`, and the section is absent from `GET /api/v1/settings` and hidden on the page. Nothing is written and no page is ever sent.
- **Texts for 36.4 (accepted, ship verbatim in `settings-view.ts` `SETTINGS_TEXTS`, each with a `ruled` SOURCES entry):** the EXPERIENCE.md "Settings (step 5)" block's On call keys: `settings.onCallSection`, `onCallHelp`, `onCallNotYet` (shown while `OcuTalon.Data.Page` isn't compiled), `onCallPrimary`, `onCallBackup`, `onCallPerson` with options `onCallNobody` and `onCallByEmail`, `onCallEmail`, `onCallChannels`, `onCallTelegramUnpaired`, `onCallTelegramEmailOnly`, `onCallMinutes`, `onCallMinutesHelp`, `badEmail`, `onCallBadMinutes`, `onCallNoChannel`, `onCallUnknownUser`, and `onCallOffOnDemo` in the Planner's replaced wording ("…because its visitors aren't admins…"). Reused unchanged: Save changes, the saved/failed texts, the unsaved-changes dialog, "Only OcuTalon admins can open settings.", the channel names "Telegram" and "Email". Any other text is proposed to the author first; nothing unaccepted ships. 36.4 judges whether a GUIDE or More-to-try line is needed (36.2 had none).
- **Open items routed to 36.4 (must be settled in its plan):**
  - DW-1249: a settings save is a production message whose `SaveSettings` Changes body Visual Trace shows, so the V3 "no trace" condition and its leak-scan test can't pass as worded until the trace exposure is resolved or the ruling is clarified.
  - DW-1250: a person given only as an email address can never acknowledge a page, so the backup is always paged after the escalation time, and the accepted On call texts don't say so (any new wording needs acceptance).
- **Admin docs link (36.3):** with Epic 22 merged, link Story 22.6's worked Jira example under `docs/` from GUIDE.md's "For admins and developers" section (linked from README) and copy its sentence that an MCP tool running operating-system commands or arbitrary code must be classified risky; the link must resolve.

## Technical Decisions

- **Setting history (36.1, delivered):** snapshots, not the IRIS audit log. `Watch.SettingHistory` runs from one line in `Checks.Tick` and snapshots through `Watch.Reader.Settings` only when none exists, the production-change counter or start mark moved, or an hour passed; tables `SettingSnapshot`/`SettingChange` (Lane A, append-only, purged at 90 days keeping each watched production's newest snapshot). A Credentials reference keeps its ID; a secret value is blank with a salted hash that never leaves its table. Change values are cut at 2,000 characters (23.3's rollback must refuse a cut value). Off on the demo. No rollback kind or `%Ens_ProductionConfig:W` grant: Story 23.3 owns those.
- **Step-5 Lane B contracts (36.2, delivered):** `page` in `NOTIFICATIONKIND` (takes the generic `Notify` route until 24.3); `Msg.Escalation` (IncidentRef, PageRef); `Command.AckPage` (Ref, Channel; from `web_user`, `web_admin`, `telegram`; owner `IncidentManager`); `Command.SaveSqlWatch` (`web_admin` only; owner `WatchOps`); `SetReminder` appends `Kind`, `IncidentRef`, `PageRef`; two `CommandsIn` Routes rows; `ReminderOps` answers `not_built` for an escalation until 24.3. A page's `Delivery` copies reuse `DecisionRef` = the page's Ref, so `Delivery` gets no new column. The spine holds all Lane B step-5 bullets, including the V3 audit rule.
- **On-call keys (spine, AD-19; written only by `SettingsOps` from the on-call section):** `oncall.primary.user`/`oncall.backup.user` (IRIS user name with an OcuTalon session, or ""); `oncall.primary.email`/`oncall.backup.email` (address pages are emailed to, or ""); `oncall.primary.channels`/`oncall.backup.channels` (comma list ordered `telegram,email`, default `telegram,email`; `telegram` accepted only for a user whose session is paired at save time; saved channels must include one the person can be reached on); `oncall.escalationMinutes` (1 to 1440, default 15). A role is configured when its user or address is set; with no on-call person nothing is paged.
- **On-call route:** `POST /api/v1/settings/on-call`, section kind `oncall` with its own saver in `SettingsOps` (`XData Sections` row, allow-list names, a dispatch line in `Save`, a branch in `Values`). Admin-only through `Web/Api` `OnPreDispatch`; no new role or grant. The user list (IRIS user names of session rows with a paired flag) is shown only to admins. An "OcuTalon user" is an IRIS user with a `Data.Session` row; pairing is per session. A user is emailed at the address the admin enters, since there is no OcuTalon-side address for a user.
- **Page email (Story 24.3, not 36.4):** `EmailOut` sends a page only for a real `Data.Page` row with `email` in its Channels, only to that role's `oncall.*.email` key read at send time, once per page; CI mail mock only; `not_available` on the demo.
- **Settings conventions:** a save is one `SaveSettings` (origin `web_admin`); each changed value gets a `Settings` audit entry; `Data.Setting.Get` caches 60 s. Existing field types: int (with range), time, channels, bridge, flag; there is no email or user type yet.

## UX & Interaction Patterns

- Settings sections save independently with **Save changes**. Settings nav grows from 7 to 8 with "On call". Per role: a Person select (Nobody, each OcuTalon user, Someone else by email), an email field, a "Page by" channel group whose Telegram option is disabled with `onCallTelegramUnpaired` or `onCallTelegramEmailOnly` beside it, then the minutes field for the whole section.
- Field errors mark the field, focus moves to the first error; every control labelled; keyboard-operable.
- Already in place: the unsaved-changes guard, the save/fail texts, 403 for non-admins on every `/v1/settings` URL.

## Cross-Story Dependencies

- Order: 36.1, 36.2 (both done), 36.4, 36.3. 36.4 consumes 36.2's on-call keys and section route. Stories 23.3 (rollback, grant), 23.4 (`Data.Page`, Telegram paging), 23.8 (SQL reader), 24.2 (partner contacts, SQL watches in Settings), 24.3 (page delivery, escalation) and 24.4 build on these contracts.
- **Epic 21 overlap (lane C, `origin/OCT-epic21`, unmerged; 74 files, incl. Stories 21.7 email digest and 21.8 OAuth2 mail):**
  - `Core/SettingsOps.cls` (+68/-): the `channels` type accepts `email`; 36.4 adds its section row, allow-list names, `Save` dispatch, `Values` branch and new methods at the end.
  - `web/src/app/settings/settings-page.ts` (`@switch`, imports) and `settings-view.ts` (`SETTINGS_SECTIONS`, `SETTINGS_TEXTS`): Epic 21 edits near the same lines; expect merge conflicts. `web/scripts/settings-view.test.mjs` also changes in both.
  - `Test/Core/SettingsSave.cls`: Epic 21 edits only `TestDigestSection`; 36.4 extends `TestAllowList` and `TestValues`. Epic 21 also changes `Test/Web/SettingsApi.cls`, `Test/Core/SettingsEmail.cls`, `daily-digest-section.ts` and `web/e2e/settings/email.spec.ts`.
  - Elsewhere: `Data/Delivery.cls` (Values 13/14), `Core/Rule/Notify.cls` (digest route), `Channel/Email/Out.cls`, `Core/CommandsIn.cls`, `Msg/Catalog/Core.cls`, the spine, EXPERIENCE.md, GUIDE.md and README.
  - 36.4's new files have no overlap: `on-call-section.ts`, `web/e2e/settings/on-call.spec.ts`; `Web/Api.cls` gains one route (`Test/Web/Api.cls` `TestRoutes` 38 → 39).
- 36.3 waits on Epic 22 (22.6 in backlog; no Jira example in `docs/` yet).
