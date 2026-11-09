# Epic 18 Context: An admin changes settings in the web app (step 2)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

An admin opens the Settings page and changes the instance's time zone, the daily digest's time and channels, each agent's provider, model, prices and second model, and the budgets. Each change applies within a minute without a restart and is recorded in the audit log, and non-admins can't open the page. Users also get the digest on every channel: a digest card in the web chat, and plain text on the Simulated phone and in Telegram. A **Got it** control on tell-now notices marks a notice handled, so "needs you" holds only what still needs the user. Story 18.1 moved to Story 33.2, which built the page shell, the save path and the step 2 contracts.

## Stories

- Story 18.2: Set the time zone and the daily digest at run time (done)
- Story 18.3: Choose models and set budgets in Settings (done)
- Story 18.4: Read the digest on every channel and mark notices as handled

## Requirements & Constraints

- **Save rules.** Every save applies within 60 seconds with no IRIS or production restart, writes a `Settings` audit entry, and shows the fixed confirmation and error texts. A refused value changes nothing and writes no audit entry.
- **Keys.** No key value ever reaches the page, an audit entry, a log or an API answer. Model keys come only from environment variables.
- **Public text.** Any new or changed user-facing string, catalog text or README claim is public text and needs the author's acceptance (the Contest Planner's under the delegation) before it ships. The fixed-strings test covers every new label.
- **Story 18.4's acceptance criteria:**
  - The web digest card: a 4px brand-teal accent bar, the digest text, then "What I checked ({n})" as a disclosure of check rows, expanded when any entry failed or wasn't checked and collapsed otherwise.
  - The Simulated phone digest: one plain-text message, parts in the PRD's order, a time-of-day greeting, check lines starting "Passed:", "Failed:" or "Not checked:", the previous day's cost with two decimals, no Markdown, and the reserved sentences exactly as the catalog keys give them. Telegram renders the same text (Lane A).
  - **Got it** on the web tell-now notice card and the phone notification: the first press wins, both copies show "Marked as handled at {time}" within one live update, and the item stops counting as needing the user. Telegram's **Got it** is Lane A's; tests may submit the command as a Telegram press would.
  - The Digest outcome chip's meaning (strip description or tooltip) reads "Saved for the daily digest".
  - The demo-path test stays green, and a Playwright test covers the Settings page as the README account, a fixture digest card and **Got it**.
  - DW-695: `Data.Handled` needs a `Purge(daysToKeep)`; no purge owner is named yet.
- **Telegram in CI.** Tests use the CI Telegram mock. A real bot is used only in the Contest Planner's hands-on pass.

## Technical Decisions

- **Lanes.** This is a Lane B epic: `Core.SettingsOps`, `Data.*` (Lane B tables, `Handled` included), `Core.Rule.Notify`, `WebChatOut`, `SimPhoneOut`, `Msg.Catalog.Core`, `Catalog.Render` and `web/`. Lane A owns `OcuTalon.Bridge.*`, `Digest.*`, `Checks.*`, `Msg.Catalog.Watch` (all `digest.*`, `button.gotIt` and `handled.marked` texts), `TelegramOut`, `TelegramIn` and `Install.Task.Purge`.
- **Settings writer.** `SettingsOps` is the only run-time settings writer (one `SaveSettings` per section save, origin `web_admin`). Budgets are bridge host-setting rows written through `Bridge.Settings.Set` and read by `Decide` on each decision, with no production update. Model changes go through the bridge's `SetModel` and apply when the runner restarts.
- **Digest routing.** `Notify` sends kind `digest` only to the channels `digest.channels` names that the session has (`Functions.DigestNamed`): web; phone when demo mode is on; Telegram when paired. Lane A's `Digest.Process` still narrows by itself (`Process.Own` and direct sends) until a Lane A story routes every digest through `Notify` (DW-820, Digest half).
- **Digest notification.** `Slots` is `{parts, lines, rows}`: `parts` the prose in the PRD's order, `lines` the coverage lines, `rows` the check rows meant for the web card (`{result, entry, finding, checkedAt}`). Each `*Out` renders every `{key, slots}` through `Catalog.Render` only, never anything else. `Channel.DigestText.Text(slots, channel)` is the shared renderer (parts and lines only; `rows` are not read).
- **Got it.** `Msg.Command.GotIt` (`Ref`, `Channel`; origins `web_user`, `web_admin`, `telegram`) goes to `SessionOps`. The `Ref` is the notice's `Decision` Ref. The marker is a `Data.Handled` row (unique `Ref`), read through `Handled.Marked(ref)`. A `handled` Notification goes to every `*Out` through the generic route; each finds its copy with `Delivery.FindByRef(ref, channel, ownerRef)`.
- **Retention.** Each area declares `Purge(daysToKeep)`, which `Install.Task.Purge` (90 days by default) calls through `Install.Registry`. No purge reads `Data.Setting`.

## UX & Interaction Patterns

- **Digest card** (D `digest-card`): the surface background, a 1px border, the 4px brand-teal accent bar, the medium radius. Check rows show a result icon and word ("Passed", "Failed", "Not checked"), the entry and the finding. "What I checked" is a button with `aria-expanded` that opens inline.
- **Got it.** On the web notice card and the phone notification; the answered line reads "Marked as handled at {time}".

## Cross-Story Dependencies

- **Built by Stories 18.2 and 18.3 (this branch).** Time zone, Daily digest with **Send my digest now** (`POST /api/v1/settings/daily-digest/send`, 202), Channels (read only; its POST route is still `NotBuilt`), Models with **Test**, and Budgets. `Notify`'s `digest` branch. Story 18.4's Playwright test covers these sections; `web/e2e/settings/settings.spec.ts` already signs in as the README admin (`signInReadmeLoaded`).
- **Delivered for Story 18.4 by Stories 17.10, 17.11 and 12.12** (integrated through feature `ce50aa62`). Judge each AC against this code:
  - **Web digest (17.10).** `Channel/WebChat/Out.cls` takes kind `digest` (in `CARDKINDS`) down the card path. The text is `DigestText.Text(Slots, "web")`: parts and coverage lines, one per line, with no title and no rows. It records a `Delivery` row of kind `digest` with that text and publishes one `notification` event. `Data/Ownership.cls` `RecentNotices` returns digest rows that have a `ChannelMessageId`, so a reload shows the card again.
  - **Web card (17.10).** `web/src/app/chat/notice-card.ts` draws a digest as a notice card (class `digest`, the `inbox` icon, `pre-line` text) with the default info accent bar (`--notice-card-accent-bar`, 4px info blue), not brand teal. It has no "What I checked ({n})" disclosure and no check rows. The `--digest-card-*` tokens (teal bar) exist in `web/src/styles/tokens.css` but nothing uses them. `chat-view.ts` maps kind `digest` to a notice. `web/e2e/chat/notice.spec.ts` N16 asserts the plain-text card, also after a reload.
  - **Online demo (17.11).** It adds a test only: an online-demo visitor's digest, rendered with `DigestText.Text(slots, "web")`, names no host path, IP address, user name or key. No product code changed.
  - **Got it (12.12).** `Core/SessionOps.cls` carries out `GotIt`: it refuses a Ref that is not the session's own tell-now Decision, writes one `Data/Handled.cls` row (first press wins) and sends one `handled` Notification. `SessionOps.End` deletes the session's rows (`Handled.DropSession`). `Digest.NeedsYou` counts only unhandled tell-now and act Decisions inside the needs-you window. `TelegramOut` adds the **Got it** button to tell-now messages and edits a handled message in place with `handled.marked`.
- **Still missing for Story 18.4:**
  - **Digest card.** The teal bar, the "What I checked ({n})" disclosure, its expanded-or-collapsed rule, and the check rows. The `Delivery` row keeps text only and the notification payload (`Live/Payload/Notification.cls`) has no rows field, so rows survive neither the event nor a reload today. `web/src/app/chat/check-rows.ts` is an existing check-row component.
  - **Phone digest.** `Channel/SimPhone/Out.cls` has no `digest` kind (its `CARDKINDS` are tellnow, reminder, incident, approval, result), so a phone digest records only a `Delivery` row and shows nothing. `DigestText.Text(slots, "phone")` is the intended renderer.
  - **Web and phone Got it.** There is no Got it button in `notice-card.ts` or `web/src/app/phone/*`, and no REST route that submits `GotIt` (`Web/Api.cls` and the spine's REST table have none). A `handled` Notification reaches `WebChatOut` and `SimPhoneOut` but only records a `Delivery` row, so no "Marked as handled at {time}" copy appears there, and the payload carries no handled marker.
  - **Digest chip.** The chip's meaning is still release 1's "Saved for later; nobody notified now" (`chat-view.ts` `meaningDigest`, used by `outcome-chip.ts`). The heartbeat card shows "Saved for the digest" (`rail/heartbeat-card/heartbeat-card-view.ts`). Neither reads "Saved for the daily digest".
  - **DW-695.** `Data.Handled` has no `Purge(daysToKeep)`. The Core area's purge declaration (`Install/Step/Core.cls`) calls only `Data.Pairing.Purge`.
  - **Playwright.** No test covers a fixture digest card with check rows or **Got it**.
