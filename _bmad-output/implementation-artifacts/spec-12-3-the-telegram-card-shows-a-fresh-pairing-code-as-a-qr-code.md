---
title: 'Story 12.3: The Telegram card shows a fresh pairing code as a QR code'
type: 'feature'
created: '2026-10-31'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-1, AD-4, AD-12, AD-13, AD-14, AD-17, AD-19, AD-22, AD-29, AD-32 and AD-33, and the Stack row "QR-code library")'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 10.3 built the session side of pairing (`POST /api/v1/pairing/code`, the typed client method `ApiClient.pairingCode()`, hash-only storage) and pinned `qrcode-generator` 2.0.4 in `web/`, and Story 12.2's `TelegramIn` records `on` with the bot's user name from `getMe`. But the Telegram card shows nothing while Telegram is on: no code is ever asked for, no QR code is drawn, nothing refreshes a code when it runs out, and no test searches the server's stores for a code the page was given.

**Approach:**
- The card gets its unpaired state, below 12.8's paused state:
  - the QR code of `https://t.me/<bot>?start=<code>`;
  - "Scan with your phone's camera, then tap Start in Telegram.";
  - an "Open in Telegram" link named with "(opens Telegram)";
  - "New code in {n} min".
- The card asks for the code itself, through `ApiClient.pairingCode()`, and asks again when the code runs out. The new code goes into the same link and QR elements, so focus and typed input stay where they were.
- A 409 answer shows the off state, and a pause shows the paused state. Neither shows a code.
- The browser tests in `telegram-page.spec.ts` drive the real chain: the real `TelegramIn` against the CI mock (with a queued `getMe` name), the real code route, and the page. A new IRIS step of `TelegramPageFixture` checks the server side of the codes and searches the production's stores for them.

## Boundaries & Constraints

**Always:**
- **When the card asks for a code.** It asks only while all of these hold:
  - the snapshot's Telegram block (the store's `telegram`) says `state` `on`, with a non-empty `botUserName`;
  - `paired` is false;
  - the card is not paused (12.8's reading of the store's `telegramPaused`).

  `included` is the rail's: the card exists only when it is true.
- **Order of the states:** paused (12.8), then not set up (`off` or `rejected`, or a refused code, below), then nothing, then unpaired. "Nothing" means `on` with no bot name, `paired` true (Story 12.4 adds the paired state), or no code yet.
- **The unpaired view** holds exactly these, in this order:
  - the QR block: 132 px square, with the `--qr-code-block-*` tokens (background `#FFFFFF`, dark modules `#102A45`, a 12 px quiet zone as padding, a 6 px radius), navy on white in both themes;
  - the scan line;
  - a foot with the link and, in caption type, "New code in {n} min".

  The view's root carries `data-state="unpaired"`.
- **The QR symbol.**
  - It is drawn in the browser by `qrcode-generator` with the calls `qr-pin.test.mjs` uses: `qrcode(0, 'M')`, `addData(link)` and `make()`. The library's own `createSvgTag`, `createImgTag` and `createDataURL` draw black and are not used.
  - The card builds its own inline `<svg>`, with `role="img"` and the accessible name "QR code that opens OcuTalon in Telegram to pair this session". Its `viewBox` is `0 0 N N`, where N is `getModuleCount()`. It holds one dark `<path>`, whose `d` is `M{col} {row}h1v1h-1z` for each dark module, row by row (`isDark(row, col)`).
  - It is bound through the template: no `innerHTML`, no sanitizer bypass (`page-safety.test.mjs`).
  - It has no `height` attribute and no CSS `height` (`floor-sources.test.mjs` allows no fixed height here): the width and the `viewBox` set the size.
- **The link.**
  - The `href` is `https://t.me/<botUserName>?start=<code>`.
  - It has `target="_blank"` and `rel="noopener noreferrer"`, and is underlined like every link.
  - Its visible text is "Open in Telegram", and a visually hidden " (opens Telegram)" follows it, so its accessible name is "Open in Telegram (opens Telegram)".
- **The code's lifetime on the page.**
  - When an answer `{code, expiresAt}` arrives at browser time `receivedAt`, its due time is `min(Date.parse(expiresAt), receivedAt + 600000)`. 600 s is FR-18's ten minutes, so neither a browser clock behind the server's nor a timer longer than the browser's maximum keeps a code longer.
  - **The countdown:** `{n}` = `max(1, floor((due - now) / 60000))`. A fresh ten-minute code reads "New code in 9 min", and the last minutes read "New code in 1 min". The text is never more than 1 s stale.
  - **The refresh:** at the due time, the card asks for a new code.
  - **The spacing:** two code requests are always at least 10 s apart. A browser clock ahead of the server's makes every code look expired, and it then gets one request every 10 s, never a loop.
  - The old code stays on screen until the new one arrives, or until the request fails. A new code replaces the old one in the same `<a>` and `<svg>` elements (bindings change, the elements stay), so a focused link keeps focus.
- **Answers that give no code.**
  - **409** (`not_available`): the card shows the not-set-up view and asks no more. The refusal is forgotten when a value of the store's Telegram block (`state`, `botUserName`, `paired`) or the pause changes. A reloaded snapshot with the same values keeps it. The paused state still wins.
  - **Any other failure:** the card shows nothing and asks again 30 s later.
  - Leaving the unpaired condition (paused, paired, not on) drops the code and its timers. Coming back asks for a fresh code.
- **Focus and announcements.** The card calls no `.focus(`, no `keepFocus` and no `afterNextRender`, and it announces nothing (`announce-focus-sources.test.mjs`). The refresh moves focus nowhere: a focused link stays focused with its new code, and focus anywhere else stays where it is.
- **The code** lives only in the card's memory and in the link and QR it renders. It is never written to the console, browser storage, the URL, a title or the announcer. The page sends it nowhere; the server sent it.
- **Texts.** The five new texts are EXPERIENCE.md's, verbatim:
  - "Scan with your phone's camera, then tap Start in Telegram." (line 355);
  - "Open in Telegram" (line 355);
  - "(opens Telegram)" (line 219);
  - "New code in {n} min" (line 355, and UX-DR56);
  - "QR code that opens OcuTalon in Telegram to pair this session" (line 445).

  They join `TELEGRAM_CARD_TEXTS` and are bound by interpolation, so the template holds no literal text (AD-13; Rule 14 ASCII).
- **The browser tests.** They run on fresh throwaways and in CI only, against the CI mock and its dummy token.
  - Telegram is turned on only through the seam (`setTelegramIncluded(1)`), and the seam is restored in `finally`.
  - Every test that calls `TelegramPageFixture.Start` calls `Finish` in `finally`.
  - Every IRIS script prints its `CHK|` lines on every path.

**Never:**
- No change to:
  - `Included()`, `Web/Api.cls`, `Data/Pairing.cls` or any other Lane B class;
  - `api/api-client.ts`, `api-types.ts`, `live/*`, `rail-view.ts`, `status-rail.ts` or `chat/page-time.ts`;
  - `web/e2e/support/**`, `rail.spec.ts` or `api/pairing.spec.ts`;
  - `ci/units.sh`, `ci/mock/**`, `Test/Contract/Mock.cls`, `README.md`, `web/package.json` or the lockfile;
  - any contended file of the dispatch.
- No Lane B `web/` edit beyond the one `ux-strings.test.mjs` entry under Design Notes, "Footprint". In particular, no entry in:
  - `announce-focus-sources.test.mjs` (the card has no focus call);
  - `floor-sources.test.mjs` (no fixed height);
  - `api-client-sources.test.mjs` (its Telegram-parts row still holds: the file has tests of its own and one `notBuilt` owned by 12.4);
  - `icon.ts` (the unpaired view has no icon).
- No new third-party dependency. `qrcode-generator` 2.0.4 is vendored, with its Stack row.
- No new spec file in `web/e2e/demo-path/` (`demo-path-summary.mjs`), and no change to the `notBuilt(…, '12.4')` line.
- No real bot, no call to `api.telegram.org`, no real token. No 10-minute wait: the test stands in for elapsed time by changing the answer's `expiresAt` on its way to the page (as 12.8 moved the mark).
- No pairing, paired state, Unpair or "just unpaired" state (Stories 12.4 and 12.5).

## I/O & Edge-Case Matrix

These rows assume:
- "T3" is the new real-chain test.
  - It turns the seam on, then calls `Start(.saved, "ocutalon_qr_bot")`, which queues a `getMe` answer naming `ocutalon_qr_bot`, then starts `TelegramIn` and waits for `on`.
  - It takes `CodeMark()`, then signs the README account in (`ocutalon`).
  - Before the sign-in it routes `**/ocutalon/api/v1/pairing/code`. The handler keeps every real answer (status, body, the test's time) and changes `expiresAt` in the first answer only (to 10 s after it) and in the second only (to 60 s before it). Every later answer passes through as the server sent it.
- `S(link)` is the `d` that `qrcode-generator` gives for that link, with the grammar above.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| A fresh code (Integration: `TelegramIn`'s `getMe` → `/state` → the card; the card → the code route) | T3, signed in | Exactly one `POST` to `/ocutalon/api/v1/pairing/code`, with the body `{}` and `X-OcuTalon-Request: 1`. Its real answer is 200 `{code, expiresAt}`: a 22-character code of `[A-Za-z0-9_-]`, and an `expiresAt` 600 s (± 2 s) after the answer. The card's `data-state` is `unpaired`, and its text holds, in order, the scan line, "Open in Telegram" and "New code in 1 min". One link, named "Open in Telegram (opens Telegram)", with `href` `https://t.me/ocutalon_qr_bot?start=<code 1>`, `target` `_blank`, `rel` `noopener noreferrer`, underlined. One element of role `img` with the alt text, whose `svg` has the path `S(href)`. The block is 132 × 132 px, its background `rgb(255, 255, 255)` and the path's fill `rgb(16, 42, 69)`, and the same with `colorScheme: 'dark'`. | — |
| The code runs out while the user types (AC3) | A draft typed in the composer ("Message OcuTalon"), which keeps focus; answer 1 due 10 s after it | The second `POST` comes 9 to 16 s after answer 1. The link's `href` and the path then carry code 2 (not code 1), and there is still one link and one QR. The composer still has focus and the draft. The card reads "New code in 1 min" (answer 2's changed expiry is in the past). | — |
| A past expiry, with focus on the link (AC3, the spacing) | The test focuses the link; answer 2 is already past | No third `POST` until 9 s after answer 2, then exactly one before 16 s. The `href` and the path carry code 3, and the focused element is the card's link with code 3. The draft is unchanged. Answer 3 is unchanged, so the card reads "New code in {n} min" with `n` = `max(1, floor((Date.parse(expiresAt 3) - page now) / 60000))`, which is 9. Three `POST`s in all. | — |
| The server side of the codes (AC1) | After code 3, `Codes(mark, "ocutalon", "<code 1>,<code 2>,<code 3>", <expiresAt 3>)` | Returns "": the README session has one code row, which holds `HashCode(code 3)` with `CodeExpiresAt` = `expiresAt 3` and an empty `CodeUsedAt`. The hashes of codes 1 and 2 find no row, and no column of any `Pairing` row holds any of the three codes. | A reason names the first failed check. |
| No code anywhere else (AC4) | The same `Codes` call | None of the codes is in: a message header or a message body since the mark, an event-log row since the mark, the event log as a whole, the settings, item settings or sessions (`KeyScan.Find`), a live event since the mark, or an audit entry since the mark. Each scan's positive control is found (Design Notes, Decided 10). | A reason names the store. |
| Refused while the server is off (AC1, And) | The seam on, no `TelegramIn` (the server's state is `off`), and a changed `/state`: `included` true, `state` `on`, `botUserName` `ocutalon_ci_bot`, `paired` false, no pause | One `POST`, answered 409. The card is `data-state="not-set-up"`: "Telegram not set up" with its link, no QR, no "Open in Telegram". No second `POST` within 3 s. | — |
| Paired | The same changed `/state` with `paired` true and `displayName` "Zz" | No `POST` within 3 s, no QR and no link (Story 12.4 adds the paired state). | — |
| Paused (AC1, And; T1, 12.8's test, extended) | T1's real 409 pause, with its reload | One `POST` before the onset. None from the page applying the onset to it applying the clear, the reload included. The card is paused as 12.8 asserts (one `svg`, the icon; no `a`, `img` or `canvas`). After the clear, a new `POST`, and the card shows a QR and the link with `ocutalon_ci_bot`. | — |
| On with no bot name (R11, Lane B's, unchanged) | A changed `/state` with `state` `on` and `botUserName` "" | The card shows nothing and asks for no code. | — |

</intent-contract>

## Code Map

**Lane A's card and spec (edit freely)**
- `web/src/app/rail/telegram-card/telegram-card.ts:1-90`: the card.
  - The template (:26-40) has the paused and not-set-up blocks; the styles are at :41-77.
  - It has `inject(LiveState)` and `view` (:89).
  - Its `telegram` input comes from `status-rail.ts:94`, `:249` (the store's `telegram`, falling back to `TELEGRAM_OFF`).
- `web/src/app/rail/telegram-card/telegram-card-view.ts:1-55`: `TELEGRAM_CARD_TEXTS` (:19), `holds` (:40) and `telegramCardView` (:45). The `kind` union is at :35.
- `web/e2e/demo-path/telegram-page.spec.ts`:
  - the describe (:25) with its helpers (:28-102, :144-181), which are scoped inside the describe;
  - T2 (:108-142) and T1 (:188-267);
  - `fixture()` (:151), `appliedInstance` (:166), and the `notBuilt` line (:270), which stays.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls`:
  - `Start` :38-65 (Reset at :51, then Enable at :56);
  - `Finish` :108-130;
  - `Pack` :139-142 (`$ListBuild(rows, marks, since)`) and `Safe` :145.
- `Test/Channel/LiveCase.cls`:
  - `HeaderMark` :249 and `HeadersFrom` :257, both private class methods;
  - the class doc (:3-21) lists its public helpers.
- `Test/Channel/TelegramNoToken.cls`:
  - its private class methods `RowsText` :24-35, `Bodies` :38-60 and `LiveMark` :194-200;
  - its scans and controls :150-185, the pattern for `Codes`.

**Called, never edited (Lane B, Lane A's bridge, and the platform)**
- The page:
  - `api/api-client.ts:100-106`: `pairingCode()`, a POST of `{}`, where a 409 fails as an `HttpErrorResponse`;
  - `api/api-types.ts:27-34` (`TelegramState`) and `:110-114` (`PairingCode {code, expiresAt}`).
- `live/live-store.ts:181-183`: `telegram` changes only on a snapshot and on `pairing` events (`paired`, `displayName`), so `state` and `botUserName` are never live.
- `chat/page-time.ts`:
  - `countdownText` :249-270 (seconds rounded up, minutes rounded down);
  - `countdownSpokenMinutes` :277-284 ("in 1 minute" through the last minute).

  The card's `{n}` follows these rules; see Design Notes, Rule 2.
- `chat/chat-view.ts`: `CHAT_TEXTS.opensInNewTab` and the not-set-up link's pattern (`telegram-card.ts:35-37`).
- `styles/tokens.css:286-290`: `--qr-code-block-background`, `-foreground`, `-size`, `-quiet-zone` and `-radius`, in the light block only. `tokens.test.mjs:141-146` pins that dark redefines none of them.
- `web/node_modules/qrcode-generator/dist/qrcode.d.ts` (`getModuleCount`, `isDark`).
  - `qrcode.mjs` ends with `export default qrcode`, and `qrcode.js` sets `module.exports`.
  - `tsconfig.json` has `module: preserve`, so `import qrcode from 'qrcode-generator'` type-checks in `web/src` and in `web/e2e`.
- `web/scripts/qr-pin.test.mjs:55-66`: the library's calls. Its header says nothing in `web/src` imports the library yet; Decided 15 covers that.
- The source pins the card must keep green (Lane B, read only):
  - `page-safety.test.mjs` (no `innerHTML` or sanitizer, comments included);
  - `announce-focus-sources.test.mjs:118-166` (the files that may move focus);
  - `floor-sources.test.mjs:215-254` (no `height:` or `block-size:` and no bound height);
  - `shell-styles.test.mjs` (every `var(--…)` exists).
- The server:
  - `Web/Api.cls:673-700`: `Pairing` gives 404 when the release does not include Telegram, and `PairingCode` gives 409 `not_available` when the state is not `on` (`MESSAGETELEGRAMOFF` :116) or a pause is set (`:119`); otherwise `NewRef`, `StoreCode`(`HashCode`) and 200;
  - `Web/Api.cls:765-774`: the Telegram block of `StateBody`.
- `Data/Pairing.cls`: `HashCode` :68, `StoreCode` :155 (replaces the session's one code row), `ForCode` :205, and the unique `CodeSessionRefIndex` :62.
- `Data/StatusMark.cls:56` `RecordTelegram` (a name of `[A-Za-z0-9_]{0,64}`). `Channel/Telegram/In.cls:142-156` records `getMe`'s `username`.
  - `Install/Step/Telegram.cls:67` records `off` with `""`, so every start without `TelegramIn` has an empty name; R11's `on` row depends on it.
- `Data/Session.cls:72` `ForUser(user, .sc)`.
- The test helpers:
  - `Test/Agent/KeyScan.cls:174` `Find(value)`, and its own event-log probe at `:140-163` (`Ens.Util.Log.LogInfo`, deleted with `DELETE FROM Ens_Util.Log WHERE Text [ ?`);
  - `Test/Agent/RunnerFixture.cls:182` `EventMark` and `:190` `LogRowsHolding`;
  - `Test/Bridge/AuditLog.cls:23` `Now`, `:30` `Entries` and `:61` `Wait`; `src/bridge/cls/OcuTalon/Bridge/Audit.cls:78` `Record` (call only; `src/bridge/**` is contended);
  - `Test/Data/Fixture.cls:19` `Session`, `:271` `Adopt`, `:331` `Clean` (which drops a recorded session's stream) and `:365` `RemoveMessages`;
  - `Core/Commands.cls:18` `Submit`, with `Msg.Command.Unpair` for a session that is not paired. Lane B's `Test/Web/PairingApi.cls` (`TestPageUnpairNothingPaired`) shows it answers `not_paired` and audits, publishes and sends nothing;
  - `Live/Publish.cls:62` `Publish(stream, type, payload)`. `status` is not a guide trigger (`:21`). `Live/Payload/Status.cls:20` has `Condition` (MAXLEN 32).
- `Test/Web/PairingApi.cls:390-404`: `CodeRows` and `ColumnsHold`, Lane B's private methods, whose SQL `Codes` copies (Design Notes, Rule 2).
- `Test/Contract/Mock.cls`: `TELEGRAMBASE` :53, `Control` :417 (`{"method": "getMe", "replies": [...]}`, as `TelegramNoToken` queues `sendMessage` replies). The default `getMe` answer is at `ci/mock/mock.mjs:197`; a queued reply answers first.
- The e2e support:
  - `support/api.ts:27-34` `changeSnapshot`, and `STATE`;
  - `support/floor.ts:47` `inMs`, `:51` `composerOf`, `:150` `signInReadmeLoaded`;
  - `support/iris.ts` `irisScript`, `chk`, `quoted`, `setTelegramIncluded`;
  - `support/page.ts` `plain`, `tokenColor`;
  - `sign-in/helpers.ts:6` `README_ACCOUNT`.
- `web/e2e/rail/rail.spec.ts:463-497`: R11 changes only `state` to `on`, so `botUserName` stays `""`. It expects the `on` card to be empty, and must stay green.
- The runner:
  - `web/playwright.config.ts` (one worker, a 45 s test timeout);
  - `docker/tests/test-demo-path.sh` (540 s deadline locally);
  - `web/scripts/demo-path-summary.mjs` (`telegram-<step>`), whose `demo-path-summary.test.mjs` leaves `@floor` tests out of its no-stack run.

## Tasks & Acceptance

**Execution:**
1. `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls`: a behaviour-preserving move (Rule 2).
   - `HeaderMark` and `HeadersFrom` lose `[ Private ]`.
   - `RowsText(sql, mark)`, `Bodies(mark)` and `LiveMark()` move here from `TelegramNoToken` as public class methods, with the same bodies.
   - The class doc lists them and names `TelegramPageFixture`'s code search as their second user.
2. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramNoToken.cls`: delete the three moved methods; its calls (`..RowsText`, `..Bodies`, `..LiveMark`) resolve to the inherited class methods. The class doc stays true.
3. `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls`:
   - **`Start(Output saved, botName As %String = "")`.**
     - After `BotApi.Reset` and before `Enable`, when `botName` is not empty, it queues one `getMe` reply through `Mock.Control("replies", {"method": "getMe", "replies": [{"status": 200, "body": {"ok": true, "result": {"id": 424243, "is_bot": true, "first_name": "OcuTalon QR", "username": (botName)}}}]})`. A refusal is a reason, and nothing is enabled.
     - `saved` gains a fourth element: the `Ref`s of every code row (`CodeSessionRef` not empty) at Start.
   - **`Finish(saved)`.** Besides what it does now, it deletes every code row whose `Ref` was not in that list (the rows the page made during the test), after `TelegramIn` is disabled. A failure is the first reason. A `saved` with three elements (no list) deletes nothing.
   - **`CodeMark() As %String`:** base64 (no line breaks) of the UTF-8 of `$ListBuild(LiveCase.HeaderMark(), AuditLog.Now(), LiveCase.LiveMark(), RunnerFixture.EventMark())`.
   - **`Codes(mark, user, codes, expiresAt) As %String`.** `codes` is comma-separated, in issue order; `expiresAt` is the last answer's, as the server sent it. It returns "" or the first failed check, with no token in it (`Safe`). The checks are in two parts.
     - **The row:**
       - `ForCode(HashCode(<last>))` is a row with `CodeSessionRef` = `Session.ForUser(user).Ref`, `CodeExpiresAt` = `expiresAt`, and an empty `CodeUsedAt`, `ChatId` and `SessionRef`;
       - the session has exactly one code row;
       - every earlier code's hash finds no row;
       - no column of any `Pairing` row holds any code.
     - **The search, with the probes it writes first** (Decided 10):
       - `KeyScan.Find(code)` is empty for each code, and `KeyScan.Find(Mock.#TELEGRAMBASE)` is not;
       - `RowsText("SELECT * FROM Ens.MessageHeader WHERE ID > ?", h)` and `Bodies(h)` hold no code. The header text holds `SessionOps`, and the body text holds the probe session's `Ref`;
       - `LogRowsHolding(e, code)` is 0 for each code, and 1 for the probe's text;
       - `RowsText("SELECT Payload FROM OcuTalon_Live.Event WHERE %ID > ?", l)` holds no code, and holds the probe's condition;
       - `AuditLog.Entries(a).%ToJSON()` holds no code, and `AuditLog.Wait(a, "OcuTalon", "Pairing", "Pairing", reason, "", 1, 20)` finds the probe entry.

       Then the probes are removed: the probe session with its stream (`Fixture.Clean`), its messages (`Fixture.RemoveMessages` with its `TraceRef`), and the event-log row. The audit entry stays, since the audit log is append-only (12.2's precedent).
   - The class doc covers the new methods and the parameter.
4. `web/src/app/rail/telegram-card/telegram-card-view.ts`:
   - **The texts.** `TELEGRAM_CARD_TEXTS` gains `scan`, `open`, `opensTelegram`, `newCodeIn` (`'New code in {n} min'`) and `qrAlt`, with the exact strings under Boundaries.
   - **The view** gains the kind `unpaired`, with the order and inputs above:
     - the Telegram block;
     - the store's status;
     - the held code (or none);
     - whether the last answer was a 409;
     - the time.

     The view stays one flat shape (12.8's Decided 13).
   - **Pure helpers** (no Angular):
     - the link `https://t.me/<bot>?start=<code>`;
     - the due time `min(Date.parse(expiresAt), receivedAt + 600000)`;
     - `{n}` = `max(1, floor((due - now) / 60000))`;
     - the symbol of a link (`{size, path}` from `qrcode(0, 'M')`, `getModuleCount` and `isDark`), here or in a sibling `telegram-qr.ts` in the card folder.
   - The module stays importable by Node: type-only imports, plus `qrcode-generator`'s ESM default. The doc states the contract.
5. `web/src/app/rail/telegram-card/telegram-card.ts`:
   - **What it injects:** `ApiClient`, beside `LiveState`.
   - **The unpaired block:**
     - the `.qr` block (tokens, `forced-color-adjust: none`), holding the `<svg role="img">` with `[attr.aria-label]`, `[attr.viewBox]` and the one path, filled with `var(--qr-code-block-foreground)`;
     - the scan line;
     - the foot: the `.link` with its visually hidden suffix, and the caption.
   - **The code's lifecycle,** in signals and effects with `onCleanup` for every timer and subscription:
     - asking when the condition starts to hold;
     - the refresh at the due time, never sooner than 10 s after the previous request;
     - the 1 s tick of `{n}` while the view is unpaired;
     - the 409 and other-failure rules;
     - dropping the code when the condition ends.
   - **The rules it keeps:** no `.focus(`, `keepFocus`, `afterNextRender`, `height` or `transition`. The new code reaches the same elements.
   - The not-set-up and paused blocks are unchanged, apart from the not-set-up block now also showing after a 409.
   - The class doc gains the unpaired state.
6. `web/scripts/ux-strings.test.mjs` (the one Lane B entry): `SOURCES.ux` gains the five strings, beside 12.8's two (:223-224). The `IMPORTED` row already exists (:45).
7. `web/e2e/demo-path/telegram-page.spec.ts`:
   - **Structure.**
     - The header names Story 12.3's tests, beside 12.8's.
     - The shared helpers move to the file's top level (`cardOf`, `railOf`, `mainOf`, `fixture`, `appliedInstance`, `loaded`, `expect…Card`), so a second describe can use them.
     - Story 12.3's tests go in their own `test.describe`. Every test keeps `@floor`.
   - **T1 (extended):**
     - it records the code `POST`s by time;
     - before the onset, the card shows a QR;
     - between the page applying the onset and it applying the clear, the reload included, there is no `POST`;
     - after the clear, a new `POST`, and the card shows the link with `ocutalon_ci_bot`.

     Its other assertions stay.
   - **T3, the real chain** (`test.setTimeout(180_000)`): the matrix rows "A fresh code", "The code runs out while the user types", "A past expiry, with focus on the link", "The server side of the codes" and "No code anywhere else". Each answer's `{status, body, at}` is recorded by the route handler, which keeps the real values. The symbol oracle `S(link)` imports `qrcode-generator` in the spec. In `finally`: `Finish(saved)`, then `setTelegramIncluded(was)`, in nested `try`/`finally` as in T1.
   - **T4, the changed snapshots:** the rows "Refused while the server is off" and "Paired". The seam is on, with `changeSnapshot` and one reload per case, the routes cleared between cases, and `finally` restoring the seam.

**Acceptance Criteria:**
- Given Telegram is on (`state` `on` in `/state`'s Telegram block) and the session is unpaired, when the page calls `POST /api/v1/pairing/code` through `ApiClient.pairingCode()`, then Lane B's endpoint:
  - creates a 22-character base64url code;
  - stores only its hash, in the session's `Pairing` row, with an expiry 10 minutes after it was issued;
  - replaces any earlier code of the session;
  - returns the plaintext only in the HTTP response.

  Matrix rows "A fresh code", "The server side of the codes" and "No code anywhere else" (FR-18, AD-1, AD-4). And while the Telegram state is not `on`, or `telegramPaused` is set, the endpoint answers 409 and issues no code, and the card shows its off or paused state instead: rows "Refused while the server is off" and "Paused" (FR-21, FR-22).
- Given a fresh code, when the card shows it, then the card draws a 132-pixel QR code in the browser with `qrcode-generator`, navy on white in both themes, for `https://t.me/<bot>?start=<code>`. `<bot>` is the `botUserName` from `/state`, which `TelegramIn` records from `getMe`. The card also shows the alt text, the scan line, an "Open in Telegram" link with the same code named with "(opens Telegram)", and "New code in {n} min" (FR-18, AD-14, UX-DR6, UX-DR42, UX-DR55, UX-DR56, UX-DR135). Row "A fresh code"; `{n}` per the rows "A past expiry, with focus on the link" and "The code runs out while the user types".
- Given the code expires while the page is open, when "New code in {n} min" runs out, then the page fetches a new code and replaces the QR code and the link in place without losing input, and moves focus to the new link if the old one had it (FR-18, UX-DR55, UX-DR131, UX-DR135). Rows "The code runs out while the user types" and "A past expiry, with focus on the link".
- Given codes issued during a test run, when a test searches the production messages, headers, event log, live events and audit entries, then no code appears in any of them, and each scan finds a value that its store does hold (FR-18, AD-4). Row "No code anywhere else".

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs:**
- AD-4: the code is made by the web layer and stored only as `HashCode` in `Pairing`. A new code replaces the session's earlier one, and the plaintext travels only in the HTTP response, never in a message, header, log, live event or audit entry. This is the search's rule.
- AD-14: the QR code is drawn in the browser from the pairing link, with the library Lane B pinned (the Stack row). The bot's user name comes from `getMe` through `RecordTelegram`.
- AD-13: no `bypassSecurityTrust*` or `innerHTML`, and `script-src 'self'`. State-changing calls go through the one typed client, whose interceptor adds the envelope.
- AD-12: the card learns `on` and the bot name only from the snapshot, and a pause from the store's live `status` (12.8).
- AD-1: the card submits no command. Asking for a code is the web layer's own route (AD-4), not a production message.
- AD-17: the search's audit probe goes through the one writer, `Bridge.Audit.Record`.
- AD-19: the token comes from the environment only. Nothing in this story reads it except 12.8's `Token`.
- AD-22: the tests run in throwaways against the CI mock. No mock change: the `getMe` name is a queued reply through `/control`.
- AD-29 and AD-33: the card folder, `telegram-*.spec.ts` and `Test/Channel/**` are Lane A's. Lane B files are called, never edited, except the one entry below.
- AD-32: the card's texts are page constants beside `RAIL_TEXTS`. The catalog is for messages.

No acceptance criterion contradicts an AD. The NFRs this story touches are measurable as written: the code's lifetime, the alt text and "New code in {n} min".

**Footprint (Rule 11 (b); reported under `footprint_extensions:`).**
- Lane A files:
  - `telegram-card.ts` and `telegram-card-view.ts`, plus an optional new `telegram-qr.ts` in the card folder;
  - `telegram-page.spec.ts`;
  - `Test/Channel/LiveCase.cls`, `TelegramNoToken.cls` and `TelegramPageFixture.cls`.
- One Lane B file is edited by entry, under the orchestrator's standing ruling for `ux-strings.test.mjs` (one entry per need): its `SOURCES.ux` gains this story's five card strings. No card text can ship without it. `icon.ts` and `api-client-sources.test.mjs` are not touched.
- No contended file is touched. `Data/Pairing.cls`, `Bridge/Audit.cls` and `Test/Data/PairingRows.cls` are called or untouched.

**Decided in-stage:**
1. **No bot name, no code.** A link without a name cannot work, so `on` with an empty `botUserName` shows nothing and asks for nothing. The real server never pairs `on` with an empty name (`In.cls:151-155`). This also keeps Lane B's R11 green as written: it changes only `state`, so its name is the install step's `""`, and no `rail.spec.ts` edit is needed.
2. **A 409 shows the off state.** A 409 that comes while the store holds no pause means the server's state is not `on` (the snapshot is stale: no event carries the state). The card shows what a reload would show: "Telegram not set up". It does not ask again until its inputs change, so a stale page never polls a refusing route. The paused state still wins, and a pause that arrives as an event shows on that update.
3. **Other failures** (404, 5xx, no connection) show nothing, and the card asks again after 30 s. The UX has no error state for the card, and an expired code must not stay on screen.
4. **The lifetime rule.** The due time is `min(expiresAt, receivedAt + 10 min)`, and two requests are at least 10 s apart.
   - A browser clock behind the server's would otherwise keep a dead code on screen.
   - A clock ahead would make every code look expired and loop.
   - A delay over the browser's timer maximum fires at once.

   10 s keeps a skewed browser at 6 requests a minute, each one replacing a row, while it still leaves time to scan.
5. **`{n}` rounds down, with a floor of 1.** "Minutes rounded down" is `countdownText`'s rule, so a fresh code reads "New code in 9 min", which is the UX's example. "Never below 1" is `countdownSpokenMinutes`'s last-minute rule, so the card never says "0 min".
6. **The QR symbol:** error correction M with an automatic version (`qr-pin.test.mjs`'s calls). There is one path of unit squares in module units, and the quiet zone is the block's padding token. `forced-color-adjust: none` keeps the symbol navy on white under forced colours (DESIGN: always navy on white).
7. **The link opens a new tab** (`_blank`, `noopener noreferrer`), so the page, its draft and its session are never navigated away from. `noreferrer` keeps the page's address from Telegram. Its name uses the UX's "(opens Telegram)". There is no external-link icon (the mockup's D1 has none).
8. **No focus code.** The refresh binds the new values into the elements that are already there, so focus stays put, whether on the link or elsewhere. `announce-focus-sources.test.mjs` therefore needs no entry. The refresh announces nothing: the UX's announcer table has no entry for it.
9. **The stand-in for ten minutes** is the route changing `expiresAt` on its way to the page, while the real answers are kept for the oracles. It is the same discipline as 12.8 moving the mark.
   - **The first answer** (due in 10 s) shows the countdown running out.
   - **The second** (due 60 s ago) shows a fast browser clock held to one request every 10 s.
   - **The third** is passed through, to pin "9 min".

   A `page.clock` jump would also trip the live channel's contact watch (`live-state.ts`), so it is not used.
10. **The search's probes.** No production message, event-log row, live event or audit entry is written by issuing a code, so every scan would read an empty store. `Codes` writes one probe per store through product paths, then removes them, as `TelegramNoToken` and `KeyScan`'s own test do:
    - a not-paired `Unpair` through `Commands.Submit` for a fresh `Fixture.Session("zztgqr")`, for the headers and bodies;
    - an `Ens.Util.Log.LogInfo` row with a unique text, for the event log;
    - a `status` event with a unique condition on the probe session's stream, for live events (not a guide trigger, and no page reads that stream);
    - a `Pairing` audit entry with a unique reason, for the audit log.
11. **`Finish` removes the code rows** the page made since `Start`, so T1 and T3 leave no code row behind (Rule 19). Deleting by "not present at Start" covers both tests without either one knowing its session.
12. **`Start`'s `botName`** proves the link follows `getMe`. With the mock's default name, a card that hard-coded `ocutalon_ci_bot` would pass.
13. **No Node unit test of the view.** It would be a new file in Lane B's `web/scripts/`. DW-499 (`wontfix-accepted`) still stands: T1 to T4 and R11 pin each branch, and `ux-strings.test.mjs` imports the module.
14. **Where the tests run and what they cost.** T1, T3 and T4 run in the existing `live:demo-path` unit, in the `browser` group. No unit is added or moved, and `ci/units.sh` is unchanged.
    - Expected (inference): T3 ≈ 45 s locally (20 s of it fixed waits), T4 ≈ 10 s, T1 + 1 s. On the runner, about 1.5 to 2 minutes more for `browser`.
    - `browser` was 26 minutes on the last full run, and 12.8 adds about 1.5, so it lands at about 29 to 29.5 minutes, under 30.
    - If a run shows `browser` over 30, moving a unit is the orchestrator's (`ci/units.sh` is Lane B's). See Residual risks in the run result.
15. **`qr-pin.test.mjs`'s header** ("Nothing in web/src imports it yet: Story 12.3 draws the code") becomes history. It is a comment in a Lane B file, so it is left for Lane B and not taken as a second entry.
16. **Not planned here:** UX-DR137's "an unpaired Telegram card tops the device column" at 1024 to 1279 px, and its place in the single column. No acceptance criterion of this story carries it, and it would be Lane B's layout (`main-page`). It is flagged for the lead to route.

**Extend, don't copy (Rule 2):**
- **The card:**
  - The card and its view extend 12.8's `telegramCardView`, its precedence and its `data-state` hook, instead of a second component.
  - The link copies the not-set-up link's pattern (`.link`, a new tab, a visually hidden suffix).
- **The countdown:** it follows `countdownText` and `countdownSpokenMinutes` (Lane B's `page-time.ts`), but it is a one-line function of its own. The card needs a bare number for its own template, "New code in {n} min", while `countdownText` returns phrased text ("in 9 min"). Splitting that text would couple the card to another module's wording.
- **The QR symbol:** the calls are `qr-pin.test.mjs`'s. The library's own SVG and image builders are not used, because they draw black.
- **The fixture:**
  - It extends `Start` and `Finish` instead of adding a second start.
  - The search calls `LiveCase`'s and `TelegramNoToken`'s scans, moved into `LiveCase` (Tasks 1 and 2), and `KeyScan.Find`, `AuditLog`, `RunnerFixture.EventMark` and `LogRowsHolding`, and `Fixture`'s helpers.
  - **Copy:** the SQL of `CodeRows` and `ColumnsHold` (two queries, about ten lines). The originals are private methods of Lane B's `Test.Web.PairingApi`, which Lane A may neither call nor edit (AD-33).
- **The spec:**
  - It reuses `fixture()`, `appliedInstance`, `changeSnapshot`, `signInReadmeLoaded`, `composerOf`, `inMs`, `setTelegramIncluded`, `quoted` and `plain`.
  - The route stand-in is a local helper beside `changeSnapshot`'s pattern, because `support/**` is Lane B's and the stand-in is this spec's alone.

**Integration ACs (Rule 1):**
- The row "A fresh code": the page, the consumer, reads `/state`'s `botUserName`, which the real `TelegramIn` recorded from the mock's `getMe` (`ocutalon_qr_bot`). It reads the code from the real route, and it shows the link and the QR with both.
- The rows "The server side of the codes" and "No code anywhere else": the fixture reads back the real `Pairing` row and the production's stores after the page's real requests.

**Consumes:**
- From Story 10.3 (Lane B): `ApiClient.pairingCode()`, the code route and its 409s, `HashCode`, `StoreCode`, `ForCode`, `/state`'s Telegram block, and the pinned `qrcode-generator`.
- From Story 12.2: `TelegramIn`'s `getMe` → `RecordTelegram("on", name)`, `LiveCase` and the mock's queue.
- From Story 12.8: the paused state and its precedence, `TelegramPageFixture` and T1.
- From Lane B: `KeyScan`, `AuditLog`, `RunnerFixture`, `Fixture`, `Commands.Submit`, `Live.Publish` and the e2e support.

All of them are exercised against the real stack and mock.

**Consumed-by:**
- 12.4:
  - it reads the code from the "Open in Telegram" link (its `notBuilt` row says so);
  - it adds the paired state where this story shows nothing for `paired` true, and the card's first focus rule (Unpair to the heading);
  - its pairing test may use `Start` and `Finish` as extended here.
- 12.5: the replaced and expired codes this story makes are the ones its "That code didn't work" reply answers. Its "just unpaired" state ends in this story's fresh code.
- 12.7: it turns the card on for the release, and the online demo then asks for codes through the same rules.

**Owned ledger:** none (the inbox is empty).

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=12 stage=<stage>'`, run from the worktree root.

How to run:
- Run one command per foreground call, with `timeout: 600000`, and never two IRIS test runs in one message.
- Tests never run on a dev slot. An IRIS MCP call, if needed, names `server: ocutalon-slot-c` and `namespace: OCUTALON`, after `iris_server_info`.
- Tear down only `e12s3i` and `e12s3iw`, also after a failure.

**Commands:**
- (loop) `npm --prefix web test`. Expected: every `scripts/*.test.mjs` passes, among them `ux-strings`, `page-safety`, `announce-focus-sources`, `floor-sources`, `shell-styles`, `qr-pin`, `tokens` and `api-client-sources`.
- (loop) `npm --prefix web run lint`. Expected: `tsc` on the e2e (with the spec's `qrcode-generator` import) and `node --check` pass.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s3iw ci/warm.sh up`, before the stage's first `ci/iris.sh build`. A rebuilt bundle changes the warm manifest, so after a build run `down`, then `up`.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e12s3iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Channel.TelegramNoToken`, `TelegramPause`, `TelegramIn`, `TelegramOut`, `TelegramMock`, `TelegramSwitch` and `TelegramApi`. Expected:
  - `CLASS … passed`;
  - the moved helpers behave the same;
  - `TelegramPageFixture` compiles (it appears in the `WARM reloaded` line).
- (loop) `<lane> OCUTALON_RUN_TAG=e12s3iw ci/warm.sh down`.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s3i ci/iris.sh build`, once after each change under `web/src` and before any browser unit.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s3i ci/iris.sh live demo-path`. Expected:
  - every PASS line, and no FAIL line;
  - `STEP 1 page: partly skipped`, with telegram-page's four tests (T1, T2, T3, T4) passed and Story 12.4's part skipped.

  If the run dies of the unit deadline with no failed test, re-run it with `OCUTALON_LIVE_DEADLINE=900`.
- (once) The fresh-environment check, one call each: `<lane> OCUTALON_RUN_TAG=e12s3i ci/iris.sh shard lane-a@Channel`, then the same with `--reverse`. Expected: every Channel class passes in both orders.
- (once) The either-order check for the browser tests:
  1. Reverse the order of the four tests in `telegram-page.spec.ts` (a temporary edit, with your own backup).
  2. Run `live demo-path` once.
  3. Restore the file and compare it byte for byte with the backup (`cmp`).
- (once) `<lane> OCUTALON_RUN_TAG=e12s3i ci/iris.sh live sign-in --part 1/2`, then `--part 2/2`. Expected: passed. R11's `on` row (no bot name) still shows an empty card, and `api/pairing.spec.ts` is unchanged.
- (once) One per call: `bash docker/tests/test-ci-config.sh` (`TelegramPageFixture` is no test class), `bash docker/tests/test-boundaries.sh`, then `bash ci/checks.sh`.
- (once) Write the changed and new paths to a file in the stage's scratchpad, and run `bash ci/changes.sh ci.yml --paths-from <file>`. Record the groups.
- (once) `<lane> OCUTALON_RUN_TAG=e12s3i ci/iris.sh teardown`.
- (once) `git status --short -- ci web/src/app/api web/src/app/live web/src/app/chat web/src/app/rail/rail-view.ts web/src/app/rail/status-rail.ts web/src/app/icon web/e2e/support web/e2e/rail web/e2e/api web/package.json web/package-lock.json src/ocutalon/cls/OcuTalon/Web src/ocutalon/cls/OcuTalon/Data src/ocutalon/cls/OcuTalon/Channel src/bridge README.md` prints nothing. The only Lane B path changed is `web/scripts/ux-strings.test.mjs`.
- (once) Record the build's initial bundle total from the `ci/iris.sh build` output. Expected: under the 1 MB error budget (the library adds about 20 kB, inference).
- Left to CI (Rule 23):
  - `browser` (`demo-path` with T1 to T4, `sign-in` with R11, `answers`);
  - `production` (`shard:lane-a@Channel`, with the moved helpers);
  - the other groups that `ci/changes.sh` selects.

  Record `iris (browser)`'s minutes and `live:demo-path`'s seconds.

**Shared surfaces:**
- **The Telegram card's rendered states.** The `on` card is no longer always empty: with a bot name and no pairing, it shows the unpaired view. Readers:
  - R11 (`rail.spec.ts`), whose `on` row has no bot name and stays empty (Decided 1);
  - 12.8's T1 (extended here) and T2 (off and rejected, unchanged).
- **The page's requests.** The card's `POST /ocutalon/api/v1/pairing/code` joins the page's traffic. Readers: T1's token search of every `/ocutalon/` response (no token in a code answer). `api/pairing.spec.ts` calls the route itself and is unaffected.
- **The `Pairing` table's code rows.** The page makes the README session's code row in T1 and T3, and `Finish` removes it. Readers: Lane B's `PairingApi` and `PairingRows`, and `api/pairing.spec.ts`. These run in other units, on their own fixture sessions.
- **The UX strings inventory** gains five strings (`ux-strings.test.mjs`).
- **`LiveCase`'s helpers** gain `HeaderMark`, `HeadersFrom`, `RowsText`, `Bodies` and `LiveMark` as public class methods. Readers: `TelegramNoToken` and `TelegramIn`.
- **`TelegramPageFixture.Start` and `Finish`:**
  - `Start` gains an optional `botName`, and T1 calls it without one;
  - `saved` gains a fourth element;
  - `Finish` gains the code-row removal.
- **The mock's Bot API state:** the queued `getMe` reply is consumed by `Start`, and `Finish` resets the mock.
- **The audit log** gains `Codes`' probe entry (append-only, as in 12.2). The other probes are removed.
- **The demo path's step 1 counts:** +2 passed (T3, T4). The verdict stays `partly skipped`, and `test-demo-path-gate.sh` reads fixtures only.
- **Every test added or changed passes on a fresh environment, in either order.**

**Pinning mutations to apply (Rule 19).**
- Each is applied, seen red, and reverted byte for byte (`cmp` against your own backup; `git status --short` and `git diff --stat` unchanged). It is then recorded here as `mutation: … -> …`.
- A mutation of Lane B code is temporary.
- A web mutation is followed by `ci/iris.sh build`, and each mutation runs `live demo-path`.
- No mutation points a call at the public API.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC1, the code is the server's | The card shows a fixed 22-character code instead of the answer's | T3 ("A fresh code": the link's code is not the answer's) |
| AC1, the row | `Web/Api.cls` `PairingCode` skips `StoreCode` | T3 (`Codes`: no row for the last hash) |
| AC1, And: off | On a 409 the card shows nothing (the refusal ignored) | T4 (refused: not-set-up expected) |
| AC1, And: paused | The card's request condition ignores the pause (only the view checks it) | T1 (a `POST` during the pause) |
| AC2, the link follows `getMe` | The link names `ocutalon_ci_bot` whatever the snapshot says | T3 (`href` and `S(href)` against `ocutalon_qr_bot`) |
| AC2, the symbol encodes the link | The symbol encodes the code alone | T3 (the path is not `S(href)`) |
| AC2, navy on white in both themes | The path's fill is `var(--ink)` | T3 (the dark case: the fill is not `rgb(16, 42, 69)`) |
| AC2, `{n}` | `Math.ceil` instead of `Math.floor` | T3 (the third answer: "10 min" against 9) |
| AC3, the refresh | No refresh at the due time | T3 (no second `POST` within 16 s) |
| AC3, focus to the new link | The link is re-created for each code (`@for (one of [code]; track one)`) | T3 (the focused element is not the link with code 3) |
| AC3, without losing input | The refresh reloads the snapshot (`LiveState`'s reload) or moves focus to the link | T3 (the composer loses focus) |
| AC3, the spacing | No 10 s spacing | T3 (more than one `POST` within 9 s of answer 2) |
| AC4 | `Web/Api.cls` `PairingCode` writes the code to the event log (`##class(Ens.Util.Log).LogInfo(…, code)`) | T3 (`Codes`: the event log holds a code) |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan summary.** The card gains its unpaired state (QR code of `https://t.me/<bot>?start=<code>`, the scan line, "Open in Telegram (opens Telegram)", "New code in {n} min"), asks for its code through `ApiClient.pairingCode()`, refreshes it in place at its due time with a 10 s spacing, and shows its off state on a 409 and its paused state on a pause. The tests are T3 and T4 (new) and T1 (extended), in `telegram-page.spec.ts`. `TelegramPageFixture` gains `Start(…, botName)`, the code-row removal in `Finish`, `CodeMark` and `Codes`, and `LiveCase` takes `TelegramNoToken`'s scans as public class methods.

**Footprint extensions to report:** `web/scripts/ux-strings.test.mjs` (`SOURCES.ux` gains the five card strings). No other Lane B file, and no contended file.

**For the lead:**
- UX-DR137's placement of the unpaired card at 1024 to 1279 px and in the single column is in no story's acceptance criteria, and would be Lane B's layout (Decided 16).
- The header comment of `qr-pin.test.mjs` becomes history (Decided 15; Lane B's).

**Residual risks.**
- `browser` is expected at about 29 to 29.5 minutes on the runner after Stories 12.8 and 12.3 (inference). A run over 30 minutes needs a unit moved in `ci/units.sh`, which is the orchestrator's (Lane B's file).
- A browser clock far from the server's is held to one code request every 10 s (fast clock) or to the ten-minute cap (slow clock). The page's other countdowns assume synchronised clocks, as before.
- Background tabs may run the refresh timer up to a minute late (browser timer throttling, inference). The expired code then shows until the timer fires, and a scan of it gets Story 12.5's "That code didn't work" reply.
