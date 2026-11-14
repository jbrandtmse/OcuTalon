---
title: 'Story 36.3: Link the worked Jira example from the admin docs'
type: 'chore'
created: '2026-11-14'
status: 'ready-for-dev'
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
- Prototype (scratch, not tracked): `/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/.scratch-e36s3/prototype-36-3.patch` (GUIDE +2 lines, test-readme +40/-2). It is measured green, and its four mutations went red.

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

## Review Triage Log

## Design Notes

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

Status: ready-for-dev
Blocking condition: none for planning. Implement waits for the Planner's rulings on Design Notes gate item 1 (Rule 5: the AC's "README's admin section" retargeted to GUIDE.md "For admins and developers"; recommendation: approve) and gate item 2 (G2's position as the section's first paragraph; G2's words are already approved under M(4)). Halted after planning, as instructed.
