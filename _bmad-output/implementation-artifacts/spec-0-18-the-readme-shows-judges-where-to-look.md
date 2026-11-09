---
title: 'Story 0.18: The README shows judges where to look'
type: 'chore'
created: '2026-11-08'
status: 'done'
baseline_revision: '4aeaff9208a6fee74e04462f73e2b9ab61b96b35'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A judge scoring the entry cannot find each claim and its evidence from the top of README.md: there is no link bar, no per-criterion "where to look" table, no list of what is new since 1.0.0, no answer to "what changes without the agent?", and no contest checklist with proof.

**Approach:** Insert the Contest Planner's approved Edits 1 to 5 into README.md at their anchors, and set `docker/tests/test-readme.sh`'s link allow-list to the approved Edit 6 line, merged with Story 0.17's change. The public text is already approved and is committed byte for byte, extracted by a script from the approved edit file, never retyped.

## Boundaries & Constraints

**Always:**
- Source of truth, read only and outside the repository, never copied into it: the Planner's final edit file `readme-judges-1.0.5-FINAL.md`, section (b). Only the fenced blocks of Edits 1 to 5 (`~~~markdown` to `~~~`) and Edit 6's "New line" are edits; sections (a), (c), (d) and the HTML comments are notes and are never committed.
- Placement, each anchor a whole line that must match exactly once (else HALT `blocked`, `intent gap`, naming the anchor):
  - Edit 1 (link bar, one line, U+00B7 separators kept as the literal character): before the line starting `Start with the online demo, at https://demo.ocutalon.com `, followed by one empty line.
  - Edits 2 and 3: after the line `4. Follow the demo guide at the top of the page.`: one empty line, block 2, one empty line, block 3 (the empty line already after step 4 then separates block 3 from `## What's interesting`).
  - Edit 4 (one paragraph): before the line starting `**With a model, and without one.**`, followed by one empty line.
  - Edit 5: before the line `## Credits and licences`, followed by one empty line.
- README.md changes by additions only: `git diff --numstat` shows 0 deleted lines.
- `docker/tests/test-readme.sh` `ALLOWED_HOSTS=` becomes exactly Edit 6's New line: `ALLOWED_HOSTS='localhost demo.ocutalon.com youtu.be github.com/jbrandtmse/OcuTalon github.com/bmad-code-org claude.com console.anthropic.com docs.anthropic.com evaluation.intersystems.com docs.intersystems.com www.intersystems.com ideas.intersystems.com docs.docker.com learn.microsoft.com community.intersystems.com openexchange.intersystems.com'`. The host entry `community.intersystems.com` replaces Story 0.17's post-path entry (host form only, never both); `community.intersystems.com` and `openexchange.intersystems.com` appear once each; nothing else is added.
- Remove exactly the two `st_append` rows of `rule_readme_links` that only 0.17's narrower entry could pass: `'a community post that is not the listed one'` and `'the listed community post with more path'`. Every other self-test (example.org, github.com/someone-else, the claude.com look-alikes, dot segments, ...) still flags. Story 0.17's `rule_measured` pin stays as it is.

**Never:**
- No reword, reorder or work-around of the approved text, and no test loosening. If any rule of `bash docker/tests/test-readme.sh` or `bash docker/tests/test-boundaries.sh` fails because of the verbatim text, HALT with status `blocked` and blocking condition `intent gap: PUBLIC TEXT: rule <name> fails on README line <n>: <the rule's message>`.
- No link to the AI Hub bug reports: no bug-report repository on the allow-list.
- No other README line, row or section changes; no other product file changes.

</intent-contract>

## Code Map

- `README.md` (line numbers are the baseline file's) L9 `## Try it in two minutes`, L11 the `Start with the online demo, ...` paragraph (Edit 1 anchor), L18 `4. Follow the demo guide at the top of the page.` (Edits 2 and 3 anchor; L19 is empty, L20 `## What's interesting`), L93 `**With a model, and without one.** ...` (Edit 4 anchor), L349 `## Credits and licences` (Edit 5 anchor). Each anchor verified to match exactly one whole line.
- `docker/tests/test-readme.sh` L1223 `ALLOWED_HOSTS=` (Story 0.17 put the exact post path in it); L1828-L1829 the two 0.17 `st_append` rows to remove; `url_allowed` (L1224-L1242) accepts a bare-host entry for any path of that host.
- The approved edit file's notes list the README rules the text was fitted to (`top`, `key-account`, `dev-only`, `telegram-demo`, `public-text`, `readme-links` anchors and paths); the real check is the script itself.
- `docker/tests/test-boundaries.sh` -- read only; must still pass.
- Scratch extraction script lives only under the run's scratch folder, never in the repository.

## Tasks & Acceptance

**Execution:**
- `README.md` -- insert Edits 1 to 5 at their anchors with a small Python script that reads the approved edit file and inserts the fenced inner lines byte for byte -- approved public text, no retyping.
- `docker/tests/test-readme.sh` -- set `ALLOWED_HOSTS` to Edit 6's New line; delete the two 0.17 negative rows named above -- nothing else.

**Acceptance Criteria:**
- Given the edited README, when `git diff --numstat -- README.md` runs, then it shows 0 deleted lines, and the inserted lines equal the approved blocks byte for byte at the four anchors.
- Given the change, when `bash docker/tests/test-readme.sh` runs, then it prints `test-readme: all rules passed`.
- Given the change, when `bash docker/tests/test-boundaries.sh` runs, then it passes.
- Given the edited test, when `grep -c 'community.intersystems.com'` runs on the `ALLOWED_HOSTS=` line, then it prints 1, `openexchange.intersystems.com` appears once on it, and no AI Hub bug-report repository is on it.
- Given the change, when the diff since the baseline is read, then it touches only README.md and `docker/tests/test-readme.sh` (plus this spec).

## Spec Change Log

- Pipeline (orchestrator ruling, same as Story 0.17): this ONE bmad-build-auto run plans the spec and implements it, self-reviews with its review layers and finalizes `status: done` with its one local finalize commit; the runner's byte-for-byte diff review replaces separate QA and code-review stages.

## Review Triage Log

### 2026-11-08 - Review pass
- verdicts: 18 findings - high 0, medium 0, low 15, false 3, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: the link bar sits under "Try it in two minutes", not at the top, and repeats the teaser link - placement and text are the approved Edit 1 anchor; a move is a public-text change, not a patch.
  - `[low]` `[reject]` Blind: the two H3 sections interrupt the quick-start - placement after step 4 is the approved Edits 2 and 3 anchor (the Planner's notes say why they cannot be H2).
  - `[low]` `[reject]` Blind: the checklist has no video or Open Exchange row - approved Edit 5 text; the Planner's notes say the full video is not published.
  - `[low]` `[reject]` Blind: article and Open Exchange URLs are no longer pinned by the allow-list - the host entry and the two removed rows are exactly the story's acceptance criterion.
  - `[false]` `[reject]` Blind: "Send my digest now" is a settings button, not a chat phrase - the Planner's sources cite the tool (Tools/DigestTools.cls:23) and the online demo-path spec (L88-90) that asks for it in the chat; the sentence is approved text.
  - `[low]` `[reject]` Blind: counts in the new text can go stale and no rule backs them - the reviewer re-counted them and they hold today; the Planner's cut-time recheck list covers them; a new rule is outside the story ("add nothing else").
  - `[false]` `[reject]` Blind: the spec file still reads in-review with an empty triage log - finalize sets status and this log; the fix edits this spec.
  - `[low]` `[reject]` Edge: no negative self-test for a look-alike host of the new entries - the bare-host branch of `url_allowed` is shared with `claude.com`, whose look-alike rows still flag; a new row is outside the approved change.
  - `[low]` `[reject]` Edge: the two removed rows leave no self-test for the new entries - the removal is the story's criterion.
  - `[low]` `[reject]` Edge: hard-coded counts have no recount rule - same as the Blind row on counts.
  - `[low]` `[reject]` Edge: the 6 of 24 and 11 figures are not pinned to eval/ - they are approved text worked out by the Planner; the cut-time recheck covers them.
  - `[low]` `[reject]` Verification-gap: nothing pins the presence of the new sections, so a later edit can delete them - no pinning rule is in the approved change and the story says add nothing else to the test file; a later story may add one.
  - `[low]` `[reject]` Verification-gap: the numeric claims are unpinned - same as above; `rule_measured` leaves numbers unpinned by design.
  - `[low]` `[reject]` Verification-gap: the widened allow-list has no negative row of its own - the shared branch is covered by the `claude.com` look-alike rows.
  - `[low]` `[reject]` Verification-gap (Rule 19): AC1, AC3 and AC5 have no `mutation:` line - they are diff and script checks, not tests; the two pins this story touched (the Open Exchange entry and the 0.17 rows) carry a mutation each, both applied, observed red and reverted with the tree byte-identical.
  - `[low]` `[reject]` Verification-gap, other: the new paragraph says 21 of 24 while the Measured table targets 22 - approved text, and the table's target is the table's own.
  - `[low]` `[reject]` Verification-gap, other: `rule_top` forbids a "Contest task" heading and the new "Contest checklist" is close in shape - it does not match today, and the Planner's notes record that "Contest checklist" passes.
  - `[false]` `[reject]` Intent alignment (descriptive): the diff implements the literal reading (verbatim insertion, allow-list swap, two rows removed) - no defect is claimed; its divergence note (structural checks versus link and claim accuracy) is the same observation as the rejected rows above.

## Design Notes

- Integration ACs (Rules 1, 2): No consumers in this story (docs-only). `Consumed-by: none`. `Consumes: none`.
- Governing AD ids (Rule 6): none. The story introduces no decision; it commits public text the Contest Planner approved under the owner's delegation.
- Sibling reuse (Rule 2): the allow-list edit extends the existing `ALLOWED_HOSTS` line in place; no copy.
- Decided in-stage: the text is inserted by script from the approved file so the U+00B7 separators, `$`, backticks, `*` and `|` survive unchanged.
- Decided in-stage: the spec's `created` date uses the system date (2026-11-08).

## Verification

**Commands:**
- `bash docker/tests/test-readme.sh` (loop) -- expected: passes ALL rules, prints `test-readme: all rules passed`
- `bash docker/tests/test-boundaries.sh` (loop) -- expected: passes
- `grep '^ALLOWED_HOSTS=' docker/tests/test-readme.sh | grep -o 'community.intersystems.com' | wc -l` (loop) -- expected: 1, and `openexchange.intersystems.com` likewise 1
- `git diff --numstat -- README.md` (loop) -- expected: deleted column 0

Shared surfaces: README.md (pinned by docker/tests/test-readme.sh) and the readme-links allow-list.

mutation: drop `openexchange.intersystems.com` from the `ALLOWED_HOSTS` line -> `readme-links` goes red (the link bar's and the checklist's Open Exchange address is off the list); revert, tree byte-identical.

mutation: restore Story 0.17's two removed `st_append` rows with the host entry on the list -> `readme-links` self-test goes red (they are no longer flagged); revert, tree byte-identical.

## Auto Run Result

Status: done
Blocking condition: none

Summary: README.md carries the Planner's approved Edits 1 to 5 (link bar, "For judges: where to look", "New since 1.0.0", "What changes without the agent?", "Contest checklist"), inserted by script from the approved edit file, 42 added lines and 0 deleted. `docker/tests/test-readme.sh` has Edit 6's exact `ALLOWED_HOSTS` line (host entries `community.intersystems.com` and `openexchange.intersystems.com` once each, Story 0.17's post-path entry gone) and no longer has the two 0.17 `st_append` rows only that entry could pass.

Files changed:
- `README.md` -- 42 added lines at four anchors.
- `docker/tests/test-readme.sh` -- `ALLOWED_HOSTS` line; two `st_append` rows removed.
- this spec.

Review: 18 findings, 0 patches, 0 deferred, 18 rejected with reasons in the triage log (low 15, false 3). Follow-up review recommended: false (no patched entries).

Verification: an independent script rebuilt the expected README and Edit 6 line from the approved file and both equal the tree byte for byte; `bash docker/tests/test-readme.sh` ended `test-readme: all rules passed` (no rule failed on the verbatim text); `bash docker/tests/test-boundaries.sh` ended `test-boundaries: all rules passed`; the `ALLOWED_HOSTS` line has `community.intersystems.com` once and `openexchange.intersystems.com` once; `git diff --numstat -- README.md` shows `42 0`. Both `mutation:` lines applied, observed red (`FAIL readme-links`; `FAIL readme-links: a broken copy was not flagged`) and reverted with `git status --short` and `git diff` byte-identical.

Residual risks: no rule pins the presence or the counts of the new sections, so a later edit can drop them unseen (a later story's call); the allow-list now accepts any path on the two hosts, as the story intends.
