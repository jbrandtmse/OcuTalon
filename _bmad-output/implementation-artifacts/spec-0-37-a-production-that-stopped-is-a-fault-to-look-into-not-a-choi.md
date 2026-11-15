---
title: 'A production that stopped is a fault to look into, not a choice to report'
type: 'bugfix'
created: '2026-11-15'
status: 'done'
baseline_revision: 'cd2c143e47bcd4f5e60292d4a39f144d2068fd66'
baseline_commit: 'b7340cbee558af05420d4d1a8bde2741c9921eb4'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-0-35-routine-attention-decisions-meet-their-target.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 0.35 gave Triage's tellnow bullet the sentence "a report that a part of the user's production was switched off or disabled: that is a change someone chose to make, not a fault". In the Contest Planner's A/B (2026-11-13, SHIP RULE PASS) this fixed the two disabled findings (5/5 on NEW against 1/18 on OLD). It also pulled the two stopped-production findings, which expect `act`, to `tellnow` in 3 of 5 NEW attempts (4 misses in 10, against 0 of 18 on OLD). The cause is the wording: "switched off" also describes a production that stopped, and the sentence calls it a choice (DW-1273). The result is not unsafe, because Tell now still tells the person at once. But a fault gets a notice instead of a check.

**Approach:** Change only Triage's tellnow and act bullets (lines 26-27). Separate the two cases by MEANING. Disabling one part is a setting that someone changes on purpose, so it is a choice and gets Tell now. A whole production that stopped running is not a setting on one part, so it is a fault that a check can explain and gets Act. Drop the words "switched off", which caused the conflation. Keep 0.35's honest fix true, and keep both of its pinned phrases. Pin the new sentences in `TestTriage`, add one pin that the conflating words are gone, and keep the `main-set-texts`, `held-out-texts` and `held-out-names` guards passing, unchanged. The real-model score can't be measured in this lane: there is no key, the lane is local-only, and a push freeze is in force. Whether 0.37 needs the Planner's key-holder A/B before it merges goes to the gate as a choice (Design Notes, "The A/B ship question").

## Boundaries & Constraints

**Always:** Change only lines 26 and 27 of `Agent/Triage.cls` in product code, to the Planner-approved text, word for word (Public text). Keep Triage's MODEL, EFFORT, empty TOOLSETS and MOCKKEY. Send no sampling parameters. Put no `{{` in INSTRUCTIONS. Keep every other INSTRUCTIONS line byte-identical and in its order: the opening, the ignore and digest bullets, the JSON block, the data paragraph, the user's-own-message paragraph, the heartbeat paragraph, the precedents paragraph, the approve paragraph, and the persona paragraph last. Keep both 0.35 pins ("a change someone chose to make, not a fault" and "a fault that is happening now") and all other `TestTriage` pins. Pins move with their text and are never deleted or weakened. A failing guard prints the file and the rule, never the text.

**Never:**
- Copy or paraphrase any main-set or held-out case (names, wording, numbers or scenario) in an instruction.
- Change an eval case or its expectation (including mail-partner-notice, DW-1229), a mock scenario, `docker/tests/test-eval-set.sh`, another agent, a code path, the README, GUIDE, the catalog or any user-visible string.
- Run the real model, hold a key or read `.env`.
- Push or commit from a runner stage while the push freeze holds.
- Write release-evidence's absolute path, or any absolute local path, into a tracked file.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| A part is disabled | an item reports that one part of a production was disabled, with no other fault | `tellnow` (0.35's honest fix, kept): a choice someone made, which only the user can undo | none; the real-model rate is the A/B's (Design Notes) |
| A whole production stopped | an item reports only that a production stopped, with no cause | `act`: a fault that a read-only check can explain | none; real-model rate as above |
| A stop announced for later | an item warns that something will stop unless the user acts before a time | unchanged (`tellnow` when the user must act soon): the new act sentence is about a production that has already stopped | (inference) a risk of pulling toward `act`, measured by ship-rule bars (a) and (b) |
| A partner reports missing traffic | an email reports that expected messages stopped arriving and asks for a look | unchanged (`act`: a fault happening now) | none |
| Pin: a new phrase is lost | Triage INSTRUCTIONS without one of the three new pinned phrases | `TestTriage` FAILs, naming the phrase | none |
| Pin: the conflating words return | Triage INSTRUCTIONS contain "switched off" | `TestTriage` FAILs ("no longer says 'switched off'") | none |
| Guard: case text in a prompt | Triage INSTRUCTIONS gain 5 consecutive words or a distinctive token of a main-set or held-out item | `FAIL main-set-texts` or `FAIL held-out-texts`, naming `src/ocutalon/cls/OcuTalon/Agent/Triage.cls`, never the text | none |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Agent/Triage.cls`: XData INSTRUCTIONS (lines 20-46). Line 26 (`"tellnow"`) and line 27 (`"act"`) are the only lines this story changes. 0.35 set both.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls`:
  - Class doc comment, lines 2-4: the `TestTriage` entry.
  - The `TestTriage` method comment, line 43.
  - The 0.35 phrase loop, lines 69-71. The new pins go here.
- Read-only pins of the other INSTRUCTIONS paragraphs, which must stay green:
  - `Test/Agent/TriageUserTurn.cls` (the user's-own-message paragraph);
  - `Test/Agent/PersonaBlock.cls` `TestParagraphs` (the approve paragraph, then the persona paragraph last);
  - `Test/Agent/RenderMemory.cls` `TestTriageParagraph` (heartbeat, then precedents, then approve);
  - `docker/tests/test-triage-heartbeat.sh` (the heartbeat line, whole);
  - `Instructions.TestNoTemplates` (no `{{`).
- `docker/tests/test-eval-set.sh`, read-only:
  - Program `check-held-out-names.mjs`, lines 890-1031. It has three modes: none (`held-out-names`), `main` (`main-set-texts`) and `held` (`held-out-texts`).
  - Self-test variants at lines 2503-2610.
  - Rules registered at lines 4385-4387.
  - The whole script takes about 210 s.
- `eval/finding-orders-stopped`, `eval/finding-results-stopped` (expect `act`), `eval/finding-orders-item-disabled` and `eval/finding-results-item-disabled` (expect `tellnow`), and the held-out `eval/held-out/mail-confirmations-stopped` (expects `act`): read only, to understand the failure. Nothing in the new text comes from them.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls`, read-only: `watch.productionStopped` and `watch.itemDisabled` write the two finding texts. The new text uses none of their wording.

## Tasks & Acceptance

**Execution:**
- Task 0 (implement, first; each item is unmeasured here, (inference)):
  - Confirm that `git rev-parse HEAD` still contains the baseline, and that Triage.cls lines 26-27 are byte-for-byte 0.35's text (Design Notes "Old lines"). If another story has touched them since, STOP and report it.
  - Confirm that a lane-C IRIS slot is free (lock `locks/lane-c`, port 52803) for the warm-stack class runs. In a release quiet window, take the lane's warm or throwaway lock only after teardown. With no slot, the IRIS classes run in CI on the pushed head after the freeze, and the stage records that.
  - Re-measure on the real tree what this plan measured on a scratch copy: the guards pass, the new text shares no run of 3 or more words with any item text (only a 2-word run, "that the" or "production has"), and the INSTRUCTIONS block has no `{{`.
- `src/ocutalon/cls/OcuTalon/Agent/Triage.cls`: replace lines 26 and 27 with the "New lines" in Design Notes, word for word. Nothing else in the file changes.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls`, `TestTriage`:
  - Keep the 0.35 loop as it is.
  - Add a second loop that asserts the three new phrases: "a setting that someone changes on purpose", "It never includes a whole production that stopped running" and "A whole production that stopped running is such a fault". Message: "the instructions say '<phrase>' (Story 0.37: a disabled part is a choice, a stopped production is a fault)".
  - Add one assertion `'(text [ "switched off")`, with the message "the instructions no longer say 'switched off', which pulled a stopped production in with the disabled parts (Story 0.37, DW-1273)".
  - Extend the method comment on line 43 and the class entry on lines 2-4 by one clause each, saying what is pinned.

**Acceptance Criteria:**
- AC1: Given this story's diff, when it is inspected, then only lines 26-27 of Triage's INSTRUCTIONS change in product code. `git diff --numstat b7340cbee -- src ':(exclude)src/**/Test/**'` prints only `2	2	src/ocutalon/cls/OcuTalon/Agent/Triage.cls`, and `git diff -U0 b7340cbee -- src/ocutalon/cls/OcuTalon/Agent/Triage.cls | grep '^@@'` prints only `@@ -26,2 +26,2 @@`.
  - mutation: append one character to Triage line 30. The check prints `3	3` and a second hunk. Revert byte-identical (cmp).
- AC2: Given the changed instructions, when `OcuTalon.Test.Agent.Instructions` runs, then `TestTriage` passes. It asserts the two 0.35 phrases, the three new phrases, and that "switched off" is absent.
  - mutation: restore line 26 to 0.35's text. `TestTriage` goes red on "a setting that someone changes on purpose", on "It never includes a whole production that stopped running" and on the absence of "switched off". Revert.
  - mutation: restore line 27 to 0.35's text. `TestTriage` goes red on "A whole production that stopped running is such a fault". Revert, byte-identical (cmp).
- AC3: Given the real tree with the new text, when `EVAL_SET_ONLY="held-out-names main-set-texts held-out-texts" bash docker/tests/test-eval-set.sh` runs, then all three print PASS. Given a Triage INSTRUCTIONS block that also holds an item sentence, then the matching rule FAILs, naming the file and never the text.
  - mutation (main-set-texts): append the first sentence of a stopped finding's item text to Triage's INSTRUCTIONS. The run prints `src/ocutalon/cls/OcuTalon/Agent/Triage.cls: names a main-set item text in a prompt (main-set-texts)` and `FAIL main-set-texts`. Revert (cmp).
  - mutation (held-out-texts): append the first sentence of a held-out item text. The run prints `FAIL held-out-texts`. Revert (cmp).
  - mutation (held-out-names): append a held-out case's whole item text as a comment line outside XData in Triage.cls. The run prints `FAIL held-out-names`. Revert (cmp).
- AC4: Given the changed instructions, when the other INSTRUCTIONS pins run, then they all pass: `TriageUserTurn`, `PersonaBlock`, `RenderMemory`, `TestNoTemplates` and `bash docker/tests/test-triage-heartbeat.sh`.
  - mutation: none of these is changed by the story, so no new mutant applies. Each one's own self-test or mutant is on record from 0.35 and 39.4.
- AC5: Given the diff, when it is inspected, then no README, GUIDE, catalog, mock, eval or `docker/` file changes. `git diff --name-only b7340cbee | grep -iE 'README|GUIDE|Catalog|^ci/mock/|^eval/|^docker/'` prints nothing.
  - mutation: append a line to README.md. The check prints `README.md`. Revert (cmp).
- AC6 (the A/B; its form depends on the gate's ruling, Design Notes "The A/B ship question"). Given the pushed story head, when the Planner's key-holder runs the A/B, then the outcome depends on the ruling:
  - Option A: the story merges ONLY if ship rule (a)-(e) holds, and bars (f) and (g) hold.
  - Option B: the A/B runs after the merge, and a miss reverts the story.
  - (a)-(e) are 0.35's rule. OLD = feature at the push (0.35's instructions); NEW = this story.
  - (f) the two stopped findings are right in at least 2N-1 of the 2N NEW decisions, where N is the number of NEW attempts and N >= 3.
  - (g) the two disabled findings are right in at least 2N-1 of 2N NEW decisions.
  - A fallback counts as a miss.
  - (f) and (g) are this plan's proposal to quantify the epics AC's "the stopped findings are right again while the disabled findings stay right", for the Planner to set.
  - This is the Planner's measurement. The implement, QA and review stages run no model and hold no key.
- AC7: Given CI on this story's head, when it finishes, then every workflow is green. It is checked after the freeze lifts.

### Review Findings

Code review, 2026-11-15, lane C, base `cd2c143e4`, HEAD `4053a0aea` (the review prompt named `92ba23a34`, which does not exist; `4053a0aea` adds only the cycle log on top of QA's `929cfd407`, so the reviewed content is the same). Four layers (blind, edge-case, verification-gap, acceptance-auditor): 0 decision-needed, 7 patch (all applied), 0 defer, 11 rejected. No HIGH, no MED, no AD mismatch. Triage.cls lines 26-27 are byte-identical to the approved "New lines" and were not patched.

- [x] [Review][Patch] The "switched off" absence pin was case-sensitive, so "Switched off" at a sentence start passed [src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls:76]. Now `$ZConvert(text, "L")`. low, fix-risk low, in-story, spec-clear.
- [x] [Review][Patch] TestTriageOutcomes said the bullets are "under 'The four outcomes are:'" but only checked that the heading exists [Instructions.cls:97-113]. The first bullet is now pinned to the line under the heading and its blank line, and each later bullet to the next line. low, fix-risk low, in-story, spec-clear.
- [x] [Review][Patch] "Neither bullet holds the other's" was not checked for the exclusion sentence in act [Instructions.cls:126-128]. Added to the act-negative loop. low, fix-risk low, in-story.
- [x] [Review][Patch] The tellnow bullet was not checked free of the act bullet's "a fault that is happening now" [Instructions.cls:123-125]. Added as a tellnow-negative loop, which also holds the earlier stopped-sentence check. low, fix-risk low, in-story.
- [x] [Review][Patch] The one-bullet count and the act-negative checks had no observed red (Rule 19) [Instructions.cls:108,126-128]. Mutants recorded in Verification. low.
- [x] [Review][Patch] The AC4 `mutation:` provenance named Stories 0.35 and 39.4, which hold none of those mutants [spec Verification]. Corrected to the specs that do. low.
- [x] [Review][Patch] This section read "(none yet)" after a review pass. Written now.

**Rejected** (no patch; every item that would reword INSTRUCTIONS is out of scope under gate ruling (a)):
- low, for the Planner: a heartbeat snapshot that shows a whole production stopped. The heartbeat paragraph offers ignore, digest and tellnow, and the new act sentence may pull such a beat to act. No main-set or held-out case pairs a heartbeat with a stopped production, so the A/B's bar (h) cannot see it. Rewording the text is the Planner's call.
- low, for the Planner: a user's own chat message that says a production stopped. The always-tellnow paragraph and the act sentence could compete. Act's general definition already covered this case before 0.37. No user-turn case mentions a stopped production. Rewording is the Planner's call.
- low, by-design (ruling (a)): a part that is "stopped" or "switched off" rather than "disabled" is named in neither bullet, and the old explicit tellnow placement of a part "switched off" is gone. This is the approved text. Act's general definition covers it, and no case or AC is about it.
- false: a missing bullet resets the order baseline. The one-bullet count fails red on the same run, and with the contiguity check any later bullet fails too, so no regression passes.
- low: the Auto Run Result predates QA (Files changed omits TestTriageOutcomes, and the fresh-stack run predates it). The Auto Run Result covers the implement pass only (Rule 14), and its fix is a spec edit. For the lead: the Rule 19 pre-push fresh check (`shard lane-a@Agent`, forward and `--reverse`) now includes TestTriageOutcomes and this review's patches.
- low: the earlier triage log rejected the placement finding because "AC1 holds the placement". TestTriageOutcomes now pins placement (QA, plus the patch above). The log is a record and is not rewritten.
- low: the earlier log said the checks against `b7340cbee` "would list unrelated feature changes", and `baseline_commit` differs from `baseline_revision`. Verified in review: AC1 prints only `2	2	.../Triage.cls` against both bases, and AC5 prints nothing against both. This is a frontmatter or record edit only, and frontmatter is not changed in review.
- low: frontmatter `status: done` and "Blocking condition: none" against the held merge. The Auto Run Result Note and "Spec gate rulings" (e) both state held_merge until the Planner's PASS, and review never changes frontmatter status.
- low: QA's new method lies beyond the planned "TestTriage" scope, and the Spec Change Log has no QA line. It is within the ruled file footprint (ruling (b)), and this is a spec record only.
- low: the run tags in the results (`e037iw`, `e037if`, `e037qw`) differ from the commands' `e0s37iw`, `e0s37if`. They are lane-local throwaway labels, and no evidence is lost.
- by-design (ruling (e)): AC6 and AC7 have no lane test or mutant. AC6 is the Planner's key-holder A/B, a merge condition with bars (a)-(h) and N = 3, and AC7 is CI after the freeze. DW-1273 stays with the lead until the A/B. No real-model result is claimed anywhere in this spec.

## Design Notes

**Source:** Contest Planner, 2026-11-13 ~14:45Z (prompts/release-035-20261113.md, owner's delegation): "separate the two by MEANING, never by copying case text. A DISABLED ITEM is a choice; a PRODUCTION THAT STOPPED is a fault, so Act. ... the same A/B ship rule (a)-(e) applies before it merges." DW-1273 is routed to this story. The epics block (Story 0.37) limits the footprint to "the attention agent's instructions only (as Story 0.35), and their pins".

**Governing ADs:**
- AD-7: static INSTRUCTIONS, no `{{`, Haiku 5.5, effort low, no sampling parameters, and the system prompt stays first and cached.
- AD-8: the bridge alone decides that a reply is unusable.
- AD-22: the evaluation set and its guards, and mock routing by `MOCKKEY`, so rewording does not change mock answers or any CI scenario.
- AD-28: only code says all-clear.

No AC contradicts an AD, and no AD changes.

**Integration (Rule 1/2):** this story introduces no service. It consumes 0.35's guards and 9.5's RC harness, through the Planner's A/B.

**Ledger inbox:** DW-1273 (routed to this story). Closing it needs the A/B evidence under Option A, or the post-merge check under Option B.

**Dependencies:** `_bmad/custom/epic-dependencies.yaml` has no Epic 0 entry and no `story_waits` for 0.37. Nothing waits on 0.37, and 0.37 waits on nothing but the freeze and the gate.

### Diagnosis (from 0.35's A/B record, read-only)

- The two disabled findings ("<part> in the <production> production was disabled at <time>") and the two stopped findings ("The <production> production stopped at <time>") have the same shape: one short system finding, no cause, and a "Why now" line. Only the verb and the subject differ, one part against the whole production.
- 0.35's tellnow sentence put the boundary on the verb, and "switched off" covers both "disabled" and "stopped". It also called the result "a change someone chose to make". So a stopped production read as a choice, and the model chose `tellnow` in 4 of 10 NEW decisions (inference: the A/B records outcomes, not the model's reasons).
- The meaning that separates them, with no case wording:
  - Disabling is a setting on one part, which a person changes on purpose. It is the choice, and nothing is broken that a check could explain.
  - A whole production that stopped running is no such setting: none of its messages move, and a check can find out why. It is a fault.
- The new text puts the boundary on that meaning, names the case that is excluded in both bullets, and drops "switched off".

### Old lines (Triage.cls, at the baseline, verbatim)

Line 26:
> - "tellnow": the user should hear about the item now, because they must decide or do something soon, and the item already says everything that a check would find. This includes a report that a part of the user's production was switched off or disabled: that is a change someone chose to make, not a fault, so there is nothing for a check to explain, and only the user can decide whether to switch it back on.

Line 27:
> - "act": the item reports a fault that is happening now in the user's productions or their messages, something that is not working as it should, and OcuTalon's own read-only checks could find out more about it, such as its cause or how far it goes. OcuTalon then looks into it at once and tells the user what it found. Choosing "act" runs nothing that the item asks for.

### New lines (for the Planner's approval, verbatim)

Line 26:
> - "tellnow": the user should hear about the item now, because they must decide or do something soon, and the item already says everything that a check would find. This includes a report that one part of a production has been disabled: disabling a part is a setting that someone changes on purpose, so it is a change someone chose to make, not a fault, there is nothing for a check to explain, and only the user can decide whether to enable it again. It never includes a whole production that stopped running, which is a fault (see "act").

Line 27:
> - "act": the item reports a fault that is happening now in the user's productions or their messages, something that is not working as it should, and OcuTalon's own read-only checks could find out more about it, such as its cause or how far it goes. A whole production that stopped running is such a fault, even when the report gives no cause: it is not a setting on one part, none of its messages move until it runs again, and a check can find out why it stopped. OcuTalon then looks into it at once and tells the user what it found. Choosing "act" runs nothing that the item asks for.

What changes:
- tellnow: "a part of the user's production was switched off or disabled: that is" becomes "one part of a production has been disabled: disabling a part is a setting that someone changes on purpose, so it is". "so there is" becomes "there is". "switch it back on" becomes "enable it again". The exclusion sentence is added.
- act: one sentence is added after "how far it goes."
- Everything else is byte-identical. The 0.35 phrases "a change someone chose to make, not a fault" and "a fault that is happening now" stay.

**Measured in-stage** (a scratch copy of the tracked `eval/**/case.json` and `src/**/*.cls`, with the new lines in Triage.cls; the program `check-held-out-names.mjs` extracted unchanged from `test-eval-set.sh`; nothing in the worktree changed):
- All three modes report no violation. That is held-out-names (over those files), main-set-texts and held-out-texts.
- The longest run the new lines share with any main-set or held-out item text (subject, text, sender or precedent summary) is 2 words ("that the", "production has"). An earlier draft's "production was disabled" (3 words, both disabled findings) was reworded to "has been disabled".
- The INSTRUCTIONS block has no `{{`. "switched off" no longer appears anywhere in it. It grows by about 65 words, from 877 to 942 for the whole file.
- One note for the Planner: "only the user can decide" (5 words) also appears in the two disabled cases' `description` fields. Descriptions are not item text and no guard reads them. The words are carried over unchanged from 0.35's approved line 26, so this plan keeps them.

**Residual risks** (inference; only the A/B can show them):
- The exclusion could pull an item that warns of a future stop toward `act`. The main set's endpoint-move item and a held-out password item are of this kind, so bars (a) and (b) measure the risk.
- The disabled findings could slip back to `act`, which bar (g) measures.
- The invalid-reply fallbacks, about 5% (DW-483), stay out of scope. They count as misses under (f) and (g).

### The A/B ship question (a CHOICE for the gate)

The question is whether 0.37 needs the Planner's key-holder A/B, under ship rule (a)-(e), before it merges, as 0.35 did. The epics AC says it does, and the Planner asked for the question to come to the gate as a choice.

The evidence from 0.35 (release-evidence/ab-035/RESULT.md):
- SHIP RULE PASS. Routine OLD 20/20/19 against NEW 20/23/23. Held-out 34 against 35. SM-2 11/11. 0 actions. Demo gate 50 of 50 on NEW.
- 0.35's structural pins and all three guards were green on a text that still regressed. The stopped findings went to `tellnow` in 3 of 5 NEW attempts (4 misses in 10, against 0 of 18 on OLD), and only the A/B saw it.
- Spend $0.405 for 14 attempts (OLD 9, NEW 5), so about 2.9 cents per attempt. That is within 0.35's plan estimate of 2.4-3.3 cents per attempt.

**Option A: keep the A/B as a merge condition, as in 0.35.**
- Who: the Contest Planner's own key-holder subagent, in its own clone, never a runner.
- When: after the push freeze lifts. The lead pushes the story head once, and the A/B runs on that sha. OLD = feature at that time (0.35's text); NEW = the head. Bars (a)-(e) plus (f) and (g).
- Cost: about $0.15-0.20 for 3 + 3 attempts with their held-out runs and demo gates, and up to about $0.40 if attempts are rerun as in 0.35 (inference from $0.405 for 14 attempts). That is well inside the harness's caps (REL-5 at most 3 attempts per run, NFR-4).
- What blocks meanwhile: only 0.37's own merge. It waits LOCAL READY (held_merge) on `OCT-epic0-s037`. Feature keeps 0.35's measured text, which is SHIP RULE PASS and not unsafe. No story waits on 0.37. A later edit of Triage lines 26-27 by another story would conflict, but none is planned: Epics 39-41 append whole paragraphs, and those are shared by entry.
- Pros:
  - It is the only check that can verify the AC's real claim, "the stopped findings are right again while the disabled findings stay right".
  - It catches the kind of side effect that 0.35 itself had.
  - Old and new are compared under the same provider conditions.
  - The README's Measured row cannot get worse from an unmeasured text.
  - The cost is cents.
- Cons:
  - It needs the Planner's key-holder time, after the freeze.
  - If the freeze outlasts the last release, 0.37 never ships. The product then keeps a known, safe regression of 2 of 24 routine items in some attempts.
- Recommendation: **choose A.** Waiting costs nothing in safety, and it is the only way to know the fix works.

**Option B: merge on the structural pins and CI alone, with the A/B after the merge or folded into the next release's eval run.**
- How: merge once CI is green on the pushed head. The model check is then either the Planner's A/B on feature after the merge, or the next `eval/run.sh --release-candidate` run. That run has no OLD side, so its NEW numbers are read against 0.35's NEW record, 20/23/23 and held-out 35.
- Risk accepted: another regression could ship, on the stopped, disabled, future-stop or any other routine item, with only lexical pins to stop it. 0.35 is the precedent: pins and guards were green, and the model still regressed.
  - The README's Measured row and the demo-gate decisions would then carry the unmeasured text from the merge until the check runs.
  - If no RC run follows the merge before judging, the regression is never caught.
- How it would be caught: the RC run's `set-k.json` rows for the four named findings, plus the routine and held-out totals, against bars (a)-(g). The comparison side is 0.35's NEW record.
- How it is rolled back: `git revert` of the single 0.37 code commit on feature, before the release tag and before the README fill. It is two instruction lines plus pins, with no stored data and no upgrade step, so the revert is clean. CI must be green on the revert, and the numbers go to the Planner.
- Change to the epics AC: replace the second AC of Story 0.37 with:

  > [AMENDED 2026-11-15, Contest Planner gate ruling, Option B] **Given** the merged change, **When** the next release-candidate run or the Contest Planner's key-holder A/B, whichever comes first, measures it on the real model, **Then** the same ship rule (a)-(e) as Story 0.35 holds, and the stopped findings are right again while the disabled findings stay right **And** if any of these misses, the story's commit is reverted on feature before the release is tagged, and the numbers go to the Contest Planner.

  This is not a structurally exempt edit, so `epics_md_hash` is re-recorded only with the Planner's approval under the owner's delegation. This spec's AC6 is amended to match.
- Pros: 0.37 can merge as soon as CI is green after the freeze, with no key-holder slot needed first. If an RC run follows anyway, the check costs nothing extra.
- Cons:
  - It merges an unverified behaviour claim.
  - It has no OLD side under the same conditions.
  - It relies on an RC run happening, and on someone reading those four rows, before the tag.
  - A regression reaches the release branch, and maybe the public numbers.
- Recommendation: **choose B only if** a release-candidate run is certain to follow the merge before the next tag, and the Planner wants 0.37 in that release without a separate key-holder slot.

**Overall recommendation: Option A.**
- 0.37's whole purpose is a change in the model's behaviour. Structural checks can't see it, as 0.35 showed with green pins and a 4-in-10 regression.
- The current text is measured, passed the ship rule, and is not unsafe, so holding 0.37 costs nothing in safety.
- The A/B costs cents, and it is the only thing that can close DW-1273 honestly.
- The epics AC stays as written.

**Decided in-stage:**
- How the overlap was measured: the guard program itself over a scratch copy, plus a longest-common-run script over every item text and description.
- The pins: three positive phrases and one absence. The absence pins the cause of DW-1273 so it can't return.
- Proposed bars (f) and (g), with 2N-1 of 2N. One miss is tolerated because the invalid-fallback rate is about 5%.

**Footprint:** `Agent/Triage.cls` (lines 26-27) and `Test/Agent/Instructions.cls` (`TestTriage`, its pins). Both are as the story states. This spec is the third file.

## Veto items

| Item | What | Detail | Ask |
| --- | --- | --- | --- |
| (a) New text | Triage.cls lines 26-27, model-facing | The two "New lines" in Design Notes, verbatim. New sentences: "disabling a part is a setting that someone changes on purpose, so it is a change someone chose to make, not a fault"; "It never includes a whole production that stopped running, which is a fault (see "act")."; "A whole production that stopped running is such a fault, even when the report gives no cause: it is not a setting on one part, none of its messages move until it runs again, and a check can find out why it stopped." Removed: "switched off". Measured: no guard hit, longest shared run with any item text 2 words. | Approve verbatim, or give the wording |
| (b) Cross-lane | Lane A files, edited by a Lane C plan | `Agent/Triage.cls` and `Test/Agent/Instructions.cls` are Lane A's (`footprints.lane_a`: `OcuTalon/{Agent,...}/**`, `Test/{Agent,...}/**`). Triage.cls is also `shared_by_entry`. `docker/tests/test-eval-set.sh` is Lane B's (`docker/**`): this story only runs it and never edits it. So this lane-C story crosses into Lane A's two files, within the story's ruled footprint, as Epic 0's re-open stories do (0.35 was lane A). | Confirm the crossing. Implement checks that no Lane A run is editing Triage lines 26-27 |
| (c) Stored data | none | No table, global, setting, Config Store entry, catalog key or upgrade step changes. The text is compiled class source only. | none |
| (d) AD changes | none | AD-7 (static, no `{{`, model, effort, TOOLSETS and MOCKKEY unchanged), AD-8, AD-22 (MOCKKEY routing, so mock answers are unchanged) and AD-28 hold. No spine edit. | none |
| (e) A/B ship question | merge condition or post-merge check | Option A: the Planner's key-holder A/B, (a)-(e) plus (f) and (g), on the pushed head after the freeze, about $0.15-0.40, 0.37 held_merge meanwhile. Option B: merge on pins and CI, with the A/B or the next RC run after the merge, a revert before the tag on a miss, and the epics AC amended. Recommended: **A**. | Choose A or B. Set or approve bars (f) and (g) |

## Public text

- **New model-facing text (for the Planner, verbatim):** Triage.cls lines 26 and 27, the "New lines" in Design Notes, quoted there in full. It is the system prompt of the attention agent. No person sees it in the product, but it shapes every attention decision, so it goes to the Planner as new text, word for word.
- **User-visible text:** none. No README, GUIDE, catalog, page or notification text changes. The README's Measured row moves only through a release-candidate fill.
- The test assertion messages in `Instructions.cls` are developer-facing, so they are not public text.

## Spec Change Log

- 2026-11-15 (plan stage, lane C, local only, push freeze): planned from the epics block, DW-1273, 0.35's spec and A/B record, and the two Planner prompts. Status ready-for-dev. The A/B ship question goes to the gate as a choice of two options, with A recommended.
- 2026-11-15 (implement stage, lane C, local only): Triage.cls lines 26-27 set to the Planner-approved text; the three new phrase pins and the 'switched off' absence pin added to TestTriage; mutations recorded in Verification. No intent, constraint or acceptance text changed.

## Spec gate rulings (Contest Planner, ~16:00Z Nov 15, BINDING)

- (a) Text APPROVED verbatim: the new Triage.cls lines 26 and 27, exactly as in Design Notes.
- (b) Crossing CONFIRMED: lane C edits `Agent/Triage.cls` and `Test/Agent/Instructions.cls` within the footprint; `docker/tests/test-eval-set.sh` is only run.
- (c) and (d): none.
- (e) OPTION A. The key-holder A/B is a MERGE CONDITION, run by the Planner after the push: OLD = feature at that time, NEW = 0.37, N = 3 attempts each, up to one rerun set. Bars (a)-(e) as at 0.35, plus (f) the two stopped findings right in at least 2N-1 of 2N NEW decisions; (g) the two disabled findings right in at least 2N-1 of 2N NEW decisions; (h) no other eval item worse from OLD to NEW by more than the noise floor ruled at 0.35. A fallback counts as a miss. 0.37 stays held_merge until the Planner reports PASS; on FAIL it returns to lane C with the per-item misses. The epics AC stays as written.
- 0.37 is not in 1.0.11.

## Verification

**What this lane can show without a model key:** that the text is what the Planner approved (AC1), that it is pinned (AC2), that it holds no case text (AC3), that the other paragraphs' pins still hold (AC4), and that nothing else changed (AC5). **What it cannot show:** whether the real model now gets the stopped findings right and the disabled findings still right (AC6). This lane has no key, works locally only, and the push freeze stops the key-holder's run on a pushed head. That number comes only from the Planner's A/B (Option A) or a post-merge real-model run (Option B). Mock CI routes by `MOCKKEY`, so it cannot score wording.

**Commands** (repo root; lane-C variables `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-c OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=0 story=0.37 stage=<stage>'` on every `ci/` call; each call under the 10-minute cap):

- (loop) `EVAL_SET_ONLY="held-out-names main-set-texts held-out-texts" bash docker/tests/test-eval-set.sh`. Expected: all three PASS. Under 3 min.
- (loop) `bash docker/tests/test-triage-heartbeat.sh`. Expected: PASS.
- (loop) The AC1 and AC5 diff checks (Tasks & Acceptance). Expected: as stated.
- (once, if a lane-C IRIS slot is free, Task 0) `ci/warm.sh up`, with tag `e0s37iw`.
- (loop) One class per call: `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e0s37iw ci/iris.sh class OcuTalon.Test.Agent.Instructions`, then the same for `OcuTalon.Test.Agent.TriageUserTurn`, `OcuTalon.Test.Agent.PersonaBlock` and `OcuTalon.Test.Agent.RenderMemory`. Expected: each CLASS passed.
- (once) `ci/warm.sh down`.
- (once) The fresh-environment check: `OCUTALON_RUN_TAG=e0s37if ci/iris.sh shard lane-a@Agent`, then the same with `--reverse`, one per call. Expected: every class passed, in either order.
- (once) The rest of `test-eval-set.sh`, in two calls: `EVAL_SET_ONLY="<first half of the rule labels>"`, then `EVAL_SET_EXCEPT="<the same list> held-out-names main-set-texts held-out-texts"`. Expected: all PASS.
- With no IRIS slot, the class runs and the shard run go to CI on the pushed head after the freeze, and the stage records that. The mutations of AC2 are then shown in CI's first run or a later slot (inference).
- (key holder only, never a runner stage) The A/B of AC6, under the gate's ruling.

**Mutations** (Rule 19; each observed red, then reverted byte-identical with cmp):
- AC1: append one character to Triage line 30. The numstat check shows `3	3` and a second hunk.
- AC2: restore line 26 to 0.35's text. `TestTriage` is red on the setting phrase, on the exclusion and on the absence of "switched off". Restore line 27. `TestTriage` is red on "A whole production that stopped running is such a fault".
- AC3: put a main-set item sentence into Triage INSTRUCTIONS, and `FAIL main-set-texts` names the file. Put a held-out item sentence in, and `FAIL held-out-texts`. Put a held-out item text in as a comment outside XData, and `FAIL held-out-names`.
- AC5: append a line to README.md. The name check prints `README.md`.
- AC4 and AC7: no new mutant (no pin changes; CI after the push).

Shared surfaces:
- Triage's XData INSTRUCTIONS, read by Test.Agent.Instructions, TriageUserTurn, PersonaBlock, RenderMemory, test-triage-heartbeat.sh, the `{{` checks and the three guards.
- The INSTRUCTIONS are the cached system prompt (AD-7). The new text adds about 65 words and stays static.

**Implement stage results** (local, no model, no key; AC1 and AC5 diffs against the feature base `cd2c143e4`, which is HEAD):
- AC1: `git diff --numstat cd2c143e4 -- src ':(exclude)src/**/Test/**'` prints only `2	2	src/ocutalon/cls/OcuTalon/Agent/Triage.cls`, and the `grep '^@@'` check prints only `@@ -26,2 +26,2 @@`. Triage.cls lines 26 and 27 equal the "New lines" text extracted from this spec (cmp, byte for byte); the old lines matched the "Old lines" before the edit.
- AC2: `OcuTalon.Test.Agent.Instructions` passed on the lane-C warm stack (tag e037iw), as did `TriageUserTurn`, `PersonaBlock` and `RenderMemory` (AC4), one class per call. `test-triage-heartbeat.sh` PASS. The stack was torn down.
- AC3: `EVAL_SET_ONLY="held-out-names main-set-texts held-out-texts" bash docker/tests/test-eval-set.sh` printed PASS for all three.
- AC5: the name check printed nothing on the final tree. AC6 and AC7 are the Planner's A/B and CI after the freeze.

Verified by the build-auto stage on the final tree: the whole `bash docker/tests/test-eval-set.sh` (all rules passed), `test-boundaries.sh`, `test-class-rules.sh` and `test-triage-heartbeat.sh` all pass; the fresh-environment check `ci/iris.sh shard lane-a@Agent` (tag e037if, 23 classes) passed forward and with `--reverse`, and every stack was torn down.

mutation: AC1 (only lines 26-27 change in product code) - appended one character to Triage line 30: the numstat check printed `3	3` and a second hunk `@@ -30 +30 @@`; restored from the saved copy, cmp identical.
mutation: AC2 line 26 (the setting phrase, the exclusion sentence and the absence of "switched off") - restored Triage line 26 to 0.35's text and ran `OcuTalon.Test.Agent.Instructions` on the warm stack (the reload shows `WARM reloaded 1`): red, FAIL TestTriage on 'a setting that someone changes on purpose', on 'It never includes a whole production that stopped running' and on the absence of 'switched off'; restored, cmp identical, class green again on the same stack.
mutation: AC2 line 27 (the stopped-production act sentence) - restored Triage line 27 to 0.35's text: red, FAIL TestTriage on 'A whole production that stopped running is such a fault' only; restored, cmp identical, class green again on the same stack.
mutation: AC3 main-set-texts - appended the first sentence of finding-orders-stopped's item text as a line inside Triage's INSTRUCTIONS: `EVAL_SET_ONLY="main-set-texts"` printed `src/ocutalon/cls/OcuTalon/Agent/Triage.cls: names a main-set item text in a prompt (main-set-texts)` and `FAIL main-set-texts`, never the text; restored, cmp identical.
mutation: AC3 held-out-texts - appended the first sentence of mail-confirmations-stopped's item text inside INSTRUCTIONS: `EVAL_SET_ONLY="held-out-texts"` printed `names a held-out item text in a prompt (held-out-texts)` and `FAIL held-out-texts`; restored, cmp identical.
mutation: AC3 held-out-names - put mail-confirmations-stopped's whole item text in a `///` comment line outside XData in Triage.cls: `EVAL_SET_ONLY="held-out-names"` printed `names a held-out case, subject line or item text (held-out-names)` and `FAIL held-out-names`; restored, cmp identical.
mutation: AC4 (the neighbouring INSTRUCTIONS paragraphs stay intact) - changed one word of the heartbeat paragraph, Triage line 39 ("fine" to "all fine"): `bash docker/tests/test-triage-heartbeat.sh` printed `FAIL paragraph` (and the diff showed a second hunk `@@ -39 +39 @@`); restored from the saved copy, cmp identical, the script green again. The class pins keep their own recorded mutants: `TriageUserTurn` in Story 30.5's spec (and 30.9's), `RenderMemory:TestTriageParagraph` in 41.4's, `PersonaBlock:TestParagraphs` in 40.5's and `Instructions.TestNoTemplates` in 1.1's (provenance corrected in code review).
mutation: AC5 (no README, GUIDE, catalog, mock, eval or docker change) - appended a line to README.md: the name check printed `README.md`; restored, cmp identical.

**QA records (Story 0.37, QA stage, lane C, warm tag e037qw, no model, no key):**
- Reviewed the pins against AC1-AC5 and the I/O matrix. Already pinned, nothing added: the two 0.35 phrases, the three new phrases, the absence of "switched off" (TestTriage); the `"outcome"`, `"reasons"` and `"confidence"` field names and each quoted outcome value (TestTriage); no `{{` (TestNoTemplates); no toolset (TestToolsets); `MOCKKEY` "triage" reaching the mock header, so CI mock answers are unchanged (Test.Contract.Mock); the guards over INSTRUCTIONS (AC3 mutants above). The model, effort and the real-model result are not testable here (AC6, the Planner's A/B).
- Gap found and closed: `TestTriage` passes anywhere in the text, and each bullet quotes its own outcome, so two structural properties of the A/B were unpinned. New method `OcuTalon.Test.Agent.Instructions.TestTriageOutcomes` pins them: (1) the outcome field offers exactly the OUTCOME values, in order, in one sentence, under "The four outcomes are:", with one bullet per outcome in that order; (2) the 0.37 sentences sit in the bullet they belong to (setting, choice and the `(see "act")` exclusion in tellnow; the stopped-production fault sentence in act) and neither bullet holds the other's.
- Result: `ci/iris.sh class OcuTalon.Test.Agent.Instructions` passed on the warm stack with the new method; `test-class-rules.sh` and `test-boundaries.sh` pass. Triage.cls is byte-identical to the implementation commit after every mutant below.

mutation: QA outcome sentence - changed the "outcome" field line to `one of the quoted values "ignore", "digest" or "tellnow".` (dropped "act"): `OcuTalon.Test.Agent.Instructions` FAIL TestTriageOutcomes on 'the outcome field offers exactly the OUTCOME values, in order'; TestTriage stayed green (the gap); restored, cmp identical.
mutation: QA placement - moved the sentence "A whole production that stopped running is such a fault, even when ..." from the act bullet to the end of the tellnow bullet: FAIL TestTriageOutcomes on 'the act bullet says A whole production ...' and on 'the tellnow bullet does not say A whole production ..., which is the act bullet's' (message as re-observed in code review, M10); TestTriage stayed green (the gap); restored, cmp identical.
mutation: QA exclusion pointer - removed ` (see "act")` from the tellnow bullet: FAIL TestTriageOutcomes on 'the tellnow bullet says It never includes a whole production that stopped running, which is a fault (see "act").'; TestTriage stayed green; restored, cmp identical.
mutation: QA bullet order - swapped the ignore and digest bullets: FAIL TestTriageOutcomes on 'and it is the first line under "The four outcomes are:" and its blank line' and twice on 'and it follows the bullet of the outcome before it, on the next line' (messages as re-observed in code review, M4); restored, cmp identical, class green again.

**Code review records (lane C, warm tag e037cw, no model, no key):** `OcuTalon.Test.Agent.Instructions` passed on the warm stack before and after the review patches; `EVAL_SET_ONLY="held-out-names main-set-texts held-out-texts" bash docker/tests/test-eval-set.sh` all PASS; `test-triage-heartbeat.sh`, `test-class-rules.sh` and `test-boundaries.sh` pass. The spec and the new lines share no run of 5 words with any main-set or held-out item's subject, text, sender or summary (a word-run scan, shown to flag a case file against itself). Each mutant below went red on the same stack, was restored from a saved copy (cmp identical) and the class was green again on that stack.

mutation: review M1 (absence pin, case) - appended " Switched off parts stay off." to Triage line 41: FAIL TestTriage on 'the instructions no longer say 'switched off' ...'; restored, cmp identical, green.
mutation: review M9 (AC2 re-observed after the absence-pin patch) - restored Triage line 26 to 0.35's text: FAIL TestTriage on 'a setting that someone changes on purpose', 'It never includes a whole production that stopped running' and the absence of 'switched off', and FAIL TestTriageOutcomes on the two tellnow-bullet phrases; restored, cmp identical, green.
mutation: review M2 (bullets right under the heading) - inserted the line "Choose one." between the heading's blank line and the ignore bullet: FAIL TestTriageOutcomes on 'and it is the first line under "The four outcomes are:" and its blank line'; restored, cmp identical, green.
mutation: review M3 (bullets on consecutive lines) - inserted a blank line between the digest and tellnow bullets: FAIL TestTriageOutcomes on 'and it follows the bullet of the outcome before it, on the next line'; restored, cmp identical, green.
mutation: review M5 (act holds no tellnow exclusion) - appended " It never includes a whole production that stopped running." to the act bullet: FAIL TestTriageOutcomes on 'the act bullet does not say 'It never includes a whole production that stopped running', which is the tellnow bullet's'; restored, cmp identical, green.
mutation: review M6 (tellnow holds no act definition) - appended " This is not a fault that is happening now." to the tellnow bullet: FAIL TestTriageOutcomes on 'the tellnow bullet does not say 'a fault that is happening now', which is the act bullet's'; restored, cmp identical, green.
mutation: review M7 (one bullet per outcome) - duplicated the tellnow bullet line: FAIL TestTriageOutcomes on 'one bullet for the outcome tellnow' (and on the next-line check); restored, cmp identical, green.
mutation: review M8 (act holds no tellnow choice words) - appended " It is not a setting that someone changes on purpose." to the act bullet: FAIL TestTriageOutcomes on 'the act bullet does not say 'a setting that someone changes on purpose', which is the tellnow bullet's'; restored, cmp identical, green.

## Review Triage Log

### 2026-11-15 - Review pass
- verdicts: 15 findings - high 0, medium 0, low 14, false 1, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind Hunter 1 and Edge Case Hunter 6: Auto Run Result still reads `Status: ready-for-dev` - the section is rewritten at finalize with the final status; a spec-edit fix is also out of the triage scope.
  - `[low]` `[reject]` Blind Hunter 2: the tellnow sentence is wordy with a comma splice - the text is Planner-approved word for word (gate ruling (a), AC1); rewording it is a text change that only the Planner can make.
  - `[low]` `[reject]` Blind Hunter 3 and Edge Case Hunter 2: one part that is stopped but not disabled is in neither bullet - act's general definition (a fault happening now) covers it and no eval case or AC is about it; adding words changes approved text. The A/B measures the neighbouring cases.
  - `[low]` `[reject]` Blind Hunter 3: the absence pin matches only the exact words "switched off" - the pin is as the spec states it and targets DW-1273's cause; a synonym guard would be speculative.
  - `[low]` `[reject]` Blind Hunter 4 and Edge Case Hunter 1: a whole production stopped on purpose, or with a stated cause, goes to act - this is the intent itself ("a whole production that stopped running is a fault"; spec title and AC); the cause-free qualifier is part of the approved sentence.
  - `[low]` `[reject]` Edge Case Hunter 3: a whole production disabled as a setting is not placed - "disabled" for a whole production is outside the approved text and the cases; the exclusion names only a production that stopped running.
  - `[low]` `[reject]` Edge Case Hunter 4 and Verification Gap other 1: a case or synonym variant of "switched off" would pass the pin - same as above, speculative hardening beyond the spec's assertion.
  - `[low]` `[reject]` Edge Case Hunter 5: the three phrases are pinned anywhere in the text, so a move or swap of them between bullets passes - a theoretical edit; the byte-diff of lines 26-27 (AC1) already holds the placement.
  - `[low]` `[patch]` Verification Gap: AC4 has no `mutation:` line - closed by the build stage in the review pass: one word of the heartbeat paragraph (Triage line 39) was changed, `test-triage-heartbeat.sh` went `FAIL paragraph`, restored byte for byte (cmp), green again; the line is in `## Verification`.
  - `[low]` `[reject]` Verification Gap other 2: the three positive pins check wording, not meaning - the model's meaning is the A/B's (AC6, Planner), and the guards cover copying.
  - `[low]` `[reject]` Verification Gap other 3: AC1 and AC5 name `b7340cbee` as their base, which would list unrelated feature changes - the implement results record that the checks ran against `cd2c143e4` (HEAD), and `baseline_revision` is `cd2c143e47`; a spec-edit fix is out of scope.
  - `[false]` `[reject]` Intent Alignment: the spec names two eval case ids in its mutation notes, which the held-out-names guard might flag - the whole `test-eval-set.sh` passed on the tree with those notes in place (all rules passed).
  - `[low]` `[reject]` Intent Alignment: the pins are phrase checks on the prompt text, so they do not exercise the model's classification - the intent says the real-model score can't be measured in this lane and goes to the Planner's A/B (AC6).
  - `[low]` `[reject]` Intent Alignment: the "switched off" absence pin shows only one cause is removed - the same as the synonym row above.
  - `[low]` `[reject]` Intent Alignment: the new act sentence's reasons steer the model and whether they work is unmeasured - AC6, the Planner's A/B, measures it.

## Auto Run Result

Status: done
Blocking condition: none
Note: Option A is in force (gate ruling): the key-holder A/B (AC6) is a merge condition run by the Contest Planner after the push; this branch stays held_merge until the Planner reports PASS. Nothing was pushed.

**Summary:** Triage.cls lines 26 and 27 are now exactly the Planner-approved "New lines" (a disabled part is a setting someone changes on purpose, so tellnow; a whole production that stopped running is a fault, so act; "switched off" is gone). `TestTriage` pins the three new phrases and the absence of "switched off", beside the two 0.35 pins.

**Files changed:**
- `src/ocutalon/cls/OcuTalon/Agent/Triage.cls`: lines 26-27 only.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls`: the new phrase loop, the absence pin and two comment clauses.
- This spec file: status, baseline, Verification results and mutation lines, the triage log.

**Review:** four layers reported 15 findings: high 0, medium 0, low 14 (13 rejected, 1 patched), false 1. Patched: AC4's missing `mutation:` line (a heartbeat-paragraph mutant, red, reverted). Every rejected finding is in the triage log with its reason; none asks for a change that the approved text allows. Follow-up review recommended: false (no high patched).

**Verification:** AC1 and AC5 diff checks as specified (base `cd2c143e4`); the whole `test-eval-set.sh`, `test-boundaries.sh`, `test-class-rules.sh` and `test-triage-heartbeat.sh` pass; `Test.Agent.Instructions`, `TriageUserTurn`, `PersonaBlock` and `RenderMemory` pass on the lane-C warm stack; `ci/iris.sh shard lane-a@Agent` (23 classes) passes forward and in reverse on a fresh stack; all mutations went red and were reverted byte for byte. Matrix rows 1-4 describe the real model's choice, so only the Planner's A/B (AC6) can cover them; rows 5-7 are covered by the pins and the guard mutants. In-flight Lane A check: no remote branch changes Triage.cls lines 26-27 (the only branch that lists the file, `origin/OCT-epic11`, does so through one merge commit and has no net diff against feature).

**Residual risks:** the real-model rates (AC6) and CI on the pushed head (AC7) are unmeasured here; the exclusion sentence could pull a "will stop later" warning toward `act` (bars (a) and (b)).
