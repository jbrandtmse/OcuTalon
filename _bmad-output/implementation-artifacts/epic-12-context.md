# Epic 12 Context: Approve from your own phone with Telegram

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Telegram puts the demo on the user's own phone. The user scans the page's QR code to pair their private Telegram chat with their OcuTalon session. From then on the chat carries conversation turns, notifications, reminders and approval requests with Approve and Reject buttons, and every copy of an approval shows who answered. Unknown codes, a bare `/start` and strangers get polite replies that link nothing and reveal nothing. OcuTalon runs fully without a bot token, and it pauses politely when another process polls the same bot. Lane A builds the epic on the session side that Lane B finished in Story 10.3 and left switched off. It ships as 0.1.1, the release right after 0.1.0 and before the online demo goes public. It is built alongside Epic 11, but it merges only after the `v0.1.0` tag exists.

## Stories

- Story 12.1: Telegram stays off without a token, and CI mocks the Telegram API
- Story 12.2: OcuTalon polls and writes to its own bot, and pauses when another process polls it
- Story 12.3: The Telegram card shows a fresh pairing code as a QR code
- Story 12.4: A valid code pairs the chat with the session
- Story 12.5: Bad codes, a bare start command and unpairing get polite answers
- Story 12.6: Chat and get notifications in the paired Telegram chat
- Story 12.7: Approve or reject from Telegram, and every copy shows who answered

## Requirements & Constraints

- **0.1.0 has no Telegram.**
  - `OcuTalon.Channel.Telegram.In.Included()` keeps its test-only body until Story 12.7 makes it return 1. Today it returns 1 only when `^OcuTalonTest("TelegramIncluded")` is 1, and only `OcuTalon.Test` classes set that global.
  - Stories 12.1 to 12.6 turn Telegram on in their tests through that global.
  - While `Included()` returns 0, `/state` hides the Telegram section and the pairing endpoints answer 404.
- **The one switch.** The Telegram installer step enables `TelegramIn` and `TelegramOut` only when `Included()` returns 1 and `TELEGRAM_BOT_TOKEN` is set. Otherwise it leaves them disabled and records `off` through `StatusMark.RecordTelegram`. With no token:
  - nothing calls the Telegram API;
  - the card keeps its not-set-up state, with no banner;
  - every other feature works.
- **No real bot.**
  - Every story runs against the CI Telegram mock. Never call `api.telegram.org`, never use or ask for a real token, and never read or print `.env`.
  - A real bot appears only in the Contest Planner's hands-on pass on the 0.1.1 candidate. Story 12.7's Telegram Web pass and its 20-run timings belong to that pass and go in the candidate's record. They are not merge criteria.
- **Nothing leaks.** No token, chat id, display name or pairing code may appear in a production setting, a `%Status` text, a log, the trace, an audit entry, a live event, a commit or the page. The token sits in the Bot API path (`/bot<token>/<method>`), so a request URL must never reach an error text or a log line. Tests search all of these for the dummy token, the codes and the chat identity, and must find none.
- **No lost or repeated messages.**
  - Confirm each processed update with the next offset, and skip an update id that was already handled, so a restart neither loses nor repeats one.
  - Retry a 429 after its `retry_after`.
  - A long poll always ends inside the compose file's 60-second stop grace period.
- **Text.** Send plain text with no parse mode, so model-written punctuation arrives exactly as written. Split a text longer than 4,096 characters at line breaks, and split a single longer line at the limit (DW-30: `Catalog.Render` caps no length).
- **Who gets processed.**
  - Only private-chat messages and button presses are processed. A group or channel message gets no reply and creates no message, row or audit entry.
  - An unpaired chat reaches no session and no model. No reply to it names a session, a person or any state.
  - A paired chat's text is the user's own turn. It is queued behind a running turn and never placed inside a tool result.
- **Notifications match the phone.** The paired chat gets the same text as the simulated phone for the same catalog key, with times in the instance's zone. A test compares the two key by key.
- **DW-295.** Telegram shows no check rows, so the Chat agent can't rely on rows shown under its reply there. "Is everything OK?" must still get a status in Telegram. The ledger routes this as rendering the reply's `CheckKey` and `CheckRows` on Telegram. The all-clear still comes only from code.
- **Approvals.**
  - A button carries the request's random `Ref` and the action, never a sequential number, and the first answer wins.
  - A late press, a press from another chat, or a press on an unknown or pre-reset request changes nothing.
- **Timing.** The page shows "Telegram paired" within 5 seconds of a valid `/start <code>`, and every other copy shows an approval's result within 5 seconds. CI checks both against the mock on every run.
- **DW-367 and DW-370 (Story 12.1 decides both).**
  - DW-367: CI's override sets the dummy token on every start, so CI can't yet express a start with no token.
  - DW-370: the mock's Bot API state is one global queue, and a reset restarts `update_id` at 1, which a live poller that keeps its offset would drop. `Test.Contract.Mock.TestTelegramBotApi` expects only its own three calls.

## Technical Decisions

- **Lane ownership.** Epic 12 is Lane A's and stays inside Lane A's files.
  - **Lane A owns:** `OcuTalon.Channel.Telegram` (`In`, `Out`), `OcuTalon.Install.Step.Telegram`, `web/src/app/rail/telegram-card/`, `web/e2e/demo-path/telegram-*.spec.ts`, the README's Telegram section and `ci/mock/scenarios/A/`.
  - **Lane B owns the session side these call:** `Data.Pairing`, `Data.StatusMark`, `Data.Delivery`, `SessionOps`, `AnswersIn`, `Notify`, `Conversation`, `Allowance`, `Trace`, the pairing endpoints, `/state`, the banners, the mock service code, the rest of `ci/`, the rest of `web/` and the rest of the README.
  - `TelegramIn` and `TelegramOut` already sit, disabled, in the production's Lane A region. Delete each class's `STUB` parameter when you build it, because the release check refuses an enabled stub.
- **Commands go through messages.**
  - `TelegramIn` is the business service. It submits state changes through `Commands.Submit` with origin `telegram`: `Pair` (accepted only from `telegram`) and `Unpair` for `/stop`. `SessionOps` returns the outcome, and `TelegramIn` sends the reply.
  - A button press goes synchronously through `AnswersIn.FromTelegram(ref, action, chatRef, .code, .slots)`, not as a command.
  - Arriving text can never approve, pair or change a setting by its content.
- **Identity.**
  - Production messages carry only `SessionRef` and `ChatRef`. The chat id and display name live only in the `Pairing` row, and the display name travels only to the session's own page, in `/state` and the `pairing` event.
  - Neither ever goes to the audit writer, log macros or step summaries. The Telegram items don't offer `ArchiveIO`.
- **Transport.**
  - Calls use `%Net.HttpRequest` in OcuTalon code, with one long-poll job per token, and the token comes only from the environment.
  - The API base URL and the SSL configuration are host settings that default to the public API. CI and the online demo override the base through `OCUTALON_TELEGRAM_API_BASE`. The online demo's IRIS holds only a dummy token, which its gateway swaps for the real one.
- **Rendering.**
  - Only `*Out` operations render, through `Msg.Catalog.Render(key, slots, "telegram")`. The one exception is `TelegramIn`'s `answerCallbackQuery` answer or alert, which it renders from `AnswersIn`'s result code and slots.
  - The keys already exist: `pairing.*`, `press.*` and `answered.*` in `Catalog.Core`, and the notices and results in `Catalog.Watch`.
  - Approve and Reject go only on kinds `incident` and `approval` that have an `ApprovalRef`.
  - An in-place edit finds its message with `Delivery.FindByApproval(approvalRef, "telegram", ownerRef)`. A Telegram row's channel message id is `<ChatRef>:<message_id>`.
  - `Notify` already routes these to `TelegramOut`: replies whose origin channel is `telegram`, `pairing` with a `ChatRef` (to `TelegramOut` alone), `allowance`, and the other kinds when the session is paired.
- **Trace.** A Telegram turn joins the session's daily thread. `TelegramIn` calls `Trace.Join` when the turn starts, and sets `..%SessionId` and `..%SuperSession` inside `OnProcessInput` before its first send.
- **Status and events.**
  - `StatusMonitor`, `/state` and the page's banner already turn a `telegramPaused` mark into the paused condition.
  - `SessionOps` is the only publisher of `pairing`, so `TelegramIn` publishes no live events.
- **CI mock.**
  - Lane A adds only scenario files under `ci/mock/scenarios/A/`: `match: {"telegram": "<method>"}`, with replies holding `status`, `headers`, `delayMs` and `body`. New mock behaviour is Lane B's work.
  - The mock serves `getMe`, `getUpdates`, `sendMessage`, `editMessageText` and `answerCallbackQuery`.
  - Tests queue updates and replies through `/_mock/telegram/updates` and `/_mock/telegram/replies`, read the recorded calls from `/_mock/telegram/calls`, and clear everything with `/_mock/telegram/reset`.
- **Test plumbing.**
  - Each `OcuTalon.Test.<Area>` must sit in exactly one shard in `ci/units.sh`, a Lane B file. `test-ci-config.sh` fails an area that is in no shard, and no Channel or Telegram area is listed today.
  - The README check, `docker/tests/test-readme.sh`, reads `Included()`'s body literally. While the body is the test-only one, the check refuses the word Telegram in the README and skips `#telegram`. Any other body requires a `#telegram` heading.
  - The CI budget stays at 35 minutes.

## UX & Interaction Patterns

- **Card states:**
  - **Not set up:** "Telegram not set up", with "How to set it up".
  - **Unpaired:**
    - a 132 px QR code, navy `#102A45` on white in both themes and never inverted;
    - the instruction line;
    - "Open in Telegram", whose name includes "(opens Telegram)";
    - "New code in {n} min".
  - **Paired:** "Telegram paired · {name}", with a ghost "Unpair" button named "Unpair Telegram". It acts on one press, with no confirmation.
  - **Paused:** "Telegram paused" and "Trying again at {time}". The QR code is withdrawn.
  - **Just unpaired:** "Telegram unpaired" for 5 seconds, then a fresh code.
- **Focus and the announcer.**
  - A code that refreshes keeps the user's input. If the old link had focus, focus moves to the new link.
  - After an unpair, focus goes to the Telegram heading.
  - The announcer reads "Telegram paired" or "Telegram unpaired".
- **Layout.**
  - From 1024 to 1279 px wide, the unpaired card moves to the top of the device column.
  - Narrower than 1024 px, it follows the guide.
- **Message style.**
  - Messages are plain text, with no Markdown, emoji, exclamation marks or arrows (use words), and lists are lines that lead with words.
  - Times are in the instance's zone, with "ET" on the online demo.
  - An answered status in message form ends with a period.
  - A refused press gets an alert that stays until dismissed.
  - Telegram and the simulated phone share every text. The exact strings come from the Message Catalog.
- **Existing card texts.** The card's two current texts live in Lane B's `web/src/app/rail/rail-view.ts`.

## Cross-Story Dependencies

- **Order inside the epic:**
  1. 12.1 sets up the switch and the mock scenarios.
  2. 12.2 polls and sends. Its `getMe` provides the `botUserName` that 12.3's link needs.
  3. 12.3 shows the code as a QR code.
  4. 12.4 pairs the chat and turns on `telegram-page.spec.ts`.
  5. 12.5 adds the polite replies and unpairing.
  6. 12.6 adds turns, notifications and `Delivery` rows through `TelegramOut`.
  7. 12.7 adds the buttons and the in-place edits, sets `Included()` to 1 and adds the README section in the same change, and turns on `telegram-approval.spec.ts`.
- **Story 12.7 waits on Epic 11, which hasn't merged.**
  - Its demo-path approval part needs Epic 11's end-to-end incident, approval and result path.
  - Its restart and upgrade checks extend Story 11.2's harness.
  - Its hands-on gate runs inside Story 11.5's release sequence.
- **The merge gate.** Epic 12 merges only once `v0.1.0` is tagged. No such tag is in this worktree yet.
- **Story 16.9 has merged,** so Story 12.6 can test against the real `TryConsume` instead of a double. Story 31.3 turns on 16.9's Telegram cases later, outside this epic.
- **Lane B files these stories reach.** Each one is a cross-lane edit under the one-owner rule, to settle when the story is planned:
  - `ci/compose.ci.yml` and `docker/tests/lib-live.sh` (DW-367);
  - `ci/mock/mock.mjs` and `OcuTalon.Test.Contract.Mock` (DW-370);
  - `ci/units.sh` (a test area for the Telegram classes);
  - `web/e2e-online/resume.spec.ts` (Story 16.3's check R2c, which 12.7 turns on);
  - `rail-view.ts` (the card's texts).
- **Gaps:**
  - Gap (12.2): no SSL configuration for the Telegram API exists, and `OcuTalon.Install.Step.SSL` is still an empty stub.
  - Gap (12.7): Story 11.2's upgrade-and-restart harness is not in the code. `release/` holds only `standalone-bridge.sh`.
  - Gap (12.7): Story 11.5's release sequence, its hands-on gate and `release/records/0.1.1/` don't exist yet.
  - Gap (12.7): next to R2c in `web/e2e-online/resume.spec.ts`, `R2b: /state returns the fixture pairing` is still a `notBuilt` placeholder owned by Story 10.3, which has merged.
