---
title: "Story 11.26: The README's Measured rows say exactly what was measured"
type: 'bugfix'
created: '2026-11-06'
status: 'done'
baseline_revision: 'ed048b5b1884f76120945fa5c96c98ad0e20667c'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Two row labels of the README's `## Measured` table claim more than their sources measured (DW-775): "The demo's incident, end to end with a live model" comes from the eval demo gate, which validates the diagnosis and its fix but runs no dry run, approval or fix run; "The always-on online demo" reports the model cost only.

**Approach:** Replace the two labels with the Contest Planner's ruling (owner delegation, 2026-11-06, ruling (a)) word for word, and update the same two lines of the `measured` rule's `MEAS_LABELS` heredoc in `docker/tests/test-readme.sh` in place.

## Boundaries & Constraints

**Always:**
- README.md lines 34 and 39 become exactly (plain ASCII apostrophe, result cells unchanged):
  - `| The demo's incident diagnosed with the right fix, on a live model | 30 of 30 runs |`
  - `| Model cost of the always-on online demo | about 9 to 10 cents a day |`
- `docker/tests/test-readme.sh` lines 510 and 515 (the `MEAS_LABELS` heredoc) become exactly `The demo's incident diagnosed with the right fix, on a live model` and `Model cost of the always-on online demo`.
- Start from README.md sha256 `8923a64fcdbccb0413587c03438fc3659089a77fb7b772c49c7fad34efd1745d` and test-readme.sh sha256 `4b9f34c75d6199479824f80486c198c95e84cd74a0dc2533839dec584979fdb5`; if either differs, HALT `blocked` `intent gap`.

**Never:**
- No other line of either file changes; no other file changes outside `_bmad-output` (not the 11.25 spec either: its amendment marker is the lead's bookkeeping).
- No other wording change in README (public text): if one seems forced, HALT `blocked` `intent gap` quoting it.
- The "19 of 22 (target: 20)" row (DW-776, closed by design) and every number stay as they are.
- No pin deleted or weakened; no new rule, helper or self-test.
- No absolute or home-folder path in any committed file (test-boundaries `paths`).

</intent-contract>

## Code Map

- `README.md` (354 lines) -- `## Measured` 26-44; the two rows are 34 and 39; nothing else references either label (git grep, case-insensitive, at 0199768176ffaa9f23d6986ed72fdb8086077e24).
- `docker/tests/test-readme.sh` (1957 lines) -- `MEAS_LABELS` heredoc 507-516 (comment 506 "two hold an apostrophe": still true after the change); `chk_measured` 517-530 iterates the heredoc; `rule_measured` 1336-1348 -- its self-tests name only "Routine attention decisions right", "Cost of one attention decision" and "Prompt-injection attempts", and `st_facts` derives the per-label removal tests from `MEAS_LABELS`, so no self-test changes; header comment 164-165 names no label.
- Read-only regression readers: `docker/tests/test-release-notes.sh` (`static`), `docker/tests/test-boundaries.sh` (paths and keys scan of README.md), `docker/tests/test-cpf.sh`, `docker/tests/test-bridge-guide.sh`.

## Tasks & Acceptance

**Execution:**
- [x] `README.md` -- verify the base sha256, replace lines 34 and 39 with the ruled rows -- DW-775 (Planner ruling (a)) -- AC1, AC3
- [x] `docker/tests/test-readme.sh` -- verify the base sha256, replace heredoc lines 510 and 515 in place with the two new labels -- DW-775 -- AC2, AC3
- [x] This spec -- record Verification results and one `mutation:` line per AC.

**Acceptance Criteria:**
- AC1 (the rows, DW-775). Given README.md, when read, then `## Measured` has the rows `| The demo's incident diagnosed with the right fix, on a live model | 30 of 30 runs |` and `| Model cost of the always-on online demo | about 9 to 10 cents a day |` at lines 34 and 39, and neither old label appears anywhere in the repository outside `_bmad-output`.
- AC2 (pins). Given `test-readme.sh`, when run under bash and `/bin/bash` 3.2, then `PASS measured`, `PASS top` and `test-readme: all rules passed`; it fails `measured` when either new label is reverted, removed, renamed or moved out of the section (the existing `st_facts` self-tests now cover the new labels).
- AC3 (smallest diff). Given the two files, then README.md sha256 is `d3ac69333f87ced2ad5f7639ab7cd909778d8f504e13b2e26619380cc9d4a941`, test-readme.sh sha256 is `f4d6876bf7fa3de76ae7dc0ebea3b777bb518d28c9034d18b5d0ff792931fa0d`, and the story diff outside `_bmad-output` is exactly those two files with 2 lines added and 2 removed in each.
- AC4 (other readers). Given the README-reading scripts, when run, then `test-release-notes.sh` passes every rule (`static` included), `test-boundaries.sh`, `test-cpf.sh` and `test-bridge-guide.sh` pass.

## Spec Change Log

## Review Triage Log

### 2026-11-06 - Review pass
- verdicts: 7 findings - high 0, medium 0, low 0, false 7, maybe-false 0
- findings:
  - `[false]` `[reject]` (blind-hunter) The spec still shows unchecked tasks, a stale Auto Run Result and no recorded verification results -- those are the finalize step's own writes, made after the layers report; the final spec carries them.
  - `[false]` `[reject]` (blind-hunter) baseline_revision `ed048b5b` differs from the commit cited in Design Notes and the base sha256s are not shown as checked -- `ed048b5b` is HEAD at dispatch, and both base sha256s were verified against it before editing (Verification results below); the plan-time commit was only the measurement copy.
  - `[false]` `[reject]` (edge-case-hunter) Spec checkboxes unchecked, no `mutation:` lines, stale Auto Run Result -- same as the first row: written at finalize.
  - `[false]` `[reject]` (verification-gap) No `mutation:` line for AC1-AC4 -- the four mutations were demonstrated after the layers reported and are recorded under Verification.
  - `[false]` `[reject]` (verification-gap, other) `rule_measured` does not pin the result cells -- existing design, outside this story (the intent keeps every number and result cell unchanged and pins nothing new).
  - `[false]` `[reject]` (intent-alignment) The tests check that README and heredoc agree, not that the labels are true to their sources -- descriptive; the truth of the labels is the Planner's ruling, taken word for word as the intent requires.
  - `[false]` `[reject]` (intent-alignment) The README lead-in and the old wording in `_bmad-output` are untouched -- the intent's Never list excludes both.

## Design Notes

**Governing ADs.** AD-29 (README.md and `docker/tests/` are Lane B; Epic 11 may change either). AD-22 (`test-readme.sh` is a hermetic static check in the hosted `checks` job; the table reports evaluation results, it does not redefine SM-1/SM-2). AD-20 (cost per decision and per turn: "Model cost of the always-on online demo" claims model cost only, which is what the usage log records). No AC contradicts an AD's Rule or Prevents line. NFRs: none unmeasurable.

**Rule 1/2.** No service, module or shared component: two README labels and two lines of an existing pin list. No consumers in this story. Consumes: the Planner's ruled labels. Consumed-by: none. Extend, don't copy: the `MEAS_LABELS` heredoc lines are edited in place; nothing new.

**Ledger (Rule 17).** DW-775 -- addressed by both Execution tasks and AC1. DW-776 is not in this story's inbox (closed by design); its row is untouched.

**Measured at plan (2026-11-06, a scratch copy of HEAD 0199768176ffaa9f23d6986ed72fdb8086077e24 outside the repository; the worktree unchanged).** With the change: the sha256s of AC3; `test-readme.sh` all rules passed (36 s) under bash and `/bin/bash` 3.2.57; `test-release-notes.sh` 16/16 PASS; `test-boundaries.sh`, `test-cpf.sh`, `test-bridge-guide.sh` all passed. README label 1 reverted -> `FAIL measured` ("has no table row 'The demo's incident diagnosed with the right fix, on a live model'"); label 2 reverted -> `FAIL measured`; base `test-readme.sh` against the new README -> `FAIL measured` naming both old labels. README.md stays ASCII.

**Decided in-stage.**
- D1. `rule_measured`'s self-tests, the heredoc comment, the header comment and `finish measured`'s text stay unchanged: none names an old label, the count stays eight and two labels still hold an apostrophe.

## Verification

All commands run from the worktree root after `git rev-parse --show-toplevel` matches it, each in its own foreground call with `timeout: 600000`. No container, IRIS, network or `ci/iris.sh` call.

**Commands:**
- (once) `shasum -a 256 README.md docker/tests/test-readme.sh` before editing -- expected: the base sha256s of Boundaries.
- (loop) `shasum -a 256 README.md docker/tests/test-readme.sh` -- expected: the sha256s of AC3 (AC1, AC3).
- (loop) `bash docker/tests/test-readme.sh` -- expected: `PASS top`, `PASS measured`, `test-readme: all rules passed` (AC2).
- (once) `/bin/bash docker/tests/test-readme.sh` -- expected: `test-readme: all rules passed` (AC2).
- (once) `bash docker/tests/test-release-notes.sh`; then, each its own call, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-cpf.sh`, `bash docker/tests/test-bridge-guide.sh` -- expected: all PASS, exit 0 (AC4).
- (once) `git diff --numstat -- . ':(exclude)_bmad-output'` -- expected: exactly `2 2 README.md` and `2 2 docker/tests/test-readme.sh` (AC3).
- (once) `git grep -n -i -E -e 'end to end with a live model' -e '^(\| )?The always-on online demo( \||$)' -- . ':(exclude)_bmad-output'` -- expected: no output, exit 1 (AC1; at plan it lists README 34, 39 and test-readme.sh 510, 515 before the change and nothing after).

**Rule 19.**
- Shared surfaces: the `measured` rule's label list (`MEAS_LABELS` in `docker/tests/test-readme.sh`) and the `rule_measured` self-tests derived from it (`st_facts`). Every test added or changed passes on a fresh environment, in either order (`test-readme.sh` is hermetic and reads only tracked files; a clean checkout is the fresh environment).
- Mutations to demonstrate (observe red, restore byte-identical, write each as a `mutation:` line here): AC1 README line 34 reverted to the old label -> `FAIL measured`; AC2 `test-readme.sh` lines 510 and 515 reverted with the new README -> `FAIL measured` naming both old labels; AC3 one byte appended to README line 3 -> the README sha256 differs and numstat shows `3 3 README.md`; AC4 ` (Ens.Director)` inserted after "It works from real failures" in the first Measured bullet -> `FAIL dev-only` in `test-readme.sh` and `FAIL static` in `test-release-notes.sh` (observed at plan).

**Verification results (2026-11-06, worktree HEAD ed048b5b1884f76120945fa5c96c98ad0e20667c).**
- Base sha256s before editing matched Boundaries. After: README.md `d3ac6933...a941`, test-readme.sh `f4d6876b...1fa0d`, both equal to AC3; `git diff --numstat` outside `_bmad-output`: `2 2 README.md`, `2 2 docker/tests/test-readme.sh`; the old-label `git grep` printed nothing (exit 1).
- `bash docker/tests/test-readme.sh`: `PASS top`, `PASS measured`, `test-readme: all rules passed`; `/bin/bash` (3.2): `test-readme: all rules passed`.
- `test-release-notes.sh` (`static` included), `test-boundaries.sh`, `test-cpf.sh`, `test-bridge-guide.sh`: all passed, exit 0.

**Mutations (Rule 19).** After each, the tree was restored byte-identical (`git status --short` and `git diff --stat` unchanged; sha256s as AC3).
- mutation: AC1 README.md line 34 reverted to the old label -> `FAIL measured` in `test-readme.sh`.
- mutation: AC2 `test-readme.sh` lines 510 and 515 reverted to the old labels (new README kept) -> `FAIL measured`, naming both old labels ("has no table row").
- mutation: AC3 one space appended to README.md line 3 -> README sha256 `6ba8a750...` differs from AC3 and numstat shows `3 3 README.md`.
- mutation: AC4 ` (Ens.Director)` inserted after "It works from real failures" in the Measured section's bullet (README line 43) -> `FAIL dev-only` in `test-readme.sh` and `FAIL static` in `test-release-notes.sh`.

## Auto Run Result

Status: done
Blocking condition: none

Summary: README.md lines 34 and 39 and `docker/tests/test-readme.sh` heredoc lines 510 and 515 now carry the Planner's two ruled labels word for word (plain ASCII); nothing else changed.

Files changed:
- `README.md` -- the two `## Measured` row labels (lines 34, 39); result cells unchanged.
- `docker/tests/test-readme.sh` -- the matching two `MEAS_LABELS` heredoc lines (510, 515), edited in place.
- This spec -- status, baseline, tasks, Verification results, mutations, triage log.

Review: four layers (blind-hunter, edge-case-hunter, verification-gap, intent-alignment) reported 7 findings, all rejected as `false` (the spec bookkeeping they flagged is written at finalize; the others restate existing design or the intent's own exclusions). Patches applied: 0. Deferred: 0.

Follow-up review recommended: false (no patch applied).

Verification: see Verification results above; every Verification command passed and the four mutations went red as expected.

Residual risks: none beyond the existing design that `rule_measured` pins the labels, not the result cells.
