---
title: 'Story 0.32: CI time budgets get a 40% margin over their green medians, and the two load timeouts get MEASURED lines (DW-1082, DW-1195)'
type: 'chore'
created: '2026-11-12'
status: 'done'
baseline_revision: 'b161e20e2cf01583116aa1df6a555696fb3e057d'
baseline_commit: 'b161e20e2cf01583116aa1df6a555696fb3e057d'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      Report-only: the iris groups' unit seconds plus the job's overhead sit under 1.4 of the 40-minute cap in six groups, and the five floors raise the worst case of the groups that hold them.
    evidence: |-
      Ten newest green jobs, 2400 s / median job: shards-10 1.33, shards-5 1.34, shards-11 1.35, shards 1.36, production 1.39, shards-2 1.39; against the largest job 1.17 (production 2050 s, shards-2 2048 s, shards-5 2019 s). Medians are 1,446 to 1,800 s.
      The worst case of a group that holds a floored unit (shards-4, shards-5 and shards-10 with the sign-in units at 1500 s, install-fresh with install-start at 1440 s, install-upgrade) can pass 2400 s, so a real hang there ends at the job's cap, not the unit's.
      Full table: evidence/0-32-task0-ci-time-budgets.md.
    location: >-
      .github/workflows/ci.yml (iris job timeout-minutes: 40), ci/units.sh (group_units)
    severity: 'medium (Planner: a job cap is a RELEASE TOOL hunk; rebalancing is Story 0.20 kind of change); changed (Planner-approved, DW-1212): the iris job cap is now 50 minutes, no rebalancing'
  - summary: >-
      Report-only: the ci `checks` job timeout (20 minutes) is 1.25 times its green median.
    evidence: |-
      962 s median, 1015 s largest of the ten newest green jobs, against 1200 s: 1.25 and 1.18.
    location: >-
      .github/workflows/ci.yml (checks, timeout-minutes: 20)
    severity: 'medium (Planner: RELEASE TOOL hunk); changed (Planner-approved, DW-1213): now 25 minutes'
  - summary: >-
      Report-only: the ci `iris` job timeout (40 minutes) is 1.33 to 1.66 times the group medians.
    evidence: |-
      See the group entry; the cap itself is the last bound of a hang and the Never list forbids raising it here.
    location: >-
      .github/workflows/ci.yml (iris, timeout-minutes: 40)
    severity: 'medium (Planner: RELEASE TOOL hunk); changed (Planner-approved, DW-1212): now 50 minutes'
  - summary: >-
      Report-only: lane-a's ipm-install (35 minutes) and ipm-install-p (35 minutes) jobs run at 1.13 and 1.21 times their green medians.
    evidence: |-
      ipm-install 1859 s median, 2098 s largest, against 2100 s: 1.13 and 1.00. ipm-install-p 1741 s median, 1893 s largest: 1.21 and 1.11. Their deadline is 1980 s, which the floors never lower. REL-4's 35 minutes is a Never-raise bound of this story.
    location: >-
      .github/workflows/lane-a.yml (ipm-install, ipm-install-p, timeout-minutes: 35)
    severity: 'medium (Planner: RELEASE TOOL hunk and REL-4); changed (Planner-approved, DW-1214): both jobs now 45 minutes as a hang backstop, REL-4 stays the 35-minute target with MEASURED and over REL-4 lines'
  - summary: >-
      Report-only: Playwright's 45 s per-test timeout is 1.27 times the slowest test of online-allowance and 1.38 times that of online-demo.
    evidence: |-
      Median over the ten newest green runs of each run's slowest test: online-allowance 35.5 s, online-demo 32.7 s, sign-in-3 31.6 s (1.42), online-session 29.4 s, answers 28.5 s. Tests that set a longer timeout of their own (demo-path 54.5 s, online-visitors 144 s) are outside the default.
    location: >-
      web/playwright.config.ts (timeout: 45_000)
    severity: 'low (Planner)'
  - summary: >-
      live:install-upgrade row 6 stays at the ruled 300 s, 1.37 times its median, below the 1.4 rule.
    evidence: |-
      Row 6's median gap is at most 219 s (an upper bound, build included); 1.4 x 219 = 307 s, rounded to 330 s. DW-1082 rules exactly 300 s, so the code follows the ruling; the next audit reads the MEASURED row 6 lines.
    location: >-
      docker/tests/test-install-upgrade.sh (row 6, wait_started_ready 300)
    severity: 'low (Planner)'
---

<intent-contract>

## Intent

**Problem:** Host load alone turns green work red. Several CI time budgets sit within 5 to 25% of what a green run takes. Two examples: the per-unit deadline is 1,200 s, and live:install-upgrade took 1,118 s and live:sign-in-3 1,184 s on green run 43227065531. The first-start wait is 400 s against `FIRST-START ... ready=355-361s`. live:install-upgrade's upgrade waits are 200 s (DW-1082). The sign-in suites hit 757 s (DW-1195). Each such red costs a rerun and delays merges.

**Approach:** Task 0 measures every unit, suite and ready-wait budget against its green median over the last 10 green CI jobs, read from the logs, and commits the audit table. Every budget with less than 40% margin is raised to at least 1.4 times its median, with these limits:
- at most about 12 budgets;
- the Contest Planner's rulings are applied as worded;
- the budgets live in repo scripts, never in the workflow.

Every changed budget prints a `MEASURED` line, so the next audit is exact.

## Boundaries & Constraints

**Always:**
- Binding rulings (Contest Planner, owner's delegation, 2026-11-12):
  - DW-1082: (a) every run prints "MEASURED row 6: the upgrade took N s to ready", pass or fail; (b) the row 6 ready budget goes from 200 s to 300 s; (c) it still fails at 300 s.
  - DW-1195: (a) every run prints "MEASURED live:sign-in suite N s"; (b) the suite timeout is at least 1.4 times the green median (about 950 s), or the suite is split. The sign-in-2 and sign-in-3 suites (755 s and 770 s) are covered the same way.
  - Audit: "Audit every CI time budget (unit, suite and ready waits) against its green median from the last 10 runs, and raise any with less than 40% margin ... A real hang still fails, just later."
- Every budget stays finite, so a real hang still fails. A raised budget never shortens, skips, deletes or tags off a test, and the job's own cap (50 minutes for the `iris` job since DW-1212) still ends a run.
- Each changed budget gets a pin in `docker/tests/test-ci-config.sh` or `docker/tests/test-lib-live.sh`, with a demonstrated mutation.
- Lane B: worktree `.worktrees/epic-0b`, branch `OCT-epic0b`. Every live call carries `<lane-B>`: `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=0b stage=<stage>'`, with an `OCUTALON_RUN_TAG` that starts with `e0bs32`. Shell code is ASCII and runs on bash 3.2.
- CI HOLD (Planner, from 18:15Z): the story may be built and committed locally. Its push waits for "CI HOLD OFF", which the lead handles.

**Never:**
- Never edit `.github/workflows/*.yml` (a job timeout change is a RELEASE TOOL hunk for the Planner) or `release/**`. [AMENDED 2026-11-12 ~18:30Z, Contest Planner approval (owner's delegation) relayed by the orchestrator: exactly four `timeout-minutes` values may change, and nothing else in any workflow: ci.yml `iris` 40 -> 50, ci.yml `checks` 20 -> 25, lane-a.yml `ipm-install` and `ipm-install-p` 35 -> 45 (DW-1212, DW-1213, DW-1214).]
- Never rename, add or remove a CI job, iris group or unit. Never move a unit between groups.
- Never raise `timeout-minutes`, REL-4's 35 minutes or CI's `OCUTALON_LIVE_DEADLINE: "1200"`.
- Never edit `_bmad/`, `irislib/` or `irissys/`.
- No IRIS MCP tool. Never SSH to, or read the memory of, a CI host or runner. Whether to read host memory is the lead's call (CI HOLD item 5); a runner or host change is the Planner's.
- Never rerun, cancel or trigger a CI run. `gh` is used read-only: `gh run list`, `gh api` GETs.
- No absolute local path, host name or runner name in any tracked file.
- Never raise a behaviour bound that an AC or NFR fixes. Examples: a notice within 60 s, a turn done within 120 s, a CSP session gone within 180 s. These are not CI budgets.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Floor raises | `ci/iris.sh live sign-in` with `OCUTALON_LIVE_DEADLINE` 1200 or unset; sign-in has a floor D | The script runs with `OCUTALON_LIVE_DEADLINE=D`; the log shows `DEADLINE live:sign-in D s` | none |
| Floor never lowers | Same unit, `OCUTALON_LIVE_DEADLINE` above D (for example the release's 1980) | The given value stays; no DEADLINE line | none |
| No floor | A unit that `unit_live_deadline` does not list | Unchanged deadline; no DEADLINE line | none |
| Wait times out | `wait_started_log` or `wait_started_ready` reaches its max | stderr shows `MEASURED wait <script>:<line> <s> s of <max> s`; the wait returns 1; the caller's FAIL/die line follows | as today |
| Row 6 slow or hung | The upgrade is not ready within 300 s | `MEASURED row 6: the upgrade took N s to ready`, then `FAIL row 6 the upgrade did not end ready within 300 s` | the unit fails |
| Suite red | A sign-in project's Playwright run fails or times out | `MEASURED live:<unit> suite budget B s` before the run and `MEASURED live:<unit> suite N s` after it, then the existing FAIL line | the unit fails |

</intent-contract>

## Code Map

- `ci/units.sh` -- the one place for the CI lists. Extend the `group_units` / `shard_areas` case-function pattern with `unit_live_deadline <unit>`: print the floor in seconds for each listed live unit (name without `live:`); return 1 for any other name. `BROWSER_UNITS` lists the 13 browser units, whose suites are audited.
- `ci/iris.sh:663-702` `cmd_live` -- apply the floor before line 698 runs the unit's script.
  - Keep line 698's text byte for byte: `web/scripts/ci-results.test.mjs` pins it.
  - `web/scripts/state-wait.test.mjs` `live()` evals only the region from `TRACE_FOLDER_NAME=` to the end of `cmd_live`, and sources no `units.sh`. The floor code must tolerate a missing `unit_live_deadline`: guard it with `command -v`.
- `ci/iris.sh:713-746` `cmd_group` -- prints `---- UNIT <u> begins`, `UNIT <u> passed|failed <s>s` and `GROUP <g> passed (<s>s)`. These are the audit's unit and group sources.
- `docker/tests/lib-live.sh`:
  - `:90`: `deadline=$((SECONDS + ${OCUTALON_LIVE_DEADLINE:-540}))`.
  - `:207`: `LIVE_PORT_WAIT=${LIVE_PORT_WAIT:-90}`, the sibling knob for the new `LIVE_FIRST_START_WAIT`.
  - `:449-466` `wait_until`: counts only its 3 s sleeps, so a budget is in poll seconds, and wall-clock runs longer by the probe time.
  - `:537-560` `wait_started_log` / `wait_started_ready`: the header says "Prints nothing"; this story changes that. `wait_started_ready` parks Telegram after its budgeted part (`PARK done <s>s`).
  - `:430-434` `first_start_report`: AD-23's 720 s WARN, unchanged.
- First-start waits, each `wait_started_ready 400` plus a die that names "the first start ... within 400 s". There are 23 CI live scripts:
  - `test-answers`, `test-audit`, `test-bundle-folder`, `test-cards`, `test-demo-switch`, `test-documents`, `test-floor`;
  - `test-heartbeat-restart`, `test-install-start`, `test-install-upgrade`, `test-memory-offline`;
  - `test-online-allowance`, `test-online-demo`, `test-online-demo-path`, `test-online-session`, `test-online-visitors`;
  - `test-production`, `test-production-restart`, `test-reminder-restart`, `test-security-overview`, `test-session-data`, `test-sign-in`, `test-storage-roundtrip`.

  Find them with `rg -l 'first start did not end ready within 400 s' docker/tests/test-*.sh`, less `test-release-sequence.sh` (fixture text only). `test-demo-path.sh` uses `live_first_start 900`: leave it alone. Out of scope: `record-eval.sh` (not a CI unit) and `release/upgrade-harness.sh` (release path).
- `docker/tests/test-install-upgrade.sh` -- three waits:
  - `:170-173`: row 6, `wait_started_ready 200`;
  - `:205-208`: row 7 failing step, `wait_started_log 200`;
  - `:256-259`: row 7 next good image, `wait_started_ready 200`.

  DW-1082's trailer lists occurrences on all three. The header's deadline sentence (`:18-19`) is stale.
- `docker/tests/test-sign-in.sh`:
  - `:47-48`: the header's deadline sentence;
  - `:318-366`: `remaining=$((deadline - SECONDS))` and `OCUTALON_E2E_TIMEOUT_MS=$(((remaining - 20) * 1000))`, which is the suite budget;
  - `:367` `e2e_status=$?`: the MEASURED suite line goes right after it.

  `--project chromium|sign-in-2|sign-in-3` gives the unit `sign-in|sign-in-2|sign-in-3`. `test-sign-in-2.sh` and `test-sign-in-3.sh` exec this script. `web/scripts/e2e-part.test.mjs` reads this script's listing lines.
- Other ready-wait sites to audit, each a literal `wait_started_ready` or `wait_started_log`:
  - `test-install-start` rows 2, 3, 4, 4-restart (200 s);
  - `test-bundle-folder` restart (200);
  - `test-production-restart` row 19 x2 (200) and row 20 (300);
  - `test-production:400` digest restart (300);
  - `test-online-demo` row 13 (200);
  - `test-online-visitors` row 7 (300);
  - `test-heartbeat-restart` restarts 1 and 2 (300);
  - `test-reminder-restart` restart 1 (300) and restart 2 (400);
  - `test-documents` restart (400);
  - `test-memory-offline` restart (400).

  Also `test-compose-start.sh:32` `wait_ready` (240 s merge, 90 s), `test-install-script-live.sh:157` (600 s) and `LIVE_PORT_WAIT` 90 s (`PORT free ... after <s> s` lines).
- Suite budgets that derive from the deadline: `test-floor:86`, `test-cards:72`, `test-answers:89`, `test-demo-path:76` (minus 80 s), `test-online-*`, `test-demo-switch:164`. The Playwright total is in each unit's `N passed (X.Ym)` line. `web/playwright.config.ts:68-71` sets `retries: 0`, `timeout: 45_000`, `expect 10_000` and `globalTimeout` from `OCUTALON_E2E_TIMEOUT_MS`.
- `docker/tests/test-ci-config.sh`:
  - `:683` pins CI's deadline at 1200; unchanged.
  - `:2052-2088` `tk_live` is the real `cmd_live` over a fake checkout, with a `TK_UNIT_EXTRA` hook in the fake unit. Extend it.
  - `:1-60` is the header list of rules; add the new rule there.
- `docker/tests/test-lib-live.sh:135-160` -- the `wait_started_log` / `wait_started_ready` rows, with a fixture log, `deadline` and `set_health`. Extend them.
- `.github/workflows/ci.yml` (read only):
  - `checks` 20 min, `web` 10, `install-macos` 15, `iris` 40 (`:32,47,58,104`); the iris env has `OCUTALON_LIVE_DEADLINE: "1200"`. Rework iteration 1 changed `checks` to 25 and `iris` to 50 (DW-1213, DW-1212).
  - `lane-a.yml`: 25, 30, 35 and 35 min; rework iteration 1 changed the last two (`ipm-install`, `ipm-install-p`) to 45 (DW-1214).

  Report-only rows.
- `_bmad-output/implementation-artifacts/evidence/` -- the project's Task 0 record folder (for example `35-1-task0-mcp-attach.md`).
- Planning sample (inference; 2 green runs, 43227065531 and 43218921197; Task 0 replaces it):
  - unit seconds: install-start 1048, install-upgrade 1118/1111, sign-in 1133/1010, sign-in-2 1170/1038, sign-in-3 1184; near 1.4x: floor 848, online-demo 846, reminder-restart 818, demo-path 763;
  - FIRST-START ready 355 and 361 s; shard READY 267-405 s;
  - sign-in suites 11.1-12.6 min;
  - install-upgrade log gaps, build included: row 6 about 271 s, row 7 failing step about 204 s, row 7 next good image about 215 s;
  - GROUP 1,370-2,000 s; the `checks` job 16.7 min of 20;
  - fetching one run's 16 iris job logs takes about 25 s.

## Tasks & Acceptance

**Execution:**
- `_bmad-output/implementation-artifacts/evidence/0-32-task0-ci-time-budgets.md` -- Task 0, first. Measure from CI logs with read-only `gh`, using scratch scripts in the stage's scratch folder, and commit only the record. Each call must finish in about 150 s.
  - Inventory:
    - U: every live unit's deadline.
    - S: every browser unit's suite budget.
    - R: each ready-wait site of the Code Map. The 23 first starts count as one budget.
    - Report-only: every workflow job's `timeout-minutes`; each iris group's unit seconds plus job overhead against 2,400 s; Playwright's 45 s per-test timeout (the slowest test's median).
  - Green: per budget, the 10 newest `ci` push runs on any branch whose job holding the unit concluded `success` and printed the unit's pass line. Fewer is allowed; record n. Fetch run lists with `gh run list --workflow ci.yml --limit 40 --json databaseId,headSha,headBranch,event,conclusion,createdAt`. Fetch job ids and logs with `gh api repos/{owner}/{repo}/actions/runs/<id>/jobs` and `gh api --allow-escape-sequences repos/{owner}/{repo}/actions/jobs/<id>/logs`, 2 to 3 runs per call.
  - Sources:
    - U: `UNIT live:<u> passed <s>s`.
    - S: the Playwright `N passed (X.Ym)` line. The budget per run is D minus (the time of the last line before the Playwright output minus `---- UNIT ... begins`) minus 20 (80 for demo-path).
    - R: the timestamp gap from the last log line before the start command to the end of the wait. When a `PARK done <s>s` line follows, the end is that line's time minus its seconds; otherwise it is the next line. This is an upper bound, marked `<=`.
    - The first start: the largest per-unit median, with demo-path's `FIRST-START ready=` as a cross-check.
  - Rule: margin = budget / median.
    - Below 1.4, the new value is 1.4 x median, rounded up to 60 s for deadlines and to 30 s for waits.
    - Exactly 300 s for row 6 (ruled).
    - At least 300 s for both row 7 waits (DW-1082's occurrences).
    - For the three sign-in units, D must also give a suite budget of at least max(950, 1.4 x the suite median) at the median setup time.
    - Every value finite and at most 2,340 s.
  - Cap: about 12 changed budgets. The ruled ones come first, then those with the least margin. Every budget left under 1.4 becomes a `deferred:` entry of this spec. Every report-only row under 1.4 does too, for the Planner: group and job margins as ONE entry, and each workflow job timeout.
  - Table columns: budget (file:site or unit), current value, source, runs read, median, margin before, action, new value, margin after. The record also names the run ids read and the method, with no host or runner name and no local path.
- `ci/units.sh` -- add `unit_live_deadline` with the audited floors (the U rows below 1.4: install-start, install-upgrade, sign-in, sign-in-2 and sign-in-3, if Task 0 confirms them), plus a comment naming the evidence file. This keeps the floors with CI's other lists, where test-ci-config already pins them.
- `ci/iris.sh` `cmd_live` -- before the unit's script runs, set `OCUTALON_LIVE_DEADLINE` to the larger of the floor and the current value (default 540). When the floor applies, export it and print `DEADLINE live:<unit> <D> s`. This lifts the suite and wait budgets of slow units with no workflow hunk; the env's 1200 still holds for every other unit.
- `docker/tests/lib-live.sh` -- add `LIVE_FIRST_START_WAIT=${LIVE_FIRST_START_WAIT:-<audited value>}` beside `LIVE_PORT_WAIT`. In `wait_started_log`, on every return, print to stderr `MEASURED wait <script>:<line> <s> s of <max> s`. `<s>` is wall-clock seconds. `<script>:<line>` is the nearest calling frame outside `lib-live.sh` (basename). Update both functions' header comments. The line goes to stderr so that no `$(...)` caller captures it; CI's log still shows it.
- The 23 first-start scripts -- `wait_started_ready "$LIVE_FIRST_START_WAIT"`, and the die names `$LIVE_FIRST_START_WAIT s`. This keeps one first-start budget, changed in one place.
- `docker/tests/test-install-upgrade.sh`:
  - Rows 6 and 7: time each wait.
  - Print, before any die and on both outcomes: `MEASURED row 6: the upgrade took N s to ready`, `MEASURED row 7: the start with a failing step took N s to end` and `MEASURED row 7: the next good image took N s to ready`.
  - Set the budgets per Task 0, with the die texts to match.
  - Correct the header's deadline sentence.
- `docker/tests/test-sign-in.sh`:
  - Before the npm run, print `MEASURED live:<unit> suite budget <remaining-20> s`.
  - Right after `e2e_status=$?`, outside the outcome branches, print `MEASURED live:<unit> suite <s> s`, with wall-clock seconds.
  - Header: the deadline is 1200 s in CI, raised by the unit's floor in `ci/units.sh`.
- Other sites that Task 0 selects (inside the cap) -- the new literal at the site, with its die text. `docker/tests/test-install-start.sh` gets the same header sentence as test-sign-in.sh if it has a floor.
- `docker/tests/test-ci-config.sh` -- a new rule, "budgets (Story 0.32)", listed in the header, that pins:
  - `unit_live_deadline`'s exact floors, each a live unit of a group, an integer in (1200, 2340], and return 1 for an unlisted or unknown name;
  - no live unit script with a literal first-start budget, and every first-start die naming the variable;
  - lib-live's default equal to the audited value;
  - row 6's `wait_started_ready 300` and both row 7 values, with their MEASURED lines before the die;
  - test-sign-in.sh's two suite lines, the result line unconditional after `e2e_status=$?`;
  - each other changed site's value.

  Extend `tk_live` with rows for floor-over-1200, floor-under-given (stays) and no-floor (unchanged). The fake unit records `OCUTALON_LIVE_DEADLINE` through `TK_UNIT_EXTRA`. The `DEADLINE` line appears only when the floor applies.
- `docker/tests/test-lib-live.sh` -- add rows: a met wait and a timed-out wait (the existing rejects at `wait_started_log 1`) each print exactly one `MEASURED wait test-lib-live.sh:<line> <s> s of <max> s` on stderr, through `wait_started_ready` too, and nothing extra on stdout.

*Rework iteration 1 (Planner-approved RELEASE TOOL hunks, 2026-11-12 ~18:30Z; work ONLY these items):*
- [x] [Planner] DW-1212: `.github/workflows/ci.yml` job `iris` `timeout-minutes: 40` -> `50` (a hang backstop; no group rebalancing until after Sunday). Pin the value in the test that already pins the workflows (`docker/tests/test-ci-config.sh` or `docker/tests/test-ci-changes.sh`, wherever workflow facts are pinned), with a mutation.
- [x] [Planner] DW-1213: `.github/workflows/ci.yml` job `checks` `timeout-minutes: 20` -> `25`. Pin and mutation as above.
- [x] [Planner] DW-1214: `.github/workflows/lane-a.yml` jobs `ipm-install` and `ipm-install-p` `timeout-minutes: 35` -> `45` as a hang backstop, with REL-4's 35 minutes kept as the TARGET: each of the two jobs prints `MEASURED <job> N s` (its own wall time so far, measured from a timestamp the job's existing scripts take at their start) and, when N is over 2100 s (35 minutes), flags `over REL-4` in the run summary (`$GITHUB_STEP_SUMMARY`) and the log. Both lines come from the scripts the jobs already run (no new workflow step, key or line other than the two `timeout-minutes` values). Pin the values and the MEASURED / over REL-4 behaviour (a hermetic test with a stub clock or a fixed start time), with mutations.
- [x] [Planner] Update every comment, doc line and existing pin in the repository that states the old values (for example a "40-minute job cap is never raised" note in `ci/units.sh` or a test), so nothing claims 40/20/35 any more; REL-4's 35-minute TARGET wording stays where it is a target. Update the evidence file's report-only rows for DW-1212/1213/1214 to "changed (Planner-approved)".

**Acceptance Criteria:**
- Given `ci/iris.sh live install-upgrade`, when row 6's upgrade start is waited for, then the log shows `MEASURED row 6: the upgrade took N s to ready` whether it passes or fails, the budget is 300 s, and a start not ready within it fails row 6 (DW-1082). Row 7's two waits behave the same way with their own lines and audited budgets (at least 300 s).
- Given `ci/iris.sh live sign-in`, `sign-in-2` or `sign-in-3`, when the browser run ends, then the log shows `MEASURED live:<unit> suite budget B s` and `MEASURED live:<unit> suite N s`. At the audit's median setup, B is at least max(950, 1.4 x the suite median) (DW-1195).
- Given a unit listed in `unit_live_deadline`, when `ci/iris.sh live` (alone or through `group`) runs it with a lower or unset deadline, then its script runs with the floor and the log shows `DEADLINE live:<unit> D s`. A higher given value and any unlisted unit are unchanged. Integration: the consumer `cmd_live` reads `unit_live_deadline`, and the real unit script sees the value.
- Given any live unit's first start, when it is waited for, then its budget is `LIVE_FIRST_START_WAIT` (the audited value), and every `wait_started_log` return writes one `MEASURED wait` line naming the calling script and line. Integration: the 23 live scripts consume the constant.
- Given the committed evidence file, when it is read, then every budget of Task 0's inventory has a row. Every budget with margin under 1.4 shows a new value at or above 1.4 x, or a stated reason (ruled value or the cap) with a matching `deferred:` entry. The code's values equal the table's new-value column.
- Given the story's diff, when `bash docker/tests/test-ci-config.sh` runs (its unit and group pins unchanged), then it passes, and no test, unit, group or job is added, removed, renamed, moved, skipped or shortened. Every budget is finite: the floors are at most 2,340 s and every wait is a literal or a lib default.
- Given CI on this story's head (pushed after CI HOLD OFF), when it finishes, then every workflow is green. The job logs show the AC 1, AC 2 and AC 4 MEASURED lines and the AC 3 DEADLINE lines.

### Review Findings

Code review 2026-11-12 (full mode, baseline 4f8505cc, QA's uncommitted test-ci-config.sh change included; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, all on the session model). 34 raw findings; 0 decision-needed, 12 patch entries (all applied), 0 defer, 13 rejected. Rule 3: exempt (CI tooling, no user-facing surface). Rule 6: no AD mismatch.

**Supersedes the figures above:** the live:sign-in floor is **1560** (not 1500). The evidence file's U, S and R tables, method, changed-budgets table and report-only job and group rows are re-measured over 27 `ci` push runs (red and cancelled runs included, as Task 0's Green rule and Decided in-stage 8 require). Every other code value is unchanged.

- [x] [Review][Patch] [med] The green sample left out green jobs of red and cancelled runs in the window (5 failed, 5 cancelled; for example `UNIT live:sign-in passed 1195s` in 43172863798), so live:sign-in's median was 1033.5 s instead of 1079.5 s and its 1500 s floor sat at 1.39 [ci/units.sh:213, evidence file Method and tables] -- re-fetched read-only, re-parsed with the implement stage's own scripts; sign-in's floor is 1560 (1.45; suite budget 1178 s, at least max(950, 966)); sign-in-2 1.43, sign-in-3 1.47, install-start 1.46; first start 510 s still holds (largest median 348 s, live:sign-in); the install waits keep their values (acceptance-auditor)
- [x] [Review][Patch] [med] The report-only job medians counted run 43200877872, whose iris jobs ran no group (11-18 s `success`), so shards-2's job median (1732 s) sat below its own unit seconds (1747 s) and shards-6 showed 1.41 instead of 1.37 [evidence file, group and workflow tables] -- each group row now uses the 10 newest runs with a `GROUP passed` line for both columns; DW-1212, DW-1213 and DW-1214 got a `by=cr` trailer with the corrected figures (blind-hunter)
- [x] [Review][Patch] [med] The install-upgrade pins did not tie `wait_rc=$?` to its wait nor `wait_began=$SECONDS` to its row, so a line between the wait and its status left the die dead with the pins green [docker/tests/test-ci-config.sh budgets loop] -- the loop now checks the wait literal at MEASURED-2 and `wait_began=$SECONDS` at MEASURED-3 for all three rows (verification-gap)
- [x] [Review][Patch] [med] The sign-in status pin accepted the npm line at either of the two lines before `e2e_status=$?`, so an interposed line could turn a red suite into a pass [docker/tests/test-ci-config.sh] -- the npm line must be the line straight before (verification-gap)
- [x] [Review][Patch] [med] test-lib-live's default row read the runtime value (red whenever the knob was set in the caller's environment) and its `-lt 720` conjunct could not fail once `= 510` held [docker/tests/test-lib-live.sh] -- the default is read with the knob unset (`env -u`, the LIVE_PORT_WAIT row's pattern), and the AD-23 bound is its own row (blind-hunter+verification-gap)
- [x] [Review][Patch] [low] The measured rows relied on the previous section's start stamp, the file-level LIVE_TELEGRAM and the global deadline [docker/tests/test-lib-live.sh] -- the block sets all four itself (verification-gap)
- [x] [Review][Patch] [low] The AC 5 check read only the changed-budgets table, not the U and R tables' new column [docker/tests/test-ci-config.sh] -- it now also checks the five U rows, the count of floor rows, every first-start row and the five raised R rows against the code (verification-gap)
- [x] [Review][Patch] [low] `unit_live_deadline`'s comment claimed the floors keep a run under the iris job's 40 minutes; the bound is per unit [ci/units.sh:204-209] (blind-hunter+edge-case-hunter)
- [x] [Review][Patch] [low] lib-live's comment said every live script that starts a stack uses `LIVE_FIRST_START_WAIT`; record-eval, the release harness and demo-path do not [docker/tests/lib-live.sh:208-212] (blind-hunter)
- [x] [Review][Patch] [low] The headers of test-install-start, test-install-upgrade and test-sign-in said 540 s when the deadline is unset, which holds only for a direct run; through `ci/iris.sh live` the floor applies (edge-case-hunter+acceptance-auditor+blind-hunter)
- [x] [Review][Patch] [low] Evidence prose: margins were computed from unrounded medians without saying so, 25 first-start rows stood for 23 scripts unexplained, and the summary sentence "every other budget has at least 1.4 (the lowest ... 1.39 and 1.38)" contradicted itself [evidence file] (blind-hunter+edge-case-hunter+acceptance-auditor)
- [x] [Review][Patch] [low] Rule 19: no recorded mutation for AC 2's B bound or AC 4's "naming the calling line" -- closed by the mutations below; AC 2's B bound is the exact floor pin (the recorded "sign-in floors set to 1200" mutation)

Mutations (review; each applied, observed red, reverted; `git status --short` and `git diff` checksums identical afterwards):
- mutation: `echo` inserted between row 6's `wait_started_ready 300` and `wait_rc=$?` -> test-ci-config budgets red ("does not follow wait_began=$SECONDS, wait_started_ready 300 and wait_rc=$? line by line").
- mutation: row 7's `wait_began=$SECONDS` deleted -> budgets red (the same message for row 7's failing step).
- mutation: `echo` inserted between the sign-in npm run and `e2e_status=$?` -> budgets red ("e2e_status=$? is not the line straight after the npm run").
- mutation: the evidence U table's live:sign-in new value 1560 -> 1500 (summary table unchanged) -> budgets red ("evidence U table: live:sign-in is '1500', ci/units.sh has '1560'").
- mutation: `${BASH_LINENO[$((i - 1))]}` -> `${BASH_LINENO[$i]}` in `wait_started_log` -> test-lib-live red (the five measured rows); in the same run, with `LIVE_FIRST_START_WAIT=600` in the environment, both default rows stayed green (hermetic).

Rejected:
- `low` Blind: the floor raises an unset local deadline (a local hang runs about 25 minutes) -- by-design, Decided in-stage 3 (local `ci/iris.sh live` runs get the floors); a green local sign-in run already takes about 17 minutes.
- `low` Blind: the 540 default lives in both cmd_live and lib-live -- wontfix-theoretical; real only if lib-live's default rose above 1440 s.
- `low` Blind: the `MEASURED wait` line of `wait_started_ready` covers only the log part and does not say whether the run's deadline ended it -- documented in both headers; the spec puts the line on `wait_started_log`, and rows 6 and 7 time the whole call.
- `low` Blind: the AC 5 pin makes test-ci-config read the dated evidence file -- by-design: it is QA's standing check of AC 5's equality, and removing it deletes a test.
- `low` Edge/acceptance: a given deadline with leading zeros, beyond int64, padded or signed -- wontfix-theoretical; CI sets the bare `"1200"` (pinned) and the release 1980; real if a caller passes such a value.
- `low` Edge: a non-numeric `LIVE_FIRST_START_WAIT` -- theoretical, as for its sibling `LIVE_PORT_WAIT`.
- `low` Edge: record-eval.sh keeps a literal 400 -- by-design, not a CI unit (Code Map).
- `low` Edge: the release harness keeps literal 400 s waits -- by-design, `release/**` is on the Never list.
- `false` Edge: a 510 s budget can pass AD-23's 720 s in wall-clock time -- the 720 s WARN is demo-path's FIRST-START report (`live_first_start 900`, unchanged); the budget is in poll seconds and AD-23 sets no bound on this wait.
- `low` Edge: the commit message says every budget gets a 40% margin while row 6 is 1.37 -- by-design, ruled (DW-1082) and recorded in the evidence and `deferred:`.
- `low` Verification-gap: no mutation for AC 3 "through `group`" -- `cmd_group` runs each unit as a new `bash ci/iris.sh live`, the same `cmd_live` the tk_live rows drive.
- `low` Verification-gap: AC 5's "every budget of the inventory has a row" and AC 6's "nothing removed" have no automated pin -- by-design, one-off checks of the record and of the diff (both held at this review: 29 U rows equal the groups' live units; no test, unit, group or job removed).
- `low` Acceptance: QA's test-ci-config.sh change is uncommitted -- not a defect; the lead commits it with this review's patches.

## Spec Change Log

- 2026-11-12 ~18:30Z, lane-B runner: rework iteration 1 opened for the Contest Planner's approval of the RELEASE TOOL hunks DW-1212 (iris 40 -> 50 min), DW-1213 (checks 20 -> 25 min) and DW-1214 (ipm-install and ipm-install-p 35 -> 45 min, REL-4's 35 min kept as the target with MEASURED and over-REL-4 lines); the Boundaries line on workflows is amended for exactly those four values. Follow-up DW-1217 (CI host memory, a proposal for the Planner) filed, routed burndown.

## Review Triage Log

### 2026-11-12 -- Review pass
- verdicts: 28 findings from the three finding layers (blind 9, edge 11, verification-gap 8; the intent-alignment layer is descriptive) -- high 0, medium 1, low 27, false 0, maybe-false 0; 3 patched, 25 rejected (rows below group them by root cause; the stale `Status:` line in the spec was fixed at finalize)
- findings:
  - `[low]` `patch` Blind: no test that the `MEASURED wait` line prints when the container has no start time (also verification-gap 1) -- a test-lib-live row was added and its mutation run (red, reverted)
  - `[low]` `patch` Verification-gap: the non-numeric given deadline in `cmd_live` was unpinned -- a `tk_live floor-nonnumeric` row was added and its mutation run (red, reverted)
  - `[medium]` `patch` Blind: `test-release-sequence.sh` and `test-rehearsal.sh` not run to a verdict -- the lead ran the `overviewunit` rule of the first (PASS); the rules that touch `ci/units.sh` and lib-live live there, and neither file reads the changed wait scripts (the default run exceeds the 150 s cap)
  - `[low]` `reject` Blind/edge: the floor lifts a lower local `OCUTALON_LIVE_DEADLINE` with no opt-out -- by design (Decided in-stage 3: local `ci/iris.sh live` runs get the floors); a spec-bound behaviour
  - `[low]` `reject` Edge: a given deadline with whitespace is read as 0 -- theoretical; CI sets a bare integer
  - `[low]` `reject` Blind/edge: MEASURED covers only the log part of `wait_started_ready`, and the empty-stamp line reads `0 s of N s` -- documented in the header comment; rows 6 and 7 time the whole call
  - `[low]` `reject` Blind/verification-gap: install-upgrade, install-start and sign-in budget pins are text pins -- by design; the scripts need a live stack and AC 7 is CI's own result
  - `[low]` `reject` Blind: release upgrade-harness waits also print the new stderr line -- the release path is out of scope; the added output is on stderr and no caller captures it
  - `[low]` `reject` Blind: 510 s sized from an upper-bound median, no tail figures, duplicate row-level lines, header tidiness -- the spec's rule (largest per-unit median x 1.4) and its row-line form are followed
  - `[low]` `reject` Edge: group sums can pass the job cap, claims about "every changed budget" and "one budget" -- already the group-margin `deferred:` entry; claims are the spec's wording
  - `[low]` `reject` Edge: BASH_SOURCE empty frames, a prefix match of `wait_started_ready 300`, record-eval's literal 400 -- theoretical or out of scope (record-eval is not a CI unit)
  - `[low]` `reject` Verification-gap: the AC 5 table check is a scratch script, AC 7 has no mutation, the `(1200, 2340]` bound is caught by the exact floor pin, test-lib-live rows rely on the earlier start stamp -- the spec makes AC 5 a one-off check and AC 7 CI's result; the exact floor pin already fails first
  - `[low]` `reject` Intent-alignment (descriptive): the diff implements the reading in which scripts raise effective deadlines while the workflow keeps 1200 -- that is the spec's approach (Decided in-stage 3), not a divergence from its intent

### 2026-11-12 -- Review pass (rework iteration 1)
- verdicts: 14 findings (blind 8, edge 6; verification-gap 2 entries with 2 sub-items; the intent-alignment layer is descriptive; the first verification-gap launch had a mistyped diff path, read nothing and was run again) -- high 0, medium 1, low 13, false 1, maybe-false 0; 2 patched (one root cause each), 12 rejected
- findings:
  - `[medium]` `patch` Verification-gap: the three negative REL-4 rows (another job, no GITHUB_JOB, no stamp) assert only an absence on output and never that the teardown ran -- each now also asserts the `TEARDOWN tag` line (mutation: the line renamed -> the three rows red)
  - `[low]` `patch` Verification-gap / blind / edge: no row for a second `build` keeping the first stamp, and none that a non-REL-4 job writes no stamp -- `budget_job` takes a fifth argument (a second build), a `rel4-twice` row and a stamp-folder check on `rel4-other` were added (mutations: the keep-first guard removed, `job_is_rel4 || return 0` removed in `job_start_stamp` -> both red)
  - `[low]` `reject` Blind: the Never list (line 87) still says never raise `timeout-minutes` -- inside the read-only intent-contract; the amendment at line 85 carves out the four values; a fix would edit this build's spec
  - `[low]` `reject` Blind / edge: the deferred entries keep the old 40/20/35 wording -- they record the audit's findings as they stood; the rows' severity lines say changed; a fix would edit the spec's record
  - `[low]` `reject` Blind: no `::warning::` annotation for an over-REL-4 job -- the item asks for the run summary and the log; by-design
  - `[low]` `reject` Blind / edge / verification-gap / intent: N counts from `build`, so it leaves out runner setup and checkout -- the item says "measured from a timestamp the job's existing scripts take at their start"; the script and its comment say "since the stamp of `build`"; spec-bound
  - `[low]` `reject` Blind: no pin that the two jobs run `build` first and `teardown` last -- `false`: test-cpf.sh pins `ci/iris.sh build` before the install script in both jobs and test-ci-config's teardown rule pins an `if: always()` teardown step for every job that runs `ci/iris.sh`
  - `[low]` `false` Blind: wiring of teardown is unpinned (see the row above) -- refuted there
  - `[low]` `reject` Blind / edge: a backwards clock prints a negative N; a stamp left by a killed runner; an unwritable stamp -- wontfix-theoretical; the tag carries the run id and attempt, so a stale stamp is never read by another run
  - `[low]` `reject` Edge: no rows for a non-numeric stamp, an unset or unwritable step summary -- defensive guards with no user-reachable failure
  - `[low]` `reject` Blind: the longer caps hold a runner longer on a hang, and the units.sh note on the 50-minute bound is looser -- Planner-approved (DW-1212, DW-1214); by-design
  - `[low]` `reject` Verification-gap: the sourced test host and stub clock do not prove `GITHUB_JOB` or `GITHUB_STEP_SUMMARY` on the runner -- CI's own result on the head (AC 7, the lead)
  - `[low]` `reject` Verification-gap: the pre-existing teardown fixture would print extra lines inside an ipm-install job -- not reachable by CI (the checks job runs it)
  - `[low]` `reject` Intent-alignment (descriptive): the diff implements the script-surface reading (the amendment's wording) -- not a divergence

## Design Notes

- **Architecture:**
  - AD-22: the one CI recipe, `ci/iris.sh` with the lists in `ci/units.sh`. The floors live there, not in the workflow.
  - AD-23: the first start's 720 s WARN and the demo-path FIRST-START figure are unchanged. The new first-start budget stays under 720 s.
  - AD-29: Epic 0 may edit any lane's scripts.

  No AC contradicts an AD's Rule.
- **Consumes / Consumed-by:**
  - `unit_live_deadline` is consumed by `ci/iris.sh cmd_live` (this story).
  - `LIVE_FIRST_START_WAIT` is consumed by the 23 live scripts (this story).
  - The MEASURED lines are consumed by the next run of the standing audit, which reads CI logs (no story id).
- **Extend, don't copy:** `unit_live_deadline` extends `group_units`/`shard_areas`; `LIVE_FIRST_START_WAIT` extends `LIVE_PORT_WAIT`; the row lines copy the existing `MEASURED Story 29.7: the restart took 38 s to ready` form; the test rows extend `tk_live` and test-lib-live's wait rows.
- **Ledger inbox (Rule 17):**
  - DW-1082 is addressed by AC 1, which also covers its row 7 occurrences.
  - DW-1195 is addressed by AC 2.

  Both close at adjudication against the delivered diff and the CI head's lines.
- **Decided in-stage:**
  1. Record location: `evidence/0-32-task0-ci-time-budgets.md`, the project's Task 0 convention. It is not `docs/`, which is judge-facing (it would need a public-text ruling), and a bookkeeping path runs no CI group when the audit is refreshed.
  2. The budget set is the AC's parenthetical: unit, suite and ready-wait timeouts. Job timeouts, REL-4, Playwright's per-test 45 s and product behaviour bounds are report-only or excluded.
  3. The floors sit in `ci/units.sh` and `cmd_live`, applied as a max. They do not go in `ci.yml` (a workflow hunk), and a script's `:=` default would lose to CI's 1200. Local `ci/iris.sh live` runs get the floors too; a direct `bash docker/tests/test-x.sh` does not.
  4. DW-1195 raises rather than splits. A fourth sign-in unit needs about 420 s of its own setup, and on the sample every group already holds 1,370-2,000 s of units, so none has room under about 33 minutes (inference; Task 0 records the check). A new group needs a workflow hunk.
  5. DW-1082's 300 s covers all three upgrade waits of live:install-upgrade (the entry's occurrences), and each wait gets the ruled line's form.
  6. Floors are not capped by the room left in the group's job, because the AC asks for 1.4 x the unit's own budget. A job whose units' worst case would pass 40 minutes goes into the one group-margin `deferred:` entry for the Planner. Raising the job cap is the Planner's call (a RELEASE TOOL hunk).
  7. Budgets count `wait_until`'s poll seconds while MEASURED lines report wall-clock, so a passing wait may print more seconds than its budget. Comparing budgets to wall-clock medians errs on the safe side.
  8. "Green" is counted per budget, by the job, so a run that is red elsewhere still counts.
  9. Not edited: `_bmad/custom/skill-rules.md` (owner-only). Its Rule 21 sentence "1200 s in CI" stays true for every unit without a floor.

## Verification

Shared surfaces:
- test-ci-config's pins: the deadline at `:683`, the unit and group pins (unchanged, must still pass), and `tk_live`.
- test-lib-live's wait rows.
- `web/scripts/state-wait.test.mjs` (the real `cmd_live` region, with no units.sh).
- `web/scripts/ci-results.test.mjs` (`cmd_live`'s `OCUTALON_E2E_OUTPUT` line).
- `web/scripts/e2e-part.test.mjs` (test-sign-in.sh's listing lines).
- `test-upgrade-harness.sh` (stubs the waits; its pins of `release/upgrade-harness.sh` are unchanged).
- `test-release-sequence.sh:2076` (fixture text "within 400 s", unchanged).
- Every caller of `wait_started_*`. Search for one inside `$(...)`; stderr keeps such a caller safe.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands.** Run them from the worktree root, one per call. `<lane-B>` is the Boundaries value with `stage=implement`; `<scratch>` is the stage's own scratch folder.
- Task 0 (once each, in about 150 s): the `gh run list` and `gh run list --workflow lane-a.yml` listings into `<scratch>`; then the job-log fetches, 2 to 3 runs per call; then the scratch parse into `<scratch>/audit.tsv`. Expected: at least 10 green samples for most budgets, and the table written.
- `for f in <changed .sh files>; do bash -n "$f" || echo "BAD $f"; done` (loop). Expected: no output.
- `bash docker/tests/test-ci-config.sh` (loop, about 85 s). Expected: `test-ci-config: all rules passed`, with the budgets rule's PASS.
- `bash docker/tests/test-lib-live.sh` (loop, about 60 s). Expected: `all checks passed`.
- `bash docker/tests/test-ci-warm.sh` (once, about 65 s), `bash docker/tests/test-upgrade-harness.sh` (once, about 35 s) and `bash docker/tests/test-ci-changes.sh` (once). Expected: all pass.
- `node --test web/scripts/state-wait.test.mjs web/scripts/ci-results.test.mjs web/scripts/e2e-part.test.mjs` (once). Expected: 0 failures.
- `<lane-B> OCUTALON_RUN_TAG=e0bs32au bash ci/iris.sh live audit` (once; about 120-160 s locally, inference). Expected: `MEASURED wait test-audit.sh:<line> <s> s of <LIVE_FIRST_START_WAIT> s` and every check PASS. If the harness backgrounds it, wait with bounded foreground polls of its output, never `Monitor`. Then `<lane-B> OCUTALON_RUN_TAG=e0bs32au bash ci/iris.sh teardown` (once).
- Table against code (once): every new value in the evidence file's table equals the code's (`unit_live_deadline`, `LIVE_FIRST_START_WAIT`, each site's literal).
- `LC_ALL=C tr -d '\011\012\040-\176' < <file> | wc -c` for each changed shell file (once). Expected: 0.
- Lead (once, after CI HOLD OFF): push; every workflow green on the head; the job logs carry the MEASURED and DEADLINE lines of the ACs (`gh api .../jobs/<id>/logs`, read-only).

**Mutations.** One per AC. Apply each, observe red, revert, and confirm `git status --short` and `git diff --stat` are unchanged.
- AC 1: row 6 back to `wait_started_ready 200`, then separately drop the row 6 MEASURED echo. Expected red: test-ci-config budgets.
- AC 2: move the suite echo inside the pass branch. Expected red: test-ci-config budgets.
- AC 3: delete the floor line in `cmd_live`. Expected red: the `tk_live` floor row. Set sign-in's floor to 1200. Expected red: the budgets floor pin.
- AC 4: drop the `MEASURED wait` echo. Expected red: test-lib-live. Put one script back to `wait_started_ready 400`. Expected red: the budgets rule.
- AC 5: change one new value in the code but not in the table. Expected: the table-against-code check reports the mismatch.
- AC 6: set a floor of 2400. Expected red: the budgets bound.
- AC 7: no mutation. It is CI's own result on the head (lead).

### Measured (implement)

Task 0 is `evidence/0-32-task0-ci-time-budgets.md` (17 ci push runs read, n = 10 per budget; the table, method and run ids are there).

- Unit deadlines: the five the plan expected are under 1.4: install-start 1.20, install-upgrade 1.18, sign-in 1.16, sign-in-2 1.15, sign-in-3 1.12. The lowest of the others is live:floor at 1.47. Floors: 1440, 1440, 1500, 1500, 1500.
- Suites: sign-in 1.23, sign-in-2 1.21, sign-in-3 1.21 (budgets 832, 841 and 822 s at a 348, 339 and 358 s setup, against suites of 675, 696 and 681 s); with D = 1500 the budgets are 1132, 1141 and 1122 s (1.68, 1.64, 1.65; DW-1195's 950 s and 1.4 x median both met). Every other suite has at least 1.8 (live:floor 1.80, demo-path 2.27).
- Ready waits: the first start 1.16 at the largest per-unit median (346 s, test-sign-in-3.sh; demo-path's own FIRST-START ready= median is 306 s), so `LIVE_FIRST_START_WAIT` is 510 s (1.4 x 346 = 484, up to 30 s; under AD-23's 720 s). install-start row 3 (210 s median, 0.95) goes to 300 s and row 4's restart (191 s, 1.05) to 270 s. install-upgrade row 6 (219 s, 0.91) is 300 s as ruled, row 7's failing step (203 s, 0.98) 300 s and its next good image (216 s, 0.93) 330 s. All other waits have at least 1.86. `LIVE_PORT_WAIT` has no sample (no `PORT free` line in any of the 17 runs).
- 11 budgets changed (the cap is about 12). Every changed budget has at least 1.4 after, except row 6 at 1.37 (ruled) with a deferred entry.
- The plan's workflow facts differ in two places: ci.yml has `install-macos` at 10 minutes and `web` at 15 (the plan names them the other way round); neither is near its cap (39 s and 80 s medians).
- The plan expected row 7's failing step to be a `PARK` site; it is `wait_started_log`, measured from the gap before its first PASS line.
- Local live check: `ci/iris.sh live audit` on a lane-B throwaway passed all its checks and printed `MEASURED wait test-audit.sh:51 99 s of 510 s`; the throwaway was torn down (0 leftovers).
- Commands run, all green: `bash -n` and the ASCII check on every changed shell file; `test-ci-config.sh` (all rules passed, with the budgets rule); `test-lib-live.sh` (all checks passed, 6 new `measured` rows); `test-ci-warm.sh`, `test-upgrade-harness.sh`, `test-ci-changes.sh`; `node --test` of state-wait, ci-results and e2e-part (96 pass, 0 fail); `test-boundaries`, `test-storage`, `test-class-rules`, `test-pinned-sources`, `test-after-start`, `test-demo-path-gate`, `test-readme`, `test-release-checklist`. `test-release-sequence.sh` and `test-rehearsal.sh` were started and stopped at 100 s without a verdict: neither reads the changed scripts except the unchanged fixture text of test-release-sequence.sh:2076. The table-against-code check (a scratch script over the evidence table, the five floors, `LIVE_FIRST_START_WAIT` and the five install literals) reported no mismatch.

### Mutations (Rule 19)

Each applied to the tree, observed red, reverted; `git status --short` and `git diff` identical afterwards (checked by checksum each time).

| mutation | test | result |
|---|---|---|
| AC 1: row 6 back to `wait_started_ready 200` | test-ci-config budgets | red: row 6 is not wait_started_ready 300, then its MEASURED line, then its die |
| AC 1: drop the row 6 MEASURED echo | test-ci-config budgets | red, same message |
| AC 1: install-start row 3 back to 200 | test-ci-config budgets | red: row 3's wait is not 300 s with its die |
| AC 2: the suite result echo removed from after `e2e_status=$?` | test-ci-config budgets | red: not the unconditional line after e2e_status |
| AC 2: the suite result echo only when `e2e_status` is 0 | test-ci-config budgets | red, same message |
| AC 3: delete `export OCUTALON_LIVE_DEADLINE=$floor` in cmd_live | test-ci-config budgets (tk_live floor rows) | red: the unit saw 1200, wanted 1500; unset, wanted 1440 |
| AC 3: the sign-in floors set to 1200 | test-ci-config budgets (floor pin) | red: the floors are ... sign-in=1200 |
| AC 3: `-lt` to `-le` (a floor equal to the given deadline) | test-ci-config budgets (floor-equal row) | red: a DEADLINE line was printed |
| AC 3: `floor` given a floor of 1300 (an unlisted unit) | test-ci-config budgets (floor pin) | red: the floors include floor=1300 |
| AC 4: drop the `MEASURED wait` echo | test-lib-live | red: the four measured wait rows |
| AC 4: the `MEASURED wait` line to stdout (no `>&2`) | test-lib-live | red: the measured rows |
| AC 4: test-floor.sh back to `wait_started_ready 400` | test-ci-config budgets | red: test-floor.sh:58 first-start wait is not the variable |
| AC 4: lib-live default 510 back to 400 | test-ci-config budgets | red: LIVE_FIRST_START_WAIT does not default to 510 |
| AC 5: a die text changed to 360 s, table unchanged | table-against-code scratch check | MISMATCH reported |
| AC 6: install-start and install-upgrade floors of 2400 | test-ci-config budgets | red: the floors are ... install-start=2400 (the bound of 2340) |
| AC 4 (review pass): the `MEASURED wait` echo skipped when the container has no start time | test-lib-live "a wait for a container with no start time" | red: that row FAILs |
| AC 3 (review pass): the `case` line that turns a non-numeric given deadline into 0 deleted from `cmd_live` | test-ci-config budgets `floor-nonnumeric` | red: the unit saw 'abc', wanted 1500 |

**Rework iteration 1 (DW-1212, DW-1213, DW-1214; Planner-approved RELEASE TOOL hunks).** Each mutation applied to the tree, `bash docker/tests/test-ci-config.sh` observed red, reverted; `git status --short` and `git diff` checksums identical afterwards (a scratch script compared them each time).

Done: `ci.yml` `iris` 40 -> 50 and `checks` 20 -> 25, `lane-a.yml` `ipm-install` and `ipm-install-p` 35 -> 45 (nothing else in a workflow). `ci/units.sh` holds `REL4_JOBS` and `REL4_TARGET_SECONDS` (2100). `ci/iris.sh build` (the first script of each IPM job) writes the job's start stamp, and `ci/iris.sh teardown` (the job's last step, `if: always()`) prints `MEASURED <job> N s` and, above 2100 s, `over REL-4: <job> took N s, the target is 2100 s` to the log and `$GITHUB_STEP_SUMMARY`; any other job, or a run with no stamp, prints nothing. No workflow step, key or line was added and `release/**` is untouched. Old values in `ci/units.sh` comments now read "then 40-minute" (history) or 50 minutes (the floors' bound); the evidence file's report-only rows are marked changed (Planner-approved). The pins are in test-ci-config.sh's `budgets` rule (the four timeouts, the two constants, and a hermetic run of the real `cmd_build` and `cmd_teardown` with a stub clock and stub docker: under, exactly at and over 2100 s, another job, no job, no stamp, stamp removed).

- mutation: ci.yml `iris` back to `timeout-minutes: 40` -> test-ci-config budgets red ("job iris has timeout-minutes '40', wanted 50").
- mutation: ci.yml `checks` back to 20 -> budgets red ("job checks has timeout-minutes '20', wanted 25").
- mutation: lane-a.yml `ipm-install` back to 35 -> budgets red ("job ipm-install has timeout-minutes '35', wanted 45").
- mutation: lane-a.yml `ipm-install-p` back to 35 -> budgets red ("job ipm-install-p has timeout-minutes '35', wanted 45").
- mutation: `job_start_stamp` call deleted from `cmd_build` -> budgets red (the MEASURED and over REL-4 rows).
- mutation: `job_wall_report "$tag"` deleted from `cmd_teardown` -> budgets red (the MEASURED rows and the stamp-still-there row).
- mutation: `-gt` to `-ge` in `job_wall_report` -> budgets red ("REL-4 exactly at 2100 s: an 'over REL-4' flag was printed").
- mutation: the `$GITHUB_STEP_SUMMARY` write deleted -> budgets red ("no 'over REL-4' line in the step summary").
- mutation: `REL4_TARGET_SECONDS=2100` -> 2400 in ci/units.sh -> budgets red (the constants pin and the over rows).
- mutation: `job_is_rel4` accepts any non-empty `GITHUB_JOB` -> budgets red ("another job (iris): a REL-4 line was printed").
- mutation (review pass): `[ -f "$f" ] ||` removed from `job_start_stamp` (a second build overwrites the stamp) -> budgets red ("REL-4 with a second build: the stamp of the first build was not kept"); reverted, `git status --short` and `git diff` checksums identical.
- mutation (review pass): `job_is_rel4 || return 0` deleted from `job_start_stamp` -> budgets red ("another job (iris): a start stamp was written"); reverted, checksums identical.
- mutation (review pass): `TEARDOWN tag` echo renamed in `cmd_teardown` -> budgets red in the three negative rows ("the teardown did not run to its TEARDOWN line"); reverted, checksums identical.

Verification: `bash -n` and the ASCII check on ci/iris.sh, ci/units.sh and test-ci-config.sh; `test-ci-config.sh` (all rules passed), `test-cpf.sh`, `test-ci-changes.sh`, `test-ci-warm.sh` pass; `node --test` of state-wait, ci-results and e2e-part (96 pass). Nothing needed a live stack.

AC 7 is CI's own result on the head (the lead, after CI HOLD OFF).

### QA record (2026-11-12, recorded by the lead from the QA stage's return)
- (QA) `docker/tests/test-ci-config.sh`, rule `budgets`: the three install-upgrade `MEASURED row 6/7` lines must sit straight after `wait_rc=$?` and before the status test (unconditional: pass or fail); and the evidence file's "Changed budgets" table must match the code (five floors, `LIVE_FIRST_START_WAIT`, install-upgrade rows 6/7/7-good-image and install-start rows 3/4), a missing file or a non-unique row failing.
- mutation: row 6 MEASURED echo moved into the failing branch -> `test-ci-config.sh` budgets red ("not the unconditional line between wait_rc=$? and the status test").
- mutation: evidence table row 9 edited 330 -> 360 -> budgets red ("row 7 next good image is '360', the code's die says '330'").
- mutation: evidence table row 5 edited 1500 -> 1560 -> budgets red ("live:sign-in-3 deadline is '1560', ci/units.sh has '1500'").

## Auto Run Result

Status: done
Blocking condition: none

Summary: the CI time budgets of Story 0.32 are audited (n = 10 green jobs per budget, 17 `ci` runs) and 11 budgets are raised; the audit table is `_bmad-output/implementation-artifacts/evidence/0-32-task0-ci-time-budgets.md`. Floors live in `ci/units.sh` `unit_live_deadline` (install-start 1440, install-upgrade 1440, sign-in / sign-in-2 / sign-in-3 1500) and are applied by `cmd_live` with a `DEADLINE` line. The first start is `LIVE_FIRST_START_WAIT` (510 s) in 23 scripts. Row 6 is 300 s (ruled), row 7 waits 300 s and 330 s, install-start rows 3 and 4 are 300 s and 270 s. `wait_started_log` prints `MEASURED wait <script>:<line> <s> s of <max> s` on stderr on every return. Rows 6 and 7 and the sign-in suites print their MEASURED lines on both outcomes.

Files changed: `ci/units.sh` (floors), `ci/iris.sh` (floor in `cmd_live`), `docker/tests/lib-live.sh` (constant and MEASURED wait line), 23 first-start live scripts (constant), `docker/tests/test-install-upgrade.sh`, `docker/tests/test-install-start.sh`, `docker/tests/test-sign-in.sh` (budgets and MEASURED lines), `docker/tests/test-ci-config.sh` (budgets rule and `tk_live` floor rows), `docker/tests/test-lib-live.sh` (measured rows), the evidence file and this spec.

Review: 28 findings from the three finding layers; patches applied 3 (empty-start-stamp MEASURED row, non-numeric-deadline floor row, release-sequence `overviewunit` run); deferred none beyond the implement stage's six entries; 25 rejected with the reasons in `## Review Triage Log`. followup_review_recommended false (no patched HIGH, one patched MEDIUM).

Verification: `bash -n` and the ASCII check pass on every changed shell file; `test-ci-config.sh` (budgets rule PASS), `test-lib-live.sh`, `test-ci-warm.sh`, `test-upgrade-harness.sh`, `test-ci-changes.sh` all pass; the three node test files pass (96); `test-release-sequence.sh overviewunit` passes; the implement stage's `ci/iris.sh live audit` ran green on lane B with its throwaway torn down. Mutations are in `## Verification`; both review-pass mutations went red and the tree was byte-identical after each revert. `test-release-sequence.sh` (all rules) and `test-rehearsal.sh` were not run to a verdict (over the 150 s call cap); neither reads the changed scripts.

Residual risks: the install-upgrade, install-start and sign-in budget pins are text pins (the scripts need a live stack); AC 7 (CI green on the pushed head, MEASURED and DEADLINE lines in the logs) waits for CI HOLD OFF and the lead. The five floors raise their groups' worst case toward the job's 40-minute cap (deferred entry for the Planner).

### Rework iteration 1 (DW-1212, DW-1213, DW-1214; this pass only)

Status: done
Blocking condition: none

Summary: four `timeout-minutes` values changed and nothing else in a workflow: ci.yml `iris` 50 and `checks` 25, lane-a.yml `ipm-install` and `ipm-install-p` 45. The two lane-a jobs print `MEASURED <job> N s` at `ci/iris.sh teardown` (N counts from a stamp that `ci/iris.sh build` takes) and, over 2100 s, `over REL-4` to the log and `$GITHUB_STEP_SUMMARY`; `REL4_JOBS` and `REL4_TARGET_SECONDS` are in `ci/units.sh`. Old values in comments and in the evidence file's report-only rows are updated.

Files changed: `.github/workflows/ci.yml`, `.github/workflows/lane-a.yml`, `ci/iris.sh`, `ci/units.sh`, `docker/tests/test-ci-config.sh` (timeout pins, hermetic REL-4 rows), the evidence file and this spec.

Review: 14 findings; patches 2 (medium 1, low 1: positive controls on the negative REL-4 rows, a second-build row and a no-stamp-for-other-jobs check, with three mutations); deferred none; 12 rejected with the reasons in `## Review Triage Log`. followup_review_recommended false (no patched HIGH).

Verification: `bash -n` and the ASCII check on `ci/iris.sh`, `ci/units.sh` and `test-ci-config.sh`; `test-ci-config.sh` all rules passed (budgets rule PASS) before and after the review patches; the implement stage also ran `test-cpf.sh`, `test-ci-changes.sh`, `test-ci-warm.sh` and the three node test files. Mutations are in `### Mutations (Rule 19)`.

Residual risks: AC 7 for these lines (that `GITHUB_JOB` and `GITHUB_STEP_SUMMARY` give the MEASURED and `over REL-4` lines on the runner) is CI's own result on the head, after CI HOLD OFF (the lead). N leaves out the runner's setup and checkout before `build`.
