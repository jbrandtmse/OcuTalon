---
title: 'Story 15.4: Every release proves the IPM package, and the guide opens with the registry install'
type: 'feature'
created: '2026-11-02'
status: 'done'
baseline_revision: 'c93e62bf678962afb301739e50ac5de770f45e72'
baseline_commit: 'c93e62bf678962afb301739e50ac5de770f45e72'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      The Unconfigure Invoke may remove OCUTALON's repository mapping during an IPM upgrade or same-version reinstall of ocutalon, and nothing maps it again.
    evidence: |-
      MapAndStop maps the repository definitions only outside OCUTALON, and UnmapRepos runs at Unconfigure, Before. If IPM runs Unconfigure of the installed version when a newer ocutalon is installed over it in OCUTALON, the three IPM.Repo.Definition mappings of OCUTALON are gone afterwards. Not measured; what would settle it: install ocutalon twice in OCUTALON from a local repository with a version bump, then read OCUTALON's three IPM.Repo.Definition mappings.
    location: >-
      src/preload/cls/OcuTalon/Install/Ipm.cls:UnmapRepos, src/module.xml:18
    severity: medium (unverified)
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
- [x] Task 0 (the first `p` loop is the measurement): (a) does `module.xml` load with the Unconfigure Invoke, and does `zpm "uninstall ocutalon"` in OCUTALON run `UnmapRepos`? Record what the uninstall prints and how it ends. If the Invoke is rejected or never runs, HALT with `intent gap` (the recommendation: a module lifecycle class, or a documented `zpm "unmap -repos-only -ns OCUTALON"` line). (b) Copy the guide's registry-section output blocks from a passing `p` run's `p-first` and `p-second` OUTPUT blocks. (c) If IPM's own install changes USER's definitions between the hash before the first command (H0) and the hash before the uninstall (H1), assert only H1 = H2 and record that.
- [x] `src/preload/cls/OcuTalon/Install/Ipm.cls`, `MapAndStop`:
  - Outside OCUTALON only, and inside the existing suspension: unless OCUTALON already sees `$Data(^IPM.Repo.DefinitionD)\2` (IPM's own skip rule), call `MapGlobalEquivalently` from `$Namespace` to OCUTALON for each of D, S and I. The first error is returned unchanged.
  - `UnmapRepos()`: `%IPM.Main.Shell("unmap -repos-only -ns OCUTALON -q")` with transactions suspended and restored, returning its status. It kills and sets no global.
  - This covers U-232 and the matrix rows "First run maps the definitions" and "Uninstall keeps the definitions".
- [x] `src/module.xml`: the Unconfigure Invoke, after the Configure Invoke, on a line of its own.
- [x] `release/ipm-install.sh`:
  - Check 3's three lines with `repo_db`, plus "OCUTALON_DATA holds no `^IPM.Repo.Definition*` node".
  - Path B's view leaves out the repository lines.
  - The helpers `ipm_precondition` and `check_signin`.
  - Packaging (`TIME package`), with the artifact check.
  - Mode `p` and part `p` (checks 26+), in this order: `TIME p-fresh` begins at `dc down -v`; `ipm_precondition`; no Node; unpack and copy; the repository; H0; `run p-first USER 'zpm "install ocutalon"'` with `stops_with_next_command` and the snapshot; `run p-second OCUTALON 'zpm "install ocutalon"'` with `check_run_ok` and `check_signin`; H1; `run p-uninstall OCUTALON 'zpm "uninstall ocutalon"'`; H2 and the snapshot comparison.
  - The header, the checks and the modes paragraph. The registry host is never named.
- [x] `release/release.sh`: `step_ipmcheck`, `ipmcheck_section` and the shared export helper. STEPS and the header. This covers the matrix rows "Gate passes", "Gate fails", "Gate busy", "Gate refusals" and "Large artifact".
- [x] `release/notes.sh`: `notes_ipm` and its place in `notes_draft`. The header's draft order. The slot text: "Not run yet. After this version is published to the package registry, the README's two commands are run once against the registry on a clean build 154 instance, and the result is recorded here."
- [x] `release/checklist.sh`: `registry_row` (`later` or `confirmed`, through `ck_confirmed_date`) and its header paragraph. The text: "After this version was published to the package registry, the README's two commands ran once against the registry on a clean build 154 instance and gave the same working OcuTalon; the result is in the release notes, and docs/install-ipm.md shows that run's output."
- [x] `docs/install-ipm.md`, in this order:
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
- [x] `docs/security-overview.md`, a Data bullet: "On an IPM install, OCUTALON also maps IPM's repository definitions (the globals `^IPM.Repo.Definition*`) from the namespace where the first install command ran, as they are, so the two namespaces share one list of repositories; uninstalling OcuTalon removes only that mapping." This is U-232 condition 3, a ruled cross-epic edit: list it under `footprint_extensions:`.
- [x] Tests:
  - `test-release-sequence.sh` `t_ipmcheck`: pass, fail, busy, refusals, the artifact path and the lock folder handed to the stub, `## FR-57 job`, no push question on a fail, and WARN over 5,000,000 bytes (the docker shim's artifact padded). Also the existing pins and `to_step`.
  - `test-release-checklist.sh` `t_registry_row`: absent, malformed, valid, and a result that stays pass or fail.
  - `test-release-notes.sh`: the subsections, and the record without the sections.
  - `test-cpf.sh`: rules 8, 9 and 12, each first on samples. Rule 12: the registry `## ` section comes before the developers' section; `zpm "enable -community"` comes before the first `zpm "install ocutalon"`; the U-232 sentence; `RUNNING command: "enable -map -repos -globally"` inside a code block; no `Node.js` before the developers' heading.
- [x] DW-576: measured at plan (see Design Notes). The implement stage runs `--live ipm` once after the `release.sh` change (the new STEPS on the live path). After the commit, the lead's smoke runs it once more, so that the repository mapping rides in the live candidate (the live seed is `git archive HEAD`).

**Acceptance Criteria:**
- Given a candidate from 1.0.0 on, when `release.sh next` reaches `ipmcheck`, then it runs the FR-57 job's command on the candidate with its artifact and stops the release before `push` unless that run passes. This is the integration AC: the consumer is the release sequence, and the effect is no `NEXT push`, plus the record. The matrix rows "Gate passes" to "Large artifact" hold in `test-release-sequence.sh` `ipmcheck`.
- Given the author has published 1.0.0, when the README's two commands run once against the registry on a clean build 154 instance, then the result goes into the notes' `### Registry install` slot and the checklist row `registry-install` reads `confirmed` only on the author's own line. Until then it reads `later` and blocks nothing. This is a hand gate, not CI.
- Given `docs/install-ipm.md`, when a judge reads it, then it opens with the registry install: the measured `zpm "enable -community"` line and its output, then `zpm "install ocutalon"` with the two-step message. The load-from-folder path comes second. U-231's advice holds, and the U-232 sentence is present. `test-cpf.sh` rules 9, 11 and 12 pass.
- Given the exact artifact (`OCUTALON_IPM_ARTIFACT`, or the one packaged in CI) and a clean build 154 throwaway with no Node.js, when it is installed through a local filesystem repository with `zpm "install ocutalon"` twice, then the row "Repository install" holds, `ARTIFACT ... bytes` is printed and the notes record the size. This is the integration AC for the mapping: IPM's install in OCUTALON reads the mapped definitions and installs.
- Given an install from the repository, when OcuTalon is uninstalled, then the row "Uninstall keeps the definitions" holds (U-232 condition 1). The job runs part `p` with no argument, and `bash release/ipm-install.sh p` passes locally.

### Review Findings

Code review 2026-11-03 (four layers, full-opus). 27 entries: 8 patch (applied), 2 defer (ledgered `wontfix-accepted`), DW-621 resolved by measurement, 16 rejected. No high, no open medium.

- [x] [Review][Resolved] DW-621: the Unconfigure Invoke might drop OCUTALON's repository mapping on an upgrade or same-version reinstall. Measured on lane-D throwaway `e15s4crm` (part p's setup, then three more installs from the local repository in OCUTALON). After a same-version `zpm "install ocutalon"`, a `-force` install, and a 0.1.0 -> 0.1.1 bump, the three `IPM.Repo.Definition` mappings were all still there. None of the runs printed a Clean or Unconfigure phase (only Reload, Configure and Activate). The definitions hash was unchanged (`same|5`), and a fourth install from the repository in OCUTALON still found the package. Ledger: `resolved-by` this story.
- [x] [Review][Patch] Rule 9 passed a guide with a `Configure SUCCESS` line but no `Configure START`, checking zero STEP lines. Now a SUCCESS line with no open block fails, and there is a `no-start` sample [docker/tests/test-cpf.sh:install_doc_ok]
- [x] [Review][Patch] Rule 14's print check covered only echo/printf/cat/tee, so `pass`, `fail` and `die` could leak a hash. Widened, with a `pass-arg` sample [docker/tests/test-cpf.sh:defs_private]
- [x] [Review][Patch] `uninstall_checks` printed a stale `snap.diff` from `same_config` when the count check or the kept-mapping check failed. It now clears the file first and prints any kept repository mapping lines [release/ipm-install.sh:uninstall_checks]
- [x] [Review][Patch] A failing `ipmcheck` with an artifact over 5,000,000 bytes printed no WARN line (matrix row "Large artifact"). The WARN now comes before the failure branch; new `t_ipmcheck` case `large fail` [release/release.sh:step_ipmcheck]
- [x] [Review][Patch] The record's Size note said "reported to the Contest Planner", an action that never happened. It now reads `Size: <n> bytes, over 5000000` [release/release.sh:ipmcheck_section]
- [x] [Review][Patch] The FR-57 section's `First failure:` skipped `step_fail`'s path scrubbing. It now uses `STEP_DETAIL` [release/release.sh:step_ipmcheck]
- [x] [Review][Patch] A relative `OCUTALON_RELEASE_STATE` produced an artifact path that pointed at no file once the unit ran inside the export. The path is now made absolute [release/release.sh:step_ipmcheck]
- [x] [Review][Patch] Nothing pinned AC 5's "the job runs part `p` with no argument", so `ipmcheck` could certify an exit 0 that never installed the artifact. New rule 16 in `test-cpf.sh`, with samples. The exit-code contract stays as specified [docker/tests/test-cpf.sh, rule 16]
- [x] [Review][Defer] `artifact_prepare`'s ARTIFACT line and its problem branch have no hermetic pin [release/ipm-install.sh:artifact_prepare] -- deferred: DW-622 `wontfix-accepted`, reopen_if an ipm-install or ipmcheck log passes without an ARTIFACT line or with an artifact that `ipm_artifact_check` rejects.
- [x] [Review][Defer] Part p enables IPM with `enable -map -ns USER`, while the guide's `enable -community` maps the definitions from IRISSYS. The IRISSYS-mapped case is measured by hand only (plan) [release/ipm-install.sh:part_p] -- deferred: DW-623 `wontfix-accepted`, reopen_if the registry-install hand gate's second command in OCUTALON finds no repository.

Rejected:
- [medium claim] Part p's `BuildCache` step is not in the matrix or the guide. By design. The guide gives no local-repository procedure, only the one "until published" line, so no reader-facing step is missing. Read on throwaway `e15s4crs`: `%IPM.Repo.Remote.Definition` and `%IPM.Repo.Remote.PackageService` reference no cache; only the Filesystem classes use `%IPM.Repo.Filesystem.Cache`. The fix would edit the spec.
- `false` The overview bullet over-claims, because `UnmapRepos` also removes an admin-made mapping. The bullet is the ruled text, and Decided in-stage 2 covers this: it is the same repository-definition mapping either way.
- `low` The shared-repositories sentence understates its reach after `enable -community`. It is U-232's verbatim ruled text and true as written; changing it is a veto item.
- `low` The checklist and notes texts name "the README's two commands" before the README has them. This is the spec's verbatim text: Story 31.3 builds that README section, and the row is a later hand gate.
- `low` Mode `p` with an artifact starts a stack it never uses. Hand runs only, and the fix restructures the script.
- `false` Packaging in mode `all` before path A's later checks was never run. lane-a run 41605812449 on `87d34be0`: job `ipm-install` passed the full no-argument run in 26 min 19 s, with `TIME p-fresh 263s`.
- `low` `ipmcheck` is silent for the whole run. `release.sh`'s output contract is one PASS, FAIL or WAIT line per step, and `image` is silent too; a new line type is more than a direct correction.
- `low` `UnmapIPM` skips OCUTALON when IPM is installed natively there. Theoretical: the first run creates OCUTALON and maps IPM in from USER.
- `low` After an uninstall, the same command in OCUTALON finds no repositories. By design under U-232 condition 1: the guide's first command in USER maps them again, and IPM's own error names the cause.
- `false` An `UnmapRepos` error stops the uninstall. Failing loudly is correct; swallowing the error would leave the mapping in place silently.
- `low` `push` does not re-check `ipmcheck_result`. Theoretical: no release state from before the new STEPS exists, and `push` re-checks no earlier step.
- `low` The guide shows `Reload START (/tmp/ocutalon-repo/...)`. That is IPM's own output, which Task 0 (b) requires verbatim; it is a container path, not a local machine path.
- `low` The developers' blocks keep the `Node:` banner. The spec keeps both existing blocks, and their text claims only that colour codes were removed.
- `low` The intro says "two commands" while the registry route also needs `enable -community`. "Two commands" is the spec's term for the install itself; pointing IPM at the registry is a setup step in its own subsection.
- `low` The `uc_expect_fail "0 nodes"` needle cannot fail. The cases still pin the behaviour, because only the node test can produce their FAIL line.
- `low` `t_ipmcheck` restores `OCUTALON_LOCK_DIR` to `$C/locks`. That is the existing `t_overview` pattern and `newcase`'s own value.

## Spec Change Log

## Review Triage Log

### 2026-11-03 -- Review pass
- verdicts: 26 findings (the layers' 29 reports, merged where one root cause) -- high 0, medium 1, low 19, false 5, maybe-false 1
- findings:
  - `[low]` `[reject]` Blind: `enable -community` has no warning about lost private repositories or the WARNING line -- the guide's sentence and the verbatim output are the spec's and the ruling's text; public text beyond them is a veto item.
  - `[low]` `[reject]` Blind: the registry section's output shows a local path and 0.1.0, and the page says nothing of what uninstall does -- the spec's one disclaimer line covers the source of the outputs; text on uninstall is not in the spec.
  - `[low]` `[reject]` Blind: the shared definitions may hold credentials, and the overview bullet does not say so -- the bullet is the ruled text (U-232 condition 3); the owner checked the exposure; no tool reads globals.
  - `[low]` `[reject]` Blind and Edge: `MapRepos` guards on `DefinitionD` only, so a failure on S or I leaves a half mapping -- the guard is IPM's own skip rule that the spec names; a `MapGlobalEquivalently` error on a mapping it just resolved is theoretical (wontfix-theoretical; the first error is returned and the run stops).
  - `[maybe-false]` `[defer]` Blind and Edge: the new Unconfigure Invoke may remove the mapping on an upgrade or same-version reinstall that runs Unconfigure of the old version, and nothing restores it -- unverified; what would settle it is `zpm "install ocutalon"` twice in OCUTALON from a repository with a version bump, then reading OCUTALON's three `IPM.Repo.Definition` mappings. Recorded in `deferred:`.
  - `[low]` `[reject]` Blind: `step_ipmcheck` deletes the unit's log on a failure -- the first FAIL line is kept in the record and the output, as `step_overview` does; the full log is on the throwaway only for the run.
  - `[low]` `[reject]` Blind: `step_ipmcheck` runs the whole unit in the foreground past the 10-minute cap -- the spec ruled it (deadline 1980, "the full unit takes about 14 to 25 min"); the author's release run is a hand run, and Story 11.14 calls the step.
  - `[false]` `[reject]` Blind and Edge and Gap: `part_p`'s `--wait-timeout "$((deadline - SECONDS))"` can be zero or negative -- paths A and B use the same expression at their `dc up`; in the job the deadline is 1980 s against a measured 21.8 to 25.7 min run, and a negative value makes `dc up` fail loudly.
  - `[low]` `[reject]` Blind: the repository add in part `p` is never checked -- the spec has its output discarded (U-232: no definition fields in any log); a failed add shows as the install's own failure.
  - `[low]` `[patch]` Blind and Edge: rule 9's awk lets an unclosed Configure block followed by a complete one pass -- fixed (`if (on) bad = 1;`) with a `first-unclosed` sample; mutation line written and observed red.
  - `[low]` `[patch]` Blind and Gap: the public notes print the internal id "FR-57 job result" -- label changed to "IPM install check" in `notes_ipm`, in `test-release-notes.sh` and its header.
  - `[false]` `[reject]` Edge: `UnmapRepos` removes an admin's mapping when `MapRepos` skipped -- Decided in-stage 2 states exactly this (OCUTALON is OcuTalon's namespace; data is never touched).
  - `[false]` `[reject]` Edge and Gap: `UnmapRepos` fails when nothing is mapped (merge path, first command in OCUTALON, admin removed it) -- IPM's `UnmapIPM` skips a namespace with no mapping, and `RemoveGlobalMapping` does nothing and returns OK when `Config.MapGlobals` has no such row (read in IPM's source).
  - `[low]` `[reject]` Edge: rule 8's `Phase="Configure"` match misses other spellings of the attribute -- the manifest is written in one style and rules 5, 8, 10 and 13 pin it; the old `/Configure/` test was looser, and no other spelling is reachable.
  - `[low]` `[reject]` Blind and Edge: `notes_ipm` says "not in the record" for a failed section -- a failed `ipmcheck` stops the release before `notes`, so the failed-record case is only a test input; the failed result is printed (test line "a failed job: the result").
  - `[low]` `[reject]` Edge: `ipmcheck` differs from the CI job (no `ci/iris.sh build`, another run tag) -- the candidate commit carries the built web bundle (`ensure_web_bundle`), so no build is needed; the tag follows `security-overview.sh`; Decided in-stage 4.
  - `[false]` `[reject]` Edge: requiring H0 = H2 contradicts Task 0 (c) -- the spec requires H0 = H2 unless Task 0 (c) measures a change, and it measured none (H0 = H1 = H2).
  - `[false]` `[reject]` Gap: the uninstall is tested only on a mapped install -- same claim as the false row above; `RemoveGlobalMapping` is idempotent, so the unmapped case cannot fail in `UnmapRepos`.
  - `[low]` `[patch]` Gap: mutation lines missing for the notes subsections, rule 9's multi-block logic and rule 13 -- three hermetic mutations run (red, restored byte-identical) and their lines written.
  - `[low]` `[reject]` Gap: the `ipm_precondition`/`check_signin`/`derive_dbs` refactor has no mutation line -- the refactor is covered by the `a`, `r`, `b` and `p` runs that call them; no AC pins it alone.
  - `[medium]` `[reject]` Gap and Intent: part `p` pre-builds the filesystem module list in OCUTALON (`BuildCache`), so the bare mapping is not shown to suffice for a filesystem repository -- by design: the cache is not a definition, U-232 covers the definitions only, a remote repository has no such list, and the mapping is still necessary (mutation 4 goes red); recorded under "Found while measuring". The registry run is the author's hand gate.
  - `[low]` `[patch]` Gap: `t_ipmcheck` unsets `OCUTALON_RUN_TAG` and `OCUTALON_LIVE_DEADLINE` for the rest of the file -- saved and restored around the case.
  - `[low]` `[reject]` Gap: the exact call `ipmcheck` makes (mode all with the artifact set) is run nowhere before the release -- Decided in-stage 7: the env branch is proved by hand in `p`, and the release's own live proof is the author's release run.
  - `[low]` `[reject]` Gap: the `ipmcheck busy: no FR-57 section` assertion also passes with no record -- the `snap` equality on the line before it is the real guard.
  - `[low]` `[reject]` Intent: readings 4 to 6 (what "first command" means; the artifact; local repository as proxy) -- descriptive; the diff takes the spec's readings, and the guide says the outputs come from a local repository.
  - `[low]` `[reject]` Intent: the guide contains the registry's definition fields in the `enable -community` output, and rule 8 was tightened -- the output is the ruled guide content (the fields are the registry's public ones, printed by IPM in the guide only); rule 8's change is the spec's plan.

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

### Measured at implement (2026-11-03, lane-D throwaways, build 154 base image, IPM 0.10.10)
- **Task 0 (a), the Unconfigure Invoke.** `module.xml` loads with it, and `zpm "uninstall ocutalon"` in OCUTALON runs `UnmapRepos`: the output is `Clean START`, `Unconfigure START`, `Unconfigure SUCCESS`, eight `WARNING: Skipping mapped resource ...CLS` lines (the mapped public classes), `Clean SUCCESS`, and no `ERROR!` or `FAILURE` line. OCUTALON's three `IPM.Repo.Definition*` mappings are gone afterwards and every other OCUTALON mapping, USER's mappings and the services equal the snapshot taken before the uninstall.
- **Task 0 (c).** The hash of USER's three definition globals is the same before the first command (H0), before the uninstall (H1) and after it (H2): IPM's own install does not change the definitions, so `uninstall_checks` asserts H0 = H1 = H2 (it prints only `same|<nodes>`, 5 nodes).
- **Task 0 (b).** The registry section's `p-first` and `p-second` blocks and the `enable -community` block of the guide are the outputs of passing runs (`zpm "enable -community"` re-measured on its own throwaway with the guide's precondition; lines from `Version of IPM in current namespace:` to `Command "enable -map -repos -globally" finished successfull`).
- **Found while measuring: a filesystem repository's module list is per namespace.** The definitions are mapped, and OCUTALON found the repository by name, but `zpm "install ocutalon"` in OCUTALON gave `ERROR! 'ocutalon' not found in any repository.` because the list of a filesystem repository's modules (`%IPM.Repo.Filesystem.Cache`, the globals `^IPM.Repo.Filesystem.Cache{D,I,S}`) is kept apart from the definition and is empty in OCUTALON. A remote repository (the registry) has no such list. Part `p` therefore builds the module list in OCUTALON before the second command (`BuildCache` of the mapped definition opened by name, which saves nothing new), and asserts again that OCUTALON_DATA holds no `^IPM.Repo.Definition*` node. The mapping itself still carries the proof: without it OCUTALON finds no repository (mutation 4). Nothing in the product maps the cache.
- **The repository database.** On the part `p` stack (IPM enabled for USER with `enable -map -ns USER -q`) the definitions live in USER's own database, so `repo_db` reads `USER`; after the guide's `enable -community` they resolve to IRISSYS. `repo_db` is read by a probe either way.
- **Times (local, one fresh stack per part).** `TIME package` 2 s; `TIME p-fresh` 105 s (first command 33 s, second 41 s, uninstall 0 s); `release/ipm-install.sh p` takes about 4 min in one call (under 540 s). Mode `a` 186 s, `r` 300 s, `b` 404 s (path B and the part p guard), `p` with a hand-made artifact 101 s for `p-fresh`; `--live ipm` PASS in 154 s (the ipm step 95 s); `ci/iris.sh live install-start` passed.
- **CI projection.** 21.8 + (`TIME package` 2 + `TIME p-fresh` 105) x 2.2 / 60 = 25.7 min, under 30 (the job's timeout is 35). The unit's full no-argument run was not run locally (about 16 min); the `ipm-install` job is its first full run.
- **Artifact sizes.** The packaged artifact is 4,940,685 bytes (98.8% of the 5,000,000-byte threshold; the hand-made `tar` of `src` is 5,039,626 and trips the WARN in `ipmcheck`).

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

**Mutations run (Rule 19).** Each was applied to a backup-protected file, the one call was run, it went red, and the file was restored from the backup (`cmp` equal; `git status --short` and `git diff --stat` unchanged).
- mutation: AC 1 gate -- `step_ipmcheck` fails only on exit codes above 1 (exit 1 treated like 0): `bash docker/tests/test-release-sequence.sh ipmcheck` red (`ipmcheck fail: exit: got '0', wanted '1'`, `PASS ipmcheck` and `NEXT push` after the failing unit).
- mutation: AC 2 registry hand gate -- `registry_row` reads `confirmed` with no line (`|| true` on the date lookup): `bash docker/tests/test-release-checklist.sh` red in `registry-row` (no LATER line, no `later` row, a `confirmed` row without a line) and in `base` (its pinned PASS-line count, 19 for 18).
- mutation: AC 3 guide -- the developers' section moved above the registry section in `docs/install-ipm.md`: `bash docker/tests/test-cpf.sh` red in rule 12 (only).
- mutation: AC 4 repository install -- the repository mapping removed from `MapAndStop`: `[L] bash release/ipm-install.sh p` red (check 3's repository lines, the module-list step, and the second command `ERROR! No repositories are configured and enabled in this namespace.`).
- mutation: AC 5 uninstall -- `UnmapRepos` runs `Kill ^IPM.Repo.DefinitionI` in OCUTALON (which resolves to USER's database) before unmapping: `[L] bash release/ipm-install.sh p` red with exactly one failure, `part p uninstall: USER's repository definitions differ` (`differs|3`, the hash not printed).
- mutation: AC 3 guide, rule 9 -- the awk in `install_doc_ok` no longer flags a `Configure START` that follows an unclosed one (`if (on) bad = 1;` removed): `bash docker/tests/test-cpf.sh` red (`rule 9 on samples`, the `first-unclosed` sample); restored.
- mutation: AC 5 uninstall, manifest -- the Unconfigure Invoke line removed from `src/module.xml`: `bash docker/tests/test-cpf.sh` red in rule 13 (only); restored.
- mutation: AC 2 notes slot -- `notes_draft` no longer prints `ipm.md` (`cat "$w/ipm.md"` removed): `bash docker/tests/test-release-notes.sh` red in `base` and `ipm`; restored. The tree was byte-identical (`git diff`) after each of these three.

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

**QA stage (Story 15.4).** Changed file: `docker/tests/test-cpf.sh` (QA), rules 14 and 15 appended; no test file added. The audit of the five lead points found 3, 4 and 5 pinned (`t_ipmcheck`, `t_registry_row`, `t_ipm`), and two gaps closed: U-232 condition 1's "never printed" and its comparison logic had only a live pin (`ipm-install.sh p`), and the ruled Data bullet of `docs/security-overview.md` (U-232 condition 3) had no pin at all.
- (QA) `bash docker/tests/test-cpf.sh` rule 14: `defs_private` (the repository is added with its output discarded, nothing lists repositories, each hash stays in a variable and is never echoed) and the real `uninstall_checks` run on synthetic files with sentinel hashes (equal hashes with nodes pass; a hash changed at the uninstall or since the first command, 0 nodes, no hash, a kept mapping, another change and a FAILURE line fail; no hash is printed).
- (QA) `bash docker/tests/test-cpf.sh` rule 15: the ruled Data bullet is present, on samples and in the real file.
- mutation (QA): AC 5 uninstall -- `uninstall_checks` no longer compares the hash before and after the uninstall (`[ "$2" = "$3" ] &&` removed): `test-cpf.sh` rule 14 on the real function red; restored.
- mutation (QA): no definition printed -- `uninstall_checks`'s `differs|` line also echoes `$3` (the hash): `test-cpf.sh` rule 14 on the real function and rule 14 red; restored.
- mutation (QA): no definition printed -- part `p`'s `zpm "repo -name ocutalon-local ..."` session no longer ends with `> /dev/null 2>&1`: `test-cpf.sh` rule 14 red; restored.
- mutation (QA): U-232 condition 3 -- the Data bullet removed from `docs/security-overview.md`: `test-cpf.sh` rule 15 red; restored. After each, `cmp` against the backup was equal and `git status --short` / `git diff --stat` were unchanged.
- mutation (CR): AC 5 "the job runs part p with no argument" -- the line `if [ "$mode" = all ]; then part_p; fi` deleted from `release/ipm-install.sh`: `test-cpf.sh` rule 16 red (only); restored.
- mutation (CR): AC 3 guide, rule 9 -- `if (!on || count != n)` reverted to `if (on && count != n)`: `test-cpf.sh` rule 9 on samples red (the `no-start` sample); restored.
- mutation (CR): no definition printed -- rule 14's print words narrowed back to `echo|printf|cat|tee`: `test-cpf.sh` rule 14 on samples red (the `pass-arg` sample); restored.
- mutation (CR): matrix row "Large artifact" -- the WARN block moved below the failure return in `step_ipmcheck`: `test-release-sequence.sh ipmcheck` red (`ipmcheck large fail: the WARN line`); restored. After each, `cmp` against the backup was equal and `git status --short` / `git diff --stat` were unchanged.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Outside OCUTALON, `MapAndStop` now also maps IPM's repository definitions (`^IPM.Repo.Definition{D,S,I}`) into OCUTALON as they are, so the second `zpm "install ocutalon"` finds the first namespace's repositories. An Unconfigure Invoke (`UnmapRepos`) removes only that mapping on uninstall. `release/ipm-install.sh` has a new part `p`: the exact artifact (or one packaged from path A's module) is installed twice from a local filesystem repository on a fresh instance with no Node.js, signs in, is uninstalled, and the definitions' hash is shown unchanged. `release.sh` has a new step `ipmcheck` after `ipm` that runs the FR-57 job's command on the candidate and blocks `push` unless it passes. The release notes record the artifact size and the FR-57 result and hold a registry-install slot; the checklist has the hand row `registry-install`; `docs/install-ipm.md` opens with the registry install; `docs/security-overview.md` lists the mapping.

**Files changed.**
- `src/preload/cls/OcuTalon/Install/Ipm.cls`: `MapRepos` (private), `UnmapRepos`, the `MapAndStop` call.
- `src/module.xml`: the Unconfigure Invoke.
- `release/ipm-install.sh`: part `p` (checks 26-29), check 3's repository lines, helpers, path B's view.
- `release/release.sh`: `step_ipmcheck`, `ipmcheck_section`, `candidate_export` and `candidate_lock_dir` (shared with `step_overview`), STEPS.
- `release/notes.sh`, `release/checklist.sh`: `notes_ipm`, `registry_row`.
- `docs/install-ipm.md`, `docs/security-overview.md`: the registry-first guide and the one Data bullet.
- `docker/tests/test-cpf.sh` (rules 8, 9, 12, 13), `test-release-sequence.sh` (`ipmcheck`), `test-release-checklist.sh` (`registry-row`), `test-release-notes.sh` (`ipm`).

**Review findings.** 26 findings from four layers, none high. Patches applied (4, all low): rule 9's unclosed-first-block hole with a sample, the internal id "FR-57" removed from the public notes label, `t_ipmcheck`'s environment restore, and three missing mutation lines. Deferred (1): the Unconfigure Invoke on an upgrade or reinstall (medium, unverified). All other findings are rejected with their reasons in the Review Triage Log. Follow-up review recommended: false (no patched high or medium).

**Verification performed.** Handoff stage, all green: `test-cpf.sh`, `test-release-checklist.sh`, `test-release-notes.sh`, `test-release-sequence.sh`, `test-boundaries.sh`, `test-pinned-sources.sh`; lane-D throwaways: `ipm-install.sh p` (TIME package 2 s, TIME p-fresh 105 s, projection 25.7 min), `p` with a hand-made artifact, `a`, `r`, `b`, `--live ipm` (PASS), `ci/iris.sh live install-start`; five planned mutations red and restored. After the review patches (no change to any IRIS-run code): the five hermetic suites again green (`test-release-sequence.sh` in 3 min 20 s) and three more mutations red and restored byte-identical. The full no-argument `ipm-install.sh` run was not made locally; CI's `ipm-install` job is its first full run. No container is left behind.

**Residual risks.** The registry install itself is the author's hand gate (`registry-install`); the artifact is 98.8% of the 5,000,000-byte threshold. Part `p` builds the filesystem repository's module list in OCUTALON itself (a registry has none). The `--live ipm` seed is `git archive HEAD`, so the lead's post-commit smoke is what carries the repository mapping into the live candidate. Footprint extensions: `src/preload/cls/OcuTalon/Install/Ipm.cls` and `docs/security-overview.md` (one bullet).
