# Epic 7 Context: Approve the fix and the orders go through

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic is the climax of the two-minute demo. For a data-format cause, OcuTalon proposes repair and resend with a dry run that changes nothing. It raises one approval request fixed to exact targets, and later failures in the same incident get their own dry run and request. After approval it re-checks each target, resends repaired copies, leaves the originals untouched and reports how many went through, for at least 500 messages. It never retries without a new approval. Stories 7.1 to 7.9 are built. The epic is re-opened once more for a single fix-forward story, 7.10. One test, `OcuTalon.Test.Fix.Refused` `TestPastExpiryCannotStart`, went red once in CI as a timing accident (DW-840). After 7.10 it should fail only when the product is wrong, so a red shard always means a real defect.

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
- Story 7.10: The past-expiry refusal test is stable (DW-840) (next, last; backlog)

## Requirements & Constraints

- **The flake (7.10).**
  - CI shard `shards-2` (`lane-a`, the Fix area among others) went red once on OCT-epic7 head 07951357, in 1 of 93 classes.
  - The failing assertion was "the incident is resolved", from the `WaitIncidentState` poll. The class took 34.03 s, where it normally takes about 4 s.
  - The same tree passed fresh on lane D in 8.99 s.
  - The ledger note says a second red on the same head is a real defect, not a flake.
- **Measure, then fix.**
  - Run the test under a repeat or load run to measure the cause and name it.
  - Show that the old code fails under that same run.
  - After the fix, make the same run 20 times. It must pass 20 of 20.
- **Forbidden fixes.**
  - Don't delete or weaken any pin (assertion).
  - Don't raise a timeout to make it pass.
- **Test-only.**
  - If the cause turns out to be in the product, stop and describe it before making any product change, so the Planner can rule on it.
  - Any change to public text needs a Planner ruling.
- **Timebox and release.**
  - The timebox is 90 minutes, under the Planner's voting-week tier (3)(a).
  - The story merges after the 1.0.3 cut. Nothing goes to `main` or `release/*`.
- **Running tests.**
  - Integration tests run only in throwaway stacks and CI, fresh, with demo mode on, through `Test.Watch.Case`.
  - Make one `iris_execute_tests` call per message, and pass the server and namespace on every IRIS call.
  - Each run must fit the 10-minute command cap: split long repeat runs, never raise the cap, and prefer warm mode.
- **Epic-wide.**
  - Use only the CI mock and its recorded replies, never a real model key or a real Telegram bot.
  - `live:demo-path` and the online-demo specs stay green, and no recorded eval expectation changes.

## Technical Decisions

- **What the test checks.**
  - An approved `repair_resend` request whose `ExpiresAt` has passed isn't refused outright. It ends as "could not start" (DW-384, U-161).
  - The real `FixExecutor` item receives an Execute by name from `SimMailboxIn`. It sends one final `FixResult` with reason `NOSTART`. The request ends `failed`, with one ended `FixRun` that holds no copy.
  - `IncidentManager` then resolves the incident and sends one `result.couldNotStart` notification.
  - The audit log holds one Action entry, and a snapshot of OCUORDERS shows no change.
- **Where the red sits.**
  - The red is the step where the incident becomes resolved. That happens asynchronously in `IncidentManager`, after the `FixResult` assertions.
  - Waits in `Test.Watch.Case` poll every 0.5 s up to `WAITRUN`, which is 30 s. The 34 s class time is consistent with that wait running out.
- **Fixing the fix flows.**
  - `FixExecutor` loads everything from the `ApprovalRequest` row alone (`FixKind`, `FixParameters`, `FixTargets`).
  - Producers never render text: `OcuTalon.Msg.Catalog.Render` does that.
  - 7.9 touched neither `Executor`, the incident transitions nor `Refused`.
- **Tests.** `%UnitTest` classes sit under `OcuTalon.Test.<Area>`. CI runs `lane-a`'s Fix area in `shards-2`, in its own compose project.
- **Pattern from an earlier flake story.** Story 34.4 (DW-825) is the model to follow:
  - Record the cause under `_bmad-output/implementation-artifacts/evidence/<story>/` (for example `cause.md`).
  - Where a red can't be forced deterministically, add a stack-free repro or probe.
  - The lead owns the repeat proof (old code red, fix 20 of 20) and records it with run IDs.

## Cross-Story Dependencies

- **Built on 7.3.** The past-expiry path is 7.3's refusal matrix ("Past expiry" row) and its `couldNotStart` result. Keep 7.3 to 7.9 behaving exactly as they do now.
- **Ledger.**
  - DW-840 is owned by 7.10.
  - DW-639, another flake class, is queued after DW-840 under the same tier-3 ruling. It stays out of scope.
  - DW-318, DW-655 and DW-653 remain open. Don't fix them in passing.
