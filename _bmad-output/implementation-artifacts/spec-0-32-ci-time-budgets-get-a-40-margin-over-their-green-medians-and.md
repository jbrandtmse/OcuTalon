---
title: 'Story 0.32: CI time budgets get a 40% margin over their green medians, and the two load timeouts get MEASURED lines (DW-1082, DW-1195)'
type: 'chore'
created: '2026-11-12'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
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
- Every budget stays finite, so a real hang still fails. A raised budget never shortens, skips, deletes or tags off a test, and the job's own 40-minute cap still ends a run.
- Each changed budget gets a pin in `docker/tests/test-ci-config.sh` or `docker/tests/test-lib-live.sh`, with a demonstrated mutation.
- Lane B: worktree `.worktrees/epic-0b`, branch `OCT-epic0b`. Every live call carries `<lane-B>`: `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=0b stage=<stage>'`, with an `OCUTALON_RUN_TAG` that starts with `e0bs32`. Shell code is ASCII and runs on bash 3.2.
- CI HOLD (Planner, from 18:15Z): the story may be built and committed locally. Its push waits for "CI HOLD OFF", which the lead handles.

**Never:**
- Never edit `.github/workflows/*.yml` (a job timeout change is a RELEASE TOOL hunk for the Planner) or `release/**`.
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
  - `checks` 20 min, `web` 10, `install-macos` 15, `iris` 40 (`:32,47,58,104`); the iris env has `OCUTALON_LIVE_DEADLINE: "1200"`.
  - `lane-a.yml`: 25, 30, 35 and 35 min.

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

**Acceptance Criteria:**
- Given `ci/iris.sh live install-upgrade`, when row 6's upgrade start is waited for, then the log shows `MEASURED row 6: the upgrade took N s to ready` whether it passes or fails, the budget is 300 s, and a start not ready within it fails row 6 (DW-1082). Row 7's two waits behave the same way with their own lines and audited budgets (at least 300 s).
- Given `ci/iris.sh live sign-in`, `sign-in-2` or `sign-in-3`, when the browser run ends, then the log shows `MEASURED live:<unit> suite budget B s` and `MEASURED live:<unit> suite N s`. At the audit's median setup, B is at least max(950, 1.4 x the suite median) (DW-1195).
- Given a unit listed in `unit_live_deadline`, when `ci/iris.sh live` (alone or through `group`) runs it with a lower or unset deadline, then its script runs with the floor and the log shows `DEADLINE live:<unit> D s`. A higher given value and any unlisted unit are unchanged. Integration: the consumer `cmd_live` reads `unit_live_deadline`, and the real unit script sees the value.
- Given any live unit's first start, when it is waited for, then its budget is `LIVE_FIRST_START_WAIT` (the audited value), and every `wait_started_log` return writes one `MEASURED wait` line naming the calling script and line. Integration: the 23 live scripts consume the constant.
- Given the committed evidence file, when it is read, then every budget of Task 0's inventory has a row. Every budget with margin under 1.4 shows a new value at or above 1.4 x, or a stated reason (ruled value or the cap) with a matching `deferred:` entry. The code's values equal the table's new-value column.
- Given the story's diff, when `bash docker/tests/test-ci-config.sh` runs (its unit and group pins unchanged), then it passes, and no test, unit, group or job is added, removed, renamed, moved, skipped or shortened. Every budget is finite: the floors are at most 2,340 s and every wait is a literal or a lib default.
- Given CI on this story's head (pushed after CI HOLD OFF), when it finishes, then every workflow is green. The job logs show the AC 1, AC 2 and AC 4 MEASURED lines and the AC 3 DEADLINE lines.

## Spec Change Log

## Review Triage Log

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
