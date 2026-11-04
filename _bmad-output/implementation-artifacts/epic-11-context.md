# Epic 11 Context: Release 1 ships: the demo path end to end, upgrade in place and a scripted release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 11 is release 1's merge point: the web demo path passes end to end in the REL-2 test, an in-place upgrade and a container restart keep every record, the clean-machine rehearsal times the demo path, and one scripted sequence (`release/release.sh`) cuts a candidate with its gates, notes, checklist and the Contest Planner's hands-on pass. Part 1 is built, including Story 11.20's fix-forward of the overview step's file mode, from which 1.0.0 was cut. After v1.0.0, `main`'s `iris (browser)` job went red twice on a test-harness defect, not a product failure: a route callback still in flight when its test ended (`route.fetch: Test ended`, 253 passed, 1 failed, demo path 28 of 28). Story 11.21 is that fix-forward and the first burndown item of the first daily release; it also bounds the online specs' helper waits so a hang names its step in seconds. The gates, hands-on gate, outward steps and update hook (11.14 to 11.16, 11.18) stay in part 2.

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
- Story 11.21: A test's route callback never outlives its test (next, backlog)
- Story 11.14: The release sequence runs every gate on the pushed candidate (part 2, backlog)
- Story 11.15: The hands-on gate and its resume command (part 2, backlog)
- Story 11.16: The sequence asks before each outward step after the gates (part 2, backlog)
- Story 11.18: The update hook and a rehearsal candidate prove the sequence (part 2, backlog)

## Requirements & Constraints

- **One shared unroute (11.21).** Every spec under `web/e2e` and `web/e2e-online` that installs a route callback calling `route.fetch` has its callbacks removed when the test ends through one shared mechanism (the shared route helper or a shared `afterEach`) using `page.unrouteAll({ behavior: 'ignoreErrors' })`. No spec carries its own copy of the fix.
- **Pinned with a mutation.** A test proves a callback still in flight at test end no longer fails the run with `route.fetch: Test ended`; removing the shared mechanism turns it red, and the mutation is shown.
- **Future specs covered.** A spec added later that installs such a callback is covered with no further edits, or a check names it.
- **Bounded helper waits (online specs).** In `web/e2e-online`, every helper wait (page action, navigation, response wait, request, and the IRIS script call through `irisScript`, which today bounds no `iris session`) gets its own bound well under the 5-minute test timeout, so a hang fails naming its step within seconds. The bound lives in the shared helpers or the shared Playwright configuration (which today sets no action or navigation timeout), never as per-spec copies; one bounded wait is pinned by a test with a mutation shown.
- **Proof runs.** On the fix branch, `iris (browser)` is green three runs in a row with every other group green, and in the same three runs `iris (shards)` (which runs `live:online-session`) is green with `web/e2e-online/session/leave.spec.ts` L5 and L6 passing.
- **No product change.** This is a test-harness defect; no product code changes. Ledger items DW-640 (`live/live.spec.ts` L9 failed from L8's callback) and DW-665 (`live/socket.spec.ts` W11, twice on v1.0.0) close with it.
- **Release-wide rules.** No step pushes an image or signs in to a registry; no step prints an environment value (`docker compose config` only with `--quiet`, `docker inspect` only with `--format`). Records describe machines only by OS, CPU architecture and memory. Nothing outward happens without the author's word.
- Every command fits one 10-minute call; prefer warm mode and split long runs.

## Technical Decisions

- **Test layout.** Playwright 1.64.x. Specs live under `web/e2e/` (demo-path specs are one per UJ-1 step under `web/e2e/demo-path/`; the accessibility floor's specs under `web/e2e/floor/` run only in their own unit `live:floor`, never in `live:sign-in`), online-demo specs under `web/e2e-online/`. A turned-on test that must never skip again carries `@floor`; an unbuilt part is a `notBuilt(title, 'N.M')` call.
- **Lanes (AD-29).** `web/` (including the e2e specs, runner configuration and fixtures), `docker/` and `docker/tests/`, `.github/workflows/ci.yml` and the rest of `ci/` are Lane B; `release/`, the release records and the `docs/` security overview are Lane A. Epic 11 may change either lane's files; the orchestrator serializes it against any epic whose files overlap.
- **Candidate model.** A candidate is identified by version and commit SHA on `release/<version>-rc<n>`, never changed after the cut; a failed gate means a fix on the integration branch and a new `rc<n+1>`. Rehearsal candidates are `rehearsal/<v>-rc<n>`, local bare remote only, never pushed to origin. After 1.0.0 a release goes out daily with whatever has merged (minor bump for a feature, patch for fixes only), each on the owner's word.
- **Records.** `release/records/<version>/rc<n>.md` on the integration branch holds the SHA, each gate's result, the hands-on pass and hands-on time; stage only `rc<n>.md` by explicit pathspec, never the folder (the draft notes beside it are never published).
- **Release script file mode.** `release.sh` and `lib-release.sh` keep `umask 077` (the state files rely on it); anything handed to a container whose user differs must be opened with `chmod -R a+rX`, as the overview and IPM steps do.

## Cross-Story Dependencies

- 11.21 touches only the shared e2e helpers and configuration (Lane B) and is independent of the part 2 release stories; its proof runs depend on the `iris (browser)` and `iris (shards)` CI groups.
- Part 2 stories add steps to 11.5's `release.sh`: 11.14's rehearsal gate calls `rehearse.sh run` once per phase with `OCUTALON_RUN_TAG` (exit 4 until the last phase, DW-548); 11.16 carries DW-27 and DW-532; 11.18 needs 11.14 to 11.16.
- Epic 38 runs the real-key and hands-on passes (38.1 to 38.3) through this sequence.
