# Epic 11 Context: Release 1 ships: the demo path end to end, upgrade in place and a scripted release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 11 is release 1's merge point: the web demo path passes end to end in the REL-2 test, an in-place upgrade and a container restart keep every record, the clean-machine rehearsal times the demo path, and one scripted sequence (`release/release.sh`) cuts a candidate with its gates, notes, checklist and the Contest Planner's hands-on pass. Part 1 is built, 1.0.0 was cut from it, and fix-forwards 11.19 to 11.26 are merged. The epic was reopened on 2026-11-07 for two timeboxed CI-flake fix-forwards that keep release CI trustworthy during voting week: 11.28 (DW-688, the no-key runner test's late timer row) is done; 11.27 (DW-550, DW-774, live pages whose `/state` or `page.close` gets no answer on a loaded CI host) is re-scoped to test-only diagnostics so the next CI occurrence shows where `/state` waits. The gates, hands-on gate, outward steps and update hook (11.14 to 11.16, 11.18) stay in part 2.

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
- Story 11.28: The no-key runner test ignores a late timer row of the test before it (done)
- Story 11.27: Live pages get their /state answer under load, as test-only diagnostics (backlog, next)
- Story 11.14: The release sequence runs every gate on the pushed candidate (part 2, backlog)
- Story 11.15: The hands-on gate and its resume command (part 2, backlog)
- Story 11.16: The sequence asks before each outward step after the gates (part 2, backlog)
- Story 11.18: The update hook and a rehearsal candidate prove the sequence (part 2, backlog)

## Requirements & Constraints

- **11.27 scope (3-hour timebox, option (b)).** The suspected per-session gateway connection cap is ruled out (many live pages in one CSP session answer `/state` in milliseconds to seconds even at a cap of 1 or with IRIS CPU-starved; in CI failures IRIS was idle and the request never reached a CSP process). DW-550 and DW-774 stay open; the story changes tests and CI only, no product code. No pin is deleted or weakened and no timeout is raised; the failing specs (I10 in `web/e2e/cards/incident-card.spec.ts`, online-session `leave.spec` L5/L6, sign-in-2 live-socket W3) stay as they are.
- **Traces.** Live units' Playwright runs on CI keep a trace only for a failing test (`retain-on-failure`). Before any upload step can run, the trace is moved to a folder on the self-hosted runner's own disk outside the job workspace, under the run's tag and the unit's name; no trace stays under `web/test-results/`. On a runner that is not self-hosted no trace is written at all.
- **Trace retention and privacy.** Each job deletes run folders in the trace folder older than 7 days. A test pins that no `actions/upload-artifact` path in `.github/workflows/*.yml` includes the trace folder or a trace file (the repository is public; CI artifacts must never carry traces).
- **Gateway dump.** When `loadedAfter`'s snapshot GET passes its bound, the diagnosis adds `DIAG /state gateway ...` lines beside the existing licence, CSP-process and session-lock lines: per server, total connections, connections in use, private connections and queued requests; per connection, its state. Counts and states only: no request body, cookie, session id or token.
- **DW-756.** The existing DIAG dump never reached CI output (only the e2e log's tail is printed). Every DIAG line must also land in the test's own output folder, which the failure artifact uploads.
- **Cost.** Measure the browser group's added time with traces on and no failures against its time before the story; more than 2 minutes goes to the Planner before the merge. A full CI run stays within 35 minutes.
- **Release-wide rules.** No step pushes an image, signs in to a registry or prints an environment value. Nothing outward happens without the author's word. Every command fits one 10-minute call; prefer warm mode and split long runs. README rules stay binding: claims only what ships, plain language, no keys, local paths, private infrastructure or other entrants' names, public wording to the Planner verbatim before commit.

## Technical Decisions

- **Lanes (AD-29).** README, install script, `docker/`, `docker/tests/`, `web/` (including `web/e2e`) and `.github/workflows/ci.yml` (builds, shards, checks, web and demo path) are Lane B; ObjectScript runner and agent tests, `lane-a.yml`, `docs/install-ipm.md`, `release/` and the release records are Lane A. Epic 11 may change either; the orchestrator serializes it against overlapping epics.
- **CI hosts.** ObjectScript shards run on the self-hosted IRIS runner, each shard in its own compose project; web and mock code run on hosted runners. Where a live unit runs decides whether 11.27 writes traces at all.
- **Shared harness rules.** Route callbacks are removed at test end through one shared mechanism; helper waits carry bounds in shared helpers or configuration and fail naming the step. Diagnostic dumps print counts and states only, never values or secrets.
- **Candidate model.** Candidates are `release/<version>-rc<n>`, never changed after the cut; rehearsals use `rehearsal/<v>-rc<n>` on a local bare remote. Daily releases follow 1.0.0 (minor for a feature, patch for fixes only), each on the owner's word. Records live at `release/records/<version>/rc<n>.md`, staged by explicit pathspec. `release.sh` and `lib-release.sh` keep `umask 077`.
- **Success metrics.** Release evaluations target SM-1 (routine attention decisions right, at least 90%) and SM-2 (incident causes right, at least 80%) on Claude Haiku 5.5 per candidate.

## Cross-Story Dependencies

- 11.27 extends the live-test support 11.21 and 11.22 built (`loadedAfter`, the DIAG `/state` dump); the new gateway lines and the DW-756 routing must be shown to appear in CI output.
- Part 2 stories add steps to 11.5's `release.sh`: 11.14's rehearsal gate calls `rehearse.sh run` once per phase with `OCUTALON_RUN_TAG`; 11.16 carries the fork-PR demo-path guard and the tracked web bundle's dirty-tree issue; 11.18 needs 11.14 to 11.16.
- Epic 38 runs the real-key and hands-on passes (38.1 to 38.3) through this sequence.
