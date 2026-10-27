---
title: 'Story 8.3: A reminder fires on time on every channel'
type: 'feature'
created: '2026-10-26'
status: 'blocked'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** `ReminderOps` and `ReminderTimer` are still Epic 0 stubs that answer "not implemented". So a reminder can't be set, never shows in Visual Trace as a waiting process, and never fires. The rail's Reminders rows and the reminder notice cards have only ever shown fixture data (FR-34).

**Approach:** `ReminderOps` carries out a `SetReminder` whose one due form is a UTC `DueAt`:
1. It writes the `Reminder` row.
2. It starts one `ReminderTimer` waiter in a trace session of its own. The start is synchronous, as `ApprovalStartIn`'s is, so the waiter has stored its start header id on the row before the call returns.
3. It publishes the `reminder` event (created).
4. It answers with the `Ref` and `DueAt`.

The waiter is frozen: it stores only `Ref`, and its logic lives in `OcuTalon.Schedule.Reminder`. It waits on `SetTimer`. When it wakes, it holds the row's lock and does four things: marks the row fired (late if it woke more than 10 s after the due time), sends one `reminder` Notification through `Notify`, releases the lock and publishes the event (fired). Every other due form and verb keeps answering `not_built` until Story 8.4.

## Boundaries & Constraints

**Always:**
- **Command path.** Commands go only through `Commands.Submit`, then `CommandsIn`, then `ReminderOps` (AD-1). The row is the truth, and the waiter mirrors it (AD-5, AD-18).
- **What this story carries out.** `ReminderOps` acts only on a `SetReminder` that has all of these:
  - a non-empty `Text`;
  - a `DueAt` that `Data.Time.Seconds` can read and that is later than now;
  - no `DelaySeconds` and no `LocalDueAt`;
  - a `SessionRef` that names a `Session` row.

  For anything else it returns `$$$ERROR($$$NotImplemented)` and writes nothing, exactly as the stub does today, so `CommandsIn` answers `not_built`. "Anything else" covers the other due forms, both forms, no form, empty text, an unreadable or past `DueAt`, an unknown session, `ListReminders`, `CancelReminder` and any other message. Story 8.4 replaces this with its refusals and due forms.
- **The frozen waiter.** `ReminderTimer` has exactly one persistent property, `Ref`, and it is append-only from now on. `OnRequest` and `OnResponse` only call `OcuTalon.Schedule.Reminder` (AD-5). Every new or changed persistent and message class commits its compiler-generated `Storage` block.
- **The waiter's own trace session (AD-26).** Before the start, `ReminderOps` clears `..%SessionId` and sets `..%SuperSession` to the session row's `TraceRef`. After the start it restores both, and also the job's session id if Task 0 shows that it moves. So the waiter's session begins at its start header, and `ReminderOps`' answer stays in the command's session.
- **The row keeps the waiter's header id (AD-18, AD-26).** Before it answers the start, the waiter writes its `%PrimaryRequestHeader` id to the new `Reminder.TraceHeaderId`. `Live.Payload.Reminder.FromRow` carries that id, with `TraceNamespace` = `$Namespace` when the id is set. `/state` and the events then get `traceUrl` from `Web.TraceLink` with no further code.
- **Firing.** The waiter opens the row with an exclusive lock (`RefIndexOpen(ref, 4)`). Then:
  - A missing or non-pending row ends the waiter, and nothing is sent.
  - A wake before `DueAt` sets the timer again for the remaining time.
  - Otherwise the waiter sets `State` to fired and `Late` = (`Seconds(now)` - `Seconds(DueAt)` > 10), and saves the row. It sends one `Notification` to `Notify`: `SessionRef`, `Kind` reminder, and either `reminder.due` with `Slots` `{"text","dueAt"}` or, when late, `reminder.late` with `{"time","text","dueAt"}`, where `time` = `dueAt`. It then releases the lock and publishes the fired event.
- **Events.** Events go out only through `Live.Publish`, after the commit. `ReminderOps` publishes created and `ReminderTimer` publishes fired (AD-12, AD-33). The payload is `FromRow`.
- **Times and text.** Times go only through `Data.Time` (AD-18). Nothing in Schedule renders text (AD-32).
- **Tests.** Tests go in `OcuTalon.Test.Schedule` (shard `lane-b`). Tests that need a running production run on throwaways only (AD-22, Rule 21). Each test creates, and removes, everything it asserts on.

**Never:**
- No edit to `CommandsIn`, `Commands`, `Notify`, `WebChatOut`, `SimPhoneOut`, `Production.cls`, the catalog classes or `web/src/**`. No edit to any contended path beyond the one escalated line of `Test/Data/Tables.cls` (see Clarification Needed). No change to `web/e2e/demo-path/03-reminder.spec.ts`: its `notBuilt(..., '8.4')` stays.
- Story 8.4 owns `DelaySeconds`, `LocalDueAt`, list, cancel, refusal reasons and repeat handling by `IdempotencyKey`. Story 8.5 owns `Reconcile`, re-arming and restarts. None of it is done here.
- No live send to `TelegramOut`, a disabled stub until Epic 12. The paired route is checked on `Notify`'s own rule.
- Nothing new in the catalog, no new live-event type, production item or table, no second publisher of `reminder`, no hand-written `Storage` block, and no literal non-ASCII character in code (Rule 14).
- CI never asserts seconds beyond order (never before `DueAt`) and outcome (NFR-10).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Set | `SetReminder` with Text and a future UTC `DueAt` only, under a bridge context | One pending row (`Ref` from `NewRef`, `SessionRef`, Text, `DueAt`, `Late` 0, `CreatedAt`, `TraceHeaderId`). One waiting waiter. One `reminder` event (pending, with the trace target). `CommandResult` Ok 1, `Outcome` `set`, `Ref`, `DueAt`, Message "The reminder is set." | none |
| Not handled yet | `DelaySeconds` or `LocalDueAt` set, both, none, empty Text, unreadable or past `DueAt`, unknown session; `ListReminders`, `CancelReminder` | `$$$NotImplemented`, so `CommandsIn` answers `0\|not_built` with its text. No row, waiter or event. | none (Story 8.4) |
| Waiter won't start | the start fails or gets no answer within `STARTSECONDS` (10) | The row is deleted. `Ok` 0, `failed`, `CommandsIn.#MESSAGEFAILED`. No event. | error logged |
| Created event fails | `Publish` errors | Warning logged. The answer is still Ok, and the row and waiter stay. | warning |
| On time | wakes within 10 s after `DueAt` | Fired, `Late` 0, `reminder.due` `{"text","dueAt"}` | none |
| Late | wakes more than 10 s after `DueAt` (10 s itself is on time) | Fired, `Late` 1, `reminder.late` `{"time","text","dueAt"}` | none |
| Early wake | wakes before `DueAt` | Timer set again for the rest; nothing sent | none |
| Not pending | row cancelled, fired or deleted | The waiter ends; no Notification, no event | none |
| Channels, demo on, unpaired | the stacks' default | `Notify` sends to `WebChatOut` (one web card) and `SimPhoneOut` (one phone message), and nothing to `TelegramOut` | none |
| Paired | fixture `Pairing` and `^OcuTalonTest("TelegramIncluded")` = 1 | `Notify`'s rule on the waiter's Notification gives `send:WebChatOut,SimPhoneOut,TelegramOut:`; without the pairing, `send:WebChatOut,SimPhoneOut:` | none |
| Send fails | `SendRequestAsync` to `Notify` errors | Error logged with the Ref; the row stays fired | error logged |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls`, `ReminderTimer.cls`: stubs with `STUB = 1`. `ReminderTimer`'s `Storage` holds only `<Type>`.
- `src/ocutalon/cls/OcuTalon/Data/Reminder.cls`: 7 properties, storage slots 1-8 and `RefIndex`. It gains `TraceHeaderId`; the compiler appends slot 9.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Reminder.cls:26-36` `FromRow`: its doc says "no trace of its own". `TraceHeaderId` and `TraceNamespace` already exist in the payload, so `web/src/app/live/payloads.ts` does not change.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls`:
  - `:30` `TOOLVERBS`; `:48` `MESSAGENOTBUILT`; `:50` `MESSAGEFAILED`;
  - `:119` `Join`, which puts the command in the thread session inside a context;
  - `:145` `IsStub`, which maps code 5003 to `not_built`;
  - `XData Routes`, where `SetReminder` goes to `ReminderOps`. Read only.
- `src/ocutalon/cls/OcuTalon/Core/Commands.cls` `Submit`: forces origin `tool` inside a context. Read only.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls:37-48,151`: the owner pattern to follow (`OnMessage` Try/Catch, `Carry`, private `Result`). Read only.
- `src/bridge/cls/OcuTalon/Bridge/Process/ApprovalHold.cls` and `Bridge/Approval.cls:551-617` (`Hold`, `HoldResponse`, `LiveHold`/`IsLive`); `Bridge/Service/ApprovalStart.cls`: the frozen-waiter pattern and its synchronous start (the hold calls `Reply` once its timer is set). Read only.
- `irislib/Ens/BusinessProcess.cls:86,97,189,1003` (`%PrimaryRequestHeader`, `%IsCompleted`, `SetTimer` (an `Ens.AlarmRequest` to `Ens.Alarm`), `Reply`); `irislib/Ens/BusinessOperation.cls:396,713-723` (the BO answers through `pRequestHeader.NewResponseMessage(..., ..%SuperSession)`; `SendRequestSync` passes `..%SessionId` by value). Reference only.
- `src/ocutalon/cls/OcuTalon/Core/Rule/Notify.cls` and `Functions.cls` (`DemoOn`, `TelegramOn`, `TelegramPaired`): every kind except `pairing` and `allowance` goes to `WebChatOut`, to `SimPhoneOut` in demo mode, and to `TelegramOut` when the session is paired. No change. `Channel/Telegram/Out.cls` is a stub and is disabled in `Production.cls:17`.
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls:21,52`: renders card kinds and keeps the `dueAt` slot on the web `Delivery` row. `Channel/SimPhone/Out.cls:20`: one `SimMessage` plus a phone `Delivery` row (no `DueAt`). Read only.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls:252-266`: `reminder.due` (`text`: sentence) and `reminder.late` (`time`, `text`). `Msg/Catalog.cls:23`: a slot that a key doesn't declare is ignored. `Msg/Notification.cls`; `Msg/Command/SetReminder.cls`; `Msg/CommandResult.cls` (`Ref`, `DueAt`, `Outcome`, `Message`).
- `src/ocutalon/cls/OcuTalon/Live/Publish.cls` `Publish(stream, "reminder", payload, .seq)`: refused inside a transaction. In demo mode it refreshes the guide after `reminder` events.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls:478-525` `StateBody` (`RailBody` pushes `FromRow` for pending rows; `TraceLink.Add` at `:523`); `Web/TraceLink.cls:41` `Url`, which gives `/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=<id>`.
- `src/ocutalon/cls/OcuTalon/Data/Time.cls:18,27,42` (`NowUtc`, `Seconds`, `AddSeconds`); `Data/Ownership.cls:267,274` (`RecentNotices`, `RecentPhone`).
- `src/ocutalon/cls/OcuTalon/Tools/ReminderTools.cls` `SetReminder`: sends only `DelaySeconds` or `LocalDueAt`, never `DueAt`. So no tool reaches this story's set path, and the tools still get `not_built`.
- Test helpers (read and call only, never edit):
  - `Test/Core/InProduction.cls`: the base class (`Guard`, `Session`, `Supers`, clean-up).
  - `Test/Core/Observe.cls:16,46,64` (`DeliveryRows`, `Events`, `WaitProcessed`).
  - `Test/Data/Fixture.cls`: `Session` `:19`, `SetTelegramIncluded` `:179`, `Pairing` `:230`, `Adopt` `:271`, `Clean` `:331`, `RemoveMessages` `:365`, `Headers`/`SessionHeaders`/`Between` `:427-460`.
  - `Test/Core/Routing.cls:393-403` `Route`: a private rule evaluator to copy.
  - `Test/Core/RoutingProduction.cls` and `Test/Demo/SimPhoneOut.cls:293-342`: the patterns for waiting on hops.
- Existing tests that must stay green without edits:
  - `Test/Core/CommandsInProduction.cls:31-58,100-155`: a `SetReminder` with no due form still gets `not_built` and an error response header, and `ListReminders` is unchanged.
  - `Test/Install/Production.cls:136-171` `TestStubsAnswer`: reads the oracle's `stub` flags.
  - `Test/Live/Payloads.cls:376-385`: a row with no header id has "no trace".
  - `Test/Web/Api.cls`, `Test/Demo/Guide*.cls` and `web/e2e/rail/rail.spec.ts` R6/R7: fixture rows with no waiter.
  - `Test/Tools/Reminders.cls`: a double stands behind `CommandsIn`.
- `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls:35`: the `ReminderTimer` row (Epic 8's), `"stub": 1`.
- `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls:431-445`: the exact contract of `OcuTalon.Data.Reminder` (`AssertContract`, "has exactly its contract"). It is contended (see Clarification Needed).
- Web support, used only through its exports:
  - `web/e2e/support/iris.ts` (`irisScript` `:71`, `chk` `:89`, `quoted` `:144`, `fixtureUser` `:47`);
  - `support/trace.ts` (`TRACE_PAGE` `:14`, `signOutTrace` `:44`, `openTrace` `:126`, `drawnMessages` `:143`);
  - `support/floor.ts` (`rowOf`, `unique`);
  - `sign-in/helpers.ts:60` `signIn`.
- Patterns in other specs: `rail/rail.spec.ts:297` is the notice-card locator `main app-notice-card`. `web/src/app/rail/status-rail.ts:116` renders `app-trace-link` in a row whose payload has `traceUrl`.
- `ci/units.sh`: `Schedule` is already a `lane-b` area. `src/module.xml` loads by package. Neither needs an edit.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (implement stage, warm throwaway; record each result under Design Notes as measured or (inference)):
  - (a) A `ReminderOps` `SendRequestSync` to `ReminderTimer` with `..%SessionId` "" starts a session whose id is the start header's id. After `%SessionId`/`%SuperSession` are restored, the BO's answer header to `CommandsIn` is in the command's session. Record whether `$$$JobSessionId` moves and needs restoring.
  - (b) Whether `SetTimer(n)` ever wakes before n seconds (for the early-wake rule).
- [ ] `src/ocutalon/cls/OcuTalon/Data/Reminder.cls`: add `Property TraceHeaderId As %Integer;` with a doc line (the start header of the reminder's waiter; its trace link's target; AD-18, AD-26). Commit the storage block the compiler generates (slot 9 appended). This is AD-18's "the row keeps its waiter's trace header id".
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/ReminderStart.cls` (new, `Extends Ens.Request`): the start request of one waiter. `Property Ref As %String(MAXLEN = 22)`, plus its generated storage block.
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/Reminder.cls` (new): the reminder logic, where the frozen waiter keeps it (AD-5).
  - Pure methods:
    - `Accepts(command, now)`: the "carries out" rule.
    - `SecondsUntil(dueAt, now)`: at least 1.
    - `IsLate(dueAt, now)`: `LATESECONDS` = 10, strictly more.
    - `Notification(row, late)`: builds the message, never saves it.
  - `Start(timer, request, .response)`: sets `timer.Ref`. For a pending row it writes `TraceHeaderId` = `timer.%PrimaryRequestHeader.%Id()`, calls `SetTimer(SecondsUntil, TIMERKEY "due")`, then `Reply(Ens.Response)`. For any other row it only replies.
  - `Wake(timer, completionKey)`: the firing rule of the Always list. Logs one error, naming the Ref, when the send fails.
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/ReminderTimer.cls`:
  - Delete `STUB` and the stub handler.
  - Add `Ref`. `OnRequest` calls `Reminder.Start` and `OnResponse` calls `Reminder.Wake`.
  - Commit the generated storage block (data node `"ReminderTimer"`, `Ref`).
  - Class doc: frozen, one waiter per reminder.
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls`:
  - `OnMessage`: when `Reminder.Accepts` holds and the session row exists, run a Try/Catch `Set`, whose throw logs and answers `failed`. Otherwise `Quit $$$ERROR($$$NotImplemented)`.
  - `Set`, in order:
    1. Save the row.
    2. Call the private `StartWaiter(row)`: the session trace rule of the Always list, `SendRequestSync("ReminderTimer", start, .response, STARTSECONDS = 10)`. On an error or no answer, delete the row and answer `failed`.
    3. Reopen the row and publish created; a failed publish is a warning.
    4. Answer `Ok` 1, `set`, `Ref`, `DueAt`, "The reminder is set."
  - Keep `STUB` (Story 8.4 deletes it), and update the class doc to what is built.
- [ ] `src/ocutalon/cls/OcuTalon/Live/Payload/Reminder.cls` `FromRow`: set `TraceHeaderId` from the row, and `TraceNamespace` = `$Namespace` only when it is set. Correct the doc (contract only).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls`: the `ReminderTimer` row gets `"stub": 0` (Epic 8's row). `ReminderOps` stays `1`.
- [ ] **Contended, awaiting the ruling below:** `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls`, XData `Contracts`, `OcuTalon.Data.Reminder` props: add `"TraceHeaderId": "%Integer"` after `"CreatedAt"`. No other line.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderOpsProbe.cls` (new): a `ReminderOps` subclass whose `StartWaiter` answers an error.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderLogic.cls` (new, no production):
  - `TestAccepts`: each matrix input.
  - `TestTimes`: `SecondsUntil` at the past, now, +1 and +5; `IsLate` at -5, 0, 10 and 11 s.
  - `TestNotification`: the exact `Kind`, `CatalogKey` and `Slots` JSON, on time and late, and `Catalog.RenderAt` of each for `web`.
  - `TestStartFailureKeepsNothing`: a probe shadow instance gets a valid `SetReminder` for a fixture session. The answer is `0|failed` with `MESSAGEFAILED`, and there is no row and no event.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderFixture.cls` (new; no Test methods; the product never refers to it):
  - `Set(sessionRef, text, seconds)`: begins a bridge context (`OwnerRef`, `SuperSession` = `TraceRef`), submits `SetReminder` (`IdempotencyKey` `zzrem<n>`, `DueAt` = `AddSeconds(NowUtc, seconds)`) with origin `tool`, ends the context, and returns `{ok, outcome, ref, dueAt, traceHeaderId, alarmHeaderId}`. `alarmHeaderId` is the `ReminderTimer` to `Ens.Alarm` request in the waiter's session.
  - `Remove(ref)`: deletes the row; the session's web `Delivery` rows of kind reminder with its `DueAt`; its phone `Delivery` rows of kind reminder recorded since `CreatedAt`, with their `SimMessage`s; the waiter session's headers with their bodies and event-log and rule-log rows; and the `ReminderTimer` instances with that `Ref`.
  - One fixture serves the unit tests and the browser spec.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/Reminders.cls` (new, `Extends OcuTalon.Test.Core.InProduction`; throwaways and CI only):
  - Clean-up: `OnAfterOneTest` runs `ReminderFixture.Remove` on its reminders and restores `TelegramIncluded`.
  - `TestSetAndWaiting` (AC 1, AC 2): due in 12 s. Checks:
    - the result, the row and the created event;
    - the start header: id = row `TraceHeaderId` = its `SessionId`, source `ReminderOps`, `SuperSession` = `TraceRef`, body `ReminderStart` with the `Ref`;
    - the `Ens.Alarm` request in that session;
    - the instance is live (not completed, pending responses > 0);
    - `ReminderOps`' answer header is in the command's session;
    - `StateBody(session).rail.reminders` holds the reminder with `traceUrl` = `/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=<id>`.

    Then the test sets the row's `State` to cancelled, waits for the instance to complete, and asserts no `ReminderTimer` to `Notify` header and still only one `reminder` event.
  - `TestFiresOnEveryChannel` (AC 3, AC 4): due in 5 s; wait for the instance to complete, at most 30 s. Checks:
    - the row is fired, and `Late` agrees with the Notification's key;
    - one `ReminderTimer` to `Notify` header, created no earlier than `DueAt`, with the exact `Kind`, key, `Slots` and `SessionRef`;
    - `Notify` to `WebChatOut` 1, to `SimPhoneOut` 1 (demo mode asserted on), to `TelegramOut` 0, all processed;
    - exactly one web card (`RenderAt` web text, `DueAt`, recorded no earlier than `DueAt`), one `SimMessage` (phone text), one `notification` event, one `phone` event, and `reminder` events pending then fired.

    Then, with `SetTelegramIncluded(1)` and a fixture `Pairing`, a copy of `Routing.Route` on that Notification's body gives `send:WebChatOut,SimPhoneOut,TelegramOut:`, and `send:WebChatOut,SimPhoneOut:` without the pairing.
- [ ] `web/e2e/reminder/reminder.spec.ts` (new; project `chromium`, run by `live:sign-in`): one test, 90 s timeout, `test.use({ timezoneId: 'UTC', locale: 'en-GB' })`, as the rail user.
  1. `irisScript` `ReminderFixture.Set` for the user's `ForUser` session, a `unique` text, 25 s.
  2. `signIn`. Within 15 s, `rowOf(page, text)` shows, and its `app-trace-link a` href is `TRACE_PAGE + traceHeaderId`.
  3. In a new browser context, `openTrace` as `LINKS`. `drawnMessages` contains the start and alarm header ids. Then `signOutTrace` and close the context.
  4. By `DueAt` + 20 s, the row is gone and one `main app-notice-card` reads `Reminder: <text>.`
  5. `test.afterEach` runs `ReminderFixture.Remove`.

  This is the real-runtime test (Rule 3). It reads no environment variable at import.

**Acceptance Criteria:**
1. **Set.**
   - Given the running production and a session, when a test under a bridge context submits a `SetReminder` with Text, `IdempotencyKey`, `SessionRef` and a `DueAt` 12 s ahead through `Commands.Submit`, then the `CommandResult` is `Ok` 1 with the reminder's `Ref` and `DueAt`, and the session has exactly one pending `Reminder` row with those values and one `ReminderTimer` waiter.
   - One `reminder` event (pending) is published. `Web.Api.StateBody` lists the reminder under `rail.reminders`.
   - In the rail user's page, the reminder's row shows in Reminders from that real data. (FR-34, AD-1, AD-5, AD-12, AD-18)
2. **Visual Trace.**
   - Given that pending reminder, when its waiter's messages are read and its rail row's trace link is opened in Visual Trace by a trace-role user, then its start header is the first header of its own session: `SuperSession` = the session's `TraceRef`, its `Ens.Alarm` request is pending, and the instance is live.
   - The row's `TraceHeaderId` is that header. The rail row's trace link opens `EnsPortal.VisualTrace.zen?SESSIONID=<that id>`.
   - The page draws the start and the timer messages. (FR-34, NFR-20, AD-26, UX-DR139)
3. **Firing.**
   - Given a pending reminder, when its due time arrives, then the waiter marks the row fired, `Late` only beyond 10 s, and sends one `reminder` Notification with `reminder.due` (or `reminder.late`) and the UTC slots. It publishes `reminder` (fired), so the row leaves the rail, and the page shows the notice card `Reminder: <text>.`
   - `Notify` sends it to `WebChatOut` and, in demo mode, to `SimPhoneOut`. With a fixture pairing and Telegram included, `Notify`'s rule routes the same Notification to `TelegramOut` too.
   - A waiter whose row is no longer pending sends nothing. (FR-34, AD-14, AD-18, AD-32, UX-DR18)
4. **The 5-second test.** Given a reminder due 5 s after it is set, when the test waits for it, then exactly one notification arrives per channel: one web card, one phone message, and `TelegramOut` once in the paired route. None of them is created before `DueAt`. No seconds bound is asserted. (FR-34, NFR-10)

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs:**
- AD-1: commands through `Submit` and `CommandsIn`; a `CommandResult` answer; origin `tool` under a context.
- AD-5: the row is the truth; the frozen waiter (append-only, logic elsewhere); committed storage blocks.
- AD-12: full-view payloads after commit; trace targets as `TraceHeaderId`/`TraceNamespace`.
- AD-14 and AD-32: `Notify` routes by kind and the session's channels; producers never render; the `dueAt` slot.
- AD-18: a `Reminder` row plus one `ReminderTimer` on `SetTimer`; late beyond 10 s; the row keeps its waiter's header id; `Data.Time`.
- AD-22: Schedule tests in `lane-b`, on throwaways.
- AD-26: a waiter's own session (clear `%SessionId`, keep `SuperSession` = `TraceRef`); a trace link carries `SESSIONID`.
- AD-29: Lane B's files; the 8.4 and 8.5 split.
- AD-33: one publisher per event phase; Lane B owns `Reminder`.

Conventions: "Times", "Live events", "Notice cards", "Identifiers".

**Integration ACs:**
- AC 1: `CommandsIn` gets `ReminderOps`' `CommandResult`, and the rail of `/state` and the page reads the row.
- AC 2: Visual Trace reads the waiter's headers.
- AC 3 and AC 4: `Notify`, `WebChatOut` and `SimPhoneOut` read the waiter's Notification; the page's chat reads the card.

**Consumes:**
- `Commands.Submit`/`CommandsIn` (Story 2.3); `Notify` (2.7, 4.5); `WebChatOut` (2.7); `SimPhoneOut` (4.5).
- `Catalog` keys `reminder.due` and `reminder.late` (0.9); `Live.Publish` and `Payload.Reminder` (0.4, 0.5); `Web.TraceLink` (2.9, 2.13); `Data.Time`; `Bridge.Ids`.
- Tests only: `Bridge.Context`, `Test.Core.InProduction`, `Test.Data.Fixture`, `Test.Core.Observe`, the e2e support helpers.

**Consumed-by:**
- Story 8.4: list, cancel, `DelaySeconds`/`LocalDueAt`, refusals and repeats. Its cancel relies on "a waiter whose row isn't pending sends nothing" and on the same row lock.
- Story 8.5: `Reconcile` starts waiters through `ReminderStart`/`ReminderTimer`; the waiter stores its own new header id; late after restart uses this story's late key.
- Story 16.4: sign-out cancels through 8.4.
- Story 11.1: the demo path with step 2 on.

**Extend, don't copy:**
- `ReminderTimer` and `Schedule.Reminder` follow `ApprovalHold` and `Bridge.Approval` (one stored `Ref`, two delegating methods, `SetTimer`, an early `Reply`). The start follows `ApprovalStartIn`'s synchronous start. The logic differs, so no code is copied.
- `ReminderOps` follows `SettingsOps`. Its private `Result` is a 6-line copy that every owner keeps (as `CommandsIn` and `SettingsOps` do), because the siblings' helpers are private in shared Core files.
- The rule evaluator in `Test.Schedule.Reminders` copies `Test.Core.Routing.Route` (10 lines), a private method of a contended Epic 2 test class.
- `ReminderFixture.Remove` has no sibling: no existing helper cleans up one product-made reminder in a real user's session.

**Decided in-stage:**
1. The handled set (Always) answers everything else exactly as the stub does, so `CommandsInProduction`, `Test.Tools.Reminders` and the tools' `not_built` answers stay unchanged until Story 8.4.
2. AD-1's repeat rule lands with Story 8.4's AC. No tool reaches this story's set path, because `set_reminder` never sends `DueAt`.
3. `ReminderOps` keeps `STUB` (only part of it is built), and Story 8.4 deletes it along with its oracle row. `ReminderTimer` is built here, so its row becomes `stub: 0`.
4. The start is synchronous (`STARTSECONDS` 10), and the waiter writes its own header id. So the created event already carries the trace target, and Story 8.5's re-armed waiter does the same. A failed start deletes the row, so the user is never told "failed" about a reminder that later fires.
5. Success is `Outcome` `set` with the model-facing Message "The reminder is set.", which `CommandCall.Answer` passes to the model and never shows to the user as written. It is reversible in Story 8.4.
6. This story already sends `reminder.late` (`time` = `DueAt`) when `Late`, so the row and the text never disagree. Story 8.5 proves it after a restart.
7. An early wake sets the timer again, so "never before due" doesn't depend on `Ens.Alarm`'s precision. `SecondsUntil` is at least 1 s.
8. Order when firing: under the lock, mark and save, then send, then release, then publish. A failed send is logged and not retried; a retry would risk firing twice, which Story 8.5's guarantee forbids.
9. The Telegram route is checked on `Notify`'s rule against the waiter's real Notification, with a fixture `Pairing` and the test switch. A live route would reach the disabled `TelegramOut` stub, whose queueing behaviour is unmeasured. This is the smallest honest check until Epic 12.
10. `ReminderStart` lives in `OcuTalon.Schedule`: it is internal to the area, not a cross-lane contract.
11. The browser spec is a new folder, `web/e2e/reminder/`. The page uses the rail user: only `rail.spec` reads that user, and it runs earlier in path order. The trace application uses the links user only, and it is signed out after.
12. Expected cost of the browser spec: about 35 s added to `live:sign-in`, which was about 461 s against its 540 s deadline (inference until measured).

**Footprint extensions to report:** `src/ocutalon/cls/OcuTalon/Live/Payload/Reminder.cls` (Lane B; contended by no running epic) and the new `web/e2e/reminder/reminder.spec.ts`.

**Contended edit needed:** `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls`, one line (see Clarification Needed).

**Ledger inbox:** none (`LEDGER slice` of this key is empty).

## Verification

**Shared values.** Every `ci/iris.sh` and `ci/warm.sh` call starts with `L` = `OCUTALON_LOCK_DIR=/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/.coordination/locks/lane-c OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=8 stage=<stage>'`, written out in full on each call. Each call is its own tool call, in the foreground, with `timeout: 600000`. Tags: fresh `e8s3i` and warm `e8s3iw` for implement; every other stage uses `e8s3<stage>` and `e8s3<stage>w`.

**Commands:**
- `(once, first)` `OCUTALON_LOCK_DIR=/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/.coordination/locks/lane-c OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=8 stage=implement' OCUTALON_RUN_TAG=e8s3iw ci/warm.sh up` -- expected: ready.
- `(loop)` `$L OCUTALON_WARM=1 OCUTALON_RUN_TAG=e8s3iw ci/iris.sh class OcuTalon.Test.Schedule.ReminderLogic` -- expected: `CLASS ... passed`.
- `(loop)` the same command for `OcuTalon.Test.Schedule.Reminders` (about 30 to 60 s) -- expected: passed.
- `(loop)` the same command for each of these, one per call: `OcuTalon.Test.Install.Production`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Core.CommandsInProduction`, `OcuTalon.Test.Web.Api` -- expected: each passed.
- `(loop)` `npm --prefix web run lint` -- expected: exit 0.
- `(once)` `$L OCUTALON_RUN_TAG=e8s3i ci/iris.sh build`, then `shard lane-b`, `shard lane-b --reverse`, `shard lane-a`, one per call -- expected: every `CLASS` line passed.
- `(once)` `$L OCUTALON_RUN_TAG=e8s3i ci/iris.sh live sign-in` (record the time; the local deadline is 540 s) -- expected: passed, with `reminder.spec.ts`.
- `(once)` `npm --prefix web test`, then `bash ci/checks.sh` (storage blocks included) -- expected: pass.
- `(once, last, also after a failure)` `$L OCUTALON_RUN_TAG=e8s3iw ci/warm.sh down`, then `$L OCUTALON_RUN_TAG=e8s3i ci/iris.sh teardown`.

**Mutations (Rule 19).** Record each one as `mutation: <change> -> <red test>`. To be observed:
- AC 1: `ReminderOps` skips the created publish -> `Reminders.TestSetAndWaiting`.
- AC 2: `Reminder.Start` writes no `TraceHeaderId`, or `ReminderOps` keeps `%SessionId` -> `TestSetAndWaiting`, and `reminder.spec.ts` for the link.
- AC 3: `Wake` ignores `State`, or `IsLate` uses `>=` -> `TestSetAndWaiting` and `ReminderLogic.TestTimes`.
- AC 4: the waiter fires on its first wake and is armed for 1 s -> `TestFiresOnEveryChannel` (created before `DueAt`). A second send -> `TestFiresOnEveryChannel` (two cards).
- The Telegram route: the Notification without `SessionRef` -> the paired route check.

**Shared surfaces:**
- the `Data.Reminder` contract (`Test.Data.Tables`, pending the ruling);
- the `ReminderTimer` oracle row (`Test.Install.Production.TestStubsAnswer`);
- `FromRow`'s trace fields (`Test.Live.Payloads`, `Test.Web.Api`; a row with no header has no trace);
- the rail user's reminders and cards (`rail.spec` runs first; `Remove` deletes this spec's own);
- the trace application's licence connections (signed out);
- `live:sign-in`'s run time;
- the throwaways' `ReminderTimer` instances and `Ens.Alarm` headers (removed).

The demo-path summary is unchanged.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Clarification Needed

**Story 8.3 needs one edit to a contended path.**

- **Why.** AD-18 ("The row keeps its waiter's trace header id") and AD-26 (rows that a link targets store the header id it needs, including the reminder waiter's) require a new property, `OcuTalon.Data.Reminder.TraceHeaderId As %Integer`. Epic 0's `Data.Reminder` has no such property.
- **The conflict.** `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` is a contended existing file (`Test/{Core,Live,Web,Data}/**`). Its XData `Contracts` pins the Reminder table exactly ("has exactly its contract", `:431-445`), so `TestContracts` goes red without a line there. An appended block can't change that entry.
- **Alternatives tried.**
  - Deriving the header from `Ens.MessageHeader` would contradict AD-18's Rule and would be lost to the message purge.
  - The existing properties can't hold it.
  - Leaving it out would drop AC 2's trace link.
- **Requested ruling.** Allow exactly one added line, `"TraceHeaderId": "%Integer"`, in the `OcuTalon.Data.Reminder` entry of that XData. That entry is the contract of Epic 8's own table.
- **Possible veto item.** This also adds a stored property: append-only under AD-5, and already required by the spine, but the lead should classify it.

Everything else in this spec is ready for development.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: Story 8.3 needs Data.Reminder.TraceHeaderId (AD-18, AD-26: the row keeps its waiter's trace header id), and the contended file src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls pins the Reminder contract exactly (XData Contracts, lines 431-445), so the story needs one added line there ("TraceHeaderId": "%Integer" in the OcuTalon.Data.Reminder entry), an edit beyond an appended block; requested ruling: allow that one line (Epic 8's own table's entry). Also a stored-property addition the spine already mandates (AD-5 append-only), for the lead to classify.
