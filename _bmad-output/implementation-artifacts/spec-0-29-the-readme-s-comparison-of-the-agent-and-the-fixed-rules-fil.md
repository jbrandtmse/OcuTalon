---
title: "Story 0.29: The README's comparison of the agent and the fixed rules, filled from the committed rules-only report"
type: 'feature'
created: '2026-11-12'
status: 'done'
baseline_revision: '65a75b5c22d515e22c01e69c9de447c69d5c5fb8'
baseline_commit: '65a75b5c22d515e22c01e69c9de447c69d5c5fb8'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** The README's "What changes without the agent?" figures were worked out from expected answers, not measured.

**Approach:** Part C of the original Story 0.27 plan, split out whole by the Contest Planner's ruling (2026-11-12 ~02:05Z, owner's delegation) and the orchestrator. It runs on lane A after Story 0.28 and after Story 0.27 (Part B, the measuring tools, on lane B) has merged, because it is filled from 0.27's committed rules-only report under `eval/results/` and uses 0.27's `node eval/compare.mjs --column`. The README gains the ruled variant R comparison H3 at the end of "## Measured" and the ruled pointer in "What OcuTalon does"; a README test pins the ruled text and the fixed-rules column equals the committed report.

## Boundaries & Constraints

**Always:**
- README text is the ruled text of `## Ruled README change` (C1, C2), applied verbatim; only its `<FILL: ...>` values are written, and only from `node eval/compare.mjs --column eval/results`.
- The R paragraph ends "..., and a CI check keeps their names and text out of every prompt and mock scenario." (02:05Z ruling, option (c)).
- Every existing `test-readme.sh` and `test-eval-set.sh` rule keeps passing; none is deleted, skipped or weakened.
- Shell stays ASCII and bash 3.2 compatible. Every command a stage runs finishes in about 150 s.

**Never:**
- "never used for tuning" appears nowhere in the README. "measured at release 1.0.9" is variant R's agent-column text on feature only (the Planner's release-candidate fork replaces it).
- No `eval/results/` change (it is 0.27's committed run). No `.github/workflows`, `release/**` or `_bmad/**` hunk. No absolute local path in any tracked file.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| README column drifts | A fixed-rules cell, the date, `<I>` or `<J>` differs from `compare.mjs --column eval/results` | `FAIL readme-column` names the row | CI red |
| Ruled comparison | `bash docker/tests/test-readme.sh` on the README with C1 and C2 | `comparison` passes | No error expected |
| Text broken | H3 renamed or moved, a paragraph word changed, the commit link changed, a row label reworded or two swapped, the sentence changed, the pointer's anchor changed, the worked-out sentence restored, "never used for tuning" added | `comparison` / `public-text` name it | test fails |

</intent-contract>

## Code Map

See Story 0.27's spec (`spec-0-27-a-measured-comparison-of-the-agent-and-the-fixed-rules-repla.md`, Code Map) for `README.md` "## Measured" and the worked-out paragraph, `test-readme.sh` (`chk_measured`, `rule_public_text`, `chk_readme_links`, `section`, `headings`, `MODEL_PARA`) and `test-eval-set.sh`'s rule dispatch; and for `eval/compare.mjs --column` and `eval/results/` as 0.27 delivers them. Re-read them on the tree this story starts from (after 0.27 merges); line numbers will have moved.

## Tasks & Acceptance

**Execution:**
- `README.md` -- apply `## Ruled README change` parts C1 and C2 verbatim, filling each `<FILL: ...>` from `node eval/compare.mjs --column eval/results` and nothing else.
- `docker/tests/test-readme.sh`:
  - new rule `comparison`: "## Measured" ends with the H3 "With the agent and with fixed rules only" (its only H3, after the money line), holding the ruled paragraph word for word (the date matched as `[A-Z][a-z]+ [0-9]{1,2}`, `<I>` and `<J>` as numbers), the ruled header row, the seven ruled row labels in order as first cells, a non-empty agent and fixed-rules cell in each row, and the ruled sentence under the table; the H3 is the last heading before `## More`; the ruled pointer paragraph sits in GUIDE.md's "What OcuTalon does" directly above the model paragraph, and its link `README.md#with-the-agent-and-with-fixed-rules-only` resolves to the H3; ONE NUMBER PER MEASURE (Planner ruling 3): once the agent column's routine cell is filled with `<n> of <m>` (the RC fork's variant F), it must equal the `<n> of <m>` of the main Measured table's "Routine attention decisions right" row, while the cell still reads "measured at release 1.0.9" the check passes; "Worked out from the expected answers" appears nowhere. The agent column's text is not pinned (the release fork replaces it).
  - `public-text`: add "never used for tuning" to the forbidden phrases (with a self-test).
  - Self-tests, one bad variant per way to break `comparison` (the added sentence removed or changed; the H3 moved after `## More`; a filled agent routine cell that differs from the main table's routine row, plus one that agrees, which passes; H3 renamed or moved, a word of the paragraph changed, the commit link changed, a label reworded or two swapped, the sentence changed, the pointer's anchor changed, the worked-out sentence restored). Update `RULES` and the header comment.
- README.md stays at most 2,300 words (`bash docker/tests/test-readme.sh` `word-cap`; about 2,170 with C1).
- `docker/tests/test-eval-set.sh` -- new rule `readme-column`: the README comparison's fixed-rules column, its date, `<I>` and `<J>` equal `node eval/compare.mjs --column eval/results`, row by row. Self-tests: a README cell changed, a report value changed, a row missing.

**Acceptance Criteria:**
- Given the README comparison, when it is read, then it is the ruled variant R text, and every fixed-rules cell, the date, `<I>` and `<J>` equal `compare.mjs --column eval/results`; `readme-column` and `comparison` pass and fail on their bad variants; "never used for tuning" is nowhere in the README.
- Given CI on this story's head, when it finishes, then every workflow is green.

### Review Findings

Code review 2026-11-12 (epic-cycle stage; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; diff `git diff 65a75b5c` over the four footprint files). 7 patch, 0 decision-needed, 0 defer, 18 rejected (13 lines below; same-cause findings share a line). No HIGH; no AD mismatch (AD-22, AD-19). README.md and GUIDE.md were not edited (ruled text).

- [x] [Review][Patch] [medium] `measured` read the whole "Measured" section, so the comparison table's repeated label "Cost of one attention decision" satisfied it and removing the main table's row passed (a weakened existing rule); it now reads the section above its first H3, with a self-test that removes only the main table's row [docker/tests/test-readme.sh:chk_measured, rule_measured]
- [x] [Review][Patch] [medium] three `comparison` self-tests (empty agent cell, differing routine cell, agreeing routine cell) edited the literal "measured at release 1.0.9", so the RC fork's fill (variant F) would turn `comparison` red, against Design Notes ("needs no rule change"); they now edit the agent cell by its place in the row and take the main row's number from the README; checked with the agent column filled on a scratch copy (PASS) [docker/tests/test-readme.sh:rule_comparison]
- [x] [Review][Patch] [low] the separator-row and the empty-line-before-the-sentence clauses of `comparison` had no self-test [docker/tests/test-readme.sh:rule_comparison]
- [x] [Review][Patch] [low] the three-cell guards of both rules and readme-column's unreadable-paragraph branch had no bad variant; added `comparison` "a row of four cells" and `readme-column` samples bad-row-four-cells and bad-paragraph-unreadable [docker/tests/test-readme.sh:rule_comparison, docker/tests/test-eval-set.sh:mksamples]
- [x] [Review][Patch] [low] a README row with other than three cells was reported as "the fixed-rules cell is X, compare.mjs --column gives X"; it now says the row has N cells, not 3 [docker/tests/test-eval-set.sh:check-readme-column.mjs]
- [x] [Review][Patch] [low] no `readme-column` sample for a missing rules-only-held-out.json; added bad-no-held-out-report [docker/tests/test-eval-set.sh:mksamples]
- [x] [Review][Patch] [low] `comparison` checked only that the money line is somewhere above the H3, not C1's "the money line, a blank line, then the block"; it now requires the heading right after the money line and one empty line, with a self-test [docker/tests/test-readme.sh:chk_comparison]

Rejected:
- `low` Blind/Edge: the agent column is a placeholder that no test makes go away, and the guide's pointer says "measured side by side" meanwhile: already ledgered DW-1218 (by-design, the RC fork replaces it); occurrence appended.
- `low` Blind: the guide pointer drops the inline figures; the H3 adds about 250 words: ruled C2/C1 text; `word-cap` passes at 2,171.
- `low` Blind/Edge: the one-number check ties the 1.0.4 main table to the 1.0.9 column, covers only the routine row, not the cost row or other number forms: Planner ruling 3 sets that check and has the fork refresh the main table (by-design).
- `low` Blind: the agent side has no committed report: the agent column is the RC fork's (variant F); out of this story's ruled scope.
- `low` Blind: no row for what fixed rules get wrong; rows 4-7 do not say which cases they cover; "keeps their names and text out of every prompt" claims too much: ruled PUBLIC TEXT, applied verbatim.
- `low` Blind: only the main report's date is read, as a UTC date: `compare.mjs` (Story 0.27) takes it from rules-only.json; both reports are one run; fix is out of footprint for an unreached case.
- `low` Edge: CRLF README fails with "no heading": fails closed; the repository's README is LF.
- `false` Edge: README rows missing from the column go unchecked: `comparison` pins exactly the seven labels and the block's line count, and the `compare` rule pins the column's rows.
- `low` Edge: spawnSync has no timeout: compare.mjs reads two small committed files; a hang meets the job timeout.
- `low` VG: `labels.length === 0` unpinned: the `compare` rule pins the exact `--column` output.
- `low` AA: the one-number check runs only when the cell starts with `<n> of <m>`: the spec's literal wording; ruled.
- `low` AA: the Verification grep's pathspec and expectation: fix edits the spec's own command (rejected by triage rule).
- `note` AA: AC2 (CI green) cannot be checked under the CI hold: the lead's CI gate owns it.

## Ruled README change

Verbatim text (the Contest Planner's rulings of 2026-11-12, part (b) and the 02:05Z section). `<FILL: ...>` marks the only values implement writes, each from `node eval/compare.mjs --column eval/results`.

**C1. End of "## Measured"** -- after the line that starts "Where the money goes and how to cap it", a blank line, then the block below, which therefore sits directly before `## More` (Planner condition 4 of Story 0.30):

```markdown
### With the agent and with fixed rules only

Fixed rules only is OcuTalon's own fallback, the one it uses when it has no model key. It ran with no model and no key on <FILL: date> on the recorded evaluation set ([eval](eval)): <FILL: main-items> routine items and <FILL: main-incidents> incidents in the main set, plus 12 held-out cases (8 routine items and 4 incidents) written for this comparison. The held-out cases' expected answers were committed ([6af31dab](https://github.com/jbrandtmse/OcuTalon/commit/6af31dab5f265ca76343127c8b2ee4d7c3cd7970)) before either side ran on them, and a CI check keeps their names and text out of every prompt and mock scenario. The agent's column is measured on the same cases with Claude Haiku 5.5 at the release 1.0.9 evaluation. Rules written for these exact cases could score higher; this measures what the model adds to OcuTalon itself.

| What was measured | With the agent (Claude Haiku 5.5) | Fixed rules only |
| --- | --- | --- |
| Routine attention decisions right (main set) | measured at release 1.0.9 | <FILL: row 1> |
| Incidents with the right cause and the right field or item at fault (main set) | measured at release 1.0.9 | <FILL: row 2> |
| Held-out cases right (8 items, 4 incidents) | measured at release 1.0.9 | <FILL: row 3> |
| Items that needed you now but weren't told now | measured at release 1.0.9 | <FILL: row 4> |
| Unsafe outcomes | measured at release 1.0.9 | <FILL: row 5> |
| Cost of one attention decision | measured at release 1.0.9 | <FILL: row 6> |
| Largest model request | measured at release 1.0.9 | <FILL: row 7> |

An unsafe outcome is a change made without a person's approval, a prompt injection that led to an action, or a false all-clear. The numbers come from `bash eval/run.sh --rules-only`, set beside the agent's run by `node eval/compare.mjs`.
```

**C2. "What OcuTalon does"** -- since Story 0.30 this section is in `GUIDE.md` (its paragraph that starts `**What changes without the agent?** Worked out from the expected answers`, GUIDE.md line 77). That paragraph is replaced, whole, by the text below, with its link target `README.md#with-the-agent-and-with-fixed-rules-only` (the relative README link GUIDE.md already uses for `#measured`; approved by the Planner 2026-11-12 ~19:30Z):

```markdown
**What changes without the agent?** OcuTalon's fixed rules were run on the same evaluation cases as the agent, with no model, and the two are measured side by side in [With the agent and with fixed rules only](README.md#with-the-agent-and-with-fixed-rules-only).
```

## Spec Change Log

- 2026-11-12 ~19:15Z (lead, after Story 0.30 and the Contest Planner's PUBLIC TEXT ruling, prompts/story-029-rulings-20261112.md, binding): "1.0.9" in both places (1.0.8 was cut without this story); the added sentence at the end of the H3's first paragraph; the `comparison` rule's one-number-per-measure check; C1 placed before `## More`; C2 now in GUIDE.md with the relative README link; README stays at most 2,300 words (`word-cap`, Story 0.30). Fill values verified against `node eval/compare.mjs --column eval/results`: November 12, 24, 11; 6 of 24, 0 of 11, 2 of 12, 0, 0, none: no model request (x2).

- 2026-11-12 ~02:10Z, lead: split out of the original Story 0.27 plan (Part C) by the Contest Planner's 02:05Z ruling and the orchestrator; bullets moved whole; the R paragraph's last clause changed to the ruled option (c). Needs no new plan; re-check the Code Map's anchors on the tree after 0.27 merges.

- 2026-11-12, implement: no existing test-readme.sh or test-eval-set.sh rule pinned the old shape of "Measured" or GUIDE's old paragraph (`measured` pins only the eight row labels, which the new table's different labels do not touch), so no expectation was changed; the new rules are `comparison` (test-readme.sh) and `readme-column` (test-eval-set.sh).

## Review Triage Log

### 2026-11-12 - Review pass
- verdicts: 23 findings - high 0, medium 0, low 19, false 0, maybe-false 4
- findings:
  - `[low]` `[reject]` Blind: agent column is a placeholder in a judge-facing README - the placeholder and past-tense wording are the Planner's ruled text for feature (Design Notes); the RC fork replaces it before main; the fix would edit ruled text.
  - `[maybe-false]` `[defer]` Blind: no gate forces the placeholders to be replaced - deferred (medium, unverified); the RC fork's checklist is to grep for it; settle by confirming that step.
  - `[low]` `[reject]` Blind: two evaluation releases on one page / only the routine row cross-checked - ruling 3 of the Planner fixes the one-number check to the routine row and has the fork refresh the main table; fix would add rules the ruling did not ask for.
  - `[low]` `[reject]` Blind: held-out counts hardcoded, not checked against the report - the `held-out` and `held-out-frozen` rules pin the cases and the `2 of 12` total is checked by readme-column; unlikely to be met.
  - `[low]` `[reject]` Blind: date read from one report - the main and held-out runs are one rules-only run set; fix adds branches for an unreached case.
  - `[low]` `[reject]` Blind: no false-alarm row - the table rows are ruled text, applied verbatim.
  - `[false]` `[reject]` Blind: commit link may not resolve - `git cat-file -t 6af31dab...` is a commit and `origin/OCT-epic0` contains it.
  - `[low]` `[reject]` Blind: spec bookkeeping (Auto Run Result status, git grep caveat) - finalized at this step; the fix is to edit the spec's own text, which triage rejects; the caveat is already logged in Verification.
  - `[low]` `[reject]` Edge: agent routine cell not in `<n> of <m>` form skips the check - agent column text is deliberately not pinned (spec); extra guard is unneeded complexity.
  - `[low]` `[reject]` Edge: main routine row reworded gives a vague message - a filled cell would then be flagged, not passed; fail-closed.
  - `[low]` `[reject]` Edge: incident/held-out agent cells not cross-checked - same as the ruling-3 row above.
  - `[false]` `[reject]` Edge: extra README rows pass readme-column - `comparison` pins exactly the seven ruled labels in order, so extra rows fail there.
  - `[low]` `[reject]` Edge: held-out split not compared with the report - same as the held-out row above.
  - `[low]` `[reject]` Edge: spawnSync has no timeout - compare.mjs reads a small committed folder; unlikely.
  - `[low]` `[reject]` Edge: CRLF README - fails closed; the repo's README is LF.
  - `[low]` `[reject]` Edge: date pattern accepts "Foo 99" - the pattern is the spec's ruled one; readme-column checks the real date.
  - `[low]` `[reject]` Edge: GUIDE pointer drops the agent figures - ruled C2 text, verbatim.
  - `[maybe-false]` `[defer]` Edge: placeholder could ship on main - same root cause as the deferred placeholder-gate item.
  - `[low]` `[reject]` Edge: spec grep command now lists test-readme.sh - the phrase must exist in the rule that forbids it; already recorded in Verification.
  - `[low]` `[defer]` VG: st() accepts any flag, multi-clause mutations do not pin one clause - script-wide harness shape; deferred.
  - `[low]` `[reject]` VG: one-number check dormant on the real tree - only live once the fork fills the cell; pinned by two self-tests and a mutation line; no bad outcome now.
  - `[maybe-false]` `[defer]` VG: nothing pins the placeholder gone before main - same root cause as the deferred placeholder-gate item.
  - `[low]` `[reject]` Intent audit: agent column is a placeholder (reading R1 vs R2/R3) - descriptive; the ruled intent is R1; same as the first row.

## Design Notes

**Contest Planner ruling (2026-11-12 ~19:30Z, owner's delegation; prompts/story-029-rulings-20261112.md, binding).** (1) "1.0.9" in both places; the 1.0.9 RC fork fills the agent column from its RC run (variant F); "measured at release 1.0.9" never reaches main; a poor held-out result for the agent goes to the owner before the merge. (2) The added sentence at the end of the H3's first paragraph. (3) One number per measure: at the 1.0.9 RC, variant F also refreshes the main Measured table's eval rows and the intro's release line from the same run; the `comparison` rule checks that the main table's routine row and the agent column's routine cell agree once filled. (4) C2 with the relative README link approved; everything else verbatim; the tests approved.

**Governing ADs:** AD-22 (the comparison reports the product's own evaluation path), AD-19 (no key-like text). No AD is amended.

**"measured at release 1.0.9" on feature.** Variant R's agent-column text on feature only; the Planner's release-candidate fork replaces it with variant F's text before anything reaches main (its RC checklist greps for it). No test-readme rule pins the agent column, so the fork's change needs no rule change.

**PUBLIC TEXT beyond the ruling:** none. Cell forms come from the approved variant R draft: rows 1-3 `<right> of <total>`, rows 4-5 a bare count, rows 6-7 `none: no model request`; the date written as the README writes dates ("November 12").

**RELEASE TOOL items:** none.

Integration (Rule 1/2): not service-introducing. Consumes: Story 0.27's `eval/results/` and `compare.mjs --column`; Story 0.26's README sections. Consumed-by: the Planner's release fork (variant F).

Extend, don't copy: `comparison` follows `measured`'s pattern; `readme-column` reuses `compare.mjs --column`.

## Verification

Shared surfaces: `test-readme.sh`'s new rule `comparison`, the `public-text` phrase list and its `RULES` count; `test-eval-set.sh`'s new rule `readme-column`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands** (from the worktree root, one per call, each finishing in about 150 s):
- `node eval/compare.mjs --column eval/results` (once, after the copy) -- expected: the date, `<I>`, `<J>` and seven cells written into the README.
- `bash docker/tests/test-readme.sh` (loop, about 25 s) -- expected: `test-readme: all rules passed`.
- `/bin/bash docker/tests/test-readme.sh` (once) -- expected: the same under bash 3.2.
- `EVAL_SET_ONLY='readme-column cases' bash docker/tests/test-eval-set.sh` (loop) -- expected: PASS.
- `git grep -n -i 'never used for tuning' -- . ':!_bmad-output'` (once) -- expected: no output.
- `bash docker/tests/test-boundaries.sh` (loop) -- expected: `test-boundaries: all rules passed`.

Mutations (one per AC; record `mutation: <change> -> <test that went red>` here, revert, check `git status --short` and `git diff --stat` unchanged):
- AC README comparison: change one fixed-rules cell -> `readme-column`; restore the worked-out sentence -> `comparison`; add "never used for tuning" -> `public-text`.

mutation: README.md fixed-rules cell "6 of 24" changed to "7 of 24" -> `readme-column` (test-eval-set.sh: row "Routine attention decisions right (main set)": the fixed-rules cell is "7 of 24", compare.mjs --column gives "6 of 24")
mutation: the worked-out sentence ("Worked out from the expected answers of the recorded evaluation set.") appended to README.md -> `comparison` (test-readme.sh: the worked-out sentence is back)
mutation: "These cases were never used for tuning." appended to README.md -> `public-text` (test-readme.sh)
mutation: chk_comparison's one-number check weakened (the agent routine cell compared with itself) -> `comparison` self-test "a filled agent routine cell that differs from the main table: not flagged" (FAIL comparison: a broken copy was not flagged)
mutation: check-readme-column.mjs's date check disabled -> `readme-column` samples bad-date and bad-date-report (the rule does not flag the sample)
mutation: (code review) chk_measured's cut at the first H3 removed (the whole section read) -> `measured` self-test "a row removed whose label the comparison table repeats: not flagged"
mutation: (code review) chk_comparison's separator-row check disabled -> `comparison` self-test "the separator row changed: not flagged"
mutation: (code review) check-readme-column.mjs's three-cell check disabled -> `readme-column` (the rule does not flag the sample bad-row-four-cells)
Code review also filled the agent column on a scratch copy (routine cell 21 of 24, the rest 11 of 11): `comparison` and `measured` PASS, so no self-test depends on the placeholder text. The review's mutations ran on a scratch copy of the tree; the worktree was never mutated.
Each mutation was reverted; `git diff` of the tree was byte-identical to the state before it. The one-liner `git grep -n -i 'never used for tuning' -- . ':!_bmad-output'` now also lists docker/tests/test-readme.sh, which must hold the phrase (the forbidden-phrase pattern, its self-test and the header comment); README.md and GUIDE.md hold none.

## Auto Run Result

Status: done
Blocking condition: none

Summary: README.md gains the ruled C1 comparison H3 ("With the agent and with fixed rules only") at the end of "## Measured", its fixed-rules column filled from `node eval/compare.mjs --column eval/results` (November 12; 24; 11; 6 of 24, 0 of 11, 2 of 12, 0, 0, none, none); GUIDE.md's "What changes without the agent?" paragraph is replaced by the ruled C2 pointer. New rules `comparison` (test-readme.sh) and `readme-column` (test-eval-set.sh), with self-tests; "never used for tuning" added to `public-text`.

Files changed:
- README.md -- C1 block (2,171 words).
- GUIDE.md -- C2 paragraph.
- docker/tests/test-readme.sh -- rule `comparison`, `public-text` phrase, RULES and header.
- docker/tests/test-eval-set.sh -- rule `readme-column` with self-tests.
- this spec -- mutation lines, change log, triage log.

Review: 23 findings; 0 patches applied; 4 deferred (two root causes, see frontmatter); 19 rejected with reasons in the Review Triage Log. Follow-up review recommended: false.

Verification: `bash docker/tests/test-readme.sh` and `/bin/bash` (bash 3.2) all rules passed; `EVAL_SET_ONLY='readme-column cases'` passed; `bash docker/tests/test-boundaries.sh` passed; `git grep -i 'never used for tuning'` lists only docker/tests/test-readme.sh (the rule itself); five mutations demonstrated red and reverted.

Residual risks: the agent column reads "measured at release 1.0.9" until the Planner's release-candidate fork fills it (variant F); the paragraph pins "release 1.0.9" word for word.
