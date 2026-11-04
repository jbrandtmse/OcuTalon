---
title: 'Story 8.4: Set, list and cancel reminders in plain words'
type: 'feature'
created: '2026-10-27'
status: 'done'
baseline_revision: '12f13aa0209123b8d69b50ea476f9976e1b69558'
baseline_commit: '12f13aa0209123b8d69b50ea476f9976e1b69558'
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
- [x] **Task 0** (implement stage, warm throwaway). Record each result under Design Notes as measured or (inference):
  - (a) For a waiting reminder, ReminderOps sends `Ens.AlarmTriggerRequest(<the Ens.AlarmRequest body id>)` to `Ens.Alarm` through its own `SendRequestAsync`, which never waits for a response. It sends with `..%SessionId` = the row's `TraceHeaderId` and `..%SuperSession` = the session's `TraceRef`.
    - The waiter's `OnResponse` runs at once and the instance completes.
    - Record the trigger header (session, `SuperSession`, status).
    - A trigger whose alarm has already fired adds no event-log error.
  - (b) The status values of a waiting reminder's `Ens.AlarmRequest` header, for the "not completed" filter (8.3 saw 2 or 3).
  - If (a) fails, drop the interrupt:
    - the cancelled waiter ends at its due time, sending nothing (8.3);
    - the production tests use dues of at most 15 s and wait for them;
    - record it, and report it in the Auto Run Result for the lead, because the intent's "at once" is then not met.
- [x] `src/ocutalon/cls/OcuTalon/Data/Time.cls` -- add `FromLocal(local As %String) As %String` per the Always list -- the only local-to-UTC converter (AD-18).
  - It takes exactly `YYYY-MM-DDThh:mm:ss` and converts with `$ZDateTime(<local $H>, -3)` in the process zone.
  - It returns `""` for an unreadable value (a thrown `<ILLEGAL VALUE>` included) and for a result outside `Seconds`' range.
  - Its doc states the measured gap behaviour (read one hour later) and overlap behaviour (the first instant).
- [x] `src/ocutalon/cls/OcuTalon/Data/Reminder.cls` -- AD-1's repeat rule on the row (Q3):
  - append `IdempotencyKey As %String(MAXLEN = 128)` (the key of the `SetReminder` that created the row) and `CancelKey As %String(MAXLEN = 128)` (the key of the `CancelReminder` that cancelled it);
  - no index;
  - commit the compiler's storage block (slots 10 and 11 appended).
- [x] `src/ocutalon/cls/OcuTalon/Schedule/Reminder.cls` -- replace `Accepts` with `Resolve(command, now, Output dueAt) As %String`, and correct the class doc -- one pure due-form rule.
  - It is the Always rule: `""` with `dueAt` set, or one of `no_text`, `due_forms`, `bad_time` and `past`, checked in that order.
  - A `DelaySeconds` must match an optionally signed whole number.
- [x] `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls` -- the built owner of the three verbs:
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
- [x] `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls` -- set the ReminderOps row to `"stub": 0` (Epic 8's row) -- the oracle follows the deleted `STUB`.
- [x] `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` -- in Epic 8's `OcuTalon.Data.Reminder` entry only, add `"IdempotencyKey": "%String(MAXLEN=128)"` and `"CancelKey": "%String(MAXLEN=128)"` after `"TraceHeaderId"`.
- [x] `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls` (Q1, allowed) -- nothing else; `TestTraceAndThread` stays unedited:
  - remove only `"SetReminder|ReminderOps|web_user", ` from the table (`:35`);
  - in the class doc (`:4-5`), drop `ReminderOps, ` and the count word: "to the four stub owners (ReminderOps, WatchOps, SessionOps and IncidentManager)" becomes "to the stub owners (WatchOps, SessionOps and IncidentManager)". Removal only, so Epic 5's edit of the same line stays a plain union;
  - in the method doc (`:27-29`), drop "ReminderOps (SetReminder), ".
- [x] `docker/tests/test-production.sh` (Q2, allowed) -- nothing else:
  - `:195-196` become `CHK|submit-user|1|0|refused|web_user` and `CHK|submit-tool|1|0|refused|tool`;
  - in the header (`:18`), "ReminderOps' plain-English not_built result" becomes "ReminderOps' plain-English refusal (the command names no session)".
- [x] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderFixture.cls` -- update the class doc, and add:
  - `Begin(sessionRef, itemId = "") As %Status`: the bridge context of the session as a chat tool call has it: `OwnerRef`, `ItemId` (by default a fresh `zzitem<n>`) and `SuperSession` = `TraceRef`. It is extracted from `Set`.
  - `Submit(sessionRef, command) As OcuTalon.Msg.CommandResult`: `Begin`, `Commands.Submit`, then End. `Set` uses it.
  - `Cancel(sessionRef, ref, key = "") As %DynamicObject`: a `CancelReminder` through `Submit` (the key defaults to `zzcan<n>`). It returns `{ok, outcome, message, ref, dueAt}`.
  - In `Remove(ref)`: a pending row is first cancelled through `Cancel`, and `Remove` waits at most 10 s until no `ReminderTimer` with that Ref is waiting. Then it deletes as before.
- [x] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderOpsProbe.cls` and `ReminderOpsStartedProbe.cls` -- correct "the handled set" in their docs (contract only).
- [x] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderOpsSendProbe.cls` -- extend it, and update its doc:
  - add a stand-in `SendRequestAsync(pTargetDispatchName, pRequest, pDescription = "")`, with the signature of `Ens.BusinessOperation`'s;
  - it pushes `{target, handle, sessionId, superSession}` onto a new `SeenAsync` array (`handle` is the request's `AlarmHandle`);
  - it then does what `Mode` says: ok and noanswer answer OK, error answers an error status, throw throws. Nothing is sent.
- [x] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderLogic.cls` (no production; shadow instances of `OcuTalon.Schedule.ReminderOps` or its probes) -- also update the header:
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
- [x] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderZone.cls` (new; extends `OcuTalon.Test.Bridge.ZoneCase`; no production):
  - `TestFromLocal`:
    - in America/New_York, the "Measured in planning" rows: the two Thursdays, the gap `2026-03-08T02:30:00` gives `07:30:00Z`, and the overlap `2026-11-01T01:30:00` gives `05:30:00Z`;
    - `ToLocal(FromLocal(x))` = x for both Thursdays;
    - `""` for `2026-02-30T10:00:00`, `next Thursday`, a value with a space, a value without seconds, a value with a `Z`, and `9999-12-31T23:00:00`;
    - in Asia/Kolkata, `2030-11-07T10:00:00` gives `04:30:00Z`;
    - with no zone, `ToLocal(FromLocal(x))` = x;
    - in New York, `FromLocal(day_"T00:00:00")` = `Bridge.Time.DayStartUtc(day)` for 2030-11-01 to 2030-11-09 (AD-18's comparison).
  - `TestResolveThursdayAt10`: `Resolve` with a `LocalDueAt` in New York gives `2030-11-07T15:00:00Z`, and a week earlier `2030-10-31T14:00:00Z`.
- [x] `src/ocutalon/cls/OcuTalon/Test/Schedule/Reminders.cls` (production, throwaways). Each test registers every Ref it makes for `OnAfterOneTest`; also update the header. Add:
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
- [x] `web/e2e/reminder/reminder.spec.ts` -- add test 2, "a cancelled reminder leaves the rail within one live update" (AC 3, NFR-9; Rule 3's real-runtime test), and update the header:
  1. `ReminderFixture.Set` sets a reminder due in 300 s for the rail user's session.
  2. After `signIn`, the row shows within `ROW_MS`.
  3. `ReminderFixture.Cancel` through `irisScript` answers `1|cancelled`.
  4. The row is gone within `ROW_MS` without a reload.
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

### Review Findings

Code review, 2026-10-27 (tags `e8s4c` fresh, `e8s4cw` warm). Four layers (blind, edge-case, verification-gap, acceptance) reported 23 findings; the reviewer's own Rule 2 check added 2. After triage: 11 entries (high 0, medium 3, low 8), 8 patched, 3 deferred through the ledger, 10 rejected. No AD mismatch; AD-4 holds under the lead's ruling (veto U-119): both key lookups are bound to the command's `SessionRef`, and the list and the cancel's target check read only `Ownership.Reminders`; no isolation leak was found.

- [x] [Review][Patch] (medium; blind+edge+vg+acceptance; Rule 19 hermeticity) `TestSetRepeat` left the other session's probe-made pending row behind; the closing `DELETE` now covers both sessions and asserts the other session is empty [src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderLogic.cls:545]
- [x] [Review][Patch] (medium; vg; Rule 19 pinning) `TestRefusalsWriteNothing` counted rows of the fixture session only, so a no_session set that saved before refusing stayed green; it now compares the rows with an empty or unknown `SessionRef` before and after [src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderLogic.cls:228]
- [x] [Review][Patch] (medium; reviewer, Rule 2) `HoldRow`/`LetGo` repeated `TestWakeBusyRowTriesAgain`'s inline hold-and-release code; that test now uses them [src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderLogic.cls:722]
- [x] [Review][Patch] (low; blind) `Repeated`'s rule that a second due form is a different command had no test; `TestSetRepeat` now repeats the key with the same Text and `DueAt` plus a `DelaySeconds` and expects `reused_key` [src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderLogic.cls:491]
- [x] [Review][Patch] (low; edge) a Text of only a line break passed `no_text`, because `$ZStrip`'s `W` strips only tab, space and no-break space (measured on slot C, build 154); `Resolve` strips control characters too, and `TestResolve` pins it [src/ocutalon/cls/OcuTalon/Schedule/Reminder.cls:39]
- [x] [Review][Patch] (low; blind) `Resolve`'s separate `DelaySeconds < 1` past check could never decide anything (the next check covers it); deleted [src/ocutalon/cls/OcuTalon/Schedule/Reminder.cls:52]
- [x] [Review][Patch] (low; blind) `ReminderLogic`'s class doc and `HOLDSECONDS` doc named only Story 8.3 and `TestWakeBusyRowTriesAgain`, while the cancel lock tests also depend on `HOLDSECONDS` exceeding the lock timeout [src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderLogic.cls:1]
- [x] [Review][Patch] (low; vg) assertions in the production cancel tests that no change to this story's code could fail were removed: the answer-in-the-command's-session pair of `TestCancelEndsWaiter` (the framework sets that session), its and `TestSeveralCancelsFromOneToolCall`'s "sent nothing to Notify" before the due time (a waiter never sends before its due time), and `TestCancelIsolationAndRepeats`' empty event stream of a session that owns no reminder; the docs no longer cite them. "No notification" stays pinned by `TestCancelInterruptFails`, isolation by the row state and QA's alarm count [src/ocutalon/cls/OcuTalon/Test/Schedule/Reminders.cls:378]
- [x] [Review][Defer] (low; vg) demo-path step 3 still reads `notBuilt(..., '8.4')` [web/e2e/demo-path/03-reminder.spec.ts:4] — deferred: DW-303 `by-design` (the split bars 8.4 from the demo-path specs; Story 8.6 replaces the call when it turns step 3 on)
- [x] [Review][Defer] (low; acceptance) AC 4's "other fields" against the repeat rule: a relative-form repeat compares the Text only, so a re-run with the same Text and another `DelaySeconds` gets the first result [src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls:140] — deferred: `by-design` under Boundaries > Repeats and Decided 2, recorded as an occurrence on DW-141 (owned by this story) for its adjudication. Should the rule be tightened, the first command's delay is `Seconds(DueAt) - Seconds(CreatedAt)` of the row, with no new property.
- [x] [Review][Defer] (low; reviewer, Rule 2) `Reminders.Rows` repeats `ReminderLogic.Rows` (a 3-line count; each Test area keeps its own private `Rows`) [src/ocutalon/cls/OcuTalon/Test/Schedule/Reminders.cls:278] — deferred: DW-304 `wontfix-accepted`, reopen_if a third copy appears or the copies diverge

Rejected:
- `low` `ReminderFixture.Submit` returns "" on a Submit error without its text: the documented helper contract; only a stopped production reaches it, and the test still fails.
- `low` `test-production.sh:18` is long and names the no_session refusal while row 17 checks only `refused`: the orchestrator's Q2 dictates that phrase and those two lines, nothing else (spec-bound).
- `low` the key and `SessionRef` lookups use the default SQLUPPER collation: theoretical; Refs and ItemIds are random 22-character base64url values, and `Ownership` and `RefIndex` compare the same way. Real only if keys stopped being random.
- `low` a `DelaySeconds` of -99999999999 answers `bad_time`, not `past`: the spec orders readability before past, and the tool sends digits only from origin `tool` (spec-bound, unreachable).
- `low` `EndWaiter` logs nothing when it finds no open alarm: the waiter then ends at its due time sending nothing, the spec's own fallback; real only if a row's `TraceHeaderId` could point at a session with no alarm while the waiter waits.
- `low` a failed `%DeleteId` after a failed start leaves a keyed row that a repeat answers `set`: needs a start failure and a delete failure together (8.3's ignored status); theoretical.
- `low` `TestCancelRacesFire` relies on the cancel reaching its lock wait within the 3-second hold: milliseconds against 3 s, and its mutation was observed red; a timing assertion would break NFR-10.
- `low` `TestSeveralCancelsFromOneToolCall` throws `<INVALID OREF>` when fewer events arrive: the test still fails, loudly.
- `low` the spec's Tasks still say 5 s and "no trigger header" for two tests: the fix edits the spec's Tasks; the Review Triage Log records both changes.
- `false` the spec's `status: done` during review: that is build-auto's machine state; `sprint-status.yaml` carries the review state.
- `false` (part of the vg finding) `TestSeveralCancelsFromOneToolCall`'s "the other session's reminder is pending / waiting" cannot fail: a cancel of the wrong row fails them; the interrupt itself is QA's alarm count, as recorded.

- [x] [Review] U-119 condition (the owner, through the Contest Planner, kept the AD-4 reading of Decided 3 on this condition): a test pins that a repeated command carrying ANOTHER session's key finds nothing and reveals nothing - no row, no result and no error text that tells it apart from "not found". Cases, in `Test/Schedule/Reminders.cls` (or `ReminderLogic.cls` where no production is needed): (a) session A sends a `SetReminder` with session B's `IdempotencyKey` and DIFFERENT fields: it is a fresh set for A (`1|set`, a new Ref that is not B's), never `reused_key`, and B's row is untouched; (b) session A sends a `CancelReminder` with session B's `CancelKey` and B's `ReminderRef`: the answer is exactly the `no_reminder` refusal an unknown Ref gets (same Ok, Outcome and Message, character for character), never B's first result and never `reused_key`; nothing changes and no event or trigger goes out; (c) session A sends a `CancelReminder` with session B's `CancelKey` and A's own pending `ReminderRef`: A's reminder is cancelled normally (its own first result), never `reused_key`. Each case gets an observed mutation (for example the key lookup without its `SessionRef` filter) and a `mutation:` line under `## Verification`. Test-only unless a case fails, in which case fix `ReminderOps` within Decided 3.

Code review, rework iteration 1, 2026-10-27 (scope `12f13aa..HEAD`; tags `e8s4d` fresh, `e8s4dw` warm). Four layers reported 20 findings. After triage: 5 entries (high 0, medium 2, low 3), all patched; 9 findings rejected. The U-119 condition is met: (a), (b) and (c) are pinned as the item words them, and their recorded mutations fail them. The patches below make case (b) compare the whole answer, and make both tests repeat their own command. No AD mismatch: `ReminderOps` is unchanged, and AD-4 holds under the owner's U-119 decision.

- [x] [Review][Patch] (medium; blind+edge+acceptance; U-119 (b), Rule 19) case (b) compared `ReminderFixture.Cancel`'s five-member projection, so `CommandResult.Data` was never compared, although the test claims "every member of the answer". `Cancel` now also returns `data`, so the whole answer is compared [src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderFixture.cls:54]
- [x] [Review][Patch] (medium; blind, Rule 2) `SetKeyed` repeated the body of `TestSetRepeatOneWaiter`'s submit loop; that test now calls it [src/ocutalon/cls/OcuTalon/Test/Schedule/Reminders.cls:609]
- [x] [Review][Patch] (low; edge+acceptance) once both sessions' rows hold the key, neither test repeats its own command. A key lookup that reads the earliest row with the key in any session and then drops another session's row passes (a), (b) and (c), yet a repeat would then make a second reminder or get `no_reminder`. Each test now repeats its own command and expects that command's first result [src/ocutalon/cls/OcuTalon/Test/Schedule/Reminders.cls:546]
- [x] [Review][Patch] (low; vg+acceptance) in case (b) the other session's reminder is already cancelled and its waiter has ended, so its row and its trigger count cannot change; only its events can. The test's doc now says exactly what case (b) pins. The acceptance layer's stray-trigger sub-claim is false: `EndWaiter` sends only in the row's own trace session (`TestCancelEndsWaiter`), and only after a publish that the event checks see [src/ocutalon/cls/OcuTalon/Test/Schedule/Reminders.cls:549]
- [x] [Review][Patch] (low; blind+acceptance, Rule 19) the rework recorded no reverse-order run of its tests; a fresh `shard lane-b --reverse` run in this pass, with the patches, passed 64 classes in 442 s [ci/iris.sh shard lane-b --reverse]

Rejected:
- `false` (acceptance) the other session's row is checked on some columns only: no `ReminderOps` path writes the unchecked ones on an existing row. A set inserts a new row, a repeat writes nothing, and a cancel writes only `State` and `CancelKey`, which are both checked.
- `false` (acceptance) cases (b) and (c) share one `mutation:` line: the line names each case's own failing assertions from the observed run.
- `low` (blind+acceptance) the Blind 5 triage reason calls `baseline_commit` the story's base and cites Rule 17: the lead moved it to the rework's base for this scoped re-review. The fix would edit the spec's triage history.
- `low` (blind+edge) the rework's tallies say 16 rejected, but 15 were (Blind 3 and VG 3 share the one patch row): the fix would edit the spec's Auto Run Result and the lead's cycle log.
- `low` (blind) the rework's `dev_complete` cycle-log line lacks `loc_added`, `loc_removed`, `nfr_tripwires` and `adr_violations_surfaced`: the cycle log is the lead's.
- `low` (blind) the first pass's Auto Run Result still lists Decided 3 as the lead's to confirm: that result covers only its own pass (Rule 14). U-119 is kept and its condition is met, as this review records.
- `low` (vg) the Edge 3 rejection reason says the waiter exists when the set answers, but `Ens.BusinessProcess.Reply` queues the answer before the instance is saved: the new tests read a waiter only after further round trips, and the fix would edit the spec's triage log.

## Spec Change Log

- 2026-10-27 (lead): rework iteration 1 opened after code review (done, no HIGH) for the owner's U-119 condition (AD-4 reading kept with a cross-session key test); one `[Review]` item under Tasks & Acceptance.

- 2026-10-27 (lead, after the plan's intent-gap HALT): the orchestrator allowed Q1, Q2 and Q4 and routed DW-140/DW-142 (U-118); the lead split the story (8.4 command side, 8.6 chat side) and ruled Q3 decide. Recorded under Intent and Design Notes; Clarification Needed removed; status set to `draft` to re-plan this story as the command side.

## Review Triage Log

### 2026-10-27 - Review pass
- verdicts: 36 findings from the four layers, grouped into 24 rows by shared root cause - high 0, medium 2, low 21, false 1, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind 1 / Edge 6 / Edge 10: a repeated key with another `DelaySeconds` gets the first result, not `reused_key` - the spec compares Text, and the instant only for an absolute form (Repeats, matrix row "Reused key"); the row has no delay column and "no new table, index" bars storing one; a model re-sends a key only for a retried call
  - `[low]` `[reject]` Blind 2 / Edge 7: a repeat of a set whose reminder fired or was cancelled still answers `set` - spec-bound: "A repeated key gets the first result" (by-design)
  - `[low]` `[reject]` Blind 3: an open failure other than the lock timeout in `Cancel` answers `no_reminder` - `IsPending` has just found the row, so only a lock or deadlock error can follow; theoretical
  - `[low]` `[reject]` Blind 4: no upper bound on the due time - spec-bound: `bad_time` is "past year 9999" (matrix); a `too_far` refusal would be new public text
  - `[low]` `[reject]` Blind 5 / Edge 8: `Remove` ignores the result of `Cancel` - the earlier `Remove` also deleted a waiter's headers while it waited; no new harm, and a failed cancel means the production is down
  - `[medium]` `[patch]` Blind 6 / VG O1 / VG 1: no test of a local-form repeat or of a key in another session - added both to `ReminderLogic.TestSetRepeat`; mutations written. The other listed gaps (empty `ReminderRef`, empty cancel key, Text over 1000 characters, a forced `Ownership` error) are `wontfix-theoretical`: each is a one-line guard with no user-reachable failure
  - `[low]` `[patch]` Blind 7 / VG 3: the last assertion of `reminder.spec.ts` test 2 (no notice card, due in 300 s) cannot fail - removed it and its two mentions; the row-removal assertion stays, and its mutation (Cancel does not publish) was run: sign-in 219 passed, test 2 red
  - `[low]` `[reject]` Blind 8: row 17 of `test-production.sh` only shows a refusal - Q2 of the orchestrator allows exactly these two lines; the live set, list and cancel path is the `Reminders` class
  - `[low]` `[reject]` Blind 9: no index on the key columns - spec-bound: "no new table, index or production item"; demo-sized tables
  - `[low]` `[reject]` Edge 1: a DelaySeconds string of more than about 146 digits throws and answers `failed` - the tool types it as a number; no realistic input
  - `[low]` `[reject]` Edge 2: the key lookup's SQLCODE is not checked - a static statement; theoretical
  - `[low]` `[reject]` Edge 3: the row cannot be reopened after the unlock - it was just saved; theoretical
  - `[low]` `[reject]` Edge 4: Publish or EndWaiter throwing after the save answers `failed` - a retry with the same key answers the first result (CancelKey); theoretical
  - `[low]` `[reject]` Edge 5: the alarm query excludes only status 9 - measured in Task 0 (a waiting alarm is status 3); a trigger for a dead alarm is a warning at most
  - `[false]` `[reject]` Edge 9: `TestSetRepeat` cleans by CreatedAt in the last hour - the delete is bound to the test's own unique fixture session
  - `[medium]` `[patch]` VG 2a: the three `SeenAsync = 0` assertions in `ReminderLogic` cannot fail (fixture rows have no `TraceHeaderId`, so `EndWaiter` sends nothing either way) - removed; the state, key and event assertions of those tests pin the behaviour
  - `[low]` `[patch]` VG 2b: the spec's mutation line credited `TestCancelEndsWaiter`'s answer-header check with the `%SessionId` restore - corrected; only `TestCancelInterruptFails` pins it
  - `[low]` `[reject]` VG 4: more clauses without their own mutation line - Rule 19 asks one demonstrated mutation per AC, and each AC has several; the cancel Ref comparison and the local compare were added anyway
  - `[low]` `[patch]` VG 5a: `Remove` waited for the waiter only for a row it cancelled itself - it now waits for every row (returns at once when no waiter is waiting)
  - `[low]` `[patch]` VG 5b: `TestCancelInterruptFails` set a reminder due in 5 seconds, so a slow runner could fire it before the cancel - now 12 seconds
  - `[low]` `[reject]` VG 5c: the busy-lock test relies on the process lock timeout being under 40 s - documented in the test; the default is 10 s
  - `[low]` `[reject]` VG O2: the empty-key rule is tested for set only - the cancel branch is one `If` on the same property, pinned by the several-cancels test with distinct keys
  - `[low]` `[reject]` VG O3: `TestSetByDelayAndLocal` compares with `FromLocal` itself - `ReminderZone` pins the conversion in two zones
  - `[low]` `[reject]` VG O4 / Intent 1-6 (descriptive): the chat surface is Story 8.6's by the lead's split; publish after the lock is released is the Boundaries order; arrival is `OnMessage`; relative repeats compare Text only (see Blind 1); the multi-cancel test runs at `CommandCall.Run`, the layer below Lane A's tool; the browser test covers the cancel effect on the rail only - all stated in the spec

### 2026-10-27 - Review pass (rework iteration 1, U-119 condition)
- verdicts: 17 findings from the four layers (16 rows; Blind 3 and VG 3 share one) - high 0, medium 0, low 6, false 11, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind 1: the set case does not test the same fields under the other session's key - `ReminderLogic.TestSetRepeat` (the key of another session is not seen) pins that, and the item's case (a) names DIFFERENT fields
  - `[false]` `[reject]` Blind 2: case (b) runs against an already cancelled Ref - the other session's CancelKey exists only after its cancel, so its Ref is cancelled by construction; the mutation (key lookup without SessionRef) went red there, which is the discrimination
  - `[low]` `[patch]` Blind 3 / VG 3: the b/c mutation line says case c is red "separately" - it is the same run and mutation, as its own failing assertions; the Verification line now says so
  - `[false]` `[reject]` Blind 4: nothing pins that CancelKey has no global unique index - the case (c) test stores the same key on two rows of two sessions and would fail if one were added
  - `[false]` `[reject]` Blind 5: review_loop_iteration, change log and the two revisions - the counter moves on a bad_spec loopback only; baseline_revision is this pass's base and baseline_commit the story's (Rule 17)
  - `[low]` `[reject]` Edge 1: a row opened from a Ref the result reported could be empty and throw - the Ref is asserted non-empty first and a throw fails the test loudly; the sibling tests do the same
  - `[false]` `[reject]` Edge 2: a late trigger from the refused cancel would be missed - the trigger header is created when the cancel runs, before the answer returns, and `Reminders` counts the same way elsewhere
  - `[false]` `[reject]` Edge 3: the waiter is counted before it exists - `StartWaiter` sends synchronously, so the Timer exists when the Set answers
  - `[false]` `[reject]` Edge 4: duplicate of Blind 2
  - `[low]` `[reject]` Edge 5: the member-for-member compare covers the fixture's five members, not Data - refusals carry no Data and the item names Ok, Outcome and Message
  - `[low]` `[reject]` VG 1: no mutation leaves the answer right and leaks a side effect in case (b) - Rule 19 asks one mutation per AC, and the side-effect assertions share the case's observed mutation
  - `[low]` `[reject]` VG 2: `mine.DueAt '= theirs.DueAt` is redundant beside the Ref assertion - it fails if a lookup hands back the other session's due time with a new Ref; not worth a change
  - `[false]` `[reject]` Intent 1: no tool-layer or e2e test - the item places the cases in Reminders.cls and the chat side is Story 8.6's
  - `[false]` `[reject]` Intent 2: the cases come from the U-119 bullet, not the contract - the bullet is this pass's spec
  - `[false]` `[reject]` Intent 3: case (b) discrimination - same as Blind 2
  - `[false]` `[reject]` Intent 4: the relative form compares text only - the contract says so, and case (a) differs in text so reused_key is the mutation's red

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

**Task 0, measured on the warm throwaway (implement stage, build 154):**
- (a) ReminderOps' `SendRequestAsync("Ens.Alarm", Ens.AlarmTriggerRequest(<the Ens.AlarmRequest body id>))`, sent with `..%SessionId` = the row's `TraceHeaderId` and `..%SuperSession` = the session's `TraceRef`, interrupts the waiter at once (measured). The waiter's `OnResponse` ran within the second and the instance completed (no `ReminderTimer` waiting). The trigger header is request type 1, `ReminderOps` to `Ens.Alarm`, `Ens.AlarmTriggerRequest`, in the waiter's session, with `SuperSession` = `TraceRef`, status 9 (completed), no error. The alarm request header went from 3 to 9 (completed), and `Ens.AlarmResponse` came back from `Ens.Alarm` to `ReminderTimer` in the same session. The event log of the waiter's session holds no warning or error rows. A trigger for an alarm that has already fired adds no event-log error (inference, from `InterruptAlarm` reading no data for an unknown handle).
- (b) A waiting reminder's `Ens.AlarmRequest` header has status 3 (delivered) for as long as it waits (measured at once and 3 s later; 8.3 saw 2 or 3). The "not completed" filter is `Status <> 9`.
- The fallback (drop the interrupt) is not needed: the intent's "at once" is met.

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
  - `EndWaiter` doesn't put `%SessionId` back -> `Reminders.TestCancelInterruptFails` (the probe's session id);
  - `EndWaiter` sends without the waiter's session id -> `TestCancelInterruptFails` (`SeenAsync`) and `TestCancelEndsWaiter` (the trigger header in the waiter's session);
  - a failed interrupt answers `failed` instead of `cancelled` -> `TestCancelInterruptFails`;
  - `Cancel` doesn't publish -> `TestCancelEndsWaiter` and `reminder.spec.ts` test 2.
- **AC 4:**
  - `Set` ignores the key -> `ReminderLogic.TestSetRepeat` and `Reminders.TestSetRepeatOneWaiter`;
  - a reused set key with other text is accepted -> `TestSetRepeat`;
  - `Cancel` ignores `CancelKey` -> `TestCancelIsolationAndRepeats`;
  - the cancel's repeat lookup drops `CancelKey = ?` and takes any cancelled row of the session -> `TestSeveralCancelsFromOneToolCall` (the second and third cancels get the first's result).

**Mutations observed in the implement stage (Rule 19).** Each was applied to the file, run on the warm stack (the ReminderOps item restarted before the production class), seen red, and reverted; the tree was byte-identical afterwards (checked by checksum).
- mutation: `Resolve` adds 0 instead of `DelaySeconds` -> `ReminderLogic.TestResolve` (and `TestSetRepeat`) and `Reminders.TestSetByDelayAndLocal`, `TestListToolReadsTheList`, `TestSetRepeatOneWaiter`
- mutation: `FromLocal` uses a fixed offset of 5 hours -> `ReminderZone.TestFromLocal` and `TestResolveThursdayAt10`
- mutation: `Resolve` accepts two forms (only no form is `due_forms`) -> `ReminderLogic.TestResolve` and `TestRefusalsWriteNothing`
- mutation: `Set` writes a row before it refuses (a refusal saves a pending row) -> `ReminderLogic.TestRefusalsWriteNothing`
- mutation: `List` reads the session's rows of every state -> `ReminderLogic.TestListShape`
- mutation: `List` sets the `text` item without the `string` type -> `ReminderLogic.TestListShape` (the earlier row's Text is saved as the number 100, so the item becomes a JSON number and `Listed` answers `NOTREAD`). With the Text saved as the string "100" this mutation stays green on build 154, because a string read back from storage is already a string; the test therefore saves the number.
- mutation: `List` orders by `CreatedAt` -> `ReminderLogic.TestListShape` and `Reminders.TestListToolReadsTheList`
- mutation: `Cancel` skips the `Ownership` check (`IsPending`) -> `Reminders.TestCancelIsolationAndRepeats`. The cancel no longer re-checks the row's `SessionRef` after the lock, so the `Ownership` check is the one guard.
- mutation: `Cancel` doesn't check `pending` again under the lock -> `ReminderLogic.TestCancelRacesFire`
- mutation: `Cancel` doesn't call `EndWaiter` -> `Reminders.TestCancelEndsWaiter`, `TestCancelInterruptFails`, `TestCancelIsolationAndRepeats` and `TestSeveralCancelsFromOneToolCall`
- mutation: `SendIn` doesn't put `%SessionId` back -> `Reminders.TestCancelInterruptFails` (the probe's session id). A production job's answer header takes its session from the request header, so only the shadow instance shows the missing restore (code review removed `TestCancelEndsWaiter`'s answer-header pair, which could not fail).
- mutation: `EndWaiter` sends without the waiter's session id -> `Reminders.TestCancelInterruptFails` (`SeenAsync`) and `TestCancelEndsWaiter` (the trigger header in the waiter's session)
- mutation: a failed interrupt answers `failed` instead of `cancelled` (the send error is thrown) -> `Reminders.TestCancelInterruptFails`
- mutation: `Cancel` doesn't publish -> `Reminders.TestCancelEndsWaiter` (the events), `TestCancelInterruptFails`, `TestCancelIsolationAndRepeats` and `TestSeveralCancelsFromOneToolCall`. With the Publish call of `Cancel` replaced by `Set published = $$$OK`, `ci/iris.sh live sign-in` ran 219 passed and 1 failed: `reminder.spec.ts` test 2 (the row stayed in the rail), 7.1 minutes of Playwright.
- mutation: the local-form comparison of a repeat is always false (`Set same = 0`) -> `ReminderLogic.TestSetRepeat` ("a local form repeated gets the first result")
- mutation: the set key lookup ignores the session (`WHERE ? <> ''` for `SessionRef = ?`) -> `ReminderLogic.TestSetRepeat` (the first command, the other session's command and the row counts)
- mutation: a cancel key naming another Ref is accepted (`If 0 Quit ..Refuse("reused_key")`) -> `Reminders.TestCancelIsolationAndRepeats` and `TestSeveralCancelsFromOneToolCall`
- mutation: `Set` ignores the key (no repeat lookup) -> `ReminderLogic.TestSetRepeat` and `Reminders.TestSetRepeatOneWaiter`
- mutation: a reused set key with other text is accepted (the `Text` comparison removed) -> `ReminderLogic.TestSetRepeat`
- mutation: `Cancel` ignores `CancelKey` (no repeat lookup) -> `ReminderLogic.TestCancelFixtureRow` and `Reminders.TestCancelIsolationAndRepeats`, `TestSeveralCancelsFromOneToolCall`
- mutation: the cancel's repeat lookup drops `CancelKey = ?` and takes any cancelled row of the session -> `Reminders.TestSeveralCancelsFromOneToolCall` (the second and third cancels are refused instead of cancelled) and `TestCancelIsolationAndRepeats`

**QA gap audit (qa stage, tags `e8s4q` fresh and `e8s4qw` warm; no new test file).** Every matrix row and AC clause was read against the tests and the observed mutations above. Clauses that had a test but no observed red, and one clause with no test, were closed as follows; each mutation was applied to the file, run on the warm stack (ReminderOps item restarted before `Reminders`), seen red, reverted from a backup, and the revert seen green on the same stack (the tree held only the two test edits afterwards, checked with `git status --short`).
- (QA) `Test/Schedule/ReminderLogic.cls`, new `TestThrownErrorAnswersFailed` (the Answers rule: an error thrown inside a verb is logged and answered `failed`; no test covered it): a SetReminder whose Text is 1001 characters makes the row's save fail.
  - mutation: `OnMessage`'s Catch leaves `pResponse` empty instead of answering `failed` -> `ReminderLogic.TestThrownErrorAnswersFailed` ("a CommandResult comes back")
- (QA) `Test/Schedule/Reminders.cls`, `TestSeveralCancelsFromOneToolCall` gains one assertion (AC 3, the other session's waiter untouched): the other session's waiter has set exactly one alarm. Its earlier "pending and waiting" assertions stay green when the waiter is interrupted, because `Wake` re-arms a pending row's timer, so they could not show an interrupt of the wrong session.
  - mutation: `EndWaiter`'s alarm query drops `SessionId = ?` (it interrupts every session's alarms) -> `Reminders.TestSeveralCancelsFromOneToolCall` ("the other session's waiter never woke early", and the trigger counts) and `TestCancelIsolationAndRepeats` ("and one trigger")
- Existing tests whose mutation had never been observed red, now observed:
  - mutation: `SessionExists` answers 1 for a non-empty Ref -> `ReminderLogic.TestRefusalsWriteNothing` (set, list and cancel "unknown session")
  - mutation: a message that is not a verb gets error code 5003 instead of 5001 -> `ReminderLogic.TestRefusalsWriteNothing` ("that is not 5003")
  - mutation: `Resolve` drops the `dueSeconds '> current` past check -> `ReminderLogic.TestResolve` (a past `DueAt`, a `DueAt` that is now, a past `LocalDueAt`) and `TestRefusalsWriteNothing` ("past")
  - mutation: a cancel whose row lock times out answers `no_reminder` instead of `failed` -> `ReminderLogic.TestCancelBusyRowFails` ("the cancel answers failed")
  - mutation: the `"IdempotencyKey"`/`"CancelKey"` contract line `CancelKey` removed from Epic 8's `Data.Reminder` entry -> `Test.Data.Tables.TestContracts` ("property CancelKey is not in the contract")
  - mutation: the ReminderOps oracle row set back to `"stub": 1` -> `Test.Install.Production.TestStubsAnswer` ("ReminderOps: ... carries STUB")
- Not added, with the reason: an empty `IdempotencyKey` on a cancel (the matrix has no row for it; the spec says an empty key turns repeat detection off). A test was written and the guard removed (`If 1` for `If command.IdempotencyKey '= ""` in `Cancel`): it stayed green, because a bound empty string is an SQL NULL that `CancelKey = ?` never matches, so the guard is redundant and the behaviour cannot regress through it. The test was deleted (an assertion that cannot fail). The empty-key set is pinned by `TestSetRepeat`.
- Fresh stack: `Reminders` and `ReminderLogic` passed on `e8s4q`.

**Code review (tags `e8s4c` fresh and `e8s4cw` warm).** Each mutation was applied to the file, run on the warm stack, seen red on the named assertion only, and reverted from a backup (checksums equal); `ReminderLogic` was green again on the same stack after the last revert, and `ReminderZone` and `Reminders` (ReminderOps restarted) were green with the patches.
- mutation: `Repeated` ignores the number of due forms (`Set same = 1`) -> `ReminderLogic.TestSetRepeat` ("and so is the same Text and DueAt with a second due form")
- mutation: `Resolve`'s blank check strips whitespace only (`"<>W"` for `"<>WC"`) -> `ReminderLogic.TestResolve` ("a Text of only a space and a line break")
- mutation: `Set` checks the session after the row's save -> `ReminderLogic.TestRefusalsWriteNothing` ("and none for an empty or an unknown session"); before the review this mutation stayed green.

**U-119 condition (rework, tags `e8s4j` fresh and `e8s4jw` warm).** `Reminders.TestSetKeyOfAnotherSession` (case a) and `TestCancelKeyOfAnotherSession` (cases b and c) pin that a key another session used finds nothing and reveals nothing. Each mutation was applied to `ReminderOps.cls`, run on the warm stack (the ReminderOps item restarted first), seen red, and reverted from a backup (checksum equal, `git status --short` and `git diff --stat` as before); `Reminders` was green again on the same stack after each revert.
- mutation: the set key lookup ignores the session (`WHERE ? <> ''` for `SessionRef = ?` in the `IdempotencyKey` statement) -> `Reminders.TestSetKeyOfAnotherSession` (case a: "the same key with other fields in this session is a fresh set, not reused_key", "with a new Ref that is not the other session's")
- mutation: the cancel key lookup ignores the session (`WHERE ? <> ''` for `SessionRef = ?` in the `CancelKey` statement) -> `Reminders.TestCancelKeyOfAnotherSession`, case b ("the other session's key and Ref get that answer, member for member": the other session's first result comes back) and, as its own failing assertions in the same run, case c ("the other session's key with this session's own Ref cancels it, with its own result", plus its row, event, waiter and trigger assertions: `reused_key` comes back)

**Code review of the rework (tags `e8s4d` fresh and `e8s4dw` warm).** Each mutation was applied to `ReminderOps.cls` from a backup, reloaded on the warm stack, run after a ReminderOps item restart, and seen red on the named assertions only. It was then restored from the backup: the checksum matched, `git status --short` and `git diff --stat` were as before, and the file equals HEAD. `Reminders` was green on the same stack after the last revert (30.0 s) and with the patches before any mutation (30.5 s). A fresh `shard lane-b --reverse` passed 64 classes in 442 s (`Reminders` 30.0 s), and `bash ci/checks.sh` and `test-boundaries.sh` passed.
- mutation: `Cancel`'s refusal for a Ref that is not the session's pending one carries `Data` "known" when the Ref names an existing row -> `Reminders.TestCancelKeyOfAnotherSession`, case b ("the other session's key and Ref get that answer, member for member"). This mutation could not fail that assertion before `ReminderFixture.Cancel` also returned `data` (by reading, not run).
- mutation: `KeyedRow` reads the earliest row with the key in any session and returns nothing when that row is another session's (`WHERE ? <> ''` for `SessionRef = ?` in both statements, plus `If row.SessionRef '= sessionRef Quit ""`) -> `Reminders.TestSetKeyOfAnotherSession` ("this session's command again gets its own first result while the other session's row holds the key too", "and makes no second row or event") and `TestCancelKeyOfAnotherSession` ("this session's cancel again gets its own first result while the other session's row holds the key too"). Every assertion of (a), (b) and (c) that predates this review stayed green under it.
- The two lines above them still hold, with no new run (by reading): their named assertions are unchanged, and the other session's first result still differs from the refusal in Ok, Outcome and Message.

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

Status: done
Blocking condition: none

**Rework iteration 1 (U-119 condition).** Test-only: `Test/Schedule/Reminders.cls` gained `TestSetKeyOfAnotherSession` (case a) and `TestCancelKeyOfAnotherSession` (cases b and c) with a `SetKeyed` helper; `ReminderOps.cls` is unchanged because all three cases passed at once. The item is `[x]` and two `mutation:` lines (key lookups without their `SessionRef` filter) sit under `## Verification`.
- **Review:** 17 findings, no high; 1 spec-wording patch, 16 rejected with reasons in the Review Triage Log; nothing deferred. Follow-up review recommended: false (no high patched).
- **Verification:** fresh `class OcuTalon.Test.Schedule.Reminders` passed (30.7 s), fresh `shard lane-b` passed (64 classes), `bash ci/checks.sh` and `bash docker/tests/test-boundaries.sh` passed. Warm and fresh stacks are torn down.

**Implement and review (bmad-build-auto).** `ReminderOps` now carries out SetReminder, ListReminders and CancelReminder; the plan-stage notes follow below the result.
- **Summary:**
  - `Schedule.Reminder.Resolve` replaces `Accepts` (the due-form rule) and `Data.Time.FromLocal` is the local-to-UTC converter.
  - `Data.Reminder` gained `IdempotencyKey` and `CancelKey` (storage slots 10 and 11).
  - `ReminderOps` lists and cancels through `Data.Ownership`. A cancel re-checks `pending` under the row lock, publishes the cancelled event and interrupts the waiter's alarm with an `Ens.AlarmTriggerRequest`. Set and cancel repeats are answered from the row.
  - Task 0 measured that the interrupt ends the waiter at once.
- **Files changed:**
  - `src/ocutalon/cls/OcuTalon/Data/Reminder.cls`, `Data/Time.cls`, `Schedule/Reminder.cls`, `Schedule/ReminderOps.cls`: the product code.
  - `Test/Schedule/ReminderLogic.cls`, `Reminders.cls`, `ReminderZone.cls` (new), `ReminderFixture.cls` and the three probes: the tests.
  - `Test/Core/CommandsInProduction.cls` (Q1), `Test/Core/ProductionItems.cls`, `Test/Data/Tables.cls`: the stub-owner and contract rows.
  - `docker/tests/test-production.sh` (Q2): row 17.
  - `web/e2e/reminder/reminder.spec.ts`: test 2.
- **Review:** 36 findings, no high. Patches applied: a local-form repeat and a key in another session in `TestSetRepeat`; three vacuous `SeenAsync` assertions removed; the vacuous notice-card assertion of `reminder.spec.ts` test 2 removed; `Remove` waits for every waiter; `TestCancelInterruptFails` due in 12 s; two stale mutation lines corrected, three mutation lines added. Deferred: none. Every rejected finding and its reason is in the Review Triage Log.
- **Follow-up review recommended:** false. The two medium patches are tests, and each was run red against its mutation and green after the revert.
- **Verification (all in this tree, lane C):**
  - Warm: `ReminderLogic` and `Reminders` green after the patches; mutations red then green (local repeat compare, session scope of the key lookup, cancel Ref compare).
  - Fresh: `shard lane-b` 64 classes, `lane-b --reverse` and `shard lane-a` 47 classes passed; `live production` passed (row 17 `refused`).
  - `live sign-in` passed 220 of 220 in 499 s. With Cancel's Publish removed it ran 219 passed and 1 failed (`reminder.spec.ts` test 2).
  - `npm --prefix web run lint` exit 0, `npm --prefix web test` 691 pass, `bash ci/checks.sh` exit 0, `bash docker/tests/test-boundaries.sh` passed. The warm and fresh stacks are torn down.
- **Residual risks:** Decided 3 (AD-4: ReminderOps' own session-scoped key lookups) is the lead's to confirm. The interrupt of an already-fired alarm adds no error is inference from `InterruptAlarm`, not measured.

**Plan stage (bmad-build-auto, re-plan in place, cycle 2; halted after planning).** The command side is re-derived around the preserved intent block. These left the spec for Story 8.6: the B mock scenarios, `ReminderChat`, spec 03, DW-210, DW-232, the `NewRef` seam, `ReminderOpsFixedRef` and `CancelPending`.
- **Kept from the first plan (467dfae):** the `FromLocal` measurements and Task 0's alarm interrupt.
- **Added:** AC 4's several-cancels clause and its test (U-118); the lock race and busy-lock cases; string-typed list items; the item restart on the warm stack.
- **Ledger:** DW-135 and DW-141 addressed; DW-140 and DW-142 declined (Lane A's, for Story 11.1).
- **For the lead to check:** Decided 3 reads AD-4 as allowing ReminderOps' own session-scoped key lookups. If the lead reads it otherwise, that is a contended `Ownership.cls` edit for the orchestrator.
