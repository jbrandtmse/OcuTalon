---
title: 'Story 11.20: The release''s overview step hands the unit files the container can read'
type: 'bugfix'
created: '2026-11-04'
status: 'done'
baseline_revision: '3348ee5cd9fe8048c10a3e29b155f3099d18f3d8'
baseline_commit: '3348ee5cd9fe8048c10a3e29b155f3099d18f3d8'
review_loop_iteration: 0
followup_review_recommended: true
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

### 2026-11-04 - Review pass
- verdicts: 20 findings - high 0, medium 2, low 15, false 3, maybe-false 0
- findings:
  - `[low]` `[reject]` blind: chmod runs before `mkdir -p web/node_modules`; stub prunes it - the chmod line is the orchestrator's (U-256 (b)) and Decided in-stage 3 prunes it on purpose; `web/` exists in the export.
  - `[low]` `[reject]` blind/edge: a stale `overview-fail.log` survives early-failure and WAIT paths - Decided in-stage 2 and the Wait matrix row say it stays; PASS and each new unit failure replace it.
  - `[medium]` `[patch]` blind/vgap: matrix rows "Wait keeps the log" and "Log could not be kept" had no test - added `overview wait` and `overview nolog` cases (new `overview-busy` marker, `nolog` stub).
  - `[low]` `[patch]` edge: a failed move can leave `overview.log` behind - the else branch now removes it.
  - `[medium]` `[patch]` vgap: the umask pin counts source text only - the pass stub now records `umask` and `t_overview` asserts `0077` (kept the line counts).
  - `[low]` `[patch]` vgap: the silent case accepts any `LOG overview ` text - tightened to `LOG overview /`.
  - `[low]` `[reject]` blind/edge/vgap/intent: the relative-`$sdir` branch is untested and unnormalised - the matrix has no row for it; `OCUTALON_RELEASE_STATE` is absolute in practice and the printed path is correct for it.
  - `[low]` `[reject]` blind: the kept log's mode is not asserted - the log keeps its owner-only mode by the script's umask, which only narrows access.
  - `[low]` `[reject]` blind: the `LOG` line is not in the header comment at L437 or the header `Output:` line - Decided in-stage 1 keeps the header out of the footprint.
  - `[false]` `[reject]` edge: `chmod` failure handling and symlink handling in the stub - the chmod line is the orchestrator's; the repo has no link the check trips on (suite green).
  - `[false]` `[reject]` edge: a local path from the unit's first line reaches the record - `step_fail` scrubbing is unchanged and the test asserts the record holds no local path.
  - `[false]` `[reject]` edge: the claim that every overview failure prints `LOG` - the spec scopes `LOG` to a failing unit run.
  - `[low]` `[reject]` edge: the rerun case asserts only the log removal - it also asserts exit 0 and `NEXT ipm`.
  - `[low]` `[reject]` vgap: `overview rerun: the kept log is gone` depends on the preceding fail assertions - they run in the same case.
  - `[low]` `[patch]` vgap: mutation lines for PASS removal, WAIT and the umask stub were missing - added to `## Verification`.
  - `[low]` `[reject]` vgap: `## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The overview step now keeps a failing unit's log as `<state>/overview-fail.log` and prints `LOG overview <absolute path>` right after the FAIL line (no path in the detail, row or record). A pass removes the kept log, a wait keeps it, and a failed move removes the stale `overview.log` and prints no `LOG` line. The hermetic test's `pass` stub fails on any export entry others cannot read, and `t_overview` pins the kept log, the wait, the rerun, the failed move and `umask 077` (line count plus the umask the unit runs under). The orchestrator's chmod line was verified, not edited.

**Files changed.**
- `release/release.sh`: `step_overview` doc sentence, kept-log move, `LOG` line, PASS cleanup.
- `docker/tests/test-release-sequence.sh`: `stub_text` (pass readability and umask record, fail busy/pass markers, `nolog`), `t_overview` cases, header overview lines.

**Review.** 20 findings: patches applied 4 (wait and failed-move tests, stub umask record, failed-move cleanup, silent-case tightening, mutation lines), deferred 0, rejected 14 with reasons in the Review Triage Log.

**Follow-up review recommended: true.** Two medium entries were patched. Unverified risk: the `nolog` stub finds the state folder through the exported `OCUTALON_RELEASE_STATE`; it passes on macOS, not measured on the hosted GNU runner.

**Verification.** Commands 1-3 (loop) pass; command 4 `PASS all rules`; command 5 checklist, notes and boundaries exit 0; command 6 lists only the two files and every `release.sh` hunk lies in `step_overview`. Mutation results are recorded under `## Verification`.

**Residual risks.** The live overview smoke is the lead's.
