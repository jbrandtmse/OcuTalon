---
title: 'Story 12.4: A valid code pairs the chat with the session'
type: 'feature'
created: '2026-10-31'
status: 'done'
baseline_revision: '70a51053232a3d3f6f45e8471d7eb5103be0be4f'
baseline_commit: '70a51053232a3d3f6f45e8471d7eb5103be0be4f'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-1, AD-4, AD-12, AD-13, AD-14, AD-17, AD-22, AD-29, AD-32 and AD-33)'
warnings: ['oversized']
deferred:
  - summary: >-
      SessionOps.Unlink keeps DisplayName in a row it unpairs, so an unpaired row holds a name until that chat writes again.
    evidence: |-
      Core/SessionOps.cls Unlink clears SessionRef and SeenAt only. TelegramIn clears the name on the chat's next update (this story), but between a page Unpair and that update the row holds a name with no session. No AC of this epic needs a change; a one-line Lane B change (clear DisplayName on unlink) would close the window.
    location: >-
      src/ocutalon/cls/OcuTalon/Core/SessionOps.cls (Unlink)
    severity: low
---

<intent-contract>

## Intent

**Problem:** Lane B's Story 10.3 built the session side of pairing: `SessionOps` carries out `Pair` (link, used mark, `Pairing` audit entry, `pairing` live event), `Notify` routes a `pairing` `Notification` with a `ChatRef` to `TelegramOut` alone, `/state` and the live store carry `paired` and `displayName`, and the guide computes its paired variant. Story 12.3's card shows a code as a QR code. But `TelegramIn` (Story 12.2) only records each private chat with no name: it never reads `/start <code>`, never submits a `Pair`, never sends the confirmation, and the card has no paired view. And once a name is stored, `TelegramIn`'s `RecordChat(chatId, "")` would blank it on the chat's next message (DW-486).

**Approach:**
- `TelegramIn` reads `/start <code>` from a private chat:
  - it records the chat with its name through `RecordChat`;
  - it hashes the code with `Pairing.HashCode`;
  - it submits `Msg.Command.Pair {CodeHash, ChatRef}` through `Commands.Submit` with origin `telegram`.
  - On the outcome `paired` it sends a `pairing` `Notification` with the chat's `ChatRef` and the key `pairing.paired`. `Notify` sends it to `TelegramOut`.
- The chat's name is kept only while the chat is paired, so a later message never blanks it (DW-486) and an unpaired row holds no name.
- The card gets its paired view: the `circle-check` icon, "Telegram paired · {name}" and a one-press ghost "Unpair" button named "Unpair Telegram". The card announces "Telegram paired" once when the pairing arrives.
- Two tests drive the real chain against the CI mock:
  - a live IRIS class, `Test.Channel.TelegramPair`: the command, the confirmation, the name kept out of the trace, and the guide;
  - browser test T5 in `telegram-page.spec.ts`, which replaces Story 12.4's `notBuilt` line. It reads the code from the "Open in Telegram" link, injects `/start <code>`, and sees the paired card within 5 s, the announcement and the reply.

## Boundaries & Constraints

**Always:**
- **What `TelegramIn` treats as a pairing.** Only an update whose `message.text` starts with `/start ` (with the space), from a private chat, followed by a payload that is not empty once trimmed of white space. The payload is the code.
  - A bare `/start`, `/help`, any other text and button presses submit nothing. Story 12.5 replies to them.
  - Group and channel traffic stays ignored, as in 12.2.
- **The order for a pairing update:**
  1. `RecordChat(chat.id, name)`, which gives the chat's `Ref`;
  2. `HashCode(payload)`;
  3. the `Pair` command, with `CodeHash` = the hash, `ChatRef` = the `Ref` and no `SessionRef`;
  4. `Commands.Submit(command, "telegram", .result)`.

  The payload is never put in a message, header, status text, log line, live event or audit entry. A warning names only the step that failed, through `Api.Safe` of the exception's name or of a status text that holds no payload.
- **The reply.** Only for `result.Outcome = "paired"`:
  - one `OcuTalon.Msg.Notification` with `Kind` `pairing`, `ChatRef` = the chat's `Ref`, `CatalogKey` `pairing.paired`, `Slots` `{}`, and `SessionRef` = the paired session, read back with `Pairing.Chat(ref).SessionRef`;
  - it goes to `Notify` with `SendRequestAsync` from `TelegramIn`. `TelegramIn` never calls `sendMessage` itself (AD-1: only business operations send).
  - Every other outcome, and a refused `Submit`, sends nothing in this story (Story 12.5 adds the "That code didn't work" reply).
- **The chat's name** is the update's `chat.first_name` (a string; anything else counts as no name). It is stored only while the chat is paired:
  - **for a pairing update:** the update's name, so that `SessionOps.Link` puts it in the `pairing` event. After an outcome other than `paired`, when the chat's row has no `SessionRef`, `TelegramIn` records the chat again with `""`, so a failed attempt leaves no name behind;
  - **for any other private update:** when the chat's row is paired (it has a `SessionRef`), the update's name, or the stored name when the update has none (DW-486); otherwise `""`;
  - "the chat's row" is read before `RecordChat`, read-only, with the same lookup `RecordChat` makes (`SELECT TOP 1 SessionRef, DisplayName FROM OcuTalon_Data.Pairing WHERE ChatId = ? ORDER BY ID`);
  - the `from` object's names and user name are never read.
- **The card's order of states:**
  1. paused (12.8);
  2. not set up (`off`, `rejected`, or a refused code; 12.3);
  3. **paired**: `state` `on` and `paired` true, with or without a bot name;
  4. nothing (`on` with no bot name, or no code yet);
  5. unpaired (12.3).
- **The paired view** holds one row, in this order, with the root's `data-state="paired"`:
  - the `circle-check` icon at 16 px, `aria-hidden`, coloured `var(--telegram-card-paired-icon)`;
  - the text "Telegram paired · {name}", or "Telegram paired" alone when `displayName` is empty;
  - an `app-server-button` with variant `ghost`, visible text "Unpair" and `label` "Unpair Telegram" (its accessible name).

  The row has no link, QR code, image or code. Its press calls `ApiClient.unpair()`, once, with no confirmation (EXPERIENCE "Unpair acts on one press").
- **The announcement.** The card says "Telegram paired" through the `Announcer`:
  - once, when the store's `telegram.paired` changes from false to true while the card exists, and the card's view is then `paired`;
  - never for the first value the card sees: a page loaded or reloaded while paired announces nothing.
- **Texts.** The new card texts join `TELEGRAM_CARD_TEXTS` and are bound by interpolation, with the middle dot written `·` (Rule 14):
  - "Telegram paired · {name}" (EXPERIENCE.md:356 and :507 as "Telegram paired · Dana"; DESIGN.md:782 with `{name}`);
  - "Telegram paired" (EXPERIENCE.md:435);
  - "Unpair" (EXPERIENCE.md:241; DESIGN.md:782, a ghost button);
  - "Unpair Telegram" (EXPERIENCE.md:406).

  The confirmation is the catalog's `pairing.paired`, unchanged (EXPERIENCE.md:715).
- **The tests** run on throwaways and in CI only, against the CI mock and its dummy token:
  - Telegram is turned on only through the seam (`setTelegramIncluded(1)` / `Fixture.SetTelegramIncluded(1)`), and the seam is restored in `finally` or `Cleanup`;
  - every test that starts an item stops it and puts its row back;
  - fixture chat ids are `840177341xx` (11 digits, so that a search for one cannot match an ordinary number);
  - every IRIS script prints its `CHK|` lines on every path.

**Never:**
- No change to:
  - `Data/Pairing.cls`, `Core/SessionOps.cls`, `Core/CommandsIn.cls`, `Core/Rule/Notify.cls`, `Web/Api.cls`, `Demo/Guide.cls`, `Live/Publish.cls`, `Msg/Catalog/Core.cls`, `Included()`, or any other Lane B class;
  - `api/*`, `live/*`, `shared/*`, `guide/*`, `rail-view.ts`, `status-rail.ts`, `icon.ts`, `web/e2e/support/**`, `rail.spec.ts`, `api/pairing.spec.ts`;
  - `ci/units.sh`, `ci/mock/**`, `Test/Contract/Mock.cls`, `README.md`, `web/package.json` or the lockfile;
  - any contended file of the dispatch.
- No Lane B `web/` edit beyond the entries under Design Notes, "Footprint" (two standing-ruling files, plus one file that needs a ruling).
- No "just unpaired" state, no "Telegram unpaired" announcement, no focus move after Unpair, and no reply to a bad code, a bare `/start`, `/help`, `/stop` or other text. These are Story 12.5's.
- No button presses (12.7), no turns from Telegram and no notification routing beyond the `pairing` reply (12.6).
- No new mock scenario: updates are queued through the mock's `/updates` control.
- No real bot, no call to `api.telegram.org`, no real token.

## I/O & Edge-Case Matrix

These rows assume:
- "P" is a live IRIS test of `Test.Channel.TelegramPair`: `TelegramIn` and `TelegramOut` run on the production against the mock, the seam is 1, and demo mode is on.
  - The session is a fresh fixture session `zztgpair<n>` that watches nothing.
  - Its code is stored with `Pairing.StoreCode(ref, HashCode(code), now + 600 s)`, as the web route stores it.
  - The update is queued through `/_mock/telegram/updates` as `{"message": {"message_id": 1, "from": {...}, "chat": {"id": <id>, "type": "private", "first_name": <name>}, "text": "/start <code>"}}`.
- "T5" is the new browser test. It calls `Start(.saved, "ocutalon_pair_bot", 1)`, signs the README account in, and reads `<code>` from the card's "Open in Telegram" link (`start=`).

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| A valid code pairs (AC1; Integration: `TelegramIn` → `CommandsIn` → `SessionOps`) | P: chat `84017734101`, name "Zqdana", the session's current code | Within 10 s, the chat's row (`ChatId` `84017734101`) holds `DisplayName` "Zqdana" and `SessionRef` = the session, and the code row has `CodeUsedAt` set. Since the mark there is exactly one `OcuTalon.Msg.Command.Pair` body: `CodeHash` = `HashCode(code)`, `ChatRef` = the row's `Ref`, `Origin` `telegram`. One linked `Pairing` audit entry names the session, on channel `telegram`. One `pairing` event on the session's stream: `paired` 1, `displayName` "Zqdana". `StateBody(session).telegram` has `paired` 1 and `displayName` "Zqdana". | — |
| The confirmation (AC2; Integration: `TelegramIn` → `Notify` → `TelegramOut` → the mock) | The same P, read before the guide row's Unpair (whose page notice is Lane B's and Story 12.5's) | Exactly one `sendMessage` to `chat_id` `84017734101`, whose `text` is "You're paired with your OcuTalon session; notifications, reminders and approval requests will arrive here (send /stop to unpair)." (the literal is the oracle; it also equals `Catalog.Render("pairing.paired", "", "telegram")`). Since the mark, one `Notification` body from `TelegramIn` to `Notify`: `Kind` `pairing`, `CatalogKey` `pairing.paired`, `ChatRef` = the row's `Ref`, `SessionRef` = the session. | — |
| Nothing leaks into the trace (AC1, AC3) | The same P, scanned from the marks taken before the update was queued | No message header or body since the mark holds the code, `84017734101` or "Zqdana", and the bodies do hold `HashCode(code)` (the control). No event-log row since the mark holds any of the three, and the probe row is found (the control). No audit entry since the mark holds any of the three. No live event of another stream since the mark holds "Zqdana", and the session's own `pairing` event does (the control). | A reason names the store. |
| The guide follows the real pairing (AC4) | P: before the update, `Guide.Compute(session)` has `TelegramRow` 1 and `Step4Variant` `unpaired` | After the pairing, a `guide.state` event on the session's stream with `step4Variant` `paired` and `telegramRow` false. Then `Commands.Submit(Unpair {SessionRef}, "web_user")` (the page's DELETE path) answers `unpaired`, and a later `guide.state` event has `step4Variant` `unpaired` and `telegramRow` true. | — |
| A stored name survives later messages (DW-486) | P after "A valid code pairs": (a) a private message "zz later" with no `first_name`; (b) one with `first_name` "Zqnew" | (a) The row's `DisplayName` stays "Zqdana" and its `SessionRef` stays. (b) It becomes "Zqnew". | — |
| No name without a pairing (DW-486, AD-4) | P: chat `84017734102` (no row yet), with `first_name` "Zqstranger": (a) "zz hello"; (b) `/start zzNoSuchCode0000000000` | (a) A row with no `SessionRef` and an empty `DisplayName`, and no `Pair` body since the mark. (b) One `Pair` body with `CodeHash` = `HashCode("zzNoSuchCode0000000000")`; nothing is linked, there is no `pairing` event, and the row's `DisplayName` is empty again. | — |
| No pairing without a code | P: from chat `84017734103`, the texts `/start` and `/start    ` (spaces only), and a group chat (`type` `group`) sending `/start <the session's current code>` | No `Pair` body since the mark. The code row's `CodeUsedAt` stays empty. The group chat has no row. | — |
| The page pairs within 5 s (AC3, AC5; T5, the real chain) | T5: the card is unpaired with `<code>`. The IRIS clock agrees with the test's within 250 ms. `Pair(code, 84017734110, "Dana", .queuedAt)` queues the update while a long poll is open | The card shows `data-state="paired"` with the text "Telegram paired · Dana Unpair" no more than 5000 ms after `queuedAt`. One button, named "Unpair Telegram", with visible text "Unpair". The only `svg` is the `circle-check` icon (`aria-hidden`), coloured `--telegram-card-paired-icon`. No link, QR code or `img`. "Telegram paired" is announced exactly once. `Replies(84017734110)` is exactly one text, the confirmation. The guide region holds no "Optional: scan the QR code" line. | — |
| A reload while paired (AC3) | T5, after the pairing: one reload | The card is paired again from the snapshot, with "Dana". Within 3 s of the loaded snapshot, no "Telegram paired" announcement (the first value is not announced). No request for a code. | — |
| Unpair from the card (Unpair acts on one press; the real DELETE) | T5, after the reload: one press on "Unpair Telegram" | Exactly one `DELETE /ocutalon/api/v1/pairing`. The card then leaves `paired` and becomes `unpaired` with a fresh code (not `<code>`), within 10 s. The README session's `/state` has `paired` false. | — |
| The paired card from a snapshot (T4, extended) | T4's changed `/state`: `state` `on`, `paired` true, `displayName` "Zz", then again with `displayName` "" | `data-state="paired"`: "Telegram paired · Zz Unpair", then "Telegram paired Unpair". The button is named "Unpair Telegram". No request for a code within 3 s, no QR code and no pairing link. | — |

</intent-contract>

## Code Map

**Lane A's files (edit freely)**
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls`:
  - `HandleUpdate` :250-261 is today's private-chat handler (`RecordChat(chat.id, "")`);
  - `Handle` :231-247 wraps each update in a `Try`, logs `LOGUPDATE` with `Safe(exception.Name)`, and keeps the offset whatever happened;
  - the class doc :17-18 says "records the chat through Pairing.RecordChat with no name";
  - the log texts are the `LOG*` parameters :52-64;
  - `Api.Safe` is used on every log text.
- `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls`, the base of the live tests. Its class doc lists the public helpers.
  - `ReadyLive` :92, `StartItems` :107 / `StopItems`, `Enable` :128, `Disable` :167 (safe for an item that is already disabled);
  - `Chat` / `DropChats` / `ChatRows` (private, :229-251), `HeaderMark` :253, `HeadersFrom` :261, `RowsText` :269, `Bodies` :282, `LiveMark` :304;
  - `FixtureSession` / `DropSessions` (`zztg…`), `Cleanup` :333;
  - `CallsOf` :344, `WaitCalls` :355, `WaitState` :379, `EpochNow` :505 (Horolog seconds, not Unix);
  - `QueueUpdates` :513 and `PrivateMessage` :518 (no `first_name`), both private.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramIn.cls`:
  - `TestPrivateOnly` :166-201 asserts `"|"` (no session, no name) for chats with no `first_name`. It stays green unchanged, because its updates carry no name and no row is paired;
  - `TestRestartLosesNothing` uses the scripted `telegram-private-update` ("Ci Private", unpaired), so it stores no name.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls`:
  - `Start(Output saved, botName = "")` :48-81 (`Enable(..#ITEM, .rows)` at :73);
  - `Finish(saved)` :126-152 (`Disable(..#ITEM, rows)` at :136, `DropCodes` at :140);
  - `Pack` :304 (`$ListBuild(rows, marks, since, codes)`), `CodeRefs` :310, `DropCodes` :322;
  - the class doc :1-17.
- `web/src/app/rail/telegram-card/telegram-card-view.ts`:
  - `TELEGRAM_CARD_TEXTS` :29;
  - `TelegramCardView` :75-80 (`kind`, `retry`, `link`, `minutes`; one flat shape, 12.8's Decided 13);
  - `telegramCardView` :135-150, with the precedence at :141-148;
  - the module doc :1-22.
- `web/src/app/rail/telegram-card/telegram-card.ts`:
  - the template :51-80 (`data-state` blocks) and the styles :81-138;
  - `imports: [Icon]` :49;
  - `inject(LiveState)` and `inject(ApiClient)` :144-145, `askKey` :163 (already excludes `paired`), `view` :170;
  - the class doc :24-46.
- `web/e2e/demo-path/telegram-page.spec.ts`:
  - the header :10-30;
  - the top-level helpers :34-181 (`cardOf`, `railOf`, `mainOf`, `loaded`, `fixture()`, `recordRequests`);
  - T1 (12.8 and 12.3) from :182, the 12.3 describe :331 (`BOT`, `CODE`, `routeCodes`, `expectCode`), T3 :417;
  - T4 :545-630, with its paired case at :577 and :594 ("the card shows no state of its own yet");
  - `notBuilt(…, '12.4')` :630, and the `notBuilt` import :8.

**Called, never edited**
- `Data/Pairing.cls` (Lane B, contended):
  - `HashCode` :68;
  - `RecordChat(chatId, displayName, .sc)` :79-123: it sets `DisplayName` unconditionally (:111), strips control characters and cuts the name to 128;
  - `Chat(ref)` :195, `ForCode` :205, `StoreCode` :155.
- `Core/Commands.cls:17` `Submit(command, origin, .result)`: `CreateBusinessService("CommandsIn")` and `ProcessInput`. `Msg/Command/Pair.cls` has `CodeHash` and `ChatRef`. `Core/CommandsIn.cls:173` accepts `Pair` from `telegram` only.
- `Core/SessionOps.cls`:
  - `Pair` :136-173: the outcomes `paired`, `unknown_chat`, `unknown_code`, `used_code`, `expired_code` and `failed`, and a used code repeated by its own chat answers `paired`;
  - `Link` :177-210 reads `chat.DisplayName` into the `pairing` event (`Announce` :403);
  - `Unlink` :95-133 clears `SessionRef` but keeps `DisplayName`, and sends `pairing.unpairedFromPage` for a page Unpair.
- `Core/Rule/Notify.cls:31-33`: kind `pairing` with a `ChatRef` goes to `TelegramOut` when `TelegramOn()` (the seam).
- `Channel/Telegram/Out.cls:63-80` `OnNotification` → `Deliver(chatRef)` → `Pairing.Chat(ref).ChatId`.
- `Msg/Catalog/Core.cls:17` `pairing.paired`. `Msg/Notification.cls` (`SessionRef`, `ChatRef`, `Kind`, `CatalogKey`, `Slots`).
- `Live/Publish.cls:21` `GUIDETRIGGERS` holds `pairing`, so a `guide.state` follows a pairing in demo mode. `Demo/Guide.cls:101-109`: `Step4Variant` and `TelegramRow` from `Ownership.Pairing`, with an incident's `OpenVariant` winning (so T5's README session, which earlier specs give incidents, cannot pin the variant).
- `Web/Api.cls:765-783` `StateBody`: `telegram.paired` / `displayName` and `guide`. `DELETE /v1/pairing` submits `Unpair` as `web_user`.
- The IRIS test helpers:
  - `Test/Core/Observe.cls:47` `Events(session, type, count, seconds)`;
  - `Test/Data/Fixture.cls:179` `SetTelegramIncluded` (it returns the old value);
  - `Test/Bridge/AuditLog.cls` `Now`, `Entries` and `Wait`;
  - `Test/Agent/RunnerFixture.cls` `EventMark`, `LogRowsHolding` and `RunningReason`;
  - `Core/Rule/Functions.cls:19` `DemoOn`;
  - `Test/Contract/Mock.cls`: `Control("updates", [...])` :417, `Calls()` :429 (each call's `params`, so `sendMessage`'s `chat_id` and `text`), and `TELEGRAMBASE`;
  - Lane B's `Test/Core/SessionOpsProduction.cls:82-146`, the pattern of the audit and event assertions, and the evidence that the session side already works with a fixture caller.
- The page:
  - `api/api-client.ts:112` `unpair()` (a DELETE of `/pairing` with `{}`);
  - `shared/server-button.ts` (inputs `action`, `variant` with `ghost`, `label`; busy and notice built in; already a speaker);
  - `shared/announcer.ts` `announce(text)`;
  - `live/live-store.ts:182-183` (a `pairing` event sets `paired` and `displayName`);
  - `styles/tokens.css:284` / `:670` `--telegram-card-paired-icon`;
  - `icon/icon.ts` has `circle-check`.
- The e2e support:
  - `support/page.ts:56` `recordAnnouncements`, `:87` `announcedTexts`, `plain`, `tokenColor`;
  - `support/iris.ts` `irisScript`, `chk`, `quoted`, `setTelegramIncluded`;
  - `support/floor.ts` `signInReadmeLoaded`;
  - `support/api.ts` `changeSnapshot`.
- The source pins (Lane B, read except the three entries below):
  - `scripts/ux-strings.test.mjs:200-230` (`SOURCES`);
  - `scripts/api-client-sources.test.mjs:112-131` (the Telegram parts row `['telegram-page.spec.ts', 'page', 0, '12.4', true]`);
  - `scripts/announce-focus-sources.test.mjs:85-111`: the rail files are silent, and the speakers are a closed list;
  - `page-safety.test.mjs`, `floor-sources.test.mjs`, `shell-styles.test.mjs`.

## Tasks & Acceptance

**Execution:**
1. `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls` (DW-486, AD-1, AD-4, AD-14):
   - `HandleUpdate` follows the Boundaries:
     1. it reads the chat's row (`SessionRef`, `DisplayName`) before `RecordChat`;
     2. it works out the name to record by the Boundaries' rule;
     3. it calls `RecordChat` with it;
     4. for a pairing update it calls a new private `Pair(ref, chatId, payload)`.
   - `Pair` does the hash, the command and `Submit` with `telegram`.
     - On `paired` it sends the `Notification` to `Notify`.
     - On any other outcome, or a refused `Submit`, it records the chat again with `""` when `Pairing.Chat(ref).SessionRef` is empty.
   - New log texts are parameters (for example `LOGPAIR`, "TelegramIn could not submit a pairing: ", and `LOGREPLY`), each followed only by `Api.Safe` of a status text or an exception's name.
   - The class doc replaces "with no name" with the name rule, names the `/start <code>` path and its one reply, and says that Story 12.5 replies to everything else.
2. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPair.cls` (new; extends `LiveCase`; `Test` methods, so it joins `shard:lane-a@Channel` with no `ci/units.sh` change):
   - **Its setup and ending.**
     - `ReadyLive`, and demo mode is on (`Functions.DemoOn()`; otherwise the test fails with that reason);
     - `Fixture.SetTelegramIncluded(1)`, with the old value put back in its cleanup;
     - `StartItems("TelegramOut,TelegramIn")`, `WaitState("on")`, and a long poll open (`WaitCalls("getUpdates", 1)`);
     - the cleanup deletes the code rows of its fixture sessions (`CodeSessionRef` = the fixture `Ref`) and the fixture chats (`Chat`/`DropChats` with `840177341xx`), and ends with `Cleanup`.
   - **Its tests**, one per matrix row group:
     - `TestPairs`: the rows "A valid code pairs", "The confirmation", "Nothing leaks into the trace" and "The guide follows the real pairing".
       - The marks: `HeaderMark`, `AuditLog.Now`, `LiveMark` and `RunnerFixture.EventMark`.
       - The event-log control is an `Ens.Util.Log.LogInfo` probe with a unique text, removed afterwards (12.3's `CodeSearch` pattern).
     - `TestNameOnlyWhilePaired`: the rows "A stored name survives later messages" and "No name without a pairing".
     - `TestNoPairWithoutACode`: the row "No pairing without a code".
   - Helpers it needs and `LiveCase` lacks (a private update with a name and a text; the `sendMessage` texts to one chat; a `Pair` body count since a mark):
     - each is written once, here or as a public class method of `LiveCase`;
     - `LiveCase`'s private `QueueUpdates` and `PrivateMessage` are extended, not copied (Rule 2);
     - `TelegramPageFixture` reuses whichever become public.
   - The class doc lists its tests and says it runs in throwaways and CI only.
3. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls`:
   - **`Start(Output saved, botName = "", out As %Boolean = 0)`.** With `out` 1, it enables `TelegramOut` before `TelegramIn`, through the same `Enable(item, .rows)`, so `rows` holds both snapshots.
   - **`saved`'s fourth element** becomes the `Ref`s of every `Pairing` row at Start (code rows and chat rows). `CodeRefs`/`DropCodes` become `RowRefs`/`DropRows` over every row.
   - **`Finish`:**
     - it disables `TelegramIn,TelegramOut` (`Disable` is safe for an item that was never enabled);
     - then it deletes every `Pairing` row that Start did not find, and reads the rows back, as now.
   - **New methods, each returning "" or a reason with no token (`Safe`):**
     - `Now()`: the IRIS clock as Unix milliseconds;
     - `Pair(code, chatId, name, Output queuedAt)`: it waits for an open long poll, then queues one private `/start <code>` update with `chat.first_name` = name. `queuedAt` is the Unix milliseconds taken just before the `/updates` call;
     - `Replies(chatId, Output texts)`: the `text` of every `sendMessage` to that `chat_id`, in order, as a JSON array.
   - The class doc covers `out`, the row removal, and the three methods.
4. `web/src/app/rail/telegram-card/telegram-card-view.ts`:
   - `TELEGRAM_CARD_TEXTS` gains `paired` (`'Telegram paired · {name}'`), `pairedAlone` (`'Telegram paired'`, also the announcement), `unpair` (`'Unpair'`) and `unpairLabel` (`'Unpair Telegram'`).
   - `TelegramCardView` gains the kind `paired` and a field `paired`: the paired line, "" in the other views.
   - `telegramCardView` puts paired third, as the Boundaries say, from `displayName`.
   - The module doc gains the paired state and drops "Story 12.4 adds that view".
5. `web/src/app/rail/telegram-card/telegram-card.ts`:
   - **Imports:** `ServerButton` beside `Icon`. **Injects:** `Announcer`.
   - **The paired block** (data-state `paired`, one row): the icon, the line, and `<app-server-button variant="ghost" [label]="…unpairLabel" [action]="unpair">{{ …unpair }}</app-server-button>`. `unpair` returns `this.api.unpair()`. `.paired-icon` takes `color: var(--telegram-card-paired-icon)`. There is no height and no transition.
   - **The announcement:** an effect that remembers the previous `telegram().paired`, skips the first value, and announces `pairedAlone` on false → true when `view().kind` is `paired`.
   - The class doc gains the paired state, the one-press Unpair, the announcement, and that the Unpair press moves no focus in this story (Story 12.5 adds the "just unpaired" state and the heading focus).
6. `web/scripts/ux-strings.test.mjs` (standing ruling, by entry): `SOURCES.ux` gains the four strings, beside 12.3's:
   - "Telegram paired · {name}" (the test's `holds` reads a slot as a non-empty run, so EXPERIENCE.md's "Telegram paired · Dana" holds it);
   - "Telegram paired", "Unpair" and "Unpair Telegram".

   The UX comes first (the test's "names the UX first" rule), so none of the four takes the source `design`. If EXPERIENCE.md does not hold one, that entry is a `## Clarification Needed`, never an invented source.
7. `web/scripts/api-client-sources.test.mjs` (standing ruling, by entry): the Telegram-parts test no longer expects a `notBuilt` in `telegram-page.spec.ts`.
   - The row for that file asserts: no `notBuilt` call and no `not-built` import, tests of its own, no skip, fixme or only, and that it is a part of the `page` step (`stepOfFile`).
   - The `telegram-approval.spec.ts` row (12.7) is unchanged.
8. `web/scripts/announce-focus-sources.test.mjs` (**needs the runner's ruling**; Design Notes):
   - `app/rail/telegram-card/telegram-card.ts` leaves the silent rail files and joins the speakers list;
   - the reason in the comment: the pairing change is announced once, from the card that shows it (UX-DR132, Story 12.4).
9. `web/e2e/demo-path/telegram-page.spec.ts`:
   - The header names Story 12.4's T5 and T4's paired cases, and drops the `notBuilt` paragraph. The `notBuilt` line and its import go.
   - **T4** (paired cases): the two rows of "The paired card from a snapshot". The case `paired, no name` is added beside `paired`.
   - **T5** in a new `test.describe('a valid code pairs the chat with the session (Story 12.4)')` (`@floor`, `test.setTimeout(150_000)`): the rows "The page pairs within 5 s", "A reload while paired" and "Unpair from the card".
     - The clock check: `before = Date.now()`, then `Now()`, then `after`. The IRIS time must fall in `[before − 250, after + 250]`.
     - The 5 s bound is `shownAt − queuedAt ≤ 5000`, polled every 100 ms.
     - In `finally`: `Finish(saved)`, then `setTelegramIncluded(was)`, nested as in T3.

**Acceptance Criteria:**
- Given a private chat sends `/start <code>` with the session's current code, when `TelegramIn` reads it, then the chat's id and name are in its `Pairing` row only. One `Pair` command, submitted with origin `telegram`, holds `HashCode(code)` and the row's `Ref`, and no message, log or audit entry holds the code, the chat id or the name. `SessionOps` links the chat, marks the code used, writes the linked audit entry and publishes the `pairing` event (FR-15, FR-18, FR-9, AD-1, AD-4, AD-17). Rows "A valid code pairs" and "Nothing leaks into the trace".
- Given the pairing is linked, when the bot confirms it, then the chat gets exactly the `pairing.paired` text, through a `pairing` `Notification` by `ChatRef` that `Notify` routes to `TelegramOut` (FR-18, FR-19, AD-14, AD-32, UX-DR109). Row "The confirmation".
- Given the page is open, when the `pairing` event arrives, then within 5 s of the `/start <code>` update the card shows "Telegram paired · {name}" with a one-press "Unpair" button named "Unpair Telegram", and the announcer reads "Telegram paired" once. The name travels only to the session's own page (FR-15, FR-18, NFR-9, UX-DR55, UX-DR56, UX-DR130, UX-DR132). Rows "The page pairs within 5 s", "A reload while paired", "Unpair from the card", "The paired card from a snapshot" and "Nothing leaks into the trace".
- Given demo mode is on, when the guide is computed after a real pairing, then the Telegram row leaves and step 4 takes its paired variant, and after an unpair the unpaired variant returns (FR-16, AD-12, UX-DR44, UX-DR45). Row "The guide follows the real pairing".
- Given the mocked Telegram API, when UJ-1's page step reaches its Telegram pairing part, then that part is a real test (T5) in place of the `notBuilt` line. It reads the code from the "Open in Telegram" link, injects `/start <code>`, and sees the paired card and the confirmation. `live demo-path` prints `STEP 1 page: passed`, with no skipped part (REL-2, AD-29, UX-DR101).
- Given a paired chat writes again, when its update has no name, then the stored name stays. An unpaired chat's row never keeps a name (DW-486, AD-4). Rows "A stored name survives later messages" and "No name without a pairing".

## Spec Change Log

## Review Triage Log

### 2026-10-31 - Review pass
- verdicts: 35 findings - high 0, medium 1, low 30, false 4, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: race between the row read and RecordChat when Unpair lands in between - the window is microseconds and the effect is a name on an unpaired row until the chat's next update; the fix is a lock around two calls, more than a direct correction.
  - `[low]` `[reject]` Blind: an unpaired chat holds its name briefly during a pairing attempt - the Boundaries order requires the name to be recorded first so `SessionOps.Link` can put it in the event; the second `RecordChat` clears it after a failed outcome.
  - `[low]` `[reject]` Blind: a failed `RecordChat` loses the pairing silently - it is logged with a safe text and the update is confirmed (12.2's rule, Decided 4); the user scans again.
  - `[low]` `[patch]` Blind: a pairing update with no `first_name` from a paired chat blanks its stored name - fixed in `HandleUpdate` (the stored name is the fallback for a pairing update too); `TestNameOnlyWhilePaired` (c) pins it.
  - `[low]` `[reject]` Blind: no test that Unpair clears the stored name - `Unlink` is Lane B's and keeps the name (deferred below).
  - `[false]` `[reject]` Blind: no test that a failed pairing sends nothing - Decided 3 pins only "nothing linked" for a bad code, Story 12.5 owns the reply.
  - `[low]` `[reject]` Blind: thin `Payload` parsing coverage (`/start@bot`, upper case, tab) - the spec defines the match as "/start " literally; the listed inputs are not pairings by that rule.
  - `[low]` `[reject]` Blind: `Hang 1` before the "exactly one message" check - a sleep as a negative signal is how an absence is shown; a duplicate would arrive well within it.
  - `[false]` `[reject]` Blind: mixed clocks in the 5 s bound - Decided 10 and T5's 250 ms agreement check measure the offset.
  - `[low]` `[reject]` Blind: `Now()` returns the number through the reason channel in the e2e call - recorded in Decided 14; cosmetic.
  - `[low]` `[patch]` Blind: a long name pushes the Unpair button out of the rail - `.paired` wraps and `.text` breaks anywhere.
  - `[low]` `[patch]` Blind: the speakers test title lost "and, from Story 16.1" - the title is reworded.
  - `[low]` `[reject]` Blind: dead `ownTests` ternary in `api-client-sources.test.mjs` - the one remaining row is the 12.7 file and its message is still true.
  - `[low]` `[reject]` Blind: `pairedAlone` is both the line and the announcement - the spec names it as both (Texts).
  - `[low]` `[reject]` Edge: a failed `Row` lookup blanks a paired chat's name - needs an SQL error on a plain SELECT; the fix adds a branch for a case nobody shows reachable.
  - `[low]` `[patch]` Edge: a pairing update with an empty name overwrites a paired chat's name - same fix as the fourth row above; a name that `RecordChat` strips to empty is not handled (negligible).
  - `[low]` `[reject]` Edge: Row/RecordChat race - same as the first row.
  - `[low]` `[reject]` Edge: crash between the named record and the clearing record - same as the second row.
  - `[low]` `[reject]` Edge: a Submit that errors after the command was applied - nothing in the diff shows `CommandsIn` applying and then erroring; Decided 4.
  - `[low]` `[defer]` Edge: `Unlink` keeps `DisplayName` (claim "an unpaired row holds no name") - Lane B code outside this change; recorded in `deferred:` and "For the lead".
  - `[low]` `[reject]` Edge: a replayed used code gets the confirmation again - `SessionOps.Pair` answers `paired` for it by design, and an update is confirmed once.
  - `[low]` `[patch]` Edge: T5's watching loop can reject on a closed page when an earlier step fails - the loop catches and ends.
  - `[low]` `[reject]` Edge: no announcement when the pairing arrives during a pause - the spec announces only when the view is then `paired`; a pairing cannot arrive while TelegramIn is paused.
  - `[medium]` `[patch]` Verification gap: the paired view's precedence (off, rejected, no bot name) has no test - T4 gains `paired, no bot name`, `paired, state off` and `paired, state rejected`.
  - `[low]` `[patch]` Verification gap: "announced exactly once" cannot fail on a later duplicate - T5 waits 2 s and counts again; the second-announcement mutation is red.
  - `[low]` `[patch]` Verification gap: pinning tests without `mutation:` lines - 10 mutations demonstrated and recorded in Verification.
  - `[low]` `[patch]` Verification gap: the audit scan has no positive control - `TestPairs` asserts the scan reads the pairing's entry. The other-stream scan shares the own-stream query's shape, whose control exists.
  - `[low]` `[reject]` Verification gap: a non-string `first_name` is untested - a one-line guard for an input Telegram does not send.
  - `[low]` `[reject]` Verification gap: the error paths of `Row`, `Pair` and `Reply` are untested - they need fault injection that the mock does not offer.
  - `[low]` `[reject]` Verification gap (other): `Row` SQL error blanks the name - same as the fourteenth row.
  - `[low]` `[reject]` Verification gap (other): `Hang 1` - same as the eighth row.
  - `[low]` `[reject]` Verification gap (other): the new `api-client-sources` assertion matches `test(` in a comment - the check exists to keep `notBuilt` out; T4 and T5 are the evidence that tests run.
  - `[false]` `[reject]` Verification gap (other): `Finish`'s failure is only annotated after a failed test - that test is already red, and a pass asserts the reason is empty.
  - `[low]` `[reject]` Intent audit: the announcement count in T5 is a substring match - no other announcement holds "Telegram paired" in that flow.
  - `[false]` `[reject]` Intent audit: `LiveCase` and `TelegramPageFixture` are not named by the intent - both are Lane A files named in the Code Map and Tasks.

## Design Notes

**Governing ADs:**
- **AD-1:** the pairing enters as `Msg.Command.Pair` through `Commands.Submit` with origin `telegram`. `CommandsIn` takes `Pair` from `telegram` only. Only business operations send channel traffic: `TelegramIn` hands the reply to `Notify`.
- **AD-4:**
  - `TelegramIn` hashes the code with `HashCode` before it builds the command, and `SessionOps` compares hashes;
  - the chat id and name live only in the `Pairing` row (`RecordChat`, a direct call), and messages carry `ChatRef`;
  - for pair outcomes, `SessionOps` returns the outcome and `TelegramIn` sends the reply;
  - the name may travel to the session's own page only (`/state`, the `pairing` event);
  - a chat has at most one live pairing (`SessionOps`, unchanged).
- **AD-12:** the guide's paired variant and Telegram row come only from `Guide.Compute`, which `Publish` re-runs after `pairing` in demo mode. The card learns `paired` from the store.
- **AD-13:** the Unpair press goes through the one typed client (`ApiClient.unpair()`), with no `innerHTML` and no bypass.
- **AD-14:** `TelegramIn` handles private chats only. Chat ids and names are never passed to the audit writer or the log macros. `Notify` is the one router.
- **AD-17:** the linked audit entry is `SessionOps`'s, through `Bridge.Audit`. The tests read it back by time, with polling.
- **AD-22:** the tests run in throwaways against the CI mock. Updates are queued through `/updates`, with no mock change.
- **AD-29 and AD-33:** `Channel/Telegram/**`, `Test/Channel/**`, the card folder and `telegram-*.spec.ts` are Lane A's. Lane B classes are called and their tables read, never edited. `TelegramIn`'s read of the chat's row is a read of Lane B's table, which AD-33 allows.
- **AD-32:** the confirmation is a `Notification` of kind `pairing` with a catalog key. Only `TelegramOut` renders it, and no Telegram text is hard-coded.

No acceptance criterion contradicts an AD. The NFRs this story touches are measurable as written: "within 5 seconds" (NFR-9) is measured from the IRIS clock's queue time to the page, with a clock check.

**Footprint (Rule 11; reported under `footprint_extensions:`).**
- **Lane A:**
  - `Channel/Telegram/In.cls`;
  - `Test/Channel/TelegramPair.cls` (new), `TelegramPageFixture.cls` and, if needed, `LiveCase.cls`;
  - `telegram-card.ts` and `telegram-card-view.ts`;
  - `telegram-page.spec.ts`.
- **Lane B, by entry, under the orchestrator's standing ruling:** `web/scripts/ux-strings.test.mjs` (four `SOURCES` entries) and `web/scripts/api-client-sources.test.mjs` (the `telegram-page.spec.ts` row).
- No contended file is touched. `Data/Pairing.cls` is called, and read by SQL, never edited.

**Needs ruling:** `web/scripts/announce-focus-sources.test.mjs` (Lane B; not contended; not in Epic 12's shared-by-entry list).
- **Ruled (runner, 2026-11-01, decide, policy ff1bd1a):** allowed as a file-level extension, by entry, like the orchestrator's standing ruling for `web/scripts/ux-strings.test.mjs` and `web/scripts/api-client-sources.test.mjs` (2026-10-31): only the two entries named below (the `telegram-card.ts` exception beside `credential-rows.ts`, and its speakers-list row with its reason); no other change to the file. Not contended on any open epic branch. The runner reports it under `footprint_extensions:`.
- **The smallest change:**
  - `app/rail/telegram-card/telegram-card.ts` is excluded from the silent `app/rail/` files (the filter at :88, beside the `credential-rows.ts` exception);
  - it is added to the closed speakers list (:94-109), with its reason in the comment.
- **Why:** AC3 says the announcer reads "Telegram paired" (UX-DR132, EXPERIENCE "Pairing changed"). The card is the one place that shows the pairing, and so the one place that should say it once. Without the entry, the announcement can't be built, and `npm --prefix web test` goes red.
- Story 12.5 will need the same file for "Telegram unpaired" (the same speaker) and for its heading focus (a `FOCUS_CALLS` entry).

**Decided in-stage:**
1. **The name is `chat.first_name`.**
   - The UX example shows a first name ("Telegram paired · Dana").
   - It is the least personal data that serves the card.
   - In a private chat the chat object is the other party, so `from` is not read.
2. **A name is kept only while the chat is paired (DW-486).**
   - Story 12.5's AC says an unpaired chat's row holds "nothing but what its replies and the once-a-minute limit need", so a stranger's name must not be stored.
   - A paired chat's later message keeps or refreshes its name and never blanks it.
   - This is done on Epic 12's side, by reading the row first, so `Data/Pairing.cls` (Lane B, contended with Epic 11) is untouched. This is the ledger's preferred route.
   - `SessionOps.Unlink` keeps `DisplayName` after an unpair, until the chat writes again, when `TelegramIn` clears it. See "For the lead".
3. **Only the outcome `paired` gets a reply in this story.** Story 12.5 owns every other reply, so this story pins only "nothing linked" for a bad code, never "no reply".
4. **A refused or failed `Submit`** is one warning with a safe text, and the update is still confirmed (12.2's rule). Telegram resending the update is no remedy, and the user can scan again.
5. **The `Notification`'s `SessionRef`** is the paired session, read back through `Pairing.Chat(ref)`, so the reply belongs to the session like every other notice (AD-4). The `Pair` command carries no `SessionRef`: `SessionOps` finds the session from the code.
6. **The paired view needs `state` `on`.**
   - It does not need a bot name.
   - While `off` or `rejected` the card says "Telegram not set up", the honest state, because nothing reaches the chat then.
   - Paused still wins.
7. **An empty name shows "Telegram paired" alone,** with no separator.
8. **The Unpair button is wired in this story.**
   - It is one press through `ApiClient.unpair()` and the shared `ServerButton`, which brings the busy state and the failure notice.
   - A visible button that did nothing would be a false affordance.
   - The card then simply asks for a fresh code. Story 12.5 adds "Telegram unpaired" for 5 s, the heading focus and its announcement.
   - Until then, the press moves no focus of its own. Telegram is in no release until 12.7, so no user meets that gap.
9. **The announcement skips the first value,** so a page loaded or reloaded while paired is silent. It needs the paired view, so a stale `off` page announces nothing it does not show.
10. **The 5 s window starts at the IRIS clock's time just before the update is queued.** T5 first checks that the IRIS clock and the test's clock agree within 250 ms (the two share the host's clock, inference; the check makes it measured). `irisScript` can retry for 5 s, so a test-side start time would be unsound.
11. **The guide is pinned in IRIS, not in T5.** The README session in the demo-path run gets incidents from earlier specs, and an incident's `OpenVariant` overrides the variant (`Guide.cls:108`), so T5 could not pin it in either order. A fresh fixture session can. T5 checks only what holds in every state: no Telegram row once paired.
12. **`Finish` removes every `Pairing` row that Start did not find** (code rows and chat rows), so T5 leaves no paired chat behind even when it fails before its Unpair (Rule 19).
13. **Where the tests run.**
    - T5 runs in the existing `live:demo-path` unit (`browser` group), and `TelegramPair` in `shard:lane-a@Channel` (`production` group). No unit is added or moved.
    - Expected (inference): T5 about 25 to 35 s locally, about 1 to 1.5 minutes on the runner; `TelegramPair` about 30 to 60 s.
14. **Test helpers (implement stage).**
    - `LiveCase.PrivateMessage(chatId, name = "", text = "zz private", type = "private")` is public and extended in place (the old one-argument call gives the old update); with a name it also carries a `from` object whose names differ, so a test proves that only `chat.first_name` is read. `TextsTo` and `PairBodies` are new public class methods of `LiveCase`.
    - `TelegramPair` waits for an update through the kept offset (the mock numbers updates from 1 after its reset, so the offset becomes the count plus 1), not by sleeping.
    - `TelegramPageFixture.Now()` returns the number (it cannot fail); `Pair` and `Replies` return "" or a reason, with `queuedAt` and `texts` as output.
    - Only a `message` update can be a pairing; a button press never is.
15. **Review patches.**
    - A pairing update with no name keeps a paired chat's stored name, as any other update does (DW-486); an unpaired chat's pairing update takes the update's name.
    - The paired row wraps, and a long name breaks anywhere, so the Unpair button stays in the rail.
    - T4 gains the precedence cases (a bot-less paired card, and a paired session while the state is off or rejected); T5 settles 2 s and counts the announcement again, and its watching loop ends quietly on a closed page.
    - `TestPairs` checks that the audit scan reads the pairing's entry.

**Extend, don't copy (Rule 2):**
- **`HandleUpdate`** stays the one private-chat handler. The pairing path is a private method it calls, not a second handler.
- **The card** extends 12.3's view, precedence and `data-state` hook with one more kind. The button is the shared `ServerButton`, not a new button. The icon row copies the paused row's pattern (`.paused`, its icon token).
- **The fixture** extends `Start` (one more parameter) and `Finish`. `DropCodes` becomes `DropRows`, not a second remover. `Pair` and `Replies` call `Mock.Control` and `Mock.Calls`, as `LiveCase` does.
- **`TelegramPair`** extends `LiveCase` and reuses `RowsText`, `Bodies`, `HeaderMark`, `LiveMark`, `Observe.Events`, `AuditLog`, `RunnerFixture.LogRowsHolding` and the `SetTelegramIncluded` seam. Its private-update helper extends `LiveCase.PrivateMessage` with a name and a text.
- **T5** reuses `fixture()`, `cardOf`, `loaded`, `recordAnnouncements`, `announcedTexts`, `tokenColor`, `signInReadmeLoaded` and `setTelegramIncluded`.

**Integration ACs (Rule 1):**
- The row "A valid code pairs": `SessionOps`, the consumer of `TelegramIn`'s `Pair`, links the chat. Observable: the row, the audit entry and the `pairing` event.
- The row "The confirmation": `Notify` and `TelegramOut` deliver `TelegramIn`'s `Notification`, so the mock receives the `sendMessage`.
- The row "The page pairs within 5 s": the page consumes the real `pairing` event and shows the paired card.
- The row "The guide follows the real pairing": `Guide.Compute` consumes the real pairing, and a `guide.state` event follows.

All of them run against the real production and the mock.

**Consumes:**
- From Story 10.3 (Lane B): `HashCode`, `RecordChat`, `Chat`, `StoreCode`, `Commands.Submit`, `SessionOps.Pair`/`Unpair`, `Notify`'s `pairing` route, `/state`'s Telegram block, the live store's `pairing` handling, `ApiClient.unpair()` and the `pairing.paired` catalog key.
- From Story 12.2: `TelegramIn`'s private-chat handler, `TelegramOut`'s `Notification` path, `LiveCase` and the mock's `/updates`.
- From Story 12.3: the unpaired card, the "Open in Telegram" link (T5 reads the code from it), `TelegramPageFixture`'s `Start` and `Finish`, and T4.
- From Epic 4 (Lane B): `Guide.Compute`'s variant and Telegram row, and `Publish`'s guide refresh.
- From Lane B: `ServerButton`, `Announcer`, `Observe`, `AuditLog`, `RunnerFixture` and `Fixture`.

**Consumed-by:**
- 12.5:
  - the bad-code, bare `/start`, `/help` and other-text replies hang on `TelegramIn`'s pairing path and on its "nothing linked" outcomes;
  - "Telegram unpaired" and the heading focus follow this story's Unpair button;
  - its `/stop` is another command from `HandleUpdate`.
- 12.6: turns and notifications go to the paired chat whose name and pairing this story keeps.
- 12.7: approvals reach the paired chat, and it turns the card on for the release.

**Owned ledger:** DW-486 is addressed by Task 1 and the rows "A stored name survives later messages" and "No name without a pairing" (Decided 2). There are no other entries.

**For the lead:**
- `SessionOps.Unlink` (Lane B) keeps `DisplayName` in a row it unpairs, until that chat writes again. No AC of this epic needs a change. A one-line Lane B ask (clear `DisplayName` on unlink) would close the window, if the lead wants it.
- DW-514 (two tabs) is not built on.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=12 stage=<stage>'`, run from the worktree root.

How to run:
- Run one command per foreground call, with `timeout: 600000`, and never two IRIS test runs in one message.
- Tests never run on a dev slot. An IRIS MCP call, if needed, names `server: ocutalon-slot-c` and `namespace: OCUTALON`, after `iris_server_info`.
- Tear down only `e12s4i` and `e12s4iw`, also after a failure.

**Commands:**
- (loop) `npm --prefix web test`. Expected: every `scripts/*.test.mjs` passes, among them `ux-strings`, `api-client-sources`, `announce-focus-sources` (after its ruling), `page-safety`, `floor-sources` and `shell-styles`.
- (loop) `npm --prefix web run lint`. Expected: clean (`tsc` on the e2e with the `notBuilt` import gone).
- (loop) `<lane> OCUTALON_RUN_TAG=e12s4iw ci/warm.sh up`, before the stage's first `ci/iris.sh build`. A rebuilt bundle changes the warm manifest, so after a build run `down`, then `up`.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e12s4iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Channel.TelegramPair`, `TelegramIn`, `TelegramOut` and `TelegramNoToken`. Expected: `CLASS … passed`, and `TelegramPageFixture` compiles (it appears in the `WARM reloaded` line).
- (loop) `<lane> OCUTALON_RUN_TAG=e12s4iw ci/warm.sh down`.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s4i ci/iris.sh build`, once after each change under `web/src` and before any browser unit.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s4i ci/iris.sh live demo-path`. Expected:
  - every PASS line, and no FAIL line;
  - `STEP 1 page: passed`, with telegram-page's five tests (T1 to T5) passed and no skipped part.

  If the run dies of the unit deadline with no failed test, re-run it with `OCUTALON_LIVE_DEADLINE=900`.
- (once) The fresh-environment check, one call each: `<lane> OCUTALON_RUN_TAG=e12s4i ci/iris.sh shard lane-a@Channel`, then the same with `--reverse`. Expected: every Channel class passes in both orders, `TelegramPair` among them.
- (once) The either-order check for the browser tests:
  1. Reverse the order of the five tests in `telegram-page.spec.ts` (a temporary edit, with your own backup in the stage's scratchpad).
  2. Run `live demo-path` once.
  3. Restore the file and compare it byte for byte with the backup (`cmp`).
- (once) `<lane> OCUTALON_RUN_TAG=e12s4i ci/iris.sh live sign-in --part 1/2`, then `--part 2/2`. Expected: passed (R11's empty `on` card is unchanged).
- (once) One per call: `bash docker/tests/test-ci-config.sh` (`TelegramPair` is in the `Channel` area of `lane-a`), `bash docker/tests/test-boundaries.sh`, then `bash ci/checks.sh`.
- (once) Write the changed and new paths to a file in the stage's scratchpad, and run `bash ci/changes.sh ci.yml --paths-from <file>`. Record the groups.
- (once) `<lane> OCUTALON_RUN_TAG=e12s4i ci/iris.sh teardown`.
- (once) Run `git status --short -- ci web/src/app/api web/src/app/live web/src/app/shared web/src/app/guide web/src/app/chat web/src/app/rail/rail-view.ts web/src/app/rail/status-rail.ts web/src/app/icon web/e2e/support web/e2e/rail web/e2e/api web/package.json web/package-lock.json src/ocutalon/cls/OcuTalon/Web src/ocutalon/cls/OcuTalon/Data src/ocutalon/cls/OcuTalon/Core src/ocutalon/cls/OcuTalon/Demo src/ocutalon/cls/OcuTalon/Live src/ocutalon/cls/OcuTalon/Msg src/bridge README.md`. Expected: it prints nothing. The only Lane B paths changed are the three `web/scripts/` entries.
- Left to CI (Rule 23):
  - `browser` (`demo-path` with T1 to T5);
  - `production` (`shard:lane-a@Channel` with `TelegramPair`);
  - the other groups that `ci/changes.sh` selects.

  Record `iris (browser)`'s and `iris (production)`'s minutes, and `live:demo-path`'s seconds.

**Shared surfaces:**
- **`TelegramIn`'s handling of private updates.** `/start <payload>` now submits `Pair`. A chat's row now holds its name while it is paired, and an unpaired row is cleared of any name it held. Readers:
  - `TelegramIn.TestPrivateOnly` (no name in its fixtures, unpaired: unchanged);
  - `TestRestartLosesNothing` (the scripted "Ci Private" update, unpaired: no name stored);
  - Lane B's `PairingApi`, `PairingRows` and `SessionOpsProduction`, which use their own rows.
- **The Telegram card's states.** The `on` and paired card is no longer empty. Readers: T4's paired case (updated here), R11 (`rail.spec.ts`; `paired` false, unchanged) and T1 to T3 (unpaired, unchanged).
- **The `Pairing` table.** T5 pairs the README session and unpairs it, and `Finish` deletes every row that Start did not find. `TelegramPair` uses its own fixture sessions and the `840177341xx` chats.
- **`TelegramPageFixture.Start` and `Finish`:**
  - `Start` gains `out`, and T1 and T3 call it without;
  - `saved`'s fourth element now lists every `Pairing` row;
  - `Finish` disables both items.
- **The page's speakers** (`announce-focus-sources.test.mjs`) gain the card. **The UX strings inventory** gains four strings. **The demo path's Telegram parts** (`api-client-sources.test.mjs`): the page file has no `notBuilt`.
- **The demo path's step 1:** `partly skipped` becomes `passed` (+1 passed, −1 skipped). `test-demo-path-gate.sh` reads fixtures only.
- **The audit log** gains linked and rejected `Pairing` entries (append-only). **The live streams** of the README session and the fixture sessions gain `pairing` and `guide.state` events (the fixture ones are removed by `DropSessions`).
- **The mock's Bot API state:** the updates are queued per test, and `Finish` / `Cleanup` reset it.
- **Every test added or changed passes on a fresh environment, in either order.**

**Pinning mutations to apply (Rule 19).**
- Each is applied, seen red, and reverted byte for byte (`cmp` against your own backup; `git status --short` and `git diff --stat` unchanged). It is then recorded here as `mutation: … -> …`.
- A mutation of Lane B code is temporary.
- A web mutation is followed by `ci/iris.sh build`.
- No mutation points a call at the public API.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC1, the hash | `TelegramIn` puts the payload itself in `CodeHash` | `TelegramPair.TestPairs` (the `Pair` body's hash; nothing linked; the bodies hold the code) |
| AC1, the `ChatRef` | `ChatRef` = the chat id | `TestPairs` (unknown_chat, nothing linked; the bodies hold the chat id) |
| AC1, the origin | `Submit` with origin `system` | `TestPairs` (refused, nothing linked) |
| AC1/AC3, the name in the row | `RecordChat(chat.id, "")` for the pairing update (today's code) | `TestPairs` (the event's `displayName`); T5 ("Telegram paired · Dana") |
| AC3, the name not in the trace | `TelegramIn` adds the name to the `Notification`'s `Slots` | `TestPairs` (a body holds "Zqdana") |
| AC2, the reply | No `Notification` on `paired` | `TestPairs` (no `sendMessage`); T5 (`Replies`) |
| AC2, routed by `ChatRef` | The `Notification` has no `ChatRef` | `TestPairs` (no `sendMessage`: `Notify` drops it) |
| AC3, the paired view | `telegramCardView` ignores `paired` (shows nothing) | T5 and T4 (no `data-state="paired"`) |
| AC3, the accessible name | The button has no `label` | T5 and T4 (not named "Unpair Telegram") |
| AC3, the announcement | No announcement | T5 ("Telegram paired" not announced) |
| AC3, the first value | The announcement is made for the first value too | T5 (the reload announces) |
| AC3, within 5 s | The card shows the paired view 6 s after the change (a temporary `setTimeout`) | T5 (`shownAt − queuedAt` over 5000) |
| AC4 | `Live/Publish.cls` `GUIDETRIGGERS` without `pairing` (temporary, Lane B) | `TestPairs` (no `guide.state` with `paired`) |
| AC5, the code from the link | The card's link carries a fixed code | T5 (nothing pairs) |
| DW-486 | `HandleUpdate` passes the update's name even when empty | `TestNameOnlyWhilePaired` (row (a) blanks "Zqdana") |
| DW-486, AD-4 | A pairing update's name stays after an outcome that is not `paired` | `TestNameOnlyWhilePaired` (row (b) keeps "Zqstranger") |
| Unpair | The button's action is a no-op (`of(null)`) | T5 (no `DELETE`; the card stays paired) |

Observed (implement stage; each applied, seen red, reverted and compared with `cmp` against a backup; IRIS mutations ran on a warm stack, web mutations each with `ci/iris.sh build` and a full `live demo-path`):
- mutation: `TelegramIn` puts the payload in `CodeHash` -> `TestPairs` red (no link, no used mark, no Pair body hash match, the bodies hold the code) and `TestNameOnlyWhilePaired` red.
- mutation: `ChatRef` = the chat id -> `TestPairs` red (nothing linked; "a message body holds the chat id").
- mutation: `Submit` with origin `system` -> `TestPairs` red (no Pair body, nothing linked).
- mutation: the pairing update records the chat with `""` -> `TestPairs` red (the row, the event and `/state` hold no name); `TestNameOnlyWhilePaired` (a) red.
- mutation: the name goes into the `Notification`'s `Slots` -> `TestPairs` red (slots not `{}`; a body holds the name).
- mutation: no `Notification` on `paired` -> `TestPairs` red (no `sendMessage`, no Notification body).
- mutation: the `Notification` has no `ChatRef` -> `TestPairs` red (no `sendMessage`).
- mutation: `Live/Publish.cls` `GUIDETRIGGERS` without `pairing` (temporary, restored) -> `TestPairs` red (no `guide.state` after the pairing or the unpair).
- mutation: `HandleUpdate` passes the update's name even when empty for a paired chat -> `TestNameOnlyWhilePaired` (a) red.
- mutation: the second `RecordChat` with `""` after an outcome other than `paired` is removed -> `TestNameOnlyWhilePaired` (b) red ("nothing is linked and the row holds no name").
- mutation: `telegramCardView` ignores `paired` -> T4 and T5 red (no `data-state="paired"`).
- mutation: the Unpair button has no `label` -> T4 and T5 red (not named "Unpair Telegram").
- mutation: no announcement -> T5 red ("Telegram paired" is announced).
- mutation: the announcement is made for the first value too -> T5 red (the reload announces).
- mutation: the paired view shows 6 s after the change (a `setTimeout`) -> T4 and T5 red (`shownAt - queuedAt` over 5000).
- mutation: the card's link carries a fixed code -> T1, T3 and T5 red (nothing pairs).
- mutation: the Unpair action is a resolved promise -> T5 red (no `DELETE`).
- mutation: `Payload` returns the raw remainder, with no `$ZStrip(..., "<>W")` -> `TestNoPairWithoutACode` red ("no Pair body was sent": a "/start    " with white space only submits a Pair).
- mutation: `HandleUpdate` without the `chat.type '= "private"` check -> `TestNoPairWithoutACode` red (the group chat pairs: "no Pair body was sent", "the code row is not marked used", "the group chat has no row").
- mutation: `HandleUpdate` always keeps `storedName` for a non-pairing update of a paired chat -> `TestNameOnlyWhilePaired` (b) red ("the new name replaces it, and the session stays") and (c) red too ("a pairing update with no name keeps the paired chat's name and session").
- mutation: `HandleUpdate` takes the old branch, so a pairing update uses `updateName` even when empty -> `TestNameOnlyWhilePaired` (c) red ("a pairing update with no name keeps the paired chat's name and session").
- mutation: `Pair` calls `Reply(ref)` twice on `paired` -> `TestPairs` red ("the chat gets exactly one message" and "TelegramIn sent exactly one Notification to Notify").
- mutation: `TelegramPageFixture.DropRows` skips every delete but keeps its read-back (the rows are left behind) -> T1 and T5 red, both with "the fixture puts everything back" (received "a Pairing row that Start did not find is still there"); T3 and T4 stay green. Disabling the whole `DropRows` call instead would remove the read-back too, so `Finish` would return "" and nothing would be seen: the read-back is what pins the clean-up.
- mutation: the paired line always uses the "Telegram paired {middle dot} {name}" form, even for an empty name -> T4 red ("paired, no name: the card says so": expected "Telegram paired Unpair", received "Telegram paired \u00b7 Unpair").
- mutation: the announcement effect calls `announce` twice in the same turn -> not red: `Announcer` joins the messages of one turn into one text, and T5 counts texts, so it still sees one. The same effect calling `announce` a second time 1.5 s later (a `setTimeout`) -> T5 red ("Telegram paired" is announced once, and not again: expected 1, received 2).
- mutation: the `state === 'on' && telegram.paired` branch moved above the `off`/`rejected` branch -> not red: the branch is gated on `state === 'on'`, so for `off` and `rejected` the order cannot change the view. Only that move together with dropping the `state === 'on'` gate from the paired branch -> T4 red ("paired, state off: the card is not-set-up": expected 1, received 0). The gate alone, with the order kept, is not red either (the not-set-up branch returns first).
- mutation: `Demo/Guide.cls` (Lane B, temporary, restored) `TelegramRow` always 1 -> T5 red ("the guide has no Telegram line": the Demo guide region still holds "Optional: scan the QR code" while paired).

QA stage (audit of every AC and matrix row against the existing tests; no test file created or changed, because every AC and row was pinned). Two assertions that the implement stage had not seen red were mutated (each applied, seen red, restored, `cmp` against a backup, `git status --short` and `git diff --stat` unchanged):
- (QA) mutation: `TelegramIn.Pair` writes `$$$LOGINFO("paired chat "_chatId)` on `paired` (AC1/AC3, the event-log scan of "Nothing leaks into the trace") -> `TestPairs` red ("the event log holds the chat id").
- (QA) mutation: `.paired-icon` loses `color: var(--telegram-card-paired-icon)` (AC3, the icon's token colour) -> T5 red (`toHaveCSS` on the icon; `STEP 1 page: failed, 10 passed, 1 failed`).
- (QA) `live sign-in --part 1/2` on a fresh throwaway (tag `e12s4qa`): passed, 127 passed in 3.7 min.

Measured: `TelegramPair` 16.2 to 16.6 s (warm, and in `shard lane-a@Channel` in both orders); the whole shard 352 s forward and 372 s reversed on a fresh throwaway; T5 8.0 s locally (T1 24.6 s, T2 0.6 s, T3 31.3 s, T4 14.4 s); `live demo-path` 4 min 56 s locally (first start 113 s ready); `STEP 1 page: passed, 11 passed, 0 skipped`. The either-order run (T5, T4, T3, T1, T2) passed. `live sign-in` parts 1/2 and 2/2 passed. `ci/changes.sh` with no push event runs every group (it reads GitHub for a base, so the real selection is CI's).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.**
- `TelegramIn` turns `/start <code>` from a private chat into `Pair {HashCode(code), ChatRef}` through `Commands.Submit` with origin `telegram`, and sends the `pairing.paired` `Notification` to `Notify` on the outcome `paired` only. A chat's name (`chat.first_name`) is kept only while the chat is paired (DW-486).
- The Telegram card has its paired view (`circle-check`, "Telegram paired \u00b7 {name}", a one-press ghost "Unpair" button named "Unpair Telegram" through `ApiClient.unpair()`) and announces "Telegram paired" once.
- The tests: `Test.Channel.TelegramPair` (new, in `shard:lane-a@Channel`), T5 in place of the `notBuilt` line, and T4's paired and precedence cases. `TelegramPageFixture` gains `out`, the removal of rows that `Start` did not find, `Now`, `Pair` and `Replies`; `LiveCase` gains public `PrivateMessage` (extended), `TextsTo` and `PairBodies`.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls`: the pairing path, the name rule, the reply.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPair.cls` (new): `TestPairs`, `TestNameOnlyWhilePaired`, `TestNoPairWithoutACode`.
- `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls`, `TelegramPageFixture.cls`: the helpers above.
- `web/src/app/rail/telegram-card/telegram-card-view.ts`, `telegram-card.ts`: the paired view, the Unpair button, the announcement.
- `web/e2e/demo-path/telegram-page.spec.ts`: T5, T4's paired and precedence cases, no `notBuilt`.
- `web/scripts/ux-strings.test.mjs` (four strings), `api-client-sources.test.mjs` (the page-file row), `announce-focus-sources.test.mjs` (the card joins the speakers): by entry, under the rulings.

**Review.** 35 findings from four layers: 9 patched (1 medium, 8 low), 1 deferred (the `Unlink` name, low, in the frontmatter), 21 rejected as low and 4 as false, each with its reason in the Review Triage Log. Follow-up review recommended: false (one medium patched, no high).

**Verification (final tree).**
- `npm --prefix web test` 1127 passed; `npm --prefix web run lint` clean.
- Warm: `TelegramPair`, `TelegramIn`, `TelegramOut`, `TelegramNoToken` passed.
- Fresh `shard lane-a@Channel`: 9 of 9 classes passed forward and with `--reverse`.
- `live demo-path`: passed, `STEP 1 page: passed, 11 passed, 0 skipped`, 17 Playwright tests in 2.3 min; also passed with the three describe blocks of `telegram-page.spec.ts` in reverse order (file restored, compared with a backup).
- `live sign-in` part 1/2 failed once (1 failed, 126 passed; the failing test was not captured) and passed on the re-run (127 passed); part 2/2 passed (96). No test of this story is in those parts.
- `test-ci-config.sh`, `test-boundaries.sh`, `ci/checks.sh` passed. `ci/changes.sh` with no push event selects every group.
- The footprint `git status` printed nothing: no Lane B path changed beyond the three `web/scripts/` entries.
- 27 mutations demonstrated red and restored byte for byte (Verification, "Observed"). Two came out not red as first stated (a double `announce` in one turn is joined into one text; a branch move that the `state === 'on'` gate neutralises) and were replaced by variants that are red.

**Measured durations (for the budget).** `TelegramPair` 17.4 s on a fresh throwaway (16.3 s warm); T5 13.2 s, T4 22.7 s locally; the Channel shard 352 s forward and 372 s reversed locally; `live demo-path` 2.3 min of Playwright locally. CI group times are not known here: `browser` and `production` are left to CI (Rule 23).

**Footprint extensions to report:** `web/scripts/ux-strings.test.mjs`, `web/scripts/api-client-sources.test.mjs` (standing ruling, by entry) and `web/scripts/announce-focus-sources.test.mjs` (the runner's ruling, two entries).

**For the lead:** the optional Lane B ask on `SessionOps.Unlink` keeping `DisplayName` (deferred, low).

**Residual risks.**
- T5's 5 s bound is the most likely to flake on a slow runner (inference).
- The unexplained single failure in `live sign-in` part 1/2.
