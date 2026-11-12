---
title: "Story 0.29: The README's comparison of the agent and the fixed rules, filled from the committed rules-only report"
type: 'feature'
created: '2026-11-12'
status: 'ready-for-dev'
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
- "never used for tuning" appears nowhere in the README. "measured at release 1.0.8" is variant R's agent-column text on feature only (the Planner's release-candidate fork replaces it).
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
  - new rule `comparison`: "## Measured" ends with the H3 "With the agent and with fixed rules only" (its only H3, after the money line), holding the ruled paragraph word for word (the date matched as `[A-Z][a-z]+ [0-9]{1,2}`, `<I>` and `<J>` as numbers), the ruled header row, the seven ruled row labels in order as first cells, a non-empty agent and fixed-rules cell in each row, and the ruled sentence under the table; the ruled pointer paragraph sits in "What OcuTalon does" directly above the model paragraph, and its link resolves to the H3; "Worked out from the expected answers" appears nowhere. The agent column's text is not pinned (the release fork replaces it).
  - `public-text`: add "never used for tuning" to the forbidden phrases (with a self-test).
  - Self-tests, one bad variant per way to break `comparison` (H3 renamed or moved, a word of the paragraph changed, the commit link changed, a label reworded or two swapped, the sentence changed, the pointer's anchor changed, the worked-out sentence restored). Update `RULES` and the header comment.
- `docker/tests/test-eval-set.sh` -- new rule `readme-column`: the README comparison's fixed-rules column, its date, `<I>` and `<J>` equal `node eval/compare.mjs --column eval/results`, row by row. Self-tests: a README cell changed, a report value changed, a row missing.

**Acceptance Criteria:**
- Given the README comparison, when it is read, then it is the ruled variant R text, and every fixed-rules cell, the date, `<I>` and `<J>` equal `compare.mjs --column eval/results`; `readme-column` and `comparison` pass and fail on their bad variants; "never used for tuning" is nowhere in the README.
- Given CI on this story's head, when it finishes, then every workflow is green.

## Ruled README change

Verbatim text (the Contest Planner's rulings of 2026-11-12, part (b) and the 02:05Z section). `<FILL: ...>` marks the only values implement writes, each from `node eval/compare.mjs --column eval/results`.

**C1. End of "## Measured"** -- after the line that starts "Where the money goes and how to cap it", a blank line, then:

```markdown
### With the agent and with fixed rules only

Fixed rules only is OcuTalon's own fallback, the one it uses when it has no model key. It ran with no model and no key on <FILL: date> on the recorded evaluation set ([eval](eval)): <FILL: main-items> routine items and <FILL: main-incidents> incidents in the main set, plus 12 held-out cases (8 routine items and 4 incidents) written for this comparison. The held-out cases' expected answers were committed ([6af31dab](https://github.com/jbrandtmse/OcuTalon/commit/6af31dab5f265ca76343127c8b2ee4d7c3cd7970)) before either side ran on them, and a CI check keeps their names and text out of every prompt and mock scenario. The agent's column is measured on the same cases with Claude Haiku 5.5 at the release 1.0.8 evaluation.

| What was measured | With the agent (Claude Haiku 5.5) | Fixed rules only |
| --- | --- | --- |
| Routine attention decisions right (main set) | measured at release 1.0.8 | <FILL: row 1> |
| Incidents with the right cause and the right field or item at fault (main set) | measured at release 1.0.8 | <FILL: row 2> |
| Held-out cases right (8 items, 4 incidents) | measured at release 1.0.8 | <FILL: row 3> |
| Items that needed you now but weren't told now | measured at release 1.0.8 | <FILL: row 4> |
| Unsafe outcomes | measured at release 1.0.8 | <FILL: row 5> |
| Cost of one attention decision | measured at release 1.0.8 | <FILL: row 6> |
| Largest model request | measured at release 1.0.8 | <FILL: row 7> |

An unsafe outcome is a change made without a person's approval, a prompt injection that led to an action, or a false all-clear. The numbers come from `bash eval/run.sh --rules-only`, set beside the agent's run by `node eval/compare.mjs`.
```

**C2. "What OcuTalon does"** -- the paragraph that starts `**What changes without the agent?** Worked out from the expected answers` is replaced, whole, by:

```markdown
**What changes without the agent?** OcuTalon's fixed rules were run on the same evaluation cases as the agent, with no model, and the two are measured side by side in [With the agent and with fixed rules only](#with-the-agent-and-with-fixed-rules-only).
```

## Spec Change Log

- 2026-11-12 ~02:10Z, lead: split out of the original Story 0.27 plan (Part C) by the Contest Planner's 02:05Z ruling and the orchestrator; bullets moved whole; the R paragraph's last clause changed to the ruled option (c). Needs no new plan; re-check the Code Map's anchors on the tree after 0.27 merges.

## Review Triage Log

## Design Notes

**Governing ADs:** AD-22 (the comparison reports the product's own evaluation path), AD-19 (no key-like text). No AD is amended.

**"measured at release 1.0.8" on feature.** Variant R's agent-column text on feature only; the Planner's release-candidate fork replaces it with variant F's text before anything reaches main (its RC checklist greps for it). No test-readme rule pins the agent column, so the fork's change needs no rule change.

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Split out of the original Story 0.27 plan by the lead on the Contest Planner's 02:05Z ruling; implement after Story 0.27 merges.
