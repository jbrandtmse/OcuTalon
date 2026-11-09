---
title: 'Story 0.21: The README opens with a centred header: logo, tagline and badges'
type: 'feature'
created: '2026-11-09'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** README.md opens with a bare `# OcuTalon` heading, so a judge or visitor sees no logo, no one-line statement of what OcuTalon is and no sign of whether it is healthy before the body starts. `docker/tests/test-readme.sh` refuses any HTML image, any image inside a link and any image host outside `docs/images/`, so a badge header cannot pass it today.

**Approach:** Add `docs/images/ocutalon-logo.png` (200 px, from `logo/OcuTalon-Icon.jpeg`). Replace line 1 of README.md with the approved centred header block (logo and title, tagline, badge row) given byte for byte in Design Notes. Give `test-readme.sh` a header allowance for that one block only: it is recognised by its position (line 1) and its exact text. Every existing rule keeps its strength from the first line after the header, and new self-tests prove that the allowance does not leak.

## Boundaries & Constraints

**Always:**
- The README's lines 1 to 11 are exactly the block under "Header markup (PUBLIC TEXT, for approval)". Line 12 is empty. Line 13 is the opening paragraph `Your integrations already tell you...`, unchanged. Everything from the opening paragraph down stays byte-identical, the link bar under `## Try it in two minutes` included.
- The tagline is exactly `An AI assistant that runs inside InterSystems IRIS Interoperability, with every decision in Visual Trace.`
- Product files changed: `README.md`, `docker/tests/test-readme.sh` and the new `docs/images/ocutalon-logo.png`, and nothing else.
- The header allowance applies only while the README's first 11 lines are exactly the approved block, followed by an empty line and the opening paragraph (`header_end` below). Otherwise no line is exempt.
- In the header block, only `<img>` tags are exempt from the teaser rule's media-tag check, and img.shields.io is allowed only on the block's lines. `ALLOWED_HOSTS` stays as it is.
- Every existing rule and self-test keeps flagging what it flags today. The one self-test that pinned "opens with `# OcuTalon`" moves to the new shape and is not deleted.
- `test-readme.sh` stays ASCII-only and portable to bash 3.2 with BSD or GNU tools. The approved header goes in as a quoted heredoc constant, like `TRY_B109`.
- Every rule message and self-test label is exactly as listed under "README-check rule messages (PUBLIC TEXT, for approval)".

**Never:**
- Never reword the tagline, the alt texts, the badge labels or the link targets. If a README rule other than `top`, `teaser`, `images` or `readme-links` refuses the approved header, HALT `blocked` with blocking condition `intent gap: README rule <name> refuses the approved header: <rule output>`.
- Never edit `.gitignore` (its `images/` line guards Early Access image folders). The logo is force-added instead.
- Never move or edit the link bar, never keep a Markdown `# OcuTalon` heading, and never edit, recolour or crop anything under `logo/`.
- Never delete or weaken a rule or self-test, and never add a rule to `RULES` (the change extends four existing rules).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Approved header | README.md as planned | `PASS` for every rule, `test-readme: all rules passed` | No error expected |
| Badge below the header | the header's CI badge line, or its license shields badge line, copied to the end | `teaser`: `an HTML media tag`; for the shields line also `readme-links`: `the address https://img.shields.io/... is not on the allow-list` | self-test fails the rule if not flagged |
| Badge from another host | `img.shields.io` of one header badge changed to `badgen.net` | `top`: the line is not line N of the approved header block; `readme-links`: `https://badgen.net/...` is not on the allow-list | as above |
| Image in a link below the header | `[![x](docs/images/<first image>)](LICENSE)` put after the hero image line | `teaser`: `an image inside a link` | as above |
| Header altered or gone | the bare `# OcuTalon` back, a stray line after the header, or the tagline changed | `top` flags. `header_end` is 0, so the header's `<img>` tags and shields addresses are flagged too | as above |
| Logo too big or missing | the logo at 300,000 bytes in the size root, or an HTML `src`/`href` to a missing file or heading | `images`: `... is 300000 bytes, not under 300000`; `readme-links`: `reaches no file or folder` / `reaches no heading` | as above |

</intent-contract>

## Code Map

- `README.md` -- line 1 is `# OcuTalon`, line 2 is empty and line 3 is the opening paragraph. The link bar is line 11, under `## Try it in two minutes` (line 9; Story 0.18 Edit 1, not pinned by the check). The heading slugs `whats-interesting`, `start-it-with-the-install-script` and `install-it-with-ipm` exist (lines 43, 151 and 204). After the change the opening paragraph is line 13 and the link bar line 21.
- `logo/OcuTalon-Icon.jpeg` -- 2048x2048 JPEG, an eye mark on a navy tile. This is the source. The light and dark logos are 2752x1536 wordmarks.
- `.gitignore:8` `images/` -- this line ignores `docs/images/ocutalon-logo.png` (`git check-ignore` confirmed it). The five existing `docs/images/*.png` are tracked because they were force-added. `lib-scan.sh` `scan_files` (`ls-files -co --exclude-standard`) lists an ignored file only once it is staged.
- `docker/tests/test-readme.sh` (1,960 lines):
  - lines 5-89: the rule header comments (`top`, `teaser`, `images` and `readme-links` change).
  - 186-207: the approved-text constants (`OPENING`, `TEASER`). `HEADER` goes here.
  - 233-275: the Markdown readers (`headings`, `image_links`, `section`). The new `header_end` goes beside them.
  - 410-438: `chk_top`. Its awk state 0 pins the first line `# OcuTalon`; `chk_block top "# OcuTalon\n\n$OPENING"`.
  - 563-606: `chk_images` and its size loop over `image_links` targets.
  - 615-641: `chk_teaser`. Line 632 greps `<(img|iframe|video|embed|object|picture)` over the whole file; line 633 greps `[![`.
  - 1223-1264: `ALLOWED_HOSTS`, `URL_RE`, `url_allowed` and `chk_readme_links`. Targets come only from Markdown `](...)`; the URL loop covers the whole file.
  - 1268-1298: `rule_top` and its self-tests; line 1271 is the `# Other` first-line self-test.
  - 1392-1429: `rule_images`; the size self-tests are at 1414-1422.
  - 1444-1465: `rule_teaser`.
  - 1814-1835: `rule_readme_links`.
  - 1925: `RULES` (unchanged).
- `release/checklist.sh:193-194` -- read only. Its product-name check reads README line 1. Line 1 still holds `OcuTalon`.
- Read-only evidence: no README link, page anchor (`inventory`) or server text uses `#ocutalon`. GitHub's markdown API (measured 2026-11-09, below) keeps `align`, `width`, `height`, `alt` and `href` and gives an HTML `<h1>` no anchor.

## Tasks & Acceptance

**Execution:**
- `docs/images/ocutalon-logo.png` -- run `sips -s format png -Z 200 logo/OcuTalon-Icon.jpeg --out docs/images/ocutalon-logo.png`, then stage it at once with `git add -f -- docs/images/ocutalon-logo.png` (index only, never a commit), so that `scan_files`, the diff and the finalize commit see it. Measured in planning: 200x200 RGB PNG, 41,442 bytes, and no local path or user name in its bytes.
- `README.md` -- replace line 1 (`# OcuTalon`) with the 11 lines of the header block, byte for byte, and keep the empty line after them. Change no other byte.
- `docker/tests/test-readme.sh` -- the following changes, all ASCII:
  1. `HEADER` constant: the block, as a quoted heredoc with its trailing newline stripped; `HEADER_LINES` is its line count (11). Add `HEADER_IMAGE_HOSTS='img.shields.io'`.
  2. `header_end <file>`, beside `image_links`: prints `HEADER_LINES` when the file's first lines equal `HEADER`, the next line is empty and the line after it is `OPENING`; otherwise prints 0.
  3. `chk_top`: lines 1 to `HEADER_LINES` must equal `HEADER` line by line, and the first line that differs is printed. The existing state machine starts at the line after the header. `chk_block top "$HEADER\n\n$OPENING"` replaces the `# OcuTalon` block. Messages follow the PUBLIC TEXT list.
  4. `chk_teaser`: the `<img` part of the media-tag grep skips lines up to `header_end`. `iframe`, `video`, `embed`, `object`, `picture` and `[![` are checked on every line, as now.
  5. Extend `url_allowed <url> [extra hosts]` (Rule 2: extend the sibling, no copy). `chk_readme_links` checks URLs on lines up to `header_end` with `HEADER_IMAGE_HOSTS` added, and every other line exactly as now. It also takes `href="..."` and `src="..."` values (whole file) through the same target `case` as Markdown `](...)` targets.
  6. `chk_images`: the size loop also reads the `docs/images/` `src` values on lines up to `header_end`.
  7. Self-tests, exactly the labels in the PUBLIC TEXT list. Derive the header's lines and paths from `HEADER` and the README, as the images self-tests do, so no image file is named in a self-test.
  8. Update the header comments: line 2 (add Story 0.21), plus `top`, `teaser`, `images` and `readme-links`.

**Acceptance Criteria:**
- Given the logo files under `logo/`, when this story merges, then `docs/images/ocutalon-logo.png` is a tracked 200x200 PNG under 300,000 bytes made from `logo/OcuTalon-Icon.jpeg`.
- Given README.md, when this story merges, then lines 1 to 11 are exactly the approved header block (logo, title OcuTalon, the verbatim tagline, then the seven badges, each an image inside a link to its stated target), line 12 is empty, and everything from the opening paragraph down is unchanged.
- Given `test-readme.sh`, when it runs on the planned README, then every rule passes. When it runs on each broken copy in the I/O matrix, then the named rule flags it: a badge below the header (`teaser`, `readme-links`), a badge from another host (`top`, `readme-links`) and an image inside a link below the header (`teaser`). Every existing self-test still passes.
- Given the pushed branch, when its README page is opened on github.com in the light and the dark theme, then the logo (about 160 px), title, tagline and seven badges show centred, each badge image loads, and each badge links to its stated target.

## Spec Change Log

## Review Triage Log

## Design Notes

### Header markup (PUBLIC TEXT, for approval)

These are README.md lines 1 to 11. Line 12 is empty, and line 13 is the opening paragraph `Your integrations already tell you...`.

```html
<h1 align="center"><img src="docs/images/ocutalon-logo.png" alt="OcuTalon logo" width="160" height="160"><br>OcuTalon</h1>
<p align="center">An AI assistant that runs inside InterSystems IRIS Interoperability, with every decision in Visual Trace.</p>
<p align="center">
  <a href="https://github.com/jbrandtmse/OcuTalon/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://github.com/jbrandtmse/OcuTalon/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI status of the main branch"></a>
  <a href="https://github.com/jbrandtmse/OcuTalon/releases"><img src="https://img.shields.io/github/v/release/jbrandtmse/OcuTalon" alt="Latest release"></a>
  <a href="https://demo.ocutalon.com"><img src="https://img.shields.io/badge/online%20demo-live-brightgreen" alt="Online demo: live"></a>
  <a href="#start-it-with-the-install-script"><img src="https://img.shields.io/badge/docker-install.sh-blue" alt="Docker: install.sh"></a>
  <a href="#install-it-with-ipm"><img src="https://img.shields.io/badge/IPM-ocutalon-blue" alt="IPM: ocutalon"></a>
  <a href="#whats-interesting"><img src="https://img.shields.io/badge/IRIS-AI%20Hub-blue" alt="IRIS: AI Hub"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
</p>
```

What the badges show (measured 2026-11-09 against the live services): the CI badge shows "ci - passing". The version badge shows "release: v1.0.5" (the latest release). The static shields show "online demo: live", "docker: install.sh", "IPM: ocutalon", "IRIS: AI Hub" and "license: MIT". The repository is public. The header has no link bar. It stays under `## Try it in two minutes` (line 21 after the change), unchanged (see Decided in-stage).

### README-check rule messages (PUBLIC TEXT, for approval)

`<f>` is the file, `<n>` a line number. Messages not listed here are unchanged in wording. Some now also print for the header's HTML values or for img.shields.io outside the header.

Changed messages:
- `top`: `<f>:<n>: the line is not line <n> of the approved header block`. It replaces `<f>:<n>: the first line is not "# OcuTalon"`.
- `top`: `<f>:<n>: a line between the header block and the first H2 section that is neither the opening paragraph, the teaser nor the image line`. It replaces `... between the title and the first H2 section ...`.
- `top`: `<f>: <k> image lines between the header block and the first H2 section, not exactly one`. It replaces `... between the title and ...`.
- `top`: the `chk_block` messages keep their format and now quote the header's first line: `top: missing the line "<first 60 chars>..."` and `top: the lines of the block "<first 40 chars>..." are not there one right after the other, in this order`.

Changed PASS lines:
- `PASS top: the header block, the opening paragraph, the teaser and the hero image, then the five top sections in order, and the other sections are there`
- `PASS teaser: the teaser is a plain link, word for word, two lines below the opening paragraph, with no media tag and only inline docs/images PNG images below the header block`
- `PASS readme-links: every link, Markdown or HTML, reaches a heading, a file or folder of the repository, or an allow-listed host, and img.shields.io only in the header block`

Unchanged wording, now also printed for the header's HTML or for img.shields.io outside the header:
- `readme-links: the link (<target>) reaches no heading`
- `readme-links: the link (<target>) reaches no file or folder of the repository`
- `readme-links: the address <url> is not on the allow-list`
- `images: <target> is <bytes> bytes, not under 300000`
- `<f>:<n>: an HTML media tag (the teaser is a plain link)`
- `<f>:<n>: an image inside a link (the teaser is a plain link)`

New self-test labels. Each prints only as `  self-test: <label>: not flagged` (or `: the edit changed nothing`) when the check fails. No new rule names.
- `top`: `the bare title back as the first line` (it replaces `a first line that is not the title`), `the header replaced by the bare title`, `a stray line between the header and the opening paragraph`, `a header badge from another host` and `the tagline changed`.
- `teaser`: `a header badge line below the header` and `an image inside a link right after the hero image`.
- `readme-links`: `a shields.io badge below the header`, `a header badge from another host`, `an HTML link to a heading that is not there` and `an HTML image of a file that is not there`.
- `images`: `the header logo of exactly 300,000 bytes` (its `st_note` text is `the header logo of exactly 300,000 bytes is not flagged`).

### Decided in-stage

- **Logo:** I chose the icon over the light logo. At about 160 px the light logo's tagline text cannot be read, its wordmark repeats the title, and its white box shows on GitHub's dark theme. The icon's navy tile reads on both themes and stays intact (brand rule). The image is shown at 160 px from a 200 px file.
- **Title:** an HTML `<h1 align="center">` on line 1, holding the logo and `OcuTalon`. A Markdown `#` heading cannot be centred on GitHub, because the `style` attribute is stripped. Losing the `#ocutalon` slug breaks nothing:
  - no README link, page anchor or server text uses it;
  - `product-links` and `readme-links` read only Markdown headings;
  - the title stays on line 1, so `release/checklist.sh`'s product-name check still reads the product name there;
  - the `top` rule now pins the header block in place of `# OcuTalon`.
- **Link bar:** it stays where it is (today line 11, line 21 after the change, under `## Try it in two minutes`), so the header ends with the badge row. Reasons:
  - the epic context says "the existing link bar follows the new header unchanged" and that "Try it in two minutes" stays at the top of the body with the online demo link;
  - the top rule keeps "opening paragraph, teaser, hero" right after the header;
  - moving the bar would remove a line from the body and change Story 0.18's approved placement.
  
  The placement is small and reversible, and the Contest Planner sees it at this spec gate.
- **Badges:** brightgreen for the live demo and blue for the four other static badges, with no logos. The CI badge links to the main-filtered runs page, the same address as the link bar's CI link, because the badge shows main.
- **Check design:** the allowance is keyed to the exact block at line 1 (`header_end`), not to a host on the global list. A changed header loses every exemption and fails closed. No new rule is added: `top`, `teaser`, `images` and `readme-links` are extended. readme-links now also checks HTML `href`/`src` values, so the header's anchors, `LICENSE` and the logo path are checked like Markdown links.
- **Force-add:** `.gitignore`'s `images/` stays. The logo is staged with `git add -f`, as the five existing `docs/images/*.png` were.

### Constraints and links

- Governing ADs: AD-29 (README.md and `docker/` are Lane B's; Epic 0 may edit both lanes' files) and the "README link" convention (unchanged, since `#readme` and the section anchors are unaffected). No AD governs README presentation.
- Integration ACs: no consumers in this story (docs and README check). Consumes: none.
- Extend, don't copy: `url_allowed` (optional extra hosts), `chk_readme_links` (HTML target extraction), `chk_images` (size loop) and `chk_top`/`chk_teaser` are extended in place. `header_end` is a new reader, written in the same style as `section`/`image_links`.
- Ledger inbox: none.

## Verification

Shared surfaces: README.md's top block (lines 1 to 13). In `docker/tests/test-readme.sh`, the `top`, `teaser`, `images` and `readme-links` rules and their self-tests (pins from Epic 10 and Stories 0.17, 0.18 and 0.19). `release/checklist.sh`'s README line-1 product-name check (read only). Standing criterion: every test added or changed passes on a fresh environment, in either order. `test-readme.sh` is hermetic, one process and no state, so order does not apply. A fresh checkout passes once the logo is staged.

**Commands:**
- `bash docker/tests/test-readme.sh` (loop, about 40 s) -- expected: `PASS` for `top`, `teaser`, `images` and `readme-links` with the PASS texts above, then `test-readme: all rules passed`. The existing `printf: write error: Broken pipe` noise is expected.
- `bash docker/tests/test-boundaries.sh` (loop, about 11 s) -- expected: `test-boundaries: all rules passed`.
- `sips -g pixelWidth -g pixelHeight docs/images/ocutalon-logo.png; wc -c < docs/images/ocutalon-logo.png; git ls-files -- docs/images/ocutalon-logo.png` (once) -- expected: 200, 200, under 300000 bytes, and the path listed.
- `head -n 1 README.md | grep -c OcuTalon` (once) -- expected: 1.
- `jq -n --rawfile t README.md '{text:$t,mode:"gfm",context:"jbrandtmse/OcuTalon"}' | gh api markdown --input - | head -n 12` (once, read-only GitHub API, about 2 s) -- expected: `<h1 align="center"` with the logo `<img` (width 160), two `<p align="center"`, and seven `<a href=...><img ... alt="...">` lines with the alt texts above.
- Mutations (one per AC; revert each and confirm that `git status --short` and `git diff --stat` are byte-identical):
  - AC1: `git rm --cached -q docs/images/ocutalon-logo.png`, which leaves the file untracked and ignored, so `readme-links` goes red (`the link (docs/images/ocutalon-logo.png) reaches no file or folder of the repository`). Revert by re-staging with `git add -f`.
  - AC2: in README.md, change `every decision` to `each decision` in the tagline, so `top` goes red.
  - AC3: let `chk_readme_links` give `HEADER_IMAGE_HOSTS` to every line, so `FAIL readme-links: a broken copy was not flagged` (`a shields.io badge below the header: not flagged`). Separately, drop the `header_end` bound in `chk_teaser`, so the teaser self-test `a header badge line below the header` is not flagged.

**Manual checks (if no CLI):**
- On the lead, after the push (Rule 7): open the pushed branch's README page on github.com in the light theme and the dark theme. Check that the logo shows at about 160 px with its navy tile intact, and that the title, the tagline and one centred row of seven badges follow. Check that each badge image has loaded (`naturalWidth > 0`) and that each link goes to its target: the ci.yml runs on main, Releases, https://demo.ocutalon.com, `#start-it-with-the-install-script`, `#install-it-with-ipm`, `#whats-interesting` and LICENSE. Check that the opening paragraph follows the header.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
