---
title: 'Story 36.2: Fix Lane B''s step 5 contracts: paging, escalation and the SQL query watch verb'
type: 'feature'
created: '2026-11-12'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-36-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-36-1-record-the-setting-history-of-each-watched-production.md'
warnings: ['oversized']
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

- `src/ocutalon/cls/OcuTalon/Msg/Enum.cls:30` -- NOTIFICATIONKIND, a comma list; pinned by `Test/Msg/Contracts.cls:72`. Web input (`ci/units.sh:219`); `web/scripts/catalog.test.mjs:25` reads this file.
- `src/ocutalon/cls/OcuTalon/Msg/IncidentCommand.cls` (29 lines) and `Msg/Tick.cls` (32 lines) -- templates for `Msg/Escalation.cls` (`Ens.Request`, storage subscript `"Escalation"`).
- `src/ocutalon/cls/OcuTalon/Msg/Command/GotIt.cls` -- the sibling of `AckPage`: the same props, `Ref` (22) and `Channel` (32).
- `src/ocutalon/cls/OcuTalon/Msg/Command/SendEmail.cls`, `ProposeFix.cls` -- the latest verb classes made by a contracts story (35.2, Epic 23); `AckPage` and `SaveSqlWatch` take their shape (`Extends OcuTalon.Msg.Command`, a one-line class comment naming the AD and owner, committed storage).
- `src/ocutalon/cls/OcuTalon/Msg/Command/SetReminder.cls:6-35` -- props Text, DueAt, DelaySeconds, LocalDueAt; storage Values 1-4.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- `XData Routes` :325-366 (`{verb, owner, origins}`; 38 rows, last `ListPinnedMemories` :365); `Carry` :100 (tool rule :109 → `MESSAGENOTFROMTOOL` :72; origin rule → `MESSAGENOTALLOWED` :78; `IsStub` → `not_built` :134/:276); `TOOLVERBS` :62; `MESSAGENOTBUILT` :84. Epic 21 changes only `ItemRunning` :288.
- `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls:98-113` -- `Set`. The first check is `SessionExists`, so the Kind guard goes before it. `Result(ok, outcome, message)` :330 builds the answer; `Refuse` :315 is outcome `refused` and must not be used for the guard.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls:299-312` -- read only (Lane A). An unknown request class gets error 5001, which `CommandsIn` maps to `failed`. `Watch/Ops.cls:71-81` (WatchOps, read only) has a `MessageMap` with StartWatch and StopWatch only, so an unmapped `SaveSqlWatch` gets the Ens not-handled error, not 5003, and `CommandsIn` answers `failed` (inference, from the code).
- `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls:216` -- `XData Named` checks that the named `SetReminder` properties exist (existence only), so the append needs no change there.
- `src/ocutalon/cls/OcuTalon/Data/Delivery.cls:90` `FindByRef(ref, channel, ownerRef)` -- matches `DecisionRef`. It is the page-copy lookup, reused with no schema change.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls:255-281` -- the `GotIt` → `Handled` → `handled` Notification pattern that the page acknowledgement mirrors (23.4/24.3).
- `src/ocutalon/cls/OcuTalon/Live/Payload/Part/DryRun.cls:6-43` -- the existing dry-run fields (Item, Field, Before, After, From, To, Example, Notice, Recipients, Simulated).
- Tests: `Test/Msg/Contracts.cls` (:42 verbs with the common fields, :72 enum strings, :83 parameter names, `XData Contracts` :161+ with entries for `SetReminder` :254 and `GotIt` :426); `Test/Core/CommandsRouting.cls:64` `TestRoutes` (12 verbs, probe owner); `Test/Schedule/Reminders.cls` (SetReminder through ReminderOps).
- Spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- AD-14 L490-508 (Notify L497, `EmailOut` L503, Got it L505), AD-18 L585-634, AD-19 L635-702 (step-2 keys L700, saving L701, per-person L662), AD-29 L1044-1099 (`ProposeFix` L1098), AD-33 L1162-1174, Tables L1418, cross-area rows near L1463, REST row L1220. Line numbers move after 36.1's spine edits; find the blocks by heading.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- Later Steps › Step 5 L1080; the Message Catalog block "Settings and requests (step 4)" L971-1024 is the model for a new "Settings (step 5)" block.

## Tasks & Acceptance

**Execution:**
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- write Design Notes › Spine additions as bullets in AD-14, AD-18, AD-19, AD-1/AD-29, AD-12/AD-16 and AD-33, found by heading. Then run `uv run --no-cache _bmad/scripts/memlog.py append --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16 --type decision --text "<the step-5 Lane B contracts, Story 36.2>"`, then `lint_spine.py` (needs `"ok": true`), and refresh `updated:` (Rule 20).
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
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- only for texts the runner has reported accepted when implement runs: a "Settings (step 5)" Message Catalog block after "Settings and requests (step 4)", plus Later Steps › Step 5 lines, each accepted text verbatim with its key. With no ruling reported, write nothing there (Decided in-stage 12).

**Acceptance Criteria:**
- Given the spine after this story, when step 5's Lane B contracts are looked up, then every item of the first criterion is there as Design Notes › Spine additions write it: the three settings sections and their routes, the on-call keys, the partner-contact table, the page notification and its route, the escalation kind on `Reminder`, the `approval` dry-run fields, `AckPage` and `SaveSqlWatch`, the `handled` notification and the `Delivery` lookup by the page's `Ref`. AC 1's check under Verification prints nothing, and `lint_spine.py` reports `"ok": true`.
- Given the compiled package, when `Test.Msg.Contracts` runs, then `Msg.Escalation`, `AckPage`, `SaveSqlWatch` and `SetReminder` have exactly the properties above, the `page` kind is in NOTIFICATIONKIND, and Lane A's classes are untouched (`git diff --stat` lists only the files in Execution).
- Given `CommandsIn` (the consumer of the new rows, Rule 1), when the I/O matrix's commands are submitted, then each reaches its owner or is refused exactly as the matrix says.
- Given `ReminderOps` (the consumer of `SetReminder.Kind`), when an escalation timer is requested before Story 24.3, then it is refused `not_built` and nothing is stored or started.
- Given the texts in Design Notes › Proposed public text, when the runner reports the Planner's ruling, then only accepted texts reach EXPERIENCE.md, each with its key. No code ships any of them in this story.

## Spec Change Log

- 2026-11-12, Contest Planner rulings on V1-V7 (binding) applied by the runner to Design Notes and Proposed public text; no re-plan needed (the contracts' plan is unchanged; the texts are now accepted, so EXPERIENCE.md gets the Settings (step 5) block per Decided 12).

- 2026-11-12, runner ruling (doctrine U5 decide, split 2 of 6; logged `ruling` in cycle-log-epic-36.md): split (A) applied in epics.md. Story 36.2 is retitled "Fix Lane B's step 5 contracts: paging, escalation and the SQL query watch verb" (sprint key `36-2-fix-lane-b-s-step-5-contracts-paging-escalation-and-the-sql`; this file renamed to match) and keeps the first criterion with its "And" clauses; Story 36.4 "Set the on-call person and backup in Settings" takes the user story and the five on-call section criteria verbatim (planned next). Earlier, Story 36.3 took the README Jira-example criterion (split 1 of 6). Status reset to `draft` for re-planning and validation as the contracts story; the on-call section's design notes remain as input for 36.4's plan.
- 2026-11-12, re-plan (cycle_iteration 2): the blocking split condition is dropped (`### Proposed split` is now a short record of the ruling); the `multiple-goals` warning is cleared; the on-call-only notes are grouped under `### For Story 36.4 (input to its plan)`; Code Map line anchors re-checked at `6c55d82c362a55c9e0747db25086545642e3cd38`; Decided in-stage 4 corrected (WatchOps's answer) and 11-15 added (the second "And" clause's reading, the EXPERIENCE.md condition, online-demo behaviour, 36.1 order, the local regression sizing); an acceptance mapping, AC 1's spine check and one mutation per AC added; the Verification lines resized (no whole `ci/checks.sh` line). The frozen intent block is unchanged. KEEP: the Spine additions, the Proposed public text and the veto items, verbatim.

## Review Triage Log

## Design Notes

### Planner rulings (2026-11-12, binding; `.coordination/prompts/story-362-rulings-20261112.md`)
- Splits approved: 36.2 = contracts; 36.4 (on-call Settings); 36.3 (Jira docs link, after 22.6). Order 36.1 -> 36.2 -> 36.4 -> 36.3.
- V1 routes named in the spine (admin-only; demo visitors 403, an admin 409 `not_available`; 36.2 adds none): approved.
- V2 stored data: approved (a removed contact's row is deleted; the demo never writes; `SetReminder` append-only).
- V3: audit WITH from/to values, ONLY in the IRIS audit log; in no other log, trace, digest, notice or eval output; ONE leak-scan test pins it (36.4 / 24.2). 36.2 writes this rule into the spine.
- V4 (no grants), V5 (page email only to the configured address for that role, only for a real page row, once; CI mail mock only; Telegram only to the paired chat; 36.2 sends nothing; never on the demo), V6 (AD additions): approved. The demo-safety pin that `SaveSqlWatch` is refused from `web_user`: approved.
- V7 text: approved verbatim EXCEPT `settings.onCallOffOnDemo` and `settings.sqlHelp` (rewritten below); `settings.partnersHelp` approved on condition 24.2 pins both halves. The strings SHIP in 36.4 and 24.2 (`settings-view.ts`), not in 36.2; 36.2 writes the accepted texts into EXPERIENCE.md › Message Catalog › "Settings (step 5)" (they are now accepted), with the two replacements and the two conditions noted. No GUIDE or More-to-try line for 36.2.

**Ledger inbox (Rule 17):** none owned by `36-2-fix-lane-b-s-step-5-contracts-paging-escalation-and-the-sql` (`owned_ledger=0`).

### Proposed split (ruled)

Split (A) was ruled by the runner on 2026-11-12 (doctrine U5, split 2 of 6; Spec Change Log). This story is the contracts half: the first criterion of `epics.md` Story 36.2 with its two "And" clauses. Story 36.4 "Set the on-call person and backup in Settings" holds the original user story and the five on-call section criteria verbatim (`epics.md` Story 36.4), and is planned after this story. Story 36.3 holds the README Jira-example criterion (split 1 of 6). Every "Story 36.2 fixes" reference in Epics 23 and 24 stays true. Nothing here blocks.

### Acceptance mapping (epics.md Story 36.2 → this spec)
- The first criterion (the spine's step-5 Lane B additions) → AC 1 and Design Notes › Spine additions.
- "And" 1 (the `OcuTalon.Msg` / `OcuTalon.Data` appends 36.1 asks for) → ACs 2-4 (Decided in-stage 11).
- "And" 2 (section names and texts proposed to the author; nothing ships unaccepted) → AC 5 and Design Notes › Proposed public text.

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
| AD-12, AD-16 | The `approval` payload's dry-run fields (spine text only) |
| AD-13, AD-24 | Admin-only settings routes; no new grant |

No criterion contradicts an AD's Rule. (Spine headings at `6c55d82c362a55c9e0747db25086545642e3cd38`: AD-1 L109, AD-5 L203, AD-12 L419, AD-13 L435, AD-14 L490, AD-16 L555, AD-18 L585, AD-19 L635, AD-24 L916, AD-29 L1044, AD-33 L1162.)

### Already met (no new work)
- `handled` notification: kind `handled` exists (`Msg/Enum.cls:30`). Each `*Out` updates its copy through `Delivery.FindByRef` (`Data/Delivery.cls:90`; `WebChat/Out.cls:77`, `Telegram/Out.cls:188,316-344`, `SimPhone/Out.cls:68`).
- `Delivery` lookup by the page's `Ref`: a page Notification carries the page's `Ref` as `DecisionRef`, which `FindByRef` already matches. Refs come from `NewRef()`, so they can't collide with Decision refs. This is the precedent that AD-14's Got it bullet set ("so `Delivery` gets no new column"). Only spine text is needed, and Epic 21's `Delivery` Values 13/14 stay uncontested.
- `approval` dry-run fields: suspend and resume (Item, Before, After), reroute (From, To, Example) and partner warning (Notice, Recipients, Simulated) exist (`DryRun.cls:6-43`). `rollback_setting` fits Item, Field, Before and After, and a page needs no approval (Story 23.4). Spine text only.
- Refusal texts the contracts return: all reused (`MESSAGENOTBUILT`, `MESSAGENOTALLOWED`, `MESSAGENOTFROMTOOL` in `CommandsIn`); no new text ships in code.

### Integration ACs, Consumed-by, Consumes (Rules 1, 2)
- In-story consumers (Integration ACs): `CommandsIn` reads the two Routes rows and delivers `AckPage` to the `IncidentManager` slot and `SaveSqlWatch` to the `WatchOps` slot (AC 3, `TestRoutes` with the probe owner); `ReminderOps` reads `SetReminder.Kind` and refuses an escalation (AC 4, `TestEscalationNotBuilt`). The real Lane A owners consume them first in 23.4 and 23.8.
- Consumed-by:
  - 23.4 sends `page` Notifications, handles `AckPage` and `Msg.Escalation`, and asks for escalation timers.
  - 23.8 handles `SaveSqlWatch` in `WatchOps`.
  - 24.2 submits `SaveSqlWatch` and builds the partner-contact table and section.
  - 24.3 builds the `page` route, the escalation timer and the page email.
  - 36.4 builds the on-call keys and section.
- Consumes: `CommandsIn` Routes, `Msg.Command`, `Delivery.FindByRef`, and 36.1's paging names.

### Extend, don't copy (Rule 2)
- `AckPage` and `SaveSqlWatch` extend `OcuTalon.Msg.Command`, as every verb does (siblings `SendEmail`, `ProposeFix`).
- `AckPage` copies `GotIt`'s two properties instead of subclassing it. `SessionOps` and the routing check `%IsA("…GotIt")`, so a subclass would be taken for a tell-now Got it.
- `Msg.Escalation` follows `Msg/IncidentCommand.cls`.
- The two Routes rows follow the existing rows (`ProposeFix` → `IncidentManager`; `StartWatch` → `WatchOps`).
- New tests extend `TestRoutes`, `Test.Msg.Contracts` and `Test.Schedule.Reminders`, so no new class is needed. (35.2 made a new `Test/Core/CommandsStep4.cls`; here two routes and one refusal fit the existing classes.)

### Decided in-stage
1. **`Notify` is not edited.** Story 24.3 builds the `page` route. Until then a `page` takes the generic route. This leaves Epic 21's appended `DigestEmail` rule uncontested.
2. **`Data.Reminder` is not edited.** Story 24.3 appends `Kind`, `IncidentRef` and `PageRef` at Values 12-14 and builds the waiter branch. 36.2 adds only the request fields and the `not_built` refusal, so a 23.4 timer request before 24.3 never turns into a user-visible reminder.
3. **Partner-contact table: spine only.** Story 24.2 creates it, because no Lane A story reads it before then (the demo's partner warning uses the Lane A fixture `Fix.PartnerContacts`).
4. **The Routes rows land now,** so 23.4 and 23.8 work end-to-end the day they merge. Before then, a submitted `AckPage` or `SaveSqlWatch` reaches a Lane A owner that answers an error other than 5003 (IncidentManager error 5001; WatchOps the Ens not-handled error of its `MessageMap`, inference), so `CommandsIn` returns `failed`, and nothing changes. No UI or tool submits either before 23.4, 23.8 or 24.2. A plain `not_built` instead needs a Lane A stub branch answering 5003. That is recommended for the runner as an addendum to 36.1, or as the first task of 23.4 and 23.8 (Lane A's files, not this story's).
5. **Any `Kind` but "" or `reminder` is `not_built`.** Story 24.3 narrows this to `escalation` from origin `system`.
6. **Bounds:** `SaveSqlWatch.Query` MAXLEN 4000; on-call minutes 1-1440 (spine; Story 36.4 enforces them).
7. (Moved to `### For Story 36.4`.)
8. **New units:** `new_units: none`. The changed tests sit in `lane-b` areas Msg, Core and Schedule (`ci/units.sh:21`); no new test class.
9. **Not judge-visible.** Story 36.2 is contracts only, and Story 36.4's section changes nothing a judge can see happen until Epics 23 and 24 send pages. So this story adds no More to try item and no GUIDE.md "New since 1.0.0" line; the item belongs with the story that delivers the first page. The registry holds 16 items and K25-K30 are taken. Its count is pinned in README (`web/scripts/more-to-try-view.test.mjs:408-417`), a contended file.
10. **Real-runtime tests (Rule 3):** exempt here. No user-facing surface and no `/api/v1` route, so the real-HTTP route rule (LIVE `OcuTalonUser` 403, README admin success, isolation) does not apply; 36.4 and 24.2 carry it for their routes.
11. **The second "And" clause.** 36.1's asks in `OcuTalon.Msg` (`Msg.Escalation`, `AckPage`, `SaveSqlWatch`, the `page` kind, the escalation fields on the request) are created now. Its asks in `OcuTalon.Data` (`Kind`/`IncidentRef`/`PageRef` on `Data.Reminder`, the `PartnerContact` table) are fixed by name, fields and owner in the spine and created by their first writer: 24.3 and 24.2. That matches the other epics' text: "a fixture for the escalation timer (until Lane B's Story 24.3 merges)" (epics.md L7960) and "the partner-contact table, fixed by Story 36.2 and filled by Story 24.2, or a test fixture with its fields until Story 24.2 merges" (L7973). It also keeps an unread column or table out of the schema (Decided 2 and 3).
12. **EXPERIENCE.md.** The proposal is this spec's `### Proposed public text`; the runner forwards it. Implement writes only the texts the runner has reported accepted by then. If none are reported, it writes nothing and AC 5 holds (no text ships). Later acceptances land with 36.4 (on-call) and 24.2 (partner contacts, SQL watches), each of which uses only accepted texts.
13. **Online demo.** No code in this story shows or changes anyone's data. `SetReminder` with an escalation `Kind` is refused everywhere. `SaveSqlWatch` from `web_user`, the only origin a demo visitor has (no admin), is refused `not_allowed`, pinned by `TestStepFiveRefusals`. An `AckPage` from a demo visitor reaches `IncidentManager`, which answers `failed` and changes nothing until 23.4, which owns its demo behaviour. The on-call keys, partner contacts and SQL watches do not exist anywhere yet; the spine states they never exist on the demo (V1-V5).
14. **36.1 order.** Implement does not wait on 36.1: the bullets use 36.1's fixed names and go at the end of each AD block's relevant list, found by heading (line numbers move). Where 36.1's own bullets are already there, this story's go after them; a merge conflict between the two is resolved by keeping both.
15. **Local regression sizing.** The `(once)` regression runs `lane-b@Contract,Core,Data,Live` (93 classes) and `lane-b@Web` (its API tests submit through `CommandsIn`) in warm parts, and the Msg and reminder classes one per call. It leaves `Test.Schedule.Heartbeat` (140-206 s alone, over the per-call size, Rule 21 timings), the other heartbeat, stall and task classes and the Demo area to the CI `shards-6` group: none of them names `CommandsIn`, `ReminderOps`, `SetReminder` or `Msg.Enum` (grep at `6c55d82c362a55c9e0747db25086545642e3cd38`). CI runs every class on the push.

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
  - Audit entries hold from/to values like the step-2 keys, ONLY in the IRIS audit log, never in any other log, trace, digest, notice or eval output; one leak-scan test pins it in the story that writes the keys (36.4; 24.2 for partner contacts) (veto V3, RULED 2026-11-12).
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

`Test/Contract/Ac.cls` (Lane B, Story 0.4's oracle) is not touched: its `Named` check is existence only.

### For Story 36.4 (input to its plan; not this story's work)
- **Already met there:** non-admins get 403 on every `/v1/settings` URL (`Web/Api.cls:307` `OnPreDispatch`, `IsAdmin` :342), and online-demo visitors hold no admin role (`Install/Step/Users.cls:46`). The audit entry names the IRIS user and session (`SettingsOps.AuditData` :222, `WriteAudit` :243; pattern in `Test/Core/SettingsAudit.cls:71-86`). `Setting.Get` caches for 60 s (`Data/Setting.cls:39`). "Save changes", "Saved. Applies within a minute. Recorded in the audit log." and "Couldn't save. Nothing was changed." exist (`web/src/app/settings/settings-view.ts:42,43,45`). The unsaved-changes guard exists (`unsaved-guard.ts:21`, `settings-page.ts:254-270`).
- **The on-call person.** An "OcuTalon user" is an IRIS user with an OcuTalon session row (`Data.Session.IrisUser`, `ForUser` :84). A user is paged by email at an address the admin enters for them, because the delivered code has no OcuTalon-side address for a user. Pairing is per session (`Ownership.Pairing` :562).
- **Size seen at the split:** a new `SettingsOps` section kind with its own saver and a user list with paired flags, one route (`Test/Web/Api.cls` route count 38 → 39), a web section component, a settings nav growing from 7 to 8, per-field errors, a Playwright spec, real-HTTP tests and an audit test.
- **Overlaps:**
  - `Core/SettingsOps.cls`: `XData Sections` row, `ALLOWLIST` names, one dispatch line in `Save`, one branch in `Values`, new methods at the end. Epic 21 edits only `Field()`'s channels branch.
  - `Web/Api.cls` UrlMap: one route. `Test/Web/Api.cls` `TestRoutes`: 38 → 39.
  - `Test/Core/SettingsSave.cls`: `TestAllowList` and `TestValues`. Epic 21 edits only `TestDigestSection`.
  - `web/src/app/settings/settings-page.ts` (`@switch` and imports) and `settings-view.ts` (`SETTINGS_SECTIONS`, `SETTINGS_TEXTS`). Epic 21 edits both near the same lines, so expect merge conflicts.
  - `web/scripts/settings-view.test.mjs` (Epic 21 too).
  - A new `on-call-section.ts` and a new `web/e2e/settings/on-call.spec.ts`.
- The on-call texts under `### Proposed public text` › On call, and veto items V1-V5's on-call parts, are this story's proposals for 36.4 to use once accepted.

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
  - **RULED (Planner, 2026-11-12): audit WITH the from/to values** (where pages and partner warnings go is security-relevant; redirecting them is an attack). Conditions: the values go ONLY into the IRIS audit log (admin-only) and appear in no other log, trace, digest, notice or eval output; ONE leak-scan test pins that (in Story 36.4 for the on-call keys, Story 24.2 for partner contacts; 36.2 writes the rule into the spine).
  - (Was recommended: audit the on-call keys like the other product keys, with from/to values and addresses.)
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
- `settings.onCallOffOnDemo` (the 409 `not_available` body): "The online demo has no on-call person, because its visitors aren't admins. On your own install, an admin chooses one here." (Planner ruling 2026-11-12: replaces "because it has no admin")

Partner contacts (Story 24.2):
- `settings.partnersSection`: "Partner contacts"
- `settings.partnersHelp`: "Partner warnings go only to the people listed here, and only after you approve each one." (Planner ruling 2026-11-12: approved on condition that Story 24.2 pins both halves in tests)
- `settings.partnerName`: "Name"; `settings.partnerEmail`: "Email address"; `settings.partnerProductions`: "Productions it concerns"; `settings.partnerAdd`: "Add contact"; `settings.partnerRemove`: "Remove"
- `settings.partnerRemoveConfirm`: "Remove {name}? Partner warnings will stop going to {address}."
- `settings.partnerBadName`: "Enter a name of 1 to 128 characters. Nothing was changed."
- `settings.partnerNoProduction`: "Choose at least one production. Nothing was changed."
- `settings.partnersOffOnDemo`: "Partner contacts are off on the online demo, where partner warnings go to simulated contacts. They work on your own install."

SQL query watches (Story 24.2; the refusal reasons come from `WatchOps`, Story 23.8):
- `settings.sqlSection`: "SQL query watches"
- `settings.sqlHelp`: "OcuTalon runs each query on its schedule and tells you when the result changes." (Planner ruling 2026-11-12: the "as a user that can only read" wording is a security claim AD-18 marks (inference); it may ship only once Story 23.8's test proves the reader user is refused on INSERT, UPDATE, DELETE and DDL)
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
- (loop) `node --test web/scripts/catalog.test.mjs` -- expected: pass (it reads `Enum.cls`)
- (once) `npm --prefix web test` -- expected: pass
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: `"ok": true`
- (once) `<lane-b vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e36s2iw bash ci/iris.sh shard lane-b@Contract,Core,Data,Live --part k/6` for k = 1..6, then `shard lane-b@Web --part k/4` for k = 1..4, one call each -- expected: all passed. If a part passes about 120 s, run the rest of that piece with a larger n. (`--part` on a piece is supported: `ci/iris.sh` `cmd_shard`.)
- (once) `<lane-b vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e36s2iw bash ci/iris.sh class <C>`, one call each for `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Schedule.ReminderChat`, `OcuTalon.Test.Schedule.ReminderLogic` and `OcuTalon.Test.Schedule.ReminderZone` -- expected: passed (Decided in-stage 15 names what CI alone runs).
- (once) `<lane-b vars> OCUTALON_RUN_TAG=e36s2i bash ci/iris.sh class OcuTalon.Test.Msg.Contracts` -- a fresh stack; expected: passed
- (once) `bash docker/tests/test-ci-config.sh` -- expected: pass (no new test class, so no `ci/units.sh` change). The whole `ci/checks.sh` runs in CI's hosted `checks` job, not as one local line.
- (loop) AC 1's check: `S=_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md; for n in oncall.primary.channels oncall.escalationMinutes settings/on-call settings/partner-contacts settings/sql-watches PartnerContact.ForProduction OcuTalon.Msg.Command.AckPage OcuTalon.Msg.Command.SaveSqlWatch OcuTalon.Msg.Escalation 'Delivery.FindByRef(pageRef' rollback_setting; do grep -qF -- "$n" "$S" || echo "MISSING $n"; done` -- expected: no output

**Shared surfaces:**
- `Msg.Enum` NOTIFICATIONKIND (`Test/Msg/Contracts.cls:72`, `web/scripts/catalog.test.mjs`)
- The `CommandsIn` Routes table and the verb list (`TestRoutes` count, `TestOriginRules` verbs, `Test/Msg/Contracts.cls:42`, `Test/Core/CommandsStep4.cls:310,408`, `Test/Core/CommandsPrecedent.cls:104`; none counts all rows)
- The `Contracts` XData
- `SetReminder` storage (`test-storage.sh`)
- The spine's ownership tables
- The short-name registry (`src/short-names.tsv`) is not touched: the three new classes are messages (`Ens.Request`, `Msg.Command`), which take no registry row (`test-storage.sh` `registry-param`).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19; one per AC; the implement stage records each as `mutation: <change> → <red test>`):**
- AC 1: delete the AD-19 on-call keys bullet → AC 1's check prints `MISSING oncall.escalationMinutes`
- AC 2: drop `PageRef` from `Msg.Escalation` → `TestContracts` (also: drop `page` from NOTIFICATIONKIND → `TestEnumerations`)
- AC 3: remove the `AckPage` Routes row → `TestRoutes`; add `web_user` to `SaveSqlWatch`'s origins → `TestStepFiveRefusals`
- AC 4: remove the Kind guard in `ReminderOps.Set` → `TestEscalationNotBuilt`
- AC 5: no code and no test; its check is the review of `git diff -- <EXPERIENCE.md>` against the runner's accepted list (empty when none is reported)

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Plan pass 2 (after split (A) was ruled): the spec is re-planned as the contracts story and meets the READY-FOR-DEVELOPMENT standard. Pending the Planner's ruling (they do not block implement): veto items V1-V6 and the proposed public texts (V7). Only accepted texts reach EXPERIENCE.md (Decided in-stage 12). `new_units: none`.
