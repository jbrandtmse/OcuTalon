# Epic 32 Context: CI gives a verdict in about ten minutes, even with both lanes pushing

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Each push runs about 46 runner-minutes of IRIS work in five groups. The `install` group alone takes about 14 minutes, and when both lanes push, jobs queue past the 35-minute CI budget. This epic splits that longest job in two, measures every IRIS job, and makes each IRIS group skip its own steps when a push changes nothing it tests. With the owner's larger CI capacity, a typical push should get its verdict in about ten minutes. Safety must not weaken: a skip never turns a red into a green, and the demo-path test never skips when product code changed. The ceiling of about 10 minutes per job is a separate story, waiting for the owner, because measurement showed that moving whole units cannot meet it on the current hosts.

## Stories

- Story 32.1: The install group runs as two jobs
- Story 32.2: An IRIS group runs only when something it tests changed
- Story 32.3: Every IRIS job finishes in about ten minutes (parked, waiting for the owner)

## Requirements & Constraints

- **Product targets (never change them).**
  - A typical push gets its verdict in about 10 minutes.
  - A full run stays within 35 minutes of wall-clock time.
  - With at least as many free runner services as groups, no IRIS job runs longer than about 10 minutes. This ceiling belongs to Story 32.3, not Story 32.1.
  - If a run still exceeds 35 minutes after rebalancing, the fix is more CI capacity. That is an owner action, not work for this epic.
- **Measure and record.** For a push that runs every group, record each IRIS job's time, runner and host, and the run's wall-clock time. Compare them with the last full run before the split. Label anything not measured `(inference)`.
- **Rebalancing.** Rebalance only when one group still runs much longer than the rest. A unit moves between groups whole and is never split. Record every move.
- **Hermetic groups.** `install-fresh` and `install-upgrade` each start from their own fresh compose project. Neither depends on anything the other leaves behind. Each passes alone, in either order.
- **The demo path never skips when product code changed.**
  - `browser` treats any product source change as its input.
  - A change under `web/` runs every group whose units check the built web bundle. Work out that list from `ci/units.sh` and the live scripts. Never assume it.
- **A skip never gives a false green.**
  - These cases run every group in full: a pull request, a missing or unknown base, a force push, and any error reading the base or the changes.
  - A group whose base run wasn't a success runs in full.
  - A push to `main` always runs everything.
- **How a skip looks.** The group's job still starts and skips its own steps, never the workflow's. It concludes `success` and logs `no input changed since <sha>`. The workflow always runs, so the kit's CI gate sees every workflow conclude.
- **Image and runner protection on every workflow edit.**
  - Any `docker push` or registry sign-in fails CI.
  - The AI Hub base image is never pulled, pushed, cached or uploaded as an artifact. It is preloaded on the runner hosts as `ocutalon-iris-base:2026.3.0AI.154.0`.
  - Fork pull requests never run on the IRIS runner.
  - Never run `docker compose config` without `--quiet`, or `docker inspect` without `--format`. Both print the secrets from `env_file`.
- **Record edits.** Story 32.1 updates Rule 21's CI section in `_bmad/custom/skill-rules.md` and the spine's AD-22 "CI as built" paragraph with exactly what its criteria name: the six groups, the measured time of each group, and the CI capacity, which replaces "two services share one host" with measured facts only. No other edit under `_bmad/` is in scope.

## Technical Decisions

- **One list.** `ci/units.sh` is the single list of check scripts, shards and groups. `IRIS_GROUPS` and the `iris` matrix in `.github/workflows/ci.yml` must match it, and `docker/tests/test-ci-config.sh` proves that they agree.
- **The six groups after Story 32.1:**
  - `install-fresh` (`live:install-start`);
  - `install-upgrade` (`live:install-upgrade`);
  - `production` (production, production-restart, audit);
  - `browser` (`demo-path` first, on its own fresh throwaway; then sign-in and bundle-folder);
  - `shards` (lane-a, lane-b);
  - `image` (storage-roundtrip, build-inputs, compose-start). This is the IRIS checks job.
- **The recipe.** `ci/iris.sh` runs the IRIS units, both on the runner and locally. It always runs in throwaway projects through `docker/tests/lib-live.sh` with `ci/compose.ci.yml`, never on a dev slot.
  - Set `OCUTALON_RUN_TAG` for the run. Use `ci/iris.sh groups`, `group <name>` or `live <name>`, then `teardown` with the same tag.
  - Under `/epic-cycle`, also set `OCUTALON_LOCK_OWNER`.
  - Keep at most one throwaway IRIS stack per machine at a time.
- **Change detection.**
  - `ci/changes.sh` decides, for each group, whether the push touched its inputs.
  - In `ci/units.sh`, each group declares an input pattern in the style of `WEB_INPUT_PATTERN`. The pattern covers the files its units test, the product code they run, the image and compose inputs, `ci/`, and the workflow file.
  - The base is the newest commit in HEAD's history whose push run of the same workflow succeeded, on any branch. On a re-run of a green run, the base is HEAD itself.
  - `docker/tests/test-ci-changes.sh` runs in the hosted `checks` job. For each group's pattern, it has at least one changed path that runs the group and one that skips it. Two cases are required:
    - a web-only change runs `browser` and every group that checks the bundle, and skips the rest;
    - a `ci/` change runs every group.
- **CI capacity (from 2026-10-21).**
  - IRIS tests run on self-hosted runners. Everything that doesn't need IRIS runs on hosted runners.
  - There are two hosts, with 12 runner services in all: `ocutalon-ci-b` (8 vCPU / 16 GB, services 3–8) and `ocutalon-ci-c` (8 vCPU / 16 GB, services 9–14). The original `ocutalon-ci` host and its services 1–2 are retired.
  - Each job runs at most one IRIS stack. Browser units use web port 52810 plus the runner's number.
- **Baseline timings.** These were measured on the retired 4 vCPU host, with two jobs at once. The last recorded full run took 28 min 7 s of wall-clock time.
  - Per unit: `install-start` took about 450–470 s and `install-upgrade` about 350–390 s.
  - Per job: `install` about 14 min, `production` 10.5–13 min, `browser` about 9.5 min, `image` 6–8 min and `shards` about 6 min.
  - A ready stack took 150–177 s.
- **New-host measurement.** Run 39594299887 had five IRIS stacks on `ocutalon-ci-b`, and `live:install-start` alone took 681 s on it. So the job that holds that unit takes about 12 minutes, whatever the grouping.
- **Ownership.**
  - Lane B owns `ci/` (except `ci/mock/scenarios/A/`), `docker/` (except `docker/merge.cpf`) and `.github/workflows/ci.yml`.
  - Lane A owns `.github/workflows/lane-a.yml`, and no criterion in this epic names it.

## Cross-Story Dependencies

- Story 32.2 builds on Story 32.1's six groups. Its patterns and test cases name `install-fresh` and `install-upgrade`.
- Story 32.3 comes after Story 32.1's split and rebalance. It stays parked until the owner decides how its ceiling is met. Do not build it, and do not fold its ceiling back into Story 32.1.
- When Story 32.1 merges, the spine's AD-22 "CI as built" paragraph and Rule 21's group list must both name the six groups. Both still name five.
- Epic 32 depends on Epic 0. It is first in Lane B's order, and Epic 2 follows it.
- `ci.yml` runs on every push from both lanes while Lane A builds Epic 1, so every change here also affects Lane A's CI verdicts. The IRIS job in `lane-a.yml` draws on the same runner pool.
