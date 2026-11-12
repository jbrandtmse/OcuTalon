---
title: 'Story 0.30: A shorter README for judges, with the install, feature and admin material moved word for word to GUIDE.md'
type: 'feature'
created: '2026-11-12'
status: 'done'
baseline_revision: '4c86e4ef840f23623f557d9f063465b4322a8ff3'
baseline_commit: '4c86e4ef840f23623f557d9f063465b4322a8ff3'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      The notice cards' install link in src/ocutalon/cls/OcuTalon/Core/Allowance.cls still gives the README anchor #install-it-yourself, which moved to GUIDE.md.
    evidence: |-
      INSTALLLINK (Allowance.cls:37) is https://github.com/jbrandtmse/OcuTalon#install-it-yourself. README.md no longer has that heading, so the link opens the README top, while the banner action of the same state (banner-stack.ts) opens GUIDE.md#install-it-yourself. src/** is outside the Q1-Q3 rulings, so the story could not change it. Needs a Planner ruling: GUIDE_URL#install-it-yourself in INSTALLLINK, with the pins that quote it (OcuTalon.Test.Core.Allowance, AllowanceInProduction, web/scripts/chat-view.test.mjs, allowance-sources.test.mjs, web/e2e-online/allowance/daily-cap.spec.ts and messages.spec.ts:132), and test-readme's product-links resolving address-form anchors (OcuTalon#x) against the README headings only. product-links accepts the anchor today because GUIDE.md has the heading.
    location: >-
      src/ocutalon/cls/OcuTalon/Core/Allowance.cls:37
    severity: medium
---

<intent-contract>

## Intent

**Problem:** README.md is 6,605 words (`wc -w`, head 53edce70), and every outside review names its length as the entry's weak spot.

**Approach:** The Contest Planner's brief governs this story. It was owner-approved, is binding word for word, and is cited as prompts/story-030-shorter-readme.md (Contest Planner brief, 2026-11-12 ~04:30Z); `epics.md` Story 0.30 carries the same ACs. Install, feature and admin material moves by mechanical extraction (never retyped) from the pre-story README to a new root file, GUIDE.md. README.md keeps the judges' parts plus two new pieces of prose: a pointer under "New since 1.0.0" and a closing "More" section. `test-readme.sh` pins follow their text to its new file and gain a word cap, a GUIDE check and cross-file anchor resolution.

## Boundaries & Constraints

**Always:**
- README.md keeps, in this order:
  - the header block, the opening paragraph, the video lines and the hero image;
  - "Try it in two minutes", with the link bar, the demo paragraph and the 4 steps;
  - "For judges: where to look";
  - "One incident, end to end";
  - "What's interesting", with its Visual Trace image and the heading `### New since 1.0.0` followed only by the pointer;
  - "Measured", which gets Story 0.29's H3 at its end whenever that story lands;
  - `## More`;
  - "Contest checklist";
  - "Credits and licences", with the not-affiliated note.
- The 0.28 Usability and Video rows stay as ruled. "sixteen ... fifteen" stays as it is, except one link target (Planner Edit 1, 2026-11-12 ~13:00Z): the Usability row's "[New since 1.0.0](#new-since-100)" points at `https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md#new-since-100`, visible text unchanged. README still keeps its `### New since 1.0.0` heading (with the pointer).
- [AMENDED 2026-11-12, Contest Planner rulings Q1-Q3 (owner's delegation, ~13:00Z): condition 5 of the brief is amended only as far as these go] Q1: `web/src/.../links.ts` gets `GUIDE_URL = 'https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md'`; the banner-stack install and set-a-key links, the Telegram card link and the settings channels-section link point at `GUIDE_URL#install-it-yourself`, `#set-a-model-key` and `#telegram`; no visible text changes; EXPERIENCE.md's "(README)" becomes "(GUIDE.md)" on those rows only. Q2: the three install.sh lines read exactly "The Troubleshooting section of GUIDE.md lists the usual causes and fixes." Q3 (RELEASE TOOL, approved): in `release/notes.sh:79` and `release/checklist.sh:474`, "the README's two commands" becomes "the guide's two commands", nothing else.
- GUIDE.md is in every scan README.md is in (Planner condition 1): test-boundaries' must-scan list and test-readme's link, anchor and ALLOWED_HOSTS checks, each proven by one mutation on GUIDE.md.
- Moved text is byte-identical to the pre-story README except for link targets (the method is in Design Notes). Kept text changes only in link targets.
- Every README link to a moved heading is an absolute URL, `https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md#<anchor>`. A GUIDE link to a kept README heading is the relative `README.md#<anchor>`.
- `wc -w README.md` is at most 2,300 (about 1,855 now, about 2,105 with 0.29's H3); the cap counts 0.29's H3 when it lands, and if 0.29 lands first its H3 sits under "## Measured" before "## More" (Planner conditions 2 and 4).
- The README and GUIDE text is exactly the text the Planner ruled at the PUBLIC TEXT gate (APPROVED 2026-11-12 ~13:00Z): the plan's scratch drafts `README.new.md` and `GUIDE.new.md` with exactly two ruled edits, Edit 1 above and Edit 2 (GUIDE, "Tests and CI": "among them the check of this README" becomes "among them the check of the README", a ruled hand edit the byte-identity check allows on that one line). "With a model, and without one" stays out of README.
- Shell stays ASCII, bash 3.2 and BSD/GNU safe, and hermetic.

**Never:**
- Change any README or GUIDE text beyond the ruled drafts and the two ruled edits.
- Change app code (`web/src/**`, `src/**`), the demo guide or catalog text, `install.sh`, `release/**`, `.github/**`, `ci/**`, `_bmad/**` or `eval/**`, beyond exactly the Q1-Q3 lines ruled above (the link targets and `GUIDE_URL` in Q1's four web files, Q2's three install.sh lines, Q3's two release lines).
- Weaken any pin, or add README anchors (Q1 option B) or land the app links at the README top (option C).
- Retype moved text.
- Keep the byte-identity check as a permanent rule. It pins a one-time move, so a later ruled edit of GUIDE text (Story 0.29's pointer) would fail it.
- Delete, skip or weaken any existing pin.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Move | Pre-story README (`git show <story_base>:README.md`) | README.md and GUIDE.md as in the plan's scratch drafts, plus 0.29's H3 if that story landed first. The byte-identity check passes | the check prints the first differing old line; exit 1 |
| Anchors | Any `#x`, `README.md#x` or `.../blob/main/GUIDE.md#x` link in either file | Resolves to a heading slug of its file; no two headings in one file share a slug | `readme-links: ... reaches no heading` |
| README to GUIDE, relative | A `GUIDE.md#x` or `GUIDE.md` link in README.md | flagged: README links GUIDE only by the absolute URL | rule fails |
| Word cap | README.md over 2,300 words | `word-cap` flags it; exactly 2,300 passes | rule fails |
| GUIDE missing | No GUIDE.md in the tree | every rule that reads it prints `FAIL <rule>: GUIDE.md is missing` (`no-guide` proves it) | fail closed |
| Text drifts | A pinned sentence edited in its new file, or moved back to the other file | the rule that pins it names it | rule fails |

</intent-contract>

## Code Map

- `README.md` and the new `GUIDE.md`: the blocks are split by heading text:
  - kept: header to `### New since 1.0.0`;
  - moved: the H3's body (its intro line and three H4 sections, to `## Measured`);
  - kept: `## Measured`;
  - moved: `## What you can use it for` to `## Contest checklist`;
  - kept: `## Contest checklist` to the end.
- `docker/tests/test-readme.sh` (2,442 lines):
  - The machinery: `rule_begin <rule> S1 S2 S3` (it fails closed through `have_readme`), `st <label> <slot> <input> <awk> <checker>`, and `finish`.
  - `st_facts`, `st_move` and `st_append` hard-code `"$README"`.
  - Readers: `headings` (slug at L299), `section` (H2 only), `image_links`, `header_end`.
  - The `HEADER` heredoc (L245) pins header lines 1-11, the badge hrefs included. `OTHER_H2` is at L282, the self-test loops `no-readme`/`rules` at L2404-2442, `inventory`/`chk_product_links` at L1466-1497 and `chk_readme_links` at L1519.
- `docker/tests/test-boundaries.sh:131`: the must-scan list for paths and keys (README.md is in it; GUIDE.md is added). L139 is its PASS text.
- `docker/tests/test-release-sequence.sh:2913-2918` (`t_static`, rule `static`): the IPM figures and the ruled A4 IPM paragraph, read from README.md.
- `docker/tests/test-ci-changes.sh:258`: `paths_case "the README runs no group"`. `ci/units.sh:251` `NOT_IRIS_INPUT_PATTERN` already declares `[^/]+\.md$`, so GUIDE.md runs no group.
- Web tests that read README.md:
  - `web/scripts/sources-docs.test.mjs`: `section(README, '### New since 1.0.0')` and the count sentence.
  - `more-to-try-view.test.mjs:411`: the count stays in README; the "Incident summaries" bullet moves.
  - `usage-docs.test.mjs:29` and `history-docs.test.mjs:31`: `'\n### New since 1.0.0\n'`.
  - `allowance-sources.test.mjs:52`: README headings for the banner anchors (Q1).
  - `sample-runbook-view.test.mjs:104`: still holds through README line 48 (none).
- Read-only evidence for the questions:
  - Q1: `web/src/app/banners/banner-stack.ts:21-31`, `rail/rail-view.ts:68,177`, `rail/telegram-card/telegram-card.ts:197` and `settings/channels-section.ts:96`; the e2e specs `banners.spec.ts:42-44`, `rail.spec.ts:118,489`, `settings.spec.ts:710` and `telegram-page.spec.ts:48`; EXPERIENCE.md L937-943 ("(README)").
  - Q2: `install.sh:373,389,396` and `docker/tests/test-install-script.sh:255`.
  - Q3: `release/notes.sh:79`, `release/checklist.sh:474`, `docker/tests/test-release-notes.sh:330` and `test-release-checklist.sh:816`.
- Ruled changes (Q1-Q3, lead-verified at 53edce70):
  - Q1: `web/src/app/links.ts` (add `GUIDE_URL` beside `README_URL`, L5); `web/src/app/banners/banner-stack.ts:29-31` (`installUrl`, `setKeyUrl` and `telegramUrl`: all three anchors move, so all three use `GUIDE_URL`); `web/src/app/rail/telegram-card/telegram-card.ts:197`; `web/src/app/settings/channels-section.ts:96`. `readmeSection(url, anchor)` lives at `web/src/app/rail/rail-view.ts:177`: make sure it yields `GUIDE_URL + '#' + anchor` for a URL without a hash (extend it, or add a sibling, Rule 2; record which). Untouched: `about/about-dialog.ts:108` and `guide/demo-guide.ts:634` link the README top (`README_URL`), which stays. EXPERIENCE.md L937-943: "(README)" becomes "(GUIDE.md)" on those rows only. Pins that follow: `product-links` in test-readme.sh (it must now prove GUIDE.md has `install-it-yourself`, `set-a-model-key` and `telegram` as heading slugs, so a renamed GUIDE heading goes red), `web/scripts/allowance-sources.test.mjs:52`, and the e2e specs `banners.spec.ts:42-44`, `rail.spec.ts:118,489`, `settings.spec.ts:710`, `telegram-page.spec.ts:48`.
  - Q2: `install.sh:373,389,396`; pins `docker/tests/test-install-script.sh:255` and test-readme's `install-pointer`.
  - Q3 (RELEASE TOOL, approved): `release/notes.sh:79`, `release/checklist.sh:474`; pins `docker/tests/test-release-notes.sh:330`, `test-release-checklist.sh:816`.
- Extra AC (Planner, Q3): notes and checklist rows that extract moved text. Lead sweep at 53edce70 (`git grep` over `release/`, `ci/`, `install.sh`, `docker/*.sh`, `.github/`): NO row of `release/notes.sh` or `release/checklist.sh` extracts text from README.md that moves. `NOTES_DEV_HEADING='## For admins and developers'` (notes.sh:77, used at L419 and L684) is the heading of the release-notes draft itself (`names_outside_section` scans the draft, not the README). The README readers are `note-readme` (checklist.sh:159, the not-affiliated note, stays in README) and `product-name` (checklist.sh:199-202, README line 1, stays). The IPM commands' registry run is a manual RC step (text only, Q3). So: no row is re-pointed at GUIDE.md; the implement stage re-runs this sweep, and if it finds a row that does extract moved text, that row reads GUIDE.md with one test proving it finds its text after the move. In either case, add one test each for `note-readme` and `product-name` run on the post-move tree (they still find their text in README.md, and fail if it is moved to GUIDE.md), so the move is proven harmless to them. Note for the Planner, not changed (beyond the approved hunk): the manual `public-links` row text (checklist.sh:104) says "the README's clone command", which moves to GUIDE.md; the Planner opens every GUIDE link at the RC.
- No change needed:
  - `release/checklist.sh` rows: `note-readme` (the note stays in README), `product-name` (README line 1), `readme` (it runs test-readme.sh) and `name-only-in-note` (GUIDE.md never names the inspiration).
  - `docker/tests/check-readme-video.sh`: it reads only the README's Video row, which stays.
  - `docker/tests/test-build-inputs.sh` and `.dockerignore`: the allow-list `*` keeps GUIDE.md out of the build context.
  - `docker/tests/test-release-notes.sh:919`: `names_outside_section` finds nothing in the new README.
  - `src/module.xml`: the package does not ship the README.

## Tasks & Acceptance

**Execution:**
- Scratch folder of the implement run (never the repo): the extraction script and the check script, as in Design Notes 4.
  - Run the extraction once on `git show <story_base>:README.md`, then splice in the Planner-ruled pointer and More text.
  - Write README.md and GUIDE.md from its output and run the byte-identity check. Paste its output under Verification.
- `README.md` and `GUIDE.md`: they are what the extraction writes; the only hand edit is the ruled text, if the Planner changes the drafts.
- `docker/tests/test-readme.sh`:
  - Add `GUIDE=GUIDE.md` with `have_guide` and `guide_p`.
  - `rule_begin` fails closed with `GUIDE.md is missing` when a slot names the guide. Add a `no-guide` loop that mirrors `no-readme`.
  - `st_facts`, `st_move` and `st_append` mutate `"$S1"` instead of `"$README"`, so rules whose S1 is the guide reuse them.
  - Move each rule to its file per the rule map in Design Notes 3. Self-test mutations anchored on a heading that left the file are re-anchored to one that stayed (e.g. `licence`'s "moved to another section").
  - Add `word-cap` and `guide`. Extend `readme-links`, `public-text`, `dev-only`, `images`, `once`, `telegram-demo`, `no-telegram`, `must-scan` and the `top`/`HEADER` pins.
  - Update the header comment's rule list and its "What it reads" list. Add both new rules to `RULES`.
- `docker/tests/test-boundaries.sh`: add `GUIDE.md` to the must-scan list for paths and keys (L131), and change the L139 PASS text to "README.md and GUIDE.md among them".
- `docker/tests/test-release-sequence.sh` (`t_static`): the DW-784 figures and the A4 paragraph pin read `$root/GUIDE.md`, and the labels say "GUIDE.md's IPM section". The A5 licence bullet stays on README.md.
- `docker/tests/test-ci-changes.sh`: add `paths_case "the guide runs no group" false none GUIDE.md` beside L258.
- `web/scripts/sources-docs.test.mjs`, `usage-docs.test.mjs`, `history-docs.test.mjs` and `more-to-try-view.test.mjs`:
  - The "New since 1.0.0" readers read GUIDE.md's `## New since 1.0.0`.
  - The README count sentence stays on README.md.
  - more-to-try's "Incident summaries" assertion reads GUIDE.md.
- [Planner] Apply Edit 1 (README Usability row: `(#new-since-100)` → `(https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md#new-since-100)`, visible text unchanged) and Edit 2 (GUIDE "Tests and CI": "among them the check of this README" → "among them the check of the README") after the extraction. Allow exactly Edit 2's line in the byte-identity check (Edit 1 is a link target, which the check already normalises). Update `judges-usability`'s `USE_TAIL` (test-readme.sh L247) to the new link target.
- [Q1] `links.ts` `GUIDE_URL`; the four links in banner-stack.ts (3), telegram-card.ts and channels-section.ts use it (Code Map); EXPERIENCE.md's "(README)" → "(GUIDE.md)" on those rows only; `product-links`, `allowance-sources.test.mjs` and the e2e pins follow, and `product-links` proves the three anchors are GUIDE.md heading slugs (mutation: rename GUIDE's `## Telegram` → `product-links` red).
- [Q2] The three install.sh lines read exactly "The Troubleshooting section of GUIDE.md lists the usual causes and fixes."; `test-install-script.sh:255` and `install-pointer` follow.
- [Q3, RELEASE TOOL approved] "the README's two commands" → "the guide's two commands" in `release/notes.sh:79` and `release/checklist.sh:474`, nothing else; `test-release-notes.sh:330` and `test-release-checklist.sh:816` follow. Extra AC: re-run the Code Map's sweep for notes/checklist rows that extract moved text; re-point any you find at GUIDE.md with one test each; add the `note-readme` and `product-name` post-move tests (Code Map). List the rows in the spec's Verification.
- [Condition 1] GUIDE.md in every scan README.md is in: `test-boundaries.sh` must-scan list (L131) and test-readme's link (`readme-links`), anchor and `ALLOWED_HOSTS` checks; one mutation each on GUIDE.md proving it is scanned (a home-folder path in GUIDE → test-boundaries red; a broken `#x` in GUIDE → `readme-links` red; a link to a host outside `ALLOWED_HOSTS` in GUIDE → red). Do not edit the `ALLOWED_HOSTS=` line itself (release/checklist.sh's no-outward allowance pins it whole); scanning GUIDE.md with it needs no edit to that line.
- [Conditions 2, 4] `word-cap` counts README.md whole (0.29's H3 included when it lands); if 0.29 has landed first, its H3 stays under "## Measured", before "## More".

**Acceptance Criteria:**
- Given README.md after the story, when `bash docker/tests/test-readme.sh` runs, then `top`, `word-cap` and `guide` pass:
  - `top`: the new H2 order, the header with the two GUIDE badge URLs, word for word.
  - `word-cap`: `wc -w` is at most 2,300.
  - `guide`: GUIDE.md exists; its line 1 is exactly `# OcuTalon guide: install, features and administration`; its H2s are in the moved order; the README holds the ruled pointer and More paragraph once each, and the More paragraph links GUIDE.md and each GUIDE H2.
- Given both files, when `readme-links` runs, then:
  - every Markdown and HTML link target in either file resolves: a `#x` to a heading of its own file, a `README.md#x` from GUIDE, a `https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md#x` from README, and a `https://github.com/jbrandtmse/OcuTalon#x` link, if any, each to a heading of the file it names;
  - files and hosts are checked as today, in both files;
  - a relative README link to GUIDE.md fails.
- Given the pre-story README, when the byte-identity check runs on the committed README.md and GUIDE.md, then it prints `byte_identity=pass` and that only link-target lines differ.
- Given the web tests and the check scripts, when they run, then every pin that followed its text passes, and the registry counts ("sixteen", "fifteen" and the 0.28 rows) pass unchanged.
- Given this story's diff, when inspected, then nothing changed outside the files the Code Map names, the Q1-Q3 rulings permitting.

## Spec Change Log

- 2026-11-12 ~13:10Z (lead, after the Contest Planner's rulings, prompts/story-030-rulings.md): the plan HALTed `blocked` on intent gap Q1-Q3 (Q1: the page's README links to #install-it-yourself, #set-a-model-key and #telegram land on moved sections while condition 5 forbade app changes; Q2: install.sh names "The Troubleshooting section of README.md"; Q3: release/notes.sh:79 and release/checklist.sh:474 say "the README's two commands"). Ruled A, A, A; condition 5 amended only that far (Boundaries, [AMENDED 2026-11-12]). PUBLIC TEXT approved with Edit 1 (Usability row link target to GUIDE.md#new-since-100) and Edit 2 (GUIDE "of this README" -> "of the README"). Added: Q1-Q3 files to the Code Map (banner-stack's telegramUrl included: its #telegram anchor also moves), the extra-AC sweep (no notes/checklist row extracts moved text; note-readme and product-name get post-move tests), conditions 1-4, and the matching Verification commands and mutations. Status reset blocked -> ready-for-dev by the lead's spec gate.

## Review Triage Log

### 2026-11-12 - Review pass
- verdicts: 21 findings (repeats of one root cause across layers share a row) - high 0, medium 2, low 11, false 8, maybe-false 0
- findings:
  - `[medium]` `[defer]` Allowance.cls:37 INSTALLLINK still points at the README anchor `#install-it-yourself` (blind hunter, edge-case hunter, verification-gap, intent-alignment) - real; the intent's own Never list excludes `src/**`, and Q1 named only the web links; recorded in `deferred:` for a Planner ruling (the fix: GUIDE_URL in INSTALLLINK and its pins).
  - `[medium]` `[patch]` Q1 wiring of `telegram-card.ts` and `channels-section.ts` has no locally run pin (verification-gap) - patched: `allowance-sources.test.mjs` gained a source ratchet for both call sites, mutation recorded.
  - `[low]` `[patch]` Several ACs lack a recorded `mutation:` line: `top`, `guide` pointer, `readme-links` relative link, `t_static`, `test-ci-changes`, `usage-docs`/`history-docs` (verification-gap) - patched: seven lines added under Verification, each applied and reverted.
  - `[low]` `[patch]` `test-install-script.sh` check labels (L779, L790, L803) still say "the README section" (edge-case hunter) - patched to "the guide section".
  - `[low]` `[patch]` `chk_must_scan` splitter lost its backslash separator (`[ \t\\;]+` became `[ \t\;]+`) without a reason (blind hunter) - patched: restored the original regex; `must-scan` still passes.
  - `[low]` `[reject]` Stale "README" wording in comments of `banner-view.ts`, `rail-view.ts`, `links.ts`, `channels-section.ts` (blind hunter, edge-case hunter, intent-alignment) - comment-only in `web/src`, which the Never list closes beyond the Q1 lines; nobody meets it in use.
  - `[low]` `[reject]` `Users.cls:310` account comment says the README explains the password change (edge-case hunter) - `src/**` is closed by the Never list; the comment is stored text only.
  - `[low]` `[reject]` EXPERIENCE.md L398 and L755 still say "README" (blind hunter) - Q1 ruled the three banner rows only.
  - `[low]` `[reject]` `release/checklist.sh` manual rows `public-links`, `readme` say "README" (blind hunter) - closed by the Never list; the spec records the note for the Planner.
  - `[low]` `[reject]` GUIDE text issues from moved text: "Email comes in a later release" against the POP3 item, the ambiguous word "guide", "README account" wording, no orientation lines, README "check this README" row, the run-on More paragraph (blind hunter) - the text is ruled word for word and pre-existing; a change needs a Planner ruling.
  - `[low]` `[reject]` `guide_p` helper not added (edge-case hunter claim) - `rule_begin` and `have_guide` carry the same job; no test needs a path helper.
  - `[low]` `[reject]` `banner-stack.ts` comment reworded "README sections" to "guide sections" (edge-case hunter claim) - comment-only, accurate, not worth a revert.
  - `[low]` `[reject]` `GUIDE_RULES` is a hard-coded list; the More paragraph's per-H2 link loop is not pinned apart from the exact match; `product-links` clause masked by the union message; `banner-view.test.mjs` still builds README fixtures (verification-gap other findings) - none can ship a wrong result: each is a duplicate path to a check that fails closed or a fixture that does not touch production wiring.
  - `[false]` `[reject]` GUIDE.md links 404 until the merge (blind hunter, edge-case hunter) - `blob/main` is the Planner's ruled address; the release order is the Planner's.
  - `[false]` `[reject]` Old README anchors are now dead (edge-case hunter) - Q1 option B (README anchors) was ruled out.
  - `[false]` `[reject]` `product-links` accepts any base URL (edge-case hunter) - it pins the three web anchors to GUIDE headings; the address-form check is part of the deferred item above.
  - `[false]` `[reject]` No committed byte-identity test (verification-gap) - the spec's Never list makes the check a one-time script.
  - `[false]` `[reject]` Spec Auto Run Result says ready-for-dev (blind hunter) - rewritten at finalize.
  - `[false]` `[reject]` `settings.spec.ts` S12 assertion is conditional (verification-gap) - existing structure of an e2e spec that the story only re-pointed.
  - `[false]` `[reject]` `printf: write error: Broken pipe` noise in test-readme.sh (verification-gap) - present before the story (14 lines then, 15 now); the run ends green.
  - `[false]` `[reject]` Intent-alignment readings A to D (intent-alignment) - descriptive; the one divergence it names is the INSTALLLINK item above.

## Design Notes

**Governing ADs:**
- AD-22: the checks stay hermetic. CI path classes: GUIDE.md is a declared non-input, so it runs no IRIS group.
- AD-29: Epic 0 may edit any lane's files.
- AD-23: the one image recipe; GUIDE.md is not in the build context.
- AD-13: Q1 is ruled A. The lead checked the spine: no AD's Rule governs the page's outbound documentation links, and Q1 changes link targets only, with no new route, privilege, script or visible text.
- No AD is contradicted and none is amended.

**Planner rulings (2026-11-12 ~13:00Z, Contest Planner under the owner's delegation; prompts/story-030-rulings.md, binding).**
- Q1 A: `GUIDE_URL = 'https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md'` in links.ts. The app links to `#install-it-yourself`, `#set-a-model-key` and `#telegram` go to GUIDE.md. No visible text changes. EXPERIENCE.md "(README)" becomes "(GUIDE.md)" on those rows only. The pins follow and prove GUIDE.md has the three anchors. Not B (no README anchors), not C (nothing weakened). The full web CI run is accepted.
  - Lead note: `banner-stack.ts`'s `telegramUrl` (L31) uses the same moved `#telegram` anchor, so it goes to GUIDE.md too. It is the same ruled change, not a new one.
- Q2 A: install.sh's three lines read exactly "The Troubleshooting section of GUIDE.md lists the usual causes and fixes."
- Q3 A, RELEASE TOOL hunk approved: "the guide's two commands" in notes.sh:79 and checklist.sh:474, nothing else.
  - Extra AC: rows that extract moved text read it from GUIDE.md, with one test each, named in the plan. The lead's sweep found none (Code Map). note-readme and product-name get post-move tests.
- PUBLIC TEXT APPROVED with two edits:
  - Edit 1: the Usability row's New since link goes to `…/GUIDE.md#new-since-100`.
  - Edit 2: GUIDE "Tests and CI" reads "of the README".
  - Approved verbatim: the GUIDE title, the 27-word pointer, `## More` and its paragraph, the README heading order and every link rewrite in report.txt.
  - "With a model, and without one" stays out of README. "the README account" stays as written (it is the account's name).
- Conditions:
  1. GUIDE.md is in every README scan, with one mutation each.
  2. The cap is 2,300 by `wc -w` and includes 0.29's H3.
  3. Q1-Q3 as ruled.
  4. If 0.29 lands first, its H3 goes under Measured, before More.
- At the RC the Planner opens every GUIDE link. 0.30 enters 1.0.8 only if it is green by the cut.

**Integration ACs (Rule 1/2):** this is a docs and tests story; it introduces no service, module or shared component.
- Consumes: Story 0.28's ruled rows and the More to try registry count.
- Consumed-by: Story 0.29. Whichever of 0.29 and 0.30 lands second carries a link-target-only edit.
  - If 0.30 lands first, 0.29's C2 pointer ("What changes without the agent?") sits in GUIDE.md's "What OcuTalon does", and its `(#with-the-agent-and-with-fixed-rules-only)` becomes `README.md#with-the-agent-and-with-fixed-rules-only`.
  - If 0.29 lands first, this extraction moves that paragraph and rewrites the link by the same rule.

**Ledger inbox:** none.

**1. Headings that move, in GUIDE.md's order, and their levels.** Line 1 is `# OcuTalon guide: install, features and administration`. Then:
- `## New since 1.0.0`, with the README H3's body below it unchanged: its intro line "Each item says where to try it. Visual Trace on the online demo is shared, so save and add nothing personal." and `#### Your integrations`, `#### Your documents and memory` and `#### Personas, the heartbeat checklist and the digest`;
- `## What you can use it for`;
- `## How you talk to it`;
- `## What OcuTalon does`;
- `## Install it yourself`, with `### What you need`, `### Get the image`, `### Start it with the install script`, `### Start it by hand`, `### The IRIS (non-Health) image`, `### Check that it is ready` and `### Install it with IPM`;
- `## Set a model key`, `## Sign in`, `## Telegram`, `## Stop, start and update` and `## Troubleshooting`;
- `## For admins and developers`, with `### Demo mode`, `### Change the README account's password`, `### Change the default IRIS accounts' passwords`, `### Repository layout` and `### Tests and CI`.

Decided in-stage:
- Every moved heading keeps its level and bytes. The H4s stay H4 under an H2, so the `new-since` pins carry over unchanged. GitHub renders the skipped level, and slugs do not depend on level.
- The two new structure lines are the title and `## New since 1.0.0`. The README keeps its own `### New since 1.0.0`, so `#new-since-100` resolves in both files.
- Each moved anchor is the same slug in GUIDE.md: `new-since-100`, `your-integrations`, `your-documents-and-memory`, `personas-the-heartbeat-checklist-and-the-digest`, `what-you-can-use-it-for`, `how-you-talk-to-it`, `what-ocutalon-does`, `install-it-yourself`, `what-you-need`, `get-the-image`, `start-it-with-the-install-script`, `start-it-by-hand`, `the-iris-non-health-image`, `check-that-it-is-ready`, `install-it-with-ipm`, `set-a-model-key`, `sign-in`, `telegram`, `stop-start-and-update`, `troubleshooting`, `for-admins-and-developers`, `demo-mode`, `change-the-readme-accounts-password`, `change-the-default-iris-accounts-passwords`, `repository-layout` and `tests-and-ci`.
- Implement stage (Rule 2: extend the machinery; no sibling script and no `readmeSection` sibling):
  - `test-readme.sh`: a fourth slot `S4` for `st`, `rule_begin` and `finish` (`sign-in-address` reads the guide, the install script, the compose file and the README; `product-links` reads the README, the list, In.cls and the guide). `st_facts`, `st_move` and `st_append` mutate `$S1`. `rule_begin` fails closed with `GUIDE.md is missing` when a slot names `$GUIDE`; the `no-guide` loop runs over `GUIDE_RULES` (every rule that names the guide). `guide_p` was not added: `rule_begin` gates every rule on `have_guide`, so rules read `$GUIDE` directly, as they read `$README`.
  - `readmeSection` (rail-view.ts) is not extended: it already yields `GUIDE_URL + '#' + anchor` for a URL without a hash, so rail-view.ts is untouched.
  - `product-links`: every inventory anchor must be a heading of the README or the guide, and `install-it-yourself`, `set-a-model-key` and `telegram` must be guide headings (the page opens them on `GUIDE_URL`). The union stays because `Allowance.cls` still gives the README address `OcuTalon#install-it-yourself` (a deferred finding, in the frontmatter). The inventory must also find the two anchors `install-it-yourself` and `set-a-model-key`, so a renamed constant cannot hide them.
  - Hygiene checks that read both files (they covered the whole README before the move): `commands` (forbidden wording), `key-account` ("No key, still works." and a key-shaped example), `ipm` (the load line appears once in the guide and not at all in the README), `dev-only`, `public-text` (the note, the credit and the pointers are the README's alone, and OpenClaw is allowed only as the README's note), `telegram-demo`, `no-telegram`, `images`, `once`, the media clauses of `teaser`, `readme-links`.
  - `readme-links` also resolves `README.md#x` and `GUIDE.md` addresses, and flags a relative `GUIDE.md` link in the README, in either form.
  - `install-pointer` also fails when install.sh still names a section of README.md.
  - The `top` rule pins exactly the seven README H2 sections in order (it used to pin the first six and the presence of the rest); `OTHER_H2` is replaced by `README_H2`.
- The byte-identity check (scratch `check2.py`) allows Edit 2's line exactly (the old line to the ruled line, nothing else). Its count reads 443 lines, 12 of which differ: 10 link-target lines from the extraction, Edit 1's Usability row (a link target) and Edit 2's line.
- Test pins outside the Code Map's list that follow Q1 (they pin the banner action, which now opens GUIDE.md): `web/e2e-online/busy.spec.ts` (`INSTALL`) and `web/e2e-online/allowance/messages.spec.ts:98` (`INSTALL_GUIDE`; line 132 keeps the README address, because the notice card's text is the server's). `banner-stack.ts`'s comment on the anchors now says "guide sections". `docker/tests/test-release-checklist.sh`: the synthetic base tree gets a `GUIDE.md`, and `t_guide_rows` (rule `guide-rows`) holds the post-move tests for `note-readme` and `product-name`.
- Extra AC sweep, re-run at implement: `git grep README` over `release/`, `ci/`, `install.sh`, `docker/*.sh` and `.github/` finds no row that extracts moved text from README.md (`note-readme` and `product-name` read the note and line 1, which stay). No row is re-pointed at GUIDE.md. `release/records/1.0.0/rc4.md` is a record of a past run and keeps its old wording.

Rewritten links, by old README line, all to `https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md#<same anchor>`:
- the header badges: L7 `#start-it-with-the-install-script` and L8 `#install-it-with-ipm`;
- the steps: L29 `#get-the-image`, L30 `#start-it-with-the-install-script` and L31 `#sign-in`;
- For judges: L39 `#troubleshooting` and `#install-it-with-ipm`, and L41 `#what-you-can-use-it-for`;
- Contest checklist: L422 `#start-it-with-the-install-script` and L423 `#install-it-with-ipm`.

In the moved text, only L153's `(#measured)` changes, to `README.md#measured`. Every other moved link resolves inside GUIDE.md.

**2. New prose (PUBLIC TEXT drafts; nothing new is claimed).**
- Pointer, 1 sentence, 27 words: "The guide lists what is new since release 1.0.0 for your integrations, your documents and memory, and personas, the heartbeat checklist and the digest: [New since 1.0.0](https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md#new-since-100)."
- More: the heading `## More`, between "Measured" and "Contest checklist", and one source line of about 3 rendered lines (49 words with the heading): "[The OcuTalon guide](https://github.com/jbrandtmse/OcuTalon/blob/main/GUIDE.md) has the rest: [New since 1.0.0](…#new-since-100), [What you can use it for](…), [How you talk to it](…), [What OcuTalon does](…), [Install it yourself](…), [Set a model key](…), [Sign in](…), [Telegram on your own install](…#telegram), [Stop, start and update](…), [Troubleshooting](…) and [For admins and developers](…)." Each "…" is the GUIDE URL with the section's anchor; the full text is in the scratch drafts.
  - "on your own install" keeps the `telegram-demo` rule.
  - Placing the More section after "Measured" keeps 0.29's H3 inside "Measured". This placement is the Planner's to move.
- Proposal, not applied: keep "With a model, and without one" and its table in README (149 words, 42 of them the paragraph). Recommended against: 0.29's measured comparison makes the same point and needs the room.

**3. Test placement (decided in-stage).** Rule map: `rule <file>`. "Both" means the rule checks each file; slot 1 is the file named first.

| File | Rules |
| --- | --- |
| README | `top` (new H2 order, `OTHER_H2`, `HEADER` with the 2 GUIDE badge URLs), `try-it` (steps 1-2 word for word with their GUIDE links), `interesting`, `measured`, `video`, `checklist-video`, `judges-usability`, `path`, `teaser` (top clauses), `licence` |
| README + GUIDE | `new-since` (README: the H3 sits after the image line and holds only the pointer; GUIDE: the `##` heading, the intro line, the 3 H4 headings and the 16 bullets), `sign-in-address` (the ready block in GUIDE; the "Try it" address and account in README; the "Sign in" address in GUIDE) |
| GUIDE | `use-cases`, `how-you-talk`, `outcomes`, `install`, `ipm`, `key-account`, `lan`, `demo-mode`, `admin-commands`, `after-start-log`, `telegram-section`, `telegram-strings`, `telegram-facts`, `commands` (the install.sh commands must be in GUIDE) |
| Both files (hygiene) | `images` (the two Break the feed images in GUIDE's "What OcuTalon does"), `once` (across both files together), `teaser`'s media and image clauses, `public-text` (the note, the credits and the licence pointers stay README-only), `dev-only` (GUIDE exempts its "For admins and developers" and the IPM load line), `telegram-demo`, `no-telegram`, `commands`' forbidden phrases, `readme-links` |
| New | `word-cap` (README `wc -w` at most 2,300; padded to 2,301 it is flagged, at 2,300 it is not), `guide` (see the ACs; it also pins the ruled pointer and More text word for word), `no-guide` (fail-closed loop) |
| Per the questions | `install-pointer` (Q2), `product-links` (Q1) |

`must-scan` names README.md and GUIDE.md. The rules stay in one script: extending the machinery is cheaper than a parallel `test-guide.sh`, which would need its own `ci/units.sh` entry (Rule 2).

Other checks:
- `test-boundaries.sh`: the must-scan list (above).
- `test-release-sequence.sh`: the A4 pin and the figures.
- `test-ci-changes.sh`: one case.
- The web tests (Tasks).
- No change: `release/checklist.sh`, `check-readme-video.sh`, `test-build-inputs.sh`, `ci/units.sh` and `test-release-notes.sh` (reasons in the Code Map).

**4. Verbatim-move method and byte-identity check.**
- The extraction script runs once on the pre-story README and splits by heading text, never by line numbers, so it also works with 0.29's H3 in place. It copies the line blocks unchanged, then rewrites only link targets:
  - a kept README `#x` whose heading moved becomes the GUIDE absolute URL;
  - a moved `#x` whose heading stayed becomes `README.md#x`;
  - an anchor in neither file stops the script.
- The check splices the old README back out of the two files and compares it line by line, after normalising `](…)` to `]()` and `href=`/`src=` values to empty:
  - the splice is README up to its `### New since 1.0.0`, then GUIDE from line 4 to `## What you can use it for`, then README `## Measured` up to `## More`, then GUIDE from `## What you can use it for` to the end, an empty line, and README from `## Contest checklist`;
  - the pointer, its blank line, the More section and GUIDE's two structure lines are left out.
- On the drafts: `byte_identity=pass`, 443 lines, 10 of which differ in link targets only.
- Falsified: "fifty" changed to "50" in README fails (old line 13), and "2.24" changed to "2.25" in GUIDE fails (old line 168). A changed link target still passes, by design: link targets are `readme-links`' job.

## Clarification Needed (resolved)

Resolved 2026-11-12 ~13:00Z by the Contest Planner (owner's delegation), cited as prompts/story-030-rulings.md (binding): Q1 A, Q2 A, Q3 A (RELEASE TOOL hunk approved), plus the extra AC for notes/checklist rows that extract moved text; PUBLIC TEXT APPROVED with Edit 1 and Edit 2; conditions 1-4. The rulings are written into Boundaries & Constraints (intent amendment of condition 5, marked [AMENDED 2026-11-12]), the Code Map, Tasks & Acceptance and Design Notes ("Planner rulings"). The question text that was here is kept in the Spec Change Log.

## Verification

Shared surfaces:
- `test-readme.sh`'s `RULES` (two new rules), `HEADER`, `OTHER_H2`, `TRY_FACTS` and every rule's file;
- README.md's text pins (the web tests listed in the Code Map; the "Its More to try panel has sixteen more things to try" count stays in README);
- `test-boundaries.sh`'s must-scan list;
- `test-release-sequence.sh`'s A4 pin;
- `test-ci-changes.sh`'s path cases;
- the release checklist rows that read the README, which are unchanged.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands**, from the worktree root, one per call, with `timeout: 600000`. No IRIS runtime and no MCP target is needed.
- `bash docker/tests/test-readme.sh` (loop, about 25 s): expected `test-readme: all rules passed`. `/bin/bash docker/tests/test-readme.sh` (once): the same.
- `wc -w README.md` (loop): at most 2,300.
- The byte-identity check on `git show <story_base>:README.md`, README.md and GUIDE.md (once): `byte_identity=pass`.
- `(cd web && node --test scripts/sources-docs.test.mjs scripts/more-to-try-view.test.mjs scripts/usage-docs.test.mjs scripts/history-docs.test.mjs scripts/allowance-sources.test.mjs scripts/sample-runbook-view.test.mjs)` (loop): 0 failed.
- `bash docker/tests/test-boundaries.sh` (loop, about 11 s), `bash docker/tests/test-release-sequence.sh static` (loop) and `bash docker/tests/test-ci-changes.sh` (once, about 17 s): all pass.
- `bash docker/tests/check-readme-video.sh` (once, online): passes unchanged.
- `bash ci/checks.sh` (once). If it would not finish in about 8 minutes, run its scripts one per call.
- `for f in docker/tests/test-readme.sh docker/tests/test-boundaries.sh docker/tests/test-ci-changes.sh docker/tests/test-release-sequence.sh; do LC_ALL=C tr -d '\011\012\040-\176' < "$f" | wc -c; done` (once): all 0.
- `git diff --name-only <story_base> -- web/src src install.sh release .github ci _bmad eval` (once): exactly `web/src/app/links.ts`, `web/src/app/banners/banner-stack.ts`, `web/src/app/rail/telegram-card/telegram-card.ts`, `web/src/app/settings/channels-section.ts` (plus `web/src/app/rail/rail-view.ts` only if `readmeSection` is extended), `install.sh`, `release/notes.sh`, `release/checklist.sh`; and `git diff -U0 <story_base> -- install.sh release` shows only the Q2/Q3 lines.
- `(cd web && npm run lint)` and `(cd web && npm run build)` (once, the Q1 change compiles); `(cd web && npm test)` (once, all web/scripts tests). The e2e pins (banners, rail, settings, telegram-page) run in CI (the Planner accepted the full web CI run); the lead's smoke opens the built page's three links and checks their targets.
- `bash docker/tests/test-install-script.sh` (loop), `bash docker/tests/test-release-notes.sh` (loop) and `bash docker/tests/test-release-checklist.sh` (loop): pass with the Q2/Q3 pins and the extra-AC tests.
- Lead (once): CI on the head is green on every workflow.

Mutations (one per AC; for each, record `mutation: <change> -> <test that went red>`, then revert and check that `git status --short` and `git diff --stat` are unchanged):
- AC README: README padded to 2,301 words -> `word-cap`; GUIDE's title reworded -> `guide`.
- AC links: a GUIDE anchor in README misspelt -> `readme-links`; `README.md#measured` renamed -> `readme-links`.
- AC byte identity: one moved word changed -> the check fails.
- AC pins: a Telegram step removed from GUIDE -> `telegram-section`; a "New since 1.0.0" bullet removed from GUIDE -> `new-since` and `sources-docs`.
- AC Q1: GUIDE's `## Telegram` renamed -> `product-links` (and `allowance-sources` for `## Set a model key`).
- AC Q2: one install.sh line back to "README.md" -> `install-pointer` / `test-install-script.sh`.
- AC Q3: notes.sh:79 back to "the README's" -> `test-release-notes.sh`; checklist.sh:474 likewise -> `test-release-checklist.sh`.
- AC condition 1: a home-folder path added to GUIDE -> `test-boundaries.sh`; a broken `#x` in GUIDE -> `readme-links`; a link to a host outside `ALLOWED_HOSTS` in GUIDE -> its rule.
- AC extra (Q3): the not-affiliated note moved from README to GUIDE -> `note-readme` test red; README line 1 moved -> `product-name` test red.
- AC Edits: the Usability row's target back to `#new-since-100` -> `judges-usability`; GUIDE's "of the README" back to "of this README" -> the pin that holds the ruled GUIDE line (add one in `guide` if none does).

### Implement-stage results (2026-11-12)

Byte identity (scratch `extract` run on `git show c205aec9:README.md`, then the two ruled hand edits; the check allows Edit 2's line exactly):
- `byte_identity=pass (443 lines; 12 differ in link targets only)`. The 12 are the 10 link-target lines of the extraction, Edit 1's Usability row (a link target) and Edit 2's line. README.md is byte-identical to the approved draft plus Edit 1, and GUIDE.md to the approved draft plus Edit 2; `cmp` of the regenerated files against the drafts was clean before the edits.
- `wc -w`: README.md 1,855 (cap 2,300), GUIDE.md 4,837.

Q1-Q3 sweep (re-run): `git grep README` over `release/`, `ci/`, `install.sh`, `docker/*.sh` and `.github/` finds no `release/notes.sh` or `release/checklist.sh` row that extracts moved text from README.md; no row is re-pointed at GUIDE.md. The README readers are `note-readme` (the note line stays) and `product-name` (README line 1 stays); `t_guide_rows` in `test-release-checklist.sh` proves both on a post-move tree. `git diff --name-only 4c86e4ef -- web/src src install.sh release .github ci _bmad eval` lists exactly `install.sh`, `release/checklist.sh`, `release/notes.sh`, `web/src/app/links.ts`, `banners/banner-stack.ts`, `rail/telegram-card/telegram-card.ts` and `settings/channels-section.ts` (rail-view.ts is untouched); `git diff -U0 4c86e4ef -- install.sh release` shows only the three Q2 lines and the two Q3 lines.

Commands run green: `test-readme.sh` (also with `/bin/bash`, 3.2.57), `test-boundaries.sh`, `test-release-sequence.sh static`, `test-ci-changes.sh`, `test-install-script.sh`, `test-release-notes.sh`, `test-release-checklist.sh`, `check-readme-video.sh` (online), the six web script tests (109 pass), `npm run lint`, `npm run build`, `npm test` (1,925 pass), and all 32 scripts of `CHECK_SCRIPTS` (what `ci/checks.sh` runs), a few per call: the full `test-release-sequence.sh` too, and eval-set, online-host, online-load, rehearsal and upgrade-harness among them. The non-ASCII count of the four edited check scripts is 0. The e2e pins (banners, rail, settings, telegram-page and the two e2e-online specs) type-check under `npm run lint`; their run is left to CI.

Mutations (each applied, observed red, reverted; after each revert `git diff`, `git status --short` and GUIDE.md hashed identical to before):
- mutation: README padded to 2,301 words -> `word-cap` red. The self-test also pads to 2,301 and 2,300 inside the rule.
- mutation: GUIDE's title reworded ("guide:" to "manual:") -> `guide` red.
- mutation: a GUIDE anchor in README misspelt (`GUIDE.md#sign-in` to `#sign-inn`) -> `readme-links` red.
- mutation: README `## Measured` renamed (GUIDE's `README.md#measured` reaches no heading) -> `readme-links` red (also `top`, `measured`, and `path`'s self-test, which anchors on that heading).
- mutation: one moved word changed (GUIDE, first `2.24` to `2.25`) -> `byte_identity=fail (lines 443 vs 443; first differing old lines [168])`.
- mutation: step 3 of GUIDE's Telegram section removed -> `telegram-section` red.
- mutation: GUIDE's "Where an answer came from" bullet removed -> `new-since` red and `sources-docs.test.mjs` red.
- mutation (Q1): GUIDE `## Telegram` renamed -> `product-links` red (also `guide`, `telegram-section`, `telegram-strings`, `telegram-facts`, `telegram-demo` and `readme-links`).
- mutation (Q1): GUIDE `## Set a model key` renamed -> `allowance-sources.test.mjs` red ("GUIDE.md has a heading for each of the two anchors") and `test-readme.sh` red (5 rules).
- mutation (Q2): one install.sh line back to "README.md" -> `install-pointer` red and `test-install-script.sh` red ("up fails: plain message with the logs command and the README section").
- mutation (Q3): notes.sh:79 back to "the README's two commands" -> `test-release-notes.sh` red (`ipm`).
- mutation (Q3): checklist.sh:474 back to "the README's two commands" -> `test-release-checklist.sh` red (`registry-row`).
- mutation (condition 1): a home-folder path added to GUIDE -> `test-boundaries.sh` red (`paths`).
- mutation (condition 1): a broken `[x](#nowhere)` added to GUIDE -> `readme-links` red.
- mutation (condition 1): a link to `https://example.org/a` added to GUIDE -> `readme-links` red.
- mutation (condition 1): GUIDE.md dropped from test-boundaries.sh's must-scan list -> `must-scan` red.
- mutation (extra AC): `row_note_readme` reads GUIDE.md instead of README.md (the note moved to the guide) -> `test-release-checklist.sh` red (`guide-rows`, and `base`, `note-rows` and the other rules that start from a passing base).
- mutation (extra AC): `row_product_name` reads line 1 of GUIDE.md (README line 1 moved) -> `test-release-checklist.sh` red (`name-rows` and `guide-rows`).
- mutation (Edit 1): the Usability row's New since target back to `#new-since-100` -> `judges-usability` red (`readme-links` stays green: the README keeps its own heading).
- mutation (Edit 2): GUIDE's "of the README" back to "of this README" -> `guide` red (the rule pins the ruled line).
- mutation (no GUIDE.md): GUIDE.md moved away -> 27 rules print `FAIL <rule>: GUIDE.md is missing` (every rule in `GUIDE_RULES`) and no other rule fails; the `no-guide` loop proves the same on every run.
- mutation (review pass): `readmeSection(GUIDE_URL, TELEGRAM_ANCHOR)` in `telegram-card.ts` back to `README_URL` -> `allowance-sources.test.mjs` red (the new Telegram-card and channels-section test; the same pin covers `channels-section.ts`).
- mutation (review pass, readme-links): the README pointer's target turned into the relative `GUIDE.md#new-since-100` -> `readme-links` red (also `guide` and `new-since`).
- mutation (review pass, guide): the ruled pointer paragraph removed from README -> `guide` red (also `new-since` and `top`).
- mutation (review pass, top): README's `## Measured` and `## More` headings swapped -> `top` red (also `guide` and `measured`).
- mutation (review pass, t_static): "about 90 MB" changed to "about 91 MB" in GUIDE's IPM paragraph -> `test-release-sequence.sh static` red.
- mutation (review pass, usage-docs, history-docs): GUIDE's `## New since 1.0.0` renamed `## New since 1.0.1` -> both `usage-docs.test.mjs` and `history-docs.test.mjs` red.
- mutation (review pass, test-ci-changes): `[^/]+\.md$` in `ci/units.sh` NOT_IRIS_INPUT_PATTERN narrowed to `README\.md$` (temporarily) -> `test-ci-changes.sh` red on "the guide runs no group" (and CLAUDE.md); reverted, `git diff` unchanged.

## Auto Run Result

Status: done
Blocking condition: none

Summary: README.md went from 6,605 to 1,855 words (cap 2,300). The install, feature and admin material moved word for word to the new root GUIDE.md (4,837 words) by the extraction script, with the two ruled edits applied by hand (Edit 1 in README, Edit 2 in GUIDE). `byte_identity=pass (443 lines; 12 differ in link targets only)`. `test-readme.sh` follows the text (`word-cap`, `guide`, `no-guide` and a GUIDE-aware `readme-links`, `public-text`, `dev-only`, `images`, `once`, `telegram-demo`, `no-telegram`, `product-links`, `must-scan`, `top`/`HEADER`), and the Q1 to Q3 rulings are in.

Files changed:
- `README.md`, `GUIDE.md`: the split text.
- `docker/tests/test-readme.sh`: rules re-pointed per Design Notes 3, plus the new rules and the fail-closed GUIDE slot.
- `docker/tests/test-boundaries.sh`, `test-ci-changes.sh`, `test-release-sequence.sh`, `test-install-script.sh`, `test-release-notes.sh`, `test-release-checklist.sh`: GUIDE.md in the scans and the pins that follow Q2 and Q3 (the checklist gets `guide-rows`, the post-move `note-readme` and `product-name` tests).
- `web/src/app/links.ts`, `banners/banner-stack.ts`, `rail/telegram-card/telegram-card.ts`, `settings/channels-section.ts`: Q1 (`GUIDE_URL`).
- `web/scripts/*.test.mjs` (sources-docs, usage-docs, history-docs, more-to-try-view, allowance-sources) and six e2e specs (banners, rail, settings, telegram-page, busy, allowance/messages): pins follow.
- `install.sh` (three lines, Q2), `release/notes.sh` and `release/checklist.sh` (one line each, Q3), EXPERIENCE.md ("(GUIDE.md)" on three banner rows).

Review: 21 findings from four layers. Patches applied: 4 (one medium, three low): a source ratchet for the Telegram-card and channels-section call sites, seven recorded mutation lines, three install-script check labels, the restored `must-scan` splitter. Deferred: 1 (medium), the notice cards' `INSTALLLINK` in `Allowance.cls`, which needs a Planner ruling because `src/**` is closed by the intent. Rejected with reasons: 16 (see the Review Triage Log). Follow-up review recommended: false (one medium patched, no high).

Verification (after the last patch): `test-readme.sh` (also under /bin/bash), `wc -w` 1,855, byte identity pass, the six web script tests (110 pass), `test-boundaries.sh`, `test-release-sequence.sh static`, `test-ci-changes.sh`, `test-install-script.sh`, `test-release-notes.sh`, `test-release-checklist.sh`, `check-readme-video.sh`, `npm run lint`, `npm run build`, `npm test` (1,926 pass), `bash ci/checks.sh` (all scripts passed), non-ASCII count 0 in the edited check scripts, and the `git diff --name-only` scope check lists exactly the ruled files. The e2e specs are not run here (they need a running stack; CI runs them).

Residual risks: the `INSTALLLINK` item above; GUIDE links use `blob/main` and 404 until the merge; the e2e pins are type-checked only.
