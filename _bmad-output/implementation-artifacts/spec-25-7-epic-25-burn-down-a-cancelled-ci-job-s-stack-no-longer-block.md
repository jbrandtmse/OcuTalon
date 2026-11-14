---
title: "Story 25.7: Epic 25 burn-down: a cancelled CI job's stack no longer blocks its runner's web port"
type: 'bugfix'
created: '2026-11-14'
status: 'done'
baseline_revision: '9ae728cbdb9eedd27573531a302a8cf11b100186'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A cancelled CI job skips its `teardown` step. Its compose stack keeps running and keeps holding the runner's fixed web port. After that, every later browser unit on that runner fails at `live_web_port: port 52xxx is in use on 127.0.0.1` (DW-1335: `ocutalon-ci-4`, port 52814, run 43593749725's stack).

**Approach:** Only one job runs on a runner at a time. So at job start, on a self-hosted CI runner with a fixed web port, `ci/iris.sh build` removes every throwaway compose project that publishes that port, and logs each project it removes. `build` is the first script step of every self-hosted job, and it runs before anything binds the port. A local developer run never sweeps.

## Boundaries & Constraints

**Always:**
- The sweep runs only when `GITHUB_ACTIONS=true`, `RUNNER_ENVIRONMENT=self-hosted` and `OCUTALON_TEST_WEB_PORT` (after `setup_tag`) is a number in 52800-52819. This is the runner-derived port or a preset one, such as `ocutalon-ci-20`'s 52805.
- Selection is by host port: `docker ps -a --filter publish=<p>` with the compose project label, under `live_bounded`. Removal is by project: the whole stack goes, its port-less mock included, through the same down line as `teardown`.
- Only names shaped like a `live_start` project are removed: `^ocutalon-[a-z0-9-]+-[0-9]{10}-[0-9]+$`, with no `slot`. Every other holder is kept and logged.
- One log line per outcome: `SWEEP off: <reason>`, `SWEEP 127.0.0.1:<p>: no leftover`, `SWEEP removed project <P> (it published 127.0.0.1:<p>)`, `SWEEP kept <name> project=<P|none>: <reason>`, `SWEEP FAIL <what>`.
- The sweep never fails the job. If it cannot list or remove a holder, it prints `SWEEP FAIL ...` and the build goes on. `live_web_port`'s existing wait, FAIL line and holder listing still apply.
- `live_web_port`, the port mapping in `setup_tag`, and the semantics of `teardown` stay unchanged for every caller.
- Every `docker` call carries `--format` where it lists or inspects (AD-22). The ASCII-only and contract-only comment rules apply (Rule 14).

**Never:**
- No product change, no public text, and no hunk under `.github/workflows/` or `release/`.
- The sweep never touches a stack on another port, a container that publishes no port, a non-compose container, or a project that is not a throwaway.
- No sweep in `group`, `live`, `shard` or `class`. A previous unit's stack in the same job may still be shutting down (Story 0.25).
- The tests never touch a real CI runner host, any `ocutalon-slot-*`, `ocupilot*`, `ocutalon-aihub-test` or `iris-community-edition` container, or another lane's stacks. They never pull an image and never call the real `docker` in hermetic mode.

## I/O & Edge-Case Matrix

These rows are hermetic. They run through the real `cmd_build` of a sourced `ci/iris.sh`, with `preflight` and `ensure_web_bundle` stubbed and `docker` a PATH stub. CI env means `GITHUB_ACTIONS=true` and `RUNNER_ENVIRONMENT=self-hosted`.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Leftover on own port | CI env, `RUNNER_NAME=ocutalon-ci-4` (52814). Running `ocutalon-demo-path-43593749725-1-browser-1794600000-123` (iris on 52814 plus a port-less mock); `ocutalon-floor-9-1-shards-1794600000-7` on 52813; a port-less `ocutalon-class-abc-1-1794600000-9` | One down of the leftover with teardown's files and `down -v --rmi local --remove-orphans`. A `SWEEP removed project ...` line comes before the bundle step. The `BUILD` line follows and the exit code is 0. Then `live_web_port` (`LIVE_PORT_WAIT=0`, `port_in_use` reads the stub table) returns 0 with `web_port=52814`. No docker call names the 52813 or the port-less project | none |
| Nothing on the port | CI env, ci-4, empty table | `SWEEP 127.0.0.1:52814: no leftover`, no down, BUILD, exit 0 | none |
| Preset port | CI env, `RUNNER_NAME=ocutalon-ci-20`, `OCUTALON_TEST_WEB_PORT=52805`, a leftover on 52805 | That leftover is removed | none |
| Auto mode | CI env, `ocutalon-ci-20` with no preset, or no runner name | `SWEEP off: no fixed web port`, no `docker ps` call | none |
| Local lane run | `GITHUB_ACTIONS` unset, or `RUNNER_ENVIRONMENT=github-hosted`, with `OCUTALON_TEST_WEB_PORT=52803` and a leftover-shaped project on 52803 | `SWEEP off: not a self-hosted CI runner`, no docker call, the project is kept | none |
| Bad preset | CI env, preset `52773`, `60000` or `abc` | `SWEEP off: ...` naming the value, no docker call | `live_web_port` still refuses it later, as today |
| Not a throwaway on the port | CI env, ci-4: a compose project `ocutalon-slot-x`, `other-proj-1794600000-1`, and a non-compose container, each publishing 52814 | Each gets a `SWEEP kept ...` line with its reason. No down, no rm | none |
| Removal does not take | CI env, ci-4: the stub's down leaves the container in place | One `docker rm -f -v <container>` of that project's container only. If the container is still listed, `SWEEP FAIL 127.0.0.1:52814 still published by <name>`. Exit 0 | the build goes on |
| Listing fails | CI env, ci-4: the stub's `ps` exits 1 | `SWEEP FAIL could not list what publishes 127.0.0.1:52814`, exit 0 | the build goes on |

</intent-contract>

## Code Map

- `ci/iris.sh:1-61` -- the header. Add the sweep to the `build` line and add one paragraph (when it runs, what it removes, what it keeps, the log lines).
- `ci/iris.sh:74-99` -- `setup_tag`, which exports the fixed port (52810+n, 52819-n, preset wins). Read only.
- `ci/iris.sh:397-403` -- `cmd_build`. Call `runner_sweep` after `preflight` and before `ensure_web_bundle`, so that Docker and the base image are already checked and nothing binds yet. The `budget_job` test calls `cmd_build` with no runner and no port, so the sweep is off there.
- `ci/iris.sh:548-590` -- `traces_on`, the sibling self-hosted check (Rule 2). The sweep does the same two-variable test inline. `traces_on` stays unchanged, because its reason texts are pinned by the traces tests.
- `ci/iris.sh:849-886` -- `cmd_teardown`. Extract its per-project down (`:870-873`) into `project_down <p>`, which both teardown and the sweep use (extend, do not copy). The output and arguments stay byte-identical, and the teardown pins at `test-ci-config.sh:1956-2055` must stay green.
- `docker/tests/lib-live.sh:339-368` -- `live_bounded` and `live_port_holders`. Reuse the holder query style (`ps -a --filter publish=`, the project label) for a parseable listing. `live_bounded` runs `timeout 10 docker ...`, and macOS has `/usr/bin/timeout`, so a docker shell-function stub is bypassed and the REAL docker runs. The hermetic stub must be an executable first on PATH (precedent: `test-lib-live.sh:1158-1175`).
- `docker/tests/lib-live.sh:204,235,264-309` -- `LIVE_FORBIDDEN_PORTS` (no entry lies in 52800-52819), `port_in_use` and `live_web_port`. Read only.
- `ci/units.sh:6` -- `CHECK_SCRIPTS`. Add `ci-sweep`. The units rule in `test-ci-config` then requires that it appears exactly once.
- `ci/compose.ci.yml:36` and `ci/iris.sh:103` -- the mock's pinned image and `mock_image()`, which is the image the `--live` plants use.
- `docker/tests/test-ci-warm.sh:1-60` -- the sibling for the header shape, the `check` helper and the `--live` mode (developer machine only, never CI).
- `docker/tests/test-ci-config.sh:296-314,347-398,401-446,561-609` -- the workflow facts, the teardown rule (the model for the new rule), `good.yml`, `make_bad` and the rule lines.
- `.github/workflows/ci.yml:120-148` and `lane-a.yml:40-121` (read only) -- every self-hosted job runs `bash ci/iris.sh build` as its first script step. In `ci.yml` only `ci/changes.sh` comes before it.

## Tasks & Acceptance

**Execution:**
- `ci/iris.sh` -- Add `project_down` (extracted from teardown) and `runner_sweep` (the Boundaries and Matrix rules), and call it from `cmd_build`. Update the header.
- `docker/tests/test-ci-sweep.sh` (new, executable) -- The default hermetic mode runs every Matrix row and a registration check (`ci-sweep` is in `CHECK_SCRIPTS` only). The stub is a PATH executable that reads a table file, `name|project|port|state`. It answers `ps -a --filter publish=<p>` with the rows for `<p>`, and `--filter label=com.docker.compose.project` with every compose row. It removes the rows of a project on `compose -p <P> ... down`, and one row on `rm -f -v <name>`, and it records every call. The test FAILs before any case if `command -v docker` is not its stub. Each case sets its own env (`env -u` for `GITHUB_ACTIONS`, `RUNNER_ENVIRONMENT`, `RUNNER_NAME`, `OCUTALON_TEST_WEB_PORT`, `OCUTALON_RUN_TAG`) and its own `TMPDIR`.
- `docker/tests/test-ci-sweep.sh --live` -- For the developer machine only. With `GITHUB_ACTIONS=true` it exits 2 with no docker call (a hermetic row pins this).
  - It needs a reachable daemon and the mock image to be present; it never pulls.
  - It picks two free ports, A and B, from 52819 down to 52806. Free means `port_in_use` is false and `docker ps -a --filter publish=` is empty. Ports 52800-52805 are the lanes' and ci-20's.
  - It plants three projects under its own tag: `ocutalon-sweepa-<tag>-<epoch>-<pid>` (iris on `127.0.0.1:A:52773` plus a port-less mock), `...sweepb...` on B, and a port-less `...sweepc...`. Each uses the mock image, `init: true` and `sleep 300`. It waits up to 20 s until A is in use.
  - Before the sweep, it requires the holders of A to be exactly its project A. If they are not, it FAILs without sweeping.
  - It then runs the real `cmd_build` in a subshell with CI env and `OCUTALON_TEST_WEB_PORT=A`, with `preflight` and `ensure_web_bundle` stubbed.
  - It asserts four things: the SWEEP line names A; A has no container left; B and C are still running, and B still publishes B; and `live_web_port` (`LIVE_PORT_WAIT=0`) returns 0 for A. The mock image must still be present afterwards.
  - Its EXIT trap downs exactly its three names (`down -v -t 0 --remove-orphans`, no `--rmi`). Expected runtime is about 20-40 s (inference).
- `ci/units.sh` -- Add `ci-sweep` to `CHECK_SCRIPTS`.
- `docker/tests/test-ci-config.sh` -- New rule `job-start`: in every self-hosted job of every workflow file, the first step with a `run:` other than `bash ci/changes.sh ...` is exactly `bash ci/iris.sh build`.
  - Give `good.yml`'s runner job a `bash ci/iris.sh build` step before `Run`.
  - Add the bad samples `job-start-missing` and `job-start-late` (a `group` step before `build`). Every other rule must still flag its own samples.
  - Update the header bullets, both for `job-start` and for teardown's `project_down`.

**Acceptance Criteria:**
- AC1: Given the CI env with a fixed port and a planted throwaway project publishing it, when `ci/iris.sh build` runs, then that project is brought down before the bundle step, `SWEEP removed project <P> (it published 127.0.0.1:<p>)` is logged, the build exits 0, and `live_web_port` then binds that port.
- AC2: Given projects on another runner's port, a project with no published port, a non-compose container and a non-throwaway project on the port, when the sweep runs, then none of them is touched, and each holder on the port gets a `SWEEP kept` line.
- AC3: Given a local run (not a self-hosted runner), or auto mode, or a bad preset, when `build` runs, then `SWEEP off: <reason>` is printed and no docker call is made.
- AC4 (real runtime, Rule 3): Given `test-ci-sweep.sh --live` on the developer machine, when it plants leftovers on ports A and B and runs the job start for A, then A's whole project is gone, B and C survive, the mock image stays, and port A binds.
- AC5 (Integration, Rule 1): Given every self-hosted job in `ci.yml` and `lane-a.yml`, when `test-ci-config.sh` reads them, then `bash ci/iris.sh build` is each job's first script step after `ci/changes.sh`, so the sweep runs at the start of every IRIS job. Both bad samples are flagged.
- AC6: Given the change, when `git diff --stat <story_base>` is read, then only `ci/iris.sh`, `ci/units.sh`, `docker/tests/test-ci-sweep.sh` and `docker/tests/test-ci-config.sh` changed. There is no product, workflow, `release/` or public-text hunk, and the teardown, lib-live and warm pins are green.
- DW-1335: resolved by AC1-AC5. The owned ledger slice holds only this entry.

## Spec Change Log

## Review Triage Log

### 2026-11-14 - Review pass
- verdicts: 22 findings - high 0, medium 1, low 18, false 3, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: `project_down` and `rm -f -v` have no time bound - teardown's down line is equally unbounded and the job-level timeout bounds a hung daemon; a timeout adds a branch for an unobserved failure.
  - `[false]` `[reject]` Blind: the sweep does not release a warm stack's lock and state folder - warm stacks exist on a developer machine only (never CI, Rule 21) and the sweep runs only when GITHUB_ACTIONS=true and RUNNER_ENVIRONMENT=self-hosted.
  - `[low]` `[reject]` Blind: `job-start` ignores `if:` and `continue-on-error` on the build step - AC5 pins the first script step; ci.yml's classifier gate skips the whole group, so no stack runs and no sweep is needed; a stricter rule adds parsing for a case no workflow has.
  - `[low]` `[reject]` Blind: every self-hosted job must start with build, with no opt-out - that is AC5; every self-hosted job today runs a stack.
  - `[low]` `[reject]` Blind: no hermetic row for a throwaway plus a non-throwaway on one port, or two throwaways on one port - one host port has one holder, so the state cannot occur; the lowercase-only shape is the spec's regex.
  - `[low]` `[reject]` Blind: the spec's AC5 mutation text says "facts awk", the result line says "rules awk" - the fix edits this build's spec outside the Verification record.
  - `[low]` `[reject]` Blind: no closing line when a kept holder stays on the port - `live_web_port` already prints its FAIL line and the holder listing; a summary line adds a branch.
  - `[low]` `[reject]` Edge: a zero-padded preset such as 052814 is not swept - no runner derives or presets a padded port; a fix adds arithmetic parsing.
  - `[low]` `[reject]` Edge: after the rm fallback, a failed `project_down` leaves the port-less mock while `SWEEP removed project` is logged - needs the compose down to fail and the rm to succeed together; a second listing adds a branch.
  - `[low]` `[reject]` Edge: unbounded `compose down` - same as the Blind finding above.
  - `[low]` `[reject]` Edge: `job-start` ignores `if:` on the build step (ci.yml's classifier gate) - same as above; skipped groups run no stack.
  - `[false]` `[reject]` Edge: a multi-line run block starting with build is flagged - the rule compares the whole text on purpose (a first step that is more than `bash ci/iris.sh build` is the sample `job-start-late`).
  - `[low]` `[reject]` Edge (claim): ci.yml's build is gated on the classifier, so a skipped group sweeps nothing - a skipped group runs no stack; the next group that runs a stack runs build.
  - `[low]` `[reject]` Edge (claim): preflight runs before the sweep and can exit - the spec's Code Map orders it so, and a job that fails preflight runs no stack.
  - `[medium]` `[patch]` Verification gap: the throwaway shape check can be loosened with every test green - patched: `notaway` gained `ocutalon-dev-stack` and `ocutalon-demo-123-45` (kept, no down, no rm); mutation recorded.
  - `[low]` `[patch]` Verification gap: a failed listing after the rm fallback had no test - patched: case `psfail3` (STUB_DOWN_KEEPS=1, STUB_PS_FAIL_FROM=3); mutation recorded.
  - `[low]` `[reject]` Verification gap, other: AC4's real-runtime evidence is the developer-machine `--live` run, not CI - decided in the spec (no `--live` in CI).
  - `[false]` `[reject]` Verification gap, other: "bad preset (empty)" depends on the fixture's 52814 fallback - the assertion reads the SWEEP line and cannot pass without the sweep.
  - `[low]` `[reject]` Intent: the sweep runs after preflight, not first - same as the Edge claim; the intent says "at job start" and the Code Map fixes the order.
  - `[low]` `[reject]` Intent: the `job-start` rule pins text, not behaviour - AC5 is stated as that text check; the behaviour is AC1 and AC4.
  - `[low]` `[reject]` Intent: two cases beyond the matrix (two holders, listing fails) and the empty-preset treatment - consistent with the contract, not a defect.
  - `[low]` `[reject]` Intent: the DW-1335 incident is represented by a stub name only - the contract forbids touching a real runner host.

## Design Notes

- **Governing ADs (Rule 6):** AD-22. It covers testing and CI: throwaway projects, `ci/iris.sh` as the one recipe, and no `docker inspect` without `--format`. AD-29 (lanes) is not touched. No spine change (Rule 20): the sweep is internal to `ci/iris.sh` and constrains no other story.
- **How the port is known:** `setup_tag` derives it from `RUNNER_NAME` (n 0-9: 52810+n; 10-19: 52819-n). `ocutalon-ci-20` presets `OCUTALON_TEST_WEB_PORT=52805` in its runner `.env` (Rule 21). Projects are named by `live_start`, `ocutalon-<label>-<run id>-<attempt>-<group>-<epoch>-<pid>`, and carry `com.docker.compose.project`. A leftover has another tag, so `teardown` never reaches it.
- **Measured (Docker 29.7.2, the developer machine, read only):** `docker ps -a --filter publish=52803` matched the running container that maps `127.0.0.1:52803->52773`. `publish=52773` did not match it, so the filter matches the host port. An exited container that has a binding (`ocupilot-slot-c`, 52778) was not matched. An exited container holds no port, so it needs no sweep. Baseline timings: `test-ci-config.sh` 78 s, `test-ci-warm.sh` 61 s, `test-lib-live.sh` 67 s, `test-ci-changes.sh` 33 s.
- **Local behaviour (decided: CI only):** On a developer machine the sweep prints `SWEEP off: not a self-hosted CI runner` and calls no docker, even with a lane's `OCUTALON_TEST_WEB_PORT`. There are three reasons:
  - The one-job-per-port premise fails locally. An auto-mode run probes 52800-52819 and can take an idle lane's port, and a lane runs several sessions, so a stack on "my" port may be another session's live stack.
  - Rules 13 and 21: an agent removes only the projects it started.
  - Locally, `ci/iris.sh teardown <tag>` and `live_web_port`'s 90 s wait and holder listing already cover the case.
- **Decided in-stage:**
  - **Hook only in `build`:** it is the first script of every self-hosted job (AC5).
  - **No `--live` in CI:**
    - On the shared self-hosted hosts, other runners' fixed ports fill 52800-52819.
    - The hosted `checks` job starts no container (`ci/checks.sh`) and has no image, and a Docker Hub pull would add a flaky dependency to a job that is never skipped.
    - So CI runs the hermetic mode (`checks` job, `CHECK_SCRIPTS`), as the precedent `test-ci-warm.sh --live` does.
  - **Throwaway names only:** a holder that is not a throwaway is kept and logged (Rule 13). Every leftover our CI makes is a `live_start` project.
  - **The leftover's mock goes too:** its port-less mock is part of the leftover stack, so it is removed with it. Point (3) protects port-less stacks, not a leftover's own services.
  - **A failed sweep is not fatal:** it never fails the job.
  - **The plants use the mock's pinned image:** it is an existing dependency, so no new image comes in.
- **Integration ACs:** the consumers are the self-hosted jobs of `ci.yml` and `lane-a.yml`, through `build` (AC5). Consumed-by: no later story. Consumes: `setup_tag`, `live_bounded`, teardown's down line.
- **Planner gate:** none.

## Verification

**Commands** (from the worktree, `TMPDIR` in the scratch folder; each command finishes in one foreground call):
- (loop) `bash docker/tests/test-ci-sweep.sh` -- expected: exit 0 and every row PASSes. About 15 s (inference).
- (once) `bash docker/tests/test-ci-sweep.sh --live` -- expected: exit 0. Afterwards `docker ps -a --filter name=ocutalon-sweep --format '{{.Names}}'` is empty. About 40 s (inference).
- (once) `bash docker/tests/test-ci-config.sh` -- expected: exit 0, with `job-start` among the PASS lines (about 80 s).
- (once) `bash docker/tests/test-ci-warm.sh` (about 61 s), then (once) `bash docker/tests/test-lib-live.sh` (about 67 s), then (once) `bash docker/tests/test-ci-changes.sh` (about 33 s) -- expected: exit 0 each, unchanged.
- (once) `git diff --stat` -- expected: only the four files of AC6.

**Mutations** (one per AC; observe red, revert, then confirm that `git status --short` and `git diff --stat` are unchanged):
- AC1 mutation: delete the `runner_sweep` call in `cmd_build` → the hermetic row "Leftover on own port" goes red.
- AC2 mutation: list with `--filter label=com.docker.compose.project` instead of `publish=<p>` → the row "the 52813 project survives" goes red.
- AC3 mutation: drop the self-hosted guard → the "Local lane run" row goes red.
- AC4 mutation: `return 0` as the first line of `runner_sweep` → `--live` goes red (A still runs, `live_web_port` FAILs).
- AC5 mutation: comment out the `bad(..., "job-start")` call in the facts awk → the rule leaves `job-start-missing` and `job-start-late` unflagged and FAILs.
- AC6 mutation: drop `--remove-orphans` in `project_down` → `test-ci-config` "teardown: each project comes down with ..." goes red.

**Mutation results (implement stage):**
- mutation: AC1 deleted the `runner_sweep` call in `cmd_build` -> test-ci-sweep.sh hermetic "leftover on own port" rows went red (SWEEP removed line, compose call, order, table), plus every other SWEEP-line row
- mutation: AC2 listed with `--filter label=com.docker.compose.project` instead of `publish=<p>` -> test-ci-sweep.sh "leftover on own port: the 52813 project survives and the port-less project is never named" went red
- mutation: AC3 replaced the self-hosted guard with `if false` -> test-ci-sweep.sh "local run (unset|hosted|norunnerenv)" rows went red
- mutation: AC4 `return 0` as the first line of `runner_sweep` -> test-ci-sweep.sh --live went red ("the real job start for A removes its project" and "a container of the project of A is left")
- mutation: AC5 removed the `bad(..., "job-start")` call in the rules awk -> test-ci-config.sh `job-start` FAIL ("the rule does not flag the sample job-start-missing")
- mutation: AC6 dropped `--remove-orphans` in `project_down` -> test-ci-config.sh "teardown: a project did not come down with 'down -v --rmi local --remove-orphans' and the CI override" went red
- mutation: AC2 (non-throwaway shape) loosened `sweep_throwaway`'s regex to `^ocutalon-` -> test-ci-sweep.sh "not a throwaway" rows went red (`ocutalon-dev-stack` and `ocutalon-demo-123-45` were taken down)
- mutation: AC1 (a failed listing after the rm fallback) replaced the inner listing guard with a bare assignment -> test-ci-sweep.sh "listing fails after the rm" went red (SWEEP removed was logged)
Each file was restored byte-identical from a saved copy (cmp), and `git status --short` was unchanged.

**Shared surfaces:**
- `CHECK_SCRIPTS`: the units rule and `ci/checks.sh`.
- `ci/iris.sh build` output: the REL-4 `budget_job` and `recipe ... -- build` rows.
- teardown's down line: the teardown pins.
- `test-ci-config.sh`'s `good.yml`: every rule's bad samples.

Every test that is added or changed passes on a fresh environment in either order: run `--live`, then the hermetic mode, then the reverse.

## Auto Run Result

Status: done
Blocking condition: none

**Change:** `ci/iris.sh build` now sweeps the runner's fixed web port. On a self-hosted runner with a port in 52800-52819 it removes every throwaway compose project that publishes that port (the leftover's port-less mock goes with it) and logs one `SWEEP` line per outcome. It never fails the job and never runs in `group`, `live`, `shard` or `class`.

**Files:**
- `ci/iris.sh`: `project_down` (extracted from teardown, same arguments), `runner_sweep`, `sweep_holders`, `sweep_throwaway`; called from `cmd_build` after `preflight`; header updated.
- `ci/units.sh`: `ci-sweep` in `CHECK_SCRIPTS`.
- `docker/tests/test-ci-sweep.sh` (new): hermetic mode (PATH docker stub, every matrix row through the real `cmd_build` and `live_web_port`, plus extra rows) and `--live` (own throwaway projects, developer machine only).
- `docker/tests/test-ci-config.sh`: rule `job-start` with `job-start-missing` and `job-start-late` samples.
- This spec (Verification mutation lines, Review Triage Log).

**Review:** 22 findings, 2 patched (a non-throwaway shape fixture set, a failed-listing-after-rm case), 0 deferred, 20 rejected with reasons in the Review Triage Log. Follow-up review recommended: false (no high patched, one medium patched).

**Verification (all exit 0):** `test-ci-sweep.sh` hermetic (twice, after the patch too) and `--live` (ports 52819 and 52818, nothing left behind), `test-ci-config.sh` (42 PASS, `job-start` among them), `test-ci-warm.sh`, `test-lib-live.sh`, `test-ci-changes.sh`, `test-boundaries.sh`. Eight mutations, one per AC plus two from review, each red then restored byte-identical.

**Residual risks:** the sweep has no time bound on `compose down` (same as teardown); `--live` is not run in CI by design, so the real-docker path is proved on a developer machine only. Nothing was pushed.
