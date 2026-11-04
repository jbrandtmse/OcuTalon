---
title: 'Mixed and unfinished resends say how far they got'
type: 'feature'
created: '2026-10-30'
status: 'done'
review_loop_iteration: 0
baseline_revision: 'a0fce35a53ace6e64c9a511439476cfa8929b98d'
baseline_commit: 'a0fce35a53ace6e64c9a511439476cfa8929b98d'
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      The reminders list answer (CommandCall.Listed) shows each due time without the zone label on the online demo, while the set reply (Answer) now carries " ET".
    evidence: |-
      CommandCall.Listed builds `due` with Data.Time.ForMessage; Answer uses TimeLabel. G-DW484 limits this story to the chat's reminder reply, and Test.Tools.Reminders (Epic 11's) pins the list's due with the online demo off only.
    location: >-
      src/ocutalon/cls/OcuTalon/Tools/CommandCall.cls:120
    severity: low
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

**G6. Points the epic-context compile raised, decided at the gate.**
- **Skipped stays wide** (`Total` less `Resent`, as rows 14 and 15 and V1 already plan it), with `Unreached` the part of it that was never reached. The page's result pick is not changed until Story 31.2 (U-183), and a narrow `Skipped` would make it read a partway run as all-through, a false all-clear (product default 2). The chat notice is honest either way, because `Notice.ResultKey` picks `stoppedPartway` before `skipped`. The spine's AD-16 extension says the same.
- **DW-519's time-slot rule:** `Msg.Catalog` (the renderer) and `Data.Time` are Lane B's (AD-33), so do not edit them. Make `WatchAnswers.WatchNames` callable (Lane A) and call it from `RecentActivity`. For the time label, call an existing public entry point of the catalog (for example render a `{time}` slot through it) instead of repeating its rule. If the rule is reachable only through a private method of a Lane B class, HALT with an intent gap that names the method, rather than editing it.
- **Verification is lane B's in this run:** slot `ocutalon-slot-b` (port 52791), `OCUTALON_LOCK_DIR` the lane-b lock folder, `OCUTALON_TEST_WEB_PORT=52802`; rewrite `## Verification` with those values (no lane-a, 52801 or `ocutalon-slot-a`).
- **The README pin:** `docker/tests/test-readme.sh` pins that item word for word; update the pin with the sentence (G4).

</intent-contract>

## Re-planned matrix rows (2026-11-01)

The rulings win over the intent's rows. These rows replace rows 14, 15, 17's `stoppedPartway` slots and 18 (G1), and add rows 19 to 27. Counts are `Total|Resent|Completed|FailedAgain|Skipped`, and `U` is Unreached. "The text" of `result.stoppedPartway` is under Design Notes, "stoppedPartway".

| # | Scenario | Input / State | Expected Output / Behavior |
|---|---|---|---|
| 14 | Partway, with copies (probe) | 3 targets: 2 copies Completed, then the 3rd is `stopped` | One LOGPARTWAY warning. Ends `done`, `3\|2\|2\|0\|1`, U 1, Reason "". Key `result.stoppedPartway`: "The resend stopped partway: I resent 2 of the 3 orders (2 went through), the next one couldn't be resent, and 0 more weren't tried. Nothing else was changed, and I won't resend the rest without a new approval." Never `result.skipped` |
| 15 | Partway, mixed (probe) | 5 targets: 3 copies (2 Completed, 1 Error), 1 real skip (`changed`), then 1 `refused`. Also: Carry throws after 2 of 3 copies | `5\|3\|2\|1\|2`, U 1, Reason the fail reason: "… I resent 3 of the 5 orders (2 went through), the next one couldn't be resent, and 0 more weren't tried. …". The throw: `3\|2\|2\|0\|1`, U 1, `stoppedPartway` |
| 17 | Key order (pure) | `Notice.ResultKey`, `ResultSlots` | The intent's order. `stoppedPartway`'s slots are count (Total), itemNoun, resent, completed and notTried (U − 1, never below 0) |
| 18 | Catalog | `result.stoppedPartway` on every channel | The text. With notTried 1, the one form: "… and 1 more wasn't tried. …" |
| 19 | Stops at copy k of n (G1, probe) | 5 targets, copies 1 and 2 Completed, the 3rd `stopped` (k 3, n 5). Also 4 targets, the 3rd `error` | `5\|2\|2\|0\|3`, U 3: "… I resent 2 of the 5 orders (2 went through), the next one couldn't be resent, and 2 more weren't tried. …". The 4-target run: `4\|2\|2\|0\|2`, U 2, the one form "… and 1 more wasn't tried. …". Entries after the one that erred are never tried (`Resend` is called with them, and they come back as `after`) |
| 20 | DW-500: Triage's instructions (unit) | Compiled XData `OcuTalon.Agent.Triage\|\|INSTRUCTIONS` | It holds the user-message paragraph (Design Notes, "DW-500"), no "You have no tools", and every phrase `Test.Agent.Instructions` requires |
| 21 | DW-500: the scorer of a user-turn case (unit) | A decided `user-turn` case whose decision is `tellnow` with reasons R | Right for "A question from the user; the user is answered directly." Wrong for "There is nothing that needs the user at this moment.", for "I have no tools in this context and cannot look up production status.", for a fallback and for outcome `digest` |
| 22 | DW-500: the four chip cases (eval) | `eval/user-turn-*/case.json`, each with one chip's exact text | `Test.Eval.Cases` passes their shape. The push run on the mock lists each case under "User turns" and prints its score, which fails nothing. A release-candidate run scores real Haiku |
| 23 | DW-519 (unit) | `Tools.RecentActivity` over its existing fixtures | Its answer is unchanged: the same display names and time labels, " ET" on the online demo. It holds no `WatchNames` or `Shown` of its own |
| 24 | Time label (unit) | `CommandCall.TimeLabel(utc, online)` | "" for ""; `Data.Time.ForMessage(utc)` for online 0; the same plus " ET" for online 1. Made by `Msg.Catalog.RenderAt("watch.time", …)` |
| 25 | DW-484 (unit) | `CommandCall.Answer` of a result with a DueAt, online demo on, then off | `due` is "<ForMessage> ET", then "<ForMessage>". The keys stay `due,dueLocal,message,ok` |
| 26 | DW-469 (unit) | `Test.Checks.Runs` TestFindingsRender: a stop with IRIS's stop time, a stop with none (the run time), a disabled item | Each renders "… at <clock> ET." with onlineDemo 1 and "… at <clock>." with 0 (" on " for another day) |
| 27 | U-183: payload (unit) | `Live.Payload.Incident.FromRow` of an incident whose request R ended with U 1; one with U empty | R's `result.unreached` is 1 in the JSON; absent for the other |

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `web/`, `eval/`, `docker/`, `ci/` or `README`. Anchors re-checked on 2026-11-01.

**DW-500 (first)**
- `Agent/Triage.cls:20-38` XData INSTRUCTIONS. `:35` "You have no tools." feeds the tool-limit reasons.
- `Test/Agent/Instructions.cls:40-66` TestTriage (Epic 11's, read only): required phrases. Copy its XData reader (`:285-290`) into the new test.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls:1171-1174` the user rule (ignore/digest → tellnow plus USERANSWERED `:129`). Unchanged.
- `Agent/Input.cls:21-24`: a user message has no channel line and no `> ` quoting. Unchanged.
- `Eval/In.cls`: KINDS `:59`, TURNKINDS `:65`, SendTurn `:411`, Converse `:447`, TurnRequest `:479` (Kind "turn"), Render `:515`.
- `Eval/Report.cls`: key phrases in reasons (injection) `:455-496`, in the reply (command) `:565-616`.
- `Test/Eval/Cases.cls`: TestTurnCases `:176-216` pins the turn cases. `Test/Eval/Report.cls`: the scorer tests. `eval/command-run-shell/case.json`: the shape to copy.
- Mock (read only): `ci/mock/mock.mjs:26-31,440-447` (a guide prompt is matched before the mock key); `ci/mock/scenarios/B/try-it-*.json` (tool call or text replies, no decision).
- `web/src/app/live/payloads.ts:162-186` DecisionPayload and `Live/Payload/Decision.cls:6-100`: no override field, so the fallback is closed.

**The executor** (`Fix/Executor.cls`)
- Parameters: NOSTART `:77`, NOTRUNNING `:82`, LOGWAIT `:112` (add LOGPARTWAY beside it).
- Execute `:189-222`: Refusal `:193`; the StartExecution-failure branch `:212-218`, its expiry test `:213`. Refusal `:231-238`, past expiry `:236`.
- Run `:302-353`: NotRunning `:314` (30.4); Carry read `:318-324`; catch `:327`; NOTRUNNING end `:330-333`; NOREAD `:337-339`; ResentAt saved `:343-344`; all-skipped end `:352`.
- NotRunning `:357-366`, ProductionState `:370-374` (`timeout` goes on to Resend). CouldNotStart `:379-394`. Finish `:410-425`. Report `:569-585`, ResultOf `:589-603`, FirstReason `:606-618`.
- Pass `:677-711` (`last(id)` `:698`; drop and LOGWAIT `:701-710`). Look `:715-730` (counts `:728`). Tally `:735-765` (`lastAt` `:764`, read only by `Fix/Run.cls:207`).
- Resend `:855-928` (codes `:870-909`; LOGCOPY `:923-925`; skipped push `:926`). SkipReason `:931-943`.

**Around it**
- `Fix/Kind/RepairResend.cls:219-233` Execute: Resend at `:226`, merge into `result.skipped` at `:228-231`.
- `Fix/Run.cls`: doc `:1-30`; LOGSWEPT `:52`; EndMarked `:154-185` (counts `:180`); EndLeft `:188-224` (gate `:207`, counts `:211`).
- `Fix/Msg/FixResult.cls`: properties `:11-33`, Storage `:35-71` (slots 1-10).
- `Data/FixRun.cls`: properties `:19-52`, Storage `:83-134` (slots 1-14).
- `Watch/Notice.cls`: doc `:19-30`; keys `:60-72`; ResultKey `:177-188`; ResultSlots `:190-228` (key list `:203`, interrupted's remaining `:226`).
- `Msg/Catalog/Watch.cls`: productionStopped `:12-19`, itemDisabled `:20-28`, failedAndSkipped `:192-207`, stillResending `:208-220`, interrupted `:221-234` (the shape to copy), couldNotStart `:235-241`.
- `Watch/IncidentManager.cls`: Result `:1205-1215` (`:1214` `$Select(final: ..ResultNotice(…), 1: "")`); ResultNotice `:1220-1229`; docs `:66-69`, `:1203-1204`, `:1217`. `Watch/Transitions.cls:118-120` accepts a progress.
- `Live/Payload/Incident.cls:141-151` copies the ended FixRun into `Part/IncidentRequestResult.cls` (no Storage; `%JSONFIELDNAME` per property). `web/scripts/payloads.mjs` generates `web/src/app/live/payloads.ts:73-81` from them; `payloads.test.mjs` fails a stale file.

**DW-519, DW-484, DW-469, README**
- `Tools/WatchAnswers.cls:177-187` WatchNames `[ Private ]` (caller `:114`). `Tools/RecentActivity.cls`: WatchNames `:219-229` (copy, caller `:69`), Shown `:212-217` (copy, callers `:133`, `:134`, `:160`), `online` from `Watch.Reader.OnlineDemo()` `:70`.
- `Msg/Catalog.cls` (Lane B, read only): RenderAt `:64` (public; now "" is the current time); SlotText `:152-165` is Private.
- `Tools/CommandCall.cls:77-90` Answer (`due` `:84`). `Test/Tools/Reminders.cls` (Epic 11's, read only) pins the keys at `:507` and `due` = ForMessage at `:729`, `:993`, `:1062` (online demo off).
- `Test/Tools/RecentActivity.cls`: `At` `:80-83`; online demo 0 and 1 `:158-164`, `:419`; names `:323`, `:425`.
- `Test/Checks/Runs.cls:586-608` TestFindingsRender renders both keys with onlineDemo 0 only. `Checks/Process.cls:366-370` the two time sources.
- `README.md:25` item 2. `docker/tests/test-readme.sh:117` ITEM2, `:371-382` chk_use_cases.

**Tests and helpers**
- `Test/Fix/ExecutorProbe.cls`: SendResult `:117`, Statuses `:159`, ProductionState `:258`, Carry `:282`. `Test/Fix/RunProbe.cls`: Narrow `:16`, Feed `:28`, FailClose `:41`.
- `Test/Fix/Executor.cls`: TestRefusedStates `:188-233` (past expiry `:207-209`); TestNothingResent `:505-537` (case 2 `:520-528`); TestRunThatErredAfterACopyStillWaits `:679-700`; TestStillRunningAfterTheWait `:702-764` (no Results `:726`); TestStartExecutionFailsForAnApprovedRequest `:1044-1100` (past expiry `:1066-1072`); the Sweep tests `:1455-1595`. Helpers: Host `:1818`, Request `:1850`, AssertEnded `:1884`, Render `:1960`, CarryJSON `:2002`, Canned `:2018`, UnmarkedRun `:2178`, CannedAt `:2238`, Stamp `:2246`.
- `Test/Fix/Recheck.cls:22-143` (direct Resend `:129`). `Test/Fix/Partial.cls`: FAILAGAIN `:26`, TestSomeHadChanged `:28`, TestCopiesFailAgain `:69`, WaitResultOf `:167`. `Test/Fix/Waits.cls`: MARGIN `:35`, TempStopItem technique `:46-113`. `Test/Fix/Refused.cls`: TestNoApprovedRowNoRun `:13-63` (past expiry `:38-39`, 7 per kind `:62`), Request `:68`.
- `Test/Watch/Case.cls`: Raised `:1589`, TempStopItem `:1083`, StopOrders `:1137`, Tick `:680`, WaitResent `:1987`, WaitQueued `:1999`, WaitState `:1772`, WaitIncidentState `:1789`, FixResultsFor `:1917`, WaitFixResults `:1960`, NoticeBodies `:1437`, WaitResultNotices `:1973`, ResultOf `:1497`, PutBack `:481`.
- `Test/Watch/Lifecycle.cls`: TestResultNotices `:449` ("a progress report sends none" `:511-518`); TestFixResults `:374` (progress `:435-446`); Finish `:1206`, Results `:1220`, AssertSent `:1250`. `Test/Watch/NoticeText.cls`: TestResultKeys `:340-409`, TestRestartAndResendTexts `:411-451`.
- `Test/Msg/Catalog.cls`: doc `:3`, `:5`; Watch keys 22 `:81-83`; 117 keys `:121`; one forms 8 `:536`, `:553-554`; XData Keys `:952`, OneForms `:1089`, Fixtures `:1186` (result.* from `:1299`). `Test/Data/Tables.cls:581-603` FixRun's exact property set.

## Tasks & Acceptance

**Execution** (in this order; G0 puts DW-500 first):
- [ ] Task 0 -- on a fresh throwaway (`e30s5i`), measure and record under "Measured at implementation":
  - (a) In OCUORDERS, with Orders running, `Ens.MessageHeader.ResendDuplicatedMessage` for an Error header of a test order whose `TargetConfigName` the test set to a name that is no item: its status, and whether `newId` is set. An error with no `newId` builds row 12's refused case; otherwise that case is dropped and the gap recorded.
  - (b) After `StopOrders`, the same call gives `ErrProductionNotRunning`, no `newId`, no new header.
  - (c) With the mock, a `decide` request of provenance `user` and the text "What can you do?" sent to Decide as the new user-turn path sends it: the decision's outcome, fallback and reasons (the chip's prompt scenario answers it). Record it; nothing asserts it.
- [ ] `Agent/Triage.cls` -- DW-500: add the user-message paragraph (Design Notes) to INSTRUCTIONS, and replace "You have no tools." at `:35` with "Decide from the message alone.". Keep every phrase `Test.Agent.Instructions` requires and no `{{`.
- [ ] `Test/Agent/TriageUserTurn.cls` (new) -- row 20: reads the compiled XData (a copy of Instructions' 5-line reader) and pins the paragraph's sentences and the absence of "You have no tools".
- [ ] `Eval/In.cls` -- DW-500: kind `user-turn` in KINDS and TURNKINDS. Its case is sent like a command case, but TurnRequest gets the kind: a user-turn case's request has Kind `decide` (the decide request of a user's chat turn), and Converse skips Render for it. The TurnResult keeps the reply's DecisionRef, Fallback and FallbackReason. Update the class doc.
- [ ] `Eval/Report.cls` -- DW-500: score a `user-turn` case from its decision row (by DecisionRef): right when it is no fallback, its outcome is `tellnow`, every `expectation.keyPhrases` group has a hit in the reasons and no `expectation.absentPhrases` entry is in them (case-insensitive). Add the score line "User turns: <right> of <total>" and a "User-turn cases" section, printed and never checked, like the command score.
- [ ] `eval/user-turn-productions`, `-anything-wrong`, `-failure-earlier`, `-what-can-you-do` `/case.json` (new) -- one chip's exact text each; heldOut false; recordedBy "written for the evaluation set (Story 30.5, DW-500)"; expectation `keyPhrases` [["user"]], `absentPhrases` per Design Notes.
- [ ] `Test/Eval/Cases.cls` -- TestUserTurnCases: exactly the four cases, their exact texts and shape (expectation fields `keyPhrases` and `absentPhrases` only). Keep TestTurnCases' pins of the other turn cases.
- [ ] `Test/Eval/Report.cls` -- row 21, over decision rows the test makes and removes.
- [ ] `Data/FixRun.cls` -- `Property Unreached As %Integer` after `Reason`: "The targets the run never reached: the copy that erred and every target after it, counted among Skipped; written by Run with ResentAt, empty for a run that made no copy." Write back the compiled `<Value name="15">` verbatim; update the class doc -- U-182.
- [ ] `Fix/Msg/FixResult.cls` -- `Property Unreached As %Integer` after `Reason` ("of Skipped, the targets the run never reached"); slot 11 verbatim; the class doc says a progress report is sent once, when the wait ends with copies running.
- [ ] `Fix/Executor.cls` -- Resend: trailing `Output unreached As %DynamicArray`. At the first entry coded `stopped`, `refused` or `error`, push `{"id", "code"}` and push every later entry as `{"id", "code": "after"}` untried. Real skips (`gone`, `status`, `body`, `field`, `changed`) still go to skipped and the loop goes on -- DW-419, U-182.
- [ ] `Fix/Kind/RepairResend.cls` -- Execute's result gains `"unreached"` (`[]` when nothing was planned).
- [ ] `Fix/Executor.cls` -- Run:
  - unreached is the Carry result's `unreached`; after a throw with copies > 0 it is the passed targets less the copies (LOGRECHECK as today).
  - copies 0 and unreached > 0: `CouldNotStart(row, total, reason, 1)`, NOTRUNNING when the first code is `stopped`, else NOSTART. A throw with copies 0 stays NOREAD.
  - copies > 0: `run.Unreached` saved with ResentAt; when > 0, one Type 3 `LOGPARTWAY` ("FixExecutor stopped the resend of request <ref> at message <id>: <code>; <n> of <total> targets were not reached", through `Bridge.Redact`, ids and counts only).
  - Look's counts gain `unreached`; Skipped stays total − resent (G6). ResultOf sets `Unreached`.
- [ ] `Fix/Executor.cls` -- AC 2, the progress: `Look(id, Output tally)`; Pass keeps the last read tally beside `last(id)`. At the drop, for a run with no EndedAt, Interrupted 0, its row executing, its time up and a kept tally: `Report(row, counts, 0)` with `{total, resent, completed, failedAgain, skipped: total − resent, unreached, reason: ""}`. LOGWAIT stays; nothing stored, no Action entry. `ResultOf(…, final As %Boolean = 1)`, `Report(…, final As %Boolean = 1)`.
- [ ] `Fix/Executor.cls` -- DW-384: Refusal no longer refuses an approved row past its expiry; Execute, right after Refusal, ends such a row with `CouldNotStart(row, total, ..#NOSTART, 0)`; the StartExecution-failure branch ends any row still approved with NOSTART, expired or not. Update the class doc (items 1, 4, 5, the wait, "A run that resent nothing").
- [ ] `Fix/Run.cls` -- EndLeft drops the `lastAt` gate (row 7); its counts and EndMarked's gain `unreached`. Remove `Tally.lastAt`. Update the doc.
- [ ] `Watch/Notice.cls` -- `KEYPARTWAY = "result.stoppedPartway"`; ResultKey: `stillResending` also for a result neither Final nor Interrupted, and `stoppedPartway` for `+result.Unreached > 0` right after couldNotStart; ResultSlots per row 17, and `failedAndSkipped` adds `resent`. Update the doc.
- [ ] `Msg/Catalog/Watch.cls` -- `result.stoppedPartway` (text, slots, one form on notTried, source per Design Notes) and `watch.time` (text "{time}", slot time `time`, source "Story 30.5 (DW-519, DW-484): the catalog's time label alone, for a tool's answer to the model").
- [ ] `Watch/IncidentManager.cls` -- Result `:1214` passes `..ResultNotice(incident, row, result)` for every owned result; docs `:66-69`, `:1203-1204`, `:1217` say a progress result gets `result.stillResending` (G3).
- [ ] `Live/Payload/Part/IncidentRequestResult.cls` -- `Property Unreached As %Integer(%JSONFIELDNAME = "unreached")`; `Live/Payload/Incident.cls` -- `Set part.Result.Unreached = run.Unreached` after `:150`, doc `:70-72`; then `(cd web && node scripts/payloads.mjs)` regenerates `web/src/app/live/payloads.ts` (generator output only) -- U-183, row 27.
- [ ] `Tools/WatchAnswers.cls` -- WatchNames loses `[ Private ]` (doc: "shared with RecentActivity"). `Tools/CommandCall.cls` -- new `TimeLabel(utc, online As %Boolean) As %String` (row 24; "" on an empty time or a render error), and Answer's `due` is `..TimeLabel(result.DueAt, ##class(OcuTalon.Watch.Reader).OnlineDemo())` (DW-484). `Tools/RecentActivity.cls` -- remove its WatchNames and Shown; call `WatchAnswers.WatchNames` and `CommandCall.TimeLabel` -- DW-519.
- [ ] `Test/Tools/RecentActivity.cls` -- unchanged expectations stay green (row 23); add one assertion that RecentActivity has no WatchNames or Shown method (`%Dictionary.CompiledMethod`). `Test/Tools/CommandCallTime.cls` (new) -- rows 24, 25 (sets and restores the onlineDemo setting).
- [ ] `Test/Checks/Runs.cls` -- TestFindingsRender: row 26 (DW-469); a third Step whose stop has no readable stop time gives the run time.
- [ ] `README.md:25` -- append "It also tells you once when a production stops or one of its items is disabled."; `docker/tests/test-readme.sh:117` ITEM2 matches it (G4).
- [ ] `Test/Fix/ExecutorProbe.cls` -- Carry's canned JSON takes `unreached`; SendResult records `unreached`.
- [ ] `Test/Fix/Executor.cls` -- TestRefusedStates loses past expiry; new TestPastExpiryCannotStart (row 10); TestStartExecutionFailsForAnApprovedRequest's past-expiry case ends NOSTART; TestNothingResent case 2 becomes couldn't start NOTRUNNING (its Carry gives copies 0 and unreached `stopped`); TestRunThatErredAfterACopyStillWaits gives `stoppedPartway`; new TestResendThatErrsPartwaySaysHowFarItGot (rows 13-16, 19, LOGPARTWAY, and row 27 through `Live.Payload.Incident.FromRow` of an unsaved `Data.Incident` whose RequestRefs holds the row); TestStillRunningAfterTheWait asserts rows 2 and 4, and a new case rows 3 and 5; Sweep: TestSweepLeavesRunsOfTheWaiter (row 8), TestSweepEndsEveryRunWhoseCopiesAreDone (row 7), and row 16.
- [ ] `Test/Fix/Recheck.cls` -- TestResendStopsWhereItErrs (row 12, Task 0a); Orders started again after it, also after a failure (`PutBack`).
- [ ] `Test/Fix/Partial.cls` -- TestSomeFailAgainAndSomeHadChanged (row 1, `/state`'s result with no `unreached`). `Test/Fix/Waits.cls` -- TestStillRunningIsReportedThenEnded (row 6). `Test/Fix/Refused.cls` -- 6 rows per kind; new TestPastExpiryCannotStart (row 11).
- [ ] `Test/Watch/NoticeText.cls` -- row 17 with `stoppedPartway`'s slots and texts (rows 14, 15, 18, 19); `failedAndSkipped` slots include `resent`. `Test/Watch/Lifecycle.cls` -- a final with Unreached 1 sends `result.stoppedPartway`; "a progress report sends none" becomes row 9.
- [ ] `Test/Msg/Catalog.cls` -- Keys (24 Watch keys, 119 in all), OneForms (9), Fixtures for both new keys, doc counts. `Test/Data/Tables.cls` -- FixRun gains `"Unreached": "%Integer"`.
- [ ] Every other test that asserts an old shape: search `Test/` for `stillResending`, `Skipped`, `past expiry`, `lastAt`, `Resend(`, `WatchNames`, `Shown(`, `user-turn`, `TURNKINDS` and update them (Shared surfaces).

**Acceptance Criteria:**
- Given a user's own chat message, when Triage decides it, then its instructions tell it that the reasons only classify the message as the user's own, which is always answered, and never describe production state, tool limits or whether anything needs the user; and the evaluation set holds a user-turn case for each of the four chips' exact texts, scored by that rule (rows 20-22; DW-500, AD-28, AD-22). The mock cannot prove real Haiku's wording: the release-candidate run and the Contest Planner's host check do.
- Given an approved repair in which some copies fail again and some targets are skipped, when FixExecutor sends its FixResult, then it carries both counts (Unreached 0), the run and the incident event's request result carry them, and the notification is `result.failedAndSkipped` with resent, completed, failed-again and skipped slots (rows 1, 17; AD-15, AD-16, AD-32).
- Given copies still running when the 60-second wait ends, when the wait ends, then FixExecutor sends one FixResult with `Final` 0 and the counts so far, the incident stays `fixing` and its owner gets `result.stillResending`; and once every copy is done, Checks' next Tick sends Sweep's final FixResult, and the incident moves by AD-15's table with the matching text (rows 2-9; AD-15, AD-16, AD-18).
- Given an approved request past its ExpiresAt when FixExecutor takes its Execute, when it is handled, then it ends as couldn't start with `NOSTART`, the row `failed`, one final FixResult with every count 0, and the incident leaves `fixing` with "Nothing was resent: OcuTalon couldn't start the resend. Nothing was changed." (rows 10, 11; DW-384, U-161).
- Given a resend that errs at copy k of n, when the run ends, then with no copy made it is couldn't start with a plain reason, and otherwise its FixResult and FixRun carry Unreached (n − k + 1), the incident payload's request result carries `unreached`, and the notice reads `result.stoppedPartway` with the resent, erred and not-tried counts and "Nothing else was changed"; no text says they had changed since the dry run (rows 12-16, 18, 19, 27; DW-419 with 30.4's `timeout` occurrence, U-182, U-183).
- Given `recent_activity` and the reminder tool's answer, when they show a time, then both make it through the catalog's time label (" ET" on the online demo), and `recent_activity`'s display names come from `WatchAnswers.WatchNames` (rows 23-25; DW-519, DW-484).
- Given a `watch.productionStopped` or `watch.itemDisabled` notice from either time source, when it is rendered, then `{time}` carries " ET" on the online demo and none otherwise (row 26; DW-469).
- Given the README, when `test-readme.sh` runs, then item 2 ends with the owner's sentence and the check passes (G4).

### Review Findings

Code review 2026-11-02 (`bmad-code-review`, full mode, four layers with no model override): 24 raw findings, grouped into 16 entries (high 0, med 3, low 13) and 7 rejected. Each entry carries severity, fix-risk, footprint and disposition (Rule 15).

- [x] [Review][Patch] (med; fix-risk low, one prompt sentence; in-story) Triage's user-message paragraph and the arriving-item paragraph clash for a user's own request to resend, approve or change something. Real Haiku could give the "an email or other arriving message can't approve requests" reason on a user chat turn, against G-DW500's "ANY user chat turn". Added one sentence to the paragraph: it holds for such requests too, and the next paragraph is about items that arrived on a channel. The sentence is pinned in TriageUserTurn, and `Test.Agent.Instructions`' phrases are kept [src/ocutalon/cls/OcuTalon/Agent/Triage.cls:37]
- [x] [Review][Patch] (med; fix-risk low; in-story; Rule 19) No test pinned `Execute`'s early expiry check (AC 4): replacing it with `If 0` left every test green, because StartExecution's failure branch also ends the run NOSTART. TestPastExpiryCannotStart's second iteration, a StartExecution that fails, was vacuous, because Start is never reached. It now runs over a registered kind and the unregistered kind `zz_fix`, which must end NOSTART, not UNUSABLE ("before the kind is read") [src/ocutalon/cls/OcuTalon/Test/Fix/Executor.cls:1295]
- [x] [Review][Patch] (med; fix-risk low; in-story; Rule 19) In row 4, a read that throws was never checked for a progress report. TestStillRunningAfterTheWait's throw case now asserts that no FixResult was sent [src/ocutalon/cls/OcuTalon/Test/Fix/Executor.cls:880]
- [x] [Review][Patch] (low; mechanical) DW-559: `CommandCall.Listed` now shows each due time through `TimeLabel`, with " ET" on the online demo. New TestListedDue. No Epic 11 file is touched, and `Test.Tools.Reminders` stays green on a fresh stack [src/ocutalon/cls/OcuTalon/Tools/CommandCall.cls:121]
- [x] [Review][Patch] (low; mechanical) QA's TestSetReminderReplyOnTheTool quit silently with no assertion when the production was not ready. It now records `$$$AssertSkipped` with the reason, as the project's other production-bound tests do. Its doc's "as on the warm stack" was dropped: the test runs on the warm stack, where no SKIP was printed [src/ocutalon/cls/OcuTalon/Test/Tools/CommandCallTime.cls:116]
- [x] [Review][Patch] (low; mechanical) A flake window: the "still inside its wait" case of TestProgressReportCarriesTheCountsSoFar set ResentAt one second back against a 3-second wait with stamps to the second. ResentAt is now the current time [src/ocutalon/cls/OcuTalon/Test/Fix/Executor.cls:923]
- [x] [Review][Patch] (low; doc) Executor's AD-33 doc listed Unreached among the end fields that only End and Mark write. It now says that Run also writes Unreached, in the ResentAt save [src/ocutalon/cls/OcuTalon/Fix/Executor.cls:53]
- [x] [Review][Patch] (low; doc) The NOTRUNNING doc still described a per-copy skip reason and called the case "mid-run". It now names the no-copy case and points the partway case to `result.stoppedPartway` [src/ocutalon/cls/OcuTalon/Fix/Executor.cls:85]
- [x] [Review][Patch] (low; doc) The `TimeLabel` doc claimed that "every time the model repeats" carries its clock. It now names its three callers. The remaining tool times (`WatchAnswers` `since` and `checked`) were appended to DW-417 as an occurrence [src/ocutalon/cls/OcuTalon/Tools/CommandCall.cls:75]
- [x] [Review][Patch] (low; doc) The `AssertRequests` doc said that `marked` 0 means "no block is marked", but Triage now passes `marked` 0 with `systemMarked` 1 [src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls:496]
- [x] [Review][Patch] (low; doc) TestSendsUserTurn claimed that "a Reply is no answer", but it drives a non-Reply container. The claim now says "an answer that is not a DecisionResponse" [src/ocutalon/cls/OcuTalon/Test/Eval/In.cls:22]
- [x] [Review][Patch] (low; Rule 19 tracking) AC 6's display-name half (DW-519) had no `mutation:` line. The mutation was applied on a fresh stack and the line is written under `## Verification`
- [x] [Review][Defer] (low; in-epic; spine) AD-12's `Requests[].Result` list lacks Unreached, and AD-22 does not name the user-turn kind (the spec's "For the lead's gate" asks for both). This is a Rule 20 note for the lead, not code. DW-568, `wontfix-accepted` with a reopen_if [ARCHITECTURE-SPINE.md AD-12] -- deferred: fixing it means amending the spine, which is the lead's job
- [x] [Review][By-design] (low) A partway run's progress notice reads "Still resending: 0 of 3 …" while one target is unreached. Row 17's key order puts `stillResending` first for any non-final result, and row 16 has the progress carry Unreached. The final result reads `stoppedPartway` [src/ocutalon/cls/OcuTalon/Watch/Notice.cls]
- [x] [Review][By-design] (low) The Action (audit) entry does not record Unreached: "the Action entry's counts are unchanged" (Decided in-stage) [src/ocutalon/cls/OcuTalon/Fix/Executor.cls:581]
- [x] [Review][By-design] (low) After a Carry throw with copies, Unreached is the passed targets less the copies, which can include in-run real skips. Row 15 pins `3|2|2|0|1`, U 1, for the throw; the thrown result carries no skip list [src/ocutalon/cls/OcuTalon/Fix/Executor.cls:362]
- [x] [Review][Wontfix-theoretical] (low) The StartExecution-failure branch for a row whose expiry passes between Execute's check and StartExecution has no test. The branch ends any still-approved row NOSTART, so the path is correct. It would become real only for an Execute taken within the last second before ExpiresAt, and pinning it needs a probe seam that moves ExpiresAt [src/ocutalon/cls/OcuTalon/Fix/Executor.cls:225]

**Rejected**
- (false) `test-eval-set.sh` and `eval/run.sh` do not check user-turn cases. Their shape is pinned by `Test.Eval.Cases` TestUserTurnCases, and the score line and section by `Test.Eval.Report` TestUserTurn.
- (false) LOGPARTWAY is logged before the ResentAt save is checked. The warning claims only that the resend stopped partway, which is true either way, and LOGRUN follows for the save. After a throw it has no message or code to name; LOGRECHECK carries the error.
- (false) TestTimeLabel's catalog-equality assertion restates the code. It pins row 24's "made by RenderAt", and the ForMessage and " ET" assertions pin the label.
- (false) The progress FixResult's trace session is untested. Progress sends through Report, whose session and SuperSession are pinned in `Test.Fix.Executor` (the two-incident session case).
- (rejected: the fix edits the spec) The implementation notes say FixResult.Unreached is empty; ResultOf gives 0. No consumer reads empty as anything different.
- (rejected: the fix edits the spec) The "Not done" bullet is stale against the Review Triage Log.
- (rejected: duplicate) Edge Case Hunter's and the Acceptance Auditor's copies of the FixResult.Unreached claim.

## Spec Change Log

- 2026-11-01 (lead, spec gate, re-plan): status reset to draft; the spec-gate rulings G0-G5 (DW-500 widened and first, DW-519, DW-484's narrow part, DW-469, U-182, U-183, Q1, the README sentence) added inside the intent block; the Never lines on Lane B and Epic 9 files changed to match U-183 and Q1. The AD-16 extension is written in the spine.
- 2026-11-01 (plan stage, re-plan): rows 14, 15, 17's slots and 18 re-worded and rows 19-27 added outside the frozen intent block; DW-500, DW-519, DW-484, DW-469, U-183's payload and the README added to the tasks; the contended and split notes removed (G3); verification moved to lane B (G6).

## Review Triage Log

### 2026-11-01 - Review pass
- verdicts: 27 findings (26 from the layers, one from the shard run) - high 1, medium 4, low 22, false 0, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: the approvals page ignores `unreached`, so it still shows `result.skipped` - the page's result pick is Story 31.2 (U-183, G6); the spec forbids a `web/**` edit for it.
  - `[low]` `[reject]` Blind: "and 0 more weren't tried" when Unreached is 1 - the wording is fixed by G1 and pinned by rows 14, 15, 19 and the tests; changing it is a spec edit (a one-form on notTried 0 is a product-text call).
  - `[low]` `[reject]` Blind: `stoppedPartway` omits failed-again, the reason and real skips - G1 fixes the text; they stay in the FixResult, the FixRun and the payload; spec-bound.
  - `[low]` `[reject]` Blind: a marked run stores Skipped 0 beside Unreached > 0 - EndMarked's Skipped 0 is as before; the interrupted key wins in ResultKey, so the text is right; reached only by a restart during a partway run.
  - `[low]` `[reject]` Blind: an expired approval reads as a generic start failure - row 11's text is the spec's (DW-384, U-161).
  - `[medium]` `[reject]` Blind, Edge: after a throw with copies, Unreached is passed less copies and may count plan-skips - row 15 pins `3|2|2|0|1` for a throw; the thrown result carries no skip list; spec-bound.
  - `[low]` `[reject]` Blind, Edge: a progress report can follow the final result - Progress re-checks the executing row at the send; the window is milliseconds, and row 9 has IncidentManager handle a late progress (still `stillResending`); a lock around a send would hold RUNLOCK across a message.
  - `[low]` `[reject]` Blind: the user-turn score gates nothing and the absent list is thin - spec-bound (printed, never checked: a target is a product number); the list is the spec's.
  - `[low]` `[reject]` Blind: the spec's Auto Run Result is stale - rewritten at finalize.
  - `[medium]` `[patch]` Blind, VG: pinning mutations for Partial row 1, Waits row 6 and the DW-519 half of AC 6 were not observed on the live classes - applied on fresh stacks: Partial, Waits and RecentActivity went red; lines in `## Verification` updated.
  - `[low]` `[reject]` Blind, Edge, IA: `failedAndSkipped` carries `resent` but the catalog does not declare it - spec row 1 asks for the slot "ignored by the text"; declaring it would regenerate the page's catalog (Lane B).
  - `[low]` `[reject]` Edge: EndMarked sets skipped 0 beside Unreached - same as the row above.
  - `[low]` `[reject]` Edge: a notice reads "0 more weren't tried" - same as above.
  - `[low]` `[reject]` Edge: CouldNotStart discards real skips of a run that made no copy - row 13 pins `n|0|0|0|0`; spec-bound.
  - `[low]` `[reject]` Edge: Progress may use a stale tally - row 3 says "the last look that read the copies"; spec-bound.
  - `[low]` `[reject]` Edge: malformed `absentPhrases` is treated as none - the four shipped cases are pinned by Test.Eval.Cases; no user-reachable path.
  - `[low]` `[reject]` Edge: a channel-less hostile item can pass as the user's message - the paragraph is the DW-500 ruling; Decide's user rule is code and does not read Triage's text for provenance.
  - `[low]` `[reject]` Edge: `failedAndSkipped` slot `resent` undeclared - duplicate of the row above.
  - `[medium]` `[patch]` VG: Resend's `error` branch is never driven (dropping `|| (code = "error")` left every test green) - added a third case to `Test.Fix.Recheck` TestResendStopsWhereItErrs (a namespace that cannot be entered); mutation observed red, restored.
  - `[low]` `[reject]` VG: `EndMarked` carrying `unreached` is unpinned - the marked path is outside rows 7 and 16; the interrupted key wins in the text; reached only by a restart during a partway run.
  - `[low]` `[reject]` VG: the StartExecution-failure guard for a past expiry is an equivalent mutant - Execute ends an expired row before Start; the spec records it. Execute's own expiry check is also not pinned by outcome (StartExecution refuses an expired row), noted in `## Verification`.
  - `[medium]` `[patch]` VG: `Test.Fix.Refused` TestPastExpiryCannotStart used targets that do not exist (101-103), so its "nothing changed" check was vacuous - it now runs over three real failed orders; the mutation "Refusal refuses a past expiry" is red on a fresh stack.
  - `[low]` `[defer]` VG: `CommandCall.Listed` (the reminders list) shows a due time with no zone label on the online demo - G-DW484 is narrowed to the reminder reply; deferred below.
  - `[low]` `[reject]` VG: the unreadable and throw cases of TestStillRunningAfterTheWait count Results from an earlier section - one method, one order; green only when no progress is sent from an unreadable read, which is the point.
  - `[low]` `[reject]` IA (descriptive): the page's result band does not read `unreached` - same as the first row; the `web/src/app/live/payloads.ts` edit is the generator's output, ruled by the lead.
  - `[low]` `[reject]` IA (descriptive): a late progress after the final result - same as the race row.
  - `[high]` `[patch]` Found by the shard run (not a layer): `Test.Agent.Runners` failed ("Triage request 1 leaves the system block unmarked") because Triage's longer instructions now reach min_tokens_for_cache; the test expects the system block marked for Triage (systemMarked 1) and its comment is corrected. The old expectation going red on the new prompt is the mutation observed.

## Design Notes

**Architecture decisions (Rule 6).** AD-16 (as amended for U-161, U-160 and U-182: past expiry, partway, Unreached, Skipped stays wide); AD-15 (`fixing` + progress stays `fixing`); AD-18 (Checks sends Sweep's results; unchanged); AD-32 (keys and slots only; `RenderAt` is the one renderer); AD-28 (no model-written all-clear; the user rule stays code); AD-22 (the evaluation set gains the user-turn kind); AD-7 (Triage stays declarative: instructions only); AD-12 (the incident payload's Result gains `unreached`); AD-33 (one writer of a run's end; Lane B's classes untouched); AD-26 (the FixResult in the incident's trace session); AD-3 (Resend's one switch); AD-5 (append-only Storage); AD-11 (FinishExecution closes the row); AD-2 (no bridge change).

**DW-500: the preferred route; the fallback is closed.** Neither `DecisionPayload` (`payloads.ts:162-186`) nor `Live.Payload.Decision` has an override field, so the web fallback would need `api-types.ts`/`payloads.ts` changes. The paragraph added to Triage's instructions:
> **The user's own message.** A message that does not say which channel it arrived on and is not quoted is the user's own chat message to OcuTalon, and it is always answered, so choose "tellnow". Give one reason that only says what kind of message it is, for example "A question from the user; the user is answered directly." or "A request from the user; the user is answered directly." Never describe the state of a production, what you can or cannot look up or access, or whether anything needs the user: OcuTalon answers the user separately, from what it checks itself.
- **What the mock can pin.** A chip's exact text matches its guide-prompt scenario before Triage's mock key (`mock.mjs:440-447`), whose reply is a tool call or text, not a decision, so on the mock Triage's decision for a chip is whatever Decide makes of an unusable reply (Task 0c). No mock case can show real Haiku's wording, and the mock's scenarios stay unchanged. So the pins are: the compiled instructions (row 20), the scorer (row 21) and the four cases' shape (row 22). The cases score real Haiku in every release-candidate run (REL-5), and the Contest Planner checks the host after the merge.
- **absentPhrases** (case-insensitive, every case): "tool", "access", "look up", "cannot", "can't", "unable", "needs the user", "need the user", "nothing", "healthy", "all clear", "everything is", "no failure", "no error". The score is reported, never a REL-5 target (a target is a product number).

**stoppedPartway (U-182's condition).** Text: "The resend stopped partway: I resent {resent} of the {count} {itemNoun} ({completed} went through), the next one couldn't be resent, and {notTried} more weren't tried. Nothing else was changed, and I won't resend the rest without a new approval." One form on `notTried` = 1: "… and 1 more wasn't tried. …". Slots: count, itemNoun (noun), resent, completed, notTried. Source: "Story 30.5 (AD-16 as amended, U-182)". The copy that erred is always one (the loop stops at it), so it is written as "the next one"; "I resent" needs no verb agreement; completed is added so a copy that failed again is never shown as gone through. `stoppedPartway` implies Resent ≥ 1 and Total ≥ 2.

**Decided in-stage.**
- **The time label** goes through the catalog's public `RenderAt` with a new Lane A key `watch.time` (text "{time}"), the route G6 names ("render a {time} slot through it"). Its home is `CommandCall.TimeLabel`, because both of its callers are tool answers. Measured: the label equals `ForMessage` (+ " ET" on the demo).
- **DW-484 needs no Epic 11 file:** the model takes the due time from `CommandCall.Answer` (Lane A, `Tools/**`), so no HALT. The label follows the catalog's rule: " ET" on the online demo, none on a local install. Whether Haiku copies "08:02 ET" into its reply is the host check's (inference).
- **U-183's payload** needs Incident's own part class `Live/Payload/Part/IncidentRequestResult.cls` (only Incident uses it; Lane A by AD-33's table row for `Live.Payload.Incident`) and the generated `web/src/app/live/payloads.ts` (else `payloads.mjs --check` and `payloads.test.mjs` fail). G1b's "no web/** change" is read as the page's result pick, and the file is regenerated, never hand-edited. Flagged for the gate below.
- **DW-469's pin** extends the existing `Test.Checks.Runs` TestFindingsRender (Lane A, warm) rather than a new class.
- Kept from the first plan: no copy made is couldn't start (NOTRUNNING or NOSTART; a throw stays NOREAD); the progress is sent once, by the waiter, only for an unmarked executing run read at least once, stores nothing and writes no audit entry; a run whose waiter was stopped gets only its final; the progress's count is Total; ResultKey gives `stillResending` for any non-final, non-interrupted result; Sweep ends every unmarked run past its wait whose copies are done; the mixed slots add `resent` (ignored by the text); DW-384 goes through `CouldNotStart(…, 0)`; the Action entry's counts are unchanged; LOGPARTWAY gives operators the code.
- Shard parts: lane-a in 8, lane-b in 6, because 30.6's `--part 1/3` of lane-b took 888 s.
- The intent's row 13 names `StateIs`: since 30.4 the probe's seam is `ExecutorProbe.ProductionState` (`:258`). The first plan's V1, V2 and V4 (`FixRun.Unreached`, `FixResult.Unreached`, stop at the first copy that errs) were ruled by U-182; its V3 text is replaced by the one above.

**For the lead's gate.**
- G1b vs the intent's Never line: `Part/IncidentRequestResult.cls` and the regenerated `payloads.ts` (above). If refused, `unreached` and row 27 move to Story 31.2 with need (1) below.
- Spine notes (Rule 20): Conventions "Result texts" (`stillResending` for a non-final result; `Unreached` > 0 → `stoppedPartway` after couldNotStart; the payload's Result gains `unreached`); AD-12's incident payload (`Result` gains `Unreached`); AD-22 (a run also sends user-turn cases to Decide as a user's decide).
- Lane B needs, for Story 31.2: (1) the page's pick of `stoppedPartway` from `unreached` and `catalog.mjs`'s key and one form; (2) the in-progress band.

**Integration ACs (Rule 1).** `RecentActivity` (consumer) reads the shared `WatchAnswers.WatchNames` and `CommandCall.TimeLabel` and gives the same names and labels (row 23, `Test.Tools.RecentActivity` on a real stack). `CommandCall.Answer` reads TimeLabel (row 25). The real IncidentManager reads the progress FixResult and sends `result.stillResending` (row 6), and the mixed one, `result.failedAndSkipped` with `/state` (row 1). `Live.Payload.Incident` reads `FixRun.Unreached` (row 27).

**Consumed-by:** `Tools.RecentActivity` (Story 5.13, this story) and `CommandCall.Answer` (this story) consume `WatchNames` and `TimeLabel`; IncidentManager (5.5, 7.3) via `Notice.ResultKey`/`ResultSlots`; Checks (7.5) via Sweep; the page (Story 31.2) via `unreached`; Telegram's in-place edit (Epic 12) sees a progress notice, then the final, with one ApprovalRef.

**Consumes:** `Msg.Catalog.RenderAt` (0.9), `Data.Time.ForMessage`, `Watch.Reader.OnlineDemo`, `Approval.FinishExecution`/`StartExecution`, `Watch.Transitions`, `Watch.Reader.Evidence`, `Test.Watch.Case`'s live helpers, Eval's turn path (9.7).

**Extend, don't copy (Rule 2).** RecentActivity's two copies are removed (DW-519). `ResultOf`/`Report` gain `final`; the progress reuses Tally; DW-384 and a no-copy partway reuse `CouldNotStart`; `stoppedPartway` reuses ResultSlots' interrupted branch and the catalog shape of `result.interrupted`; Resend gains a trailing output; the user-turn kind extends EvalIn's turn path and Report's key-phrase scoring; the new Triage test copies `Test.Agent.Instructions`' 5-line XData reader, because that file is Epic 11's.

**Ledger inbox (Rule 17).** DW-500: rows 20-22. DW-519: row 23. DW-484: row 25. DW-469: row 26. DW-384: rows 10, 11. DW-419 (with 30.4's `timeout` occurrence): rows 12-16, 19. None declined.

**Files outside "Ours"** (`footprint_extensions`): `Tools/CommandCall.cls`; `Live/Payload/Part/IncidentRequestResult.cls` and `web/src/app/live/payloads.ts` (generated); `eval/user-turn-*`; `README.md` and `docker/tests/test-readme.sh` (G4); `Test/Msg/Catalog.cls` and `Test/Data/Tables.cls` (own entries).

**Measured at planning** (slot B, `ocutalon-slot-b`, `OCUTALON`, build 154U; in-memory calls only, nothing saved or compiled): `RenderAt("answered.expired", {"time": t}, "web", "", 0|1)` gives `ForMessage(t)` without and with " ET" ("Expired at 21:25 ET."), "on" for another day, and accepts now "".

**Implementation notes (2026-11-01).**
- DW-500: the preferred route was built, the web fallback was not. `Agent/Triage.cls` has the user-message paragraph and "Decide from the message alone." in place of "You have no tools."; `Eval.In` and `Eval.Report` have the kind `user-turn` (the request is a `decide` of provenance `user`, answered with a `DecisionResponse`, scored from its decision row by outcome, key phrases and absent phrases; the "User turns" score line and the "User-turn cases" section are printed and never checked); `eval/user-turn-productions`, `-anything-wrong`, `-failure-earlier` and `-what-can-you-do` hold the four chips' exact texts. The Contest Planner checks real Haiku's wording on the host.
- `result.failedAndSkipped` carries `resent` in its slots, but the catalog entry does not declare it (the text ignores it), so the page's generated catalog is unchanged and `catalog.mjs --check` needs no regeneration; `Test.Watch.NoticeText` pins `resent` apart from the declared slots.
- `Look(id, Output tally)` gives the tally only when the read outcome was `read`; `Pass` keeps the latest such tally in `last(id, "tally")`; at the drop, `Progress` sends the report if the run is not marked, its request is executing and its time is up. `Test.Fix.ExecutorProbe.ProgressNow` is the public call of `Progress` for the tests.
- `FixRun.Unreached` and `FixResult.Unreached` are stored as empty for a run that did not stop partway (End writes it only above 0), so the payload leaves `unreached` out; `Skipped` stays wide (G6).
- `Test.Watch.Case` gained `unreached` in `Runs` and `FixResultsFor`; `Test.Eval.ZzIn` answers a `decide` request with a `DecisionResponse`.
- Not done: `eval/run.sh` and `docker/tests/test-eval-set.sh` are unchanged (the latter passes and checks no field of a user-turn case beyond the common ones); `Test.Tools.RecentActivity`'s data tests skip on the warm stack, so its unchanged expectations are for the lead's shard run to confirm; `Test.Fix.Partial` row 1 and `Test.Fix.Waits` row 6 pass on a fresh stack as written, but their mutation lines were observed in `Test.Fix.Executor` only.

**Measured at implementation** (fresh throwaway `e30s5i`, `Test.Fix.Recheck`; the same values were read first on the warm stack):
- Task 0a (Orders running, an Error header whose `TargetConfigName` is set to `ZzNoSuchItem`): `Ens.MessageHeader.ResendDuplicatedMessage` returns the error "Target config item 'ZzNoSuchItem' is not running", which is not `ErrProductionNotRunning`, with no `newId` and no new header. Row 12's refused case is built (`TestResendStopsWhereItErrs`, second half).
- Task 0b (after `StopOrders`): the same call returns `ErrProductionNotRunning` ("No production is running"), no `newId`, no new header (first half of the same test).
- Task 0c (mock, a `decide` request of provenance `user`, text "What can you do?", through the `SimMailboxIn` service to `Decide`, owner eval): the answer is a `DecisionResponse` with outcome `tellnow`, `Fallback` 1, fallback reason `invalid` and empty reasons; the decision row is kind `decide` with a cost (0.000071 USD), so the cost and size of the row are known. "Which productions are running?" gives the same with a cost of 0.000151. On the mock the four chip cases therefore score not right and are listed as fallbacks, and fail nothing.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=30 stage=implement'`, run from the worktree root. Fresh tag `e30s5i`, warm tag `e30s5iw`.

- One command per tool call, foreground, `timeout: 600000`; never two IRIS test runs in one message; after the harness backgrounds a call (about 180 s), poll its output in loops under 170 s and never start a second copy.
- Throwaway stacks only for tests. Warm for in-process classes; fresh for classes that need the running production's FixExecutor, IncidentManager or Checks.
- On `ocutalon-slot-b` (`server` `ocutalon-slot-b`, `namespace` `OCUTALON`, identity by `iris_server_info`, build 154U) only load and compile the changed classes (`iris_doc_load`, `baseDir` `src/ocutalon/cls`), then write the compiled Storage blocks of FixRun and FixResult back verbatim. Its production is not OcuTalon's: run no test there.
- Tear down only your own tags, also after a failure.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e30s5iw ci/warm.sh up`, once -- expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e30s5iw ci/iris.sh class <Class>`, one call each -- expected: `CLASS … passed`: `OcuTalon.Test.Agent.TriageUserTurn`, `OcuTalon.Test.Agent.Instructions` (unchanged), `OcuTalon.Test.Eval.Cases`, `OcuTalon.Test.Eval.Report`, `OcuTalon.Test.Fix.Executor`, `OcuTalon.Test.Watch.NoticeText`, `OcuTalon.Test.Watch.Lifecycle`, `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Tools.RecentActivity`, `OcuTalon.Test.Tools.CommandCallTime`, `OcuTalon.Test.Tools.Reminders` (unchanged), `OcuTalon.Test.Checks.Runs`, `OcuTalon.Test.Live.Payloads` (unchanged).
- (loop) `<lane> OCUTALON_RUN_TAG=e30s5i ci/iris.sh class <Class>`, fresh, one call each -- expected: passed: `OcuTalon.Test.Fix.Recheck` (Task 0 first), `.Partial`, `.Waits` (about 4-5 min), `.Refused`, `.Stopped`, `.Runs`.
- (loop) `bash docker/tests/test-readme.sh` -- expected: passed.
- (loop) `(cd web && node scripts/payloads.mjs --check && node --test scripts/payloads.test.mjs)` -- expected: exit 0.
- (once) `bash ci/checks.sh` -- expected: every script passes.
- (once) `(cd web && node scripts/catalog.mjs --check)` -- expected: exit 0 (neither new key is a page key).
- (once) `<lane> OCUTALON_RUN_TAG=e30s5i bash eval/run.sh` -- expected: "eval/run: all checks passed", with the "User turns" score line and section printed (inference: about 6-9 min; record its time).
- (once) `<lane> OCUTALON_RUN_TAG=e30s5i ci/iris.sh shard lane-a --part k/8` for k = 1..8, then `shard lane-b --part k/6` for k = 1..6, fresh, one call each -- expected: passed, each part's time recorded.
- (once) `<lane> OCUTALON_RUN_TAG=e30s5iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e30s5i ci/iris.sh teardown`, also after a failure.

**Shared surfaces:** FixRun's columns (+Unreached: `Test.Data.Tables`); FixResult (+Unreached: `ExecutorProbe.SendResult`); the Watch catalog (+2 keys, +1 one form: `Test.Msg.Catalog`; the web allowlist unchanged); the result key order and slots (`Test.Watch.NoticeText`, `Test.Watch.Lifecycle`); the incident payload's Result (+unreached: `payloads.ts`, `Test.Live.Payloads` names seven fields without an exact-set check); Resend's outputs and stop (`Test.Fix.Recheck`); executor behaviour (past expiry: `Test.Fix.Executor`, `Test.Fix.Refused`; the progress; the Sweep gate; an all-stopped Carry); IncidentManager's progress notice (Lifecycle); the eval set's kinds and turn cases (`Test.Eval.Cases`, `Test.Eval.Report`; `Test.Eval.Run` uses its own fixture folders); `CommandCall.Answer`'s `due` (`Test.Tools.Reminders`, online demo off); RecentActivity's output (`Test.Tools.RecentActivity`); README item 2 (`test-readme.sh`). CI: the new live tests run in `shards-2`, about +3 to +5 min (inference). Every test added or changed passes on a fresh environment, in either order; Orders and OrdersFromPartner, when stopped, are started again after the test, also after a failure.

**Pinning mutations (Rule 19).** Apply, observe red, revert byte-identically (`git status --short` and `git diff --stat` unchanged), record `mutation: … → …` here.

| AC or row | Mutation | Expected red |
|---|---|---|
| DW-500, row 20 | drop the paragraph's "Never describe the state of a production" sentence | `Test.Agent.TriageUserTurn` |
| DW-500, row 21 | the scorer ignores absentPhrases | `Test.Eval.Report` (the all-clear reason scores right) |
| DW-500, row 22 | one case's text loses its "?" | `Test.Eval.Cases` TestUserTurnCases |
| AC 2, row 1 | ResultSlots leaves out `resent` | NoticeText; Partial row 1 |
| AC 2, row 1 | Look's skipped is 0 | Partial row 1 (`result.failedAgain`) |
| AC 3, rows 2, 6 | the drop sends no progress | Executor TestStillRunningAfterTheWait; Waits row 6 |
| row 3 | progress counts from the first look | Executor row 3 |
| rows 4, 5 | progress without a tally, or for a marked run | Executor rows 4, 5 |
| AC 3, row 7 | EndLeft keeps the `lastAt < due` gate | Executor row 7; Waits row 6 |
| AC 3, row 9 | ResultKey without the progress rule; Result keeps `$Select(final: …, 1: "")` | NoticeText, Lifecycle row 9; Waits row 6 |
| AC 4, rows 10, 11 | Refusal refuses a past expiry again; the failure branch keeps "not past its expiry" | Executor TestPastExpiryCannotStart, TestStartExecutionFailsForAnApprovedRequest; Refused row 11 |
| AC 5, row 12 | Resend does not stop at `stopped` | Recheck row 12 |
| AC 5, row 13 | copies 0 with unreached ends `done`; NOSTART for `stopped` | Executor row 13, TestNothingResent |
| AC 5, rows 14, 15, 19 | Unreached never saved, or ResultKey ignores it; notTried is Unreached | Executor rows 14, 15, 16, 19 |
| AC 5, row 15 | after a throw, unreached is 0 | Executor row 15 (the throw) |
| row 18 | the one form drops "1 more wasn't" | `Test.Msg.Catalog` (OneForms); NoticeText row 19 |
| row 27 | Incident.cls does not copy Unreached | Executor row 27 |
| AC 6, rows 23-25 | TimeLabel drops " ET"; Answer keeps `ForMessage` | RecentActivity (the onlineDemo 1 case); CommandCallTime rows 24, 25 |
| AC 7, row 26 | `watch.productionStopped`'s `time` slot typed `text` | `Test.Checks.Runs` TestFindingsRender |
| AC 8 | ITEM2 keeps the old line | `test-readme.sh` |
| Storage | the Tables entry lacks `Unreached` | `Test.Data.Tables` |


**Pinning mutations, observed at implementation (Rule 19).** Each was applied to one file, the named class run (warm lane-B stack unless it says fresh), red observed, and the file put back byte-identically (checked with `cmp` against a copy).
- mutation: drop the paragraph's "Never describe the state of a production" sentence from Triage's instructions → red: `Test.Agent.TriageUserTurn` TestUserMessageParagraph.
- mutation: the user-turn scorer ignores absentPhrases → red: `Test.Eval.Report` TestUserTurn (the all-clear reason scores right).
- mutation: one chip case's text loses its "?" → red: `Test.Eval.Cases` TestUserTurnCases.
- mutation: `ResultSlots` leaves out `resent` for failedAndSkipped → red: `Test.Watch.NoticeText` TestResultKeys and TestRestartAndResendTexts.
- mutation: Look's skipped is 0 (the final result of a waited run) → red: `Test.Fix.Executor` TestResendThatErrsPartwaySaysHowFarItGot (3|2|2|0|1 loses its skip). `Test.Fix.Partial` TestSomeFailAgainAndSomeHadChanged (row 1) and TestSomeHadChanged are red with it too (fresh stack, review pass).
- mutation: the drop sends no progress (Pass never calls Progress) → red: `Test.Fix.Executor` TestStillRunningAfterTheWait and TestProgressReportCarriesTheCountsSoFar. `Test.Fix.Waits` TestStillRunningIsReportedThenEnded ("one FixResult goes to IncidentManager when the wait ends", row 6) is red with it too (fresh stack, review pass).
- mutation: the progress tally is kept from the first look, not the latest → red: `Test.Fix.Executor` TestProgressReportCarriesTheCountsSoFar (row 3).
- mutation: Progress does not check Interrupted or the request's executing state → red: `Test.Fix.Executor` TestProgressReportCarriesTheCountsSoFar (a marked run; a request no longer executing).
- mutation: Look keeps the tally of a read that is not read (row 4) → red: `Test.Fix.Executor` TestStillRunningAfterTheWait (the unreadable case sends a report).
- mutation: Sweep leaves a run more than 30 s past its wait (stands for a gate on the time of the last copy; Tally.lastAt is gone) → red: `Test.Fix.Executor` TestSweepEndsARunNoWaiterEnded and TestSweepEndsEveryRunWhoseCopiesAreDone.
- mutation: ResultKey without the progress rule (`'result.Final && 'result.Interrupted`) → red: `Test.Watch.NoticeText` TestResultKeys.
- mutation: IncidentManager Result keeps `$Select(final: ..ResultNotice(...), 1: "")` → red: `Test.Watch.Lifecycle` TestResultNotices (rows 9).
- mutation: Refusal refuses a past expiry again → red: `Test.Fix.Executor` TestPastExpiryCannotStart and, on a fresh stack over three real failed orders, `Test.Fix.Refused` TestPastExpiryCannotStart (row 11; no FixResult, the row stays approved). Execute's own expiry check is not pinned by an outcome (replacing it with `If 0` leaves Refused green, because StartExecution refuses an expired row and the failure branch ends it as NOSTART). The StartExecution-failure branch keeping "not past its expiry" is an equivalent mutant: Execute ends an expired row before it calls Start, so that guard cannot be reached by an expired row.
- mutation: Resend does not stop at `stopped` → red: `Test.Fix.Recheck` TestResendStopsWhereItErrs (row 12).
- mutation: Resend does not stop at `error` (a copy that throws goes to skipped and the loop goes on) → red: `Test.Fix.Recheck` TestResendStopsWhereItErrs (the throwing copy, fresh stack, review pass).
- mutation: copies 0 with unreached ends done (the NOTRUNNING/NOSTART branch is switched off) → red: `Test.Fix.Executor` TestNothingResent and TestResendThatErrsPartwaySaysHowFarItGot.
- mutation: Unreached is never saved with ResentAt → red: `Test.Fix.Executor` TestResendThatErrsPartwaySaysHowFarItGot, TestProgressReportCarriesTheCountsSoFar.
- mutation: after a throw the unreached count is 0 → red: `Test.Fix.Executor` TestRunThatErredAfterACopyStillWaits.
- mutation: ResultKey ignores Unreached → red: `Test.Watch.NoticeText` TestResultKeys and TestRestartAndResendTexts.
- mutation: notTried is Unreached, not Unreached less the copy that erred → red: `Test.Watch.NoticeText` TestRestartAndResendTexts.
- mutation: the one form drops "1 more wasn't" ("1 more weren't") → red: `Test.Msg.Catalog` TestCountOfOneForms.
- mutation: Incident.cls does not copy Unreached → red: `Test.Fix.Executor` TestResendThatErrsPartwaySaysHowFarItGot (the payload check).
- mutation: TimeLabel drops " ET" → red: `Test.Tools.CommandCallTime` TestTimeLabel and TestAnswerDue.
- mutation: Answer keeps `ForMessage` for `due` → red: `Test.Tools.CommandCallTime` TestAnswerDue.
- mutation: `watch.productionStopped`'s `time` slot typed `text` → red: `Test.Checks.Runs` TestFindingsRender.
- mutation: ITEM2 in `docker/tests/test-readme.sh` keeps the old line → red: `test-readme.sh` use-cases.
- mutation: the Tables entry lacks `Unreached` → red: `Test.Data.Tables` TestContracts.
- mutation: TimeLabel ignores `online` (always 0) → red on a fresh stack: `Test.Tools.RecentActivity` TestDemoPath (the online demo's times lose " ET") and TestSharedRulesAreNotCopied (review pass).

**QA additions (Rule 19).** Tests added by the QA stage; each mutation was applied to one file, red observed, and the file put back byte-identically from a copy (`git status --short` and `git diff --stat` equal to their state before).
- (QA) `src/ocutalon/cls/OcuTalon/Test/Eval/Report.cls` TestShippedChipCasesScoreTheHostReasons (DW-500, rows 21-22): the four shipped `eval/user-turn-*/case.json` expectations, not a list written in the test, score the host's model-written all-clear and the three tool-limit reasons wrong (each names the user, so only `absentPhrases` decide) and Triage's own two example reasons right. A reason that describes production state is wrong only when it holds a listed word (the score is lexical, as the spec's list is). mutation: `access` dropped from `eval/user-turn-anything-wrong/case.json` → `Test.Eval.Report` TestShippedChipCasesScoreTheHostReasons red ("no access: scored right"); `Test.Eval.Cases` TestUserTurnCases was already red for the same drop.
- (QA) `src/ocutalon/cls/OcuTalon/Test/Tools/CommandCallTime.cls` TestSetReminderReplyOnTheTool (DW-484, row 25): the reply of the `set_reminder` tool itself (`Tools.ReminderTools` SetReminder, with the CI double behind CommandsIn) carries " ET" after `due` with the online demo on and none with it off; it restores the item's class and the setting and is skipped (no failure) where no production runs, as on the warm stack, so it ran on a fresh stack (`e30s5q`). mutation: `CommandCall.Answer`'s `due` uses `Data.Time.ForMessage` again → `Test.Tools.CommandCallTime` TestSetReminderReplyOnTheTool red (and TestAnswerDue).
- (QA) re-demonstrated (no change of the test): mutation: the whole user-message paragraph removed from `Agent/Triage.cls` INSTRUCTIONS → `Test.Agent.TriageUserTurn` TestUserMessageParagraph red (all eleven phrase pins).

**Code review additions (Rule 19, 2026-11-02).** Each mutation was applied to one file, the named class run (warm `e30s5crw` unless it says fresh `e30s5cr`), red observed, and the file put back from a copy (checked with `cmp`, with `git status --short` and `git diff --stat` as before). Every class was green again afterwards, on the same warm stack where it ran warm.
- mutation: the sentence "This holds also when the user asks OcuTalon to resend, approve or change something: …" removed from Triage's instructions → red: `Test.Agent.TriageUserTurn` TestUserMessageParagraph (its two new phrase pins). `Test.Agent.Instructions` (unchanged) and `Test.Agent.Runners` are green with the sentence.
- mutation: `Execute`'s early expiry check switched off (`If 0 && …`) → red: `Test.Fix.Executor` TestPastExpiryCannotStart (`zz_fix`: reason UNUSABLE, not NOSTART). This replaces the earlier note that the check was not pinned by any outcome.
- mutation: `Pass`'s throw path keeps a default tally → red: `Test.Fix.Executor` TestStillRunningAfterTheWait ("a read that throws keeps no tally").
- mutation: `CommandCall.Listed`'s due uses `Data.Time.ForMessage` again → red: `Test.Tools.CommandCallTime` TestListedDue (DW-559). `Test.Tools.Reminders` (unchanged) is green on a fresh stack with the patch.
- mutation: RecentActivity skips `WatchAnswers.WatchNames` (`Kill names`) → red on a fresh stack: `Test.Tools.RecentActivity` TestAnotherSession, TestDemoPath, TestPoisoned and TestProductionName (AC 6, DW-519 display-name half).
- `Test.Tools.CommandCallTime` passed on a fresh stack with TestSetReminderReplyOnTheTool executed (no SKIP line), and on the warm stack too.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** DW-500 first (Triage's user-message paragraph, the `user-turn` evaluation kind and four chip cases; the web fallback is closed), then the Story 30.5 items: the progress `FixResult` when the wait ends with copies running and Sweep's gate removed, `Unreached` and the stop at the first copy that errs with `result.stoppedPartway` (three counts, one form), couldn't-start for no copy made, a past-expiry approved Execute ending as NOSTART, `resent` in the mixed result's slots, `unreached` on the incident payload, DW-519 (shared `WatchNames` and `CommandCall.TimeLabel`), DW-484 (the zone label on the reminder reply's `due`), DW-469 (a pin on the stop and disabled-item times), and the README sentence.

**Files changed.** `Agent/Triage.cls`, `Eval/In.cls`, `Eval/Report.cls`, `eval/user-turn-*/case.json` (4 new), `Data/FixRun.cls`, `Fix/Msg/FixResult.cls`, `Fix/Executor.cls`, `Fix/Run.cls`, `Fix/Kind/RepairResend.cls`, `Watch/Notice.cls`, `Msg/Catalog/Watch.cls`, `Watch/IncidentManager.cls` (the one-line `Result()` edit), `Live/Payload/Incident.cls`, `Live/Payload/Part/IncidentRequestResult.cls`, `web/src/app/live/payloads.ts` (generated), `Tools/WatchAnswers.cls`, `Tools/CommandCall.cls`, `Tools/RecentActivity.cls`, `README.md`, `docker/tests/test-readme.sh`, and the tests under `Test/` (new: `Agent/TriageUserTurn`, `Tools/CommandCallTime`).

**Footprint notes for the lead.** `Test/Live/Payloads.cls` (Epic 11's file) gained one line in its Contracts XData (`Unreached` in the request-result contract), forced by the payload field the lead's gate ruled; it is append-only and mechanical. `Test/Agent/Runners.cls` now expects Triage's system block to be cache-marked (its instructions now reach min_tokens_for_cache).

**Review.** 27 findings (26 from the four layers, one from the shard run): patches applied 4 (live mutation evidence for Partial, Waits and RecentActivity; Resend's `error` branch case in `Test.Fix.Recheck`; `Test.Fix.Refused` over real failed orders; `Test.Agent.Runners`' Triage expectation), deferred 1 (the reminders list's due time has no zone label), 22 rejected with the reasons in the Review Triage Log (spec-bound texts, Story 31.2's page pick, a millisecond race the receiver handles, equivalent mutants). Patched by verdict: high 1, medium 3. Follow-up review recommended: false (the one high was a stale test expectation found and fixed by the shard run).

**Verification.** Loop classes passed warm and fresh (see Design Notes); this pass on fresh stacks: `Test.Fix.Recheck`, `Refused` and `Tools.RecentActivity` green, and red under their mutations; `Partial` and `Waits` red under theirs. Once-lines: `bash ci/checks.sh` passed (11 min 24 s), `catalog.mjs --check` passed, `eval/run.sh` passed (123 s; "User turns | 0 | 4" printed, the mock falls back), `payloads.mjs --check` and `payloads.test.mjs` passed, `test-readme.sh` passed; `shard lane-a` parts 1-8 (442, 165, 157, 210, 442, 472, 297, 383 s) and `shard lane-b` parts 1-6 (184, 185, 149, 207, 559, 142 s) all passed (part 1/8 first failed on `Test.Agent.Runners`, fixed, then passed). Warm `e30s5iw` and fresh `e30s5i` stacks are torn down.

**Residual risks.** Real Haiku's wording for the four chips is not provable on the mock; the release-candidate run and the Contest Planner's host check decide DW-500. The page still picks its result text from counts until Story 31.2 reads `unreached`.
