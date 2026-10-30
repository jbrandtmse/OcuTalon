# Epic 12 Context: Approve from your own phone with Telegram

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Telegram puts the demo on the user's own phone. The user scans the page's QR code to pair their private chat with their OcuTalon session. The chat then carries turns, notifications, reminders and approval requests with Approve and Reject buttons, and every copy of an approval shows who answered. Unknown codes, a bare `/start` and strangers get polite replies that link nothing and reveal nothing. OcuTalon runs fully without a bot token, and when another process polls the same bot it pauses politely and the page says when it will try again. Lane A builds it on the session side Lane B finished, switched off, in Story 10.3. It ships as 0.1.1, right after 0.1.0 and before the online demo goes public, and merges only after the `v0.1.0` tag exists.

## Stories

- Story 12.1: Telegram stays off without a token, and CI mocks the Telegram API (done)
- Story 12.2: OcuTalon polls and writes to its own bot, and pauses when another process polls it (spec ready for development)
- Story 12.8: The page shows when Telegram is paused, and when it will try again (planned next, after 12.2 and before 12.3)
- Story 12.3: The Telegram card shows a fresh pairing code as a QR code
- Story 12.4: A valid code pairs the chat with the session
- Story 12.5: Bad codes, a bare start command and unpairing get polite answers
- Story 12.6: Chat and get notifications in the paired Telegram chat
- Story 12.7: Approve or reject from Telegram, and every copy shows who answered

## Requirements & Constraints

- **0.1.0 has no Telegram.** `OcuTalon.Channel.Telegram.In.Included()` keeps its test-only body (1 only when `^OcuTalonTest("TelegramIncluded")` is 1) until Story 12.7 makes it return 1. Earlier stories turn Telegram on in their tests through that seam (`Test.Data.Fixture.SetTelegramIncluded`). While it returns 0, `/state` hides the Telegram section and the pairing endpoints answer 404.
- **The one switch is built.** `OcuTalon.Install.Step.Telegram` writes structural `Enabled` rows for `TelegramIn` and `TelegramOut` at every start: 1 only when `Included()` is 1 and `TELEGRAM_BOT_TOKEN` is not empty. It records `off` only on the disabled path. On the enabled path `TelegramIn` owns the mark, through `StatusMark.RecordTelegram`: `on` with the bot's user name, `rejected` when `getMe` rejects the token, `off` when it stops. No item checks `Included()` itself.
- **No real bot.** Every story runs against the CI Telegram mock with its dummy token. Never call `api.telegram.org`, never use or ask for a real token, never read or print `.env`. A real bot appears only in the Contest Planner's hands-on pass on the 0.1.1 candidate (Story 12.7): Telegram Web, the 20-run timings, and a verified TLS handshake with `api.telegram.org` through `OcuTalonClient` with peer verification on, all recorded in the candidate's record and none a merge criterion.
- **Nothing leaks.** No token, chat id, display name or pairing code in a production setting, a `%Status` text, a log, the trace, an audit entry, a live event, a commit or the page. The token is in the request path (`/bot<token>/<method>`), so a request URL must never reach an error text or a log line. 12.2's test searches the server side for the dummy token; 12.8's searches the page.
- **One client SSL configuration (owner's U-164).**
  - `OcuTalonClient`, made by `Install.Step.SSL`, is the one general configuration for all of OcuTalon's outbound HTTPS (the later email story reuses it), never a Telegram-only one. It holds no secret (no private key, certificate password or credential) and verifies the peer. Changing it is a security-posture veto item.
  - A test against the shipped image (never slot A) proves the CA file it names exists in the image and that a disposable local TLS server with a bad certificate is refused, never a real external host.
  - With an `http://` endpoint override (the CI mock, the demo host's gateway) both items make plain HTTP requests with no SSL configuration in the way.
- **No lost or repeated updates.**
  - `TelegramIn` keeps the next offset to confirm (the last handled `update_id` plus 1) at `$$$EnsStaticAppData("TelegramIn", "offset")` and nowhere else; no node means no offset.
  - That one value confirms updates and skips handled ids, and is read before polling, so a reset made while it is stopped takes effect at its next start. DW-422 (12.2): tests prove the poller keeps its offset in the node `Test.Channel.BotApi.Offset()` reads.
  - Retry a 429 after its `retry_after`. A long poll always ends inside the 60-second `stop_grace_period`.
- **A rejected token and a busy bot.** A rejected `getMe` keeps Telegram off for that start, the card shows "Telegram not set up", and the log says so without the token. A 409 from `getUpdates` stops polling for 5 minutes through `StatusMark.Record("telegramPaused", until)`, from which `StatusMonitor` and `/state` raise the paused condition; then it polls again, success clears it, another 409 pauses again. The server side is 12.2's; the banner, the card's paused state and "the banner leaves within one live update" are 12.8's.
- **Text.** Plain text with no parse mode, so model-written punctuation arrives exactly as written. Split a text over 4,096 characters at line breaks, and a single longer line at the limit. DW-30 (12.6): `Catalog.Render` caps no length, so rendered notices must stay within the limit.
- **Who gets processed.** Only private-chat messages and button presses. A group or channel message gets no reply and creates no message, row or audit entry. An unpaired chat reaches no session and no model, and no reply to it names a session, a person or any state. A paired chat's text is the user's own turn: queued behind a running turn, never inside a tool result.
- **Notifications match the phone.** Same text as the simulated phone for the same catalog key, times in the instance's zone; a test compares them key by key. DW-295 (12.6): Telegram shows no check rows, so "Is everything OK?" must still get a status there; the ledger routes it as rendering the reply's check key and rows on Telegram. The all-clear still comes only from code.
- **Approvals.** A button carries the request's random `Ref` and the action, never a sequential number; the first answer wins. A late press, a press from another chat, or one on an unknown or pre-reset request changes nothing.
- **Timing.** "Telegram paired" within 5 seconds of a valid `/start <code>`; every other copy shows an approval's result within 5 seconds. CI checks both against the mock on every run.

## Technical Decisions

- **Lanes and binding rulings (orchestrator, 2026-10-30, every later story).**
  - Epic 12 stays inside Lane A's files: `OcuTalon.Channel.Telegram`, `web/src/app/rail/telegram-card/`, `web/e2e/demo-path/telegram-*.spec.ts`, the README's Telegram section and `ci/mock/scenarios/A/`. Any other edit needs an orchestrator ruling.
  - Lane B's mock code (`ci/mock/*.mjs`, `ci/mock/test/**`) and `OcuTalon.Test.Contract.Mock` never change. Lane A extends the mock only by adding scenario files; needed mock behaviour is a "Lane B mock ask (AD-22, AD-33)" under the story's Design Notes, judged at the spec gate.
  - `Install/Step/Telegram.cls` and `Install/Step/SSL.cls` (Epic 15's `Install/**`) are file-level extensions allowed for Epic 12 and reported in the runner's contract; `Install/Registry.cls` and its `Order()` stay untouched. 12.1 also extended `docker/tests/lib-live.sh` (its own functions only, never `iris_script`), `test-lib-live.sh` and `test-production-restart.sh`.
  - The runner never amends the spine. DW-420: `lane-a` gains `Channel`, which the orchestrator writes into AD-22 at the merge gate.
  - Lane B owns the session side these stories call: `Data.Pairing`, `Data.StatusMark`, `Data.Delivery`, `SessionOps`, `AnswersIn.FromTelegram`, `Notify`, `Conversation`, `Allowance`, `Trace`, the pairing endpoints, `/state` and the banners.
- **What 12.2 delivers (planned in 12.2, not yet built).** `TelegramIn` and `TelegramOut` still carry `STUB = 1`; delete it when building each, because the release check refuses an enabled stub.
  - `Channel/Telegram/Api.cls`: the one Bot API client (`Api.Call`), `%Net.HttpRequest` in product code; it sets `Https` and the SSL configuration only for an `https://` base. Product code never calls test classes, so it copies no request building from `Test.Contract.Mock` or `BotApi`.
  - `TelegramIn` (`FailurePoller`'s shape):
    - `OnInit` records `off`; `getMe` runs on the first poll in `OnProcessInput`, and only 401 or 404 means `rejected`.
    - `getUpdates` timeout 5 s, HTTP read timeout 8 s, `CallInterval` 1, so 10-second stops in tests and CI hold once it runs at every start. `allowed_updates` asks for messages and presses only.
    - The offset node is read before every poll and written after each update; a failing update is logged and confirmed. A private update is `Pairing.RecordChat(chatId, "")`, with no name.
    - 409: the `telegramPaused` mark is the one truth, survives a restart, is left by `OnTearDown` and deleted by success. A 429 on `getUpdates` waits `retry_after` or 5 s.
  - `TelegramOut` (extends `Channel.Operation`, `SimPhoneOut`'s MessageMap): sends an `Outbound` or `Notification` by `ChatRef` (none: a warning and an OK status). Plain text; the split counts UTF-16 units, never splits a surrogate pair, drops the break at a cut. A 429 resends the same part after `retry_after` (at least 1 s), at most 5 tries; other failures are error statuses.
  - Host settings `ApiBase` and `SSLConfig`, declared in each item. A new `Install.Step.Telegram.Base` writes `ApiBase` as a structural row at every start, from `OCUTALON_TELEGRAM_API_BASE` (CI: `http://mock:8080`) or the public API; `SSLConfig` defaults to `OcuTalonClient` with no row. The token comes only from the environment; the online demo's gateway swaps its dummy token for the real one.
  - `Test/Channel/LiveCase.cls`: the live-test helpers moved out of `TelegramMock` (reuse it, don't copy), with new `TelegramApi`, `TelegramIn`, `TelegramPause`, `TelegramOut`, `TelegramSettings` and `TelegramNoToken` test classes and three new scenarios (rejected `getMe`, a busy `getUpdates`, a 200 then a 429). Lane B mock ask: none.
- **Commands go through messages.** `TelegramIn` submits `Pair` and `Unpair` (`/stop`) through `Commands.Submit` with origin `telegram`; `SessionOps` returns the outcome and `TelegramIn` sends the reply. A press goes synchronously through `AnswersIn.FromTelegram(ref, action, chatRef, .code, .slots)`. Arriving text never approves, pairs or changes a setting by its content.
- **Identity.** Production messages carry only `SessionRef` and `ChatRef`. The chat id and display name live only in the `Pairing` row (`Pairing.RecordChat`); 12.4 decides when a name is kept. The name reaches only the session's own page (`/state`, the `pairing` event), never the audit writer, log macros or step summaries; the Telegram items don't offer `ArchiveIO`.
- **Rendering.** Only `*Out` operations render, through `Msg.Catalog.Render(key, slots, "telegram")`, except `TelegramIn`'s `answerCallbackQuery` text, rendered from `AnswersIn`'s result code and slots. Keys exist: `pairing.*`, `press.*`, `answered.*` in `Catalog.Core`, notices and results in `Catalog.Watch`. Buttons only on kinds `incident` and `approval` with an `ApprovalRef`. An edit finds its message with `Delivery.FindByApproval(approvalRef, "telegram", ownerRef)`; a Telegram row's message id is `<ChatRef>:<message_id>`.
- **Trace and events.** A Telegram turn joins the session's daily thread: `TelegramIn` calls `Trace.Join` and sets `..%SessionId` and `..%SuperSession` inside `OnProcessInput` before its first send. Only `SessionOps` publishes `pairing`; `TelegramIn` publishes no live events.
- **The CI mock's Bot API side** (read-only for Epic 12):
  - It serves `getMe` (default bot `ocutalon_ci_bot`), `getUpdates`, `sendMessage`, `editMessageText` and `answerCallbackQuery`; an empty token gets a 401.
  - Tests queue through `/_mock/telegram/updates` and `/replies`, read `/calls`, and clear with `/reset` (ids restart at 1).
  - `getUpdates` drops ids below the offset and, with nothing queued, waits `min(timeout, 50)` s, answering at once when a reply is queued.
- **Test plumbing from 12.1.**
  - Lane A's scenarios `ci/mock/scenarios/A/telegram-*.json`: private, group and button updates (`update_id` 1), `telegram-conflict` (409), `telegram-rate-limited` (429 on `sendMessage`, `retry_after` 2).
  - `Test.Channel.BotApi` gives `Offset`, `SetOffset`, `PollerReason`, `BotReply` and `Reset`, which clears the offset with the mock reset and refuses while a live `TelegramIn` runs; reset only through it, one update source per reset.
  - Live tests (throwaways and CI only) check `TelegramMissingReason` and `PollerReason()` first and start and end with `BotApi.Reset()`. New `OcuTalon.Test.Channel.*` classes join `lane-a`'s `Channel` area in `shards-2`.
  - `live_no_bot_token` in `lib-live.sh` gives a CI start with no token (row 19 of `test-production-restart.sh`; 12.7 reuses it).
- **Running `TelegramIn` in a test.** Through 12.6 no CI start runs it, so a test that enables it must stop it and restore its rows and the seam before returning. Whether the `Enabled` row takes effect for this pool-1 item is unmeasured (inference) until 12.2 runs it.
- **Other checks.** `docker/tests/test-readme.sh` reads `Included()`'s body literally: the test-only body forbids the word Telegram in the README; any other body requires a `#telegram` heading. CI budget stays 35 minutes.

## UX & Interaction Patterns

- **Card states:**
  - **Not set up:** "Telegram not set up", with "How to set it up".
  - **Unpaired:** a 132 px QR code, navy `#102A45` on white in both themes, never inverted; the instruction line; "Open in Telegram", named with "(opens Telegram)"; "New code in {n} min".
  - **Paired:** "Telegram paired · {name}", with a ghost "Unpair" button named "Unpair Telegram"; one press, no confirmation.
  - **Paused (12.8):** "Telegram paused" and "Trying again at {time}", with the QR code withdrawn.
  - **Just unpaired:** "Telegram unpaired" for 5 seconds, then a fresh code.
- **Focus and announcements.** A refreshed code keeps the user's input, and focus moves to the new link if the old one had it. After an unpair, focus goes to the Telegram heading. The announcer reads "Telegram paired" or "Telegram unpaired".
- **Layout.** From 1024 to 1279 px wide the unpaired card moves to the top of the device column; narrower than 1024 px it follows the guide.
- **Message style.** Plain text: no Markdown, emoji, exclamation marks or arrows (use words); lists are lines led by words. Times in the instance's zone, "ET" on the online demo. An answered status in message form ends with a period. A refused press gets an alert that stays until dismissed. Telegram and the simulated phone share every text, from the Message Catalog.

## Cross-Story Dependencies

- **Order, and what each takes from 12.2:**
  1. 12.1 (done) built the switch, the scenarios and the test helpers.
  2. 12.2 polls and sends.
  3. 12.8 shows the pause on the page.
  4. 12.3 uses `botUserName` from `/state` for its link.
  5. 12.4 parses `/start` in 12.2's private handler, replies through `TelegramOut`'s `Notification`-by-`ChatRef` path, and turns on `telegram-page.spec.ts`.
  6. 12.5 uses the nameless unpaired rows and replies through `TelegramOut`.
  7. 12.6 adds turns, routing by `SessionRef` and `Delivery` rows on 12.2's transport (whose split meets DW-30).
  8. 12.7 adds presses and `Api.Call` for `answerCallbackQuery` and `editMessageText`, sets `Included()` to 1 with the README section, and turns on `telegram-approval.spec.ts`.
- **Story 12.8's ground today:**
  - The card, `web/src/app/rail/telegram-card/telegram-card.ts`, is Epic 12's and renders only not-set-up (`off` or `rejected`). `status-rail.ts` passes it only the store's `telegram` block (its `pausedUntil` comes from the snapshot), no live status.
  - Its texts sit in `RAIL_TEXTS` in `web/src/app/rail/rail-view.ts`, checked exactly by `web/scripts/rail-view.test.mjs`; page strings are listed in `web/scripts/ux-strings.test.mjs`; icons are in `web/src/app/icon/icon.ts` (no pause icon yet; 12.2's spec names `pause-circle`). These, and `banner-view.ts`, are in Epic 29's contended `web/src/app/**`, so editing them needs an orchestrator ruling.
  - The banner, its `banner.telegramPaused` key and its "Set up a bot" link already exist (`banner-view.ts`) and are tested by Lane B in `web/e2e/banners/banners.spec.ts`. 12.8 adds the pause seen from a real 409, the card's state, two strings, the icon and a browser spec. 12.3's second criterion also names the card's paused state.
- **DW-421 (escalated, a Lane B mock ask).** The mock keeps one Bot API state for every client. That first matters at 12.7: once `Included()` is 1, `TelegramIn` polls at every CI start, so `Test.Contract.Mock.TestTelegramBotApi` shares its queue and calls, and the live tests fail their poller check until 12.7 stops the poller around them or the ask lands.
- **Story 12.7 waits on Epic 11, still backlog:** its approval part needs Epic 11's incident, approval and result path; its restart and upgrade checks extend Story 11.2's harness; its hands-on gate runs inside Story 11.5's release sequence.
- **The merge gate.** Epic 12 merges only once `v0.1.0` is tagged; no such tag exists yet.
- **Story 16.9 has merged,** so 12.6 tests against the real `Allowance.TryConsume`; Story 31.3 turns on 16.9's Telegram cases later. Story 12.7 turns on R2c, Story 16.3's check in Lane B's `web/e2e-online/resume.spec.ts`.
- **Gaps:**
  - (12.2) The image's CA bundle was measured, but whether `%OSCertificateStore` resolves to it on Linux is inference until 12.2's image test; 12.2 may name the bundle as an explicit CA file instead. The first real handshake is 12.7's hands-on pass.
  - (12.7) Story 11.2's upgrade-and-restart harness isn't built; `release/` holds only `standalone-bridge.sh`. Story 11.5's release sequence, its hands-on gate and `release/records/0.1.1/` don't exist yet.
  - (12.7) Next to R2c, `R2b: /state returns the fixture pairing` is still a `notBuilt` placeholder owned by Story 10.3, which has merged.
