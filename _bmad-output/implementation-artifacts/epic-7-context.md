# Epic 7 Context: Approve the fix and the orders go through

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic is the climax of the two-minute demo. For a data-format cause, OcuTalon proposes repair and resend with a dry run that changes nothing. It raises one approval request fixed to exact targets, and later failures get their own dry run and request in the same incident. After approval it re-checks each target, resends repaired copies, leaves the originals untouched and reports how many went through ("All 50 orders went through."), for at least 500 messages. It never retries a failed resend, or acts on a changed target, without a new approval. The last piece makes a resend cut short by a restart say how far it got, so no approved request is left hanging. This turns Epic 5's diagnosed incident into an approved fix you can audit, moving the incident through awaiting approval, fixing and resolved.

## Stories

- Story 7.1: Repair and resend proposes a dry run that changes nothing (done)
- Story 7.2: The incident notice carries the dry run and one approval request (done)
- Story 7.6: Later failures in the same incident get their own dry run and approval request (done)
- Story 7.3: Approved repairs are re-checked and resent (done)
- Story 7.4: OcuTalon reports how many orders went through (done)
- Story 7.5: A resend cut short by a restart says how far it got (next, last)

## Requirements & Constraints

- **A run cut short by a restart is never resumed.** A `FixRun` still running when IRIS stopped is marked interrupted at the next start. Its approval row closes through `FinishExecution(ref, "interrupted")`, which leaves it `failed`. The user gets the interrupted result with the count that went through, and the rest needs a new approval.
- **Exactly one final `FixResult` per run.** It carries `Final` 1 and `Interrupted` set, and it is never sent for a run already reported. Each request's result is its own: with two requests in one incident, neither run's copies count in the other's (U-140).
- **The incident moves by AD-15's table.** A final `FixResult` (interrupted included) with no approved request waiting moves `fixing` to `resolved`, or to `awaiting_approval` if a later request is pending. When an approved request is waiting, the incident stays `fixing` and the earliest waiting request gets the next `Execute`. One fix runs at a time per incident.
- **Every approved request ends.** No request may stay `executing` with its incident `fixing` and no result (DW-380's principle). DW-395 sharpens this for 7.5: a waiter that stops on a quiesce or terminate while the production keeps running must not leave its runs hanging. Either the Sweep or a waiter restart ends them.
- **No model, and nothing resent behind the user's back.** The CI mock receives no request during any of this. Reconcile and Sweep resend nothing.
- **Catalog criterion.** Three P16 keys must exist in `OcuTalon.Msg.Catalog.Watch` with their slots and render through the same `*Out` path as the other results: `result.failedAndSkipped`, `result.stillResending` and `result.interrupted`. Their wording was accepted on October 17.
- **Audit.** Write only through `OcuTalon.Bridge.Audit.Record("Action", data)`, with exactly `irisUser`, `sessionRef`, `channel`, `action`, `target`, `result`, `counts` and `approvalRef`. Never include a key, token, password or Telegram identity. 7.4 writes one entry for every run that ends, including couldn't-start and nothing-resent runs, so the page's "Recorded in the IRIS audit log." holds under every result band.
- **Tests.** The Reconcile criterion's test leaves a `FixRun` row running, then runs the `Reconcile` step. The exactly-once criterion is checked by sending fixture `Tick`s to `Checks`.

## Technical Decisions

- **Paths to `IncidentManager`.** The answer path is `AnswersIn` → `AnswerOps` → `Approval.Answer` → `ApprovalHold` → `IncidentManager` → `FixExecutor` → `IncidentManager` → `Notify`. A final `FixResult` that comes after a restart, or after `FixExecutor`'s wait, takes a different path: on each heartbeat `Tick`, `Checks` calls `OcuTalon.Fix.Run.Sweep()` (a new class) and sends each `FixResult` it returns to `IncidentManager`. The dependency rule allows exactly this one call from `Checks` into Fix.
- **Restarts.**
  - `Install.Registry`'s order runs the `Reconcile` step right after the `Production` step, so the production, `FixExecutor` included, is already running when the areas reconcile.
  - `CallAreas("Reconcile")` calls every `Install.Step.<Name>` area sorted by name. `Approvals` re-arms pending holds; executing rows are Fix's.
  - Fix's `Reconcile()` is new, in `Install.Step.Fix`. That class sits outside the registry's order and today only declares `Grants()`.
  - A crash between a resend and its registration loses that one copy id.
- **Messages.** `Fix.Msg.FixResult` has `ApprovalRef`, `IncidentRef`, `Final`, `Total`, `Resent`, `Completed`, `FailedAgain`, `Skipped`, `Interrupted` and `Reason`. No Fix message gets new properties. Items are addressed by name.
- **`IncidentManager`** is the only writer of `Incident` and `FailureGroup`, and the only publisher of `incident` events (after commit, each payload the full current view).
  - It treats `Final` or `Interrupted` as finished. It accepts a result only for its own request (`Owns`) and drops any other. It does not check who sent the result.
  - For an accepted result it sends one `result` notification per recipient, carrying `ApprovalRef` and `IncidentRef`, so the chat and the phone edit their message in place.
- **Result texts (`Notice.ResultKey`/`ResultSlots`).** The first match wins: row `executing` → `result.stillResending`, then `Interrupted` > 0 → `result.interrupted`, with `remaining` = `Total` − `Completed`. So the approval row must be closed before the interrupted `FixResult` reaches `IncidentManager`. The page picks its key by the same rule from the payload's `Requests[].State` and `Result`.
- **`Data.FixRun` after 7.4.**
  - Properties: `ApprovalRef`, `IncidentRef`, `StartedAt`, `Copies` (header ids in resend order, with `CopiesIndex`), `ResentAt` (the last registration; the 60 s run from it), `EndedAt`, then `Total`, `Resent`, `Completed`, `FailedAgain`, `Skipped`, `Interrupted` and `Reason`.
  - `EndedAt` set means the run has a final result. `ResentAt` set with `EndedAt` empty means the run is waiting or was given up on.
  - `OfRequest` uses object access only (it serves `/state`). `CopyOf` uses SQL, for `IncidentManager.Record`, which drops a registered copy's failure.
  - The class doc names `FixExecutor` as the only writer of the end fields, and 7.4 kept `FixRun` to one writer (AD-33). 7.5's spec must say who writes `Interrupted` and the end for `Reconcile` and `Sweep`.
  - Stored properties are append-only, every persistent class commits its `Storage` block, and a new property needs its Lane A entry in `Test/Data/Tables.cls`.
- **`FixExecutor` after 7.4.**
  - PoolSize 2. One waiting job at a time holds `WAITLOCK` and finishes every waiting run (`Waiting()` lists the runs with `ResentAt` set and no `EndedAt`) in 0.5 s passes, for `WAITSECONDS` 60 from each run's `ResentAt`. Copy states: `Completed` is done; `Error`, `Aborted`, `Discarded` and `Suspended` count as failed again; a copy it can't read counts as still running.
  - Finishing a run happens in this order: store the counts and `EndedAt`, call `FinishExecution`, write the `Action` entry, then send the `FixResult` in the incident's trace session (`Report` sets `%SessionId` to the incident's `TraceHeaderId` and `%SuperSession` to its `TraceRef`).
  - A run that can't start ends `failed` with `NOTALLOWED`, `UNUSABLE`, `NOREAD` or `NOSTART` ("OcuTalon couldn't start the resend").
  - When a run's time is up, the waiter drops it with one `LOGWAIT` warning and never looks at it again.
- **Runs 7.4 leaves `executing` for 7.5's Sweep or Reconcile:**
  - a run whose `ResentAt` save failed, which is never waited for;
  - runs left when the waiter stopped on an error or on a quiesce or terminate request while IRIS kept running (DW-395);
  - a run whose last copy finishes in the final 0.5 s of the wait;
  - a row that a failed `FinishExecution` left `executing`.

  On disk these runs look like Story 30.5's still-running runs: `ResentAt` set, `EndedAt` empty, row `executing`. Sweep's still-running branch and the in-progress `FixResult` (`Final` 0) are 30.5's.
- **`Checks` (Lane A's).**
  - `Checks.Process` keeps PoolSize 1. On each `Tick` it first runs its quiet sweep: `closeQuiet` sent synchronously to `IncidentManager` (`SendQuiet`, at most `QUIETWAIT`), with the owner's `TraceRef` as `%SuperSession`. A failed send logs one `LOGQUIET` warning and the loop goes on. Then it runs the due checks. Each part sits in its own Try/Catch.
  - Its private method `Sweep` is already taken by the quiet sweep.
- **The heartbeat (Epic 8's, merged; read only).**
  - The Task Manager task `Schedule.HeartbeatTask` runs every minute (`RescheduleOnStart` 1). Each run makes `HeartbeatIn` send one `Tick` to `Checks` without waiting for it. After downtime it sends one `Tick` with `CatchUp` 1, never one per missed minute.
  - Real `Tick`s reach `Checks` on every running stack, so a test's fixture `Tick`s can race them (DW-300 hit this with check rows). The exactly-once assertion must hold anyway.
- **Tests and the mock.**
  - `%UnitTest` classes go under `OcuTalon.Test.<Area>` and run on throwaways.
  - The mock logs every request to `/opt/ocutalon/mock-log/requests.jsonl`, which is the evidence for "no model request". A test must fail when that log is missing.
  - For failed orders, call `Partner.Send(count, dateFormat, traceRef, orderDate)` in OCUORDERS. Take OCUORDERS snapshots only after `Case.WaitSettled`.
  - Read audit entries by `UTCTimeStamp` range, polling with a timeout, because the indexes lag up to 60 s.
  - Times convert only through `OcuTalon.Data.Time` (`Bridge.Time` in the bridge).

## UX & Interaction Patterns

- **Restart text:** "The resend stopped when OcuTalon restarted: 30 of 50 orders went through. The other 20 need a new approval." When `remaining` = 1, the last sentence reads "The other one needs a new approval."
- **Voice.** Numbers first. The phone and Telegram say "becomes", not arrows. New public wording is a veto-window item.
- **On the page (Epic 6's, built).** Each request card shows its own answered status and a result band rendered from the payload, followed by "Recorded in the IRIS audit log."

## Cross-Story Dependencies

- **Built by 7.4, for 7.5 to consume:**
  - production code: the `FixRun` end fields and `CopiesIndex`, the waiter, `FixRun.OfRequest`/`CopyOf`, the `Action` entry, each request's `Result` in `Live.Payload.Incident.FromRow` (events and `/state`), and `NOSTART`;
  - tests: `Test.Fix.{Results,Partial,Waits,Scale}` beside 7.3's `Test.Fix.{Executor,ExecutorProbe,Runs,Execute,Refused}`;
  - `Case` helpers: `Runs` (with each run's stored result), `AskDryRun`, `Posts`, `Joined`, `Originals`, `FixResultsOf`, `RunOf`, `WaitIncidentState`, `WaitSettled`, `SendExecute`;
  - `Test.Fix.Later` (two requests in one incident on a real production).
- **Checks tests (Story 5.6).** `Test.Checks.Heartbeat` sends a real `Tick` through an adapterless service, in the production, fresh. `Test.Checks.Runs` and `Test.Checks.Probe` call a shadow `Checks` with fixture rows.
- **Catalog tests.** `Test.Msg.Catalog` belongs to Epic 16 beyond its shared entries. `Test.Watch.NoticeText` is Lane A's.
- **Veto window.** 7.4's spec-gate items (inbox U-146 to U-148) still stand: the nine `FixRun` properties, PoolSize 2 with the one waiter, and the `NOSTART` and fail-reason wording.
- **Open ledger items.**
  - Story 7.5's own: DW-395 (above).
  - Escalated for the decision sheet, so build nothing for them:
    - DW-368: a stopped production, or a resend that errs partway, renders as `result.skipped`'s "had changed since the dry run".
    - DW-384: an approved row past its `ExpiresAt` is refused silently.
  - DW-365 (`decision-pending`, owner): a later request reuses the first `fixSummary`. Don't change it ad hoc.
  - DW-345 (wontfix-theoretical): an unanswered dry run has no sweep. 7.5's Sweep covers `FixRun`s only.
  - DW-328: Fix's references into Watch stay as they are.
- **Contended paths** (ask the orchestrator before editing):
  - Epic 8 and Epic 10 paths are merged and read-only except shared entries: `Schedule/**`, `HeartbeatIn`, `Msg/Tick.cls`, the install script, the README, pairing, and `ci/iris.sh`.
  - Epic 9 (live): `Eval/**`, `Test/Eval/**`, `eval/**` and `.github/workflows/lane-a.yml`.
  - Epic 16 (live):
    - `Web/Public/**`, `Web/SessionEvents.cls` and the other web paths;
    - `Data/{Ownership,Session,AddressCounter,Setting}.cls`;
    - `Core/{BridgeSink,SessionOps,StatusMonitor,Allowance}*.cls`;
    - `Test/{Web,Data,Msg}/**` beyond the shared entries.
  - Waiting: Epic 15 has every `Install/**` file except `Install/Step/Fix.cls`. Epic 13 has `BridgeExample/**`, its `bridge-example-*` scenarios and `Test/Install/Production.cls`, where Lane A changes only its `FixExecutor` row.
  - Lane A's own:
    - `Fix/**`, `Test/Fix/**`, `src/bridge/**`, `Watch/**`, `Checks/**`, `Tools/**`;
    - `Msg/Catalog/Watch.cls`, `Test/{Watch,Bridge,Checks}/**`, `Install/Step/Fix.cls`;
    - the Lane A Data tables (`Incident`, `FailureGroup`, `FixRun`, `Bridge.Data.*`) and the lane-a entry in `ci/units.sh`.
- **Later epics.**
  - Story 30.5: the mixed and still-running results, and Sweep's still-running branch.
  - Epic 11: turns the demo path on end to end.
  - Stories 9.5, 12.6 and 29.4: wait for Epic 7 to merge.
