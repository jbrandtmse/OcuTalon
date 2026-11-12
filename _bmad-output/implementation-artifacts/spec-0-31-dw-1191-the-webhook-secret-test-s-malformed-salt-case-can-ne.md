---
title: 'Story 0.31: DW-1191: the webhook secret test''s malformed-salt case can never equal the real salt'
type: 'bugfix'
created: '2026-11-12'
status: 'ready-for-dev'
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

## Spec Change Log

- 2026-11-12 ~18:50Z (lead): spec written by the lead from the ruling (precedent: 0.28 and 0.29), no plan spawn; the fix is fully specified by the Contest Planner's standing ruling.

## Review Triage Log

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
