# Epic 32 Context: CI gives a verdict in about ten minutes, even with both lanes pushing

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 32 keeps CI's verdict fast and trustworthy inside REL-4's 35-minute budget. It splits long jobs, skips the groups a push can't affect, and keeps the groups balanced. Stories 32.1 to 32.5 are done. The epic is re-opened (SC-5) for Story 32.6, a test-only story for two host-load flakes. In DW-550, live pages time out in `loadedAfter`'s `/state` wait after sign-in, for example live:cards I10. In DW-774, live:online-session's leave.spec `page.close` (L5, L6) and `GET /state` (decision D2, sign-in-2 W3) get no answer within 30 s under heavy CI load. Both pass on an unchanged rerun, so they turn green heads red. Story 32.6 either finds the cause and fixes it in the tests, or adds one retry per wait that is logged and counted, so that every retry is visible.

## Stories

- Story 32.1: The install group runs as two jobs (done)
- Story 32.2: An IRIS group runs only when something it tests changed (done)
- Story 32.3: Every IRIS job finishes in about ten minutes (done)
- Story 32.4: The developer loop reuses one warm throwaway per lane (done)
- Story 32.5: live:sign-in splits again after 4.11's tests (done)
- Story 32.6: A live page's /state wait under CI load either finds its cause or retries once, logged

## Requirements & Constraints

- **Timebox.** Investigation gets at most 90 minutes from the spec gate. The spec then records one of two outcomes:
  - the cause, with evidence of where the `/state` GET or `page.close` waited: never sent by the page, queued in the browser, queued at the web gateway, or held in IRIS;
  - `none_in_timebox`, with what was read and what was ruled out.
- **Bounds stay put without evidence.** A fix that makes a wait longer needs its own diagnostics showing that the page did send `/state` and that the answer was queued on the CI host, not lost in IRIS. Without that evidence these stay as they are:
  - `web/e2e/support/bounds.ts`;
  - `loadedAfter` in `web/e2e/support/floor.ts`;
  - the projects' waits and the test timeouts;
  - `OCUTALON_LIVE_DEADLINE`.
- **Fallback when no cause is found.** The diagnostics land together with a bounded retry of the page load:
  - at most one retry per wait;
  - each retry prints `RETRY <spec>:<line> <step>`, and the CI summary counts these lines;
  - a second failure fails as it does today, naming its step;
  - the retry is reported in the completion contract.
- **Proof.** The old code goes red under the load harness: four concurrent CI-like runs, or the project's load recipe if one is recorded (Rule 21 records none at the time of this compile). The fix then passes 20 of 20 under the same load. Both results go in the spec's `## Verification` with their counts.
- **Scope of change.** Test-only. Fixes go in test support code, specs or `ci/` test scripts.
  - Nothing under `src/**` changes.
  - The release tools are frozen: `release/*.sh`, `eval/run.sh`, the upgrade harness, demo-host-check and the IPM scripts.
  - No real model key is used.
  - Other epics' specs change only in the shared support files (`web/e2e/support/**`) and in the wait-related lines of the specs the occurrences name.
- **Limits that still hold.** Every group stays under 35 minutes. No deadline or timeout is raised as the fix, and no test is removed or weakened.
- **Done means.** `docker/tests/test-boundaries.sh` passes before the push, and full CI is green on every workflow.
- **Secrets and images.** Never run `docker compose config` without `--quiet`, or `docker inspect` without `--format`.

## Technical Decisions

- **What `/state` is.** The page first reads `GET /api/v1/state`, a snapshot that includes each stream's last `Seq`. It then polls `/api/v1/events` every 1 to 2 seconds, or uses a WebSocket where it can connect.
  - `LastSeq` waits for an open publish on its stream, so `/state` never hands out a cursor ahead of a committed event. This is one way an answer can be held in IRIS.
  - `/ocutalon` and `/ocutalon/api` share one CSP session.
- **Diagnostics already in place (Story 11.27).**
  - On CI, a failing test keeps its Playwright trace (`retain-on-failure`). The trace moves to the self-hosted runner's own disk, outside the job workspace, under the run tag and the unit name. Run folders older than 7 days are deleted.
  - Traces are never uploaded, because the repository is public. A test pins that no `actions/upload-artifact` path includes the trace folder.
  - When `loadedAfter`'s snapshot GET passes its bound, the diagnosis prints `DIAG /state gateway ...` lines beside the licence, CSP-process and session-lock lines. Those lines hold counts and states only: no body, cookie, session id or token.
  - The DIAG lines also reach the test's output folder, which the failure artifact uploads.
  - What these diagnostics measured so far: under host load, the request never reaches IRIS.
- **Already ruled out.**
  - Story 11.27's first step ruled out the gateway's per-session connection cap (`Maximum_Session_Connections`).
  - Story 11.22 looked into held CSP sessions and licence units.
- **CI as built.** There are ten IRIS groups, each a job of the `iris` matrix: `install-fresh`, `install-upgrade`, `production`, `browser`, `shards`, `shards-2`, `image`, `shards-3`, `shards-4` and `shards-5`.
  - `ci/units.sh` is the one list of units and groups.
  - Every live script runs on the Health image in CI, on its own fresh throwaway.
  - A group skips its own steps only when nothing it checks changed since the last green push run.
- **One recipe.** `ci/iris.sh` runs every IRIS unit, on the runner and on the developer machine, always on throwaway compose projects through `docker/tests/lib-live.sh` and `ci/compose.ci.yml`.
  - Use one `OCUTALON_RUN_TAG` per session, run one piece per call, and finish with `teardown` and the same tag.
  - Use the lane's own `OCUTALON_LOCK_DIR` (Rule 21).
  - `live` units refuse `OCUTALON_WARM`, so the load runs always start fresh stacks.
- **Where records go.** Measured facts may be appended to Rule 21's sections of `_bmad/custom/skill-rules.md`.

## Cross-Story Dependencies

- Story 32.6 builds directly on Story 11.27's traces and DIAG lines and on Story 11.22's failure artifacts. Read their occurrences and artifacts first, before adding new instrumentation.
- The occurrences sit in specs that other epics own: live:cards I10, live:online-session's leave.spec L5/L6, decision D2, and the `sign-in-2` project's W3 (from the 2026-11-05 split, extended by Story 32.5). Only their wait-related lines may change.
- The `browser` group holds the demo path (REL-2). A retry must never hide a real demo-path failure: a second failure still fails.
