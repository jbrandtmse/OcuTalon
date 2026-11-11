# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton. One image build and `docker compose up` give OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start. It provides a branded page behind sign-in, the Orders demo production in OCUORDERS, every cross-lane contract and production stub, and CI with the model mock, so the build lanes can work in parallel. Stories 0.1 to 0.24 are done. Epic 0 is re-opened again (lane B, after Story 0.24) for Story 0.25, a CI-tooling fix for DW-1099, which came back after 0.24. Story 0.24 added a guard in `docker/tests/lib-live.sh`: every guarded stack start waits up to 20 s for its web port, then retries once on the bind error. On ocutalon-ci-8 the guard still failed: it waited, retried once after 5 s and printed "FAIL web port: 127.0.0.1:52818 could not be bound after one retry". The likely cause, not proven, is that the previous unit's IRIS stack on the same runner was still shutting down, and a graceful IRIS shutdown can take well over the guard's 25 s or so. The goal is that the guard waits out a stack that is still shutting down, and that no unit's teardown can still be running when the next unit starts.

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
- Story 0.24: A test stack's web port can never collide with a port that is still being released (done)
- Story 0.25: The web-port guard waits long enough for a stack that is still shutting down (backlog)

## Requirements & Constraints

**The guard's new bounds (0.25).** This applies to every guarded start: `dc up`, `dc start` and `dc restart` with a web port, through `live_port_guard` and `live_port_wait_free`.
- When the port is in use, wait up to 90 s for it to be free, polling every 3 s. Linux uses `ss -tan (every state but TIME-WAIT)`; 0.24's macOS equivalent stays for local runs.
- When the start fails with exactly the bind error ("address already in use" or "failed programming external connectivity"), retry it up to twice, waiting again before each retry. After the second retry fails, print the same loud `FAIL web port: ...` line and return the failure.
- Any other failure returns at once, with no retry.
- Every guarded start that had to wait prints exactly one line, `waited N s for port P`, where N is the seconds waited and P is the port. The next ledger entry uses it to measure the wait.

**Teardown is waited for.** Check every live script's teardown path: a foreground `dc down`, a background one, or one run from a trap. A unit's teardown must run in the foreground and finish before the next unit can start. A teardown that ran in the background or was not waited for must now be waited for, with a foreground `dc down` or a wait on its PID.

**Out of scope.** No change to `ci/iris.sh`, the workflows or the release harnesses. Story 0.24's ephemeral-port option (publish `127.0.0.1::52773` and read the port back) stays out of scope. No test-logic change.

**Invariants kept from 0.24.**
- `OCUTALON_TEST_WEB_PORT` keeps working as an explicit override. The lanes' dev slots 52801 to 52804 and the lanes' throwaways depend on it.
- The web port stays bound to 127.0.0.1 only.
- The forbidden ports stay refused.

**Tests.**
- `docker/tests/test-lib-live.sh` runs with a stubbed docker and a fast clock or stubbed sleep, and passes with `docker/tests/test-boundaries.sh`.
- Its rows pin the 90 s bound, the 3 s poll, the two retries followed by the loud FAIL, the `waited N s for port P` line, and no retry on any other error.
- No existing row is deleted or weakened beyond what the new bounds replace.

**Done means:**
- On a lane-B throwaway, a port held for about 40 s by a listener is waited out: the start succeeds and logs the wait.
- A port held for more than 90 s gets two retries, then the loud FAIL.
- DW-1099 is resolved by this story again. DW-1100 (the FAIL line does not name what holds the port) and DW-1101 (step 5 of the install-script test is pinned only by a grep) keep their reopen condition: a CI log that shows "FAIL web port:".
- Every workflow is green on the story's head.

## Technical Decisions

- **Throwaway stacks.** Destructive and CI tests run only in throwaway compose projects (`docker compose -p <name>` with the CI override), never on a developer instance. Every live script and release harness starts its stack through `dc` in `lib-live.sh`, so the guard is the one place the fix goes. `ci/iris.sh` runs the IRIS units on the runner and on a developer machine.
- **CI hosts.** ci-b holds runners 3 to 8, ci-c runners 9 to 14, and ci-d runners 15 to 20. Each runner has its own fixed web port (52810 + n or 52819 - n), so the previous unit on the same runner is the likely holder.
- **Gates.** CI log message text is internal, so there is no PUBLIC TEXT gate. A hunk in `.github/workflows/*.yml` or `release/**` would be a RELEASE TOOL item for the Contest Planner, but this story makes none.
- **Never weaken checks.** Never delete or weaken a rule or self-test. Shell test scripts stay ASCII-only and run on bash 3.2 with BSD or GNU tools; for example, BSD `head -n 0` fails, so use `awk`.
- **Lane ownership.** Epic 0 may edit files from any lane in one story. Never write a local absolute path into a tracked file.

## Cross-Story Dependencies

- **Builds on** Story 0.24 (the guard: `live_port_guard`, `live_port_wait_free`, `live_bind_error`, and its hermetic rows in `test-lib-live.sh`), Story 0.14 (`lib-live.sh` checks for the live tests and the upgrade harness) and Story 0.7 (CI on the IRIS runner).
- **Sequenced after 0.24.** 0.25 runs on lane B.
- **The failure that reopened DW-1099:** run 42943118887, job 130269395421, iris (shards) `live:online-allowance` on ocutalon-ci-8. dockerd on ci-b logged the bind error at 02:21:35 and again at 02:21:44, and nothing held 52818 when it was checked at 02:45Z.
- **Known flakes.** Other inherited CI flakes (for example DW-973, DW-774, DW-689 and DW-1026) can turn a run red without a cause in this story. Classify them; do not change the story to work around them.
