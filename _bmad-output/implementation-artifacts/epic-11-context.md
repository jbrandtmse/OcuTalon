# Epic 11 Context: Release 1 ships: the demo path end to end, upgrade in place and a scripted release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 11 is release 1's merge point: the web demo path passes end to end in the REL-2 test, an in-place upgrade and a container restart keep every record, the clean-machine rehearsal times the demo path, and one scripted sequence (`release/release.sh`) cuts a candidate with its gates, notes, checklist and the Contest Planner's hands-on pass. Part 1 is built, 1.0.0 was cut from it, and fix-forwards 11.19 to 11.25 are merged (11.25 added the README's `## Measured` table for judges). Story 11.26 is the next fix-forward, on the owner's decision (DW-775): two of the Measured table's row labels claimed more than their sources measured, so they are renamed to say exactly what was measured, with the numbers and everything else unchanged. The gates, hands-on gate, outward steps and update hook (11.14 to 11.16, 11.18) stay in part 2.

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
- Story 11.24: The README's IPM install works literally on fresh build 154 and 109 (done)
- Story 11.25: The README's judges section: a Measured table (done)
- Story 11.26: The README's Measured rows say exactly what was measured (next, backlog)
- Story 11.14: The release sequence runs every gate on the pushed candidate (part 2, backlog)
- Story 11.15: The hands-on gate and its resume command (part 2, backlog)
- Story 11.16: The sequence asks before each outward step after the gates (part 2, backlog)
- Story 11.18: The update hook and a rehearsal candidate prove the sequence (part 2, backlog)

## Requirements & Constraints

- **The two label changes (11.26), exactly as ruled.** In the README's `## Measured` table, the row label "The demo's incident, end to end with a live model" becomes "The demo's incident diagnosed with the right fix, on a live model" (its source, the eval demo gate, validates the fix and runs no dry run, approval or fix run), and "The always-on online demo" becomes "Model cost of the always-on online demo" (its number is the model cost only). Result cells ("30 of 30 runs", "about 9 to 10 cents a day") stay as they are.
- **Smallest diff.** Only those two README lines change; no other file changes except `docker/tests/test-readme.sh` and this epic's bookkeeping.
- **Pins.** The `measured` rule's label list replaces the two old labels with the new ones word for word, in place; every other pin is kept, none deleted or weakened, and the rule still fails when either new label is removed, renamed or moved out of the section. It pins no numbers.
- **Out of scope.** DW-776 (the "19 of 22 (target: 20)" row) is closed by design and stays as is. The Contest Planner updates its own collateral source file; never copy that file's path into the README.
- **Public text.** Any wording change beyond the two ruled labels (forced by the surroundings) goes to the Contest Planner verbatim as public text before commit.
- **README rules (still binding).** It claims only what the release ships, is in plain language with no class names or error codes outside developer sections, carries the not-affiliated note and the credits, and contains no keys, local machine paths, private infrastructure details or other entrants' names.
- **Release-wide rules.** No step pushes an image, signs in to a registry or prints an environment value. Nothing outward happens without the author's word. Every command fits one 10-minute call; prefer warm mode and split long runs.

## Technical Decisions

- **Lanes (AD-29).** README, install script, `docker/`, `docker/tests/` and `web/` are Lane B; `docs/install-ipm.md`, `release/` and the release records are Lane A. Epic 11 may change either; the orchestrator serializes it against overlapping epics. Epic 34's README and test-readme.sh hunks (licence notices, licence check) stay separate from Epic 11's.
- **Success-metric context.** The release evaluation targets are SM-1 (routine attention decisions right, at least 90%) and SM-2 (incident causes right, at least 80%), run on Claude Haiku 5.5 on each release candidate; the table reports results, it does not redefine the targets.
- **Shared harness rules.** Route callbacks are removed at test end through one shared mechanism; helper waits carry bounds in shared helpers or configuration and fail naming the step.
- **Candidate model.** Candidates are `release/<version>-rc<n>`, never changed after the cut; rehearsals use `rehearsal/<v>-rc<n>` on a local bare remote. Daily releases follow 1.0.0 (minor for a feature, patch for fixes only), each on the owner's word. Records live at `release/records/<version>/rc<n>.md`, staged by explicit pathspec. `release.sh` and `lib-release.sh` keep `umask 077`.

## Cross-Story Dependencies

- 11.26 edits the Measured section and `measured` rule that 11.25 added (and the README and `test-readme.sh` that 11.23 and 11.24 changed); build on their merged pins and leave the rest untouched.
- 11.26 ships in the next daily release; the README goes public with the repository.
- Part 2 stories add steps to 11.5's `release.sh`: 11.14's rehearsal gate calls `rehearse.sh run` once per phase with `OCUTALON_RUN_TAG`; 11.16 carries the fork-PR demo-path guard and the tracked web bundle's dirty-tree issue; 11.18 needs 11.14 to 11.16.
- Epic 38 runs the real-key and hands-on passes (38.1 to 38.3) through this sequence.
