# Epic 12 Context: Approve from your own phone with Telegram

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Telegram puts the demo on the user's own phone. The user scans the page's QR code to pair their private chat with their OcuTalon session. The chat then carries turns, notifications, reminders and approval requests with Approve and Reject buttons, and every copy of an approval shows who answered. Unknown codes, a bare `/start` and strangers get polite replies that link nothing and reveal nothing. OcuTalon runs fully without a bot token and pauses politely when another process polls the same bot. Lane A builds it on the session side Lane B finished, switched off, in Story 10.3. It ships as 0.1.1, right after 0.1.0 and before the online demo goes public, and merges only after the `v0.1.0` tag exists.

## Stories

- Story 12.1: Telegram stays off without a token, and CI mocks the Telegram API (done)
- Story 12.2: OcuTalon polls and writes to its own bot, and pauses when another process polls it
- Story 12.3: The Telegram card shows a fresh pairing code as a QR code
- Story 12.4: A valid code pairs the chat with the session
- Story 12.5: Bad codes, a bare start command and unpairing get polite answers
- Story 12.6: Chat and get notifications in the paired Telegram chat
- Story 12.7: Approve or reject from Telegram, and every copy shows who answered

## Requirements & Constraints

- **0.1.0 has no Telegram.** `OcuTalon.Channel.Telegram.In.Included()` keeps its test-only body (1 only when `^OcuTalonTest("TelegramIncluded")` is 1) until Story 12.7 makes it return 1. Stories 12.2 to 12.6 turn Telegram on in their tests through that seam (`Test.Data.Fixture.SetTelegramIncluded`). While it returns 0, `/state` hides the Telegram section and the pairing endpoints answer 404.
- **The one switch is built.** `OcuTalon.Install.Step.Telegram` writes structural `Enabled` rows for `TelegramIn` and `TelegramOut` at every start: 1 only when `Included()` is 1 and `TELEGRAM_BOT_TOKEN` is not empty. It records `off` only on the disabled path. On the enabled path `TelegramIn` owns the mark, through `StatusMark.RecordTelegram`: `on` with the bot's user name when it starts polling, `rejected` when `getMe` rejects the token, and `off` when it stops.
- **No real bot.** Every story runs against the CI Telegram mock with its dummy token. Never call `api.telegram.org`, never use or ask for a real token, and never read or print `.env`. A real bot appears only in the Contest Planner's hands-on pass on the 0.1.1 candidate, where Story 12.7's Telegram Web pass and 20-run timings are recorded; they are not merge criteria.
- **Nothing leaks.** No token, chat id, display name or pairing code may appear in a production setting, a `%Status` text, a log, the trace, an audit entry, a live event, a commit or the page. The token is in the request path (`/bot<token>/<method>`), so a request URL must never reach an error text or a log line. Tests search all of these and must find none.
- **No lost or repeated updates.**
  - `TelegramIn` keeps the next offset to confirm (the last handled `update_id` plus 1) at `$$$EnsStaticAppData("TelegramIn", "offset")` and nowhere else. No node means no offset.
  - It uses that one value both to confirm updates and to skip ids it has handled, and reads it when it starts polling, so a reset made while it is stopped takes effect at its next start.
  - DW-422 (12.2): its tests must prove that the poller keeps its offset in the node `Test.Channel.BotApi.Offset()` reads.
  - Retry a 429 after its `retry_after`. A long poll always ends inside the 60-second `stop_grace_period` in `docker-compose.yml`.
- **A rejected token and a busy bot.** If `getMe` rejects the token, Telegram stays off for that start, the card shows "Telegram not set up", and the log says the token was rejected without showing it. On a 409 from `getUpdates`, `TelegramIn` stops polling for 5 minutes and records the pause through `StatusMark.Record("telegramPaused", until)`. It then polls again. Success clears the condition within one live update, and another 409 pauses it again.
- **Text.** Send plain text with no parse mode, so model-written punctuation arrives exactly as written. Split a text longer than 4,096 characters at line breaks, and split a single longer line at the limit. DW-30 (12.6): `Catalog.Render` caps no length, so rendered notices must stay within the limit.
- **Who gets processed.** Only private-chat messages and button presses are processed. A group or channel message gets no reply and creates no message, row or audit entry. An unpaired chat reaches no session and no model, and no reply to it names a session, a person or any state. A paired chat's text is the user's own turn: it is queued behind a running turn and never placed inside a tool result.
- **Notifications match the phone.** The paired chat gets the same text as the simulated phone for the same catalog key, with times in the instance's zone. A test compares the two key by key.
- **DW-295 (12.6).** Telegram shows no check rows, so the Chat agent can't rely on rows shown under its reply there, and "Is everything OK?" must still get a status in Telegram. The ledger routes this as rendering the reply's check key and rows on Telegram. The all-clear still comes only from code.
- **Approvals.** A button carries the request's random `Ref` and the action, never a sequential number, and the first answer wins. A late press, a press from another chat, or a press on an unknown or pre-reset request changes nothing.
- **Timing.** The page shows "Telegram paired" within 5 seconds of a valid `/start <code>`, and every other copy shows an approval's result within 5 seconds. CI checks both against the mock on every run.

## Technical Decisions

- **Lanes and the binding rulings (orchestrator, 2026-10-30, every later story).**
  - Epic 12 stays inside Lane A's files: `OcuTalon.Channel.Telegram`, `web/src/app/rail/telegram-card/`, `web/e2e/demo-path/telegram-*.spec.ts`, the README's Telegram section and `ci/mock/scenarios/A/`. The only other edits are the ones the orchestrator rules on.
  - Epic 12 never changes Lane B's mock code (`ci/mock/*.mjs`, `ci/mock/test/**`) or `OcuTalon.Test.Contract.Mock`. Lane A extends the mock only by adding scenario files. A story that needs new mock behaviour records a "Lane B mock ask (AD-22, AD-33)" under its Design Notes, and the runner judges it at the spec gate.
  - The runner never amends the spine. DW-420 records that `lane-a` gains `Channel`, which the orchestrator writes into AD-22 at the merge gate.
  - Extensions already ruled for 12.1: `Install/Step/Telegram.cls`, in Epic 15's `Install/**`; `docker/tests/lib-live.sh` (only 12.1's own functions, never `iris_script`); `test-lib-live.sh`; and `test-production-restart.sh`.
  - Lane B owns the session side that these stories call: `Data.Pairing`, `Data.StatusMark`, `Data.Delivery`, `SessionOps`, `AnswersIn.FromTelegram`, `Notify`, `Conversation`, `Allowance`, `Trace`, the pairing endpoints, `/state` and the banners, including the paused banner.
- **Stubs.** `TelegramIn` (an `Ens.InboundAdapter` service) and `TelegramOut` still carry `STUB = 1`. Delete each class's `STUB` parameter when you build it, because the release check refuses an enabled stub.
- **Commands go through messages.** `TelegramIn` submits `Pair` and `Unpair` (for `/stop`) through `Commands.Submit` with origin `telegram`. `SessionOps` returns the outcome, and `TelegramIn` sends the reply. A button press goes synchronously through `AnswersIn.FromTelegram(ref, action, chatRef, .code, .slots)`. Arriving text can never approve, pair or change a setting by its content.
- **Identity.** Production messages carry only `SessionRef` and `ChatRef`. The chat id and the display name live only in the `Pairing` row, written through `Pairing.RecordChat`. The display name reaches only the session's own page, in `/state` and the `pairing` event. Neither ever goes to the audit writer, log macros or step summaries, and the Telegram items don't offer `ArchiveIO`.
- **Transport.** Calls use `%Net.HttpRequest` in OcuTalon code, with one long-poll job per token, and the token comes only from the environment. The API base URL and the SSL configuration are host settings that default to the public API. CI overrides the base through `OCUTALON_TELEGRAM_API_BASE` (`http://mock:8080`, plain HTTP), and so does the online demo, whose gateway swaps its dummy token for the real one. No product code reads that variable yet.
- **Rendering.** Only `*Out` operations render, through `Msg.Catalog.Render(key, slots, "telegram")`, except `TelegramIn`'s `answerCallbackQuery` answer or alert, rendered from `AnswersIn`'s result code and slots. The keys exist: `pairing.*`, `press.*` and `answered.*` in `Catalog.Core`, the notices and results in `Catalog.Watch`. Approve and Reject go only on kinds `incident` and `approval` with an `ApprovalRef`. An edit in place finds its message with `Delivery.FindByApproval(approvalRef, "telegram", ownerRef)`; a Telegram row's message id is `<ChatRef>:<message_id>`.
- **Trace and events.** A Telegram turn joins the session's daily thread: `TelegramIn` calls `Trace.Join` and sets `..%SessionId` and `..%SuperSession` inside `OnProcessInput` before its first send. `SessionOps` alone publishes `pairing`, so `TelegramIn` publishes no live events. `StatusMonitor` and `/state` already turn the `telegramPaused` mark into the paused condition.
- **The CI mock's Bot API side** (Lane B's, read-only for Epic 12).
  - It serves `getMe` (default bot `ocutalon_ci_bot`), `getUpdates`, `sendMessage`, `editMessageText` and `answerCallbackQuery`. An empty token gets a 401.
  - Tests queue through `/_mock/telegram/updates` and `/replies`, read back through `/calls`, and clear through `/reset`, which restarts ids at 1.
  - `getUpdates` drops ids below the offset. With nothing queued it waits `min(timeout, 50)` seconds, and a reply queued meanwhile answers at once.
  - A rejected-token test needs a new `getMe` scenario file under `ci/mock/scenarios/A/`.
- **Test plumbing from 12.1.**
  - Lane A's five scenarios, under `ci/mock/scenarios/A/telegram-*.json`:
    - private, group and button updates, queued as scripted `getUpdates` replies with `update_id` 1;
    - `telegram-conflict`, a 409;
    - `telegram-rate-limited`, a 429 on `sendMessage` with `retry_after` 2.
  - `OcuTalon.Test.Channel.BotApi` provides `Offset`, `SetOffset`, `PollerReason` and `BotReply`, plus `Reset`, which clears the kept offset in the same call as the mock reset and refuses while a live `TelegramIn` job runs. Reset only through it, and queue one update source per reset.
  - `Test.Channel.TelegramMock` (throwaways and CI only) checks `Test.Contract.Mock.TelegramMissingReason` and `BotApi.PollerReason()` first, then starts and ends each test with `BotApi.Reset()`. `Test.Channel.TelegramSwitch` runs anywhere.
  - The `Channel` area sits in `ci/units.sh`'s `lane-a` and runs in `shards-2`, so new `OcuTalon.Test.Channel.*` classes join it.
  - `docker/tests/lib-live.sh`'s `live_no_bot_token` produces a CI start with an empty token, which `live_key_count` counts as no key. `test-production-restart.sh` row 19 uses it, and Story 12.7 reuses it.
- **Running `TelegramIn` in a test.** Through Story 12.6, no CI start runs `TelegramIn`, so a test that enables it must stop it and restore its rows and the seam before it returns. 12.1 pinned the switch only at the rows. Whether the `Enabled` row takes effect for this pool-1 item is unmeasured (inference) until 12.2 runs it.
- **Other checks.** `docker/tests/test-readme.sh` reads `Included()`'s body literally: the test-only body forbids the word Telegram in the README, and any other body requires a `#telegram` heading. The CI budget stays at 35 minutes.

## UX & Interaction Patterns

- **Card states:**
  - **Not set up:** "Telegram not set up", with "How to set it up".
  - **Unpaired:** a 132 px QR code, navy `#102A45` on white in both themes and never inverted; the instruction line; "Open in Telegram", named with "(opens Telegram)"; and "New code in {n} min".
  - **Paired:** "Telegram paired · {name}", with a ghost "Unpair" button named "Unpair Telegram". It acts on one press, with no confirmation.
  - **Paused:** "Telegram paused" and "Trying again at {time}", with the QR code withdrawn.
  - **Just unpaired:** "Telegram unpaired" for 5 seconds, then a fresh code.
- **Focus and announcements.** A code that refreshes keeps the user's input, and focus moves to the new link if the old one had it. After an unpair, focus goes to the Telegram heading. The announcer reads "Telegram paired" or "Telegram unpaired".
- **Layout.** From 1024 to 1279 px wide, the unpaired card moves to the top of the device column. Narrower than 1024 px, it follows the guide.
- **Message style.**
  - Messages are plain text: no Markdown, emoji, exclamation marks or arrows (use words), and lists are lines that lead with words.
  - Times are in the instance's zone, with "ET" on the online demo.
  - An answered status in message form ends with a period.
  - A refused press gets an alert that stays until dismissed.
  - Telegram and the simulated phone share every text, and the exact strings come from the Message Catalog.

## Cross-Story Dependencies

- **Order inside the epic:**
  1. 12.1 (done) built the switch, the scenarios and the test helpers.
  2. 12.2 polls and sends. Its `getMe` records the `botUserName` that 12.3's link needs.
  3. 12.3 shows the code as a QR code.
  4. 12.4 pairs the chat and turns on `telegram-page.spec.ts`.
  5. 12.5 adds the polite replies and unpairing.
  6. 12.6 adds turns, notifications and `Delivery` rows through `TelegramOut`.
  7. 12.7 adds the buttons and the edits in place, sets `Included()` to 1 together with the README section, and turns on `telegram-approval.spec.ts`.
- **Overlaps to settle at each story's plan:**
  - 12.2's criteria include `TelegramOut`'s plain text, splitting and 429 retry, but `Out.cls` still says it stays a stub until 12.6. 12.1's spec also lists the 429 scenario for 12.6.
  - 12.2's criteria include the card's paused state, but the card renders only the not-set-up state, and its doc leaves the other states to 12.3.
  - None of the card's new state texts exist yet. The two current ones sit in Lane B's `web/src/app/rail/rail-view.ts`.
- **DW-421 (escalated, a Lane B mock ask).** The mock keeps one Bot API state for every client. That first matters at 12.7: once `Included()` is 1, `TelegramIn` polls at every CI start, so `Test.Contract.Mock.TestTelegramBotApi` shares its queue and calls, and `Test.Channel.TelegramMock` fails its poller check until 12.7 stops the poller around it or the ask lands.
- **Story 12.7 waits on Epic 11, which is still backlog.** Its approval part needs Epic 11's end-to-end incident, approval and result path. Its restart and upgrade checks extend Story 11.2's harness, and its hands-on gate runs inside Story 11.5's release sequence.
- **The merge gate.** Epic 12 merges only once `v0.1.0` is tagged. No such tag is in this worktree yet.
- **Story 16.9 has merged,** so Story 12.6 tests against the real `Allowance.TryConsume`. Story 31.3 turns on 16.9's Telegram cases later, outside this epic.
- **A Lane B file still in reach:** Story 12.7 turns on R2c, Story 16.3's check in `web/e2e-online/resume.spec.ts`.
- **Gaps:**
  - Gap (12.2): no SSL configuration for the Telegram API exists. `OcuTalon.Install.Step.SSL` is still an empty stub, and its doc says the first story that needs a client SSL configuration fills it in place. That step is Lane A's installer core, but it sits in Epic 15's `Install/**`, so filling it needs an orchestrator ruling, like 12.1's step did.
  - Gap (12.7): Story 11.2's upgrade-and-restart harness isn't built. `release/` holds only `standalone-bridge.sh`.
  - Gap (12.7): Story 11.5's release sequence, its hands-on gate and `release/records/0.1.1/` don't exist yet.
  - Gap (12.7): next to R2c, `R2b: /state returns the fixture pairing` is still a `notBuilt` placeholder owned by Story 10.3, which has merged.
