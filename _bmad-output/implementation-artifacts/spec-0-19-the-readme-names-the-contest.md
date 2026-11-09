---
title: 'Story 0.19: The README names the contest'
type: 'chore'
created: '2026-11-09'
status: 'done'
baseline_revision: '0875e90a96e999f18d83750bc5335edaff516b09'
baseline_commit: '0875e90a96e999f18d83750bc5335edaff516b09'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** README.md's "## Contest checklist" opens with `What OcuTalon uses, and where to check each one:` and never says which contest OcuTalon is entered in, so a judge cannot see what the entry is judged against.

**Approach:** Replace that one line with the owner-approved sentence that names the contest and links its Developer Community post, followed by `What it uses, and where to check each one:`. The text is public and approved verbatim; it is committed byte for byte.

## Boundaries & Constraints

**Always:**
- The replacement line is exactly (ASCII only): `OcuTalon is an entry in the [InterSystems Programming Contest: AI Agents in Interoperability Workflows](https://community.intersystems.com/post/intersystems-programming-contest-ai-agents-interoperability-workflows). What it uses, and where to check each one:`
- The old line `What OcuTalon uses, and where to check each one:` appears exactly once (under `## Contest checklist`); the replacement keeps the empty lines around it.
- README.md is the only product file changed.

**Never:**
- Never reword the approved text or "fix" its punctuation.
- Never change `docker/tests/test-readme.sh` (`community.intersystems.com` is already on its allow-list).
- If a README rule refuses the text: HALT `blocked`, blocking condition `intent gap: README rule <name> refuses the approved text: <rule output>`.

</intent-contract>

## Code Map

- `README.md` -- the line `What OcuTalon uses, and where to check each one:` sits under `## Contest checklist` (about line 376), above the `| Item | Where to check it |` table; it occurs exactly once.
- `docker/tests/test-readme.sh` -- read only. `ALLOWED_HOSTS` (line 1223) already lists `community.intersystems.com`; `url_allowed` and the readme-links rule check every URL of the README against it.

## Tasks & Acceptance

**Execution:**
- `README.md` -- replace the one line under `## Contest checklist` with the approved sentence -- DW-1020: name the contest with a link to its post. Touch no other byte.

**Acceptance Criteria:**
- Given README.md's `## Contest checklist` section, when this story merges, then the line `What OcuTalon uses, and where to check each one:` is replaced by exactly the approved line and nothing else in README.md changes (DW-1020).
- Given the change, when this story merges, then README.md is the only file changed, `bash docker/tests/test-readme.sh` passes every rule, `docker/tests/test-boundaries.sh` passes, and lane-a is green.

### Review Findings

Code review 2026-11-09 (four layers; 0 decision-needed, 3 patch, 0 defer, 8 rejected). The README line is byte-exact to the Always rule and to epics.md, README.md has one hunk (1+/1-), and both checks pass.

- [x] [Review][Patch] AC1's pinning check had no `mutation:` line under `## Verification` (Rule 19 LOW) [spec `## Verification`] -- mutation applied in review, red observed, reverted byte-identical; line written.
- [x] [Review][Patch] AC2's pinning check had no `mutation:` line (Rule 19 LOW) [spec `## Verification`] -- mutation applied in review (`readme-links` red), reverted byte-identical; line written.
- [x] [Review][Patch] The `git diff --stat` pin read the working tree, so it printed nothing once the build was committed (not reproducible) [spec `## Verification`] -- replaced by a baseline-pinned `git diff --numstat 0875e90a -- . ':(exclude)_bmad-output'`.

Rejected:
- `low` AC2's "README.md is the only file changed" is literally false for the commit (the spec and bookkeeping also change) -- the Always rule scopes it to product files, which holds; the fix is a spec edit.
- `low` The earlier triage row sent "contest named only in the checklist" to Story 0.21, whose header does not name the contest -- the owner approved the text and its place (DW-1020); moving or adding public text is the owner's call; by-design.
- `low` Nothing in CI pins the approved sentence after merge -- the spec forbids changing `docker/tests/test-readme.sh`; by-design (reopen via a spec amendment if a later README story rewrites the checklist).
- `low` The `dev_complete` row records `story_base=0875e90a` while `stage_spawned` recorded `ec94259d` -- lead-owned cycle log, which this stage may not write; the two bases differ by bookkeeping only; handed to the lead.
- `low` The `dev_complete` row's `files=2` and `loc_added=1 loc_removed=1` disagree, and it omits `nfr_tripwires=` and `adr_violations_surfaced=` -- lead-owned cycle log; handed to the lead.
- `false` The spec status `done` contradicts sprint-status `review` -- `done` is bmad-build-auto's contract status (Rule 4); review state lives in sprint-status.
- `false` "lane-a is green" is unverified -- CI on the pushed head is the lead's gate; the residual risk is already stated.
- `false` The post URL was never checked -- a read-only fetch in review returned HTTP 200 with the contest's title.

## Spec Change Log

## Review Triage Log

### 2026-11-09 -- Review pass
- verdicts: 11 findings -- high 0, medium 0, low 9, false 2, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: the contest is named only in the checklist, not near the top -- the intent fixes the line and section; a header change is Story 0.21's scope; fix would exceed the intent.
  - `[low]` `[reject]` Blind: AC says "only file changed" while the Always rule says "only product file" -- the AC mirrors epics.md; the spec file is the story's own bookkeeping; fix is a spec edit.
  - `[low]` `[reject]` Blind: nothing checks that the post URL resolves -- the text is owner-approved verbatim and public; a live check is not asked for and the text may not be reworded either way.
  - `[low]` `[reject]` Blind: nothing guards the sentence after merge -- the intent forbids changing test-readme.sh; closed by design.
  - `[low]` `[reject]` Edge: "only file changed" vs spec file in the diff -- same as the second Blind row.
  - `[low]` `[reject]` Verification-gap: the mutation line sits under Design Notes, not Verification -- fix is a spec edit, which triage rejects; the mutation was run by the implementer and is recorded in the Auto Run Result.
  - `[false]` `[reject]` Verification-gap: the fixed-string grep is a source-text match -- the reviewer's own evidence shows it goes red on revert, so it can fail; it is the right check for verbatim text.
  - `[low]` `[reject]` Verification-gap: "lane-a green" has no command in Verification -- the dispatch makes CI the full verification for this docs-only story; a command cannot run lane-a locally.
  - `[low]` `[reject]` Verification-gap, other: `git diff --stat` expects README only, false once the spec is committed -- the check runs before the finalize commit and counts tracked changes only.
  - `[low]` `[reject]` Intent-alignment: nothing checks the URL points at the contest post -- reading D is not in the intent; the owner approved the URL.
  - `[false]` `[reject]` Intent-alignment: nothing checks the rendered link -- the link is plain Markdown on one line, blank lines around it untouched, and test-readme.sh's link rules pass on it.

## Design Notes

- Governing architecture decisions: none (a one-line README docs change).
- No consumers in this story (docs-only).
- Shared surfaces: README.md contest-checklist intro line (docker/tests/test-readme.sh asserts on README.md).
- Decided in-stage: none.
- mutation: revert the README line to its old text; `grep -c 'OcuTalon is an entry in the \[InterSystems Programming Contest: AI Agents in Interoperability Workflows\]' README.md` must go from 1 to 0 (red); restore the approved line and show `git diff --stat` and the file hash identical to the pre-mutation state.

## Verification

**Commands:**
- `bash docker/tests/test-readme.sh` (loop) -- expected: passes ALL rules, prints `test-readme: all rules passed`
- `bash docker/tests/test-boundaries.sh` (loop) -- expected: passes
- `grep -c -F 'OcuTalon is an entry in the [InterSystems Programming Contest: AI Agents in Interoperability Workflows](https://community.intersystems.com/post/intersystems-programming-contest-ai-agents-interoperability-workflows). What it uses, and where to check each one:' README.md` (loop) -- expected: 1, and `grep -c -F 'What OcuTalon uses, and where to check each one:' README.md` expected: 0
- `git diff --numstat 0875e90a -- . ':(exclude)_bmad-output'` -- expected: exactly one row, `1`, `1`, `README.md` (tab-separated) (the only product file, one line in and one out), before or after the build commit
- mutation (AC1): README.md's approved line reverted to `What OcuTalon uses, and where to check each one:` → the approved-line grep went 1 to 0 and the old-line grep 0 to 1 (red), and the baseline numstat printed nothing; restored, README.md's shasum and `git status --short`/`git diff --stat` matched the pre-mutation state (code review 2026-11-09)
- mutation (AC2): the link's host changed from `community.intersystems.com` to `community.example.org` → `bash docker/tests/test-readme.sh` exited 1 with `FAIL readme-links` (not on the allow-list); restored byte-identical as above (code review 2026-11-09)

## Auto Run Result

Status: done
Blocking condition: none

- Summary: the line under `## Contest checklist` (README.md:376) now reads the owner-approved sentence naming the InterSystems Programming Contest: AI Agents in Interoperability Workflows with a link to its Developer Community post, then `What it uses, and where to check each one:` (DW-1020).
- Files changed: `README.md` (one line replaced); this spec. `docker/tests/test-readme.sh` untouched.
- Review: 11 findings from four layers (low 9, false 2); 0 patches applied, 0 deferred, 11 rejected with reasons in the Review Triage Log.
- Follow-up review recommended: false (no patches).
- Verification: `bash docker/tests/test-readme.sh` -> `test-readme: all rules passed` (no rule refused the text); `bash docker/tests/test-boundaries.sh` -> `test-boundaries: all rules passed`; the fixed-string grep of the approved line gives 1 and of the old line 0; `git diff --stat` shows README.md only, 1 insertion and 1 deletion; diff adds no non-ASCII bytes. Mutation: with the line reverted to its old text the pin grep went 1 to 0 (red); after restoring, README.md's shasum matched the pre-mutation value and the tree was byte-identical.
- Residual risks: lane-a green is confirmed by CI only; the post URL was not fetched (owner-approved verbatim).
