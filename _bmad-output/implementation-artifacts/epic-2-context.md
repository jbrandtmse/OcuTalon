# Epic 2 Context: Chat with OcuTalon on a live web page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 2 makes the signed-in page release 1's main page. A user chats with OcuTalon and sees each reply with its decision, cost and trace link, a live status rail and status banners, all without a reload. Stories 2.1 to 2.14 are done. Two stories remain, and together they finish the accessibility floor (keyboard alone, every control labelled, AA contrast; not a full audit). Story 2.15 lays the page out at every supported width. Story 2.16 proves the floor in Chromium, Firefox and WebKit, with an accessibility scan and a string test. Epic 2 is part of the October 30 milestone, "working demo path (local)".

## Stories

- Stories 2.1 to 2.14 (done): the frame; the session and live updates; routing commands; the turn pipeline; chat; decisions; outcome routing; the rail; Visual Trace; banners; lost contact; announcements and focus; Visual Trace from the page; keyboard and labels
- Story 2.15: Lay the page out at every supported width
- Story 2.16: Prove the floor in Chromium, Firefox and WebKit

## Requirements & Constraints

- **Layout (2.15).** The page fills the viewport, each region scrolls on its own, and regions are separated by 1px borders.

  | Width (CSS px) | Layout |
  | --- | --- |
  | 1440 and wider | The rail is `rail-width-wide` (320px). |
  | 1280 to 1439 | The rail is `rail-width` (288px). Every UJ-1 control is reachable without scrolling the page. |
  | 1024 to 1279 | The rail becomes a drawer, opened from a "Status" header button that shows the approval request count. |
  | Under 1024, or at 200% zoom | One column that scrolls as a page: header, banners, the chat (scrolling on its own at `min(70vh, content)`), then the status sections. Only a compact header is sticky. |

  - 200% browser zoom at 1280px gives a 640px layout, so it lands in the stacked layout.
  - Text must resize to 200% without loss, so heights are minimums.
  - Optional, beyond the floor: no horizontal scrolling at 320px.
- **The narrow-window note (2.15).** In the stacked layout, an info inline notice (an icon and text on a tint, with no accent bar) reads "This page is designed for a wider window. Everything still works."
  - It shows once per session.
  - Its close is remembered per browser in local storage, and a storage failure is tolerated.
  - It is announced only if it appears after the page has loaded.
- **Supported browsers:** current desktop Chrome, Edge, Firefox and Safari. Story 2.16's tests run at 1280×720 and 1280×600, in the light and dark themes.
- **Contrast, in both themes:**
  - Load-bearing text: at least 4.5:1.
  - Interactive boundaries (inputs, the composer, secondary buttons, actionable chips) and the focus ring: at least 3:1.
  - The orange "Talon" wordmark is large bold text, so it needs only 3:1.
  - Exempt: the decorative `border` and the inactive Break the feed outline.
- **Fixed strings match the UX word for word,** with the single "…" character ("Deciding…", "Working…", "Reconnecting…"). The turn indicator shows "Deciding" with animated dots and speaks "Deciding…".
- **New public text is a veto-window item.** The UX doesn't give:
  - the drawer's heading, its close control, its count format, or whether it is modal;
  - what the compact header holds;
  - the name of the note's Close button. That name must include its object; a bare "Close" isn't enough.
- **Dependencies:** a new one must be MIT, BSD-2/3-Clause, Apache-2.0 or ISC, pinned to an exact version, and recorded as a Stack row.
  - `axe-core` and `@axe-core/playwright` are MPL-2.0, so the scan is written in-house.
  - Unlabelled controls: use Playwright's accessible names.
  - Contrast: compute it from computed styles in `page.evaluate`, with WCAG's formula and the exemptions above.
- **CI budget:**
  - A full run takes at most 35 minutes.
  - No IRIS job runs more than about 25% over the mean of the six jobs.
  - If the slowest job runs over about 10 minutes, its times go to the owner as a CI-capacity item.

## Technical Decisions

- **The web app:** Lane B owns `web/`. It uses standalone Angular components with signals, hash routing, and the Angular CDK plus custom components styled from the `DESIGN.md` tokens. There is one typed API client and one live-event service.
- **Security:** the CSP is `script-src 'self'`, and model text renders as text. Measure first whether the scan's `page.evaluate` runs under this CSP in Firefox and WebKit.
- **Announcements and focus (a binding convention):**
  - The page speaks only through `Announcer`, a single polite region.
  - Focus moves only when an update removes the focused element, and only through `shared/focus-rule.ts`.
  - A source ratchet pins each file's number of `.focus(` calls, so every new call needs its count and a reason.
- **Floor tests:**
  - The floor specs live in `web/e2e/floor/` and run only in their own unit, `live:floor` (`docker/tests/test-floor.sh`). Never add them to `live:sign-in`, which is near its deadline.
  - An unbuilt part is a `notBuilt(title, 'N.M')` call, and a test that must never skip again carries `@floor`.
  - Floor cases never stop IRIS or its web server, never hold a poll for 8 s or longer, and never let a chat post reach the server.
- **The `live:floor` unit today:**
  - It has 24 cases and takes about 140 s locally. It runs in the `shards` group, where the CI estimate is 330 to 450 s.
  - Story 2.14's first CI run, still pending, measures `shards` against the balance rule.
  - Firefox and WebKit are estimated to add 9 to 12 minutes on the runner, so Story 2.16's plan places the unit again. The extra time fits in `shards` but not in `browser`.
- **Registering units:** Lane B registers units only in its own entries of `ci/units.sh`. `ci/iris.sh`, `ci/warm.sh` and `docker/tests/test-ci-config.sh` are contended and stay read-only.
- **CI hosts:** `ocutalon-ci-b` and `-c` have only Chromium's system packages, and the runner user has no sudo.
  - Before Story 2.16 is implemented, the owner has to install the Firefox and WebKit packages, for example with `sudo npx -y playwright@1.64.1 install-deps firefox webkit`.
  - The alternative, a digest-pinned Playwright image, is a new dependency and so a veto item. It also costs about 2 GB per host.
  - There is no record that this owner item has been raised or resolved, so confirm it at Story 2.16's plan.
- **Trace tabs stay stubbed in the added browsers (DW-146, escalated):** real trace tabs seem to hold licence connections and starve the cases that run after them.

## UX & Interaction Patterns

- **Skip links:** "Skip to chat" and "Skip to status" are the first tab stops, and each target takes focus. "Skip to status" must keep working when the rail is a drawer or a stacked section.
- **Focus ring:** 2px solid `focus` at a 2px offset with a `surface` halo, never clipped and never removed. The drawer's and the stacked layout's scrollers keep the 4px `scroll-gutter` and `scroll-padding`.
- **Focus in the drawer:** when a row leaves its list, focus goes to the section heading through the focus-rule helper. The note's Close returns focus the same way.
- **Labels:** icon buttons name their action and object, state is text, and icons are hidden from assistive technology. A control that can't act uses `aria-disabled` with its visible reason linked by `aria-describedby`. Disclosures use `aria-expanded`.
- **Never colour alone:** every state has a word and every link is underlined.
- **Reduced motion:** nothing rotates, pulses, shimmers or scrolls smoothly.
- **Banned:** modal notification interruptions, toasts as the only copy, sounds, tabs that switch by themselves, hover-only controls, drag-and-drop as the only way, model-progress bars, celebrations, and infinite scroll in counted lists.

## Cross-Story Dependencies

- **Story 2.15 builds on:**
  - Story 2.1's header, popovers and dialogs;
  - Story 2.8's rail (its Telegram card, `web/src/app/rail/telegram-card/`, is Lane A's from Epic 12);
  - the banners of Stories 2.10 and 2.11;
  - Story 2.14's skip links.
- **Story 2.16 comes after Stories 2.14 and 2.15,** because its scan and string test cover their surfaces.
  - **The string test** checks these against EXPERIENCE.md's quoted texts:
    - the text constants `CHAT_TEXTS`, `NOTICE_TEXTS`, `DECISION_TEXTS`, `RAIL_TEXTS`, `TRACE_TEXTS` (including `conversationNotYet`), `BANNER_TEXTS`, `BUSY_NOTICE`, `LOAD_FAILED` and `NEW_UPDATES`;
    - `SKIP_LINKS`, the two banner Close names and About's Close;
    - the header's inline strings;
    - Story 2.15's drawer and note texts.
  - **The scan's names check** extends Story 2.14's K5 case.
  - **A lean Firefox and WebKit subset is suggested:** the load, the skip links, the Visual Trace menu toggle, the scrollers' tab stops, the scan in both themes, and one announcement. Chromium keeps the full suite.
  - **Also check in Firefox and WebKit:** the announcer and the focus rule, and (WebKit) that an Enter confirming IME input doesn't send.
- **Ledger items owned by Story 2.16:**
  - **DW-89:** the chat list and the rail each get a tab stop and a name, for example `tabindex="0"` labelled by the heading. On the rail this replaces Story 2.14's `tabindex="-1"`, and the skip link's target stays focusable. The WebKit run checks it.
  - **DW-145:** in Safari and macOS Firefox, pressing the Visual Trace button reopens its open menu instead of closing it. The fix is in `popover.ts`: a press on the trigger counts as inside the popover. The Firefox and WebKit runs check it.
  - **DW-178:** the skip links' `href="#/"` points at nothing, and the scan may flag it.
    - If it does, give each link a target the scan accepts, such as a real id on each region, and keep the prevented default.
    - A plain in-page `#id` would navigate the hash router.
  - **DW-179:** Story 2.12's cases A1, A5, A7 and P4 must pass `turnRows` to `cleanFixtureRows`.
    - Otherwise the turns they seed pile up when the floor unit runs in several browser projects on one stack.
    - K4's tab walk is bounded at 150 stops, and the leftover turns add stops to it.
- **Story 2.14's low residuals, to recheck at 200%:**
  - About's Close scrolls with the text.
  - A wrapped composer draft keeps a stale height after a text-size change.
  - The inset halo sits inside a banner's 4px accent. Reopen it if the scan flags it.
- **Not in these stories:** DW-159, the screen-reader check with VoiceOver and NVDA, is for a human. DW-81 and DW-74 belong to the Epic 2 burn-down.
- **Later epics:**
  - Story 4.5 inserts "Skip to simulated devices" into `SKIP_LINKS`.
  - The guide and simulated devices (Epic 4) and the unpaired Telegram card (Epic 12) take their places in the drawer and stacked layouts in their own epics.
