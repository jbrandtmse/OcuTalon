---
title: 'Story 2.16: Prove the floor in Chromium, Firefox and WebKit'
type: 'feature'
created: '2026-10-24'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The accessibility floor (keyboard alone, every control named, AA contrast) is proven only in Chromium, nothing measures contrast in a browser, and nothing checks the page's fixed strings against the UX. Task 0 found that the floor breaks in the other supported engines:
- WebKit's Tab skips links and buttons; Option+Tab reaches them.
- WebKit does not focus a pressed button, so the Visual Trace button reopens its own menu (DW-145).
- The chat list and the rail are no tab stops in WebKit (DW-89).
- Firefox leaves a control that sits partly past the rail's or the list's edge where it is when Tab reaches it, so its ring is clipped. It also makes the chat list a tab stop whose ring falls outside the window.

**Approach:**
- The floor unit `live:floor` runs, on its one stack, every floor case in Chromium and then a tagged subset (`@browsers`) in Firefox and WebKit.
- An in-house scan (names, contrast and links) runs in all three engines at 1280×720 and 1280×600, in the light and dark themes.
- A Node string test checks every fixed page string against the UX.
- DW-89, DW-145, DW-178 and DW-179 are fixed, and so is Firefox's clipped ring.
- Two CI group entries move, so that REL-4 and the balance rule hold.

## Boundaries & Constraints

**Always:**
- **Engines.**
  - `web/playwright.config.ts` gains two projects, `floor-firefox` (`devices['Desktop Firefox']`) and `floor-webkit` (`devices['Desktop Safari']`). Each has `testDir: './e2e/floor'` and `grep: /@browsers/`.
  - `e2e:floor` becomes `playwright test --project=floor --project=floor-firefox --project=floor-webkit`, so Chromium runs first and runs every floor case.
- **The `@browsers` subset** (Playwright `{ tag: '@browsers' }`):
  - K1 (skip links);
  - K2's first case (tooltip, then popover, then row);
  - K4 (the ring walk at 1280×720);
  - G1 (1280×600: the page does not scroll, and the ring walk);
  - P2 (the focus rule);
  - A1 (an announcement, and the single "…" of "Working…" as rendered);
  - U1 to U3 (the scan);
  - E1 to E3 (the engine cases below).

  A later floor case may join the subset.
- **The step key.** `stepKeys(page)` in `web/e2e/support/floor.ts` returns `{ next, back }`, where `back` is `Shift+` and the same key.
  - It detects the key once per engine, in a scratch context of its own that holds a link and a button: `Tab` when Tab reaches the link, else `Alt+Tab` (Option+Tab) when that does, else it throws.
  - Every Tab and Shift+Tab press of the `@browsers` cases, of K4's loop and of `layout.spec.ts`'s `walk()` uses it.
  - It detects rather than reading the engine's name, because Linux WebKit's Tab is unmeasured.
- **Rings at tab stops.** `support/floor.ts` gains:
  - `INSIDE_RING`, the regions that draw their ring inside their own edge: `section.rail`, `main.main` and `app-chat-panel .list`;
  - `readFocus`'s `inside` flag, true when the focused element is one of them;
  - `expectInsideRing`, moved from `keyboard.spec.ts`;
  - `expectStopRing(page, reading)`, which applies `expectInsideRing` to those regions and `expectRing` to every other stop.

  The walks of K4, G1 and G5 use `expectStopRing`.
- **The scan** (`web/e2e/support/scan.ts`, new). `scanPage(page, what)` returns its findings as strings, and every case expects `[]`. It has three rules, and each finding names its rule and its element.
  - **Names.** K5's `expectNamed` moves here and is extended. K5 calls this rule.
    - In `body.ariaSnapshot()`, every line of a widget role has a name. The widget roles are button, link, textbox, searchbox, combobox, checkbox, radio, switch, slider, spinbutton, tab, menuitem, menuitemcheckbox, menuitemradio and option.
    - No control is named "Close" alone, no `img` is read, and every `svg` is `aria-hidden`.
    - Every visible element with `tabindex="0"` that is not a native control has a `role` and a non-empty accessible name (Playwright's `toHaveAccessibleName`).
  - **Contrast.** It uses WCAG's relative-luminance formula, computed in `page.evaluate` from computed styles. Each colour is composited over its ancestors' backgrounds down to the first opaque one, over white.
    - **Text:** every painted text run, and the composer's `::placeholder`, needs 4.5:1, or 3:1 for large text (24px and up, or 18.66px and up at weight 700 or more; this covers the "Talon" wordmark).
    - **Boundaries:** each visible `textarea`, `input`, `.button-secondary` and chip control (a `button` with a chip class) needs 3:1 against its backdrop: its border colour when the border is wider than 0, else its background.
    - **The focus ring:** `--focus` needs 3:1 against `--surface` (the halo) and against the backdrop of every visible focusable control.
    - **Exempt,** each named in the code with its reason:
      - inactive controls (`aria-disabled="true"` or `:disabled`) and their text (WCAG; DESIGN's inactive Break the feed);
      - decorative borders: only the listed controls' boundaries are checked, and card borders in `--border` are decorative by design;
      - text that is not painted (`visibility: hidden`, opacity 0, clipped by `clip` or `clip-path`, or the visually hidden classes).
    - **No false all-clear:** a run, boundary or backdrop that the scan cannot measure (a background image or gradient in its stack, or a colour it cannot parse) is an `unmeasured` finding. It is never skipped.
  - **Links.** For every `a[href]`:
    - a fragment `#name` must name an element id that exists;
    - `#/…` and `#!…` are hash routes, the page's own addresses, and pass;
    - an empty `href` and `javascript:` are findings.

    This is DW-178's rule.
- **DW-89: the scrollers are tab stops with names.**
  - The chat list (`.list`) gets `tabindex="0"`, `role="region"` and `aria-labelledby="chat-title"`. `MainPage`'s hidden h2 "Chat" gets `id="chat-title"`.
  - The rail gets `[attr.tabindex]="layout.stacked() ? -1 : 0"`. It is a tab stop while it scrolls on its own, and stays the skip link's focus target when stacked.
  - Both draw their ring inside their edge. The inside-ring declarations move from `main-page.ts` and `banner-stack.ts` into `web/src/styles/base.css` as the class `.ring-inside:focus-visible`, which `section.rail`, `main.main`, the list and the banner (`.banner`) carry.
  - The names are the existing headings "Chat" and "Status".
- **The clipped ring in Firefox.** `web/src/app/shared/reveal-ring.ts` (new, framework-free) exports `revealRing(scroller, target)`.
  - It acts when the target is inside the scroller and is not the scroller itself.
  - When the target's box, grown by the scroller's own computed `scroll-padding` (the 4px gutter, the ring's reach), passes the scroller's client box at the top or the bottom, it changes only that scroller's `scrollTop` by the overflow.
  - It never scrolls smoothly, the page or another scroller.
  - `(focusin)` on `section.rail` (`MainPage`) and on the list (`ChatPanel`) calls it.
  - In Chromium and WebKit the box is already inside, so it does nothing there (Task 0).
- **DW-145: the Visual Trace button closes its own menu.** In `Popovers`, a press that starts on the trigger (`pointerdown` on it) counts as inside the popover until the press ends.
  - The focus-leave check does not close the popover for focus that the press took away, so the trigger's click toggles it closed.
  - A press that ends without a click on the trigger (`pointerup` or `pointercancel` elsewhere) runs the focus-leave check again. It runs once the press's click would have run (a task after `pointerup`), so that a press that ends on the trigger is still the click's to toggle.
  - Esc, a press outside and Tab out are unchanged.
- **DW-179: every floor case removes its turns.** A1, A5, A7 and P4 add `turnRows(seeded)` to the refs that `cleanFixtureRows` removes in `finally`. `floor-fixtures.test.mjs` lists `floor/announcements.spec.ts` and `floor/focus.spec.ts`.
- **The string test** (`web/scripts/ux-strings.test.mjs`, new).
  - **The inventory** is collected in three ways, and each named extraction must match:
    - imported, as `trace-view.test.mjs:12-14` imports a module: `CHAT_TEXTS`, `NOTICE_TEXTS`, `DECISION_TEXTS`, `RAIL_TEXTS`, `TRACE_TEXTS`, `BANNER_TEXTS`, `LAYOUT_TEXTS`, `NEW_UPDATES`, `WHEN_TEXTS` and the catalog's `PAGE_TEXTS`;
    - read from the source text (`code()` of `source-files.mjs`): `BUSY_NOTICE`, `LOAD_FAILED`, the texts of `SKIP_LINKS`, About's `ABOUT_CLOSE_NAME`, the header's theme labels, its `Theme: ` prefix, "Online demo", "Demo mode" and "Account";
    - every literal text run and every literal `aria-label`, `title`, `placeholder` and `alt` value of every component template under `web/src/app/`. Today these are in the header, the main page and About. A text node's whitespace collapses to one space, and an interpolation inside it becomes a `{slot}` (About's "Default model: {slot}.").
  - **The sources.** A `SOURCES` table gives each inventory string one source:
    - `ux`: `EXPERIENCE.md` holds it verbatim. In a template, each `{slot}` matches a non-empty run on one line.
    - `design`: the same check, in `DESIGN.md`.
    - `ac: '<story>'`: a story's acceptance criteria in `epics.md` or the PRD state it, for example "Decision message", "Agent steps", "Repair and resend" and "Open Visual Trace". It is written out with the story and not read, because those files are bookkeeping paths that never run the web job (`ci/units.sh` `BOOKKEEPING_PATTERN`). The two UX documents are web inputs.
    - `ruled: '<story and ruling>'`: text the UX does not write, written out exactly. Examples are the banner Close names and "Available after your first message." (Story 2.14's ruling, `cycle-log-epic-2.md` 2026-10-24T16:21:41Z), and "Close narrow-window note" and the Status count (Story 2.15's ruling, 2026-10-24T22:15:51Z).
    - `calendar`: the English weekday and month names, written out.
    - `format`: a template that, with its slots removed, holds only punctuation, digits, the separator and the unit words `s`, `min`, `h`, `in`, `at`, `hour`, `hours`, `minute`, `minutes`, `second` and `seconds`. This is checked mechanically (examples: `{label} ({n})`, `in {n} s`, `{day} at {time}`).
  - **A string with no source.** A string that neither UX document holds, that no story's criteria state, that no ruling in `cycle-log-epic-2.md` covers, and that is neither `calendar` nor `format`, is public text nobody ruled. It is never given an invented source. The implement stage escalates it (veto window: public text).
  - **These fail:** an inventory string with no entry, an entry that matches no inventory string, and a document that does not hold its entry's string.
  - **The ellipsis.**
    - No inventory string holds "...".
    - A string that holds U+2026 holds it once, is `ux`, and appears with U+2026 in `EXPERIENCE.md`.
    - "Deciding…", "Working…" and "Reconnecting… New messages may be delayed." are asserted by name, written with the escape `\u2026`.
    - The only non-ASCII characters allowed are U+2026 and U+00B7.
- **CI.**
  - **`ci/units.sh`** (Lane B's entries only):
    - a new `FIREFOX_WEBKIT_UNITS="floor"`, with a comment;
    - `browser` is `live:demo-path live:sign-in`;
    - `install-fresh` is `live:install-start live:bundle-folder`;
    - `shards` is `shard:lane-a live:floor`;
    - `image` is `live:storage-roundtrip live:build-inputs live:compose-start shard:lane-b`;
    - `BROWSER_UNITS` is unchanged.
  - **`ci/iris.sh` `cmd_live`** runs `npx --prefix web playwright install firefox webkit || exit 1` for a name in `FIREFOX_WEBKIT_UNITS`, after the Chromium install. The usage text says so.
  - **`docker/tests/test-floor.sh`:**
    - its header names the subset and U1 to U3 and E1 to E3;
    - its PASS and FAIL line names the engines;
    - its missing-browser hint reads `npx --prefix web playwright install chromium firefox webkit`;
    - a log line holding `Host system is missing dependencies` prints the hint `npx -y playwright@1.64.1 install-deps firefox webkit (as root)`;
    - its "Needs" line names the three browsers.
  - **`docker/tests/test-demo-path-gate.sh`:**
    - the browser group's checks expect its two units;
    - `ci/iris.sh live bundle-folder` in the scratch tree installs no browser;
    - `ci/iris.sh live floor` installs Chromium, then Firefox and WebKit, before its script;
    - every name of `FIREFOX_WEBKIT_UNITS` is in `BROWSER_UNITS`.

**Never:**
- **No new dependency:**
  - no axe-core (MPL-2.0);
  - no Playwright container image;
  - no `package.json` entry;
  - no host, sudo or runner-config step: the Contest Planner installs the hosts' packages.
- **No contended path is edited:**
  - `.github/workflows/*.yml`, `docs/**`, `.gitattributes` and `install.sh`;
  - `docker/tests/test-boundaries.sh`, `test-ci-config.sh` and `test-install-script*.sh`;
  - `src/bridge/**` and `src/ocutalon/cls/OcuTalon/Install/**`;
  - Lane A's entries of `ci/units.sh`: `shard_areas lane-a` and `shard:lane-a`'s place stay as they are.
- **No server change:** no ObjectScript, route, payload, event, stored data, role or grant.
- **No public text.** The two names are existing headings, and nothing is added to a `*_TEXTS` constant or the catalog.
- **No new noise:** no `.focus(` call, live region, smooth scroll, keyboard handler or `tabindex` above 0.
- **Tests:**
  - no case in `live:sign-in`;
  - no real Visual Trace tab in Firefox or WebKit (DW-146);
  - no floor case stops IRIS, holds a poll for 8 s or longer, or lets a chat post reach the server.
- **Not this story:**
  - the full floor in Firefox and WebKit, and the stacked layout's cases (G4 to G7) there;
  - WebKit's mouse press on the Status button or on the note's Close, which leaves focus on the body;
  - DW-159 (screen readers), DW-81 and DW-74.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Three engines | `ci/iris.sh live floor` on a throwaway | Chromium passes every floor case, then Firefox and WebKit pass every `@browsers` case, on the one stack | A browser that is not installed, or whose host packages are missing, fails the unit, and it prints the install hint |
| Step key | WebKit (macOS) | `stepKeys` gives `Alt+Tab`, and the walk reaches every link and button | Neither key reaches the link: the case throws, naming the engine |
| Scan, page | The full page at 1280×720 and 1280×600, light and dark, in each engine | No finding | — |
| Scan, overlays | Visual Trace open, the account menu open, About open, and the failed load with Retry and its busy notice; 1280×720, light and dark | No finding | — |
| Scan, self-test | Planted: an icon-only button with no name, text at about 2.8:1, `<a href="#nowhere">`, an input whose border is about 1.4:1, and text on a background image | Exactly these five findings, by rule; the plant is removed | — |
| Skip links (DW-178) | `href="#/"` on both | The links rule passes | `#nowhere` is a finding (U3) |
| Visual Trace (DW-145) | Menu open, then a press on its button (down, 150 ms, up), plain and Safari-like | The menu closes, focus is on the button, `aria-expanded` is false, and the next press opens it | Safari-like press released over the chat list: the menu closes, and no pane is left open |
| Scrollers (DW-89) | The scrolling page at 1280×720, a walk with the step key | The stops include region "Chat" and region "Status", each with its inside ring. With one focused, End and PageDown scroll it and focus stays | At 1000×800 the rail has `tabindex="-1"`, and Skip to status still focuses it |
| Clipped ring | Firefox, a control partly past the rail's or the list's bottom, reached by Tab | The scroller moves so that the whole ring is inside it (K4, G1) | The scroller itself, focused: no scroll |
| IME (Safari order) | `compositionstart`, `compositionend`, then keydown Enter with `keyCode` 229 and `isComposing` false; then Enter with `isComposing` true | No post, and the text stays | — |
| Strings | A string missing from its source, "...", or new template text with no entry | The string test fails, naming the string | — |
| Turns (DW-179) | A1, A5, A7 and P4 run | Each removes the turns it seeded | — |

</intent-contract>

## Code Map

**Page (Lane B)**
- `web/src/app/shared/popover.ts`:
  - `show()` `:73-123`: the trigger's press listener and its cleanup sit beside the escape and outside subscriptions (`:100-113`);
  - `closeOnFocusLeave()` `:161-181`: the check skips a press that started on the trigger, and runs again when the press ends.
- `web/src/app/shared/reveal-ring.ts` (new): `revealRing`, with a module doc as `trace-view.ts:1-10` has.
- `web/src/app/chat/chat-panel.ts`:
  - the template's list `:94` gains `tabindex`, `role`, `aria-labelledby`, `class="list ring-inside"` and `(focusin)`;
  - the class doc `:58-84` (scrolling and focus).
- `web/src/app/main-page/main-page.ts`:
  - `section.rail` `:61-71`: `[attr.tabindex]`, the class `ring-inside` and `(focusin)`;
  - `main.main` `:91-98`: the class `ring-inside`;
  - the h2 "Chat" `:99`: `id="chat-title"`;
  - the inside-ring rule `:144-149` is deleted;
  - the class doc `:24-47`: "take focus (tabindex -1) but are not tab stops" becomes true of main only.
- `web/src/app/banners/banner-stack.ts:133-136`: `.banner:focus-visible`'s inside-ring declarations move to the class, which the banner element carries.
- `web/src/styles/base.css:104-109`: the class `.ring-inside:focus-visible` (`outline-offset: -2px; box-shadow: inset 0 0 0 4px var(--surface)`) follows the global ring.
- Read only:
  - `web/src/app/header/skip-links.ts:15-26` (`href="#/"`, unchanged);
  - `web/src/app/header/header.ts:35-40,360-378` (the theme labels, the badge texts, the account fallback and the `Theme: ` prefix, for the string test);
  - `web/src/app/about/about-dialog.ts:12` (`ABOUT_CLOSE_NAME`, for the string test);
  - `web/src/app/shared/server-button.ts:10`, `web/src/app/live/live-state.ts:29` and `web/src/app/msg/catalog.ts`;
  - the `*_TEXTS` modules (`chat/chat-view.ts:29,67`, `chat/decision-view.ts:18`, `rail/rail-view.ts:24`, `shared/trace-view.ts:14`, `banners/banner-view.ts:85`, `shared/layout-view.ts:26`, `shared/announce-queue.ts:29` and `chat/page-time.ts:82`);
  - `web/src/app/chat/composer.ts:76-80` (the IME guard, unchanged).

**Tests (Lane B)**
- `web/playwright.config.ts:34-41` and its doc `:3-12`: the two projects.
- `web/package.json:16`: `e2e:floor`.
- `web/scripts/playwright-projects.test.mjs`: a new describe.
  - `e2e:floor` lists every floor test for `floor`, and the same `@browsers` titles for `floor-firefox` and `floor-webkit` (`spec.tests[].projectName`), K1, K4, G1, P2, A1, U1 to U3 and E1 to E3 among them.
  - `e2e` still lists nothing under `floor/`.
- `web/scripts/floor-fixtures.test.mjs:32-41`: the file list gains `floor/announcements.spec.ts` and `floor/focus.spec.ts`.
- `web/scripts/ux-strings.test.mjs` (new).
- `web/e2e/support/floor.ts`:
  - `readFocus` `:174-212` gains `inside`;
  - `expectRing` `:224`;
  - new: `stepKeys`, `INSIDE_RING`, `expectInsideRing` and `expectStopRing`;
  - the header doc `:19-30`.
- `web/e2e/support/scan.ts` (new). Its contrast core follows Task 0's prototype (Design Notes).
- `web/e2e/floor/keyboard.spec.ts`:
  - `expectInsideRing` `:57-66` moves to `support/floor.ts`;
  - K1 `:75`, K2 `:166` and K4 `:358-449` are tagged, with the step key in K1 and K4 and `expectStopRing` in K4;
  - `expectNamed` `:452-461` moves to the scan, and K5 `:463` calls it.
- `web/e2e/floor/layout.spec.ts`: `walk()` `:113-133` (the step key and `expectStopRing`); G1 `:135` tagged.
- `web/e2e/floor/focus.spec.ts`: P2 `:91` tagged; P4 `:149-216` with `turnRows`.
- `web/e2e/floor/announcements.spec.ts`: A1 `:123-155` tagged and with `turnRows`; A5 `:227-249` and A7 `:299-355` with `turnRows`.
- `web/e2e/floor/scan.spec.ts` (new): U1 to U3.
- `web/e2e/floor/browsers.spec.ts` (new): E1 to E3.
- Helpers to use:
  - `support/floor.ts`: `seedFullPage` `:108`, `addReminder` `:130`, `addResetSoon` `:138`, `clearFullPage` `:144`, `seedScrollingPage` `:237` and `openFloor` `:76`;
  - `support/api.ts` `holdState` `:114`;
  - `support/page.ts` `tokenColor` `:17`;
  - `web/e2e/chat/chat.spec.ts:296-301` (C3's IME events) is the pattern for E3.

**CI (Lane B)**
- `ci/units.sh:28-41`: the group entries and `FIREFOX_WEBKIT_UNITS`.
- `ci/iris.sh:16` and `:325-337` (`cmd_live`). This is the footprint extension.
- `docker/tests/test-floor.sh`: header `:1-28` (its "Needs" line `:27-28`), the hint `:87-89` and the PASS and FAIL lines `:84,90`.
- `docker/tests/test-demo-path-gate.sh`: header `:17-21`; stubs `:82-84`; the group checks `:336-370`, with the new `live` runs beside them (`run_group` `:189-198` is the pattern).
- Read only:
  - `docker/tests/test-ci-config.sh:1335-1344`: its recipe stub fails at the first `npx` call, so it still sees `install chromium` first for every browser unit;
  - `docker/tests/test-ci-config.sh:825` (`install-fresh` holds `live:install-start`).

## Tasks & Acceptance

**Execution:**
- **Task 0 (done at plan, 2026-10-24; nothing kept).**
  - **Throwaway tag `e2s216p`.** The full floor suite (37 cases) ran in Firefox, then in WebKit, through temporary projects. Firefox passed 34 cases in 92 s; WebKit passed 29 in 143 s, of which about 60 s were 10 s timeouts. A scratch spec then measured the walks, the Visual Trace toggle and a scan prototype in all three engines.
  - **macOS static probes:**
    - `page.evaluate` and init scripts run under `script-src 'self'` in all three engines;
    - the Tab key, focus on a press, and keyboard scrolling were measured (Design Notes).
  - **Restoring the tree.** The files were restored from backup (`shasum` matched, `git status` clean), and teardown left nothing.
- `web/src/app/shared/popover.ts` -- DW-145: a press that starts on the trigger counts as inside until it ends -- the toggle works without focus on the button.
- `web/src/app/shared/reveal-ring.ts` -- `revealRing` -- Firefox's clipped ring at a scroller's edge.
- `web/src/styles/base.css`, `web/src/app/main-page/main-page.ts`, `web/src/app/banners/banner-stack.ts` and `web/src/app/chat/chat-panel.ts` -- the `ring-inside` class (Rule 2); the scrollers' tab stops, names and `(focusin)`; `chat-title`; the rail's tabindex binding; class docs -- DW-89.
- `web/e2e/support/floor.ts` -- `stepKeys`, `INSIDE_RING`, `inside`, `expectInsideRing` (moved) and `expectStopRing`; doc.
- `web/e2e/support/scan.ts` -- `scanPage` and its three rules, each exemption with its reason in a comment; a header that states what it pins and needs.
- `web/e2e/floor/keyboard.spec.ts`, `layout.spec.ts`, `focus.spec.ts` and `announcements.spec.ts` -- the tags, the step key and `expectStopRing` in the walks, K5 on the moved names rule, and `turnRows` in A1, A5, A7 and P4 (DW-179). Each file header says which of its cases run in every engine.
- `web/e2e/floor/scan.spec.ts` (new), U1 to U3, all `@browsers`, one header:
  - **U1:** `seedFullPage` plus `addReminder` and `addResetSoon`. At 1280×720 and 1280×600, each with `emulateMedia` light and then dark, `scanPage` finds nothing (4 scans).
  - **U2:** at 1280×720, light and dark, nothing is found:
    - with Visual Trace open;
    - with the account menu open;
    - with About open;
    - on a load whose `/state` answers 500, after a Retry that fails, so the load error, Retry and its busy notice show.
  - **U3:** the planted fragment of the matrix, built with DOM and CSSOM calls in `page.evaluate`, gives exactly its five findings. The fragment is removed in `finally`.
- `web/e2e/floor/browsers.spec.ts` (new), E1 to E3, all `@browsers`, one header:
  - **E1 (DW-145):** the matrix row. The Safari-like press is a one-time capture `mousedown` on the button that prevents the default and blurs the active element, which is what Safari and macOS Firefox do. The press is `mouse.down()`, 150 ms, `mouse.up()`.
  - **E2 (DW-89):** the matrix row, on `seedScrollingPage`. Its rows are removed in `finally`.
  - **E3:** the IME row. The `keyCode` 229 keydown is built in `page.evaluate` as a `KeyboardEvent` with `keyCode` defined on the event, because whether `KeyboardEventInit` takes `keyCode` differs between engines (inference). Posts to `**/api/v1/messages` are routed and aborted, and counted (0).
- `web/playwright.config.ts` and `web/package.json` -- the two projects and `e2e:floor`; the config doc names five projects. `web/scripts/playwright-projects.test.mjs` -- the listing assertions.
- `web/scripts/floor-fixtures.test.mjs` -- the two files (DW-179).
- `web/scripts/ux-strings.test.mjs` -- the inventory, `SOURCES`, the three failure kinds, the ellipsis assertions and the non-ASCII rule. A header says what it pins.
- `ci/units.sh` and `ci/iris.sh` -- the entries and the install (the footprint extension).
- `docker/tests/test-floor.sh` and `docker/tests/test-demo-path-gate.sh` -- as Boundaries say.
- **Sweep.**
  - Search `web/e2e/` for `press('Tab')`, `press('Shift+Tab')`, `expectNamed`, `expectInsideRing`, `section.rail`, `.list` and `tabindex`, and confirm or update each reader. F1's `[tabindex]` check, `decision.spec.ts:262`, `chat.spec.ts:660`, `banners.spec.ts:582-586` and `frame.spec.ts:147-149,390-441` stay green as they are.
  - Search `web/src/app/` for string literals that the page shows outside the inventory, and add each one found.

**Acceptance Criteria:**
- **Three engines (FR-12, NFR-25).**
  - **Given** the CI demo-path environment (a throwaway stack from `ci/iris.sh`),
  - **when** `live:floor` runs,
  - **then:**
    - Playwright runs the main page in Chromium (every floor case) and in Firefox and WebKit (the `@browsers` cases) at 1280×720 (K4, U1, U2) and 1280×600 (G1, U1);
    - every case passes;
    - Firefox and WebKit are installed by the unit's own recipe.

  Tests: the floor unit, and `playwright-projects.test.mjs`.
- **The scan (NFR-25, UX-DR8).**
  - **Given** the full page, its overlays and the failed load,
  - **when** `scanPage` runs in each engine, light and dark,
  - **then** it finds no unlabelled control, no contrast failure and no link that points at nothing;
  - **and** a planted fault of each kind, and an unmeasurable backdrop, are reported.

  Tests: U1, U2, U3.
- **The strings (UX-DR117, UX-DR138).**
  - **Given** every fixed string that the page can show,
  - **when** `node --test web/scripts/` runs,
  - **then** each string is found in its source, the UX first, and "Deciding…", "Working…" and "Reconnecting…" carry the single "…".

  Test: `ux-strings.test.mjs`.
- **DW-89.**
  - **Given** the chat list and the rail, scrolling on their own,
  - **when** a keyboard user walks the page in any engine,
  - **then** each is a tab stop named by its heading, with its ring inside, and keys scroll it.

  Test: E2 (WebKit's run is the one that checks it), and K4 and G1.
- **DW-145.**
  - **Given** the Visual Trace menu is open,
  - **when** its button is pressed in any engine, with or without Safari's no-focus press,
  - **then** the menu closes and focus is on the button.

  Test: E1.
- **DW-178.**
  - **Given** the skip links,
  - **when** the scan runs in every engine,
  - **then** no link points at nothing.

  Tests: U1 and U3.
- **DW-179.**
  - **Given** the floor unit's three projects on one stack,
  - **when** A1, A5, A7 and P4 end,
  - **then** their turns are gone.

  Tests: `floor-fixtures.test.mjs`, and K4's bounded walk in Firefox and WebKit.
- **Integration (Rule 1).**
  - **Given** the real page on a real stack,
  - **when** the floor unit runs,
  - **then:**
    - `MainPage` and `ChatPanel` call `revealRing`, so in Firefox a ring at a scroller's edge ends inside it (K4, G1);
    - U-cases and K5 read `support/scan.ts`;
    - K1, K4, G1, G5 and E2 read `stepKeys`.
- **CI (REL-4).**
  - **Given** the new grouping,
  - **when** `test-demo-path-gate.sh` runs,
  - **then** it pins the browser group's two units, no install before `live bundle-folder`, and the Firefox and WebKit install before `live floor`;
  - **and** the figures under Verification hold 35 minutes and 1.25 times the mean, as estimates that the first CI run measures.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs and conventions (Rule 6).**
- **AD-13:** the CSP `script-src 'self'` and text as text are unchanged. The scan reads the page through Playwright, whose `evaluate` and init scripts were measured to run under that CSP in all three engines. U3 plants DOM through `page.evaluate`, never through markup.
- **AD-22:** Playwright specs run on throwaway stacks, `ci/iris.sh` is the one recipe and `ci/units.sh` the one list. There are still six groups, and `live:demo-path` is still first in `browser`.
- **AD-29:** Lane B's files, and Lane B's own entries of `ci/units.sh`.
- **Convention "Tests":** "the accessibility floor's browser specs (`web/e2e/floor/`) run only in their own unit `live:floor`". They still do, because the added engines run inside that unit. A second unit would need this row amended.
- **Convention "Announcements and focus":** no `.focus(` call is added, and `revealRing` only scrolls.
- **Stack:** Playwright 1.64.x is unchanged, and no package is added.

No AC contradicts an AD's Rule. **Rule 5:** every criterion is measurable as planned: the sizes, the themes, the WCAG formula and the inventory.

**Task 0 findings** (macOS, Playwright 1.64.1: Chromium 156.0.8078.4, Firefox 157.0, WebKit 27.2).
- **The Tab key.** Chromium's and Firefox's Tab reaches links, buttons and a scroller that has no tab stop. WebKit's Tab reaches only form fields and `tabindex="0"` elements. WebKit's `Alt+Tab` reaches links and buttons, but still not a scroller without `tabindex` (DW-89). Firefox's `Alt+Tab` focuses nothing.
- **A press on a button.** Chromium and Playwright's Firefox focus the pressed button. WebKit moves focus to the body (`relatedTarget` null). So a plain press reproduces DW-145 in WebKit, and only the Safari-like press reproduces it in Firefox. In Chromium a Safari-like press made with `click()` still closed the menu: the release probably comes before the focus-leave check's task (inference). That is why E1 presses with a 150 ms gap.
- **The walks** (12 rail rows and 8 turns):
  - Chromium has no clipped stop at 1280×720 or 1280×600.
  - WebKit with `Alt+Tab` has none either, in 41 stops.
  - Firefox clips:
    - the chat list itself (a scroller stop whose outward ring passes the window's right edge);
    - at 1280×600, a rail button, a Trace link and "Decision details", each partly past its scroller's bottom.

    A focus-in reveal removed all three of the edge clips. DW-89's inside ring removes the first.
- **Keyboard scrolling** of a focused `tabindex="0"` scroller: End and PageDown scroll it in all three engines. ArrowDown did not move WebKit within 150 ms.
- **Colours.** Computed colours and `::placeholder` read as `rgb()` in all three engines. The prototype scan found no unnamed control and no text contrast failure on the full page at both sizes and themes in any engine: 57 runs, none unmeasured.
- **Time.** Most floor cases take the same time in each engine (Firefox 92 s and WebKit about 85 s for the 37 cases).
- **Also found** (not floor): G2's and G6's click steps fail in WebKit, because Safari focuses no pressed button. A mouse press on the Status button or on the note's Close leaves focus on the body. Story 2.15's Decided 3, which held this by inference, is false. Keyboard use is unaffected.

**Decided in-stage** (small, reversible, within the intent):
1. **A lean subset in Firefox and WebKit, and the full floor in Chromium** (the epic context's suggestion). The subset covers each floor promise once: skip links, Esc layers, ring walks at both sizes, the focus rule, an announcement, the scan, the toggle, the scrollers and the IME guard. It adds about 95 s locally instead of about 180 s for the full suite.
2. **One unit, one stack.** This keeps the Tests convention and saves a stack start of about 3 minutes per run in CI. DW-179 is what makes the shared stack safe for K4's bounded walk.
3. **The rebalance.** `live:bundle-folder` moves from `browser` to `install-fresh`, and `shard:lane-b` from `shards` to `image`. Both are Lane B entries; the figures are under Verification.
   - Without the moves, `shards` reaches about 1.31 times the mean and `browser` stays at about 1.49.
   - The other placements that were tried each break 1.25: `live:floor` in `image` alone gives 1.30, and moving only `bundle-folder` leaves `shards` at 1.31.
   - `production` takes no unit, because it is the only group that skips on a web-only push.
4. **The step key is detected, not named,** because Linux WebKit is unmeasured.
5. **DW-145's fix** keeps a press on the trigger inside, instead of preventing the press's default. Preventing the default would hide the bug from E1's Safari-like press and change how a press works.
6. **DW-178.** `href="#/"` stays. It is a hash route, so a middle-click opens the same page, whereas a fragment `#id` would navigate the hash router. axe-core's skip-link rule draws the same line (`/^#[^/!]/`, from its source, read on the web, not measured). The scan's links rule passing in every engine settles the entry.
7. **DW-89.**
   - The list is a region named by the existing "Chat" heading, so no text is added.
   - The rail is a tab stop only while it scrolls on its own; when stacked it does not scroll.
   - The inside-ring rule becomes one class in place of three copies (Rule 2).
8. **The reveal** changes only the scroller's `scrollTop`. `scrollIntoView` would also scroll the page and undo the focus rule's `preventScroll`.
9. **The scan's limits.**
   - It treats unmeasured as a failure.
   - It checks only the boundaries that DESIGN lists.
   - The ring check is the halo plus the backdrop. The halo always sits between the control and the ring, and DESIGN's ratios are 5.1 and up.
   - Story 2.14's residual (a banner's inset halo inside its accent) is now measured by the ring rule. It reopens only if U1 flags it.
10. **The string test's model:** `ux` is a verbatim match in `EXPERIENCE.md`. A string the UX lacks names its other source or its ruling, so every string's provenance is written once and checked.
11. **Ids:** U (the scan) and E (engines), because S is taken in `web/e2e/`.
12. **No split.** It is one criterion and four ledger bullets. About 25 files change, each by a little, and nothing on the server.

**Veto-window items:** none. No public text is added: the two new names are the headings "Chat" and "Status".

**For the lead (your calls).**
- **The CI hosts.** Confirmed: `@playwright/test`, `playwright` and `playwright-core` are 1.64.1 in `web/package.json` and `web/package-lock.json`.
  - The only CI unit that needs Firefox and WebKit is `live:floor`, in `shards`.
  - Before the first push of this story's code, run `npx -y playwright@1.64.1 install-deps firefox webkit` with root rights (for example under `sudo`) on `ocutalon-ci-b` and `ocutalon-ci-c`.
  - The job then fetches the browsers itself (`npx --prefix web playwright install firefox webkit`, about 170 MB, once per host user).
  - Without the packages, `live:floor` fails with Playwright's "Host system is missing dependencies", and the unit prints that command.
- **Footprint extension:** `ci/iris.sh`. Also shared but in the footprint: `web/src/styles/base.css` and `docker/tests/test-demo-path-gate.sh`.
- **The rebalance** (Decided 3) is yours to keep or to drop. Dropping it leaves `browser` over 1.25, as it was before this story.
- **Rule 21's Groups bullet** in `_bmad/custom/skill-rules.md` is stale: it lists `browser` with `bundle-folder` and `shards` without `floor`. Appending a measured line is yours.
- **Licences.** Firefox (MPL-2.0) and WebKit (LGPL-2.1 and BSD) are the browsers the AC names. The pinned Playwright (Apache-2.0) downloads its own builds into the user cache at test time. Nothing is vendored, added to `package.json`, shipped or committed, so no Stack row is planned. Confirm.
- **Task 0's WebKit mouse-focus finding** (G2, G6) is for you to record. The recommendation is `wontfix-accepted`, `reopen_if=` a Safari mouse user loses their place after closing the drawer.
- **Linux.** The Linux Firefox and WebKit behaviours (the Tab key, focus on a press, the edge reveal) are unmeasured until the first CI run (inference). The cases are written to hold either way: the step key is detected, and E1 forces Safari's press.
- **DW-55:** `browser` stays over 10 minutes (about 780 s, an estimate), the existing CI-capacity item.

**Ledger (Rule 17).** None is declined.
- DW-89: E2, and K4 and G1.
- DW-145: E1.
- DW-178: U1 and U3, the links rule.
- DW-179: A1, A5, A7 and P4, and the `floor-fixtures` ratchet.

**Integration ACs (Rule 1).** The shared pieces and their consumers:
- `revealRing`: `MainPage` and `ChatPanel` (K4 and G1 in Firefox).
- `support/scan.ts`: U1 to U3 and K5.
- `stepKeys` and `expectStopRing`: K1, K4, G1, G5 and E2.
- The `ring-inside` class: the rail, main, the list and the banners (K1, K4 and E2).

**Consumed-by:**
- Every later page story: a new floor case may join `@browsers`, the scan runs over its surfaces, and its fixed strings join the string test's inventory with a source.
- Story 4.5: "Skip to simulated devices" joins `SKIP_LINKS` and the inventory.
- Stories 4.4, 6.2 and 12.3: their surfaces meet U1's scan.

**Consumes:**
- 2.1: `Popovers`, the header and About.
- 2.5: the chat panel and the composer's IME guard.
- 2.8: the rail.
- 2.10 and 2.11: the banners.
- 2.12: the A and P cases, and `Announcer`.
- 2.13: `TRACE_TEXTS`.
- 2.14: the skip links, the K cases and their helpers, and the ratchets.
- 2.15: `LAYOUT_TEXTS`, `Layout.stacked` and the G cases.

**Extend, don't copy (Rule 2).**
- `stepKeys` and `expectStopRing` extend `support/floor.ts`'s ring helpers.
- The names rule is K5's `expectNamed`, moved and extended.
- `ring-inside` replaces the copies in `main-page.ts` and `banner-stack.ts`.
- E3 repeats C3's two IME events in Safari's order, in every engine. That is a different event order run where C3 does not run, so it is not a copy.

## Verification

**IRIS.** This story changes no ObjectScript. If a stage makes a call:
- name `server: ocutalon-slot-b` and `namespace: OCUTALON`;
- make `iris_server_info` (build 154) the first call;
- make one `iris_execute_tests` call per message.

**Throwaway commands** are `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_RUN_TAG=e2s216i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`.
- `<main checkout>` is typed only at the prompt, never in a tracked file.
- Run one piece per call with `timeout: 600000`, and end with `teardown` on the same tag.
- `LOCK busy` (exit 75) means wait 30 to 90 s and retry.
- QA uses `e2s216q` (stage `qa`), and review uses `e2s216r` (stage `review`).
- Install the engines once on the machine: `npx --prefix web playwright install firefox webkit` (8 s measured).

**Commands:**
- **(loop)** Each in its own call: `npm --prefix web test`, `npm --prefix web run lint`, `node web/scripts/catalog.mjs --check`, `bash docker/tests/test-web-build.sh`, `bash docker/tests/test-boundaries.sh` and `bash docker/tests/test-demo-path-gate.sh`. Expected: exit 0, with `ux-strings.test.mjs`, `playwright-projects.test.mjs`, `floor-fixtures.test.mjs`, `floor-sources.test.mjs` and `announce-focus-sources.test.mjs` passing.
- **(loop)** Throwaway, one piece per call: `build`; `live floor`; `teardown`. Expected:
  - every floor case passes in `floor`, and every `@browsers` case in `floor-firefox` and `floor-webkit`;
  - teardown leaves nothing.
  - **Time:** about 280 s locally (inference: 160 s today, plus about 20 s for U and E in Chromium, plus about 95 s for the two engines). The 540 s deadline holds. Record the figure.
- **(once)** In their own calls: `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-ci-changes.sh` and `bash ci/checks.sh`. Expected: exit 0, with no edit to the first.
- **(once)** Throwaway, one piece per call: `build`; `group install-fresh`; `group image`; `group shards`; `live sign-in`; `live demo-path`; `teardown`. Expected:
  - every unit passes;
  - `live sign-in` passes 190 with 2 skipped, unchanged;
  - record each group's time.

**CI figures (estimates; Rule 21's budget).**
- **The base** is run 40151813813 (Story 2.15, `8abe0c5`; production skipped, so production's 490 s is from run 40135456843). In seconds:
  - `install-fresh` 515 (`install-start` 491);
  - `install-upgrade` 650;
  - `production` 490;
  - `browser` 968 (`demo-path` 180, `sign-in` 577, `bundle-folder` 188);
  - `shards` 703 (`lane-a` 174, `lane-b` 225, `floor` 281 with 37 cases and 1.9 min of Playwright);
  - `image` 420.
- **Story 2.16 adds about 156 s to `live:floor`:**
  - about 26 s for U and E in Chromium;
  - about 120 s for the subset in two engines (Task 0's local 95 s at 1.25, CI's Playwright ratio in this run);
  - about 10 s for the installs, with about 30 s once per host for the first download.
- **After the rebalance:**

  | Group | Seconds |
  | --- | --- |
  | `install-fresh` | 703 |
  | `install-upgrade` | 650 |
  | `production` | 490 |
  | `browser` | 780 |
  | `shards` | 634 |
  | `image` | 645 |

  The mean is 650, and the longest is `browser` at 1.20 times it. On a web-only push, with production skipped, the mean is 682 and the longest is 1.14 times it.
- **Wall-clock** is about 13 minutes for one run alone, and about 26 minutes in the worst case with three epics' runs queued on 12 services (inference). Both are inside REL-4's 35 minutes.
- Without the moves, `shards` is 1.31 and `browser` 1.49 times the mean.
- Host placement (ci-c up to about 1.4 to 1.9 times ci-b) is not modelled.
- Measure at this story's first CI run.

**Planned mutations (Rule 19).** For each: apply it, observe red, restore a byte-identical tree (`git status --short` and the hash of `git diff` unchanged), and record `mutation: ... -> ...` below.

| AC | Mutation | Expected red |
| --- | --- | --- |
| Engines | `stepKeys` always `Tab` | K1 and K4 in `floor-webkit` |
| Engines | `floor-firefox` dropped from `e2e:floor` | `playwright-projects.test.mjs` |
| Scan | the reset banner's Close loses its name binding | U1 in every engine; K5 |
| Scan | a rail meta text coloured `#B0B0B0` | U1 (contrast, light) |
| Scan | the unmeasured branch returns "pass" | U3 |
| Strings | `CHAT_TEXTS.deciding` written `'Deciding...'` | `ux-strings.test.mjs` |
| Strings | a literal `<span>Hello</span>` in `main-page.ts`'s template | `ux-strings.test.mjs` (no entry) |
| DW-89 | the list without `tabindex` | E2 in every engine |
| DW-89 | the rail back to `tabindex="-1"` | E2 |
| DW-145 | the focus-leave check ignores the press | E1 in every engine |
| DW-145 | the press flag never cleared without a click | E1 (released over the list) |
| DW-178 | Skip to chat's `href` set to `#nowhere` | U1 (links) |
| Reveal | the list's `(focusin)` removed | G1 in `floor-firefox` |
| DW-179 | A1 without `turnRows` | `floor-fixtures.test.mjs` |
| CI | `FIREFOX_WEBKIT_UNITS` empty | `test-demo-path-gate.sh` |
| IME | the composer guard without `keyCode === 229` | E3 in every engine; C3 |

**Shared surfaces:**
- **The tab order:** region "Chat" in every band, and region "Status" in the framed bands. K1, K4, G1, G5 and E2 walk it, and the other Tab readers are listed in the Sweep.
- **`section.rail`'s `tabindex`:** F1 allows only -1 and 0.
- **The inside-ring rule** moves to `base.css`. K1, K4 and E2 read its computed values, which are unchanged.
- **`Popovers`' focus-leave rule:** the trace links' Shift+Tab-out case, K2 and G3 stay green.
- **`ci/units.sh`'s groups and `FIREFOX_WEBKIT_UNITS`:** `test-demo-path-gate.sh` is updated; `test-ci-config.sh` and `test-ci-changes.sh` pin no member that moves.
- **The Playwright projects and `e2e:floor`:** `playwright-projects.test.mjs` and `test-floor.sh`.
- **`floor-fixtures.test.mjs`'s list,** and K5's names rule, which moves.

**Every test added or changed passes on a fresh environment, in either order:**
- each case signs in the floor user in a fresh context;
- it seeds and removes only its own rows (`turnRows` included), and unroutes in `afterEach`;
- U3 removes its plant;
- `stepKeys` uses a context of its own;
- the Node tests read sources only.

**Manual checks (human-only):** Safari and Firefox on macOS by hand. Pressing the Visual Trace button closes its menu, and Option+Tab reaches the chat list and the rail. This is the human's check of the emulated Safari press.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (2026-10-24).** The plan halted after planning, as the dispatch asked.
- It reused the committed `epic-2-context.md` without recompiling it, and took Story 2.15 as the continuity context.
- It read the CI runs 40135456843 and 40151813813 with read-only `gh`. The second is Story 2.15's first run, green.
- **Task 0** was measured on the throwaway tag `e2s216p`, with three `live floor` runs and a scratch spec, and with two static Playwright probes on macOS. Firefox and WebKit were installed into the user's Playwright cache.
  - The two tracked files that Task 0 changed (`web/playwright.config.ts` and `web/package.json`) were restored from this stage's backup, and `shasum` matched. The scratch spec was deleted, `git status` is clean apart from this spec, and teardown of `e2s216p` left nothing.
  - No IRIS MCP call and no slot was used.
- The ledger inbox (DW-89, DW-145, DW-178 and DW-179) is addressed in full. None is declined.
- **For the lead** (Design Notes):
  - the CI hosts' command, `npx -y playwright@1.64.1 install-deps firefox webkit` with root rights on `ocutalon-ci-b` and `ocutalon-ci-c`, before the first push; `live:floor` is the only unit that needs it;
  - the footprint extension, `ci/iris.sh`;
  - the rebalance (Decided 3);
  - the stale Groups bullet of Rule 21;
  - the browsers' licences (no Stack row planned);
  - the WebKit mouse-focus finding;
  - the Linux engines, unmeasured;
  - no veto-window text.
