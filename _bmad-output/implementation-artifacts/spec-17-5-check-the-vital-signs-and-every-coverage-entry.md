---
title: 'Story 17.5: Check the vital signs and every coverage entry'
type: 'feature'
created: '2026-11-05'
status: 'draft'
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

Paths are under `src/ocutalon/cls/OcuTalon/`.

- `Checks/Process.cls` (read only; contended, Epic 39). Anchors:
  - `Run` :304; the scoping loop :325-329.
  - `Record` :379, with the `UPDATE` at :382.
  - `Finding` :492; the `REASON*` parameters :106-114, `FINDING*` :85-103 (reuse via `$Parameter`), `INTERVALSECONDS` 60.
  - `Read` :542, the seam.
- `Checks/Render.cls` (read only). Release 1's row normalisation: `Row` :82. It drops any field outside the four.
- `Data/BackgroundCheck.cls`. Properties `Ref`, `SessionRef`, `CreatedAt`, `LastRunAt`, `Result`, `Finding`, `LastRunHeaderId`. It has no triggers today; none exist in `src/`.
- `Digest/Data/CheckRun.cls`, `Sent.cls`: no methods. `Item.cls` `Purge` :64-75 is the sibling (`DaysCutoff` + `DELETE ... < ?`). `Test/Digest/Contracts.cls` pins their shape; keep it unchanged.
- `Watch/Reader.cls`:
  - `Readable` :162; `Failures` :179 (8 arguments, called by `Process`, `FailurePoller` and `Fix.Executor`).
  - `Current` :255, the only `New $NAMESPACE`.
  - Items in error: `$$$GetHostMonitor(host,"%Status")="Error"` (Ensemble.inc :169-180).
  - Queues: `Ens.Queue` / `Ens.MessageHeader` `Status=2` (to be measured).
- `Tools/WatchAnswers.cls`: `ENTRY` :45, `CheckResults` :202. `Data/Ownership.cls` `Checks(sessionRef, .sc)` :276.
- `Schedule/Heartbeat.cls` `Gaps(from, to)` :87 gives `[{start, end, missed}]`; it is Lane B's and pinned by `Test/Schedule/Heartbeat.cls` :266.
- `Data/Setting.cls`: `Get(key, default)` :39 (60 s cache `^||OcuTalon.Setting`), `Seed` :57. It is Lane B's; only `OcuTalon.Install.*` may call `Seed` (`Test/Core/SettingsOps.cls` ~:346).
- `Core/SettingsOps.cls` (Lane B, read only): XData `Sections` :196-201 holds the threshold defaults and bounds; `Sections()` :208.
- `Install/Registry.cls`: `Order()` :12, `Areas()` :20, `Declared` :137, `Purge` :111. `Test/Install/Registry.cls` :126 pins `Order()`.
- `Install/Step/Digest.cls`: `Purge` only. Siblings: `Install/Step/Web.cls` `SeedSettings` :103 (seeding), `Fix.cls` `Grants` :35 (grants).
- `Install/SecurityOverview.cls`: `RoleRows` :177 builds from `Grants()`. `docker/tests/test-security-overview.sh --write` regenerates `docs/security-overview.md`.
- `Msg/Catalog/Watch.cls` :323-478, the `digest.*` keys:
  - `passed` and `failed` take `{entry, finding?, time}`.
  - `notChecked{Error,Timeout,Unreachable,Stale}` take `{entry, time}`.
  - `notChecked{Missed,Paused}` take `{entry, from, to}`.
  - `healthy` takes count slots.
  - `Msg/Catalog.cls` `count` :256 rejects non-integers.
- Tests to reuse:
  - `Test/Checks/Probe.cls` (`Read` :67, `Feed` :203) and the `Test/Checks/Runs.cls` helpers `Host` :903, `Tick` :1013. Use them, don't edit them.
  - `Test/Data/Fixture.cls` `Check(...)`.
  - `Test/Digest/Store.cls` purge tests :389-453 and `NewRow` :618.
  - `Test/Watch/Case.cls`: `GrantRole`/`RevokeRole`, `TempStopItem` :1085, `SetItemEnabled` :1174; it mutates the Orders production, so throwaway only.
  - `Test/Install/Retention.cls`: `Seed` :293 (Digest :330-339), `TestOcuTalonPurge` :247, `Cleanup` :435.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (measure on warm throwaway `e17s5iw` and record under Design Notes):
  - `messages.log` timestamp zone on a stack whose TZ is not UTC;
  - `%SYS.DatabaseQuery` `FreeSpace` columns read from OCUTALON;
  - reading a host's `%Status` Error and a queue's count and oldest age inside `Current`;
  - `KeyLicenseUnits()` on the image;
  - an AFTER UPDATE trigger firing on `Process`'s SQL `UPDATE`, and a caught error inside it leaving the update applied.

  If a measurement contradicts a rule above, stop with Clarification Needed.
- [ ] `Watch/Reader.cls`:
  - add `Vitals(namespaces As %List, fromUtc, toUtc, Output vitals) As %DynamicObject` (raw figures and per-sign status; no switch);
  - give `Failures` two optional trailing outputs, `errored` (item names) and `queues` (`[{name, count, oldestAt}]`), filled inside `Current`'s one switch. Existing callers are unchanged.
- [ ] `Checks/Coverage.cls` (new):
  - `Build` as fixed above;
  - `RecordRun(ref, sessionRef, ranAt, result, finding, headerId)`, the one CheckRun writer, which catches its own errors;
  - the `THRESHOLDS`, entry and finding parameters;
  - private seams `Vitals`, `Read` and `Gaps` that wrap `Watch.Reader` and `Heartbeat.Gaps`.
- [ ] `Data/BackgroundCheck.cls`: add `Trigger RecordRun [Event=UPDATE, Foreach=row/object, Time=AFTER]`. It calls `Checks.Coverage.RecordRun` when `{LastRunAt*C}` and the new `LastRunAt` is not empty.
- [ ] `Digest/Data/CheckRun.cls`, `Digest/Data/Sent.cls`: add `Purge(daysToKeep)` on `Item.Purge`'s pattern; `Sent` keeps each session's newest row.
- [ ] `Install/Seeds.cls` (new, not a step): `Defaults(seeds As %DynamicObject) As %Status`, which calls `Data.Setting.Seed` for each key.
- [ ] `Install/Step/Digest.cls`: add `Run()` (seeds `Checks.Coverage.#THRESHOLDS` through `Install.Seeds`) and `Grants()` (`[{"role": Users.#SERVICEROLE, "resource":"%Admin_Operate", "permission":"U"}]`); `Purge` runs all three purges. `Install/Registry.cls` `Order()`: add `Digest` after `Demo`.
- [ ] `Test/Install/Registry.cls` (the `Order` pin), `Test/Install/Retention.cls` (61- and 59-day `CheckRun` and `Sent` fixtures, the asserts, `Cleanup`), and `docs/security-overview.md` (regenerated): update.
- [ ] Tests (new; no `ci/units.sh` edit):
  - `Test/Digest/CoverageProbe.cls` (seams fed from `^||CoverageProbe`);
  - `Test/Digest/Coverage.cls`: every matrix row on the probe, and the Gaps signature through the class dictionary;
  - `Test/Digest/Runs.cls`: the trigger and `Checks.Process` through `Test.Checks.Probe` to `Build` (the integration AC);
  - `Test/Digest/Thresholds.cls`: seeds, upgrade keeps, defaults equal `SettingsOps.Sections()`, an admin value used after the cache;
  - `Test/Digest/Purge.cls`;
  - `Test/Watch/Vitals.cls`: real reads and the privilege check on a throwaway; errored and queue reads on Orders.

**Acceptance Criteria:**
- Given a session with a watched production and healthy fixtures, when `Build` runs for its window, then `rows` holds the five vital rows, the watch row and no source row; `lines` matches them one to one; and `vitals.figures` are whole numbers.
- Given a fresh install and an upgrade with an admin-changed `licenseUsePercent`, when the installer runs, then the five keys exist with their defaults on the fresh install and the changed value is kept on the upgrade.
- Given an admin threshold saved through Lane B's `SettingsOps` path, when `Build` runs after the 60-second cache, then it uses the new value.
- Given the integration of a `Checks.Process` run (real `Run`/`Record` through the shadow `Test.Checks.Probe`), when the run records its result, then one `CheckRun` row with the mapped `Reason` and the `HeaderId` exists, and `Build` derives that entry's row from it.
- Given the service user without `%Admin_Operate:U`, when the vitals are read, then `database space` is `not_checked`; and the security overview's privilege table lists `%Admin_Operate` U declared by `Digest`.
- Given `CheckRun` and `Sent` rows 61 and 59 days old, when the OcuTalon purge task runs with `DaysToKeep` 60, then the 61-day rows are gone (except a session's newest `Sent`) and the 59-day rows remain (DW-646).

## Spec Change Log

- 2026-11-05 lead: re-plan for the U-290 reversal (no new privilege; capped database not_checked with a plain reason); U-291 kept; AD-28 `vitals` allowed. Status reset to draft.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):** AD-3, AD-18, AD-19, AD-24, AD-27, AD-28, AD-29 and AD-33. No AC contradicts an AD's Rule.
- AD-3: `Watch.Reader` is the one reader and switcher.
- AD-18: the coverage rules and `CheckRun`.
- AD-19: `seed` values.
- AD-24: the service user and the generated overview.
- AD-27: area purges, no setting read.
- AD-28: results only from `Checks`; the vital-sign sentence stays `Render`'s (17.7).
- AD-29/AD-33: lanes, and table owners. `CheckRun`, `BackgroundCheck` and `Sent` are Lane A's; `Data.Setting` and `StatusMark` are Lane B's, and 17.5 only reads them.

**Ledger (Rule 17).**
- DW-646 is addressed by the purge task, the Retention update and the last AC.
- DW-648 is addressed by result rules 2 and 4, the rounding rule, and the "Never ran" and "Unknown reason" rows.

**Decided in-stage.**
1. **The `CheckRun` write is a trigger, not an edit of `Process.Record`.** Epic 39 replaced exactly that block. The trigger runs in the same statement as the update ("beside the BackgroundCheck update"), and `Checks.Coverage` still does the INSERT. The reason is mapped from the release-1 phrase through the `REASON*` parameters. Leftover `CheckRun` rows from other tests' fixture updates are harmless; the purge removes them.
2. **A production watch is AD-18's history plus a live read at build time.** The spine already uses the thresholds there, and the AC lists items in error, disabled items, failures since the last digest and backlog for each production. Release-1 runs neither fail on a disabled item nor read queues. The failure-scoping loop (4 lines) is copied from `Process.Run`, because that file is contended.
3. **`Build` gains an optional sixth Output, `vitals`.** It lets 17.6 and 17.7 tell the vital rows apart and get the `digest.healthy` figures from the same read. The five-argument call is unchanged.
4. **Any heartbeat gap is `paused`**, as AD-18 says: the literal rule, and the conservative one.
5. **Thresholds have one Lane A copy** (`Coverage.THRESHOLDS`). `Thresholds` tests that it equals Lane B's XData defaults.
6. **`Install.Seeds` is generic.** `Web.SeedSettings` stays as it is: Rule 2, a new caller with a reason.

**Lead rulings at the spec gate (2026-11-05, runner A).** (a) The `%Admin_Operate:U` grant is kept (veto U-290). (c) The new texts are accepted as listed (veto U-291). (b) The optional sixth `vitals` output of `Build` is an AD-28 contract extension: it is with the orchestrator (U14) and must be settled before 17.5's implement; if it is refused, use a separate `Checks.Coverage.Vitals()` from the same read. Correction to the footprint list: `docs/security-overview.md` is CONTENDED with Epic 39, which has changed it. It is a generated file, so regenerate it, never hand-merge; at integrate-forward or merge, regenerate after the union.

**For the lead (veto window).**
- (a) Privilege: `%Admin_Operate:U` goes to `OcuTalonServiceRole`, through `Digest.Grants()`, and appears in the overview. If it is vetoed, database space falls back to the volume share alone, and capped databases are not covered.
- (b) Spine text: the optional `vitals` Output of `Build` (Rule 20, AD-18 and AD-28).
- (c) New user-facing text. These are Checks parameters, worded from AC1 and the accepted catalog lines:
  - entries: `IRIS instance`, `database space`, `journal space`, `license use`, `system log`;
  - findings: `{name} {n}% free` (each low database, joined with ", "), `{n}% free`, `{n}% in use`, `1 error` / `{count} errors`, `1 item in error` / `{count} items in error`, `1 item disabled` / `{count} items disabled`, `{count} messages queued`, `a message waiting {minutes} minutes`;
  - not-checked findings: `Background checks were paused`, `The check didn't run`, `Its last check was too long ago`.

  Release-1 phrases are reused for the state, the failures and the reasons.

**Needs the orchestrator:** none. The plan builds without any contended edit.
- Not touched: `Checks/Process.cls`, `Test/Checks/**`, `ci/units.sh`, `src/short-names.tsv`, `Test/Data/*`.
- If any Lane B test asserts that threshold rows are absent, stop with Clarification Needed (U-177).
- If a contended test (`Test.Data.Tables`, `Test.Checks.*`) goes red because of the `BackgroundCheck` trigger or the new `Order()` entry, stop with Clarification Needed. Never edit it.

**Story 30.7 check.** No planned file is one that 30.7 changes. `IncidentManager.Purge`, Turn, Delivery and Session, `Reconcile`, `Redact`, `KeyProof` and `list_productions` are untouched. The new purges use `Bridge.Time.DaysCutoff`, as 30.7 asks of the others.

**Footprint extensions (Rule 11; none contended):** `Data/BackgroundCheck.cls`, `Install/Registry.cls`, `Install/Seeds.cls`, `Test/Install/{Registry,Retention}.cls`, `Test/Watch/Vitals.cls`, `docs/security-overview.md`.

**Extend, don't copy (Rule 2):**
- `Failures` and `Current` are extended.
- The purges follow `Item.Purge`.
- `Grants` follows `Fix.Grants`.
- The probe follows `Test.Checks.Probe`.
- Copies, with their reasons: the scoping loop (item 2) and `Install.Seeds` (item 6).

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

Run one command per call, in the foreground, with `timeout: 600000`. Tags are `e17s5iw` (warm) and `e17s5i` (fresh); QA and code review use their own. Run `ci/warm.sh down` at the end, also after a failure. On `ocutalon-slot-a` use `iris_doc_load` only, with `server` and `namespace` on every call; nothing destructive runs there.

**Commands:**
- (once) `OCUTALON_RUN_TAG=e17s5iw ci/warm.sh up`: a ready stack.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s5iw ci/iris.sh class <C>`, one per call. Expect `CLASS <C> passed` for each of:
  - `OcuTalon.Test.Digest.Coverage`, `.Runs`, `.Thresholds`, `.Purge`, `.Contracts`, `.Store`
  - `OcuTalon.Test.Watch.Vitals`, `OcuTalon.Test.Watch.Reader`
  - `OcuTalon.Test.Checks.Runs`
  - `OcuTalon.Test.Install.Registry`, `.SecurityOverview`
- (once) `bash docker/tests/test-security-overview.sh`, then `test-storage.sh`, `test-class-rules.sh`, `test-boundaries.sh` and `test-ci-config.sh`, one per call: each passes.
- (once) Fresh, `OCUTALON_RUN_TAG=e17s5i`, one per call:
  - `ci/iris.sh live install-start`, then `live install-upgrade`;
  - `ci/iris.sh class OcuTalon.Test.Install.Retention`;
  - `shard lane-a@Checks,Install,Watch` and `shard lane-a@rest`, adding `--part k/n` to keep each call under about 8 minutes;
  - `ci/iris.sh teardown`.

**Shared surfaces:**
- `Registry.Order()`: `Test.Install.Registry` and the install scripts' step logs;
- the service role's grants and `docs/security-overview.md`;
- the `Data.Setting` threshold rows (Lane B's settings tests);
- the `CheckRun` rows;
- `Reader.Failures`' signature.

Every test added or changed passes on a fresh environment, in either order.

**Planned mutations (Rule 19), one per AC:**
- `Build` drops the journal row → `Coverage` `TestEntries` red.
- `Digest.Run` seeds nothing → `Thresholds` `TestSeeded` red; `Coverage` reads `THRESHOLDS` instead of `Get` → `TestAdminValue` red.
- The trigger is removed → `Runs` `TestProcessRunRecorded` red; the `timeout` map becomes `error` → `TestReasonMap` red.
- The `%Admin_Operate` check is skipped → `Vitals` `TestPrivilege` red; `Grants()` is emptied → `test-security-overview.sh` red.
- `CheckRun.Purge` is not called → `Retention` `TestOcuTalonPurge` and `Purge` red.
- The paused rule is dropped → `Coverage` `TestPaused` red.
- The queue comparison is flipped → `TestBacklog` red.
- No rounding → `TestFigures` red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
