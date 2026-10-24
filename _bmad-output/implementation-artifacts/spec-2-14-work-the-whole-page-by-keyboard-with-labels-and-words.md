---
title: 'Story 2.14: Work the whole page by keyboard, with labels and words'
type: 'feature'
created: '2026-10-24'
status: 'done'
baseline_revision: '38dad9391d019f80eece532ee0a5a4687d47bb72'
baseline_commit: 'b09b1d0e57ee2ccf7e5ec3f078e697c6be112316'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      The skip links' href="#/" points at no element on the page, so a rule-based accessibility scan (for example axe's
      skip-link and region rules) may not treat them as skip links and may report the two hidden links as content outside the landmarks.
    evidence: |-
      Unverified (inference by the Blind Hunter; no scan was run). The href is the spec's own choice (Decided 2): an in-page #id would
      navigate the hash router. What would settle it: run the scan of Story 2.16 on the loaded page with the skip links present and
      read its skip-link and region results; if it reports them, give the links a target the scan accepts (for example a real id on each
      region) while keeping the prevented default.
    location: >-
      web/src/app/header/skip-links.ts:34
    severity: medium (unverified)
  - summary: >-
      The turns that seedTurns writes are never removed: it does not adopt them, so cleanFixtureRows cannot delete them, and every
      floor case that seeds a turn leaves a done turn (and its decisions) in the floor user's session.
    evidence: |-
      web/e2e/support/iris.ts seedTurns (lines 306-361) has no Fixture.Adopt call, while seedDecisions (line 426) has one. This predates the
      story (Story 2.12's A and P cases and the sign-in unit's specs do the same). K4's tab walk is bounded at 150 stops and holds with the
      turns of a forward or reverse run of the unit, which is a throwaway stack; a stack reused across many runs would grow the walk.
    location: >-
      web/e2e/support/iris.ts:306
    severity: low
---

<intent-contract>

## Intent

**Problem:** The page misses parts of the accessibility floor (NFR-25). These are the starting points that Story 2.12's plan listed (its Decided 1), checked again against the code:
- **Keyboard.**
  - There is no skip link: the first tab stop is the header's home link `a.home`.
  - One Esc can act on two layers. A shown tooltip's Esc also reaches the disclosure that holds focus. A disclosure's handler does not check for an open popover, so a popover whose trigger sits inside it closes together with the disclosure.
  - Focus rings can be clipped. The focus targets that fill the page's width (`main.main`, a banner) draw their ring outside the viewport. A control that focus scrolls into view in the rail or the chat list sits flush with the scroller's edge. The rail does not use its gutter token.
- **Labels.**
  - The banners' Close and the About dialog's Close are named only "Close".
  - The inactive "Open my conversation in Visual Trace" link is `aria-disabled` and gives no visible reason.
- **Words.**
  - Links styled as buttons, and the home link, are not underlined.
  - The outcome chip and the Fallback flag have a fixed 22px height.
  - The composer's pixel height goes stale after a text resize.
  - The About dialog cannot scroll.
  - The busy notice, the load error and "Not sent" are not linked to their buttons.
  - The spinner relies on the global reduced-motion rule alone.
- **Tests.** `live:sign-in` takes about 460 s of its 540 s local deadline, so this story's browser cases cannot join it.

**Approach:**
- One small, targeted change for each gap. The words come from the UX where it gives them, and the four texts it leaves open go to the veto window.
- Node source ratchets pin the rules that no single browser state shows:
  - there are no single-key shortcuts;
  - heights are minimums;
  - nothing scrolls smoothly;
  - every animation stops under reduced motion;
  - none of the banned patterns appears.
- A browser unit of its own, `live:floor` (`docker/tests/test-floor.sh`, in the `shards` group). Story 2.12's floor specs (A1 to A7, P1 to P4) move there from `live:sign-in`, together with this story's K1 to K6 and W1 to W4. This makes `live:sign-in` faster.

## Boundaries & Constraints

**Always:**
- **Skip links.**
  - `web/src/app/header/skip-links.ts` (new) is the standalone component `app-skip-links`. `app.ts` renders it first, before `<app-header />`. It is not a landmark: no `nav` (F1 counts landmarks).
  - It exports `SKIP_LINKS`, an ordered list of `{ text, target }`:
    - "Skip to chat" → `main.main`;
    - "Skip to status" → `section.rail`.

    These are the UX's words (E:376), in ASCII. Story 4.5 inserts "Skip to simulated devices" between the two.
  - Each link is an `a` with `href="#/"`, so it is a link that takes focus.
    - It is visually hidden until it has focus.
    - With focus it shows at the page's top left, above the header, with the `.link` look and its ring inside the viewport.
  - A press (a click or Enter) prevents the default, so the route and the URL never change. It then moves focus to the target with `focus()`, which is the user's own move.
    - The call is listed in `announce-focus-sources.test.mjs` with a count of 1 and its reason.
    - A target that is not in the page does nothing.
  - `section.rail` gets `tabindex="-1"`; `main.main` already has it.
  - Three focus targets are not tab stops: `main.main`, `section.rail` and each `.banner`. Each draws the same 2px ring and 2px `surface` halo inside its own edge, the ring outermost (for example `outline-offset: -2px` with `box-shadow: inset 0 0 0 4px var(--surface)`). So none of it falls outside the viewport.
- **Esc acts on one layer, the topmost:** a shown tooltip, then the open popover or dialog, then the disclosure that holds focus.
  - `Tooltip` listens for Esc on `document` in the capture phase.
    - While its tooltip shows, Esc hides it and stops the event's propagation.
    - While the tooltip is only waiting out its 300 ms delay, Esc cancels it and lets the event through.
  - `Popovers.hasOpen()` (new) says whether any popover is open.
  - `DecisionStrip.collapse()` and `DecisionRow.collapse()` do nothing while `hasOpen()` is true.
  - **Unchanged:**
    - Esc inside a disclosure collapses it and keeps focus (D4, R8).
    - Esc with focus outside a disclosure leaves it as it is.
    - The CDK menus and the About dialog handle their own Esc (F6, `sign-in/shell.spec.ts` row 8).
- **Keys.** Only Enter (the composer) and Escape are handled. There is no single-character shortcut and no `accesskey`. The CDK menus' typeahead acts only inside an open menu, and it stays.
- **The focus ring.**
  - The base rule stays: 2px solid `focus`, a 2px offset and a 2px `surface` halo (`base.css`).
  - Each scroller keeps at least `--space-scroll-gutter` (4px) of inline padding and a `scroll-padding` of the gutter. That applies to `section.rail`, the chat's `.list` and the About dialog. So a control that focus scrolls into view keeps its whole ring inside the scroller.
  - The rail's inline padding is `--status-rail-padding-inline`. Its content keeps today's 12px inset: 8px of its own inside the 4px gutter.
  - The New messages button keeps the halo when focused. Its own shadow adds to the halo and does not replace it.
  - (Inference: Chromium's focus scrolling honours the scroller's `scroll-padding`. K4 measures it. If it does not, the rail rows' and chat entries' focusable controls get a `scroll-margin` of the gutter instead, and the spec records which was used.)
- **Labels.**
  - **Icon-only buttons name their action and object:**
    - Reset soon's Close is "Close reset notice", and Reconnecting's is "Close reconnecting notice" (veto, Design Notes);
    - About's Close is "Close About OcuTalon" (veto);
    - the theme button keeps the UX's name, "Theme: System", "Theme: Light" or "Theme: Dark" (E:205).
  - Every other control keeps its current visible or programmatic name. Every icon stays `aria-hidden` (`icon.ts`).
  - **Explained-disabled.** With no turn yet, the "Open my conversation in Visual Trace" link keeps `role="link"`, `tabindex="0"` and `aria-disabled="true"`.
    - The popover shows the visible reason "Available after your first message." under it (veto). The reason has an id, and the link's `aria-describedby` names it.
    - When a turn gives the link its address, the reason and the `aria-describedby` both go. The link keeps focus (V7).
  - **Busy server buttons** keep the UX's form (E:379): the label, a spinner, `aria-busy` and `aria-disabled`, and no reason text (Decided 5).
- **Errors are linked to their cause.**
  - `ServerButton` gains an optional input, `describedBy`: the ids of text that explains the button.
    - The button's `aria-describedby` holds those ids, plus the busy notice's id while the notice shows. The notice's id is unique to each button.
    - With neither, the button has no `aria-describedby`.
  - `MainPage`: the load error's text gets an id, and Retry is described by it.
  - `UserMessage`: "Not sent" gets an id that is unique on the page, and Retry sending is described by it.
- **Every link is underlined at rest.**
  - Links styled as buttons (`a.button`) take the link's underline: 1px with a 2px offset, and 2px on hover and focus. These are the conversation link, active or inactive, and the help's "Open Visual Trace".
  - The home link underlines its wordmark (veto: the brand's look).
  - The skip links use `.link`.
  - Every other link is already underlined.
- **Text resizes to 200%.**
  - The outcome chip and the Fallback flag use `min-height: 22px` in place of `height`.
  - The composer sets its height in line units (`lh`) plus its padding. After a text-size change it still fits its lines, up to five, with no keystroke. At 100% its sizes are unchanged (C3).
  - The About dialog is at most the viewport's height less `--space-4` above and below. It scrolls (`overflow-y: auto`) and keeps the gutter, and its Close stays at the top right (F6).
  - Every `height` in `web/src/app/**` and `web/src/styles/**` is one of these, and the ratchet lists them:
    - the app root's viewport height;
    - the reply avatar's size;
    - the static skeleton blocks;
    - `.visually-hidden`.

    A later story adds any new one to that list, with its reason.
- **Motion.**
  - `controls.css` stops the spinner under `prefers-reduced-motion: reduce` (`animation: none`), as `ocutalon-reply.ts` already stops the dots.
  - `base.css`'s global rule stays.
  - Nothing scrolls smoothly.
- **The banned patterns** (UX-DR129): none appears, and the ratchet pins that.
- **The unit `live:floor`.**
  - `docker/tests/test-floor.sh` (new) runs these steps:
    1. `lib-live.sh`, with the label `floor` and no web rebuild (`ci/iris.sh build` makes the bundle);
    2. `live_web_port`, then `dc up -d --build` and `live_track_image`;
    3. `wait_started_ready 400` and `check_no_key "floor"`;
    4. the floor user `ZzFloor` with the user role. Its random password goes by environment variable, is never printed, and is redacted in the log;
    5. `npm --prefix web run e2e:floor` with `OCUTALON_URL`, `OCUTALON_FLOOR_USER` and `OCUTALON_FLOOR_PASSWORD`, `OCUTALON_E2E_IRIS_CONTAINER`, and a global timeout of what is left of the deadline minus 20 s;
    6. one PASS or FAIL line that names Story 2.12's A1-A7 and P1-P4 and Story 2.14's K1-K6 and W1-W4.
  - `lib-live.sh` gains `live_fixture_user`. It is `test-sign-in.sh`'s `create_fixture_user`, moved, and both scripts call it.
  - `web/playwright.config.ts` gets a project `floor` (`testDir: './e2e/floor'`, Desktop Chrome). The `chromium` project ignores `e2e/demo-path/` and `e2e/floor/`. `web/package.json` gets the script `e2e:floor`.
  - `ci/units.sh`: `shards` becomes `shard:lane-a shard:lane-b live:floor`, and `BROWSER_UNITS` becomes `"demo-path sign-in floor"`. Nothing else in the file changes.
  - `test-sign-in.sh` loses the floor user: its variables, its redaction, its header bullet and its part of the labels.
- **Convention "Announcements and focus".** The skip link's call is the only new `.focus(`. Nothing new is announced: a reason is a description, not an event.

**Never:**
- **No server change:** no ObjectScript, REST route, payload, event type, stored data, role, grant or dependency.
- **No new noise:** no live region, announcement, toast, modal, sound or keyboard shortcut.
- **No public text** beyond the UX's and the four veto-window texts: the two banner Close names, About's Close and the conversation link's reason.
- **Not changed:**
  - Enter and Shift+Enter (C3).
  - A disclosure's Esc from inside (D4, R8).
  - The popover and dialog rules (F6, F8, V7, V12, V13).
  - The one-line previews (D2, R19). This is spec-bound (Decided 7).
  - The trace links' names (Story 2.13) and the theme button's name.
  - The layout at any width (Story 2.15).
- **Not this story:**
  - **Story 2.15:** the drawer, the stacked layout, the note, and the layout at 200% zoom.
  - **Story 2.16:** Firefox, WebKit, the scan, the string test, DW-89 and DW-145.
  - **Story 16.9:** the composer at the allowance limit.
  - **Epic 4:** Break the feed and the mailbox. **Story 4.5:** "Skip to simulated devices".
- **Registration** touches only Lane B's entries in `ci/units.sh`. Never `ci/iris.sh`, `docker/tests/test-ci-config.sh`, `ci/warm.sh` or `.github/workflows/*`.
- **No case joins `live:sign-in`.** Its specs change only where they read a renamed control or a moved helper, and no wait is added.
- **Tests:**
  - never stop IRIS or its web server;
  - never hold a poll for 8 s or longer;
  - no floor case lets a chat post reach the server (the A6 and P1 pattern).
- **Contended paths stay read-only:**
  - `src/bridge/**`;
  - `OcuTalon/{Agent,Tools,Digest,Install,Schedule,Checks,Eval,Watch}/**`;
  - `Data/Public/**` and `Data/{StatusMark,Time,Reminder}.cls`;
  - `Core/Commands*.cls` and `Msg/Tick.cls`;
  - `Test/{Agent,Bridge,Install,Tools,Digest,Schedule}/**`;
  - `ci/mock/scenarios/{A,B}/**`, `web/e2e/demo-path/0{2,3}-*.spec.ts` and `release/**`;
  - `.github/workflows/lane-a.yml`, `ci/iris.sh` and `ci/warm.sh`;
  - `docker/tests/test-pinned-sources.sh`, `test-production.sh`, `test-ci-warm.sh` and `test-ci-config.sh`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First tab stops | The page loads; focus is at the document's start | Tab: "Skip to chat"; Tab: "Skip to status"; Tab: the home link. Each skip link shows while focused, with its ring inside the viewport | The page is still loading: the same two links |
| Skip to chat | Enter on "Skip to chat" | Focus on `main.main`, with its ring inside the viewport; the URL is unchanged; the next Tab reaches the first control inside main | — |
| Skip to status | Enter on "Skip to status" | Focus on the region Status (`section.rail`); the next Tab reaches the rail's first control | — |
| Esc, tooltip on top | A rail decision row is open with focus on its button; the pointer shows its chip's tooltip | The first Esc only hides the tooltip; the row stays open and focus stays. The second Esc collapses the row | — |
| Esc, popover on top | A row's Trace help is open; focus is back on its Trace link inside the open row | Esc closes only the help; the row stays open; focus is on the link | — |
| Esc outside | A row is open; focus is on the composer | Esc changes nothing | — |
| Printable keys | Focus is on the body, on main, then on a rail row; keys "a", "s", "t", "/", "?", "1" | Nothing moves focus, opens, sends or navigates | — |
| Ring | Tab through every stop of a page whose rail and chat list both scroll | Every ring is 2px solid in the focus colour, with its halo, and lies inside the viewport and inside every scroller around it. New messages keeps its halo | — |
| Banner Close | Reset soon and Reconnecting show | Their buttons are "Close reset notice" and "Close reconnecting notice"; no control is named "Close" alone | — |
| About Close | About is open | Its Close is "Close About OcuTalon", top right, and focus returns to the account trigger | — |
| Inactive conversation link | No turn; the Visual Trace popover is open | The link is a link, `aria-disabled`, focusable, and described by the visible "Available after your first message." | A turn arrives: the link gets its `href`, keeps focus, and loses `aria-disabled`, the description and the reason |
| Busy | Retry is pressed, with no answer yet | The label, a spinner, `aria-busy` and `aria-disabled`; no reason text | — |
| Load error | No snapshot by 10 s, or an error answer | Retry is described by "Couldn't load your session."; after its own 10 s, also by the busy notice | An answer clears both |
| Not sent | A post fails | Retry sending is described by its own "Not sent" | — |
| Links | Every link on the page, in the popovers and in About | Underlined at rest | — |
| 200% text | Every font-size token doubled, at 1280×600 | The chips, the Fallback flag, the buttons, the banners and the header hold their text. The composer fits its two typed lines with no keystroke. About scrolls to its last line | — |
| Reduced motion | `prefers-reduced-motion: reduce`, a busy Retry and a running turn | No animation runs; the spinner and the dots have `animation-name: none`; every scroller has `scroll-behavior: auto` | Without reduced motion, the dots animate |

</intent-contract>

## Code Map

**Page (Lane B; edit or new)**
- `web/src/app/app.ts:18-22`: the template: `<app-header />`, the banner slot and the router outlet. The skip links go first.
- `web/src/app/header/header.ts`:
  - the home link `:54-57`, and its style `.home` `:165-171` (`text-decoration: none`) and `.wordmark` `:175`;
  - the conversation link `:102-116`, inside `<app-trace-help>` content, where the reason paragraph goes;
  - the theme button `:74-83` (name unchanged).
- `web/src/app/shared/trace-view.ts:14-24`: `TRACE_TEXTS`, which gains the reason, in ASCII.
- `web/src/app/shared/trace-link.ts:115-119`: the help's "Open Visual Trace" (`a.button.button-primary`).
- `web/src/app/main-page/main-page.ts`:
  - `section.rail` `:40`;
  - `main.main` `:61-68` (`tabindex="-1"`);
  - the load error `:77-82`;
  - `.rail` styles `:94-104` (padding `:101`: `var(--space-3) var(--space-3) var(--space-4)`);
  - `.main` styles `:143-150`.
- `web/src/app/banners/banner-stack.ts`: the banner element `:70` (`tabindex="-1"`, full width) and Close `:79-81`, named by `texts.close`; `.banner` styles `:90-104`.
- `web/src/app/banners/banner-view.ts`:
  - `BannerSpec.closable` `:59`;
  - the closable `resetSoon` and `reconnecting` specs `:71-72`;
  - `BANNER_TEXTS` `:82-84` (`{ close: 'Close' }`);
  - `BannerView` `:118-126`;
  - `activeBanners` `:154-180`.
- `web/src/app/about/about-dialog.ts`: Close `:37-39` (`aria-label="Close"`); `:host` `:42-51`, with a width and no `max-height` or overflow. This folder is outside the listed epic footprint; nobody contends it (For the lead).
- `web/src/app/shared/dialogs.ts:27-36`: the CDK dialog config, unchanged. CDK 22.2.3's pane is `max-height: 100%`, and `.cdk-dialog-container` has no overflow.
- `web/src/app/shared/server-button.ts:25-41`: the button, with `aria-busy` and `aria-disabled` while busy, and the spinner and the notice; `BUSY_NOTICE` `:10`.
- `web/src/app/chat/user-message.ts:22-28`: "Not sent" and Retry sending.
- `web/src/app/shared/popover.ts`: the `open` set `:70` and `closeAll` `:133-137`, which `hasOpen()` sits beside.
- `web/src/app/shared/tooltip.ts`: the listener `:77`, its removal `:100` and `onKeydown` `:105-109`.
- `web/src/app/chat/decision-strip.ts`: `(keydown.escape)` `:54` and `collapse()` `:240`. `web/src/app/rail/decision-row.ts`: `:29` and `collapse()` `:162`.
- `web/src/app/chat/chat-panel.ts`: `.list` `:128-135` (`padding-inline: var(--chat-panel-padding-inline)`, 4px); the New messages button's style around `:150-175` (its `box-shadow` `:171` replaces the halo).
- `web/src/app/chat/composer.ts:96-103`: `grow()`, which sets a pixel height on input and on send only.
- `web/src/app/chat/outcome-chip.ts:41` and `web/src/app/chat/fallback-flag.ts:24`: `height: 22px`.
- `web/src/app/chat/ocutalon-reply.ts:144-160`: the dots, with their own reduced-motion rule (the pattern for the spinner).
- `web/src/styles/controls.css`:
  - `.button` `:9-22` (`text-decoration: none`);
  - `.button-inactive` `:75-82`;
  - the spinner `:84-93`;
  - `.link` `:104-114`.
- `web/src/styles/base.css`: the focus ring `:94-99` and the global reduced-motion rule `:101-111`.
- `web/src/styles/tokens.css`: `--space-scroll-gutter` `:129`, `--status-rail-padding-inline` `:265` and `--chat-panel-padding-inline` `:302`. The file is generated from DESIGN.md; never edit it.
- `web/src/app/icon/icon.ts:30-34`: every `svg` is `aria-hidden="true"` (unchanged).
- Read only:
  - `web/src/app/shared/focus-rule.ts` (its fallback is `main.main`);
  - `node_modules/@angular/cdk/fesm2022/_overlay-module-chunk.mjs:415-424`, the body-level keydown dispatcher that runs after an element's own handler.

**Tests (Lane B; edit or new)**
- `web/scripts/announce-focus-sources.test.mjs`:
  - `listFiles` `:17-23`, `code` `:26`, `files` and `file` `:28-35`, which move into the shared helper;
  - `FOCUS_CALLS` `:121-126`, which gains the skip links (1).
- `web/scripts/banner-view.test.mjs:90-91`: `BANNER_TEXTS` deep-equals `{ close: 'Close' }`. Its view cases also deep-equal `BannerView` objects, so they change if the name rides on the view.
- `web/scripts/trace-view.test.mjs:23`: `TRACE_TEXTS` deep-equals.
- `web/scripts/playwright-projects.test.mjs:66-82`: what the `e2e` and `e2e:demo-path` scripts list.
- `web/scripts/controls-styles.test.mjs`, `shell-styles.test.mjs`, `banner-styles.test.mjs`: style scans that must stay green. `shell-styles` checks that every `var(--x)` exists.
- `web/e2e/support/api.ts`: `changeSnapshot` `:26` and `holdPoll` `:82`. `holdState` (`web/e2e/live/live.spec.ts:52-68`) moves here.
- `web/e2e/support/iris.ts`:
  - `required` `:8-12` (its message names `test-sign-in.sh`);
  - `FixtureKind` `:15`;
  - `seedTurns` `:306`, `finishTurn` `:389`, `seedDecision` `:442`, `cleanFixtureRows` `:575`, `seedApproval` `:613`, `seedCheck` `:662` and `publishStatus` `:723`.
- `web/e2e/support/page.ts`: `tokenColor` `:17`, `recordAnnouncements` `:53` and `countFocusins` `:90`.
- `web/e2e/floor/announcements.spec.ts` and `web/e2e/floor/focus.spec.ts` (P1 `:85`, P2 `:124`, P3 `:148`): their headers name `test-sign-in.sh`.
- Patterns:
  - `frame.spec.ts`: F7 `:372-410` (the ring's CSS through `tokenColor`) and F1 `:62-93` (landmarks and DOM order).
  - `rail.spec.ts`: R8 `:311` (row Esc) and R17 (20 rows at 1280×720).
  - `focus.spec.ts` P2 (a fresh context, so the Trace help is needed).
  - `live.spec.ts` L6 `:271` (`page.clock`, a held `/state`, the busy notice) and L7.
  - `announcements.spec.ts` A1 (a running turn), and A6 (`/messages` answered 500 in the browser).
  - `decision.spec.ts` D4 `:198`.
- **Shared-surface readers** (renamed Close):
  - `frame.spec.ts` F6 `:339` and F7 `:402`;
  - `banners.spec.ts` B5 `:359-361`, B8 `:510-511`, B9 `:525`, B10 `:587`, B13 `:808` and B14 `:869`.
- **The unit:**
  - `docker/tests/test-sign-in.sh`:
    - the header bullet `:44-46` and the user list `:49`;
    - `flooruser` and `floorpassword` `:91-92`;
    - `create_fixture_user` `:118-127`;
    - the loop comment and list `:155-159`;
    - `show_log` `:206`;
    - the variables `:236-237`;
    - the labels `:250` and `:256`.
  - `docker/tests/test-demo-path.sh`: the skeleton of a lean live browser unit. `docker/tests/lib-live.sh`: header `:1-45`, `live_start` `:53`, `live_web_port` `:197`, `dc` `:239`, `wait_started_ready` `:358`, `check_no_key` `:634`.
  - `ci/units.sh`: `group_units` `shards` and `BROWSER_UNITS`.
  - `web/playwright.config.ts:30-33` and `web/package.json:14-15`.
- **Read only (the registration needs no edit to these):**
  - `ci/iris.sh` `live_known` `:314-322` and `cmd_live` `:324-337`: any `live:<name>` of a group runs `docker/tests/test-<name>.sh`, and a `BROWSER_UNITS` name installs Chromium first.
  - `cmd_group` `:339-366`: it runs a group's units in order, of either kind.
  - `docker/tests/test-ci-config.sh`:
    - `units`: every `test-*.sh` is in exactly one place;
    - `demo-path` `:709-745`: a script that runs `npm --prefix web run e2e...` is in `BROWSER_UNITS`, and each of those is a live unit of a group;
    - `inputs`: `lib-live.sh` is claimed by `IRIS_INPUT`.
  - `docker/tests/test-demo-path-gate.sh` stubs the `browser` group only.
  - `.github/workflows/ci.yml:89-120`: the matrix of groups, `ci/iris.sh build`, then `group`, with a 40-minute job timeout.
- **UX:**
  - `EXPERIENCE.md`: E:372-376 (keyboard), E:379 (busy), E:400-453 (the Accessibility Floor) and E:388-398 (banned);
  - `DESIGN.md`: D:280-283 and D:748 (the ring), D:696 (scroll gutters), D:695 (minimum heights) and D:757 (links).

## Tasks & Acceptance

**Execution:** No Task 0 on the server, because nothing there changes. The one platform question, whether focus scrolling honours `scroll-padding`, is measured by K4 in Task 4 (Boundaries, the focus ring).

1. **The unit move** (do it first, so every later browser run is `live floor`):
   - `web/playwright.config.ts`: the `floor` project, `chromium` ignoring `e2e/floor/`, and the header doc;
   - `web/package.json`: `e2e:floor`;
   - `web/scripts/playwright-projects.test.mjs`: `chromium` lists the files outside `demo-path/` and `floor/`, and `floor` (the `e2e:floor` script) lists exactly `floor/`;
   - `docker/tests/lib-live.sh`: `live_fixture_user`, with its header line;
   - `docker/tests/test-floor.sh` (new), as Boundaries says, with a header that states what it pins and needs;
   - `docker/tests/test-sign-in.sh`: drop the floor user, and call `live_fixture_user`;
   - `ci/units.sh`: `shards` and `BROWSER_UNITS`;
   - `web/e2e/support/iris.ts`: `required`'s message names the unit scripts;
   - `web/e2e/floor/*.spec.ts`: their headers name `test-floor.sh`.
2. **Skip links.**
   - `web/src/app/header/skip-links.ts` (new): `SKIP_LINKS`, the component, its style and its class doc.
   - `web/src/app/app.ts`: render it first, and update the doc.
   - `web/src/app/main-page/main-page.ts`: `section.rail` gets `tabindex="-1"`; the inside ring for `.main` and `.rail`.
   - `web/src/app/banners/banner-stack.ts`: the inside ring for `.banner`.
   - `web/scripts/announce-focus-sources.test.mjs`: the `FOCUS_CALLS` entry.
3. **Esc on one layer.**
   - `web/src/app/shared/popover.ts`: `hasOpen()`, documented.
   - `web/src/app/shared/tooltip.ts`: the capture-phase Esc.
   - `web/src/app/chat/decision-strip.ts` and `web/src/app/rail/decision-row.ts`: `collapse()` returns while a popover is open, and their docs say so.
4. **Scrollers and the ring.**
   - `web/src/app/main-page/main-page.ts`: the rail's inline padding is the token, with the 8px content inset and `scroll-padding`.
   - `web/src/app/chat/chat-panel.ts`: the list's `scroll-padding`, and New messages keeps the halo when focused.
   - `web/src/app/about/about-dialog.ts`: `max-height`, `overflow-y: auto` and `scroll-padding`.
   - If K4 shows that focus scrolling ignores `scroll-padding`, use `scroll-margin` on the focusable controls instead, and record it.
5. **Labels and the reason.**
   - `web/src/app/banners/banner-view.ts`: the two Close names in `BANNER_TEXTS`, keyed by banner id. `banner-stack.ts` names each Close by its banner.
   - `web/src/app/about/about-dialog.ts`: the Close name, as a constant.
   - `web/src/app/shared/trace-view.ts`: `TRACE_TEXTS.conversationNotYet`.
   - `web/src/app/header/header.ts`: the reason paragraph under the inactive link, with an id, and the link's `aria-describedby` while inactive.
6. **Errors linked.**
   - `web/src/app/shared/server-button.ts`: `describedBy`, and the notice's id.
   - `web/src/app/main-page/main-page.ts`: the load error text's id, passed to Retry.
   - `web/src/app/chat/user-message.ts`: "Not sent"'s id, which Retry sending is described by.
7. **Resizing.**
   - `web/src/app/chat/outcome-chip.ts` and `web/src/app/chat/fallback-flag.ts`: `min-height`.
   - `web/src/app/chat/composer.ts`: `grow()` in `lh` units, with its doc.
8. **Links and motion.**
   - `web/src/styles/controls.css`: `a.button` underlined (1px, 2px offset; 2px on hover and `:focus-visible`), and the spinner's reduced-motion rule.
   - `web/src/app/header/header.ts`: the wordmark underlined.
9. **Node ratchets.**
   - `web/scripts/source-files.mjs` (new): the source listing and comment stripping that `announce-focus-sources.test.mjs` uses today, exported (Rule 2), with the file extensions as a parameter. That test imports it with `.ts`, `.js` and `.html`, as today; the new ratchet adds `.css`.
   - `web/scripts/floor-sources.test.mjs` (new), with one header and these cases:
     - **Keys:** every keyboard handler in `web/src/**` compares only `Enter` or `Escape` (the composer's IME guard, `keyCode === 229`, stays); there is no `keypress` or `keyup` handler and no `accesskey`.
     - **Esc guard:** every `(keydown.escape)` host (`decision-strip.ts`, `decision-row.ts`) asks `hasOpen()` in its handler, and the tooltip's Esc listener is a capture-phase one.
     - **Heights:** every `height:` or `block-size:` declaration is in the list of Boundaries, and each entry has its reason. The custom properties of `tokens.css` are not declarations of a height.
     - **Motion:**
       - no `scroll-behavior: smooth` and no `behavior: 'smooth'`;
       - no `transition`;
       - every file that declares an `animation` also sets `animation: none` under `prefers-reduced-motion: reduce`;
       - `base.css` keeps its global rule.
     - **Banned:**
       - no toast or snackbar;
       - no `Audio`, `AudioContext` or `<audio`;
       - no `draggable`, drag or drop handler, or CDK drag-drop;
       - no `<progress`, `progressbar` or `aria-valuenow`;
       - no `IntersectionObserver`;
       - no `role="tab"` or `tablist`;
       - no `alert(`, `confirm(`, `prompt(` or `showModal`;
       - no confetti or celebration;
       - `Dialogs.open` is called only from `header/header.ts` (the user's About);
       - no `:hover` rule sets `display`, `visibility` or `opacity`.

       Each list names its files and says why. A later story that needs an entry adds it with its reason.
     - **Source guard:** the helper reads every `.ts`, `.js`, `.html` and `.css` file under `web/src/`, `index.html` and `styles/*.css` included.
   - `web/scripts/banner-view.test.mjs`: the new `BANNER_TEXTS`, and each closable banner's Close name. `web/scripts/trace-view.test.mjs`: the new key.
10. **Browser.**
    - `web/e2e/support/api.ts`: `holdState`, moved from `live.spec.ts` (which imports it).
    - `web/e2e/floor/keyboard.spec.ts` (new): one header, and K1 to K6 below, each signing in as `FLOOR`, removing its rows and clearing its conditions in `finally`.
    - `web/e2e/floor/words.spec.ts` (new): one header, and W1 to W4 below, under the same rules.
    - **K1: skip links.**
      - From a fresh load, Tab reaches "Skip to chat", then "Skip to status", then the home link. Each is a link with that exact name, shown while focused, with its ring inside the viewport.
      - Enter on "Skip to chat" puts focus on `main.main`, with its ring inside the viewport, and leaves `page.url()` unchanged. The next Tab is inside main.
      - The same holds for "Skip to status" and `section.rail`.
      - On a second load with `/state` held (`holdState`), the same two links are the first stops, and Enter on "Skip to chat" focuses `main.main` while it shows its skeletons. The hold is released in `finally`.
    - **K2: Esc on one layer.** A rail decision row with a trace link is seeded and published (as P2 and R8 do), in a fresh context, so the Trace help is needed.
      - The row is opened by keyboard.
      - The pointer hovers its chip until the tooltip shows. Esc hides only the tooltip, and the row stays open with focus on its button. A second Esc collapses the row, and focus stays.
      - The row is opened again. Its Trace link is pressed, and the help opens. Focus moves back to the link with `focus()`. Esc closes only the help, the row stays open, and focus is on the link.
      - With the row open and the composer focused, Esc leaves it open.
    - **K3: no single-key shortcuts.** With focus on the body, on `main.main`, then on a rail row's button, the keys "a", "s", "t", "/", "?" and "1" change nothing:
      - `document.activeElement` is unchanged;
      - no `[role=dialog]`, `[role=menu]` or popover appears;
      - the URL is unchanged;
      - no request goes to `/messages`.
    - **K4: the ring is never clipped.** At 1280×720, seed 12 rail rows (so the rail scrolls; the decision rows carry trace links) and 8 done turns with decisions (so the chat list scrolls), and publish Reset soon.
      - Tab through every stop, from the first skip link to Send. At each stop:
        - the focused element's computed outline is 2px, solid and the focus colour (`tokenColor`), and its `box-shadow` holds the 2px `surface` halo;
        - its ring box lies inside the viewport and inside the client box of every scrolling ancestor (±0.5px). The ring box is the border box, grown by the outline's offset plus its width when the offset is positive.
      - Then `main.main`, `section.rail` and a banner are focused by the keyboard path (the skip links, and the focus rule's targets through `focus()` after a key press). Their rings lie inside the viewport.
      - Each scroller's computed `padding-inline-start` and `padding-inline-end` are at least 4px.
    - **K5: every control is named.**
      - On a page with one row of each rail kind with trace links, a done turn with a decision strip, the no-key banner and Reset soon, `page.locator('body').ariaSnapshot()`:
        - has no `button`, `link`, `textbox` or `menuitem` without a quoted name;
        - has no control named exactly "Close";
        - has no `img`.
      - Every `svg` in the document has `aria-hidden="true"`.
      - Reset soon's Close is "Close reset notice". With the Visual Trace popover open, and then with About open, the same checks hold, and About's Close is "Close About OcuTalon".
      - Reconnecting's name is pinned in `banner-view.test.mjs`, and it is read in B13.
    - **K6: the inactive link explains itself.** With `changeSnapshot` giving an empty chat, the Visual Trace popover's conversation link:
      - is a link with `aria-disabled="true"` and focus;
      - is described by a visible element whose text is "Available after your first message.".

      Then a done turn is seeded, and `changeSnapshot` gives the newest chat item a `traceUrl` of the test's own. On that load the link has that `href`, no `aria-disabled`, no `aria-describedby`, and no reason text. No post reaches the server. V7 keeps pinning the change on a live turn.
    - **W1: links are underlined.** On a page seeded as K5's (one helper in the spec file), with the skip link focused, the Visual Trace popover (inactive link), the Trace help (fresh context) and About each open in turn, and with a reply that holds a markdown link: every `a` and `[role=link]` has `text-decoration-line` with `underline`. For the home link, it is its `.wordmark`.
    - **W2: 200% text.** At 1280×600, on a page with a done turn whose strip shows a chip and the Fallback flag, two short lines ("zz one", Shift+Enter, "zz two") are typed into the composer. Then every custom property of `:root` (tokens.css) whose name ends in `font-size` is doubled on `document.documentElement`. Then, with no keystroke:
      - the outcome chip's `.chip`, the Fallback flag's `.flag`, every `.button`, the banners and `.header` have `scrollHeight - clientHeight <= 1`, so no box is shorter than its text;
      - the composer's field has `scrollHeight - clientHeight <= 1` and is at least two doubled lines tall;
      - About, opened afterwards, has `scrollHeight > clientHeight`, computed `overflow-y: auto`, and its last paragraph can be scrolled inside the viewport.
    - **W3: reduced motion.** With `emulateMedia({ reducedMotion: 'reduce' })`:
      - The first `/state` answers 500. Retry's next request is held, so Retry is busy. The spinner shows, with `animation-name: none`, and `document.getAnimations()` has nothing running.
      - The route is released. A running turn is seeded and published, so the dots show with `animation-name: none` and nothing runs.
      - Every scroller and `html` have `scroll-behavior: auto`.
      - With `reducedMotion: 'no-preference'`, the dots' animation runs, which is the control.
      - The turn is finished in `finally`.
    - **W4: errors are linked.** With `page.clock` and `holdState` (the L6 pattern):
      - after 10 s, Retry's `aria-describedby` names the element with "Couldn't load your session.";
      - Retry is pressed, and 10 s more pass. It names that element and the notice with `BUSY_NOTICE`;
      - the hold is released.

      Then, with `/messages` answered 500 in the browser, a sent message's Retry sending is described by its own "Not sent".
11. **The sweep (shared surfaces).**
    - Search `web/e2e/` and `web/scripts/` for `name: 'Close'`, `'Close'`, `BANNER_TEXTS`, `TRACE_TEXTS`, `holdState` and the chromium project's spec list, and update each reader: F6, F7, B5, B8 (count the Close buttons by `button.close`), B9, B10, B13 and B14, `banner-view.test.mjs`, `trace-view.test.mjs` and `live.spec.ts`.
    - Search `web/src/app/` for every `.focus(` and confirm the ratchet's counts.

**Acceptance Criteria:**
- **Keyboard (NFR-25, UX-DR11, UX-DR33, UX-DR125).**
  - **Given** I use only the keyboard,
  - **when** I work through the page,
  - **then** every function works: the first tab stops are "Skip to chat" and "Skip to status"; Enter sends and Shift+Enter adds a line; Esc closes the topmost popover or dialog and collapses a disclosure only when focus is inside it; there are no single-character shortcuts; and the focus ring is always visible and never clipped, because every scrolling region keeps `scroll-gutter`.

  Tests: K1 to K4 and `floor-sources.test.mjs` (keys). These existing cases stand unchanged: C3 (Enter and Shift+Enter), D4 and R8 (Esc from inside), F6 and F8 (the dialog and the tooltip), V7, V12 and V13 (popovers).
- **Labels (NFR-25, UX-DR130, UX-DR133).** This is the first criterion's "And", under the same Given and When.
  - **Given** I use only the keyboard,
  - **when** I work through the page,
  - **then** every control has a visible or programmatic label, icon buttons name their action and object, state is text with icons hidden from assistive technology, and a control that can't act stays focusable with `aria-disabled`, its visible reason linked by `aria-describedby`.

  Tests: K5, K6, `banner-view.test.mjs` and `trace-view.test.mjs`.
- **Words, resizing, errors and motion (NFR-25, UX-DR14, UX-DR134, UX-DR135).**
  - **Given** any state on the page,
  - **when** it is shown,
  - **then** it never relies on colour alone (every state has a word and every link is underlined), text resizes to 200% without loss because heights are minimums, errors are text beside their cause linked to their field, and under `prefers-reduced-motion` nothing rotates, pulses, shimmers or scrolls smoothly.

  Tests: W1 to W4, K6 (the inactive link's word), and `floor-sources.test.mjs` (heights and motion).
- **Banned patterns (UX-DR129).** This is the second criterion's "And", under the same Given and When.
  - **Given** any state on the page,
  - **when** it is shown,
  - **then** none of the banned patterns appears: modal notification interruptions, toasts as the only copy, sounds, tabs that switch by themselves, hover-only controls, drag-and-drop as the only way, model-progress bars, celebration effects, or infinite scroll in counted lists.

  Tests: `floor-sources.test.mjs` (banned) and K3.
- **The floor unit.**
  - **Given** the CI recipe,
  - **when** `ci/iris.sh` lists and runs the units,
  - **then:**
    - `live:floor` is a browser unit of the `shards` group;
    - it runs exactly the specs of `web/e2e/floor/` on a throwaway stack of its own, with the floor user;
    - `live:sign-in` no longer runs them or creates that user;
    - no edit is made to `ci/iris.sh`, `test-ci-config.sh` or a workflow.

  Tests: `playwright-projects.test.mjs`, `test-ci-config.sh` (units, demo-path and inputs, unchanged), `ci/iris.sh live floor`, `ci/iris.sh group shards` and `ci/iris.sh live sign-in`.
- **Integration (Rule 1).**
  - **Given** the real page on a real stack,
  - **when** the keyboard uses it,
  - **then:**
    - `App` renders `SkipLinks` first, and its links move focus to `MainPage`'s regions (K1);
    - `DecisionRow` and `DecisionStrip` read `Popovers.hasOpen()` (K2 for the row; the strip goes through the same guard, and the ratchet checks that both call it);
    - `MainPage` and `UserMessage` describe their buttons through `ServerButton.describedBy` and their own ids (W4);
    - `test-sign-in.sh` and `test-floor.sh` both create their users through `live_fixture_user` (both units pass).

### Review Findings

Code review, 2026-10-24 (full mode; four layers: Blind Hunter, Edge Case Hunter, Verification Gap, Acceptance Auditor; 38 rows, 10 root causes kept, 0 decision-needed, 0 deferred, every patch applied). No AC violation, no AD mismatch (AD-12, AD-13, AD-22, AD-29, AD-33), no breach of the Never list; QA's DW-179 fix is complete for this story's own cases (K2 strip, K4, K5, K6, W1-W3, H1). Each line: severity, fix-risk, footprint, spec-status, disposition.

- [x] [Review][Patch] The keys ratchet missed Angular's global key bindings (`(window:keydown.k)`, a `host:` `'(document:keydown)'`), `fromEvent(..., 'keydown')`, a reversed or lower-cased key comparison and `event.key.length`, so a single-key shortcut written that way passed it [web/scripts/floor-sources.test.mjs:90] — medium, fix-risk low (patterns and samples only), in-story, clear; fixed, mutations recorded.
- [x] [Review][Patch] Rule 2: `support/floor.ts` copied twelve helpers of `floor/focus.spec.ts` and eight of `floor/announcements.spec.ts` verbatim (the same floor page, the same unit) with no stated reason; both siblings now import them from it [web/e2e/floor/focus.spec.ts:17] — medium, fix-risk low (identical pure helpers; tsc and `live floor` green), in-story, clear; fixed. The same one-line locators recur in specs of other folders (`trace/`, `rail/`, `banners/`, `chat/`), which this story did not add.
- [x] [Review][Patch] Rule 19 hermeticity: K5 counted every rail row and every rail trace link (`li.row` = 4), so it depended on every other case's clean-up; it now counts its own rows (its stamp, and its approval's `data-row-key`) [web/e2e/floor/keyboard.spec.ts:552] — medium, fix-risk low, in-story, clear; fixed (`FullPage.approval` added).
- [x] [Review][Patch] K4's Trace count also took the header's Visual Trace button, so a missing rail link still passed, and its message (and W1's) named chat and strip links the seeded page does not render [web/e2e/floor/keyboard.spec.ts:469] — low, fix-risk low, in-story, clear; fixed.
- [x] [Review][Patch] The scroller ratchet missed `overflow-x`, a two-value `overflow` and `overflow-block`/`-inline`, and `cssOf` reads neither a `styles: [...]` array nor a template's `<style>` block (which also blinds the `:hover` check); a guard now requires one `styles` literal per component [web/scripts/floor-sources.test.mjs:264] — low, fix-risk low, in-story, clear; fixed, mutations recorded.
- [x] [Review][Patch] The script-height ratchet missed Renderer2's `setStyle(el, 'height')`, `style['height']`, a `HostBinding('style.height')` and an ngStyle key, and "only in line units" held for one assignment only [web/scripts/floor-sources.test.mjs:224] — low, fix-risk low, in-story, clear; fixed, mutations recorded.
- [x] [Review][Patch] The Esc check read only a single-quoted `'keydown'` listener with a named handler, so a double-quoted or inline-handler document listener was invisible to it [web/scripts/floor-sources.test.mjs:188] — low, fix-risk low, in-story, clear; fixed, mutation recorded.
- [x] [Review][Patch] H1 recorded the first seed's rows only after the second seed, so a failure of the second left them on the session [web/e2e/floor/fixtures.spec.ts:33] — low, fix-risk low, in-story, clear; fixed.
- [x] [Review][Patch] H1's header said the cases that follow find the session as on a fresh stack, while Story 2.12's A and P cases still leave their turns [web/e2e/floor/fixtures.spec.ts:8] — low, fix-risk low, in-story, clear; fixed (comment states the contract).
- [x] [Review][Patch] `live_fixture_user`'s docs named its 4th argument `<comment>`; it is `Security.Users.Create`'s FullName [docker/tests/lib-live.sh:24] — low, fix-risk low, in-story, clear; fixed.

Rejected (each with its reason):
- `false` Edge Case Hunter: W3 hangs if the page asks for /state twice after the 500 — the page asks for /state only at load and on Retry (W4 shows the count move from 1 to 2 only on Retry), so one route is held at a time.
- `false` Verification Gap: no mutation line for `trace-view.test.mjs`, K6's reason text, K3 under Banned, the fourth Integration bullet, or "live:sign-in no longer creates that user" — Rule 19 asks one mutation per AC, and the Labels, Words, Banned, Integration and floor-unit ACs each have recorded ones; both units die without `CHK|fixture-user|1`.
- `false` Verification Gap: K6's `expect(posts).toEqual([])` cannot fail — it is the Boundaries' no-post guard, not a pin.
- `false` Blind Hunter: the published events of K4 and W3 stay on the stream — a later page reads from its own snapshot's cursor, and A7 reads only events after its own `after`.
- `low` Blind Hunter (with Edge Case Hunter, Acceptance Auditor): Story 2.12's A1, A5, A7 and P4 still leave turns in the floor unit, and `floor-fixtures.test.mjs` reads only this story's files — DW-179's residual, outside QA's stated scope; the lead adjudicates DW-179 (no new entry, no trailer written).
- `low` Acceptance Auditor, Verification Gap: `floor-fixtures.test.mjs` compares call counts, not that each `turnRows` reaches `cleanFixtureRows` — a data-flow check is more than a direct correction, and each case's refs were read in this review.
- `low` Acceptance Auditor: the scroller ratchet checks `scroll-padding` but not the inline padding — padding comes from shorthands and other rules; K4 pins the three scrollers the Boundaries name.
- `low` Blind Hunter, Acceptance Auditor: on a banner's 4px accent border the inset halo sits inside the accent, so the left edge reads ring, accent, halo — the ring stays 2px solid and outermost, and a fix needs a design choice. Reopen if Story 2.16's scan or a contrast check flags the banner's focus.
- `low` Verification Gap: About's `scroll-padding` has only a source pin — its mutation is recorded, and K4 shows Chromium honouring `scroll-padding` on the chat list (Decided 21); a runtime step goes beyond K4's plan.
- `low` Verification Gap: `cleanFixtureRows` ignores its `CHK|clean|1` — a shared helper that predates the story; an assertion would throw from every `finally` of the sign-in unit, and K5 no longer depends on others' clean-up.
- `low` Edge Case Hunter: a `:hover` rule could reveal a control with `clip-path` or `transform` — the Boundaries name `display`, `visibility` and `opacity`.
- `low` Edge Case Hunter: `seedTurns` throwing after a partial save leaves recorded rows — as Edge Case 4 of the implement review: the case fails loudly on a throwaway stack.
- `low` Edge Case Hunter: About's Close scrolls with the text; K5's roles leave out `menuitemradio` — the same root causes as the implement review's Blind Hunter 1 and 5, with no new evidence.
- `low` Verification Gap: W3's `scroll-behavior` read cannot fail from a component — the same as the implement review's Verification Gap 6.
- `low` Blind Hunter: the heights ratchet skips `signin/` — spec-bound (Boundaries: `web/src/app/**` and `web/src/styles/**`).
- `low` Blind Hunter: W2 measures only vertical overflow — spec-bound (W2's measure; the layout at every width is Story 2.15's).
- `low` Blind Hunter: `live_fixture_user` keeps Story 0.3's "t03 fixture" comment and `OCUTALON_T03_PW` name — internal names with no behaviour.
- `low` Acceptance Auditor: the spec's frontmatter `deferred`, Review Triage Log and Residual risks still say every floor case leaves its turns — the fix edits the spec's intent sections; it bears on the lead's DW-179 adjudication.

### Rework 1 (smoke)

- [x] [Smoke] A popover that closes before its next render throws - `web/src/app/shared/popover.ts:115` and `:174` (`focusFirst`, from Story 2.1) - the lead's smoke opened the Visual Trace menu and pressed Esc at once: the popover closed and focus went back to its trigger, as K2 asks, but the deferred `afterNextRender(() => this.focusFirst(overlayRef))` then read `overlayRef.overlayElement`, which is null once the overlay is disposed, and Angular's ErrorHandler logged `ERROR TypeError: Cannot read properties of null (reading 'querySelector') at focusFirst`. The fix must: make `focusFirst` (and any other deferred callback in `popover.ts` or `tooltip.ts` that reads an overlay after a render) do nothing once its popover has closed; and pin it with a real-runtime step in the floor unit (for example in K2 or K3: open the Visual Trace popover and press Esc in the same task, then assert that the popover is gone, focus is on its trigger and the page logged no console error), with its `mutation:` line under `## Verification` (the guard removed -> that step red).

## Spec Change Log

- 2026-10-24, lead (spec gate): veto U-56 ruled (the new Close names, the inactive link's reason, the wordmark underline; busy buttons keep the UX's spinner form); the Conventions Tests row now names `live:floor`; `web/src/app/about/about-dialog.ts` is a reported footprint extension.
- 2026-10-24, lead (smoke): rework 1 opened with one `[Smoke]` item.

## Review Triage Log

### 2026-10-24 — Review pass
- verdicts: 43 findings — high 0, medium 7, low 25, false 10, maybe-false 1 (a row that names another row's root cause shares its verdict and route; the 43 rows hold 33 distinct root causes, 3 of them medium)
- findings:
  - `[low]` `[reject]` Blind Hunter 1: About's Close scrolls away with the text — F6 pins the Close at the top right at rest, which holds; Esc, the backdrop and Tab reach it at any scroll position; it scrolls only at a large text size or a short window; the fix moves the scroll to an inner wrapper and gives it its own gutter, with two tests changed. Residual risk for the lead (reopen if a user reports it, or Story 2.15's 200% case shows it)
  - `[low]` `[reject]` Blind Hunter 2: the composer's height is stale for soft-wrapped text after a text-size change — the criterion and W2 are the typed lines (hard breaks), which `lh` keeps fitted; a wrapped draft cut after a text-size change is rare, the field scrolls its text, and the fix is a new ResizeObserver with its test. Reopen if Story 2.15's 200% zoom case shows a cut draft
  - `[medium]` `[patch]` Blind Hunter 3 (with Verification Gap 3, Intent Alignment C1): the New messages halo is untested — K4 now scrolls the list up, publishes a turn, reaches the button with Shift+Tab and runs the ring check on it; mutation recorded
  - `[low]` `[patch]` Blind Hunter 4 (with Edge Case 5, Intent Alignment B4): the heights ratchet does not see script-set heights — it now catches `style.height =`, `[style.height...]` and `setProperty('height')`, lists the composer with its reason and requires lh units; mutation recorded
  - `[low]` `[reject]` Blind Hunter 5: K5's roles are narrower than its title — the spec names exactly button, link, textbox and menuitem, and the theme menu's items are named by the theme button's own case; no unnamed menuitemradio exists
  - `[low]` `[reject]` Blind Hunter 6: live_fixture_user has no hermetic test — it needs Docker; both live units check its CHK line and die when it is not `CHK|fixture-user|1`, so a break fails `live:sign-in` and `live:floor` at their first user
  - `[low]` `[reject]` Blind Hunter 7: Rule 21's recipe text is not updated — the spec assigns it to the lead ("For the lead"), and `_bmad/` is not a build-auto file
  - `[maybe-false]` `[defer]` Blind Hunter 8: the skip links' href="#/" points at no element, so a scan may not accept them — unverified; would be medium; deferred to Story 2.16's scan (see the frontmatter)
  - `[low]` `[patch]` Blind Hunter 9: the banned-pattern test titles read "has no a toast" — titles now read "finds no occurrence of a toast or a snackbar in web/src/"
  - `[false]` `[reject]` Blind Hunter 10: 4242 is a magic number reused for two ids — the header id and the trace session id are two placeholders that need no value in common; no caller reads one as the other
  - `[low]` `[reject]` Edge Case 1: the composer height after a re-wrap with no input — same root cause as Blind Hunter 2
  - `[false]` `[reject]` Edge Case 2: `1lh` unsupported or `line-height: normal` — `lh` is supported by Chromium, Firefox and WebKit (the engines of Story 2.16's subset), and the composer's line height is a token, never `normal`
  - `[low]` `[patch]` Edge Case 3: `refs.push(incident, await seedApproval(...))` loses the incident when seedApproval rejects — split into two pushes
  - `[low]` `[reject]` Edge Case 4: seedDecisions throws after saving some rows — the helper's own failure on a throwaway stack; the rows are not reachable by the case
  - `[low]` `[patch]` Edge Case 5: the heights ratchet and script-set heights — same root cause as Blind Hunter 4
  - `[false]` `[reject]` Edge Case 6: test-floor.sh does not set LIVE_REBUILD_WEB=1 — the spec says "no web rebuild" and the script header says that `ci/iris.sh build` makes the bundle, as for the demo-path unit
  - `[false]` `[reject]` Edge Case 7: a busy ServerButton has no reason for its first 10 s — spec-bound: E:379 gives busy buttons the label, the spinner, aria-busy and aria-disabled and no reason text (Decided 5)
  - `[low]` `[reject]` Edge Case 8: W2 holds the chip and the flag to their line, not to scrollHeight <= 1 — Decided 15 explains why the literal measure cannot hold; the `height: 22px` mutation still turns W2 red
  - `[false]` `[reject]` Edge Case 9: K4's ring box grows by a small negative offset — the outline's outer edge lies offset + width beyond the border box, so the case's `max(0, offset + width)` is the exact geometry; the spec's "when the offset is positive" is its simplification
  - `[medium]` `[patch]` Verification Gap 1 (with Intent Alignment B2): DecisionStrip's Esc guard has no running test — a new K2 case opens a reply strip's Trace help from its details and presses Esc; mutation recorded
  - `[medium]` `[patch]` Verification Gap 2 (with Intent Alignment B1): the tooltip's "only waiting" Esc branch has no running test — K2 drives the pointer's enter and the Esc in one task; mutation recorded
  - `[medium]` `[patch]` Verification Gap 3: duplicate of Blind Hunter 3
  - `[low]` `[patch]` Verification Gap 4: About's scroll-padding is pinned by nothing — a ratchet now requires the gutter's scroll-padding in every scrolling rule (the composer's text area is listed with its reason); K4 shows that the mechanism works; mutation recorded
  - `[low]` `[patch]` Verification Gap 5: the per-instance ids are unpinned — W4 sends a second failing message and expects a distinct id; mutation recorded. The busy notice's id is not pinned: no two buttons show a notice together on the page today (reopen when one does)
  - `[low]` `[reject]` Verification Gap 6: W3's getAnimations and scroll-behavior assertions cannot fail from a component — the pins are `animation-name: none` (spinner mutation recorded) and the ratchet's smooth-scroll and global-rule cases; the two runtime reads are the control that the probe sees a running animation
  - `[low]` `[defer]` Verification Gap other 1: rows are not removed (seedTurns does not adopt them) — pre-existing helper behaviour, deferred (see the frontmatter); the K cases bound their own assumptions (their rows are counted by their own stamp)
  - `[low]` `[reject]` Verification Gap other 2: source-text pins are not behaviour pins — by design (the spec's ratchets scan sources); K2 and the new strip case are the behaviour pins
  - `[low]` `[patch]` Verification Gap other 3 (with Intent Alignment C3): the inset halo of main, the rail and a banner is not asserted — K4 now reads style, width, colour, offset and the halo of each; mutation recorded
  - `[false]` `[reject]` Intent Alignment A: no run evidence for `live:floor` — the evidence is the verification section of this spec (21 cases at the first pass, 22 after the patches)
  - `[medium]` `[patch]` Intent Alignment B1: duplicate of Verification Gap 2
  - `[medium]` `[patch]` Intent Alignment B2: duplicate of Verification Gap 1
  - `[low]` `[reject]` Intent Alignment B3: reduced motion is a per-file ratchet and W3 reads the spinner and the dots — the ratchet asserts that the files that animate are exactly those two
  - `[low]` `[patch]` Intent Alignment B4: duplicate of Blind Hunter 4
  - `[medium]` `[patch]` Intent Alignment C1: duplicate of Blind Hunter 3
  - `[false]` `[reject]` Intent Alignment C2: the scroll mechanism is not recorded — Decided 21 and the K4 mutation line record that scroll-padding was used
  - `[low]` `[patch]` Intent Alignment C3: duplicate of Verification Gap other 3
  - `[low]` `[reject]` Intent Alignment C4: About's Close while scrolled — same root cause as Blind Hunter 1
  - `[low]` `[reject]` Intent Alignment C5: the composer's soft-wrapped text — same root cause as Blind Hunter 2
  - `[low]` `[reject]` Intent Alignment C6: "a target that is not in the page does nothing" is unexercised — the regions always render with the page, and the code is a single optional call; a test would need a page without a region
  - `[false]` `[reject]` Intent Alignment C7: the inactive link's change is reached by a reload — the spec leaves the in-place change on a live turn to V7 (Story 2.13), which stands
  - `[low]` `[patch]` Intent Alignment C8: the "error answer" path of the load error is not asserted — W3 reaches the failed state by an error answer and now reads Retry's description there; mutation recorded
  - `[false]` `[reject]` Intent Alignment C9: Reconnecting's Close is not in K5 — spec-bound: its name is pinned in banner-view.test.mjs and read in B13
  - `[false]` `[reject]` Intent Alignment D: the spec file is not in the diff — the layer's input excludes the claims on purpose

### 2026-10-24 — Review pass (rework 1, smoke)
- verdicts: 9 findings — high 0, medium 0, low 5, false 3, maybe-false 1
- findings:
  - `[low]` `[reject]` Blind Hunter: the Verification "unit" line still says 22 floor tests, K2 now has three — the fix is an edit to this spec's own text, which a finding cannot ask for (the count of this pass is on the rework's mutation line).
  - `[low]` `[reject]` Blind Hunter: the Spec Change Log has no entry for rework 1 and `baseline_commit` differs from `baseline_revision` — spec bookkeeping; the fix edits this build's spec, and the two baselines are the skill's (first pass and this pass).
  - `[low]` `[reject]` Blind Hunter: the new case reads `shown` synchronously, sends Esc to `document.activeElement` without a focus check, waits a fixed 500 ms, and has no fast-tier test of `Popovers.show` — the case asserts `opened` is 1 and focuses the trigger and asserts it before the task; with the guard removed it was red, so each assumption holds on the runner; there is no Angular component test host in `web/` (Node ratchets and Playwright only), so a fast-tier test is not a direct correction.
  - `[maybe-false]` `[reject]` Edge Case Hunter: an overlay disposed other than by `ref.close()` leaves `isOpen` true and the callback throws again — no path disposes the overlay but `PopoverRef`'s `onClose` (read in `popover.ts`); if one existed the harm is a logged error in a focus helper (low), so a guard (`hasAttached()`) is not worth its branch.
  - `[false]` `[reject]` Edge Case Hunter: the new case has no try/finally — it seeds nothing and publishes no condition, so there is nothing to clean up.
  - `[false]` `[reject]` Edge Case Hunter: Esc goes to `document.activeElement`, assumed to be the trigger — the case asserts `menu` is focused before the task, and a script `click()` does not move focus.
  - `[low]` `[reject]` Verification Gap: the 500 ms wait is not a signal that the render ran — the guard-removed run was red on this runner, so the render comes well inside it; a wait on the render would add machinery for a runner-speed case nobody met.
  - `[false]` `[reject]` Verification Gap: the `errors` collector counts any `console.error` or `pageerror`, so an unrelated error could flake it — it is cleared after `openFloor` and can only fail loudly, never hide the regression; no unrelated error was seen in 24 floor runs.
  - `[low]` `[reject]` Intent Alignment (descriptive): the diff implements reading B (the defect fix keeps every contract-described outcome); its decisive assertion, no console error, and the Visual Trace menu popover are not a matrix row, and the same-task Esc is synthetic — all three are what the lead's `[Smoke]` item asks for; no deviation from the contract.

## Design Notes

**Governing ADs and conventions (Rule 6).**
- **AD-13:** untrusted text renders as text. Every new text is bound by interpolation, nothing calls `bypassSecurityTrust*`, and the CSP stays `script-src 'self'`. W2 changes custom properties through the CSSOM, which the CSP does not restrict.
- **AD-12:** one live path. No poller and no event is added.
- **AD-22:** Playwright specs run on a throwaway stack and Node tests in `web/scripts/`. `ci/iris.sh` is the one recipe, and `ci/units.sh` is the one list. `image` stays the IRIS checks job, which is why the new unit joins `shards`.
- **AD-29:** `web/`, `docker/tests/**` and Lane B's entries of `ci/units.sh` are Lane B's.
- **AD-33:** no new event type or publisher.
- **Conventions:**
  - **Angular:** standalone components and signals.
  - **Announcements and focus:** one new `.focus(`, listed in the ratchet with its count and reason; no new announcement.
  - **Tests:** specs under `web/e2e/`, and the floor specs in `web/e2e/floor/`.
  - **Text OcuTalon sends:** the page's fixed strings are page constants, as `BANNER_TEXTS` and `TRACE_TEXTS` are; nothing is added to the catalog.
- **Stack:** no new dependency.

No AC contradicts an AD's Rule.

**Rule 5:** no NFR is unmeasurable. NFR-25's keyboard, label, colour, resize and motion parts are all DOM facts:
- names come from Playwright's own accessible names (`ariaSnapshot`);
- ring geometry, `text-decoration`, scroll heights and `getAnimations()` are read in the page;
- "200%" is the text-only doubling of Decided 7.

**Decided in-stage** (small, reversible, within the intent):
1. **No further split.** The story's two criteria come to about 20 small page edits, two Node ratchets, ten browser cases and the unit move, with no new logic module. Story 2.12 carried three new modules and 46 Node cases in one pass. Each gap is a few lines, and a split would pay a second plan-to-smoke cycle for the same unit move. Epic 2 keeps its four split children.
2. **Skip links.**
   - They are `a` elements with `href="#/"`, a prevented default, and `focus()` on the region.
     - Under hash routing, an in-page `#id` would navigate the router.
     - `#/` is the page's own route, so a middle-click opens the same page.
   - They sit outside every landmark, so F1's landmark counts hold.
   - The look (hidden until focused, then top left, link-styled) is not in the UX; it is presentation only and adds no words.
   - The targets are the regions themselves, as E:404 names them.
3. **Rings inside the region.** `main.main`, `section.rail` and each `.banner` fill the page's width, so the 2px outer ring cannot show at the viewport's edge. They draw the same ring and halo inside their edge, so the focus look is unchanged in kind and stays unique to focus (UX-DR33).
4. **"Topmost" includes a shown tooltip.** E:216 makes Esc dismiss a tooltip. A tooltip sits above a disclosure, so it takes the first Esc. A popover's Esc is handled by the CDK's body-level dispatcher, after an element's own handler, so a disclosure must ask `Popovers.hasOpen()` first.
5. **Busy buttons keep E:379's form.** The UX lists the explained-disabled controls (E:441, UX-DR133): Break the feed, and the composer and guide prompts at the limit. It gives busy buttons their own form: the label kept, a spinner, `aria-busy` and `aria-disabled`. The spinner is a shape, not a colour, and `aria-busy` says the state. Adding a reason would change the UX's busy form, so none is added.
6. **The explained-disabled controls of Epic 2.**
   - The conversation link is the only control of this epic that cannot act.
   - The composer at the allowance limit is Story 16.9's criterion (`epics.md:4307`); it follows this pattern.
   - Break the feed and the mailbox are Epic 4's.
7. **"200% without loss" is minimum heights.**
   - The criterion says "because heights are minimums", and E:443 says "minimum heights replace fixed ones" plus the stacked layout, which is Story 2.15's. So this story removes fixed heights, makes the composer and About follow the text, and tests a text-only doubling. Browser zoom at 1280px gives a 640px layout, which is Story 2.15's.
   - The one-line previews (the older strips' first reason, D2; the rail row's summary, R19) are specified by Stories 2.6 and 2.8, and they still cut text in the 288px rail at large text. Changing them is spec-bound (For the lead).
8. **Errors linked.** There are three error texts on Epic 2's page, each beside its button: the load error, the busy notice and "Not sent". Each button is described by its error. The composer has no field error: an empty send does nothing.
9. **Links.** `a.button` gets the link's underline in `controls.css`, so the conversation link and "Open Visual Trace" are underlined wherever they are. The home link underlines its wordmark, the text part of the link (veto: the brand's look).
10. **The rail's padding** is the token, `--status-rail-padding-inline` (4px), plus an 8px inset of the content. This keeps today's 12px and its look, and the gutter is now the token.
11. **Names left as they are.**
    - The trace links' "Trace (opens in a new tab)": a text link, composed by Story 2.13 by UX-DR42's rule.
    - The theme button's "Theme: System": the UX's own name (E:205).
    - "Retry" and "Send": text buttons, the UX's words.
12. **State words, as read.**
    - A banner's severity is shown by its icon and colour, but its text states the condition.
    - A card's kind is in its text ("Reminder:", "Why now:"), and in its chip when a decision shows.
    - The theme's state is the checked item of its menu.
    - A disclosure's state is its content, and `aria-expanded`.
    - None needs a new word.
13. **The unit.**
    - **Where.** `live:floor` joins `shards`, not `browser` and not `image`:
      - `browser` is already the longest group;
      - `test-demo-path-gate.sh` stubs the `browser` group's units;
      - AD-22 names `image` the IRIS checks job.
    - **No rebuild.** The script does not rebuild the web bundle, like `test-demo-path.sh`, because `ci/iris.sh build` builds it in CI and in the Verification recipe.
    - **`live_fixture_user`** is the sign-in script's helper, moved into `lib-live.sh` (Rule 2).
    - **What stays in `live:sign-in`.** Its specs still read the renamed Close buttons and the moved `holdState`. These are edits to assertions only, with no new wait, so they add no browser time.
14. **The ids.** The keyboard and label cases are K1 to K6, and the words, resizing, errors and motion cases are W1 to W4. A6, P1 and P3 keep theirs.

**Decided in-stage (implement).**
15. **W2's measure for the chip and the flag.** `.chip` and `.flag` set their text at `line-height: 1`, so at 200% the font's content area is about 2px taller than the line box, and `scrollHeight - clientHeight <= 1` fails though no glyph is cut. W2 holds those two to their line (`clientHeight` at least the computed line height) and keeps the literal `<= 1` measure for `.button`, the banners and `.header`. The product is unchanged.
16. **The floor cases' shared page helper** is `web/e2e/support/floor.ts`, not "in the spec file": K5 and W1 (two spec files) read the same page, and a second copy would be a copy for no reason (Rule 2).
17. **The hidden skip link** uses `overflow: hidden` and `clip-path: inset(50%)` until it has focus, not `.visually-hidden`, so `base.css`'s fixed `height: 1px` stays the only entry of the heights list.
18. **Reset soon and the first snapshot.** A session's status events reach the page only live, never in the first snapshot, so K4, K5, W1 and W2 publish Reset soon after the page has loaded (`addResetSoon`). The no-key banner comes from the instance.
19. **Seeded turns carry a reply decision only.** A seeded turn's attention decision stays in the rail's Recent decisions with no cleanup path, so the floor cases seed turns without one.
20. **About's Close** is absolutely positioned inside the dialog host, which is now the scroller (Task 4's reading), so it scrolls with the text. It is at the top right at scroll 0 (F6), and Tab or Esc reaches it or closes the dialog at any scroll position.
21. **Focus scrolling and `scroll-padding`.** K4 measured that Chromium's focus scrolling honours the scroller's `scroll-padding` (with the chat list's `scroll-padding` removed, the ring of "Decision details" falls outside `div.list`), so the rail, the chat list and About use `scroll-padding: var(--space-scroll-gutter)`, and no control got a `scroll-margin`.
22. **Esc on a waiting tooltip** is tested by driving the pointer's enter and the Esc in one task from the page (K2), so that no 300 ms timer can run between them on a slow runner.

**Veto-window items** (new public text, or the brand's look, that the UX leaves open):
- **"Close reset notice" and "Close reconnecting notice":** the two banner Close names, verb plus object, as in the UX's "Unpair Telegram". Alternatives: "Close the reset warning" and "Close the reconnecting message".
- **"Close About OcuTalon":** About's Close, named after the menu item that opens it. Alternative: "Close the About dialog".
- **"Available after your first message.":** the inactive conversation link's reason. It is true as built: the link takes the newest turn's address, and a turn exists once a message is sent. Alternative: "Send OcuTalon a message first."
- **The underlined wordmark:** the home link's text part is underlined, as every link is. DESIGN.md's logo don'ts (recolor, crop, outline, animate; D:871) do not cover an underline, but it is the brand's look. Alternative: underline the home link only on hover and focus, which would leave one link not underlined at rest.

**For the lead (your calls).**
- **The veto-window items above.**
- **Decided 5's reading.** "A control that can't act" is read as the UX's explained-disabled list. A busy button keeps E:379's form (a spinner and `aria-busy`, no reason text). If you read it as covering busy buttons too, the reason would be new public text: a veto item and a change to the UX's busy form.
- **Footprint extension (Rule 11):** `web/src/app/about/about-dialog.ts`. Story 2.1 made it, it is Lane B's web, and no contended epic owns it. Shared web infrastructure is also edited, which you report: `web/playwright.config.ts` (the `floor` project) and `web/package.json` (`e2e:floor`).
- **Rule 21's recipe text** in `_bmad/custom/skill-rules.md` lists the live units and the groups. Appending "`live floor` (Story 2.14; `shards` runs lane-a, lane-b and `live:floor`)" is yours to decide.
- **The balance rule.** These figures are from the two latest Epic 2 runs, 40073746083 and 40088998253:
  - `shards` took 407 to 440 s and `browser` 978 to 1020 s. The mean of the six is about 575 s, with run 40073746083's 462 s for `production`, which run 40088998253 skipped.
  - With `live:floor` (about 330 to 450 s in CI, inference), `shards` comes to about 740 to 890 s, against a new mean of about 640 s. That is about 1.15 to 1.4 times the mean, around the rule's edge.
  - `browser`, at about 1.5 times after the move, is over it already, and was before this story.
  - Measure at this story's first CI run. If `shards` runs over 1.25 times the mean, a whole-unit move is a `ci/units.sh` change (for example `live:bundle-folder` or `live:floor` between groups).
- **Story 2.16 and the floor unit.** Story 2.16's Firefox and WebKit subset will run in `live:floor`, adding about 9 to 12 minutes in CI (Story 2.12's estimate), so its plan places the unit again.
- **The one-line previews (Decided 7).** At large text in the 288px rail, the rail row's summary (R19) and an older strip's first reason (D2) are cut by design. A change would amend Stories 2.6 and 2.8.
- **Rule 20 (optional).** A Conventions row "Tests": "The accessibility floor's browser specs live in `web/e2e/floor/` and run in `live:floor` (`docker/tests/test-floor.sh`), never in `live:sign-in`." Stories 2.15, 2.16 and 4.5 add cases there.

**Integration ACs (Rule 1).** The new shared pieces and their consumers in this story:
- `SkipLinks`: consumed by `App` (K1).
- `Popovers.hasOpen()`: consumed by `DecisionRow` and `DecisionStrip` (K2, and the ratchet).
- `ServerButton.describedBy`: consumed by `MainPage` (W4).
- `live_fixture_user`: consumed by `test-sign-in.sh` and `test-floor.sh`.
- `web/scripts/source-files.mjs`: consumed by `announce-focus-sources.test.mjs` and `floor-sources.test.mjs`.
- `holdState` in `support/api.ts`: consumed by `live.spec.ts`, `keyboard.spec.ts` and `words.spec.ts`.

**Consumed-by:**
- **2.15:** "Skip to status" when the rail is a drawer; the drawer's and stacked layout's scrollers keep the gutter and `scroll-padding`; its note's Close names its object.
- **2.16:**
  - its string test reads `SKIP_LINKS`, the two banner Close names, About's Close and `TRACE_TEXTS.conversationNotYet`;
  - its Firefox and WebKit subset runs in `live:floor`;
  - its scan's names check extends K5's;
  - DW-89's tab stop on the rail (`tabindex="0"`) replaces this story's `tabindex="-1"`, and the skip link's target stays focusable.
- **4.5:** "Skip to simulated devices", inserted into `SKIP_LINKS`.
- **16.9:** the composer at the allowance limit takes K6's explained-disabled pattern.
- **Every later page story:** `floor-sources.test.mjs`'s lists (heights, keys, motion, banned).

**Consumes:**
- 2.1: the header, `Popovers`, `Tooltip`, `Dialogs` and About;
- 2.5: the composer and the user message;
- 2.6: the strip and the outcome chip;
- 2.8: the rail and the decision row;
- 2.10 and 2.11: the banners and their Close;
- 2.12: `focus-rule.ts`, the ratchet and the floor specs;
- 2.13: the Visual Trace menu and the trace help.

**Extend, don't copy (Rule 2).**
- **`live_fixture_user`** is `create_fixture_user`, moved; it is not copied into `test-floor.sh`.
- **`source-files.mjs`** takes the source listing of `announce-focus-sources.test.mjs`, so the new ratchet does not copy it.
  - `page-safety.test.mjs` and `shell-styles.test.mjs` keep their own listings: they read other trees, with comments included.
- **`holdState`** moves to `support/api.ts` beside `holdPoll`.
- **`test-floor.sh`** follows `test-demo-path.sh` and `test-sign-in.sh`. It is a new unit script, as every unit is: the CI recipe runs one script per unit.
- **The spinner's reduced-motion rule** follows the dots' own rule in `ocutalon-reply.ts`.

**Ledger (Rule 17):** the inbox for this story is empty (`LEDGER slice` read empty), so no entry is addressed or declined.

## Verification

**IRIS.** This story changes no ObjectScript, so no slot call is needed. If a stage makes one:
- every IRIS MCP call names `server: ocutalon-slot-b` and `namespace: OCUTALON`;
- the first call is `iris_server_info` (build 154, port 1991);
- there is one `iris_execute_tests` call per message.

**Throwaway commands** are `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_RUN_TAG=e2s214i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`.
- `<main checkout>` is the main checkout's absolute path. It is typed only at the prompt, never in a tracked file.
- Run one piece per call with `timeout: 600000`, and end with `teardown` on the same tag and variables.
- `LOCK busy` (exit 75) means contention: wait and run it again.
- QA uses the tag `e2s214q` (stage `qa`), and review uses `e2s214r` (stage `review`).

**Every other command** runs in the foreground with `timeout: 600000`.

**Commands:**
- **(loop)** Each in its own call: `npm --prefix web test`, `npm --prefix web run lint`, `node web/scripts/catalog.mjs --check`, `bash docker/tests/test-web-build.sh` and `bash docker/tests/test-boundaries.sh`. Expected: exit 0, with `floor-sources.test.mjs`, the changed `announce-focus-sources.test.mjs`, `banner-view.test.mjs`, `trace-view.test.mjs` and `playwright-projects.test.mjs` passing.
- **(loop)** Throwaway, one piece per call: `build`; `live floor`; `teardown`. Expected:
  - A1 to A7, P1 to P4, K1 to K6 and W1 to W4 pass;
  - teardown leaves nothing.
  - **Time:** about 160 to 220 s locally (inference): a 55 to 60 s start, about 3 s for the fixture user, A and P about 53 s (measured in Story 2.12), and K and W about 50 to 90 s. Record the measured figure here.
  - **Measured at implement (local, 22 cases after the review patches; 21 before):** `ci/iris.sh live floor` took 135 s at the first pass and 138 to 141 s after the patches (the first start about 65 s; Playwright 1.3 min, K1 to K6 and W1 to W4 about 20 s of it). In `group shards` the unit took 141 s.
- **(once)** `bash docker/tests/test-ci-config.sh` and `bash ci/checks.sh`. Expected: exit 0. This covers the units, demo-path and inputs rules, with `live:floor` registered.
- **(once)** Throwaway, one piece per call: `build`; `live sign-in`; `live demo-path`; `live bundle-folder`; `group shards`; `teardown`. Expected:
  - every case passes, with the same two skips in `live sign-in` (B6 and the demo-path "not built" case) and no floor case;
  - `live sign-in` takes about 400 s (460 s before; record it);
  - `group shards` runs `shard:lane-a`, `shard:lane-b` and `live:floor`, installs Chromium before `live:floor`, and passes, in about 330 s locally.
  - **Measured at implement (local, on the patched tree):**
    - `live sign-in`: 409 s (405 s at the first pass), with 190 passed and 2 skipped (Playwright's `chromium` project lists 192 cases and no file of `e2e/floor/`); the run before this story took about 460 s.
    - `live demo-path`: 63 s, with 3 passed and 11 skipped, and `live bundle-folder`: 78 s. Both pass.
    - `group shards`: 291 s, with `shard:lane-a` 57 s, `shard:lane-b` 94 s and `live:floor` 141 s. `cmd_group` runs each unit through `ci/iris.sh live`, and `cmd_live` installs Chromium for a `BROWSER_UNITS` name, which now holds `floor`.
    - `bash docker/tests/test-ci-config.sh` (8 s) and `bash ci/checks.sh` (48 s) exit 0.
- **CI estimate (inference).** Run 40088998253 measured `live:demo-path` at 197 s (a 180 s start) and `live:sign-in` at 613 s (Playwright 6.9 min for 189 cases). From those:
  - `live:floor` takes about 330 to 450 s in CI;
  - `live:sign-in` takes about 70 to 90 s less than with the floor specs;
  - the run's wall-clock stays set by the `browser` group, so REL-4's 35 minutes holds.

**Planned mutations (Rule 19).** For each one: apply it, observe red, restore a byte-identical tree (`git status --short` and `git diff --stat` unchanged), and record `mutation: … → …` here.

| AC | Mutation | Expected red |
| --- | --- | --- |
| Keyboard | `app.ts` renders `<app-skip-links />` after `<app-header />` | K1 (the first stop is the home link) |
| Keyboard | the skip link's press does not prevent the default | K1 (the URL changes) |
| Keyboard | `DecisionRow.collapse()` ignores `Popovers.hasOpen()` | K2 (the popover step collapses the row) |
| Keyboard | the tooltip's Esc listener in the bubble phase, with no `stopPropagation` | K2 (the tooltip step collapses the row) |
| Keyboard | a `document` keydown handler that focuses the composer on "/" | K3; `floor-sources.test.mjs` (keys) |
| Keyboard | the chat list's `scroll-padding` (or the controls' `scroll-margin`) removed | K4 |
| Keyboard | `main.main` drawing its ring outside (`outline-offset: 2px`) | K4 |
| Labels | the banner Close named "Close" | K5; `banner-view.test.mjs` |
| Labels | About's Close named "Close" | K5 |
| Labels | the conversation link's `aria-describedby` dropped | K6 |
| Labels | one `app-icon` rendered without `aria-hidden` | K5 |
| Words | `a.button` with no underline | W1 |
| Words | the wordmark not underlined | W1 |
| Words | the outcome chip back to `height: 22px` | W2; `floor-sources.test.mjs` (heights) |
| Words | the composer's height in px again | W2 |
| Words | About without `overflow-y: auto` | W2 |
| Words | the spinner's reduced-motion rule removed | W3; `floor-sources.test.mjs` (motion) |
| Words | `ServerButton` without the notice's id in `aria-describedby` | W4 |
| Words | Retry sending without its description | W4 |
| Banned | a `new Audio(` in a component | `floor-sources.test.mjs` (banned) |
| Floor unit | `chromium` still running `e2e/floor/` | `playwright-projects.test.mjs` |
| Floor unit | `floor` missing from `BROWSER_UNITS` | `test-ci-config.sh` (demo-path rule) |

**Mutations recorded at implement (Rule 19).** Each was applied, the unit rebuilt (`ci/iris.sh build`) and run, and the tree restored; after each batch `git status --short` and the hash of `git diff` equalled their values before, and the untracked source files were byte-identical. Mutations that hit different cases ran together in one stack (three stacks, the cases `K1` to `K6` and `W1` to `W4` only); the Node and shell ones ran alone.
- mutation: `app.ts` renders `<app-skip-links />` after `<app-header />` -> K1 red ("the first tab stop is Skip to chat"); K4 and W1 also red, because both start with a Tab from the page's start.
- mutation: the skip link's press does not call `event.preventDefault()` -> K1 red ("and leaves the address as it was"). The case marks the address with `#/k1` first: from `#/`, the link's own address, a followed link changes nothing.
- mutation: `DecisionRow.collapse()` ignores `Popovers.hasOpen()` -> K2 red ("and only the help: the row stays open"); `floor-sources.test.mjs` (Esc guard) red.
- mutation: the tooltip's Esc listener in the bubble phase (`addEventListener` and `removeEventListener` without `true`) with no `stopPropagation()` -> K2 red ("the row stays open", at the tooltip step); `floor-sources.test.mjs` (Esc guard, two cases) red.
- mutation: a `document` keydown handler in `App` that focuses the composer on "/" -> K3 red ("on the body: "/" moves no focus"); `floor-sources.test.mjs` (keys, two cases) and `announce-focus-sources.test.mjs` (the `.focus(` count) red.
- mutation: the chat list's `scroll-padding` removed -> K4 red (the ring of "Decision details" lies outside `div.list`, which is how K4 shows that Chromium's focus scrolling honours `scroll-padding`: the `scroll-margin` fallback was not needed).
- mutation: `main.main` drawing its ring outside (`.main:focus-visible { outline-offset: 2px }`) -> K4 red ("main: the ring ... lies inside the viewport"); K1 also red, which checks the same ring.
- mutation: the banner Close names both "Close" -> K5 red ("the page: no control is named Close alone"); `banner-view.test.mjs` red.
- mutation: About's Close named "Close" -> K5 red ("with About open: no control is named Close alone").
- mutation: the conversation link's `aria-describedby` dropped -> K6 red ("it is described by an element").
- mutation: the `svg` of `app-icon` without `aria-hidden` -> K5 red ("the page: no image is read").
- mutation: `a.button` with `text-decoration-line: none` -> W1 red (the first link it finds, the Trace help's "Open Visual Trace", "with the Trace help open").
- mutation: the wordmark without its underline -> W1 red ("on the page: the skip links, the wordmark, ...").
- mutation: the outcome chip back to `height: 22px` -> W2 red ("no .chip is shorter than its text"); `floor-sources.test.mjs` (heights, two cases) red.
- mutation: the composer's `grow()` back to a pixel height -> W2 red ("the composer shows both lines, with no keystroke").
- mutation: About without `overflow-y: auto` -> W2 red ("so it scrolls").
- mutation: the spinner's reduced-motion rule removed from `controls.css` -> W3 red ("which has no animation"); `floor-sources.test.mjs` (motion) red.
- mutation: `ServerButton` without the notice's id in `aria-describedby` -> W4 red ("after 10 s more it is described by the load error and the busy notice").
- mutation: Retry sending without its `aria-describedby` -> W4 red ("Retry sending is described by its own Not sent").
- mutation: `private readonly ping = new Audio('ping.mp3')` in `App` -> `floor-sources.test.mjs` (banned: a sound) red.
- mutation: `chromium` without `'**/e2e/floor/**'` in its `testIgnore` -> `playwright-projects.test.mjs` ("chromium (the e2e script) lists exactly the spec files outside demo-path/ and floor/") red.
- mutation: `floor` missing from `BROWSER_UNITS` -> `test-ci-config.sh` red ("FAIL demo-path: the demo-path unit and the browser units").
- mutation (review patch): the `.new-messages:focus-visible` rule removed from `chat-panel.ts` -> K4 red ("New messages: with the surface halo"), at the step that scrolls the list up, publishes a turn and reaches the button with Shift+Tab from the composer.
- mutation (review patch): `DecisionStrip.collapse()` ignores `Popovers.hasOpen()` -> the new K2 case on a reply strip red ("and only the help: the details stay open").
- mutation (review patch): the tooltip's Esc handler stops the event whether or not the tooltip showed -> K2 red at the new step ("and that Esc reached the row, which collapsed"); the pending tooltip's Esc is driven by the page in one task, with `pointerenter` and the Esc dispatched together.
- mutation (review patch): `.rail:focus-visible, .main:focus-visible` without the inset `box-shadow` -> K4 red ("main: with the surface halo inside the ring"), from the new `expectInsideRing` that reads main, the rail and a banner.
- mutation (review patch): `UserMessage.notSentId` a constant -> W4 red ("which has an id of its own"), at the second failed message.
- mutation (review patch): `MainPage` without `[describedBy]` on Retry -> W3 red at the new line ("on an error answer, Retry is described by the load error") and W4 red ("after 10 s Retry is described by the load error").
- mutation (review patch): the `scroll-padding` line removed from `about-dialog.ts` -> `floor-sources.test.mjs` red ("scrollers keep the gutter").
- mutation (review patch): the composer's `style.height` back to a pixel value -> `floor-sources.test.mjs` red ("sets a height from a script or a binding only where this list has it, and only in line units"), as well as W2.
- (QA) mutation: the theme button's `[attr.aria-label]` removed from `header.ts` (an icon-only button with no name) -> K5 red ("the page: every button, link, textbox and menuitem has a name"); the recorded Close and `svg` mutations pinned the other two branches of `expectNamed`, this one pins the unnamed-control branch.
- (QA) mutation: `seedTurns` without the `Adopt(t)` of its turn -> H1 red ("the clean-up removed the turn and both decisions": the turn row was still there, `1|0|0`); `floor-sources` is not involved. The same change makes `floor-fixtures.test.mjs` ("adopts each turn and each Decision row it saves") red, observed alone.
- (QA) DW-179 fixed in test support: `seedTurns` adopts each turn and each Decision row it saves, `turnRows(seeded)` lists their Refs, and the K2 strip, K4 (both seeds), K6, W3 and `seedFullPage` (K5, W1, W2) put them in the `refs` that `cleanFixtureRows` removes in `finally`. Usage rows have no Ref and stay unrecorded (no floor case writes one). Story 2.12's A and P cases are unchanged and still leave their turns.
- (QA) After the QA changes, on the restored tree: `live floor` 23 passed in about 140 s (A1-A7, H1, P1-P4, K1-K6, W1-W4), `npm --prefix web test` 515 pass, `lint`, `test-boundaries.sh` and `test-ci-config.sh` exit 0; tag e2s214q torn down. Both QA mutations ran in one stack (one build, one `live floor`); `git status --short` and the hash of `git diff` equalled their values before.
- (QA) Files created: `web/e2e/floor/fixtures.spec.ts` (H1), `web/scripts/floor-fixtures.test.mjs`. Files changed: `web/e2e/support/iris.ts`, `web/e2e/support/floor.ts`, `web/e2e/floor/keyboard.spec.ts`, `web/e2e/floor/words.spec.ts`, `docker/tests/test-floor.sh` (header and the two result lines name H1).
- A case that expects a key to change nothing looks only after the page has drawn (`settled` in `web/e2e/support/floor.ts`: two animation frames and a task). K2 passed against the first mutation of the popover step because the popover is removed at once and the row's `aria-expanded` is drawn later; with the wait it is red.
- (review) mutation: `app/app.ts` gains the template binding `(window:keydown.k)`, and separately a `host: { '(document:keydown)': ... }` binding -> `floor-sources.test.mjs` red ("binds a template key event only to Enter or Escape ..." and "registers a keyboard handler only in the files that are listed ...") for each.
- (review) mutation: `composer.ts` gains `'/' === event.key` -> `floor-sources.test.mjs` red ("compares a key only with Enter and Escape ...").
- (review) mutation: `tooltip.ts` gains `doc.addEventListener("keydown", (event) => ...)` (double quotes, an inline handler) -> `floor-sources.test.mjs` red ("has no other listener for a document keydown ...").
- (review) mutation: `decision-row.ts`'s first `overflow: hidden` becomes `overflow-x: auto` -> `floor-sources.test.mjs` red ("declares a scroll-padding of the gutter in every rule that scrolls ...").
- (review) mutation: `composer.ts`'s `grow()` sets a pixel height after its lh one -> `floor-sources.test.mjs` red ("sets a height from a script or a binding only where this list has it, and only in line units"); `user-message.ts` gaining `setStyle(el, 'height', '40px')` turns the same case red.
- (review) mutation: `app/app.ts` gains a `styles: [...]` array -> `floor-sources.test.mjs` red ("reads the CSS of every component ...").
- (review) K5's "one row of each rail kind" now counts only its own rows (its stamp, and its approval's row key), and K4's Trace count reads only links; both are preconditions, so the K5 and K4 mutation lines above stand. After the review patches, on the restored tree: `npm --prefix web test` 516 pass; `lint`, `test-boundaries.sh` and `test-ci-config.sh` exit 0; `build` and `live floor` passed 23 (A1-A7, H1, P1-P4, K1-K6, W1-W4; Playwright 1.3 min); teardown of tag e2s214r left nothing. `git status --short` and the hash of `git diff` were equal before and after every mutation.
- (rework 1, smoke) mutation: `Popovers.show`'s deferred `afterNextRender` calls `focusFirst` without the `ref.isOpen` guard -> the new case "K2: a popover that Esc closes in the task that opened it logs no error" red ("and the page logged no error": `ERROR TypeError: Cannot read properties of null (reading 'querySelector')`), the only red of 24 in `live floor`. The case opens the Visual Trace popover and dispatches Esc in one task, so the render that waits to focus into it comes after the popover has closed; with the guard it is green (24 passed, 1.3 min). `tooltip.ts` has no render-deferred callback (only timers that `hide()` clears). `npm --prefix web test` 516 pass; `lint`, `test-web-build.sh` and `test-boundaries.sh` pass. `git status --short` and the hash of `git diff` were equal before and after the mutation.

**Shared surfaces:**
- **The first tab stops.** The two skip links now come before `a.home`. F3, F7 and B10 start from `a.home` or from the header and are unaffected; no case presses Tab from the page's start.
- **Every "Close" name.** The banners' Close (B5, B8, B9, B10, B13, B14; `BANNER_TEXTS` in `banner-view.test.mjs`) and About's Close (F6, F7) are renamed (Task 11).
- **`TRACE_TEXTS`** gains `conversationNotYet` (`trace-view.test.mjs`). The Visual Trace popover gains the reason line while the link is inactive (V7 and V8 read the popover; neither checks its whole text).
- **`ServerButton`'s and Retry sending's `aria-describedby`** are new. L6, L7, L11 and P3 find Retry by name, and C4 and P1 find Retry sending by name; none of these changes.
- **The Playwright projects.** `chromium` loses `e2e/floor/`, and `floor` and `e2e:floor` are new (`playwright-projects.test.mjs`).
- **The units.**
  - `ci/units.sh`'s `shards` and `BROWSER_UNITS` change (the `test-ci-config.sh` rules; the `browser` group that `test-demo-path-gate.sh` stubs is unchanged).
  - `test-sign-in.sh` loses `ZzFloor`, its variables and its label; `lib-live.sh` gains `live_fixture_user`.
- **`FOCUS_CALLS`** gains the skip links; `section.rail` gains `tabindex="-1"` (F1 counts only positive tab indexes).
- **`holdState`** moves to `support/api.ts` (`live.spec.ts`).
- **Composer heights.** C3's five-line cap reads the computed line height plus padding, and stays equal at 100%.
- **No server surface changes.**

**Every test added or changed passes on a fresh environment, in either order:**
- each K and W case signs in the floor user;
- each holds or routes only its own requests, and `afterEach` unroutes them;
- each clears every condition it turns on and removes its rows with `cleanFixtureRows`, in `finally`, and finishes any running turn it seeds;
- K2 and W1's help step start a fresh browser context, so the Trace help is needed;
- no case lets a chat post reach the server (W4 answers `/messages` in the browser), so no turn of one case replies inside another case's window;
- W2's doubled text lives only in its own page;
- the Node tests read sources only.

**Manual checks (human-only):** none new. DW-159's screen-reader check stays with the human.

## Auto Run Result

Status: done
Blocking condition: none

**Plan stage (2026-10-24).** The plan halted after planning, as the dispatch asked.
- It reused the committed `epic-2-context.md` (d7717c3) without recompiling it.
- It took Story 2.12 as the continuity context, and Story 2.13's Code Map as well.
- It ran no runtime measurement and started no throwaway. It read the CI job and unit times of runs 40073746083 and 40088998253 (read-only `gh`).
- **The registration needs no edit to `ci/iris.sh`, `test-ci-config.sh` or a workflow.** `live <name>` runs any group's `live:<name>`, and the rules read `ci/units.sh`.
- **For the lead:**
  - the four veto-window items;
  - the footprint extension (`about/about-dialog.ts`) and the shared web infrastructure (`playwright.config.ts`, `package.json`);
  - the balance-rule figures;
  - optionally, Rule 21's recipe line and a Conventions row.

**Implement and review stage (2026-10-24).**

*Change.* Each gap of the Problem has its small change, and the accessibility floor has its own browser unit.
- Skip links: "Skip to chat" and "Skip to status", the first tab stops, move focus to `main.main` and `section.rail` (`tabindex="-1"`) without changing the address.
- One Esc, one layer: the tooltip listens in the capture phase and stops the event only when it showed; `Popovers.hasOpen()` makes `DecisionRow` and `DecisionStrip` leave an open popover to the Esc.
- Focus rings: `main.main`, `section.rail` and each banner draw the ring and its halo inside their own edge; the rail, the chat list and About keep the gutter and a `scroll-padding`; New messages keeps the halo.
- Labels: "Close reset notice", "Close reconnecting notice", "Close About OcuTalon"; the inactive conversation link says "Available after your first message." and is described by it.
- Errors and words: `ServerButton.describedBy` and the notice's id, the load error's and "Not sent"'s ids; `a.button` and the wordmark underlined; `min-height` for the chip and the flag; the composer in `lh` units; About scrolls; the spinner stops under reduced motion.
- The unit: `live:floor` (`docker/tests/test-floor.sh`) in the `shards` group runs Story 2.12's A1-A7 and P1-P4 and this story's K1-K6 and W1-W4 (22 Playwright tests; K2 has a second test for the reply strip); `live_fixture_user` moved into `lib-live.sh`.
- Node ratchets: `web/scripts/floor-sources.test.mjs` (keys, Esc, heights, scrollers' gutter, motion, banned patterns) over `web/scripts/source-files.mjs`, which `announce-focus-sources.test.mjs` shares.

*Files.*
- Page, new: `web/src/app/header/skip-links.ts`.
- Page, changed: `app/app.ts`, `app/about/about-dialog.ts`, `app/banners/banner-stack.ts` and `banner-view.ts`, `app/chat/{chat-panel,composer,decision-strip,fallback-flag,outcome-chip,user-message}.ts`, `app/header/header.ts`, `app/main-page/main-page.ts`, `app/rail/decision-row.ts`, `app/shared/{popover,server-button,tooltip,trace-view}.ts`, `styles/controls.css`.
- Unit, new: `docker/tests/test-floor.sh`. Changed: `docker/tests/lib-live.sh`, `docker/tests/test-sign-in.sh`, `ci/units.sh` (`shards`, `BROWSER_UNITS`), `web/playwright.config.ts`, `web/package.json`.
- Specs, new: `web/e2e/floor/keyboard.spec.ts`, `web/e2e/floor/words.spec.ts`, `web/e2e/support/floor.ts`. Changed: `web/e2e/floor/{announcements,focus}.spec.ts` (headers), `web/e2e/support/{api,iris}.ts`, and the readers of renamed controls `web/e2e/banners/banners.spec.ts`, `web/e2e/frame/frame.spec.ts`, `web/e2e/live/live.spec.ts`.
- Node tests, new: `web/scripts/floor-sources.test.mjs`, `web/scripts/source-files.mjs`. Changed: `announce-focus-sources.test.mjs`, `banner-view.test.mjs`, `trace-view.test.mjs`, `playwright-projects.test.mjs`.

*Review.* Four layers reported 43 findings (33 root causes). Patches: 10 root causes, of which 3 medium (the New messages halo, the strip's Esc guard and the waiting tooltip's Esc had no running test) and 7 low (script-set heights in the ratchet, a scroller-gutter ratchet, test titles, a fixture push, the unique "Not sent" id, the non-tab-stop ring, the load error's error-answer path). Deferred: 2 (the skip links' href under a scan, unverified; seedTurns rows never removed, pre-existing). Rejected: 21, each with its reason in the Review Triage Log; the ones a person may want to reopen are About's Close scrolling with the text and the composer's height for wrapped text after a text-size change (both low, at a large text size only).
- Patched counts by verdict: medium 3, low 7.
- Follow-up review recommended: true. The three medium patches added test steps and one ratchet after the layers had read the diff (K2's reply-strip test and its waiting-tooltip step, K4's New messages and inset-ring steps, W3 and W4 additions, the "scrollers keep the gutter" and script-height ratchets); each has a mutation that turned it red, but no layer has read them.

*Verification.* All on the patched tree, forward only.
- `npm --prefix web test` 510 pass; `lint`, `catalog.mjs --check`, `test-web-build.sh`, `test-boundaries.sh`, `test-ci-config.sh` and `ci/checks.sh` exit 0.
- `live floor`: 22 passed in 141 s (21 at the first pass in 135 s). `live sign-in`: 190 passed and 2 skipped in 409 s (about 460 s before), and no floor case. `live demo-path` 63 s, `live bundle-folder` 78 s, `group shards` 291 s (`shard:lane-a` 57 s, `shard:lane-b` 94 s, `live:floor` 141 s). Teardown of tag e2s214i left nothing.
- 30 mutations (22 at the first pass, 8 for the review patches) turned the named test red; the tree was byte-identical after each batch (`git status --short` and the hash of `git diff` equal).

*Residual risks.*
- About's Close is inside the scrolling host, so it scrolls with the text when About is taller than the window (a large text size). Esc, the backdrop and Tab still close About.
- A composer draft of wrapped text keeps its old line count after a text-size change until the next input.
- The fresh-environment check in reverse order has not run: K4's walk is bounded at 150 stops and the floor cases leave their seeded turns (deferred).
- The skip links' `href="#/"` under Story 2.16's scan is unverified (deferred).

*For the lead.*
- The four veto-window texts are in as the spec lists them.
- Footprint extensions to report (Rule 11): `web/src/app/about/about-dialog.ts`, `web/playwright.config.ts`, `web/package.json`, `web/e2e/support/{api,iris,floor}.ts`, and the assertions of `web/e2e/banners/banners.spec.ts`, `frame/frame.spec.ts` and `live/live.spec.ts` that read a renamed Close or the moved `holdState`. No contended path was touched.
- Optional, yours to decide: Rule 21's recipe line for `live floor` (and `shards` running `live:floor`), and the Conventions row "Tests" for `web/e2e/floor/`.
- The balance rule: measure `shards` at this story's first CI run (local: 291 s in all, `live:floor` 141 s; CI estimate 330 to 450 s for the unit).

**Rework 1 (smoke) pass (2026-10-24).** This pass covers only the one `[Smoke]` item.

*Change.* `Popovers.show` in `web/src/app/shared/popover.ts` runs its render-deferred `focusFirst` only while `ref.isOpen`, so a popover that Esc closes before the next render no longer reads a disposed overlay. `tooltip.ts` has no callback that reads an overlay after a render (only timers that `hide()` clears), so it needed no change. The floor unit gains a case: `web/e2e/floor/keyboard.spec.ts` "K2: a popover that Esc closes in the task that opened it logs no error" (the unit is now 24 cases).

*Review.* Four layers reported 9 findings: patches 0, deferred 0, rejected 9, each with its reason in the Review Triage Log (low 5, false 3, maybe-false 1). Follow-up review recommended: false (no patched finding). Patched counts by verdict: none.

*Verification.* `npm --prefix web test` 516 pass; `lint`, `test-web-build.sh` and `test-boundaries.sh` exit 0. Throwaway tag e2s214i: `live floor` 24 passed (1.3 min); `live sign-in` 190 passed and 2 skipped (5.6 min); teardown left nothing. The mutation (the guard removed) turned only the new case red; the tree was byte-identical afterwards.

*Residual risks.* The new case waits a fixed 500 ms for the render that would throw (red on the guard's removal on the local runner).
