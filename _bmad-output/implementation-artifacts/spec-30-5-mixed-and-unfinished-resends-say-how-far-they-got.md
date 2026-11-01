---
title: 'Mixed and unfinished resends say how far they got'
type: 'feature'
created: '2026-10-30'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A fix run that is still waiting for its copies when FixExecutor's 60-second wait ends is dropped without a word: nothing is sent, and Sweep never ends it, because Sweep leaves alone a run whose last copy finished after the wait. A resend that errs partway (the production stops, refuses a copy, or an error is thrown) counts the targets it never reached as Skipped, so its result reads "had changed since the dry run", which is false (DW-419, AD-16 as amended for U-160). An approved Execute that arrives after the row's ExpiresAt is refused with an info line only, so its incident stays `fixing` with no result (DW-384, U-161). The mixed result exists, but its notification's slots lack `resent`, and no test drives it end to end.

**Approach:**
- When the wait ends with copies still running, the waiter sends one in-progress `FixResult` (`Final` 0) with the counts so far, and the result notification reads `result.stillResending`. Sweep then ends every run past its wait once all its copies are done, and Checks sends that final result on as today.
- A resend stops at the first copy that errs. With no copy made, the run ends as couldn't start. Otherwise the run records the targets it never reached in a new `Unreached` count, and its result reads a new key, `result.stoppedPartway`.
- A past-expiry approved Execute ends as couldn't start, with the reason `NOSTART`.
- The mixed result's slots gain `resent`.

## Boundaries & Constraints

**Always:**
- A result's text never claims a change that did not happen. "Had changed since the dry run" is only for a target that really changed (AD-16, owner rule). A result never reads all-through while a target was left out.
- Each run gets exactly one final `FixResult`, and at most one in-progress one. `End` and `Mark` stay the only writers of a run's end fields, under `RUNLOCK` (AD-33).
- Every producer picks the result key in one order, `Notice.ResultKey` (Conventions "Result texts").
- Producers never render (AD-32). The FixResult goes in the incident's trace session (AD-26).
- `Resend` stays the only namespace switch, and it calls no OcuTalon class in the production's namespace (AD-3).
- Persistent and message classes are append-only, and their Storage blocks stay, with the compiler's new slots written back verbatim (AD-5).
- Originals are never changed, and a copy is never retried without a new approval.

**Never:**
- Never edit a Lane B class or file: `web/**` (except DW-500's fallback, ruling G-DW500 below), `Core.*`, `Data/Session.cls`, or any `Live.Payload.*` class other than `Live/Payload/Incident.cls` (U-183, ruling G1b).
- Never edit `Watch/FailurePoller.cls`, `Ops.cls` or `EvidencePack.cls`. `Watch/IncidentManager.cls` takes only the one-line in-place edit to `Result()` (Q1, ruling G3).
- Never edit `Install/**` or `Production.cls`, add a setting, or change the bridge (`Approval.*`).
- Never send a progress result from a read of the copies that did not succeed, or for a marked run or a row that is no longer executing.
- Never change the texts of the existing result keys or reasons. Never write an audit entry for a progress result.
- Never run these tests on slot A: load and compile only.

## I/O & Edge-Case Matrix

The counts are written `Total|Resent|Completed|FailedAgain|Skipped`. "Probe" means `Test.Fix.ExecutorProbe` (WAITSECONDS 3) or `Test.Fix.RunProbe`.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Mixed result (AC 1, live) | R1 over 5 failed orders. Before approval, its FixParameters are `Partial.FAILAGAIN` and two of the orders are rewritten so that the re-check skips them | One final FixResult `5\|3\|0\|3\|2`, Unreached 0, Reason "the order date still wasn't accepted"; the FixRun holds the same. The incident is resolved, and its event and `/state` list R1 `done` with that result. One result Notification, `result.failedAndSkipped`, with slots count 5, itemNoun, completed 0, failedAgain 3, failReason, skipped 2 and resent 3. It renders "0 of 5 orders went through. 3 failed again (the order date still wasn't accepted), and 2 had changed since the dry run, so I skipped them. I won't retry any of them without a new approval." | -- |
| 2 | Still running when the wait ends (AC 2, probe) | 3 copies Queued until the wait ends | One LOGWAIT warning, as today, and one FixResult with `Final` 0, Interrupted 0, `3\|3\|0\|0\|0`, Unreached 0 and Reason "", in the incident's trace session. No Action entry. The FixRun has no EndedAt and no counts, and the row stays `executing`. A later `WaitNow` sends nothing more | -- |
| 3 | Counts so far (probe) | At the last look before the drop, 1 copy Completed, 1 Error, 1 Queued | The progress FixResult is `3\|3\|1\|1\|0` | -- |
| 4 | No progress without a read (probe) | Every look is `unreadable`, or throws | The warning only (and one LOGLOOK for a throw), no FixResult, as today | -- |
| 5 | No progress for a run that moved on (probe) | At the drop, the run is marked, or its row is no longer executing | No FixResult | -- |
| 6 | In progress, then final (AC 2, live, Integration) | OrdersFromPartner stopped (`TempStopItem`) before R1 is approved over 3 orders | After the 60 s: FixExecutor sends IncidentManager one FixResult with `Final` 0, `3\|3\|0\|0\|0`. The incident stays `fixing`. [contended] Its owner gets one result Notification `result.stillResending`: "Still resending: 0 of 3 orders have gone through so far. I'll tell you when it's done." Then OrdersFromPartner starts, the copies complete, and the next Tick runs: Checks sends one FixResult with `Final` 1, `3\|3\|3\|0\|0`. The incident is resolved, with one `result.allThrough` Notification, "All 3 orders went through." In all, one final FixResult and one Action entry `done` | -- |
| 7 | Sweep ends a run reported in progress (probe) | Unmarked run, ResentAt 100 s ago, row executing, every copy done, the last one at ResentAt + 70 (or with no time) | Ended `done` with its counts. Its final FixResult is returned, and one Action entry `done` is written | -- |
| 8 | Sweep still leaves (probe) | Inside its wait; a copy still running; no ResentAt; the row not executing; the read not `read` | Left alone, as today | -- |
| 9 | Progress notice (IncidentManager, contended) | A `fixing` incident, then a FixResult with `Final` 0 | One result Notification `result.stillResending` per recipient (count, itemNoun, completed). The incident stays `fixing`. With the row already `done` when the result is handled, the key is still `stillResending`. A progress result on an incident that is not `fixing` is refused and sends none | -- |
| 10 | DW-384 (probe) | An approved fix row past its ExpiresAt. Also: StartExecution fails and the row reads approved and past its expiry | Couldn't start: one FixRun with no copy, the row `failed` (Result failed), one FixResult `n\|0\|0\|0\|0` with `Final` 1 and Reason `NOSTART`, and one Action entry `failed`. Check and Carry are never called. Pending, rejected, expired, cancelled, executing, tool_call and unknown rows are still refused with one info line | -- |
| 11 | DW-384 (live) | A `fixing` incident whose RequestRefs name R, which is approved with ExpiresAt 2020. An Execute for R goes to the real FixExecutor | R is `failed`. It has one FixRun with no copy and one FixResult (`3\|0\|0\|0\|0`, `NOSTART`). The incident is resolved, with one `result.couldNotStart` Notification: "Nothing was resent: OcuTalon couldn't start the resend. Nothing was changed." One Action entry `failed`, and nothing in OCUORDERS changed | -- |
| 12 | Resend stops where it errs (DW-419, live, direct `Resend`) | Orders stopped. The plan is [a header that is gone, a valid entry, a valid entry] | resent 0. skipped holds the gone one. unreached is [{id2, `stopped`}, {id3, `after`}]: entry 3 is never tried. No header is made, and OCUORDERS is unchanged. With Orders running and Task 0a's refusal: [valid, refused, valid] gives resent 1 and unreached [{`refused`}, {`after`}] | -- |
| 13 | Partway, no copy (probe) | A Carry with copies 0 whose first unreached code is `stopped`. Also: one real skip besides; the first code `refused` or `error`; `StateIs` `timeout` with that Carry (30.4's occurrence) | Couldn't start, the row `failed`, `n\|0\|0\|0\|0`. The Reason is `NOTRUNNING` for `stopped`, else `NOSTART`. A throw before any copy stays `NOREAD` | -- |
| 14 | Partway, with copies (probe) | 3 targets: 2 copies Completed, 1 unreached (`stopped`) | One LOGPARTWAY warning. Ends `done`, `3\|2\|2\|0\|1`, Unreached 1, Reason "". Key `result.stoppedPartway`: "The resend stopped partway: 2 of 3 orders went through. The other one needs a new approval." Never `result.skipped` | -- |
| 15 | Partway, mixed (probe) | 5 targets: 3 copies (2 Completed, 1 Error), 1 real skip, 1 unreached. Also: Carry throws after 2 of 3 copies | `5\|3\|2\|1\|2`, Unreached 1, Reason the fail reason, giving "... 2 of 5 orders went through. The other 3 need a new approval." The throw gives `3\|2\|2\|0\|1`, Unreached 1, and `stoppedPartway` | -- |
| 16 | Unreached travels (probe) | Sweep's EndLeft of a run whose FixRun has Unreached 1; the progress of such a run | Both FixResults carry Unreached 1. The final reads `stoppedPartway` | -- |
| 17 | Key order (pure) | `Notice.ResultKey` | First match wins: executing, or a result that is neither final nor interrupted, gives `stillResending`; Interrupted gives `interrupted`; nothing counted and a Reason gives `couldNotStart`; Unreached > 0 gives `stoppedPartway`; then `failedAndSkipped`, `failedAgain`, `skipped`, `allThrough`. `stoppedPartway`'s slots are count, itemNoun, completed and remaining (count less completed) | -- |
| 18 | Catalog | `result.stoppedPartway` on every channel; remaining 1 | The text of row 14. With remaining 1: "The other one needs a new approval." | -- |

## Spec-gate rulings (2026-11-01, re-plan; the lead, applying the orchestrator's and the Contest Planner's rulings)

This spec was planned on 2026-10-30, before these rulings and before Story 30.5's `epics.md` block gained DW-500, DW-519 and DW-484's note. The re-plan keeps the intent above and adds the following. Where they disagree with a row or a line above, these win.

**G0. Order.** DW-500 is the demo launch's visible fix: plan it, and let the implement stage build it, first among this story's items.

**G-DW500 (WIDENED; Contest Planner under the owner's delegation, 2026-11-01; `epics.md` Story 30.5).** On ANY user chat turn (the always-answered Tell-now override, AD-28), Triage's reasons never describe production state, what Triage can or cannot access, or whether anything needs the user. They only classify the turn as the user's own message, which is always answered (for example "A question from the user; the user is answered directly"). Seen on the host with real Haiku: under chip 2 the reasons made a model-written all-clear ("…there is nothing that needs the user at this moment"); under chips 1, 3 and 4 they described Triage's tool limits ("I have no tools in this context and cannot look up production status…", "I have no access to earlier items or failure logs…", "I have no tools, so I can only classify an item…").
- **Preferred:** Triage's instructions (`Agent/Triage.cls`, Lane A). Add evaluation cases on the mock for all four "Try it yourself" chips' exact texts: "Which productions are running?", "Is anything wrong right now?", "What was that failure earlier?", "What can you do?" (their chat scenarios are `ci/mock/scenarios/B/try-it-*.json`). The cases pin the rule above (no production state, no tool limits, no all-clear; the reasons classify the turn as the user's own message).
- **Fallback, only if the decision payload already marks the override** (no change to `web/src/app/api/api-types.ts` or `web/src/app/live/live-store.ts`, which are Epic 11's): with the override, the decision strip shows only the override line and the reasons move into Decision details (`web/src/app/chat/decision-strip.ts`, `decision-view.ts`, now free), pinned by a web unit test.
- Record under Design Notes which one was built. The Contest Planner checks real Haiku's wording on the host after the merge. Never edit `Agent/Chat.cls` (Epic 11's).
- Not this story's: chip 1's missing running state (DW-541, routed to Story 30.1).

**G-DW519.** Make `WatchAnswers.WatchNames` and the catalog's ET time-slot rule shared (callable), and call them from `Tools.RecentActivity` instead of its copies (`RecentActivity.WatchNames`, `RecentActivity.Shown`; Story 5.13's), so `recent_activity`'s display names and time labels never drift from the cards'. Keep every existing test of `recent_activity` green.

**G-DW484 (narrow part, kept in 30.5 by the Contest Planner).** The chat's reminder reply carries the zone label, so a visitor elsewhere can tell which clock it is. Only the zone label on the chat's reminder reply; the rest of DW-484 is not this story's. If the only place to add it is a path another in-flight epic owns (`Agent/Chat.cls`, `Tools/ReminderTools.cls`, `Test/Tools/Reminders.cls`, `Test/Schedule/ReminderChat.cls` are Epic 11's), HALT with an intent gap that names the file, rather than editing it.

**G-DW469 (U-180's condition).** The `{time}` of a `watch.productionStopped` or `watch.itemDisabled` notice renders through the catalog's time format with the zone label, for both time sources; a test pins it.

**G1. U-182 (`apply U-182 at=2026-10-31T06:23:40Z#553`).** Keep the AD-16 extension: `Unreached`, stop at the first copy that errs, none-went as couldn't-start, `result.stoppedPartway`. It is now written in the spine (AD-16, "A resend that errs partway stops at the first copy that errs", `[AMENDED 2026-11-01, Story 30.5, orchestrator ruling U-182]`). Condition: the `result.stoppedPartway` text gives the three counts (resent, the copy that erred, not tried) and says that nothing else was changed, and a test pins a run that stops partway at copy k of n. Rows 14, 15 and 18 above are re-worded to meet it (their earlier text "The other one needs a new approval" lacks the three counts).

**G1b. U-183 (`apply U-183 at=2026-10-31T06:23:40Z#554`).** Keep the routing. For this story: `unreached` on `Live.Payload.Incident` (`src/ocutalon/cls/OcuTalon/Live/Payload/Incident.cls`, in this epic's footprint; append-only, per AD-5's Storage rule where it applies), the `result.stoppedPartway` text and its count-of-one form in `Msg/Catalog/Watch.cls`, and the chat notice using it. The page's result pick is DW-472/DW-473 for Story 31.2: don't touch it (no `web/**` change for this).

**G3. Q1 (decided).** The one-line in-place edit to `Watch/IncidentManager.cls`'s `Result()` is allowed. No split.

**G4. The README sentence (the owner's).** Append "It also tells you once when a production stops or one of its items is disabled." to the second item of "What you can use it for" in `README.md`. Keep `docker/tests/test-readme.sh` green; update its `use-cases` pin if it pins that text.

**G5. Also in scope, unchanged:** DW-384 and DW-419, as the rows above plan them.

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `web/`, `ci/` or `_bmad`.

**The executor** (`Fix/Executor.cls`)
- `:3-61` class doc: items 1, 4 and 5, "A run that resent nothing", the wait, and "Story 30.5 reports it in progress".
- Parameters:
  - `:77` NOSTART and `:82` NOTRUNNING, the reasons a partway run with no copy reuses;
  - `:112` LOGWAIT; add LOGPARTWAY beside it.
- `:189-222` Execute:
  - the Refusal call is at `:193`;
  - the StartExecution-failure branch at `:212-218` still requires "not past its expiry" (DW-384).
- `:231-238` Refusal: `:236` refuses a past-expiry approved row (DW-384).
- `:302-353` Run:
  - the Carry result is read at `:318-324`;
  - the throw is caught at `:327`;
  - a throw with copies 0 ends `NOREAD` at `:337-339`;
  - ResentAt is saved at `:343-344`;
  - the all-skipped end is at `:352`.
- `:379-394` CouldNotStart(row, total, reason, saved): reuse it for DW-384 and for a partway run with no copy.
- `:410-425` Finish. `:569-585` Report and `:589-603` ResultOf: extend both with `final` (default 1) and set Unreached.
- `:606-618` FirstReason.
- `:677-711` Pass:
  - `last(id)` holds the running count;
  - the drop and its LOGWAIT are at `:701-710`.
- `:715-730` Look: its counts are at `:728`, where Skipped is total - resent.
- `:735-765` Tally: `lastAt` is read only by `Run.EndLeft`; remove it when nothing else reads it.
- `:855-928` Resend:
  - the codes are at `:870-909`;
  - every non-sent entry is pushed to skipped at `:926`;
  - `refused` and `error` log LOGCOPY at `:923-925`.
- `:931-943` SkipReason.

**Around it**
- `Fix/Kind/RepairResend.cls:219-233` Execute: it merges Resend's skipped into `result.skipped`. Pass `unreached` through.
- `Fix/Run.cls`:
  - `:3-29` doc;
  - `:154-185` EndMarked (its counts are at `:180`);
  - `:188-224` EndLeft (the `lastAt < due` gate is at `:207`, its counts at `:211`);
  - `:236` LOGSWEPT.
- `Fix/Msg/FixResult.cls`: properties, Storage slots 1-10.
- `Data/FixRun.cls`: properties, doc, Storage slots 1-14 (`^OcuTalonP.FixRunD`).
- `Watch/Notice.cls`:
  - `:19-30` doc;
  - `:59-72` the result keys;
  - `:176-187` ResultKey;
  - `:191-229` ResultSlots (the list of keys at `:203`, interrupted's remaining at `:227`).
- `Msg/Catalog/Watch.cls:192-207` failedAndSkipped, `:221-234` interrupted (the shape to copy), `:235-241` couldNotStart.
- `Checks/Process.cls:189-228` Fixes and its SendFixResult seam: unchanged. It already sends every result Sweep returns, in the incident's trace session.

**Contended** (`Watch/IncidentManager.cls`, Epic 9)
- `:1164-1174` Result: `:1173` builds a notice only when `final`.
- `:1179-1189` ResultNotice. The docs that need updating are at `:66-69`, `:1162-1163` and `:1176`.
- `Watch/Transitions.cls`' row `fixing,*,progress → fixing` already accepts a progress result.

**Lane B, read only** (needs recorded under Design Notes)
- `Live/Payload/Incident.cls:141-151` fills a request's Result only from an ended FixRun.
- `web/src/app/approvals/approval-view.ts:351-398` resultView.
- `web/scripts/catalog.mjs:51-89` the allowlist of page keys: a new key not on the list leaves `catalog.ts` unchanged.

**Tests and helpers**
- `Test/Fix/ExecutorProbe.cls`:
  - `:117` SendResult records `final` (add `unreached`);
  - `:282` Carry, whose canned `{copies, skipped, fail}` gains `unreached`;
  - `:159` Statuses;
  - `:258` StateIs.
- `Test/Fix/RunProbe.cls`: Feed, Narrow, FailClose.
- `Test/Fix/Executor.cls`:
  - `:188-233` TestRefusedStates (the past-expiry case is at `:207-209`);
  - `:505-537` TestNothingResent (its case 2 cans every copy "stopped");
  - `:679-700` TestRunThatErredAfterACopyStillWaits (`3|2|2|0|1`, "1 had changed");
  - `:702-764` TestStillRunningAfterTheWait (it asserts no Results at `:726`);
  - `:1044-1083` TestStartExecutionFailsForAnApprovedRequest (its past-expiry case is at `:1066-1072`);
  - `:1455-1495` TestSweepEndsARunNoWaiterEnded;
  - `:1497-1544` TestSweepLeavesRunsOfTheWaiterAndOfStory305;
  - `:1546-1595` TestSweepDecidesByTheLatestCopyTime.
  - Helpers: `:1818` Host, `:1884` AssertEnded, `:1960` Render, `:2002` CarryJSON, `:2018` Canned, `:2178` UnmarkedRun, `:2238` CannedAt, `:2246` Stamp.
- `Test/Fix/Recheck.cls:120-137`: the direct `Resend(..#ORDERS, plan, "", .copies, .refused)` call.
- `Test/Fix/Partial.cls`:
  - `:28` TestSomeHadChanged (the rewrite) and `:69` TestCopiesFailAgain (FAILAGAIN at `:26`);
  - `:167` WaitResultOf.
- `Test/Fix/Waits.cls:46-112`: the TempStopItem technique and MARGIN.
- `Test/Fix/Refused.cls`:
  - `:13-66` TestNoApprovedRowNoRun (its past-expiry case is at `:35-36`, the count of 7 per kind at `:65`);
  - `:68` Request.
- `Test/Watch/Case.cls`:
  - `:1589` Raised; `:1083` TempStopItem; `:1137` StopOrders;
  - `:680` Tick; `:1987` WaitResent; `:1999` WaitQueued; `:1772` WaitState; `:1789` WaitIncidentState;
  - `:1917` FixResultsFor; `:1960` WaitFixResults; `:1437` NoticeBodies; `:1973` WaitResultNotices; `:1497` ResultOf;
  - `:481` PutBack.
- `Test/Watch/Lifecycle.cls`:
  - `:449` TestResultNotices ("a progress report sends none" is at `:511-518`);
  - `:435-446` TestFixResults;
  - helpers `:1206` Finish, `:1220` Results and `:1250` AssertSent;
  - the probe is `Test/Watch/IncidentProbe.cls` (SendNotice records to Sent).
- `Test/Watch/NoticeText.cls:340-372` TestResultKeys, `:411-420` TestRestartAndResendTexts.
- `Test/Msg/Catalog.cls`:
  - `:3` doc (22 Watch keys, 8 one forms);
  - `:82-83`, `:121` (116 keys), `:553-554` (8 one forms);
  - XData Keys `:952`, OneForms `:1088` and Fixtures (around `:1300`).
- `Test/Data/Tables.cls:581-600`: our own FixRun entry.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 -- on a fresh throwaway (`e30s5i`), measure and record under "Measured at implementation":
  - (a) In OCUORDERS, with Orders running, `Ens.MessageHeader.ResendDuplicatedMessage` for an Error header of a test order whose `TargetConfigName` the test has set to a name that is no item of the production: its status, and whether `newId` is set. If the call gives an error with no `newId`, row 12's refused case is built with it. Otherwise the refused case is dropped and the gap is recorded.
  - (b) After `StopOrders`, the same call gives `ErrProductionNotRunning`, with no `newId` and no new header (S8, again).
- [ ] `Data/FixRun.cls` -- `Property Unreached As %Integer` after `Reason`. Doc: "The targets of the request that the run never reached: not resent because the resend stopped where a copy erred (the production stopped or refused it, or an error), counted among Skipped; written by Run with ResentAt, empty for a run that made no copy." Keep the Storage block. Write back the compiled `<Value name="15">` verbatim. Update the class doc -- V1, DW-419.
- [ ] `Fix/Msg/FixResult.cls` -- add `Property Unreached As %Integer` after `Reason`, with its doc ("of Skipped, the targets the run never reached"). Write back slot 11 verbatim. Update the class doc: a progress report is sent once, when the wait ends with copies running -- V2.
- [ ] `Fix/Executor.cls` -- DW-419, Resend:
  - Add a trailing `Output unreached As %DynamicArray`.
  - At the first entry whose code is `stopped`, `refused` or `error`, push `{"id", "code"}` and stop the loop. Every later entry is pushed as `{"id", "code": "after"}` without being tried.
  - The real skips (`gone`, `status`, `body`, `field`, `changed`) still go to `skipped` and the loop goes on. Existing callers keep working.
  - Update the doc -- DW-419, V4.
- [ ] `Fix/Kind/RepairResend.cls` -- Execute's result gains `"unreached"` (Resend's; `[]` when nothing was planned). Update the doc.
- [ ] `Fix/Executor.cls` -- DW-419, Run:
  - unreached is the Carry result's `unreached`. After a throw with copies > 0, it is the passed targets less the copies, the throw still logs LOGRECHECK as today, and LOGPARTWAY names the first passed target without a copy.
  - With copies 0 and unreached > 0: `CouldNotStart(row, total, reason, 1)`, where the reason is NOTRUNNING when the first code is `stopped`, else NOSTART (row 13). A throw with copies 0 stays NOREAD.
  - With copies > 0: `run.Unreached` is saved in the same save as ResentAt. When unreached > 0, log one Type 3 warning, `LOGPARTWAY` ("FixExecutor stopped the resend of request <ref> at message <id>: <reason>; <n> of <total> targets were not reached", redacted).
  - Look's counts gain `unreached` (`+run.Unreached`). Skipped stays total - resent.
  - ResultOf sets `Unreached`.
- [ ] `Fix/Executor.cls` -- AC 2, the progress:
  - `Look(id, Output tally)` gives the tally of a read that was read. Pass keeps the last such tally (completed, failedAgain) beside `last(id)`.
  - At the drop: when the run has no EndedAt, Interrupted 0, its row is executing, its time is up and Pass kept a tally, `Report(row, counts, 0)` with `{total, resent: copies, completed, failedAgain, skipped: total - resent, unreached, reason: ""}`. LOGWAIT stays. Nothing is stored and no entry is written (rows 2-5).
  - `ResultOf(row, counts, final As %Boolean = 1)` and `Report(row, counts, final As %Boolean = 1)`.
- [ ] `Fix/Executor.cls` -- DW-384:
  - Refusal no longer refuses an approved fix row past its expiry.
  - Execute, right after Refusal: an approved row with `'(ExpiresAt ] now)` gives `CouldNotStart(row, total, ..#NOSTART, 0)`.
  - The StartExecution-failure branch ends any row that still reads approved with NOSTART, past its expiry or not.
  - Update the class doc (items 1, 4 and 5, the wait, and "A run that resent nothing") -- DW-384, AD-16.
- [ ] `Fix/Run.cls` -- EndLeft drops the `lastAt` gate: an unmarked run past its wait, with its row executing, a read of `read` and no copy running, ends `done` whenever its last copy was done (row 7). Its counts and EndMarked's gain `unreached` (`+run.Unreached`). Remove `Tally.lastAt` if nothing else reads it. Update the doc -- AC 2, DW-419.
- [ ] `Watch/Notice.cls`:
  - `Parameter KEYPARTWAY = "result.stoppedPartway"`.
  - ResultKey: `stillResending` also for a result that is neither Final nor Interrupted, and `stoppedPartway` for `+result.Unreached > 0` after couldNotStart (row 17).
  - ResultSlots: `stoppedPartway` takes interrupted's slots (count, itemNoun, completed, remaining), and `failedAndSkipped` adds `resent` (`+result.Resent`), which the catalog ignores (`Test.Msg.Catalog.TestExtraSlots`).
  - Update the doc -- AC 1, AC 2, DW-419.
- [ ] `Msg/Catalog/Watch.cls` -- `result.stoppedPartway`, per Design Notes V3 (text, slots, one form on remaining, source) -- V3.
- [ ] CONTENDED, only after the orchestrator's ruling: `Watch/IncidentManager.cls` -- in Result `:1173`, pass `..ResultNotice(incident, row, result)` for every owned result, the progress one included, and update the docs at `:66-69`, `:1162-1163` and `:1176` -- AC 2 (row 9).
- [ ] `Test/Fix/ExecutorProbe.cls` -- Carry's canned JSON takes `unreached` (`[{id, code}]`), and SendResult records `unreached`. Update the doc.
- [ ] `Test/Fix/Executor.cls`:
  - TestRefusedStates loses its past-expiry case.
  - New TestPastExpiryCannotStart (row 10).
  - TestStartExecutionFailsForAnApprovedRequest: its past-expiry case moves to the NOSTART end.
  - TestNothingResent case 2 becomes couldn't start `NOTRUNNING`.
  - TestRunThatErredAfterACopyStillWaits gives `stoppedPartway`.
  - New TestResendThatErrsPartwaySaysHowFarItGot (rows 13-15, LOGPARTWAY).
  - TestStillRunningAfterTheWait asserts the progress (rows 2, 4), and a new case covers rows 3 and 5.
  - Sweep: TestSweepLeavesRunsOfTheWaiterAndOfStory305 becomes TestSweepLeavesRunsOfTheWaiter (row 8); TestSweepDecidesByTheLatestCopyTime becomes TestSweepEndsEveryRunWhoseCopiesAreDone (row 7); add a case for row 16. Pin AD-16 and DW-419 in the docs.
- [ ] `Test/Fix/Recheck.cls` -- TestResendStopsWhereItErrs (row 12, Task 0a). Orders is started again after it, also after a failure (`PutBack`).
- [ ] `Test/Fix/Partial.cls` -- TestSomeFailAgainAndSomeHadChanged (row 1). Update the doc.
- [ ] `Test/Fix/Waits.cls` -- TestStillRunningIsReportedThenEnded (row 6). The stillResending Notification assertion is one block, which moves if the contended edit is split off. Update the doc.
- [ ] `Test/Fix/Refused.cls` -- TestNoApprovedRowNoRun drops "past expiry" (6 rows per kind). New TestPastExpiryCannotStart (row 11). Update the doc.
- [ ] `Test/Watch/NoticeText.cls` -- the rows of row 17, with the slots and texts of `stoppedPartway`. The `failedAndSkipped` slots include `resent`.
- [ ] `Test/Watch/Lifecycle.cls` -- TestResultNotices:
  - a final result with Unreached 1 sends `result.stoppedPartway` (Integration, not contended);
  - [contended] "a progress report sends none" becomes row 9.
- [ ] `Test/Msg/Catalog.cls` -- Keys (23 Watch keys, 117 in all), OneForms (9) and Fixtures for `result.stoppedPartway` (row 18), with the doc counts.
- [ ] `Test/Data/Tables.cls` -- our own FixRun entry gains `"Unreached": "%Integer"`.
- [ ] Every other test that asserts the old shapes: search `Test/` for `stillResending`, `Skipped`, `past expiry`, `lastAt` and `Resend(` and update them (Shared surfaces).

**Acceptance Criteria:**
- Given an approved repair in which some copies fail again and some targets are skipped, when FixExecutor sends its FixResult, then it carries both counts (Unreached 0), the run's stored result and the incident event's request result carry them as the incident resolves (AD-15), and the result notification uses `result.failedAndSkipped`, with the resent, completed, failed-again and skipped counts as slots (rows 1, 17; FR-8, FR-25, AD-16, AD-32).
- Given copies still running when FixExecutor's 60-second wait ends, when the wait ends, then FixExecutor sends one FixResult with `Final` 0 and the counts so far, the incident stays `fixing`, and the result notification uses `result.stillResending` [contended]; and once every registered copy has completed or failed, Checks' next Tick gets the run's final FixResult from `Fix.Run.Sweep()` and sends it to IncidentManager, which moves the incident by AD-15's table with the matching result text (rows 2-9; FR-25, AD-15, AD-16, AD-18).
- Given an approved request whose ExpiresAt has passed when FixExecutor takes its Execute, when it is handled, then it ends as couldn't start with `NOSTART`: the row is closed `failed`, one final FixResult goes out with every count 0, and the incident leaves `fixing` with "Nothing was resent: OcuTalon couldn't start the resend. Nothing was changed." (rows 10, 11; DW-384, AD-16 as amended, U-161).
- Given a resend that errs partway, when the run ends, then the targets it never reached are reported by how far it got: with no copy made, as couldn't start with a plain reason; otherwise, as `result.stoppedPartway` ("The resend stopped partway: {completed} of {count} {itemNoun} went through. The other {remaining} need a new approval."). No text says that they had changed since the dry run (rows 12-16, 18; DW-419, including 30.4's `timeout` occurrence; AD-16 as amended, U-160).

## Spec Change Log

- 2026-11-01 (lead, spec gate, re-plan): status reset to draft; the spec-gate rulings G0-G5 (DW-500 widened and first, DW-519, DW-484's narrow part, DW-469, U-182, U-183, Q1, the README sentence) added inside the intent block; the Never lines on Lane B and Epic 9 files changed to match U-183 and Q1. The AD-16 extension is written in the spine.

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6).**
- AD-16, as amended 2026-10-30:
  - U-161: a past-expiry Execute ends as couldn't start with `NOSTART`.
  - U-160: a resend that errs partway reports the targets it never reached by how far it got, and a result never claims a change.
  - A run still running after the wait is reported in progress, and then with its final result through Sweep.
  - Each run gets exactly one final FixResult.
- AD-15: the transition table. `fixing` plus progress stays `fixing`; `fixing` plus final goes to `resolved`.
- AD-18: Checks sends Sweep's final results on each Tick. It is unchanged.
- AD-32: producers never render. Keys and slots only.
- Conventions "Result texts": one key order for every producer.
- AD-33: one writer of a run's end, and Lane B's classes are read only.
- AD-26: the FixResult goes in the incident's trace session.
- AD-3: Resend's one switch.
- AD-5: append-only storage.
- AD-11: FinishExecution closes the row.
- AD-12: the payload is unchanged here (the Lane B need below).
- AD-2: no bridge change.
- AD-22: throwaway stacks.

**Contended edit:** `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls`.
- In `Result` (`:1173`), `$Select(final: ..ResultNotice(incident, row, result), 1: "")` becomes `..ResultNotice(incident, row, result)`. One code line.
- The docs of the class (`:66-69`), of Result (`:1162-1163`) and of ResultNotice (`:1176`) change about 4 lines, to say that a progress result gets `result.stillResending`.
- With `Notice.ResultKey`'s new progress rule (ours), that is all the in-progress notice needs.
- No design without it was found:
  - IncidentManager calls no Lane A hook for a progress result: `Event`, `Apply`, `Transitions.Next` and `Move`/`Tell` all carry notification "".
  - A notice sent by FixExecutor straight to Notify was rejected. It adds a FixExecutor → Notify path that the spine's incident flow ("FixExecutor → IncidentManager → Notify") does not have. It copies Tell's recipient fan-out (`Data.Session.Recipients`, Epic 29). And it would send even when the table refuses the progress (an incident not `fixing`).
- **Split:** everything else lands without the edit. Without it, the progress FixResult is still sent and accepted, and only the stillResending Notification is missing; the final result and its notice still follow.
  - So, if the orchestrator rules that the edit must wait for Epic 9, a sibling (Story 30.6, after Epic 9 merges) takes the edit, Lifecycle's row 9 assertion and the stillResending block of the Waits test, and this story lands the rest.
  - Moving that one clause of AC 2 is the lead's call (a veto item when it is an AC move).
  - Recommendation: keep it here if the orchestrator allows a one-line edit inside Epic 9's file, else split.

**V1. Stored data (veto window): `FixRun.Unreached`** (`%Integer`, slot 15), written by Run with ResentAt.
- The waiter and Sweep end the run in other jobs, later, so the count of the targets the run never reached must be stored when the copies are registered.
- **Rejected:**
  - (a) Making Skipped hold only the real changes and deriving the rest. The page's resultView (Lane B, unchanged) would then show "All N went through" for a partway run with no failure and no real skip: a false all-clear until Lane B changes the page.
  - (b) Reusing `Interrupted`. Its key says "when OcuTalon restarted", and a stored Interrupted above 0 marks a run for `End`/`Mark`.
  - (c) Counting the targets as FailedAgain. They were never resent, so "failed again" misstates what happened and breaks Completed + FailedAgain = Resent.
  - (d) Storing the stop reason as well (a second column).
- **Recommendation:** add it. Skipped keeps its meaning (the targets left out, Total - Resent), so today's page shows a partway run as it does now, never as all-through.

**V2. Stored data and AD-16's message contract (veto window): `FixResult.Unreached`** (`%Integer`, slot 11).
- IncidentManager picks the key from the FixResult (`Notice.ResultKey` is pure), and Skipped is inclusive, so the subset cannot be derived.
- AD-16's list of FixResult's properties gains it: an addition in the sense of the Rule's "reports the targets it never reached", for the lead under U7.

**V3. Public text (veto window): `result.stoppedPartway`.**
- Text: "The resend stopped partway: {completed} of {count} {itemNoun} went through. The other {remaining} need a new approval."
- Slots: count, itemNoun (noun), completed and remaining.
- One form, on `remaining` = 1: "The resend stopped partway: {completed} of {count} {itemNoun} went through. The other one needs a new approval."
- Source: "Story 30.5 (AD-16 as amended, U-160), in the form of EXPERIENCE Incidents and Approvals / Results / Cut off by a restart".
- It folds the failed-again and skipped targets into "the other {remaining}", as `result.interrupted` does, and claims no change and no cause it does not know.
- **Alternatives:**
  - With a reason: "The resend stopped partway: {reason}. {completed} of {count} ...". This needs the stop reason stored (a second column) and a new reason sentence for a refusal or an error. The production-stopped case is already told to the user by 30.4's check finding.
  - The word "didn't finish" in place of "stopped partway".
- **Recommendation:** as written. EXPERIENCE.md's Results table gains a "Stopped partway" row with the ruling (UX note for the lead).

**V4. A claim about what the product does (veto window): the resend stops at the first copy that errs** (`stopped`, `refused` or `error`) instead of trying the rest.
- It makes "stopped partway" literally true and "never reached" literal (AD-16's wording).
- It is the safe choice (product default 3): no more copies go out after an unexpected error.
- The real skips still go on.
- **Recommendation:** keep it.

**Decided in-stage.**
- **No copy made** means couldn't start: the row is `failed`, every count is 0, and the reason is `NOTRUNNING` for a stop or `NOSTART` for a refusal or an error. A throw before the first copy stays `NOREAD`. This matches AD-16's couldn't-start shape and the existing "an error before any copy" rule, and it uses existing texts only.
- **The progress** is sent once, by the waiter, when it drops a run whose time is up. It is sent only for an unmarked run whose row is executing and whose copies were read at least once in the wait. The counts are from the last read, at most WAITPAUSE old. It writes no audit entry and stores nothing, and LOGWAIT stays.
- A run whose waiter was stopped (DW-395) gets no progress, only its final result.
- The progress's count slot is Total, as the UX text has it: "30 of 50 have gone through so far" is true even when some targets were skipped or never reached, and the final result says the rest.
- **ResultKey** gives `stillResending` for any result that is neither final nor interrupted. This guards a progress that IncidentManager handles after Sweep has closed the row: it never renders a final text from partial counts.
- **Sweep** ends every unmarked run past its wait whose copies are all done, whenever the last copy was done. The `lastAt` gate only kept Story 30.5's branch open.
- **The mixed slots** add `resent`, which the catalog ignores (Render accepts extra slots), so that the AC's four counts are all in the Notification's Slots. The text is unchanged.
- **DW-384** goes through `CouldNotStart(…, 0)` with no gate beyond FinishExecution's locked approved → failed move, like UNUSABLE and NOTALLOWED. A second Execute for the row then finds it `failed` and is refused, and IncidentManager refuses a second final on a resolved incident.
- **The Action entry's counts are unchanged.** Skipped there includes the unreached targets, as the FixRun's does.
- **LOGPARTWAY** gives operators the reason the user text does not carry.

**Lane B needs (for the lead to route; not planned here).**
- (1) The page's `resultView` gains `unreached > 0 → result.stoppedPartway` after couldNotStart. `catalog.mjs` lists the key and its one form, and the payload's `IncidentRequestResult` gains `unreached` from `FixRun.Unreached`. The spine's ownership table gives `Live.Payload.Incident` to Lane A (its publisher), and the lead says Lane B: the lead decides which lane. Until then the page shows a partway run as it does today (`result.skipped`'s claim, on the page only), never as all-through.
- (2) The page has no in-progress band. A request whose run has not ended has no `result`, and the counts so far are stored nowhere.

**Spine notes for the lead (Rule 20).**
- Conventions "Result texts": after couldNotStart, `Unreached` > 0 gives `result.stoppedPartway`. A producer that holds a FixResult that is neither final nor interrupted gives `result.stillResending`. The payload's Result gains `unreached`.
- AD-16:
  - the FixResult's properties gain `Unreached`;
  - a resend that errs stops at that copy, and with no copy made it ends as couldn't start (`NOTRUNNING` or `NOSTART`);
  - FixRun records `Unreached` with ResentAt.

**Declined DW:** none. DW-384 is addressed in rows 10 and 11. DW-419, with 30.4's `timeout` occurrence, is addressed in rows 12-16.

**Integration ACs (Rule 1).**
- Row 6: the real IncidentManager reads FixExecutor's progress FixResult, keeps the incident `fixing` and sends `result.stillResending`. The real Checks then sends Sweep's final, and IncidentManager resolves the incident with `result.allThrough`.
- Row 1: the real IncidentManager reads the mixed FixResult and sends `result.failedAndSkipped`, and `/state` shows the request's result.
- Lifecycle (in-process `IncidentProbe`): a final with Unreached 1 gives `result.stoppedPartway`.

**Consumed-by:**
- IncidentManager (Story 5.5/7.3), through `Notice.ResultKey` and `ResultSlots`.
- Checks (Story 7.5), with Sweep's results.
- The page (Lane B), through need (1).
- Telegram's in-place result edit (Epic 12), which sees a progress notice followed by the final notice with the same ApprovalRef.

**Consumes:**
- `Watch.Reader.Evidence`, through `Executor.Read`.
- `Approval.FinishExecution` and `StartExecution` (3.x/7.3).
- `Watch.Transitions` (5.5).
- `Msg.Catalog.Render` (0.9).
- `Test.Watch.Case`'s live helpers.

**Extend, don't copy (Rule 2).**
- `ResultOf` and `Report` gain `final`; there is no progress builder.
- The progress reuses Tally and Report's trace session.
- DW-384 and a partway run with no copy reuse `CouldNotStart`.
- `stoppedPartway` reuses ResultSlots' interrupted branch and the catalog shape of `result.interrupted`.
- `Resend` gains a trailing output.
- The live tests reuse Case's helpers, Partial's `FAILAGAIN` and rewrite, and Waits' TempStopItem technique.
- The Refused live test reuses its `Request` helper.

**Files outside "Ours"** (`footprint_extensions`):
- `Data/FixRun.cls`: Lane A's table (AD-33).
- `Watch/Notice.cls` and `Fix/Kind/RepairResend.cls`: Lane A's, not contended.
- `Test/Msg/Catalog.cls`: the expectations for our Watch key.
- `Test/Data/Tables.cls`: our own entry.
- The contended `Watch/IncidentManager.cls`, only by ruling.

**Measured at planning.** Planning used no IRIS instance and no throwaway stack.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=30 stage=implement'`, run from the worktree root. The fresh tag is `e30s5i` and the warm tag `e30s5iw`.

How to run:
- One command per tool call, in the foreground, with `timeout: 600000`. Never two IRIS test runs in one message.
- The harness moves a call to the background after about 180 s. Poll it in loops of under 170 s, and never start a second copy.

Where to run:
- **Throwaway stacks only.** These tests stop Orders and OrdersFromPartner, approve fixes and resend copies.
- **Warm** for the in-process classes. **Fresh** for the classes that need the running production's FixExecutor, IncidentManager or Checks: a warm stack's jobs keep their old code.
- **On `ocutalon-slot-a`** (`server` `ocutalon-slot-a`, `namespace` `OCUTALON`, checked with `iris_server_info`, build 154), only load and compile the changed classes (`iris_doc_load`, `baseDir` `src/ocutalon/cls`). Then export the compiled Storage blocks of FixRun and FixResult back into the files.
- Tear down only your own tags, after a failure too.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e30s5iw ci/warm.sh up`, once. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e30s5iw ci/iris.sh class <Class>`, one call per class. Expected: `CLASS … passed`.
  - `OcuTalon.Test.Fix.Executor` (about 30 s)
  - `OcuTalon.Test.Watch.NoticeText`
  - `OcuTalon.Test.Watch.Lifecycle`
  - `OcuTalon.Test.Msg.Catalog`
  - `OcuTalon.Test.Data.Tables`
- (loop) `<lane> OCUTALON_RUN_TAG=e30s5i ci/iris.sh class <Class>`, fresh, one call per class. Expected: `CLASS … passed`.
  - `OcuTalon.Test.Fix.Recheck` (Task 0 first)
  - `OcuTalon.Test.Fix.Partial`
  - `OcuTalon.Test.Fix.Waits` (about 4 to 5 min with the stack)
  - `OcuTalon.Test.Fix.Refused`
  - `OcuTalon.Test.Fix.Stopped`
  - `OcuTalon.Test.Fix.Runs`
- (once) `bash ci/checks.sh`. Expected: every script passes, storage and class rules included.
- (once) `node web/scripts/catalog.mjs --check`. Expected: exit 0: the new key is not a page key, so `catalog.ts` is unchanged.
- (once) `<lane> OCUTALON_RUN_TAG=e30s5i ci/iris.sh shard lane-a --part k/6` for k = 1 to 6, fresh, one call each. Expected: passed, with each part's time recorded.
- (once) `<lane> OCUTALON_RUN_TAG=e30s5i ci/iris.sh shard lane-b --part 1/2`, then `--part 2/2`, fresh. Expected: passed (`Test.Msg.Catalog` and `Test.Data.Tables` run there).
- (once) `<lane> OCUTALON_RUN_TAG=e30s5iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e30s5i ci/iris.sh teardown`, also after a failure.

**Shared surfaces:**
- **FixRun's columns (+Unreached):** `Test.Data.Tables`' own entry. `Live.Payload.Incident` reads fixed columns and is unchanged.
- **FixResult (+Unreached):** `ExecutorProbe.SendResult`'s record. `Test.Checks.Probe.SendFixResult` is unchanged.
- **Watch catalog (+1 key, +1 one form):** `Test.Msg.Catalog` (Keys 22 → 23, 116 → 117, OneForms 8 → 9, Fixtures). The web allowlist is unchanged.
- **The result key order and slots:** `Test.Watch.NoticeText`, `Test.Watch.Lifecycle`. The page's resultView is Lane B's and unchanged (need 1).
- **Resend's outputs (+unreached) and its stop:** the direct calls in `Test.Fix.Recheck`.
- **Executor behaviour:**
  - the past expiry: `Test.Fix.Executor` TestRefusedStates and TestStartExecutionFailsForAnApprovedRequest, and `Test.Fix.Refused`;
  - the progress at the wait's end: TestStillRunningAfterTheWait;
  - the Sweep gate: the three Sweep tests;
  - an all-stopped Carry: TestNothingResent.
- **IncidentManager's progress notice (contended):** Lifecycle's "a progress report sends none".
- **CI time:** the new live tests run in `shards-2` (the Fix area). Expect about +3 to +5 minutes (inference) on its 23.
- Every test added or changed passes on a fresh environment, in either order. Orders and OrdersFromPartner, when a test stopped them, are started again after it, also after a failure (`Case.PutBack`, `TempStartItem`).

**Pinning mutations (Rule 19).** Apply each mutation, observe red, revert byte-identically (`git status --short` and `git diff --stat` unchanged), and record `mutation: … → …` here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1, row 1 | ResultSlots leaves out `resent` | NoticeText (the mixed slots); Partial row 1 (the slots) |
| AC 1, row 1 | Look's skipped is 0 | Partial row 1 (`result.failedAgain`, `5\|3\|0\|3\|0`) |
| AC 2, rows 2, 6 | the drop sends no progress | Executor TestStillRunningAfterTheWait; Waits row 6 (no `Final` 0 FixResult) |
| row 3 | the progress counts come from the first look, not the last | Executor row 3 |
| rows 4, 5 | the progress goes without a tally, or for a marked run | Executor rows 4, 5 |
| AC 2, rows 7, 6 | EndLeft keeps the `lastAt < due` gate | Executor row 7; Waits row 6 (no final after the Tick) |
| AC 2, row 9 | ResultKey without the progress rule (a `done` row) | NoticeText; Lifecycle row 9 |
| AC 2, row 9 [contended] | Result keeps `$Select(final: …, 1: "")` | Lifecycle row 9; Waits row 6 (no stillResending) |
| AC 3, rows 10, 11 | Refusal refuses a past expiry again | Executor TestPastExpiryCannotStart; Refused row 11 |
| AC 3, row 10 | the StartExecution-failure branch keeps "not past its expiry" | Executor TestStartExecutionFailsForAnApprovedRequest |
| AC 4, row 12 | Resend does not stop at `stopped` | Recheck row 12 (entry 3 tried, no `after`) |
| AC 4, row 13 | copies 0 with unreached ends `done` with Skipped | Executor rows 13 (and TestNothingResent) |
| AC 4, row 13 | the reason is NOSTART for `stopped` | Executor row 13 (`NOTRUNNING`) |
| AC 4, rows 14, 15 | Unreached is never saved, or ResultKey ignores it | Executor rows 14, 15 (`result.skipped`), 16 |
| AC 4, row 15 | after a throw, unreached is 0 | Executor row 15 (the throw case) |
| row 18 | the one form drops "one" | Test.Msg.Catalog (OneForms) |
| Storage | the Tables entry lacks `Unreached` | `Test.Data.Tables` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (halted after planning, as dispatched).**
- The spec covers Story 30.5's two ACs and DW-384 and DW-419, including 30.4's `timeout` occurrence. Nothing is declined.
- Items for the lead's spec gate:
  - **Contended edit:** `Watch/IncidentManager.cls` `Result` `:1173`: one code line and about 4 doc lines, for the in-progress notice. Everything else lands without it, and the split is described under Design Notes. For the orchestrator.
  - **V1:** `FixRun.Unreached`, a stored-data change.
  - **V2:** `FixResult.Unreached`, a stored-data change and an addition to AD-16's message contract (U7).
  - **V3:** the new public text `result.stoppedPartway` and its one form, plus a UX row in EXPERIENCE.md.
  - **V4:** the resend stops at the first copy that errs.
  - **Spine notes (Rule 20):** Conventions "Result texts" and AD-16.
  - **Lane B needs:** (1) the page's partway band and the payload's `unreached`; (2) the in-progress band.
- Files outside "Ours":
  - `Data/FixRun.cls`, `Watch/Notice.cls` and `Fix/Kind/RepairResend.cls`;
  - `Test/Msg/Catalog.cls` and `Test/Data/Tables.cls` (own entries);
  - the contended `Watch/IncidentManager.cls`, by ruling only.
- Planning used no IRIS instance and no throwaway stack. Nothing was committed.
