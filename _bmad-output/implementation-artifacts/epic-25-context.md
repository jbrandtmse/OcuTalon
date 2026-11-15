# Epic 25 Context: Usage, history and files in the page (step 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 25 is Lane B's half of step 6. Users can filter History, send a file from the web app or Telegram, and assign and enforce approver and viewer roles; a sent file gets a reply. Stories 25.2 to 25.5 are done and 25.6 is in the backlog. The remaining story, 25.7, is a CI burn-down and touches no product code. A cancelled CI job skips its teardown, so its compose stack keeps running and holds the runner's fixed web port. After that, every later browser unit on that runner fails at `live_web_port` with "port <p> is in use on 127.0.0.1". This happened to runner `ocutalon-ci-4` on port 52814 (DW-1335). The fix must land before the 1.0.10 release candidate.

## Stories

- Story 25.2: Filter past decisions and incidents on the History page (done)
- Story 25.3: Send a PDF, Word file or photo from the web app or Telegram (done)
- Story 25.4: Assign approver and viewer roles in Settings (done)
- Story 25.5: Answer only with the right approver role, and say why otherwise (done)
- Story 25.6: Reply to a sent file: Add to documents, Saved to memory and the read failure (backlog)
- Story 25.7: Epic 25 burn-down: a cancelled CI job's stack no longer blocks its runner's web port

## Requirements & Constraints

- When an IRIS job starts, before anything binds the port, `ci/iris.sh` removes every compose stack that publishes this runner's fixed web port. It logs each project it removes.
- It never touches a stack on another runner's port, and never a container that publishes no port.
- The premise is that one job runs per runner. So on a self-hosted runner with a fixed port, any stack already publishing that port at job start is a leftover by definition.
- Test: plant one compose project bound to the runner's port and another on a different port, then run the job start. The planted leftover must be removed and the job must go on, while the other stack survives.
- The test must be a demonstrated mutation: with the cleanup skipped, it fails.
- Test and CI only. Nothing changes in the product and there is no new public text.

## Technical Decisions

**Runner and port model**
- Self-hosted runners (`runs-on: [self-hosted, ocutalon]`) are spread over a few hosts. Runners on one host share its 127.0.0.1, so each runner has its own fixed port.
- `setup_tag` takes the trailing number n of `RUNNER_NAME` (for example `ocutalon-ci-4`) and exports `OCUTALON_TEST_WEB_PORT`:
  - n from 0 to 9: 52810 + n
  - n from 10 to 19: 52819 - n
  - n of 20 or more, no number, or no runner name (a developer machine): the variable stays unset ("auto"), and `live_web_port` probes 52800-52819 for the first free port.
  - A preset `OCUTALON_TEST_WEB_PORT` always wins.
  - The cleanup should act only on a fixed port, never in auto mode. Be careful about running it on a developer machine.
- `LIVE_FORBIDDEN_PORTS` (the judges' 52773, slots and other instances) must never be touched.

**Job flow**
- The `iris` job in `ci.yml` (16-group matrix, timeout 50 minutes) runs `ci/iris.sh build`, then `group <g>`, then `teardown` (`if: always()`). `OCUTALON_RUN_TAG` is `<run id>-<attempt>-<group>`.
- The lane-a.yml jobs run `build` first and `teardown` last.
- `cmd_group` calls `setup_tag` and `preflight`, then runs each unit as a child `bash ci/iris.sh live|shard ...`, which calls `setup_tag` again.
- `cmd_teardown` removes only projects that match `^ocutalon-[a-z0-9-]+-<tag>-<epoch>-<pid>` (never "slot"). It runs `docker compose -p <p>` with `docker-compose.yml`, `docker/tests/compose.throwaway.yml` and `ci/compose.ci.yml`, then `down -v --rmi local --remove-orphans`. A leftover belongs to a different tag, so teardown never reaches it. The new cleanup selects by published port, not by tag.

**Throwaway stacks (`docker/tests/lib-live.sh`)**
- Projects are named `ocutalon-<label>[-<run tag>]-<epoch>-<pid>`.
- The throwaway override resets `ports`, so a stack publishes nothing unless a browser unit calls `live_web_port`. That call writes `$tmp/port.yml` (`127.0.0.1:<port>:52773`), so the leftover's own port file is gone.
- `live_web_port` waits up to `LIVE_PORT_WAIT` (90 s) for an override port that is in use, then fails.
- `live_port_guard` and `live_port_holders` already find holders with `docker ps -a --filter publish=<p>` and the `com.docker.compose.project` label. Reuse that query style, bounded by `live_bounded` (timeout 10).
- The warm stack (`ci/warm.sh`) publishes no port.

**Self-tests (`ci/` and `docker/tests/`)**
- `test-ci-config.sh` pins the workflow and recipe rules, `ci/iris.sh` included.
- Sourced, `ci/iris.sh` defines its functions and runs nothing. Its tests stub `docker` as a shell function and stub `port_in_use`.
- `test-lib-live.sh` covers `live_web_port` and the port guard. `test-ci-warm.sh` covers warm mode.
- These scripts are `CHECK_SCRIPTS`, run by `ci/checks.sh` in the hosted `checks` job (25 minutes). They start no container, so the planted stacks must come from a docker stub.
- Every new rule must show itself flagging a bad sample first. Update the header comments of `ci/iris.sh` and `test-ci-config.sh` to cover the new behaviour.
- The owner keeps a 10-minute Bash cap, so keep local test runs short.

## Cross-Story Dependencies

- Story 25.7 does not depend on 25.6 or on Epic 26.
- Story 25.7 touches the CI infrastructure that every IRIS group and the lane-a jobs share. Leave `live_web_port`, the port mapping and the `teardown` semantics unchanged for every other caller.
