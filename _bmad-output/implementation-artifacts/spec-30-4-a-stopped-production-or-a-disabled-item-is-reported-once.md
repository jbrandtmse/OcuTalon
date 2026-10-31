---
title: 'A stopped production or a disabled item is reported once'
type: 'feature'
created: '2026-10-30'
status: 'done'
baseline_revision: '9f0280e3de82004fdf0d7ebe7ee3ec9180a44dd0'
baseline_commit: '9f0280e3de82004fdf0d7ebe7ee3ec9180a44dd0'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `Checks` sees a watched production stop (its row's finding reads "Production stopped") but never tells the user: it sends no Item to `Intake`, it does not read the items' enabled flags, and no row remembers what was already reported, so it cannot say "only new". Separately, a fix approved while its target production is stopped ends `done` with every copy Skipped, and its result reads "had changed since the dry run", which is false (DW-368, AD-16 as amended by U-160).

**Approach:**
- Each check run that reads the production compares its running state and its disabled items with what the row last reported (a new appended column, `BackgroundCheck.Reported`).
- A production newly found stopped, and each item newly found disabled, becomes exactly one `OcuTalon.Msg.Item` sent to `Intake`. The Item carries the `watch.productionStopped` or `watch.itemDisabled` key and its slots, and the row records it so that it is never sent again.
- `FixExecutor` reads the target production's state through `Watch.Reader` when the run starts. A production that is not running ends the run as couldn't start, with a plain reason.
- DW-414's test reads the first run's own time.

## Boundaries & Constraints

**Always:**
- What counts as "new" lives in the row (`Reported`), never in memory or a global. It is written in the same `UPDATE` keyed by `Ref` as the run fields (AD-5, AD-18). No row is re-created.
- Producers never render text (AD-32). `Checks` sets `CatalogKey` and `Slots` (times as UTC `YYYY-MM-DDTHH:MM:SSZ`), and only the `*Out` operations render.
- The Item passes `Intake`'s entry rules: provenance `untrusted`, an `ItemId`, the row's `SessionRef` as owner, and a `Text` (AD-14, AD-30). It goes to `Intake` only, never to `OutcomeRouter` or `Notify`.
- Only `Watch.Reader` switches namespace for these reads, inside its one method (AD-3). `Fix` reads the state through `Watch.Reader`.
- Persistent classes are append-only. The `Storage` block stays, and the compiler's new slot is written back verbatim (AD-5).
- A result's text never claims a change that did not happen. A stopped production's run is "couldn't start", never "skipped because the orders changed" (AD-16).
- Each fix run gets exactly one final `FixResult`. `StartExecution` stays the single gate.

**Never:**
- Never edit Lane B classes (`Core.Intake`, `Core.Rule.*`, `Msg.Item`, `Msg.Tick`, `Msg.ItemDecision`), `Watch/IncidentManager.cls`, `Watch/FailurePoller.cls`, `Watch/Ops.cls`, `Watch/EvidencePack.cls`, `Install/**`, `Production.cls`, or `Live.Payload.Check`'s properties.
- No new catalog key. No setting on the `Checks` item (`Test.Install.Production` pins it with no settings).
- Never send a finding for a run that could not read the production's state, or for a row deleted meanwhile.
- Never retry a finding whose send failed.
- Never change the mid-run case: a production that stops between the start check and a copy, and `Resend`'s skip code `stopped`, stay as they are. That is Story 30.5's (DW-419).
- Never run these tests on slot A.

## I/O & Edge-Case Matrix

"Previous" is the row's `Reported` before the run. `S` is the row's session. "Item" means one `Msg.Item` that `Checks` sends to `Intake`.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Stopped since the last run (AC 1) | Previous: stopped 0. Read: `stopped`, with IRIS's stop time T | One Item with: `ItemId` a new Ref; `SessionRef` S; `Channel` system; `Provenance` untrusted; `Text` "The {DisplayName} production stopped."; key `watch.productionStopped`; `Slots` `{"production": DisplayName, "time": T}`. It is sent in the Tick's session with S's TraceRef as SuperSession, and the process's own SuperSession is put back. `Reported` now has stopped 1 | -- |
| 2 | Still stopped (AC 2) | Previous: stopped 1. Read: `stopped` | No Item | -- |
| 3 | Restarted, then stopped again | A run reads `running` (stopped becomes 0), then a run reads `stopped` | A new Item on the second stop | -- |
| 4 | No stop time recorded | `stopped`, and the read gives no stop time | `time` is the run time | -- |
| 5 | Item disabled (AC 1) | Previous disabled `[]`. Read: disabled `["A","B"]` | Two Items, A then B, with: key `watch.itemDisabled`; `Slots` `{"itemName", "production": DisplayName, "time": run time}`; `Text` "The {item} in the {DisplayName} production was disabled." `Reported` disabled becomes `["A","B"]` | -- |
| 6 | Still disabled, re-enabled, disabled again | `["A","B"]`, then `["B"]`, then `["A","B"]` | No Item, then no Item, then one Item for A | -- |
| 7 | First run (baseline) | `Reported` empty (a new watch, or a row from before this story). Read: `stopped`, disabled `["A"]` | No Item. `Reported` becomes `{"stopped":1,"disabled":["A"]}` | -- |
| 8 | Not checked | The read throws, is `unreadable` or `not_current`, or gives state `timeout`, `unknown` or "" | No Item, and `Reported` is unchanged | -- |
| 9 | Not "stopped" | State `troubled` or `network_stopped` | No stop Item, and stopped becomes 0. `suspended` counts as stopped | -- |
| 10 | Watch stopped meanwhile | The row is deleted during the read | No Item, and nothing is recorded (as today) | -- |
| 11 | Send fails | `SendFinding` errs for one of two findings | One Type 3 warning (`LOGFINDING`, naming the check's Ref). The other finding still goes. Both count as reported: no resend on the next Tick | Warning, no retry |
| 12 | Story's test (live, FR-33) | S watches Orders. The Tick at NextDueAt (baseline, running), then `StopOrders`, then Ticks at +60 s and +120 s | Exactly one Item from `Checks` to `Intake` for S, across the two Ticks' sessions. Its key is `watch.productionStopped`; `production` is "Orders"; `time` lies between just before the stop and just after it. `Intake` sends one `ItemDecision` to `OutcomeRouter` with the same `CatalogKey` and `Slots` (Integration AC). Orders is started again | -- |
| 13 | Disabled item to the user (live, Integration AC) | S's fixture watch, whose DisplayName carries the marker `[[mock:check-finding-tell-now]]`. Baseline Tick, then `OrdersToWarehouse` disabled in OCUORDERS, then two Ticks | Exactly one `watch.itemDisabled` Item with `itemName` OrdersToWarehouse. S's web chat gets one tell-now notification: its text and Why now are `Catalog.Render` of that key and those slots for `web`, and the second line reads "Why now: you asked me to watch the {DisplayName} production." The item is enabled again after the test, also after a failure | -- |
| 14 | DW-368: stopped at the run's start (live) | Orders stopped when R1 is approved | One final `FixResult`: Total 3, Resent 0, Completed 0, FailedAgain 0, Skipped 0, Reason `NOTRUNNING`. R1 is `failed` (Result failed), its FixRun holds no copy, and the incident is `resolved`. S has one result notification, `result.couldNotStart`, which renders "Nothing was resent: the production isn't running. Nothing was changed." One Action entry has result failed. Nothing in OCUORDERS changed | -- |
| 15 | DW-368: unit cases | `ProductionState` gives `stopped`, `suspended` or `network_stopped`, then `troubled`, `running`, `timeout`, "", or throws | The first three: could not start with `NOTRUNNING`, and the re-check is never called. The rest go on to the re-check, which ends a read failure with `NOREAD` as today | -- |
| 16 | DW-414 | `TestWindow` with `Hang 1.1` between its two Ticks | Green on every run. The expected `from` is the first run's `LastRunAt` (kept as text before the second Tick) less 2 s | -- |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `ci/` or `_bmad`.

**Checks (the producer)**
- `Checks/Process.cls`:
  - `:1-37` class doc, which needs updating.
  - `:51` MANAGER: add `INTAKE = "Intake"` beside it.
  - `:128-156` Tick.
  - `:200-223` Sweep, the pattern to copy for the trace: `TraceOf` `:241-246`, and save/restore of `%SuperSession`.
  - `:258-270` Due: add `Reported` to the `SELECT`, and `"reported"` to the row object.
  - `:273-326` Run: `runAt` at `:275`, the read at `:283`, the not-checked reasons at `:308-317`.
  - `:329-339` Record: the one `UPDATE` at `:332`, and "nothing when no row updated" at `:334`.
  - `:413-416` Read seam.
- `Checks/Msg/CheckChanged.cls` is unchanged.

**The reader**
- `Watch/Reader.cls`:
  - `:175-186` Failures.
  - `:245-473` Current, the one switching method:
    - the state at `:258-260`;
    - the definition opened at `:261-265`;
    - "not_current" at `:267-269`.
  - The stop time is `^Ens.Configuration("csp","Activity",<production>,"stopped")` in the production's namespace. It holds `$$$timeUTC`, `YYYY-MM-DD HH:MM:SS.sss`, and is killed at a start (`irislib/Ens/Director.cls:68-69, 294`).
  - Item flags: `Ens.Config.Item` has `Production`, `Name` and `Enabled` (`irislib/Ens/Config/Item.cls:17,20,47`; SQL `Ens_Config.Item`).
- Callers of Failures:
  - `Checks/Process.cls:415`, 6 args;
  - `Watch/FailurePoller.cls:145` (Epic 9, contended; its 5-arg call must keep working);
  - `Test/Watch/Reader.cls:159-362`;
  - `Test/Watch/Poller.cls:238`.
- `Watch/Mark.cls`:
  - `:23` Normal, `:40` Shift, `:52` Start, `:117` FailedAt (the stamp a slot needs).

**The row**
- `Data/BackgroundCheck.cls`: properties `:10-46`, and Storage `:54-106`, which holds slots 1-14 (`^OcuTalonP.CheckD`).
- `Live/Payload/Check.cls` stays unchanged. `Test/Live/Payloads.cls:890-904` pins it.

**Lane B consumers (read only)**
- `Core/Intake.cls`:
  - `:122-130` Refusal, the entry rules;
  - `:142-147` Join, which keeps the header's SuperSession;
  - `:168-175` SummaryOf: the first line of the Text, which becomes the decision row's title on the page (`web/src/app/rail/rail-view.ts:275`);
  - `:217-234` Finish, which copies `CatalogKey` and `Slots`.
- `Core/Rule/Outcome.cls`: digest goes to DigestStore; tellnow and act go to the Notice transform.
- `Core/Rule/Notice.cls:32-37` uses the key and slots as they are.
- `Msg/Item.cls`, `Msg/Enum.cls:36` (CHANNEL includes `system`).

**Catalog**
- `Msg/Catalog/Watch.cls:12-27`: `watch.productionStopped` (`production`, `time`) and `watch.itemDisabled` (`itemName`, `production`, `time`). Their text matches the story; `{readable item name}` is the item's name (EXPERIENCE.md:812).
- `:235-241`: `result.couldNotStart` (`reason`).
- `Msg/Catalog.cls:158-164`: a time renders as HH:MM in the instance zone.

**The executor (DW-368)**
- `Fix/Executor.cls`:
  - `:3-60` class doc;
  - `:66-75` UNUSABLE, NOREAD and NOSTART, the precedents;
  - `:182-215` Execute;
  - `:295-338` Run: the FixRun is saved at `:305`, before Check at `:306`;
  - `:343-358` CouldNotStart(row, total, reason, saved);
  - `:819-893` Resend, skip code `stopped` at `:864`, which stays;
  - `:895-907` SkipReason.
- `Watch/Notice.cls:20-27`: ResultKey (couldNotStart when nothing counted and a Reason).

**Tests and fixtures**
- `Test/Checks/Probe.cls`:
  - `:63-77` Read: the spec gains `disabled` and `stoppedAt`.
  - `:157` Feed, `:163` Reset.
  - It has no Intake seam yet.
- `Test/Checks/Runs.cls`:
  - `:282-300` TestWindow (DW-414). The measured cause: `Record` (`Checks/Process.cls:335-336`) opens and `%Reload`s the same OREF the test holds in `row`, so `row.LastRunAt` becomes the second run's time.
  - Helpers: `:554` Watch, `:587` Feed, `:614` Tick, `:626` Case, `:711` Warnings.
- `Test/Checks/Heartbeat.cls`:
  - `:63-87` TestFailingOrders: its stop Tick will now send one Item, which it does not assert.
  - The class runs fresh.
- `Test/Watch/Case.cls`:
  - `:343` HeadersBetween, `:614` Watch (due 24 h ahead), `:630` SendTick, `:663` Tick;
  - `:1120` StopOrders, `:1129` StartOrders, `:1154` OrdersRunning;
  - `:464` PutBack, `:1383` NoticeBodies.
  - `Test/Core/Observe.cls:47` Events.
- `Test/Data/Fixture.cls:65-77` Check(session, namespace, production, fields).
- `Test/Watch/Reader.cls:264-298` TestStoppedProduction: extend it.
- `Test/Fix/Runs.cls`: `:20-24` doc and `:213-250` `TestStoppedProductionSkipsEveryCopy`, which this story rewrites.
- `Test/Fix/Executor.cls`:
  - `:124-128`: copies of the reason texts;
  - `:252` TestCouldNotStartRoutes;
  - `:461-464` TestNothingResent, the canned mid-run stop, which stays (Story 30.5).
- `Test/Fix/ExecutorProbe.cls:89-91` CheckIs/CarryIs, the pattern for a new StateIs.
- `Test/Data/Tables.cls:482-503`: our own BackgroundCheck entry.
- Precedent for EnableConfigItem in a test: `Test/Schedule/Heartbeat.cls:421`.
- `ci/mock/scenarios/A/decide-ignore.json` is the shape of a one-reply marker scenario.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 -- On the warm throwaway (fresh where a production job's code matters), measure and record under Design Notes "Measured at implementation":
  - (a) After `StopOrders`: the value of `^Ens.Configuration("csp","Activity","OcuTalon.Demo.Orders.Production","stopped")` in OCUORDERS, compared with `$ZTimeStamp`. Is it UTC `YYYY-MM-DD HH:MM:SS.sss`?
  - (b) After `Ens.Director.EnableConfigItem("OrdersToWarehouse", 0, 1)` in OCUORDERS (the precedent is `Test/Schedule/Heartbeat.cls:421`): a later read sees `Enabled` 0, through the `Ens_Config.Item` rows of the production (`Production`, `Enabled`) or through the definition's `Items`. Check it in the test process, and in the Checks job on the fresh Heartbeat run. Use the `Ens_Config.Item` rows when they show it, else the definition's `Items`. Record which.
  - (c) A `[[mock:…]]` marker in a finding Item's Text selects that scenario for `Intake`'s decide request.
- [ ] `Data/BackgroundCheck.cls` -- add `Property Reported As %String(MAXLEN = "")` after `LastRunHeaderId`, with this doc: "What the findings of the check have reported, as JSON, written by Checks with each run that read the production: {"stopped": 1 while the production's stop has been reported, "disabled": [the names of its items reported disabled]}; empty until the first such run, which reports nothing." Keep the Storage block. Compile on slot A and write back the appended `<Value name="15">` verbatim. Update the class doc -- V1.
- [ ] `Watch/Reader.cls` -- `Failures` gains the trailing outputs `disabled` and `stoppedAt`, both read in `Current`'s one switch when the production is the namespace's own:
  - `disabled`: a `%DynamicArray` of the names of the production's items whose `Enabled` is 0 in its stored definition, in ID order (Task 0b).
  - `stoppedAt`: the stop time above, as stored, or "".
  - Both are `[]` and "" with every other outcome, and with a read that threw. Existing callers keep working.
  - Update the doc of the class, Failures and Current.
- [ ] `Checks/Process.cls` -- the findings:
  - Due carries `reported`.
  - The Read seam passes `.disabled` and `.stoppedAt` through.
  - A new pure `ClassMethod Findings(previous, state, disabled, Output reported) As %DynamicArray` applies rows 1-9. It gives `[{"kind": "stopped"} | {"kind": "disabled", "item"}]` in that order. `reported` is the previous value, unchanged, when the state is not readable (row 8).
  - Run calls Findings only when the read gave a state: outcome `read`, nothing thrown, and a state other than `timeout`, `unknown` and "" (row 8). A run that is `not_checked` only because the read was cut (`REASONTOOMANY`) or the incidents could not be read still compares the state. Run then builds each Item (row 1, row 5; the time from `Mark.FailedAt(stoppedAt)` when that is a stamp, else `runAt`) and passes the Items and `reported` to Record.
  - Record writes `Reported` in its `UPDATE`. Then, only when a row was updated, it sends each Item through a new private seam `SendFinding(item)` (`SendRequestAsync(..#INTAKE, item, 0)`) with S's TraceRef as SuperSession, put back after each send. A failed or thrown send logs `LOGFINDING` and the rest still go (row 11). The event and the log line follow as today.
  - Add the parameters `INTAKE`, `LOGFINDING`, `TEXTSTOPPED` ("The {production} production stopped.") and `TEXTDISABLED` ("The {itemName} in the {production} production was disabled.").
  - Update the class doc -- AC 1-3, V2, V4.
- [ ] `Fix/Executor.cls` -- the start check:
  - `Parameter NOTRUNNING = "the production isn't running"`, documented beside NOSTART (veto item V3).
  - A private seam `ProductionState(incident) As %String`: `Watch.Reader.Failures(incident.Namespace, incident.Production, "", 0, .rows, .state)`, giving the state on outcome read, else "".
  - In `Run`, after the FixRun's first save and before `Check`: a state of `stopped`, `suspended` or `network_stopped` ends the run through `CouldNotStart(row, total, ..#NOTRUNNING, 1)`, and the re-check is not called. A seam that throws, or gives any other state, goes on (row 15).
  - Update the class doc, items 5 and "A run that cannot start" -- DW-368.
- [ ] `ci/mock/scenarios/A/check-finding-tell-now.json` (NEW) -- marker `check-finding-tell-now`, one reply `{"outcome":"tellnow","reasons":["The CI mock tells you about this check finding now."],"confidence":0.8}`, in the `decide-ignore.json` shape -- row 13.
- [ ] `Test/Checks/Probe.cls` -- Read gives the spec's `disabled` (default `[]`) and `stoppedAt` (default "") as well. `SendFinding` records `{itemId, sessionRef, channel, provenance, text, sender, subject, catalogKey, slots, sessionId, superSession}` in `Findings` and answers OK, or an error for a check Ref in `FailFinding`. Reset clears both. Update the doc.
- [ ] `Test/Checks/Runs.cls`:
  - Probe tests for rows 1-11: each asserts the Items recorded, `Reported` on the row, the trace fields and the warning.
  - A pure test of `Findings`.
  - A render test: each Item's key and slots render through `Catalog.RenderAt` (a fixed now) to the UX text.
  - TestWindow (DW-414): keep the first run's `LastRunAt` as text and `Kill` the row object before the second Tick, put `Hang 1.1` between the two Ticks, and assert against the kept text (row 16). Check the class for any other row object held across a Tick and compared after, and fix it the same way.
  - Update the doc -- AC 1-3, DW-414.
- [ ] `Test/Checks/Heartbeat.cls`:
  - `TestStoppedProductionIsReportedOnce` (row 12, the story's test).
  - `TestDisabledItemIsReportedOnce` (row 13). Its own `OnAfterOneTest` enables the item again and updates the production before `##super`, also after a failure.
  - TestFailingOrders' doc says that its stop Tick sends one finding Item.
  - Count Items with `HeadersBetween(tickSession, 1, "Checks", "Intake", "OcuTalon.Msg.Item")` over S's bodies -- AC 1, AC 2, Integration ACs.
- [ ] `Test/Watch/Reader.cls`:
  - TestStoppedProduction also asserts `Failures`' `state` stopped and `stoppedAt` (a stamp between before and after the stop), and `disabled` `[]`.
  - A new test disables `OrdersToWarehouse` and asserts `disabled` `["OrdersToWarehouse"]`, then `[]` once it is enabled again. The item is restored after the test.
- [ ] `Test/Fix/ExecutorProbe.cls` and `Test/Fix/Executor.cls`:
  - `StateIs` (a state, or `throw`) overrides `ProductionState`.
  - New cases in TestCouldNotStartRoutes or a sibling test for row 15: the request failed, the FixResult `n|0|0|0|0` with `NOTRUNNING`, Checked 0, one Action entry failed.
  - A `NOTRUNNING` parameter copy beside `:124-128` -- DW-368.
- [ ] `Test/Fix/Runs.cls` -- rewrite `TestStoppedProductionSkipsEveryCopy` as `TestStoppedProductionCannotStart` (row 14) and its doc lines `:20-24` -- DW-368.
- [ ] `Test/Data/Tables.cls` -- our own BackgroundCheck entry gains `"Reported": "%String(MAXLEN=)"`.

**Acceptance Criteria:**
- Given a watched production that the check's last run found running, or one of its items enabled, when it stops, or the item is disabled, and the next Tick runs the check, then exactly one `OcuTalon.Msg.Item` goes to `Intake` for that finding. Its `CatalogKey` and `Slots` are `watch.productionStopped` with `production` and `time`, or `watch.itemDisabled` with `itemName`, `production` and `time`. `Intake` copies them to the `ItemDecision` it sends to `OutcomeRouter`, and a tell-now decision reaches the session's web chat as "The … production stopped at {time}." or "The {item} in the … production was disabled at {time}.", then "Why now: you asked me to watch the … production." (rows 1, 5, 12, 13; FR-23, AD-14, AD-30, AD-32, UX-DR112).
- Given that finding has been sent, when two more Ticks run with the production still stopped (or the item still disabled), then no second Item is sent. The live test sends two Ticks after stopping a test production and finds exactly one finding Item (rows 2, 6, 12; FR-33).
- Given a first run, a run that could not read the production, a row deleted meanwhile, or a send that failed, when the Tick runs, then rows 7, 8, 10 and 11 hold: nothing is reported twice, and nothing is reported from a state that was not read.
- Given an approved fix whose target production is not running when the run starts, when `FixExecutor` runs it, then the run ends as couldn't start: one final `FixResult` with `Resent` 0, `Skipped` 0 and the reason `NOTRUNNING`, the row closed `failed`, the incident out of `fixing`, and the notification `result.couldNotStart` ("Nothing was resent: the production isn't running. Nothing was changed."). No result claims that the orders changed (rows 14, 15; DW-368, AD-16 as amended, U-160).
- Given `Test.Checks.Runs.TestWindow`, when its two runs fall in different clock seconds, then it passes, because it compares against the first run's own `LastRunAt` (row 16; DW-414).

## Spec Change Log

## Review Triage Log

### 2026-10-30 -- Review pass
- verdicts: 25 rows -- high 0, medium 1, low 19, false 5, maybe-false 0 (grouped findings share a row; by-design and spec-bound rows count as low and are rejected)
- findings:
  - `[low]` `[reject]` BH1/EH3 a `Reported` that is valid JSON but not an object makes `Findings` throw each Tick -- only Checks writes `Reported`, always as an object; no user path reaches it, and the fix adds a guard.
  - `[low]` `[reject]` BH2/EH6 a failing `Ens_Config.Item` query fails the whole `Current` read -- the table is in the production's own namespace, read right after its definition; a failure there is a failed definition read as well. No guard added.
  - `[low]` `[reject]` EH7 `Evidence` also runs the item query and the global read -- one indexed SELECT per read, negligible.
  - `[false]` `[reject]` BH3 a failed `TestStoppedProductionIsReportedOnce` leaves Orders stopped -- `Test.Watch.Case.OnAfterOneTest` calls `PutBack`, which starts Orders again (class doc and `:231`).
  - `[low]` `[patch]` BH4 `SetItemEnabled`/`OnAfterOneTest`/`ITEMNAME` duplicated in Heartbeat and Reader (Rule 2) -- moved into `Test.Watch.Case` (the Orders item, `ItemDisabled`, `SetItemEnabled`, the re-enable in `OnAfterOneTest`); both classes use it.
  - `[low]` `[patch]` BH5 the `--- helpers ---` marker swallowed into `SetItemEnabled`'s doc -- the helper is gone from Heartbeat and the marker is back with `WaitStopped`.
  - `[low]` `[reject]` BH6 `NotRunning` swallows a throw from the state read silently -- the spec says a throwing seam goes on to the re-check, whose read failure logs NOREAD.
  - `[low]` `[reject]` BH7/EH4 `$Replace` order and a newline in a name -- a display name containing the text `{itemName}`, or an item name with a newline, is not reachable from the product (names come from the watched production's definition).
  - `[low]` `[reject]` BH8 the disabled item's `time` is the run time -- decided and ruled (V4, veto U-180, AD-15); spec-bound.
  - `[false]` `[reject]` EH1 two Checks jobs send one finding twice -- `Checks` has PoolSize 1 in `Production.cls`, and a due row is gated by `NextDueAt`.
  - `[low]` `[reject]` EH2 no cap on Items per run -- spec: every newly disabled item is its own Item, with no cap (Design Notes).
  - `[low]` `[reject]` EH5 a crash between the `UPDATE` and the send loses a finding for good -- spec: send after the row's update, never retried (Design Notes); "never sent again" is the guarantee.
  - `[false]` `[reject]` EH8 a stale stop time -- IRIS kills the stamp at a start (`Ens/Director.cls:68-69, 294`), and the time is used only when the state is stopped/suspended.
  - `[low]` `[reject]` EH9 a stop and restart in one interval is not reported -- decided in the spec (the state at each run decides).
  - `[low]` `[reject]` EH10 a `timeout`/`unknown` state at the start goes on -- row 15 of the matrix; the mid-run case is Story 30.5's.
  - `[low]` `[reject]` EH11 a FixRun save that throws ends as NOREAD, not NOTRUNNING -- the run did not start for another reason, and NOREAD is the existing behaviour for it.
  - `[low]` `[reject]` EH12/EH13 `FailFindings` matches by the Item's Text, not the check's Ref -- `SendFinding(item)` has no Ref, and row 11 needs one of two findings of one check to fail; the doc says so.
  - `[medium]` `[patch]` VG1 the thrown-send branch of `Record` had no test -- `Probe.FailFindings(texts, throw)` and `Runs.TestThrownSendIsNeverRetried` added; mutation line written (the `Catch` answering OK -> red, observed).
  - `[low]` `[patch]` VG2 an incident read that fails still compares the state, but no test pinned it -- a step added to `TestNotCheckedReportsNothing`; mutation line written (`'unread` in the gate -> red, observed).
  - `[low]` `[reject]` VG-other1 `WaitDeliveries(session, 1)` returns at the first delivery -- duplicate Items are excluded by the per-Tick Item counts; the delivery is one by construction.
  - `[false]` `[reject]` VG-other2 `TestDisabledItems` control assertion relies on earlier state -- `Case.OnAfterOneTest` restores the item and Orders, so each test starts from them.
  - `[false]` `[reject]` VG-other3/IA the intent-alignment auditor and the hunt for unfalsifiable assertions reported no divergence and no unfalsifiable assertion -- descriptive reports, counted as two rows with no defect (IA: rows 12-14 are live tests that ran green in this stage).
  - `[low]` `[reject]` EH12b the claim that the spec's `FailFinding` names a Ref -- same as EH12/EH13.
  - `[low]` `[reject]` EH-claim the Reader's `stoppedAt` is "" for a never-stopped production -- by design (time falls back to the run time, row 4).
  - `[low]` `[reject]` BH-resid duplicates BH8.

## Design Notes

**Architecture decisions (Rule 6).**
- AD-18: only new findings become Items. The row holds what was reported. Checks writes the run fields and `Reported` with one `UPDATE`.
- AD-14, AD-30, AD-32: a check finding is an `untrusted` Item to `Intake` with `CatalogKey` and `Slots`. Producers never render.
- AD-16 (amended 2026-10-30, U-160): a production not running at the run's start ends the run as couldn't start, like the missing-resources case. A result's text never claims a change that did not happen.
- AD-15: a final `FixResult` while `fixing` resolves the incident.
- AD-3: the reads stay in `Watch.Reader`'s one switch.
- AD-5: append-only storage, and "new" kept in rows.
- AD-26: the Item goes in the Tick's session, with the owner's TraceRef.
- AD-4: each session's row gets its own Item.
- AD-33: Lane B classes are read only.
- AD-2: no bridge change.
- AD-22: throwaway stacks.

**V1. A stored-data change, for the lead's ruling (veto window: how stored data is kept).**
- **Chosen:** one appended property, `BackgroundCheck.Reported` (`%String(MAXLEN = "")`, JSON, slot 15), written by `Checks` in its existing `UPDATE`. Rows from before this story have it empty, so their first run is a baseline (row 7). Later check kinds (AD-18: source polls, queue backlog, SQL watch) can keep their own keys in it.
- **Rejected:**
  - (a) A private mark global per check (`^OcuTalonP.CheckMark`): it is not a row (AD-18 and Conventions "Background checks"). It would outlive the row, because WatchOps (Epic 9, contended) deletes only the row. SQL can't see it.
  - (b) Deriving "already sent" from earlier Items or ItemDecisions: `Checks`' messages are purged after 7 days (Story 30.2), so a production stopped longer than that would be reported again. It also costs a message search on every run.
  - (c) Deriving it from the previous `Result`/`Finding`: that means parsing public text, it holds no item names, and a `not_checked` run loses the state.
  - (d) A new findings table: a new AD-33 table and a spine row, more than "only new" needs.
- **Recommendation:** add the column. The CI storage diff stays append-only, and `Test.Data.Tables` gains our own entry.

**V2. Public text: the finding Item's `Text` (veto window: public-facing text not already specified).** The first line of an Item's Text becomes the item summary, which the page shows as the decision row's title (`Intake.SummaryOf`; `rail-view.ts:275`). The UX gives no title for a check finding.
- **Recommended:** the catalog sentence without its time and its Why now line: "The Orders production stopped." and "The OrdersToWarehouse in the Orders production was disabled." They introduce no new words.
- **Alternative:** the check's existing finding words ("Orders: Production stopped").

**V3. Public text: the couldn't-start reason (veto window).** `Fix.Executor.NOTRUNNING` = "the production isn't running". It renders as "Nothing was resent: the production isn't running. Nothing was changed."
- These are the words of the existing per-copy skip reason (`SkipReason` `:899`).
- **Alternative:** a reason naming the production. The reasons are fixed parameters with no slot.

**V4. A claim about what the product does (veto window): the `{time}` slot.**
- For a stopped production it is IRIS's own stop time (`^Ens.Configuration(...,"stopped")`, written by `StopProduction`), so it is exact.
- When IRIS recorded none (a crash), and for a disabled item, which IRIS gives no time for, it is the time the check found it. That can be up to one check interval (60 s) after the change.
- AD-15 already states that a change's time is known only to within the check interval.
- **Recommendation:** keep this, and add the sentence to AD-18 (spine note below).

**Lead rulings (spec gate, 2026-10-30).**
- V1 kept: `BackgroundCheck.Reported` — veto item U-179. The lead wrote the spine's Conventions "Background checks" row now (it lists `Reported` and the baseline rule, with the U-179 marker).
- V2, V3 and V4 kept as recommended — veto item U-180 (the owner may reverse the texts before the release).
- Spine note: AD-18 and AD-3 are NOT amended (decide). AD-15 already states that a change's time is known only to within the check interval, which covers V4; AD-3's Rule is unchanged because the new reads stay inside `Watch.Reader`'s one switch. Cite AD-15 for V4 in code comments and tests; do not edit the spine.
- The repository is public: the new mock scenario `ci/mock/scenarios/A/check-finding-tell-now.json` and every test fixture use the existing fixture names only (no real infrastructure values).

**Decided in-stage.**
- **Baseline.** A row's first run with `Reported` empty records the state and sends nothing (row 7). This covers:
  - a watch started on a production that is already stopped: "stopped at {time}" would name a time before the watch existed;
  - items that are disabled by design;
  - rows from before the upgrade, which would otherwise flood users.

  The check row's `Finding` still shows "Production stopped" on the page. The AC's "since the last run" needs a last run.
- **Which states.**
  - The finding counts `stopped` and `suspended` (a stop that left queued messages) as stopped.
  - `troubled`, `network_stopped`, `timeout` and `unknown` are not stops.
  - The executor's "not running" is `stopped`, `suspended` and `network_stopped`, the states in which IRIS's resend refuses (`Ens.MessageHeader:461` uses `IsProductionRunning`; that `troubled` passes that check is an inference).
- **Disabled** means `Enabled` 0 in the production's stored definition. A `TempStopConfigItem` stop is not a disable. Every newly disabled item is its own Item, with no cap, in ID order.
- **Item fields.** `Channel` system, no Sender or Subject, `ItemId` from `Bridge.Ids.NewRef()`. The trace is the Tick's session with S's TraceRef, as the quiet sweep does (AD-26).
- **Send after the row's update, never retried.** "Never sent again" is the guarantee. A lost send is logged, and the check row still shows the finding.
- **The start check comes after `StartExecution` and the FixRun's save,** not before `Start` as the resources check does. A second Execute is then refused by the single gate, and the run has exactly one final `FixResult`.
- **A stop and a restart inside one check interval are not reported.** The state at each run decides.
- **Demo mode off** stops Orders before its namespace is removed (`Install/Step/Demo.cls:594`). A Tick in between correctly reports "stopped" to a session watching Orders.
- **DW-414's cause** is measured, not the clock. On slot A (read-only), a second `%OpenId` of an object already open in the process returned the same OREF (`Ens.Config.Production`, `1616@` both times). So `Record`'s `%Reload` rewrites the test's `row`. The test failed whenever the two runs fell in different seconds; midnight was a coincidence.
- **The Integration AC reaches the chat** through a mock marker in the fixture watch's display name, because the mock's Triage answers `digest` by default (`ci/mock/scenarios/A/triage.json`). Row 12 asserts the `ItemDecision` at `OutcomeRouter`, which holds whatever the outcome.
- **Not changed (Story 30.5, DW-419):** a production that stops after the start check, `Resend`'s skip code `stopped`, and `Test.Fix.Executor.TestNothingResent`'s canned all-stopped Carry.

**Decided at implementation.**
- `Probe.FailFindings` matches by the Item's Text (comma-separated fragments), not by the check's Ref: `SendFinding(item)` carries no Ref, and row 11 needs one of two findings to fail.
- The Orders item switch (`ITEMNAME`, `ItemDisabled`, `SetItemEnabled`, the re-enable in `OnAfterOneTest`) lives in `Test.Watch.Case` (Ours, Test/Watch), shared by Heartbeat and Reader.
- A time on another day renders as "on {date} at {time}" (`Msg.Catalog`); `TestFindingsRender` allows for it.

**Measured at planning (slot A `ocutalon-slot-a`, build 154, port 52790, read-only).**
- `%OpenId` of an already open `Ens.Config.Production` gives the same OREF with concurrency 0 and with the default.
- Slot A has no OCUORDERS and no `^Ens.Configuration("csp","Activity")` entries, so the stop time's format is Task 0a, on a throwaway.

**Measured at implementation (throwaway stacks `e30s4hw` warm and `e30s4h` fresh, build 154).**
- Task 0a: after `StopOrders`, `^Ens.Configuration("csp","Activity","OcuTalon.Demo.Orders.Production","stopped")` in OCUORDERS is a UTC stamp `YYYY-MM-DD HH:MM:SS.sss`. `Test.Watch.Reader.TestStoppedProduction` reads it through `Failures` as `stoppedAt` and asserts that `Mark.FailedAt(stoppedAt)` lies between `NowUtc()` taken just before and just after the stop (both UTC to the second). `Test.Checks.Heartbeat.TestStoppedProductionIsReportedOnce` asserts the same for the `time` slot of the Item from the real Checks job.
- Task 0b: the `Ens_Config.Item` rows of the production (`Production`, `Enabled`) show `Enabled` 0 after `Ens.Director.EnableConfigItem("OrdersToWarehouse", 0, 1)` in OCUORDERS, both in the test process (`Test.Watch.Reader.TestDisabledItems`: `["OrdersToWarehouse"]`, then `[]` once it is enabled again) and in the Checks job on the fresh run (`Test.Checks.Heartbeat.TestDisabledItemIsReportedOnce`: one `watch.itemDisabled` Item). `Reader.Current` therefore reads the SQL rows, not the definition's `Items`.
- Task 0c: a `[[mock:check-finding-tell-now]]` marker that the Item's Text carries (the display name is in it) selects the scenario for `Intake`'s decide request: the tell-now decision reaches the web chat as one Delivery row (`TestDisabledItemIsReportedOnce`). Without the marker, row 12's Item still gets its `ItemDecision` at `OutcomeRouter`.
- A time slot on another day than the catalog's `now` reads "was disabled on {date} at {time}" (`Msg.Catalog` replaces a trailing "at " with "on " for a dated time), which `TestFindingsRender` takes into account.
- Times: warm `Test.Watch.Reader` 3 s, `Test.Checks.Runs` 1.3 s, `Test.Fix.Executor` 29 s, `Test.Data.Tables` 0.4 s; fresh `Test.Checks.Heartbeat` 3.8 s, `Test.Fix.Runs` 62 s (each fresh start took 90-155 s).

**Integration ACs (Rule 1).**
- Row 12: `Intake` (Lane B, the real item) reads the Item and sends `OutcomeRouter` an `ItemDecision` that carries its `CatalogKey` and `Slots`.
- Row 13: `OutcomeRouter`, `Notify` and `WebChatOut` turn the tell-now decision into a web chat notification rendered from `watch.itemDisabled`.

**Consumed-by:**
- `Intake`, `OutcomeRouter`, `Notify` and `WebChatOut` (Lane B, Story 2.7): the finding's notification (rows 12 and 13).
- Story 30.5: the mid-run stop (DW-419). It shares `CouldNotStart` and the Result texts order.
- The step 4 and 5 check kinds (AD-18): "only new" kept in `Reported`.

**Consumes:**
- `Watch.Reader.Failures` (Stories 5.2, 5.6) and `Checks`' runs (Stories 5.6, 5.10).
- `Intake` (2.6) and `Core.Rule.Outcome`/`Notice` (2.7).
- `Msg.Catalog.Watch` (0.9).
- `Fix.Executor.CouldNotStart`/`Finish` (7.4) and `Watch.Notice.ResultKey` (7.3).
- `Test.Watch.Case`, and the CI mock (marker scenarios).

**Extend, don't copy (Rule 2).**
- The disabled items and the stop time extend `Reader.Current`'s one switch, with no second read.
- The Item's trace reuses `TraceOf` and Sweep's save/restore (4 lines).
- The executor reuses `CouldNotStart` with `saved` 1, and its reason sits beside UNUSABLE, NOREAD and NOSTART.
- The probes extend `Read`/`Feed` and follow `CheckIs`.
- The live tests reuse `Test.Watch.Case`'s helpers (Watch, Tick, StopOrders, HeadersBetween).
- `TestStoppedProductionIsReportedOnce` is a new method and not an extension of TestFailingOrders: that test's failing orders raise an incident, which this pin does not need.

**Spine note for the lead (Rule 20).**
- Conventions "Background checks": Checks writes the run fields and `Reported`, and a row's first reading run is a baseline.
- AD-18: the `{time}` sentence (V4).
- AD-3: `Watch.Reader` also reads the disabled items and the stop time in its one switch.

**Ledger inbox (Rule 17).**
- DW-368: addressed (rows 14, 15; executor task; `Test.Fix.Runs` rewrite).
- DW-414: addressed (row 16; `Test.Checks.Runs` TestWindow).

**Contended edits:** none. The plan edits no Epic 9 file (`Watch/IncidentManager.cls`, `FailurePoller.cls`, `Ops.cls` untouched; FailurePoller's call of `Failures` keeps working), no `Install/**` file and no Lane B class.

**Files outside "Ours"** (`footprint_extensions`):
- `Data/BackgroundCheck.cls`: Lane A's table, Data by class (AD-33).
- `Watch/Reader.cls`: Lane A's, not contended.
- `Test/Data/Tables.cls`: shared by entry; our own entry.
- `ci/mock/scenarios/A/check-finding-tell-now.json`: a new file in Lane A's folder.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=30 stage=implement'`, run from the worktree root. The fresh tag is `e30s4i` and the warm tag `e30s4iw`.

How to run:
- One command per tool call, in the foreground, with `timeout: 600000`. Never two IRIS test runs in one message.
- The harness moves a call to the background after about 180 s. Poll it in loops of under 170 s, and never start a second copy.

Where to run:
- **Throwaway stacks only.** These tests stop the Orders production, disable an Orders item, send Ticks and Items, and approve fixes. The recipe is `ci/iris.sh class|shard` with the lane's variables.
- **Warm for probe and in-process classes.** Fresh for `Checks.Heartbeat` and `Fix.Runs`: `Checks` and `FixExecutor` are code of the running production, and a warm stack's jobs keep their old code.
- **`ci/mock` changes** (the new scenario) refuse a warm run: `ci/warm.sh down`, then `up`.
- **On `ocutalon-slot-a`** (`server` `ocutalon-slot-a`, `namespace` `OCUTALON`, checked with `iris_server_info`, build 154), only load and compile the changed classes (`iris_doc_load`, `baseDir` `src/ocutalon/cls`). Then export BackgroundCheck's compiled Storage block back into the file.
- Tear down only your own tags, after a failure too.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e30s4iw ci/warm.sh up`, once, and again after the scenario file is added. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e30s4iw ci/iris.sh class <Class>`, one call per class. Expected: `CLASS … passed`.
  - `OcuTalon.Test.Checks.Runs`
  - `OcuTalon.Test.Fix.Executor`
  - `OcuTalon.Test.Watch.Reader` (first, with Task 0a and 0b)
  - `OcuTalon.Test.Data.Tables`
- (loop) `<lane> OCUTALON_RUN_TAG=e30s4i ci/iris.sh class <Class>`, fresh, one call per class. Expected: `CLASS … passed`.
  - `OcuTalon.Test.Checks.Heartbeat` (Task 0c)
  - `OcuTalon.Test.Fix.Runs`
- (once) `bash ci/checks.sh`. Expected: every script passes, storage included.
- (once) `bash docker/tests/test-mock.sh`. Expected: the mock's node tests pass with the new scenario.
- (once) `<lane> OCUTALON_RUN_TAG=e30s4i ci/iris.sh shard lane-a --part k/6` for k = 1 to 6, fresh, one call each. Expected: passed, with each part's time recorded.
- (once) `<lane> OCUTALON_RUN_TAG=e30s4i ci/iris.sh shard lane-b --part 1/2`, then `--part 2/2`, fresh. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e30s4iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e30s4i ci/iris.sh teardown`, also after a failure.

**Shared surfaces:**
- **BackgroundCheck's columns** (+`Reported`): `Test.Data.Tables`' own entry. `Watch.Case.Rows` and `Live.Payload.Check` select fixed columns and are unchanged.
- **`Checks.Process`'s Read seam** (+2 outputs) and the new `SendFinding` seam: `Test.Checks.Probe`, the only subclass.
- **`Watch.Reader.Failures`** (+2 trailing outputs): FailurePoller, `Test.Watch.Reader` and `Test.Watch.Poller` keep their calls.
- **Checks now sends Items to Intake.**
  - `Test.Checks.Heartbeat.TestFailingOrders` sends one, on its stop Tick.
  - `Test.Watch.Reader.TestStoppedProduction`'s WatchOps row only records a baseline.
  - The `Posts(mark)` = 0 tests run in `shards-2`, where no due Orders row exists while Orders is stopped (sweep at planning).
- **A stopped production at a fix run's start** now gives couldNotStart: `Test.Fix.Runs`.
- **The mock's scenarios** (+1 file).
- **CI time:** the new live tests run in `shards` (the Checks and Watch areas) and in `shards-2` (Fix). Expect about +1 to +2 minutes (inference) on 20.4 and 20.8.
- Every test added or changed passes on a fresh environment, in either order. An item disabled or a production stopped by a test is restored after it, also after a failure.

**Pinning mutations (Rule 19).** Apply each mutation, observe red, revert byte-identically (`git status --short` and `git diff --stat` unchanged), and record `mutation: … → …` here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1, rows 1, 12 | Record never calls `SendFinding` | Runs row 1; Heartbeat row 12 (no Item) |
| AC 1, row 1 slots | `production` slot = `row.Production` (the class) | Runs row 1; Heartbeat row 12 |
| AC 1, rows 1, 4 time | the stop time ignored (always `runAt`) | Runs row 1 (time is T) |
| AC 2, rows 2, 12 | `Findings` ignores `previous` | Runs row 2; Heartbeat row 12 (two Items) |
| row 3 | stopped kept 1 on a `running` run | Runs row 3 |
| AC 2, rows 5, 6, 13 | `Reported` disabled never stored | Runs rows 5 and 6; Heartbeat row 13 (two Items) |
| row 6 | disabled kept as a union (never dropped) | Runs row 6 (A not sent again) |
| AC 3, row 7 | the first run reports | Runs row 7 |
| AC 3, row 8 | Findings runs on a not-checked run | Runs row 8 |
| AC 3, row 10 | the sends happen before the `ROWCOUNT` check | Runs row 10 |
| AC 3, row 11 | a failed send drops its finding from `Reported` | Runs row 11 (sent again) |
| row 1 trace | SuperSession not set for the send | Runs row 1 (superSession) |
| Integration, row 12 | the Item's Provenance is `user` | Heartbeat row 12 (no ItemDecision: Intake refuses) |
| Integration, row 13 | the Item's `CatalogKey` left empty | Heartbeat row 13 (the card is not the itemDisabled text) |
| Reader | `disabled` always `[]` | Watch.Reader disabled test; Heartbeat row 13 |
| AC 4, row 14 | the start check dropped | Fix.Runs row 14 (Skipped 3, result.skipped); Fix.Executor row 15 |
| AC 4, row 15 | the check uses `state '= "running"` | Fix.Executor row 15 (troubled ends couldn't start) |
| AC 5, row 16 | `Mark.Start` ignores `markAt` | TestWindow; and, once, the old re-read expectation with the `Hang 1.1` → TestWindow red on every run |
| Storage | the Tables entry lacks `Reported` | `Test.Data.Tables` |

mutation lines (Rule 19; each applied, red observed, reverted byte-identically with `cmp` against a copy):
- mutation: `Record` does not call `SendFinding` (`Set sc = $$$OK`) -> Runs TestStoppedIsReportedOnce rows 1-4, TestDisabledItemsAreReportedOnce, TestFailedSendIsNeverRetried, TestSuspendedAndTroubled red.
- mutation: `production` slot = `row.production` -> Runs TestStoppedIsReportedOnce (key and slots), TestDisabledItemsAreReportedOnce (slots), TestFindingsRender red.
- mutation: the stop time ignored (`runAt` always) -> Runs TestStoppedIsReportedOnce (IRIS's stop time) and TestFindingsRender red.
- mutation: `Findings` ignores the stop in `previous` (`If stopped Do found.%Push`) -> Runs TestFindingsRule row 2, TestFirstRunIsABaseline, TestStoppedIsReportedOnce rows 2-4 red.
- mutation: stopped kept 1 on a run that does not read stopped -> Runs TestFindingsRule rows 3 and 9, TestStoppedIsReportedOnce row 3, TestSuspendedAndTroubled red.
- mutation: `Reported` disabled never stored (`[]`) -> Runs TestDisabledItemsAreReportedOnce rows 5-6, TestFindingsRule rows 5-7, TestFirstRunIsABaseline, TestFailedSendIsNeverRetried red.
- mutation: disabled kept as a union -> Runs TestFindingsRule row 6 and TestDisabledItemsAreReportedOnce row 6 (A is not sent again) red.
- mutation: a missing `previous` treated as `{stopped 0, disabled []}` (the first run reports) -> Runs TestFindingsRule row 7, TestFirstRunIsABaseline red.
- mutation: the state guard of `Findings` removed (it runs on a not-checked run) -> Runs TestFindingsRule row 8, TestNotCheckedReportsNothing red.
- mutation: the sends happen when no row was updated (before the `ROWCOUNT` Quit) -> Runs TestDeletedMeanwhileSendsNothing red.
- mutation: a failed send resets `Reported` (drops its finding) -> Runs TestFailedSendIsNeverRetried (sent again) red.
- mutation: SuperSession not set for the send -> Runs TestStoppedIsReportedOnce (superSession) and TestDisabledItemsAreReportedOnce red.
- mutation: Provenance `user` on the stop Item and an empty `CatalogKey` on the disabled Item (fresh, one run) -> Heartbeat TestStoppedProductionIsReportedOnce (no ItemDecision: Intake refuses) and TestDisabledItemIsReportedOnce (not the itemDisabled card) red.
- mutation: `Reader` `disabled` always `[]` -> Test.Watch.Reader TestDisabledItems red (warm) and Heartbeat TestDisabledItemIsReportedOnce (no Item) red (fresh).
- mutation: the start check dropped (`Set notRunning = 0`) -> Fix.Executor TestProductionNotRunningCannotStart (stopped, suspended, network_stopped) red (warm) and Fix.Runs TestStoppedProductionCannotStart red (fresh).
- mutation: the check uses `state '= "running"` -> Fix.Executor TestProductionNotRunningCannotStart (troubled, timeout, none, throw go on to the re-check) red.
- mutation: `Mark.Start` ignores `markAt` -> Runs TestWindow red; and the old expectation (the held `row.LastRunAt` re-read after the second Tick) with the `Hang 1.1` -> TestWindow red on the run.
- mutation: the Tables entry lacks `Reported` -> Test.Data.Tables TestContracts red.
- mutation: the `Catch` of `Record`'s send loop answers OK (a send that throws logs nothing) -> Runs TestThrownSendIsNeverRetried (the warning and the Ref in it) red.
- mutation: the findings gate also requires `'unread` (an incident read that fails reports nothing) -> Runs TestNotCheckedReportsNothing (the item read as disabled) red.

**Verification run (implement stage, tags e30s4i and e30s4iw; all torn down).**
- (loop) warm: Watch.Reader 3 s, Checks.Runs 1.3 s, Fix.Executor 29 s, Data.Tables 0.2 s; fresh: Checks.Heartbeat 3.9 s (stack 105 s), Fix.Runs 60.9 s (stack 90 s). All passed, run again after the review patches.
- (once) `bash ci/checks.sh` passed (3 min 24 s); `bash docker/tests/test-mock.sh` passed (0 failures).
- (once) `shard lane-a --part k/6` fresh: 1/6 451 s, 2/6 160 s, 3/6 261 s, 4/6 477 s, 5/6 264 s, 6/6 347 s, all passed.
- (once) `shard lane-b`: part 1/2 266 s passed; part 2/2 first run 540 s with one red, `Test.Web.GuideApi.TestRunAgain` ("steps 3 to 5 reset; the watch still counts", not in this story's area; green alone and green on the one rerun of the part, 558 s). A new flake, to be ledgered by the lead (not on the known list).

## Auto Run Result

Status: done
Blocking condition: none

**Implement stage (Story 30.4).**
- Summary: Checks now reports a newly stopped production and each newly disabled item once, as an `untrusted` Item to `Intake`, with "new" kept in the appended `BackgroundCheck.Reported` column (written in the run's `UPDATE`; a first run is a baseline). `Watch.Reader.Failures` gained the trailing outputs `disabled` and `stoppedAt`. `FixExecutor` ends a run whose production is stopped, suspended or network_stopped as couldn't start (`NOTRUNNING`, Resent 0, Skipped 0, row `failed`) before the re-check. DW-414 fixed in `TestWindow`.
- Files changed: `Data/BackgroundCheck.cls` (Reported, slot 15), `Watch/Reader.cls`, `Checks/Process.cls` (Findings, FindingItem, SendFinding, Record), `Fix/Executor.cls` (NOTRUNNING, NotRunning, ProductionState), new `ci/mock/scenarios/A/check-finding-tell-now.json`; tests: `Test/Checks/{Probe,Runs,Heartbeat}.cls`, `Test/Watch/{Case,Reader}.cls`, `Test/Fix/{Executor,ExecutorProbe,Runs}.cls`, `Test/Data/Tables.cls`.
- Files outside "Ours" (footprint_extensions): `Data/BackgroundCheck.cls`, `Watch/Reader.cls`, `Test/Data/Tables.cls` (own entry), the new mock scenario. No contended file, no Lane B class, no `Install/**`, spine untouched.
- Review: 25 triage rows. Patched 3 (VG1 thrown-send test, medium; VG2 incident-read-fails case, low; BH4/BH5 duplicated item helpers moved to `Test.Watch.Case` and the helpers marker, low). Deferred: none. Rejected with reasons: see the Review Triage Log (non-object `Reported`, Reader side-query failure, notice/newline in names, double send, caps, spec-decided cases).
- Follow-up review recommended: false (one medium patched, a test).
- Verification: see "Verification run" above; every mutation line demonstrated red and reverted byte-identically.
- Residual risks: the disabled item's `{time}` is the run time (V4, up to 60 s late); the `Test.Web.GuideApi.TestRunAgain` flake seen once in `lane-b` part 2/2 (green on rerun).

**Plan stage (halted after planning, as dispatched).**
- The spec passed the READY FOR DEVELOPMENT gate on the first check, after one in-place clarification of when `Findings` runs.
- Items for the lead's spec gate:
  - V1: the appended `BackgroundCheck.Reported` column, a stored-data change.
  - V2: the finding Item's Text, which the page shows as the decision row's title.
  - V3: `Fix.Executor.NOTRUNNING`, "the production isn't running".
  - V4: the `{time}` slot. It is IRIS's stop time for a stopped production; for a disabled item, and when IRIS recorded none, it is the time the check found the change.
  - Spine note (Rule 20): the Conventions "Background checks" row, AD-18 and AD-3.
- No contended edit, and no Lane B, Epic 9 or `Install/**` file.
- Files outside "Ours": `Data/BackgroundCheck.cls`, `Watch/Reader.cls`, `Test/Data/Tables.cls` (own entry), and the new `ci/mock/scenarios/A/check-finding-tell-now.json`.
- Measured read-only on slot A (build 154, port 52790): DW-414's cause. A second `%OpenId` in a process returns the same OREF, so `Record`'s `%Reload` rewrites the test's row object.
- The CI log of run 40975637263 (job 123802857844) shows the failing value `2026-10-29 23:59:24.000` at 23:59:27Z.
- Planning used no throwaway stack. Nothing was committed.
