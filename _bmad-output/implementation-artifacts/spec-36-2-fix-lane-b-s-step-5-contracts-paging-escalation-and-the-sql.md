---
title: 'Story 36.2: Fix Lane B''s step 5 contracts: paging, escalation and the SQL query watch verb'
type: 'feature'
created: '2026-11-12'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-36-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-36-1-record-the-setting-history-of-each-watched-production.md'
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Step 5's Lane B names exist nowhere: the spine doesn't say how a page is routed, how an escalation timer runs on `ReminderTimer`, which verbs acknowledge a page or save a SQL query watch, which keys hold the on-call choice, or what the partner-contact table holds. Stories 23.4, 23.8 and Epic 24 can't build against them. As written, the story also builds the whole on-call Settings section. That is too much for one story (Design Notes › Proposed split).

**Approach:** This spec plans the **contracts half** of the proposed split. It writes Lane B's step-5 additions into the spine and creates their code contracts: the `page` notification kind, `OcuTalon.Msg.Escalation`, the `AckPage` and `SaveSqlWatch` verb classes with their `CommandsIn` routes, the escalation fields on `SetReminder` with a plain `not_built` refusal in `ReminderOps`, and the proposed texts. The on-call section's five criteria move verbatim to a new sibling, Story 36.4.

## Boundaries & Constraints

**Always:**
- Judge each criterion against the delivered code, and build only what is missing (Design Notes › Already met).
- Use only Lane B files (AD-29, AD-33). In contended files, make only the edits listed under Design Notes › Contended overlaps.
- Use 36.1's planned names as fixed: `IncidentManager`, `Data.Page` and its fields, `Msg.Escalation (IncidentRef, PageRef)`, and the catalog keys `page.*`.
- Change message storage only by appending (`docker/tests/test-storage.sh`).
- Run every IRIS test on a lane-B throwaway (`ci/iris.sh`, `ci/warm.sh`), never on slot B.
- Ship only public texts the runner reports as accepted (Design Notes › Proposed public text). Never invent wording.

**Never:**
- Edit Lane A files: `Watch/IncidentManager.cls`, `Watch/Ops.cls`, `Watch/*`, `Fix/*`, `Checks/*`, `Data/Page.cls` (Story 23.4), `Telegram/Out.cls`, `Msg/Catalog/Watch.cls`.
- Edit `Core/Rule/Notify.cls`, `Data/Delivery.cls`, `Data/Reminder.cls`, `Schedule/Reminder.cls`, `Core/SettingsOps.cls`, `Web/Api.cls`, `web/`, `README.md` or `GUIDE.md`. Those are Stories 24.3 and 36.4 (Design Notes › Decided in-stage).
- Add a table, an `/api/v1` route, a grant, a UI, a `ci/units.sh`, `.github/workflows` or `release/**` change.
- Send a page, an escalation or an email. Create a `Reminder` row of any kind but a plain reminder.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Ack, accepted origin | `AckPage` (Ref, Channel) from `web_user`, `web_admin` or `telegram` | Sent once to `IncidentManager`, with key, session and origin unchanged | none |
| Ack from a tool | `AckPage` with origin `tool` | `not_allowed`; nothing sent | Refusal text from the existing tool rule |
| SQL watch, admin | `SaveSqlWatch` from `web_admin` | Sent once to `WatchOps` | none |
| SQL watch, wrong origin | `SaveSqlWatch` from `web_user`, `telegram`, `tool`, `timer` or `system` | `not_allowed`; nothing sent | Existing `MESSAGENOTALLOWED` or `MESSAGENOTFROMTOOL` text |
| Escalation timer before 24.3 | `SetReminder` with `Kind` `escalation` (or any `Kind` but "" or `reminder`), any origin | Ok 0, outcome `not_built`, "This part of OcuTalon isn't built yet. Nothing was changed."; no `Reminder` row; no waiter | none |
| Plain reminder | `SetReminder` with `Kind` "" or `reminder` | Behaves as today | as today |
| Page kind | `Msg.Enum` NOTIFICATIONKIND | Ends `...,summary,page`; `Notify` unchanged | none |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Msg/Enum.cls:26` -- NOTIFICATIONKIND, a comma list; pinned by `Test/Msg/Contracts.cls:72`. Web input (`ci/units.sh:219`); `web/scripts/catalog.test.mjs:25` reads this file.
- `src/ocutalon/cls/OcuTalon/Msg/IncidentCommand.cls` (29 lines) and `Msg/Tick.cls` (32 lines) -- templates for `Msg/Escalation.cls` (`Ens.Request`, storage subscript `"Escalation"`).
- `src/ocutalon/cls/OcuTalon/Msg/Command/GotIt.cls` -- the sibling of `AckPage`: the same props, `Ref` (22) and `Channel` (32).
- `src/ocutalon/cls/OcuTalon/Msg/Command/SetReminder.cls:6-35` -- props Text, DueAt, DelaySeconds, LocalDueAt; storage Values 1-4.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- `XData Routes` :326-367 (`{verb, owner, origins}`); `Carry` :100 (refusals, `IsStub` → `not_built` :276); `TOOLVERBS` :62; `MESSAGENOTBUILT` :83. Epic 21 changes only `ItemRunning` :288.
- `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls:99-113` -- `Set`. The first check is `SessionExists`, so the Kind guard goes before it. `Result` :330.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls:299-312` -- read only (Lane A). An unknown request class gets error 5001, which `CommandsIn` maps to `failed`.
- `src/ocutalon/cls/OcuTalon/Data/Delivery.cls:90` `FindByRef(ref, channel, ownerRef)` -- matches `DecisionRef`. It is the page-copy lookup, reused with no schema change.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls:255-281` -- the `GotIt` → `Handled` → `handled` Notification pattern that the page acknowledgement mirrors (23.4/24.3).
- `src/ocutalon/cls/OcuTalon/Live/Payload/Part/DryRun.cls:6-43` -- the existing dry-run fields (Item, Field, Before, After, From, To, Example, Notice, Recipients, Simulated).
- Tests: `Test/Msg/Contracts.cls` (:42 verbs with the common fields, :72 enum strings, :83 parameter names, `XData Contracts` :161+ with entries for `SetReminder` :254 and `GotIt` :426); `Test/Core/CommandsRouting.cls:64` `TestRoutes` (12 verbs, probe owner); `Test/Schedule/Reminders.cls` (SetReminder through ReminderOps).
- Spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- AD-14 L490-508 (Notify L497, `EmailOut` L503, Got it L505), AD-18 L585-634, AD-19 L635-702 (step-2 keys L700, saving L701, per-person L662), AD-29 L1044-1099 (`ProposeFix` L1098), AD-33 L1162-1174, Tables L1418, cross-area rows near L1463, REST row L1220. Line numbers move after 36.1's spine edits; find the blocks by heading.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- Later Steps › Step 5 L1080; the Message Catalog block "Settings and requests (step 4)" L971-1024 is the model for a new "Settings (step 5)" block.

## Tasks & Acceptance

**Execution:**
- Spine -- write Design Notes › Spine additions. Then run `memlog.py append`, then `lint_spine.py` (needs `"ok": true`), and refresh `updated:` (Rule 20).
- `src/ocutalon/cls/OcuTalon/Msg/Enum.cls` -- append `,page` to NOTIFICATIONKIND.
- `src/ocutalon/cls/OcuTalon/Msg/Escalation.cls` -- NEW `Ens.Request` with `IncidentRef`, `PageRef` (MAXLEN 22), committed storage.
- `src/ocutalon/cls/OcuTalon/Msg/Command/AckPage.cls` -- NEW `Msg.Command` with `Ref` (22, the page's Ref) and `Channel` (32: `web`, `phone`, `telegram`).
- `src/ocutalon/cls/OcuTalon/Msg/Command/SaveSqlWatch.cls` -- NEW `Msg.Command` with `Action` (16: `save`, `remove`), `CheckRef` (22; empty for a new watch), `Name` (128), `Query` (4000), `IntervalMinutes` (`%Integer`).
- `src/ocutalon/cls/OcuTalon/Msg/Command/SetReminder.cls` -- append `Kind` (32; "" or `reminder` is a reminder, `escalation` an escalation timer), `IncidentRef` (22), `PageRef` (22), as storage Values 5-7.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- append two rows at the end of `XData Routes`: `{"verb": "AckPage", "owner": "IncidentManager", "origins": "web_user,web_admin,telegram"}` and `{"verb": "SaveSqlWatch", "owner": "WatchOps", "origins": "web_admin"}`. `TOOLVERBS` is unchanged.
- `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls` -- first line of `Set`: any `Kind` other than "" or `reminder` returns Ok 0, outcome `not_built`, with `CommandsIn`'s `MESSAGENOTBUILT` sentence, and stores nothing.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Contracts.cls` -- update the NOTIFICATIONKIND string. Add `AckPage` and `SaveSqlWatch` to the common-fields verb list. Add `Contracts` entries for `Msg.Escalation`, `Command.AckPage` and `Command.SaveSqlWatch`, and the three new `SetReminder` properties.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsRouting.cls` -- `TestRoutes` gains `AckPage|IncidentManager|telegram` and `SaveSqlWatch|WatchOps|web_admin` (12 → 14). New `TestStepFiveRefusals`: `AckPage` from `tool`, and `SaveSqlWatch` from `web_user` and `tool`, are `not_allowed` with zero probe calls.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/Reminders.cls` -- new `TestEscalationNotBuilt`: an escalation (origin `system`, `DelaySeconds` 60, `IncidentRef`/`PageRef` set) and a `Kind` `other` both answer `not_built` with the sentence. The session's `Reminder` count and the waiter count are unchanged. A plain `SetReminder` with `Kind` `reminder` still answers `set`.
- `EXPERIENCE.md` -- after acceptance only: a "Settings (step 5)" Message Catalog block, plus Later Steps › Step 5 lines, with each accepted text and its key.

**Acceptance Criteria:**
- Given the spine after this story, when step 5's Lane B contracts are looked up, then every item of the first criterion is there as Design Notes › Spine additions write it: the three settings sections and their routes, the on-call keys, the partner-contact table, the page notification and its route, the escalation kind on `Reminder`, the `approval` dry-run fields, `AckPage` and `SaveSqlWatch`, the `handled` notification and the `Delivery` lookup by the page's `Ref`. `lint_spine.py` reports `"ok": true`.
- Given the compiled package, when `Test.Msg.Contracts` runs, then `Msg.Escalation`, `AckPage`, `SaveSqlWatch` and `SetReminder` have exactly the properties above, the `page` kind is in NOTIFICATIONKIND, and Lane A's classes are untouched (`git diff --stat` lists only the files in Execution).
- Given `CommandsIn` (the consumer of the new rows, Rule 1), when the I/O matrix's commands are submitted, then each reaches its owner or is refused exactly as the matrix says.
- Given `ReminderOps` (the consumer of `SetReminder.Kind`), when an escalation timer is requested before Story 24.3, then it is refused `not_built` and nothing is stored or started.
- Given the texts in Design Notes › Proposed public text, when the runner reports the Planner's ruling, then only accepted texts reach EXPERIENCE.md, each with its key. No code ships any of them in this story.

## Spec Change Log

- 2026-11-12, runner ruling (doctrine U5 decide, split 2 of 6; logged `ruling` in cycle-log-epic-36.md): split (A) applied in epics.md. Story 36.2 is retitled "Fix Lane B's step 5 contracts: paging, escalation and the SQL query watch verb" (sprint key `36-2-fix-lane-b-s-step-5-contracts-paging-escalation-and-the-sql`; this file renamed to match) and keeps the first criterion with its "And" clauses; Story 36.4 "Set the on-call person and backup in Settings" takes the user story and the five on-call section criteria verbatim (planned next). Earlier, Story 36.3 took the README Jira-example criterion (split 1 of 6). Status reset to `draft` for re-planning and validation as the contracts story; the on-call section's design notes remain as input for 36.4's plan.

## Review Triage Log

## Design Notes

**Ledger inbox (Rule 17):** none owned by `36-2-set-the-on-call-person-and-backup-in-settings`.

### Proposed split (the blocking `intent gap`)

**Why.** After removing what is already delivered, the story still holds two separately shippable pieces of standard size.
- **(1) Contracts:** spine additions in five ADs, three new message classes, the `SetReminder` append, two routes, a refusal, contract tests, and text proposals for three sections.
- **(2) The on-call section:** a new `SettingsOps` section kind with its own saver and a user list with paired flags, a new route (`Test/Web/Api.cls` route count 38 → 39), a web section component, a settings nav that grows from 7 to 8, per-field errors, a Playwright spec, real-HTTP tests, and an audit test.
- Together they are well over 2,000 changed lines in contended files (SettingsOps, settings-page/view, CommandsIn).
- The contracts need no public text and unblock Stories 23.4, 23.8 and Epic 24. The section can't ship until its texts are accepted.
- Product default (6): split rather than stretch.

**Recommended (A):**
- Story 36.2 keeps its key and the first criterion with both of its "And" clauses (spine, the `Msg`/`Data` appends, the text proposals). It is retitled "Fix Lane B's step 5 contracts: paging, escalation and the SQL query watch verb", as Story 35.2 is named. The user story becomes "As the builders of Epics 23 and 24, we want step 5's Lane B names fixed in the spine and created as code contracts, so that both lanes build paging, escalation and the SQL watch in parallel."
- A new sibling, **Story 36.4: Set the on-call person and backup in Settings**, gets the original user story and the five criteria below, verbatim. It depends on Story 36.2, in Lane B's files.
- Why A: every cross-reference stays true without editing another epic's block. That covers Epic 23's dependency line (epics.md L785: "Story 36.2's on-call keys and acknowledgement verb … its save-SQL-query-watch verb"), Story 23.4's, 23.8's, 24.2's and 24.3's "the command verb Story 36.2 fixes", Epic 24's L793, and 36.1's spec ("Story 36.2 fixes").
- The retitle changes the sprint key. Use Rule 5's retitle steps: `SPRINT_PLAN generate --set`; the key's ledger slice is empty.

**Alternative (B):** Story 36.2 keeps its title and the section, and a new Story 36.4 takes the first criterion. It needs no retitle. But the five "Story 36.2 fixes" references in Epics 23 and 24, and 36.1's spec, would then name the wrong story. Changing another epic's dependency statements is owner-only.

**The criteria that move to Story 36.4, verbatim:**
- **Given** an admin opens the on-call section **When** they choose the on-call person and the backup **Then** each is either an OcuTalon user or an email address, paged by Telegram and email by default, with each person's choice of Telegram, email or both saved in their on-call settings; Telegram is offered only for a user whose session has a paired chat, because the bot can't message anyone first, so a person without one, or given only as an email address, is paged by email; and the time before escalation defaults to 15 minutes (FR-28) [AMENDED 2026-10-25, owner decision, relayed by the Contest Planner (PRD Open Question 5; the owner: "A. Both, and person can choose."): it read "on the channels PRD Open Question 5's answer allows (put to the author by Lane A's Story 36.1 (was 23.1)); Telegram is offered only for a user whose session has a paired chat, because the bot can't message anyone first;"] **And** **Save changes** saves the section on its own and confirms "Saved. Applies within a minute. Recorded in the audit log.", and leaving with unsaved changes asks first (FR-17, UX-DR141)
- **Given** a saved change **When** a minute has passed **Then** `OcuTalon.Data.Setting.Get` returns the new values without a restart, `SettingsOps` was the only writer, and the IRIS audit log holds a settings entry with the admin's IRIS user and session (FR-17, FR-9, AD-17, AD-19)
- **Given** an email address that isn't valid, or a time before escalation that isn't a whole number of minutes above zero **When** the admin saves **Then** a field error marks the field, focus moves to the first error, and nothing is saved; a save that fails on the server shows "Couldn't save. Nothing was changed." (UX-DR36, UX-DR141)
- **Given** a user without the admin role **When** they call the on-call section's routes **Then** the routes refuse with 403 and change nothing, as every settings route does from step 2; the online demo, which has no admin, never has an on-call configuration (FR-17, AD-13)
- **Given** automated tests in `OcuTalon.Test.Core` and a Playwright spec under `web/e2e/` **When** an admin saves, corrects and saves the section again **Then** the stored values, the audit entries and the page's states match, and the section works by keyboard with every control labelled (NFR-25, UX-DR125, UX-DR130)

The epic's promise is unchanged. Epics 23 and 24 depend on Epic 36 as a whole, which merges whole. Story 36.4 is planned after Story 36.2. This spec is written for split (A) and can be re-planned from `draft`.

### Governing ADs (Rule 6)

| AD | What it requires here |
| --- | --- |
| AD-1 | Each command is a production message through `CommandsIn` |
| AD-5 | Escalation reuses `ReminderTimer`, so the long-timer list doesn't grow; storage only grows by appending |
| AD-14 | One outbound rule, `Notify`; `Delivery` rows; Got it and `handled` copies; `EmailOut` sends only what it can prove allowed |
| AD-18 | Reminders and their waiter |
| AD-19 | Settings keys are written only by `SettingsOps`; sections and the allow-list |
| AD-29 | Lane B's step story creates the step's verb classes under Lane A's names; stubs refuse |
| AD-33 | Ownership tables are updated in the same change |
| AD-13, AD-24 | Admin-only settings routes; no new grant |

No criterion contradicts an AD's Rule.

### Already met (no new work)
- `handled` notification: kind `handled` exists (`Msg/Enum.cls:26`). Each `*Out` updates its copy through `Delivery.FindByRef` (`Data/Delivery.cls:90`; `WebChat/Out.cls:77`, `Telegram/Out.cls:188,316-344`, `SimPhone/Out.cls:68`).
- `Delivery` lookup by the page's `Ref`: a page Notification carries the page's `Ref` as `DecisionRef`, which `FindByRef` already matches. Refs come from `NewRef()`, so they can't collide with Decision refs. This is the precedent that AD-14's Got it bullet set ("so `Delivery` gets no new column"). Only spine text is needed, and Epic 21's `Delivery` Values 13/14 stay uncontested.
- `approval` dry-run fields: suspend and resume (Item, Before, After), reroute (From, To, Example) and partner warning (Notice, Recipients, Simulated) exist (`DryRun.cls:6-43`). `rollback_setting` fits Item, Field, Before and After, and a page needs no approval (Story 23.4). Spine text only.
- For Story 36.4 (record there): non-admins get 403 on every `/v1/settings` URL (`Web/Api.cls:307` `OnPreDispatch`, `IsAdmin` :342), and online-demo visitors hold no admin role (`Install/Step/Users.cls:46`). The audit entry names the IRIS user and session (`SettingsOps.AuditData` :222, `WriteAudit` :243; pattern in `Test/Core/SettingsAudit.cls:71-86`). `Setting.Get` caches for 60 s (`Data/Setting.cls:39`). "Save changes", "Saved. Applies within a minute. Recorded in the audit log." and "Couldn't save. Nothing was changed." exist (`web/src/app/settings/settings-view.ts:42,43,45`). The unsaved-changes guard exists (`unsaved-guard.ts:21`, `settings-page.ts:254-270`).

### Integration ACs, Consumed-by, Consumes (Rules 1, 2)
- In-story consumers: `CommandsIn` reads the two Routes rows, and `ReminderOps` reads `SetReminder.Kind` (criteria 3 and 4).
- Consumed-by:
  - 23.4 sends `page` Notifications, handles `AckPage` and `Msg.Escalation`, and asks for escalation timers.
  - 23.8 handles `SaveSqlWatch` in `WatchOps`.
  - 24.2 submits `SaveSqlWatch` and builds the partner-contact table and section.
  - 24.3 builds the `page` route, the escalation timer and the page email.
  - 36.4 builds the on-call keys and section.
- Consumes: `CommandsIn` Routes, `Msg.Command`, `Delivery.FindByRef`, and 36.1's paging names.

### Extend, don't copy (Rule 2)
- `AckPage` copies `GotIt`'s two properties instead of subclassing it. `SessionOps` and the routing check `%IsA("…GotIt")`, so a subclass would be taken for a tell-now Got it.
- `Msg.Escalation` follows `Msg/IncidentCommand.cls`.
- New tests extend `TestRoutes`, `Test.Msg.Contracts` and `Test.Schedule.Reminders`, so no new class is needed.

### Decided in-stage
1. **`Notify` is not edited.** Story 24.3 builds the `page` route. Until then a `page` takes the generic route. This leaves Epic 21's appended `DigestEmail` rule uncontested.
2. **`Data.Reminder` is not edited.** Story 24.3 appends `Kind`, `IncidentRef` and `PageRef` at Values 12-14 and builds the waiter branch. 36.2 adds only the request fields and the `not_built` refusal, so a 23.4 timer request before 24.3 never turns into a user-visible reminder.
3. **Partner-contact table: spine only.** Story 24.2 creates it, because no Lane A story reads it before then (the demo's partner warning uses the Lane A fixture `Fix.PartnerContacts`).
4. **The Routes rows land now,** so 23.4 and 23.8 work end-to-end the day they merge. Before then, a submitted `AckPage` or `SaveSqlWatch` reaches a Lane A owner that answers error 5001, so `CommandsIn` returns `failed`, and nothing changes. No UI or tool submits either before 23.4, 23.8 or 24.2. A plain `not_built` instead needs a Lane A stub branch answering 5003. That is recommended for the runner as an addendum to 36.1, or as the first task of 23.4 and 23.8 (Lane A's files, not this story's).
5. **Any `Kind` but "" or `reminder` is `not_built`.** Story 24.3 narrows this to `escalation` from origin `system`.
6. **Bounds:** `SaveSqlWatch.Query` MAXLEN 4000; on-call minutes 1-1440 (spine; Story 36.4 enforces them).
7. **The on-call person.** An "OcuTalon user" is an IRIS user with an OcuTalon session row (`Data.Session.IrisUser`, `ForUser` :84). A user is paged by email at an address the admin enters for them, because the delivered code has no OcuTalon-side address for a user. Pairing is per session (`Ownership.Pairing` :562).
8. **New units:** `new_units: none`. The changed tests sit in `lane-b` areas Msg, Core and Schedule.
9. **Not judge-visible.** Story 36.2 is contracts only. Story 36.4's section changes nothing a judge can see happen until Epics 23 and 24 send pages. So neither story adds a More to try item or a GUIDE.md line; the item belongs with the story that delivers the first page. The registry holds 16 items, not 14, and K29 and K30 are taken too. Its count is pinned in README (`web/scripts/more-to-try-view.test.mjs:408-417`), a contended file.
10. **Real-runtime tests (Rule 3):** exempt here. No user-facing surface and no route change.

### Spine additions (the implement stage writes them; within step 5's text, pending ruling V6)
- **AD-14, Notify (after the digest bullets):**
  - From Story 24.3, kind `page` goes only to the paged person's chosen channels:
    - the web chat of that user's session;
    - the paired Telegram chat of that session (`telegram` chosen and paired at send time; `TelegramOut`'s delivery is Story 23.4);
    - `EmailOut` (`email` chosen).
  - A person with no paired chat, or one given only as an address, gets email only. Until 24.3, a `page` takes the generic route.
  - A page Notification's `DecisionRef` is the page's `Ref`. Every `*Out` records it as its `Delivery` row's `DecisionRef`, and `Delivery.FindByRef(pageRef, channel, ownerRef)` finds each copy, so `Delivery` gets no new column.
  - On acknowledgement, the paging owner sends one `handled` Notification (DecisionRef = the page's Ref) per session holding a copy, and each `*Out` updates its copy to `handled.marked`.
- **AD-14, EmailOut (a third allowed send; Story 24.3, veto V5):**
  - It handles a `page` Notification only when its `DecisionRef` is a `Data.Page` row whose `Channels` include `email`.
  - It sends to exactly the address of the on-call key for the page's `Role` (`oncall.primary.email` or `oncall.backup.email`), read from its row at send time, and never to an address from the notification's text or slots.
  - At most one email per page row, claimed by a `Delivery` row of channel `email` with the page's Ref.
  - It answers `not_available` on the online demo, and sends nowhere but the CI mock in tests (`OCUTALON_TEST_PLAIN_SMTP` with host `mock`).
  - The email carries no acknowledgement (36.1).
- **AD-18, escalation timers:**
  - `SetReminder` gains `Kind` ("" or `reminder`, or `escalation`), `IncidentRef` and `PageRef`.
  - From Story 24.3, `ReminderOps` accepts an escalation only from origin `system` (the paging owner) with `DelaySeconds`. Its row has `SessionRef` `instance`, appears in no `ListReminders` and no live event, and is cancelled by `CancelReminder` from `system`.
  - At its due time the waiter (`ReminderTimer` → `Schedule.Reminder.Wake`) sends `OcuTalon.Msg.Escalation` (IncidentRef, PageRef) to `IncidentManager` asynchronously, instead of a Notification.
  - The reconciler re-arms it like a reminder. `Data.Reminder` appends `Kind`, `IncidentRef` and `PageRef` (24.3).
  - Until 24.3, `ReminderOps` answers `not_built` and stores nothing (36.2).
- **AD-19, on-call keys (product keys in `OcuTalon.Data.Setting`, on the allow-list, written only by `SettingsOps` from the on-call section, Story 36.4, read through `Setting.Get`):**
  - `oncall.primary.user` and `oncall.backup.user`: an IRIS user name with an OcuTalon session, or "".
  - `oncall.primary.email` and `oncall.backup.email`: the address pages are emailed to, or "".
  - `oncall.primary.channels` and `oncall.backup.channels`: a comma list in the order `telegram,email`, default `telegram,email`. `telegram` is accepted only for a user whose session is paired at save time. The saved channels must include one the person can be reached on.
  - `oncall.escalationMinutes`: a whole number from 1 to 1440, default 15.
  - A role is configured when its user or its address is set. With no on-call person, nothing is paged.
  - The online demo never has these keys: the section is refused `not_available` and absent from `GET /api/v1/settings`.
  - Audit entries hold from/to values like the step-2 keys (veto V3).
- **AD-19, step-5 settings sections (all admin-only through `OnPreDispatch`; on the online demo each answers 409 `not_available` and is absent from the GET):**
  - `on-call`: `POST /api/v1/settings/on-call`, kind `oncall`, its own saver (Story 36.4).
  - `partner-contacts`: `POST /api/v1/settings/partner-contacts`, kind `contacts`, its own saver writing the partner-contact table (Story 24.2).
  - `sql-watches`: `POST /api/v1/settings/sql-watches`. It submits `SaveSqlWatch` to `WatchOps`, not `SaveSettings` (Story 24.2).
- **AD-1/AD-29, verbs:**
  - `OcuTalon.Msg.Command.AckPage` (`Ref`, the page's Ref; `Channel` `web`, `phone` or `telegram`) comes from `web_user`, `web_admin` and `telegram`, with owner `IncidentManager`. Telegram's comes only from the paired chat (23.4). Email never acknowledges. It is not a tool verb.
  - `OcuTalon.Msg.Command.SaveSqlWatch` (`Action` `save` or `remove`, `CheckRef`, `Name`, `Query`, `IntervalMinutes`) comes from `web_admin` only, with owner `WatchOps` (23.8). It is not a tool verb.
  - Both are created and routed by Story 36.2. Lane A never edits them.
- **AD-12/AD-16, `approval` dry run:** `rollback_setting` uses DryRun `Item` (the target item), `Field` (the setting), `Before` and `After`. No new field; a page raises no approval.
- **AD-33:**
  - Lane B tables gain `PartnerContact` (`^OcuTalonP.PartnerContact`, Story 24.2): Ref, Name (128), Email (254), Productions (a JSON array of {namespace, production}, MAXLEN 4000), CreatedAt and UpdatedAt (UTC). It is written only by `SettingsOps` and read through `PartnerContact.ForProduction(namespace, production)`. It is configuration with no purge: a removed contact's row is deleted.
  - Cross-area rows: `Msg.Escalation`, `AckPage` and `SaveSqlWatch` (B, 36.2).

### Contended overlaps

| File | What 36.2 touches | Kind |
| --- | --- | --- |
| `Core/CommandsIn.cls` (Epic 21: `ItemRunning` :288) | Two rows at the end of `XData Routes` (after `ListPinnedMemories`) | Append-only, in a different block |
| `Msg/Enum.cls` | `,page` at the end of NOTIFICATIONKIND | One-name append |
| `Msg/Escalation.cls`, `Msg/Command/AckPage.cls`, `Msg/Command/SaveSqlWatch.cls` | New files | Append-only |
| `Msg/Command/SetReminder.cls` | Three properties and storage Values 5-7 | Append-only (no other lane) |
| `Schedule/ReminderOps.cls` | One guard line at the top of `Set` | Non-append edit, but no other lane changes the file |
| `Test/Msg/Contracts.cls`, `Test/Core/CommandsRouting.cls`, `Test/Schedule/Reminders.cls` | Expected strings and lists, an appended XData entry, appended methods | Non-append edits to test data; no other lane's diff touches them |
| `Core/Rule/Notify.cls`, `Data/Delivery.cls`, `Core/SettingsOps.cls`, `Msg/Catalog/Core.cls`, `Test/Core/SettingsSave.cls`, `Test/Core/Routing.cls` (Epic 21) | Nothing | — |
| `Data/BackgroundCheck.cls`, `Checks/Process.cls`, `Checks/Coverage.cls` (Epic 22) | Nothing | — |
| `README.md`, `GUIDE.md` (Epics 0, 21) | Nothing | — |
| `Msg/Catalog/Watch.cls`, `src/short-names.tsv` (36.1) | Nothing | — |
| Spine (36.1, Epic 21) | New bullets in AD-14 (after Epic 21's digest-email bullets), AD-18, AD-19, AD-29 and AD-33 | Append-only bullets in shared planning text |
| EXPERIENCE.md (36.1, Epic 21) | A new "Settings (step 5)" catalog block after "Settings and requests (step 4)", plus lines under Step 5 | Appended block |

Story 36.4's overlaps, for its plan:
- `Core/SettingsOps.cls`: `XData Sections` row, `ALLOWLIST` names, one dispatch line in `Save`, one branch in `Values`, new methods at the end. Epic 21 edits only `Field()`'s channels branch.
- `Web/Api.cls` UrlMap: one route. `Test/Web/Api.cls` `TestRoutes`: 38 → 39.
- `Test/Core/SettingsSave.cls`: `TestAllowList` and `TestValues`. Epic 21 edits only `TestDigestSection`.
- `web/src/app/settings/settings-page.ts` (`@switch` and imports) and `settings-view.ts` (`SETTINGS_SECTIONS`, `SETTINGS_TEXTS`). Epic 21 edits both near the same lines, so expect merge conflicts.
- `web/scripts/settings-view.test.mjs` (Epic 21 too).
- A new `on-call-section.ts`.
- A new `web/e2e/settings/on-call.spec.ts`.

### Veto and security items (pending the Planner's ruling; online-demo behaviour stated)
- **V1, new routes.**
  - Recommended: spine names `POST /api/v1/settings/on-call` (36.4), `/partner-contacts` and `/sql-watches` (24.2). All are admin-only by the existing `OcuTalonAdmin` check.
  - Real-HTTP tests (36.4/24.2): `OcuTalonUser` gets 403 and nothing changes; the README admin succeeds.
  - Online demo: 403 for every visitor (no admin), and 409 `not_available` even for an admin; the sections are absent.
- **V2, new stored data.**
  - The on-call keys and their format (Spine additions › AD-19): configuration kept until changed, with no purge.
  - The partner-contact table: its fields, owned by Lane B, written only by `SettingsOps`, no purge, deleted on removal.
  - `SetReminder` grows by three fields (append-only storage). Escalation rows are purged with reminders (24.3).
  - Online demo: none of it is written.
- **V3, people's contact data.**
  - On-call user names and email addresses, and partner names and addresses, are stored as plain configuration.
  - Recommended: audit the on-call keys like the other product keys, with from/to values and addresses. The IRIS audit log is admin-only, and an admin must see who was put on call.
  - Alternative: redact addresses in the audit through `Redact.SensitiveKey`.
  - Never in a production message, log or trace beyond the audit entry.
  - Online demo: none.
- **V4, grants and privileges.** None: no role, no grant, and the user role is not widened. Story 36.4's user list (IRIS user names of session rows, each with a paired flag) is shown only to admins.
- **V5, outward actions.**
  - (a) Recommended: a page email to an on-call address only through the EmailOut contract above. It goes only to the role's configured key address, only for a `Data.Page` row, once per page, never on the online demo, and only to the CI mock in tests. Real mail goes out only on a local install after an admin has connected an outgoing server and set an address.
  - Telegram pages go only to a chat that user paired (23.4).
  - Nothing outward is sent in 36.2.
  - (b) Alternative: email pages only to the mailbox owner's own address (`email.address`). That fails the "an email address" person in the criterion.
  - Online demo: no page is ever sent (there is no on-call configuration, and `EmailOut` answers `not_available`).
- **V6, AD amendments.** The additions to AD-14, AD-18, AD-19, AD-1/AD-29 and AD-33 above, within step 5's existing text.
- **V7, public text.** Everything below.

### Proposed public text (verbatim; none ships until accepted; target EXPERIENCE.md › Message Catalog › new block "Settings (step 5)", web strings in `web/src/app/settings/settings-view.ts` `SETTINGS_TEXTS`, each with a `web/scripts/ux-strings.test.mjs` SOURCES `ruled` entry)

Reused as they are: "Save changes", "Saved. Applies within a minute. Recorded in the audit log.", "Couldn't save. Nothing was changed." (`settings-view.ts:42-45`), the unsaved-changes dialog texts (`:48-50`), "Only OcuTalon admins can open settings." (`Web/Api.cls:186`), the channel names "Telegram" and "Email", "Check every" (Msg.Catalog.Core, step 4), and `CommandsIn` `MESSAGENOTBUILT` "This part of OcuTalon isn't built yet. Nothing was changed."

On call (Story 36.4):
- `settings.onCallSection` (nav label and heading): "On call"
- `settings.onCallHelp`: "Choose who OcuTalon pages when an incident starts, and who it pages next if nobody presses Got it in time."
- `settings.onCallNotYet` (shown while `OcuTalon.Data.Page` isn't compiled, so the text claims only what the product does): "OcuTalon doesn't send pages yet. It keeps these choices for when it does."
- `settings.onCallPrimary` (group legend): "On-call person"
- `settings.onCallBackup` (group legend): "Backup"
- `settings.onCallPerson` (select label): "Person"; options `settings.onCallNobody` "Nobody", each OcuTalon user name, and `settings.onCallByEmail` "Someone else, by email"
- `settings.onCallEmail` (field label): "Email address for pages"
- `settings.onCallChannels` (group legend): "Page by"
- `settings.onCallTelegramUnpaired` (beside a Telegram option that can't be chosen, for a user): "{user} hasn't paired Telegram, so OcuTalon can't message them there yet. They can pair it on their own OcuTalon page."
- `settings.onCallTelegramEmailOnly` (the same, for an address-only person): "Telegram needs an OcuTalon user with a paired chat."
- `settings.onCallMinutes` (field label): "Minutes before paging the backup"
- `settings.onCallMinutesHelp`: "15 unless you change it."
- `settings.badEmail` (field error; also partner contacts): "Enter an email address such as name@example.com. Nothing was changed."
- `settings.onCallBadMinutes` (field error): "Enter a whole number of minutes from 1 to 1440. Nothing was changed."
- `settings.onCallNoChannel` (field error on Page by): "Choose a way to reach this person: Telegram needs a paired chat, email needs an address. Nothing was changed."
- `settings.onCallUnknownUser` (field error on Person): "{user} isn't an OcuTalon user any more. Choose again. Nothing was changed."
- `settings.onCallOffOnDemo` (the 409 `not_available` body): "The online demo has no on-call person, because it has no admin. On your own install, an admin chooses one here."

Partner contacts (Story 24.2):
- `settings.partnersSection`: "Partner contacts"
- `settings.partnersHelp`: "Partner warnings go only to the people listed here, and only after you approve each one."
- `settings.partnerName`: "Name"; `settings.partnerEmail`: "Email address"; `settings.partnerProductions`: "Productions it concerns"; `settings.partnerAdd`: "Add contact"; `settings.partnerRemove`: "Remove"
- `settings.partnerRemoveConfirm`: "Remove {name}? Partner warnings will stop going to {address}."
- `settings.partnerBadName`: "Enter a name of 1 to 128 characters. Nothing was changed."
- `settings.partnerNoProduction`: "Choose at least one production. Nothing was changed."
- `settings.partnersOffOnDemo`: "Partner contacts are off on the online demo, where partner warnings go to simulated contacts. They work on your own install."

SQL query watches (Story 24.2; the refusal reasons come from `WatchOps`, Story 23.8):
- `settings.sqlSection`: "SQL query watches"
- `settings.sqlHelp`: "OcuTalon runs each query on its schedule as a user that can only read, and tells you when the result changes."
- `settings.sqlName`: "Name"; `settings.sqlQuery`: "Query (one SELECT statement)"; `settings.sqlMinutes`: "minutes"; `settings.sqlSave`: "Save query"; `settings.sqlRemove`: "Remove"
- `settings.sqlColumns` (list headings): "Schedule", "Last run", "Last result"
- `settings.sqlBadName`: "Enter a name of 1 to 128 characters. Nothing was changed."
- `settings.sqlOffOnDemo`: "SQL query watches are off on the online demo. They work on your own install."

GUIDE.md and More to try: none (Decided in-stage 9).

## Verification

Every command uses the lane-B variables `OCUTALON_LOCK_DIR=<lock-dir>/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=36 stage=implement'` (written `<lane-b vars>`). The fresh tag is `e36s2i` and the warm tag `e36s2iw`. Run one command per call with `timeout: 600000`, each at most about 150 s, and never on slot B. At the end, even after a failure, run `<lane-b vars> OCUTALON_RUN_TAG=e36s2iw bash ci/warm.sh down` and `<lane-b vars> OCUTALON_RUN_TAG=e36s2i bash ci/iris.sh teardown`.

**Commands:**
- (loop) `<lane-b vars> OCUTALON_RUN_TAG=e36s2iw bash ci/warm.sh up` -- once per stage; expected: a ready stack
- (loop) `<lane-b vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e36s2iw bash ci/iris.sh class <C>`, one call each for `OcuTalon.Test.Msg.Contracts`, `OcuTalon.Test.Core.CommandsRouting` and `OcuTalon.Test.Schedule.Reminders` -- expected: `CLASS ... passed`
- (loop) `bash docker/tests/test-storage.sh` -- expected: pass (SetReminder append-only; new classes)
- (loop) `npm --prefix web test` -- expected: pass (`catalog.test.mjs` reads `Enum.cls`)
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: `"ok": true`
- (once) `<lane-b vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e36s2iw bash ci/iris.sh shard lane-b@Contract,Core,Data,Live --part k/4` for k = 1..4, then `shard lane-b@rest --part k/3` for k = 1..3, one call each -- expected: all passed. Raise n if a part nears 150 s; `--part` on a piece is (inference).
- (once) `<lane-b vars> OCUTALON_RUN_TAG=e36s2i bash ci/iris.sh class OcuTalon.Test.Msg.Contracts` -- a fresh stack; expected: passed
- (once) `bash docker/tests/test-ci-config.sh`, then `bash ci/checks.sh`, one per call -- expected: pass

**Shared surfaces:**
- `Msg.Enum` NOTIFICATIONKIND (`Test/Msg/Contracts.cls:72`, `web/scripts/catalog.test.mjs`)
- The `CommandsIn` Routes table and the verb list (`TestRoutes` count, `Test/Msg/Contracts.cls:42`, `Test/Core/CommandsStep4.cls:310,408`)
- The `Contracts` XData
- `SetReminder` storage (`test-storage.sh`)
- The spine's ownership tables

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19; the implement stage records each as `mutation: <change> → <red test>`):**
- Drop `page` from NOTIFICATIONKIND → `TestEnumerations`
- Remove the `AckPage` Routes row → `TestRoutes`
- Add `web_user` to `SaveSqlWatch`'s origins → `TestStepFiveRefusals`
- Remove the Kind guard in `ReminderOps.Set` → `TestEscalationNotBuilt`
- Drop `PageRef` from `Msg.Escalation` → `TestContracts`

## Auto Run Result

Status: blocked
Blocking condition: intent gap -- Story 36.2 is two standard-size stories after the delivered parts are removed. Proposed split (A), recommended: Story 36.2 keeps its key and its first criterion with both "And" clauses (step 5's Lane B contracts in the spine and as code contracts, plus the text proposals), retitled "Fix Lane B's step 5 contracts: paging, escalation and the SQL query watch verb". A new sibling, Story 36.4 "Set the on-call person and backup in Settings", takes the original user story and the five on-call section criteria verbatim (listed under Design Notes › Proposed split), depends on 36.2, and is planned next in this epic, in Lane B's files. (B), the alternative: 36.2 keeps its title and the section, and 36.4 takes the contracts; this leaves the "Story 36.2 fixes" references in Epics 23 and 24 pointing at the wrong story. This spec is planned for (A). After the ruling, set `status: draft` and re-dispatch to validate it.
