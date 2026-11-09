---
title: 'Story 17.13: The system-log vital sign is not a false alarm after a restart'
type: 'bugfix'
created: '2026-11-08'
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

**Problem:** On the v1.0.4 demo host the digest said "Failed: system log (6 errors, at 16:24 ET)" (DW-980, D4, HIGH for 1.0.5 by the Contest Planner's ruling under the owner's delegation). The severity 2 lines of `messages.log` were only IRIS's own start-up noise. Task 0 (below) measured it on fresh Docker installs of builds 154 and 109. Every start logs `<METHOD DOES NOT EXIST>Sharding+2^STU` at severity 2. A start in a new container (a recreate, as a Docker user's `docker compose up` after an image or container change does) also logs "System appears to have failed over from node <old container id>". `OcuTalon.Watch.Reader`'s severe-line count counts both, so every recreate adds 2 to the count and fails the "system log" entry of `OcuTalon.Checks.Coverage`.

**Approach (recommended option (a); pending the Planner's ruling):** The reader leaves out a severe line only when it is one of the two start-up signatures that Task 0 measured, exactly, at severity 2. Every other line of severity 2 or 3 still counts, inside or outside a start, so a real later error still fails the entry with its count and time. Nothing else changes: the window, the switched files, the error outcome, the never-kept text and the Coverage row. No string changes.

## Boundaries & Constraints

**Always:**
- A line is start-up noise only when its severity is `2` and the text after the severity matches one signature exactly:
  - `[Utility.Event] Error: ERROR #5002: ObjectScript error: <METHOD DOES NOT EXIST>Sharding+2^STU *Sharding,SYS.ICM` (whole text, nothing before or after);
  - `[Utility.Event] System appears to have failed over from node ` followed by one non-empty host name with no space, and nothing after it.
- Every other line of severity 2 or 3 counts as it does today: a near miss (extra words, another routine or label, another error number) and a signature text at severity 3 all count.
- The noise check runs after the window checks and changes neither the file's `first` time nor the order or stop rule of the file reads. The signatures apply in every file read (`messages.log` and `messages.old_*`).
- The text of a line is still never kept or returned: only the count leaves `Vitals` (the class rule). The read stays a file read in the manager directory, with no privileged API and no namespace switch (AD-3).
- Every test writes and deletes its own kept-log files in the manager directory (`messages.old_zzvitals17_*`, `DropSwitchedLogs`) and passes on a fresh stack, in either order.

**Never:**
- No skip by time, by process id, by a start-sequence marker, or of a whole start (that is option (b); see Design Notes).
- No edit to `Checks/Coverage.cls`, its findings, the `digest.*` catalog keys or `docs/`. If a string change turns out to be needed, HALT with `intent gap` and a condition that begins `PUBLIC TEXT:` with the exact text and file:line.
- No edit to the `Productions`/`state` part of `Watch/Reader.cls` (Epic 30), to `Core/**`, `Agent/{Input,Triage}.cls`, `Channel/SimPhone/**`, `Data.Handled`, `Delivery.CheckRows`, `Web/Api.cls`, `Install/Step/*.cls`, `Data/Purge.cls` or `release/*.sh` (contended).
- No live restart in a test. Fixtures are kept-log files that the test writes.
- No real model key, no real Telegram bot, never the demo host or a dev slot for a destructive step.

## I/O & Edge-Case Matrix

All rows except the last read a kept file `messages.old_zzvitals17_<n>` that the test writes at times before `b` (two days before the current `messages.log`'s first timed line, as `TestSwitchedLog` does), over the window [b-3600, b-60], so the current file contributes nothing.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Start-up noise alone (pin, DW-980) | One recreate's lines as Task 0 measured them: `Instance 'IRIS' starting on node zzhostnew ...` (0), the failover line from node `zzhostold` (2), `Enabling logons` (0), `Interoperability System Startup Complete` (0), the Sharding line (2) | `Vitals("", from, to).systemLog` = {"outcome": "read", "count": 0} | none |
| Two recreates | The same five lines twice, 600 s apart | count 0 | none |
| Real later error (pin) | The noise lines, then a later `[Utility.Event] Error: ERROR #5002: ObjectScript error: <UNDEFINED>zzvitals+1^ZZVITALS17 *zz` (2), a `[Generic.Event]` line (3), a near-miss failover line `... from node zzhostold to zzhostnew` (2) and the Sharding text at severity 3 | count 4: the four non-noise lines | none |
| Coverage row, noise only (Integration) | A fixture session that watches nothing; `Checks.Coverage.Build(session, from, to, ...)` over the real reader and the noise-only file | The "system log" row (rows[4]) is `passed` with no finding; lines[4] is `digest.passed` | Build's sc is OK |
| Coverage row, real later error (Integration) | The same, over the real-later-error file | rows[4] is `failed` with finding "4 errors" and a `checkedAt` of the Build time; lines[4] is `digest.failed` with slots finding "4 errors" and time = rows[4].checkedAt | Build's sc is OK |
| Real start of this stack (Rule 3) | The real `messages.log` of the throwaway: the window from the last `Instance 'IRIS' starting on node` line to 1 s after the next Sharding line | count 0 (before the fix: 1). The test asserts that both lines are found | none |

</intent-contract>

## Code Map

**The fix:**
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls`
  - Class doc, the Vitals bullet :37-40 ("the count of the severe lines ..."), and the `Vitals` doc's systemLog bullet :234. Extend both: start-up noise is left out (the two signatures).
  - Parameters `MESSAGESLOG` :71, `SWITCHEDLOGS` :74, `LINEMAX` :78. Add the two signature parameters beside them.
  - `SevereLines` :359-397: the file order and the stop rule. Its doc :359-361 ends with "The text of a line is never kept." Keep it, and add the noise rule.
  - `SevereLinesIn` :399-422: the severity :411, the `first` time :412-415, the window :417-418, the count `Set count = count + 1` :419. The noise skip goes between :418 and :419.
- `src/ocutalon/cls/OcuTalon/Checks/Coverage.cls` (read only): `Build` :128, `Vitals` :145 through the seam :444-446; `VitalRows` :201-234, the system-log row :225-230; `FINDINGERROR`/`FINDINGERRORS` :61-63 ("1 error", "{count} errors"); `AddChecked` :188-193 sets the slot `time` to the row's `checkedAt`. The "at 16:24 ET" of D4 is this `checkedAt`, the time of the check.

**Tests to extend (Rule 2):**
- `src/ocutalon/cls/OcuTalon/Test/Watch/Vitals.cls` runs in throwaway stacks and CI only (`Test.Watch.Case`, `Ready()`).
  - Header :1-19.
  - `TestSwitchedLog` :177-202 is the window pattern: `FirstTimeOfCurrent` :219, `b = c - 2 days`, the window [b-3600, b-60].
  - `WriteKept(name, base, lines)` :232-242 writes `(1) <severity> [Zz.Event] a line of a kept log, ignore` :239. Extend it with an optional third element, the text after the severity.
  - `DropSwitchedLogs` :244, called in `OnBeforeOneTest`/`OnAfterOneTest`/`OnAfterAllTests` :34-62.
  - `TestBuildOnRealSeams` :299-322 is the Build pattern, with `Fixture.Session` and `DropBuildFixtures` :325.
  - `TestNoSwitch` :333-346 lists the reader's vital-sign methods :338. Add any new private method there.
- `src/ocutalon/cls/OcuTalon/Test/Digest/Coverage.cls` :146-151 and `CoverageProbe.cls` :52 feed fixture vitals through the seam. They are unaffected, because the reader's output shape is unchanged.

**Read-only evidence:**
- `docker/tests/lib-live.sh` :307 `merge_errors` reads the same severity rule (2, 3 or `ERROR #`) for the merge check. It is unchanged.
- PRD addendum §1 "Harmless startup noise" names `Sharding+2^STU` (and `GetCacheDirs`, which is severity 1 and never counted).

## Tasks & Acceptance

**Execution (after the Planner's ruling; for (b) see the Alternative):**
- [ ] `src/ocutalon/cls/OcuTalon/Watch/Reader.cls`:
  - Add `Parameter NOISESHARDING` (the whole Sharding text) and `Parameter NOISEFAILOVER` (the failover prefix, with its closing space), each with a doc line: IRIS's own start-up lines of builds 154 and 109, Story 17.13's Task 0.
  - Add a private `StartNoise(line) As %Boolean`. It is 1 only when the severity piece is `2` and `$Piece(line, " ", 4, *)` equals `NOISESHARDING`, or begins with `NOISEFAILOVER` with a non-empty rest that holds no space.
  - In `SevereLinesIn`, after the window checks :417-418, `If ..StartNoise(line) Continue`.
  - Update the docs (class :37-40, Vitals :234, SevereLines :359-361). ASCII only; comments state the contract (Rule 14) -- DW-980.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Watch/Vitals.cls`:
  - `WriteKept` takes an optional third list element, the text after the severity (default: today's text, so every existing call is unchanged).
  - Add the tests, one per matrix row, and list them in the header: `TestStartNoise` (rows 1-2), `TestLaterRealError`, `TestStartNoiseRow` (both Coverage rows, with a `Fixture.Session` dropped by `DropBuildFixtures`) and `TestRealStartNoise`.
  - Add `StartNoise` to `TestNoSwitch`'s list :338.
  - Every existing test stays unchanged and green -- DW-980.
- [ ] Mutations (Rule 19), one per call on the warm stack: observe red, restore byte for byte (`cmp` against a backup in `<scratchpad>/e17s13impl/`), and see the class green again. Record each one under Verification:
  - (pinning, noise) Delete the `StartNoise` skip. `TestStartNoise` (count 2/4), `TestStartNoiseRow` (row failed) and `TestRealStartNoise` (count 1) go red.
  - (over-breadth) Make `StartNoise` return `$Piece(line, " ", 3) = 2 && ($Piece(line, " ", 4) = "[Utility.Event]")`. `TestLaterRealError` goes red (the later error and the near miss are lost: count 2), and so does the failed row in `TestStartNoiseRow`.
  - (prefix) Drop the "no space after the host" rule. `TestLaterRealError` goes red (count 3).

**Acceptance Criteria:**
- Given an instance whose `messages.log` in the window holds only the measured start-up lines of one or more starts or recreates, when the digest's coverage is built, then the "system log" entry passes (FR-36, AD-28). The pin goes red under the pinning mutation.
- Given a real error of severity 2 or 3 logged after a start (any text other than the two exact signatures at severity 2), when the coverage is built, then the entry fails with its count ("1 error" / "{count} errors") and the check time, as Story 17.5 left it. The pin goes red under the over-breadth mutation (Rule 19).
- Given the change, when it merges, then no user-facing string, catalog entry or `docs/` text changes (`git diff` touches no `Msg/Catalog/*`, no `Checks/Coverage.cls` and no `docs/`), and `Vitals`'s systemLog keeps the members `count,outcome` only (`TestFiveSigns`).

## Spec Change Log

## Review Triage Log

## Task 0 findings

These were measured on 2026-11-09 between 00:23 and 00:33 UTC (the throwaways' clock; the instance zone was UTC). Each build ran on its own throwaway in lane B: tag `e17s13t154` for build 154 (`ocutalon-iris-base:2026.3.0AI.154.0`, banner `2026.3.0AI (Build 154U)`), then tag `e17s13t109` for build 109 (the base image chosen with `IRIS_IMAGE=<the build 109 image name>`, the compose build argument that the 1.0.0 rc4 run used, banner `2027.1.0AI (Build 109U)`). Each stack started through `ci/warm.sh up`, the judges' compose file plus the throwaway and CI overrides: a full first start, with the after-start installer, to `ready 1.0.4`. Then three restarts, each waited to healthy and `AFTER-START end ... ready`:
- (R) an in-place `docker compose restart iris`, the same container;
- (C) a recreate, `up -d --no-build --force-recreate --no-deps iris` with the durable volume kept;
- on 109 only, (K) a `docker compose kill iris` followed by `start`, a crash restart.

Both stacks were torn down (`ci/warm.sh down`, 0 leftovers), the base images were untouched, and nothing was pulled. Host names and container ids are redacted. `messages.log` is `/durable/iris/mgr/messages.log`. It also holds the image's own build-time starts (dated 09/24/26 on 154 and 10/30/26 on 109), which a window of the last 24 h never reaches.

**Severity 2 and 3 lines after start-up was over (verbatim; the same text on both builds):**

| Build | Start | Lines at severity 2 or 3 of that start |
|---|---|---|
| 154 | first | `11/09/26-00:24:28:967 (2511) 2 [Utility.Event] Error: ERROR #5002: ObjectScript error: <METHOD DOES NOT EXIST>Sharding+2^STU *Sharding,SYS.ICM` and, 63 s later, during the installer's OCUORDERS step, `11/09/26-00:25:32:130 (3367) 2 [Generic.Event] License limit exceeded 1 times since instance start.` |
| 154 | R | `11/09/26-00:26:46:128 (1299) 2 [Utility.Event] Error: ERROR #5002: ObjectScript error: <METHOD DOES NOT EXIST>Sharding+2^STU *Sharding,SYS.ICM` |
| 154 | C | `11/09/26-00:27:13:042 (1715) 2 [Utility.Event] System appears to have failed over from node <container id>` and `11/09/26-00:27:14:347 (1715) 2 [Utility.Event] Error: ERROR #5002: ObjectScript error: <METHOD DOES NOT EXIST>Sharding+2^STU *Sharding,SYS.ICM` |
| 109 | first | `11/09/26-00:29:16:890 (2511) 2 [Utility.Event] Error: ERROR #5002: ObjectScript error: <METHOD DOES NOT EXIST>Sharding+2^STU *Sharding,SYS.ICM` (no licence line) |
| 109 | R | `11/09/26-00:30:53:318 (1299) 2 [Utility.Event] Error: ERROR #5002: ObjectScript error: <METHOD DOES NOT EXIST>Sharding+2^STU *Sharding,SYS.ICM` |
| 109 | C | `11/09/26-00:31:16:861 (1715) 2 [Utility.Event] System appears to have failed over from node <container id>` and `11/09/26-00:31:18:196 (1715) 2 [Utility.Event] Error: ERROR #5002: ObjectScript error: <METHOD DOES NOT EXIST>Sharding+2^STU *Sharding,SYS.ICM` |
| 109 | K | `11/09/26-00:32:06:644 (1302) 2 [Utility.Event] Error: ERROR #5002: ObjectScript error: <METHOD DOES NOT EXIST>Sharding+2^STU *Sharding,SYS.ICM` only. The crash's journal recovery logs at severity 0 and 1 (for example `1 [Utility.Event] Configuration file /durable/iris/iris.cpf is not the same as when last shut down`, `1 [Utility.Event] [JOURNAL RESTORE] Not restoring ... because the database is not journaled`) |

No severity 3 line appeared in any start. The failover line names the previous container's id, its host name, and appears only when the container changes (C), never on an in-place restart (R or K).

**Where the start sequence ends.** In every start, every line of the start sequence is written by one process, the start process (pid 2511, 1299, 1715 or 1302 above):
- It begins with `<ts> (<pid>) 0 [Utility.Event] Instance 'IRIS' starting on node <host> by user 'irisowner' on <date> UTC`, which follows the multi-line `Startup of InterSystems IRIS [...]` banner.
- The failover line comes about 0.16 s after that line, before `Activating namespaces`, and about 1.2 s before `Enabling logons`.
- Then come `<ts> (<pid>) 0 [Utility.Event] Enabling logons` and `<ts> (<pid>) 0 [Utility.Event] Interoperability System Startup Complete`.
- The Sharding line comes 0 to 2 ms after "Interoperability System Startup Complete" (100 to 330 ms after "Enabling logons"). It is the start process's last line. No line marks the end of the start after it, and the next line comes from the installer's merge (another pid, about 30 ms later).

So both noise lines fall inside the start process's lines. The failover line falls before both candidate end markers, and the Sharding line falls after both.

**`OcuTalon.Watch.Reader`'s system-log count** (`Vitals("", from, "").systemLog`, run in the container):

| Build | After | Window from just before that start | Last 24 h |
|---|---|---|---|
| 154 | first start | 2 (Sharding, licence) | 2 |
| 154 | R | 1 (Sharding) | 3 |
| 154 | C | 2 (failover, Sharding) | 5 |
| 109 | first start | 1 (Sharding) | 1 |
| 109 | R | 1 | 2 |
| 109 | C | 2 | 4 |
| 109 | K | 1 | not read |

The demo host's "6 errors" fits about three container changes in one window (inference).

**Evaluation of the two candidate fixes:**
- **(a) ignore the exact start-up signatures.** This is the narrowest fix, and it leaves a real later error failing.
  - It drops exactly the two measured lines and nothing else, inside or outside a start.
  - A later real error that matches a signature exactly would be dropped. `Sharding+2^STU` is a label of the start routine `^STU`, and the failover line names a node change detected at start, so a later exact match is not realistic (inference: every observed instance was the start process's line).
  - A crash-restart loop: the measured kill-restart logs nothing at severity 2 or 3 except the Sharding line, so (a) and (b) see the same thing there. Any other severe line that a failing start logs (a database that cannot mount, a journal restore error; inference) still counts under (a).
  - Log switching: the check is per line, so it works the same in `messages.old_*` with no state across files.
  - Builds: the text is identical on 154 and 109. If a later build changes it, the line counts again, a false alarm, never a false all-clear (AD-28).
  - Privileges: the read stays the same file read (AD-3).
  - "The text of a line is never kept": the line is compared in memory, as the severity already is, and only the count leaves.
- **(b) count only errors logged after the start sequence ends.**
  - The log has no end marker after the Sharding line. With either end marker ("Enabling logons" or "Interoperability System Startup Complete"), (b) still counts the Sharding line, so it would not fix D4.
  - A (b) that works must skip by process id (every line of the start process) or by a grace period after the marker. Either one drops every severe line of a start, real start failures included, a wider rule with a false all-clear risk (AD-28).
  - It needs state across lines and across files, because the reader reads the current file first and older files after it, and a start can be split by a switch.
  - A crash loop hides every start's own errors.
- **Recommendation: (a).**
- **Also seen, for the Planner (no change planned).** On build 154's first start, `License limit exceeded 1 times since instance start.` (severity 2, `[Generic.Event]`) during the installer's OCUORDERS step. It is not start-up noise: it comes from another process 63 s after the start sequence. It is a licence event of the instance, and build 109's first start did not show it. Neither option leaves it out, so a first digest within 24 h of a fresh 154 install can say "Failed: system log (1 error)". It is kept counted, because hiding a licence event would be a false all-clear risk.

## Design Notes

**Pending Planner ruling: (a) or (b); the lead holds implement until it arrives.**

**Recommended option (a), and why it is the narrowest:** see Task 0 findings, "Evaluation".
- It removes exactly the two lines that Task 0 measured on both builds, at severity 2, and nothing else, so every other severe line, before, during or after a start, still fails the entry.
- Option (b) cannot remove the Sharding line with any marker the log has, because that line comes after both end markers. A working (b) drops whole starts.

### Alternative (if the Planner rules the other option)

Option (b) replaces the signature check with a start-sequence rule in `SevereLines`/`SevereLinesIn`. A severe line is skipped when it comes from the pid of the latest `Instance 'IRIS' starting on node` line of its start, from that line until the next line of a different start. "Enabling logons" cannot be the end, because the Sharding line comes after it (Task 0).

What changes:
- The reader keeps the start pid as state while it reads a file, and across a file boundary, which is hard because the files are read newest first.
- The matrix gains rows for two starts in one window, a start split across `messages.old_*` and the current file, a real severe line of the start process (now skipped: Never/AC wording would change from "a real error at any time counts" to "a real error after the start counts"), and pid reuse.
- The pinning mutation becomes "skip nothing".
- AD-28 needs a sentence in the spec accepting that a failing start's own errors are not reported by this sign.

Expected size: about 3 times the code and the tests of (a) (inference).

**Governing ADs (Rule 6):**
- AD-28: the all-clear comes only from code, and the change may not add a false all-clear. Only two exact, measured lines are dropped.
- AD-3: `Watch.Reader` is the one reader, it reads the manager directory with no namespace switch and no privileged API, and `TestNoSwitch` covers the new method.
- AD-18: the window and the zone conversion (`Data.Time.FromLocal`) are unchanged.
- AD-22: the tests run in throwaway stacks and CI, and the fixtures are files the test writes.
- AD-33: only Lane B's reader changes; `Checks.Coverage` is only read.
- No AC contradicts an AD.

**Ledger (Rule 17):** DW-980 is addressed by Task 0 (above), the reader task, the test task, the matrix and ACs 1-2.

**Integration ACs (Rule 1):** no new service, module or shared component. The two Coverage-row matrix rows are the consumer check, over the real reader.
- Consumes: the instance's `messages.log` and `messages.old_*` (IRIS).
- Consumed-by: `Checks.Coverage.Build` (Story 17.5), which feeds the digest (Stories 17.6, 17.7, 17.10) and `check_status`.

**Extend, don't copy (Rule 2):** the skip extends `SevereLinesIn`, and the tests extend `Test.Watch.Vitals`'s `WriteKept`, `TestSwitchedLog`'s window and `TestBuildOnRealSeams`'s Build pattern. No sibling is copied.

**PUBLIC TEXT:** none. The signatures are IRIS's own log text, matched and never shown; the findings and keys are unchanged.

**Decided in-stage:**
1. The signatures are two `Parameter`s of `Watch.Reader`, word for word from Task 0, and severity 2 is part of each.
2. For the failover line, the host name is one token with nothing after it, so a longer line counts. A host name can contain no space (inference: Docker's are 12 hex digits).
3. The check is not tied to the start process's pid. That would add state across files for a case the evidence does not show (Task 0, "Evaluation").
4. "Fails with its count and time" is the row's finding and its `checkedAt`, as Story 17.5 built it. No error-time slot is added, which would be a string change.
5. The licence line of 154's first start keeps counting (Task 0, "Also seen").
6. The tests live in `Test.Watch.Vitals`, which already writes kept-log fixtures in the manager directory. `TestRealStartNoise` reads the throwaway's own start, so CI exercises build 154's real noise.

## Verification

Every `ci/*.sh` call sets `OCUTALON_LOCK_DIR=<lock-dir>/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=17 stage=implement'`.
- Tags: `e17s13iw` (warm, the loop) and `e17s13if` (a second warm-up stack started after the last edit, for the fresh evidence).
- Run one call at a time, in the foreground, with `timeout: 600000`, sized to about 150 s. A stack start is its own call (`ci/warm.sh up` took 153 to 154 s here, so if it is moved to the background, wait in bounded foreground polls before anything else).
- Make one `iris_execute_tests` per message.
- MCP calls go only to `server` `ocutalon-slot-b`, `namespace` `OCUTALON`, after `iris_server_info` shows build 154.

**Commands:**
- (once) `iris_doc_load` of `Watch/Reader.cls` and `Test/Watch/Vitals.cls` on `ocutalon-slot-b`. Expected: both compile. The tests themselves run only in throwaways.
- (once) `OCUTALON_RUN_TAG=e17s13iw ci/warm.sh up`. Expected: `WARM up ... ready`.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s13iw ci/iris.sh class OcuTalon.Test.Watch.Vitals`. Expected: `CLASS ... passed`. The mutation runs use this command.
- (once) The same warm command for `OcuTalon.Test.Digest.Coverage`. Expected: passes unedited.
- (once) `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-class-rules.sh`, one per call. Expected: PASS (ascii, assert-concat).
- (once) `OCUTALON_RUN_TAG=e17s13iw ci/warm.sh down`, also after a failure.
- (once) Fresh evidence:
  1. `OCUTALON_RUN_TAG=e17s13if ci/warm.sh up` (a new stack built from the final tree; its first warm run prints `WARM reloaded 0`).
  2. `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s13if ci/iris.sh class OcuTalon.Test.Watch.Vitals`.
  3. The same for `OcuTalon.Test.Digest.Coverage`.
  4. `OCUTALON_RUN_TAG=e17s13if ci/warm.sh down`.

  Each step is its own call. Expected: both pass.
- (CI) The `shards` group (`shard:lane-a@Checks,Install,Watch`) runs `Test.Watch.Vitals` on a fresh stack on push.

**Shared surfaces:** the system-log count of `Watch.Reader.Vitals` and the "system log" row of a digest's coverage (and with it the all-clear). The other tests that assert them are `Test.Watch.Vitals` (`TestFiveSigns`, `TestSystemLog`, `TestSwitchedLog`, `TestUnreadableSwitchedLog`), whose lines use other texts and still count, and `Test.Digest.Coverage`, `CoverageProbe`, `OnlineDemoFacts` and `ProcessProbe`, which feed fixture vitals through the seam. None changes shape.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
