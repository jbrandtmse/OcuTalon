---
title: 'Story 8.4: Set, list and cancel reminders in plain words'
type: 'feature'
created: '2026-10-27'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
warnings: [oversized, multiple-goals]
deferred: []
---

<intent-contract>

## Intent

**Problem:** The chat's reminder tools (Story 1.10) send `SetReminder` with `DelaySeconds` or `LocalDueAt`, `ListReminders` and `CancelReminder`. Today `ReminderOps` (Story 8.3) carries out only a `SetReminder` with a UTC `DueAt` and answers everything else `not_built`. So "Remind me in 1 minute to stretch" and guide step 2 create nothing, and a user can neither list nor cancel a reminder (FR-34).

**Approach:** `ReminderOps` becomes a built owner of all three verbs.
- **Set.** It resolves exactly one due form to a UTC `DueAt` through `OcuTalon.Data.Time`: `DelaySeconds` counts from the command's arrival, and `LocalDueAt` is converted in the instance zone by a new `Data.Time.FromLocal`. It refuses a bad command with a plain-English `Message` and writes nothing. Otherwise it creates the reminder exactly as Story 8.3 does.
- **List.** It answers the session's pending reminders, earliest due first, in the shape the list tool reads (DW-135).
- **Cancel.** Under the row's lock it marks the session's pending reminder cancelled and publishes the `reminder` event (cancelled). It then ends the waiter at once by interrupting its alarm. A waiter whose row isn't pending sends nothing (8.3).
- **Repeats.** A repeated `IdempotencyKey` gets the first result back. A key reused for different fields is refused (AD-1, DW-141).
- **Split (lead ruling, 2026-10-27, decide, doctrine U5).** This story is the command side only. The chat side moved to Story 8.6 (`8-6-reminders-through-the-chat-on-the-demo-path`): the CI-mock scenarios ("Thursday at 10", cancelling through the chat, the `guide-reminder.json` extension of DW-232), the chat production test (`ReminderChat`), turning on REL-2's reminder step (`03-reminder.spec.ts`), DW-210, and the `test-demo-path.sh` header comment. 8.4 proves set, list, cancel and repeats through the commands the Chat agent's tools send (Story 1.10), in its own `Test/Schedule/**` tests and `web/e2e/reminder/reminder.spec.ts`; it writes no CI-mock scenario and does not touch the demo-path specs.

## Boundaries & Constraints

**Always:**
- **Command path.** Commands go only through `Commands.Submit`, then `CommandsIn`, then `ReminderOps`, which answers a synchronous `CommandResult` (AD-1). The `Reminder` row is the truth. `ReminderTimer`, `ReminderStart` and `Schedule.Reminder.Start`/`Wake` stay as Story 8.3 built them (AD-5, frozen waiter).
- **Every verb checks the session first.** An empty `SessionRef`, or one that names no `Session` row, is refused (`no_session`).
- **Set.**
  - The due-form rule lives in one pure method, `Schedule.Reminder.Resolve(command, now, .dueAt)`. It returns `""` with `dueAt` set, or one refusal code. The checks run in this order:
    1. A `Text` that is blank after stripping whitespace is `no_text`.
    2. Not exactly one of `DueAt`, `DelaySeconds` and `LocalDueAt` is set: `due_forms`.
    3. The one form can't be read: `bad_time`. That is a `DueAt` that `Data.Time.Seconds` can't read, a `DelaySeconds` that isn't an optionally signed whole number, an `AddSeconds` result of `""`, or a `LocalDueAt` that `FromLocal` gives `""` for.
    4. A due time not later than `now` is `past`. A `DelaySeconds` of 0 or less is past.
  - `now` is `Data.Time.NowUtc()`, taken once when `OnMessage` starts (the arrival).
- **Times.** `Data.Time.FromLocal(local)` is the only local-to-UTC converter. It takes exactly `YYYY-MM-DDThh:mm:ss`, reads it in the process zone and returns `YYYY-MM-DDThh:mm:ssZ`, or `""` for an unreadable value or one out of range. The conversion is `$ZDateTime(<local $H>, -3)`.
  - A spring-forward gap time and a fall-back overlap time convert as build 154 does, as measured in planning (Design Notes).
  - Nothing in Schedule renders text (AD-18, AD-32).
- **List.** It reads only through `Ownership.Reminders(SessionRef)`: pending rows, `ORDER BY DueAt, ID` (AD-4). The answer is `Ok` 1, `Outcome` `listed`, and `Data` = `{"reminders":[{"ref","text","dueAt"}]}` with exactly those three keys per item. An empty list is `{"reminders":[]}`.
- **Cancel.**
  1. The target must be among `Ownership.Reminders(SessionRef)`. Anything else is refused `no_reminder`, with one message for an unknown Ref, another session's Ref, a fired reminder and a cancelled one, so another session's reminder is never revealed (AD-4).
  2. Open the row with `RefIndexOpen(ref, 4)`. Under that lock, re-check that it is `pending` (otherwise `no_reminder`), set `State` cancelled and `CancelKey`, save, and release.
  3. Publish `reminder` (cancelled; `FromRow`). A failed publish is a warning.
  4. End the waiter: send `Ens.AlarmTriggerRequest` for every not-completed `Ens.AlarmRequest` header from `ReminderTimer` in the waiter's session (`TraceHeaderId`) to `Ens.Alarm`, with no response required. The send runs with `..%SessionId` = `TraceHeaderId` and `..%SuperSession` = the session's `TraceRef`, and both are put back afterwards, as `StartWaiter` does (AD-26). A failed interrupt is a warning. The waiter then ends at its due time instead.
  5. Answer `Ok` 1, `cancelled`, `Ref`, `DueAt`.
- **Repeats (AD-1, AD-8, DW-141).**
  - A `SetReminder` with a non-empty key finds the session's row whose `IdempotencyKey` is that key.
    - If `Text` matches, and for an absolute form the resolved UTC equals the row's `DueAt`, it answers that first result (`Ok` 1, `set`, `Ref`, `DueAt`) and writes nothing.
    - Otherwise it is refused `reused_key`.
  - A `CancelReminder` with a non-empty key finds the session's row whose `CancelKey` is that key.
    - The same `ReminderRef` answers the first result (`Ok` 1, `cancelled`, `Ref`, `DueAt`).
    - Another Ref is refused `reused_key`.
  - A refused command, repeated, is checked again and gets the same refusal, because refusals depend only on state that never comes back.
  - `ListReminders` is read-only and answers the current list every time.
  - An empty key turns off repeat detection.
- **Answers.** A refusal is `Ok` 0, `Outcome` `refused`, and the code's `Message` from the Design Notes table, word for word. The tools pass the `Message` to the model unchanged (`CommandCall.Answer`). An error thrown inside a verb is logged and answered `failed` with `CommandsIn.#MESSAGEFAILED`. A message that isn't one of the three verbs gets an error status (not 5003).
- **Events.** `ReminderOps` publishes `reminder` created (8.3) and cancelled, only after the change commits. The waiter publishes fired (AD-12, AD-33).
- **Tests.** IRIS tests go in `OcuTalon.Test.Schedule` (shard `lane-b`). Those that need the production run on throwaways only (AD-22, Rule 21). Each test creates and removes what it asserts on, and ends every waiter it started.

**Never:**
- Don't edit Lane A's files: `Agent/**`, `Tools/**`, `Test/Tools/**`, `Test/Agent/**`, `Test/Bridge/**`, `src/bridge/**` (AD-29). Use their helpers only.
- Don't edit any contended path except as the orchestrator rules on the two named under Clarification Needed.
- Don't touch anything of Epic 16. Story 16.4 turns its own sign-out test onto this cancel path (U-107, DW-291).
- Don't change `ReminderTimer`'s properties or methods, `ReminderStart`, the catalog, the live-event types or payload shapes, `Production.cls`, `web/src/**`, or `ci/mock/` outside `scenarios/B/`.
- Don't add a second scenario for "Remind me in 1 minute to stretch.", and leave `B/guide-reminder.json` unchanged (DW-232; `Test.Demo.GuidePrompts` and `guide-view.test.mjs` pin it).
- No new table, index or production item. No hand-written `Storage` block. No literal non-ASCII character in code (Rule 14). No seconds asserted in CI beyond order and outcome (NFR-10).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Set, relative | Text, `DelaySeconds` 60 | Row `DueAt` = `AddSeconds(now, 60)`, one waiter, created event; `Ok` 1 `set` `Ref` `DueAt` | none |
| Set, local | Text, `LocalDueAt` `2030-11-07T10:00:00` | `DueAt` = `FromLocal(...)` (America/New_York: `2030-11-07T15:00:00Z`; one week earlier, `2030-10-31T10:00:00`, gives `14:00:00Z`) | none |
| Set, UTC | Text, future `DueAt` | as Story 8.3 | none |
| Refusals | no session; blank text; 0, 2 or 3 forms; unreadable form (`2026-02-30T10:00:00`, `next Thursday`, a `DelaySeconds` past year 9999); past (`DelaySeconds` 0 or -5, a past `LocalDueAt` or `DueAt`) | `Ok` 0 `refused`, the code's Message; no row, waiter or event | none |
| List | session with pending rows due later and earlier, one fired, one cancelled; another session's row | `Data` lists only the session's two pending rows, earliest first, keys `ref,text,dueAt`; `Ok` 1 `listed` | `Ownership` error is answered `failed` |
| Cancel | the session's pending reminder with a live waiter | Row cancelled with `CancelKey`; one cancelled event; the waiter ends at once with no `Notify` header; `Ok` 1 `cancelled` `Ref` `DueAt` | interrupt fails: warning, and the waiter ends at its due time |
| Cancel refused | another session's Ref, unknown Ref, a fired or a cancelled row | `Ok` 0 `refused` `no_reminder`; nothing changes; no event | none |
| Cancel races fire | the waiter holds the lock and fires | Cancel sees `fired` under the lock: `no_reminder`, nothing changes | none |
| Repeat | same key, same verb and fields | the first result; no second row, waiter or event | none |
| Reused key | same key, same verb, other Text, due instant or Ref | `Ok` 0 `refused` `reused_key`; nothing changes | none |
| Not a verb | any other message | an error status, not 5003, so `CommandsIn` answers `failed` | logged |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls` (8.3):
  - `STUB` `:20`; `OnMessage` `:31-45`, whose `Accepts`/`SessionExists` gate goes;
  - `Set` `:48-79`: `NewRef` is at `:51`, and the save, `StartWaiter`, created publish and answer stay;
  - `StartWaiter` `:84-102`: its session save and restore is the pattern for `EndWaiter`;
  - `SessionExists` `:105`, `Result` `:112`, `MESSAGESET` `:29`.
- `src/ocutalon/cls/OcuTalon/Schedule/Reminder.cls`:
  - `Accepts` `:30-39` is replaced by `Resolve`;
  - `Wake` `:98-135` already ends without sending when the row isn't pending. It is checked before the early-wake rule, so an interrupted wake on a cancelled row ends. No change.
- `src/ocutalon/cls/OcuTalon/Data/Time.cls`: `Seconds` `:27`, `AddSeconds` `:42`, `ToLocal` `:54`, `Zone` `:84`. It has no local-to-UTC method. `src/bridge/cls/OcuTalon/Bridge/Time.cls:40-53` `DayStartUtc` uses `$ZDateTime(days_",0", -3)` (read only).
- `src/ocutalon/cls/OcuTalon/Data/Reminder.cls`: 8 properties, storage slots 1-9, `RefIndex` unique, `SessionRefIndex`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: `:219` `Reminders(sessionRef, .sc)` (pending, `ORDER BY DueAt, ID`, `:579`). Contended: call only.
- `src/ocutalon/cls/OcuTalon/Msg/Command/SetReminder.cls`: `Text`(1000), `DueAt`(20), `DelaySeconds` `%Integer`, `LocalDueAt`(19). `CancelReminder.ReminderRef`(22). `Msg/Command.cls` `IdempotencyKey`(128). `Msg/CommandResult.cls`: `Ok`, `Message`(1000), `Outcome`(32), `Ref`, `DueAt`, `Data` (a JSON string, MAXLEN "").
- Lane A consumers (read only):
  - `Tools/ReminderTools.cls:49-80`: set sends only `Text`/`DelaySeconds`/`LocalDueAt` and refuses a non-digit delay itself; list; cancel by `reminderRef`.
  - `Tools/CommandCall.cls`:
    - `:38-41` the key `<ItemId>:<position>`;
    - `:63` `Answer` gives the model `ok`, `message`, and `ref`, `due` and `dueLocal` when set (no `Outcome`);
    - `:82` `Listed` needs the `reminders` array, each `ref`/`text`/`dueAt` readable, or answers `NOTREAD`.
  - `Test/Tools/CommandsDouble.cls:41-95`: the double's outcomes (`created`, `cancelled`, `listed`, `refused`).
  - `Agent/Chat.cls:18` `MaxIterations` 4; `:36` INSTRUCTIONS.
  - `Core/Conversation.cls:406`: a retry gets a new `ItemId`.
  - `Bridge/Context.cls:73`: `CommandCount` restarts at 0 on `Begin`.
- `irislib/Ens/BusinessProcess.cls:189` `SetTimer` (its `pAlarmHandle` is the `Ens.AlarmRequest` id). `irislib/Ens/Alarm.cls:21-52,358-380`: an `Ens.AlarmTriggerRequest(handle)` interrupts; an unknown handle is a no-op. `irislib/Ens/AlarmTriggerRequest.cls`. Reference only.
- Tests to change, Epic 8's (`src/ocutalon/cls/OcuTalon/Test/Schedule/`):
  - `ReminderLogic.cls`: `TestAccepts` `:54-95` and `TestNotHandledWritesNothing` `:137-167` pin the old not-implemented answers; the header bullets are at `:6-7,11-12`.
  - `ReminderFixture.cls`: `Set` `:14` (bridge context, origin tool, key `zzrem<n>`) and `Remove` `:54`.
  - `Reminders.cls`: the production base, with clean-up in `OnAfterOneTest`.
  - The probes `ReminderOpsProbe`, `ReminderOpsStartedProbe`, `ReminderOpsSendProbe` and `ReminderTimerDouble` stay valid.
- Shared by entry (Epic 8's entries):
  - `Test/Core/ProductionItems.cls:34`, the ReminderOps row `"stub": 1`;
  - `Test/Data/Tables.cls:431-447`, the `OcuTalon.Data.Reminder` contract. `AssertContract` checks the exact property and index sets.
- Must stay green with no edit:
  - `Test/Install/Production.cls:139-185` `TestStubsAnswer` (Lane B stubs remain);
  - `Test/Core/CommandsRouting.cls` (probes);
  - `Test/Tools/Reminders.cls` (the double);
  - `Test/Demo/GuidePrompts.cls:96-108` (a session-less owner, so no row);
  - `Test/Demo/Guide.cls:111-124` (a cancelled reminder doesn't mark step 2 done);
  - `Test/Web/Api.cls`, `Test/Live/Payloads.cls`;
  - `Test/Contract/Ac.cls:289-299`, which checks only the listed signatures.
- **Contended and red once ReminderOps is built** (see Clarification Needed):
  - `Test/Core/CommandsInProduction.cls:35,50-56` (`SetReminder|ReminderOps|web_user` expects `0|not_built` and an error header);
  - `docker/tests/test-production.sh:17-19,194-197` (row 17 expects `not_built` for a `ListReminders` with no `SessionRef`).
- Test helpers (call only):
  - `Test/Agent/RunnerFixture.cls`: `NewRequest` `:276` (ownerRef), `Run` `:378`, `StepsOf` `:335`, `DecisionOf` `:315`, `PointKeys`/`RestoreKeys` `:456-463`, `UseItemClass`/`RestoreItemClass` `:645`, `DeleteSteps` `:349`, `FindRequests`.
  - `Test/Contract/Mock.cls:365,378` (`LogMark`, `LogSince`).
  - `Test/Demo/GuidePrompts.cls:127-160` (`Turn`, `ToolInputOf`: the private pattern to copy).
  - `Test/Tools/Reminders.cls:926-960` `AssertSteps` (private): the agent-step check to copy.
  - `Test/Bridge/ZoneCase` (the zone base: `$SYSTEM.Process.TimeZone`, restored per test).
  - `Test/Core/InProduction.cls`, `Test/Core/Observe.cls`.
  - `Test/Data/Fixture.cls:50` `Reminder(sessionRef, dueAt, state, fields)`.
- Mock:
  - `ci/mock/mock.mjs`: selection `:11-17`; a marker beats a prompt; the reply index is `min(k, last)` (`:262,291`); `input` is copied verbatim (`:307`), so there is no reference to a tool result.
  - `ci/mock/scenarios.mjs`: refuses a repeated prompt (`:259`), a prompt contained in another (`:272`), and a duplicate name across A and B (`:244`).
  - `B/guide-reminder.json`: `set_reminder {"text":"stretch","delaySeconds":60}`, then "The CI mock set the reminder."
  - The A marker names in use: `reminder-cancel`, `reminder-list`, `reminder-set-local`, `reminder-set-relative`, `reminder-set-two`.
- Web:
  - `web/e2e/demo-path/03-reminder.spec.ts`: one `notBuilt(..., '8.4')`.
  - `02-watch.spec.ts:10-25`: the describe-level skip pattern for a stack-only test.
  - `web/e2e/support/devices.ts:148-161` `pointKeys`/`restoreKeys`, and `demo-switch/mailbox.spec.ts:33-44` (`beforeAll`/`afterAll`, 240 s).
  - `guide/guide.spec.ts:44-50` (`stepName`, `promptOf`) and `:277` (step 2 Send).
  - `support/floor.ts` `rowOf`; `support/iris.ts` `irisScript`/`chk`; `sign-in/helpers` `signInReadme`/`signIn`.
  - `web/e2e/reminder/reminder.spec.ts` (8.3, rail user).
  - `web/src/app/rail/rail-view.ts:311` keeps only `state === 'pending'`, and its row title is the text exactly (`:235-242`).
  - `web/scripts/demo-path-summary.test.mjs:332-363`: `playwrightEnv()` and 'skip every unbuilt part', which needs at least one skipped, Story-labelled, non-`@floor` test per step 2 to 6.
- `src/ocutalon/cls/OcuTalon/Production.cls:68`: ReminderOps `PoolSize="1"`, so commands are serialized. `Demo/Guide.cls:76,97` with `Ownership.cls:653`: step 2 is done for a pending or fired reminder.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0** (implement stage, warm throwaway; record each result under Design Notes as measured or (inference)):
  - (a) For a waiting reminder, `ReminderOps` sends `Ens.AlarmTriggerRequest(<the Ens.AlarmRequest body id>)` to `Ens.Alarm` with no response required, in the waiter's session. The waiter's `OnResponse` runs at once and the instance completes. Record the trigger header (session, `SuperSession`, status). A trigger whose alarm already fired adds no event-log error.
  - (b) The status values of a waiting reminder's `Ens.AlarmRequest` header, used for the "not completed" filter.
  - (c) The guide's step 2 Send on a `live:demo-path` stack with `pointKeys` reaches the mock through `WebChatIn`.
  - If (a) fails, drop the interrupt (`EndWaiter`). The cancelled waiter then ends at its due time (8.3), and the tests wait for that due time using short dues. Record it.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Time.cls`: add `FromLocal(local As %String) As %String` per the Always list. The doc states the measured gap and overlap behaviour.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Reminder.cls`: append these and commit the compiler's storage block (slots 10 and 11). No index. Correct `State`'s doc only where needed.
  - `IdempotencyKey As %String(MAXLEN = 128)`: the key of the `SetReminder` that created the row.
  - `CancelKey As %String(MAXLEN = 128)`: the key of the `CancelReminder` that cancelled it.
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/Reminder.cls`: replace `Accepts` with `Resolve(command, now, Output dueAt) As %String` (the Always rule; codes `no_text`, `due_forms`, `bad_time`, `past`). Correct the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls`:
  - Delete `STUB`. Add one `MESSAGE*` parameter per code (Design Notes) plus `MESSAGELISTED` and `MESSAGECANCELLED`.
  - `OnMessage`: take `now`; dispatch `SetReminder` to `Set`, `ListReminders` to `List` and `CancelReminder` to `Cancel`, each in Try/Catch (a throw is `failed`). Any other message gets an error status.
  - Each verb: the session check, then (set and cancel) the repeat check, then its rule.
  - `Set` also stores `IdempotencyKey`, and takes its Ref from a new private `NewRef()`, a seam a test subclass overrides.
  - New private `List`, `Cancel`, `Refuse(code)` and `EndWaiter(row)`. `EndWaiter` and `StartWaiter` share one private session save-and-restore helper.
  - The class doc states what is built.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls`: the ReminderOps row gets `"stub": 0` (Epic 8's row).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls`, Epic 8's `OcuTalon.Data.Reminder` entry: add `"IdempotencyKey": "%String(MAXLEN=128)"` and `"CancelKey": "%String(MAXLEN=128)"`.
- [ ] **Only as the orchestrator rules (Clarification Needed Q1, Q2):**
  - `Test/Core/CommandsInProduction.cls`: remove the `SetReminder|ReminderOps|web_user` entry, and ReminderOps from the class doc's stub-owner sentences.
  - `docker/tests/test-production.sh` row 17: `not_built` becomes `refused` in its two expected lines and in its header bullet.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderFixture.cls`:
  - add `Submit(sessionRef, command)`, the bridge-context submit that `Set` now uses;
  - add `Cancel(sessionRef, ref)` returning `{ok, outcome, message}`;
  - add `CancelPending(sessionRef)`, which cancels every pending reminder of the session through `Cancel` and returns the count;
  - `Remove(ref)` first cancels a pending row and waits, at most 10 s, until no `ReminderTimer` instance has that Ref.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderOpsFixedRef.cls` (new): a `ReminderOps` subclass whose `NewRef()` returns, and kills, `^OcuTalonTest("ReminderOpsFixedRef")` when it is set, and otherwise calls the parent.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderLogic.cls` (no production):
  - Replace `TestAccepts` with `TestResolve`: each due-form, refusal and order row of the matrix, by code.
  - Replace `TestNotHandledWritesNothing` with `TestRefusalsWriteNothing`, on a shadow instance: each refusal gives status OK, `0|refused` and the exact Message, with no row and no event. A non-verb message gives an error that is not 5003.
  - Add `TestListShape`, on fixture rows (matrix row List): `Data` is exactly right. **Integration AC (DW-135):** `Tools.CommandCall.Listed` of that answer gives `ok` true and the two refs in due order, not `NOTREAD`, and `{"reminders":[]}` for an empty session.
  - Add `TestCancelFixtureRow`: a row with no waiter is cancelled, with `CancelKey`, one cancelled event and no trigger header. The same key again gives the first result and no second event. A new key gives `no_reminder`.
  - Add `TestSetRepeat`, on `ReminderOpsStartedProbe`: the same key twice gives one row and identical answers. The same key with other text gives `reused_key` and no second row. An empty key twice gives two rows.
  - Update the header.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderZone.cls` (new; extends `OcuTalon.Test.Bridge.ZoneCase`; no production):
  - `TestFromLocal`, in America/New_York: the two Thursdays, the gap `2026-03-08T02:30:00` gives `07:30:00Z`, the overlap `2026-11-01T01:30:00` gives `05:30:00Z`, `ToLocal(FromLocal(x))` = x for both Thursdays, and unreadable inputs give `""`. Also Asia/Kolkata and no zone. And `FromLocal(day_"T00:00:00")` = `Bridge.Time.DayStartUtc(day)` for 2030-11-01 to 2030-11-09 (AD-18's comparison).
  - `TestResolveThursdayAt10`: `Resolve` in New York gives the two Thursdays' UTC times.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/Reminders.cls` (production, throwaways): add these, through `ReminderFixture.Submit`/`Cancel`.
  - `TestSetByDelayAndLocal` (AC 1): delay 30 gives a `DueAt` within `[AddSeconds(before,30), AddSeconds(after,30)]`, a waiter waiting and a created event. `LocalDueAt` `2030-11-07T10:00:00` gives a `DueAt` of `FromLocal` of it.
  - `TestCancelEndsWaiter` (AC 3): due in 120 s; cancel gives `1|cancelled`. The row is cancelled. No live instance remains within 10 s, and there is no `ReminderTimer`-to-`Notify` header. Events are created, then cancelled. `StateBody` shows no rail row. The waiter's session holds the trigger header.
  - `TestCancelIsolationAndRepeats` (AC 3b): sessions A and B. B cancelling A's Ref gives `no_reminder`, and A is still pending with no event. A cancels twice with one key: the second answer is the first result, with one cancelled event and one trigger. A cancels with a new key: `no_reminder`. A fixture row that has fired gives `no_reminder`.
  - `TestSetRepeatOneWaiter` (AC 3b): the same key twice gives one row, one `ReminderOps`-to-`ReminderTimer` start header and one created event.
  - `TestListToolReadsTheList` (Integration AC, DW-135): `Tools.ReminderTools.ListReminders()`, under a bridge context of the session, lists its two real reminders in due order.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderChat.cls` (new; production, throwaways and CI):
  - Setup: `PointKeys` and `UseItemClass("ReminderOps", "OcuTalon.Test.Schedule.ReminderOpsFixedRef")` in `OnBeforeAllTests`; restore both in `OnAfterAllTests` on every path. Turns go through `RunnerFixture.NewRequest("turn", "user", text, .ref, <session Ref>)` and `Run` (with `SuperSession` = `TraceRef`), and the mock's log is read.
  - `TestGuidePromptSetsReminder` (AC 2):
    - The answer is "The CI mock set the reminder.", not a fallback. Two requests are selected by prompt `guide-reminder`, and the second carries a `tool_result` with `ok` true and the row's Ref.
    - One pending row: text `stretch`, its `DueAt` within the `+60` bracket, a live waiter. It shows in the rail (`StateBody`).
    - The steps are model, tool, model. The tool step's summary names `set_reminder`, its status is ok, and every step is in the decision's session.
  - `TestThursdayMarkerSetsLocalReminder` (AC 2): "Remind me Thursday at 10 to load the new certificate. [[mock:reminder-thursday]]".
    - The answer is the scenario's.
    - The row has text "load the new certificate", and its `DueAt` = `FromLocal("2030-11-07T10:00:00")` in the stack's zone.
    - The rail and the agent step are as above.
  - `TestCancelThroughChat` (AC 3):
    - Sessions A and B each send the guide prompt. A's reminder takes `zzReminderChatCancel01` through the fixed-Ref seam; any leftover row with that Ref is removed first.
    - A sends "Cancel my reminder to stretch. [[mock:reminder-cancel-chat]]". The answer is "The CI mock cancelled the reminder." with three requests.
    - The list `tool_result` holds exactly one reminder, A's Ref (B's Ref is absent). The cancel `tool_result` has `ok` true.
    - A's row is cancelled with `CancelKey` = `<ItemId>:2`. A's waiter ends with no `Notify` header. A's events are created, then cancelled. A's rail is empty.
    - B's row is pending and B's waiter is live.
  - Clean-up: `ReminderFixture.Remove`, plus the turns' steps (`DeleteSteps`).
- [ ] `ci/mock/scenarios/B/reminder-thursday.json` (new): marker `reminder-thursday`; `set_reminder {"text":"load the new certificate","localDueAt":"2030-11-07T10:00:00"}`, then the text "The CI mock set the Thursday reminder."
- [ ] `ci/mock/scenarios/B/reminder-cancel-chat.json` (new): marker `reminder-cancel-chat`; `list_reminders {}`, then `cancel_reminder {"reminderRef":"zzReminderChatCancel01"}`, then the text "The CI mock cancelled the reminder."
- [ ] `ci/mock/scenarios/B/guide-reminder.json`: unchanged. It is AC 2's guide scenario (DW-232).
- [ ] `web/e2e/demo-path/03-reminder.spec.ts`: replace the `notBuilt` call with a describe whose describe-level skip is `!process.env['OCUTALON_URL']`, with the text `Story 8.4 needs the first-start stack (OCUTALON_URL), which a run without one lacks`. Its hooks are inside the describe, so nothing starts without a stack.
  - `beforeAll` (240 s): `pointKeys`.
  - One untagged test, as the README account:
    1. Step 2 reads upcoming. Select it and press Send.
    2. The user message is the exact prompt with "From the demo guide". The reply "The CI mock set the reminder." shows.
    3. Under Reminders, a row whose text matches `/^stretch\b/i` shows a countdown: a middle dot, then `in <n> s`. The test's regular expression writes the dot as the escape `·` (Rule 14).
    4. The guide's "Step 2, Reminder, done" shows.
  - `afterAll`: `ReminderFixture.CancelPending(<README session>)` through `irisScript`, then `restoreKeys`.
- [ ] `web/e2e/reminder/reminder.spec.ts` (8.3's): add test 2, "a cancelled reminder leaves the rail within one live update" (AC 3, NFR-9):
  - `ReminderFixture.Set` due in 300 s; sign in as the rail user; the row shows.
  - `ReminderFixture.Cancel` through `irisScript` answers `1|cancelled`. Within 10 s the row is gone, and no notice card with its text exists.
  - `afterEach` runs `Remove`.
- [ ] `web/scripts/demo-path-summary.test.mjs` (DW-210): `playwrightEnv()` sets `PLAYWRIGHT_BROWSERS_PATH` to a path that holds no browsers (for example `/nonexistent-ocutalon-browsers`), so a demo-path test that starts a browser before it skips goes red everywhere. Update its header if needed. This is a footprint extension.

**Acceptance Criteria:**
1. **Due forms and refusals.**
   - Given the running production and a session, when `SetReminder` commands go through `Commands.Submit` under a bridge context, then:
     - a `DelaySeconds` counts from the command's arrival;
     - a `LocalDueAt` is converted through `Data.Time` in the instance's zone, so "Thursday at 10" is 10:00 local in a daylight-saving week (`2030-11-07T10:00:00` in New York is `15:00:00Z`, the week before is `14:00:00Z`);
     - each gives one pending row and one waiting waiter.
   - An empty Text, a past due time, or anything other than exactly one due form gets `Ok` 0 with the plain-English Message, which `CommandCall.Answer` passes back unchanged, and creates no row, waiter or event. (FR-34, NFR-24, AD-18)
2. **Through the chat.** Given the CI mock and pointed keys, when the guide prompt "Remind me in 1 minute to stretch." (`B/guide-reminder.json`) or "Remind me Thursday at 10 to load the new certificate." (`B/reminder-thursday.json`, marker) is sent as a chat turn, then:
   - Chat calls `set_reminder`, `ReminderOps` creates the reminder, the reply confirms it, the rail's `/state` lists it, and the tool call is an agent step in the decision's trace session.
   - On a `live:demo-path` stack, pressing Send on guide step 2 shows the reply and a "stretch" row with its countdown under Reminders, and the guide marks step 2 done. REL-2's step 3 spec runs and passes there. (FR-34, REL-2, AD-9, AD-22, AD-29, UX-DR44)
3. **List and cancel.** Given a pending reminder set through the chat in each of two sessions, when one session sends "Cancel my reminder to stretch." (`B/reminder-cancel-chat.json`: it lists, then cancels by Ref), then:
   - `ListReminders` answers only that session's pending reminder.
   - `CancelReminder` marks its row cancelled. Its waiter ends without any notification. One `reminder` event (cancelled) removes the row from the rail within one live update (the browser test). The reply confirms. The other session's reminder is untouched.
   - A cancel naming another session's reminder, or one already fired or cancelled, is refused and changes nothing. A command repeated with the same `IdempotencyKey` returns the first result with no second row, waiter or event. A key reused for different fields is refused. (FR-34, NFR-9, AD-1, AD-4, AD-8, UX-DR54)
4. **REL-2's skip rule (DW-210).** Given `npm --prefix web test`, when 'skip every unbuilt part' runs without `OCUTALON_URL` and with no browser available, then step 3 reports `skipped, 0 passed, 1 skipped (Story 8.4: ...)` and no browser starts.

## Spec Change Log

- 2026-10-27 (lead, after the plan's intent-gap HALT): the orchestrator allowed Q1, Q2 and Q4 and routed DW-140/DW-142 (U-118); the lead split the story (8.4 command side, 8.6 chat side) and ruled Q3 decide. Recorded under Intent and Design Notes; Clarification Needed removed; status set to `draft` to re-plan this story as the command side.

## Review Triage Log

## Design Notes

**Rulings in force (recorded by the lead, 2026-10-27):**
- **Split (lead, decide, U5):** 8.4 is the command side; 8.6 takes the chat side (see Intent). The whole earlier plan is kept in git at 467dfae for reference.
- **Q1, ALLOWED (orchestrator, decide):** `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls` stub rows are shared by entry (since Epic 5's ruling). Remove ONLY the `SetReminder|ReminderOps|web_user` entry from `TestStubOwnersAnswerPlainEnglish`'s table, and ReminderOps from the stub-owner sentences of the class doc (L4-5) and the method doc (L27-29). `TestTraceAndThread` routes `ListReminders` to ReminderOps: if one of its assertions depends on the stub's answer, change only that assertion. Prove the built ReminderOps in Epic 8's own tests (`Test/Schedule/**`), not in that table. Expect a same-line conflict at integrate-forward with Epic 5 (it removes WatchOps and IncidentManager from the same sentences and table line): a plain union, every built owner removed. Reported as a footprint extension.
- **Q2, ALLOWED (orchestrator, decide):** `docker/tests/test-production.sh` row 17: change only the two expected lines (`submit-user`, `submit-tool`) from `not_built` to `refused`, and the matching header phrase ("ReminderOps' plain-English refusal (the command names no session)"). Nothing else. Reported as a footprint extension.
- **Q3 (lead, decide):** `Data.Reminder` gains `IdempotencyKey` and `CancelKey` (`%String(MAXLEN=128)`, no index), append-only (AD-5), for AD-1's repeat rule; Epic 8's own `OcuTalon.Data.Reminder` entry of `Test/Data/Tables.cls` XData `Contracts` gets the two matching lines (that XData is shared by entry).
- **Q4 (orchestrator, decide):** belongs to Story 8.6 (the `docker/tests/test-demo-path.sh` header comment, only once 8.6 turns spec 03 on). Not this story.
- **DW-140 and DW-142 (orchestrator, U-118):** declined here; the lead re-owns them at the spec gate (DW-142 to Story 11.1, DW-140 to Story 11.6). Never edit `Agent/Chat.cls` (Lane A's, AD-33).
- **DW-210 and DW-232:** re-owned to Story 8.6 with the split; not this story's.
- **Story 16.4 (U-107 kept; DW-291 under 16.4):** 8.4 delivers the real cancel path; 16.4's sign-out test uses it (or a recording double turned on by whichever of 8.4/16.4 merges second). 8.4 touches nothing of Epic 16. The sign-out cancels with one `CancelReminder` per pending Ref; no cancel-by-session entry point is needed.
- **No local absolute paths** in this spec or any committed file (CI's `test-boundaries.sh`). Write the lane-C lock folder as `"$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c"` (it resolves from the worktree) or as the dispatch placeholder.

**Governing ADs:**
- AD-1: the command path; origin `tool` under a context; the owner ignores a repeat.
- AD-4: session-scoped reads through `Ownership`; another session's reminder is never revealed.
- AD-5: the row is the truth; the frozen waiter stays unchanged; append-only storage.
- AD-8: a re-sent turn never acts twice.
- AD-9: agent steps.
- AD-12 and AD-33: events after the commit; `ReminderOps` publishes created and cancelled, the waiter publishes fired.
- AD-18: `Data.Time` is the only converter; the instance zone is the container's `TZ`.
- AD-20: Chat's 4 iterations (DW-140, declined below).
- AD-22: B scenarios (marker or prompt); `lane-b`; throwaways.
- AD-26: the trigger goes in the waiter's own session under `TraceRef`.
- AD-29: Lane B's files; the REL-2 step spec turned on.
- AD-32: no rendering in Schedule.

Conventions: "Times", "Identifiers", "Tests" (demo-path `notBuilt` and `@floor`), "SessionBroken retry".

**Refusal codes and messages.** All are `Outcome` `refused`. The messages are for the model and are never shown as written (8.3, Decided 5).

| Code | `Message` |
| --- | --- |
| `no_session` | "This conversation has no signed-in session, so nothing was done." |
| `no_text` | "The reminder has no text, so nothing was set." |
| `due_forms` | "A reminder needs exactly one due time, either delaySeconds or localDueAt, so nothing was set." |
| `bad_time` | "The due time could not be read, so nothing was set. Give delaySeconds as a whole number of seconds, or localDueAt as a local date and time in the form YYYY-MM-DDThh:mm:ss." |
| `past` | "That time has already passed, so nothing was set." |
| `no_reminder` | "This session has no pending reminder with that ref; it may have fired or been cancelled already. Nothing was cancelled." |
| `reused_key` | "This call reused the key of a different earlier call, so nothing was done." |

The success messages are `MESSAGESET` "The reminder is set." (8.3), `MESSAGELISTED` "These are the session's pending reminders, earliest first." and `MESSAGECANCELLED` "The reminder is cancelled."

**Measured in planning** (slot C, build 154, `$SYSTEM.Process.TimeZone("America/New_York")`, `$ZDT($ZDT($ZDTH(x,3,1),-3),3,1)`; the process zone was put back):

| Local time | UTC | Note |
| --- | --- | --- |
| 2026-03-08 01:30 | 06:30 | |
| 02:00 | 07:00 | gap |
| 02:30 | 07:30 | gap, read as 03:30 EDT |
| 03:00 | 07:00 | |
| 2026-11-01 00:30 | 04:30 | |
| 01:00 | 05:00 | overlap, first instant |
| 01:30 | 05:30 | overlap, first instant |
| 02:00 | 07:00 | |
| 2030-10-31 10:00 | 14:00 | |
| 2030-11-07 10:00 | 15:00 | |
| 2026-02-30 | `<ILLEGAL VALUE>` | thrown, so `FromLocal` catches it |

`date` confirms that 2030-11-07 is a Thursday in EST and that US daylight saving ends Sunday 2030-11-03.

**Decided in-stage:**
1. **The Thursday date.** The mock's `localDueAt` is the fixed Thursday `2030-11-07T10:00:00`, the Thursday of a daylight-saving week. The mock can't compute "next Thursday", and a near date (the A scenario uses 2026-10-29) would turn the scenario into a `past` refusal once that date has gone. Throwaways run in UTC, so the daylight-saving property is pinned in-process by `ReminderZone` with the zone set.
2. **Cancel through the chat uses a fixed Ref.** The mock copies tool inputs verbatim and can't take a Ref from an earlier `tool_result` (`mock.mjs:307`). New mock behaviour would need the contended `ci/mock/mock.mjs` and `scenarios.mjs`. So the B cancel scenario names `zzReminderChatCancel01`, as Lane A's `A/reminder-cancel.json` does. The test gives session A's chat-set reminder that Ref through a test subclass behind the ReminderOps item (`NewRef` seam, `UseItemClass`). The list's `tool_result` is asserted to hold exactly that Ref. The scenario is a marker scenario, because it only means something in that test.
3. **The cancel ends the waiter at once** by interrupting its alarm, which is the platform's own mechanism (`SetTimer`'s alarm handle). Nothing is stored and the waiter is unchanged (AD-5). Visual Trace then shows no waiting process for a cancelled reminder, Story 16.4's sign-out ends waiters at once, and tests need no wait for the due time. 8.3's "a non-pending row sends nothing" remains the guarantee if the interrupt fails. Task 0 measures it, with a fallback.
4. **The repeat rule.**
   - Each verb keeps its own keys (`IdempotencyKey` for set, `CancelKey` for cancel).
   - A key reused across verbs is a new command. Its first use acted, and the re-run asked for something else.
   - A key reused within a verb is compared. A relative `DelaySeconds` names no fixed instant, so a set compares `Text` (and the resolved instant for an absolute form).
   - `ListReminders` is read-only and answers the current list, because AD-1's repeat rule exists so that a re-sent turn can't act twice.
   - Both stores are properties of the row. No index is needed: the lookup is per session through `SessionRefIndex`, and `ItemId`s never repeat across sessions.
5. **One `no_reminder` message for every cancel refusal.** The ownership check goes through `Ownership.Reminders` (AD-4), whose `Statement` is contended. One message covers an unknown, foreign, fired or cancelled Ref and never reveals another session's reminder. AC 3 asks only for "a plain-English reason".
6. **Validation order.** Session, then repeat, then text, forms, readability, past. A repeat is answered before the due time is checked, so a repeated `LocalDueAt` gets its first result even after that time has passed.
7. **Answers.** A refusal's `Outcome` is `refused`, as the Lane A double uses. Set stays `set` (8.3; the double says `created`, and `Answer` drops `Outcome`). Cancel answers `DueAt` too, so the model can name the time.
8. **03 is not `@floor`.** 'skip every unbuilt part' needs a skipped, non-`@floor` test for step 3, and in `live:demo-path` the test always runs. Story 11.1 tags the end-to-end floor.
9. **03 cancels its reminder in `afterAll`.** Steps 4 to 6 then see the README session as they did before this story: no reminder fires during 04's assertions, and step 2 is not done. Story 11.1's notBuilt part in 04, "the reminder lands … during the wait", will drop that cancel.
10. **03 matches "stretch" case-insensitively.** The mock sends `stretch` (pinned by `GuidePrompts`), the rail shows text exactly, and capitalising would mean editing the contended `web/src/app/rail/**`.
11. **The chat ACs at IRIS level** go through `Decide` (`RunnerFixture.Run`), as Stories 1.10 and 4.4 do. The full web path is proven by 03 for the guide prompt.
12. **Expected cost** (inference until measured): `live:sign-in` +10 to 15 s (506 s locally against 540 s; run it with `OCUTALON_LIVE_DEADLINE=900`; CI allows 1200 s); `live:demo-path` +30 to 60 s (two runner restarts); `ReminderChat` about 30 to 60 s.

**Ledger inbox:**
- DW-135: addressed by the List rule, `TestListShape`, `TestListToolReadsTheList` and AC 3.
- Declined DW-140: settling it needs a live Haiku 5.5 run, which uses the release-candidate key (owner-only: keys and money). The fix would amend AD-20's `MaxIterations`, Lane A's `Agent/Chat.cls:18` (AD-29; veto). This story's cancel scenario uses 3 model requests, within 4. Recommend routing it to Lane A's release-candidate live check.
- DW-141: addressed by the repeat rule (Decided 4), `TestSetRepeat`, `TestCancelIsolationAndRepeats` and the `reused_key` matrix row.
- Declined DW-142: the fix is in Lane A's `Agent/Chat.cls:36` INSTRUCTIONS (AD-29; Epic 8 keeps Lane B's files), and its check needs a live Haiku 5.5 run. Flagged for the orchestrator as a risk to UJ-1's live step 2, to route to a Lane A story before the online demo.
- DW-210: addressed by the `playwrightEnv()` task, 03's describe-level skip and AC 4.
- DW-232: addressed by reusing `guide-reminder.json` unchanged. The new B files are marker scenarios with names that aren't used anywhere else.

**U-107 and DW-291 (Story 16.4).** This story delivers the real cancel path with its own tests and touches nothing of Epic 16. The sign-out can cancel through it as it stands: `SessionOps.End` reads `Ownership.Reminders(SessionRef)` and sends one `CancelReminder` per Ref, each with a key of its own. Each ends its waiter at once. No cancel-by-session entry point is needed, so DW-291 covers it.

**Integration ACs:**
- Story 1.10's list tool (`CommandCall.Listed`) reads `ReminderOps`' `Data` and gives the model the reminders in due order (`TestListShape`, `TestListToolReadsTheList`).
- The set and cancel tools pass `Message` and `Ref`/`DueAt` through `Answer`.
- The page's rail removes a cancelled row (`reminder.spec.ts`).
- The guide marks step 2 done (03).
- Chat confirms (`ReminderChat`).

**Consumes:**
- `Commands.Submit`/`CommandsIn` (2.3); `Ownership.Reminders` (2.x); `Live.Publish`/`Payload.Reminder` (0.5, 8.3); `Data.Time` (0.4); `Schedule.Reminder`, `ReminderTimer`, `ReminderStart` (8.3); `Bridge.Ids`.
- Tests: the tools and `CommandCall` (1.10), Chat and the mock (1.x, 0.11), `B/guide-reminder.json` and guide step 2 (4.4), `RunnerFixture`, `Test.Contract.Mock`, `ZoneCase`, and the e2e support helpers.

**Consumed-by:**
- Story 8.5: `Reconcile` re-arms pending rows only, and leaves a cancelled row and the key properties alone.
- Story 16.4: the sign-out cancels, as described above.
- Story 11.1: UJ-1 end to end (03's clean-up cancel, Decided 9).

**Extend, don't copy:**
- `Resolve` extends 8.3's `Accepts`. List reuses `Ownership.Reminders`. Cancel uses `Wake`'s lock pattern.
- `EndWaiter` and `StartWaiter` share one session helper.
- `ReminderFixture.Submit` is extracted from `Set`.
- `FromLocal` mirrors `Bridge.Time.DayStartUtc`'s `-3` conversion. AD-18 keeps a separate converter on each side of the bridge, and the test compares them.
- `ReminderChat` copies `GuidePrompts.Turn` (about 15 lines) and the step part of `Test.Tools.Reminders.AssertSteps` (about 20 lines). Both are private methods of other epics' contended test classes.

**Footprint extensions to report:** `web/scripts/demo-path-summary.test.mjs` (no running epic claims it). Approved extensions: `web/e2e/reminder/reminder.spec.ts`. New Epic 8 files are under `ci/mock/scenarios/B/` and `Test/Schedule/`.

**Proposed split** (multiple-goals; for the lead):
- **8.4: the command side.** All IRIS tasks except `ReminderChat`, plus `reminder.spec.ts`'s cancel test. Covers AC 1 and AC 3's command clauses.
- **A sibling, 8.6, "Reminders through the chat on the demo path".** The two B scenarios, `ReminderChat`, 03 turned on, DW-210 and DW-232. Covers AC 2, AC 3's chat clause and AC 4.

The plan above stays whole if the lead keeps one story.

## Verification

**Shared values.** Every `ci/iris.sh` and `ci/warm.sh` call starts with `OCUTALON_LOCK_DIR=<the lane-c lock folder named in the dispatch> OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=8 stage=<stage>'`, written out in full on each call. Each call is its own tool call, in the foreground, with `timeout: 600000`. Tags: fresh `e8s4i` and warm `e8s4iw` for implement; any other stage uses `e8s4<stage>` and `e8s4<stage>w`. Items that `ReminderOps`, `ReminderTimer` or `Schedule.Reminder` run are picked up on a warm stack only after the item restarts (8.3, Task 0).

**Commands:**
- `(once, first)` `OCUTALON_LOCK_DIR=<the lane-c lock folder named in the dispatch> OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=8 stage=implement' OCUTALON_RUN_TAG=e8s4iw ci/warm.sh up`. Expected: ready.
- `(loop)` `OCUTALON_LOCK_DIR=<the lane-c lock folder named in the dispatch> OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=8 stage=implement' OCUTALON_WARM=1 OCUTALON_RUN_TAG=e8s4iw ci/iris.sh class OcuTalon.Test.Schedule.ReminderLogic`. Expected: `CLASS ... passed`.
- `(loop)` the same command, one per call, for `OcuTalon.Test.Schedule.ReminderZone`, `OcuTalon.Test.Schedule.Reminders`, `OcuTalon.Test.Schedule.ReminderChat`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Install.Production`, `OcuTalon.Test.Demo.GuidePrompts`, `OcuTalon.Test.Core.CommandsInProduction` (after the Q1 ruling) and `OcuTalon.Test.Tools.Reminders`. Expected: each passed.
- `(loop)` `bash docker/tests/test-mock.sh`. Expected: pass, with the scenario loader accepting the two new B files.
- `(loop)` `npm --prefix web run lint`. Expected: exit 0.
- `(once)` the lock prefix with `OCUTALON_LOCK_OWNER='epic=8 stage=implement' OCUTALON_RUN_TAG=e8s4i`, one call each: `ci/iris.sh build`, `ci/iris.sh shard lane-b`, `ci/iris.sh shard lane-b --reverse`, `ci/iris.sh shard lane-a`. Expected: every `CLASS` line passed.
- `(once)` the same prefix, one call each: `ci/iris.sh live demo-path` (record the time); `OCUTALON_LIVE_DEADLINE=900 ci/iris.sh live sign-in` (record the time); `ci/iris.sh live production` (after the Q2 ruling). Expected: each passed, with 03 and both `reminder.spec.ts` tests passing.
- `(once)` `npm --prefix web test`, then `bash ci/checks.sh` (storage blocks included). Expected: pass.
- `(once, last, also after a failure)` the lock prefix with `OCUTALON_RUN_TAG=e8s4iw ci/warm.sh down`, then with `OCUTALON_RUN_TAG=e8s4i ci/iris.sh teardown`.

**Mutations (Rule 19).** Record each as `mutation: <change> -> <red test>`.
- **AC 1:**
  - `Resolve` adds 0 instead of `DelaySeconds` -> `ReminderLogic.TestResolve` and `Reminders.TestSetByDelayAndLocal`.
  - `FromLocal` uses a fixed offset -> `ReminderZone.TestFromLocal`.
  - `Resolve` accepts two forms -> `TestResolve` and `TestRefusalsWriteNothing`.
  - `Set` saves before it resolves -> `TestRefusalsWriteNothing`.
- **AC 2:**
  - `ReminderOps` answers not-implemented for `DelaySeconds` -> `ReminderChat.TestGuidePromptSetsReminder`, and 03 in `live:demo-path` (the rail row).
  - The created event is dropped -> 03 (no row).
- **AC 3:**
  - `Cancel` skips the ownership check -> `Reminders.TestCancelIsolationAndRepeats`.
  - `Cancel` doesn't interrupt the alarm -> `TestCancelEndsWaiter`.
  - `Cancel` doesn't publish -> `TestCancelEndsWaiter` and `reminder.spec.ts` test 2.
  - `List` includes non-pending rows -> `TestListShape` and `ReminderChat.TestCancelThroughChat`.
  - `Set` ignores the key -> `TestSetRepeatOneWaiter`.
  - `Cancel` ignores `CancelKey` -> `TestCancelIsolationAndRepeats`.
  - A reused key with other text is accepted -> `ReminderLogic.TestSetRepeat`.
- **AC 4:** 03's skip moved into the test body -> 'skip every unbuilt part' in `demo-path-summary.test.mjs`. Undo the `playwrightEnv()` fix and run the same mutation again: it must then be green where Chromium is installed (DW-210's evidence).

**Shared surfaces:**
- the ReminderOps oracle row (`Test.Install.Production.TestStubsAnswer`; `test-production.sh` rows 16 and 17);
- `CommandsInProduction`'s stub-owner table;
- the `Data.Reminder` contract (`Test.Data.Tables`);
- the mock's scenario set (no count test; names unique across A and B; `guide-reminder.json` pinned by `GuidePrompts` and `guide-view.test.mjs`);
- the demo-path step summary (step 3 now runs on a stack and skips without one);
- the README session's reminders in `live:demo-path` (01 runs first and asserts none; 03 cancels its own);
- the rail user's reminders and cards in `live:sign-in` (each test removes its own);
- the runners' keys (`pointKeys`/`restoreKeys` in 03 and `ReminderChat`);
- the ReminderOps item's class (`ReminderChat` swaps it and puts it back);
- the throwaways' `ReminderTimer` instances and alarms (each ended by a cancel);
- the run times of `live:sign-in` and `live:demo-path`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: draft
Blocking condition: none (re-plan as the command side after the rulings)
