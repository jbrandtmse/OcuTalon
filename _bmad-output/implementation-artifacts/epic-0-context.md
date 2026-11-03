# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton: one image build and `docker compose up` give OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start, with a branded page behind sign-in, the Orders demo production in OCUORDERS, every cross-lane contract and production stub in place, and CI with the model mock. Stories 0.1 to 0.13 are done and merged; Story 0.13 made a start retry the CPF merge when IRIS answers ERROR #453 ("cannot quiesce"). Epic 0 is re-opened again for one fix-forward, Story 0.14: the live-test library's log check still keeps every STEP line, so a start that recovered through that retry and became healthy is still read as a failure by the live tests, the clean-machine rehearsal and the release upgrade harness. Story 0.14 makes exactly that one sanctioned recovery count as a pass, and makes the upgrade harness report how many retries its starts carried, so a rare #453 stops failing healthy starts while every retry stays visible.

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
- Story 0.14: A start that recovers through the merge retry passes the live checks and the upgrade harness (backlog; the only open story)

## Requirements & Constraints

- **The one sanctioned recovery passes.** When a start log carries exactly one `STEP merge RETRY 1 after #453` line and a `STEP merge OK` line follows it in the same start log, `check_log` treats the start as matching its expected STEP and RESULT lines, as if the merge had succeeded first time.
- **Everything else fails exactly as today:** any `STEP merge FAILED` line; a second `RETRY` line (any number); a `RETRY` line with no `STEP merge OK` after it; a `RETRY` line in any other form (a near-miss of the exact text). No other STEP or RESULT line is ignored or loosened.
- **Retries stay visible.** The upgrade harness's result names how many `STEP merge RETRY` lines its starts carried, 0 when none.
- **Tests:** the live-library test pins one RETRY then OK (pass), and RETRY with no OK, two RETRY lines, RETRY then FAILED and a near-miss RETRY line (each fails); the harness test's fixtures read a count of 0 and of 1.
- **Scope lock:** `docker/after-start.sh` and `docker/merge.cpf` stay unchanged. Done when the fixtures pass and CI is green on every workflow (`ci` and `lane-a`).
- **Release placement:** the 1.0.0 release candidate takes this story only if it has merged by the time Story 31.3 merges; otherwise it ships in the first daily release after 1.0.0. It must never become rc1's last item.

## Technical Decisions

- **Start log format (fixed by the start sequence):** the after-start script writes `STEP <name> OK|FAILED` per step and a final `RESULT OK <version>` to `/durable/ocutalon-after-start.log`, rewritten every start; a non-fatal condition is a `WARN <step> <text>` line that never changes the result. Story 0.13 added exactly one line per merge retry, `STEP merge RETRY <n> after #453`, before the merge's final OK or FAILED line. That text is fixed: the Contest Planner's rehearsal counts it across 20 starts.
- **Where the check lives:** `docker/tests/lib-live.sh`'s `log_steps` extracts the STEP lines and `check_log` compares them with the expected list. Both the live install tests and `release/upgrade-harness.sh` use them, so one change covers both.
- **Readiness is unchanged:** a start is ready only when the ready marker equals the image's version; the health check opens no IRIS session. Story 0.14 changes only how test tooling reads the log, not what makes a start ready.
- **Platform:** the scripts also run under the host's bash in hermetic tests (3.2 on macOS), so keep the matching logic in portable shell.
- **CI rules:** every `docker/tests/test-*.sh` belongs to exactly one of `CHECK_SCRIPTS`, `WEB_SCRIPTS` or an IRIS group in `ci/units.sh`, or `test-ci-config.sh` fails. A full CI run stays within 35 minutes. Scripts never run `docker compose config` without `--quiet` or `docker inspect` without `--format`.
- **Ownership:** `docker/` is Lane B's apart from Lane A's `merge.cpf`, and `release/` is Lane A's release work. Only Epic 0 edits both lanes' files together.

## Cross-Story Dependencies

- **Builds on Story 0.13's retry and its log line.** The exact form `STEP merge RETRY <n> after #453` and the bound of one retry that leads to OK are what `check_log` must recognise; nothing else should match.
- **Existing tests to extend:** `docker/tests/test-lib-live.sh` and `docker/tests/test-upgrade-harness.sh`, both already in `CHECK_SCRIPTS` (the hosted checks job). The live install tests (`test-install-start.sh`, `test-install-upgrade.sh`) inherit the change through `lib-live.sh`.
- **Downstream consumers:** the release upgrade harness (one check at 1.0.0, run on a new Linux droplet), the Planner's clean-machine rehearsal (Story 38.2), which counts retry lines across 20 starts, and the 1.0.0 candidate's gates. Story 31.3's merge decides whether this story is in rc1.
- **Out of scope:** the larger rework that stops re-merging on an unchanged start belongs to the first daily release after 1.0.0.
