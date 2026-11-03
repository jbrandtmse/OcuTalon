---
title: 'Story 15.3: An IPM install survives restarts and reinstalls, and every release proves it'
type: 'feature'
created: '2026-11-02'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** After Story 15.2, an IPM install gives a running OcuTalon, but no check proves that it survives an instance restart, a production restart or a reinstall with the same or the next version (FR-6, NFR-16, NFR-17, AD-5, AD-23). Story 9.1's IPM case is not checked. `src/module.xml` doesn't declare the staff-requested `SystemRequirements`, and with it IPM refuses a first run in a namespace without Interoperability (such as %SYS), which `release/ipm-install.sh` check 5 and `docs/install-ipm.md` still expect to work (U-231).

**Approach:** Extend `release/ipm-install.sh`; don't copy it.
- **Path B's stack** takes the restart checks after its own checks: a production restart alone (DW-80), then two instance restarts. It then takes a reinstall with the next version.
- **The forced-failure recovery run** (part `r`) also passes the reinstall checks of this story (U-176).
- **The Story 9.1 IPM case** runs after every full install.
- **`SystemRequirements`** is added to `src/module.xml` as the bullet gives it. Check 5's %SYS case asserts IPM's refusal with nothing left behind, and `docs/install-ipm.md`'s namespace sentences follow U-231 (first run in an Interoperability-enabled namespace such as USER, on both supported images; IPM's refusal described with what to do instead).

The release-proof criteria (part `p`, the repository mapping (U-232), the `ipmcheck` release step, the notes, the checklist row, the registry-first guide rewrite and DW-576) moved to Story 15.4 by the orchestrator's split ruling of 2026-11-03; they are not part of this story.

## Boundaries & Constraints

**Always:**
- **Throwaway stacks only.** Every install, restart, reinstall and repository install runs only in throwaway stacks of `docker/tests/lib-live.sh` (`release/ipm/Dockerfile`: no after-start script, no version file). One fresh stack at a time for lane D (AD-22, Rule 21).
- **Reuse stacks.** The restarts and the reinstall with the next version reuse path B's stack. The same-version reinstall checks reuse part `r`'s recovery run. Part `p` reuses the compose project (`dc down -v`, then `dc up`). No new compose project is added.
- **Waiters, with Lane B's code unchanged (U-177).** "Re-armed exactly once" is read from state:
  - **Reminders:** `Test.Schedule.ReminderFixture.WaitingCount` and `StartHeaders`. These are Lane B test methods; the script calls them and never edits them.
  - **Approvals:** `Bridge.Approval.LiveHold` and `Test.Bridge.Approval.HoldCount` (Lane A).
  - **Starts:** `ReconcileIn`'s Info rows (`reconcile_rows`). Each start that the `Production` step didn't make adds exactly one row.
- **The job's limits.** It stays one job, `ipm-install`, with `timeout-minutes: 35`, `OCUTALON_LIVE_DEADLINE: "1980"`, `run: bash release/ipm-install.sh` and its fork guard (CON-1, already in place at `lane-a.yml:68`). No job is renamed. The iris matrix is unchanged.
- **The package artifact.** It is never a CI artifact or cache, and it is never pushed (CON-1). The release artifact stays in the release state folder (Story 11.17).
- **The guide's output blocks** are copied from a passing run's `OUTPUT` blocks, with ANSI codes and the `Node: ... Instance:` banner removed. The guide holds no local path, key or token (`test-boundaries.sh`).

**Never:**
- Never edit a Lane B class or test (U-177). Calling `Test.Schedule.ReminderFixture` and `Test.Data.Fixture` methods is allowed.
- Never edit another open epic's contended lines. That covers:
  - `docker/tests/lib-live.sh`, `lib-online.sh` and `test-production.sh`;
  - `lane-a.yml`'s header and its `standalone-bridge` job;
  - `docs/security-overview.md`'s bridge-guide sentence, which is Epic 13's and is absent today;
  - `Test/Install/Production.cls`;
  - `ci/units.sh`, except a plain one-name append.
- Never add a unit to the `production`, `browser`, `install-fresh` or `install-upgrade` groups.
- Never run `zpm "enable -community"` in the job. It maps IPM into every namespace and reads the public registry. It is measured once, by hand, in Task 0.
- Never publish, tag or push. Never contact the registry from a test. Never add a shipped switch that fails a step.
- Never raise the job's timeout above 35 minutes (REL-4, owner-fixed value 9). Never work around the `SystemRequirements` checks.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Production alone (DW-80) | Path B installed and its checks done. Seeded from a session in OCUTALON: a session `ZzIpmDurable` with one done turn; a live reminder `RL` (`ReminderFixture.Set`, due in 180 s); a lost reminder `RX` (`Fixture.Reminder`, pending, due in one day, no waiter); a lost approval `AX` (`ApprovalRows.Save(NewRow("tool_call"),"pending",86400,,.ref)`, no hold). Then `StopProduction(30,0)` and `StartProduction("OcuTalon.Production")` from a session, with no installer run | `ReconcileIn` logs exactly one new Info row within 60 s, and still one after 15 s more. `RX` has exactly 1 waiter and one more start header, from `HeartbeatIn`. `AX` has `HoldCount` 1 and a non-empty `LiveHold`. `RL` keeps its 1 waiter and its one `ReminderOps` start | A missing or second row, or a count other than 1, is a FAIL naming the row |
| Instance restart 1 | A second lost pair (`RY`, `AY`) seeded, then `dc restart iris` | Within the deadline: `OcuTalon.Production` runs with nothing missing, `^Ens.AutoStart` is `OcuTalon.Production`, and the container has no `/opt/ocutalon/version`, so there is no after-start script. Exactly one new `ReconcileIn` Info row. `RY` and `AY` are re-armed once (1 waiter or 1 hold, and one new start for `RY`). `RL`, `RX` and `AX` are unchanged: the same `LiveHold`, 1 waiter, the same start count | FAIL names the row and its `waiting|starts|source` or `hold|count` |
| Instance restart 2 | `dc restart iris` again | The production runs again. Exactly one new `ReconcileIn` row. Every row still has exactly one waiter or hold, and every start count and hold id equals the value after restart 1, so nothing was re-armed twice and no process is duplicated | as above |
| After the restarts | - | The session and its turn are unchanged (read back by value). `RL` fires: state `fired`, `WaitingCount` 0, one `ReminderTimer`-to-`Notify` header. `Approval.Answer(AX,"reject","web","ocutalon","")` returns `done`, the row is `rejected`, and `LiveHold` is "". `RX`, `RY` and `AY` are still pending with one waiter | - |
| Reinstall, next version | Path B's stack. A scratch copy of the real folder with the patch number raised, loaded with `zpm "load <copy>"` in OCUTALON | Initialize to Activate `SUCCESS`, one `STEP OK` per step in order, no `FAILURE` or `ERROR!`. The module version is the raised one. Every item's job id differs from before (lib-live `item_jobs`), so every item restarted on the new code. No new `ReconcileIn` row, because the step made the start. The session, `RX`, `RY` and `AY` are intact with one waiter each. The configuration is unchanged | - |
| Recovery run passes 15.3's checks | Part `r`. Before the forced Audit failure, seed a session with a turn, a live reminder (due in one day) and a lost approval. After the real folder's recovery run | The 15.2 checks pass as today. The session is intact, the reminder has exactly 1 waiter, and the approval has `HoldCount` 1, re-armed once by the installer's `Reconcile` step. Every item's job differs from before the failed reinstall. Story 9.1's IPM case holds | - |
| Story 9.1's IPM case | After the second run (path A), the recovery run, path B's second run and the reinstall with the next version | The default setting `OcuTalon.Production||EvalIn||*||Enabled` is 0. `CreateBusinessService("EvalIn")` fails with a text containing `is disabled`. `Ens.Config.Production.%OpenId("OcuTalon.Production").TestingEnabled` is 0. EvalIn has no job | - |
| First run in %SYS refused (U-231) | Check 5: a fresh instance, IPM 0.10.10 in %SYS; the first command run in %SYS against the real folder with `SystemRequirements` declared | IPM prints `ERROR! This module requires an interoperability-enabled namespace. %SYS is not interoperability-enabled.` and no phase runs. Nothing is left behind: no OCUTALON namespace, none of its four databases, no OCUTALON mapping, no OcuTalon global in %SYS, no `ocutalon` module record | Any residue, or a missing refusal line, is a FAIL naming it |
| First run in USER (U-231) | The same instance; the first command in USER | The stop line, as in Story 15.1 (USER is Interoperability-enabled on both build 154 images) | - |

</intent-contract>

## Code Map

Anchors were taken at `12fe53a1`; no source file changed since the first plan.

- `release/ipm-install.sh` (Epic 15; the only script this story extends):
  - :1-66 the header and check list (check 5 is :20-22; the mode paragraph :63-64). Checks 19-25 and check 5's new text go here; the modes stay `all|a|r|b` (:71-79).
  - :101 `run`; :121 `snapshot`; :137 `residue`; :171 `check_no_residue <label> [ns...]`; :188 `take_snapshot`; :205 `stops_with_next_command`; :221 `chk`.
  - :276-281 `reconcile_rows`, `reconcile_rows_above`.
  - :310-345 `check_second_run [<run> <label>]`. Its first half (phases, STEP order, production running, autostart, module) is generic; its second half compares with path A's references (`same_services base`, `same_config first`, `PasswordValidationRoutine` empty), which do not hold on path B (foreign routine `ZzOther^ZzForeign`, base `base-b`).
  - :507-520 `check_start_outside`: stop and start from a session, one new row within 60 s, none after 15 s more. The DW-80 row and both restarts reuse its counting.
  - :553 `scratch_copy`; :560 `module_version`; :571 `same_config`.
  - :636-657 `check_recovery` (check 17); :695-741 `reinstall_failures` (`REAL_VERSION` and `RAISED_VERSION` at :697-698, the version `sed` at :725-726, the forced failure run at :716, the recovery run at :719).
  - :749-766 the stack (`live_web_port` before `dc up`).
  - :770-785 the precondition and `take_snapshot base`; :787 `run first-user`; :823-832 the repeat in USER; :834-843 `run again-sys %SYS` (today it expects the stop line: replaced by U-231's refusal case, moved before :787); :845 the Shell() case.
  - :862-874 path A's second run per mode; :876-884 the `a`/`r` exit; :887-985 path B; :950 `run second-merge`; :979 `same_services "path B second run"`, after which the durability checks go.
- `docker/tests/lib-live.sh` (read only, contended): :244 `dc`; :287 `wait_until`; :315 `iris_script`; :460 `compare_chk`; :485 `check_session`; :493 `session_value`; :622 `item_jobs <file> [ns]` (Alive jobs per item, `name<TAB>jobs`).
- Restart patterns (read only):
  - `docker/tests/test-reminder-restart.sh` (Lane B): :20-26 (a clean restart keeps a live waiter; Reconcile re-arms only a lost one; a waiter that is waking when Reconcile runs can look lost, so that script never asserts the start headers of a due reminder); :56-63 `rem_state`; :93-138 `fired_lines` (the `ReminderTimer`-to-`Notify` header query).
  - `release/upgrade-harness.sh:605-610` the one-line probes `reminder_waiting`, `approval_hold`; :1346-1424 `phase_restart` (`dc restart iris`).
  - `docker/tests/test-production-restart.sh:50-66` `check_eval` (EvalIn's default row and the `is disabled` refusal).
- Fixtures, installed with the package (`module.xml` loads `OcuTalon.PKG`), called only:
  - `Test/Data/Fixture.cls`: :22 `Session(user)`, :35 `Turn(sessionRef,...)`, :53 `Reminder(sessionRef,dueAt,state,fields)` (a row with no waiter);
  - `Test/Schedule/ReminderFixture.cls` (Lane B): :65 `Set(sessionRef,text,seconds)` (a live waiter), :197 `WaitingCount`, :209 `StartHeaders`, :221 `WaitEnded(ref,seconds)`;
  - `Test/Bridge/ApprovalRows.cls`: :12 `NewRow(kind)`, :37 `Save(row,state,expiresIn,answerer,.ref)` (no hold);
  - `Test/Bridge/Approval.cls:2294` `HoldCount(ref)`.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` (read only): :277 `Answer(ref,action,channel,irisUser,sessionRef)` (use `reject`; `approve` replays the tool call); :752 `LiveHold(ref)`; :779-814 `Reconcile`.
- `src/ocutalon/cls/OcuTalon/Schedule/Reminder.cls:217-247` `Reconcile` (Lane B, read only; re-arms through `HeartbeatIn`).
- `src/ocutalon/cls/OcuTalon/Install/ReconcileIn.cls` (read only): :23 `LOGTEXT`; :50 `OnProcessInput`; :120 the Info row.
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls` (read only): :110 `RestartProduction` (a running production's items restart); :296-299 `EvalEnabled`; :303-306 `SetEval` (EvalIn's default row).
- `src/module.xml:4-16`: the new line goes right after `<SourcesRoot>.</SourcesRoot>` (:8).
- IPM 0.10.10 (the first plan's extracts, `%IPM.Utils.Module` about :1180-1213, `%IPM.Main:2546`): `CheckSystemRequirements` runs after the module record is opened and before `LoadDependencies` and every phase; `load` without `-dev` sets `DeveloperMode` 0, so the transaction holding the record is rolled back on the refusal (inference from source; the %SYS case measures it).
- `docs/install-ipm.md`: :7 the requirement line ("enabled for the namespace you start from"); :21 "Open an IRIS terminal in any namespace (USER here)"; :25-45 the first run's output block; :47 "Running the first command again in USER or %SYS gives the same stop and changes nothing." `test-cpf.sh` rule 9 (:264-307) pins none of these sentences.
- `.github/workflows/lane-a.yml:67-86`: job `ipm-install` (fork guard :68, `timeout-minutes: 35`, `OCUTALON_LIVE_DEADLINE: "1980"`, `run: bash release/ipm-install.sh`). Unchanged: it already runs the whole script.

## Tasks & Acceptance

**Execution:**
- [ ] `src/module.xml` -- add `<SystemRequirements Version=">=2026.3" Interoperability="enabled"/>` after `<SourcesRoot>.</SourcesRoot>`, exactly as written -- the staff-requested bullet (U-231 keeps it).
- [ ] `release/ipm-install.sh`, path A (check 5, U-231) -- after `check_no_residue "precondition"` (:785) and before `run first-user`, run the install in %SYS on the fresh instance (`run first-sys %SYS "$INSTALL"`): pass only when the final line is exactly `ERROR! This module requires an interoperability-enabled namespace. %SYS is not interoperability-enabled.`, no `Initialize START` line, the new snapshot equals `base` byte for byte (no OCUTALON, databases, resources or mappings; USER's mappings and services unchanged), and `check_no_residue` (no OcuTalon class, routine, module record or global in USER and %SYS, no role, user or web application); each failure names what it found. Delete the old %SYS repeat (:834-843). The USER first run and the USER repeat stay as they are -- matrix rows "First run in %SYS refused" and "First run in USER".
- [ ] `release/ipm-install.sh`, shared helpers (Rule 2, extend) --
  - factor `check_second_run`'s first half into `check_run_ok <run> <label>` (phases, STEP order, production running with nothing missing, autostart, module with 0 dependencies), then `check_ipm_case <label>`; `check_second_run` calls it and keeps its texts and its path-A comparisons;
  - factor `check_start_outside`'s counting into `one_new_row <before> <label>` (wait up to 60 s for `before+1`, settle 15 s, pass only on exactly one); `check_start_outside` calls it and keeps its texts;
  - `check_ipm_case <label>` (check 19): one `check_session` in OCUTALON for matrix row "Story 9.1's IPM case" (EvalIn's default row 0, `CreateBusinessService("EvalIn")` refused with `is disabled`, `TestingEnabled` 0, EvalIn has no Alive job). It runs from `check_run_ok` (path A's second run, the recovery run, the next-version reinstall) and once after path B's second run.
- [ ] `release/ipm-install.sh`, probes and seeding -- `rem_probe <ref>` (`state|waiting|starts`), `hold_probe <ref>` (`liveHold|holdCount`) and `conv_probe` (the session and turn read back by value), each a one-line `session_value` probe like `upgrade-harness.sh:605-610`; `seed_durable <tags>` writes, in one OCUTALON session, the session `ZzIpmDurable` with one done turn, `RL` (`ReminderFixture.Set`, 180 s), `RX` (`Fixture.Reminder`, pending, due in one day), `AX` (`ApprovalRows.Save(NewRow("tool_call"),"pending",86400,,.ref)`), and on request `RY`/`AY` the same way; refs go to shell variables and print as `SEED` lines.
- [ ] `release/ipm-install.sh`, path B after :979 -- in this order, each a function with `TIME` lines:
  - `check_restart_alone` (check 21, DW-80): row "Production alone": `StopProduction(30,0)` and `StartProduction` from a session, `one_new_row`, then the probes;
  - `instance_restart <n>`: `dc restart iris`, `wait_until` (within the run's deadline) the production runs with nothing missing, `TIME restart-<n>`; `check_restart <n>` (checks 22 and 23): rows "Instance restart 1" (after seeding `RY`, `AY`) and "Instance restart 2" (no action between the two restarts), each with `one_new_row`, `^Ens.AutoStart`, no `/opt/ocutalon/version` in the container, and every probe against the value recorded after the step before;
  - `check_after_restarts` (check 24): row "After the restarts": wait for `RL` with `WaitEnded`, then its state, `WaitingCount` 0 and one `ReminderTimer`-to-`Notify` header (the header query copied from `fired_lines`), `Answer(AX,"reject","web","ocutalon","")` = `done`, the row `rejected`, `LiveHold` ""; `RX`, `RY`, `AY` still pending with one waiter or hold; `conv_probe` unchanged;
  - `reinstall_next` (check 25): row "Reinstall, next version": `item_jobs` before; `scratch_copy` of `$SRC` with only `<Version>` raised (the :725-726 `sed`); `run reinstall-next OCUTALON "zpm \"load <copy>\""`; `check_run_ok reinstall-next "next version"`; the raised `module_version`; every item's jobs differ from before; `reconcile_rows` unchanged; `same_services base-b`, `same_config second-merge`; the foreign setting unchanged; `conv_probe`, `RX`, `RY`, `AY` intact with one waiter or hold.
- [ ] `release/ipm-install.sh`, part `r` (check 20) -- in `reinstall_failures`, before the forced failure: seed a session with a turn, a live reminder (`ReminderFixture.Set`, 86400 s) and a lost approval, and save `item_jobs`; in `check_recovery`, right after `check_second_run reinstall-recover`: row "Recovery run passes 15.3's checks" (session intact, reminder 1 waiter, approval `HoldCount` 1 with a `LiveHold`, every item's jobs differ from before the failed reinstall).
- [ ] `release/ipm-install.sh`, header -- check 5's new text, checks 19-25, and the mode paragraph (`b` now also runs checks 21-25). The registry host name is never named.
- [ ] `docs/install-ipm.md` -- :7 becomes "enabled for USER"; :21 says to open a terminal in USER, that OcuTalon needs an Interoperability-enabled namespace, that USER is one on both IRIS for Health and IRIS build 154, and that in a namespace without Interoperability, such as %SYS, IPM refuses the package before it changes anything, quoting its line `ERROR! This module requires an interoperability-enabled namespace. %SYS is not interoperability-enabled.`, and to run the command in USER instead; :47 keeps only "Running the first command again in USER gives the same stop and changes nothing." Nothing else changes, unless the first run's output (:25-45) differs from a passing run's `first-user` block beyond times and the banner, in which case the block is replaced with it -- U-231's guide conditions.

**Acceptance Criteria:**
- Given an IPM install (path B) holding a conversation, a pending reminder and pending approval requests, when the production restarts alone and then the instance restarts twice in a row, then the rows "Production alone", "Instance restart 1", "Instance restart 2" and "After the restarts" hold and `release/ipm-install.sh b` passes. This is the Integration AC: the consumer is the instance's autostart, and its observable effect is `ReconcileIn` re-arming each lost waiter exactly once.
- Given an IPM install holding data, when the install command runs again with the same version (part `r`'s recovery run after the forced Audit failure) or the next one (path B), then the rows "Recovery run passes 15.3's checks" and "Reinstall, next version" hold, the failed compile still rolls back with the previous version running (check 18), and `release/ipm-install.sh r` and `b` pass.
- Given a push or pull request, when the `ipm-install` job runs `bash release/ipm-install.sh` with no argument, then it runs path A, the reinstalls and path B with checks 1-25, fails unless every check passes, and the row "Story 9.1's IPM case" holds at each of its four points; `lane-a.yml` is unchanged (fork guard, `timeout-minutes: 35`), and `test-cpf.sh` rules 6 and 7 pass.
- Given `src/module.xml` with the `SystemRequirements` line, when the package loads on build 154, then the version check passes (every USER and OCUTALON run of `a`, `r`, `b` and `live install-start`), the rows "First run in %SYS refused" and "First run in USER" hold, and `docs/install-ipm.md` advises USER on both images, quotes IPM's refusal and says to run the command in USER instead, with `test-cpf.sh` rule 9 and `test-boundaries.sh` passing.

## Spec Change Log

- 2026-11-03, plan iteration 1 -> re-plan (lead, after the orchestrator's rulings on the plan's two intent gaps and its 7 h size estimate): (a) split, decide (split_children 1 of 6): this story keeps ACs 1-3 (restarts and DW-80; reinstalls with the rollback reading and the U-176 forced-failure re-run; the FR-57 job with Story 9.1's IPM case), DW-80, DW-306 and the `SystemRequirements` bullet; the release gate, the registry install, the guide and local-repository criteria and DW-576 moved to Story 15.4 (`epics.md`, marker `[SPLIT 2026-11-03 from Story 15.3, orchestrator ruling (decide)]`; DW-576 re-owned to 15.4); (b) U-231 (veto, kept with conditions by the owner's delegate, answer 2026-11-03T03:57:20Z#695): the first run's promise narrows to any Interoperability-enabled namespace; `epics.md` L265 and Story 15.1's three lines amended with `[AMENDED 2026-11-03, Story 15.3, unattended ruling U-231]`, and a U-231 bullet added to this story; the PRD states no first-run namespace (nothing to amend); the spine's AD-23 sentence "first in any namespace" is NOT amended by this story (a runner never amends an AD, U14) and is reported to the orchestrator; (c) U-232 (veto, kept with conditions, answer #696): MapAndStop also maps IPM's repository definitions into OCUTALON, in Story 15.4 (this story's tests use the load-from-folder paths, never a repository); (d) the intent block narrowed to this story, the three release-proof matrix rows moved to Design Notes ("Moved to Story 15.4"), and two U-231 rows added. The previous status was `blocked` (two intent gaps); reset to `draft` for the re-plan.

## Review Triage Log

## Design Notes

### Lead rulings (2026-11-03; supersede the intent gaps below)

1. **Split (orchestrator ruling, decide; split_children 1 of 6).** This story: ACs 1-3 (restarts and DW-80; reinstalls, the rollback reading and the U-176 forced-failure re-run; the FR-57 job and Story 9.1's IPM case) and the `SystemRequirements` bullet, plus the U-231 bullet. Story 15.4 (`15-4-every-release-proves-the-ipm-package-and-the-guide-opens-wit`): part `p`, the repository mapping (U-232), the `ipmcheck` release step (the FR-57-passed check Story 11.14 can call), the release notes, the checklist row, the registry-first guide rewrite and DW-576. Both stories ship before rc1. Re-estimate this story's size at the spec gate; over about 4 h is a new stop.
2. **U-231 (veto ruling, orchestrator; kept with conditions by the owner's delegate, answer 2026-11-03T03:57:20Z#695).** Owner's words: "Keep (a). The staff-requested Interoperability="enabled" stays, and the promise narrows to 'any Interoperability-enabled namespace'. Two conditions. (1) The guide's namespace advice must hold on both supported images, IRIS for Health and the plain IRIS build 154 image. Check that USER is Interoperability-enabled on the plain image too, or name the right namespace for each image. (2) The guide quotes, or plainly describes, IPM's refusal for a namespace without Interoperability, and says what to do instead (run the first command in USER). The %SYS test asserting the refusal with nothing left behind is good." So:
   - Keep `<SystemRequirements Version=">=2026.3" Interoperability="enabled"/>` exactly as written.
   - Check 5's %SYS case asserts IPM's refusal message with nothing left behind (no OCUTALON namespace or databases, no mappings, no globals, no module record); the USER first run still stops with the stop line.
   - **Measured by the lead (2026-11-03):** on the plain `iris-community:2026.3.0AI.154.0` image, USER is Interoperability-enabled (`%EnsembleMgr.IsEnsembleNamespace("USER")` = 1) and %SYS is not (0); on `irishealth-community:2026.3.0AI.154.0`, USER = 1 and %SYS = 0 (also HSLIB and HSCUSTOM = 1), measured the same way on a lane-D throwaway (and at plan). So USER is the right namespace on both supported images.
   - `docs/install-ipm.md`: replace its two any-namespace sentences (the requirement line near :7/:21 and the "in USER or %SYS gives the same stop" sentence at :47) so the guide says to run the first command in USER (Interoperability-enabled on both supported images), and quotes or plainly describes IPM's refusal in a namespace without Interoperability, such as %SYS, and that the fix is to run it in USER. Keep the rest of the guide; Story 15.4 rewrites it registry-first and must keep this advice.
   - The spine's AD-23 text still says "first in any namespace" (ARCHITECTURE-SPINE.md, the IPM install bullet). A stage never amends the spine; the lead reports it to the orchestrator. Implement to the narrowed promise.
3. **U-232 (veto ruling, orchestrator; kept with conditions, answer #696)** lands in Story 15.4 with MapAndStop's change: this story's tests run the load-from-folder paths only and never need the second run from a repository. Do not change MapAndStop in this story.

### Intent gaps (resolved 2026-11-03 by the lead rulings above; kept for the record)

**Intent gap 1, the `SystemRequirements` bullet.** `Interoperability="enabled"` refuses the first run in %SYS, where Story 15.1's flow runs it.
- **Measured at plan** (2026-11-02, the build 154 base image, a throwaway with no network, a test module that has only this `SystemRequirements` line):
  - `zpm "load"` in USER: all phases SUCCESS.
  - `zpm "load"` in %SYS: `ERROR! This module requires an interoperability-enabled namespace. %SYS is not interoperability-enabled.` No phase runs.
- **The source** (IPM 0.10.10):
  - `%IPM.Utils.Module:1210` calls `%IPM.Storage.Module.CheckSystemRequirements` before any phase and before `LoadDependencies`.
  - `CheckInteroperability` tests `$namespace` with `%EnsembleMgr.IsEnsembleNamespace`. That is `USER 1`, `%SYS 0` and `OCUTALON 1` on build 154. USER comes from the base image, which `docker/merge.cpf` doesn't change.
- **The conflict.** Story 15.1's criteria say "in any namespace" and "the same command runs again in any namespace other than OCUTALON".
  - `release/ipm-install.sh` check 5 runs the first command in %SYS and expects the stop line.
  - `docs/install-ipm.md:47` says that running it "in USER or %SYS gives the same stop".
  - The bullet itself says that such a refusal is a clarification and never a workaround.
- **The version half passes.**
  - `CheckVersion` compares only `GetMajor()_"."_GetMinor()`, which is "2026.3" on build 154, so the "AI" text (in `GetPoint()`, "0AI") never reaches the comparison.
  - The USER load above passed `>=2026.3`.
  - `ipm_artifact_check` greps only three module.xml strings, and `test-cpf.sh`, `test-pinned-sources.sh` and `test-build-inputs.sh` have no pin the line breaks.
- **Recommended amendment** (an ask-first narrowing of Story 15.1's done criteria, and public text):
  - Story 15.1's two criteria read "in any Interoperability-enabled namespace other than OCUTALON (USER on build 154)".
  - In a namespace without Interoperability, such as %SYS, IPM refuses the package before its first phase with its own message above, and nothing changes.
  - Check 5's %SYS case asserts that refusal and no residue.
  - The guide's :21 and :47 say "an Interoperability-enabled namespace such as USER", with the %SYS refusal in one sentence.
  - Then add the line exactly as the bullet gives it.

**Intent gap 2, the second command after an install from a repository.** The second `zpm "install ocutalon"` in OCUTALON finds no repository.
- **Measured at plan** (2026-11-02, a throwaway with no network, the real `src` of this worktree as `ocutalon-0.1.0` in a filesystem repository):
  - `zpm "repo -name ocutalon-local -fs -depth 2 -path /tmp/repo/"` and `zpm "install ocutalon"` in USER gave the stop line, as designed (25 s).
  - `zn "OCUTALON"` and the same command then gave `ERROR! No repositories are configured and enabled in this namespace.` (`repo -list`: "No repositories found.").
  - The same holds after `zpm "enable -community"` in %SYS, run before the first install. Its `-repos -globally` maps the repository globals only into the namespaces that exist when it runs, so in OCUTALON `repo -list` again gave "No repositories found."
- **The cause.** `MapAndStop` maps only the `%IPM` package and routines (`enable -map -ns OCUTALON -q`). IPM keeps repositories per namespace, in `^IPM.Repo.DefinitionD`, `S` and `I` (`%IPM.Main:3570-3601`).
- **The conflict.** The AC's "README's two commands" with "the two-step namespace message", the stop sentence's "then the same install command", and part `p`'s "`zpm "install ocutalon"` and its two steps" can't hold as built.
- **The options** give observably different outcomes:
  - (A) `MapAndStop` also maps the repository globals.
  - (B) The stop sentence or the guide adds a command between the runs, for example `zpm "enable -map -repos -ns OCUTALON"` in %SYS.
  - (C) The guide's second command adds the repository in OCUTALON again.
- **Recommended: (A).** `MapAndStop` runs `enable -map -repos -ns OCUTALON -q`, IPM's own repository mapping of `^IPM.Repo.Definition{D,S,I}` from the run namespace, under the same suspension.
  - IPM skips it when OCUTALON's `%IPM` isn't mapped from the run namespace (`%IPM.Main:3576`). If so, call `%IPM.Utils.Build.MapGlobalEquivalently` for the three globals directly.
  - Task 0 (b) measures which one works.
  - It keeps "the same install command", changes only OCUTALON's own mappings, and amends the spine's "IPM early step" row ("the IPM mapping into OCUTALON" becomes "the IPM and IPM repository mappings"). A stage may not make that spine amendment.
  - Check 3's expected mappings gain three `omap-MapGlobals|IPM.Repo.Definition?|<db>` lines. `docs/install-ipm.md` and the README order are unchanged by (A).

### Moved to Story 15.4 (for its plan; not this story's scope)

These matrix rows were planned here at iteration 1 and moved with the split. Story 15.4's plan may reuse them; gap 2's measurement and option (A) above apply to its part `p`.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Artifact (part `p`) | `OCUTALON_IPM_ARTIFACT=<.tgz>`, set by the release step. When it is unset, the module installed by path A's second run is packaged with `zpm "package ocutalon -only -path ..."` in OCUTALON and checked with lib-release's `ipm_artifact_check` | One line, `ARTIFACT ocutalon-<v>.tgz <bytes> bytes`. The artifact check finds no problem | A check problem fails the part |
| Repository install (part `p`) [held: intent gap 2] | A fresh instance (`dc down -v`, `dc up`): IPM 0.10.10 in %SYS, enabled for USER. `command -v node` in the container prints nothing. The artifact is unpacked to `/tmp/ocutalon-repo/ocutalon-<v>/` (lib-release `ipm_unpack`), then `zpm "repo -name ocutalon-local -fs -depth 2 -path /tmp/ocutalon-repo/"` in USER, then `zpm "install ocutalon"` in USER, then `zpm "install ocutalon"` in OCUTALON | The first command ends with the stop line. The second gives Initialize to Activate `SUCCESS` and one `STEP OK` per step. The production runs. `/ocutalon/` serves `Sign in to OcuTalon`, and `ocutalon`/`ocutalon` signs in | Measured at plan, today's code: the second command prints `ERROR! No repositories are configured and enabled in this namespace.` |
| Release gate | `release.sh next` at step `ipmcheck` | The step exports the candidate's tree and runs `bash release/ipm-install.sh` there, with `OCUTALON_IPM_ARTIFACT` set to the candidate's artifact. Exit 0 gives `PASS ipmcheck ...`, a `## FR-57 job` record section and `NEXT push`. Exit 75 gives `WAIT ipmcheck ...` and exit 5 | Any other exit gives `FAIL ipmcheck <first FAIL line>`, the release stops before `push`, and the record is written |

### Lead pre-rulings (both `decide`, by the orchestrator's dispatch; both now apply to Story 15.4)
1. **The registry-install AC.** This run never publishes. It delivers:
   - the guide's registry section, measured on a clean build 154 throwaway up to the point that needs the published package: `zpm "enable -community"`, its exact IPM 0.10.10 form, and its real output (Task 0 (a));
   - the after-publish checklist row `registry-install`;
   - the notes slot `### Registry install`.
   
   The author's run itself is the hand gate, not this story's CI. Planning found no test that only a published package can pass. Part `p` installs the same artifact from a local repository, but its second command depends on gap 2, which is a different question.
2. **The release-gate AC.** The candidate is pushed only at `push`, and `lane-a` doesn't run on `release/*` branches. So "the FR-57 job passed on that candidate" is delivered as `step_ipmcheck`: it runs the job's own command, `bash release/ipm-install.sh`, on the candidate's exported tree, with the candidate's artifact, before `push`.
   - Story 11.14's pushed-candidate sequence calls `step_ipmcheck` (a `step_<name>` function in `release/release.sh`, which 11.14 extends), or reads the `ipm-install` job of its full CI run.
   - `release/ipm-install.sh` already has the unit contract that `security-overview.sh` has: exit 0 pass, 75 busy (lib-live), 1 fail, 2 usage.
   - This is not a set-aside or a deferral.

The decisions taken at iteration 1 for the moved work, for Story 15.4's plan to reuse or revisit: `ipmcheck` comes after `ipm` (the exact artifact exists only then) and before `push`; part `p` packages from path A's installed module with `zpm "package ocutalon -only"` plus `ipm_artifact_check` in CI, and the release step passes the release's own artifact; the size threshold is 5,000,000 bytes; `registry-install` is an after-publish checklist row that reads `later` until the author confirms it. The intent block's words "Part `p` reuses the compose project" and "repository install" describe Story 15.4's part `p`: this story adds no part `p` and no repository install.

### Decided in-stage (re-plan)
1. **Where things run.** The restarts and the next-version reinstall run on path B's stack after its own checks, and the same-version checks on part `r`'s recovery run (iteration 1's decision 2, kept). The two instance restarts run once, on path B. No compose project, mode or job is added.
2. **"Re-armed once" uses lost waiters** (iteration 1's decision 3, kept): a clean restart keeps a live waiter (`test-reminder-restart.sh:20-26`), so the checks seed pending rows with no waiter (`RX`, `AX`, `RY`, `AY`) and assert one re-arm each and no new start on the next restart; the live ones (`RL`, and `AX` after DW-80) must stay the same process.
3. **`RL` may come due during the restarts on a slow runner.** Its 180 s due time (the matrix's input) fits the local run (the restarts end about 150 s after seeding), but on the runner the DW-80 step and two restarts take about 300-450 s (inference, x2.2-3). So each restart check asserts the matrix's "1 waiter, the same start count" for `RL` only while `RL` is not yet due (its due time from the seeding, minus 5 s); once due, it accepts either that or `fired` with `WaitingCount` 0 and exactly one `ReminderTimer`-to-`Notify` header, never two, and it does not assert the start headers of a due `RL` (the same reason `test-reminder-restart.sh:24-25` gives: a waking waiter can look lost to a Reconcile). Every other assertion of the rows is unchanged, and check 24 still requires `RL` fired exactly once. Reversible inside this story.
4. **The approval is answered with `reject`** (iteration 1's decision 4): an approve replays the fixture's tool call to Decide.
5. **Story 9.1's IPM case** exists only as criteria text (`epics.md`, spec 9.1); no disabled test was left in the code. "Turn it on" means `check_ipm_case` in the job's script (iteration 1's decision 8). It also runs at path A's second run in mode `r`, which is harmless.
6. **The %SYS case moves before the first USER run.** The matrix row needs "a fresh instance" and "no OCUTALON namespace or databases", which cannot hold after the USER run created them; the old %SYS repeat after the first run is removed with the guide's matching sentence (U-231's "the first run repeated in %SYS, and its pair").
7. **`check_second_run` is split, not copied.** Its path-A comparisons (`base`, `first`, the empty password-validation routine) are wrong on path B, so `reinstall_next` uses the generic half (`check_run_ok`) and path B's own references (`base-b`, `second-merge`, the foreign setting).
8. **`multiple-goals` is dropped from `warnings`.** The split left one goal: the IPM install's durability in the FR-57 job.

### Governing ADs (Rule 6)
- AD-2: one package, no dependency (the module stays with 0 dependencies).
- AD-3: OCUTALON's databases and mappings; the %SYS refusal leaves none behind, and check 3's expected mappings are unchanged.
- AD-5: waiters re-armed from rows; only `ApprovalHold` and `ReminderTimer` hold long timers; settings and data kept across reinstall.
- AD-16: EvalIn off on the judges' install (Story 9.1's case).
- AD-22: throwaways only, the CI mock, fork pull requests never on the runner.
- AD-23: the IPM install runs the same steps, marks autostart, reconciles every start once, and "A restart test on an IPM install proves the waiters are re-armed". Its sentence "first in any namespace" is known to the orchestrator (the lead's report); this story implements the narrowed U-231 promise and never edits the spine.
- AD-33: `ReconcileIn` is Lane A's.

No AC contradicts an AD's Rule.

### Ledger inbox (Rule 17)
- **DW-80** is addressed by check 21 and the matrix row "Production alone" (Execution: `check_restart_alone`).
- **Declined DW-306:** its bullet applies only when this story edits `docker/tests/test-production.sh`; that file is contended (Epic 12 and others) and this story never edits it, so row 21's wait is left to the next story that edits the file.
- DW-576 moved to Story 15.4 with the split (re-owned by the lead).

### Integration ACs, Consumed-by and Consumes (Rules 1 and 2)
- **Integration AC:** AC 1. The instance's autostart is the consumer; the observable effect is one `ReconcileIn` row per start and each lost waiter re-armed exactly once, read from the rows and the fixtures' probes on a real IPM install.
- **Consumed-by:** Story 15.4 (extends `release/ipm-install.sh` with part `p` and keeps the U-231 guide advice in its registry-first rewrite); Story 31.3 (the README's IPM section from the guide); Stories 19.2 and 34.1 and Epic 38's 1.0.0 checks (run on this install path).
- **Consumes:** Stories 15.1 and 15.2's harness and checks; `Test.Data.Fixture`, `Test.Schedule.ReminderFixture` (Lane B, called only), `Test.Bridge.ApprovalRows` and `HoldCount`; `ReconcileIn`; the areas' `Reconcile()` declarations; the CI model mock (not used by the new checks).

### Extend, don't copy (Rule 2)
- `check_restart_alone` and both restart checks share `one_new_row`, factored out of `check_start_outside`.
- `reinstall_next` and `check_second_run` share `check_run_ok`; `reinstall_next` reuses `scratch_copy`, `module_version`, `same_config` and lib-live's `item_jobs`.
- The %SYS case reuses `run`, `final_line`, `take_snapshot`, the snapshot diff and `check_no_residue`.
- **Copies, with their reasons:**
  - The three one-line probes follow `upgrade-harness.sh:605-610`, a script that runs when sourced.
  - The `Notify` header query copies a few lines of `test-reminder-restart.sh`'s `fired_lines`, a Lane B script's local function (U-177; `lib-live.sh` is contended).
  - `check_ipm_case` copies `test-production-restart.sh:50-66`'s refusal branch (about 8 lines), a local function of another live script that runs when sourced.

### Footprint, for the lead
Edited: `release/ipm-install.sh`, `src/module.xml`, `docs/install-ipm.md`, all Epic 15's files. Mutations touch `src/ocutalon/cls/OcuTalon/Install/ReconcileIn.cls`, `Install/Step/Production.cls` and `src/module.xml` only while applied, and are restored byte-identical. `lane-a.yml`, `ci/units.sh`, `MapAndStop`, the spine, `epics.md`, `docs/security-overview.md`, every Lane B class and test and `docker/tests/test-production.sh` are unchanged. No footprint extension.

### Size estimate (this story alone)
About 3.75 hours from implement to commit, under the lead's 4-hour stop:
- implement about 2 h: the script about 1 h; live loops of `a`, `r`, `b` (about 3, 5 and 7 min) two or three times; four mutation runs (about 18 min); the once-checks (about 10 min);
- QA and review about 1 h (each re-run mutation is a 3-7 min live call);
- smoke and CI about 0.75 h (the `ipm-install` job about 28 min).

What drives it: every pinning test is a live `ipm-install.sh` part, and `b` grows from 142 s to about 400 s. No hermetic suite changes.

### CI budget (the 35-minute job)
- **Measured:** the job ran 15.9 min of steps on `3dd30fc`. Locally on lane D: `a` 166 s, `r` 272 s, `b` 142 s.
- **Added, inference:** `a` about +5 s (the %SYS case replaces the %SYS repeat; the IPM case); `r` about +25 s (seeding, probes, item jobs, the IPM case); `b` about +260 s (seeding 10, DW-80 35, two restarts about 65 each, the remaining `RL` wait and the answer 40, the next-version reinstall 60, the IPM case 5). On the runner: the non-restart part (about 160 s) x2.2 = about 350 s, and the restarts (about 130 s) x3 = about 390 s, so about 12.3 min more: about 28 min of 35, a 7-minute margin. Part `p`'s former 120 s is gone.
- **Rule for the implement stage:** let `added` = the wall seconds of the new `a`, `r` and `b` calls minus 580 (166 + 272 + 142), and `restarts` = the sum of `b`'s `TIME restart-<n>` lines; projected minutes = 15.9 + ((`added` - `restarts`) x 2.2 + `restarts` x 3) / 60. Over 30 min: stop with `## Clarification Needed` before committing (a second fork-guarded job is a lead decision). A local `b` over 570 s also stops (it would not fit one 10-minute call with its teardown). Never raise the timeout.

### Measured at plan (2026-11-02, kept from iteration 1)
- Slot D: build 154 (`2026.3.0AI`, `GetMajor` 2026, `GetMinor` 3, `GetPoint` "0AI"); `CheckVersion` compares "2026.3", so `>=2026.3` passes (a USER load of a test module with the line: all phases SUCCESS). Slot D has no `%IPM`.
- In %SYS the same test module gave `ERROR! This module requires an interoperability-enabled namespace. %SYS is not interoperability-enabled.` and no phase.
- The base image ships `zpm 0.10.5-SNAPSHOT` in HSLIB; the script loads IPM 0.10.10 into %SYS itself (the precondition).
- The plan's throwaways (`e15s3plan-*`) were removed. This re-plan started no runtime.

## Verification

Run every command from the epic-15 worktree root (verify `git rev-parse --show-toplevel` first), in the foreground, one per call, with `timeout: 600000`. Prefix every `[L]` command with:

`OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=15 stage=implement' OCUTALON_RUN_TAG=e15s3i`

Fresh throwaways only (the `module.xml` change refuses a warm reload, and `live` is never warm). One lane-D stack at a time. End with `[L] bash ci/iris.sh teardown`, also after a failure. Never a slot for any of these.

**Commands:**
- `bash docker/tests/test-cpf.sh` (loop). Expected: every PASS, exit 0 (rules 6, 7 and 9).
- `bash docker/tests/test-pinned-sources.sh` (loop). Expected: `all checks passed`.
- `bash docker/tests/test-boundaries.sh` (loop). Expected: exit 0 (no local path, no non-ASCII byte).
- `[L] bash ci/iris.sh build` (loop; first on each pass that runs IRIS). Expected: `BUILD the web bundle is built`.
- `bash -c '. release/lib-release.sh; d=$(mktemp -d); tar -czf "$d/a.tgz" -C src module.xml ocutalon/csp; ipm_artifact_check "$d/a.tgz" 0.1.0 "$PWD"; rm -rf "$d"'` (once, after the build). Expected: no output (the artifact checks pass with the changed `module.xml`).
- `[L] bash release/ipm-install.sh a` (loop, about 170 s). Expected: `ipm-install: all checks passed`; check 5's %SYS case and check 19 PASS.
- `[L] bash release/ipm-install.sh r` (loop, about 300 s). Expected: all checks passed; check 20 PASS.
- `[L] bash release/ipm-install.sh b` (loop, about 400 s; over 570 s is a stop, see CI budget). Expected: all checks passed; checks 19 and 21-25 PASS; `TIME restart-1` and `TIME restart-2` printed.
- `bash docker/tests/test-readme.sh` (once). Expected: no failure (the guide's links and text).
- `[L] bash ci/iris.sh live install-start` (once). Expected: pass; the image's after-start loads the changed `module.xml` in OCUTALON.
- The full `release/ipm-install.sh` with no argument does not fit one 10-minute call locally (about 14 min, inference), so CI's `ipm-install` job is its first full run; record its job minutes against the projection.
- `[L] bash ci/iris.sh teardown` (once, last). Expected: a `TEARDOWN tag e15s3i` line.

**Planned mutations (Rule 19, one per AC).** Back up the file into the stage's own scratch folder, apply, run the one call, see red, restore from the backup, and confirm `git status --short` and `git diff --stat` are unchanged. Then write the `mutation:` lines here.

| AC | Mutation | Test that goes red |
|---|---|---|
| 1 restarts | `ReconcileIn.OnProcessInput` (:50) quits before its run branch | `ipm-install.sh b`, checks 21 and 22 (no new row, `RX`/`RY`/`AY` not re-armed) |
| 2 reinstalls | `Install/Step/Production.cls` :110 skips `RestartProduction` for a running production | `ipm-install.sh r`, check 20 (every item's job unchanged after the recovery run) |
| 3 FR-57 job and 9.1 | `Install/Step/Production.cls` `EvalEnabled` (:296-299) returns 1 | `ipm-install.sh a`, check 19 (row 1, EvalIn not refused) |
| 4 SystemRequirements and U-231 | the `SystemRequirements` line removed from `src/module.xml` | `ipm-install.sh a`, check 5's %SYS case (no refusal line, OCUTALON created) |

**Shared surfaces:**
- `release/ipm-install.sh`'s check list, functions and modes: lane-a's `ipm-install` job and `test-cpf.sh` rules 6 and 7 (the `run:` line and deadline are unchanged); Story 15.4 extends it.
- `src/module.xml`: `test-pinned-sources.sh`, `test-cpf.sh` rule 8, `release/lib-release.sh`'s artifact checks, `ci/warm.sh`'s manifest (a change refuses a warm reload) and every image start (`docker/after-start.cos` loads it in OCUTALON).
- `docs/install-ipm.md`: `test-cpf.sh` rule 9, `test-boundaries.sh`, `test-readme.sh`, and Story 31.3's README section.

Standing criterion: every test added or changed passes on a fresh environment, in either order (each `ipm-install.sh` part starts its own fresh stack, and its checks seed and read only their own rows).

**Manual checks:**
- The guide's first-run block (:25-45) matches a passing `a` run's `OUTPUT begin first-user` block apart from times, compile durations, ANSI codes and the `Node: ... Instance:` banner; if it does not, it is replaced with that block.
- The guide's new sentences name USER for both images, quote IPM's refusal exactly, and name no host, path or rival.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
