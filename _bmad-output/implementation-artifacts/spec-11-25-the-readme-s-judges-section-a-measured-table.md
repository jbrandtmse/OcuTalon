---
title: "Story 11.25: The README's judges section: a Measured table"
type: 'feature'
created: '2026-11-05'
status: 'done'
baseline_revision: '5649a994972de3d07778d334b035974aceb6ca84'
baseline_commit: '5649a994972de3d07778d334b035974aceb6ca84'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** A judge reading the README sees what makes OcuTalon interesting but none of its measured results or costs; the release evaluations, the persona sweep and the online demo's usage log hold them, and a judge would have to run the evaluations to see them.

**Approach:** Insert the Contest Planner's ruled `## Measured` section (owner decision, public text ruled; lines 9-27 of the Planner's file, sha256 `bcabdc9cb70c3e915ba78627e3d1f21dab11e425741f327e038ee9dd19a44b68`, 1015 bytes, ASCII) byte for byte between "What's interesting" and "What you can use it for", and pin its heading, its eight row labels and its position in `docker/tests/test-readme.sh`.

## Boundaries & Constraints

**Always:**
- README.md changes only by the inserted section and its separating blank line: after line 24 (the `docs/images/vt-decision.png` image line) and the existing blank line 25 come the 19 ruled lines, then one new blank line, then `## What you can use it for`. Source of the text: `sed -n 9,27p ../../../collateral/readme-11-25-measured.md` from the worktree root (the contest folder's `collateral/`, outside the repo), or the fenced block under Design Notes "Ruled text" (identical); verify sha256 before and after inserting.
- `docker/tests/test-readme.sh` changes exactly as the diff under Design Notes "Pins" (`git apply`); result sha256 `1ecc422d948b7ee2a45628abe2444ff3ed8ec77e6e6f186961092b495f0d7936` from base `3965095b294f4a92ec1acdb4e7cef8b1227b6c66961d007fe4e93302c930901d`.
- The text's numbers and wording are owner-fixed: used exactly as given, never recomputed, rounded, linked or reflowed.

**Never:**
- No other file changes (outside `_bmad-output`): not `docs/**`, `release/**`, `ci/**`, `.github/**`, other `docker/tests/*.sh`, `src/**`, `web/**`.
- No change to any other README line; never copy the Planner's file path, its HTML comment (lines 1-7) or the word "Planner" into the README.
- No pin of a number, the intro line, the header row, the results or the two bullets; no existing check in `test-readme.sh` deleted or weakened.
- If README.md or `docs/*.md` states one of the table's numbers differently, or the text would need any change (a link, a heading level, a line break, an escape), HALT `blocked` `intent gap` quoting both places; never reconcile or reword.

</intent-contract>

## Code Map

- `README.md` (334 lines at d8a1e83a) -- 20 "## What's interesting", 22 its paragraph, 24 the `vt-decision.png` image line, 25 blank, 26 "## What you can use it for". After the insertion the section is lines 26-44 and "What you can use it for" moves to 46.
- `docker/tests/test-readme.sh` (1911 lines) -- header `top` 6-9, `interesting` 13-15; `H_TRY`/`H_INT`/`INT_IMAGE`/`H_USE`/`H_TALK` 178-182; helpers `headings` 234, `section` 266, `chk_facts` 275, `st` 334, `st_append` 349, `st_move` 353, `st_facts` 358, `rule_begin` 373, `finish` 388; `chk_top` 407 (first-four H2 order at 429-430); `TRY_B109` heredoc pattern 446; `chk_interesting` 485, `# use-cases` 503; `rule_top` 1237 (`finish top` 1262); `rule_interesting` 1282; `rule_use_cases` 1304; `RULES` 1873; the `unlisted` (`rules`) and `no-readme` checks 1875-1903 run every listed rule. Epic 34's regions (header `licence` ~39-44, `DOCKERFILE`/`dockerfile_p` 138/168, `chk_licence`, `rule_licence`) are untouched by the diff.
- README readers that must stay green (read only): `docker/tests/test-release-notes.sh` `static` 909-925 (the note word for word in README.md; `names_outside_section` from `lib-scan.sh` 72 finds nothing outside "For admins and developers" but the `IPM_LOAD` line); `docker/tests/test-boundaries.sh` 115 (README.md in the paths-and-keys scan); `release/checklist.sh` 153, 193 (note line, first line; untouched lines). `test-cpf.sh` and `test-bridge-guide.sh` read the docs pages, run as regression only.

## Tasks & Acceptance

**Execution:**
- [ ] `README.md` -- verify the source sha256, insert the 19 ruled lines plus one blank line after line 25, verify the section's sha256 and the whole-file rebuild check (Verification) -- AC1, AC2
- [ ] `docker/tests/test-readme.sh` -- `git apply` the diff of Design Notes "Pins" (check the result sha256); touch no other line -- AC3
- [ ] This spec -- record Verification results and one `mutation:` line per AC.

**Acceptance Criteria:**
- AC1 (the section). Given README.md, when read, then a `## Measured` section stands after the `docs/images/vt-decision.png` image line of "What's interesting" (one blank line between) and before "## What you can use it for" (one blank line between), and its 19 lines are byte-identical to the ruled text (sha256 `bcabdc9c...a44b68`): the intro line, the eight-row table (the "Routine attention decisions right" row reads `19 of 22 (target: 20)`) and the two differentiator lines.
- AC2 (smallest diff). Given the README at `baseline_revision`, when the ruled lines plus one blank line are inserted after its line 25, then the result equals README.md byte for byte; and `git diff --name-only <baseline_revision> -- . ':(exclude)_bmad-output'` lists only `README.md` and `docker/tests/test-readme.sh`.
- AC3 (pins). Given `test-readme.sh`, when run, then `PASS top` (the first five H2 sections: Try it in two minutes, What's interesting, Measured, What you can use it for, How you talk to it), `PASS measured` and `test-readme: all rules passed`; it fails when the heading is removed, renamed, set to another level or moved, or when a row label is removed, renamed or moved out of the section; it does not fail when a number or other wording of the section changes.
- AC4 (other readers). Given the README-reading scripts, when run, then `test-release-notes.sh` passes all rules (`static` included), `test-cpf.sh` and `test-bridge-guide.sh` pass, and `test-boundaries.sh` reports no README hit.

### Review Findings

Code review 2026-11-06 (bmad-code-review, full mode; layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, all at session model). 17 raw findings, 14 entries: 0 decision-needed, 2 patch (applied), 3 deferred (ledgered), 1 closed in-pass, 8 rejected.

- [x] [Review][Patch] No self-test proves `chk_measured` keeps the trailing ` |` of a label's first cell: with `p="| $label"` every self-test passed, so a label extended in place ("Routine attention decisions right today") went unflagged (verification-gap; med, fix-risk low: one `st` line) [docker/tests/test-readme.sh:1343]
- [x] [Review][Patch] The negative self-test's `mutate` succeeded when any one of its three edits applied, so a drifted README could quietly test less; the awk program now counts its edits and exits 1 unless all three apply (edge-case-hunter+verification-gap; low, fix-risk low: in-place edit of one line) [docker/tests/test-readme.sh:1345]
- [x] [Review][Defer] The row "The demo's incident, end to end with a live model: 30 of 30 runs" cites the eval demo gate, which runs no dry run, approval or fix run (`Gate.cls` header), and rc4's live rehearsal stopped at run 8 [README.md:34] — deferred: owner-ruled text, not editable by a story; DW-775 decision-pending owner=burndown, note for the Contest Planner (blind-hunter; med)
- [x] [Review][Defer] The row "Routine attention decisions right: 19 of 22" is the best of three rc4 attempts (19, 18, 18 of 22 in the Planner's sources) with no note [README.md:33] — deferred: owner-ruled text; DW-776 decision-pending owner=burndown, note for the Contest Planner (blind-hunter; med)
- [x] [Review][Defer] Nothing ties the table's numbers to later release evaluations [README.md:32] — deferred: out-of-footprint (`release/**`), numbers unpinned by the spec; DW-777 wontfix-accepted with reopen_if (blind-hunter; low)
- [x] [Review][Closed] AC4's `test-boundaries.sh` clause had no `mutation:` line — closed in-pass: mutation applied and observed red, line written under Verification (verification-gap; low)

**Rejected:**
- `low` test-readme.sh no longer matches the Pins diff's sha256 `1ecc422d...` and the Results/Auto Run Result still quote it (blind-hunter+acceptance-auditor): by-design, QA's added self-test pins AC3's negative clause (Rule 19) and no check was deleted or weakened; the fix is a spec edit. The current sha256 after this review is recorded under Verification.
- `low` the Results say "eight hunks" in test-readme.sh; the diff has seven (edge-case-hunter): spec-record miscount only, the fix is a spec edit; no hunk is in Epic 34's regions.
- `false` a second `## Measured` section can hide an empty first one (edge-case-hunter): `chk_readme_links` flags two headings with the slug `measured` (test-readme.sh:1243), so the suite fails.
- `false` spec frontmatter `status: done` vs sprint-status `review` (acceptance-auditor): the frontmatter is bmad-build-auto's build status; sprint status is synced by this review.
- `false` the implement and QA AC4 mutation lines disagree (acceptance-auditor): QA ran only `test-release-notes.sh`; both observations hold.
- `low` "19 of 22 (target: 20)" sits below its target (acceptance-auditor): owner-ruled text; AD-22 has the table report results, not redefine targets.
- `low` the demo row's "about 9 to 10 cents a day" can read as the whole running cost, hosting included (blind-hunter): owner-ruled wording; passed to the Planner as a note with DW-775.
- `low` the two bullets under Measured are not measurements and repeat the image caption (blind-hunter): owner-ruled text.

## Spec Change Log

## Review Triage Log

### 2026-11-05 - Review pass
- verdicts: 9 findings - high 0, medium 0, low 9 (reject), false 0, maybe-false 0 (the verification-gap and intent-alignment layers reported none)
- findings:
  - `[low]` `[reject]` Blind: 19 of 22 sits below its target (20) with no explanation -- the text is the owner-ruled public text, byte for byte; any clause is a wording change the story forbids (spec-bound).
  - `[low]` `[reject]` Blind: the table's sources are unnamed (no release, date or re-run path) -- ruled wording; adding provenance is a wording change, owner-only.
  - `[low]` `[reject]` Blind: the two zero rows and the cost rows carry no denominator -- ruled wording and numbers, never reworded.
  - `[low]` `[reject]` Blind: `chk_measured` pins labels, not the header or delimiter row -- Boundaries forbid pinning the header row; D2 pins the heading and the eight first cells only.
  - `[low]` `[reject]` Edge: header or delimiter row removed while label rows remain -- same as the row above; header row not to be pinned (Never).
  - `[low]` `[reject]` Edge: a row's Result cell emptied -- Never pins the results column.
  - `[low]` `[reject]` Edge: a label row inside a fenced block in the section -- theoretical; the ruled text has no fence and the guard would add branches.
  - `[low]` `[reject]` Edge: a future label with a backslash read by `awk -v` -- none of the eight labels has one; a theoretical hardening.
  - `[low]` `[reject]` Edge: a duplicated label row passes -- not a user-reachable failure of the ruled text; the guard would add a count branch.

## Design Notes

**Governing ADs.** AD-29 (README.md and `docker/tests/` are Lane B; Epic 11 may change either; no other open branch touches these two files, measured). AD-22 (`test-readme.sh` is a hermetic static check in the hosted `checks` job; the table reports the release-candidate evaluation's SM-1/SM-2 results, it does not redefine the targets). AD-20 (cost is per decision and per turn: the text's "Cost of one attention decision" and "each decision's message carries its exact tokens and cost" match it; it claims no per-step cost). No AC contradicts an AD's Rule or Prevents line. NFRs: none unmeasurable.

**Rule 1/2.** No service, module or shared component: a README section and its hermetic pins. No consumers in this story. Consumes: the Planner's ruled text. Consumed-by: none. Extend, don't copy: the position pin extends `chk_top`'s H2-order check in place; the new `measured` rule follows `chk_interesting`/`rule_interesting` and reuses `section`, `st`, `st_facts`, `st_move`, `rule_begin`, `finish` and the `TRY_B109` heredoc pattern; no helper is copied.

**Ledger (Rule 17).** Inbox for this story: empty; nothing to address or decline.

**Measured at plan (2026-11-05, a scratch copy of HEAD d8a1e83a, nothing in the worktree changed):**
- With the section inserted and no pin change, `test-readme.sh` fails only `top` ("the first four H2 sections are not, in this order..."); `dev-only`, `public-text`, `telegram-demo`, `interesting`, `images`, `readme-links` (slug `measured` unique) pass, so the words "Claude Haiku 5.5", "Visual Trace", "Orders production", "$0.0001" trip no rule. `test-release-notes.sh` 16/16 PASS (`static`: no `names_outside_section` hit), `test-cpf.sh` and `test-bridge-guide.sh` pass.
- With the diff below: all rules pass under bash 5 and `/bin/bash` 3.2.57; label renamed -> `FAIL measured`; `19 of 22` -> `18 of 22` -> all pass; baseline README -> `FAIL top`, `FAIL measured`; Measured and Use headings swapped -> `FAIL top`, `FAIL measured`, `FAIL use-cases`.
- GitHub rendering (its markdown API, gfm, repo context): an h2 "Measured", the eight-row table and two list items; the dollar amounts render as plain text (no math element; a `$x^2$` control did render as math). No wording change is forced.
- README.md and `docs/*.md` state none of the table's numbers.

**For the lead (outside this story).** HEAD d8a1e83a already fails `test-boundaries.sh` `paths` on exactly `_bmad-output/implementation-artifacts/epic-11-context.md:39` and `_bmad-output/planning-artifacts/epics.md:4800`: the charter wrote the Planner's file as an absolute home-folder path. Both files are the lead's bookkeeping; rewrite those paths (for example relative, as this spec does) before the implement dispatch, or the `checks` job is red. The implement stage never edits them; if it still sees exactly those two hits, it records them and goes on.

**Decided in-stage.**
- D1. The position pin is `chk_top`'s H2-order check, extended in place from four to five sections (`H_MEAS` between `H_INT` and `H_USE`), with its header line and `finish` label saying so: without it `top` fails on the inserted section (measured), and no check is deleted or weakened. Four `rule_top` self-tests prove it bites (removed, above "What's interesting", below "What you can use it for", one level down).
- D2. A new rule `measured` pins the heading (the section exists) and each of the eight labels as a row's first cell (`| <label> |` at the line start), section-scoped, so a renamed label or a row moved out is flagged. It pins no number; "50" in "Cost of diagnosing 50 failed orders" is part of the charter's label. A ninth row, the header row, the intro and the bullets are not pinned.
- D3. The insertion keeps the existing blank line 25 and adds one blank line after the section, so the neighbours are separated by single blank lines and the README diff is one hunk of 20 added lines.

**Ruled text** (README lines 26-44 after the insertion; byte-identical to lines 9-27 of the Planner's file):

```markdown
## Measured

From the real-model release evaluations (Claude Haiku 5.5), the persona sweep and the online demo's usage log:

| What was measured | Result |
| --- | --- |
| Incidents diagnosed with the right cause and fix | 9 of 10 (target: 8) |
| Routine attention decisions right | 19 of 22 (target: 20) |
| The demo's incident, end to end with a live model | 30 of 30 runs |
| Prompt-injection attempts that led to an action | 0 |
| Changes made without a person's approval | 0 |
| Cost of one attention decision | about $0.0001 |
| Cost of diagnosing 50 failed orders | $0.0005 to $0.0007 |
| The always-on online demo | about 9 to 10 cents a day |

Two things to look at in the demo:

- It works from real failures. The broken partner feed sends real orders that fail in the Orders production; OcuTalon reads the failed messages and groups them by cause into one incident.
- Every model request and every tool call is its own step in Visual Trace, and each decision's message carries its exact tokens and cost.
```

**Pins** (`docker/tests/test-readme.sh`, against d8a1e83a; `git apply --check` first; if whitespace was mangled, make the same hunks by hand and require the result sha256 above):

```diff
diff --git a/docker/tests/test-readme.sh b/docker/tests/test-readme.sh
index d1773b6..ae6a978 100755
--- a/docker/tests/test-readme.sh
+++ b/docker/tests/test-readme.sh
@@ -4,15 +4,17 @@
 #
 # What it pins, one rule each:
 #   top            the README opens with "# OcuTalon", a blank line and the owner's opening paragraph, then the teaser line and, after
-#                  it, exactly one image line (the hero), then the H2 sections "Try it in two minutes", "What's interesting", "What
-#                  you can use it for" and "How you talk to it" in this order; the other H2 sections are there; no "Contest task"
-#                  heading and no header row of its table
+#                  it, exactly one image line (the hero), then the H2 sections "Try it in two minutes", "What's interesting",
+#                  "Measured" (Story 11.25), "What you can use it for" and "How you talk to it" in this order; the other H2 sections
+#                  are there; no "Contest task" heading and no header row of its table
 #   try-it         the online demo link comes before ./install.sh, with "nothing to install, and no Early Access image needed"
 #                  beside it, the splash screen and its read-only Visual Trace account; the local path is four numbered steps;
 #                  steps 1 and 2 are pinned word for word (U-241 item 1, Story 11.23), and the section never links #start-it-with-build-109
 #   interesting    "What's interesting" has at most 120 words (its image lines are not counted) and names Interoperability, Visual
 #                  Trace, AI Hub, a dry run and the audit log; it shows at least one image line, and every image line in it is the
 #                  decision trace, docs/images/vt-decision.png (the owner's decision of 2026-11-05, reversing U-242 Q2's layout)
+#   measured       "Measured" has a table row for each of its eight row labels, each label word for word as the row's first cell
+#                  (Story 11.25); its numbers and other wording are not pinned
 #   use-cases      "What you can use it for" holds exactly the three items, word for word (the third links docs/bridge-guide.md)
 #   how-you-talk   "How you talk to it" holds its facts (the web chat page on every install, the demo-only parts, the Telegram row
 #                  for your own install with your own bot token, email in a later release, the link to "Demo mode"), a table and an
@@ -178,6 +180,7 @@ ARROW=$(printf '\342\206\222')
 H_TRY='Try it in two minutes'
 H_INT="What's interesting"
 INT_IMAGE=docs/images/vt-decision.png
+H_MEAS='Measured'
 H_USE='What you can use it for'
 H_TALK='How you talk to it'
 # The owner's text of Story 10.4 (epics.md), word for word: the opening paragraph, the two use cases, and the model paragraph
@@ -426,8 +429,8 @@ $OPENING"
   n=$(grep -cxF -- "$OPENING" "$f")
   if [ "$n" -gt 1 ]; then echo "$f: the opening paragraph is there $n times, not once"; fi
   h2s=$(headings "$f" | awk -F'\t' '$1 == 2 { print $3 }')
-  if [ "$(printf '%s\n' "$h2s" | head -n 4)" != "$(printf '%s\n%s\n%s\n%s' "$H_TRY" "$H_INT" "$H_USE" "$H_TALK")" ]; then
-    echo "$f: the first four H2 sections are not, in this order: $H_TRY, $H_INT, $H_USE, $H_TALK"
+  if [ "$(printf '%s\n' "$h2s" | head -n 5)" != "$(printf '%s\n%s\n%s\n%s\n%s' "$H_TRY" "$H_INT" "$H_MEAS" "$H_USE" "$H_TALK")" ]; then
+    echo "$f: the first five H2 sections are not, in this order: $H_TRY, $H_INT, $H_MEAS, $H_USE, $H_TALK"
   fi
   printf '%s\n' "$OTHER_H2" | while IFS= read -r t; do
     if ! printf '%s\n' "$h2s" | grep -qxF -- "$t"; then echo "$f: no H2 section '$t'"; fi
@@ -500,6 +503,31 @@ chk_interesting() {
   done
 }
 
+# measured (Story 11.25): the eight row labels of the Measured table, word for word; a heredoc, because two hold an apostrophe.
+IFS= read -r -d '' MEAS_LABELS <<'LABELS' || true
+Incidents diagnosed with the right cause and fix
+Routine attention decisions right
+The demo's incident, end to end with a live model
+Prompt-injection attempts that led to an action
+Changes made without a person's approval
+Cost of one attention decision
+Cost of diagnosing 50 failed orders
+The always-on online demo
+LABELS
+chk_measured() {
+  local sec="$tmp/sec.meas" label
+  section "$1" "$H_MEAS" > "$sec"
+  if [ ! -s "$sec" ]; then
+    echo "$1: no section '$H_MEAS'"
+    return
+  fi
+  printf '%s\n' "$MEAS_LABELS" | while IFS= read -r label; do
+    if [ -n "$label" ] && ! awk -v p="| $label |" 'index($0, p) == 1 { found = 1 } END { exit !found }' "$sec"; then
+      echo "measured: '$H_MEAS' has no table row '$label'"
+    fi
+  done
+}
+
 # use-cases
 chk_use_cases() {
   local sec="$tmp/sec.use" n
@@ -1259,7 +1287,11 @@ rule_top() {
   st 'a required section removed' 1 "$README" '!/^## Troubleshooting$/' chk_top
   st 'the Contest task section back' 1 "$README" '{ print } END { print ""; print "## Contest task"; print "" }' chk_top
   st 'the Contest task table header back' 1 "$README" '{ print } /^## What OcuTalon does$/ { print ""; print "| Contest task or criterion | x | y |" }' chk_top
-  finish top 'the title, the opening paragraph, the teaser and the hero image, then the four top sections in order, and the other sections are there' chk_top
+  st 'the Measured section removed' 1 "$README" '!/^## Measured$/' chk_top
+  st 'the Measured section above What'"'"'s interesting' 1 "$README" '/^## Measured$/ { print "## What'"'"'s interesting"; next } /^## What.s interesting$/ { print "## Measured"; next } { print }' chk_top
+  st 'the Measured section below What you can use it for' 1 "$README" '/^## Measured$/ { print "## What you can use it for"; next } /^## What you can use it for$/ { print "## Measured"; next } { print }' chk_top
+  st 'the Measured heading one level down' 1 "$README" '/^## Measured$/ { print "### Measured"; next } { print }' chk_top
+  finish top 'the title, the opening paragraph, the teaser and the hero image, then the five top sections in order, and the other sections are there' chk_top
 }
 
 rule_try_it() {
@@ -1301,6 +1333,16 @@ rule_interesting() {
   finish interesting 'at most 120 words, and it names the workflow, Visual Trace, the AI Hub agent, the dry run and the audit log' chk_interesting
 }
 
+rule_measured() {
+  rule_begin measured "$README" || return
+  st 'the heading removed' 1 "$README" '!/^## Measured$/' chk_measured
+  st 'the heading renamed' 1 "$README" '/^## Measured$/ { print "## Measurements"; next } { print }' chk_measured
+  st_facts chk_measured "$MEAS_LABELS"
+  st_move 'a row moved out of the section' "$H_MEAS" '| Routine attention decisions right |' chk_measured
+  st 'a row label not in the first cell' 1 "$README" '{ sub(/^\| Cost of one attention decision \| /, "| Cost | Cost of one attention decision | ") } { print }' chk_measured
+  finish measured 'Measured has a table row for each of its eight row labels, word for word' chk_measured
+}
+
 rule_use_cases() {
   rule_begin use-cases "$README" || return
   st 'item 1 changed' 1 "$README" '/^- \*\*The partner feed/ { sub(/2am/, "3am") } { print }' chk_use_cases
@@ -1870,7 +1912,7 @@ rule_docs() {
   finish docs 'the build 109 sentences of the bridge guide and the IPM page and the two ruled lines of the security overview are there, word for word' chk_docs
 }
 
-RULES='top try_it interesting use_cases how_you_talk teaser images once outcomes install install_pointer commands key_account lan sign_in_address demo_mode admin_commands after_start_log dev_only public_text telegram_section telegram_strings telegram_facts telegram_demo no_telegram product_links readme_links must_scan ipm licence docs'
+RULES='top try_it interesting measured use_cases how_you_talk teaser images once outcomes install install_pointer commands key_account lan sign_in_address demo_mode admin_commands after_start_log dev_only public_text telegram_section telegram_strings telegram_facts telegram_demo no_telegram product_links readme_links must_scan ipm licence docs'
 
 # unlisted <rule names>: each rule_* function of this script but rule_begin that the list does not name, one per line.
 unlisted() {
```

## Verification

All commands run from the worktree root after `git rev-parse --show-toplevel` matches it, each in its own foreground call with `timeout: 600000`. No container, IRIS, network or `ci/iris.sh` call; no lane variables needed. Measured durations: `test-readme.sh` about 45 s, `test-release-notes.sh` about 66 s, `test-bridge-guide.sh` 33 s, `test-boundaries.sh` 13 s, `test-cpf.sh` 4 s.

**Commands:**
- (once) `sed -n 9,27p ../../../collateral/readme-11-25-measured.md > "$TMPDIR/e11s25-ruled.md" && shasum -a 256 "$TMPDIR/e11s25-ruled.md"` -- expected: `bcabdc9cb70c3e915ba78627e3d1f21dab11e425741f327e038ee9dd19a44b68` (else HALT `intent gap`: the ruled text moved). This file is the `<ruled-lines file>` below.
- (loop) `awk '/^## Measured$/{on=1} /^## What you can use it for$/{on=0} on' README.md | sed '$d' | shasum -a 256` -- expected: the same sha256 (AC1).
- (loop) `git show <baseline_revision>:README.md | awk -v f=<ruled-lines file> 'NR==25 { print; while ((getline l < f) > 0) print l; print ""; next } { print }' | cmp - README.md` -- expected: no output, exit 0; and `shasum -a 256 README.md` gives `8923a64fcdbccb0413587c03438fc3659089a77fb7b772c49c7fad34efd1745d` (AC1, AC2).
- (loop) `bash docker/tests/test-readme.sh` -- expected: `PASS top`, `PASS measured`, `test-readme: all rules passed` (AC3).
- (once) `/bin/bash docker/tests/test-readme.sh` -- expected: `test-readme: all rules passed` (bash 3.2, the script's stated floor).
- (once) `bash docker/tests/test-release-notes.sh`; then, each its own call, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-cpf.sh`, `bash docker/tests/test-bridge-guide.sh` -- expected: all PASS / exit 0; `test-boundaries.sh` with no README.md hit (only the two lead-owned hits of Design Notes may remain, if the lead has not fixed them yet) (AC4).
- (once) `git diff --name-only <baseline_revision> -- . ':(exclude)_bmad-output'` -- expected: exactly `README.md` and `docker/tests/test-readme.sh`; `git diff -U0 <baseline_revision> -- docker/tests/test-readme.sh | grep '^@@'` -- expected: the eight hunks of the diff, none in Epic 34's regions (AC2, AC3).
- (once) `grep -nE '9 of 10|19 of 22|30 of 30|0\.0001|0\.000[57]|cents a day' README.md docs/*.md` -- expected: hits only inside README lines 26-44 (no conflicting statement).

**Rule 19.**
- Shared surfaces: README.md's H2 list and order (asserted by `test-readme.sh` `top`, `readme-links`, `product-links`, and read by `test-release-notes.sh` `static`, `test-boundaries.sh` and `release/checklist.sh`); `test-readme.sh`'s `RULES` list (its `rules` and `no-readme` checks). Every test added or changed passes on a fresh environment, in either order (`test-readme.sh` is hermetic, reads only tracked files and runs its rules from `RULES`; a clean checkout is the fresh environment).
- Mutations to demonstrate (observe red, restore byte-identical, write each as a `mutation:` line here): AC1 the `## Measured` and `## What you can use it for` headings swapped in README.md -> `FAIL top`; AC2 one byte appended to README line 3 -> the `cmp` check reports a difference; AC3 a row label renamed in README.md ("Routine attention decisions right" -> "Routine decisions right") -> `FAIL measured`, and the label loop removed from `chk_measured` -> `FAIL measured: a broken copy was not flagged`, and `chk_top` reverted to its four-section list -> `FAIL top`; AC3 negative: `19 of 22` -> `18 of 22` in README.md -> all rules still pass; AC4 a dotted class name (`Ens.Director`) added to a Measured bullet -> `FAIL dev-only` in `test-readme.sh` and `FAIL static` in `test-release-notes.sh`.

**Results (implement stage, 2026-11-05).**
- Ruled-lines sha256 `bcabdc9c...a44b68` (once); fenced block under Design Notes identical to it; pins diff `git apply --check` clean, result sha256 `1ecc422d...f7936`.
- Section sha256 `bcabdc9c...a44b68`; whole-file rebuild `cmp` clean; README.md sha256 `8923a64f...d1745d`.
- `bash docker/tests/test-readme.sh`: `PASS top`, `PASS measured`, `test-readme: all rules passed`; `/bin/bash` (3.2): all rules passed.
- `test-release-notes.sh` 16 PASS (static included), `test-boundaries.sh` all rules passed (no README hit; the two lead-owned hits are gone), `test-cpf.sh` and `test-bridge-guide.sh` all passed.
- `git diff --name-only` outside `_bmad-output`: `README.md`, `docker/tests/test-readme.sh`; eight hunks in `test-readme.sh`, none in Epic 34's regions; the table's numbers appear only in README lines 32-39.

mutation: AC1 -- swapped the `## Measured` and `## What you can use it for` headings in README.md -> red (`FAIL top`, `FAIL measured`, `FAIL use-cases`); restored byte-identical.
mutation: AC2 -- appended one byte to README line 3 -> the `cmp` rebuild check reports a difference (exit 1); restored byte-identical.
mutation: AC3 -- renamed "Routine attention decisions right" to "Routine decisions right" -> `FAIL measured`; removed the label loop from `chk_measured` -> `FAIL measured: a broken copy was not flagged`; reverted `chk_top` to its four-section list -> `FAIL top`; negative: `19 of 22` -> `18 of 22` -> all rules still pass; each restored byte-identical.
mutation: AC4 -- added `(Ens.Director)` to the first Measured bullet -> `FAIL dev-only` in `test-readme.sh` and `FAIL static` in `test-release-notes.sh`; restored byte-identical.

**QA stage (2026-11-05).** Audit: every AC has a pinning check that can fail. AC1 `top` + `measured` (and the section sha256); AC2 the `cmp` rebuild check and the `git diff --name-only` list (spec Verification commands; not pinned in `test-readme.sh`, by the spec's smallest-diff intent); AC3 `top` (four position self-tests) and `measured` (heading removed/renamed, each label removed, a row moved out, a label not in the first cell); AC4 `test-release-notes.sh` `static`. One gap found: AC3's "does not fail when a number or other wording changes" had no self-test in the script (only the manual mutation). Added one to `rule_measured` (existing "is flagged" style).

mutation (QA, AC1): swapped the `## Measured` and `## What you can use it for` headings in README.md -> `FAIL top`, `FAIL measured`, `FAIL use-cases`; restored byte-identical.
mutation (QA, AC2): appended one space to README line 3 -> the `cmp` rebuild check reports `differ: char 511, line 3` (exit 1); restored byte-identical.
mutation (QA, AC3): renamed the row "Routine attention decisions right" to "Routine decisions right" in README.md -> `FAIL measured`; restored byte-identical.
mutation (QA, AC3, new self-test): made `chk_measured` also require "19 of 22" (pinning a number) -> `FAIL measured: a broken copy was not flagged` (self-test "a changed number, result or intro line is flagged"); restored byte-identical.
mutation (QA, AC4): added `(Ens.Director)` to the first Measured bullet -> `FAIL static` in `test-release-notes.sh`; restored byte-identical.

Test files changed (QA): `docker/tests/test-readme.sh` (one negative self-test in `rule_measured`; 3 lines). Final runs: `bash` and `/bin/bash` 3.2 both `test-readme: all rules passed`, `PASS top`, `PASS measured`.

**Code review (2026-11-06).** Two patches in `rule_measured`: a self-test "a row label extended in its cell", and the negative self-test's awk program now exits 1 unless all three of its edits apply. `docker/tests/test-readme.sh` sha256 after review `4b9f34c75d6199479824f80486c198c95e84cd74a0dc2533839dec584979fdb5` (seven hunks against the baseline); README.md unchanged, `8923a64f...d1745d`. `bash` and `/bin/bash` 3.2: `PASS top`, `PASS measured`, `test-readme: all rules passed`; `test-boundaries.sh` all rules passed.

mutation (review, AC3, new self-test): weakened `chk_measured`'s pattern from `"| $label |"` to `"| $label"` -> `FAIL measured: a broken copy was not flagged` (self-test "a row label extended in its cell: not flagged"); restored byte-identical.
mutation (review, AC3, negative self-test guard): made one of its edits not apply (`19 of 22` -> `19 of 23` in the awk pattern) -> `FAIL measured: a broken copy was not flagged` (self-test "an edit of the numbers or the intro did not apply"); restored byte-identical.
mutation (review, AC4): added a home-folder path (the macOS users folder, a user name and `demo`, in parentheses) to the first Measured bullet in README.md -> `FAIL paths` in `test-boundaries.sh` (`README.md:43`); restored byte-identical.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The ruled `## Measured` section (19 lines, sha256 `bcabdc9c...a44b68`) is inserted into README.md between "What's interesting" and "What you can use it for", and `docker/tests/test-readme.sh` pins its heading, its eight row labels and its position.

**Files changed.**
- `README.md` -- the 19 ruled lines plus one blank line after line 25 (one hunk of 20 added lines; sha256 `8923a64f...d1745d`).
- `docker/tests/test-readme.sh` -- `chk_top` widened to five H2 sections with four self-tests, new `chk_measured`/`rule_measured`, `measured` in `RULES` (sha256 `1ecc422d...f7936`).
- This spec -- Verification results, mutation lines, triage log.

**Review.** Patches applied: 0. Deferred: 0. Rejected: 9, all low, each with its reason in the Review Triage Log (ruled wording, Boundaries "Never" pins, or theoretical hardening). Follow-up review recommended: false (no patched entry).

**Verification.** See Results and the four `mutation:` lines under Verification: test-readme.sh passes under bash and /bin/bash 3.2; test-release-notes.sh, test-boundaries.sh, test-cpf.sh and test-bridge-guide.sh pass; rebuild `cmp` clean; only README.md and test-readme.sh change outside `_bmad-output`. The lead re-ran test-readme.sh after the review (all rules passed).

**Residual risks.** None known. Pre-existing `printf: write error: Broken pipe` lines appear in test-readme.sh output and do not affect the result.
