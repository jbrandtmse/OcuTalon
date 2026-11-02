---
title: 'Story 12.7: Approve or reject from Telegram, and every copy shows who answered'
type: 'feature'
created: '2026-11-02'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-4, AD-11, AD-14, AD-16, AD-17, AD-22, AD-29, AD-32 and AD-33; for the gated Part C also AD-3 and AD-19)'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md (read only the Telegram table of the incident notice, lines 811-821, and line 468)'
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Telegram notices have no buttons, so a paired chat cannot answer an approval request. A button press is confirmed and ignored today (`TelegramIn.HandleUpdate` runs no branch for it), and `TelegramOut` drops every `answered` notification, so a Telegram copy never shows who answered. Lane B already built the rest: `AnswersIn.FromTelegram` with its result codes and slots, `Delivery.FindByApproval`, the `answered.*` and `press.*` catalog keys, `Notify`'s routing of `answered` and `result` to `TelegramOut`, and the page's "Approved from Telegram at 14:15".

**Approach (Part A, the story this spec plans in full):**
- **Buttons.** `TelegramOut` adds the "Approve" and "Reject" inline buttons to `incident` and `approval` notices that carry an `ApprovalRef`.
- **Presses.** `TelegramIn` handles a button press by calling `AnswersIn.FromTelegram`, then answers the press with `answerCallbackQuery`, rendered from the catalog. A refused press gets an alert that stays until dismissed.
- **Answered.** On `answered`, `TelegramOut` edits the message in place: it removes the buttons and makes the status the last line. After a Telegram rejection it sends the follow-up.
- **Proof.** The REL-2 Telegram part of step 5 is turned on, checked against the CI mock.

**Part C, the online demo's texts (U-197, DW-501, DW-506)**, and the rest of the epic's criterion, the switch (`Included()` returns 1, the README section, the harness and the online case), are sibling Story 12.9's (the split was accepted at the spec gate; Design Notes, "Proposed split" and "Runner rulings at the spec gate").

## Boundaries & Constraints

**Always:**
- **Buttons (AD-32, AD-14).**
  - Only a `Notification` of kind `incident` or `approval` whose `ApprovalRef` is not "" gets buttons. They go on its last part only, as `reply_markup` `{"inline_keyboard": [[{"text": <button.approve>, "callback_data": "approve:<Ref>"}, {"text": <button.reject>, "callback_data": "reject:<Ref>"}]]}`.
  - The labels are `Catalog.Render` of `button.approve` and `button.reject` for `telegram` ("Approve", "Reject").
  - The callback data carries the request's `Ref` and the action, never a sequential number.
  - A message with buttons is split at 3,840 UTF-16 units (4,096 less a reserve), so its edited text always fits.
- **The Delivery row of a message with buttons** is recorded through `Delivery.Record` with the approval `Ref` and the last part's text (`text` argument), which the edit needs. Rows with no `ApprovalRef` keep `text` "".
- **A press (AD-11, AD-32).**
  - **Which presses count:** a `callback_query` from a private chat (12.2's rule). It is recorded through `Pairing.RecordChat` first, unchanged.
  - **The call:** `TelegramIn` splits `data` at the first ":" into action and `Ref`. It calls `AnswersIn.FromTelegram(ref, action, chatRef, .code, .slots)` synchronously with the chat row's `Ref`, never a chat id.
  - **The answer:** it then calls `answerCallbackQuery` `{callback_query_id, text, show_alert}` once. The text is `Catalog.Render(key, slots, "telegram")`:

    | code | key | show_alert |
    |---|---|---|
    | `approved` | `press.approved` | false |
    | `rejected` | `press.rejected` | false |
    | `already_answered` | `answered.alreadyApproved`, or `answered.alreadyRejected` when `slots.action` is `reject`, with {channel, time} | true |
    | `expired` | `answered.expired` {time} | true |
    | `not_paired`, `not_visible` | `press.notPairedChat` | true |
    | `unknown` | `press.unavailable` | true |

  - **No text:** these cases answer with no `text` and `show_alert` false, plus one warning (the last three only):
    - `approved` with no `count` slot (a request with no dry run);
    - `not_allowed` (step 6, Story 26.4);
    - an error status from `FromTelegram`;
    - a render error.
  - **What a press never does:** it makes no Turn, calls no model, and sends no chat message. A failed `answerCallbackQuery` is one warning.
- **Edit in place (AD-14, AD-32, UX "Answered anywhere").** On a `Notification` of kind `answered`, `TelegramOut` reads the session's newest `telegram` Delivery row of that `ApprovalRef` through `Ownership.DeliveryFor`. Then:
  - **No row, or a row with no stored text or message id:** nothing is sent, with one warning.
  - **The row's kind is `answered`:** nothing is sent. The first answer stays.
  - **Otherwise:**
    1. It calls `editMessageText` with `chat_id` (the chat row of the id's `ChatRef`, `Pairing.Chat`), `message_id` and text = the stored text + LF LF + `Catalog.Render(CatalogKey, Slots, "telegram")`. It sends no `reply_markup`, which removes the buttons.
    2. It records a Delivery row of kind `answered`, with the same id and `ApprovalRef` and the edited text.
    3. When `CatalogKey` is `answered.rejected` or `answered.rejectedBy`, `Slots.channel` is `telegram` and `IncidentRef` is set, it then sends `press.rejectedFollowUp` as a new message to the same chat. That message's row has kind `answered` and `ApprovalRef` "".
  - **The result:** `result` notifications stay 12.6's new messages.
  - **Retries:** a 429 on the edit is retried as `SendPart` retries.
- **Logs (AD-4, AD-14).** A log text is a parameter, followed only by `Api.Safe` of a status text. No chat id, name, `Ref`, callback data or message text appears in a log, a message body, a live event or an audit entry. The audit entry of a Telegram answer names channel `telegram` and the session's IRIS user (Lane B's `Approval.Answer`, unchanged).
- **Tests.**
  - They run on lane-A throwaways and in CI only, against the CI mock and its dummy token.
  - The seam goes through `SetTelegramIncluded` and is restored on every path.
  - Fixture chat ids are `84017734140` to `84017734149` (IRIS) and `84017734115` (the browser spec). Sessions are `zztg...`.
  - Every row a test makes is removed on every path. Every IRIS script prints its `CHK|` lines on every path.

**Never:**
- **No edit to a Lane B or contended file** beyond the two ruled edits named under Design Notes, "Edits outside Lane A that need the runner's ruling" (the Delivery doc line listed there is an ask, not an edit):
  - not `AnswersIn`, `Notify`, `IncidentManager`, `Data/*`, `Msg/Catalog/Core.cls`, `web/src/**` or `web/e2e/support/**`;
  - not `ci/mock/*.mjs`, `ci/mock/test/**`, `ci/units.sh` or `README.md`.
- No `editMessageReplyMarkup`: the mock does not serve it, and `editMessageText` without markup removes the buttons.
- **Scope held for other stories:**
  - `Included()` keeps its seam body; the switch is Story 12.9.
  - No README change.
  - No real bot, no `api.telegram.org`, no real token or model key.
  - Part C is Story 12.9's (the split; U-197's follow-up decides its mechanism there).

## I/O & Edge-Case Matrix

**Test contexts:**
- **"A"** is the new live class `Test.Channel.TelegramApproval`. It uses `LiveCase.BeginPairing`, which starts `TelegramIn` and `TelegramOut` against the mock with the seam on. Its requests are `Test.Data.Fixture.Approval` rows for sessions of this process's user, with a role it holds, as `Test.Core.AnswersTelegramProduction` makes them (a fixture row has no hold, so each real answer waits 5 s and logs one task warning, which the test removes).
- **"O"** is a direct test of `Test.Channel.TelegramOut`.
- **"Answers"** are the mock's `answerCallbackQuery` calls since a mark, and **"Edits(c)"** are its `editMessageText` calls for chat c.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Buttons on a request notice (AC1) | O: `incident.withFix` (slots from `Test.Msg.Catalog` Fixtures), kind `incident`, `ApprovalRef` R, `SessionRef` S. The same with kind `approval` (`incident.laterRequest`). A 5,000-character `approval` notice | The last sendMessage part has exactly the Boundaries' `reply_markup` with R. Earlier parts have none, and every part is at most 3,840 units. One `telegram` Delivery row with R and `Text` = the last part's text | - |
| No buttons | O: kind `incident` with no `ApprovalRef` (fallback notice); kinds `tellnow`, `result`, `reminder`; an `Outbound` | No `reply_markup` on any part. Rows keep `Text` "" | - |
| Approve first (AC2; Integration: `TelegramIn` -> `AnswersIn` -> `Approval.Answer`) | A, `TestApprove`. A pending request R of S with a dry run {affected 50, itemNoun order/orders}. Chat 140, paired with S, presses `approve:R` | Answers = [{text "Approved. Repairing and resending 50 orders.", show_alert false}]. The row is `approved`, `AnsweredChannel` `telegram`, with S's IRIS user. The audit entry since the mark names channel `telegram` and holds neither "84017734140" nor the chat's name. No Turn of S, and no sendMessage since the mark | - |
| Reject first (AC2) | A, `TestReject`. Chat 141 presses `reject:R2` | Answers = [{"Rejected. Nothing was changed.", false}], and the row is `rejected` | - |
| A late press (AC4) | A, `TestLate`. R3 was answered `approve` on channel `web` first (`Approval.Answer`); chat 142 presses `reject:R3`. R3b was answered `reject` on channel `phone` first; chat 142 presses `approve:R3b` | Answers = [{"Already answered: approved from the web chat at T.", true}, {"Already answered: rejected from the simulated phone at T2.", true}], with T and T2 = `ForMessage` of each winning time. Both rows are unchanged | - |
| Expired (AC4) | A, `TestExpired`. R4 is past its `ExpiresAt`; chat 143 presses approve | {"Expired at T. Nothing was changed.", true}. The row is unchanged and no audit entry is written | - |
| Not the paired chat (AC4) | A, `TestNotPairedChat`: (a) unpaired chat 144 presses approve on S's R5; (b) chat 145, paired with another session S2, presses approve on R5 | Both get {"Only the paired chat can answer this request.", true}. R5 stays `pending`, with no audit entry | - |
| Unknown request (AC4) | A, `TestUnknown`. Chat 146, paired, presses `approve:` + an unused 22-character Ref, then `zz`, then `approve:` | Three answers {"That request is no longer available.", true} | - |
| No dry run | A, `TestApproveNoDryRun`. A request with no `DryRun` | One answer with no `text` and `show_alert` false. The row is `approved` | - |
| Edit in place (AC3) | O, `TestEditApproved`: a message with buttons for R is sent, then `answered` `answered.approved` {channel `telegram`, time t}. `TestEditOnlineDemo`: the same with `onlineDemo` 1 | Edits = [{message_id n, text = the sent text + LF LF + "Approved from Telegram at HH:MM."}], with no `reply_markup` (with `onlineDemo` 1 the status ends " ET."). A row of kind `answered`, the same id, `Text` the edited text | `onlineDemo` restored on every path |
| First answer stays; nothing to edit | O, `TestEditOnce`: (a) a second `answered` (`answered.expired`) for the same R; (b) `answered` for an R with no `telegram` row; (c) a row recorded with `Text` "" | No editMessageText call. (b) and (c) log one warning each, and the status is OK | - |
| Rejected follow-up (AC2) | O, `TestRejectedFollowUp`: `answered.rejected` {channel `telegram`} with `IncidentRef` set; the same with channel `web`; the same with no `IncidentRef` | The first: the edit (status "Rejected from Telegram at HH:MM. Nothing was changed."), then one sendMessage "Fix rejected. Nothing was changed. The incident stays open on your OcuTalon page." The other two: the edit only | - |
| Every copy shows who answered (AC2's 5 s; Integration: `Notify` -> `TelegramOut`, `SimPhoneOut` and `WebChatOut`) | A, `TestEveryCopy`. Demo mode on, chat 147 paired with S. Through `Notify` (12.6's host-service pattern): an `incident` notice with R, then `answered.approved` {channel `telegram`}, then `result.allThrough` {count 50} | Telegram and the phone each get the notice; Telegram has the buttons. Within 5 s of the `answered` send: the Telegram message is edited with the status, and the phone message's `Answer` is "Approved from Telegram at HH:MM.". Then one new chat message, "All 50 orders went through." | - |
| REL-2 step 5's Telegram part (AC5) | `telegram-approval.spec.ts` T8, on the demo-path stack after `01`-`08`: the README account pairs chat `84017734115` from its card, ends any incident left in progress, presses Break the feed, then presses Approve from the chat | See AC5 | `finally`: `Finish(saved)`, then `setTelegramIncluded(was)` |

</intent-contract>

## Code Map

**Lane A, edit (Epic 12's footprint unless marked):**
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls`:
  - class doc :3-40 (:22 says a press "is not answered, Story 12.7");
  - LOG parameters :81-115;
  - `Poll` :229 (already asks for `callback_query`);
  - `Handle` :294-311;
  - `HandleUpdate` :314-355 (the press's chat at :321-322, the `RecordChat` call, then the command dispatch: add the press branch there);
  - `Command` :357-376 (it returns "" for a press);
  - `Reply` :562-573, which shows how a reply goes out (through `Notify`);
  - `Included()` :586-591 (unchanged).
  - In's own Bot API wrapper is the `..Call(method, params, .httpStatus, .sc)` used by `Poll`.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls`:
  - class doc :1-25 (:25 "Buttons and the edit in place ... come with Story 12.7");
  - `KINDS` :58 (unchanged: `answered` gets its own branch before the KINDS check);
  - `OnNotification` :98-108, `Target` :111-128, `Deliver` :132-138;
  - `Recorded` :141-150 (passes `text` "" today);
  - `Send(chatId, text, .messageId, .sent)` :236-249: public and called by tests. Add optional trailing `markup` and `limit` arguments; keep the call shape;
  - `SendPart` :252-273: its 429 loop becomes a private `Post(method, params, .answer)` used by sendMessage and editMessageText (Rule 2).
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/Api.cls`:
  - `Call` :36 posts JSON, so `reply_markup` passes as an object;
  - `Split(text, limit)` :129, `LIMIT` :28, `Safe` :161.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` (Lane A's catalog class, AD-29. A footprint extension: outside Epic 12's paths, and not contended): add a new prefix `button.` with `button.approve` and `button.reject`. AD-32 puts a prefix in the class of the lane that owns its producer, and the producer is `TelegramOut`.
- `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls`:
  - `BeginPairing`/`EndPairing` (12.6), `QueueUpdates` :561, `PrivateMessage` :568, `TextsTo` :578;
  - `CallsOf(method)` :393, `WaitCalls` :404, `PairChat` :742, `Notifications(mark)` :772, `DropSessions`.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls`: `Start(.saved, botName, out)` :68, `Pair` :334, `Send` :341 (waits for a long poll, then queues), `Replies` :377, `Finish` :154.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramOut.cls`: helpers `MakeChat` :25, `SentTo` :35, `Outbound` :46, `Texts` :55; its fixture ids use the 85xx/86xx range.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramChat.cls`: `TestNotices`. Its `answered` assertion ("sends no sendMessage and records no telegram row") is a shared surface: `answered` now edits and records a row.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramIn.cls`: `TestPrivateOnly` :167 queues a private press `zz2` (:184), which is now answered with an alert. `TestMock.TestUpdateScenarios` (`TelegramMock.cls` :21-35) reads the `telegram-button-update` scenario.
- `web/e2e/demo-path/telegram-approval.spec.ts` (8 lines): one `notBuilt(..., '12.7')` at :8, which this story replaces.
- `web/e2e/demo-path/telegram-page.spec.ts`: T5 :716 (pairs from the card's code), T7 :1002-1054 (the template: `setTelegramIncluded`, `pointKeys`, `Start`, `signInReadmeLoaded`, `Pair`, `Replies`, the nested `finally`), `fixture()` :118.

**Called or read, never edited (Lane B or contended):**
- `Core/AnswersIn.cls` `FromTelegram` :56-82 (codes and slots in its doc :44-55; `TelegramCode` :86-120; an action outside `approve,reject` or a bad Ref gives `unknown` with an OK status).
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`:
  - `Answer` :277: the winner's action is `approve`/`reject` (:316); it audits through `Audited` :299;
  - `IsRef`.
- `Data/Delivery.cls`: `Record` :48 (it already takes `text`), `FindByApproval` :72. `Data/Ownership.cls` `DeliveryFor` returns the row. `Data/Pairing.cls` `Chat(chatRef)`.
- `Core/Rule/Notify.cls` :42-49 routes `answered` and `result` to `TelegramOut` while paired.
- `Watch/IncidentManager.cls` `AnswerNotice` :1176-1188 (keys `answered.approved`, `answered.rejected` {channel, time} and `answered.expired` {time}; `ApprovalRef` and `IncidentRef` set) and `ResultNotice` :1220.
- `Channel/SimPhone/Out.cls` `EditAnswered` :69-91: the sibling of the edit, including first-answer-stays.
- `Msg/Catalog/Core.cls`: `press.*` :52-79, `answered.*` :80-150. `Msg/Catalog.cls`: `Render` :51, `CHANNELNAMES` :41 (`telegram` = "Telegram"), and the " ET" time on the online demo :163.
- `ci/mock/mock.mjs`:
  - it serves `editMessageText` and `answerCallbackQuery` (`scenarios.mjs:43`), not `editMessageReplyMarkup`;
  - every call is recorded with its params (:552);
  - an edit returns a new counted `message_id` (:236), which the edit ignores;
  - `POST /_mock/telegram/updates` takes any update object (:347-361).
- `Test/Contract/Mock.cls`: `Calls()` :429, `Control` :417.
- `Test/Core/AnswersTelegramProduction.cls`: `WebSession` :164, `HeldRole` :174, `Request` :232 and `RemoveTaskWarnings` :247. These show the fixture requests a real answer accepts (private there: mirror them).
- `Test/Data/Fixture.cls`: `Approval` :108, `SetTelegramIncluded` :200. `Test/Bridge/AuditLog.cls`: `Now`, `Entries`. `Test/Demo/SimPhoneOut.cls` `TestThroughNotify` :634 (the Notify pattern).
- **The page, unchanged:**
  - `web/src/app/approvals/approval-view.ts:219-237` (`answered.approved` with `answeredChannel`) and `catalog.ts:127-131` (`telegram` -> "Telegram");
  - `rail-view.ts:310-316`: an answered request leaves the rail.
- `web/e2e/support/demo-path.ts` (helpers):
  - `pressBreakFeed` :481, `expectIncidentAwaitingApproval` :301, `newIncidentRef` :466, `incidentCardOf` :463;
  - `rejectOnPhone` :400, `dismissIncident` :595;
  - `phoneNotes` :60, `approvalRows` :61, `readmeSession` :114.
- `web/e2e/demo-path/07-failure-paths.spec.ts` leaves the replay's request pending; `08` runs after it.
- `web/scripts/demo-path-summary.mjs` :38-92: `telegram-approval` is a part of step 5. `docker/tests/test-demo-path-gate.sh` is hermetic: no change.
- `web/scripts/api-client-sources.test.mjs` :114-136 (Lane B): it pins the 12.7 part as `notBuilt`, and must flip (see Design Notes, "Edits outside Lane A").

## Tasks & Acceptance

**Execution (Part A):**
1. `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` (AD-29, AD-32): add `"button.approve": {"text": "Approve", "slots": {}, "source": "EXPERIENCE Message Catalog / Telegram / word-labeled buttons"}` and `"button.reject"` ("Reject"), in the same form.
2. `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls` (AD-14, AD-32):
   - `OnNotification` sends `answered` to a private `EditAnswered(request)`, before the KINDS check.
   - It builds the markup through a private `Keyboard(approvalRef)` for `incident`/`approval` with an `ApprovalRef`.
   - `Send` and `SendPart` take the markup (last part only) and the 3,840 limit. `Post` is shared by sendMessage and editMessageText.
   - `Recorded` takes the text, kept only when `approvalRef` is set.
   - `EditAnswered` follows the Boundaries, including the follow-up.
   - New LOG parameters: nothing to edit, an edit failed.
   - The class doc is rewritten to the contract, and :25 is dropped.
3. `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls` (AD-11, AD-32):
   - `HandleUpdate` calls a new private `Press(chatRef, query)` for a `callback_query`, after `RecordChat`.
   - `Press` parses `data`, calls `FromTelegram`, picks the key and `show_alert` from the Boundaries' table, renders, and calls `answerCallbackQuery` through `..Call`.
   - New LOG parameters: press not handed over, press not answered, render failed, not allowed.
   - The class doc describes the press and drops ":22 ... Story 12.7".
4. `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls`:
   - public `ButtonPress(chatId, name, messageId, data, id)`, beside `PrivateMessage`;
   - `EditsTo(chatId)`: the editMessageText params for that chat, in order;
   - `PressAnswers(mark)`: the answerCallbackQuery params since a mark;
   - `KeyboardTo(chatId)`: the newest sendMessage `reply_markup` for that chat.
   - The class doc names them.
5. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls`, each returning "" or a reason:
   - `Press(chatId, name, data, .queuedAt)` (as `Send`: wait for a long poll, then queue `ButtonPress` for the newest message with buttons);
   - `Buttons(chatId, .data)` (a JSON array of the newest keyboard's callback data);
   - `Edits(chatId, .texts)`, `PressAnswers(.answers)`;
   - `Audit(ref, chatId, name, .found)`: the Approval audit entry of `ref`, as JSON {channel, holdsChatId, holdsName}, read through `Test.Bridge.AuditLog`.
6. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramOut.cls`:
   - new tests: `TestButtons`, `TestNoButtons`, `TestEditApproved`, `TestEditOnlineDemo`, `TestEditOnce`, `TestRejectedFollowUp`;
   - each covers its Matrix row. They use unused 86xx ids and give the chat row a session by SQL, on fixture rows only, as 12.6 did.
7. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramApproval.cls` (new; `shard:lane-a@Channel` takes it with no `ci/units.sh` change):
   - **Setup:** `OnBeforeAllTests` runs `BeginPairing` (chats 140-147). `OnAfterAllTests` folds `EndPairing`'s status into the class status (12.6's review patch).
   - **Tests:** `TestApprove`, `TestReject`, `TestLate`, `TestExpired`, `TestNotPairedChat`, `TestUnknown`, `TestApproveNoDryRun`, `TestEveryCopy`, as in the Matrix.
   - **Helpers:** the session and role helpers mirror `AnswersTelegramProduction`'s private ones (Design Notes, Rule 2), and `RemoveTaskWarnings` runs on every path.
   - The class doc names what it pins and needs.
8. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramChat.cls` `TestNotices`: its `answered` check now asserts no sendMessage, one editMessageText of the `incident.withFix` message, and one `answered` row. `TestNoIdentity` is unchanged.
9. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramIn.cls` `TestPrivateOnly` and `TelegramMock.cls`: update any assertion that a private press makes no Bot API call. It now gets one `answerCallbackQuery` with `press.unavailable` and `show_alert` true; the group press still gets nothing.
10. `web/e2e/demo-path/telegram-approval.spec.ts`: replace `notBuilt` with T8, in `test.describe('approve from the paired Telegram chat (Story 12.7)')`, tagged `@floor`, `test.setTimeout(240_000)`, `test.use({ timezoneId: 'UTC', locale: 'en-GB' })`. The header names what it pins.
   1. **Set up:** `setTelegramIncluded(1)`, `Start(.saved, BOT, 1)`, `signInReadmeLoaded`, and pair `84017734115` from the card's code (T5's way).
   2. **Clear the way:** end any incident left in progress with `rejectOnPhone` and `dismissIncident` (07's way).
   3. **Raise:** `pressBreakFeed`. `expectIncidentAwaitingApproval` gives the request's `Ref` K.
   4. **Check the notice:** poll `Replies`/`Buttons` until the notice with buttons arrives. `Buttons` = [`approve:K`, `reject:K`].
   5. **Press:** `Press(..., 'approve:K')`.
   6. **Within 5 s of the press:**
      - the incident card's request reads "Approved from Telegram at HH:MM", with HH:MM read from the approval's answered time (`readApproval`, `web/e2e/support/iris.ts:788`);
      - the phone's note for K reads "Approved from Telegram at HH:MM.";
      - the rail has no `approvals:K` row;
      - `PressAnswers` holds "Approved. Repairing and resending 50 orders.";
      - `Edits` holds the notice + LF LF + "Approved from Telegram at HH:MM.".
   7. **Then** (no time bound): `Replies` gains "All 50 orders went through." after the edit. `Audit(K, ...)` gives channel `telegram`, with no chat id and no name.
   8. **`finally`:** `Finish(saved)`, then `setTelegramIncluded(was)`.

**Acceptance Criteria (Part A):**
- **AC1, the notice.** Given an approval request for a paired session, when `TelegramOut` sends its notice, then:
  - it is rendered from the notification's catalog key, with the dry run and "Details and trace: on your OcuTalon page.";
  - its last part carries the "Approve" and "Reject" buttons, whose callback data is `approve:<Ref>`/`reject:<Ref>`;
  - its Delivery row records the approval `Ref` (FR-8, FR-20, AD-14, AD-32, UX-DR113, UX-DR136, UX-DR156).

  Rows: "Buttons on a request notice", "No buttons", T8.
- **AC2, the first answer.** Given the paired chat presses Approve or Reject first, when `TelegramIn` hands the press to `AnswersIn.FromTelegram` with channel `telegram`, the `Ref`, the action and the `ChatRef`, then:
  - the request is answered on channel `telegram` by the session's IRIS user, and the audit entry names no Telegram identity;
  - the press is answered "Approved. Repairing and resending 50 orders." or "Rejected. Nothing was changed.";
  - the web chat card, the rail and the simulated phone show "Approved from Telegram at 14:15" (or the rejected status) within 5 seconds, which the browser spec checks against the mock on every CI run that runs `live:demo-path`;
  - after a Telegram rejection of a fix the chat also gets "Fix rejected. Nothing was changed. The incident stays open on your OcuTalon page." (FR-8, FR-9, FR-20, NFR-9, P30, AD-11, AD-17, AD-30, UX-DR76, UX-DR114).

  Rows: "Approve first", "Reject first", "Rejected follow-up", "Every copy shows who answered", T8.
- **AC3, the edit.** Given a request answered on any channel, or expired, when the `answered` notification reaches `TelegramOut`, then:
  - the Telegram message is edited in place: the buttons are removed and the last line becomes the status in message form ("Approved from Telegram at 14:15 ET." on the online demo);
  - a result follows as a new message (FR-8, FR-20, FR-25, UX-DR76, UX-DR79, UX-DR114).

  Rows: "Edit in place", "First answer stays", "Every copy shows who answered".
- **AC4, refused presses.** Given a press that is late, from a chat that isn't the session's paired chat, or for an unknown or cleared request, when `TelegramIn` handles it, then nothing changes, and the press gets an alert that stays until dismissed, with the Boundaries' texts (FR-8, FR-20, AD-11, AD-30, UX-DR114, UX-DR136). Rows: "A late press", "Expired", "Not the paired chat", "Unknown request".
- **AC5, REL-2.** Given the mocked Telegram API and a paired chat, when the REL-2 spec reaches step 5's Telegram part, then T8 runs with no skip. It presses Approve on the notice's button and sees:
  - the answered status on the chat card and the phone;
  - the edited Telegram message and "All 50 orders went through." in the paired chat;
  - the approval in the IRIS audit log with channel Telegram and no Telegram identity.

  `demo-path-summary` reports step 5 as passed (FR-8, FR-9, REL-1, REL-2, UX-DR101, UX-DR103).

**Part C (the online demo's texts, U-197, DW-501, DW-506) is not this story's:** it moved to Story 12.9 at the spec gate (Spec Change Log, 2026-11-02).

## Spec Change Log

- 2026-11-02, lead (Epic 12 runner, runner A), spec gate: the split is accepted (Part A only; the switch and Part C go to Story 12.9); the gated Part C block and its Verification lines are removed from this spec; the two edits outside Lane A are ruled and the `Delivery.Text` ask is a veto ruling (Design Notes, "Runner rulings at the spec gate"). DW-501 and DW-506 are re-owned to Story 12.9.

## Review Triage Log

## Design Notes

**Governing ADs:**
- **AD-4:** a press reaches `AnswersIn` with the chat row's `ChatRef` only. The chat id and name stay in the `Pairing` row and never reach the audit, a log or a message.
- **AD-11:** `AnswersIn` resolves the session from the chat's live pairing, and `Approval.Answer` makes the first answer win. `TelegramIn` turns the result code and its slots into the press's answer.
- **AD-14:** inline buttons carry an approval `Ref`. `TelegramOut` records its Delivery rows, and finds the message to edit by `FindByApproval`'s row, whose id `<ChatRef>:<message_id>` keeps the edit in its own chat.
- **AD-16:** the approve answer's count and noun come from the stored dry run (through `FromTelegram`'s slots).
- **AD-17:** `Approval.Answer` is the audit writer, and it is unchanged.
- **AD-22:** throwaways and the CI mock only.
- **AD-29 and AD-33:** Lane A files only, apart from the three edits that need the ruling (below). The new `button.` keys go in Lane A's `Catalog.Watch`.
- **AD-32:**
  - Buttons go only on `incident`/`approval` with an `ApprovalRef`.
  - `TelegramIn`'s `answerCallbackQuery` is the one sanctioned render outside an `*Out`, and every text comes from `Catalog.Render`.
  - Its "Prevents" line ("notices ... in Telegram without Approve and Reject") is met from this story.
- **For Part C:** AD-3 (the splash reads only `Data.Public.Settings`) and AD-19 (the fixed public keys).
- **AD contradictions and tripwires:** apart from the pre-answered U-197, no AC contradicts an AD's Rule. NFR-9's "within 5 seconds" is measurable as worded, so no Rule 5 tripwire applies.

**Proposed split (the story as written is three independently shippable goals; the runner decides at its spec gate):**
- **This spec, Story 12.7 (Part A, plus the gated Part C):** buttons, presses, alerts, the edit in place, the follow-up, the 5-second check and REL-2 step 5's Telegram part. Everything is proved on the mock with the seam on.
  - It must come first: AD-32's "Prevents" line forbids a released Telegram notice without buttons, so the switch cannot precede it.
- **Sibling Story 12.9, "Telegram is included: the switch, the README and the release checks" (planned next):** it makes `Included()` return 1 (`In.cls:586-591`). In the same change it adds the README's `## Telegram` section, which must have that heading so its slug is `telegram`:
  - creating a bot with BotFather and turning groups off;
  - setting `TELEGRAM_BOT_TOKEN` in `.env` and restarting;
  - one bot per OcuTalon.

  It appends "You can approve it in Telegram on your phone, without a laptop or the Management Portal." to the first item of "What you can use it for" (README.md:24, adding to the line, not rewriting it). It then updates `docker/tests/test-readme.sh`: `ITEM1` :116-117 and its self-tests :801-811; the `no-telegram` and `#telegram` skips at :653-668 and :693 open by themselves.

  It also repairs every test that assumed "not included":
  - `Test/Msg/Contracts.cls:125-135` (contended, Epic 40);
  - `Test/Web/Api.cls:444-446` and `:1243-1248`, `Test/Web/PairingApi.cls:97-109`;
  - `Test/Core/SessionOps.cls:353,360` (contended);
  - `Test/Core/Routing.cls:198-205` and `:262-266`, `Test/Demo/Guide.cls:245-249`;
  - `Test/Channel/TelegramSwitch.cls:102-135`;
  - `Test/Core/SessionOpsProduction.cls` and `AnswersTelegramProduction.cls:122-127`;
  - `web/e2e/api/pairing.spec.ts:71-76`, `api.spec.ts:144-145`, `rail/rail.spec.ts:114` and `demo-path/01-page.spec.ts:118`;
  - `docker/tests/test-production-restart.sh` :132, :160-166 and :179.

  It decides how CI starts behave when every stack now enables `TelegramIn` against the mock with the dummy token (`ci/compose.ci.yml:21-22`; `BotApi.Reset` refuses while a `TelegramIn` job is live, DW-370). It turns on Story 11.2's pairing family in `release/upgrade-harness.sh`:
  - `seed_pairing` and `check_pairing_restart` from 1.0.0 (stubs at :768-771, the `HARNESS_OFF` text at :52-57, callers at :1024, :1340 and :1423, pins in `docker/tests/test-upgrade-harness.sh:439-512`);
  - with "the pairing still receives notifications afterwards";
  - leaving `check_pairing_upgrade` off with its row text "joins from the release after 1.0.0". No stub is needed for the upgrade part now.

  It turns on Story 16.3's online case, `web/e2e-online/resume.spec.ts:190` R2c (the rail's card shows R2b's fixture pairing "Zz chat"; the card renders once `telegram.included` is true). Under U-197 option (b) it also carries the splash change (below).
- **If the runner wants a smaller first story,** Part C moves whole to its own sibling, Story 12.10, "The online demo's texts follow Telegram", with no change to Part A.

**Runner rulings at the spec gate (2026-11-02; the orchestrator ruled the cross-epic questions):**
- **Split (U5 decide, accepted by the orchestrator):** this story is Part A only. Story 12.9, "Telegram is included" (inserted in `epics.md` under Epic 12), takes the switch, the README, Story 11.2's harness pairing family, Story 16.3's online case and Part C (the splash and banners, DW-501 and DW-506, re-owned to `12-9-telegram-is-included`). Part C's design as planned here (Tasks C1-C5 and its acceptance criteria) is in this spec's first committed version (git history of this file) and is input to Story 12.9's plan. U-197's mechanism waits on the Contest Planner (inbox U-219); only Story 12.9's splash and banner part waits on it.
- **Edit 1, `Test/Msg/Catalog.cls` (contended, Epic 40), orchestrator ruling option (i):** add `button.approve` and `button.reject` to Lane A's `Msg/Catalog/Watch.cls` and make the four edits in `Test/Msg/Catalog.cls` (header, the Watch count lines 24 to 26, the total 119 to 121, the two keys and fixtures in XData `Keys` and `Fixtures`). Whichever epic merges second resolves the total by adding the deltas. Touch no other line of that file.
- **Edit 2, `web/scripts/api-client-sources.test.mjs` (Lane B, not contended):** allowed; the pin flip as described.
- **Ask 3, `Delivery.Text` (veto ruling, inbox U-218):** storing the sent text of a Telegram message with buttons is allowed on three conditions: the schema is unchanged; the stored text is the phone copy's text, with no chat id; and the implement checks that every reader of `Delivery.Text` filters on channel `web`, and stops with `## Clarification Needed` if one does not. Lane B's doc line stays unedited.

**Pending orchestrator ruling (U-197): the telegramIncluded public key and AD-19**

*The mechanism the AC names (option (a)):* Part C's gated block.
- **Writer:** Lane A's `Install.Step.Public`, on every start (local too, so the key is never stale), as "1"/"0" from `Included()`. It is a structural value.
- **Reader:** only `OcuTalon.Web.Public.Splash`, through `Data.Public.Settings.Get` (AD-3 allows that). The signed-in banners need no public key: they read `/state`'s `telegram.included`, which Lane B already serves (AD-29).
- **Tests:** they pin both values of the key on the splash, in process and in a browser, and the key list in the three tests that hold it.

*(a) The proposed amendment of AD-19's Rule.* In the bullet "Public settings live only in `^OcuTalonPublic`", the key list becomes "... the message allowance per session per hour (shown on the splash), whether the release includes Telegram, and readiness." A sub-bullet is added:

> "`telegramIncluded` ("1" or "0") is written on every start, local or online demo, by the `Public` step from `OcuTalon.Channel.Telegram.In.Included()` (Lane A), and read only by the splash (`OcuTalon.Web.Public.Splash`), which shows its Telegram line and the "chat or Telegram" allowance line only when it is "1" (Story 12.7). It is a structural value; `SettingsOps` never writes it."

Nothing else changes, and AD-3's allow-list is unchanged.

*(a') A variant.* Write the key from the Telegram step's own decision, `Included()` and a token set (`Install/Step/Telegram.cls:60-71`), instead of `Included()` alone. The splash would then promise a QR code only when this start actually has a bot, which matters on a demo host without a token: no repository file sets one for the online demo (inference from the search). This differs from the AC's wording "written from `Included()`".

*(b) The alternative that needs no AD amendment.* Story 12.9 makes `Included()` a code constant, 1. From then on no shipped build can have Telegram excluded, so a runtime key carries nothing a build can vary.
- **The splash:** in the same change as the switch (Story 12.9), the splash's Telegram line and the "chat or Telegram" allowance line return unconditionally (the C3 parameters, with no `If`).
- **The pin:** one Lane A test (`Test.Channel.TelegramSwitch`) asserts that `Included()` = 1 and the splash's rendered list contains both lines. If `Included()` ever returns 0 again, the test fails until the texts change.
- **The banners:** they keep their UX texts, which become true at the switch, so DW-501 and DW-506 close as `resolved-by:` Story 12.9. No new public text is needed (C5's `banner.resetSoonChat` is unspecified text, a veto-window item).
- **Cost:** no new key, no Lane B accessor change, no contended `Test/Install/Public.cls` edit, no new catalog keys and no banner code.
- **What it changes:** the AC's mechanism sentence would change ("through a public key `telegramIncluded`"), which is the orchestrator's to amend.

*(c) Recommendation: (b).*
- It is smaller (product default 6) and equally true for every build that can ship.
- It touches no contended file, and needs no unspecified public text.
- The AC's condition "with `Included()` 0 neither text mentions Telegram" stays pinned by the consistency test.
- Option (a) is worth its cost only if a future build must exclude Telegram at run time; option (a') only if the splash must follow the bot's presence on the demo host. Neither is in the PRD.

**Edits outside Lane A that need the runner's ruling (Part A):**
1. **`src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`** (contended: Epic 40 changes its key counts):
   - the header :3 ("24 of ... Watch") and `TestEntries` :81 and :83: 24 to 26;
   - the total at :121: 119 to 121;
   - XData `Keys`' watch list and `Fixtures` gain `button.approve` and `button.reject`, with {} slots and the texts "Approve" and "Reject".

   This cannot be avoided for any new key. The fallback if refused: `TelegramOut` keeps the labels as parameters pinned by a test, and the keys are routed to Epic 40's merge. That is worse, because it puts text in code.
2. **`web/scripts/api-client-sources.test.mjs` :114-136** (Lane B, not contended): drop the `['telegram-approval.spec.ts', 'approval', 4, '12.7', false]` entry, and assert for `telegram-approval.spec.ts` what :116-123 asserts for `telegram-page.spec.ts` (it has tests, and no `notBuilt`, skip or fixme). Update the header :6-9. The pin was built for this flip, and without it `npm --prefix web test` fails.
3. **Lane B ask (doc only, not edited here): `Data/Delivery.cls` `Text` :31-32.** Its doc says "empty for any other row". Telegram rows of a message with buttons now keep their sent text, so that the edit can rebuild it; `Record` already takes `text`.
   - This is a new use of an existing column, not a schema or format change.
   - The text equals the phone copy's, which `SimMessage` already stores, and it holds no chat id.
   - The implement stage checks that every reader of `Delivery.Text` filters on channel `web` (`Ownership.RecentNotices`); if one does not, it stops with a clarification.

**Decided in-stage:**
1. **The callback data form is `approve:<Ref>` / `reject:<Ref>`** (30 bytes, under the Bot API's 64). Anything else reaches `FromTelegram` as given and comes back `unknown`.
2. **Buttons go on the last part only.** A message with buttons is split at 3,840 units, so the status line always fits in the edit (the longest status is under 80 characters).
3. **The edited text** is the stored text + a blank line (LF LF, as 12.6's check sentence) + the status. "The final line becomes the answered status" (EXPERIENCE "Answered anywhere"), and the original lines are kept, as the phone keeps its message and puts the answered line where the buttons were (`EditAnswered`).
4. **The first answer stays:** the newest row of kind `answered` stops a second edit, as `SimPhoneOut` does. A message with no stored text (one sent before this story, with no buttons) is not edited.
5. **The follow-up goes only after a Telegram rejection of a fix** (`answered.rejected*`, channel `telegram`, `IncidentRef` set):
   - it is the Telegram table's row, and its text speaks of "the incident";
   - `TelegramOut` sends it as an `*Out` operation in the same handler, so no new route and no producer render are needed;
   - its row has `ApprovalRef` "", so `FindByApproval` still finds the request's message.
6. **Answers with no text, and the warnings:**
   - with no text and `show_alert` false: `approved` with no count, `not_allowed`, and a failed hand-over or render;
   - a warning for each of these except the first: the edit shows the status anyway, and step 6 owns `not_allowed`'s text.
7. **The REL-2 spec raises its own incident** (Break the feed once more, after ending the one `07` left pending). A Telegram notice reaches only a chat paired before the incident is raised. It depends on step 2's watch, as `05` and `07` do: REL-2 is one journey on one stack by design (AD-29). It asserts the watch rather than assuming it.

**Extend, don't copy (Rule 2):**
- **`EditAnswered`** mirrors `SimPhoneOut.EditAnswered` (Lane B, for another channel, with different storage): the same steps, with Telegram's API.
- **`Post`** is `SendPart`'s 429 loop, extracted and shared, not copied.
- **`Press`** is the press half of `AnswersIn.FromTelegram`'s contract. It extends `HandleUpdate`'s dispatch.
- **`TelegramApproval`** reuses `LiveCase` (`BeginPairing`, `PairChat`, `CallsOf`) and 12.6's Notify pattern.
  - Its session and role helpers copy `AnswersTelegramProduction`'s private `WebSession`/`HeldRole` (about 15 lines). That class is a Lane B test that Lane A does not edit, and making them public there would be a Lane B change, so the copy is the better choice.
- **`TelegramPageFixture.Press`** extends `Send`'s wait-then-queue shape.
- **T8** reuses T5's pairing, T7's `finally`, and 05/07's helpers.

**Integration ACs (Rule 1).** Each runs against the real production and the CI mock:
- `AnswersIn` and `Approval.Answer` consume `TelegramIn`'s press: the row, the audit, and the answer text (`TestApprove`).
- `TelegramOut` and `SimPhoneOut` consume `Notify`'s `answered`: both copies are edited within 5 s (`TestEveryCopy`).
- The page consumes the answer through the real chain (T8).

**Consumes:** from Lane B:
- `AnswersIn.FromTelegram` (10.3), `Delivery.Record`/`DeliveryFor` (2.7), `Notify` and `Rule.Functions`;
- `IncidentManager`'s `answered` and `result` notices (5.5, 7.3);
- `Catalog.Render` and the `press.*`/`answered.*` keys;
- the page's approval views;
- the mock's Bot API (`answerCallbackQuery`, `editMessageText`).

From Stories 12.2-12.6: `TelegramIn`'s dispatch, `TelegramOut`'s `Send`/`Target`, `LiveCase`, and `TelegramPageFixture`.

**Consumed-by:**
- **12.9:** the switch, the harness pairing family and R2c.
- **31.3 and 31.4:** the online demo's Telegram cases.
- **26.4:** `not_allowed`'s alert.
- **38.3:** the owner's real-bot pass and the 20 timed approvals (moved there by the owner's decision of 2026-10-31; this story touches no real bot).

**Owned ledger (Rule 17):** none after the spec gate: DW-501 and DW-506 were re-owned to `12-9-telegram-is-included` with Part C (`by=spec_gate`). As planned:
- **DW-501** (the allowance banner) is addressed by Part C's C5 under option (a). Under the recommended (b) it is resolved by the switch in Story 12.9, and the runner re-owns it there.
- **DW-506** (the reset-soon banner) is the same: C5 under (a), and Story 12.9 under (b).

**Footprint (Rule 11; report under `footprint_extensions:`):** `Msg/Catalog/Watch.cls` (Lane A, outside Epic 12's paths), the two ruled edits above, and, under Part C, its files. No `ci/units.sh`, mock, `README.md` or other contended file is touched.

**Cost (inference until measured):**
- `TelegramApproval` takes about 45-70 s: 6 fixture answers that each wait 5 s, plus `TestEveryCopy`. `TelegramOut` grows by about 3 s.
- The CI group that runs `shard:lane-a@Channel` (`production`, per Story 12.6) grows by about 1 min on the runner.
- T8 takes about 60-90 s locally (Break the feed and a diagnosis on the mock), which makes `browser` about 3 min longer on the runner.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=12 stage=<stage>'`, run from the worktree root.

**How to run:**
- **Calls:** one command per foreground call, with `timeout: 600000`. Never two IRIS test runs in one message.
- **Tags:** implement `e12s7i`/`e12s7iw`, QA `e12s7q`/`e12s7qw`, review `e12s7r`/`e12s7rw`. Each stage tears down only its own tags, also after a failure.
- **Targets:** tests never run on a slot. An IRIS MCP call, if one is needed, names `server: ocutalon-slot-a` and `namespace: OCUTALON`, after `iris_server_info`.

**Commands:**
- (loop) `npm --prefix web test`. Expected: every `scripts/*.test.mjs` passes, `api-client-sources` included (after the ruled flip).
- (loop) `npm --prefix web run lint`. Expected: clean.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s7iw ci/warm.sh up`, once per stage.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e12s7iw ci/iris.sh class <Class>`, one call per class:
  - `OcuTalon.Test.Channel.TelegramApproval`, `TelegramOut`, `TelegramChat`, `TelegramIn`, `TelegramMock`, `TelegramPair`;
  - `OcuTalon.Test.Core.AnswersTelegramProduction`, unchanged, as a regression;
  - `OcuTalon.Test.Msg.Catalog`.

  Expected: `CLASS ... passed` for each.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s7iw ci/warm.sh down`, at the stage's end, also after a failure.
- (once) `<lane> OCUTALON_RUN_TAG=e12s7i ci/iris.sh build`, before the first browser unit.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s7i ci/iris.sh live demo-path`. Expected: no FAIL line, T8 passed with no skip, and the summary line `STEP 5 approval: passed`. If the unit dies of its deadline with no failed test, re-run it with `OCUTALON_LIVE_DEADLINE=900`.
- (once) The fresh-environment check, one call each: `<lane> OCUTALON_RUN_TAG=e12s7i ci/iris.sh shard lane-a@Channel --part 1/2`, then `--part 2/2`, then both with `--reverse`. Expected: every Channel class passes in both orders. Use `--part k/3` if a part nears 8 minutes.
- (once) `<lane> OCUTALON_RUN_TAG=e12s7i ci/iris.sh class OcuTalon.Test.Msg.Catalog`, on a fresh stack.
- (once) One per call: `bash docker/tests/test-mock.sh`, `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-boundaries.sh`, `bash ci/checks.sh`.
- (once) Write the changed paths to a file in the stage's scratchpad subfolder, run `bash ci/changes.sh ci.yml --paths-from <file>`, and record the groups.
- (once) `<lane> OCUTALON_RUN_TAG=e12s7i ci/iris.sh teardown`.
- (once) `git status --short -- src/ocutalon/cls/OcuTalon/Core src/ocutalon/cls/OcuTalon/Data src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls src/ocutalon/cls/OcuTalon/Msg/Catalog.cls src/ocutalon/cls/OcuTalon/Watch src/ocutalon/cls/OcuTalon/Web src/ocutalon/cls/OcuTalon/Live src/ocutalon/cls/OcuTalon/Channel/WebChat src/ocutalon/cls/OcuTalon/Channel/SimPhone src/bridge web/src web/e2e/support ci/units.sh ci/mock/mock.mjs ci/mock/scenarios.mjs ci/mock/test README.md`. Expected: it prints nothing. Part C, when it is ruled in, adds its own files.
- **Left to CI (Rule 23):** `production` (`shard:lane-a@Channel`), `browser` (`demo-path`), and the groups `ci/changes.sh` selects. Record `TelegramApproval`'s seconds, T8's seconds, and the `iris (browser)` minutes.

**Shared surfaces:**
- **TelegramIn's handling of a press** now answers it: `TelegramIn.TestPrivateOnly` (the private `zz2`) and `TelegramMock.TestUpdateScenarios` are updated.
- **TelegramOut:**
  - request notices carry `reply_markup`, and their Delivery rows keep `Text`;
  - `answered` now edits and records an `answered` row (`TelegramChat.TestNotices`, and 12.6's mutation line "AC4, answered");
  - a message with buttons splits at 3,840 (`TestLongNotice` sends `tellnow`, so it is unchanged).
- **The catalog's key lists and counts:** Watch 24 to 26, total 119 to 121 (`Test.Msg.Catalog`).
- **REL-2's step summary:** step 5 goes from "partly skipped (Story 12.7 ...)" to passed, and `api-client-sources.test.mjs`'s part list changes.
- **The demo-path stack's README session:** T8 pairs and unpairs a chat (`Finish`), and leaves one more incident, resolved. `telegram-page.spec.ts` runs after it and starts from an unpaired README session (each `Finish` drops its Pairing rows).
- **Delivery rows of channel `telegram`** gain `Text` and rows of kind `answered`. Every reader of `Delivery.Text` must filter on channel (checked as above).
- **The mock's global Bot API state** is reset by `Ready`/`Finish`. Every new test arms nothing it does not clear.
- **Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**Pinning mutations (Rule 19).** Each is applied, seen red, and reverted byte for byte (`cmp` against the stage's own backup; `git status --short` and `git diff --stat` unchanged). It is then recorded as `mutation: ... -> ...`.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC1, buttons | `Keyboard` not called | `TestButtons`; T8 (`Buttons` empty) |
| AC1, the Ref | The callback data carries a counter, not the Ref | `TestButtons`; `TestApprove` (unknown) |
| AC1, last part | Markup on every part | `TestButtons` (5,000-character case) |
| AC1, kinds | Buttons on `incident` with no `ApprovalRef` | `TestNoButtons` |
| AC2, hand-over | `Press` passes the chat id, not the `ChatRef` | `TestApprove` (`not_paired`) |
| AC2, answer text | `press.rejected` rendered for `approved` | `TestApprove` |
| AC2, follow-up | No follow-up | `TestRejectedFollowUp` |
| AC2, 5 s | `TelegramOut.EditAnswered` hangs 6 s | `TestEveryCopy`; T8 |
| AC3, edit | A `reply_markup` is sent with the edit | `TestEditApproved` |
| AC3, first stays | The `answered`-row check removed | `TestEditOnce` (a) |
| AC4, alert | `show_alert` false for refusals | `TestLate`, `TestExpired`, `TestNotPairedChat`, `TestUnknown` |
| AC4, late key | `already_answered` always renders `alreadyApproved` | `TestLate` (the rejected-winner case) |
| AC5 | `telegram-approval.spec.ts` keeps `notBuilt` | `api-client-sources.test.mjs`; the demo-path summary |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
