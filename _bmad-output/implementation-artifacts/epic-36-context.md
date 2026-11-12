# Epic 36 Context: Step 5's contracts: setting history, and the on-call person in Settings

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Fix step 5's cross-lane names in the spine so Lane A's Epic 23 and Lane B's Epic 24 can build without waiting on each other. Story 36.1 (Lane A files) names step 5's Lane A contracts and builds per-production setting history, so an incident can name the change that came just before its failures. Story 36.2 (Lane B files) names step 5's Lane B contracts in the spine and creates them as code (paging, escalation, the acknowledge and SQL-query-watch verbs, on-call keys, partner-contact table), so Epics 23 and 24 build in parallel. Story 36.4 (Lane B files, after 36.2) builds the Settings section where an admin picks the on-call person, the backup, each person's paging channels and the time before escalation. Story 36.3 (Lane B files, last) adds the admin-docs link to Epic 22's worked Jira example once Epic 22 merges. The epic only groups the stories for merging: each story keeps its home lane's files.

## Stories

- Story 36.1: Record the setting history of each watched production
- Story 36.2: Fix Lane B's step 5 contracts: paging, escalation and the SQL query watch verb
- Story 36.4: Set the on-call person and backup in Settings
- Story 36.3: Link the worked Jira example from the admin docs

## Requirements & Constraints

- **Paging channels (decided):** by default a page goes to the on-call person and the backup by both Telegram and email; each person can choose Telegram, email or both. Telegram reaches only a user whose session has a paired chat (the bot can't message anyone first), so a person with no paired chat, or given only as an email address, is paged by email. An acknowledgement on any channel stops escalation. Escalation to the backup defaults to 15 minutes. IRIS Managed Alerts are never turned off.
- **Setting history:** a production's first snapshot records no changes; a detected time is accurate to within the check interval; no row names who made a change; taking a snapshot never changes the watched production. Credentials: a setting that references an `Ens.Config.Credentials` entry stores only its ID (a name, not a secret); only a setting whose value is itself a secret is stored as a salted hash (`Webhook.HashSecret`/`Matches`), used only for change detection. The hash never leaves its table (no GET, `/v1/state`, trace, log, digest, notice or eval output carries it), proved by one leak-scan test; a change row for such a setting keeps both values blank. Rows older than `daysToKeep` (90) are purged, but the newest snapshot per watched production is always kept. Setting history is off on the online demo (pinned).
- **On-call section (36.4):** each choice is an OcuTalon user or an email address. Escalation time defaults to 15 and must be a whole number of minutes above zero. An invalid email or time gets a field error, focus moves to the first error, nothing is saved. Server failure: "Couldn't save. Nothing was changed." Good save: "Saved. Applies within a minute. Recorded in the audit log." Leaving with unsaved changes asks first. Non-admins get 403 and nothing changes. The online demo has no admin and never has an on-call configuration. Every control is labelled; the section works by keyboard. Tests: `OcuTalon.Test.Core` plus a Playwright spec under `web/e2e/`.
- **Texts:** a string ships in the story that first shows it. 36.1 ships no public text and no GUIDE line. Already approved as catalog text (36.2 / 23.3 use them verbatim, no re-proposal unless changed): `page.onCall`, `page.onCallEmail`, `page.backup`, `page.backupEmail`, `page.subject` (36.2), and the rollback strings, `incident.settingChangeCause`, `NOTALLOWED`, `ONLINESHARED` (23.3); `NOTSETUP` is dropped. Any other text the UX doesn't give (escalation, the on-call, partner-contact and SQL-query-watch sections and their field errors) is proposed to the author as an `EXPERIENCE.md` addition with its catalog key; nothing ships until accepted, so 36.4 uses only accepted on-call texts. Other settings texts reuse step 2's.
- **Admin docs link (36.3):** with Epic 22 merged, link Story 22.6's worked Jira example under `docs/` and copy its sentence that an MCP tool running operating-system commands or arbitrary code must be classified risky; the link must resolve.

## Technical Decisions

- **Setting history:** snapshots, not the IRIS audit log (scripted/API changes leave no record; the log needs `%Admin_Secure`). On each `Tick`, `Checks` compares the per-namespace production-change counter (`^IRIS.Temp.EnsProdModCounter`; 36.1's Task 0 measures it on a lane-B throwaway first, else HALT) with the last value seen; only when it moved, after a restart, or hourly, `OcuTalon.Watch.SettingHistory` snapshots every item's host and adapter settings plus applying System Default Settings through `Watch.Reader` and diffs against the previous snapshot. Each difference is one `SettingChange` row. `SettingSnapshot`/`SettingChange` are Lane A tables (short names, `^OcuTalonP.*`, committed storage, append-only, purged from the Watch area). Off on the online demo.
- **Fix-kind privileges:** no write grant ships before something uses it. 36.1 declares no roll-back kind and adds no `RESOURCES` entry, no `%Ens_ProductionConfig:W` grant, no forbidden-list test exception and no security-overview change; own installs keep their current privileges. The spine's AD-24 records: "%Ens_ProductionConfig:W is granted by Story 23.3 together with rollback_setting; the demo install leaves it out." Story 23.3 (the first story that offers a rollback) declares the kind, its grant, the installer composition, the overview line and the one test exception. Suspend/resume declare only `%Ens_ConfigItemRun`, reroute `%Ens_MessageResend`.
- **Lane split (AD-29/AD-33):** Lane A never edits Lane B contracts. 36.2 appends what 36.1 asks for in `OcuTalon.Msg` and `OcuTalon.Data` as their owner. Any new table, item or event type enters the spine's ownership tables in the same change. The AD-29 pattern is an "Epic N's names" bullet.
- **Settings:** `SettingsOps` is the only run-time writer. A save is one `SaveSettings` (origin `web_admin`) whose section is declared in `SettingsOps`' `XData Sections`, keys on its allow-list. Each changed value gets a `Settings` audit entry; `Data.Setting.Get` serves it within 60 s with no restart. Field types today: int (with range), time, channels, bridge, flag; no email or user type exists yet.
- **Escalation** reuses `ReminderTimer`, so AD-5's long-timer list doesn't grow.

**Lane B contracts 36.2 must fix (named by 36.1's spec; the spine amendments, `IncidentManager`, `Data.Page`, `Msg.Escalation` and the paging-ack rules are approved).** Check the spine as 36.1 actually writes it:
- `page` notification kind (`Msg.Enum` `NOTIFICATIONKIND`) and its `Notify` route.
- An escalation kind on `Reminder` (it has no `Kind` property today), run by `ReminderTimer`, which sends `OcuTalon.Msg.Escalation` (IncidentRef, PageRef) to `IncidentManager` when due. 36.2 creates the class as `Msg` owner.
- Verbs `AckPage` and `SaveSqlWatch` (neither exists; `GotIt` is only the tell-now handled verb). `IncidentManager` routes AckPage, as with `ProposeFix`.
- On-call setting keys and the on-call section; partner-contact table (Lane B, written only by `SettingsOps`; `Fix.PartnerContacts` is a demo-only Lane A fixture, not this table).
- `handled` notification (the kind exists) and a `Delivery` lookup by the page's `Ref`. `Delivery.FindByRef` today matches `DecisionRef`; reusing it is a design choice.
- `approval` payload fields for the new kinds' dry runs.
- Spine routes for the partner-contact and SQL-query-watch sections (Story 24.2 builds them).

**Lane A names 36.1 fixes that 36.2 consumes:** paging owner `IncidentManager`; table `OcuTalon.Data.Page` (Lane A, built in 23.4): Ref, IncidentRef, Role `oncall|backup`, Person (user name or email, never a Telegram identity), Channels, SentAt, AcknowledgedAt, AcknowledgedChannel, EscalationRef. Acknowledging: web Got it submits AckPage through `CommandsIn`; Telegram Got it carries an unguessable ref, accepted only from the paired chat; email carries no acknowledgement, and a reply never counts. Every copy then shows `handled.marked`. Catalog keys `page.onCall`, `page.onCallEmail`, `page.backup`, `page.backupEmail`, `page.subject`. `incident` payload gains `Page` {state `paged|acknowledged|escalated`, pagedAt, acknowledgedAt, channel}. SQL-query check: `BackgroundCheck` `Kind` `sql_query`, running as `OcuTalonSqlReader` (23.8); its mechanism stays marked inference in AD-18 until 23.8 measures it.

**Already delivered vs missing in `src/` (re-checked at `046614b9`):**

| Contract | State |
| --- | --- |
| Reroute, SuspendItem, ResumeItem, PartnerWarning kinds with `RESOURCES`; ProposeFix verb | Exist (Stories 23.2, 23.5) |
| Queue-backlog check (`Kind` `queues`); incident summary storage and `summary` kind | Exist (Stories 23.6, 23.7) |
| Step-5 catalog texts for suspend, resume, reroute, partner, summary; `handled.marked`, `button.gotIt` | Exist and approved; reuse by key |
| SettingHistory and both tables | Missing; 36.1 spec gate ruled |
| Roll-back kind, its `RESOURCES`, the `%Ens_ProductionConfig:W` grant and test exception | Not in this epic (Story 23.3) |
| `page` kind, `Reminder` kind, `Msg.Escalation`, AckPage, SaveSqlWatch, on-call keys, section routes in the spine, partner-contact table, page-Ref lookup | Missing (36.2) |
| On-call Settings section UI, its save path and tests | Missing (36.4) |

## UX & Interaction Patterns

- Settings sections save independently with **Save changes**. The section list today has no on-call entry, and the UX gives no on-call wording, so every on-call label and field error is a proposal.
- Each step-5 fix uses the approval request card with its own dry run. A partner warning shows the exact text and recipients (simulated on the demo, sent to the Simulated mailbox). On the online demo only reroute is offered.
- Every copy of an acknowledged page updates to "Marked as handled at {time}" (Telegram's in Story 23.4).

## Cross-Story Dependencies

- Order: 36.1, 36.2, 36.4, 36.3. 36.2 follows 36.1 (it appends what 36.1 asks for and builds on 36.1's spine text). 36.4 depends on 36.2's contracts (on-call keys, section route). Story 23.3 waits on 36.1 and now carries the roll-back declaration and grant (DW-1225). Stories 23.4, 23.8 and Epic 24 (24.2 partner contacts and SQL watches in Settings, 24.3 page delivery and acknowledgement, 24.4 the page view) wait on 36.2's contracts; the split keeps every "Story 36.2 fixes" reference in Epics 23 and 24 true.
- 36.1 does not wait on Epic 22. On the contended `Checks/Process.cls` (36.1's `Tick` hook is a non-append edit; Story 22.5 appends `BackgroundCheck` columns there) 36.1 lands first and 22.5/22.11 integrate forward; all local until HOLD OFF.
- **Epic 21 (lane C, `origin/OCT-epic21`, not merged; Story 21.7, email digest) touches 36.2's and 36.4's files:**
  - `Core/Rule/Notify.cls`: new `DigestEmail` rule routing kind `digest` to `EmailOut`. 36.2's `page` route must sit beside it.
  - `Data/Delivery.cls`: appends `DigestKey` and `EchoedAt` (storage Values 13 and 14), a trailing `digestKey` argument on `Record`, and `SentByEmail`, `TakeEcho`, `DigestEmailsSince`, `DigestEmailSent`. A page-Ref property must append after them or collide.
  - `Core/SettingsOps.cls` (36.4's save path): the `channels` type accepts `email` (stored web, phone, telegram, email). `CommandsIn.ItemRunning` becomes public.
  - `Msg/Catalog/Core.cls` (`email.digestSubject`), `Test/Core/Routing.cls` (`TestNotifyDigestEmail`), `Test/Core/SettingsSave.cls`, `README.md` (a "Your own mailbox" sentence), EXPERIENCE.md (two rows) and the spine (Notify digest-email bullets, `EmailOut`'s digest path, the renderer's `email` channel, a `Functions.DigestChannels` row).
  - `EmailOut` works out the digest recipient itself (`email.address`, mailbox owner only); paging an arbitrary on-call address is a new path.
- **Story 0.30 (merged)** moved install, features and administration from README to `GUIDE.md`. The README now links GUIDE.md's "For admins and developers" section, so 36.3's "README admin section" now means that GUIDE.md section. Epic 21's README feature edit predates 0.30 and will have to move to GUIDE.md when it merges.
- 36.3 is the only story waiting on Epic 22; it cannot start until Epic 22 merges (22.6 is in backlog; no Jira example in `docs/` today).

**Decisions made unattended:** delivered Epic 23 kinds count toward 36.1's contract. 36.1's spec names are treated as fixed for 36.2's planning (rulings V1-V6 are now in). 36.3's README criterion is read as GUIDE.md's admin section, linked from README.

**Gaps:** (1) The on-call page's email recipient and `EmailOut` path are unnamed: Epic 21's `EmailOut` only mails `email.address`. (2) The on-call keys' names and value format are not named anywhere; 36.2 must name them for 36.4. The UX gives no email or user field type and no on-call text. (3) `Delivery` contention with Epic 21 means its merge order must be settled. (4) The `approval` payload's dry-run fields for the new kinds are not specified.
