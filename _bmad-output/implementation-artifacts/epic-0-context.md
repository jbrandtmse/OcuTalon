# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton: one image build and `docker compose up` give OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start, with a branded page behind sign-in, the Orders demo production in OCUORDERS, every cross-lane contract and production stub, and CI with the model mock. Stories 0.1 to 0.14 and 0.16 are done and merged. Epic 0 is re-opened after the v1.0.4 release, targeting 1.0.5 or later, for two small stories. Story 0.17 updates the README's Measured table to release 1.0.4's real-model evaluation and the demo's latest usage log, using text the Contest Planner has already approved. Story 0.15 moves the Dockerfile to the repository root so the Open Exchange listing reads Docker True. Neither story changes how the image builds or installs.

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
- Story 0.15: The Dockerfile sits at the repository root (backlog)
- Story 0.16: The Embedded Python callback crash (S11) is re-verified with a minimal reproduction (done)
- Story 0.17: The README's evaluation table shows release 1.0.4's numbers (backlog)

## Requirements & Constraints

**Story 0.17 (README numbers):**
- The text is already approved and goes in exactly as written: the intro line, the five changed rows, and one new paragraph with the cost-article link placed right after the table and before "Two things to look at in the demo:". Do not reword, re-punctuate or "improve" it. The other rows stay as they are.
- README.md is the only product file that changes. A pin in `docker/tests/test-readme.sh` that holds an old number or the old intro line moves to the new text; no pin is dropped.
- Done when none of the old figures ("9 of 10 (target", "19 of 22", "0.0005 to", "9 to 10 cents") remain in README.md, `test-boundaries.sh` and `test-readme.sh` pass, and CI is green.
- Pipeline: one `bmad-build-auto` stage plans and implements, then the runner's own diff review stands in for the separate QA and code-review stages.

**Story 0.15 (Dockerfile at the root):**
- Use `git mv docker/Dockerfile Dockerfile`. Afterwards `docker/Dockerfile` must not exist, and every reference to the old path (about 42) names the new one: both compose files' `dockerfile:`, `ci/warm.sh`'s manifest list, `release/release.sh`, `release/upgrade-harness.sh`, `docker/tests/*`, workflow files, the dependency file's `paths_hint`, and any other grep hit.
- No change in behaviour: the build context stays `.`, the COPY paths stay the same, and `.dockerignore` still keeps the image small. Measure the image size before and after with `docker image inspect … --format '{{.Size}}'`; it must not change beyond layer metadata.
- `install.sh` and the README's install steps stay the same for the user. No test pin is deleted or weakened; a pin of the old path moves to the new path.
- `release.sh` builds the current tree from the root `Dockerfile`. The upgrade harness must accept either location for the previous release's tree, because v1.0.4 and earlier have `docker/Dockerfile`. A test pins each case.
- Any change to `release/*.sh` goes to the Contest Planner before it merges. The release-tool freeze is lifted for this story only on that condition.
- A planning artifact or spine row that names `docker/Dockerfile` as the current location is amended in place with an `[AMENDED …, Story 0.15, owner decision via the Contest Planner]` marker. The architecture's repository-layout line, which lists the Dockerfile under `docker/`, is one of these. A public doc sentence that names the path counts as public text.
- Gates: full CI green on every workflow, plus the Planner's clean install.

## Technical Decisions

- **One image recipe (AD-23):** a single Dockerfile builds `FROM` the retagged build 154 image (`ocutalon-iris-base:2026.3.0AI.154.0`). The `IRIS_IMAGE` build argument selects the non-Health image. IPM and the `ocutalon` package install at container start, version-gated, because the code database lives on the durable volume. Moving the file must keep all of this.
- **CON-1:** the AI Hub image, and any image built on it, is never pushed to a registry or kept in CI caches or artifacts. The repository ships the Dockerfile and compose files, and images are built where they run. A CI step fails on any `docker push` or registry sign-in.
- **CI rules:** scripts never run `docker compose config` without `--quiet`, or `docker inspect` without `--format`, because both print `env_file` values. Every `docker/tests/test-*.sh` belongs to exactly one of `CHECK_SCRIPTS`, `WEB_SCRIPTS` or an IRIS group in `ci/units.sh`, or `test-ci-config.sh` fails.
- **Portability:** the scripts also run under the host's bash 3.2 (macOS) in hermetic tests, so keep any new path-fallback logic in portable shell.
- **Ownership:** `docker/` belongs to Lane B, apart from Lane A's `merge.cpf`. `release/` is Lane A's release work. Only Epic 0 may edit both lanes' files together.

## Cross-Story Dependencies

- Story 0.17 was chartered after 0.16 and Story 0.15 after 0.14. They touch separate files apart from shared README pins in `docker/tests/`. If 0.15 changes any README text, rebase onto 0.17's pins.
- 0.15 contends with other epics' work on `docker/tests/lib-live.sh`, `docker/tests/test-install-upgrade.sh` (Epics 17 and 19), `docker/tests/test-release-sequence.sh` and `release/release.sh` (Epic 19). Integrate forward and expect merge conflicts there.
- The upgrade harness's previous-release build depends on v1.0.4's tree layout (old path). Both 0.15 and 0.17 are aimed at release 1.0.5 (at most one release a day).
