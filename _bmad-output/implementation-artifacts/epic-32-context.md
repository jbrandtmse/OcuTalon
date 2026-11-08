# Epic 32 Context: CI gives a verdict in about ten minutes, even with both lanes pushing

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 32 keeps CI's verdict fast and inside REL-4's 35-minute budget by splitting long jobs, skipping groups a push can't affect, and keeping the groups balanced. Stories 32.1 to 32.4 are done. The epic is re-opened as a fix-forward for Story 32.5. Story 4.11 added 96 more-to-try tests to the chromium Playwright project, and `live:sign-in` grew back over the 1,000 s unit line: 1,170 s on OCT-epic11 623b9cb0 (ci run 42392984136) and 1,034 s on feature 5b47f052 (ci run 42393186349), close to its 1,200 s deadline. Story 32.5 splits it again, the way the 2026-11-05 split made `live:sign-in-2`. It raises no deadline and drops no test.

## Stories

- Story 32.1: The install group runs as two jobs (done)
- Story 32.2: An IRIS group runs only when something it tests changed (done)
- Story 32.3: Every IRIS job finishes in about ten minutes (done)
- Story 32.4: The developer loop reuses one warm throwaway per lane (done)
- Story 32.5: live:sign-in splits again after 4.11's tests

## Requirements & Constraints

- **Limits that hold.**
  - A unit stays under the 1,000 s line and well clear of its 1,200 s deadline.
  - Every group stays under REL-4's 35-minute budget. The Planner's packing rule is each group at or under about 33 minutes, against the 40-minute job timeout.
  - No deadline or timeout is raised, and no test is skipped, removed or weakened.
- **Exact test coverage.**
  - The two sign-in units together list exactly today's chromium tests. Check this with `npx playwright test --list` per project, diffed against today's one-unit list.
  - No test is lost or duplicated, and every other project's list stays the same.
- **Placement.** The new unit goes into a group whose clean time plus the unit stays under 35 minutes, based on CI's own per-unit seconds, not guesses. Label anything not measured `(inference)`.
- **Pins.** Everything that names the sign-in units must cover the new unit the way it covers `live:sign-in-2`:
  - the unit list and the group map in `ci/units.sh`;
  - the changed-inputs rules (`ci/changes.sh`, `docker/tests/test-ci-changes.sh`);
  - the e2e-part and playwright-projects tests;
  - `docker/tests/test-ci-config.sh`, which proves the workflow matrix matches `ci/units.sh`.
- **Done means.** `docker/tests/test-boundaries.sh` passes before the push, and full CI is green on every workflow.
- **One commit.** The fix is its own commit on its own branch, so the Planner can cherry-pick it onto the release branch (1.0.3 rc1 is cut). Nothing else changes.
- **Secrets and images.** Never run `docker compose config` without `--quiet`, or `docker inspect` without `--format`. The base image `ocutalon-iris-base:2026.3.0AI.154.0` is never pulled or pushed.

## Technical Decisions

- **How the 2026-11-05 split works.** The sign-in spec files are split into Playwright projects, and each unit runs on its own fresh stack with the full setup of `docker/tests/test-sign-in.sh`.
  - `live:sign-in` keeps the project `chromium` in the `browser` group.
  - `live:sign-in-2` (`docker/tests/test-sign-in-2.sh`) runs the project `sign-in-2` in `shards-4`. That project holds the folders listed in `SIGN_IN_2_DIRS` in `web/playwright.config.ts`.
  - Each unit prints one `SPEC` line per spec file with its seconds, so files can be moved between projects using CI's own numbers.
  - About 260 s of each unit is its own build, start and setup. The rest is the browser run.
  - The new split moves whole spec files or folders and follows the same pattern: a new project, a new `test-sign-in-N.sh`, a new unit and a group entry.
- **CI as built.** There are ten IRIS groups, each its own job of the `iris` matrix: `install-fresh`, `install-upgrade`, `production`, `browser`, `shards`, `shards-2`, `image`, `shards-3`, `shards-4` and `shards-5`.
  - `ci/units.sh` is the one list of units and groups, and records each split's measured basis in comments.
  - A group skips its own steps only when nothing it checks changed since the last green push run. Pull requests, a missing base and errors run everything.
  - Every live script runs on the Health image in CI.
- **One recipe.** `ci/iris.sh` runs every IRIS unit, on the runner and on the developer machine, always on throwaway compose projects through `docker/tests/lib-live.sh` and `ci/compose.ci.yml`.
  - Set `OCUTALON_RUN_TAG` (at least 3 lower-case letters, digits and hyphens, no `slot`) and run one piece per call (`build`, `shard`, `class`, `live <name>`).
  - Finish with `teardown` and the same tag.
  - `live` units refuse `OCUTALON_WARM`, so the sign-in units always run on fresh stacks. The warm stack only helps repeated `class` and `shard` runs.
- **Per-lane variables.** This run is runner A's side task on lane A, slot `ocutalon-slot-a`. Every call sets:
  - `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-a`;
  - `OCUTALON_TEST_WEB_PORT=52801`;
  - `OCUTALON_LOCK_OWNER='epic=32 stage=<stage>'`, and logs the `LOCK` lines.

  Name the target on every call, never run destructive work on a slot, and tear down only what this session started.
- **Ownership.** The files are Lane B's: `ci/`, `docker/` (except `docker/merge.cpf`), `.github/workflows/ci.yml` and `web/` (except the Telegram card and the `telegram-*.spec.ts` files).
- **Where records go.** Measured facts may be appended to Rule 21's sections of `_bmad/custom/skill-rules.md`. Escalate any other edit under `_bmad/`.

## Cross-Story Dependencies

- Story 32.5 builds on the 2026-11-05 `live:sign-in-2` split and on Story 4.11's tests in the chromium project. Its unit times come from the two CI runs above.
- Other lanes' merges move unit and group seconds (for example, Story 19.8's `shards-5` split on 2026-11-07). Pick the group from the newest measured runs, and keep the comments in `ci/units.sh` consistent.
- The `browser` group holds the demo path (REL-2). `live:demo-path` stays first in `browser` on its own fresh throwaway.
