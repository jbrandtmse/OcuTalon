---
title: 'Story 39.3: Beats fall due on the tick, and skip without a model call when they should'
type: 'feature'
created: '2026-11-03'
status: 'done'
baseline_revision: '15ff20a5fcb66869d25004974df63ba36088861b'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 39.1 left `OcuTalon.Checks.Beat` as stubs, so nobody's heartbeat ever runs. The owner's hard rule is that the tick never calls the model and a person's beat calls it at most once per interval, and only when something may need a decision.

**Approach:** Fill `Beat.RunDue`/`RunNow` with AD-18's rules. They read each person's values through `Data.Setting.Get`, apply the six skip rules in order with no model request, record the skip or the beat on the person's `HeartbeatBeat` row, and return the beat's `Msg.Item`. `Checks.Process` sends that Item to `Intake` through Story 30.4's send seam, in a trace session of its own. On a later tick it records the beat's `Decision`. Until Story 39.4 the snapshot is the checklist alone, and `Key` is its SHA-256. The `heartbeat` live event is planned separately (the Event group, blocked on DW-633).

## Boundaries & Constraints

**Always:**
- Lane A files only (U-177): `Checks/Process.cls`, `Checks/Beat.cls` and tests under `Test/Checks/**`. Lane B classes are only called: `Data.Setting.Get` (and its generated `KeyIndexExists`), `Data.Ownership.DecisionOfItem`, `Msg.Item`, `Msg.CommandResult` and `Data.Session` (read by SQL).
- The tick never calls the model. Every model request comes from `Intake`, after `Checks` has sent it a beat Item.
- Nothing that decides "due" lives in memory (AD-5). A due beat is one with no row, an empty `NextDueAt`, or `NextDueAt` at most `Process.DUESLACKSECONDS` after the tick. A run beat's next due time is the tick time plus one interval, so a beat missed across several intervals runs once.
- The values are read on every tick: `Setting.Get(Beat.SettingKey(ref, name))`. A key with no row takes its default: `on` is `DEFAULTON`, or `DEFAULTONDEMO` when `Watch.Reader.OnlineDemo()`; the other defaults are `DEFAULTINTERVAL`, `DEFAULTFROM`, `DEFAULTTO` and "". A stored interval outside `INTERVALS` reads as 30, so nothing under 30 minutes can run. `from` and `to` both stored as "" mean all day. Any other pair that is not two `HH:MM` values reads as the defaults.
- The skip order is empty checklist, outside hours, back-off, cap, no key, unchanged. "Empty" is empty after white space is stripped. Hours are read in the instance zone through `Data.Time` only. The cap is `Bridge.Budget.State(at).capped`, and the key is `Bridge.Keys.Status("TriageAgent")`; each is read once per tick, not per person. The snapshot is built only when none of the first five rules holds. An empty `LastQuietKey` never matches.
- A skip writes `LastSkipAt` (the tick) and `LastSkipReason` (a code from `Beat`'s parameters). `NextDueAt` becomes the next active-hours start for `hours`, and the tick plus one interval for every other reason.
- A beat that runs writes `LastBeatAt`, `LastItemId` and `LastSnapshotKey`, sets `NextDueAt` to the tick plus one interval, and clears the five decision fields, so that a pending beat is `LastItemId` set and `LastDecisionRef` empty. The row is saved before `Checks` sends the Item.
- No log line or status text names a `SessionRef`. A per-person failure gives only its count and its error codes.
- No `BackgroundCheck` row, check result or coverage entry exists for a beat (AD-28).
- Fixed clocks in every time-dependent test. Every test added or changed passes on a fresh environment, in either order.

**Never:**
- No edit to `Production.cls`, `docker/tests/test-production.sh`, `Live/**`, `Test/Live/**`, `web/**`, `Core/**`, `Data/Setting.cls`, `Data/Ownership.cls`, `Msg/Enum.cls`, `ci/mock/test/constants.test.mjs`, `docker/**`, `Install/**`, `src/module.xml` or `src/cpf/**`. No change to `Data/HeartbeatBeat.cls` (storage stays as 39.1 committed it).
- No new production item, scheduler, task or timer. No new mock scenario: `decide-ignore` serves.
- No public text beyond the epics' own Subject "Heartbeat check-in". `CommandResult.Message` stays empty.
- No unit test on slot D.

## I/O & Edge-Case Matrix

Clocks are fixed UTC stamps in 2099 (local times built with `Data.Time.FromLocal`), so no real tick can reach a test row. Rows are created before keys are written.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Not due | row `NextDueAt` = T+10 min; tick T | row unchanged, no Item | none |
| No row, empty checklist | on 1, no checklist key | a row is made: `empty` at T, `NextDueAt` T+30 min | none |
| Off | `on` = "0", due row | nothing written, no Item | none |
| Each skip reason, in order | due row; each rule made to hold alone, then two at once | the first reason in AD-18's order (`empty`, `hours`, `backoff`, `cap`, `nokey`, `unchanged`); `NextDueAt` T + interval (`hours`: next start) | none |
| Window over midnight | from 22:00, to 06:00 | local 23:00 and 05:00 are inside; 12:00 is outside, next due at today's 22:00 local | none |
| Normal window | 08:00 to 20:00 | local 21:00 is outside, next due at tomorrow's 08:00; local 07:00 gives today's 08:00 | none |
| Beat runs | due, checklist C, `LastQuietKey` of another text | one Item: new `ItemId`, `untrusted`, `heartbeat`, the person's ref, Subject "Heartbeat check-in", Text C; row `LastBeatAt` T, `LastItemId`, `LastSnapshotKey` = `Key(C)`, `NextDueAt` T + interval, decision fields empty | none |
| Restart catch-up | `NextDueAt` = T-3 h; ticks T, T+1 min | one Item at T, none at T+1 min; `NextDueAt` T+30 min | none |
| Decision recorded | pending row; `Decision` (decide, same `ItemId`, owner the ref, ignore, cost 0.0004) | next tick: `LastOutcome` ignore, `LastFallback` 0, `LastCostUSD`, `LastDecisionRef`, `LastTraceSessionId`; `LastQuietKey` = `LastSnapshotKey` | none |
| No decision yet | pending row, no `Decision` | row stays pending | none |
| Fallback | decision fallback 1; interval 30, then 1440 | `BackoffUntil` = tick + 4 h, then tick + 24 h | none |
| Unchanged after Ignore | `LastQuietKey` = `Key(C)`, checklist C, due | skip `unchanged`, no Item | none |
| Run now | outside hours, `LastQuietKey` = `Key(C)` | Item sent, `LastRunNowAt` = now, `NextDueAt` now + interval, outcome `sent` | none |
| Run now, held | empty / back-off / capped / no key | outcome is the reason, no Item, `LastRunNowAt` set, `NextDueAt` unchanged; back-off gives `availableAt` = `BackoffUntil` | none |
| Run now, cooldown | `LastRunNowAt` = now-119 s | outcome `cooldown`, `availableAt` = `LastRunNowAt`+120 s, nothing written, no Item; at now-120 s it runs | none |
| One person fails | two due people; B's stored row node has a 65-character `LastQuietKey`, written straight into its global by the test, so that B's save fails validation | A still beats; RunDue gives an error status holding the count 1 and the error code, never B's ref | caught per person |
| Send fails (probe) | `FailFindings` on the beat text | `LOGBEATSEND` names the ItemId, not the ref; Tick OK | logged |
| Integration (production) | fresh throwaway; checklist holds `[[mock:decide-ignore:<key>]]` | `Intake` gets the beat Item in its own trace session (SuperSession = the TraceRef) and records a `Decision` for it; the CI mock's log holds exactly one request with the marker; the next tick records ignore on the row | assertion failure |
| An hour of ticks (production) | 30-min interval; row `NextDueAt` T0, `LastQuietKey` = Key(an earlier checklist); ticks T0 to T0+59 min | T0 changed: exactly 1 request; T0+1 to +29: 0; T0+30 unchanged since the Ignore: 0, skip `unchanged`; the hour holds 1 (at most 2) | assertion failure |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- these are the places to change:
  - the class doc, lines 1-56 (Tick's last step, the BeatNow answer);
  - `OnRequest` at 157 (BeatNow at 163);
  - the `Tick` beat block, 196-203;
  - `BeatNow`, 208-219;
  - the seams `BeatRunDue`/`BeatRunNow`, 222-231;
  - `Record`'s send loop, 429-445 (the trace-session sequence to extract);
  - `TraceOf`, 316;
  - `SendFinding`, 592 (Story 30.4's seam to reuse);
  - `FindingItem`, 499 (the Item-building sibling);
  - `DUESLACKSECONDS`, 64;
  - the `LOG*` parameters, 121-143.
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls` -- 39.1's stubs (lines 27-49) and parameters plus `SettingKey`. Fill this class.
- `src/ocutalon/cls/OcuTalon/Data/HeartbeatBeat.cls` -- the 15 fields and `SessionRefIndexOpen`. Read-only.
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls` -- `Get(key, default)`, line 39 (60 s per-process cache; "" for both an absent key and an empty value, so presence is `KeyIndexExists`). Lane B; call only.
- `src/ocutalon/cls/OcuTalon/Data/Time.cls` -- `Seconds` 27, `AddSeconds` 42, `ToLocal` 54, `FromLocal` 68 (the only zone converter).
- `src/bridge/cls/OcuTalon/Bridge/Budget.cls` (`State(now)`, line 41) and `Keys.cls` (`Status(agent)`, line 32; item `TriageAgent`).
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls` -- `OnlineDemo()`, line 135.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- `DecisionOfItem(itemId, ownerRef, .sc)`, line 339. Epic 31-contended; call only.
- `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls` -- `Outcome`, `Fallback`, `CostUSD`, `Ref`, `TraceSessionId`.
- `src/ocutalon/cls/OcuTalon/Msg/CommandResult.cls` -- `Ok`, `Outcome`, `Ref`, `Data`. `Msg/Item.cls` -- the Item fields.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Probe.cls` -- these are the places to change:
  - the overrides `BeatRunDue` 153 and `BeatRunNow` 163;
  - `SendFinding` 137 (it keeps channel, provenance, text, subject, sessionId and superSession);
  - `FailFindings` 221;
  - the doc, lines 24-26.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls` -- these are the places to change:
  - the beat tests, 900-1082, of which `TestBeatNow` (948) asserts the old empty response;
  - the helpers `Host` 1095, `Owner` 1104, `Tick` 1205, `Beaten` 1255, `Warnings` 1317 and `RemoveLogs` 1349.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls` -- `TestStubsDoNothing` (17-28) becomes obsolete. `Open` and `Rows` are the helpers.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Heartbeat.cls` -- these are the places to change:
  - `TestBeatNowIsAnswered`, 356 (asserts "no response object");
  - the helpers `Findings` 283 and `Decision` 321.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls` -- `HEARTBEAT`/`CHECKS`/`TICKWAIT` (137-142), `WAITDIAGNOSIS`, and `OnAfterOneTest` 241 (the `ItemIds` cleanup deletes Decision/Usage rows).
- `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls` -- `LogMark()` 471 and `LogSince(mark, .entries)` 484: pick the entries whose marker is the test's own.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` -- `Session(user)` 22 and `Decision(owner, kind, recordedAt, fields)` 141.
- `ci/mock/scenarios/A/decide-ignore.json` -- an unarmed `[[mock:decide-ignore:<key>]]` answers ignore to every request that carries it.

## Tasks & Acceptance

**Execution:**
- Task 0 (measure; unmeasured so far, inference): the two production tests below start with precondition assertions, `Keys.Status("TriageAgent")` = 1 and `Budget.State().capped` false, each with a message that names it as a precondition. Record the values of their first fresh run in `## Verification`. If either fails on the throwaway, stop with `## Clarification Needed` (TOOLING:) and do not weaken the tests.
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls` -- fill the stubs. Add these parameters:
  - `CHANNEL = "heartbeat"`, `SUBJECT = "Heartbeat check-in"` and `AGENT = "TriageAgent"`;
  - `RUNNOWSECONDS = 120` and `BACKOFFSECONDS = 14400`;
  - the outcome codes `SKIPEMPTY` "empty", `SKIPHOURS` "hours", `SKIPBACKOFF` "backoff", `SKIPCAP` "cap", `SKIPNOKEY` "nokey", `SKIPUNCHANGED` "unchanged", `SENT` "sent", `COOLDOWN` "cooldown" and `FAILED` "failed";
  - `STATUSPREFIX = "Status at "` and `STATUSSUFFIX = "(built by OcuTalon):"`.

  Add these public class methods, all pure except where noted:
  - `Values(sessionRef)`: a `%DynamicObject` of `on`, `interval`, `from`, `to` and `checklist`, per Always.
  - `InHours(values, at)`: all day, or from<=local<to, or over midnight when from>to. from=to counts as all day.
  - `NextDue(values, at, reason)`.
  - `Skip(values, row, at, runNow, capped, keyed, key)`: the first reason, or "". `row` may be "". `key` "" leaves rule 6 out. `runNow` drops `hours` and `unchanged`.
  - `Capped(at)` and `Keyed()`.
  - `Snapshot(sessionRef, now)`: `Values(...).checklist` until 39.4.
  - `Key(snapshot)`: the lower-case hex SHA-256 of the UTF-8 snapshot with its line that starts `STATUSPREFIX` and ends `STATUSSUFFIX` removed (64 characters).
  - `RunDue(tickAt, Output items As %ListOfObjects, sessions As %String = "", capped = "", keyed = "") As %Status`:
    - first it records the pending decision of each row in scope (`DecisionOfItem` by `LastItemId` and the row's ref). On ignore it copies `LastSnapshotKey` to `LastQuietKey`. On a fallback it sets `BackoffUntil` to the tick plus max(`BACKOFFSECONDS`, interval);
    - then it takes the due people, from `OcuTalon_Data.Session` (every row, or the comma-separated `sessions`) whose `on` is 1;
    - "" for `capped` or `keyed` means read `Capped(tickAt)` and `Keyed()`;
    - each person runs in its own Try/Catch.
  - `RunNow(sessionRef, now, Output item, Output outcome, Output availableAt, capped = "", keyed = "") As %Status`: it records the session's pending decision first, then the cooldown check (nothing written), then `LastRunNowAt` = now. It ignores `on`. On a run it sets `NextDueAt` to now + interval.

  Each run builds its Item as `FindingItem` does. Update the class doc. -- AC 1-4, AD-5, AD-18, AD-19, AD-20, AD-28.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- make these changes:
  - Extract `SendOwn(item) As %Status [ Private ]` from `Record`'s loop body. It saves `%SessionId` and `%SuperSession`, clears `%SessionId`, sets `%SuperSession` to `TraceOf(item.SessionRef)`, calls `SendFinding(item)` in a Try, restores both and returns the status. `Record` uses it, with its behaviour unchanged.
  - `BeatRunDue(tickAt, Output items)` calls `Beat.RunDue(tickAt, .items)`.
  - `Tick`'s beat block sends every Item that `items` holds through `SendOwn`, also when `sc` is an error. A failed send logs `LOGBEATSEND = "Checks could not send a heartbeat beat, item "` plus the ItemId.
  - `OnRequest` calls `..BeatNow(request, .response)`.
  - `BeatNow`: now is `RequestedAt` when it is a UTC stamp (Tick's rule), else `NowUtc()`. It calls the seam `BeatRunNow(ref, now, .item, .outcome, .availableAt)` and sends a returned item through `SendOwn`. An error, an exception or a failed send logs `LOGBEATNOW`/`LOGBEATSEND`, and the outcome becomes `failed`. It answers OK with a `Msg.CommandResult`:
    - `Ok` = (outcome = `sent`);
    - `Outcome`;
    - `Ref` = the ItemId when sent;
    - `Data` = `{"availableAt": ...}` when availableAt is set, else "";
    - `Message` "".
  - Update the class doc. -- AC 2, 4, AD-18, AD-26, AD-30.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Probe.cls` -- match the new seam signatures. Add the properties:
  - `BeatSessions`, `BeatCapped` (default 0) and `BeatKeyed` (default 1): while `BeatSessions` is set, `BeatRunDue`/`BeatRunNow` record as now and then call the real `Beat.RunDue(tickAt, .items, ..BeatSessions, ..BeatCapped, ..BeatKeyed)` / `RunNow`;
  - `BeatNowOutcome` (the outcome that a record-only `BeatRunNow` gives).

  `BeatNows` also records `now`. Update the doc.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls` -- replace `TestStubsDoNothing` (and remove the stub wording from the class doc) with these tests:
  - `TestValues`: defaults, the demo `on`, an interval under 30, an all-day pair, a bad pair;
  - `TestActiveHours`: both windows, from=to;
  - `TestNextDue`;
  - `TestSkipOrder`: each reason alone and in pairs, run-now;
  - `TestKey`: 64 hex characters, stable, deaf to the status line, changed by the checklist;
  - `TestDueSelection`: not due, no row, off, restart;
  - `TestBeatRow`;
  - `TestDecisionIsRecorded`: ignore, pending, fallback 30 and 1440;
  - `TestUnchangedAfterIgnore`;
  - `TestRunNow`: hours and unchanged do not hold it, the held reasons, cooldown at 119 and 120 s;
  - `TestOneFailureLeavesTheOthers`;
  - `TestInputsAreRead`: `Capped` follows `^OcuTalonBP.UsageCapped(<a 2099 test-only day>)`, set and killed by the test; `Keyed()` = `Keys.Status("TriageAgent")`; `RunDue` with `capped` "" skips `cap` on that day.

  Seed keys with `Setting.Set` after the row exists. Delete the test's Setting and `HeartbeatBeat` rows, and its fixture decisions, after each test. Each test calls `RunDue` with explicit `sessions`, never without. -- AC 1-4 (matrix rows 1-16).
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls` -- add three tests:
  - `TestTickSendsTheBeats`: a probe with `BeatSessions`; the Item is in `FindingItems` with channel `heartbeat`, `sessionId` "", `superSession` = TraceOf; it comes after the due row's read;
  - `TestBeatSendFailureIsLogged`: `LOGBEATSEND` with no ref;
  - `TestBeatNowRunsOnce`: a CommandResult `sent` with Ref = the ItemId, then `cooldown` with `Data.availableAt` and no second Item.

  Update `TestBeatNow`, `TestBeatLogsAreRedacted` and `TestBeatNowKeepsEachSession` for the CommandResult answer and the new signatures. `RemoveLogs` also removes the test's `LOGBEATSEND` lines.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Heartbeat.cls` -- add two tests (fresh, production):
  - `TestBeatReachesIntake` (Integration AC):
    - the person's row is made with `NextDueAt` T0 (now + 2 days, on the minute) before keys `on` 1, `interval` 30, `from`/`to` "" and checklist `"zz beat [[mock:decide-ignore:"_NewRef()_"]]"`;
    - `LogMark`, then a Tick at T0;
    - the existing `Findings` helper (extend it with Subject and Text) finds one `Checks`->`Intake` Item for the ref (channel `heartbeat`, provenance `untrusted`, Subject, Text) whose SuperSession is the TraceRef, in a session other than the Tick's;
    - wait up to `WAITDIAGNOSIS` for `DecisionOfItem`; `LogSince` holds exactly one request with the marker;
    - a Tick at T0+1 min records `LastOutcome` ignore, `LastDecisionRef` = the Decision's `Ref`, `LastCostUSD` and `LastTraceSessionId`.
  - `TestAnHourOfTicks` (the mock-log AC):
    - the row is seeded with `LastQuietKey` = `Key("zz an earlier checklist")`;
    - the Tick at T0 gives 1 request, and the test waits for its Decision;
    - after a new mark, the Ticks T0+1 to T0+59 min give 0 requests, and the row holds `unchanged` at T0+30 and `NextDueAt` T0+60;
    - the hour's total is 1 (at most 2).

  Add each ItemId to `ItemIds`. Override `OnAfterOneTest` to delete the test's `person.<ref>.heartbeat.*` and `HeartbeatBeat` rows, then call `##super`. Update `TestBeatNowIsAnswered`: the answer is a CommandResult with Outcome `empty`, and the Intake assertions stay. Update the class doc. -- AC 2, 5.

**Event (split to Story 39.7 by the lead's spec-gate ruling; NOT implemented in this story):** kept for reference only; the implement stage skips this group entirely.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Heartbeat.cls` (new, Lane A) -- `%RegisteredObject`, `%JSON.Adaptor`: `On`, `Interval`, `From`, `To`, `NextDueAt`, `LastBeatAt`, `LastOutcome`, `LastFallback`, `LastCostUSD`, `LastTraceSessionId`, `LastSkipAt`, `LastSkipReason`, `BackoffUntil`, `LastRunNowAt`; `FromRow(row, values)`. No `SessionRef`, checklist or key.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- after each committed skip, beat or recorded decision, `Live.Publish.Publish(ref, "heartbeat", payload)` (RunDue returns the touched refs). A failure logs `LOGPUBLISH`.
- Tests: `Test/Checks/Heartbeat` -- one `heartbeat` event per committed row change on the session stream (`Test.Core.Observe.Events`), without the ref, the checklist or a key.

**Acceptance Criteria:**
- AC 1. Given people whose heartbeat is on, when `Checks` handles a Tick, then `Beat.RunDue(tickAt)` takes only the people with no row or a passed `NextDueAt`, and the tick itself makes no model request (FR-64, NFR-28, AD-18).
- AC 2. Given a due beat, when any skip rule holds, then it makes no model request, records `LastSkipAt` and `LastSkipReason`, and moves `NextDueAt` on (next active-hours start when outside hours, else one interval), checking the rules in AD-18's order. A beat that does not skip sends `Intake` one Item asynchronously in a new trace session whose SuperSession is the TraceRef. Its row records `LastBeatAt`, `LastItemId` and `LastSnapshotKey`, with `NextDueAt` one interval later, and a beat missed across several intervals runs once (FR-64, AD-5, AD-14, AD-18, AD-20, AD-26, AD-30).
- AC 3. Given a beat sent on an earlier tick, when its `Decision` (Kind `decide`, same `ItemId`) exists, then the row records the outcome, fallback, cost, decision ref and trace session. Ignore copies `LastSnapshotKey` to `LastQuietKey`, and a fallback sets `BackoffUntil` to max(4 h, one interval) later (FR-4, AD-8).
- AC 4. Given a `BeatNow`, when `Checks` handles it, then one beat runs at once: active hours and an unchanged snapshot do not hold it, while the empty, back-off, cap and key rules do. A request within 2 minutes of `LastRunNowAt` answers outcome `cooldown` with `availableAt` and sends nothing (FR-66, AD-18).
- AC 5. Given the CI mock's request log, when `OcuTalon.Test.Checks` drives an hour of ticks with fixed clocks for a person on a 30-minute interval, then a non-due tick makes no request, a due beat unchanged since the last Ignore makes none, a changed one makes exactly one, and the hour holds at most two (FR-64, NFR-28). Integration: consumer `Intake` receives the beat's Item and records a `Decision` for it, and the mock's log shows that one request.
- AC 6 (moved to Story 39.7 by the spec-gate split; not part of this story). Given any beat, skip or recorded result, when its row is committed, then `Checks` publishes `heartbeat` to the session's stream with the row's public view (on, interval, hours, next due, last result, last skip), never the `SessionRef`, the checklist or a key (AD-12, AD-33).
- AC 7. Given the story's diff, when it is compared with the merge base of `origin/feature/OCT_OcuTalon_MVP`, then the paths under Never are unchanged and `test-production.sh`'s item list is the same.

## Spec Change Log

- 2026-11-04, lead at the re-check on the merged tree: the (once) guard under `## Verification` diffed from the merge-base with feature, which counts 39.1's `Data/HeartbeatBeat.cls` and the orchestrator's ruled test edit (`docker/tests/test-release-notes.sh`); neither is this story's. It now diffs from b50f3add, the pushed head this story starts from. Line anchors, `Data.Ownership.DecisionOfItem`, `Data.Session` and `Test.Data.Fixture` checked against the merged tree: no spec change needed.

- 2026-11-04, orchestrator ruling (decide): Story 39.7 re-homed to Lane B in `epics.md`; its line read "Home lane: A." and now reads "Home lane: B.". DW-633 stays with 39.7. This story is unaffected: its Event group stays out of scope.

- 2026-11-03, lead at spec validation (unattended ruling, decide; Rule 5 split into a sibling in the same epic): AC 6 (the `heartbeat` event) and the Event group are split into the new Story 39.7 "Publish the heartbeat event" (epics.md); DW-633 is re-owned to 39-7-publish-the-heartbeat-event. This story implements AC 1-5 and AC 7 only.

## Review Triage Log

### 2026-11-04 - Review pass
- verdicts: 16 rows (findings of the four layers grouped by root cause) - medium 5, low 11; patched 8, rejected 8 (rows below)
- findings:
  - `[medium]` `[patch]` Key: a leading empty line (or empty lines before a removed status line) dropped the newline, so "\nabc" and "abc" shared a key (edge-case) - fixed with a `kept` flag; TestKey asserts it.
  - `[medium]` `[patch]` Hours and next-start were read through ToLocal but every test ran in UTC, so reading the UTC clock stayed green (verification-gap) - TestActiveHours and TestNextDue now run in America/New_York; the process zone is restored after each test.
  - `[medium]` `[patch]` Tick sends the Items of a RunDue that answered an error status, and BeatNow answers failed after a failed send: neither was pinned (verification-gap) - TestTickSendsTheItemsOfAFailedRunDue and TestBeatNowSendFailureAnswersFailed added; Probe answers BeatError after the real RunDue while BeatSessions is set.
  - `[medium]` `[patch]` RunNow's own Capped/Keyed reads were never exercised (verification-gap) - TestInputsAreRead calls RunNow with both left to be read on a capped day and expects `cap`.
  - `[medium]` `[patch]` LOGBEATNOW could name the SessionRef through a raw save error (edge-case) - Process.WithoutRef takes it out; TestBeatLogsAreRedacted asserts it.
  - `[low]` `[patch]` Key was only pinned for ASCII (verification-gap) - two non-ASCII SHA-256 vectors added to TestKey.
  - `[low]` `[patch]` TestValues and TestKey made a session with a checklist and no row, which a real Tick would treat as due (verification-gap) - both now make the row first with a far NextDueAt.
  - `[low]` `[patch]` Heartbeat header said "Outcome is empty" for the code "empty" (blind) - reworded.
  - `[low]` `[reject]` Quiet key not cleared by a non-ignore decision, then reverting the checklist (blind) - AC 3 says only Ignore copies the key; spec-bound.
  - `[low]` `[reject]` A failed send leaves the beat pending, with no retry or age limit (blind, edge-case) - AC 2 saves the row before the send and defines pending as LastItemId set with LastDecisionRef empty; the next beat clears it; one cheap read per tick.
  - `[low]` `[reject]` RequestedAt trusted as the clock, an unreal stamp gives an empty NextDueAt (blind, edge-case) - "Tick's rule" is the spec's; the stamp is set by the platform, not by a visitor; no reachable failure shown.
  - `[low]` `[reject]` RunDue ends silently on a mid-iteration row read error, aborts on the first query's SQL error, and the lazy cap/key read can fail for every person (blind, edge-case) - systemic failures, reported as an error status or per person; theoretical.
  - `[low]` `[reject]` RunNow makes a row for an unknown SessionRef (blind, edge-case) - the caller is the authenticated session's command; theoretical.
  - `[low]` `[reject]` Snapshot re-reads Values, and interval 30 is a literal (blind) - Setting.Get is cached for 60 s; the spec says "reads as 30" and fixes the Snapshot signature.
  - `[low]` `[reject]` Untested CRLF, FromLocal-empty and ToLocal-empty fallbacks, whitespace code points 11/12/13/160, cost copy weak in TestBeatReachesIntake, no mutation line for sub-clauses (blind, verification-gap) - one mutation per AC is the rule; the cost copy is pinned in TestDecisionIsRecorded; the rest is cosmetic.
  - `[low]` `[reject]` TestOneFailureLeavesTheOthers depends on the storage layout and error code 5808 (blind, verification-gap, intent) - the global is the one TestHeartbeatBeatRowAndUniqueness already pins; the matrix mechanism cannot fail a save (see Design Notes, Decided in-stage).
  - `[low]` `[reject]` Intent-alignment readings (Beat-level versus Process-level tests, run-now settling a pending decision, `Ready()` early exit in the Heartbeat tests) - descriptive; the production tests ran on fresh throwaways and passed, and the `Ready()` pattern is the class's existing one.

## Design Notes

**Governing ADs:**
- AD-18: the agent heartbeat (the whole amendment).
- AD-19: per-person keys and defaults; `Setting.Get`.
- AD-20: `Budget.State`, `Keys.Status`.
- AD-5: nothing "due" in memory; storage unchanged.
- AD-14 and AD-30: the Item, `Intake`, the `Decision`.
- AD-26: the beat's own trace session.
- AD-8: a fallback still notifies, through `Intake`.
- AD-28: a beat is no check.
- AD-12 and AD-33: the event (Event group).
- AD-29 and U-177: lanes.
- No AD Rule changes.

**Decided in-stage:**
- The candidates are every `Session` row whose `on` is 1. On a local install `on` defaults to 1, so a person with no checklist gets `empty` skips. That is what the UX's "Skipped at {time}: your checklist is empty." shows. On the online demo `on` defaults to 0.
- `Beat` cannot send: it has no business host. So `RunDue`/`RunNow` return the Items and `Checks` sends them, which refines 39.1's stub signatures as its notes allowed. The optional `sessions`/`capped`/`keyed` arguments let tests steer the probe and the direct calls without a product test hook.
- `BeatNow` now answers a `Msg.CommandResult`, which changes 39.1's "no response object". This gives Story 39.2's 409 its `cooldown` and `availableAt`, and its reason. The outcome codes are internal; no message text is added.
- Run now ignores `on`, because it is an explicit request (AD-18 lists only hours and unchanged as not holding it). A request that passes the cooldown sets `LastRunNowAt` even when a rule then holds it. A sent run-now moves `NextDueAt`, so a scheduled beat cannot follow a minute later.
- `from` = `to` reads as all day. A stored pair that is invalid reads as the defaults (39.2's validation never writes one).
- `Key` removes only the line that 39.4 will add ("Status at ... (built by OcuTalon):"). In 39.3 the snapshot is the checklist, so `Key` is fully real now, and 39.4 adds lines without changing `Key`.
- Every model request is pinned on a fresh production with the `decide-ignore` marker. The "changed" beat is the first beat after a seeded earlier quiet key. That avoids the 60-second setting cache of the Checks job, which a mid-test checklist edit would hit.
- The matrix row "One person fails" cannot be built as written: `%Save` validates only the properties modified since the open, and a beat never modifies `LastQuietKey`, so a 65-character stored value does not fail B's save (measured on slot D). `Beat.TestOneFailureLeavesTheOthers` makes B fail by replacing B's row node with a non-list string while `RunDue` runs (put back at once), so B's row cannot be opened and the new row is refused by the unique SessionRef index (error 5808). The row's expectation (A still beats, the status holds the count and the code, never a ref) is unchanged.
- Review pass: `Beat.Key` joins kept lines with a flag, so a leading empty line is part of the key; `Process.BeatNow` takes the SessionRef out of the text of a `LOGBEATNOW` line (a `%Save` error may name it). The `Beat` tests read hours in America/New_York (January, so no daylight-saving change), and the `Probe` answers `BeatError` after the real `RunDue` while `BeatSessions` is set.
- `Channel` `heartbeat` goes out before `Msg.Enum` CHANNEL holds it (39.2's append, Lane B, waits on Epic 40). Nothing at run time validates an Item's channel; checked in `Intake`, `Agent.Input` and `Decide`.

**Extend, don't copy (Rule 2):**
- the send reuses Story 30.4's `SendFinding` seam and the `INTAKE` parameter. `SendOwn` is extracted from `Record`, not copied;
- the Item mirrors `FindingItem`;
- the decision read reuses `Ownership.DecisionOfItem`;
- the times use `Data.Time` (`AddSeconds`, `FromLocal`, `ToLocal`);
- the demo flag uses `Watch.Reader.OnlineDemo`;
- the due slack uses `Process.DUESLACKSECONDS`;
- the probe and helpers extend `Test.Checks.Probe`, `Runs`, `Heartbeat`, `Case`, `Test.Contract.Mock.LogMark`/`LogSince` and `Test.Data.Fixture.Decision`.

**Integration ACs:** `Intake` (a real instance) receives the beat Item and records its `Decision`, and the CI mock's request log shows one request (matrix rows 18-19).

**Consumed-by:**
- 39.2: `Beat.Values` for the GET defaults, and the BeatNow `CommandResult` for 202/409.
- 39.4: `Snapshot`/`Key` and the Triage outcomes.
- 39.5: the row's view.
- 39.6: end to end.

**Consumes:**
- Story 30.4's send seam;
- `Intake`/`Decide` (Epics 2, 8);
- `Data.Setting` (AD-19);
- `Bridge.Budget`/`Keys` (AD-20);
- `Ownership.DecisionOfItem`.

**Ledger inbox:** DW-633 is addressed in the Event group. Recommendation: split AC 6 into a sibling story planned next in Epic 39 (Lane A, a new story 39.7 "Publish the heartbeat event"). It lands once Epic 31 merges, or with a Lane B append that the orchestrator arranges. DW-633 is then re-owned to that story. The event needs these edits:
- Lane A: `Live/Payload/Heartbeat.cls` (new), the publish in `Checks/Process.cls`, and the event test in `Test/Checks/Heartbeat.cls`.
- Lane B (Epic 31-contended): the `heartbeat:Heartbeat` pair appended to `Live/Publish.cls` TYPES; `Test/Live/Payloads.cls` (`EXPECTED`, 16 to 17 types, 30 to 31 classes); `web/src/app/live/payloads.ts`, regenerated by `web/scripts/payloads.mjs`.
- Lead: the spine's Built-in cell for `Live.Payload.Heartbeat`, which names Story 39.1.

**Footprint:** all paths are in Epic 39's paths_hint. No contended file is edited; `Data/Ownership.cls`, `Data/Setting.cls` and `Data/Session.cls` are only called or read.

## Verification

`<lane>` is `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=39 stage=implement'`. Each command is a foreground call with `timeout: 600000`, one test class per call, never two at once. Slot D (`server: ocutalon-slot-d`, `namespace: OCUTALON`, port 52793) is only for `iris_doc_load` and compiling. Tear down only your own tags, also after a failure.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e39s3implw ci/warm.sh up`, once -- expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e39s3implw ci/iris.sh class OcuTalon.Test.Checks.Beat` -- expected: `CLASS ... passed`.
- (loop) the same for `OcuTalon.Test.Checks.Runs` -- expected: passed.
- (loop) `<lane> OCUTALON_RUN_TAG=e39s3impl ci/iris.sh class OcuTalon.Test.Checks.Heartbeat`, fresh (production) -- expected: passed; record the time.
- (once) `git diff --exit-code b50f3add -- src/ocutalon/cls/OcuTalon/Production.cls docker src/ocutalon/cls/OcuTalon/Live src/ocutalon/cls/OcuTalon/Test/Live web src/ocutalon/cls/OcuTalon/Core src/ocutalon/cls/OcuTalon/Data src/ocutalon/cls/OcuTalon/Msg src/ocutalon/cls/OcuTalon/Install src/module.xml src/cpf ci/mock` -- expected: exit 0 (the Event group, if assigned, adds `Live/Payload/Heartbeat.cls` only).
- (once) the hosted checks in three parts: `. ci/units.sh; echo $CHECK_SCRIPTS`, then about a third per call, `for n in <part>; do bash docker/tests/test-$n.sh >/dev/null 2>&1 || echo "FAIL $n"; done` -- expected: no FAIL line.
- (once) `<lane> OCUTALON_RUN_TAG=e39s3impl ci/iris.sh shard lane-a@Checks`, fresh, then again with `--reverse` -- expected: passed; record the time.
- (once) `<lane> OCUTALON_RUN_TAG=e39s3implw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e39s3impl ci/iris.sh teardown`, also after a failure.

Pinning mutations to apply, observe red, revert byte-identical and record (Rule 19):
- AC 1: due selection ignores `NextDueAt` -> `Beat.TestDueSelection`.
  - mutation: due selection ignores `NextDueAt` applied, red: TestDueSelection (not-due row, slack and restart assertions), also TestDecisionIsRecorded; reverted byte-identical (cmp against a backup, `git status --short` shows the story's files only).
- AC 2: the `cap` rule removed -> `Beat.TestSkipOrder`.
  - mutation: the `cap` rule removed applied, red: TestSkipOrder (also TestRunNow, TestInputsAreRead); reverted byte-identical (cmp against a backup, `git status --short` shows the story's files only).
- AC 2: `hours` and `empty` swapped -> `Beat.TestSkipOrder`.
  - mutation: `hours` and `empty` swapped applied, red: TestSkipOrder; reverted byte-identical (cmp against a backup, `git status --short` shows the story's files only).
- AC 2: the over-midnight window read as from<=t<to -> `Beat.TestActiveHours`.
  - mutation: the over-midnight window read as from<=t<to applied, red: TestActiveHours (mutated to `from <= t && t < to` for the over-midnight branch); reverted byte-identical (cmp against a backup, `git status --short` shows the story's files only).
- AC 2: `hours` moves `NextDueAt` by one interval -> `Beat.TestNextDue`.
  - mutation: `hours` moves `NextDueAt` by one interval applied, red: TestNextDue; reverted byte-identical (cmp against a backup, `git status --short` shows the story's files only).
- AC 2: `NextDueAt` = old `NextDueAt` + interval -> `Beat.TestDueSelection` (restart).
  - mutation: `NextDueAt` = old `NextDueAt` + interval applied, red: TestDueSelection (also TestRunNow); reverted byte-identical (cmp against a backup, `git status --short` shows the story's files only).
- AC 2: `SendOwn` does not clear `%SessionId` -> `Runs.TestTickSendsTheBeats`.
  - mutation: `SendOwn` does not clear `%SessionId` applied, red: TestTickSendsTheBeats (also TestBeatNowRunsOnce and the 30.4 TestStoppedIsReportedOnce); reverted byte-identical (cmp against a backup, `git status --short` shows the story's files only).
- AC 3: no copy to `LastQuietKey` -> `Beat.TestDecisionIsRecorded`.
  - mutation: no copy to `LastQuietKey` applied, red: TestDecisionIsRecorded (also TestRunNow); reverted byte-identical (cmp against a backup, `git status --short` shows the story's files only).
- AC 3: the back-off is always 4 h -> `Beat.TestDecisionIsRecorded` (interval 1440).
  - mutation: the back-off is always 4 h applied, red: TestDecisionIsRecorded; reverted byte-identical (cmp against a backup, `git status --short` shows the story's files only).
- AC 4: run-now obeys hours -> `Beat.TestRunNow`.
  - mutation: run-now obeys hours applied, red: TestRunNow (also TestSkipOrder); reverted byte-identical (cmp against a backup, `git status --short` shows the story's files only).
- AC 4: cooldown of 60 s -> `Beat.TestRunNow`.
  - mutation: cooldown of 60 s applied, red: TestRunNow; reverted byte-identical (cmp against a backup, `git status --short` shows the story's files only).
- AC 5: the `unchanged` rule removed -> `Heartbeat.TestAnHourOfTicks`.
  - mutation: the `unchanged` rule removed applied, red on a fresh throwaway: TestAnHourOfTicks (skip at 30 minutes, the 59 ticks, the hour's total); reverted byte-identical (cmp against a backup, `git status --short` shows the story's files only).
- AC 5: the Tick block drops the send loop -> `Heartbeat.TestBeatReachesIntake`.
  - mutation: the Tick block drops the send loop applied, red on a fresh throwaway: TestBeatReachesIntake (also TestAnHourOfTicks); reverted byte-identical (cmp against a backup, `git status --short` shows the story's files only).
- Review pass additions (each applied to the product class, observed red on the warm stack, reverted byte-identical: `git diff` before and after compared with `cmp`):
  - mutation: the `Key` separator tested on `text = ""` instead of a `kept` flag -> `Beat.TestKey` (leading empty line).
  - mutation: `InHours` and `NextDue` read the UTC clock instead of `ToLocal` -> `Beat.TestActiveHours` and `Beat.TestNextDue` (America/New_York cases).
  - mutation: `RunNow` does not read `Capped(now)` (capped = 0) -> `Beat.TestInputsAreRead`.
  - mutation: `Key` hashes the text without `$ZConvert(..., "O", "UTF8")` -> `Beat.TestKey` (the two non-ASCII vectors).
  - mutation: `Process.WithoutRef` returns the text -> `Runs.TestBeatLogsAreRedacted`.
  - mutation: the Tick drops the Items of a RunDue that answered an error status -> `Runs.TestTickSendsTheItemsOfAFailedRunDue`.
  - mutation: `BeatNow` keeps the outcome `sent` after a failed send -> `Runs.TestBeatNowSendFailureAnswersFailed`.
- 39.1's `TestStubsDoNothing` mutation line is obsolete; the test is replaced.

**Measured (implement stage):**
- Task 0, first fresh run of `Heartbeat` (tag e39s3impl): `Keys.Status("TriageAgent")` = 1 (after `Case.PointKeys`, the entries point at the CI mock key variable) and `Budget.State().capped` = false. Both preconditions held; no `## Clarification Needed`.
- `Beat` warm 0.1-0.3 s, `Runs` warm 1.4-1.9 s, `Heartbeat` fresh 11-13 s (the class; the fresh start is about 100 s). `shard lane-a@Checks`: 6 classes passed in 134 s, and passed again with `--reverse` in 131 s. The hosted checks (28 scripts, three parts) printed no FAIL, the `(once)` guard diff from b50f3add exits 0.
- Deviation from the Integration matrix row "One person fails": a row whose stored `LastQuietKey` node is 65 characters does not fail the save, because `%Save` validates only the properties that were modified since the open (measured on slot D), and a beat never modifies `LastQuietKey`. `TestOneFailureLeavesTheOthers` makes B fail another way: B's row node is replaced by a non-list string while RunDue runs (the node is put back at once), so that B's row cannot be opened and the new row for B is refused by the unique SessionRef index (error 5808). The status holds the count and the code only.

**Shared surfaces:**
- the `Test.Checks.Probe` seam signatures and new properties;
- `Checks`'s answer to `BeatNow` (now a `CommandResult`): `Runs.TestBeatNow`, `TestBeatLogsAreRedacted`, `TestBeatNowKeepsEachSession` and `Heartbeat.TestBeatNowIsAnswered` updated;
- `HeartbeatBeat` rows: real ticks now write an `empty` skip row for every session of a stack (local `on` defaults to 1); no test counts the whole table after this story;
- `Intake` gets beat Items only for sessions with a checklist, and no fixture outside these tests has one;
- unchanged: the production item list, `Live.Publish` TYPES (16), the payload classes (30) and the mock scenarios.
- Standing criterion: every test added or changed passes on a fresh environment, in either order.
- Added test time: about 3 s warm (`Beat`, `Runs`) and about 30-40 s in `Checks.Heartbeat` (61 synchronous ticks plus two decision waits) (inference). It lands in the `shards` group.

## Auto Run Result

Status: done
Blocking condition: none

**Summary:** Story 39.3 fills `Checks.Beat` (settings read on every tick, the six skip rules in AD-18's order, the row writes, the decision record and the run-now rules) and wires `Checks.Process` (`SendOwn`, the Tick's send loop, `BeatNow` answering a `CommandResult`). AC 1-5 and AC 7; AC 6 and the Event group belong to Story 39.7.

**Files changed:**
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls`: beat logic, parameters and class doc.
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls`: `SendOwn`, the beat send loop, `BeatNow`/`WithoutRef`, seams, class doc.
- `src/ocutalon/cls/OcuTalon/Test/Checks/{Beat,Runs,Heartbeat,Probe}.cls`: the tests, the probe seam and docs.

**Review:** 0 high, 5 medium and 3 low patched (see the Review Triage Log), 0 deferred, the rest rejected with their reasons logged. Follow-up review recommended: true, because two or more medium findings were patched; the unverified risk is the `Key` separator change and `WithoutRef`, which only the tests written in this pass cover.

**Verification:** warm `Beat` and `Runs` pass after the patches, all seven review-pass mutations went red and were reverted byte-identical, `shard lane-a@Checks` passed forward and `--reverse` on fresh throwaways (6 classes, about 134 s each, `Heartbeat` 12.7 s), the 28 hosted checks printed no FAIL, the (once) guard diff from b50f3add exits 0. Slot D holds the final classes. Added test time is about 3 s warm plus about 13 s in `Heartbeat`.

**Residual risks:** a pending beat whose send failed waits for the next beat (by design); the "One person fails" matrix row uses another failure mechanism than the one written (Design Notes).
