# Epic 32 Context: CI gives a verdict in about ten minutes, even with both lanes pushing

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Every push from either lane runs about 46 runner-minutes of IRIS work in five groups. The `install` group alone takes about 14 minutes, and when both lanes push, jobs queue past the 35-minute CI budget. This epic splits that longest job so that no IRIS job runs much longer than the others, and makes each IRIS group skip its steps when a push changes nothing that group tests. With the owner's larger CI capacity, a typical push should get its verdict in about ten minutes, and safety must not weaken: a skip never turns a red into a green, and the demo-path test never skips when product code changed.

## Stories

- Story 32.1: The install group runs as two jobs
- Story 32.2: An IRIS group runs only when something it tests changed

## Requirements & Constraints

- **Speed targets (product numbers; do not change them).** A typical push gets its verdict in about 10 minutes. With at least as many free runner services as groups, no IRIS job runs longer than about 10 minutes. A full run stays within 35 minutes of wall-clock time. If a run still exceeds 35 minutes after the groups are rebalanced, the fix is more CI capacity, which only the owner can add. It is not a change to make in this epic.
- **Rebalancing.** Units move between groups whole and are never split. Record every move, along with the measured wall-clock time compared with the last full run before the split.
- **The demo path never breaks.** The `browser` group, which holds the demo path, treats any product source change as its input. A change under `web/` runs every group whose units check the built web bundle. Work out which groups those are from `ci/units.sh` and the live scripts. Do not assume the list.
- **A skip never gives a false green.**
  - These cases run every group in full: a pull request, a missing or unknown base, a force push, or any error reading the base or the changes.
  - A push to `main` always runs everything.
  - A group whose base run was not a success runs in full.
- **How a skip looks.** A skipped group's job still starts. It skips its own steps (never the workflow), concludes `success`, and logs `no input changed since <sha>`. The workflow itself always runs, so the kit's CI gate sees every workflow conclude.
- **Hermetic groups.** Each new group starts from its own fresh compose project and needs nothing left behind by the other. Each passes alone, run in either order.
- **Records hold measured facts only.** Rule 21's CI section records the new group list, the measured time for each group and the CI capacity. That capacity is two hosts: `ocutalon-ci-b` (8 vCPU / 16 GB, services 3–8) and `ocutalon-ci-c` (8 vCPU / 16 GB, services 9–14), 12 runner services in all. The original `ocutalon-ci` host was retired on 2026-10-21. Anything not measured is labelled `(inference)`. Rule 21 lives under `_bmad/`. Appending measured facts there is in scope. Any other edit is limited to exactly what the acceptance criteria name.
- **Image and runner protection still apply to every workflow edit:**
  - Any `docker push` or registry sign-in fails CI.
  - The AI Hub base image is never pulled, pushed, cached or uploaded as an artifact.
  - Fork pull requests never run on the IRIS runner.
  - Never run `docker compose config` without `--quiet`, or `docker inspect` without `--format`, because both print secrets from `env_file`.

## Technical Decisions

- **One list.** `ci/units.sh` is the single list of check scripts, shards and groups. `IRIS_GROUPS` and the `iris` matrix in `.github/workflows/ci.yml` must match it. `docker/tests/test-ci-config.sh` proves they agree and must keep passing.
- **Groups after Story 32.1 (six):**
  - `install-fresh` (`live:install-start`)
  - `install-upgrade` (`live:install-upgrade`)
  - `production` (production, production-restart, audit)
  - `browser` (demo-path first, on its own fresh throwaway; then sign-in, bundle-folder)
  - `shards` (lane-a, lane-b)
  - `image` (storage-roundtrip, build-inputs, compose-start; this is the IRIS checks job)
- **The recipe.** `ci/iris.sh` is the one recipe for IRIS units, both on the runner and locally. It always runs in throwaway projects through `docker/tests/lib-live.sh` with `ci/compose.ci.yml`, never on a dev slot.
  - Set `OCUTALON_RUN_TAG` for the run.
  - Commands: `ci/iris.sh groups`, `ci/iris.sh group <name>` and `ci/iris.sh live <name>`, then `ci/iris.sh teardown` with the same tag.
  - Under `/epic-cycle`, also set `OCUTALON_LOCK_OWNER`.
  - Keep at most one throwaway IRIS stack per machine at a time.
- **Change detection.** `ci/changes.sh` decides for each group whether the push touched its inputs.
  - Each group declares an input pattern in the same style as `WEB_INPUT_PATTERN`. The pattern covers the files its units test, the product code they run, the image and compose inputs, `ci/`, and the workflow file.
  - The base is the newest commit in HEAD's history whose push run of the same workflow succeeded, on any branch. On a re-run of a green run, the base is HEAD itself.
  - `docker/tests/test-ci-changes.sh` runs in the hosted `checks` job. For each group's pattern it covers at least one path that runs the group and one that skips it. Among those cases: a web-only change runs `browser` and every group that checks the bundle, and skips the rest; a `ci/` change runs every group.
- **Ownership.** Lane B owns `ci/` (except `ci/mock/scenarios/A/`), `docker/` (except `docker/merge.cpf`) and `.github/workflows/ci.yml`. `.github/workflows/lane-a.yml` belongs to Lane A, and this epic's acceptance criteria do not name it.
- **Runner facts.** Each job runs at most one IRIS stack. The base image `ocutalon-iris-base:2026.3.0AI.154.0` is preloaded on the runner host. Browser units use web port 52810 plus the runner's number.
- **Baseline timings.** These were measured on the retired 4 vCPU host, with two jobs running at once.
  - Per unit: `install-start` took about 450–470 s and `install-upgrade` about 350–390 s.
  - Per job: `install` about 14 min, `production` 10.5–13 min, `browser` about 9.5 min, `image` 6–8 min and `shards` about 6 min.
  - A ready stack took 150–177 s.
  - The last run recorded in Rule 21 took 28 min 7 s of wall-clock time.
  - `production` already ran over 10 minutes on that host, so it is the likely group to rebalance next `(inference)`. Timings on the 8 vCPU hosts are unmeasured, so measure them before deciding.

## Cross-Story Dependencies

- Story 32.2 builds on Story 32.1's six groups. Its patterns and test cases name `install-fresh` and `install-upgrade`.
- When Story 32.1 merges, two documents must both name the six groups: the spine's AD-22 "CI as built" paragraph and Rule 21's group list.
- Epic 32 depends on Epic 0. Lane B's Epic 2 waits for Epic 32.
- `ci.yml` runs on every push from both lanes, and Lane A is building at the same time (Epic 1). Every change here affects Lane A's CI verdicts too. Lane A's `lane-a.yml` IRIS jobs also draw on the same runner pool.
