---
title: 'Story 17.5: Check the vital signs and every coverage entry'
type: 'feature'
created: '2026-11-05'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-17-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The digest (Stories 17.6 and 17.7) needs a coverage list in which every entry is passed, failed, or not checked with a reason. Today:
- Nothing builds that list. Story 33.1 named `OcuTalon.Checks.Coverage.Build` in the spine but left no stub.
- Nothing reads the vital signs.
- Nothing writes `Digest.Data.CheckRun`.
- Nothing seeds the `checks.thresholds.*` keys.
- Nothing purges `CheckRun` or `Sent`.

**Approach:**
- Every background-check run gets a `CheckRun` row. A trigger on the `BackgroundCheck` update writes it, through `Checks.Coverage.RecordRun`, so the contended `Checks/Process.cls` is not edited.
- New reads go into `Watch.Reader`:
  - the vital signs;
  - a production's items in error and its queues.
- `Checks.Coverage.Build` builds the rows and catalog lines by AD-18's rules, reading the thresholds through `Data.Setting.Get`.
- The digest install step seeds the thresholds and declares the one new privilege.
- The digest area's purge also covers `CheckRun` and `Sent`.

## Boundaries & Constraints

**Always:**
- **What the list holds.** `Build(sessionRef, fromUtc, toUtc, Output rows, Output lines, Output vitals) As %Status` returns rows in this order, and never drops an entry:
  1. Five vital-sign rows, always present: `IRIS instance`, `database space`, `journal space`, `license use`, `system log`.
  2. One row per `BackgroundCheck` row of the session (`Data.Ownership.Checks`), in ID order. A production watch's entry is `Tools.WatchAnswers.#ENTRY` (`{name} production`).
  3. No source rows: the sources section stays empty until step 4.
- **The output shapes.**
  - Each row is release 1's `{result, entry, finding, checkedAt}` (UTC `YYYY-MM-DDThh:mm:ssZ`).
  - `lines` holds one `{key, slots}` per row, in the rows' order.
  - `vitals` is `{"rows": <the five vital rows>, "figures": {"upDays", "databasesFull", "licenseUse"}}`. Each figure is a whole number, or "" when its sign was not read.
- **The result of a background check (AD-18).** Its span runs from max(`fromUtc`, `CreatedAt`) to `toUtc`. The first rule that applies wins:
  1. **paused:** a `Schedule.Heartbeat.Gaps(spanStart, toUtc)` gap overlaps the span. `from` and `to` are the gap clamped to the span, with an open end read as `toUtc`.
  2. **No run in the span:**
     - **stale** when an earlier run exists (`time` is that run's `RanAt`);
     - **missed** when the check never ran (`from` = span start, `to` = `toUtc`). This settles DW-648.
  3. **missed:** two consecutive runs, or the span start and the first run, or the last run and `toUtc`, are more than 180 s apart. `from` and `to` are the first such gap.
  4. **The latest run is `not_checked`:** its `Reason` is mapped through a fixed table: `error` → `notCheckedError`, `timeout` → `notCheckedTimeout`, `unreachable` → `notCheckedUnreachable`. An empty or unknown reason gives `notCheckedError` (DW-648).
     - For `unreachable`, `time` is the first run of the trailing unbroken streak of unreachable runs.
     - For the other reasons, `time` is the latest run's `RanAt`.
  5. **Otherwise** the latest run's `failed` (with its finding) or `passed`, at its `RanAt`.
- **A production watch adds a live read** whenever rule 5 applies. `Watch.Reader.Failures` reads, in one switch, from the span start:
  - the running state;
  - the disabled items;
  - the items in error;
  - the queues;
  - the failures, counted with the session scoping that `Checks.Process.Run` uses (`FailurePoller.Scope` with `Reader.OnlineDemo`).

  How the live read changes the row:
  - If it finds anything, the row is `failed` with the live finding, at the read time. The finding is listed in the "For the lead" note.
  - If the read is `unreadable` or `not_current`, the row is `not_checked`, `unreachable`.
  - If the read times out, the row is `not_checked`, `timeout`.
  - If the read throws, the row is `not_checked`, `error`.
- **The thresholds.** Every `Build` reads them through `Data.Setting.Get(key, default)`. The defaults come from `Checks.Coverage` parameter `THRESHOLDS`: disk 10, journal 10, license 90, queue 100 messages, queue 10 minutes.
  - **failed** when database free < `diskFreePercent`, journal free < `journalFreePercent`, license use > `licenseUsePercent`, any severity-2 or 3 line in `messages.log` within [`fromUtc`, `toUtc`], or a queue with more than `queueMessages` messages or an oldest message waiting more than `queueWaitMinutes`.
  - The comparisons use the unrounded values. Only the figures are rounded (DW-648).
- **Database free share.** For each database it is the volume's free share (`%File.GetDirectorySpace`). When `MaxSize` is set, it is the smaller of that and (`MaxSize` - `Size` + `Available`) / `MaxSize`.
  - The databases are OcuTalon's (code, data, private and public, found through `%SYS.Namespace` with no switch) plus the code and data databases of each watched production's namespace.
  - The database read checks that the service user holds `%Admin_Operate:U` (`CheckUserPermission`). If it doesn't, the row is `not_checked` `error` with the finding `Checks.Process.#REASONREAD`.
  - Uptime (`$ZH`), license (`$SYSTEM.License`), journal (`%SYS.Journal.System` + `%File`) and `messages.log` (in `$SYSTEM.Util.ManagerDirectory()`) need no IRIS privilege. Only counts and percentages leave the reader, never a log line's text.
- **When a read fails.** A vital read that fails gives `not_checked` `error`, finding `#REASONREAD`. So does a license with `KeyLicenseUnits()` <= 0.
- **The reader's rules (AD-3, AD-24).** Only `Watch.Reader` reads, and only `Reader.Current` switches namespace. The new privilege is declared by `Install.Step.Digest.Grants()`, so the generated security overview lists it.
- **Recording runs.** `CheckRun` gets one row per `LastRunAt` change, with `CheckRef` = `Ref`, `HeaderId` = `LastRunHeaderId`, and `Reason` mapped from a `not_checked` `Finding`:
  - `REASONTIMEOUT` → `timeout`;
  - `REASONUNREADABLE` or `REASONNOTCURRENT` → `unreachable`;
  - anything else → `error`.

  A failed `CheckRun` write logs a warning and never fails the `BackgroundCheck` update.
- **Seeding.** `Install.Step.Digest` joins `Registry.Order()` after `Demo`. Its `Run()` seeds the five keys as `seed` values, through a new `OcuTalon.Install.Seeds` helper. The step itself still names `OcuTalon.Data.Setting` nowhere (`Test.Install.Retention TestNoSettingRead`).
- **Purges (DW-646).** `Install.Step.Digest.Purge` runs `Item`, `CheckRun` (`RanAt`) and `Sent` (`SentAt`), each through `Bridge.Time.DaysCutoff`, and returns the first error after running all three. Each session's newest `Sent` row is kept.
- **Source rules.** ASCII source and contract-only comments (Rule 14). Append-only storage: no storage or property change to any persistent class.

**Never:**
- An edit to an existing contended file: `Checks/{Beat,Process}.cls`, `Test/Checks/**`, `Test/Eval/**`, `Test/Data/Tables.cls`, `Test/Data/Fixture.cls`, `Test/Contract/Ac.cls`, `Test/Core/**`, `Test/Install/{SecurityOverview,Production,PrivateData}.cls`, `ci/units.sh`, `src/short-names.tsv`, the spine.
- An edit to any Lane B class or test (U-177).
- A write to a Lane B table other than `Data.Setting.Seed` from `OcuTalon.Install`. Tests use the `CoverageProbe` seam for heartbeat gaps.
- Digest composition, sending, the all-clear choice or a vital-sign sentence (Stories 17.6 and 17.7). `digest.time` and `digest.channels` seeds are 17.6's.
- New catalog keys, or user-facing text beyond the list under Design Notes.
- Destructive work on `ocutalon-slot-a`, `SYS.Stats.Dashboard`, a `%SYS` switch, or a purge that reads `Data.Setting`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| All passing | 1 watch, runs every 60 s in the window, no gap, healthy vitals | 6 rows, all `passed`; lines `digest.passed`; figures whole numbers | none |
| Item in error / disabled / stopped / backlog | live read: an item with `%Status` Error; a disabled item; state `stopped`; a queue of 101 or oldest 11 min | the watch row `failed` with that finding at the read time | none |
| Low disk / journal / license / syslog | DB free 9.6%; journal 8%; license 91%; 2 sev-2 lines in the window | that vital row `failed`; `databasesFull` 90 (rounded), compared unrounded | none |
| No privilege | service user lacks `%Admin_Operate:U` | `database space` `not_checked`, `error`, `Couldn't be read` | no throw |
| Heartbeat stopped > 3 min | gap 10:00-10:05 in the window, later runs passed | the watch row `not_checked`, `digest.notCheckedPaused` from/to | none |
| Missed / never ran / stale | runs 4 min apart; no run ever; last run before the span | `notCheckedMissed`; `notCheckedMissed` span start to `toUtc`; `notCheckedStale` | none |
| Check errored | latest run `not_checked`, Finding `Couldn't be read` | `digest.notCheckedError` at its `RanAt` | none |
| Unknown reason | a CheckRun `not_checked` with Reason "" or `zz` | `digest.notCheckedError` | none |
| Run recorded | `Checks.Process` runs a due watch (timeout) | one CheckRun: `not_checked`, `timeout`, HeaderId = the run's session | a CheckRun failure only warns |
| Admin threshold | `licenseUsePercent` saved 95 through `SettingsOps`; cache expired | license 91% `passed` | none |


**Owner rulings of 2026-11-05 (binding on re-derivation).** U-290 REVERSED by the Contest Planner (owner's delegation): OcuTalon does NOT grant `%Admin_Operate:U` (or any new privilege) to `OcuTalonServiceRole`. Database space is read without it (the volume's free share); a database that has a maximum size the service user cannot read is reported `not_checked` with one plain reason, and never counted as passed, so a capped database can never give a false all-clear. That reason's text is new user-facing text: propose it verbatim under Design Notes as "Proposed text (for the Planner)"; the lead sends it to the Planner before the code is committed. U-291 KEPT: the vital-sign texts listed under Design Notes stand. AD-28 extension ALLOWED (orchestrator ruling under U7, the Planner agreeing; written into the spine): `Checks.Coverage.Build` has the optional sixth output `vitals`.
</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/`; `irislib/` is the IRIS reference export (read only).

- `Checks/Process.cls` (read only; contended, Epic 39). Anchors:
  - `Run` :304; the scoping loop :325-329.
  - `Record` :379, with the `UPDATE` at :382.
  - `Finding` :492; the `REASON*` parameters :106-114, `FINDING*` :85-103 (reuse via `$Parameter`), `INTERVALSECONDS` 60.
  - `Read` :542, the seam.
- `Checks/Render.cls` (read only). Release 1's row normalisation: `Row` :82. It drops any field outside the four.
- `Data/BackgroundCheck.cls`. Properties `Ref`, `SessionRef`, `CreatedAt`, `LastRunAt`, `Result`, `Finding`, `LastRunHeaderId`. No triggers exist in `src/` today.
- `Digest/Data/CheckRun.cls`, `Sent.cls`: no methods. `Item.cls` `Purge` :64-75 is the sibling (`DaysCutoff` + `DELETE ... < ?`). `Test/Digest/Contracts.cls` pins their shape; keep it unchanged.
- `Watch/Reader.cls`:
  - `Readable` :162; `Failures` :179 (8 arguments, called by `Process`, `FailurePoller` and `Fix.Executor`).
  - `Current` :255, the only `New $NAMESPACE`.
  - Items in error: `$$$GetHostMonitor(host,"%Status")="Error"` (Ensemble.inc :169-180).
  - Queues: `Ens.Queue` / `Ens.MessageHeader` `Status=2` (Task 0).
- The vital-sign APIs, measured in this plan (see Design Notes, "Measured"). None needs a privilege, and none switches namespace:
  - `%SYS.Namespace` `GetAllNSInfo` (code and data directories) and `GetGlobalDest` (the private and public databases, as `Install/Step/PrivateData.cls` :66 and `Demo.cls` :207 use it).
  - `##class(%File).GetDirectorySpace(dir, .free, .total, 0)` (`irislib/%Library/File.cls` :411): the volume's free and total bytes.
  - `$$GetDatabaseInfo^%SYS.DATABASE(dir, .info)` (`irislib/%SYS/DATABASE.int` :23): comma pieces 2 block size, 4 size in MB, 6 maximum size in blocks (0 = no maximum).
  - `%SYS.Journal.System` `GetPrimaryDirectory()`; `$SYSTEM.License` `KeyLicenseUnits()`, `LUConsumed()`; `$SYSTEM.Util.ManagerDirectory()` + `messages.log` through `%Stream.FileCharacter`; `$ZH`.
  - Never called: `%SYS.DatabaseQuery` (`irislib/%SYS/DatabaseQuery.cls` :19-89, each method requires `%Admin_Operate:U`) and `GetFreeCount^%SYS.DATABASE` (:2265, switches to `%SYS`).
- `Tools/WatchAnswers.cls`: `ENTRY` :45, `CheckResults` :202. `Data/Ownership.cls` `Checks(sessionRef, .sc)` :276.
- `Schedule/Heartbeat.cls` `Gaps(from, to)` :87 gives `[{start, end, missed}]`; Lane B's, pinned by `Test/Schedule/Heartbeat.cls` :266.
- `Data/Setting.cls`: `Get(key, default)` :39 (60 s cache `^||OcuTalon.Setting`), `Seed` :57. Lane B's; only `OcuTalon.Install.*` may call `Seed` (`Test/Core/SettingsOps.cls` ~:346).
- `Core/SettingsOps.cls` (Lane B, read only): XData `Sections` :196-201 holds the threshold defaults and bounds; `Sections()` :208.
- `Install/Step.cls`: `Grants()` returns `[]` by default, so a step that doesn't override it declares nothing.
- `Install/Registry.cls`: `Order()` :12, `Areas()` :20, `Declared` :137, `Purge` :111. `Test/Install/Registry.cls` `TestOrder` :123-126 pins `Order()` (15 steps).
- `Install/Step/Digest.cls`: `Purge` only. Sibling for seeding: `Install/Step/Web.cls` `SeedSettings` :103.
- `docker/tests/lib-live.sh` `expected_run` :676-684 writes out every registry step in order; `test-install-start.sh`, `test-install-upgrade.sh`, `test-audit.sh` and `test-lib-live.sh` all use it, so it is the one list to update. Not contended (Epic 34 changes `test-lib-live.sh`, which needs no edit).
- `Msg/Catalog/Watch.cls` :338-441, the `digest.*` keys:
  - `passed` and `failed` take `{entry, finding?, time}`.
  - `notChecked{Error,Timeout,Unreachable,Stale}` take `{entry, time}` (no finding slot).
  - `notChecked{Missed,Paused}` take `{entry, from, to}`.
  - `healthy` takes count slots; `Msg/Catalog.cls` `count` :256 rejects non-integers.
- Tests to reuse:
  - `Test/Checks/Probe.cls` (`Read` :67, `Feed` :203) and the `Test/Checks/Runs.cls` helpers `Host` :903, `Tick` :1013. Use them, don't edit them.
  - `Test/Data/Fixture.cls` `Check(...)`.
  - `Test/Digest/Store.cls` purge tests :389-453 and `NewRow` :618.
  - `Test/Watch/Case.cls`: `TempStopItem` :1085, `SetItemEnabled` :1174; it mutates the Orders production, so throwaway only.
  - `Test/Install/Retention.cls`: `Seed` :293 (Digest :330-339), `TestOcuTalonPurge` :247, `Cleanup` :435.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (measure on warm throwaway `e17s5iw`, record under Design Notes "Measured"):
  - `messages.log` timestamp zone on a stack whose `TZ` is not UTC;
  - reading a host's `%Status` Error and a queue's count and oldest age inside `Current`;
  - an AFTER UPDATE trigger firing on `Process`'s SQL `UPDATE`, and a caught error inside it leaving the update applied.

  If a measurement contradicts a rule above, stop with Clarification Needed.
- [ ] `Watch/Reader.cls`:
  - add `Vitals(namespaces As %List, fromUtc, toUtc) As %DynamicObject`: raw, unrounded readings and a per-sign outcome (`read` or `error`), no switch. `databases` is one `{name, directory, volumeFreePercent, maxBlocks, outcome}` per distinct directory: OcuTalon's code, data, private and public, plus the code and data of each namespace in `namespaces`. `name` is the directory's last folder, upper case.
  - add `Database(directory) As %DynamicObject`, that one entry, which `Vitals` uses and `Test.Watch.Vitals` calls;
  - give `Failures` two optional trailing outputs, `errored` (item names) and `queues` (`[{name, count, oldestAt}]`), filled inside `Current`'s one switch. Existing callers are unchanged.
- [ ] `Checks/Coverage.cls` (new):
  - `Build` as fixed above, with the database-space rule under Design Notes;
  - `RecordRun(ref, sessionRef, ranAt, result, finding, headerId)`, the one CheckRun writer, which catches its own errors;
  - parameters: `THRESHOLDS`, the entries and findings of U-291, and `REASONSIZELIMIT` (the proposed text);
  - private seams `Vitals`, `Read` and `Gaps` that wrap `Watch.Reader` and `Heartbeat.Gaps`.
- [ ] `Data/BackgroundCheck.cls`: add `Trigger RecordRun [Event=UPDATE, Foreach=row/object, Time=AFTER]`. It calls `Checks.Coverage.RecordRun` when `{LastRunAt*C}` and the new `LastRunAt` is not empty.
- [ ] `Digest/Data/CheckRun.cls`, `Digest/Data/Sent.cls`: add `Purge(daysToKeep)` on `Item.Purge`'s pattern; `Sent` keeps each session's newest row.
- [ ] `Install/Seeds.cls` (new, not a step): `Defaults(seeds As %DynamicObject) As %Status`, which calls `Data.Setting.Seed` for each key.
- [ ] `Install/Step/Digest.cls`: add `Run()` (seeds `Checks.Coverage.#THRESHOLDS` through `Install.Seeds`); `Purge` runs all three purges. No `Grants()` override. `Install/Registry.cls` `Order()`: add `Digest` after `Demo`.
- [ ] Update `Test/Install/Registry.cls` `TestOrder` (16 steps, `Digest` after `Demo`), `docker/tests/lib-live.sh` `expected_run` (`'STEP Digest OK'` after `'STEP Demo OK'`) and `Test/Install/Retention.cls` (61- and 59-day `CheckRun` and `Sent` fixtures, the asserts, `Cleanup`).
- [ ] Tests (new; no `ci/units.sh` edit):
  - `Test/Digest/CoverageProbe.cls` (seams fed from `^||CoverageProbe`);
  - `Test/Digest/Coverage.cls`: every matrix row and every database-space case below, on the probe; the Gaps signature through the class dictionary;
  - `Test/Digest/Runs.cls`: the trigger and `Checks.Process` through `Test.Checks.Probe` to `Build` (the integration AC);
  - `Test/Digest/Thresholds.cls`: seeds, upgrade keeps, defaults equal `SettingsOps.Sections()`, an admin value used after the cache, and `Install.Step.Digest.Grants()` empty;
  - `Test/Digest/Purge.cls`;
  - `Test/Watch/Vitals.cls` (throwaway): real reads of the five signs; OcuTalon's databases read with `maxBlocks` 0 and a volume share; a database the test creates with `$$CreateDatabase^%SYS.DATABASE` and a 50 MB maximum in a temporary folder reads `maxBlocks` > 0, and is removed with `DeleteDatabase` and its folder; errored and queue reads on Orders.

- [ ] Ruled public text and key (Contest Planner, 2026-11-06; Design Notes "Ruled text" and "Digest line"): `Checks.Coverage` parameter `REASONSIZELIMIT` = `OcuTalon can't read this database's size limit`; new key `digest.notCheckedSizeLimit` in `Msg/Catalog/Watch.cls`, text `Not checked: {entry} (OcuTalon can't read this database's size limit).`; `Build` gives it to the capped-database row; Lane B `Test/Msg/Catalog.cls` gets the key's fixture row and the count 152 with a U-177 marker (the one-time exception; nothing else in Lane B); any web catalog test the key trips is fixed. A fixed-strings test pins both texts byte for byte (the parameter, and the key rendered for `database space`), with the mutation shown.

**Acceptance Criteria:**
- Given a session with a watched production and healthy fixtures, when `Build` runs for its window, then `rows` holds the five vital rows, the watch row and no source row; `lines` matches them one to one; and `vitals.figures` are whole numbers.
- Given a fresh install and an upgrade with an admin-changed `licenseUsePercent`, when the installer runs, then the five keys exist with their defaults on the fresh install and the changed value is kept on the upgrade.
- Given an admin threshold saved through Lane B's `SettingsOps` path, when `Build` runs after the 60-second cache, then it uses the new value.
- Given the integration of a `Checks.Process` run (real `Run`/`Record` through the shadow `Test.Checks.Probe`), when the run records its result, then one `CheckRun` row with the mapped `Reason` and the `HeaderId` exists, and `Build` derives that entry's row from it.
- Given the installed service user, which holds no `%Admin_Operate`, when the vital signs are read, then a database with a maximum size makes `database space` `not_checked` with `REASONSIZELIMIT` (never `passed`); with no such database the row is `passed` or `failed` from the volume share; and the security overview's generated privilege list is unchanged, because the digest step declares no grant.
- Given `CheckRun` and `Sent` rows 61 and 59 days old, when the OcuTalon purge task runs with `DaysToKeep` 60, then the 61-day rows are gone (except a session's newest `Sent`) and the 59-day rows remain (DW-646).

## Spec Change Log

- 2026-11-06 lead: Planner ruling (a) applied: new key `digest.notCheckedSizeLimit` for the capped-database row, one-time U-177 exception for the `Test.Msg.Catalog` fixture row and count (152) only; any web catalog test the key trips is fixed.

- 2026-11-06 lead: the capped-database reason text ruled by the Contest Planner (owner's delegation): "OcuTalon can't read this database's size limit", pinned by a fixed-strings test; the digest line's key is with the orchestrator (U-177).

- 2026-11-05 lead: re-plan for the U-290 reversal (no new privilege; capped database not_checked with a plain reason); U-291 kept; AD-28 `vitals` allowed. Status reset to draft.

## Review Triage Log

## Design Notes

**Reading the contract after the 2026-11-05 rulings.** The rulings paragraph at the end of the contract is binding and replaces these lines above it:
- Approach, "declares the one new privilege": the digest step declares none.
- Always, "Database free share": the `MaxSize` formula, (`MaxSize` - `Size` + `Available`) / `MaxSize`, and the third sub-bullet (`%Admin_Operate:U` through `CheckUserPermission`, finding `#REASONREAD`). Both are replaced by the database-space rule below. `Available` is the part only `%Admin_Operate:U` can read (measured), so the ruling's "a maximum size the service user cannot read" means a database that has a maximum: its free share within it can't be read, and the row is `not_checked`.
- Always, "The reader's rules", second sentence (`Grants()` and the overview): there is no new privilege, so the overview doesn't change.
- Matrix row "No privilege": replaced by the "Capped database" cases below.

Everything else in the contract stands.

**The database-space rule (U-290 as reversed).** For each database, `volumeFreePercent` = free / total of its volume, and `maxBlocks` is read without privilege. The row's result, first match wins:
1. **failed** when any database's `volumeFreePercent` < `diskFreePercent`. A maximum can only lower the free share, so this is certain. The finding lists each low database (`{name} {n}% free`, joined with ", ").
2. **not_checked**, reason `error`, finding `#REASONREAD`, when any database could not be read.
3. **not_checked**, reason `error`, finding `REASONSIZELIMIT`, when any database has `maxBlocks` > 0. Its free space within the maximum needs `%SYS.DatabaseQuery`, which requires `%Admin_Operate:U`; OcuTalon never calls it and grants nothing.
4. **passed** otherwise.

`figures.databasesFull` is 100 minus the lowest `volumeFreePercent`, rounded, when the row is `passed` or `failed`, and "" when it is `not_checked`.

| Database case | Expected `database space` row |
|---|---|
| all without a maximum, lowest volume 40% free | `passed`; `databasesFull` 60 |
| one with a 50 MB maximum, volume 40% free | `not_checked`, `notCheckedSizeLimit` (ruled 2026-11-06), finding `REASONSIZELIMIT`; `databasesFull` "" |
| one with a maximum, its volume 8% free | `failed`, `{name} 8% free` |
| one read error, another with a maximum | `not_checked`, finding `Couldn't be read` |

**Ruled text (Contest Planner under the owner's delegation, 2026-11-06T02:37:12Z; replaces the proposal "No read access to the free space within a database's size limit").** The one new user-facing text, `Checks.Coverage` parameter `REASONSIZELIMIT`, shown as the `database space` row's finding, is exactly:

> OcuTalon can't read this database's size limit

- Pin it with a fixed-strings test: the parameter's value equals that text byte for byte (ASCII apostrophes, no trailing period), with the mutation shown.
- **Digest line (Contest Planner ruling under the owner's delegation, 2026-11-06 ~04:40Z, option (a); binding).** A new catalog key `digest.notCheckedSizeLimit` in `Msg/Catalog/Watch.cls`, text exactly `Not checked: {entry} (OcuTalon can't read this database's size limit).` (trailing period included), one slot `entry` (`text`), `source` an ASCII line citing this ruling (e.g. `Contest Planner ruling 2026-11-06 (owner delegation): Daily digest / Coverage line, not checked: capped database`). `Coverage.Build` gives the capped-database `database space` row (rule 3 below) this key instead of `digest.notCheckedError`; the row's reason stays `error` and its finding stays `REASONSIZELIMIT`. Rendered for `database space` it reads `Not checked: database space (OcuTalon can't read this database's size limit).`
- **One-time U-177 exception (this ruling), scoped to the catalog-count test only:** add the key's fixture row to Lane B's `Test/Msg/Catalog.cls` (`Fixtures`), raise the asserted count from 151 to 152, and put a U-177 marker comment beside the change citing this ruling (Contest Planner, 2026-11-06). Fix any web catalog test the new key trips (the page's generated catalog module reads `Watch.cls`). Nothing else in Lane B: any other Lane B edit is `## Clarification Needed`. Story 17.6's `digest.cost` takes the count to 153 under the same ruling.
- Any text in this spec that names `digest.notCheckedError` for the capped case is superseded by this ruling; the other not-checked cases keep their keys.

- It follows release 1's `No read access to its namespace`.
- [SUPERSEDED 2026-11-06 by the Planner's ruling (a): the capped row uses `digest.notCheckedSizeLimit`.] The row's digest line is the existing `digest.notCheckedError` ("Not checked: database space (the check stopped with an error at {time})."), because the catalog's not-checked lines carry no finding and the contract keeps reason `error` for an unreadable vital and forbids new keys. The alternative is `notCheckedUnreachable` ("unreachable since {time}"); the Planner may choose it.

**Measured (plan stage, 2026-11-05, lane-A warm throwaway `e17s5pw` with OcuTalon installed, build 154; torn down).** A process logged in as a throwaway user holding only `OcuTalonServiceRole` (plus `%DB_USER` and `%Service_Terminal`, so that the session could run):
- `$SYSTEM.Security.Check("%Admin_Operate","USE")` 0, and `CheckUserPermission("OcuTalonService","%Admin_Operate","U")` 0.
- `%File.GetDirectorySpace` read 405,808,336,896 of 539,977,244,672 bytes free: the volume read needs no privilege.
- `$$GetDatabaseInfo^%SYS.DATABASE` (same as `$zu(49,dir)`) read every OcuTalon database. Piece 6 was 6400 (50 MB at 8192 bytes) on a database given a 50 MB maximum, and 0 on the others.
- `%SYS.DatabaseQuery.GetFreeSpace`: `ERROR #921: Operation requires %Admin_Operate:USE privilege`.
- `GetAllNSInfo("OCUTALON")`, `KeyLicenseUnits()` (8), `LUConsumed()` (1), the journal directory and its volume, `messages.log` (928 lines) and `$ZH` all read.
- Every database of the stack has no maximum (`%SYS.DatabaseQuery` FreeSpace as `%All`: `MaxSize` "Unlimited" for all 19). So on a default install `database space` is `passed` or `failed`, and only an admin-set maximum gives `not_checked`.
- The volume share, not the database file's own free share, is the measure: the file's own was 3-4% for `OCUTALON_CODE` and `OCUTALON_DATA`, with 75% of the volume free.
- The stack's `TZ` was empty (UTC), so the `messages.log` zone stays in Task 0.

**Governing ADs (Rule 6):** AD-3, AD-18, AD-19, AD-24, AD-27, AD-28, AD-29 and AD-33. No AC contradicts an AD's Rule.
- AD-3: `Watch.Reader` is the one reader; only `Current` switches namespace. The vital reads switch nothing.
- AD-18: the coverage rules and `CheckRun`.
- AD-19: `seed` values, seeded by the digest area's install step.
- AD-24: no OcuTalon role gains a privilege, so the generated overview is unchanged.
- AD-27: area purges, no setting read.
- AD-28: results only from `Checks`; the vital-sign sentence stays `Render`'s (17.7). The `Build` contract row with `vitals` is already in the spine.
- AD-29/AD-33: lanes, and table owners. `CheckRun`, `BackgroundCheck` and `Sent` are Lane A's; `Data.Setting` and `StatusMark` are Lane B's, and 17.5 only reads them (and seeds through `Install`).

**Ledger (Rule 17).**
- DW-646 is addressed by the purge task, the Retention update and the last AC.
- DW-648 is addressed by result rules 2 and 4, the rounding rule, and the "Never ran" and "Unknown reason" rows.

**Decided in-stage.**
1. **The `CheckRun` write is a trigger, not an edit of `Process.Record`.** Epic 39 replaced exactly that block. The trigger runs in the same statement as the update, and `Checks.Coverage` does the INSERT. The reason is mapped from the release-1 phrase through the `REASON*` parameters. Leftover `CheckRun` rows from other tests' fixture updates are harmless; the purge removes them.
2. **A production watch is AD-18's history plus a live read at build time.** The AC lists items in error, disabled items, failures since the last digest and backlog for each production; release-1 runs check neither disabled items nor queues. The failure-scoping loop (4 lines) is copied from `Process.Run`, because that file is contended.
3. **Any heartbeat gap is `paused`**, as AD-18 says.
4. **Thresholds have one Lane A copy** (`Coverage.THRESHOLDS`). `Thresholds` tests that it equals Lane B's XData defaults.
5. **`Install.Seeds` is generic.** `Web.SeedSettings` stays as it is: Rule 2, a new caller with a reason.
6. **A database's maximum is read with `GetDatabaseInfo^%SYS.DATABASE`.** It is the one measured read that needs no privilege and no switch. It is not a documented API, so `Test.Watch.Vitals` pins it on a real capped database.
7. **A database's name is its directory's last folder, upper case.** No privilege-free API gives the configured name.
8. **Database and volume metadata are not namespace reads,** so a watched namespace's databases are read without `Readable`. Its production read keeps `Readable`.

**For the lead.**
- The proposed text above goes to the Planner before the code is committed.
- Decided in-stage item 6 relies on an internal IRIS routine label; a later build that drops it turns `database space` into `not_checked` `Couldn't be read` (rule 2), never `passed`.

**Needs the orchestrator:** none. The plan builds without any contended edit.
- Not touched: `Checks/Process.cls`, `Test/Checks/**`, `ci/units.sh`, `src/short-names.tsv`, `Test/Data/*`, `docs/security-overview.md` (contended with Epics 39 and 40), `Test/Install/SecurityOverview.cls` (changed by Epic 40).
- If any Lane B test asserts that threshold rows are absent, stop with Clarification Needed (U-177).
- If a contended test (`Test.Data.Tables`, `Test.Checks.*`) goes red because of the `BackgroundCheck` trigger or the new `Order()` entry, stop with Clarification Needed. Never edit it.

**Story 30.7 check.** No planned file is one that 30.7 changes. `IncidentManager.Purge`, Turn, Delivery and Session, `Reconcile`, `Redact`, `KeyProof` and `list_productions` are untouched. The new purges use `Bridge.Time.DaysCutoff`, as 30.7 asks of the others.

**Footprint extensions (Rule 11; none contended):** `Data/BackgroundCheck.cls`, `Install/Registry.cls`, `Install/Seeds.cls`, `Test/Install/{Registry,Retention}.cls`, `Test/Watch/Vitals.cls`, `docker/tests/lib-live.sh`.

**Extend, don't copy (Rule 2):**
- `Failures` and `Current` are extended.
- The purges follow `Item.Purge`.
- The probe follows `Test.Checks.Probe`.
- Copies, with their reasons: the scoping loop (item 2) and `Install.Seeds` (item 5).

**Integration ACs (Rule 1):** `Checks.Process`, then `CheckRun`, then `Build` (the fourth AC). The first outside consumer is Story 17.6.

**Consumes:**
- 33.1: `CheckRun`, `Sent`, the keys, the slot types.
- 33.2: `checks.thresholds.*` and `SettingsOps`.
- 8.1: `Heartbeat.Gaps`.
- `Data.Ownership.Checks`.

**Consumed-by:**
- 17.6: `Build` rows, lines and `vitals`, plus the seeds step (`digest.time` and `digest.channels`).
- 17.7: `Render` over the rows; `digest.healthy` and `vitalsNotAll` from `vitals`.
- 18.4: the web digest card's rows.

## Verification

Every `ci/*.sh` call carries:
- `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a"`
- `OCUTALON_TEST_WEB_PORT=52801`
- `OCUTALON_LOCK_OWNER='epic=17 stage=<stage>'`

Run one command per call, in the foreground, with `timeout: 600000`. Tags are `e17s5iw` (warm) and `e17s5i` (fresh); QA and code review use their own. Run `ci/warm.sh down` at the end, also after a failure. On `ocutalon-slot-a` use `iris_doc_load` only, with `server` and `namespace` on every call; nothing destructive runs there (`Test.Watch.Vitals` creates and deletes a database, so it runs only on throwaways).

**Commands:**
- (once) `OCUTALON_RUN_TAG=e17s5iw ci/warm.sh up`: a ready stack.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s5iw ci/iris.sh class <C>`, one per call. Expect `CLASS <C> passed` for each of:
  - `OcuTalon.Test.Digest.Coverage`, `.Runs`, `.Thresholds`, `.Purge`, `.Contracts`, `.Store`
  - `OcuTalon.Test.Watch.Vitals`, `OcuTalon.Test.Watch.Reader`
  - `OcuTalon.Test.Checks.Runs`
  - `OcuTalon.Test.Install.Registry`
- (once) `bash docker/tests/test-security-overview.sh` (passes with `docs/security-overview.md` unchanged), then `test-lib-live.sh`, `test-storage.sh`, `test-class-rules.sh`, `test-boundaries.sh` and `test-ci-config.sh`, one per call: each passes.
- (once) Fresh, `OCUTALON_RUN_TAG=e17s5i`, one per call:
  - `ci/iris.sh live install-start`, then `live install-upgrade`;
  - `ci/iris.sh class OcuTalon.Test.Install.Retention`, then `class OcuTalon.Test.Install.SecurityOverview`;
  - `shard lane-a@Checks,Install,Watch` and `shard lane-a@rest`, adding `--part k/n` to keep each call under about 8 minutes;
  - `ci/iris.sh teardown`.

**Shared surfaces:**
- `Registry.Order()`: `Test.Install.Registry` and `lib-live.sh` `expected_run` (the install, upgrade and audit scripts' step logs);
- the `Data.Setting` threshold rows (Lane B's settings tests);
- the `CheckRun` rows;
- `Reader.Failures`' signature.

Every test added or changed passes on a fresh environment, in either order.

**Planned mutations (Rule 19), one per AC:**
- `Build` drops the journal row → `Coverage` `TestEntries` red.
- `Digest.Run` seeds nothing → `Thresholds` `TestSeeded` red; `Coverage` reads `THRESHOLDS` instead of `Get` → `TestAdminValue` red.
- The trigger is removed → `Runs` `TestProcessRunRecorded` red; the `timeout` map becomes `error` → `TestReasonMap` red.
- The size-limit rule is dropped (a capped database judged by its volume share) → `Coverage` `TestCappedDatabase` red; `Reader.Database` ignores piece 6 → `Vitals` `TestCappedDatabase` red; a `Grants()` returning `%Admin_Operate:U` is added to `Digest` → `Thresholds` `TestNoGrant` and `test-security-overview.sh` red.
- `CheckRun.Purge` is not called → `Retention` `TestOcuTalonPurge` and `Purge` red.
- The paused rule is dropped → `Coverage` `TestPaused` red.
- The queue comparison is flipped → `TestBacklog` red.
- No rounding → `TestFigures` red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
