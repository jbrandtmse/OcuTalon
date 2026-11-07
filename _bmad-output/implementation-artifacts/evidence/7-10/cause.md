# Story 7.10 (DW-840): why TestPastExpiryCannotStart went red once in CI - evidence (lead, Task 0, 2026-11-07)

## The CI failure
`OcuTalon.Test.Fix.Refused` `TestPastExpiryCannotStart` failed once (`shards-2`, `lane-a@rest`, run 42314928349, OCT-epic7
`079513571ebef52a4aad9294644e6d5fdfe57120`) at the pin "the incident is resolved" (`src/ocutalon/cls/OcuTalon/Test/Fix/Refused.cls`, line 100 before this fix, 102 after it).
The class took 34.03 s against about 3.6 s green: the 30 s `WAITRUN` wait (`Test/Watch/Case.cls`, `WaitIncidentState` polling every 0.5 s) ran out.

## The cause
The test's fixture incident came from `Case.Fixture` with its default `LastAt` of 2026-10-25T08:00:05Z, far more than
`IncidentManager.QUIETSECONDS` (900 s, `Watch/IncidentManager.cls:115`) before now. Every heartbeat Tick runs the quiet sweep first
(`Checks/Process.cls`, class doc 3-8 and `Quiet` 419-431: every incident not `closed` whose `LastAt` is more than `QUIETSECONDS` old)
and sends `closeQuiet` for it. While the incident is `fixing` the table refuses that. Once the final FixResult moves it to `resolved`,
`resolved + closeQuiet -> closed` is accepted (`Watch/Transitions.cls:15-19`, AD-15). A sweep landing between that move and the test's
first poll leaves `WaitIncidentState` seeing `closed` until it times out. `Settle.Quiet` (`Watch/Settle.cls:83-89`) is `(now - last) > seconds`.

## Measurement (lead, warm lane B stack; harness untracked)
Load harness: an untracked subclass of `Refused` with two jobs sending `closeQuiet` back to back for every unclosed incident.
- Old code: red 2 of 11 runs, "FAIL TestPastExpiryCannotStart: the incident is resolved", class 38-43 s.
- Control: an old-shape copy of the test recorded `resolved@0.08 s, closed@0.33 s` in every run.
- With `FirstAt` and `LastAt` set to now in the fixture: 20 of 20 pass under the same load.

## Why the product is right
The quiet sweep (AD-18) and `resolved + closeQuiet -> closed` (AD-15's table) are the rule: a resolved incident whose last failure is
older than 15 minutes closes on the next heartbeat. Only the fixture's stale 2026-10-25 `LastAt` made a seconds-old incident look 13 days quiet.
`IncidentManager` re-checks `Settle.Quiet` on `closeQuiet` and answers `not_quiet` for a fresh `LastAt`.

## The fix
Test-only, in `TestPastExpiryCannotStart` alone: `FirstAt` and `LastAt` are now beside `NoticedAt`, following `Test/Fix/DryRun.cls:94`, which sets `LastAt` the same way (quiet is judged on `LastAt` alone; `FirstAt` is set with it so it is never later than `LastAt`).
Every pin, wait call and timeout is unchanged; `Test/Watch/Case.cls` and the product are untouched.

## Other callers checked
The other `WaitIncidentState(..., "resolved")` callers (`Test/Fix/{Waits,Results,Scale,Execute,Restart,Partial,Stopped,Runs}.cls`) wait on real raised
incidents with fresh `LastAt`; `Test/Watch/Closing.cls` uses `Test.Data.Fixture.Incident` (LastAt 2030, never quiet). The `Waits.cls` incident F and
`Refused.TestNoApprovedRowNoRun` fixtures are `open` and not noticed, a state with no `closeQuiet` row in the transition table (an `open`, noticed incident
closes on `closeQuiet` only when demo mode is off). The other classes that call `Fixture` with its default `LastAt` (`Test/Fix/{DryRun,Recheck}.cls`,
`Test/Watch/{Evidence,GoodMessages,Payload}.cls`) never wait for a state. Only `TestPastExpiryCannotStart` carried the race.
