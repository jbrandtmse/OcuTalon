---
title: 'Story 11.20: The release''s overview step hands the unit files the container can read'
type: 'bugfix'
created: '2026-11-04'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The 1.0.0-rc1 cut failed twice at `release/release.sh`'s overview step ("FAIL Regenerate did not succeed"). The cause is the script's own file mode, not the product:
- `release.sh` (L51) and `lib-release.sh` (L59) set `umask 077`.
- So `candidate_export` (a `git archive | tar -x`) writes the export owner-only: `docs/security-overview.md` is 0600.
- `release/security-overview.sh` runs `docker/tests/test-security-overview.sh`, which `docker cp`s the file into the container. There IRIS's user reads an empty file and fails (ERROR #5001, missing generated-tools marker).

The same tree under umask 022 passes the whole unit. The step also removed the failing unit's log (`rm -f "$log"`), and that cost a reproduction. This is veto U-256, a fix-forward. rc2 is cut from this story's merge.

**Approach:** The fix has three parts.
- **The chmod line.** Under U-256 (b), the orchestrator commits one line, `chmod -R a+rX "$ctx"`, with a two-line why-comment, right after `candidate_export overview "$ctx" || return 1`. The lead integrates it forward before implement. This story verifies that line and tests it. It does not write the line.
- **The kept log (this story's code).** A failing overview unit's log is moved to `$sdir/overview-fail.log`, and its absolute path is printed on its own `LOG` line right after the FAIL line. The path stays out of the record.
- **The pins.** The hermetic release-sequence test's `pass` stub fails on any exported file or folder that others cannot read. One case pins the kept log, and one check pins the `umask 077`.

## Boundaries & Constraints

**Always:**
- Edit only these two files:
  - `release/release.sh`: `step_overview` only (its body and its doc comment).
  - `docker/tests/test-release-sequence.sh`: `stub_text`, `t_overview`, and the header's `overview` rule lines.
- `umask 077` in `release/release.sh` and in `release/lib-release.sh` stays exactly as it is. The release state files rely on it.
- `step_fail`'s rule holds: the FAIL detail, the `rows.tsv` row and the record name no local path. The kept log's path goes only on the separate `LOG` line on standard output.
- PASS and WAIT go on removing `$sdir/overview.log`, as today.
- Source is ASCII. Comments state the contract (Rule 14). New lines pass the script's `forbidden_scan` (`t_static`). Public repo: keep comments plain.
- Every command runs in the foreground of its own call with `timeout: 600000`.

**Never:**
- Write, move or reword the chmod line or its comment. It is the orchestrator's, under U-256 (b). If it is not in the tree when implement starts, HALT `blocked` with `U-256 (b) chmod line not integrated`. Do not add it.
- Touch any of these files: `release/security-overview.sh`, `docker/tests/test-security-overview.sh`, `docs/security-overview.md`, `install.sh`, `docker/after-start.sh`, `docker/merge.cpf`, `release/lib-release.sh`. If the fix seems to need one of them, HALT with an intent gap that names the file.
- Touch `release.sh`'s header, `step_fail`, `candidate_export`, `cmd_next`, `stop_routine` or any other step.
- Touch `ci/units.sh` or `.github/workflows/*`. Add no CI unit and make no group change.
- Run `release/release.sh` against origin or any real remote. Cut, tag or push nothing. The hermetic test's temporary repositories are fine.
- Undo a mutation with `git checkout`, `git restore` or `git stash`. Back the file up to the stage scratchpad and copy it back.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Pass | The unit exits 0. | `PASS overview ...`, then `NEXT ipm`. The export and `overview.log` are gone. A leftover `overview-fail.log` from an earlier failed run of this candidate is removed too. | none |
| Wait | The unit exits 75. | `WAIT overview ...`, exit 5, nothing recorded. `overview.log` is removed and an earlier `overview-fail.log` stays. | none |
| Fail with a DRIFT line | The unit exits 1, and its log holds `DRIFT ...` / `FAIL ...`. | The FAIL line and its detail are unchanged. The log is moved to `$sdir/overview-fail.log`, replacing an earlier one. The next line is `LOG overview <absolute path of overview-fail.log>`. Then RECORD and `RESULT fail` follow, as today. No `overview.log` remains, and the record and row hold no local path. | exit 1 |
| Fail with no matching line | The unit exits with any code but 0 and 75, and prints no DRIFT/FAIL line. | `FAIL overview the overview unit ended with exit <n>`, then the same `LOG` line. | exit 1 |
| Log could not be kept | The move fails (no log file, or a write error). | The FAIL line and record are as above, and no `LOG` line is printed. | exit 1 |
| Export not readable (regression) | The chmod line is absent, so the export is 0600/0700 under umask 077. | The test's `pass` stub prints `FAIL overview <path> is not readable by others` and exits 1. `overview pass` goes red. | test red |

</intent-contract>

## Code Map

- `release/release.sh:51`: `umask 077` (pinned unchanged). `release/lib-release.sh:59`: the same (read only).
- `release/release.sh:442-451`: `step_fail`. It replaces `$sdir` with `<state>`, the checkout with `.` and HOME with `~`, and prints `FAIL <step> <detail>`. Read only. The kept log's path must not go through it.
- `release/release.sh:599-618`: `candidate_export`. `rm -rf`, then `mkdir -p` and `git archive | tar -x`, all under umask 077. Read only. `ipmcheck` uses it too (L950). Its unit, `release/ipm-install.sh`, copies with `cp --no-preserve=mode` and runs its own `chmod -R a+rX` (L653, L1341), so it is not in scope.
- `release/release.sh:628-670`: `step_overview`, this story's code.
  - The chmod line lands after L636.
  - L642 `mkdir -p "$ctx/web/node_modules"` runs after the chmod, so that empty folder stays 0700. It is not part of the export.
  - L651-662: the PASS (0) and WAIT (75) branches, each with `rm -f "$log"`.
  - L664-669: the failure branch. It runs `grep -m 1 -E '^(DRIFT |FAIL |CLASS .* failed)'`, then `rm -f "$log"` (which becomes the move), then `step_fail`.
  - Extend the doc comment (L628-633) by one sentence on the kept log and the `LOG` line.
- `release/release.sh:748,780`: `step_ipm`'s `chmod -R a+rX` inside its container. This is the precedent for the chmod line.
- `release/release.sh:904,1145`: `echo "ARTIFACT $art"`. This is the precedent for printing an absolute local path on its own keyword line, outside the record.
- `release/release.sh:1165-1189`: `cmd_next`. On a non-zero, non-5 return it calls `row_set` with `STEP_DETAIL` and then `stop_routine failed`. `stop_routine` (L336) prints `RECORD ...`, the record question and `RESULT fail`. So the `LOG` line comes after FAIL and before RECORD.
- `release/lib-release.sh:81-83`: `release_state_dir`. It can be relative if `OCUTALON_RELEASE_STATE` is relative. Make the printed path absolute the way L948 does (`case $p in /*) ;; *) p="$PWD/$p" ;; esac`).
- `docker/tests/test-release-sequence.sh`:
  - L23-24: the header's `overview` rule description.
  - L420-442: `stub_text`, with `pass`, `fail`, `busy` and `silent`.
  - L479-485: `set_stub`.
  - L487-520: `mkseed`. The seed holds the `pass` stub, so every rule that passes overview runs the new check.
  - L535-582: `newcase`, `rs` (sets `out`/`rc`), `snap` and `rec_file`. `OCUTALON_RELEASE_STATE=$C/state` is absolute.
  - L1653-1711: `t_overview`.
  - L1668: the pass listing `"rows.tsv state.env "` (must still hold).
  - L2649: `t_static`, which runs the forbidden scan, ASCII, `bash -n` and the step_overview no-ASK awk up to `# --- the ipm step`.
- `.github/workflows/ci.yml:30-43`: the hosted `checks` job. It runs on `ubuntu-24.04` as a non-root user and calls `bash ci/checks.sh`. `ci/units.sh:6`'s `CHECK_SCRIPTS` holds `release-sequence`. Unchanged.

## Tasks & Acceptance

**Execution:**
- Precondition (no edit): confirm that exactly one `chmod -R a+rX "$ctx"` line sits in `step_overview`, and that it is the first non-comment line after `candidate_export overview "$ctx" || return 1` (Verification command 2). If it is absent, HALT as the Never list says.
- `release/release.sh` `step_overview`: change the failure branch.
  - After the first-line grep, move `$log` to `$sdir/overview-fail.log` (`mv -f`) instead of removing it.
  - Call `step_fail` as today.
  - Then, only if the move succeeded, print `LOG overview <absolute path>`.
  - In the PASS branch, also remove `$sdir/overview-fail.log`. The WAIT branch is unchanged.
  - Add one sentence to the doc comment about the kept log and the `LOG` line.
- `docker/tests/test-release-sequence.sh` `stub_text pass`: before the PASS line, find the first path under `.` that is not readable by others, or a folder not searchable by others. Prune `./web/node_modules`, which the step creates after the export. On a hit, print `FAIL overview <path> is not readable by others` and `exit 1`. The measured form is in Design Notes.
- `docker/tests/test-release-sequence.sh` `stub_text fail`: add a first line that exits 0 with a PASS line when `$SHIMLOG/overview-pass` exists. The rerun sub-case uses it. Without the marker the output is unchanged.
- `docker/tests/test-release-sequence.sh` `t_overview` gets three additions.
  - In the pass case, assert that each of `release/release.sh` and `release/lib-release.sh` holds exactly one line `umask 077`.
  - In the fail case, assert all of these:
    - `$OCUTALON_RELEASE_STATE/1.0.0-rc1/overview-fail.log` exists and holds `DRIFT tool recent_activity`.
    - Neither `overview.log` nor the `overview` folder remains.
    - `out` holds the line `LOG overview $OCUTALON_RELEASE_STATE/1.0.0-rc1/overview-fail.log`, and it is the line right after the FAIL line.
    - The record lacks `overview-fail.log`.
  - Then a rerun sub-case: create `$SHIMLOG/overview-pass`, run `rs '' next`, and assert exit 0, `NEXT ipm` and that `overview-fail.log` is gone.
  - In the silent case, assert that the `LOG` line is present.
- `docker/tests/test-release-sequence.sh` header: extend the `overview` rule's lines. They should say that the stub checks the export is readable by others, that a failure keeps its log (`LOG` line) and that the umask stays 077.
- This spec: record the Verification results and the `mutation:` lines.

**Acceptance Criteria:**
- AC1. Given the story's tree with U-256 (b)'s line, when the overview step hands the candidate's export to the unit, then every exported file and folder is readable by others, and every folder is searchable by others. The `pass` stub checks this on every rule that passes the overview step. `umask 077` stays in both release scripts.
  - Pins: `overview pass` and the umask assertion.
  - mutation: delete the chmod line, and `overview pass` goes red with `not readable by others`.
  - mutation: `umask 022` in release.sh, and the umask assertion goes red.
- AC2. Given an overview unit that fails, when the step reports it, then the unit's log is kept at `<state>/overview-fail.log`, and `LOG overview <absolute path>` follows the FAIL line. The FAIL detail, the row and the record carry no local path. PASS and WAIT leave no `overview.log`.
  - mutation: put `rm -f "$log"` back in place of the move, and the kept-log assertions go red.
- AC3. Given `bash docker/tests/test-release-sequence.sh` (no IRIS, no container), when it runs, then every rule passes, including `overview` with the new cases and `static`. In CI it stays in the hosted `checks` job (`CHECK_SCRIPTS` release-sequence), and no unit or group is added.
- AC4 (footprint). Given the diff since `story_base`, excluding `_bmad-output`, when listed, then it holds only `release/release.sh` and `docker/tests/test-release-sequence.sh`. Every `release/release.sh` hunk lies inside `step_overview`'s block. The chmod line counts as the orchestrator's, from before `story_base`.

## Spec Change Log

## Review Triage Log

## Design Notes

**U-256 (Contest Planner, owner's delegated authority, 2026-11-04T02:01:21Z#770): (b) for the one line, (a) for the rest.** AC 1's chmod line landed on the feature branch by U-256 (b); this story verifies and tests it. At plan time (HEAD `f552b73328b2a05d6e32e50d3cf1c908cf70dac4`) the line is not yet in `OCT-epic11`. The lead integrates it forward before implement.

**Lead note (spec gate, 2026-11-04):** the U-256 (b) line arrived on the feature branch as commit 8d60ad43 (a three-line why-comment, then `chmod -R a+rX "$ctx"`, right after `candidate_export overview "$ctx" || return 1`); the lead integrates it forward before implement. The `static` rule "the overview step makes no ASK" counts the text `ask ` (with its trailing space) anywhere from `step_overview()` to `# --- the ipm step`, comments included: words such as `umask ` or `mask ` followed by a space trip it, so nothing added to `step_overview` (the doc comment sentence, the `LOG` line, the PASS cleanup) may contain them. Command 1 runs `static` and catches it.

**Governing ADs (Rule 6):**
- AD-22: testing and CI. Shell checks run on hosted runners, and no unit is added.
- AD-29, with the lane-exception paragraph under AD-33 (spine L1035): `release/` is Lane A and `docker/tests/` is Lane B. Epic 11's exception lets it change the Lane B test file. No AC contradicts an AD.

**Measured at plan (macOS bsdtar 3.5.3, harness umask 022, uid 501).** Under `umask 077`, `git archive HEAD release docs/security-overview.md | tar -x` left 21 paths that others could not read. After `chmod -R a+rX`, the find below returns 0. The script's own `umask 077` therefore decides the modes, whatever the harness umask, so removing the chmod reds the stub locally. Hosted CI runs GNU tar as a non-root user, and GNU tar applies the umask by default for non-root users (documented; inference for CI: it is not measured on the runner). The stub's check:
```
bad=$(find . -path ./web/node_modules -prune -o \( ! -perm -004 -o \( -type d ! -perm -001 \) \) -print | head -n 1)
[ -z "$bad" ] || { echo "FAIL overview $bad is not readable by others"; exit 1; }
```
`bash docker/tests/test-release-sequence.sh overview` took 8.5 s. The full file took 3 min 40 s, with all 26 rules passing at HEAD.

**Decided in-stage:**
1. **The path goes on a separate `LOG overview <absolute path>` line, right after the FAIL line.** The detail stays as `step_fail` makes it, so the row, the record and `RESULT` are unchanged and free of local paths. `ARTIFACT <absolute path>` is the precedent. The header's `Output:` line is not edited, because the footprint is `step_overview` only. That line already omits WARN, NOTE and ASK, so it is not an exhaustive list.
2. **The name is `overview-fail.log`, replaced by each new failure.** PASS also removes it, because a passed run supersedes the failure it documents. WAIT keeps it, because nothing superseded it.
3. **The stub prunes `./web/node_modules`.** The step creates that empty folder after the chmod (L642), so it is not part of the export. No container reads it.
4. **The umask pin is a line count in `t_overview`** (one `^umask 077$` per script). It also keeps the readability check meaningful: under umask 022 the check would pass with no chmod.
5. **No helper.** The change is a few lines inside `step_overview`.
6. **If the chmod line is missing at implement, HALT and do not add it.** U-256 (b) gives the line to the orchestrator.

**Extend, don't copy (Rule 2).** The chmod mirrors `step_ipm`'s `chmod -R a+rX` (L748, L780) on the host side. The new stub check extends `stub_text pass`, and the new assertions extend `t_overview`'s existing cases. No copy. `step_ipmcheck` removes its log the same way (L982). Keeping that log too is outside U-256's footprint and is not tasked here.

**Integration ACs, Consumes and Consumed-by (Rules 1 and 2):** no new service, module or shared component.
- **Consumes:** `release/security-overview.sh` and its `docker/tests/test-security-overview.sh` (unchanged). The lead's smoke runs them for real.
- **Consumed-by:**
  - the Contest Planner's rc2 cut of 1.0.0, then Epic 38's real cut (38.1 to 38.3);
  - part 2's 11.14 to 11.16 and 11.18, which add steps beside `step_overview`.

**Ledger inbox (Rule 17):** none.

**Shared surfaces with other files:** none. Only `docker/tests/test-release-sequence.sh` reads `release.sh`'s output. The checklist and notes tests share `lib-release.sh`, which this story leaves unchanged.

## Verification

Run every command from the worktree root, each in its own foreground call with `timeout: 600000`. No IRIS slot is needed. `<story_base>` is the baseline revision that the implement stage records in this spec's frontmatter (`baseline_commit`) at its start, after the lead's integrate-forward.

**Commands:**
1. `(loop)` `bash docker/tests/test-release-sequence.sh overview static`. Expected: `PASS overview`, `PASS static`, `PASS all rules` (about 15 s).
2. `(loop)` Two checks of the chmod line.
   - `awk '/^step_overview\(\)/{f=1} f&&/candidate_export overview "\$ctx" \|\| return 1/{g=1;next} g&&!/^[[:space:]]*#/{print;exit}' release/release.sh`. Expected: `  chmod -R a+rX "$ctx"`.
   - `awk '/^step_overview\(\)/,/^}/' release/release.sh | grep -c 'chmod -R a+rX "\$ctx"'`. Expected: `1`.
3. `(loop)` `grep -c '^umask 077$' release/release.sh release/lib-release.sh`. Expected: `:1` for each file.
4. `(once)` `bash docker/tests/test-release-sequence.sh`. Expected: every rule passes and the last line is `PASS all rules` (about 4 min).
5. `(once)` `bash docker/tests/test-release-checklist.sh`, then `bash docker/tests/test-release-notes.sh`, then `bash docker/tests/test-boundaries.sh`, one per call. Expected: exit 0 each.
6. `(once)` `git diff --name-only <story_base> -- . ':(exclude)_bmad-output'`. Expected: only `release/release.sh` and `docker/tests/test-release-sequence.sh`. Also `git diff -U0 <story_base> -- release/release.sh`: every hunk lies inside `step_overview`'s block.

**Mutations (Rule 19).** For each: back the file up to the stage scratchpad, mutate, run command 1, observe red, copy the backup back, check `cmp` identical, and check that `git status --short` and `git diff --stat` are unchanged. Record each as `mutation: <change> -> <test red>`.
- AC1: delete the `chmod -R a+rX "$ctx"` line. Expected red: `overview pass: exit`, with `not readable by others`.
- AC1 (umask): `umask 077` -> `umask 022` in `release/release.sh`. Expected red: the umask assertion.
- AC2: `mv -f "$log" ...` -> `rm -f "$log"`. Expected red: the kept-log and `LOG` line assertions.
- AC4: a blank line appended to `release/lib-release.sh`. Expected: the command 6 listing names it.

**Lead-owned smoke (after review).**
- Make a lane-A throwaway export the way the step makes it, inside the stage scratchpad: `(umask 077; mkdir -p X; git archive HEAD | tar -x -C X; chmod -R a+rX X; mkdir -p X/web/node_modules)`.
- Then, in `X`, run one live unit: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=11 stage=smoke' OCUTALON_RUN_TAG=e11s20smoke bash release/security-overview.sh`. Run it in its own call. Expected: exit 0 with a `PASS overview` line. The unit tears down its own run tag.
- Optionally, run the same steps without the chmod as the negative control. Expected: the `Regenerate did not succeed` FAIL.

**Shared surfaces:**
- The `pass` stub of `stub_text`: every rule that passes the overview step runs it through the seed.
- The state-folder listing after the overview step (pass: `rows.tsv state.env`; fail: plus `overview-fail.log`).
- `release.sh next`'s output on an overview failure: the new `LOG` line.
- No other test or script reads these.

Every test added or changed passes on a fresh environment, in either order. Each case builds its own throwaway repositories and state folder.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
