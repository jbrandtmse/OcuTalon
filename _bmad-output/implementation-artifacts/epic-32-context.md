# Epic 32 Context: CI gives a verdict in about ten minutes, even with both lanes pushing

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Before this epic, each push ran about 46 runner-minutes of IRIS work in five groups. The `install` group alone took about 14 minutes, and when both lanes pushed, jobs queued past the 35-minute CI budget. Story 32.1 is done: it split `install` into two jobs and rebalanced the groups, so there are now six IRIS groups. Two stories remain. Story 32.2 makes each group skip its own steps when a push changes nothing it tests. Story 32.3 keeps the six jobs balanced and puts every job's time on record, so that a slow runner host shows up as a capacity item for the owner rather than as a silent wait. With the owner's larger CI capacity, a typical push should get its verdict in about ten minutes. Safety must not weaken: a skip never turns a red into a green, and the demo-path test never skips when product code changed.

## Stories

- Story 32.1: The install group runs as two jobs (done)
- Story 32.2: An IRIS group runs only when something it tests changed
- Story 32.3: Every IRIS job finishes in about ten minutes

## Requirements & Constraints

- **Product targets. Never change them; changing one is the owner's call.**
  - A typical push gets its verdict in about 10 minutes.
  - A full run takes at most 35 minutes of wall-clock time. If a run goes over after the groups are rebalanced, the fix is more CI capacity, which the owner adds. It is not work for this epic.
- **The balance rule (Story 32.3).** On a push that runs every IRIS group:
  - no IRIS job runs more than about 25% over the mean of the six;
  - each job's time, runner and host are recorded;
  - if the slowest job runs over about 10 minutes, its measured times go to the owner as a CI-capacity item. The epic doesn't try to force that ceiling.
- **Rebalancing.** A unit moves between groups whole and is never split. Record every move. Each unit runs in its own fresh throwaway compose project, and every group must still pass alone, in any order (Rule 19).
- **Measure, don't guess.** Label anything not measured `(inference)`.
- **The demo path never skips when product code changed (Story 32.2).**
  - `browser` treats any product source change as its input.
  - A change under `web/` runs every group whose units check the built web bundle. Work out that list from `ci/units.sh` and the live scripts; never assume it.
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
- **Records.** Appending measured facts (timings, commands, recipes) to Rule 21's CI section in `_bmad/custom/skill-rules.md` is allowed. Any other edit under `_bmad/` is escalated.

## Technical Decisions

- **One list.** `ci/units.sh` is the single list of check scripts, shards and groups. `IRIS_GROUPS` and the `iris` matrix in `.github/workflows/ci.yml` must match it, and `docker/tests/test-ci-config.sh` proves that they agree. Its `groups` rule pins only these things: the six names in order, the two install groups' anchor units, no empty group, and `live:demo-path` first in `browser`. So a rebalance of whole units needs no test edit.
- **The six groups, in matrix order:**
  - `install-fresh` (`live:install-start`);
  - `install-upgrade` (`live:install-upgrade live:audit`). Story 32.1 moved `audit` here from `production`;
  - `production` (`live:production live:production-restart`);
  - `browser` (`live:demo-path`, which runs first on its own fresh throwaway, then `live:sign-in live:bundle-folder`);
  - `shards` (`shard:lane-a shard:lane-b`);
  - `image` (`live:storage-roundtrip live:build-inputs live:compose-start`). This is the IRIS checks job.
- **The recipe.** `ci/iris.sh` runs the IRIS units, both on the runner and locally. It always uses throwaway projects through `docker/tests/lib-live.sh` with `ci/compose.ci.yml`, never a dev slot.
  - Set `OCUTALON_RUN_TAG` for the run. Use `ci/iris.sh groups`, `group <name>` or `live <name>`, then `teardown` with the same tag.
  - Under `/epic-cycle`, also set `OCUTALON_LOCK_OWNER`.
  - Keep at most one throwaway IRIS stack per machine at a time.
- **Change detection (Story 32.2).**
  - `ci/changes.sh` decides, for each group, whether the push touched its inputs.
  - Each group declares an input pattern in `ci/units.sh`, in the style of `WEB_INPUT_PATTERN`. The pattern covers the files its units test, the product code they run, the image and compose inputs, `ci/`, and the workflow file.
  - The base is the newest commit in HEAD's history whose push run of the same workflow succeeded, on any branch. On a re-run of a green run, it is HEAD itself.
  - `docker/tests/test-ci-changes.sh` runs in the hosted `checks` job. For each group's pattern, it tests at least one changed path that runs the group and one that skips it. It must include a web-only change (which runs `browser` and every group that checks the bundle, and skips the rest) and a `ci/` change (which runs every group).
- **CI capacity (from 2026-10-21).**
  - IRIS tests run on self-hosted runners. Everything else runs on hosted runners.
  - There are two hosts with 12 runner services in all: `ocutalon-ci-b` (8 vCPU / 16 GB, services 3–8) and `ocutalon-ci-c` (8 vCPU / 16 GB, services 9–14). The original `ocutalon-ci` host and its services 1–2 are retired.
  - Each job runs at most one IRIS stack.
  - The browser units get the fixed web port 52810 plus the runner's number only on runners 1 to 9. Runners 10 to 14 probe for a free port in 52800–52819, so two concurrent browser jobs on `ocutalon-ci-c` can pick the same port (DW-49, which belongs to Story 32.3).
- **Measured so far.**
  - The baseline is run 39594299887 (commit `a500860`). All five jobs ran on `ocutalon-ci-b`, with five stacks at once, and the wall-clock was 20 min 25 s. Group unit times: `install` 1184 s, `production` 902 s, `browser` 805 s, `shards` 567 s, `image` 560 s. Each job also spends about 40 s outside its group.
  - Those same unit times, regrouped into the six groups after the `audit` move, come to 681, 777, 627, 805, 567 and 560 s. The mean is 669.5 s, and `browser`, the longest, is 20% over it. That is a computed figure, not a measured six-job run.
  - Running five stacks on `ocutalon-ci-b` made each unit about 1.21 times as long as running two.
  - `install-start` alone took 847 s on `ocutalon-ci-c`, with no other stack there. Why that host was slower is unknown (inference).
  - The first real six-group run (the push of `e73b33c`) was still pending at this compile.
- **Ownership.**
  - Lane B owns `ci/` (except `ci/mock/scenarios/A/`), `docker/` (except `docker/merge.cpf`) and `.github/workflows/ci.yml`.
  - Lane A owns `.github/workflows/lane-a.yml`, which no criterion here names.

## Cross-Story Dependencies

- Story 32.2 builds on the six groups. Its patterns name `install-fresh` and `install-upgrade`, and `audit`'s inputs now belong to `install-upgrade`.
- Story 32.3 is planned after Story 32.2. After Story 32.2, a full run needs a push that touches every group's inputs; a change under `ci/` does. If Story 32.3 moves a unit, the unit's input paths move with it in the group patterns.
- Story 32.1's records are still to be written. Rule 21's group list and AD-22's "CI as built" both still name five groups, with `audit` under `production`. The lead writes those records after the real run, so until then, trust `ci/units.sh` over both.
- Epic 32 depends on Epic 0. It is first in Lane B's order, and Epic 2 follows it.
- `ci.yml` runs on every push from both lanes, so every change here affects Lane A's CI verdicts too. The IRIS job in `lane-a.yml` draws on the same runner pool.
