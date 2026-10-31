# Epic 12 Context: Approve from your own phone with Telegram

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Telegram puts the demo on the user's own phone. A user scans the page's QR code to pair their private Telegram chat with their OcuTalon session. From then on the chat carries turns, notifications, reminders and approval requests with Approve and Reject buttons, and every copy of an approval shows who answered first. Codes that don't work, a bare `/start` and strangers get polite replies that link nothing and reveal nothing. OcuTalon runs fully without a bot token. When another process polls the same bot, OcuTalon pauses for five minutes and the page says so. Lane A builds the channel on the session side that Lane B built and left switched off. It ships as 0.1.1, the release right after 0.1.0, and reaches the online demo with the 1.0.0 update. Its merge also unblocks step 2, because step epics start only once Epic 12 has merged and v0.1.0 is tagged.

## Stories

- Story 12.1: Telegram stays off without a token, and CI mocks the Telegram API (done)
- Story 12.2: OcuTalon polls and writes to its own bot, and pauses when another process polls it (ready for development)
- Story 12.8: The page shows when Telegram is paused, and when it will try again (split from 12.2; next after it)
- Story 12.3: The Telegram card shows a fresh pairing code as a QR code
- Story 12.4: A valid code pairs the chat with the session
- Story 12.5: Bad codes, a bare start command and unpairing get polite answers
- Story 12.6: Chat and get notifications in the paired Telegram chat
- Story 12.7: Approve or reject from Telegram, and every copy shows who answered (waits on Epic 11)

## Requirements & Constraints

- **Off until 0.1.1.** No 0.1.0 candidate may contain Telegram.
  - `OcuTalon.Channel.Telegram.In.Included()` returns 0 until Story 12.7 makes it return 1. While it is 0, `/state` hides the Telegram section and the pairing endpoints answer 404.
  - Earlier stories turn Telegram on only in tests, through `^OcuTalonTest("TelegramIncluded")`.
  - The installer's Telegram step is the one switch. It enables both items only when `Included()` is 1 and `TELEGRAM_BOT_TOKEN` is set. Otherwise it leaves them disabled and records `off`.
- **No real bot.** Every story runs against the CI mock with a dummy token. Never call the public Bot API or use a real token. A real bot is used only in the Contest Planner's hands-on pass on the 0.1.1 candidate.
- **Nothing leaks.** Tests search for each of these:
  - The token comes only from the environment. It never appears in a production setting, a `%Status` text, a log, the trace, an audit entry, a live event or the page. It sits in the request path, so a request URL must never reach an error text or a log.
  - The chat id and display name live only in the chat's `Pairing` row. Production messages refer to a chat only by `ChatRef` and to a person only by `SessionRef`. The display name goes only to the session's own page.
  - A pairing code is stored only as its hash. It never appears in a message, header, log, live event or audit entry.
  - A chat has at most one live pairing.
- **No lost or repeated updates.**
  - One poller per token. Each processed update is confirmed with the next offset, and an id already handled is skipped, so a restart neither loses nor repeats an update.
  - A long poll ends inside the 60-second stop grace period. A 429 waits for `retry_after`.
  - A 409 pauses polling for 5 minutes. After that, success clears the pause and another 409 starts a new one.
- **Who is heard.**
  - Only private-chat messages and button presses are processed. Group and channel traffic gets no reply and creates no message, row or audit entry.
  - An unpaired chat reaches no session and no model. Its replies name no session, person or state, and its other messages get at most one reply a minute.
  - The content of arriving text never approves, pairs or changes a setting.
  - A paired chat's text is the user's own turn. It queues behind a running turn and never goes inside a tool result.
- **Text.**
  - Plain text with no parse mode, so model-written punctuation arrives exactly as written.
  - A text over 4,096 characters splits at line breaks. A single line longer than the limit splits at the limit.
  - Each notice is identical to the simulated phone's for the same catalog key, with times in the instance's zone.
- **Approvals.**
  - Buttons carry the request's unguessable `Ref` and the action, never a sequential number.
  - The first answer on any channel wins.
  - A press that is late, from another chat, for an unknown request or from before a reset changes nothing and gets an alert.
- **Timing.**
  - "Telegram paired" shows within 5 s of a valid code, and every other copy shows an approval's result within 5 s. CI checks both against the mock on every run.
  - The 19-of-20 timings over real networks are recorded at the 0.1.1 hands-on gate. They are not a merge criterion.
- **TLS.**
  - Outbound HTTPS goes through one general client SSL configuration, `OcuTalonClient`. It holds no secret and verifies the peer, and the later email story reuses it.
  - An `http://` override (the CI mock, the demo's gateway) stays plain HTTP.
  - The first verified handshake with the real API is recorded in the 0.1.1 hands-on pass.

## Technical Decisions

- **Lane footprint.**
  - Epic 12 stays in Lane A's files: `OcuTalon.Channel.Telegram` (`TelegramIn`, `TelegramOut`), `web/src/app/rail/telegram-card/`, `web/e2e/demo-path/telegram-*.spec.ts`, the README's Telegram section and `ci/mock/scenarios/A/`.
  - Lane B owns the session side these stories call; don't edit it:
    - `SessionOps` pairing and unpairing, with its notices to a dropped chat
    - `Data.Pairing` (`RecordChat`, `HashCode`, `TakeReplySlot`), `Data.StatusMark` and `Data.Delivery`
    - `AnswersIn`'s Telegram entry and its result codes
    - `Notify`, `Allowance.TryConsume` and `Trace.Join`
    - the pairing endpoints and `/state`'s Telegram block
    - the banners and every other `web/` file outside the card folder
    - the mock's Bot API endpoints
  - Lane A extends the mock only by adding scenario files. Any new mock behaviour is a Lane B ask.
- **Everything is a message.**
  - `TelegramIn` submits pair and unpair (`/stop`) through `Commands.Submit` with origin `telegram`.
  - `SessionOps` returns the outcome, and `TelegramIn` sends the reply as a `pairing` `Notification` by `ChatRef`. `Notify` routes it to `TelegramOut` alone.
  - A button press calls `AnswersIn` synchronously with the press's `ChatRef`.
  - Only business operations send channel traffic.
- **State.**
  - `TelegramIn` records its state through `StatusMark.RecordTelegram`: `on` with the bot's user name from `getMe`, `rejected`, or `off`.
  - It records a pause through `StatusMark.Record("telegramPaused", until)`. `StatusMonitor` and `/state` turn that into the `telegramPaused` condition.
  - The code endpoint answers 409 while Telegram isn't `on` or is paused.
  - The kept offset lives at `$$$EnsStaticAppData("TelegramIn", "offset")`.
- **Transport.**
  - Calls use `%Net.HttpRequest` in OcuTalon code.
  - The API base URL and the SSL configuration are host settings. CI points `OCUTALON_TELEGRAM_API_BASE` at the mock, and the demo's gateway swaps its dummy token in the path for the real one.
- **Rendering and routing.**
  - Only `*Out` operations render, through `Msg.Catalog.Render(key, slots, "telegram")`. The one exception is `TelegramIn`'s `answerCallbackQuery`, which it renders from `AnswersIn`'s result code and slots. Never hard-code Telegram text.
  - Buttons appear only on kinds `incident` and `approval` that carry an `ApprovalRef`.
  - Notifications go to the web chat, the simulated phone (in demo mode) and the paired chat. Kind `allowance` goes to the web chat and the paired chat only.
  - `TelegramOut` records `Delivery` rows, with the message id as `<ChatRef>:<message_id>`. It edits a message in place by finding it with `Delivery.FindByApproval`.
- **Turns.** For each turn, `TelegramIn`:
  1. calls `Allowance.TryConsume` before queueing. On a refusal it queues nothing, and it sends the allowance notice only on the first refusal;
  2. joins the session's daily thread with `Trace.Join`, then sets `%SessionId` and `%SuperSession` in `OnProcessInput` before its first send;
  3. sends `Conversation` an `Item` with channel `telegram` and provenance `user`.
- **Tests and CI.**
  - New `OcuTalon.Test.Channel.*` classes join `lane-a`, whose newer areas run in `shards-2`.
  - Pairing audit entries carry no Telegram identity. Tests read them back by time range, with polling.
  - CI keeps its 35-minute budget.

## UX & Interaction Patterns

- **Card states:**
  - **Not set up:** "Telegram not set up" and "How to set it up", with no banner.
  - **Unpaired:**
    - a 132 px QR code, navy on white in both themes
    - the scan instruction
    - "Open in Telegram", named with "(opens Telegram)"
    - "New code in {n} min"
  - **Paired:** "Telegram paired · {name}" and a one-press "Unpair" button named "Unpair Telegram".
  - **Paused:** "Telegram paused" and "Trying again at {time}", with the QR code withdrawn.
  - **Just unpaired:** "Telegram unpaired" for 5 s, then a new code.
- **Banner.** The "bot in use" warning banner has a "Set up a bot" README link. It appears and clears within one live update, in the fixed stacking order of banners.
- **Focus and announcements.**
  - A refreshed code keeps the user's input. Focus moves to the new link if the old link had it.
  - After an unpair, focus goes to the Telegram heading.
  - The one polite announcer reads "Telegram paired" or "Telegram unpaired".
- **Telegram messages.**
  - Plain text only: no Markdown, no emoji, no arrows.
  - Buttons are labelled with words, and list lines start with words.
  - An answered message loses its buttons, and its last line becomes the status.
  - A refused press gets an alert that stays until dismissed.
  - Exact texts come from the Message Catalog.

## Cross-Story Dependencies

- **Order:** 12.1, 12.2, 12.8, 12.3, 12.4, 12.5, 12.6, 12.7.
  - 12.2 owns DW-422 (the kept offset node).
  - 12.8 shows 12.2's pause. It may change only the card folder and the Telegram spec files. Any other `web/` edit is Lane B's and needs an orchestrator ruling.
  - 12.3's link uses the bot name that 12.2 records.
  - 12.4 to 12.6 build on 12.2's private-chat handler and on `TelegramOut` sending by `ChatRef`.
  - 12.6 needs Epics 5, 7 and 8, all merged, and tests against the real `TryConsume` now that Story 16.9 has merged. It also resolves DW-30 (message length) and DW-295 (a status answer on Telegram, which shows no check rows).
- **Story 12.7 waits on Epic 11,** which hasn't merged.
  - It extends Story 11.2's upgrade-and-restart harness.
  - It runs its hands-on gate inside Story 11.5's release sequence and records it in `release/records/0.1.1/rc<n>.md`.
  - It turns on Story 16.3's Telegram-card check (Epic 16 has merged).
  - In one change, it sets `Included()` to 1, adds the README's `#telegram` section, and appends the sentence that Story 10.4 reserves for the first "What you can use it for" item. Until then, the README checks forbid any Telegram claim.
- **CI mock.** The mock keeps a single Bot API state for every client. DW-421 has escalated this as a Lane B mock ask. It starts to matter at 12.7, when `TelegramIn` polls at every CI start.
- **Merge gate.**
  - Epic 12 merges only once `v0.1.0` is tagged, and no such tag exists yet.
  - Step epics 33, 34, 17 and 18 start after Epic 12 merges, and merge only after v0.1.1.
