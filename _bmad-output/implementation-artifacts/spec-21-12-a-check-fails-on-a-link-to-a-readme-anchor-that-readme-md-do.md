---
title: 'Story 21.12: A check fails on a link to a README anchor that README.md does not have'
type: 'chore'
created: '2026-11-12'
status: 'ready-for-dev'
baseline_revision: '407b4dafb4ab2a7e4b012a690697115e16bc0747'
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

## Spec Change Log

## Review Triage Log

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

Run every command from the worktree root, after `git rev-parse --show-toplevel` equals `/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/epic-21`. Use one command per foreground call with `timeout: 600000`. Each is sized under about 150 s (measured on the developer machine: test-readme 40 s, test-boundaries 9 s, test-release-checklist 37 s). No IRIS, no slot and no throwaway is used.

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned only (halt after planning). One file to change, `docker/tests/test-readme.sh`; no veto item, no public text. The documentation-set scope is decided in-stage (Design Notes), with a Rule 5 apply-and-report wording offered to the lead; `footprint_extensions: docker/tests/test-readme.sh`.
