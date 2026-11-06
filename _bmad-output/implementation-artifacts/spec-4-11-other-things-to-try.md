---
title: 'Story 4.11: Other things to try'
type: 'feature'
created: '2026-11-06'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A judge who has finished the demo guide, or who wants to look further at any point, has no list of the other things the demo can show. They have to work out for themselves how to change the persona, send the suspicious email, reject a fix or see the page without the demo. The owner decided on 2026-11-06 (made by the Contest Planner under the owner's delegation, 05:27Z) that the guide offers an "Other things to try" panel. Each item has a label, one look-for line and one button that uses a control the demo already has.

**Approach:**
- **Server.** A new read-only class, `OcuTalon.Demo.Features`, lists the ids of the features this instance has, from what the server already knows: compiled classes and the `STUB` parameter that every unbuilt production item carries (AD-29). `Demo.Guide.View` puts the list into the guide payload as `GuideState.Features`. So it rides `/v1/state` and the `guide.state` event, demo mode only, with no new route, write path, role or install step.
- **Client.** A framework-free registry holds all seven items. The panel shows each registered item whose id is in the server's list, in registry order. Items 5 to 7 therefore appear by themselves once Epics 19 and 39 merge, with no client change. On this branch they are hidden, because their features are absent.
- **Buttons.** Each button hands off to the real control: it puts focus on that control and presses it. So the action is exactly that control's own action: the Persona card's Change, the mailbox chip "Sample: suspicious request", the box's Break the feed and the header's Demo view switch.
- **Opening.** The panel opens by itself in the guide's finish state. A new "More to try" link in the guide's row 1 opens and closes it at any time.

## Boundaries & Constraints

**Always:**
- **Demo view only.** The link and the panel live inside `DemoGuide`, which renders only while `DemoView.on()` and the snapshot carries a guide (`guideOf`). No new file reads `demoMode` (`demo-view-sources.test.mjs`).
- **The catalog is the server's.**
  - `OcuTalon.Demo.Features.Present()` returns a `%List` of ids, in this order. Each id is listed only when its condition holds:
    - `persona`: the class `OcuTalon.Msg.Command.SetPersona` is compiled.
    - `suspiciousEmail`, `rejectFix`, `demoView`: always. They are this demo's own controls, shipped in the same package as this class.
    - `memory`: `OcuTalon.Memory.Ops` is compiled and its `STUB` parameter is not 1 (stub until Story 19.3).
    - `documents`: `OcuTalon.Docs.Ops` is compiled and its `STUB` parameter is not 1 (stub until Story 19.4). Epic 34's Documents page does not count.
    - `heartbeat`: the class `OcuTalon.Msg.Command.RunHeartbeat` (Epic 39's Run now command) is compiled.
  - `Ids(has)` is the pure mapping from probe flags to the list. `Present()` is `Ids` of the instance's probes. Each probe is one `%Dictionary.CompiledClass` `%ExistsId`, plus one `$Parameter` read where a stub is checked. No SQL, no write, no lock, no setting.
  - `Demo.Guide.View` sets `view.Features` from `Present()`, so `Compute`, `Blank()` and the markers' 200 answers all carry it.
- **The client never hard-codes which epics merged.**
  - `web/src/app/guide/more-to-try-view.ts` (framework-free) exports:
    - `MORE_TO_TRY_TEXTS`;
    - `MORE_TO_TRY_ITEMS`: seven entries `{ id, label, lookFor, button, action }`;
    - `itemsFor(features: readonly string[] | undefined)`: the registry entries whose id the list holds, in registry order. Unknown ids are ignored, and undefined gives `[]`.
  - Nothing else decides availability.
- **Actions.** Every action runs only in a `(click)` handler of a native button or link. Focus moves only for that press.
  1. **`persona`:** `Layout.focusRegion(RAIL_REGION)`, so the drawer band opens the drawer. After the next render, focus goes to the Persona card's Change (`app-persona-card button.change`), and it is pressed only when `aria-expanded` is not `"true"`. If the card has not loaded, focus goes to `#rail-heading-persona`.
  2. **`suspiciousEmail`:** `DeviceTabs.select('mailbox')`. After the next render, focus goes to the mailbox chip named `chipName(SAMPLES[2].label)` and the chip is pressed. The chip itself handles the email limit, its error line and its announcement.
  3. **`rejectFix`:** focus goes to the box's Break the feed button (`app-break-feed-box app-server-button button`, demo-guide.ts:34) and it is pressed. An inactive box does nothing, and its hint describes it. Availability stays `Guide.Compute`'s.
  4. **`demoView`:** focus goes to the header's switch (`app-demo-view-switch [role="switch"]`) and it is pressed only while `aria-checked="true"`, so focus is on the switch when the guide leaves.
  5. **`memory`:** sends `MORE_TO_TRY_TEXTS.rememberPrompt` once through `ChatOutbox.send(text)` (one argument), with `TryItRow`'s guard: `aria-disabled` and a press sends nothing while `turnInFlight(...)` holds or `AllowanceState.active()` is set. No focus move.
  6. **`documents`:** an `<a routerLink="/documents">`, as header-nav.ts:24 has it.
  7. **`heartbeat`:** `Layout.focusRegion(RAIL_REGION)` (the "Heartbeat checklist" card is a rail card, Story 39.5).
- **Markup.**
  - **The link.** It sits in row 1, after "About 2 minutes" and before Hide guide: `<button type="button" class="link more-link" data-guide-focus="moreLink" [attr.aria-expanded] [attr.aria-controls]>`. `aria-controls` names the panel's id only while the panel is open. The collapsed bar has no link.
  - **The panel.** `app-more-to-try`: `<div role="group" aria-labelledby>`, labelled by a visible `<p>` with the panel label. It is never a heading, because the heading lists are pinned (4.10 Decided 8). Then a `<ul>` with one `<li>` per item, each holding:
    - a `<p class="item-label">`;
    - a `<p class="look-for">`;
    - one native control with `data-guide-focus="moreItem"`: a `<button type="button" class="button button-secondary">`, or the link for `documents`.
  - Every control is named by its visible text alone: no `aria-label`, no icon. No element uses the classes `more`, `line`, `chip` or `headline`.
- **Open state** (in `DemoGuide`):
  - `chosen = signal<boolean | undefined>(undefined)`, and `open = chosen() ?? finished`.
  - The link sets `chosen` to `!open()`. An item's press sets it to `true`. A rising edge of `finished` resets it to `undefined`.
  - Placement: in the finish, the panel sits after `.finish-links` and before the Try it yourself row. Outside the finish it sits after the prompt bar. Only one renders at a time.
- **Focus rule.** `FINISH_PARTS` gains `'moreItem'`, so a panel control that loses focus when the finish leaves hands focus on, like the finish's other parts. The link's toggle keeps focus on the link. The panel announces nothing.
- **Look.**
  - Panel label: `--type-body-sm-*` and `--ink-muted`.
  - Item label: `--type-body-*` with `--type-body-strong-font-weight`, in `--ink`.
  - Look-for line: `--type-body-sm-*` and `--ink-muted`.
  - Buttons: `button-secondary`, never attention colours.
  - Items are rows that wrap (`flex-wrap`, `gap: var(--space-2)`), with the button after the text.
  - No `transition`, no fixed height, and width queries only through `LAYOUT_QUERIES`.
- **Texts.** Every string is ruled at the spec gate. See "Public text (proposed, awaiting the ruling)". The implement stage uses the ruled strings verbatim, writes them into EXPERIENCE.md, and pins them in `more-to-try-view.test.mjs` and `ux-strings.test.mjs`. Straight ASCII quotes only.

**Never:**
- No new route, REST call, write path, role, install step or setting. No edit of `Web/Api.cls` or `Live/Publish.cls`.
- No edit of the other contended paths, except the two lines named under "Contended edits" once the orchestrator rules (Design Notes).
- No change to `Guide.Compute`'s progress, finish or Break the feed rules.
- No new mock scenario, and no edit of any existing scenario. No new CI unit, group, Playwright project or e2e folder.
- No duplicate of a control's logic. A hand-off presses the real control, and never calls `postMailboxSample`, `postBreakFeed`, `DemoView.set` or a persona API itself.
- No look-for line of items 1-4 names memory, documents or the heartbeat. No line claims an all-clear (AD-28).
- No button or link text contains the accessible name of an existing control: "Break the feed", "Show me", "Run again", "Change", "Demo view", ", send sample email", "Simulate an incoming email", "Open the trace". (The ruled "Send the suspicious email" contains "Send": see Design Notes, "Name-collision check".)
- The existing finish line `moreToTry` is changed only as the ruling says (Design Notes, "Naming clash").

## I/O & Edge-Case Matrix

"Demo view" means `DemoView.on()`. The registry is items 1-7. "Features" means the server's `guide.features`.

| # | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| 1 | Demo view, guide finished, features = the four ids | The link shows `aria-expanded="true"`. The panel is in the finish after the links and before Try it yourself, with items 1-4 in order (label, look-for, control). Items 5-7 are absent. Nothing is sent | none |
| 2 | Demo view, not finished | No panel. The link shows `aria-expanded="false"`. A press (click, Enter, Space) opens the panel after the prompt bar and keeps focus on the link. A second press closes it | none |
| 3 | Features = all seven ids (or one more id) | The items for exactly those ids, in registry order. Each id's appearance shows its item, and an unknown id shows nothing | none |
| 4 | **(Integration)** Real stack: `/v1/state` `guide.features` from `Demo.Features.Present()` | The panel shows exactly `itemsFor(features)`. On this branch that is items 1-4 (Task 0 records it) | none |
| 5 | Press item 1 | Rail focused (the drawer opened in the drawer band), then the Persona card's Change `aria-expanded="true"` and focused | Card not loaded: focus is on the Persona heading |
| 6 | Press item 2 | The Simulated mailbox tab is selected. Exactly one `POST .../mailbox/samples/suspicious-request` goes out, the chip's own request. Focus is on the chip | Email limit: the chip is inactive, no POST, described by its reason |
| 7 | Press item 3, box active | Focus is on the box's Break the feed. Exactly one `POST .../demo/break-feed`, the box's own | Box inactive: no POST, focus on it, its hint describes it |
| 8 | Press item 4 | The switch is `aria-checked="false"` and focused. The guide, the box and the Simulated devices are gone, and sessionStorage `ocutalon.demoView.off` is `1`. No request to the server | none |
| 9 | Press item 5 (routed features) | One `POST /messages` `{text: rememberPrompt, fromGuide: false}`. While a turn is in flight, or the allowance is used up: `aria-disabled="true"` and no POST | none |
| 10 | Item 6 / item 7 (routed features) | Item 6 is a link to `#/documents`. Item 7 focuses `section.rail` | none |
| 11 | Switch off, server `demoMode` false, or no guide | No link and no panel | none |

</intent-contract>

## Code Map

**New:**
- `src/ocutalon/cls/OcuTalon/Demo/Features.cls`: `Present() As %List`, `Ids(has As %DynamicObject) As %List`, and the private probes `Compiled(class)` and `Built(class)` (compiled and `'+$Parameter(class,"STUB")`). Parameters name the four marker classes.
  - Siblings: `Install/Step/Tools.cls:33` and `Fix/Kind.cls:44` (the `%ExistsId` probe idiom); the `STUB` contract at `Memory/Ops.cls:13` and `Docs/Ops.cls:12` (AD-29).
  - Absent here, verified: `Checks/Beat.cls` and `Msg/Command/RunHeartbeat.cls`. `RunHeartbeat` is on `origin/OCT-epic39`.
- `src/ocutalon/cls/OcuTalon/Test/Demo/Features.cls`: lane-b shard area `Demo`, which joins automatically (`ci/units.sh:21`). Tasks give its content.
- `web/src/app/guide/more-to-try-view.ts`: texts, registry, `itemsFor`. Siblings: `chat/try-it-view.ts` and `header/demo-view-texts.ts`.
- `web/src/app/guide/more-to-try.ts`: `app-more-to-try`, OnPush, standalone. Input `items`; output `pressed` (so `DemoGuide` sets `chosen`).
  - It injects `Layout`, `DeviceTabs`, `ChatOutbox`, `LiveState`, `AllowanceState`, `Injector` and `RouterLink`.
  - Its one private `handTo(selectors: string[], press: (el) => boolean)` focuses the first element found and clicks it when `press` says so: this file's single `.focus(` call.
- `web/scripts/more-to-try-view.test.mjs`, `web/scripts/more-to-try-sources.test.mjs`, `web/e2e/guide/more-to-try.spec.ts`: Tasks.

**Edited (Lane B, in no other epic's diff):**
- `src/ocutalon/cls/OcuTalon/Live/Payload/GuideState.cls`: after `Run` (last property), `Property Features As list Of %String(%JSONFIELDNAME = "features", MAXLEN = 32);` with a contract doc comment.
- `src/ocutalon/cls/OcuTalon/Demo/Guide.cls:217-240` `View`: insert each id of `##class(OcuTalon.Demo.Features).Present()` into `view.Features`, so `Compute`, `Blank()` and the markers' answers carry it (Live.Publish.RefreshGuide compares against Blank: no extra publish).
- `web/src/app/guide/demo-guide.ts`:
  - row 1 (`:178-179`): the link between `.duration` and Hide guide;
  - the finish (`:187-199`): `<app-more-to-try>` after `.finish-links`, with `.more` per the ruling;
  - the prompt branch (`:203-241`): `@if (moreOpen())` `<app-more-to-try>` after `.prompt`;
  - `FINISH_PARTS` (`:50`) gains `'moreItem'`;
  - `chosen`, `moreOpen`, the rising-edge reset in `follow()` (`:673-680`), the `items` computed (`itemsFor(view.features)`), the imports, the class doc comment (`:94-127`) and the styles for `.more-link`.
- `web/scripts/announce-focus-sources.test.mjs`:
  - `FOCUS_CALLS` (`:127-143`) gains `'app/guide/more-to-try.ts': [1, 'an item of Other things to try hands focus to the control it presses, for the user\'s own press (Story 4.11)']`;
  - the `afterNextRender` list (`:155`) gains the file.
- `web/scripts/ux-strings.test.mjs`: `IMPORTED` (`:41-66`) gains `['guide/more-to-try-view.ts', ['MORE_TO_TRY_TEXTS']]`; `SOURCES.ux` gains every ruled string. Its `*_TEXTS` scan (`:744-749`) requires the row.

**Contended (only after the orchestrator's ruling; Design Notes):**
- `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls:1000`: in the GuideState contract, after `"Run": "OcuTalon.Live.Payload.Part.GuideRun(%JSONFIELDNAME=run)"`, add `"Features": "list Of %String(%JSONFIELDNAME=features,MAXLEN=32)"`. The 31-class count (`:93`) does not change.
- `web/src/app/live/payloads.ts:268`: regenerate with `npm --prefix web run payloads`, which adds `features?: string[];` after `run?: GuideRun;`. Its `--check` runs in `payloads.test.mjs:54-58`.

**Pins of the old shape** (update in the same pass; Rule 19):
- The link adds a Tab stop in row 1: `floor/guide.spec.ts` M1 (`:91-108`, exact Tab order); `guide/guide.spec.ts` Q1 (`:139-153`) and Q11 (`:621-627`: row 1 at 1280px).
- The panel in the finish: `floor/guide.spec.ts` M9 (`:510`, `MORE` `:42`, `:561`) and the other finish cases (M10, M14).
- Ruling P1 only: `chat/try-it.spec.ts:291` (`follows '.finish .more'`), `try-it-sources.test.mjs:59-66`, `guide-view.test.mjs:68` (the `GUIDE_TEXTS` deepEqual), and the `moreToTry` entry of `ux-strings.test.mjs` `SOURCES.ux`.
- Search `web/e2e/**`, `web/scripts/**` and, read only, `web/e2e-online/**` for: finish content, row 1 controls, Tab sequences through the guide, button counts in the guide, and `getByText` or non-exact names that a new text could match.

**Read only (the hand-off targets and their tests):**
- `rail/persona-card/persona-card.ts:89-98` (Change: `aria-expanded`, `toggle()` `:383`);
- `rail/rail-view.ts:56` (`persona: 'Persona'`, heading id `PERSONA_HEADING_ID` in persona-card-view.ts);
- `mailbox/simulated-mailbox.ts:119-131` (chips are `ServerButton variant="chip"`, `[label]=chipName(label)`, `[inactive]=limited()`), `mailbox-view.ts:55,119`;
- `devices/device-tabs.ts` `select`;
- `feed/break-feed-box.ts:45` and `break-feed-view.ts:23`;
- `header/demo-view-switch.ts:16-23`;
- `shared/layout.ts:10,62` (`RAIL_REGION`, `focusRegion`);
- `chat/try-it-row.ts` (the guard to extend) and `try-it-view.ts` `turnInFlight`.

**E2e helpers:**
- `guide/guide.spec.ts`: `guideOf` (`:30-41`), `serve` via `changeSnapshot` (`:56-66`), `liveEvents` (`:75`, drop `guide.state` so a routed finish stands, as 4.10's Y5 does);
- `persona-card.spec.ts:45` (`changeOf`);
- `support/devices.ts:205,214` (`mailboxOf`, `sampleChipOf`);
- `support/demo-path.ts:57` (`breakFeedButton`);
- `demo-switch/view.spec.ts:33` (the switch locator);
- `support/api.ts` (`changeSnapshot`).

**UX** (`_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/`):
- `EXPERIENCE.md`: `:222-243` "Demo guide and controls", `:595-618` "The demo guide" (the finish list, More to try at `:615`), `:584-593` "Demo Mode and the Online Demo";
- `DESIGN.md`: `:764-777` Demo guide and controls, `:848` the Try it yourself row;
- `mockups/states.html`: `:715-750` C4, the finish state.

## Tasks & Acceptance

**Execution** (in dependency order):
- [ ] **Task 0 (measure, recorded under Verification).**
  - (a) On a fresh stack, `/v1/state` `guide.features` is `["persona","suspiciousEmail","rejectFix","demoView"]`: items 5-7 are hidden on this branch.
  - (b) The sign-in stack is in demo mode. 4.10's Y3 relied on it; K1 fails loudly naming it otherwise.
  - (c) Under `live:floor` M9's finish, the guide's height and the chat's visible height at 1280x800, 1024x768 and the compact height band, before and after the panel.
  - If a floor layout case fails because of the panel, fix the panel's own layout within the footprint. Never weaken a floor case; otherwise HALT with a clarification.
- [ ] `src/ocutalon/cls/OcuTalon/Demo/Features.cls` (new): as in Always and the Code Map. The doc comment states the contract.
- [ ] `Live/Payload/GuideState.cls` and `Demo/Guide.cls` `View`: as in the Code Map.
- [ ] Contended, after the ruling: the `Payloads.cls:1000` line, and `npm --prefix web run payloads`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Demo/Features.cls` (new):
  - (a) `Ids`: with no flag set, the ids are the three constants; each flag alone adds exactly its id in its place; all flags give the seven in order (the catalog unit test, server side).
  - (b) `Present()` equals `Ids` of probes the test computes itself: `%ExistsId` for SetPersona and RunHeartbeat; compiled and `STUB` not 1 for Memory.Ops and Docs.Ops.
  - (c) `Guide.Compute(<a test session>).Features` and `Blank().Features` equal `Present()`.
  - (d) The class holds no SQL and no `%Save`/`Set ^` (a source read of its `.cls`).
- [ ] `web/src/app/guide/more-to-try-view.ts` (new): the ruled texts, the registry, `itemsFor`. Rule 14: the comments state the contract.
- [ ] `web/src/app/guide/more-to-try.ts` (new): the group, the list, the controls and the seven actions, as in Always. Styles as in Look.
- [ ] `web/src/app/guide/demo-guide.ts`: the link, both placements, the open state, `FINISH_PARTS` and the doc comment.
- [ ] `web/scripts/more-to-try-view.test.mjs` (new, `node --test`):
  - (a) The fixed strings: `MORE_TO_TRY_TEXTS` equals the ruled strings exactly, and the registry's ids, labels, look-fors and button texts are in order.
  - (b) `itemsFor`: `[]` for undefined or empty; the four ids give items 1-4; for each of `memory`, `documents` and `heartbeat`, adding it shows exactly its item in its place; an unknown id is ignored; order follows the registry, not the input.
  - (c) Each quoted on-screen name equals its source, imported:
    - `rail-view.ts` `persona`;
    - `PRESETS` Pirate and Another language;
    - the Language help's "Spanish";
    - `PERSONA_TEXTS.save`;
    - `TRY_IT_TEXTS.prompts[1]`;
    - `SAMPLES[2].label`;
    - `DEVICE` `mailboxTab`;
    - the Break the feed button text;
    - `'Nothing was changed.'` within `msg/catalog.ts` `answered.rejected`;
    - `REQUEST_NAMES.reject`;
    - `DEMO_VIEW_TEXTS.label`.
  - (d) No look-for of items 1-4 matches `/memor|document|heartbeat/i`, and no text matches the reply guard's `BANNED` or `RESERVED` phrases (read from `Checks/ReplyGuard.cls`, as `persona-card-view.test.mjs` does).
  - (e) No control text contains a name from the Never list.
- [ ] `web/scripts/more-to-try-sources.test.mjs` (new; the shape of `try-it-sources.test.mjs`):
  - (a) Neither file mentions `demoMode`. `more-to-try.ts` has no `Announcer`, no `ApiClient`/`HttpClient`, no `(keydown`, and no call of `postMailboxSample`, `postBreakFeed`, `DemoView` or `.set(false)`. It has one `.focus(` and one `outbox.send(` with one argument. Every `<button` has `type="button"`, and every action is in a `(click)`.
  - (b) `demo-guide.ts`: the link is in row 1 between `class="duration"` and `data-guide-focus="hide"`, with `aria-expanded`. The finish holds `<app-more-to-try` after `finish-links` and before `<app-try-it-row`. The prompt branch holds it after the prompt bar. `FINISH_PARTS` lists `'moreItem'`.
- [ ] `web/scripts/announce-focus-sources.test.mjs` and `ux-strings.test.mjs`: as in the Code Map. Under ruling P1, also `guide-view.test.mjs` and `try-it-sources.test.mjs`.
- [ ] `web/e2e/guide/more-to-try.spec.ts` (new). Project chromium (`live:sign-in`), the guide spec's user and helpers. Routed cases rewrite `/state` and drop `guide.state` from the polls. POSTs that a case routes are fulfilled with the answer the control expects, and counted.
  - **K1** (real, matrix 4): from `page.request` `/api/v1/state`, `guide.features`. Open the link; the panel's labels equal `itemsFor(features)`'s, in order. It records the list for Task 0 (a).
  - **K2** (routed finish, four ids; matrix 1): placement by `compareDocumentPosition` (after `.finish-links`, before the Try it yourself group); `aria-expanded="true"`; four items, each label, look-for and control (`type="button"`, named exactly); no item 5-7; no POST.
  - **K3** (routed, seven ids; matrix 3, 10): seven items in order; item 6's `href` ends `#/documents`; item 7's press puts focus on `section.rail`.
  - **K4** (routed step 1; matrix 2): no panel. Tab from the last step reaches the link, then Hide guide. Enter opens the panel after the prompt bar with focus on the link; Space closes it. Tab through the open panel reaches each control in order.
  - **K5** (item 1, real persona card; matrix 5): Space on the button. Change is `aria-expanded="true"` and focused. `afterEach` collapses it (Esc).
  - **K6** (item 2, routed POST; matrix 6): Enter on the button. The mailbox tab is selected, exactly one POST to `/mailbox/samples/suspicious-request`, and focus is on `sampleChipOf(mailbox, 'Sample: suspicious request')`.
  - **K7** (item 3, routed finish with `breakFeed.active` true; matrix 7): click. Exactly one POST to `/demo/break-feed`, and focus is on `breakFeedButton`. Then with `breakFeed.active` false: no POST, focus on the button, and its `aria-describedby` names the hint.
  - **K8** (item 4; matrix 8): click. `getByRole('switch', { name: 'Demo view' })` is `aria-checked="false"` and focused; no guide region, no box, no Simulated devices region; sessionStorage key `1`; no request to the server.
  - **K9** (item 5, routed seven ids; matrix 9): one `POST /messages` `{text: rememberPrompt, fromGuide: false}` (routed). With the routed allowance used up: `aria-disabled="true"` and no POST.
  - **K10** (matrix 11): a page with sessionStorage `ocutalon.demoView.off`=`1`, then `changeSnapshot` `demoMode` false: no link and no group "Other things to try".
- [ ] Update the pins of the old shape (Code Map), only to the new shape. A floor rule is never weakened.
- [ ] **`EXPERIENCE.md`.** Each change carries the marker `[ADDED 2026-11-06, Story 4.11, owner decision made by the Contest Planner under the owner's delegation]`:
  - "Demo guide and controls" gains a bullet **Other things to try**: the link, the panel, the seven items with their ruled texts, "each shown only when the instance has its feature", the hand-off rule, keyboard and focus.
  - "The demo guide" finish list follows the ruling. Under P1 the "More to try: ..." bullet is replaced by the panel, with the old text quoted in an `[AMENDED ...]` marker. The Try it yourself bullets (`:238`, `:616`) then say "after the Other things to try panel".
- [ ] **`DESIGN.md`**, with the same marker: `:767` Row 1 gains the "More to try" link-styled button before Hide guide. A new bullet **Other things to try panel** gives the Look tokens. `:772` the finish gains the panel. `:848` the Try it yourself row's placement follows the ruling.
- [ ] **`mockups/states.html`**: C4 (`:715-750`) shows the panel in place of the "More to try" line (P1) and the link in row 1. The caption carries the marker.

**Acceptance Criteria:**
- **AC1.** Given the demo view is on and the guide's finish state shows, when the guide renders, then the "Other things to try" panel shows in the finish with one item per available feature, each with its label, look-for line and one control, in registry order.
- **AC2.** Given the demo view is on at any step, when I press the "More to try" link, then the panel opens (and closes on a second press), with focus kept on the link and `aria-expanded` following.
- **AC3 (Integration).** Given a real stack, when the page reads `/v1/state`, then `guide.features` is `Demo.Features.Present()`'s list and the panel shows exactly the items for it. On this branch that is items 1-4, and items 5-7 are absent.
- **AC4.** Given the catalog, when a feature's id appears in it, then its item shows, with no client change. This holds for each of memory, documents and heartbeat (node and server unit tests).
- **AC5 (Integration).** Given items 1-4, when I press a control, then the real control acts as on its own press: the Persona card's Change opens; the "Sample: suspicious request" chip sends its POST; Break the feed sends its POST; the Demo view switch turns off. Focus is on that control. Nothing happens without a press.
- **AC6.** Given the panel, when it is used by keyboard alone, then every control is reachable by Tab and works with Enter and Space. The panel announces nothing, and focus moves only on the user's press or through the focus rule.
- **AC7.** Given the demo view off, or an install without demo mode, when the page renders, then neither the link nor the panel shows.
- **AC8.** Given the ruled strings, when this story merges, then the fixed-strings tests pin them, EXPERIENCE.md and DESIGN.md carry the panel with the 2026-11-06 marker, and every on-screen name a text quotes equals its source.
- **AC9.** Given the change, when it merges, then no new route, write path, role, install step, mock scenario, CI unit or e2e folder exists, the contended files change only by the ruled lines, and CI is green on every workflow.

## Spec Change Log

- 2026-11-06 (spec gate, runner): the Planner's PUBLIC TEXT ruling (exact strings; naming clash P1 with the finish-open condition) and the orchestrator's contention ruling (approach A allowed; `payloads.ts` regenerated only; Payloads.cls plain union, higher count) written into Design Notes. Item 3's "Simulated phone" verified as `DEVICE_TEXTS.phoneTab` (device-view.ts:19). Flake classes for this story's runs: DW-349, DW-376, DW-396, DW-414, DW-333, DW-415, DW-462, DW-471, DW-497, DW-550, DW-555, DW-764, DW-772, DW-774, DW-453, DW-670 (GuideApi).

## Review Triage Log

## Design Notes

**Architecture decisions** (spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`, status final):
- **AD-12** (L393): the guide payload stays the server's: `Guide.Compute` alone. The catalog rides `guide.state` and `/v1/state`, and the TS interface is generated by `payloads.mjs` (L399). Progress, the finish and Break the feed availability are unchanged.
- **AD-29** (L960): `STUB = 1` marks every unbuilt production item, so the memory and documents probes read the spine's own signal, not a guess. Lane B files only.
- **AD-33** (L1065): `GuideState` is Lane B's payload with one publisher (`Live.Publish` hook, L1383). A property is not a new type, so the ownership tables are unchanged.
- **AD-28** (L949): item 1's "Is anything wrong right now?" is answered by `check_status`'s code-built sentence. No text claims an all-clear.
- **AD-13** (L408) and **AD-10** (L344): item 2's email is untrusted and decided live; the look-for says only what the decision shows.
- **AD-20** (L652): item 5's send counts against the allowance; item 2's chip keeps the email limit.
- **AD-22** (L763): no mock change.
- **Conventions:** L1130 Announcements and focus; L1155 Angular; L1159 Tests.
- No AC contradicts an AD's Rule. No NFR trips Rule 5.

**Open question for the orchestrator: contended edits (Rule 11 (c)).** Every route to a server-built list needs a contended file:
- **(A, planned)** One property on `GuideState`. It needs two contended lines: the GuideState contract in `Test/Live/Payloads.cls:989-1000` (one line after `:1000`; `TestContracts` `:77-96` asserts each class has exactly its contract), and the generated `web/src/app/live/payloads.ts:259-269` (one line after `:268`; `payloads.test.mjs:54-58` fails a stale file). Epic 39 edits both, adding the Heartbeat payload's contract and interface and the count 31 to 32.
  - Proposed plain union at the merge: keep both sides' added lines in `Payloads.cls` (Epic 39's count), then regenerate `payloads.ts` with `npm --prefix web run payloads`. The two additions touch different blocks.
- **(B)** A top-level `/v1/state` key needs `Web/Api.cls` `StateBody` (`:939-979`) and its key pin `Test/Web/Api.cls:132`: three contended files, and Epic 39's largest. Rejected.
- **(C, fallback if A is refused)** No server change: the registry gains `available: boolean` per item, true for 1-4 and false for 5-7, and each later epic flips its own line. That is the story's named fallback, "one line per item when its epic merges".
  - Under C, drop the server tasks, `Test/Demo/Features.cls`, K1 and AC3's server half. AC4 becomes "flipping the line shows the item".
- **The spec says which was built: A (RULED 2026-11-06 by the orchestrator: approach A allowed).** Add the read-only `OcuTalon.Demo.Features` class and `GuideState.Features`; in `Test/Live/Payloads.cls` add the one contract line; `web/src/app/live/payloads.ts` is changed ONLY by `npm --prefix web run payloads` (never hand-edited or hand-merged; after any union, regenerate it and rerun the payloads tests). At a merge with Epic 39, `Payloads.cls` is a plain union taking the higher class count; whoever integrates second does the union. Fallback C is not built.

**Naming clash (a proposal for the ruling; the existing line is not changed on the stage's own call):**
- **P1 (recommended).** In the finish, the line "More to try: simulate an incoming email in the simulated mailbox and see what OcuTalon decides. On your own install, ask it to watch any production." (`guide-view.ts:60`, `demo-guide.ts:198`) gives way to the panel.
  - Why: the panel's items 2 and 4 say the same things with a button each, and the row's new link takes the name "More to try" for the panel it opens.
  - `GUIDE_TEXTS.moreToTry` and its pins go (Code Map, "Ruling P1 only").
- **P2.** The line stays where it is, and the panel follows it. Only the placement checks change (K2, `more-to-try-sources` (b): after `.more`), and the P1-only pins stay.

**Public text (RULED 2026-11-06 by the Contest Planner under the owner's delegation, relayed by the orchestrator; exact, verbatim).** The implement stage uses exactly these strings, pins every one with fixed-strings tests (`more-to-try-view.test.mjs`, `ux-strings.test.mjs`), and writes them into EXPERIENCE.md and DESIGN.md with the marker `[ADDED 2026-11-06, Story 4.11, owner decision made by the Contest Planner under the owner's delegation]`. Any other wording change is a new `## Clarification Needed` beginning `PUBLIC TEXT:` (implement: a HALT, never a change of its own). Straight ASCII double quotes inside the strings exactly as shown.
- Link (row 1, after "About 2 minutes", before Hide guide, with `aria-expanded`): `More to try`
- Panel label (a labelled group, not a heading): `Other things to try`
- Item 1 (`persona`):
  - label `Change how OcuTalon talks`
  - look-for `In the Persona card, choose Pirate, or Another language and then Spanish, and press Save. Then ask "Is anything wrong right now?" and look for the new style in the replies. The check results under them are written by OcuTalon's code, so they stay the same in any style.`
  - button `Go to the Persona card`
- Item 2 (`suspiciousEmail`):
  - label `Send a suspicious email`
  - look-for `This sends "Sample: suspicious request" to the Simulated mailbox. The email asks OcuTalon to resend every failed order and approve pending requests. Look for its decision and the reasons under it: nothing is resent or approved.`
  - button `Send the suspicious email`
- Item 3 (`rejectFix`):
  - label `Reject a fix`
  - look-for `This presses Break the feed again. OcuTalon usually notices within a minute. When the fix waits for your approval, press Reject in the chat or on the Simulated phone, and look for "Nothing was changed."`
  - button `Break it again`
  - "Simulated phone" is the tab's exact visible text: `DEVICE_TEXTS.phoneTab`, `web/src/app/devices/device-view.ts:19` (checked by the runner 2026-11-06; pin it in `more-to-try-view.test.mjs` (c)).
- Item 4 (`demoView`):
  - label `See the page as on your own install`
  - look-for `The demo guide, Break the feed and the Simulated devices are hidden, as on your own install. Turn Demo view back on in the top bar to return.`
  - button `Show the page without the demo`
- Item 5 (`memory`, hidden until its feature is present):
  - label `Ask it to remember something`
  - look-for `This sends "Remember that the Results partner's contact is Lee." Later, ask "Who do I call about Results?" and look for the answer it remembered.`
  - button `Ask it to remember`
  - sends (`rememberPrompt`) `Remember that the Results partner's contact is Lee.`
- Item 6 (`documents`, hidden until its feature is present):
  - label `Ask about a document`
  - look-for `On the Documents page, add a short file, such as a runbook (nothing personal: Visual Trace on the demo is shared). Then ask about it in the chat and look for the citation under the answer.`
  - link `Open the Documents page`
- Item 7 (`heartbeat`, hidden until its feature is present):
  - label `Run a heartbeat check-in`
  - look-for `In the Heartbeat checklist card, write what to check and press Run the heartbeat now. Look for the check-in's outcome and its cost in the card.`
  - button `Go to the Heartbeat checklist card`
- **Naming clash: P1 RULED.** The finish line `More to try: simulate an incoming email in the simulated mailbox and see what OcuTalon decides. On your own install, ask it to watch any production.` (`guide-view.ts:60`, `demo-guide.ts:198`) is removed, with its pins (Code Map "Ruling P1 only"), replaced by pins for the panel. CONDITION (ruled): in the finish state the panel shows OPEN exactly where that line was (after `.finish-links`, before the Try it yourself row); everywhere else it is closed until the link is pressed. This is the Open state already planned (`open = chosen() ?? finished`).
- **Accessible names and announcements.** The group is named by the panel label. Each control is named by its visible text, and the link carries `aria-expanded`. No new announcement.
- **Name-collision check (Never list).** The ruled control texts contain none of the Never list's names except one: "Send the suspicious email" contains the chat's and the guide's "Send". The ruling is exact, so the text stays: the implement stage checks every e2e locator that finds a control named "Send" (`getByRole('button', { name: 'Send' })` and similar) and makes it `exact: true` or scoped to its own region where it could also match the panel's button, within the footprint (only `web/e2e/**` files that are not contended; a contended one is a HALT). The Never list's "Send" entry is replaced by this rule, and `more-to-try-view.test.mjs` (e) exempts exactly that one pair.
- **On-screen names quoted, with their sources:** "Persona" (the card's heading; the ruling's "Persona card" names the card) `rail/rail-view.ts:56`; "Pirate" `rail/persona-card/persona-card-view.ts:46`; "Another language" `persona-card-view.ts:48`; "Spanish" `persona-card-view.ts:24`; "Save" `persona-card-view.ts:22`; "Is anything wrong right now?" `chat/try-it-view.ts:12`; "Sample: suspicious request" `mailbox/mailbox-view.ts:55`; "Simulated mailbox" `devices/device-view.ts:20`; "Simulated phone" `devices/device-view.ts:19`; "Simulated devices" `devices/device-view.ts:18`; "Break the feed" `feed/break-feed-view.ts:23`; "Reject" `phone/phone-view.ts:108` and `approvals/approval-view.ts:43`; "Nothing was changed." `msg/catalog.ts:28` and `guide/guide-view.ts:41`; "Demo view" `header/demo-view-texts.ts:12`; "Documents" `header/header-nav.ts:24`. Planned names, not on screen yet: "Heartbeat checklist", "Run the heartbeat now" (Story 39.5; re-checked by the orchestrator at Epic 39's merge, not this story).

**Integration ACs (Rule 1):**
- Matrix 4 (AC3): the consumer `DemoGuide`'s panel reads `Demo.Features.Present()` through the real `/v1/state` on `live:sign-in` and shows exactly those items.
- Matrix 5-8 (AC5): each item's consumer effect is the real control's own request or state, on the real page.

**Consumed-by:**
- this story's panel;
- Story 19.3 (memory), Story 19.4 (documents) and Epic 39 (Run now): their own classes make items 5-7 appear, with no code here.
- A later demo-only list reuses `MORE_TO_TRY_ITEMS` and `itemsFor`, and never copies them.

**Consumes:**
- 4.9 `DemoView`;
- 4.7 the finish, `FINISH_PARTS` and the focus rule;
- 4.10 `TryItRow`'s guard and `turnInFlight`;
- 4.6 the sample chips and `chipName`;
- 4.4/4.8 the Break the feed box;
- 40.4 the Persona card;
- 2.15 `Layout.focusRegion`;
- 4.5 `DeviceTabs`;
- 34.2 the Documents route;
- 2.5 `ChatOutbox`;
- 16.9 `AllowanceState`.

**Rule 2 (extend, don't copy):**
- The hand-off extends `DemoGuide.showMe()` (`:641-653`), which selects a tab and focuses a sibling's element after the next render, and its `BREAK_FEED_BUTTON` selector, which is reused, not repeated.
- Item 5's guard reuses `turnInFlight` and the allowance check of `TryItRow.press`.
- `itemsFor` sits beside `try-it-view.ts`.
- `Demo.Features` uses the `%ExistsId` idiom of `Install/Step/Tools.cls`.
- One copy is justified: the routed-guide helpers of `guide/guide.spec.ts` (`guideOf`, `serve`), because a spec cannot import another without running its tests, and `support/*` gains nothing for one file.

**Ledger (Rule 17):** the inbox is empty, and this story owns no entry.

**Epic context:** the committed `epic-4-context.md` was reused, and no planning file is newer.

**Footprint extensions** (outside the stated footprint, in no contended list; for `footprint_extensions:`):
- `Live/Payload/GuideState.cls` and `Demo/Guide.cls` (Lane B, Epic 4's own);
- `Test/Demo/Features.cls`;
- the pins of the old shape listed in the Code Map (existing web tests);
- `web/scripts/announce-focus-sources.test.mjs`.
- `api-types.ts` is not touched.

**Decided in-stage** (unattended: small, reversible, within the intent):
1. **The hand-off presses the real control** (focus, then `click()`), rather than calling its API. That is the only way to act "exactly as the existing control does", including the email limit, the inactive box, the chip's announcement and the persona card's own disclosure. Precedent: `showMe()` and the guide's focus rule already reach sibling components by selector.
2. **Items 1-4's catalog entries.** `suspiciousEmail`, `rejectFix` and `demoView` are constant, because no instance has this class without them. `persona` probes Epic 40's `SetPersona`.
3. **The probes.**
   - Memory and documents read `STUB`, the spine's marker for an unbuilt item. So Epic 34's Documents page (with `Docs.Ops` still a stub) and `Memory.cls`'s sign-out stub never count.
   - The heartbeat reads `RunHeartbeat`, which arrives with Epic 39 as a whole on the feature branch. Inside Epic 39's own worktree, item 7 may show between 39.2 and 39.5; its button only focuses the rail. Accepted.
4. **No e2e asserts "items 5-7 absent" unconditionally.** K1 asserts "shown = the server's list", and Task 0 records the list on this branch. A hard absence pin would turn the feature branch red the moment Epic 19 or 39 merged.
5. **Items 5-7 are built now** with actions that exist today: a chat send, the Documents route, the rail. So the later epics need no client change. Their texts are hidden proposals for the ruling.
6. **A labelled group with a list, not a heading** (the pinned heading lists). The link is a link-styled `<button>` with `aria-expanded`, a disclosure, like the box's "Do step 1" button.
7. **Open state.** Open by default in the finish (the story's "when the 5 steps are done"). An item's press keeps it open, so item 3, which ends the finish, leaves the list in view. A new finish opens it again.
8. **The e2e home is `web/e2e/guide/more-to-try.spec.ts`** in `live:sign-in` (browser group), beside the guide's own specs. A new file in an existing folder needs no `playwright-projects.test.mjs` edit. The POSTs of items 2, 3 and 5 are routed, because their downstream flows are pinned on the real stack by `demo-path/08-quiet-outcomes.spec.ts:73-100` and `07-failure-paths.spec.ts:83-97`.

**Veto items:** the public text, handled by the Public text section above. Nothing touches security, roles, a stored table (`GuideState` is a `%RegisteredObject` payload), a dependency, an AD or a PRD guarantee.

**Expected CI cost (inference):**
- `live:sign-in` gains 10 routed or light cases, about 40-70 s on CI. The browser group goes from about 1,680 s (Planner's split, 2026-11-05; units 628/575 s, `groups_max=29.2min`) to about 1,750 s, under REL-4's 35 minutes.
- `shard:lane-b` (image, about 1,740 s) gains one class of about 1 s.
- `live:floor` (shards-3, about 1,890 s) gains no case.

## Verification

`<B>` means `OCUTALON_LOCK_DIR=/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=4 stage=<stage>'`, run from the worktree root.
- **Tags:** fresh `e4s11i`; warm `e4s11iw`; QA `e4s11q`; review `e4s11r`.
- **One command per foreground call** (`timeout: 600000`), and one `iris_execute_tests` per message.
- **Slot B is not needed.** If an IRIS MCP call is made, it uses `server` `ocutalon-slot-b` and namespace `OCUTALON`, checked first with `iris_server_info`.
- **Flakes** (one rerun and an `occurrence=` note; a second red on the same head is real): DW-349, DW-376, DW-396, DW-414, DW-333, DW-415, DW-462, DW-471, DW-497, DW-550, DW-555, DW-764, DW-772, DW-774, DW-453, DW-670.

**Commands:**

`(loop)`:
- `npm --prefix web test` -- expected: every node test passes, including `more-to-try-view`, `more-to-try-sources`, `ux-strings`, `guide-view`, `try-it-sources`, `demo-view-sources`, `announce-focus-sources`, `floor-sources`, `shell-styles`, `payloads` (`--check`) and `playwright-projects`.
- `npm --prefix web run lint` -- expected: exit 0.
- `<B> OCUTALON_RUN_TAG=e4s11iw ci/warm.sh up` once. Then one per call:
  - `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e4s11iw ci/iris.sh class OcuTalon.Test.Demo.Features`, then the classes `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Demo.Guide` and `OcuTalon.Test.Web.GuideApi` -- expected: each passes.
  - At the stage's end, also after a failure: `<B> OCUTALON_RUN_TAG=e4s11iw ci/warm.sh down`.
- `<B> OCUTALON_RUN_TAG=e4s11i ci/iris.sh build` -- run before any live unit, and again after any `web/` or class change.
- `<B> OCUTALON_RUN_TAG=e4s11i ci/iris.sh live sign-in --part 2/3` -- expected: PASS. Its PART line must list `guide/more-to-try.spec.ts`; if it does not, run the part that does. About 5 min; record K1-K10 and Task 0 (a) and (b).
- `<B> OCUTALON_RUN_TAG=e4s11i ci/iris.sh live floor` -- expected: PASS in all three engines, with M1, M9, M10 and M14 updated. About 7 min; record Task 0 (c).

`(once)`:
- `<B> OCUTALON_RUN_TAG=e4s11i ci/iris.sh live sign-in --part 1/3`, then the remaining part, one per call -- expected: PASS (guide.spec Q1 and Q11, persona-card.spec, chat/try-it.spec).
- `<B> OCUTALON_RUN_TAG=e4s11i ci/iris.sh live demo-path` -- expected: PASS (UJ-1). 06's finish holds the panel, and 07's Break the feed in the finish still presses the box's button.
- `<B> OCUTALON_RUN_TAG=e4s11i ci/iris.sh live demo-switch` -- expected: PASS in both modes.
- `<B> OCUTALON_RUN_TAG=e4s11i ci/iris.sh shard lane-b`, then `--reverse` -- expected: PASS. If a call nears 8 minutes, run `--part 1/2` and `--part 2/2` instead.
- `bash docker/tests/test-web-build.sh` and `bash ci/checks.sh`, one per call -- expected: pass.
- `git diff --stat 957eb1d15ae28856763b57e94883d8feea07f404 -- ci/mock src/ocutalon/cls/OcuTalon/Web/Api.cls src/ocutalon/cls/OcuTalon/Live/Publish.cls web/src/app/api/api-types.ts` -- expected: empty.
- `git diff 957eb1d15ae28856763b57e94883d8feea07f404 -- src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls web/src/app/live/payloads.ts` -- expected: exactly the two ruled lines.
- At the end, also after a failure: `<B> OCUTALON_RUN_TAG=e4s11i ci/iris.sh teardown`.

**Planned mutations (Rule 19).** Apply each one, observe red, revert, and confirm that `git status --short` and `git diff --stat` are unchanged. Rebuild where `web/` or a class changed. Record each as `mutation: … → …`.
- **AC1:**
  - `open` is `chosen() ?? false` → K2 and `more-to-try-sources` (b);
  - two registry entries swapped → `more-to-try-view` (a) and K2.
- **AC2:** the link's handler leaves `chosen` unchanged → K4.
- **AC3:** `View` drops `Features` → `Test.Demo.Features` (c) and K1.
- **AC4:**
  - `Ids` ignores the memory flag → `Test.Demo.Features` (a);
  - `itemsFor` keeps only the first four entries → `more-to-try-view` (b).
- **AC5:**
  - item 2's selector names `SAMPLES[0]` → K6 (wrong POST);
  - item 3 calls nothing → K7;
  - item 4 presses regardless of `aria-checked` → K8, after a second press;
  - item 1 always clicks Change → K5, when the card is already open.
- **AC6:**
  - the link placed after Hide guide → K4's Tab order and `more-to-try-sources` (b);
  - `'moreItem'` removed from `FINISH_PARTS` → `more-to-try-sources` (b).
- **AC7:** the panel rendered outside `DemoGuide`'s gate → K10.
- **AC8:**
  - one word of a ruled string changed in EXPERIENCE.md → `ux-strings`;
  - "Pirate" changed in a look-for → `more-to-try-view` (c).
- **AC9:** a `Set ^` added to `Features.cls` → `Test.Demo.Features` (d).

**Shared surfaces:**
- the guide's row 1 controls and Tab order (floor M1, guide Q1 and Q11);
- the finish's content, order and focus parts (floor M9, M10 and M14; `chat/try-it.spec.ts` Y1; `try-it-sources`; `FINISH_PARTS`);
- the guide payload's contract (`Test.Live.Payloads`, generated `payloads.ts`);
- the guide's JSON in `/v1/state` (`Test.Web.GuideApi` compares it with `Compute`, so it is unchanged);
- the UX string inventory (`ux-strings` `IMPORTED` and `SOURCES.ux`; `guide-view.test.mjs` `GUIDE_TEXTS` under P1);
- the focus and `afterNextRender` lists (`announce-focus-sources`);
- the demo-view source rule (`demo-view-sources`, unchanged);
- the persona card's open state (K5 collapses it);
- the tab choice in localStorage and the switch in sessionStorage (each case's own page context; K8 runs last in its context).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan summary.**
- **Server:** a read-only `OcuTalon.Demo.Features` lists the instance's feature ids, from compiled classes and the `STUB` contract. They ride `GuideState.Features` through `Guide.Compute`, demo mode only, with no new route or write path.
- **Client:** a registry of all seven items. `app-more-to-try` shows the server's ones, in the finish by default and through a new "More to try" link in row 1. Each button focuses and presses the real control.
- **For the lead:** two items. The contended two-line edit (`Test/Live/Payloads.cls:1000` and the regenerated `payloads.ts:268`) goes to the orchestrator; the fallback is C. The public text and the naming clash (P1 recommended) go to the Planner's ruling.
