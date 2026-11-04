# Epic 12 Context: Approve from your own phone with Telegram

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Telegram puts OcuTalon on the user's own phone. A user scans the page's QR code to pair a private Telegram chat with their session; the chat then carries turns, notifications, reminders and approval requests with inline Approve and Reject buttons, and every copy of an approval shows who answered first. OcuTalon runs fully without a bot token and pauses when another process polls the same bot. Stories 12.1 to 12.9 built the channel and turned it on (Telegram ships in 1.0.0, the first release). Epic 12 is re-opened for one story, 12.10, a fix before the 1.0.0 tag: at 1024 to 1279 px the status rail is a drawer that starts closed, so the unpaired Telegram card is off the page while the demo guide tells the user to "scan the QR code in the Telegram card". The guide must lead the user to the Status button and open the drawer with the card in view. The 1.0.0 release candidate (rc1) waits for this story.

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
- Story 12.10: In a narrower window, the Telegram step leads to the Status drawer

## Requirements & Constraints

- **Scope of 12.10 (narrow).** It applies only when all three hold: the page is 1024 to 1279 px wide (rail is a closed drawer), Telegram is configured (bot token set, card in its unpaired state), and the session is unpaired. Then the guide's Telegram hint tells the user to open the Status button in the page header, naming the button exactly as it is labelled, and the step gets a Show me that opens the Status drawer with the Telegram card in view: not clipped, hidden or overlapping anything, with the QR code and "Open in Telegram" visible and enabled.
- **Everything else unchanged.** At 1280 px or wider, with Telegram not configured, or with the session paired, the Telegram step behaves exactly as today.
- **Online demo stays dark.** The demo host sets no bot token at 1.0.0, so the public key `telegramIncluded` is 0 there; neither the Telegram hint nor the unpaired card may show at any width. The change must keep that, and a check should show it.
- **Tests.** A browser test at 1100 px pins the hint and the Show me drawer; a control at 1400 px shows nothing changed. CI green on every workflow.
- **Out of scope.** The device-column placement of the unpaired card at 1024 to 1279 px (DW-503) goes to the first daily release after 1.0.0. The README addition for narrow windows belongs to Story 31.3, not this story.
- **Wording.** All page text comes from the Message Catalog (plain text, no emoji). The new hint wording is not in the UX spec; it goes to the Contest Planner as a veto item before implementing, like any new or changed user-facing wording.
- **Standing rules from 12.1 to 12.9.** No real bot: every story runs against the CI Telegram mock with a dummy token (the real-device pass is Story 38.3's). The bot token never reaches a setting, log, trace, live event or the page. The Telegram display name appears only on the session's own Telegram card.

## Technical Decisions

- **Lane ownership.** The page layout, header (including the Status button), status-rail drawer and demo guide are Lane B's web files; 12.10 runs on runner B. Lane A owns the Telegram card component (`web/src/app/rail/telegram-card/`), `web/e2e/demo-path/telegram-*.spec.ts`, `OcuTalon.Channel.Telegram`, the README's Telegram section and `ci/mock/scenarios/A/`. Keep 12.10's changes in Lane B files unless a Lane A file truly must change.
- **Telegram state on the page.** The page learns whether Telegram is included, set up, unpaired, paired or paused from `/state`'s Telegram block; `OcuTalon.Channel.Telegram.In.Included()` now returns 1 (the test-only seam `^OcuTalonTest("TelegramIncluded")` can still turn it off in tests). The online demo's public pages read only `telegramIncluded` from `Data.Public.Settings`, which is 1 only when `Included()` is 1 and a bot token is set on that start.
- **README links.** One README address in `web/src/app/links.ts`; the Telegram section's anchor is `#telegram`.

## UX & Interaction Patterns

- At 1024 to 1279 px the rail is a drawer opened from a "Status" header button that shows the pending approval request count; guide step labels shorten to numbers, and the prompt bar keeps its full text.
- Today's Telegram step (before step 1, while Telegram is on and unpaired) reads "Optional: scan the QR code in the Telegram card to get the notice on your own phone.", has no action button, and is done when Telegram pairs or step 1 is done.
- Show me follows the existing pattern (guide step 4): a switch the user causes is allowed, it moves focus to the revealed target, and it never presses anything for the user. Focus rules from the floor still apply: focus moves to a replacement when an update removes the focused element, and one polite live region carries announcements.
- Unpaired card content: the QR code, "Scan with your phone's camera, then tap Start in Telegram.", "Open in Telegram", and "New code in 9 min".

## Cross-Story Dependencies

- Stories 12.1 to 12.9 are done and merged; 12.10 builds on 12.3's card and 12.9's switch.
- 12.10 runs in parallel with Story 31.3 (Epic 31's branch), which adds the README's narrow-window wording to the Telegram setup steps; rc1 waits for both. If 12.10 has not merged when 31.3 does, the Contest Planner wants an ETA.
- Downstream: DW-503's device-column placement is a Lane B layout story in the first daily release after 1.0.0; Story 38.3 runs the real-device Telegram pass on the 1.0.0 candidate.
