---
title: 'Story 22.14: SourceSet TestUpdate asserts the repoint RESET and no longer depends on the clock'
type: 'burndown'
created: '2026-11-14'
status: 'done'
baseline_revision: '42e7b3ec4'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** `Test.Mcp.SourceSet` `TestUpdate` (Story 22.5) updates the source "Jira" with a new tool and new arguments, then asserts "CreatedAt and the run fields are kept". Since Story 22.13 that update is a repoint, and `Watch.Ops.SetSource` moves `CreatedAt` to now (DW-1328, RESET, ruled). `Data.Time.NowUtc()` has whole seconds, so the stale assertion passes only when the create and the update share a second; on a loaded CI runner it fails (feature 42e7b3ec, ci 43633699261 attempt 1, shards-2; DW-1352).

**Approach:** test only. Start the row from a `CreatedAt` in the past (as the test already does for `NextDueAt`), assert the run fields are kept, and assert the repoint moves `CreatedAt` to now. No product change.

## Boundaries & Constraints

- Only `src/ocutalon/cls/OcuTalon/Test/Mcp/SourceSet.cls` `TestUpdate` changes. No product code, no other test.
- The keep branch (interval-only or letter-case-only update) stays pinned by 22.13's `TestSameTargetKeepsCreatedAt`.

</intent-contract>

## Tasks & Acceptance

- [x] `Test/Mcp/SourceSet.cls` `TestUpdate`: `Set row.CreatedAt = "2000-01-01T00:00:00Z"` beside the `NextDueAt` fixture (the unused `created` capture removed); the assertion becomes `Result` kept plus `CreatedAt ] "2020-01-01T00:00:00Z"` ("a new tool and arguments repoint the source: CreatedAt moves to now (DW-1328)").

**Acceptance Criteria:**
- Given `TestUpdate`'s repoint, when the row is checked, then the run fields are kept and `CreatedAt` is now, with and without a one-second delay before the update. Mutation: `Watch.Ops` `REPOINTRESETS` 0 → `TestUpdate` red (with `TestRepointMovesCreatedAt`).

## Spec Change Log

- 2026-11-14 (lead). Chartered by the orchestrator after the Contest Planner accepted lane D's diagnosis (~21:55Z Nov 14): 1.0.10 is cut from 42e7b3ec as it is; this fix lands right after the release's main CI green. Pipeline: the lead applies the diagnosed patch and runs the three proofs the orchestrator named (the class with and without the delay, and the `REPOINTRESETS` 0 mutation).

## Design Notes

- Cause: `Test/Mcp/SourceSet.cls:117` (the update is a repoint) and `:122` (the stale assertion) against `Watch/Ops.cls:251` (the ruled RESET), masked by `Data/Time.cls:21` (whole seconds). Not a merge interaction: no file it touches changed after f403bf66.
- Governing ADs: AD-18 (the source row; a repoint moves `CreatedAt`, Story 22.13), AD-22 (tests).
- Ledger: owns DW-1352 (the entry lives on feature; the orchestrator records `resolved-by` at the merge).

## Verification

Lane-D warm throwaway, tag `e22s14w` (new stack), lane variables as in Story 22.13's spec; one class per call.
- (once) `ci/iris.sh class OcuTalon.Test.Mcp.SourceSet` -- passed.
- (once) the same with a temporary `Hang 1.1` before the update -- passed (reverted, checksum identical).
- (once) mutation: `Watch.Ops` `REPOINTRESETS = 0` -- `TestUpdate` red ("CreatedAt moves to now … 2000-01-01T00:00:00Z") and `TestRepointMovesCreatedAt` red; reverted, checksum identical; the class green again.
- (once) `ci/iris.sh class OcuTalon.Test.Watch.Ops` -- passed. `bash docker/tests/test-class-rules.sh` -- exit 0.

**Shared surfaces:** none. Standing criterion: every test added or changed passes on a fresh environment, in either order.

mutation: REPOINTRESETS 0 → TestUpdate

## Auto Run Result

Status: done
Blocking condition: none
