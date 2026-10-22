---
title: 'Story 2.5: Chat with OcuTalon in the page'
type: 'feature'
created: '2026-10-22'
status: 'done'
baseline_revision: 'a1b899e6350ab101d52eb70c38edae00eb552c0c'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      The chat panel's at-the-bottom flag can turn false when an entry lands between the panel's own scroll to the bottom and that scroll's event, so the list stops following new content.
    evidence: |-
      Edge-case review: by event order (scrollTop set, a DOM growth of more than 24 px, then the scroll event measures the geometry) the flag turns false and the ResizeObserver stops pinning. Not reproduced: C10 (8 sends and replies in a 30-turn chat), C6 and C9 passed on a throwaway. To settle it: run C10 over several CI runs on the slow hosts, or trace a send frame by frame; if it reproduces, mark the scroll that scrollToBottom makes as the panel's own and skip re-measuring on its scroll event.
    location: >-
      web/src/app/chat/chat-panel.ts onScroll and scrollToBottom
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** The signed-in page has no chat. `main` holds only its hidden "Chat" heading, so the user can't see the conversation, type a message, or watch a turn run and get its reply, although Story 2.4 built the whole server path: `POST /api/v1/messages`, the turn pipeline, and `chat.message` at `queued`, `running` and `done`. `/state`'s chat also loads and serializes every turn and noticed incident of the session on every load (DW-65), so a durable local session makes each reload slower without limit.

**Approach:** Build the chat panel inside `main`:
- the conversation from `LiveState.store().chat`, in order, with live `chat.message` updates;
- the empty chat panel for a fresh session;
- the composer, which posts each message with a new `clientId` and reuses it for **Retry sending**;
- the user's bubbles, OcuTalon's replies (rendered as text, the fallback sentence from the message catalog), the turn indicator, and the **New messages** button.

Turn on the demo-path page step's chat check. Cap `/state`'s chat at the newest 100 entries, through two new `Ownership` row kinds (DW-65).

## Boundaries & Constraints

**Always:**
- **The panel (UX-DR58).** It lives inside `<main class="main">`, the `main` landmark, after the hidden `<h2>Chat</h2>`, and only once `live.status()` is `loaded`. The loading skeletons and the load error stay exactly as Story 2.2 built them.
  - **Order.** The list shows the `chat.message` entries of `LiveState.store().chat` in store order, followed by this page's own messages that the store doesn't hold yet, in send order. The store's order is the snapshot's, plus events appended as they arrive.
  - **Width.** Text lines are capped at `--chat-panel-text-max` (72ch). Entries span the column, so later cards are full width.
  - **Not a live region.** Nothing in `main` carries `aria-live`, `role="log"`, `role="status"` or `role="alert"`, and nothing in the panel moves focus, except the **New messages** press.
  - **Layout.** The page fills the viewport's height. The list scrolls on its own, with the composer at the bottom of `main`, and the rail scrolls on its own.
- **Entries.** A `chat.message` entry renders as the user's bubble, then the turn's indicator or its reply.
  - `incident` entries (Story 6.1's card) and `notification` entries (Story 2.7's card) render nothing yet.
  - A local message is dropped from view as soon as the store holds a `chat.message` with its `clientId`. It is gone whether the turn arrived by event or by snapshot, and even after a send that failed.
- **The empty chat panel (UX-DR70, UX-DR89).** It shows while the store's chat holds no entry of any type and no message of this page is pending. It is centred in the list, and the first message replaces it.
  - The headline is a `<p>` in `display-md`: "For everything that arrives, OcuTalon makes one attention decision". It is not a heading, because frame spec F1 pins the page's h2 and h3 lists.
  - Next come the four outcome chips, each with its release-1 meaning in `body-sm`:
    - Ignore "Recorded; nobody notified"
    - Digest "Saved for later; nobody notified now"
    - Tell now "Needs you now"
    - Act "OcuTalon took or requested an action"
  - Then, in `body` and `ink-muted`:
    - "It watches your productions from inside IRIS, and every decision is a production message you can trace."
    - "Anything risky waits for your approval."
    - "Ask OcuTalon to watch a production, set a reminder, or say what you need." This line shows in demo mode too; Story 4.4 adds the demo-mode line.
- **The outcome chip (`app-outcome-chip`, UX-DR63, DESIGN:794).** A borderless pill coloured by `--outcome-chip-<outcome>-*`. It has its icon (`eye-off`, `inbox`, `bell-ring` or `zap`, `aria-hidden`) and its label ("Ignore", "Digest", "Tell now", "Act"). It is not focusable. Story 2.6 adds its tooltip and its place in the decision strip.
- **The composer (UX-DR68, UX-DR125).**
  - **Field.** A `<textarea>` labelled "Message OcuTalon" by a visually hidden `<label>`, so the name holds while text is typed. Its placeholder is "Message OcuTalon".
  - **Keys.** Enter sends, except while an IME composition is open. Shift+Enter adds a line.
  - **Height.** It grows with its content, by script, up to 5 lines, then scrolls.
  - **Send.** A `button button-primary` "Send". It is not `app-server-button`; see Decided 7.
  - **Sending.** The text is trimmed at both ends, and its inner line breaks are kept. Empty text sends nothing.
  - **After a send.** The field clears and shrinks, and has focus: Enter never moves focus, and a click on **Send** returns focus to the field.
  - **During a turn.** It is never disabled, and each message becomes its own turn (NFR-6).
  - **No autofocus.**
- **Sending (AD-30, AD-4).** `ChatOutbox.send(text, fromGuide = false)` makes a local entry and posts it at once.
  - The entry is `{clientId, text, sentAt, status}`. Its `clientId` is new: 16 bytes from `crypto.getRandomValues`, as 22 base64url characters.
  - The post is `ApiClient.postMessage({clientId, text, fromGuide})`, through the envelope interceptor. The body carries no session reference.
  - **Status.** A 202 marks the entry `sent`. Any other answer marks it `failed`: a network error, a non-202 status, or no answer within `BUSY_TIMEOUT_MS` (10 s). A 401 is `SessionGate`'s.
  - **Retry sending** posts the same `clientId` and text again, so a send that reached the server is not queued twice.
  - A new message (`send`, not `retry`) scrolls the list to the bottom.
- **The user's bubble (UX-DR59, UX-DR123).** It is right-aligned on `--chat-message-user-background` (`sunken`), with `--chat-message-user-radius`, and is at most 80% of the list's width. The text keeps its line breaks.
  - **The line under it.** It holds the time, in the browser's zone and hour format with no zone suffix (`Intl.DateTimeFormat(undefined, {hour: 'numeric', minute: '2-digit'})`).
    - The time comes from the server's `createdAt`, or from the local `sentAt` until the server's entry arrives.
    - A caption comes first when it applies: "via Telegram · 14:11" for `channel` `telegram`, and "From the demo guide · 14:11" for `fromGuide`.
  - **A failed entry** shows "Not sent", with `circle-alert` (`aria-hidden`) in `--danger-ink`, and a `button button-secondary` "Retry sending".
- **OcuTalon's reply (UX-DR60, UX-DR42, AD-13).** It is left-aligned and unboxed, under the 24px mark avatar and the name "OcuTalon". The avatar is the header's `assets/brand/icon-192.png`, `alt=""`.
  - **A done turn with `catalogKey`** shows `renderPageText(catalogKey, {fallbackReason})` from the generated catalog module.
  - **A done turn without it** shows `replyText`, parsed by `reply-text.ts` into:
    - paragraphs: blocks between blank lines, keeping their single line breaks;
    - bulleted list lines (`- `, `* `, `• `) and numbered list lines (`1. `, `1) `);
    - links: bare `http://` and `https://` URLs, without trailing `.,;:!?` or an unmatched `)`, and `[label](http(s)://…)`.
  - **Everything else shows as typed**, `<`, `*`, `#` and backticks included. A link whose scheme is not http(s) stays text.
  - **Rendering is by template interpolation and `[href]` only.** Nothing in `web/src` uses `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `DomSanitizer` or `bypassSecurityTrust*`. The shell keeps sending `Content-Security-Policy: script-src 'self'`.
  - **Links** are `class="link" target="_blank" rel="noopener noreferrer"` with the `external-link` icon. Their accessible name ends in "(opens in a new tab)", as in the About dialog.
- **The turn indicator (UX-DR66, UX-DR14).** It sits in the reply's place: a row in `--turn-indicator-*`, with the 24px avatar.
  - **States:**
    - an entry that is `sent`, or a turn that is `queued`: "Deciding…";
    - a turn that is `running`: "Working…";
    - 10 s after this page first saw the turn `running` (the page's clock): "Working · 12 s", whole seconds, with the accessible text "Working · 12 seconds";
    - a turn that is `done`: the reply replaces it, a fallback included.
  - An entry that is `sending` or `failed` has no indicator.
  - **The dots.** The text's "…" is the single character U+2026. When motion is allowed, its glyph is revealed in three steps by CSS. Under `prefers-reduced-motion: reduce` it has `animation: none`.
  - **Not a live region.** A 1 s clock ticks only while a turn is `running`.
- **Scrolling (UX-DR67, UX-DR126).**
  - On the first load the list scrolls to the bottom. While it is at the bottom (within 24 px), new content keeps it there.
  - **Scrolled up.** New content changes nothing about the list's scroll. The content is a new entry, or a reply that lands. The **New messages** button then shows (`button` in `--new-messages-button-*`, with `chevron-down`, `aria-hidden`). It floats centred above the composer and comes just before the composer in the DOM and the tab order.
  - **Pressing it** scrolls the list to the bottom with no smooth scroll and focuses the first entry that arrived or changed while the list was scrolled up. Each user message and each reply is an element with `tabindex="-1"`. The button hides when the list is at the bottom.
- **The catalog on the page (AD-32, Conventions "Text OcuTalon sends").** `web/scripts/catalog.mjs` writes `web/src/app/msg/catalog.ts` from `Msg/Catalog/Core.cls`'s `XData Entries` and `Msg/Catalog.cls`'s `REASONKEYS`. It reads an allowlist of the keys the page renders: `conversation.turnFallback` and every `fallbackReason.*`.
  - Each entry's `web` text is used, else its `text`.
  - `renderPageText(key, slots)` fills `fallbackReason` slots through `REASONKEYS`. A value outside them gives `fallbackReason.generic`.
  - **Fail closed.** The generator exits 1, naming the file, for a listed key that is missing, a listed key with a slot type other than `fallbackReason`, or an `XData` block it can't parse.
  - **`--check`** writes nothing and exits 1 when the file is stale. It runs in `npm run build`.
- **The fixed strings** are exported constants in one module, with every non-ASCII character as an escape sequence in the source (backslash-u 2026 for the ellipsis, 00B7 for the middle dot, 2022 for the bullet) (Rule 14).
- **DW-65: `/state`'s chat cap.**
  - `Web.Api` `Parameter CHATMAX = 100`.
  - `ChatItems` reads `Ownership.RecentTurns(sessionRef, ..#CHATMAX)` and `RecentIncidents(sessionRef, ..#CHATMAX)`, both newest first. It merges them as today: by time, a turn before an incident of the same second, then by ID. It returns only the newest `CHATMAX` entries, oldest first.
  - The snapshot keeps its key list and `chat: LiveItem[]` shape (AD-12). `streams` is still read before the chat.
- **SQL (AD-13 as amended).** Two new `Ownership` row kinds, each with the owner check in its `WHERE`, fixed SQL, and `TestIsolationEveryRowKind` coverage:
  - `recentTurns` (`ao`): `SELECT TOP ? ID FROM OcuTalon_Data.Turn WHERE SessionRef = ? ORDER BY CreatedAt DESC, ID DESC`;
  - `recentIncidents` (`aoao`): the `incidents` statement with `TOP ?` and `ORDER BY i.NoticedAt DESC, i.ID DESC`.

  They need no new unchecked prepare and no embedded SQL. `ALLOW_UNCHECKED` is unchanged.
- **The demo path (REL-2, AD-29).** In `web/e2e/demo-path/01-page.spec.ts`, `notBuilt('the chat panel and the composer', '2.5')` becomes a real `@floor` test, "shows the empty chat panel and the composer", as the README account.
  - It sends no message and sees no `POST /messages` request: the demo-path stack has no fixture user and no model key.
  - It asserts only what both demo modes share, so it leaves out the last line.
- **Tests (AD-22, Rule 19).**
  - Browser specs that send or seed sign in as the new fixture user `PANEL`. The README account is only read.
  - No spec publishes on the README session or the instance stream (api.spec pins their counts) or touches the `CHAT` user's chat.
  - A node-tested module (`chat-view.ts`, `reply-text.ts`, `catalog.ts`, `page-time.ts`) imports only types, so `node --test` can import it as it is.

**Never:**
- **Never edit Lane A paths:** `src/bridge/**`, `Agent/**`, `Install/**` other than `Install/Step/Web.cls`, `Test/Install/**`, `Msg/Catalog/Watch.cls`, `docs/**`, `eval/**`, `release/**` and `lane-a.yml`. Never edit `docker/merge.cpf` or `test-production.sh`'s Epic 1 fixture check (about `:277-298`).
- **Never build another story's part:**
  - Story 2.6: the decision strip, the chip's tooltip and description, `BridgeSink`, and the `turn.step` label.
  - Story 2.7: notice cards, `WebChatOut` and `Delivery`.
  - Story 2.9: trace links.
  - Stories 2.10 and 2.11: banners and lost contact.
  - Story 2.12: announcements ("OcuTalon replied:", "Message not sent"), the focus-replacement rule (a removed **Retry sending** included), skip links, the Firefox and WebKit runs, the accessibility scan and the stacked layout.
  - Story 4.4: the demo-mode last line and guide sends.
  - Story 6.1: incident cards.
  - Story 16.9: the 429, the refused turn and the composer's `aria-disabled` reason.
  - The WebSocket.
- **Never change:**
  - `POST /messages`, the `chat.message` payload or the snapshot's key list;
  - what `Ownership.Turns` and `Ownership.Incidents` return, because `Recap`, `Fixture.AdoptTurns` and the incident readers use them (their SQL text may move into a shared fixed parameter, unchanged);
  - `ALLOW_UNCHECKED`;
  - `tokens.css`, which is generated.
- **Never render** model-written or arriving text as HTML, never add an inline script, and never loosen the CSP.
- **Never add** a single-key shortcut or autofocus.
- **Never run on slot B:** `Test.Live.Publish`, `Test.Web.Install`, `Test.Install.Registry`, `Test.Demo.Production`, `Test.Core.CommandsInProduction` or `Test.Core.ConversationProduction` (Rule 21).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fresh | Loaded, the store's chat empty | The empty chat panel: the headline, the four chips with their meanings, and the three lines. The composer is below it. Nothing in `main` is a live region | Loading or failed: Story 2.2's skeletons or error, and no composer |
| Snapshot | `/state` chat with turns (and incidents) | Each turn is a bubble, then its reply, in the snapshot's order. Incidents render nothing | — |
| Send | Enter or **Send** with text | `POST /messages` `{clientId: 22 base64url chars, text trimmed, fromGuide: false}`. The bubble shows at once, the field clears and keeps focus, and the list goes to the bottom | Empty or space-only text: nothing sent. Enter during an IME composition: no send |
| Lines | Shift+Enter, then more lines | A line break and no send. The field grows to 5 lines, then scrolls | — |
| Stages | 202, then `queued`, `running`, `done` | "Deciding…", then "Working…" (after 10 s "Working · N s", spoken "N seconds"), then the reply. The `running` stage is on the page before the reply | — |
| Mid-turn | Send while a turn shows "Deciding…" | The composer is still enabled. A second bubble and a second turn, with replies in order | — |
| Fallback | `done` with `catalogKey` `conversation.turnFallback`, reason R | "I couldn't answer that: {R's text}. Nothing was changed.", with each of the 12 reasons in the UX's words | A reason outside `REASONKEYS`: the generic reason |
| Reply text | `replyText` with paragraphs, two kinds of list, links and HTML-like text | Paragraphs and lists. http(s) links open in a new tab, named "… (opens in a new tab)". `<b>`, `<img onerror>` and `javascript:` show as text | — |
| Captions | `channel` `telegram`; `fromGuide` true | "via Telegram · 14:11"; "From the demo guide · 14:11"; browser zone | — |
| Send fails | Network error, a non-202 status, or no answer in 10 s | The bubble keeps the text, "Not sent", **Retry sending**. A retry posts the same `clientId` | The first post did reach the server: one turn only. 401: `SessionGate` |
| Arrives anyway | A failed post whose turn then arrives by poll | The server's entry replaces the local one, and no "Not sent" is left | — |
| Scrolled up | A new entry or a reply lands | `scrollTop` and the visible entries stay put, and **New messages** shows | At the bottom: the list follows |
| New messages | Press it | Scrolled to the bottom; focus on the first new entry; the button is gone | — |
| Reduced motion | `prefers-reduced-motion: reduce`, a turn deciding | The indicator's dots have `animation-name` `none` | — |
| Long session (DW-65) | 103 turns, 1 s apart, plus noticed incidents at 10:00:00 (oldest) and at turn 50's second | `/state` chat = 100 entries: turns 5-103, with the second incident after turn 50, in time order | — |

</intent-contract>

## Code Map

**Page (Lane B, edit)**
- `web/src/app/main-page/main-page.ts`:
  - the template is `:26-67`. `main.main` and its `data-snapshot`/`data-session-seq`/`data-instance-seq`/`aria-busy` attributes (`:45-51`) are read by every spec and must stay;
  - the h2 is at `:52`, the skeleton `:53-59` (class `.chat-bubble`, so don't reuse that name) and the error `:60-65`;
  - styles: `.main` `:117-121`, host `:69-73`;
  - class `:155-165`.

  The panel goes after the h2, under `@if (live.status() === 'loaded')`.
- `web/src/app/app.ts` -- the host is `min-height: 100vh` (`:22-26`); the template is `:15-19`, with `.banner-slot` at `:17` (Story 2.10's).
- `web/src/app/live/live-state.ts` -- `store` `:63`, `status` `:60`, `sessionSeq`/`instanceSeq` `:66-69`; views read `store().chat`, not `snapshot` (`:54-57`). "Nothing here moves keyboard focus" `:32`.
- `web/src/app/live/live-store.ts`:
  - `COLLECTIONS` `:39-56` puts `chat.message`, `notification` and `incident` in `chat`;
  - `chatKey` = `type:ref` `:95-97`;
  - `fromSnapshot` `:109-128`;
  - replace-in-place or append `:147-152`;
  - `applyEvents` `:195-214`.

  It has no get or list API.
- `web/src/app/live/payloads.ts:71-84` -- `ChatMessagePayload`: every field is optional (`ref`, `clientId`, `channel`, `fromGuide`, `state`, `text`, `replyText`, `catalogKey`, `fallbackReason`, `createdAt`, `traceHeaderId`, `traceNamespace`).
- `web/src/app/api/api-client.ts` -- `BASE` `:7`; `endSession` `:20-22` is the POST pattern. There is no `postMessage` yet.
- `web/src/app/api/api-types.ts` -- `LiveItem` `:12`, `StateSnapshot` (`chat` `:37`), `EventsResponse` `{epoch, events}` `:52-55`, `ApiError`.
- `web/src/app/api/envelope.interceptor.ts:19-38` -- it adds `Content-Type: application/json` and `X-OcuTalon-Request: 1` to every POST, and sends a 401 to `SessionGate`.
- `web/src/app/session/session-gate.ts:26-33`.
- `web/src/app/shared/busy-state.ts:14` -- `BUSY_TIMEOUT_MS`.
- `web/src/app/shared/server-button.ts:10` -- `BUSY_NOTICE`. It is not used for Send.
- `web/src/styles/controls.css` -- `.button .button-{variant}`, `.link` `:104-114`.
- `web/src/app/icon/icon.ts` -- `IconName` `:4-14` and the `@switch` of inline Lucide paths `:16-94`. It has `chevron-down`, `circle-alert` and `external-link`, and lacks `eye-off`, `inbox`, `bell-ring` and `zap`.
- `web/src/app/header/header.ts:32` -- `<img class="mark" src="assets/brand/icon-192.png" alt="">`; `web/scripts/brand.mjs` copies it.
- `web/src/app/about/about-dialog.ts:28-32` -- the new-tab link pattern.
- `web/src/styles/tokens.css` (generated, read-only):
  - colours: `--sunken` `:6`, `--ink-muted` `:11`, `--danger-ink` `:30`, `--link-foreground` `:221`;
  - type: `--type-display-md-*` `:45-48`, `--type-body-sm-*` `:74-77`;
  - components: `--chat-panel-*` `:300-302`, `--chat-message-user-*` `:303-309`, `--chat-message-ocutalon-*` `:310-316`, `--turn-indicator-*` `:334-338`, `--new-messages-button-*` `:339-343`, `--outcome-chip-*` `:344-359`, `--composer-*` `:364-371`.

  `scripts/shell-styles.test.mjs` fails on an undeclared `var(--x)`.
- `web/src/styles/base.css` -- the reduced-motion rule `:101-111` (durations only, so the dots need their own `animation: none`); `.visually-hidden` `:113-123`.
- `angular.json:54-58` -- the component style budget is 4 kB (warning) and 8 kB (error), so keep component styles small.
- `web/package.json:9-17` -- `build` = tokens `--check` + payloads `--check` + brand + `ng build`; `test` = `node --test scripts/*.test.mjs`.
- `web/scripts/payloads.mjs` -- the generator pattern (its header, `parseArgs`, fixtures by option), with `emitOutputs` from `tokens.mjs:395-416`.
- `web/scripts/live-store.test.mjs:1-15` -- a `.ts` module imported directly; types-only imports.

**Browser tests (Lane B, edit)**
- `web/playwright.config.ts:26-33` -- `chromium` takes every spec outside `demo-path/`; one worker; 45 s tests.
- `web/e2e/support/iris.ts`:
  - `fixtureUser` union `:15-17`;
  - `irisScript` `:39-54`;
  - `chk` `:57-60`;
  - `literal` `:63-66`;
  - `publishReminder` `:69-84`, the pattern for a seeding helper.
- `docker/tests/test-sign-in.sh`:
  - the user names and passwords `:35-48`;
  - the role loop `:106-118` (chat fixture `:108`);
  - the redaction in `show_log` `:152`;
  - the env vars `:154-176`.
- `web/e2e/demo-path/01-page.spec.ts` -- the floor test and `notBuilt('the chat panel and the composer', '2.5')`; `not-built.ts:11`. The demo-path stack has "no fixture user, no seeded event … no model key" (`docker/tests/test-demo-path.sh:12-13`).
- `web/scripts/playwright-projects.test.mjs:91-95` -- the `@floor` titles of `01-page`, exactly one today.
- `web/scripts/demo-path-summary.test.mjs` -- `:339-361` runs the real specs with `--grep-invert @floor` and no stack, so a real untagged test there would fail. The baseline at `:56-58`, `:91` and `:105` is synthetic and stays, as does `docker/tests/test-demo-path-gate.sh:134-151`.
- `web/e2e/sign-in/shell.spec.ts:36-42` -- row 8: "main holds its hidden heading and nothing else" (`toHaveCount(1)`), and exactly one h2 in main.
- `web/e2e/frame/frame.spec.ts`:
  - F1 `:76-77` -- the h2 list `['Status','Chat']` and the h3 list `RAIL_LABELS`;
  - `:92` -- no positive tabindex;
  - F2 `:109-112` -- main's x and width;
  - F3 runs with demo mode on.
- `web/e2e/live/live.spec.ts`:
  - L4 `:223-243` -- applying an event fires no `focusin`;
  - L5 `:245-287` -- while loading, 3 `.skeleton`, 1 `.chat-bubble` and no `app-server-button`; the static check is `toHaveCSS('animation-name','none')` `:277`.
- `web/e2e/api/api.spec.ts`:
  - row 13 `:109-124` -- README's `chat` `[]` and its stream counts;
  - row 14 `:161`, `:176-213`;
  - the `CHAT` user's chat is pinned at `:474-488`.
- `web/e2e/sign-in/helpers.ts:31-40` -- `watchViolations`; `README_ACCOUNT` and `signInReadme`.
- `web/e2e/session/session.spec.ts` -- S1 `:67-114` and S8 `:296-325` hold small chats; the cap leaves them unchanged.

**Server (Lane B, edit)**
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - the parameters `:23-45`;
  - `StateBody` `:253-290`: `streams` first `:255-258`, then `ChatItems` `:260`;
  - `ChatItems` `:290-327`: `Ownership.Turns` + `Incidents`, merged into `merged("T"_time, rank, id)` and pushed in ascending order;
  - `RailBody` `:331-347`: `Decisions(sessionRef, 20)` `:343` is the in-repo precedent for a snapshot cap;
  - `PayloadObject` `:372-376`, `Check` `:393`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - wrappers: `Turns` `:75`, `Decisions` `:119-122` (`+max`), `Incidents` `:126-129` (`LocalFlag()` as `a`), `LocalFlag` `:199`;
  - `Rows` `:211-254`: the `args...` bind expansion `:228-235`, the refusals `:215-219`;
  - `Statement` `:259-311`: `decisions` `:286-289` is `TOP ?` with `ao`, and `incidents` `:290-293`.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls`:
  - `TestStateBody` `:70` (keys `:98`);
  - `TestStateSections` `:158` (chat `:198-199`; 20 of 22 decisions `:220-221`, the pattern for the cap test);
  - `TestCursorsAreReadBeforeTheSections` `:246`;
  - the helpers `StateJob` `:919`, `Refs` `:953`, `Items` `:963`.
- `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls`:
  - `TestOrders` `:257` (`Decisions(a,2)` `:281`);
  - `TestIsolationEveryRowKind` `:300` (kinds `:308`);
  - `TestRowsRefuses` `:328` (the further-argument loop `:357`);
  - `Seed` `:445`, `ReadAll` `:464`.
- `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls` -- `Session` `:14`, `Turn(sessionRef, createdAt, state, text, clientId, attempt)` `:27`, `Incident(ownerRef, noticedAt, …)` `:73`, `Clean(refs)` `:212`.
- `ci/units.sh:49` -- `WEB_INPUT_PATTERN`, which holds `Live/` because the web build reads it. The catalog generator's two inputs must join it. Pinned by `docker/tests/test-ci-changes.sh` (`paths_case` `:190`) and `ci/mock/test/constants.test.mjs:123-131`.

**Read-only**
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls`:
  - `XData Entries [ MimeType = application/json ]` `:14-397`, one JSON object;
  - `conversation.turnFallback` `:157-163` (no `web` text);
  - `fallbackReason.*` `:181-234`.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls` -- the slot-type contract `:1-30`; `REASONKEYS` `:44` (`invalid` and `unusable` map to `generic`).
- `src/ocutalon/cls/OcuTalon/Web/Public/Shell.cls:104-108` -- sends `script-src 'self'` for `index.html`; pinned by `Test/Web/Shell.cls:47,53`.
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls:564-589` -- `Recap` reads `Ownership.Turns` (unchanged).
- `docker/tests/test-production-restart.sh:66-73,185-193` -- compares the whole snapshot of a one-turn session (unchanged under the cap).
- UX:
  - `EXPERIENCE.md`:
    - time `:174`;
    - link names `:219`;
    - the bubble and reply `:251-252`;
    - the chip meanings `:258-262`;
    - the indicator, composer and empty panel `:264-272`;
    - the busy rule `:381-384`;
    - new tabs `:391`;
    - the announcer `:419` (Story 2.12's);
    - the catalog `:743`, `:750-760`.
  - `DESIGN.md`:
    - `chat-text-max` `:183`;
    - `chat-panel` `:349-351`;
    - the chip icons `:378-396`, `:615`;
    - the components `:790-800`.
  - Mockups: `mockups/main-page.html:431` (caption "From the demo guide · 14:11"), `:496` (placeholder); `mockups/states.html:291-301`, `:968-983` (empty panel).

## Tasks & Acceptance

**Execution:**
- **Task 0** (implement stage, slot B, before `ChatItems` changes; record under `## Verification`). A temporary `TestMeasureChatCap` in `Test.Web.Api` does the following, and is removed afterwards (`grep -rn MEASURE src/` finds none):
  - it seeds a fixture session with 1,000 `done` turns (200-character text, 1,000-character reply);
  - it calls `/state` three times through `StateJob`;
  - it logs `MEASURE` lines with the median time and the body's length.

  Run it once on the old `ChatItems` and once on the capped one. It only records; if the capped `/state` stays slow because Turn has no `CreatedAt` index, that becomes a `reopen_if` line, not a schema change.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- add the kinds `recentTurns` and `recentIncidents` to `Statement`, with the SQL in Boundaries. Prefer sharing the incident `WHERE` text with `incidents` and `incident` through one fixed class parameter over a third copy (Rule 2). Add the wrappers:
  - `RecentTurns(sessionRef, max As %Integer = 100, Output sc) As %ListOfObjects`, which calls `Rows("recentTurns", sessionRef, .sc, +max)`;
  - `RecentIncidents(sessionRef, max As %Integer = 100, Output sc) As %ListOfObjects`, which calls `Rows("recentIncidents", sessionRef, .sc, +max, ..LocalFlag())`.

  Each returns newest first. Why: DW-65 under AD-13.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - add `Parameter CHATMAX = 100;` ("the most entries `/state`'s chat holds: the newest, oldest first (DW-65)");
  - `ChatItems` uses the two wrappers and keeps the newest `CHATMAX` merged entries in ascending order;
  - rewrite the `ChatItems` and `StateBody` comments.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` -- add `TestStateChatCapped`, which follows `TestStateSections`' fixture and clean-up:
  - the fixture: 103 done turns at 10:00:01 to 10:01:43, plus noticed own incidents at 10:00:00 and at 10:00:50, plus another session's turn;
  - `chat` has exactly 100 entries;
  - `Items(chat)` is turns 5-50, the incident, then turns 51-103;
  - the other session's ref is absent;
  - the number 100 is written out, never read from the parameter.
- `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls`:
  - `recentturns` and `recentincidents` join `TestIsolationEveryRowKind` (`:308`), `Seed`/`ReadAll` and `TestRowsRefuses`' further-argument loop (`:357`);
  - `TestOrders` gains `RecentTurns(a, 2)`, which gives the two newest turns newest first, and `RecentIncidents(a, 1)`, which gives the newest noticed incident only.
- `web/scripts/catalog.mjs` (new) and `web/src/app/msg/catalog.ts` (generated) -- the generator as in Boundaries.
  - It has a header like `payloads.mjs`'s, the options `--core <file> --catalog <file> --out <file>` (fixtures in tests), and `emitOutputs('catalog', …)`.
  - `catalog.ts` exports `PAGE_TEXTS` (key → text), `REASON_KEYS` (value → suffix) and `renderPageText(key, slots): string`. A slot value is trimmed and loses its control characters, as `Catalog.Render` does for a string slot.
- `web/package.json` -- add `"catalog": "node scripts/catalog.mjs"`; `build` runs `node scripts/catalog.mjs --check` after the payloads check.
- `ci/units.sh` -- `WEB_INPUT_PATTERN` gains `src/ocutalon/cls/OcuTalon/Msg/Catalog\.cls$` and `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core\.cls$`. Update its comment. `docker/tests/test-ci-changes.sh` gains a `paths_case`: a change to `Msg/Catalog/Core.cls` runs web and every group.
- `web/src/app/api/api-types.ts` and `api-client.ts`:
  - add `MessagePost {clientId: string; text: string; fromGuide: boolean}` and `MessageAccepted {clientId: string}`;
  - add `postMessage(body: MessagePost): Observable<MessageAccepted>` (`POST ${BASE}/messages`).
- `web/src/app/icon/icon.ts` -- add `eye-off`, `inbox`, `bell-ring` and `zap` to `IconName` and the switch, as Lucide paths like the others.
- `web/src/app/chat/page-time.ts` (new, node-tested) -- `pageTime(iso, locale?, timeZone?)`. Its defaults are the browser's.
- `web/src/app/chat/reply-text.ts` (new, node-tested) -- `parseReply(text): ReplyBlock[]`, where a block is a paragraph or a list (ordered or not) of inline runs, each `text` or `link {href, label}`. The grammar is in Boundaries.
- `web/src/app/chat/chat-view.ts` (new, node-tested):
  - `CHAT_TEXTS` holds every fixed string of the panel, from Boundaries ("Message OcuTalon", "Send", "Not sent", "Retry sending", "Deciding…", "Working…", "Working · {n} s", "{n} seconds", "New messages", "OcuTalon", "via Telegram", "From the demo guide", "(opens in a new tab)", the empty panel's headline and three lines, and the four chip labels and meanings);
  - `newClientId(random?)`;
  - `chatView(chat, outbox, runningSince, now)` → the entries to render: each turn with its key, text, time (ISO), caption, send state, and one of the reply states `none`, `deciding`, `working {seconds?}`, `text {replyText}` or `fallback {catalogKey, fallbackReason}`. The reply component calls `parseReply`, `renderPageText` and `pageTime` itself, so `chat-view.ts` imports no value from another module;
  - `isFreshChat(chat, outbox)`.
- `web/src/app/chat/chat-outbox.ts` (new, root service, signals) -- `entries`, `send(text, fromGuide = false)` and `retry(clientId)`. It posts with `timeout(BUSY_TIMEOUT_MS)` and prunes the entries the store now holds. `send` returns whether it sent.
- `web/src/app/chat/outcome-chip.ts`, `empty-chat.ts`, `user-message.ts`, `ocutalon-reply.ts` (the reply and the indicator), `composer.ts` and `chat-panel.ts` (new standalone OnPush components):
  - `chat-panel` reads `LiveState.store().chat` and `ChatOutbox`, keeps `runningSince` and the 1 s clock, and owns the scroll position, the **New messages** button and its focus target;
  - styles come from the tokens, each component within the 4 kB budget.
- `web/src/app/main-page/main-page.ts` -- render `<app-chat-panel>` in `main` after the h2 when loaded; `.main` becomes a flex column with `min-height: 0`; the rail gets `overflow-y: auto`. `web/src/app/app.ts` -- the host height is the viewport's (`height: 100vh`, then `100dvh`).
- `web/scripts/page-time.test.mjs`, `reply-text.test.mjs`, `chat-view.test.mjs`, `catalog.test.mjs` and `page-safety.test.mjs` (new; `node --test`; oracles written out):
  - **`page-time`**: `'2026-10-22T14:11:00Z'` in `Asia/Kolkata`/`en-US` gives "7:41 PM", and in `Europe/Berlin`/`en-GB` gives "16:11". Current ICU puts U+202F, the narrow no-break space, before "PM", so the oracle writes it as an escape.
  - **`reply-text`**:
    - blank lines split paragraphs, and a single line break is kept;
    - `- `, `* `, `• `, `1. ` and `1) ` lists;
    - a bare URL without its trailing period or unmatched `)`;
    - a `[label](https://…)` link;
    - `javascript:` and `data:` links stay text;
    - `<img src=x onerror=alert(1)>` stays text;
    - CRLF.
  - **`chat-view`**:
    - order and the outbox merge (a local entry is gone once a store entry has its `clientId`, even after `failed`);
    - every reply state, including "Working · 12 s"/"12 seconds" at 12 s and "Working…" at 9 s;
    - the captions;
    - `isFreshChat` (an incident alone is not fresh);
    - `newClientId` (22 characters `[A-Za-z0-9_-]`, two calls differ);
    - the string test: each `CHAT_TEXTS` value equals the UX's wording written out, and "Deciding…"/"Working…" hold U+2026, not "...".
  - **`catalog`**:
    - the generated file is current;
    - `renderPageText('conversation.turnFallback', {fallbackReason})` gives the AC's sentence for each of the 12 `FALLBACKREASON` values and for an unknown one (the generic);
    - on fixtures, the generator fails on a missing listed key, on a listed key with a `time` slot, and on a broken `XData` block.
  - **`page-safety`**: no `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `DomSanitizer` or `bypassSecurityTrust` in `web/src` (the source scan of `shell-styles.test.mjs`).
- `web/e2e/support/iris.ts` -- `'PANEL'` joins the `fixtureUser` union. Add `seedTurns(user, turns, publish)`:
  - **What it does.** It writes `OcuTalon.Data.Turn` rows for the user's session (`Session.ForUser`) with `Ref` and `ItemId` from `NewRef()`, `State` `done`, `CreatedAt`, `Channel`, `FromGuide`, `Text` and `ReplyText`. With `publish`, it publishes each row's `ChatMessage.FromRow` on the session stream, after its save.
  - **What it returns.** The refs and seqs, through `CHK|` lines.
  - **How values reach the script.** Every value goes through a literal helper that doubles quotes and writes control and non-ASCII characters as `$Char(n)`.
- `docker/tests/test-sign-in.sh` -- the fixture user `ZzPanel` (the user role, "panel fixture"): its password beside the others, the role loop, the `show_log` redaction, and `OCUTALON_PANEL_USER`/`_PASSWORD`. Update the pass line's list of specs.
- `web/e2e/chat/chat.spec.ts` (new; chromium project; the test titles are what the I/O matrix and the ACs cite):
  - **C1** (README, sends nothing): the empty chat panel exactly as in Boundaries, within `main`. The composer has the name "Message OcuTalon", and a "Send" button. `main` holds no `aria-live` and no `role` `log`, `status` or `alert`. A reload's document answer carries `content-security-policy: script-src 'self'`, and `watchViolations` is empty.
  - **C2** (PANEL, `timezoneId` `Asia/Kolkata`, `locale` `en-US`), sending with Enter:
    - the POST body has a 22-character `clientId`, the trimmed text and `fromGuide` false;
    - the bubble is right-aligned on `--sunken` and at most 80% of the list's width, and its time equals the turn's `createdAt` formatted in that zone;
    - the field is empty and focused.

    Then, with a route that answers each `/events` poll with the real answer cut to its first event:
    - a `MutationObserver` log of the turn's indicator and reply texts reads "Deciding…", then "Working…", then "I couldn't answer that: the model's reply couldn't be used. Nothing was changed.";
    - the reply sits under the avatar and "OcuTalon".
  - **C3** (PANEL):
    - Shift+Enter adds a line and makes no request;
    - 3 lines make the field taller, and 8 lines leave it at its 5-line height with `scrollHeight > clientHeight`;
    - the field keeps its name with text in it;
    - with the `/events` route holding the turn at "Deciding…", the composer is enabled and a second message is sent. That makes two 202s with different `clientId`s and two replies in send order.
  - **C4** (PANEL), a failed send in three cases:
    - the first POST aborted;
    - the first POST passed to the server and its answer replaced by 503, with `/events` withholding the events until the retry;
    - a POST that is never answered, which gives "Not sent" after 10 s.

    Each shows "Not sent" and **Retry sending**. A retry posts the same `clientId`, and `/state` then holds exactly one turn with it.
  - **C5** (PANEL), after `seedTurns` and a reload:
    - the turns are in `CreatedAt` order;
    - "via Telegram · {time}" and "From the demo guide · {time}";
    - a reply with two paragraphs, both lists, a bare link and a `[label](https://…)` link. Each link has `target=_blank` and `rel` `noopener noreferrer`, and an accessible name ending "(opens in a new tab)";
    - a `javascript:` link and `<b>x</b><img src=x onerror=…>` show as text, with no `b` and no `img` in the reply;
    - a long paragraph is no wider than a `72ch` probe in the same font.
  - **C6** (PANEL), scrolled up:
    - `seedTurns` makes 30 turns and the page reloads; the list starts at the bottom; scroll it to the top;
    - `seedTurns(…, publish)` adds one turn; within 2 s of its publish, `main[data-session-seq]` reaches its seq and its element is in the list (FR-12);
    - `scrollTop` and the first visible entry's box are unchanged;
    - **New messages** is visible, with `chevron-down`, centred over the composer and above it; Shift+Tab from the composer reaches it;
    - pressing it puts the list at the bottom, focuses the new turn's element and hides the button.
  - **C7** (PANEL), with a turn held at "Deciding…":
    - with `reducedMotion: 'reduce'`, the dots have `animation-name` `none`;
    - with `'no-preference'`, they don't.
- `web/e2e/sign-in/shell.spec.ts` row 8 -- main holds its hidden heading, the empty chat panel and the composer. It still has exactly one h2, "Chat". Search `web/e2e` for other assertions on `main`'s contents and update any that read the old shape.
- `web/e2e/demo-path/01-page.spec.ts` -- replace the `notBuilt` call with the `@floor` test "shows the empty chat panel and the composer":
  - README sign-in;
  - the headline, the four chips with their meanings and the first two lines;
  - "Message OcuTalon" and "Send";
  - Shift+Enter adds a line and no `POST /messages` request is seen;
  - no live region in `main`;
  - `watchViolations` empty.

  `web/scripts/playwright-projects.test.mjs:94` -- the floor titles are both tests, in file order.

**Acceptance Criteria:**
- **The panel (FR-6, FR-12, UX-DR58).**
  - **Given** the main page has loaded, **when** the chat panel renders, **then** it is inside the `main` landmark, with text lines capped at `chat-text-max` and entries spanning the column. It shows the session's conversation from the snapshot in order and adds `chat.message` updates as they arrive, within 2 s. Nothing in it is a live region or `role="log"` (C1, C5, C6, `chat-view.test.mjs`).
  - **Given** a fresh session, **when** the panel renders, **then** the empty chat panel shows exactly the headline, the four chips with their meanings and the three lines, until the first message (C1, `chat-view.test.mjs`).
- **The composer (NFR-6, UX-DR68, UX-DR125).**
  - **Given** the composer, **when** I type and press Enter or **Send**, **then**:
    - it sends the text with a new `clientId`;
    - Shift+Enter adds a line;
    - it grows to 5 lines, then scrolls;
    - it stays labelled "Message OcuTalon";
    - it stays usable during a turn, and each message becomes its own turn

    (C2, C3).
- **The bubble (FR-12, UX-DR59, UX-DR123).**
  - **Given** a sent message, **when** it renders, **then** it is a right-aligned `sunken` bubble at most 80% wide, with its text and its time in the browser's zone. A Telegram turn says "via Telegram", and a `FromGuide` turn says "From the demo guide" (C2, C5, `page-time.test.mjs`, `chat-view.test.mjs`).
  - **Given** a message, **when** its post fails, **then** the bubble keeps the text and shows "Not sent" with **Retry sending**, which resends the same `clientId`. A send that reached the server is not queued twice (C4, `chat-view.test.mjs`).
- **The reply (AD-13, UX-DR42, UX-DR60).** **Given** a reply arrives, **when** it renders, **then** it is left-aligned and unboxed under the 24px mark avatar and "OcuTalon", as paragraphs and lists. Model-written text renders as text, never HTML: nothing in `web/src` calls `bypassSecurityTrust*` or writes HTML, and the page sends `script-src 'self'`. Its links open in a new tab and say "(opens in a new tab)" in their names (C5, C1, `reply-text.test.mjs`, `page-safety.test.mjs`).
- **The turn (FR-4, NFR-8, UX-DR14, UX-DR66).**
  - **Given** a turn in progress, **when** its stages arrive, **then**:
    - the indicator shows "Deciding…" until the decision lands (`running`), then "Working…" until the reply, and "Working · 12 s" (spoken "12 seconds") after 10 s;
    - the reply replaces it, a fallback reply included;
    - its dots are static under reduced motion;
    - it is not a live region

    (C2, C7, `chat-view.test.mjs`).
  - **Given** a turn whose stages arrive in separate polls, **when** the page applies them, **then** the decision (`running`) is on the page before its reply, and CI asserts that order (C2's log). NFR-8's 10-second bound is measured in the clean-machine rehearsal on Claude Haiku 5.5, not here.
  - **Given** a fallback reply, **when** it renders, **then** it reads "I couldn't answer that: {reason}. Nothing was changed.", with each of the 12 reasons in the UX's words (`catalog.test.mjs`, C2).
- **Scrolling (UX-DR67, UX-DR126).** **Given** I have scrolled up, **when** new content arrives, **then** the chat doesn't move, and a "New messages" button with `chevron-down` shows, centred above the composer and just before it in tab order. Pressing it scrolls down and focuses the first new message (C6).
- **The demo path (REL-2, AD-29).** **Given** the demo-path project, **when** step 1 runs, **then** its `@floor` test checks the chat panel and the composer, and the step summary reads `STEP 1 page: partly skipped, 2 passed, 3 skipped (Story 4.7: …)` (`01-page.spec.ts`, `live demo-path`, `playwright-projects.test.mjs`).
- DW-65: **Given** a session with more than 100 chat entries, **when** `/state` loads, **then** its chat holds the newest 100, oldest first, merged as before. Each new row kind returns none of another session's rows (`TestStateChatCapped`, `TestOrders`, `TestIsolationEveryRowKind`).

## Spec Change Log

- 2026-10-22, spec validation (lead):
  - The 100-entry cap on `/state`'s chat (DW-65) is ruled as planned (veto, inbox U-24).
  - Reply links open in a new tab, following the story's criteria and UX-DR60. The conflict with EXPERIENCE:391 and UX-DR127 is noted in U-24 for the UX owner.
  - The spine's Conventions rows "Live events" (the cap) and "Text OcuTalon sends" (the generated page catalog) are amended (Rule 20). The cap is not written into AD-12, because a runner never amends an AD alone (U14).
  - DW-65 is addressed, and no decision-pending entry is built on.

## Review Triage Log

### 2026-10-22 - Review pass
- verdicts: 54 findings - high 0, medium 6, low 47, false 0, maybe-false 1
- findings (Blind Hunter 1-12, Edge Case Hunter 13-25, Verification Gap 26-45, Intent Alignment 46-54; a repeat of an earlier row says so and shares its route):
  - 1 `[low]` `patch` `Msg/Enum.cls` is missing from `WEB_INPUT_PATTERN` although `catalog.test.mjs` reads it - added to the pattern and a `paths_case` in `test-ci-changes.sh`; mutation red.
  - 2 `[low]` `reject` A bare link keeps trailing `**`, backticks, quotes or `]`; nested list lines flatten - the grammar is the contract's ("without trailing `.,;:!?` or an unmatched `)`"; list lines by their prefix), and whether the chat agent writes Markdown is Lane A's instruction (Decided 2); a wider grammar is a spec change.
  - 3 `[medium]` `reject` A `[label](url)` label can name another address (a phishing shape if injected content steers the model) - the link form is the contract's (UX-DR60); showing the destination is new public text and a security-posture call, which is a spec edit; the browser shows the target on hover and focus; named under Residual risks for the lead.
  - 4 `[low]` `patch` A `catalogKey` the page does not render showed the generic reason, which may be false - it now shows the `conversation.turnFallback` sentence with the turn's own reason (the server sets only that key today); Decided 24 amended.
  - 5 `[low]` `reject` A chat with only incidents or notices draws nothing - spec-bound (`isFreshChat` counts every type, Decided 11); ends with Stories 6.1 and 2.7.
  - 6 `[low]` `reject` The 100-entry cap counts entries the panel does not draw and says nothing - ruled by the lead (veto U-24, Decided 20 "no affordance").
  - 7 `[low]` `reject` `TOP ?` still sorts the session's rows without an index - Decided 20 says so; Task 0 measured 3.4 ms and 138 KB at 1,000 turns.
  - 8 `[low]` `reject` The reverse merge's hard cases are untested (incidents alone over the cap, a tie at the cut, instance incidents, `max` of 0 or less) - the walk is generic, `max` is only the `CHATMAX` constant, and the matrix row has `TestStateChatCapped`.
  - 9 `[low]` `reject` A permanent failure (a 400 for control-only text) reads as transient; a 401 leaves the entry `sending` - Decided 7 covers the 400, and a 401 is `SessionGate`'s, which leaves the page.
  - 10 `[medium]` `patch` The elapsed-seconds path has no browser test, and `turns` writes the `since` map - C8 added (see 28); the impure computed and the unpruned map are bounded by the session's turns and left.
  - 11 `[low]` `reject` `CHAT_TEXTS.seconds` is unused - the spec lists "{n} seconds" in `CHAT_TEXTS`, and Story 2.12's announcements use it.
  - 12 `[low]` `reject` C6's 2 s bound has little slack - it is the AC's bound (FR-12); loosening it edits the AC.
  - 13 `[maybe-false]` `defer` The at-the-bottom flag can flip to false when an entry lands between the panel's own scroll and its scroll event - plausible by event order, not reproduced by C10 (8 sends and replies in a 30-turn chat), C6 or C9; medium if true; deferred as unverified.
  - 14 `[low]` `reject` The composer keeps a stale height after a width change - rare; fixing it adds an observer; Story 2.12 owns the narrow layouts.
  - 15 `[low]` `reject` Safari sends on the Enter that confirms an IME candidate - the contract's rule is `isComposing`; the WebKit runs are Story 2.12's.
  - 16 `[low]` `reject` Control-only text answers 400 (repeat of 9).
  - 17 `[low]` `reject` Trailing markup on a bare link (repeat of 2).
  - 18 `[low]` `patch` A known key other than `turnFallback`, or an unknown one, shows a wrong reason (repeat of 4); a known fragment key as `catalogKey` has no producer.
  - 19 `[low]` `reject` A repeated REASONKEYS value would write a duplicate key - `Catalog.cls` is server code pinned by `Test.Msg.Catalog`; no user path.
  - 20 `[low]` `reject` A `fallbackReason.*` entry with a slot would show a raw placeholder - an author-time case with no such entry; the generator already rejects undeclared placeholders.
  - 21 `[low]` `patch` `Enum.cls` missing from the web inputs (repeat of 1).
  - 22 `[low]` `reject` `max` of 0 or less on the wrappers (repeat of 8).
  - 23 `[low]` `reject` A queued or running turn outside the newest 100 entries would reappear last - it needs 100 newer entries while one turn runs.
  - 24 `[low]` `reject` `seedTurns` keeps going when `ForUser` fails - the helper throws unless every save reports 1; a test helper.
  - 25 `[low]` `reject` The page cleans a reason value more leniently than the server - the value is the server's own `FallbackReason`, always exact.
  - 26 `[medium]` `patch` "Only a 202 is a success" is untested for a 2xx - C4 case "an answer other than 202" added; mutation red.
  - 27 `[low]` `reject` The outbox's 401 branch is untested - the effect is invisible, as `SessionGate` leaves the page; reopen_if a 401 keeps the page.
  - 28 `[medium]` `patch` The elapsed indicator never runs in a test - C8 added (real 10 s, visible and spoken text, no live region); mutation red.
  - 29 `[medium]` `patch` "Not a live region" was asserted only where no indicator, failed entry or button shows - C7 (indicator), C4 (failed entry), C6 (button) and C8 (working time) assert it; mutation red in C7.
  - 30 `[medium]` `patch` The scrolled-up branches (a reply landing on an existing turn, Send while scrolled up, scrolling down by hand) are unexercised - C9 added; three mutations red.
  - 31 `[low]` `patch` Missing adoption of `Msg/Enum.cls` (repeat of 1).
  - 32 `[low]` `reject` The step-1 summary line is asserted nowhere and its fixtures show the pre-2.5 shape - the spec keeps the synthetic baseline and `test-demo-path-gate.sh:134-151`; `live demo-path` prints the line and the two floor tests gate it.
  - 33 `[low]` `patch` The rail's `overflow-y` and the app's height are untested - C1 asserts the app fills the viewport, the page does not scroll, and the rail and list scroll on their own; mutation red.
  - 34 `[low]` `reject` `window.__pwned` cannot fail on its own - it backs the `b, img, script` count, which carries the red.
  - 35 `[low]` `patch` The chip icon check holds for an icon with no path - C1 asserts a drawn path per chip; mutation red.
  - 36 `[low]` `reject` The default-zone `pageTime` test compares the same call - by design; the explicit-zone tests and C2 pin the zone.
  - 37 `[low]` `patch` C4's "arrives anyway" never saw the failed state - the events are held until "Not sent" shows.
  - 38 `[low]` `reject` C3's negative checks read `posts()` with no settle - the IME and empty-text mutations went red.
  - 39 `[low]` `reject` C1, the floor test and `shell.spec` row 8 assume the README chat is empty - the spec's premise (the README account is only read, api.spec posts as the CHAT user).
  - 40 `[low]` `reject` C5 and C6 leave seeded turns on the PANEL session - each run has a fresh throwaway (`retries: 0`) and each test asserts its own refs; reopen_if a spec runs twice on one stack.
  - 41 `[low]` `reject` C2's reply log follows the last reply - the live-appended turn is the last one, and one worker runs.
  - 42 `[low]` `reject` C6's 2000 ms bound (repeat of 12).
  - 43 `[low]` `reject` Mutation lines are missing for sub-claims of the ACs - Rule 19 asks one per AC and each AC has one or more; lines were added for every test added here.
  - 44 `[low]` `reject` A 401 leaves the entry `sending` (repeat of 27).
  - 45 `[low]` `patch` C3's `oneLine` is measured with two lines - renamed `twoLines`.
  - 46 `[low]` `patch` The send scroll sits at the composer-to-panel event, not at `ChatOutbox.send` - `ChatOutbox.sendCount` now drives it, so a guide send scrolls too (Decided 32).
  - 47 `[low]` `reject` DW-65 is pinned at class level, not over HTTP - `TestStateChatCapped` runs the body `/state` returns; the matrix row names the chat.
  - 48 `[low]` `patch` "Working - N s" is covered in node only (repeat of 28).
  - 49 `[low]` `reject` The browser shows one of the 12 reasons - `catalog.test.mjs` covers all 12 on the module the page uses, and C2 covers the wiring.
  - 50 `[low]` `patch` A reply landing while scrolled up is unexercised (repeat of 30).
  - 51 `[low]` `patch` The layout is unasserted (repeat of 33).
  - 52 `[low]` `patch` No live-region check while the indicator, a failed entry or the button shows (repeat of 29).
  - 53 `[low]` `patch` "No composer while loading or failed" is unasserted - L5 and L7 assert no panel and no composer; mutation red in both.
  - 54 `[low]` `reject` Incident and notice entries, and a local `fromGuide` caption, are covered in node only - the page has no path for them before Stories 6.1, 2.7 and 4.4.

## Design Notes

**Governing ADs and conventions (Rule 6).**
- **AD-4:** the session only from `Ownership`, so the page sends no session reference.
- **AD-12:** the snapshot and polling; full views keyed by `Ref`; idempotent apply; the cap keeps the snapshot's shape.
- **AD-13 as amended:** text rendered as text, no `bypassSecurityTrust*`, `script-src 'self'`; the two new row kinds with isolation tests; the request headers through the interceptor.
- **AD-22:** Playwright under `web/e2e/`, fixture users, throwaway stacks.
- **AD-29:** the demo-path spec, the `@floor` convention, and Lane B's footprint.
- **AD-30:** the `clientId` dedup; each message a turn; the stages.
- **AD-32 and the Conventions row "Text OcuTalon sends":** the page renders from the catalog classes.
- **AD-33:** `chat.message` has one publisher. Test helpers publish fixtures, as `publishReminder` does.
- **Conventions rows:** Angular (standalone components, signals, one typed client, one live-event service), Identifiers (the `clientId`'s shape), Times, Tests (demo-path naming, `notBuilt`, `@floor`), and Fonts and icons (bundled Lucide paths, ISC, under the existing notice).

No AC contradicts an AD's Rule. Rule 5: NFR-6 and FR-12's 2 s are measured in CI. NFR-8 is measurable as worded; the AC places it in the rehearsal.

**Decided in-stage** (small, reversible, within the intent):
1. **The fallback sentence comes from a generated module.** The Conventions row says "Only `*Out` operations (and the page) render, from the catalog classes", and nothing served catalog text to the page. A generated module keeps one source of truth, as `payloads.mjs` does for payloads. Its allowlist holds only the keys the page renders, and its renderer handles only the slot types they use. Later stories add keys and types.
2. **The markup subset.** UX-DR60 and EXPERIENCE:252 say "plain paragraphs and lists". So paragraphs, the two list forms and http(s) links are recognised, and every other character shows as typed. No UX rule names bold, code or headings. Whether the chat agent writes Markdown is Lane A's instruction (inference).
3. **Reply links open in a new tab.** The AC, UX-DR60 and EXPERIENCE:252 say so. EXPERIENCE:391 and UX-DR127 limit new tabs to Visual Trace and README links. The specific rule for a reply's links, which the AC repeats, is followed. The general rule is read as being about the page's own links. Flagged for the UX's owner.
4. **Elapsed time counts from when this page first saw the turn `running`**, on the page's clock, so a skew between the browser's and IRIS's clocks can't show a wrong figure. "Working · 12 s" names the working time. After a reload mid-turn it restarts.
5. **Which state shows "Deciding…".** A 202 (`sent`) or a `queued` turn shows "Deciding…", as 2.4's Decided 3 planned. A post still in flight, or a failed one, shows no indicator.
6. **The dots** are the "…" glyph revealed in three steps. That keeps the exact string "Deciding…" and still gives DESIGN:796's three animated dots. Under reduced motion they have `animation: none`, which a test can assert (the global rule only shortens durations).
7. **Send is optimistic and is not an `app-server-button`.** EXPERIENCE:381-384's busy-and-failure rule gives way to UX-DR59's per-message "Not sent", because the composer must stay usable mid-turn (UX-DR68).
   - The 10 s limit is the same `BUSY_TIMEOUT_MS`.
   - A 429 shows "Not sent" until Story 16.9 builds the refusal.
   - A 400 can't come from the page, because empty text is never sent and the id is 22 characters; if one does, it shows "Not sent".
8. **The `clientId`** comes from `crypto.getRandomValues`, with the Identifiers convention's 22-character base64url shape. `crypto.randomUUID` needs a secure context, and a local install may be served over plain HTTP on a LAN name.
9. **Sending.** The text is trimmed at both ends, and inner line breaks stay, so a trailing Shift+Enter adds no empty line.
10. **Scrolling.**
    - A send of this page scrolls to the bottom: it is the user's own action, not content arriving.
    - Content from elsewhere never moves a list that is scrolled up.
    - The list counts as at the bottom within 24 px, and the first load scrolls to the bottom.
11. **What "fresh" means.** The empty panel needs no entry of any type and no message of this page pending. An `incident` or `notification` entry renders nothing until Story 6.1 or 2.7, so "fresh" doesn't depend on what the page can draw yet.
12. **The headline is a `<p>`.** F1 pins the heading lists, and the headline is a statement, not a section. The last line is always the non-demo one; Story 4.4 adds the demo line.
13. **No reply time.** The UX text gives none, and a `Turn` has no reply time.
14. **The composer renders only once loaded.** That keeps L5's loading view: 3 skeletons and no `app-server-button`.
15. **Layout.** The app fills the viewport's height, so the list scrolls on its own and the composer stays at the bottom of `main`. The rail scrolls on its own. Story 2.12 owns the stacked layout below 1024 px.
16. **A failed message is not kept across a reload.** The outbox lives in the page.
17. **The outcome chip is built here**, because the empty panel needs it. Story 2.6 extends it with the tooltip and the strip description.
18. **The caption form** "via Telegram · 14:11" follows the mockup (`main-page.html:431`). The bubble's time has no zone suffix: EXPERIENCE:174 gives that suffix only to times in cards.
19. **The order test needs one event per poll.** The 2.5 order assertion is the `running` stage on the page before `done`; Story 2.6 adds the `decision` event and its strip. The stub `Decide` answers at once, so two stages can share one poll. C2 therefore passes the real `/events` answers through one event at a time, which is how a real model's turn arrives, and checks the page's order.
20. **DW-65: the cap is 100, with no affordance.**
    - **Why 100.** The rail already caps decisions at 20, and the recap uses 20 turns. 100 entries is a long working session. On the online demo, the allowance (50 an hour) and the reset bound a session anyway.
    - **What the reads save.** `TOP ?` with a bound value is proven in this repo (`decisions`, `Live.Event.Since`). The newest-first reads plus the merge keep the snapshot's order with no subquery. They still sort the session's rows, because Turn has no `CreatedAt` index, but they no longer open, export and parse every row. Task 0 records the effect.
    - **No flag.** No flag or "earlier messages" text is added, because the bullet asks for a cap within AD-12's shape, and a flag would change the key list and need new public text.
21. **The time's day-period space.** `page-time.test.mjs` reads the space before AM or PM as either U+0020 or U+202F. The runtime that runs it (Node 26 with ICU 78) writes a plain space, and the spec's oracle assumed U+202F; the page uses `Intl.DateTimeFormat` as it is, so the browser's own form shows. C2 and C5 compare with the narrow no-break space read as a space.
22. **The outbox entry also holds `fromGuide`.** `{clientId, text, fromGuide, sentAt, status}`: Retry sending posts the same body again, and the caption of a guide message must survive until the server's entry arrives.
23. **Only a 202 is a success.** `ApiClient.postMessage` observes the response and fails any other status, a 2xx included, as the matrix says ("a non-202 status"). The body is `MessageAccepted`.
24. **A catalog key the page does not render** (an entry of a later story, such as the allowance texts) shows the `conversation.turnFallback` sentence with the turn's own reason (the generic reason when that is unknown too), never a blank or the raw key. The story that renders that key adds it to `catalog.mjs`'s allowlist.
25. **Reply markup details** (within Decided 2). A list ends at a list line of the other kind, a plain line or a blank line; a numbered list keeps its first number (`start`); a list line needs text after its marker (`-x`, `1.5 is` and a bare `- ` are text); a paragraph keeps its own leading spaces; a scheme in capitals still links; `new URL` must accept the address as http(s) with a host, or it stays text.
26. **One element for the indicator and the reply.** The reply's place is one element (`data-part="reply"`, `tabindex="-1"`), so the New messages focus has one target and the DOM node survives the change from indicator to reply. The indicator row is the 24px mark and the text (no name); the reply adds the name. After 10 s the visible "Working · 12 s" is `aria-hidden` and a visually hidden "Working · 12 seconds" follows it.
27. **New messages focuses with `preventScroll`.** The press scrolls the list to the bottom first, so the focus must not scroll it back up to an entry above the view.
28. **A new entry's focus target is its user message, a landed reply's is the reply.** "Changed" means a reply that landed (the matrix's "new entry, or a reply that lands"); the indicator's states and its seconds never show the button.
29. **The generator also fails closed** on a listed key with a `one` form, with a placeholder that is no declared slot or with a stray brace, on a reason of REASONKEYS whose `fallbackReason.*` key is missing, and on a missing `fallbackReason.generic`.
30. **The fixture tests.** `TestStateChatCapped` removes its own rows with `Fixture.Clean(refs)`. C4 has a fourth case, "a failed post whose turn then arrives by poll leaves no Not sent" (the matrix's "Arrives anyway"). C6 allows 2 s from the return of `seedTurns` (which runs after the publish), a stricter bound than 2 s from the publish. `iris.ts` exports `quoted()`, the literal helper of `seedTurns`.
31. **Matrix audit additions (the Send row's error handling and the "at the bottom" row).** C3 sends nothing for empty text, space-only text, a click on **Send** over an empty field and an Enter inside an IME composition (a `keydown` with `isComposing`), sends its second message by a click on **Send** and asserts the field is empty and focused; C5 asserts no live region in `main` with entries rendered; C6 asserts that the list follows a turn that lands while it is at the bottom and that **New messages** stays hidden.
32. **A new message scrolls the list through `ChatOutbox`.** The outbox counts the new messages it sends (`sendCount`, a retry is not one), and the panel scrolls to the bottom when the count changes, so any caller of `send` (the composer now, the demo guide in Story 4.4) gets the contract's "a new message scrolls the list to the bottom". The composer no longer has a `sent` output.
33. **Tests added after review (C4's 200 case, C8, C9, C10; assertions in C1, C3, C4, C6, C7, L5, L7).** C8 waits about 11 s in real time for the working time (the page's clock, not a fake one) with the done event held back; C9 covers a reply that lands on an existing turn, Send while scrolled up and scrolling down by hand; C10 sends 8 messages in a 30-turn chat and checks the list is at the bottom after each reply. C1 asserts the app fills the viewport, the page does not scroll, and the rail and the list scroll on their own; L5 and L7 assert no panel and no composer while loading or after a failed load.
34. **`ci/units.sh`'s `WEB_INPUT_PATTERN` also names `Msg/Enum.cls`**, which `catalog.test.mjs` reads to compare the 12 fallback reasons with the module; `test-ci-changes.sh` has its case.
35. **`chat.spec.ts` unroutes its routes after each test** (`page.unrouteAll({ behavior: 'ignoreErrors' })`), because a routed `/events` poll that is still being answered when a test ends is reported against the next test as `route.fetch: Test ended`; one clean run showed it.

**Veto-window items for the lead** (ruled at spec validation: kept as planned, veto inbox U-24; the implement stage builds as planned unless the owner reverses them):
1. **Weakening a guarantee? DW-65's cap.** After a reload, the page shows only the newest 100 chat entries; older turns stay in `Turn` rows and in Visual Trace. This reads FR-1's "the web chat shows every turn" as covering every channel's turns. It reads FR-6 and EXPERIENCE:340's "history intact" as being about what is kept. The alternative is paging: a `before` cursor, an "earlier messages" control and its text, a new key or endpoint, and UX text that doesn't exist yet. That would be a follow-on story if the owner wants it.

No other veto item:
- no schema, retention or storage change (two read statements);
- no new public text (every string is the UX's or the catalog's; the separator " · " is the mockup's);
- no new dependency (node built-ins and the existing Lucide icon set);
- the `ZzPanel` fixture user exists only on throwaway stacks, with the user role, as Stories 2.2 and 2.4's users do.

**Spine notes for the lead (Rule 20, light path):** written by the lead at spec validation, as Conventions rows rather than an AD-12 amendment: "Live events" gains the 100-entry snapshot chat cap (veto U-24), and "Text OcuTalon sends" names the generated page catalog.
- The Conventions row "Text OcuTalon sends" could add: the page renders catalog texts from `web/src/app/msg/catalog.ts`, which `web/scripts/catalog.mjs` generates from the catalog classes (an allowlist of the keys the page renders), and whose `--check` runs in the build. Decided 1 is a convention later stories would otherwise drift on: 2.6's `Checks.Render` keys and 2.7's notices.
- The REST surface row for `GET /api/v1/state` could add: "chat: the newest 100 entries, oldest first (DW-65)". Stories 2.7 (DW-62's notice cards) and 6.1 (incident cards) merge into this list.

AD-13 needs no change: its amendment provides for new row kinds.

**Integration ACs (Rule 1).**
- **The chat panel** (consumer) reads `LiveState.store().chat` (2.2) and posts through `ApiClient.postMessage` to `POST /messages` → `WebChatIn` → `Conversation` (2.4). Observable: the turn's bubble, its stages in order and its fallback reply on the page (C2, against a real throwaway stack).
- **`Web.Api.ChatItems`** (consumer) reads `Ownership.RecentTurns`/`RecentIncidents`. Observable: `/state`'s chat capped at the newest 100 (`TestStateChatCapped`).
- **The reply** (consumer) renders through the generated `catalog.ts`. Observable: the fallback sentence on the page (C2) and for every reason (`catalog.test.mjs`).
- **The demo path** (consumer) checks the panel and the composer on the README account (`live demo-path`).

**Consumed-by:**
- **2.6:** the outcome chip, the reply's place for the decision strip, the indicator's step label from `turn.step`, and `catalog.ts` for `Checks.Render`'s keys.
- **2.7:** notice cards in the chat list and in the capped snapshot; catalog keys.
- **2.9:** the turn's trace link (`traceHeaderId`).
- **2.12:** the announcements ("OcuTalon replied:", "Message not sent"); focus replacement when **Retry sending** goes; the epic string test extends `CHAT_TEXTS`; the Firefox and WebKit runs.
- **4.4:** the empty panel's demo-mode line, and guide sends through `ChatOutbox.send(text, true)`.
- **4.7:** step 1's other parts.
- **6.1:** the incident card in the list and in the cap.
- **16.9:** the 429, the composer's `aria-disabled` reason and the refused turn.
- **12.6 (Lane A):** Telegram turns show "via Telegram".

**Consumes:**
- Story 2.1: the frame, controls, icons and tokens;
- Story 2.2: `LiveState`, the store, the envelope, `SessionGate` and `/state`;
- Story 2.4: `POST /messages`, the `chat.message` stages and the `Turn` fields;
- Story 0.9: the catalog classes;
- Story 0.8: the demo-path harness.

The Integration ACs run against a real throwaway.

**Extend, don't copy (Rule 2).**
- `catalog.mjs` follows `payloads.mjs` and reuses `tokens.mjs`'s `emitOutputs`.
- `postMessage` joins the one typed `ApiClient`.
- The new-tab link follows `about-dialog.ts:28-32`.
- The avatar reuses the header's brand image.
- The chip icons join `icon.ts`'s switch.
- The row kinds extend `Ownership`'s fixed table, in the shapes of `decisions` and `incidents`, with the incident `WHERE` shared rather than copied a third time.
- `seedTurns` follows `publishReminder`.
- `TestStateChatCapped` follows `TestStateSections`.
- The node tests follow `live-store.test.mjs`; `page-safety.test.mjs` follows `shell-styles.test.mjs`'s source scan.
- No copy is planned.

**Ledger (Rule 17).** DW-65 is addressed: the cap, its two row kinds and `TestStateChatCapped`. It is not declined.

## Verification

Every IRIS MCP call names `server: ocutalon-slot-b` and `namespace: OCUTALON`, with one `iris_execute_tests` call per message. Every throwaway command is `OCUTALON_RUN_TAG=e2s25i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`. Each runs one piece per call with `timeout: 600000`, and the run ends with `teardown` on the same tag. A `LOCK busy` exit 75 is the other lane's contention: wait and run it again. Every other command runs in the foreground with `timeout: 600000`.

**Commands:**
- (loop) `iris_server_info` (`ocutalon-slot-b`). Expected: build 154, ports 1991 and 52791.
- (loop) `iris_doc_load` (`compile: true`, `flags: "ck"`) as two calls: `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls`. Expected: 0 errors.
- (once) Task 0: `iris_execute_tests` `OcuTalon.Test.Web.Api` with `TestMeasureChatCap`, before and after the `ChatItems` change; then remove the method. Expected: the `MEASURE` lines, recorded here. If the class nears the call's cap on slot B, run it as `ci/iris.sh class OcuTalon.Test.Web.Api` on the throwaway instead, and say so.
- (loop) `iris_execute_tests` on slot B, one class per message: `OcuTalon.Test.Web.Api`, `OcuTalon.Test.Data.Ownership`, `OcuTalon.Test.Web.Shell`. Expected: all pass, with no `zz` fixture row left.
- (loop) One call each: `npm --prefix web test`, `npm --prefix web run lint`, `node web/scripts/catalog.mjs --check`, `node web/scripts/payloads.mjs --check`, `node web/scripts/tokens.mjs --check`. Expected: exit 0.
- (loop) `bash docker/tests/test-web-build.sh`. Expected: exit 0, within the style budget, and no inline script.
- (loop) One call each: `bash docker/tests/test-class-rules.sh` (with `ALLOW_UNCHECKED` unchanged), `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-ci-changes.sh`, `bash docker/tests/test-mock.sh` (its `constants.test.mjs` reads `WEB_INPUT_PATTERN`). Expected: exit 0.
- (loop) Throwaway: `build`, then `live sign-in` (C1-C7, `shell.spec`, `api.spec`), then `live demo-path` (`STEP 1 page: partly skipped, 2 passed, 3 skipped (Story 4.7: …)`, floor 2 of 2), then `teardown`. Expected: each passes; teardown leaves nothing.
- (once) `bash ci/checks.sh`. Expected: exit 0.
- (once) Throwaway: `shard lane-b`, then `teardown`. Expected: every class passes.

**Planned mutations (Rule 19).** For each, the implement stage applies the mutation, observes red, restores a byte-identical tree (`git status --short` and `git diff --stat` unchanged), and records `mutation: … → …` here.

| AC | Mutation | Expected red |
| --- | --- | --- |
| Panel order | `chatView` reverses the store order | `chat-view.test.mjs`; C5 |
| Live updates | the panel reads `snapshot().chat` instead of `store().chat` | C6 (the published turn never shows) |
| Not a live region | `aria-live="polite"` on the list | C1 |
| Empty panel | the headline loses "one" | `chat-view.test.mjs` string test; C1 |
| Fresh | `isFreshChat` counts only `chat.message` entries | `chat-view.test.mjs` |
| Composer | Shift+Enter also sends | C3 |
| New turn per message | `send` reuses the last `clientId` | `chat-view.test.mjs` (`newClientId`); C3 (one turn) |
| Growth | no max height | C3 |
| Bubble time | `pageTime` formats in UTC | `page-time.test.mjs`; C2 |
| Captions | "via Telegram" dropped | `chat-view.test.mjs`; C5 |
| Retry | `retry` makes a new `clientId` | C4 (two turns in the reached-server case) |
| Arrives anyway | a local entry kept after its `clientId` is in the store | `chat-view.test.mjs`; C4 |
| Text, not HTML | the reply bound with `[innerHTML]` | `page-safety.test.mjs`; C5 (an `img` exists) |
| Links | `target` removed; `javascript:` accepted | C5; `reply-text.test.mjs` |
| Stages | `running` shown as "Deciding…" | `chat-view.test.mjs`; C2's log |
| Elapsed | the threshold is 0 s | `chat-view.test.mjs` |
| Reduced motion | the `animation: none` rule removed | C7 |
| Fallback | `unusable` mapped to `error` | `catalog.test.mjs` |
| Generator | `web` text ignored; `--check` passing a stale file | `catalog.test.mjs` |
| Scroll | follow new content while scrolled up | C6 |
| New messages | no focus on press | C6 |
| Demo path | the panel not rendered | `01-page` floor test (`live demo-path`) |
| DW-65 | `ChatItems` ignores `CHATMAX` | `TestStateChatCapped` |
| Isolation | `recentTurns` without its owner check | `TestIsolationEveryRowKind` |

**Shared surfaces:**
- `main`'s contents: `shell.spec` row 8, and `frame.spec` F1's heading lists (unchanged: the headline is not a heading);
- `live.spec` L4 (no focus move) and L5 (the loading view);
- the app's and the rail's height and overflow (frame specs F2 and F3 measure boxes);
- `01-page.spec.ts`'s `notBuilt` list, `playwright-projects.test.mjs`'s floor titles, and the demo-path step summary;
- `test-sign-in.sh`'s fixture users and redaction, and `iris.ts`'s `fixtureUser` union;
- `ApiClient` and `api-types.ts`;
- `icon.ts`'s `IconName`;
- `web/package.json`'s `build` and `npm test` (five new test files);
- `ci/units.sh` `WEB_INPUT_PATTERN`, with `test-ci-changes.sh` and `ci/mock/test/constants.test.mjs`;
- `Ownership`'s row-kind list (`TestIsolationEveryRowKind`, `Seed`, `ReadAll`, `TestRowsRefuses`, `TestOrders`);
- `/state`'s chat: `TestStateSections`, api.spec row 13, session.spec S1 and S8, restart row 20 (each under 100 entries, so unchanged);
- the PANEL user's session on throwaways.

Every test added or changed passes on a fresh environment, in either order:
- the `%UnitTest` methods create their rows through `Test.Data.Fixture` and remove them with `Fixture.Clean(refs)` naming only their own rows;
- the browser specs read the README account without publishing on it, and each PANEL test seeds or sends its own turns and asserts only on its own `clientId`s and refs;
- C6 seeds its own 30 turns, so it needs no other test's leftovers.

**Manual checks:** none.

**Implement-stage record.**

Task 0 (slot B, `OcuTalon.Test.Web.Api:TestMeasureChatCap`: one fixture session with 1,000 done turns of 200-character text and 1,000-character reply; `/state` three times through `StateJob`, the median logged). The method is removed and `grep -rn MEASURE src/` finds nothing.
- MEASURE old `ChatItems` (`Turns` and `Incidents`, every row): turns=1000 runs=.151565,.020182,.019489 s medianSeconds=.020182 bodyLength=1376458
- MEASURE capped `ChatItems` (`RecentTurns` and `RecentIncidents`, 100 each): turns=1000 runs=.089225,.003436,.003214 s medianSeconds=.003436 bodyLength=138058
- The capped snapshot is a tenth of the size and about a sixth of the time; no `reopen_if` line (3.4 ms: nothing stays slow without a `CreatedAt` index at this size).

Mutations (Rule 19; each applied, red observed, the tree restored byte-identical with `git status --short` and `git diff --stat` unchanged). The browser mutations ran on the throwaway as four batches of `live sign-in`, each mutation in a test of its own; a mutation whose red is in a node test ran in `node --test`.
- mutation: `chatView` walks the store's chat reversed -> `chat-view.test.mjs` (order, outbox merge, keys, captions); C5 (the turns' order)
- mutation: the panel's entries read `snapshot().chat` instead of `store().chat` -> C6 (the published turn never shows)
- mutation: `aria-live="polite"` on the list -> C1 (nothing in main is a live region)
- mutation: the headline loses "one" -> `chat-view.test.mjs` string test; C1 (the headline)
- mutation: `isFreshChat` counts only `chat.message` entries -> `chat-view.test.mjs` (an incident alone is not fresh)
- mutation: Shift+Enter also sends (`event.shiftKey` dropped from the key test) -> C3 (Shift+Enter adds a line and makes no request)
- mutation: `newClientId` draws a constant -> `chat-view.test.mjs` (`newClientId`); `ChatOutbox.send` reuses the last clientId -> C3 (each message is its own turn)
- mutation: the field's height has no maximum -> C3 (8 lines leave it at its 5-line height)
- mutation: `pageTime` formats in UTC -> `page-time.test.mjs`; C2 (the bubble's time)
- mutation: the "via Telegram" caption dropped -> `chat-view.test.mjs` (captions); C5 (the Telegram caption)
- mutation: `retry` posts a new clientId -> C4 (the three cases that retry: the retry posts the same clientId, and its turn never shows)
- mutation: a local entry kept after its clientId is in the store (no skip in `chatView`, no pruning in `ChatOutbox`) -> `chat-view.test.mjs` (the local message is dropped); C4's fourth case (one bubble)
- mutation: the reply's text runs bound with `[innerHTML]` -> `page-safety.test.mjs`; C5 (HTML-like text shows as text)
- mutation: the links lose `target` -> C5 (`target` is `_blank`); a `javascript:` scheme accepted -> `reply-text.test.mjs` (a non-http(s) link stays text)
- mutation: a running turn shown as "Deciding…" -> `chat-view.test.mjs` (stages); C2 (the log reads Deciding…, then the fallback, with no Working…)
- mutation: the elapsed threshold 0 s -> `chat-view.test.mjs` ("Working…" at 9 s)
- mutation: the `prefers-reduced-motion` rule of the dots removed -> C7 (`animation-name` is not `none`)
- mutation: `unusable` mapped to `error` in `REASON_KEYS` -> `catalog.test.mjs` (the sentence of each of the 12 reasons; the generated file is current)
- mutation: the generator ignores an entry's `web` text -> `catalog.test.mjs` (uses the web text); `--check` always passes -> `catalog.test.mjs` (a stale file fails the check)
- mutation: the ResizeObserver scrolls to the bottom whether or not the list was at the bottom -> C6 (scrollTop did not change)
- mutation: the New messages press does not focus the target -> C6 (focuses the new turn's element)
- mutation: the panel is not rendered -> `01-page.spec.ts` floor test "shows the empty chat panel and the composer" (`live demo-path`: floor 1 of 2 passed, step 1 failed)
- mutation: `ChatItems` ignores `CHATMAX` (the parameter 100000) -> `TestStateChatCapped` (slot B)
- mutation: `recentTurns` without its owner check (`WHERE ? <> ''`) -> `TestIsolationEveryRowKind` (slot B)
- mutation: the IME guard (`event.isComposing`, `keyCode` 229) dropped from the composer's key test -> C3 (empty text, space-only text and Enter during an IME composition send nothing)
- mutation: `ChatOutbox.send` without its empty-text guard -> C3 (the same assertion)
- mutation: `Composer.send` without `field.focus()` -> C3 (a click on Send returns focus to the field)
- mutation: the panel's `ResizeObserver` disconnects after its first callback -> C6 (at the bottom, the list follows new content)
- mutation: the panel's `ResizeObserver` disconnects after its first callback -> C10 (after message 0 the list is at the bottom), as in C6
- mutation: `ApiClient.postMessage` accepts any 2xx (the `status !== 202` test dropped) -> C4 (an answer other than 202 is Not sent)
- mutation: `ChatPanel` never notes a running turn (`since.set` removed) -> C8 (after 10 seconds the working time shows)
- mutation: `role="status"` on the indicator -> C7 (the indicator is no live region)
- mutation: the reply-landed branch of `noteArrivals` removed -> C9 (a reply that lands while scrolled up shows New messages)
- mutation: `onSent` only clears the button and neither pins nor scrolls -> C9 (Send takes a list that is scrolled up to the bottom)
- mutation: `onScroll` no longer clears the button at the bottom -> C9 (scrolling to the bottom by hand hides New messages)
- mutation: the rail's `overflow-y: auto` removed -> C1 (the rail scrolls on its own)
- mutation: the `zap` icon has no path -> C1 (the chip's icon is drawn)
- mutation: `<app-chat-panel />` rendered whatever the load status -> L5 and L7 (no panel and no composer while loading or failed)
- mutation: `Msg/Enum.cls` removed from `WEB_INPUT_PATTERN` -> `test-ci-changes.sh` (the message enums run web and every group)

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The signed-in page has its chat: the empty chat panel, the user's bubbles, OcuTalon's replies (paragraphs, lists and http(s) links as text; the generated catalog's fallback sentence), the turn indicator (Deciding, Working, and the working time after 10 s), the composer, the New messages button and the scroll rules. `ChatOutbox` sends with a new `clientId` and reuses it for Retry sending. `/state`'s chat is capped at the newest 100 entries through two new `Ownership` row kinds (DW-65). The demo-path page step has its second `@floor` test.

**Files changed.**
- Server: `Data/Ownership.cls` (row kinds `recentTurns`, `recentIncidents`, their wrappers, the shared `INCIDENTVISIBLE` condition), `Web/Api.cls` (`CHATMAX`, the capped `ChatItems`), `Test/Data/Ownership.cls` and `Test/Web/Api.cls` (`TestStateChatCapped`, the order, isolation and refusal cases).
- Catalog: `web/scripts/catalog.mjs` (generator), `web/src/app/msg/catalog.ts` (generated), `web/package.json` (`catalog`, and `--check` in `build`), `ci/units.sh` and `docker/tests/test-ci-changes.sh` (the catalog classes and `Msg/Enum.cls` join the web inputs).
- Page: `web/src/app/chat/` (`chat-panel`, `composer`, `empty-chat`, `user-message`, `ocutalon-reply`, `outcome-chip`, `chat-outbox`, `chat-view`, `reply-text`, `page-time`), `main-page.ts`, `app.ts`, `icon.ts`, `api-client.ts`, `api-types.ts`.
- Tests: `web/scripts/{catalog,chat-view,page-safety,page-time,reply-text}.test.mjs`, `playwright-projects.test.mjs`, `web/e2e/chat/chat.spec.ts` (C1-C10), `web/e2e/support/iris.ts` (`PANEL`, `quoted`, `seedTurns`), `web/e2e/sign-in/shell.spec.ts`, `web/e2e/live/live.spec.ts` (L5 and L7 assert no composer), `web/e2e/demo-path/01-page.spec.ts` (the floor test), `docker/tests/test-sign-in.sh` (`ZzPanel`).

**Review.** 54 findings from four layers: high 0, medium 6, low 47, maybe-false 1. Patched: 4 medium entries (the elapsed indicator, "only a 202 is a success", the live-region checks while something is showing, the scrolled-up branches) and 8 low ones (the `Msg/Enum.cls` web input, an unknown catalog key showing the turn's own reason, the layout assertions, the chip icon paths, C4's "arrives anyway", the `twoLines` name, the send scroll through `ChatOutbox.sendCount`, no composer while loading or failed). Deferred: 1 (the at-the-bottom flag race, medium, unverified). Rejected: 33, each with its reason in the Review Triage Log (the spec-bound ones are the link and list grammar, the cap's shape, Decided 7, 11 and 20, and the synthetic summary fixtures).

**Follow-up review recommended: true.** Four medium entries were patched, and the changes made after the review layers read the diff were not read by a layer: the send scroll now runs from `ChatOutbox.sendCount` through an effect in `ChatPanel`, and C8 (a real 10 s wait), C9 and C10 are timing-dependent browser tests that passed on one machine (a throwaway on the developer machine) and could flake on the slow CI hosts.

**Verification performed.** Slot B (build 154U, 52791): both source trees load and compile with 0 errors; `Test.Web.Api` 25 of 25, `Test.Data.Ownership` 13 of 13, `Test.Web.Shell` 5 of 5; no `zz` row left. `npm --prefix web test` 180 passed; `lint`, `catalog`, `payloads` and `tokens` `--check` exit 0; `test-web-build.sh`, `test-class-rules.sh`, `test-boundaries.sh`, `test-ci-config.sh`, `test-ci-changes.sh`, `test-mock.sh` and `ci/checks.sh` exit 0. Throwaway (tag `e2s25i`): `live sign-in` 97 passed (C1-C10 included), `live demo-path` printed `STEP 1 page: partly skipped, 2 passed, 3 skipped (Story 4.7: ...)` and `floor 2 of 2 passed`, `shard lane-b` 31 classes passed; teardown left nothing. Task 0 measured the cap (below the Verification section). Every added or changed pinning test has a recorded mutation that went red.

**Residual risks.**
- A `[label](url)` link shows its label only, so a model-written label can name another address (finding 3). The link form is the contract's; the options are showing the destination host with the link, or having the reply guard (AD-28, Lane A) remove such links. It is a security-posture call for the UX and security owner, with the chat agent's input being content that arrives from productions (AD-10).
- The deferred scroll-flag race (frontmatter `deferred:`).
- Reply links open in a new tab against EXPERIENCE:391 and UX-DR127 (U-24, for the UX owner).
- A Safari IME confirmation Enter may send (WebKit runs are Story 2.12's).
- Control-only text that JavaScript does not trim answers 400 and shows "Not sent" with a Retry that cannot succeed (Decided 7).
- `page-time.test.mjs` accepts a plain space or U+202F before AM or PM, since Node 26 with ICU 78 writes the plain space the spec's oracle did not expect.
