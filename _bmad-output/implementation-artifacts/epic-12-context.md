# Epic 12 Context: Approve from your own phone with Telegram

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Telegram puts OcuTalon on the user's own phone. A user scans the page's QR code to pair a private Telegram chat with their session; the chat then carries turns, notifications, reminders and approval requests with inline Approve and Reject buttons, and every copy of an approval shows who answered first. Bad codes, a bare `/start` and strangers get polite replies that link nothing and reveal nothing. OcuTalon runs fully without a bot token, and pauses for five minutes when another process polls the same bot. Lane A builds the channel on the session side Lane B built and left switched off; the last story turns the switch on, because no released Telegram notice may lack Approve and Reject. Telegram ships in 1.0.0, the first release (0.1.0 and 0.1.1 are not cut); Epic 12 merges when done, with no tag gate, and its merge is what lets the step epics start.

## Stories

- Story 12.1: Telegram stays off without a token, and CI mocks the Telegram API
- Story 12.2: OcuTalon polls and writes to its own bot, and pauses when another process polls it
- Story 12.8: The page shows when Telegram is paused, and when it will try again
- Story 12.3: The Telegram card shows a fresh pairing code as a QR code
- Story 12.4: A valid code pairs the chat with the session
- Story 12.5: Bad codes, a bare start command and unpairing get polite answers
- Story 12.6: Chat and get notifications in the paired Telegram chat
- Story 12.7: Approve or reject from Telegram, and every copy shows who answered
- Story 12.9: Telegram is included

## Requirements & Constraints

- **The switch is Story 12.9.** `OcuTalon.Channel.Telegram.In.Included()` still returns 0 except through the test-only seam `^OcuTalonTest("TelegramIncluded")` (set only by test classes, never in the judges' install). While 0, `/state` hides the Telegram section and the pairing endpoints answer 404. Story 12.9 makes it return 1, so `/state` shows the rail's Telegram card and the pairing endpoints answer. The installer's Telegram step stays the one switch: it enables `TelegramIn` and `TelegramOut` only when `Included()` is 1 and `TELEGRAM_BOT_TOKEN` is set, otherwise leaves them disabled and records `off`.
- **README in the same change.** The switch lands in the same change as the README's Telegram section (heading `## Telegram`, so its anchor is `#telegram`): create a bot with BotFather, turn groups off for it, set `TELEGRAM_BOT_TOKEN` in `.env` and restart, and each OcuTalon needs its own bot. The card's "How to set it up" link and the banner's "Set up a bot" link open it, so no link points at a missing section; the README link check covers it from then on. The same change appends "You can approve it in Telegram on your phone, without a laptop or the Management Portal." to the first item of "What you can use it for" (adding to the line, not rewriting it).
- **No real bot in this epic.** Every story runs against the CI mock with a dummy token. The real-device pass (Telegram Web, the verified TLS handshake through `OcuTalonClient`, the 20 timed pairings and approvals) is Story 38.3's, on `release/1.0.0-rc1`.
- **Secrets and identity.** The bot token comes only from the environment and never reaches a setting, `%Status` text, log, trace, audit entry, live event or the page. Chat id and display name live only in the chat's `Pairing` row; messages refer to a chat by `ChatRef` and a person by `SessionRef`; the display name goes only to the session's own page. Pairing codes are stored only as hashes; a chat has at most one live pairing. Audit entries carry no Telegram identity.
- **Who is heard.** Only private-chat messages and button presses are processed. An unpaired chat reaches no session or model, and no reply to it reveals any session, name or state.
- **Approvals.** Buttons carry the request's unguessable `Ref` and the action; the first answer on any channel wins; every other copy shows the result within 5 s, checked against the mock on every CI run.
- **Text.** Plain text, no parse mode, no emoji; every text comes from the Message Catalog, with times in the instance's zone.

## Technical Decisions

- **Ownership.** Lane A owns `OcuTalon.Channel.Telegram` (`TelegramIn`, `TelegramOut`), the installer's Telegram and `Public` steps, `web/src/app/rail/telegram-card/`, `web/e2e/demo-path/telegram-*.spec.ts`, the README's Telegram section and `ci/mock/scenarios/A/`. Lane B owns the session side: `SessionOps` pairing, `Data.Pairing`, `Data.StatusMark`, `Data.Delivery`, `Data.Public.Settings`, `AnswersIn`, `Notify`, `Allowance`, the pairing endpoints, `/state`'s Telegram block and the mock's Bot API endpoints.
- **The public key `telegramIncluded` (AD-19, amended for Story 12.9, U-219 option (a')).** A fixed public key, `1` only when `Included()` returns 1 and a bot token is set on that start, otherwise `0`. `OcuTalon.Install.Step.Public` writes it on every start (structural value, local and online demo alike) through the `Data.Public.Settings` accessor, the only reader and writer of public values (Lane B's; `Set` takes fixed keys only); only the online demo's splash reads it. The splash's Telegram line, the allowance line's "or Telegram" and `banner.allowance`'s "chat or Telegram" follow this key, not `Included()` alone. The online demo thus keeps Telegram off by host configuration (no bot token in its IRIS container) with a truthful splash, and turns on at the next start once a token is set, with no code change.
- **Banners on the demo.** `banner.allowance` (DW-501) and `banner.resetSoon`, which names Telegram pairing (DW-506), are owned by Story 12.9. Any new or changed banner wording goes to the Contest Planner as a veto item.
- **Approval path (built in 12.7).** `TelegramIn` hands a press to `AnswersIn` synchronously (channel `telegram`, approval `Ref`, action, the press's `ChatRef`) and answers with `answerCallbackQuery` rendered from the returned result code; `TelegramOut` records each request message's `Delivery` row with the approval `Ref` and, on an `answered` notification, finds it with `Delivery.FindByApproval`, removes the buttons and edits the status line in place. The stored text of a request message is redacted and identity-free.

## UX & Interaction Patterns

- With the key `1`, the splash shows "Have Telegram? You can scan a QR code inside to get the notices on your own phone." and "Each session can send {limit} messages an hour in the chat or Telegram." (`splash.limitLine`), and `banner.allowance` says "chat or Telegram"; with the key `0` none of these mention Telegram.
- Approval texts already built: buttons "Approve" and "Reject"; press answers "Approved. Repairing and resending {count} {item noun}." or "Rejected. Nothing was changed."; edited status "Approved from Telegram at 14:15 ET." or "Expired at {time}. Nothing was changed."; page copies "Approved from Telegram at 14:15"; results "All 50 orders went through." or a partial result.

## Cross-Story Dependencies

- Stories 12.1 to 12.8 are done; Story 12.9 is next and depends on Story 12.7 (the buttons, presses and edit in place). It does not depend on Story 31.4, which the owner deferred to after the v1.0.0 tag.
- Story 12.9 extends Story 11.2's upgrade and restart harness: the restart check includes a pairing through the Telegram mock from 1.0.0, and the pairing still receives notifications afterwards; the upgrade check joins from the first release after 1.0.0, once the previous release includes Telegram.
- Story 12.9 turns on Story 16.3's online-demo check that the rail's Telegram card shows a resumed session's pairing.
- Turning the switch on breaks every test that assumed "not included" (API, pairing, routing, guide, restart and e2e specs); they must be repaired in the same change.
- CI mock caveats that bite once `Included()` is 1: the CI override sets the dummy token for every start, so a no-token start can't be expressed in CI (DW-367); the mock keeps one global Bot API state for every client, and every CI stack now enables `TelegramIn` against it (DW-370).
- Downstream: Epics 33, 34, 17 and 18 start once Epic 12 merges (and merge only once `release/1.0.0-rc1` exists); Story 31.3 turns on Story 16.9's Telegram allowance cases; Story 31.4 (after v1.0.0) brings the online demo's paired-chat cases; Story 38.3 runs the real-device pass.
