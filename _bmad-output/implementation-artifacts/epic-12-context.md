# Epic 12 Context: Approve from your own phone with Telegram

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Telegram puts OcuTalon on the user's own phone. A user scans the page's QR code to pair a private Telegram chat with their session; the chat then carries turns, notifications, reminders and approval requests with inline buttons, and every copy of an answer shows who answered first. OcuTalon runs fully without a bot token and pauses when another process polls the same bot. Stories 12.1 to 12.11 built the channel, turned it on for 1.0.0 and fixed it before and after the cut; they are done. Epic 12 is re-opened for one fix-forward, Story 12.12, for Sunday's 1.0.4. Story 17.6 sends tell-now notices to Telegram with a **Got it** button, and the press reaches `SessionOps`, but `SessionOps` still answers with the 5003 "not built" stub. So nothing is marked handled, the message is never edited, and the digest's "needs you" count keeps growing, because it reads up to 1,000 Decisions with no time window. Story 12.12 builds the Telegram GotIt path and limits that count to what still needs the user.

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
- Story 12.11: The rehearsal's first run leaves out the specs that need CI's mock Telegram
- Story 12.12: Got it on Telegram marks the notice handled, and needs-you counts only what still needs you

## Requirements & Constraints

- **Got it carries out the command (12.12).** A GotIt from the paired chat (origin `telegram`, channel `telegram`, the notice's decision Ref, the session of the chat's live pairing) is checked first: the Ref must be a reference, and the Decision must be a tell-now Decision of the command's own session. Then it writes one handled marker (Ref, SessionRef, HandledAt in UTC, Channel) and sends one `Notification` of kind `handled` carrying that DecisionRef. `TelegramOut`'s existing edit in place replaces the button with the existing `handled.marked` text and its time. The result is Ok 1.
- **The first press wins.** A second press of the same notice, from any channel, changes nothing and sends no second notification. The answer is Ok, with an outcome saying the notice was already handled. This is enforced through the marker table's unique index on Ref.
- **Refusals.** If the Ref is not a reference, names no Decision, names another session's Decision, or names a Decision that is not tell-now, nothing changes: no row, no notification, and the answer is Ok 0.
- **End of session.** `SessionOps.End` also deletes the session's handled rows, alongside its other cleanup. The delete is tried even when an earlier step failed, and a failed delete counts as a failed step like the others. This closes DW-695.
- **Needs-you count.** The session's tell-now and act Decisions count only while they are not marked handled AND were recorded inside the digest's window. The window runs from the session's newest digest, or from a day before its first digest. Failed check rows and incidents awaiting approval (open approval requests) always count while they are open, however old they are.
- **No new user-facing text.** The button, the edit and its text are the ones Story 17.6 already ships. The digest's wording does not change. If the window turns out to need a change to a `digest.*` text, that text is public, so it goes to the Contest Planner first. All page and chat text comes from the Message Catalog: plain text, no emoji.
- **Tests (12.12).** Replace `TestGotItNotBuilt` with tests of the built command:
  - a press marks the notice handled, and a second press is a no-op;
  - another session's Ref, and a Ref that is not a tell-now Decision, are refused;
  - End deletes the session's handled rows;
  - the needs-you cases: an old unhandled tell-now outside the window does not count, one inside it does, a handled one does not, and an awaiting incident older than the window still counts.
  
  A CI-mock Telegram test shows the press reaching the edit in place. Show each new pin red with a mutation. CI must be green on every workflow.
- **Out of scope (12.12).** The web chat's and the Simulated phone's **Got it** controls, and their "Marked as handled at {time}" copies, stay with Story 18.4. That story reuses this story's command and marker.
- **Standing Telegram rules.**
  - No real bot, chat or key: stories run against the CI Telegram mock with a dummy token. The real-device pass belongs to Story 38.3.
  - The bot token never reaches a setting, log, trace, live event or the page.
  - The Telegram display name appears only on the session's own Telegram card.
  - Mock-dependent demo-path specs carry the `@ci-only` tag, and their Rule 21 guard never skips itself (12.11). Tag any new spec that needs CI's mock or dummy token.
  - The online demo has no bot token, so its public `telegramIncluded` stays 0.

## Technical Decisions

- **The Got it contract.** Story 33.2 created the names. Story 12.12 builds Telegram's press, and Story 18.4 builds the web chat's and the Simulated phone's:
  - `OcuTalon.Msg.Command.GotIt` (`Ref`, `Channel`) is accepted from origins `web_user`, `web_admin` and `telegram`, and is routed to `SessionOps`, which marks a tell-now notice handled. The first press wins.
  - A notice's Ref is its Decision's Ref (`Notification.DecisionRef`). Every `*Out` already records it as the `DecisionRef` of its `Delivery` row, so `Delivery` gets no new column.
  - The marker lives in the Lane B table `OcuTalon.Data.Handled` (`Ref`, `SessionRef`, `HandledAt`, `Channel`; unique on `Ref`) and is read through `Handled.Marked(ref)`, which `Digest` uses.
  - Kind `handled` goes to each `*Out` operation so it can update its copy of the notice. The copy is found with `OcuTalon.Data.Delivery.FindByRef(ref, channel, ownerRef)`, the newest row of that owner and channel whose `DecisionRef` is `ref`.
  - From Story 12.12, `SessionOps` carries out a GotIt. It refuses a Ref that is not the session's own tell-now Decision (Ok 0, nothing changed). Otherwise it writes one `Handled` row, where the unique `Ref` makes the first press win, and sends one `handled` Notification. `SessionOps.End` deletes the session's `Handled` rows. The old "until Story 18.4, answer `not_built`" rule no longer applies.
  - Story 12.12 is the `Handled` writer, and Story 18.4 only adds the web chat's and the Simulated phone's controls and their handled copies, reusing the same command and marker.
- **Ownership.**
  - Lane B owns `SessionOps`, `Data.Handled`, `Delivery` and `Notify`.
  - The digest (`OcuTalon.Digest.*`, including `Digest.NeedsYou`) is Lane A's, and so are `OcuTalon.Channel.Telegram` (`TelegramIn`, `TelegramOut` with `EditHandled`), the Telegram spec files and `ci/mock/scenarios/A/`.
  - 12.12 is dispatched on runner B, but its needs-you change sits in Lane A's digest files.
  - `SessionOps.End` is a shared-by-entry file: append your own cleanup entry, and don't restructure the others.
- **Digest window and record.** `Digest` alone writes one `OcuTalon.Digest.Data.Sent` row per digest, with `WindowStart` and `SentAt`; the session's newest row is its last digest. The window starts at the newest `Sent.SentAt`, or covers the last 24 hours for a first digest.
- **Commands.** Every layer submits commands through `OcuTalon.Core.Commands.Submit` and gets back a `CommandResult`. Repeats are keyed on `IdempotencyKey`.
- **Retention.** Purging uses each area's `Purge(daysToKeep)` declaration. A demo reset restores the golden copy, which holds no session tables, so 12.12 needs only the End delete.

## UX & Interaction Patterns

- **Got it** appears on Telegram tell-now messages as an inline button. Pressing it marks the notice handled, and the message's answered line then reads "Marked as handled at {time}" (the `handled.marked` text).
- The digest's "needs you" lists failed checks, plus tell-now items the user hasn't dealt with yet, either by answering the approval request or by marking the item handled with **Got it**.

## Cross-Story Dependencies

- 12.12 builds on Story 17.6, which provides the tell-now Telegram notice, its **Got it** button, `TelegramIn`'s GotIt submit, `EditHandled` and `Digest.NeedsYou`.
- It also builds on Story 33.2, which created the GotIt class and route, the `Data.Handled` table and reader, `Delivery.FindByRef` and the `handled` kind.
- It builds on Story 16.4 for `EndSession` and `SessionOps.End`.
- Downstream: Story 18.4 adds the web chat and Simulated phone **Got it**, reusing the command and marker.
- Ledger: 12.12 closes DW-873 and DW-695.
