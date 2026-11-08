# Epic 7 Context: Approve the fix and the orders go through

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic is the climax of the two-minute demo. For a data-format cause, OcuTalon proposes repair and resend with a dry run that changes nothing. It raises one approval request fixed to exact targets, and later failures in the same incident get their own dry run and request. After approval it re-checks each target, resends repaired copies, leaves the originals untouched and reports how many went through, for at least 500 messages. It never retries without a new approval. Stories 7.1 to 7.10 are built. The epic is re-opened once more for a single test-only story, 7.11 (DW-675). The "nothing changed" snapshot tests go red when IRIS's alarm job starts a schedule call inside the dry-run window, which writes a new header from `Ens.ScheduleService` to `Ens.ScheduleHandler`. That flake is now red on two branches and blocks merges for Epic 17 and Story 32.6. After 7.11 a red snapshot diff should mean only that the fix changed something.

## Stories

- Story 7.1: Repair and resend proposes a dry run that changes nothing (done)
- Story 7.2: The incident notice carries the dry run and one approval request (done)
- Story 7.6: Later failures in the same incident get their own dry run and approval request (done)
- Story 7.3: Approved repairs are re-checked and resent (done)
- Story 7.4: OcuTalon reports how many orders went through (done)
- Story 7.5: A resend cut short by a restart says how far it got (done)
- Story 7.7: A date repair that could read either way names its evidence (done)
- Story 7.8: The web incident card shows the either-way date line too (done)
- Story 7.9: The dry run shows the fix leaves good messages unchanged (done)
- Story 7.10: The past-expiry refusal test is stable (DW-840) (done)
- Story 7.11: The dry-run snapshot excuses the alarm job's own schedule writes (DW-675) (next, last; backlog)

## Requirements & Constraints

- **What the flake is (7.11).**
  - A new OCUTALON header appeared during the dry-run window with source `Ens.ScheduleService` and target `Ens.ScheduleHandler`. These are `Ens.Alarm` jobs started off `Ens.ScheduleService.CallScheduleService()` when a timer's request header is missing. It is a schedule call that started inside the window, not a timer that was already running.
  - CI saw it in `OcuTalon.Test.Fix.DryRun` `TestFiftyOrdersChangeNothing` (Story 7.8's fresh check, header 564) and in `OcuTalon.Test.Watch.GoodMessages` `TestFewerThanTwentyGood` (OCT-epic17 321dcad7, twice; OCT-epic32 cf04f99a).
- **Exact scope of the excusal.**
  - `OcuTalon.Test.Fix.Snapshot.Diff` leaves out a new header only when its source is `Ens.ScheduleService` **and** its target is `Ens.ScheduleHandler`. Nothing else is excused.
  - A header from `Ens.ScheduleService` to any other target, a header from any other source to `Ens.ScheduleHandler`, and every header that counts today must still give a line. No existing excusal is widened.
- **Proof (Rule 19).**
  - Add a forced-condition test that plants such a header inside the window. Show the old code red on it, then run the fix 20 of 20 green.
  - Removing the new excusal must turn the pinning test red.
- **Keep the callers green.** The tests that use the snapshot must stay green on a fresh environment, run forward and reversed. These are `TestFewerThanTwentyGood`, `TestFiftyOrdersChangeNothing` and their siblings in `OcuTalon.Test.Fix` and `OcuTalon.Test.Watch.GoodMessages`.
- **Test-only.**
  - Change no product file.
  - Don't delete or weaken any pin, and don't raise a timeout to make a test pass.
  - Any change to public text needs a Planner ruling.
- **Release.** The story targets Sunday's 1.0.4. Nothing goes to `main` or `release/*` from this epic.
- **Running tests.**
  - Integration tests run only in throwaway stacks and CI, fresh, with demo mode on, through `Test.Watch.Case`.
  - Make one `iris_execute_tests` call per message, and pass the server and namespace on every IRIS call.
  - Each run must fit the 10-minute command cap: split long repeat runs, never raise the cap, and prefer warm mode.
- **Epic-wide.**
  - Use only the CI mock and its recorded replies, never a real model key or a real Telegram bot.
  - `live:demo-path` and the online-demo specs stay green, and no recorded eval expectation changes.

## Technical Decisions

- **The snapshot oracle.**
  - `OcuTalon.Test.Fix.Snapshot` is the shared read-only helper of every "nothing changed" test, from 7.1 on, and 7.3, 7.4, 7.9 and `Refused` reuse it.
  - `Diff` already excuses three things: headers in the test's allowed sessions, sessions started by a new `HeartbeatIn` header, and, in OCUTALON only, a timer that was already running before the snapshot together with its one wake-up from `Ens.Alarm`.
  - The new rule sits beside these. Update the class doc comment to name it.
- **Stack-free tests.** `OcuTalon.Test.Fix.SnapshotDiff` tests `Diff` on hand-made snapshots, with no production. It is the natural home for the planted-header pin and its negative cases (other target, other source).
- **Don't mix it up with `OcuTalon.Test.Checks.Snapshot`.** That class tests the heartbeat status snapshot (Epic 39), which is unrelated. Leave it alone.
- **Tests.** `%UnitTest` classes sit under `OcuTalon.Test.<Area>`. CI runs `lane-a`'s Fix area in `shards-2`, in its own compose project.
- **Pattern from earlier flake stories.** Follow 7.10 and 34.4:
  - Record the cause under `_bmad-output/implementation-artifacts/evidence/<story>/`.
  - Where a red can't be forced on a stack, use a stack-free repro.
  - The lead owns the repeat proof (old code red, fix 20 of 20) and records it with run IDs.

## Cross-Story Dependencies

- **Behaviour to keep.** 7.11 widens only the test oracle. Keep 7.1 to 7.10 behaving exactly as they do now.
- **Downstream.** Epic 17's and Story 32.6's merges wait on DW-675 being fixed.
- **Ledger.**
  - DW-675 is owned by 7.11.
  - DW-868 (`Case.Fixture`'s stale default `LastAt`, escalated) and DW-639 (a different flake class) stay out of scope.
  - DW-318, DW-655 and DW-653 remain open. Don't fix them in passing.
