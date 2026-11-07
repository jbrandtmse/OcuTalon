# Epic 11 Context: Release 1 ships: the demo path end to end, upgrade in place and a scripted release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 11 is release 1's merge point: the web demo path passes end to end in the REL-2 test, an in-place upgrade and a container restart keep every record, the clean-machine rehearsal times the demo path, and one scripted sequence (`release/release.sh`) cuts a candidate with its gates, notes, checklist and the Contest Planner's hands-on pass. Part 1 is built, 1.0.0 was cut from it, and fix-forwards 11.19 to 11.26 are merged. The epic was reopened on 2026-11-07 for two timeboxed CI-flake fix-forwards that keep release CI trustworthy during voting week: 11.28 (DW-688, a no-key runner test that a late timer row of the previous test turns red) and 11.27 (DW-550, DW-774, live pages whose `/state` or `page.close` gets no answer on a loaded CI host). The gates, hands-on gate, outward steps and update hook (11.14 to 11.16, 11.18) stay in part 2.

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
- Story 11.26: The README's Measured rows say exactly what was measured (done)
- Story 11.27: Live pages get their /state answer under load (backlog)
- Story 11.28: The no-key runner test ignores a late timer row of the test before it (backlog, next)
- Story 11.14: The release sequence runs every gate on the pushed candidate (part 2, backlog)
- Story 11.15: The hands-on gate and its resume command (part 2, backlog)
- Story 11.16: The sequence asks before each outward step after the gates (part 2, backlog)
- Story 11.18: The update hook and a rehearsal candidate prove the sequence (part 2, backlog)

## Requirements & Constraints

- **Flake fix-forward rules (11.27, 11.28).** Test-only unless the cause is in the product; a product cause goes to the Contest Planner as a described change (file, lines, how upgrade and rebuild keep it) before any product code changes. No pin is deleted or weakened, and no timeout or deadline is raised as the fix. Proof: the old code fails under a repeat or load run (or a run that places the triggering condition), the fixed code passes 20 of 20 under the same conditions, and full CI is green on every workflow. When the timebox runs out without a confirmed, proved fix, the story stops and reports what was ruled out.
- **11.28 (90-minute timebox).** `OcuTalon.Test.Agent.Runners`' `TestStartsWithNoKey` check "the event log holds no error or alert row since the mark" must ignore an Ens.Alarm "Message '<n>' can not be found, timer event ignored" row for a message that existed before the mark (an earlier test's purged message, typically `TestStartRefused`'s), and must still fail on every other Type 2 or Type 6 row since the mark, including such an Ens.Alarm row for a message created after the mark. A test pins that the narrowed check still fails on a row it must see. Known evidence: the existing check counts any Type 2 row of any ConfigName; the flake was not reproduced alone, warm or in lane order.
- **11.27 (3-hour timebox), as re-ruled.** The suspected per-session gateway connection cap is ruled out: many live pages in one CSP session, even at a cap of 1 or with IRIS CPU-starved, answer `/state` in milliseconds to a few seconds, never 30 to 90 s; in CI failures IRIS was idle and the request never reached a CSP process (inference: host-level starvation of the browser or web-server path). The Planner chose option (b): DW-550 and DW-774 stay open, and 11.27 becomes test-only diagnostics: retain-on-failure traces for the live units on the CI host only (never uploaded, kept at most 7 days and deleted job-side, with a pin that no upload path includes their folder; stop and report if the runner is not self-hosted), a gateway-status dump of counts and states only in `loadedAfter`, and a measurement of the time this adds to the browser group (report it if over 2 minutes). The failing specs (I10 in `web/e2e/cards/incident-card.spec.ts`, online-session `leave.spec` L5/L6, sign-in-2 live-socket W3) keep every pin and timeout.
- **README rules (still binding).** The README claims only what the release ships, in plain language with no class names or error codes outside developer sections, keeps the not-affiliated note and credits, and contains no keys, local paths, private infrastructure details or other entrants' names; any public wording change goes to the Planner verbatim before commit.
- **Release-wide rules.** No step pushes an image, signs in to a registry or prints an environment value. Nothing outward happens without the author's word. Every command fits one 10-minute call; prefer warm mode and split long runs.

## Technical Decisions

- **Lanes (AD-29).** README, install script, `docker/`, `docker/tests/` and `web/` (including `web/e2e`) are Lane B; ObjectScript runner and agent tests run in lane A's shards, and `docs/install-ipm.md`, `release/` and the release records are Lane A. Epic 11 may change either; the orchestrator serializes it against overlapping epics.
- **Shared harness rules.** Route callbacks are removed at test end through one shared mechanism; helper waits carry bounds in shared helpers or configuration and fail naming the step. Diagnostic dumps print counts and states only, never values or secrets.
- **Success-metric context.** Release evaluations target SM-1 (routine attention decisions right, at least 90%) and SM-2 (incident causes right, at least 80%) on Claude Haiku 5.5 per candidate.
- **Candidate model.** Candidates are `release/<version>-rc<n>`, never changed after the cut; rehearsals use `rehearsal/<v>-rc<n>` on a local bare remote. Daily releases follow 1.0.0 (minor for a feature, patch for fixes only), each on the owner's word. Records live at `release/records/<version>/rc<n>.md`, staged by explicit pathspec. `release.sh` and `lib-release.sh` keep `umask 077`.

## Cross-Story Dependencies

- Order for the reopen: 11.28 first (lane A), then 11.27 under option (b). Before implementing 11.28, check Epic 19's in-flight diff on `Runners.cls` so the two do not collide.
- 11.27's diagnostics extend the live-test support that 11.21 and 11.22 built (`loadedAfter`, the DIAG `/state` dump); DW-756 notes that dump never reached CI output, so the new dump must be shown to appear there.
- Part 2 stories add steps to 11.5's `release.sh`: 11.14's rehearsal gate calls `rehearse.sh run` once per phase with `OCUTALON_RUN_TAG`; 11.16 carries the fork-PR demo-path guard and the tracked web bundle's dirty-tree issue; 11.18 needs 11.14 to 11.16.
- Epic 38 runs the real-key and hands-on passes (38.1 to 38.3) through this sequence.
