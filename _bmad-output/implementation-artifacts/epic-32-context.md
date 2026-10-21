# Epic 32 Context: CI gives a verdict in about ten minutes, even with both lanes pushing

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Before this epic, each push ran about 46 runner-minutes of IRIS work in five groups, `install` alone took about 14 minutes, and with both lanes pushing, jobs queued past the 35-minute CI budget. Stories 32.1 and 32.2 are done. `install` is now two jobs, so there are six IRIS groups, and each group skips its own steps when a push changes nothing it tests. Story 32.3 is the last story. It keeps the six jobs balanced, puts every job's time, runner and host on record, and closes DW-49, so that a slow runner host shows up as a capacity item for the owner instead of a silent wait. With the owner's larger CI capacity, a typical push should get its verdict in about ten minutes. Safety must not weaken: a skip never turns a red into a green, and the demo-path test never skips when product code changed.

## Stories

- Story 32.1: The install group runs as two jobs (done)
- Story 32.2: An IRIS group runs only when something it tests changed (done)
- Story 32.3: Every IRIS job finishes in about ten minutes

## Requirements & Constraints

- **Product targets. Never change them; changing one is the owner's call.**
  - A typical push gets its verdict in about 10 minutes.
  - A full run takes at most 35 minutes of wall-clock time. If a run goes over after the groups are rebalanced, the fix is more CI capacity, which the owner adds. It is not work for this epic.
- **The balance rule (Story 32.3, owner decision U-1, option a).** On a push that runs every IRIS group:
  - no IRIS job runs more than about 25% over the mean of the six;
  - each job's time, runner and host are recorded;
  - if the slowest job runs over about 10 minutes, its measured times go to the owner as a CI-capacity item. The epic doesn't try to force that ceiling.
  - Story 32.1's split note says Story 32.3 keeps the condition of at least as many free runner services as groups.
- **DW-49 (Story 32.3).** Only runners 1 to 9 give the browser units a fixed web port (52810 plus the runner's number). Runners 10 to 14 probe for a free port, so two browser jobs running at once on `ocutalon-ci-c` can pick the same port.
- **Rebalancing.** A unit moves between groups whole and is never split. Record every move. Each unit runs in its own fresh throwaway compose project, and every group must still pass alone, in any order (Rule 19).
- **Measure, don't guess.** Label anything not measured `(inference)`.
- **Skips stay safe.** A pull request, a push to `main`, a force push, an unreadable payload, no base, and any error from the runs API, the base or the diff all run every group. So does a changed path that no group claims and no declaration excludes. A group whose base run wasn't a success runs in full. The demo-path group (`browser`) treats any product source change as its input.
- **Image and runner protection on every workflow edit.**
  - Any `docker push` or registry sign-in fails CI.
  - The AI Hub base image is never pulled, pushed, cached or uploaded as an artifact. It is preloaded on the runner hosts as `ocutalon-iris-base:2026.3.0AI.154.0`.
  - Fork pull requests never run on the IRIS runner.
  - Never run `docker compose config` without `--quiet`, or `docker inspect` without `--format`. Both print the secrets from `env_file`.
- **Records.** Appending measured facts (timings, commands, recipes) to Rule 21's CI section in `_bmad/custom/skill-rules.md` is allowed. Any other edit under `_bmad/` is escalated.

## Technical Decisions

- **One list.** `ci/units.sh` is the single list of check scripts, shards, groups and group input patterns. `IRIS_GROUPS` and the `iris` matrix in `.github/workflows/ci.yml` must match it, and `docker/tests/test-ci-config.sh` proves that they agree.
- **The six groups, in matrix order** (AD-22's "CI as built" and Rule 21 both record them):
  - `install-fresh` (`install-start`);
  - `install-upgrade` (`install-upgrade`, `audit`). Story 32.1 moved `audit` here from `production`;
  - `production` (`production`, `production-restart`);
  - `browser` (`demo-path`, first on its own fresh throwaway, then `sign-in` and `bundle-folder`);
  - `shards` (`lane-a`, `lane-b`);
  - `image` (`storage-roundtrip`, `build-inputs`, `compose-start`). This is the IRIS checks job.
- **The recipe.** `ci/iris.sh` runs the IRIS units on the runner and locally, always in throwaway projects through `docker/tests/lib-live.sh` with `ci/compose.ci.yml`, never a dev slot. Set `OCUTALON_RUN_TAG`, run `groups`, `group <name>` or `live <name>`, then `teardown` with the same tag. Under `/epic-cycle`, also set `OCUTALON_LOCK_OWNER`. Keep at most one throwaway IRIS stack per machine at a time.
- **How skips work (Story 32.2, as built).**
  - Each `iris` job runs `ci/changes.sh ci.yml --group <group>`. Only when it returns `run=false` does the job skip `Build the web bundle` and `Run the group`. It then logs `iris <group> skipped: no input changed since <base sha>` and concludes `success`.
  - A group's inputs are the shared inputs (`src/`, the image, compose and throwaway files, `eval/`, `ci/` and `ci.yml`), its own live scripts, and the web bundle's inputs. Only a group whose units are all measured not to check the bundle leaves out the web inputs, and today that is only `production`.
  - The base is the newest commit in HEAD's history whose `ci` push run succeeded, on any branch.
  - So a web-only push runs every group except `production`, and a push touching only declared non-inputs (`docs/`, `release/`, `README.md`) runs none.
- **CI capacity (from 2026-10-21).** IRIS tests run on self-hosted runners, and everything else on hosted runners. There are 12 runner services on two hosts: `ocutalon-ci-b` (8 vCPU / 16 GB, services 3–8) and `ocutalon-ci-c` (8 vCPU / 16 GB, services 9–14). The original `ocutalon-ci` host and its services 1–2 are retired. Each job runs at most one IRIS stack.
- **Measured.**
  - **Before the split** (run 39594299887, five groups, all five jobs on `ocutalon-ci-b`): wall-clock 20 min 25 s. Regrouped into the six groups, those unit times come to 681, 777, 627, 805, 567 and 560 s. The longest is 1.20 times the mean, and Story 32.1's search found that no whole-unit move lowers the longest.
  - **The first six-group run** (run 39633794167, commit `e73b33c`, no other run on the runners, every job waited 3 s): wall-clock 19 min 21 s. Per job, with its runner:
    - `install-upgrade`: 19 min 18 s (ci-13);
    - `install-fresh`: 16 min 59 s (ci-14);
    - `production`: 15 min 3 s (ci-11);
    - `image`: 13 min 50 s (ci-10);
    - `browser`: 12 min 52 s (ci-5);
    - `shards`: 8 min 59 s (ci-4).
  - The mean of the six is 870 s, and `install-upgrade` ran 1.33 times it. So that run misses the balance rule, and its slowest job is over 10 minutes.
  - The spread comes from host placement. Four of the six IRIS jobs ran on `ocutalon-ci-c`, where a stack ran about 1.4 to 1.9 times as long as on `ocutalon-ci-b` (that ratio is from two runs, so it is `(inference)`). By ruling, Story 32.1 moved no unit.
- **Ownership.** Lane B owns `ci/` (except `ci/mock/scenarios/A/`), `docker/` (except `docker/merge.cpf`) and `.github/workflows/ci.yml`. Lane A owns `.github/workflows/lane-a.yml`, whose `standalone-bridge` job also runs on the IRIS runners.

## Cross-Story Dependencies

- Story 32.3 builds on both done stories. After Story 32.2, a full run needs a push that touches every group's inputs. A change under `ci/` or `src/` does that.
- If Story 32.3 moves a unit, the unit's live script moves with it in the group input patterns. The group's web-input exemption must then still match the units it holds.
- Epic 32 depends on Epic 0. It is first in Lane B's order, and Epic 2 follows it.
- `ci.yml` runs on every push from both lanes, so every change here affects Lane A's CI verdicts too, and Lane A's IRIS job draws on the same runner pool.
