# Epic 12 Context: Approve from your own phone with Telegram

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Telegram puts the demo on the user's own phone. A user scans the page's QR code to pair their private Telegram chat with their OcuTalon session; the chat then carries turns, notifications, reminders and approval requests with Approve and Reject buttons, and every copy of an approval shows who answered first. Bad codes, a bare `/start` and strangers get polite replies that link nothing and reveal nothing. OcuTalon runs fully without a bot token, and when another process polls the same bot it pauses for five minutes and the page says so. Lane A builds the channel on the session side that Lane B built and left switched off. Telegram ships in 1.0.0, the first release (and reaches the online demo with that update). Epic 12 merges when done, with no tag gate.

## Stories

- Story 12.1: Telegram stays off without a token, and CI mocks the Telegram API (done)
- Story 12.2: OcuTalon polls and writes to its own bot, and pauses when another process polls it (done)
- Story 12.8: The page shows when Telegram is paused, and when it will try again (split from 12.2; next)
- Story 12.3: The Telegram card shows a fresh pairing code as a QR code
- Story 12.4: A valid code pairs the chat with the session
- Story 12.5: Bad codes, a bare start command and unpairing get polite answers
- Story 12.6: Chat and get notifications in the paired Telegram chat
- Story 12.7: Approve or reject from Telegram, and every copy shows who answered (waits on Epic 11)

## Requirements & Constraints

- **Off until Story 12.7.** `OcuTalon.Channel.Telegram.In.Included()` returns 0 until 12.7 sets it to 1. While it is 0, `/state` hides the Telegram section and the pairing endpoints answer 404. Earlier stories turn Telegram on only in tests, through `^OcuTalonTest("TelegramIncluded")`. The installer's Telegram step is the one switch: it enables both items only when `Included()` is 1 and `TELEGRAM_BOT_TOKEN` is set, and otherwise leaves them disabled and records `off`.
- **No real bot.** Every story runs against the CI mock with a dummy token. Never call the public Bot API or use a real token. The real-bot pass (hands-on use, the TLS handshake with the real API, the 20 timed runs) is the owner's Story 38.3 on `release/1.0.0-rc1`, outside this epic.
- **Nothing leaks.** Tests search for each of these:
  - The token comes only from the environment. It never appears in a production setting, a `%Status` text, a log, the trace, an audit entry, a live event or the page. It sits in the request path, so a request URL must never reach an error text or a log.
  - The chat id and display name live only in the chat's `Pairing` row. Messages refer to a chat only by `ChatRef` and to a person only by `SessionRef`. The display name goes only to the session's own page.
  - A pairing code is stored only as its hash, and never appears in a message, header, log, live event or audit entry.
  - A chat has at most one live pairing.
- **Who is heard.**
  - Only private-chat messages and button presses are processed. Group and channel traffic gets no reply and creates no message, row or audit entry.
  - An unpaired chat reaches no session and no model. Its replies name no session, person or state, and its other messages get at most one reply a minute.
  - Arriving text never approves, pairs or changes a setting. A paired chat's text is the user's own turn: it queues behind a running turn and never goes inside a tool result.
- **Text.** Plain text with no parse mode. Over 4,096 characters splits at line breaks, and a single over-long line at the limit. Each notice is identical to the simulated phone's for the same catalog key, with times in the instance's zone.
- **Approvals.** Buttons carry the request's unguessable `Ref` and the action, never a sequential number. The first answer on any channel wins. A press that is late, from another chat, for an unknown request or from before a reset changes nothing and gets an alert.
- **Timing.** "Telegram paired" shows within 5 s of a valid code, and every other copy shows an approval's result within 5 s. CI checks both against the mock on every run.
- **Polling.** Later stories keep 12.2's guarantees: one poller per token, no lost or repeated update across a restart, a long poll inside the 60 s stop grace.

## Technical Decisions

- **Built in Story 12.2:** `TelegramIn` (short long poller, kept offset, the 409 pause through the `telegramPaused` mark, its state through `StatusMark.RecordTelegram`: `on` with the bot name from `getMe`, `rejected` or `off`); `TelegramOut` (plain text, split at 4,096, retry after a 429); the shared Bot API client `OcuTalon.Channel.Telegram.Api`; the `ApiBase` rows written at every start from `OCUTALON_TELEGRAM_API_BASE`; and the client SSL configuration `OcuTalonClient` (verifies the peer, no secret; an `http://` override such as the CI mock or the demo's gateway stays plain HTTP).
- **Lane footprint.**
  - Epic 12 stays in Lane A's files: `OcuTalon.Channel.Telegram`, `web/src/app/rail/telegram-card/`, `web/e2e/demo-path/telegram-*.spec.ts`, the README's Telegram section and `ci/mock/scenarios/A/`.
  - Lane B owns the session side; don't edit it: `SessionOps` pairing and unpairing; `Data.Pairing` (`RecordChat`, `HashCode`, `TakeReplySlot`), `Data.StatusMark`, `Data.Delivery`; `AnswersIn`'s Telegram entry and result codes; `Notify`, `Allowance.TryConsume`, `Trace.Join`; the pairing endpoints (the code endpoint answers 409 while Telegram isn't `on` or is paused) and `/state`'s Telegram block; the banners and every other `web/` file outside the card folder; the mock's Bot API endpoints. Lane A extends the mock only with scenario files; new mock behaviour is a Lane B ask.
- **Everything is a message.** `TelegramIn` submits pair and unpair (`/stop`) through `Commands.Submit` with origin `telegram`. `SessionOps` returns the outcome, and `TelegramIn` sends the reply as a `pairing` `Notification` by `ChatRef`, which `Notify` routes to `TelegramOut` alone. A button press calls `AnswersIn` synchronously with the press's `ChatRef`.
- **Rendering and routing.** Only `*Out` operations render, through `Msg.Catalog.Render(key, slots, "telegram")`; the one exception is `TelegramIn`'s `answerCallbackQuery`, rendered from `AnswersIn`'s result code and slots. Never hard-code Telegram text. Buttons appear only on kinds `incident` and `approval` that carry an `ApprovalRef`. Notifications go to the web chat, the simulated phone (demo mode) and the paired chat; kind `allowance` to the web chat and the paired chat only. `TelegramOut` records `Delivery` rows with message id `<ChatRef>:<message_id>` and edits in place via `Delivery.FindByApproval`.
- **Turns.** `TelegramIn` calls `Allowance.TryConsume` before queueing (on a refusal it queues nothing, and sends the allowance notice only on the first refusal), joins the session's daily thread with `Trace.Join`, sets `%SessionId` and `%SuperSession` in `OnProcessInput` before its first send, and sends `Conversation` an `Item` with channel `telegram` and provenance `user`.
- **Tests and CI.** `OcuTalon.Test.Channel.*` classes run as their own CI unit, `shard:lane-a@Channel`, in the `production` group. Pairing audit entries carry no Telegram identity; tests read them back by time range, with polling. CI keeps its 35-minute budget.

## UX & Interaction Patterns

- **Card states:** not set up ("Telegram not set up", "How to set it up", no banner); unpaired (a 132 px QR code, navy on white in both themes, the scan instruction, "Open in Telegram" named with "(opens Telegram)", "New code in {n} min"); paired ("Telegram paired · {name}", a one-press "Unpair" button named "Unpair Telegram"); paused ("Telegram paused", "Trying again at {time}", QR code withdrawn); just unpaired ("Telegram unpaired" for 5 s, then a new code).
- **Banner.** The "bot in use" warning banner has a "Set up a bot" README link, and appears and clears within one live update, in the fixed stacking order of banners.
- **Focus and announcements.** A refreshed code keeps the user's input, and focus moves to the new link if the old one had it. After an unpair, focus goes to the Telegram heading. The one polite announcer reads "Telegram paired" or "Telegram unpaired".
- **Telegram messages.** Plain text: no Markdown, emoji or arrows. Buttons are labelled with words, and list lines start with words. An answered message loses its buttons and its last line becomes the status. A refused press gets an alert that stays until dismissed. Exact texts come from the Message Catalog.

## Cross-Story Dependencies

- **Order:** 12.8, 12.3, 12.4, 12.5, 12.6, then 12.7 once Epic 11 merges.
  - 12.8 shows 12.2's pause (the banner and the card's paused state). It may change only the card folder and the Telegram spec files; any other `web/` edit is Lane B's and needs an orchestrator ruling.
  - 12.3's link uses the bot name 12.2 records.
  - 12.4 to 12.6 build on 12.2's private-chat handler and `TelegramOut` sending by `ChatRef`.
  - 12.4 owns DW-486: `TelegramIn` calls `Pairing.RecordChat(chatId, "")` for every private update, which would blank a stored display name. Fix it on Epic 12's side if possible (pass the update's own name, or skip an empty one); `Data/Pairing.cls` is Lane B's and contended with Epic 11.
  - 12.6 needs Epics 5, 7 and 8 (merged) and tests against the real `TryConsume` (Story 16.9 merged). It resolves DW-30 (message length) and DW-295 (a status answer on Telegram, which shows no check rows).
- **Story 12.7** keeps everything built and proved on the CI mock and still waits on Epic 11's merge.
  - It extends Story 11.2's upgrade-and-restart harness: the restart check includes a pairing through the mock from 1.0.0, and the upgrade check from the first release after 1.0.0.
  - It turns on Story 16.3's Telegram-card check (Epic 16 has merged).
  - In one change it sets `Included()` to 1, adds the README's `#telegram` section (BotFather, groups off, `TELEGRAM_BOT_TOKEN` in `.env` and a restart, one bot per OcuTalon), which the card's and banner's links open, and appends "You can approve it in Telegram on your phone, without a laptop or the Management Portal." to the first item of the README's "What you can use it for" section (Story 10.4, merged). Until then the README checks forbid any Telegram claim.
  - Its real-device pass is Story 38.3's; any release record goes under `release/records/1.0.0/`.
- **CI mock.** The mock keeps a single Bot API state for every client (DW-370; DW-421 escalated as a Lane B mock ask), and the CI override sets the dummy token for every start, so a no-token start can't be expressed once `Included()` is 1 (DW-367). Both start to matter at 12.7, when `TelegramIn` polls at every CI start.
- **Downstream.** Step epics 33, 34, 17 and 18 start once Epic 12 has merged (they merge only once `release/1.0.0-rc1` exists). Epic 38, the 1.0.0 check, depends on every 1.0.0-scope epic, this one included.
