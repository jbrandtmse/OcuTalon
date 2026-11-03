---
title: 'Story 15.3: An IPM install survives restarts and reinstalls, and every release proves it'
type: 'feature'
created: '2026-11-02'
status: 'blocked'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** After Story 15.2, an IPM install gives a running OcuTalon, but no check proves that it survives an instance restart, a production restart or a reinstall with the next version (FR-6, NFR-16, NFR-17, AD-5, AD-23). Story 9.1's IPM case is not checked. The release sequence doesn't stop a candidate whose FR-57 job did not pass. No check installs the exact release artifact through an IPM repository with no Node.js. `docs/install-ipm.md` doesn't open with the registry install.

**Approach:** Extend `release/ipm-install.sh`; don't copy it.
- **Path B's stack** takes the restart checks after its own checks: a production restart alone (DW-80), then two instance restarts. It then takes a reinstall with the next version.
- **The forced-failure recovery run** (part `r`) also passes the reinstall checks of this story.
- **The Story 9.1 IPM case** runs after every full install.
- **A new part `p`** installs the packaged artifact through a local filesystem IPM repository on a fresh instance.

The release sequence gains the step `ipmcheck`. It runs the FR-57 job's own script on the candidate's tree, with the candidate's artifact, and stops the release unless the script passes. The guide opens with the registry install. The checklist gets an after-publish author row, and the notes get its slot and the artifact's size.

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
| Artifact (part `p`) | `OCUTALON_IPM_ARTIFACT=<.tgz>`, set by the release step. When it is unset, the module installed by path A's second run is packaged with `zpm "package ocutalon -only -path ..."` in OCUTALON and checked with lib-release's `ipm_artifact_check` | One line, `ARTIFACT ocutalon-<v>.tgz <bytes> bytes`. The artifact check finds no problem | A check problem fails the part |
| Repository install (part `p`) [held: intent gap 2] | A fresh instance (`dc down -v`, `dc up`): IPM 0.10.10 in %SYS, enabled for USER. `command -v node` in the container prints nothing. The artifact is unpacked to `/tmp/ocutalon-repo/ocutalon-<v>/` (lib-release `ipm_unpack`), then `zpm "repo -name ocutalon-local -fs -depth 2 -path /tmp/ocutalon-repo/"` in USER, then `zpm "install ocutalon"` in USER, then `zpm "install ocutalon"` in OCUTALON | The first command ends with the stop line. The second gives Initialize to Activate `SUCCESS` and one `STEP OK` per step. The production runs. `/ocutalon/` serves `Sign in to OcuTalon`, and `ocutalon`/`ocutalon` signs in | Measured at plan, today's code: the second command prints `ERROR! No repositories are configured and enabled in this namespace.` |
| Release gate | `release.sh next` at step `ipmcheck` | The step exports the candidate's tree and runs `bash release/ipm-install.sh` there, with `OCUTALON_IPM_ARTIFACT` set to the candidate's artifact. Exit 0 gives `PASS ipmcheck ...`, a `## FR-57 job` record section and `NEXT push`. Exit 75 gives `WAIT ipmcheck ...` and exit 5 | Any other exit gives `FAIL ipmcheck <first FAIL line>`, the release stops before `push`, and the record is written |

</intent-contract>

## Code Map

- `release/ipm-install.sh` (Lane A, Epic 15):
  - :1-66 the header and check list;
  - :71-79 the modes `all|a|r|b`;
  - :101 `run`;
  - :188 `take_snapshot`; :221 `chk`; :224 `registry_order`; :230 `step_names`;
  - :276-281 `reconcile_rows` and `reconcile_rows_above`;
  - :310-345 `check_second_run [<run> <label>]`, the pattern for a labelled re-check;
  - :507-520 `check_start_outside`, the DW-80 shape: stop and start from a session, +1 row, no second row after 15 s;
  - :523-534 `check_start_by_step`;
  - :553 `scratch_copy`; :560 `module_version`; :565 `seed_mark_value`; :571 `same_config`; :582 `command_failed`;
  - :636-657 `check_recovery`, which gets this story's reinstall checks;
  - :695-738 `reinstall_failures`, where the next-version copy follows the compile copy's `sed` of `<Version>`;
  - :749-765 the stack. `live_web_port` comes before `dc up`, so path B's re-up keeps the port;
  - :862-883 the mode dispatch;
  - :885-979 path B, which ends at `same_services "path B second run"` (:979). The durability checks go after it.
- `docker/tests/lib-live.sh` (read only, contended):
  - :94 `live_lock_dir`; :244 `dc`; :287 `wait_until`; :315 `iris_script`; :485 `check_session`; :493 `session_value`;
  - :622 `item_jobs <file>`; :636 `check_items_run <label>`;
  - :130 exit 75 on a busy lock.
  - Not usable on IPM, because they read the after-start log or the ready marker: `start_log`, `wait_started_ready`, `log_steps`, `check_log`.
- **Restart patterns, read only.**
  - `docker/tests/test-reminder-restart.sh` (Lane B):
    - :56-63 `rem_state` (`state|late|traceHeaderId|waiting|starts|source|...`);
    - :93-138 `fired_lines` and `await_fired`;
    - :159-174 the seeding;
    - :25-26: a clean restart keeps a live waiter, and only lost waiters are re-armed.
  - `release/upgrade-harness.sh` (Lane A): :605-610 the one-line probes `reminder_waiting` and `approval_hold`; :1346-1424 `phase_restart` (`dc restart iris`).
  - `docker/tests/test-production-restart.sh:50-66` `check_eval` (the EvalIn default setting and the "is disabled" refusal), and `docker/tests/test-production.sh:102-104` (row 14).
- **Fixtures,** installed with the package (`module.xml:12` loads `OcuTalon.PKG`):
  - `Test/Data/Fixture.cls`: :22 `Session`, :35 `Turn`, :53 `Reminder`;
  - `Test/Schedule/ReminderFixture.cls`: :65 `Set`, :197 `WaitingCount`, :209 `StartHeaders`, :221 `WaitEnded`;
  - `Test/Bridge/ApprovalRows.cls`: :12 `NewRow`, :37 `Save` (`RequiredRole` `OcuTalonUser`);
  - `Test/Bridge/Approval.cls:2294` `HoldCount`.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` (Lane A, read only):
  - :277 `Answer(ref,action,channel,irisUser,sessionRef)`; :313 the actions `approve` and `reject`;
  - :752 `LiveHold`; :779-814 `Reconcile`.
  - Use `reject`: an approve replays the tool call to Decide.
- `src/ocutalon/cls/OcuTalon/Schedule/Reminder.cls:217-247` `Reconcile` (Lane B, read only). It re-arms through `HeartbeatIn`.
- `src/ocutalon/cls/OcuTalon/Install/ReconcileIn.cls` (read only): :23 and :120 `LOGTEXT`, one Info row per reconciled start.
- `src/preload/cls/OcuTalon/Install/Ipm.cls:16-27` `MapAndStop`, which runs `%IPM.Main.Shell("enable -map -ns OCUTALON -q")` with transactions suspended [held: intent gap 2].
- `src/module.xml:4-16` [held: intent gap 1 for `SystemRequirements`].
- `release/release.sh`:
  - :4 the header's step line; :56 `STEPS="cut image overview ipm push notes"`;
  - :439 `step_fail`; :451 `base_image`;
  - :596-653 `step_overview`. Its export, run and exit mapping become a shared helper;
  - :706-780 `ipm_pack`. :738 shows the `zpm "package ocutalon -only -path ..."` form, and :769 the repository form `repo -name ... -fs -depth 2 -path <dir>/`;
  - :782-890 `step_ipm`. :866-877 is the `## IPM artifact` record, with `Size:`;
  - :1044-1085 `cmd_next`: exit 0 records the step, 4 is stopped, 5 is wait.
- `release/lib-release.sh`: :92 `ipm_artifact_path <v> <rc>` ("Story 15.3 reads it"); :95 `ipm_unpack`; :99-133 `ipm_artifact_check`, which needs only the three module.xml strings.
- `release/security-overview.sh:2-15,61`: the callable-unit contract to follow. Exit 0 is pass, 75 busy, 1 fail and 2 a bad argument. It ends with one `PASS|FAIL|WAIT <unit>` line.
- `release/checklist.sh`:
  - :30-35 the author-row grammar; :57 `CK_AUTHOR_IDS`; :85-94 `ck_author_text`;
  - :423-448 `author_rows`;
  - :44-46 Result `not confirmed` exits 1;
  - :359-366 `outward_hits`. A script naming `community.intersystems.com` after a non-dot character fails `no-outward`.
- `release/notes.sh`: :330-368 `notes_record_part`, which today requires `Mode:`; :370-378 `notes_rehearsal` and `notes_upgrade`; :384-400 `notes_draft` ("How this release was checked").
- `docker/tests/test-release-sequence.sh`:
  - :7-9 the `--live ipm` header;
  - :470-542 `live_run` and `live_ipm_run`, which use local bare repositories only;
  - :1096-1098, :1601, :2069 `NEXT push` after ipm; :2453 the `STEPS` pin;
  - `to_step`, the step chain at about :530-545;
  - :2043-2133 `t_ipm`.
- `docker/tests/test-release-checklist.sh` and `docker/tests/test-release-notes.sh`: the hermetic tests of the two scripts above.
- `docker/tests/test-cpf.sh`:
  - :114-120 rule 6, the exact `run:` line; :123-136 rule 7, deadline < timeout x 60;
  - :264-307 rule 9, the guide. Its awk counts every `STEP` line of every `Configure` block into one total, so a second block of STEP lines fails today.
- `docs/install-ipm.md`:
  - :5 What you need; :19 The first command; :49 The second command; :109 The `iris merge` alternative; :128 Demo mode; :142 The model key; :146 The README account;
  - :47 "Running the first command again in USER or %SYS gives the same stop" [held: intent gap 1].
- `docs/security-overview.md`: no IPM, package or install-path sentence (the investigation's grep). This story makes none of its "this release" sentences untrue, so U-223 condition 2 needs no edit.
- `.github/workflows/lane-a.yml:67-86`: job `ipm-install`, unchanged.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0, measurements** (lane-D throwaways, tag `e15s3i`). Record each result under Design Notes, "Measured in implement".
  - (a) `zpm "enable -community"` in %SYS on a fresh instance with IPM 0.10.10 loaded, in a container with network, run by hand once with `docker run --pull never`. Keep its exact output for the guide. The plan's offline output is in Design Notes.
  - (b) After the ruling on gap 2: the first and second `zpm "install ocutalon"` from the local repository. Confirm that the second run finds the repository in OCUTALON, and that a registry left configured but unreachable doesn't block the local install.
  - (c) The `TIME` lines of `a`, `r`, `b` and `p`, and the job projection (see Verification).
  - (d) That `dc restart iris` keeps a live `ApprovalHold` and a live `ReminderTimer` on the IPM stack, as `test-reminder-restart.sh:25-26` measured on Docker.
- [ ] `release/ipm-install.sh`: extend the functions; don't copy them. Add the header's checks 19-27 and the argument `p`, and add `p` to the usage line.
  - **`check_ipm_case <label>`** (check 19): matrix row "Story 9.1's IPM case", as one `check_session`. Call it in `check_second_run`'s callers: the second run, `check_recovery`, path B's second run, and the next-version reinstall.
  - **`seed_durable <tag>` and the probes.** `seed_durable` writes the session and turn, `RL`, `RX` and `AX` (and `RY` and `AY` when asked) through the fixtures in one session, and keeps their refs in shell variables. The probes `rem_probe <ref>` (`waiting|starts|lastsource`), `hold_probe <ref>` (`liveHold|holdCount`) and `conv_probe` copy only the one-line probe pattern of `upgrade-harness.sh:605-610`. The reason goes under Design Notes.
  - **`check_restart_alone`** (check 21, DW-80): matrix row "Production alone". It reuses `check_start_outside`'s stop/start and row counting: factor the counting into a helper that both call.
  - **`instance_restart <name>`**: `dc restart iris`, `wait_until` the ready query of `check_second_run:331-336`, then the row wait. **`check_restart <n>`** (checks 22 and 23): matrix rows "Instance restart 1" and "Instance restart 2". Restart 2 follows restart 1 with no other action between them.
  - **`check_after_restarts`** (check 24): matrix row "After the restarts". Wait for `RL` with `wait_until` against `WaitEnded`.
  - **`reinstall_next`** (check 25): matrix row "Reinstall, next version". `scratch_copy` of the real folder with only `<Version>` raised (the compile copy's `sed`). `run reinstall-next OCUTALON "zpm \"load <copy>\""`, then `check_second_run reinstall-next "next version"` with the raised version expected, then `item_jobs` before and after.
  - **`check_recovery`** (check 20): matrix row "Recovery run passes 15.3's checks". `reinstall_failures` seeds before the forced failure, and `check_recovery` adds the reinstall checks.
  - **`package_artifact`** (check 26): matrix row "Artifact". It runs after the second run's checks in modes `all` and `p`, before `reinstall_failures`. It is skipped when `OCUTALON_IPM_ARTIFACT` names a file. Source `release/lib-release.sh` for `ipm_artifact_check` and `ipm_unpack`.
  - **Part `p`** (check 27): matrix row "Repository install". Run it at the end of `all`, and after path A's first and second run for `p`. [held: intent gap 2 for the second command's success]
  - **Never named in the script:** the registry host name.
- [ ] `release/release.sh`:
  - **The step.** `STEPS="cut image overview ipm ipmcheck push notes"`, and the header's step line and step paragraph.
  - **The shared helper.** Extract `step_overview`'s export, `node_modules` stub, lock-folder handoff, run and exit mapping into `candidate_unit <step> <script> [VAR=value...]`. `step_overview` calls it, and its behaviour and texts are unchanged.
  - **`step_ipmcheck`** calls `candidate_unit ipmcheck release/ipm-install.sh OCUTALON_IPM_ARTIFACT=<the state's artifact>`. On a pass it writes `## FR-57 job` through `record_write`, with these lines:
    - `Result: pass`
    - `Candidate: <v> rc<n>, <branch> at <sha>`
    - `Artifact: ocutalon-<v>.tgz <bytes> bytes`
    - `Run: release/ipm-install.sh on the candidate's tree, its artifact installed through a local IPM repository`
    - `Checks: <n> passed`
    - `Time: <s> s`
  - **The behaviour:** matrix row "Release gate". It makes no ASK.
  - **`step_ipm`** prints `WARN ipm the artifact is <bytes> bytes, over 5 MB: report it to the Contest Planner` when the artifact is over 5,000,000 bytes, and adds the same note to its `Size:` line.
- [ ] `release/notes.sh`:
  - **`notes_record_part`:** an empty `<real mode>` means a section without `Mode:` is accepted. The existing callers are unchanged.
  - **`notes_ipm`** copies `## IPM artifact`'s `Result:`, `Size:` and `SHA-256:` under `### IPM package`.
  - **`notes_registry`** adds `### Registry install`, with the record's `registry-install` confirmation text and date. With no confirmation it adds `Not run yet: it runs once, after the author publishes the package, and its result is added here.`
  - Both go in "How this release was checked".
- [ ] `release/checklist.sh`: the after-publish author row `registry-install`, in the same line grammar.
  - Unconfirmed, it prints `LATER registry-install: after publishing <v>, run the registry commands of docs/install-ipm.md once on a clean build 154 instance, then add the line "- registry-install: confirmed <YYYY-MM-DD> <result>" under "## Author confirmations" in <record>`.
  - It reads `later` in the table and never makes the result `not confirmed`. Confirmed, it reads `confirmed`.
  - The header documents the row kind.
- [ ] `docker/tests/test-release-sequence.sh`:
  - Pin the new `STEPS`. The chain and every "ipm passes" case now expect `NEXT ipmcheck`.
  - Add a rule `ipmcheck` whose seed stub `release/ipm-install.sh` reads a flag: pass (`NEXT push`, the `## FR-57 job` section, the artifact variable handed over), fail (a stop before push, with the record), and exit 75 (WAIT, exit 5, nothing recorded).
  - Cover the `step_overview` cases unchanged through the helper, and the 5 MB warning.
  - Pin the header text of the new rule.
- [ ] `docker/tests/test-release-notes.sh`: cases for `### IPM package` and `### Registry install`, confirmed and unconfirmed.
- [ ] `docker/tests/test-release-checklist.sh`: `registry-install` is unconfirmed (`LATER`, and the result is still `pass` when every other row passes), then confirmed, then malformed (as the other rows treat it).
- [ ] `docs/install-ipm.md`, rewritten in the AC's order:
  1. **What you need.**
  2. **"Install from the package registry":** `zpm "enable -community"` in %SYS with the Task 0 (a) output, then in USER `zpm "install ocutalon"` and its stop, `zn "OCUTALON"`, and `zpm "install ocutalon"` with its STEP lines.
     - Until the author publishes, it shows part `p`'s real output and says that it comes from a local repository holding the same package (`zpm "repo -name ocutalon-local -fs -depth 2 -path <folder>/"`). [held: intent gap 2]
  3. **"Install from the source folder (developers; needs Node.js)":** today's first-command and second-command sections.
  4. Then the `iris merge` alternative, Demo mode, the model key, the README account and the step-failure paragraph, unchanged.
- [ ] `docker/tests/test-cpf.sh`, rule 9:
  - Count STEP lines per `Configure START`/`SUCCESS` block. Each block holds every step of the order, in order, and there is at least one block.
  - Add the phrases `zpm "enable -community"` and `zpm "install ocutalon"`.
  - The registry heading comes before the source-folder heading.
  - Add one sample that keeps the rule and one that breaks it.
- [ ] [held: intent gap 1] `src/module.xml`: `<SystemRequirements Version=">=2026.3" Interoperability="enabled"/>` after `<SourcesRoot>`. Also: `release/ipm-install.sh` check 5's %SYS case, and `docs/install-ipm.md:47`, as the ruling says.
- [ ] [held: intent gap 2] `src/preload/cls/OcuTalon/Install/Ipm.cls` `MapAndStop`: also map IPM's repository globals into OCUTALON, as the ruling says. Then update `release/ipm-install.sh` check 3's expected mappings (`$tmp/expected.chk`).
- [ ] **DW-576** (measured task): after the release.sh changes, run `docker/tests/test-release-sequence.sh --live ipm` once, in its own call, on HEAD, which carries the two-run `MapAndStop` `module.xml`. Record its `TIME ipm`, its result and the namespace that it packaged in (it must be OCUTALON) under Design Notes, "Measured in implement".

**Acceptance Criteria:**
- Given an IPM install holding a conversation, a pending reminder and a pending approval request, when the production restarts alone and then the instance restarts twice in a row, then the rows "Production alone", "Instance restart 1", "Instance restart 2" and "After the restarts" hold, and `release/ipm-install.sh b` passes. This is the Integration AC: its consumer is the instance's autostart, and its effect is `ReconcileIn` re-arming each lost waiter exactly once.
- Given an IPM install holding data, when the install command runs again with the same version (part `r`'s recovery run) or the next one (path B), then the rows "Recovery run passes 15.3's checks" and "Reinstall, next version" hold. The forced step failure and the failed compile of Story 15.2 still pass (U-176), and `release/ipm-install.sh r` passes.
- Given any full IPM install, when Story 9.1's IPM case is checked, then the row "Story 9.1's IPM case" holds at each of its four points.
- Given a push or pull request, when the `ipm-install` job runs `bash release/ipm-install.sh` with no argument, then it runs paths A, `r`, B with its durability checks, and `p`, and fails unless every check passes. `test-cpf.sh` rules 6 and 7 still pass, and the fork guard is unchanged.
- Given a release candidate, when `release.sh next` reaches `ipmcheck`, then the row "Release gate" holds (`test-release-sequence.sh` rule `ipmcheck`). This is the Integration AC: its consumer is the release sequence, and its effect is a stop before `push`.
- Given the artifact the release would publish, when part `p` installs it through a local filesystem repository on a fresh instance with no Node.js, then the rows "Artifact" and "Repository install" hold [held: intent gap 2], and `step_ipm`'s record and the notes give its size (`test-release-notes.sh`).
- Given the registry check after publishing, when the author confirms `registry-install`, then the checklist reads it as confirmed and the notes carry its result. Before that, the row reads `later` and never blocks the checklist (`test-release-checklist.sh`).
- Given `docs/install-ipm.md`, when it is read, then it opens with the registry install, its output blocks are a passing run's, and `test-cpf.sh` rule 9 and `test-boundaries.sh` pass.
- Given `src/module.xml` with `SystemRequirements` [held: intent gap 1], when the package loads on build 154, then IPM's version check passes ("2026.3"), `release/lib-release.sh`'s artifact checks pass, and the first run behaves as the ruling says.

## Spec Change Log

## Review Triage Log

## Design Notes

### Intent gaps (blocking)

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

### Lead pre-rulings (both `decide`, by the orchestrator's dispatch)
1. **The registry-install AC.** This run never publishes. It delivers:
   - the guide's registry section, measured on a clean build 154 throwaway up to the point that needs the published package: `zpm "enable -community"`, its exact IPM 0.10.10 form, and its real output (Task 0 (a));
   - the after-publish checklist row `registry-install`;
   - the notes slot `### Registry install`.
   
   The author's run itself is the hand gate, not this story's CI. Planning found no test that only a published package can pass. Part `p` installs the same artifact from a local repository, but its second command depends on gap 2, which is a different question.
2. **The release-gate AC.** The candidate is pushed only at `push`, and `lane-a` doesn't run on `release/*` branches. So "the FR-57 job passed on that candidate" is delivered as `step_ipmcheck`: it runs the job's own command, `bash release/ipm-install.sh`, on the candidate's exported tree, with the candidate's artifact, before `push`.
   - Story 11.14's pushed-candidate sequence calls `step_ipmcheck` (a `step_<name>` function in `release/release.sh`, which 11.14 extends), or reads the `ipm-install` job of its full CI run.
   - `release/ipm-install.sh` already has the unit contract that `security-overview.sh` has: exit 0 pass, 75 busy (lib-live), 1 fail, 2 usage.
   - This is not a set-aside or a deferral.

### Decided in-stage
1. **`ipmcheck` comes after `ipm`, not beside `overview`.** The exact artifact exists only after `ipm`, and the AC installs that artifact before any publish. It is still before `push`.
2. **The restarts and the next-version reinstall run on path B's stack, and the same-version checks on part `r`'s recovery run.** This adds no stack, and "the forced-failure re-run also passes this story's checks" becomes the recovery run's reinstall checks plus Story 9.1's case. The two instance restarts run once, on path B.
3. **"Re-armed once" uses lost waiters.** A clean restart keeps a live waiter (Lane B's measurement; Task 0 (d) confirms it on IPM), so the check seeds pending rows with no waiter and asserts one re-arm each, and no new start on restart 2. The live waiters (`RL`, and `AX` after DW-80's re-arm) must stay the same process.
4. **The approval is answered with `reject`.** An approve replays the fixture's tool call to Decide.
5. **Part `p` packages from path A's installed module in CI.** It uses `zpm "package ocutalon -only"`, as `ipm_pack` does, plus `ipm_artifact_check`. The release step passes the release's own artifact. Packing in a new container would cost about 40-90 s more (inference).
6. **The size threshold is 5,000,000 bytes** ("a few MB"; an implementation detail).
7. **`registry-install` is an after-publish row.** A checklist that gates a candidate can't require an act done after publishing, so the row reports `later` until the author confirms it.
8. **Story 9.1's "IPM case"** exists only as criteria text (`epics.md:3672`, spec 9.1). No disabled or skipped test was left in the code. "Turn it on" means adding `check_ipm_case` to the job's script.

### Size estimate
About 7 hours from implement to commit:
- implement about 3.5 h;
- QA and review about 1.5 h;
- smoke and CI about 1.5 h, plus a re-run for each held item after the rulings.

What drives it:
- each `ipm-install.sh` part is a 3-6 minute live run, and each of about 12 mutations needs one;
- the release, notes and checklist hermetic suites, `test-release-sequence.sh` at 170 s each;
- the guide rewrite from captured output.

**Proposed split** (the lead decides; both before rc1, and the release gate and FR-57 checks stay in the release):
- **15.3,** the durability in the FR-57 job (about 3.5 h): restarts, DW-80, reinstalls, the recovery run's checks, Story 9.1's case and `SystemRequirements` (gap 1). ACs 1-4 and the last.
- **15.4,** the release proof (about 3.5 h): part `p` and `MapAndStop`'s repository mapping (gap 2), `ipmcheck`, the notes, the checklist row, the guide rewrite and DW-576. ACs 5-8.

### CI budget (the 35-minute job)
- **Measured:** the job took 15.9 min of steps on `3dd30fc`. Locally, `a` takes 166 s, `r` 272 s and `b` 142 s (lane D). The full run was 433 s locally in Story 15.2, about 2.2 times faster than the runner.
- **Added, all inference:**
  - path B's checks: about 200 s locally (two restarts at about 30 s each, two row waits of 15 s, the reinstall about 40 s, probes about 30 s; the reminder's 180 s due time overlaps the restarts);
  - the recovery run: about 40 s;
  - part `p`: about 120 s (packaging about 10 s, one fresh cycle about 15 s, two installs about 65 s, the web checks).
  - That is about 360 s locally, or about 13 min on the runner, so about 29 min of 35.
- **How the margin is kept:** no new compose project, no repeated restarts, and the waits overlap.
- **Rule for the implement stage:** compute the projection as (the sum of the job's `TIME` lines from `a`, `r`, `b` and `p`, minus the repeated path-A runs of `b` and `p`) x 2.2. If it is over 30 min, stop with `## Clarification Needed` before committing. The remedy then is a second fork-guarded lane-a job for part `p`, a lead decision that adds a job and renames none. Never raise the timeout.

### Measured at plan (2026-11-02)
- Slot D: build 154 (`2026.3.0AI`, `GetMajor` 2026, `GetMinor` 3, `GetPoint` "0AI"). Slot D has no `%IPM`.
- **The base image ships `zpm 0.10.5-SNAPSHOT` in HSLIB.** `enable -community` skips it ("IPM already installed"), so the guide's "IPM 0.10.10 loaded in %SYS" stays.
- **`zpm "enable -community"`, offline:**
  - It prints `Version of IPM in current namespace:` and `%SYS> zpm 0.10.10`, then three `RUNNING command:` blocks:
    - `repo -delete-all`;
    - `repo -reset-defaults`, which prints a `WARNING: Using -password via the CLI is insecure...` line and the `registry` repository, `Source: https://pm.community.intersystems.com`;
    - `enable -map -repos -globally`, which maps `%IPM` into HSCUSTOM, HSSYS, HSSYSLOCALTEMP and USER, and the repositories into USER.
  - Each ends `Command "..." finished successfull`.
  - Offline, the registry shows `Available? No` and `currently unavailable`. Task 0 (a) measures the online form for the guide.
- **A filesystem repository** lists a module only from an unpacked `<name>-<version>/` folder, not from a `.tgz` in the folder (`-list-modules` printed nothing). `install` from the unpacked folder took 6 s for the test module.
- The plan's throwaways (`e15s3plan-*`) were removed.

### Governing ADs (Rule 6)
- AD-2: one package, no dependency.
- AD-3: OCUTALON's mappings, which gap 2 extends.
- AD-5: waiters re-armed from rows, only `ApprovalHold` and `ReminderTimer` as long timers, append-only storage, and settings kept across reinstall.
- AD-16: EvalIn off on the judges' install (Story 9.1's case).
- AD-22: throwaways, mocks only in CI, fork pull requests never on the runner.
- AD-23: the IPM install runs the same steps, autostart, every start reconciled, and "A restart test on an IPM install proves the waiters are re-armed".
- AD-33: `ReconcileIn` is Lane A's.
- The conventions "IPM early step" (gap 2 would amend it) and "IPM steps".

No other AC contradicts an AD.

### Ledger inbox (Rule 17)
- **DW-80** is addressed by check 21 and the matrix row "Production alone".
- **DW-576** is addressed by the DW-576 task, a live `--live ipm` run on HEAD's two-run `module.xml`.
- **Declined DW-306:** this story doesn't edit `docker/tests/test-production.sh`, which is contended, so its row 21 wait is left for the next story that edits that file.

### Integration ACs, Consumed-by and Consumes (Rules 1 and 2)
- **Integration ACs:** the instance autostart, through `ReconcileIn` (AC 1), and the release sequence's `ipmcheck` (AC 5).
- **Consumed-by:**
  - Story 11.14 calls `step_ipmcheck`, or reads the `ipm-install` job;
  - Story 31.3 builds the README's IPM section from the guide's order;
  - Stories 19.2 and 34.1 and Epic 38's 1.0.0 checks run on this install path.
- **Consumes:**
  - Stories 15.1 and 15.2's harness and checks;
  - Story 11.17's artifact (`ipm_artifact_path`, `ipm_artifact_check`, `ipm_unpack`);
  - `Test.Data.Fixture`, `Test.Schedule.ReminderFixture` (Lane B, called only), `Test.Bridge.ApprovalRows` and `HoldCount`;
  - `ReconcileIn`;
  - the CI model mock (unused by the new checks).

### Extend, don't copy (Rule 2)
- `step_ipmcheck` and `step_overview` share `candidate_unit`.
- `check_restart_alone` shares the row counting of `check_start_outside`.
- `reinstall_next` reuses `scratch_copy` and `check_second_run`.
- `notes_ipm` extends `notes_record_part`.
- `registry-install` is an author row of `checklist.sh`'s grammar.
- **Copies, with their reasons:**
  - The three one-line probes copy `upgrade-harness.sh:605-610`, a script that runs when it is sourced.
  - The reminder wait copies about 10 lines of `test-reminder-restart.sh`'s `await_fired`, a Lane B script's local function (U-177; `lib-live.sh` is contended).

### Footprint, for the lead
Inside Epic 15's files: `release/**`, `docker/tests/test-release-*.sh`, `docker/tests/test-cpf.sh`, `docs/install-ipm.md` and `src/module.xml`. Footprint extension, held by gap 2: `src/preload/cls/OcuTalon/Install/Ipm.cls`, Story 15.1's class, which no contended epic owns. `lane-a.yml` and `ci/units.sh` are unchanged.

## Verification

Run every `[L]` command from the epic-15 worktree root, in the foreground, one per call, with `timeout: 600000`. Prefix each with:

`OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=15 stage=implement' OCUTALON_RUN_TAG=e15s3i`

Fresh throwaways only. End with `[L] bash ci/iris.sh teardown`, also after a failure.

**Commands:**
- `bash docker/tests/test-cpf.sh` (loop). Expected: every PASS, exit 0.
- `bash docker/tests/test-pinned-sources.sh` (loop). Expected: `all checks passed`.
- `bash docker/tests/test-boundaries.sh` (loop). Expected: exit 0.
- `bash docker/tests/test-release-sequence.sh` (loop, about 170 s). Expected: no FAIL.
- `bash docker/tests/test-release-notes.sh` (loop). Expected: no FAIL.
- `bash docker/tests/test-release-checklist.sh` (loop). Expected: no FAIL.
- `[L] bash ci/iris.sh build` (loop; first on every pass that runs IRIS). Expected: `BUILD the web bundle is built`.
- `[L] bash release/ipm-install.sh a` (loop). Expected: `ipm-install: all checks passed`.
- `[L] bash release/ipm-install.sh r` (loop). Expected: all checks passed.
- `[L] bash release/ipm-install.sh b` (loop). Expected: all checks passed.
- `[L] bash release/ipm-install.sh p` (loop). Expected: all checks passed.
- (once) Each remaining script of `CHECK_SCRIPTS` in `ci/units.sh`, one `bash docker/tests/test-<name>.sh` per call (`ci/checks.sh` takes 16 min). Expected: no failure.
- `[L] bash ci/iris.sh shard lane-a@Install` (once, 222 s). Expected: every class passed.
- `[L] bash ci/iris.sh live install-start` (once). Expected: pass. The image loads the changed `module.xml` in OCUTALON.
- `[L] bash ci/iris.sh live reminder-restart` (once). Expected: pass.
- `[L] bash ci/iris.sh live production-restart` (once). Expected: pass.
- `[L] bash docker/tests/test-release-sequence.sh --live ipm` (once, DW-576; in its own call). Expected: `PASS ipm`, packaged in OCUTALON. Record its time.
- The full `release/ipm-install.sh` with no argument doesn't fit one 10-minute call locally (about 13 min, inference), so CI's `ipm-install` job is its first full run.
- `[L] bash ci/iris.sh teardown` (once, last). Expected: a `TEARDOWN tag e15s3i` line.

**Planned mutations (Rule 19).** Apply each, see red, revert, and confirm that `git status --short` and `git diff --stat` are unchanged. Then write the `mutation:` lines here.

| Mutation | Test that goes red | Pins |
|---|---|---|
| `ReconcileIn` never reaches its run branch | `ipm-install.sh b`, checks 21-22 | restart re-arms |
| `Approval.Reconcile` starts a hold even when `LiveHold` is set (a seeded state in the script: a second `StartHold` before restart 2) | `ipm-install.sh b`, check 23 ("no duplicate") | exactly once |
| The script's restart 2 is skipped | `ipm-install.sh b`, check 23 | two restarts |
| `Production.AutoStart` never marks | `ipm-install.sh b`, check 22 (production not running) | autostart |
| The next-version copy keeps the version | `ipm-install.sh b`, check 25 (version) | next version |
| The Production step doesn't restart a running production (a script seam: stop the items' restart) | `ipm-install.sh b`, check 25 (job ids) | new code |
| The recovery run's seeded approval is deleted | `ipm-install.sh r`, check 20 | reinstall keeps data |
| The EvalIn default setting is seeded to 1 before the check | `ipm-install.sh a`, check 19 | Story 9.1's case |
| `step_ipmcheck` ignores the unit's exit code | `test-release-sequence.sh` rule `ipmcheck` | release gate |
| `notes_ipm` drops the `Size:` line | `test-release-notes.sh` | artifact size |
| `registry-install` counts as `not confirmed` | `test-release-checklist.sh` | after-publish row |
| The guide without `zpm "enable -community"`, or with the registry section after the folder section | `test-cpf.sh` rule 9 | guide order |

**Shared surfaces:**
- **`release.sh`'s `STEPS` and the step after `ipm`:** `test-release-sequence.sh` (:1098, :2069, :2453, `to_step`), and later Story 11.14.
- **`checklist.sh`'s author ids and its section table:** `test-release-checklist.sh`.
- **`notes.sh`'s "How this release was checked":** `test-release-notes.sh`.
- **`docs/install-ipm.md`:** `test-cpf.sh` rule 9.
- **`release/ipm-install.sh`'s check list and modes:** lane-a's `ipm-install` job and `test-cpf.sh` rules 6 and 7.
- **`src/module.xml`** [held]: `test-cpf.sh`, `test-pinned-sources.sh`, `ci/warm.sh`'s manifest (a change refuses a warm reload) and `test-build-inputs.sh`.
- **Check 3's expected OCUTALON mappings** [held]: `release/ipm-install.sh`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Manual checks:**
- The guide's output blocks equal those of the run it cites, with ANSI codes and the banner removed.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: (1) Story 15.3's SystemRequirements bullet: `Interoperability="enabled"` makes IPM 0.10.10 refuse the package in %SYS before any phase ("ERROR! This module requires an interoperability-enabled namespace. %SYS is not interoperability-enabled.", measured on build 154), but Story 15.1's criteria, `release/ipm-install.sh` check 5 and `docs/install-ipm.md:47` run or promise the first run in %SYS. The bullet makes this a clarification. Recommended: narrow 15.1's "any namespace" to "any Interoperability-enabled namespace (USER on build 154)", make check 5's %SYS case assert IPM's refusal with no residue, and change the guide's two sentences. The version half passes ("2026.3"). (2) The registry and local-repository installs: after the first `zpm "install ocutalon"` in USER, the second in OCUTALON prints "ERROR! No repositories are configured and enabled in this namespace." (measured with the real package from a filesystem repository, also after `zpm "enable -community"`), because MapAndStop maps only the %IPM package and routines. So "the README's two commands" with "the two-step namespace message" can't hold. Recommended: option A, MapAndStop also maps IPM's repository globals into OCUTALON (`enable -map -repos -ns OCUTALON -q`, or `MapGlobalEquivalently` for `^IPM.Repo.Definition{D,S,I}`), with a spine amendment to the "IPM early step" row. Everything else is planned and ready; the tasks these two rulings affect are marked [held].
