---
title: 'Story 4.2: Derive the guide state and Break the feed availability on the server'
type: 'feature'
created: '2026-10-25'
status: 'done'
baseline_revision: '49f38823504ab56fce87dcf7d3c79be4c592233c'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Nothing on the server derives the demo guide's progress or Break the feed's availability. There is no `OcuTalon.Demo.Guide`, the `guide.state` payload holds only `runEpoch`, `step` and `finished`, nothing publishes `guide.state`, `/state` has no guide, and `POST /api/v1/guide/markers` answers 501. Without a server-derived state the page would decide progress itself, which AD-12 forbids, and Story 4.3's locked check would have nothing to ask.

**Approach:** Add `OcuTalon.Demo.Guide.Compute(SessionRef)`, the single derivation. It reads the session's real rows through `Data.Ownership` (the Orders watch, a reminder, the Orders incident and its approval requests, the latest Break the feed run), plus the guide markers and the clock. `Live.Publish` gains the one refresh that recomputes the guide and publishes `guide.state` only when it changed. The refresh runs after the seven trigger events, on `StatusMonitor`'s tick for sessions with a recent run, and on the new marker endpoint. `/state` carries the result as `guide`.

## Boundaries & Constraints

**Always:**
- **What Compute reads.**
  - Other lanes' rows (`BackgroundCheck`, `Reminder`, `Incident`, `ApprovalRequest`), Lane B's `BreakFeedRun` and the session's own live events are read only through `Data.Ownership`. Each new read is a new fixed statement of `Ownership.Rows` with the owner check. Rows is the one unchecked prepare that the contended `test-class-rules.sh` allows (AD-13).
  - `GuideState` is read by its unique `SessionRef` index.
  - No endpoint takes a `SessionRef` from the client.
- **Which incidents count.** Only incidents that the ownership API shows: noticed ones that are the session's own, or, on a local install, an `instance` incident of a production the session watches (AD-4, AD-15).
- **The Orders production.** `Install.Step.Demo`'s `NAMESPACE`, compared without regard to case, and its `PRODUCTION`.
- **Publishing `guide.state`.**
  - `guide.state` has one publisher, `Live.Publish.RefreshGuide(sessionRef)` (AD-33).
  - It acts only while demo mode is on, and only for a stream that is exactly a `Session` row's `Ref`.
  - It holds `^OcuTalon.Demo.Guide(sessionRef)` while it computes, compares and publishes.
  - It publishes only when the exported JSON differs from the payload of the stream's latest `guide.state` event. A stream with no such event is compared with `Guide.Blank()`.
- **The hook.**
  - It runs in `Publish` after Publish's own commit and unlock, for `chat.message`, `incident`, `approval`, `check`, `reminder`, `pairing` and `breakfeed.progress` on a session stream.
  - A refresh that fails is logged as a warning and never changes Publish's status or its committed event.
- **REST writes only the UI-only markers in `GuideState` (AD-1).**
  - "trace opened" sets `TraceOpened`.
  - "run again" adds 1 to `RunEpoch`, sets `RunStartedAt` to now and clears `TraceOpened`.
  - Nothing else of the session changes.
- **With demo mode off:**
  - `/state` has no `guide` key;
  - the marker endpoint answers 404 `not_found` before it reads the body;
  - the hook and the tick do nothing.
- **Times** are UTC strings `YYYY-MM-DDThh:mm:ssZ`. Ages are whole seconds.
- **Tests.**
  - They build every state from fixture rows (`Test.Data.Fixture`).
  - They restore the `demo.mode` row through `Test.Demo.Step`, `^OcuTalonTest("TelegramIncluded")` through `Fixture.SetTelegramIncluded`, and `onlineDemo` as `Test.Data.Ownership` does.

**Never:**
- **Contended paths.** Never edit one. That includes `Data/{StatusMark,Time,Reminder,Pairing,Delivery}.cls`, `Data/Public/**`, `Install/**` (all of it: this story reads `Install/Step/Demo.cls` and does not change it), `Schedule/**`, `Core/Commands*.cls`, `Core/{SessionOps,AnswersIn,Allowance,Trace}*.cls`, `src/bridge/**`, `docker/**`, `ci/mock/**`, `web/src/app/api/**`, `Test/Contract/Ac.cls` and `.github/**`. A need to edit one stops the story with `## Clarification Needed`.
- **Ownership of rows.** No write to another lane's row in product code.
- **No new structure.** No new production item, table, live-event type, route, role or grant, and no unchecked prepare outside `Ownership.Rows`.
- **Methods that Epic 8 also edits.** Never reshape one.
  - `StatusMonitor` gains one parameter, one new method, one call line and a header sentence.
  - `Web.Api` gains a handler, a private body reader, one message parameter, the markers route's `Call`, and one line in `StateBody`.
- **Out of scope:**
  - the press of Break the feed (Story 4.3);
  - any page rendering (Stories 4.4 and 4.7);
  - the recorded Telegram state (Story 10.3).

## I/O & Edge-Case Matrix

Fixture session S, demo mode on, Compute through `Test.Demo.GuideProbe` (fixed clock, Telegram seam) unless the row says otherwise. "Orders" means `OCUORDERS` / `OcuTalon.Demo.Orders.Production`. The window start W is the `StartedAt` of the epoch's latest run, or `GuideState.RunStartedAt` when the epoch has no run.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1. Blank | S has no rows | `runEpoch` 1, `step` 1, five steps not done, `breakFeed` {active false, reason `not_watching`, no stage}, `step4Variant` `unpaired`, `telegramRow` false, `finished` false. `Blank()` exports the same JSON | none |
| 2. Step 1 | an Orders production check of S (namespace in any case) | step 1 done, Break the feed active. A check of another production, of another namespace, or of another session leaves step 1 not done and the reason `not_watching` | none |
| 3. Step 2 | a reminder of S that is pending, or one that has fired | step 2 done. A cancelled reminder alone, or another session's reminder, leaves it not done | none |
| 4. Step 3 | a noticed Orders incident of S with `NoticedAt` at or after W; also an `instance` Orders incident while S watches Orders on a local install | step 3 done. An incident that is unnoticed, not on Orders, another session's, noticed before W, or an `instance` one with `onlineDemo` 1 does not count | none |
| 5. Step 4 | the run's incident has a request that is approved, rejected, executing, done or failed | step 4 done. Requests that are only pending, expired or cancelled leave it not done | none |
| 6. Step 5 | `GuideState.TraceOpened` 1 | step 5 done | none |
| 7. Variant | the run incident's `OpenVariant` is `rejected`, `fallback` or `no_fix` | that value. Otherwise (none, or `expired`): `paired` when Telegram is on and S is paired, else `unpaired`. The real Guide, with `TelegramIncluded` 1 and a pairing, gives `unpaired`: Telegram counts as off until Story 10.3 | none |
| 8. Telegram row | the probe says Telegram is on; S unpaired; step 1 not done | `telegramRow` true. It is false once S is paired or step 1 is done, and always false with the real Guide | none |
| 9. Finished | step 5 done, an approved request (approved, executing, done or failed), and the incident `resolved` (or `closed` with no open variant) | `finished` true. It is false after a rejection, a fallback or a no-fix notice, while fixing, for an incident closed after a rejection, or without the trace marker | none |
| 10. Current step | various | `step` is the lowest step not done (5 when all are done). With the variant `rejected`, `fallback` or `no_fix`, a `step` of 5 becomes 4, so step 4 stays current after a rejection (Story 4.7, AC 2) | none |
| 11. Busy incident | an Orders watch, and S's Orders incident `open` (any variant), `awaiting_approval` or `fixing` | inactive, `incident_in_progress`. With `resolved` or `closed`, active | none |
| 12. Run stages | the latest run started at T0, with no Orders incident noticed at or after T0 | `sent`: 89 s gives `waiting`; 90 s and 179 s give `still_waiting`, both inactive with `incident_in_progress`; 180 s gives `no_notice`, active. `sending` at 10 s gives `sending`. With an incident noticed at or after T0: `notice_arrived`. `startedAt` is T0 | an unreadable `StartedAt` counts as older than 180 s |
| 13. Second run | resolved incident I1, then a new run started after I1's notice | steps 3 and 4 are not done and `finished` is false until a new incident is noticed. Step 5 keeps its marker | none |
| 14. Run again | `RunEpoch` 2, `RunStartedAt` after the last notice; a run from before the epoch, 60 s old | steps 3 to 5 are not done; the watch and the reminder still count; no stage is reported. The 60 s run still blocks with `incident_in_progress`, and stops blocking from 180 s | none |
| 15. Hook | S has an Orders check; publish any of the seven trigger types on S's stream | exactly one `guide.state` follows when the view changed, and none when it did not. None for a non-trigger type, with demo mode off, on the instance stream, on a stream that is no session's, or for a session whose view equals the blank one | a held guide lock: Publish answers OK, its event is committed, one warning is logged |
| 16. Tick | S: Orders check, run sent 100 s ago | a `StatusMonitor` run publishes `still_waiting`; a second run publishes nothing; at 200 s it publishes `no_notice`. A run 300 s old is not refreshed. Demo mode off: nothing | none |
| 17. Markers | `POST /v1/guide/markers` with `{"marker":"trace_opened"}` or `{"marker":"run_again"}` | 200 with the guide view, and a `guide.state` event. "run again": `runEpoch` +1, steps 3 to 5 reset, and S's other rows unchanged | any other body: 400 `bad_marker` (V2), nothing written. Demo mode off: 404 `not_found`, nothing written |
| 18. `/state` | demo mode on, or off | on: `guide` is the last key, equal to Compute's view; off: no `guide` key | a failed read throws (500), as today |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Data/GuideState.cls:1-43` -- `SessionRef` (unique), `RunEpoch`, `TraceOpened`, storage `^OcuTalonP.Guide`. `RunStartedAt` is added as storage slot 5, appended only (`test-storage.sh` release-diff). Owned by Lane B and Epic 4 (AD-33); no writer exists yet.
- `src/ocutalon/cls/OcuTalon/Data/BreakFeedRun.cls:1-43` -- `SessionRef` (non-unique index), `State` (`sending`/`sent`), `StartedAt`. No writer until Story 4.3.
- `src/ocutalon/cls/OcuTalon/Live/Payload/GuideState.cls:1-14` -- `RunEpoch`, `Step`, `Finished`. `Live/Payload/BreakFeedProgress.cls` is the sibling for the run row's view: its shape differs, so it is not reused (Rule 2).
- `src/ocutalon/cls/OcuTalon/Live/Payload/Part/CheckRow.cls` -- the pattern for a part class. `ChatMessage.cls:52,58` show a part property and a `list Of` part.
- `src/ocutalon/cls/OcuTalon/Live/Publish.cls`:
  - `:10` `TYPES` (unchanged), `:13` `INSTANCE`, `:16` `LOCKWAIT`;
  - `:52-93` `Publish`, which unlocks at `:91`. The hook goes after that line.
  - It has no `Include Ensemble` yet; `$$$LOGWARNING` needs one.
- `src/ocutalon/cls/OcuTalon/Core/StatusMonitor.cls:25-56` -- `OnProcessInput`, the 15 s tick. `Readings`/`Stream` seams at `:59,65`. Shared by function with Epic 8: insert `Do ..GuideTick()` just before `Quit $$$OK` and change nothing else.
- `src/ocutalon/cls/OcuTalon/Core/Rule/Functions.cls:19` -- `DemoOn()`, reused by the tick (Core → Core).
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - `:63` the markers route (`Call="NotBuilt"`);
  - `:42-50` the `MESSAGE*` parameters;
  - `:167-200` `MessageBody`/`BodyText`, the pattern for the body reader;
  - `:238` `NotBuilt`;
  - `:258-297` `StateBody`: `demoMode` is set at `:280`. Insert the `guide` line just before `:294` (`TraceLink).Viewer`), so `guide` is the last key;
  - `:392` `PayloadObject`, `:400` `CurrentSession`, `:465` `Fail`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - `:42` `INCIDENTVISIBLE` (reuse it in the incident kinds);
  - `:76-88` `RunCost`'s empty-`since` convention (`0000-01-01T00:00:00Z`);
  - `:226` `Incidents`, `:283` `Incident`, `:305` `Approval` (its visibility text is the one for the incident's requests), `:388` `LocalFlag`;
  - `:401` `Rows` (Final, Private, the one unchecked prepare);
  - `:449-537` `Statement`: append new kinds as a block before `:536` `Quit ""`.
  - `Watchers` (`:319`) is the precedent for a checked read across sessions that runs only in production jobs.
- `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls:36,39,42` (read-only) -- `MODEKEY`, `NAMESPACE`, `PRODUCTION`.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls:20` (read-only, Lane A) -- `Included()`. `/state` writes the Telegram state as the literal `"off"` (`Web/Api.cls:286`). Story 10.3 adds `StatusMark.RecordTelegram`.
- `src/ocutalon/cls/OcuTalon/Msg/Enum.cls:18,21,24` (read-only) -- `INCIDENTSTATE`, `INCIDENTOPENVARIANT`, `APPROVALSTATE`.
- `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls:95-104` (contended, private) -- `ToSeconds`/`FromSeconds`. `BreakFeedRun` gets its own copy (Rule 2).
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls`:
  - creators `Check` `:65`, `Reminder` `:50`, `Incident` `:81` (default `OpenVariant` "fix", `State` "open"), `Approval` `:102`, `Pairing` `:191`, `SetTelegramIncluded` `:156`;
  - `Keep(row, ref)` `:420`;
  - `Clean` `:292`, whose session branch is at `:308`.
- `src/ocutalon/cls/OcuTalon/Test/Demo/Step.cls:125-165` -- `Saved`/`Put`/`Remove`/`PutBack` of the `demo.mode` row.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls`:
  - `:93-121` `TestStateBody` pins the exact snapshot keys;
  - `:158` `TestStateFlags`;
  - `:722` `TestRoutes` pins the route list;
  - `Written`/`Capture`/`Collect` (`:1027-1068`) are public class methods; `PostMessage` (`:1012`) is the stand-in pattern.
- `src/ocutalon/cls/OcuTalon/Test/Web/StubRequest.cls` -- `MakeBody(application, json)`.
- `src/ocutalon/cls/OcuTalon/Test/Core/StatusMonitor.cls:40-56` and `StatusMonitorProbe.cls` -- the shadow probe with `KeysReading`, `BudgetReading` and `StreamRef`, and `Test.Core.Observe.LastLog`/`RemoveWarnings`.
- `src/ocutalon/cls/OcuTalon/Test/Live/Publish.cls:274,290` -- `Holder`, the JOB pattern for a lock held by another process.
- `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls:349-476` and `OwnershipProbe.cls` -- the isolation and refusal pattern for every row kind.
- `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls:76-92,696` -- the payload contracts; `:92` counts 27 classes.
- `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls:323` -- the `GuideState` table contract.
- `web/scripts/payloads.mjs` -- writes `web/src/app/live/payloads.ts`. `--check` runs in `npm run build`. A property needs `%JSONFIELDNAME` equal to its name with a lower-case first letter. The bundle is gitignored; `payloads.ts` is committed.
- `web/e2e/api/api.spec.ts`:
  - `:66-71` `UNBUILT`, which includes the markers route;
  - `:117` row 13 pins the exact `/state` keys and `streams {session: 2}` after `test-sign-in.sh`'s two reminder events on the README session.
- `web/e2e/demo-switch/badge.spec.ts` and `web/playwright.config.ts` -- the `demo-switch` project. `docker/tests/test-demo-switch.sh:161` runs it with `OCUTALON_E2E_DEMO_MODE=0` (step 5) and `=1` (step 8), with only `OCUTALON_URL` set (no IRIS access), after the `/state` checks of each step.
- `ci/units.sh:18` -- the `lane-b` shard holds the areas `Contract Core Data Demo Live Msg Web`, so the new test classes need no entry.
- Not affected: `Schedule/ReminderOps.cls` and `ReminderTimer.cls` are stubs (`STUB` 1), so no product path writes a `Reminder` row today.

## Tasks & Acceptance

**Execution:**
- [ ] `src/ocutalon/cls/OcuTalon/Data/GuideState.cls` -- add `Property RunStartedAt As %String(MAXLEN = 20)` ("When the current run epoch started, UTC; empty for the first epoch"; V1) with its storage slot. Add:
  - `ClassMethod ForSession(sessionRef) As OcuTalon.Data.GuideState`: the row, or "";
  - `ClassMethod Lock(sessionRef, wait) As %Boolean` and `Unlock(sessionRef)` over `^OcuTalon.Demo.Guide(sessionRef)`: the one lock name, re-entrant in a process;
  - `ClassMethod TraceOpened(sessionRef) As %Status`: creates the row (`RunEpoch` 1) or sets `TraceOpened` 1;
  - `ClassMethod RunAgain(sessionRef) As %Status`: `RunEpoch` +1 (2 when there is no row), `RunStartedAt` now and `TraceOpened` 0.
  - Both writers run under `Lock`. The doc comment says that the REST marker endpoint is their only caller (AD-1).
- [ ] `src/ocutalon/cls/OcuTalon/Data/BreakFeedRun.cls` -- add:
  - `Method Age(now As %String) As %Integer`: seconds from `StartedAt` to `now`; a large value when either time is unreadable;
  - `ClassMethod RecentSessions(seconds As %Integer, now As %String = {##class(OcuTalon.Data.Time).NowUtc()}, Output sc As %Status) As %List`: the distinct `SessionRef`s with a run started less than `seconds` before `now`. It is a checked prepare, which runs in the `StatusMonitor` job (the production holds `%All`, AD-24) and in tests;
  - private `ToSeconds`/`FromSeconds` (Rule 2 note).
- [ ] `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- six statement kinds appended to `Statement`, each with the owner check, and one public method each, with a header doc line. `since` "" follows RunCost's convention.

  | Method | What it answers |
  | --- | --- |
  | `ReminderSetOrFired(sessionRef, .sc)` | the session's newest reminder that is pending or fired, or "" |
  | `NewestIncident(sessionRef, namespace, production, since, .sc)` | the newest visible incident of that production noticed at or after `since`, or "" |
  | `IncidentInProgress(sessionRef, namespace, production, .sc)` | the newest visible incident of that production that is open, awaiting approval or fixing, or "" |
  | `IncidentApprovals(incidentRef, sessionRef, .sc)` | the requests of that incident that the session can see, in any state, by `RaisedAt` |
  | `LatestBreakFeedRun(sessionRef, .sc)` | the latest run by `StartedAt` then ID, or "" |
  | `LastEvent(sessionRef, type, .sc)` | the stream's newest event of that type, by `Seq`, or "" |
- [ ] `src/ocutalon/cls/OcuTalon/Live/Payload/Part/GuideStep.cls` (new) -- `Step` %Integer and `Done` %Boolean.
- [ ] `src/ocutalon/cls/OcuTalon/Live/Payload/Part/GuideBreakFeed.cls` (new) -- `Active` %Boolean, `Reason`, `Stage` (MAXLEN 32) and `StartedAt` (MAXLEN 20).
- [ ] `src/ocutalon/cls/OcuTalon/Live/Payload/GuideState.cls` -- after the existing three, add `Steps` (list Of `Part.GuideStep`), `BreakFeed` (`Part.GuideBreakFeed`), `Step4Variant` (MAXLEN 32) and `TelegramRow` %Boolean. The doc comments list the closed values (V1).
- [ ] `web/src/app/live/payloads.ts` -- regenerate it with `node web/scripts/payloads.mjs`. No other web source changes.
- [ ] `src/ocutalon/cls/OcuTalon/Demo/Guide.cls` (new) -- the single source (AD-12):
  - `ClassMethod Compute(sessionRef) As OcuTalon.Live.Payload.GuideState`: matrix rows 1 to 14. It throws when a read fails. The notice check for availability reads `NewestIncident` with the latest run's own `StartedAt`, which is the window start unless that run is from an earlier epoch;
  - `ClassMethod Blank()`: the view of a session with no rows. One private builder serves both (Rule 2);
  - `ClassMethod DemoOn() As %Boolean`;
  - private seams `Now()` (`Data.Time.NowUtc()`) and `TelegramOn()` (`Telegram.In.Included()` and `TelegramState() = "on"`). `TelegramState()` answers "off", as `/state` does until Story 10.3;
  - parameters for the closed lists and the 90 and 180 s thresholds.
- [ ] `src/ocutalon/cls/OcuTalon/Live/Publish.cls` -- add:
  - `Parameter GUIDETRIGGERS` (the seven types);
  - `ClassMethod RefreshGuide(sessionRef, Output guide) As %Status`, as the Boundaries describe. It outputs the computed view even when nothing was published;
  - at the end of `Publish`, after the unlock: on success, for a trigger type and a stream that is not `INSTANCE`, call `RefreshGuide`. Log an error with `$$$LOGWARNING` and a `LOGGUIDE` text, and return Publish's own status.
- [ ] `src/ocutalon/cls/OcuTalon/Core/StatusMonitor.cls` -- add:
  - `Parameter GUIDESECONDS = 240`;
  - a private `GuideTick()`: when `Core.Rule.Functions.DemoOn()`, it calls `Live.Publish.RefreshGuide` for each of `BreakFeedRun.RecentSessions(GUIDESECONDS)`. Each error is a warning, and nothing throws;
  - one call line at the end of `OnProcessInput`. The class header says what the tick adds.
- [ ] `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- these changes:
  - the markers route gets `Call="GuideMarkers"`;
  - `Parameter MESSAGEBADMARKER` (V2);
  - `ClassMethod GuideMarkers()`, which checks in this order: `Guide.DemoOn()`, or 404 `not_found`; a valid body, or 400 `bad_marker`; then `CurrentSession`, the `GuideState` writer and `RefreshGuide`, each 500 `server_error` on failure; then 200 with `PayloadObject(guide)`;
  - a private `MarkerBody(Output marker)`, built like `MessageBody`;
  - in `StateBody`, one line: `If body.demoMode Set body.guide = ..PayloadObject(##class(OcuTalon.Demo.Guide).Compute(sessionRef))`;
  - in the class header, the markers route and the `guide` key.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` -- add two creators, each recorded under `sessionRef` (so `Clean(sessionRef)` removes them):
  - `BreakFeedRun(sessionRef, state = "sent", startedAt = now)`;
  - `GuideState(sessionRef, runEpoch = 1, runStartedAt = "", traceOpened = 0)`.

  `Clean`'s session branch also deletes the session's `GuideState` and `BreakFeedRun` rows, the ones product code made included, as `DropDeliveries` does.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Demo/GuideProbe.cls` (new) -- it extends `Demo.Guide` and overrides `Now()` and `TelegramOn()`, which read `^OcuTalonTest("GuideProbe", ...)`. When the test sets nothing, `Now()` is the real clock and `TelegramOn()` answers 0 (matrix row 1). The test kills the global before and after.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Demo/Guide.cls` (new) -- matrix rows 1 to 14 through the probe. It also has:
  - `TestTelegramCountsAsOff` with the real `Guide`;
  - `TestBlank`: `Blank()` equals `Compute` of a fresh fixture session.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/OwnershipGuide.cls` (new) -- for each new read: its content and order; isolation between sessions A and B; and refusal of an empty, `instance` or `eval` owner (through `OwnershipProbe`).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Live/GuideRefresh.cls` (new) -- matrix row 15, the held-lock row (a JOBbed holder, as `Test.Live.Publish.Holder`), and the integration check: `Web.Api.EventsBody` serves the `guide.state` that the hook published.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/StatusMonitorGuide.cls` (new) -- matrix row 16, driving a shadow `Test.Core.StatusMonitorProbe` with fixed readings and a private status stream.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/GuideApi.cls` (new) -- matrix rows 17 and 18 with stand-in requests (`StubRequest.MakeBody`, `Test.Web.Api.Written`). It also checks that "run again" leaves S's `Turn`, `BackgroundCheck`, `Reminder`, `Incident` and `BreakFeedRun` rows unchanged (counts and refs).
- [ ] Shared surfaces -- update these, then search the test trees for others (Verification):
  - `Test/Web/Api.cls`:
    - `TestStateBody` puts `demo.mode` "1" and expects `...,status,guide`;
    - `TestStateFlags` asserts that `guide` is present exactly when `demoMode` is true;
    - `TestRoutes` expects `GuideMarkers`; update the class header;
  - `Test/Live/Payloads.cls`: the `GuideState` contract, the two parts, the count 29, and the header;
  - `Test/Data/Tables.cls`: `"RunStartedAt": "%String(MAXLEN=20)"`;
  - `web/e2e/api/api.spec.ts`: row 13 gains `guide` as the last key and asserts the blank guide of matrix row 1. Drop the markers route from `UNBUILT`.
- [ ] `web/e2e/demo-switch/guide.spec.ts` (new) -- signs in as the README account over real HTTP and uses only HTTP.
  - **With `OCUTALON_E2E_DEMO_MODE=1`:**
    1. `/state` has `guide`, with `breakFeed` inactive and the reason `not_watching` (the README session watches nothing).
    2. `trace_opened` answers 200, with step 5 done and `runEpoch` unchanged.
    3. `/events` after the cursor holds that `guide.state`, and `/state`'s `guide` equals it.
    4. `run_again` answers 200, with `runEpoch` +1 and step 5 not done.
    5. A bad body answers 400 `bad_marker`.
    6. `chat` and `rail` are unchanged throughout.
    Every assertion is relative to the values first read, so a re-run passes.
  - **With `0`:** `/state` has no `guide`, and both markers answer 404 `not_found`.
  - **Without the variable** it fails at once, as `badge.spec.ts` does.

**Acceptance Criteria:**
- Given demo mode on and fixture rows of every kind the AC names, when `Guide.Compute(S)` runs, then matrix rows 1 to 14 hold (`Test.Demo.Guide`), and only the session's own or visible rows count (`Test.Data.OwnershipGuide`).
- Given demo mode on, when `Live.Publish` publishes one of the seven trigger types for S, then exactly one `guide.state` follows a change and none follows no change. **Integration:** consumer `Web.Api.EventsBody` serves it as the page polls it. `StatusMonitor`'s run publishes the clock stages for sessions with a run under 240 s old (`Test.Live.GuideRefresh`, `Test.Core.StatusMonitorGuide`).
- Given the page signed in on a Docker throwaway, when it calls `GET /api/v1/state` and `POST /api/v1/guide/markers` over real HTTP, then `web/e2e/demo-switch/guide.spec.ts` holds in both modes, inside `live:demo-switch`. **Integration:** consumer `/state` carries Compute's view. With demo mode off the endpoint answers 404.
- Given a marker call, when it is answered, then only `GuideState` changed, and "run again" never changes the session's data (`Test.Web.GuideApi`).

## Spec Change Log

- 2026-10-25, spec gate (runner): V1 and V2 kept as veto items; spine diagram edges added (Rule 20).

## Review Triage Log

### 2026-10-25 -- Review pass
- verdicts: 29 findings -- high 0, medium 2, low 23, false 4, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: GuideMarkers answers 500 after RunAgain committed when the refresh fails, so a retry advances the epoch again -- the spec prescribes 500 for a failed refresh (Decided 9); the refresh fails only on a 5 s lock timeout; reopen_if a marker call is seen to 500 on a healthy stack.
  - `[low]` `[reject]` Blind: RecentSessions compares StartedAt as a string and scans the table -- only Story 4.3 writes StartedAt, in this format; the table is demo-sized; no user-reachable failure.
  - `[low]` `[patch]` Blind: RecentSessions and the tick's error branches have no direct test -- the 240 s window had only the 100, 200 and 300 s probes; added `TestWindowEdges` (230 s refreshed, 250 s not) with a mutation line; the error branches stay untested (not in the matrix).
  - `[low]` `[reject]` Blind: two DemoOn implementations -- the spec's Rule 2 note records the copy (the spine has no Demo to Core edge).
  - `[low]` `[reject]` Blind: REASONS and STAGES parameters unused -- the spec asks for parameters for the closed lists; they document the closed values.
  - `[low]` `[reject]` Blind: the hook waits up to 5 s for the guide lock and a skipped refresh is not retried -- Decided 7 and matrix row 15 state both.
  - `[low]` `[reject]` Blind: Fixture.DropGuide ignores the prepare status -- it mirrors DropDeliveries, as the spec says.
  - `[low]` `[patch]` Blind: stale docs -- the `web/playwright.config.ts` header now names the guide spec; `docker/tests/test-demo-switch.sh` is contended and untouched.
  - `[low]` `[reject]` Blind: guide.spec.ts leaves the README session changed -- the spec requires relative assertions so a re-run passes.
  - `[low]` `[reject]` Edge: Run again in the same second as the latest run's StartedAt keeps the old run current -- the order within one second is unknowable and a press that fast is not reachable by a person.
  - `[low]` `[reject]` Edge: GuideMarkers retry after a failed refresh -- same root cause as the first row.
  - `[low]` `[reject]` Edge: a monitor stalled past 240 s misses the 180 s tick -- `/state` recomputes on every load; Decided 8 fixes the window.
  - `[low]` `[reject]` Edge: a StartedAt in the future gives a negative age -- needs a clock step back; theoretical.
  - `[low]` `[reject]` Edge: the tick can block 5 s per busy session -- a guide lock is held for milliseconds.
  - `[low]` `[reject]` Edge: a failed Compute makes /state a 500 -- matrix row 18 says a failed read throws (500), as today.
  - `[medium]` `[patch]` Verification gap: no TestFinished row has an approved fix together with a closed incident that has an open variant, so the variant clause is unpinned -- added four rows (rejected, fallback, no_fix, expired, each with a done request); mutation line written.
  - `[medium]` `[patch]` Verification gap: the "only the marker changes" fingerprint omits approval requests in every state and the incident's fields -- Fingerprint now reads Incident (Ref, State, OpenVariant, NoticedAt) and ApprovalRequest (Ref, State) by owner; mutation line written.
  - `[low]` `[reject]` Verification gap: the 500 branches of GuideMarkers have no test -- not a matrix row; reopen_if Story 4.3 changes the endpoint.
  - `[low]` `[patch]` Verification gap: the tick window and guard are pinned only by redundant paths -- same root cause as the third row; the demo-off guard is duplicated by RefreshGuide and stays.
  - `[low]` `[reject]` Verification gap: the instance-stream guards cannot fail on their own -- defensive duplicates of the Session-row check; no behaviour depends on them alone.
  - `[low]` `[reject]` Verification gap: an unreadable StartedAt refreshes forever -- same root cause as the second row.
  - `[low]` `[reject]` Verification gap: TestStateBody leaves demo.mode at 1 -- OnAfterAllTests restores it, and `shard lane-b --reverse` passed with 49 classes.
  - `[low]` `[reject]` Verification gap: the guide.spec event assertions sit inside `if (!wasOpen)` -- on a fresh throwaway the branch is taken; it only weakens a re-run.
  - `[low]` `[reject]` Verification gap: duplicate DemoOn predicate -- same root cause as the fourth row.
  - `[false]` `[reject]` Intent: RecentSessions is a prepare outside Ownership.Rows -- the spec prescribes it as a checked prepare in BreakFeedRun, as Watchers does.
  - `[low]` `[reject]` Intent: StatusMonitor gains two parameters, GUIDESECONDS and LOGGUIDE -- recorded as Decided 17; the constraint protects Epic 8's methods and the constant follows LOGRUN's pattern.
  - `[false]` `[reject]` Intent: the marker body accepts extra members -- Decided 9 says other members are ignored.
  - `[false]` `[reject]` Intent: incident namespace case under SQL equality -- Decided 12; the default collation is SQLUPPER and the matrix row 2 test passes.
  - `[false]` `[reject]` Intent: a marker publishes an event only on change -- the Publishing boundary says it publishes only when the JSON differs.

## Design Notes

**Architecture decisions** (spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`):
- AD-1: REST writes only UI-only markers; the marker endpoint writes `GuideState` and nothing else.
- AD-4: every read goes through `Data.Ownership` with the caller's `SessionRef`, and the client never sends one.
- AD-12: Compute is the single source; the `Live.Publish` hook covers the seven types; the tick covers open runs; marker writes recompute; `GuideState` holds the markers and the run epoch.
- AD-13: the browser envelope; no unchecked prepare outside `Ownership.Rows`.
- AD-15: incidents count only from `NoticedAt`; the transition table and `OpenVariant` decide steps 4 and finish.
- AD-18: the `StatusMonitor` 15 s interval; UTC times. Run ages are UTC arithmetic, not zone conversion.
- AD-19: demo mode comes from `Setting.Get`.
- AD-22 and AD-29: fixture rows and doubles in `OcuTalon.Test.*`; destructive checks only in throwaways (`live:demo-switch`).
- AD-33: `guide.state` has one publisher; Lane B owns `GuideState`, `BreakFeedRun` and `Live.Event`; other lanes' rows are read-only.

**Lead rulings at the spec gate (runner, 2026-10-25; policy 9e90866):**
- **V1 (veto, kept):** `GuideState.RunStartedAt` and the additive `guide.state` fields and parts, as recommended. Inbox item recorded by the runner.
- **V2 (veto, kept):** `MESSAGEBADMARKER` as written. Inbox item recorded by the runner.
- **Spine edges** `Guide --> Telegram.In.Included()` and `Guide --> Install.Step.Demo` (its key constant) are added to the dependency diagram under Rule 20; not an AD change.
- **Cross-epic note** (Decided 6): with demo mode on, a session stream gains `guide.state` events after trigger events; recorded for the orchestrator (Epic 8's later stories count stream events).

**Decided in-stage:**
1. **The run window.** The current run starts at the latest Break the feed run of the epoch, or at the epoch start. Step 3, step 4, the variant and the finish read the newest visible Orders incident noticed in that window. So a second press without Run again makes steps 3 and 4 wait for the new notice (UX: "steps 3 to 5 wait for the new run"). Step 5 is a marker, which only Run again resets.
2. **Answered and approved.**
   - "Answered" means the request's state is approved, rejected, executing, done or failed.
   - Expired and cancelled requests are not answered, and `expired` gives the paired/unpaired variant. The AC lists no variant for it, and no UX text exists. It is a local-install edge after 24 h; Story 4.7 may revisit it.
   - "Approved fix" means approved, executing, done or failed.
3. **The current step.** It is the lowest step not done. With the variant `rejected`, `fallback` or `no_fix`, a value of 5 becomes 4. This is the only reading that satisfies both 4.2's "step 4 done when answered" and 4.7's "Given step 4 is current … after a rejection".
4. **Finished.** Step 5 done, plus an approved request, plus an incident that is `resolved`, or `closed` with an `OpenVariant` outside `INCIDENTOPENVARIANT`. A resolved incident that is dismissed or closes quietly keeps the finish; an incident closed after an open variant does not.
5. **Availability and stage.**
   - Availability reads the session's latest run in any epoch, so a batch in flight blocks a second batch across Run again.
   - The stage is reported only for a run of the current epoch.
   - Stage precedence: `notice_arrived`, then `no_notice` (180 s and later), then `sending`, then `still_waiting` (90 s and later), then `waiting`.
6. **The comparison base.**
   - A stream with no `guide.state` event is compared with `Blank()`, and a stream that is no session's is skipped.
   - This keeps every existing test that publishes trigger events on fixture streams hermetic. It also sends the page nothing it doesn't already have from `/state`.
   - In production every guide-relevant row change is followed by a trigger publish, a marker write or a tick, and the marker answer carries the view itself.
7. **Locking.** One lock per session, `^OcuTalon.Demo.Guide(sessionRef)` (5 s), held over compute, compare and publish, so the last refresh publishes the newest view. The hook runs after Publish releases the stream lock, so no lock-order cycle exists.
8. **The tick.** It refreshes sessions with a run started in the last 240 s: 180 s plus four 15 s intervals of slack. A refresh publishes only on a change.
9. **The marker body.** `{"marker": "trace_opened" | "run_again"}`; other members are ignored.
   - The answer is 200 with the guide view, the same object as `/state`'s `guide`.
   - The checks run in this order: 404 (demo off), 400, 500.
   - A failure after the body check is 500, as for every other route.
10. **`/state`.** `guide` is the last key, and only with demo mode on. That keeps `StateBody`'s edit to one line.
11. **"Telegram is on"** is `Included()` together with `TelegramState() = "on"`. `TelegramState()` mirrors `/state`'s literal `"off"` until Story 10.3 reads `StatusMark` for both. The paired variant needs Telegram on.
12. **The Orders match.** The check's or incident's namespace equals `OCUORDERS` without regard to case (SQL's default collation), and its production equals `OcuTalon.Demo.Orders.Production`.
13. **Epoch numbering.** It starts at 1 with no row. "trace opened" on a missing row creates epoch 1.
14. **Closed values** (snake_case, like `no_fix`):
    - reason: `not_watching` or `incident_in_progress`;
    - stage: `sending`, `waiting`, `still_waiting`, `no_notice` or `notice_arrived`;
    - variant: `paired`, `unpaired`, `rejected`, `fallback` or `no_fix`.
15. **New test classes, not edits to Epic 8's.** New classes keep away from Epic 8's `Test/Core/StatusMonitor.cls`. `Test.Data.Ownership` stays as it is, and the new kinds get their own isolation and refusal tests.
16. **No Task 0.** No platform behaviour is unknown:
    - class-method seams through `..` in a probe subclass were proven in 4.1 (`AdminProbe`);
    - part lists export as in `ChatMessage.Checks`;
    - the REST user writes private-database rows (row 14 of `api.spec.ts`);
    - production jobs run with `%All` (AD-24).

    The hook's cost per trigger publish is unmeasured (inference: a few ms). The implement stage records it.
17. **Two constants on `StatusMonitor`.** `LOGGUIDE` (the warning text) sits beside `GUIDESECONDS`, as `LOGRUN` sits beside the run. Both are next to `GuideTick`, away from Epic 8's lines. `Live.Publish` has the same `LOGGUIDE`.
18. **`Web/Playwright` header and `frame.spec.ts`.** `web/e2e/frame/frame.spec.ts` (Epic 2) F9 pins the exact `/state` keys, so its list gained `'guide'` (one word) for the new last key with demo mode on. `web/playwright.config.ts`'s header now names the guide spec.

**Veto-window items (for the lead; the spec is written with the recommended option):**
- **V1 (schema and stored format). Recommended.**
  - `GuideState.RunStartedAt`: an additive property on Lane B's own table. No rows exist.
  - The `guide.state` payload's additive fields `steps`, `breakFeed`, `step4Variant` and `telegramRow`, with the parts `GuideStep` and `GuideBreakFeed` and the closed values of Decided 14.
  - Without the epoch's start time, Run again can't reset steps 3 to 5 and Story 4.7's `RunCost` has no `since`. No in-footprint alternative exists.
  - Reversal: drop the property, which needs an AC amendment of Run again's semantics; or reshape the payload, which means 4.4 and 4.7 render another shape.
- **V2 (public text not in the UX or PRD).**
  - `MESSAGEBADMARKER`: "A guide marker must be trace_opened or run_again." It is the 400 text, in the style of `MESSAGEBADMESSAGE`.
  - Reversal: change the text.

**Rule 2 (extend, don't copy):**
- The new reads extend `Ownership.Rows`/`Statement` and reuse `INCIDENTVISIBLE` and the `approval` visibility text. `Live.Event.Since` can't filter by type, so `LastEvent` is a new kind.
- `Guide.DemoOn` repeats `Core.Rule.Functions.DemoOn` (two lines), because the spine's diagram has no edge from Demo, Live or Data to Core. The tick, in Core, reuses the original.
- `BreakFeedRun`'s `ToSeconds`/`FromSeconds` copy `Data.Public.Settings`' private helpers. That class and `Data.Time` are contended, and BreakFeedRun is the one home both Guide and the tick may call.
- `Part.GuideBreakFeed` is not `BreakFeedProgress`: one is the run row's state and the other the guide's availability.
- `RefreshGuide` compares against the stream's last durable event, unlike `StatusMonitor`'s in-memory `Remembered`, because three callers in different jobs share it and must survive a restart (AD-5).
- The tests reuse `Fixture`, `Test.Demo.Step`, `Test.Web.Api.Written`, `StubRequest`, `StatusMonitorProbe`, `Observe`, `OwnershipProbe` and `Test.Live.Publish.Holder`'s pattern.

**Integration ACs (Rule 1):** these consumers read Compute in this story, each on a real stack, never a mock:
- `Web.Api` `/state` (the guide spec, over HTTP);
- `Web.Api.EventsBody` (`Test.Live.GuideRefresh`);
- `StatusMonitor` (`Test.Core.StatusMonitorGuide`).

**Consumed-by:**
- 4.3: `BreakFeedIn`'s locked check reads `Compute().BreakFeed` (`Active`, `Reason`). Its `breakfeed.progress` publishes trigger the refresh.
- 4.4: renders `steps`, `step`, `breakFeed` (reason as the hint, stage as the box line, `startedAt` as the elapsed time) and `telegramRow`, from `/state` and `guide.state`. Its page needs `StateSnapshot.guide` in contended `web/src/app/api/api-types.ts`, which is a planning item for 4.4.
- 4.7: `step4Variant`, `finished`, `runEpoch`, the marker endpoint, and `GuideState.RunStartedAt` for `RunCost`'s `since`.
- 8.3 to 8.5: step 2 from real reminders (`Ownership.ReminderSetOrFired`).
- 10.3: replaces `Guide.TelegramState()` and `/state`'s `"off"` with the recorded state, and tests the Telegram row and the paired variant.

**Consumes:**
- `Data.Ownership` and its visibility rule (2.2);
- `Setting.Get` and `Install.Step.Demo`'s constants (0.10, 4.1);
- `Telegram.In.Included()` (0.6);
- `Live.Publish` (0.5), `StatusMonitor` (2.10) and `Web.Api` (0.5, 2.2);
- fixture rows for Lane A's tables and Epic 8's `Reminder`, which are not merged yet.

**Ledger:** no entries are owned by this story (the inbox is empty).

**For the lead:**
- **Footprint.** Lane B paths outside the listed footprint:
  - `Data/{GuideState,BreakFeedRun,Ownership}.cls` (AD-33, Lane B);
  - `Live/Payload/GuideState.cls` and the new `Live/Payload/Part/Guide{Step,BreakFeed}.cls`;
  - `web/src/app/live/payloads.ts` (generated);
  - `Test/Data/{Fixture,Tables,OwnershipGuide}.cls`, `Test/Live/{Payloads,GuideRefresh}.cls`, `Test/Core/StatusMonitorGuide.cls`, `Test/Web/{Api,GuideApi}.cls`;
  - `web/e2e/api/api.spec.ts`; `web/e2e/demo-switch/guide.spec.ts` (Epic 4's folder from 4.1).

  No contended path is edited. In the shared Lane B files `Ownership.Statement` and `Fixture`, the additions are separate appended blocks.
- **Spine (Rule 20, conv).** Add two dependency edges to the diagram:
  - `Guide --> TgIncluded`: AD-12 and the REST surface require the read, but the diagram draws it only from Web;
  - `Guide --> Install.Step.Demo` (the `MODEKEY`, `NAMESPACE` and `PRODUCTION` parameters), as Web and `Core.Rule.Functions` already read them.

  `Data` (with Live) `--> Guide` and `Core --> Data` already exist. This is not an AD change.
- **Cross-epic note (Epic 8, Stories 8.3 to 8.5).** With demo mode on, a session stream gets one `guide.state` after the first trigger publish that changes its view: for example, a reminder event once the session has a pending reminder. Tests that assert a stream's exact events must expect it or switch demo mode off. This is AD-12's behaviour.

## Verification

`<lane B vars>` are Rule 21's `OCUTALON_LOCK_DIR` (the main checkout's `.worktrees/.coordination/locks/lane-b`), `OCUTALON_TEST_WEB_PORT=52802` and `OCUTALON_LOCK_OWNER='epic=4 stage=implement'`.
- **Warm runs.** Start the warm stack once with `<lane B vars> OCUTALON_RUN_TAG=e4s2iw ci/warm.sh up` and end it with `ci/warm.sh down`, also after a failure.
- **Fresh runs.** Use the tag `e4s2i`, then `ci/iris.sh teardown`.
- **One command per foreground call** (`timeout: 600000`). Slot B is for loading, compiling and non-destructive class runs only. Tests that write the `demo.mode` row restore it, and they run on the lane-B throwaways above. The demo-mode switch itself runs only in `live:demo-switch`, on a fresh throwaway.

**Commands:**

`(loop)` commands run on every verification pass:
- `<lane B vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e4s2iw ci/iris.sh class <Class>`, one call each, for these classes (expected: `CLASS ... passed`):
  - `OcuTalon.Test.Demo.Guide`
  - `OcuTalon.Test.Data.OwnershipGuide`
  - `OcuTalon.Test.Live.GuideRefresh`
  - `OcuTalon.Test.Core.StatusMonitorGuide`
  - `OcuTalon.Test.Web.GuideApi`
  - `OcuTalon.Test.Web.Api`
  - `OcuTalon.Test.Live.Payloads`
  - `OcuTalon.Test.Data.Tables`
  - `OcuTalon.Test.Data.Ownership`
  - `OcuTalon.Test.Live.Publish`
  - `OcuTalon.Test.Core.StatusMonitor`
- `node web/scripts/payloads.mjs --check` -- expected: exit 0.
- `npm --prefix web run lint` and `npm --prefix web test` -- expected: exit 0.
- `<lane B vars> OCUTALON_RUN_TAG=e4s2i ci/iris.sh live demo-switch` (fresh; it runs `guide.spec.ts` in both modes) -- expected: every line PASS, exit 0.

`(once)` commands run before the implement stage finalizes:
- `<lane B vars> OCUTALON_RUN_TAG=e4s2i ci/iris.sh shard lane-b` -- expected: every class passed.
- `<lane B vars> OCUTALON_RUN_TAG=e4s2i ci/iris.sh shard lane-a` -- expected: every class passed.
- `<lane B vars> OCUTALON_RUN_TAG=e4s2i ci/iris.sh live sign-in` (`api.spec.ts` row 13 and `UNBUILT`) -- expected: PASS.
- `bash ci/checks.sh` -- expected: every block passes (storage, class-rules, ci-config).

**Measure and record** under this section: the median of 20 `Guide.Compute` calls, on the warm stack, for a session with all five steps' rows. The hook adds this cost to every trigger publish.

**Planned mutations** (apply each, observe red, revert, confirm `git status --short`/`git diff --stat` unchanged, and record it as `mutation: … → …`):
- AC 1, steps and payload:
  - `reminderSetOrFired` also matches `cancelled` → `Test.Demo.Guide` (step 2);
  - step 3 ignores the window (`since` "") → the second-run row;
  - `ANSWERED` gains `pending` → the step 4 row;
  - `Finished` without the resolved check → the finish row;
  - the rejected clamp removed → the current-step row;
  - `TelegramState()` returns "on" → `TestTelegramCountsAsOff`;
  - the owner bind of `newestIncident` dropped → the isolation test of `Test.Data.OwnershipGuide`.
- AC 1, Break the feed: the 180 s threshold becomes 181 → the 180 s stage row; `incidentInProgress` gains `resolved` → the busy row.
- AC 2, hook and tick:
  - `reminder` removed from `GUIDETRIGGERS` → `Test.Live.GuideRefresh`;
  - publish without comparing → its "no change" row;
  - no blank base → its blank row, and `live:sign-in` row 13's `streams`;
  - the `GuideTick` call removed → `Test.Core.StatusMonitorGuide`.
- AC 3, markers and `/state`:
  - `RunAgain` keeps `TraceOpened` → `Test.Web.GuideApi` and `guide.spec.ts` with mode 1;
  - the demo-off check removed → `Test.Web.GuideApi` and `guide.spec.ts` with mode 0;
  - the `StateBody` line removed → `Test.Web.GuideApi`, `api.spec.ts` row 13 and `guide.spec.ts`.
- AC 4, only the marker: `RunAgain` also deletes the session's `BreakFeedRun` rows → `Test.Web.GuideApi`'s "rows unchanged".

**Measured (implement stage, warm stack `e4s2iw`):** the median of 20 `Guide.Compute` calls, for a session with all five steps' rows (Orders check, reminder, resolved Orders incident with an approved request, a Break the feed run and the trace marker), is 0.46 ms (min 0.42 ms, max 0.52 ms). The hook adds that to every trigger publish while demo mode is on, and nothing with demo mode off.

**Mutations run (each applied, red observed, reverted byte-identical):**
- mutation: `ReminderSetOrFired` also matches `cancelled` (Ownership statement) -> `Test.Demo.Guide` `TestStepTwo` red ("a cancelled reminder alone").
- mutation: step 3 ignores the window (`window` = "") -> `Test.Demo.Guide` `TestSecondRun`, `TestRunAgain` and `TestStepThree` red.
- mutation: `ANSWERED` gains `pending` -> `TestStepFour` red ("pending request").
- mutation: `Finished` without the resolved check (`Set finished = 1`) -> `TestFinished` red ("while fixing").
- mutation: the rejected/fallback/no_fix clamp of the current step removed -> `TestCurrentStep` red (three variants).
- mutation: `TelegramState()` returns "on" -> `TestTelegramCountsAsOff` red.
- mutation: the owner check of `newestIncident` dropped (statement keeps its bind count) -> `Test.Data.OwnershipGuide` `TestNewestIncident` red (isolation).
- mutation: `NOTICEWAIT` 180 -> 181 -> `TestRunStages` ("180 s, sent") and `TestRunAgain` red.
- mutation: `incidentInProgress` gains `resolved` -> `TestBusyIncident` red ("resolved incident").
- mutation: `reminder` removed from `GUIDETRIGGERS` -> `Test.Live.GuideRefresh` red (`TestEachTriggerType`, `TestHookPublishesOnChange`, `TestHeldLock`, `TestEventsBodyServesTheGuide`).
- mutation: publish without comparing (`json '= base` dropped) -> `Test.Live.GuideRefresh` `TestHookPublishesOnChange` ("the same view again publishes none") and `TestNoRefresh` red.
- mutation: no blank base (`base` = "" when the stream has no guide.state) -> `Test.Live.GuideRefresh` `TestNoRefresh` ("a session whose view is the blank one") red; and `live:sign-in` aborts at its seeding check (the README session's second reminder event gets Seq 3, not 2), so row 13's `streams {session: 2}` is protected there.
- mutation: the `GuideTick` call removed -> `Test.Core.StatusMonitorGuide` red.
- mutation: `RunAgain` keeps `TraceOpened` -> `Test.Web.GuideApi` `TestRunAgain` red, and `live:demo-switch` fails at "demo mode 1: the page specs failed" (`guide.spec.ts`).
- mutation: the demo-off check removed from `GuideMarkers` -> `Test.Web.GuideApi` `TestDemoOff` red, and `live:demo-switch` fails at "demo mode 0: the page specs failed".
- mutation: the `StateBody` guide line removed -> `Test.Web.GuideApi` `TestStateCarriesTheGuide` red, and `live:demo-switch` fails at "demo mode 1: the page specs failed".
- mutation: `RunAgain` also deletes the session's `BreakFeedRun` rows -> `Test.Web.GuideApi` `TestOnlyTheMarkerChanges` ("run_again changes none of the session's data rows") red.
- mutation: the variant clause of `finished` removed (`closed` alone finishes) -> `Test.Demo.Guide` `TestFinished` red (four rows "closed after <variant> with an approved fix").
- mutation: `RunAgain` also sets the session's incidents to `closed` -> `Test.Web.GuideApi` `TestOnlyTheMarkerChanges` red ("run_again changes none of the session's data rows"; the fingerprint now holds incident states and approval requests).
- mutation: `GUIDESECONDS` 240 -> 290 -> `Test.Core.StatusMonitorGuide` `TestWindowEdges` red ("a run 250 s old is not").

**Shared surfaces:**
- The `/state` keys: `Test.Web.Api` `TestStateBody`/`TestStateFlags`, and `api.spec.ts` row 13. `guide` is the last key, with demo mode on.
- The route table: `TestRoutes`, and `api.spec.ts` `UNBUILT`.
- The `guide.state` payload contract and the part count: `Test.Live.Payloads`, and `payloads.ts` with `--check`.
- The `GuideState` table contract and its storage block: `Test.Data.Tables`, `test-storage.sh`.
- The events of a session stream with demo mode on. A `guide.state` now follows a trigger publish that changes the session's view. Search the test trees for `Live.Event).Since(`, `EventSeqs(`, `.States(`, `LastSeq(` and `streams.session`, and update any test whose session has Orders check, reminder, Orders incident, `BreakFeedRun` or `GuideState` rows.
- The `demo.mode` row, `^OcuTalonTest("TelegramIncluded")` and `onlineDemo`: saved and put back.
- `Fixture.Clean`: it now drops a fixture session's `GuideState` and `BreakFeedRun` rows.
- The README session of `live:demo-switch`: its guide rows change only after that unit's `/state` checks.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The server derives the guide: `Demo.Guide.Compute` and `Blank` read the session's rows through six new `Ownership` kinds, `Live.Publish.RefreshGuide` publishes `guide.state` only on a change (hook after the seven trigger types, `StatusMonitor.GuideTick` for runs under 240 s old, and the marker endpoint), `POST /v1/guide/markers` writes the two UI-only markers of `GuideState` (new `RunStartedAt`), and `/state` carries `guide` last while demo mode is on.

**Files changed.**
- Product: `Data/{GuideState,BreakFeedRun,Ownership}.cls`, `Demo/Guide.cls` (new), `Live/Publish.cls`, `Live/Payload/GuideState.cls`, `Live/Payload/Part/Guide{Step,BreakFeed}.cls` (new), `Core/StatusMonitor.cls`, `Web/Api.cls`, `web/src/app/live/payloads.ts` (generated).
- Tests: `Test/Demo/{Guide,GuideProbe}.cls`, `Test/Data/OwnershipGuide.cls`, `Test/Live/GuideRefresh.cls`, `Test/Core/StatusMonitorGuide.cls`, `Test/Web/GuideApi.cls` (new); `Test/Data/{Fixture,Tables}.cls`, `Test/Live/Payloads.cls`, `Test/Web/Api.cls`, `web/e2e/api/api.spec.ts`, `web/e2e/frame/frame.spec.ts` (outside the footprint: Epic 2's F9 key list); `web/e2e/demo-switch/guide.spec.ts` (new); `web/playwright.config.ts` (header).

**Review.** 29 findings: patches applied 5 entries (2 medium: the `finished` variant clause rows and the widened fingerprint of `TestOnlyTheMarkerChanges`; 3 low: the 240 s window test, the playwright header, the shared tick-window root cause), deferred 0, rejected 24 with the reasons in the Review Triage Log. The patches changed tests and one comment only.

**Follow-up review recommended:** false. Patched: medium 2, low 3; each new assertion was shown red by a mutation and no product code changed in review.

**Verification.** After the last patch: all 11 `(loop)` classes passed on the warm stack; `live demo-switch` (fresh) all PASS with `guide.spec.ts` in both modes; `shard lane-b` 49 classes and `shard lane-a` 41 classes passed; `live sign-in` 192 passed; `payloads.mjs --check`, `npm --prefix web run lint`, `npm --prefix web test` (567 pass) and `bash ci/checks.sh` passed. No stack with the tags `e4s2i` is left. The handoff subagent sent two warm class runs in one message once (both passed); no git or CI action by any subagent (HEAD unchanged until finalize).

**Residual risks.** With demo mode on, a session stream gains `guide.state` events after the first trigger publish that changes its view (Epic 8 tests that count stream events must expect them or turn demo mode off). Compute's median is 0.46 ms over 20 calls on the warm stack (see Verification).
