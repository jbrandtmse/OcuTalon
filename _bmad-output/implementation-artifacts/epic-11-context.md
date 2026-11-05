# Epic 11 Context: Release 1 ships: the demo path end to end, upgrade in place and a scripted release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 11 is release 1's merge point: the web demo path passes end to end in the REL-2 test, an in-place upgrade and a container restart keep every record, the clean-machine rehearsal times the demo path, and one scripted sequence (`release/release.sh`) cuts a candidate with its gates, notes, checklist and the Contest Planner's hands-on pass. Part 1 is built and 1.0.0 was cut from it; fix-forwards 11.20 and 11.21 and the first daily release's burn-down (11.22) are merged. Story 11.23 is the burn-down's follow-on: the Early Access portal now offers only build 109, and install.sh refuses it, so a judge's local install stops at its first step. 11.23 makes install.sh accept the build 109 image by its exact ref alongside today's build 154 ref, and retires the README's separate build-109 path; it ships in the next daily release. The gates, hands-on gate, outward steps and update hook (11.14 to 11.16, 11.18) stay in part 2.

## Stories

- Story 11.0: Epic 10 deferred cleanup (done)
- Story 11.1: The web demo path passes end to end in the REL-2 test (done)
- Story 11.7: Failure paths, quiet outcomes and online run (done)
- Story 11.10: Failure paths and quiet outcomes pass in REL-2 (done)
- Story 11.8: The chat cancels several reminders in one call (done)
- Story 11.9: Every check left off for release 1 turns on; CI flakes fixed (done)
- Story 11.2: Upgrades and restarts keep every record working (done)
- Story 11.3: The clean-machine rehearsal installs and times the demo path (done)
- Story 11.11: The rehearsal runner times the demo path and checks every bound (done)
- Story 11.12: The rehearsal runner repeats the demo path N times (done)
- Story 11.4: The release checklist (done)
- Story 11.13: Draft release notes (done)
- Story 11.5: One scripted sequence cuts a release (done)
- Story 11.17: The release's IPM artifact carries the built page (done)
- Story 11.19: Seeded check rows stay out of the heartbeat's way (done)
- Story 11.20: The overview step hands the unit files the container can read (done)
- Story 11.21: A test's route callback never outlives its test (done)
- Story 11.22: First daily release burn-down (done)
- Story 11.23: install.sh accepts build 109 (next, backlog)
- Story 11.14: The release sequence runs every gate on the pushed candidate (part 2, backlog)
- Story 11.15: The hands-on gate and its resume command (part 2, backlog)
- Story 11.16: The sequence asks before each outward step after the gates (part 2, backlog)
- Story 11.18: The update hook and a rehearsal candidate prove the sequence (part 2, backlog)

## Requirements & Constraints

- **Accepted image refs (11.23).** install.sh accepts exactly two refs: the build 109 image `irishealth-community:2027.1.0AI.109.0` and today's build 154 ref; every other ref is refused as it is today. A test pins both accepted refs, and a mutation shows a third ref is refused. Match by exact ref, never by pattern or prefix.
- **What install.sh still does.** It finds the loaded image and checks its CPU architecture against the machine; retags it to the name every compose file expects; runs `docker compose up` and waits up to 15 minutes for the health check, showing progress; prints the web address and sign-in details. A missing image or wrong architecture stops with a clear message giving the exact fix. It is safe to re-run, runs on macOS and Linux, and a hand load-and-retag followed by a plain `docker compose up` gives the same result.
- **README is public text (11.23).** The README's separate "Start it with build 109" path is changed once install.sh accepts build 109. The new text goes to the Contest Planner verbatim before it is committed and is committed only once approved. `docker/tests/test-readme.sh`'s build-109 pins are updated, never deleted. The README claims only what the release ships.
- **API errors.** REST errors are `{"error": {"code": "...", "message": "..."}}` in plain English with snake_case codes; any request body over 256 KB gets 413 `body_too_large` unless its route declares a larger bound of its own.
- **Shared harness rules (still binding).** Route callbacks are removed at test end through one shared mechanism; helper waits carry bounds in the shared helpers or shared Playwright configuration, never per-spec copies, and fail with a message naming the step. A new bound is pinned by a test with the mutation shown.
- **Release-wide rules.** No step pushes an image or signs in to a registry; no step prints an environment value (`docker compose config` only with `--quiet`, `docker inspect` only with `--format`). Records describe machines only by OS, CPU architecture and memory. Nothing outward happens without the author's word.
- Every command fits one 10-minute call; prefer warm mode and split long runs.

## Technical Decisions

- **Image and retag.** One Dockerfile builds `FROM` the retagged base image (`ocutalon-iris-base:...`, the name every compose file expects); a build argument (`IRIS_IMAGE`) selects the non-Health image. install.sh retags whichever accepted archive was loaded, preferring the IRIS for Health image when both are present. Build 154 (`irishealth-community:2026.3.0AI.154.0`) is the platform the architecture was checked against.
- **Test layout.** The README pins live in `docker/tests/test-readme.sh`; Playwright 1.64.x specs under `web/e2e/` and `web/e2e-online/`. A turned-on test that must never skip again carries `@floor`.
- **Lanes (AD-29).** `web/`, `docker/` and `docker/tests/`, `.github/workflows/ci.yml` and the rest of `ci/` are Lane B; `release/`, the release records and the `docs/` security overview are Lane A. Epic 11 may change either lane's files; the orchestrator serializes it against any epic whose files overlap. Shared files take one appended entry per story.
- **Candidate model.** A candidate is identified by version and commit SHA on `release/<version>-rc<n>`, never changed after the cut; a failed gate means a fix on the integration branch and a new `rc<n+1>`. Rehearsal candidates are `rehearsal/<v>-rc<n>`, local bare remote only. After 1.0.0 a release goes out daily with whatever has merged (minor bump for a feature, patch for fixes only), each on the owner's word.
- **Records.** `release/records/<version>/rc<n>.md` holds the SHA, each gate's result and the hands-on pass; stage only `rc<n>.md` by explicit pathspec, never the folder.
- **Release script file mode.** `release.sh` and `lib-release.sh` keep `umask 077`; anything handed to a container whose user differs is opened with `chmod -R a+rX`.

## Cross-Story Dependencies

- 11.23 was split out of 11.22 (declined there on size, 2 to 2.5 h) so 11.22's validated spec stands; it is independent of the part 2 release stories and ships in the next daily release.
- 11.23's README change waits on the Contest Planner's approval of the verbatim public text before commit.
- Part 2 stories add steps to 11.5's `release.sh`: 11.14's rehearsal gate calls `rehearse.sh run` once per phase with `OCUTALON_RUN_TAG`; 11.16 carries the fork-PR demo-path guard and the tracked web bundle's dirty-tree issue; 11.18 needs 11.14 to 11.16.
- Epic 38 runs the real-key and hands-on passes (38.1 to 38.3) through this sequence.
