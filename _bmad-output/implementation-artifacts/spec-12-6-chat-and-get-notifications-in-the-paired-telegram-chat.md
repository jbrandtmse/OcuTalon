---
title: 'Story 12.6: Chat and get notifications in the paired Telegram chat'
type: 'feature'
created: '2026-11-01'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-4, AD-14, AD-20, AD-22, AD-26, AD-28, AD-30, AD-32 and AD-33, and the Consistency Conventions rows HostData and Notice cards)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A paired chat's ordinary text gets no answer today (`TelegramIn.Other` quits for a paired chat), and `TelegramOut` delivers only by `ChatRef`. `Conversation`'s replies and every session notification carry a `SessionRef` and no `ChatRef`, so even though `Notify` already routes them to `TelegramOut`, nothing reaches the chat. `TelegramOut` also records no `Delivery` row, and it drops a reply's check results. So on Telegram, "is everything OK?" gets no status (DW-295).

Lane B already built everything else, and this story leaves it unchanged:
- `Conversation` takes an `Item` of channel `telegram`, queues it behind a running turn, saves the Turn's `Channel`, and sets the reply's `OriginChannel`.
- The page shows "via Telegram" for a turn of channel `telegram`, through `chat.message` and `/state`.
- `Notify` routes replies of a `telegram` turn, and every notification kind, to `TelegramOut` while the session is paired.
- `Allowance.TryConsume`, `Allowance.Notice`, `Trace.Join` and `Trace.Started`, and `Delivery.Record` are in place.

**Approach:**
- **`TelegramIn`:** a paired chat's text becomes the user's turn, through the steps that `WebChatIn` takes for a page message: the allowance, the day's thread, then an `Item` to `Conversation`. A refused message gets the one allowance notice instead.
- **`TelegramOut`:**
  - It finds the chat by `ChatRef`, else by the session's pairing.
  - It sends the kinds that the simulated phone shows, plus `allowance` and `pairing`.
  - It adds the reply's check sentence under a reply, built from the check key and rows the way the page builds it.
  - It records one `Delivery` row per message, with the Telegram message id.
- **Tests:**
  - A new IRIS class `Test.Channel.TelegramChat` drives the real chain against the CI mock.
  - `Test.Channel.TelegramOut` gains three tests.
  - `TelegramPair.TestNameOnlyWhilePaired` is updated.
  - `telegram-page.spec.ts` gains T7: a Telegram message shows "via Telegram" in the web chat.

## Boundaries & Constraints

**Always:**
- **A turn.**
  - The message is a `message` update from a private chat whose row had a `SessionRef` when `Row` read it, whose command is `other` (Story 12.5's `Command`), and whose `text` is not empty once trimmed.
  - `/start <code>`, a bare `/start`, `/help` and `/stop` keep Story 12.5's branches.
  - A paired chat's message with no text (a sticker, or a photo with a caption) gets no turn and no reply.
- **The steps of a turn**, in `WebChatIn.Accept`'s order (AD-20, AD-26, AD-30):
  1. The session row must exist (`Data.Session.RefIndexOpen`). If it does not: one warning, nothing sent.
  2. `Allowance.TryConsume(sessionRef, "telegram", text, .retryAt, .firstRefusal)`:
     - **Refused with a `retryAt`:** nothing is queued and no model is called. On `firstRefusal` only, TelegramIn sends `Notify` `Allowance.Notice(sessionRef, retryAt)` with `%SessionId` "" and `%SuperSession` = the session's `TraceRef`.
     - **Refused with no `retryAt`** (busy): one warning, nothing sent.
  3. `Trace.Join(sessionRef, .sc, now)`. A failed Join is one warning, and the turn goes on in a session of its own. `%SessionId` = the thread and `%SuperSession` = the session's `TraceRef`.
  4. One `OcuTalon.Msg.Item` to `Conversation` through `SendRequestAsync`, with:
     - a new `ItemId` (`Bridge.Ids.NewRef()`), `SessionRef`, `Channel` `telegram`, `Provenance` `user` and `Text` = the message's text as sent;
     - an empty `ClientId`, and `FromGuide` 0;
     - no chat id and no name anywhere in it.
  5. When Join gave "" with an OK status: `Trace.Started(sessionRef, <the send's %SessionId, or "" when the send failed>, now)`.
  6. A send that fails gives the entry back (`Allowance.Refund`) and is one warning.
  7. Afterwards, TelegramIn sets `%SessionId` and `%SuperSession` back to "". A later update of the same poll answer then starts its own trace session and carries no session's `TraceRef`.
- **The reply.** `Conversation` sends it to `Notify`, which sends it to `WebChatOut` and `TelegramOut`. TelegramIn sends no reply of its own to a turn.
- **`TelegramOut` finds the chat:**
  - by the message's `ChatRef` when it is set (every `pairing` notice, unchanged);
  - otherwise by `Data.Ownership.Pairing(SessionRef, .sc)`, the session's live pairing;
  - an owner that is not a session (`IsSession`) is dropped with `LOGNOTASESSION`;
  - no chat sends nothing, with 12.2's one `LOGNOCHAT` warning and status OK.
- **What `TelegramOut` sends:**
  - `Outbound`: the `Text`, else the rendering of its `CatalogKey`. When `CheckKey` is set and its sentence is not "", the text is followed by a blank line (two LF) and the sentence.
  - `Notification` of kind `tellnow`, `incident`, `approval`, `result`, `reminder`, `allowance` or `pairing`: the rendering of its `CatalogKey` for `telegram`.
  - Any other kind (`answered`, `status`, `digest`, `fallback`): nothing, and no row.
  - Every text goes through 12.2's `Send` (`Api.Split`, at most 4,096 UTF-16 units a part).
- **The check sentence (DW-295; AD-28; the spine's HostData row).** It mirrors `web/src/app/shared/check-sentence.ts` `checkSentence`/`whatFailed`:
  - `checks.allPassed`, `checks.everythingElsePassed` and `checks.nothingWatched` give the catalog text.
  - `checks.notEverything` and `checks.notEverythingRestPassed` are rendered with `whatFailed`, built from the rows:
    - which rows: every row whose `result` is not `passed` and whose `entry` is not empty, the `failed` rows first, then the others, each group in row order;
    - each row is `{entry} ({finding}, at {time})`. The finding's first letter is lower case. An empty part is left out: `{entry} ({finding})`, `{entry} (at {time})` or `{entry}`;
    - `{time}` is `Data.Time.ForMessage(checkedAt)`, plus " ET" on the online demo, which is what a `time` slot renders. As `Catalog.Fill` does, "at " becomes "on " before a dated time;
    - the rows are joined with "; ". When no row is left, the sentence is "".
  - Any other key, or a render error, gives "" with one warning, and the reply still goes. The rows never make an all-clear: only the key does.
- **`Delivery` (AD-14).**
  - After every part of a message that has a `SessionRef` is sent: `Delivery.Record(SessionRef, "telegram", ChatRef_":"_<message_id of the last part>, ApprovalRef, Kind, "", DecisionRef)`. An `Outbound` passes kind "" and approval "".
  - The `message_id` is the sendMessage answer's `result.message_id`, or "" when it has none. The last part is the one that Story 12.7's buttons and status line will edit.
  - A message with no `SessionRef` (a reply to an unpaired chat) records no row.
  - A failed `Record` is one warning, and the status stays OK: the message is never sent again.
- **Logs.** New log texts are parameters followed only by `Api.Safe` of a status text or an exception's name (AD-14). No chat id, name, code or message text appears in a log, a message, a live event or an audit entry.
- **Tests.** They run on throwaways and in CI only, against the CI mock and its dummy token:
  - the seam goes through `SetTelegramIncluded`, restored on every path;
  - `onlineDemo` and any allowance window the test filled are put back on every path;
  - the runner keys are pointed at the mock and restored as `Test.Schedule.ReminderChat` does;
  - fixture chat ids are `84017734130` to `84017734139` (IRIS) and `84017734114` (T7). `TelegramOut`'s new tests use unused ids of its own 85xx/86xx range;
  - fixture sessions are `zztg...`, and their Turn, Decision, Delivery, SimMessage and AI-session rows are removed at the end;
  - every IRIS script prints its `CHK|` lines on every path.

**Never:**
- **No edit to a Lane B class or file:**
  - `Conversation`, `Notify`, `Rule/Functions`, `Allowance`, `Trace`, `Data/*`, `Msg/*` (the catalog classes included), `Channel/WebChat/*`, `Channel/SimPhone/*`, `Checks/*`, `Web/*`, `Live/*`;
  - the web chat and every other `web/src/**` file;
  - `web/e2e/support/**`, `ci/mock/*.mjs`, `ci/mock/test/**`, `Test/Contract/Mock.cls`, `ci/units.sh`, `README.md`;
  - any contended file of the dispatch. `Agent/Chat.cls` stays untouched: DW-295 is met on Telegram's side.
- No new catalog key and no Telegram text written in code: every sentence comes from `Msg.Catalog.Render`. The row forms and the separator are the spine's HostData forms (vetoes U-110 and U-111).
- No inline buttons, and no edit in place (Story 12.7). No "Got it" button (UX-DR143 is step 2).
- `Included()` stays 0. No real bot, no call to `api.telegram.org`, no real token, no real model key.

## I/O & Edge-Case Matrix

These rows assume:
- **"C"** is a live IRIS test of the new `Test.Channel.TelegramChat`, under its `Begin`:
  - `TelegramIn` and `TelegramOut` are started against the mock, the seam is 1 and demo mode is on, as in `TelegramPair.Begin`;
  - the runner keys are pointed at the mock (`RunnerFixture.ReadyReason`/`PointKeys`);
  - S is a fresh `zztgchat...` session that its chat pairs with through the real `/start <code>` path.
- **"O"** is a direct test of `Test.Channel.TelegramOut` (`RunnerFixture.Send("TelegramOut", ...)`). Its chat row is given the fixture session's `Ref` by SQL, on fixture rows only.
- **"Texts(c)"** is `LiveCase.TextsTo(c)` after the work is done and 1 s has settled. PAIRED and NOTPAIRED are 12.4's and 12.5's literals.
- **Message ids.** After its reset, the mock numbers its default sendMessage answers 1, 2, 3, ... (`ci/mock/mock.mjs` `defaultAnswer`). So a message's id is its position among the sendMessage calls of `Mock.Calls()`.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| A paired chat's text is a turn (AC1, DW-295; Integration: `TelegramIn` -> `Conversation` -> `Notify` -> `TelegramOut` and `WebChatOut`) | C, `TestTurn`. Chat `84017734130`, "Zqchat", is paired with S. In one `/updates` call: (1) 130 sends "Is everything OK? [[mock:checks-false-all-clear]]", with the marker armed at 1 as `Test.Checks.Turns` arms it; (2) unpaired chat `84017734131` sends "zz hello" | One `Item` from TelegramIn to Conversation since the mark:<br>- the fields of "The steps of a turn" (step 4);<br>- its body holds neither "84017734130" nor "Zqchat";<br>- its header's `SessionId` is S's `ThreadSessionId` and its `SuperSession` S's `TraceRef`.<br><br>On S's side:<br>- one Turn of S with `Channel` `telegram` reaches `done`, and a `chat.message` event on S's stream has `channel` `telegram`;<br>- Notify sends the reply to WebChatOut and TelegramOut.<br><br>Texts(130) = [PAIRED, R]:<br>- R = the reply's `Text` + LF LF + the text of `checks.nothingWatched` (S watches nothing);<br>- R holds no "Everything I checked passed.".<br><br>Rows: one `telegram` Delivery row of S, `<ChatRef of 130>:<n>`, with n the id of R's last part; and WebChatOut's row of the reply.<br><br>The stranger: Texts(131) = [NOTPAIRED]. Its Notification's header has `SuperSession` "" and a `SessionId` that is not S's thread. | - |
| A refused message queues nothing (AC2; Integration: `TelegramIn` -> `TryConsume`, `Notify` -> `TelegramOut` and `WebChatOut`) | C, `TestRefused`. `onlineDemo` 1. S's window is filled to `Allowance.Limit()`, the way `Test.Core.AllowanceInProduction.Seed` fills it. Chat 132, paired with S, sends "zz over the limit", then "zz still over" | Two Turns of S: `State` `refused`, `Channel` `telegram`, no decision. No Item to Conversation, and no `/v1/messages` in the mock log since the mark.<br><br>One Notification from TelegramIn to Notify: kind `allowance`, key `conversation.sessionAllowance`, `SessionRef` S, no `ChatRef`. Notify sends it to WebChatOut and TelegramOut, and not to SimPhoneOut.<br><br>Texts(132) gains exactly one text, equal to `Catalog.Render` of that Notification's key and `Slots` for `telegram`. One `web` Delivery row of kind `allowance`. The second refusal adds nothing. | `onlineDemo` and the window are restored on every path |
| A message while a turn runs waits (AC3; Integration: `TelegramIn` -> `Conversation` -> the mock) | C, `TestQueued`. Chat 133, paired with S, sends "zz first [[mock:telegram-turn-held]]" (the new scenario, armed at 1). Once that Turn is `running`, it sends "zz second while the first runs" | While the first Turn is `running`, the second is `queued`, and it starts only after the first is `done`.<br><br>In the mock log since the mark, the second turn's chat requests:<br>- their newest user message is that turn's `Agent.Input` text (`RunnerFixture.Messages` starts "user:");<br>- the last of them carries a tool result (A/chat.json's `list_productions`);<br>- no tool result of any logged request holds "zz second while the first runs" (`RunnerFixture.ToolResults`).<br><br>Texts(133) = [PAIRED, the first reply, the second reply], in that order. | - |
| Every notice reaches the chat as the phone shows it (AC4, AC5; Integration: `Notify` -> `TelegramOut` and `SimPhoneOut`) | C, `TestNotices`. Chat 134 is paired with S. One at a time, waiting for each sendMessage, one Notification to Notify (`SuperSession` S's `TraceRef`) for each key K:<br>- **the Watch keys:** every `Msg.Catalog.Watch` key with prefix `incident.` or `result.`, read from its XData; there must be exactly 12;<br>- **the Core keys:** `notice.tellNow`, `notice.tellNowFallback`, `reminder.due`, `reminder.late`, `conversation.sessionAllowance` and `conversation.dailyCap`.<br><br>Each carries:<br>- its kind: `incident` for `incident.*` but `approval` for `incident.laterRequest`; `result`, `tellnow`, `reminder`, `allowance`;<br>- the `Slots` of `Test.Msg.Catalog`'s `Fixtures` XData for K;<br>- a fixture `ApprovalRef` on `incident` and `approval`.<br><br>Then one Notification of kind `answered` | For each key, the chat's new text:<br>- equals the text of the SimPhone message that the phone got for the same Notification (`Ownership.RecentPhone(S)`);<br>- for the two allowance keys, equals `Catalog.Render(K, slots, "phone")`, and the phone gets nothing.<br><br>For `incident.withFix`, the text holds `Data.Time.ForMessage(<its time slot>)` and not the slot's UTC string.<br><br>Rows: 18 `telegram` Delivery rows of S, each with the Notification's kind and `ApprovalRef` and `<ChatRef>:<n>`, n its message id.<br><br>The `answered` Notification: no sendMessage and no `telegram` row. | - |
| No Telegram identity outside the Pairing row (AC6) | C, `TestNoIdentity`. Marks are taken (headers, live events, `RunnerFixture.EventMark`, `AuditLog.Now`). Chat 135, "Zqhidden", pairs with S, sends "zz a quiet turn" (A/chat.json), and S gets a `notice.tellNow` and a `reminder.due` through Notify. An `Ens.Util.Log` probe holding both values is written, as in `TelegramPair.TestPairs` | None of these holds "84017734135" or "Zqhidden":<br>- the header rows since the mark;<br>- `Bodies(mark)`: Visual Trace's messages, the agent steps among them;<br>- `RunnerFixture.StepsOf` of the turn's two decisions;<br>- the event-log rows since the mark, the probe excepted;<br>- `AuditLog.Entries(since)`.<br><br>Each scan finds the probe (a positive control), and the Pairing row of 135 holds both values. | - |
| A session's message goes to its paired chat (Integration: `Ownership.Pairing` -> `TelegramOut`) | O, `TestBySession`:<br>(a) a `tellnow` Notification with `SessionRef` S and no `ChatRef`;<br>(b) an Outbound with `SessionRef` S and no `ChatRef`;<br>(c) the same for an unpaired session;<br>(d) owner `instance` | (a) and (b) go to S's chat. Each has a `telegram` Delivery row of S with `<ChatRef>:<n>`: (a) with kind `tellnow`, (b) with kind "".<br><br>(c) and (d) send nothing and return OK: (c) with one `LOGNOCHAT` warning, (d) with one `LOGNOTASESSION` warning, and neither records a row. | - |
| A long notice goes in parts (DW-30) | O, `TestLongNotice`. `notice.tellNow`, `SessionRef` S, with a `whatHappened` of 5,000 characters of words and no line break | 2 or more sendMessage parts, each at most 4,096 UTF-16 units. Joined, they equal `Catalog.Render` of the same key and slots. One Delivery row, with the id of the last part. | - |
| The check sentence follows the reply (DW-295) | O, `TestCheckSentence`. An Outbound with `SessionRef` S, `Text` "zz reply" and:<br>(a) `checks.notEverythingRestPassed`, rows [passed "Alpha"; not_checked "Beta", finding "Not run yet", no time; failed "Gamma", finding "Stopped", checkedAt 2 min ago];<br>(b) the same with Gamma checked 3 days ago;<br>(c) `checks.allPassed`, every row passed;<br>(d) `checks.notEverything` with only a passed row;<br>(e) a `CheckKey` "checks.nope" | (a) "zz reply" LF LF "Not everything: Gamma (stopped, at T); Beta (not run yet). Everything else I checked passed.", with T = `ForMessage` of Gamma's time.<br><br>(b) "... Gamma (stopped, on D) ...", with D the dated `ForMessage` text.<br><br>(c) "zz reply" LF LF "Everything I checked passed."<br><br>(d) "zz reply" alone.<br><br>(e) "zz reply" alone, with one warning. | - |
| A paired chat's other message is a turn (shared surface) | `TelegramPair.TestNameOnlyWhilePaired`, updated | Each of its paired chat's other messages makes one Item from TelegramIn to Conversation, and no `pairing` Notification. Its name assertions are unchanged. | - |
| The web chat shows the Telegram turn (AC1 on the page; T7) | T7, a new test: `Start(.saved, "ocutalon_pair_bot", 1)`, the README account signed in, and the link's code paired for chat `84017734114` ("Zqweb"). Then the fixture's `Send` sends "zz from my phone 12.6" | In the web chat, the user message with that text shows the caption "via Telegram". Its reply part (the same `data-key`) shows the mock's reply. `Replies(84017734114)` = [CONFIRMATION, that reply]. | - |

</intent-contract>

## Code Map

**Lane A's files (edit freely)**
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls`:
  - the class doc :3-40 (":34 A paired chat is not answered (the turns are Story 12.6's)");
  - `HandleUpdate` :281-318 (`Row` gives `sessionRef` before `RecordChat`; `Other(ref, sessionRef)` at :316);
  - `Command` :323-340, `Other` :414-418 (its `If sessionRef '= "" Quit` is the turn's branch point);
  - `Reply` :433-443, the LOG parameters :69-91.
  - The message's `text` is read in `Command`; the turn needs it too, so pass the message or its text on.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls`:
  - the class doc :1-11 (":11 Routing by SessionRef, Delivery rows and the message kinds come with Stories 12.6 and 12.7");
  - `OnOutbound` :51-60, `OnNotification` :63-69, `Deliver(chatRef, text)` :72-80;
  - `Send(chatId, text)` :83-94 is public and called by tests: add an `Output messageId` and keep the call shape;
  - `SendPart` :97-116 (the answer is `answer.result`);
  - `LOGNOTASESSION` :32 is already declared, and `IsSession` is inherited from `Channel.Operation`.
- `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls`:
  - `DropSessions` :324 (it deletes `zztg%` sessions, events and counters, but not their Turn, Delivery or SimMessage rows: extend it);
  - `PrivateMessage` :523, `TextsTo` :533, `QueueUpdates` :516 (private), `HeaderMark` :257, `Bodies` :286, `LiveMark` :308, `RowsText` :273, `Cleanup` :337, `Enable`/`StartItems` :114-160.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPair.cls`:
  - `Begin` :63-92 and `Ending` :93-108 (start, seam, demo check, chat list, items, state on, open poll);
  - helpers `NewSession` :110, `NewCode` :119, `Send` :129, `ChatRow` :144, `WaitLinked` :154, `Notifications(mark)` :166, `PairChat(chatId, name, session)` :197;
  - `TestPairs` :272 (its leak scans :328-345 and probe :287);
  - `TestNameOnlyWhilePaired` :364 (a shared surface).
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramOut.cls` (328 lines): `MakeChat` :25, `SentTo` :35, `Outbound` :46, `Texts` :55; tests :77-300.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls`: `Start(.saved, botName, out)` :68, `Pair` :334, `Send(chatId, name, text, .queuedAt)` :341, `Replies` :377, `Finish` :154.
- `web/e2e/demo-path/telegram-page.spec.ts` (972 lines):
  - header :9-29, `fixture()` :114, `railOf`/`cardOf`;
  - the 12.4 describe :687 (T5 :712, `CONFIRMATION`), the 12.5 describe :844 (T6 :897), `codeOf` :682.
  - Playwright runs it after `01`-`06` (path order, `workers: 1`).
- `ci/mock/scenarios/A/` (new file only): `telegram-turn-held.json`.

**Called, never edited (Lane B or contended)**
- `Channel/WebChat/In.cls` `Accept` :58-105, `Notify` :109-120: the sibling of the turn's steps.
- `Core/Allowance.cls`:
  - `TryConsume` :50 (off unless `onlineDemo` = 1, `Off` :251; records a refused Turn with the channel passed in, `Refused` :108);
  - `Notice` :204 (kind `allowance`, key `conversation.sessionAllowance`, no ChatRef), `Refund` :148, `Limit` :178 (setting `messageAllowance`).
- `Core/Trace.cls`: `Join` :39 ("" with OK keeps the Session row's lock until `Started`), `Started` :84.
- `Core/Conversation.cls`:
  - `Take` :164-193 (Turn `Channel` = the Item's; an empty ClientId is no duplicate);
  - `Start` :282-310 (the queue), `Tell` :568-587 (`OriginChannel` = `turn.Channel`, `CheckKey`/`CheckRows`, no ChatRef).
- `Core/Rule/Notify.cls` :22-50 and `Core/Rule/Functions.cls` :30-40 (`TelegramOn`, `TelegramPaired`).
- `Data/Ownership.cls` `Pairing(sessionRef, .sc)` :307, `RecentPhone`. `Data/Delivery.cls` `Record` :48 (message id format :17), `FindByApproval` :72. `Data/Session.cls` `ThreadSessionId` :36, `TraceRef` :22.
- `Msg/Catalog.cls`: `Render` :51, `RenderAt` :64; the `time` slot and the "at"/"on" rule are `SlotText` :152-165 and `Fill` :139-142 (private: mirror them, don't call them).
- `Msg/Catalog/Watch.cls`: the `checks.*` keys :49-76; `incident.*` and `result.*` :78-247 (12 keys).
- `Data/Time.cls` `ForMessage` :88.
- `Channel/SimPhone/Out.cls` :52-105 (CARDKINDS `tellnow,reminder,incident,approval,result`; renders for `phone`).
- `Checks/Render.cls` :36 (the row shape and the key choice).
- `web/src/app/shared/check-sentence.ts` :17-90: the sentence rule this story mirrors.
- `Agent/Chat.cls` (contended, unchanged): its check-status line says that OcuTalon shows the results under the reply. That is true on Telegram once this story ships.
- The test helpers:
  - `Test/Agent/RunnerFixture.cls`: `ReadyReason` :306, `PointKeys` :456, `RestoreKeys` :463, `KeysAre`, `WaitRecords`, `EventMark` :182, `LogRowsHolding` :190, `StepsOf` :335, `SessionMark` :863, `DropSince` :870, `FindRequests` :918, `Messages` :930, `ToolResults` :969, `Send` :262;
  - `Test/Contract/Mock.cls`: `LogMark` :471, `LogSince` :484, `Arm` :439, `Calls` :429;
  - `Test/Bridge/AuditLog.cls` `Now`/`Entries`;
  - `Test/Data/Fixture.cls` `SetTelegramIncluded`, `AdoptTurns` :281 and `Clean`;
  - `Test/Core/Observe.cls` `Events`/`WaitProcessed`;
  - `Test/Demo/SimPhoneOut.cls` `TestThroughNotify` :634 (the pattern for sending a Notification to Notify through a host service);
  - `Test/Core/AllowanceInProduction.cls` (`onlineDemo` and `Seed`);
  - `Test/Checks/Turns.cls` :20-32, :117 (the `checks-false-all-clear` marker armed at 1);
  - `Test/Schedule/ReminderChat.cls` :45-90 (key pointing, restore, `AdoptTurns`, `SessionMark`).
- `Test/Msg/Catalog.cls`: its `Fixtures` XData (read with `%Dictionary.XDataDefinition`; its own `Read` is private).
- `ci/mock/mock.mjs` :24-37 (selection, arming), :195-207 (`message_id` count); `ci/mock/scenarios/A/chat.json`, `checks-false-all-clear.json`, `turn-late.json` (the file form).
- The page: `web/src/app/chat/chat-view.ts:276` `captionOf` ("via Telegram" for channel `telegram`) and `web/e2e/chat/chat.spec.ts:89` (`[data-part="user"][data-key=...]`, `.when`). `web/e2e/support/floor.ts:52` `replyOf`.

## Tasks & Acceptance

**Execution:**
1. `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls` (AD-4, AD-14, AD-20, AD-26, AD-30):
   - `Other` takes the message's text. For a chat that was paired when read, and a text that is not empty once trimmed, it calls a new private `Turn(sessionRef, text)`. A paired chat with no text still gets no reply.
   - `Turn` takes the Boundaries' steps 1-7. Make it one private method plus small private seams (`Allowed`, `Notify`, `SendTurn` and `Refund`) shaped like `WebChatIn`'s, so a test can read each step.
   - New LOG parameters: no session row, a busy allowance, the notice not sent, a failed Join, a failed `Started`, and a failed send.
   - The class doc drops "the turns are Story 12.6's" and describes the turn.
2. `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls` (AD-14, AD-28, AD-32):
   - One private `Target(request, .chatRef, .chatId)` gives the chat by `ChatRef`, else by `Ownership.Pairing(SessionRef)`. It is used by both handlers.
   - `OnNotification` sends only the Boundaries' kinds.
   - `OnOutbound` adds the check sentence through a private `CheckSentence(key, rowsJson)` and `WhatFailed(rows)`.
   - `Send` returns the last part's message id. A private `Recorded(...)` writes the Delivery row.
   - The class doc covers the routing, the kinds, the sentence and the rows, and drops ":11".
3. `ci/mock/scenarios/A/telegram-turn-held.json` (new, in Story 10.3's form):
   - `match` `{"marker": "telegram-turn-held"}`;
   - `replies`: [the triage JSON of `checks-false-all-clear`'s first reply with `delayMs` 3000, then `{"status": 200, "text": "The CI mock answers the first Telegram message."}`].
   - It is armed at 1 by the test, so the triage request gets the held reply and the Chat request the text.
4. `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls`:
   - Move `TelegramPair.Begin`'s body and `Ending`'s body into public class methods `BeginPairing(chats, .reason)` and `EndPairing(...)`, which `TelegramPair` and `TelegramChat` both call. Also move `PairChat` (Rule 2).
   - `DropSessions` also deletes the `zztg%` sessions' Turn, Delivery and SimMessage rows.
   - The class doc says so.
5. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPair.cls`:
   - `Begin`/`Ending`/`PairChat` call LiveCase's, with unchanged behaviour.
   - `TestNameOnlyWhilePaired` asserts the row "A paired chat's other message is a turn". Its turns end in the runner's `no_key` fallback, because this class points no keys: its texts assertions wait for those replies, or exclude them.
   - `Ending` also removes those turns' Turn and Decision rows, with `Fixture.AdoptTurns`/`Clean` as `TelegramChat` does.
6. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramChat.cls` (new; `shard:lane-a@Channel` takes it with no `ci/units.sh` change):
   - **Setup:** `OnBeforeAllTests` runs `BeginPairing` with chats 130-135, `RunnerFixture.ReadyReason` and `PointKeys`. `OnAfterAllTests` runs `RestoreKeys`, `KeysAre`, `WaitRecords`, `Fixture.AdoptTurns`/`Clean`, `EndPairing` and `DropSince(SessionMark)`, following `ReminderChat`.
   - **Tests:** `TestTurn`, `TestRefused`, `TestQueued`, `TestNotices` and `TestNoIdentity`, as in the Matrix.
   - **Helpers:** a wait for S's newest Turn by `ItemId` or `State`, since a Telegram Turn has no ClientId; `Items(mark)` (the TelegramIn -> Conversation bodies); `ToNotify(notification)` (`TestThroughNotify`'s host-service pattern); `Rows(session, channel)` (Delivery).
   - The class doc names what it pins and needs.
7. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramOut.cls`: `TestBySession`, `TestLongNotice` and `TestCheckSentence`, as in the Matrix. The existing tests stay green unchanged, since their messages carry a `ChatRef`.
8. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls`: no change is expected; `Send` and `Replies` exist. If T7 needs a reader for the turn's reply, add one method in the file's style (it returns "" or a reason).
9. `web/e2e/demo-path/telegram-page.spec.ts`:
   - The header names T7.
   - **T7** goes in a new `test.describe('chat and notifications in the paired Telegram chat (Story 12.6)')`, tagged `@floor`, with `test.setTimeout(120_000)`. It covers the row "The web chat shows the Telegram turn".
     - Its locators are local (the user part as in `chat.spec.ts:89`, and `replyOf` from `support/floor`).
     - Its `finally` calls `Finish(saved)` and then `setTelegramIncluded(was)`, nested as in T5.

**Acceptance Criteria:**
- Given a paired chat, when it sends a text message, then:
  - `TelegramIn` calls `Allowance.TryConsume` with channel `telegram` and joins the session's day thread;
  - it sends `Conversation` one `Item` with the session's `SessionRef`, channel `telegram` and provenance `user`, holding no chat id or name;
  - the reply reaches the chat and the web chat, and the web chat shows the user's message with "via Telegram" (FR-20, FR-15, AD-4, AD-14, AD-20, AD-26, AD-30, UX-DR18, UX-DR59).

  Rows "A paired chat's text is a turn" and "The web chat shows the Telegram turn".
- Given a paired chat whose session's allowance is used up, when it sends a text and the real `TryConsume` refuses it, then:
  - `TryConsume` has recorded the refused Turn;
  - nothing is queued and no model is called;
  - the first refusal of the window sends the one allowance Notification, which reaches the paired chat and the web chat, and later refusals send nothing (FR-20, FR-40, AD-20, UX-DR96).

  Row "A refused message queues nothing".
- Given a Telegram message that arrives while a turn of the same session runs, when `Conversation` takes it, then it queues as the next turn and reaches the model as the user's own message, never inside a tool result, which the test reads in the requests the mock received (FR-20, NFR-6, AD-30). Row "A message while a turn runs waits".
- Given a notification for the session of any kind the AC names, when `Notify` routes it, then:
  - `TelegramOut` sends it to the paired chat, rendered from the catalog with times in the instance's zone and identical to the simulated phone's text;
  - it records its `Delivery` row with `<ChatRef>:<message_id>`;
  - a test compares the two key by key over every `Catalog.Watch` notice key and the Core notice keys (FR-20, FR-24, FR-25, FR-34, AD-14, AD-32, UX-DR108, UX-DR112, UX-DR115, UX-DR155, UX-DR156).

  Rows "Every notice reaches the chat as the phone shows it" and "A session's message goes to its paired chat".
- Given a Telegram turn, a pairing and several notices, when a test searches the production messages, Visual Trace, the agent steps, the event log and the IRIS audit log, then none holds the chat's Telegram id or display name, and only the Pairing row does (FR-15, FR-3, FR-9, AD-4). Row "No Telegram identity outside the Pairing row".
- DW-30: Given a rendered notice longer than 4,096 characters, when `TelegramOut` sends it, then it goes in parts of at most 4,096, which together are the whole text. Row "A long notice goes in parts".
- DW-295: Given a reply with check results, when it reaches Telegram, then OcuTalon's own check sentence follows it, built from the key and rows as the page builds it, so "is everything OK?" gets a status on Telegram, and only the code-chosen key can give an all-clear (AD-28). Rows "The check sentence follows the reply" and "A paired chat's text is a turn".

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs:**
- **AD-4:** the chat's id and name live only in its `Pairing` row. The turn's `Item` and every notice refer to the session by `SessionRef`, and to the chat only by `ChatRef`, and only inside `TelegramOut`'s Delivery id. The display name still travels to the session's own page (`/state`, the `pairing` event), as 12.4 pins; AC6 searches only the stores it names.
- **AD-14:** a paired chat's text has provenance `user`. `Notify` is the one router, and it is unchanged. `TelegramOut` records its Delivery row with `<ChatRef>:<message_id>`.
- **AD-20:** `TryConsume` comes before anything is queued. On a refusal the channel service sends the allowance notice once.
- **AD-26:** `Trace.Join` comes at the start of the turn. `%SessionId` and `%SuperSession` are set before the turn's first send, and cleared after it, because one `OnProcessInput` handles several updates.
- **AD-28:** the check sentence is a catalog entry rendered by an `*Out` operation. Only the key that `Checks.Render` chose can say that everything passed. The spine's HostData row fixes the `whatFailed` forms.
- **AD-30:** `TelegramIn` sends the user's text to `Conversation`, which alone owns the queue.
- **AD-32:**
  - Producers never render, and `TelegramOut` renders through `Catalog.Render` for `telegram`, whose text is the phone's.
  - AD-32's "Prevents" line also rules out a notice in Telegram without Approve and Reject, and the buttons are Story 12.7's. That line holds for every released build, because `Included()` stays 0 until 12.7 adds the buttons in the same release.
- **AD-22:** throwaways and the CI mock only.
- **AD-33:** only Lane A files change.

No AC contradicts an AD's Rule. The NFR-like phrases are measurable as worded ("identical", "the instance's zone", "within 4,096"). No Rule 5 tripwire.

**The TryConsume test double is moot.** AC2's "tested with a TryConsume test double until Story 16.9 merges" no longer applies: Story 16.9 is `done` on the feature branch, and its tests are active here (`Test/Core/Allowance.cls` `TestTelegramFixtureIsRefusedTheSameWay` :138). `TestRefused` uses the real `TryConsume`, turned on by `onlineDemo` = 1. Story 31.3's "turns on Story 16.9's Telegram cases" means the online-session shell row 4 (`docker/tests/test-online-session.sh:336`) and `web/e2e-online/session/leave.spec.ts:351` L6. They are 31.3's, and this story builds the path they need.

**Footprint (Rule 11; report under `footprint_extensions:`):**
- Lane A, in Epic 12's footprint:
  - `Channel/Telegram/In.cls` and `Out.cls`;
  - `Test/Channel/LiveCase.cls`, `TelegramPair.cls`, `TelegramOut.cls`, the new `TelegramChat.cls`, and `TelegramPageFixture.cls` (only if needed);
  - `telegram-page.spec.ts`;
  - the new `ci/mock/scenarios/A/telegram-turn-held.json`: a new file in Lane A's scenario folder, used only by the Telegram tests. Report it as a footprint extension, because the footprint names "Telegram mock scenarios" and this one answers a model request.
- No Lane B file is edited, not even by entry: no new UX string and no source pin.
- No contended file is edited. `Agent/Chat.cls`, `Data/Pairing.cls`, `Test/Data/Fixture.cls`, `Test/Agent/RunnerFixture.cls`, `Test/Checks/Turns.cls` and `Test/Schedule/ReminderChat.cls` are called or read only.
- **No "Needs ruling" item, and no part set aside (U14).** DW-295 is met in `TelegramOut`, as the ledger's routing note says ("12.6 renders the reply's check key and rows on Telegram"), so `Agent/Chat.cls` needs no change and nothing waits for Epic 11.

**Decided in-stage:**
1. **What a turn is.** It is any text from a paired chat that is not 12.5's `/start`, `/start <code>`, `/help` or `/stop`, unknown commands included, since the user's text is their own turn. Text that is empty once trimmed, and a message with no text, make no turn. That follows `WebChatIn`, which refuses an empty text, and 12.5, which answers a paired chat's non-text message with nothing.
2. **No ClientId on a Telegram Item.** The kept offset (12.2) already guarantees no repeated update. A synthetic id would enter the page's `clientId` matching, so the Item carries none.
3. **The check sentence, not the rows.**
   - DW-295's outcome is that "is everything OK?" gets a status on Telegram. OcuTalon's own sentence gives it: what did not pass, with times, or the code's all-clear.
   - Row lines ("Passed: ...", EXPERIENCE.md:890) would need new catalog keys and a line form that the UX does not fix: public text not yet specified (veto window) and a cross-lane catalog change.
   - The sentence uses existing keys and the spine's fixed `whatFailed` forms. The Chat agent's "OcuTalon shows the check results under your reply" then holds on Telegram too.
   - Reversible: a later story may add row lines.
4. **The sentence's layout and time.** The sentence comes after the reply's text, separated by a blank line. Its times use the instance zone (AD-32), where the page uses the browser's zone, with Catalog's own " ET" and "at"/"on" rules, so that a sentence reads as a catalog text does.
5. **The kinds that TelegramOut sends** are those the phone shows (`tellnow`, `incident`, `approval`, `result`, `reminder`), plus `allowance` (AD-14) and `pairing`. `answered` sends nothing until Story 12.7 edits the request's message in place, as the phone does (`SimPhoneOut.EditAnswered`), so Telegram never holds a status the phone does not. `status`, `digest` and `fallback` have no Telegram form in release 1.
6. **One Delivery row per message, carrying the last part's id.** The last part is where 12.7's buttons and status line go. A message with no `SessionRef` records none, because `Delivery.Record` needs an owner and an unpaired chat has no session. A failed `Record` does not resend.
7. **The chat comes from `ChatRef`, else from the session's pairing.** A `pairing` notice to a chat that just unpaired (`pairing.stopped`, `unpairedFromPage`) carries both, and it must reach that chat, so `ChatRef` wins.
8. **One shared Begin.** `TelegramChat` and `TelegramPair` share their start and stop through `LiveCase`, rather than a second copy. A subclass of `TelegramPair` would rerun its tests.
9. **The key-by-key comparison** reads the Watch notice keys from `Catalog.Watch`'s XData, so a later notice key is covered without a change, and pins that there are 12 of them, so an empty read cannot pass. It sends the notices one at a time, so the order of the outputs cannot matter.
10. **Where the tests run, and their cost** (inference until measured):
    - `TelegramChat` runs in `shard:lane-a@Channel` (`production`), for about 45-75 s locally: about 15-25 s of key pointing and restore, 4 turns and 19 notices. `TelegramOut` grows by about 3-5 s. That is about +2 to 3 min on the runner, so `production` goes from about 31 to about 33-34 min.
    - T7 runs in `live:demo-path` (`browser`), for about 10-15 s locally, or about +0.5 min on the runner.
    - Both groups stay under REL-4's 35 minutes, but `production` is close. If its job exceeds 35, the lead's Rule 21 rebalance applies; `ci/units.sh` is not this story's file.

**Extend, don't copy (Rule 2):**
- **The turn's steps copy `WebChatIn.Accept`'s order (about 30 lines), and do not call or extend `WebChatIn`.**
  - `WebChatIn` is Lane B's (AD-33). It takes a page `Post` with a required `ClientId` and the fixed channel `web`, and AD-20, AD-26 and AD-30 name both channel services as the ones that take these steps.
  - Folding the two into one helper would be a Lane B change that no story needs, so this copy is the better choice.
  - The seams carry `WebChatIn`'s names (`Allowed`, `Notify`, `Refund`), so a reader sees the parallel.
- **`WhatFailed`/`CheckSentence`** port `web/src/app/shared/check-sentence.ts` (TypeScript, which ObjectScript cannot call). This is the only ObjectScript renderer of check rows, because replies reach no other `*Out` with rows.
- **`TelegramOut`** keeps one `Send` path, and `Target` replaces `Deliver`'s lookup for both handlers.
- **The tests:**
  - `TelegramChat` reuses LiveCase's (moved) Begin, `PairChat`, `TextsTo`, `Bodies` and `HeaderMark`;
  - it uses `RunnerFixture`'s request readers and the `TestThroughNotify` pattern for Notify, and `Test.Msg.Catalog`'s fixture slots;
  - `TelegramOut`'s new tests reuse `SentTo`, `Outbound` and `Texts`;
  - T7 reuses T5's helpers and constants.

**Integration ACs (Rule 1).** Every row marked "Integration" runs against the real production and the CI mock:
- `Conversation` consumes TelegramIn's Item: the Turn, the reply on both channels, and the request the mock receives;
- `Allowance` consumes the call: the refused Turn rows and the notice;
- `TelegramOut` consumes Notify's routing and `Ownership.Pairing`: the chat's texts and the Delivery rows;
- the page consumes the `chat.message` event: T7.

**Consumes:**
- From Lane B (Stories 2.4, 2.6, 2.7, 2.9, 5.7, 10.3 and 16.9):
  - `Allowance.TryConsume`, `Notice` and `Refund`; `Trace.Join` and `Started`;
  - `Conversation`'s queue and `Tell`; `Notify` and `Rule.Functions`;
  - `Ownership.Pairing` and `RecentPhone`; `Delivery.Record`;
  - `Catalog.Render`; `Checks.Render`'s output; the page's `captionOf`.
- From Stories 12.2 to 12.5:
  - `TelegramIn`'s dispatch and `Row`;
  - `TelegramOut`'s `Send`/`Split`;
  - `LiveCase`, `TelegramPair`'s fixture, `TelegramPageFixture` and T5's helpers.

**Consumed-by:**
- **12.7:** buttons on `incident`/`approval` notices, through the Delivery rows (`FindByApproval(approvalRef, "telegram", owner)` gives the newest row of that approval, the last part's id), and the edit in place for `answered`, which this story leaves unsent.
- **31.3:** turns on 16.9's Telegram cases, on the online demo, over this turn path.
- **38.3:** the owner's real-bot pass.

**Owned ledger:**
- DW-30 is addressed by the row "A long notice goes in parts". `Api.Split` already caps every part (12.2); this story pins it for a rendered notice whose model-written slot is long.
- DW-295 is addressed by the rows "The check sentence follows the reply" and "A paired chat's text is a turn". Its routing note's "rows" are met as the sentence built from the rows; Decided in-stage 3 says why no row lines are added.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=12 stage=<stage>'`, run from the worktree root.

How to run:
- Run one command per foreground call, with `timeout: 600000`, and never two IRIS test runs in one message.
- Tests never run on a dev slot. An IRIS MCP call, if needed, names `server: ocutalon-slot-c` and `namespace: OCUTALON`, after `iris_server_info`.
- Tear down only `e12s6i` and `e12s6iw`, also after a failure.

**Commands:**
- (loop) `npm --prefix web test`. Expected: every `scripts/*.test.mjs` passes, unchanged.
- (loop) `npm --prefix web run lint`. Expected: clean.
- (loop) `bash docker/tests/test-mock.sh`. Expected: the mock's node tests pass, and the new scenario loads with no problem (row 15).
- (loop) `<lane> OCUTALON_RUN_TAG=e12s6iw ci/warm.sh up`. Run it again (`down`, then `up`) after any change under `ci/mock/`, which a warm run refuses.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e12s6iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Channel.TelegramChat`, `TelegramOut`, `TelegramPair`, `TelegramIn`. Expected: `CLASS ... passed`, and `LiveCase` compiles (the `WARM reloaded` line).
- (loop) `<lane> OCUTALON_RUN_TAG=e12s6iw ci/warm.sh down`.
- (once) `<lane> OCUTALON_RUN_TAG=e12s6i ci/iris.sh build`, before the first browser unit. This story changes nothing under `web/src`.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s6i ci/iris.sh live demo-path`. Expected: no FAIL line, and telegram-page's seven tests passed with no skip. If it dies of the unit deadline with no failed test, re-run it with `OCUTALON_LIVE_DEADLINE=900`.
- (once) The fresh-environment check, one call each:
  - `<lane> OCUTALON_RUN_TAG=e12s6i ci/iris.sh shard lane-a@Channel --part 1/2`, then `--part 2/2`;
  - then both again with `--reverse`.
  - Expected: every Channel class passes in both orders. The two parts keep each call well inside the cap: the whole shard took 363-390 s before this story.
- (once) The either-order browser check:
  1. Reverse the order of the five describe blocks of `telegram-page.spec.ts`, with your own backup in the stage's scratchpad.
  2. Run `live demo-path` once.
  3. Restore the file and `cmp` it against the backup.
- (once) One per call: `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-boundaries.sh`, `bash ci/checks.sh`.
- (once) Write the changed paths to a file in the stage's scratchpad, run `bash ci/changes.sh ci.yml --paths-from <file>`, and record the groups.
- (once) `<lane> OCUTALON_RUN_TAG=e12s6i ci/iris.sh teardown`.
- (once) `git status --short -- web/src web/scripts web/e2e/support web/package.json web/package-lock.json ci/units.sh ci/mock/mock.mjs ci/mock/scenarios.mjs ci/mock/test src/ocutalon/cls/OcuTalon/Core src/ocutalon/cls/OcuTalon/Data src/ocutalon/cls/OcuTalon/Msg src/ocutalon/cls/OcuTalon/Agent src/ocutalon/cls/OcuTalon/Checks src/ocutalon/cls/OcuTalon/Web src/ocutalon/cls/OcuTalon/Live src/ocutalon/cls/OcuTalon/Channel/WebChat src/ocutalon/cls/OcuTalon/Channel/SimPhone src/ocutalon/cls/OcuTalon/Test/Data src/ocutalon/cls/OcuTalon/Test/Agent src/bridge README.md`. Expected: it prints nothing.
- Left to CI (Rule 23): `production` (`shard:lane-a@Channel`), `browser` (`demo-path`) and the other groups that `ci/changes.sh` selects. Record `iris (production)`'s and `iris (browser)`'s minutes, `TelegramChat`'s seconds and T7's seconds.

**Shared surfaces:**
- **`TelegramIn`'s handling of a paired chat's other message** now makes a turn.
  - `TelegramPair.TestNameOnlyWhilePaired` is updated here.
  - The implement stage searches `Test/Channel` and `telegram-page.spec.ts` for other paired chats that send plain text (none was found at planning: T5 and T6 send only commands from paired chats, and 12.5's "zz still here" comes from an unpaired one), and runs `TelegramIn`, `TelegramPair` and live demo-path to confirm.
- **`TelegramOut`:**
  - Notifications of the listed kinds, and replies of a `telegram` turn, now reach a session's paired chat.
  - It writes Delivery rows of channel `telegram`.
  - `answered` and the other kinds send nothing.
  - Its existing tests carry a `ChatRef` and stay unchanged.
  - With the seam 0, `Notify` routes nothing to it, so a stack without the seam is unchanged.
- **The `Delivery`, `Turn`, `SimMessage` and AI-session tables** gain fixture rows, which `DropSessions`, `Fixture.Clean` and `DropSince` remove.
- **`LiveCase`:** Begin, Ending and `PairChat` move there with unchanged behaviour, and `DropSessions` removes more of the fixture sessions' rows.
- **The `onlineDemo` setting and the allowance window** are changed only inside `TestRefused`, and restored on every path.
- **The runner keys** are pointed and restored by `TelegramChat`, as `ReminderChat` does.
- **The mock:**
  - the new scenario file joins the committed set (row 15 checks the set for problems, never a count);
  - the `checks-false-all-clear` and `telegram-turn-held` countdowns are armed at 1 and cleared with `Arm(marker, "")`;
  - the Bot API state is reset by `Ready`/`Finish`.
- **The README session's chat** (T7) gains one Telegram turn. telegram-page runs after `01`-`06`, and T7 finds its turn by text and `data-key`.
- **The demo path's step 1:** one more passed test in `telegram-page.spec.ts`. `test-demo-path-gate.sh` reads fixtures only.
- **Every test added or changed passes on a fresh environment, in either order.**

**Pinning mutations to apply (Rule 19).**
- Each is applied, seen red and reverted byte for byte: `cmp` against your own backup, and `git status --short` and `git diff --stat` unchanged. It is then recorded here as `mutation: ... -> ...`.
- A Lane B mutation is temporary, and a stack job that keeps an old class is restarted.
- No mutation points a call at the public API.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC1, the turn | `Other` quits for a paired chat (12.5's code) | `TestTurn` (no Item); T7 |
| AC1, the channel | The Item's `Channel` is `web` | `TestTurn` (`Channel`, `chat.message`); T7 (no "via Telegram") |
| AC1, the thread | `Trace.Join` not called (`%SessionId` left "") | `TestTurn` (the header's `SessionId` is not S's thread) |
| AC1, the reset | `%SessionId`/`%SuperSession` not cleared after the turn | `TestTurn` (the stranger's reply carries S's `TraceRef`) |
| AC1, the reply | `Target` ignores `SessionRef` (12.2's `Deliver`) | `TestTurn` (Texts(130)); `TestBySession`; T7 (`Replies`) |
| AC2, the allowance | `TryConsume` is not called | `TestRefused` (an Item, a model request, no refused Turn) |
| AC2, once | The notice is sent on every refusal | `TestRefused` (two notices) |
| AC2, the channel | `TryConsume` is called with channel `web` | `TestRefused` (refused Turns of channel `web`) |
| AC3 | `Conversation.Start` starts a queued turn while another runs (temporary, Lane B) | `TestQueued` (the second is `running` beside the first) |
| AC3, user message | TelegramIn sends the text with `Provenance` `untrusted` | `TestQueued` (the newest user message is not the Input, or no turn) |
| AC4, identical | `TelegramOut` renders its notices for `web` (whose `incident.withFix` text drops "Approve?") | `TestNotices` (incident.withFix differs from the phone's) |
| AC4, the kinds | `OnNotification` skips kind `result` | `TestNotices` (no text for the 7 result keys) |
| AC4, answered | `answered` is sent | `TestNotices` (a text for `answered`) |
| AC4, Delivery | No `Recorded` call | `TestNotices`; `TestBySession` (no row) |
| AC4, the id | The first part's id is recorded | `TestLongNotice` (the row's id) |
| AC4, the Watch set | The XData read returns only `incident.withFix` | `TestNotices` ("there are 12 Watch notice keys") |
| AC6 | TelegramIn copies the chat's name into the Item's `Text` (a temporary prefix) | `TestNoIdentity` (`Bodies` holds "Zqhidden") |
| DW-30 | `Send` sends the text whole (no `Split`) | `TestLongNotice` (the mock refuses it or gets one part over 4,096) |
| DW-295, the sentence | `OnOutbound` ignores `CheckKey` | `TestCheckSentence` (a)-(c); `TestTurn` (R) |
| DW-295, the order | `WhatFailed` keeps row order (not failed first) | `TestCheckSentence` (a) |
| DW-295, no all-clear from rows | `CheckSentence` gives `checks.allPassed`'s text when no row is left to name | `TestCheckSentence` (d) |
| DW-295, dated | The "at"/"on" rule is left out | `TestCheckSentence` (b) |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned only. The plan stage made no code change, ran no test, and did not commit (the lead's validation gate).
