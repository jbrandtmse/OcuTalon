---
title: 'Story 12.5: Bad codes, a bare start command and unpairing get polite answers'
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_revision: '467b60be1ca4253b96801ad693775e1b535bbbfc'
baseline_commit: '467b60be1ca4253b96801ad693775e1b535bbbfc'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-1, AD-4, AD-12, AD-13, AD-14, AD-17, AD-22, AD-27, AD-29, AD-32 and AD-33)'
warnings: ['oversized']
deferred:
  - summary: >-
      The order of the Telegram card's states (paused, not set up and paired ahead of just-unpaired) has no node-level unit test.
    evidence: |-
      telegramCardView is framework-free, but no web/scripts/*.test.mjs calls it; only T5 and T6 (browser, CI only) run the new just-unpaired view. Moving the
      `if (own.justUnpaired)` line above the paired or paused branch keeps T5 and T6 green (a pairing during the 5 s window would then show the unpaired row).
      The fix is a new file under web/scripts (Lane B's directory, outside the standing rulings), so it needs a ruling.
    location: >-
      web/src/app/rail/telegram-card/telegram-card-view.ts:169
    severity: low
---

<intent-contract>

## Intent

**Problem:** Story 12.4 answers only a valid code. Every other private message gets silence: a bad code, a bare `/start`, `/help`, `/stop` and any other text from a chat that is not paired. `TelegramIn` never submits `/stop`. The card has no "just unpaired" state, no "Telegram unpaired" announcement and no heading focus. Lane B's Story 10.3 already built the session side, unchanged here:
- `SessionOps`: the `Pair` outcomes, `Unpair` from `telegram` and from the page, the moved-chat and second-chat unlinks, their notices and their audit entries;
- `Pairing.TakeReplySlot`, `Pairing.Purge` and its `Install.Step.Core.Purge` declaration;
- the catalog keys `pairing.badCode`, `pairing.start`, `pairing.notPaired` and `pairing.stopped`.

**Approach:**
- `TelegramIn` reads the command of each private message and answers it through the one reply path of Story 12.4 (a `pairing` `Notification` by `ChatRef` to `Notify`):
  - a code that does not pair gets `pairing.badCode`;
  - a bare `/start` and `/help` get `pairing.start`;
  - `/stop` submits `Unpair {ChatRef}` with origin `telegram` and, on `unpaired`, gets `pairing.stopped`;
  - any other message from a chat that is not paired gets `pairing.notPaired`, at most once a minute, through `TakeReplySlot`.
- The card shows "Telegram unpaired" for 5 seconds whenever the store's `paired` turns false while the card exists, then the fresh code. It announces "Telegram unpaired" once. When the paired row held the focus, focus goes to the Telegram heading through the rail's existing focus rule.
- The tests drive the real chain against the CI mock: `Test.Channel.TelegramPair` gains four tests, T5 is extended and a new browser test T6 joins `telegram-page.spec.ts`.

## Boundaries & Constraints

**Always:**
- **What a private message is** (a `message` update of a chat with `type` `private`; button presses stay unanswered until 12.7). Its command is its `text` up to the first white space:
  - **pair:** 12.4's rule, unchanged: "/start " and a payload that is not empty once trimmed;
  - **start:** the command `/start` with no payload (also "/start" with white space only), or the command `/help`, with or without text after it;
  - **stop:** the command `/stop`, with or without text after it;
  - **other:** every other message, including one with no `text` (a sticker or a photo) and every other command.
- **Order:** 12.4's order holds. The chat's row is read first (`Row`), the chat is recorded with 12.4's name rule, and the branch then runs with the row's `Ref`. Group and channel traffic stays ignored.
- **The replies.** Each reply is one `OcuTalon.Msg.Notification`: `Kind` `pairing`, `ChatRef` = the chat row's `Ref`, `Slots` `{}`. It goes to `Notify` through `SendRequestAsync` from `TelegramIn`. `TelegramIn` never calls `sendMessage` itself (AD-1).

  | Branch and outcome | Catalog key | `SessionRef` | Reply-slot |
  |---|---|---|---|
  | pair, `paired` | `pairing.paired` (12.4, unchanged) | the paired session | no |
  | pair, any other outcome, a refused `Submit` or a failed one | `pairing.badCode` | "" | no |
  | start (bare `/start`, `/help`), paired or not | `pairing.start` | "" | no |
  | stop, `unpaired` | `pairing.stopped` | the session it left (the row's `SessionRef` read before the update) | no |
  | stop, `not_paired` | handled as "other" | — | — |
  | stop, `failed` or a refused `Submit` | no reply (one warning) | — | — |
  | other, chat not paired (`SessionRef` empty when read) | `pairing.notPaired` | "" | `TakeReplySlot(ref)` first; no reply when it returns 0 |
  | other, chat paired | no reply (turns are Story 12.6's) | — | — |
- **`/stop`:**
  - `Msg.Command.Unpair` with `ChatRef` = the row's `Ref` and no `SessionRef`, through `Commands.Submit(command, "telegram", .result)`.
  - After `unpaired`, the chat is recorded again with `""`, as 12.4 already does after a code that did not pair. So a chat that unpaired itself keeps no name (AD-4; this closes DW-520's window for `/stop`; a page Unpair still leaves the name until the chat's next update, as DW-520 accepted).
- **Nothing for an unpaired chat reaches a session or a model.**
  - The only request headers its updates cause are `TelegramIn` → `Notify`, `Notify` → `TelegramOut` and `CommandsIn` → `SessionOps` (a code or `/stop`).
  - Every reply to it is a fixed catalog text with no slots, so it names no session, person or state.
  - Its row holds `Ref`, `ChatId`, `CreatedAt`, `SeenAt` and `ReplySlotAt` only: no `SessionRef`, no `DisplayName` and no code columns.
- **Logs.** New log texts are parameters followed only by `Api.Safe` of a status text or an exception's name (AD-14). No code, chat id or name appears in a message, log, live event or audit entry.
- **The card's order of states:**
  1. paused (12.8);
  2. not set up (12.3);
  3. paired (12.4);
  4. **just unpaired**;
  5. nothing;
  6. unpaired.
- **The "just unpaired" view:**
  - The root carries `data-state="just-unpaired"`. It holds one row: the `circle-slash` icon at 16 px, `aria-hidden`, coloured `var(--ink-muted)` (DESIGN.md:785), and the text "Telegram unpaired". It has no button, link, QR code, image or code.
  - It starts when the store's `telegram.paired` changes from true to false while the card exists. The first value the card sees never starts it: a page loaded while unpaired shows the unpaired view at once.
  - It lasts 5000 ms (UX-DR14). The card then shows its code as in 12.3: the asking starts at the change, so the code is usually held by then.
  - A pairing that arrives during the 5 s wins (the paired view). Paused and not set up win too.
  - So a session that pairs a second chat ends paired with the new chat's name, never "unpaired" (UX-DR56 lists "after Unpair, /stop or pairing elsewhere").
- **The announcement.** The card says "Telegram unpaired" through the `Announcer` once for each true → false change that starts the just-unpaired view. 12.4's "Telegram paired" rule is unchanged, and both live in the one existing effect.
- **Focus (UX-DR131, NFR-25).**
  - The paired view's root also carries `data-row-key="telegram:paired"` and `data-section="telegram"`, so it is a row of the Telegram section for the rail's shared focus rule (`status-rail.ts` `FOCUS_RULE`). When an update removes it while focus is inside it (the Unpair button), focus goes to the section heading "Telegram" (`#rail-heading-telegram`, `tabindex="-1"`), whatever caused the unpair: the page's Unpair, `/stop` or a move.
  - Focus anywhere else is never moved. The card adds no `.focus(`, `afterNextRender` or focus rule of its own.
- **Texts.** "Telegram unpaired" joins `TELEGRAM_CARD_TEXTS` (EXPERIENCE.md:358 and :435). The Telegram replies are the catalog's entries, unchanged (EXPERIENCE.md:715-722).
- **Tests.** They run on throwaways and in CI only, against the CI mock and its dummy token:
  - the seam goes through `SetTelegramIncluded` / `setTelegramIncluded`, restored on every path;
  - every test that starts an item stops it and puts its row back;
  - fixture chat ids are `840177341xx`;
  - every IRIS script prints its `CHK|` lines on every path.

**Never:**
- No change to any Lane B class or file outside the entries under Design Notes, "Footprint":
  - `Data/Pairing.cls`, `Core/SessionOps.cls`, `Core/CommandsIn.cls`, `Core/Rule/Notify.cls`, `Msg/Catalog/Core.cls`, `Install/Step/Core.cls`, `Web/Api.cls`, `Live/*`, `Demo/*`, `Included()`;
  - `api/*`, `live/*`, `shared/*`, `icon/icon.ts`, `rail-view.ts`, `status-rail.ts`, `styles/tokens.css`, `web/e2e/support/**`, `rail.spec.ts`;
  - `ci/units.sh`, `ci/mock/**`, `Test/Contract/Mock.cls`, `Test/Data/Fixture.cls`, `README.md`, `web/package.json` and the lockfile;
  - any contended file of the dispatch.
- No rate limit on the bad-code and start replies beyond what the AC sets (AD-4: the reply-slot is for "any other message" only). No reply to a button press (12.7) and no turn from a paired chat (12.6).
- No new mock scenario: updates are queued through the mock's `/updates` control.
- No real bot, no call to `api.telegram.org`, no real token.

## I/O & Edge-Case Matrix

These rows assume:
- **"P"** is a live IRIS test of `Test.Channel.TelegramPair`, under its `Begin` (`TelegramIn` and `TelegramOut` on the production against the mock, the seam 1, demo mode on).
  - The sessions are fresh `zztgpair…` fixture sessions.
  - A code is stored with `Pairing.StoreCode(ref, HashCode(code), now + 600 s)`, or `now − 1 s` for an expired one.
  - "Texts(c)" is `LiveCase.TextsTo(c)` after `TelegramIn` handled the updates and 1 s settled.
  - The literals:
    - BAD: "That code didn't work. Open the OcuTalon page and scan the QR code there for a new one."
    - START: "This is OcuTalon, an assistant that runs inside InterSystems IRIS. To use it here, open your OcuTalon page and scan the QR code there; that pairs this chat with your session."
    - NOTPAIRED: "This chat isn't paired yet. Open your OcuTalon page and scan the QR code there."
    - STOPPED: "Unpaired. This chat won't get OcuTalon messages anymore. Scan the QR code on the OcuTalon page to pair again."
    - FROMPAGE: "Unpaired from the OcuTalon page. Scan the QR code there to pair again."
    - OTHERCHAT: "Another Telegram chat was paired with this OcuTalon session, so this chat is no longer paired."
    - PAIRED: 12.4's confirmation.
- **"T5"** is 12.4's browser test, extended. **"T6"** is the new browser test: `Start(.saved, "ocutalon_pair_bot", 1)`, the README account signed in, codes read from the "Open in Telegram" link, and announcements recorded.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Bad codes (AC1; Integration: `TelegramIn` → `SessionOps` → `Notify` → `TelegramOut`) | P, `TestBadCodes`. Chat `84017734106`, name "Zqbad", not paired, sends `/start` with four codes in turn: (a) one never stored; (b) an expired one of session S2; (c) one of session S1 that chat `84017734107` has just used to pair; (d) "before a reset": one of session S3 whose code row and session row were then deleted | Texts(106) = [BAD, BAD, BAD, BAD]. The row of 106 has no `SessionRef` and no `DisplayName`. 107 is still paired with S1. No `pairing` live event on any stream since the mark. Four `rejected` `Pairing` audit entries on channel `telegram`, with reasons `unknown`, `expired`, `used` and `unknown`; no audit entry since the mark holds `84017734106` or "Zqbad". TelegramIn's four `Notification`s are `pairing.badCode`, with `ChatRef` the row's `Ref`, `SessionRef` "" and `Slots` `{}`. | — |
| Bare start, help, and other messages once a minute (AC2, AC3; Integration: `TelegramIn` → `TakeReplySlot`) | P, `TestStrangerReplies`. Chat `84017734108`, name "Zqstranger", not paired, sends in order: `/start`, `/help`, "zz hello", "zz again", `/stop`. Then its `ReplySlotAt` is set 61 s back (SQL), and it sends a message with no `text` (a `sticker`) | Texts(108) = [START, START, NOTPAIRED, NOTPAIRED]. "zz again" and `/stop` get nothing (the slot is taken). One `Unpair` body (origin `telegram`, `ChatRef` the row's `Ref`) answered `not_paired`, and no audit entry. TelegramIn's four `Notification`s: keys `pairing.start` ×2 and `pairing.notPaired` ×2, each with `SessionRef` "" and `Slots` `{}`. Every request header since the mark targets `Notify`, `TelegramOut` or `SessionOps`: none reaches `Conversation` or any other item. The row has `ChatId`, `Ref`, `CreatedAt`, `SeenAt` and `ReplySlotAt`, and an empty `SessionRef`, `DisplayName`, `CodeSessionRef`, `CodeHash`, `CodeExpiresAt` and `CodeUsedAt`. | — |
| Old rows without a session are purged (AC3; Integration: `Install.Step.Core.Purge` → `Pairing.Purge`) | P, `TestStrangerReplies` after the row above. Chat `84017734109` is paired with a session. Both rows get `SeenAt` and `CreatedAt` "2001-01-01T00:00:00Z" (SQL). Then `Install.Step.Core.Purge(3650)` | OK. The row of 108 is gone. The paired row of 109 stays (aged, but paired), and the unaged code row of 109's session stays (no session, but not old). | — |
| `/stop` unpairs from the chat (AC4; Integration: `TelegramIn` → `SessionOps`) | P, `TestStop`. Chat `84017734120`, "Zqstop", pairs with S1, then sends `/stop` | One `Unpair` body: origin `telegram`, `ChatRef` the row's `Ref`. The row has no `SessionRef` and no `DisplayName`. One `unlinked` audit entry for S1: reason `stop`, channel `telegram`. One `pairing` event on S1's stream with `paired` 0, and `StateBody(S1).telegram.paired` is 0. Texts(120) = [PAIRED, STOPPED]. TelegramIn's `Notification` for it is `pairing.stopped`, with `ChatRef` the row's `Ref` and `SessionRef` S1. | — |
| The page's Unpair tells the chat (AC4; Integration: `SessionOps` → `Notify` → `TelegramOut`) | P, `TestStop`. Chat `84017734121` pairs with S2, then `Commands.Submit(Unpair {SessionRef S2}, "web_user")` | Outcome `unpaired`. Texts(121) = [PAIRED, FROMPAGE]. One `unlinked` audit entry for S2: reason `page`, channel `web`. One `pairing` event on S2's stream with `paired` 0. TelegramIn sends no `Notification` for it. | — |
| A chat moves to another session (AC5, first case) | P, `TestOneLivePairing`. Sessions A and B. Chat `84017734122` pairs with A, then sends `/start <B's code>` | The row's `SessionRef` is B, and it is the chat's only row. Since the mark, one `pairing` event on A's stream with `paired` 0, and one on B's with `paired` 1. `StateBody(A).telegram.paired` is 0. Audit entries: `unlinked` (reason `moved`) for A and `linked` for B. Texts(122) = [PAIRED, PAIRED]: no unpair notice, because the chat moved itself. | — |
| A session pairs a second chat (AC5, second case) | P, `TestOneLivePairing`. Chat `84017734123`, "Zqfirst", pairs with A (a new code). Then chat `84017734124`, "Zqsecond", pairs with A (another new code). Then 123 sends "zz still here" | 123's row has no `SessionRef`, and `Ownership.Pairing(A)` is 124's row. On A's stream since the mark: a `pairing` event with `paired` 0, then one with `paired` 1 and `displayName` "Zqsecond". `StateBody(A).telegram` has `paired` 1 and "Zqsecond". Audit entries: `unlinked` (reason `other_chat`) and `linked`, both for A. Texts(123) = [PAIRED, OTHERCHAT, NOTPAIRED]: the chat is treated as unpaired from then on. 123's row then holds no name. | — |
| A private message no longer passes silently (shared surface) | `TelegramIn.TestPrivateOnly`, unchanged updates, the seam 0 | The private message from 8324 makes exactly one `Notification` from `TelegramIn` to `Notify` (`pairing.notPaired`, `SessionRef` "", the row's `ChatRef`). The private press from 8325 makes none. Still no `sendMessage` (the seam 0, so `Notify` routes nothing), no audit entry, and rows with no session and no name. | — |
| Unpair from the card (AC4; T5, extended) | T5 after its reload: focus on the button, one press on "Unpair Telegram" | One DELETE. The card shows `data-state="just-unpaired"`, text "Telegram unpaired", the `circle-slash` icon (`aria-hidden`, colour `--ink-muted`), and no button, link or QR code. The heading "Telegram" has focus. "Telegram unpaired" is announced exactly once. Then the card is `unpaired` with a fresh code (not `<code>`), within 5000 + `LOADED_MS` ms. `Replies(84017734110)` = [PAIRED, FROMPAGE]. | — |
| A bad code changes no page (AC1; T6) | T6: the card is paired with chat `84017734111` ("Dana"), from the link's code K1. Chat `84017734113` sends `/start K1` (used) | `Replies(84017734113)` = [BAD]. For 3 s after that the card stays "Telegram paired · Dana Unpair". No "Telegram unpaired" announcement, and the "Telegram paired" count is unchanged. | — |
| `/stop` from the chat (AC4; T6) | T6 next: the Unpair button has focus (`focus()`, no press); chat 111 sends `/stop` | The card shows just-unpaired; the heading "Telegram" has focus; "Telegram unpaired" is announced once. It is still `just-unpaired` 4000 ms after it was first seen (polled every 100 ms), and it is `unpaired` with a fresh code no sooner than 4500 ms and no later than 8000 ms after that. `Replies(84017734111)` = [PAIRED, STOPPED]. `/state` has `paired` false. | — |
| Pairing elsewhere, focus untouched (AC5, first case on the page; T6) | T6 next: chat `84017734112` pairs with the fresh code; the composer ("Message OcuTalon") has focus; the fixture's `Move` has chat 112 pair with a fixture session of its own | The card shows just-unpaired, then unpaired with a fresh code. The composer keeps focus. "Telegram unpaired" is announced (the second in T6). `Replies(84017734112)` = [PAIRED, PAIRED]. | — |

</intent-contract>

## Code Map

**Lane A's files (edit freely)**
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls`:
  - the class doc :17-26 (its last sentence says "Story 12.5 replies to every other text…");
  - the `LOG*` parameters :60-78 and `STARTPREFIX` :81;
  - `HandleUpdate` :268-297 (the name rule :282-290, then `Pair` at :296; a `callback_query` sets `chat` only, so `message` is "" for a press);
  - `Payload` :301-307, `Row` :311-323;
  - `Pair` :328-354 (the outcome :344-347, and the re-record with `""` :348-353, which `/stop` reuses);
  - `Reply(ref)` :357-368, which becomes the one reply method with a key and a `SessionRef` (Rule 2).
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPair.cls`:
  - the class doc :1-12;
  - `Begin` :41-70 (its fixture chat list :54-55);
  - `Ending` :74-89 (deletes the code rows of `..Sessions`);
  - `NewSession` :92, `NewCode(session, .hash)` :99-106 (always 600 s: extend it with a lifetime);
  - `Send` :109, `Handled` :117, `ChatRow` :123, `WaitLinked` :131, `Notifications(mark)` :141-150 (TelegramIn → Notify bodies with kind, key, `chatRef`, `sessionRef`, `slots`);
  - `TestPairs` :175 (its page Unpair :254-258), `TestNameOnlyWhilePaired` :269, `TestNoPairWithoutACode` :323.
- `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls`:
  - `FixtureSession` :314;
  - `DropSessions` :322-331 is private, and deletes every `zztg%` session with its events;
  - `Cleanup` :335, `HeaderMark` :255, `RowsText` :271, `Bodies` :284, `LiveMark` :306;
  - `PrivateMessage(chatId, name, text, type)` :521, `TextsTo` :531, `PairBodies` :542 (the sibling for an `Unpair` body scan);
  - the class doc :1-29.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramIn.cls`: `TestPrivateOnly` :166-201 (its asserts :193-194, "no reply is sent" and "TelegramIn sends no message") and the class doc :14-15.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls`:
  - `Pair(code, chatId, name, .queuedAt)` :327-342;
  - `Replies` :344, `Finish` :148 (`DropRows` :381 deletes every `Pairing` row that `Start` did not find);
  - the class doc :20-26.
- `web/src/app/rail/telegram-card/telegram-card-view.ts`:
  - `TELEGRAM_CARD_TEXTS` :32-44, `CardOwn` :71-75, `TelegramCardView` :82-88, `telegramCardView` :143-162 (paired :154-157);
  - the module doc :1-25.
- `web/src/app/rail/telegram-card/telegram-card.ts`:
  - the template :59-95 (the paired root :73);
  - the styles :113-134 (`.paused`, `.paired`, the icon colours);
  - the announcement effect :219-230 and the asking effect :232-244 (`askKey` :195 already asks once `paired` is false);
  - the class doc :26-54 ("moves no focus in this story (Story 12.5 adds…)" :50).
- `web/e2e/demo-path/telegram-page.spec.ts`:
  - the header :9-29;
  - the helpers `railOf` :47, `cardOf` :48, `loaded` :99, `fixture()` :111, `recordRequests` :158;
  - the 12.4 describe :663, its constants :671-675 (`CHAT`, `CONFIRMATION`, `PAIRING_PATH`), `pairedAnnouncements` :678;
  - T5 :688-798, with its Unpair part :776-786;
  - `composerOf` is imported from `support/floor` :5.

**Called, never edited (Lane B)**
- `Core/SessionOps.cls`:
  - `Unlink` :92-133: `SessionRef` cleared, `DisplayName` kept (DW-520), the notice, `Announce(session, 0, "")`;
  - `Pair` :136-173: moved :153-156 with no notice; other chat :157-166 with `pairing.otherChatPaired`;
  - `Unpair` :214-230: from `telegram`, reason `stop` and no notice; from the page, reason `page` with `pairing.unpairedFromPage`; the outcomes `unpaired`, `not_paired` (not audited) and `failed`;
  - `Reject` :384-391: a `rejected` audit entry with reason `unknown`, `expired` or `used`, and no event.
- `Data/Pairing.cls` (contended with Epic 11):
  - `RecordChat` :79-123, `TakeReplySlot(chatRef)` :128-150 (60 s, under the row's lock, 0 for an unknown `Ref`);
  - `StoreCode` :155, `Chat` :195, `ForCode` :205;
  - `Purge(daysToKeep)` :217-238: rows with no `SessionRef` whose `SeenAt` (else `CreatedAt`) is older; code rows have no `SessionRef` either.
- `Install/Step/Core.cls:8-11`: the Core area's `Purge` declaration (AD-27).
- `Core/CommandsIn.cls:173-174`: `Pair` only from `telegram`; `Unpair` from `web_user`, `web_admin`, `telegram`, `timer` and `system`.
- `Msg/Command/Unpair.cls` (`ChatRef`).
- `Msg/Catalog/Core.cls:17-50`: the seven `pairing.*` keys, all with no slots.
- `Core/Rule/Notify.cls:31-35`: kind `pairing` with a `ChatRef` goes to `TelegramOut` alone when `TelegramOn()` (the seam), else to nothing.
- `Channel/Telegram/Out.cls:63-80` (Lane A, unchanged): `OnNotification` → `Deliver(chatRef)`, with no use of `SessionRef`.
- `Data/Ownership.cls` `Pairing(sessionRef, .sc)`; `Web/Api.cls` `StateBody`.
- The IRIS test helpers:
  - `Test/Bridge/AuditLog.cls` `Now` :23, `Entries` :30, `Wait` :61;
  - `Test/Core/Observe.cls` `Events`;
  - `Test/Data/Fixture.cls` `SetTelegramIncluded` (contended: called only);
  - `Test/Agent/RunnerFixture.cls` (contended: called only);
  - `Test/Contract/Mock.cls` `Control("updates", …)`.
- The page:
  - `rail/status-rail.ts`: `ROW_KEY`/`ROW_SECTION` :26-27, `headingId` :34, `FOCUS_RULE` :40-44 (an item's `data-section` names the heading), the `h3 tabindex="-1"` :85, the effect that calls `keepFocus` on every view change :270-273;
  - `shared/focus-rule.ts` `keepFocus` (it moves only a lost focus);
  - `shared/announcer.ts`;
  - `live/live-store.ts:181-183` (a `pairing` event sets `paired` and `displayName`);
  - `icon/icon.ts` has `circle-slash` :15/:95;
  - `styles/tokens.css:11` `--ink-muted`.
- The e2e support: `support/page.ts` `recordAnnouncements`, `announcedTexts`, `plain`, `tokenColor`; `support/floor.ts:51` `composerOf`; `support/iris.ts` `setTelegramIncluded`, `quoted`.
- The source pins (Lane B, by entry only):
  - `web/scripts/ux-strings.test.mjs:230-233` (12.4's four strings);
  - `web/scripts/announce-focus-sources.test.mjs`:
    - :98-99, the Story 12.4 comment about the card's speaking;
    - :102, the speakers test's title "…the Telegram card (the pairing, once, Story 12.4)";
    - :124-136 `FOCUS_CALLS` and :139 the `afterNextRender` list, both unchanged by this story.

## Tasks & Acceptance

**Execution:**
1. `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls` (AD-1, AD-4, AD-14, AD-32):
   - `HandleUpdate` keeps the read, the name rule and `RecordChat`, then dispatches on the command of a `message` (the Boundaries). A press dispatches nothing.
   - **pair:** `Pair` unchanged except that every outcome other than `paired`, and a refused or failed `Submit`, also sends `pairing.badCode`.
   - **start:** `pairing.start`.
   - **stop:** a new private `Stop(ref, chatId, sessionRef)` submits `Unpair`. On `unpaired` it records the chat again with `""` (the step that `Pair` already has, made one private method that both call), then replies `pairing.stopped` with the session it left. On `not_paired` it goes on as "other". Otherwise it logs one warning (a new `LOGSTOP` parameter) and does not reply.
   - **other:** when the row read before had no `SessionRef`: `TakeReplySlot(ref)`, and `pairing.notPaired` when it returns 1.
   - `Reply(ref, key, sessionRef)` is the one reply method: 12.4's paired call passes `Chat(ref).SessionRef`.
   - The class doc names the commands, their replies, the reply-slot and the `/stop` name rule, and drops "Story 12.5 replies to…".
2. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPair.cls` (extend; no new class, so `shard:lane-a@Channel` takes it with no `ci/units.sh` change):
   - `Begin` adds the chats `84017734106`-`109` and `84017734120`-`124` to its list.
   - `NewCode` takes a lifetime in seconds (default 600).
   - A helper for the `Unpair` bodies since a mark extends `LiveCase.PairBodies` (one method with the body class as a parameter, or a sibling beside it; Rule 2), and is used once in `TestStrangerReplies` and once in `TestStop`.
   - **`TestBadCodes`**: the row "Bad codes". "Before a reset" deletes S3's code row and session row, as the reset clears every session and pairing (PRD FR-59).
   - **`TestStrangerReplies`**: the rows "Bare start, help, and other messages once a minute" and "Old rows without a session are purged". The ages are set by SQL on the fixture rows only, and `Purge(3650)` deletes only rows older than about ten years, so no other row of the stack can be hit.
   - **`TestStop`**: the rows "`/stop` unpairs from the chat" and "The page's Unpair tells the chat".
   - **`TestOneLivePairing`**: the rows "A chat moves to another session" and "A session pairs a second chat".
   - The class doc lists the four new tests.
3. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramIn.cls`: `TestPrivateOnly` asserts the row "A private message no longer passes silently", and the class doc says so.
4. `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls`: `DropSessions` becomes a public class method (its second user is the fixture's `Finish`). The class doc says so.
5. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls`:
   - `Send(chatId, name, text, Output queuedAt)`, a generalization of `Pair`'s body, which `Pair` then calls. It waits for an open long poll and takes `queuedAt` just before the `/updates` call. With an empty name the update has no `first_name`.
   - `Move(chatId, name, Output queuedAt)` makes a fixture session `zztgmove<n>` and stores a code for it (600 s), then `Send`s `/start <code>`.
   - `Finish` also calls `LiveCase.DropSessions()` (after `DropRows`, which removes the move's code row and chat rows).
   - Every new method returns "" or a reason with no token. The class doc covers the three changes.
6. `web/src/app/rail/telegram-card/telegram-card-view.ts`:
   - `TELEGRAM_CARD_TEXTS.unpaired` = `'Telegram unpaired'`, and `JUST_UNPAIRED_MS = 5_000`.
   - `CardOwn` gains `justUnpaired: boolean`. The view kind gains `'just-unpaired'`, placed by the Boundaries' order.
   - The module doc gains the state.
7. `web/src/app/rail/telegram-card/telegram-card.ts`:
   - **The just-unpaired block:** the icon `circle-slash` at 16, the text, its colour `var(--ink-muted)`. Its row reuses the paused row's style (one shared selector, not a copy).
   - **The paired root** gains `data-row-key="telegram:paired"` and `data-section="telegram"`.
   - **The effect** that already remembers `paired`, on true → false: sets a `justUnpaired` signal, announces `unpaired` once when the card then shows `just-unpaired`, and clears the signal after `JUST_UNPAIRED_MS` (a timer cleared on the next change and on destroy).
   - **The class doc:** the state, the 5 s, the announcement and the heading focus through the rail's rule. It drops "moves no focus in this story (Story 12.5 adds…)".
8. `web/scripts/ux-strings.test.mjs` (standing ruling, one entry): `'Telegram unpaired'` beside 12.4's four strings. EXPERIENCE.md holds it (:358, :435), so it is a UX source.
9. `web/scripts/announce-focus-sources.test.mjs` (the runner's 12.4 ruling, by entry; two text entries, no list change):
   - **the Story 12.4 comment (:98-99):** it says the card speaks "Telegram paired" or "Telegram unpaired", once each, when the pairing changes (Stories 12.4 and 12.5);
   - **the speakers test's title (:102):** "the Telegram card (the pairing and the unpairing, once each, Stories 12.4 and 12.5)".

   `FOCUS_CALLS`, the `afterNextRender` list and the hosts' rules stay unchanged. If the implement stage finds that one of them must change, that is a `## Clarification Needed`, never an extra entry.
10. `web/e2e/demo-path/telegram-page.spec.ts`:
    - The header names Story 12.5's T5 extension and T6.
    - **T5:** the row "Unpair from the card". The wait for the unpaired view after Unpair becomes `5_000 + LOADED_MS`, and the `Replies` check after it expects `[CONFIRMATION, FROMPAGE]`.
    - **T6** in a new `test.describe('bad codes, a bare start command and unpairing get polite answers (Story 12.5)')`, tagged `@floor`, with `test.setTimeout(180_000)`. It covers the rows "A bad code changes no page", "`/stop` from the chat" and "Pairing elsewhere, focus untouched", in that order, in one test.
      - The heading is `railOf(page).getByRole('heading', { name: 'Telegram', exact: true })`, checked with `toBeFocused()`.
      - Its `finally` calls `Finish(saved)`, then `setTelegramIncluded(was)`, nested as in T5.
      - Text constants for BAD, STOPPED and FROMPAGE beside 12.4's `CONFIRMATION`.

**Acceptance Criteria:**
- Given a private chat sends `/start` with an unknown, expired or used code, or one from before a reset, when `TelegramIn` handles it, then the chat gets exactly "That code didn't work. Open the OcuTalon page and scan the QR code there for a new one.". Nothing is linked and no `pairing` event reaches any page, and a `rejected` `Pairing` audit entry holds no Telegram identity (FR-19, FR-9, AD-17, UX-DR104, UX-DR109). Rows "Bad codes" and "A bad code changes no page".
- Given a bare `/start` or `/help` from a private chat, when it arrives, then the chat gets exactly the `pairing.start` text and nothing is linked (FR-19, UX-DR109). Row "Bare start, help, and other messages once a minute".
- Given any other message from a chat that is not paired, when it arrives, then:
  - it gets "This chat isn't paired yet. …" at most once a minute, because `TakeReplySlot` is called first;
  - it reaches no session and no model;
  - the reply names no session, person or state;
  - the chat's row holds no session, no name and no code, and the Core area's `Purge` removes it once old;
  - every reply is a `pairing` `Notification` with only that row's `ChatRef` (FR-19, AD-4, AD-27).

  Rows "Bare start, help, and other messages once a minute", "Old rows without a session are purged" and "A private message no longer passes silently".
- Given a paired chat, when the page's Unpair or the chat's `/stop` unpairs it, then:
  - `SessionOps` unlinks it, audits it and publishes the event;
  - the chat gets FROMPAGE or STOPPED;
  - the card shows "Telegram unpaired" for 5 s, then a fresh code, and the announcer reads "Telegram unpaired";
  - focus goes to the Telegram heading when the removed paired row held it, and stays put otherwise (FR-18, FR-9, UX-DR14, UX-DR56, UX-DR109, UX-DR131, UX-DR132).

  Rows "`/stop` unpairs from the chat", "The page's Unpair tells the chat", "Unpair from the card" and "`/stop` from the chat".
- Given sessions A and B, when a chat paired with A pairs with B, or A pairs a second chat, then a chat keeps at most one live pairing:
  - in the first case, A's card shows "Telegram unpaired" and then a new code;
  - in the second, the first chat gets OTHERCHAT and is treated as unpaired from then on;
  - each change is audited (FR-18, FR-9, AD-4, UX-DR56, UX-DR109).

  Rows "A chat moves to another session", "A session pairs a second chat" and "Pairing elsewhere, focus untouched".

## Spec Change Log

## Review Triage Log

### 2026-11-01 — Review pass
- verdicts: 31 findings — high 0, medium 1, low 12, false 18, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: start and bad-code replies have no reply slot — the spec's Boundaries and Decided 5 say the reply-slot is for "any other message" only (AD-4); the behaviour is the specified one.
  - `[false]` `[reject]` Blind: a paired chat gets the start text for /help — specified (Decided 3: "The start reply goes to paired chats too").
  - `[low]` `[patch]` Blind and Edge: /stop answered not_paired after a stale "paired" read goes to Other with the stale sessionRef and gets no reply — `Stop` now passes "" to `Other` for not_paired (patched in In.cls, class doc reworded).
  - `[low]` `[reject]` Blind: no tests for Command parsing edges (/stop now, /START, /start TAB code) — the matrix pins exact words in fixed chat ids; the extra cases would need chats and rows beyond the spec's; unlikely in use; no behaviour is wrong.
  - `[low]` `[defer]` Blind and Gap and Intent: no node unit test for the card view and its state order — recorded in the frontmatter `deferred:` list (fix is a new Lane B-directory file, needs a ruling).
  - `[low]` `[reject]` Blind and Edge and Intent: "Telegram unpaired" is not announced when the view is masked (paused, not set up) at the change and the state clears inside 5 s — the spec announces when the card then shows just-unpaired; a rare double condition; the fix adds state.
  - `[false]` `[reject]` Blind: T6 timing windows may flake — the 4000 ms and 4500-8000 ms windows are the spec's (Decided 11); the poll lag needed to break them (over 500 ms) is not shown.
  - `[false]` `[reject]` Blind: T6 watches the bad-code case for 3 s only — the spec's row says 3 s.
  - `[false]` `[reject]` Blind: Auto Run Result still says ready-for-dev — rewritten at finalize.
  - `[low]` `[reject]` Blind: mutation lines say T6 not separately evidenced — T5 is red for each of those mutations, so every AC has a pinning test with a recorded mutation; T6's own red for them was hidden by the grouped runs.
  - `[false]` `[reject]` Edge: Stop with a result that is not an object logs nothing — Commands.Submit returns an object on OK (SessionOps always answers); the path is not reachable.
  - `[false]` `[reject]` Edge: /Stop, /stop@bot and other cases are "other" — specified (Decided 1: the first word matched exactly).
  - `[false]` `[reject]` Edge: unthrottled start and bad-code replies — as the first Blind row.
  - `[false]` `[reject]` Edge: a Submit that throws after linking sends badCode — the table says a failed Submit gets pairing.badCode; Commands.Submit is synchronous and a throw after the link is not shown to happen.
  - `[low]` `[patch]` Edge: same stale-read race as the Blind one — one fix, above.
  - `[low]` `[reject]` Edge: unannounced "Telegram unpaired" when masked — as above.
  - `[false]` `[reject]` Edge: Move leaves a zztgmove session when Send fails — Finish runs in T6's finally with a non-empty held and drops the zztg sessions; Move is only called after Start found its rows.
  - `[low]` `[reject]` Gap: the view's order has no executed test host — merged into the deferred entry.
  - `[low]` `[reject]` Gap: the second-chat sequence (paired 0 then paired 1) is not run on a page — the end state follows from the view order (paired wins), covered by the deferred entry; the reset branch only clears a flag that the view order already ignores.
  - `[medium]` `[patch]` Gap: no assertion on a paired chat's replies (no reply to other text, start text for /help, bad code stays paired) — `TestNameOnlyWhilePaired` now asserts [CONFIRMATION, BAD] and then [CONFIRMATION, BAD, START]; the `Other` mutation is red there and a `mutation:` line is written.
  - `[low]` `[reject]` Gap: command parser tested only with bare words — as the Blind row.
  - `[low]` `[reject]` Gap: failure paths of Pair and Stop (a refused or failed Submit, outcome failed) are untested — forcing a Submit failure on the live production needs a Lane B seam; the paths are a warning and a fixed reply.
  - `[false]` `[reject]` Gap, other: T6 and mutation lines — as the Blind row.
  - `[low]` `[reject]` Gap, other: AssertEventsSince and the negative checks use a fixed settle time — the same pattern as the sibling tests (Hang 1); no failure shown.
  - `[false]` `[reject]` Gap, other: the `WaitCalls` readiness in Send is cumulative — harmless, the mock queues the update until the next poll.
  - `[false]` `[reject]` Gap, other: Finish drops every zztg session — tests on a stack run serially; the same scope as LiveCase.Cleanup.
  - `[false]` `[reject]` Intent: reading 3 (both surfaces) is implemented — descriptive; no divergence beyond those logged.
  - `[false]` `[reject]` Intent: an extra warning for an unknown Unpair outcome — a log line only.
  - `[false]` `[reject]` Intent: the empty-outcome-without-error case logs nothing — as the Edge row on the non-object result.
  - `[false]` `[reject]` Intent: heading focus and the 5 s window are proven only in the browser — T5 and T6 are the specified pins (Decided 9 and 11).
  - `[false]` `[reject]` Intent: only T5 and T6 link the chat events to the card — specified.

## Design Notes

**Governing ADs:**
- **AD-1:** `/stop` enters as `Msg.Command.Unpair` through `Commands.Submit` with origin `telegram`. Only business operations send: `TelegramIn` hands every reply to `Notify`.
- **AD-4:**
  - Its "Pairing replies and notices" paragraph is this story's contract. `TakeReplySlot` comes before each reply to any other message from an unpaired chat, and before no code, bare `/start` or `/help` reply.
  - For `/stop` and the pair outcomes, `SessionOps` returns the outcome and `TelegramIn` replies.
  - A page Unpair and a second chat get `SessionOps`'s own notices, and a moved chat gets only its pair reply.
  - The chat id and name live only in the row. An unpaired chat's row holds no session.
  - Every change publishes a `pairing` event to every session whose state changed.
- **AD-12:** the card learns `paired` from the live store. The just-unpaired view is the card's own, timed in the page.
- **AD-13:** no new client call (the Unpair button is 12.4's `ApiClient.unpair()`), and no `innerHTML`.
- **AD-14:** private chats only. No chat id or name reaches a log, the audit writer or a message. `Notify` is the one router.
- **AD-17:** the `rejected` and `unlinked` entries are `SessionOps`'s, through `Bridge.Audit`. The tests read them back by time, with polling.
- **AD-22:** throwaways and the CI mock only. Updates are queued through `/updates`.
- **AD-27:** old chat rows without a session go through the Core area's `Purge(daysToKeep)` declaration, which the test calls directly.
- **AD-29, AD-33:** only Lane A files change, plus the source-pin entries under "Footprint". Lane B's tables are read and, in tests, aged by SQL on fixture rows; Lane B classes are never edited.
- **AD-32:** every reply is a `pairing` `Notification` with a catalog key and `Slots` `{}`. Only `TelegramOut` renders it. A reply to an unpaired chat has an empty `SessionRef`, because the chat has no session; AD-4 refers to it by `ChatRef` alone.

No AC contradicts an AD. The two NFR-like numbers are measurable as worded: "at most once a minute" is `TakeReplySlot`'s 60 s, and "for 5 seconds" is UX-DR14's timing, measured in T6 with a 4000 ms / 4500-8000 ms window. No Rule 5 tripwire.

**Footprint (Rule 11; report under `footprint_extensions:`):**
- **Lane A:**
  - `Channel/Telegram/In.cls`;
  - `Test/Channel/TelegramPair.cls`, `TelegramIn.cls`, `LiveCase.cls` and `TelegramPageFixture.cls`;
  - `telegram-card.ts` and `telegram-card-view.ts`;
  - `telegram-page.spec.ts`.
- **Lane B, by entry:**
  - `web/scripts/ux-strings.test.mjs`: one string (the orchestrator's standing ruling);
  - `web/scripts/announce-focus-sources.test.mjs`: two text entries (the runner's 12.4 ruling: by entry, entries named here).
- No contended file is edited. `Data/Pairing.cls`, `Test/Data/Fixture.cls` and `Test/Agent/RunnerFixture.cls` are called only.
- No "Needs ruling" item: no change in a Lane B class or a contended file is needed. The heading focus uses the rail's existing rule by marking the paired view as a row, so `status-rail.ts` and `FOCUS_CALLS` stay unchanged.

**Decided in-stage:**
1. **What counts as a command.** The first word of `text`, matched exactly: `/start`, `/help` and `/stop`, with or without text after them. `/start` with a payload stays 12.4's pairing. A `/start@bot` form or another case is "other" (12.4's literal rule).
2. **Every unsuccessful pair attempt gets the bad-code reply.** That covers the outcomes `unknown_code`, `used_code`, `expired_code`, `unknown_chat` and `failed`, and a refused or failed `Submit`. "That code didn't work" is true of each, and silence would leave the user guessing. A bad code from a paired chat gets it too, and the chat stays paired (12.4 (c)).
3. **The start reply goes to paired chats too.** The AC does not separate them, and the text names no state.
4. **A `/stop` from a chat that is not paired** is "other": `SessionOps` answers `not_paired`, and the chat gets the reply-slotted `pairing.notPaired`. A failed `/stop` gets no reply (one warning), because "not paired" would be false and no catalog text fits.
5. **The only reply-slot is AD-4's.** The bad-code and start replies have no limit beyond Telegram's own (TelegramOut retries a 429). 12.4's review already rejected a per-chat limit on pairs as a change of specified behaviour.
6. **`SessionRef` of the replies.** `pairing.paired` keeps 12.4's paired session, and `pairing.stopped` carries the session it left (like `SessionOps`'s `unpairedFromPage`). The bad-code, start and not-paired replies carry `ChatRef` alone, which the AC requires for unpaired chats; they use one rule for every chat.
7. **`/stop` clears the name** by recording the chat again with `""`, the step 12.4 takes after a failed code. A page Unpair keeps DW-520's accepted window.
8. **Heading focus only replaces a lost focus.** UX-DR131 (cited by the AC) and EXPERIENCE "Focus replacement" say focus moves "when an update removes the focused element", "whether the update came from the user or from another channel". So a remote `/stop` or move takes focus to the heading only when it was on the Unpair button, and focus elsewhere stays (NFR-25). T6 pins both.
9. **The heading focus reuses the rail's rule (Rule 2).** The paired view becomes a row of the Telegram section (`data-row-key`, `data-section`), so `status-rail.ts`'s `FOCUS_RULE` sends a lost focus to `#rail-heading-telegram`. The rail's effect runs `keepFocus` on every store change, before the card's DOM changes. A focus call in the card would race the rail's own rule, which runs first and would send a lost focus to the main region. It would also need two new Lane B entries (`FOCUS_CALLS` and the `afterNextRender` list). (inference until T5 and T6 measure it; their mutation pins it.) If they show that the heading does not get the focus, that is a `## Clarification Needed`, never a focus call or a Lane B entry added unasked.
10. **A pairing during the 5 s wins,** and a session pairing a second chat ends paired with the new name. UX-DR56 lists the causes of "just unpaired" as "Unpair, /stop or pairing elsewhere". EXPERIENCE.md:358 also lists "another chat pairing with this session", but a fresh QR code there would show a false state for a session that is paired. The AC for that case names only the first chat's notice. Whether a brief just-unpaired view flashes between the two events is not pinned.
11. **The 5 s window in T6.** Still just-unpaired 4000 ms after it was first seen, and unpaired no sooner than 4500 ms and no later than 8000 ms after that. The 100 ms polling and a code that is already held usually put it near 5000 ms; the upper slack covers a slow runner.
12. **Where the tests run.**
    - `TelegramPair`'s four new tests run in `shard:lane-a@Channel` (`production` group). T6 and T5's extension run in `live:demo-path` (`browser` group). No unit is added or moved.
    - Expected (inference): `TelegramPair` grows from about 17 s to 40-55 s locally (about +1 to 1.5 min on the runner). T6 takes about 25-35 s locally, and T5 grows by about 6 s (together about +1 to 1.5 min on the runner).
    - So the groups go from about 31 to 32-33 min (`production`) and from about 28 to 29-30 min (`browser`), under REL-4's 35.

**Extend, don't copy (Rule 2):**
- **`HandleUpdate`** stays the one private-chat handler, with one dispatch. `Reply` becomes the one reply method. 12.4's re-record with `""` becomes one private method that `Pair` and `Stop` share.
- **The card** extends 12.4's effect (one more direction), its view function (one more kind) and its state-row style (shared with the paused row). No new focus code: the rail's rule does it.
- **The tests:**
  - `TelegramPair` keeps `Begin`, `Ending`, `NewSession`, `NewCode`, `Send`, `Handled`, `ChatRow`, `WaitLinked` and `Notifications`;
  - the `Unpair` body scan extends `PairBodies`;
  - `TelegramPageFixture.Send` is `Pair`'s body generalized, and `Finish` reuses `LiveCase.DropSessions`;
  - T6 reuses T5's helpers and constants.

**Integration ACs (Rule 1):**
- **"Bad codes":** `SessionOps` consumes `TelegramIn`'s `Pair` and answers a rejection; `TelegramIn` turns it into the reply that the mock receives.
- **"Bare start…":** `TakeReplySlot` gates the reply, which is observable as one `sendMessage` a minute.
- **"Old rows without a session are purged":** the Core area's `Purge` declaration removes the row `TelegramIn` recorded.
- **"`/stop` unpairs" and "The page's Unpair tells the chat":** `SessionOps` consumes the `Unpair`, and its audit entry, event and notice are observed.
- **"Unpair from the card", "`/stop` from the chat" and "Pairing elsewhere":** the page consumes the real `pairing` event.

All of them run against the real production and the mock.

**Consumes:**
- From Story 10.3 (Lane B):
  - `SessionOps.Pair`/`Unpair`/`Unlink`;
  - `Pairing.RecordChat`, `TakeReplySlot`, `StoreCode`, `Chat`, `Purge` and `Install.Step.Core.Purge`;
  - `CommandsIn`'s `Unpair` route, `Notify`'s `pairing` route;
  - the seven `pairing.*` catalog keys, and the live store's `pairing` handling.
- From Story 12.4:
  - `TelegramIn`'s name rule, `Pair` and `Reply`;
  - `TelegramPair`'s fixture;
  - T5 and `TelegramPageFixture`'s `Pair` and `Replies`;
  - the paired card and its effect.
- From Lane B's page: the rail's `FOCUS_RULE` and heading, `keepFocus`, `Announcer` and `circle-slash`.

**Consumed-by:**
- **12.6:** a paired chat's "other" message, which this story leaves unanswered, becomes its turn, on the same dispatch.
- **12.7:** button presses (no reply here) get their alerts.

**Owned ledger:** none (the inbox is empty).
- DW-520 (wontfix-accepted) is cited: this story clears the name on `/stop` on Epic 12's side, and the page-Unpair window stays as accepted.
- DW-514 (decision-pending, two tabs) is not built on: T5 and T6 use one tab.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=12 stage=<stage>'`, run from the worktree root.

How to run:
- Run one command per foreground call, with `timeout: 600000`, and never two IRIS test runs in one message.
- Tests never run on a dev slot. An IRIS MCP call, if needed, names `server: ocutalon-slot-c` and `namespace: OCUTALON`, after `iris_server_info`.
- Tear down only `e12s5i` and `e12s5iw`, also after a failure.

**Commands:**
- (loop) `npm --prefix web test`. Expected: every `scripts/*.test.mjs` passes, among them `ux-strings`, `announce-focus-sources`, `api-client-sources`, `page-safety`, `floor-sources` and `shell-styles`.
- (loop) `npm --prefix web run lint`. Expected: clean.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s5iw ci/warm.sh up`, before the stage's first `ci/iris.sh build`. After a build: `down`, then `up`.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e12s5iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Channel.TelegramPair`, `TelegramIn`, `TelegramOut` and `TelegramNoToken`. Expected: `CLASS … passed`, and `TelegramPageFixture` and `LiveCase` compile (the `WARM reloaded` line).
- (loop) `<lane> OCUTALON_RUN_TAG=e12s5iw ci/warm.sh down`.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s5i ci/iris.sh build`, once after each change under `web/src` and before any browser unit.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s5i ci/iris.sh live demo-path`. Expected: every PASS line, no FAIL line, and `STEP 1 page: passed` with telegram-page's six tests passed and no skip. If it dies of the unit deadline with no failed test, re-run with `OCUTALON_LIVE_DEADLINE=900`.
- (once) The fresh-environment check, one call each: `<lane> OCUTALON_RUN_TAG=e12s5i ci/iris.sh shard lane-a@Channel`, then the same with `--reverse`. Expected: every Channel class passes in both orders.
- (once) The either-order browser check:
  1. Reverse the order of the four describe blocks of `telegram-page.spec.ts`, with your own backup in the stage's scratchpad.
  2. Run `live demo-path` once.
  3. Restore the file and `cmp` it against the backup.
- (once) `<lane> OCUTALON_RUN_TAG=e12s5i ci/iris.sh live sign-in --part 1/2`, then `--part 2/2`. Expected: passed (the rail and its focus rule are shared).
- (once) One per call: `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-boundaries.sh`, `bash ci/checks.sh`.
- (once) Write the changed paths to a file in the stage's scratchpad, run `bash ci/changes.sh ci.yml --paths-from <file>`, and record the groups.
- (once) `<lane> OCUTALON_RUN_TAG=e12s5i ci/iris.sh teardown`.
- (once) `git status --short -- ci web/src/app/api web/src/app/live web/src/app/shared web/src/app/guide web/src/app/chat web/src/app/icon web/src/styles web/src/app/rail/rail-view.ts web/src/app/rail/status-rail.ts web/e2e/support web/e2e/rail web/package.json web/package-lock.json src/ocutalon/cls/OcuTalon/Web src/ocutalon/cls/OcuTalon/Data src/ocutalon/cls/OcuTalon/Core src/ocutalon/cls/OcuTalon/Demo src/ocutalon/cls/OcuTalon/Live src/ocutalon/cls/OcuTalon/Msg src/ocutalon/cls/OcuTalon/Install src/ocutalon/cls/OcuTalon/Test/Data src/ocutalon/cls/OcuTalon/Test/Agent src/bridge README.md`. Expected: it prints nothing. The only Lane B paths changed are the two `web/scripts/` entries.
- Left to CI (Rule 23): `production` (`shard:lane-a@Channel`), `browser` (`demo-path`) and the other groups that `ci/changes.sh` selects. Record `iris (production)`'s and `iris (browser)`'s minutes, `TelegramPair`'s seconds and `live:demo-path`'s seconds.

**Shared surfaces:**
- **`TelegramIn`'s handling of private messages:**
  - an unpaired chat's message now makes one `Notification` to `Notify`: `TestPrivateOnly` is updated here;
  - `TestRestartLosesNothing`, `TestOffsetNode`, `TestRecordChatFailure` and `TestNameOnlyWhilePaired` assert rows and offsets only, and stay unchanged; the implement stage runs them to confirm;
  - with the seam 0, `Notify` sends these to nothing, so no `TelegramOut` queue is left behind.
- **The `Pairing` table:**
  - unpaired chats' rows now get `ReplySlotAt`, and `/stop` clears a name;
  - `TestStrangerReplies` ages two fixture rows only;
  - `TelegramPageFixture.Finish` now also drops `zztg%` sessions (the README session is not one).
- **`LiveCase.DropSessions`** becomes public, with unchanged behaviour.
- **The Telegram card's states:**
  - the new `just-unpaired` view, and the paired root's row attributes, which make it an item of the rail's focus rule;
  - readers: T5 (updated here), T4's paired cases (snapshot-loaded, so no transition: unchanged), R11 in `rail.spec.ts` (unpaired: unchanged), and `[data-row-key]` users in other specs, which all select `li.row[...]` (unchanged).
- **The demo path's step 1:** one more passed test in `telegram-page.spec.ts`. `test-demo-path-gate.sh` reads fixtures only.
- **The source pins:** the UX strings inventory gains one string, and the speakers test's comment and title are reworded.
- **The audit log** gains `rejected` and `unlinked` `Pairing` entries (append-only). **The live streams** of fixture sessions and the README session gain `pairing` events.
- **The mock's Bot API state:** reset per test by `Ready`/`Finish`.
- **Every test added or changed passes on a fresh environment, in either order.**

**Pinning mutations to apply (Rule 19).**
- Each is applied, seen red and reverted byte for byte: `cmp` against your own backup, and `git status --short` and `git diff --stat` unchanged. It is then recorded here as `mutation: … -> …`.
- A Lane B mutation is temporary.
- A web mutation is followed by `ci/iris.sh build`.
- No mutation points a call at the public API.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC1, the reply | `Pair` sends nothing after an outcome other than `paired` (12.4's code) | `TestBadCodes`; T6 (`Replies(113)`) |
| AC1, nothing changes | `SessionOps.Reject` also calls `Announce(sessionRef, 0, "")` (temporary, Lane B) | `TestBadCodes` (a `pairing` event); T6 (the card leaves paired) |
| AC1, audited | `SessionOps.Reject` skips `WriteAudit` (temporary, Lane B) | `TestBadCodes` (no `rejected` entries) |
| AC2 | The start branch matches `/start` only, not `/help` | `TestStrangerReplies` (Texts has one START) |
| AC3, the minute | `TakeReplySlot` is not called (a reply every time) | `TestStrangerReplies` (NOTPAIRED three times) |
| AC3, no session or model | `TelegramIn` also sends the unpaired chat's text as an `OcuTalon.Msg.Item` to `Conversation` | `TestStrangerReplies` (a request header to `Conversation`) |
| AC3, only `ChatRef` | The not-paired `Notification` carries a fixture session's `Ref` as `SessionRef` | `TestStrangerReplies` (`SessionRef` not "") |
| AC3, purge | `Install.Step.Core.Purge` returns OK without calling `Pairing.Purge` (temporary, Lane B) | `TestStrangerReplies` (the row of 108 is still there) |
| AC4, `/stop` | `/stop` is "other" (no `Unpair` submitted) | `TestStop` (no `Unpair` body, still linked); T6 |
| AC4, the stop reply | No reply on `unpaired` | `TestStop` (Texts(120)); T6 (`Replies(111)`) |
| AC4, the name | No re-record with `""` after `unpaired` | `TestStop` (`DisplayName` stays "Zqstop") |
| AC4, the page notice | `SessionOps.Unpair` passes `""` for the page's notice key (temporary, Lane B) | `TestStop` (Texts(121)); T5 (`Replies(110)`) |
| AC4, the view | `telegramCardView` ignores `justUnpaired` | T5 and T6 (no `data-state="just-unpaired"`) |
| AC4, 5 s | `JUST_UNPAIRED_MS` = 1000, then 9000 | T6 (gone before 4000 ms; then later than 8000 ms) |
| AC4, the announcement | No announcement on true → false | T5 and T6 ("Telegram unpaired" not announced) |
| AC4, the heading | The paired root has no `data-row-key` | T5 and T6 (the heading is not focused) |
| AC4/AC5, focus stays | The card focuses the heading itself on every true → false (a `.focus()`) | T6 (the composer loses focus); `announce-focus-sources` (`FOCUS_CALLS`) |
| AC5, moved | `SessionOps.Unlink` skips `Announce` when the reason is `moved` (temporary, Lane B) | `TestOneLivePairing` (no `paired` 0 event on A); T6 (the card stays paired) |
| AC5, the other chat | `SessionOps.Pair` passes `""` for `pairing.otherChatPaired` (temporary, Lane B) | `TestOneLivePairing` (Texts(123)) |
| AC5, unpaired from then on | The "other" branch reads the chat as paired (no reply) | `TestOneLivePairing` (no NOTPAIRED for 123) |

Mutations run at the implement stage (each applied, seen red, reverted byte for byte against a backup; `git status` shows no Lane B path changed; a Lane B mutation needed a restart of the `SessionOps` job on the warm stack, because the job keeps the class it loaded):
- mutation: `Pair` sends nothing after an outcome other than `paired` -> `TestBadCodes` ("the chat gets the bad-code reply four times"); T6 ("chat 113 is told that the code did not work")
- mutation: `SessionOps.Reject` also calls `Announce(sessionRef, 0, "")` (temporary) -> `TestBadCodes` ("no pairing event reached any stream"); T6 ("the card stays paired": the card showed "Telegram unpaired")
- mutation: `SessionOps.Reject` skips `WriteAudit` (temporary) -> `TestBadCodes` ("four rejected Pairing entries on telegram")
- mutation: the start branch matches `/start` only, not `/help` -> `TestStrangerReplies` ("the chat gets the start text twice ...")
- mutation: `TakeReplySlot` is not called -> `TestStrangerReplies` ("the chat gets the start text twice and the not-paired text once", "the row holds ReplySlotAt")
- mutation: `TelegramIn` also sends an `OcuTalon.Msg.Item` to `Conversation` for the unpaired chat (a fixed text, as `Other` has not the message) -> `TestStrangerReplies` ("no request header reaches Conversation")
- mutation: the not-paired `Notification` carries a session `Ref` as `SessionRef` -> `TestStrangerReplies` ("notice 3 is by the row's Ref, with no session and no slots")
- mutation: `Install.Step.Core.Purge` returns OK without calling `Pairing.Purge` (temporary) -> `TestStrangerReplies` ("the aged row with no session is gone")
- mutation: `/stop` is "other" (no `Unpair` submitted) -> `TestStop` ("there is one Unpair body"); T6 ("the card showed \"Telegram unpaired\"", with that mutation alone)
- mutation: no reply on `unpaired` -> `TestStop` ("the chat got the confirmation and the stopped text"); T6 ("chat 111 got the confirmation and the unpaired text")
- mutation: no re-record with `""` after `unpaired` -> `TestStop` ("the row has no session and no name")
- mutation: `SessionOps.Unpair` passes `""` for the page's notice key (temporary) -> `TestStop` ("the chat got the confirmation and the from-page text"); T5 ("the chat was told of the unpair")
- mutation: `telegramCardView` ignores `justUnpaired` -> T5 ("the card shows that Telegram was unpaired"); T6 failed too, but that run also held the `/stop`-is-other mutation, so T6 is not separately evidenced for this one
- mutation: `JUST_UNPAIRED_MS` = 1000 -> T6 ("the card still shows \"Telegram unpaired\" 992 ms after it was first seen")
- mutation: `JUST_UNPAIRED_MS` = 9000 -> T6 ("and no later than 8000 ms after it", received 8951)
- mutation: no announcement on true -> false -> T5 ("\"Telegram unpaired\" is announced", received 0); T6 not separately evidenced (that run held the "Pair sends nothing" mutation, which fails T6 first)
- mutation: the paired root has no `data-row-key` and `data-section` -> T5 ("the focus went to the Telegram heading", inactive); T6 not separately evidenced (that run held the `Reject` `Announce` mutation, which fails T6 first)
- mutation: the card focuses the heading itself on every true -> false (a `.focus()`) -> T6 ("the composer keeps focus"); `announce-focus-sources` ("has a .focus( call only in the files that ...", with `npm --prefix web test`)
- mutation: `SessionOps.Unlink` skips `Announce` when the reason is `moved` (temporary) -> `TestOneLivePairing` ("one pairing event with paired 0 reaches A's stream"); T6 ("the card showed \"Telegram unpaired\"" at the move: the card stayed paired)
- mutation: `SessionOps.Pair` passes `""` for `pairing.otherChatPaired` (temporary) -> `TestOneLivePairing` ("chat 123 got the confirmation, the other-chat notice and then the not-paired text")
- mutation: the "other" branch quits as if the chat were paired (no reply) -> `TestOneLivePairing` ("chat 123 got the confirmation, the other-chat notice and then the not-paired text"); `TestStrangerReplies` fails too
- mutation: `Other` replies to a paired chat too (its `If sessionRef '= "" Quit` line removed) -> `TestNameOnlyWhilePaired` ("a paired chat gets the confirmation and the bad-code reply, and no reply to its other messages", and the `/help` assertion), found at review

Tests added and mutations demonstrated at the QA stage (QA):
- (QA) `web/scripts/telegram-card-view.test.mjs` (new; `npm --prefix web test` picks it up by the existing `scripts/*.test.mjs` glob, no `package.json` change): pins the card view's state order on the framework-free view (paused, then not set up, then paired, then just unpaired, then none or unpaired), the 5000 ms constant and the text. It closes DW-527.
- mutation (QA): the `if (own.justUnpaired)` line of `telegramCardView` moved above the not-set-up/paired branch -> `telegram-card-view.test.mjs` ("shows paired, not just unpaired, when a pairing happens inside the 5 s window", "... with no name", "shows not set up ahead of just unpaired"); moved above the paused branch too -> also "shows paused ahead of just unpaired". Reverted; `cmp` identical.
- T6 pins its own rows independently. The other tests of the file were set to `test.skip` in a temporary copy (`.only` is refused by `forbidOnly`), so T6 ran alone on a fresh stack (`e12s5qa`), after `ci/iris.sh build` for each web mutation. Each was reverted, `cmp` against a backup was identical, and the tree was unchanged (`git status --short`):
  - mutation (QA): `telegramCardView` ignores `justUnpaired` (the line removed) -> T6 alone ("the card showed \"Telegram unpaired\"")
  - mutation (QA): no announcement on true -> false (the `announce(TELEGRAM_CARD_TEXTS.unpaired)` line removed) -> T6 alone ("\"Telegram unpaired\" was announced once")
  - mutation (QA): the paired root has no `data-row-key` and `data-section` -> T6 alone ("the focus went to the Telegram heading")
- (QA) `npm --prefix web test`: 1137 passed, 0 failed (1127 before, plus the 10 cases of the new file). `npm --prefix web run lint`: clean.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `TelegramIn` now reads the command of each private message and answers through the one reply path: a code that does not pair gets `pairing.badCode`, a bare `/start` and `/help` get `pairing.start`, `/stop` submits `Unpair` (origin `telegram`) and gets `pairing.stopped`, and any other message from an unpaired chat gets `pairing.notPaired` once a minute through `TakeReplySlot`. The Telegram card shows "Telegram unpaired" for 5 s whenever `paired` turns false, announces it once, and its paired root is a row of the Telegram section, so the rail's own focus rule takes a lost focus to the Telegram heading (no focus code in the card, `status-rail.ts` and `FOCUS_CALLS` untouched).

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls`: command dispatch (`Command`, `Stop`, `Other`, `Forget`, one `Reply`), `LOGSTOP`, class doc.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPair.cls`: `TestBadCodes`, `TestStrangerReplies`, `TestStop`, `TestOneLivePairing`, helpers, `NewCode` lifetime, paired-chat reply assertions in `TestNameOnlyWhilePaired`.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramIn.cls`: `TestPrivateOnly` asserts the one `pairing.notPaired` notice.
- `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls`: `DropSessions` public, `PairBodies` takes a verb.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls`: `Send`, `Move`, `Finish` drops fixture sessions.
- `web/src/app/rail/telegram-card/telegram-card-view.ts`, `telegram-card.ts`: the `just-unpaired` view, `JUST_UNPAIRED_MS`, the announcement and the row attributes.
- `web/e2e/demo-path/telegram-page.spec.ts`: T5 extended, T6 added.
- `web/scripts/ux-strings.test.mjs` (one string) and `web/scripts/announce-focus-sources.test.mjs` (two text entries): the standing and the 12.4 rulings.

**Review findings.** 31 findings (high 0, medium 1, low 12, false 18).
- Patches applied: 3 entries (1 medium, 2 low). `/stop` answered `not_paired` after a stale paired read now goes to `Other` as unpaired (In.cls); `TestNameOnlyWhilePaired` now asserts a paired chat's replies, with a mutation line (the `Other` mutation is red there).
- Deferred: 1 (the card view's state order has no node-level unit test; the fix is a new Lane B-directory file, which needs a ruling; see frontmatter `deferred:`).
- Rejected: all others, each with its reason in the Review Triage Log (specified behaviour, unreachable path, or low and not worth the added complexity).

**Follow-up review recommended:** false (patched: medium 1, low 2; no high, fewer than two medium).

**Verification performed.**
- `npm --prefix web test`: 1127 passed, 0 failed. `npm --prefix web run lint`: clean.
- Warm stack: `TelegramPair`, `TelegramIn`, `TelegramOut`, `TelegramNoToken` passed (also after the review patches for `TelegramPair` and `TelegramIn`).
- `ci/iris.sh live demo-path`: 18 passed, 8 skipped (not-built placeholders), 0 failed; STEP 1 page: 12 passed, 0 skipped; floor 13 of 13.
- Either-order browser check (the four describe blocks of `telegram-page.spec.ts` reversed, then restored and `cmp` identical): STEP 1 12 passed, 0 failed.
- `ci/iris.sh shard lane-a@Channel`: passed (9 classes, 363 s); `--reverse`: passed (390 s).
- `live sign-in --part 1/2` (127 passed) and `--part 2/2` (96 passed).
- `test-ci-config.sh`, `test-boundaries.sh` (also after the patches) and `ci/checks.sh`: all passed.
- `ci/changes.sh ci.yml --paths-from <file>`: every group runs (no base: "event none"), so the groups to expect in CI are install-fresh, install-upgrade, production, browser, shards, shards-2 and image.
- The Lane B path `git status` check printed nothing.
- Mutations: 21 table mutations applied, red and reverted at the first pass (see `mutation:` lines under `## Verification`), plus one at review. A Lane B mutation needed a restart of the `SessionOps` job on the warm stack.
- Runtimes: the warm tag `e12s5implw` and the fresh tag `e12s5impl` are torn down.

**New test durations (local, throwaway stack).** `TelegramPair` 59.7 to 62.7 s (was about 17 s; above the spec's 40 to 55 s estimate), T5 17.9 s, T6 24.6 s; `live demo-path` 2.8 min. Estimate for CI: `production` about +1.5 to 2 min and `browser` about +1 to 1.5 min over the last green head (31 and 28 min), inside REL-4's 35.

**Residual risks.**
- The card view's state order is pinned only by the browser tests (deferred).
- T6's 4000 and 4500-8000 ms windows assume a poll lag under 500 ms on the CI runner.
- Heading focus relies on the rail's `keepFocus` effect running on the same change; T5 and T6 measured it as working.
