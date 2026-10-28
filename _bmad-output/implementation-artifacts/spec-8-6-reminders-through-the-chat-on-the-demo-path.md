---
title: 'Story 8.6: Reminders through the chat on the demo path'
type: 'feature'
created: '2026-10-27'
status: 'in-progress'
baseline_revision: '99931c0368f1974776296c0889c1472cde59886f'
baseline_commit: '99931c0368f1974776296c0889c1472cde59886f'
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

### Review Findings

Code review, 2026-10-27 (Epic 8 code-review stage; four layers, no model override; diff `99931c0..HEAD` plus the working tree). 31 findings from the layers, plus 2 from the reviewer's own Rule 2 check. They make 12 rows (med 2, low 10, high 0): 10 patched, 2 ledgered. 15 were rejected.

- [x] [Review][Patch] (med; Blind, Edge, Auditor) `chat.spec.ts` left the rail user's real turns, with their triage and turn decisions, AgentSteps, Usage rows and AI sessions. `rail/rail.spec.ts` R1 holds that session empty ("Recent decisions (0)"), so it stayed green only because `rail/` runs before `reminder/` (Rule 19). A C2 whose swap failed also leaked a random-Ref `stretch` reminder, and the Thursday sweep was not limited to a session. Fixed:
  - `afterEach` now runs `ReminderFixture.RemoveAll` and the new `ReminderFixture.RemoveTurns` on the rail user's session, and asserts that no reminder and no turn are left (`0|0`);
  - `afterAll` drops the AI sessions saved since the `beforeAll` mark (`RunnerFixture.DropSince`).

  `ReminderChat.OnAfterOneTest` now calls `RemoveTurns` instead of its own copy of the loop. [web/e2e/reminder/chat.spec.ts:83]
- [x] [Review][Patch] (low; Blind) `ReminderChat.OnBeforeOneTest` killed today's `^OcuTalonBP.UsageCapped` mark even when `Missing` was set. It is now guarded, as `GuidePrompts.Ready` does. [src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderChat.cls:88]
- [x] [Review][Patch] (low; Blind) `AssertToolSteps` compared the total of in-session headers with the step count, so one step with two headers could hide a step with none. It now counts the steps that have a header in the turn's trace session. [ReminderChat.cls:277]
- [x] [Review][Patch] (low; Blind) The private class method `Refs(session)` shared its name with the inherited property `Refs`. It is renamed `ReminderRefs`. [ReminderChat.cls:155]
- [x] [Review][Patch] (low; Blind) The `Turn` doc said "1 when the message was accepted and the turn exists", but the method answers whether the turn is done. The doc is corrected. [ReminderChat.cls:118]
- [x] [Review][Patch] (low; Blind) The class doc of `ReminderFixture` named only `Reminders` and `reminder.spec.ts` as its users. It now names its users and `RemoveTurns`. [src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderFixture.cls:1]
- [x] [Review][Patch] (low; Gap, Auditor) `ReminderOpsFixedRef.Restore()` answered OK with no class stored, even while the item still ran the test class (a swap left by a crashed run on a reused stack, which `Use()` then does not store). It now returns an error while `$$$ConfigClassName("ReminderOps")` is still this class. [src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderOpsFixedRef.cls:42]
- [x] [Review][Patch] (low; Gap) `playwrightEnv()` kept `OCUTALON_E2E_IRIS_CONTAINER`. A spec whose hooks ran before its skip could then reach a named live container. The variable is now deleted, so the doc's "no stack, whatever the shell holds" is true. [web/scripts/demo-path-summary.test.mjs:340]
- [x] [Review][Patch] (low; Auditor) `ReminderChat.OnAfterAllTests` ran `Fixture.AdoptTurns` before the restores. If it threw, the item swap and the pointed keys stayed for the rest of `lane-b`. It now runs after them. [ReminderChat.cls:66]
- [x] [Review][Patch] (low; Auditor) AC 2 says "the exact prompt", but 03 matched the user message by substring. It now also asserts the message's `.bubble` text exactly. [web/e2e/demo-path/03-reminder.spec.ts:39]
- [x] [Review][Defer] (med; reviewer, Rule 2) `AssertToolSteps` is a near-copy of Lane A's private `Test.Tools.Reminders.AssertSteps`. The copy is forced by AD-29, as the spec records. DW-316: routed to Story 11.1, which changes `cancel_reminder` and that test class. [ReminderChat.cls:240] -- deferred: out-of-footprint (Lane A's `Test/Tools/**`).
- [x] [Review][Defer] (low; reviewer, Rule 2) 03 and `chat.spec.ts` repeat the same tail: `restoreKeys()`, then `WaitRecords`. Its natural home, `support/devices.ts`, is contended. DW-317: `wontfix-accepted` with a `reopen_if`. [web/e2e/demo-path/03-reminder.spec.ts:62] -- deferred: out-of-footprint.

**Evidence (review pass, lane C).**
- Warm `e8s6cw`: `ReminderChat` passed (11.0 s) and `Reminders` passed (29.7 s).
- `RemoveTurns` was run directly on a WebChatIn turn of a new fixture session: 1 turn and 2 decisions before, `0|0` after.
- `Restore()` after a swap whose stored node was killed answered `ERROR #5001: The ReminderOps item still runs OcuTalon.Test.Schedule.ReminderOpsFixedRef after the restore`. A normal `Use`/`Restore` answered OK, with the item back on `OcuTalon.Schedule.ReminderOps`.
- Fresh `e8s6c`:
  - `live demo-path` passed in 100 s (`STEP 3 reminder: passed, 1 passed, 0 skipped`, floor 7 of 7);
  - `live sign-in` passed in 512 s (`OCUTALON_LIVE_DEADLINE=900`, 222 passed).
- `node --test web/scripts/demo-path-summary.test.mjs` passed 28, web lint exited 0, and `test-boundaries.sh` passed.
- Both tags are torn down.

**Rejected:**
- `false` (Blind): the marker tests do not pin their scenario names. The cancel answer's `ref` and the `CancelKey` are `zzReminderChatCancel01`, which `A/reminder-cancel.json` (it cancels `zzReminderStretch00001`) cannot produce. The Thursday reply and text are unique to `reminder-thursday`.
- `low` (Blind, Edge): there is no early exit after A's control check in `TestCancelThroughChat`. A failed control already turns the test red, and the `<INVALID OREF>` that follows is a loud failure. The fix would add a guard.
- `low` (Blind): 03's `afterAll` adds a second failure (cancelled 0) when the test failed before the Send. It follows a real failure only, and the fix needs extra state.
- `low` (Edge, three findings): a 60-second reminder could fire before its cancel in `TestCancelThroughChat`, C2 or 03's `afterAll`. A turn takes about 1 s (measured), and a fire would fail loudly, never green.
- `low` (Edge): C2's setup script prints a constant (`CHK|next|1`). A failed `Remove` or `Next` fails C2 loudly at the fixed-Ref row, and `test-boundaries.sh` keeps `^OcuTalonTest` out of specs.
- spec text (Edge; the fix edits the spec): the triage log above says "a script error already fails `irisScript`". That premise is wrong. `irisScript` resolves `[]` after three tries with no `CHK` line, and an ObjectScript error on one line does not stop the later lines. The rejection it supported (the constant `CHK` lines) still stands, on the reason in the previous bullet.
- spec text (Blind, Edge, Auditor; the fix edits the spec): Decided 15 says `afterEach` removes "the kept Refs only". The first patch above replaces that clean-up with the rail user's session clean-up.
- spec text (Auditor): the `TestCancelThroughChat` task bullets say "request 2's one `tool_result`" and "request 3's second". The code follows Decided 12 and 13, which are the in-stage record.
- spec text (Blind): Residual risks names a 570 s line without defining it and without citing DW-314. 570 s is the stage's stop line for a local `live:sign-in` run, and DW-314 already holds the risk.
- `false` (Gap): C1 has no `mutation:` line. Rule 19 asks one observed mutation per AC. AC 1 has two (`ReminderChat`), and the same created-publish skip turned 03's rail row red through the same rail path.
- `false` (Auditor): the spec's `status: done` disagrees with sprint-status `review`. The frontmatter is `bmad-build-auto`'s contract, and this review syncs the sprint status.
- not this diff (Auditor): a live model on guide step 2 is unproven, and the CI mock's triage ends `invalid`. Both are ledgered for Story 11.1: DW-142 and DW-307 (this story is DW-307's source).

- [ ] [Smoke] Integrate-forward red (merge 8d5f805 of feature 289d47a into OCT-epic8): `OcuTalon.Test.Schedule.ReminderChat` fails all three tests (`Chat made N request(s)`), because Epic 5 added `OcuTalon.Tools.Watching` to `OcuTalon.Agent.Chat`'s `TOOLSETS`, so `CHATTOOLS` ("cancel_reminder,list_reminders,set_reminder") no longer equals Chat's `ToolNames` and no Chat request is selected. Fix the selection so it identifies Chat's requests without pinning Chat's whole tool list (for example: a `/v1/messages` entry whose `ToolNames` includes the reminder tools, since Triage offers none; or derive the expected list from `OcuTalon.Agent.Chat`'s own toolsets, never a copy), keep the counts the tests assert, and check `web/e2e/reminder/chat.spec.ts` and `web/e2e/demo-path/03-reminder.spec.ts` for the same exact-match assumption (fix it the same way if present). Never edit `Agent/**` or `Tools/**`. Each changed pinning assertion gets its `mutation:` line (e.g. a request without the reminder tools counted as Chat's -> red).

## Spec Change Log

- 2026-10-28 (lead): rework iteration 1 opened at Epic 8's integrate-forward: ReminderChat red on the merged tree (Chat's toolset grew with Epic 5's Watching tools); one `[Smoke]` item.

## Review Triage Log

### 2026-10-27 - Review pass
- verdicts: 31 findings reported by the four layers, 21 rows (findings with one root cause share a row and name their layers) - high 0, medium 5, low 10, false 6, maybe-false 0
- findings:
  - `[medium]` `[patch]` Blind: the AC 4 mutation line contradicts Decided 16 (green vs red with `playwrightEnv()` reverted); Gap: the `playwrightEnv()` fix has no red-proving mutation; Intent: DW-210's evidence is not shown -- fixed: ran the isolating mutation (a hook-free `page` test that skips in its body: red with the fix, green with it removed), recorded it in `## Verification`, rewrote Decided 16 and the AC 4 line.
  - `[medium]` `[patch]` Blind, Edge, Gap: 03's `afterAll` passes when `CancelPending` returns 0 (`/^\d+$/`), so a failed cancel lets the reminder fire in steps 4-6 -- fixed: asserts the count is at least 1.
  - `[medium]` `[patch]` Blind, Edge: 03 restores the keys without `WaitRecords`, which the run rules require for any spec that points them -- fixed: `WaitRecords` must be 1 after `restoreKeys`, in a `finally`.
  - `[medium]` `[patch]` Blind, Edge, Gap: `chat.spec.ts` C1 keeps its Ref only after the reply and row assertions, so an early failure leaks a 2030 reminder with a live waiter -- fixed: `afterEach` also removes every row whose Text is the Thursday text.
  - `[medium]` `[patch]` Edge, Gap: `AssertToolSteps`' "no header outside the trace session" is vacuous when the steps have no headers -- fixed: also asserts every step has a header inside the session (`ReminderChat` passes warm and in both shards).
  - `[low]` `[patch]` Intent, Gap: the unit test does not pin `Story 8.6` for step 3 (the matrix row and AC 4 name it) -- fixed: one assertion on the step 3 line.
  - `[low]` `[reject]` Blind, Gap: `chat.spec.ts` ignores the `CHK|removed` and `CHK|next` lines -- both print a constant, and a script error already fails `irisScript`; a check would add code for no new failure mode.
  - `[low]` `[reject]` Blind, Edge, Gap: `ReminderOpsFixedRef.Use()` cannot recover a swap left by a crashed run, and `Restore()` kills the stored class even when the restore fails -- needs a crash between `Use` and `Restore` on a reused stack; the spec fixes both behaviours ("it always kills both nodes"), and throwaways are fresh.
  - `[low]` `[reject]` Blind: AD-4 is checked through the list, not by a cancel of B's Ref from A -- the AC pins the list's scope and B's untouched state, and the cancel's ownership check is 8.4's.
  - `[low]` `[reject]` Blind, Gap: no mutation lines for `CancelPending`, `RemoveAll`, `Restore`, or for C1 and the rail, waiter and B-isolation bullets -- Rule 19 asks one mutation per AC, and each AC has one (AC 1 has two).
  - `[low]` `[reject]` Blind: the `test-demo-path.sh` line is long and reads oddly -- the spec fixes that exact edit and forbids re-wrapping (Q4).
  - `[low]` `[reject]` Edge: `CancelPending` when `Ownership.Reminders` returns "" -- the Output status is unreachable for a session that exists, and a raise fails the `afterAll` loudly.
  - `[low]` `[reject]` Gap: C2 depends on nothing else consuming the stored Ref between `Next` and the send -- the failure would be loud (the row with the fixed Ref would not show), never a false green, and the file runs serially.
  - `[low]` `[reject]` Gap: no in-process test of `Restore()` after a failed `Use()` -- the swap runs only in throwaways and is exercised end to end by `ReminderChat` and `chat.spec.ts`.
  - `[false]` `[reject]` Edge: the `DueAt` bounds could be flaky on second resolution -- `before` is taken before the send and `after` after the turn, so both bounds hold under truncation.
  - `[false]` `[reject]` Edge: `PLAYWRIGHT_BROWSERS_PATH` could mask an ungated spec as a skip regression -- the isolating mutation shows the failure is the late skip, which is the intended signal.
  - `[false]` `[reject]` Gap: line 521's two history copies could both be "none" -- line 517 compares with the fixed Ref first.
  - `[false]` `[reject]` Gap: `ReplyText_"|"_FallbackReason` compared with a literal ending in `|` -- the reviewer found it sound.
  - `[false]` `[reject]` Intent: NFR-10 strict reading against the `DueAt` window -- the spec prescribes the window; it is arithmetic, not a wait.
  - `[false]` `[reject]` Intent: the rail and step 2 are read through `StateBody`, and the cancel through the fixture, in `ReminderChat` -- the spec prescribes both; the page specs cover the page surface.
  - `[low]` `[reject]` Gap: C1's countdown shape relies on `page-time.ts` having no day unit -- checked by the passing `live:sign-in` run and the fixed 2030 date; no new work.

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
12. **A created event has the state `pending`.** The payload's `state` is the reminder's state, as `Test.Schedule.Reminders` reads it (`pending`, then `cancelled`), so `ReminderChat` asserts `pending` and `pending,cancelled` where the spec says "created".
13. **Tool results carry the session's history.** A later turn of the same session sends the earlier set tool's answer as its first `tool_result`. In `TestCancelThroughChat`, request 2 holds two results (the set's, then the list) and request 3 three (the set's, the list, the cancel); the test reads the last of request 2 as the list and the last of request 3 as the cancel.
14. **Thursday has an independent oracle.** `FromLocal` is both the product's conversion and the test's, so a fault in it would cancel out. `TestThursdaySetsLocalReminder` also asserts `ToLocal(DueAt)` = `2030-11-07T10:00:00`.
15. **`chat.spec.ts` C1 reads the Reminders section only** (`li.row[data-section="reminders"]`): the rail's decision rows quote the user's message, so the text alone matches two rows. Its `afterEach` removes the kept Refs only; `Restore()` in `afterAll` clears the stored Ref (`test-boundaries.sh` allows `^OcuTalonTest` in tests, not in specs).
16. **The 03 mutation and DW-210's evidence.** Moving 03's skip into the test body alone stays red without a stack, because its `beforeAll` (`pointKeys`) fails; that run pins 03's describe-level skip, not `playwrightEnv()`. DW-210's evidence is a separate mutation: a 03 with no hooks whose `page` test skips in its body, which is red with `playwrightEnv()`'s browsers path and green without it, where Chromium is installed.

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
- AC 4: 03's `test.skip` moved into the test body -> `demo-path-summary.test.mjs` 'skip every unbuilt part' (red through 03's `beforeAll`). DW-210's evidence: 03 reduced to a hook-free `page` test that skips in its body is red; with `playwrightEnv()`'s fix also reverted, the same run is green where Chromium is installed (Decided 16).

**Mutation results (implement stage).**
- mutation: `ReminderOps.Set` skips its created publish -> `ReminderChat.TestGuidePromptSetsReminder` (events) and `TestCancelThroughChat` (B's events) red.
- mutation: `Data.Time.FromLocal` adds 3600 s -> `ReminderChat.TestThursdaySetsLocalReminder` (ToLocal of `DueAt`) red. The `FromLocal` comparison alone stayed green, because the test and the product share the converter (Decided 14).
- mutation: the same publish skip -> `03-reminder.spec.ts` red in `live:demo-path` (`STEP 3 reminder: failed`, the row never shows).
- mutation: `ReminderOps.Cancel` skips its publish -> `chat.spec.ts` C2 red (the row stays; `reminder.spec.ts` 8.4's cancel case too) and `ReminderChat.TestCancelThroughChat` (A's events) red.
- mutation: `ReminderOps.List` reads every session's pending rows -> `ReminderChat.TestCancelThroughChat` (the list holds B's Ref) red.
- mutation: 03's `test.skip` moved into the test body -> `demo-path-summary.test.mjs` 'skip every unbuilt part' red.
- mutation: 03 reduced to a `page` test that skips in its body, with no hooks -> 'skip every unbuilt part' red (the browser starts and cannot launch); with `playwrightEnv()`'s `PLAYWRIGHT_BROWSERS_PATH` also removed, the same run is green (28 passed), so the fix is what turns a late skip red (DW-210).

**QA gap audit (QA).** Every AC and matrix row is pinned by an assertion that can fail, and each AC had an observed mutation from the implement stage. No test file was added. One more bullet of AC 3 had no observed mutation (the waiter ends at once); it was demonstrated on warm `e8s6qw`:
- mutation (QA): `ReminderOps.Cancel` skips `..EndWaiter(row)` -> `ReminderChat.TestCancelThroughChat` red on "and its waiter has ended, long before its due time" only; reverted from a backup, tree clean (`git status --short` empty), warm `ReminderChat` green again (9.5 s).

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

Status: done
Blocking condition: none

**Plan stage (bmad-build-auto, halted after planning).** This is the chat side, split from 8.4. The first 8.4 plan (467dfae) was checked against the code 8.4 committed.
- **Kept:** the B marker scenarios, `ReminderChat`, the fixed Ref, `CancelPending`, the `playwrightEnv()` fix, 03 untagged, the case-insensitive "stretch", 03's cleanup cancel, and the fixed Thursday.
- **Changed:**
  - 8.4 has no `NewRef` seam, so this story adds it to Epic 8's `ReminderOps.cls`;
  - the IRIS tests go through `WebChatIn` instead of only Decide;
  - a browser spec, `web/e2e/reminder/chat.spec.ts`, shows AC 1's Thursday and AC 3's cancel on the page.
- **Measured on a warm throwaway** (torn down): the guide prompt through the real web path makes one reminder (Triage ends in a fallback, a mock artefact noted for Story 11.1). The `ReminderOps` item swap works, at 1 s each way, and pointing or restoring the keys takes 3 s each.
- **Ledger:** DW-210 and DW-232 are addressed. **Footprint extensions:** `web/scripts/demo-path-summary.test.mjs`, `docker/tests/test-demo-path.sh` lines 12-13 (Q4) and `web/e2e/reminder/chat.spec.ts`.

**Implement and review pass (bmad-build-auto).**
- **Implemented:** the two B marker scenarios, the private `ReminderOps.NewRef()` seam, `ReminderOpsFixedRef`, `ReminderFixture.CancelPending` and `RemoveAll`, `Test.Schedule.ReminderChat` (3 tests through `WebChatIn`), 03 turned on (describe-level skip, untagged), `web/e2e/reminder/chat.spec.ts` (C1, C2), `playwrightEnv()`'s empty browsers path (DW-210), and the Q4 header sentence in `docker/tests/test-demo-path.sh`. Footprint extensions as planned.
- **Review:** 31 findings in 21 rows, 6 patched (5 medium, 1 low), 0 deferred, 15 rejected with reasons (see the triage log). The patches: the isolating DW-210 mutation and its record, 03's `afterAll` (cancel count at least 1, `WaitRecords` after the restore), C1's cleanup by text, the trace-session positive check in `AssertToolSteps`, and the step 3 `Story 8.6` assertion.
- **Follow-up review:** not recommended (`followup_review_recommended: false`); every patch was re-verified by the full run below.
- **Verification (after the last patch):** warm `ReminderChat` passed; `test-mock.sh` 94 passed; web lint exit 0; `demo-path-summary.test.mjs` 28 passed; fresh `build`; `shard lane-b` 65 classes (437 s), `shard lane-b --reverse` 65 (400 s) and `shard lane-a` 47 (425 s), all passed; `live demo-path` passed in 126 s (`STEP 3 reminder: passed, 1 passed, 0 skipped`, floor 7 of 7); `live sign-in` passed, 222 tests, whole call 515 s (limit 570 s) with `OCUTALON_LIVE_DEADLINE=900`; `npm --prefix web test` 691 passed; `ci/checks.sh` and `test-boundaries.sh` passed. The loop classes `Reminders`, `ReminderLogic`, `GuidePrompts` and `ConversationProduction` passed warm in the implement pass, and no code they cover changed after it. Both throwaways are torn down.
- **Residual risks:** `live:sign-in` is 515 s against the 570 s line (about 500 s before this story), so the next story that adds browser cases to that unit needs the unit split. The fixed-Ref swap can stay behind the `ReminderOps` item after a crash between `Use` and `Restore` on a reused stack (rejected as low).
