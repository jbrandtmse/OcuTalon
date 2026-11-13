---
title: 'Story 21.12: A check fails on a link to a README anchor that README.md does not have'
type: 'chore'
created: '2026-11-12'
status: 'done'
baseline_revision: 'cb8981a11d8bf7ca76e196637b7d201cc192a044'
baseline_commit: '407b4dafb4ab2a7e4b012a690697115e16bc0747'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-21-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `docker/tests/test-readme.sh`'s `readme-links` rule checks README anchors only in README.md and GUIDE.md, without line numbers, and misses `../README.md#x`, `/README.md#x`, `blob/HEAD/README.md#x`, reference-style links and autolinks. `product-links` checks only product code (`web/src/app/**/*.ts`, `src/**/*.cls`). No check reads `docs/*.md` or any other Markdown file, so renaming a README heading can leave a dead link there (DW-1207).

**Approach:** Add one rule, `readme-anchors`, to `test-readme.sh`, built from the script's own helpers. It reads every Markdown file of the documentation set (GUIDE.md and `docs/*.md` included; README.md and the records excluded, Design Notes), finds each link that resolves to the root README.md with an anchor, and checks the anchor against README.md's heading slugs as GitHub renders them. It prints `<path>:<line>` and the anchor for each dead link. In the script's in-script mutation style, it first proves it flags planted dead links and passes planted live ones. Test-only: no product, workflow, `ci/` or `release/` change.

## Boundaries & Constraints

**Always:**
- Same script and the same CI job (`readme` in `ci/units.sh` `CHECK_SCRIPTS`, run by `ci/checks.sh` in the hosted `checks` job). Hermetic: no network, no container, bash 3.2 and BSD or GNU tools (the script's header rule: POSIX awk only, so no `gensub`, no three-argument `match`, no `declare -A`, no `grep -P`).
- The file set comes from the script's `$listing` (`scan_files`: tracked or untracked-not-ignored, never `.env`).
- Slugs come from the existing `headings` reader. Duplicate headings get GitHub's suffixes: the first `foo`, then `foo-1`, then `foo-2`.
- A link counts only where GitHub renders one: inline `[t](target)` and `![t](target)`, a reference definition `[label]: target`, an HTML `href="target"`, an autolink `<https://...>`, and a bare `https://` address. Anything inside a fenced block (```` ``` ```` or `~~~`) or an inline code span is not a link.
- A target resolves to the root README when it is (after its `?query` is dropped) one of these:
  - a relative path resolved against the linking file's folder (`README.md`, `./README.md`, `../README.md`, `../../README.md`, ...);
  - a root path, `/README.md`;
  - `https://github.com/jbrandtmse/OcuTalon/blob/main/README.md` or `.../blob/HEAD/README.md`;
  - the repository page, `https://github.com/jbrandtmse/OcuTalon` or the same with a trailing `/`.
- Each failure line names the file, the line and the anchor. One line per link: a link that two forms match is reported once.
- The rule fails closed in four cases: no README.md, or no GUIDE.md (both through `rule_begin`: the checker's third slot is `$GUIDE`, and the rule is in `GUIDE_RULES`); a file set that holds no GUIDE.md or no `docs/*.md` file; and a README heading in a form that `headings` does not slug as GitHub does (it holds `](` or `<`, ends in a closing `#` run, or ends in whitespace).
- Comments state the contract, never the history (Rule 14). Update the header's rule list and its "What it reads" list. The edits to this contended file are placed: the helpers and the checker go after `chk_readme_links`, the rule after `rule_readme_links`, and `readme_anchors` right after `readme_links` in `RULES` and `GUIDE_RULES`.

**Never:**
- No change to README.md, GUIDE.md, `docs/`, `release/**`, `.github/workflows/**`, `ci/**`, `_bmad/**` or `.claude/**`, and no new script, unit or group.
- No change to the existing rules' behaviour (`readme-links`, `product-links`, `headings`, `ALLOWED_HOSTS`). An `ALLOWED_HOSTS` edit would also need a `release/checklist.sh` edit, which would be a veto item.
- No outward host in the new code (`release/checklist.sh` `outward_hits`: no community, openexchange, youtube.com, x.com, linkedin and so on). `github.com/jbrandtmse/OcuTalon` and `example.org` are fine.
- No anchor check against any README other than the root one, and no check of links to a pinned ref (`blob/<tag or sha>/README.md#x`).

## I/O & Edge-Case Matrix

The rule's self-tests (`st`, planted files under `$tmp`), plus the run on the real tree. `M` is a README copy with `## Measured` (slug `measured`).

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Live, every form | Root file: `[a](README.md#measured)`, `[b](./README.md#measured)`, `[r]: README.md#measured`, `<a href="README.md#measured">`. `docs/` file: `[c](../README.md#measured)`, `[d](/README.md#measured)`, `[e](https://github.com/jbrandtmse/OcuTalon/blob/main/README.md#measured)`, `[f](https://github.com/jbrandtmse/OcuTalon/blob/HEAD/README.md#measured)`, `<https://github.com/jbrandtmse/OcuTalon#measured>`, a bare `https://github.com/jbrandtmse/OcuTalon#readme` (the repository page's README anchor) | no output | none |
| Dead anchor, each form | Each form above with `#nowhere` (one planted line each) | one line per link: `readme-anchors: <path>:<line>: the link (<target>) names '#nowhere', and README.md has no heading with that slug` | rule FAIL, exit 1 |
| Heading renamed | `M` with `## Measured` renamed `## Measurements`; planted `README.md#measured` | flagged with its path, line and `#measured` | FAIL |
| Duplicate headings | `M` plus a second `## Measured` | `#measured-1` not flagged, `#measured-2` flagged | FAIL on -2 only |
| Case | `README.md#Measured` | flagged (anchors compare exactly) | FAIL |
| Wrong folder | `docs/x.md` with `[x](README.md#measured)` (that is `docs/README.md`), or a root file with `../README.md#measured` (outside the repository) | flagged: `the link (...) names docs/README.md, which is not a file of the tree` or `... leaves the repository` | FAIL |
| Not a link | `#nowhere` links in a code span, a ```` ``` ```` fence, a `~~~` fence, or to a pinned `blob/v1.0.0/README.md#nowhere` | no output | none |
| File set | a listing with `GUIDE.md`, `CLAUDE.md`, `docs/a.md`, `eval/x/y.md`, `release/demo-host-checks.md`, `web/README.md`, `newdir/z.md` and `README.md`, `_bmad/x.md`, `_bmad-output/x.md`, `.claude/x.md`, `release/records/1.0.0/rc4.md` | exactly the first seven are selected | a set with no GUIDE.md or no `docs/*.md` is flagged |
| Unsluggable heading | `M` plus a heading with a link, an HTML tag, a closing `##`, or a trailing space | `readme-anchors: README.md:<line>: the heading ... is not in a form this check slugs as GitHub does` | FAIL |
| Real tree | today's files (the one README anchor link: `GUIDE.md:77` `README.md#measured`) | `PASS readme-anchors: ...` | none |

</intent-contract>

## Code Map

- `docker/tests/test-readme.sh` -- the only file changed.
  - Header :1-160: the Stories list on :2 gains 21.12 and DW-1207; "What it pins" :13-136 (`product-links` :126-128, `readme-links` :129-134) gains a `readme-anchors` entry; "What it reads" :138-142 gains the documentation set.
  - Inputs: `README`/`GUIDE` :171-172; `listing=$(scan_files)` :192; `in_tree` :197; `of` :201; `have_readme`/`have_guide` :204-206; `product_files` :228 (the shape for a path filter).
  - Readers: `headings` :353-359 (slug: lower-case, drop all but `[a-z0-9 _-]`, spaces to `-`; skips ```` ``` ```` fences only; no line number, no duplicate suffix). Reuse it, do not change it. `image_links` :363-381 is the awk shape for scanning links on a line.
  - Self-test helpers: `st_note` :459, `mutate` :466, `st` :479-492 (slot 1-4 replaced by `$tmp/m`, the checker must print something), `st_append` :495, `rule_begin` :520-541 (README fail-closed; GUIDE fail-closed when a slot equals `$GUIDE`), `finish` :545-560.
  - Siblings: `address_anchors` :1601-1605 and `chk_product_links` :1622-1657 (product code; reads `jbrandtmse/OcuTalon#x` only); `chk_readme_links` :1683-1733 (README and GUIDE: its `GUIDE_URL`, repository-URL and `README.md#x` cases :1700-1717 have no line number; `../README.md#x` reaches the `*)` file branch :1718-1721, so its anchor is never checked); `ALLOWED_HOSTS` :1662 (do not edit).
  - Rules: `rule_product_links` :2437-2484, `rule_readme_links` :2592-2634 (its slug self-tests :2613-2618 are the model for the live-link rows), `rule_docs` :2707-2722; `RULES` :2767, `GUIDE_RULES` :2769; the `rules`, `no-readme` and `no-guide` meta-checks :2771-2811, and the run loop :2813.
- Read only, unchanged:
  - `docker/tests/lib-scan.sh` :11-22 (`scan_files`).
  - `ci/units.sh` :6 (`readme` in `CHECK_SCRIPTS`) and :251 (`NOT_IRIS_INPUT_PATTERN` holds `docker/tests/test-[^/]+\.sh$`, so this push runs no IRIS group).
  - `release/checklist.sh`: :219 (name-only-in-note exempts test-readme.sh), :313 (`row_readme` reads the exit code only), :382-389 (`outward_hits`; the one allowed line of test-readme.sh is `ALLOWED_HOSTS`).
  - `docker/tests/test-release-checklist.sh` :107 and :555-620 (stubs test-readme.sh and pins the `ALLOWED_HOSTS` line).
- Today's measured inputs:
  - The documentation set has 7 files: GUIDE.md, CLAUDE.md, the 3 files of `docs/`, `eval/documents-runbook-rotate/results-runbook.md` and `release/demo-host-checks.md`.
  - Its one README anchor link is `GUIDE.md:77` `[Measured](README.md#measured)`.
  - README.md has 9 ATX headings, all ASCII, none with a link, HTML, a closing `#` or trailing space, and no duplicate. It has no setext heading and no `~~~` fence.
  - `bash docker/tests/test-readme.sh` takes 40 s on the developer machine.

## Tasks & Acceptance

**Execution:**
- `docker/tests/test-readme.sh` -- after `chk_readme_links`, add:
  - (a) `doc_files`: a filter over `$listing` that keeps `*.md`/`*.markdown`, except `README.md` at the root and anything under `_bmad/`, `_bmad-output/`, `.claude/` or `release/records/`;
  - (b) `readme_slugs <readme>`: `headings` field 2 with GitHub's `-1`/`-2` suffixes;
  - (c) a link extractor that prints `line<TAB>target` for every link form under Always, skipping fences and code spans;
  - (d) the path resolver;
  - (e) `chk_readme_anchors <readme> <list file> <guide>`, where the list holds `repo-path<TAB>file-to-read` pairs, so planted copies keep a repository path.
  It also adds `rule_readme_anchors` after `rule_readme_links`, with one `st` self-test per matrix row (dead rows must be flagged, and the live and not-a-link rows must not be, through the `st_note` pattern of :2616/:2618), and `finish readme-anchors 'every README anchor that a Markdown file outside README.md links, relative or by the repository address, is a heading slug of README.md as GitHub renders it' chk_readme_anchors`. It adds `readme_anchors` after `readme_links` in `RULES` and `GUIDE_RULES` and updates the header. -- One rule in the README check's own script, so it runs wherever `readme` runs, with no new unit (Rule 2: it extends the script's readers and self-test helpers).

**Acceptance Criteria:**
- Given the branch's tree, when `bash docker/tests/test-readme.sh` runs (as CI's hosted `checks` job does through `ci/checks.sh`), then it prints `PASS readme-anchors: ...`, every other rule's line is unchanged, and it exits 0.
- Given README.md's `## Measured` heading renamed in the working tree, when the script runs, then `readme-anchors` prints a line with `GUIDE.md:77` and `#measured`, prints `FAIL readme-anchors`, and the script exits 1. With the heading restored, it passes.
- Given a planted `[x](../README.md#nowhere)` line in `docs/install-ipm.md`, when the script runs, then `readme-anchors` names `docs/install-ipm.md:<that line>` and `#nowhere` and fails. With `../README.md#measured` on that line instead, `readme-anchors` passes.
- Given the rule's checker made to accept every anchor, or the documentation-set filter made to drop `docs/`, when the script runs, then it prints `FAIL readme-anchors: a broken copy was not flagged` (the self-tests prove the check can fail), and exits 1.
- Given `readme_anchors` left out of `RULES`, or the rule run with no README.md or no GUIDE.md, when the script runs, then the existing `rules`, `no-readme` and `no-guide` meta-checks fail.
- DW-1207: given any Markdown file outside README.md (GUIDE.md and `docs/*.md` included) that links a README anchor README.md does not have, when the script runs, then it fails, naming the file, line and anchor. The other ACs pin this.

### Review Findings

Code review 2026-11-12 (four layers: blind, edge, verification-gap, acceptance-auditor). 0 decision-needed, 10 patch (all applied), 0 defer, 9 rejected. No AD violated: AD-22 (hosted, hermetic, no new unit or group) and AD-29 (placed edits in a shared file) are kept. Rule 3: test-only tooling, exempt.

- [x] [Review][Patch] (medium, fix-risk low, in-story; verification-gap+acceptance-auditor) The renamed-README self-test read the real GUIDE.md:77 link, so removing that link turned the rule red with nothing dead -- the row now plants its own link against the real README renamed [docker/tests/test-readme.sh rule_readme_anchors]
- [x] [Review][Patch] (medium, fix-risk low, in-story; verification-gap) The angle-bracket reference definition `[r]: <README.md#x>` had no row; breaking its branch missed real dead links -- dead row added [docker/tests/test-readme.sh rule_readme_anchors]
- [x] [Review][Patch] (medium, fix-risk low, in-story; blind) The resolver was tested one folder deep only (`dir=${1%%/*}` passed every row; the real set has `eval/<dir>/<file>.md`), and the repository page with `?tab=readme-ov-file` had no row -- live and dead rows two folders deep and with the query [docker/tests/test-readme.sh rule_readme_anchors]
- [x] [Review][Patch] (low, fix-risk low; edge) A footnote definition `[^1]: see [x](README.md#x)` was read as a reference definition, so its dead link passed -- footnote labels are now scanned as text, with a dead row [docker/tests/test-readme.sh md_links]
- [x] [Review][Patch] (low, fix-risk low; edge) An inline destination opening with `<` and no `>` dropped the rest of the line, so a later dead link passed -- the scan continues, with a dead row [docker/tests/test-readme.sh md_links]
- [x] [Review][Patch] (low, fix-risk low; edge+blind) The unsluggable-heading guard let through forms `headings` slugs unlike GitHub, some false greens: a leading space, a reference link `[x][y]`, an entity, `_emphasis_`, an `:emoji:` and more than six `#` -- they fail closed now, one row each [docker/tests/test-readme.sh chk_readme_anchors]
- [x] [Review][Patch] (low, fix-risk low; acceptance-auditor, the implement review's residual) `headings` toggles only on a column-0 backtick fence, so a README `~~~`, four-backtick or indented fence could add a phantom slug (a false green) -- such a README fence fails closed, with a row per form [docker/tests/test-readme.sh chk_readme_anchors]
- [x] [Review][Patch] (low, fix-risk low; verification-gap) The bare-address cleanup (an unbalanced `)`, the stop at `]`) had no live row, so breaking it stayed green -- two live rows [docker/tests/test-readme.sh rule_readme_anchors]
- [x] [Review][Patch] (low, fix-risk low; blind+acceptance-auditor) The header's rule entry left out the leaves-the-repository and other-README lines and the new fail-closed forms, and its run summary said "a README line number" [docker/tests/test-readme.sh:1-170]
- [x] [Review][Patch] (low, fix-risk low; verification-gap+blind+acceptance-auditor) Mutation lines missing for the no-readme half of AC 5 and for AC 4's self-test half seen alone, and AC 1's "every other line unchanged" had no recorded comparison -- run and recorded under Verification (Rule 19) [this spec, Verification]

Rejected:
- low (wontfix-accepted, DW-1243): `md_links` models no block context, so links in an HTML comment or indented code count (false reds) and a backtick line indented four or more spaces outside a list toggles the fence (a rare false green). A fix needs a list-aware block parser; the set has none of these today.
- false: the two file-set self-tests do not depend on the real tree. `finish` prints the real run's output first, and a clean list with rows removed can print only the fail-closed line.
- low: the unsluggable-heading `case` pattern's `*` spans lines. Over-flagging is still caught by the `README.md:$n` prefix and by the 0-count rows.
- low (by-design, Design Note 6): a TAB after the hashes, non-ASCII letters, setext headings and `<a id>` anchors are not modelled. These give false reds (non-ASCII rarely a false green), and `headings` may not change.
- low (by-design): an identical dead target repeated on one line is reported once. That is the documented `md_links` contract, and the file, line and anchor are still named.
- low (by-design, the matrix's File set row): CLAUDE.md and `release/demo-host-checks.md` are in the set, although editing them is owner-only or a veto item. Neither is frozen, and a red there clears from README's side. The append-only records stay out.
- false: "not run on CI's Ubuntu awk". Run under mawk in `ubuntu:24.04` (`--network none`, a `git ls-files` shim): `PASS readme-anchors`.
- false: `REPO_URL` duplicates a variable. No earlier variable holds the repository page's address; `GUIDE_URL` is a different address.
- low: record-keeping mismatches (QA's probe count 13 against 14, `:388` against `:389`, `baseline_commit` against `baseline_revision` and the cycle log's `story_base`, "Nine mutations", the frontmatter status against `sprint-status.yaml`, the Verification precondition wording). Fixing them means editing the lead's bookkeeping or the frontmatter, and none affects behaviour.

## Spec Change Log

## Review Triage Log

### 2026-11-12 -- Review pass
- verdicts: 18 findings (the layers' items grouped by claim) -- high 0, medium 1, low 13, false 4, maybe-false 0
- findings:
  - `[medium]` `[patch]` (blind, edge, verification-gap) the 'README.md from a folder that has none' self-test read the real tree's `docs/README.md` absence -- patched: the row plants `ra-none/x.md`, so adding a `docs/README.md` later cannot turn it red; its mutation re-run (resolver ignoring the folder) is red on it
  - `[low]` `[reject]` (verification-gap) `GUIDE_RULES` completeness is unchecked for every rule -- pre-existing for all members, not worth a story; the rule's own `no-guide` mutation (no `"$GUIDE"` slot) is now recorded and red
  - `[low]` `[patch]` (verification-gap) mutation lines missing for AC 1, the `no-guide` half of AC 5 and the `doc_files` exclusions -- spec text only: three lines added, the two runs observed red
  - `[low]` `[reject]` (blind, verification-gap, edge) `headings` toggles only on a column-0 backtick fence, so a `~~~` or long fence in README could add a phantom slug -- README has neither; a guard would add a branch; residual risk noted
  - `[low]` `[reject]` (blind, edge) non-ASCII README headings slug without their letters -- README is ASCII; spec Design Note 6 accepts the limit
  - `[low]` `[reject]` (blind, edge) `#L10`, percent-encoded and `user-content-` fragments, `#x:~:text=` are flagged -- false reds only, no such link in the tree
  - `[false]` `[reject]` (blind, edge) anchors should compare case-insensitively -- the sibling rule and decision 1 compare exactly; strict is safe by design
  - `[low]` `[reject]` (blind, edge) HTML comments, indented code, multi-line spans, blockquote fences, escaped backticks, CRLF are not modelled -- false reds (one rare false green for an escaped backtick); none in the tree; the real-tree run passes
  - `[low]` `[reject]` (blind, edge) the repository address is matched in one spelling (case, `http://`, `www`, `tree/main`, folder links) -- the AC lists the forms; by design
  - `[low]` `[reject]` (blind, edge) hard-coded `REPO_URL` -- the AC names this repository's address, as the sibling rules do
  - `[low]` `[reject]` (blind, verification-gap) the renamed-README real-surface row depends on the real `## Measured` and GUIDE.md:77 -- AC 2 asks for exactly that surface
  - `[false]` `[reject]` (verification-gap) the 0-line rows pass vacuously -- the dead-link rows of each form and `a link after a fence` prove the extractor emits
  - `[low]` `[reject]` (blind) a repeated unsluggable heading is reported at the first line -- README has no repeated heading; cosmetic
  - `[low]` `[reject]` (edge) a listed file that is unreadable passes silently -- the list comes from `$listing`, which names existing files
  - `[false]` `[reject]` (edge) `README.md#` flagged as a dead anchor -- spec decision 2
  - `[false]` `[reject]` (edge) explicit `<a id>` anchors and setext headings -- spec decision 6 (false reds only, none in README)
  - `[low]` `[reject]` (edge) unquoted or upper-case `href`, a link target wrapped over two lines, link text that is a URL -- false reds or rare misses, none in the tree
  - `[low]` `[reject]` (verification-gap) `http://` and the other extractor branches have no row -- the dead-link rows pin each form named in the AC
  - (intent-alignment) descriptive: the diff implements readings A, B, C, E, F, G and the whole-tree set D2 the spec decided; its remark that the real tree has no README anchor link besides GUIDE.md:77 matches the spec

## Design Notes

**Governing ADs (Rule 6):** none binds the README check. AD-22 (testing and CI) is the nearest one and is kept: the check is hosted and hermetic, and it adds no unit or group. AD-29 is kept: `test-readme.sh` is a shared file, so the edits are placed. No spine change.

**Integration ACs (Rule 1):** No consumers. The story adds a check, not a service. CI's `checks` job runs it through `ci/checks.sh`, and `release/checklist.sh`'s `readme` row reads only its exit code.

**Extend, don't copy (Rule 2):** the rule reuses `headings`, `$listing`/`scan_files`, `st`/`mutate`/`st_note`, `rule_begin`/`finish` and the `RULES` meta-checks. Its link extractor follows `image_links`' awk shape. `readme-links` is not widened, for two reasons. Its contract covers every link of README.md and GUIDE.md (hosts, files, header images). Its ~40 self-tests feed it two slots, and its link scan reads code spans and has no line numbers. Pointing it at seven more files would apply its host allow-list to `docs/` too, which is outside this AC. So a dead `README.md#x` in GUIDE.md shows under both rules, and that is intended. `product-links` stays the code-side check.

**The file set (decided in-stage).** The AC says "any tracked Markdown file other than README.md". Read literally, the check could never pass:
- **`_bmad-output/` is out.** It holds autolinked README addresses to anchors that moved, today, in append-only records: `deferred-work.md:7300` (`https://github.com/jbrandtmse/OcuTalon#install-it-yourself`), `spec-16-9-...md:402` and `cycle-log-epic-2.md:18`. The ledger body is written once (Rule 15), so they cannot be fixed.
- **`_bmad/` and `.claude/` are out.** They are method and agent tooling, owner-only to edit, so a red there would hold every lane's CI until the owner acted.
- **`release/records/` is out.** Records are frozen release evidence, true of the README at their tag. A later README rename must not force a rewrite of a record, and `release/**` is the RELEASE TOOL's footprint, where any edit is a veto item. They hold no README link today.
- **Everything else is in:** GUIDE.md, CLAUDE.md, `docs/*.md`, `eval/**/*.md`, `release/demo-host-checks.md` (a living list), and any Markdown file added later anywhere else.

Story 0.30's planned `readme-anchors` rule (its spec :135, never delivered; DW-1207 records the gap) skipped the same three trees. The intent, "moving a README section can never leave a dead link behind" in the documents people read, is unchanged. For the lead: this is a Rule 5 apply-and-report rewording of the AC's observable ("... other than README.md and the build records under `_bmad/`, `_bmad-output/`, `.claude/` and `release/records/` ..."), if the lead wants `epics.md` to say so.

**Other decisions taken in-stage:**
1. Anchors compare exactly, so `#Measured` is flagged. This is the sibling's rule; strict is safe.
2. `README.md#` (empty) is flagged, as in `readme-links`.
3. On the repository page only, `#readme` is live. GitHub uses it for the README; `product-links` and 0.30's plan treat it so.
4. Only `blob/main` and `blob/HEAD` follow the current README. A link to a tag or sha is pinned and cannot go dead by a rename on main.
5. A relative `README.md#x` from a sub-folder means that folder's README. It is flagged when that file does not exist (the likely mistake), and skipped when it is another tracked README (not README.md's anchors).
6. Known limit (fail-safe direction only): `headings` drops non-ASCII bytes, so a future heading with an accented letter would give a false red, never a false green. Setext headings and `<a id>` anchors are not modelled either, also false reds only. README has none of them today.

**Contended file and footprint:** `docker/tests/test-readme.sh` is in no epic's `paths_hint` (only a comment at `_bmad/custom/epic-dependencies.yaml:45` names it). Under Rule 11 (b) it is a footprint extension for the completion contract (`footprint_extensions: docker/tests/test-readme.sh`). Every story's findability lines touch it, so the edits stay placed.

**Ledger (Rule 17):** DW-1207 addressed: the whole story, and its AC above. Expect `resolved-by:21-12-a-check-fails-on-a-link-to-a-readme-anchor-that-readme-md-do` at adjudication.

## Veto items

None: no `release/**`, `.github/workflows/**`, public text or new dependency. The online demo is unaffected, because the check runs in CI and on developer machines only.

## Public text

None.

## Verification

Run every command from the worktree root, after `git rev-parse --show-toplevel` equals the worktree root. Use one command per foreground call with `timeout: 600000`. Each is sized under about 150 s (measured on the developer machine: test-readme 40 s, test-boundaries 9 s, test-release-checklist 37 s). No IRIS, no slot and no throwaway is used.

Shared surfaces: `docker/tests/test-readme.sh`'s `RULES` and `GUIDE_RULES` lists and its PASS/FAIL line set (one new `readme-anchors` line). `headings` is read, not changed. `release/checklist.sh` `row_readme` reads only the exit code. `test-release-checklist.sh` stubs the script and pins only its `ALLOWED_HOSTS` line. No other tracked test asserts on the script's lines (searched with `git grep`).

Standing criterion: every test added or changed passes on a fresh environment, in either order. The rule creates and removes its own planted files under the script's `$tmp`, and reads no other rule's state. The lead's fresh check is the script in a clean clone (`git clone --no-local` of this worktree into scratch), run once.

**Commands:**
- `bash docker/tests/test-readme.sh` (loop) -- expected: `PASS readme-anchors: ...`, every other line as before, `test-readme: all rules passed`, exit 0.
- `bash docker/tests/test-readme.sh` with README.md's `## Measured` renamed to `## Measurements` (once; restore it, then `git diff --quiet README.md`) -- expected: a `readme-anchors` line naming `GUIDE.md:77` and `#measured`, `FAIL readme-anchors`, exit 1. `readme-links` fails too, as before.
- `bash docker/tests/test-readme.sh` with `[x](../README.md#nowhere)` appended to `docs/install-ipm.md` (once; restore it, then `git diff --quiet docs/`) -- expected: `docs/install-ipm.md:<n>` and `#nowhere`, `FAIL readme-anchors`, exit 1.
- `bash docker/tests/test-boundaries.sh` (once) -- expected: all rules passed.
- `bash docker/tests/test-release-checklist.sh` (once) -- expected: all rules passed (no outward host and `ALLOWED_HOSTS` untouched).
- `git status --short` and `git diff --stat` (once, at the end) -- expected: only `docker/tests/test-readme.sh` and this spec changed.

**Mutations (Rule 19; each applied, observed red, reverted byte-identical with `cmp` against a saved copy):**
- AC 2, the real surface: README `## Measured` renamed → `FAIL readme-anchors` naming `GUIDE.md:77` `#measured`.
- AC 3, `docs/*.md` in scope: the planted `../README.md#nowhere` in `docs/install-ipm.md` → `FAIL readme-anchors` naming `docs/install-ipm.md:<n>`.
- AC 4, the self-tests can fail:
  - `chk_readme_anchors`' slug lookup made always true → `FAIL readme-anchors: a broken copy was not flagged`;
  - `doc_files` without `docs/` → the file-set self-test fails;
  - duplicate suffixes started at `-2` → the duplicate-heading row fails;
  - the resolver ignoring the linking file's folder → the wrong-folder row fails.
- The implement stage writes the observed red line next to each mutation.
- mutation: README.md `## Measured` renamed `## Measurements` -> `readme-anchors: GUIDE.md:77: the link (README.md#measured) names '#measured', and README.md has no heading with that slug`, `FAIL readme-anchors`, exit 1 (`readme-links` fails too); restored, `cmp` identical and `git diff --quiet README.md`
- mutation: `[x](../README.md#nowhere)` appended to docs/install-ipm.md -> `readme-anchors: docs/install-ipm.md:388: the link (../README.md#nowhere) names '#nowhere', and README.md has no heading with that slug`, `FAIL readme-anchors`, exit 1; with `../README.md#measured` on that line -> `PASS readme-anchors`, exit 0; restored, `cmp` identical and `git diff --quiet docs/`
- mutation: the slug lookup in `chk_readme_anchors` made always true -> `FAIL readme-anchors: a broken copy was not flagged` (12 self-test notes, e.g. `a link that two forms match: 0 lines flagged, 1 expected`), exit 1; restored, `cmp` identical
- mutation: `doc_files` made to drop `docs/*` -> `readme-anchors: the documentation set holds no docs/*.md file`, `FAIL readme-anchors`, exit 1 (the real set fails closed first, so the file-set self-test note is not printed); restored, `cmp` identical
- mutation: duplicate suffixes in `readme_slugs` started at -2 (`k += 2`) -> `self-test: a repeated heading: -1 is live and -2 is not: the output is not ...`, `FAIL readme-anchors: a broken copy was not flagged`, exit 1; restored, `cmp` identical
- mutation: the resolver ignoring the linking file's folder (the `dir` of a relative path left empty) -> `self-test: README.md from a folder that has none: the output is not ...` (and one more row), `FAIL readme-anchors: a broken copy was not flagged`, exit 1; restored, `cmp` identical
- mutation: `readme_anchors` left out of `RULES` -> `FAIL rules: rule_readme_anchors is not in RULES`, exit 1; restored, `cmp` identical
- mutation: `rule_begin` of `rule_readme_anchors` without its `"$GUIDE"` slot -> `FAIL no-guide: rule readme_anchors does not fail when GUIDE.md is missing`, exit 1; restored, `cmp` identical
- mutation: `doc_files` without its `.claude/*` and `release/records/*` exclusions -> `self-test: the documentation set is not the Markdown files but the root README, the build records and the release records`, `FAIL readme-anchors: a broken copy was not flagged`, exit 1; restored, `cmp` identical
- AC 1 and AC 6 (the real tree and DW-1207) are pinned by the rows above: the rename and planted-link mutations are the AC 6 proofs, and the unmutated run (`PASS readme-anchors`, every other line unchanged against the original script's, exit 0) is AC 1.
- QA stage: `docker/tests/test-readme.sh` (QA) gains two self-test rows for gaps found by 16 probe mutations of the delivered rule (run in a scratch `git clone --no-local`, never in the tracked tree); the other 14 probes (the four unsluggable-heading branches, `#readme` live only on the repository page, `?query` drop, exact case, empty `#`, `..` out of the repository, code span, `~~~` fence, `blob/HEAD`, the last row of the dead-link list) were already red.
- mutation: the `other <path>` branch of `chk_readme_anchors` made to flag every other-folder README.md (`if ! in_tree` -> `if true`) -> was green; now `self-test: README.md from a folder that has one, which is not the root README: 1 lines flagged, 0 expected`, `FAIL readme-anchors: a broken copy was not flagged`, exit 1 (new row `ra-has/README.md`, planted by prepending to `$listing` and restored)
- mutation: `readme_target` without its `//*` guard (`*:* | //*` -> `*:*`) -> was green; now `self-test: a link to another file or to its own heading: 1 lines flagged, 0 expected`, `FAIL readme-anchors: a broken copy was not flagged`, exit 1 (new `[w](//example.org/README.md#nowhere)` in the not-a-link row)
- QA checks, all in the scratch clone: the run with both rows is `PASS readme-anchors` and its output differs from the delivered-baseline (`cb8981a1`) script's output by that one line only; a planted `[x](../README.md#nowhere)` in `docs/install-ipm.md` gives `FAIL readme-anchors` naming `docs/install-ipm.md:389` and `test-readme: 1 rule(s) failed`; `readme_anchors` is in `RULES` and `GUIDE_RULES`, and `readme` is in `CHECK_SCRIPTS`, which `ci/checks.sh` loops in the hosted `checks` job.
- Files touched by QA: `docker/tests/test-readme.sh` (QA)
- Code review (each mutation run in a scratch `git clone --no-local` with the reviewed script copied in, restored byte-identical, `cmp` true):
- mutation: the reference-definition test back to `\[[^]]+\]:` (footnotes read as definitions) -> `self-test: a dead link: [^1]: see [x](README.md#nowhere): 0 lines flagged, 1 expected`, `FAIL readme-anchors: a broken copy was not flagged`, exit 1
- mutation: an unclosed `<` destination dropping the rest of the line (`: substr(rest, 2)` -> `: ""`) -> `self-test: a dead link: [a](<b) and [c](README.md#nowhere): 0 lines flagged, 1 expected`, `FAIL readme-anchors: a broken copy was not flagged`, exit 1
- mutation: the heading guard back to the delivered `'\]\(|<|(^|[[:space:]])#+$|[[:space:]]$'` with no level test -> six notes (`the heading '##   Leading'`, `'## See [the link][r]'`, `'## A &amp; B'`, `'## The _real_ thing'`, `'## :tada: Party'`, `'####### Seven'` `is not flagged by its line`), `FAIL readme-anchors: a broken copy was not flagged`, exit 1
- mutation: the angle-bracket reference-definition branch off (`if (0)`) -> `self-test: a dead link: [r]: <README.md#nowhere>: 0 lines flagged, 1 expected`, `FAIL readme-anchors: a broken copy was not flagged`, exit 1
- mutation: the unbalanced-`)` drop off (`if (cl > o)` -> `if (0)`) -> `self-test: a live link of every form, in docs/: 1 lines flagged, 0 expected`, `FAIL readme-anchors: a broken copy was not flagged`, exit 1
- mutation: the bare address no longer stopping at `]` -> `self-test: a live link of every form, in docs/: 1 lines flagged, 0 expected`, `FAIL readme-anchors: a broken copy was not flagged`, exit 1
- mutation: the resolver keeping only the first folder (`${1%/*}` -> `${1%%/*}`) -> `self-test: a live link two folders deep: 1 lines flagged, 0 expected`, `FAIL readme-anchors: a broken copy was not flagged`, exit 1
- mutation: the README fence guard without its indented form (`|^ +```` dropped) -> `self-test: a README fence ' ```' is not flagged by its lines`, `FAIL readme-anchors: a broken copy was not flagged`, exit 1
- mutation: AC 5, the no-readme half: `rule_readme_anchors` with its `rule_begin` call replaced by plain slot assignments -> `FAIL no-readme: rule readme_anchors does not fail when README.md is missing` and `FAIL no-guide: rule readme_anchors does not fail when GUIDE.md is missing`, exit 1
- mutation: AC 4, the self-test half seen alone: `doc_files` dropping `docs/*.markdown` (the real `docs/*.md` files stay, so the real set does not fail closed first) -> `self-test: the documentation set is not the Markdown files but the root README, the build records and the release records`, `FAIL readme-anchors: a broken copy was not flagged`, exit 1
- hermeticity: GUIDE.md:77's `([Measured](README.md#measured))` removed -> `test-readme: all rules passed`, exit 0 (the delivered rename row went red here); GUIDE.md restored, `git diff --quiet GUIDE.md`
- AC 1: the reviewed script's output differs from the baseline `cb8981a1` script's output by the one `PASS readme-anchors: ...` line only (`diff`), exit 0; under mawk (`ubuntu:24.04`) `PASS readme-anchors` too. `test-boundaries.sh` and `test-release-checklist.sh`: all rules passed.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `docker/tests/test-readme.sh` gains the rule `readme-anchors`. It reads every Markdown file of the documentation set (all tracked Markdown but README.md, `_bmad/`, `_bmad-output/`, `.claude/` and `release/records/`), extracts the links GitHub renders (inline, image, reference definition, href, autolink, bare address; none inside a fence or code span), resolves the ones that reach the root README.md (relative, `/README.md`, `blob/main` and `blob/HEAD`, the repository page with `#readme` live), and checks each anchor against README.md's heading slugs with GitHub's `-1`/`-2` suffixes. A dead link prints `<path>:<line>`, the target and the anchor. It fails closed with no GUIDE.md, no `docs/*.md` file, or an unsluggable README heading. Self-tests cover every matrix row on planted files.

**Files changed.**
- `docker/tests/test-readme.sh` -- helpers `doc_files`, `readme_slugs`, `md_links`, `readme_target`, `chk_readme_anchors` after `chk_readme_links`; `rule_readme_anchors` (with `ra_run`, `ra_expect`, `ra_line`) after `rule_readme_links`; `readme_anchors` after `readme_links` in `RULES` and `GUIDE_RULES`; the header updated.
- This spec -- mutation lines, triage log, this result.

**Review.** Four layers, 18 grouped findings: 1 patch (a self-test that relied on the real tree having no `docs/README.md`; now plants `ra-none/x.md`), 1 patch of spec text (three missing mutation lines, runs observed red), 12 low rejected and 4 false rejected, each with its reason in the triage log. Nothing deferred. Patched counts: medium 1, low 1. Follow-up review recommended: false.

**Verification.**
- `bash docker/tests/test-readme.sh`: `PASS readme-anchors`, every other PASS line identical to the original script's, `test-readme: all rules passed`, exit 0 (run after the last patch).
- `bash docker/tests/test-boundaries.sh`: all rules passed. `bash docker/tests/test-release-checklist.sh`: all rules passed.
- Nine mutations applied, observed red and reverted byte-identical (`cmp`); see `## Verification`.

**Residual risks.**
- `headings` (unchanged, reused) toggles only on a column-0 backtick fence, so a future `~~~` or long fence in README.md holding a `#` line could add a phantom slug (a false green, not only a false red as Design Note 6 says). README.md has none today.
- Non-ASCII README headings slug without their letters (false red or, rarely, a false green).
- `GUIDE_RULES` completeness is not checked for any rule (pre-existing).
- The `printf: write error: Broken pipe` stderr lines existed before the change (same count, 14).
- `footprint_extensions: docker/tests/test-readme.sh`.
