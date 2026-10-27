---
title: 'Story 8.4: Set, list and cancel reminders in plain words'
type: 'feature'
created: '2026-10-27'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
warnings: [oversized]
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
- **Several cancels from one tool call (U-118, the owner's delegate).** Lane A will make the `cancel_reminder` tool take one or more reminder ids and submit one `CancelReminder` per id inside a single tool call, each with its own `IdempotencyKey` (Story 11.1). `ReminderOps` must accept several `CancelReminder` commands that arrive back to back from one tool call, each with a distinct `IdempotencyKey`, with no collision in the repeat rule (`IdempotencyKey`/`CancelKey`): each cancels its own reminder and a repeat of any one returns that one's first result. A test proves it. If the design cannot allow it, HALT with an intent gap. Epic 8 changes neither the tool (Lane A's, `OcuTalon.Tools`) nor the `CancelReminder` message (an Epic 0 cross-lane contract).
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

Product, Epic 8's footprint (paths under `src/ocutalon/cls/OcuTalon/` unless written in full):
- `Schedule/ReminderOps.cls` (8.3):
  - `STUB` `:20` goes. `OnMessage` `:31-45`: its `Accepts`/`SessionExists` gate becomes the verb dispatch.
  - `Set` `:48-79` keeps the row save, `StartWaiter`, the release of its own row before the reopen (`:62`; 8.3 found that a row still open in the process reopens stale), the created publish and the answer.
  - `StartWaiter` `:84-102`: its save and restore of `..%SessionId`/`..%SuperSession` becomes the shared helper.
  - `SessionExists` `:105`, `Result` `:112`, `MESSAGESET` `:29`.
- `Schedule/Reminder.cls`:
  - `Accepts` `:28-39` is replaced by `Resolve`. Only `ReminderOps:35` and `ReminderLogic` call it.
  - `Wake` `:98-135` already ends without sending for a non-pending row (`:109`, before the early-wake rule), so an interrupted wake of a cancelled row ends the waiter. Its open is the lock pattern for `Cancel`: `RefIndexOpen(ref, 4, .sc)` and the `$$$LockFailedToAcquireExclusive` check at `:103`. `Start`/`Wake` don't change. Class doc `:3-15`.
- `Data/Time.cls`: `Seconds` `:27`, `AddSeconds` `:42` (`""` beyond 9999-12-31), `ToLocal` `:54`, `Zone` `:84`. It has no local-to-UTC method. Its twin `src/bridge/cls/OcuTalon/Bridge/Time.cls:40` `DayStartUtc` uses `$ZDateTime(days_",0", -3)` (read only).
- `Data/Reminder.cls`: 8 properties, storage slots 1-9, `RefIndex` unique, `SessionRefIndex`.

Read only (call, never edit):
- `Data/Ownership.cls:219` `Reminders(sessionRef, .sc)`: the session's pending rows, opened, `ORDER BY DueAt, ID` (`:581`). Contended.
  - Drop that list before `RefIndexOpen(ref, 4)`. An object still open in the process comes back as it is, without the lock (8.3).
- Messages:
  - `Msg/Command/SetReminder.cls`: `Text`(1000), `DueAt`(20), `DelaySeconds` `%Integer`, `LocalDueAt`(19).
  - `CancelReminder.ReminderRef`(22); `Msg/Command.cls` `IdempotencyKey`(128).
  - `Msg/CommandResult.cls`: `Ok`, `Message`, `Outcome`, `Ref`, `DueAt`, and `Data`, a JSON string.
- `Core/CommandsIn.cls`:
  - routes the three verbs to ReminderOps from every origin (`:166-168`);
  - code 5003 is `not_built`, and any other error is `failed` (`MESSAGEFAILED` `:50`).
- `Production.cls:68`: ReminderOps `PoolSize="1"`, so its commands are handled one at a time.
- Lane A consumers:
  - `Tools/CommandCall.cls` `Run` `:32-59` sets `SessionRef` = the context's `OwnerRef` and `IdempotencyKey` = `<ItemId>:<CommandCount+1>`, and writes the count back. So several commands of one tool call get distinct keys. A call that runs again repeats them, because `Bridge.Context.Begin` resets the count (`src/bridge/cls/OcuTalon/Bridge/Context.cls:59-73`).
  - `CommandCall.Answer` `:63` gives the model `ok`, the message unchanged, `ref`, `due` and `dueLocal`.
  - `CommandCall.Listed` `:82-115` needs a `reminders` array whose items have string `ref`, `text` and `dueAt` (UTC to the second); otherwise it answers `NOTREAD`.
  - `Tools/ReminderTools.cls:49-90`:
    - set sends only `Text`/`DelaySeconds`/`LocalDueAt`, and refuses a non-digit delay itself;
    - list and cancel (by `reminderRef`) need nothing more;
    - each returns its dynamic object through `Tools.Result.Return`.
  - `Agent/Chat.cls` (DW-140, DW-142) is never edited.
- Platform (reference only):
  - `irislib/Ens/BusinessProcess.cls:189` `SetTimer`: the alarm handle is the `Ens.AlarmRequest` body id.
  - `irislib/Ens/Alarm.cls:21-52`: an `Ens.AlarmTriggerRequest` header is handled by `InterruptAlarm` (`:358-380`), which marks a known handle interrupted and ignores an unknown one. The trigger header ends Completed.
  - `irislib/Ens/AlarmTriggerRequest.cls` (`AlarmHandle`).
  - `irislib/Ens/BusinessOperation.cls:726`: a business operation's `SendRequestAsync(target, request, description)` has no response flag, because an operation never gets an answer. Never pass `0` as its third argument: that would be the description. The method reads `..%RequestHeader.Resent`, so a shadow instance with no request header can't make the real send. The tests stand in for it (`ReminderOpsSendProbe`).

Tests, Epic 8's (`Test/Schedule/`):
- `ReminderLogic.cls`:
  - header `:1-23`; `Command` `:43`; `EventStates` `:216`; `Rows` `:483`;
  - `TestAccepts` `:54-95` and `TestNotHandledWritesNothing` `:137-167` pin the old answers;
  - the lock jobs `HoldLock` `:387` and `TryLock` `:401`.
- `ReminderFixture.cls`: `Set` `:14-45` (bridge context, origin tool, key `zzrem<n>`) and `Remove` `:54-84`.
- `Reminders.cls` (base `Test.Core.InProduction`): `OnAfterOneTest` `:34`, `SetReminder` `:47`, `Timers` `:55`, `IsWaiting` `:66`, `WaitEnded` `:75`.
- `ReminderOpsProbe.cls` and `ReminderOpsStartedProbe.cls` name "the handled set" in their docs. `ReminderTimerDouble` stays valid.
- `ReminderOpsSendProbe.cls`: overrides `SendRequestSync` by `Mode` (ok, noanswer, error, throw) and records what it saw in `Seen`. `ReminderLogic.TestStartWaiterSeam` `:448-481` uses it.
- Helpers:
  - `Test/Data/Fixture.cls`: `Session`, `Reminder` `:50`, `SessionHeaders`/`Between`, `Clean`. Contended, call only.
  - `Test/Core/Observe.cls` (`Events`, `LastLog`).
  - `Test/Bridge/ZoneCase.cls`: saves the zone and puts it back per test. Lane A's, extend only.
- `web/e2e/reminder/reminder.spec.ts` (8.3; the rail user; `afterEach` runs `Remove`):
  - from `support/iris`: `irisScript`, `chk`, `quoted`, `fixtureUser`;
  - from `support/floor`: `rowOf`, `unique`;
  - from `sign-in/helpers`: `signIn`.

Shared by entry, and the allowed extensions:
- `Test/Core/ProductionItems.cls:34`: the ReminderOps row, `"stub": 1`. It is read by:
  - `Test/Install/Production.cls:136-171` `TestStubsAnswer`;
  - `test-production.sh` row 16's sweep (`:162-171`).
- `Test/Data/Tables.cls:431-447`: Epic 8's `OcuTalon.Data.Reminder` entry. `AssertContract` checks the exact property and index sets.
- `Test/Core/CommandsInProduction.cls` (Q1): class doc `:4-5`, method doc `:27-29`, table `:35`.
  - `TestTraceAndThread` `:106-155` sends `ListReminders` to ReminderOps but asserts only headers and sessions, so it stays green unedited.
- `docker/tests/test-production.sh` (Q2): the header at `:17-19`, and the expected lines at `:195-196` for a `ListReminders` with no `SessionRef`.

Stay green with no edit:
- `Test/Core/CommandsRouting.cls` (probes);
- `Test/Core/Commands.cls` and `CommandsContext.cls` (they assert the origin only);
- `Test/Tools/Reminders.cls` (the double);
- `Test/Demo/GuidePrompts.cls` (a session-less owner, so nothing is submitted);
- `Test/Demo/Guide.cls:111-124`, `Test/Web/Api.cls` and `Test/Live/Payloads.cls`;
- `Test/Contract/Ac.cls` (listed signatures only).

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0** (implement stage, warm throwaway). Record each result under Design Notes as measured or (inference):
  - (a) For a waiting reminder, ReminderOps sends `Ens.AlarmTriggerRequest(<the Ens.AlarmRequest body id>)` to `Ens.Alarm` through its own `SendRequestAsync`, which never waits for a response. It sends with `..%SessionId` = the row's `TraceHeaderId` and `..%SuperSession` = the session's `TraceRef`.
    - The waiter's `OnResponse` runs at once and the instance completes.
    - Record the trigger header (session, `SuperSession`, status).
    - A trigger whose alarm has already fired adds no event-log error.
  - (b) The status values of a waiting reminder's `Ens.AlarmRequest` header, for the "not completed" filter (8.3 saw 2 or 3).
  - If (a) fails, drop the interrupt:
    - the cancelled waiter ends at its due time, sending nothing (8.3);
    - the production tests use dues of at most 15 s and wait for them;
    - record it, and report it in the Auto Run Result for the lead, because the intent's "at once" is then not met.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Time.cls` -- add `FromLocal(local As %String) As %String` per the Always list -- the only local-to-UTC converter (AD-18).
  - It takes exactly `YYYY-MM-DDThh:mm:ss` and converts with `$ZDateTime(<local $H>, -3)` in the process zone.
  - It returns `""` for an unreadable value (a thrown `<ILLEGAL VALUE>` included) and for a result outside `Seconds`' range.
  - Its doc states the measured gap behaviour (read one hour later) and overlap behaviour (the first instant).
- [ ] `src/ocutalon/cls/OcuTalon/Data/Reminder.cls` -- AD-1's repeat rule on the row (Q3):
  - append `IdempotencyKey As %String(MAXLEN = 128)` (the key of the `SetReminder` that created the row) and `CancelKey As %String(MAXLEN = 128)` (the key of the `CancelReminder` that cancelled it);
  - no index;
  - commit the compiler's storage block (slots 10 and 11 appended).
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/Reminder.cls` -- replace `Accepts` with `Resolve(command, now, Output dueAt) As %String`, and correct the class doc -- one pure due-form rule.
  - It is the Always rule: `""` with `dueAt` set, or one of `no_text`, `due_forms`, `bad_time` and `past`, checked in that order.
  - A `DelaySeconds` must match an optionally signed whole number.
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls` -- the built owner of the three verbs:
  - Delete `STUB`. Add one `MESSAGE*` parameter per refusal code (the Design Notes table, word for word), plus `MESSAGELISTED` and `MESSAGECANCELLED`.
  - `OnMessage`:
    - takes `now` = `NowUtc()` once;
    - sends, by exact class name, `SetReminder` to `Set`, `ListReminders` to `List` and `CancelReminder` to `Cancel`, inside the one Try/Catch (a throw is logged and answered `failed`);
    - for any other message, logs one error naming its class and returns an error status that is not 5003, with no answer.
  - Each verb checks the session first (`no_session`). Set and cancel with a non-empty key then apply the repeat rule. Each verb then applies its own rule (Always).
  - `Set` resolves before it writes anything, and stores `IdempotencyKey` on the row. The rest is 8.3's.
  - `List` reads `Ownership.Reminders`.
    - It builds each item with `%Set(<key>, <value>, "string")` for `ref`, `text` and `dueAt`, so a text of digits stays a JSON string.
    - An Ownership error is answered `failed`.
  - `Cancel` follows the Always steps 1-5. A lock it can't take within the process lock timeout logs a warning and answers `failed`, and changes nothing (Decided 7).
  - The repeat lookups use one fixed statement per key, `WHERE SessionRef = ? AND IdempotencyKey = ?` (or `CancelKey = ?`), bound to the command's `SessionRef` (Decided 3).
  - Add private `Refuse(code)` and `EndWaiter(row)`, and one private helper that sets `..%SessionId`/`..%SuperSession` for a send and puts both back on every path. `StartWaiter` and `EndWaiter` both use it.
  - `EndWaiter` sends each trigger with `..SendRequestAsync("Ens.Alarm", trigger)`, which takes no response flag (Code Map).
  - The class doc says what is built, with no history.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls` -- set the ReminderOps row to `"stub": 0` (Epic 8's row) -- the oracle follows the deleted `STUB`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` -- in Epic 8's `OcuTalon.Data.Reminder` entry only, add `"IdempotencyKey": "%String(MAXLEN=128)"` and `"CancelKey": "%String(MAXLEN=128)"` after `"TraceHeaderId"`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls` (Q1, allowed) -- nothing else; `TestTraceAndThread` stays unedited:
  - remove only `"SetReminder|ReminderOps|web_user", ` from the table (`:35`);
  - in the class doc (`:4-5`), drop `ReminderOps, ` and the count word: "to the four stub owners (ReminderOps, WatchOps, SessionOps and IncidentManager)" becomes "to the stub owners (WatchOps, SessionOps and IncidentManager)". Removal only, so Epic 5's edit of the same line stays a plain union;
  - in the method doc (`:27-29`), drop "ReminderOps (SetReminder), ".
- [ ] `docker/tests/test-production.sh` (Q2, allowed) -- nothing else:
  - `:195-196` become `CHK|submit-user|1|0|refused|web_user` and `CHK|submit-tool|1|0|refused|tool`;
  - in the header (`:18`), "ReminderOps' plain-English not_built result" becomes "ReminderOps' plain-English refusal (the command names no session)".
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderFixture.cls` -- update the class doc, and add:
  - `Begin(sessionRef, itemId = "") As %Status`: the bridge context of the session as a chat tool call has it: `OwnerRef`, `ItemId` (by default a fresh `zzitem<n>`) and `SuperSession` = `TraceRef`. It is extracted from `Set`.
  - `Submit(sessionRef, command) As OcuTalon.Msg.CommandResult`: `Begin`, `Commands.Submit`, then End. `Set` uses it.
  - `Cancel(sessionRef, ref, key = "") As %DynamicObject`: a `CancelReminder` through `Submit` (the key defaults to `zzcan<n>`). It returns `{ok, outcome, message, ref, dueAt}`.
  - In `Remove(ref)`: a pending row is first cancelled through `Cancel`, and `Remove` waits at most 10 s until no `ReminderTimer` with that Ref is waiting. Then it deletes as before.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderOpsProbe.cls` and `ReminderOpsStartedProbe.cls` -- correct "the handled set" in their docs (contract only).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderOpsSendProbe.cls` -- extend it, and update its doc:
  - add a stand-in `SendRequestAsync(pTargetDispatchName, pRequest, pDescription = "")`, with the signature of `Ens.BusinessOperation`'s;
  - it pushes `{target, handle, sessionId, superSession}` onto a new `SeenAsync` array (`handle` is the request's `AlarmHandle`);
  - it then does what `Mode` says: ok and noanswer answer OK, error answers an error status, throw throws. Nothing is sent.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderLogic.cls` (no production; shadow instances of `OcuTalon.Schedule.ReminderOps` or its probes) -- also update the header:
  - `TestResolve` replaces `TestAccepts`. It checks every due-form, refusal and order case by code:
    - `DelaySeconds` 60, "+60", 0, -5, "1.5", "abc", and one beyond 9999;
    - `LocalDueAt` unreadable and past; `DueAt` unreadable, now and past;
    - 0, 2 and 3 forms;
    - the order: blank text first, then the forms, then readability, then past.
  - `TestRefusalsWriteNothing` replaces `TestNotHandledWritesNothing`.
    - Each refusal of each verb gives status OK, `0|refused` and the exact Message, with no row and no event. That covers `no_session` for an empty and an unknown session on all three verbs, and the set refusals.
    - A message that isn't a verb gives an error status that is not 5003, no answer, and one logged error (removed after the check).
  - `TestListShape` (AC 2) uses fixture rows of the session: pending due later, pending due earlier with the text `100`, fired and cancelled. Another session has a pending row.
    - The answer is `1|listed` with `MESSAGELISTED`.
    - `Data` is exactly `{"reminders":[<earlier>,<later>]}`, with only `ref`, `text` and `dueAt`, all strings.
    - **Integration AC (DW-135):** `Tools.CommandCall.Listed` of that answer is `ok` true with the two refs in due order, not `NOTREAD`.
    - An empty session gives `{"reminders":[]}`, and `Listed` gives an empty list.
  - `TestCancelFixtureRow` (AC 3): a pending fixture row with no waiter is cancelled with `CancelKey`, one cancelled event and no trigger header. The same key again gives the first result and no second event. A new key gives `no_reminder`.
  - `TestCancelRacesFire` (AC 3): a `HoldLock` job holds the row's lock and marks the row fired before it lets go. The cancel waits, then answers `no_reminder`. The row is fired, with no `CancelKey` and no cancelled event.
  - `TestCancelBusyRowFails`: a `HoldLock` job holds the lock past the process lock timeout. The cancel answers `0|failed`, the row stays pending, there is no event and one warning. Then the job is let go.
  - `TestSetRepeat` (AC 4, on `ReminderOpsStartedProbe`):
    - the same key twice gives one row and identical answers;
    - the same key with other text, or with an absolute form naming another instant, gives `reused_key` and no second row;
    - a row whose `DueAt` has passed, repeated with its key, text and `DueAt`, gives its first result, not `past` (Decided 5);
    - an empty key twice gives two rows.
  - `HoldLock(ref, seconds, state = "")` extends 8.3's job: when `state` is given, the job saves the row with that state before it lets go.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderZone.cls` (new; extends `OcuTalon.Test.Bridge.ZoneCase`; no production):
  - `TestFromLocal`:
    - in America/New_York, the "Measured in planning" rows: the two Thursdays, the gap `2026-03-08T02:30:00` gives `07:30:00Z`, and the overlap `2026-11-01T01:30:00` gives `05:30:00Z`;
    - `ToLocal(FromLocal(x))` = x for both Thursdays;
    - `""` for `2026-02-30T10:00:00`, `next Thursday`, a value with a space, a value without seconds, a value with a `Z`, and `9999-12-31T23:00:00`;
    - in Asia/Kolkata, `2030-11-07T10:00:00` gives `04:30:00Z`;
    - with no zone, `ToLocal(FromLocal(x))` = x;
    - in New York, `FromLocal(day_"T00:00:00")` = `Bridge.Time.DayStartUtc(day)` for 2030-11-01 to 2030-11-09 (AD-18's comparison).
  - `TestResolveThursdayAt10`: `Resolve` with a `LocalDueAt` in New York gives `2030-11-07T15:00:00Z`, and a week earlier `2030-10-31T14:00:00Z`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/Reminders.cls` (production, throwaways). Each test registers every Ref it makes for `OnAfterOneTest`; also update the header. Add:
  - `TestSetByDelayAndLocal` (AC 1), under `ReminderFixture.Begin`:
    - `Tools.ReminderTools.SetReminder(text, 30)` answers `ok` true with a ref, and the row's `DueAt` lies in `[AddSeconds(before, 30), AddSeconds(after, 30)]`;
    - `SetReminder(text2, "", ToLocal(AddSeconds(before, 40)))` gives the `DueAt` = `FromLocal` of that local time;
    - each row is pending, with one waiting waiter and one created event;
    - `SetReminder("", 30)` answers `ok` false with `no_text`'s Message unchanged, and makes no row.
  - `TestListToolReadsTheList` (AC 2, Integration AC, DW-135):
    - session A has two reminders (set due in 300 s, then in 200 s), a fired fixture row and a cancelled one; session B has one reminder;
    - `Tools.ReminderTools.ListReminders()` under A's context answers `ok` true with exactly A's two refs, the 200-s one first.
  - `TestCancelEndsWaiter` (AC 3), with a reminder due in 120 s:
    - `Tools.ReminderTools.CancelReminder(ref)` under the context answers `ok` true with `MESSAGECANCELLED`, the ref and the due time;
    - the row is cancelled with the call's key;
    - within 10 s no `ReminderTimer` with that Ref is waiting, and there is no `ReminderTimer`-to-`Notify` header;
    - the `reminder` events are created, then cancelled, and `StateBody`'s rail has no row for it;
    - the waiter's session holds one `Ens.AlarmTriggerRequest` header from ReminderOps to `Ens.Alarm`, with `SuperSession` = `TraceRef` and the alarm request's body id as its handle;
    - ReminderOps' answer header to `CommandsIn` is in the command's session.
  - `TestCancelInterruptFails` (matrix row Cancel, its error case), with a reminder due in 5 s. A shadow instance of `ReminderOpsSendProbe` with `Mode` error gets that session's `CancelReminder` through `OnMessage`:
    - the answer is `1|cancelled`, and the row is cancelled with one cancelled event;
    - one warning is logged that names the Ref;
    - `SeenAsync` holds one send to `Ens.Alarm`, whose handle is the alarm request's body id, sent with session id = the row's `TraceHeaderId` and `SuperSession` = `TraceRef`;
    - the probe's own session id and `SuperSession` are as they were before;
    - the waiter ends after its due time (within `FIRESECONDS`) with no `Notify` header.
  - `TestCancelIsolationAndRepeats` (AC 3, AC 4), with sessions A and B:
    - B cancelling A's Ref through the tool answers `ok` false with `no_reminder`'s Message. A's row is pending, its waiter is waiting, and there is no new event. An unknown Ref gets the same answer.
    - A cancels with key K: cancelled.
    - K again gives the first result, with still one cancelled event and one trigger header.
    - A new key gives `no_reminder`, and so does a fired fixture row.
    - K naming A's second pending reminder gives `reused_key`, and that reminder stays pending.
  - `TestSetRepeatOneWaiter` (AC 4):
    - a `SetReminder` (`DelaySeconds` 300) with key K, submitted twice, gives identical answers, one row, one ReminderOps-to-ReminderTimer start header and one created event;
    - K with other text gives `reused_key`, and there is still one row.
  - `TestSeveralCancelsFromOneToolCall` (AC 4, U-118). Session A has three reminders (due in 300, 310 and 320 s), and B has one.
    - Under one `ReminderFixture.Begin(A, item)`, three `Tools.CommandCall.Run` calls submit one `CancelReminder` each, back to back.
    - Each answers `1|cancelled` with its own Ref and DueAt. The rows carry `CancelKey` `<item>:1`, `:2` and `:3`.
    - There are three cancelled events, one per Ref. Each waiter ends within 10 s with no `Notify` header. B's row is pending and its waiter waiting.
    - The same call run again (`Begin` with the same item, the same Refs in the same order) answers each command its own first result, with no new event or trigger header.
    - Run again with the first two Refs swapped, the first command answers `reused_key` and nothing changes.
- [ ] `web/e2e/reminder/reminder.spec.ts` -- add test 2, "a cancelled reminder leaves the rail within one live update" (AC 3, NFR-9; Rule 3's real-runtime test), and update the header:
  1. `ReminderFixture.Set` sets a reminder due in 300 s for the rail user's session.
  2. After `signIn`, the row shows within `ROW_MS`.
  3. `ReminderFixture.Cancel` through `irisScript` answers `1|cancelled`.
  4. The row is gone within `ROW_MS` without a reload, and no notice card holds its text.
  5. `afterEach` removes the reminder.

**Acceptance Criteria:**
1. **Due forms and refusals.**
   - Given the running production and a session, when the set tool (`Tools.ReminderTools.SetReminder`) sends `DelaySeconds` 30 or a `LocalDueAt` under a bridge context of the session, then:
     - each answer is `ok` true with the reminder's ref;
     - the row's `DueAt` is the command's arrival plus 30 s, or `Data.Time.FromLocal` of the local time in the instance zone (in New York, `2030-11-07T10:00:00` is `15:00:00Z` and the week before `14:00:00Z`);
     - each gives one pending row and one waiting waiter.
   - Given the same production and session, when a set command has a blank Text, a due time that is past or can't be read, or not exactly one due form, then:
     - the answer is `ok` false with the code's Message word for word, which `CommandCall.Answer` passes on unchanged;
     - no row, waiter or event is created. (FR-34, NFR-24, AD-1, AD-18)
2. **List (DW-135).** Given a session with two pending reminders due at different times, one fired and one cancelled, and another session with a pending reminder, when the list tool sends `ListReminders`, then:
   - ReminderOps answers `Ok` 1, `listed`, with `Data` = `{"reminders":[{"ref","text","dueAt"}]}` holding only the session's two pending reminders, earliest first, with `dueAt` in UTC;
   - the tool gives the model both refs in that order, never `NOTREAD`;
   - a session with none gets `{"reminders":[]}`. (FR-34, AD-4)
3. **Cancel.**
   - Given a pending reminder with a live waiter in each of two sessions, when the cancel tool sends a `CancelReminder` with one session's `ReminderRef`, then:
     - the row is cancelled with the command's key, and its waiter ends at once without any notification;
     - one `reminder` event (cancelled) removes the row from the rail user's page within one live update;
     - the answer confirms, with the Ref and the due time;
     - the other session's reminder and waiter are untouched.
   - Given a session, when a `CancelReminder` names another session's reminder, an unknown Ref, or the session's reminder that has already fired or been cancelled (also one that fires while the cancel waits for its lock), then it is refused `no_reminder` with one plain-English Message and nothing changes. (FR-34, NFR-9, AD-1, AD-4, AD-5, AD-26, UX-DR54)
4. **Repeats, and several cancels from one tool call (AD-1, AD-8, DW-141, U-118).**
   - Given a session's earlier `SetReminder` or `CancelReminder` with an `IdempotencyKey`, when a command of the same verb arrives with that key:
     - with the same fields, then it answers the first result, with no second row, waiter, event or trigger;
     - with other fields, then it is refused `reused_key` and nothing changes.
   - Given three pending reminders of one session, when one tool call submits three `CancelReminder`s back to back through `CommandCall.Run` (keys `<ItemId>:1` to `:3`), then all three are cancelled, each with its own key and its own answer.
   - Given those three cancels, when the same call runs again (the same `ItemId`), then:
     - with the same Refs in the same order, each command answers its own first result and nothing changes;
     - with the Refs in another order, a key that names another Ref is refused `reused_key` and nothing changes.

## Spec Change Log

- 2026-10-27 (lead, after the plan's intent-gap HALT): the orchestrator allowed Q1, Q2 and Q4 and routed DW-140/DW-142 (U-118); the lead split the story (8.4 command side, 8.6 chat side) and ruled Q3 decide. Recorded under Intent and Design Notes; Clarification Needed removed; status set to `draft` to re-plan this story as the command side.

## Review Triage Log

## Design Notes

**Lead ruling at the spec gate (2026-10-27, veto U-119):** Decided 3 stands. The two repeat lookups (`IdempotencyKey`, `CancelKey`) are ReminderOps' own session-scoped reads of its own table, bound to the command's server-side `SessionRef`; every read of a target the caller names (the list, the cancel's target check) goes through `Ownership.Reminders` (AD-4). The reviewer checks AD-4 against this ruling. Reversal, if the owner reverses U-119: a key-lookup kind in `Ownership.Rows` in a follow-up story, with the two lookups routed through it.

**Rulings in force (recorded by the lead, 2026-10-27):**
- **Split (lead, decide, U5):** 8.4 is the command side; 8.6 takes the chat side (see Intent). The whole earlier plan is kept in git at 467dfae for reference.
- **Q1, ALLOWED (orchestrator, decide):** `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls` stub rows are shared by entry (since Epic 5's ruling). Remove ONLY the `SetReminder|ReminderOps|web_user` entry from `TestStubOwnersAnswerPlainEnglish`'s table, and ReminderOps from the stub-owner sentences of the class doc (L4-5) and the method doc (L27-29). `TestTraceAndThread` routes `ListReminders` to ReminderOps: if one of its assertions depends on the stub's answer, change only that assertion. Prove the built ReminderOps in Epic 8's own tests (`Test/Schedule/**`), not in that table. Expect a same-line conflict at integrate-forward with Epic 5 (it removes WatchOps and IncidentManager from the same sentences and table line): a plain union, every built owner removed. Reported as a footprint extension.
- **Q2, ALLOWED (orchestrator, decide):** `docker/tests/test-production.sh` row 17: change only the two expected lines (`submit-user`, `submit-tool`) from `not_built` to `refused`, and the matching header phrase ("ReminderOps' plain-English refusal (the command names no session)"). Nothing else. Reported as a footprint extension.
- **Q3 (lead, decide):** `Data.Reminder` gains `IdempotencyKey` and `CancelKey` (`%String(MAXLEN=128)`, no index), append-only (AD-5), for AD-1's repeat rule; Epic 8's own `OcuTalon.Data.Reminder` entry of `Test/Data/Tables.cls` XData `Contracts` gets the two matching lines (that XData is shared by entry).
- **Q4 (orchestrator, decide):** belongs to Story 8.6 (the `docker/tests/test-demo-path.sh` header comment, only once 8.6 turns spec 03 on). Not this story.
- **DW-140 and DW-142 (U-118, kept by the owner's delegate):** declined here; the lead re-owns both to Story 11.1 at the spec gate, with the delegate's conditions in the notes. DW-140's fix is Lane A's multi-id `cancel_reminder` (no AD-20 change); 8.4's share is the several-cancels test above. Never edit `Agent/Chat.cls` or `OcuTalon.Tools` (Lane A's, AD-29, AD-33).
- **DW-210 and DW-232:** re-owned to Story 8.6 with the split; not this story's.
- **Story 16.4 (U-107 kept; DW-291 under 16.4):** 8.4 delivers the real cancel path; 16.4's sign-out test uses it (or a recording double turned on by whichever of 8.4/16.4 merges second). 8.4 touches nothing of Epic 16. The sign-out cancels with one `CancelReminder` per pending Ref; no cancel-by-session entry point is needed.
- **No local absolute paths** in this spec or any committed file (CI's `test-boundaries.sh`). Write the lane-C lock folder as `"$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c"` (it resolves from the worktree) or as the dispatch placeholder.

**Governing ADs:**
- AD-1: the command path; origin `tool` under a context; the owner ignores a repeat; the key is the turn's `ItemId` plus the call's position.
- AD-4: the list and the cancel's target check go only through `Ownership`; another session's reminder is never revealed. The repeat lookups are covered by Decided 3.
- AD-5: the row is the truth; the frozen waiter is unchanged; storage is append-only.
- AD-8: a re-sent turn never acts twice.
- AD-12 and AD-33: events go out after the commit. ReminderOps publishes created and cancelled; the waiter publishes fired. ReminderOps is the `Reminder` table's one owner.
- AD-18: `Data.Time` is the only converter; the instance zone is the container's `TZ`; a test compares `Data.Time` with `Bridge.Time` across a daylight-saving change.
- AD-22: `lane-b`; throwaways only.
- AD-26: the trigger goes in the waiter's own session under `TraceRef`, and ReminderOps' own session is put back.
- AD-29: Lane B's files; Lane A's tools and Chat are read only.
- AD-32: nothing in Schedule renders text.

Conventions: "Times", "Identifiers".

**Refusal codes and messages.** Every refusal has `Outcome` `refused`. The messages are for the model and are never shown as written (8.3, Decided 5).

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

**Measured in planning** (first plan; slot C, build 154, `$SYSTEM.Process.TimeZone("America/New_York")`, `$ZDT($ZDT($ZDTH(x,3,1),-3),3,1)`; the process zone was put back):

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

`date` confirms that 2030-11-07 is a Thursday in EST and that US daylight saving ends on Sunday 2030-11-03.

**Decided in-stage:**
1. **The cancel ends the waiter at once** by interrupting its alarm. That is the platform's own mechanism: `SetTimer`'s alarm handle and `Ens.Alarm.InterruptAlarm`. Nothing is stored and the waiter is unchanged (AD-5). So:
   - Visual Trace shows no waiting process for a cancelled reminder;
   - Story 16.4's sign-out ends waiters at once;
   - tests need not wait for the due time.

   8.3's "a non-pending row sends nothing" stays the guarantee if the interrupt fails. Task 0 measures it, with a fallback.
2. **The repeat rule.**
   - Each verb keeps its own key: `IdempotencyKey` for set, `CancelKey` for cancel. A key reused across verbs is a new command: its first use acted, and the re-run asked for something else.
   - A key reused within a verb is compared. A relative `DelaySeconds` names no fixed instant, so a set compares `Text`, plus the resolved instant for an absolute form.
   - `ListReminders` is read-only and answers the current list. AD-1's repeat rule exists so that a re-sent turn can't act twice.
   - **U-118.** The keys of one tool call's commands are distinct (`CommandCall.Run` numbers them). Each cancel looks up only its own key and writes it only on the row it cancels, so the keys of one call never collide.
     - A second command in the same call that names a Ref already cancelled is refused `no_reminder`. Its repeat gets the same refusal.
     - A re-run that names the Refs in another order meets a key that belongs to another Ref, and is refused `reused_key` (DW-141).
   - The check, then the write, is safe because ReminderOps handles one command at a time (`PoolSize` 1). With a larger pool it would need a lock (inference).
3. **The repeat lookups are ReminderOps' own reads of its own table** (AD-33), one fixed statement each, with the owner check in the statement, bound to the command's `SessionRef`. That is the same shape as `Ownership.Rows` and AD-4's "applies the caller's SessionRef".
   - They return only the command's own earlier result, never a target the caller names. The list and the cancel's target check go through `Ownership.Reminders` (AD-4).
   - A key-lookup kind in `Ownership.cls` would be a contended edit. The intent itself says the set "finds the session's row whose IdempotencyKey is that key".
   - If the lead reads AD-4 as requiring these lookups inside `Ownership.cls`, that is a contended edit for the orchestrator.
4. **One `no_reminder` message for every cancel refusal.** The target check goes through `Ownership.Reminders` (AD-4). One message covers an unknown, foreign, fired or cancelled Ref, and never reveals another session's reminder.
5. **Validation order:** session, then repeat, then text, forms, readability and past. A repeat is answered before the due time is checked, so a repeated absolute set gets its first result even after its time has passed.
6. **Answers.** A refusal's `Outcome` is `refused`, as the Lane A double uses. Set stays `set` (8.3); `Answer` drops `Outcome`. Cancel also answers `DueAt`, so the model can name the time.
7. **A busy row lock.** A cancel that can't take the row's lock within the process lock timeout answers `failed` (`CommandsIn.#MESSAGEFAILED`, "may not have finished"), logs a warning and changes nothing.
   - Only a firing waiter (milliseconds) holds that lock, or a caller that DW-296 already forbids.
   - Refusing `no_reminder` would wrongly say that the reminder isn't pending.
8. **List items are typed strings**, so that a text of digits doesn't make `Listed` answer `NOTREAD`.
9. **The production `LocalDueAt` case uses a local time 40 s ahead** (`ToLocal(AddSeconds(now, 40))`), so its waiter ends quickly, even under Task 0's fallback. Throwaways run in UTC, so `ReminderZone` pins the daylight-saving property in-process with the zone set.
10. **Left to Story 8.6.** The `NewRef()` seam and `ReminderOpsFixedRef`, `ReminderFixture.CancelPending`, the B mock scenarios, `ReminderChat`, spec 03, DW-210 and DW-232. 8.6 adds what it needs to Epic 8's own files.
11. **`TestTraceAndThread` is unedited.** It asserts headers and sessions only, and a built ReminderOps still answers with one response header in the same session.
12. **Expected cost** (inference until measured):
    - `ReminderLogic` about +15 s (the busy-lock test waits out the lock timeout);
    - `Reminders` about +50 to 70 s (`TestCancelInterruptFails` waits for a 5-s due);
    - `live:sign-in` about +10 to 15 s. It was 506 s locally against the 540 s deadline, so run it with `OCUTALON_LIVE_DEADLINE=900`; CI allows 1200 s.

**Ledger inbox:**
- DW-135: addressed by AC 2, the List rule, `TestListShape` and `TestListToolReadsTheList`.
- DW-141: addressed by AC 4 and the repeat rule (Decided 2): a reused key is compared, never answered blindly. Tests: `TestSetRepeat`, `TestCancelIsolationAndRepeats` and `TestSeveralCancelsFromOneToolCall`.
- Declined DW-140: the fix is Lane A's multi-id `cancel_reminder` in `OcuTalon.Tools` and Chat's turn in `Agent/Chat.cls` (AD-29, AD-33; no AD-20 change), which Epic 8 never edits. The lead re-owns it to Story 11.1 at the spec gate. 8.4's share is AC 4's several-cancels clause and `TestSeveralCancelsFromOneToolCall`.
- Declined DW-142: the fix is Lane A's `Agent/Chat.cls` INSTRUCTIONS (AD-29), with a live Haiku 5.5 check. The lead re-owns it to Story 11.1 at the spec gate.

**Story 16.4 (U-107, DW-291).** This story delivers the real cancel path with its own tests and touches nothing of Epic 16.
- The sign-out can cancel through it as it stands: `SessionOps.End` reads `Ownership.Reminders(SessionRef)` and sends one `CancelReminder` per Ref, each with a key of its own. Each one ends its waiter at once. No cancel-by-session entry point is needed.
- A reminder that fires between that read and its cancel answers `no_reminder`, which the sign-out can treat as done.
- 16.4 is in the backlog (it waits on Epic 10), so 8.4 merges first, and 16.4 turns the real path on, as DW-291's condition says. The design matches DW-291; nothing to report.

**Integration ACs:**
- Story 1.10's list tool (`ReminderTools.ListReminders`, `CommandCall.Listed`) reads ReminderOps' `Data` and gives the model the session's reminders in due order (AC 2: `TestListShape`, `TestListToolReadsTheList`).
- The set and cancel tools pass ReminderOps' Message, Ref and due time to the model through `CommandCall.Answer` (AC 1, AC 3: `TestSetByDelayAndLocal`, `TestCancelEndsWaiter`, `TestCancelIsolationAndRepeats`).
- `CommandCall.Run`, which Lane A's multi-id cancel will use, gets one distinct, repeatable answer per command of one call (AC 4: `TestSeveralCancelsFromOneToolCall`).
- The page's rail removes a cancelled row (AC 3: `reminder.spec.ts` test 2).

**Consumes:**
- `Commands.Submit`/`CommandsIn` (2.3); `Ownership.Reminders`; `Live.Publish`/`Payload.Reminder` (0.5, 8.3); `Data.Time` (0.4); `Schedule.Reminder`, `ReminderTimer` and `ReminderStart` (8.3); `Bridge.Ids`; `Ens.Alarm` (the platform).
- Tests only: the reminder tools and `CommandCall` (1.10), `Bridge.Context`, `Bridge.Time`, `Test.Core.InProduction`/`Observe`, `Test.Data.Fixture`, `ZoneCase`, and the e2e support helpers.

**Consumed-by:**
- Story 8.6: reminders set, listed and cancelled through the chat on the demo path, through Story 1.10's tools.
- Story 8.5: `Reconcile` re-arms pending rows only, and leaves a cancelled row and the key properties alone.
- Story 16.4: the sign-out cancels, as described above.
- Story 11.1: Lane A's multi-id `cancel_reminder` (DW-140) relies on AC 4.

**Extend, don't copy:**
- `Resolve` replaces and extends 8.3's `Accepts`. List reuses `Ownership.Reminders`. Cancel uses `Wake`'s lock pattern.
- `EndWaiter` and `StartWaiter` share one session helper.
- `ReminderFixture.Begin`/`Submit` are extracted from `Set`, and `HoldLock` gains an optional state rather than a second lock job.
- `FromLocal` mirrors `Bridge.Time.DayStartUtc`'s `-3` conversion. AD-18 keeps a separate converter on each side of the bridge, and `ReminderZone` compares them.
- The new `Reminders` tests reuse `Timers`, `IsWaiting` and `WaitEnded`.
- `ReminderOpsSendProbe` gains the stand-in async send beside its sync one, instead of a second send probe.

**Footprint extensions to report:**
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls` (Q1) and `docker/tests/test-production.sh` (Q2);
- `Test/Data/Tables.cls` and `Test/Core/ProductionItems.cls` (shared by entry, Epic 8's entries);
- `web/e2e/reminder/reminder.spec.ts` (Epic 8's file since 8.3).

No other contended path is edited.

## Verification

**Shared values.**
- `<L>` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=8 stage=<stage>'`, written out in full on each call.
- Each call is its own tool call, in the foreground, with `timeout: 600000`.
- Tags: fresh `e8s4i` and warm `e8s4iw` for implement. Any other stage uses `e8s4<stage>` and `e8s4<stage>w`.
- A class that a production item runs (`ReminderOps`, `Schedule.Reminder`) is picked up on the warm stack only after the item restarts (8.3).
- On the warm stack, a red that a leftover could explain counts only when the class is green again on the same stack after the revert (Rule 21).

**Commands:**
- `(once, first)` `<L> OCUTALON_RUN_TAG=e8s4iw ci/warm.sh up`. Expected: ready.
- `(loop)` `<L> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e8s4iw ci/iris.sh class OcuTalon.Test.Schedule.ReminderLogic`. Its `WARM reloaded` line loads the changed classes. Expected: `CLASS ... passed`.
- `(loop)` After a warm call has reloaded a change to `ReminderOps` or `Schedule.Reminder`, restart the item on the warm stack. Expected: no error printed.
  ```
  P=$(OCUTALON_RUN_TAG=e8s4iw ci/warm.sh status | sed -n 's/.*project=\([^ ]*\).*/\1/p') && printf '%s\n' 'Do ##class(Ens.Director).EnableConfigItem("ReminderOps",0,1)' 'Do ##class(Ens.Director).EnableConfigItem("ReminderOps",1,1)' 'Halt' | docker exec -i "$(docker ps -q --filter label=com.docker.compose.project=$P --filter label=com.docker.compose.service=iris)" iris session IRIS -U OCUTALON
  ```
- `(loop)` The warm class command above, one per call, for each of these. Expected: each passed.
  - `OcuTalon.Test.Schedule.ReminderZone`;
  - `OcuTalon.Test.Schedule.Reminders` and `OcuTalon.Test.Core.CommandsInProduction`, after the restart;
  - `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Install.Production` and `OcuTalon.Test.Tools.Reminders`;
  - `OcuTalon.Test.Demo.Guide` and `OcuTalon.Test.Demo.GuidePrompts`.
- `(loop)` `npm --prefix web run lint`. Expected: exit 0.
- `(once)` One per call: `<L> OCUTALON_RUN_TAG=e8s4i ci/iris.sh build`, then `shard lane-b`, `shard lane-b --reverse` and `shard lane-a`. Expected: every `CLASS` line passed.
- `(once)` `<L> OCUTALON_RUN_TAG=e8s4i ci/iris.sh live production`. Expected: passed, with row 17's `refused` lines.
- `(once)` `<L> OCUTALON_LIVE_DEADLINE=900 OCUTALON_RUN_TAG=e8s4i ci/iris.sh live sign-in` (record the time). Expected: passed, with both `reminder.spec.ts` tests.
- `(once)` `npm --prefix web test`, then `bash ci/checks.sh` (the storage-block checks included). Expected: pass.
- `(once, last, also after a failure)` `<L> OCUTALON_RUN_TAG=e8s4iw ci/warm.sh down`, then `<L> OCUTALON_RUN_TAG=e8s4i ci/iris.sh teardown`.

**Mutations (Rule 19).** Record each one as `mutation: <change> -> <red test>`.
- **AC 1:**
  - `Resolve` adds 0 instead of `DelaySeconds` -> `ReminderLogic.TestResolve` and `Reminders.TestSetByDelayAndLocal`;
  - `FromLocal` uses a fixed offset of -5 hours -> `ReminderZone.TestFromLocal`;
  - `Resolve` accepts two forms -> `TestResolve` and `TestRefusalsWriteNothing`;
  - `Set` saves before it resolves -> `TestRefusalsWriteNothing`.
- **AC 2:**
  - `List` reads the session's rows of every state -> `ReminderLogic.TestListShape`;
  - `List` sets the items without the `string` type -> `TestListShape` (the text `100`, `NOTREAD`);
  - `List` orders by `CreatedAt` -> `TestListShape` and `Reminders.TestListToolReadsTheList`.
- **AC 3:**
  - `Cancel` skips the `Ownership` check -> `Reminders.TestCancelIsolationAndRepeats`;
  - `Cancel` doesn't check `pending` again under the lock -> `ReminderLogic.TestCancelRacesFire`;
  - `Cancel` doesn't call `EndWaiter` -> `Reminders.TestCancelEndsWaiter`;
  - `EndWaiter` doesn't put `%SessionId` back -> `Reminders.TestCancelInterruptFails` (the probe's session id) and `TestCancelEndsWaiter` (the answer header);
  - `EndWaiter` sends without the waiter's session id -> `TestCancelInterruptFails` (`SeenAsync`) and `TestCancelEndsWaiter` (the trigger header in the waiter's session);
  - a failed interrupt answers `failed` instead of `cancelled` -> `TestCancelInterruptFails`;
  - `Cancel` doesn't publish -> `TestCancelEndsWaiter` and `reminder.spec.ts` test 2.
- **AC 4:**
  - `Set` ignores the key -> `ReminderLogic.TestSetRepeat` and `Reminders.TestSetRepeatOneWaiter`;
  - a reused set key with other text is accepted -> `TestSetRepeat`;
  - `Cancel` ignores `CancelKey` -> `TestCancelIsolationAndRepeats`;
  - the cancel's repeat lookup drops `CancelKey = ?` and takes any cancelled row of the session -> `TestSeveralCancelsFromOneToolCall` (the second and third cancels get the first's result).

**Shared surfaces:**
- the ReminderOps oracle row (`Test.Install.Production.TestStubsAnswer`, and `test-production.sh` row 16's stub sweep);
- `CommandsInProduction`'s stub-owner table (Q1) and `test-production.sh` row 17 (Q2);
- the `Data.Reminder` contract (`Test.Data.Tables`) and its committed storage block (the CI storage checks);
- `Schedule.Reminder`'s methods (`Accepts` goes; only `ReminderLogic` called it);
- the rail user's reminders and cards in `live:sign-in` (each `reminder.spec.ts` test removes its own);
- the throwaways' `ReminderTimer` instances, `Ens.Alarm` requests and trigger headers (each test cancels and removes its own);
- the counters and flags under `^OcuTalonTest("ReminderFixture")` and `^OcuTalonTest("ReminderLogic")`;
- `live:sign-in`'s run time.

The demo-path step summary and the mock's scenarios are unchanged (they are 8.6's).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (bmad-build-auto, re-plan in place, cycle 2; halted after planning).** The command side is re-derived around the preserved intent block. These left the spec for Story 8.6: the B mock scenarios, `ReminderChat`, spec 03, DW-210, DW-232, the `NewRef` seam, `ReminderOpsFixedRef` and `CancelPending`.
- **Kept from the first plan (467dfae):** the `FromLocal` measurements and Task 0's alarm interrupt.
- **Added:** AC 4's several-cancels clause and its test (U-118); the lock race and busy-lock cases; string-typed list items; the item restart on the warm stack.
- **Ledger:** DW-135 and DW-141 addressed; DW-140 and DW-142 declined (Lane A's, for Story 11.1).
- **For the lead to check:** Decided 3 reads AD-4 as allowing ReminderOps' own session-scoped key lookups. If the lead reads it otherwise, that is a contended `Ownership.cls` edit for the orchestrator.
