---
title: 'Story 32.1: The install group runs as two jobs'
type: 'chore'
created: '2026-10-21'
status: 'done'
baseline_revision: '9d7155db1cced714f58677f6f1df2b1324bc47bb'
baseline_commit: '9d7155db1cced714f58677f6f1df2b1324bc47bb'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: [oversized]
deferred:
  - summary: >-
      The `units` and `demo-path` rules of docker/tests/test-ci-config.sh read only the stdout of their violation functions, so a tree that cannot be read can print PASS.
    evidence: |-
      `hits=$(units_violations "$root")` and `hits=$(demo_path_violations "$root")` ignore the function's exit status; a `set -u` abort in the sourced ci/units.sh leaves stdout empty. The suite stays red through other rules (matrix, recipe) in every realistic case. The new `groups` rule carries the guard.
    location: >-
      docker/tests/test-ci-config.sh (the `hits=$(units_violations ...)` and `hits=$(demo_path_violations ...)` lines)
    severity: low
---

<intent-contract>

## Intent

**Problem:** The `install` IRIS group runs `live:install-start` and `live:install-upgrade` one after the other in one job. On the last full run before the split (run 39594299887) that job took 20 min 23 s, against 10 to 16 minutes for the other four, so it alone set the run's wall-clock time of 20 min 25 s.

**Approach:** Replace `install` with two groups, `install-fresh` (`live:install-start`) and `install-upgrade` (`live:install-upgrade`), in `ci/units.sh` and in the `iris` matrix of `ci.yml`. Move one whole unit (`live:audit`, from `production` to `install-upgrade`) on the measured job logs. Pin the six groups in `docker/tests/test-ci-config.sh`. Then the lead measures the real run.

## Boundaries & Constraints

**Always:**
- `ci/units.sh` is the one list (AD-22): `IRIS_GROUPS`, `group_units` and the `ci.yml` matrix name the same six groups in the same order, and `test-ci-config.sh` proves it.
- A unit moves whole and is never split. Every move is recorded under Design Notes.
- `live:demo-path` stays the first unit of `browser`, on its own fresh throwaway (AD-22).
- Each unit still runs in its own process and its own fresh compose project (`cmd_group` → `ci/iris.sh live` → `live_start`).
- Image and runner protection keep holding. No `docker push` or registry sign-in. The base image is never pulled, cached or uploaded. Fork pull requests never reach the IRIS runner. No `docker compose config` without `--quiet`, and no `docker inspect` without `--format`.

**Never:**
- Edit `.github/workflows/lane-a.yml`, `ci/mock/scenarios/A/**`, `release/**`, `docker/merge.cpf`, `docs/**`, `src/bridge/**`, `src/cpf/**`, `eval/**` or any Lane A package. In `ci/units.sh`, edit only the `IRIS_GROUPS` line and the `group_units` cases.
- Change `ci/changes.sh` or `docker/tests/test-ci-changes.sh`. Per-group skips are Story 32.2.
- Change runner labels, `runs-on`, host assignment or any runner or repository setting (owner-only).
- Change any live script, `lib-live.sh` or `ci/iris.sh`.
- Edit `_bmad/custom/skill-rules.md` or the architecture spine. The lead writes those records.
- Push, run `gh workflow run`, or re-run a CI job. Use a dev slot or any IRIS instance other than this story's throwaways.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Six groups | `bash ci/iris.sh groups` | Six lines in this order: `install-fresh`, `install-upgrade`, `production`, `browser`, `shards`, `image` | No error expected |
| New group contents | `bash ci/iris.sh list` | `group install-fresh: live:install-start`, `group install-upgrade: live:install-upgrade live:audit`, `group production: live:production live:production-restart`; the other groups unchanged | No error expected |
| Workflow agrees | `ci.yml` matrix against `ci/iris.sh groups` | `PASS matrix` | A missing, extra or reordered name gives `FAIL matrix` with the line |
| `install` comes back | `IRIS_GROUPS` names `install`, or lacks one of the six | `FAIL groups` naming `IRIS_GROUPS` | exit 1 |
| Anchors lost or a group empty | `install-fresh` without `live:install-start`, `install-upgrade` without `live:install-upgrade`, a group listed twice, or a group with no unit | `FAIL groups` naming that violation (each synthetic sample draws its own message) | exit 1 |
| Demo path not first | `browser`'s first unit is not `live:demo-path` | `FAIL groups` naming the first unit and AD-22 | exit 1 |
| Old name called | `ci/iris.sh group install` | `unknown group 'install'; groups: install-fresh install-upgrade production browser shards image` | exit 2 |
| Hyphenated CI tag | `OCUTALON_RUN_TAG=39594299887-1-install-upgrade bash ci/iris.sh port` | The tag is accepted (prints `auto`, exit 0). Neither new tag ends the other, so one job's teardown matches none of the other's projects | No error expected |
| Each group alone, either order | No project of the tag exists; run `group install-fresh` and `group install-upgrade` one per call, in both orders | `GROUP <name> passed (<s>s)`, exit 0; afterwards no container, volume or network name contains `-<tag>-` | `LOCK busy` (exit 75) means another runner holds the throwaway lock: run the same call again |

</intent-contract>

## Code Map

- `ci/units.sh` L23-37 -- `IRIS_GROUPS` (L24) and `group_units` (L28-37; `install` L30, `production` L31). This is the only part of the file to edit; the shards, `BROWSER_UNITS` and the patterns stay as they are.
- `.github/workflows/ci.yml` L1-2 -- the header comment says "a matrix of five groups". L91-94 -- `matrix.group: [install, production, browser, shards, image]`. L97 -- `OCUTALON_RUN_TAG: <run_id>-<attempt>-<group>`. The tag stays as it is; hyphenated group names are valid tags.
- `docker/tests/test-ci-config.sh` L2-40 -- the header list of rules (add `groups`). L395-425 `rule()`, L410 -- the matrix rule compares `ci.yml` with `bash ci/iris.sh groups`, names and order (L439 `rule matrix`). L552-659 -- the `units` rule. L661-753 -- the `demo-path` rule, the pattern to follow: a `*_violations <tree>` function, `mk*` synthetic trees, and one wanted message per bad sample (L727-742). The new section goes between L753 and the test-classes section at L755. L305 and L373-376 -- the matrix rule's synthetic YAML samples use the names `install, production`; leave them (see Design Notes). L1164-1172 -- the closing lines (`test-ci-config: all rules passed`).
- `ci/iris.sh` L307-315 `live_known`, L332-360 `cmd_group`, L39-61 `setup_tag`. Read-only. The groups need no code change: `group <name>` runs each unit as its own `bash ci/iris.sh live|shard` process, and an unknown name exits 2.
- `docker/tests/lib-live.sh` L53-84 `live_start`. Read-only. It gives each unit a fresh project `ocutalon-<label>-<tag>-<epoch>-<pid>`, takes `throwaway-iris.lock` (waits up to `OCUTALON_LOCK_WAIT`, default 240 s, then prints `LOCK busy` and exits 75; L112-125), and sets the cleanup trap. This is why the two groups are hermetic by construction.
- `docker/tests/test-install-start.sh` L50 (`live_start t02s`), `test-install-upgrade.sh` L25 (`live_start t02u`) and `test-audit.sh` L22 (`live_start t04`). Read-only units. `audit` tests the installer's Audit step (AD-17), which makes it a natural member of an install group.
- `docker/tests/test-demo-path-gate.sh` -- runs `ci/iris.sh group browser` in a scratch copy. `browser` is unchanged, so this needs no edit.
- `ci/changes.sh` -- names no group (its outputs are `base`, `web`, `iris` and `reason`). Unchanged.

## Tasks & Acceptance

**Execution:**
- `ci/units.sh` -- Set `IRIS_GROUPS="install-fresh install-upgrade production browser shards image"`. Replace the `install)` case with `install-fresh) echo "live:install-start" ;;` and `install-upgrade) echo "live:install-upgrade live:audit" ;;`. Change `production)` to `echo "live:production live:production-restart"`. -- This is the split plus the one measured move. The comment "in the order of the matrix" stays true.
- `.github/workflows/ci.yml` -- Set the matrix to `group: [install-fresh, install-upgrade, production, browser, shards, image]`, and in the L1-2 comment change "five groups" to "six groups". Change nothing else. -- The `matrix` rule then holds with the new list.
- `docker/tests/test-ci-config.sh` -- Add a `groups` section after the `demo-path` block (after L753). It follows that block's pattern: `groups_violations <tree>` sources the tree's `ci/units.sh` and reports each of these:
  - the sorted `IRIS_GROUPS` is not `browser image install-fresh install-upgrade production shards`;
  - a group is listed twice;
  - a group has no unit;
  - `install-fresh` does not hold `live:install-start`;
  - `install-upgrade` does not hold `live:install-upgrade`;
  - the first unit of `browser` is not `live:demo-path` (AD-22).

  A good synthetic tree passes. Each bad sample (`install` in place of the two, a duplicate, an empty group, each lost anchor, demo-path second) draws its own message. The real tree passes. The section prints `PASS groups: …` or `FAIL groups: …` and counts into `fails`. Add a `groups` bullet to the header list. -- The matrix rule alone proves only that the two files agree, not that `install` was replaced. This pins the rename, and keeps AD-22's demo-path-first rule safe from later rebalances.

**Acceptance Criteria:**
- Given this story's `ci/units.sh` and `ci.yml`, when `bash ci/iris.sh groups`, `bash ci/iris.sh list` and `bash docker/tests/test-ci-config.sh` run, then `install` is replaced by `install-fresh` (`live:install-start`) and `install-upgrade` (`live:install-upgrade`, with `live:audit` after it), the matrix lists the same six groups in the same order, and `test-ci-config.sh` prints `PASS matrix` and `PASS groups` and ends `test-ci-config: all rules passed` (REL-4, AD-22).
- Given a `ci/units.sh` that names `install` again, loses an anchor, empties a group or puts another unit before `live:demo-path` in `browser`, when `test-ci-config.sh` runs, then it prints `FAIL groups` with that violation and exits 1.
- Given a machine with no project of the run tag, when `ci/iris.sh group install-fresh` and `ci/iris.sh group install-upgrade` run one per call, first in one order and then in the other, then each call prints `GROUP <name> passed`, exits 0 and leaves no container, volume or network of the tag. Neither group needs the other's leftovers (Rule 19).
- Given the lead's push of this story's commit, with every IRIS group running, when CI runs, then each IRIS job's time, runner and host, and the run's wall-clock time, are recorded and compared with run 39594299887; and if one group runs much longer than the rest (more than about 25 % over the mean of the six IRIS jobs), its units are rebalanced (whole units) and each move is recorded. This is the lead's `(CI)` check (see Verification). The ceiling "no IRIS job longer than about 10 minutes" is Story 32.3's, by the lead's split ruling (Design Notes).
- Given the story is done and merged, when Rule 21's CI section and AD-22's "CI as built" are read, then both name the six IRIS groups, and Rule 21 records the measured per-group times and the capacity. The lead writes both records, using the exact wording under Design Notes. They are not implement tasks.

### Review Findings

Code review of 2026-10-21 (`bmad-code-review`, tier `full-opus`; layers blind-hunter, edge-case-hunter, verification-gap and acceptance-auditor; 17 rows, 7 entries after grouping, 5 rejected; no high).

- [x] [Review][Patch] DW-48: the `units` and `demo-path` rules read only their function's stdout, so a tree that cannot be read printed `PASS units` and `PASS demo-path` (observed on this tree with `IRIS_GROUPS` renamed), and the `groups` guard was pinned by no sample. Fixed: one helper, `real_hits`, now serves the real-tree read of all three rules, and the sample `u-unread` pins it [docker/tests/test-ci-config.sh:561, 662-667, 761, 869] (blind-hunter+acceptance-auditor; low, fix-risk low)
- [x] [Review][Patch] The `groups` rule read `group_units` as one string, where `cmd_group` splits it into words. A group that prints only blanks counted as having a unit, so `cmd_group` would run nothing and print `GROUP passed`. A leading blank before `live:demo-path` failed the demo-path-first check. Fixed: both checks now split the output into words, and the samples `g-blank` (must draw "has no unit") and `g-spaced` (must stay clean) pin them [docker/tests/test-ci-config.sh:792-800, 832-833, 843, 853] (edge-case-hunter+blind-hunter; low, fix-risk low)
- [x] [Review][Patch] The `recipe` rule's header bullet and its FAIL line described only refusals and the port, not QA's group checks (`groups` order, `list` anchors, `group install` refused, the six CI tags). Both now name them [docker/tests/test-ci-config.sh:30-33, 1017] (blind-hunter+acceptance-auditor; low, fix-risk low)
- [x] [Review][Patch] AC 3's mutation line did not say what it proves about order. The plan said "red in both orders", but it was run only alone on a clean tag. Corrected under `## Verification`: how the forward order is covered is now stated, and no live run was added [spec `## Verification`, the first AC 3 line] (verification-gap+acceptance-auditor; low, fix-risk low)
- [x] [Review][Defer] Runners 10 to 14 have no fixed web port, so their browser units race for the first free port of 52800-52819 [ci/iris.sh:55] — deferred: pre-existing (from the scale-out to 12 services) and outside this story (`ci/iris.sh` is on the Never list); DW-49 `routed owner=burndown` (med, fix-risk low). The lead's Rule 21 wording "the web port of the browser units is 52810 plus the runner's number" is not yet true for those runners (blind-hunter)
- [x] [Review][Defer] The six group names are literals in both the `groups` rule and the `recipe` rule [docker/tests/test-ci-config.sh:782, 984] — deferred: DW-50 `by-design`. QA's recipe line is a deliberate, independent pin of the CLI output, and a missed edit fails closed (blind-hunter)
- [x] [Review][Defer] AC 1's "with `live:audit` after it" has no pinning test, and `g-moved` keeps a rebalanced tree green [docker/tests/test-ci-config.sh:843] — deferred: DW-51 `by-design` (Design Notes item 3). AC 1 keeps its pinning test for the names, order and anchors (verification-gap)

**Rejected:**
- `low` (blind-hunter) The `(loop)` line `bash ci/iris.sh group install` uses the real image, so a stale case would start a stack. The fix is a spec edit. On the shipped tree the call exits 2 before `setup_tag`, and the suite's recipe line covers the old name with a missing image. The containment slip is the lead's closed `protocol_violation` record.
- `low` (blind-hunter+acceptance-auditor) The Execution bullet still says "the sorted `IRIS_GROUPS`". The fix is a spec edit, and the Review Triage Log already records the change to an ordered compare. The rest of that finding is false: the expected lines end with `all rules passed`, which only prints when `recipe` passes; "one medium entry" counts the three medium rows that share one root cause; and the suffix-cut mutation does break AC 3's own `group install-fresh` call.
- `false` (edge-case-hunter) "Files changed" omits QA's recipe lines. That list covers the implement pass only (Rule 14), and the QA files paragraph documents the recipe lines.
- `false` (acceptance-auditor) A live unit ran outside the worktree. That is a closed process record, not a defect in the change, and no layer of this review ran a live unit (HEAD and the tree were checked after the layers returned).

## Spec Change Log

- 2026-10-21, the lead (epic runner), unattended ruling on the plan's intent gap (a split, decide, U5): the ceiling "no IRIS job runs longer than about 10 minutes" and "until no job exceeds about 10 minutes" moved to the new sibling Story 32.3, which waits for the owner (a number stated as a target in the epics is owner-only). This story keeps the split, the measured rebalance, the record and comparison of each job's time, and the lead-owned records. "Much longer than the rest" reads as more than about 25 % over the mean of the six IRIS jobs (decided in the ruling). The AC and the `(CI)` pass line were restated; nothing else changed. Status reset to `draft` for a re-plan.
- 2026-10-21, the lead, the `(CI)` check on run 39633794167 (commit `e73b33c`): wall-clock 19 min 21 s against 20 min 25 s; `install-upgrade` ran 1.33 times the mean of the six (19 min 18 s, ci-13 on `ocutalon-ci-c`, where four of the six IRIS jobs ran). Unattended ruling (decide): no unit moved, because the spread is host placement and on one host's unit times the groups are 1.20 times the mean with no whole-unit move that lowers the longest; the balance rule and the slowest job go to Story 32.3 (owner decision U-1). The lead-owned records are written: Rule 21's `Groups` bullet and sixth-run record, and AD-22's "CI as built" (veto item U-4).

## Review Triage Log

### 2026-10-21 -- Review pass
- verdicts: 16 findings -- high 0, medium 3, low 9, false 4, maybe-false 0
- findings:
  - `[medium]` `[patch]` (blind-hunter) A stale `install)` case in `group_units` goes undetected and "old name refused" is not pinned -- `cmd_group` decides exit 2 from `group_units`, so a leftover case keeps `group install` running; patched: `groups_violations` now reports a `group_units install` that answers, the good sample tree lost its `install)` case, and a `g-stale` sample draws the message (mutation line under AC 2).
  - `[low]` `[patch]` (blind-hunter) `groups_violations` fails open: only stdout is read, so a tree that cannot be read prints `PASS groups` -- patched: `hits=$(...) || hits="...could not read the tree..."` (mutation line under AC 2). The same shape in the older `units` and `demo-path` rules is pre-existing and recorded under `deferred:`.
  - `[low]` `[patch]` (blind-hunter) The order of `IRIS_GROUPS` is not pinned (names are compared sorted) -- the intent's matrix row says "in this order"; patched: the unsorted list is compared, a `g-order` sample draws the message (mutation line under AC 1).
  - `[low]` `[patch]` (edge-case-hunter) Same fail-open as the second finding (a missing directory or an unset `IRIS_GROUPS` under `set -u` leaves stdout empty) -- fixed by the same one-line guard.
  - `[low]` `[reject]` (edge-case-hunter) A group whose `group_units` output is only blanks passes the has-a-unit check -- contrived (`echo " "`), and the fix is a new pipeline guard, not a direct correction; a plain empty `echo ""` is caught.
  - `[false]` `[reject]` (edge-case-hunter) Removing the job `iris (install)` may orphan a required status check -- GitHub answers 403 "Upgrade to GitHub Pro or make this repository public" for branch protection and rulesets on this private repository, so no required check can name it.
  - `[medium]` `[patch]` (verification-gap) Same as the first finding (stale `install)` case ships green; the `group install` rc=2 loop line has no suite test) -- same patch.
  - `[low]` `[patch]` (verification-gap) Group order and `live:audit` placement are asserted by the spec but pinned by no test -- the order is now pinned (third finding); the audit placement stays unpinned on purpose (Design Notes item 3: later rebalances need no test edit; the lead's per-unit CI times are the safety net), closed by-design.
  - `[low]` `[reject]` (verification-gap) AC 4's pass line does not require the six `iris` jobs to succeed -- the fix is a spec edit of the lead's `(CI)` line; a red job is the lead's failed-CI path (Rule 23), so the gap is not met in practice.
  - `[low]` `[patch]` (verification-gap) `PASS groups` can print when the real-tree call crashes -- same as the second finding.
  - `[false]` `[reject]` (intent-alignment) The intent's timing outcome is not exercised by the diff's tests -- the intent assigns the measurement to the lead ("Then the lead measures the real run"; AC 4), and the config tests are not meant to model a duration.
  - `[low]` `[patch]` (intent-alignment) Order is not pinned by any rule -- same as the third finding.
  - `[low]` `[reject]` (intent-alignment) `live:audit` placement is not pinned -- same by-design closure as the eighth finding.
  - `[medium]` `[patch]` (intent-alignment) The old-name refusal is a manual check only -- same as the first finding.
  - `[false]` `[reject]` (intent-alignment) Per-group hermeticity lives in live runs the diff does not make -- the live runs were made: `install-fresh` and `install-upgrade` one per call in both orders, plus `production`, all passed, and the leftover counts of the tag were 0, 0 and 0 after each call.
  - `[false]` `[reject]` (intent-alignment) The job names change and an external setting may name `iris (install)` -- same as the sixth finding.

## Design Notes

**Governing ADs.**
- AD-22: one recipe and one list; each unit in its own throwaway project; `live:demo-path` first in `browser`; image protection; skips belong to 32.2.
- AD-29: Lane B owns `ci/` (except `ci/mock/scenarios/A/`), `docker/` (except `docker/merge.cpf`) and `ci.yml`. Lane A owns `lane-a.yml`.

No acceptance criterion contradicts an AD's Rule.

**Out of scope: Story 32.3.** By the lead's split ruling (Spec Change Log), the ceiling of about 10 minutes per IRIS job belongs to Story 32.3, which is parked for the owner. This story does not plan, build or judge it. Its rebalance test is the restated one: no IRIS job more than about 25 % over the mean of the six.

**Task 0, the measurement (done at planning, read-only from the job logs).**

Run 39594299887 (a500860; all five jobs on `ocutalon-ci-b`, five IRIS stacks at once):

| Job | Runner | Units (s) | Group | Job time |
| --- | --- | --- | --- | --- |
| `install` | ci-4 | `install-start` 681, `install-upgrade` 502 | 1184 s | 20:23 |
| `production` | ci-3 | `production` 309, `production-restart` 318, `audit` 275 | 902 s | 15:42 |
| `browser` | ci-5 | `demo-path` 284, `sign-in` 276, `bundle-folder` 245 | 805 s | 14:04 |
| `shards` | ci-6 | `lane-a` 286, `lane-b` 281 | 567 s | 10:06 |
| `image` | ci-8 | `storage-roundtrip` 308, `build-inputs` 9, `compose-start` 243 | 560 s | 10:00 |

- Job overhead: 36 s before the group (checkout, classifier, preflight, bundle build) and 4 s after it.
- `demo-path` printed `FIRST-START engine=x86_64 build=1s ready=249s`.
- Wall-clock: 20 min 25 s.

Run 39594116236, attempt 2 (12:06Z):

| Job | Runner and host | Units (s) | Job time |
| --- | --- | --- | --- |
| `install` | ci-11, on `ocutalon-ci-c`, the only IRIS stack there | `install-start` 847, `install-upgrade` 610 | 24:48 |
| `production` | ci-7, on `ocutalon-ci-b`, two stacks there | 265, 274, 206 | 12:52 |
| `image` | ci-6, on `ocutalon-ci-b` | 257, 6, 205 | 8:15 |
| `shards` | ci-2, on the retired host | 160, 172 | 5:55 |

- On ci-b, five stacks against two cost 1.21 times as long (mean over five units: 1.17, 1.16, 1.34, 1.20 and 1.19).
- At two stacks per host, ci-b was 8 to 30 % slower per unit than the retired host was in Rule 21's fifth run.
- `install-start`'s row 5 (the bridge installed alone) took 106 s on ci-b and 201 s on ci-c. Why ci-c ran slower alone is unknown (inference: other work on the host during its first hour).

**Decided in-stage.**
1. *Rebalance now, from the measured logs: one move, `live:audit` from `production` to `install-upgrade`.* After the split, `production` is the longest group at every measured load:

   | Load | `production` | Next longest | Mean of the other five |
   | --- | --- | --- | --- |
   | Run 39594299887 (five stacks on ci-b) | 902 s | 805 s (`browser`) | 623 s |
   | Two stacks on ci-b | 745 s | 666 s (`browser`, inference) | |

   `install-upgrade` is the second-shortest group. The six groups' unit times become:

   | Load | Unit times after the move (s) | Best possible max |
   | --- | --- | --- |
   | Run 39594299887 | 681, 777, 627, 805, 567, 560 | 777 s |
   | Two stacks on ci-b | 563, 621, 539, 666, 469, 468 | 636 s |

   Against the restated test (more than about 25 % over the mean of the six), the split alone leaves `production` 35 % over the mean on run 39594299887 (902 s against 669.5 s; 33 % with the 40 s job overhead) and 34 % over at two stacks (745 s against 554 s), so the criterion calls for a rebalance. After the move, the longest group (`browser`) is 20 % over the mean at both loads (19 % with the overhead). The two-stack row is partly scaled from the measured load ratio (inference).

   "Best possible max" is a full search over every assignment that keeps the anchors (scratch calculation). The move is within about 30 s of that optimum at both loads. The optimal assignments scatter units across all six groups, which would blur Story 32.2's per-group input patterns. A second move does not help: every target group would then exceed `browser`.
2. Group order: `install-fresh` and `install-upgrade` take `install`'s place, so the order is `install-fresh install-upgrade production browser shards image`.
3. Add a `groups` rule to `test-ci-config.sh`. It pins the six names, the two anchors, non-empty groups and demo-path first. It does not pin where `audit` sits, so later rebalances need no test edit.
4. Leave the matrix rule's synthetic sample names (`install, production`) unchanged. They are the samples' own names, passed to `wf_check` as the expected list, and are not the real groups.
5. `ci.yml`'s `timeout-minutes: 40` and `OCUTALON_LIVE_DEADLINE: "1200"` (per unit) stay as they are. After the move the longest group is `browser`, at 805 s on run 39594299887. The longest unit measured is `install-start`, at 847 s on ci-c.
6. The live group runs are marked `(once)`. The live scripts do not change, and an implement-loop edit can only change the grouping, which the `(loop)` static check pins.
7. *Re-plan check:* the live group calls set `OCUTALON_LOCK_WAIT=120`. Each unit takes the lock on its own, so with the default 240 s, `group install-upgrade` (two units, about 4 to 5 min of work) could wait 8 min and pass the 10-minute call cap (Rule 18 (5)). With 120 s, the worst case is about 9 min. A unit that gives up prints `LOCK busy` and exits 75. Its group then prints `UNIT … failed` and exits 1, so the call is run again.
8. The baseline stays run 39594299887, the run the intent names. Every `ci` run since then (up to 13:48Z on 2026-10-21) was a bookkeeping push that ran no IRIS job. If a later full five-group run exists when the lead pushes (Lane A's pushes run `ci.yml` too), the lead records it beside the baseline.

**Rule 2 (extend, don't copy).** `groups_violations` and its sample trees extend the file's own rule pattern (`demo_path_violations` and `mkdemo`, L661-753). They are a sibling rule with no shared helper to factor out, because each rule's tree differs.

**Integration ACs.** This story introduces no service, module or shared component. It reshapes a shared list.
- Consumed-by: Story 32.2, which declares an input pattern per group and names `install-fresh` and `install-upgrade`; also the lead's CI records (Rule 21, AD-22).
- Consumes: `ci/iris.sh` and `docker/tests/lib-live.sh`, both unchanged.

**Ledger inbox.** None.

**Footprint.** `ci/units.sh` (only the group lines) and `.github/workflows/ci.yml` are in the footprint. `docker/tests/test-ci-config.sh` is a Lane B footprint extension, which the lead reports.

**Observation (no action here).** `setup_tag` gives the browser units port 52810 + n only for runners 1 to 9. Runners `ocutalon-ci-10` to `-14` get the first free port.

**Lead-owned records (the lead writes them after the real run; they are not implement tasks).**
- Rule 21, `_bmad/custom/skill-rules.md` L257. Replace the `Groups` bullet with:
  > - **Groups** (the matrix of `ci.yml`; six from Story 32.1): `install-fresh` (install-start), `install-upgrade` (install-upgrade, audit), `production` (production, production-restart), `browser` (demo-path, sign-in, bundle-folder), `shards` (lane-a, lane-b) and `image` (storage-roundtrip, build-inputs, compose-start). Story 32.1 split `install` into `install-fresh` and `install-upgrade`, and moved `audit` from `production` to `install-upgrade`, because after the split `production` ran about 35 % over the mean of the six groups at both measured loads on the new hosts (902 s and 745 s of unit time). `image` is the IRIS checks job of AD-5. In CI each unit runs in its own project, and the web port of the browser units is 52810 plus the runner's number.

  Then append one run bullet in the form of the existing ones. It holds:
  - the `ci` run id and commit;
  - the wall-clock time, against 20 min 25 s on run 39594299887;
  - each `iris (<group>)` job's time with its runner and host;
  - each unit's time;
  - what else ran on the runners at the time.

  The capacity line (L252) is already appended.
- AD-22, the "CI as built (Story 0.7)" bullet in the spine. Replace "inside five IRIS groups (`install`, `production`, `browser`, `shards` and `image`); `image` is the IRIS checks job." with:
  > inside six IRIS groups (`install-fresh`, `install-upgrade`, `production`, `browser`, `shards` and `image`), each its own job of the `iris` matrix; `image` is the IRIS checks job [AMENDED 2026-10-21, Story 32.1: `install-fresh` and `install-upgrade` replace `install`].

  This follows Rule 20: a memlog `decision` entry, `lint_spine.py` with `"ok": true`, and a refreshed `updated:`. If the edit happens on a later day, use that day's date.

## Verification

No dev slot. This story changes CI configuration only, so no stage touches `ocutalon-slot-b` or any IRIS MCP profile.

Live units run only in throwaway stacks through `ci/iris.sh`, one stack at a time, from the root of the epic-32 worktree.
- Run tags: `OCUTALON_RUN_TAG=e32s1i` (implement), `e32s1q` (QA), `e32s1r` (review), `e32s1l` (lead).
- Set `OCUTALON_LOCK_OWNER='epic=32 stage=<stage>'` and `OCUTALON_LOCK_WAIT=120` (Design Notes, item 7).
- Pass `timeout: 600000` on every call.
- Run `ci/iris.sh teardown` with the same tag at the end.
- `LOCK waiting` is normal, because Epic 1 may hold the lock. A group call whose output has a `LOCK busy` line (the unit exits 75, the group exits 1) is run again as the same call.

**Commands:**
- `(loop)` `bash docker/tests/test-ci-config.sh` -- expected: `PASS matrix`, `PASS groups`, `PASS units`, `PASS demo-path`, and the last line `test-ci-config: all rules passed`; exit 0. About 5 s.
- `(loop)` `bash ci/iris.sh groups; bash ci/iris.sh list` -- expected: the six names in order, and the group lines of the I/O matrix.
- `(loop)` `bash ci/iris.sh group install; echo "rc=$?"` -- expected: `unknown group 'install'; …` and `rc=2`. No stack starts.
- `(loop)` `OCUTALON_RUN_TAG=39594299887-1-install-upgrade bash ci/iris.sh port` -- expected: `auto`, exit 0.
- `(once)` `bash ci/checks.sh` -- expected: `checks: all scripts passed`. This includes `ci-config`, `ci-changes` and `demo-path-gate`.
- `(once)` `OCUTALON_RUN_TAG=e32s1i OCUTALON_LOCK_OWNER='epic=32 stage=implement' OCUTALON_LOCK_WAIT=120 bash ci/iris.sh group install-fresh` -- expected: `UNIT live:install-start passed`, then `GROUP install-fresh passed`; exit 0. About 3 to 4 min on the developer machine.
- `(once)` the same with `group install-upgrade` -- expected: `UNIT live:install-upgrade passed`, `UNIT live:audit passed`, `GROUP install-upgrade passed`; exit 0. About 4 to 5 min.
- `(once)` the same two again in reverse order (`install-upgrade`, then `install-fresh`), one per call -- expected: both pass.
- `(once)` After each of the four calls, `docker ps -a --format '{{.Names}}' | grep -c -- '-e32s1i-'; docker volume ls --format '{{.Name}}' | grep -c -- '-e32s1i-'; docker network ls --format '{{.Name}}' | grep -c -- '-e32s1i-'` -- expected: `0`, `0` and `0`.
- `(once)` the same with `group production` -- expected: two units pass, `GROUP production passed`.
- `(once)` `OCUTALON_RUN_TAG=e32s1i bash ci/iris.sh teardown` -- expected: one `TEARDOWN tag e32s1i: …` line.
- `(CI)` For the lead only, after its push of the story's commit:
  - The run qualifies when it is the `ci` run of that commit, every `iris (<group>)` job logs `iris=true`, and no other IRIS run was using the runners at the time (`gh run list`).
  - Read each job's `started_at` and `completed_at`, its runner and its machine (`gh api repos/jbrandtmse/OcuTalon/actions/runs/<id>/jobs`). Read each unit's `UNIT … <s>s` line from the job logs.
  - Pass: each `iris (<group>)` job's time, runner and host, and the wall-clock time (`created_at` to the last `completed_at`), are recorded against run 39594299887's 20 min 25 s, and the wall-clock stays within REL-4's 35 minutes. If a job runs more than about 25 % over the mean of the six IRIS jobs, the lead opens one `[CI]` rebalance item (whole units, each move recorded). The about-10-minute ceiling is not judged here (Story 32.3).
  - The lead then writes the two lead-owned records.

**Mutations (Rule 19, one per AC; apply, observe red, revert, confirm that `git status --short` and `git diff --stat` are unchanged):**
- mutation: AC 1 -- drop `install-upgrade` from the `ci.yml` matrix → `FAIL matrix` (the `groups` rule stays green). (QA re-demonstrated: red, reverted, tree unchanged.)
- mutation: AC 1 -- set `IRIS_GROUPS` to `install production browser shards image` with a matching matrix → `FAIL groups` while `PASS matrix` holds (the rename is pinned, not only the agreement between the files). (QA re-demonstrated; `FAIL units` is red too in this variant, because the scripts of the two install groups are then in no group, and so is `FAIL recipe`, because `ci/iris.sh groups` then prints the old five.)
- mutation: AC 1 -- swap `install-fresh` and `install-upgrade` in `IRIS_GROUPS` and in the matrix → `FAIL groups` (the order is pinned; `matrix` stays green). (QA re-demonstrated; `FAIL recipe` is red too, because the QA recipe line pins the order that `ci/iris.sh groups` prints.)
- mutation: AC 2 -- add an `install)` case to `group_units` → `FAIL groups` ("group_units still has a case for the retired group install"). (QA re-demonstrated, before the recipe line below existed; the QA recipe line makes `FAIL recipe` red too.)
- mutation: AC 2 -- in the real `ci/units.sh`, put `live:sign-in` before `live:demo-path` in `browser` → `FAIL groups` naming AD-22. Each synthetic sample's wanted message is checked inside the rule. (QA re-demonstrated.)
- mutation: AC 2 -- rename `IRIS_GROUPS` in the real `ci/units.sh` so the rule cannot read the tree → `FAIL groups` ("could not read the tree"), never `PASS groups`. (QA re-demonstrated; `matrix` and `recipe` are red too.)
- mutation: AC 3 -- insert right after `live_start t02u` in `test-install-upgrade.sh` a line that exits 1 unless a container of the tag whose name holds `t02s` exists (a dependency on install-fresh's leftovers) → `bash ci/iris.sh live install-upgrade` (the process `group install-upgrade` runs for that unit) printed the line, released the lock and exited 1 within seconds, before any stack started; reverted, tree byte-identical. (QA re-demonstrated with tag `e32s1q`: the first call ended `LOCK busy` after 120 s because Epic 1 held the lock, and the same call again printed the line, released the lock and exited 1 after 39 s including the wait; reverted, `git status --short` and `git diff --stat` unchanged, the file identical to HEAD.) (Review: this shows that `install-upgrade`, run alone on a clean tag, goes red when it needs install-fresh's leftovers. The forward order, `install-fresh` and then the mutated `install-upgrade`, was not run with the mutation. It is covered by recorded evidence instead: the mutation's test is false whenever the tag holds no container, and the implement stage counted 0 containers, volumes and networks of the tag after every `install-fresh` call.)
- mutation: AC 1 -- (QA) pin `live:audit` in `install-upgrade` by adding a check to `groups_violations` → `FAIL groups` ("the rule flags the good tree g-moved"); the real tree still passes, so only the new sample `g-moved` turns red. It pins Design Notes item 3: a rebalance of whole units needs no edit here.
- mutation: AC 2 -- (QA) match the two anchors as substrings (`grep -q` in place of `grep -qx`) → `FAIL groups` (the sample `g-near`, whose units are `live:install-starter` and `live:install-upgrade-old`, draws neither anchor message).
- mutation: AC 2 -- (QA) a stale `install)` case in `group_units`, seen from the command line → `FAIL recipe` ("ci/iris.sh group install -> exit 1, wanted exit 2"), besides `FAIL groups`. The recipe line sets `IRIS_IMAGE=ocutalon-no-such-image:0`, so with the stale case the call ends at the preflight: no UNIT line, no lock and no container of the tag appeared.
- mutation: AC 1 -- (QA) `ci/iris.sh list` loops over the groups without the two install groups → `FAIL recipe` ("ci/iris.sh list has no group install-fresh line with live:install-start" and the install-upgrade twin).
- mutation: AC 1 -- (QA) `ci/iris.sh groups` prints the names sorted → `FAIL recipe` ("ci/iris.sh groups printed 'browser image install-fresh install-upgrade production shards '"), besides `FAIL matrix`.
- mutation: AC 3 -- (QA) a group name with an underscore (`install_fresh`, in `IRIS_GROUPS` and its case) → `FAIL recipe` (the CI tag `39594299887-1-install_fresh` is refused with exit 2 where `port` is wanted to exit 0, and `group install_fresh` exits 2 where 1 is wanted), besides `FAIL groups` and `FAIL matrix`.
- mutation: AC 3 -- (QA) `cmd_group` looks up the name with its suffix cut (`${name%%-*}`) → `FAIL recipe` ("ci/iris.sh group install-fresh -> exit 2, wanted exit 1" and the install-upgrade twin): each new name must be a known group of `group <name>`.
- mutation: DW-48 -- (review) in the real `ci/units.sh`, rename `IRIS_GROUPS` so the tree cannot be read → `FAIL units` ("the units rule could not read the tree") and `FAIL demo-path` ("the demo-path rule could not read the tree"), besides `FAIL groups`; before the review's `real_hits` patch, the same mutation printed `PASS units` and `PASS demo-path`. Reverted, tree byte-identical.
- mutation: DW-48 -- (review) `real_hits` keeps only the function's stdout (its `|| out=...` dropped) → `FAIL units` ("a tree whose ci/units.sh cannot be read passes the rule"; the sample `u-unread` has an empty `ci/units.sh`). Reverted, tree byte-identical.
- mutation: AC 2 -- (review) the has-a-unit check tests the output string (`[ -z "$(group_units "$g")" ]`) in place of the split words → `FAIL groups` (the sample `g-blank`, whose `production` prints one blank, does not draw "the group production has no unit"). Reverted, tree byte-identical.
- mutation: AC 2 -- (review) the first unit of `browser` is taken with `cut -d" " -f1` in place of the split words → `FAIL groups` ("the rule flags the good tree g-spaced": with leading blanks, which `cmd_group` skips, the first unit read as ''). Reverted, tree byte-identical.
- AC 4 is a CI measurement: there is no local mutation, and the lead's recorded times are the evidence. AC 5 is the lead's records.

**QA files (Rule 8: `test-ci-config.sh` is the `ci-config` entry of `CHECK_SCRIPTS`, so `bash ci/checks.sh` runs it; no new script was added):**
- (QA) `docker/tests/test-ci-config.sh` -- changed. In the `groups` rule: the sample `g-moved` (a rebalance that must stay clean) and the sample `g-near` (near-miss anchors must draw both anchor messages). In the `recipe` rule: `ci/iris.sh groups` prints the six names in order; `list` has the install-fresh and install-upgrade lines with their anchors; `group install` exits 2 with the new group list (with a missing base image, so a stale case never starts a stack); and, for each of the six groups, the CI tag `39594299887-1-<group>` is accepted by `port` and `group <group>` is a known group (it ends at the preflight with exit 1). These cover the I/O rows `Six groups`, `New group contents`, `Old name called` and `Hyphenated CI tag` in the suite; the live row `Each group alone, either order` stays with the four live group runs of the implement stage (the live scripts did not change since).

**Shared surfaces:**
- `IRIS_GROUPS` and `group_units` in `ci/units.sh`, read by `ci/iris.sh` (`groups`, `list`, `group`, `all`, `live_known`) and by `test-ci-config.sh` (`matrix`, `units`, `demo-path` and the new `groups` rule);
- the `ci.yml` matrix and the job names `iris (<group>)`, which no test asserts on (only the lead's records name them);
- `ci/iris.sh group browser`, run by `test-demo-path-gate.sh`, which is unchanged.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Implemented.** `install` is now two groups, `install-fresh` (`live:install-start`) and `install-upgrade` (`live:install-upgrade`, then `live:audit`, moved whole from `production`). `IRIS_GROUPS`, `group_units` and the `ci.yml` matrix name the six groups in the order `install-fresh install-upgrade production browser shards image`. A new `groups` rule in `docker/tests/test-ci-config.sh` pins the names and their order, the retired `install` case, the two anchors, non-empty groups and `live:demo-path` first in `browser`.

**Files changed.**
- `ci/units.sh` -- the `IRIS_GROUPS` line and the `group_units` cases only.
- `.github/workflows/ci.yml` -- the matrix list and "six groups" in the header comment.
- `docker/tests/test-ci-config.sh` -- the `groups` rule (`groups_violations`, `mkgroups` samples) and its header bullet.
- This spec -- `mutation:` lines, the triage log, the `deferred:` item, and the local machine path removed from `## Verification` (the `boundaries` check flagged it on the planned spec, so `bash ci/checks.sh` was red before any code change).

**Review.** Four layers reported 16 findings: high 0, medium 3, low 9, false 4. Three root causes were patched: the stale `install)` case in `group_units` (medium), the fail-open real-tree check of the new rule (low), and the unpinned order of `IRIS_GROUPS` (low). Deferred: 1 (low), the same fail-open shape in the older `units` and `demo-path` rules. Rejected: blank-only group output (contrived), the required-status-check worry (false: GitHub offers no branch protection or rulesets on this private repository), the AC 4 pass line (a spec edit; a red job is the lead's failed-CI path), the timing and hermeticity readings (false: the lead measures the run; the live runs were made), and the `live:audit` placement (by design, Design Notes item 3). Follow-up review recommended: false (one medium entry patched, no high).

**Verification performed.**
- `bash docker/tests/test-ci-config.sh`: `PASS matrix`, `PASS groups`, `PASS units`, `PASS demo-path`, `test-ci-config: all rules passed`.
- `bash ci/iris.sh groups` and `list`: the six names in order and the group lines of the I/O matrix. `group install`: `unknown group 'install'; ...`, rc 2. `OCUTALON_RUN_TAG=39594299887-1-install-upgrade bash ci/iris.sh port`: `auto`, rc 0.
- `bash ci/checks.sh`: `checks: all scripts passed`.
- Live groups, tag `e32s1i`, one per call: `install-fresh` passed (198 s), `install-upgrade` passed (270 s: 173 s + `audit` 97 s); then in reverse order `install-upgrade` passed (348 s: 243 s + 105 s) and `install-fresh` passed (212 s); `production` passed (203 s: 84 s + 119 s). The counts of containers, volumes and networks holding `-e32s1i-` were 0, 0 and 0 after each call, and `teardown` printed `TEARDOWN tag e32s1i: 0 project(s) removed, 0 leftover ...`. These are ARM developer-machine times, not the runner's.
- Mutations (the lines under `## Verification`): each went red and was reverted with the tree byte-identical.
- Matrix Test Audit: every I/O row is covered. `Six groups` by the `groups` rule and the `groups` loop line; `New group contents` by the `list` loop line (the `audit` placement is unpinned by design); `Workflow agrees`, `install comes back`, `Anchors lost or a group empty` and `Demo path not first` by the `matrix` and `groups` rules and their samples; `Old name called` and `Hyphenated CI tag` by their loop lines (the first also by the stale-case check); `Each group alone, either order` by the four live group runs.

**Residual risks and notes.**
- AC 4 (the real run's per-job times and wall-clock) and AC 5 (the two records) are the lead's.
- Epic 1 held the throwaway lock during the reverse-order runs: two `install-upgrade` calls ended `LOCK busy` (every unit exit 75, group exit 1) and the third passed, as the Verification section expects.
- Containment note: the verification-gap layer, trying a mutation in a scratch copy outside the worktree, ran `ci/iris.sh group install` there; with its stale `install)` case that began `live:install-start` and was cut short by `head`. Afterwards no process, container, volume, network or lock remained, `HEAD` and the worktree were unchanged, and no subagent committed or pushed.
- The plan pass (re-plan, cycle iteration 2) kept the intent word for word and the first plan's decisions; the baseline `test-ci-config.sh` passed on the unchanged tree.
