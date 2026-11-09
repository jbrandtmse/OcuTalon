---
title: 'Story 0.17: The README''s evaluation table shows release 1.0.4''s numbers'
type: 'chore'
created: '2026-11-08'
status: 'done'
baseline_revision: 'f9f8d891400a93c30b75e6c5d605906c32a227e5'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** README.md's "Measured" section still shows the numbers of the earlier real-model release evaluations (9 of 10, 19 of 22, $0.0005 to $0.0007, 9 to 10 cents a day). Release 1.0.4's evaluation (November 8) and the online demo's usage log for November 1 to 7 give newer numbers, and the page has no link to where the money goes.

**Approach:** Replace the intro line and five table rows with the approved text, and add the one linking paragraph after the table. The public text is already approved by the Contest Planner and is committed byte for byte. Move the one test pin that names the old numbers and intro to the new values.

## Boundaries & Constraints

**Always:**
- README.md line 28 (the line beginning "From the real-model release evaluations") becomes exactly: `From the real-model evaluation of release 1.0.4 (Claude Haiku 5.5, November 8), the persona sweep and the online demo's usage log for November 1 to 7:` (the apostrophe is a plain ASCII `'`).
- These table rows are replaced exactly; every other row stays byte-identical:
  - `| Incidents diagnosed with the right cause and fix | 11 of 11 (target: 9) |`
  - `| Routine attention decisions right | 21 of 24 (target: 22) |`
  - `| Cost of one attention decision | about $0.0001 on average, $0.0003 at most |`
  - `| Cost of diagnosing 50 failed orders | $0.0007 to $0.0012 |`
  - `| Model cost of the always-on online demo | about 9 to 11 cents a day |`
- Directly after the table and before "Two things to look at in the demo:", one paragraph with exactly one blank line before and one after: `Where the money goes and how to cap it, with the numbers: [What an always-on AI assistant costs to run](https://community.intersystems.com/post/what-always-ai-assistant-costs-run-real-numbers-iris).` (the `$` signs are literal; use an editor tool, not a shell heredoc).
- `docker/tests/test-readme.sh` `rule_measured`: the `mutate` awk moves to `19 of 22` becoming `21 of 24` with its mutation `21 of 24` becoming `20 of 24`, and the intro regex to `/^From the real-model evaluation of release/`. It still requires exactly 3 edits. The `readme-links` rule's `ALLOWED_HOSTS` gains one entry, `community.intersystems.com/post/what-always-ai-assistant-costs-run-real-numbers-iris` (a path-prefix entry: it allows that one post, with the query, fragment and `.git` forms the rule already accepts for a path entry, and no other address of the host), and `rule_readme_links` gains two `st_append` rows that must stay flagged (another community post; the listed post with more path). Nothing else in that file changes and no assertion is weakened.
- Any other pin in `docker/tests/` that names an old number or the old intro line moves to the new one the same way and is reported.

**Never:**
- No other product file changes. No change to any other README line, row or section.
- No change to the approved text, even by a character. A needed deviation is a `## Clarification Needed` beginning `PUBLIC TEXT:`.

</intent-contract>

## Code Map

- `README.md` L26-41 -- the "Measured" section: intro line (L28), table (L30-39; rows to change at L32, L33, L37, L38, L39), then a blank line and "Two things to look at in the demo:" (L41). Edit with the Edit tool.
- `docker/tests/test-readme.sh` L1339-1352 -- `rule_measured`; L1348 is the `mutate` line naming `19 of 22`, `18 of 22` and `/^From the real-model release evaluations/`. `chk_measured` (L517) pins only the heading and the eight row labels, so the new rows and paragraph do not trip it. The header comment (L17-18) says numbers are not pinned and needs no change.
- Searched `docker/tests/`, `release/`, `ci/` for `19 of 22`, `9 of 10`, `0.0005`, `9 to 10 cents`, `18 of 22` and the old intro: the only pin is L1348 (`release/records/1.0.0/rc4.md` holds an unrelated "109 of 109").
- `docker/tests/test-boundaries.sh` -- read only; must still pass.

## Tasks & Acceptance

**Execution:**
- `README.md` -- replace line 28, the five rows, and add the paragraph after the table, exactly as in Boundaries -- the approved public text.
- `docker/tests/test-readme.sh` -- edit the `mutate` line in `rule_measured` (the pin follows the new numbers and intro), add the one `ALLOWED_HOSTS` entry and the two negative `readme-links` rows named in Boundaries -- nothing else.

**Acceptance Criteria:**
- Given the edited README, when `git grep -n -e '9 of 10 (target' -e '19 of 22' -e '0.0005 to' -e '9 to 10 cents' -- README.md` runs, then it prints nothing.
- Given the edited README and pin, when `bash docker/tests/test-readme.sh` runs, then it passes with no self-test note that the measured rule's edit did not apply.
- Given the change, when `bash docker/tests/test-boundaries.sh` runs, then it passes.
- Given the change, when the diff since the baseline is read, then it touches only README.md and `docker/tests/test-readme.sh` (plus this spec), and the README text equals the approved text byte for byte.

## Spec Change Log

- Pipeline: one bmad-build-auto stage plans and implements; the runner's diff review replaces QA and code review — orchestrator ruling under the Planner's 'one-file change, text approved', 2026-11-09.
- Contract amended during implementation (planning-stage author, before any review): the first implement pass showed `bash docker/tests/test-readme.sh` fails in `readme-links` because the approved paragraph's address is not on `ALLOWED_HOSTS`, so the Done-when criterion cannot hold without it. The 'change nothing else in that file' line gave way to the narrowest allow-list entry (one post path, not the host) plus two negative rows that keep the allow-list closed. Known-bad state avoided: widening to the whole host, or leaving the suite red. KEEP: the `rule_measured` pin move and the approved text, unchanged.

## Review Triage Log

### 2026-11-08 — Review pass
- verdicts: 12 findings — high 0, medium 0, low 5, false 0, maybe-false 0 (7 are scope or public-text observations with no defect in the change)
- findings:
  - `[low]` `[reject]` Blind: no test keeps the new cost-article paragraph — the Measured rule deliberately pins only the heading and row labels (its header and the comment at the `mutate` line say numbers and wording are not pinned); a wording pin is a new assertion outside the story and more than a direct correction.
  - `[low]` `[reject]` Blind: the Tasks line for test-readme.sh was stale after the contract amendment — fix is a spec edit, rejected as a finding; the line was reconciled as housekeeping at finalize.
  - `[low]` `[reject]` Blind: the acceptance criteria do not check the added content — fix edits this spec; the byte-for-byte check was run at verification (below).
  - `[low]` `[reject]` Blind: unchanged rows (30 of 30, 0, 0) sit under an intro that dates the changed ones — the intro and rows are approved public text committed verbatim; a change is a public-text escalation, not a patch.
  - `[low]` `[reject]` Blind: the new numbers have no source in the diff — they equal the approved story text in epics.md; the source is the Planner's approval.
  - `[low]` `[reject]` Blind: the linked article's existence is unverified — a read-only HEAD request returned 200 for the exact address at review time.
  - `[low]` `[reject]` Blind: the dates carry no year and "November 1 to 7" will age — approved public text; the 2026-11-09 date is the orchestrator's ruling quoted verbatim.
  - `[low]` `[reject]` Blind: spec housekeeping left open (status, empty triage log) — finalize sets status and this log.
  - `[low]` `[reject]` Blind: the negative allow-list rows could cover more continuations — the rows pin the two risks of the narrow entry (another post, a longer slug); more rows add test code for no reachable README change.
  - `[low]` `[reject]` Edge: the path entry also accepts `.git`, `?query` and `#fragment` forms — the rule's existing semantics for every path entry; the spec wording now says so; tightening one entry would fork the rule.
  - `[low]` `[reject]` Edge: no check keeps the paragraph in the README — same as the first Blind row.
  - `[low]` `[reject]` Intent alignment (descriptive): the diff implements the outcome-first reading, and "change nothing else in that file" gave way to the narrowest allow-list entry plus two negative rows so the Done-when suite passes — recorded in the Spec Change Log and flagged in the report; no verification-gap findings.

## Design Notes

- Integration ACs (Rules 1, 2): No consumers in this story (docs-only). `Consumed-by: none`. `Consumes: none`.
- Governing AD ids (Rule 6): none. The story introduces no decision; it commits approved public text, and the Measured table's honesty convention (per-decision and per-order cost, never per step) is unchanged.
- Sibling reuse (Rule 2): the pin edit extends the existing `rule_measured` mutate line; no copy.
- Decided in-stage: the allow-list entry is the exact post path, a path-prefix form the rule already supports (it extends the existing list; no copy). It is flagged in the report because it goes one step past the dispatch's 'change nothing else in that file'.
- Decided in-stage: the spec's `created` date uses the system date (2026-11-08); the pipeline ruling line keeps the orchestrator's date verbatim.

## Verification

**Commands:**
- `git grep -n -e '9 of 10 (target' -e '19 of 22' -e '0.0005 to' -e '9 to 10 cents' -- README.md` (loop) -- expected: prints nothing
- `bash docker/tests/test-readme.sh` (loop) -- expected: passes, with no `st_note` that the measured rule's edit did not apply
- `bash docker/tests/test-boundaries.sh` (loop) -- expected: passes

Shared surfaces: the README's Measured table (pinned by docker/tests/test-readme.sh).

mutation: README's intro line reverted to the old "From the real-model release evaluations (...)" text (the moved pin's `/^From the real-model evaluation of release/` then matches nothing) → `rule_measured` records the self-test note 'an edit of the numbers or the intro did not apply' and `bash docker/tests/test-readme.sh` goes red (`FAIL measured`); reverted, `git status --short`, `git diff --stat` and `git diff` byte-identical to before.

mutation: the new `ALLOWED_HOSTS` entry widened from the post path to the bare host `community.intersystems.com` → the two new `readme-links` rows ('not flagged') go red (`FAIL readme-links`); reverted, tree byte-identical.

## Auto Run Result

Status: done
Blocking condition: none

Summary: README.md's Measured section now reads release 1.0.4's numbers (intro line, five rows) and carries the approved link paragraph after the table, all committed byte for byte. `docker/tests/test-readme.sh` follows: the `rule_measured` pin moved to `21 of 24` / `20 of 24` and the intro regex `/^From the real-model evaluation of release/`; the `readme-links` allow-list gained the exact article post path with two negative rows (the new address otherwise failed `readme-links`).

Files changed:
- `README.md` -- intro line, five rows, link paragraph.
- `docker/tests/test-readme.sh` -- measured pin moved; one `ALLOWED_HOSTS` entry; two `readme-links` negative rows.
- this spec.

Review: 12 findings, 0 patches, 0 deferred, 12 rejected with reasons in the triage log. Follow-up review recommended: false (no patched entries).

Verification: `git grep` for the old strings printed nothing (exit 1); `bash docker/tests/test-readme.sh` ended `all rules passed` with no self-test note; `bash docker/tests/test-boundaries.sh` ended `all rules passed`; both `mutation:` lines applied, observed red and reverted with the tree byte-identical; the review layer's own run of test-readme.sh passed.

Residual risks: the unchanged rows (30 of 30, 0, 0) sit under an intro that now dates the changed rows to release 1.0.4 (approved text, not ours to change). The allow-list entry goes one step past the dispatch's "change nothing else in that file"; reported to the orchestrator.
