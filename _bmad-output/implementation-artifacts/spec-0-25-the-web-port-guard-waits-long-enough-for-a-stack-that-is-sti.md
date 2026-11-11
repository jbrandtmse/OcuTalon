---
title: 'Story 0.25: The web-port guard waits long enough for a stack that is still shutting down'
type: 'bugfix'
created: '2026-11-10'
status: 'done'
baseline_revision: '9db150c7ef13bd154dd7fdbb8c91ea47ced94eff'
baseline_commit: '9db150c7ef13bd154dd7fdbb8c91ea47ced94eff'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      docker/tests/test-install-script-live.sh step 5 prints only the last 5 lines of the guard's output, so after a double-retry failure the FAIL web port line and the bind error scroll out of view behind the holder lines.
    evidence: |-
      Step 5 runs `live_port_guard ... 2>&1` into plain_out and prints `tail -n 5`. The guard now ends a failure with the FAIL line, up to 20 PORT holder lines and the waited line. The step still fails on the exit status and the holder lines and the waited line stay visible; the spec's Design Notes say step 5 needs no edit.
    location: >-
      docker/tests/test-install-script-live.sh:153
    severity: low
  - summary: >-
      docker/tests/test-boundaries.sh fails its `keys: nothing key-like` rule on the lead's own cycle-log line 818 (story_created for 0.25): `note=plan_measured_job_130269395421:occupant_...` matches the bot-token shape `[0-9]{8,10}:[A-Za-z0-9_-]{35}`.
    evidence: |-
      `bash docker/tests/test-boundaries.sh` prints `FAIL keys: nothing key-like` listing `_bmad-output/implementation-artifacts/cycle-log-epic-0.md:818` and nothing else; the line is committed at the baseline (9db150c7), outside this story's diff. `ci/checks.sh` runs the script, so the head is red until the line is reworded (for example a different separator after the job id).
    location: >-
      _bmad-output/implementation-artifacts/cycle-log-epic-0.md:818
    severity: medium
---

<intent-contract>

## Intent

**Problem:** Story 0.24's guard in `docker/tests/lib-live.sh` gave up too soon. On ocutalon-ci-8 at 02:21Z (run 42943118887, `live:online-allowance`), it retried once after 5 s and then printed `FAIL web port: 127.0.0.1:52818 could not be bound after one retry`. Its loud failure also does not say what holds the port, so this recurrence gives no more diagnosis than the first (DW-1099, DW-1100).

**Approach:** This follows the Contest Planner's ruling (c). The guard waits up to 90 s for the port, polling every 3 s. On exactly the bind error it retries up to twice, then prints the same loud `FAIL web port: ...` line. Every guarded start that waited prints one `waited N s for port P` line. The loud failure and `PORT still in use` also list what holds the port. All of this lives in the one start path, `dc`. Nothing changes in `ci/iris.sh`, the workflows or `release/**`.

## Boundaries & Constraints

**Always:**
- A guarded start is `dc up`, `dc start` or `dc restart` (the first argument) with `${web_port}` set. Every other `dc` call, and every call with no web port, runs exactly as it does today.
- Each guarded start has one port-wait budget of `LIVE_PORT_WAIT` seconds (default 90). It polls every 3 s through `wait_until`, which never waits past the run's `deadline`.
  - The pre-wait and the wait before each retry share that one budget.
  - The pauses before the retries (`LIVE_PORT_RETRY_PAUSE`, default 10 s) are extra, outside the budget.
- Retry only when a guarded start exits non-zero and its stderr contains `address already in use` or `failed programming external connectivity`. Retry at most twice. Any other failure, including one on a retry, returns its status at once.
- `waited N s for port P` is printed exactly once per guarded start that waited, after its last attempt. "Waited" means the pre-wait found the port in use, or a retry ran. N is the whole seconds (`$SECONDS`) spent in that start's port waits and pauses. A start that did not wait prints no such line.
- The holder lines are printed after the loud FAIL and after `PORT still in use`. They are bounded and only print: they never change the guard's status.
- Keep 0.24's invariants:
  - `OCUTALON_TEST_WEB_PORT` is the override, with the same range and refusals.
  - The port is published on `127.0.0.1` only.
  - `LIVE_FORBIDDEN_PORTS` is unchanged.
  - The pre-wait is skipped when the project's own container publishes the port.
  - `LIVE_PORT_WAIT=0` refuses a held override silently.
- Shell code stays ASCII only and runs on bash 3.2 with BSD or GNU tools.

**Never:**
- Any hunk in `ci/iris.sh`, `.github/workflows/*`, `release/**`, `web/**` or `_bmad/**`.
- 0.24's fix (1): a port Docker picks, or a different port range.
- A real 90 s sleep in a hermetic test.
- A local absolute path in a tracked file.
- Deleting or weakening an existing row. A 0.24 row changes only the numbers and wording that the new bounds replace.

## I/O & Edge-Case Matrix

These are hermetic rows in `test-lib-live.sh`, run through `guard_run`. Its `sleep` stub records the seconds and advances `SECONDS` by them (the fast clock), and `deadline` is `SECONDS + 1000`. "Checks" means calls to `port_in_use`.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Defaults (90 s bound) | `lib-live.sh` sourced with both knobs unset | `LIVE_PORT_WAIT=90`, `LIVE_PORT_RETRY_PAUSE=10` | -- |
| Held briefly (DW-1099) | busy for 3 checks; outcome `ok` | `PORT waiting: ... waiting up to 90 s`, then `PORT free`; 1 compose; one `waited 6 s for port 52803` | -- |
| Held for good | busy for every check; `ok` | 30 sleeps, all of 3 s; 32 checks; `PORT still in use ... after 90 s; starting anyway`, then `PORT holder:` lines; 1 compose; one `waited 90 s for port 52803` | The start decides (rc 0) |
| Freed after the last poll | busy for 31 checks | 30 sleeps, 32 checks, `PORT free`, no `starting anyway` | -- |
| Deadline | busy for every check; `deadline=SECONDS+30` | 10 sleeps, not 30; `starting anyway` | -- |
| Bind, then ok | port free; `bind-mac ok` | 2 composes with identical arguments; `PORT retry: <line>; retry 1 of 2 in 10 s`; sleeps `10`; one `waited 10 s ...`; no FAIL | Retried |
| Bind twice, then ok | `bind-mac bind-ci ok` | 3 composes; `retry 1 of 2`, then `retry 2 of 2`; sleeps `10 10`; rc 0; one `waited 20 s ...` | Retried twice |
| Bind three times | `bind-ci bind-ci bind-ci` | exactly 3 composes; `FAIL web port: 127.0.0.1:52803 could not be bound after two retries: <line>`; holder lines; stderr holds 3 bind lines; one `waited 20 s ...` | Non-zero rc |
| Shared budget | busy for every check; `bind-ci` x3 | 32 sleeps in all (30 of 3 s, then 10, 10); 3 composes; one `waited 110 s ...`; FAIL | Non-zero rc |
| Other error | port free; `other` | 1 compose, no `PORT retry`, no `waited` line | rc 1, not retried |
| Other error on a retry | `bind-mac other` | 2 composes, one `PORT retry`, no `FAIL web port`, one `waited 10 s ...` | rc 1, no further retry |
| No wait | own stack (`restart iris`, `up -d`); no web port; `exec`/`ps`/`down`; free port and `ok` | no `waited` line, other rows as in 0.24 | -- |
| Own stack, bind error | own=1; `bind-mac ok`; `start iris` | 2 composes; one `waited 10 s ...` | Retried |
| Override waited (`live_web_port`) | `OCUTALON_TEST_WEB_PORT=52815`, busy for 2 checks, fast clock | accepted; one `waited 3 s for port 52815` | -- |
| Holders named (DW-1100) | FAIL path; `docker ps -a` stub lists `other-iris-1 Up 2 minutes project=other`; `ss` stub lists `ESTAB ... 127.0.0.1:52803 ...`, a neighbour `:528030` and 30 more matching lines | `PORT holder: other-iris-1 Up 2 minutes project=other`, plus at most 10 `PORT holder:` lines from `ss` (the `ESTAB` one included, the neighbour excluded); the holder query has `-a` and `--filter publish=52803` and no `label=` filter | -- |
| Holder tools fail | `docker ps` exits 1; no `ss` and no `lsof` | `PORT holder: none seen`; the FAIL line and the start's rc are unchanged | Never fails the guard |
| Teardown is foreground | the tracked `docker/tests/*.sh`, `ci/*.sh` and `release/*.sh` | no `dc down` or `docker compose ... down` line ends in `&`; `live_cleanup`'s `dc down -v --rmi local` is unchanged | -- |

</intent-contract>

## Code Map

- `docker/tests/lib-live.sh`
  - `:23-25` -- the header sentence on the guard. Restate it: 90 s, the shared budget, up to two retries, the `waited` line and the holder lines.
  - `:203-205` -- the knobs: `LIVE_PORT_WAIT` 20 -> 90, `LIVE_PORT_RETRY_PAUSE` 5 -> 10.
  - `:209-221` -- `live_port_listed` (`ss -ltn`, else `lsof -sTCP:LISTEN`). Lead ruling at the spec gate (see Design Notes): on the `ss` branch, list TCP sockets in every state (`ss -tan`) and count the port as in use when a socket whose local address is `127.0.0.1:<p>`, `0.0.0.0:<p>`, `*:<p>`, `[::]:<p>` or `[::ffff:127.0.0.1]:<p>` is in any state except `TIME-WAIT` (LISTEN keeps counting). A socket on another local address, or in `TIME-WAIT`, does not count. The `lsof` branch (macOS) is unchanged. Update the comment above it.
  - `:230-243` -- `live_port_wait_free <p>`. Extend it with an optional `[<max s>]` (default `LIVE_PORT_WAIT`). It is silent and returns 1 when max <= 0 and the port is busy. Its `PORT waiting ... up to <max> s` and `PORT free` lines keep their text.
  - `:245-289` -- `live_web_port`. The override branch (`:271`) gets the 90 s through the shared knob. It prints one `waited N s for port P` when its wait found the port in use.
  - `:292-310` -- `dc_compose` and `dc`. Unchanged.
  - `:312-317` -- `live_bind_error`. Unchanged; it keeps the 200-character cut.
  - `:319-349` -- `live_port_guard`. Rework it in place:
    - a budget local;
    - a retry loop for k = 1..2: `PORT retry: <line>; retry <k> of 2 in <pause> s`, the pause, the wait with the remaining budget, then the attempt with the same stderr capture and replay;
    - FAIL `... after two retries: <line>`;
    - the holder lines;
    - one `waited` line before `return`.
  - New `live_port_holders <p>`, beside the guard. It prints `PORT holder: <line>`:
    - `docker ps -a --filter "publish=<p>" --format '{{.Names}} {{.Status}} project={{.Label "com.docker.compose.project"}}'`, across all projects;
    - the `ss -tanp` lines whose local address ends in `:<p>`, in any state (else `lsof -nP -iTCP:<p>`);
    - at most 10 lines from each source, each tool run once (under `timeout 10` where the host has `timeout`);
    - `PORT holder: none seen` when nothing is found. It always returns 0.
  - `:367-373` -- `live_cleanup`. A foreground `dc down -v --rmi local` in the EXIT trap. Read only.
  - `:388-400` -- `wait_until`. It counts by its own 3 s sleeps and stops at `deadline`. Reuse it.
  - `:587-588` -- `live_first_start` greps `^PORT` from `first-up.log`. Widen it to `^(PORT|waited )` so the `waited` line shows beside FIRST-START (AD-23).
- `docker/tests/test-lib-live.sh`
  - `:41-48` -- the guard bullet of the header. Restate it with the new bounds.
  - `:554`, `:564` -- the comment "20 s" -> 90 and the restore `LIVE_PORT_WAIT=20` -> 90.
  - `:596-678` -- `guard_run` and its helpers:
    - set 90 and 10 (`:605-606`);
    - the `sleep` stub also advances `SECONDS`;
    - the `docker` stub answers `ps -a ...` (the holder query) apart from the own-stack `ps -q ...`;
    - stub `ss`/`lsof` as functions where a row needs them.
  - `:680-792` -- the 0.24 rows. Update only these bound numbers and wording:
    - "up to 20 s" -> "up to 90 s";
    - 7 sleeps / 9 checks -> 30 / 32 (busy 8 -> 31);
    - pause `5` -> `10`;
    - "retrying once in 5 s" -> "retry 1 of 2 in 10 s";
    - the bind-twice row (`:706-713`): outcomes `bind-ci bind-ci` become a "bind twice, then ok" row, and a new three-bind row carries "after two retries" and 3 composes.
  - Leave as they are:
    - `:794-812` -- the `LIVE_PORT_WAIT=0` row;
    - `:814-845` -- the step-5 rows (`PORT retry: ` still matches);
    - `:849-877` -- the override row.
  - `:1043-1048` -- the `PORT|FIRST-START` row stays. Add a sibling row in which the `up` stub also prints a `waited` line.
  - Baseline at 0.24's close: 156 PASS, about 65 s.
- `docker/tests/test-ci-config.sh:1527` -- `LIVE_PORT_WAIT=0` in `live_port_checks`. It stays, and stays true. Read only.
- `docker/tests/test-ci-warm.sh:168,437-441` -- `^PORT` pins on `ci/iris.sh`'s own `PORT the web port ...` line. A warm or class run has no web port. Unaffected; read only.
- Read only, checked for the teardown AC (no backgrounded or unwaited teardown found):
  - `ci/iris.sh:712-742` (`cmd_group` runs each unit as a foreground `bash ci/iris.sh <kind> <arg>`);
  - `:806` (`teardown`, foreground);
  - `ci/warm.sh:161`, `release/rehearse.sh:972` and `docker/tests/test-online-session.sh:53` (`live_cleanup` in the EXIT trap);
  - `docker/tests/test-install-script-live.sh:35,134`;
  - `release/ipm-install.sh:1858,2176` (foreground `dc down -v`);
  - `release/upgrade-harness.sh:1937-1987` (foreground `bash "$me" down`).
  - The background jobs in `test-online-session.sh:176`, `test-online-load.sh:760`, `test-session-data.sh:277` and `release/demo-load.sh:742` are clients, not teardowns, and are waited for.
- `ci/compose.ci.yml:37` -- `stop_grace_period: 2s` (`docker-compose.yml:13` 60s). Read only.

## Tasks & Acceptance

**Execution:**
- `docker/tests/lib-live.sh` -- Rework the guard as the Code Map says: the knobs, the `[max]` of `live_port_wait_free`, the shared budget and up to two retries in `live_port_guard`, `live_port_holders`, the `waited` line (guard and override), the `live_first_start` grep, and the header and doc comments. Rationale: the ruling's bounds and DW-1100's holder diagnosis, both in the one start path (DW-1099, DW-1100).
- `docker/tests/test-lib-live.sh` -- Add every I/O matrix row as a PASS/FAIL check in the block `the start's port guard (Story 0.24; bounds of Story 0.25)`. Make the stub and 0.24-row changes listed in the Code Map, add the teardown static row, and update the header bullet. No existing assertion is dropped. Rationale: the ruling's tests, with a fast clock so nothing sleeps 90 s.

- `docker/tests/test-lib-live.sh` -- Lead ruling rows for `live_port_listed`'s `ss` branch (stub `ss` as a function that prints `ss -tan`-shaped lines and records its arguments): an `ESTAB` socket with local `127.0.0.1:52803` counts as in use; a `LISTEN` one on `0.0.0.0:52803` counts; a `TIME-WAIT` one on `127.0.0.1:52803` does not; an `ESTAB` one on `10.0.0.5:52803` does not; a neighbour `127.0.0.1:528030` does not; the poll's `ss` call carries `-a` (all states). Mutation: restore `ss -ltn` (listening only) -> the ESTAB row goes red. Rationale: the 02:21Z occupant was invisible to `ss -ltn` (Measured, below), so a wait that cannot see a non-listening holder could not have helped (DW-1099).

**Acceptance Criteria:**
- Given `docker/tests/lib-live.sh`, when a guarded start finds its web port in use, then:
  - it polls every 3 s for up to 90 s, which the pre-wait and both retries' waits share, and never waits past the run's deadline;
  - on exactly the bind error it retries up to twice, each after a 10 s pause and a wait, and after the second retry it prints `FAIL web port: 127.0.0.1:<p> could not be bound after two retries: <line>` and returns the failure;
  - any other failure returns at once;
  - exactly one `waited N s for port P` line is printed for each guarded start that waited, and none for one that did not (DW-1099).
- Given the loud FAIL or `PORT still in use`, when it is printed, then `PORT holder:` lines follow. They list every container of any project that publishes the port, and every TCP socket in any state with local port P, at most 10 lines per source, or `PORT holder: none seen`. The guard's status is unchanged (DW-1100).
- Given every live script's and release harness's teardown path, when a unit ends, then its teardown runs in the foreground and finishes before the next unit. The paths, checked read-only, are listed in the Code Map. None is backgrounded, so no fix is needed, and the static row pins it.
- Given `test-lib-live.sh` (with `bash` and `/bin/bash` 3.2), `test-boundaries.sh`, `test-ci-config.sh`, `test-ci-warm.sh` and `test-ci-changes.sh`, when they run, then all pass. Every existing assertion is kept, and only the bound numbers and wording change.
- Given a lane-B throwaway, when a listener holds the web port for about 40 s after `live_web_port`, then `dc up` waits it out, starts, and logs `waited N s for port 52802`. When the listener holds it past 90 s, the start retries twice and then prints the loud FAIL and the holder lines.
- Integration AC: given consumer `docker/tests/test-online-allowance.sh` (CI `iris (shards)` `live:online-allowance`, the unit DW-1099 hit, starting through `dc up` on the runner's fixed port), when CI runs on the story's head, then the unit passes. Any wait it made appears as `waited N s for port P` in the job log, and every workflow is green.

### Review Findings

Code review (bmad-code-review, 2026-11-11; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 32 rows, 9 entries after grouping, 13 rejected).

- [x] [Review][Patch] Rule 2: `override_run` (QA) was a near-copy of the inline override block of the "override held briefly" row; that row now calls `override_run 2` [docker/tests/test-lib-live.sh:1152] -- med, fix-risk low (test-only refactor, same assertions), in-story.
- [x] [Review][Patch] Rule 19 hermeticity: the "override held briefly" row's `port.yml` assertion could pass on the 52815 file left by `override_run 0`; `override_run` now removes `port.yml` first [docker/tests/test-lib-live.sh:1039] -- med, fix-risk low (one `rm -f`), in-story.
- [x] [Review][Patch] The guard's clock `t` started before the own-stack `docker ps -q`, so that query's time counted in `PORT still in use ... after N s`, in the budget and in `waited N s`; `t` is now taken right before the pre-wait [docker/tests/lib-live.sh:379] -- low, fix-risk low (one line). No hermetic pin: the query runs in a command substitution, so the fast clock cannot advance from it (tried; the row stayed green under the mutation and was removed). The lead's proofs A and B show the real figure.
- [x] [Review][Patch] The `ss` listener-table row accepted any arguments containing ` -tan `, so `ss -tan state listening` (listeners only again) stayed green; it now requires exactly `-tan` [docker/tests/test-lib-live.sh:1203] -- low, fix-risk low.
- [x] [Review][Patch] The bind-three-times row's `[ "$(g_holders)" -ge 1 ]` was met by any holder output; it now requires exactly the one `PORT holder: none seen` line its stubs produce [docker/tests/test-lib-live.sh:780] -- low, fix-risk low.
- [x] [Review][Patch] The teardown scan missed a trailing comment after `&`, `docker-compose ... down`, `live_cleanup &`, `ci/iris.sh teardown &` and `"$me" down &`; it now strips a trailing comment and matches those forms (a multi-line `( ... ) &` is still not scanned, as the comment says) [docker/tests/test-lib-live.sh:1267] -- low, fix-risk low.
- [x] [Review][Patch] DW-1113: step 5 of `test-install-script-live.sh` printed only `tail -n 5`, so the holder lines could hide the FAIL and retry lines; it now prints every guard line (`PORT`, `FAIL web port`, `waited`) and then the last 5 other lines, pinned by a static row in `test-lib-live.sh` [docker/tests/test-install-script-live.sh:154] -- low, fix-risk low; ledger DW-1113 resolved-by this story.
- [x] [Review][Defer] The `ss -tan` poll counts FIN-WAIT-1/2, CLOSING and LAST-ACK sockets as busy, though server-side ones inherit SO_REUSEADDR and may not block the bind [docker/tests/lib-live.sh:218] -- deferred: maybe-false (medium if true; harm is delay inside the 90 s budget, never a failed start); spec-bound by the lead's spec-gate ruling, so DW-1115 `by-design`; a CI log with `PORT waiting` while the holder lines list only those states would settle it.
- [x] [Review][Defer] `epics.md:1659` and `epic-0-context.md:40` still say the poll uses `ss -ltn` [_bmad-output/planning-artifacts/epics.md:1659] -- deferred: low, planning artifacts outside this story's footprint; DW-1116 `wontfix-accepted` with a reopen probe.

Rejected:
- false: `docker ps --filter publish=<p>` matches the container port, so the holder query and the own-stack skip never match (verification-gap, twice) -- measured on engine 29.7.2: `publish=52791` returns `ocutalon-slot-b` (host 52791 -> 52773), and `publish=52773` returns only the container whose HOST port is 52773, not the slots that map to 52773 inside.
- false: `docker ps -a` lists no exited container, so "none seen" misleads (blind, edge) -- measured true that exited ones are not listed, but an exited container holds no port; a socket that does hold it shows in the `ss`/`lsof` half.
- false: `LIVE_PORT_RETRY_PAUSE=0` prints `waited 0 s` after a retry (edge) -- the spec defines "waited" as "a retry ran".
- false: the teardown row fails from a copy with no `.git` (edge) -- a loud failure in a setup no runner uses; the empty-list check was added on purpose by the previous review.
- low: no holder lines when a retry succeeds (blind) -- AC2 names exactly when they print; the FAIL listing runs right after the last bind error, while the occupant is there.
- low: unprivileged `ss -tanp` shows no process for root sockets (blind) -- print-only diagnostic; the socket line still shows; the fix needs privileges.
- low: non-numeric `LIVE_PORT_WAIT` breaks the arithmetic (edge) -- an internal knob, the same as in 0.24.
- low: `LIVE_PORT_WAIT=0` on a guarded start prints no waited line although the pre-check found the port in use (auditor) -- a 0 s budget is no wait; the QA row pins that reading and `PORT still in use ... after 0 s` already shows the busy port.
- low: AC4, AC5 and the Integration AC have no `mutation:` line; the real `timeout`, `docker ps -a`, `ss -tanp` and `lsof` holder calls run only against stubs (verification-gap) -- AC4 is the suites; AC5 and the Integration AC are the lead's live proofs and CI, which also exercise the real holder tools.
- low: stale `deferred:` item 2 and Residual-risks line on `test-boundaries.sh` (the line was reworded at 59db3869; the suite passes), the review tally that sums to 32, and the Auto Run Result's 169 PASS (blind, auditor) -- the fix is to edit build-auto's own record in this spec; the lead's bookkeeping.

## Spec Change Log

- 2026-11-11 (lead, after code review): the second `deferred:` item (test-boundaries red on a cycle-log line) was resolved by the lead before any push (59db3869 reworded the line; ledger DW-1114 resolved); `test-boundaries.sh` passes. The suite count after QA and review is 179 PASS. epics.md's Story 0.25 AC now says `ss` (every state but TIME-WAIT), amended with a marker (DW-1116).

## Review Triage Log

### 2026-11-11 - Review pass
- verdicts: 28 findings - high 0, medium 3, low 22, false 3, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: holder lookups run before `spent` is measured, so they eat the retry budget and inflate `waited N s` -- real (the first wait's `spent` was taken after `live_port_holders`); patched: `t_end` is taken right after the wait and used for both the "after N s" figure and `spent`; pinned by a new row with a 7 s holder listing.
  - `[low]` `[defer]` Blind: step 5 of `test-install-script-live.sh` prints `tail -n 5`, which can hide the FAIL line behind the holder lines -- real but in a file the story does not change (Design Notes: step 5 needs no edit); the status and the holder lines still show; deferred (low).
  - `[low]` `[reject]` Blind: many tests discard the guard's lines (`dc up >/dev/null 2>&1`) -- pre-existing call sites of other scripts; the lines go to stdout and each script chose to drop them; the fix is a per-script change beyond a direct correction.
  - `[low]` `[reject]` Blind: the `lsof` fallback does not see non-listening sockets, and a comment on the auto-pick says "nothing listens on" -- the lead ruling at the spec gate keeps the `lsof` branch unchanged and widens only the `ss` branch; a comment nuance is cosmetic.
  - `[low]` `[reject]` Blind: the `lsof` branch and the `docker ps` cap of `live_port_holders` are untested -- the `docker ps` cap is now pinned (patched with the holders-named row: 12 containers, 20 lines); the `lsof` branch is the macOS fallback of a print-only diagnostic that cannot change the guard's status.
  - `[medium]` `[patch]` Blind (with Verification-gap): the teardown static row can pass with an empty file list -- real (a missing `git` or a broken pathspec makes `bg_down` empty); patched: the row also requires a non-empty file list; its scan half is pinned by a new mutation line.
  - `[low]` `[reject]` Blind: nothing runs the real `timeout` wrapper; macOS has none -- the spec says "under `timeout 10` where the host has `timeout`"; the holder query is print-only.
  - `[false]` `[reject]` Blind: the test header's "about a minute" is stale -- the script still takes about 62 s (real waits elsewhere in it).
  - `[low]` `[reject]` Edge: the retry pauses pass the run's deadline -- the Design Notes state it ("the pauses and the attempts can pass the deadline by about 20 s"); the spec bounds only the polls.
  - `[low]` `[reject]` Edge: `lsof -iTCP:<p>` also matches a remote port -- the spec names that command; print-only diagnostic.
  - `[low]` `[reject]` Edge: `live_bounded` has no bound without `timeout` -- same as the Blind finding above.
  - `[low]` `[reject]` Edge: `wait_until` overshoots a budget that is not a multiple of 3 by up to 2 s -- the spec fixes the 3 s poll; the overshoot is bounded and cosmetic.
  - `[medium]` `[patch]` Edge (same root cause as the Blind teardown finding): the scan can pass vacuously -- patched with the non-empty file list.
  - `[low]` `[reject]` Edge (claim): the wait "never waits past the deadline" does not cover the pauses -- by design, see the first Edge row.
  - `[low]` `[reject]` Edge (claim): the holder lines may not list a half-removed container or a remote-port socket -- print-only diagnostic and the spec's command shape.
  - `[low]` `[patch]` Verification-gap: a different failure on the second retry is not pinned (the FAIL line could be printed for it) -- code correct, row missing; patched: a `bind-mac bind-ci other` row; mutation demonstrated.
  - `[medium]` `[patch]` Verification-gap: no row has a retry wait that polls with a non-zero budget, so the carry-over of the budget and the waited seconds were unpinned -- patched: a hook (`g_bindbusy`) and two rows (free at the pre-check and busy after the bind error: `10 3 3 3`, waited 19; pre-wait 30 s, retry 60 s, retry 0 s: waited 110); the mutations of the finding turn them red.
  - `[low]` `[reject]` Verification-gap: the `lsof` branch and the `timeout 10` bound have no executed test -- the gap's own disposition was defer; diagnostic-only on the macOS path, so closed like the Blind row.
  - `[low]` `[patch]` Verification-gap (other): the holder-tools-fail row compared its status with a variable of the previous row -- patched: the redundant comparison is gone and the literal status remains.
  - `[low]` `[reject]` Verification-gap (other): the bind-three-times row's `-ge 1` holder check is met by `none seen` -- the holders-named row pins real holders.
  - `[low]` `[reject]` Verification-gap (other): the `timeout` stub drops its argument -- a pass-through stub for the hermetic run; the bound is the spec's "where the host has `timeout`".
  - `[low]` `[reject]` Verification-gap (other): AC4, AC5 and the Integration AC have no mutation line -- the spec itself says AC4's falsifiable parts are the rows above and AC5 and the Integration AC are live observations owned by the lead.
  - `[false]` `[reject]` Intent: `live_web_port` prints a `waited` line, which is not a guarded start -- the Design Notes decide it ("Decided in-stage, live_web_port") and a row pins it.
  - `[false]` `[reject]` Intent: `live_port_listed` widens to every state but TIME-WAIT -- the lead's ruling at the spec gate, in the Code Map, the Tasks and the Design Notes.
  - `[low]` `[reject]` Intent: the teardown row is a repo-wide `git ls-files` check -- it is the spec's AC3 and its static row.
  - `[low]` `[reject]` Intent: the holder cases use canned `docker`, `ss` and `timeout` output, not the real tools -- hermetic by the spec's rule; the real-listener proofs are the lead-owned lane-B proofs.
  - `[low]` `[patch]` Intent: N includes the holder listing time -- same root cause as the first Blind row; patched there.
  - `[low]` `[patch]` Intent: no row has a retry wait shortened by a part-spent budget -- same root cause as the Verification-gap budget row; patched there.

## Design Notes

**Measured (plan stage, read-only, from job 130269395421's log):**
- The unit before `live:online-allowance` on ci-8 was `shard:lane-a@Install,Digest,Eval`. A shard publishes no web port. Its foreground teardown ended at 02:21:31 (`SHARD passed` 02:21:19, `UNIT passed` 02:21:31).
- The failing unit ran from 02:21:31 to 02:21:48, 17 s in all. Its first attempt failed at about 02:21:35 and the retry at 02:21:44. So the pre-wait found the port free: the occupant was invisible to the connect check and to `ss -ltn`, and it was not a previous unit's stack.
- The log shows only the up log's tail, so whether the retry's wait saw the port busy is unknown.
- Inference: an outgoing connection's ephemeral source port (52800-52819 lies inside Linux's default `ip_local_port_range`, 32768-60999), or a port reservation of another project's container.
- The holder lines therefore cover every TCP state and every project.
- For the lead to report:
  - If the holder lines show a non-listening socket, the real fixes are a port range outside the ephemeral range or fix (1). Both change `ci/iris.sh` and Rule 21's port scheme, so they are out of scope here. The ruling's `ss -ltn` poll would then need an amendment to cover all states.
  - The longer pause (10 s) is this story's lever for an invisible occupant.

**Lead ruling at the spec gate (2026-11-11, category=decide, reported in PART READY):** the poll's Linux check widens from `ss -ltn` (listening sockets) to `ss -tan` restricted to the publish addresses (`127.0.0.1`, the wildcards and the v4-mapped loopback) in every state except `TIME-WAIT`. Why: the Measured block shows the occupant was invisible to `ss -ltn` and the connect check, and a loopback client socket whose ephemeral source port is the web port (52800-52819 lies inside `ip_local_port_range`) is a bound, non-listening socket that refuses Docker's bind. `TIME-WAIT` stays excluded: Docker's listener sets `SO_REUSEADDR`, so it does not block the bind, and counting it would add up to 60 s after every stack that served HTTP on the port. This keeps the ruling's intent (wait up to 90 s, every 3 s, for the port to be free) and its mechanism (`ss`); only the socket states the check sees are widened. (inference: not measured on a CI host; the holder lines of DW-1100 will show it.)

**Decided in-stage:**
- **Budget.** One 90 s budget per guarded start, shared by the pre-wait and both retries' waits, rather than 90 s again per retry.
  - The worst case is about 90 + 10 + 10 s plus three attempts: about 110 s of waiting, not about 290 s.
  - The held-past-90 s proof then fits one call of about 150 s.
  - `wait_until` still stops every poll at `deadline`. The pauses and the attempts can pass the deadline by about 20 s plus the attempts' own time. Each retry reuses the caller's arguments, `--wait-timeout` included, as in 0.24.
- **Pause.** 10 s before each retry (0.24 used 5). The 02:21Z retry after 5 s failed, and when the check cannot see the occupant, the pause is the only spacing between attempts. Both knobs are implementation values.
- **N.** The whole seconds of `$SECONDS` spent in all of one guarded start's port waits and pauses, not the attempts. It is printed once, at the end of the guard, before `return`. The tests advance `SECONDS` in the `sleep` stub.
- **`live_web_port`.** Its override wait uses the same knob, so up to 90 s. In CI the port is always an override, so a port that is held before a unit starts is waited for here. This site therefore also prints one `waited N s for port P` line when it waited. It is not a guarded start, and the guarded-start rule stays exactly one line each.
- **0.24's lines stay.** `PORT waiting`, `PORT free` and `PORT still in use` keep their formats. `PORT retry: <line>; ` keeps its prefix; only the tail becomes `retry <k> of 2 in <s> s`. The FAIL line keeps `FAIL web port: 127.0.0.1:<p> could not be bound after ` and ends `two retries: <line>`.
  - No `ci/iris.sh`, workflow or release file greps any of them: checked with `git grep`. Only `test-lib-live.sh` does, and `test-ci-warm.sh`'s `^PORT` pins match `ci/iris.sh`'s own line.
- **Header text.** The `lib-live.sh` header and the `test-lib-live.sh` bullet state the new bounds. No README or doc mentions the guard (checked).

**Teardown finding (ruling's check, read-only):** every teardown is foreground and waited for (the Code Map lists them). Nothing is in scope to fix, and nothing in `ci/iris.sh`, a workflow or `release/**` needs reporting.

**Ledger inbox:**
- DW-1099 is addressed by the guard task and AC1. Its rows are the held-briefly, held-for-good, bind and shared-budget rows, plus the lane-B proof and the Integration AC. Residual risk (Measured above): if the occupant stays invisible to the check, only the two 10 s pauses help.
- DW-1100 is addressed by `live_port_holders`, AC2, and the holders-named and holder-tools-fail rows.
- Declined DW-1101: running step 5 hermetically needs the whole live script stubbed (fix-risk med). Its reopen condition was not met at 02:21Z. Step 5 gets the new retries through `live_port_guard` with no edit. It returns to wontfix-accepted, with reopen_if `install-script-live` shows a bind error at step 5 with no `PORT retry` line before it.

**Governing ADs:**
- AD-22: throwaway stacks and CI. The change stays in the throwaway recipe and keeps the docker-call bans; `docker ps --format` is allowed.
- AD-23: `live_first_start`'s ready figure can include the wait, and the `waited` line is shown beside it.
- AD-29: Epic 0 may edit any lane's files.
- No AD is amended.

**Extend, don't copy:**
- `live_port_guard`, `live_port_wait_free` (gains `[max]`) and `live_bind_error` are extended in place, and `wait_until` is reused.
- `live_port_holders` is new. It shares `live_port_listed`'s tool choice (`ss`, else `lsof`).

**Integration:**
- Consumed-by: every live script that calls `live_web_port` and then `dc up/start/restart`, through `ci/iris.sh live` and `group`, and the release harnesses through `dc`.
- Consumes: Story 0.24's guard.

## Verification

Shared surfaces:
- The guard's line formats: the `PORT retry` tail, the FAIL line's suffix, and the new `waited` and `PORT holder:` lines.
- The `LIVE_PORT_WAIT` and `LIVE_PORT_RETRY_PAUSE` defaults, and `test-ci-config.sh`'s `LIVE_PORT_WAIT=0`.
- `test-lib-live.sh`'s PASS count.
- `live_first_start`'s printed lines.
- No `ci/iris.sh` grep and no `test-ci-config.sh` pin changes.

Standing criterion: every test added or changed passes on a fresh environment, in either order. The hermetic scripts are single processes with their own temporary folders.

**Commands** (from the worktree root, one per call, each under about 150 s):
- `bash docker/tests/test-lib-live.sh` (loop, about 65 s) -- expected: `test-lib-live: all checks passed`, 156 PASS plus the new rows.
- `bash docker/tests/test-boundaries.sh` (loop, about 11 s) -- expected: `test-boundaries: all rules passed`.
- `/bin/bash docker/tests/test-lib-live.sh` (once) -- expected: the same under bash 3.2.
- `bash docker/tests/test-ci-config.sh` (once, about 40 s) -- expected: every PASS line.
- `bash docker/tests/test-ci-warm.sh` (once, about 50 s) -- expected: `test-ci-warm: all checks passed (including the DW-164 block)`.
- `bash docker/tests/test-ci-changes.sh` (once, about 17 s) -- expected: all pass.
- `for f in docker/tests/lib-live.sh docker/tests/test-lib-live.sh; do LC_ALL=C tr -d '\011\012\040-\176' < "$f" | wc -c; done` (once) -- expected: two lines of 0.
- `git diff --name-only 524f590fea135c29ad545c11897cfd6c69a679df -- ci/iris.sh .github release web _bmad` (once) -- expected: empty.
- Lead-owned (once, at smoke). These need the lane-B variables `OCUTALON_LOCK_DIR=<lock-dir>/lane-b`, `OCUTALON_TEST_WEB_PORT=52802` and `OCUTALON_LOCK_OWNER='epic=0 stage=<stage>'`, and `HOLD` set to 40 for proof A and 200 for proof B, one call each, about 60 s and about 135 s:

  ```
  OCUTALON_RUN_TAG=e0s25proof HOLD=40 bash -c '. docker/tests/lib-live.sh; live_start proof; live_web_port || exit 1
    python3 -c "import socket,sys,time; s=socket.socket(); s.bind((\"127.0.0.1\", int(sys.argv[1]))); s.listen(1); time.sleep(int(sys.argv[2]))" "$web_port" "$HOLD" & lp=$!
    sleep 1; t=$SECONDS
    dc up -d --build > "$tmp/up.log" 2>&1; rc=$?
    kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
    grep -hE "^PORT|^waited|^FAIL web port" "$tmp/up.log"; echo "RC=$rc after $((SECONDS - t)) s"'
  ```

  - Proof A expected: `PORT waiting`, `PORT free ... after` about 40 s, exactly one `waited N s for port 52802` with N from 36 to 45, and `RC=0`.
  - Proof B expected: `PORT still in use ... after 90 s; starting anyway`, `PORT holder:` lines (lsof names python3), `retry 1 of 2`, `retry 2 of 2`, `FAIL web port: 127.0.0.1:52802 could not be bound after two retries: ...`, exactly one `waited N s for port 52802` with N about 110, and `RC` non-zero.
  - Then run `OCUTALON_RUN_TAG=e0s25proof bash ci/iris.sh teardown` with the lane's variables.
- Lead (once): CI on the head, with every workflow green, including `iris (shards)` `live:online-allowance` (the Integration AC).

Mutations (one per AC; revert each and confirm that `git status --short` and `git diff --stat` are unchanged):
- mutation: AC1, bound -- default `LIVE_PORT_WAIT` back to 20 -> the defaults row goes red (observed; the held-for-good row pins 90 through `guard_run`'s own knob, so it stays green).
- mutation: AC1, shared budget -- each retry waits a full `LIVE_PORT_WAIT` -> the shared-budget row goes red (92 sleeps; observed).
- mutation: AC1, two retries -- stop after one retry -> the "bind twice, then ok", three-bind, shared-budget, holders-named and holder-tools-fail rows go red (observed).
- mutation: AC1, exact error -- retry on any non-zero exit -> the "other error" and "other error on a retry" rows go red (observed).
- mutation: AC1, one line -- print the `waited` line after each attempt instead of once at the end -> the bind-then-ok, bind-twice, bind-three-times, shared-budget, other-on-retry and own-stack rows go red (observed); dropping the line -> the held-briefly, held-for-good and the retry rows go red (observed).
- mutation: AC1, retry waits poll -- pass `0` instead of `"$left"` to the retry's `live_port_wait_free` -> the "retry wait polls" and "budget carried over" rows go red (observed); delete the `spent=$((spent + SECONDS - t2))` line -> the "budget carried over" row goes red (observed).
- mutation: AC1, other failure on the second retry -- drop `&& line=$(live_bind_error "$errf")` from the FAIL condition -> the "other failure on the second retry" row goes red (observed).
- mutation: AC1, waited figure -- measure the first wait's `spent` after the holder listing (`$((SECONDS - t))`) -> the "seconds spent listing the holders are not counted" row goes red (observed).
- mutation: AC2, holders -- add `--filter label=com.docker.compose.project=$P` to the holder query -> the holders-named row goes red (observed); let the guard take its status from `live_port_holders` (`live_port_holders "$p" && rc=0` after the FAIL line; the function itself returns 0 always, so a changed return alone cannot reach the guard's status) -> the bind-three-times, holders-named and holder-tools-fail rows go red (observed).
- mutation: AC2, holder cap -- drop `NR <= 10` from the `docker ps -a` awk -> the holders-named row goes red (22 lines, not 20; observed).
- mutation: AC3, teardown scan -- end a `dc down` line of a scanned script (`docker/tests/test-compose-start.sh`) with `&` -> the teardown row goes red from the scan alone (observed).
- mutation: AC3, teardown -- append ` &` to `live_cleanup`'s `dc down` -> the teardown row goes red (observed).
- mutation: lead ruling, `ss` branch -- `ss -tan` back to `ss -ltn` in `live_port_listed` -> the listener-table `ss` row goes red through its arguments assertion only, since the `ss` stub prints its table whatever the arguments (corrected in code review); `ss -tan state listening` -> the same row goes red now that it requires exactly `-tan` (code review, observed).
- mutation: AC4 -- the rows above are its falsifiable parts.
- mutation: AC5 and the Integration AC -- (lead) these are live observations; the hermetic rows are their stand-ins.

QA (bmad-qa-generate-e2e-tests), hermetic bash suite `docker/tests/test-lib-live.sh` extended (QA); 178 PASS under `bash` and `/bin/bash` 3.2 (169 before), about 64 s; `test-boundaries.sh` passes:
- `docker/tests/test-lib-live.sh` (QA) -- nine rows added in the block `QA rows (Story 0.25)` and after the `ss` listener-table row, plus `guard_run` hooks `g_wait`, `g_tools=lsof`, `g_lsof` (and `lsof.calls`): a free-port start prints no PORT, holder or waited line; a port freed by the last check and a wait cut short by the deadline print exactly one waited line, last (`waited 90 s`, `waited 30 s`); a start after a start that waited in one process prints no waited line of its own; `LIVE_PORT_WAIT=0` on a guarded start is silent (no sleep, no `PORT waiting`, no waited line) and a retry still pauses 10 s (`waited 10 s`); the `lsof` holder fallback (header dropped, 10-line cap, one call); the `ss` holders are the sockets whose local port is the port in any state (TIME-WAIT and LISTEN listed, a client socket of the port not); the 10-line caps after `PORT still in use`; the override's waited line (none when free, one `waited 90 s` before the refusal when held); every state but TIME-WAIT counts in the `ss` poll (CLOSE-WAIT, FIN-WAIT-1/2, SYN-SENT, SYN-RECV, LAST-ACK, CLOSING) and a socket whose peer is the port does not.
- Audit: every row of the I/O matrix and every AC clause has a row (defaults, held briefly, held for good, freed after the last poll, deadline, bind then ok, bind twice, bind three times, shared budget, other error, other on a retry, no wait, own stack, override, holders named, holder tools fail, teardown); the gaps filled are the ones above (the freed-after-last-poll, deadline and free-port rows asserted no waited line, the `ss` rows covered ESTAB and LISTEN only, the `lsof` holders and the peer-only socket were unpinned, and the `LIVE_PORT_WAIT=0` guard path was unpinned).
- mutation: AC1, bound -- default `LIVE_PORT_WAIT` 90 -> 20 -> the defaults row goes red (QA, observed).
- mutation: AC1, two retries -- `[ "$k" -lt 2 ]` -> `-lt 1` -> 9 rows red: bind twice, bind three times, shared budget, second-retry other failure, budget carried over, holders named, holder tools fail, lsof holders, ss holders (QA, observed).
- mutation: AC1, exact error -- retry on any non-zero exit -> the bind-then-ok, other error, other error on a retry, long bind error and step-5 rows go red (QA, observed).
- mutation: AC1, one waited line -- drop `LIVE_PORT_BUSY_SEEN=0` from the guard -> the "waited flag across starts" row goes red; print `waited` unconditionally -> the free-port, other-error, own-stack and `LIVE_PORT_WAIT=0` rows go red; print it only when the wait failed -> held-port, budget-carried-over, last-check/deadline and across-starts rows go red (QA, observed).
- mutation: AC1, `LIVE_PORT_WAIT=0` -- `[ "$max" -le 0 ]` -> `-lt 0` in `live_port_wait_free` -> the `LIVE_PORT_WAIT=0` guard row and the held-override row go red (QA, observed).
- mutation: AC1, override -- `live_web_port` prints the waited line unconditionally -> the override waited row and the `LIVE_PORT_WAIT=0` override row go red (QA, observed).
- mutation: AC2, docker cap -- drop `NR <= 10` from the `docker ps -a` awk -> holders named (22 lines) and the still-in-use cap row (12) go red (QA, observed).
- mutation: AC2, lsof cap -- drop `n < 10` from the lsof awk -> the lsof holders row goes red (12 lines) (QA, observed).
- mutation: AC2, local port only -- the `ss` holder filter also matches the peer column -> the ss-holders-by-local-port row goes red (3 lines, not 2) (QA, observed).
- mutation: AC2, status unchanged -- `live_port_holders "$p"; rc=0` after the FAIL line -> bind-three-times, shared-budget, holders named, holder tools fail, lsof and ss holder rows go red (QA, observed).
- mutation: AC3, teardown -- ` &` on `live_cleanup`'s `dc down` -> the teardown row goes red; ` &` on the `dc down` line of `docker/tests/test-compose-start.sh` -> the teardown row goes red from the scan alone (QA, observed).
- mutation: lead ruling, `ss` branch -- `ss -tan` -> `ss -ltn` -> the listener-table `ss` row goes red; only LISTEN and ESTAB counted -> the new `ss states` row goes red; the peer column counted -> the `ss states` row goes red (QA, observed).
- mutation: AC4/shared surface, `live_first_start` -- grep narrowed to `^PORT` -> the waited-line row goes red (QA, observed).
- QA mutation count: 18 applied, all red, each restored from a backup in the session scratchpad; `git status --short` and the checksums of `docker/tests/lib-live.sh` and `docker/tests/test-compose-start.sh` are unchanged after each. mutations_demonstrated=18.
- mutation: code review, holder line -- `PORT holder: none seen` -> `PORT holder: nothing` -> the bind-three-times row (now exact) and the holder-tools-fail row go red (observed).
- mutation: code review, teardown scan -- append `dc down -v >/dev/null 2>&1 & # background` to `docker/tests/test-compose-start.sh` -> the teardown row goes red (observed; the old scan missed the trailing comment).
- mutation: code review, DW-1113 -- drop step 5's full print of the guard lines in `test-install-script-live.sh` -> the DW-1113 row goes red (observed).
- Code review: the four code-review mutations above (`ss -tan state listening`, the holder line, the teardown scan, DW-1113) ran together, each turning a different row red (5 FAIL in all), then every file was restored from a backup in the session scratchpad, with checksums and `git status --short` unchanged. After the review: 179 PASS (178 + the DW-1113 row) under `bash` and `/bin/bash` 3.2.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The web-port guard in `docker/tests/lib-live.sh` now waits for the port for one shared budget of `LIVE_PORT_WAIT` (default 90 s, polled every 3 s through `wait_until`), retries up to twice on exactly the bind error after a 10 s pause outside the budget, and then prints `FAIL web port: ... after two retries: <line>`. A guarded start that waited prints one `waited N s for port P` line (the override of `live_web_port` does too). The loud FAIL and `PORT still in use` list the holders (`live_port_holders`: containers of any project that publish the port, then TCP sockets of any state on it, at most 10 lines per source, or `none seen`; print-only). The poll's Linux check (`live_port_listed`) now reads `ss -tan` and counts every state but TIME-WAIT on the publish addresses (the lead's ruling at the spec gate). `live_first_start` shows the `waited` line beside FIRST-START.

**Files changed.**
- `docker/tests/lib-live.sh` -- the guard, `live_port_wait_free [max]`, `live_port_holders`, `live_bounded`, `live_port_listed`, the override's `waited` line, the knobs, `live_first_start`'s grep, and the header comments.
- `docker/tests/test-lib-live.sh` -- every matrix row, the lead-ruling `ss` rows, the teardown static row, the fast-clock stubs, and the rows added by this review (second-retry other failure, retry wait polls, budget carried over, holder time not counted, holder cap).
- This spec (frontmatter, `## Verification` mutation lines, triage log).

**Review.** 28 findings: patches 8 (medium 3 rows over 2 entries: the teardown scan, the unpinned retry budget; the rest low), deferred 2 (step 5's `tail -n 5`; the cycle-log line below), rejected 19 with reasons in the triage log, false 3. Follow-up review recommended: true, because two medium entries were patched; the unverified risk is the new retry-wait and budget rows and the `ss -tan` widening, none of which has run against a real CI engine (the lead-owned proofs A and B and CI do that).

**Verification.** `bash docker/tests/test-lib-live.sh` 169 PASS (156 before), `/bin/bash` 3.2 the same, `test-ci-config.sh`, `test-ci-warm.sh` and `test-ci-changes.sh` pass, the non-ASCII check prints 0 for both files, and the forbidden-paths diff is empty. Every mutation line was observed red and restored byte-identical.

**Residual risks.**
- `bash docker/tests/test-boundaries.sh` fails its one rule `keys: nothing key-like` on `_bmad-output/implementation-artifacts/cycle-log-epic-0.md:818` (the lead's `story_created` line for 0.25: the job id followed by a colon matches the bot-token shape), not on this diff; it fails the same at the baseline. Until the lead rewords that line, `ci/checks.sh` and so the head's CI are red on it (deferred, medium).
- The `ss -tan` widening and the 10 s pause are unmeasured on a CI host (inference); the holder lines of the next recurrence will show what the occupant is.
- `waited N s` reads from `$SECONDS` and can be one second high on a real clock.
