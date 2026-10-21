---
title: 'Story 32.3: Every IRIS job finishes in about ten minutes'
type: 'chore'
created: '2026-10-21'
status: 'done'
baseline_revision: '6960adbc00836172cde1d870de601bf12448bbca'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** On the first six-group run, the slowest IRIS job ran 1.33 times the mean of the six (19 min 18 s). But four of the six jobs ran on `ocutalon-ci-c`, where a unit takes about 1.4 to 2 times as long as on `ocutalon-ci-b`, and nothing on record separates the grouping from the host. Separately, on runners `ocutalon-ci-10` to `-14` the browser units probe for the first free web port, and two browser jobs on `ocutalon-ci-c` can both pick it (DW-49).

**Approach:**
- Judge the balance rule on the grouping: each group's unit time on one host, normalized per host from the measured runs (Design Notes, "The method"). Move whole units only where that lowers the longest group on every measured dataset. None does today, so `ci/units.sh` keeps its six groups.
- In `setup_tag`, give runners 10 to 19 the fixed ports 52809 down to 52800. Runners 0 to 9 and every developer machine stay exactly as they are.
- The lead's push changes `ci/`, so it runs every group. The lead records each job's time, runner and host, re-judges the rule on that run, and files the host gap and any job over about 10 minutes as the owner's CI-capacity item.

## Boundaries & Constraints

**Always:**
- **The port mapping (DW-49).** Take n, the number at the end of `RUNNER_NAME`:
  - n from 0 to 9: port 52810 + n, as today;
  - n from 10 to 19: port 52819 - n, so 52809 down to 52800;
  - anything else (n of 20 or more, no trailing number, or no `RUNNER_NAME`, as on a developer machine): no fixed port, so `live_web_port` probes 52800-52819 as today;
  - a set `OCUTALON_TEST_WEB_PORT` always wins.

  Every fixed port is in 52800-52819, distinct across runners 1 to 19, and not in `LIVE_FORBIDDEN_PORTS`.
- **The balance rule** is judged on the grouping, with the method in Design Notes. The raw job times, runners and hosts are recorded as measured. This follows the lead's pre-ruling on host placement.
- **Units stay whole.** A unit moves between groups whole and is never split. The six groups, their order, the install anchors and `live:demo-path` first in `browser` all stay.
- **Protections from Stories 32.1 and 32.2 keep holding.** No `docker push` and no registry sign-in. No cache or upload of the base image. A fork's pull request never reaches the IRIS runner. No `docker compose config` without `--quiet`, and no `docker inspect` without `--format`.
- **Script rules.** ASCII only, bash 3.2, and both the BSD and GNU tools. No new dependency.

**Never:**
- **Lane A's paths and planning files.** Never edit `.github/workflows/lane-a.yml`, `ci/mock/scenarios/A/**`, `release/**`, `docker/merge.cpf`, `docs/**`, `src/bridge/**`, `src/cpf/**`, `eval/**`, a Lane A package, `_bmad/**`, the architecture spine or `.claude/**`.
- **Files that stay as they are.** Do not change:
  - `docker/tests/lib-live.sh` (`live_web_port`, its range and `LIVE_FORBIDDEN_PORTS`) or any live script;
  - `ci/units.sh`, `ci/changes.sh` or `.github/workflows/ci.yml` (the matrix, `runs-on`, `timeout-minutes` and `OCUTALON_LIVE_DEADLINE` among them).

  Never raise a first-start or ready limit to absorb a slow host.
- **No host choice.** Never choose a host or a runner from the repository. Runner labels, host assignment and runner settings are the owner's.
- **No push, no CI trigger, no runtime.** Do not push, run `gh workflow run` or re-run a CI job. Do not use a dev slot or any IRIS instance. This story's checks need no throwaway (Verification says how a later stage starts one, should it choose to). Do not file the CI-capacity item: the lead files it.

## I/O & Edge-Case Matrix

These rows are `ci/iris.sh port` with `OCUTALON_RUN_TAG=abc-1` and `OCUTALON_TEST_WEB_PORT` unset, unless the row says otherwise.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Runners 1 to 9 (DW-49) | `RUNNER_NAME=ocutalon-ci-1` to `ocutalon-ci-9` | `52811` to `52819`, as today | No error expected |
| Runners 10 to 19 (DW-49) | `ocutalon-ci-10`, `-12`, `-14`, `-19` | `52809`, `52807`, `52805`, `52800` | No error expected |
| Leading zeros | `ocutalon-ci-012` | `52807` (the number is read in base 10, as today) | No error expected |
| Runner 0 | `ocutalon-ci-0` | `52810`, as today | No error expected |
| No fixed port | `ocutalon-ci-20`, `ocutalon-ci-114`, `somerunner`, `ocutalon-ci-x`, or no `RUNNER_NAME` | `auto`; a browser unit then probes as today | No error expected |
| Override | `OCUTALON_TEST_WEB_PORT=52805` with `ocutalon-ci-12`, and with `ocutalon-ci-1` | `52805` | No error expected |
| One host's runners (DW-49) | Each n from 1 to 19 | 19 distinct ports, each in 52800-52819, none in `LIVE_FORBIDDEN_PORTS` | No error expected |
| The live unit | `ci/iris.sh live sign-in` with `ocutalon-ci-12` and a base image that does not exist | `PORT the web port of the browser units: 52807`, then the preflight's `FAIL` line; no stack starts | exit 1 |
| A fixed port in use | Unchanged behaviour (`test-lib-live.sh`) | `FAIL live_web_port: port <p> is in use on 127.0.0.1` | The unit fails; it never takes another port |
| The grouping | The unit times of each measured dataset, normalized per host | The longest group is at most 1.25 times the mean of the six. No move of up to three whole units lowers the longest on every dataset, so the groups stay | A run with a failed unit is not a dataset |

</intent-contract>

## Code Map

- `ci/iris.sh`
  - L10: the `port` line of the usage text (`5281<n> in CI, or auto`).
  - L21-23: the header sentence on the web port.
  - L34: `usage` prints lines 2-25. Keep the header within them, or move the range with it.
  - L39-61: `setup_tag`. The port block is L48-60: it takes n from `${RUNNER_NAME##*-}`, refuses an empty or non-digit n, and maps `10#$n` of at most 9 to 52810 + n. This is the code to extend.
  - L258-261: `cmd_port` prints `${OCUTALON_TEST_WEB_PORT:-auto}`.
  - L324: `cmd_live` prints `PORT the web port of the browser units: ...` before the preflight. The lead's CI evidence reads this line.
  - L413-414: sourced, the file defines functions and runs nothing.
- `docker/tests/test-ci-config.sh`
  - L36-39: the header's `recipe` bullet ("its web port is 52810 plus the runner's number in CI and the first free port elsewhere").
  - L1129-1144: `recipe <exit> <text> <env...> -- <args>`. It runs `env -u OCUTALON_RUN_TAG -u OCUTALON_TEST_WEB_PORT -u RUNNER_NAME ... bash ci/iris.sh` and matches the text with `grep -q`.
  - L1157-1165: the port pins. L1159 pins `auto` for `ocutalon-ci-12`, which this story changes. L1163 pins the `PORT` line of `live sign-in` on `ocutalon-ci-2`.
  - L1184-1187: each group's CI tag with no `RUNNER_NAME` gives `auto`. Unchanged.
  - L1202-1208: the `PASS recipe` and `FAIL recipe` lines.
  - L1225, L1342, L1383, L1410: subshells that source `ci/iris.sh`, so `LIVE_FORBIDDEN_PORTS` is readable there.
- Read-only facts (do not edit):
  - `docker/tests/lib-live.sh` L185-237. L188 is `LIVE_FORBIDDEN_PORTS="52773 1979 52779 8089 1990 1991 52790 52791 8090 8091"`; none of them is in 52800-52819. L191 is `port_in_use` (a TCP connect to 127.0.0.1). L197-237 is `live_web_port`: a set port must be in 52800-52819, not forbidden and free, or it fails. With no port set it probes 52800 upwards (L223) and takes the first one that is free.
  - `docker/tests/test-lib-live.sh` L183-263 pins `live_web_port` itself: the probe, the override, the refusals and "no forbidden port in the range" (L255-263).
  - The callers of `live_web_port`: `docker/tests/test-demo-path.sh` L24, `test-sign-in.sh` L26 and `test-bundle-folder.sh` L24. `test-demo-path-gate.sh` L69 stubs it.
  - `.github/workflows/ci.yml` L86-125: the `iris` job. `RUNNER_NAME` comes from the runner, and every group runs `ci/iris.sh build` and then `ci/iris.sh group`.
  - `ci/units.sh` L28-38: `group_units`. Unchanged (Design Notes, "Result").
  - Per-script first-start limits (`wait_started_ready 400`): for example `docker/tests/test-production.sh` L60 and `test-storage-roundtrip.sh` L34. Unchanged.

## Tasks & Acceptance

**Execution:**
- `ci/iris.sh`: change the following. Rationale: DW-49, so that no two runners of one host share a web port.
  - In `setup_tag`'s port block (L48-60), export `OCUTALON_TEST_WEB_PORT=$((52819 - 10#$n))` when n is from 10 to 19. Keep the branch for n up to 9, the guard that a set `OCUTALON_TEST_WEB_PORT` wins, and the refusal of an empty or non-digit n.
  - Rewrite the usage line (L10) and the header sentence (L21-23) to state the mapping: 52810 + n on runners 0 to 9, 52819 - n on runners 10 to 19, and the first free port of 52800-52819 otherwise. State it as a contract: distinct ports for runners 1 to 19, so the runners of one host never share one.
  - Keep `usage`'s line range (L34) in step with the header.
- `docker/tests/test-ci-config.sh`, the `recipe` rule: change the following. Rationale: this pins DW-49 hermetically through the command line.
  - Replace the `auto` pin of `ocutalon-ci-12` (L1159) with `^52807$`.
  - Add anchored pins (`^<port>$`) for `ocutalon-ci-9` (52819), `-10` (52809), `-14` (52805), `-19` (52800), `-012` (52807) and `-0` (52810).
  - Add `^auto$` pins for `ocutalon-ci-20`, `ocutalon-ci-114` and `ocutalon-ci-x`, and add `^52805$` for `OCUTALON_TEST_WEB_PORT=52805` with `ocutalon-ci-12`.
  - Add a pin that `live sign-in` with `ocutalon-ci-12` and the missing base image prints `PORT the web port of the browser units: 52807` and exits 1.
  - Add one check over n from 1 to 19. It runs `ci/iris.sh port` with `RUNNER_NAME=ocutalon-ci-<n>`, and adds to `recipe_fail` any port that repeats, falls outside 52800-52819 or is in `LIVE_FORBIDDEN_PORTS` (read from a subshell that sources `ci/iris.sh`).
  - Rewrite the header's `recipe` bullet (L36-39) to match. Keep the `PASS recipe` wording, or extend it to say that the ports of runners 1 to 19 are distinct.

**Acceptance Criteria:**
- **Fixed ports on runners 10 to 19 (DW-49).** Given `ci/iris.sh` with `RUNNER_NAME` ending in n from 10 to 19, when `ci/iris.sh port` runs, then it prints 52819 - n. On runners 1 to 9 it still prints 52810 + n. `bash docker/tests/test-ci-config.sh` prints `PASS recipe`.
- **No two runners share a port (DW-49).** Given the runner names `ocutalon-ci-1` to `ocutalon-ci-19`, when `ci/iris.sh port` runs for each, then the 19 ports are pairwise distinct, all in 52800-52819, and none is in `LIVE_FORBIDDEN_PORTS`. A mapping that repeats a port makes `test-ci-config.sh` print `FAIL recipe`.
- **Developer machines and overrides are unchanged.** Given no `RUNNER_NAME`, a runner name with no trailing number, or a number of 20 or more, when `ci/iris.sh port` runs, then it prints `auto`, and `live_web_port` probes as before. Given a set `OCUTALON_TEST_WEB_PORT`, it prints that port whatever the runner. `bash docker/tests/test-lib-live.sh` passes, with that file unchanged.
- **The grouping holds the balance rule.** Given the unit times of the measured runs (Design Notes, Task 0), when each dataset's six group times are computed on one host by the method, then the longest group is at most 1.25 times the mean of the six on every dataset. No move of up to three whole units lowers the longest group on every dataset, so `git diff -- ci/units.sh` is empty and no unit is split (REL-4, AD-22).
- **Every check script passes.** Given the finished tree, when `bash ci/checks.sh` runs, then it ends `checks: all scripts passed`.
- **Real CI (the lead's check, see Verification).** Given the lead's push of this story, when CI runs, then every IRIS group runs, and every `PORT` line of an IRIS job on runners 10 to 14 shows that runner's fixed port, never `auto`. Each job's time, runner and host, and the run's wall-clock, are recorded. The balance rule is re-judged on that run by the method. If the slowest IRIS job ran over about 10 minutes, the lead files its measured times as the owner's CI-capacity item, as owner decision 9 does for REL-4's 35 minutes.

## Spec Change Log

## Review Triage Log

### 2026-10-21 — Review pass
- verdicts: 23 findings — high 0, medium 0, low 20, false 3, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind Hunter 1: the `ci/iris.sh` header says the runners of one host never share a port, but a runner of 20 or more, an unnumbered one, or none probes from 52800 and can meet a fixed port — the header now says runners 1 to 19 never share a port and that the probe can meet a fixed-port runner's port. The probe itself stays (Decided in-stage 2, the matrix row "No fixed port").
  - `[low]` `[reject]` Blind Hunter 2: the check over runners 1 to 19 omits runner 0 — by-design: AC 2 and the matrix say 1 to 19 (19 ports), no runner 0 service exists, and runner 0 is pinned to `^52810$`.
  - `[low]` `[patch]` Blind Hunter 3: the range and forbidden-port clauses of the loop have no mutation evidence — the range clause shows red in AC 1's mutation (`auto`); a mutation of the forbidden list now shows the forbidden clause red; both are recorded under `## Verification`.
  - `[false]` `[reject]` Blind Hunter 4: the spec's `## Auto Run Result` still reads `ready-for-dev` and records no green baseline — the Finalize step of this run writes that section from the verification outcomes; it is not part of the reviewed code.
  - `[low]` `[reject]` Edge Case Hunter 1: a `RUNNER_NAME` ending in a number of 19 digits or more wraps `10#$n` and can land in a fixed-port branch — no realistic runner name has it, and the `10#$n` reading is the existing one (wontfix-theoretical).
  - `[low]` `[reject]` Edge Case Hunter 2: the loop omits runner 0 — same as Blind Hunter 2, by-design.
  - `[low]` `[reject]` Edge Case Hunter 3: a probing runner (n of 20 or more, no number) can take a port that a numbered runner's fixed port needs — by-design: Decided in-stage 2 and the matrix row "No fixed port"; the hosts run services 3 to 14 and no port of the range is left over for more.
  - `[low]` `[patch]` Edge Case Hunter 4: the header's contract overstates what the mapping enforces — same root cause as Blind Hunter 1, one fix.
  - `[low]` `[reject]` Edge Case Hunter 5: Rule 21 in the skill rules still says that runners 10 to 14 probe — lead-owned record 1 of Design Notes; `_bmad/**` is outside this stage's footprint and the lead writes the amendment after its push.
  - `[low]` `[reject]` Verification Gap 1: no check passes the fixed ports 52800-52809 to the real `live_web_port` — Decided in-stage 4 makes the lead's CI run the live check; `test-lib-live.sh` pins the range's edges (52799 and 52820 refused, 52815 accepted), and a narrowed range would fail the first CI run loudly; a stubbed call would add more than a direct correction.
  - `[low]` `[patch]` Verification Gap 2: the `usage` range change (2,25 to 2,28) has no assertion — the `nosuchcommand` pin of `recipe` now wants "Needs bash 3.2 or later" (the last header line); mutation recorded.
  - `[low]` `[patch]` Verification Gap 3: the `-012` pin cannot tell base 10 from octal in the branch conditions — pins `ocutalon-ci-08` (`^52818$`) and `ocutalon-ci-019` (`^52800$`) added, both invalid octal; mutations recorded.
  - `[low]` `[patch]` Verification Gap 4: the `LIVE_FORBIDDEN_PORTS` clause cannot fail through `ci/iris.sh` — it does fail when the list gains a port of the range; shown by a mutation of the list (restored byte-identical), recorded. AC 2 names the clause, so it stays.
  - `[low]` `[reject]` Verification Gap 5: AC 4, AC 5 and AC 6 have no `mutation:` line — by-design: the spec's `## Verification` says AC 4 is a measurement (`ci/units.sh` is unchanged), AC 5 aggregates the others and AC 6 is the lead's CI evidence.
  - `[low]` `[reject]` Verification Gap 6: `-0`, `-012`, `somerunner`, no runner, `-x` and `-114` have no mutation of their own — Rule 19 asks one demonstrated mutation per AC, and AC 1 and AC 3 have theirs; the `-012` gap is closed by Verification Gap 3's pins.
  - `[low]` `[reject]` Verification Gap 7: the loop writes the range 52800-52819 as a literal instead of reading it from `lib-live.sh` — same cause as Verification Gap 1; AC 2 states the range literally and `test-lib-live.sh` pins it.
  - `[low]` `[patch]` Verification Gap 8: the spec records no run of the two scripts in both orders — run at the `(once)` pass after the last patch and recorded under `## Auto Run Result`.
  - `[low]` `[reject]` Intent Alignment 1: the matrix rows are observed at `ci/iris.sh port` and the `PORT` line, and no test calls `live_web_port` with a fixed port — same as Verification Gap 1, Decided in-stage 4.
  - `[false]` `[reject]` Intent Alignment 2: the matrix row "A fixed port in use" is delegated to `test-lib-live.sh`, which the diff does not show running — it is unchanged and passes at the `(once)` pass; recorded under `## Auto Run Result`.
  - `[low]` `[reject]` Intent Alignment 3: the grouping computation and the 1.25 threshold are not in the diff — by-design: AC 4 is a measurement; the four datasets were added up again (1.20, 1.21, 1.18, 1.18) and `ci/units.sh` has no diff (Decided in-stage 6).
  - `[low]` `[reject]` Intent Alignment 4: runners 3 to 8, 11, 13 and 15 to 18 are covered by the invariants and not by exact-value pins — by-design: the Execution list names the exact pins, and the check over 1 to 19 covers distinct, in range and not forbidden for all of them.
  - `[low]` `[reject]` Intent Alignment 5: the new `live sign-in` pin matches the `PORT` text and exit 1 but not the preflight's `FAIL` line — it has the shape of its sibling pin for `ocutalon-ci-2` (Rule 2), and exit 1 on a missing base image comes only from that preflight.
  - `[false]` `[reject]` Intent Alignment 6: the spec's `## Auto Run Result` is stale — the Finalize step rewrites it; same as Blind Hunter 4.

## Design Notes

**Governing ADs.**
- **AD-22:** `ci/iris.sh` is the one recipe, and every unit runs in its own throwaway. The six groups are the `iris` matrix. `live:demo-path` comes first in `browser`. The image protections hold. The port mapping is a detail of the recipe, and the groups do not change.
- **AD-29:** Lane B owns `ci/` (except `ci/mock/scenarios/A/`), `docker/` (except `docker/merge.cpf`) and `ci.yml`.

No acceptance criterion contradicts an AD's Rule.

**Rule 5 check: the balance rule on raw job times.** Read on raw job times, the balance rule depends on which host each job lands on, and the repository cannot choose that. On run 39633794167 the raw ratio is 1.33, while the grouping on one host is 1.21. The lead pre-ruled this case: judge the rule on the grouping, record every raw job's time, runner and host, and send the host gap and any raw job over about 10 minutes to the owner as the CI-capacity item. The lead records the pre-ruling as a veto ruling at the spec gate. This spec follows it, so it does not halt. The 35 minutes of REL-4 are untouched.

**Task 0, the balance rule (measured at planning, read-only, on HEAD `e6a372cd779674ceeb91608921fa62f9be1a1d52`).** Sources: `gh api repos/jbrandtmse/OcuTalon/actions/runs/<id>/jobs` for each job's runner and times, and the job logs for `Machine name:` (the host), the `UNIT ... passed|failed <s>s` lines and the `GROUP` line. The job logs are read with `gh run view <id> --log --job <job id>`, or, while the run is still in progress, with `gh api --allow-escape-sequences repos/jbrandtmse/OcuTalon/actions/jobs/<job id>/logs`. Every `Machine name:` matched the services map (3 to 8 on `ocutalon-ci-b`, 9 to 14 on `ocutalon-ci-c`).

1. **Run A: 39594299887** (commit `a500860`; five groups; all five jobs on `ocutalon-ci-b`, five stacks at once; per-unit times from Story 32.1's Design Notes), regrouped into the six groups:

   | Group | Units (s) | Group (s) |
   | --- | --- | --- |
   | `install-fresh` | `install-start` 681 | 681 |
   | `install-upgrade` | `install-upgrade` 502, `audit` 275 | 777 |
   | `production` | `production` 309, `production-restart` 318 | 627 |
   | `browser` | `demo-path` 284, `sign-in` 276, `bundle-folder` 245 | 805 |
   | `shards` | `lane-a` 286, `lane-b` 281 | 567 |
   | `image` | `storage-roundtrip` 308, `build-inputs` 9, `compose-start` 243 | 560 |

   The mean is 669.5 s, and the longest, `browser`, is 1.20 times it.
2. **Run B: 39633794167** (commit `e73b33c`; six groups; no other run on the runners):

   | Job | Runner, host | Job time | Units (s) |
   | --- | --- | --- | --- |
   | `install-upgrade` | ci-13, c | 19:18 (1158 s) | 718, 406 |
   | `install-fresh` | ci-14, c | 16:59 (1019 s) | 985 |
   | `production` | ci-11, c | 15:03 (903 s) | 457, 413 |
   | `image` | ci-10, c | 13:50 (830 s) | 451, 13, 331 |
   | `browser` | ci-5, b | 12:52 (772 s) | 242, 256, 246 (port 52815) |
   | `shards` | ci-4, b | 8:59 (539 s) | 244, 269 |

   The raw mean is 870 s and the raw ratio 1.33. The wall-clock was 19 min 21 s.
   - The host factors (the method below) are 1.446 for ci-c and 0.928 for ci-b.
   - Normalized, the groups are 681, 777, 601, 802, 553 and 550 s. The mean is 660.7 s and the ratio 1.21 (`browser`).
   - Job overhead (job time minus the `GROUP` line) was 26 to 34 s per job.
3. **Runs 4 and 5 of Rule 21** (39462430218 and 39523373710; the retired host, two jobs at once; every unit on one host), regrouped:
   - Run 4: 470, 562, 488, 545, 350 and 447 s. The longest is `install-upgrade`, at 1.18 times the mean.
   - Run 5: 461, 521, 456, 532, 338 and 400 s. The longest is `browser`, at 1.18 times the mean.
4. **Run C: 39657913372** (commit `b5eeb26`, Story 32.2's push, every group). It ran beside Epic 1's run 39656233766 (commit `98a1fc2`, the five old groups, started 11 min earlier). From 19:01 to about 19:14Z, `ocutalon-ci-c` held six IRIS stacks: Epic 1's `production` and `browser`, and this run's `image`, `production`, `browser` and `shards`. `ocutalon-ci-b` held three.

   | Job | Runner, host | Job time | Units (s) |
   | --- | --- | --- | --- |
   | `install-fresh` | ci-3, b | 11:16 (676 s) | 647 (port 52813) |
   | `install-upgrade` | ci-4, b | 13:33 (813 s) | 500, 283 |
   | `image` | ci-12, c | 15:12 (912 s), **failure** | `storage-roundtrip` failed 516 ("the first start did not end ready within 400 s"), `build-inputs` 15, `compose-start` failed 329 ("IRIS did not reach running with the merge applied within 240 s") |
   | `production` | ci-14, c | 17:50 (1070 s), **failure** | `production` failed 519, `production-restart` failed 496 (both first starts over 400 s) |
   | `shards` | ci-9, c | 19:21 (1161 s) | 575, 531 |
   | `browser` | ci-11, c | 25:03 (1503 s), **failure** | `demo-path` 570 (`FIRST-START ... ready=547s`), `sign-in` failed 493 (first start over 400 s), `bundle-folder` 385 |

   The run concluded failure, with a wall-clock of 25 min 6 s (19:01:07 to 19:26:13Z).

   - Epic 1's jobs on ci-c also failed on their first starts: `production` (ci-10) had `production` 485 s passed, then `production-restart` and `audit` failed; `browser` (ci-13) had `demo-path` 468 s passed (`ready=432s`), then `sign-in` and `bundle-folder` failed.
   - Its ci-b jobs passed: `install-start` 636 s, `install-upgrade` 513 s, `storage-roundtrip` 267 s, `build-inputs` 7 s, `compose-start` 209 s, `lane-a` 261 s and `lane-b` 260 s.
   - Neither run printed a `live_web_port` "in use" line, so DW-49's collision did not happen here, although two probing browser jobs (ci-11 and ci-13) ran on ci-c at once.
   - **Run C is not a dataset for the grouping**, because a failed unit's time is its time to the failure. It is evidence for the capacity item:
     - with six stacks on ci-c, `lane-a` and `lane-b` ran 2.01 and 1.89 times their run A times;
     - nine units of the two runs failed a start limit, all of them on ci-c: eight the 400 s first-start limit, and `compose-start` its 240 s merge limit;
     - Story 32.2's head `b5eeb26` concluded red for that reason, not for its code.

**The method (how the lead normalizes a run).**
1. The reference is run A's per-unit times (the table in item 1).
2. For each host h of the run, the host factor f_h is the median of t(run) / t(A) over the passed units that ran on h. `live:build-inputs` is left out, because it starts no stack.
3. A unit's normalized time is t(run) / f_h, and a group's normalized time is the sum over its units.
4. The rule holds when the longest normalized group is at most 1.25 times the mean of the six (two decimals).
5. A run with a failed unit is not a dataset. Record it, and judge on the next green full run.

Limits (inference): the method assumes that a host's load slows its units evenly. A host that ran one job is normalized by that job's units alone, so its group comes out at run A's value. The job overhead of 26 to 34 s per job is left out. Adding a constant to every group lowers the max/mean ratio, so leaving it out makes the test stricter.

**Result.**
- The grouping holds the rule on all four datasets: 1.20 (A), 1.21 (B, normalized), 1.18 (run 4) and 1.18 (run 5).
- A full search over every set of up to three whole-unit moves found none that lowers the longest group on all four datasets. It kept the anchors (`install-start`, `install-upgrade`, and `demo-path` first) and allowed no empty group.
- The best single move lowers nothing on run A. The best pair, `sign-in` to `image` with `compose-start` to `browser`, lowers the longest group on A (805 to 777 s), on B (802 to 777 s) and on run 5 (532 to 521 s), but raises it on run 4 (562 to 567 s). Its gain is within run-to-run unit variance (`compose-start` 161 to 209 s and `production-restart` 211 to 246 s on one host, runs 4 and 5).
- So no unit moves, and `ci/units.sh` stays as it is. With no move, `test-demo-path-gate.sh` (which pins `browser`'s three units, L341-343) and Rule 21's `Groups` bullet need no edit either.

**Why the slowest job is a capacity item.** No grouping brings a job under about 10 minutes on these hosts. `install-start` alone took 636 to 681 s on ci-b (runs A and C, Epic 1's run), plus about 30 s of job overhead. It took 847 s on ci-c as the only stack there (run 39594116236, attempt 2), and 985 s with four stacks (run B). A unit is never split, so a ceiling of about 10 minutes needs faster hosts, which is an owner action (owner decision U-1, option a).

**Task 0, DW-49 (measured at planning).**
1. **The port range.** `live_web_port` accepts only 52800-52819. `LIVE_FORBIDDEN_PORTS` holds none of them. Runners 1 to 9 use 52811 to 52819 (runner 0, which does not exist, would use 52810). That leaves 52800 to 52809 free of every fixed and forbidden port. `test-lib-live.sh` L255-263 pins that no forbidden port is in the range.
2. **The probe.** With no port set, `live_web_port` probes 52800 upwards and takes the first free port. It does not bind the port. Each browser script calls it right after `live_start` (for example `test-demo-path.sh` L23-24), and the port is published only later, when `live_first_start` brings the stack up after the image build. Two probing jobs on one host can therefore both pick the same port in that window, which is DW-49.
3. **The runners as measured.** `RUNNER_NAME` is `ocutalon-ci-<n>`, and the jobs API's `runner_name` is the same. Every job log's `Set up job` prints `Runner name:` and `Machine name:`. Runs B and C printed `PORT the web port of the browser units: 52815`, `52813` and `52814` on ci-5, ci-3 and ci-4, and `auto` on ci-10 to ci-14. (A shard unit prints no `PORT` line.) Measured today: `ci/iris.sh port` prints 52810, 52811 and 52819 for runners 0, 1 and 9, and `auto` for 10, 12, 14, 19, 20, `012` and no runner. The runner services of one host share its Docker engine and its 127.0.0.1 (inference from the hosts' setup, one runner user with Docker per host; it is DW-49's premise).
4. **This developer machine.** It publishes 1972 to 1976, 1990, 1991, 8090, 8091, 52773 to 52777, 52790 and 52791 (`docker ps --format`), and nothing in 52800-52819. A developer machine sets no `RUNNER_NAME`, so it keeps `auto`.
5. **Other users of the range.** Only the three browser units call `live_web_port`. Lane A's `standalone-bridge` job (`lane-a.yml`) runs on the same runners and publishes no port. No other script names 52800-52819.
6. **Baseline.** `test-ci-config.sh` passed every rule in 7 s, and `test-lib-live.sh` passed every check in 16 s, on the unchanged tree.

**Decided in-stage.**
1. **The ports count down: runner 10 gets 52809, and runner 19 gets 52800.** The ledger suggested the range 52800-52809, and this mapping uses it. Until every branch carries this story, an older recipe on runners 10 to 14 still probes 52800 upwards. A fixed port counted up from 52800 would be exactly what such a probe takes first. That probe would hold the port, and the new fixed-port unit would fail "in use". Counting down, an older probe reaches 52805 only when five lower ports are busy on that host. Reversible: one line in `setup_tag` and its pins.
2. **Runners 20 and above keep the probe.** No port in the range is left for them, and today's hosts have services 3 to 14.
3. **No new tool for the record.** The job log already records the runner (`Runner name:`), the host (`Machine name:`), each unit's time (`UNIT`) and the group's time (`GROUP`), and the jobs API records each job's times. The lead's Rule 21 bullet is the durable record, as in Story 32.1. A script that computes the method would be new surface for one check per full run.
4. **No live run in this story.** `ci/iris.sh port` is static. The path where `live_web_port` uses a set port is the one runners 1 to 9 use on every CI run (52815 in run B), and `test-lib-live.sh` pins it. The real run of the lead's push is the live check.
5. **The rule is judged at two decimals against 1.25.** "About 25 %" becomes a number that the lead can apply the same way to every run.
6. **The matrix row "The grouping" is a measurement row (implement).** No test can cover it: `ci/units.sh` does not change and the spec declines a script for the method (decision 3). The implement stage added up the four datasets of Task 0 again from the tables: the longest group over the mean is 1.20 (run A), 1.21 (run B, normalized), 1.18 (run 4) and 1.18 (run 5), and `git diff -- ci/units.sh` is empty. This is not a `matrix test audit failed`: AC 4 names the Task 0 computation and the lead's `(CI)` re-judgement as its evidence. Reversible: it changes nothing in the tree.
7. **Two extra leading-zero pins and a usage pin (review).** `ocutalon-ci-08` (52818) and `ocutalon-ci-019` (52800) are not valid octal, so they fail the base-10 reading of `setup_tag` in a way that `-012` cannot. The `nosuchcommand` pin of the `recipe` rule now wants the last line of the usage text, so a header that outgrows `usage`'s line range turns it red. Reversible: three lines of `test-ci-config.sh`.

**Rule 2 (extend, don't copy).**
- The mapping extends `setup_tag`'s existing runner-number branch (`ci/iris.sh` L48-60): the same n, the same `10#` reading, and the same `OCUTALON_TEST_WEB_PORT` export that `live_web_port` reads. There is no second helper.
- The pins extend the `recipe` rule of `test-ci-config.sh`. The check over 1 to 19 reuses `recipe`'s `env -u OCUTALON_RUN_TAG -u OCUTALON_TEST_WEB_PORT -u RUNNER_NAME` line. One way is to factor that line into a helper that both use, so that there is no second sanitizer.

**Integration ACs.** This story introduces no service, module or shared component. It changes one mapping in the recipe.
- Consumed-by:
  - the three browser units, through `OCUTALON_TEST_WEB_PORT` and `live_web_port`;
  - the `PORT` line, which the lead's CI evidence reads;
  - the lead's Rule 21 record and the owner's CI-capacity item.
- Consumes: `RUNNER_NAME` (from the runner), `live_web_port` and `LIVE_FORBIDDEN_PORTS` (`lib-live.sh`, unchanged), and `group_units` (unchanged).

**Ledger inbox.** DW-49 is addressed by the two Execution items, the first three acceptance criteria and the DW-49 rows of the matrix. Nothing is declined.

**Footprint.**
- In the footprint: `ci/iris.sh`.
- A Lane B extension, which the lead reports: `docker/tests/test-ci-config.sh`.
- `ci/units.sh`, `ci.yml` and `docker/tests/lib-live.sh` do not change.

**Lead-owned records (the lead writes them after its push; they are not implement tasks; Rule 20 needs no spine edit, because AD-22 names no port).**
1. **Rule 21, the `Groups` bullet.** Replace "The web port of the browser units is 52810 plus the runner's number on runners 1 to 9; on runners 10 to 14 they probe for a free port (DW-49, Story 32.3)." with:
   > The web port of the browser units is 52810 plus the runner's number on runners 1 to 9 and 52819 minus it on runners 10 to 19 (52809 down to 52800), so no two runners of a host share one; anywhere else, a developer machine included, they probe for the first free port of 52800-52819 (DW-49, Story 32.3).

   The bullet keeps its earlier marker, and the lead adds an `[AMENDED <date>, Story 32.3]` marker that quotes the old sentence.
2. **Rule 21, a run bullet for run C**, in the form of the sixth one:
   > **Seventh real run, Story 32.2's push beside Epic 1's run (October 21; the `ci` run of commit `b5eeb26`, run 39657913372, x64, 12 services on two hosts; Epic 1's `ci` run 39656233766 of `98a1fc2`, five groups, started 11 min earlier).** Wall-clock 25 min 6 s (19:01:07 to 19:26:13Z); concluded failure. From 19:01 to about 19:14Z `ocutalon-ci-c` held six IRIS stacks (four of this run, two of Epic 1's), and nine units of the two runs, all on ci-c, failed a start limit: eight the 400 s first-start limit (`storage-roundtrip`, `production`, `production-restart` and `sign-in` here; `production-restart`, `audit`, `sign-in` and `bundle-folder` in Epic 1's run), and `compose-start` its 240 s merge limit. Per job, with its runner and host: `install-fresh` 11 min 16 s (ci-3, ci-b), `install-upgrade` 13 min 33 s (ci-4, ci-b), `image` 15 min 12 s (ci-12, ci-c, failed), `production` 17 min 50 s (ci-14, ci-c, failed), `shards` 19 min 21 s (ci-9, ci-c), `browser` 25 min 3 s (ci-11, ci-c, failed). Per passed unit on ci-b: `install-start` 647 s, `install-upgrade` 500 s, `audit` 283 s; on ci-c: `build-inputs` 15 s, `lane-a` 575 s, `lane-b` 531 s (2.01 and 1.89 times run 39594299887's), `demo-path` 570 s (`FIRST-START engine=x86_64 build=6s ready=547s`) and `bundle-folder` 385 s. No `in use` line from `live_web_port`, although two probing browser jobs (ci-11 and Epic 1's ci-13) ran on ci-c at once.
3. **Rule 21, a run bullet for this story's push (run D).** It holds: the run id and commit; the wall-clock; each `iris (<group>)` job's time with its runner and host; each unit's time; each job's wait for a runner; what else ran on the runners; the raw max/mean ratio; and the normalized ratio by the method, with the host factors.
4. **The CI-capacity item** (owner decision U-1, option a). After the push, the lead files it with `ledger.sh new`'s positional grammar (summary, source, severity, fix-risk, footprint, evidence, status, owner, by, note), putting run D's slowest job (time, runner, host) where the evidence says `<run D>`:
   ```
   bash _bmad/scripts/ledger.sh _bmad-output/implementation-artifacts/deferred-work.md new \
     "IRIS jobs on ocutalon-ci-c run 1.4 to 2 times as long as on ocutalon-ci-b, and the job holding install-start runs over 10 minutes on either host" \
     "spec-32-3 (lead CI check)" med low out-of-footprint \
     "run 39633794167: install-upgrade 19:18 on ci-c, raw 1.33x the mean of six, the grouping on one host 1.21x; install-start 636-681 s on ci-b, 847 s alone and 985 s with four stacks on ci-c; run 39657913372: six stacks on ci-c, 9 units of two runs failed a start limit (8 the 400 s first start); <run D>" \
     decision-pending burndown lead \
     "human=CI capacity: resize, replace or cap the services of ocutalon-ci-c; a ~10 min job needs faster hosts"
   ```
   The note is 105 characters, within the grammar's 120. In this parallel run the lead sets `LEDGER_ID_COUNTER` as it does for every `new`.
   - The recommendation for the decision sheet: make `ocutalon-ci-c` as fast per stack as `ocutalon-ci-b`, then re-measure one full green run. Until then, either cap ci-c's services so that at most four IRIS stacks run there, or accept that a busy ci-c turns a correct push red.
   - Accept that the job holding `install-start` takes about 11 minutes on a ci-b class host, or choose a faster CPU class for the ceiling of about 10 minutes.
5. **Run C's red.** Story 32.2's head `b5eeb26` is red on capacity, not on code. Per Rule 23, the lead's path is a re-run of the failed jobs (lead-only) or the next green full run before the next implement.

## Verification

**Runtime targets.** No dev slot and no IRIS instance: no stage touches `ocutalon-slot-b` or any MCP profile. No stage needs a throwaway: `ci/iris.sh port` and the hermetic scripts start nothing. If a QA or review stage chooses to run a live unit, it does so only through `ci/iris.sh`, with these settings:
- the stage's tag: `OCUTALON_RUN_TAG=e32s3i` (implement), `e32s3q` (QA), `e32s3r` (review) or `e32s3l` (lead);
- `OCUTALON_LOCK_OWNER='epic=32 stage=<stage>'` and `OCUTALON_LOCK_WAIT=120`;
- one call at a time, then `ci/iris.sh teardown` with the same tag. `LOCK busy` means: run the same call again.

`ocutalon-aihub-test`, any `ocupilot*` container and `iris-community-edition` are never touched. Every command runs from the epic worktree's root, in the foreground, with `timeout: 600000`. Keep this spec free of local machine paths: `boundaries` scans it.

**Commands:**
- `(loop)` `bash docker/tests/test-ci-config.sh`. Expected: `PASS recipe` and every other rule, then `test-ci-config: all rules passed`; exit 0. About 8 s.
- `(loop)` `for n in 0 1 9 10 12 14 19 20 012; do env -u OCUTALON_TEST_WEB_PORT RUNNER_NAME=ocutalon-ci-$n OCUTALON_RUN_TAG=e32s3i bash ci/iris.sh port; done; env -u RUNNER_NAME -u OCUTALON_TEST_WEB_PORT OCUTALON_RUN_TAG=e32s3i bash ci/iris.sh port`. Expected, one per line: `52810 52811 52819 52809 52807 52805 52800 auto 52807 auto`.
- `(once)` `bash docker/tests/test-lib-live.sh`. Expected: `test-lib-live: all checks passed` (the file is unchanged). About 16 s.
- `(once)` The two scripts in both orders: `bash docker/tests/test-ci-config.sh && bash docker/tests/test-lib-live.sh`, then the reverse. Expected: both pass both times (Rule 19).
- `(once)` `bash ci/checks.sh`. Expected: `checks: all scripts passed`. About 50 s (47 s at planning, with this spec in the tree).
- `(once)` `git status --short`, and `git diff --stat -- ci/units.sh ci/changes.sh .github/workflows/ci.yml docker/tests/lib-live.sh`. Expected: only `ci/iris.sh`, `docker/tests/test-ci-config.sh` and this spec are modified, and the diff stat is empty.
- `(CI)` For the lead only: the push of this story's commit. It changes `ci/iris.sh`, so every group runs. Read the jobs with `gh api repos/jbrandtmse/OcuTalon/actions/runs/<id>/jobs` and the logs with `gh run view <id> --log -R jbrandtmse/OcuTalon`. Pass when all of these hold:
  - the `ci` run concludes `success`, and all six `iris (<group>)` jobs ran `Run the group`;
  - every `PORT the web port of the browser units:` line of a job on runner n from 10 to 14 shows 52819 - n, and on n from 3 to 9 it shows 52810 + n. No IRIS job prints `auto`. Every live unit prints this line, whatever its group. If no job with a live unit lands on runners 10 to 14, the lead records that, and checks the line on the next full run;
  - each job's time (started to completed), runner (`Runner name:`), host (`Machine name:`), wait for a runner and unit times, and the run's wall-clock, are written into the Rule 21 bullet (lead-owned record 3). A wait of more than about a minute means the runners were not all free (Story 32.1's Given, which this story keeps), and the bullet says so;
  - the normalized ratio by the method is at most 1.25. The raw ratio is recorded whatever it is;
  - if the slowest IRIS job ran over 600 s, the CI-capacity item (record 4) is filed with this run's numbers.

  Two cases are not passes:
  - A red unit whose `FAIL` is a first-start or ready limit on a host that ran more than four IRIS stacks at once is capacity evidence, not this story's defect (measured: with four stacks on ci-c every unit passed in run B; with six there, nine units of two runs failed in run C). The lead's failed-CI path applies (Rule 23), and the item cites it.
  - A normalized ratio over 1.25 on a green run re-opens the story. The run is added as a dataset, and the rework searches whole-unit moves across every dataset, as in Design Notes.

**Planned mutations (Rule 19; one per AC; the implementer applies each, observes red, reverts, and records it as `mutation: ... → ...`).**
- **AC 1:** delete the 10-to-19 branch of `setup_tag`. Wanted: `FAIL recipe` (`ocutalon-ci-12` printed `auto`, and `^52807$` was wanted).
- **AC 2:** give runner 13 alone the port 52813, which is runner 3's, and leave every pinned runner as planned. Wanted: `FAIL recipe` from the check over 1 to 19, with no pin red.
- **AC 3:** drop the guard that a set `OCUTALON_TEST_WEB_PORT` wins. Wanted: `FAIL recipe` (the override with `ocutalon-ci-12` printed 52807, and 52805 was wanted). A second mutation widens the branch to n of at most 29. Wanted: `FAIL recipe` (`ocutalon-ci-20` printed 52799, and `^auto$` was wanted).
- **AC 4** is a measurement. Its evidence is the Task 0 computation and the lead's `(CI)` re-judgement: no local mutation.
- **AC 5** aggregates the others: no local mutation of its own. **AC 6** is the lead's CI evidence.

**Mutations applied (Rule 19; implement stage, each on a saved copy of `ci/iris.sh`, restored from it with `git status --short`, `git diff --stat` and `git diff` byte-identical to before).**
- mutation: AC 1, deleted the `elif` 10-to-19 branch of `setup_tag` → `bash docker/tests/test-ci-config.sh` printed `FAIL recipe` with the pins `^52809$` (`-10`), `^52807$` (`-12` and `-012`), `^52805$` (`-14`), `^52800$` (`-19`) and the `PORT ... 52807$` line of `live sign-in` red, and the check over runners 1 to 19 naming `auto` (outside 52800-52819, and repeated).
- mutation: AC 2, gave runner 13 alone the port 52813 (runner 3's), with every pinned runner as it was → `FAIL recipe` from the check over runners 1 to 19 alone (`runner 13: port '52813' repeats an earlier runner's`), no pin red.
- mutation: AC 3, replaced the `[ -z "${OCUTALON_TEST_WEB_PORT:-}" ]` guard by `true` → `FAIL recipe` (the override with `ocutalon-ci-12` printed 52807, `^52805$` wanted, and the older override pin with `ocutalon-ci-1` red as well).
- mutation: AC 3, widened the branch to n of at most 29 → `FAIL recipe` (`ocutalon-ci-20` printed 52799, `^auto$` wanted; `-114` and `-x` stayed green).
- mutation: AC 1, base-10 reading (review pass): replaced `10#$n` by `n` in the 10-to-19 condition of `setup_tag` → `FAIL recipe` (`ocutalon-ci-019` exited 1, `^52800$` wanted); replaced it in the 0-to-9 condition → `FAIL recipe` (`ocutalon-ci-08` exited 1, `^52818$` wanted, and `-019` red too).
- mutation: AC 2, forbidden-port clause (review pass): added `52805` to `LIVE_FORBIDDEN_PORTS` in `docker/tests/lib-live.sh`, then restored it from a saved copy (`git diff` byte-identical) → `FAIL recipe` (`runner 14: port '52805' is in LIVE_FORBIDDEN_PORTS`). The clause fails only on a change to that list, because the list holds no port of 52800-52819 today.
- mutation: usage range (review pass): set `usage`'s `sed -n '2,28p'` back to `'2,25p'` → `FAIL recipe` (`ci/iris.sh nosuchcommand -> exit 2, wanted exit 2 with 'Needs bash 3.2 or later'`).

**Shared surfaces:**
- the output of `ci/iris.sh port`, and the `PORT` line of `ci/iris.sh live`. The `recipe` rule of `test-ci-config.sh` and the lead's CI evidence read them;
- `OCUTALON_TEST_WEB_PORT` as `setup_tag` exports it on runners 10 to 19. The three browser units read it through `live_web_port`;
- the `recipe` rule and its header bullet in `test-ci-config.sh`.

No list that another test counts changes size: the groups, the units, `BROWSER_UNITS`, `CHECK_SCRIPTS` and the shards are unchanged. Only one existing assertion has the old shape: the `auto` pin of `ocutalon-ci-12` (L1159). The test trees name the mapping nowhere else (`grep -rn RUNNER_NAME docker/tests ci`).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Implement and review pass (2026-10-21).**
- **Summary.** `setup_tag` gives runners 10 to 19 the fixed web port 52819 minus the runner's number (52809 down to 52800); runners 0 to 9, every other runner name and a developer machine keep their ports, and a set `OCUTALON_TEST_WEB_PORT` still wins. `ci/units.sh` is unchanged: the four datasets of Task 0 were added up again from the tables (longest group over the mean: 1.20, 1.21, 1.18, 1.18) and `git diff -- ci/units.sh` is empty. Everything the lead owns after the push (the `(CI)` run, the Rule 21 bullets and the CI-capacity item) is untouched.
- **Files changed.**
  - `ci/iris.sh`: the 10-to-19 branch in `setup_tag`; the `port` usage line and the header sentence state the mapping and its limit; `usage` prints lines 2-28.
  - `docker/tests/test-ci-config.sh`: an `iris_env` helper shared by `recipe` and the new check; pins for runners 9, 10, 12, 14, 19, 012, 0, 08 and 019, `^auto$` pins for 20, 114 and x, the override with runner 12, the `live sign-in` pin for runner 12, a check over runners 1 to 19 (distinct, within 52800-52819, none in `LIVE_FORBIDDEN_PORTS`), the usage pin and the rewritten header bullet and `PASS recipe` wording.
  - This spec: the `mutation:` lines, Decided in-stage 6 and 7, the triage log and this section.
- **Review.** Four layers reported 23 findings: high 0, medium 0, low 20, false 3. Patched (5 entries, all low): the header claim, the missing mutation evidence for the range and forbidden-port clauses, the unpinned `usage` range, the leading-zero pins that octal could not fail (`-08`, `-019`), and the unrecorded both-orders run. Rejected with a recorded reason: 16 findings (by-design 6, the live check settled by Decided in-stage 4: 3, not a defect 3, theoretical 1, lead-owned 1, Rule 19's one-mutation-per-AC scope 1, the sibling pin's shape 1). Deferred: none (`deferred: []`). Follow-up review recommended: false (no high and no medium was patched).
- **Verification performed (all in the foreground, from the worktree).**
  - `bash docker/tests/test-ci-config.sh`: `PASS recipe`, `test-ci-config: all rules passed` (about 8 s), on every pass.
  - The port loop printed `52810 52811 52819 52809 52807 52805 52800 auto 52807 auto`.
  - `bash docker/tests/test-lib-live.sh` (unchanged): `test-lib-live: all checks passed`, which covers the matrix row "A fixed port in use".
  - Both scripts in both orders: all four runs exit 0.
  - `bash ci/checks.sh`: `checks: all scripts passed` (49 s).
  - `git status --short` lists only `ci/iris.sh`, `docker/tests/test-ci-config.sh` and this spec; `git diff --stat` of `ci/units.sh`, `ci/changes.sh`, `.github/workflows/ci.yml` and `docker/tests/lib-live.sh` is empty.
  - Seven mutations were applied, observed red and reverted from saved copies with a byte-identical `git diff` (the `mutation:` lines under `## Verification`).
  - Matrix Test Audit: every row is covered by a pin or the check over runners 1 to 19 that ran and passed, except "The grouping", a measurement row (Decided in-stage 6).
- **Residual risks.**
  - The real-runner check is the lead's `(CI)` run: the `PORT` lines of runners 10 to 14 must show 52809 to 52805. No hermetic test calls `live_web_port` with a port of 52800-52809 (`test-lib-live.sh` pins the range's edges only).
  - A runner of 20 or more, or an unnumbered one, still probes from 52800 and can meet a fixed port of the same host; today's services are 3 to 14.
  - Rule 21's `Groups` bullet still says that runners 10 to 14 probe, until the lead writes lead-owned record 1.

**Planning pass (2026-10-21).** Planned and halted after planning, as the dispatch asked. The plan measured runs 39594299887, 39633794167 and 39657913372 (with Epic 1's run 39656233766 beside it) and Rule 21's runs 4 and 5. On every valid dataset the grouping holds the balance rule (1.18 to 1.21), and no set of up to three whole-unit moves lowers the longest group on all of them, so `ci/units.sh` keeps its groups. The implement work is DW-49 alone: `ci/iris.sh` (`setup_tag`) and its pins in `docker/tests/test-ci-config.sh`. Run 39657913372, Story 32.2's push, concluded failure on capacity (six IRIS stacks on `ocutalon-ci-c`, nine units of two runs over their start limits), which the lead-owned records 2, 4 and 5 cover. No code was changed, and no IRIS instance, throwaway, push or CI trigger was used.
