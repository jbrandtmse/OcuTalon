---
title: 'Several incidents at once are each diagnosed inside their timer'
type: 'bugfix'
created: '2026-11-07'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Decide starts a diagnosis's timer when it sends the request, and `DiagnosisAgent` runs one job. So when several incidents settle together, the later diagnoses spend their timer in the runner's queue and fall back to `timeout` before the model is asked (DW-879). The runner then still runs each abandoned request when its turn comes: a model call, perhaps tool calls, and a Usage row that no answer uses.

**Approach:** `DiagnosisAgent` gets a pool of 2, and every other item keeps its pool. The agent runner's adapter skips a request whose `DecisionRef` already has a `Decision` row. The skip builds nothing and makes no model request, tool call or Usage row. It writes one Info log line and returns status OK with no response, and Decide's completed process discards that empty answer. Both changes are proved on the CI mock:
- a diagnosis queued past its timer is skipped, while the two that held the jobs ran;
- two diagnoses that settle together run at once, and each is answered well inside the 60-second timer.

## Boundaries & Constraints

**Always:**
- The skip covers every request of kind `decide`, `diagnose` or `turn` whose `DecisionRef` is not empty and has a `Data.Decision` row (`RefIndexExists`) when `Answer` takes it. That holds for any provenance, linked or not, and for a first attempt, a rate-limit re-send or a second-model retry alike. The check runs once, after the kind check, the `RetryOf` check and the `tool` line, and before `BuildAgent` and `Context.Begin`.
- Never skipped:
  - a request of kind `tool` (`Replay.Run`, the replay of an approved call, which keeps its own single gate `StartExecution`);
  - a request with an empty `DecisionRef`;
  - a request whose row does not exist yet;
  - a `ToolInventory` message.
- A skipped request has:
  - status OK and no response object (`OnMessage` sets none);
  - no agent build or model lookup, no model request, no tool call, no Usage row, no AI session, no conversation lock and no link;
  - exactly one `$$$LOGINFO` row from `Answer` (the text is under Public text). It names the runner item (`BusinessHost.%ConfigName`), the kind and the `DecisionRef`. It holds nothing else of the request: no Input, ItemId or OwnerRef, no key and no model text.
- `IncidentManager`, `Decide`, `DiagnosisAgentRetry` and every other item keep their pool sizes. The `DiagnosisAgent` item is the only change in `Production.cls`.
- `RetryIsLate` keeps its name and its save guard in `SaveRetried`. A retry whose decision is recorded while it chats still saves no session, and its cost is still counted (Story 17.2, DW-725).
- Tests use the CI mock only. Each test creates and removes its own rows, settings and sessions.

**Never:**
- No change to `TimerSeconds`, `Timeouts`, `Decide.cls`, the `RetryItem` wiring or any timeout. The timer still starts when Decide sends (AD-8; option A was not chosen). A test may lower Decide's `TimerSeconds` row for its own run and put it back, as `Test.Agent.Decide` `TestTimer` does.
- No new property on a message class or a table (no schema change). A skip never returns an error status and never logs at warning level.
- No edit to:
  - `Decide.cls`, `Agent/Triage.cls`, `ci/units.sh` or `ci/mock/test/constants.test.mjs`;
  - an existing mock scenario;
  - `release/*` or `eval/run.sh`;
  - any contended line that Design Notes does not name.
- No real model key.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Stale, each kind | Three requests, each with a `DecisionRef` that has a Decision row, each sent to a fresh shadow runner: a `decide` (Triage), a `diagnose` (Diagnosis) and an untrusted `turn` (Chat) | Status OK and no response. No mock request carries the request's test reference, and no Usage row has its `DecisionRef`. The agent is not built. One Info row of `Adapter.Agent` `Answer` holds `ZzRunner`, the kind and the `DecisionRef`, and no row holds the request's Input or ItemId. The item still has exactly one Decision row | No error expected |
| Stale linked turn | A user `turn` whose `DecisionRef` has a row | As above, and no AI session is saved and no link is made | No error expected |
| Stale retry | A retry of a linked turn (`Decide.RetryRequest`, `RetryOf` ZzRunner) whose `DecisionRef` has a row, sent to the retry runner (`ZzRetryRunner`, config name `ZzRetry`) | Skipped as above; the Info row names `ZzRetry` | No error expected |
| Live | A `decide` and a linked `turn` whose `DecisionRef` has no row | Answered as before: a Reply with text, one Usage row, a request in the mock's log, and no skip row | No error expected |
| No DecisionRef | A request with an empty `DecisionRef` (every existing `Test.Bridge.Runner` call through `Ask`) | Never skipped | No error expected |
| Replay with a row | A `tool` request for an approved `tool_call` whose `DecisionRef` has a row | The replay runs once (the approval row is done, `ToolsRun` 1), and no skip row is written | No error expected |
| Late during its Chat | A retry of a linked turn whose row is recorded after its Chat and before its save (`ZzRetryAdapter` `ConcludeRef`) | It answered (a text, one mock request, one Usage row) and saved no session (`SessionId` empty, the session mark unchanged) | No error expected |
| Queued past its timer (Integration AC) | Decide's `TimerSeconds` row is 12, with Decide restarted alone. Diagnoses R1 and R2 (`diagnosis-busy`, 20 s replies) hold both DiagnosisAgent jobs. R3 goes to Decide once R1 and R2 are in the mock's log | R3's only Decision row is its timeout fallback. When a job frees, the runner skips R3: no mock request, no Usage row and no AgentStep, and one Info row names `DiagnosisAgent` and R3's `DecisionRef`. Its answer to Decide has no body and is marked Discarded. R1 and R2 reached the mock and have one Usage row each | No error expected |
| Two at once (Integration AC) | One batch of two synthetic failures on two items, with the markers `diagnosis-slow:one` and `diagnosis-slow:two` (10 s replies); Decide's timer is 60 s | Two incidents, each with its usable no-fix diagnosis. Decide sent both runner requests to DiagnosisAgent within 3 s of each other, and both model requests reached the mock less than 10 s apart. Each is answered within 16 s of its send, and within half the timer | No error expected |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `src/bridge/`, `ci/`, `docker/` or `irislib/`.

- `Production.cls` L30-33 is the DiagnosisAgent item, in the lane A region (L15-66).
  - `FixExecutor` L57 already has a pool of 2, so a pool above 1 has precedent.
  - Decide L20, DiagnosisAgentRetry L41 and IncidentManager L53 stay at 1.
  - Epic 19 edits L20-25 and L62-66.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:
  - the class doc L3-73 (L36-44 cover the retry and the late retry);
  - the per-object state L92-100 (`Expected`, `Retrying` and `Building` are Transient), `OnInit` L104-109 and `BuildAgent` L197-217: each job builds its own host and adapter;
  - `Answer`: its doc L350-365 and body L366-406, with the kind check L370-372, the RetryOf check L373-375, the `tool` line L376, the Input check L377, `BuildAgent` L380, `Retrying` L382 and `Context.Begin` L383. The skip goes after L376;
  - `SaveRetried` L512-530 and `RetryIsLate` L532-539: the `RefIndexExists` check to reuse;
  - `Converse` L553-593, which writes the Usage row (L571-576).
- `src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls`: the class doc L1-12. `OnMessage` L31-45 passes the adapter's reply through (L35-37), so a skip with `reply` "" gives no response.
- `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls` L71: `Index RefIndex On Ref [ Unique ]`.
- Decide, read-only (`src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`, contended):
  - `OnRequest` L306-343: a recorded (ItemId, Kind) is answered from its row (L312), every call allocates a new `DecisionRef` (L328), the send is at L339 and the timer at L341-342;
  - `OnResponse` L385-429, with the timer key at L389-394;
  - `TryRetry` L660-699: the retry carries the same `DecisionRef` (L682-696);
  - `Resend` L436-450: the same `DecisionRef` (L446);
  - `SentRequest` L471-478 and `RetryRequest` L484-493;
  - `RecordFallback` L1581-1611 and `Record` L1648-1661 write one row per (ItemId, Kind). The class doc L69-74 says that the timer's controlled keys make the framework discard a late reply.

  So a row with a request's `DecisionRef` exists only after the Decide instance that allocated that Ref has concluded and answered its caller.
- The Ens framework, read-only:
  - `irislib/Ens/BusinessOperation.cls` L395-397: a request that needs a reply gets a response header, with no body when the response is null;
  - `irislib/Ens/BusinessProcess.cls` L294-297: a response to a completed process is marked Discarded, with a sysTRACE line only. L322-326: a response that is no longer pending is marked Discarded;
  - `irislib/Ens/Actor.cls` L95-100: a response for a deleted instance is marked Discarded, with a catTRACE line only.
- State that the two jobs could share, read-only:
  - `src/bridge/cls/OcuTalon/Bridge/Context.cls` and `Bridge/Adapter/StepBuffer.cls` keep their state in process-private globals (`^||OcuTalonBP.Context`, `^||OcuTalonBP.Steps`);
  - `src/bridge/cls/OcuTalon/Bridge/Keys.cls`: `Record` L88-99 (one node per item, holding the last writer's `$Job`), `Forget` L103-110 (removes only the writer's record), `Status` L35-44, and `Absent` L64-83, which reads the settings and not the record.
- `src/bridge/cls/OcuTalon/Bridge/Replay.cls` L1-21: the replay's own gate.
- `Watch/IncidentManager.cls` L684 sends the diagnose request to Decide asynchronously, so two incidents' diagnoses can be in flight at once.
- The mock:
  - `ci/mock/mock.mjs` L40-48: the log line (`ts`, `marker`) is written before a reply's delay. L605-620: `delayMs` is a non-blocking timer;
  - `ci/mock/scenarios/A/diagnosis-nofix.json` holds the no-fix reply text to reuse;
  - `ci/mock/test/scenarios.test.mjs` L130-140 checks the committed scenarios by name, never by count.
- The pins:
  - `Test/Agent/Runners.cls`: header L31, `RUNNERS` L61, `INVENTORYRUNNERS` L65, `TestStartsWithNoKey` L169, `TestStartRefused` L246-247, `TestPoolIsTheCap` L397-412 and `AssertOthersRun` L604-616;
  - `Test/Install/Production.cls` L658: the DiagnosisAgent row of `XData Items`.
- Checked, generic, no change needed:
  - `docker/tests/lib-live.sh`: `item_jobs` L727-733 and `check_items_run` L736-760;
  - `docker/tests/test-production.sh` rows 14, 16 and 18 (L100-235), which compare job lists per item;
  - `Install.Step.Production.NotRunning`;
  - `Test/Agent/RunnerFixture.cls` `WaitRecord` L195-213, which accepts any alive job's record;
  - `Test/Bridge/Keys.cls`;
  - `Test/Install/ProductionRules.cls` `TestPoolSizes` L96-112 (a pool of at least 1);
  - `Test/Fix/Waits.cls` L58 (FixExecutor's two jobs).
- `Test/Agent/RunnerFixture.cls`:
  - `Jobs` L184-193, `EventMark` L239, `LogRowsHolding` L247, `Send` L319, `NewRequest` L333, `DecisionOf` L372, `Headers` L380, `StepsOf` L392, `DeleteSteps` L406 and `HeaderMark` L494;
  - `PointKeys` and `RestoreKeys` L513-526, `PutDefault` L749, and `RememberDefault` and `RestoreDefaults` L782-803;
  - `Drain` L862-877, whose doc says that a runner has a pool of 1;
  - `Warnings` L1155-1171 and `UsageIds` L1174;
  - Epic 11 edits L35-43, L315-330 and L830-846.
- `Test/Bridge/Runner.cls`:
  - the header L1-79 and `OnAfterOneTest` L98-106;
  - `TestUnbuiltKinds` L490-538 (the "nothing reached the mock" pattern) and `TestUsageRows` L545;
  - `TestReplayThroughTheRunner` L998-1122, whose replay setup uses `ZzReplayAgent`;
  - the helpers `NewUsageRequest` L943, `UsageIds` L961, `LogMark` L967, `ToolRequest` L1185, `ApprovedRow` L1199, `LinkCount` L1239, `NewRunner` L1261 and `ProviderConfig` L1275.
- `Test/Bridge/ZzRetryAdapter.cls` L1-40 and `ZzRetryRunner.cls`: the retry double. `RetryAllowed` accepts ZzRunner, and its `SaveLinked` hook is the pattern to follow.
- `Test/Bridge/Conversation.cls` (contended): `TestRetryMovesTheLinkOnlyWhenOnTime` L454-503 records a row and then sends a retry (L470-481 and L495-502). `RecordDecision` L505-519 is private, and `NewRetryHost` L216-219 makes `ZzRetry`.
- Patterns to follow:
  - `Test/Agent/Decide.cls` `TestTimer` L567-623: a `TimerSeconds` row of 12, Decide restarted alone, and the late reply marked Discarded (`AnswerStatus` L1517-1526);
  - `Test/Watch/Diagnose.cls` `TestDiagnosisVariants` L240-318: one batch of synthetic incidents with markers;
  - `Test/Watch/Case.cls`: `Ready` L316, `PointKeys` L566, `Item` L1360, `SendBatch` L1369, `WaitIncident` L1439, `WaitDiagnosed` L1483, and the `ItemIds` clean-up;
  - `Test/Schedule/Heartbeat.cls` `Settle` L897-919: the idle loop over every job of an item.

## Tasks & Acceptance

**Execution:**
- `ci/mock/scenarios/A/diagnosis-slow.json` (new) -- Name and marker `diagnosis-slow`. One reply: status 200, `delayMs` 10000, and the `text` of `diagnosis-nofix.json` -- AC5's 10-second diagnosis. A no-fix diagnosis asks FixExecutor for no dry run on a synthetic incident.
- `ci/mock/scenarios/A/diagnosis-busy.json` (new) -- Name and marker `diagnosis-busy`. One reply: status 200, `delayMs` 20000, and the same text -- for AC4, it holds the jobs past a 12-second timer, which stays under the 25-second attempt timeout that the runners' entries derive from the 60-second timer.
- `src/ocutalon/cls/OcuTalon/Production.cls` -- Set `PoolSize="2"` on L30 and change nothing else -- DW-879, AD-6.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` -- DW-879:
  - a new private `Concluded(request) As %Boolean`, which returns `(request.DecisionRef '= "") && ##class(OcuTalon.Bridge.Data.Decision).RefIndexExists(request.DecisionRef)`. `RetryIsLate` returns `..Concluded(request)` and keeps its doc, so the check has one source;
  - in `Answer`, right after the `tool` line: when `..Concluded(request)`, log the Public text line with `$$$LOGINFO` and `Quit $$$OK` with `reply` "". This comes before `BuildAgent` and `Context.Begin`;
  - the docs (contract only):
    - the class doc gains the skip: which requests it covers, what happens, and why (Decide records the row when it concludes, so a request taken after that is abandoned, while a request already in Chat when the timer fires runs to its end as before);
    - the `Answer` doc names the skip;
    - L36-44 say that a retry already late when the runner takes it is skipped, and that a retry whose timer fires during its Chat saves nothing and is counted.
- `src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls` -- Class doc only:
  - a Request whose decision Decide has already recorded gets no response and status OK (`Adapter.Agent` `Concluded`);
  - a pool above 1 (DiagnosisAgent) runs that many requests at once.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` -- Test helpers:
  - `Warnings` takes a trailing optional `type`, 3 by default, and its doc says so;
  - a new `Idle(item, seconds) As %Boolean` after `Jobs`. It polls, up to the seconds, until the item's queue is empty and every Ens.Job of the item is Alive and dequeuing with no ActiveMessage;
  - `Drain`'s doc says that its guarantee holds for a runner with a pool of 1, which is every runner but DiagnosisAgent. No caller drains DiagnosisAgent.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzRetryAdapter.cls` -- A new property `ConcludeRef`. When it is set, `SaveRetried` first records the Decision row of that Ref (`Test.Bridge.Runner` `RecordConcluded`), as Decide does when the retry's timer fires during the call, and then runs `##super`. The class doc says so.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Runner.cls` --
  - a public `RecordConcluded(ref, itemId, kind, owner)` that saves a timeout fallback Decision row with the Summary of a new parameter `CONCLUDEDMARK` ("ZzConcluded"). `OnAfterOneTest` deletes the Decision rows with that Summary, and the Usage rows of `ZzRetry` as well as those of `ZzRunner`;
  - `TestSkipsAConcludedRequest` covers the matrix rows Stale each kind, Stale linked turn, Stale retry, Live and Replay with a row (with the setup of `TestReplayThroughTheRunner`);
  - `TestRetryLateAfterItsChat` covers the row Late during its Chat;
  - the header names both tests (Story 5.14).
- `src/ocutalon/cls/OcuTalon/Test/Agent/QueuedPastTimer.cls` (new) -- It extends `%UnitTest.TestCase` and runs in throwaway stacks and CI only. Its one test, `TestSkippedAfterItsTimer`, is the matrix row Queued past its timer:
  - the test checks that the stack is ready and points the keys (RunnerFixture `ReadyReason` and `PointKeys`; `RestoreKeys` in `OnAfterAllTests`), then waits for `Idle("DiagnosisAgent", 60)`;
  - Decide's `TimerSeconds` row is set to 12 (`RememberDefault`, `PutDefault`), and only Decide is restarted, so the runners' entries keep the derivation of 60;
  - R1, R2 and R3 are built with RunnerFixture `NewRequest("diagnose", "untrusted", "[[mock:diagnosis-busy:<n>]] Diagnose this incident.")` and go to Decide by `SendRequestAsync` from an `ApprovalStartIn` service. R3 is sent only once the mock's log holds R1 and R2, that is, once both jobs are in Chat;
  - the test polls, with ceilings, for the three Decision rows and for DiagnosisAgent's answers to the three runner requests, and then asserts the row. It logs with `$$$LogMessage` the send and answer times of the three runner requests and the timer;
  - `OnAfterOneTest` puts the row back and restarts Decide (also after a failure), waits for `Idle`, and deletes the three items' Decision, Usage and AgentStep rows.
- `src/ocutalon/cls/OcuTalon/Test/Watch/DiagnoseTogether.cls` (new) -- It extends `Test.Watch.Case` and runs in throwaway stacks and CI only. Its one test, `TestTwoAtOnce`, is the matrix row Two at once:
  - `Ready`, `PointKeys`, a fixture session, and `Idle("DiagnosisAgent", 60)`;
  - one `SendBatch(..#SYNTHNS, ..#SYNTH, session, ...)` of two failures, on `Item("slow-one")` and `Item("slow-two")`, with the texts `[[mock:diagnosis-slow:one]] Field 'Qty' was empty` and `[[mock:diagnosis-slow:two]] Field 'Qty' was empty`, as `TestDiagnosisVariants` does;
  - `WaitIncident(.., 2)`, then `WaitDiagnosed` for each incident. For each incident: its `diagnose` Decision is usable; the send time is the time of the header from Decide to DiagnosisAgent that carries its `DecisionRef`, and the answer time is the time of that header's response;
  - the test asserts the row's bounds and logs with `$$$LogMessage` the send time, answer time and milliseconds of each, and the timer;
  - clean-up through `ItemIds` (Watch.Case).
- `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls` -- The pins (AC1):
  - a new `Parameter POOLS`, placed right above `TestPoolIsTheCap` and away from Epic 19's hunk at L73-80: `TriageAgent:1,DiagnosisAgent:2,ChatAgent:1,TriageAgentRetry:1,DiagnosisAgentRetry:1,ChatAgentRetry:1`;
  - `TestPoolIsTheCap` (L397-412) runs over `POOLS`. For each runner, its `PoolSize` in `Ens_Config.Item` equals the expected pool, and so does its count of alive jobs. The query moves into a new private `PoolOf(item)` beside the test;
  - L169 (`"has one job"`) and L247 assert `..PoolOf(item)` jobs (`..PoolOf(other)` on L247), with messages that say "the jobs of its pool". `AssertOthersRun` (L604-616) waits for and asserts `..PoolOf(other)` jobs, and its doc says so;
  - header L31: TestPoolIsTheCap pins 2 for DiagnosisAgent (Story 5.14) and 1 for the other five runners.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` -- Set `"pool": 2` on L658 and change nothing else (Epic 19 edits L654 and the header).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Conversation.cls` -- Contended: edit it only with the orchestrator's ruling (see Design Notes, Footprint). Nothing else in the file changes:
  - L454-457: the doc says that since Story 5.14 a retry already late when the runner takes it is skipped (no model request, no Usage row, no reply, no session) and moves nothing;
  - L477 expects 0 model requests, L478 no reply, L481 0 Usage rows, and L501 no reply.
- This spec's `## Verification` -- The implement stage adds the Measured line from the two integration tests' `$$$LogMessage` output (AC5) and each `mutation:` line.

**Acceptance Criteria:**
- **AC1 (DW-879, AD-6).** Given `OcuTalon.Production` running, when its runners are read, then:
  - DiagnosisAgent has `PoolSize` 2 and two alive jobs, and the other five runners have 1 and one job each (`TestPoolIsTheCap`);
  - the oracle of `Test.Install.Production` holds pool 2 for DiagnosisAgent, with every other row unchanged;
  - every job-count check of `Test.Agent.Runners` passes.
- **AC2 (DW-879, AD-6, AD-20).** Given a `decide`, `diagnose` or `turn` request whose `DecisionRef` has a Decision row, when a runner takes it, then the matrix rows Stale each kind, Stale linked turn and Stale retry hold.
- **AC3 (AD-8, AD-10).** Given a live request, a request with no `DecisionRef`, or a replay whose `DecisionRef` has a row, when a runner takes it, then it runs exactly as before (the rows Live, No DecisionRef and Replay with a row). A retry whose decision is recorded during its Chat saves no session and is counted (the row Late during its Chat).
- **AC4 (Integration AC; Decide reads the runner's answer; AD-8).** Given Decide's timer at 12 s and both DiagnosisAgent jobs busy, when a third diagnosis waits in the queue past its timer, then the row Queued past its timer holds: Decide recorded one timeout row for it and nothing more, and the runner skipped it when a job freed.
- **AC5 (Integration AC; IncidentManager reads both diagnoses; NFR-7, AD-15).** Given two incidents that settle together and a 10-second mock reply, when IncidentManager sends both diagnoses, then the row Two at once holds, and `## Verification` records the measured send and answer times of both and the timer.
- **AC6.** Given the change, when it merges, then:
  - `TimerSeconds` and every timeout are unchanged, and no RetryItem is set;
  - CI is green on every workflow, on the mock only;
  - the evaluation set on the mock passes;
  - the diff is the files of the Execution list;
  - the only new operator-facing string is the log line under Public text.

## Spec Change Log

- 2026-11-08, lead spec gate: added "CI time" and "Calls the harness moves to the background" under `## Verification`, and the Epic 11 merge note under Footprint. Epic 11 merged into feature at ece74afb after the plan, so its hunks in `Test/Agent/Runners.cls` and `Test/Agent/RunnerFixture.cls` are no longer contended; the end-of-epic integrate-forward takes them (no overlap with this story's lines). The contended edits to Epic 19's paths wait on the orchestrator's ruling.

## Review Triage Log

## Design Notes

**Governing ADs:**
- **AD-6.** All model use goes caller → Decide → runner. "Pool size is the concurrency cap", and runners are the only code that calls `Chat` and writes the Usage row.
  - Two DiagnosisAgent jobs are two concurrent `Chat` calls of one runner item.
  - TriageAgent, DiagnosisAgent and ChatAgent already chat in three jobs at once, and FixExecutor already runs two jobs.
  - AD-6 binds NFR-23 (the online demo's visitors).
- **AD-8.** The timer starts at Decide's send and is not changed. A late reply moves nothing and is dropped, and a retry carries the first attempt's `DecisionRef`. A skipped request sends no reply, so nothing reaches Decide's classification.
- **AD-20.** Decide records one Decision row per call and allocates its Ref before the send. The runner writes the Usage row of each `Chat`. Decide checks the budget, the daily cap and the request size when it sends.
- **AD-5.** The production class holds the pool sizes, which are structure.
- **AD-15 and AD-30 (NFR-7).** IncidentManager sends the diagnose request to Decide asynchronously and consumes the decision; AD-15 also sets the notice budget.
- **AD-10 and AD-11.** The replay is governed and runs once, and it is never skipped. A skipped turn runs no tool, so a command whose turn the user saw fail never runs afterwards.
- **AD-22.** Tests run on the mock. Lane A adds mock behaviour only as new files under `ci/mock/scenarios/A/`.
- **AD-2.** The adapter names only bridge classes (`Data.Decision`).
- **AD-29 and AD-33.** These are Lane A's files, and DiagnosisAgent is Lane A's item.

**Which requests the skip covers** (the AC's "request kinds"):

| Request | Its `DecisionRef` | A row exists when the runner takes it | Skipped |
|---|---|---|---|
| First attempt (`decide`, `diagnose`, `turn`) | New for each Decide call (L328) | Only once that Decide has concluded, that is, its timer fired while the request waited | Yes, then |
| Rate-limit re-send | The same (L446), sent after the earlier reply and before any row | Only when its timer fired while it waited | Yes, then |
| Second-model retry (`RetryOf`) | The same (L682) | Only when `T2` fired while it waited | Yes, then |
| A first attempt still queued when its retry answered | The same | After the retry concluded | Yes |
| `tool` (a replay) | New for each Decide call | Possible, when its timer fired | Never: the replay is handled before the check |
| An empty `DecisionRef` (a direct caller, such as a test) | None | Not applicable | Never |
| `ToolInventory` | None | Not applicable | Never |

So no live request is ever skipped: a row with a request's Ref exists only after the Decide instance that allocated the Ref has answered its caller. The check is read once, before the build. A row written after the check changes nothing for that request: it runs to its end, as a request already in `Chat` when the timer fires always did.

**What the runner returns, and what Decide does with it:**
- The runner returns status OK and no response. The business operation then sends Decide a response header with no body (BusinessOperation L395-397).
- That Decide instance has completed: it answered when its timer fired, and `SetTimer`'s controlled keys removed the reply's pending entry. So the framework marks the response Discarded and writes only a trace line (BusinessProcess L294-297 and L322-326; Actor L95-100 for an instance that was already deleted). No warning, error, row, step or event follows.
- Why not an error status: Ens would log an error row for every skip, which `ErrorRows` and the operators read as a fault.
- Why not an empty Reply: it stores a body that no one reads, and a Decide that was still waiting (by construction there is none) would classify it.

**Per-job state with two jobs:**
- Each job builds its own host and adapter object, so `Agent`, `Building`, `Retrying`, `Expected` and the built agent are per job.
- Context and the step buffer live in process-private globals.
- A diagnose request chats in a throwaway session, with no conversation lock and no link.
- The one shared node is `^OcuTalonBP.KeyState(item)`:
  - both jobs record the same state from the same settings, and the record names the job that wrote last;
  - `Forget` removes only the writer's record;
  - `Keys.Absent`, Decide's precheck, reads the settings and not the record.

  So if the writing job stopped alone, the key's status display could clear while the other job runs. The status display is the only effect, and a production stop or an item restart stops both jobs together. Real only if one DiagnosisAgent job stops alone (wontfix-theoretical).

**Budget, daily cap and request size:**
- These checks do not change in kind. Decide (PoolSize 1) prechecks each request when it sends it, and a queued request had already passed its precheck when DiagnosisAgent ran one job. A second job changes when the spend happens, not which requests pass.
- The skip lowers spend: a request whose decision has already fallen back no longer reaches the model.
- The gateway's 120 requests a minute, the daily cap of 20 USD and LUConsumed 1 of 8 are the Planner's host checks (context only). The Planner watches LUConsumed in the demo-path smoke after the update; no test here measures it.

**NFR-7 with more than two incidents at once (inference):**
- Two jobs serve two diagnoses at a time. A third waits for a whole diagnosis first, so at AD-15's typical time (a diagnosis under 12 s) it still lands inside the 60-second timer, but outside NFR-7's 20-second share for diagnosis.
- Six at once run in about three waves.
- This story proves two (AC5). More jobs and pacing are out of scope, and DW-878 belongs to Epic 9.

**Integration ACs (Rules 1 and 2):**
- Consumed-by:
  - Decide (AC4): it records no new decision for a skipped request and discards its empty answer;
  - IncidentManager (AC5): two incidents get their diagnoses at once;
  - the online demo (NFR-23; Epics 16 and 29).
- Consumes:
  - the `Data.Decision` rows that Decide writes (AD-20);
  - Story 17.2's `RetryIsLate` check (DW-725);
  - Story 5.4's diagnosis pipeline;
  - the CI mock (Story 0.11).

**Extend, don't copy:**
- The skip reuses `RetryIsLate`'s `RefIndexExists` check: the check moves into `Concluded`, and `RetryIsLate` delegates to it. Both names are kept, because `Test.Bridge.Conversation` (contended) names `RetryIsLate`.
- `RunnerFixture.Warnings` is extended with an optional `type`. It is not copied.
- `TestPoolIsTheCap`'s query becomes `PoolOf`, which four checks share.
- Copies, each with its reason:
  - `RunnerFixture.Idle` copies the loop of `Test.Schedule.Heartbeat.Settle` (about 15 lines). That method is in a Lane B test class, its ceiling is a fixed 10 s, and its doc names one job; a Lane A fixture needs a longer ceiling and should not depend on a Lane B test class;
  - `Test.Bridge.Runner.RecordConcluded` copies `Test.Bridge.Conversation.RecordDecision` (about 10 lines), which is private to a contended class. The new helper is shared by `Test.Bridge.Runner` and `ZzRetryAdapter`.
- The two integration tests are new classes that follow `Test.Agent.Decide` `TestTimer` and `Test.Watch.Diagnose` `TestDiagnosisVariants`. They are not added to those classes, because each new class has to fit one foreground call, and both of those classes already hold several timed tests.

**Footprint (Rule 11):**
- Files:
  - `Production.cls`;
  - `Bridge/Adapter/Agent.cls` and `Bridge/Operation/AgentRunner.cls`;
  - `ci/mock/scenarios/A/diagnosis-slow.json` and `diagnosis-busy.json` (new);
  - `Test/Agent/RunnerFixture.cls`, `Test/Bridge/ZzRetryAdapter.cls` and `Test/Bridge/Runner.cls`;
  - `Test/Agent/QueuedPastTimer.cls` and `Test/Watch/DiagnoseTogether.cls` (new; both areas already exist, so `ci/units.sh` is unchanged);
  - `Test/Agent/Runners.cls` and `Test/Install/Production.cls` (the pins);
  - `Test/Bridge/Conversation.cls` (with the ruling);
  - this spec.
- Footprint extensions to report: `Test/Agent/RunnerFixture.cls`, `Test/Bridge/ZzRetryAdapter.cls` and the two new test classes.
- Contended paths, with their exact lines. Each merges cleanly against `origin/OCT-epic11` and `origin/OCT-epic19`, checked at plan time:
  - `Test/Agent/Runners.cls` L169 is in `TestStartsWithNoKey`, Epic 11's method, whose hunks are at L149-155, L207-213 and L228-234. It is a required pin (AC1). The other `Runners.cls` edits (L31, L247, L397-412 with the new parameter and helper beside it, and L604-616) are outside Epic 19's hunks (L73-80, L322-328, L362-385, L517-534 and L538-550).
  - `Test/Install/Production.cls` L658 is the named pin; Epic 19 changes L654 and the header L10.
  - `Production.cls` L30; Epic 19 changes L20-25 and L62-66.
  - `Test/Bridge/Conversation.cls` L454-457, L477, L478, L481 and L501, outside Epic 19's hunks (L123-133 and L1172-1179). This is not a pin, and it **needs the orchestrator's ruling**:
    - `TestRetryMovesTheLinkOnlyWhenOnTime` records a Decision row and then sends a retry (parts 1 and 3). The skip now skips that retry (no model request, no reply, no Usage row), so its expectations must be reversed;
    - the save guard that this part covered keeps its pin, in `Test.Bridge.Runner` `TestRetryLateAfterItsChat`;
    - an alternative, if the ruling refuses the edit: leave requests with `RetryOf` out of the skip, keeping Story 17.2's late-retry rule unchanged. That needs no contended edit, but a retry queued past `T2` on a retry runner would still chat. No RetryItem is set at install in 1.0.4, so a default install sends no retry.
  - [Lead, spec gate, 2026-11-08: Epic 11 merged into feature at ece74afb, so its hunks below are now feature changes, not contended paths; Epic 19 is the only in-flight epic whose diff holds this story's files: `Production.cls`, `Test/Agent/Runners.cls`, `Test/Install/Production.cls` and `Test/Bridge/Conversation.cls`.]
  - `Test/Agent/RunnerFixture.cls` is not on the runner's contended list, but Epic 11 edits L35-43, L315-330 and L830-846 in flight. This story edits the `Drain` doc (L862-868) and `Warnings` (L1155-1171), and adds a method after L193. None of these overlap Epic 11's hunks, and the header list (L1-66) is left alone.

### Public text

- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` (`Answer`, `$$$LOGINFO`; an operator-facing event-log row), with `<item>` the runner item's config name, `<kind>` one of `decide`, `diagnose` or `turn`, and `<DecisionRef>` the 22-character Ref:
  `<item> skipped the <kind> request of the decision <DecisionRef>: Decide has already recorded that decision, so no model request was made and no tool ran.`
  For example: `DiagnosisAgent skipped the diagnose request of the decision Qx3v9KpZt0aLmB7cR2dE4f: Decide has already recorded that decision, so no model request was made and no tool ran.`
- The release-note line: this story writes none. `release/notes.sh` drafts the story's title, "Several incidents at once are each diagnosed inside their timer", under "Watching productions and incidents" (`release/notes-areas.txt` maps epic 5 there).
- No other user-facing or operator-facing string changes. Assertion messages and doc comments are not public.

**Ledger inbox:** DW-879 is addressed by the `Production.cls` and `Adapter/Agent.cls` tasks and by AC1 to AC5. No entry is declined.

**Decided in-stage:**
- The skip covers retries and re-sends as well as first attempts, which is the AC's Given read as written. The cost is the contended `Conversation.cls` edit above, for the orchestrator's ruling.
- A skip returns status OK with no response; it is neither an error status nor an empty Reply (reasons above).
- The log line is at Info level, not a warning. Skipping is the correct handling, and the timeout itself is already visible as the decision's fallback.
- The check runs after the kind and `RetryOf` checks, so a bad `RetryOf` still gets its error, and before `BuildAgent`, so a skip makes no model lookup either.
- `TestPoolIsTheCap` pins all six runners, so the retry runners are pinned at 1 too.
- The timings:
  - the two-at-once test uses a 10 s reply, bounded at 16 s (with one job, the second would take 20 s or more);
  - the queued test uses 20 s replies and a 12 s timer row, which leaves about 7 s between R3's timeout and a free job.
- Each integration test is a new small class that fits one foreground call.
- The release-note line is the story title, which the notes script drafts.
- Both new scenarios reply with the no-fix text of `diagnosis-nofix.json`.

**Spine (for the lead, Rule 20).** This plan writes no spine text. It proposes this AD-6 clause, after "Pool size is the concurrency cap.":

> DiagnosisAgent runs two jobs and every other runner one (Story 5.14, DW-879). A runner answers a request of kind decide, diagnose or turn whose DecisionRef already has a Decision row with no response, no model request, no tool call and no Usage row, and one Info line naming the runner, the kind and the Ref: Decide has concluded that decision (its timer fired while the request waited, or a retry answered first). A request of kind tool and a request with no DecisionRef are never skipped.

## Verification

`<lane>` stands for:

```
env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=5 stage=implement'
```

The rules for every run:
- Run one command per call, each with `timeout: 600000`, and never two IRIS test runs in one message.
- Each command must finish in about 150 s, because the harness moves a call to the background at about 170 s. That is why these runs are warm class runs: a warm `class` run starts no stack.
- QA uses the tags `e5s14q` and `e5s14qw`, and review uses `e5s14r` and `e5s14rw`, each with its own stage name.
- No step uses the slot.
- **Warm stacks and the production.** The warm stack's production runs the code that was loaded at `ci/warm.sh up`, and a running job keeps that code. So:
  - run `up` only after editing `Production.cls`, `Bridge/Adapter/Agent.cls` and `Bridge/Operation/AgentRunner.cls`;
  - after any later edit or mutation of one of those three files, run `<lane> OCUTALON_RUN_TAG=e5s14implw ci/warm.sh down` and then `up` again, each in its own call, before the classes that use the running production (`QueuedPastTimer`, `DiagnoseTogether`, `Runners` and `Install.Production`);
  - `Test.Bridge.Runner` runs in the test process, so a warm reload is enough for it.

**Commands:**
- **(loop)** `<lane> OCUTALON_RUN_TAG=e5s14implw ci/warm.sh up`, under the rule above.
- **(loop)** One per call, each `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s14implw ci/iris.sh class <Class>`, for these classes:
  - `OcuTalon.Test.Bridge.Runner`;
  - `OcuTalon.Test.Agent.QueuedPastTimer`;
  - `OcuTalon.Test.Watch.DiagnoseTogether`;
  - `OcuTalon.Test.Agent.Runners`;
  - `OcuTalon.Test.Install.Production`;
  - `OcuTalon.Test.Bridge.Conversation`, once the ruling allows the edit.

  Expected: passed.
- **(once)** The mutations (Rule 19). Apply each one, observe the red, revert it, and confirm that `git status --short` and `git diff --stat` are unchanged:
  - DiagnosisAgent's `PoolSize` back to 1. After `warm.sh down` and `up`, `TestPoolIsTheCap` and `Test.Install.Production` go red; `DiagnoseTogether` goes red on "within 16 s" and "less than 10 s apart"; and `QueuedPastTimer` goes red, because R2 does not reach the mock while R1 holds the one job (AC1, AC5);
  - the skip removed from `Answer`. `TestSkipsAConcludedRequest` goes red; after `down` and `up`, `QueuedPastTimer` goes red, because R3 reaches the mock (AC2, AC4);
  - the `$$$LOGINFO` line removed. `TestSkipsAConcludedRequest` goes red on "one Info row" (AC2);
  - the skip moved above the `tool` line. `TestSkipsAConcludedRequest` goes red on "the replay runs" (AC3);
  - `Concluded` returning 1 for any non-empty `DecisionRef`. It goes red on Live (AC3);
  - `RetryIsLate` returning 0. `TestRetryLateAfterItsChat` goes red, because the session is saved (AC3).

  Record each as `mutation: <change> → <test> red` under this section, with the Measured line (AC5): the send and answer times (UTC, from the message headers) of both diagnoses, their milliseconds and the timer, as `DiagnoseTogether` logs them, and the same for R1, R2 and R3 from `QueuedPastTimer`.
- **(once)** `bash docker/tests/test-mock.sh`. Expected: it passes, and the two new scenario files load.
- **(once)** `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s14implw ci/iris.sh class OcuTalon.Test.Watch.Diagnose`. Its four-at-once batch now runs two at a time. Expected: passed.
- **(once)** `bash ci/checks.sh`. Expected: every check passes.
- **(once)** `<lane> OCUTALON_RUN_TAG=e5s14implw ci/warm.sh down`, also after a failure. Then confirm that the lane-a lock folder holds none of this stage's locks.

**CI time (lead, spec gate).** The two new integration classes join CI groups near REL-4's 35-minute budget (2,100 s): `Test.Agent.QueuedPastTimer` runs in `shards-5` (`shard:lane-a@Bridge,Agent` with `live:sign-in-3`; the job took 1,978 s on feature bed23f1d, ci run 42419117439) and `Test.Watch.DiagnoseTogether` in `shards` (1,880 s on the same run). Keep each class short: aim for at most 60 s for `QueuedPastTimer` and at most 45 s for `DiagnoseTogether` on the warm stack, and record each class's measured seconds (the `CLASS <name> passed <s>s` line) under this section with the Measured line. A class well over its aim is a finding to report, never a deadline to raise.

**Calls the harness moves to the background (lead, spec gate).** `ci/warm.sh up` starts a stack and can take longer than the 170 s at which the harness moves a call to the background. If any call is moved there, wait for it to exit with bounded foreground polls (`ci/warm.sh status`, or the task's output) before anything else, and never end a turn with it running.

**Left to CI and the lead.** CI is available and resolves before the next implement:
- the full shards (lane-a's Bridge and Agent piece takes about 1,246 s in CI, and its Checks, Install and Watch piece about 902 s);
- the timer-heavy classes `Test.Agent.Decide`, `Test.Bridge.SecondModel`, `Test.Agent.Conversation` and `Test.Bridge.Decide` (no timings are recorded, and their timer tests run 12 to 60 s each);
- the evaluation set (`Test.Eval.Run` and the lane-a workflow's evaluation job);
- the live units (`production` and `demo-path`).

The fresh-environment check, forward and reverse, is the lead's (Rule 19).

**Shared surfaces:**
- DiagnosisAgent's pool size and job count:
  - changed: `Test.Agent.Runners` (`TestPoolIsTheCap`, L169, L247 and `AssertOthersRun`) and `Test.Install.Production` L658;
  - checked and unchanged: `lib-live.sh` `item_jobs` and `check_items_run`, `test-production.sh` rows 14, 16 and 18, `NotRunning`, RunnerFixture `WaitRecord` and `WaitRecords`, and `Test.Bridge.Keys` `TestStatus`.
- `RunnerFixture.Drain`'s pool-of-1 premise (a doc change).
- `RunnerFixture.Warnings` (a new optional argument; every caller is unchanged).
- The late-retry behaviour that `Test.Bridge.Conversation` `TestRetryMovesTheLinkOnlyWhenOnTime` pins (the contended edit).
- The event log gains a new Info row from `Adapter.Agent` `Answer`. `ErrorRows` (types 2 and 6) and the warning counters (type 3) do not read it.
- The mock's scenario set gains two new files. The set is checked by name, never by count.
- Decide's `TimerSeconds` row and Decide's job while `QueuedPastTimer` runs; both are restored in `OnAfterOneTest`.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned and halted after planning, as the dispatch asked. Two points for the lead at the spec gate:
- **The contended edit.** One edit needs the orchestrator's ruling: `Test/Bridge/Conversation.cls` L454-457, L477, L478, L481 and L501, which reverse the late-retry expectations that the skip changes. Design Notes (Footprint) also give the alternative for the ruling.
- **For the Planner.** The new operator-facing string is under Design Notes, Public text. The release-note line is the story title, which `release/notes.sh` drafts.
