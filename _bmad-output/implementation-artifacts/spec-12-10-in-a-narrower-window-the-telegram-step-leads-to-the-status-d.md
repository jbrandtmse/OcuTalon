---
title: 'Story 12.10: In a narrower window, the Telegram step leads to the Status drawer'
type: 'bugfix'
created: '2026-11-03'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-12, AD-19, AD-22 and AD-29)'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md (read only lines 425-436, 477 and 599)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** From 1024 to 1279 px wide the status rail is a drawer that starts closed, so the unpaired Telegram card is not on the page while the demo guide's Telegram row says "scan the QR code in the Telegram card" (DW-503, owner decision U-238).

**Approach:** In the drawer band only, and only while the server's guide view says `telegramRow` (Telegram on, session unpaired, not yet watching; AD-12), the row names the header's Status button and gets a Show me that opens the drawer with the Telegram card in view, through the Layout service's existing drawer API. Everywhere else the row is exactly as today.

## Boundaries & Constraints

**Always:**
- The page decides nothing about the row's presence: it shows only while the server's `telegramRow` is true. The page chooses only its wording and the Show me, from `Layout.band()` (AD-12).
- The button's word is `LAYOUT_TEXTS.status` (`web/src/app/shared/layout-view.ts`), passed in where the text is composed, never a second copy of "Status".
- The hint uses the wording recorded under Design Notes, "Proposed hint", verbatim. If the lead writes a changed wording into this spec before implement, use that one.
- Show me reuses `GUIDE_TEXTS.showMe` and moves focus only through `Layout.focusRegion`. `demo-guide.ts` keeps exactly one `.focus(` call (`web/scripts/announce-focus-sources.test.mjs` pins it).
- Browser tests use the CI Telegram mock and its dummy token only, through `TelegramPageFixture` on throwaway stacks. The token is never printed (AD-19, AD-22).
- Source text is ASCII; comments state the contract (Rule 14).

**Never:**
- No change to `web/src/app/rail/telegram-card/**`, `web/e2e/demo-path/**`, `header.ts`, `web/e2e/floor/*.spec.ts`, `web/src/app/about/**`, the guide's finish state or `.finish` styles, `layout-view.ts`'s doc comment, any `src/**` class, `ci/units.sh`, the workflows, `docker/after-start.sh` or `docker/merge.cpf`.
- No change at 1280 px or wider, below 1024 px, with Telegram not configured, or with the session paired.
- No device-column placement of the card (UX-DR137; DW-503 stays routed to burndown, and this story does not close it). No README change (Story 31.3).
- No real bot and no call to api.telegram.org.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Drawer band, row on | band `drawer`, `telegramRow` true | The row reads the proposed hint, followed by a Show me | No error expected |
| Show me, drawer closed | press Show me | The drawer opens and the rail region takes focus. The Telegram card (unpaired) is in view, inside the viewport and the rail and not covered, with the QR code and "Open in Telegram" visible and enabled | No error expected |
| Show me, drawer open | press Show me again | The drawer stays open and the rail takes focus again (focusRegion, never toggleStatus) | No error expected |
| User closes the drawer | Esc in the rail, or the Status button | The drawer closes and focus goes to the Status button (the existing `closeDrawer`). The hint and Show me stay, and Show me opens it again | No error expected |
| Show me goes while focused | the band leaves `drawer`, or the row leaves | Focus goes to the prompt bar (`data-guide-focus="bar"`) | Through FOCUS_RULE |
| Reference or wide band | band `reference`/`wide`, `telegramRow` true | The original line, no button in the row | No error expected |
| Stacked band | width under 1024 px | The original line, no button in the row (out of scope; DW-503) | No error expected |
| Not configured, paired, or online demo | `telegramRow` false, at any band | No Telegram row at all, as today | No error expected |

</intent-contract>

## Code Map

- `web/src/app/guide/guide-view.ts`: `GUIDE_TEXTS` :25-67 (`showMe` :41, `telegram` :60); `fill` :88-90; `GuideView.telegramRow` :150-151; `promptOf` :164-194 is the pattern to follow (a pure "what to render" function of the view). The module may import only types, because Node runs it as it is and cannot resolve an extensionless value import. So the Status word comes in as an argument.
- `web/src/app/guide/demo-guide.ts`: the import of `layout-view` :21; `FOCUS_RULE` :61-82 (an unknown key falls through to the first of action, text or bar); the Telegram row :184-186; step 4's Show me :204-206 (button-primary, the step's own action); `.telegram` style :371-376; injections :501-510; `model` :546-555; the `keepFocus` effect :566-570, which re-runs only when `model` or `hidden` changes; `showMe()` :595-611 (the step 4 sibling). Epic 31 also edits this file: keep to the Telegram row's own lines.
- `web/src/app/shared/layout.ts`: `RAIL_REGION` :10 (private now); `toggleStatus` :53-59 (closes an open drawer, so not for Show me); `focusRegion` :62-69 (a closed drawer opens, then the rail is focused after the next render; otherwise it is focused at once and scrolled to the top); `closeDrawer` :72-80; `band` :38.
- `web/src/app/header/skip-links.ts:21,73`: "Skip to status" calls `focusRegion('section.rail')`, the precedent (read only).
- `web/src/app/main-page/main-page.ts:69-79`: `section.rail#status-region`, tabindex 0 in the framed bands, `.drawer`/`.open`; Esc closes the drawer at :299-307 (read only).
- `web/src/app/header/header.ts:104-118`: the Status button `button.status-button`, `aria-expanded`, visible "Status" plus a count pill (read only).
- `web/src/app/rail/status-rail.ts:85-95`: the Telegram section is the rail's first section (`#rail-heading-telegram`, `app-telegram-card`) (read only).
- `src/ocutalon/cls/OcuTalon/Demo/Guide.cls:109` `telegramRow = telegramOn && 'paired && 'watching`; `TelegramOn` :205-208 (included and state `on`). Pinned by `Test/Demo/Guide.cls` `TestTelegramRow` :257-271 and the state test :222-249 (off and rejected give 0) (read only).
- `web/e2e/demo-path/telegram-page.spec.ts:113-131` (the `fixture()` helper) and T3 :428-447 and :538-549 (`setTelegramIncluded(1)`, `Start(.saved, BOT)`, then `Finish(saved)` and the seam put back in `finally`). This is the recipe. `telegram-approval.spec.ts:61-74` is the second copy of `fixture()` (both read only).
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPageFixture.cls`: `Start` :76 (guards the mock base, the token and the production, starts TelegramIn, and waits for the state `on`); `Finish` :162 (deletes the code rows the test made and puts everything back).
- `web/e2e/support/iris.ts`: `irisScript` :93, `chk` :111, `quoted` :189, `setTelegramIncluded` :1077. `web/e2e/support/floor.ts:150` `signInReadmeLoaded`.
- `web/e2e/guide/guide.spec.ts:286-301` Q4: at the default 1280x720 the row has no button of its own and `.prompt`'s children are `['telegram', 'prompt-line']`. It must stay green unedited.
- `web/playwright.config.ts`: the `chromium` project runs every spec under `e2e/` except demo-path, demo-switch, floor, answers and cards (Desktop Chrome, 1280x720). `docker/tests/test-sign-in.sh --part k/n` with `web/scripts/e2e-part.mjs` picks a new file up with no list change.
- `web/scripts/demo-path-summary.mjs:38-65`: a demo-path file must be `0n-<step>` or `telegram-<step>` with an existing step id, or the unit fails.
- `web/scripts/guide-view.test.mjs`: fixed strings `deepEqual` :34+ (`telegram` :71); the Telegram row tests :168-172.
- `web/scripts/ux-strings.test.mjs`: `GUIDE_TEXTS` is in the inventory (:55); the `ruled:` table is at :460. A new string with no entry fails the test.
- `web/scripts/announce-focus-sources.test.mjs:121-133,147`: the `.focus(` counts (demo-guide 1, layout 2) and the `afterNextRender` file list. Both must stay unchanged.

## Tasks & Acceptance

**Execution:**
- `web/src/app/shared/layout.ts` -- export the existing `RAIL_REGION` (no behaviour change) -- so Show me names the rail without a third literal.
- `web/src/app/guide/guide-view.ts` -- add `GUIDE_TEXTS.telegramDrawer`, the proposed hint as a template with `{status}` in place of the button's word. Add an exported pure `telegramRowOf(view, drawer, status)`. It returns `undefined` unless `view.telegramRow === true`. Otherwise it returns `{ text, showMe }`: the filled template with `showMe: true` when `drawer`, else `GUIDE_TEXTS.telegram` with `showMe: false`. Keep `GuideView.telegramRow` as it is. Update the module doc's list -- the server-only rule (AD-12) stays in one function the node tests reach.
- `web/src/app/guide/demo-guide.ts` -- inject `Layout`; add `telegram: telegramRowOf(view, this.layout.band() === 'drawer', LAYOUT_TEXTS.status)` to `model`, so the focus effect re-runs on a band change. Render the row as `<p class="telegram">`, holding a `<span>` with an id and the text, then, when `showMe`, a `button button-secondary` with `data-guide-focus="telegram"`, `aria-describedby` set to that span's id, and `{{ texts.showMe }}`. Its press calls a new `showTelegram()`, whose whole body is `this.layout.focusRegion(RAIL_REGION)`. Add a `FOCUS_RULE` branch: key `telegram` goes to `find('bar')`. Lay the row out in one line with a gap when it has the button. Update the class doc -- the hint, the Show me and the focus rules.
- `web/scripts/guide-view.test.mjs` -- add `telegramDrawer` to the fixed strings. Test `telegramRowOf`: the drawer row text equals the proposed hint for `'Status'` and carries the given word; outside the drawer it gives the original line with no Show me; `telegramRow` false or absent gives `undefined` at both bands -- the unit pins of AC1 to AC3.
- `web/scripts/ux-strings.test.mjs` -- add one `ruled` entry for the `telegramDrawer` template. It names Story 12.10's veto item and cites the ruling id that the lead writes into this spec's Spec Change Log before implement (U-238 if none is written) -- every page string has a source.
- `web/e2e/guide/telegram-drawer.spec.ts` (NEW) -- in the chromium project, on the sign-in unit's stack, two tests. Each sets `setTelegramIncluded(1)` and calls `Start(.saved, 'ocutalon_drawer_bot')` through a file-local `fixture()`, signs in with `signInReadmeLoaded`, and in `finally` calls `Finish(saved)` and puts the seam back. **D1 (1100x720):** the precondition (the row shows, so the README session is unpaired and not watching); the rail hidden and the Status button `aria-expanded="false"`; the row's text equals the hint exactly; one "Show me" in the row, described by the hint and not clipped in the guide. Press it: `aria-expanded="true"`, the rail visible and focused, and the card `[data-state="unpaired"]`, whose box lies within the viewport and the rail. `elementFromPoint` at the centres of the QR image and of the link hits the card. The QR image (its alt text) is visible, and the link "Open in Telegram (opens Telegram)" is visible and enabled. Press Show me again: still open, and the rail is focused. Esc: closed, focus on the Status button, Show me still there. Focus Show me, then resize to 1400 wide: Show me is gone and focus is on the prompt bar. **D2 (1400x720):** the row's text is the original line, there is no button in the row and no Status button, and the rail and the unpaired card are visible -- AC1, AC2 and AC4 on the real chain.

**Acceptance Criteria:**
- Given a 1100x720 page with Telegram on through the CI mock and the README session unpaired and not watching, when the guide shows, then the Telegram row reads the proposed hint naming "Status", followed by a Show me, while the drawer is closed.
- Given that page, when the user presses the row's Show me, then the drawer opens with the rail focused and the unpaired Telegram card in view, within the viewport and the rail and not covered, with the QR code and "Open in Telegram" visible and enabled. A second press keeps the drawer open, and Esc closes it with focus on the Status button.
- Given a 1400x720 page in the same state, or a view with `telegramRow` false at any band, when the guide shows, then the row is exactly today's: the original line with no button, or no row.
- Given the online demo (no bot token, so the Telegram state is off), when a visitor opens the page at any width, then the server's `telegramRow` is false (Test.Demo.Guide's existing pins), so neither the hint nor the unpaired card shows. `telegramRowOf`'s unit pin shows the page adds neither at any band.

## Spec Change Log

- 2026-11-03, lead spec gate: Decided in-stage 9 confirmed. The one `ruled` entry in `web/scripts/ux-strings.test.mjs` is a one-key append to a shared catalog (standing precedent: a plain union at whichever epic merges second). Epic 31's open branch appends its own `ruled` entry directly after the `'Step {n}, {label}, upcoming',` block (about :508-513), so put this story's entry somewhere else in the `ruled` table, not on those lines, so that the two changes touch different lines. The lead reports the file under `footprint_extensions:`. The hint wording stays pending the orchestrator's veto ruling.

## Review Triage Log

## Design Notes

**Proposed hint (veto item, U-238):** "Optional: press Status at the top of the page, then scan the QR code in the Telegram card to get the notice on your own phone."
This wording is pending the orchestrator's veto ruling, which the lead raises before implement. A changed wording is written here before implement. The template is `GUIDE_TEXTS.telegramDrawer = 'Optional: press {status} at the top of the page, then scan the QR code in the Telegram card to get the notice on your own phone.'`, filled with `LAYOUT_TEXTS.status`. "Press" is the guide's own verb ("Press Break the feed.").

**Governing ADs:** AD-12 (the page renders only what the server's guide view says; `telegramRow` is the server's); AD-29 (Lane B's guide and layout files; the card and the demo-path Telegram specs are Lane A's and untouched); AD-22 (browser tests on throwaways against the CI mock); AD-19 (the dummy bot token is never printed or compared except as a boolean).

**Consumes:** `Layout.band` and `Layout.focusRegion` with `RAIL_REGION`, `LAYOUT_TEXTS.status`, and the server's guide view `telegramRow` (`Demo.Guide.Compute`, through `/state` and `guide.state`). The tests also consume `TelegramPageFixture` `Start`/`Finish` and `setTelegramIncluded`. **Consumed-by:** none. No new service or module: `telegramRowOf` is consumed in this story by `DemoGuide`. Integration AC: D1/D2 drive the real server, mock and page.

**Extend, don't copy (Rule 2):** Show me extends the Layout API, `focusRegion(RAIL_REGION)`, which is what "Skip to status" and the Status button use. It adds no drawer mechanism, and `showMe()`'s phone path is untouched. `telegramRowOf` follows `promptOf`'s pattern. The spec's `fixture()` is a third copy of the 14-line helper in `telegram-page.spec.ts:118` and `telegram-approval.spec.ts:61`. It is a copy because both siblings are file-local in Lane A files this story may not edit, so a shared export in `web/e2e/support/` would still leave both copies, and it would edit a shared support file outside the footprint. A Lane A story can unify all three.

**Decided in-stage:**
1. Focus on Show me goes to the rail region (`#status-region`), through `focusRegion(RAIL_REGION)`. This is what the existing drawer API does when it opens the drawer (the Status button, Skip to status). EXPERIENCE's focus table (UX-DR131) gives Show me for step 4 only and otherwise "the nearest container": the rail is the card's container, the card is its first section and so in view, and the next Tab reaches "Open in Telegram".
2. Show me never closes the drawer: when the drawer is open it focuses and scrolls the rail. Closing stays the existing Esc or Status press (focus to the Status button). The hint and Show me depend on the band only, not on `drawerOpen`, so the bar does not change under the user.
3. When Show me leaves while it holds focus (a band change, or the row leaving), focus goes to the prompt bar, the nearest container.
4. Show me is `button-secondary`: the row is optional, and the bar's primary is the step's own action. `aria-describedby` points at the hint, so two "Show me" buttons (when step 4 is selected while the row shows) are told apart with no new text.
5. Below 1024 px the card is in the one scrolling column (on the page, below the chat), not off the page, so nothing changes there. Its placement is UX-DR137 (DW-503).
6. "The card" in the online-demo AC is the unpaired QR card (epic context). The off state's "Telegram not set up" card is unchanged.
7. The browser tests go in the chromium project (sign-in unit), not demo-path, for three reasons. First, `demo-path-summary.mjs` fails any demo-path file not named `0n-<step>` or `telegram-<step>`, and the only fitting name, `telegram-page.spec.ts`, is contended. Second, the README session watches Orders from step 02, so the server's `telegramRow` is false when the `telegram-*` files run. Third, the sign-in stack has the same CI override (dummy token, mock base), so the same fixture works (inference until D1's first run: if `Start` refuses there, that is a `TOOLING:` clarification). No `ci/units.sh` or workflow change is needed.
8. The tests use the project's default height, 720 px: Epic 12 measured the card at y=271 with a height of 235 at 1100x900, so 720 still holds it. D1's box assertion measures it.
9. `ux-strings.test.mjs` already tests the guide view's strings (it imports `GUIDE_TEXTS`), so its one entry is read as within the footprint ("the guide's unit tests"). The lead should confirm this at the validation gate. Epic 31 may add entries to the same table, and the merge is a plain union.

**Ledger:** no inbox entries. DW-503 is context only.

## Verification

`<laneB>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=12 stage=implement'`. The fresh tag is `e12s10i`. Each command runs in the foreground with `timeout: 600000`, one per call. Tear down only `e12s10i` (`<laneB> OCUTALON_RUN_TAG=e12s10i ci/iris.sh teardown`), also after a failure.

**Commands:**
- (loop) `node --test web/scripts/guide-view.test.mjs web/scripts/ux-strings.test.mjs web/scripts/announce-focus-sources.test.mjs web/scripts/floor-sources.test.mjs web/scripts/layout-view.test.mjs` -- expected: all pass.
- (loop) `npm --prefix web run lint` -- expected: exit 0.
- (loop) `<laneB> OCUTALON_RUN_TAG=e12s10i ci/iris.sh build` after each web change -- expected: the bundle builds.
- (loop) `<laneB> OCUTALON_RUN_TAG=e12s10i ci/iris.sh live sign-in --part k/4`, where k is the part whose `PART` line lists `guide/telegram-drawer.spec.ts`. Find k with `npm --silent --prefix web run e2e -- --list --reporter=json > <scratchpad>/e12s10i/list.json`, then `node web/scripts/e2e-part.mjs k/4 <that file>`. Expected: the part passes, D1 and D2 included.
- (once) `npm --prefix web test` -- expected: every node test passes.
- (once) `bash ci/checks.sh` -- expected: every block passes.
- (once) `<laneB> OCUTALON_RUN_TAG=e12s10i ci/iris.sh live sign-in --part 1/2`, then `--part 2/2` -- expected: both pass (guide Q4 at 1280 unchanged, D1, D2).
- (once) `<laneB> OCUTALON_RUN_TAG=e12s10i ci/iris.sh class OcuTalon.Test.Demo.Guide` -- expected: passes (the server's `telegramRow` pins behind AC3).
- (once) `git status --short -- web/src/app/rail web/e2e/demo-path web/e2e/floor web/src/app/header web/src/app/about src ci .github docker` -- expected: prints nothing.
- Left to CI: the demo-path, floor and online units (`live demo-path`, `live floor`, `live online-demo`). The change is inert at 1280x720, and Telegram is parked on those stacks. CI's `browser` and `shards` groups run them on push.

**Mutations (Rule 19, one per AC; apply, see red, revert, and confirm `git status --short`/`git diff --stat` unchanged):**
- AC1: `telegramRowOf` ignores `drawer` (always the original line) -> `guide-view.test.mjs` and D1's hint assertion go red.
- AC2: `showTelegram` does nothing (or calls `toggleStatus`) -> D1 goes red (the drawer stays closed, or the second press closes it).
- AC3: `telegramRowOf` ignores `view.telegramRow` -> `guide-view.test.mjs`'s `undefined` rows go red.
- AC4: `telegramRowOf` gives the drawer row at every band -> D2 goes red. The `FOCUS_RULE` `telegram` branch removed -> D1's resize step goes red.

**Shared surfaces:** the `GUIDE_TEXTS` key set (`guide-view.test.mjs`); the `ux-strings.test.mjs` inventory and `ruled` table; the chromium project's spec files and the sign-in parts' cut (`e2e-part.mjs`); the sign-in stack's TelegramIn, mock Bot API and code rows while D1/D2 run (`Start`/`Finish` restores them); `layout.ts`'s exports; the `.focus(` and `afterNextRender` pins (unchanged). Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Plan stage only, halted after planning as instructed. Before implement, the lead raises the proposed hint (Design Notes) as the veto item and confirms Decided in-stage 9 (the `ux-strings.test.mjs` entry as within the footprint).
