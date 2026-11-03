---
title: 'Story 0.14: A start that recovers through the merge retry passes the live checks and the upgrade harness'
type: 'bugfix'
created: '2026-11-03'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 0.13 lets a start recover from ERROR #453 by retrying the merge once. The recovered start writes `STEP merge RETRY 1 after #453` and then `STEP merge OK <n>s`. But `docker/tests/lib-live.sh`'s `log_steps` keeps every `^STEP ` line, and `check_log` diffs that list against `expected_run`, which has only `STEP merge OK`. So the live tests and `release/upgrade-harness.sh` still read a healthy, recovered start as a failure (DW-624).

**Approach:** Teach `check_log`, and only `check_log`, to accept exactly one sanctioned shape: one `STEP merge RETRY 1 after #453` line followed straight away by `STEP merge OK`. Every other shape fails exactly as it does today, and `log_steps` doesn't change. The upgrade harness counts the `STEP merge RETRY` lines of every start it makes and reports the total in its result, so every retry stays visible (veto U-240, binding scope items 1 to 5).

## Boundaries & Constraints

**Always:**
- The check is all or nothing. `check_log` removes the line `STEP merge RETRY 1 after #453` from the reduced log only when all four of these conditions hold for that start's reduced log (the `log_steps` output):
  - (a) exactly one line contains `retry`, in any case;
  - (b) that line is exactly `STEP merge RETRY 1 after #453`, the whole line;
  - (c) the next line is exactly `STEP merge OK`;
  - (d) no line starts with `STEP merge FAILED`.
  
  Then it diffs the rest against the expected file as today. When any condition fails, the `$tmp/actual.log` it diffs is byte-identical to `log_steps` output, so the verdict and the printed diff are exactly today's.
- When the sanctioned line was removed, the pass label still starts with today's text and adds `(after one merge retry on #453)`. The fail label and the diff output stay unchanged.
- `log_steps` stays byte-unchanged. Its direct callers (`test-production.sh`, `test-production-restart.sh`, `test-install-upgrade.sh` row 7, `test-reminder-restart.sh`) keep today's behaviour.
- The harness counts every start it makes, five in all: settings previous, settings candidate, records previous, records candidate and records restart. It counts each start from that start's own log (`start_log | grep -c '^STEP merge RETRY'`) right after the wait for the start returns, whether the start ended ready or not, and before any `die`. Each start appends one line, `MERGE-RETRIES <n> <start label>`, to the phase's `$results` file.
- `record_section` writes `Merge retries: <total>` as the line right after `Run:` (the sum of the `MERGE-RETRIES` lines in its results file; 0 when there are none, a dry run included). `phase_report` prints `MERGE-RETRIES <total>` on stdout before its `RECORD` and `RESULT` lines, and `RESULT <n>` stays the last line.
- Portable to bash 3.2 and BSD awk. ASCII only. Comments state the contract (Rule 14).

**Never:**
- No edit to `docker/after-start.sh` or `docker/merge.cpf`: the diff against the feature branch's merge base must be empty for both.
- No change to `log_steps`, `expected_run`, `start_log`, `record_rows`, `record_result`, `HARNESS_ROWS`, the table, or any existing record line, its order or its values (`Result:`, `Mode:`, `Required:`, `Candidate:`, `Previous:`, `Note:` and `Run:`).
- No other STEP or RESULT line is ignored or loosened.
- No edit to `ci/units.sh`, `release/notes.sh`, any Lane B class or any live test script.

## I/O & Edge-Case Matrix

Rows 1-11 run `check_log` on one start log against `expected_run ... 0.1.0` (OK lines carry seconds, such as `STEP merge OK 9s`). "As today" means fail, with `$tmp/actual.log` byte-identical to `log_steps` output.

| # | Start log (STEP/RESULT lines) | Expected |
|---|---|---|
| 1 | the expected run, first-try merge | pass, unchanged label |
| 2 | `STEP merge RETRY 1 after #453`, then the expected run | pass, label adds `(after one merge retry on #453)`; `actual.log` equals the expected file |
| 3 | RETRY 1, then `STEP merge FAILED exit 7`, no RESULT | as today |
| 4 | RETRY 1 as the last STEP line (no OK after it) | as today |
| 5 | RETRY 1, RETRY 1, then the run | as today |
| 6 | RETRY 1, `STEP merge RETRY 2 after #453`, then the run | as today |
| 7 | near misses, each alone before the run: `RETRY 2 after #453`; `RETRY 1 after #4530`; `RETRY 1 after #453 x` (trailing text); `step merge retry 1 after #453` (other case) | as today, each |
| 8 | RETRY 1, the run, plus a later `STEP merge retry 1 after #453` line | as today |
| 9 | RETRY 1, the run, plus a later `STEP merge FAILED exit 7` line | as today |
| 10 | RETRY 1, then the run ending `RESULT OK 0.0.9` (another STEP or RESULT difference) | fail (not loosened) |
| 11 | `log_steps` on row 2's log | still prints the RETRY line (unchanged) |
| 12 | harness: start logs without RETRY / with one `STEP merge RETRY 1 after #453` | `MERGE-RETRIES 0 <label>` / `MERGE-RETRIES 1 <label>` appended to `$results` |
| 13 | harness: results with no `MERGE-RETRIES` line / lines 0 and 1 from two phases | section `Merge retries: 0` / `Merge retries: 1`; report prints `MERGE-RETRIES 1` before `RESULT`; `Result:` and the table unchanged |

</intent-contract>

## Code Map

- `docker/tests/lib-live.sh` (Epic 0 may edit it; scope: `check_log` only):
  - L355 `start_log`: the current start's log, with `\r` stripped (the log is rewritten at every start, so it holds one start).
  - L619 `log_steps`: `^(STEP|RESULT) ` lines, with ` OK <n>s` reduced to ` OK`. Read only.
  - L624-630 `expected_run`: starts with `STEP merge OK`. Read only.
  - L632-642 `check_log`: writes `$tmp/actual.log` from `log_steps`, then `diff "$2"`, then pass or fail. Add the four-condition filter between `log_steps` and `diff` (an inline awk, or a small helper used only here), and update the comment at L632.
- `docker/tests/test-lib-live.sh` (hermetic, `CHECK_SCRIPTS`):
  - L1-35: the header. Add `check_log` to the item at L9.
  - L44-55: the `dc` stub serves `$log_fixture` as the start log.
  - L68-73: `write_log`.
  - L75-89: `pass`, `fail`, `accepts` and `rejects`.
  - L262-274: the reductions block. Add the new rows after it.
  - L859: the verdict pattern, a subshell with `pass` and `fail` overridden to echo `VERDICT ...`. Use it to read `check_log`'s verdict and label. `check_log` writes into `$tmp`, so each row compares `$tmp/actual.log` with `log_steps` output.
- `release/upgrade-harness.sh` (Lane A's release work; Epic 0 may edit it):
  - L1-38: the header. L24 (report) names the count.
  - L395-428: `record_section`. Add `Merge retries:` after the `Run:` line (L420).
  - L547-584: `row`, `record_line`, `pass` and `fail`. `record_rows` (L354-385) reads only `$1 == "RECORD"`, so a `MERGE-RETRIES` line doesn't touch the rows.
  - L702-708: `ready_or_die`, which serves the starts at L1070, L1090 and L1158.
  - L1467-1470: the upgrade's direct wait. L1523-1526: the restart's direct wait.
  - L1093 and L1373: the two `check_log` calls. They need no change.
  - L1639-1656: `phase_report`. L1733-1738: `$results` is `$state/results.<phase>`, emptied when the phase runs again.
- `docker/tests/test-upgrade-harness.sh` (hermetic, `CHECK_SCRIPTS`):
  - L1-34: the header (the rule list).
  - L46-79: `eq`, `has`, `lacks` and `status_is`. L80: `rule <name> <t> <b>`, where the break must make the test fail.
  - L431 `write_results`, L448 `write_options`, L465-553 `t_record`.
  - L668-715: `t_record_contract`. The fixed-order grep is at L674 and L677.
  - L943 `report_state`, L953 `run_cmd_phase`, L962-993 `t_report`, L996-1010 the rule list.
- Read only:
  - `docker/after-start.sh` L10 and L69, the RETRY form.
  - `docker/tests/test-after-start.sh`, Story 0.13's pins.
  - `release/notes.sh` L379 and L398: it copies `Result:`, `Mode:`, `Previous:` and `Note:` by prefix plus the first table, so the new line doesn't reach the notes.
  - `docker/tests/test-rehearsal.sh` L683-715 and `test-release-notes.sh` L167: synthetic harness sections.
  - `docker/tests/test-release-sequence.sh` L1434: `plan` writes a section.

## Tasks & Acceptance

**Execution:**
- `docker/tests/lib-live.sh`: in `check_log`, apply the four-condition filter (Boundaries) to the `log_steps` output before the diff. On the sanctioned path, add the label suffix. Change nothing else in the file. This addresses DW-624 and scope items 1 and 2.
- `docker/tests/test-lib-live.sh`: add matrix rows 1-11. Build each log from the `expected_run` lines (OK lines with seconds) plus the row's lines. Check the verdict and the label through the overridden `pass` and `fail`. For every "as today" row, check that `$tmp/actual.log` equals `log_steps` output. Update the header. This covers DW-624 and scope item 4.
- `release/upgrade-harness.sh`: add a helper, for example `count_merge_retries <start label>`, that appends `MERGE-RETRIES <n> <label>` to `$results`. Call it after each of the five waits (in `ready_or_die`, which takes its label, and at L1467 and L1523). Add the `Merge retries:` line to `record_section` and the stdout line to `phase_report`. Update the header. This is scope item 3.
- `docker/tests/test-upgrade-harness.sh`: add a rule `merge-retries` (`t_merge_retries`, `b_merge_retries`) that pins matrix rows 12-13, with the helper on a stubbed `start_log` (counts 0 and 1), `record_section` and `report` over a `report_state` folder. Extend `t_record_contract`'s fixed order with `Merge retries` after `Run`. Update the header. This is scope item 4.

**Acceptance Criteria:**
- Given matrix rows 1-11, when `bash docker/tests/test-lib-live.sh` runs under the host's `/bin/bash` (3.2 on macOS), then every check passes and the script ends `test-lib-live: all checks passed`.
- Given matrix rows 12-13, when `bash docker/tests/test-upgrade-harness.sh` runs, then the rule `merge-retries` passes, its break makes it fail, every existing rule passes unchanged in its assertions (only the record-contract order gains `Merge retries`), and the script ends `test-upgrade-harness: all rules passed`.
- Given the change, when `git diff --name-only "$(git merge-base HEAD feature/OCT_OcuTalon_MVP)" -- . ':(exclude)_bmad-output'` runs, then it lists only the four files above, and `docker/after-start.sh` and `docker/merge.cpf` aren't among them. The merge base keeps the check true when the feature branch moves on.
- Given the hermetic scripts that source `lib-live.sh` or the harness (Verification, `(once)`), when each runs, then it passes unchanged.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs.**
- AD-23: the after-start STEP log grammar and the log rewritten at every start, so one log is one start. Readiness is the marker only. This story changes how the tooling reads the log, not what makes a start ready.
- AD-22: the hermetic checks stay in the hosted `checks` job, and no `compose config` or `inspect` call is added.
- AD-29: `docker/tests/` is Lane B's and `release/` is Lane A's. Only Epic 0 edits both.
- AD-5 was checked: the harness proves upgrades. Its rows and verdict are unchanged.

No criterion contradicts an AD.

**Why condition (a) uses any case, and why (d) exists.** Rows 7-9 fail on the diff whatever is removed. But scope item 2 says such a log fails "exactly as today", so a removal that leaves a different diff would break it. All or nothing makes the negative rows byte-checkable.

**Decided in-stage.**
- "Follows it" means the next reduced line. After-start writes no STEP line between the RETRY line and the OK line, and any other place fails on the diff anyway.
- Placement of the count. A `Merge retries:` record line after `Run:`, and not a table row: notes.sh copies the first table into the release notes, and the tests pin eleven rows. Every existing line keeps its text and order, and notes.sh reads by prefix, so it ignores the new line (no user-facing text). The `MERGE-RETRIES` line is printed on stdout before `RECORD`, so `RESULT` stays last.
- A dry run reads `Merge retries: 0`: no start was made.
- The count covers all five starts, including the restart, which has no `check_log`, and the previous-build starts, which read 0 until a build with the retry is the previous one. It counts every line that starts with `STEP merge RETRY`, near misses included, because visibility isn't acceptance.
- The pass label suffix makes a recovery visible in the live tests' output.

**Integration (Rules 1 and 2).** This story has no new service, and its consumers already exist.
- Consumed-by:
  - the `check_log` callers: `test-install-start.sh` rows 1-4, `test-install-upgrade.sh` row 6, `test-online-demo.sh` rows 1 and 13, `test-audit.sh` row 10, and the harness's settings and records upgrade checks;
  - the harness record, read by Story 11.5's sequence, Story 38.2's rehearsal count and the 1.0.0 gates.
- Consumes: Story 0.13's RETRY line form.
- The lead's live smoke (`test-install-start.sh`, `test-install-upgrade.sh`) shows that a run without #453 still passes through the real callers.

**Reuse (Rule 2).** This extends `check_log`, `record_section` and `phase_report` in place, plus the existing test helpers and the rule/break pattern. No sibling is copied.

**Ledger inbox.** DW-624 is addressed by the `lib-live.sh` and `test-lib-live.sh` tasks.

## Verification

**Commands** (each with `timeout: 600000`, one per call):
- `(loop)` `bash docker/tests/test-lib-live.sh`. Expected: `all checks passed`. About 25 s.
- `(loop)` `bash docker/tests/test-upgrade-harness.sh`. Expected: `all rules passed`. About 22 s.
- `(loop)` `git diff --exit-code "$(git merge-base HEAD feature/OCT_OcuTalon_MVP)" -- docker/after-start.sh docker/merge.cpf`. Expected: exit 0.
- `(once)` `git diff --name-only "$(git merge-base HEAD feature/OCT_OcuTalon_MVP)" -- . ':(exclude)_bmad-output'`. Expected: exactly the four files of the Tasks.
- `(once)` `bash docker/tests/test-boundaries.sh`. Expected: `all rules passed`. About 5 s.
- `(once)` `bash docker/tests/test-ci-config.sh`. Expected: exit 0. About 40 s.
- `(once)` `bash docker/tests/test-ci-warm.sh`. Expected: `all checks passed`. About 34 s.
- `(once)` `bash docker/tests/test-rehearsal.sh`. Expected: `all rules passed`. About 85 s.
- `(once)` `bash docker/tests/test-release-sequence.sh`. Expected: `PASS all rules`. About 186 s.

All timings were measured on the base at plan time. The live throwaway tests are the lead's smoke, not implement-stage commands.

**Mutations (Rule 19; apply, see red, revert, record):**
- Drop the RETRY line whatever follows it: row 4 goes red.
- Drop every `^STEP merge RETRY ` line (DW-624's first suggestion): rows 5-7 go red.
- Skip condition (a) or (d): row 8 or row 9 goes red (`actual.log` vs `log_steps`).
- Filter in `log_steps` instead: row 11 goes red.
- Leave the restart's count out, or hard-code 0: row 12/13's count of 1 goes red.
- Remove the `Merge retries:` line: row 13's count of 0 goes red.

**Shared surfaces:**
- `check_log`'s verdict for its callers, loosened only for the sanctioned shape.
- The harness record section gains `Merge retries:` after `Run:`. Its readers are notes.sh (by prefix) and the record-contract order rule, which is updated.
- The harness results files gain `MERGE-RETRIES` lines, which `record_rows` ignores.
- `report` stdout gains one line before `RECORD`.
- `CHECK_SCRIPTS` is unchanged.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
