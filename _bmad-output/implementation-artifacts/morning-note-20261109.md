# Morning note — run 20261026T1518Z-1-37, hold 2026-11-09 11:00Z (owner's overnight hold; account switch ~13:00Z)

## Feature and releases
- **v1.0.5 is RELEASED** (Planner): PR #9 merged; main 5de22fd3; cut from feature 2a45f8bc (rc1 7353750b).
- Feature origin head: **95aa59b0** = merge-back of v1.0.5 (module.xml versions only). Its CI runs were cancelled under the Planner's standing rule; it is **green by identity** (version bump over green trees). Morning dispatch base.
- Last head before Epic 41: **0ab2eef0** (0.17+0.18) — FULLY GREEN (ci 42574755205 attempt 2, lane-a 42574755208).
- Head after Epic 41: **2a45f8bc** — FULLY GREEN (ci 42583599821, lane-a 42583599730). 1.0.5 was cut from it.
- 09a47f3b (the Planner's rc1 record) — green.

## Merged overnight (all in 1.0.5)
5.15 (ab73a661), 30.7 (2992191c), Epic 18 18.2-18.4 (cee6c109), 39.11 DW-978 (360306f4), 32.7 flakes (2e7791d5), Epic 17 17.12/17.13 D3/D4 (19a4bae6), 0.17+0.18 README (0ab2eef0), Epic 41 part 1 41.1-41.7 (2a45f8bc). Earlier: 4.12 (a77f9a87, v1.0.4).

## Lanes at the hold
| Lane | Epic | State | Next |
|---|---|---|---|
| A | Epic 41 part 2 (41.8, 41.9, 41.12-41.14; 41.10/41.11 out) | held; 5b08b957 (= origin); 41.8 DONE and pushed (4cb52a8d, CI 42603815732/42603815693 was in progress at the hold); 41.9 spec ready-for-dev | resolve 41.8 CI first; 41.9 needs Planner rulings (PUBLIC TEXT over_cap 409 string; security note; 3 additive spine lines; owner call on the origin-system learned-save AC: keep on 41.9 / move to 41.11 / drop); DW-1015 (41.8 eval case cannot really save: give it a real session or keep it report-only wording-only) |
| B | Epic 35 (35.1 done cca91ec2 GREEN; 35.2 planned; 35.3 new) | held; local 4eef96eb (6 unpushed bookkeeping/integrate commits) | push the integrate-forward (87de75f1), resolve CI; apply 35.2 rulings (split agreed; SECURITY + AdminAtSignIn approved; DROP "Email to anyone else waits for your approval" until 22.7; the other 29 strings pending Planner review — implement all but those); then 35.3 |
| C | Epic 0 (0.15 Dockerfile move, done; head 729ec359 red on inherited DW-973/DW-774 only) | held; local f2390d0e | integrate 0.15 onto the newest green feature head (brings 32.7 fixes), checks, push, CI; re-send RELEASE TOOL hunks if they change; merge (leads 1.0.6; hunks approved); then `ci/warm.sh down`/`up` on every lane; orchestrator applies epic-dependencies.yaml :296 and :176 edits at the merge |
| D | Epic 11 part 2 (11.14 done 94391c83 GREEN, merge held) | held; 7a2cc0d5 (= origin) | 11.15 implement; then the checks-job split (release-sequence self-test to its own hosted job; Planner yes); 11.16 only after its PUBLIC TEXT is approved; 11.18 then 11.29 (after 0.15 lands). Planner reviews 11.14 hunks + 11.16 text today after 1.0.5 |

## Waiting on the Planner (today)
- 11.14 release-tool hunks (patch: scratchpad e11lead/11.14-release-tool-hunks.patch) and 11.16 PUBLIC TEXT (spec lines 339-426).
- 11.18 part A and 11.29 PUBLIC TEXT and veto items (in their specs).
- 35.2's other 29 Catalog.Core strings.

## Owner's list
- Attended architecture Update to ratify: AD-18 sentence, AD-19 note (action items ep18-ai-ad18/ad19), AD-16 S6 and AD-31 S8 (Story 35.1), AD-29 merge-back amendment (Story 11.16).
- Repository setting: add lane-a `ipm-install` and `ipm-install-p` as required checks on main (11.16's merge step refuses until then).

## Queue after these
DW-446/DW-485 release-tool story (Epic 31 re-open; DW-485 touches release/demo-host-check.sh); the CI split redo (live:security-overview production -> shards-5 with the overviewdoc pin, two clean runs, after the 1.0.5 cut); tier 3 per the lane plan.

## Standing rules still in force
- Planner rule (a) (merge without re-integrating) ENDED at the 1.0.5 cut: merges integrate forward again.
- DW-973 standing yes ENDED when 32.7 merged.
- Cancel CI on the Planner's record-only pushes and version-only merge-backs.
