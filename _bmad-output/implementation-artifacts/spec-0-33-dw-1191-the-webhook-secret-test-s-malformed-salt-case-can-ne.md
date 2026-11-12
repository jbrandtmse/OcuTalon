---
title: 'Story 0.33: DW-1191: the webhook secret test''s malformed-salt case can never equal the real salt'
type: 'bugfix'
created: '2026-11-12'
status: 'done'
baseline_revision: '7d2891ba4bcba10d07f8824070b86bdded02ec0a'
baseline_commit: '7d2891ba4bcba10d07f8824070b86bdded02ec0a'
review_loop_iteration: 0
followup_review_recommended: false
context: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** `OcuTalon.Test.Data.Webhook` `TestMatches` builds one malformed stored value as `"x"_$Extract(salt, 2, *)_"."_digest`. When the random salt already starts with "x" (about 1 run in 64), that value is the real stored value, `Data.Webhook.Matches` rightly answers 1, and the test fails at random (DW-1191; CI run 43206845957, job 131144052048, stored value 'xrvjRiPqHbxlagA8SDES').

**Approach:** The Contest Planner's standing ruling (owner's delegation; prompts/standing-rulings-20261112.md, DW-1191: test-only, burndown) fixes it in the test only. The replacement first character is chosen the way the test's own `lastChanged` chooses its last one: a character the salt does not start with. A deterministic assertion proves the choice on a salt that starts with "x".

## Boundaries & Constraints

**Always:**
- Change only `src/ocutalon/cls/OcuTalon/Test/Data/Webhook.cls`.
- Keep every other case of `TestMatches`, and the rest of the class, as they are.
- ObjectScript source stays ASCII (Rule 14). Comments state the contract, never review history.

**Never:**
- Change product code (`OcuTalon.Data.Webhook` and the rest of `src/` outside this test class), `web/`, `ci/`, docs, README.md or GUIDE.md.
- Delete, skip or weaken any assertion.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Random salt not starting with x | the usual case | the variant is "x" + salt[2..] + "." + digest; Matches answers 0 | assertion |
| Random salt starting with x | about 1 in 64 runs | the variant is "y" + salt[2..] + "." + digest; Matches answers 0 | assertion |
| Deterministic proof | a literal salt that starts with "x" | the changed-first value differs from it in the first character only | assertion |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Test/Data/Webhook.cls`, `TestMatches` (L65-85): L73 builds `lastChanged` with `$Select($Extract(digest, 43) = "A": "B", 1: "A")`; L74's `For stored = ...` list holds the defective `"x"_$Extract(salt, 2, *)_"."_digest`.

## Tasks & Acceptance

**Execution:**
- In `TestMatches`, build `firstChanged = $Select($Extract(salt) = "x": "y", 1: "x")_$Extract(salt, 2, *)`, mirroring `lastChanged`, and use `firstChanged_"."_digest` in place of `"x"_$Extract(salt, 2, *)_"."_digest` in the `For stored = ...` list. If a small helper (for example a private class method of the test class that returns a string with its first character changed) is clearer, both the list and the proof below use it (Rule 2: one place for the choice).
- Add the deterministic proof: for a literal salt that starts with "x" (for example `"xAbCdEfGhIjKlMnOpQrStU"`, 22 characters), the changed-first value differs from it, has the same length and the same characters from position 2 on.
- `- DW-1191:` covered by both items.

**Acceptance Criteria:**
- Given `TestMatches`, when it runs with any random salt, then the malformed-salt variant never equals the stored value and Matches answers 0 for it.
- Given a literal salt that starts with "x", when the choice is applied, then the result differs in the first character only.
- Given the diff, when inspected, then only `Test/Data/Webhook.cls` changed, and no assertion was removed or weakened.

### Review Findings

Code review 2026-11-12 (full mode; Blind Hunter, Edge Case Hunter, Verification Gap, Acceptance Auditor). 1 patch, 0 decision-needed, 0 defer, 9 rejected.

- [x] [Review][Patch] AC 1's loop entry `firstChanged_"."_digest` had no deterministic pin: reverting just that entry to the old fixed "x" left every assertion green about 63 runs in 64 (Rule 19: an AC whose pinning assertion cannot go red deterministically, MED in-story, fix-risk low: test-only, about 10 lines, the expected digest uses the same formula as `TestHashFormat`). Fixed: the stored-value cases now run over the random hash and over `xHash`, built from the canonical fixed salt `xAbCdEfGhIjKlMnOpQrStQ` (16 bytes) with a control that `Matches(xHash, secret)` is 1, and `firstChanged '= salt` moved inside that loop, so it too is deterministic. [src/ocutalon/cls/OcuTalon/Test/Data/Webhook.cls:72-86] (source: verification-gap+acceptance-auditor+blind-hunter)

Rejected:
- edge-case-hunter, assert that an "x" salt gets exactly "y": `low`, over-specifies. The spec's Design Notes say any character other than the salt's first is equally correct, and the proof asserts exactly that.
- blind-hunter, use the `lastChanged` idiom inline instead of a helper (and add a matching `LastChanged`): `false` as a defect. The spec's Execution item sanctions the helper so the list and the proof share one choice (Rule 2), and the reviewer names no harm.
- blind-hunter, the loop's message (first 20 characters) cannot tell the salt-prefixed cases apart: `low`, pre-existing diagnostics, seen only on a red run. Labelling every case adds structure. After the patch the two passes differ in their first character.
- blind-hunter, the comments describe the helper but not its history: `false`. Rule 14 keeps history in the spec. The doc comment states the contract ("never equals the value"), and the header bullet was rewritten for the patch.
- acceptance-auditor, `FirstChanged` is public, not `[ Private ]`: `low`, no harm. The spec offers private only as an example, and the name has no `Test` prefix, so the runner never runs it.
- acceptance-auditor, the Verification `git diff --name-only` line is narrower than the bookkeeping files the process writes: `low`, and the fix would edit the spec under review. AC 3's source-only condition holds.
- verification-gap, no `mutation:` line for the non-x branch: `false` under Rule 19, which asks for one mutation per AC, not per assertion. AC 2's is recorded.
- verification-gap, AC 3 has no pinning test or mutation: `false`. AC 3 is an inspection check, answered by `git diff --name-only 7d2891ba`: only the test class among source files.
- verification-gap + blind-hunter + acceptance-auditor, `firstChanged '= salt` cannot fail on its own: merged into the patch above (the assertion now runs on the fixed x salt, where the always-"x" mutation turns it red).

## Spec Change Log

- 2026-11-12 ~18:50Z (lead): spec written by the lead from the ruling (precedent: 0.28 and 0.29), no plan spawn; the fix is fully specified by the Contest Planner's standing ruling.

## Review Triage Log

### 2026-11-12 - Review pass
- verdicts: 8 findings - high 0, medium 0, low 8, false 0, maybe-false 0 (the Edge Case Hunter reported none; the Intent Alignment auditor's one divergence note is row 7)
- findings:
  - `[low]` `[patch]` Blind Hunter: the header clause calls the changed salt "malformed"; it is well formed and only wrong - reworded to "the real salt with only its first character changed, whatever that is, so that it is never the real salt" (applied).
  - `[low]` `[patch]` Blind Hunter: only the "x" branch of `FirstChanged` has a deterministic assertion - one fixed non-x literal assertion added ("zAbC..." becomes "xAbC...") (applied; class green on the warm stack).
  - `[low]` `[reject]` Blind Hunter: the loop case's failure message does not name the salt - the message shows the first 20 characters of the stored value, which are the changed salt; a label adds code for no named harm.
  - `[low]` `[reject]` Blind Hunter: add a control assertion that the real salt and digest match - `TestHashFormat` already asserts that a hash matches its secret through the same `Matches`.
  - `[low]` `[reject]` Blind Hunter: no other test uses the `"x"_$Extract(` pattern - a statement of absence, nothing to fix.
  - `[low]` `[reject]` Verification Gap: the loop entry `firstChanged_"."_digest` is not pinned deterministically, only the helper - the flake returns only if someone reverts that call site, which is unlikely; a deterministic loop case needs a hash built from a chosen salt (more test code than this fix); the spec scopes the proof to the choice.
  - `[low]` `[reject]` Intent Alignment (descriptive): `Matches` is not asserted on a value built from the literal "x" salt (reading C) - same root as the previous row; matrix row 3 asks only for the differs-in-first-character proof, which exists.
  - `[low]` `[reject]` Verification Gap: the first AC has no `mutation:` line - the fix would edit this build's spec as a defect; the limit (a random-salt assertion cannot be made red deterministically) is stated next to the mutation line instead.

## Design Notes

**Governing ADs:** AD-22 (the checks stay hermetic: the test creates its own hash and needs no fixture). AD-19 and AD-27 are named by the class header for the product side and are not touched. No AD is contradicted.

**Integration ACs (Rule 1/2):** a test-only bugfix; it introduces no service. Consumes: `OcuTalon.Data.Webhook.HashSecret` and `Matches` as they are. Consumed-by: none.

**Ledger inbox:** DW-1191 (owned by this story; addressed by both Execution items).

**Decided by the lead:** the replacement pair "x"/"y" follows the ruling's example. Any character other than the salt's first is equally correct.

## Verification

Shared surfaces: none (one test method of one test class).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands**, from the worktree root, one per call, `timeout: 600000`, each under ~3 minutes. Lane A's throwaway only (Rule 21), never a dev slot. Set these variables on EVERY call: `OCUTALON_LOCK_DIR=<lock-dir>/lane-a (the lane-A lock folder the lead names in the prompt) OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=0 stage=<stage>'`.
- (once) `OCUTALON_RUN_TAG=e0s31iw bash ci/warm.sh up`. Then (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e0s31iw bash ci/iris.sh class OcuTalon.Test.Data.Webhook`, and at the end, also after a failure, (once) `OCUTALON_RUN_TAG=e0s31iw bash ci/warm.sh down`.
- (once) `bash docker/tests/test-boundaries.sh`.
- (once) `git diff --name-only <baseline_revision>` lists only `src/ocutalon/cls/OcuTalon/Test/Data/Webhook.cls` (plus this spec).

Mutations (one per AC; record `mutation: <change> -> <test that went red>`, then revert and check that `git status --short` and `git diff --stat` are unchanged):
- AC deterministic proof: make the choice always "x" again -> the proof assertion goes red.

- mutation: `FirstChanged` made to always answer "x"_$Extract(value, 2, *) (the old defect) -> `OcuTalon.Test.Data.Webhook` TestMatches went red on the warm stack ("a salt starting with x is changed", "in its first character"); reverted, `git status --short`, `git diff --stat` and the file checksum identical, class green again on the same stack. (Recorded before the code-review patch; the patch made the loop run over a fixed x-salt hash as well, so the AC 1 mutation below is now deterministic.)
- mutation (AC 1, demonstrated by the lead after code review, lane-A warm throwaway e0s31cw): the loop entry `firstChanged_"."_digest` reverted to the old `"x"_$Extract(salt, 2, *)_"."_digest` -> `OcuTalon.Test.Data.Webhook` TestMatches red on the xHash pass ("'xAbCdEfGhIjKlMnOpQrS' is not a stored value of the secret"); reverted (file checksum and `git status --short` identical), the class green again; the patched class green before the mutation; throwaway torn down.

## Auto Run Result

Status: done
Blocking condition: none

- Summary: `OcuTalon.Test.Data.Webhook` `TestMatches` no longer builds its malformed-salt value with a fixed "x"; a private-by-use class method `FirstChanged` returns the value with its first character replaced by one it does not start with ("y" for "x", else "x"). The loop uses `firstChanged_"."_digest`. Deterministic proof: a literal salt starting with "x" gives a different value of the same length that differs in the first character only; a non-x literal gets an "x". No product code changed.
- Files changed: `src/ocutalon/cls/OcuTalon/Test/Data/Webhook.cls` (the helper, the loop entry, six added assertions, one header line); this spec.
- Review: 2 patches applied (header wording; a non-x literal assertion), 0 deferred, 6 findings rejected with reasons in the triage log (the Edge Case Hunter reported none).
- Follow-up review recommended: false (patched low findings only).
- Verification: lane-A warm throwaway `e0s31iw`: `ci/iris.sh class OcuTalon.Test.Data.Webhook` passed before review, red under the mutation, green after the revert (identical tree and checksum), and green again after the review patches; `bash docker/tests/test-boundaries.sh` passed; `git diff --name-only` lists the test class and this spec only; no non-ASCII bytes. The warm stack is down (torn down, no container left).
- Residual risks: the loop entry itself (the use of `FirstChanged`) is pinned by the random salt only; reverting that one line would bring the 1-in-64 flake back (rejected as low, see the triage log).
