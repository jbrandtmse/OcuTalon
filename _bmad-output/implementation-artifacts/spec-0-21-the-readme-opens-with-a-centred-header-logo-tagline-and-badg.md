---
title: 'Story 0.21: The README opens with a centred header: logo, tagline and badges'
type: 'feature'
created: '2026-11-09'
status: 'done'
baseline_revision: '3a9a1fd473ae7caca9f910b6878d1e58f54e80a3'
baseline_commit: '3a9a1fd473ae7caca9f910b6878d1e58f54e80a3'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      The README header is an HTML h1, with no Markdown H1, so the Open Exchange listing might not show the title and logo as GitHub does.
    evidence: |-
      GitHub's markdown API renders the header correctly (measured). Whether the Open Exchange page renders the README's HTML header cannot be seen from the repository.
      Settles by opening the Open Exchange listing once it shows the README.
    location: >-
      README.md:1
    severity: medium (unverified)
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
  7. Self-tests, exactly the labels in the PUBLIC TEXT list, including the ruling's `top` self-test `a header logo with a different src` [AMENDED 2026-11-09, Contest Planner ruling]. Derive the header's lines and paths from `HEADER` and the README, as the images self-tests do, so no image file is named in a self-test.
  8. Update the header comments: line 2 (add Story 0.21), plus `top`, `teaser`, `images` and `readme-links`.

**Acceptance Criteria:**
- Given the logo files under `logo/`, when this story merges, then `docs/images/ocutalon-logo.png` is a tracked 200x200 PNG under 300,000 bytes made from `logo/OcuTalon-Icon.jpeg`.
- Given README.md, when this story merges, then lines 1 to 11 are exactly the approved header block (logo, title OcuTalon, the verbatim tagline, then the seven badges, each an image inside a link to its stated target), line 12 is empty, and everything from the opening paragraph down is unchanged.
- Given `test-readme.sh`, when it runs on the planned README, then every rule passes. When it runs on each broken copy in the I/O matrix, then the named rule flags it: a badge below the header (`teaser`, `readme-links`), a badge from another host (`top`, `readme-links`) and an image inside a link below the header (`teaser`). Every existing self-test still passes.
- Given the pushed branch, when its README page is opened on github.com in the light and the dark theme, then the logo (about 160 px), title, tagline and seven badges show centred, each badge image loads, and each badge links to its stated target.

### Review Findings

Code review 2026-11-09 (bmad-code-review; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, all completed; 11 findings after dedup: 5 patched, 6 dismissed, 0 deferred).

- [x] [Review][Patch] The `images` self-test printed `the header names no docs/images logo`, a self-test message not in the approved PUBLIC TEXT list [docker/tests/test-readme.sh `rule_images`] -- medium, fix-risk low, in-story. The no-logo case now prints the approved `the header logo of exactly 300,000 bytes is not flagged`, so an altered header still fails `images` closed with approved text only (observed on the tagline mutation).
- [x] [Review][Patch] `header_images` ran `head -n 0` when `header_end` is 0, which BSD `head` refuses (`illegal line count -- 0` on stderr; the script promises BSD and GNU tools) [docker/tests/test-readme.sh `header_images`] -- low, fix-risk low. It now reads the header lines with `awk -v n=... 'NR > n { exit } { print }'`; the altered-header run prints no `head:` error.
- [x] [Review][Patch] The teaser self-test `a header badge line below the header` copied the last header `<img>` line (the license badge) while its comment said the CI badge, and no self-test ran the CI badge line, whose host is allowed on every line, so only `teaser` can catch it below the header [docker/tests/test-readme.sh `rule_teaser`] -- low, fix-risk low. The self-test now copies the first header badge line (the CI badge) and the comment says so; label unchanged.
- [x] [Review][Patch] Spec: the surviving-mutants ruling was dated 2026-11-10; the cycle log records it at 2026-11-09T23:58:17Z [this spec, `## Verification`] -- low. Date corrected.
- [x] [Review][Patch] Spec: "What the badges show" had no measurement of the ruled online-demo website badge [this spec, Design Notes] -- low. Measured 2026-11-09 and added (it shows "online demo: live", brightgreen); the "brightgreen for the live demo" note stays true while the demo is up.
- [Review][Dismiss] `chk_top` prints extra, misplaced "a line between the header block ..." messages when the header is gone, because lines 1 to 11 are skipped whatever they hold -- low, developer-only diagnostics: the first message names line 1 correctly and the verdict is right; separating the cases adds branches to the state machine.
- [Review][Dismiss] No `teaser`, `readme-links` or `images` self-test runs on an altered header, and the readme-links `a header badge from another host` self-test goes red because `header_end` drops to 0, not because of `HEADER_IMAGE_HOSTS` -- the two surviving mutants ACCEPTED by orchestrator ruling (see `## Verification`); not re-filed.
- [Review][Dismiss] AC1's "200x200 PNG" is pinned only by the one-time `sips` command -- low; a static asset, the five existing `docs/images/*.png` share the gap, and a format check would need a new rule message (PUBLIC TEXT). Tracking and size are pinned by rules and mutations.
- [Review][Dismiss] AC4 (render on github.com, badges load) has no automated test -- by design: the spec makes it the lead's manual check after the push (Rule 3 / Rule 7), and a network check would break the hermetic script.
- [Review][Dismiss] The spec's frontmatter says `status: 'done'` while the tracker says `review` -- false: `done` is `bmad-build-auto`'s completion contract; the tracker is set by the review.
- [Review][Dismiss] The `top` self-test `a line before the first H2 section` and the `public-text` self-test `OpenClaw outside the note` now land inside the header -- false: both still go red for the property their labels name, and `a stray line between the header and the opening paragraph` covers the state-machine branch.

## Spec Change Log

- 2026-11-09 [AMENDED 2026-11-09, Contest Planner ruling] (spec gate, owner delegation, verbatim in the orchestrator's rulings file): header approved except the online-demo badge, now shields' live website check (`https://img.shields.io/website?url=https%3A%2F%2Fdemo.ocutalon.com&label=online%20demo&up_message=live&down_message=down`, alt "Online demo status"); link bar stays where 0.18 put it; rule messages, PASS lines and self-test labels approved, plus self-test `top`: `a header logo with a different src`.

## Review Triage Log

### 2026-11-09 — Review pass
- verdicts: 16 findings — high 0, medium 0, low 10, false 5, maybe-false 1
- findings:
  - `[maybe-false]` `[defer]` Blind: the README has no Markdown H1, so a consumer that takes the title from a first `# ` line (the Open Exchange listing renders the README) might show stray text — the HTML `<h1>` is the approved header (Decided in-stage), and GitHub renders it (measured with the markdown API); whether the Open Exchange page renders it cannot be seen from the repo. Deferred as medium (unverified); settles by viewing the Open Exchange listing once it shows the README.
  - `[low]` `[reject]` Blind: the logo `alt="OcuTalon logo"` beside the visible "OcuTalon" is read twice by a screen reader — the intent forbids rewording the alt texts (approved PUBLIC TEXT), so no fix is in scope.
  - `[false]` `[reject]` Blind: the header logo size check is tested only at its upper edge — a check that flagged every header image would flag the real 41,442-byte logo in the passing run; the 299,999-byte case of the shared size loop is pinned by the existing self-test.
  - `[low]` `[reject]` Blind: `readme-links` extracts only double-quoted lowercase `href`/`src` (no single quotes, unquoted, `srcset`, `poster`) — the spec names `href="..."` and `src="..."`; absolute URLs are still caught by `URL_RE`; a wider extractor adds parsing complexity for forms the README does not use. Same root cause as the Edge rows 1 and 4.
  - `[false]` `[reject]` Blind: the badge row repeats the link bar and some labels are weak — the header block is approved PUBLIC TEXT and the link bar placement was ruled; not a defect of the diff.
  - `[low]` `[reject]` Blind: the live-status badges add outside dependencies and show "down" when the demo is down — the website badge is the Contest Planner's ruling (a static "live" badge would stay green while the demo is down); the allow-list change is bounded to the header lines.
  - `[low]` `[reject]` Blind: the header lives in two places (README and the `HDR` heredoc) and the `top` message names neither — the message text is approved verbatim; the pin is deliberate and fails closed.
  - `[low]` `[reject]` Edge: single-quoted, unquoted or uppercase `href`/`src` values are never checked — same root cause as the Blind row above; not worth the extra parsing.
  - `[low]` `[reject]` Edge: `chk_images` does not report a header logo that is missing or not in the tree listing — the spec limits the `images` change to the size loop (item 6), the existing loop also skips a missing Markdown-image file silently (the listing check covers those), and `readme-links` flags a missing header logo (AC1 mutation observed red).
  - `[low]` `[reject]` Edge: `chk_images` does not check the alt text of the header `<img>` tags — `top` pins the header line by line, so a blanked alt text is flagged there.
  - `[low]` `[reject]` Edge: the spec's "whole file" claim for HTML targets holds only for the double-quoted lowercase form — the same root cause as above; the claim is true of the form the README uses.
  - `[low]` `[reject]` Verification gap: no `teaser`, `readme-links` or `images` self-test runs on an altered header, so `header_end` could be loosened with every self-test staying green — `top` still fails closed on any altered header, so the suite would stay red; a fix adds self-test labels beyond the approved list (PUBLIC TEXT lists the labels, plus one added `top` test), so it needs approval and is recorded under residual risks.
  - `[low]` `[reject]` Verification gap: the logo's PNG signature and 200x200 size are pinned only by the one-time `sips` command — a static asset; the five existing `docs/images/*.png` have the same gap, and the size, tracking and link are pinned by rules and mutations.
  - `[false]` `[reject]` Verification gap: AC4 (GitHub render, badges load) has no automated test or mutation — the spec makes it a manual check after the push (Rule 7), and a network check would break the hermetic script.
  - `[false]` `[reject]` Verification gap (other finding): the `images` size self-test passes on any output, like its siblings — the test resets every other image to 10 bytes, and the `mutation:` line shows `not flagged` when the check is removed.
  - `[false]` `[reject]` Intent alignment: the descriptive audit finds the diff implements the text-level pin with a narrow allowance, with rendering left to the manual check, and the spec file as a fourth changed file — no defect: the spec is the process artifact committed with the diff, and the audit names no unmet requirement.

## Design Notes

### Header markup (PUBLIC TEXT, for approval)

These are README.md lines 1 to 11. Line 12 is empty, and line 13 is the opening paragraph `Your integrations already tell you...`.

```html
<h1 align="center"><img src="docs/images/ocutalon-logo.png" alt="OcuTalon logo" width="160" height="160"><br>OcuTalon</h1>
<p align="center">An AI assistant that runs inside InterSystems IRIS Interoperability, with every decision in Visual Trace.</p>
<p align="center">
  <a href="https://github.com/jbrandtmse/OcuTalon/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://github.com/jbrandtmse/OcuTalon/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI status of the main branch"></a>
  <a href="https://github.com/jbrandtmse/OcuTalon/releases"><img src="https://img.shields.io/github/v/release/jbrandtmse/OcuTalon" alt="Latest release"></a>
  <a href="https://demo.ocutalon.com"><img src="https://img.shields.io/website?url=https%3A%2F%2Fdemo.ocutalon.com&label=online%20demo&up_message=live&down_message=down" alt="Online demo status"></a>
  <a href="#start-it-with-the-install-script"><img src="https://img.shields.io/badge/docker-install.sh-blue" alt="Docker: install.sh"></a>
  <a href="#install-it-with-ipm"><img src="https://img.shields.io/badge/IPM-ocutalon-blue" alt="IPM: ocutalon"></a>
  <a href="#whats-interesting"><img src="https://img.shields.io/badge/IRIS-AI%20Hub-blue" alt="IRIS: AI Hub"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
</p>
```

[AMENDED 2026-11-09, Contest Planner ruling] The header block above is APPROVED as PUBLIC TEXT (owner delegation, ~23:35Z), with one change: the online-demo badge is shields' live website check (the line above, verbatim from the ruling; it renders "online demo: live" while the demo answers and "online demo: down" otherwise), replacing the static `https://img.shields.io/badge/online%20demo-live-brightgreen` badge with alt text "Online demo: live", because a static "live" badge stays green while the demo is down. Same position, same link, still on img.shields.io inside lines 1-11; no allow-list change. If the `HEADER` constant in test-readme.sh embeds the URL, it carries this exact line.

What the badges show (measured 2026-11-09 against the live services): the CI badge shows "ci - passing". The version badge shows "release: v1.0.5" (the latest release). The static shields show "docker: install.sh", "IPM: ocutalon", "IRIS: AI Hub" and "license: MIT". The ruled website badge shows "online demo: live" in brightgreen (measured 2026-11-09 in code review). The repository is public. The header has no link bar. It stays under `## Try it in two minutes` (line 21 after the change), unchanged (see Decided in-stage).

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

[AMENDED 2026-11-09, Contest Planner ruling] The changed `top`/`teaser`/`readme-links` messages, the PASS lines and the self-test labels below are APPROVED as written, plus one more self-test the ruling adds: `top`: `a header logo with a different src` (the logo must be the local `docs/images/ocutalon-logo.png`; a header whose `<h1>` `<img src>` names any other file or host is flagged).

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
- [AMENDED 2026-11-09, Contest Planner ruling: link bar placement confirmed; it stays where Story 0.18 put it.] **Link bar:** it stays where it is (today line 11, line 21 after the change, under `## Try it in two minutes`), so the header ends with the badge row. Reasons:
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

mutation: AC1 (the logo tracked): `git rm --cached -q docs/images/ocutalon-logo.png`, run `bash docker/tests/test-readme.sh`, observed `readme-links: the link (docs/images/ocutalon-logo.png) reaches no file or folder of the repository` and `FAIL readme-links`; re-staged with `git add -f`; `git status --short` and `git diff --stat` identical to before.
mutation: AC2 (the approved header): README.md line 2 `every decision` changed to `each decision`, observed `README.md:2: the line is not line 2 of the approved header block` and `FAIL top` (the teaser rule also flags the header's `<img>` lines, since `header_end` is 0); restored from the scratch copy; README.md byte-identical (`cmp`), status and diff stat identical.
mutation: AC3 (readme-links, header_end bound): in `chk_readme_links` the test `[ "$n" -le "$he" ]` made true for every line (`-le 99999`), observed `self-test: a shields.io badge below the header: not flagged` and `FAIL readme-links: a broken copy was not flagged`; restored from the scratch copy, byte-identical (`cmp`), status and diff stat identical.
mutation: AC3 (teaser, header_end bound): the `<img` filter in `chk_teaser` set to `$1 > 99999` (every `<img` line exempt), observed `self-test: a header badge line below the header: not flagged` (with `an image tag` and `an image tag in capitals`) and `FAIL teaser: a broken copy was not flagged`; restored, byte-identical, status and diff stat identical. With the bound dropped instead (`$1 > 0`), the real header is flagged and `FAIL teaser` prints.
mutation: images self-test `the header logo of exactly 300,000 bytes`: `header_images` removed from the size loop of `chk_images`, observed `self-test: the header logo of exactly 300,000 bytes is not flagged` and `FAIL images: a broken copy was not flagged`; restored, byte-identical, status and diff stat identical.
mutation: ruling's `top` self-test `a header logo with a different src`: the src values ignored in the line-by-line comparison of `chk_top` and the header dropped from its `chk_block`, observed `self-test: a header logo with a different src: not flagged` (and `a header badge from another host: not flagged`) and `FAIL top: a broken copy was not flagged`; restored, byte-identical, status and diff stat identical.
(QA) Test framework for this story: `docker/tests/test-readme.sh` itself (its rules run on README.md; its self-tests prove each rule flags broken copies). All self-tests run in the default run (no skip switch). Each mutation below: one `bash docker/tests/test-readme.sh` run, restored from a scratch backup, files byte-identical (`cmp`), `git status --short` empty and `git diff --stat` empty after.
(QA) mutation: AC1 (the logo tracked): `git rm --cached -q docs/images/ocutalon-logo.png` → `readme-links: the link (docs/images/ocutalon-logo.png) reaches no file or folder of the repository`, `FAIL readme-links`; re-staged with `git add -f`, index entry identical (re-observed).
(QA) mutation: AC1 (logo under 300,000 bytes): `-ge "$IMAGE_LIMIT"` → `-gt` in `chk_images` → self-tests `a linked file of exactly 300,000 bytes is not flagged` and `the header logo of exactly 300,000 bytes is not flagged`, `FAIL images: a broken copy was not flagged`.
(QA) mutation: AC2/I-O "header altered" (tagline): README.md line 2 `every decision` → `each decision` → `top`: `README.md:2: the line is not line 2 of the approved header block` and `top: missing the line "<p align=..."`, `FAIL top`; because `header_end` is 0, `teaser` flags the header's `<img>` lines (1, 4 to 10), `readme-links` flags the six img.shields.io addresses, and `images` fails closed (`self-test: the header logo of exactly 300,000 bytes is not flagged`, re-observed in code review after the no-logo case moved to the approved message).
(QA) mutation: I-O "header altered" (stray line): `A stray line.` inserted as line 12 → `top`: `README.md:12: a line between the header block and the first H2 section ...` and `the lines of the block ... are not there one right after the other`; `teaser`, `readme-links` and `images` flag/fail closed as above.
(QA) mutation: I-O "header gone": lines 1 to 11 replaced by the bare `# OcuTalon` → `top`: `README.md:1: the line is not line 1 of the approved header block`, `FAIL top`; `teaser` (`a header badge line below the header: not flagged`), `images` and `readme-links` (`a shields.io badge below the header: not flagged`) fail closed.
(QA) mutation: I-O "image inside a link below the header": the `[![` grep removed from `chk_teaser` → `self-test: a linked image: not flagged` and `self-test: an image inside a link right after the hero image: not flagged`, `FAIL teaser`.
(QA) mutation: AC3 (teaser, `header_end` bound): `awk ... '$1 > he'` → `'$1 > 99999'` → `self-test: a header badge line below the header: not flagged` (also `an image tag`, `an image tag in capitals`), `FAIL teaser` (re-observed).
(QA) mutation: AC3 (readme-links, `header_end` bound): `[ "$n" -le "$he" ]` → `-le 99999` → `self-test: a shields.io badge below the header: not flagged`, `FAIL readme-links` (re-observed).
(QA) mutation: I-O "logo/links missing" (HTML targets): the `(href|src)="..."` extraction of `chk_readme_links` disabled → `self-test: an HTML link to a heading that is not there: not flagged` and `self-test: an HTML image of a file that is not there: not flagged`, `FAIL readme-links`.
(QA) mutation: AC2/I-O "badge from another host" (top): the line-by-line header comparison of `chk_top` disabled and the header dropped from its `chk_block` → `self-test: the tagline changed`, `a header badge from another host`, `a header logo with a different src` and `the bare title back as the first line: not flagged`, `FAIL top` (re-observed, wider).
(QA) survivors (no label closes them; recorded, not fixed): (1) `HEADER_IMAGE_HOSTS='img.shields.io badgen.net'` → all rules pass: `a header badge from another host` (readme-links) is flagged because the changed header makes `header_end` 0, not because of the host list. (2) `header_end` always printing `HEADER_LINES` → all rules pass: no `teaser`, `readme-links` or `images` self-test runs on an altered header. Neither changes the suite verdict, since `top` pins the exact header, the blank line and the opening paragraph by position and text, so a header that makes `header_end` 0 always turns `top` red. The consequence "header_end is 0, so the allowance is lost" was checked by hand in the three header mutations above.

- Surviving mutants, ACCEPTED (orchestrator ruling 2026-11-09, no new self-test labels): (1) adding another host to `HEADER_IMAGE_HOSTS` and (2) making `header_end` always print 11 leave every rule green. Both are accepted because `top` pins the exact header block, the empty line and the opening paragraph by text and position, so any header that would exploit either one already turns `top` red; pinning them would need new self-test labels (PUBLIC TEXT), which are not wanted.

(CR) mutation: teaser self-test `a header badge line below the header`, now copying the CI badge line: `'$1 > he'` → `'$1 > 99999'` in `chk_teaser` → `self-test: a header badge line below the header: not flagged` (also `an image tag`, `an image tag in capitals`), `FAIL teaser`; restored from the scratch copy, `cmp` identical, status and diff stat identical.
(CR) mutation: images self-test `the header logo of exactly 300,000 bytes` after the no-logo change: `header_images "$1";` removed from the size loop of `chk_images` → `self-test: the header logo of exactly 300,000 bytes is not flagged`, `FAIL images: a broken copy was not flagged`; restored, `cmp` identical, status and diff stat identical.
(CR) check: `header_images` without `head -n 0`: README line 2 `every decision` → `each decision` → `FAIL top`, `teaser`, `images` (approved message above) and `readme-links`, and no `head:` line on stderr (macOS BSD tools); README restored, `cmp` identical.

**Manual checks (if no CLI):**
- On the lead, after the push (Rule 7): open the pushed branch's README page on github.com in the light theme and the dark theme. Check that the logo shows at about 160 px with its navy tile intact, and that the title, the tagline and one centred row of seven badges follow. Check that each badge image has loaded (`naturalWidth > 0`) and that each link goes to its target: the ci.yml runs on main, Releases, https://demo.ocutalon.com, `#start-it-with-the-install-script`, `#install-it-with-ipm`, `#whats-interesting` and LICENSE. Check that the opening paragraph follows the header.

## Auto Run Result

Status: done
Blocking condition: none

**Summary:** the README opens with the approved centred header (logo and title, tagline, seven badges; the online-demo badge is the ruled website check). `test-readme.sh` pins that block by position and text (`header_end`) and gives it a narrow allowance: `<img>` tags in `teaser`, img.shields.io in `readme-links`, and the logo's size in `images`. `top`, `teaser`, `images` and `readme-links` are extended in place, `readme-links` now also checks HTML `href`/`src` values, and no rule was added to `RULES`.

**Files changed:**
- `docs/images/ocutalon-logo.png` -- new 200x200 PNG (41,442 bytes) from `logo/OcuTalon-Icon.jpeg`, force-added to the index.
- `README.md` -- line 1 replaced by the 11-line header block; nothing else changed.
- `docker/tests/test-readme.sh` -- `HEADER`, `header_end`, `header_images`, the four extended rules, the new self-tests (including `a header logo with a different src`) and the comments. The `public-text` self-test `OpenClaw outside the note` now selects `NR == 1` because the old `# OcuTalon` line is gone.
- This spec -- six `mutation:` lines, the triage log, the deferred item and this result.

**Review findings:** 16 reported, 0 patches applied, 1 deferred (Open Exchange rendering of the HTML header, medium unverified), 15 rejected with reasons in the Review Triage Log (10 low, 5 false). Follow-up review recommended: false (no patches).

**Verification:** `bash docker/tests/test-readme.sh` printed the approved PASS lines for `top`, `teaser`, `images` and `readme-links` and `test-readme: all rules passed`. `bash docker/tests/test-boundaries.sh` printed `test-boundaries: all rules passed`. The logo is 200x200 and 41,442 bytes, and it is listed by `git ls-files`. `head -n 1 README.md | grep -c OcuTalon` gives 1. The GitHub markdown API keeps the centred `<h1>` with the logo (width 160), two `<p align="center">` and seven badges with the approved alt texts. The mutation checks in the Verification section were observed red and reverted. The `test-readme.sh` source has no non-ASCII byte.

**Residual risks:**
- AC4 (github.com render in light and dark theme, badges load) is the lead's manual check after the push. GitHub's markdown API also wraps the `<h1>` logo in a link to the image file.
- No `teaser`, `readme-links` or `images` self-test runs on an altered header, so `header_end` is pinned through `top` and the observed mutation only. Adding one needs new self-test labels, which the approved list does not include.
- HTML `href`/`src` extraction covers the double-quoted lowercase form only.
