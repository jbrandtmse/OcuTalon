---
title: 'Story 39.4: Each beat carries your checklist and a status snapshot built by code'
type: 'feature'
created: '2026-11-04'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 39.3 left `Beat.Snapshot` returning the checklist alone, so a beat shows the model nothing about where things stand, and the outcomes of a beat have never been run end to end. Triage also has no words for the channel `heartbeat`, so it can't tell a person's own checklist from any other arriving item.

**Approach:** Fill `Beat.Snapshot` with a code-built status of the person's incidents, watches, approval requests, reminders and recent decisions. Add the one static heartbeat paragraph to Triage. Add the `heartbeat-*` mock scenarios and prove each outcome end to end through the real `Intake`, `OutcomeRouter` and `DigestStore`.

## Boundaries & Constraints

**Always:**
- Lane A files only (U-177): `Checks/Beat.cls`, `Agent/Triage.cls`, tests under `Test/Checks/**`, `ci/mock/scenarios/A/heartbeat-*.json`. Lane B classes are only called: `Data.Ownership` (`Incidents`, `Checks`, `Approvals`, `Reminders`, `Decisions`, `Incident`, `TurnOfItem`), `Data.Time.ToLocal`.
- The text is the checklist, a blank line, the line `Status at {local time} (built by OcuTalon):`, then one line per entry in this order: incidents, watches, approval requests, reminders, decisions. A kind with no entries gets one line that says `none`.
- Every time in the text is the instance-zone local time as `YYYY-MM-DD HH:MM`, from `Data.Time.ToLocal`. `Data.Time.ForMessage` is never used here: its text depends on `now`, so an entry line would change at local midnight with no record changed.
- An entry holds only these fields:
  - incident: the production, `State`, `Count`, `FirstAt`, for every row of `Ownership.Incidents` whose state is not `closed`;
  - watch (rows of `Ownership.Checks` of `Kind` `production`): `DisplayName`, `Result`. A watch that has not run says so;
  - approval request (`Ownership.Approvals`): `Kind`, `FixKind` or `ToolName`, the production of its incident (`none` when it has no incident), `RaisedAt`, `ExpiresAt`;
  - reminder (`Ownership.Reminders`, `DueAt` at or before `now` plus one interval): `Text`, `DueAt`;
  - decision: `RecordedAt`, the channel, `Outcome`, `Summary`, at most `DECISIONSMAX` (10), newest first.
- The decisions come from `Ownership.Decisions` (Kind `decide`), read newest first and stopping at the first beat's own row, which is the last beat that made a decision. A beat's row is one whose `Summary` is `Beat.SUBJECT`. A row with a `Turn` (`TurnOfItem`) is the user's own chat message and is left out, because its `Summary` is that message's first line. The channel is `Bridge.Data.Usage.Channel` of the row's `DecisionRef`, and `unknown` when it has no usage row (a fallback that made no model request).
- Every field written into a line loses its control characters and every line break that `Agent.Input.Quoted` knows (CR, LF, VT, FF, NEL, U+2028, U+2029), so no field can start a line of its own.
- The status block, from the `Status at` line through its last line, is at most 4,000 characters (NFR-27: 1,000 of checklist plus 4,000 of snapshot). Over that it keeps whole lines and ends with the line `(more not shown)`.
- `Key` takes the text it is given, as 39.3 built it. `Run` keys the whole status, uncut, so a change past the cut still changes `LastSnapshotKey`.
- A read that fails throws. It never reads as `none`: `RunDue`'s per-person Try/Catch counts it, and the beat stays due.
- The beat keeps 39.3's shape: `Beat` builds, `Checks` sends. No text of the snapshot reaches a log line, a status text or the row.
- Triage's paragraph is the UX text word for word, in one self-contained paragraph at the end of `XData INSTRUCTIONS`, with no `{{`.
- Fixed clocks in every time-dependent test. Every test added or changed passes on a fresh environment, in either order.

**Never:**
- No `Incident.Cause`, `FixSummary`, `Element`, `SampleError`; no `Decision.Reasons` or `Payload`; no `BackgroundCheck.Finding`, `AskedBy` or `Reported`; no `ApprovalRequest.DryRun`, `ToolArguments`, `FixParameters`, `FixTargets`, `AnsweredBy` or `RequiredRole`; no `Ref`, `SessionRef`, `ItemId`, `TraceRef` or token of any row. No event-log or message text.
- No edit to `Bridge/**`, `Data/**`, `Msg/**`, `Core/**`, `Live/**`, `Web/**`, `web/**`, `Agent/Input.cls`, `Checks/Process.cls`, `Test/Agent/Instructions.cls` (Epic 7 has changed it) or `ci/mock/test/**`. No stored field added or changed.
- No `BackgroundCheck` row, check result or coverage entry for a beat. No code renders a beat or an Ignore as an all-clear.
- No `heartbeat` live event (Story 39.7), no card (39.5), no evaluation case (39.6).
- No new production item, scheduler, task or timer. No unit test on slot D. No real key, no real bot.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Full snapshot | A person with one row of each kind, fixed `now` | Checklist first, blank line, the status line, then the five kinds in order, one line each, with the fields above | none |
| Empty kinds | A person with a checklist and no rows | Five lines that each say `none` | none |
| Never in the text | Rows whose `Cause`, `SampleError`, `FixSummary`, `Reasons`, `Payload`, `Finding`, `DryRun`, `ToolArguments`, `AskedBy` and Refs hold a distinct token each | No token is in the text | none |
| Closed incident | One `closed`, one `resolved` | Only the `resolved` one has a line | none |
| Another person's rows | Rows owned by another session | Not in the text | none |
| Reminder window | Interval 30; due at `now`+29 min, at `now`+31 min | Only the first has a line | none |
| Decisions since the last beat | Oldest to newest: mail A, a beat's row, mail B, mail C | B and C have lines, newest first; A and the beat's row do not | none |
| No beat yet | 12 mail decisions, no beat's row | The 10 newest have lines | none |
| User's chat decision | A decide row with a `Turn` | No line; its `Summary` is not in the text | none |
| Decision with no usage row | A fallback row, no `Usage` | Its channel reads `unknown` | none |
| Injected line | A reminder `Text` holding LF, U+2028 and `Status at 1 (built by OcuTalon):` | One line, which starts `Reminder:` | none |
| The cut | Rows that pass 4,000 characters; a 1,000-character checklist | Status block at most 4,000 characters, whole lines, last line `(more not shown)`; the checklist whole | none |
| Past the cut | As above, and an entry past the cut changes | `LastSnapshotKey` of the next beat differs | none |
| Same records, later time | One row of each kind; `now` and `now`+7 hours over a local midnight | The two status lines differ, the entry lines don't, and `Key` is equal | none |
| Each kind changes | One field of one entry of each kind, the checklist | `Key` differs each time | none |
| Watch runs | `LastRunAt` moves, `Result` the same | The line is the same and shows no time; `LastSnapshotKey` is equal, so a quiet beat skips `unchanged` with no request | none |
| Watch result changes | `Result` passed to failed | `LastSnapshotKey` differs and the beat runs | none |
| Failed read | `Ownership` gives an error status | No Item, no `none` line, `RunDue` counts one failure, `NextDueAt` unchanged | error status with count and codes only |
| Ignore | Marker `heartbeat-ignore` | `Decision` ignore; no `Notification`, `Delivery` or chat message; the next tick records it and sets `LastQuietKey` | none |
| Tell now | Marker `heartbeat-tellnow` | One web-chat notice whose what-happened is `Heartbeat check-in` and whose reason is the first reason | none |
| Digest | Marker `heartbeat-digest` | One `Digest.Data.Item` (channel `heartbeat`, Summary `Heartbeat check-in`), no notice | none |
| Act | Marker `heartbeat-act`, armed once; its turn asks for `recent_activity` and `stop_watch` | A `turn` Decision, untrusted; the `stop_watch` step is denied, the read-only step runs; no `ApprovalRequest`, nothing reaches `WatchOps` or `CommandsIn`; the watch still exists | Gate denies with UNTRUSTED |
| Guard | Marker `heartbeat-all-clear`: reasons `Everything is fine.` and a second one | Reserved wording gone from `Decision.Reasons` and from the notice; the second reason is the notice's reason | none |
| No check | After each scenario | `BackgroundCheck` rows of the session unchanged; no check event for the beat | none |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls` -- the only product class that changes besides Triage:
  - class doc, lines 24-25 ("Until Story 39.4 ...");
  - `Snapshot` 173, the stub to fill; `Run` 298, which calls `Snapshot` and `Key` at 304-305;
  - `STATUSPREFIX`, `STATUSSUFFIX`, `SUBJECT`; `Key` 180, which needs no change;
  - `Values`, for the interval of the reminder window.
- `src/ocutalon/cls/OcuTalon/Agent/Triage.cls` -- `XData INSTRUCTIONS`, last paragraph ends at line 39. Epic 40's Story 40.3 also edits this file; it has not yet.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- line 1017, `**Triage, heartbeat:**`, the paragraph's source.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- `Reminders` 270, `Checks` 276, `Decisions` 282, `Incidents` 289, `Approvals` 303, `TurnOfItem` 238, `Incident` 381. Each takes `.sc`. `Decisions` takes a `max` (default 20), newest first by `RecordedAt`, then ID, and holds chat rows too. `Reminders` holds pending rows only. Call only.
- `src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls` -- `Channel`, `DecisionRefIndex`. Read by SQL, table `OcuTalon_Bridge_Data.Usage`, with a bound value, compared exactly afterwards as `TurnOfItem` does (the default collation ignores case). `Bridge/Data/Decision.cls` has no `Channel`.
- `src/ocutalon/cls/OcuTalon/Tools/WatchAnswers.cls` -- `WatchNames`, line 179, and `Tools/RecentActivity.cls`: the sibling reads of the same rows, and the same list of what never to read. Read for reference, not called (see Design Notes).
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- `KIND` at 85, the value that picks a watch from `Ownership.Checks`. `INTERVALSECONDS` = 60 at 67 and the unconditional `UPDATE` at 491: `LastRunAt` moves every minute, which is why a watch's line holds no time. Read only.
- `src/ocutalon/cls/OcuTalon/Core/Intake.cls` -- `SummaryOf`, the Summary of a beat and of mail. `Core/Rule/Outcome.cls` -- digest to `DigestStore`, tellnow and act to `Notify`. `Digest/Store.cls`, `Digest/Data/Item.cls`. All read only.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls` -- old shape to update:
  - `TestKey`'s last line (299);
  - the Item's text as the checklist: 353, 437;
  - each key that must equal the real snapshot's: 355, 412 with 549's skip, 429, 535. Use `..BKey(..BSnap(ref, at))`, set after the person's row exists. 429 matters most: with a stale key, "unchanged does not hold a run now" would pass without testing anything;
  - the other seeds (305, 347, 371, 468, 539, 543, 578-579) are only copied or must only differ, so they stay.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Heartbeat.cls` -- old shape to update: `TestBeatReachesIntake` (480) and `TestBeatNowReachesIntake` (520) assert the Item's text equals the checklist. The quiet key at 505 must become the real snapshot's key, written after `SeedBeat` because `Snapshot` reads the saved checklist; otherwise "unchanged does not hold a run now" tests nothing. `TestAnHourOfTicks` (534) needs no change: its minute-30 snapshot stops at T0's own decision, so its text is T0's. Helpers `Findings` 292, `Beatable` 350, `Due` 361, `SeedBeat` 369, `Beat` 383, `WaitDecision` 391, `Marked` 403 and `Check` 587 move to `BeatCase` (see Tasks). `TestTickRunsTheWatch` (50) is how a real watch is seeded and run.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls` -- old shape to update: 1035 asserts the Item's text is the checklist.
- `src/ocutalon/cls/OcuTalon/Test/Checks/BrokenGuard.cls` -- the shape of a test-support subclass with no test; `ci/iris.sh` `is_test_case` needs a `Method Test`, so it lists none.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls` -- `Tick` 680, `HeadersBetween` 360, `PointKeys` 560.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Turns.cls` -- `AssertDenied` 195: the shape of the act test.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` -- `Session`, `Turn`, `Reminder`, `Check`, `Incident`, `Approval`, `Decision`, `Usage`, `Clean`.
- `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls` -- `Arm` 439, `LogMark`, `LogSince`. `Test/Core/Observe.cls` -- `DeliveryRows`, `DeliveryCount`.
- `ci/mock/mock.mjs` -- lines 35-39, the reply rule: an unarmed marker answers `replies[0]` to a fresh turn too, so the act scenario must be armed with remaining 1.
- `ci/mock/scenarios/A/` -- `decide-ignore.json`, `bridge-example-digest.json`, `watch-injected-stop.json`, `usage-decide.json` (a `body` with fixed usage) are the shapes to follow.
- `ci/units.sh` line 6 `CHECK_SCRIPTS`; `docker/tests/test-readme.sh` 791-804 is the shape of an extraction from EXPERIENCE.md. No open epic has changed `ci/units.sh`.

## Tasks & Acceptance

**Execution:**
- `ci/mock/scenarios/A/heartbeat-ignore.json`, `heartbeat-tellnow.json`, `heartbeat-digest.json`, `heartbeat-act.json`, `heartbeat-all-clear.json` -- add first, before `ci/warm.sh up` (a change under `ci/mock` refuses a warm run). `heartbeat-ignore` uses `body` with fixed usage as `usage-decide.json` does. `heartbeat-act` has three replies: the act decision; `toolUse` of `recent_activity` and `stop_watch`; a closing text. `heartbeat-all-clear` is tellnow with reasons "Everything is fine." then a plain second reason.
- `src/ocutalon/cls/OcuTalon/Checks/Beat.cls` -- fill `Snapshot(sessionRef, now, Output whole)`: the return value is the Item's text, and `whole` is that same text with no cut, which `Run` hands to `Key`. Each line is built once, so the two differ only past the 4,000-character cut. A watch's line reads `DisplayName` and `Result` only. Add `DECISIONSMAX`, `DECISIONSREAD` (100) and `STATUSMAX` parameters, the "(more not shown)" text as a parameter, and one private builder for each kind of line. Every read goes through one method that throws on an error status, which a test subclass overrides to fail a read, as `Test.Checks.BrokenGuard` overrides `ReplyGuard`'s. The `Usage` read goes through it too, so a failed SQL read throws. Change `Run` to key `whole`. Replace the class doc's two 39.3 lines -- the snapshot's contract.
- `src/ocutalon/cls/OcuTalon/Agent/Triage.cls` -- append the UX paragraph as the last paragraph of `XData INSTRUCTIONS` -- one self-contained block so that Epic 40's merge is a plain union.
- `docker/tests/test-triage-heartbeat.sh` (new) and `ci/units.sh` -- the hosted check: it extracts the quoted text of `**Triage, heartbeat:**` from EXPERIENCE.md, fails when the extraction is empty, and requires that exact text as one whole line of `Agent/Triage.cls`. Append `triage-heartbeat` to `CHECK_SCRIPTS` (a one-name append; report it under `footprint_extensions`).
- `src/ocutalon/cls/OcuTalon/Test/Checks/BrokenBeat.cls` (new) -- a `Checks.Beat` whose read method throws. Test support only, with no test.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Snapshot.cls` (new, plain `%UnitTest.TestCase`, `Test.Data.Fixture`, no production) -- the matrix rows from Full snapshot to Failed read, the last through `BrokenBeat`.
- `src/ocutalon/cls/OcuTalon/Test/Checks/BeatOutcomes.cls` (new, extends `Test.Watch.Case`) -- the matrix rows Ignore to No check, on the real production through a real Tick. Two further proofs on real Ticks. The Watch runs row again, with a real watch: a person of their own, so that the No check row stays true of every other person, holds a watch and `heartbeat-ignore`; the watch's `LastRunAt` moves between the beats (`Hang 1.1`, as `TestTickRunsTheWatch` does), and the beat due one interval later skips `unchanged` with no request carrying the marker. And the `Usage` read under the production's job: the Tell now person also holds a mail decision with a `Usage` row, and the mock's log shows that channel in the request. Move `Findings`, `Beatable`, `Due`, `SeedBeat`, `Beat`, `WaitDecision`, `Marked` and `Check` from `Heartbeat.cls` to a shared place rather than copying them: a new `Test/Checks/BeatCase.cls` extending `Test.Watch.Case`, declared `[ Abstract ]` as `Case` is (`ci/iris.sh` then lists it as no test class), which `Heartbeat` and `BeatOutcomes` both extend.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Beat.cls`, `Test/Checks/Heartbeat.cls`, `Test/Checks/Runs.cls` -- update every old-shape assertion in the Code Map. Search `Test/**` for `Beat.Snapshot`, `Beat).Key(`, `LastSnapshotKey`, `LastQuietKey`, and the text of a heartbeat Item.

**Acceptance Criteria:**
- AC 1 -- Given a person with watches, incidents, approval requests, reminders and decisions, when `Beat.Snapshot(sessionRef, now)` builds the text, then it writes the checklist first, then the status line, then one line per entry with the fields of Boundaries.
- AC 2 -- Given rows that hold a diagnosis cause, reasons, event-log or message text, keys and identities, when the snapshot is built, then none of them is in the text.
- AC 3 -- Given rows that pass the cap, when the snapshot is built, then the status block is at most 4,000 characters and ends with "(more not shown)", and given a kind with no rows, its line says "none".
- AC 4 -- Given two snapshots built at different times over the same records, then `Beat.Key` is the same, and given a change to an entry or to the checklist, then the key that `Run` stores differs. A watch that runs again with the same `Result` changes no entry, because its line holds no time.
- AC 5 -- Given Triage's instructions, when the hosted check compares them with EXPERIENCE.md, then the paragraph is there word for word, and `Test.Agent.Instructions` `TestNoTemplates` still passes.
- AC 6 -- Given each `heartbeat-*` scenario, when a beat runs end to end on the real production, then the outcomes are those of the matrix rows Ignore, Tell now, Digest and Act.
- AC 7 -- Given a beat, when Decide answers, then the `DecisionResponse` from Decide to Intake carries the fixed input tokens and a cost equal to the `Decision` row's, and the beat's `Decision.TraceSessionId` is the Item's own trace session, whose `SuperSession` is the person's `TraceRef`.
- AC 8 -- Given `heartbeat-all-clear`, when the beat runs, then the reserved wording is gone from the decision and the notice, and given any beat, no `BackgroundCheck` row, check result or coverage entry exists for it.
- AC 9 (U-275, condition 1) -- Given a mail decision whose stored `Summary` is over 80 characters and whose Item has a distinct token in its body, when the snapshot is built, then its decision line holds the `Summary` at most 80 characters long, as `Core.Conversation.Summary` cut it, and the body's token is nowhere in the text. Pin it in `Test/Checks/Snapshot.cls`, with its own `mutation:` line (for example: the line reads the Item's text instead of the stored `Summary`).
- AC 10 (U-275, condition 2) -- Given a beat, when its Item reaches `Intake`, then its `Provenance` is `untrusted`, and on act its turn can only look, notify and save: the `Act` row's denied `stop_watch` pins the turn, and this AC adds an assertion on the Item's `Provenance` in `Test/Checks/BeatOutcomes.cls`, with its own `mutation:` line (the beat's Item set to provenance `user` -> that test goes red).
- Integration AC -- `Intake`, `OutcomeRouter`, `Notify`, `DigestStore` and the Gate (real instances) consume the Item whose text `Beat.Snapshot` built, and produce the notice, the digest row and the denied step of AC 6. The CI mock's log shows the request carrying the status line.

## Spec Change Log

- 2026-11-04, lead, applying U-275 (kept with conditions, at=2026-11-04T15:27:10Z#834): AC 9 and AC 10 added. The Summary line stays, cut at 80 characters, with no message body; the beat stays untrusted, so its turn can only look, notify and save. The third condition, a re-check of the security overview's no-names sentence and of AD-18's wording, is the runner's at the epic's close.

- 2026-11-04, lead at the spec gate, ruling on the plan's intent gap (veto U-274; U7 step 1, comply): option B. A watch's line carries no time, so it holds `DisplayName` and `Result` only and `Beat.Key` needs no special case; the key stays as AD-18 says, and AD-18 is not amended (open specs of Epics 33 and 7 cite it). Original AC wording: "its last check result with its time, from the row"; amended in `epics.md`. Options A and C are rejected: A needs an AD amendment that U14 stops, and C ships the skip dead for anyone with a watch.

- 2026-11-04, lead at the spec gate, ruling (veto U-275): a mail decision's stored `Summary` is kept as the AC names it. Lead read of U-268: clear, confirmed in the code (`Core.Rule.Outcome` sends `digest` to `DigestStore`; `Bridge.Policy.Gate` denies a non-read-only call in an untrusted turn before `CommandsIn.TOOLVERBS`).

## Review Triage Log

## Design Notes

**Governing ADs:**
- AD-18: the agent heartbeat (the snapshot, the key, the outcomes, no all-clear).
- AD-7: Triage's static instructions, no template token.
- AD-10: item 3 of its list, provenance and taint, behind act (`Bridge.Policy.Gate` step 4). AD-14 and AD-30: untrusted Item, `Intake`, `OutcomeRouter`, `DigestStore`.
- AD-26: the beat's own trace session. AD-20: tokens and cost.
- AD-28: the guard, no all-clear. AD-32: the tell-now notice.
- AD-29 and U-177: lanes.
- The story changes no AD's Rule. `Beat.Key` stays as AD-18 says, and the spine is not amended.

**U-268 (Story 33.2's pending additions to AD-1, AD-14, AD-13, AD-19, AD-32): nothing in this story relies on them.**
- `digest` ("reaches `DigestStore`") is the inbound half only. `Core.Rule.Outcome` forwards the `ItemDecision` unchanged and `Digest.Store.Keep` writes one `Digest.Data.Item`. No `Notification` of kind `digest` is built, `Rule.Notify` and `digest.channels` are not involved, and `SendDigest` and **Got it** are not called. The test asserts the row and no notice. So it does not rely on outbound digest routing.
- `act` ("calls no tool that isn't read-only") rests on `Bridge.Policy.Gate`'s step 4, provenance and taint, which is item 3 of AD-10's list: in an untrusted or tainted turn a call runs only when its classification is safe and its readOnly is 1. Every other call is denied with UNTRUSTED, fires no `turn.step` and never reaches step 5, so no approval request can come from it. The Gate decides before the call, from the tool's own class parameters: `stop_watch` is safe with `READONLYSTOPWATCH` 0, and `recent_activity` is safe with `READONLYRECENTACTIVITY` 1. `CommandsIn.TOOLVERBS`, the closed `tool` list of AD-1, is a later fence that a denied call never reaches. Adding `SendDigest` to it widens nothing here, because a tool that submits a command isn't read-only and the Gate stops it first. The test asserts a denied step and nothing at `WatchOps` or `CommandsIn`, not the list's contents, so it stays green when the list grows.
- Nothing else: the story adds no route, setting, notification kind or command verb, and `SendDigest` takes no part in a beat.

**Decided in-stage:**
- A watch's line holds `DisplayName` and `Result` (veto U-274), so its text and its keyed form are the same. `LastRunAt` is not read. An empty `Result` reads `not run yet`, and `not_checked` is shown as stored. Going from `not run yet` to a result is a real change of an entry.
- The line forms, for the model only, with ` | ` between fields and a kind with no entries as its plural label and `none`:
  ```
  Status at 2026-11-04 12:00 (built by OcuTalon):
  Incident: Demo.Orders | open | 3 | 2026-11-04 11:40
  Watch: Orders feed | failed
  Watch: Billing feed | not run yet
  Approval request: fix | restart | Demo.Orders | 2026-11-04 11:45 | 2026-11-04 12:45
  Reminders: none
  Decision: 2026-11-04 11:50 | mailbox | digest | Ana: Invoice run
  ```
- `Beat` reads at most `DECISIONSREAD` (100, the size of `Ownership`'s other recent reads) rows of `Ownership.Decisions`, and stops at the first beat's row or the tenth line. The read needs a bound above 10 because chat rows are read and left out. More than 100 newer chat decisions would hide an older mail decision from the list, and the person took part in those turns.
- `heartbeat` is not yet in `Msg.Enum` CHANNEL (39.2's append, in backlog), and no matrix row needs it. `Intake` copies the channel, `Digest.Data.Item.Channel` is a plain string, `Delivery.Record` validates the notice's own `web` channel, and no `Bridge.Audit` writer is on the denied-step path.
- `%ExecDirect` is privilege-checked, and only `Ownership` and `Eval` read a bridge table by SQL today. No hosted rule forbids it (`test-class-rules.sh`), and `BeatOutcomes` proves the read in the production's own job.
- The 4,000 characters bound the status block, not the checklist too. NFR-27 reads "1,000 characters of checklist plus 4,000 of snapshot", and AD-18 says the snapshot is at most 4,000.
- `Key` hashes the uncut status. Otherwise a new incident past the cut would leave the key unchanged and a quiet beat would skip it, against AC 4 and the point of the skip.
- User-turn decisions are left out. `Conversation`'s `Summary` is the first line of the user's message, so listing it breaks "no message text" (AD-18). Those rows are always tellnow and tell a beat nothing.
- A mail decision's `Summary` is "{Sender}: {Subject}", kept as stored. The AC names `Summary`, and FR-64 says the snapshot "can quote outside content". The list of identities that never appear (Never) is OcuTalon's own: refs, IRIS users, approvers and tokens. Veto U-275 keeps this.
- A beat's row is found by `Summary = Beat.SUBJECT`, because a fallback beat with no model request has no `Usage` row to give its channel. Only an Item with no sender and that exact subject or first line could match, and no channel builds one today.
- A new decision costs two model requests, not one: the beat that lists it, and the next one, whose decisions line has moved on. It is then quiet. Inside FR-64 and NFR-28.
- The line labels (`Incident:`, `Watch:`, ...) are code-written facts for the model. They appear in no card or notice. `Status at ... (built by OcuTalon):` and "(more not shown)" are the AC's.
- A reminder enters the text as its due time comes within one interval, so the key changes then. That is a real change for the person.
- Reminder `Text` can be the Chat model's tool argument, while FR-64 says the snapshot holds no model text. The AC names the reminder's text, so it stays.
- A sole reason of "Everything is fine." empties the reasons, which Decide treats as a fallback (invalid): a tell-now notice and the 4-hour back-off. It fails on the noisy side, and the paragraph tells the model not to write it. `heartbeat-all-clear` has a second reason so that the guard's removal can be seen; Story 39.6's cases measure the real model.
- The source comparison is a hosted check, not an IRIS test, because a throwaway has no `_bmad-output`. A test-held copy, as Epic 40's `Test.Agent.Persona` has, can't see the UX text change.

**Extend, don't copy (Rule 2):**
- `Tools.WatchAnswers.WatchNames` resembles the display-name read, and a copy is the better choice: it swallows a failed read, which here must throw, and `Checks` has no dependency on `Tools` today. `Beat` takes the names from the `Ownership.Checks` rows it already holds, a few lines. `Tools.RecentActivity` is not copied either: it answers JSON for a 24-hour window.
- `Ownership`'s reads carry the visibility rules, so `Beat` writes no incident or approval SQL.
- The clean-up of a field follows `Agent.Input.Quoted`'s list of line breaks. `Quoted` prefixes and can't be reused for stripping; `Beat` keeps its own one-line translate, naming the same characters.
- `BeatCase` lifts the test helpers instead of copying them.

**Integration ACs:** the Integration AC above, on real instances.

**Consumed-by:**
- 39.5: the row's view of an outcome this story proves.
- 39.6: the `heartbeat-*` scenarios and the snapshot's format, for the evaluation cases.

**Consumes:**
- Story 39.3's `Run` and `Key`; Story 30.4's send seam;
- `Data.Ownership`'s reads (Epic 2 onward);
- `Intake`, `OutcomeRouter`, `DigestStore`, the Gate, `ReplyGuard` (Epics 2, 3, 5, 8).

**Ledger inbox:** none.

**Footprint:** `ci/units.sh` and `docker/tests/test-triage-heartbeat.sh` are outside Epic 39's paths_hint and no open epic has changed them (Rule 11 (b), `footprint_extensions`, for the lead to report). The stability watch has ended, so both are allowed. `Agent/Triage.cls` is shared with Epic 40 and unchanged there. Epic 7 has changed `Test/Watch/Case.cls`, which `BeatCase` only extends. Nothing else contended is edited.

## Verification

`<lane>` is `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=39 stage=implement'`. Each command is a foreground call with `timeout: 600000`, one test class per call, never two at once. Slot D (`server: ocutalon-slot-d`, `namespace: OCUTALON`, port 52793) is only for `iris_doc_load` and compiling. Tear down only your own tags, also after a failure.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e39s4implw ci/warm.sh up`, once, after the scenarios exist -- expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e39s4implw ci/iris.sh class OcuTalon.Test.Checks.Snapshot` -- expected: `CLASS ... passed`.
- (loop) the same for `OcuTalon.Test.Checks.Beat`, then `OcuTalon.Test.Checks.Runs` -- expected: passed.
- (loop) `<lane> OCUTALON_RUN_TAG=e39s4impl ci/iris.sh class OcuTalon.Test.Checks.BeatOutcomes`, fresh (production) -- expected: passed; record the time.
- (loop) the same for `OcuTalon.Test.Checks.Heartbeat`, fresh -- expected: passed.
- (loop) `bash docker/tests/test-triage-heartbeat.sh` -- expected: exit 0.
- (once) `bash docker/tests/test-mock.sh` -- expected: exit 0.
- (once) `git diff --exit-code a22e223e40f9884e891ae6e2038bba64d53721a2 -- src/bridge src/ocutalon/cls/OcuTalon/Data src/ocutalon/cls/OcuTalon/Msg src/ocutalon/cls/OcuTalon/Core src/ocutalon/cls/OcuTalon/Live src/ocutalon/cls/OcuTalon/Web web src/ocutalon/cls/OcuTalon/Agent/Input.cls src/ocutalon/cls/OcuTalon/Checks/Process.cls src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls ci/mock/test` -- expected: exit 0.
- (once) the hosted checks in three parts: `. ci/units.sh; echo $CHECK_SCRIPTS`, then about a third per call, `for n in <part>; do bash docker/tests/test-$n.sh >/dev/null 2>&1 || echo "FAIL $n"; done` -- expected: no FAIL line.
- (once) `<lane> OCUTALON_RUN_TAG=e39s4impl ci/iris.sh shard lane-a@Checks`, fresh, then again with `--reverse` -- expected: passed; record the time.
- (once) `<lane> OCUTALON_RUN_TAG=e39s4impl ci/iris.sh class OcuTalon.Test.Agent.Instructions`, then the same for `OcuTalon.Test.Agent.TriageUserTurn` and `OcuTalon.Test.Agent.RequestSize`, fresh, one per call -- expected: passed (Triage's prompt changed).
- (once) `<lane> OCUTALON_RUN_TAG=e39s4implw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e39s4impl ci/iris.sh teardown`, also after a failure.

Pinning mutations to apply, observe red, revert byte-identical and record (Rule 19):
- AC 1: swap the watch and incident lines -> `Snapshot`'s full-snapshot test.
- AC 2: add `Cause` to the incident line -> `Snapshot`'s never-in-the-text test.
- AC 3: `STATUSMAX` of 5000 -> `Snapshot`'s cut test.
- AC 4: entry times through `ForMessage` -> `Snapshot`'s later-time test; `Run` keys the cut text -> the past-the-cut test; `LastRunAt` added to the watch line -> `Snapshot`'s watch-runs test and `BeatOutcomes`' real-watch test.
- AC 5: one word of the paragraph changed -> `test-triage-heartbeat.sh`; the extraction pattern broken -> the same, by its empty-extraction failure.
- AC 6: `READONLYSTOPWATCH` set to 1 in `Tools/WatchTools.cls` -> `BeatOutcomes`' act test.
- AC 7: the Item in the Tick's session -> `BeatOutcomes`' trace assertion.
- AC 8: "everything is fine" taken out of `ReplyGuard.BANNED` -> `BeatOutcomes`' guard test.

Shared surfaces: `CHECK_SCRIPTS` (one name added; `test-ci-config.sh` asserts on it); the text of a beat's Item and the value of `LastSnapshotKey` (`Test.Checks.Beat`, `Test.Checks.Heartbeat`, `Test.Checks.Runs`); Triage's `INSTRUCTIONS` (`Test.Agent.Instructions`); the `Test.Checks` class list (`ci/iris.sh` shards, `test-ci-config.sh`).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

Added test time: `BeatOutcomes` about 20 to 30 s in the `shards` group, and `Snapshot` under 1 s (inference from `Heartbeat`'s 12 to 14 s; record the measured time).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
