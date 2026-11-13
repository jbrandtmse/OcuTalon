---
title: 'Story 36.1: Record the setting history of each watched production'
type: 'feature'
created: '2026-11-12'
status: 'done'
baseline_revision: '848178dc9d82a8a634d820c7da79a2d7e6cd883c'
baseline_commit: '5a27798b2a5fe9f58a613fd3129f6a96239449c2'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-36-context.md'
warnings: ['oversized']
deferred:
  - summary: >-
      lint_spine.py reports "ok": false on the architecture spine because of 10 low "possible unfilled template token" findings in catalog-template prose, so the "ok": true that Rule 20 and this story's first AC expect cannot be reached by any story that edits the spine.
    evidence: |-
      The same 10 findings (lines for {time}, {old}, {new}, {day}, {what happened}, {reason}, {entry}, {finding}, {n}) are on the baseline spine at commit 9ca1d94a, and this story adds none; no ad_id or ad_fields finding. Settling it needs the lint to accept braces in catalog templates, or the spine to quote them.
    location: >-
      _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md
    severity: low
  - summary: >-
      The evidence read in Reader.Current takes the first item of a name whatever its Enabled, so with same-name items it can describe the disabled copy.
    evidence: |-
      `Reader.Current` evidence block: `If entry.Name '= item Continue` then `Quit` after the first match. Pre-existing and outside Story 36.1's settings snapshot; the settings block now picks the first enabled item of a name.
    location: >-
      src/ocutalon/cls/OcuTalon/Watch/Reader.cls (evidence block of Current)
    severity: low
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
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls` -- `Current` (:556), the one namespace switch (`New $NAMESPACE`, :571-573); its last parameters are `listItems`/`items`, added for `Items` (:513). Extend it the same way. `Readable` (:202), `OnlineDemo()` (:175), `CredentialName` (:526) and `CREDENTIALPARTS` (:101; it holds `credential`, so it matches `Credentials`). Already `Include (Ensemble, EnsConstants, EnsErrors)`.
- `src/ocutalon/cls/OcuTalon/Watch/FailurePoller.cls:57-75` -- `Watched()`, the set of watched productions (Kind `production` rows, eval rows excluded). Reuse it.
- `src/ocutalon/cls/OcuTalon/Data/Webhook.cls:82,90` -- `HashSecret(secret)` and `Matches(stored, secret)`, the salted SHA-256 scheme. Reuse it for secret-value change detection.
- `src/ocutalon/cls/OcuTalon/Data/Handled.cls:10,61-79` -- DEFAULTGLOBAL, storage and a `Purge` sibling (`Bridge.Time.DaysCutoff`).
- `src/ocutalon/cls/OcuTalon/Install/Step/Watch.cls:8-11` -- the Watch area's `Purge(daysToKeep)`. `Install/Step/Digest.cls:22-31` is the pattern for running several purges.
- `src/short-names.tsv` -- the registry (`short global class lane`), checked by `docker/tests/test-storage.sh`.
- `src/ocutalon/cls/OcuTalon/Test/Install/Retention.cls:149-160` (`TestNoSettingRead`, pattern `ocutalon\.data\.setting`) and `Test/Install/RetentionRules.cls:41` (pins the literal `IncidentManager).Purge(daysToKeep)`).
- `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls` -- base for OCUORDERS tests: `Tick(tickAt)` (:686), `SetItemDefault`/`ITEMNAME` (:153-159), cleanup in `OnAfterOneTest`.
- `src/ocutalon/cls/OcuTalon/Test/Watch/OrdersDefinition.cls:15,26-58` -- `CREDENTIALS` = `Credentials,SMTPPassword,BotToken,ApiKey`; `Put(on, credentialValue, noteValue)` writes one value into all four plus `NOTE`. Callers: `Test/Watch/Evidence.cls:53,298,316`, `Test/Eval/Record.cls:173,666,678,960`. `Defined()` (:60).
- `src/ocutalon/cls/OcuTalon/Test/Core/SecretHandoff.cls:177-209` -- `Leaks(text)` (every `^OcuTalon*` global, `OcuTalonTest` excluded, data and subscripts) and `TableHolds(table, column, text)`. Reuse both; `Test/Core/SettingsEmail.cls:473` and `Test/Web/SettingsApi.cls:617` call them the same way.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls:1319` `Routes(class)` (the UrlMap as `METHOD url call`), `:1407` `Written(.sc, class, method, args...)`, `:1346` `CallSession` (stand-in `%request`/`%response`/`%session`); `Test/Web/StubRequest.cls` `Make(application)`. `Data/Ownership.cls:68,293` -- `SESSIONKEY` and `SessionRef` (a `%session.Data(SESSIONKEY)` ref whose `IrisUser` is `$Username`); `Data/Session.cls:84` `ForUser(irisUser, .sc)`.
- GET routes (UrlMaps): `Web/Api.cls:250-277` (`/v1/state`, `/v1/events`, persona, heartbeat, the four memory lists, `/v1/settings`), `Web/History.cls:23-24`, `Web/Usage.cls:20`, `Web/Documents.cls:59,61`, `Web/HookSettings.cls:28`, `Web/Public/Status.cls:37`. `Web/Public/Shell.cls:45-47` serves only the built bundle's files.
- `src/ocutalon/cls/OcuTalon/Test/Digest/Compose.cls:138-147` (`Route`: `ProcessProbe` `Reset`, `Feed`, `Host`, `Handle` of a `Compose`) and `Test/Digest/ProcessProbe.cls` (records each Notification as `^||DigestProbe("notice", n)`). `Watch/Notice.cls:164,182` (`Key`, `Slots`), `Msg/Catalog.cls:52` (`Render(key, slots, channel, .sc)`).
- `src/ocutalon/cls/OcuTalon/Eval/Record.cls:57` -- `Capture(case, namespace, production, item, keys, folder, .pack)`, which writes `snapshot.json` and `case.json`. `Test/Eval/Record.cls:950-990` is the pattern (send one failing batch through `Test.Demo.Production`, key `h<header id>`, a temporary folder, cleanup).
- `irislib/Ensemble.inc:254-270` -- `$$$EnsProdModCounterGet` = `^IRIS.Temp.EnsProdModCounter($namespace)`. `irislib/Ens/Config/Production.cls:1968-1976` (`SetModified` increments only while that production runs). `irislib/Ens/Config/DefaultSettings.cls:265-293,336-346` (SDS saves move the same counter). `irislib/Ens/Director.cls:103-106,251-252` (`^Ens.Runtime("StartTime")`/`("CheckSum")` set at each start; `UpdateProduction` kills the counter). `irislib/Ens/Config/Item.cls:83-87,642-735` (`PopulateVirtualSettings`: `$LB(Target,Name,Value,ValueType,...,EditorContext)`, with item, SDS and default precedence). `irislib/EnsLib/EMail/OutboundAdapter.cls:56` (`credentialsSelector` in the `EditorContext` of a `Credentials` reference).
- Spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` -- AD-15 SettingHistory L519-523, payload L427-428, summary L550, kinds L571-572, AD-18 L590-593, AD-24 L943-945, AD-29 L1054, Catalog L1077/L1159, ownership tables L1383-1512 (tables paragraph L1418), S15 L1709, Deferred L1722-1724.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Test/Watch/SettingHistory.cls` -- **Task 0 (measure first, on the lane-B warm throwaway)**. While Orders runs in OCUORDERS, record `^IRIS.Temp.EnsProdModCounter("OCUORDERS")` before and after: (i) `OrdersDefinition.Put`; (ii) saving a test-owned SDS row for `ITEMNAME`; (iii) a full Reader settings read. Also record whether `PopulateVirtualSettings` lists stored item settings that are not class settings. Write the values into this spec under a new `### Measured` heading at the end of Design Notes. If (i) or (ii) does not move the counter, or (iii) does, HALT `intent gap`. Do not plan around it.
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls` -- add a public `Settings(namespace, production, full, salts, Output marks, Output settings) As %String`, with outcomes as `Items`:
  - It goes through a new trailing `Current` flag. `marks` = {counter, started}.
  - With `full`, `settings` is a sorted array of {item, target, setting, value, source, credential, hash}: the union of each item's `PopulateVirtualSettings` entries and its stored `Settings`.
  - Inside `Current`, an entry whose EditorContext starts with `credentialsSelector` is marked a Credentials reference. After switching back, a setting named `Credentials` (any case) is one too. A reference keeps its value (the ID) with `credential` 0.
  - Every other setting whose name `CredentialName` matches is a secret value: `value` "", `credential` 1, `hash` the matching old `salt.hash` from `salts` (`Webhook.Matches`), else a new `Webhook.HashSecret`.
  - Writes nothing. -- One reader, one switch (AD-3). A secret never leaves the Reader.
- `src/ocutalon/cls/OcuTalon/Data/SettingSnapshot.cls` and `src/ocutalon/cls/OcuTalon/Data/SettingChange.cls` -- new persistent tables, fields as in Design Notes › Veto items V2. Each has `DEFAULTGLOBAL`, a committed `Storage Default` block, indexes, and its own `Purge(daysToKeep)` modelled on `Data/Handled.cls`. -- AD-3, AD-5, AD-27.
- `src/short-names.tsv` -- append `SettingSnap	^OcuTalonP.SettingSnap	OcuTalon.Data.SettingSnapshot	A` and `SettingChange	^OcuTalonP.SettingChange	OcuTalon.Data.SettingChange	A`.
- `src/ocutalon/cls/OcuTalon/Watch/SettingHistory.cls` -- new class. `Watch(tickAt) As %Status`, which never throws:
  - On an online-demo install it returns at once.
  - For each `FailurePoller.Watched()` entry it reads the marks. It takes a full snapshot only when there is no snapshot, the counter or start mark differs, or the newest row's `CheckedAt` is 3600+ s old.
  - It diffs against the newest snapshot. If the content is the same, it updates the marks in place. If it differs, or this is the first snapshot, it inserts a new snapshot plus one `SettingChange` per difference (none for a first snapshot), in one transaction, with `DetectedAt` = tickAt. A secret-value difference (hash changed) gets `OldValue` = `NewValue` = "" and `Credential` 1.
  - Each production has its own Try, logging one redacted warning that carries no value.
  - `Purge(daysToKeep)` runs both tables' purges.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- in `Tick`, insert one line `Do ##class(OcuTalon.Watch.SettingHistory).Watch(tickAt)` after the queue-loop Try block. -- AD-18. This is the only edit to this contended file.
- `src/ocutalon/cls/OcuTalon/Install/Step/Watch.cls` -- `Purge` runs `IncidentManager.Purge` and `SettingHistory.Purge`, each whatever the other returned, and returns the first error (the `Install/Step/Digest.cls` pattern). Keep the literal `IncidentManager).Purge(daysToKeep)`, which RetentionRules pins.
- `src/ocutalon/cls/OcuTalon/Test/Install/Retention.cls` -- in `TestNoSettingRead`, end the pattern at a word boundary (`ocutalon\.data\.setting\b`). Add scanner assertions that `OcuTalon.Data.SettingChange` is not flagged and `OcuTalon.Data.Setting).Get` still is. Add `OcuTalon.Watch.SettingHistory`, `OcuTalon.Data.SettingSnapshot` and `OcuTalon.Data.SettingChange` to its class list. -- The new `Data.Setting*` names would otherwise trip the guard; it stays and its coverage grows.
- `src/ocutalon/cls/OcuTalon/Test/Watch/OrdersDefinition.cls` -- extend `Put` with a trailing optional `only As %String = ""`: a comma list of names from `CREDENTIALS` and `NOTE`. When set, only those are taken out and put back; "" keeps today's behaviour, so its current callers are unchanged. Update the header. -- Lets a test set `Credentials` (a reference) and `ApiKey` (a secret) to different values (Rule 2: extend, don't copy).
- `src/ocutalon/cls/OcuTalon/Test/Watch/SettingDiff.cls` -- tests with no other namespace: the diff (added, removed, changed, unchanged, item added or removed); a first snapshot gives no changes; secret entries (blank values, change detected through the hash, same secret with the old salt gives no change); a Credentials reference diffs as a plain value; restart and hourly marks; and the purge (fixtures at 91 and 89 days; the newest snapshot of a watched production is kept).
- `src/ocutalon/cls/OcuTalon/Test/Watch/SettingHistory.cls` -- live tests on OCUORDERS, extending `Test.Watch.Case` (THROWAWAY STACKS AND CI ONLY):
  - Task 0's measurements; `TestCounterUnchanged`, `TestChangesRecorded`, `TestSnapshotChangesNothing`, `TestCredentialsReference`, `TestSecretValue`, `TestOnlineDemoOff`.
  - Drive everything through `Tick(tickAt)`. Delete only its own production's history rows at the start. Restore every changed setting (`OrdersDefinition.Put(0)`) and SDS row in `OnAfterOneTest`.
- `src/ocutalon/cls/OcuTalon/Test/Watch/SettingSecret.cls` -- the ONE leak-scan test, `TestSecretAppearsNowhere`, extending `Test.Watch.Case` (THROWAWAY STACKS AND CI ONLY). It is described in Design Notes › Leak-scan test.
- Spine (`ARCHITECTURE-SPINE.md`) -- write the additions in Design Notes › Spine additions. Then `memlog.py append` and `lint_spine.py` (`"ok": true`), and refresh `updated:` (Rule 20).

**Acceptance Criteria:**
- Given the spine after this story, when the step-5 Lane A contracts are looked up, then every item of the epic's first AC is there as Design Notes › Spine additions list it, with `rollback_setting` named as Story 23.3's and AD-24 holding the ruled sentence word for word, the Lane B list that Story 36.2 fixes, and the paging channels with how a page is acknowledged on each. `lint_spine.py` reports `"ok": true`.
- Given a watched production with a snapshot, when a Tick runs with the counter and start mark unchanged and `CheckedAt` under 60 minutes old, then no settings are read and no row is written (`CheckedAt` unchanged). With `CheckedAt` 60+ minutes old, a snapshot is taken, and unchanged content only refreshes the marks.
- Given Orders running in OCUORDERS on a throwaway and its first snapshot taken (zero `SettingChange` rows), when a test changes an item setting through the production configuration and then an SDS row that applies, then after the next Tick that sees the counter move each change is one `SettingChange` row, `Source` `production` and `default`, with `DetectedAt` at most `INTERVALSECONDS` after the change and no user named in any column or value.
- Given a snapshot is taken, when the counter and the saved definition (`OrdersDefinition.Defined()`, the SDS global) are compared before and after, then nothing changed.
- Given the item's `Credentials` setting holds the ID `ZzCredA`, when it is changed to `ZzCredB` and a Tick runs, then one change row holds `OldValue` `ZzCredA`, `NewValue` `ZzCredB` and `Credential` 0.
- Given the item's `ApiKey` setting holds a unique sentinel, when it is changed to a second sentinel and a Tick runs, then one change row holds `OldValue` = `NewValue` = "" and `Credential` 1, and the snapshot's entry for it has `value` "" and a `hash` that `Webhook.Matches` the second sentinel.
- Given that secret-value change recorded, when every surface of Design Notes › Leak-scan test is read, then neither sentinel nor the stored hash appears in any of them, and the hash appears only in `SettingSnapshot`'s own globals.
- Given `onlineDemo` 1, when a Tick runs, then no snapshot or change row is written for any production.
- Given rows older than 90 days, when `OcuTalon.Install.Step.Watch.Purge(90)` runs, then they are gone, newer rows remain, and the newest snapshot of each watched production is kept.
- Given the storage checks, when `test-storage.sh` runs, then both tables' `DEFAULTGLOBAL` values match `short-names.tsv` and their storage blocks are committed.

### Review Findings

- [x] [CI] DW-1245: `OcuTalon.Test.Core.SettingsOps` `TestOnlyRunTimeWriter` fails: its writer pattern for `Data.Setting`'s global matches the new globals `^OcuTalonP.SettingChange` and `^OcuTalonP.SettingSnap` [src/ocutalon/cls/OcuTalon/Test/Core/SettingsOps.cls] -- HIGH (would turn CI `shard:lane-b` red on 36.1's head cf2658d8). Fix the pattern so it names only `Data.Setting`'s own global (a word boundary, as 36.1 did for `TestNoSettingRead` in `Test/Install/Retention.cls`), keeping the guard's intent; pin with a mutation. Done: the pattern's global branch is now `OcuTalonP\.Setting[DIS]?\b` (the data, index and stream globals of `Data.Setting`, not `SettingSnap*` or `SettingChange*`); `TestOnlyRunTimeWriter` also asserts that the index and stream globals are still flagged and that the snapshot and change globals pass. Reproduced red first on a warm throwaway (the two classes named in the failure), green after.
- [x] [CI] DW-1246: `OcuTalon.Test.Data.Tables` `TestEveryTableIsRegistered` fails: its `XData Registry` lacks rows for `OcuTalon.Data.SettingChange` and `OcuTalon.Data.SettingSnapshot` [src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls] -- HIGH (CI `shard:lane-b` red, warm and fresh). Append the two rows in the registry's own format (one-name appends; the file is also in Epic 21's diff, so append only); pin with a mutation. Done: two rows appended at the end of `XData Registry` in `Test/Data/Tables.cls` (`SettingSnap`, `SettingChange`); the file is also in Epic 21's diff, so the edit is append-only. Reproduced red first, green after.
- [x] [CI] Shared-surface sweep: find every other test that enumerates tables, globals, classes or storage (e.g. grep `src/ocutalon/cls/OcuTalon/Test` for `OcuTalonP`, `Registry`, `%Dictionary`, `short-names`, `ExtentSize`, `Every`) and run each such class once on a lane-B throwaway against this branch; fix any the two new tables or `Data.SettingStream` break, the same way. Report the list checked. Done: found one more break, `Test.Bridge.CodeRules` `TestWatchReadsCallOnlyListed` (`Watch.Reader` now calls `OcuTalon.Data.Webhook` for the secret hash and the class was not in `CALLBACKHELPERS`); fixed by appending `OcuTalon.Data.Webhook` to that list. Classes checked, each once on a warm lane-B throwaway, all passed after the fixes: `Test.Core.SettingsOps`, `Test.Data.Tables`, `Test.Bridge.CodeRules`, `Test.Contract.Step3`, `Test.Install.PrivateData`, `Test.Install.Registry`, `Test.Core.AnswersIn`, `Test.Web.Status`, `Test.Web.LeavingThePage`, `Test.Agent.Instructions`, `Test.Docs.Python`, `Test.Channel.EmailOAuth`, `Test.Eval.KeyProof`, `Test.Bridge.Gate`, `Test.Msg.Contracts`, `Test.Digest.Contracts`, `Test.Core.SecretHandoff`, `Test.Watch.Reader`; after the review also `Test.Contract.Ac`, `Test.Core.SettingsCommands` and `Test.Install.Retention`; the shard parts `lane-b@Core` 4/4 (holds `SettingsOps`, 15 classes), `lane-b@Data` 2/2 (holds `Tables`, 12 classes) and `lane-a@Watch` 3/4 (holds `SettingHistory`, 6 classes) passed too, and `test-boundaries.sh` passed. `Test/Bridge/CodeRules.cls` is outside this story's footprint (a one-name append to `CALLBACKHELPERS`, plus a clause in the comment above it): the lead reports it as a footprint extension, as it does the append-only `Test/Data/Tables.cls`. `Data.SettingStream` breaks none (it is not a persistent class, so the table enumerations skip it).

Code review 2026-11-12 (four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 33 raw findings, 15 entries after grouping: high 0, medium 6, low 9; 15 rejected). Planner rulings V1(b), V3, V4, the `Never:` list and the one-line `Checks/Process.cls` edit all hold. Open: the two medium patches below, for the story's one rework iteration.

- [x] [Review][Patch] Items that share a name are merged in a snapshot [src/ocutalon/cls/OcuTalon/Watch/Reader.cls:941] -- medium, fix-risk med. IRIS allows several items with one `Name` when only one is enabled (`Current` already handles it for `disabled`), but the settings block keys `stAll(stItem.Name, target, setting)`, so each setting takes the value of whichever same-named item comes last and a change to the running copy can be masked or misattributed. Fix: in the settings block, take one item per name, the first enabled item of that name, else the first, and add a live test in `Test/Watch/SettingHistory.cls` (for example a disabled copy of `OrdersFromPartner` added to the saved Orders definition with another stored value: the snapshot keeps the enabled copy's value, and changing the disabled copy is no change; OnAfterOneTest removes the copy), with its `mutation:` line. (blind-hunter + edge-case-hunter)
- [x] [Review][Patch] The class-setting branches of `Reader.Current` (the `credentialsSelector` editor context at list position 18, and a class setting whose name `CredentialName` matches) never run on live data [src/ocutalon/cls/OcuTalon/Watch/Reader.cls:924] -- medium, fix-risk med. The live tests use only the stored non-class settings `Credentials` and `ApiKey`; the Orders classes have no adapter and no secret-named class setting, so reading position 18 wrongly (every class setting a reference) would store a class setting's secret in plain text with every test green. Fix: a live test over an item whose class has a `credentialsSelector` setting not named `Credentials` and a secret-named class setting (an `EnsLib` class, or another choice that adds no product class), asserting the reference keeps its ID with `credential` 0 and the secret is blank with a hash that never reaches `SettingChange`, with its `mutation:` line. (verification-gap)
- [x] [Review][Patch] Live tests race the real heartbeat Tick [src/ocutalon/cls/OcuTalon/Test/Watch/SettingHistory.cls, Test/Watch/SettingSecret.cls] -- medium (Rule 19 hermeticity). `TestCredentialsReference`, `TestSecretValue` and `SettingSecret.TestSecretAppearsNowhere` now set the first value before Orders is watched, `TestOnlineDemoOff` turns the demo on first, `TestReadFailure` counts at least one warning, `TestChangesRecorded`'s lower bound allows a real Tick sent up to one interval before the change, and `TestRestartAndCounterGone` reads the snapshot before putting the counter back. (verification-gap)
- [x] [Review][Patch] `TestRestartAndCounterGone` left `^IRIS.Temp.EnsProdModCounter(OCUORDERS)` killed if it stopped between the kill and the restore [src/ocutalon/cls/OcuTalon/Test/Watch/SettingHistory.cls] -- medium (Rule 19). The taken counter is kept in `TakenCounter`, which OnAfterOneTest puts back if the counter is still gone. (blind-hunter)
- [x] [Review][Patch] The 2000-character cut of change values had no test; without it `%Save` fails MAXLEN and the production's history stops for good [src/ocutalon/cls/OcuTalon/Test/Watch/SettingDiff.cls] -- medium. Added `SettingDiff.TestLongValueCut` (the row keeps the first VALUEMAX characters, the snapshot the whole value); mutation observed red. (verification-gap)
- [x] [Review][Patch] The value cut was not in the spine for Story 23.3 [ARCHITECTURE-SPINE.md AD-15 "The rows"] -- low. AD-15 now says `OldValue`/`NewValue` keep at most 2,000 characters with no marker while the snapshot keeps the whole value, which 23.3's `rollback_setting` has to allow for. (blind-hunter)
- [x] [Review][Patch] The counter is killed by `Ens.Director.StopProduction`, not by `UpdateProduction` (`irislib/Ens/Director.cls:251-252`) [src/ocutalon/cls/OcuTalon/Watch/SettingHistory.cls:7, ARCHITECTURE-SPINE.md AD-15 "When"] -- low; corrected in both. (edge-case-hunter)
- [x] [Review][Patch] "Dated within one check interval while the production runs" holds only for changes that move the counter (a definition or System Default Setting save); a recompiled class default or a service-registry value is seen at the hourly check [SettingHistory.cls class description, ARCHITECTURE-SPINE.md AD-15 "What it can say"] -- low; both now say so. (edge-case-hunter)
- [x] [Review][Patch] `TestPurgeTriesBoth`'s holder job kept the row lock up to 60 s when the test stopped before releasing it, so `Drop()` could leave a row for the next test [src/ocutalon/cls/OcuTalon/Test/Watch/SettingDiff.cls] -- low; OnAfterOneTest releases a holder that is still holding and waits for it. (verification-gap)
- [x] [Review][Patch] The `Source` mapping of class settings was pinned only for `default` [src/ocutalon/cls/OcuTalon/Test/Watch/SettingHistory.cls] -- low. `TestChangesRecorded` asserts `class` for a class setting nothing sets and `production` for `TargetConfigName`, which the definition sets; mutation observed red. (verification-gap)
- [x] [Review][Defer] Core item properties (Enabled, PoolSize, Schedule, ClassName) are not snapshotted -- medium, by-design (Decided 2 and V2 fix `Target` Host|Adapter); DW-1235. (blind-hunter + edge-case-hunter)
- [x] [Review][Defer] A fault inside `Reader.Current` during a settings read is unpinned (needs a fault seam inside the namespace switch) -- low, wontfix-accepted; DW-1236. (verification-gap)
- [x] [Review][Defer] The history purge running after the incident purge returned an error is unpinned -- low, wontfix-accepted; DW-1237. (verification-gap)
- [x] [Review][Defer] `lint_spine.py` `"ok": true` is unreachable (the same 10 low placeholder findings as the baseline; none new after the review's spine patches) -- low; occurrence on DW-351. (acceptance-auditor)
- [x] [Review][Defer] The leak scan's route, digest, notice and eval surfaces cannot go red in this story (nothing reads the setting tables yet) -- low, by-design; already recorded under Verification as a guard that becomes live with Story 23.3. (verification-gap)

Rejected:
- low: a service-registry value is labelled `production` and a read-only one `class` -- `Source` is V2's fixed enum (`production|default|class`); the registry is rarely used.
- low: the payload's `SettingChange` fields lack `ref`/`source` and `GapMinutes` is undefined -- spec-bound (Spine additions); Story 23.3 extends the payload append-only.
- false: the `rollback_setting` resource text contradicts itself -- it is the ruled V5 sentence plus a note marked (inference) that 23.3 measures.
- false: AD-33's Lane B `Setting` entry is ambiguous as a prefix -- it names the single class; no check reads it as a prefix (`test-boundaries.sh` passed).
- false: the spec says `done` while sprint status says `review` -- the frontmatter `status` is build-auto's machine state.
- reject: the Auto Run Result's patch count (8 against 7 `[patch]` rows) -- the fix edits the spec under review.
- low: the incident-summary bullet repeats its sentence while naming the property -- no harm; the spec asked for the property name.
- low: `SettingSnapshot` has no `TakenAt` index for its purge -- a small table read once a day.
- low: `Ens.Config.Production` `%OpenId` failing for the current production would read as every setting removed -- not shown reachable for a running production.
- low: a Tick whose `tickAt` is before `CheckedAt` stops the hourly check -- Ticks run in order; a clock step back delays it by at most the step.
- low: one production watched under two namespace spellings gets two histories -- the watch UI gives the canonical name; only a test makes the other spelling.
- low: the newest snapshot deleted between `Newest()` and `%OpenId` restarts the history -- the purge keeps the newest snapshot of each watched production.
- low: AD-24's step-5 bullet still reads in the present tense beside the ruled sentence -- Design Notes keep L943 as it is; rewording an AD is the Planner's.
- low: `Data/SettingStream.cls` (uncompressed) was added outside the task list -- justified: `%Stream.GlobalCharacter` compresses (`COMPRESS = 1`), so without it the one leak-scan test has no positive control; it has no extent (its data is at `^OcuTalonP.SettingSnapS`, under the snapshot's `DEFAULTGLOBAL`), so it needs no `short-names.tsv` row (`test-storage.sh` passes), and compression was never a secrecy control.
- false: `Install.Step.Watch.Purge` skips the history purge if `IncidentManager.Purge` throws -- `IncidentManager.Purge` returns a status and catches its per-row errors.

Code review 2026-11-13, rework re-review (iteration 1 of 3; diff `5a27798b..HEAD`; four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 17 raw findings, 6 entries after grouping: high 0, medium 0, low 6, all patched; 8 rejected). Both items from the round above are confirmed fixed. (1) The settings block of `Reader.Current` takes one item per name, the first enabled one, else the first. `TestSameNameItems` pins this, and the reviewer saw it go red when the `stPick` skip was removed. (2) Both class-setting credential branches run on live data in `TestClassSettings`, and the reviewer saw it go red when the editor-context test was replaced by 1. Blanking `UseCookies` by its name is within V3 and Decided 5 ("a non-secret whose name matches ... is hashed too"), so it is not a finding. AD-3 holds: inside `Current` the new code calls only `Ens.Config.DefaultSettings.%GetSetting`. `Checks/Process.cls` still has its one `Tick` line.
- [x] [Review][Patch] `ItemClass` returned the last item's class when `OrdersFromPartner` was missing (a `For` loop's variable keeps its last value), and `AddItem` then built copies under an unrelated class [src/ocutalon/cls/OcuTalon/Test/Watch/SettingHistory.cls:160] -- low. It now returns "" when there is no such item, and `AddItem` returns an error for an empty class. (edge-case-hunter + blind-hunter + verification-gap)
- [x] [Review][Patch] `OnBeforeOneTest` ignored the status of `DropItems`, so a failure to remove marked items left over from an aborted run went unreported [src/ocutalon/cls/OcuTalon/Test/Watch/SettingHistory.cls:60] -- low. The status is now appended to the result. (blind-hunter + edge-case-hunter + verification-gap)
- [x] [Review][Patch] `TestSameNameItems` relied on the definition's item order without asserting it, and `AddItem` ignored the `Insert`/`InsertAt` status [src/ocutalon/cls/OcuTalon/Test/Watch/SettingHistory.cls] -- low (Rule 19). `AddItem` now returns that status, and the test asserts the order `0|1|0` (new helper `EnabledInOrder`). The assertion went red when `AddItem` appended instead. (verification-gap)
- [x] [Review][Patch] `TestClassSettings` looked for the first secret only in the snapshot taken after the change, where it cannot be [src/ocutalon/cls/OcuTalon/Test/Watch/SettingHistory.cls] -- low (Rule 19). The first snapshot's stream is now scanned for it as well, and that assertion went red under the mutation that marks every class setting a reference. (verification-gap)
- [x] [Review][Patch] "The first" item of a name did not say which order it means: the pick uses the definition's item list, while `Items` and `disabled` use ID order [src/ocutalon/cls/OcuTalon/Watch/Reader.cls:56,538] -- low. Both doc comments now say "in the definition's item list". (blind-hunter)
- [x] [Review][Patch] The `lane-a@Checks` and `lane-a@Install` shards were not rerun after the change to `Reader.Current` -- low (acceptance-auditor). The reviewer ran them on the warm stack after the patches: Checks parts 1-3 of 3 and Install parts 1-3 of 3 passed.

Rejected:
- false: the disabled items the tests add raise "was disabled" findings and incidents that outlive the test -- the copies exist before the test's watch row is created, and the first Tick for a new row is a baseline (`Checks.Process.Findings`: an empty previous gives no finding). No test changes Enabled after that, and the throwaway held 0 incidents after two full class runs.
- low: the System Default Setting `Enabled` half of the same-name pick has no live test -- the expression is the one `Current` uses for `disabled`, and a pinning fixture would need an SDS `Enabled` row on an item of the running production; ledgered DW-1242 wontfix-accepted with its reopen_if. (verification-gap + acceptance-auditor)
- false: AC 2's hourly clause has no `mutation:` line -- Rule 19 asks for one mutation per AC, and AC 2's is recorded (skip the counter compare -> `TestCounterUnchanged`). The clause is also outside this rework.
- false: `TestClassSettings` stores a string in the `%Boolean` `UseCookies` -- the probe item is disabled and never runs, and V3 / Decided 5 accept that a non-secret is hashed because of its name.
- reject (spec edit): the round above's "Open:" line, frontmatter `status`/`review_loop_iteration` against sprint status, and DW-1238's frontmatter `deferred:` entry against its ledger `wontfix-accepted` -- the frontmatter is build-auto's machine state, and DW-1238 was filed by the lead (a LOW, which `burndown` never owns). (acceptance-auditor + blind-hunter + edge-case-hunter)

## Spec Change Log

- 2026-11-13, rework iteration 2 of 3 (lead; trigger: ci, found locally by Story 36.2's lane-b regression run before CI reported on 36.1's pushed head cf2658d8): work ONLY the three unchecked `[CI]` items (DW-1245, DW-1246, the shared-surface sweep).

- 2026-11-12, rework iteration 1 of 3 (lead; trigger: first review left 2 in-story MEDs unpatched, fix-risk med): work ONLY the two unchecked `[Review]` items under `### Review Findings` (same-name items merged in a snapshot, `Reader.cls:941`; class-setting credential branches never run on live data, `Reader.cls:924`) and the tests they name.

- 2026-11-12, Contest Planner rulings on V1-V6 (binding; `.coordination/prompts/story-361-rulings-20261112.md`), applied by the runner inside the intent contract and Design Notes; status reset to `draft` to re-plan only what V1(b) removes: V1 option (b): no `RollbackSetting`, no RESOURCES entry, no `%Ens_ProductionConfig:W`, no forbidden-list exception, no overview or ONLINESTATEMENT change (moved to Story 23.3 as an AC, ledgered DW-1225 routed to 23-3). V2 tables approved. V3 approved with conditions (Credentials reference stores its ID; only a secret value is hashed; the hash never leaves its table; one leak-scan test; change row values blank). V4 demo off, pinned: approved. V5 spine approved, with AD-24 adjusted to "%Ens_ProductionConfig:W is granted by Story 23.3 together with rollback_setting; the demo install leaves it out."; AD-18's sql_query mechanism stays (inference). Task 0 approved (HALT if the counter misbehaves). Public text: 36.1 ships none and no GUIDE line; the proposed strings are approved catalog text for 36.2/23.3 (NOTSETUP dropped).
- 2026-11-12, re-plan (cycle_iteration 2) for those rulings. Removed: the `Fix/Kind/RollbackSetting.cls` task, the `KINDS` and `TARGETTYPE` edits to `Fix/Kind.cls`, the `Roles.cls` exception, the `SecurityOverview.cls` and `docs/security-overview.md` changes, the test changes to `Test/Install/Registry.cls`, `Test/Web/Install.cls`, `Test/Fix/Kind.cls`, `Test/Fix/ItemKinds.cls` and `Test/Install/SecurityOverview.cls` (none must change for another reason: 36.1 no longer touches `KINDS`, `FORBIDDEN`, the roles or the overview), their Code Map rows and Verification runs, the `live security-overview` command, the `lane-a@Fix` shard parts, the grant, online-demo-roles and rollback-refusal ACs, their Shared-surfaces entries and the exception mutation, and the EXPERIENCE.md task. V3: the name heuristic no longer hashes a Credentials reference; one leak-scan test (`Test/Watch/SettingSecret.cls`) and the `OrdersDefinition.Put` extension were added. Added the counter-gating AC (the epic's "only when the counter moved ... once an hour") with its own mutation, the spine-terms check, and the spine's naming of the summary property (the epic's first AC; it was listed as still missing but had no addition).

## Review Triage Log

### 2026-11-12 -- Review pass
- verdicts: 27 grouped findings (37 reported by the four layers; members of a group share its row) -- high 0, medium 3, low 23, false 1, maybe-false 0
- findings:
  - `[medium]` `[patch]` Blind: `Check` quits silently on `unreadable`/`not_current`, and the skip, warn and continue paths of `Watch` have no test (Edge/VGap: read-throws, unreadable, not-current untested). The silence is the matrix (`No warning`), but the Matrix rows 'Unreadable or not-current' and 'Read throws' had no covering test -- added `SettingHistory.TestSkippedReads` and `TestReadFailure` (a corrupt newest snapshot makes the read throw: one warning, nothing written, and a second watched entry for the same production under the namespace's lower-case spelling is still snapshotted); two mutations observed red
  - `[low]` `[reject]` Blind/Edge/VGap: a failed `PopulateVirtualSettings` is swallowed, so an item's class and default entries drop out of the snapshot -- a failure is deterministic (a class the item cannot load) and gives stable stored-only entries with no phantom change; faulting the read would stall that production's history for good with a warning every minute; a transient failure is not reachable by any cause shown
  - `[medium]` `[patch]` Blind/VGap/Intent: the editor-context branch (`credentialsSelector`) of the Credentials reference has no test; only the stored setting named `Credentials` is covered -- moved the classification into the pure `Reader.SettingEntry` and added `SettingDiff.TestSettingEntries` (a `SOAPCredentials` entry marked by its editor context keeps its ID; unmarked, it is blanked); mutation observed red. Index 18 of the virtual-settings row checked against `Ens.Config.Item` (EditorContext is the 18th column). The new method is a pure public helper beside `CredentialName`/`SaltKey`, not a new kind of surface
  - `[medium]` `[patch]` VGap: the purge's 'newest snapshot of a watched production is kept' is pinned only for watched productions; keeping the newest of every production would pass `TestPurge` -- `TestPurge` now has a production that is not watched with one 95-day snapshot and asserts it is gone; mutation (spare the newest of every production) observed red
  - `[low]` `[reject]` Blind: the secret fingerprint is one salted SHA-256 over possibly low-entropy values, kept 90 days -- the Planner's ruling V3 fixes `Data.Webhook.HashSecret`/`Matches` and that the hash never leaves its table; a different scheme is the Planner's call
  - `[low]` `[reject]` Blind/Edge: `Watch` runs synchronously in the Tick, with no time budget, and a marks-only read still runs the item and queue queries in `Current` -- the spec fixes the call as one line in `Tick` and the marks read inside `Current`; `FailurePoller` already does the same read per watched production each Tick, so the extra is about one more read per production per minute; no failure shown
  - `[low]` `[reject]` Blind: an item added or removed gives one row for every class-default setting (noise) -- matrix row 'Item added or removed' and Decided 6 specify one row per setting
  - `[low]` `[patch]` Blind: the cross-area table does not record that Lane A (`Reader.Settings`) calls Lane B's `Data.Webhook.HashSecret`/`Matches` -- appended that call to the spine's existing `Data.Webhook.HashSecret` row (AD-33)
  - `[low]` `[patch]` Blind/VGap: the 'no user column' assertion is weak (substring checks, an empty `$Username` passes) -- `TestChangesRecorded` now asserts a user is signed in and that each table has exactly the specified property list; mutation (an `Operator` property) observed red
  - `[low]` `[reject]` Blind/VGap/Edge: 'both purges run whatever the other returned' is untested (the first purge's error must not stop the second); `IncidentManager.Purge` throwing would skip the history purge -- needs a fault-injection seam that the sibling `Install/Step/Digest` pattern does not have; `IncidentManager.Purge` returns a status and does not throw; a LOW not worth a seam
  - `[low]` `[reject]` Blind/Edge: an unparsable newest `Settings` stream throws on every Tick, so that production's history is stuck -- the snapshot and its stream are saved in one transaction, so no path writes a truncated stream; theoretical hardening
  - `[low]` `[reject]` Edge: a stored setting with an empty `Target` or `Name` gives a null subscript -- `Ens.Config.Setting` requires both; theoretical
  - `[low]` `[reject]` Edge: a raw secret placed in a setting named `Credentials` (or marked as a reference) is stored as a plain value -- Decided 5 and the Planner's V3 define the reference path by name and editor context; IRIS stores an `Ens.Config.Credentials` ID there
  - `[low]` `[reject]` Edge: `after.%ToJSON()` as one string could exceed the maximum string length -- needs about 3.6 million characters of settings for one production; theoretical
  - `[low]` `[reject]` Edge: values are cut at 2000 characters, so a roll-back from a cut value would restore less -- the 2000-character limit is V2's field definition; Story 23.3 owns refusing to roll back a cut value (noted under residual risks)
  - `[low]` `[reject]` Edge: `DetectedAt` is the Tick message's time, so a late Tick can date a change before it was made -- Decided 4: `DetectedAt` is the Tick's time
  - `[low]` `[reject]` Edge: a persistent read failure logs one warning per production per minute -- the matrix says one warning per failed read; FailurePoller does the same
  - `[low]` `[reject]` Edge: `SettingSnapshot.Purge` returns before purging when `Watched()` throws, and one bad entry blocks all -- failing closed (purge nothing) is the safe direction; the next run retries
  - `[low]` `[reject]` Edge: `TestNoSettingRead`'s trailing `\b` could miss a future `Data.Setting*` table, an allow-list would not -- the spec names the `\b` change, and the test adds assertions that `Data.SettingChange` is exempt and `Data.Setting).Get` is still flagged
  - `[low]` `[patch]` Edge: the claim that a change made while stopped is dated at the first Tick after the start is false when the hourly check reads the stopped production first -- `Reader.Current` reads a stopped production, so the wording is now 'the first Tick that reads it': corrected in the spine, the class description and Decided 4
  - `[low]` `[defer]` Edge/VGap: `lint_spine.py` reports `"ok": false`, so the first AC's `"ok": true` cannot be met -- 10 low 'possible unfilled template token' findings in catalog-template prose this story does not own, the same 10 on the baseline spine (commit 9ca1d94a); this story adds none; deferred, as Story 39.1 took 'no new finding'
  - `[low]` `[reject]` VGap: the leak-scan surfaces other than the global scan have no consumer of the setting tables in this story, so they cannot go red here -- spec-mandated test with positive controls; recorded under Verification as a guard that becomes live with Story 23.3
  - `[low]` `[patch]` VGap other: `TestSnapshotChangesNothing`'s checksum could be 0 against 0 -- added an assertion that the checksum is not 0; mutation observed red
  - `[low]` `[reject]` VGap other: `TestChangesRecorded`'s 'within the check interval' bound compares the Tick's own time -- the lower bound and the interval bound still fail if the code stamps another time; kept
  - `[low]` `[reject]` VGap other: `TestPurge` calls the real Watch purge, so it could delete older rows it did not create -- the same call the installed purge task makes; it removes only rows older than the product's own retention; throwaway and CI stacks
  - `[low]` `[reject]` VGap other: other Watch tests leave history rows for Orders in shared tables -- only the two new classes read Orders history, and both clear it before and after each test; no other class asserts on those tables
  - `[false]` `[reject]` Intent auditor: descriptive report of readings (spine contracts versus code; tests exercise the code half) -- no divergence from the spec: the spine contracts are checked by the spine-terms command and `lint_spine.py`, as the spec's Verification says; its gap 5 duplicates the credentialsSelector finding

### 2026-11-12 -- Rework iteration 1 review pass (follow-up pass)
- verdicts: 21 findings -- high 0, medium 1, low 16, false 4, maybe-false 0
- findings:
  - `[low]` `[patch]` The `Reader.Items` doc claims same-name items are one, but `Items` lists every item row (blind-hunter, edge-case-hunter, verification-gap, intent-alignment) -- the sentence belongs to `Settings`; removed from `Items`, and the `Settings` bullet of the class description now states the rule.
  - `[low]` `[patch]` The class description's `Settings` bullet does not mention that same-name items collapse (blind-hunter) -- the bullet now says it.
  - `[medium]` `[patch]` `TestSameNameItems` asserts "a change to a disabled copy is no change" without showing that a read happened (verification-gap) -- the step now asserts that the counter moved and that the snapshot holds it after the Tick; mutation: `SettingHistory.Due` drops the counter comparison -> `TestSameNameItems` "the Tick read the settings again: the snapshot holds the new counter", observed red, restored.
  - `[low]` `[patch]` Test helpers: `ChangeStored` throws instead of returning its status, `DropItems` ignores a failed `DELETE` and a dangling item (blind-hunter, edge-case-hunter) -- `ChangeStored` returns the save status, `DropItems` skips a missing item and returns an error status for a negative SQLCODE.
  - `[low]` `[defer]` The evidence path in `Reader.Current` (`If entry.Name '= item Continue ... Quit`) takes the first same-name item whatever its Enabled (blind-hunter) -- real but pre-existing evidence code, not this rework's change; deferred (frontmatter).
  - `[low]` `[reject]` The System Default Setting `Enabled` override of the same-name pick has no live test (blind-hunter, verification-gap, intent-alignment) -- reachable only for same-name items switched by a System Default Setting `Enabled`; the expression is the one `Current` uses for `disabled`, and a pinning test needs a second System Default Setting fixture and branches; not worth them (reopen_if a production is seen to switch same-name items through System Default Settings).
  - `[low]` `[reject]` The `AddItem` Insert/InsertAt statuses are ignored and the order it relies on is not asserted (blind-hunter, edge-case-hunter) -- the order is pinned: the mutation that takes the first item whatever its Enabled goes red only when the disabled copy is first.
  - `[low]` `[reject]` Item names differing only in letter case would not merge (edge-case-hunter) -- not shown reachable: Ens.Config.Item names are one identifier in a production.
  - `[low]` `[reject]` `TestClassSettings` depends on `EnsLib.HTTP.GenericOperation` keeping `ProxyAuthorization` and `UseCookies` (blind-hunter, verification-gap) -- the test header names the probe class and its two settings (`PROBECLASS`), and a change would fail the first assertion for that reason.
  - `[low]` `[reject]` `DropItems` before every test has no guard against a missing Orders namespace (edge-case-hunter) -- these tests run on throwaway stacks and CI only, where OCUORDERS exists, as `OnAfterOneTest`'s `Put(0)` already needs.
  - `[low]` `[reject]` Spec bookkeeping (`review_loop_iteration`, the "Open:" paragraph, resolution notes on the `[x]` items) (blind-hunter) -- the fix is to edit this build's spec.
  - `[false]` The leak scan (`SettingSecret`) is not extended to class settings (intent-alignment, a divergence note) -- the rework item asks for the class-setting secret to be blank with a hash that never reaches `SettingChange`, which `TestClassSettings` asserts on the snapshot stream and the change rows; the other surfaces have no consumer yet (Shared-surface note).
  - `[false]` A flip of which copy is enabled would show as a value difference, not an item add (intent-alignment) -- a descriptive divergence note, not a defect: identity is the name (V2).
  - `[false]` `TestSameNameItems` extends the matrix (intent-alignment) -- a descriptive note; the test pins the rework item.
  - `[false]` File scope: the Lane A test helpers and the spec edit (intent-alignment) -- both are in the footprint.
  - `[low]` `[reject]` The pick adds a second pass over the items (descriptive: R3a/R3b readings, intent-alignment) -- the settings block is the only reader of same-name items in a snapshot; `Items` and the evidence path are other surfaces.
  - `[low]` `[reject]` `ChangeStored` filters on the stored Enabled, so a test fails with a clear message when `OrdersFromPartner` is not stored-enabled (verification-gap) -- the Orders definition ships it enabled and `Ready()` skips the class without the production.
  - `[low]` `[reject]` `Ready()` does not check `OrdersFromPartner` or the probe class (verification-gap) -- the same: a missing class fails an assertion naming it, on throwaway stacks only.
  - `[low]` `[reject]` Dangling `GetAt` oref in `DropItems` (edge-case-hunter) -- covered by the patch above (the `$IsObject` guard).
  - `[low]` `[reject]` The `Reader.Items` doc claim, second sighting (verification-gap other findings) -- same root cause as the first row.
  - `[low]` `[reject]` `AddItem` sets `item.Production` and then inserts (edge-case-hunter) -- the same root cause as the `AddItem` row above.

### 2026-11-12 -- CI rework iteration 2 review pass (follow-up pass)
- verdicts: 16 findings -- high 0, medium 3, low 10, false 3, maybe-false 0
- findings:
  - `[medium]` `[patch]` The writer pattern's SQL-table and `$ClassMethod` branches still match `SettingSnapshot` and `SettingChange` by prefix; only the global branch got a boundary (blind-hunter, edge-case-hunter, verification-gap; one root cause) -- no non-test line trips it today, but Story 23.3's code on the new tables would; `\b` added to both branches and two pass assertions added, mutations observed red.
  - `[low]` `[reject]` The `[DIS]?` suffix list hard-codes `Data.Setting`'s storage globals and no assertion pins a bare name (blind-hunter) -- the bare `^OcuTalonP.Setting` is flagged by the same branch, and a storage change of `Data.Setting` is guarded by `test-storage.sh`.
  - `[low]` `[patch]` The comment above `CALLBACKHELPERS` does not name `Data.Webhook` (blind-hunter, edge-case-hunter) -- a clause naming it and the reason added.
  - `[low]` `[patch]` Only the `SettingChange` registry row has a mutation (blind-hunter, verification-gap) -- the `SettingSnap` row mutation observed red and recorded.
  - `[low]` `[reject]` The widened `CALLBACKHELPERS` allowance covers every `Data.Webhook` method (blind-hunter) -- the list is per class by design, as for every other entry.
  - `[low]` `[reject]` The spec's stale "Open: ..." line and the iteration counter (blind-hunter) -- the fix is an edit of this build's spec.
  - `[false]` `[reject]` `Data.Webhook` may break another callback-class rule (edge-case-hunter) -- `Test.Bridge.CodeRules` passed on the warm stack with it listed.
  - `[low]` `[patch]` The added flag assertions (index and stream global) have no mutation line (verification-gap) -- `[DIS]?` narrowed to `[D]?`, observed red, recorded.
  - `[low]` `[reject]` The `CodeRules` mutation line is the pre-fix failure restated (verification-gap) -- removing the name is exactly the pre-fix state, which was observed red; the line says so.
  - `[low]` `[reject]` The registry's `short` field is not read by `TestEveryTableIsRegistered` (blind-hunter, verification-gap) -- the field is not part of the item; every existing row has the same shape, and `short-names.tsv` is checked by `test-storage.sh`.
  - `[low]` `[patch]` The sweep list is partial (verification-gap) -- `Test.Contract.Ac`, `Test.Core.SettingsCommands` and `Test.Install.Retention` run too and passed; listed.
  - `[false]` `[reject]` Scope reading: the edits touch files outside the overlap table (intent-alignment) -- `Test/Core/SettingsOps.cls` is in the epic footprint, `Tables.cls` is append-only, and `CodeRules.cls` is reported as a footprint extension.
  - `[false]` `[reject]` `Reader` may call `Data.Webhook` inside `Current`'s namespace switch (intent-alignment) -- `SettingEntry` runs in `Settings` after `Current` returns (`Reader.cls` line 554).

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

**Ledger inbox (Rule 17):** none owned by this story key. DW-1225 is Story 23.3's and is not addressed here.

**Governing ADs (Rule 6):**

| AD | What it requires here |
| --- | --- |
| AD-3 | Only the Reader switches namespace, in one method |
| AD-5 | Durable state only, with append-only schema evolution: the "last seen" values are stored, never kept in memory |
| AD-15 | SettingHistory, Lane A; one owner per table; no credential value stored |
| AD-16 | Spine only: each kind's parameter schema and declared resources (`rollback_setting` as 23.3's) |
| AD-17 | No secrets in audit data |
| AD-18 | Heartbeat `Tick` → `Checks`; BackgroundCheck is the one check table |
| AD-22 | `%UnitTest` under `OcuTalon.Test.<Area>`; destructive tests on throwaways |
| AD-24 | Spine only: no role holds `%Ens_ProductionConfig` today; 23.3 grants its WRITE |
| AD-27 | Area `Purge(daysToKeep)`, 90 days |
| AD-29 | Lane files; 36.1/36.2 split |
| AD-33 | Ownership tables updated in the same change |

No AC contradicts an AD's Rule. AD-24 L943 already names the roll-back kind's WRITE as the one exception from step 5; the ruled sentence says who grants it and when.

**Already met (no new work; evidence on this branch):**
- Kinds reroute, suspend, resume and partner warning, with their resources. `Fix/Kind.cls:75` lists them in `KINDS`. `Reroute.cls:16-24` declares `target` and `%Ens_MessageResend:U`. `SuspendItem.cls:15-27` declares `item`, `%Ens_ConfigItemRun:U` and ONLINEGRANT 0, which `ResumeItem.cls:6` inherits. `PartnerWarning.cls:18-28` declares `text,to`, no resources, and `contact`. Spine L571-572 and L943-945 record them; only the per-kind parameter schema is still missing from the spine.
- The installer composes service grants from `RESOURCES` (`Install/Step/Fix.cls:36-59`), and the overview lists are generated from them (`SecurityOverview.cls:209-256`). 23.3 adds its grant through that path; 36.1 does not touch it.
- The queue-backlog check type: `Kind` `queues` (`Checks/Process.cls:857`, `Watch/Ops.cls:29,32`, spine L593).
- Incident summary storage: `Data/Incident.cls:94` `Summary`, written by `Watch.Summary`; notification kind `summary` (`Msg/Enum.cls:30`); spine L550 and L1159. The spine still needs to name the property (Spine additions).
- ProposeFix (`IncidentManager.cls:1082-1089`).
- PRD Open Question 5 already reads as answered (`prd.md` L1702), so no PRD amendment is needed. The spine records it, which the AC asks for.
- The epic's text AC (texts proposed with catalog keys, none shipped unaccepted): the texts were proposed in this spec and the Planner approved them as catalog text for 36.2 and 23.3. 36.1 ships none, so neither `Msg.Catalog.Watch` nor EXPERIENCE.md changes; the spine names the keys with their owner stories. Existing approved texts (`incident.suspendRequest`, `incident.rerouteRequest`, `incident.partnerRequest`, `result.*`, `summary.*`, `handled.marked`, `button.gotIt`) are reused by key.

**Integration ACs (Rule 1).**
- `Reader.Settings` is consumed in this story by `SettingHistory.Watch`. The live Tick ACs (changes recorded, Credentials reference, secret value) exercise that consumer against the real Reader and a real production in OCUORDERS.
- SettingHistory and its tables: No consumers in this story; the first consumer will be Story 23.3. With V1(b) the installer and security-overview consumers are gone.
- Consumed-by:
  - 23.3: `EvidencePack.Build` lists `SettingChange` rows from the 24 h before the first failure, and its roll-back kind restores a change's old value. A secret-value row has blank values, so 23.3 cannot offer to roll it back.
  - 23.4: the `Data.Page` contract named here.
  - 23.8: the SQL-query contract named here.
  - 36.2: the Lane B names listed here.
- Consumes: `FailurePoller.Watched`, `Watch.Reader`, `Data.Webhook.HashSecret`/`Matches`, `Bridge.Time.DaysCutoff`.

**Extend, don't copy (Rule 2).**

| New piece | Extends or reuses |
| --- | --- |
| `Reader.Settings` | Extends `Current` the way `Items` (:513) did. No second switch. |
| The watched set | `FailurePoller.Watched()` |
| Secret hashing | `Data.Webhook.HashSecret`/`Matches`, called (not edited) from Lane A |
| Secret detection | `Reader.CredentialName`, minus Credentials references |
| Table purges | Copy `Data/Handled.cls:61-79` with `DaysCutoff`. Each table owns its purge, which is the codebase convention. |
| The Watch step's purge | The `Install/Step/Digest.cls:22-31` pattern |
| Test settings | `OrdersDefinition.Put`, extended with `only` |
| Leak scan | `SecretHandoff.Leaks`/`TableHolds`, `Test.Web.Api.Routes`/`Written`, `Test.Digest.ProcessProbe`, `Eval.Record.Capture` |
| Tests | `Test.Watch.Case` (`Tick`, cleanup) |

**Decided in-stage:**
1. "Watched production" means `FailurePoller.Watched()` (Kind `production` rows; eval rows excluded).
2. A snapshot is each item's effective settings (`PopulateVirtualSettings`, which applies SDS) together with its stored `Settings`. An SDS change therefore shows on each item it applies to, with `Source` `default`.
3. The "last value seen" (counter, start mark, `CheckedAt`) lives on the newest `SettingSnapshot` row and is updated in place. A new row is written only for a first snapshot or changed content (AD-5: no in-memory state).
4. `DetectedAt` is the Tick's time. It is within the check interval while the production runs. A change made while the production is stopped is dated at the first Tick that reads it, the first after the start or the hourly check while it is stopped, whichever is earlier, because no earlier time can be read. The spine says so.
5. Secret detection (V3). A Credentials reference is an entry whose EditorContext starts with `credentialsSelector`, or a setting named `Credentials` (any case; the fixture's stored `Credentials` setting has no class EditorContext). It stores its ID and diffs like any setting. A secret value is any other setting whose name `Reader.CredentialName` matches. A non-secret whose name matches (for example `AuthType`) is hashed too. That errs on the safe side, and its change row is blank. The plain name heuristic is not used on its own any more, because `CREDENTIALPARTS` holds `credential` and would hash every `Credentials` reference.
6. An item added or removed gives one row per setting.
7. The roll-back kind is not declared in 36.1. The spine names `rollback_setting` (parameter `change`, `%Ens_ProductionConfig:W`, ONLINEGRANT 0) as Story 23.3's plan (ruling V1(b)). Its target type is left to 23.3.
8. The Tick hook is a single line, and `Watch` handles its own errors.
9. The Watch step purges through `SettingHistory.Purge`. `TestNoSettingRead`'s pattern gains a word boundary so that `Data.SettingChange` is not mistaken for `Data.Setting`. The guard stays, and its coverage grows.
10. Short names `SettingSnap` and `SettingChange`.
11. New tests sit under `Test/Watch/`, so they join `shard:lane-a@Watch` in group `shards-8` by area mapping. No `ci/units.sh` edit is needed (`test-ci-config.sh:42-46`). `new_units: none`. Their added time is about 1-2 min (inference; the leak scan sends one failing batch).
12. Not judge-visible: back end and contracts only, so no GUIDE.md "New since 1.0.0" line.
13. Spine contract names (Spine additions below) are chosen within the spine's existing step-5 text. Paging stays with IncidentManager, which owns the AckPage verb's routing, as with ProposeFix (L1098).
14. The test fixtures use `Credentials` for the reference case and `ApiKey` for the secret case, set separately through `OrdersDefinition.Put(..., only)`. `Put` without `only` still writes one value into all four names, as `Evidence` and `Eval.Record` need.
15. The ACs about the grant, the online-demo roles and the roll-back refusal are dropped with V1(b). The online-demo omission of `%Ens_ConfigItemRun:U` stays pinned by Story 23.2's delivered tests.
16. `Test.Eval.Record` (Eval area, CI's `shards-2`) calls `Put` only without `only`, so its path is unchanged and it is not run locally. Its time is unmeasured and could exceed one call. `Test.Watch.Evidence` covers `Put`'s default path locally.
17. The approved catalog strings stay in this spec verbatim (Approved catalog text, below) as the reference for 36.2 and 23.3. They are not shipped here.

### Leak-scan test (V3; `Test/Watch/SettingSecret.cls` `TestSecretAppearsNowhere`; throwaway only)
Setup: `ApiKey` is set to sentinel A (`Put(1, A, , "ApiKey")`), a Tick runs, then it is set to sentinel B and a Tick runs, so a blank change row exists. `hash` is that entry's stored value, read from the newest `SettingSnapshot`. Each surface below is read after that and must hold neither A, B nor `hash`. Each read is also checked to have produced output, so an empty read cannot pass.
- **Stored data (trace bodies, digests, notices, decisions, every OcuTalon table):** `SecretHandoff.Leaks(A)` and `Leaks(B)` are "". `Leaks(hash)` names only `SettingSnapshot`'s own globals: its `DEFAULTGLOBAL` and the stream global derived from it. It must name at least that one, which is the positive control.
- **Trace:** `TableHolds("Ens.MessageHeader", "Description", x)` is 0 in OCUTALON. Message bodies are `^OcuTalon*` globals, so `Leaks` covers them.
- **Log:** `TableHolds("Ens_Util.Log", "Text", x)` is 0 in OCUTALON. The Reader writes nothing in OCUORDERS (AD-3).
- **GET routes and `/v1/state`:** every `GET` route of `Test.Web.Api.Routes(c)` for `OcuTalon.Web.Api`, `Web.History`, `Web.Usage`, `Web.Documents`, `Web.HookSettings` and `Web.Public.Status`. Each is called through `Test.Web.Api.Written` with a `StubRequest.Make` request, a `%CSP.Response`, and a `%CSP.Session` stand-in whose `Data(Data.Ownership.#SESSIONKEY)` is the ref of `Data.Session.ForUser($Username)`, so `Ownership.SessionRef` resolves it. A route with a `:ref` parameter (`Documents /:ref`) is called once for each ref its list route returned. `/v1/events` gets `after` and `afterInstance` 0. `/v1/state` is asserted by name and must answer a JSON object. `Web.Public.Shell` is left out because it serves only the built bundle's files, which no runtime value reaches.
- **Digest:** one requested `Compose` for that session on a shadow `Test.Digest.ProcessProbe`, as `Test.Digest.Compose.Route` does (`Reset`, `Feed`, `Host`, `Handle`). Every recorded `^||DigestProbe("notice", n)` list, and each one's `Msg.Catalog.Render(key, slots, "telegram")`, is scanned.
- **Notice:** a fixture incident on the Orders production (`Test.Data.Fixture` `Incident`, removed after). `Msg.Catalog.Render(Watch.Notice.Key(i), Watch.Notice.Slots(i), "telegram")` and the slots' JSON are scanned.
- **Eval output:** `Eval.Record.Capture` of one failing Orders batch into a temporary folder, as `Test.Eval.Record` does at :950-990. The batch is sent through `Test.Demo.Production` while the Orders WatchMark is held (`HoldFailures`, then `ReleaseFailures`), so no incident is made. Its headers, folder and settings are removed in `OnAfterOneTest`. The `snapshot.json` and `case.json` texts are scanned.

### Spine additions (the implement stage writes them)
- **AD-15 L519-523.**
  - The counter is `^IRIS.Temp.EnsProdModCounter(<namespace>)` (`$$$EnsProdModCounterGet`), read inside `Reader.Current`. It moves on production-config and SDS saves only while that production runs, it is lost at an IRIS restart, and `UpdateProduction` kills it. Any difference, a missing value included, counts as moved.
  - The start mark is `^Ens.Runtime("StartTime")` with `("CheckSum")`.
  - The hourly net uses `CheckedAt`.
  - The table field lists. A Credentials reference stores its ID. A secret value is never stored, only a salted hash used to detect a change, and the hash never leaves `SettingSnapshot`; its change row is blank. Also the detected-time scope (Decided 4).
  - Off on an online-demo install.
  - The watched set, and the purge through `SettingHistory.Purge` from the Watch area, which keeps the newest snapshot of each watched production.
  - The Task 0 measurements, or "(inference)" until they are measured.
- **AD-15 L550.** The incident summary is stored in `OcuTalon.Data.Incident.Summary`, written by `Watch.Summary`, and sent as a `summary` notification.
- **AD-16 L571.** A per-kind parameter schema and `RESOURCES`:
  - `reroute`: `target`, `%Ens_MessageResend:U`
  - `suspend_item` / `resume_item`: `item`, `%Ens_ConfigItemRun:U`, ONLINEGRANT 0
  - `partner_warning`: `text,to`, no resources
  - `rollback_setting` (Story 23.3's, not yet declared): `change` (a `SettingChange` Ref), `%Ens_ProductionConfig:W`, ONLINEGRANT 0.
  - A note for 23.3 (inference, from `irislib`): the `Ens.Config.*` classes check no resource, so a write needs WRITE on the target's database, and SDS writes match `%Ens_SystemDefaultConfig` in the portal. 23.3 measures this.
- **AD-24 L943-945.** A new bullet `[ADDED 2026-11-12, Story 36.1, Contest Planner ruling V5]` that reads exactly: "%Ens_ProductionConfig:W is granted by Story 23.3 together with rollback_setting; the demo install leaves it out."
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
- **Catalog keys (`Msg.Catalog.Watch`), names only, no text:**
  - Story 36.2: `page.onCall`, `page.onCallEmail`, `page.backup`, `page.backupEmail`, `page.subject`.
  - Story 23.3: `incident.rollbackRequest`, `result.settingRestored`, `result.settingChangedSince`, `summary.requestedRollback`, `summary.settingRestored`, `incident.settingChangeCause`, and the `rollback_setting` reasons NOTALLOWED and ONLINESHARED.
  - Existing keys are reused as listed under Already met.
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
  - Tables paragraph L1418: `SettingSnapshot` and `SettingChange` (A, 36.1); `Page` from step 5 (A, 23.4).
  - Cross-area row: `OcuTalon.Watch.SettingHistory` (A, 36.1).
  - Deferred L1722-1724 updated.

### Contended overlaps
| File | What 36.1 touches | Kind |
| --- | --- | --- |
| `Checks/Process.cls` (Epic 22, lane D) | Method `Tick`: one inserted line after the queue-loop Try block (:255) | **Non-append edit to `Tick`** (orchestrator serializes) |
| `Checks/Coverage.cls` | nothing | — |
| `Data/BackgroundCheck.cls` (Epic 22) | nothing (SQL-query columns are 23.8's; spine only) | — |
| `Data/SettingSnapshot.cls`, `Data/SettingChange.cls` | new files in `Data/` | append-only |
| `Watch/SettingHistory.cls`, `Test/Watch/SettingDiff.cls`, `Test/Watch/SettingHistory.cls`, `Test/Watch/SettingSecret.cls` | new files | append-only |
| `Test/Watch/OrdersDefinition.cls` | `Put` gains a trailing optional parameter | non-append (not named as contended) |
| `src/short-names.tsv` | two appended rows | append-only |
| `Core/SettingsOps.cls`, `Test/Core/SettingsSave.cls`, `Test/Web/SettingsApi.cls`, `Test/Core/Routing.cls`, `Mcp/Ops.cls` (Epic 21) | nothing | — |
| `README.md`, `GUIDE.md` (Epics 0, 21), `EXPERIENCE.md` | nothing | — |
| `Fix/*`, `Install/Step/Roles.cls`, `Install/SecurityOverview.cls`, `docs/security-overview.md`, `Test/Web/Install.cls` | nothing (V1(b)) | — |
| Spine | paragraph edits and appended rows | shared planning artifact; other lanes may edit it too |

### Veto and security items (all RULED by the Contest Planner, 2026-11-12; nothing pending)
- **V1: the `%Ens_ProductionConfig` grant. RULED: option (b).** The spine records it as Story 23.3's. The kind, the grant, the overview lines and the test exception all move to 23.3 (DW-1225). The online demo is unchanged.
- **V2: new stored data. RULED: approved as drafted.** Retention: 90 days (`daysToKeep`) through the Watch area's purge, keeping the newest snapshot of each still-watched production regardless of age, so history never restarts as "first".
  - `SettingSnapshot` (`^OcuTalonP.SettingSnap`, Lane A): Ref, Namespace (128), Production (128), TakenAt (UTC), CheckedAt (UTC), Counter, Started, Settings (`%Stream.GlobalCharacter`, a JSON array of {item, target, setting, value, source, credential, hash}).
  - `SettingChange` (`^OcuTalonP.SettingChange`, Lane A): Ref, SnapshotRef, Namespace, Production, Item, Target (`Host|Adapter`), Setting, OldValue, NewValue (MAXLEN 2000), Source (`production|default|class`), Credential (boolean), DetectedAt (UTC).
  - No user columns.
- **V3: credentials (NFR-11, AD-15). RULED: approved with conditions,** as Decided 5 and the leak-scan test apply them. A Credentials reference stores its ID. Only a secret value is dropped in the Reader and hashed (`Webhook`'s `salt.hash`) for change detection only. The hash never leaves its table, its change row is blank, and one leak-scan test pins it.
- **V4: online demo. RULED: approved.** Setting history is OFF on an online-demo install, pinned by `TestOnlineDemoOff`.
- **V5: AD amendments. RULED: approved,** with the AD-24 sentence as worded above; AD-18's `sql_query` mechanism stays (inference) until 23.8.
- **V6: public text. RULED:** 36.1 ships none and no GUIDE.md line. The proposals are approved catalog text for 36.2 and 23.3; NOTSETUP, the `ONLINESTATEMENT` rewording and the overview sentence are dropped with V1(b).

### Public text
36.1 ships no public text: no string is added to `Msg.Catalog.Watch`, EXPERIENCE.md, the security overview or GUIDE.md. The strings below are the approved catalog text (Planner, 2026-11-12) for the stories that first show them. They are kept here only as their reference (Decided 17).

Approved catalog text (reference only):
- Story 36.2:
  - `page.onCall`: "{count} {itemNoun} failed in the {production} production since {time}. {cause}.\nWhy now: you're on call for OcuTalon. Press Got it to show you're on it; if nobody does within {minutes} minutes, I'll page {backup}."
  - `page.onCallEmail`: "{count} {itemNoun} failed in the {production} production since {time}. {cause}.\nWhy now: you're on call for OcuTalon. To show you're on it, press Got it on your OcuTalon page; if nobody does within {minutes} minutes, I'll page {backup}. Replying to this email doesn't count."
  - `page.backup`: "{count} {itemNoun} failed in the {production} production since {time}. {cause}.\nWhy now: you're the backup, and nobody pressed Got it on {person}'s page within {minutes} minutes. Press Got it to show you're on it."
  - `page.backupEmail`: "{count} {itemNoun} failed in the {production} production since {time}. {cause}.\nWhy now: you're the backup, and nobody pressed Got it on {person}'s page within {minutes} minutes. To show you're on it, press Got it on your OcuTalon page. Replying to this email doesn't count."
  - `page.subject`: "OcuTalon page: {production} incident"
- Story 23.3:
  - `incident.rollbackRequest`: "{count} {itemNoun} failed since {time}. {cause}. I can put {setting} on {target} back to its earlier value. Approve?\n\nDry run: {setting} on {target}. Before: {before}. After: {after}. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page."
  - `result.settingRestored`: "{setting} on {target} is back to {after}. To undo it, ask me to undo the rollback."
  - `result.settingChangedSince`: "{setting} on {target} was not changed: it changed again after the dry run. It needs a new approval."
  - `summary.requestedRollback`: "{time}: OcuTalon asked for approval to put {setting} on {target} back."
  - `summary.settingRestored`: "{time}: {setting} on {target} was put back to its earlier value."
  - `incident.settingChangeCause`: "The feed broke {minutes} after this setting changed: {setting} on {target}, at {time}."
  - `rollback_setting` NOTALLOWED: "OcuTalon isn't allowed to change settings in that production"
  - `rollback_setting` ONLINESHARED: "On the online demo every visitor shares the Orders production, so OcuTalon doesn't change its settings there; on your own install it can"

### Measured

Task 0, measured on the lane-B warm throwaway (tag `e36s1iw`, Orders running in OCUORDERS), by a test that saved the settings through `OrdersDefinition.Put` and a System Default Setting row for `OrdersToWarehouse` through `Ens.Config.DefaultSettings`, and read `^IRIS.Temp.EnsProdModCounter("OCUORDERS")` around each step. Nothing diverged from the spine, so there is no `INTENT GAP`.

| Step | Counter before | Counter after | Result |
| --- | --- | --- | --- |
| (i) `OrdersDefinition.Put` (settings added to an item of the running production, `%Save`) | 0 | 4 | moved (+4); a second run: 10 to 14 |
| (ii) saving a test-owned SDS row (`RetryInterval` for `OrdersToWarehouse`) | 4 | 5 | moved (+1); a second run: 14 to 15 |
| (iii) a full `Reader.Settings` read (every item, every setting) | 5 | 5 | did not move; a second run: 15 to 15 |

- The counter exists (a number) once a production runs; `marks.started` read `<start time>|<check sum>`, for example `2026-11-12 21:21:18.130|475381989`.
- `PopulateVirtualSettings` lists only the class's settings (`TargetConfigName` yes; the stored `ApiKey`, `Credentials` and `ZzFixtureNote` no), so `Reader.Settings` adds each item's stored settings to its entries, as designed.
- A stored non-class setting appears in a snapshot with Source `production`; a System Default Setting on a class setting appears with Source `default` on the item it applies to; a class default with Source `class`.
- Found while testing: `%Stream.GlobalCharacter` compresses what it stores, so `SecretHandoff.Leaks` could not see text in the snapshot's stream and the leak scan had no positive control. `SettingSnapshot.Settings` therefore uses `OcuTalon.Data.SettingStream` (`COMPRESS = 0`), a stream class of its own with no state. This adds one small Lane A class beyond the task list.
- `lint_spine.py` reports `"ok": false` on this branch before and after the story's edits: the same ten low-severity `possible unfilled template token` findings, all in existing catalog-template prose (lines 497, 1072, 1146, 1159, 1228, 1239). No finding is from this story's text, and there is no `ad_id` or `ad_fields` finding.
- This worktree had no `.memlog.md` (the file is gitignored), so `memlog.py init` created one here before the `append`.

## Verification

Every command uses the lane-B variables `OCUTALON_LOCK_DIR=<lock-dir>/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=36 stage=implement'` (written `<lane-b vars>` below; expand it on each call). The fresh tag is `e36s1i` and the warm tag `e36s1iw`. Run one command per call, with `timeout: 600000`, each about 150 s at most. Never use slot B. At the end, also after a failure, run `<lane-b vars> OCUTALON_RUN_TAG=e36s1iw bash ci/warm.sh down` and `<lane-b vars> OCUTALON_RUN_TAG=e36s1i bash ci/iris.sh teardown`.

**Commands:**
- (loop) `<lane-b vars> OCUTALON_RUN_TAG=e36s1iw bash ci/warm.sh up` -- once per stage; expected: a ready stack
- (loop) `<lane-b vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e36s1iw bash ci/iris.sh class <C>`, one call for each of `OcuTalon.Test.Watch.SettingHistory`, `OcuTalon.Test.Watch.SettingDiff`, `OcuTalon.Test.Watch.SettingSecret`, `OcuTalon.Test.Watch.Evidence`, `OcuTalon.Test.Install.Retention`, `OcuTalon.Test.Install.RetentionRules` -- expected: `CLASS ... passed`
- (loop) `bash docker/tests/test-storage.sh` -- expected: pass
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: `"ok": true`
- (loop) spine-terms check -- `F=_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md; for t in '%Ens_ProductionConfig:W is granted by Story 23.3 together with rollback_setting; the demo install leaves it out.' 'EnsProdModCounter' 'OcuTalon.Watch.SettingHistory' 'OcuTalon.Data.SettingSnapshot' 'OcuTalon.Data.SettingChange' 'OcuTalon.Data.Incident.Summary' 'OcuTalon.Data.Page' 'OcuTalon.Msg.Escalation' 'OcuTalonSqlReader' 'page.onCall' 'incident.settingChangeCause' 'SaveSqlWatch'; do grep -qF -- "$t" "$F" || echo "MISSING $t"; done` -- expected: no output
- (once) `<lane-b vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e36s1iw bash ci/iris.sh shard lane-a@Watch --part k/4` for k = 1..4, then the same for `lane-a@Checks --part k/3` and `lane-a@Install --part k/3`, one call each -- expected: all passed. If a part nears 150 s, raise n. That `--part` works on a piece is (inference).
- (once) `<lane-b vars> OCUTALON_RUN_TAG=e36s1i bash ci/iris.sh class OcuTalon.Test.Watch.SettingHistory` -- a fresh stack proves the `Tick` change; expected: passed
- (once) `bash docker/tests/test-ci-config.sh` and `bash ci/checks.sh`, one per call -- expected: pass

**Mutation results (Rule 19; each applied to the file, observed red, and put back from a backup of the file, `git status` unchanged):**
- mutation: delete the AD-24 sentence from a copy of the spine -> the spine-terms check prints `MISSING %Ens_ProductionConfig:W is granted by Story 23.3 together with rollback_setting; the demo install leaves it out.`
- mutation: skip the counter compare (`Check` drops `If '..Due(...) Quit`) -> `SettingHistory.TestCounterUnchanged` (CheckedAt moves, the canary content is replaced, rows are written)
- mutation: read stored settings only (`Reader.Current` skips `PopulateVirtualSettings`) -> `SettingHistory.TestChangesRecorded` (no `default` row, and no class setting in the snapshot)
- mutation: call `%Save` on the production definition in the read (`Reader.Current`) -> `SettingHistory.TestSnapshotChangesNothing` (the counter moved; `TestCounterUnchanged` and `TestMeasuredCounter` also red)
- mutation: treat the name `Credentials` as a secret (`Reader.SettingEntry` drops its name test) -> `SettingHistory.TestCredentialsReference` (blank values; `SettingDiff.TestSettingEntries` also red)
- mutation: skip the secret check in `Reader.SettingEntry` (keep the value, no hash) -> `SettingHistory.TestSecretValue`
- mutation: store the new hash in `SettingChange.NewValue` (`SettingHistory.Change`) -> `SettingSecret.TestSecretAppearsNowhere` (the hash is also in `SettingChange`'s global; the change row's values are not blank)
- mutation: drop the online-demo guard in `SettingHistory.Watch` -> `SettingHistory.TestOnlineDemoOff`
- mutation: purge the newest snapshot too (`SettingSnapshot.Purge` ignores the kept set) -> `SettingDiff.TestPurge`
- mutation: change `SettingChange`'s `DEFAULTGLOBAL` to `^OcuTalonP.SettingChg` -> `test-storage.sh` (`registry-class`, `datalocation` and `locations` fail)
- mutation: drop `entry.reference ||` from `Reader.SettingEntry`, so only the name `Credentials` marks a reference -> `SettingDiff.TestSettingEntries` (a `SOAPCredentials` entry marked by its editor context is blanked), observed red
- mutation: `SettingSnapshot.Purge` also spares the newest snapshot of every production (its SQL excludes `MAX(ID)` per namespace and production) -> `SettingDiff.TestPurge` (a production that is not watched keeps a 95-day snapshot), observed red
- mutation: remove the per-production Try in `SettingHistory.Watch` -> `SettingHistory.TestReadFailure` (no warning for the production, and the one after it is not snapshotted), observed red
- mutation: `SettingHistory.Check` goes on after a read outcome other than `read` -> `SettingHistory.TestSkippedReads` (a snapshot is written for an unreadable and a not-current production), observed red
- mutation: add a property `Operator` to `SettingChange` -> `SettingHistory.TestChangesRecorded` (the property list is not the specified one), observed red
- mutation: `SettingHistory.Fingerprint` reads a global that does not exist -> `SettingHistory.TestSnapshotChangesNothing` (the checksum is 0), observed red
- (QA) Added `Test/Watch/SettingDiff.cls` `TestPurgeFirstError` and `TestPurgeTriesBoth` (the matrix row 'First error is returned after every table has been tried'; the Review Triage Log judged it needed a seam, but the day-count error names its caller and a second process can hold a row's lock, so none is needed) and `Test/Watch/SettingHistory.cls` `TestRestartAndCounterGone` (the matrix rows 'Restart' and 'the counter is gone', at the Tick; before this they were pinned only by the pure `Due`). No new file; all run on the Watch shard by area mapping.
- (QA) mutation: `SettingHistory.Purge` returns the snapshot purge's error ahead of the change purge's -> `SettingDiff.TestPurgeFirstError` (red, restored)
- (QA) mutation: `SettingHistory.Purge` quits on the change purge's error before the snapshot purge runs -> `SettingDiff.TestPurgeTriesBoth` (the old snapshot is not deleted; red, restored)
- (QA) mutation: `SettingHistory.Due` drops the start-mark comparison -> `SettingHistory.TestRestartAndCounterGone` (no change recorded, no new snapshot; red, restored)
- (QA) mutation: `SettingHistory.Due` ignores a missing counter -> `SettingHistory.TestRestartAndCounterGone` (the counter mark stays and CheckedAt does not move; red, restored)
- (CR) mutation: `SettingHistory.Record` saves `NewValue` without the VALUEMAX cut -> `SettingDiff.TestLongValueCut` (ERROR #5802, MAXLEN 2000 on `NewValue`; red, restored)
- (CR) mutation: `Reader.Current` maps `$$$eConfigSettingValueTypeProduction` to `class` -> `SettingHistory.TestChangesRecorded` ("with the definition's value and the source production"; red, restored)
- (rework) mutation: `Reader.Current` takes the last item of a name again (the `stPick` skip removed) -> `SettingHistory.TestSameNameItems` (the snapshot holds a disabled copy's value; the change to the enabled item is not recorded), observed red, restored
- (rework) mutation: `Reader.Current` takes the first item of a name whatever its Enabled -> `SettingHistory.TestSameNameItems` (the disabled copy placed first wins), observed red, restored
- (rework) mutation: `Reader.Current` marks every class setting a reference (the editor-context test replaced by 1) -> `SettingHistory.TestClassSettings` (`UseCookies` keeps its value and no hash; the sentinels reach the snapshot and the change row), observed red, restored
- (rework) mutation: `Reader.Current` never marks a class setting a reference (the editor-context test replaced by 0) -> `SettingHistory.TestClassSettings` (`ProxyAuthorization` is blanked and marked a secret), observed red, restored
- (rework) mutation: `SettingHistory.Due` drops the counter comparison -> `SettingHistory.TestSameNameItems` ("the Tick read the settings again: the snapshot holds the new counter" and "that is one change"), observed red, restored
- (CR2) mutation: `AddItem` appends every copy (the `InsertAt` position ignored) -> `SettingHistory.TestSameNameItems` ("the definition lists a disabled copy, then the enabled item, then the other disabled copy"), observed red, restored
- (CR2) mutation: `Reader.Current` marks every class setting a reference (the editor-context test replaced by 1) -> `SettingHistory.TestClassSettings` ("the secret is nowhere in the first snapshot's stored settings", with the rework's assertions), observed red, restored
- (CR2) verification after the re-review's patches: on the warm stack (tag e36s1c2w), `SettingHistory`, `SettingDiff` and `SettingSecret` passed, as did `lane-a@Checks` parts 1-3 of 3 and `lane-a@Install` parts 1-3 of 3. `SettingHistory` passed on a fresh stack (tag e36s1c2), and `ci/checks.sh` passed. Both throwaways were torn down.
- (CI rework 2) mutation: widen `TestOnlyRunTimeWriter`'s global pattern back to `OcuTalonP\.Setting` -> `Test.Core.SettingsOps` `TestOnlyRunTimeWriter` (the snapshot and change globals fail the pass assertions; `Data.SettingSnapshot` and `Data.SettingChange` are flagged), observed red, restored
- (CI rework 2) mutation: drop the `SettingChange` row from `Test.Data.Tables` `XData Registry` -> `Test.Data.Tables` `TestEveryTableIsRegistered` ("OcuTalon.Data.SettingChange has a registry row"), observed red, restored
- (CI rework 2) mutation: remove `OcuTalon.Data.Webhook` from `CALLBACKHELPERS` in `Test/Bridge/CodeRules.cls` -> `Test.Bridge.CodeRules` `TestWatchReadsCallOnlyListed` ("OcuTalon.Watch.Reader runs inside the callback and calls only listed callback classes"), observed red before the fix, restored with it
- (CI rework 2, review) mutation: drop the word boundary after `OcuTalon_Data\.Setting` in `TestOnlyRunTimeWriter`'s `writer` pattern -> `Test.Core.SettingsOps` `TestOnlyRunTimeWriter` ("the scanner passes an SQL write to the snapshot and change tables"), observed red, restored
- (CI rework 2, review) mutation: drop the word boundary after `\$ClassMethod\(.OcuTalon\.Data\.Setting` -> `TestOnlyRunTimeWriter` ("and a $ClassMethod call on them"), observed red, restored
- (CI rework 2, review) mutation: narrow the global branch's `[DIS]?` to `[D]?` -> `TestOnlyRunTimeWriter` ("the scanner flags the index global" and "the stream global"), observed red, restored
- (CI rework 2, review) mutation: drop the `SettingSnap` row from `Test.Data.Tables` `XData Registry` -> `TestEveryTableIsRegistered` ("OcuTalon.Data.SettingSnapshot has a registry row"), observed red, restored
- Shared-surface note: the leak-scan surfaces of `SettingSecret.TestSecretAppearsNowhere` other than the global scan (`Leaks`) have no consumer of the setting tables in this story, so they are a guard that becomes live when Story 23.3's evidence pack reads `SettingChange`; each also asserts its read produced output.

**Shared surfaces:**
- `src/short-names.tsv` (`test-storage.sh`).
- The Watch purge declaration (`RetentionRules.cls:41`, `Retention.cls` `TestNoSettingRead` and its class list).
- `Checks.Tick`'s steps (every test that drives `Test.Watch.Case.Tick`).
- `OrdersDefinition.Put` (`Test/Watch/Evidence.cls`, `Test/Eval/Record.cls`): its default call is unchanged.
- `Reader.Current`'s parameter list (every Reader method calls it; the new flag is appended last).
- The `^OcuTalon*` global set that `SecretHandoff.Leaks` scans: the two new globals hold no other test's secret.
- The spine's ownership tables.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19; one per AC, in AC order; the implement stage records each as `mutation: <change> → <red test>`):**
- Spine: delete the AD-24 sentence → the spine-terms check prints `MISSING`.
- Gating: skip the counter compare (full snapshot on every Tick) → `SettingHistory.TestCounterUnchanged` (`CheckedAt` moves).
- Changes recorded: read stored settings only, without the `PopulateVirtualSettings` entries → `SettingHistory.TestChangesRecorded` (no `default` row).
- Read-only: call `%Save` on the production definition in the read → `SettingHistory.TestSnapshotChangesNothing`.
- Credentials reference: treat the name `Credentials` as a secret → `SettingHistory.TestCredentialsReference` (blank values).
- Secret value: skip the secret check in `Reader.Settings` (keep the value, no hash) → `SettingHistory.TestSecretValue`.
- Leak scan: store the new hash in `SettingChange.NewValue` → `SettingSecret.TestSecretAppearsNowhere` (`Leaks(hash)` also names `SettingChange`'s global).
- Online demo: drop the online-demo guard → `SettingHistory.TestOnlineDemoOff`.
- Purge: purge the newest snapshot too → `SettingDiff.TestPurge`.
- Storage: change `SettingChange`'s `DEFAULTGLOBAL` to one not in `short-names.tsv` → `test-storage.sh`.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Setting history is recorded for each watched production. `Reader.Settings` reads the production-change counter, the start mark and (when due) every item's effective settings inside `Current`; `Reader.SettingEntry` keeps a Credentials reference's ID and blanks a secret value, keeping a salted hash. `Watch.SettingHistory.Watch` runs from `Checks.Tick` (one line), takes a snapshot only when there is none, a mark moved or an hour has passed, and writes `SettingSnapshot` and `SettingChange` rows in one transaction, with `DetectedAt` = the Tick's time. It is off on an online-demo install. The Watch area's purge runs `SettingHistory.Purge`, which keeps the newest snapshot of each watched production. The spine holds the step-5 Lane A contracts (AD-15, AD-16, AD-18, AD-24, AD-29, payload, paging, catalog keys, ownership tables, Deferred). Task 0 was measured (see Design Notes, Measured): the counter behaves as the spine says.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls`: `Settings`, `SettingEntry`, `SaltKey`, and the trailing `Current` flags.
- `src/ocutalon/cls/OcuTalon/Watch/SettingHistory.cls`: new; `Watch`, `Check`, `Due`, `Record`, `Diff`, `Purge`.
- `src/ocutalon/cls/OcuTalon/Data/SettingSnapshot.cls`, `Data/SettingChange.cls`, `Data/SettingStream.cls`: the two tables and an uncompressed stream class (so a leak scan can see the stored text); `src/short-names.tsv`: two rows.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls`: the one `Tick` line. `Install/Step/Watch.cls`: `Purge` runs both purges.
- `src/ocutalon/cls/OcuTalon/Test/Watch/SettingDiff.cls`, `SettingHistory.cls`, `SettingSecret.cls`: new tests; `Test/Watch/OrdersDefinition.cls`: `Put` gains `only`; `Test/Install/Retention.cls`: word boundary and extra assertions.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: the additions.

**Review.** Four layers reported 37 findings (grouped into 27 rows in the Review Triage Log): patches applied 8 (three medium, all missing tests: the Credentials-reference editor-context branch, the unreadable / not-current / read-throws paths, and the purge of a production that is not watched; five low: the no-user property list, the fingerprint control, the cross-area row, the stopped-production dating wording), deferred 1 (the pre-existing `lint_spine.py` placeholder findings), rejected 18 low and 1 false with the reasons in the log.

**Follow-up review recommended: false.** Three medium findings were patched (all missing tests, added with their mutations observed red), none high; the patched tests ran green on the warm stack, in the Watch, Checks and Install shards and on a fresh stack, so no unverified risk remains.

**Verification performed.** Warm stack (tag e36s1iw): `Test.Watch.SettingHistory`, `SettingDiff`, `SettingSecret`, `Evidence`, `Test.Install.Retention`, `RetentionRules` passed after the last patch; `test-storage.sh` passed; the spine-terms check printed nothing; `lint_spine.py` reports the same 10 low findings as the baseline (`"ok": false`, none new). Once, after the last patch: `lane-a@Watch` parts 1 to 4 of 4, `lane-a@Checks` parts 1 to 3 of 3 and `lane-a@Install` parts 1 to 3 of 3 passed (Watch part 1 took 330 s, above the 150 s sizing; it passed); `SettingHistory` passed on a fresh stack (tag e36s1i); `test-ci-config.sh`, `ci/checks.sh` and `test-boundaries.sh` passed. Both throwaways were torn down.

**Residual risks.**
- The first AC's `"ok": true` for `lint_spine.py` is not reachable (deferred above); the check is read as "no new finding".
- `Reader.Current` keeps its existing per-production reads, so the marks-only read each Tick costs about one more read of the production per minute.
- A change row's values are cut at 2000 characters; Story 23.3 must refuse to roll back a cut value.
- `TestReadFailure` reaches a second watched entry through the lower-case spelling of the Orders namespace (the `Namespace` column is case-exact); a stack whose service user cannot read `ocuorders` by that spelling would fail it.
- The spine's `.memlog.md` is gitignored and was created in this worktree, so the `memlog.py append` for this story is not in the commit.

**Rework iteration 1 (this pass only).** Both open `[Review]` items are done. `Reader.Current`'s settings block takes one item per name, the first that is enabled as IRIS runs it, else the first (`Reader.cls`); `Test/Watch/SettingHistory.cls` gained `TestSameNameItems` (disabled copies before and after the enabled item, and a name with no enabled item) and `TestClassSettings` (a `credentialsSelector` class setting keeps its ID, a secret-named class setting is blank with a hash that never reaches `SettingChange`), with their helpers and four `(rework)` mutations plus one for the read check, each observed red. The follow-up review's patches: the `Reader.Items` doc claim removed, the read check in `TestSameNameItems`, and two test-helper status fixes; one low finding is deferred (the evidence block takes the first same-name item). Follow-up review recommended: false (no high patched; one medium test gap patched). Verification: `SettingHistory`, `SettingDiff`, `SettingSecret`, `Evidence`, `Retention`, `RetentionRules` and `test-storage.sh` green on the warm stack; `lane-a@Watch` parts 1 to 8 of 8 green after the last patch; `SettingHistory` green on a fresh stack; `test-boundaries.sh` passed; both throwaways torn down. Residual risk: `TestClassSettings` needs `EnsLib.HTTP.GenericOperation` to keep `ProxyAuthorization` as a credentials selector and `UseCookies` as a secret-looking name; the System Default Setting `Enabled` override of the pick has no live test (rejected as low).

**Rework iteration 2 (CI) -- this pass only.**
- Changed: `Test/Core/SettingsOps.cls` (`TestOnlyRunTimeWriter`: boundaries on the global, SQL and `$ClassMethod` branches, with flag and pass assertions), `Test/Data/Tables.cls` (two registry rows appended; append-only, the file is also in Epic 21's diff), `Test/Bridge/CodeRules.cls` (`OcuTalon.Data.Webhook` appended to `CALLBACKHELPERS`, with its comment; a footprint extension for the lead).
- Review: 16 findings -- high 0, medium 3 (one root cause, patched), low 10, false 3; patches applied: 1 medium and 4 low; rejected with reasons in the Review Triage Log.
- Follow-up review recommended: false (no high patched on this follow-up pass); the patched count is medium 1 (one root cause), high 0.
- Verification: the failing tests red before the fix and green after on a warm lane-B throwaway (tag e36s1r2w, torn down); `Test.Core.SettingsOps`, `Test.Data.Tables`, `Test.Bridge.CodeRules` and the 18 sweep classes passed; shard parts `lane-b@Core` 4/4, `lane-b@Data` 2/2 and `lane-a@Watch` 3/4 passed (`lane-b@Core` 4/4 was run twice by mistake); `docker/tests/test-boundaries.sh` passed.
- Residual risk: the sweep ran on the warm stack only, and found its classes by reading the tests, not by an exhaustive proof.
