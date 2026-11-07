---
title: "Story 39.9: Heartbeat follow-up: today's cost matches its check-ins, and the tidy-ups"
type: 'bugfix'
created: '2026-11-07'
status: 'done'
baseline_revision: '9fce6cbee980dfea2cc4dc2d2d09b9a4b7f2d3c9'
baseline_commit: '9fce6cbee980dfea2cc4dc2d2d09b9a4b7f2d3c9'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** On the 1.0.2 online demo the Heartbeat card read "Last check-in 12:20 PM · Offered an action · $0.0003 · Trace" but "Today: 1 check-in, $0.0006" (DW-824): the last check-in shows only its Triage decision's cost, while Today also counts the read-only turn that an Act runs on the same Item. Three tidy-ups ride along: a 60-minute schedule reads "Every 1 hour", two docker test scripts repeat one security-overview rule (DW-785), and the GuideApi flake prints no fingerprints when it fails (DW-670).

**Approach:** The last check-in's cost becomes the sum of the same Usage rows that Today counts for that check-in's Item (its decision and, on Act, its read-only turn), computed when the view is built, so the two lines always agree and no shown text changes. Then: "Every hour" for 60 minutes (ruled text), one sourced helper for the shared overview rule, and both fingerprints in GuideApi's failure messages.

## Boundaries & Constraints

**Always:**
- Items 1 and 2 (DW-824, "Every hour") come first and are complete and verifiable alone. Items 3 and 4 touch only `docker/tests/` and `Test/Web/GuideApi.cls`, which items 1 and 2 never touch.
- The check-in's cost is the sum of `CostUSD` of the session's own `OcuTalon.Bridge.Data.Usage` rows with `Channel` `heartbeat` and `ItemId` = the row's `LastItemId`: the very rows `Ownership.HeartbeatToday` counts for that Item. It is read in `Live.Payload.Heartbeat.FromRow`, so the `heartbeat` event and `GET /api/v1/heartbeat` keep one view (they cannot drift).
- A pending beat (`LastDecisionRef` empty) has no `lastCostUSD`, as today. A failed Usage read gives no `lastCostUSD` (the card then shows no cost), never a partial number.
- `HeartbeatBeat.LastCostUSD` keeps recording the decision's own cost (AD-18's "records its cost"); `Checks.Beat` is not changed.
- "Every hour" strings are used exactly as ruled (PUBLIC TEXT, Planner 2026-11-06): "Every hour" and "Every hour, {from} to {to}". Every other interval's line and the Interval picker's labels stay byte-identical.
- Both docker scripts print byte-identical output before and after the refactor, on the real tree and under each docs mutation below. No pin is deleted or weakened.
- GuideApi's assertions keep their descriptions on pass; only a failing assertion's message adds the values.
- Tests that need the person's heartbeat off on a running production save `on` 0 first (Story 39.8's hermeticity rule); every test removes the rows and keys it made.

**Never:**
- Change any other shown string, the Today line's wording, the catalog, or the outcome texts.
- Edit `Checks/Beat.cls`, `Checks/Process.cls`, `Core/SettingsOps.cls`, `Core/Intake.cls`, the bridge (`src/bridge/**`), `Watch/**`, `Digest/**`, `Msg/Catalog/**`, `web/src/app/guide/**`, `web/src/app/live/**`, `release/**`, `eval/**`, `docker/tests/lib-security-overview.sh`, `docker/tests/test-security-overview.sh`, or `ci/mock/**`.
- Add a storage property, a table, an event type, an index, a scheduler or a mock scenario.
- Fix the GuideApi race (its cause is not plain and not in Epic 39's code; see Design Notes).
- Amend EXPERIENCE.md (it does not quote "Every 1 hour"; see Design Notes).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| One check-in that acted (DW-824) | Row: `LastItemId` I, `LastDecisionRef` D, `LastOutcome` act, `LastCostUSD` 0.0003. Today's heartbeat Usage rows of the session: I/decide 0.0003, I/turn 0.0003. | GET: `lastCostUSD` 0.0006, `today` {"checkIns":1,"costUSD":0.0006}. Card: "Last check-in … · Offered an action · $0.0006 · Trace" and "Today: 1 check-in, $0.0006". | none |
| One decide row only (ignore, tell now, digest) | Usage: I/decide 0.0004. | `lastCostUSD` 0.0004, the same as before this story. | none |
| Two check-ins today | Usage: I1 0.0002 + 0.0002, I2 (the row's item) 0.0003. | `lastCostUSD` 0.0003; Today 2 check-ins, 0.0007. | none |
| Rows that are not the check-in's | Of I: a row of another session and a row of channel `web`. A row of another item. | None of them is in `lastCostUSD`. | none |
| Pending beat | `LastDecisionRef` empty. | No `lastCostUSD` member. | none |
| Turn still running at the recording tick | The Settle event is built before the turn's Usage row lands. | Both lines show the decision's cost alone (they agree). The next read (next event or reload) shows both with the turn. Follows from the one read; not separately pinned. | none |
| Failed Usage read | `CheckInCost` answers an error status. | No `lastCostUSD`; the view is otherwise built (as `Payload.Decision` treats a failed `TurnOfItem`). Not pinned: no fixture makes the read fail. | the GET's `today` read reports its own status, as today |
| 60 minutes with hours | interval 60, 07:15 to 21:45, next due. | "Every hour, 07:15 to 21:45 · Next check-in {time}" | none |
| 60 minutes all day | interval 60, both hours empty (or equal). | "Every hour" (plus " · Next check-in {time}" when due). | none |
| Other intervals | 30, 120, 240, 480, 1440. | "Every 30 minutes, …", "Every 2 hours, …", …, "Every 24 hours" exactly as before; the picker still lists "1 hour". | none |

</intent-contract>

## Code Map

**Item 1 (DW-824): the finding, with evidence.** Today sums every heartbeat Usage row of the session's day; the last check-in shows only the Triage decision's cost. The extra $0.0003 is the read-only turn that Act runs on the same Item. It is not a second beat (that would be a second ItemId, so 2 check-ins), not the notice (`OutcomeRouter` sends act to `Notify` through the code-written `Core.Rule.Notice`, `Core/Rule/Outcome.cls` 25-26, no model call) and not the run-now itself (the run-now *is* the beat). In the walk the decision was recorded on the tick after the turn had finished, so the GET that the event triggered held both rows in Today and only the decision's cost on the last line. Evidence is the code path below; no slot measurement was made (slot D holds no demo data and runs no production), and `TestGetCheckInCost` and `TestAct` reproduce it.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - `HeartbeatToday` 115-147: sums `CostUSD` of every Usage row with `OwnerRef` = session and `Channel` 'heartbeat' in the cap's day, and counts distinct non-empty ItemIds. Its doc at 118 already says "an Act's read-only turn shares the beat's Item". Statement `heartbeatUsage` at 849-851.
  - `TurnCost` 74-91 (the sibling shape: `Rows` then `Sum`); `Sum` 152 (private); `Rows` 750; `DecisionOfItem` 419-433 with `decisionOfItem` 905-907 (`Kind = 'decide'` only).
- `src/ocutalon/cls/OcuTalon/Core/Intake.cls`: `Decided` 179-191: on a non-fallback act it sends Decide a `turn` request built by `RequestFor(item, "turn", ...)` (185), and `RequestFor` 151-163 copies the Item's `ItemId`, `Channel` (heartbeat) and `OwnerRef` (the session). Read only.
- `src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls` `NewRow` 160-172: the Usage row takes `DecisionRef`, `ItemId`, `Kind`, `OwnerRef` and `Channel` from the request, so the turn's row is a heartbeat row of the same Item. `Bridge/Process/Decide.cls` 1293-1298: a Decision's `CostUSD` is `Usage.Totals(decisionRef)`, its own rows only. Read only.
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls` `Settle` 566-588: `LastCostUSD = decision.CostUSD` (574) of the `decide` Decision. Read only.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Heartbeat.cls` `FromRow` 57-82: `payload.LastCostUSD = row.LastCostUSD` (72); property doc 32-33; class doc 1-4. The one place to change.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` `Heartbeat` 405-438: the GET is `FromRow`'s export plus `today` (432). Read only; unchanged.
- `web/src/app/rail/heartbeat-card/heartbeat-card-view.ts` `lastLine` 188-209 (cost at 199-201) and `todayLine` 212-219; `heartbeat-card.ts` 79-81 re-reads the GET on every `heartbeat` event, so both lines always come from one GET. Read only.
- Sibling precedent for a payload that reads Ownership: `Live/Payload/Decision.cls` 103-108 (`TurnOfItem`, tolerant of a failed read).
- Tests that pin `lastCostUSD` today:
  - `Test/Live/Payloads.cls` `TestHeartbeatFromRow` 502-545 (row with `LastCostUSD` 0.012345, no Usage rows; asserts .012345 at 522 and 531);
  - `Test/Checks/Runs.cls` 1136-1147 (fixture decide Decision `CostUSD` 0.0025 at 1138, no Usage row) and 1344-1357 (0.0031 at 1346); its `BeatViewOf` 1803-1807 is `FromRow` itself;
  - `Test/Core/SettingsHeartbeat.cls` 328-360 and `Test/Checks/Heartbeat.cls` (`ViewOf`) compare with `FromRow` itself: unaffected;
  - `Test/Checks/Beat.cls` 132-147, 370-418 and `Test/Checks/Heartbeat.cls` 420 assert the row's field: unaffected.
- `src/ocutalon/cls/OcuTalon/Test/Web/HeartbeatApi.cls`: `TestGetRowView` 169-198 is the shape to follow (fixture session, row, `..Get(.response)`); class doc 1-19; real production, fresh stack.
- `src/ocutalon/cls/OcuTalon/Test/Checks/BeatOutcomes.cls` `TestAct` 147-208 (real production, CI mock `heartbeat-act`, which answers the decision then the turn); helpers `Start` 271, `WaitDecision`, `Tick` (Test.Watch.Case 682); `Test.Agent.RunnerFixture.DecisionOf(item, "turn")`; `Test.Core.Observe.Events(session, "heartbeat")`.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` `Usage(decisionRef, ownerRef, fields)` 160-173 (fields `ItemId`, `Kind`, `Channel`, `CostUSD`, `RecordedAt`; kept and removed with the fixture's rows); `SettingsHeartbeat.Usage` 554-557 shows the call.

**Item 2 ("Every hour"):**
- `web/src/app/rail/heartbeat-card/heartbeat-card-view.ts`: `HEARTBEAT_TEXTS.every` 27, `everyHours` 28, `intervals` 62 (picker labels, unchanged); `stateLine` 138-152 (the line is built at 149); module doc 5-8.
- `web/scripts/heartbeat-card-view.test.mjs`: the texts' `deepEqual` 54-97; `stateLine` cases 159-174 (the 60-minute expectations at 163 and 169-173).
- `web/scripts/ux-strings.test.mjs`: the `ux` heartbeat block 501-531; `ac` 542-560; `ruled` 562-570.
- `web/e2e/heartbeat-card.spec.ts` 416-421: a stubbed GET with interval 60 expects "Every 1 hour, 07:15 to 21:45 · Next check-in …" (uses `clock(iso, LOCALE, ZONE)`, keep it).
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` 1003: "Every {interval}, {from} to {to} · Next check-in {time}" and the picker list "30 minutes, 1 hour, 2, 4, 8 or 24 hours". No "Every 1 hour" anywhere (searched): no amendment.

**Item 3 (DW-785):**
- `docker/tests/test-triage-heartbeat.sh` `chk_overview` 56-72 (the beat sentence once, inside the model-requests bullet under "Data leaves the instance only:", no heading between); its synthetic overviews 84-119 and self-test 131-135; `SENTENCE` 17, `OVERVIEW` 16.
- `docker/tests/test-heartbeat-overview.sh` `chk_runnow` 21-37 (the same awk, with the placed text "$BEAT $SENTENCE"); `good_overview` 39-44 and variants 46-72; `BEAT` 15.
- Helper conventions: `docker/tests/lib-security-overview.sh` 1-3 (header "sourced and never run", plain functions, state only in `$tmp`), sourced by `test-security-overview.sh:28` as `. "$(dirname "$0")/lib-security-overview.sh"`.
- `ci/units.sh:168`: `docker/tests/lib-*.sh` is an IRIS input (a change runs every IRIS group); `:186` `test-*.sh` are not. Both scripts are `CHECK_SCRIPTS` (hosted `checks` job, `ci/units.sh:6,12`).

**Item 4 (DW-670):**
- `src/ocutalon/cls/OcuTalon/Test/Web/GuideApi.cls`: `TestRunAgain` 75-104 (the `done` assertion at 90-94); `TestOnlyTheMarkerChanges` 142-168 (Fingerprint assertions at 160, 163 and 164); `Fingerprint` 194-229. `%UnitTest.TestCase.AssertEqualsViaMacro` (irislib) prints neither value when a description is given.

## Tasks & Acceptance

**Execution (in this order; items 1 and 2 first):**

Item 1, DW-824:
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- add `CheckInCost(sessionRef As %String, itemId As %String, Output sc As %Status) As %DynamicObject`: the `Sum` of `Rows("checkInUsage", sessionRef, .sc, itemId)`, the new statement `SELECT ID FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ? AND Channel = 'heartbeat' AND ItemId = ?` (class `OcuTalon.Bridge.Data.Usage`, binds "oa"), shaped like `TurnCost`; an empty `itemId` or a failed read gives {} and an error status. Add one sentence to `HeartbeatToday`'s doc: a check-in's own rows are `CheckInCost`'s, so Today's cost is the sum of its check-ins' costs. -- one rule for both lines (AD-20: totals that add up).
- `src/ocutalon/cls/OcuTalon/Live/Payload/Heartbeat.cls` -- in `FromRow`, when `row.LastDecisionRef '= ""`, set `LastCostUSD` to `CheckInCost(row.SessionRef, row.LastItemId, .sc).costUSD` when `sc` is OK, else ""; when `LastDecisionRef` is "", "" (as today). Update the property doc ("the cost in USD of the last check-in: its Item's heartbeat Usage rows, its decision and on act its read-only turn, the rows Today counts"), the class doc and `FromRow`'s doc. -- the event and the GET share it.
- `src/ocutalon/cls/OcuTalon/Test/Web/HeartbeatApi.cls` -- new `TestGetCheckInCost` (the pinning regression of DW-824's case; matrix rows 1, 3, 4, 5): `Guard`, fixture session with `on` 0, a row like `TestGetRowView` with `LastItemId` I, `LastDecisionRef` D, `LastOutcome` act, `LastCostUSD` 0.0003; `Fixture.Usage` rows recorded now: (D, I, decide, heartbeat, 0.0003) and (T, I, turn, heartbeat, 0.0003), plus a row of I on channel `web` (0.5), one of I owned by another fixture session (0.7) and one of another item J (0.0001). GET: `today` is {"checkIns":2,"costUSD":0.0007} and `lastCostUSD` is .0006 (assert `+answer.lastCostUSD = (+answer.today.costUSD - 0.0001)` and the literal .0006); then remove J's row and GET again: `today` {"checkIns":1,"costUSD":0.0006} equals `lastCostUSD` .0006 (the 1-check-in, 2x-cost case). Then clear `LastDecisionRef` and GET: no `lastCostUSD` member. Class-doc entry. -- outermost server surface the card reads.
- `src/ocutalon/cls/OcuTalon/Test/Checks/BeatOutcomes.cls` -- extend `TestAct` (Integration AC, real production and mock): after the turn Decision exists, wait (bounded by `WAITDIAGNOSIS`) until `Ownership.CheckInCost(session, item.itemId).costUSD` exceeds `decision.CostUSD`; assert `turn.CostUSD > 0` (control: the case has two costs); `Tick` at `case.t0` + 60 s (records the decision, not due); the last `heartbeat` event's `payload.lastCostUSD` equals `decision.CostUSD + turn.CostUSD`, and equals `Ownership.HeartbeatToday(session).costUSD` with `checkIns` 1. Class-doc bullet. -- real Checks, Intake, Decide.
- `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls` -- `TestHeartbeatFromRow`: keep `LastCostUSD` 0.012345 on the row but seed `Fixture.Usage` rows of the row's session and item I on channel heartbeat (0.0002 and 0.0003) and one on channel web; assert `LastCostUSD` .0005 in the payload and the JSON (522, 531), and that a row with `LastDecisionRef` "" exports no `lastCostUSD`; remove the rows after. Doc of the test.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls` -- at 1138 and 1346 also seed `Fixture.Usage(decision, <person>, {"ItemId": <item>, "Kind": "decide", "Channel": "heartbeat", "CostUSD": <the same cost>})` (the fixture records it under the decision's ref, which `..Refs` already holds, so the class's cleanup removes it), so the expected .0025 and .0031 stand. Search `src/ocutalon/cls/OcuTalon/Test` and `web/e2e` for any other `lastCostUSD` assertion on a server-built view and update it the same way.

Item 2, "Every hour":
- `web/src/app/rail/heartbeat-card/heartbeat-card-view.ts` -- add `everyHour: 'Every hour'` and `everyHourHours: 'Every hour, {from} to {to}'` to `HEARTBEAT_TEXTS`; `stateLine` uses them when `state.interval === 60`, else `every`/`everyHours` as today; update the module doc and `stateLine`'s doc. `intervals` unchanged.
- `web/scripts/heartbeat-card-view.test.mjs` -- the texts' `deepEqual` gains the two keys; the 60-minute expectations read "Every hour, 07:15 to 21:45 · Next check-in 14:30", "Every hour · Next check-in 14:30", "Every hour, 07:15 to 21:45", "Every hour"; add a fixed-strings case for every offered interval with hours and all day: 30 "Every 30 minutes", 120 "Every 2 hours", 240 "Every 4 hours", 480 "Every 8 hours", 1440 "Every 24 hours"; and `intervalName(60)` and `INTERVALS` still give "1 hour".
- `web/scripts/ux-strings.test.mjs` -- add 'Every hour' and 'Every hour, {from} to {to}' under `ac` with the key `'Story 39.9: Heartbeat follow-up (the 60-minute schedule line "Every hour, …" and "Every hour" all day; PUBLIC TEXT ruled by the Contest Planner 2026-11-06, relayed by the orchestrator)'`.
- `web/e2e/heartbeat-card.spec.ts` -- line 420's expectation becomes `` `Every hour, 07:15 to 21:45 · Next check-in ${clock(nextDueAt, LOCALE, ZONE)}` ``.

Item 3, DW-785:
- `docker/tests/lib-heartbeat-overview.sh` (new, ASCII, `bash -n` clean, sourced and never run, header in the style of `lib-security-overview.sh`) -- holds `HEARTBEAT_OVERVIEW="docs/security-overview.md"`, `HEARTBEAT_BEAT_SENTENCE` (the beat sentence, verbatim) and `overview_bullet_rule <rule> <file> <sentence> <placed> <what> [<how>]`, which prints `<rule>: <file> holds <what> <n> times, not once` when the sentence is not there exactly once, and `<rule>: <file> does not hold <what><how> in the line '- In model requests to the configured provider' under 'Data leaves the instance only:'` when `<placed>` is not inside that line of that section with no heading between (the awk of both scripts today, moved once).
- `docker/tests/test-triage-heartbeat.sh` -- source the helper; `chk_overview` becomes a one-line call with rule `overview`, sentence = placed = the beat sentence, what `the sentence about a heartbeat check-in`, how empty. Synthetic files, self-tests and PASS/FAIL lines unchanged; header comment names the helper.
- `docker/tests/test-heartbeat-overview.sh` -- source the helper; `chk_runnow` becomes a one-line call with rule `runnow`, sentence = the run-now sentence, placed = "$BEAT $SENTENCE", what `the run-now sentence`, how ` directly after the beat sentence`. The rest unchanged; header names the helper.

Item 4, DW-670:
- `src/ocutalon/cls/OcuTalon/Test/Web/GuideApi.cls` -- in `TestOnlyTheMarkerChanges`, read each after-fingerprint into a variable and, only when it differs, append `": before "_before_" after "_after` to the description (all three assertions; `other` likewise). In `TestRunAgain`, when `done '= "10000"`, append the `done` value, `view.%ToJSON()` and `..Fingerprint(ref)` to that assertion's description. Class doc: one line saying the fingerprint assertions print both fingerprints when they fail. No other change.

**Acceptance Criteria:**
- AC 1 (DW-824) -- Given a session whose only check-in today decided Act and ran its read-only turn, when the card reads `GET /api/v1/heartbeat` (and on each `heartbeat` event), then `lastCostUSD` equals `today.costUSD` (the decision plus its turn), so "Last check-in … · $0.0006" sits beside "Today: 1 check-in, $0.0006"; a check-in with only a decision keeps its cost as before; a pending beat shows none; and no shown string changes (AD-20, AD-18, AD-12).
- AC 2 -- Given a heartbeat interval of 60 minutes, when the card's state line is shown, then it reads "Every hour, {from} to {to}" (or "Every hour" all day), and every other interval and the Interval picker's labels read exactly as before (PUBLIC TEXT ruled 2026-11-06).
- AC 3 (DW-785) -- Given `docker/tests/test-heartbeat-overview.sh` and `docker/tests/test-triage-heartbeat.sh`, when each runs, then its security-overview rule comes from `docker/tests/lib-heartbeat-overview.sh`, and its output is byte-identical to the output before this story on the real tree and under each docs mutation of Verification.
- AC 4 (DW-670) -- Given `OcuTalon.Test.Web.GuideApi`, when `TestOnlyTheMarkerChanges` fails on a fingerprint or `TestRunAgain` fails on its steps, then the failure line carries both fingerprints (or the steps, the view and the fingerprint); passing runs print as before.
- Integration AC (Rule 1) -- Given the real production and the CI mock's `heartbeat-act`, when a beat acts and the next Tick records its decision, then the `heartbeat` event that `Checks` publishes (through `FromRow`, the consumer of `Ownership.CheckInCost`) carries `lastCostUSD` = decision cost + turn cost = `Ownership.HeartbeatToday(session).costUSD`, with one check-in.
- Integration AC (helper) -- Given the shared helper, when its section-reset rule is broken, then both `test-triage-heartbeat.sh` (overview self-test) and `test-heartbeat-overview.sh` (runnow self-test) print FAIL for their `heading` variant.
- AC 5 -- Given the tests above, when each pinning test's mutation of Verification is applied, then it goes red, and the tree is byte-identical after the revert (Rule 19).

### Review Findings

Code review 2026-11-07 (four layers, full-opus tier; 25 raw findings, 8 entries after grouping, 17 rejected). Each entry: severity | fix-risk | footprint | spec-status -> disposition.

- [x] [Review][Patch] `BeatOutcomes.cls` had a hunk outside the ruled `TestAct` hunk (the class-doc bullet), against the orchestrator's plain-union ruling [src/ocutalon/cls/OcuTalon/Test/Checks/BeatOutcomes.cls:12] -- high | low (doc-only revert) | in-story | clear -> fixed: class doc back to the baseline; the behavior is described by the comment inside `TestAct`; merge-file re-run exit 0. (acceptance-auditor)
- [x] [Review][Patch] `TestAct`'s event assertion depended on no real Tick recording the decision before the turn's Usage row landed (`RunDue` settles every pending row; the real `HeartbeatIn` ticks every minute; that event holds the decision's cost alone and the test's own Tick then publishes nothing) [src/ocutalon/cls/OcuTalon/Test/Checks/BeatOutcomes.cls:224] -- med (Rule 19 hermeticity) | low | in-story | clear -> fixed: when the last event holds the decision's cost alone, the view is built again from the row, as the GET and the next event build it; the AC 1 mutation still turns `TestAct` red (fresh). (verification-gap)
- [x] [Review][Patch] After the bridge purge (AD-27, 90 days) deletes a check-in's Usage rows, `lastCostUSD` read 0 ("<$0.0001") instead of the decision's recorded cost, against AC 1's "a check-in with only a decision keeps its cost as before" [src/ocutalon/cls/OcuTalon/Live/Payload/Heartbeat.cls:80] -- med | low | in-story | clear -> fixed: the check-in's cost is never below the row's own `LastCostUSD` (the decision's rows are a subset of the Item's rows, so only a purge makes the sum smaller); `TestHeartbeatFromRow`'s row cost became 0.000234 (still distinct from the sum 0.0005) and gained the purged case; mutation recorded. DW-437 (same root cause, the purge leaves rows that read 0) got an occurrence. (blind-hunter+acceptance-auditor)
- [x] [Review][Patch] Doc comments claimed more than the code keeps: "Today's cost is the sum of its check-ins' costs", "the rows HeartbeatToday counts", "the event and the GET can't drift", and the property's empty cases left out the empty-Item case [src/ocutalon/cls/OcuTalon/Data/Ownership.cls:120] -- low | low | in-story | clear -> fixed: the docs of `HeartbeatToday`, `CheckInCost`, the payload class, `LastCostUSD` and `FromRow` now state the no-day-bound rule, the late-turn view, the purge floor and the empty cases (Rule 14). (blind-hunter+acceptance-auditor)
- [x] [Review][Patch] The failed-read matrix row was left unpinned on a false premise ("no fixture makes the read fail": an empty `SessionRef` does) [src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls:579] -- low | low | in-story | clear -> fixed: `TestHeartbeatFromRow` asserts a failed read exports no `lastCostUSD`; with the purge floor the `IsOK(sc)` guard is no longer redundant, and its removal turns the test red (mutation recorded). (verification-gap)
- [x] [Review][Patch] The fixed-strings case was titled "every other offered interval" but hard-coded the list, so a new interval would go untested [web/scripts/heartbeat-card-view.test.mjs:186] -- low | low | in-story | clear -> fixed: the case asserts its minutes plus 60 are `INTERVALS`; mutation (a 720-minute interval) red. (blind-hunter)
- [x] [Review][Patch] QA's HC8 mutation line labelled the stubbed-GET step as AC 1's pin and its red was seen only in the failed-test list [_bmad-output/implementation-artifacts/spec-39-9-heartbeat-follow-up-today-s-cost-matches-its-check-ins-and-t.md, ## Verification] -- low (Rule 19 stale line) | low | in-story | clear -> fixed: the line now names what the step pins (the card's rendering of a cost under $0.001 on both lines) and that HC8's red is the new step by elimination (every other HC8 cost is 0.0012 or more; checked by reading HC8). Judged adequate for a rendering pin; AC 1 itself is pinned by `TestGetCheckInCost`, `TestHeartbeatFromRow` and `TestAct`. (blind-hunter+verification-gap)
- [x] [Review][Defer] `CheckInCost` has no day bound while Today is day-bounded, so a check-in whose turn lands after instance-zone midnight reads more on "Last check-in" than on "Today" [src/ocutalon/cls/OcuTalon/Data/Ownership.cls:152] -- low | low | in-story | spec-bound -> closed `by-design` (DW-859): the Task's SQL and Design Notes sum all of the Item's rows; a day bound would blank or shrink yesterday's last check-in while Today is empty; AC 1's Given (the only check-in today) holds. (edge-case-hunter+acceptance-auditor)

**Rule checks:** Rule 3 met (the card's two changed lines are asserted in the real browser by HC8; the server change runs on the real production in `TestAct` and through `GetHeartbeat` in `TestGetCheckInCost`). Rule 6: AD-20 (totals in the ownership API beside `TurnCost`), AD-12 (a full current view of one entity), AD-18 (the row still records the decision's cost) and AD-29/AD-33 hold; no mismatch. Rule 1: two Integration ACs present. Rule 2: `CheckInCost` extends `Rows`/`Sum`; the helper removes the copy. Release freeze: no frozen path touched. Shown strings: only "Every hour" and "Every hour, {from} to {to}". DW-785: both scripts check what they checked before. DW-670: diagnostics only.

**Rejected:**
- `false` %EXACT on `OwnerRef`/`ItemId` (edge): refs are 128-bit random (`Bridge.Ids.NewRef`), and Today's `heartbeatUsage` uses the same collation, so the two lines share one partition.
- `low` failed read not logged (edge): the precedent `Payload.Decision`'s `TurnOfItem` read is tolerant and silent; logging adds a branch for a rare path.
- `low` `TestGetCheckInCost` could race a real Tick (edge): the window is the milliseconds between `..Session()` and the off `Put`; a pending row with no Decision settles as a no-op.
- `false` the event can hold a partial cost (edge): the matrix's "Turn still running" row rules it; the doc now says so (patched entry above).
- `false` AD-18/AD-12 contradicted (auditor): no AD Rule is contradicted; the reading of "the row's public view" is the spec's, with `Payload.Decision` as precedent.
- `false` `Payloads.cls` hunks past L545 (auditor): every hunk is in `TestHeartbeatFromRow` or its own doc comment (the method had grown past the ruling's approximate range); merge-file exit 0.
- `low` `If ..Tick() = "" Quit` skips `AssertNoCheck` (auditor): only on an already-red path; sibling tests use the same line.
- `low` the Review Triage Log's counts disagree with the Auto Run Result (blind): a spec edit.
- `low` triage row 13's reason is wrong and the Usage rows leak if the method throws (blind): only on a runtime error, and the class doc is outside the ruled hunk.
- `low` cycle-log `dev_complete` row has shifted fields and two rows lack timestamps (blind+auditor): the lead's log, not code.
- `low` the helper's `lib-*` name makes it an IRIS input in `ci/units.sh` (blind): the spec names the file and its Code Map cites the rule; it costs CI time only when the helper changes.
- `low` frontmatter `status: done` vs sprint `review`, and the Verification's `git diff` baseline 4497f660 (auditor): build-auto's machine state and a spec edit.
- `low` AC 4's diagnostics have no standing test (verification-gap): the one-off mutations proved them; not worth automating.

## Spec Change Log

- 2026-11-07 (lead, spec gate): the charter's home-lane line amended to "A and B" (apply-and-report). Three planned edits sit on paths in other in-flight epics' diffs: `Test/Live/Payloads.cls` and `web/scripts/ux-strings.test.mjs` (Epic 4) and `Test/Checks/BeatOutcomes.cls` (Epic 17). Each planned hunk is disjoint from the other epic's (Payloads: theirs at XData Contracts ~L1069, ours `TestHeartbeatFromRow` 502-545; ux-strings: theirs L63 and ~L411-440, ours one new `ac` entry ~L560; BeatOutcomes: theirs a `Session` override after `TestWatchRunsAgain` ~L265, ours inside `TestAct` 147-208), a plain union. The orchestrator rules on them before the implement spawn (dispatch rule); the ruling is recorded here.
- 2026-11-07 ~06:55Z (orchestrator ruling, decide): PLAIN UNION for all three paths. Edit ONLY the named hunks: `Test/Live/Payloads.cls` `TestHeartbeatFromRow` (L502-545); `web/scripts/ux-strings.test.mjs` one new `ac` entry under the Story 39.9 key; `Test/Checks/BeatOutcomes.cls` inside `TestAct` (L147-208) only, kept here for the real-production coverage (not moved to `Runs.cls`). Before finalize, each is proved with `git merge-file` against the other epic's current origin version (Payloads.cls and ux-strings.test.mjs vs `origin/OCT-epic4`, BeatOutcomes.cls vs `origin/OCT-epic17`): exit 0, or a conflict confined to count lines resolved as both sides. DW-824's approach is accepted (the last check-in cost = the sum of the Item's heartbeat Usage rows through `Ownership.CheckInCost` in `FromRow`; no string changes).

## Review Triage Log

### 2026-11-07 -- Review pass
- verdicts: 22 findings -- high 0, medium 0, low 16, false 6, maybe-false 0
- findings:
  - `[low]` `[reject]` blind: `checkInUsage` has no ItemId index, so each read scans the owner's Usage rows -- the intent forbids adding an index; the owner's rows per day are few.
  - `[low]` `[reject]` blind: `CheckInCost` has no day bound while Today has one, so a check-in across local midnight differs -- the intent sums "all of the Item's heartbeat rows" (Design Notes); a day bound would change the specified behavior; negligible in use.
  - `[low]` `[patch]` blind: a failed or empty-Item read leaves `lastCostUSD` empty silently and the path is untested -- added the empty-Item assertion to `TestHeartbeatFromRow` (mutation line added); the failed read stays unpinned as the matrix says.
  - `[false]` `[reject]` blind: `If ..Tick(...) = "" Quit` hides a failed Tick -- Tick returns "" only after its own failed assertion; four siblings in the class use the same line.
  - `[low]` `[reject]` blind: the wait loop's timeout is not named -- the next assertion fails with both costs in its text; not worth a branch.
  - `[low]` `[reject]` blind: `HeartbeatBeat.LastCostUSD` docs still read as the displayed cost -- they sit in `Data/HeartbeatBeat.cls` and `Checks/Beat.cls` (frozen, out of footprint); the row keeps AD-18's "records its cost".
  - `[false]` `[reject]` blind: the spec's Auto Run Result and path placeholders are inconsistent -- the result is rewritten at finalize; `test-boundaries.sh` forbids local paths in tracked files (the placeholders were needed for it to pass).
  - `[false]` `[reject]` blind: `stateLine` hard-codes 60 and the wording is split from the picker -- the two whole constants are the spec's ruled design; the all-day case is pinned in `heartbeat-card-view.test.mjs`.
  - `[false]` `[reject]` edge: the event keeps a partial sum until the next publish when the turn lands late -- matrix row "Turn still running at the recording tick" rules this; the next read shows both.
  - `[low]` `[reject]` edge: no day bound (as above) -- carried claim, same evidence.
  - `[low]` `[reject]` edge: a recorded decision without Usage rows shows 0 instead of the row's cost -- a decision with a cost always has its Usage row; the Runs fixtures were given theirs as the spec directs.
  - `[low]` `[patch]` edge: silent failed read when `LastDecisionRef` is set and `LastItemId` empty -- same patch as the third row.
  - `[low]` `[reject]` edge: `TestHeartbeatFromRow` leaves Usage rows if it throws -- the same Clean-at-end shape as its siblings, and fixture rows are removed by the class's own cleanup of refs; negligible.
  - `[low]` `[reject]` edge: a timed-out wait is not named -- same as the fifth row.
  - `[low]` `[patch]` verification-gap: no recorded mutation for the `OwnerRef` and `ItemId` clauses -- both run, both red in `TestGetCheckInCost`, lines written, tree byte-identical after the revert.
  - `[low]` `[patch]` verification-gap: empty-Item and failed-read branches unpinned, the `IsOK(sc)` guard unkillable -- the empty-Item branch is now pinned (mutation line); the guard is redundant by construction and the failed read is "not pinned" by the matrix.
  - `[low]` `[reject]` verification-gap: the lib's failure text is checked only by a recorded `cmp` -- the text prints only on failure; the flag behavior and M3c are pinned; byte identity was verified under M3a and M3b.
  - `[low]` `[reject]` verification-gap: a run across instance-zone midnight would fail the exact Today asserts -- unlikely and the same as existing Today tests.
  - `[false]` `[reject]` intent-alignment: no test renders the card's two cost lines for an Act check-in -- the card renders the GET (39.5's tests), and the GET is pinned by `TestGetCheckInCost` with the event by `TestAct`; AC 1 names the GET.
  - `[low]` `[reject]` intent-alignment: day window differs -- carried claim, same evidence.
  - `[low]` `[reject]` intent-alignment: no rows at all gives 0 not the decision's cost -- same as the eleventh row.
  - `[false]` `[reject]` intent-alignment: a second lib rather than extending `lib-security-overview.sh` -- Rule 2 reason in Design Notes (that file is frozen).

## Design Notes

**Governing ADs:** AD-20 (Usage rows per turn; "totals that don't add up" is what it prevents; totals live in the ownership API beside `TurnCost`), AD-18 (the agent heartbeat: a beat is one decision plus one read-only turn on act; the row records the decision's cost, kept; the Event bullet: the payload is "the row's public view", read here as the view of the row's check-in, see below), AD-12 (one view per commit; the GET and the event are one view), AD-28 (no all-clear: no text added), AD-29 and AD-33 (lanes, see below), AD-22 (the CI mock and throwaway stacks).

**Decided in-stage:**
- **Make the last check-in's cost cover its whole check-in, rather than make Today sum only decisions.** Today is the heartbeat's real spend (every row counts toward the daily cap), so cutting it would hide cost; counting the turn as a second check-in would be false. The card's text stays; the number beside "Last check-in" becomes the check-in's cost. Rejected: storing the item's sum in `Settle` (the turn can land after the recording tick, and the stored number would then stay low while Today grows, the very mismatch); holding the decision unrecorded until the turn ends (a new pending state, and a beat whose turn never records stays pending).
- **Read it in `FromRow`, not in `SettingsOps`,** so the event and the GET stay one view (Story 39.2's rule). Precedent: `Payload.Decision` reads `Ownership.TurnOfItem`. AD-18's "the row's public view": the view is still built from the row; its `lastCostUSD` is the cost of the row's check-in (its `LastItemId`'s rows). The row's own `LastCostUSD` keeps AD-18's "records its cost".
- **All of the Item's heartbeat rows, not "decision plus turn rows":** the same partition as Today, so a decision's late Usage row (Decide stopped waiting, the runner still wrote it) also counts on both lines.
- **A failed read shows no cost,** never a number that may be wrong (the honest default).
- **Fixtures that set a cost without Usage rows get the Usage row** (Payloads, Runs) instead of a code branch that only fixtures could reach.
- **"Every hour" as two whole constants** (`everyHour`, `everyHourHours`), not a schedule name "hour" filled into "Every {interval}": the ruled strings are then inventory strings that `ux-strings.test.mjs` can source, and the picker's "1 hour" stays.
- **`ac`, not `ruled`, in `ux-strings.test.mjs`:** Story 39.9's acceptance criterion in `epics.md` states the strings; the cycle log holds no ruling entry for them.
- **A new `lib-heartbeat-overview.sh` rather than extending `lib-security-overview.sh`** (Rule 2): that sibling is sourced by `test-security-overview.sh`, which the frozen `release/security-overview.sh` runs, and `test-release-sequence.sh` pins it; the release-tool freeze keeps it untouched. Only the rule moves; each script keeps its own synthetic files, so its self-test inputs stay byte-identical.
- **EXPERIENCE.md is not amended:** it writes the template "Every {interval}, …" and the picker list, never "Every 1 hour" (searched).

**Lanes (AD-29, AD-33) -- for the lead at the spec gate.** The charter's line reads "*Home lane: A.*", but the Planner's rulings put Lane B files in the ACs: `web/` (the card), `Test.Web.*`, `docker/`, `.Data.Ownership` and `.Live`. The dispatch names them as this story's footprint, no other Epic 39 story is in flight, and none is on the contended list. Recommended apply-and-report amendment (as Story 39.7's home-lane amendment): "*Home lane: A and B (one runner; the Planner's follow-up rulings name both lanes' files).*" `footprint_extensions:` to report: `Data/Ownership.cls`, `Test/Live/Payloads.cls`, `Test/Checks/Runs.cls`, `web/scripts/ux-strings.test.mjs`.

**PUBLIC TEXT.** Item 1 changes no string: the line still reads "Last check-in {time} · Offered an action · {cost} · Trace"; only its cost now includes the read-only checks' turn ($0.0006 in the walk, not $0.0003). No proposal is needed. Item 2's strings are the Planner's ruling of 2026-11-06, used verbatim: "Every 1 hour, 07:15 to 21:45" becomes "Every hour, 07:15 to 21:45", and "Every 1 hour" becomes "Every hour" (`heartbeat-card-view.ts:27-28` gain `everyHour`, `everyHourHours`).

**DW-670, the residual (the race is not fixed).** Both tests went red together, in a class under a second, in CI's `shard:lane-b`, since Epic 30 (DW-453, before Epic 39). Epic 39 touches none of the guide, marker, `Live.Publish` or session-row paths (39.2's occurrence note). A plausible cause (inference): `Ownership`'s `INCIDENTVISIBLE` and `APPROVALVISIBLE` (Ownership.cls 62-67) also show, on a local install, instance incidents of a production that the owner's checks watch, and both fixtures watch OCUORDERS's Orders production; an instance incident noticed during the class would change `Incidents` in the Fingerprint and the guide's steps at once. The new messages will show it: an `Incidents:` or `incident:` entry that the test did not make. The ledger entry stays open as a flake with this residual.

**Split recommendation:** none needed. Items 3 and 4 are small (one new 40-line helper and two one-line wrappers; about ten test lines) and touch files that items 1 and 2 never touch. If the implement stage has not reached item 3 by about 13:00Z, the runner can split items 3 and 4 off as Story 39.10 with no change to items 1 and 2.

**Extend, don't copy (Rule 2):** `CheckInCost` extends `Ownership`'s `Rows` + `Sum` pattern (sibling `TurnCost`) and uses `HeartbeatToday`'s filter; the helper replaces both copies (DW-785); the "Every hour" constants sit beside `every`/`everyHours`.

**Integration ACs:** the two above.

**Consumed-by:**
- `Ownership.CheckInCost`: `Live.Payload.Heartbeat.FromRow` (this story), and through it `GET /api/v1/heartbeat` (39.2's route, via `SettingsOps.Heartbeat`) and the `heartbeat` event (39.7) that the Heartbeat card (39.5) re-reads on.
- `docker/tests/lib-heartbeat-overview.sh`: `test-triage-heartbeat.sh` and `test-heartbeat-overview.sh` (this story).

**Consumes:** `OcuTalon.Bridge.Data.Usage` rows (AD-20), `Ownership.Rows`/`Sum`, `Live.Payload.Heartbeat.FromRow`'s callers unchanged (`Checks.Beat.AddView`, `SettingsOps.Heartbeat`).

**Ledger inbox:**
- DW-824 is addressed by AC 1, the Integration AC and matrix rows 1 to 7 (`TestGetCheckInCost`, `TestAct`).
- DW-785 is addressed by AC 3 and the helper's Integration AC.
- DW-670 is addressed by AC 4 (diagnostics); the race fix is declined under the residual above. Declined DW-670 (the fix only): its cause is not plain and not in Epic 39's code.

**Footprint:** item 1: `Data/Ownership.cls`, `Live/Payload/Heartbeat.cls`, `Test/Web/HeartbeatApi.cls`, `Test/Checks/BeatOutcomes.cls`, `Test/Live/Payloads.cls`, `Test/Checks/Runs.cls`; item 2: `web/src/app/rail/heartbeat-card/heartbeat-card-view.ts`, `web/scripts/heartbeat-card-view.test.mjs`, `web/scripts/ux-strings.test.mjs`, `web/e2e/heartbeat-card.spec.ts`; item 3: `docker/tests/lib-heartbeat-overview.sh` (new), `docker/tests/test-triage-heartbeat.sh`, `docker/tests/test-heartbeat-overview.sh`; item 4: `Test/Web/GuideApi.cls`. None is on the contended list.

## Verification

`<lane>` is `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=39 stage=implement'` (another stage puts its own name in `stage=`).

**Run rules:**
- Every command is a foreground call with `timeout: 600000`, one test class, shard piece or live part per call, never two at once.
- Slot D (`server: ocutalon-slot-d`, `namespace: OCUTALON`; check identity with `iris_server_info` first) is only for `iris_doc_load` and compiling; no production or test runs there.
- At most one fresh and one warm throwaway for lane D; tear down only your own tags, also after a failure.

**Shared surfaces:**
- the `heartbeat` event's and the GET's `lastCostUSD` (now the check-in's Usage sum): `Test.Live.Payloads`, `Test.Checks.Runs` (updated); `Test.Core.SettingsHeartbeat`, `Test.Checks.Heartbeat` (compare with `FromRow`; unchanged); `web/e2e/heartbeat-card.spec.ts` (stubbed GET; unchanged);
- `HEARTBEAT_TEXTS` (two new keys) and the 60-minute state line: `heartbeat-card-view.test.mjs`, `ux-strings.test.mjs`, `heartbeat-card.spec.ts:420`;
- the two docker scripts' output: unchanged.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**ci_groups:** `image` (`shard:lane-b`: HeartbeatApi, Payloads, GuideApi, about 1,740 s plus a few seconds), `shards` (`shard:lane-a@Checks,Install,Watch`: BeatOutcomes and Runs, about 1,830 s plus about 10 s for `TestAct`'s extra Tick and wait), `browser` (`live:sign-in`: one changed expectation, no new test), the hosted `web` job (node tests) and the hosted `checks` job (the two scripts). Every group stays under 35 minutes.

**Commands:**
- (once) Before any edit: `bash docker/tests/test-triage-heartbeat.sh > <scratchpad>/e39s9impl/th-clean.txt; echo $?` and the same for `test-heartbeat-overview.sh` (`ho-clean.txt`); then each of M3a and M3b below applied to `docs/security-overview.md`, both scripts run into `th-M3a.txt`, `ho-M3a.txt`, …, and the file reverted (`git diff --quiet -- docs/security-overview.md`). Expected: clean exit 0; M3a red in both; M3b red in `heartbeat-overview` only.
- (loop) `<lane> OCUTALON_RUN_TAG=e39s9implw ci/warm.sh up`, once. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e39s9implw ci/iris.sh class OcuTalon.Test.Live.Payloads`. Expected: passed.
- (loop) the same, warm, one per call, for `OcuTalon.Test.Checks.Runs`, `OcuTalon.Test.Core.SettingsHeartbeat` and `OcuTalon.Test.Web.GuideApi`. Expected: passed.
- (loop) `<lane> OCUTALON_RUN_TAG=e39s9impl ci/iris.sh class OcuTalon.Test.Web.HeartbeatApi`, fresh (real production). Expected: passed.
- (loop) `<lane> OCUTALON_RUN_TAG=e39s9impl ci/iris.sh class OcuTalon.Test.Checks.BeatOutcomes`, fresh. Expected: passed; record the time.
- (once) the same, fresh, for `OcuTalon.Test.Checks.Heartbeat`. Expected: passed.
- (loop) `npm --prefix web test`. Expected: exit 0.
- (once) `npm --prefix web run lint`, then `npm --prefix web run build`, one call each. Expected: exit 0.
- (once) `<lane> OCUTALON_RUN_TAG=e39s9impl ci/iris.sh build`, then `OCUTALON_LIVE_DEADLINE=900 <lane> OCUTALON_RUN_TAG=e39s9impl ci/iris.sh live sign-in --part k/3` for the part whose `PART` line lists `heartbeat-card.spec.ts` (3/3 at Story 39.5). Expected: passed, with `SPEC heartbeat-card.spec.ts` green.
- (loop) `bash docker/tests/test-triage-heartbeat.sh` and `bash docker/tests/test-heartbeat-overview.sh`, one per call. Expected: exit 0, output byte-identical to `th-clean.txt` / `ho-clean.txt` (`cmp`).
- (once) M3a and M3b again on the refactored scripts: outputs `cmp`-identical to the recorded ones; revert byte-identical.
- (once) `bash -n docker/tests/lib-heartbeat-overview.sh` and `LC_ALL=C grep -n '[^[:print:][:space:]]' docker/tests/lib-heartbeat-overview.sh`. Expected: no output.
- (once) `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-ci-changes.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh`, one per call. Expected: exit 0.
- (once) `<lane> OCUTALON_RUN_TAG=e39s9impl ci/iris.sh shard lane-b@Live,Web`, then the same with `--reverse`; then `shard lane-a@Checks` forward and `--reverse`; fresh, one per call. Expected: every class passed.
- (once) `git diff --name-only 4497f66072a88e572de4d88403aadb2d363fc644` lists only the Footprint files and this spec. Expected: true.
- (once) `<lane> OCUTALON_RUN_TAG=e39s9implw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e39s9impl ci/iris.sh teardown`, also after a failure.

**Pinning mutations** (apply, observe red, revert, `git status --short` and `git diff --stat` unchanged; record a `mutation:` line under each):
- AC 1: `FromRow` sets `payload.LastCostUSD = row.LastCostUSD` again. Expected red: `HeartbeatApi.TestGetCheckInCost` (.0003, not .0006), `Payloads.TestHeartbeatFromRow` and, fresh, `BeatOutcomes.TestAct` (the event's cost is the decision's alone).
- AC 1, the filter: the `checkInUsage` statement loses `AND Channel = 'heartbeat'`. Expected red: `TestGetCheckInCost` and `TestHeartbeatFromRow` (the web row counted).
- AC 1, pending: the `LastDecisionRef '= ""` guard removed. Expected red: `TestGetCheckInCost`'s pending step and `TestHeartbeatFromRow`'s pending row.
- AC 2: `stateLine` without the 60-minute branch. Expected red: `heartbeat-card-view.test.mjs` (the state line cases).
- AC 2, other intervals: the branch taken for `interval >= 60`. Expected red: the new fixed-strings case ("Every 2 hours").
- AC 3: M3a, the beat sentence in `docs/security-overview.md` ends "at most once per day." Expected: both scripts FAIL, output identical before and after the refactor. M3b, the run-now sentence removed. Expected: `heartbeat-overview` FAIL runnow, `triage-heartbeat` PASS, identical before and after. M3c, the helper's `/^#/ { sect = 0 }` removed. Expected: both scripts FAIL on their `heading` variant (the helper's Integration AC).
- AC 4: in `TestOnlyTheMarkerChanges`, a temporary `Do $ClassMethod(fixture, "Reminder", ref)` after the trace_opened post. Expected red, with a failure line holding both fingerprints (one more `Reminders:` entry). In `TestRunAgain`, a temporary open fixture incident before run_again. Expected red, with `done`, the view and the fingerprint in the line.

**Mutations run (implement stage; each applied, observed red, reverted, `git status --short` and `git diff --stat` byte-identical to before):**
- mutation: AC 1, `FromRow` sets `payload.LastCostUSD = row.LastCostUSD` again -> red: `Payloads.TestHeartbeatFromRow` (the values assertions), `HeartbeatApi.TestGetCheckInCost` (lastCostUSD .0003, not .0006; the 1-check-in case's equality lines), `BeatOutcomes.TestAct` (the event's lastCostUSD is the decision's alone).
- mutation: AC 1, filter: the `checkInUsage` statement without `AND Channel = 'heartbeat'` -> red: `Payloads.TestHeartbeatFromRow`, `HeartbeatApi.TestGetCheckInCost`.
- mutation: AC 1, pending: the `LastDecisionRef '= ""` guard removed -> red: `Payloads.TestHeartbeatFromRow` (pending row), `HeartbeatApi.TestGetCheckInCost` (pending step).
- mutation: AC 1, the `checkInUsage` statement without its `OwnerRef = ?` clause -> red: `HeartbeatApi.TestGetCheckInCost` (the other session's 0.7 row is counted; four assertions).
- mutation: AC 1, the `checkInUsage` statement without its `ItemId = ?` clause -> red: `HeartbeatApi.TestGetCheckInCost` (the other Item's row is counted; two assertions).
- mutation: AC 1, `CheckInCost` without its empty-`itemId` guard -> red: `Payloads.TestHeartbeatFromRow` (a decision on a row with no Item exports a `lastCostUSD` instead of none; 0 before code review's purge rule, the row's own cost after it).
- mutation: AC 2, `const hourly = false` in `stateLine` -> red: `heartbeat-card-view.test.mjs` (the two 60-minute state line cases).
- mutation: AC 2, other intervals, `hourly = interval >= 60` -> red: the state line case and the new fixed-strings case ("Every 2 hours").
- mutation: AC 3, M3a and M3b on `docs/security-overview.md` -> both scripts' outputs `cmp`-identical to the recorded pre-refactor ones; M3c (the helper's `/^#/ { sect = 0 }` removed) -> both scripts FAIL on their `heading` variant.
- mutation: AC 4, `Reminder` fixture after the trace_opened post -> `TestOnlyTheMarkerChanges` red with both fingerprints in the line (one more `Reminders:` entry); an open fixture incident before run_again -> `TestRunAgain` red with `done 10100`, the view and the fingerprint.

**QA stage (Story 39.9; tests added or extended, marked `(QA)`):**
- (QA) `web/e2e/heartbeat-card.spec.ts` (HC8, extended; no new file): a stubbed GET of an Act check-in with `lastCostUSD` 0.0006 and `today` {1, 0.0006} reads "Last check-in ... Offered an action $0.0006 Trace" beside "Today: 1 check-in, $0.0006" in the real browser (DW-824's case, the pair side by side; `clock(iso, LOCALE, ZONE)` kept). Run: fresh throwaway, `ci/iris.sh build`, `live sign-in --part 3/3`: 79 passed, `heartbeat-card.spec.ts` green.
- mutation: the card's rendering of a cost below $0.001 on the "Last check-in" and "Today" lines (not a pin of AC 1's server change, which the stubbed GET bypasses; AC 1 is pinned by `TestGetCheckInCost`, `TestHeartbeatFromRow` and `TestAct` above), `formatCost` in `web/src/app/chat/decision-view.ts` shows "<$0.0001" below 0.001 instead of below 0.0001 -> red: `heartbeat-card.spec.ts` HC8 (the new step holds the only cost under 0.001 in that test; every other HC8 cost is 0.0012 or more), plus collateral reds in HC4, `links.spec.ts` V1 and V9 (observed as the failed-test list only; that the new step is HC8's red is by elimination, which code review checked by reading HC8); reverted, `git status --short` and `git diff --stat` byte-identical to before.
- Audit: every other AC and matrix row already has a pinning test with a recorded mutation (above); no further gap found. The failed-read row stays unpinned as the matrix says.

**Code review (Story 39.9; each applied, observed red, reverted, `git status --short` and `git diff --stat` byte-identical to before):**
- mutation: AC 1, purged rows: `FromRow` sets `payload.LastCostUSD = cost.costUSD` without the floor at the row's own `LastCostUSD` -> red: `Payloads.TestHeartbeatFromRow` ("an Item whose Usage rows are gone exports the row's own LastCostUSD"), warm.
- mutation: matrix row "Failed Usage read" (now pinned; a row with an empty `SessionRef` makes `Ownership.Rows` fail): `FromRow` sets `LastCostUSD` without its `IsOK(sc)` guard -> red: `Payloads.TestHeartbeatFromRow` ("a failed Usage read exports no lastCostUSD" and the no-Item line), warm.
- mutation: AC 1 / Integration AC on the patched `TestAct` (event, or after a real Tick that came first, the view built again): `FromRow` sets `payload.LastCostUSD = row.LastCostUSD` -> red: `BeatOutcomes.TestAct` (both cost assertions), fresh; so the real-Tick branch does not hide the defect.
- mutation: AC 2, fixed-strings case: a 720-minute interval added to `INTERVALS` in `heartbeat-card-view.ts` -> red: `heartbeat-card-view.test.mjs` ("the cases are every offered interval").
- Runs after the patches: `Live.Payloads`, `Checks.Runs` (warm), `Checks.BeatOutcomes` (fresh, 28.2 s), `Web.HeartbeatApi` (fresh, 8.6 s) passed; `heartbeat-card-view.test.mjs` 37 of 37; `test-boundaries.sh` and `test-class-rules.sh` exit 0.
- merge-file re-run after the patches: `Test/Live/Payloads.cls` and `web/scripts/ux-strings.test.mjs` vs `origin/OCT-epic4` (621dd3a5) exit 0; `Test/Checks/BeatOutcomes.cls` vs `origin/OCT-epic17` (17989a90) exit 0. Every hunk of the three files is inside the ruled ones (the BeatOutcomes class-doc hunk was reverted).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The Heartbeat card's last check-in cost is now the sum of the check-in Item's heartbeat Usage rows (`Ownership.CheckInCost`, read in `Live.Payload.Heartbeat.FromRow`), so it equals Today's cost for a person's only check-in (DW-824); the 60-minute schedule reads "Every hour" (ruled text); the two docker overview scripts share one helper (DW-785); GuideApi's failures print both fingerprints (DW-670, diagnostics only; the race is not fixed). Items 3 and 4 were done in this pass (not split).

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: `CheckInCost` and the `checkInUsage` statement.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Heartbeat.cls`: `FromRow` reads the check-in cost; docs.
- `src/ocutalon/cls/OcuTalon/Test/Web/HeartbeatApi.cls`: `TestGetCheckInCost` (the 1-check-in, 2x-cost case).
- `src/ocutalon/cls/OcuTalon/Test/Checks/BeatOutcomes.cls`: `TestAct` pins the event's cost against Today on the real production.
- `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls`: `TestHeartbeatFromRow` seeds Usage rows; pending and no-Item cases.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls`: two fixtures also seed their decide Usage row.
- `src/ocutalon/cls/OcuTalon/Test/Web/GuideApi.cls`: failure messages carry the values.
- `web/src/app/rail/heartbeat-card/heartbeat-card-view.ts`, `web/scripts/heartbeat-card-view.test.mjs`, `web/scripts/ux-strings.test.mjs`, `web/e2e/heartbeat-card.spec.ts`: "Every hour".
- `docker/tests/lib-heartbeat-overview.sh` (new), `docker/tests/test-triage-heartbeat.sh`, `docker/tests/test-heartbeat-overview.sh`: the shared rule.

**Review.** 22 findings from four layers: patches applied 3 rows (one root cause each: the empty-Item/failed-read assertion, and the two missing mutation lines), deferred 0, rejected 19 with their reasons in the Review Triage Log (6 false, 13 low). High 0, medium 0. Follow-up review recommended: false.

**Verification performed.**
- Class tests (warm): `Live.Payloads`, `Checks.Runs`, `Core.SettingsHeartbeat`, `Web.GuideApi` passed. Fresh: `Web.HeartbeatApi` passed (8.5 s of test, about 126 s call with the stack), `Checks.BeatOutcomes` passed (28.1 s test, about 164 s call), `Checks.Heartbeat` passed (14.6 s).
- Shards, fresh: `lane-b@Live,Web` forward (28 classes, 123 s to ready) and `--reverse` (154 s to ready), `lane-a@Checks` forward (8 classes, 139 s) and `--reverse` (148 s): every class passed; `BeatOutcomes` 27.8 s and 26.7 s in them.
- `npm --prefix web test` 1495 of 1495; `lint` and `build` exit 0; `live sign-in --part 3/3` passed (79 tests; `heartbeat-card.spec.ts` 15 tests, 208 s).
- Docker scripts: both outputs `cmp`-identical to the pre-change outputs on the real tree and under M3a and M3b; M3c red on both `heading` variants; `bash -n` and the ASCII check clean; `test-ci-config.sh`, `test-ci-changes.sh`, `test-boundaries.sh`, `test-class-rules.sh` exit 0.
- `git diff --name-only` since the baseline lists only the Footprint files and this spec.
- merge-file: src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls vs origin/OCT-epic4 exit=0 clean union (re-run at code review after its patches, theirs 621dd3a5: exit=0)
- merge-file: web/scripts/ux-strings.test.mjs vs origin/OCT-epic4 exit=0 clean union (re-run at code review after its patches, theirs 621dd3a5: exit=0)
- merge-file: src/ocutalon/cls/OcuTalon/Test/Checks/BeatOutcomes.cls vs origin/OCT-epic17 exit=0 clean union (re-run at code review after its patches, theirs 17989a90: exit=0)

**Residual risks.** `CheckInCost` has no day bound (the intent sums all of the Item's heartbeat rows), so a check-in across local midnight can differ from Today for that Item. The failed-read path is unpinned (the matrix says so). `footprint_extensions:` `Data/Ownership.cls`, `Test/Live/Payloads.cls`, `Test/Checks/Runs.cls`, `web/scripts/ux-strings.test.mjs`. The spec's Verification commands use `<main checkout>` and `<scratchpad>` placeholders because `test-boundaries.sh` forbids local paths in tracked files. Slot D was not used (all runs in throwaways).
