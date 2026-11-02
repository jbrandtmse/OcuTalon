# Epic 11 Context: Release 1 ships: the demo path end to end, upgrade in place and a scripted release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 11 is release 1's merge point: the web demo path passes end to end in the REL-2 test, upgrades keep every record, the clean-machine rehearsal times the demo path, and one scripted sequence (`release/release.sh`) cuts a candidate. On 2026-11-02 the owner trimmed it: part 1 (this merge) ends with one fix-forward, Story 11.19, which stops seeded check rows from being run by the real heartbeat (DW-349, which reds most browser runs on every epic). The remaining release-sequence stories (gates, hands-on gate, outward steps, update hook) go to Epic 11 part 2, after rc1.

## Stories

- Stories 11.0-11.13, 11.2-11.5 and 11.17: demo path, failure paths, upgrade harness, rehearsal and repeats, checklist, notes, `release.sh`, IPM artifact (done)
- Story 11.14: The release sequence runs every gate on the pushed candidate (SPLIT to part 2, backlog)
- Story 11.15: The hands-on gate stops the sequence, and its resume command waits for a pass or a carry-over (SPLIT to part 2, backlog)
- Story 11.16: The sequence asks before each outward step after the gates (SPLIT to part 2, backlog)
- Story 11.18: The update hook updates the online demo, and a rehearsal candidate proves the sequence (SPLIT to part 2, backlog)
- Story 11.19: Seeded check rows stay out of the heartbeat's way unless a case asks for the real watch (next, backlog)

## Requirements & Constraints

- **Not due by default (11.19).** A check row seeded through the e2e helper without asking for the real watch must be stored with its next due time about an hour ahead, so no heartbeat tick (the minute task or a fixture's HeartbeatTask) runs it and overwrites its seeded last run, result or finding while a spec asserts them.
- **Explicit opt-in.** A case that wants the real watch passes an empty next due time (`""`), and every spec that relies on the real watch says so.
- **Every seeding path, no spec edits.** banners, rail, answers/close-loop, floor/focus, floor/guide, trace/links, session (two direct `Fixture.Check` calls in its own `irisScript`, not via `seedCheck`), `demo-path/04-incident` and any other caller get the default on the merged tree without their specs changing; `banners.spec.ts` changes only if the fix truly needs it.
- **One web-side pin.** One test pins the default on the web side, as `Test.Data.FixtureDefaults` pins it on the IRIS side.
- Every command fits one 10-minute call; prefer warm mode and split long runs.

## Technical Decisions

- **The IRIS default exists (Story 11.1).** `OcuTalon.Test.Data.Fixture.Check(sessionRef, namespace="ZZNS", production="Zz.Production", fields)` sets `NextDueAt` to now plus `Parameter CHECKAHEAD = 3600`; any `NextDueAt` field, even `""` (due at once), replaces it. It reached the feature branch only through this epic's merge, so other epics' CI still reds until part 1 lands.
- **The IRIS pin.** `OcuTalon.Test.Data.FixtureDefaults.TestCheckIsNotDue`: no field gives due `CHECKAHEAD` s ahead (±120 s); `{"NextDueAt": ""}` gives an empty `NextDueAt`. It cleans its own rows with `Fixture.Clean(refs)`.
- **The web helper.** `web/e2e/support/iris.ts` `seedCheck(user, CheckFields)` calls `Fixture.Check` through `irisScript`; `CheckFields.nextDueAt` (ISO UTC to the second) is passed as `NextDueAt` only when set, because `properties()` drops `undefined` (an empty string is kept). So the default today comes from IRIS, not from the helper; the web pin must prove an unset `nextDueAt` lands an hour ahead and `""` lands due.
- **Callers today.** `seedCheck` in answers/close-loop, banners (4), floor/focus, floor/guide, rail (4), trace/links (2), `support/floor.ts` `seedFullPage` (floor/keyboard, scan, words), and `heartbeat/heartbeat.spec.ts`, which already passes an explicit `nextDueAt` an hour ahead (Story 8.2's fix). Many IRIS unit tests also call `Fixture.Check` (e.g. `Test.Core.*`, `Test.Demo.*`); DW-349 counted one, `GuideRefresh.TestHeldLock`, whose red came from a tick's check event.
- **Why the heartbeat matters (AD-15).** The heartbeat's `Checks` run (since Story 5.6) runs every row of kind production whose `NextDueAt` is empty or within `DUESLACKSECONDS` of the tick (`Checks.Process.Due`), writes its last run, result, finding and header id, publishes a check event on the session, and sets `NextDueAt` to the tick plus `INTERVALSECONDS`.
- **Lanes (AD-29).** Do not edit `README.md`, `docker/Dockerfile`, `.gitignore`, `src/module.xml`, `release/ipm*`, `release/standalone-bridge.sh` or `.github/workflows/*`; `ci/units.sh` changes only by plain union append.

## Cross-Story Dependencies

- 11.19 builds on 11.1's `CHECKAHEAD` default and lands with Epic 11 part 1, so every epic's browser CI gets it at the merge.
- Part 2 (11.14 to 11.16, 11.18) adds steps to 11.5's `release.sh`; DW-548 (the rehearsal gate calls `rehearse.sh run` once per phase with `OCUTALON_RUN_TAG`, exit 4 until the last phase) and DW-27 go with them. Epic 38 runs the real 1.0.0 cut; Stories 13.3, 14.1 and 15.3 need Epic 11 merged. Epics 39-41 (on the merged-in feature branch) are other epics.
