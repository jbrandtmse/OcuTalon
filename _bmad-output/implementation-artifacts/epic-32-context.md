# Epic 32 Context: CI gives a verdict in about ten minutes, even with both lanes pushing

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 32 keeps CI's verdict fast and trustworthy inside REL-4's 35-minute budget. It splits long jobs, skips the groups a push can't affect, and keeps the groups balanced. Stories 32.1 to 32.6 are done. The epic is re-opened (SC-5) for Story 32.7, a test-only story for the CI flakes that remain. Each of these fails only on a loaded CI host and passes on an unchanged rerun, so it turns a green head red. For each entry group, Story 32.7 either finds the cause and fixes it in the tests, or contains it with at most one retry per wait that is logged and counted. A cause found in product code goes to the Planner before anything is fixed.

## Stories

- Story 32.1: The install group runs as two jobs (done)
- Story 32.2: An IRIS group runs only when something it tests changed (done)
- Story 32.3: Every IRIS job finishes in about ten minutes (done)
- Story 32.4: The developer loop reuses one warm throwaway per lane (done)
- Story 32.5: live:sign-in splits again after 4.11's tests (done)
- Story 32.6: A live page's /state wait under CI load either finds its cause or retries once, logged (done)
- Story 32.7: The remaining CI flakes either find their cause or are contained, logged

## Requirements & Constraints

- **Entry groups in Story 32.7:**
  - DW-211: `Test.Agent.Runners` `TestStartRefused` fails on the Production step's not-running check, in CI's `lane-a` shard on the Linux host.
  - DW-639: `Test.Schedule.Heartbeat` `TestAfterAllTestsNothingSaved` fails "the production runs every item" in the `image` group's `lane-b`. `NotRunning()` names TelegramIn, with no jobs.
  - DW-774 (the `page.close` half): live:online-session's leave.spec `page.close` gets no answer within 30 s while the renderer and browser do answer, under host I/O pressure.
  - DW-973: `Test.Docs` `TestTimeLeft` fails under CI load because of a timing bound.
  - DW-966: tests that wait on `Observe.WaitDeliveries(session, 1, ...)` for any channel's row and then read only the web rows (`Test.Checks.BeatOutcomes`, about :106 and :254).
  - DW-911: when a retried test passes, its retry-time DIAG lines are never printed or uploaded.
- **Timebox.** Investigation gets at most 90 minutes per entry group from the spec gate. For each group the spec records one of two outcomes:
  - the cause with its evidence, and the fix;
  - `none_in_timebox`, with what was read and what was ruled out.
- **Product cause.** If the cause is in product code, investigation of that group stops and the evidence goes to the Planner first. No product file changes in this story.
- **Bounds stay put without evidence.** A fix that lengthens a wait needs its own evidence: what the test waited on, and that the wait ended late on the loaded host rather than the product failing. Without that evidence no bound or timeout changes.
- **Fallback when no cause is found.**
  - At most one retry per wait.
  - Each retry prints `RETRY <spec-or-class>:<line> <step>`, and the retries are counted in the `RETRIES` line of the CI group.
  - A second failure fails as it does today, naming its step.
- **DW-966: measure first.** Run each test once with a second channel's row recorded first. Fix the race only if that measurement shows it.
- **DW-911.** When a group's `RETRIES` count is above 0 and its job ends green, the retry-time `DIAG` lines are printed, or the results uploaded. This takes one changed step of `.github/workflows/ci.yml`.
  - The `RETRY` lines stay as they are.
  - `ci/units.sh` gains no new IRIS group for bookkeeping-only pushes (U-307).
- **Proof.** For each fixed entry, the old code goes red under the load harness, or under an injected stall where plain load does not reproduce the failure. The fix then passes 20 of 20 under the same load. Both results go in the spec's `## Verification` with their counts.
- **Scope of change.** Test-only. Fixes may go in:
  - the named test classes, in their wait and timing lines only (the only `src/**` change allowed);
  - `web/e2e/support/**`;
  - the leave spec's close lines;
  - `ci/` test scripts.
- **Frozen and forbidden.** The release tools are frozen: `release/*.sh`, `eval/run.sh`, the upgrade harness, demo-host-check and the IPM scripts. No real model key is used. Other epics' specs change only in the shared support files.
- **Limits that still hold.** No pin is deleted, weakened or moved, no deadline is raised as the fix, and every group stays under 35 minutes.
- **Done means.** `docker/tests/test-boundaries.sh` passes before the push, and full CI is green on every workflow.
- **Secrets.** Never run `docker compose config` without `--quiet`, or `docker inspect` without `--format`.

## Technical Decisions

- **CI as built.** There are ten IRIS groups, each a job of the `iris` matrix: `install-fresh`, `install-upgrade`, `production`, `browser`, `shards`, `shards-2`, `image`, `shards-3`, `shards-4` and `shards-5`.
  - The `%UnitTest` classes run in two lane-aligned shards. `lane-a` holds Agent, Bridge, Checks, Fix, Install, Tools, Digest, Watch, Eval and Channel, split across `shards`, `shards-2`, `shards-4` and `shards-5` (Bridge and Agent). `lane-b` holds the rest.
  - `ci/units.sh` is the one list of units and groups. A group skips its own steps only when nothing it checks changed since the last green push run.
- **One recipe.** `ci/iris.sh` runs every unit on throwaway compose projects, on the runner and on the developer machine.
  - Use one `OCUTALON_RUN_TAG` per session and finish with `teardown` and the same tag.
  - Use the lane's own `OCUTALON_LOCK_DIR`.
  - `live` units refuse `OCUTALON_WARM`, so load runs always start fresh stacks.
- **Retry plumbing from Story 32.6.**
  - A live retry is appended to `$OCUTALON_E2E_RETRY_LOG`.
  - `cmd_live` reprints only the `RETRY` lines and `RETRIES <n> in live:<unit>`.
  - `cmd_group` prints `RETRIES <total> in group <g>` on every run, 0 included, and writes them to the step summary only when the total is above 0.
  - `ci.yml` uploads results on failure only, which is why DW-911 exists.
- **Load harness from Story 32.6.** The lead runs it, not the implement stage. It uses one fresh throwaway at a time with four concurrent Playwright processes against it, optionally with host CPU load beside them.
  - Locally, plain load did not reproduce 32.6's flake (0 of 164). The "old red" half was therefore proven with an injected stall instead.
  - The implement stage's own verification stays hermetic and fast. Live units are left to the lead's proof and to CI.
- **Story 32.6's findings, which carry over.**
  - Its outcome was `none_in_timebox`.
  - The occurrences fell on all three CI hosts and did not follow host swapping. One failed on a quiet host.
  - For `page.close`, Story 32.6 landed diagnostics only and judged a retry of close not meaningful.
  - The L5 and L6 snapshots show the page still open and rendering after a CSP group sign-out in the same context.
- **Diagnostics already in place.**
  - Story 11.27 kept the Playwright traces on the self-hosted runner's disk. They are never uploaded, because the repository is public, and a test pins that.
  - Story 11.27 also added the `DIAG /state gateway` lines, which hold counts and states only.
  - Story 39.10 made the Heartbeat "production runs every item" pin name each missing item and its job's state. Its cause was never confirmed (0 red in 7 load runs).
- **Where records go.** Measured facts may be appended to Rule 21's sections of `_bmad/custom/skill-rules.md`.

## Cross-Story Dependencies

- Story 32.7 builds on Story 32.6's load harness, page-side diagnostics and `RETRIES` counts, and on Story 39.10's Heartbeat diagnostics. Read the occurrences and these artifacts before adding new instrumentation.
- The entries sit in test classes and specs that other epics own: Agent runners, Schedule.Heartbeat (Lane B), Docs (Story 19.7), Checks.BeatOutcomes, and live:online-session's leave spec. Only their wait and timing lines may change.
- DW-911 changes the step that Lane B owns in `.github/workflows/ci.yml`. The `browser` group holds the demo path (REL-2), so a retry must never hide a real failure there: a second failure still fails.
