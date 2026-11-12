---
title: 'Story 36.1: Record the setting history of each watched production'
type: 'feature'
created: '2026-11-12'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-36-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Step 5's Lane A contracts are only partly in the spine, and nothing records how a watched production's settings change, so Story 23.3 cannot name "the setting change behind an incident" or offer its rollback, and Lane B's Story 36.2 has no fixed names to build against.

**Approach:** Write the missing step-5 Lane A contracts into the spine (the delivered fix kinds' parameter schemas and resources, the roll-back kind named as Story 23.3's, paging owner/table/escalation message, SQL-query check and its read-only user, catalog keys, `incident` payload fields, the paging channels and how each acknowledges, and the Lane B list Story 36.2 fixes). Build `OcuTalon.Watch.SettingHistory` with two new Lane A tables, driven from the heartbeat `Tick` by Interoperability's per-namespace production-change counter. The roll-back kind, its `%Ens_ProductionConfig:W` grant, the forbidden-list exception and every security-overview change belong to Story 23.3, the first story that offers a rollback (Planner ruling V1(b), 2026-11-12; DW-1225).

## Boundaries & Constraints

**Always:**
- Judge each AC against the delivered code; record what is already met (Design Notes) and build only the missing parts.
- Only `OcuTalon.Watch.Reader` enters the watched namespace (AD-3); `Current` stays its one namespace-switching method, and it calls no OcuTalon class while inside.
- Credentials (Planner ruling V3, 2026-11-12): a setting that holds a reference to an `Ens.Config.Credentials` entry stores only that reference's ID (a name, not a secret). Only a setting whose VALUE is itself a secret is dropped inside the Reader before anything leaves it; for it a salted hash (`Data.Webhook.HashSecret`/`Matches`) is kept, solely to detect a change, and the hash never leaves its table: no GET, `/v1/state`, trace, log, digest, notice or eval output carries it (one leak-scan test pins this). A change row for such a setting keeps both values blank.
- Taking a snapshot only reads: no `%Save`, no `UpdateProduction`, no write to `Ens.Config.*`. The production-change counter does not move because of a snapshot.
- No row, column or log line names who made a change.
- Lane A files only (AD-29, AD-33). Contended files get only the edits listed under Design Notes › Contended overlaps.
- Every destructive or cross-namespace test runs on a lane-B throwaway (`ci/iris.sh` / `ci/warm.sh`), never on slot B.
- Ship no public text and no GUIDE.md line (Planner ruling, 2026-11-12): the `page.*`, roll-back and `RollbackSetting` strings ship with the stories that first show them (36.2, 23.3). EXPERIENCE.md and `Msg.Catalog.Watch` get no new user-facing string from this story.

**Never:**
- Edit the Lane B contracts: the page notification and its `Notify` route, the escalation kind on `Reminder`, the AckPage and SaveSqlWatch verbs, the on-call keys, the partner-contact table, `OcuTalon.Msg.*`, `OcuTalon.Data.Public.*`. 36.1 only names them in the spine.
- Declare `OcuTalon.Fix.Kind.RollbackSetting`, add any `RESOURCES` entry, grant `%Ens_ProductionConfig` to any role, add a forbidden-privilege test exception, or change the security overview (its generated lists, `ONLINESTATEMENT` or any sentence) (Planner ruling V1(b): all Story 23.3's).
- Take setting snapshots on an online-demo install.
- Read the IRIS audit log. Add an `/api/v1` route, a UI, a README or GUIDE change, a `ci/units.sh`, `.github/workflows` or `release/**` change.
- Edit `Data/BackgroundCheck.cls`, `Checks/Coverage.cls`, `Core/SettingsOps.cls` or `Mcp/Ops.cls`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First snapshot | Watched production, no `SettingSnapshot` row | One snapshot row; zero `SettingChange` rows | none |
| Counter unchanged | Same counter and start mark; last check under 60 min ago | No settings read beyond the marks; no new rows | none |
| Production config change | Item setting saved through `Ens.Config.Production` while it runs | Counter moves; the next Tick writes one `SettingChange` per difference; `DetectedAt` = Tick time, at most 60 s after the save | none |
| System Default Setting change | SDS row that applies to an item is saved | One row on that item and target, `Source` `default` | none |
| Restart | `^Ens.Runtime` StartTime/CheckSum pair differs, or the counter is gone | Snapshot and diff on that Tick | none |
| Hourly safety net | Counter unchanged, `CheckedAt` 60+ min old | Snapshot and diff; unchanged content only refreshes the marks | none |
| Credentials reference changes | A setting holding an `Ens.Config.Credentials` ID (e.g. an adapter's `Credentials`) gets another ID | Change row with the old and new IDs (names, not secrets) | none |
| Secret value changes | A setting whose value is itself a secret gets a new value | Change row with `OldValue` = `NewValue` = "" and `Credential` 1; the value appears nowhere; the hash stays in `SettingSnapshot` only | none |
| Hash leak scan | After a secret-value change: GET routes, `/v1/state`, trace, log, digest, notice and eval output | Neither the secret nor its hash appears in any of them | none |
| Item added or removed | Item appears or disappears | One row per setting of that item (blank new or old value) | none |
| Online-demo install | `onlineDemo` 1 | Tick takes no snapshot and writes no row | none |
| Unreadable or not-current production | Reader outcome `unreadable` / `not_current` | Nothing written; marks kept | No warning (same as FailurePoller) |
| Read throws | Reader error | That production is skipped this Tick; other productions continue | One `$$$LOGWARNING` via `Bridge.Redact`, with no setting value |
| Purge | Rows older than `daysToKeep` (90) | Old `SettingChange` and old snapshots deleted; the newest snapshot of each still-watched production is kept | First error is returned after every table has been tried |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Checks/Process.cls:216-283` -- `Tick`. Insert the one SettingHistory call between the queue loop (ends :255) and `Set items = ""` (:256). `INTERVALSECONDS` = 60 (:92) is the check interval.
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls` -- `Current` (:556), the one namespace switch (`New $NAMESPACE`, :571-573). Extend it the way `listItems`/`Items` (:513) did. `Readable` (:202), `OnlineDemo()` (:175), `CredentialName` and `CREDENTIALPARTS` (:101, :526). Already `Include (Ensemble, EnsConstants, EnsErrors)`.
- `src/ocutalon/cls/OcuTalon/Watch/FailurePoller.cls:57-75` -- `Watched()`, the set of watched productions (Kind `production` rows, eval rows excluded). Reuse it.
- `src/ocutalon/cls/OcuTalon/Data/Webhook.cls:82,90` -- `HashSecret(secret)` and `Matches(stored, secret)`, the salted SHA-256 scheme. Reuse it for credential change detection.
- `src/ocutalon/cls/OcuTalon/Data/Handled.cls:10,61-79` -- DEFAULTGLOBAL, storage and a `Purge` sibling (`Bridge.Time.DaysCutoff`).
- `src/ocutalon/cls/OcuTalon/Install/Step/Watch.cls:8-11` -- the Watch area's `Purge(daysToKeep)`. `Install/Step/Digest.cls:22-31` is the pattern for running several purges.
- `src/short-names.tsv` -- the registry (`short global class lane`), checked by `docker/tests/test-storage.sh`.
- `src/ocutalon/cls/OcuTalon/Fix/Kind.cls:34-75,225` -- kind parameters, `KINDS`, `Ready`. Siblings: `Fix/Kind/SuspendItem.cls:15-39,77-82` (ONLINEGRANT 0, `Refusal`) and `Fix/Kind/ResumeItem.cls`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Fix.cls:36-59` -- `GrantsOf` already turns `RESOURCES` into service-role grants and drops `ONLINEGRANT` 0 kinds online. No change needed.
- `src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls:13,54-56` -- `FORBIDDEN` and its check in `Add`. This is where the single exception goes.
- `src/ocutalon/cls/OcuTalon/Install/SecurityOverview.cls:35,209-256` -- `ONLINESTATEMENT`, `FixKindRows`, `RoleRows`. Regenerating writes `docs/security-overview.md`, and `docker/tests/test-security-overview.sh` checks it for drift.
- Tests that pin those surfaces: `Test/Install/Registry.cls:625-653,721-759`, `Test/Web/Install.cls:329-380,687-691`, `Test/Fix/Kind.cls:202-231`, `Test/Fix/ItemKinds.cls:56-70`, `Test/Install/SecurityOverview.cls:252-298,342-371`, `Test/Install/Retention.cls:149-160` (`TestNoSettingRead`, pattern `ocutalon\.data\.setting`), `Test/Install/RetentionRules.cls:41`.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls` -- base for OCUORDERS tests: `Tick(tickAt)` (:686), `SetItemDefault`/`ITEMNAME` (:153-159), cleanup in `OnAfterOneTest`. `Test/Watch/OrdersDefinition.cls:26` -- `Put(on, credentialValue, noteValue)` saves credential and plain settings on the saved Orders definition (throwaway only).
- `irislib/Ensemble.inc:254-270` -- `$$$EnsProdModCounterGet` = `^IRIS.Temp.EnsProdModCounter($namespace)`. `irislib/Ens/Config/Production.cls:1968-1976` (`SetModified` increments only while that production runs). `irislib/Ens/Config/DefaultSettings.cls:265-293,336-346` (SDS saves move the same counter). `irislib/Ens/Director.cls:103-106,251-252` (`^Ens.Runtime("StartTime")`/`("CheckSum")` set at each start; `UpdateProduction` kills the counter). `irislib/Ens/Config/Item.cls:83-87,642-735` (`PopulateVirtualSettings`: `$LB(Target,Name,Value,ValueType,...,EditorContext)`, with item, SDS and default precedence). `irislib/EnsLib/EMail/OutboundAdapter.cls:56` (`credentialsSelector` in the `EditorContext`).
- Spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- AD-15 SettingHistory L519-523, payload L427-428, summary L550, kinds L571-572, AD-18 L590-593, AD-24 L943-945, AD-29 L1054, Catalog L1077/L1159, ownership tables L1383-1512 (tables paragraph L1418), S15 L1709, Deferred L1722-1724.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- Message Catalog L757, Step 5 L1080-1082; key rows look like `| Case (\`key\`) | "text" |`.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Test/Watch/SettingHistory.cls` -- **Task 0 (measure first, on the lane-B warm throwaway)**. While Orders runs in OCUORDERS, record `^IRIS.Temp.EnsProdModCounter("OCUORDERS")` before and after: (i) `OrdersDefinition.Put`; (ii) saving a test-owned SDS row for `ITEMNAME`; (iii) a full Reader settings read. Also record whether `PopulateVirtualSettings` lists stored item settings that are not class settings. Write the measured values into this spec under a new `### Measured` heading at the end of Design Notes. If (i) or (ii) does not move the counter, or (iii) does, HALT `intent gap`. Do not plan around it.
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls` -- add a public `Settings(namespace, production, full, salts, Output marks, Output settings) As %String`, with outcomes as `Items`.
  - It goes through a new `Current` flag. `marks` = {counter, started}.
  - With `full`, `settings` is a sorted array of {item, target, setting, value, source, credential, hash}: the union of each item's `PopulateVirtualSettings` entries and its stored `Settings`.
  - A credential-type value (EditorContext starting `credentialsSelector`, checked inside; or `CredentialName(name)`, checked after switching back) has `value` "". Its `hash` is the matching old salt.hash from `salts` (`Webhook.Matches`), else a new `Webhook.HashSecret`.
  - Writes nothing. -- One reader, one switch (AD-3). The value never leaves the Reader.
- `src/ocutalon/cls/OcuTalon/Data/SettingSnapshot.cls` and `src/ocutalon/cls/OcuTalon/Data/SettingChange.cls` -- new persistent tables, fields as in Design Notes › Veto items V2. Each has `DEFAULTGLOBAL`, a committed `Storage Default` block, indexes, and its own `Purge(daysToKeep)` modelled on `Data/Handled.cls`. -- AD-3, AD-5, AD-27.
- `src/short-names.tsv` -- append `SettingSnap	^OcuTalonP.SettingSnap	OcuTalon.Data.SettingSnapshot	A` and `SettingChange	^OcuTalonP.SettingChange	OcuTalon.Data.SettingChange	A`.
- `src/ocutalon/cls/OcuTalon/Watch/SettingHistory.cls` -- new class. `Watch(tickAt) As %Status`, which never throws:
  - On an online-demo install it returns at once.
  - For each `FailurePoller.Watched()` entry it reads the marks. It takes a full snapshot only when there is no snapshot, the counter or start mark differs, or the newest row's `CheckedAt` is 3600+ s old.
  - It diffs against the newest snapshot. If the content is the same, it updates the marks in place. If it differs, or this is the first snapshot, it inserts a new snapshot plus one `SettingChange` per difference (none for a first snapshot), in one transaction, with `DetectedAt` = tickAt.
  - Each production has its own Try, logging one redacted warning that carries no value.
  - `Purge(daysToKeep)` runs both tables' purges.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- in `Tick`, insert one line `Do ##class(OcuTalon.Watch.SettingHistory).Watch(tickAt)` after the queue-loop Try block. -- AD-18 (the heartbeat drives it). This is the only edit to this contended file.
- `src/ocutalon/cls/OcuTalon/Install/Step/Watch.cls` -- `Purge` runs `IncidentManager.Purge` and `SettingHistory.Purge`, each whatever the other returned, and returns the first error (the `Install/Step/Digest.cls` pattern). Keep the literal `IncidentManager).Purge(daysToKeep)`, which RetentionRules pins.
- `src/ocutalon/cls/OcuTalon/Test/Install/Retention.cls` -- in `TestNoSettingRead`, end the pattern at a word boundary (`ocutalon\.data\.setting\b`). Add scanner assertions that `OcuTalon.Data.SettingChange` is not flagged and `OcuTalon.Data.Setting).Get` still is. Add `OcuTalon.Watch.SettingHistory`, `OcuTalon.Data.SettingSnapshot` and `OcuTalon.Data.SettingChange` to its class list.
- `src/ocutalon/cls/OcuTalon/Fix/Kind/RollbackSetting.cls` -- new declare-only kind:
  - Parameters: `NAME` `rollback_setting`, `PARAMETERS` `change` (a `SettingChange` Ref), `RESOURCES` `%Ens_ProductionConfig:W`, `TARGETTYPE` `setting`, `DIAGNOSED` 0, `ASKED` 0, `ONLINEGRANT` 0, plus `NOTSETUP`, `NOTALLOWED` and `ONLINESHARED` (the accepted texts).
  - `Ready` returns 0 with `NOTSETUP`. `DryRun` returns an error: `ONLINESHARED` on the online demo, else `NOTSETUP`.
  - Extends `Fix.Kind`, with `Refusal` modelled on SuspendItem's.
- `src/ocutalon/cls/OcuTalon/Fix/Kind.cls` -- append `,OcuTalon.Fix.Kind.RollbackSetting` to `KINDS`, and `setting` to the `TARGETTYPE` doc line.
- `src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls` -- add an exception parameter for exactly role `Users.#SERVICEROLE` + `%Ens_ProductionConfig` + `W`, declared by area `OcuTalon.Install.Step.Fix`. `Add` lets only that triple through. Every other forbidden pair, holder, area or permission (`R`, `RW`, `U`) is still refused. -- AD-24.
- `src/ocutalon/cls/OcuTalon/Install/SecurityOverview.cls` -- reword `ONLINESTATEMENT` and add the not-offered-yet sentence (accepted texts only). Then regenerate `docs/security-overview.md` (`bash docker/tests/test-security-overview.sh --write` on the throwaway).
- Forbidden-privilege and grant tests -- update `Test/Install/Registry.cls` (`TestForbiddenGrantRefused`, `TestEveryRole`), `Test/Web/Install.cls` (`CheckGrants`/`Forbidden`), `Test/Fix/Kind.cls` (`TestGrants`), `Test/Fix/ItemKinds.cls` (`TestGrants`) and `Test/Install/SecurityOverview.cls` (`TestFixKindRows` expected rows and statement, `TestRoleRowsDeclaredBy` line pin).
  - They allow exactly the one triple and still fail on any other forbidden resource, holder, permission or area.
  - Each gains one negative case: the same resource on another role, and `RW` on the service role, are refused.
- `src/ocutalon/cls/OcuTalon/Test/Watch/SettingDiff.cls` -- pure tests (no other namespace): the diff (added, removed, changed, unchanged, item added or removed), first snapshot gives no changes, credential entries (blank values, change detected through the hash), the purge (fixtures at 91 and 89 days; the newest snapshot of a watched production is kept), and online-demo off.
- `src/ocutalon/cls/OcuTalon/Test/Watch/SettingHistory.cls` -- live tests on OCUORDERS, extending `Test.Watch.Case` (THROWAWAY STACKS AND CI ONLY):
  - Task 0's measurements.
  - Drive everything through `Tick(tickAt)`.
  - Delete only its own production's history rows at the start.
  - Restore every changed setting and SDS row in `OnAfterOneTest`.
- Spine (`ARCHITECTURE-SPINE.md`) -- write the additions in Design Notes › Spine additions. Then `memlog.py append` and `lint_spine.py` (`"ok": true`), and refresh `updated:` (Rule 20).
- `EXPERIENCE.md` -- add a Message Catalog row with its key for each accepted proposal, plus rows that quote the already-accepted Story 23.2/23.5/23.6 catalog texts by key (Design Notes › Proposed public text).

**Acceptance Criteria:**
- Given the spine after this story, when the step-5 Lane A contracts are looked up, then every item of the first AC is there with the Design Notes › Spine additions, including the Lane B list that Story 36.2 fixes and the paging channels with how a page is acknowledged on each. `lint_spine.py` reports `"ok": true`.
- Given a local install, when the installer composes roles, then `OcuTalonServiceRole` holds `%Ens_ProductionConfig:W`, declared by `Fix` from `rollback_setting`'s `RESOURCES`. The security overview's fix-kinds table and privileges list show it. Epic 3's forbidden-privilege tests pass with that one grant and fail for any other forbidden privilege or holder.
- Given an online-demo install, when the installer composes roles, then the service role holds neither `%Ens_ConfigItemRun:U` nor `%Ens_ProductionConfig:W`.
- Given any request for `rollback_setting`, when it reaches `Fix.Kind.Check`, ProposeFix or `DryRun`, then it is refused with the kind's plain reason, and nothing changes.
- Given Orders running in OCUORDERS on a throwaway, when a test changes an item setting through the production configuration, and then an SDS row that applies, then after the next Tick that sees the counter move each change is one `SettingChange` row, with `DetectedAt` at most `INTERVALSECONDS` after the change and no user named in any column or value.
- Given a snapshot is taken, when the counter and the saved definition (`OrdersDefinition.Defined()`, the SDS global) are compared before and after, then nothing changed.
- Given a credential setting set to a unique sentinel and then changed, when history runs, then a row records the change with both values blank. The sentinel is absent from every `SettingSnapshot` stream, every `SettingChange` row, the OCUTALON event log and the OCUTALON message bodies written since the test began.
- Given `onlineDemo` 1, when a Tick runs, then no snapshot or change row is written for any production.
- Given rows older than 90 days, when `OcuTalon.Install.Step.Watch.Purge(90)` runs, then they are gone, newer rows remain, and the newest snapshot of each watched production is kept.
- Given the storage checks, when `test-storage.sh` runs, then both tables' `DEFAULTGLOBAL` values match `short-names.tsv` and their storage blocks are committed.

## Spec Change Log

- 2026-11-12, Contest Planner rulings on V1-V6 (binding; `.coordination/prompts/story-361-rulings-20261112.md`), applied by the runner inside the intent contract and Design Notes; status reset to `draft` to re-plan only what V1(b) removes: V1 option (b): no `RollbackSetting`, no RESOURCES entry, no `%Ens_ProductionConfig:W`, no forbidden-list exception, no overview or ONLINESTATEMENT change (moved to Story 23.3 as an AC, ledgered DW-1225 routed to 23-3). V2 tables approved. V3 approved with conditions (Credentials reference stores its ID; only a secret value is hashed; the hash never leaves its table; one leak-scan test; change row values blank). V4 demo off, pinned: approved. V5 spine approved, with AD-24 adjusted to "%Ens_ProductionConfig:W is granted by Story 23.3 together with rollback_setting; the demo install leaves it out."; AD-18's sql_query mechanism stays (inference). Task 0 approved (HALT if the counter misbehaves). Public text: 36.1 ships none and no GUIDE line; the proposed strings are approved catalog text for 36.2/23.3 (NOTSETUP dropped).

## Review Triage Log

## Design Notes

### Planner rulings (2026-11-12, binding; supersede anything below that conflicts)
- **V1 = option (b).** 36.1 does NOT declare `Fix.Kind.RollbackSetting`, adds no `RESOURCES` entry, gives no `%Ens_ProductionConfig:W` to OcuTalonServiceRole, adds no forbidden-list test exception (`Roles.cls`, `Test/Install/Registry.cls`, `Test/Web/Install.cls` unchanged), and makes no security-overview change (no `ONLINESTATEMENT` change, no "declared so that ..." sentence, no `docs/security-overview.md` edit). All of it is Story 23.3's (approved AC move; DW-1225 routed to 23-3). Own installs keep their current privileges. The spine's AD-16 per-kind schema list names `rollback_setting` only as Story 23.3's.
- **V2 approved:** `SettingSnapshot`, `SettingChange` as drafted (no user column, 90-day purge, newest snapshot per watched production always kept).
- **V3 approved with conditions:** a setting that holds a reference to an `Ens.Config.Credentials` entry stores only its ID (a name, not a secret) and is diffed like any setting; only a setting whose VALUE is itself a secret gets the salted hash (`Data.Webhook.HashSecret`/`Matches`), only for change detection; the hash never leaves its table: no GET, `/v1/state`, trace, log, digest, notice or eval output carries it, pinned by ONE leak-scan test; a change row for such a setting keeps both values blank.
- **V4 approved:** setting history OFF on an online-demo install, pinned by a test.
- **V5 approved as drafted,** with AD-24 worded: "%Ens_ProductionConfig:W is granted by Story 23.3 together with rollback_setting; the demo install leaves it out." AD-18's `sql_query` mechanism stays marked (inference) until 23.8 measures it. `IncidentManager`, `Data.Page`, `Msg.Escalation` (36.2) and the paging-ack rules (Got it on the web or the paired Telegram chat; an email page has none; a reply never counts): approved.
- **Task 0 approved:** measure `^IRIS.Temp.EnsProdModCounter` on a lane-B throwaway first; HALT (`intent gap`) if it does not behave as the spine draft says.
- **Public text:** 36.1 ships NO public text and NO GUIDE.md line. The proposed `page.*`, roll-back, `incident.settingChangeCause`, NOTALLOWED and ONLINESHARED strings are approved catalog text for the stories that first show them (36.2, 23.3); NOTSETUP is dropped. The spine's catalog-key list may NAME those keys as step-5 contracts (owner stories 36.2 / 23.3), but 36.1 adds no string to `Msg.Catalog.Watch` or EXPERIENCE.md.
- **Contended order:** 36.1 goes first on `Checks/Process.cls` `Tick`; Epic 22's 22.5/22.11 integrate forward after it. All local until CI HOLD OFF.

**Ledger inbox (Rule 17):** none owned by this story key.

**Governing ADs (Rule 6):**

| AD | What it requires here |
| --- | --- |
| AD-3 | Only the Reader switches namespace, in one method |
| AD-5 | Durable state only, with append-only schema evolution: the "last seen" values are stored, never kept in memory |
| AD-15 | SettingHistory, Lane A; one owner per table |
| AD-16 | Kinds with a parameter schema and declared resources; the executor runs a kind only if the service user holds them |
| AD-17 | No secrets in audit data |
| AD-18 | Heartbeat `Tick` → `Checks`; BackgroundCheck is the one check table |
| AD-22 | `%UnitTest` under `OcuTalon.Test.<Area>`; destructive tests on throwaways |
| AD-23 | The installer is the one install path |
| AD-24 | No role holds `%Ens_ProductionConfig`, except the roll-back kind's WRITE |
| AD-27 | Area `Purge(daysToKeep)`, 90 days |
| AD-29 | Lane files; 36.1/36.2 split |
| AD-33 | Ownership tables updated in the same change |

No AC contradicts an AD's Rule. AD-24 L943 already writes the exception that this story implements.

**Already met (no new work; evidence on this branch):**
- Kinds reroute, suspend, resume and partner warning, with their resources. `Fix/Kind.cls:75` lists them in `KINDS`. `Reroute.cls:16-24` declares `target` and `%Ens_MessageResend:U`. `SuspendItem.cls:15-27` declares `item`, `%Ens_ConfigItemRun:U` and ONLINEGRANT 0, which `ResumeItem.cls:6` inherits. `PartnerWarning.cls:18-28` declares `text,to`, no resources, and `contact`. Spine L571-572 and L943-945 record them; only the per-kind parameter schema is still missing from the spine.
- The installer composes service grants from `RESOURCES` (`Install/Step/Fix.cls:36-59`), and the overview lists are generated from them (`SecurityOverview.cls:209-256`). Only the `Roles.Add` forbidden check blocks the new grant.
- The queue-backlog check type: `Kind` `queues` (`Checks/Process.cls:857`, `Watch/Ops.cls:29,32`, spine L593).
- Incident summary storage: `Data/Incident.cls:94` `Summary`, written by `Watch.Summary`; notification kind `summary` (`Msg/Enum.cls:30`); spine L550 and L1159. The spine still needs to name the property.
- ProposeFix (`IncidentManager.cls:1082-1089`).
- PRD Open Question 5 already reads as answered (`prd.md` L1702), so no PRD amendment is needed. The spine records it, which the AC asks for.
- Catalog texts for suspend, resume, reroute, partner warning and summary already exist and were approved by the Contest Planner (`Msg/Catalog/Watch.cls`: `incident.suspendRequest` :817, `incident.resumeRequest` :826, `incident.rerouteRequest` :835, `result.itemSuspended` :865, `result.itemSkipped` :881, `result.itemNotChanged` :889, `result.rerouted` :896, `incident.partnerRequest` :959, `result.partner*`, `summary.*` :619-781, `partner.subject`). The handled line is `handled.marked` "Marked as handled at {time}" (:430), and the button is `button.gotIt` (:425). None of these get a new proposal; EXPERIENCE.md only mirrors them by key.

**Integration ACs (Rule 1).**
- Consumers inside this story: the installer (`Step/Fix.GrantsOf` → `Roles`) reads `rollback_setting`'s `RESOURCES`, and the service role holds `%Ens_ProductionConfig:W`. The overview generator reads the same declaration, and its lists show the line. Both are pinned by the second AC.
- SettingHistory and its tables have no consumer in this story; the first consumer will be Story 23.3.
- Consumed-by:
  - 23.3: `EvidencePack.Build` lists `SettingChange` rows from the 24 h before the first failure, and the roll-back kind restores a change's old value.
  - 23.4: the `Data.Page` contract named here.
  - 23.8: the SQL-query contract named here.
  - 36.2: the Lane B names listed here.
- Consumes: `FailurePoller.Watched`, `Watch.Reader`, `Data.Webhook.HashSecret`/`Matches`, `Bridge.Time.DaysCutoff`, `Install.Step.Fix.GrantsOf`.

**Extend, don't copy (Rule 2).**

| New piece | Extends or reuses |
| --- | --- |
| `Reader.Settings` | Extends `Current` the way `Items` (:513) did. No second switch. |
| The watched set | `FailurePoller.Watched()` |
| Credential hashing | `Data.Webhook.HashSecret`/`Matches`, called (not edited) from Lane A |
| Table purges | Copy `Data/Handled.cls:61-79` with `DaysCutoff`. Each table owns its purge, which is the codebase convention. |
| The Watch step's purge | The `Install/Step/Digest.cls:22-31` pattern |
| `RollbackSetting` | Extends `Fix.Kind`. Its refusal follows `SuspendItem.Refusal`/`ONLINESHARED`. A separate class rather than a subclass of `SuspendItem`, because it is not an item kind. |
| Tests | `Test.Watch.Case` (`Tick`, cleanup) and `OrdersDefinition.Put` |

**Decided in-stage:**
1. "Watched production" means `FailurePoller.Watched()` (Kind `production` rows; eval rows excluded).
2. A snapshot is each item's effective settings (`PopulateVirtualSettings`, which applies SDS) together with its stored `Settings`. An SDS change therefore shows on each item it applies to, with `Source` `default`.
3. The "last value seen" (counter, start mark, `CheckedAt`) lives on the newest `SettingSnapshot` row and is updated in place. A new row is written only for a first snapshot or changed content (AD-5: no in-memory state).
4. `DetectedAt` is the Tick's time. It is within the check interval while the production runs. A change made while the production is stopped is dated at the first Tick after the start, because no earlier time can be read. The spine says so.
5. Credential detection is a `credentialsSelector` EditorContext, or a name matching `Reader.CREDENTIALPARTS`.
6. An item added or removed gives one row per setting.
7. The roll-back kind: class `RollbackSetting`, name `rollback_setting`, parameter `change`, target type `setting`. The type is new because Fix.Run, Notice and Summary treat `item` kinds as suspend/resume. It is declare-only until 23.3.
8. The Tick hook is a single line, and `Watch` handles its own errors.
9. The Watch step purges through `SettingHistory.Purge`. `TestNoSettingRead`'s pattern gains a word boundary so that `Data.SettingChange` is not mistaken for `Data.Setting`. The guard stays, and its coverage grows.
10. Short names `SettingSnap` and `SettingChange`.
11. New tests sit under `Test/Watch/`, so they join `shard:lane-a@Watch` in group `shards-8` by area mapping. No `ci/units.sh` edit is needed (`test-ci-config.sh:42-46`). `new_units: none`. Their added time is about 1 min (inference).
12. Not judge-visible: back end, contracts and the security overview only, so no GUIDE.md "New since 1.0.0" line.
13. Spine contract names (Spine additions below) are chosen within the spine's existing step-5 text. Paging stays with IncidentManager, which owns the AckPage verb's routing, as with ProposeFix (L1098).

**Spine additions (the implement stage writes them).**
- **AD-15 L519-523.**
  - The counter is `^IRIS.Temp.EnsProdModCounter(<namespace>)` (`$$$EnsProdModCounterGet`), read inside `Reader.Current`. It moves on production-config and SDS saves only while that production runs, it is lost at an IRIS restart, and `UpdateProduction` kills it. Any difference, a missing value included, counts as moved.
  - The start mark is `^Ens.Runtime("StartTime")` with `("CheckSum")`.
  - The hourly net uses `CheckedAt`.
  - The table field lists; credential values are never stored, only a salted hash; the detected-time scope (item 4 above).
  - Off on an online-demo install.
  - The watched set; purge through `SettingHistory.Purge` from the Watch area, keeping the newest snapshot of each watched production.
  - The Task 0 measurements, or "(inference)" until they are measured.
- **AD-16 L571.** A per-kind parameter schema and `RESOURCES`:
  - `reroute`: `target`, `%Ens_MessageResend:U`
  - `suspend_item` / `resume_item`: `item`, `%Ens_ConfigItemRun:U`, ONLINEGRANT 0
  - `partner_warning`: `text,to`, no resources
  - `rollback_setting`: `change`, `%Ens_ProductionConfig:W`, ONLINEGRANT 0, `TARGETTYPE` `setting`. Declared in 36.1; Story 23.3 builds its `DryRun`/`Recheck`/`Execute` and flips `DIAGNOSED`.
  - A note for 23.3 (inference, from `irislib`): the `Ens.Config.*` classes check no resource, so a write needs WRITE on the target's database, and SDS writes match `%Ens_SystemDefaultConfig` in the portal. 23.3 measures this.
- **AD-24 L943-945.** The online-demo install leaves `%Ens_ProductionConfig:W` out as well.
- **Paging (new, step 5):**
  - The paging owner is `IncidentManager` (Lane A). Its table is `OcuTalon.Data.Page` (Lane A, Story 23.4): Ref, IncidentRef, Role `oncall|backup`, Person (OcuTalon user name or email address, never a Telegram identity), Channels, SentAt, AcknowledgedAt, AcknowledgedChannel, EscalationRef. It is purged with its incidents.
  - The escalation message is `OcuTalon.Msg.Escalation` (IncidentRef, PageRef), which `ReminderTimer` sends to `IncidentManager` when an escalation-kind `Reminder` falls due. Story 36.2 creates the class as `Msg` owner.
  - Channels: Telegram and email by default; each person chooses Telegram, email or both. Telegram only reaches a user whose session has a paired chat, so a person without one, or one given only as an email address, is paged by email.
  - Acknowledging:
    - Web: the page card's Got it, which submits AckPage through `CommandsIn`.
    - Telegram: the Got it button with an unguessable reference, accepted only from the paired chat.
    - Email: it carries no acknowledgement. The person presses Got it on their OcuTalon page or in Telegram, and a reply never acknowledges, because email is untrusted content.
    - Any acknowledgement stops escalation, and every copy shows `handled.marked`.
- **AD-18 L590-593.** SQL-query check: `BackgroundCheck` `Kind` `sql_query`, owned by the admin's session, scheduled by Epic 22's `IntervalMinutes`. Story 23.8 appends its query and result-hash columns. It runs as the IRIS user `OcuTalonSqlReader`, which has no OcuTalon role and only the SQL `SELECT` an admin grants, over a separate xDBC loopback connection, never the production's user. The mechanism and how its password is kept are measured and decided in 23.8 (inference; a veto item there). This replaces Deferred L1724's candidate.
- **Catalog keys (`Msg.Catalog.Watch`):** `page.onCall`, `page.onCallEmail`, `page.backup`, `page.backupEmail`, `page.subject`, `incident.rollbackRequest`, `result.settingRestored`, `result.settingChangedSince`, `summary.requestedRollback`, `summary.settingRestored`, `incident.settingChangeCause`. Existing keys are reused as listed above.
- **`incident` payload (L427-428):** `SettingChange` {item, target, setting, oldValue, newValue, credential, detectedAt} and `GapMinutes` (23.3); `Page` {state `paged|acknowledged|escalated`, pagedAt, acknowledgedAt, channel} (23.4). The summary stays a `summary` notification, not a payload field.
- **Lane B list (AD-29 L1054):** Story 36.2 fixes:
  - the `page` notification kind and its `Notify` route;
  - the escalation kind on `Reminder`, run by `ReminderTimer`;
  - the AckPage and SaveSqlWatch verbs;
  - the on-call setting keys;
  - the partner-contact table;
  - `Msg.Escalation`.
  Lane A never edits them.
- **Ownership tables (AD-33):**
  - Tables paragraph L1418: `Page` from step 5.
  - Cross-area rows: `OcuTalon.Watch.SettingHistory` (A, 36.1), `OcuTalon.Fix.Kind.RollbackSetting` (A, 36.1 declares, 23.3 builds).
  - Deferred L1722-1724 updated.

### Contended overlaps
| File | What 36.1 touches | Kind |
| --- | --- | --- |
| `Checks/Process.cls` (Epic 22, lane D) | Method `Tick`: one inserted line after the queue-loop Try block (:255) | **Non-append edit to `Tick`** (orchestrator serializes) |
| `Checks/Coverage.cls` | nothing | — |
| `Data/BackgroundCheck.cls` (Epic 22) | nothing (SQL-query columns are 23.8's; spine only) | — |
| `Data/SettingSnapshot.cls`, `Data/SettingChange.cls` | new files in `Data/` | append-only |
| `Watch/SettingHistory.cls`, `Fix/Kind/RollbackSetting.cls` | new files | append-only |
| `src/short-names.tsv` | two appended rows | append-only |
| `Core/SettingsOps.cls`, `Test/Core/SettingsSave.cls`, `Test/Web/SettingsApi.cls`, `Test/Core/Routing.cls`, `Mcp/Ops.cls` (Epic 21) | nothing | — |
| `README.md`, `GUIDE.md` (Epics 0, 21) | nothing | — |
| `Test/Web/Install.cls` | `CheckGrants`/`Forbidden`: one exception | non-append (not named as contended) |
| Spine, `EXPERIENCE.md` | paragraph edits and appended rows | shared planning artifacts; other lanes may edit them too |

### Veto and security items (pending the Planner's ruling; the runner sends them before any implement spawn)
- **V1: the `%Ens_ProductionConfig` grant.**
  - (a) **Recommended.** 36.1 ships a declare-only `rollback_setting` (schema and RESOURCES, no behaviour, never offered, refused if invoked). The grant, the overview lines and the one test exception land now. This matches spine AD-24 L943 and Story 23.3's "grant from Story 36.1".
    - Cost: until 23.3 merges, the service role holds a WRITE privilege that nothing uses. The overview says so.
    - Online demo: the grant is OFF (ONLINEGRANT 0), and the kind refuses with `ONLINESHARED`.
  - (b) The spine records it only. The grant, overview line and test exception move to Story 23.3, an AC move to a not-yet-planned story of another epic in the same release. 23.3's "grant from Story 36.1" would need amending.
    - Online demo: unchanged.
- **V2: new stored data.** Retention: 90 days (`daysToKeep`) through the Watch area's purge, keeping the newest snapshot of each still-watched production regardless of age, so history never restarts as "first".
  - `SettingSnapshot` (`^OcuTalonP.SettingSnap`, Lane A): Ref, Namespace (128), Production (128), TakenAt (UTC), CheckedAt (UTC), Counter, Started, Settings (`%Stream.GlobalCharacter`, a JSON array of {item, target, setting, value, source, credential, hash}).
  - `SettingChange` (`^OcuTalonP.SettingChange`, Lane A): Ref, SnapshotRef, Namespace, Production, Item, Target (`Host|Adapter`), Setting, OldValue, NewValue (MAXLEN 2000), Source (`production|default|class`), Credential (boolean), DetectedAt (UTC).
  - No user columns.
- **V3: credentials (NFR-11, AD-15).**
  - The value is dropped inside the Reader. Only a salted SHA-256 hash (Webhook's `salt.hash`) is stored, and only so that a change can be detected. Recommended.
  - Alternatives: no hash, which makes credential changes undetectable and fails the AC; or a keyed HMAC, which needs a stored key.
- **V4: online demo.** Setting history is OFF on an online-demo install. Reasons: every visitor shares one Orders production, and nothing there consumes the history (only reroute is offered, UX L1082). Pinned by the online-demo AC.
- **V5: AD amendments.** The additions to AD-15, AD-16, AD-18 and AD-24 and the new paging and SQL-query contract names above. They are within step 5's existing spine text, but they amend AD Rules.
- **V6: public text.** The texts below, the overview statement included.

### Proposed public text (verbatim; none ships until accepted)
- `page.onCall` (EXPERIENCE.md Message Catalog › Step 5; web card and Telegram, with Got it): "{count} {itemNoun} failed in the {production} production since {time}. {cause}.\nWhy now: you're on call for OcuTalon. Press Got it to show you're on it; if nobody does within {minutes} minutes, I'll page {backup}."
- `page.onCallEmail` (email): "{count} {itemNoun} failed in the {production} production since {time}. {cause}.\nWhy now: you're on call for OcuTalon. To show you're on it, press Got it on your OcuTalon page; if nobody does within {minutes} minutes, I'll page {backup}. Replying to this email doesn't count."
- `page.backup` (escalation; web card and Telegram): "{count} {itemNoun} failed in the {production} production since {time}. {cause}.\nWhy now: you're the backup, and nobody pressed Got it on {person}'s page within {minutes} minutes. Press Got it to show you're on it."
- `page.backupEmail`: "{count} {itemNoun} failed in the {production} production since {time}. {cause}.\nWhy now: you're the backup, and nobody pressed Got it on {person}'s page within {minutes} minutes. To show you're on it, press Got it on your OcuTalon page. Replying to this email doesn't count."
- `page.subject`: "OcuTalon page: {production} incident"
- `incident.rollbackRequest`: "{count} {itemNoun} failed since {time}. {cause}. I can put {setting} on {target} back to its earlier value. Approve?\n\nDry run: {setting} on {target}. Before: {before}. After: {after}. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page."
- `result.settingRestored`: "{setting} on {target} is back to {after}. To undo it, ask me to undo the rollback."
- `result.settingChangedSince`: "{setting} on {target} was not changed: it changed again after the dry run. It needs a new approval."
- `summary.requestedRollback`: "{time}: OcuTalon asked for approval to put {setting} on {target} back."
- `summary.settingRestored`: "{time}: {setting} on {target} was put back to its earlier value."
- `incident.settingChangeCause` (the UX fixture "The feed broke four minutes after this setting changed."; {minutes} is a duration slot): "The feed broke {minutes} after this setting changed: {setting} on {target}, at {time}."
- `RollbackSetting.NOTSETUP` (kind reason): "OcuTalon can't put settings back yet"
- `RollbackSetting.NOTALLOWED`: "OcuTalon isn't allowed to change settings in that production"
- `RollbackSetting.ONLINESHARED`: "On the online demo every visitor shares the Orders production, so OcuTalon doesn't change its settings there; on your own install it can"
- `SecurityOverview.ONLINESTATEMENT` (`docs/security-overview.md`): "On the online demo, OcuTalonServiceRole holds neither %Ens_ConfigItemRun:U nor %Ens_ProductionConfig:W, so OcuTalon can't suspend or resume items or change settings there."
- New overview sentence after it: "`rollback_setting` is declared so that OcuTalonServiceRole holds its grant, but OcuTalon doesn't offer it yet and refuses any request for it."
- GUIDE.md: none (not judge-visible).

## Verification

Every command uses the lane-B variables `OCUTALON_LOCK_DIR=<lock-dir>/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=36 stage=implement'` (written `<lane-b vars>` below; expand it on each call). The fresh tag is `e36s1i`, the warm tag `e36s1iw`. Run one per call, `timeout: 600000`, each about 150 s at most. Never slot B. At the end, also after a failure, run `<lane-b vars> OCUTALON_RUN_TAG=e36s1iw bash ci/warm.sh down` and `<lane-b vars> OCUTALON_RUN_TAG=e36s1i bash ci/iris.sh teardown`.

**Commands:**
- (loop) `<lane-b vars> OCUTALON_RUN_TAG=e36s1iw bash ci/warm.sh up` -- once per stage; expected: a ready stack
- (loop) `<lane-b vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e36s1iw bash ci/iris.sh class <C>`, one call for each of `OcuTalon.Test.Watch.SettingHistory`, `OcuTalon.Test.Watch.SettingDiff`, `OcuTalon.Test.Fix.Kind`, `OcuTalon.Test.Fix.ItemKinds`, `OcuTalon.Test.Install.Registry`, `OcuTalon.Test.Install.SecurityOverview`, `OcuTalon.Test.Install.Retention`, `OcuTalon.Test.Install.RetentionRules`, `OcuTalon.Test.Web.Install` -- expected: `CLASS ... passed`
- (loop) `bash docker/tests/test-storage.sh` -- expected: pass
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: `"ok": true`
- (once) `<lane-b vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e36s1iw bash ci/iris.sh shard lane-a@Watch --part k/4` for k = 1..4, then the same for `lane-a@Checks --part k/3`, `lane-a@Fix --part k/3` and `lane-a@Install --part k/3`, one call each -- expected: all passed. If a part nears 150 s, raise n. That `--part` works on a piece is (inference).
- (once) `<lane-b vars> OCUTALON_RUN_TAG=e36s1i bash ci/iris.sh class OcuTalon.Test.Watch.SettingHistory` -- a fresh stack proves the `Tick` change; expected: passed
- (once) `<lane-b vars> OCUTALON_RUN_TAG=e36s1i bash ci/iris.sh live security-overview` -- expected: no DRIFT
- (once) `bash docker/tests/test-ci-config.sh` and `bash ci/checks.sh`, one per call -- expected: pass

**Shared surfaces:**
- `Fix.Kind` `KINDS` and the fix-kinds table: `Test/Fix/Kind.cls` `TestGrants`, `Test/Fix/ItemKinds.cls`, `Test/Install/SecurityOverview.cls` `TestFixKindRows`.
- The forbidden-privilege lists: `Roles.FORBIDDEN`, `Test/Install/Registry.cls`, `Test/Web/Install.cls` `Forbidden`.
- The security overview's generated fix-kinds and privileges lists, and `docs/security-overview.md`.
- `src/short-names.tsv` (`test-storage.sh`).
- The Watch purge declaration (`RetentionRules.cls:41`, `Retention.cls` `TestNoSettingRead`).
- `Checks.Tick`'s steps.
- The spine's ownership tables.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19; the implement stage records each as `mutation: <change> → <red test>`):**
- Skip the counter compare (snapshot every Tick) → the counter-unchanged test.
- Store the raw credential value → the sentinel test.
- Write a change on the first snapshot → the first-snapshot test.
- Drop the online-demo guard → the online-demo test.
- Let the exception admit any holder → the Registry negative case.
- Purge the newest snapshot → the purge test.
- Call `%Save` on the production in the read → the snapshot-changes-nothing test.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned as one story (no split). Halted after planning, as the dispatch asked. Before any implement spawn, the Planner must rule on veto items V1-V6 (Design Notes › Veto and security items) and on the proposed public texts.
