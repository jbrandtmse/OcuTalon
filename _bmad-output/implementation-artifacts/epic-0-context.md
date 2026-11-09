# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton: one image build and `docker compose up` give OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start, with a branded page behind sign-in, the Orders demo production in OCUORDERS, every cross-lane contract and production stub, and CI with the model mock. Stories 0.1 to 0.14, 0.16 and 0.17 are done. Epic 0 is re-opened after the v1.0.4 release for release 1.0.5, with small stories that leave the build and install unchanged. Story 0.17 (done) updated the README's Measured table to 1.0.4's real-model numbers. Story 0.18 adds Planner-approved judge-facing README sections on top of 0.17, and must merge before the 10:00Z hold. Story 0.15 moves the Dockerfile to the repository root so the Open Exchange listing reads Docker True.

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
- Story 0.15: The Dockerfile sits at the repository root (ready-for-dev)
- Story 0.16: The Embedded Python callback crash (S11) is re-verified with a minimal reproduction (done)
- Story 0.17: The README's evaluation table shows release 1.0.4's numbers (done)
- Story 0.18: The README shows judges where to look (backlog)

## Requirements & Constraints

**Approved public text (0.17, 0.18):** README text the Contest Planner approved under the owner's delegation goes in byte for byte. Do not reword, re-punctuate or "improve" it. If a test rule fails on the verbatim text, the text still stays as written; report the failure.

**Story 0.18 (README for judges):**
- Source is the Planner's final edit file (`readme-judges-1.0.5-FINAL.md`, section (b), Edits 1 to 6). Edits 1 to 5 go into README.md at their anchors: the link bar becomes the first paragraph of "Try it in two minutes"; the H3 sections "For judges: where to look" and "New since 1.0.0" go after step 4 of the local path; the "What changes without the agent?" paragraph goes above "With a model, and without one."; the H2 "Contest checklist" goes directly before "Credits and licences".
- Nothing else in README.md changes, and no line is removed.
- Edit 6 replaces `docker/tests/test-readme.sh`'s link allow-list with exactly the Planner's line: `community.intersystems.com` and `openexchange.intersystems.com` appear once each, nothing else is added, and no AI Hub bug-report repository is allowed. 0.17's narrower post-path entry, and its two self-tests that only that narrower entry could pass, give way to the host entry.
- Done when `bash docker/tests/test-readme.sh` passes every rule, `docker/tests/test-boundaries.sh` passes, and CI is green.
- Pipeline (also used for 0.17): one `bmad-build-auto` stage plans and implements. The runner's own byte-for-byte diff review takes the place of separate QA and code-review stages.
- The README's standing rules still hold: "Try it in two minutes" stays at the top with the online demo link; claim only what the release ships; plain English, with no class names or error codes outside the developer sections; keep the BMAD/Claude Code credits and the not-affiliated note.

**Story 0.15 (Dockerfile at the root):**
- Use `git mv docker/Dockerfile Dockerfile`. Afterwards `docker/Dockerfile` must not exist, and every reference to the old path names the new one: both compose files' `dockerfile:`, `ci/warm.sh`'s manifest list, `release/release.sh`, `release/upgrade-harness.sh`, `docker/tests/*`, workflow files, and every other grep hit.
- Behaviour stays the same: the build context stays `.`, the COPY paths are unchanged, and `.dockerignore` still keeps the image small. Compare `docker image inspect … --format '{{.Size}}'` before and after; the only allowed difference is layer metadata.
- `install.sh` and the README's install steps stay the same for the user. No test pin is deleted or weakened; a pin of the old path moves to the new path.
- `release.sh` builds the current tree from the root `Dockerfile`. The upgrade harness accepts either location for the previous release's tree (v1.0.4 and earlier use `docker/Dockerfile`), with a test pinning each case.
- Any change to `release/*.sh` goes to the Contest Planner before it merges; the release-tool freeze is lifted for this story only.
- Any planning artifact or spine row that names `docker/Dockerfile` as the current location (including the architecture's repository-layout line) is amended in place with an `[AMENDED …, Story 0.15, owner decision via the Contest Planner]` marker. A public doc sentence that names the path counts as public text.
- Gates: CI green on every workflow, and the Planner's clean install.

## Technical Decisions

- **One image recipe:** a single Dockerfile builds `FROM` the retagged build 154 image (`ocutalon-iris-base:2026.3.0AI.154.0`), and the `IRIS_IMAGE` build argument selects the non-Health image. IPM and the `ocutalon` package install at container start, version-gated, because the code database lives on the durable volume.
- **Never push the image:** the AI Hub image, and any image built on it, is never pushed to a registry or kept in CI caches or artifacts. A CI step fails on any `docker push` or registry sign-in.
- **CI rules:** never run `docker compose config` without `--quiet`, or `docker inspect` without `--format`, because both print `env_file` values. Every `docker/tests/test-*.sh` belongs to exactly one of `CHECK_SCRIPTS`, `WEB_SCRIPTS` or an IRIS group in `ci/units.sh`; otherwise `test-ci-config.sh` fails.
- **Portability:** scripts also run under macOS's bash 3.2 in hermetic tests, so any new path-fallback logic must be portable shell.
- **Ownership:** `docker/` belongs to Lane B, except Lane A's `merge.cpf`. `release/` is Lane A's release work. Only Epic 0 may edit files from both lanes in one story.

## Cross-Story Dependencies

- 0.18 is built on 0.17's README text and its `test-readme.sh` pins. 0.18 must merge before the 10:00Z hold for release 1.0.5.
- 0.15 and 0.18 both touch `docker/tests/` README pins. Whichever merges second rebases onto the other's pins. If 0.15 changes any README text, the 0.18 anchors must still hold.
- 0.15 contends with other epics on `docker/tests/lib-live.sh`, `docker/tests/test-install-upgrade.sh` (Epics 17 and 19), `docker/tests/test-release-sequence.sh` and `release/release.sh` (Epic 19). Integrate forward and expect conflicts there.
- The upgrade harness's previous-release build depends on v1.0.4's tree layout (the old path). Releases ship at most one a day.
