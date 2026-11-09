---
title: 'Story 0.15: The Dockerfile sits at the repository root'
type: 'chore'
created: '2026-11-08'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Open Exchange reads the Docker flag from a root `Dockerfile`. OcuTalon's sits at `docker/Dockerfile`, so its listing reads Docker False (17 of the 18 field entries with a root Dockerfile read True, and all 5 without one read False).

**Approach:** Move the file with `git mv docker/Dockerfile Dockerfile`, leaving its content unchanged. Point every reference at the new path, and keep every guard that covered the old path: the LF attribute, the boundary scan, the CI change patterns and the warm manifest. Then pin the move. The upgrade harness accepts either location for the previous release's tree.

## Boundaries & Constraints

**Always:**
- Nothing changes in how the image builds. The build context stays `.`, the COPY lines and every other byte of the Dockerfile stay the same (the rename is `R100`), and `.dockerignore` stays byte-identical. The image's `.Size` measured before and after the move is equal (Task 0).
- `install.sh`, `README.md`, `docs/`, `.dockerignore` and `.github/` stay unchanged.
- Every test pin of the old path moves to the new path. No pin is deleted or weakened, and a guard that covered `docker/Dockerfile` through a `docker/` scope now names the root `Dockerfile`.
- `release/release.sh` builds the candidate from `"$ctx/Dockerfile"` only. `release/upgrade-harness.sh` takes the previous tree's root `Dockerfile` when it exists, else its `docker/Dockerfile`, and otherwise fails loudly as it does today.
- Edits in the contended files (`release/**`, `docker/tests/lib-live.sh`, `docker/tests/test-install-upgrade.sh`, `docker/tests/test-release-sequence.sh`) are path-only (old path to new). The one exception is the harness's either-location selection. Every `release/*.sh` hunk goes to the Contest Planner verbatim before the merge.
- Shell stays portable to bash 3.2.

**Never:**
- No change to public text. If a README or docs sentence ever needed the path, that is an `intent gap` HALT naming the sentence. None does: `git grep` finds the path in no README or docs file.
- No edit under `_bmad/` (`epic-dependencies.yaml` goes to the orchestrator; see Design Notes), and no edit to done specs, cycle logs, the ledger, evidence or set-aside patches (all history).
- No `docker push`, `save`, `export` or registry pull. Only the two `ocutalon-e0s15:*` tags are removed afterwards.
- No `Dockerfile.dockerignore` is created, and no second Dockerfile.

## I/O & Edge-Case Matrix

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Previous tree, root only | the exported tree has `Dockerfile` | the harness builds it with `dockerfile: Dockerfile` | none |
| 2 | Previous tree, v1.0.4 layout | the tree has only `docker/Dockerfile` | `dockerfile: docker/Dockerfile` | none |
| 3 | Previous tree, both | the tree has both files | root `Dockerfile` | none |
| 4 | Previous tree, neither | the tree has `src/module.xml` and no Dockerfile | `die "previous build: the exported tree of <sha> has no src/module.xml, or neither Dockerfile nor docker/Dockerfile"` | dies before any build, as today |
| 5 | Previous tree, no manifest | the tree has a Dockerfile and no `src/module.xml` | the same die | as today |
| 6 | Release image step | the candidate's tree (root `Dockerfile`) | `docker build -f "$ctx/Dockerfile" ... "$ctx"` | the build's failure path is unchanged |
| 7 | Judges' compose | `docker-compose.yml` | `context: .`, `dockerfile: Dockerfile` | none |
| 8 | CI change detection | only the root `Dockerfile` changed | every IRIS group runs because its own pattern claims the path (`1 input path(s) of <group>`), not through the unclassified fallback | none |
| 9 | Warm stack made before the move | a stored manifest naming `docker/Dockerfile` | a warm run is refused as stale (`ci/warm.sh down`, then `up`) | the existing stale refusal |
| 10 | Build context | the decoy tree of `test-build-inputs.sh`, its probe at `$ctx/Dockerfile` | the context carries exactly the copied files, and the Dockerfile is not among them | none |

</intent-contract>

## Code Map

The old path has 15 tracked files outside `_bmad-output` (one, `epic-dependencies.yaml`, under `_bmad/`) (`git grep -n docker/Dockerfile -- . ':(exclude)_bmad-output'`), plus five files that the grep misses (marked NEW).

- `docker/Dockerfile` -> `Dockerfile`: 52 lines, and no line names its own path. Its COPY sources are `docker/licences/*`, `src/`, `docker/ipm/`, `docker/merge.cpf`, `docker/healthcheck.sh`, `docker/after-start.sh` and `docker/after-start.cos`, all relative to the context `.`, so none changes.
- `docker-compose.yml:8`: `dockerfile: docker/Dockerfile` (context `.` at :7). `docker-compose.dev.yml` has no `build:` and inherits it, so it needs no change. The brief expected one there.
- NEW `.gitattributes`: `docker/** text=auto eol=lf` gives the old path LF, and the root path gets nothing (`git check-attr eol -- Dockerfile` is `unspecified`). Add `/Dockerfile text eol=lf`, anchored so that `release/ipm/Dockerfile` is unaffected.
- NEW `ci/units.sh:194-200`: `IRIS_INPUT` claims `docker/[^/]+$`. A root `Dockerfile` would be unclaimed and fall to the every-group fallback (safe, but no longer claimed). Add the alternative `Dockerfile$` (the patterns are wrapped as `^(...)`, so it anchors to the root) and mention it in the comment at :194-197. `WEB_INPUT_PATTERN` and `NOT_IRIS_INPUT_PATTERN` need nothing.
- `ci/warm.sh:78`: in `warm_manifest`'s printf list, `docker/Dockerfile` becomes `Dockerfile`. A missing path is silently dropped by `[ -f ]`, so a stale entry would leave the Dockerfile out of the manifest.
- `release/release.sh:48` (header: the base image of `docker/Dockerfile`) and `:575` (`step_image`: `-f "$ctx/docker/Dockerfile"`). Path-only.
- `release/upgrade-harness.sh` (sourced by `test-upgrade-harness.sh`):
  - :715-718 `add_previous_context`: hard-codes `dockerfile: docker/Dockerfile` for `$state/previous`.
  - :1203-1210 `phase_build`: dies unless `$prev/src/module.xml` and `$prev/docker/Dockerfile` exist.
  - Add the helper `previous_dockerfile <tree>`, which prints `Dockerfile` or `docker/Dockerfile` and returns 1 for neither, and use it at both places. Use `df=$(previous_dockerfile ...) || die ...`, so that the die runs in the caller's shell. The pass line at :1210 stays unchanged.
- `docker/tests/lib-live.sh:515` `dockerfile_copy_sources` reads `docker/Dockerfile`. :529-534 `copy_build_context` creates `$dir/docker` and copies the file to `$dir/docker/Dockerfile`; it becomes `cp Dockerfile "$dir/Dockerfile"` (the loop creates each file's own directory). Consumers of the copied layout:
  - `test-compose-start.sh:278,286` (`-f "$ctx/docker/Dockerfile"`);
  - `test-build-inputs.sh:103`;
  - `test-install-upgrade.sh:56` (`dockerfile: docker/Dockerfile` in `use_image_context`);
  - `test-lib-live.sh:349` (`expected_files`);
  - `ci/warm.sh` (through `copied_files`).
- `docker/tests/test-build-inputs.sh`:
  - :5, :7: header;
  - :50-51: the optional `docker/Dockerfile.dockerignore` becomes `Dockerfile.dockerignore` at the root (BuildKit reads `<dockerfile>.dockerignore` beside the Dockerfile before `.dockerignore`);
  - :58-63: the probe's path, `$ctx/docker/Dockerfile` becoming `$ctx/Dockerfile`, and the fail message;
  - :103: `-f`.
- `docker/tests/test-ci-changes.sh`:
  - :233: `claimed_case "docker/Dockerfile" false docker/Dockerfile` becomes the root path;
  - :290: the c1 commit;
  - :664-669: the rename fixture, `g mv Dockerfile docs/old-Dockerfile.txt`.
  - Helpers: `commit` at :63 and `claimed_case` at :157.
- `docker/tests/test-ci-warm.sh`:
  - :611, :615: the stale fixture's sed and its expected `FAIL WARM stale: Dockerfile changed ...`;
  - :681-682: `mk_tree` writes `$d/Dockerfile`;
  - :951, :968: the matrix lists.
- `docker/tests/test-compose-file.sh`:
  - :2: header;
  - :10: `dockerfile=Dockerfile`;
  - :97, :125: section titles;
  - :416: the `files_keep_lf` list.
  - Helpers: `check` at :13, `code` at :25 and `has_line` at :67. The new checks go here (Tasks).
- `docker/tests/test-readme.sh:46` (comment) and `:140` (`DOCKERFILE=Dockerfile`, read by the `licence` rule).
- `docker/tests/test-release-sequence.sh`:
  - :200 and :1032: the shim's planted-failure message and its pin, which become `<state>/context/Dockerfile`;
  - :511: the seed's `git archive` path list;
  - :2908: `$root/Dockerfile`.
  - All path-only. It accepts rule names as arguments (:4); the rules `image` and `static` hold these lines.
- NEW `docker/tests/test-boundaries.sh`:
  - :92: the scope `scan_files docker ...` loses the Dockerfile after the move (ASCII, no push or save, compose config and inspect rules). Add `Dockerfile` to the pathspecs.
  - :102-106: add it to the must-scan list.
  - :2: name it in the header.
- NEW `docker/tests/test-upgrade-harness.sh`: add the rule `previous-dockerfile` (`t_previous_dockerfile`, `b_previous_dockerfile`) beside `merge-retries`. Pattern: `rule` at :90, with stubs in a subshell (the `t_merge_retries` style at :1227); the rule list is at :1332-1349; update the header at :1-42.
- NEW `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md:1491`, the repository layout: `docker/  # Dockerfile, merge.cpf (Lane A's), ...`. It is the one planning row that names the current location (amendment, Design Notes). The spine has no `.memlog.md`.
- Read only:
  - `.dockerignore`: its first rule `*` excludes the Dockerfile, root or `docker/`.
  - `release/ipm/Dockerfile` and `compose.ipm.yml`: a separate image.
  - `install.sh:32`: a comment with no path.
  - `ci/iris.sh` `cmd_live` (:634): `live build-inputs` starts no IRIS.

## Tasks & Acceptance

**Execution:**
- Task 0, before any edit, on a clean tree: run `docker image inspect --format '{{.Id}}' ocutalon-iris-base:2026.3.0AI.154.0`. If it is missing, record that and skip the measurement (never pull). Then run `docker build -q -f docker/Dockerfile --build-arg IRIS_IMAGE=ocutalon-iris-base:2026.3.0AI.154.0 -t ocutalon-e0s15:before .` and record `docker image inspect --format '{{.Id}} {{.Size}}' ocutalon-e0s15:before` in `## Verification`. Don't rebuild the web bundle until the second build.
- `docker/Dockerfile` -> `Dockerfile`: `git mv docker/Dockerfile Dockerfile`, with no content change.
- Task 0, after the move: run the same build with `-f Dockerfile -t ocutalon-e0s15:after` and the same inspect. Record both sizes and IDs, then run `docker image rm ocutalon-e0s15:before ocutalon-e0s15:after` (only these two tags).
- `docker-compose.yml`, `ci/warm.sh`, `release/release.sh`, `docker/tests/lib-live.sh`, `test-build-inputs.sh`, `test-compose-start.sh`, `test-install-upgrade.sh`, `test-lib-live.sh`, `test-readme.sh`, `test-ci-warm.sh`, `test-release-sequence.sh`: path-only edits at the Code Map lines.
- `.gitattributes`: add `/Dockerfile text eol=lf` after `docker/**`. This keeps the LF guarantee that `files_keep_lf` pins.
- `ci/units.sh`: add `|Dockerfile$` to `IRIS_INPUT` and mention it in its comment. `docker/tests/test-ci-changes.sh`: move the pins to the root path, with the label `the root Dockerfile`.
- `release/upgrade-harness.sh`: add `previous_dockerfile`, with a contract comment ("the root Dockerfile, else docker/Dockerfile (v1.0.4 and earlier); 1 when neither"). Use it in `add_previous_context` and `phase_build`, with the die text of matrix row 4. Make the hunks minimal.
- `docker/tests/test-upgrade-harness.sh`: rule `previous-dockerfile` for matrix rows 1-5:
  - the helper on synthetic trees;
  - `add_previous_context` with `live_add_file` stubbed, reading `context.yml`'s `dockerfile:` line (rows 1-3, and a die for row 4);
  - `phase_build` over a synthetic repository, run from that repository with `row`, `pass` and `die` stubbed so that it stops after the export check (rows 1, 2, 4 and 5).
  - Break: `previous_dockerfile() { echo docker/Dockerfile; }`. Update the header.
- `docker/tests/test-compose-file.sh`, new checks:
  - (a) `Dockerfile` is a file and `docker/Dockerfile` doesn't exist;
  - (b) compose has `context: .` and `dockerfile: Dockerfile`;
  - (c) `release/release.sh`'s code names `-f "$ctx/Dockerfile"`;
  - (d) no tracked or unignored file outside `_bmad/` and `_bmad-output/` names `docker/Dockerfile`, except `release/upgrade-harness.sh` and `docker/tests/test-upgrade-harness.sh`. Assemble the string, as `t_static` does, so the check doesn't match itself.
  - Plus the path moves.
- `docker/tests/test-boundaries.sh`: add `Dockerfile` to the scan scope and to the must-scan list, and update the header.
- `ARCHITECTURE-SPINE.md`: apply the amendment in Design Notes, set `updated:` to the implement date, and run `lint_spine.py`.

**Acceptance Criteria:**
- Given the change, when `git diff -M --name-status "$(git merge-base HEAD feature/OCT_OcuTalon_MVP)" -- Dockerfile docker/Dockerfile` runs, then it prints `R100	docker/Dockerfile	Dockerfile`. `git diff --exit-code <same base> -- README.md install.sh docs .dockerignore .github docker-compose.dev.yml` exits 0.
- Given Task 0, when both sizes are recorded, then `after` `.Size` equals `before` `.Size`. A difference is a HALT `intent gap` with both IDs and `docker history` sizes, never waived.
- Given matrix rows 7 and 10 and the new compose-file checks (a)-(d), when `test-compose-file.sh` and `ci/iris.sh live build-inputs` run, then both pass.
- Given matrix row 8, when `test-ci-changes.sh` runs, then `the root Dockerfile` is claimed by every group's pattern and all checks pass.
- Given matrix rows 1-5, when `test-upgrade-harness.sh` runs, then rule `previous-dockerfile` passes, its break makes it fail, every other rule passes unchanged, and the script ends `all rules passed`.
- Given matrix rows 6 and 9 and the moved pins, when `test-release-sequence.sh` (both batches), `test-ci-warm.sh`, `test-lib-live.sh`, `test-readme.sh`, `test-boundaries.sh` and `test-ci-config.sh` run, then each passes. `test-boundaries.sh` scans `Dockerfile`.
- Given the change, when `git diff --no-renames --name-only <base> -- . ':(exclude)_bmad-output'` runs, then it lists exactly the 20 paths of Design Notes "Files changed".

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs and rows (Rule 6).**
- AD-23: one recipe, `FROM` the retagged base, `IRIS_IMAGE`. Kept: still one file, with the same bytes.
- AD-22: the hermetic checks stay in the hosted `checks` job, with no `compose config` (without `--quiet`) and no `inspect` (without `--format`).
- CON-1: no push, save or export. Task 0 only builds and removes its own tags.
- AD-5: the harness proves upgrades from v1.0.4, whose tree has the old path, so the fallback is needed.
- AD-29: Lane B's `docker/` and Lane A's `release/`. Only Epic 0 edits both.
- Spine rows naming the Dockerfile: :810 (AD-23), :1471 (environments), :1556 and :1561 (requirement map). None of them names a path, so they are unaffected. Only :1491 names one.

No criterion contradicts an AD.

**Amendments** (marker `[AMENDED 2026-11-09, Story 0.15, owner decision via the Contest Planner]`):
- `ARCHITECTURE-SPINE.md:1491`: the `docker/` line drops "Dockerfile, " and carries the marker plus `it read "Dockerfile, merge.cpf (Lane A's), ..."`. A new layout line after `install.sh` reads `Dockerfile  # the image's one recipe (AD-23), at the repository root; Lane B's, as under docker/` with the marker.

**Left as history (Rule 5 tier 1).**
- `epics.md:1033`: Story 0.1's done AC states the build as delivered then. Amending it would rewrite a delivered acceptance.
- `epics.md:1389-1405`: this story names the old path as the origin.
- `epic-0-context.md`: a generated cache, and recompiling it is forbidden. It already describes the move.
- `epics.md:215, 253, 263`, PRD :1460, the brief and PRD addenda, and `ARCHITECTURE-NOTES.md:57, 72`: they name "the Dockerfile" or `docker/` with no Dockerfile path, so they are unaffected.
- Done specs, cycle logs, `deferred-work.md`, `set-aside/*.patch` and `evidence/*`: history by rule.

**orchestrator_edits** (under `_bmad/`, owner-only; apply them at the merge):
- `_bmad/custom/epic-dependencies.yaml:296` (`epic-34` `paths_hint`): `"docker/Dockerfile"` becomes `"Dockerfile"`.
- `_bmad/custom/epic-dependencies.yaml:176` (`footprints.lane_b`): after `- docker/**`, add `    - Dockerfile                                       # the image's recipe, at the root (Story 0.15)`.

**For the orchestrator.**
- Story 11.18 (Epic 11 part 2, ready-for-dev) plans a stand-in that builds `docker/Dockerfile` (`spec-11-18...:71, 164, 173`). It must name the root `Dockerfile`, and check (d) turns red if it doesn't.
- In-flight edits to `docker/Dockerfile` follow the rename at integrate-forward (git rename detection; inference).
- The online demo host's own deployment configuration lives outside the repository (spine :929) and may name the old path. That is owner-only and unseen here.
- A warm stack built before the move refuses its next run (matrix row 9). Each lane runs `ci/warm.sh down` and then `up` after it integrates this story.

**Decided in-stage.**
- `docker-compose.dev.yml` has no `dockerfile:`, so it stays unchanged.
- "Unchanged beyond layer metadata" is measured as equal `.Size`. `.Size` counts layer content only, and the Dockerfile is in no layer (`.dockerignore` `*`).
- The release.sh pin is a static check in `test-compose-file.sh` and not a shim change in `test-release-sequence.sh`, because that file is contended and the shim change would go beyond a path change.
- The test-ci-changes fixtures move to the root path, since they model the repository layout.
- `.gitattributes` uses the anchored `/Dockerfile`.
- The Dockerfile's ownership stays with Lane B (a rename isn't a transfer). It is recorded in the spine layout line, and AD-29's Rule isn't amended (it names folders, not this file).

**Integration (Rules 1/2).** No consumers in this story: it introduces no service.
- Consumed-by: none.
- Consumes: none.
- The new helper `previous_dockerfile` has no sibling. `lib-live.sh`'s `dockerfile_copy_sources` reads the current tree, which must use the root path only, and adding a fallback there would let a stale reference pass. The helper's one caller is the harness, which reads an older tree.

**Ledger inbox (Rule 17).** None.

**Files changed (20):** `Dockerfile` (with `docker/Dockerfile` removed), `docker-compose.yml`, `.gitattributes`, `ci/units.sh`, `ci/warm.sh`, `release/release.sh`, `release/upgrade-harness.sh`, and in `docker/tests/`: `lib-live.sh`, `test-build-inputs.sh`, `test-ci-changes.sh`, `test-ci-warm.sh`, `test-compose-file.sh`, `test-compose-start.sh`, `test-install-upgrade.sh`, `test-lib-live.sh`, `test-readme.sh`, `test-release-sequence.sh`, `test-boundaries.sh` and `test-upgrade-harness.sh`. With `--no-renames`, the diff lists both `docker/Dockerfile` and `Dockerfile`: 7 root, `ci/` and `release/` paths, `docker/Dockerfile` and 12 `docker/tests/` scripts make 20. The spine is under `_bmad-output`.

**ci_groups:** no new unit and no moved unit.
- The new and changed checks run in the hosted `checks` job (`CHECK_SCRIPTS`: compose-file, ci-changes, ci-warm, lib-live, readme, release-sequence, boundaries and upgrade-harness), adding seconds.
- Changed live scripts keep their groups: `live:build-inputs` stays in `image`, and `live:compose-start` and `live:install-upgrade` stay in `install-upgrade`. Their edits are path-only, so no group's time changes and each stays as measured under 35 minutes.

## Verification

**Runtime targets (Rule 13/21):**
- No IRIS MCP call or slot is needed. If one ever is, use only `ocutalon-slot-c` (profile `ocutalon-slot-c`, namespace `OCUTALON`).
- Docker work is limited to the local daemon's `ocutalon-e0s15:*` tags and the `e0s15i` throwaway tag, torn down by `ci/iris.sh teardown`.

**Commands** (each in its own call with `timeout: 600000`; times measured on the base at plan time unless marked):
- `(loop)` `bash docker/tests/test-compose-file.sh`: `all checks passed`, 2 s.
- `(loop)` `bash docker/tests/test-ci-changes.sh`: `all checks passed`, 21 s.
- `(loop)` `bash docker/tests/test-upgrade-harness.sh`: `all rules passed`, 26 s.
- `(loop)` `bash docker/tests/test-ci-warm.sh`: `all checks passed`, about 34 s (Story 0.14).
- `(loop)` `bash docker/tests/test-lib-live.sh`: `all checks passed`, about 25 s (Story 0.14).
- `(loop)` `bash docker/tests/test-readme.sh`: `all rules passed`, 18 s.
- `(loop)` `bash docker/tests/test-boundaries.sh`: `all rules passed`, about 5 s.
- `(loop)` `bash docker/tests/test-release-sequence.sh image static`: `PASS all rules`, 7 s.
- `(loop)` `OCUTALON_RUN_TAG=e0s15i OCUTALON_LOCK_DIR=<lock-dir>/lane-c OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=0 stage=implement' ci/iris.sh live build-inputs`, then `ci/iris.sh teardown` with the same variables: three PASS lines, about 4-13 s with the layers cached.
- `(once)` the Task 0 builds and inspects. Expected: 10-60 s each with a warm layer cache (inference); a cold pip layer takes longer.
- `(once)` `bash docker/tests/test-release-sequence.sh libs refusals cut recut image overview ipmcheck overviewunit overviewdrift overviewdoc push record hands`, then, in its own call, `... resume notes gate secret ipm ipmfail ipmwait ipmnet ipmlib first word pushes static`. Expected: `PASS all rules` each. The whole suite took 186 s, so each half should take about 95 s (inference).
- `(once)` `bash docker/tests/test-ci-config.sh` (exit 0, about 40 s) and `bash docker/tests/test-rehearsal.sh` (about 85 s).
- `(once)` `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16`: `"ok": true`.
- `(once)` the two diff checks of the AC.
- CI-covered, not run locally (a throwaway start plus its tests won't fit about 150 s): `live:compose-start` and `live:install-upgrade` (group `install-upgrade`), which build from `copy_build_context`'s `Dockerfile` and from the real compose file. The real harness's v1.0.4 previous-tree build is covered by the Planner's clean install and the next rehearsal.

**Intended mutations (Rule 19; one per AC, in AC order):**
- AC "R100 and unchanged files": add a comment line to `Dockerfile`. The name-status no longer reads `R100`, so it goes red.
- AC "equal size": a measurement with no pinning test. Its falsifier is the equality itself; record both numbers.
- AC "compose-file and build-inputs":
  - restore `dockerfile: docker/Dockerfile` in compose: checks (b) and (d) go red;
  - revert `release.sh:575`: checks (c) and (d) go red;
  - add `!Dockerfile` to `.dockerignore`: the `test-build-inputs` dockerignore check goes red (an extra file is carried).
- AC "ci-changes": drop `|Dockerfile$` from `IRIS_INPUT`. `claimed_case "the root Dockerfile"` goes red.
- AC "previous-dockerfile": remove the `docker/Dockerfile` fallback, and the row 2 cases go red. The break turns row 1 red.
- AC "moved pins":
  - leave `ci/warm.sh:78` on the old path: the real-tree manifest check in `test-ci-warm` goes red;
  - drop `/Dockerfile` from `.gitattributes`: `files_keep_lf` in `test-compose-file` goes red;
  - drop `Dockerfile` from the boundary scope: `not scanned: Dockerfile` goes red.
- AC "name-only diff": add a comment line to `ci/iris.sh`. A 21st path is listed.

**Shared surfaces:**
- `warm_manifest`'s list (`test-ci-warm`);
- `IRIS_INPUT` and `group_input_pattern` (`test-ci-changes`, `test-ci-config`);
- `copy_build_context`'s layout (`test-lib-live`, `test-compose-start`, `test-build-inputs`, `test-install-upgrade`);
- compose `dockerfile:`;
- `.gitattributes`;
- `test-boundaries`' scan scope;
- the release-sequence seed path list;
- the harness's `context.yml` and its phase_build die text.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
