---
title: 'Story 8.6: Reminders through the chat on the demo path'
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

**Problem:** Story 8.4 built the command side: `ReminderOps` sets by `DelaySeconds`/`LocalDueAt`, lists, cancels and answers repeats. Nothing yet proves this through the chat. No CI-mock scenario covers "Thursday at 10" or a cancel by `Ref`. REL-2's reminder step (`web/e2e/demo-path/03-reminder.spec.ts`) is still `notBuilt(..., '8.4')`. And the step summary's unit test stays green for a step spec that starts a browser before it skips (DW-210).

**Approach:** Drive real chat turns against the CI mock and show the results on the page.
- **Scenarios.** Two new marker scenarios under `ci/mock/scenarios/B/`:
  - `reminder-thursday`: a `localDueAt` of the fixed Thursday `2030-11-07T10:00:00`;
  - `reminder-cancel-chat`: lists, then cancels by a fixed `Ref`.
  - The guide prompt keeps Story 4.4's `B/guide-reminder.json` unchanged (DW-232).
- **Fixed Ref.** The cancel scenario's Ref is fixed. A test subclass behind the `ReminderOps` item hands out that Ref, through a one-line `NewRef()` seam in `ReminderOps`.
- **IRIS tests.** `OcuTalon.Test.Schedule.ReminderChat` sends turns through `WebChatIn`, the REST surface's own entry, to the real Conversation, Chat, tools and `ReminderOps`.
- **Browser tests.**
  - `03-reminder.spec.ts` is turned on: the README account presses Send on guide step 2.
  - A new `web/e2e/reminder/chat.spec.ts` sends the Thursday and cancel messages through the page's composer.
- **DW-210.** `playwrightEnv()` gets a browsers path that holds no browser.

## Boundaries & Constraints

**Always:**
- **The real path.** Every chat-side test goes through the product's own path: `WebChatIn` or the page's `POST /messages`, then Conversation, then Decide, ChatAgent and Story 1.10's tools, then `Commands.Submit`, `CommandsIn` and `ReminderOps`.
  - The page tests use the real page and the real rail.
  - The CI mock scripts the model. No test reaches a real model API (`RunnerFixture.GuardReason`).
  - Keys are pointed at `OCUTALON_MOCK_KEY_HEADER` (`PointKeys`) and put back on every path (`RestoreKeys`).
- **Ownership.** `ReminderOps` stays the one owner of the `Reminder` table (AD-33). Its behaviour does not change. Its only change is the private seam `NewRef()`, which returns `Bridge.Ids.NewRef()`.
- **The test subclass.** `ReminderOpsFixedRef` sits behind the `ReminderOps` item only:
  - for the duration of `ReminderChat`, put back in its `OnAfterAllTests`;
  - for the duration of `chat.spec.ts`, put back in its `afterAll`.
- **Scenario names.** The two new files are marker scenarios whose names nothing else uses. The guide prompt is served only by `B/guide-reminder.json` (DW-232). The loader refuses a repeated prompt.
- **Spec 03** has one test. It is not tagged `@floor`.
  - It skips at describe level, before any hook or fixture starts, when `OCUTALON_URL` is not set. The skip text starts with `Story 8.6`.
  - Its hooks start no browser.
  - Its `afterAll` cancels the README session's pending reminders through the product's cancel path, then puts the keys back.
- **Tests.**
  - IRIS tests run on throwaways and in CI only (AD-22, Rule 21), in shard `lane-b`.
  - Each test creates and removes what it asserts on: rows, waiters, turns, decisions, steps, AI sessions and the item class.
  - No literal non-ASCII character in code (Rule 14): write the middle dot as the escape `\u00B7`.
  - No seconds are asserted beyond bounded waits for order and outcome (NFR-10).
- **No local absolute path** in any committed file (`test-boundaries.sh`).

**Never:**
- Don't edit `Agent/**` (`Agent/Chat.cls` included), `Tools/**`, `src/bridge/**`, `Test/Tools/**`, `Test/Agent/**` or `Test/Bridge/**`. These are Lane A's (AD-29, AD-33). Call their helpers only. Chat needs no instruction line, because the mock scripts the model's reply.
- Don't edit `ci/mock/mock.mjs`, `ci/mock/scenarios.mjs`, the A scenarios, `ci/mock/test/**` or `B/guide-reminder.json`. Add no second scenario for "Remind me in 1 minute to stretch." (DW-232).
- Don't edit any other contended path: `web/src/**`, `web/e2e/demo-path/0{1,2,4,5,6}-*.spec.ts`, other epics' `web/e2e/**` specs and support files, the catalog, `Production.cls`, `Data/Ownership.cls`, or `docker/**` except the Q4 header lines.
- Don't change `ReminderTimer`, `ReminderStart`, `Schedule.Reminder` or any message, payload or event shape.
- Add no new table, index, production item, catalog key or public text.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Guide prompt (DW-232) | A session's chat message "Remind me in 1 minute to stretch.", typed (`ReminderChat`) or from the guide's Send (03) | `B/guide-reminder.json`, selected by prompt, makes Chat call `set_reminder` (text `stretch`, 60 s). Results: one pending row with key `<ItemId>:1`, a live waiter, one created event, the row in the rail, step 2 of the guide done, and the reply "The CI mock set the reminder." | The decide request also gets this scenario. Triage has no tools and ends in an `invalid` fallback triage decision, and the turn goes on (measured) |
| Thursday | "Remind me Thursday at 10 to load the new certificate. [[mock:reminder-thursday]]" | One pending row, "load the new certificate", `DueAt` = `Data.Time.FromLocal("2030-11-07T10:00:00")`. The reply is "The CI mock set the Thursday reminder." The row is in the rail | none |
| Cancel through the chat | Sessions A and B each have a reminder set by the guide prompt. A's Ref is `zzReminderChatCancel01`. A sends "Cancel my reminder to stretch. [[mock:reminder-cancel-chat]]" | `list_reminders` gives A's reminder only. `cancel_reminder` cancels it with key `<ItemId>:2`, and the waiter ends at once. One cancelled event, and the row leaves A's rail. The reply is "The CI mock cancelled the reminder." B is untouched | none |
| Demo path, step 3 | `live:demo-path`, README account, keys pointed, step 2 Send | The user message, the reply, a "stretch" row with a countdown, and "Step 2, Reminder, done". The `afterAll` cancels it | none |
| No stack (DW-210) | `npm --prefix web test`, no `OCUTALON_URL`, no browser available | 'skip every unbuilt part' reads `STEP 3 reminder: skipped, 0 passed, 1 skipped (Story 8.6: ...)` | A step spec that starts a browser before it skips fails the test |

</intent-contract>

## Code Map

Product (Epic 8's):
- `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls`:
  - `Set` `:109` calls `##class(OcuTalon.Bridge.Ids).NewRef()` inline. It becomes `..NewRef()`.
  - `StartWaiter` `:264-278` is the existing private seam that the probes override ("A test subclass overrides it."). The new `NewRef` follows the same pattern.

Mock (B is Epic 8's for new files; read the rest only):
- `ci/mock/scenarios/B/guide-reminder.json`: the prompt "Remind me in 1 minute to stretch.", then `set_reminder {"text":"stretch","delaySeconds":60}`, then the text "The CI mock set the reminder.". It is pinned by `Test.Demo.GuidePrompts` and `web/scripts/guide-view.test.mjs:216`.
- `ci/mock/scenarios/A/reminder-cancel.json`: the shape to mirror, with `list_reminders {}`, then `cancel_reminder {"reminderRef":...}`, then text.
- `ci/mock/mock.mjs:11-24`, the selection rules:
  1. a marker in the newest user message with text;
  2. else a B prompt contained in that message;
  3. else the mock key.

  The reply is `replies[min(k,last)]`, where `k` is the number of assistant messages after that user message. Inputs are copied verbatim, so a reply can't use a Ref from an earlier tool result.
- `ci/mock/scenarios.mjs:244-276`: names are unique across A and B, a marker equals the file's name, and a repeated or contained prompt is refused.

Test helpers (Epic 8's to extend):
- `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderFixture.cls`:
  - `Begin` `:17`, `Submit` `:29`, `Cancel` `:46` (`{ok,outcome,message,ref,dueAt,data}`) and `Set` `:61`;
  - `Remove` `:91` cancels a pending row first, waits for the waiter and deletes everything;
  - `Timers` `:133`, `IsWaiting` `:144`, `WaitEnded` `:153`.
- `ReminderOpsProbe.cls` and `ReminderOpsStartedProbe.cls`: subclasses overriding the private `StartWaiter`, the pattern for `ReminderOpsFixedRef`.
- `Test/Schedule/Reminders.cls`: the production-test pattern, with `OnAfterOneTest` `:51` removing by Ref, `EventStates` `:269` and `StateBody` rail reading `:171-180`.

Read only (call, never edit):
- `Test/Core/InProduction.cls` (abstract base):
  - `OnBeforeAllTests` `:36` and `OnAfterAllTests` `:52` (`RemoveMessages(Supers)`, `Fixture.Clean(Refs)`);
  - `Send(session, clientId, text, .output)` `:72` creates a `Channel.WebChat.Post` as the REST surface does, and has no `FromGuide` argument;
  - `WaitDone` `:85` (`..#WAIT`) and `Session(name)` `:100`.
  - `Test/Core/ConversationProduction.cls:57-61`: `OnAfterAllTests` adopts the turns with `Fixture.AdoptTurns(..Sessions, ..Refs)` before `##super()`; `:113-120`: the turn's trace session is the session of its Item header (`Turn.TraceHeaderId`).
- `Test/Agent/RunnerFixture.cls`:
  - keys: `ReadyReason` `:306`, `PointKeys` `:456`, `RestoreKeys` `:463`, `KeysAre` `:470` and `WaitRecords` `:168`;
  - the item class: `UseItemClass` `:645` and `RestoreItemClass` `:656` (saved `{"className"}`);
  - agent steps: `StepsOf(decisionRef)` `:335` (`kind`, `label`, `summary`, `status`, `id`) and `DeleteSteps(itemId)` `:349`;
  - AI sessions: `SessionMark` `:863` and `DropSince` `:870`;
  - the mock's log: `ToolNames(entry)` `:950` (it throws on an entry without `request`, so filter on `path` = `/v1/messages` first) and `ToolResults(entry)` `:969`.
- `Test/Contract/Mock.cls`: `LogMark` `:365` and `LogSince` `:378`. Entry fields are `path`, `selectedBy`, `scenario`, `marker`, `status`, `step` and `request`.
- `Test/Data/Fixture.cls`: `Session` `:19`, `Adopt` `:271`, `AdoptTurns` `:281`, `Clean` `:331`, `States`, `Headers` and `Between`. `Test/Core/Observe.cls:46`: `Events(session, type, count, seconds)`.
- `Test/Demo/GuidePrompts.cls`:
  - `Ready` `:111-120` removes today's `^OcuTalonBP.UsageCapped(...)` mark;
  - `OnAfterOneTest` deletes the Decision, Usage and AgentStep rows by `ItemId`.
- `Test/Tools/Reminders.cls:928-962` `AssertSteps` (private, Lane A's): the sibling of the step check. Tool step labels: "Setting a reminder", "Listing your reminders", "Cancelling a reminder".
- `Data/Turn.cls`: `State`, `ReplyText`, `FallbackReason`, `TriageDecisionRef`, `TurnDecisionRef`, `ItemId`, `TraceHeaderId` and `FromGuide`. `Channel/WebChat/Post.cls`: `SessionRef`, `ClientId`, `Text` and `FromGuide`. `Data/Ownership.cls`: `Reminders`, `Turns` and `TurnByClient`.
- `Web/Api.cls` `StateBody(session)`: `rail.reminders[]` (`ref`, `text`, `state`, `dueAt`) and `guide.steps[]` (`step`, `done`).
- `Agent/Chat.cls:14,18`: `TOOLSETS` `OcuTalon.Tools.Reminders` and `MaxIterations` 4. The cancel scenario makes 3 model requests (AD-20; DW-140 is Story 11.1's). `Agent/Triage.cls:13`: `TOOLSETS` is empty.

Web:
- `web/e2e/demo-path/03-reminder.spec.ts`: one `notBuilt(..., '8.4')` line (DW-303: 8.6 replaces it).
- `web/e2e/demo-path/02-watch.spec.ts:16-17`: the describe-level skip pattern, `'Story 8.2 needs the first-start stack (OCUTALON_URL), which a run without one lacks'`.
- `web/e2e/demo-path/01-page.spec.ts:9` holds `P2` (the exact prompt) and the guide locators (`:153-170`).
- `web/e2e/guide/guide.spec.ts`:
  - `:44` `stepName`: "Step 2, Reminder, upcoming|done";
  - `:272-281`: `app-user-message` with `.when` `/^From the demo guide/`;
  - the guide's Send sits outside `main`.
- Support helpers:
  - `support/devices.ts:152-161`: `pointKeys()` and `restoreKeys()`;
  - `support/iris.ts`: `irisScript`, `chk`, `quoted` and `fixtureUser('RAIL')`. On the demo-path stack, the container is found by `OCUTALON_URL`'s port;
  - `support/floor.ts:51-52`: `rowOf` and `replyOf(page, clientId)`;
  - `sign-in/helpers.ts`: `README_ACCOUNT` `:6`, `signInReadme` `:94` and `signIn` `:60`.
- `web/e2e/chat/chat.spec.ts:58-90`: the composer is `getByRole('textbox', { name: 'Message OcuTalon' })` plus the `main` Send button, and the POST body's `clientId` keys the reply. Its `sendWithEnter` is private to that file.
- Rail markup: `web/src/app/rail/status-rail.ts:93-101`, `li.row[data-row-key="reminders:<ref>"][data-section="reminders"]` with `.lead` and `.countdown`. The countdown words are in `web/src/app/chat/page-time.ts:179-196`: `in <n> s`, `in <n> min`, `in <h> h <m> min`.
- `web/scripts/demo-path-summary.test.mjs:331-337`: `playwrightEnv()`. `:339-363`: 'skip every unbuilt part'.
- `docker/tests/test-demo-path.sh:12-13`: "... no model key. No test sends a model request." (Q4).
- `web/playwright.config.ts`: the chromium project runs `web/e2e/reminder/**` in `live:sign-in`, alphabetically after `chat/` and `banners/`, before `session/`, `sign-in/` and `trace/`. `trace/links.spec.ts:185` expects the no-key fallback.

## Tasks & Acceptance

**Execution:**
- [ ] `ci/mock/scenarios/B/reminder-thursday.json` (new): `{"name":"reminder-thursday","match":{"marker":"reminder-thursday"},"replies":[...]}`. Reply 1 is `set_reminder {"text":"load the new certificate","localDueAt":"2030-11-07T10:00:00"}`; reply 2 is the text "The CI mock set the Thursday reminder." Each reply has status 200.
- [ ] `ci/mock/scenarios/B/reminder-cancel-chat.json` (new): marker `reminder-cancel-chat`. Replies: `list_reminders {}`, then `cancel_reminder {"reminderRef":"zzReminderChatCancel01"}`, then the text "The CI mock cancelled the reminder."
- [ ] `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls` -- add `Method NewRef() As %String [ Private ]` returning `##class(OcuTalon.Bridge.Ids).NewRef()`, with the doc "A new Ref for a reminder. A test subclass overrides it." `Set` calls `..NewRef()`. Nothing else changes -- the fixed-Ref seam (Decided 1).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderOpsFixedRef.cls` (new; `Extends OcuTalon.Schedule.ReminderOps`; class doc in the probes' style) -- AC 3's fixed Ref:
  - `NewRef()` override: if `^OcuTalonTest("ReminderOpsFixedRef","next")` holds a Ref, kill it and return it. Otherwise return `##super()`.
  - `ClassMethod Next(ref)`: sets that node.
  - `ClassMethod Use() As %Status`: `RunnerFixture.UseItemClass("ReminderOps", <this class>, .saved)`. It stores `saved.className` under `^OcuTalonTest("ReminderOpsFixedRef","className")`.
  - `ClassMethod Restore() As %Status`:
    - when a class is stored, `RestoreItemClass("ReminderOps", {"className": <stored>})`;
    - it always kills both nodes;
    - with nothing stored, it is `$$$OK`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderFixture.cls` -- add two methods and list them in the class doc:
  - `CancelPending(sessionRef) As %Integer`: cancels each Ref of `Ownership.Reminders(sessionRef)` through `Cancel`, letting the rows go first. It returns the number answered `1|cancelled`.
  - `RemoveAll(sessionRef)`: `Remove` for every `Reminder` row of the session, any state.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderChat.cls` (new; `Extends OcuTalon.Test.Core.InProduction`) -- AC 1 and AC 3 at IRIS level. `SESSIONPREFIX` is `zzprodchat` and `WAIT` 60. Header in the style of `Reminders`.
  - **Setup.** `OnBeforeAllTests`:
    - runs `##super()`, then `RunnerFixture.ReadyReason()`, `PointKeys()` and `ReminderOpsFixedRef.Use()`;
    - records the first failure in `Missing`;
    - flags what it changed, so that `OnAfterAllTests` puts back only that.
  - **Teardown.** `OnAfterAllTests`, on every path:
    - `..Refs = Fixture.AdoptTurns(..Sessions, ..Refs)`;
    - `ReminderOpsFixedRef.Restore()`;
    - `RestoreKeys()`, then `KeysAre(Provider #KEYPLACEHOLDER)` and `WaitRecords()`, each as a status;
    - `##super()`.
  - **Per test.** `OnBeforeOneTest` takes `RunnerFixture.SessionMark()` and kills today's `^OcuTalonBP.UsageCapped` mark (as `GuidePrompts.Ready` does). `OnAfterOneTest`:
    - `ReminderFixture.RemoveAll` for each run session, and `Remove("zzReminderChatCancel01")`;
    - kills the `next` node;
    - for each turn `ItemId` of the run's sessions, `DeleteSteps` and `DELETE` of `OcuTalon_Bridge_Data.Usage` by `ItemId`;
    - `DropSince(mark)`.
  - **Helper `Turn(session, clientId, text, .row, .chat)`:**
    - `Mock.LogMark()`;
    - `..Send(session, clientId, text, .output)`, a typed chat message through `WebChatIn`. The guide's own Send, with `FromGuide`, is 03's;
    - `row = WaitDone(...)`;
    - `chat` = the logged `/v1/messages` entries whose `ToolNames` is `cancel_reminder,list_reminders,set_reminder` (Chat's requests, not Triage's).
  - **Helper `AssertToolSteps(row, tools, labels)`** reads `StepsOf(row.TurnDecisionRef)`:
    - the kinds are `model` followed by `tool,model` for each tool;
    - each tool step has its label, a summary naming its tool and status `ok`;
    - no AgentStep header lies outside the turn's trace session (the session of `Ens.MessageHeader` `row.TraceHeaderId`).
  - **`TestGuidePromptSetsReminder`** (AC 1, DW-232). Session A sends `Turn("Remind me in 1 minute to stretch.")` between `before` and `after` (`NowUtc`). Then:
    - the turn is `done`, with `ReplyText` "The CI mock set the reminder." and no `FallbackReason`;
    - Chat made 2 requests, each `selectedBy` `prompt` with scenario `guide-reminder`;
    - A has exactly 1 row: `stretch`, pending, `IdempotencyKey` `<ItemId>:1`, `DueAt` within `[AddSeconds(before,60), AddSeconds(after,60)]`;
    - its waiter is waiting, and its events are `created`;
    - `StateBody` lists its Ref in `rail.reminders`, with step 2 `done: true`;
    - `AssertToolSteps` gives `set_reminder` / "Setting a reminder".
  - **`TestThursdaySetsLocalReminder`** (AC 1). `Turn("Remind me Thursday at 10 to load the new certificate. [[mock:reminder-thursday]]")`. Then:
    - the reply is "The CI mock set the Thursday reminder.";
    - Chat made 2 requests, `selectedBy` `marker`;
    - there is one row with Text "load the new certificate" and `DueAt` = `Data.Time.FromLocal("2030-11-07T10:00:00")`, pending, with its waiter waiting;
    - the rail lists it, and the tool steps are as above.
  - **`TestCancelThroughChat`** (AC 3).
    - **Setup:** `Remove("zzReminderChatCancel01")`, sessions A and B, `ReminderOpsFixedRef.Next("zzReminderChatCancel01")`. A sends the guide prompt (control: A's row Ref is the fixed one), then B sends it (B's Ref differs).
    - **Then** A sends `Turn("Cancel my reminder to stretch. [[mock:reminder-cancel-chat]]")`, and:
      - the reply is "The CI mock cancelled the reminder.", and Chat made 3 requests, `selectedBy` `marker`;
      - request 2's one `tool_result` lists exactly A's Ref, not B's. Read its `reminders[].ref`; a string result is parsed first, as Lane A's `AssertListed` reads it;
      - request 3's second `tool_result` is `ok` true with that Ref;
      - A's row is `cancelled`, with `CancelKey` `<cancel ItemId>:2`;
      - `WaitEnded(fixed, 10)`, long before its 60-s due;
      - A's events are `created,cancelled`, and A's `StateBody` rail has no reminder;
      - B's row is pending, its waiter waiting, and its events are `created`;
      - `AssertToolSteps` gives list then cancel ("Listing your reminders", "Cancelling a reminder").
- [ ] `web/e2e/demo-path/03-reminder.spec.ts` -- AC 2 (REL-2; DW-303, DW-210). Replace the `notBuilt` line with one `test.describe`, untagged, whose first statement is `test.skip(!process.env['OCUTALON_URL'], 'Story 8.6 needs the first-start stack (OCUTALON_URL), which a run without one lacks')`. Its header says what it pins.
  - `beforeAll` (240 s): `pointKeys()`.
  - The test (120 s):
    1. `signInReadme`, and the snapshot loads.
    2. Click "Step 2, Reminder, upcoming". The prompt reads `"Remind me in 1 minute to stretch."`. Click the guide's Send.
    3. `main app-user-message` shows the prompt, with `.when` `/^From the demo guide/`.
    4. A reply holding "The CI mock set the reminder." shows (30 s).
    5. Under Reminders, one `li.row[data-section="reminders"]` has `.lead` `/^stretch$/i` and `.countdown` `/^in \d+ (s|min)$/`.
    6. "Step 2, Reminder, done" is present.
  - `afterAll` (240 s), each part in `try`/`finally`:
    - via `irisScript`, `ReminderFixture.CancelPending(<README session Ref>)`, with the Ref from `Session.ForUser("ocutalon")`;
    - then `restoreKeys()`.
- [ ] `web/e2e/reminder/chat.spec.ts` (new; the rail user; `test.use` UTC and en-GB as `reminder.spec.ts` does) -- the page surface of AC 1's Thursday and AC 3. The header says what it pins and what it needs.
  - `beforeAll` (240 s): `pointKeys()`, then `irisScript` `ReminderOpsFixedRef.Use()`, which must be OK.
  - `afterAll` (240 s), each part in `try`/`finally`: `Restore()`, then `restoreKeys()`, then `irisScript` `RunnerFixture.WaitRecords()`, which must be 1. Later sign-in specs expect the no-key fallback.
  - `afterEach`: `ReminderFixture.Remove` for each Ref the test kept.
  - A local `send(page, text)` types into `Message OcuTalon`, clicks `main`'s Send, and returns the POST `/messages` body's `clientId`.
  - **C1, a Thursday reminder set through the chat shows in the rail.**
    - Sign in. `send` the Thursday message. `replyOf(clientId)` contains "The CI mock set the Thursday reminder.".
    - A reminders row whose `.lead` is "load the new certificate" shows with a `.countdown` `/^in \d+ h \d+ min$/`.
    - Its Ref, read from `data-row-key`, is kept.
  - **C2, a reminder cancelled through the chat leaves the rail within one live update.**
    - Setup: `Remove` and `Next("zzReminderChatCancel01")`. Sign in. `send` the guide prompt. Its reply shows, and `li.row[data-row-key="reminders:zzReminderChatCancel01"]` shows. The reminder is due in 60 s, so the cancel below runs well before it.
    - `send` "Cancel my reminder to stretch. [[mock:reminder-cancel-chat]]". Its reply contains "The CI mock cancelled the reminder.".
    - The row is gone within 15 s, without a reload.
    - `irisScript` reads the row's `State` as `cancelled`.
- [ ] `web/scripts/demo-path-summary.test.mjs` -- DW-210. `playwrightEnv()` sets `PLAYWRIGHT_BROWSERS_PATH` to `join(work, 'no-browsers')`, a folder that is never created. Its doc says why: a step spec that starts a browser before it skips then fails the run everywhere. The file's header line "no browser starts" stays true.
- [ ] `docker/tests/test-demo-path.sh` (Q4: the header comment's lines 12-13 only, nothing else) -- on line 13, replace only the sentence "No test sends a model request." with "Only step 3's spec sends a model request, to the CI mock." Don't re-wrap the following lines: a longer line 13 is fine.

**Acceptance Criteria:**
1. **Set through the chat.**
   - Given the running production, pointed keys and the CI mock, when a session's chat message holds the guide prompt "Remind me in 1 minute to stretch." (`B/guide-reminder.json`, by prompt), or "Remind me Thursday at 10 to load the new certificate." with `[[mock:reminder-thursday]]`, then:
     - Chat calls `set_reminder`, and `ReminderOps` creates one pending reminder with a live waiter (`stretch` due 60 s after arrival, or `FromLocal("2030-11-07T10:00:00")`);
     - the reply is the scenario's;
     - the rail lists the reminder;
     - the tool call is an ok `tool` AgentStep in the turn's trace session (`ReminderChat`).
   - Given the sign-in stack, when the rail user sends the Thursday message in the composer, then the reply and a "load the new certificate" row with its countdown show (`chat.spec.ts` C1). (FR-34, AD-9, AD-22, AD-26)
2. **REL-2's reminder step is on.** Given the `live:demo-path` first-start stack with the CI mock, when the README account presses Send on guide step 2, then:
   - the exact prompt shows as "From the demo guide";
   - the reply "The CI mock set the reminder." shows;
   - a "stretch" row with its countdown shows under Reminders;
   - the guide marks step 2 done.

   `03-reminder.spec.ts` passes there, and the step summary reads step 3 `passed`. (REL-2, AD-12, AD-29, UX-DR44)
3. **Cancel through the chat.** Given a pending reminder set through the chat in each of two sessions, when one sends "Cancel my reminder to stretch." with `[[mock:reminder-cancel-chat]]`, then:
   - Chat calls `list_reminders`, which gives only that session's reminder, and then `cancel_reminder`;
   - `ReminderOps` cancels that reminder (`CancelKey` `<ItemId>:2`), and its waiter ends at once;
   - one cancelled event removes its row from the rail, which in the page happens within one live update without a reload (`chat.spec.ts` C2);
   - the reply confirms;
   - the other session's reminder, its waiter and its events are untouched. (FR-34, NFR-9, AD-1, AD-4, UX-DR54)
4. **REL-2's skip rule (DW-210).** Given `npm --prefix web test` with no `OCUTALON_URL`, when 'skip every unbuilt part' runs, then:
   - Playwright finds no browser;
   - step 3 reads `skipped, 0 passed, 1 skipped (Story 8.6: ...)`;
   - a step spec that starts a browser before its skip fails the test.

## Spec Change Log

## Review Triage Log

## Design Notes

**Rulings in force (dispatch, 2026-10-27):**
- Q4 (orchestrator, decide): only the `test-demo-path.sh` header lines 12-13, and only once 03 is on.
- DW-303 (by-design at 8.4's review): this story replaces 03's `notBuilt(..., '8.4')`.
- U-118: Lane A's multi-id `cancel_reminder` is Story 11.1's, and the tool is unchanged here.
- `Agent/Chat.cls` and `OcuTalon/Tools/**` are never edited. No Chat instruction line is needed, because the mock scripts every reply (checked: no intent gap).

**Governing ADs:**
- AD-1: the command path through the tools, origin `tool`, key `<ItemId>:<n>`.
- AD-4: the list and the cancel see only the session's reminders.
- AD-9: agent steps.
- AD-12: live events, the snapshot and the server-derived guide.
- AD-18: `Data.Time.FromLocal` converts the Thursday.
- AD-20: Chat's 4 iterations; the cancel scenario takes 3.
- AD-22: the B scenarios, marker before prompt, throwaways, `lane-b`.
- AD-26: each turn's own trace session.
- AD-29: Lane B turns REL-2's step on; Lane A's files are read only.
- AD-33: `ReminderOps` is the table's one owner.

Conventions: "Tests" (`notBuilt`, `@floor`) and "Identifiers" (a 22-character Ref).

**Measured in planning** (warm throwaway `e8s6planw`, build 154, lane C, torn down):
- **The guide prompt through `WebChatIn`.** With `FromGuide` 1 and keys pointed, the turn ended `done` in about 1 s with the reply "The CI mock set the reminder.". It left:
  - one pending `stretch` row, `DueAt` = `CreatedAt` + 60 s, key `<ItemId>:1`;
  - one `reminder` event;
  - a `guide.state` with step 2 done.
- **The mock log.** It held 2 Triage requests (no tools, `selectedBy` `prompt`) and 2 Chat requests (3 tools, `prompt`, `guide-reminder`).
  - The triage decision is a fallback, `invalid`. Triage has no tools, so the `set_reminder` call goes unused and the text reply isn't Triage's schema.
  - The turn decision is not a fallback, with 3 steps: model, tool "Setting a reminder", model.
- **A marker message that lists and cancels** (`A/reminder-cancel`) took 3 Triage requests and 3 Chat requests, and the turn ended `done`.
- **The item swap.**
  - `RunnerFixture.UseItemClass("ReminderOps", "OcuTalon.Test.Schedule.ReminderOpsStartedProbe")` took 1.0 s, and the next `ReminderFixture.Set` was answered by the subclass (no waiter).
  - `RestoreItemClass` took 1.0 s, and the next set started its waiter. The stored class was then `OcuTalon.Schedule.ReminderOps`.
- `PointKeys` took 3.1 s and `RestoreKeys` 3.1 s.
- In the throwaway (UTC), `FromLocal("2030-11-07T10:00:00")` is `2030-11-07T10:00:00Z`.

**Decided in-stage:**
1. **A fixed Ref through a seam.** The mock copies tool inputs verbatim and can't carry a Ref from a tool result. New mock behaviour would edit the contended `mock.mjs`. So:
   - the cancel scenario names `zzReminderChatCancel01`, as `A/reminder-cancel.json` names a fixed Ref;
   - `ReminderOps` gets a private `NewRef()` seam, the same pattern as `StartWaiter`;
   - a test subclass hands out the fixed Ref once, behind the item, for the chat-cancel tests only.

   The demo path never swaps the item: 03 uses the real `ReminderOps`.
2. **Marker scenarios.** The Thursday and cancel scenarios are marker scenarios, sent with the AC's words plus the marker. A prompt scenario for "Cancel my reminder to stretch." would catch any message holding the rail's hint text, and its fixed Ref only means something with the seam.
3. **The Thursday date.** It is the fixed `2030-11-07T10:00:00`, a Thursday in the week after US daylight saving ends. The mock can't compute "next Thursday", and a near date would become a `past` refusal. The daylight-saving property is pinned in-process by 8.4's `ReminderZone`, because throwaways run in UTC.
4. **03 is untagged.**
   - With no stack it must skip with a Story label, for 'skip every unbuilt part'. That follows 02's Story 8.2 precedent.
   - In `live:demo-path` it always runs, and a failed test fails the unit.
   - Story 11.1 tags UJ-1's end-to-end floor.
5. **"stretch" is matched case-insensitively.**
   - The AC says "Stretch", but the mock sends `stretch`, pinned by Epic 4's `GuidePrompts` and `guide-view.test.mjs`.
   - The rail shows the text exactly.
   - Capitalising would edit the contended `web/src/app/rail/**`.
6. **03 cancels its reminder in `afterAll`** through the product's cancel path, `CancelPending`.
   - So steps 4 to 6 see the README session as before: no reminder fires during 04, and step 2 is not done again (`Test.Demo.Guide`: a cancelled reminder doesn't count).
   - Story 11.1's `notBuilt` in 04 ("the reminder lands ... during the wait") drops this cancel.
7. **The IRIS chat tests go through `WebChatIn`**, the REST surface's own entry, instead of only Decide as Stories 1.10 and 4.4 do. That covers the real Conversation, its triage request and the turn, as measured above.
8. **The page surface is `web/e2e/reminder/chat.spec.ts`** in `live:sign-in`, on the rail user. It is a separate file, so the pointed keys and the swapped item cover its two cases only.
   - Its `afterAll` waits for the runners' key records (`WaitRecords`), because `trace/links.spec.ts` runs later and expects the no-key fallback.
   - It adds about 20 s to `live:sign-in` (inference from the timings above). The 8.4 local run was 499-506 s, and CI was 701 s of 1200.
9. **DW-232.** `B/guide-reminder.json` stays as it is. It already answers the exact prompt with `set_reminder` (`stretch`, 60) and a reply that confirms.
   - Under the reply rule (`k`), no request could reach an extra reply.
   - Its text is pinned by Epic 4's tests.
   - The loader refuses a second prompt scenario, and the two new files are marker scenarios.
10. **The triage fallback of a guide turn is a CI-mock artefact.** The mock serves every request that holds the prompt from one scenario. It is recorded for Story 11.1, which checks UJ-1 end to end, and is not changed here: the selection is contended and Triage is Lane A's.
11. **03's reply assertion** uses the reply text, not the `clientId`. The guide's Send has no POST capture in 03, and the README chat holds no other reply.

**Ledger inbox:**
- DW-210: addressed by the `playwrightEnv()` task, 03's describe-level skip, AC 4 and the matrix row "No stack".
- DW-232: addressed by reusing `B/guide-reminder.json` unchanged (Decided 9), AC 1 and the matrix row "Guide prompt". No second prompt scenario is added.

**Integration ACs:**
- Chat, through Story 1.10's tools and the CI mock, reads the B scenarios. `ReminderOps` then sets or cancels, and the reply confirms (AC 1, AC 3: `ReminderChat`).
- The page's rail reads the `reminder` events and `/state`: the row shows (AC 1, AC 2) or leaves within one live update (AC 3: `chat.spec.ts`, 03).
- The guide marks step 2 done from the real reminder (AC 2: 03, `ReminderChat`).

**Consumes:**
- Story 8.4: `ReminderOps`'s set, list and cancel.
- Story 1.10: the reminder tools and `CommandCall`.
- Story 4.4: guide step 2 and `B/guide-reminder.json`.
- Story 0.11: the mock.
- Stories 2.4, 2.5 and 2.8: the chat, the reply and the rail.
- Story 2.3: `WebChatIn` and Conversation.
- Tests: `Test.Core.InProduction`, `RunnerFixture`, `Test.Contract.Mock`, `Test.Data.Fixture` and the e2e support helpers.

**Consumed-by:**
- Story 11.1 (UJ-1 end to end): 03's step, its cleanup cancel (Decided 6), and the triage note (Decided 10).
- Story 8.5: no new seam it needs. `NewRef` and the subclass are test-only.

**Extend, don't copy:**
- `ReminderOpsFixedRef` extends `ReminderOps`, as the probes do.
- `CancelPending` and `RemoveAll` extend `ReminderFixture` over `Cancel` and `Remove`.
- `ReminderChat` extends `Test.Core.InProduction` (`Send`, `WaitDone`, `Session` and the clean-up) and reuses `ReminderFixture`, `RunnerFixture`, `Mock`, `Fixture` and `Observe`.
- Its `AssertToolSteps` is new. The sibling `Test.Tools.Reminders.AssertSteps` is a private method of a Lane A class (AD-29) and can't be shared. The new helper reads the turn's trace session from its Item header.
- `chat.spec.ts`'s `send` is local, because `chat/chat.spec.ts`'s `sendWithEnter` is private to Epic 2's spec.

**Footprint extensions to report:**
- `web/scripts/demo-path-summary.test.mjs` (DW-210, uncontended);
- `docker/tests/test-demo-path.sh` lines 12-13 (Q4);
- `web/e2e/reminder/chat.spec.ts` (the approved `web/e2e/reminder/**`).

## Verification

**Shared values.**
- `<L>` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=8 stage=<stage>'`. Write it out in full on each call.
- Each call is its own foreground tool call with `timeout: 600000`. Tags: implement uses `e8s6i` (fresh) and `e8s6iw` (warm); other stages use `e8s6<stage>` and `e8s6<stage>w`.
- **The warm stack.** Its manifest includes `ci/mock/**`, so write both B files before `warm.sh up`. A later change to them needs `warm.sh down`, then `up`.
- **ReminderOps changes.** A change to `ReminderOps` reaches the warm stack only after the item restarts, as recorded in 8.4's restart recipe.
- `ReminderChat`'s own swap also restarts the item.

**Commands:**
- `(once, first)` `<L> OCUTALON_RUN_TAG=e8s6iw ci/warm.sh up`. Expected: ready.
- `(loop)` `<L> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e8s6iw ci/iris.sh class OcuTalon.Test.Schedule.ReminderChat`. Expected: `CLASS ... passed`.
- `(loop)` After a warm reload of `ReminderOps.cls`, restart the item:
  ```
  P=$(OCUTALON_RUN_TAG=e8s6iw ci/warm.sh status | sed -n 's/.*project=\([^ ]*\).*/\1/p') && printf '%s\n' 'Do ##class(Ens.Director).EnableConfigItem("ReminderOps",0,1)' 'Do ##class(Ens.Director).EnableConfigItem("ReminderOps",1,1)' 'Halt' | docker exec -i "$(docker ps -q --filter label=com.docker.compose.project=$P --filter label=com.docker.compose.service=iris)" iris session IRIS -U OCUTALON
  ```
  Expected: no error.
- `(loop)` The warm class command, one per call, for each class below. Expected: passed.
  - `OcuTalon.Test.Schedule.Reminders` and `OcuTalon.Test.Schedule.ReminderLogic`;
  - `OcuTalon.Test.Demo.GuidePrompts`, which must still find the keys restored and no reminder from its own turn;
  - `OcuTalon.Test.Core.ConversationProduction`, which expects the no-key fallback after `ReminderChat` restored the keys.
- `(loop)` `bash docker/tests/test-mock.sh` (the loader accepts the two B files), `npm --prefix web run lint` and `node --test web/scripts/demo-path-summary.test.mjs`. Expected: pass and exit 0.
- `(once)` One per call: `<L> OCUTALON_RUN_TAG=e8s6i ci/iris.sh build`, then `shard lane-b`, `shard lane-b --reverse` and `shard lane-a`. Expected: every `CLASS` passed, about 7 minutes each.
- `(once)` `<L> OCUTALON_RUN_TAG=e8s6i ci/iris.sh live demo-path`. Measure and record the time. Expected: passed, `STEP 3 reminder: passed, 1 passed, 0 skipped`, and the floor passed.
- `(once)` `<L> OCUTALON_LIVE_DEADLINE=900 OCUTALON_RUN_TAG=e8s6i ci/iris.sh live sign-in`. Record the time; it was about 500 s before this story. Expected: passed, with both `chat.spec.ts` cases and every `trace/links.spec.ts` case passing.
- `(once)` `npm --prefix web test`, then `bash ci/checks.sh` and `bash docker/tests/test-boundaries.sh`. Expected: pass.
- `(once, last, also after a failure)` `<L> OCUTALON_RUN_TAG=e8s6iw ci/warm.sh down`, then `<L> OCUTALON_RUN_TAG=e8s6i ci/iris.sh teardown`.

**Mutations (Rule 19).** Apply each, observe red, revert, and confirm the tree is byte-identical. Record each as `mutation: <change> -> <red test>`.
- AC 1:
  - `ReminderOps.Set` skips its created publish -> `ReminderChat.TestGuidePromptSetsReminder` (events);
  - `Data.Time.FromLocal` adds 3600 s -> `ReminderChat.TestThursdaySetsLocalReminder` (`DueAt`).
- AC 2: the same publish mutation -> 03 in `live:demo-path`, because the row never shows.
- AC 3:
  - `ReminderOps.Cancel` skips its publish -> `chat.spec.ts` C2 (the row stays) and `ReminderChat.TestCancelThroughChat` (events);
  - `ReminderOps.List` reads every session's pending rows instead of `Ownership.Reminders` -> `TestCancelThroughChat` (the list holds B's Ref).
- AC 4: 03's `test.skip` moved into the test body -> `demo-path-summary.test.mjs` 'skip every unbuilt part'. With `playwrightEnv()`'s fix also reverted, the same run is green where Chromium is installed (DW-210's evidence).

**Shared surfaces:**
- the mock's scenario set: names unique across A and B, and `guide-reminder.json` unchanged;
- the demo-path step summary: step 3 now runs on a stack and skips without one;
- the README session's reminders and chat in `live:demo-path`: 03 cancels its own reminder;
- the runners' Config Store keys: 03, `chat.spec.ts` and `ReminderChat` point them and put them back;
- the `noModelKey` status events on the instance stream while the keys are pointed;
- the `ReminderOps` item's class, swapped and put back, and `^OcuTalonTest("ReminderOpsFixedRef")`;
- the fixed Ref `zzReminderChatCancel01`: each test removes it first and last;
- the rail user's chat and reminders in `live:sign-in`;
- the run times of `live:sign-in`, `live:demo-path` and `shard lane-b`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (bmad-build-auto, halted after planning).** This is the chat side, split from 8.4. The first 8.4 plan (467dfae) was checked against the code 8.4 committed.
- **Kept:** the B marker scenarios, `ReminderChat`, the fixed Ref, `CancelPending`, the `playwrightEnv()` fix, 03 untagged, the case-insensitive "stretch", 03's cleanup cancel, and the fixed Thursday.
- **Changed:**
  - 8.4 has no `NewRef` seam, so this story adds it to Epic 8's `ReminderOps.cls`;
  - the IRIS tests go through `WebChatIn` instead of only Decide;
  - a browser spec, `web/e2e/reminder/chat.spec.ts`, shows AC 1's Thursday and AC 3's cancel on the page.
- **Measured on a warm throwaway** (torn down): the guide prompt through the real web path makes one reminder (Triage ends in a fallback, a mock artefact noted for Story 11.1). The `ReminderOps` item swap works, at 1 s each way, and pointing or restoring the keys takes 3 s each.
- **Ledger:** DW-210 and DW-232 are addressed. **Footprint extensions:** `web/scripts/demo-path-summary.test.mjs`, `docker/tests/test-demo-path.sh` lines 12-13 (Q4) and `web/e2e/reminder/chat.spec.ts`.
