---
title: 'Story 36.3: Link the worked Jira example from the admin docs'
type: 'chore'
created: '2026-11-14'
status: 'done'
baseline_revision: '0b90b8d7a9f9ac87a5e0c5b1c6a7446d5333637f'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-36-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** FR-10 needs the admin guide, as well as the security overview, to say that an MCP tool that runs operating-system commands or arbitrary code must be classified Risky. Story 22.6 shipped the worked example `docs/mcp-jira-example.md` and the overview's line, but the admin guide neither links the example nor carries the sentence. The AC names "the README's admin section", which Story 0.30 moved word for word into `GUIDE.md` "## For admins and developers" on 2026-11-12. The README has no admin section now, and the README's More paragraph links that guide section.

**Approach:** Add the Planner-approved paragraph G2 (ruling M(4), 2026-11-13 ~09:30Z) as the first paragraph of `GUIDE.md` "## For admins and developers". It holds the example's sentence verbatim and a relative link to `docs/mcp-jira-example.md`. Pin both with a new `admin-mcp` rule in `docker/tests/test-readme.sh`. Implementation waits for the Planner's ruling on gate item 1 (the target file).

## Boundaries & Constraints

**Always:** G2 word for word as ruled, with no new words. The link is relative (`docs/mcp-jira-example.md`), as GUIDE.md already links `docs/bridge-guide.md` and `docs/install-ipm.md`; Story 0.30's AC allows relative links inside GUIDE.md. The guide's sentence equals line 36 of the example as a whole line. Every existing `test-readme.sh` rule stays green.

**Never:** Edit `README.md`; its Measured table, the filled comparison, the word count and the More paragraph stay byte-identical. Never edit `docs/mcp-jira-example.md` or `docs/security-overview.md` (Lane A, AD-29) or any product code, web code, release notes or More to try text. Never ship G1 or M1; they belong to other lanes. Add no H2 to GUIDE.md: the `guide` rule pins its H2 list. Add no new heading or new sentence.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| HAPPY_PATH | GUIDE.md with G2 under the admin H2; the example holds line 36 | `PASS admin-mcp`; all 43 rules pass | No error expected |
| DRIFT | Either copy of the sentence changes (guide or example) | `FAIL admin-mcp` | Fix the text to the ruled wording |
| BROKEN_LINK | Link target renamed, or the example missing from the tree (`of` returns the empty file) | `FAIL admin-mcp` (plus `readme-links` for a renamed link) | Restore the path |
| MISPLACED | G2 below `### Demo mode`, in another section, twice, or after a stray line | `FAIL admin-mcp` | Put it back as the section's first paragraph, once |
| NO_GUIDE | GUIDE.md absent | `FAIL admin-mcp: GUIDE.md is missing` (fail closed; in `GUIDE_RULES`) | Expected |

</intent-contract>

## Code Map

- `GUIDE.md:283-285` -- `## For admins and developers`, then a blank line, then `### Demo mode`. G2 goes between them, with a blank line on each side. The section has no text of its own yet.
- `docs/mcp-jira-example.md:36` -- the sentence, verbatim: `An MCP tool that runs operating-system commands or arbitrary code must be classified Risky.` (Lane A; read-only). It has no anchor to link.
- `docs/security-overview.md:210,218` -- already links the example (`mcp-jira-example.md`) and carries the sentence (22.6); no change.
- `README.md:101` -- the More paragraph already links `GUIDE.md#for-admins-and-developers`; no change.
- `docker/tests/test-readme.sh` -- the inputs (`SECOV_DOC=` ~L213, `secov_p=$(of ...)` ~L247); `section()` L437; `st`/`rule_begin`/`finish` L506-590; sibling `chk_admin_commands` L1342 (it reads the same section); `rule_admin_commands` L2690; `RULES` and `GUIDE_RULES` ~L3290; the header rule list L14-159 and "What it reads" L161.
- `docker/tests/test-release-sequence.sh:2182,2289` -- Lane A's `overviewdoc` already pins the sentence in the example and the overview (`OVW_MCP_RISKY`). It is untouched; the new rule does not depend on it.
- Prototype (scratch, not tracked): `prototype-36-3.patch` in the stage scratch folder `.scratch-e36s3` (GUIDE +2 lines, test-readme +40/-2). It is measured green, and its four mutations went red.

## Tasks & Acceptance

**Execution:**
- `GUIDE.md` -- after L283 `## For admins and developers`, insert an empty line and then the G2 line, so that G2 is the section's first paragraph above `### Demo mode` -- the admin guide is where the README's admin section now lives (FR-10, FR-58).
- `docker/tests/test-readme.sh` -- add the rule `admin-mcp`. Inputs: `MCP_EXAMPLE_DOC=docs/mcp-jira-example.md` and `mcpexample_p=$(of ...)`. Constants: `ADMIN_MCP_RISKY` (the sentence) and `ADMIN_MCP_LINE` (G2, built from the two). `chk_admin_mcp <guide> <example>` checks three things: the first non-empty line of `section "$1" 'For admins and developers'` is G2; `grep -cxF` of G2 in the guide is 1; and `grep -cxF` of the sentence in the example is 1. `rule_admin_mcp` runs `rule_begin admin-mcp "$GUIDE" "$mcpexample_p"` and these self-test copies, each of which must be flagged: G2 removed; "must" to "should"; link to `docs/mcp-jira.md`; link text changed; a stray line above G2; G2 under Demo mode; G2 in Troubleshooting only; G2 twice; the admin H2 renamed; the example's sentence changed; the example's sentence removed; the example empty. Then `finish`. Add `admin_mcp` to `RULES` (after `admin_commands`) and to `GUIDE_RULES`. In the header, add Story 36.3 and FR-10 to line 2, add `admin-mcp` to the GUIDE.md rules list and a one-line rule description, and add `docs/mcp-jira-example.md` to "What it reads" -- Rule 2: a new rule that reuses `section`/`st`/`of`; it is not folded into `admin-commands`, whose st_facts check matches facts anywhere and reads one file.

**Acceptance Criteria:**
- AC1: Given GUIDE.md after this story, when its "For admins and developers" section is read, then its first paragraph is G2 word for word, G2 is in the guide once, and it is above `### Demo mode`.
- AC2: Given `docs/mcp-jira-example.md`, when compared with the guide, then G2's first sentence is the example's line 36 word for word.
- AC3: Given GitHub renders the root GUIDE.md, when the link is followed, then it reaches `docs/mcp-jira-example.md`, a tracked file. The link has no anchor.
- AC4: Given `bash docker/tests/test-readme.sh`, when it runs, then `PASS admin-mcp` prints, every other rule passes (43 PASS, exit 0), and every self-test copy is flagged.
- AC5: Given the story diff, when it is inspected, then only `GUIDE.md` (+2 lines) and `docker/tests/test-readme.sh` change, besides this spec. `README.md`, `docs/`, `src/`, `web/` and `release/` are unchanged.

## Spec Change Log

- 2026-11-14, Contest Planner gate ruling (~13:00Z) applied by the lead: amendment and G2 position approved; epics.md retargeted (36.3 and 22.6).

## Review Triage Log

### 2026-11-14 — Review pass
- verdicts: 9 findings — high 0, medium 0, low 3, false 6, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind Hunter and Verification Gap (grouped): no self-test duplicates the classification sentence in the example, so the example side's "exactly once" half is unpinned — real but cosmetic: Lane A's `overviewdoc` rule pins that sentence in the example, the spec fixes the count at 12 self-test copies, and a 13th copy is added complexity for a regression nobody would meet in everyday use.
  - `[false]` `[reject]` Blind Hunter: the paragraph does not say where to classify or what the default is — G2's words are ruled verbatim (M(4)) with "no new words"; adding a sentence is excluded by the spec's Boundaries.
  - `[low]` `[reject]` Blind Hunter: the sentence is pinned in three places (`overviewdoc`, `admin-mcp`, the example) — the spec states the new rule does not depend on `overviewdoc`; a shared constant across two test scripts is a larger change for a drift that either rule would flag.
  - `[low]` `[reject]` Blind Hunter: `admin_mcp` is first in `GUIDE_RULES` but after `admin_commands` in `RULES` — cosmetic; the `unlisted` guard passes and the spec names no order for `GUIDE_RULES`.
  - `[false]` `[reject]` Intent Auditor divergence 1: the link target is checked as a string only — `readme-links` also failed in the link-rename mutation (shown red), and the link smoke confirms the target is a tracked file.
  - `[false]` `[reject]` Intent Auditor divergence 2 (R4): G2's wording cannot be checked against the ruling from the intent alone — the wording is the verbatim text in the spec's Design Notes and the lead's instruction, and the diff matches it byte for byte.
  - `[false]` `[reject]` Intent Auditor divergence 3: the diff exercises GUIDE.md, not the README — descriptive; this is the ruled retarget (gate ruling 2026-11-14).
  - `[false]` `[reject]` Intent Auditor divergence 4: the "43 rules" count is not visible in the diff — the real run printed 43 PASS lines and exit 0.
  - `[false]` `[reject]` Verification Gap: AC5 has no mutation line — AC5 is a diff-scope check, pinned by the `git diff --quiet` commands in Verification (exit 0), not by a test.
- Edge Case Hunter returned no findings.

## Design Notes

### Contest Planner ruling at the gate (2026-11-14 ~13:00Z, binding; `.coordination/prompts/epic-36-rulings-20261113-2130.md`, "36.3 gate")

- The Rule 5 amendment is APPROVED as worded and applied by the lead in epics.md (Story 36.3's AC, and the same retarget in Story 22.6's ACs in Epic 22's block), each marked `[AMENDED 2026-11-14, Story 36.3, Contest Planner gate ruling ~13:00Z ...]`.
- G2's position is APPROVED: the first paragraph of `## For admins and developers` in GUIDE.md, before `### Demo mode`, the words verbatim under M(4).
- The `admin-mcp` rule is APPROVED, with its self-tests and the 4 mutations.

**Governing ADs:** AD-29. GUIDE.md, README.md and `docker/tests/` are Lane B's. The worked example and the security overview are Lane A's: this story links them and does not edit them. The Consistency Conventions "README link" row governs product links (`GUIDE_URL` plus an anchor); this is a link inside a document, and Story 0.30 allows a relative one. No AD is amended. **Rules 1 and 2:** no service is introduced, so there are no Integration ACs and no consumers. Consumes: Story 22.6's `docs/mcp-jira-example.md`, the real file. **Rule 3:** docs only; the real-runtime evidence is the CLI run of `test-readme.sh` (exit code and PASS line) plus the link smoke.

### Gate item 1 (Rule 5 amendment; veto window, for the Planner, not decided here): the target is GUIDE.md, not README.md

The AC says "adds the README link ... into the README's admin section". That section no longer exists. Story 0.30 (owner-approved, 2026-11-12) moved "For admins and developers" word for word into GUIDE.md. Its `top` rule pins the README's H2 list, which has no admin section. Evidence that GUIDE.md is the intended target:
- FR-10 itself says "the admin guide".
- Story 22.6's AC says "the README's admin section (the admin guide)".
- The Planner approved G2 for "GUIDE.md 'For admins and developers' (Lane B's Story 36.2, per its AC)" (M(4); 22.6 spec L624).
- 22.6's spec L187 says Lane B copies the sentence "into GUIDE.md's admin section".

**Recommendation: approve.** Amend epics.md Story 36.3's AC: "adds the README link" becomes "adds the admin guide's link (GUIDE.md "For admins and developers", where Story 0.30 moved the README's admin section)", and "into the README's admin section" becomes "into that section". Optional bookkeeping: Story 22.6's AC still names "Lane B's Story 36.2" for this criterion, which the 2026-11-12 split moved to 36.3. That block belongs to Epic 22, so it is the Planner's call. The alternative is a new admin section in README.md, which is not recommended: it reverses Story 0.30's ruled structure, adds new public text for judges and breaks the `top` rule.

### Gate item 2: public text

### Proposed public text (verbatim; none ships until accepted)

- **G2, existing approved text (Planner M(4), 2026-11-13 ~09:30Z; no new words).** File `GUIDE.md`, position: the first paragraph of "## For admins and developers", between the H2 (L283) and `### Demo mode` (L285), with an empty line on each side. The position inside the section is this plan's choice, because G2 did not name one; it is the only place that needs no new heading. Confirm it.

```markdown
An MCP tool that runs operating-system commands or arbitrary code must be classified Risky. The worked example [A Jira MCP server, step by step](docs/mcp-jira-example.md) shows how to add a server and classify its tools.
```

M(4)(e) truth check: sections 1 and 2 of the example add the server and classify its tools, so the claim is true. No other text: no heading and no lead-in. Out of scope: G1 (Epic 0) and M1 (More to try).

## Verification

**Commands:**
- `bash docker/tests/test-readme.sh` -- expected: exit 0, `PASS admin-mcp: ...`, `test-readme: all rules passed` (43 PASS lines; 42 before).
- `bash ci/checks.sh` -- expected: exit 0.
- `bash docker/tests/test-release-sequence.sh overviewdoc` -- expected: pass, unchanged.
- `node --test web/scripts/allowance-sources.test.mjs web/scripts/banner-view.test.mjs web/scripts/chat-view.test.mjs web/scripts/files-docs.test.mjs web/scripts/history-docs.test.mjs web/scripts/more-to-try-view.test.mjs web/scripts/rail-view.test.mjs web/scripts/sources-docs.test.mjs web/scripts/usage-docs.test.mjs` (the tests that read GUIDE.md) -- expected: 270 of 270 pass (measured on the prototype).
- `git diff --stat` -- expected: exactly `GUIDE.md` and `docker/tests/test-readme.sh`; `git diff --quiet -- README.md docs src web release` exits 0.

**Smoke (the link resolves):** `t=$(grep -xF 'An MCP tool that runs operating-system commands or arbitrary code must be classified Risky. The worked example [A Jira MCP server, step by step](docs/mcp-jira-example.md) shows how to add a server and classify its tools.' GUIDE.md | sed -n 's/.*](\([^)]*\)).*/\1/p')`. Then `[ "$t" = docs/mcp-jira-example.md ] && git ls-files --error-unmatch "$t" && case $t in *'#'*) false;; esac`. Expected: exit 0. GUIDE.md is at the root, so the relative path is the repository path. There is no anchor to check. After the lead's push, `https://github.com/jbrandtmse/OcuTalon/blob/<branch>/docs/mcp-jira-example.md` renders; this check is optional and the lead's.

**Mutations** (Rule 19; measured on the scratch prototype, to be re-run by the implement stage; restore byte-identical):
- mutation: delete the G2 line from GUIDE.md -> `FAIL admin-mcp` (AC1).
- mutation: GUIDE.md "must be classified Risky" -> "should be classified Risky" -> `FAIL admin-mcp` (AC2).
- mutation: G2's link `docs/mcp-jira-example.md` -> `docs/mcp-jira.md` -> `FAIL admin-mcp`, `FAIL readme-links` (AC3).
- mutation: example line 36 "must" -> "should" -> `FAIL admin-mcp` (AC2, the tie to the example).

**Shared surfaces:** GUIDE.md "For admins and developers" (read by `admin-commands`, `dev-only` and `test-release-notes.sh`'s `names_outside_section`); `RULES`/`GUIDE_RULES`. Every test added or changed passes on a fresh environment, in either order. `test-release-notes.sh` `real-tree` fails on a history-less scratch copy both with and without G2, so that failure is a property of the copy, not of this change.

## Auto Run Result

Status: done
Blocking condition: none

**Change.** G2 is the first paragraph of GUIDE.md "## For admins and developers", before `### Demo mode`, verbatim. A new `admin-mcp` rule in `docker/tests/test-readme.sh` pins it: it must be the section's first paragraph and appear once in the guide, and the example's sentence must be a whole line of `docs/mcp-jira-example.md` once. It has 12 self-test copies and is in `RULES` and `GUIDE_RULES`.

**Files changed.**
- `GUIDE.md` (+2 lines): G2 and its blank line.
- `docker/tests/test-readme.sh`: the rule, its inputs and constants, the self-tests, the registration and the header notes (Story 36.3, FR-10, `docs/mcp-jira-example.md`).
- This spec: status, baseline, the triage log and this result. The Code Map's absolute prototype path was replaced by a relative description, because `test-boundaries.sh` rule `paths` flags absolute paths in tracked files.

**Review.** 9 findings from 4 layers: patches applied 0, deferred 0, rejected 9 (3 low, 6 false; reasons in the triage log). Follow-up review recommended: false (no patches).

**Verification.**
- `test-readme.sh`: exit 0, 43 PASS, `PASS admin-mcp`. It was run again by the review layer after the last edit.
- `test-release-notes.sh`: exit 0, including `real-tree`.
- `test-boundaries.sh`: all rules passed, after the spec path fix.
- `npm --prefix web test`: 2082 of 2082.
- The 9 GUIDE.md-reading node tests: 270 of 270.
- `test-release-sequence.sh overviewdoc`: pass.
- Link smoke: exit 0, tracked, no anchor.
- Mutations (each red, then reverted by hand, md5 identical): deleted G2 -> `FAIL admin-mcp`; "should" in the guide -> `FAIL admin-mcp`; link to `docs/mcp-jira.md` -> `FAIL admin-mcp` and `FAIL readme-links`; "should" on example line 36 -> `FAIL admin-mcp`.
- `git diff --quiet -- README.md docs src web release`: exit 0.
- `ci/checks.sh` (about 25 minutes) failed only at `boundaries` for the absolute path in this spec, since fixed. The other checks passed; it was not re-run.

**Residual risks.** The `printf: write error: Broken pipe` noise in `test-readme.sh` is pre-existing. The work is not committed: the lead commits (the stage owner forbade `git commit`).
