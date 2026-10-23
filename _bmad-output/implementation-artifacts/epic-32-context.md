# Epic 32 Context: CI gives a verdict in about ten minutes, even with both lanes pushing

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Stories 32.1 to 32.3 are done. They split `install` into two jobs, let each IRIS group skip its steps when nothing it tests changed, and made the six jobs balanced, with every job's time on record. The epic is re-opened for Story 32.4, which targets the wait on the developer machine. On Stories 1.7 and 2.7, about half of each 5.7-hour story went to throwaway IRIS runs, because every `ci/iris.sh class` or `shard` call starts a fresh IRIS. There were 66 `class` calls averaging 1.7 minutes, more than half of each spent starting IRIS, and 261 `ci/iris.sh` calls in 10 hours. Story 32.4 lets a stage's repeated class and shard runs reuse one warm throwaway per lane. The fresh checks stay exactly as strict.

## Stories

- Story 32.1: The install group runs as two jobs (done)
- Story 32.2: An IRIS group runs only when something it tests changed (done)
- Story 32.3: Every IRIS job finishes in about ten minutes (done)
- Story 32.4: The developer loop reuses one warm throwaway per lane

## Requirements & Constraints

- **Developer loop only.** Story 32.4 changes no product code and no CI behaviour. CI never sets `OCUTALON_WARM`, and the six groups, skips and workflow stay as they are.
- **Fresh checks stay fresh.** None of these use a warm stack: `live` units (they refuse `OCUTALON_WARM`), destructive tests, the fresh-environment check (Rule 19: `shard lane-a` and `shard lane-b` forward, then both with `--reverse`, one per call) and CI. Hermeticity is still proven on a fresh stack before every commit.
- **No stale code.** Before each warm `class` or `shard` run:
  - load and compile every class changed in the tree since the stack's last load;
  - delete every class removed or renamed since then;
  - print `WARM reloaded <n>, deleted <m>`.

  A compile error fails the run, as it would on a fresh stack.
- **Lifecycle.**
  - There is one warm stack per lane. It holds its own lock, `warm-iris.lock` in the lane's lock folder, until `warm down`; fresh stacks keep `throwaway-iris.lock`, so a lane holds at most one warm and one fresh stack at a time (AC 2 as amended 2026-10-23, Rule 5 tier 1, pre-ruled with the Contest Planner).
  - When a stage ends, fails or is killed, `warm down` and the cleanup trap remove the stack and release the lock.
  - `ci/iris.sh teardown` with the stack's tag removes an orphaned warm stack, like any other throwaway.
  - So a stage's own fresh runs (`live` units, destructive tests, the fresh check) take `throwaway-iris.lock` as before and never wait on the lane's warm stack.
  - Memory: Task 0 measures it first. The estimate is about 2.4 GB per stack, three lanes x (warm + fresh) plus about 17 GB of other containers, about 32 of 62.7 GiB (inference until measured).
- **Measure, don't guess.** Label anything not measured `(inference)`.
  - **Task 0** records, as a Rule 21 measured fact:
    - the Docker VM's memory and CPUs;
    - the memory of a slot, of a fresh throwaway, and of a warm throwaway after a shard run;
    - the headroom for three lanes that each hold one warm stack, beside the three slots and the other long-running containers.
  - **Known figures.** On 2026-10-23 the owner raised the Docker VM to 64 GB (62.7 GiB usable, 16 CPUs). Before that, it had 31 GB with 17 GB in use, and one throwaway took about 2.4 GB.
  - **Warm against fresh.** The story runs the same classes warm and fresh in one stage and records both times.
- **Where records go.** You may append measured facts and recipes to Rule 21's sections of `_bmad/custom/skill-rules.md`. That includes the new "when stages use warm mode" recipe, and it is the run's own write. Escalate any other edit under `_bmad/`.
- **Secrets and images.** Never run `docker compose config` without `--quiet`, or `docker inspect` without `--format`, because both print `env_file` secrets. The base image `ocutalon-iris-base:2026.3.0AI.154.0` must already be on the machine and is never pulled or pushed.

## Technical Decisions

- **One recipe.** `ci/iris.sh` runs every IRIS unit, on the CI runner and on the developer machine.
  - It always uses throwaway compose projects through `docker/tests/lib-live.sh` with `ci/compose.ci.yml`, never a slot or any other instance.
  - Set `OCUTALON_RUN_TAG` (lower-case letters, digits and hyphens, at least 3 characters, no `slot`), then run one piece per call: `build`, `shard <lane-a|lane-b>`, `class <Class>` or `live <name>`.
  - Finish with `teardown` and the same tag. It removes only that tag's projects (`ocutalon-<label>-<tag>-<epoch>-<pid>`), containers, volumes, networks and images, so pick a tag that does not end another run's tag.
  - Build the warm mode on `lib-live.sh`'s existing functions, either in `ci/iris.sh` (`warm up` and `warm down`) or in a new `ci/warm.sh`.
- **Per-lane variables (from 2026-10-23).** Under `/epic-cycle`, every call sets:
  - `OCUTALON_LOCK_DIR` to `<main checkout>/.worktrees/.coordination/locks/lane-a`, `lane-b` or `lane-c`. `lib-live.sh` holds `throwaway-iris.lock` there while a stack runs, so a lane waits only on its own stacks.
  - `OCUTALON_TEST_WEB_PORT`: 52801 for lane A, 52802 for lane B and 52803 for lane C.
  - `OCUTALON_LOCK_OWNER='epic=<N> stage=<stage>'`, and logs the `LOCK` lines.

  CI and sequential runs have no lock folder and take no lock. Each lane still runs at most one throwaway at a time.
- **How a class runs.**
  - It runs through `%UnitTest.Manager` with `/noload/nodelete/norecursive` from the installed package, after `^UnitTestRoot` is set to an existing folder in the stack.
  - Each class prints one `CLASS <name> passed|failed <s>s` line, with any `FAIL` or `SKIP` under it.
  - The call exits 1 when a class fails, runs no test or is not compiled.
  - `lane-a` holds 9 classes (Agent, Bridge, Install) and `lane-b` holds 24.
- **Baseline on the developer machine (ARM).** A ready stack takes 52 to 57 s. Almost every class takes under 0.4 s, the slowest about 2 s. A shard call takes 61 to 64 s, almost all of it the stack start.
- **Targets.** Lane C's slot is `ocutalon-slot-c` (1992 / 52792). A warm stack is a throwaway, never a slot, and destructive work never runs on a slot. Name the target on every call. Tear down only what your own session started (Rule 13).
- **CI as built (unchanged by Story 32.4).** There are six IRIS groups, and `ci/units.sh` is the one list of units and groups. `docker/tests/test-ci-config.sh` proves that `ci.yml` agrees with it.
- **Ownership.** Story 32.4 is built by runner C, which owns no packages, in Lane B's files. Lane B owns `ci/` (except `ci/mock/scenarios/A/`), `docker/` (except `docker/merge.cpf`) and `.github/workflows/ci.yml`.

## Cross-Story Dependencies

- Story 32.4 builds on the recipe from Stories 32.1 to 32.3 and on the per-lane lock folders and ports. It does not change their CI behaviour.
- `docker/tests/lib-live.sh` is on Epic 2's contended paths until Epic 2 merges. The new mode builds on its existing functions, and any change to `lib-live.sh` itself contends with Epic 2.
- All three lanes' stages will follow the appended Rule 21 recipe. The warm mode must work with each lane's lock folder and web port.
- Epic 32 depends on Epic 0. Runner C builds Story 32.4 while it waits for Epic 1.
