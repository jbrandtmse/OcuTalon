# Epic 11 Context: Release 1 ships: the demo path end to end, upgrade in place and a scripted release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 11 is release 1's merge point: the web demo path passes end to end in the REL-2 test, an in-place upgrade and a container restart keep every record, the clean-machine rehearsal times the demo path, and one scripted sequence (`release/release.sh`) cuts a candidate with its gates, notes, checklist and the Contest Planner's hands-on pass. Part 1 is built and 1.0.0 was cut from it; fix-forwards 11.20 to 11.23 are merged (11.23 made install.sh accept the build 109 image). Story 11.24 is a high-priority fix-forward: the 1.0.1 registry check installed the package, but the README's IPM path stopped on a fresh AI Hub image, which ships without IPM, and the first `zpm "enable -community"` skipped USER's repository mapping when IPM was loaded in %SYS only. Organizers check IPM installs on build 154 during judging, so the README's commands must work literally, as written, on a fresh build 154 and build 109 instance. The gates, hands-on gate, outward steps and update hook (11.14 to 11.16, 11.18) stay in part 2.

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
- Story 11.23: install.sh accepts build 109 (done)
- Story 11.24: The README's IPM install works literally on a fresh build 154 and build 109 instance (next, backlog)
- Story 11.14: The release sequence runs every gate on the pushed candidate (part 2, backlog)
- Story 11.15: The hands-on gate and its resume command (part 2, backlog)
- Story 11.16: The sequence asks before each outward step after the gates (part 2, backlog)
- Story 11.18: The update hook and a rehearsal candidate prove the sequence (part 2, backlog)

## Requirements & Constraints

- **Literal IPM install (11.24).** On throwaway containers from the plain AI Hub build 154 image and the plain build 109 Health image (never OcuTalon's built image), the README's "Install it with IPM" commands, pasted in order, install IPM 0.10.10, enable it for USER and install `ocutalon` from the public registry with no extra command. Each run ends with OCUTALON Activate SUCCESS and the page answering 200. Evidence of both runs is committed under `_bmad-output/implementation-artifacts/evidence/`.
- **Mapped and unmapped USER.** The one documented sequence that points USER at the community registry works whether or not USER was IPM-mapped before it ran (for example a `-map` step before `enable -community`). Show both cases by a real run, never by assumption.
- **The install guide matches.** `docs/install-ipm.md` carries exactly the README's commands, drops the stale "Until the package is published ... a local IPM repository." sentence, and its sample outputs come from a real public-registry run.
- **Public text.** README and `docs/install-ipm.md` diffs go to the Contest Planner verbatim before commit and are committed only once approved. `docker/tests/test-readme.sh` pins are updated in place, never deleted. Epic 34's README and test-readme.sh hunks (licence notices, licence check) stay separate from this story's. The README claims only what the release ships.
- **IPM install shape (still binding).** An IPM install into an existing instance is the same package run twice: first in any Interoperability-enabled namespace (USER; IPM refuses %SYS and namespaces without Interoperability), which creates OCUTALON and stops with `ERROR! ` and the exact next command by design; then in OCUTALON. Demo mode is off there. The `iris merge` alternative is followed by `zpm "enable -map -ns OCUTALON"`.
- **Release-wide rules.** No step pushes an image or signs in to a registry. No step prints an environment value (`docker compose config` only with `--quiet`, `docker inspect` only with `--format`). Records describe machines only by OS, CPU architecture and memory. Nothing outward happens without the author's word: the registry publish, Open Exchange listing and contest entry are the owner's.
- **Shared harness rules.** Route callbacks are removed at test end through one shared mechanism. Helper waits carry bounds in shared helpers or configuration, fail naming the step, and a new bound is pinned by a test with the mutation shown.
- Every command fits one 10-minute call; prefer warm mode and split long runs.

## Technical Decisions

- **One package.** `ocutalon` is the single IPM package (IPM 0.10.10). `src/module.xml` lists its CPF resource first, then the bridge, then the rest, plus the built web bundle (11.17), so a registry install needs no Node.js.
- **Early step and repositories.** The early preload step maps IPM into OCUTALON with transactions suspended and, outside OCUTALON, maps IPM's repository definitions (`^IPM.Repo.Definition{D,S,I}`) from the run namespace via `%IPM.Utils.Build.MapGlobalEquivalently`, because IPM's own `enable -map -repos` skips a namespace whose IPM is mapped from elsewhere (measured). Definitions are mapped as they are, never copied, created, edited or printed. Uninstall removes only that mapping.
- **IPM steps.** The installer steps run from `Registry.Ipm` at Configure/After; on the image (`/opt/ocutalon/version` exists) it does nothing. The IPM caller marks `OcuTalon.Production` autostart; STEP/WARN lines print to the install command's output.
- **Images.** install.sh accepts exactly `irishealth-community:2026.3.0AI.154.0`, `irishealth-community:2027.1.0AI.109.0` or `iris-community:2026.3.0AI.154.0` by exact ref, preferring Health and build 154 before build 109, and retags to `ocutalon-iris-base:2026.3.0AI.154.0`. The AI Hub image is never pushed or cached in CI.
- **Lanes (AD-29).** README, install script, `docker/`, `docker/tests/` and `web/` are Lane B; `docs/install-ipm.md`, `release/` and the release records are Lane A. Epic 11 may change either; the orchestrator serializes it against overlapping epics. Shared files take one appended entry per story.
- **Candidate model.** Candidates are `release/<version>-rc<n>`, never changed after the cut; rehearsals use `rehearsal/<v>-rc<n>` on a local bare remote. Daily releases follow 1.0.0 (minor for a feature, patch for fixes only), each on the owner's word. Records live at `release/records/<version>/rc<n>.md`, staged by explicit pathspec. `release.sh` and `lib-release.sh` keep `umask 077`.

## Cross-Story Dependencies

- 11.24 builds on Epic 15's IPM package and install guide (15.1 to 15.4) and on 11.17's self-contained artifact, as published to the public registry (1.0.1 installed from it).
- 11.24's public text waits on the Contest Planner's approval before commit, and it must not absorb Epic 34's README/test-readme.sh hunks.
- Part 2 stories add steps to 11.5's `release.sh`: 11.14's rehearsal gate calls `rehearse.sh run` once per phase with `OCUTALON_RUN_TAG`; 11.16 carries the fork-PR demo-path guard and the tracked web bundle's dirty-tree issue; 11.18 needs 11.14 to 11.16.
- Epic 38 runs the real-key and hands-on passes (38.1 to 38.3) through this sequence.
