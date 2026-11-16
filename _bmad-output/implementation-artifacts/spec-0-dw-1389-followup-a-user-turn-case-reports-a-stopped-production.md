---
title: 'DW-1389 follow-up: a user-turn case reports a stopped production'
type: 'chore'
created: '2026-11-16'
status: 'done'
baseline_revision: 'a0add4f4a803fe0d7fc6ee982cbd020186306f87'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: []
deferred:
  - summary: >-
      No committed check ties scores.userTurns.total, or the per-case entries of rules-only.json, to the number of user-turn folders in eval/.
    evidence: |-
      test-eval-set.sh rule `cases` does not read scores.userTurns or compare cases[] with the folders, and compare.mjs --column has no user-turn row, so the committed report can drift from the case set. Pre-existing for the six siblings; the spec forbids editing test-eval-set.sh and the release fork's re-run replaces the file.
    location: >-
      docker/tests/test-eval-set.sh rule cases
    severity: low
---

<intent-contract>

## Intent

**Problem:** None of the six user-turn cases in the main evaluation set has the user report a fault in their own words. DW-1389's A/B showed that Triage's reasons can drift toward describing production state. A turn such as "Our Orders production has stopped..." is still the user's own message, but no case measures whether Triage treats it that way: tell now, with reasons that only classify the turn.

**Approach:** The Contest Planner ruled (`epic-21-rulings-20261113-1800.md`, "User-turn case..." ~06:30Z Nov 16, revised ~07:30Z Nov 16; BINDING) and approved the main draft **verbatim**. The work:
- Add `eval/user-turn-orders-stopped/case.json`, byte for byte as approved.
- Pin it in `Test.Eval.Cases`, which grows from six user-turn cases to seven, and update its docs.
- Refresh `eval/results/rules-only.json` so that `scores.userTurns.total` reads 7.

The case is eval-only and report-only. It no longer waits for DW-1389. The stale "the next paragraph" reference (`Triage.cls:37`) is **not** part of this story: it is held until after 1.0.12, in one A/B with any narrower DW-1389 wording.

## Boundaries & Constraints

**Footprint (the ruled one; lane C makes the edits, Veto item 2):**
- `eval/user-turn-orders-stopped/case.json` (new);
- `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls`: `TestUserTurnCases` (joined list, `wanted`, message) and the two doc comments (header L16, method doc L270);
- `eval/results/rules-only.json`: the new case's three entries and `userTurns.total` 7.
- Plus this spec and the bookkeeping under `_bmad-output/`.

**Always:**
- `case.json` is the approved draft byte for byte: 2-space JSON, arrays expanded, one trailing newline, ASCII only, SHA-256 `7df8056a73b085670892302fd263426f5e2e51e851232db263b73b82212a9fcc`. `recordedBy` stays `"written for the evaluation set (DW-1389 follow-up)"`: the ruling gives the case no DW id, so the draft's text is kept verbatim.
- `rules-only.json` keeps its form: one line, compact (`JSON.stringify` round-trips the committed file byte for byte), no trailing newline, its `run`, `builtAt` and `actions.since` unchanged, and every other entry unchanged. Only the new case's `cases[]`, `userTurnChecks[]` and `fallbacks[]` entries are added, in name order (after `user-turn-forget`), and `scores.userTurns.total` goes from 6 to 7. `right` stays 0 and `share` stays 0.
- The three added entries come from a real fixed-rules run (`--rules-only main`, Verification). They must equal `user-turn-forget`'s entries with only `case` renamed, which is what the fixed rules give every user-turn case.
- `node eval/compare.mjs --column eval/results` prints the same ten lines as at the baseline, `date|November 12` included. The README is not touched.
- Every `ci/iris.sh`, `ci/warm.sh` and `eval/run.sh` call carries the lane-C variables (Verification). Each run tag starts with `e0ut`. No model, no real key, no `.env`, no dev slot and no IRIS MCP tool.

**Never:**
- Edit the draft's text, description, phrases or `recordedBy`. Add a second case, or the alternatives A or B.
- Touch `Triage.cls`, `TriageUserTurn.cls`, any XData INSTRUCTIONS, the mock scenarios, `Eval.Report`, `Eval.Gate`, `eval/run.sh`, `eval/compare.mjs`, `test-eval-set.sh`, `rules-only-held-out.json`, the README, `release/**` or any other test class.
- Copy a fresh `rules-only.json` over the committed one whole. A fresh run on today's tree also picks up Story 23.3's two incidents (`orders-target-renamed`, `orders-target-to-review`), which the committed report does not hold. The column would then change (date, `main-incidents` 11 to 13, "0 of 11" to "0 of 13"), `readme-column` would go red, and the README would have to change. That re-run and re-commit belong to the release fork (`eval/run.sh` L1292-1304), not to this story.
- Change `turns >= 8` at Cases L211 or its message. It is a floor and stays true at 7 user turns.

## I/O & Edge-Case Matrix

| Scenario | Input | Expected |
|----------|-------|----------|
| The shipped case, in `Test.Eval.Cases` | the seven user-turn folders | the joined list is exactly the seven names. The new case has the ruled text, `[["user"]]`, the 14 absent phrases and the ruled `recordedBy`, and it is not held out |
| `TestRecordedCases` | the whole eval/ | the new case is sent as the decide request of a user turn of owner eval. Its Input holds `turn.text`. `turns` counts it (the floor of 8 still holds) |
| The fixed rules (no key) | the new case | `no_key` fallback, got `tellnow`, `right` false. `userTurns` reads 0 of 7 |
| The CI mock (push run) | the new case | the triage mock key answers it, as it answers the other six. No B/ prompt scenario is a substring of the turn text (checked at plan time) |
| A real-model RC run | the new case | right only for tell now with reasons that name the user and hold none of the 14 phrases. Report-only: `userTurns` is not in `Gate.SCORES` |

</intent-contract>

## Code Map

- `eval/user-turn-*/case.json` (6): the same shape as the draft. The draft differs from `user-turn-forget` only in `name`, `description`, `turn.text` and `recordedBy`.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls` (1064 lines; WARM-SAFE):
  - L16-17 header bullet `TestUserTurnCases`: "exactly the six named ones, one for each "Try it yourself" chip, one remember case ... and one forget case ...";
  - `TestRecordedCases` (L124): handles a user-turn case generically. L211 `turns >= 8` is a floor;
  - L270-272 method doc of `TestUserTurnCases`: "exactly one for each of the four ... chips, one remember case ... and one forget case ..., with the chip's exact text";
  - `TestUserTurnCases` (L273):
    - L290 asserts the sorted joined list (six names) and "exactly the six named ones";
    - L292 `wanted`: each entry is name, exact text and recordedBy;
    - L294-316: each wanted case is checked for name, kind and heldOut, `turn` equal to `{"text": ...}`, the expectation keys, `[["user"]]`, the 14 phrases and size 14, `AssertTurnShape` and `recordedBy`.
- `eval/results/rules-only.json` (25,362 bytes, one line, run `TJn4Fgi8EZcGC9PZnk5U9Q`, builtAt `2026-11-12T14:39:09Z`):
  - each user-turn case appears exactly 3 times: `cases[]`, `userTurnChecks[]` and `fallbacks[]` (`{"case":...,"reason":"no_key","outcome":""}`);
  - `turnChecks[]` holds no user-turn case;
  - `scores.userTurns` is `{"right":0,"total":6,"share":0}`;
  - the arrays are in name order;
  - it lacks the two 23.3 incidents (pre-existing; see Never).
- How the file is made: `bash eval/run.sh --rules-only main` (Story 0.27). It **starts a throwaway stack**: the push run's stack without the key, `RestoreKeys`, `Keys.Status` 0, then `Eval.Report.Run` with rulesOnly 1. It takes about 3 minutes and writes `rules-only.json` into `OCUTALON_EVAL_REPORT_DIR`. Nothing reads the committed file except:
  - `compare.mjs --column`, which gives the README's fixed-rules column: date, item and incident counts, held-out and unsafe. It has **no user-turn row**;
  - `test-eval-set.sh` `cases` (eval/results holds only the two files, `rulesOnly` true, no home folder) and `readme-column`;
  - the push run's NOTE comparison (`eval/run.sh` L1292-1304, date excluded, never a failure).
- `docker/tests/test-eval-set.sh` (25 rules). The ones that read the new case:
  - `cases`: name equals the folder, kind of `Eval.Report CASEKINDS` (user-turn is one), boolean heldOut, description, recordedBy and a non-empty expectation. The rule has no user-turn branch beyond these;
  - `set` and `incidents`: they do not count user turns;
  - `held-out-names`: no held-out name, subject or text may appear in a tracked or not-ignored file. Checked at plan time over all 12 held-out cases: 0 hits;
  - `main-set-texts`: reads only `item` subject, text and sender and precedent summaries, **not** `turn.text`. This is the ruled LOW Lane B ledger item for after 1.0.12, not this story. Checked by hand at plan time: no 5-word run of the turn text in any of the 11 INSTRUCTIONS blocks, and it holds no distinctive token;
  - `feed`: the case does not name the test feed;
  - `readme-column`: reads `eval/results`;
  - `rc-flow` and `key-proof`: their key scans below eval/ find no key-like text;
  - `key-like`: scripts only.
- Other places that list or count user-turn cases. All are **unchanged**, and none goes red:
  - `Test/Eval/Report.cls`:
    - `TestShippedChipCasesScoreTheHostReasons` (L2235) loops over a named list of six. It does not require exactly six. The new case's expectation is byte-identical to `user-turn-forget`'s, so adding it would add no coverage;
    - `TestUserTurn` "1 of 6" (L2161) is synthetic fixtures;
  - `Test/Eval/In.cls` `TestForgetCaseRecorded` and `Test/Agent/RememberDecision.cls` pin their own cases only;
  - `Test/Eval/PersonaSweep.cls` reads `eval/persona-cases/`;
  - `Eval.Report` and `Eval.In` count user turns dynamically;
  - README, docs, `release/**`, the release and readme test scripts and `ci/`: no user-turn count. The README table has no user-turn row.
- Unmerged branches at plan time: of 61 `origin/OCT-*` branches, only `OCT-epic0-dw1421` touches `eval/`, in `eval/run.sh` and `eval/capture-fallbacks.sh`, not this footprint.

## Tasks & Acceptance

**Execution:**
1. `eval/user-turn-orders-stopped/case.json`: copy the approved draft byte for byte. The text is in Design Notes, and the hash is in Always.
2. `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls`:
   - L16: replace `the user-turn cases are exactly the six named ones, one for each "Try it yourself" chip, one remember case (Story 30.9, DW-890) and one forget case (Story 9.11, DW-902), each with the exact` with `the user-turn cases are exactly the seven named ones, one for each "Try it yourself" chip, one remember case (Story 30.9, DW-890), one forget case (Story 9.11, DW-902) and one in which the user reports that the Orders production has stopped (DW-1389 follow-up), each with the exact`. Also add `; DW-1389 follow-up` after `DW-908` in that bullet's label.
   - L270: replace `one remember case (Story 30.9, DW-890) and one forget case (Story 9.11, DW-902), with the chip's exact text,` with `one remember case (Story 30.9, DW-890), one forget case (Story 9.11, DW-902) and one in which the user reports that the Orders production has stopped (DW-1389 follow-up), with its exact text,`.
   - L290: the joined list becomes `user-turn-anything-wrong,user-turn-failure-earlier,user-turn-forget,user-turn-orders-stopped,user-turn-productions,user-turn-remember,user-turn-what-can-you-do`, and the message becomes `"the user-turn cases of eval/ are exactly the seven named ones"`.
   - L292: append to `wanted`, after the forget entry: `, $ListBuild("user-turn-orders-stopped", "Our Orders production has stopped and no orders have come through since lunchtime.", "written for the evaluation set (DW-1389 follow-up)")`.
   - Nothing else changes, and the file stays ASCII.
3. `eval/results/rules-only.json`: run `--rules-only main` and splice in the new case's entries (the Verification commands). Do this after task 1, on a tree that holds the final `case.json`.

**Acceptance Criteria:**
- AC 1: Given the new folder, when its `case.json` is hashed, then the SHA-256 is the approved draft's, `7df8056a...a9fcc`, and the file is plain ASCII.
- AC 2: Given eval/, when `OcuTalon.Test.Eval.Cases` runs, then it passes. `TestUserTurnCases` finds exactly the seven named user-turn cases. The new one has the ruled text, `[["user"]]`, the 14 absent phrases, `heldOut` false, the fields of its kind and the ruled `recordedBy`. `TestRecordedCases` sends it as a user-turn decide request.
- AC 3: Given the tree, when every rule of `docker/tests/test-eval-set.sh` runs, then all 25 PASS.
- AC 4: Given the committed `rules-only.json`, when the new case's three entries are removed and `userTurns.total` is set back to 6, then the result is byte-identical to the baseline file. The three entries equal `user-turn-forget`'s with `case` renamed and equal the fresh run's entries, and `scores.userTurns` is `{"right":0,"total":7,"share":0}`.
- AC 5: Given `eval/results`, when `node eval/compare.mjs --column eval/results` runs, then its output is byte-identical to the baseline's (`date|November 12`, 24, 11, 6 of 24, 0 of 11, 2 of 12, 0, 0, none, none).
- AC 6: Given CI on this story's head, when it finishes, then every workflow is green (lead).

### Review Findings

Code review 2026-11-16, full mode (Blind Hunter, Edge Case Hunter, Verification Gap, Acceptance Auditor), diff `a0add4f4a..39080fbdc` without bookkeeping. 19 raw findings: 0 high, 0 med; 1 patch, 1 ledgered (`wontfix-accepted`), 17 rejected. The Acceptance Auditor found no AC violation; the reviewer re-checked the focus items: hash `7df8056a...a9fcc`; the six sibling user-turn entries unchanged; removing the three new entries and setting `userTurns.total` back to 6 gives the `a0add4f4a` file byte for byte; `compare.mjs --column` byte-identical; README, `rules-only-held-out.json` and `Triage.cls` untouched; the only other "6 user-turn" text is `Report.cls:2161`, a synthetic fixture (Code Map).

- [x] [Review][Patch] The per-case message "it asks the chip's exact text" was wrong for three of seven cases (remember, forget, orders-stopped) after the method doc became "its exact text" [src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls:301] - now "it asks its exact text, and nothing else". mutation: `lunchtime` to `noon` -> red: `Cases.TestUserTurnCases` (`user-turn-orders-stopped: it asks its exact text, and nothing else` and `its case.json is the approved draft byte for byte`); reverted byte for byte, green again on the same warm stack.
- [x] [Review][Defer] No committed check ties the user-turn entries and `scores.userTurns.total` of `eval/results/rules-only.json` to the user-turn folders (frontmatter `deferred`; VerGap, Blind, Edge) [docker/tests/test-eval-set.sh rule cases] - ledgered DW-1434 `wontfix-accepted` owner=`0-27-a-measured-comparison-of-the-agent-and-the-fixed-rules-repla`, reopen_if the committed `userTurns.total` differs from the user-turn folder count. Pre-existing for the six siblings; its natural guard is outside the ruled footprint, and the score is report-only.

Rejected:
- (low) The new SHA-256 assertion fails on a CRLF checkout, since `.gitattributes` has no `eol=lf` for `eval/**` (Edge, VerGap, Auditor, Blind): no CRLF checkout runs these tests (macOS stacks, Linux CI), `test-eval-set.sh held-out-frozen` already byte-hashes `eval/held-out/*/case.json` the same way, and the fix (`.gitattributes`) grows the footprint.
- (low) QA's hash pin and private `Sha256` helper go beyond the ruled Cases.cls edit list and "No helper is added" (Auditor, Blind): QA was authorized to add gap tests in `Test.Eval.Cases`; the helper is private to the test class, no shared hex SHA-256 helper exists to reuse (`Core/SecretHandoff.cls` inlines the same 3-line loop), and the QA block records it. Planner may overrule.
- (false) The Auto Run Result's "Files changed" omits QA's helper and assertion (Blind, VerGap): the Auto Run Result covers the implement pass only (Rule 14); the QA block records QA's change.
- (low) The earlier triage line VerGap 3 says "siblings are pinned the same way" (Blind, Edge): a spec-record correction of a prior pass; the QA block states what is byte-pinned now (this case only).
- (low) The 23.3 drift of the committed report (11 vs 13 incidents) is not ledgered (Blind): it is DW-1358 (decision-pending), and `eval/run.sh` L1292-1304 documents the release fork's re-run.
- (low) Only two of the fresh run's column lines are recorded (Blind): Verification L228 records `scores.incidents` and `builtAt` when a main-only run has no held-out report, which is what was recorded.
- (false) `status: done` while AC 6 is open (Blind): AC 6 and the fresh check are the lead's by the spec.
- (false) The Auto Run mutation "the hash check" is ambiguous (Blind): it names the AC 1 `shasum` check of the spec's mutation list.
- (low) AC 2's `TestRecordedCases` clause has no per-case mutation, and `turns >= 8` cannot fail from this case (VerGap): Rule 19 scopes to one pinning test per AC, and AC 2's pin has seven recorded mutations; the floor is not claimed as a pin.
- (low) AC 1's ASCII half and AC 2's `[["user"]]` and field-shape clauses have no mutation of their own (VerGap): one per AC, and the hash pin now catches any byte change.
- (false) `SHAHashStream`'s signature was not verified (VerGap): `%SYSTEM.Encryption.SHAHashStream(bitlength, input, ByRef sc)` exists, and the pin was observed green and red.
- (low) `run`/`builtAt` still name the Nov 12 run for spliced entries (Edge): option (iii), by design; recorded in Residual risks.
- (low) The three entries are only claimed measured (Auditor): `fresh ok` recorded; measured and cloned give the same bytes.
- (low) Verification commands use `8fa1e285b` while the baseline is `a0add4f4a` (Auditor): the two are identical for `eval/` and Cases.cls.
- (false) The Auto Run file list omits `cycle-log-epic-0.md` (Auditor): bookkeeping, excluded by design.
- (low) The hex loop duplicates existing code (Blind): there is no shared helper to call; see the helper item above.
- (low) The spliced values could be edited without a committed test failing (Edge): same root cause as DW-1434.

Runs after the patch (lane-C wrapper, warm `e0utqw`, torn down): `OcuTalon.Test.Eval.Cases` passed; `test-eval-set.sh` part 1 (14 rules) PASS (part 2 PASS on the QA commit; the patch touches no file it reads); `test-boundaries.sh` and `test-class-rules.sh` passed. Follow-up review: not recommended (no high or med; one message-text patch).

## Design Notes

**The approved case (verbatim; `eval/user-turn-orders-stopped/case.json`):**

```json
{
  "name": "user-turn-orders-stopped",
  "kind": "user-turn",
  "heldOut": false,
  "description": "The user reports in their own chat message that the Orders production has stopped, and asks OcuTalon for nothing (DW-1389 follow-up). A fault that the user reports is still the user's own message, so the case is right only when Triage decides tell now and its reasons only classify the turn as the user's own message: they never describe the state of a production, what Triage can or cannot look up, or whether anything needs the user.",
  "turn": {
    "text": "Our Orders production has stopped and no orders have come through since lunchtime."
  },
  "expectation": {
    "keyPhrases": [
      [
        "user"
      ]
    ],
    "absentPhrases": [
      "tool",
      "access",
      "look up",
      "cannot",
      "can't",
      "unable",
      "needs the user",
      "need the user",
      "nothing",
      "healthy",
      "all clear",
      "everything is",
      "no failure",
      "no error"
    ]
  },
  "recordedBy": "written for the evaluation set (DW-1389 follow-up)"
}
```

The Planner's chat prompt showed this in compact form. The approved draft file in the Planner's scratch folder holds the 2-space, arrays-expanded layout above, which is the layout of the six siblings. The SHA-256 is that file's. If the implementer cannot reach that file, they write the block above with a trailing newline, and it must hash to the same value.

**How `rules-only.json` is refreshed: a measured splice, not a whole copy and not an invented entry.** There are three options:
- (i) Copy a fresh run whole. This is Story 0.31's way, but today it also brings in the 23.3 drift, so the README would have to change. That grows the footprint (Never).
- (ii) Hand-write the entries by cloning a sibling. This needs no stack, but the entries would not be measured.
- (iii) **Chosen.** Run `--rules-only main` once on a lane-C throwaway, take only the new case's three entries from it, and splice them into the committed file with `userTurns.total` 7. Then check that:
  - they equal the sibling clone, which is what (ii) would give;
  - the fresh run's six sibling entries equal the committed ones, so this kind has not drifted.

  The committed file keeps the Nov 12 run's `run` and `builtAt`. It is not a single measured run any more, but it adds only measured entries for a new case, and the column is unchanged. The release fork's re-run replaces the whole file anyway (`eval/run.sh` L1292-1304).

Stop with `## Clarification Needed` in either case:
- the fresh entries differ from the clone, or the fresh siblings differ from the committed ones. The fixed rules then answer user turns differently than on Nov 12, and splicing would mix two behaviours;
- `--rules-only main` cannot run, for example because the lane is locked through the quiet window. Do not fall back to (ii) without the Planner.

**Decided in-stage:**
- The new `wanted` entry goes last, after forget. The order of `wanted` is not asserted, and the joined list is sorted by `$Order`.
- The `turns >= 8` message ("four user-turn") is stale but is not a doc of the user-turn list. It stays (Never).
- `TestShippedChipCasesScoreTheHostReasons` is not extended (Code Map).
- The fresh run's full `--column` output (expected: `date|November 16`, `main-incidents|13`, `0 of 13`) is recorded in the Auto Run Result for the Planner, as evidence of the pre-existing eval/results drift that the 1.0.12 release fork must re-commit. It is not acted on here.

**Governing ADs:** AD-22 (the evaluation set scores the product's own path; the user-turn score is report-only), AD-29 (lane A owns `eval/` and `OcuTalon.Eval`), AD-19 (no key reaches the rules-only run). No AD is amended.

**Integration ACs (Rule 1):** none. No service, module or shared component is introduced. It consumes `Eval.In` (user-turn decide request), `Eval.Report` (`userTurns`) and `eval/run.sh --rules-only`. It is consumed by the Planner's 1.0.12 RC run and the release fork's re-run.

**Extend, don't copy (Rule 2):** the case reuses the siblings' expectation verbatim, and the pin extends the existing `wanted` list. No helper is added.

**Ledger (Rule 17):** the DW-1389 side question, item 1, is addressed. Item 2, a Triage clause, waits until this case misses in an RC or A/B. Item 3, the stale reference, is held until after 1.0.12 (ruling ~07:30Z). The guard gap (`main-set-texts` does not read `turn.text`) is the Planner's LOW Lane B item for after 1.0.12. This story only checks it by hand (Code Map).

## Veto items

| # | Gate item | What | Recommendation |
|---|-----------|------|----------------|
| 1 | (a) Eval-set change | One new main-set user-turn case, `eval/user-turn-orders-stopped`, approved verbatim (ruling ~06:30Z Nov 16, timing revised ~07:30Z). The pin goes from 6 to 7 cases. `rules-only.json` is refreshed by the measured splice of Design Notes: the new case's three entries from a fresh `--rules-only main` run, `userTurns` 0 of 7, everything else unchanged. The README is untouched. | Approve, as ruled. Confirm the splice: a whole copy would change the README column through pre-existing 23.3 drift. |
| 2 | (b) Cross-lane edits | `eval/` and `OcuTalon.Test.Eval.Cases` are Lane A (AD-29). Lane C makes the edits under the Planner's lane-C order ("5. The user-turn case, when ready"). At plan time, no unmerged `OCT-*` branch touches these paths. | Approve, as the Planner's assignment. |
| 3 | (c) Stored data or schema | None. | Approve. |
| 4 | (d) Architecture change | None. | Approve. |
| 5 | (e) Behaviour change (report-only) | The next RC run's user-turns score has 7 in the denominator. If Triage describes the stopped production, which DW-1389's drift suggests, the right count stays where it was and the share drops. The score stays report-only (not in `Gate.SCORES`) and moves no verdict. The 1.0.12 RC report states the new denominator plainly, with no adjective (ruling). | Approve. |

## Public text

None. No catalog key, UI string, log text, README or release-note text changes. The case's description and turn are evaluation data, not product text. The RC report's sentence about the new denominator is the Planner's text.

**Findability:** no UI change.

## Verification

Lane C throwaway only (Rule 21), never a dev slot. Set these on every `ci/iris.sh`, `ci/warm.sh` and `eval/run.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=0 stage=<stage>'`. `<lane-C>` below stands for these. Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e0utiw`. In a release quiet window, take the lane's lock only after any running review's teardown. `<scratch>` is the stage's own scratch folder, outside the checkout. Keep each call one command, `timeout: 600000`, and expect it to finish well under 10 minutes.

**Commands** (from the worktree root):
- `shasum -a 256 eval/user-turn-orders-stopped/case.json` (once). Expected: `7df8056a73b085670892302fd263426f5e2e51e851232db263b73b82212a9fcc`.
- `for f in eval/user-turn-orders-stopped/case.json src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls; do LC_ALL=C tr -d '\011\012\040-\176' < "$f" | wc -c; done` (once). Expected: both 0.
- test-eval-set in two parts, each run in a loop:
  - Part 1: `EVAL_SET_ONLY='cases markers set demo incidents held-out held-out-frozen held-out-names main-set-texts held-out-texts feed compare readme-column' bash docker/tests/test-eval-set.sh`;
  - Part 2: `EVAL_SET_EXCEPT='cases markers set demo incidents held-out held-out-frozen held-out-names main-set-texts held-out-texts feed compare readme-column' bash docker/tests/test-eval-set.sh`.
  - Expected: every rule PASS, 25 in total. Split part 2 further, for example `rc-flow` alone, if it runs over about 150 s.
- `<lane-C> OCUTALON_RUN_TAG=e0utiw bash ci/warm.sh up` (once). Use Story 0.27's R1 log arrangement if it runs over about 150 s.
- `<lane-C> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e0utiw bash ci/iris.sh class OcuTalon.Test.Eval.Cases` (loop). Expected: `CLASS OcuTalon.Test.Eval.Cases passed`.
- `<lane-C> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e0utiw bash ci/iris.sh class OcuTalon.Test.Eval.Report` (once, regression). Expected: passed.
- `<lane-C> OCUTALON_RUN_TAG=e0utiw bash ci/warm.sh down` (once, also after a failure).
- `git show 8fa1e285b:eval/results/rules-only.json > <scratch>/rules-only.old.json` and `node eval/compare.mjs --column eval/results > <scratch>/column.old.txt` (once, before any edit to the file).
- The fresh run (once, after task 1): `( <lane-C> OCUTALON_RUN_TAG=e0utrm OCUTALON_EVAL_REPORT_DIR=<scratch>/e0utrm bash eval/run.sh --rules-only main; echo "EXIT=$?" ) > <scratch>/e0utrm.log 2>&1`, with R1's arrangement. Expected: the rules-only PASS lines, `the mock received 0 request(s)`, `eval/run: all checks passed` and `EXIT=0`. Then `<lane-C> OCUTALON_RUN_TAG=e0utrm bash ci/iris.sh teardown`. Record `node eval/compare.mjs --column <scratch>/e0utrm` only if the folder holds `rules-only-held-out.json`; otherwise record the fresh `scores.incidents` and `builtAt`.
- The drift check (once). Expected: `fresh ok`.
  ```
  node -e 'const fs=require("fs");const [o,f]=process.argv.slice(1).map(p=>JSON.parse(fs.readFileSync(p,"utf8")));const N="user-turn-orders-stopped",F="user-turn-forget";const one=(r,k,n)=>r[k].filter(x=>x.case===n);for(const k of ["cases","userTurnChecks","fallbacks"]){const a=one(f,k,N);if(a.length!==1||JSON.stringify({...a[0],case:F})!==JSON.stringify(one(o,k,F)[0]))throw new Error("new entry "+k);for(const s of o[k].filter(x=>/^user-turn-/.test(x.case)))if(JSON.stringify(one(f,k,s.case)[0])!==JSON.stringify(s))throw new Error("sibling "+k+" "+s.case)}if(f.scores.userTurns.right!==0||f.scores.userTurns.total!==7)throw new Error("score");console.log("fresh ok")' <scratch>/rules-only.old.json <scratch>/e0utrm/rules-only.json
  ```
- The splice (once). Expected: `spliced`.
  ```
  node -e 'const fs=require("fs");const [o,f,out]=process.argv.slice(1);const d=JSON.parse(fs.readFileSync(o,"utf8")),r=JSON.parse(fs.readFileSync(f,"utf8")),N="user-turn-orders-stopped";for(const k of ["cases","userTurnChecks","fallbacks"]){const e=r[k].find(x=>x.case===N);const i=d[k].findIndex(x=>x.case>N);d[k].splice(i<0?d[k].length:i,0,e)}d.scores.userTurns.total=7;fs.writeFileSync(out,JSON.stringify(d));console.log("spliced")' <scratch>/rules-only.old.json <scratch>/e0utrm/rules-only.json eval/results/rules-only.json
  ```
- The AC 4 check (loop). Expected: `identical apart from the new case` and `entries ok`.
  ```
  node -e 'const fs=require("fs");const [o,n]=process.argv.slice(1).map(p=>fs.readFileSync(p,"utf8"));const d=JSON.parse(n),N="user-turn-orders-stopped",F="user-turn-forget";for(const k of ["cases","userTurnChecks","fallbacks"]){const a=d[k].filter(x=>x.case===N),b=d[k].filter(x=>x.case===F);if(a.length!==1||JSON.stringify({...a[0],case:F})!==JSON.stringify(b[0]))throw new Error(k)}if(JSON.stringify(d.scores.userTurns)!==JSON.stringify({right:0,total:7,share:0}))throw new Error("score");console.log("entries ok");for(const k of ["cases","userTurnChecks","fallbacks"])d[k]=d[k].filter(x=>x.case!==N);d.scores.userTurns.total=6;console.log(JSON.stringify(d)===o?"identical apart from the new case":"DIFFERS")' <scratch>/rules-only.old.json eval/results/rules-only.json
  ```
- `node eval/compare.mjs --column eval/results | cmp - <scratch>/column.old.txt` (loop). Expected: no output, exit 0.
- `git diff --exit-code -- eval/results/rules-only-held-out.json README.md` (once). Expected: empty.
- `git status --short` and `git diff --name-only 8fa1e285b` (once). Expected: only the three footprint files, plus this spec and `_bmad-output/` bookkeeping.
- Lead (once): the fresh check (Rule 19) of `OcuTalon.Test.Eval.Cases`, forward and reverse, on a lane-C throwaway; then CI on the head, every workflow green.

**Mutations (Rule 19).** Apply each mutation, observe red, then revert it. After each revert, `git status --short` and `git diff --stat` must be unchanged:
- AC 1 / AC 2: change one word of `turn.text` (`lunchtime` to `noon`). Expected red:
  - `Cases.TestUserTurnCases` (`user-turn-orders-stopped: it asks the chip's exact text`);
  - the AC 1 hash.
- AC 2: delete the `eval/user-turn-orders-stopped/` folder. Expected red: `Cases.TestUserTurnCases` (the joined list is "exactly the seven named ones", and "the user-turn case is in eval/").
- AC 2: copy the folder as `eval/user-turn-zz/`, with `name` set to match. Expected red: `Cases.TestUserTurnCases` (the joined list).
- AC 2: change `recordedBy` to `written for the evaluation set (DW-1389)`. Expected red: `Cases.TestUserTurnCases` (`it says which story wrote it`).
- AC 2: drop `"nothing"` from `absentPhrases`. Expected red: `Cases.TestUserTurnCases` (`it forbids 'nothing'` and the size of 14).
- AC 2: set `heldOut` to true. Expected red: `Cases.TestUserTurnCases` (`not held out`).
- AC 3: set `kind` to `user-turns`. Expected FAIL: `test-eval-set.sh` rule `cases` (`kind is not one of the case kinds`).
- AC 3: set `name` to `user-turn-stopped`. Expected FAIL: rule `cases` (`name is not its folder's name`).
- AC 4: in a scratch copy of the committed file, leave `userTurns.total` at 6. Expected: the AC 4 check throws `score`.
- AC 4: in a scratch copy, delete the new `fallbacks` entry. Expected: the AC 4 check throws `fallbacks`.
- AC 5: in a scratch copy of `eval/results`, copy the fresh run's `rules-only.json` whole. Expected: `cmp` differs, and `readme-column` FAILs on the date. This is why the story splices.
- AC 6: lead (CI evidence).

**QA (2026-11-16, gaps only).** One gap found and closed; nothing else about the case, its pin or the splice can change unnoticed by a committed test except the deferred LOW in the frontmatter (left to code review's disposition).
- Gap: AC 1's verbatim pin was a one-time shell command, so an edit to the case's `description` (which `AssertTurnShape` checks only for non-blank) or to its layout passed every committed test. Closed in `Test.Eval.Cases.TestUserTurnCases`: the case's `case.json` must hash to `7df8056a...a9fcc` (new private helper `Sha256`), with the header bullet and method doc updated.
- mutation: `description` "asks OcuTalon for nothing" to "asks OcuTalon for nothing at all" -> red: `Cases.TestUserTurnCases` (`user-turn-orders-stopped: its case.json is the approved draft byte for byte`), the only failing assertion, so no other committed test caught it; reverted byte for byte (hash `7df8056a...a9fcc` again, `git status --short` and `git diff --stat` unchanged), then green.
- Runs (tags `e0utq*`, lane-C wrapper): warm `e0utqw` `OcuTalon.Test.Eval.Cases` passed; `test-eval-set.sh` parts 1 and 2 all 25 rules PASS; `test-boundaries.sh` and `test-class-rules.sh` all passed.
- `tests/test-summary.md` is not touched: the record is here, and a shared append would only add a cross-lane merge point.

## Review Triage Log

### 2026-11-16 - Review pass
- verdicts: 15 findings - high 0, medium 0, low 11, false 2, maybe-false 2
- findings:
  - `[low]` `[reject]` Blind 1: TestShippedChipCasesScoreTheHostReasons (Report.cls) is not extended to the new case - spec decision (Design Notes): the expectation is byte-identical to user-turn-forget's so it adds no coverage; Report.cls is in the Never list.
  - `[low]` `[reject]` Blind 2: no In.cls equivalent of TestForgetCaseRecorded - Cases.TestUserTurnCases pins the case generically; In.cls is outside the footprint and Eval.In handles user turns generically.
  - `[low]` `[reject]` Blind 3: rules-only.json is a spliced mix of two runs with no marker in the file - the chosen option (iii) of the spec, recorded in Residual risks; the release fork's re-run replaces the whole file; the fix would change the file's form (Always).
  - `[false]` `[reject]` Blind 4: recordedBy "DW-1389 follow-up" is not a ticket id - the ruling gives the case no DW id and the draft's text is approved verbatim; no bad outcome occurs.
  - `[low]` `[reject]` Blind 5: the TestUserTurnCases doc does not say why the reason-wording rules apply to a fault report - the case's description says so; a doc change is cosmetic.
  - `[maybe-false]` `[reject]` Blind 6: the absent phrase "nothing" may mark a correct reason that echoes the user's report - the phrase list is the Planner's approved text (Never: edit the draft); the score is report-only, so if true the grade would be low.
  - `[low]` `[defer]` VerGap 1: no committed test ties rules-only.json user-turn entries and total 7 to the eval/ folders - pre-existing for the six siblings, test-eval-set.sh is in Never; recorded in `deferred`.
  - `[low]` `[reject]` VerGap 2: the spec has a mutation list, not `mutation:` lines, and the Auto Run Result was blanket - each mutation and its red test is recorded per line in the Auto Run Result below; the fix would not change the spec's frozen text.
  - `[low]` `[reject]` VerGap 3: description is not pinned beyond non-blank (AssertTurnShape) - the byte hash covers it (AC 1); siblings are pinned the same way.
  - `[false]` `[reject]` VerGap 4: the fixed six-name list in Report.cls is not extended, "for the record" - same as Blind 1; the reviewer itself found it consistent with the spec, so there is no bad outcome.
  - `[low]` `[reject]` Edge 1: Report.cls chip list not extended - same as Blind 1.
  - `[low]` `[reject]` Edge 2: spliced provenance of rules-only.json - same as Blind 3.
  - `[low]` `[reject]` Edge 3: the `turns >= 8` floor message still says four - spec Never (Cases L211 stays; the floor holds at 7 user turns); pre-existing stale wording.
  - `[maybe-false]` `[reject]` Edge 4: absentPhrases do not hold "stopped" etc., so a reason that restates the fault may score right - approved text, verbatim by ruling; an RC run would show it, and if true the grade is low (report-only).
  - `[low]` `[reject]` Intent audit: reading B (the case is scored against reasons) is not exercised by any changed test, only by a later real-model run - the intent says eval-only and report-only, and the Never list forbids the files such a test would live in.

## Auto Run Result

Status: done
Blocking condition: none

Summary: added the approved case byte for byte, grew the `Test.Eval.Cases` pin from six to seven user-turn cases (header, method doc, joined list, message, `wanted`), and spliced the case's three measured entries into `eval/results/rules-only.json` (`userTurns.total` 7). README, column and every other entry untouched.

Files changed:
- `eval/user-turn-orders-stopped/case.json` (new): the approved case, SHA-256 7df8056a73b085670892302fd263426f5e2e51e851232db263b73b82212a9fcc;
- `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls`: the pin (6 to 7) and two doc comments;
- `eval/results/rules-only.json`: the case's three entries and `userTurns.total` 7;
- this spec.

Review findings: 15 findings (high 0, medium 0, low 11, false 2, maybe-false 2). Patches applied: none. Deferred: 1 (VerGap 1, low). Rejected: 14, each with its reason in the triage log. Follow-up review recommended: false (no high patched).

Verification performed:
- fresh run tag e0utrm: EXIT=0, all rules-only PASS lines, mock received 0 requests; torn down;
- `fresh ok`; AC 4: `entries ok`, `identical apart from the new case`; column unchanged (cmp clean); `git diff --exit-code` on the held-out report and README clean;
- fresh run: incidents 0 of 13, builtAt 2026-11-16T13:53:33Z (the 23.3 drift; its whole-copy column reads `date|November 16`, `main-incidents|13`; the release fork must re-commit);
- Eval.Cases and Eval.Report warm: passed; test-eval-set parts 1 and 2, test-boundaries and test-class-rules: all passed;
- mutation: `lunchtime` to `noon` -> red: Cases.TestUserTurnCases (it asks the chip's exact text) and the hash check;
- mutation: delete the case folder -> red: Cases.TestUserTurnCases (exactly the seven named ones; the case is in eval/);
- mutation: copy the folder as `eval/user-turn-zz/` -> red: Cases.TestUserTurnCases (the joined list);
- mutation: recordedBy to `(DW-1389)` -> red: Cases.TestUserTurnCases (it says which story wrote it);
- mutation: drop "nothing" from absentPhrases -> red: Cases.TestUserTurnCases (it forbids 'nothing'; those 14 phrases);
- mutation: heldOut true -> red: Cases.TestUserTurnCases (not held out);
- mutation: kind `user-turns` -> red: test-eval-set rule `cases` (kind is not one of the case kinds);
- mutation: name `user-turn-stopped` -> red: test-eval-set rule `cases` (name is not its folder's name);
- mutation: userTurns.total left at 6 in a scratch copy -> red: AC 4 check threw `score`;
- mutation: new fallbacks entry deleted in a scratch copy -> red: AC 4 check threw `fallbacks`;
- mutation: fresh rules-only.json copied whole -> red: column cmp differs and `readme-column` FAILs (date, incident count);
- each mutation was reverted byte for byte. AC 6 (CI on the head) and the lead's forward/reverse fresh check are the lead's.

Residual risks: the committed `rules-only.json` is no longer a single measured run (Nov 12 run plus three measured entries); the release fork's re-run replaces it. The stale "next paragraph" reference in Triage and the `turns >= 8` message are untouched by design.
