# Epic 12 Context: Approve from your own phone with Telegram

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Telegram puts OcuTalon on the user's own phone. A user scans the page's QR code to pair a private Telegram chat with their session; the chat then carries turns, notifications, reminders and approval requests with inline Approve and Reject buttons, and every copy of an approval shows who answered first. Bad codes, a bare `/start` and strangers get polite replies that link nothing and reveal nothing. OcuTalon runs fully without a bot token, and pauses for five minutes when another process polls the same bot. Lane A builds the channel on the session side Lane B built and left switched off. Telegram ships in 1.0.0, the first release (0.1.0 and 0.1.1 are not cut); Epic 12 merges when done, with no tag gate, and its merge is what lets the step epics start.

## Stories

- Story 12.1: Telegram stays off without a token, and CI mocks the Telegram API
- Story 12.2: OcuTalon polls and writes to its own bot, and pauses when another process polls it
- Story 12.8: The page shows when Telegram is paused, and when it will try again
- Story 12.3: The Telegram card shows a fresh pairing code as a QR code
- Story 12.4: A valid code pairs the chat with the session
- Story 12.5: Bad codes, a bare start command and unpairing get polite answers
- Story 12.6: Chat and get notifications in the paired Telegram chat
- Story 12.7: Approve or reject from Telegram, and every copy shows who answered

## Requirements & Constraints

- **Off until 12.7.** `OcuTalon.Channel.Telegram.In.Included()` returns 0 until Story 12.7 sets it to 1; while 0, `/state` hides the Telegram section and the pairing endpoints answer 404, and tests turn Telegram on through the test seam `^OcuTalonTest("TelegramIncluded")`. The installer's Telegram step is the one switch: it enables `TelegramIn` and `TelegramOut` only when `Included()` is 1 and `TELEGRAM_BOT_TOKEN` is set, otherwise leaves them disabled and records `off`.
- **No real bot in this epic.** Every story runs against the CI mock with a dummy token. The real-device pass (Telegram Web, the verified TLS handshake with the real API through `OcuTalonClient`, the 20 timed pairings and approvals) moved to Story 38.3 on `release/1.0.0-rc1`; Story 12.7 keeps only what is built and proved on the mock and carries "Moved to Story 38.3" markers.
- **Secrets and identity.** The bot token comes only from the environment and never reaches a setting, `%Status` text, log, trace, audit entry, live event or the page. Chat id and display name live only in the chat's `Pairing` row; messages refer to a chat by `ChatRef` and to a person by `SessionRef`; the display name goes only to the session's own page. Pairing codes are stored only as hashes. A chat has at most one live pairing.
- **Who is heard.** Only private-chat messages and button presses are processed; groups and channels get nothing. An unpaired chat reaches no session or model, and no reply to it reveals any session, name or state. A paired chat's text is the user's own turn (never inside a tool result).
- **Approvals (12.7).** Buttons carry the request's unguessable `Ref` and the action, never a sequential number; the first answer on any channel wins. A late press, a press from a chat that isn't the session's paired chat, or one for an unknown or pre-reset request changes nothing and gets an alert that stays until dismissed. Every other copy (web chat card, rail row, simulated phone) shows the result within 5 s, checked against the mock on every CI run.
- **Text.** Plain text, no parse mode, no emoji or arrows; over 4,096 characters splits at line breaks; every text comes from the Message Catalog, with times in the instance's zone.

## Technical Decisions

- **Ownership.** Lane A owns `OcuTalon.Channel.Telegram` (`TelegramIn`, `TelegramOut`), `web/src/app/rail/telegram-card/`, `web/e2e/demo-path/telegram-*.spec.ts`, the README's Telegram section (`#telegram`) and `ci/mock/scenarios/A/`. Lane B owns the session side; don't edit it: `SessionOps` pairing, `Data.Pairing` (`RecordChat`, `HashCode`, `TakeReplySlot`), `Data.StatusMark`, `Data.Delivery`, `Data.Public.Settings`, `AnswersIn`'s Telegram entry and result codes, `Notify`, `Allowance`, `Trace`, the pairing endpoints, `/state`'s Telegram block and the mock's Bot API endpoints. Lane A adds mock scenario files only.
- **Button presses.** `TelegramIn` calls `AnswersIn` synchronously with channel `telegram`, the approval `Ref`, the action and the press's `ChatRef` (never a chat id). `AnswersIn` resolves the session from the chat's live `Pairing` row and returns `approved` (with the affected count and item noun from the stored dry run), `rejected`, `already_answered` (winning action, channel, time), `expired` (expiry time), `not_paired`, `not_visible`, `not_allowed` (step 6, out of scope) or `unknown`. `TelegramIn` answers the press with `answerCallbackQuery`, rendered through `Msg.Catalog.Render` from that code and its slots: the one exception to "only `*Out` operations render".
- **Edit in place.** `TelegramOut` records each approval message's `Delivery` row with the approval `Ref` (`Delivery.Record`; channel message id `<ChatRef>:<message_id>`). On an `answered` notification (any channel, or expiry) it finds the message with `Delivery.FindByApproval(approvalRef, channel, ownerRef)`, removes the buttons and makes the last line the message-form status; a result follows as a new message. Buttons appear only on kinds `incident` and `approval` whose `ApprovalRef` is set.
- **Audit.** `Bridge.Approval.Answer` records channel `telegram`, the session's IRIS user and the time; audit entries carry no Telegram identity.
- **Public key for the splash.** The online demo's splash may read only `Data.Public.Settings`' fixed keys, so the splash's Telegram lines need a public key `telegramIncluded`, written from `Included()` by Lane A's `Install.Step.Public` at every online-demo start. Adding a key amends AD-19, which is the owner's: 12.7's spec gate must raise the mechanism as a `## Clarification Needed` before building it. The catalog keys `splash.telegramLine` and `splash.limitLine` keep their text for this story.

## UX & Interaction Patterns

- Telegram approval notice: rendered from the notification's catalog key, with word-labelled inline "Approve" and "Reject" buttons; fixture first notice "50 orders failed since 14:12 ET. The partner changed its date format. I can repair and resend all 50. Approve?", then the dry run and "Details and trace: on your OcuTalon page."
- Press answers: "Approved. Repairing and resending {count} {item noun}." or "Rejected. Nothing was changed."; after a rejection the chat also gets "Fix rejected. Nothing was changed. The incident stays open on your OcuTalon page."
- Edited status lines: "Approved from Telegram at 14:15 ET." or "Expired at {time}. Nothing was changed."; page copies read "Approved from Telegram at 14:15". Results use the catalog's result text ("All 50 orders went through." or a partial result).
- Refused-press alerts: "Already answered: approved from the web chat at {time}.", the expired status, "Only the paired chat can answer this request." (`not_paired`, `not_visible`), "That request is no longer available." (`unknown`).
- With Telegram included, the splash shows "Have Telegram? You can scan a QR code inside to get the notices on your own phone." and "Each session can send {limit} messages an hour in the chat or Telegram.", and `banner.allowance` says "chat or Telegram"; with `Included()` 0 neither mentions Telegram.

## Cross-Story Dependencies

- Stories 12.1 to 12.6 and 12.8 are done; Story 12.7 remains, and its waits (Epic 11's merge for Story 11.2's harness; Epic 16 for Story 16.3's check) are met.
- In one change Story 12.7 sets `Included()` to 1 and adds the README's `#telegram` section (create a bot with BotFather, turn groups off, set `TELEGRAM_BOT_TOKEN` in `.env` and restart, one bot per OcuTalon), which the card's "How to set it up" and the banner's "Set up a bot" links open; Story 10.2's README link check covers it from then on. The same change appends "You can approve it in Telegram on your phone, without a laptop or the Management Portal." to the first item of the README's "What you can use it for" (Story 10.4).
- 12.7 extends Story 11.2's upgrade and restart harness: the restart check includes a pairing through the mock from 1.0.0, the upgrade check from the first release after 1.0.0, and the pairing still gets notifications afterwards.
- 12.7 turns on Story 16.3's check that the rail's Telegram card shows a resumed session's pairing, and the skipped approval part of the REL-2 `telegram-*.spec.ts` (press Approve, see the answered status on the chat card and phone, the edited message and the result in the chat, and the audit entry with channel Telegram and no Telegram identity).
- CI mock caveats that bite once `Included()` is 1: the CI override sets the dummy token for every start, so a no-token start can't be expressed (DW-367); the mock keeps one global Bot API state for every client (DW-370).
- Downstream: Epics 33, 34, 17 and 18 start once Epic 12 merges (and merge only once `release/1.0.0-rc1` exists); Stories 31.3 and 31.4 turn on later Telegram cases; Story 38.3 runs the real-device pass; Story 10.5's Telegram row depends on Epic 12 having merged.
