# Epic 17 Context: A daily digest you can trust, and model choice with budgets (step 2)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Once a day at the set time, and whenever the user asks, OcuTalon sends one short digest. It holds the vital signs, a coverage list where every entry is passed, failed or not checked, what needs the user, what was saved for later, and yesterday's model cost. Only code decides whether an all-clear is given. The epic also lets an admin choose each agent's provider and model, set prices, budgets and the time zone through the bridge, and name a second model for one retry. Stories 17.2 to 17.9 are done. Story 17.10 is left, a fix-forward for release 1.0.4. Today "send my digest now" promises a digest that never shows up in the web chat or on the online demo. The story makes the digest appear as a plain-text notice card in the web chat on every install, and stops the morning run from sending to online-demo sessions.

## Stories

- Story 17.2: Retry once on a second model before falling back (done)
- Story 17.3: Run each agent on a supported provider (done)
- Story 17.4: Apply model, price, budget and zone changes through the bridge (done)
- Story 17.5: Check the vital signs and every coverage entry (done)
- Story 17.6: Send the daily digest at the set time and on request (done)
- Story 17.7: Give an all-clear only when every check passed (done)
- Story 17.8: Only Decide moves a conversation's link (done)
- Story 17.9: Epic 17 burn-down (done)
- Story 17.10: The digest shows in the web chat, and the online demo's digest is visible

## Requirements & Constraints

- **Scope of the ruling (DW-874, option a).**
  - In scope: a web chat digest card on every install, as plain text, web only.
  - Out of scope: the Simulated phone gets no digest, and `SimPhoneOut` is unchanged.
  - Out of scope: the full UX digest card, with the brand-teal bar, grouped check rows and the "What I checked ({n})" disclosure. That card belongs to Lane B's Story 18.4.
  - A local user with Telegram paired gets the digest in both the web chat and Telegram. This is accepted.
- **No new strings.** The web copy renders the shared `digest.*` and `checks.*` catalog texts through `Msg.Catalog.Render` with channel `web`. It keeps the same parts, in the same order, one piece per line. Any wording that visitors see is public text, checked at the spec gate.
- **Telegram stays byte-identical.** `TelegramOut`'s `DigestText`, `Pieces` and `Piece` move into one shared helper that takes the channel. Before the move, write a golden test of Telegram's output; it must still pass after the move. `Test.Channel.TelegramDigest` must also stay green.
- **Online demo.** A session is an online-demo session when `Data.Public.Settings` "onlineDemo" is on and the session's `ResumeHash` is not empty.
  - The morning (scheduled) digest run skips these sessions. Pin this with a test and show a mutation turning it red.
  - A visitor's own "send my digest now" still composes the digest and shows the card in that visitor's chat. The model summary runs only when something was saved for later, as on any install.
- **REL-2 stays green.** The online demo path gains one step: the visitor asks for the digest and its card appears. Only new CI mock scenario files may be added for it.
- **Tests and pins.**
  - Update the tests that hard-code the web chat's card kinds: `Test.Core.WebChatOut` and `Test.Data.Ownership`.
  - Add a `WebChatOut` digest case.
  - Add a Playwright case to `web/e2e/chat/notice.spec.ts`.
  - Show every new pin turning red with a mutation.
- **Digest rules from earlier stories still hold:**
  - The all-clear and its reserved sentences come only from `Checks.Render`.
  - The cost shows two decimals (slot type `dailyCost`).
  - The greeting depends on the hour in the instance zone.
  - The digest has no Markdown.
- **Public-text guard (DW-755).** No README, guide, settings page or release text may say that a provider other than Anthropic runs decisions.
- **Flakes.** A flake gets one rerun and an occurrence line in the ledger.

## Technical Decisions

- **The digest notification.** A digest is one `OcuTalon.Msg.Notification` of kind `digest`.
  - Its `Slots` are `{"parts": [{key, slots}...], "lines": [{key, slots}...], "rows": [...]}`.
  - `parts` are the prose parts in order: greeting, vital signs, what was checked with the reserved sentence, needs you, saved for later, cost.
  - `lines` are the coverage lines. `rows` are the check rows meant for the full web card.
  - Producers never render text. Each `*Out` operation renders every `{key, slots}` through `Catalog.Render(key, slots, channel)` and renders nothing else.
- **Routing.** A digest goes only to the session's own digest channels, and the web chat is always one of them. Until Story 18.2 lands, `Digest.Process` narrows Notify's route itself (`Own`) and sends straight to those channels' outbound items. `WebChatOut` must now accept kind `digest`: its card-kind list lacks it today.
- **Web notice cards.** `WebChatOut` is the only publisher of the `notification` live event. It keeps each web card on its web copy's `Delivery` row, with `Kind`, the rendered `Text`, `DecisionRef`, `DueAt` and `FallbackReason`.
  - The digest's row has kind `digest` and holds the whole text.
  - `WebChatOut` publishes one `notification` event on the session's stream, after its own change commits. The payload is the full public view, keyed by `Ref`, and its `text` is the whole digest.
  - The snapshot query in `Data.Ownership` rebuilds the cards on reload, so it must include digest rows.
- **Web drawing.** The chat draws the digest as a notice card with the digest's own class and icon, keeps its line breaks, and shows no title.
  - The TypeScript payload interfaces are generated from the payload classes (`web/scripts/payloads.mjs --check` runs in the build).
  - On the online demo, live updates arrive only by polling. The page never opens the WebSocket there.
- **Ownership.** `WebChatOut`, `SimPhoneOut`, `Data.Delivery`, `Data.Ownership` and the web chat are Lane B's. `TelegramOut`, `Digest` and `Checks` are Lane A's. Story 17.10 changes the Lane B files it names under the Planner's ruling, and runs on runner slot B. The ownership tables do not change.
- **Testing.** Tests use the CI model mock (`ci/mock/`, scenarios under `ci/mock/scenarios/`). The digest summary's model request goes through `Decide`. If it is unusable, the digest still goes out with the count and no summary.

## UX & Interaction Patterns

- A notice card shows the catalog text exactly, with no title. The digest card's text keeps one piece per line.
- In the full UX design, the digest card uses a 4px brand-teal accent bar and the `inbox` icon for the digest outcome. Story 17.10's card only needs the digest's own class and icon. The check rows and the disclosure wait for Story 18.4.
- In chat, "send my digest now" is a safe tool action that submits `SendDigest` (origin `tool`). A digest of either kind starts the next window.

## Cross-Story Dependencies

- Story 17.10 builds on:
  - Story 17.6's `Digest.Process` and `TelegramOut` digest rendering;
  - Story 17.7's `Checks.Render`;
  - Epic 16's online-demo settings and `ResumeHash`;
  - Story 2.7's `WebChatOut` and `Delivery` notice cards.
- Epic 12's Story 12.12 (Telegram **Got it**, DW-873) is in flight at the same time and also changes `TelegramOut`'s class. Either a merge-file proof shows the two changes combine cleanly, or this story merges first.
- Lane B's Epic 18 is in backlog:
  - Story 18.2 owns Notify's `digest.channels` route.
  - Story 18.4 owns the full digest card, the phone copy and **Got it** on the web.
- Target: release 1.0.4 (Sunday), ahead of every tier (3) item.
