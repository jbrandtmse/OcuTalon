# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton: one image build and `docker compose up` give OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start, with a branded page behind sign-in, the Orders demo production in OCUORDERS, every cross-lane contract and production stub, and CI with the model mock, so both build lanes can work in parallel. Stories 0.1 to 0.18 are done. Epic 0 is re-opened again for one CI-only story, 0.20. On Story 0.15's head, IRIS CI groups were cancelled at the 40-minute job limit with no failing test, and other groups ran 38 to 39 minutes. Story 0.20 repacks the IRIS groups so that every group finishes well under the 35-minute budget and every head can go green without reruns.

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
- Story 0.15: The Dockerfile sits at the repository root (done; CI not yet green, merges together with 0.20)
- Story 0.16: The Embedded Python callback crash (S11) is re-verified with a minimal reproduction (done)
- Story 0.17: The README's evaluation table shows release 1.0.4's numbers (done)
- Story 0.18: The README shows judges where to look (done)
- Story 0.20: Rebalance the IRIS CI groups so every group finishes well under the 35-minute budget (backlog)

## Requirements & Constraints

**The CI budget.** A full CI run takes at most 35 minutes of wall-clock time. Live-IRIS tests run on the dedicated self-hosted runner. Everything else runs on hosted runners.

**The standing CI split rules:**
- A unit takes about 1,000 s at most. A unit too long for that is split into pieces, never given a longer deadline.
- Every group's planned sum, including the job's own setup time, stays well under 35 minutes.
- Add a new IRIS group only when packing the existing groups cannot meet the budget.
- No group gets a longer deadline, and no test is dropped.

**Story 0.20:**
- Pack the groups from measured unit times, taken from recent CI runs, not from estimates. The spec records each group's planned sum.
- When this story is done, two clean CI runs (the second may be the merge head's) show every IRIS group under 35 minutes, and each group's time from both runs is reported. This resolves DW-1025.

**Test pins:**
- `docker/tests/test-ci-config.sh` and `test-ci-changes.sh` pin the group layout. Every pin of the old layout moves to the new one, and no pin is deleted or weakened.
- Both scripts must pass together with `docker/tests/test-boundaries.sh`.
- Every `docker/tests/test-*.sh` belongs to exactly one of `CHECK_SCRIPTS`, `WEB_SCRIPTS` or an IRIS group in `ci/units.sh`.

**Consistency:**
- `IRIS_GROUPS`, the `iris` matrix in `.github/workflows/ci.yml` and `ci/iris.sh groups` must agree.
- Every new job reports as `iris (<group>)`.
- A unit that moves with a pin attached (for example, the overview-doc check's `NO_WEB_BUNDLE_UNITS` membership) has the unit and its pin change in the same commit.

**Approvals:**
- The `.github/workflows/ci.yml` matrix hunk goes to the Contest Planner (`RELEASE TOOL:`) before it merges.
- Once the story merges, the Planner adds every new job name to main's required checks.

## Technical Decisions

- **How CI runs IRIS tests:** `ci/iris.sh` is the one recipe for IRIS units, on the runner and on a developer machine, always in throwaway compose projects layered with `ci/compose.ci.yml`. `ci/units.sh` maps groups to units.
- **Shard pieces:** `%UnitTest` classes run in whole-area shards aligned with the lanes (`lane-a`, `lane-b`). A shard too long for one job runs as `shard:<name>@<piece>`. The `rest` piece is computed from the pieces the groups name, so every area stays in exactly one piece and every test class runs once. Split `shard:lane-a@rest` with this existing mechanism, not a new one.
- **Image safety:** the AI Hub image, and any image built on it, is never pushed to a registry or kept in CI caches or artifacts. Never run `docker compose config` without `--quiet`, or `docker inspect` without `--format`, because both print `env_file` values.
- **Portability:** scripts also run under macOS's bash 3.2 in hermetic tests, so shell changes must be portable.
- **Lane ownership:** `docker/` belongs to Lane B, except Lane A's `merge.cpf`. `release/` is Lane A's. Only Epic 0 may edit files from both lanes in one story.

## Cross-Story Dependencies

- **Built on 0.15:** 0.20 is built on Story 0.15 (Dockerfile at the repository root) and merges with it on one head. 0.15's merge is held until after the 1.0.5 cut, and that combined head's CI is the gate.
- **Contended files:** other epics change `ci/units.sh` and the CI pin tests too (Epic 41 changed `ci/units.sh` recently). Integrate forward and expect conflicts in those files. Base the repacking on the merged unit list, so units added by other epics are packed too.
- **Known flakes:** inherited flakes such as DW-973, DW-774, DW-689 and DW-1026 can turn a run red without a 0.20 cause. Classify them; do not repack around them.
