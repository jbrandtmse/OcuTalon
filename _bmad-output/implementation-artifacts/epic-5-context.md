# Epic 5 Context: OcuTalon watches a production and explains what broke

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A user asks OcuTalon in plain words to watch a production. New failures are picked up within seconds and grouped by the settle rule into one incident. Each incident is diagnosed into a plain-English cause, the element at fault and a proposed fix, with its evidence, and moves through fixed states. OcuTalon never gives a false all-clear. Stories 5.1 to 5.13 are done. Epic 5 is re-opened under SC-5 for one fix-forward story, 5.14 (DW-879), for Sunday's 1.0.4. The problem: `Decide` starts a diagnosis's timer when it sends the request, and `DiagnosisAgent` runs one job. When several incidents arrive together, for example several online-demo visitors breaking the feed at once, the later diagnoses spend their timer in the queue and time out before the model is asked. Their timeout rows carry no Usage and an empty model, and the visitor gets the fallback notice with no fix. The Contest Planner chose option B plus skip-abandoned: a second DiagnosisAgent job, and runners that skip a request `Decide` has already concluded.

## Stories

- Story 5.1: Ask OcuTalon to watch a production, and to stop
- Story 5.2: New failures are picked up within seconds
- Story 5.3: Same-cause failures become one incident by the settle rule
- Story 5.4: The diagnosis explains the cause from the failed messages
- Story 5.5: An incident moves through its states and closes
- Story 5.6: The production watch runs on every heartbeat
- Story 5.7: Asked whether everything is fine, OcuTalon never gives a false all-clear
- Story 5.8: Each noticed incident says what broke, with its evidence behind Show details
- Story 5.9: Ask OcuTalon in the chat to dismiss an incident
- Story 5.10: Epic 5 burn-down
- Story 5.11: The demo guide's tests hold now that incidents are real
- Story 5.12: A correct diagnosis is never refused for an over-long evidence reference
- Story 5.13: Ask OcuTalon what happened earlier, and it tells you from its own records
- Story 5.14: Several incidents at once are each diagnosed inside their timer

## Requirements & Constraints

Story 5.14 is the only open story.

- **Two diagnosis jobs.** In `OcuTalon.Production`, the `DiagnosisAgent` item gets PoolSize 2. `IncidentManager`, `Decide`, `DiagnosisAgentRetry` and every other item keep their pool sizes. A runner's pool size is still its concurrency cap.
- **Pins.** Every pin on DiagnosisAgent's pool size reads 2: `OcuTalon.Test.Agent.Runners` (its pool check and its alive-jobs check) and the DiagnosisAgent row of `OcuTalon.Test.Install.Production`'s oracle. The other runners' pins still read 1. Any other test the change trips is updated and named in the spec.
- **Skip an abandoned request.** A request can reach an agent runner after `Decide` has already concluded its decision, so its `DecisionRef` already has an `OcuTalon.Bridge.Data.Decision` row (for example, its timer fired while it waited in the queue). The runner skips that request:
  - no model request, no tool call and no Usage row, and `Decide` records no new decision for it;
  - exactly one log line, naming the runner item and the `DecisionRef`, with no key, message body or model text.
- **Never skip a live or deliberate request.** A request whose `DecisionRef` has no row yet runs exactly as before. A request the bridge sends on purpose after a decision is recorded, such as the replay of an approved tool call, is never skipped. The spec names which request kinds the skip covers.
- **Tests:**
  - a stale request is skipped and a live one is not;
  - on the CI model mock with a reply delay, two diagnoses that `Decide` sends at nearly the same time run at once on the two jobs, and the second is answered well inside its timer. The spec's `## Verification` records the measured send and answer times of both diagnoses and the timer.
- **Unchanged:** `TimerSeconds` and every timeout. The timer still starts when `Decide` sends. No RetryItem is wired.
- **Footprint.** Touch only these: `Production.cls`'s DiagnosisAgent item, `OcuTalon.Bridge.Operation.AgentRunner`, `OcuTalon.Bridge.Adapter.Agent`, their tests, the pool-size pins and new mock scenario files.
- **CI.** CI is green on every workflow using the CI mock only, with no real model key, and the evaluation set passes on the mock.
- **User-facing text.** At most one release-note line. Any new or changed user-facing string goes to the Contest Planner before it is committed.
- **Time budget.** The incident notice arrives within 60 seconds in 19 of 20 runs: pickup within 15 s, settle within 30 s of the first failure, diagnosis within 20 s, delivery within 5 s. The online demo serves about 6 concurrent visitors, each within that budget.
- **Out of scope:**
  - pacing the evaluation's incident cases (DW-878);
  - starting the timer at the runner (option A, not chosen).

## Technical Decisions

- **The pipeline.** Every model use goes caller → `OcuTalon.Bridge.Process.Decide` → one agent runner operation per agent (`TriageAgent`, `DiagnosisAgent`, `ChatAgent`) → response.
  - All runners are `AgentRunner` on the adapter `OcuTalon.Bridge.Adapter.Agent`, and only runners call `Chat`.
  - `Decide` sends asynchronously with `SetTimer(timeout)`, classifies the reply, records the decision and answers its caller.
  - `IncidentManager` calls `Decide` with kind `diagnose` and consumes the decision itself.
  - Request kinds: `decide`, `diagnose`, `turn` and `tool`. A `tool` request uses no model; it is an approved call's replay or a source poll.
- **Timer and late replies.** The bridge timer is 60 s by default and capped at 110 s. Derived timeouts come only from `OcuTalon.Bridge.Timeouts.Derive`, and a timer change restarts the runners. A reply after the timer is counted for cost and dropped, and it changes nothing.
- **Decision rows.** `Decide` allocates the `DecisionRef` before sending and passes it in the request. It records one `Decision` row per call, unique on (`ItemId`, `Kind`), when the decision concludes. So an existing row for a request's `DecisionRef` means `Decide` is done with it. Reuse Story 17.2's late-retry check (DW-725: the `RetryIsLate` pattern on `Data.Decision` `RefIndexExists`), which is already on this branch.
- **The AD-8 retry** goes to `DiagnosisAgentRetry` with the same `DecisionRef` as the first attempt, and the one row is written only at conclusion. A live retry therefore has no row yet and must not be skipped.
- **Usage.** The runner, not `Decide`, writes one `Usage` row per `Chat` call, even after `Decide` has stopped waiting. A skipped request writes none.
- **Production class.** It holds structure only: items, classes, pool sizes and enabled flags. Settings values live elsewhere.
- **Mock.** Lane A adds mock behaviour only as new files under `ci/mock/scenarios/A/`.
  - A request picks its scenario by a `[[mock:<name>]]` marker in its newest user message. Otherwise the default script for the agent's `MOCKKEY` answers it, which is `diagnosis` for this runner.
  - A reply's `delayMs` gives the reply delay.
- **Ownership and tests.** Epic 5 is Lane A, and the Bridge, Agent, Watch and Tools packages are all Lane A. Tests are `%UnitTest` classes named `OcuTalon.Test.<Area>`.

## Cross-Story Dependencies

- 5.14 builds on these:
  - 5.4: diagnosis through `Decide` and `IncidentManager`;
  - Story 17.2: the retry runners and the late-retry check (DW-725);
  - Epic 0: the production and the runner pins.
- DW-878, pacing the evaluation's incident cases, is Epic 9's fix-forward and is handled separately.
- The motivating load is the online demo's concurrent visitors (NFR-23), shipping in release 1.0.4.
