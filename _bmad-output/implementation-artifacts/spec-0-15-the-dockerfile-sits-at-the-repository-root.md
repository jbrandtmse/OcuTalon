---
title: 'Story 0.15: The Dockerfile sits at the repository root'
type: 'chore'
created: '2026-11-08'
status: 'done'
baseline_revision: '52849f666c11edd547f2ef8a5a1d53a49f3ea3b6'
baseline_commit: '52849f666c11edd547f2ef8a5a1d53a49f3ea3b6'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      The release image step's `-f` path is pinned only by a source-text check (compose-file check (c)); the docker shim of
      `test-release-sequence.sh` discards the `-f` value, so no behavioural test fails if `step_image` builds from a wrong path.
    evidence: |-
      The shim's `-f | --build-arg) shift 2` arm ignores the value and its planted-failure message is derived from the context
      directory. This predates Story 0.15 (the old `docker/Dockerfile` path was equally unchecked); the story kept the contended
      file to path-only edits. A fix is a few lines in the shim (fail when the `-f` file is absent from the context).
    location: >-
      docker/tests/test-release-sequence.sh:197
    severity: low
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

### Review Findings

Code review (2026-11-09, review tier full-opus; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; diff `52849f66` plus working tree). 20 raw findings: 0 decision-needed, 2 patch, 3 defer, 15 rejected. No high or medium. Rule 6: AD-5, AD-22, AD-23 and AD-29 match (one recipe with the same bytes, no new `compose config`/`inspect`, either-location previous tree, Lane B ownership in the spine layout). Rule 3: build and install tooling; `live:build-inputs` builds the real compose file and `copy_build_context`'s root `Dockerfile` (run locally), `live:compose-start` and `live:install-upgrade` run in CI. `test-release-sequence.sh` both batches passed on the committed tree (`d594c615`, acceptance-auditor run), closing the "re-run on the committed tree" residual risk.

- [x] [Review][Patch] The spine's `updated:` was not set to the implement date (Task "set `updated:` to the implement date"; the markers read 2026-11-09) [_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md:10] — low, fix-risk low (frontmatter date only, outside Epic 41's regions); set to `2026-11-09`; `lint_spine.py` still the same 10 low pre-existing placeholder findings.
- [x] [Review][Patch] The `IRIS_INPUT` comment reflow left two short ragged lines [ci/units.sh:197] — low, fix-risk low (comment only, outside Epic 41's ~108-128/~209-218 regions); joined into one line; `test-ci-changes` all checks passed.
- [x] [Review][Defer] The release image step's `-f` path has no behavioural pin: the shim discards `-f`, so `t_image`'s moved `planted build failure in <state>/context/Dockerfile` expectation is fixed by the context, not by `-f`, and `--live` never runs in CI [docker/tests/test-release-sequence.sh:195] — deferred: pre-existing, contended file beyond a path change; occurrence appended to DW-1004 (wontfix-accepted, reopen_if unchanged). Its cited line 197 is the `*) ctx=$1` arm; the `-f` arm is :195.
- [x] [Review][Defer] Nothing checks that the Open Exchange listing reads Docker True after the move reaches the branch it reads [Dockerfile] — deferred: outward, owner/Planner; DW-1005 wontfix-accepted, reopen_if the listing still reads False after the release that carries the root Dockerfile.
- [x] [Review][Defer] README "Repository layout" says `docker` holds the image's files and names no root `Dockerfile` [README.md:366] — deferred: spec Never forbids public-text changes, and the sentence names no path and stays true for the remaining files; DW-1006 by-design.

**Rejected:**
- `low` blind: `add_previous_context`'s die text names `src/module.xml` though it checks only the Dockerfile — matrix row 4 prescribes the text; on the normal path `phase_build`'s combined check runs first; the fix edits the spec's matrix.
- `low` blind: DW-1004 and the `deferred:` entry cite :197, not :195 — the ledger body is write-once and the frontmatter is build-auto's; noted on the defer row above.
- `low` blind: the Auto Run Result's file counts disagree (20 vs 19 listed vs 21 in the commit) — the fix edits the spec; 20 is the `--no-renames` count the AC defines.
- `low` blind: no real `release.sh` image build — grouped into the DW-1004 row; the committed-tree non-live run is now done (both batches green).
- `low` gap: the equal-size AC is weak and has no mutation line — the spec decided the measure; its falsifier is the equality (Rule 19 allows a measurement); the fix edits the spec.
- `false` gap: the unchanged-files half of the R100 AC has no mutation line — Rule 19 asks one mutation per AC, and the R100 AC has one (`R099`).
- `low` gap: `test-compose-start.sh` and `test-install-upgrade.sh` edits never ran locally — one path each, run by `live:compose-start` and `live:install-upgrade` in CI; `live:build-inputs` built the same layout locally.
- `false` gap: check (d) (`--untracked`), check (a) and `mkseed` read checkout state — the checkout's content is their subject; an unignored file naming the old path should fail; the move is committed, so `mkseed` reads it.
- `low` gap: the AC base `git merge-base HEAD feature/OCT_OcuTalon_MVP` takes in an earlier README change (21 paths, README diff) — the fix edits the spec's AC; against the baseline revision both checks pass.
- `false` gap + auditor: spec `status: done` while sprint status reads `review` — the frontmatter is build-auto's machine state; this review sets sprint status.
- `false` auditor: no record of the `release/*.sh` hunks going to the Contest Planner — the constraint says before the merge, which is the lead's step; the hunks are path-only plus the allowed helper.
- `false` auditor: `orchestrator_edits` in `epic-dependencies.yaml` still pending — owner-only by the spec, applied at the merge.
- `false` blind: the DW-1004 fix is "in footprint" because the story edits the file — the file is contended and the story's edits there are path-only by constraint.
- `false` gap: `t_image`'s moved assertion is an AC pin that cannot fail — the row 6 AC's pin is compose-file check (c), whose mutation is recorded red; `t_image` pins the failure report, which it still does.
- edge-case-hunter: no findings (`[]`).

## Spec Change Log

- planner-2026-11-09-0.15: the Contest Planner (via the orchestrator, 2026-11-09 ~08:05Z) APPROVED the release-tool hunks as shown: `release/release.sh` is path-only (header comment :48, `step_image` build line :575); `release/upgrade-harness.sh` gets the `previous_dockerfile` helper, the `phase_build` precheck and the new `previous-dockerfile` test rule; the wording nit in `add_previous_context`'s die message stays. Merge held until after the 1.0.5 cut (0.15 leads 1.0.6); after it integrates, every lane runs `ci/warm.sh down` then `up`.

## Review Triage Log

### 2026-11-08 - Review pass
- verdicts: 26 findings - high 0, medium 1, low 19, false 6, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: `add_previous_context` die text says "no src/module.xml" though it checks only the Dockerfile - matrix row 4 prescribes this exact text and the rule pins it; the manifest is checked by `phase_build` before.
  - `[low]` `[reject]` Blind: no run evidence for `test-compose-start` and `test-install-upgrade` - the spec marks both CI-covered (a throwaway start does not fit one call); their edits are one path each.
  - `[low]` `[reject]` Blind: check (d) exempts the harness and its test whole - the spec prescribes exactly this exemption; the harness's current-tree build is covered by `previous-dockerfile` and the release rows.
  - `[low]` `[defer]` Blind: release `-f` path pinned by a text grep only - pre-existing shim gap (see `deferred:`).
  - `[low]` `[patch]` Blind: overlong comment line in `ci/units.sh` - reflowed.
  - `[false]` `[reject]` Blind: marker date 2026-11-09 is later than today - the spec's Design Notes prescribe that marker.
  - `[false]` `[reject]` Blind: stale Auto Run Result block - rewritten at finalize.
  - `[low]` `[reject]` Blind: equal `.Size` is weak proof of identical content - the spec decided the measure; `.Size` counts layer content, the Dockerfile is in no layer, and the ids differ as expected.
  - `[low]` `[reject]` Edge: optional root `Dockerfile.dockerignore` not claimed by `IRIS_INPUT` - the file does not exist and the spec forbids creating it.
  - `[low]` `[reject]` Edge: same file has no LF attribute - same reason.
  - `[medium]` `[patch]` Edge: matrix row 9 (a manifest stored before the move) had no test, only a changed-hash root entry - added a `test-ci-warm` check whose stored manifest names the old path; mutation line written.
  - `[low]` `[reject]` Edge: compose check (b) matches lines anywhere in the file - compose has one service and one build block; a stricter parse is more complexity than the risk.
  - `[low]` `[reject]` Edge: `mkseed` fails until the move is committed - transitional by construction; both batches pass on a single-commit copy of this tree.
  - `[low]` `[reject]` Edge: the `epic-dependencies.yaml` footprint - owner-only; already listed as `orchestrator_edits` in the spec.
  - `[low]` `[defer]` Gap: release `-f` pin is source text only - same entry as above.
  - `[low]` `[patch]` Gap: moved pins, check (a) and the harness wiring had no `mutation:` lines - ran each mutation to red, restored, wrote the lines.
  - `[false]` `[reject]` Gap: the equal-size AC has no test - the spec says it is a measurement whose falsifier is the equality.
  - `[low]` `[reject]` Gap: the name-only diff and unchanged-files ACs fail against `git merge-base` because of an earlier README change on the branch - an AC wording issue (the fix edits the spec); against the baseline revision they pass (20 paths, README untouched).
  - `[low]` `[reject]` Gap: `mkseed` reads `git archive HEAD` - same as the Edge row.
  - `[low]` `[reject]` Gap: check (d) uses `--untracked`, so a stray file can turn it red - that is its purpose (an unignored file naming the old path); it fails loudly.
  - `[low]` `[reject]` Gap: the `Dockerfile.dockerignore` branch of `test-build-inputs` never executes - pre-existing for the old path; no such file may exist.
  - `[false]` `[reject]` Gap: stale Auto Run Result block - same as above.
  - `[false]` `[reject]` Gap: marker date - same as above.
  - `[low]` `[reject]` Intent: nothing asserts the file is tracked at the root - the change is a staged rename committed by this run; a tracked-file assertion adds a git dependency to a static test.
  - `[false]` `[reject]` Intent: `IRIS_INPUT`'s `Dockerfile$` is unanchored - the group patterns are wrapped as `^(...)`, so it claims only the root file; pinned by the `newdir/Dockerfile` and `docker/other/Dockerfile` cases (mutation line written).
  - `[low]` `[reject]` Intent: `copy_build_context` goes beyond a path swap (`mkdir -p "$dir"`) - required, because the context directory no longer exists before the copy.

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

**Implementation record (Story 0.15, implement stage):**
- Task 0 base image `ocutalon-iris-base:2026.3.0AI.154.0`: id `sha256:4e3907db20043abb15774aaa50b00f1a1bdb72f7cf37efaeb9ec48e7c329dba9`.
- Task 0 `before` (`-f docker/Dockerfile`): `sha256:1f01e86e2adbed9537efa660f06558159577b96828713bf852822d4fd66b9015` `.Size` 5667082326.
- Task 0 `after` (`-f Dockerfile`, after the `git mv`): `sha256:9656f9010d85aaafc0ec81533421a09d26a1ccac6ae75d5fcedb8e587e490862` `.Size` 5667082326. The sizes are equal; the ids differ (layer metadata). Both tags were removed afterwards.
- mutation: a comment line added to `Dockerfile` -> `git diff -M --name-status` reads `R099`, not `R100` (red); restored to `R100`.
- mutation: `dockerfile: docker/Dockerfile` back in `docker-compose.yml` -> `test-compose-file` checks (b) and (d) red; restored.
- mutation: `release.sh` `step_image` back to `-f "$ctx/docker/Dockerfile"` -> checks (c) and (d) red; restored.
- mutation: `!Dockerfile` appended to `.dockerignore` -> `ci/iris.sh live build-inputs` "dockerignore: the build context differs from the files the Dockerfile copies" red (the context held `Dockerfile` too); restored, `e0s15i` torn down.
- mutation: `|Dockerfile$` dropped from `IRIS_INPUT` -> `claimed_case "the root Dockerfile"` red (no group claims it); restored.
- mutation: `IRIS_INPUT`'s `Dockerfile$` widened to `.*Dockerfile$` -> the `newdir/Dockerfile` and `docker/other/Dockerfile` cases of `test-ci-changes` (unclassified, never claimed by a non-root Dockerfile) red; restored. (`web/Dockerfile` and `release/ipm/Dockerfile` are already claimed or declared by other patterns, so they pin nothing.)
- mutation: the `docker/Dockerfile` fallback removed from `previous_dockerfile` -> the v1.0.4 layout cases of rule `previous-dockerfile` red; restored. The rule's own break (`previous_dockerfile() { echo docker/Dockerfile; }`) is red on the root layout (the rule runs it on every execution).
- mutation: `docker/Dockerfile` recreated beside the root file -> check (a) of `test-compose-file` red; removed again (the index keeps the rename).
- mutation: `add_previous_context` back on the old path, `phase_build`'s check back on `-f docker/Dockerfile`, and, separately, the order of the root file and the fallback swapped in `previous_dockerfile` -> rule `previous-dockerfile` red each time; restored.
- mutation: `ci/warm.sh` `warm_manifest` left on `docker/Dockerfile` -> the stale-warm, non-class-input and real-tree manifest checks of `test-ci-warm`, and the new check for a stack made before the move (matrix row 9), red; restored.
- mutation: `expected_files` of `test-lib-live` back on the old path, and, separately, `copy_build_context` copying to `$dir/docker/Dockerfile` -> `build context: the copied files differ from the files the Dockerfile names` red both times; restored.
- mutation: `DOCKERFILE=docker/Dockerfile` in `test-readme` -> rule `licence` red; restored.
- mutation: the `pip_pins` source in `t_static` of `test-release-sequence` back on the old path -> rule `static` red; restored.
- mutation: `/Dockerfile` dropped from `.gitattributes` -> `files_keep_lf` red; restored.
- mutation: `Dockerfile` dropped from the `test-boundaries` scan scope -> `not scanned: Dockerfile` red; restored.
- mutation: a comment line added to `ci/iris.sh` -> the name-only diff lists 21 paths, not 20; restored.
- Runs, all green: `test-compose-file`, `test-ci-changes`, `test-upgrade-harness` (`all rules passed`), `test-ci-warm`, `test-lib-live`, `test-readme`, `test-boundaries`, `test-ci-config`, `test-rehearsal`, `live build-inputs` (three PASS lines). `test-release-sequence.sh` (both batches) passes only when `HEAD` holds the move, because its seed is `git archive HEAD ... Dockerfile`: it was run from a scratch repository holding this tree as a single commit (`PASS all rules` each); re-run it on the committed tree.
- `lint_spine.py`: `"ok": false` with 10 low "placeholder" findings, identical on the unmodified spine at `HEAD` (pre-existing); the amendment adds none.
- The AC name-only diff against `git merge-base HEAD feature/OCT_OcuTalon_MVP` lists 21 paths because that base predates a `README.md` change committed earlier on this branch; against the baseline revision the list is the 20 paths.

**QA stage (Story 0.15):** every AC with a test is pinned by a script in `CHECK_SCRIPTS` (`boundaries`, `ci-changes`, `compose-file`, `lib-live`, `ci-warm`, `readme`, `upgrade-harness`, `release-sequence`, `ci-config`) or by a live unit (`build-inputs`, `compose-start`, `install-upgrade`), so the default suite finds all of them. The R100 / unchanged-files, equal-size and name-only-diff ACs are one-shot git or measurement checks with no test (a test would need the baseline revision); no test was added. Mutations re-demonstrated on the committed tree, each restored from a scratch backup (`git status --short` empty afterwards):
- mutation: a comment line added to `Dockerfile` -> `git diff -M --name-status 52849f66` reads `R099` (red, AC R100); restored to `R100`.
- mutation: `dockerfile: docker/Dockerfile` back in `docker-compose.yml` -> `test-compose-file` `compose: builds the root Dockerfile from the context .` and `dockerfile: no file names the old path` red (AC compose-file).
- mutation: `release.sh` `step_image` back to `-f "$ctx/docker/Dockerfile"` -> `test-compose-file` `release.sh: the image step builds from the root Dockerfile of the context` and the old-path scan red.
- mutation: `docker/Dockerfile` recreated beside the root file -> `test-compose-file` `dockerfile: Dockerfile is a file at the repository root and the old path is gone` red.
- mutation: `|Dockerfile$` dropped from `IRIS_INPUT` -> `test-ci-changes` `classifier: the root Dockerfile: not claimed by the pattern of` every group red (AC ci-changes).
- mutation: the `docker/Dockerfile` fallback disabled in `previous_dockerfile` -> `test-upgrade-harness` rule `previous-dockerfile` red (v1.0.4 layout, context.yml and phase_build cases) (AC previous-dockerfile).
- mutation: `ci/warm.sh:78` left on `docker/Dockerfile` -> `test-ci-warm` five checks red, including the real-tree manifest and the row 9 stale-stack check (AC moved pins).
- mutation: `/Dockerfile` dropped from `.gitattributes` -> `test-compose-file` `gitattributes: the copied and executed files keep LF` red.
- mutation: `Dockerfile` dropped from the `test-boundaries` scan scope -> `scope: a file that must be scanned is not` (`not scanned: Dockerfile`) red.
- mutation: a comment line added to `ci/iris.sh` -> the name-only diff lists 21 paths, not 20 (red, AC name-only diff); restored.
- Runs on the committed tree, green: `test-compose-file`, `test-ci-changes`, `test-upgrade-harness`, `test-boundaries`, `test-lib-live`, `test-readme`, `test-release-sequence.sh image static` (`PASS all rules`).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `git mv docker/Dockerfile Dockerfile` (R100). Every reference points at the root: compose, `ci/warm.sh`, `release/release.sh`, `lib-live.sh` and the tests. The guards that covered the old path now cover the root file (`/Dockerfile text eol=lf`, the boundary scan, `IRIS_INPUT` `Dockerfile$`, the warm manifest). The upgrade harness takes the root Dockerfile of the previous tree, else `docker/Dockerfile`. The image `.Size` is equal before and after (5667082326); the ids differ (layer metadata).

**Files changed (20 outside `_bmad-output`, plus the spec and the spine):** `Dockerfile` (renamed from `docker/Dockerfile`), `docker-compose.yml`, `.gitattributes`, `ci/units.sh`, `ci/warm.sh`, `release/release.sh`, `release/upgrade-harness.sh`, and in `docker/tests/`: `lib-live.sh`, `test-boundaries.sh`, `test-build-inputs.sh`, `test-ci-changes.sh`, `test-ci-warm.sh`, `test-compose-file.sh`, `test-compose-start.sh`, `test-install-upgrade.sh`, `test-lib-live.sh`, `test-readme.sh`, `test-release-sequence.sh`, `test-upgrade-harness.sh`. The spine's repository layout (`ARCHITECTURE-SPINE.md`) carries the amendment.

**Review.** 26 findings: high 0, medium 1, low 19, false 6. Patches applied: 3 (one medium: the row 9 warm-manifest test; two low: the comment reflow and the mutation lines). Deferred: 1 (the release `-f` shim gap, low). Every rejected finding and its reason is in the Review Triage Log. Follow-up review recommended: false.

**Verification.** Green: `test-compose-file`, `test-ci-changes`, `test-upgrade-harness`, `test-ci-warm`, `test-lib-live`, `test-readme`, `test-boundaries`, `test-ci-config`, `test-rehearsal`, `ci/iris.sh live build-inputs` (three PASS, torn down), and `test-release-sequence.sh` in both batches (each `PASS all rules`) on a single-commit copy of this tree. `lint_spine.py` reports `"ok": false` with the same 10 low placeholder findings as the unmodified spine at HEAD. The name-only diff is the 20 paths against the baseline revision; the R100 and unchanged-files checks pass.

**Residual risks.** `live:compose-start` and `live:install-upgrade` are CI-covered only. `test-release-sequence.sh` must be re-run on the committed tree. The `epic-dependencies.yaml` `orchestrator_edits` and the online demo host's own configuration are the owner's. The AC base `git merge-base HEAD feature/OCT_OcuTalon_MVP` also includes an earlier README change on the branch (21 paths).
