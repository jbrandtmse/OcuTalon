---
title: 'Story 39.7: Publish the heartbeat event'
type: 'feature'
created: '2026-11-04'
status: 'done'
baseline_revision: '6c00ff1d392f1e7817caa650bb9ab9e11f22ac35'
baseline_commit: '6c00ff1d392f1e7817caa650bb9ab9e11f22ac35'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Stories 39.3 and 39.4 commit a person's `HeartbeatBeat` row on every beat, skip and recorded decision, but nothing tells the page. The `heartbeat` live event is in the spine's event table with `Checks` as its publisher, yet `OcuTalon.Live.Payload.Heartbeat` does not exist, `Live.Publish` TYPES does not list it, and the generated `payloads.ts` has no interface for it (DW-633).

**Approach:** Create the payload class: the row's public view plus the person's on, interval and hours. Add the `heartbeat:Heartbeat` pair to TYPES, update the payload tests' counts and regenerate `payloads.ts`, all in one change. Then make `Checks.Beat` hand back a view at each row commit, and make `Checks.Process` publish those views to the person's stream, in commit order, after the beat's sends.

## Boundaries & Constraints

**Always:**
- Each committed row change gets one `heartbeat` event, in commit order, on the stream of the row's `SessionRef`. Row changes include:
  - a skip (the scheduled beat, or a run now that wrote only `LastRunNowAt`);
  - a beat that runs (scheduled or run now);
  - a recorded decision (`Settle`), for a person whose heartbeat is off too.
- When one call commits twice (a `Settle`, then a `Run` in the same `RunDue` or `RunNow`), two events go out. The first holds the recorded result, and the second holds the new state.
- A call that commits nothing for a person publishes nothing for them. That covers: not due, nothing pending, off with nothing pending, a run now on cooldown, and a read that threw before the save.
- The view is built from the row as just committed and from `Beat.Values(sessionRef)`. Its fields:
  - `on`, `interval`, `from`, `to`;
  - `nextDueAt`;
  - `lastBeatAt`, `lastOutcome`, `lastFallback`, `lastCostUSD`;
  - `traceHeaderId` (the row's `LastTraceSessionId`) and `traceNamespace` (`$Namespace`), both set only when that id is set (AD-12, AD-26);
  - `lastSkipAt`, `lastSkipReason`;
  - `lastRunNowAt`, `backoffUntil`.
- `Checks` (`OcuTalon.Checks.Process`) is the only class that calls `Publish` with `heartbeat`. It does so outside any transaction, after the call's Items have been sent (AD-12, AD-33).
- A publish that fails or throws logs one Type 3 warning, `LOGBEATPUBLISH`. The warning has its error text redacted and the `SessionRef` removed in any case (`WithoutRef`). The Tick and the BeatNow still answer as before, and the other views still go out.
- The class, the TYPES pair, `Test.Live.Payloads` (`EXPECTED` and 16 to 17 types, 30 to 31 contract classes), the regenerated `payloads.ts` and the live store's entry land in one commit (DW-633).
- Every test added or changed passes on a fresh environment, in either order. Fixed clocks wherever a time is asserted.

**Never:**
- The payload never holds:
  - the `SessionRef`, the checklist's text, `LastSnapshotKey` or `LastQuietKey` (AD-12, AD-33);
  - `LastItemId` or `LastDecisionRef`;
  - any rendered text (no all-clear, AD-28).
- No publish from `Checks.Beat`, `SettingsOps` or any other class. No event for a settings write (Story 39.2's).
- No hand edit of `payloads.ts`. It is only regenerated, with `npm --prefix web run payloads`.
- Only the files under Code Map, Footprint. In particular, none of these change:
  - `Web/Api.cls` (Epic 40's diff), `Core/**`, `Msg/**`, `Data/**`;
  - `web/src/app/api/**`, `web/src/app/rail/**`, `ci/**`, `docker/**`.
  - `web/scripts/payloads.test.mjs` changes by exactly one name: `'HeartbeatPayload'` added to the list of interfaces that carry `traceUrl` (the test at about line 110), nothing else [AMENDED 2026-11-05, lead ruling at the implement halt, decide: it read as a never-change file, which contradicted AC 4].
- No new production item, table, setting, route or test class. No stored field added. No `GUIDETRIGGERS` change.
- No route (`GET /api/v1/heartbeat` is Story 39.2's) and no card (Story 39.5's).
- No unit test on slot D. No real key and no real bot.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Beat runs | Due person, checklist, keyed, not capped; Tick at T | One `heartbeat` event equal to `FromRow(row, values)`. `lastBeatAt` T, `nextDueAt` T+interval, no `lastOutcome` | none |
| Skip | Due person with a checklist, outside hours | One event with `lastSkipAt` T, its reason and the moved `nextDueAt` | none |
| Skip, empty checklist (tick) | Due person, empty checklist, on a Tick | The row is saved with `lastSkipAt` T and reason `empty`; NO event (CI rework, veto ruling) | none |
| Recorded result | Pending beat; its `Decision` exists; next Tick | One event: `lastOutcome`, `lastFallback`, `lastCostUSD`, `traceHeaderId` = the decision's `TraceSessionId`, `traceNamespace`. A fallback also shows `backoffUntil` | none |
| Two commits in one call | Pending ignore and a due beat at the same Tick (39.3's `TestRecordedDecisionCountsInTheSameRunDue` shape) | Two events, in order: the recorded `ignore`, then the `unchanged` skip | none |
| Off, pending | Heartbeat off, decision pending | One event, `on` false, the result recorded | none |
| Nothing committed | Not due, nothing pending; or off with nothing pending | No event | none |
| Run now sent | BeatNow, beat runs | One event (two when a pending decision is recorded first), with `lastRunNowAt` = now | none |
| Run now held | BeatNow, empty checklist | One event, `lastRunNowAt` = now, `lastSkipAt` unchanged | none |
| Cooldown | Second BeatNow within 120 s, nothing pending | No event. With a pending decision, `RunNow`'s `Settle` commits first, so there is only that result's event; `lastRunNowAt` is unchanged | none |
| Never in the payload | Row with distinct tokens in `SessionRef`, `LastSnapshotKey`, `LastQuietKey`, `LastItemId`, `LastDecisionRef`; checklist token | The JSON holds exactly the keys listed above. No token appears in it | none |
| No row yet | `FromRow("", values)` (39.2's GET for a person with no beat) | Only `on`, `interval`, `from`, `to` | none |
| Publish fails | `PublishBeat` answers an error that names the `SessionRef` (as it is and in upper case) | One `LOGBEATPUBLISH` warning without the ref. Tick OK, Item still sent, other people's events still published | warning only |
| Served to the page (Integration) | Real production, Tick at T | `Web.Api.EventsBody(session, 0, 0)` serves the event: `type` `heartbeat`, `stream` `session`, the same payload | none |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Data/HeartbeatBeat.cls` -- the row (read only). Its fields are `SessionRef`, `NextDueAt`, `LastBeatAt`, `LastItemId`, `LastOutcome`, `LastFallback`, `LastCostUSD` (SCALE 6), `LastDecisionRef`, `LastTraceSessionId` (%Integer), `LastSkipAt`, `LastSkipReason` (32), `LastRunNowAt`, `BackoffUntil`, `LastSnapshotKey` and `LastQuietKey`.
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls` -- `Values` 104 gives {on, interval, from, to, checklist}. The commit points:
  - `Run` 476 saves at 492 (skip) and 511 (beat);
  - `Settle` 516 saves at 532, and reads `Values` only for a fallback;
  - `RunDue` 385 calls `Settle` in its first loop (every pending row, on or off) and `Run` in its second;
  - `RunNow` 442 calls `Settle` then `Run`; a cooldown at 457 writes nothing.

  The class doc is lines 1-32.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls`:
  - `Tick` 177-223: the beats at 204-222;
  - `BeatNow` 226-261;
  - the seams `BeatRunDue` 269 and `BeatRunNow` 275;
  - `WithoutRef` 263;
  - `Announce` 631, the check event's sibling;
  - `LOG*` parameters 127-151, `CHECKEVENT` 88;
  - class doc lines 15-28, and 61-62 ("the only one that publishes the check event").
- `src/ocutalon/cls/OcuTalon/Live/Publish.cls` -- `TYPES` at line 18 and `Publish` 82. `Publish` refuses an open transaction, and its "busy" error names the stream, which is the SessionRef.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Check.cls`, `Reminder.cls` -- the siblings: `%RegisteredObject` and `%JSON.Adaptor`, one property per line with `%JSONFIELDNAME` = the camelCase name, and `FromRow` setting the trace pair only when the id is set.
- `web/scripts/payloads.mjs` -- reads TYPES and every payload class, fails closed on a class not in TYPES, and adds `traceUrl?` when both trace keys are present. Run it with `npm --prefix web run payloads`; the build runs `--check`.
- `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls`:
  - class doc lines 1-2 ("30 payload");
  - `EXPECTED` 14;
  - `TestEventTable` 32-73 (16 at 37, 38, 71 and in the doc at 32-33);
  - `TestContracts` 93 (`classes, 30`);
  - `XData Contracts` 891, alphabetical, which needs a `Heartbeat` entry;
  - `TestCheckFromRow` 469, the shape of a FromRow test.

  Epic 7's `DryRun` lines and `TestApprovalEitherWay` are in the base: edit around them.
- `src/ocutalon/cls/OcuTalon/Test/Contract/Checker.cls` -- `TestEveryPinnedPartOfEveryContractIsDetected` (classes >= 47) also exercises the new contract. It needs no change, but run it.
- `web/src/app/live/live-store.ts` -- `COLLECTIONS: Readonly<Record<LiveEventType, CollectionRule>>` 40-57. TypeScript requires an entry for every type. `applyEvent`'s `default` returns the store unchanged.
- `web/scripts/live-store.test.mjs` 306 -- `types.length, 16`, and keys equal to the union. `web/scripts/payloads.test.mjs` 60 checks only that its 16 listed types are present, so it stays green unchanged.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` `EventsBody` 947 and `Web/TraceLink.cls` `Add` 60 -- the consumer (read only). `Test/Core/Observe.cls` `Events` 47.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Probe.cls` -- `BeatRunDue` 168 and `BeatRunNow` 181 override the seams. Both call the real Beat while `BeatSessions` is set. Class doc 25-30.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls` -- the shapes to follow:
  - `TestTickSendsTheBeats` 1020 and `TestBeatSendFailureIsLogged` 1051;
  - helpers `Host` 1252, `Owner` 1261, `Events` 1455 (type `check`; add a heartbeat twin), `Warnings` 1474 (filters by logging method), `Beating` 1506, `TICK`/`NEXT` 67/70.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls` -- `TestRecordedDecisionCountsInTheSameRunDue` 540. Helpers `Open` 645, `Person` 685, `Decision` 718, `BDue` 815.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Heartbeat.cls` -- `TestBeatReachesIntake` 370, `TestBeatNowReachesIntake` 405, `TestAnHourOfTicks` 445; class doc 1-47.
- Spine: the event table row `heartbeat | Checks | A` (line 1322) and the payload row (1299) already exist, so no spine row is added.
- **Footprint** (one commit):
  - new: `Live/Payload/Heartbeat.cls`;
  - edited: `Live/Publish.cls` (the TYPES pair only), `Test/Live/Payloads.cls`, `web/src/app/live/payloads.ts`, `Checks/Process.cls`, `Checks/Beat.cls`, `Test/Checks/{Probe,Beat,Runs,Heartbeat}.cls`, `web/src/app/live/live-store.ts` (one entry), `web/scripts/live-store.test.mjs` (one number).

  None of these is in the diff of Epic 11, 33 or 40 (checked 2026-11-04 against `origin/feature/OCT_OcuTalon_MVP` `ac2c4549`).

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Live/Payload/Heartbeat.cls` (new, DW-633) -- `Extends (%RegisteredObject, %JSON.Adaptor)`. Properties, in this order, each on one line with its camelCase `%JSONFIELDNAME`:
  - `On` %Boolean, InitialExpression 0;
  - `Interval` %Integer;
  - `From`, `To` %String(MAXLEN 5);
  - `NextDueAt`, `LastBeatAt` %String(MAXLEN 20);
  - `LastOutcome` %String(MAXLEN 32);
  - `LastFallback` %Boolean, InitialExpression 0;
  - `LastCostUSD` %Numeric(SCALE 6);
  - `TraceHeaderId` %Integer, `TraceNamespace` %String(MAXLEN 128);
  - `LastSkipAt` %String(MAXLEN 20), `LastSkipReason` %String(MAXLEN 32);
  - `LastRunNowAt`, `BackoffUntil` %String(MAXLEN 20).

  Add `ClassMethod FromRow(row As OcuTalon.Data.HeartbeatBeat, values As %DynamicObject)`. It sets on, interval, from and to from `values`. When `row` is an object, it also sets the row fields, and the trace pair only when `LastTraceSessionId` is set. Class doc: "Lane A publishes it (Checks)", and that Story 39.2's GET reuses `FromRow`.
- `src/ocutalon/cls/OcuTalon/Live/Publish.cls` -- append `,heartbeat:Heartbeat` to `TYPES`. Nothing else.
- `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls` -- the changes:
  - `EXPECTED` gets the same pair;
  - 16 becomes 17 in `TestEventTable` and its doc, and 30 becomes 31 in `TestContracts` and the class doc;
  - a `Heartbeat` entry in `XData Contracts`;
  - new `TestHeartbeatFromRow`, for the matrix rows "Never in the payload" and "No row yet": the exact key set of `%JSONExportToString`, no token, the trace pair only with an id, and `FromRow("", values)`.
- `web/src/app/live/payloads.ts` -- regenerate with `npm --prefix web run payloads`.
- `web/src/app/live/live-store.ts` -- append `heartbeat: { collection: 'heartbeat', key: null },` as the last entry of `COLLECTIONS`. Nothing else. The store keeps ignoring the type until Story 39.5 adds its field and case.
- `web/scripts/live-store.test.mjs` -- 16 becomes 17 in the count and its message.
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls` -- add a trailing `Output views` to `RunDue` and `RunNow`. It is a local array: `views` is the count, `views(n)` the SessionRef, and `views(n, "payload")` the `Live.Payload.Heartbeat` of the row just committed. A private helper appends one view right after each successful save in `Run` (both saves) and `Settle`; `Settle` reads `Values` once. Update the class doc (one bullet: the views, in commit order, and nothing without a commit).
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- the changes:
  - `HEARTBEATEVENT = "heartbeat"` and `LOGBEATPUBLISH = "Checks could not publish a heartbeat event: "`;
  - the seams `BeatRunDue` and `BeatRunNow` gain `Output views`;
  - new `AnnounceBeat(sessionRef, payload)`: it calls the new seam `PublishBeat(sessionRef, payload) As %Status` (`Live.Publish.Publish`), logs `LOGBEATPUBLISH` with `WithoutRef` and `Redact.Text` on an error status or a throw, and never throws;
  - `Tick` and `BeatNow` call it for each view, in order, after their sends. In `Tick` this is after the Items loop; `views` is killed before the beats' Try.

  Update the class doc bullets and the "only one that publishes" line.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Probe.cls` -- `BeatRunDue` and `BeatRunNow` take `Output views` and pass it to the real Beat. A new `BeatPublishError` property makes `PublishBeat` answer an error naming the SessionRef, as it is and in upper case; otherwise `PublishBeat` calls the real one. Update the doc.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls` -- new `TestViewsInCommitOrder`, through `BDue` and `RunNow`, covering these matrix rows: Two commits in one call, Off pending, Nothing committed, Run now sent, Run now held and Cooldown. It asserts the refs, the order, and `%JSONExportToString` equal to `FromRow` of the reopened row at each point.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls` -- new `TestTickPublishesTheBeats` (Beat runs, Skip and Recorded result, with a twin of `Events` for type `heartbeat`). Also `TestBeatNowPublishes`, and `TestBeatPublishFailureIsLogged` (the Publish fails row). Update the class doc.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Heartbeat.cls` -- extend three tests:
  - `TestBeatReachesIntake`: one event after T0, a second with the recorded outcome after T0+60. The Integration row: `Web.Api.EventsBody` serves both.
  - `TestAnHourOfTicks`: exactly 3 events in the hour (beat, result, skip at 30), so the 57 other Ticks publish nothing.
  - `TestBeatNowReachesIntake`: one event with `lastRunNowAt` = t0. After the cooldown BeatNow there are exactly two events: the second is the recorded `ignore`, written by that BeatNow's `Settle` or by a real Tick before it, with `lastRunNowAt` still t0.

  Each event's JSON holds neither the ref nor the checklist. Update the class doc.

**Acceptance Criteria:**
- AC 1 -- Given a beat, a skip or a recorded result, when its row is committed, then `Checks` publishes one `heartbeat` event to the session's stream with the row's public view: on, the interval, the hours, next due, the last result and the last skip (AD-12, AD-18). Except: a Tick's skip with reason `empty` (no checklist) publishes no event; its row is still saved, and a run-now still publishes [AMENDED 2026-11-05, CI rework, veto ruling].
- AC 2 -- Given a row whose `SessionRef`, checklist and keys hold distinct tokens, when its heartbeat event is published, then the payload holds none of them. And when the publish fails, then the warning names no `SessionRef` in any case (AD-12, AD-33).
- AC 3 -- Given a person for whom a Tick or BeatNow commits nothing, when it runs, then no event is published for them.
- AC 4 (DW-633) -- Given the new class and TYPES pair, when the IRIS payload tests and the web checks run, then all of these agree: TYPES, `Test.Live.Payloads` (17 types, 31 contract classes), `payloads.ts` (`--check` clean, `HeartbeatPayload` with `traceUrl?`) and the live store (17 entries). And `npm --prefix web test`, `lint` and `build` pass.
- [x] [Clarification] Add `'HeartbeatPayload'` to the list of interfaces that carry `traceUrl` in `web/scripts/payloads.test.mjs` (the test "is on exactly the interfaces that have both traceHeaderId and traceNamespace", about line 110), and nothing else in that file; then `npm --prefix web test` is green (AC 4).
- [x] [CI] browser `live:sign-in` L10 (`web/e2e/live/live.spec.ts:405`) red on f20a41c2: `data-session-seq` 4, expected 3. Cause: a session with no checklist (heartbeat on by default) gets a Tick `empty` skip on its first tick, and 39.7 published it, moving the session stream's seq under the test. Fix in `Checks/Beat.cls`: a Tick's (RunDue's) skip with reason `SKIPEMPTY` adds no view (the row is still saved; Settle's recorded result, other skips, beats and RunNow, including a run-now held by an empty checklist, still add one). Pin it: a Tick test that a due person with an empty checklist gets a saved `empty` row and NO view/event (mutation: add the view back -> red), and update any existing test that expected an event for a Tick `empty` skip. Do NOT edit `web/e2e/**` (contended by Epic 11).
- [x] [CI] `.github/workflows/ci.yml`: the `checks` job's `timeout-minutes` from 15 to 20 (the Contest Planner's pre-ruling; a clean run takes about 13.7 minutes; same job, same name). Change no other job. `ci/checks.sh` already prints each script's elapsed seconds (`==== <name> passed|failed <n>s`): no change there. Run `docker/tests/test-ci-config.sh` after the edit.
- Integration AC -- Given a real Tick that runs a beat, when the page polls, then `Web.Api.EventsBody` (the real `/api/v1/events` body) serves it as `{type: "heartbeat", stream: "session", payload}`. The generated `HeartbeatPayload` types it, and the live store accepts the type.

### Review Findings

Code review 2026-11-05 (runner D; four layers, full-opus; 25 rows, 9 entries after grouping and rejection: high 0, med 2, low 7).

- [x] [Review][Patch] (med; fix-risk low, test-only) `TestBeatNowReachesIntake` (and `TestBeatReachesIntake`'s first read) asserted exactly one event, but a real Tick may record the decision and publish the outcome before the read: a timing red [src/ocutalon/cls/OcuTalon/Test/Checks/Heartbeat.cls:397,497] -- the first read now accepts one or two events, asserts event 0 is the beat or run now and a second is the recorded outcome; "exactly two" after the cooldown stays.
- [x] [Review][Patch] (med; fix-risk low, test-only) `TestBeatPublishFailureIsLogged` counted and `RemoveLogs` deleted every `AnnounceBeat` warning since the mark, so a real Checks job's warning would be counted and removed (Rule 19 hermeticity) [src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls] -- `BeatPublishWarnings` and the removal now match only lines holding the probe's own error text (`BEATPUBLISHREFUSED`).
- [x] [Review][Patch] (low) BeatNow's "publish after the send" was not pinned (Tick only) [src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls] -- `TestBeatPublishFailureIsLogged` asserts the BeatNow's publish saw its Item kept; mutation below.
- [x] [Review][Patch] (low) `TestFailedCommitsGiveNoView`'s comments said the save fails "for its copy to LastQuietKey"; it fails on LastSnapshotKey's own MAXLEN [src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls] -- comments corrected.
- [x] [Review][Patch] (low) `Test.Live.Payloads` class doc did not name Heartbeat among the 31 classes or `TestHeartbeatFromRow` [src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls:2] -- doc updated.
- [x] [Review][Patch] (low) `Test.Checks.Runs` class doc omitted `TestTickPublishesEachCommitInOrder` [src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls] -- listed.
- [x] [Review][Patch] (low, Rule 19) AC 4's contract half (`TestContracts`, the Heartbeat contract entry) had no mutation line and the live-store mutation's `ng build` half was not shown red -- both demonstrated below.
- [x] [Review][Defer] (low; fix-risk high) The Beat and Runs fixtures' pending decisions can be settled first by a real HeartbeatIn Tick (milliseconds window; Story 39.3's tests have the same shape) [src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls] -- deferred: pre-existing shape; DW-711 `wontfix-accepted` with `reopen_if`.
- [x] [Review][By-design] (low) `web/scripts/payloads.test.mjs` still lists 16 event pairs, so the generated `'heartbeat': HeartbeatPayload` map line is pinned only by `--check` and the traced list -- the spec's Never line allows exactly one name in that file; reopens only by a spec amendment.

Rejected:
- Settings writes publish no heartbeat event (Blind, Edge) -- spec-bound: "No event for a settings write (Story 39.2's)"; AD-33 keeps `SettingsOps` from publishing this type; the PUT answer carries it.
- Views made before a RunDue/RunNow exception are untested (Blind, VGap) -- low: the Output array is passed by reference, so the claim holds by construction; a test needs a new probe mode.
- `lastFallback` is `false` on a beat with no result while `lastOutcome` is absent (Blind) -- low: `lastOutcome` decides; the card is Story 39.5's.
- `Settle` reads `Values` for every recorded decision, a second read in the same RunDue (Blind) and a failed read blocks a decision (Edge) -- low/theoretical, as the implement triage found (Blind 2).
- `AddView` throwing after the save (Edge) -- theoretical (implement triage Blind 1).
- `FromRow` with a non-object `values` (Edge) -- theoretical: `values` is typed `%DynamicObject` and `Values` always answers one.
- The Tick's Items loop has no Try, so a throwing send loses the views (Edge) -- theoretical: `SendOwn` answers a status; the loop is unchanged from the base.
- The live-store test name "accepts" overstates (Blind) -- low: the store ignores the type until Story 39.5, which the test pins.
- `live-store.test.mjs` gained a QA test beyond "one number" (Auditor) -- false as a defect: the file is in the Footprint and adding tests is QA's role.
- No `ref` key in the payload against AD-12's "keyed by its public Ref" (Auditor) -- by design (Decided in-stage): the only Ref is the SessionRef, which AD-12/AD-33 forbid.
- Bookkeeping status and dates disagree; `payloads.test.mjs` listed as "unchanged" under Shared surfaces (Blind, Auditor) -- not code; the fix edits the spec.

## Spec Change Log

- 2026-11-05, lead, rework iteration 1 (trigger ci): CI on f20a41c2 failed browser `live:sign-in` L10 because every session without a checklist got a heartbeat event at its first Tick. Ruling (veto): a Tick's `empty` skip publishes no event; AC 1 and the Matrix are amended, and epics.md's 39.7 block carries the same amendment. Also the `checks` job's timeout 15 -> 20 per the Planner's pre-ruling.

- 2026-11-05, lead, answering the implement stage's intent gap (decide, round 1): `web/scripts/payloads.test.mjs` hardcodes the interfaces that carry `traceUrl`, and `HeartbeatPayload` has both trace fields, so AC 4 needs one name added there. The file is Lane B like this story, in no open epic's diff (11, 33, 40), and the change is a one-name append to a list (standing precedent), so it is allowed and reported as a footprint extension. The Never line is amended and one open task added; the earlier pass's implementation stays in the working tree, uncommitted, for this pass to finish.

## Review Triage Log

### 2026-11-04 -- Review pass
- verdicts: 29 findings -- high 0, medium 6, low 22, false 1, maybe-false 0 (a duplicate keeps its own row and verdict)
- findings:
  - `[low]` `[reject]` Blind 1: `AddView` after the save can throw and lose the Item -- `FromRow` only copies properties and `Values` is plain settings reads that the same person's own `Run` already did; a guard adds a branch for a failure that no input reaches.
  - `[low]` `[reject]` Blind 2: `Settle` now reads `Values` for every recorded decision -- `RunDue` counts a throw as that person's failure and `BeatNow` answers failed; the same read already precedes the person's beat; theoretical.
  - `[low]` `[reject]` Blind 3: a crash between commit and publish loses the event with no replay -- by design (AD-12 publishes after the commit): the next commit republishes the whole view (store key null) and Story 39.2's GET is the reconciliation.
  - `[medium]` `[patch]` Blind 4: no test for a publish failure in the BeatNow path -- real; `TestBeatPublishFailureIsLogged` now also runs a BeatNow whose publish fails (answers sent, one more warning, no ref, no secret); mutation recorded.
  - `[low]` `[reject]` Blind 5: `TestBeatNowReachesIntake` leaves open whether Settle or a Tick wrote the second event -- the spec's task text allows either; the count is 2 on both paths.
  - `[low]` `[reject]` Blind 6: `FromRow` not tested for a row with no decision or cost -- `TestTickPublishesTheBeats` and `TestBeatNowPublishes` assert a beaten row's payload (no `lastOutcome`) against `FromRow`; a missing cost cannot hurt a reader.
  - `[low]` `[reject]` Blind 7: the FromRow JSON helper is repeated in four test classes -- real but not a two-way door (the classes have different bases); accepted, reopen_if a fifth copy is added.
  - `[low]` `[reject]` Blind 8: no web test of the `heartbeat` collection -- `live-store.test.mjs` pins an entry for every type and the store ignores the type until Story 39.5.
  - `[low]` `[reject]` Edge 1: same root cause as Blind 1.
  - `[low]` `[reject]` Edge 2: same root cause as Blind 2.
  - `[low]` `[reject]` Edge 3: a view for a `HeartbeatBeat` row whose Session row is gone goes to an orphan stream -- harmless like any publisher's; no user-reachable path.
  - `[low]` `[reject]` Edge 4: a busy stream drops the view and stalls the Tick up to the lock wait -- the same bound as every `Publish` caller; the next commit republishes the full view.
  - `[medium]` `[patch]` Edge 5: an all-day person's payload shape is not pinned -- real; `TestHeartbeatFromRow` now asserts that empty `from`/`to` are absent from the JSON; mutation recorded.
  - `[medium]` `[patch]` Edge 6: BeatNow's publish error and throw path is untested -- same root cause as Blind 4, fixed with it.
  - `[low]` `[patch]` Edge 7: the Beat class doc says a cooldown commits nothing, but one with a pending decision gives the result's view -- the doc now reads "a run now on cooldown with nothing pending".
  - `[low]` `[reject]` Edge 8: "Never throws" on `AnnounceBeat` but the log call in the Catch is unguarded -- the same shape as `Announce` and the other `LOG*` sites; a throwing logger is not a reachable input.
  - `[medium]` `[patch]` VGap 1: the redaction of the `LOGBEATPUBLISH` text is not pinned -- real; the probe's errors can end with a secret (`BeatPublishSecret`) and the test asserts it is absent; mutation recorded.
  - `[medium]` `[patch]` VGap 2: views made before a RunDue error status are published but untested -- real (the class doc claims it); `TestBeatPublishesWhatRunDueCommittedBeforeAnError`; mutation recorded.
  - `[low]` `[patch]` VGap 3: "publish after the sends" is not verified -- the probe records the kept Items at each publish and the failure test asserts `3,3,3`; mutation recorded.
  - `[medium]` `[patch]` VGap 4: the all-day shape is not pinned -- same root cause as Edge 5.
  - `[low]` `[patch]` VGap 5: pinning tests without a `mutation:` line (the `payloads.test.mjs` entry, GuideRefresh, redaction, the publish-fails and error-status paths) -- lines written for each new or changed one; the Heartbeat contract entry is pinned by the TYPES mutation and `Contract.Checker`.
  - `[low]` `[reject]` VGap 6: `GuideRefresh.cls` is outside the spec's Footprint -- true and needed (a shared surface); no epic's diff (11, 33, 40) holds it; reported as a footprint extension.
  - `[low]` `[reject]` VGap 7: no IRIS test that a served heartbeat event carries `traceUrl` -- `TraceLink.Add` is generic and tested in Epic 2; the Integration test asserts the trace pair.
  - `[low]` `[reject]` VGap 8: no single-publisher scanner for `heartbeat` in `Test.Bridge.CodeRules` -- outside the Footprint and no AC; `Checks.Process` is the only caller by construction.
  - `[low]` `[reject]` VGap 9: no test that `Values` failing in `Settle` blocks a decision -- same root cause as Blind 2.
  - `[false]` `[reject]` Intent 1: "outside any transaction" is not asserted -- `Live.Publish.Publish` refuses an open transaction, so the call cannot run inside one.
  - `[low]` `[reject]` Intent 2: the single publisher is not enforced by a test -- same as VGap 8.
  - `[low]` `[reject]` Intent 3: cross-person commit order inside one RunDue is tested only at the Beat level -- `AnnounceBeats` iterates the array in order and the Tick-level test pins the order of one person's two commits.
  - `[low]` `[reject]` Intent 4: the BeatNow publish-failure path is untested -- same root cause as Blind 4, fixed with it.

### 2026-11-04 -- Review pass (CI rework, iteration 1; four layers)
- verdicts: 18 findings -- high 0, medium 2, low 16, false 0, maybe-false 0 (a duplicate keeps its own row and verdict)
- findings:
  - `[low]` `[reject]` Blind 1: the Settle view goes stale when an empty skip follows it in one RunDue -- by design: the veto ruling makes the empty Tick skip silent, the row keeps it, and the next published commit carries it; spec-bound (AC 1, matrix row "Skip, empty checklist (tick)").
  - `[low]` `[reject]` Blind 2: the page's schedule for an empty-checklist person lags the row -- same root cause as Blind 1; the amended AC 1 states it.
  - `[medium]` `[patch]` Blind 3: the `runNow ||` half of the guard has no recorded mutation -- real (Rule 19); mutation A applied, red in `Beat.TestViewsInCommitOrder` and two `Runs` tests, lines added under Verification.
  - `[low]` `[reject]` Blind 4: nothing pins `timeout-minutes` 20 -- the pin would live in `docker/tests/test-ci-config.sh`, outside the footprint (`docker/**`), and a config value has no AC to pin; closed with reopen_if a `checks` run is cancelled at the limit.
  - `[low]` `[patch]` Blind 5: the new mutation heading carried a date ahead of the session date -- heading corrected to 2026-11-04 (the lead's own dated entries are left as written).
  - `[low]` `[patch]` Blind 6: the test header says "the other skips ... each give one" and tests one -- reworded to the back-off skip it exercises; a whitespace-only checklist case is not added (`Skip` is covered by `TestSkipOrder`).
  - `[low]` `[reject]` Edge 1: stale state after an earlier skip when the checklist is cleared -- same root cause as Blind 1.
  - `[low]` `[reject]` Edge 2: suggestion to publish once when the reason changes to empty -- would contradict the veto ruling (no event for the empty Tick skip); every event moves the session seq.
  - `[low]` `[reject]` Edge 3: the unamended "Always" bullet lists a skip as publishing -- the fix edits the spec's intent block, which this build does not do; AC 1 and the matrix row carry the exception.
  - `[low]` `[reject]` Edge 4: the Tick test no longer pins an hours skip -- the guard keys on the reason `empty` alone, and `Beat.TestSkipsAreRecordedByRunDue` and `TestViewsInCommitOrder` cover the other reasons' views; a back-off exercises the same branch.
  - `[low]` `[reject]` Edge 5: `ci.yml` is not in the Footprint -- the `[CI]` task names it; the fix edits the spec.
  - `[low]` `[reject]` VGap 1: nothing pins `timeout-minutes` 20 -- same as Blind 4.
  - `[medium]` `[patch]` VGap 2: mutations for `runNow ||` and for a guard widened to every RunDue skip are not recorded -- same root cause as Blind 3; both applied and observed red, lines added.
  - `[low]` `[reject]` VGap 3: the pending-decision block repeats the DW-711 shape (a production's Tick could settle first) -- the throwaway test stack runs no production, so no Tick can reach the seeded row; no further entry.
  - `[low]` `[reject]` VGap 4 (other): the browser symptom is not run by any check in the diff -- run in this pass: `ci/iris.sh live sign-in --part 2/2` (holds `live.spec.ts`, L10) passed, 116 tests.
  - `[low]` `[reject]` Intent 1: the `Process.cls` class comment does not mention the `empty` exception -- outside this pass's footprint; `Beat.cls` states it, and the comment's "committed row" still holds.
  - `[low]` `[reject]` Intent 2: the matrix row "Skip" is now exercised by a back-off, not hours -- same as Edge 4.
  - `[low]` `[reject]` Intent 3: the browser surface is not exercised by the diff's tests -- same as VGap 4.

## Design Notes

**Governing ADs:**
- AD-12: one publisher per type, publishing after the commit, a full view, and the trace pair.
- AD-33: `Checks` is the single publisher, and the ownership tables are unchanged.
- AD-18: "after each beat, skip or result".
- AD-29 and U-177: lanes, with the orchestrator's rulings.
- AD-26: the trace target. AD-28: no rendered text.

No AD's Rule changes. The spine's event-table row (line 1322) and payload row (1299) already exist. Their "Story 39.1 / 39.3" cells may be corrected to 39.7 by the lead: that is bookkeeping, not this story's edit. AD-1 and AD-14 are not cited (U-268: nothing relies on Story 33.2).

**Lanes:** this is a Lane B story by the 11:49Z ruling. `Live.Payload.Heartbeat` stays Lane A in the ownership table, published by `Checks`. The Lane A edits (`Checks/{Process,Beat}.cls`, `Test/Checks/**`) run under the 2026-11-04 evening ruling and Epic 39's paths_hint.

**footprint_extensions** for the runner's report:
- `Live/Publish.cls`, `Test/Live/Payloads.cls`, `payloads.ts`, `Checks/Process.cls` and `Test/Checks/Heartbeat.cls`, all by ruling;
- `Checks/Beat.cls` and `Test/Checks/{Probe,Beat,Runs}.cls`, under paths_hint;
- `web/src/app/live/live-store.ts`, a one-entry append the dispatch anticipated;
- `web/scripts/live-store.test.mjs`, the live store's own event-count assertion (16 to 17). Without these last two, `ng build` fails on the typed `Record<LiveEventType, ...>` and `npm test` fails on the count. No open epic touches either file.

**Decided in-stage:**
- **One event per commit, not one per person per call.** The AC reads "any recorded result, when its row is committed". In a `RunNow` (or a late `RunDue`), a `Settle` followed by a `Run` would otherwise never show the recorded result: `Run` clears it.
- **`Beat` returns the views and `Process` publishes them**, so `Checks` stays the single publisher and `Beat` keeps no host. The views go out after the sends, so a slow stream lock never delays a model request. `PoolSize` 1 serializes Ticks and BeatNows, so a stream's events stay in commit order.
- **The view adds `lastRunNowAt` and `backoffUntil`** beyond the AC's list. They hold no secret, and the card needs the cooldown and the back-off after a reload.
- **The view leaves out `LastItemId` and `LastDecisionRef`.** The trace is the pair `traceHeaderId`/`traceNamespace` (AD-12's names), so `TraceLink.Add` adds `traceUrl`.
- **There is no `ref` key.** The person is the stream, and the live store keys the event `null`, as `guide.state` is keyed.
- **`LOGBEATPUBLISH` is a new text**, not `LOGPUBLISH` ("could not publish check ..."). `WithoutRef` is required because `Publish`'s busy error names the stream.
- **The `ng` store ignores the event until Story 39.5.** Adding the store field is Story 39.5's.

**Extend, don't copy (Rule 2):**
- `Live.Payload.Heartbeat` follows `Live.Payload.Check` and `Reminder`: the same base classes, the camelCase keys, and a `FromRow` with a guarded trace pair.
- `Process.AnnounceBeat` follows `Process.Announce` (631). It is a sibling method, not a widened `Announce`, because `Announce`'s log line names a check Ref and `AnnounceBeat`'s must name none.
- `PublishBeat` is a seam like `SendFinding`.

**Integration ACs:** the Integration AC above, on the real production, polling body and generated types.

**Consumed-by:**
- 39.5 (the card): updates from the event. It needs a store field and an `applyEvent` case.
- 39.2 (`GET /api/v1/heartbeat`): returns `FromRow(row, Beat.Values(ref))`, with `row` "" for a person with no beat.

Not on the row, so not in the event:
- today's heartbeat cost: 39.5 reads it elsewhere, or a later story adds a field;
- a settings save: 39.2's PUT answer carries it, because `SettingsOps` may not publish this type (AD-33).

**Consumes:**
- `Checks.Beat`'s commits (39.3, 39.4);
- `Live.Publish` (Story 0.5);
- `Web.Api.EventsBody` and `Web.TraceLink` (Epic 2).

**Ledger inbox:** DW-633 is addressed by the first four Execution items and AC 4. Its 39.3-era note ("correct the spine Built-in cell") is the lead's bookkeeping, recorded above.

## Verification

`<lane>` is `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=39 stage=implement'`.

Run rules:
- Every command is a foreground call with `timeout: 600000`, one test class per call, never two at once.
- Slot D (`server: ocutalon-slot-d`, `namespace: OCUTALON`) is only for `iris_doc_load` and compiling.
- Tear down only your own tags, also after a failure.

**Commands:**
- (loop) `npm --prefix web run payloads`, then `node web/scripts/payloads.mjs --check`. Expected: "generated files are current".
- (loop) `npm --prefix web test`. Expected: exit 0.
- (once) `npm --prefix web run lint`, then `npm --prefix web run build`, one per call. Expected: exit 0.
- (once) `<lane> OCUTALON_RUN_TAG=e39s7impl ci/iris.sh build`, after the web change. Expected: OK.
- (loop) `<lane> OCUTALON_RUN_TAG=e39s7implw ci/warm.sh up`, once. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e39s7implw ci/iris.sh class <C>`, one per call, for `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Checks.Beat` and `OcuTalon.Test.Checks.Runs`. Expected: `CLASS ... passed`.
- (once) the same, warm, for `OcuTalon.Test.Contract.Checker`, `OcuTalon.Test.Bridge.CodeRules` and `OcuTalon.Test.Live.Publish`. Expected: passed.
- (loop) `<lane> OCUTALON_RUN_TAG=e39s7impl ci/iris.sh class OcuTalon.Test.Checks.Heartbeat`, fresh, because it runs the production. Expected: passed; record the time.
- (once) `<lane> OCUTALON_RUN_TAG=e39s7impl ci/iris.sh shard lane-a@Checks`, then the same with `--reverse`; then `shard lane-b@Live` and its `--reverse`. All fresh, one per call. Expected: passed.
- (once) `bash docker/tests/test-ci-config.sh`, then `bash docker/tests/test-boundaries.sh`. Expected: exit 0.
- (once) `git diff --name-only 35a326d064fe7d80e450b6ad4af50407cab653a0` lists only the Footprint files and this spec, and `git diff 35a326d0 -- src/ocutalon/cls/OcuTalon/Live/Publish.cls` changes only line 18. Expected: true.
- (once) `<lane> OCUTALON_RUN_TAG=e39s7implw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e39s7impl ci/iris.sh teardown`, also after a failure.

**Pinning mutations.** For each, apply it, observe red, revert byte-identical and record it (Rule 19):
- AC 1: drop the view append after `Settle`'s save. Expected red: `Beat.TestViewsInCommitOrder` and `Heartbeat.TestBeatReachesIntake`'s second event.
- AC 1: publish the views in reverse order. Expected red: `TestViewsInCommitOrder` and `Runs.TestTickPublishesTheBeats`.
- AC 2: `FromRow` sets `LastSkipReason` from `row.LastSnapshotKey`. Expected red: `Payloads.TestHeartbeatFromRow`.
- AC 2: `AnnounceBeat` logs without `WithoutRef`. Expected red: `Runs.TestBeatPublishFailureIsLogged`.
- AC 3: `RunDue` appends a view for every person it reads. Expected red: `Heartbeat.TestAnHourOfTicks` (3 events) and the Nothing committed row.
- AC 4: TYPES without the pair. Expected red: `Payloads.TestEventTable`, and `payloads.mjs --check` fails.
- AC 4: drop the live-store entry. Expected red: `live-store.test.mjs`, and `ng build` fails.
- Integration: publish to `Live.Publish.#INSTANCE`. Expected red: `TestBeatReachesIntake`'s `EventsBody` assertion (`stream` is not `session`).

Mutation results (implement stage; each applied, observed red, reverted byte-identical; `git status --short` and `git diff --stat` unchanged by the reverts):
- mutation: drop the view append after `Settle`'s save -- red `Beat.TestViewsInCommitOrder` (warm) and, fresh, `Heartbeat.TestBeatReachesIntake` (second event, EventsBody), `TestAnHourOfTicks` (3 events) and `TestBeatNowReachesIntake` (two events).
- mutation: publish the views in reverse order (`AnnounceBeats`) -- red `Runs.TestTickPublishesEachCommitInOrder` (the two-commit case; `TestTickPublishesTheBeats` has one event per stream, so it stays green). `Beat.TestViewsInCommitOrder` cannot see it: `Beat` publishes nothing.
- mutation: `FromRow` sets `LastSkipReason` from `row.LastSnapshotKey` -- red `Payloads.TestHeartbeatFromRow`.
- mutation: `AnnounceBeat` logs without `WithoutRef` -- red `Runs.TestBeatPublishFailureIsLogged`.
- mutation: `RunDue` appends a view for every person it reads -- red `Beat.TestViewsInCommitOrder` (the Nothing committed rows) and, fresh, `Heartbeat.TestAnHourOfTicks` (and `TestBeatReachesIntake`).
- mutation: TYPES without the pair -- red `Payloads.TestEventTable`; `payloads.mjs --check` fails ("not in the TYPES parameter").
- mutation: drop the live-store entry -- red `live-store.test.mjs` ("has an entry for every event type"); `ng build` was not re-run for this mutation.
- mutation: publish to `Live.Publish.#INSTANCE` -- red, fresh, `Heartbeat.TestBeatReachesIntake` ("Web.Api.EventsBody serves both heartbeat events"), `TestBeatNowReachesIntake` and `TestAnHourOfTicks`.

Mutation results (this pass; each applied, observed red, reverted byte-identical, `git diff --stat` unchanged by the reverts):
- mutation: `AnnounceBeat` logs the error text without `Redact.Text` (both branches) -- red `Runs.TestBeatPublishFailureIsLogged` ("and none holds the secret").
- mutation: `Tick` publishes the views before the Items loop -- red `Runs.TestBeatPublishFailureIsLogged` ("and publishes only after all three are sent").
- mutation: `Tick` drops the views when RunDue answers an error status -- red `Runs.TestBeatPublishesWhatRunDueCommittedBeforeAnError`. (A first try, skipping `AnnounceBeats` on `$$$ISOK(sc)`, stayed green because the Items loop reassigns `sc`; it was not the mutation.)
- mutation: `BeatNow` does not call `AnnounceBeats` -- red `Runs.TestBeatNowPublishes` and `TestBeatPublishFailureIsLogged` ("and logs one more warning"), fresh.
- mutation: `FromRow` gives an all-day person the default `from` -- red `Payloads.TestHeartbeatFromRow` ("an all-day person's empty from and to are left out of the JSON").
- mutation: `HeartbeatPayload` removed from the traced list in `payloads.test.mjs` -- red "is on exactly the interfaces that have both traceHeaderId and traceNamespace" (the same test was red before the edit, at the implement halt).
- mutation: `GuideRefresh.TestNonTriggerTypes` at 8 instead of 9 -- red on the first fresh `shard lane-b@Live` after the pair joined TYPES ("eight types are neither a trigger nor guide.state").

Mutation results (CI rework, 2026-11-04; lane D, tag `e39s7rww` warm, torn down; applied, observed red, reverted from a backup, the file byte-identical afterwards):
- mutation: `Beat.Run` adds the view for a RunDue skip with reason `empty` again (the `If runNow || (reason '= ..#SKIPEMPTY)` guard removed) -> red `Beat.TestRunDueEmptySkipGivesNoView` ("but only the back-off skip gives a view, and the empty one gives none", "an empty skip of a person with a row gives no view", "the recorded result gives one view") and `Runs.TestTickPublishesTheBeats` ("and publishes no event", "the others, not due, publish nothing more") and `Runs.TestPublishedEventsHoldNoRefChecklistOrKey` (H's event count).
- mutation: `Beat.Run` drops `runNow ||` from the guard (a held run now adds no view) -> red `Beat.TestViewsInCommitOrder` ("it is held, with one view") and `Runs.TestBeatNowPublishes` ("and publishes one event") and `TestPublishedEventsHoldNoRefChecklistOrKey` ("H's held run now (its Tick skip published none) holds no SessionRef"); warm.
- mutation: `Beat.Run` widens the guard to `If runNow` (every RunDue skip adds no view) -> red `Beat.TestRunDueEmptySkipGivesNoView` ("but only the back-off skip gives a view, and the empty one gives none") and `TestViewsInCommitOrder` ("three views: ..."), `Runs.TestTickPublishesTheBeats` ("a skip publishes one event"), `TestTickPublishesEachCommitInOrder` ("two commits publish two events") and `TestPublishedEventsHoldNoRefChecklistOrKey`; warm. `Beat.cls` restored from the backup, `cmp` identical, both classes green again.
- no mutation for the `checks` job's `timeout-minutes` (15 to 20): a config value no test pins; checked by the one-line diff and `docker/tests/test-ci-config.sh` (exit 0).

**Shared surfaces:**
- `Test.Live.GuideRefresh.TestNonTriggerTypes` counts the types that are neither a trigger nor `guide.state` (8 to 9); it is outside the listed Footprint and in no open epic's diff (11, 33, 40), a footprint extension;
- `Live.Publish` TYPES and its count (`Test.Live.Payloads` `EXPECTED`, `TestEventTable`);
- the payload contract classes (`TestContracts` 31, `Test.Contract.Checker`);
- `web/src/app/live/payloads.ts` (`payloads.mjs --check`, `payloads.test.mjs`, unchanged and green);
- the event-type list (`live-store.test.mjs`, COLLECTIONS);
- the signatures of `Beat.RunDue`/`RunNow` and of the `Process` seams (`Test.Checks.Probe` and the direct callers in `Test.Checks.{Beat,Snapshot,Runs}`; the trailing Output keeps the existing calls valid);
- the session stream's event list in `Test.Checks.Heartbeat` and `Runs`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Added test time (inference):** about 2 s in `shards` (the `Heartbeat` additions only read events after the synchronous Ticks) and under 1 s in `image` (lane-b's `Payloads`).

**QA stage (2026-11-04, runner D; lane D, tags `e39s7qa` fresh and `e39s7qaw` warm, both torn down).** Files created or changed (QA):
- `src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls` (QA): new `TestFailedCommitsGiveNoView` (AC 3: a recorded decision that cannot be saved, a refused duplicate row and a RunNow that cannot settle give no view; the person after a failure still gives its views); `BDueBroken` gains a trailing `Output views`.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls` (QA): new `TestPublishedEventsHoldNoRefChecklistOrKey` (AC 2, over a recorded ignore with the unchanged skip, a beat with its recorded fallback, a sent run now, a skip with a held run now; helper `NoLeaks`) and `TestOffPersonsRecordedResultIsPublishedWithTheirSettings` (AC 1, AC 3).
- `src/ocutalon/cls/OcuTalon/Test/Checks/Heartbeat.cls` (QA): `TestBeatReachesIntake` also pins the polled body (the published payloads, `traceUrl` on the recorded outcome, no ref, checklist, Item Id, decision Ref or snapshot key).
- `web/scripts/live-store.test.mjs` (QA): new test `accepts a heartbeat event` (the entry, the cursor, no other collection changes).

Mutation results (QA stage; each applied, observed red, reverted from a backup, `git status --short` and `git diff` identical to before):
- mutation: `Heartbeat.FromRow` fills `LastSkipReason` from `LastItemId` when the row has none (AC 2) -> red `Runs.TestPublishedEventsHoldNoRefChecklistOrKey` and `TestOffPersonsRecordedResultIsPublishedWithTheirSettings` ("does not hold ..."); no earlier test saw it.
- mutation: `Beat.Settle` adds its view without the `$$$ISOK(sc)` guard, so a failed save is viewed (AC 3) -> red `Beat.TestFailedCommitsGiveNoView` only.
- mutation: `Process.AnnounceBeats` publishes only the views of people who are on (AC 1) -> red `Runs.TestOffPersonsRecordedResultIsPublishedWithTheirSettings` only.
- mutation: `Heartbeat.FromRow` fills `LastSkipReason` from `LastDecisionRef` when the row has none (Integration AC, polled body), fresh -> red `Heartbeat.TestBeatReachesIntake` ("no polled event holds <decision Ref>") only.
- mutation: the live-store entry for `heartbeat` names the collection `chat` (Integration AC, store accepts the type) -> red `live-store.test.mjs` "accepts a heartbeat event".

Runs after the changes: warm `Test.Checks.Beat` and `Test.Checks.Runs` passed; fresh `Test.Checks.Heartbeat` passed (13.4 s); fresh `shard lane-a@Checks` passed forward and `--reverse`; `npm --prefix web test` 1331 pass. Added test time: about 0.2 s in `Beat`, 0.4 s in `Runs`, none measurable in `Heartbeat`.

Mutation results (code review, 2026-11-05; lane D, tags `e39s7crw` warm and `e39s7cr` fresh, both torn down; each applied, observed red, reverted from a backup, `git status --short` and `git diff --stat` identical to before):
- mutation: `BeatNow` calls `AnnounceBeats` before the `SendOwn` block -> red `Runs.TestBeatPublishFailureIsLogged` ("and publishes only after its Item is sent").
- mutation: `Live.Payload.Heartbeat.LastOutcome` MAXLEN 32 -> 33 (AC 4, 31 contract classes) -> red `Payloads.TestContracts` ("OcuTalon.Live.Payload.Heartbeat has exactly its contract: LastOutcome has MAXLEN '33', not '32'").
- mutation: drop the `heartbeat` entry from `COLLECTIONS` in `live-store.ts` (AC 4) -> `npm --prefix web run build` exit 1 (TS2741 "Property 'heartbeat' is missing ... Readonly<Record<LiveEventType, CollectionRule>>").

Runs after the review patches: warm `Test.Checks.Runs`, `Test.Live.Payloads` and `Test.Checks.Beat` passed; fresh `Test.Checks.Heartbeat` passed (13.5 s); `npm --prefix web run build` exit 0 and `npm --prefix web test` 1331 pass.

## Auto Run Result

Status: done
Blocking condition: none

Pass: rework iteration 1 of the implement stage (2026-11-04, runner D; baseline `6c00ff1d392f1e7817caa650bb9ab9e11f22ac35`). It covers only the two `[CI]` items.

**Summary.** `Beat.Run` adds no view for a RunDue skip with reason `empty` (the row is still saved); Settle's result, the other skips, beats and every RunNow (a run now held by an empty checklist too) still add one. The `checks` job's `timeout-minutes` is 20.

**Files changed in this pass.**
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls`: the guard in `Run` and the `Run` and class docs.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls`: new `TestRunDueEmptySkipGivesNoView`.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls`: `TestTickPublishesTheBeats` (a back-off skip, plus an empty-checklist person with a saved row and no event) and `TestPublishedEventsHoldNoRefChecklistOrKey` (H gives one event).
- `.github/workflows/ci.yml`: `checks` job `timeout-minutes` 15 to 20.
- This spec: the `[CI]` items ticked, the mutation lines, the triage entry.

**Review.** Patches applied: 2 at medium (the same root cause: two missing mutation lines, both mutations run) and 2 at low (the test header wording, a heading date). Deferred: none. Rejected: 14 low, each with its reason in the Review Triage Log.

**Follow-up review recommended:** false. No high was patched on this follow-up pass.

**Verification performed (lane D; tags `e39s7rw` fresh, `e39s7rww` warm, both torn down).**
- Warm: `Test.Checks.Beat` and `Test.Checks.Runs` passed; three mutations observed red and reverted (`Beat.cls` byte-identical).
- Fresh: `shard lane-a@Checks` forward and `--reverse` (8 classes each) and `shard lane-b@Live` (4 classes) passed. `npm --prefix web test` 1331 pass. `test-ci-config.sh` and `test-boundaries.sh` exit 0.
- Browser: `ci/iris.sh live sign-in` as one unit passed 247 of 254 tests and stopped at the harness's global timeout (about 408 s; 7 not run, none failed). Run as `--part 1/2` (138 passed) and `--part 2/2` (116 passed; it holds `live.spec.ts`, so L10) on fresh stacks, both exit 0.

**Residual risks.** The `checks` timeout is pinned by no test. `GuideRefresh.TestHeldLock` (DW-349) can flake on a fresh `lane-b@Live` shard.
