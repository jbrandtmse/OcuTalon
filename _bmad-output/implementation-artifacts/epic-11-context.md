# Epic 11 Context: Release 1 ships: the demo path end to end, upgrade in place and a scripted release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 11 is release 1's merge point: the web demo path passes end to end in the REL-2 test, an in-place upgrade and a container restart keep every record, the clean-machine rehearsal times the demo path, and one scripted sequence (`release/release.sh`) cuts a candidate with its gates, notes, checklist and the Contest Planner's hands-on pass. Part 1 is built and 1.0.0 was cut from it; fix-forwards 11.20 (the overview step's file mode) and 11.21 (route callbacks removed at test end, bounded helper waits) are merged. Story 11.22 is the first daily release's burn-down: it fixes, or closes on evidence, the harness reds and small product gaps that release found (a disabled Telegram item's lingering job, an unbounded request body, a leaked incident, CI uploading no Playwright results, `/state` not answering after sign-in, the request fixture's missing timeout), merges when done and ships in the next daily release, ahead of part 2. The gates, hands-on gate, outward steps and update hook (11.14 to 11.16, 11.18) stay in part 2.

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
- Story 11.22: First daily release burn-down (next, backlog)
- Story 11.14: The release sequence runs every gate on the pushed candidate (part 2, backlog)
- Story 11.15: The hands-on gate and its resume command (part 2, backlog)
- Story 11.16: The sequence asks before each outward step after the gates (part 2, backlog)
- Story 11.18: The update hook and a rehearsal candidate prove the sequence (part 2, backlog)

## Requirements & Constraints

- **Disabled items sampled only when quiet (11.22).** Before `check_items_run` or `live_park_telegram` samples a disabled production item (TelegramIn, TelegramOut), it waits on its own bound of about 30 s until the item has no `Ens.Job` entry in any state; on the bound it fails naming the item and the entry's state. Never count only Alive jobs (the strict fix).
- **Request body cap (11.22).** The shared request-body reader (`BodyText`) answers 413 `body_too_large` for any body over 256 KB, before parsing, in the API's standard error shape (`{"error": {"code", "message"}}`). A route may declare a larger bound of its own without changing the shared reader (the documents upload route declares about 14 MB, the encoded size of its 10 MB file limit). A test on each side of 256 KB pins it. `Web/Api.cls` is a shared file: append blocks only.
- **Timeboxed and sized items (11.22).** The leaked resolved Orders incident in lane-a@rest is replayed in CI order on one warm stack for at most 60 minutes: a reproduction gets its fix, otherwise the entry returns to the ledger with what was tried. The TLS-proxy origin check (online-demo API POST behind a TLS-terminating proxy) and install.sh finding the right IRIS build image are each fixed here only if sized at 2 hours or less; otherwise returned to the ledger with the size.
- **CI evidence (11.22).** A browser unit that fails in CI uploads its Playwright test-results (error-context.md, traces) as a short-retention artifact holding no secret except the CI dummy key and token.
- **`/state` after sign-in (11.22).** Investigate the occurrences against held CSP sessions and licence units (CI's Community licence, the demo's 8 units); record the finding, fix here only if small.
- **Request fixture bound (11.22).** The web/e2e request fixture's waits fail on a bound of their own, through an append-only edit or a shared-support alternative to `web/e2e/sign-in/helpers.ts` (that file is on Epic 40's open path); otherwise this item waits for Epic 40's merge.
- **Shared harness rules (from 11.21, still binding).** Route callbacks are removed at test end through one shared mechanism (`page.unrouteAll({ behavior: 'ignoreErrors' })`); helper waits carry bounds in the shared helpers or shared Playwright configuration, never per-spec copies, bounded by the smaller of their own bound and the test's remaining time less a cleanup reserve of about 60 s, failing with a message naming the step. A new bound is pinned by a test with the mutation shown.
- **Release-wide rules.** No step pushes an image or signs in to a registry; no step prints an environment value (`docker compose config` only with `--quiet`, `docker inspect` only with `--format`). Records describe machines only by OS, CPU architecture and memory. Nothing outward happens without the author's word.
- Every command fits one 10-minute call; prefer warm mode and split long runs.

## Technical Decisions

- **Test layout.** Playwright 1.64.x. Specs live under `web/e2e/` (demo-path specs one per UJ-1 step under `web/e2e/demo-path/`; the accessibility floor's specs under `web/e2e/floor/` run only in their own unit `live:floor`), online-demo specs under `web/e2e-online/`. A turned-on test that must never skip again carries `@floor`; an unbuilt part is a `notBuilt(title, 'N.M')` call.
- **API errors.** REST errors are `{"error": {"code": "...", "message": "..."}}` in plain English with snake_case codes; a new code (such as `body_too_large`) follows that shape.
- **Lanes (AD-29).** `web/` (e2e specs, runner configuration, fixtures), `docker/` and `docker/tests/`, `.github/workflows/ci.yml` and the rest of `ci/` are Lane B; `release/`, the release records and the `docs/` security overview are Lane A. Epic 11 may change either lane's files; the orchestrator serializes it against any epic whose files overlap. Shared files (`Web.Api` among them) take one appended entry per story.
- **Candidate model.** A candidate is identified by version and commit SHA on `release/<version>-rc<n>`, never changed after the cut; a failed gate means a fix on the integration branch and a new `rc<n+1>`. Rehearsal candidates are `rehearsal/<v>-rc<n>`, local bare remote only, never pushed to origin. After 1.0.0 a release goes out daily with whatever has merged (minor bump for a feature, patch for fixes only), each on the owner's word.
- **Records.** `release/records/<version>/rc<n>.md` on the integration branch holds the SHA, each gate's result, the hands-on pass and hands-on time; stage only `rc<n>.md` by explicit pathspec, never the folder (the draft notes beside it are never published).
- **Release script file mode.** `release.sh` and `lib-release.sh` keep `umask 077`; anything handed to a container whose user differs is opened with `chmod -R a+rX`.

## Cross-Story Dependencies

- 11.22's request-fixture item depends on Epic 40 (which has `web/e2e/sign-in/helpers.ts` open) unless done append-only or through shared support; its body-size bound must leave room for the documents upload route's larger declared bound (Epic 34).
- 11.22 is independent of the part 2 release stories and merges first, shipping in the next daily release.
- Part 2 stories add steps to 11.5's `release.sh`: 11.14's rehearsal gate calls `rehearse.sh run` once per phase with `OCUTALON_RUN_TAG` (exit 4 until the last phase); 11.16 carries the fork-PR demo-path guard and the tracked web bundle's dirty-tree issue; 11.18 needs 11.14 to 11.16.
- Epic 38 runs the real-key and hands-on passes (38.1 to 38.3) through this sequence.
