---
title: 'Story 0.13: A start retries the CPF merge when IRIS cannot quiesce'
type: 'bugfix'
created: '2026-11-03'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `docker/after-start.sh` runs `iris merge` on a fresh copy of `merge.cpf` at every start (AD-23, DW-1). Even an unchanged merge runs several namespace activations. Each one waits up to about 120 s for the system to quiesce and returns ERROR #453 if it can't. The merge then fails, and the start ends not ready (`STEP merge FAILED exit 7`). CI hit this on a fresh first start (run 41419787515, attempt 1) and twice at install-start's restart row (runs 41577358713 and 41577710442, attempt 1). So a user's first start, restart or image update can end not ready.

**Approach:** When a failed merge's output carries `ERROR #453:`, the script pauses briefly and runs the merge once more, on a fresh copy. It writes exactly one countable `STEP merge RETRY <n> after #453` line per retry. Any other failure, and a #453 on the last try, ends not ready exactly as today. A hermetic test with a fake `iris` and a fake `sleep` pins every case.

## Boundaries & Constraints

**Always:**
- Retry only when the merge exits non-zero **and** its output contains the fixed string `ERROR #453:`. At most **1 retry** (2 attempts), with a **10 s** pause before the retry. There is no pause after the last attempt.
- Each retry writes exactly one line, `STEP merge RETRY <n> after #453` (`<n>` = 1 for the first retry), through `say`, so it goes to both stdout and the log. It is written after the failed attempt's output and before the pause.
- Every attempt merges its own fresh temporary copy, made the way the first attempt makes it today (`mktemp -d` and `cp`), and removes it right after that attempt. Every attempt's merge output goes to the log.
- `SECONDS` is reset once, before the first attempt, so `STEP merge OK <n>s` covers all attempts.
- A merge that succeeds on the retry carries on exactly as a first-try success: the same `STEP merge OK` line, then the session and the marker.
- Keep the script's contract: it always exits 0, the log is rewritten at each start, and a failure shows only as a missing marker plus a log line. Keep it portable to bash 3.2 (the macOS test host) and to the image's bash. Comments state the contract (Rule 14). The header's item 2 says that a #453 merge is retried once.
- Keep the `log_file="${OCUTALON_AFTER_START_LOG:-...}"` line's shape, because `test-readme.sh` extracts it. Write ASCII only.

**Never:**
- No edit to `docker/merge.cpf` (byte-unchanged; the orchestrator watches it), `docker-compose.yml` (`start_period` stays 600 s; see Design Notes), `docker/after-start.cos`, `docker/tests/lib-live.sh`, `ci/units.sh`, `release/**`, or any live test's ready limit.
- No new environment override in `after-start.sh`. The test fakes `sleep` on `PATH` instead.
- No retry on any other error, on a copy or temporary-directory failure, or on a near-miss number such as `ERROR #4530:`.
- No skip-merge-when-unchanged rework (that is out of scope; see Design Notes).

## I/O & Edge-Case Matrix

Each row is one run of the script. The merge results come from the fake `iris`. "453" means it prints the real three-line #453 output (below) and exits 7.

| Scenario | Merge results, in order | Expected | Error handling |
|---|---|---|---|
| A: #453 then OK | 453, 0 | Two merges, each of its own copy, both copies removed. The log holds, in order: the first output, `STEP merge RETRY 1 after #453` (once), `STEP merge OK <n>s`. Stdout holds the RETRY line. One `sleep 10`. The session runs, the marker holds the version, and the log ends `ready 0.1.0`. | none |
| B: #453 on every try | 453, 453 | Two merges, one RETRY line (`... RETRY 1 ...`), one `sleep 10` (none after the last try), then `STEP merge FAILED exit 7`. No session and no marker. The log ends `not ready`, and both #453 outputs are in the log. | as today's failure |
| C: another failure | 7 (no output) or `ERROR #5001: ...`, exit 7 | One merge, no RETRY line, no `sleep`, then `STEP merge FAILED exit 7`, not ready. | as today |
| D: near-miss number | `ERROR #4530: ...`, exit 7 | The same as C: no retry. | as today |
| E: #453 then another failure | 453, then `ERROR #5001: ...` exit 7 | One RETRY line, one `sleep 10`, then `STEP merge FAILED exit 7`, not ready. | as today |
| F: first-try success | 0 | One merge, no RETRY line, no `sleep`. Everything else as today. | none |
| G: no copy possible | missing merge file, or no temporary directory | No merge, no RETRY line, no `sleep`, `STEP merge FAILED exit 1` (today's row 8 checks). | as today |

The real #453 output, from run 41419787515 attempt 1 (exit 7):
```
IRIS Merge of /tmp/ocutalon-merge.brYAK4/merge.cpf into /durable/iris/iris.cpf
ERROR #453: Cannot quiesce the system for namespace reactivation
IRIS Merge failed
```

</intent-contract>

## Code Map

- `docker/after-start.sh` (Lane B; Epic 0 may edit it):
  - L2-15: the header contract. Update item 2 there.
  - L23-25: `stamp`, `log` and `say` (`say` = stdout plus the log).
  - L41-60: the merge block. `SECONDS=0` (L42), `mktemp -d` (L43), `cp` and `iris merge IRIS <copy>` with `2>&1` (L47-49), `rm -rf` of the directory (L54), `log "$merge_out"` (L55), `STEP merge FAILED exit $merge_rc` and `finish "not ready"` (L56-59), `STEP merge OK ${SECONDS}s` (L60). Only this block and the header change.
- `docker/tests/test-after-start.sh` (hermetic; `CHECK_SCRIPTS` in `ci/units.sh` L6, i.e. the hosted `checks` job; no open branch touches it):
  - L2-6: the header (what it pins).
  - L18-41: the fake `iris`. `merge` logs `$*` to `FAKE_CALLS`, notes `merge-file-matches`, overwrites `FAKE_MERGE_ARG` with `$3`, and exits `FAKE_MERGE_RC`.
  - L42-47: the fake `mv`, the pattern for a fake `sleep` (record `sleep $*` in `FAKE_CALLS`, exit 0 without sleeping; bash has no `sleep` builtin, so `PATH` decides).
  - L103-127: `run_script` (its second argument is the merge exit). L153-155: the copy and removal checks, which read the single `merge-arg`. L179-204: row 8, the failure cases. The existing checks must keep passing.
- Read only:
  - `docker-compose.yml` L21-26: health check `interval: 10s`, `retries: 3`, `start_period: 600s`.
  - `docker/tests/lib-live.sh` L589-611: `log_steps` keeps every `^STEP ` line, and `check_log` diffs them against `expected_run`. Its callers: `test-install-start.sh` rows 1-4, `test-online-demo.sh` rows 1 and 13, `test-audit.sh` row 10, `test-install-upgrade.sh` row 6, `release/upgrade-harness.sh` L934 and L1213.
  - `docker/tests/test-readme.sh` L674-680 (the `log_file=` extraction).
  - `docker/tests/test-compose-file.sh` L61-85 (`start_period` of at least 600).
  - `irissys/NSPACTIVATE.int` L86-91 (`TurnOnSwitch10`: 12000 x `h .01`, then `$$Error^%apiOBJ(453)`).
  - `irislib/%occErrors.inc` L426 (`CPFReactivateCannotQuiesce` 453).
  - Spine AD-23 (`architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` L761-805).
  - PRD addendum L55 (`prds/prd-OcuTalon-2026-10-16/addendum.md`).

## Tasks & Acceptance

**Execution:**
- `docker/after-start.sh`:
  - Turn the merge block into at most 2 attempts. Each attempt makes, merges and removes its own copy, and logs its output.
  - After a failed attempt: if it was not the last attempt **and** the output contains `ERROR #453:`, `say "STEP merge RETRY <n> after #453"`, run `sleep 10`, and try again. Otherwise `say "STEP merge FAILED exit <rc>"` and finish not ready.
  - Keep `SECONDS=0` before the first attempt. Update header item 2.
  - Rationale: conditions 1 and 4 of U-235. A shell `case` match (`*'ERROR #453:'*`) works on multi-line output under bash 3.2 and runs no subprocess. The implementer may choose another form if it is exactly as narrow.
- `docker/tests/test-after-start.sh`:
  - Let the fake `iris` answer a sequence of merge results. For example, `run_script`'s second argument becomes a space-separated list such as `"453 0"`, kept in a counter file, with tokens for the #453 output, `ERROR #5001:` and `ERROR #4530:` outputs, and plain exit codes.
  - Record every merge's copy path (append, not overwrite).
  - Add a fake `sleep` on `PATH` that records its argument.
  - Add checks for matrix rows A-F. In existing runs (F, G), also check that there is no RETRY line and no `sleep`.
  - Update the header (what it pins).
  - Rationale: condition 3. The test stays in the existing `checks` group, with no new script and no registration change.

**Acceptance Criteria:**
- Given matrix rows A-G, when `bash docker/tests/test-after-start.sh` runs under the host's `/bin/bash` (3.2 on macOS), then every check passes, including the exact RETRY line form, its count (one in A, B and E; none in C, D, F and G), its place before the final `STEP merge` line, its presence on stdout, the pause (`sleep 10` exactly once in A, B and E; none elsewhere), a distinct copy per attempt with every copy removed, and the exit code 0 in every row.
- Given the change, when `git diff` is taken against the story's base, then `docker/merge.cpf` and `docker-compose.yml` are byte-unchanged, and the only source files changed are `docker/after-start.sh` and `docker/tests/test-after-start.sh`. This spec and other files under `_bmad-output/` don't count.
- Given a start where no #453 occurs, when the lead runs `docker/tests/test-install-start.sh` and `docker/tests/test-install-upgrade.sh` on fresh throwaways (lane C), then both pass unchanged within their existing limits, because the STEP sequence of a start without #453 is unchanged.
- Given the pushed head, when CI runs, then `ci` and `lane-a` are green (the lead's gate).

## Spec Change Log

- **2026-11-03, before planning (lead; Rule 5 tier 1, intent kept).** Story 0.13's block in `epics.md` carries `[AMENDED 2026-11-03, Contest Planner under the owner's delegation, U-235 conditions]` (answer 2026-11-03T09:22:15Z#706). Its five binding conditions refine the criteria and win where they differ:
  1. Retry only on ERROR #453, with a short pause and exactly one `STEP merge RETRY <n> after #453` line per retry.
  2. Size the bound against `start_period: 600s` (one #453, the pause, a successful retry and the slowest measured first start), not against the live tests' 400 s and 200 s. This replaces the original third criterion ("stays inside the ready limits the live tests use").
  3. A stubbed test pins #453-then-OK, #453-every-try and another failure, in an existing CI group other than `production`, `browser`, `install-fresh` and `install-upgrade`.
  4. `docker/merge.cpf` stays unchanged, and this is `after-start.sh`'s only change before the 1.0.0 tag.
  5. rc1 includes this story.

  The matrix and the acceptance criteria above carry them. Known-bad state avoided: a retry bound sized against live-test limits it cannot meet.

## Review Triage Log

## Design Notes

**Governing ADs.**
- AD-23 governs: the after-start sequence, the merge at every start on a fresh copy, the always-exit-0 contract, the STEP log, and the health check with `start_period` at least 10 minutes.
- AD-22 governs: the hermetic check stays in the hosted `checks` job.
- AD-29 governs: `docker/` is Lane B's and `merge.cpf` is Lane A's, and only Epic 0 edits both. The footprint is the lead-authorized `test-after-start.sh` in Epic 15's contended `docker/tests/**`.
- AD-19 was checked: no new variable and no override, so it does not bind.
- No criterion contradicts an AD.

**The bound (condition 2): 1 retry, 10 s pause.** Measured on CI's x64 runners:
- 31 `FIRST-START` lines (the demo-path unit: `docker compose up` to healthy) from the last 60 `ci` runs (2026-11-02 15:08Z to 2026-11-03 09:45Z) read 210-326 s, with a mean of 255 s. The slowest is 326 s: run 41495452746, `iris (browser)`, runner `ocutalon-ci-17`, `FIRST-START engine=x86_64 build=7s ready=326s`.
- October's figures were 150-177 s (`epic-0-readme-notes.md`). The package has grown since.
- AD-23's "earlier first start of 5 to 8 minutes" is the PRD addendum's pre-spike estimate for Apple silicon (addendum L55). S1's measurement of about 1 minute superseded it. The spine keeps it only as the reason for the 10-minute margin, so it is not a figure for this image.
- A #453 attempt costs 127 s in all three failures, from `AFTER-START begin` to `end`. The quiesce wait itself is 122 s (09:40:27.36 to 09:42:29.40 in run 41419787515).
- A successful merge takes about 5-7 s (inference: four activations took 5 s before the stuck one). CI prints no `STEP merge OK` lines, because the start log is dumped only on failure.

Worst case for one #453: the slowest first start, which already includes one successful merge, plus the failed attempt, the pause and one probe interval. That is 326 + 127 + 10 + 10 = **473 s <= 600 s**, with 127 s to spare. A second retry would add 137 s and reach about 610 s, past `start_period` at the slowest measured start, so it is not chosen. `start_period` stays 600 s, no test that pins 600 changes, and AD-23's sentence "The 10-minute `start_period` stays" needs no spine update. `install.sh` waits 900 s and the demo host's update waits 1200 s, so both have more room. The live tests' 400 s and 200 s limits are unchanged. Their runs inject no #453, and a natural #453 there still fails them (by time or by diff, below), as it does today.

**Detection.** The real output carries the line `ERROR #453: Cannot quiesce the system for namespace reactivation` (all three runs). The fixed string `ERROR #453:` is the narrowest match that this output carries. A bare `#453` or `ERROR #453` without the colon would also match `ERROR #4530`, which row D pins.

**Decided in-stage.**
- **1 retry and 10 s** (the arithmetic above). The pause is short because IRIS's own 120 s quiesce wait is the real wait. The blocker is unproven: each activation starts a "Purging old application errors" job (pids 2783, 2787 and 2791 in run 41419787515), consistent with the `Config.Startup.ErrorPurge` candidate (inference).
- **A fresh copy per attempt**, not a reused one. Each attempt is then exactly today's proven first try, and nothing depends on whether a failed merge writes a `*.last_merge` record. If it did, a reused path would be skipped and would report a false success.
- **The RETRY line goes through `say`**, like every other STEP line. Stdout reaches `docker compose logs`, which keeps it across restarts of one container, while the log file is rewritten per start. The rehearsal can count either source.
- **`SECONDS` covers all attempts.** The OK figure is what the merge phase cost the start.
- **No override variable.** A fake `sleep` on `PATH` follows the fake-`mv` pattern, and L15's "overridable only so that a test can supply its own files" stays true.

**For the lead.**
- (1) **Out of scope, routed:** the larger rework (no re-merge on an unchanged start; re-create only the missing items) goes to the first daily release after 1.0.0. The lead files the ledger entry.
- (2) **Known interaction:** `lib-live.sh`'s `log_steps` keeps every `^STEP ` line. So a live start that meets a natural #453 and recovers would show `STEP merge RETRY 1 after #453` as a `check_log` diff in the callers listed in the Code Map, `release/upgrade-harness.sh` included. Such a run fails today anyway (not ready), so the retry makes no run worse. Teaching `log_steps` to drop RETRY lines touches Epic 12's `lib-live.sh` and Epic 15's `release/**`, outside this footprint. Recommend filing it with (1), or with Epic 15 if the 38.2 rehearsal uses the harness.

**Integration (Rules 1 and 2).** No new service, module or shared component. The new log line is a consumed surface, pinned at the outermost surface (the log file and stdout of a real script run).
- Consumed-by:
  - Story 38.2's rehearsal counts `STEP merge RETRY` lines across 20 starts.
  - The online demo's 1.0.0 update relies on the retry when the container is recreated.
  - `install.sh` and the compose health check see the ready marker as before.
- Consumes: `iris merge`'s output and exit code (build 154) and `docker/merge.cpf` (unchanged).

**Reuse (Rule 2).** This extends the existing merge block and the existing test's fakes and `run_script`. No sibling is copied.

**Ledger inbox:** none.

## Verification

**Commands:**
- `(loop)` `bash docker/tests/test-after-start.sh`. Expected: `test-after-start: all checks passed`, about 2 s.
- `(loop)` `git diff --exit-code -- docker/merge.cpf docker-compose.yml docker/after-start.cos`. Expected: exit 0.
- `(once)` `bash docker/tests/test-boundaries.sh`. Expected: `all rules passed` (ASCII, no local paths), about 6 s.
- `(once)` `bash docker/tests/test-compose-file.sh`. Expected: `all checks passed`, about 1 s.
- `(once)` `bash docker/tests/test-cpf.sh`. Expected: `all checks passed`, about 1 s.
- `(once)` `bash docker/tests/test-readme.sh`. Expected: `all rules passed` (the `log_file=` extraction), about 10 s.
- `(once)` `bash docker/tests/test-ci-config.sh`. Expected: exit 0, about 60 s.
- `(once)` `bash docker/tests/test-ci-changes.sh`. Expected: `all checks passed`, about 34 s.
- Lead-run at smoke, not implement-stage: `ci/iris.sh live install-start`, then `ci/iris.sh live install-upgrade`, one per call. Each runs on a fresh throwaway with `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=0 stage=smoke'` and an `OCUTALON_RUN_TAG` starting `e0s13` (for example `e0s13s`), with `timeout: 600000`.

**Mutations (Rule 19; the implement stage applies each, sees red, reverts, and records it here):**
- Set the attempts to 1: row A goes red.
- Match `#453` instead of `ERROR #453:`: row D goes red.
- Retry on any non-zero exit: row C goes red.
- Sleep after the last attempt, or change the pause value: the `sleep 10` count check goes red.
- Reuse one copy for both attempts: the distinct-copy check goes red.
- Write the RETRY line with `log` instead of `say`: the stdout check goes red.

**Shared surfaces:** The after-start log's STEP grammar gains one line kind, written only on a #453 retry. No list, menu, roster, schema or count that another test asserts on changes in a run without #453 (see Design Notes, For the lead (2)). `CHECK_SCRIPTS` is unchanged.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
