---
title: 'Story 32.1: The install group runs as two jobs'
type: 'chore'
created: '2026-10-21'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: [oversized]
deferred: []
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
- `docker/tests/test-ci-config.sh` L2-36 -- the header list of rules (add `groups`). L405-411 -- the matrix rule compares `ci.yml` with `bash ci/iris.sh groups`, names and order. L554-645 -- the `units` rule. L648-753 -- the `demo-path` rule, the pattern to follow: a `*_violations <tree>` function, `mk*` synthetic trees, and one wanted message per bad sample. L304-305 and L373-376 -- the matrix rule's synthetic YAML samples use the names `install, production`; leave them (see Design Notes).
- `ci/iris.sh` L307-315 `live_known`, L332-360 `cmd_group`, L39-61 `setup_tag`. Read-only. The groups need no code change: `group <name>` runs each unit as its own `bash ci/iris.sh live|shard` process, and an unknown name exits 2.
- `docker/tests/lib-live.sh` L53-84 `live_start`. Read-only. It gives each unit a fresh project `ocutalon-<label>-<tag>-<epoch>-<pid>`, takes `throwaway-iris.lock` (waits up to 240 s, then exits 75), and sets the cleanup trap. This is why the two groups are hermetic by construction.
- `docker/tests/test-install-start.sh` (`live_start t02s`), `test-install-upgrade.sh` (`live_start t02u`) and `test-audit.sh` (`live_start t04`). Read-only units. `audit` tests the installer's Audit step (AD-17), which makes it a natural member of an install group.
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

## Spec Change Log

- 2026-10-21, the lead (epic runner), unattended ruling on the plan's intent gap (a split, decide, U5): the ceiling "no IRIS job runs longer than about 10 minutes" and "until no job exceeds about 10 minutes" moved to the new sibling Story 32.3, which waits for the owner (a number stated as a target in the epics is owner-only). This story keeps the split, the measured rebalance, the record and comparison of each job's time, and the lead-owned records. "Much longer than the rest" reads as more than about 25 % over the mean of the six IRIS jobs (decided in the ruling). The AC and the `(CI)` pass line were restated; nothing else changed. Status reset to `draft` for a re-plan.

## Review Triage Log

## Design Notes

**Governing ADs.**
- AD-22: one recipe and one list; each unit in its own throwaway project; `live:demo-path` first in `browser`; image protection; skips belong to 32.2.
- AD-29: Lane B owns `ci/` (except `ci/mock/scenarios/A/`), `docker/` (except `docker/merge.cpf`) and `ci.yml`. Lane A owns `lane-a.yml`.

No acceptance criterion contradicts an AD's Rule.

**Task 0, the measurement (done at planning, read-only from the job logs).**

Run 39594299887 (a500860; all five jobs on `ocutalon-ci-b`, five IRIS stacks at once):

| Job | Runner | Units (s) | Group | Job time |
| --- | --- | --- | --- | --- |
| `install` | ci-4 | `install-start` 681, `install-upgrade` 502 | 1184 s | 20:23 |
| `production` | ci-3 | `production` 309, `production-restart` 318, `audit` 275 | 902 s | 15:42 |
| `browser` | ci-5 | `demo-path` 284, `sign-in` 276, `bundle-folder` 245 | 805 s | 14:04 |
| `shards` | ci-6 | `lane-a` 286, `lane-b` 281 | 567 s | 10:07 |
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

   "Best possible max" is a full search over every assignment that keeps the anchors (scratch calculation). The move is within about 30 s of that optimum at both loads. The optimal assignments scatter units across all six groups, which would blur Story 32.2's per-group input patterns. A second move does not help: every target group would then exceed `browser`.
2. Group order: `install-fresh` and `install-upgrade` take `install`'s place, so the order is `install-fresh install-upgrade production browser shards image`.
3. Add a `groups` rule to `test-ci-config.sh`. It pins the six names, the two anchors, non-empty groups and demo-path first. It does not pin where `audit` sits, so later rebalances need no test edit.
4. Leave the matrix rule's synthetic sample names (`install, production`) unchanged. They are the samples' own names, passed to `wf_check` as the expected list, and are not the real groups.
5. `ci.yml`'s `timeout-minutes: 40` and `OCUTALON_LIVE_DEADLINE: "1200"` stay as they are. The longest group measured after the move is 777 s.
6. The live group runs are marked `(once)`. The live scripts do not change, and an implement-loop edit can only change the grouping, which the `(loop)` static check pins.

**Rule 2 (extend, don't copy).** `groups_violations` and its sample trees extend the file's own rule pattern (`demo_path_violations` and `mkdemo`, L648-753). They are a sibling rule with no shared helper to factor out, because each rule's tree differs.

**Integration ACs.** This story introduces no service, module or shared component. It reshapes a shared list.
- Consumed-by: Story 32.2, which declares an input pattern per group and names `install-fresh` and `install-upgrade`; also the lead's CI records (Rule 21, AD-22).
- Consumes: `ci/iris.sh` and `docker/tests/lib-live.sh`, both unchanged.

**Ledger inbox.** None.

**Footprint.** `ci/units.sh` (only the group lines) and `.github/workflows/ci.yml` are in the footprint. `docker/tests/test-ci-config.sh` is a Lane B footprint extension, which the lead reports.

**Observation (no action here).** `setup_tag` gives the browser units port 52810 + n only for runners 1 to 9. Runners `ocutalon-ci-10` to `-14` get the first free port.

**Lead-owned records (the lead writes them after the real run; they are not implement tasks).**
- Rule 21, `_bmad/custom/skill-rules.md` L257. Replace the `Groups` bullet with:
  > - **Groups** (the matrix of `ci.yml`; six from Story 32.1): `install-fresh` (install-start), `install-upgrade` (install-upgrade, audit), `production` (production, production-restart), `browser` (demo-path, sign-in, bundle-folder), `shards` (lane-a, lane-b) and `image` (storage-roundtrip, build-inputs, compose-start). Story 32.1 split `install` into `install-fresh` and `install-upgrade`, and moved `audit` from `production` to `install-upgrade`, because `production` was the longest group after the split in both measured runs on the new hosts (902 s and 745 s of unit time). `image` is the IRIS checks job of AD-5. In CI each unit runs in its own project, and the web port of the browser units is 52810 plus the runner's number.

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

Live units run only in throwaway stacks through `ci/iris.sh`, one stack at a time, from `/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/epic-32`.
- Run tags: `OCUTALON_RUN_TAG=e32s1i` (implement), `e32s1q` (QA), `e32s1r` (review), `e32s1l` (lead).
- Set `OCUTALON_LOCK_OWNER='epic=32 stage=<stage>'`.
- Pass `timeout: 600000` on every call.
- Run `ci/iris.sh teardown` with the same tag at the end.
- `LOCK waiting` is normal. Epic 1 may hold the lock, and exit 75 means run the same call again.

**Commands:**
- `(loop)` `bash docker/tests/test-ci-config.sh` -- expected: `PASS matrix`, `PASS groups`, `PASS units`, `PASS demo-path`, and the last line `test-ci-config: all rules passed`; exit 0. About 5 s.
- `(loop)` `bash ci/iris.sh groups; bash ci/iris.sh list` -- expected: the six names in order, and the group lines of the I/O matrix.
- `(loop)` `bash ci/iris.sh group install; echo "rc=$?"` -- expected: `unknown group 'install'; …` and `rc=2`. No stack starts.
- `(loop)` `OCUTALON_RUN_TAG=39594299887-1-install-upgrade bash ci/iris.sh port` -- expected: `auto`, exit 0.
- `(once)` `bash ci/checks.sh` -- expected: `checks: all scripts passed`. This includes `ci-config`, `ci-changes` and `demo-path-gate`.
- `(once)` `OCUTALON_RUN_TAG=e32s1i OCUTALON_LOCK_OWNER='epic=32 stage=implement' bash ci/iris.sh group install-fresh` -- expected: `UNIT live:install-start passed`, then `GROUP install-fresh passed`; exit 0. About 3 to 4 min on the developer machine.
- `(once)` the same with `group install-upgrade` -- expected: `UNIT live:install-upgrade passed`, `UNIT live:audit passed`, `GROUP install-upgrade passed`; exit 0. About 4 to 5 min.
- `(once)` the same two again in reverse order (`install-upgrade`, then `install-fresh`), one per call -- expected: both pass.
- `(once)` After each of the four calls, `docker ps -a --format '{{.Names}}' | grep -c -- '-e32s1i-'; docker volume ls --format '{{.Name}}' | grep -c -- '-e32s1i-'` -- expected: `0` and `0`.
- `(once)` the same with `group production` -- expected: two units pass, `GROUP production passed`.
- `(once)` `OCUTALON_RUN_TAG=e32s1i bash ci/iris.sh teardown` -- expected: one `TEARDOWN tag e32s1i: …` line.
- `(CI)` For the lead only, after its push of the story's commit:
  - The run qualifies when it is the `ci` run of that commit, every `iris (<group>)` job logs `iris=true`, and no other IRIS run was using the runners at the time (`gh run list`).
  - Read each job's `started_at` and `completed_at`, its runner and its machine (`gh api repos/jbrandtmse/OcuTalon/actions/runs/<id>/jobs`). Read each unit's `UNIT … <s>s` line from the job logs.
  - Pass: each `iris (<group>)` job's time, runner and host, and the wall-clock time (`created_at` to the last `completed_at`), are recorded against run 39594299887's 20 min 25 s, and the wall-clock stays within REL-4's 35 minutes. If a job runs more than about 25 % over the mean of the six IRIS jobs, the lead opens one `[CI]` rebalance item (whole units, each move recorded). The about-10-minute ceiling is not judged here (Story 32.3).
  - The lead then writes the two lead-owned records.

**Mutations (Rule 19, one per AC; apply, observe red, revert, confirm that `git status --short` and `git diff --stat` are unchanged):**
- AC 1: drop `install-upgrade` from the `ci.yml` matrix → `FAIL matrix`. Separately, restore `IRIS_GROUPS` to `install production browser shards image`, with an `install)` case and a matching matrix → `FAIL groups` (this proves the rename is pinned, not only the agreement between the files).
- AC 2: in the real `ci/units.sh`, put `live:sign-in` before `live:demo-path` in `browser` → `FAIL groups` naming AD-22. Each synthetic sample's wanted message is checked inside the rule.
- AC 3: insert right after `live_start t02u` in `test-install-upgrade.sh` a line that dies unless a container of the tag whose name holds `t02s` exists (a dependency on install-fresh's leftovers) → `group install-upgrade` goes red in both orders, within seconds and before any stack starts, so the cleanup and the lock release run as usual. Then revert.
- AC 4 is a CI measurement: there is no local mutation, and the lead's recorded times are the evidence. AC 5 is the lead's records.

**Shared surfaces:**
- `IRIS_GROUPS` and `group_units` in `ci/units.sh`, read by `ci/iris.sh` (`groups`, `list`, `group`, `all`, `live_known`) and by `test-ci-config.sh` (`matrix`, `units`, `demo-path` and the new `groups` rule);
- the `ci.yml` matrix and the job names `iris (<group>)`, which no test asserts on (only the lead's records name them);
- `ci/iris.sh group browser`, run by `test-demo-path-gate.sh`, which is unchanged.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: Story 32.1's second criterion ("no IRIS job runs longer than about 10 minutes", with units rebalanced "until no job exceeds about 10 minutes") cannot be met by splitting and rebalancing whole units on the measured runners. Measured from the job logs (read-only): on run 39594299887 (five IRIS stacks on ocutalon-ci-b) `live:install-start` alone took 681 s, so the job that holds it takes about 12.0 min whatever the grouping (36 s before the group, 4 s after), and the best six-group partition of the 13 units is 13.6 min; on run 39594116236 attempt 2, `install-start` took 847 s alone on ocutalon-ci-c (a job of about 14.8 min), and `iris (production)` with two stacks on ocutalon-ci-b took 12 min 52 s. At the lightest load measured (two stacks on ocutalon-ci-b; 7 of the 13 unit times scaled by the measured load ratio of 1.21, inference) the floor is 10.1 min and the best six-group partition 11.3 min; only at the retired host's per-stack speed do six groups make it (9.1 min best, 9.5 min with this plan's one move). Recommended amendment (the owner's call, a product number): keep the split and the move of `live:audit` to `install-upgrade`, and restate the criterion as "no IRIS job runs much longer than the others: none more than about 25% longer than the mean of the six IRIS jobs. Each job's time, runner and host, and the run's wall-clock time, are recorded and compared with run 39594299887. If the slowest job is over about 10 minutes, the measured times go to the owner as a CI-capacity item (faster or less-loaded runner hosts), as owner decision 9 already provides for REL-4's 35 minutes." With the planned move, the slowest job is projected at about 1.20 times the mean at both measured loads (inference). Alternatives: (b) the owner changes capacity (dedicated-CPU hosts, or fewer IRIS jobs per host), which this story cannot do; (c) allow `live:install-start` to be split (its row 5, the standalone-bridge install, took 106 s on ci-b and 201 s on ci-c), which the criterion forbids. The rest of the plan is complete: only this criterion's `(CI)` pass line changes with the answer.
