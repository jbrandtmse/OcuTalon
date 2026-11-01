---
title: 'Story 11.9: Every check left off for release 1 turns on, and the CI flakes are fixed'
type: 'chore'
created: '2026-10-31'
status: 'done'
baseline_revision: 'f5aecd55e9dcefd1105caa2302a1a26b7abc940a'
baseline_commit: 'f5aecd55e9dcefd1105caa2302a1a26b7abc940a'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Five checks that Epics 1 to 10 left on a fixture or a double "until … merges" still run that way: Story 1.12's digest row through OutcomeRouter, Story 2.8's expired and cancelled approval events, Story 2.9's thread over a real Decide, Story 6.4's dismissal against the real IncidentManager, and Story 10.3's `/state` pairing check (R2b). Three CI flakes also cost reruns: DW-376 (`Test.Schedule.Heartbeat`'s RunNow wait), DW-396 (`test-ci-warm.sh`'s 1 s lock wait) and DW-415 (`page.goto` aborted with `net::ERR_NETWORK_CHANGED`).

**Approach:** Each check gets turned on against the real items on the CI mock. A double stays only for an answer the real item can never give. Turning on Story 6.4's check exposes one defect, and this story fixes it: the dismiss route answers the real IncidentManager's refusal (`not_allowed`) with 500 instead of the spine's 409 `not_dismissible`. Each flake fix waits on the real signal, or retries only the one error it names, and comes with a deterministic reproduction.

## Boundaries & Constraints

**Always:**
- A turned-on test drives the running production's real items. A double stays only for an owner answer the real item cannot give, and the test's header names that answer.
- Tests are hermetic (Rule 19). Each test removes the rows it makes: digest rows, approval requests, fix runs, turns, steps and usage. A class that points the runners' keys at the mock restores them in `OnAfterAllTests`, and a failed restore fails the class.
- New mock scenarios go only under `ci/mock/scenarios/A/` (AD-22).
- Flake fixes:
  - A ceiling stays a ceiling: it is polled, never slept.
  - A retry covers only `net::ERR_NETWORK_CHANGED`, at most once, and logs a line.
- Rule 14: ASCII sources, and comments that state the contract.

**Never:**
- Turn on a check whose clause names a story of Epic 12, 30 or 31. That leaves off: R2c (12.7), the `telegram-*` specs, the 31.x `notBuilt` lines, and the replayed tool call's `approval.result` (30.3).
- Edit a file of Epics 15, 30, 12 or 13. That includes:
  - `ci/units.sh`, `docker/tests/lib-live.sh` and `docker/tests/test-lib-live.sh`;
  - `Test/Install/{Registry,Production,Users,StartLock,ReconcileIn,ProductionRules}.cls` and `Test/Checks/{Heartbeat,Probe,Runs}.cls`;
  - every Epic 30 `Test/Bridge/*` file, `src/bridge/.../Bridge/{Approval,Context,Purge,Replay,Time}.cls`, `Bridge/Process/{ApprovalHold,Decide}.cls` and `Bridge/Data/ApprovalRequest.cls`.
  - Calling their public methods is fine.
- Edit Story 11.7's files:
  - `ci/mock/mock.mjs`, `ci/mock/scenarios.mjs`, `ci/mock/test/*` and `ci/mock/scenarios/B/guide-*.json`;
  - `web/e2e/demo-path/*.spec.ts`, `web/e2e/support/{demo-path,devices}.ts` and `web/e2e-online/demo-path/demo-path.spec.ts`;
  - `docker/tests/test-{demo-path,demo-path-gate,online-demo-path,ci-config}.sh`;
  - `Test/Demo/GuidePrompts.cls` and `Test/Schedule/ReminderChat.cls`.
- Change an AD, `web/playwright.config.ts` (no `retries`), or `web/src`.
- Commit a new test class or area. Task 0's probe class is temporary and is deleted before the commit.
- Use a real model key, or run a test on slot A.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| dismiss own Open incident | real IncidentManager, session S, incident R | 200 `{"result":"done"}`. One CommandsIn→IncidentManager header carries `IncidentCommand` dismiss (R, S, origin `web_user`). The row is `closed`, and S's stream gets R's closed view. | none |
| dismiss refused | R `awaiting_approval` or `fixing` (the owner answers `not_allowed`) | 409 `{"error":{"code":"not_dismissible","message":"OcuTalon can't dismiss this incident now. Nothing was changed."}}`. The row is unchanged. | no 500 |
| dismiss another session's | R owned by T | 404 `not_found` | nothing submitted |
| goto, network changed once | the first `goto` throws `page.goto: net::ERR_NETWORK_CHANGED at <url>` | the second `goto`'s answer, plus one `NAV retry <url>` line | none |
| goto, network changed twice | both throw | the second error is thrown, after 2 calls | no loop |
| goto, other error | throws `net::ERR_CONNECTION_REFUSED` or a timeout | thrown unchanged, after 1 call | no retry |

</intent-contract>

## Code Map

**Story 1.12: digest row (shard lane-b, CI group `image`)**
- `src/ocutalon/cls/OcuTalon/Test/Core/RoutingProduction.cls`:
  - :103-167 is `TestEachOutcomeThroughTheRouter`. Its digest branch, :142-152, checks only the OutcomeRouter→DigestStore hop.
  - Today its ItemIds are `Bridge.Ids.NewRef()` (:118), so its digest rows are never cleaned.
  - It extends `Test.Core.InProduction`, whose `OnAfterAllTests` is at :52-58.
- `src/ocutalon/cls/OcuTalon/Test/Digest/Store.cls` (area Digest, `shards-2`):
  - :533-560 is the private `AssertKept`, with the row checks to share;
  - :578 `NewRef` (fixture prefix), :706 `CountItem`, :743 `EventMark`, :753 `LiveEvents` and :769 `Clean` (deletes every prefix row).
- `Test/Core/Observe.cls:65` `WaitProcessed(trace, source, target, count, seconds)` and `:47` `Events(session, type, count, seconds)`.

**Story 2.8: real expired and cancelled events (lane-b, `image`)**
- `src/ocutalon/cls/OcuTalon/Test/Core/AnswersInProduction.cls`:
  - :1-28 is the header;
  - :113-127 is `TestExpiredRequestAnswersExpired` (a fixture row; it checks no event);
  - :258-275 is `TestCancelledAndBadBodies` (a pre-cancelled row: 404);
  - :305-347 is `TestGateStepAndHeldCallReachTheStream`. Its held-call set-up, :308-336, makes the real gate raise a request.
- Read only (Epic 30):
  - `Test/Bridge/Approval.cls`: `TestTimerExpires` :1014 is the pattern: `Age(ref,86460,-60)` :1876, delete `Approval.LiveHold(ref)`'s hold, run `Install.Step.Reconcile.Run()`, then `WaitHoldGone`. Also `TrackOwner` :2048 and `Clean` :1996.
  - `Bridge/Approval.cls`: `Cancel` :356 fires `approval.cancelled`, and `Expire` (from the hold's timer) fires `approval.expired`.
  - The product's cancel callers are `SessionOps.EndApprovals` :303-317 and `IncidentManager:971`.
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls:84` publishes all five `approval.*` types.

**Story 2.9: real Decide in the thread (lane-b, `image`)**
- `src/ocutalon/cls/OcuTalon/Test/Core/ThreadProduction.cls`:
  - :1-28 is the header;
  - :56-64 `OnBeforeAllTests` swaps Decide to the double, and :297-329 is `UseDouble`;
  - :83 `TestTwoTurnsOneThread` and :152 `TestNewThreadAfterMidnight` (both use `Record`/`Script`/`Seen` and the double's text and steps);
  - :198-216 `TestRealDecideAfterTheRestore`;
  - :222-260 `TestBrokenRetryThroughTheProduction` (DW-112);
  - :262 `Turn` and :279 `AssertRealSessions`.
- `src/ocutalon/cls/OcuTalon/Test/Core/DecideDouble.cls`:
  - :2-4 and :17-19 are the swap docs;
  - :126 calls, and :132-146 is, `Step`. It runs only as a production item (`%ConfigName` set).
  - `Record`, `Script`, `Written` and `Clear` stay for `Core/Intake.cls`, `Core/ConversationTurns.cls` and `Core/ProbeSeam.cls:65` (a shadow instance).
- Key pointing, by the pattern of `Test/Schedule/ReminderChat.cls:53-121` (read only):
  - `RunnerFixture.ReadyReason` :309, `PointKeys` :459, `RestoreKeys` :466, `KeysAre` :473 and `WaitRecords`;
  - `SessionMark`/`DropSince`, and the `^OcuTalonBP.UsageCapped` kill.
- `RunnerFixture.StepsOf`, and `StepProblems` (Story 11.8).
- `Test/Contract/Mock.cls:439` `Arm(marker, remaining)`. The mock's countdown (read only, `ci/mock/mock.mjs:36-37,451-462`):
  - armed with remaining > 0, it answers `replies[0]` and decrements;
  - at 0, it answers `replies[min(1+k, last)]`.
- `ci/mock/scenarios/A/invalid-input.json` is the 400 to copy. `A/chat.json` (no marker) calls `list_productions`, then replies "The CI mock looked at the productions.".
- `Test.Data.Fixture.AdoptTurns` :287 and `ReminderFixture.RemoveTurns` :160.

**Story 6.4: the real IncidentManager**
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - the class doc's line :30 says "409 not_dismissible (the owner's refusal)";
  - :552-586 is `DismissIncident`; :581-582 list `not_allowed` among the 500s;
  - :113 is `MESSAGENOTDISMISSIBLE`.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls:1120-1146` `Command`: an AD-15 move it refuses is `not_allowed` (:1143), with a developer `Message`.
- The spine's Conventions:
  - REST row: "409 `not_dismissible` (`POST /incidents/:ref/dismiss` that `IncidentManager` refuses)";
  - Incident commands row: "`Message` is developer text, and the words users see are their channel's".
- `src/ocutalon/cls/OcuTalon/Test/Web/DismissApi.cls` (area Web, lane-b, `image`):
  - :1-23 is the header;
  - :59 and :78 are the class-wide `Use`/`Restore` of `Test.Demo.IncidentManagerDouble`;
  - the tests: :89 `TestOwnOpenIncidentCloses`, :117 `TestResolvedIncidentCloses`, :131 `TestBreakFeedAvailableAgain`, :157 `TestRefusedIs409`, :183 `TestDoubleAppliesAD15DismissRows`, :217 `TestOwnerErrorIs500`, :230 `TestOtherSessionsIncidentIs404` and :268 `TestBodyIsIgnored`;
  - :359-365 read the double's commands, and :388 is `CommandsInHeaders`.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Incident.cls:70-71,133-141`: the closed view's requests are `RequestRefs` entries whose `ApprovalRequest` names the incident. A request's `result` is that of its ended `FixRun` (`OfRequest`).
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`:
  - :87 `Incident`, :108 `Approval`, :236 `Pairing`, :337 `Clean`, :433 `Headers` and :456 `Between`.
  - `Test/Live/Payloads.cls:345` `Run` is a private FixRun builder, the sibling to lift.
- `Test.Demo.IncidentManagerDouble` stays unchanged. `Test/Demo/BreakFeedProduction.cls:82` (Story 4.3's isolation double) uses it.
- `web/e2e/answers/close-loop.spec.ts` (`live:answers`, CI group `browser`, about 335 s locally):
  - :26-35 is the header; :75-82 the beforeAll/afterAll swap;
  - C1 :170 (`doubleCommands` :238), C5 :376 (:418), C10 :600 (:613);
  - the other cases render published fixture payloads.
- `web/e2e/support/iris.ts`: :969 `seedIncident`; :990-1022 `useIncidentManagerDouble`, `restoreIncidentManager` and `doubleCommands`, used only by close-loop. `irisScript`, `chk` and `quoted` are the pattern.
- `docker/tests/test-answers.sh:6` describes the double.

**Story 10.3: R2b (`live:online-demo`, CI group `install-fresh`)**
- `web/e2e-online/resume.spec.ts`:
  - :41 is the local `readState` (epoch, chat, session);
  - :104 is R2, which seeds `Fixture.Pairing` at :122 and reads the row at :173;
  - :187 is `notBuilt('R2b …', '10.3')`, and :188 R2c, which stays.
- `Web/Api.cls:765-773`: `/state`'s `telegram` block sets `paired` and `displayName` from `Ownership.Pairing`, even with `included` false.
- `docker/tests/test-online-demo.sh:40` lists R1, R2, R4 and R5. No script counts its skips.

**Stale texts**
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Fallback.cls:193`: "until Story 1.8". `Classify` still says `error`, and the broken session is Decide's (`Decide.cls:696-699`).
- `src/ocutalon/cls/OcuTalon/Schedule/HeartbeatIn.cls:10`: "until Story 5.6". The guard stays.
- `src/ocutalon/cls/OcuTalon/Test/Tools/Reminders.cls:4-5`: "a stub until … Story 2.3, and ReminderOps until Epic 8". The double stays by design.
- `web/e2e/support/approvals.ts:7-8`: "the demo path's steps 4 and 5 … until Epic 11 turns it on". Only `answers.spec.ts` and `close-loop.spec.ts` import it.
- `release/demo-host-checks.md:45` H6: "(steps 4 and 5 wait on Story 11.1)". `test-online-host.sh:851-897` parses only each row's presence, its status, ASCII and no host details.
- `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls:512` ("until Story 4.1") is Epic 15's file, so it is left.

**DW-376 (`Test/Schedule/Heartbeat.cls`, lane-b, `image`)**
- :65 `RUNSECONDS = 75` ("RunNow takes up to a minute").
- :287-304 `TestStoppedThenStarted`: `RunNow` at :303, then `WaitRuns(historyMark, RUNSECONDS)` at :304.
- :830-837 `WaitRuns` polls `%SYS_Task.History` each second and skips "Task has expired" notes (:810).
- The Task Manager runs RunNow's run at its next pass, at a minute boundary (inference: Story 8.1's measurements). InterSystems' own code follows `RunNow` with `##class(%SYS.Task).WakeTASKMGR()` (`irislib/%ZHSLIB/Services/TaskUpdateRolesAndResources.cls:188-189`).
- The earlier `TestSendFails` suspends the task by a direct save (:678-708). An expiry note may then take one pass (inference).

**DW-396**
- `docker/tests/lib-live.sh:111-137` (read only) `live_lock_claim`:
  - `started=$SECONDS`, then a `date -u` fork and the create try;
  - the deadline check (`LOCK busy`) comes before the `LOCK waiting` line.
  - With `OCUTALON_LOCK_WAIT=1`, a first try that crosses a whole second prints busy with no waiting line.
- `ci/warm.sh:54-55` derives the warm claim from that text.
- `docker/tests/test-ci-warm.sh`:
  - :1109-1112 (claim case) and :1260-1262 ('up beside a held warm-iris.lock') use `WAIT=1`;
  - `up_run` and `claim_run` are the drivers;
  - the other `WAIT=1` cases take the lock on the first try.
- `docker/tests/test-lib-live.sh:552` uses 2 for its own case.
- The script runs in hosted `checks` (`CHECK_SCRIPTS`), about 27 s in CI.

**DW-415 (Playwright 1.64.1, `retries: 0`)**
- Both failures were at `web/e2e/sign-in/helpers.ts:44` (`fillSignIn`'s `page.goto(path)`).
- The other shared navigation sites: `web/e2e/support/trace.ts:127` (`openTrace`), and `web/e2e-online/support.ts:54` (`signInFromSplash`), :112 (`openTraceTab`) and :121 (`expectTraceSignIn`).
- 40 direct `goto` calls in specs stay as they are (Design Notes).
- `route.abort` has no network-changed code, so the reproduction is hermetic.
- `web/package.json:26` is `node --test scripts/*.test.mjs`, run by the hosted `web` job on Node 24 (`ci.yml:77,90`).
- Measured at plan time, Node v26.8.1: a `node --test` `.mjs` imports a `.ts` with only `import type` (type stripping).

## Tasks & Acceptance

**Execution:**
- `(Task 0, measure)`. Record each result under Verification:
  - (a) DW-376. In a temporary class `OcuTalon.Test.Schedule.ZzRunNowProbe`, run on the warm stack and deleted before the commit:
    - Three times without the wake and three times with it: wait until the clock is at :05 to :25 of a minute, take a History mark, `RunNow` the heartbeat task (and `WakeTASKMGR`), then poll History for up to 30 s. Record each latency.
    - Expected: no run within 30 s without the wake, and at most 5 s with it.
    - If the run comes within 5 s without the wake too, the boundary theory is wrong. Add no wake; keep only the ceiling and the diagnostics below.
  - (b) On ThreadProduction's first warm run, record which requests carried the marker: the triage request, the turn request and the retry. Set the `Arm` count so that the turn's first Chat request gets the 400 and the retry gets the text (2 when triage also matches).
  - (c) Before the C1 rework, record whether the real closed view of a fixture incident keeps C1's band. Expected: only with `RequestRefs`, a done approval row naming the incident, and an ended FixRun.
- `src/ocutalon/cls/OcuTalon/Test/Digest/Store.cls` -- add public `ClassMethod KeptProblems(itemId, owner, decisionRef, channel, summary, before, after) As %String`. It returns the "; "-joined row problems of `AssertKept` (count 1, SessionRef, DecisionRef, Channel, Summary, RecordedAt format and range), else "". `AssertKept` calls it (Rule 2).
- `src/ocutalon/cls/OcuTalon/Test/Core/RoutingProduction.cls` -- digest ItemIds come from `Test.Digest.Store.NewRef()`. The digest branch then:
  - waits `Observe.WaitProcessed(trace, "OutcomeRouter", "DigestStore", 1, WAIT)`;
  - asserts `KeptProblems(...)` = "" (Summary "zz Dana: Invoice", Channel `mailbox`, `after` taken after the wait) and no live event since the send.
  - `OnAfterAllTests` also calls `Test.Digest.Store.Clean()`.
  - Update the header.
- `src/ocutalon/cls/OcuTalon/Test/Core/AnswersInProduction.cls`:
  - Lift :308-336 into a private `HeldCall(session) As %String` (it answers the ref). `TestGateStepAndHeldCallReachTheStream` calls it.
  - Add `TestHeldCallExpiresOnTheStream`: `HeldCall`, then `Test.Bridge.Approval.Age(ref,86460,-60)`, delete `Approval.LiveHold(ref)`'s hold, `Install.Step.Reconcile.Run()`. Assert:
    - the second approval event on the stream is ref with state `expired`;
    - the answer endpoint answers 409 `expired`.
  - Add `TestHeldCallCancelledOnTheStream`: `HeldCall`, then `Approval.Cancel` with the arguments `SessionOps.EndApprovals` passes. Assert:
    - the second event is state `cancelled`;
    - the endpoint answers 404, with the body of an unknown ref.
  - `TestExpiredRequestAnswersExpired` also asserts one `approval` event, state `expired`, for the request.
  - Clean up with `TrackOwner` and `Test.Bridge.Approval.Clean()`. Update the header.
- `ci/mock/scenarios/A/thread-broken-retry.json` -- new, with match `marker` `thread-broken-retry` and two replies:
  - the 400 of `A/invalid-input.json`, verbatim;
  - a 200 text "The CI mock answered the retried turn.".
- `src/ocutalon/cls/OcuTalon/Test/Core/ThreadProduction.cls` -- remove the swap: `UseDouble`, every `DecideDouble` call, and `TestRealDecideAfterTheRestore`.
  - Point the keys as ReminderChat :53-121 does:
    - `ReadyReason`, then `PointKeys` in `OnBeforeAllTests`;
    - `RestoreKeys`, `KeysAre(##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER)` and `WaitRecords` in `OnAfterAllTests`, where a failure fails the class;
    - `SessionMark`/`DropSince` and the `UsageCapped` kill per test.
  - The thread tests send unmarked messages, answered by `A/chat.json`. They keep every thread and header assertion, and also assert:
    - the reply text;
    - `StepProblems(turnRef, thread, $LB("Listing the productions"), $LB("list_productions"))` = "" for each turn;
    - each turn's triage and turn Decision rows have the thread as `TraceSessionId`, with a decision event each.
  - `TestBrokenRetryThroughTheProduction` uses the marker `thread-broken-retry:<Number>` armed through `Mock.Arm` (Task 0 b). It asserts:
    - the retry is a new Decide call under `RetryItemId` = the turn's ItemId, in the day's thread;
    - the reply is the scenario's text;
    - the mock's log holds the 400 and the retry request.
  - It clears the countdown after. The clean-up adopts the broken attempt's Decision row (`ItemIdKindIndexOpen`) and removes the retry ItemId's AgentSteps and Usage rows.
  - Update the header.
- `src/ocutalon/cls/OcuTalon/Test/Core/DecideDouble.cls` -- remove `Step`, its call and the swap docs. The class doc says what the double serves now.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - `DismissIncident`: `not_allowed` answers `Fail(409, "not_dismissible", ..#MESSAGENOTDISMISSIBLE)`;
  - `failed` and `unknown_command` stay 500, and the branch for any other outcome is unchanged;
  - fix the docs at :30 and :552-559.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` -- add public `FixRun(incident, request, fields) As %Integer`:
  - lifted from `Test/Live/Payloads.cls:345` `Run`, with `EndedAt` set unless `fields` gives it;
  - `Clean` removes the fix runs of the run's fixture incidents.
- `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls` -- `Run` calls `Fixture.FixRun`.
- `src/ocutalon/cls/OcuTalon/Test/Web/DismissApi.cls` -- no class-wide swap. Commands are read from the CommandsIn→IncidentManager headers' `IncidentCommand` bodies (verb, IncidentRef, SessionRef, origin), extending `CommandsInHeaders`.
  - `TestOwnOpenIncidentCloses` seeds `RequestRefs`, a done `Fixture.Approval` and a `Fixture.FixRun`, so that the closed view carries the request.
  - `TestRefusedIs409` holds the "dismiss refused" row for `awaiting_approval` and `fixing` on the real item.
  - `TestDoubleAppliesAD15DismissRows` becomes `TestRealItemAppliesAD15DismissRows`, through `Commands.Submit`.
  - `TestOwnerErrorIs500` alone swaps the double in, and restores it in the test, also after a failure. It holds the error-status case and the refusal with no Message (`MESSAGENOTDISMISSIBLE`).
  - Update the header.
- `web/e2e/support/iris.ts`:
  - remove `useIncidentManagerDouble`, `restoreIncidentManager` and `doubleCommands`;
  - add `incidentCommands(ref): Promise<{verb, session, origin}[]>`, which reads the CommandsIn→IncidentManager headers' bodies (oldest first);
  - add `seedFixRun(incident, request, fields)` (`Fixture.FixRun`).
- `web/e2e/answers/close-loop.spec.ts` -- drop the beforeAll/afterAll swap; read `incidentCommands` instead of `doubleCommands`. C1 seeds what Task 0 (c) names. Update the header.
- `docker/tests/test-answers.sh` -- in the header, the real IncidentManager replaces the double.
- `web/e2e-online/resume.spec.ts` -- delete :187. `readState` also gives `telegram`, and R2 asserts after the resume that `telegram.paired` is true and `telegram.displayName` is "Zz chat". Its doc names R2b.
- `docker/tests/test-online-demo.sh` -- the header at :40 names R2b.
- `docker/tests/test-ci-warm.sh`:
  - `OCUTALON_LOCK_WAIT=3` at :1109 and :1260;
  - add the case 'up beside a held warm-iris.lock, slow first try'. It puts a `date` on `PATH` that sleeps 1.2 s on its first `-u` call only (a marker file in the case's folder), then runs `/bin/date`.
    - Expected: `LOCK waiting` before `LOCK busy … '<holder>'`, exit 75, and nothing started.
- `web/e2e/support/navigate.ts` -- new, with no runtime import. `gotoSettled(page, url, options?)`:
  - calls `page.goto(url, options)`;
  - when the error message matches `/net::ERR_NETWORK_CHANGED\b/`, logs `NAV retry <url>` and calls `goto` once more;
  - rethrows anything else.
- `web/e2e/sign-in/helpers.ts`, `web/e2e/support/trace.ts`, `web/e2e-online/support.ts` -- the five shared sites named in the Code Map (DW-415) call `gotoSettled`.
- `web/scripts/goto-settled.test.mjs` -- new. It holds the matrix's three goto rows on a fake page (calls, options passed, the line logged), and a source pin that each of the five sites navigates through `gotoSettled`.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls` -- `TestStoppedThenStarted`:
  - `WakeTASKMGR()` after `RunNow`, unless Task 0 (a) found no boundary wait;
  - the stopped-production wait uses a new `RUNNOWSECONDS = 90`;
  - on a miss, its message names the History rows since the mark (Name, Error, LastStarted) and the task's Suspended, LastFinished and TimeNextScheduled;
  - the passing message gives the seconds it took;
  - fix the doc of `RUNSECONDS` and the test.
- Stale texts:
  - `Test/Bridge/Fallback.cls:193`'s label: "Invalid input is an error: Classify gives it no reason of its own";
  - `Schedule/HeartbeatIn.cls:10`: "(as Lane A's OcuTalon.Checks.Process did until Story 5.6)";
  - `Test/Tools/Reminders.cls:4-5`: state that the double stays as Story 1.10's recording double;
  - `web/e2e/support/approvals.ts:7-8`: the answers unit's specs only;
  - `release/demo-host-checks.md:45`: "(steps 4 and 5 were not built at that deploy)".

**Acceptance Criteria:**
- **AC1 (Story 1.12).** Given a digest ItemDecision sent into the running OutcomeRouter, plain or keyed, when DigestStore handles it, then:
  - one `Digest.Data.Item` row holds its ItemId, with the session's Ref, the DecisionRef, Channel `mailbox`, Summary "zz Dana: Invoice" and a RecordedAt between the send and the wait's end;
  - no live event is published;
  - the class leaves no digest row behind (`TestEachOutcomeThroughTheRouter`).
- **AC2 (Story 2.8).** Given a request the real gate raised for a held call:
  - when its re-armed hold's timer expires it, then the session's stream gets an approval event with state `expired` and the endpoint answers 409 `expired`;
  - when `Approval.Cancel` cancels it, then the stream gets state `cancelled` and the endpoint answers 404;
  - when a request past its expiry is answered, then the stream gets an `expired` event.
- **AC3 (Story 2.9).** Given the running production with no Decide swap and the runners pointed at the CI mock, when a session sends two messages on one day, then:
  - both turns are answered by the real Decide with the mock's reply;
  - every header of the session's SuperSession, both turns' Decide requests and responses, each decision's agent steps and the Outbound to Notify are in one trace session T (the first Item's id);
  - the four Decision rows have T as `TraceSessionId`;
  - after midnight, a new thread starts;
  - no other header id is used as a session id.
- **AC4 (Story 2.9, DW-112).** Given `thread-broken-retry` armed, when the turn's first Chat request gets "Invalid input", then the turn is retried as a new Decide call under `RetryItemId` in the day's thread and gets the scenario's text.
- **AC5 (Story 6.4).** Given the real IncidentManager item, when `POST /v1/incidents/:ref/dismiss` runs, then the matrix's three dismiss rows hold (`Test.Web.DismissApi`). The class swaps the double in only inside `TestOwnerErrorIs500`.
- **AC6 (Story 6.4, browser).** Given the page with no IncidentManager swap:
  - when C1 and C5 press Dismiss, then the card compacts to its headline and band (C1), or the incident closes and Break the feed is active again (C5);
  - in both, `incidentCommands` shows one dismiss with origin `web_user`;
  - C10's press on another session's incident submits nothing (`live:answers`).
- **AC7 (Story 10.3).** Given R2's resumed session with its fixture pairing, when the page reads `/state`, then `telegram.paired` is true and `telegram.displayName` is "Zz chat", and `resume.spec.ts` has no R2b `notBuilt` (`live:online-demo`).
- **AC8 (the inventory).** Given the tree, when `git grep -n -i "notBuilt(\|until Epic 11" -- src web docker ci release` runs, then:
  - every call of the spec helper `notBuilt(title, story)` names a story of Epic 12, 30 or 31, or is one of the four online step lines of `web/e2e-online/demo-path/demo-path.spec.ts` that Story 11.7 turns on. The helper's definition, `Web.Api.NotBuilt` and comments are not calls;
  - "until Epic 11" appears nowhere.
- **AC9 (DW-376).** Given the stopped production, when `TestStoppedThenStarted` asks for the run, then its History row is seen within `RUNNOWSECONDS`. Task 0 (a)'s six latencies are the deterministic reproduction: with no wake, the run waits for the minute boundary; with the wake, it does not.
- **AC10 (DW-396).** Given a held `warm-iris.lock` and a first lock try that takes 1.2 s, when `ci/warm.sh up` runs, then it prints `LOCK waiting` before `LOCK busy` and exits 75 (`test-ci-warm.sh`).
- **AC11 (DW-415; integration: consumers `fillSignIn`, `openTrace`, the online splash and trace helpers).** Given the matrix's goto rows, when `gotoSettled` navigates, then each row holds (`goto-settled.test.mjs`), and every shared sign-in navigation goes through it (`live:sign-in` part 1 passes).

### Review Findings

Code review, 2026-11-01 UTC (four layers on the full tier: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 33 rows, 8 entries after grouping; high 0, medium 1, low 7; every entry patched; nothing deferred or ledgered).

- [x] [Review][Patch] (medium; fix-risk low: a test-side call to the approvals area's own public Reconcile declaration; footprint in-story; Rule 19 hermeticity) `TestHeldCallExpiresOnTheStream` ran the whole Reconcile step, whose Web area sweeps every `queued` or `running` Turn of the namespace (`Conversation.Sweep`). `HeldCall` leaves its fixture turn `running`, so the sweep ran this class's fixture turns again (and any other class's leftovers) through the real Conversation and Decide, leaving rows the clean-up does not name. It now calls `OcuTalon.Install.Step.Approvals.Reconcile()` (`Bridge.Approval.Reconcile`, the declaration that the Reconcile step calls for this area), which re-arms the hold as AC2 requires. Decided in-stage: the Task named `Install.Step.Reconcile.Run()`, and its intent (the re-armed hold's timer expires the row) is unchanged. [src/ocutalon/cls/OcuTalon/Test/Core/AnswersInProduction.cls:343]
- [x] [Review][Patch] (low; fix-risk low; in-story) `DismissApi.OnAfterAllTests` discarded the status of the backstop `IncidentManagerDouble.Restore()`, so a failed restore left later classes on the double without a word. It writes the error again, as before this story. [src/ocutalon/cls/OcuTalon/Test/Web/DismissApi.cls:78]
- [x] [Review][Patch] (low; fix-risk low; in-story) The `DismissApi` class doc and `TestOwnerErrorIs500`'s doc said "the two answers the real item never gives", but the test now holds three. Both docs name the three. [src/ocutalon/cls/OcuTalon/Test/Web/DismissApi.cls:8,209]
- [x] [Review][Patch] (low; fix-risk low; in-story; Rule 2) `CommandList` repeated `CommandsInHeaders`' header query instead of extending it. Both now read the private `IncidentManagerHeaders(trace)`. [src/ocutalon/cls/OcuTalon/Test/Web/DismissApi.cls:369,410]
- [x] [Review][Patch] (low; fix-risk low; in-story) The ThreadProduction docs said `thread-broken-retry` answers only the turn's first Chat request with the 400. As `ARMED = 2` and Task 0 (b) record, the triage request gets it too, and the docs now say so. That the triage also breaks is the spec's own choice (Task 0 (b)). [src/ocutalon/cls/OcuTalon/Test/Core/ThreadProduction.cls:15,208]
- [x] [Review][Patch] (low; fix-risk low; in-story) `DismissIncident`'s doc gave the developer-text rationale for every outcome, then excepted any outcome with a Message, which contradicted itself. It now says `not_allowed` is MESSAGENOTDISMISSIBLE, and that any other outcome, which the real IncidentManager never gives to a dismissal (`Watch/IncidentManager.Command` answers unknown_command, not_found, failed, not_allowed or closed), carries its own Message. The branch itself is unchanged, as the spec's Task orders, and is closed `wontfix-theoretical`: it would become real if a CommandsIn owner answered a dismissal with another outcome that carries developer text. [src/ocutalon/cls/OcuTalon/Web/Api.cls:559]
- [x] [Review][Patch] (low; fix-risk low; in-story; Rule 19) No assertion pinned AC1's third bullet, "the class leaves no digest row behind". `RoutingProduction.OnAfterAllTests` now fails the class when a `Digest.Data.Item` row of the fixture prefix is still there after `Test.Digest.Store.Clean()`. The mutation is recorded under Verification. [src/ocutalon/cls/OcuTalon/Test/Core/RoutingProduction.cls:30]
- [x] [Review][Patch] (low; fix-risk low; bookkeeping) `sprint-status.yaml`'s `last_updated` had gone backwards (10-31 01:21 for a write at 2026-11-01T01:21Z). The review's `sprint_plan.py generate` sync rewrites it. [_bmad-output/implementation-artifacts/sprint-status.yaml:163]

Verified after the patches: on slot A, the five changed classes compile. On warm stack `e11s9cw` (lane A), `AnswersInProduction`, `DismissApi` and `RoutingProduction` pass. `test-class-rules` and `test-boundaries` pass. The stack is torn down, and lane-a holds no lock.

**Rejected** (21 of the 33 rows; the other 12 are the eight entries above):
- `false` The spec's `status: 'done'` disagrees with sprint-status `review` (blind, edge, acceptance): the frontmatter is bmad-build-auto's machine state, and the review's verdict goes to sprint-status.
- `false` `TestHeldCallCancelledOnTheStream` cancels before the hold exists (edge): `Approval.Cancel` moves the row under its lock and polls up to TASKSECONDS for the hold's task. The verification-gap layer checked this and filed it as not a finding (two rows).
- `false` `Payloads.Run`'s assertion cannot fail when `FixRun` throws (edge): a throw errors the test, which is a loud failure.
- `false` The slow-date shim's `/bin/date` is missing on some hosts (edge): `/bin/date` exists on macOS and, with merged `/usr`, on the Ubuntu runners.
- `false` C10's "submits nothing" has no mutation line (verification-gap): Verification already records the route-level pin (the review-stage mutation without the visibility check, against `TestOtherSessionsIncidentIs404` and `TestBodyIsIgnored`).
- `low` The cycle log's `hold_complete` names `2da3f0ba` twice (blind): this is the lead's record, and this stage writes no cycle-log entry. It is passed to the lead.
- `low` The previous Review paragraph counts a row that changed nothing as a patch (blind): fixing it would edit the spec's own historical record.
- `low` AC9's wake has no assertion (blind, verification-gap): `by-design`. AC9 names Task 0 (a)'s six latencies as the reproduction, and the previous review adjudicated this. A latency bound on the real Task Manager would add a timing assertion to a flake fix. Removing the wake costs at most 60 s and no flake, because the 90 s ceiling is polled.
- `low` C1 seeds a `done` row while the first payload says `executing` (blind): `by-design`. Task 0 (c) and the C1 task name the `done` row, and the page draws from the published payloads.
- `low` The Message branch pins developer text reaching the user (blind, acceptance; the code part of the doc entry above, the same two rows): the branch is spec-bound ("the branch for any other outcome is unchanged"), and the real item never reaches it. Its doc is patched above.
- `low` `WaitLiveHold` and the heartbeat's `took` do not handle the `$ZHorolog` midnight wrap (edge, two rows): the wait follows the waits of its siblings (`Test.Bridge.Approval`, `Test.Schedule.Heartbeat`). A hang needs a run that crosses midnight and a hold that never appears. The fix adds a guard.
- `low` `Fixture.FixRun` with an empty incident (edge): every caller passes a seeded incident, and the fix adds a guard.
- `low` `RemoveRetries` ignores a failed `Ownership.Turns` (edge): a failed read fails loudly or leaves an empty list in a class that has just run the turns. Unlikely, and the fix adds a branch.
- `low` The broken-retry log count does not filter on the label (edge): the class runs alone under the lane lock, and nothing else sends this scenario after the mark.
- `low` AC3's steps are asserted for the turn decision only (acceptance): `by-design`. The Task names `StepProblems` per turn, and every SuperSession header is asserted in T.
- `low` `TestOwnOpenIncidentCloses` was renamed `TestOwnIncidentCloses` (acceptance): nothing refers to the old name, and the Verification lines use the new one.
- `low` The slow-date marker is in the script's work folder, not the case's (acceptance): it is removed before the case, and the behaviour is the same.
- `low` The DW-415 source pin matches text (verification-gap): the previous review adjudicated it, and `live:sign-in` part 1 ran through the wrapper.
- Grouped into the entries above: the restore status (blind and edge, two rows), last_updated (blind, edge and acceptance, three rows), the Message-branch doc (blind and acceptance, two rows), the triage 400 doc (blind) and the AC1 clean-up (verification-gap).

## Spec Change Log

## Review Triage Log

### 2026-10-31 -- Review pass
- verdicts: 27 findings -- high 0, medium 3, low 18, false 4, maybe-false 2
- findings:
  - `[low]` `[reject]` Blind: the slow-date shim could be spent on an earlier `date -u` -- the lock try's `date -u` is the first in `live_lock_claim`, and the planned mutation (`OCUTALON_LOCK_WAIT=1`) went red with `LOCK busy` after 1 s, which only happens when the delay lands in the lock's first try.
  - `[low]` `[reject]` Blind: no comment says why other cases keep `WAIT=1` -- those cases take the lock on the first try (Code Map); a comment is not a defect.
  - `[low]` `[patch]` Blind and Edge: `bad >= 1` is weaker than `ARMED = 2` -- `ThreadProduction.TestBrokenRetryThroughTheProduction` now asserts `bad = ARMED`.
  - `[low]` `[reject]` Blind: `WAIT` 30 to 60 undocumented -- the parameter's doc states what it waits for; the value is an implementation detail.
  - `[false]` `[reject]` Blind: `DismissIncident` still passes another outcome's Message to the user -- the spec (Tasks) says the branch for any other outcome is unchanged, and the route's doc states it.
  - `[medium]` `[patch]` Blind and Edge: `TestOwnerErrorIs500` has no backstop if it dies between `Use` and `Restore` -- `DismissApi.OnAfterAllTests` calls `IncidentManagerDouble.Restore()` (a no-op when nothing was saved).
  - `[low]` `[reject]` Blind: the test name `TestOwnerErrorIs500` no longer matches all its cases -- the spec names the test.
  - `[low]` `[reject]` Blind: `incidentCommands` scans every CommandsIn header -- CI stacks are fresh; the query already filters on class and type; the cost is milliseconds.
  - `[low]` `[reject]` Blind and Edge: other `page.goto` sites keep no retry -- declined in the spec's Ledger (DW-415) with `reopen_if`.
  - `[low]` `[patch]` Blind: `body()` in `goto-settled.test.mjs` slices to -1 when the terminator is missing -- it now asserts the terminator is found.
  - `[low]` `[reject]` Blind: no Node version guard for type stripping -- CI runs Node 24 (spec Code Map); the failure would be loud.
  - `[false]` `[reject]` Blind: `DecideDouble` doc still implies a production-item mode -- the doc says it has no session as a shadow instance, and `Write` still reads `%SessionId`.
  - `[low]` `[reject]` Edge: `CommandList` could open a body of another class -- the headers are CommandsIn to IncidentManager, and the Matrix and the browser reader filter on class; a different class there would be a product defect that other tests already catch.
  - `[low]` `[patch]` Edge: assert the countdown is spent -- covered by `bad = ARMED` and `good = 1`; no separate `Remaining` call added.
  - `[low]` `[reject]` Edge: `TestRealDecideAfterTheRestore` removed -- the spec (Tasks) orders its removal; the no-key fallback stays pinned by `Test.Bridge.Fallback`.
  - `[medium]` `[patch]` Edge and Verification-gap: the route's own-Message branch for an outcome other than `not_allowed` is untested -- `TestOwnerErrorIs500` has a third case (the double's default refusal of an awaiting_approval incident gives 409 with the double's Message); mutation recorded.
  - `[medium]` `[patch]` Verification-gap: AC9 and the `DismissApi`, AC3 record assertions and C10 lack `mutation:` lines -- mutation lines added under Verification (route without Submit, route without the visibility check, Message branch, test-side thread and steps mutations, the Task 0 (a) no-wake runs for AC9).
  - `[low]` `[reject]` Verification-gap: `TestStoppedThenStarted` asserts no latency, so the wake is unpinned -- a latency bound is not deterministic (a lucky run passes either way); Task 0 (a)'s six latencies are the spec's reproduction (AC9), and the passing message gives the seconds.
  - `[low]` `[reject]` Verification-gap: the source pin does not execute the five real sites -- the pin names each site; `live:sign-in` part 1 ran through the wrapper; wrong-argument wiring is unlikely.
  - `[false]` `[reject]` Verification-gap: `TestHeldCallCancelledOnTheStream` acts before the hold exists -- `Approval.Cancel` moves the row's state under its lock and cancels the hold's task only when there is one; the test passed warm and fresh.
  - `[false]` `[reject]` Verification-gap: `DecideDouble.Step` removal might break `SettingsOps` -- its "zz step" strings belong to `SettingsOpsProbe`, not to `DecideDouble`.
  - `[low]` `[reject]` Intent: Story 6.4's 409 is pinned in-process, not over HTTP -- AC5 names `Test.Web.DismissApi`, and the browser cases C1, C5 run the real item.
  - `[low]` `[reject]` Intent: R2b is two assertions in R2 -- the spec's task says exactly this.
  - `[low]` `[reject]` Intent: DW-396's new case would not fail with the old wait of 1 s -- it is the point: the mutation with `OCUTALON_LOCK_WAIT=1` goes red (deterministic).
  - `[maybe-false]` `[reject]` Intent: DW-376 has no simulation of a slow Task Manager -- the Task 0 (a) runs are the reproduction (AC9).
  - `[low]` `[reject]` Intent: DW-415 is at five shared helpers, not every `goto` -- the Ledger declines the rest.
  - `[maybe-false]` `[reject]` Intent: doc and comment edits change no behaviour -- a note, not a finding.

## Design Notes

**Architecture decisions.**

| AD | What it governs here |
| --- | --- |
| AD-1 | The dismissal is a command through `Commands.Submit` to CommandsIn. |
| AD-4 | Another session's incident is 404, and nothing is submitted. |
| AD-8 | A broken session is retried once in a fresh seeded session. |
| AD-9 | Agent steps come from the real runners. |
| AD-11 | Raise, the hold's timer, Expire and Cancel; the row is the truth. |
| AD-12 | Approval and incident events on the session's stream. |
| AD-15 and Conventions (REST, Incident commands) | `not_allowed` is the owner's refusal: 409 `not_dismissible`, in the channel's words. |
| AD-18 | The heartbeat task and the Task Manager. |
| AD-22 | The CI mock, a new marker scenario under `A/`, and the per-test countdown. |
| AD-26 | One trace thread per session per day. |
| AD-29 | The turns-on clauses, and the Epic 11 exception for Lane B's files. |
| AD-30 | OutcomeRouter to DigestStore. |
| AD-33 | Each item keeps its owner; the tests never write the owners' tables. |

**Integration ACs and links (Rule 1/2).**

| Link | Who |
| --- | --- |
| Consumes | the running OcuTalon.Production (OutcomeRouter, DigestStore, Decide, the runners, ApprovalHold, IncidentManager, CommandsIn, BridgeSink), the CI mock, and `RunnerFixture`'s key and step helpers |
| Consumes | `Test.Bridge.Approval`'s `Age`, `TrackOwner` and `Clean`, read only (if Epic 30 changes them, its merge gate re-runs this class) |
| Consumed-by | `gotoSettled`: `fillSignIn`, `openTrace` and the three online helpers (AC11), and later specs |
| Consumed-by | `Test.Digest.Store.KeptProblems`: `AssertKept` and RoutingProduction (AC1) |
| Consumed-by | `Fixture.FixRun` and `seedFixRun`: DismissApi, close-loop C1 and `Live.Payloads` |

**Extend, don't copy (Rule 2).**
- `KeptProblems` comes out of `AssertKept`, and `Fixture.FixRun` out of `Payloads.Run`.
- `HeldCall` comes out of AnswersInProduction's own test.
- `incidentCommands` follows `iris.ts`'s `irisScript`/`chk` readers.
- The expiry seam reuses `Test.Bridge.Approval.Age` and the Reconcile step, as `TestTimerExpires` does.
- **A copy, with its reason.** ThreadProduction's key pointing repeats ReminderChat's ten lines that call `RunnerFixture`'s shared helpers. About 20 test classes compose them the same way. A base-class mechanism would be a real unification only with ReminderChat (Story 11.7's file, in flight) and the others moved too.

**Inventory (re-checked against the tree; AC: "every check left off … except Epic 30 or 31").**
- Turned on here: 1.12 (AC1), 2.8 (AC2), 2.9 (AC3, AC4), 6.4 (AC5, AC6) and 10.3 (AC7).
- Already on:
  - 2.7: real Decide in `RoutingProduction:6-10` and `mailbox.spec.ts`. `Test.Core.Intake` keeps the double by design, as a slot test.
  - 2.10: `banners.spec.ts:181` B1.
  - 4.5: `notice.spec.ts:473` N11, on the real Intake and Decide. Its decision is the no-key fallback; mock decisions to the phone are MB4 and demo step 4.
  - 4.6: MB2 and MB4 against the mock.
  - 8.4: `session/sign-out.spec.ts`, and `test-online-session.sh:21-23`.
  - 1.9: the real `Tools.Watch`. 1.10: the real gate. 9.2: incident cases in `eval/run.sh`.
- Doubles kept by design (no turns-on clause): 1.10's and 5.1's CommandsIn doubles, 4.3's IncidentManager double, 6.2's Approval API double, and 8.1's Checks double.
- Left to their epics: R2c (12.7), `telegram-*` (12.4, 12.7), the 31.x lines, and 2.8's replayed `approval.result` (30.3).
- The And-clause's step specs: the web steps have run since Story 11.1, and the online steps 2 to 5 are Story 11.7's (DW-221).

**Ledger (Rule 17).**
- Addressed:
  - DW-376 (AC9);
  - DW-396 (AC10);
  - DW-415 (AC11): both measured failures and every sign-in navigation.
- Declined, DW-415's 40 direct `goto` calls in specs. Converting them would change about 20 spec files for no observed failure, and widen every browser unit's fresh check. `reopen_if`: `ERR_NETWORK_CHANGED` at a `goto` with no `NAV retry` line.

**Decided in-stage.**
- **No split.** The title names both halves, they share no file, and a split would retitle the sprint key (Rule 5).
- **The dismiss route's `not_allowed` is 409 with `MESSAGENOTDISMISSIBLE`.** This is the spine's REST row and its Incident commands row ("Message is developer text"), with Story 6.4's vetoed V1 text, so no new user text.
  - Today a refused or repeated dismissal is a 500.
  - No product caller gets `not_allowed` from CommandsIn for `web_user`.
  - No test pins the 500.
- **close-loop's rendering cases (C2-C4, C6-C9) keep published fixture payloads.** They test how the page draws payload variants that the real path gives only on orchestrated failures. The real result is demo step 5's (Story 11.1). Only the dismissal goes to the real item.
- **The double stays in `TestOwnerErrorIs500`.** An error status, and a refusal with no Message, are owner answers the real item never gives.
- **`thread-broken-retry`'s text** is CI-mock-only and never shown to a user.
- **DW-376's ceiling is 90 s.** It allows a pass taken by an expiry note, plus one minute, plus 30 s for a slow host. It is polled, so a green run pays nothing.
  - `%SYS.Task.Resume` in `ResumeTask` is not adopted: whether it reschedules is unmeasured. The new diagnostic message decides it if DW-376 recurs.
- **DW-396 is fixed in the test.** `lib-live.sh` is Epic 12's file, and `ci/warm.sh` must keep deriving its claim from that text. A wait of 3 s leaves a 2 s first try before the waiting line can be skipped.
- **`demo-host-checks.md` H6:** the wording only, so the Planner's record stays true. The status column is unchanged.

**Contended paths (U14).** At plan time, no file planned here was in `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` for N = 15, 30, 12 or 13. Re-check before editing.

**CI budget (REL-4; inference until Epic 11's next CI run).**
- `image` (`shard:lane-b`; 28.8 min), about -60 to +40 s in all:
  - RoutingProduction +1 s;
  - AnswersInProduction +10 to 20 s;
  - ThreadProduction -15 to +30 s (four production updates gone; keys pointed; about six mock turns);
  - DismissApi -10 to -30 s (no class-wide swap);
  - Heartbeat 0 to -60 s (the wake).
- `browser` (`live:answers`; 28.8 min): -10 to -30 s.
- `install-fresh` (`live:online-demo`; 34.0 min, already over the soft line, with Story 11.7's swap planned): under +1 s.
- `shards-2` (Digest, Bridge.Fallback): about 0.
- Hosted `checks` +6 to 8 s, and hosted `web` under +1 s.

## Verification

`<A>` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=11 stage=implement'`.
- Tags: implement `e11s9i` and `e11s9iw`; QA `stage=qa` with `e11s9q` and `e11s9qw`; review `stage=review` with `e11s9c` and `e11s9cw`.
- `<scratch>` is the stage's own scratch folder.

**Run discipline:**
- Run from the epic-11 worktree root, in the foreground, with `timeout: 600000`. `ANTHROPIC_API_KEY` stays unset.
- One test call per message. Never re-submit after a client-side timeout.
- Every IRIS MCP call passes `server` `ocutalon-slot-a` and namespace `OCUTALON`.

**Shared surfaces:**
- the IncidentManager and Decide items' classes, which are no longer swapped class-wide;
- the runners' Config Store key entries, pointed during ThreadProduction;
- `Digest.Data.Item` prefix rows;
- `ApprovalRequest` rows and holds. The Reconcile step re-arms any orphaned hold;
- the dismiss route's 409 for `not_allowed`;
- `ci/mock/scenarios/A/`, and the countdown keyed by `thread-broken-retry:<n>`;
- every browser sign-in, now through `gotoSettled`;
- the heartbeat task's schedule;
- the lane lock folder in `test-ci-warm.sh`'s fixtures.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. The lead's shards, forward and `--reverse`, are the order check.

**Commands:**
- (once, first) `iris_server_info` on `ocutalon-slot-a` -- expected: build 154U.
  - Then load and compile there the changed `.cls` files -- expected: they compile. No test runs on the slot.
- (once) `<A> OCUTALON_RUN_TAG=e11s9i ci/iris.sh build` -- expected: the image and bundle build.
- (once, after `A/thread-broken-retry.json` is written) `<A> OCUTALON_RUN_TAG=e11s9iw ci/warm.sh up` -- expected: `LOCK acquired warm-iris`.
- (once) Task 0 (a): `<A> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e11s9iw ci/iris.sh class OcuTalon.Test.Schedule.ZzRunNowProbe` -- expected: six latencies recorded. Then delete the probe class.
- (loop) `<A> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e11s9iw ci/iris.sh class <C>`, one call each -- expected: `CLASS <C> passed`. C is each of:
  - `OcuTalon.Test.Core.RoutingProduction`, `OcuTalon.Test.Core.AnswersInProduction`, `OcuTalon.Test.Core.ThreadProduction`;
  - `OcuTalon.Test.Web.DismissApi`, `OcuTalon.Test.Digest.Store`, `OcuTalon.Test.Schedule.Heartbeat` (about 3 min).
- (once) the same warm call -- expected: passed. C is each of:
  - `OcuTalon.Test.Core.Intake`, `OcuTalon.Test.Core.ConversationTurns`, `OcuTalon.Test.Live.Payloads`;
  - `OcuTalon.Test.Demo.BreakFeedProduction`, `OcuTalon.Test.Bridge.Fallback`, `OcuTalon.Test.Web.Api`.
- (once) `<A> OCUTALON_RUN_TAG=e11s9i ci/iris.sh class <C>` for the six loop classes, one per call -- expected: passed on a fresh stack.
- (once) each of the following, one per call -- expected: every PASS:
  - `bash docker/tests/test-mock.sh`, which loads the new scenario;
  - `bash docker/tests/test-ci-warm.sh`;
  - `bash docker/tests/test-online-host.sh`;
  - `bash docker/tests/test-boundaries.sh`;
  - `bash docker/tests/test-class-rules.sh`;
  - `npm --silent --prefix web test`.
  - These are the parts of `ci/checks.sh` and the `web` job that the story touches.
- (once) `<A> OCUTALON_RUN_TAG=e11s9i ci/iris.sh live answers` -- expected: every case passes, about 335 s.
- (once) `<A> OCUTALON_RUN_TAG=e11s9i ci/iris.sh live online-demo` -- expected: passes. Add `OCUTALON_LIVE_DEADLINE=900` only if it dies of the deadline with no failed test.
- (once) `<A> OCUTALON_RUN_TAG=e11s9i ci/iris.sh live sign-in --part 1/2` -- expected: passes, with no `NAV retry` line.
- (once, last; also after a failure) `<A> OCUTALON_RUN_TAG=e11s9iw ci/warm.sh down`, then `<A> OCUTALON_RUN_TAG=e11s9i ci/iris.sh teardown` -- expected: no lock of this stage left in `lane-a`.

**Planned mutations (Rule 19).** For each: apply, see red, revert, check that `git status --short` and `git diff --stat` are unchanged, then green again. On the warm stack a red counts only when the class is green again on the same stack.

| AC | Mutation | Expected red |
|---|---|---|
| AC1 | the item `OcuTalon.Digest.Store` (`src/ocutalon/cls/OcuTalon/Digest/Store.cls`) saves no row | RoutingProduction, digest |
| AC2 | `Core/BridgeSink.cls` drops `approval.expired`, then, separately, `approval.cancelled` | the two new AnswersInProduction tests |
| AC3 | `PointKeys` removed from ThreadProduction | the thread tests (a no_key reply) |
| AC4 | Conversation does not retry a broken session | `TestBrokenRetryThroughTheProduction` |
| AC5 | the route's `not_allowed` back among the 500s | `TestRefusedIs409` |
| AC6 | the route answers 200 without `Commands.Submit` | close-loop C1, C5 |
| AC7 | `/state` sets `telegram.paired` to 0 | R2 |
| AC8 | a `notBuilt('x', '10.3')` line added | the AC8 grep names a 10.3 entry |
| AC9 | Task 0 (a)'s no-wake runs | latency up to the minute boundary (the reproduction) |
| AC10 | the slow-first-try case run with `OCUTALON_LOCK_WAIT=1` | `test-ci-warm.sh`: no `LOCK waiting` (deterministic) |
| AC11 | `gotoSettled` rethrows the first error; `helpers.ts:44` back to `page.goto` | `goto-settled.test.mjs` (the retry row; the source pin) |

**Implement-stage results (measured on warm stack `e11s9iw`, lane A, build 154).**
- Task 0 (a), DW-376: `RunNow` of the heartbeat task, started at second :05 to :16 of a minute, History polled up to 30 s. With `WakeTASKMGR` after it: a run seen after 0.26 s, 0.26 s and 0.26 s. Without the wake: no run within 30 s, three times (30.09 s, 30.08 s, 30.09 s). The boundary theory holds, so the wake is added.
- Task 0 (b): the requests that carried `[[mock:thread-broken-retry:<n>]]` were the triage request, the turn's first Chat request and the retry's Chat request. `Arm` count 2 gives the 400 to the first two and the text to the retry (`ARMED = 2`).
- Task 0 (c): the real closed view of a fixture incident (`Live.Payload.Incident.FromRow`) lists no request without `RequestRefs`; with `RequestRefs` and an approval row naming the incident it lists the request without a result; with an ended FixRun as well, the request carries its result. A request in `executing` with an ended run also carries the result, so C1 seeds a `done` row for the band's meaning.
- A recompiled class reaches a running production item only after the item restarts (disable and enable it); the product mutations below restarted DigestStore, ApprovalHold and Conversation after the reload.
- mutation: `Digest.Store` saves no row (item restarted) -> `RoutingProduction` `TestEachOutcomeThroughTheRouter` red (digest, plain and keyed); reverted, green.
- mutation: `BridgeSink.IsApproval` without `approval.expired` -> `AnswersInProduction` `TestHeldCallExpiresOnTheStream` and `TestExpiredRequestAnswersExpired` red; without `approval.cancelled` -> `TestHeldCallCancelledOnTheStream` red; reverted, green.
- mutation: `PointKeys` removed from `ThreadProduction.OnBeforeAllTests` -> all three thread tests red (no_key replies); reverted, green.
- mutation: `Conversation.Rebuild` never retries (item restarted) -> `TestBrokenRetryThroughTheProduction` red; reverted, green.
- mutation: `DismissIncident` with `not_allowed` back among the 500s -> `DismissApi` `TestRefusedIs409` red; reverted, green.
- mutation: `DismissIncident` answers 200 without `Commands.Submit` (throwaway image; the run was reduced to C1 and C5 by skipping the other 18 cases) -> close-loop C1 and C5 red; reverted.
- mutation: `/state` sets `telegram.paired` to 0 (full `live:online-demo`) -> `resume.spec.ts` R2 red at the paired assertion; reverted, `live:online-demo` green (mutated: 49 passed, 1 failed; reverted: 50 passed, 2 skipped).
- mutation: a `notBuilt('x', '10.3')` line added -> the AC8 grep names it; reverted.
- mutation: `gotoSettled` rethrows the first error -> `goto-settled.test.mjs` retry row and twice row red; `fillSignIn` back to `page.goto` -> the source pin names `fillSignIn`; reverted, 11 of 11 green.
- mutation: the slow-first-try case with `OCUTALON_LOCK_WAIT=1` -> `test-ci-warm.sh` has no `LOCK waiting` (LOCK busy after 1 s); reverted, green.
- mutation (review stage, Rule 19): `Web.Api.DismissIncident` answers 200 without `Commands.Submit` -> `DismissApi` `TestOwnIncidentCloses`, `TestResolvedIncidentCloses`, `TestBreakFeedAvailableAgain`, `TestRefusedIs409` and `TestOwnerErrorIs500` red; reverted, green.
- mutation (review stage): `DismissIncident` without the visibility check (submits for any ref) -> `DismissApi` `TestOtherSessionsIncidentIs404` and `TestBodyIsIgnored` red (the route-level pin of close-loop C10's "submits nothing"); reverted, green.
- mutation (review stage): `DismissIncident`'s last line always answers `MESSAGENOTDISMISSIBLE` -> `TestOwnerErrorIs500` ("with the Message that the outcome carries") red; reverted, green.
- mutation (review stage, test-side, because `Bridge/Process/Decide.cls` is Epic 30's): `AssertTurnRecords` expecting another tool and `thread + 1` -> `TestTwoTurnsOneThread` and `TestNewThreadAfterMidnight` red on the steps and the TraceSessionId assertions; reverted, green.
- mutation (AC9, DW-376): the no-wake runs of Task 0 (a) are the mutation of `WakeTASKMGR()` after `RunNow`: without it, no run within 30 s, three times. The test itself asserts only the 90 s ceiling, because a latency bound cannot be deterministic (a run that starts just before a minute boundary passes either way); the passing message gives the seconds it took.
- QA stage (Rule 19; warm stack `e11s9qw` and throwaways `e11s9q`, lane A; no test file was added, because every AC already has a discoverable pinning test; each mutation was reverted and the tree checked clean):
  - mutation (QA, AC1): `Digest.Store` skips `%Save` (DigestStore restarted) -> `RoutingProduction` `TestEachOutcomeThroughTheRouter` red for the plain and the keyed digest row; reverted, green.
  - mutation (QA, AC2): `BridgeSink.IsApproval` without `approval.expired` -> `AnswersInProduction` `TestHeldCallExpiresOnTheStream` and `TestExpiredRequestAnswersExpired` red; without `approval.cancelled` -> `TestHeldCallCancelledOnTheStream` red (Decide and ApprovalHold restarted); reverted, green.
  - mutation (QA, AC3): `PointKeys` replaced by OK in `ThreadProduction.OnBeforeAllTests` -> all three thread tests red; reverted, green.
  - mutation (QA, AC4): `Conversation.Rebuild` never retries (Conversation restarted) -> `TestBrokenRetryThroughTheProduction` red (five assertions); reverted, green.
  - mutation (QA, AC5): `DismissIncident` with `not_allowed` among the 500s -> `DismissApi` `TestRefusedIs409` red for awaiting_approval and fixing; reverted, green.
  - mutation (QA, AC6): `DismissIncident` answers 200 before `Commands.Submit` (the other 18 cases skipped for time) -> `live:answers` C1 and C5 red; reverted, the full unit 20 passed.
  - mutation (QA, AC7): `/state` sets `telegram.paired` to 0 (the project reduced to `resume.spec.ts`) -> R2 red at the paired assertion; reverted, `live:online-demo` 50 passed, 2 skipped.
  - mutation (QA, AC8): `notBuilt('x', '10.3')` appended to `resume.spec.ts` -> the AC8 grep names it; reverted, the grep names only Epic 12, 30 and 31 calls.
  - mutation (QA, AC9): `RUNNOWSECONDS` 90 to 0 -> `TestStoppedThenStarted` red with the new diagnostic ("history rows after the mark ... the task: Suspended 0, LastFinished ..."); reverted, green. Removing `RunNow` and the wake leaves the "task ran" assertion green, because the task's own schedule runs it within the 90 s ceiling: the wake is pinned by Task 0 (a) only, as recorded above.
  - mutation (QA, AC10): the slow-first-try case with `OCUTALON_LOCK_WAIT=1` -> `test-ci-warm.sh` red twice (no `LOCK waiting`, slow date ran); reverted, `test-ci-warm` all checks passed.
  - mutation (QA, AC11): `gotoSettled` throws the first error -> `goto-settled.test.mjs` retry row and twice row red; `fillSignIn` back to `page.goto` -> the source pin red; reverted, 11 of 11 green; `npm --prefix web test` 1153 pass.
  - QA also ran: `Digest.Store`, `DismissApi` (warm, green), `live:answers` 20 passed, `live:online-demo` 50 passed. The warm stack and throwaways are torn down; lane-a holds no lock.
- mutation (code review, AC1 third bullet): `RoutingProduction.OnAfterAllTests` without `Test.Digest.Store.Clean()` (warm `e11s9cw`) -> the class red with "Digest rows of the fixture prefix are left after the clean-up"; reverted (tree byte-identical), green.
- Runs: the six loop classes and `Intake`, `ConversationTurns`, `Live.Payloads`, `BreakFeedProduction`, `Bridge.Fallback`, `Web.Api` pass warm; the six loop classes pass on a fresh stack; `live:answers` 20 passed; `live:online-demo` passed; `live:sign-in` part 1/2 passed with no `NAV retry` line; `test-mock`, `test-ci-warm`, `test-online-host`, `test-boundaries`, `test-class-rules` and `npm test` pass.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Five checks that Epics 1 to 10 left on a fixture or a double now run on the real items and the CI mock: Story 1.12's digest row through OutcomeRouter, Story 2.8's expired and cancelled approval events, Story 2.9's thread over the real Decide (with the new marker scenario `A/thread-broken-retry.json`), Story 6.4's dismissal against the real IncidentManager (in `Test.Web.DismissApi` and `close-loop.spec.ts`) and Story 10.3's R2b. The dismiss route answers the owner's `not_allowed` with 409 `not_dismissible` instead of 500. The three flakes are fixed: DW-376 (`WakeTASKMGR` after `RunNow`, a polled 90 s ceiling, diagnostics), DW-396 (`OCUTALON_LOCK_WAIT=3` and a slow-first-try case) and DW-415 (`gotoSettled` at the five shared navigation sites, with a hermetic node test). The stale "until ..." texts are corrected.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Test/Digest/Store.cls`: public `KeptProblems`, called by `AssertKept`.
- `src/ocutalon/cls/OcuTalon/Test/Core/RoutingProduction.cls`: the digest branch waits for DigestStore and asserts the row; the class cleans digest rows.
- `src/ocutalon/cls/OcuTalon/Test/Core/AnswersInProduction.cls`: `HeldCall`, the expired and cancelled stream tests, and an expired event check.
- `src/ocutalon/cls/OcuTalon/Test/Core/ThreadProduction.cls`, `.../Test/Core/DecideDouble.cls`, `ci/mock/scenarios/A/thread-broken-retry.json`: the thread over the real Decide on the mock; the double no longer runs in a production.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`: `not_allowed` is 409 `not_dismissible`.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`, `.../Test/Live/Payloads.cls`: `Fixture.FixRun`, lifted from `Payloads.Run`.
- `src/ocutalon/cls/OcuTalon/Test/Web/DismissApi.cls`: no class-wide swap; the real item; the double only in `TestOwnerErrorIs500`.
- `web/e2e/support/iris.ts`, `web/e2e/answers/close-loop.spec.ts`, `docker/tests/test-answers.sh`: `incidentCommands` and `seedFixRun`; no IncidentManager swap.
- `web/e2e-online/resume.spec.ts`, `docker/tests/test-online-demo.sh`: R2b folded into R2 with the `telegram` assertions.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls`: the wake, `RUNNOWSECONDS`, diagnostics.
- `docker/tests/test-ci-warm.sh`: `OCUTALON_LOCK_WAIT=3` and the slow-first-try case.
- `web/e2e/support/navigate.ts`, `web/e2e/sign-in/helpers.ts`, `web/e2e/support/trace.ts`, `web/e2e-online/support.ts`, `web/scripts/goto-settled.test.mjs`: `gotoSettled` and its tests.
- Stale texts: `Test/Bridge/Fallback.cls`, `Schedule/HeartbeatIn.cls`, `Test/Tools/Reminders.cls`, `web/e2e/support/approvals.ts`, `release/demo-host-checks.md`.

**Review.** 27 findings across the four layers. Patches applied: 6 rows (3 medium, 3 low): the Message-branch case and the `OnAfterAllTests` restore in `DismissApi`, `bad = ARMED` in `ThreadProduction` (which also covers the countdown finding), the `body()` terminator assertion, and the added `mutation:` lines. Deferred: none. Rejected: 21 rows, each with its reason in the Review Triage Log. Follow-up review recommended: false. Three medium rows were patched, but every patch is test-side or a record, and the full verification below ran after the last one, so no unverified risk is left to name.

**Verification (re-run by the build stage after the patches).** Slot A: the two patched classes compile. Warm stack: `RoutingProduction`, `AnswersInProduction`, `ThreadProduction`, `DismissApi`, `Digest.Store`, `Schedule.Heartbeat` (135 s), `Intake`, `ConversationTurns`, `Live.Payloads`, `BreakFeedProduction`, `Bridge.Fallback` and `Web.Api` pass. Fresh stacks: the same six loop classes pass. `test-mock`, `test-ci-warm`, `test-online-host`, `test-boundaries`, `test-class-rules` and `npm --prefix web test` (1153) pass. `live answers` 20 of 20, `live online-demo` passes, `live sign-in --part 1/2` 127 passed with no `NAV retry` line. The AC8 grep names only Epic 12, 30 and 31 calls. All stacks of this stage are torn down and lane-a holds no lock.

**Residual risks.** DW-376's wake is pinned by the Task 0 measurements and the diagnostics, not by an assertion (a latency bound is not deterministic). A recompiled class reaches a running production item only after the item restarts; warm-stack mutation runs of product items must restart the item. About 40 direct `goto` calls in specs keep no retry (declined, with `reopen_if` in the Ledger).
