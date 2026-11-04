# Epic 11 Context: Release 1 ships: the demo path end to end, upgrade in place and a scripted release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 11 is release 1's merge point: the web demo path passes end to end in the REL-2 test, an in-place upgrade and a container restart keep every record, the clean-machine rehearsal times the demo path, and one scripted sequence (`release/release.sh`) cuts a candidate with its gates, notes, checklist and the Contest Planner's hands-on pass. Part 1 is built; the gates, hands-on gate, outward steps and update hook (11.14 to 11.16, 11.18) were split to part 2, after rc1. The 1.0.0-rc1 cut then failed twice at the release sequence's overview step because of the script's own file mode, not the product; Story 11.20 is the fix-forward, and rc2 is cut from its merge.

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
- Story 11.14: The release sequence runs every gate on the pushed candidate (part 2, backlog)
- Story 11.15: The hands-on gate and its resume command (part 2, backlog)
- Story 11.16: The sequence asks before each outward step after the gates (part 2, backlog)
- Story 11.18: The update hook and a rehearsal candidate prove the sequence (part 2, backlog)
- Story 11.20: The overview step hands the unit files the container can read (next, backlog)

## Requirements & Constraints

- **Readable export (11.20).** After the overview step exports the candidate's tree and before it hands it to the security-overview unit, every exported file and folder must be readable by other users and every folder searchable (`chmod -R a+rX` on the export), with a comment in the script's style saying why: the unit copies files into a container whose IRIS user differs, and the script's umask 077 leaves them owner-only.
- **Umask stays.** The script's `umask 077` is unchanged; the release state files rely on it.
- **Failure log kept.** When the overview unit fails, its log stays in the release state folder (for example `overview-fail.log`) and its path is printed with the FAIL line, instead of being removed.
- **Regression pinned without IRIS.** The release unit tests' stub overview unit fails if any exported file is not readable by others, so a regression of the mode fix reds the release-sequence tests; one case checks that a failing unit's log is kept and its path printed.
- **Security overview purpose.** The overview's generated sections (tool list, service-user privileges) must equal a fresh generation from the candidate's code; the step checks that rather than failing on file access.
- **Release-wide rules.** No step pushes an image or signs in to a registry; no step prints an environment value (`docker compose config` only with `--quiet`, `docker inspect` only with `--format`). Records describe machines only by OS, CPU architecture and memory, never by host name or address. Nothing outward happens without the author's word.
- Every command fits one 10-minute call; prefer warm mode and split long runs.

## Technical Decisions

- **Root cause (11.20).** `release.sh` and `lib-release.sh` both set `umask 077`; `candidate_export` (a `git archive | tar -x`) therefore writes `docs/security-overview.md` as 0600; `test-security-overview.sh` copies it into the container, where IRIS's user reads an empty file and reports the missing generated-tools marker (ERROR #5001, "Regenerate did not succeed"). The same tree under umask 022 passes the whole unit. The IPM step already opens its files to others inside its container (`chmod -R a+rX`), which is the precedent to follow.
- **Candidate model.** A candidate is identified by version and commit SHA on `release/<version>-rc<n>`, never changed after the cut; a failed gate means a fix on the integration branch and a new `rc<n+1>`. Rehearsal candidates are `rehearsal/<v>-rc<n>`, local bare remote only, never pushed to origin.
- **Records.** `release/records/<version>/rc<n>.md` on the integration branch holds the SHA, each gate's result, the hands-on pass and hands-on time; stage only `rc<n>.md` by explicit pathspec, never the folder (the draft notes beside it must never be published).
- **Lanes (AD-29).** `release/`, the release records, and `docs/` security overview and bridge guide are Lane A; `docker/` (including `docker/tests/`), `web/`, the rest of `ci/`, the install script and the README are Lane B. Changes across lanes are serialized by the orchestrator.

## Cross-Story Dependencies

- 11.20 is a fix-forward on 11.5's `release.sh` overview step (Story 14.1's unit); rc2 of 1.0.0 is cut from its merge.
- Part 2 stories add steps to 11.5's `release.sh`: 11.14's rehearsal gate calls `rehearse.sh run` once per phase with `OCUTALON_RUN_TAG` (exit 4 until the last phase, DW-548); 11.16 carries DW-27 and DW-532; 11.18 needs 11.14 to 11.16.
- Epic 38 runs the real 1.0.0 cut and the real-key and hands-on passes (38.1 to 38.3) through this sequence.
