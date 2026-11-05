---
title: 'Story 39.7: Publish the heartbeat event'
type: 'feature'
created: '2026-11-04'
status: 'in-progress'
baseline_revision: '5bc59f8b26d2e8f573e47984a7319392861e43d1'
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
| Skip | Due person, empty checklist (or outside hours) | One event with `lastSkipAt` T, its reason and the moved `nextDueAt` | none |
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
- AC 1 -- Given a beat, a skip or a recorded result, when its row is committed, then `Checks` publishes one `heartbeat` event to the session's stream with the row's public view: on, the interval, the hours, next due, the last result and the last skip (AD-12, AD-18).
- AC 2 -- Given a row whose `SessionRef`, checklist and keys hold distinct tokens, when its heartbeat event is published, then the payload holds none of them. And when the publish fails, then the warning names no `SessionRef` in any case (AD-12, AD-33).
- AC 3 -- Given a person for whom a Tick or BeatNow commits nothing, when it runs, then no event is published for them.
- AC 4 (DW-633) -- Given the new class and TYPES pair, when the IRIS payload tests and the web checks run, then all of these agree: TYPES, `Test.Live.Payloads` (17 types, 31 contract classes), `payloads.ts` (`--check` clean, `HeartbeatPayload` with `traceUrl?`) and the live store (17 entries). And `npm --prefix web test`, `lint` and `build` pass.
- [ ] [Clarification] Add `'HeartbeatPayload'` to the list of interfaces that carry `traceUrl` in `web/scripts/payloads.test.mjs` (the test "is on exactly the interfaces that have both traceHeaderId and traceNamespace", about line 110), and nothing else in that file; then `npm --prefix web test` is green (AC 4).
- Integration AC -- Given a real Tick that runs a beat, when the page polls, then `Web.Api.EventsBody` (the real `/api/v1/events` body) serves it as `{type: "heartbeat", stream: "session", payload}`. The generated `HeartbeatPayload` types it, and the live store accepts the type.

## Spec Change Log

- 2026-11-05, lead, answering the implement stage's intent gap (decide, round 1): `web/scripts/payloads.test.mjs` hardcodes the interfaces that carry `traceUrl`, and `HeartbeatPayload` has both trace fields, so AC 4 needs one name added there. The file is Lane B like this story, in no open epic's diff (11, 33, 40), and the change is a one-name append to a list (standing precedent), so it is allowed and reported as a footprint extension. The Never line is amended and one open task added; the earlier pass's implementation stays in the working tree, uncommitted, for this pass to finish.

## Review Triage Log

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

**Shared surfaces:**
- `Live.Publish` TYPES and its count (`Test.Live.Payloads` `EXPECTED`, `TestEventTable`);
- the payload contract classes (`TestContracts` 31, `Test.Contract.Checker`);
- `web/src/app/live/payloads.ts` (`payloads.mjs --check`, `payloads.test.mjs`, unchanged and green);
- the event-type list (`live-store.test.mjs`, COLLECTIONS);
- the signatures of `Beat.RunDue`/`RunNow` and of the `Process` seams (`Test.Checks.Probe` and the direct callers in `Test.Checks.{Beat,Snapshot,Runs}`; the trailing Output keeps the existing calls valid);
- the session stream's event list in `Test.Checks.Heartbeat` and `Runs`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Added test time (inference):** about 2 s in `shards` (the `Heartbeat` additions only read events after the synchronous Ticks) and under 1 s in `image` (lane-b's `Payloads`).

## Auto Run Result

Status: blocked
Blocking condition: intent gap: AC 4 requires `npm --prefix web test` to pass, and the spec says `web/scripts/payloads.test.mjs` stays green unchanged and must not be edited. It does not: its test "is on exactly the interfaces that have both traceHeaderId and traceNamespace" (line 110) hardcodes the traced interface list, and `HeartbeatPayload` (traceHeaderId and traceNamespace, as the spec requires) now gets `traceUrl`. Recommended amendment: rule `web/scripts/payloads.test.mjs` into this story's allowed files for one added `'HeartbeatPayload'` in that list (no open epic touches the file), then re-dispatch; the rest of the web suite, lint, build and `payloads.mjs --check` pass.

Implement stage (2026-11-04, runner D, baseline `5bc59f8b26d2e8f573e47984a7319392861e43d1`). The handoff subagent implemented the whole Footprint and ran the loop checks (Payloads, Beat, Runs, Contract.Checker, Bridge.CodeRules, Live.Publish warm; Heartbeat fresh: passed) and all eight pinning mutations. The work is uncommitted in the tree for the lead to set aside or pick up. Not yet run: review layers, the `(once)` shard/CI-config/boundary commands, the finalize commit. Nothing was committed or pushed; no stack of this stage is left running.
