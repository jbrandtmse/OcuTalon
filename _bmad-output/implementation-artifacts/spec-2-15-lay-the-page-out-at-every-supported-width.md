---
title: 'Story 2.15: Lay the page out at every supported width'
type: 'feature'
created: '2026-10-24'
status: 'done'
baseline_revision: '050ca9aff992d66c2978922d350f5b7c292ff7cb'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The main page has one layout at every width: the 288px rail beside the chat, both fixed to the viewport's height (320px from 1440px). Below 1280px the rail squeezes the chat. Below 1024px, and at 200% browser zoom (a 1280px window gives a 640px CSS viewport), nothing reflows: the page cannot scroll as a page, and there is no narrow-window note. FR-12, UX-DR20, UX-DR35, UX-DR128, UX-DR137 and UX-DR138 ask for four width bands and the note.

**Approach:**
- One set of width media queries, written once in a framework-free module, drives both the CSS and a small `Layout` service:
  - **1440px and wider:** the rail is 320px.
  - **1280 to 1439px:** today's frame, with the rail at 288px.
  - **1024 to 1279px:** the rail is a push drawer behind a "Status" header button that shows the approval request count.
  - **Below 1024px:** one stacked column that scrolls as a page, with a sticky compact header and the once-per-session note.
- Every Story 2.12 and 2.14 rule keeps holding in every band: skip links, one Esc per layer, rings inside the viewport and never under the header, and the focus rule.
- The browser cases G1 to G7 join `live:floor`.

## Boundaries & Constraints

**Always:**
- **One source for the bands.** `web/src/app/shared/layout-view.ts` (new, framework-free like `trace-view.ts`) exports:
  - `LAYOUT_QUERIES`, which holds four range queries: `stacked: '(width < 1024px)'`, `framed: '(width >= 1024px)'` (the page fills the viewport and each region scrolls on its own), `drawer: '(1024px <= width < 1280px)'` and `wide: '(width >= 1440px)'`. The reference band (1280 to 1439px) is the width where `framed` matches and neither `drawer` nor `wide` does.
  - `LAYOUT_TEXTS`, which holds the fixed strings: `status: 'Status'`, the count's spoken forms, the note's text and its Close name.
  - the note's storage keys.

  Every width `@media` in `web/src/app/**` and `web/src/styles/**` is one of these four strings, and `Layout` calls `matchMedia` only with them. Range syntax leaves no gap at fractional widths, which zoom produces.
- **`Layout`** (`web/src/app/shared/layout.ts`, new, root service) exposes:
  - `band`: `'wide' | 'reference' | 'drawer' | 'stacked'`, from `matchMedia` change listeners;
  - `stacked`;
  - `drawerOpen`;
  - `toggleStatus()`, `focusRegion(selector)` and `closeDrawer()`.

  Rules:
  - `drawerOpen` matters only in the drawer band.
  - On entering the drawer band, the drawer is closed, unless focus is inside the rail. That includes a popover whose trigger is inside the rail (`Popovers.triggerOf`). In that case it is open.
  - `focusRegion(selector)` focuses the region at once when it shows. For the rail in a closed drawer, it opens the drawer and focuses the rail after the next render (`afterNextRender`).
  - `closeDrawer()` closes the drawer, and moves focus to the Status button when focus was inside the rail.
- **The drawer (1024 to 1279px).**
  - `section.rail` gets `id="status-region"`. It is `display: none` while the drawer is closed.
  - While open, it shows as today's rail column. It is 288px wide, beside main, and the chat narrows. Nothing overlaps the chat, and the page itself does not scroll.
  - It is not modal: no backdrop, no `aria-modal`, no focus trap and no light dismiss. It has no heading or Close of its own. It stays the region "Status", named by its existing hidden h2.
- **The Status button** sits in the header, first in the right-hand group. It renders only in the drawer band.
  - It is `button.button.button-ghost.header-button.status-button`, with `aria-controls="status-region"` and `aria-expanded` = `drawerOpen`.
  - It shows the text "Status" and a count pill styled with the `--tab-badge-*` tokens (`aria-hidden="true"`). A visually hidden spoken part follows, so the name is "Status, 2 approval requests", or "Status, 1 approval request" for one.
  - The count is `pendingApprovals(store).length`, the same source as the rail's "Approval requests" heading.
  - Before the snapshot has loaded, and when the load failed, it shows "Status" alone, with no pill and no spoken count. It never shows a zero it does not know.
  - A press opens the drawer and focuses the rail (`toggleStatus` → `focusRegion`), or closes it (`closeDrawer`).
- **Esc acts on one layer.** The order is: a shown tooltip (capture phase, unchanged), then an open popover, then the innermost disclosure, then the drawer.
  - `DecisionRow.collapse(event)` and `DecisionStrip.collapse(event)` call `event.stopPropagation()` when they collapse. They still return first while `Popovers.hasOpen()`.
  - `section.rail` gets `(keydown.escape)="collapse($event)"`. `MainPage.collapse(event)` returns while `hasOpen()`, and otherwise closes an open drawer (`closeDrawer`) in the drawer band.
  - In other bands, Esc on the rail does nothing new.
- **Skip links.** `SkipLinks.skip` keeps `preventDefault()` and calls `Layout.focusRegion(target)`, so "Skip to status" opens a closed drawer. `SKIP_LINKS` is unchanged. The skip links take `z-index: 2`, above the sticky header's 1.
- **The stacked layout (below 1024px).**
  - The page scrolls as a document. `app.ts` keeps `height: 100vh; height: 100dvh` only under `LAYOUT_QUERIES.framed` and is `min-height: 100vh; min-height: 100dvh` always, so the heights ratchet's values for `app.ts` are unchanged.
  - The order, top to bottom, is: the header, the banners, the note, main (the chat), then `section.rail` (the status sections). DOM order matches it.
    - `MainPage` moves `section.rail` after `main.main` while stacked, and back before it otherwise (F1's order at 1280px).
    - A focused element inside the moved rail keeps focus: it is re-focused with `preventScroll` if the move blurred it.
  - Main and the rail span the column. The rail does not scroll on its own (`overflow: visible`), has no right border, and has a 1px top border (`var(--status-rail-border-right)`).
  - The chat list scrolls on its own at `min(70vh, content)`: `max-height: 70vh` and `flex: none`. The composer follows it. Nothing is `height`-fixed.
  - **Only the compact header is sticky.** `app-header` is `display: block` always. Below 1024px it is `position: sticky; top: 0; z-index: 1`, its `.header` has `min-height: var(--space-12)` and `padding-inline: var(--space-3)`, and it may wrap. Its contents and words are unchanged. No other element is sticky or fixed except the skip links (fixed, clipped until focused).
  - **Focus is never under the header.**
    - `base.css` declares `:root { --app-header-block-size: var(--app-header-min-height); }`, and under the stacked query `html { scroll-padding-top: calc(var(--app-header-block-size) + var(--space-scroll-gutter)); }`.
    - `Header` writes its measured border-box block size to `--app-header-block-size` on the root element through a `ResizeObserver`, which it disconnects on destroy.
    - No horizontal page scroll at 640px.
- **The narrow-window note** (UX-DR35, UX-DR128, UX-DR138).
  - It is an info `app-inline-notice` (an icon and the text on a tint, with no accent bar) with the text "This page is designed for a wider window. Everything still works.". It sits first in `MainPage`'s column, under the banners, and only in the stacked layout.
  - **`NarrowNote`** (`web/src/app/shared/narrow-note.ts`, new, root service) follows `TraceHelp`'s pattern:
    - The "shown" flag is in sessionStorage and the "closed" flag in localStorage. Both are read once when the service starts and held in memory, so a storage that throws still gives a note that shows once per page load.
    - `layoutChanged(stacked, atLoad)` shows the note when `stacked` holds and neither flag is set, and records "shown". When the note appears after load (`atLoad` false), it announces the note's text once through `Announcer`. A note shown at load is silent.
    - Leaving the stacked layout hides the note, and it does not come back in that browser session.
    - `close()` hides it and records "closed".
  - `MainPage` calls `layoutChanged` from an effect on `Layout.stacked`, with `atLoad` true on the effect's first run only.
  - **The Close button.** `InlineNotice` gains an optional `closeName` input and a `closed` output. When `closeName` is set, the notice ends with an icon-only `button.button.button-ghost.close` named by it (the `x` icon), as the banners' Close is. `ServerButton`'s notice sets neither, so it is unchanged.
  - The note's Close is "Close narrow-window note" (veto). Its removal returns focus through the focus rule: `MainPage`'s `NOTE_RULE` is `{ within: '.narrow-note' }`, so focus goes to the main region without scrolling.
- **Reuse (Rule 2).**
  - `readFlag` and `writeFlag` move from `trace-help.ts` into `web/src/app/shared/stored-flag.ts`, with the stored value as a parameter. `TraceHelp` and `NarrowNote` both use them, and `TRACE_FLAG` stays.
  - `pendingApprovals(store)` is exported from `rail-view.ts`, and `railView` uses it.
  - K4's `readFocus`, `inside`, `expectRingInside` and `expectRing`, and its scrolling-page seed (12 decision rows and 8 done turns), move into `web/e2e/support/floor.ts`. `keyboard.spec.ts` imports them.
- **Text.** Every new string comes from `LAYOUT_TEXTS` by interpolation, in ASCII. "Status" and the note's text are the UX's own words.

**Never:**
- **No server change:** no ObjectScript, REST route, payload, event, stored data, role, grant or dependency.
- **No new noise:** no live region, no toast, no modal, no `transition` or animation for the drawer, no smooth scroll, no keyboard shortcut and no new `height:` declaration.
- **No public text** beyond `LAYOUT_TEXTS`: the note's text (UX), "Status" (UX), and the veto items under Design Notes.
- **No overlay drawer and no detection of the zoom level.** The bands come from the CSS width only.
- **Not changed:**
  - the layout from 1280px up, apart from the 1440px query's syntax;
  - F1's DOM order at 1280px;
  - `SKIP_LINKS`;
  - the rail's and the chat's content;
  - the popover, tooltip and dialog rules.
- **Not this story:**
  - **Story 2.16:** Firefox, WebKit, the scan, the string test, DW-89, DW-145, DW-178 and DW-179.
  - **Story 4.4:** the demo guide's place and its compact form.
  - **Story 4.5:** the device column, and "Skip to simulated devices".
  - **Story 12.3:** the unpaired Telegram card's place at 1024 to 1279px and in the column.
  - **Story 6.2:** UX-DR20's incident card at 1280×600.
- **Registration.** No edit to `ci/units.sh`, `ci/iris.sh`, `ci/warm.sh`, `docker/tests/test-ci-config.sh` or a workflow. The new spec joins `web/e2e/floor/`, which `live:floor` already runs. No case joins `live:sign-in`.
- **Tests:**
  - never stop IRIS or its web server;
  - never hold a poll for 8 s or longer;
  - no floor case lets a chat post reach the server.
- **Contended paths stay read-only.** They are the same list as Story 2.14's Never:
  - `src/bridge/**`;
  - `OcuTalon/{Agent,Tools,Digest,Install,Schedule,Checks,Eval,Watch}/**`;
  - `Data/Public/**` and `Data/{StatusMark,Time,Reminder}.cls`;
  - `Core/Commands*.cls` and `Msg/Tick.cls`;
  - `Test/{Agent,Bridge,Install,Tools,Digest,Schedule}/**`;
  - `ci/mock/scenarios/{A,B}/**`, `web/e2e/demo-path/0{2,3}-*.spec.ts` and `release/**`;
  - `.github/workflows/lane-a.yml`, `ci/iris.sh` and `ci/warm.sh`;
  - `docker/tests/test-pinned-sources.sh`, `test-production.sh`, `test-ci-warm.sh` and `test-ci-config.sh`;
  - `web/src/app/rail/telegram-card/` (Lane A's, Epic 12).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Wide | 1440×900 | The rail is 320px, beside main. No Status button | — |
| Reference | 1439×900; 1280×600 with a scrolling rail and chat | The rail is 288px. The page does not scroll. Tab reaches every control from the first skip link to Send, each ring inside the viewport and its scrollers, with `scrollTop` 0 throughout | — |
| Drawer, closed | 1024 to 1279px, the snapshot loaded, n pending approvals | The Status button's name is "Status, n approval requests", n equals the rail's "Approval requests" count, the pill shows n, `aria-expanded="false"`, and the region Status is not shown | Snapshot still loading or failed: "Status" alone, with no pill |
| Drawer, open | Status pressed | `aria-expanded="true"`. The region shows at 288px, and main starts at its right edge. Focus is on `section.rail`. The page does not scroll | — |
| Esc in the drawer | An expanded decision row holds focus | 1st Esc collapses only the row. 2nd Esc closes the drawer, and focus moves to the Status button | A shown tooltip or an open Trace help takes its Esc first, and the drawer stays open |
| Close by the button | Status pressed while open | The drawer closes, and focus is on the button (moved there if it was inside the rail) | — |
| Skip to status | Drawer band, drawer closed | The drawer opens, focus is on `section.rail` with its ring inside the viewport, and the URL is unchanged | — |
| Band change | Focus inside the rail at 1280px, then 1100px wide | The drawer is open and focus is unchanged. With focus elsewhere, the drawer starts closed | — |
| Stacked | 1000×800; 640×360 at device scale 2 (200% of 1280×720) | Header, banners, note, main, rail, in this order on screen and in the DOM. Main and the rail span the page. The page scrolls, only the header sticks (top 0 after scrolling) and it is shorter than at 1280px. There is no horizontal scroll | Empty chat: the list is as tall as its content (under 70vh) |
| Chat list, stacked | 8 done turns at 640×360 | The list's client height is 70% of the viewport (±1) and it scrolls on its own | — |
| Live update, stacked | A reminder published after the move | Its row appears in the region Status | — |
| Focus, stacked | Tab through every stop; the skip links | Every ring is inside the viewport, and every ring outside the header lies below the header's bottom. Every stop in main comes before every stop in the rail | — |
| Layout change, focus in the rail | Resized from 1280 to 1000px with a rail control focused | The same element keeps focus | — |
| Note, first time | A fresh browser, stacked at load | The note shows at the top of the column with the UX's text and "Close narrow-window note". Nothing is announced | Storage throws: the note still shows, and Close works for the page |
| Note appears later | A fresh browser loads at 1280, then is resized to 1000px | The note appears and its text is announced once | — |
| Note, same session | Widened and narrowed again, or reloaded in the same tab | No note | — |
| Note closed | Close pressed | The note goes, focus is on `main.main`, and no later tab of this browser shows it | localStorage throws: it stays closed for this page only |

</intent-contract>

## Code Map

**Page (Lane B; edit or new)**
- `web/src/app/shared/layout-view.ts` (new):
  - `LAYOUT_QUERIES`, `LAYOUT_TEXTS`, `statusCount(n | undefined)` (the pill and the spoken part, or none) and the note's keys (`ocutalon.narrowNote.shown`, `ocutalon.narrowNote.closed`, value `'1'`);
  - module doc as in `trace-view.ts:1-10`. It imports types only.
- `web/src/app/shared/layout.ts` (new): the root service, with `matchMedia` listeners, the drawer state and the two focus calls.
- `web/src/app/shared/narrow-note.ts` (new): the root service, modelled on `web/src/app/shared/trace-help.ts:31-51`.
- `web/src/app/shared/stored-flag.ts` (new): `readFlag` and `writeFlag`, moved from `web/src/app/shared/trace-help.ts:6-22`. `TRACE_FLAG` and the keys stay in `trace-view.ts:27-34`.
- `web/src/app/shared/inline-notice.ts:5-55`: the template and the `variant` input. It gains `closeName` and `closed`. The Close markup to copy is `web/src/app/banners/banner-stack.ts:80-84`.
- `web/src/app/app.ts:26-36`: `:host` `height: 100vh; height: 100dvh`. These move under `LAYOUT_QUERIES.framed`, and `min-height` is added.
- `web/src/app/header/header.ts`:
  - `.side.right` `:63-94`: the Status button goes first;
  - the styles `.header` `:152-161` and `.header-button` `:212-217`: add `:host`, the stacked compact rules and `.count`;
  - the class `:261-306`: inject `Layout`, a `requests` computed from `live.store()` and `live.status()`, and the `ResizeObserver` with its `DestroyRef` cleanup;
  - the badge text pattern is `:288-294`.
- `web/src/app/header/skip-links.ts`:
  - `skip()` `:61-64`: its `.focus(` call moves to `Layout.focusRegion`;
  - `.skip-link` `z-index` `:41`.
- `web/src/app/main-page/main-page.ts`:
  - template `:43-92`: the note block after the h1; on `section.rail` `:45`, the `id`, `[class.open]` and `(keydown.escape)`;
  - styles `:93-200`: `:host` `:94-98`; `.rail` `:99-110`; the 1440 query `:123-127`, rewritten as `LAYOUT_QUERIES.wide`; `.main` `:161-168`; plus the drawer and stacked blocks;
  - the class `:202-223`: `LOAD_ERROR_RULE` `:21` is the pattern for `NOTE_RULE`, and the `keepFocus` effect `:218-221` is the pattern for the note's effect;
  - inject `Layout` and `NarrowNote`, and add the placement effect and `collapse(event)`.
- `web/src/app/chat/chat-panel.ts`: `:host` `:122-127` and `.list` `:128-136`. They gain the stacked block (`flex: none`, with `max-height: 70vh` on the list).
- `web/src/app/rail/rail-view.ts:297-301`: the pending-approvals filter inside `railView`, which becomes the exported `pendingApprovals(store)`.
- `web/src/app/rail/decision-row.ts`: `:31` `(keydown.escape)="collapse()"`, and `collapse()` `:164-172`.
- `web/src/app/chat/decision-strip.ts`: `:56` and `collapse()` `:242-250`. Both pass `$event` and stop it when they collapse.
- `web/src/styles/base.css`: `:root` `:47-52` gains the default `--app-header-block-size`, and a stacked `html` block follows `html, body` `:70-73`.
- `web/src/styles/tokens.css` (read only; generated): `--space-header-height` `:114`, `--space-rail-width(-wide)` `:118-119`, `--space-target-min` `:128`, `--space-scroll-gutter` `:129`, `--app-header-min-height` `:135`, `--status-rail-width` `:264`, `--status-rail-border-right` `:263`, `--tab-badge-*` `:454-460` and `--inline-notice-info-*` `:178-181`.
- Read only:
  - `web/src/app/shared/focus-rule.ts:53-92`: `keepFocus`, whose fallback is `main.main`;
  - `web/src/app/shared/popover.ts`: `hasOpen()` and `triggerOf()`;
  - `web/src/app/shared/announcer.ts:31`: `announce`;
  - `web/src/app/rail/status-rail.ts:35-39`: its focus rule, unchanged inside the drawer.

**Tests (Lane B; edit or new)**
- `web/scripts/layout-view.test.mjs` (new). It imports the module as `web/scripts/trace-view.test.mjs:14` does.
- `web/scripts/rail-view.test.mjs`: `pendingApprovals`.
- `web/scripts/floor-sources.test.mjs`:
  - `KEY_HANDLERS` `:98`, the bindings list `:141-148` and `ESC_HOSTS` with the `collapse` regex `:161-175`;
  - `FIXED_HEIGHTS` `:194` (unchanged values);
  - new describes for the bands and for sticky or fixed positions.
- `web/scripts/announce-focus-sources.test.mjs`:
  - the speakers `:94-104`;
  - `FOCUS_CALLS` `:108-114`;
  - the `afterNextRender` list `:125-127`;
  - the hosts `:129-145` (main page: `NOTE_RULE` as well).
- `web/scripts/floor-fixtures.test.mjs:34`: the list of files that must pass `turnRows`. It gains `floor/layout.spec.ts`.
- `web/e2e/support/floor.ts`: new exports. Its header doc gains the moved helpers.
- `web/e2e/floor/keyboard.spec.ts`:
  - the helpers to move are `Box` `:54`, `Reading` `:62`, `readFocus` `:78`, `inside` `:115`, `expectRingInside` `:119` and `expectRing` `:128`;
  - K4's seed `:453-475` and its walk `:485-499` are the pattern for G1 and G5;
  - K2 `:255-325` (the Trace help in a fresh context) and K1 `:164` are patterns.
- `web/e2e/floor/layout.spec.ts` (new): G1 to G7.
- Helpers to use: `web/e2e/support/api.ts` `changeSnapshot` `:27` and `holdState` `:114`; `web/e2e/support/page.ts` `recordAnnouncements` `:53`, `announcements` `:77` and `tokenColor` `:17`; `web/e2e/support/iris.ts` `seedIncident` `:793`, `seedApproval` `:619` and `fixtureUser` `:18`.
- `docker/tests/test-floor.sh`:
  - the header `:1-23` names the cases;
  - the PASS and FAIL lines name Story 2.12's A1-A7 and P1-P4 and Story 2.14's K1-K6, W1-W4 and H1, and gain Story 2.15's G1-G7.
- **Shared-surface readers:**
  - `web/e2e/banners/banners.spec.ts` B12 `:653-691`: its 800×900 step is now stacked, and the note shows there;
  - `web/e2e/rail/rail.spec.ts` R1 `:124-127`: 288px and 320px;
  - `web/e2e/frame/frame.spec.ts` F1 `:61-93`: the DOM order at 1280px;
  - `web/e2e/chat/chat.spec.ts:179-181`: the app fills the viewport at 1280×720.

  Each must stay green unchanged.
- **Read only:**
  - `ci/units.sh:34,41`: `shards` already runs `live:floor`, and `BROWSER_UNITS` holds `floor`;
  - `web/playwright.config.ts:34-41`: the `floor` project is Desktop Chrome at 1280×720 and runs `e2e/floor/`.
- **UX:** `EXPERIENCE.md` E:386-387 (persistence), E:443 (200% and below 1024), E:457-465 (Responsive & Platform); `DESIGN.md` D:692-698 (widths, gutters, minimum heights), D:750 (inline notice), D:481-485 (the tab badge).

## Tasks & Acceptance

**Execution:**
- **Task 0 (done at plan, 2026-10-24).** A scratch Playwright script ran on static pages in Playwright 1.64.1's Chromium 156. It used no stack, and nothing was kept. It measured:
  - (a) The range queries match exactly at 1023/1024, 1279/1280 and 1439/1440.
  - (b) At 640×360 with device scale factor 2: `innerWidth` is 640, `(width < 1024px)` matches and a sticky header stays at top 0 after scrolling.
  - (c) With no `scroll-padding-top`, a control under a 48px sticky header stays under it when focused, by `focus()` and by Tab (top 10px). With `scroll-padding-top: 52px` on `html`, both scroll it clear (top 195px).
  - (d) Moving an ancestor of the focused element blurs it (focus goes to the body). `Element.prototype.moveBefore` exists in Chromium 156. That it is missing in some supported browser is (inference).

  No further Task 0.
1. `web/src/app/shared/layout-view.ts` -- `LAYOUT_QUERIES`, `LAYOUT_TEXTS`, `statusCount`, the note's keys -- the one source that the CSS, the services and Story 2.16's string test read. `web/scripts/layout-view.test.mjs` -- it pins the four query strings, the texts (deep-equal) and `statusCount(undefined)`/`(0)`/`(1)`/`(2)`.
2. `web/src/app/shared/stored-flag.ts` and `web/src/app/shared/trace-help.ts` -- move `readFlag` and `writeFlag` (value as a parameter); `TraceHelp` imports them -- Rule 2, for `NarrowNote`.
3. `web/src/app/rail/rail-view.ts` -- export `pendingApprovals(store)` and use it in `railView`; `web/scripts/rail-view.test.mjs` -- it pins the pending filter and the order -- one count for the rail heading and the Status button.
4. `web/src/app/shared/layout.ts` -- the service as Boundaries say, with a class doc that states its contract.
5. `web/src/app/shared/narrow-note.ts` -- the service as Boundaries say.
6. `web/src/app/shared/inline-notice.ts` -- `closeName` and `closed` -- the note's Close; `ServerButton` is unchanged.
7. `web/src/app/app.ts` -- the heights under `LAYOUT_QUERIES.framed`, `min-height` always -- the page scrolls when stacked.
8. `web/src/app/header/header.ts` -- the Status button and its count, `:host` display, the stacked sticky compact rules, and the `ResizeObserver` that writes `--app-header-block-size`; update the class doc.
9. `web/src/app/header/skip-links.ts` -- `skip()` calls `Layout.focusRegion`; `z-index: 2`; update the doc.
10. `web/src/app/main-page/main-page.ts` -- the note block; on the rail, the `id`, `[class.open]` and `(keydown.escape)="collapse($event)"`; the drawer and stacked styles, with the 1440 query rewritten; the placement effect with focus kept; the note effect and `NOTE_RULE`; update the class doc. If the placement uses `afterRenderEffect` or `afterNextRender` rather than an `effect` over view queries, the ratchet's render list gains `main-page.ts` with its reason.
11. `web/src/app/chat/chat-panel.ts` -- the stacked list, at `min(70vh, content)`.
12. `web/src/app/rail/decision-row.ts` and `web/src/app/chat/decision-strip.ts` -- `collapse(event: Event)`, which stops the event when it collapses; update the docs -- so the drawer's Esc acts only when no layer above it did.
13. `web/src/styles/base.css` -- the default `--app-header-block-size` and the stacked `html` `scroll-padding-top`.
14. **Ratchets.**
    - **`web/scripts/floor-sources.test.mjs`:**
      - `KEY_HANDLERS` and the bindings gain `app/main-page/main-page.ts` (Escape closes the drawer);
      - `ESC_HOSTS` gains it, and the regex reads `protected collapse(event: Event): void {` and then `hasOpen()` first;
      - a new assertion that the strip and the row call `event.stopPropagation()` when they collapse;
      - a new describe for the bands: every width `@media` of `app/**` and `styles/**` is one of `LAYOUT_QUERIES` (imported from `layout-view.ts`), and `layout.ts` calls `matchMedia` only with them. A sample `@media (max-width: 1000px)` must be caught;
      - a new describe: `position: sticky` only in `app/header/header.ts`, and only inside the stacked query; `position: fixed` only in `app/header/skip-links.ts`. Each list carries its reason.
    - **`web/scripts/announce-focus-sources.test.mjs`:**
      - the speakers gain `app/shared/narrow-note.ts`;
      - `FOCUS_CALLS` loses `skip-links.ts` and gains `app/shared/layout.ts` [2] (the region that the user's skip link or Status press reveals, and the Status button when the user closes the drawer from inside it) and `app/main-page/main-page.ts` [1] (a focused element of the rail keeps its focus when the layout moves the rail);
      - the render list gains `app/shared/layout.ts`;
      - the main page's hosts entry also names `NOTE_RULE`.
    - **`web/scripts/floor-fixtures.test.mjs`:** gains `floor/layout.spec.ts`.
15. **E2E support.**
    - `web/e2e/support/floor.ts`: the moved ring helpers and `seedScrollingPage(user, refs, stamp)`, which seeds K4's 12 decision rows and 8 done turns.
    - `web/e2e/floor/keyboard.spec.ts`: import them, with no behaviour change.
16. **`web/e2e/floor/layout.spec.ts` (new).** One header (what it pins and needs). Every case signs in as `FLOOR` in a fresh context, removes its rows with `cleanFixtureRows` (with `turnRows`) in `finally`, and unroutes in `afterEach`. The 200% cases use `test.use({ viewport: { width: 640, height: 360 }, deviceScaleFactor: 2 })` in their own describe.
    - **G1: the wide and reference widths.**
      - With the scrolling page seeded: at 1440×900 the region Status is 320px wide, its right edge is main's left edge (±1), and there is no Status button. At 1439×900 it is 288px.
      - At 1280×600:
        - the page does not scroll;
        - the rail and the chat list each scroll (more than 40px);
        - a Tab walk from the first skip link to Send has every ring inside the viewport and its scrollers, `document.scrollingElement.scrollTop === 0` at every stop, and at least 12 rail Trace links.
    - **G2: the drawer, its count and Esc,** at 1100×720 in a fresh context. Seeded: two approval requests, each with its own incident (`seedIncident` then `seedApproval`, as `seedFullPage` seeds one), and a decision row with a trace link.
      - With `/state` held, the button's name is exactly "Status", it has no pill, and the region Status is absent. Then the hold is released.
      - **Loaded:**
        - the name is "Status, n approval requests", and the pill shows n, where n is the rail's "Approval requests" count and at least 2;
        - `aria-controls` is the rail's id and `aria-expanded` is false.
      - **Pressed:**
        - `aria-expanded` is true;
        - the region is 288px wide and main's left edge is at its right edge;
        - focus is on `section.rail`;
        - the page does not scroll.
      - The row is opened by keyboard. Esc collapses only the row, and the drawer stays open. A second Esc closes the drawer, with focus on the Status button.
      - Reopened, the row's Trace link is pressed, so the help opens, and focus goes back to the link. Esc closes only the help, and the drawer stays open.
      - A click on the button closes the drawer, with focus on the button.
      - At 1024×720 and 1279×720 the button shows. At 1280×720 it does not, and the region shows as a column.
    - **G3: skip links and band changes,** at 1100×720.
      - Tab twice, then Enter on "Skip to status": the drawer opens, focus is on `section.rail` with its ring inside the viewport, and `page.url()` is unchanged.
      - Esc returns focus to the button. "Skip to chat" focuses `main.main`.
      - At 1280×720 a rail heading is focused, then the window is resized to 1100: the drawer is open and focus is unchanged.
      - The composer is focused, then the window goes to 1280 and back to 1100: the drawer is closed.
    - **G4: the stacked column,** at 1000×800 and in the 200% describe. With the scrolling page:
      - **The order:** the tops of `app-header`, `.banner-slot`, the note, `main.main` and `section.rail` ascend, and `main.main` precedes `section.rail` in the DOM.
      - **Widths:** main and the rail span the page (±1), and `scrollWidth <= clientWidth`.
      - **Scrolling:**
        - the page scrolls;
        - after `scrollTo` to the bottom, `app-header`'s top is 0;
        - its block size is less than at 1280×720;
        - no other element has a computed `position` of `sticky`, and none of `fixed` except the clipped skip links and the empty `.cdk-overlay-container`.
      - **The list:** at 640×360 its client height is 0.7 × the inner height (±1), and it scrolls. On a load whose snapshot `changeSnapshot` empties, it is as tall as its content (`scrollHeight - clientHeight <= 1`) and shorter than 70vh.
      - **A live update:** `addReminder` shows its row in the region Status.
      - **Focus kept:** at 1280×720 a rail trace link is focused, then the window is resized to 1000. The link keeps focus.
    - **G5: the keyboard in the column,** in the 200% describe.
      - A Tab walk from the first skip link to the rail's last stop, bounded:
        - every ring is inside the viewport and every scroller;
        - every stop outside `app-header` has its ring's top at or below the header's bottom (−0.5);
        - every stop inside main comes before every stop inside the rail.
      - "Skip to status", then "Skip to chat": each region takes focus, with its ring below the header's bottom and inside the viewport.
      - About opens inside the viewport and scrolls; Esc closes it and focus returns to the account button. This rechecks Story 2.14's residual.
    - **G6: the note, once per session and closed per browser,** at 1000×800 with `recordAnnouncements`.
      - On the first load:
        - the note shows above main and below the banner slot;
        - its text is exactly the UX's, and its `svg` is `aria-hidden`;
        - its Close is "Close narrow-window note";
        - nothing announced holds its text.
      - At 1280 the note is gone; back at 1000 it is still gone. A reload shows no note.
      - A new page in the same context (a new tab session, already signed in, so it opens the page's address directly) shows the note. Close takes it away, and focus is on `main.main`. A third page shows none.
    - **G7: a note that appears later, and storage that fails.**
      - A fresh context at 1280×720, resized to 1000×800: the note appears and its text is announced exactly once.
      - A fresh context whose init script makes `Storage.prototype.getItem` and `setItem` throw, at 1000×800: the note shows, Close takes it away, the composer is visible, and the console holds no error.
17. `docker/tests/test-floor.sh` -- the header and the PASS and FAIL lines name G1-G7 -- the unit names what it ran.
18. **Sweep.**
    - Search `web/e2e/` and `web/scripts/` for `collapse()`, `section.rail`, `getByRole('region', { name: 'Status'`, `app-inline-notice`, `readFlag` and `skip(`, and confirm or update each reader.
    - Search `web/src/app/` for every `.focus(`, `afterNextRender(`, `@media` and `position:` against the ratchets.

**Acceptance Criteria:**
- **The bands (FR-12, UX-DR20, UX-DR137).**
  - **Given** the browser window's size,
  - **when** the page lays out,
  - **then:**
    - from 1440px wide the rail is `rail-width-wide`;
    - from 1280 to 1439px it is `rail-width`, and every UJ-1 control is reachable without scrolling the page, because each region scrolls on its own;
    - from 1024 to 1279px the rail becomes a drawer, opened from a "Status" header button that shows the approval request count;
    - below 1024px or at 200% zoom the page becomes one scrolling column (header, banners, the chat scrolling on its own at `min(70vh, content)`, then the status sections), with only a compact header sticky.

  Tests: G1 (wide and reference), G2 and G3 (drawer), G4 and G5 (column), `layout-view.test.mjs`, `rail-view.test.mjs` and `floor-sources.test.mjs` (bands, sticky).
- **The note (UX-DR35, UX-DR128, UX-DR138).**
  - **Given** the stacked layout,
  - **when** it shows,
  - **then** the info inline notice "This page is designed for a wider window. Everything still works." shows once per session, and its close is remembered per browser.

  Tests: G6, G7 and `layout-view.test.mjs`.
- **The floor holds in every band (NFR-25; Stories 2.12 and 2.14).**
  - **Given** the drawer or the column,
  - **when** I use only the keyboard,
  - **then:**
    - the skip links reach their regions (a closed drawer opens);
    - one Esc acts on one layer, the drawer last;
    - every ring is inside the viewport and never under the sticky header;
    - focus survives a layout change;
    - the note's Close returns focus through the focus rule.

  Tests: G2, G3, G5, G4 (focus kept), G6 (Close), and K1 to K6 and W1 to W4 unchanged.
- **Integration (Rule 1).**
  - **Given** the real page on a real stack,
  - **when** the width changes,
  - **then:**
    - `Header`, `MainPage` and `SkipLinks` read `Layout` (G2, G3, G4);
    - `Header` reads `pendingApprovals` through the live store, and its count equals the rail's heading (G2);
    - `MainPage` drives `NarrowNote` and renders `InlineNotice`'s Close (G6 and G7);
    - `TraceHelp` and `NarrowNote` read and write through `stored-flag.ts` (G7; the trace links' cases in `live:sign-in` unchanged).

## Spec Change Log

## Review Triage Log

### 2026-10-24 - Review pass
- verdicts: 30 findings - high 0, medium 4, low 24, false 2, maybe-false 0
- findings:
  - `[medium]` `[patch]` blind: the "every query is an interpolation" test captured `$` and could not fail - patched: the width conditions are read with a pattern that keeps `${...}`, a self-test for it, and a mutation (a typo'd name) that goes red.
  - `[low]` `[reject]` blind: the stacked list is capped at `70vh`, not `dvh` - the spec fixes `max-height: 70vh` and G4 measures 70% of `innerHeight`; it is spec-bound.
  - `[low]` `[reject]` blind: the header's `ResizeObserver` has no guard and no cleanup - the header lives as long as the page, and every supported browser has the observer; a guard is added complexity for no reachable failure.
  - `[low]` `[reject]` blind: no unit tests for `Layout`, `NarrowNote` and `stored-flag` - the spec's test plan puts them in G1 to G7, which run them for real; a host for the services is new infrastructure.
  - `[low]` `[reject]` blind: Esc on the Status button does not close the drawer - spec-bound (Decided: the Esc handler is on the rail, the button toggles), so it reopens only through a spec amendment.
  - `[low]` `[reject]` blind: G6 and G7 use a 1.5 s wait before an absence check - the recorded mutations show the checks fail when the defect is present.
  - `[low]` `[patch]` blind: a wrong doc on `headerBottom`, a missing doc on the G7 storage case, an unneeded export of `inside` - patched.
  - `[low]` `[reject]` edge: no range-syntax media query support - the range syntax is Decided 1's choice and holds in the supported browsers (Chrome 104, Firefox 63, Safari 16.4).
  - `[low]` `[reject]` edge: the Status button is removed while it holds focus when the band changes - a window change with focus on the button is rare and recovers at the next Tab; the fix (a focus rule for the header) is not a two-way door. reopen_if=a user report of lost focus after a zoom change.
  - `[low]` `[reject]` edge: Esc on the Status button - the same finding as the blind one above.
  - `[low]` `[reject]` edge: the `ResizeObserver` is not guarded - the same finding as the blind one above.
  - `[low]` `[reject]` edge: the root property is not removed on destroy - the header is never destroyed while the page lives.
  - `[false]` `[reject]` edge: `place` may run before the view exists - the rail and main are in the template unconditionally, and G4 and G5 load at 1000 and 640px and find `main.main + section.rail`.
  - `[low]` `[reject]` edge: the refocus of a moved rail element may aim at a removed node - the rail's elements are not removed by the move, and a removed node's `focus()` does nothing.
  - `[low]` `[reject]` edge: `scrollIntoView` runs in every band - in the framed bands no ancestor scrolls as a page, so it changes nothing there; G1 and K1 pass unchanged.
  - `[low]` `[reject]` edge: the G1 walk ends at any name that holds "Send" - the walk asserts the first stop and the Trace count, and no rail or chat control before the composer holds "Send".
  - `[low]` `[reject]` edge: the G5 walk's failure message is generic - the failure names the stop count and the last five stops in the thrown error.
  - `[false]` `[reject]` edge: `drawerOpen` stays true outside the drawer band - it is read only under the `drawer` class and on entering the band, where `changed()` sets it from focus.
  - `[low]` `[reject]` edge: the same `scrollIntoView` claim - rejected as above.
  - `[medium]` `[patch]` verification-gap: the skip-link case did not pin the region into the window - patched: the ring's top must lie inside the window, with a mutation (no `scrollIntoView`) that goes red.
  - `[medium]` `[patch]` verification-gap: the popover-trigger arm of the band entry had no test - patched: G3 opens a rail Trace link's help at 1280px and narrows, with a mutation (no `triggerOf`) that goes red.
  - `[medium]` `[patch]` verification-gap: the header's measured size was never told from the 56px default - patched: G5 expects the root property to equal the header's height, with a mutation (the observer never observing) that goes red.
  - `[low]` `[reject]` verification-gap: `DecisionStrip`'s `stopPropagation` has no consumer - it is the lead's ruling (Decided 4: both disclosures stop the Esc), kept for the drawer's Esc order; the source check pins it.
  - `[low]` `[patch]` verification-gap: `layout-view.test.mjs` had no mutation line - patched: the singular branch of `statusCount` is mutated and the line recorded.
  - `[low]` `[patch]` verification-gap: several pinning tests had no mutation line - patched: `closeDrawer`'s focus move, `NOTE_RULE`, `writeFlag`'s `try`, the Close wiring, `preventDefault` and the wide query each have a recorded mutation.
  - `[low]` `[patch]` verification-gap: assertions that cannot fail - patched where it was real: the G5 backward walk now expects it read the rail's stops; the focus-then-assert steps of G2 and G3 set up the case, and the G6 and G7 waits are rejected as above.
  - `[low]` `[reject]` intent: the Status button after a failed load is not tested in a browser - `statusCount(undefined)` is in the node test and the button reads it, so a failed load shows "Status" alone.
  - `[low]` `[reject]` intent: an Esc taken by a shown tooltip is not exercised - the tooltip's capture-phase Esc is Story 2.14's and unchanged; the drawer adds no handler before it.
  - `[low]` `[reject]` intent: no case at 1023px or at a fractional width - the range queries leave no gap and `layout-view.test.mjs` evaluates the edges; G2 reaches 1024 and 1279.
  - `[low]` `[reject]` intent: G7 does not narrow again after a failing storage - the matrix asks that Close works for the page, which G7 asserts.

## Design Notes

**Governing ADs and conventions (Rule 6).**
- **AD-13:** text as text and the CSP `script-src 'self'`. Every new string is bound by interpolation, there is no inline script and no `bypassSecurityTrust*`, and the tests change the viewport and storage through Playwright, not the page.
- **AD-12:** one live path. No poller and no event is added. The count reads the live store.
- **AD-22:** Playwright specs on a throwaway stack, and Node tests in `web/scripts/`. `ci/iris.sh` is the one recipe and `ci/units.sh` the one list, both unchanged.
- **AD-29:** `web/` and `docker/tests/test-floor.sh` are Lane B's.
- **AD-33:** no new event type or publisher.
- **Conventions:**
  - **Angular:** standalone components, signals, CDK plus custom components.
  - **Announcements and focus:** the note speaks only through `Announcer`, once, and never at load. The new `.focus(` calls are the user's own moves, plus one that keeps focus on the same element across the move, each listed with its reason. The note's Close goes through `shared/focus-rule.ts`.
  - **Tests:** the floor specs live in `web/e2e/floor/` and run in `live:floor`.
  - **Text OcuTalon sends:** page constants, nothing added to the catalog.
- **Stack:** no new dependency. `matchMedia` and `ResizeObserver` are platform APIs.

No AC contradicts an AD's Rule.

**Rule 5:** no NFR is unmeasurable. The bands are CSS widths read in the page. "200% zoom" is the CSS width it gives, which is measurable by emulation (Decided 1).

**Decided in-stage** (small, reversible, within the intent):
1. **The bands come from the CSS width alone.**
   - "At 200% zoom" is read as the width zoom gives: a 1280px window at 200% is 640 CSS px. W3C's Understanding SC 1.4.10 equates a 1280px viewport at 400% with 320 CSS px. E:443 and E:463 tie the stacked layout to "below 1024 CSS pixels (including 200% zoom)".
   - Browsers expose no reliable zoom level, since `devicePixelRatio` mixes zoom with screen density.
   - The tests emulate 200% as 640×360 at device scale 2 (Task 0 b), because Playwright cannot press browser zoom.
2. **The drawer pushes; it is not an overlay.** The UX says only "drawer". Pushing means:
   - nothing ever covers a focused control in the chat (WCAG 2.4.11);
   - there is no light-dismiss or focus-out logic;
   - there is one rail instance, so the focus rule, the skip link target and the Esc guard hold unchanged.

   With no device column yet, the chat keeps at least 736px. Story 4.5's device column may revisit this at 1024px.
3. **Opening, closing and entering the band.**
   - Opening focuses the region, as "Skip to status" does, so the next Tab is inside it.
   - Closing returns focus to the Status button when it was inside the rail. This also covers a click that does not focus the button, as in Safari (inference).
   - Entering the band closes the drawer unless focus is inside the rail.
4. **Esc order.** A disclosure that acts on Esc stops the event, so the drawer, the outermost layer, closes only on an Esc nothing inside it used. This extends Story 2.14's `hasOpen()` guard and does not replace it.
5. **The count.**
   - No count before the snapshot has loaded or when it failed: a "0" there would be a false all-clear.
   - After the load, 0 shows, because the AC says the button shows the count.
   - The count comes from the same function as the rail's heading.
6. **The column's DOM order is the visual order.**
   - E:64's order (rail before chat) holds at 1024px and wider, and F1 pins it. The column puts the chat first.
   - CSS `order` alone would send Tab to the rail first, the bottom of the page, before the chat (WCAG 1.3.2, 2.4.3). `reading-flow` is not in every supported browser (inference).
   - So `MainPage` moves the one static `section.rail`, and keeps the focus of an element inside it (Task 0 d).
7. **Document scroll with a sticky compact header,** not an inner scroller. Keyboard scrolling works from the page's start, and the scroller adds no tab-stop gap (compare DW-89). `scroll-padding-top` from the measured header size keeps focus clear of it (Task 0 c), even when the header wraps or text grows.
8. **The compact header** holds the same controls and words, at 48px minimum height with 12px inline padding, and may wrap. It is sticky only below 1024px. It adds no text, so it is not a veto item.
9. **The note.**
   - "Once per session" means once per browser session (sessionStorage), the UX's own word for the Visual Trace popover's "seen" (E:386-387), as `TraceHelp` keeps it.
   - "Remembered per browser" means localStorage.
   - The flags are read once and held in memory, so a storage failure still gives once per page load.
   - The note sits at the top of the main page's column, under the banners (E:465: "at the top").
   - It is silent at load and announced when it appears later (UX-DR35).
10. **The unit.** G1 to G7 join `live:floor`, whose 540 s local deadline holds about 140 s of 24 cases today. They add about 25 to 45 s (inference), so no second unit is needed.
11. **Ids:** G1 to G7 (G is unused in `web/e2e/`).
12. **No split.** It is one layout criterion plus the note, which only exists in the stacked layout. That comes to about 12 page files, 3 ratchet edits and 7 browser cases, with no server work.

**Veto-window items** (public text the UX does not write out):
- **The Status button's count:**
  - visibly "Status" with the count in a `tab-badge` pill (the UX's count badge, D:481-485);
  - named "Status, 2 approval requests", "Status, 1 approval request" or "Status, 0 approval requests";
  - before the snapshot loads, "Status" alone.

  Alternatives: the rail heading's text form, "Status (2)" spoken "Status, 2"; or the pill only when n > 0.
- **The note's Close:** "Close narrow-window note". These are the UX's own words for it (E:465, "The narrow-window note"), with verb plus object as in Story 2.14's banner Close names. Alternative: "Close the narrow window notice".
- **The drawer has no heading and no Close of its own, and is not modal.** It adds no text. It is listed so that you can rule: the alternative is a visible "Status" heading and a "Close status" button inside it.

**For the lead (your calls).**
- The veto items above, and Decided 2 (push, not overlay) and Decided 6 (moving the rail in the DOM for the column).
- **Decided 4 edits Story 2.6's `decision-strip.ts` and Story 2.8's `decision-row.ts`:** `collapse(event)`, which stops the event when it collapses. Both are Lane B's web, in this epic.
- **Footprint.** Every file is in `web/` or `docker/tests/test-floor.sh`. Shared web infrastructure is edited, which you report: `web/src/styles/base.css` and `web/src/app/shared/inline-notice.ts`.
- **The balance rule (inference).**
  - In run 40135456843 (832aaad), `live:floor` took 284 s in `shards`, with Playwright at 1.5 min for 24 cases. The jobs took 544, 1013, 770, 708, 490 and 435 s, a mean of 660 s, and `shards` was 1.17 times the mean.
  - With G1 to G7 (about 25 to 45 s), `shards` comes to about 800 to 815 s, against a mean of about 666 s: 1.20 to 1.22 times, inside 1.25.
  - `browser`, at 1.53 times, was already over before this story.
  - Measure at this story's first CI run. Story 2.16 places the unit again.
- **Story 2.14's 200% residuals.**
  - About at 640×360 is rechecked by G5.
  - The banner's inset halo goes to Story 2.16's scan.
  - The stale composer height after a text-size change is a text-size effect, not a zoom effect, and is unchanged.
- **Later epics.**
  - Story 4.4 (the guide in the column and its compact form), Story 4.5 (the device column at 352/384px, its place in the column, "Skip to simulated devices" through `focusRegion`) and Story 12.3 (the unpaired Telegram card at 1024 to 1279px and in the column) read `Layout` and `LAYOUT_QUERIES`.
  - Story 6.2 owns UX-DR20's incident card at 1280×600.

**Integration ACs (Rule 1).** The new shared pieces and their consumers in this story:
- `Layout`: consumed by `Header`, `MainPage` and `SkipLinks` (G2 to G5).
- `layout-view.ts`: consumed by `Layout`, `Header`, `NarrowNote`, `MainPage` and `floor-sources.test.mjs`.
- `NarrowNote`: consumed by `MainPage` (G6, G7).
- `InlineNotice.closeName`: consumed by `MainPage`'s note (G6).
- `stored-flag.ts`: consumed by `TraceHelp` and `NarrowNote` (G7).
- `pendingApprovals`: consumed by `railView` and `Header` (G2).
- `support/floor.ts`'s ring helpers and `seedScrollingPage`: consumed by `keyboard.spec.ts` (K4) and `layout.spec.ts` (G1, G4, G5).

**Consumed-by:**
- **2.16:** the string test reads `LAYOUT_TEXTS`; its Firefox and WebKit subset may run G-cases; DW-89's rail tab stop keeps `id="status-region"` and the skip target.
- **4.4:** the guide in the column, and its compact form at 1024 to 1279px.
- **4.5:** the device column and its place, and "Skip to simulated devices" through `Layout.focusRegion`.
- **12.3:** the unpaired Telegram card's place.
- **Every later page story:** the bands, and `floor-sources.test.mjs`'s band and sticky lists.

**Consumes:**
- 2.1: the header, `Popovers`, About and `InlineNotice`;
- 2.5: the chat panel;
- 2.6: the strip;
- 2.8: the rail, `rail-view.ts` and the decision row;
- 2.10 and 2.11: the banner slot;
- 2.12: `focus-rule.ts` and `Announcer`;
- 2.13: `TraceHelp`'s flags;
- 2.14: the skip links, `hasOpen()`, the ring rules, the ratchets and K4's helpers.

**Extend, don't copy (Rule 2).**
- `stored-flag.ts` is `TraceHelp`'s pair, moved.
- `NarrowNote` follows `TraceHelp`'s shape (flags read once and held in memory). It is a second service because its flags, its trigger and its announcement differ.
- `pendingApprovals` is `railView`'s filter, exported.
- The note's Close extends `InlineNotice`, not a new notice. Its markup follows the banners' Close.
- The G-cases import K4's ring helpers and seed, moved to `support/floor.ts`.
- The count pill reuses the `tab-badge` tokens.

**Ledger (Rule 17):** the inbox for this story is empty, so no entry is addressed or declined.

## Verification

**IRIS.** This story changes no ObjectScript, so no slot call is needed. If a stage makes one:
- name `server: ocutalon-slot-b` and `namespace: OCUTALON`;
- make `iris_server_info` (build 154, port 1991) the first call;
- make one `iris_execute_tests` call per message.

**Throwaway commands** are `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_RUN_TAG=e2s215i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`.
- `<main checkout>` is typed only at the prompt, never in a tracked file.
- Run one piece per call with `timeout: 600000`, and end with `teardown` on the same tag.
- `LOCK busy` (exit 75) means wait 30 to 90 s and run it again.
- QA uses `e2s215q` (stage `qa`), and review uses `e2s215r` (stage `review`).

Every other command runs in the foreground with `timeout: 600000`.

**Commands:**
- **(loop)** Each in its own call: `npm --prefix web test`, `npm --prefix web run lint`, `node web/scripts/catalog.mjs --check`, `bash docker/tests/test-web-build.sh` and `bash docker/tests/test-boundaries.sh`. Expected: exit 0, with `layout-view.test.mjs`, `rail-view.test.mjs`, `floor-sources.test.mjs`, `announce-focus-sources.test.mjs`, `floor-fixtures.test.mjs`, `trace-view.test.mjs` and `shell-styles.test.mjs` passing.
- **(loop)** Throwaway, one piece per call: `build`; `live floor`; `teardown`. Expected:
  - A1 to A7, H1, P1 to P4, K1 to K6, W1 to W4 and G1 to G7 pass;
  - teardown leaves nothing.
  - **Time:** about 165 to 190 s locally (inference: 140 s today plus G1 to G7). Record the measured figure here.
- **(once)** In their own calls: `bash docker/tests/test-ci-config.sh` and `bash ci/checks.sh`. Expected: exit 0.
- **(once)** Throwaway, one piece per call: `build`; `live sign-in`; `live demo-path`; `live bundle-folder`; `group shards`; `teardown`. Expected:
  - everything passes, with the same skips as before;
  - B12's 800×900 step, R1, F1 and the chat fill case pass unchanged;
  - `live sign-in` takes about 410 s (record it), and `group shards` about 320 s locally (record it).

**Planned mutations (Rule 19).** For each: apply it, observe red, restore a byte-identical tree (`git status --short` and the hash of `git diff` unchanged), and record `mutation: ... -> ...` below.

| AC | Mutation | Expected red |
| --- | --- | --- |
| Bands | the wide query's `.rail` width rule removed | G1 (320px) |
| Bands | `app.ts` with `min-height` only, at every width | G1 (the page scrolls at 1280×600) |
| Bands | the Status button without its count | G2; `layout-view.test.mjs` if `statusCount` changes |
| Bands | `pendingApprovals` without the `pending` filter | `rail-view.test.mjs` |
| Bands | the closed drawer not hidden (`display` rule removed) | G2 (the region shows while collapsed) |
| Floor | `DecisionRow.collapse` without `stopPropagation` | G2 (one Esc collapses the row and closes the drawer); `floor-sources.test.mjs` |
| Floor | `MainPage.collapse` ignores `hasOpen()` | G2 (the help step closes the drawer); `floor-sources.test.mjs` |
| Floor | `focusRegion` focusing without opening the drawer | G3 |
| Floor | the band-entry rule ignoring focus in the rail | G3 |
| Bands | the rail placed with CSS `order` only, with no DOM move | G4 (DOM order); G5 (stop order) |
| Floor | the stacked `html` `scroll-padding-top` removed | G5 (a ring under the header) |
| Bands | `app-header` not sticky | G4 |
| Bands | the compact header's rules removed | G4 (not shorter) |
| Bands | the stacked list's `max-height` removed | G4 |
| Floor | the placement without the re-focus | G4 (focus kept) |
| Note | "shown" not written to sessionStorage | G6 (it shows again after a reload) |
| Note | "closed" not written to localStorage | G6 (the third page shows it) |
| Note | the note announced at load | G6 |
| Note | no announcement after load | G7 |
| Note | `readFlag` without its `try` | G7 (a console error, no note) |
| Bands | a `@media (max-width: 1000px)` added to a component | `floor-sources.test.mjs` (bands) |
| Bands | `position: sticky` in `chat-panel.ts` | `floor-sources.test.mjs` (sticky) |

**Recorded mutations (Rule 19).** Each was applied, run, observed red and reverted to a byte-identical tree (`git status --short` and the hash of every file under `web/src`, `web/e2e`, `web/scripts` and `docker/tests` unchanged). Browser reds are `live floor` on throwaway tag `e2s215i`; the others are `node --test web/scripts/`.
- mutation: the wide query's `.rail` width rule removed -> G1 red (the rail is 288px at 1440px).
- mutation: `app.ts` with `min-height` only, at every width -> G1 red (the page scrolls at 1280x600); K1 and K4 also red.
- mutation: the Status button without its count (`count` always undefined) -> G2 red (the name is "Status" and not "Status, n approval requests").
- mutation: `pendingApprovals` without the `pending` filter -> `rail-view.test.mjs` red (three tests).
- mutation: the closed drawer not hidden (the `display: none` rule removed) -> G2 red (the region shows while collapsed).
- mutation: `DecisionRow.collapse` without `stopPropagation` -> G2 red (one Esc collapses the row and closes the drawer); `floor-sources.test.mjs` red.
- mutation: `DecisionStrip.collapse` without `stopPropagation` -> `floor-sources.test.mjs` red (no browser case reaches a strip inside the drawer).
- mutation: `MainPage.collapse` ignores `hasOpen()` -> G2 red (the Trace help step closes the drawer); `floor-sources.test.mjs` red.
- mutation: `focusRegion` focusing without opening the drawer -> G3 red (Skip to status leaves `aria-expanded` false).
- mutation: the band-entry rule ignoring focus in the rail (`drawerOpen` set to false on entering) -> G3 red (narrowed with focus in the rail, the drawer is closed).
- mutation: the rail placed with CSS `order` only, no DOM move -> G4 red at 1000x800 and at 200% (`main.main + section.rail` is absent); G5 red (stop order).
- mutation: the stacked `html` `scroll-padding-top` removed -> G5 red in both cases (going back, a ring lies under the header; Skip to status leaves its ring at 3.8px under a 56px header).
- mutation: `app-header` not sticky -> G4 red at 1000x800 and at 200% (the header leaves the top after scrolling).
- mutation: the compact header's rules removed -> G4 red at 1000x800 and at 200% (the header is not shorter than at 1280x720).
- mutation: the stacked list's `max-height` removed -> G4 red at 200% (the list is as tall as its content, not 70% of the window).
- mutation: the placement without the re-focus -> G4 red at 1000x800 and at 200% (the rail's Trace link lost focus).
- mutation: "shown" not written to sessionStorage -> G6 red (a reload in the same tab shows the note again).
- mutation: "closed" not written to localStorage -> G6 red (the third page shows the note).
- mutation: the note announced at load (`atLoad` ignored) -> G6 red (its text was announced at load).
- mutation: no announcement after load -> G7 red (the note's text is never announced).
- mutation: `readFlag` without its `try` -> G7 red (the page does not load: no `main.main`, so no note).
- mutation: a `@media (max-width: 1000px)` added to a component -> `floor-sources.test.mjs` red (bands: both lists of width conditions).
- mutation: `position: sticky` in `chat-panel.ts` -> `floor-sources.test.mjs` red (sticky).

Review pass (2026-10-24). Browser reds are `live floor` on throwaway tag `e2s215i` (one batch applies mutations to different files or cases, and the red that names each is the one recorded); the others are `node --test web/scripts/`. A restore is checked by the hash of `git diff` and by a diff of `web/src` against the diff taken before the batch (untracked files are not in `git diff`).
- mutation: the width of a component's `@media` typed as `${LAYOUT_QUERIES.stacekd}` -> `floor-sources.test.mjs` red (the interpolation test and the bands test).
- mutation: `statusCount`'s singular branch (`n === 1`) never taken -> `layout-view.test.mjs` red ("1 approval request").
- mutation: `Layout.closeDrawer` without the move of focus to the Status button -> G2 red (focus is not on the button after the second Esc).
- mutation: `NOTE_RULE`'s effect removed from `MainPage` -> G6 red (focus is not on the main region after Close).
- mutation: `writeFlag` without its `try` -> G7 red (with a storage that throws the note does not show).
- mutation: the skip link without `preventDefault` -> G3 red (the address changed after Skip to status); K1 also red.
- mutation: `focusTarget` without `scrollIntoView` -> G5 red (Skip to status: the ring's top lies below the window, the page is scrolled to 0).
- mutation: `focusInRail` without `Popovers.triggerOf` -> G3 red (narrowed with the help of a rail trigger open, the drawer is closed).
- mutation: `InlineNotice`'s Close without `closed.emit()` -> G6 and G7 red (Close does not take the note away).
- mutation: `LAYOUT_QUERIES.wide` at 1280px instead of 1440px -> G1 red (the rail is 320px at 1439px and 1280px) and G2 red (at 1280px the rail is not 288px).
- mutation: the header's `ResizeObserver` never observing -> G5 red (the root holds no `--app-header-block-size`).

**Measured (local, 2026-10-24).** `live floor` takes 160 s of the script's own run (24 cases before, 35 now: G1 to G7 are 11 Playwright cases), 158 s inside `group shards` (326 s in all, with `shard:lane-a` 63 s and `shard:lane-b` 105 s). `live sign-in` takes 417 s (190 passed, 2 skipped), `live demo-path` 68 s and `live bundle-folder` 88 s.

**Measured at the last pass (local, 2026-10-24).** `live floor` 154 to 160 s (35 cases), `live sign-in` 407 s (190 passed, 2 skipped), `group shards` 318 s (`shard:lane-b` 101 s, `live:floor` 154 s), `live demo-path` and `live bundle-folder` green; `npm --prefix web test` 534 passed.

**Shared surfaces:**
- **The ratchets' lists:** the speakers, `FOCUS_CALLS` (`skip-links.ts` 1 → 0; `layout.ts` 2; `main-page.ts` 1), the render list, `KEY_HANDLERS`, the key bindings, `ESC_HOSTS` and its `collapse` regex, and `floor-fixtures.test.mjs`'s file list. `FIXED_HEIGHTS` and the scrollers list are unchanged.
- **The header's right group** gains the Status button in the drawer band only, so F3 and F7 at 1280px are unaffected.
- **`section.rail`** gains `id`, `class="open"` while open, and an Esc handler. In the column it follows main in the DOM, while F1 at 1280px keeps its order.
- **`InlineNotice`** gains an optional Close. The busy notice (L6, W4) is unchanged.
- **`TraceHelp`'s flag helpers** move, and the trace links' cases (`web/e2e/trace/`) are unchanged.
- **`railView`** reads `pendingApprovals` (`rail-view.test.mjs`).
- **B12's 800×900 step** is now the stacked layout and shows the note. It measures only the banners.
- **K4's helpers** move to `support/floor.ts`.
- **No server surface changes.**

**Every test added or changed passes on a fresh environment, in either order:**
- each G-case signs in the floor user in a fresh context, so its storage is empty;
- it seeds and removes only its own rows (`turnRows` included) and unroutes its own routes;
- G2 compares its count with the rail's own heading, so it does not depend on other cases' approvals;
- G6 and G7 own their contexts' storage;
- the Node tests read sources only.

**Manual checks (human-only):** none new. A real browser zoom to 200% at 1280×720 in Chrome, Firefox and Safari is the human's check of Decided 1's equivalence. Story 2.16 covers Firefox and WebKit by emulation.

## Auto Run Result

Status: done
Blocking condition: none

**Plan stage (2026-10-24).** The plan halted after planning, as the dispatch asked.
- It reused the committed `epic-2-context.md` without recompiling it, and took Story 2.14 as the continuity context.
- **Task 0** was measured with a scratch Playwright script on static pages in Chromium 156. It used no stack and no IRIS call, and started no throwaway. The script is not kept.
- It read the job and unit times of run 40135456843 with read-only `gh`.
- The ledger inbox was empty.
- **For the lead:**
  - the three veto items: the count's format, the note's Close name, and a drawer with no heading or Close of its own;
  - Decided 2 (a push drawer) and Decided 6 (the rail moves after main in the column);
  - Decided 4's edit to the strip's and the row's `collapse`;
  - the balance estimate for `shards`, 1.20 to 1.22 times the mean (inference).

**Implement and review (2026-10-24).**
- **Summary:** the page has the four width bands: the rail at 320px from 1440px, at 288px from 1280px, a push drawer behind a "Status" header button with the approval request count from 1024px, and below 1024px one scrolling column with the sticky compact header, the rail after main in the DOM and the once-per-session note. One module (`layout-view.ts`) holds the queries for the CSS and the `Layout` service. G1 to G7 join `live:floor` (35 cases).
- **Files:**
  - new: `web/src/app/shared/layout-view.ts`, `layout.ts`, `narrow-note.ts`, `stored-flag.ts`; `web/e2e/floor/layout.spec.ts`; `web/scripts/layout-view.test.mjs`.
  - changed: `app.ts`, `header.ts`, `skip-links.ts`, `main-page.ts`, `chat-panel.ts`, `decision-row.ts`, `decision-strip.ts`, `rail-view.ts`, `inline-notice.ts`, `trace-help.ts` and `base.css` under `web/src`; the node ratchets and `rail-view.test.mjs`; `web/e2e/support/floor.ts`, `keyboard.spec.ts`; `docker/tests/test-floor.sh` (the text of its messages).
- **Departures from the spec (decided in stage):** `position: relative` on `.rail` and `.list` (their hidden texts lengthened the page); the closed drawer is hidden by a class that `Layout` sets, not by the width query alone; the Status button's visible text and pill are `aria-hidden` beside a spoken name; `focusTarget` focuses with `preventScroll` and then scrolls the region's top into view; G4's empty chat runs at 1000x800 and G5's About asserts what fits at 640x360.
- **Review:** 8 patched, 4 at medium (a vacuous interpolation test, and the skip-link, popover-arm and header-size gaps) and 4 at low (docs and an export, mutation lines, the backward walk's count); nothing deferred; 22 rejected with their reasons in the triage log, 2 of them false.
- **Follow-up review recommended:** true, because four mediums were patched. The unverified risk is the keyboard and focus behaviour at a real browser zoom of 200% in Chrome, Firefox and Safari, and the focus lost when the Status button leaves with its band (rejected as rare).
- **Verification:** `npm --prefix web test` 534 passed, lint, `catalog.mjs --check`, `test-web-build.sh`, `test-boundaries.sh` green; `live floor` 35 passed (154 to 160 s); `test-ci-config.sh`, `ci/checks.sh` green; `live sign-in` 407 s (190 passed, 2 skipped), `live demo-path`, `live bundle-folder` and `group shards` (318 s) green; 11 mutations at review and 23 at implement went red and were reverted; teardown of tag `e2s215i` left nothing.
- **Residual risks:** the initial bundle is 538 kB against the 500 kB warning budget (a warning; the error budget is 1 MB), not compared with the baseline; real browser zoom is the human's check; the focus loss above.
