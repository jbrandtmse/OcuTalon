---
title: 'Story 15.4: Every release proves the IPM package, and the guide opens with the registry install'
type: 'feature'
created: '2026-11-02'
status: 'ready-for-dev'
baseline_revision: '8d6ce22da5f21c72fc18ffda4cd43f199628d1ee'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Nothing stops a release whose IPM package fails FR-57. The exact artifact a release would publish has never been installed from an IPM repository on an instance with no Node.js, and today it cannot be: IPM keeps repositories per namespace, so the second `zpm "install ocutalon"` in OCUTALON finds none (measured). `docs/install-ipm.md` opens with the load-from-folder path, which needs Node.js. DW-576: `release.sh`'s ipm step had never run the two-run path live.

**Approach:**
- **Repository mapping (U-232).** `MapAndStop`, outside OCUTALON, also maps IPM's repository definitions (`^IPM.Repo.Definition{D,S,I}`) into OCUTALON through `%IPM.Utils.Build.MapGlobalEquivalently`. IPM's own `enable -map -repos` form skips OCUTALON (measured). A new Unconfigure step removes only that mapping.
- **Part `p` in `release/ipm-install.sh`.** It installs the exact artifact from a local filesystem repository on a fresh instance with no Node.js, signs in, then uninstalls and proves the definitions are unchanged.
- **Release step `ipmcheck`.** It comes after `ipm` and runs the FR-57 job's own command on the candidate, with the candidate's artifact.
- **Notes and checklist.** The release notes record the artifact's size and get a registry-install slot. The checklist gets the hand row `registry-install`.
- **Guide.** The guide is rewritten registry-first.
- **Security overview.** The Data section lists the mapping.

## Boundaries & Constraints

**Always:**
- **Where installs run.** Every install, uninstall and measurement runs on lane-D throwaways of `docker/tests/lib-live.sh` (`release/ipm/Dockerfile`), one fresh stack at a time (AD-22, Rule 21).
- **How the definitions are handled.** They are mapped as they are. They are never copied, created, edited or printed, and no test or log prints a definition's fields: no `repo -list`, and the repository a test creates is made in a session whose output is discarded. The definitions hash is computed and compared inside the container and never printed.
- **The FR-57 job stays as it is:** one job `ipm-install`, `timeout-minutes: 35`, `run: bash release/ipm-install.sh`, the fork guard (CON-1). `lane-a.yml` is unchanged.
- **Time limits.**
  - The job's projected minutes stay under 30 (see Design Notes, "CI budget"); otherwise stop with `## Clarification Needed`.
  - Local `release/ipm-install.sh p` must finish in one 10-minute call. Over 540 s is a stop.
- **U-231 stays in force.** The guide's first command runs in USER, quotes IPM's refusal line once and says "run the command in USER instead". `test-cpf.sh` rules 9-11 stay green. Rule 9 is adjusted only for the guide's second Configure block, and rule 8 only for the new Unconfigure Invoke.
- **Exit codes.** `ipmcheck` maps `ipm-install.sh`'s exits: 0 pass, 75 busy (the step answers WAIT, exit 5), anything else fail. It is a `step_<name>` function that Story 11.14 can call.
- **Committed files carry** no local path, no non-ASCII byte and no secret. `release/` scripts never name the registry host (the no-outward and ipmnet scans).

**Never:**
- Never edit `docker/merge.cpf`, `README.md`, the spine, `epics.md`, a Lane B class or test, Epic 13's lines or the existing checklist rows.
- Never add or rename a job, unit or group, and never raise a timeout.
- Never publish, tag or push.
- Never run `enable -community` or contact the registry from a committed test or script. It is only measured by hand.
- Never edit `docs/security-overview.md`'s Epic 13 bridge-guide sentence.
- Never add a switch that weakens or skips a check.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First run maps the definitions | `zpm "load"` or `zpm "install ocutalon"` in USER (path A and part `p`) | The stop line, as before. Check 3's snapshot also holds `CHK\|omap-MapGlobals\|IPM.Repo.Definition{D,I,S}\|<repo_db>`, where `repo_db` is the database where each global resolves in USER (read by a probe, like `ipm_db`). OCUTALON_DATA holds no `^IPM.Repo.Definition*` node. The repeat in USER gives the same snapshot | A missing or extra line is a FAIL naming it |
| Second run, Docker path, merge path | A run in OCUTALON; the image's after-start; path B (`iris merge` + `enable -map -ns OCUTALON`) | No repository mapping is added or changed. Path B's view leaves out the `%IPM` and `IPM.Repo.Definition` lines and holds none | as today |
| Artifact | `OCUTALON_IPM_ARTIFACT=<.tgz>` set (by `ipmcheck`). When it is unset (CI, local), the module installed by path A's second run is packaged with `zpm "package ocutalon -only -path /tmp/ocutalon-pkg/ocutalon-<v>"` in OCUTALON, copied out and checked with lib-release `ipm_artifact_check` | `ARTIFACT ocutalon-<v>.tgz <bytes> bytes`, and no problem lines | A missing file or a problem line fails part `p` |
| Repository install (part `p`) | A fresh instance (`dc down -v`, `dc up`). IPM 0.10.10 loaded in %SYS and enabled for USER. The artifact is unpacked into `/tmp/ocutalon-repo/ocutalon-<v>/` (made readable). `zpm "repo -name ocutalon-local -fs -depth 2 -path /tmp/ocutalon-repo/"` runs in USER with its output discarded. Then `zpm "install ocutalon"` in USER, then the same command in OCUTALON | No `node` or `npm` in the container. The USER run ends with the stop line. The OCUTALON run passes `check_run_ok` (Initialize to Activate SUCCESS, every STEP OK in order, the production running, autostart, 0 dependencies, Story 9.1's case). `/ocutalon/` serves `Sign in to OcuTalon`, and `ocutalon`/`ocutalon` signs in | Today: `ERROR! No repositories are configured and enabled in this namespace.` |
| Uninstall keeps the definitions (U-232 condition 1) | After the checks of the row above, `zpm "uninstall ocutalon"` runs in OCUTALON | OCUTALON's three `IPM.Repo.Definition` mappings are gone, and every other OCUTALON mapping, USER's mappings and the services are unchanged. The hash of USER's three globals right after the uninstall equals the hash right before it, and the hash taken before the first command (see Task 0 (c)). Only `same\|<nodes>` (nodes > 0) is printed | `differs` or 0 nodes is a FAIL. The hash is never printed |
| Gate passes | `release.sh next` at `ipmcheck`. The `ipm` step passed and its artifact exists | The step runs `bash release/ipm-install.sh` on an export of the candidate's tree, with `OCUTALON_IPM_ARTIFACT` set to the artifact, the lane lock folder, a run tag of its own and `OCUTALON_LIVE_DEADLINE=1980`, then `ci/iris.sh teardown`. Output: `PASS ipmcheck ...`, a `## FR-57 job` record section with `Result: pass`, and `NEXT push` | - |
| Gate fails | The unit exits 1, or any code other than 0 or 75 | `FAIL ipmcheck <the unit's first FAIL line>`. The record carries a `## FR-57 job` section with `Result: fail`. The release stops before `push`, and no push question is asked | - |
| Gate busy | The unit exits 75 | `WAIT ipmcheck the lane's throwaway lock is busy`, exit 5. Nothing is recorded, and the next call runs the step again | - |
| Gate refusals | The `ipm` step did not pass, the artifact is missing, or the candidate has no `release/ipm-install.sh` | `FAIL ipmcheck <reason>` before any container starts | - |
| Large artifact | The artifact is over 5,000,000 bytes | A `WARN ipmcheck the artifact is <n> bytes, over 5000000; report it to the Contest Planner` line, and a `Size:` note in the section. It is not a failure | - |
| Notes | `release/notes.sh` with the record | Under `## How this release was checked`: `### IPM package` (the record's `## IPM artifact` size line and the `## FR-57 job` result, copied), then `### Registry install` with the not-run-yet slot. A missing section says it is not in the record | - |
| Checklist row | `release/checklist.sh`; the record has no `- registry-install: confirmed <date>` line, or a malformed one | Row `registry-install`, result `later`, and a `LATER registry-install: ...` line naming the line to add. The checklist's result is unchanged (a pass stays a pass). With a valid line, the row reads `confirmed`, with the date | - |

</intent-contract>

## Code Map

The anchors are taken at `8d6ce22d`.

- `src/preload/cls/OcuTalon/Install/Ipm.cls` (30 lines; Epic 15's file, outside the declared footprint: report it):
  - `MapAndStop` :17-30. The repository mapping goes inside the same suspension, after the `%IPM` Shell call, only when `$Namespace '= "OCUTALON"`.
  - A new `UnmapRepos()` for the Unconfigure Invoke. It prints nothing, and it never kills or sets a global.
  - The doc comments state the contract. The header comment says "maps IPM", and it grows by one clause.
- `src/module.xml:15-16`: add `<Invoke Class="OcuTalon.Install.Ipm" Method="UnmapRepos" Phase="Unconfigure" When="Before"/>` after the Configure Invoke. `SystemRequirements` stays as it is.
- IPM 0.10.10 (measured at plan, in the scratch run's `sig` output):
  - `%IPM.Utils.Build.MapGlobalEquivalently(pGlobalName, pSourceNamespace, pMappedToNamespace, pSkipActivation=0)` resolves the source database (`GetGlobalDest`) and calls `%IPM.Utils.Module.AddGlobalMapping`, which activates. A repeat call is OK and leaves the mapping as it was.
  - IPM's own `-repos` code is `%IPM.Main:3569-3602`. It skips a namespace whose IPM is "Installed In" another namespace, and it skips when the target holds `$Data(^IPM.Repo.DefinitionD)\2`.
  - `unmap -repos-only -ns OCUTALON -q` is `UnmapIPM`, `%IPM.Main:3837-3910`. It calls `RemoveGlobalMapping` for D, S and I and nothing else.
- `release/ipm-install.sh` (1430 lines; extend, don't copy):
  - :1-115: the header, the checks list (check 3's text :15-17 gains the repository mapping, check 7's "minus the %IPM mappings" gains "and the repository mappings", and part `p` adds its own checks 26+) and the modes paragraph (`p`).
  - :105-112: `case $mode` (add `p`; the usage line). :113-116: source `release/lib-release.sh` for `ipm_unpack` and `ipm_artifact_check`.
  - :130 `run`; :150 `snapshot`; :217 `take_snapshot`; :234 `stops_with_next_command`; :359 `check_run_ok`; :392 `check_second_run`.
  - :440-490 `check_web`: factor its first two checks plus `logout_all` into `check_signin`, and `check_web` calls it (Rule 2).
  - :1199-1206: the precondition session (load IPM, `enable -map -ns USER -q`). Factor it into `ipm_precondition <label>`, which path A and part `p` call. Path B still loads IPM only.
  - :1207-1210: `ipm_db` from the base snapshot. Add `repo_db` the same way (a probe of `GetGlobalDest("USER","^IPM.Repo.DefinitionD")`, resolved to the database name).
  - :1234-1250: `expected.chk` gains three `omap-MapGlobals|IPM.Repo.Definition?|$repo_db` lines. The `compare_chk` label names them.
  - :1302-1315: path A's second run. Package here when mode is `all` or `p` and `OCUTALON_IPM_ARTIFACT` is unset. In mode `p` with the artifact set, skip the second run.
  - :1316-1323: the `a`/`r` exit. Add a `p` branch that runs part `p` and exits.
  - :1356: path B `view()` also leaves out `IPM.Repo.Definition`.
  - :1415-1430: after path B (`all`), part `p`, then the final lines.
- `release/release.sh` (1248 lines):
  - :3-45: the header (steps list, an `ipmcheck` paragraph).
  - :56 `STEPS="cut image overview ipm ipmcheck push notes"`.
  - :604-654 `step_overview`: the pattern to extend. Factor the export (`git archive "$cand" | tar -x`) and the `live_lock_dir` lookup into a helper that both steps call. The exit mapping stays per step.
  - :782-903 `step_ipm`: `sget ipm_result`, `ipm_artifact_path "$version" "$rc"`, the `record_write` section pattern (:878-889).
  - `step_ipmcheck` goes after `step_ipm`, before `step_push` :905. It makes no ASK. `ipmcheck_section` writes `## FR-57 job`.
- `release/lib-release.sh`: :92 `ipm_artifact_path`; :95 `ipm_unpack`; :99-132 `ipm_artifact_check`; :359 `record_write`. Unchanged.
- `release/notes.sh`:
  - :15-24 the draft-order header; :277 `notes_section`; :375 `notes_upgrade` (the pattern).
  - :386-414 `notes_draft`: add `cat "$w/ipm.md"` after `upgrade.md`.
  - :638-646 the work files: add `notes_ipm "$record" > "$nt_work/ipm.md"`.
- `release/checklist.sh`:
  - :28-35 the author's-rows paragraph: append a paragraph after it.
  - :405 `ck_confirmed_date` (reuse); :423-451 `author_rows` (unchanged); :453 `checklist_result` (`later` counts as neither fail nor not confirmed).
  - A new `registry_row <record>` after `author_rows`, and its call after `author_rows "$record"` at :572. Nothing else changes.
- Tests:
  - `docker/tests/test-release-sequence.sh` (all Epic 15's):
    - :4-56 header; :415-442 `stub_text` (add a stub `release/ipm-install.sh` in the same style, seeded in `mkseed` :461);
    - :536-548 `to_step` (add the ipmcheck stop);
    - the pins at :1098, :1240, :2069 (`NEXT push` and `next push` after ipm become `ipmcheck`) and :2453 (the STEPS line);
    - a new `t_ipmcheck` with `rule ipmcheck`;
    - the `--live ipm` path :2507-2560 stops after ipm and is unchanged.
  - `docker/tests/test-release-checklist.sh`: a new `t_registry_row` and `rule registry-row`, appended. The pinned counts (`LINES 9`, `LINES 7`, seven CONFIRM lines) call `author_rows` alone and stay as they are.
  - `docker/tests/test-release-notes.sh`: `t_base` :247-322 (the draft's headings) and any byte-pinned draft, plus a case for the two new subsections.
  - `docker/tests/test-cpf.sh`:
    - :142-153 rule 8 (`/Configure/` becomes `/Phase="Configure"/`; add an Unconfigure sample that passes);
    - :269-330 rule 9 (the STEP order checked per Configure block, at least one block);
    - a new rule 12 (the guide's registry-first structure);
    - :433-482 rule 11 (unchanged; its phrases must stay in the guide).
- `docs/install-ipm.md` (167 lines): the structure is in Tasks. Its existing load-from-folder output blocks (:27-43, :59-100) stay as the developers' section.
- `docs/security-overview.md:145-151` (the Data section, hand-written): one bullet after :150. It is outside the generated markers :5-81, so nothing is regenerated.
- `docker/tests/lib-live.sh` (read only, contended): :244 `dc`; :311 `iris_script` (prints only CHK lines); :485 `check_session`; :493 `session_value`. Copying files in follows `release.sh:730-732` (`docker cp`, then `docker exec -u root ... chmod -R a+rX`), because `release.sh` runs with umask 077.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (the first `p` loop is the measurement): (a) does `module.xml` load with the Unconfigure Invoke, and does `zpm "uninstall ocutalon"` in OCUTALON run `UnmapRepos`? Record what the uninstall prints and how it ends. If the Invoke is rejected or never runs, HALT with `intent gap` (the recommendation: a module lifecycle class, or a documented `zpm "unmap -repos-only -ns OCUTALON"` line). (b) Copy the guide's registry-section output blocks from a passing `p` run's `p-first` and `p-second` OUTPUT blocks. (c) If IPM's own install changes USER's definitions between the hash before the first command (H0) and the hash before the uninstall (H1), assert only H1 = H2 and record that.
- [ ] `src/preload/cls/OcuTalon/Install/Ipm.cls`, `MapAndStop`:
  - Outside OCUTALON only, and inside the existing suspension: unless OCUTALON already sees `$Data(^IPM.Repo.DefinitionD)\2` (IPM's own skip rule), call `MapGlobalEquivalently` from `$Namespace` to OCUTALON for each of D, S and I. The first error is returned unchanged.
  - `UnmapRepos()`: `%IPM.Main.Shell("unmap -repos-only -ns OCUTALON -q")` with transactions suspended and restored, returning its status. It kills and sets no global.
  - This covers U-232 and the matrix rows "First run maps the definitions" and "Uninstall keeps the definitions".
- [ ] `src/module.xml`: the Unconfigure Invoke, after the Configure Invoke, on a line of its own.
- [ ] `release/ipm-install.sh`:
  - Check 3's three lines with `repo_db`, plus "OCUTALON_DATA holds no `^IPM.Repo.Definition*` node".
  - Path B's view leaves out the repository lines.
  - The helpers `ipm_precondition` and `check_signin`.
  - Packaging (`TIME package`), with the artifact check.
  - Mode `p` and part `p` (checks 26+), in this order: `TIME p-fresh` begins at `dc down -v`; `ipm_precondition`; no Node; unpack and copy; the repository; H0; `run p-first USER 'zpm "install ocutalon"'` with `stops_with_next_command` and the snapshot; `run p-second OCUTALON 'zpm "install ocutalon"'` with `check_run_ok` and `check_signin`; H1; `run p-uninstall OCUTALON 'zpm "uninstall ocutalon"'`; H2 and the snapshot comparison.
  - The header, the checks and the modes paragraph. The registry host is never named.
- [ ] `release/release.sh`: `step_ipmcheck`, `ipmcheck_section` and the shared export helper. STEPS and the header. This covers the matrix rows "Gate passes", "Gate fails", "Gate busy", "Gate refusals" and "Large artifact".
- [ ] `release/notes.sh`: `notes_ipm` and its place in `notes_draft`. The header's draft order. The slot text: "Not run yet. After this version is published to the package registry, the README's two commands are run once against the registry on a clean build 154 instance, and the result is recorded here."
- [ ] `release/checklist.sh`: `registry_row` (`later` or `confirmed`, through `ck_confirmed_date`) and its header paragraph. The text: "After this version was published to the package registry, the README's two commands ran once against the registry on a clean build 154 instance and gave the same working OcuTalon; the result is in the release notes, and docs/install-ipm.md shows that run's output."
- [ ] `docs/install-ipm.md`, in this order:
  - **The intro.**
  - **`## What you need`:** IPM 0.10.10 in %SYS and enabled for USER, and, for the registry, an instance that can reach the community package registry.
  - **`## Install from the package registry`:**
    - in %SYS, `zpm "enable -community"` with the measured output (Design Notes), and one sentence: "The command first deletes the repositories configured in %SYS (`repo -delete-all` in its output), then adds the community registry";
    - the first command `zpm "install ocutalon"` in USER, with U-231's paragraph and the refusal line (once in the file) and the `p-first` output;
    - the U-232 sentence, verbatim: "OCUTALON shares the repositories of the namespace where you ran the first command, so a repository added or removed in either namespace changes both.";
    - `zn "OCUTALON"` plus the same command, with the `p-second` output and the STEP and U-176 paragraphs;
    - one line saying that, until the package is published, these outputs come from the same package installed from a local IPM repository.
  - **`## Install from the package folder (for developers)`:** the Node.js build, and `Open an IRIS terminal in USER and load the package` with both existing output blocks. It refers to the namespace advice above rather than repeating the refusal line.
  - **Then, unchanged:** `iris merge`, demo mode, the model key and the README account.
  - Real output only, with ANSI codes and the `Node:` banner removed.
- [ ] `docs/security-overview.md`, a Data bullet: "On an IPM install, OCUTALON also maps IPM's repository definitions (the globals `^IPM.Repo.Definition*`) from the namespace where the first install command ran, as they are, so the two namespaces share one list of repositories; uninstalling OcuTalon removes only that mapping." This is U-232 condition 3, a ruled cross-epic edit: list it under `footprint_extensions:`.
- [ ] Tests:
  - `test-release-sequence.sh` `t_ipmcheck`: pass, fail, busy, refusals, the artifact path and the lock folder handed to the stub, `## FR-57 job`, no push question on a fail, and WARN over 5,000,000 bytes (the docker shim's artifact padded). Also the existing pins and `to_step`.
  - `test-release-checklist.sh` `t_registry_row`: absent, malformed, valid, and a result that stays pass or fail.
  - `test-release-notes.sh`: the subsections, and the record without the sections.
  - `test-cpf.sh`: rules 8, 9 and 12, each first on samples. Rule 12: the registry `## ` section comes before the developers' section; `zpm "enable -community"` comes before the first `zpm "install ocutalon"`; the U-232 sentence; `RUNNING command: "enable -map -repos -globally"` inside a code block; no `Node.js` before the developers' heading.
- [ ] DW-576: measured at plan (see Design Notes). The implement stage runs `--live ipm` once after the `release.sh` change (the new STEPS on the live path). After the commit, the lead's smoke runs it once more, so that the repository mapping rides in the live candidate (the live seed is `git archive HEAD`).

**Acceptance Criteria:**
- Given a candidate from 1.0.0 on, when `release.sh next` reaches `ipmcheck`, then it runs the FR-57 job's command on the candidate with its artifact and stops the release before `push` unless that run passes. This is the integration AC: the consumer is the release sequence, and the effect is no `NEXT push`, plus the record. The matrix rows "Gate passes" to "Large artifact" hold in `test-release-sequence.sh` `ipmcheck`.
- Given the author has published 1.0.0, when the README's two commands run once against the registry on a clean build 154 instance, then the result goes into the notes' `### Registry install` slot and the checklist row `registry-install` reads `confirmed` only on the author's own line. Until then it reads `later` and blocks nothing. This is a hand gate, not CI.
- Given `docs/install-ipm.md`, when a judge reads it, then it opens with the registry install: the measured `zpm "enable -community"` line and its output, then `zpm "install ocutalon"` with the two-step message. The load-from-folder path comes second. U-231's advice holds, and the U-232 sentence is present. `test-cpf.sh` rules 9, 11 and 12 pass.
- Given the exact artifact (`OCUTALON_IPM_ARTIFACT`, or the one packaged in CI) and a clean build 154 throwaway with no Node.js, when it is installed through a local filesystem repository with `zpm "install ocutalon"` twice, then the row "Repository install" holds, `ARTIFACT ... bytes` is printed and the notes record the size. This is the integration AC for the mapping: IPM's install in OCUTALON reads the mapped definitions and installs.
- Given an install from the repository, when OcuTalon is uninstalled, then the row "Uninstall keeps the definitions" holds (U-232 condition 1). The job runs part `p` with no argument, and `bash release/ipm-install.sh p` passes locally.

## Spec Change Log

## Review Triage Log

## Design Notes

### Lead rulings (2026-11-03)
1. **Split (orchestrator, decide).** This story covers:
   - part `p`: the local-repository install of the exact release artifact, with no Node.js;
   - the repository mapping (ruling 3);
   - the `ipmcheck` release step, which is the FR-57-passed check that Story 11.14 can call;
   - the release notes (the artifact's size, the registry-install slot);
   - the checklist row;
   - the registry-first guide rewrite;
   - DW-576.
2. **Dispatch pre-rulings (decide).**
   - **(a) The registry install.** This run never publishes. It delivers:
     - the procedure in the guide's registry section, measured up to the point that needs the published package;
     - a checklist hand row in Story 11.4's style, which the author marks after publishing;
     - a slot in the release notes for the result.
     
     The author's run is that hand gate, not CI. This plan found no test that only a published package can pass.
   - **(b) The release gate.** It hooks into Story 11.5's `release.sh` steps, beside Epic 14's `overview`. `ipmcheck` comes after `ipm`, because the artifact exists only after `ipm`, and before `push`. Story 11.14's sequence is not merged, so the check is a step that 11.14 can call, as Epic 14 did with `release/security-overview.sh`.
3. **U-232 (veto, kept with conditions by the owner's delegate, answer 2026-11-03T03:57:20Z#696).** The owner's words: "Keep (a): map IPM's repository definitions into OCUTALON as they are, never copied or printed, and the README keeps its two commands. I checked the exposure: no built-in tool reads globals or runs SQL (the generated tool table), so the model cannot reach those definitions, and the production's code already runs with %All. Three conditions. (1) Removing or uninstalling OcuTalon removes the mapping only. It never kills or edits the first namespace's repository data, and a test asserts that the definitions are unchanged after uninstall. (2) The guide says in plain words that OCUTALON shares the first namespace's repositories, so a repository added or removed in either namespace changes both. (3) If the security overview or its generated lists describe OCUTALON's mappings, this mapping is listed there." What this plan does with them:
   - **The mapping form, measured.** IPM's own `enable -map -repos -ns OCUTALON -q` skips OCUTALON, so the equivalent global mapping is used.
   - **Condition (3).** The overview's hand-written Data section describes OCUTALON's global mappings (:150). The bullet goes there, and nothing is regenerated, because no generated list describes mappings.
   - **The spine row.** The proposed "IPM early step" text is below; the lead writes it.
4. **U-231 is in force.** The first command runs in USER, and the guide quotes IPM's refusal with "run it in USER instead". `test-cpf.sh` rules 9-11 stay green (rule 9 is adjusted for the guide's second Configure block).
5. **Orchestrator notes.**
   - **(a) The checklist.** This story's checklist row is a self-contained append. It edits no existing row and does not touch `CK_AUTHOR_IDS`, and the existing pinned counts are unchanged. README.md is not touched.
   - **(b) The merge file.** `docker/merge.cpf` is unchanged, and no criterion needs it.
6. **Size and schedule.** Both stories ship before rc1. The size estimate is below; over about 4 h is the lead's stop.
7. **The FR-57 job.** It ran 21.8 min on `f2d8faba`. Adding part `p` must keep it under 30 min projected (see "CI budget"). The rest stays: no new job, timeout, rename or matrix change, and fork pull requests never run it on the IRIS runner.
8. **DW-576.** This is the live `--live ipm` run on a candidate carrying Epic 15's `module.xml`, measured and recorded below.

### Measured at plan (2026-11-03, lane-D throwaways `e15s4plan`, the build 154 IRIS for Health base image, IPM 0.10.10, with network; both removed)
- **Run 1: IPM loaded in %SYS only, then `zpm "enable -community"`.**
  - IPM maps `%IPM` into every namespace.
  - It printed "Skipping repository mapping of USER - IPM not mapped from source namespace", so USER got no repositories: `zpm "install ocutalon"` in USER gave `ERROR! No repositories are configured and enabled in this namespace.`
  - So the guide keeps the precondition "IPM 0.10.10 in %SYS and enabled for USER".
- **Run 2, the guide's precondition: `zpm "enable -map -ns USER"` in %SYS, then `zpm "enable -community"` in %SYS.**
  - It printed "Mapping IPM repository in %SYS equivalently to USER". USER's `IPM.Repo.Definition{D,I,S}` then map to IRISSYS.
  - `zpm "install ocutalon"` in USER gave `ERROR! 'ocutalon' not found in any repository.`: the registry answers, and the package is not published yet. This is the point that needs the published package.
  - The output, with ANSI codes removed, is in the scratch file `e15s4plan/out2/enable-community.raw`, under the session scratchpad. Its lines run from `Version of IPM in current namespace:` to `Command "enable -map -repos -globally" finished successfull`. It includes `WARNING: Using -password via the CLI is insecure. ...`, two `registry` blocks (`Available? Yes`) and the line `https://pm.community.intersystems.com - 1.0.0`.
  - Task 0 re-measures it on its own throwaway with the same precondition, and the guide shows that run's output.
- **The mapping forms, after `iris merge` of `src/cpf/ocutalon.cpf` and `enable -map -ns OCUTALON -q` from USER** (what MapAndStop's first call does):
  - `zpm "enable -map -repos -ns OCUTALON"` from USER printed "Skipping repository mapping of OCUTALON - IPM not mapped from source namespace", and the second command still found no repository.
  - `MapGlobalEquivalently(g,"USER","OCUTALON")` for D, S and I returned OK. OCUTALON then maps the three to IRISSYS, as USER does. OCUTALON sees USER's 3 definition nodes, and `zpm "install ocutalon"` in OCUTALON gave `'ocutalon' not found in any repository` (the registry is visible there). A repeat call is OK and changes nothing.
  - `unmap -repos-only -ns OCUTALON -q` from OCUTALON returned OK. It removed exactly OCUTALON's three mappings. USER's mappings were unchanged, the nodes in %SYS and USER were still 3, and OCUTALON then sees 0.
- **DW-576.** It ran on HEAD `8d6ce22d`, whose `module.xml`, last changed at `297ad6f4`, is the two-run MapAndStop path. The command was `bash docker/tests/test-release-sequence.sh --live ipm` with the lane-D variables:
  - result PASS, exit 0, 194 s wall (the ipm step 117 s);
  - the ipm log shows `[OCUTALON|ocutalon] Activate SUCCESS`, and the record says "in namespace OCUTALON", so the two-run path ran live through `step_ipm`;
  - the artifact was 4,940,070 bytes, with 19 bundle files and `ocutalon 1.0.0` listed by the filesystem repository; no container was left behind.
  - Note for the lead: the artifact is 98.8% of the 5,000,000-byte threshold, so a little page growth crosses it, and then the WARN line fires.

### Decided in-stage
1. **The mapping goes through `MapGlobalEquivalently`, and only outside OCUTALON.** It uses IPM's own skip rule: skip when OCUTALON already sees `^IPM.Repo.DefinitionD` data. A second run in OCUTALON, the Docker path and the merge path add no repository mapping, so their snapshots and tests are unchanged.
2. **How uninstall removes the mapping.** It runs IPM's own `unmap -repos-only -ns OCUTALON -q` from an Unconfigure Invoke. OCUTALON is OcuTalon's namespace, so a repository mapping that an admin made there is removed too. It never touches data.
3. **The artifact when none is given.** It is packaged from path A's installed module with `step_ipm`'s command (`zpm "package ocutalon -only"`), iteration 1's decision. The size threshold is 5,000,000 bytes. `ipmcheck` prints a WARN and does not fail.
4. **The `ipmcheck` settings.** `ipmcheck` sets `OCUTALON_LIVE_DEADLINE=1980`, the job's value, unless the caller set one. Its run tag is `<caller tag->ipmchk-<pid>`, as `security-overview.sh` does. It always ends with `ci/iris.sh teardown`.
5. **The guide keeps both output pairs.** The registry section shows the local-repository install's real output, and the developers' section keeps its load-from-folder output. Rule 9 therefore checks each Configure block.
6. **The guide's sentence about `enable -community`.** It states only what the measured output shows (`repo -delete-all`), and it shows IPM's own WARNING line verbatim, without comment.
7. **The env-set branch of part `p` is proved by hand.** It runs once with a hand-made artifact (`tar -czf ... -C src .` after `ci/iris.sh build`, which has the same layout). The release's own artifact gets its live proof at the author's release run (`ipmcheck`).

### Proposed spine row (the lead writes it; a stage never edits the spine)
"IPM early step" becomes: ... "Configuration such a step must keep when the run stops is made with transactions suspended (`$SYSTEM.Process.TransactionsSuspended(1)`), restoring the previous state on every path. That configuration is the IPM mapping into OCUTALON and, outside OCUTALON, the mapping of IPM's repository definitions `^IPM.Repo.Definition{D,S,I}` into OCUTALON from the database where they resolve in the run namespace (`%IPM.Utils.Build.MapGlobalEquivalently`; IPM's own `enable -map -repos` skips a namespace whose IPM is mapped from another namespace, measured), so the second command finds the first namespace's repositories. The definitions are mapped as they are: never copied, created, edited or printed. The package's Unconfigure Invoke (`UnmapRepos`, IPM's `unmap -repos-only -ns OCUTALON`) removes only that mapping on uninstall (U-232)." ... The rest of the row is unchanged. Also for the lead: AD-23's bullet "A second early step maps IPM into OCUTALON" now does slightly more. This plan reads that as a wording note, not a contradiction.

### Governing ADs (Rule 6)
- **AD-2:** one package, 0 dependencies.
- **AD-3:** OCUTALON's own mappings are unchanged, and the repository mapping sits outside the CPF file, like `%IPM`'s.
- **AD-22:** throwaways only and the CI mock; fork pull requests never run on the runner.
- **AD-23:** the two-run IPM install, the second early step, the release checks inside the built artifact.
- **AD-29:** Lane A owns `release/` and the installer.

No AC contradicts an AD's Rule. AD-23's sentence "first in any namespace" is known to the orchestrator, and this story implements U-231.

### Ledger inbox (Rule 17)
- **DW-576** is addressed: measured at plan (PASS, above), plus the implement-stage run and the lead's post-commit smoke (Tasks).

### Integration ACs, Consumed-by and Consumes (Rules 1 and 2)
- **Integration ACs.**
  - AC 1: the release sequence consumes `ipm-install.sh`'s exit, its first FAIL line and the ipm step's artifact, and stops before `push`. It is tested hermetically with a stub unit, as Epic 14's overview step was. The full unit takes about 14 to 25 min, beyond one 10-minute call.
  - AC 4: IPM's install in OCUTALON consumes the mapped definitions, on a real instance.
- **Consumed-by:**
  - Story 11.14 calls `step_ipmcheck`, or reads the `ipm-install` job of its full CI run;
  - Story 31.3 builds the README's IPM section from the guide, registry first;
  - Epic 38's 1.0.0 checks and the author's release run use this step.
- **Consumes:**
  - Story 11.17's `step_ipm` and the lib-release IPM helpers;
  - Story 11.5's `release.sh`, Story 11.4's checklist and Story 11.13's notes;
  - Stories 15.1-15.3's `ipm-install.sh`;
  - Story 14.1's `step_overview` pattern.

### Extend, don't copy (Rule 2)
- `step_ipmcheck` shares the export and lock helper with `step_overview`.
- Part `p` reuses `run`, `take_snapshot`, `stops_with_next_command`, `check_run_ok`, the new `ipm_precondition` and `check_signin` (factored out of path A and `check_web`), and lib-release's `ipm_unpack` and `ipm_artifact_check`.
- The packaging follows `step_ipm`'s command, inside `ipm-install.sh`'s own stack. It is a copy of about 5 lines, kept because `step_ipm` packs in a container of its own and its subshell helpers write the release state.
- `registry_row` reuses `ck_confirmed_date` and `ck_add`.
- `notes_ipm` reuses `notes_section`.

### Footprint, for the lead
- **Edited:** Epic 15's files (`src/module.xml`, `release/**`, `docker/tests/**`, `docs/install-ipm.md`).
- **footprint_extensions:**
  - `src/preload/cls/OcuTalon/Install/Ipm.cls` (Epic 15's own file from Story 15.1, outside the declared paths, uncontended);
  - `docs/security-overview.md` (one bullet in its Data section; ruled by U-232 condition 3; Epic 13's sentence is untouched).
- **Unchanged:** `lane-a.yml`, `ci/units.sh`, `docker/merge.cpf`, `README.md` and the spine.

### Size estimate
About 3.75 h from implement to commit:
- **Implement, about 2.25 h:**
  - MapAndStop, UnmapRepos and the manifest, 15 min;
  - part `p` and its helpers, 50 min;
  - `release.sh` and its tests, 35 min;
  - the notes, the checklist and their tests, 25 min;
  - the guide, the overview and `test-cpf.sh`, 25 min;
  - live runs: `p` about 6 min, two or three times; `a` once (check 3); `r` and `b` once each (the mapping lines; path B's view);
  - two live mutations (`p`, about 6 min each) and hermetic ones (seconds).
- **QA and review, about 1 h.**
- **Smoke and CI, about 0.5 h**, including the `ipm-install` job at about 28 min and the lead's `--live ipm`.

What drives it: part `p`'s live loops, and `test-release-sequence.sh`'s pins after STEPS changes.

### CI budget (the 35-minute job)
- **Measured:** 21.8 min on `f2d8faba`.
- **Added, by inference:**
  - packaging about 10 s;
  - part `p` on a fresh stack: down and up about 55 s, IPM about 16 s, the runs about 50 s, the checks about 30 s, the uninstall and the hashes about 25 s;
  - about 185 s locally, x2.2 = about 6.8 min, so about 28.6 min of 35.
- **Rule for the implement stage:** projected = 21.8 + (`TIME package` + `TIME p-fresh`) x 2.2 / 60.
  - Over 30 min: stop with `## Clarification Needed` and the numbers. A second fork-guarded job is the lead's or the orchestrator's decision.
  - Local `p` over 540 s is also a stop.

## Verification

Run everything from the epic-15 worktree root, after verifying `git rev-parse --show-toplevel`. Run in the foreground, one call each, with `timeout: 600000`. `[L]` means the prefix `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=15 stage=implement' OCUTALON_RUN_TAG=e15s4i`. Fresh throwaways only, and never a slot. End with `[L] bash ci/iris.sh teardown`, also after a failure.

**Commands:**
- `bash docker/tests/test-cpf.sh` (loop) -- expected: every PASS (rules 8, 9, 11 and 12 included).
- `bash docker/tests/test-release-sequence.sh` (loop, about 170 s) -- expected: `PASS all rules` (`ipmcheck` included).
- `bash docker/tests/test-release-checklist.sh` (loop) -- expected: every PASS (`registry-row` included).
- `bash docker/tests/test-release-notes.sh` (loop) -- expected: every PASS.
- `bash docker/tests/test-boundaries.sh` and `bash docker/tests/test-pinned-sources.sh` (loop) -- expected: exit 0.
- `[L] bash ci/iris.sh build` (once per pass that runs IRIS) -- expected: the bundle is built.
- `[L] bash release/ipm-install.sh p` (loop, about 330 s; over 540 s is a stop) -- expected: `all checks passed`, with the `ARTIFACT`, `TIME package` and `TIME p-fresh` lines.
- `[L] bash release/ipm-install.sh a` (once, about 170 s) -- expected: all checks passed, check 3 with the repository lines.
- `[L] bash release/ipm-install.sh r` (once, about 300 s) and `[L] bash release/ipm-install.sh b` (once, about 400 s) -- expected: all checks passed.
- `[L] OCUTALON_IPM_ARTIFACT=<scratch>/ocutalon-0.1.0.tgz bash release/ipm-install.sh p` (once; the artifact is `tar -czf` of the built `src`, Decided in-stage 7) -- expected: all checks passed, and the second run is skipped.
- `[L] bash docker/tests/test-release-sequence.sh --live ipm` (once, about 200 s) -- expected: `PASS live`, and the ipm log shows `[OCUTALON|ocutalon] Activate SUCCESS`.
- `[L] bash ci/iris.sh live install-start` (once) -- expected: pass (the Docker path is unaffected by the mapping).
- `[L] bash ci/iris.sh teardown` (once, last).
- The full no-argument run is about 16 min locally, so CI's `ipm-install` job is its first full run. Record its minutes against the 28.6 projection.

**Planned mutations (Rule 19, one per AC).** For each one: back up into the stage's scratch folder, apply, run the one call, see red, restore, and confirm `git status --short` and `git diff --stat` are unchanged.

| AC | Mutation | Test that goes red |
|---|---|---|
| 1 gate | `step_ipmcheck` treats exit 1 like 0 | `test-release-sequence.sh ipmcheck` (fail case: `PASS ipmcheck`, `NEXT push`) |
| 2 registry hand gate | `registry_row` reads `confirmed` with no line | `test-release-checklist.sh registry-row` |
| 3 guide | the developers' section moved above the registry section | `test-cpf.sh` rule 12 |
| 4 repository install | `MapAndStop`'s repository mapping removed | `ipm-install.sh p` (the second command: `No repositories are configured`), and check 3 |
| 5 uninstall | `UnmapRepos` also runs `Kill ^IPM.Repo.DefinitionI` (in OCUTALON, which resolves to USER's database) before unmapping | `ipm-install.sh p` (the hash `differs`) |

**Shared surfaces:**
- `release.sh`'s STEPS and `to_step` (and every `NEXT push` or `next push` pin after ipm);
- the checklist's rows and result (the counts pinned in `test-release-checklist.sh` call `author_rows` alone and stay as they are);
- the notes draft's sections (`test-release-notes.sh`);
- the guide's structure (`test-cpf.sh` rules 9, 11 and 12, and `test-boundaries.sh`);
- MapAndStop's expected mappings (check 3, path B's view, `same_config`);
- `ipm-install.sh`'s modes and checks (lane-a's job, `test-cpf.sh` rules 6 and 7).

Standing criterion: every test added or changed passes on a fresh environment, in either order. Each `ipm-install.sh` part starts its own fresh stack, and each hermetic case builds its own repository.

**Manual checks:**
- The guide's registry outputs match the `p-first` and `p-second` blocks of a passing `p` run, and the `enable -community` block matches Task 0's run, apart from times, ANSI codes and the banner.
- No guide or overview sentence claims more than the measured behaviour and the ruled sentences.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
