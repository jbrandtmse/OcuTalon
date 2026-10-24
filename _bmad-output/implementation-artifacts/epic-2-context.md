# Epic 2 Context: Chat with OcuTalon on a live web page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 2 turns the signed-in page into release 1's main page: chat, each reply's decision, cost and trace link, a live status rail and banners, all without a reload. Stories 2.1 to 2.13 are done, and 2.12 delivered the announcer queue and the focus rule. The three stories split from 2.12 bring the page up to the accessibility floor (keyboard alone, every control labelled, AA contrast; not a full audit): 2.14 covers keyboard use, labels and words, 2.15 the layout at every width, and 2.16 the proof in three browsers.

## Stories

- Stories 2.1 to 2.13: frame, session, routing, turns, chat, decisions, outcomes, rail, Visual Trace, banners, lost contact, announcements and focus (done)
- Story 2.14: Work the whole page by keyboard, with labels and words
- Story 2.15: Lay the page out at every supported width
- Story 2.16: Prove the floor in Chromium, Firefox and WebKit

## Requirements & Constraints

- **Contrast, in both themes:**
  - Text that carries meaning: at least 4.5:1.
  - Interactive boundaries (inputs, the composer, secondary buttons, actionable chips) and the focus ring: at least 3:1.
  - Exempt: the decorative `border` and the inactive Break the feed outline.
- **Browsers:** current desktop Chrome, Edge, Firefox and Safari, at 1280×720 and larger.
- **Text resizes to 200% without loss.** Heights are minimums, never fixed. Targets are at least 32px, and every page sets `lang="en"`.
- **Fixed strings match the UX word for word,** using the single "…" character. The turn indicator shows "Deciding" with animated dots but speaks "Deciding…".
- **New public text needs the veto window.** Any label or disabled reason the UX doesn't give is a veto-window item. The UX leaves open the drawer's heading, close control, count format and modality, the compact header's contents, and the name of the note's Close button.
- **Dependency licences:** a new dependency must be MIT, BSD-2/3-Clause, Apache-2.0 or ISC, pinned to an exact version, and recorded as a Stack row.
  - `axe-core` and `@axe-core/playwright` are MPL-2.0, so the scan has to be written in-house.
  - Unlabelled controls: use Playwright's own accessible names.
  - Contrast: compute it from computed styles in `page.evaluate`, using WCAG's formula and the exemptions above.

## Technical Decisions

- **The web app:**
  - Lane B owns `web/`: standalone Angular components with signals, the Angular CDK plus custom components (no component kit), and `DESIGN.md` tokens.
  - There is one typed API client and one live-event service. Don't add a second poller.
- **Security:**
  - The page's CSP is `script-src 'self'`.
  - Untrusted text renders as text, and nothing calls `bypassSecurityTrust*`.
  - Measure first whether the scan's `page.evaluate` runs under this CSP in Firefox and WebKit.
- **Announcements and focus (a binding convention):**
  - The page speaks only through `Announcer`, a single polite region. No other element gets `aria-live` or a log, status, alert or timer role.
  - One update's messages are joined into one text, and texts land at least 1 s apart.
  - At most three announcements are spoken in any 2 s; when two or more wait beyond that, they are spoken as "{n} new updates".
  - Each event is announced from one place only, and the first snapshot is silent.
  - Focus moves only when an update removes the focused element, and only through `shared/focus-rule.ts`.
  - A source ratchet pins the number of `.focus(` calls in each file. Every call you add needs its count and a reason added there too.
- **Tests:**
  - Playwright 1.64.x specs go under `web/e2e/`.
  - An unbuilt part is a `notBuilt(title, 'N.M')` call. A test that must never skip again carries `@floor`, and a skip never counts as a pass.
  - `web/e2e/demo-path/` holds only UJ-1's step specs.
  - The floor specs live in `web/e2e/floor/`.
  - The `live:sign-in` unit already uses about 460 s of its 540 s local deadline. From Story 2.14 on, new browser cases go to a unit of their own (for example `live:floor`, with its own throwaway stack and deadline).
- **CI:**
  - "The CI demo-path environment" means the `browser` group's throwaway stack, with the CI override and the model mock.
  - A full CI run takes at most 35 minutes.
  - No IRIS job runs more than about 25% over the mean of the six, and units move between groups whole.
  - If the slowest job runs over about 10 minutes, it goes to the owner as a CI-capacity item.
  - Estimate: Firefox and WebKit add about 9 to 12 minutes on the runner, which fits in `shards` but not in `browser`.
- **CI hosts:** they have only Chromium's system packages, and the runner user has no sudo.
  - Before Story 2.16 is implemented, the owner has to install the Firefox and WebKit packages.
  - The alternative is a digest-pinned Playwright image, which is a new dependency and so a veto item.
- **Trace tabs stay stubbed in the added browsers.** Real trace tabs seem to hold licence connections and starve the cases that run after them.

## UX & Interaction Patterns

- **Keyboard:**
  - The first tab stops are "Skip to chat" and "Skip to status", and each skip link's target takes focus.
  - Enter sends, and Shift+Enter adds a line.
  - Esc closes the topmost popover or dialog, and collapses a disclosure only when focus is inside it.
  - There are no single-character shortcuts.
- **Focus ring:** 2px solid `focus`, a 2px offset and a `surface` halo, used for nothing else.
  - It is never clipped, because every scroller keeps a 4px `scroll-gutter`, and it is never removed.
  - No selected marker looks like the focus ring.
- **Labels:**
  - Landmarks: banner, `main` (the chat), and the region "Status".
  - Icon buttons name both action and object, for example "Open in Visual Trace (opens in a new tab)". A bare "Close" isn't enough.
  - State is text, and icons are hidden from assistive technology.
  - A control that can't act stays focusable with `aria-disabled`, and `aria-describedby` points to its visible reason.
  - Busy buttons use `aria-disabled` and `aria-busy`, never `disabled`.
  - Disclosures are inline buttons with `aria-expanded`.
  - Only Visual Trace and README links open new tabs, and they say so.
- **Never colour alone:** every state has a word, and every link is underlined, including links styled as buttons. An error is text beside its cause, linked to its field.
- **Reduced motion:** under `prefers-reduced-motion`, nothing rotates, pulses, shimmers or scrolls smoothly. Skeletons never shimmer.
- **Banned:** modal notification interruptions, toasts as the only copy, sounds, tabs that switch by themselves, hover-only controls, drag-and-drop as the only way, model-progress bars, celebrations, and infinite scroll in counted lists.
- **Layout:** the page fills the viewport, each region scrolls on its own, and regions are separated by 1px borders.

  | Width | Layout |
  | --- | --- |
  | 1440px and wider | The rail is `rail-width-wide` (320px). |
  | 1280 to 1439px | The rail is `rail-width` (288px). Every UJ-1 control is reachable without scrolling the page. |
  | 1024 to 1279px | The rail becomes a drawer, opened from a "Status" header button that shows the approval request count. |
  | Under 1024px, or at 200% zoom | One column that scrolls as a page: header, banners, chat (scrolling on its own at `min(70vh, content)`), then status. Only a compact header is sticky. |

- **The narrow-window note:** an info inline notice (an icon and text on a tint, with no accent bar) reading "This page is designed for a wider window. Everything still works."
  - It shows once per session.
  - Its close is remembered per browser in local storage, and a storage failure is tolerated.
  - It is announced only if it appears after the page has loaded.

## Cross-Story Dependencies

- **What Story 2.12 hands over:**
  - **To Story 2.14:** disabled reasons and field errors may be announced through `Announcer`.
  - **To Story 2.15:** the drawer's rail keeps the rule that focus goes to the section heading when a row leaves, through the helper, and the note's Close returns focus the same way.
  - **To Story 2.16:** checking the announcer and the focus rule in Firefox and WebKit.
- **Also built on:** Story 2.1's header and popover service, Story 2.5's chat (in WebKit, check that an Enter confirming IME input doesn't send), Story 2.8's rail, the banners of Stories 2.10 and 2.11, and Story 2.13's trace links, Visual Trace menu and sign-in popover.
- **Story 2.16 comes after Stories 2.14 and 2.15,** because its scan and its string test cover their surfaces.
  - The string test covers the epic's text constants: `CHAT_TEXTS`, `NOTICE_TEXTS`, `DECISION_TEXTS`, `RAIL_TEXTS`, `TRACE_TEXTS`, `BANNER_TEXTS`, `BUSY_NOTICE`, `LOAD_FAILED` and `NEW_UPDATES`, plus the header strings and the skip, drawer and note texts.
  - A lean Firefox and WebKit subset is suggested: the load, the skip links, the Visual Trace menu toggle, the scrollers' tab stops, the scan in both themes, and one announcement. Chromium keeps the full suite.
- **Ledger items owned by Story 2.16:**
  - **DW-89:** the chat list and the rail each get a tab stop and a name, for example `tabindex="0"` labelled by the heading. The WebKit run checks it.
  - **DW-145:** in Safari and macOS Firefox, the Visual Trace button must close its own open menu, so the popover service has to treat a press on the trigger as inside. The Firefox and WebKit runs check it.
- **Not in these stories:** DW-159, the screen-reader check with VoiceOver and NVDA, is for a human.
- **Later epics:**
  - Story 4.5 inserts "Skip to simulated devices" between the two skip links.
  - Story 2.15 lays out only Epic 2's regions. The guide and simulated devices (Epic 4) and the unpaired Telegram card (Epic 12, Lane A) take their places in the drawer and stacked layouts in their own epics.
