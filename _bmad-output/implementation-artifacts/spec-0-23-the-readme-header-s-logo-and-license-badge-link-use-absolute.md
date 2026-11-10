---
title: 'Story 0.23: The README header''s logo and LICENSE badge link use absolute GitHub URLs'
type: 'bugfix'
created: '2026-11-10'
status: 'done'
baseline_revision: '48e55642883ec1b2b9805d04a802efbe1b773c6e'
baseline_commit: '48e55642883ec1b2b9805d04a802efbe1b773c6e'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      Nothing pins, as a permanent self-test, that chk_readme_links still feeds the header logo into its existence check.
    evidence: |-
      The only demonstration is the AC4 untrack mutation. Dropping `header_images "$1"` from the target stream of chk_readme_links keeps every rule and self-test green while the logo is tracked. chk_readme_links takes no tree-list argument, so a self-test cannot stub a missing logo. The relative-src form had the same limit before this story.
    location: >-
      docker/tests/test-readme.sh:1305
    severity: low
---

<intent-contract>

## Intent

**Problem:** Open Exchange's README import mangles relative HTML paths. Another entry's relative `<img src>` came out as a doubled, broken raw URL. So OcuTalon's listing would show a broken image where the header logo should be, and the LICENSE badge link would break the same way.

**Approach:** Make the two relative HTML values in the README header absolute, using the Contest Planner's ruled URLs (2026-11-10, PUBLIC TEXT ruled). Then update `docker/tests/test-readme.sh` so that its header pins carry the new URLs and the header logo is still checked for existence and size. The new host allowance stays confined to the header block.

## Boundaries & Constraints

**Always:**
- README.md line 1: change only the logo's `src`, from `docs/images/ocutalon-logo.png` to `https://raw.githubusercontent.com/jbrandtmse/OcuTalon/main/docs/images/ocutalon-logo.png`. Everything else on the line stays byte for byte.
- README.md line 10: change only `href="LICENSE"`, to `href="https://github.com/jbrandtmse/OcuTalon/blob/main/LICENSE"`.
- Every rule and self-test of `test-readme.sh` keeps its strength. The header logo's file is still checked: it must exist in the tree under `docs/images/` and be under 300,000 bytes. `raw.githubusercontent.com` is allowed only on the header block's lines (up to `header_end`), and only for this repository's `main/docs/images/` path.
- `test-readme.sh` stays ASCII only and runs on bash 3.2 with BSD or GNU tools. Its rule messages and PASS lines keep their wording. The only new public text is the one self-test label under PUBLIC TEXT proposals below.

**Never:**
- Change any other README line. The body's Markdown links `[MIT License](LICENSE)` (line 21) and `[LICENSE](LICENSE)` (line 409) stay relative.
- Reword the ruled URLs.
- Add a rule to `RULES`, or remove or weaken any rule or self-test.
- Put `raw.githubusercontent.com` in `ALLOWED_HOSTS`.
- Name an image file in a new self-test.
- Write a local absolute path into a tracked file.
- Touch the logo file itself.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Ruled header | README lines 1 and 10 carry the ruled URLs; the logo is tracked and 41,442 bytes | Every rule prints PASS; `test-readme: all rules passed` | No error expected |
| Logo not tracked | `docs/images/ocutalon-logo.png` is not listed by the tree | `readme-links: the link (docs/images/ocutalon-logo.png) reaches no file or folder of the repository`, then `FAIL readme-links` | Fails closed |
| Logo too large | The header logo is 300,000 bytes or more | `images: docs/images/ocutalon-logo.png is <n> bytes, not under 300000` (the existing self-test proves this case) | Fails closed |
| Raw address below the header | The header's logo line is copied to the end of the README | `readme-links: the address https://raw.githubusercontent.com/... is not on the allow-list` | Flagged (new self-test) |
| Header changed | Any byte of lines 1 to 11 differs from the pin, so `header_end` is 0 | `top` flags the line. The raw address, the shields badges and the `<img>` tags lose their allowance. `header_images` lists nothing | Fails closed, as in 0.21 |

</intent-contract>

## Code Map

- `README.md:1` -- the `<h1>` with the logo `<img src=...>`. Only the `src` value changes.
- `README.md:10` -- the LICENSE badge `<a href="LICENSE">`. Only the `href` value changes.
- `docker/tests/test-readme.sh:211-230` -- the `HEADER` quoted heredoc (lines 214 and 223 are the two pins), `HEADER_LINES`, `HEADER_IMAGE_HOSTS='img.shields.io'` (228) and `header.want`.
- `test-readme.sh:304-307` `header_images` -- it extracts only `src="docs/images/..."` from the header lines. An absolute src would yield nothing, which would silently drop the logo from the size check and its self-test. This is the extension point.
- `test-readme.sh:604-627` `chk_images` -- a size loop over `image_links` plus `header_images`. It checks only files that exist.
- `test-readme.sh:1469-1483` -- the self-tests `a linked file of exactly 300,000 bytes` and `the header logo of exactly 300,000 bytes`. Both take the logo from `header_images`.
- `test-readme.sh:1266-1314` `url_allowed`/`chk_readme_links`:
  - Part 1 checks the Markdown targets and the `href`/`src` targets. An `http(s)` target is skipped. A relative target must be listed by `scan_files`, and until now this was what checked that the logo exists.
  - Part 2 checks each URL against `ALLOWED_HOSTS`, plus `HEADER_IMAGE_HOSTS` on lines up to `header_end`.
  - An entry that contains `/` matches as a path prefix (`"$entry"/*`), and `..` segments are refused. Prototyped: the entry `raw.githubusercontent.com/jbrandtmse/OcuTalon/main/docs/images` allows the logo URL on header lines only. It refuses the URL in the body, another repository's raw path, `main/README.md` and `docs/images/../../x`.
  - `https://github.com/jbrandtmse/OcuTalon/blob/main/LICENSE` already passes everywhere through `github.com/jbrandtmse/OcuTalon`.
- `test-readme.sh:1881-1906` `rule_readme_links` -- holds the self-test `a shields.io badge below the header` (the model for the new self-test). The new one goes beside it.
- `test-readme.sh:1324,1326,1898` -- `a header badge from another host` (the first img.shields.io in the header, line 5) and `a header logo with a different src` (`sub(/src="[^"]*"/, ...)` on line 1). Both still work with the new src. No change.
- `test-readme.sh:1527-1529` -- the teaser self-test `a header badge line below the header` picks the first header line that has `<img` and no `src="docs/images/`. After the change it would pick line 1, the logo `<h1>`, not the CI badge its comment names.
- `test-readme.sh:651-653` `chk_once` -- `grep -o 'docs/images/...'` still counts the logo once (inside the raw URL). No change.
- `test-readme.sh:2-92` -- the header comment. Lines 25-26, 30 and 87-89 describe the header allowances.
- Read only:
  - `release/checklist.sh:193-194` reads README line 1 for the product-name check, which still passes.
  - The `dev_names`/`public_text_scan` patterns do not match either URL (checked).
  - `test-boundaries.sh`'s path and key scan does not match them either.
  - `docs/images/ocutalon-logo.png` is tracked through `git add -f`, because `images/` is gitignored, and is 41,442 bytes.

## Tasks & Acceptance

**Execution:**
- `README.md` -- On line 1, replace `src="docs/images/ocutalon-logo.png"` with the ruled raw URL. On line 10, replace `href="LICENSE"` with the ruled blob URL. Change nothing else.
- `docker/tests/test-readme.sh`:
  - (a) Change heredoc lines 214 and 223 to match the new README lines byte for byte.
  - (b) Extend `HEADER_IMAGE_HOSTS` with the path entry `raw.githubusercontent.com/jbrandtmse/OcuTalon/main/docs/images`.
  - (c) Extend `header_images` so that a header `src` equal to exactly `https://raw.githubusercontent.com/jbrandtmse/OcuTalon/main/docs/images/<name>` is printed as `docs/images/<name>`, beside the relative form it already reads. Define the prefix once and reuse it.
  - (d) In `chk_readme_links`, add `header_images "$1"` to part 1's target stream. The mapped path then goes through the existing `*)` branch, so a logo that is not in the tree prints the existing `reaches no file or folder of the repository` message.
  - (e) Change the filter of the teaser self-test at line 1529 from `!/src="docs\/images\//` to `/<a href=/`, so that it copies the CI badge line again. Keep its label.
  - (f) Add the self-test `the header logo address below the header` to `rule_readme_links`: `st '<label>' 1 "$README" 'NR == 1 { b = $0 } { print } END { print ""; print b }' chk_readme_links`.
  - (g) Update the comments that describe the header allowances (lines 25-26, 30, 87-89, 211-212 and 304) so that they stay true.

  Rationale: the pins must follow the ruled README, and every check the relative src fed must keep reading the logo.

**Acceptance Criteria:**
- Given README.md line 1, when the story is done, then the only change on it is the logo `src`, which is now the ruled raw URL. `alt="OcuTalon logo"`, `width="160"`, `height="160"` and the rest of the line are unchanged.
- Given README.md line 10, when the story is done, then its `href` is `https://github.com/jbrandtmse/OcuTalon/blob/main/LICENSE` and nothing else in the badge has changed. `git diff -U0 -- README.md` shows only lines 1 and 10.
- Given `docker/tests/test-readme.sh`, when it runs, then its header pins carry the two new URLs, and the self-test `a header logo with a different src` is still flagged.
- Given a README whose header logo file is untracked, oversized, or whose raw address appears below the header, when `test-readme.sh` runs, then `readme-links` or `images` goes red. The logo's existence and size are still checked, and the raw allowance holds only on the header lines.
- Given the change, when `bash docker/tests/test-readme.sh` and `bash docker/tests/test-boundaries.sh` run, then both pass, and CI is green after the push.

## Spec Change Log

- 2026-11-10 (spec gate, lead): the Contest Planner approved the PUBLIC TEXT proposal (the self-test label `the header logo address below the header`, verbatim, in `rule_readme_links` after `a shields.io badge below the header`) and the supersession of 0.21's "local docs/images file" wording. Task (f) is confirmed; no other change.

## Review Triage Log

### 2026-11-10 - Review pass
- verdicts: 13 findings - high 0, medium 0, low 9, false 4, maybe-false 0
- findings:
  - `[low]` `reject` Blind: the LICENSE badge href is no longer checked against a file in the tree - the ruled blob URL is allow-listed by design (Design Notes, no exemption); the `licence` rule still requires LICENSE and the body links `[LICENSE](LICENSE)` stay relative; the fix adds a mapping for a ruled value
  - `[low]` `reject` Blind: the logo URL points at main while the checks read the branch tree - decided in-stage (identical tracked file, confirmed 200 image/png on main); no network check belongs in a hermetic test
  - `[false]` `reject` Blind: header_images silently drops an unrecognised src - any header change makes header_end 0 and `top` flags it, so no header edit escapes; the behavior is unchanged from the relative form
  - `[low]` `reject` Blind: thin self-test for the raw path prefix on header lines - a header line edit empties header_end, so the allowance cannot be exercised on an edited header; the confinement self-test and AC4 confinement mutation pin it
  - `[low]` `reject` Edge: the allowance admits any file under main/docs/images - the header is pinned word for word by `top`, so no other raw URL can sit on a header line; the path entry is the spec's decision
  - `[false]` `reject` Edge: an http:// or differently cased src is unmapped - the pinned header cannot carry it; `top` flags it first
  - `[low]` `reject` Edge: a relative header src would print the missing-file message twice - cosmetic, unreachable because the pinned header carries the absolute form
  - `[low]` `reject` Edge: existence and size read the branch tree while the URL resolves on main - same as the second row
  - `[low]` `defer` Verification gap: no permanent self-test pins that chk_readme_links feeds header_images into the existence check - pre-existing limit (the relative form had it); closing it needs a tree-list argument on chk_readme_links; recorded in `deferred:`
  - `[false]` `reject` Verification gap (other): no self-test that the allowance is not the bare host - the pinned header makes that unreachable; the AC4 confinement mutation turns the new self-test red
  - `[low]` `reject` Intent: the intent's surface is the imported Open Exchange listing, which no local check reaches - the lead smoke (GFM render and curl, both 200, image/png) covers what is reachable; the import itself is outside CI
  - `[low]` `reject` Intent: other relative references (body images, anchors) are untouched - the intent names two values and Boundaries keep the body links; DW-1052 is the related open item
  - `[false]` `reject` Verification gap (other): Rule 19 observations - every AC has a mutation line and every demonstrated mutation turned red as named; no finding

## Design Notes

**Governing ADs:**
- AD-29: README.md and `docker/` are Lane B's files, and Epic 0 may edit any lane's files in one story.
- AD-22: `test-readme.sh` is one of the hosted, hermetic checks of `ci/checks.sh`.

No AD governs README presentation, and the README-link convention (`README_URL`, `#readme`) is unaffected.

**Integration ACs:** this story changes two README lines and a check script. It introduces no service, module or shared component, so it needs no Integration AC.
- Consumed-by: none.
- Consumes: none.

**Ledger inbox:** none. DW-1052 (decision-pending, owned by the Contest Planner: the HTML `<h1>` header may not show its title and logo on Open Exchange) is related. This story is a partial response, the logo URL, and does not resolve or close it.

**Extend, don't copy (Rule 2):**
- `header_images` gains the raw form in place; it is not copied.
- `HEADER_IMAGE_HOSTS` gains a path entry that the existing `url_allowed` path-prefix grammar already handles.
- `chk_readme_links` reuses `header_images` and its existing "reaches no file" branch.
- The new self-test mirrors `a shields.io badge below the header`.

**Decided in-stage:**
- **The existence check stays in readme-links.** Before this story, `readme-links` checked that the logo exists, through the relative `src` (0.21's AC1 mutation), and `images` checked its size. Feeding the mapped `header_images` into `readme-links` keeps exactly that coverage with the existing message, so no new rule message is needed.
- **The allowance is a path entry, not a bare host.** It allows only this repository's `main/docs/images/` on the header lines (prototyped, Code Map).
- **No exemption for the blob href.** The LICENSE href passes the existing allow-list. No rule prefers relative links: `licence` pins only the Markdown `[LICENSE](LICENSE)` line of "Credits and licences", which stays.
- **PASS lines stay as they are.** The `readme-links` PASS line ("... and img.shields.io only in the header block") stays true, so it is unchanged.
- **The 0.21 parenthetical is superseded.** Story 0.21's ruling described `a header logo with a different src` as "the logo must be the local `docs/images/ocutalon-logo.png`". Today's ruling supersedes that. The self-test and its label are unchanged and still flag any other src.
- **The URL points at `main`.** The checks read the branch's copy of the logo, and the listing shows main's copy. The story does not change the logo, so the two are the same (inference: an identical tracked file).

### PUBLIC TEXT proposals

- `docker/tests/test-readme.sh`, in `rule_readme_links` after line 1897, a new self-test label: `the header logo address below the header`. It prints only as `  self-test: the header logo address below the header: not flagged` (or `: the edit changed nothing`) when the check cannot flag it.
  - Why it is needed: without it, moving the raw entry into `ALLOWED_HOSTS` would leave every rule green. No existing self-test would notice, so the confinement AC would have no pinning test.
  - If the Planner declines it: drop task (f), and record the confinement mutant as accepted, like 0.21's survivors.
  - [APPROVED 2026-11-10, Contest Planner ruling (owner delegation), relayed by the orchestrator] The label `the header logo address below the header` goes in verbatim, in `rule_readme_links` after `a shields.io badge below the header`. Task (f) stands. Replacing 0.21's "the logo must be the local docs/images file" ruling text with today's ruling is also approved; the self-test `a header logo with a different src` stays.

## Verification

Shared surfaces:
- README.md lines 1 and 10, the header block that `test-readme.sh` pins verbatim (`HEADER`, lines 213-226).
- `HEADER_IMAGE_HOSTS`.
- `header_images` and its readers: `chk_images`, the 300,000-byte self-tests and `chk_readme_links`.
- The teaser self-test filter at line 1529.
- `release/checklist.sh` reads README line 1 (read only).

A repo-wide `git grep` finds no other file outside `_bmad-output` that names `ocutalon-logo`, `href="LICENSE"` or `githubusercontent`. Standing criterion: every test added or changed passes on a fresh environment, in either order. `test-readme.sh` is one hermetic process, so order does not apply.

**Commands:**
- `bash docker/tests/test-readme.sh` (loop, about 23 s) -- expected: PASS for every rule and `test-readme: all rules passed`. The existing `printf: write error: Broken pipe` noise is expected.
- `bash docker/tests/test-boundaries.sh` (loop, about 11 s) -- expected: `test-boundaries: all rules passed`.
- `git diff -U0 -- README.md | grep -c '^[-+][^-+]'` (once) -- expected: 4, the two removed lines and the two added lines.
- `LC_ALL=C tr -d '\011\012\040-\176' < docker/tests/test-readme.sh | wc -c` (once) -- expected: 0, so the script is ASCII only.
- Both scripts again before finalizing (once). They are the story's whole suite, and CI runs the rest.
- Lead smoke (once, read only):
  - `jq -n --rawfile t README.md '{text:$t,mode:"gfm",context:"jbrandtmse/OcuTalon"}' | gh api markdown --input - | head -n 12` -- expected: the logo `<img>` with the raw URL and the LICENSE `<a>` with the blob URL.
  - `curl -sI` on both URLs -- expected: 200, and `image/png` for the raw URL.

Mutations to demonstrate, one per AC (revert each one and confirm that `git status --short` and `git diff --stat` are unchanged):
- mutation: AC1 -- in README line 1, change `/main/` to `/master/` in the raw URL -> `top` (`README.md:1: the line is not line 1 of the approved header block`).
- mutation: AC2 -- put README line 10's `href` back to `"LICENSE"` -> `top` (`README.md:10: ...`).
- mutation: AC3 -- put pin line 214 back to the relative src -> `top` on the real README. Then ignore `src` values in both of `chk_top`'s header comparisons (its awk line compare and `chk_block`) -> `self-test: a header logo with a different src: not flagged`, `FAIL top`; ignoring them in the awk compare alone stays green, because `chk_block` pins the line too.
- mutation: AC4, existence -- `git rm --cached -q docs/images/ocutalon-logo.png` -> `readme-links: the link (docs/images/ocutalon-logo.png) reaches no file or folder of the repository`. Re-stage with `git add -f`.
- mutation: AC4, size -- remove the raw-prefix mapping from `header_images` -> `self-test: the header logo of exactly 300,000 bytes is not flagged`, `FAIL images`.
- mutation: AC4, confinement -- move the raw entry from `HEADER_IMAGE_HOSTS` to `ALLOWED_HOSTS` -> `self-test: the header logo address below the header: not flagged`, `FAIL readme-links`.
- mutation: AC5 -- covered by the commands above; any of the mutations above turns `test-readme.sh` red.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** README line 1 now carries the ruled raw logo URL and line 10 the ruled blob LICENSE URL. `docker/tests/test-readme.sh` pins both lines, allows the raw path only on header lines (`HEADER_RAW_DIR`, in `HEADER_IMAGE_HOSTS`, never in `ALLOWED_HOSTS`), maps the raw logo address back to `docs/images/<name>` in `header_images`, and feeds that into the `readme-links` existence check. The teaser self-test filter picks the CI badge line again. The one approved new self-test label, `the header logo address below the header`, sits after `a shields.io badge below the header`.

**Files changed.**
- `README.md`: lines 1 and 10 only (`git diff -U0` shows four changed lines).
- `docker/tests/test-readme.sh`: header pin, `HEADER_RAW_DIR`, `header_images`, `chk_readme_links` target stream, teaser self-test filter, new self-test, comments.
- This spec: the AC3 mutation line, corrected (ignoring `src` in the awk compare alone stays green because `chk_block` also pins the line; both must be ignored).

**Review.** 13 findings: 0 patched, 1 deferred (low, in `deferred:`), 12 rejected with the reasons in the Review Triage Log. Follow-up review recommended: false (no patches).

**Verification.**
- `bash docker/tests/test-readme.sh`: `test-readme: all rules passed`. `bash docker/tests/test-boundaries.sh`: `test-boundaries: all rules passed`.
- README diff count 4; the ASCII check printed 0; the logo is tracked.
- Mutations demonstrated red and reverted byte-identical: AC1 (`top`), AC2 (`top`), AC3 (`top`, then both comparisons ignored gives `a header logo with a different src: not flagged`), AC4 existence (`reaches no file or folder`, restored with `git add -f`), AC4 size (`the header logo of exactly 300,000 bytes is not flagged`, `FAIL images`), AC4 confinement (`the header logo address below the header: not flagged`, `FAIL readme-links`).
- Lead smoke: the GFM render shows the raw logo `<img>` and the blob LICENSE `<a>`; `curl -sI` gave 200 `image/png` for the raw URL and 200 for the blob URL.

**Residual risk.** The checks read the branch tree while the URLs resolve on main; the logo is the same tracked file (200 on main). Whether Open Exchange's importer keeps absolute URLs is unreachable from CI.
