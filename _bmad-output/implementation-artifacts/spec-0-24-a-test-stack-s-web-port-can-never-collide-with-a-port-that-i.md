---
title: 'Story 0.24: A test stack''s web port can never collide with a port that is still being released'
type: 'bugfix'
created: '2026-11-10'
status: 'done'
baseline_revision: 'af4189de12b78ecebee770b838f2d96abe846a8d'
baseline_commit: 'af4189de12b78ecebee770b838f2d96abe846a8d'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** CI jobs fail before any test runs with "failed to bind host port 127.0.0.1:52816/tcp: address already in use" (also logged as "driver failed programming external connectivity"). The cause (inference) is a throwaway stack that starts on the job's fixed web port before Docker has released that port from the stack before it. Path B of `release/ipm-install.sh` runs `dc down -v` and then `dc up` straight after it on the same port, and part p does the same thing 6 s later (DW-1099).

**Approach:** Use the Contest Planner's ruled fallback, fix (2). Every stack start that publishes a web port goes through `docker/tests/lib-live.sh`. Before the start, it waits up to 20 s for the port to be free. If the start fails with exactly the bind error, it retries once, and if the retry also fails it fails loudly. The start path is `dc`, which every live script and release harness already uses, so no release harness, workflow or web client changes. Design Notes explain why fix (1) was not chosen.

## Boundaries & Constraints

**Always:**
- The fixed per-runner port scheme of `ci/iris.sh` `setup_tag` stays as it is (52810 + n for runners 0 to 9, 52819 - n for runners 10 to 19).
- `OCUTALON_TEST_WEB_PORT` stays the explicit override, with the same range (52800-52819) and the same refusals. The only change is that an override port that is in use is waited for before the "in use" refusal.
- The web port stays bound to 127.0.0.1 only. `LIVE_FORBIDDEN_PORTS` and its refusals are unchanged.
- A retry happens only when a start subcommand (`up`, `start` or `restart`, as `dc`'s first argument) fails with a message that contains `address already in use` or `failed programming external connectivity`. It happens at most once.
- Calls that publish no web port (`web_port` empty: warm stacks, shards, classes, non-browser units) and every other `dc` subcommand run exactly as they do today.
- No test assertion changes. Existing pins move only where the wait needs it: `LIVE_PORT_WAIT=0` where a held port is simulated, and the comments that describe the new behaviour.
- Shell code stays ASCII only and runs on bash 3.2 with BSD or GNU tools, on macOS (Docker Desktop) and on Linux (the CI hosts).

**Never:**
- Edit anything under `release/**` or `.github/workflows/*.yml` (a RELEASE TOOL item), `web/**`, `ci/iris.sh` or `_bmad/**`.
- Publish on a port Docker picks (`127.0.0.1::52773`). That is fix (1), which this story does not take.
- Retry more than once, retry any other failure, or move to a different port after a failure.
- Write a local absolute path into a tracked file.

## I/O & Edge-Case Matrix

These rows are the hermetic self-tests in `test-lib-live.sh`. They stub `docker`, `sleep` and `port_in_use`, and source a fresh `lib-live.sh` in a subshell so that the real `dc` runs.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Held port waited for (DW-1099) | `web_port` set, own container not running, port busy for the first 3 checks | `PORT waiting` line, then `PORT free`; `docker compose ... up` runs once, after the checks; exit 0 | No error expected |
| Port still held after the wait | port busy on every check | The wait ends once `wait_until`'s count reaches `LIVE_PORT_WAIT` (with 20 and its 3 s steps: 7 sleeps, 21 s, and no more); `PORT still in use ... starting anyway`; the start runs once | The start's own result decides |
| Bind error, then success (DW-1099) | first compose call fails with the measured Docker line (`... bind: address already in use`) | `PORT retry` line; one pause and another wait; the compose call runs a second time; exit 0; the first attempt's stderr is still shown | Retried once |
| Bind error twice | both compose calls fail with `driver failed programming external connectivity on endpoint ...` | exactly 2 compose calls; `FAIL web port: 127.0.0.1:<p> could not be bound after one retry: <line>`; non-zero exit | Fails loudly |
| Other start failure | compose fails with `no such image` | 1 compose call, no `PORT retry` line, non-zero exit | Not retried |
| Own stack publishes the port | `dc restart iris` (or `up -d` on a running stack) while `docker ps --filter publish=<p>` lists the project's container | no pre-wait (the busy stub is never consulted); 1 compose call | Bind error: retried once, as above |
| No web port | `web_port` empty; `dc up -d --build --wait` | 1 compose call, no `docker ps`, no `port_in_use` call, no PORT line | Unchanged |
| Not a start | `web_port` set; `dc exec ...`, `dc ps -q iris`, `dc down -v` | passed straight through, output unchanged | Unchanged |
| Override held briefly | `OCUTALON_TEST_WEB_PORT=52815`, busy for 2 checks | accepted after `PORT waiting`; `web_port=52815`; `port.yml` holds `127.0.0.1:52815:52773` | No error expected |
| Listener table | `ss` stub lists `127.0.0.1:<p>`, `0.0.0.0:<p>`, `*:<p>` or `[::]:<p>` in LISTEN state; or, without `ss`, `lsof -iTCP:<p> -sTCP:LISTEN` exits 0 | `port_in_use <p>` is true. A neighbour such as `:<p>0` or `:1<p>` is not | Neither tool present: the connect check alone, as today |

</intent-contract>

## Code Map

- `docker/tests/lib-live.sh`
  - `:19-21` -- header. Today: "publishes no host port, unless ... live_web_port". Gains one sentence on the start guard.
  - `:196-201` -- `LIVE_FORBIDDEN_PORTS` (unchanged) and `port_in_use` (connect only). This is the extension point for the listener table.
  - `:203-246` -- `live_web_port`.
    - The override branch refuses an in-use port at once (`:228-231`). It will wait first.
    - The probe loop (`:233-238`) is unchanged and picks up the extended `port_in_use`.
    - `port.yml` is written at `:245` with `127.0.0.1:%s:52773` (unchanged).
  - `:248-252` -- `dc`. It is the one start path. Its body becomes `dc_compose`, unchanged.
  - `:292` -- `wait_until <max> <cmd>`. It checks every 3 s and stops at `deadline`. Reuse it for the wait; do not write a second loop.
  - `:473-500` -- `live_first_start`. Its `dc up -d --no-build` is guarded automatically. `first_ready_s` then includes any port wait, and the PORT lines show it.
- `docker/tests/test-lib-live.sh`
  - `:1-40` -- the header list. Add the guard's bullet.
  - `:55` -- a stub `dc` used by the earlier blocks. The new block must re-source `lib-live.sh` in a subshell to get the real `dc`.
  - `:494-570` -- the `live_web_port` block. It stubs `port_in_use` from a `used_ports` file.
  - `:544-554` -- the in-use override case. Set `LIVE_PORT_WAIT=0` there; its assertion and message stay.
  - Baseline: 134 PASS lines, 54 s.
- `docker/tests/test-ci-config.sh`
  - `:1510-1592` -- `live_port_checks`. Its subshell stubs `port_in_use` and runs 20 held-port cases ("exit 1, no port and an in use message"). Set `LIVE_PORT_WAIT=0` after sourcing, or the wait would add about 400 s. Assertions unchanged.
  - `:64` and `:1511` -- comments. They stay true.
  - `:1465-1484` -- the `ci/iris.sh port` pins. Unchanged.
- `docker/tests/test-install-script-live.sh`
  - `:134` -- `dc down`.
  - `:148-153` -- step 5: a plain `env COMPOSE_PROJECT_NAME=... COMPOSE_FILE=... docker compose up -d` on the same project and port. This is DW-1099's down-then-up shape, outside `dc`. Wrap that command in the guard. Keep `plain_out`, `plain_rc` and the assertions as they are.
  - `:50-51` -- `install.sh` (steps 2 and 3). Not wrapped; see Design Notes.
- Starts through `dc`, guarded with no edit. Read only; verify each one with `git grep -nE '(^|[^a-z_])dc (up|start|restart)( |$)'` (the subcommand is the first argument at every site):
  - `release/ipm-install.sh`:
    - `:2034-2042` -- the first start.
    - `:2176-2177` -- path B's `dc down -v` and `dc up`.
    - `:1858-1859` -- part p.
    - `:1585` -- `dc restart iris`.
  - `release/upgrade-harness.sh`:
    - `:734`, `:1657` and `:1726` -- starts and the restart.
    - `:791` and `:805` -- `attach_stack` restores `web_port` from the saved file, so the guard applies in attach mode too.
  - The 16 scripts under `docker/tests/` that call `live_web_port || exit 1` (`record-screenshot.sh` included), and the users of `lib-online.sh`.
- Read only, unchanged:
  - `ci/iris.sh:72-97` `setup_tag`, `:280` (a class or shard start, with no web port).
  - `release/rehearse.sh`:
    - `:973` -- calls `live_web_port`, so it gets the override wait.
    - `:1008-1015` -- the stand-in starts through its own `docker compose`, not `dc`.
  - `web/e2e/support/iris.ts:28` -- `docker ps --filter publish=<port>`. Still valid, since the port is unchanged.
  - `eval/key-proof.sh:31` -- passes the override through.
  - `docker/tests/test-ci-warm.sh` and `test-demo-path-gate.sh` -- they stub `dc` or `live_web_port` and are unaffected (`test-ci-warm.sh` baseline: 141 PASS, 49 s).
- `docker/tests/test-boundaries.sh:284` -- the docker-call rule. `docker ps -q --filter ...` is allowed. Never use `docker inspect` without `--format`, and never `compose config` without `--quiet`.

## Tasks & Acceptance

**Execution:**
- `docker/tests/lib-live.sh` -- Implement fix (2) in the start path, with knobs `LIVE_PORT_WAIT=${LIVE_PORT_WAIT:-20}` and `LIVE_PORT_RETRY_PAUSE=${LIVE_PORT_RETRY_PAUSE:-5}` (set like `DISABLED_QUIET_SECONDS`). Rationale: one central change covers every start, release harnesses included, without touching them (DW-1099).
  - (a) Extend `port_in_use <p>`: it is true when the connect check succeeds, as today, OR when the host's listener table lists TCP port `<p>` in LISTEN state on 127.0.0.1 or on all addresses.
    - Linux: `ss -ltn`, where the Local Address column ends in `:<p>`.
    - Where `ss` is absent (macOS): `lsof -nP -iTCP:<p> -sTCP:LISTEN`.
    - Neither tool present: the connect check alone.
  - (b) Add `live_port_wait_free <p>`.
    - It returns 0 at once when `<p>` is free.
    - Otherwise it prints `PORT waiting: 127.0.0.1:<p> is in use; waiting up to <LIVE_PORT_WAIT> s`. It then waits through `wait_until "$LIVE_PORT_WAIT"` for the port to be free; `wait_until` already stops at `deadline`.
    - When the port frees, it prints `PORT free: 127.0.0.1:<p> after <s> s` and returns 0. When it does not, it returns 1.
  - (c) Make `live_web_port`'s override branch call `live_port_wait_free` before the existing `in use` FAIL. Keep the message text.
  - (d) Rename today's `dc` body to `dc_compose`, unchanged. The new `dc` sends a first argument of `up`, `start` or `restart`, with `${web_port:-}` non-empty, to `live_port_guard dc_compose "$@"`. Everything else goes to `dc_compose "$@"`.
  - (e) Add `live_port_guard <command...>`:
    1. Pre-wait. Skip it when `docker ps -q --filter label=com.docker.compose.project=$P --filter publish=$web_port` lists a container, because the project's own stack holds the port. Otherwise call `live_port_wait_free`. If the port is still in use, print `PORT still in use: 127.0.0.1:<p> after <n> s; starting anyway`.
    2. Run the command. Capture its stderr to a file under `$tmp` and replay it to stderr afterwards.
    3. If the command exits non-zero and its stderr contains `address already in use` or `failed programming external connectivity`:
       - Print `PORT retry: <first matching line, at most 200 characters>; retrying once in <pause> s`.
       - `sleep "$LIVE_PORT_RETRY_PAUSE"`, then `live_port_wait_free`.
       - Run the command once more in the same way.
       - If the retry fails with the bind error again, print `FAIL web port: 127.0.0.1:<p> could not be bound after one retry: <line>`.
    4. Return the last exit status. Any other failure returns its status with no retry.
  - (f) Update the header (`:19-21`) and the `live_web_port` comment so that they state the wait and the guard.
- `docker/tests/test-lib-live.sh` -- Add the block `--- the start's port guard (Story 0.24) ---`.
  - It covers every I/O matrix row, in a subshell that sources `lib-live.sh` again, with these stubs:
    - `docker`: records its arguments in a calls file. For `ps` it prints an id when the case says the stack is its own. For `compose`, it takes the next outcome (`ok`, `bind-mac`, `bind-ci`, `other`) from a queue file and prints the matching stderr.
    - `sleep`: records the seconds and does not sleep.
    - `port_in_use`: a countdown of busy checks.
    - `P`, `tmp`, `deadline` and `LIVE_FILES` set.
  - The listener-table row stubs `ss` (and `lsof`) on `PATH`. Use a port that nothing listens on (for example 9), and symlink any real tool the helper needs into the stub folder. That lets the `lsof` row run with `ss` hidden on Linux too.
  - Set `LIVE_PORT_WAIT=0` in the existing in-use override case (`:544-554`).
  - Add the guard's bullet to the header.
  - Rationale: the ruling's self-test is "a held port is waited for, and the bind error is retried once and then fails loudly".
- `docker/tests/test-ci-config.sh` -- In `live_port_checks`, set `LIVE_PORT_WAIT=0` after `. ci/iris.sh`, with a one-line comment. The assertions do not change. Rationale: the held-port pins simulate a port that is held for good, so they must not wait 20 s each.
- `docker/tests/test-install-script-live.sh` -- Run step 5's plain `docker compose up -d` through `live_port_guard`, inside `plain_out=$(...)`. Rationale: `dc down` then a plain up on the same port is DW-1099's shape, and this unit runs in CI.

**Acceptance Criteria:**
- Given `docker/tests/lib-live.sh` after this story, when any `dc up`, `dc start` or `dc restart` runs with a web port, then it waits up to 20 s for the port to be free, retries once on exactly the bind error, and then fails loudly; fix (2), its reason and the files it touches are recorded under Design Notes (DW-1099).
- Given `OCUTALON_TEST_WEB_PORT` set to a lane's port (52801-52804) or to a runner's fixed port, when `live_web_port` runs, then that port is used, published as `127.0.0.1:<p>:52773` only; every refused value in the existing loop (`52773 052773 52790 1979 8089 0 80 99999 52799 52820 abc 52x`) is still refused.
- Given `test-lib-live.sh`, `test-ci-config.sh`, `test-ci-changes.sh`, `test-ci-warm.sh` and `test-boundaries.sh`, when they run, then all pass. They keep every existing assertion, and the new block shows the held-port wait, one retry on the bind error, no retry on another error, and the loud failure.
- Given a lane-C throwaway (Integration AC: consumer `release/ipm-install.sh`, whose path B and part p start with `dc down -v` and then `dc up` on one port), when two stacks start back to back through `dc` on the lane's port, then the second stack starts and answers HTTP on 127.0.0.1:52803 with no bind error.
- Given CI on the story's head, when it finishes, then every workflow is green. That includes lane-a's `ipm-install-p` job (modes `b` then `p`), where DW-1099 occurred.

## Spec Change Log

## Review Triage Log

### 2026-11-10 -- Review pass
- verdicts: 21 rows (grouped findings share a row; the intent layer's descriptive report is the last row) -- high 0, medium 2, low 18, false 0, maybe-false 0; 3 patched, 0 deferred, 17 rejected, 1 descriptive
- findings:
  - `[low]` `[reject]` Blind: stderr is held until the start ends -- Task (e).2 of the spec prescribes capture-and-replay; callers redirect the up log to a file; a tee would add a process-substitution race on bash 3.2.
  - `[low]` `[reject]` Blind, Edge, Intent: `lsof` branch matches any address (`::1`, LAN IP) -- the spec's task (a) names `lsof -nP -iTCP:<p> -sTCP:LISTEN`; the worst case is a 20 s wait; macOS only.
  - `[low]` `[reject]` Blind, Edge: `wait_until` does not check after the last sleep (7 checks, 21 s) -- the matrix row pins exactly 7 sleeps and no more (spec-bound).
  - `[low]` `[reject]` Blind, Edge x2: retry pause and second start ignore `$deadline`; a pre-wait plus a retry can pass it -- Design Notes record "can pass the run's deadline by at most about 25 s" (spec-bound).
  - `[low]` `[reject]` Blind, Edge: `live_bind_error` matches the phrase anywhere in stderr, not tied to the port -- the spec says "a message that contains" the phrases (spec-bound); a wrong port in the FAIL line is cosmetic.
  - `[low]` `[reject]` Blind: `ss` present but failing does not fall back to `lsof` -- theoretical (standard `ss` on the CI hosts; `lsof` on macOS).
  - `[low]` `[reject]` Edge: the retry after a bind error on the project's own stack waits 21 s -- a bind error there means another process holds the port, so the wait is what is wanted.
  - `[low]` `[reject]` Edge: `ss` address spellings `[::ffff:127.0.0.1]` or `127.0.0.1%dev` are missed -- Docker publishes `127.0.0.1:<p>`, which `ss` prints as that; no reachable case shown.
  - `[low]` `[reject]` Edge: `dc` with global compose options before the subcommand, or `create`, `run`, `unpause`, is not guarded -- the spec guards the first argument `up`, `start`, `restart` and records the `git grep` check that every site uses it.
  - `[low]` `[reject]` Edge: `$tmp` empty or unwritable -- `$tmp` is set by `live_start` before any `dc`; theoretical.
  - `[low]` `[reject]` Edge: PORT lines on stdout mix into a caller's captured output -- Design Notes decide stdout and record that no caller parses them.
  - `[low]` `[reject]` Edge: test-lib-live restores `LIVE_PORT_WAIT=20` hard-coded -- the new block now sets its own values in each subshell, so nothing downstream depends on it.
  - `[low]` `[reject]` Edge, Intent: the claim "exactly the bind error" or "every start" is looser than the code -- same root cause as the substring and first-argument rows above; no code change.
  - `[medium]` `[patch]` Edge: with `LIVE_PORT_WAIT=0` the `PORT waiting ... is in use` line is printed, so the `test-ci-config.sh` pin that greps `in use` in the refusal output can pass without the `FAIL live_web_port` line -- fixed: `live_port_wait_free` returns 1 silently when `LIVE_PORT_WAIT` is 0 or less (the held-port pins keep their meaning).
  - `[low]` `[patch]` Blind, Verification-gap: `LIVE_PORT_RETRY_PAUSE` (and `LIVE_PORT_WAIT`) are read from the caller's environment inside the new block -- fixed: each guard subshell sets both explicitly.
  - `[medium]` `[patch]` Verification-gap: no assertion checks the compose arguments of the first and the retry call or the `docker ps` probe's filters -- fixed: the retry row asserts 2 identical `compose -p guardproj -f a.yml up -d --build` calls, the own-stack row asserts the probe's label and publish filters and the `restart iris` call; two new `mutation:` lines observed red.
  - `[low]` `[reject]` Verification-gap: step 5's `live_port_guard` wrapper has no hermetic test or mutation -- the wrapper can fail only when the race occurs; the logic it calls is pinned through `dc`. Closed wontfix-accepted; reopen_if `install-script-live` shows a bind error at step 5.
  - `[low]` `[reject]` Verification-gap: AC4 and AC5 are live observations and cannot fail without the race -- the only fix is to edit this spec's Verification (a held listener around the second start), which a review may not do; recorded as a residual risk.
  - `[low]` `[reject]` Verification-gap Other: `LIVE_PORT_WAIT=0` pins no longer reach the wait path -- intended (the knob exists for that); the new rows cover the wait.
  - `[low]` `[reject]` Verification-gap: listener-table rows assume nothing listens on port 9 -- the connect check on 127.0.0.1:9 is refused on any dev or CI host; theoretical.
  - Intent-alignment layer: descriptive report, no defect. Its divergences (the diff proves the logic at the `dc` surface with stubs; Path B and part p are not replayed live; the guard adds the own-stack skip, the start-anyway rule, the pause and the second wait) are all recorded in Design Notes; the live proof and CI (AC4, AC5) own the real surface.

## Design Notes

**Choice: fix (2), wait and retry once (decided in-stage).**
- Fix (1) changes the port on every start, and starts happen several times per process:
  - `ipm-install.sh` has 4 starts and a restart;
  - `upgrade-harness.sh` persists `web_port` across calls and restarts;
  - live scripts run `dc down` then `dc up`.
- So with fix (1), every caller would have to re-read the port after each `up` and `restart`, and rebuild its `base`. That means about 20 live scripts, 3 release harnesses (RELEASE TOOL hunks), `ci/iris.sh`, and the pins of the per-runner scheme in `test-ci-config.sh`. This is far more than the ruling's 2-3 hours.
- Fix (2) fits in `dc`, the one start path that every one of those callers already uses.
- Files touched:
  - `docker/tests/lib-live.sh`
  - `docker/tests/test-lib-live.sh`
  - `docker/tests/test-ci-config.sh`
  - `docker/tests/test-install-script-live.sh`
- No `release/**` file and no workflow file.

**Measured (plan stage, 2026-11-10, developer machine, Docker 29.7.2 Desktop, lane C port 52803, own probe containers removed):**
- With a listener on the port, `docker compose up -d` exits 1. All its output goes to stderr, ending in `Error response from daemon: ports are not available: exposing port TCP 127.0.0.1:52803 -> 127.0.0.1:0: listen tcp4 127.0.0.1:52803: bind: address already in use`, and the container is left `Created`.
- After the port is freed, the same `up -d` starts that container (exit 0). That is what the retry relies on.
- A socket that is bound but not listening also blocks the bind. The connect check and `lsof -sTCP:LISTEN` both miss it, so the pause before the retry is needed.
- A back-to-back `down -v` and `up -d` of a small container did not reproduce the race on Docker Desktop.
- Inference, not measured: the CI hosts' Linux engine releases the port later, and `ss` is present there (standard Ubuntu). The tool fallback keeps the check working if `ss` is missing.

**Decided in-stage:**
- **Where the wait is, and the pre-wait skip.** The 20 s wait comes before every guarded start, and also in `live_web_port`'s override branch, which is where the port is chosen. A new process, like part p after path B, then waits out a teardown that is still releasing the port. The pre-wait is skipped when the project's own container publishes the port, as on a `restart`, or an `up` that recreates a running stack, because waiting there would cost 20 s for nothing.
- **A held port does not fail by itself.** If the port is still held after the wait, the start goes ahead, and the bind decides. A false "busy" then costs nothing, and a real one ends in the loud failure after the retry.
- **Pause before the retry.** Before the retry, a 5 s pause, then the wait, because the free check can miss the occupant (measured). Both knobs are implementation values.
- **The retry's timeout.** The retry reuses the caller's arguments, including a `--wait-timeout` computed before the first try, so a retried start can pass the run's deadline by at most about 25 s. The deadline still bounds every wait.
- **`install.sh` and the rehearsal stand-in stay unguarded.** `install.sh` is the product script under test, and its first start comes straight after `live_web_port`'s wait. The rehearsal stand-in's start is in `release/rehearse.sh` (a RELEASE TOOL file), runs once per rehearsal, and is not a CI unit. Residual risk: an occupant that the checks cannot see. Reopen if either one shows the bind error.
- **PORT lines.** They are internal log text (no PUBLIC TEXT gate). They print to stdout, like the `LOCK` lines, so they land in each caller's up log. No caller parses those logs (checked).

**Governing ADs:**
- AD-22: throwaway stacks and CI. The change stays inside the throwaway recipe and keeps its docker-call bans.
- AD-29: Epic 0 may edit any lane's files.
- AD-23: the first-start report. `live_first_start`'s ready time can include a port wait, and the PORT lines show it.

No AD is amended, and nothing of architectural weight changes (Rule 20). The fixed port scheme recorded in Rule 21 of `_bmad/custom/skill-rules.md` stays true, so no edit is needed there. The lead may append the measured facts above to Rule 21 if it wishes.

**Integration ACs:** `dc` is a shared component. Consumers:
- `release/ipm-install.sh` (path B, part p) -- the AC4 live proof replays its down-then-up through `dc`. CI lane-a's `ipm-install-p` job (AC5) is the real consumer.
- Every browser live unit in CI (AC5).
- Consumed-by: Story 0.24's CI units, and every later story's live scripts.
- Consumes: none.

**Extend, don't copy (Rule 2):**
- `port_in_use` is extended in place.
- The wait reuses `wait_until`.
- `dc_compose` is `dc`'s existing body.
- One `live_port_wait_free` serves both `live_web_port` and the guard.
- One `live_port_guard` serves `dc` and the plain up in `test-install-script-live.sh`.

**Ledger inbox:** DW-1099 is addressed by tasks (d) and (e), the I/O rows marked DW-1099, AC1 and AC4.

## Verification

Shared surfaces:
- `dc`'s behaviour for start subcommands when a web port is set. Every live script and release harness shares it.
- `port_in_use`, which `live_web_port`'s probe and its pins in `test-lib-live.sh` and `test-ci-config.sh` use.
- The new `PORT` lines in up logs. No test asserts on them, except the new block.

Standing criterion: every test added or changed passes on a fresh environment, in either order. The hermetic scripts are single processes with their own temporary folders.

**Commands** (run from the worktree root, one per call):
- `bash docker/tests/test-lib-live.sh` (loop, about 55 s) -- expected: `test-lib-live: all checks passed`, with 134 PASS lines plus the new block's.
- `bash docker/tests/test-ci-config.sh` (loop, about 32 s) -- expected: every PASS line, including `PASS recipe: ...`.
- `bash docker/tests/test-boundaries.sh` (loop, about 11 s) -- expected: `test-boundaries: all rules passed`.
- `bash docker/tests/test-ci-changes.sh` (once, about 17 s) -- expected: all pass.
- `bash docker/tests/test-ci-warm.sh` (once, about 49 s) -- expected: `test-ci-warm: all checks passed (including the DW-164 block)`.
- `/bin/bash docker/tests/test-lib-live.sh` (once, about 55 s) -- expected: the same result under macOS bash 3.2.
- `for f in docker/tests/lib-live.sh docker/tests/test-lib-live.sh docker/tests/test-ci-config.sh docker/tests/test-install-script-live.sh; do LC_ALL=C tr -d '\011\012\040-\176' < "$f" | wc -c; done` (once) -- expected: four lines of 0.
- Live proof (once, about 90 s; the implement stage may run it, or the lead owns it). Set Rule 21's lane-C variables: `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-c`, `OCUTALON_TEST_WEB_PORT=52803` and `OCUTALON_LOCK_OWNER='epic=0 stage=<stage>'`. Then run:

  ```
  OCUTALON_RUN_TAG=e0s24proof bash -c '. docker/tests/lib-live.sh; live_start proof; live_web_port || exit 1
    answers() { [ "$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" "http://127.0.0.1:$web_port/ocutalon/")" != 000 ]; }
    for k in 1 2; do t=$SECONDS
      dc up -d --build > "$tmp/up$k.log" 2>&1 || { tail -n 20 "$tmp/up$k.log"; echo "FAIL stack $k did not start"; exit 1; }
      if wait_until 120 answers; then echo "PASS stack $k answers on 127.0.0.1:$web_port after $((SECONDS - t)) s"; else echo "FAIL stack $k does not answer"; exit 1; fi
      grep -hE "^PORT|^FAIL web port|already in use|external connectivity" "$tmp/up$k.log"
      [ "$k" = 2 ] || dc down -v > "$tmp/down.log" 2>&1
    done'
  ```

  Expected: `PASS stack 1 ...` and `PASS stack 2 ... 127.0.0.1:52803`, and no bind-error line. A PORT line may appear, and the log keeps it as evidence. Afterwards, run `OCUTALON_RUN_TAG=e0s24proof bash ci/iris.sh teardown` with the lane's variables.
- `bash ci/iris.sh live install-script-live` (once, with the lane's variables; lead-owned if it does not fit in about 150 s) -- expected: every PASS line, including `a plain docker compose up -d exits 0`.
- Lead (once): CI on the head, with `ci` and `lane-a` green, `ipm-install-p` included.

Mutations, one per AC. Revert each one and confirm that `git status --short` and `git diff --stat` are unchanged:
- mutation: AC1, wait -- in `live_port_guard`, drop the pre-wait call -> the `held port waited for` row goes red.
- mutation: AC1, retry -- return after the first failed attempt -> the `bind error, then success` row goes red.
- mutation: AC1, exact error -- retry on any non-zero exit -> the `other start failure` row goes red (2 compose calls).
- mutation: AC1, loud failure -- drop the `FAIL web port` line -> the `bind error twice` row goes red.
- mutation: AC2, override wait -- in `live_web_port`, refuse an in-use override at once again -> the `override held briefly` row goes red.
- mutation: AC2, binding -- write `"%s:52773"` (all interfaces) in `port.yml` -> the existing `publishes 52800 on 127.0.0.1 only` check goes red.
- mutation: AC1, retry arguments -- the retry runs the command without its last argument (`"${@:1:$#-1}"`) -> the `bind error, then success` row goes red (observed).
- mutation: AC1, own-stack probe -- drop `--filter "publish=$p"` from the `docker ps` probe in `live_port_guard` -> the `own stack, restart` row goes red (observed).
- mutation: AC3, listener table -- make `port_in_use` ignore `ss` -> the listener-table row goes red.
- mutation: AC3, pass-through -- run the guard with no web port set -> the `no web port` row goes red.
- mutation: AC4 -- (lead) none needed; the proof is a live observation of two starts.

## Auto Run Result

Status: done
Blocking condition: none

**Implemented (fix 2).** `dc` sends `up`, `start` and `restart` with a web port through `live_port_guard`; every other call runs as before. The guard waits up to `LIVE_PORT_WAIT` (20) s for the port, unless the project's own container publishes it, starts anyway when the port stays held, retries once after `LIVE_PORT_RETRY_PAUSE` (5) s and another wait on `address already in use` or `failed programming external connectivity`, and then fails loudly. `port_in_use` also reads the listener table (`ss -ltn`, else `lsof`), and `live_web_port`'s override waits before its refusal.

**Files changed**
- `docker/tests/lib-live.sh` -- the guard, the wait, the listener table, the `dc` split, header and comments.
- `docker/tests/test-lib-live.sh` -- the block `the start's port guard (Story 0.24)` (14 PASS lines, 134 to 148), `LIVE_PORT_WAIT=0` around the held-override case, the header bullet.
- `docker/tests/test-ci-config.sh` -- `LIVE_PORT_WAIT=0` in `live_port_checks` (no assertion changed).
- `docker/tests/test-install-script-live.sh` -- step 5's plain `docker compose up -d` runs through `live_port_guard`.

**Decided in-pass (small).** `live_port_wait_free` returns 1 silently when `LIVE_PORT_WAIT` is 0 or less, so the held-port pins that set the knob to 0 keep seeing the `FAIL live_web_port ... in use` line (not the PORT line) in their match.

**Review.** 21 triage rows from four layers; 3 patched (medium 2, low 1), 0 deferred, 17 rejected with reasons in the Review Triage Log, and the intent layer's descriptive report. Follow-up review recommended: false.

**Verification performed.** `test-lib-live.sh` (148 PASS, 0 FAIL, with `bash` and with `/bin/bash` 3.2), `test-ci-config.sh`, `test-boundaries.sh`, `test-ci-changes.sh`, `test-ci-warm.sh` all pass; ASCII check prints four 0; no absolute local path in the diff. Ten mutations (the eight planned, plus two for the new assertions) went red and were reverted byte-identically.

**Not run here (lead-owned).** The live proof (two stacks back to back on lane C, port 52803), `bash ci/iris.sh live install-script-live`, and CI on the head (`ipm-install-p`).

**Residual risks.** AC4 and AC5 are observations: Docker Desktop did not reproduce the race, so a green proof or a green CI run is evidence, not a falsification; the hermetic rows carry the logic. An occupant that neither the connect check nor the listener table sees (a bound, non-listening socket) is covered only by the retry. `install.sh` and the rehearsal stand-in stay unguarded (Design Notes).
