# Epic 9 Context: Quality is measured: the evaluation set

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Measure OcuTalon's quality instead of assuming it. A recorded evaluation set in `eval/` holds item cases for all four outcomes, injection cases, all-clear cases, a run-a-command case and recorded incidents taken from real IRIS failures, the demo's date-format incident among them. Each run sends the cases through the product's own path, reaching nobody and changing nothing. It scores decisions and causes and records each decision's cost and the largest request. The set runs against the CI mock on every push and on Claude Haiku 5.5 for each release candidate, where the set and the 10-run demo-incident gate decide whether a release ships. Stories 9.1 to 9.10 are done. Epic 9 is re-opened under SC-5 for one fix-forward, Story 9.11, for the 1.0.4 release (Sunday 2026-11-08). On the 1.0.3 rc1 run, the 10th and 11th incident cases (`returns-negative-weight`, `shipments-epoch-time`) timed out at about 60.1 s. They had spent their diagnosis timer queued behind earlier cases, so the cause score measured the queue, not the diagnosis.

## Stories

- Story 9.1: Evaluation cases run through the product path and reach nobody (done)
- Story 9.2: Each run scores decisions and causes and records cost and size (done)
- Story 9.3: Decision cases cover every outcome, two injections, the all-clear and a command request (done)
- Story 9.7: Turn cases measure the all-clear, the command reply and a stop-watching injection (done)
- Story 9.8: A stop-watching injection leaves the watch unchanged (done)
- Story 9.4: Ten incidents are recorded from real failures (done)
- Story 9.9: The other nine incidents come from real failures in a test feed (done)
- Story 9.6: Incident cases are diagnosed through IncidentManager and reach nobody (done)
- Story 9.5: Release candidates pass the evaluation and the demo incident gate (done)
- Story 9.10: The release-candidate run proves the key leaks nowhere and gates the maximum decision cost (done)
- Story 9.11: The evaluation paces its incident cases so none waits out its timer in a queue (backlog, next; carries DW-878)

## Requirements & Constraints

**Story 9.11: what must hold**
- `EvalIn` (`OcuTalon.Eval.In`) still sends the turn cases first. After that, it sends each incident case after the first only once the previous incident case's `OcuTalon.Eval.Data.CaseResult` row is completed. That takes about 70 s per case on Haiku 5.5. At most one incident case is being diagnosed at any time.
- The pacing depends on the previous case's result, never on `DiagnosisAgent`'s pool size, so it still holds when that runner has two jobs.
- The wait for a row is bounded, so a result that never arrives can't hang the run.
  - The bound is at least as long as a diagnosis can take under `Decide`'s timers. The first attempt's timer defaults to 60 s, and a whole decision, any second-model retry included, stays at or under 110 s.
  - The spec must say what `EvalIn` does when the bound is reached.
- A late `CaseResult` never lets two incident cases overlap: the next case is not sent before that row is completed.
- **Unchanged:**
  - no case's expectation, no score, no timer, no timeout and no existing wait;
  - `EvalIn` stays disabled in the product (the judges' compose file and an IPM install).
- **Frozen until the v1.0.4 merge-back, not edited:** `eval/run.sh`, the IPM artifact and the check scripts.
- **Out of scope:** DW-879, the product's own diagnosis queue (Story 5.14).
- **Tests:**
  - `OcuTalon.Test.Eval.In`, plus any other test the change trips (the spec names each), proves the sending order (turn cases first, then incident cases one at a time).
  - It also proves that a late `CaseResult` doesn't let two incident cases overlap.
  - Each test needs a demonstrated mutation (Rule 19).
  - Update the existing order pins to the new order. Don't remove them.

**Standing rules of the set (all stories)**
- **Isolation.** A run creates no `Notification`, `Delivery`, live event, dry run, approval request, or incident owned by a session or `instance`. Its `Usage` rows carry owner `eval` and count toward no session total and no daily cost cap.
- **CON-3.**
  - Only `OCUTALON_EVAL=1`, which Lane A's evaluation job sets, enables `EvalIn`.
  - `EnsLib.Testing.Service` is never used, and the testing switch stays off.
  - The test feed is installed only in the throwaway stack.
- **Scoring.**
  - An item is right when its outcome matches. An incident is right when its cause category and element at fault both match. A fallback is never right.
  - Targets: SM-1 needs at least 90% of items right and SM-2 at least 80% of incidents, plus all 10 runs of the demo incident. NFR-4 is gated on the maximum item-decision cost (under $0.001). NFR-3 caps a request at 100,000 input tokens.
- **Release candidates.** A candidate below any target runs twice more and passes on 2 of 3. Otherwise it is blocked unless the author overrides, with the reason in the run's result file.
- **Push runs.** Runs on the CI mock record scores but never gate on them. The job fails only on problems.

## Technical Decisions

- **The incident path, as built.**
  1. `EvalIn` mints the incident's `Ref` and opens the case's `CaseResult` row with that `Ref` as `ItemId`.
  2. It sends `IncidentManager` an `OcuTalon.Eval.Msg.IncidentCase`: `IncidentRef`, `SourceItemId` (the case folder name) and `Snapshot` (the reader snapshot's JSON).
  3. `IncidentManager`'s eval branch builds the pack with `EvidencePack.Build` and sends `Decide` the same `diagnose` request as the live path, with owner `eval`.
  4. It sends `EvalSink` exactly one `ItemDecision`, which completes the row by matching `ItemId`.
  5. Every failure on this path still ends the case as a fallback `ItemDecision`.
- **Why cases queue.**
  - `EvalIn` sends its cases asynchronously, all at once.
  - `Decide` starts the diagnosis timer when it sends the request to the runner (`Decide.cls` about lines 339-342), not when the runner starts work.
  - `DiagnosisAgent` has PoolSize 1, and pool size is the runner's concurrency cap. Later cases therefore spend their timer waiting behind earlier ones.
  - The DW-878 ledger points at the async sends in `Eval/In.cls` (about lines 8-9 and 480-483).
- **Leave the timers alone.** Any timer change goes through `OcuTalon.Bridge.Timeouts.Derive`. Raising `TimerSeconds` was ruled out for DW-879. The fix belongs in `EvalIn`'s sending, not in the bridge, the runner or the production class.
- **AD-5.** Only `ApprovalHold` and `ReminderTimer` hold long timers. Every other process handles one message and ends, keeping its state in rows. A wait in `EvalIn` must be bounded and read the `CaseResult` row as its truth.
- **Footprint (runner B, Lane A).**
  - Epic 9 owns `OcuTalon.Eval.*`, `OcuTalon.Test.Eval.*` and `eval/**` (minus the frozen files above), plus new mock scenario files under `ci/mock/scenarios/A/`.
  - Lane B's files are read-only, and the signature oracle pins cross-lane API signatures.
  - A new persistent class needs a `DEFAULTGLOBAL` registered in `src/short-names.tsv` and its storage block committed. Storage is append-only.
- **CI.**
  - The evaluation job is in `.github/workflows/lane-a.yml`.
  - `Test.Eval.*` runs in the `shards-2` group, and the IRIS groups run close to REL-4's 35-minute budget, so keep new tests short.
  - On the mock, the demo incident `orders-date-format` ends decided. The other incidents end as fallback `invalid`, and the job requires every incident to run and the demo to be decided.

## Cross-Story Dependencies

- **Story 5.14 (DW-879), the same 1.0.4 burn-down, scheduled before this story.**
  - It changes `DiagnosisAgent` alone to PoolSize 2 (`IncidentManager` and `Decide` stay at 1).
  - The runner will skip a request whose `Decision` row already exists.
  - It owns the pins in `Test/Agent/Runners.cls` and `Test/Install/Production.cls`.
  - Story 9.11 must not touch the pool size, and it must work with either pool size.
- **Release path.** The 1.0.4 release runs this set on its release candidate. Story 11.4's generator reads the result file that Story 9.5's release-candidate mode writes. Its format and `eval/run.sh` are unchanged here.
- **Later growth.** Story 17.7's digest cases and step 5's setting-change incidents add cases through the same `EvalIn` path. Pacing applies to whatever incident cases the set holds.

Compiler notes:
- The criteria don't settle the behaviour at the bound. If the bound is reached, the next incident case still must not overlap a case whose row could complete late. The spec has to reconcile the bounded wait with the no-overlap criterion.
- The criteria fix only two parts of the order: turn cases first, then the incident cases one at a time. They say nothing about where item cases go.
