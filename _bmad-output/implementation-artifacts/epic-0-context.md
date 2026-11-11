# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton. One image build and `docker compose up` give OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start. It provides a branded page behind sign-in, the Orders demo production in OCUORDERS, every cross-lane contract and production stub, and CI with the model mock, so the build lanes can work in parallel. Stories 0.1 to 0.23 are done. Epic 0 is re-opened once more (lane C, after Story 0.23) for Story 0.24, a CI-tooling fix for DW-1099. CI jobs have failed before running a single test with "failed to bind host port 127.0.0.1:52816/tcp: address already in use", also logged as "driver failed programming external connectivity". 52816 is the runner's own fixed web port, and no orphan container held it. The most likely cause is that a job starts its next throwaway stack before Docker's port proxy has released the previous stack's port after `compose down`. The goal is that no throwaway test stack can publish its web port on a host port that is still being released.

## Stories

- Story 0.1: The image builds and starts OcuTalon in its own namespace (done)
- Story 0.2: The package installs and upgrades itself at every start (done)
- Story 0.3: Sign in to an empty OcuTalon page (done)
- Story 0.4: The cross-lane message and data contracts (done)
- Story 0.5: Live events and the REST skeleton (done)
- Story 0.6: Every release-1 production item runs as a stub, beside the Orders production (done)
- Story 0.7: CI runs on hosted runners and the IRIS runner, with the model mock (done)
- Story 0.8: The demo-path test signs in and loads the page (done)
- Story 0.9: The message catalog and its one renderer (done)
- Story 0.10: The Orders demo production runs in OCUORDERS (done)
- Story 0.11: The CI model mock answers every scenario the stories need (done)
- Story 0.12: Epic 0 burn-down (done)
- Story 0.13: A start retries the CPF merge when IRIS cannot quiesce (done)
- Story 0.14: A start that recovers through the merge retry passes the live checks and the upgrade harness (done)
- Story 0.15: The Dockerfile sits at the repository root (done)
- Story 0.16: The Embedded Python callback crash (S11) is re-verified with a minimal reproduction (done)
- Story 0.17: The README's evaluation table shows release 1.0.4's numbers (done)
- Story 0.18: The README shows judges where to look (done)
- Story 0.19: The README names the contest (done)
- Story 0.20: Rebalance the IRIS CI groups so every group finishes well under the 35-minute budget (done)
- Story 0.21: The README opens with a centred header: logo, tagline and badges (done)
- Story 0.22: The More to try panel shows its items under three group headings (done)
- Story 0.23: The README header's logo and LICENSE badge link use absolute GitHub URLs (done)
- Story 0.24: A test stack's web port can never collide with a port that is still being released (backlog)

## Requirements & Constraints

**Two ruled fixes (0.24); the spec picks one.** The spec must say which fix it chose and why, and list the files it touches.
- **Preferred: ephemeral port.** Publish the web port as `127.0.0.1::52773`, so Docker picks a free host port. Read it back with `docker compose port` after the stack starts. This replaces both the fixed per-runner scheme in `ci/iris.sh` (52810 + n and 52819 - n) and the port probe in `docker/tests/lib-live.sh` (`live_web_port`). Every web client must then use the read-back port: each live script's `base`, the Playwright configs and `web/e2e/support`, `ci/**`, and the release harnesses.
- **Fallback: wait and retry once.** Take this only if the preferred fix is too large (more than about 2 to 3 hours of work). Before each stack start, wait up to 20 s for the chosen port to be free: `ss -ltn` on Linux, or an equivalent such as `lsof -iTCP:<port> -sTCP:LISTEN` for local macOS runs. Then retry the start exactly once, and only on exactly this bind error ("address already in use" or "failed programming external connectivity"). If the retry also fails, fail loudly.

**Invariants either way.**
- `OCUTALON_TEST_WEB_PORT` keeps working as an explicit override. The lanes' dev slot ports 52801 to 52804 and the lanes' throwaways depend on it, so check every local caller.
- The web port stays bound to 127.0.0.1 only.
- The forbidden ports stay refused.
- No test-logic change.
- No workflow-file change beyond what the port needs.

**Tests.**
- `docker/tests/test-ci-config.sh`, `test-ci-changes.sh` and `test-lib-live.sh` pass, and so does `docker/tests/test-boundaries.sh`.
- Every pin of the old port scheme that changes moves to the new one. No pin is deleted or weakened beyond what the chosen fix replaces.
- A self-test or unit covers the new port logic:
  - Preferred fix: an ephemeral port is read back, and every web client uses it.
  - Fallback: a held port is waited for, and the bind error is retried once and then fails loudly.

**Done means:**
- On a lane-C throwaway, two stacks started back to back (the way `release/ipm-install.sh` path B and part p do) both come up, and the second answers on its web port with no bind error.
- DW-1099 is resolved by this story.
- Every workflow is green on the story's head.

## Technical Decisions

- **Throwaway stacks.** Destructive and CI tests run only in throwaway compose projects (`docker compose -p <name>` with the CI override), never on a developer instance. `ci/iris.sh` is the one recipe that runs the IRIS units, on the runner and on a developer machine. `ci/compose.ci.yml` is layered after the throwaway override.
- **CI hosts.** ci-b holds runners 3 to 8, ci-c runners 9 to 14, and ci-d runners 15 to 20. Each runner currently has its own fixed web port.
- **Release-tool gate.** Any `.github/workflows/*.yml` or `release/**` hunk is a RELEASE TOOL item and goes to the Contest Planner before it merges. CI log message text is internal, so there is no PUBLIC TEXT gate.
- **Never weaken checks.** Never delete or weaken a rule or self-test. Shell test scripts stay ASCII-only and run on bash 3.2 with BSD or GNU tools; for example, BSD `head -n 0` fails, so use `awk`.
- **Lane ownership.** Epic 0 may edit files from any lane in one story. Never write a local absolute path into a tracked file.

## Cross-Story Dependencies

- **Builds on** Story 0.7 (CI on the IRIS runner and the throwaway recipe), Story 0.14 (`lib-live.sh` checks used by the live tests and the upgrade harness) and Story 0.20 (the IRIS CI groups).
- **Sequenced after 0.23** on lane C.
- **Failures this story removes.** The bind error is DW-1099: lane-a run 42907226019 (two failures on the same port 6 s apart) and ci run 42894860855 (`live:online-demo`).
- **Known flakes.** Other inherited CI flakes (for example DW-973, DW-774, DW-689 and DW-1026) can turn a run red without a cause in this story. Classify them; do not change the story to work around them.
