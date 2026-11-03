# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton: one image build and `docker compose up` give OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start, with a branded page behind sign-in, the Orders demo production in OCUORDERS (demo mode), every cross-lane contract and production stub in place, and CI with the model mock. Stories 0.1 to 0.12 are done and merged. Epic 0 is re-opened for one fix-forward, Story 0.13, before the 1.0.0 tag: the after-start script re-runs `iris merge` at every start, and even an unchanged merge performs several namespace reactivations, each of which waits up to about 120 s for a system quiesce and fails with ERROR #453 when it cannot get one. CI hit this on a fresh first start and on the install-start test's restart row, so a user's first start, restart or image update (the online demo's 1.0.0 update recreates the container) can end not ready. A bounded retry on #453 alone closes that gap; the larger rework (no re-merge on an unchanged start) is routed to the first daily release after 1.0.0 and is out of scope.

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
- Story 0.13: A start retries the CPF merge when IRIS cannot quiesce (backlog; the only open story)

## Requirements & Constraints

Story 0.13's acceptance criteria carry five binding conditions added on November 3 under the owner's delegation; where they differ from the original criteria, they win:

- **Retry only on #453.** Retry the merge only when its output carries ERROR #453 ("Cannot quiesce the system for namespace reactivation"). Any other merge failure fails at once with no retry, exactly as today. A #453 on the last try ends the start not ready with the existing `STEP merge FAILED` report and no ready marker. A short pause separates the tries so the blocking job can finish. A merge that succeeds on a retry continues the start exactly as a first-try success does.
- **One countable line per retry:** exactly `STEP merge RETRY <n> after #453`, written to the start's log. The Contest Planner's pre-release rehearsal counts these lines across 20 starts, so the form is fixed.
- **Size the bound against `start_period`, not the live tests.** One #453 (about 122 s), the pause, a successful retry and the slowest measured first start (IPM and package install) must still reach healthy inside `docker-compose.yml`'s `start_period: 600s`. The spec's Design Notes must cite or measure the slowest first start and show the arithmetic. If it doesn't fit, this story raises `start_period` and says so. The live tests' ready limits (install-start row 1's 400 s, row 2's 200 s) apply only to their own runs, where no #453 is injected. They are not the retry bound and are loosened only if the plan finds they must be, with the reason recorded.
- **The stubbed test** uses a fake `iris merge` and pins three cases with their log lines: #453 then success (ready, one `RETRY` line); #453 on every try (`STEP merge FAILED`, not ready, one `RETRY` line per retry); any other failure (no retry, no `RETRY` line). It runs in an existing CI group or list, never `production`, `browser`, `install-fresh` or `install-upgrade`.
- **Scope lock:** `docker/merge.cpf` stays byte-for-byte unchanged, and this story is `docker/after-start.sh`'s only change before the 1.0.0 tag. The 1.0.0 release candidate branch includes this story, so the Planner's hand checks run the `after-start.sh` that ships.
- **Done when:** the three stubbed cases pass, `merge.cpf` is unchanged, `test-install-start.sh` and `test-install-upgrade.sh` pass, and CI is green on every workflow (`ci` and `lane-a`).

## Technical Decisions

- **The start sequence (AD-23):**
  - The image's `CMD` deletes the ready marker before IRIS starts.
  - `iris-main` applies `ISC_CPF_MERGE_FILE` only at the first start or when the file changes. So the after-start script re-runs `iris merge` at every start, before any session or install step, on a fresh temporary copy of the image's merge file, because `iris merge` skips a path whose `*.last_merge` record is unchanged. This keeps the merge idempotent and repairs a mapping removed by hand.
  - After the merge, the script installs IPM and the package (version-gated), runs the registry's steps in their fixed order and writes the ready marker atomically, only after every step succeeds.
- **Reporting:**
  - The script logs `STEP <name> OK|FAILED` per step and a final `RESULT OK <version>` to `/durable/ocutalon-after-start.log`, rewritten every start. A non-fatal condition is a `WARN <step> <text>` line after the step's line, and never changes the result.
  - The script always exits 0 and reports failure only through the missing ready marker. A non-zero exit stops IRIS and the restart policy loops the container.
- **Health check:** a shell script that opens no IRIS session. It passes only when `iris qlist` shows IRIS running and the ready marker equals the image's version. `start_period` is at least 10 minutes (600 s today), and the install script waits 15 minutes. Changing `start_period` keeps that floor.
- **First-start figures for the bound's arithmetic:**
  - The x64 IRIS runner's `FIRST-START` lines run from `docker compose up` to ready. They read 150 s, 177 s and 160 s across Epic 0; 160 s at Epic 0's merge head is the README's figure.
  - The early spike measured about 1 minute on Apple silicon, and about 20 s for the non-Health image.
  - An earlier first start of the same image took 5 to 8 minutes. That is why `start_period` stays at 10 minutes.
  - Check later epics' figures before choosing the slowest one.
- **Platform:** the script runs under the host's bash in hermetic tests (3.2 on macOS), so the retry logic must stay portable shell.
- **Ownership:** `docker/merge.cpf` is Lane A's and the rest of `docker/` (the after-start script included) is Lane B's. Only Epic 0 edits both lanes' files together.
- **CI rules:**
  - Every `docker/tests/test-*.sh` belongs to exactly one of `CHECK_SCRIPTS`, `WEB_SCRIPTS` or an IRIS group in `ci/units.sh`, or `test-ci-config.sh` fails.
  - A full CI run must stay within 35 minutes.
  - Scripts never run `docker compose config` without `--quiet` or `docker inspect` without `--format`.

## Cross-Story Dependencies

- **Builds on Story 0.2's after-start script and its merge step.** The existing hermetic test `docker/tests/test-after-start.sh` (in `CHECK_SCRIPTS`, the hosted checks job) already puts a fake `iris` on `PATH` that answers `merge` from the environment. It is the natural home for the three stubbed cases and sits in an allowed list.
- **The live install tests** `docker/tests/test-install-start.sh` (group `install-fresh`) and `test-install-upgrade.sh` (group `install-upgrade`) must keep passing unchanged within their 400 s and 200 s limits. They get no new #453 cases.
- **Downstream consumers:**
  - The 1.0.0 release candidate and the Planner's timed rehearsal on a clean Linux droplet (Story 38.2) count the `RETRY` lines across 20 starts, a restart check included.
  - The online demo's 1.0.0 update relies on the retry on its container recreate.
  - The README's first-start figure and Story 10.2's wording stay as they are unless `start_period` changes.
- **Reversal:** if the owner reverses the decision behind this story, Story 0.13 is dropped, or its merge is reverted.
