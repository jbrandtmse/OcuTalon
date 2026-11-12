# Epic 36 Context: Step 5's contracts: setting history, and the on-call person in Settings

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Fix step 5's cross-lane names in the spine so Lane A's Epic 23 and Lane B's Epic 24 can build without waiting on each other. Two stories do it. Story 36.1 (Lane A files) names step 5's Lane A contracts and builds per-production setting history, so an incident can name the change that came just before its failures. Story 36.2 (Lane B files) names step 5's Lane B contracts and builds the Settings section where an admin picks the on-call person, the backup, each person's paging channels and the time before escalation. The epic only groups the two stories for merging: each story keeps its home lane's files.

## Stories

- Story 36.1: Record the setting history of each watched production
- Story 36.2: Set the on-call person and backup in Settings

## Requirements & Constraints

- **Paging channels (decided, not open):** by default a page goes to the on-call person and the backup by both Telegram and email. Each person can choose Telegram, email or both. Telegram reaches only a user whose session has a paired chat (the bot can't message anyone first), so a person with no paired chat, or one given only as an email address, is paged by email. The spine must say how a page is acknowledged on each channel before any paging work starts.
- **Setting history:** a production's first snapshot records no changes. A detected time is accurate to within the check interval. No row ever names who made a change, and taking a snapshot never changes the watched production. Credential-type values are removed before anything is stored: a credential change is recorded with both values blank, and its value never reaches a message, a log or an agent step. Rows older than `daysToKeep` (90 by default) are purged.
- **On-call section:** each choice is either an OcuTalon user or an email address. The escalation time defaults to 15 minutes and must be a whole number of minutes above zero. An invalid email address or escalation time gets a field error, focus moves to the first error, and nothing is saved. A server failure shows "Couldn't save. Nothing was changed." A good save shows "Saved. Applies within a minute. Recorded in the audit log." Leaving with unsaved changes asks first. Non-admins get 403 and nothing changes. The online demo has no admin and never has an on-call configuration. Every control is labelled and the section works by keyboard.
- **Texts:** any channel or settings text the UX doesn't give yet goes to the author as a proposed `EXPERIENCE.md` addition with its catalog key. This covers the page, the escalation, each new fix's dry run and result, the partner-warning request, the incident summary, and the on-call, partner-contact and SQL-query-watch sections and their field errors. No text ships until the author accepts it. Every other settings text reuses the step-2 settings text.

## Technical Decisions

- **Setting history mechanism:** setting history is built from snapshots, not the IRIS audit log. Scripted and API changes leave no audit record, and reading the log needs `%Admin_Secure`, which the service user lacks. On each `Tick`, `Checks` compares Interoperability's per-namespace production-change counter with the last value it saw. Only when the counter moved, after a restart, or hourly as a safety net, `OcuTalon.Watch.SettingHistory` snapshots every item's host and adapter settings plus the System Default Settings that apply, read through `Watch.Reader`, and diffs the result against the previous snapshot. Each difference becomes one `SettingChange` row: production, item, target, setting, old, new, and detected-at in UTC. The evidence pack uses the changes from the 24 hours before the first failure. A roll-back restores a snapshot's old value through the governed fix path.
- **Tables:** `SettingSnapshot` and `SettingChange` are Lane A tables. Each needs a short-name entry in `src/short-names.tsv`, `DEFAULTGLOBAL` `^OcuTalonP.*`, a committed storage block, append-only storage, and a place in the Watch area's `Purge(daysToKeep)` declaration. That declaration is `Install/Step/Watch.cls`, which today calls only `IncidentManager.Purge`.
- **Fix-kind privileges:** roll-back declares `%Ens_ProductionConfig` WRITE, and AD-24 names it as the one exception to the forbidden-privilege list. Suspend and resume declare only `%Ens_ConfigItemRun`, and reroute declares `%Ens_MessageResend`. The installer composes the service user's grants from these declarations. The generated security overview must list `%Ens_ProductionConfig` with the kind that needs it. The forbidden-privilege test must allow exactly that one grant to the service user and still fail on any other forbidden privilege or holder. The online demo leaves item privileges out (as for `%Ens_ConfigItemRun`, shown by the `ONLINEGRANT` pattern).
- **Lane split (AD-29/AD-33):** Lane A (36.1) never edits Lane B contracts: the page notification and its `Notify` route, the escalation kind on `Reminder` that `ReminderTimer` runs, the verbs to acknowledge a page and save a SQL query watch, the on-call keys and the partner-contact table. Story 36.2 appends what 36.1 asks for in `OcuTalon.Msg` and `OcuTalon.Data` as their owner. Any new table, item or event type goes into the spine's ownership tables in the same change.
- **Settings:** `SettingsOps` is the only run-time writer. A save is one `SaveSettings` command (origin `web_admin`) whose section is declared in `SettingsOps`' `XData Sections`. The keys must join its allow-list. Each changed value gets a `Settings` audit entry (AD-17), and `Data.Setting.Get` serves the new value within 60 s without a restart. Escalation reuses `ReminderTimer`, so AD-5's list of long-timer processes does not grow.

**Already delivered on this branch vs. still missing** (checked against `src/` at `abb3b1ae`). 36.1 records the already-delivered contracts in the spine and builds only the missing ones:

| Contract | State |
| --- | --- |
| `Fix/Kind/Reroute`, `SuspendItem`, `ResumeItem` (extends Suspend), `PartnerWarning`, registered in `Fix.Kind` `KINDS`, with `RESOURCES` as above (PartnerWarning none) | Exist (Stories 23.2, 23.5); the spine's AD-16 step-5 and partner-warning paragraphs exist |
| Queue-backlog `BackgroundCheck` row (`Kind` `queues`) and the `StartWatch.Kind` field | Exist (Story 23.7) |
| Incident summary storage (`Data.Incident.Summary`, `Watch.Summary`, notification kind `summary`) | Exists (Story 23.6) |
| `ProposeFix` verb (Lane A, owner `IncidentManager`) | Exists (Story 23.2) |
| Spine: SettingHistory paragraph (AD-15), AD-24 exception, ownership of `SettingSnapshot`/`SettingChange` | Written, but no code exists |
| `OcuTalon.Watch.SettingHistory`, `SettingSnapshot`, `SettingChange`, change-counter read, System Default Settings read in `Reader` | **Missing** |
| Roll-back kind | **Missing**; `%Ens_ProductionConfig` is still in `Install/Step/Roles.cls` `FORBIDDEN` and in the forbidden lists in `Test/Install/Registry.cls` and `Test/Web/Install.cls` |
| Paging owner, its table and its escalation message; a `page` notification kind (`Msg.Enum` `NOTIFICATIONKIND` has `handled` but no page) and its `Notify` route | **Missing** |
| `Reminder` escalation kind (`Reminder` has no `Kind` property) | **Missing** |
| Verbs to acknowledge a page and to save a SQL query watch | **Missing** (`GotIt` exists only as the tell-now handled verb) |
| SQL-query check type, read-only SQL user | **Missing** |
| On-call keys and section (sections today: models, budgets, daily-digest, time-zone, check-thresholds, demo-mode, channels) | **Missing** |
| Partner-contact table | **Missing**; `Fix.PartnerContacts` is a demo-only, read-only XData fixture (Lane A), not the Lane B table |
| New `incident` payload fields; `Msg.Catalog.Watch` step-5 keys | **Missing**; `Payload.Incident` has no setting-change or summary field |
| `Delivery` lookup by a page's `Ref` | Not present; `Delivery.FindByRef` looks up by `DecisionRef` and could serve if a page carries one (design choice) |

## UX & Interaction Patterns

- Each step-5 fix uses the existing approval request card with its own dry run. A partner warning shows the exact text and recipients; on the demo the recipients are simulated and the notice goes to the Simulated mailbox. A setting-change cause adds "The feed broke four minutes after this setting changed." On the online demo only reroute is offered.
- Every copy of an acknowledged page updates to "Marked as handled at {time}". Telegram's copy is updated in Story 23.4.

## Cross-Story Dependencies

- Story 36.2 follows 36.1 because it appends what 36.1 asks for. Epic 23's Story 23.3 waits on 36.1. Stories 23.4 and 23.8 and Epic 24 wait on 36.2.
- 36.1 also needs Epics 14 and 30 (both done) and Epic 22, because Story 22.5 changes the same `BackgroundCheck`/`Checks` footprint. **Epic 22 is not merged** (22.3 to 22.7, 22.9 and 22.10 are open). It will append the `BackgroundCheck` columns `Server`, `Tool`, `Arguments` and `IntervalMinutes`, add a `CheckRun.Reason` value, and edit `Checks/Process.cls` and `Checks/Coverage.cls`. 36.1's SQL-query row type and its changes to `Checks` must append without colliding, or wait.
- 36.2's README acceptance criterion (the link to Story 22.6's worked Jira example under `docs/`, and its sentence that a tool running operating-system commands or arbitrary code must be classified risky) **cannot be met until Epic 22 merges**. No Jira example exists in `docs/` today.
- Readiness flagged the `%Ens_ProductionConfig` grant as a veto-sensitive change to a privilege rule from Epic 3. Treat it as deliberate and as the only exception.
- Judgment call made unattended: the delivered Epic 23 kinds count as satisfying their parts of 36.1's spine contract. 36.1 confirms and records them, adding only the parts listed as missing above, and does not rebuild them.
