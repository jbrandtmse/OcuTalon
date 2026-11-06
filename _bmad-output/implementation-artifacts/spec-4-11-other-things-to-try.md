---
title: 'Story 4.11: Other things to try'
type: 'feature'
created: '2026-11-06'
status: 'in-review'
baseline_revision: '49be23afafd49035d9619d59d3f865af3c462fbb'
baseline_commit: 'efc62bca8c6205e3b3162ed3df04472061edbed3'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      Q11 (guide spec) was relaxed from "row 1 fits one line at 1280px" to "at most two lines, label and steps on the first", because the ruled "More to try" link makes row 1 about 34px wider than the Linux host's 896px.
    evidence: |-
      Measured by the implement stage: children 930px of a 896px row on the Linux throwaway (live:sign-in). On macOS the row may still fit one line. Decision for the lead: keep the relaxation, or trim row 1 (for example the link's padding or the gaps) and restore the one-line pin; the placement of the link is ruled, so the fix is in the row's other spacing.
    location: >-
      web/e2e/guide/guide.spec.ts Q11; web/src/app/guide/demo-guide.ts .row1 and .more-link
    severity: medium
  - summary: >-
      Items 2 and 3 (the mailbox chip and Break the feed) hand off by selector; whether their targets are on the page in the drawer and stacked layout bands is unverified.
    evidence: |-
      K6 and K7 run at the default viewport only. Settle it by running them at 1100x720 and 800x720: if the Simulated devices column or the box is not on the page there, the press finds nothing and does nothing.
    location: >-
      web/src/app/guide/more-to-try.ts press (suspiciousEmail, rejectFix)
    severity: medium (unverified)
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

### Review Findings

Code review 2026-11-06 (four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; full tier). Fix-risk and Rule 15 disposition on each.

- [ ] [Review][Patch] HIGH: the Other things to try panel, open by default in the finish, squeezes the chat to 0px at every desktop size [web/src/app/guide/demo-guide.ts:209, web/src/app/guide/more-to-try.ts:70] — measured (Verification, code review pass): at 1280x800 the guide grows from 280px to 639px and the chat's visible height falls from 338px to 0px; at 1024x768, 1280x650 and 1280x600 the chat is 0px as well and the page scrolls. Task 0 (c) asked for this measurement and its "fix the panel's own layout within the footprint" rule applies; no floor case pins the chat's height in the finish, so floor stayed green. Fix in the rework: keep the ruled placement, text and open-in-the-finish condition, and change the panel's own layout (for example a denser item layout and a bounded, keyboard-scrollable panel within DESIGN.md's tokens) so the chat keeps a usable visible height in the finish in the wide, drawer, stacked and compact bands; add an e2e case that pins the chat's visible height in the finish with the panel open (mutation: the bound removed -> red), and rerun `live floor`. If no panel layout keeps the chat visible, HALT with a clarification (Task 0). Fix-risk high (layout across four bands and three engines). Footprint in-story. Rule 15: HIGH, rework.
  - [ ] [Review] Rework targets (lead, rework iteration 1, decided under the unattended rules: implementation numbers, not product targets): (a) no whole-page scroll in any band with the panel open in the finish (DESIGN.md:677, "the page fills the viewport rather than scrolling as a whole"); (b) the chat's visible height in the finish with the panel open is at least 160px at 1280x800 and 1024x768, and at least 96px at 1280x650 and 1280x600 (the compact band), and never 0 in the drawer and stacked bands; (c) the panel stays OPEN in the finish where the old line was, with the ruled strings complete and unclamped (no truncated or hidden look-for text): bound it (a max-height with its own vertical scroll, and a denser item layout such as a two-column grid at wide widths) so its controls scroll into view on Tab; if the bounded container itself scrolls, it is keyboard-reachable (`tabindex="0"`, named by the panel label) per the project's scroll-region rule; (d) a new e2e case (floor or `guide/more-to-try.spec.ts`) pins (a) and (b) at those sizes with a `mutation:` line (the bound removed -> red), and `live floor` is rerun in all three engines; (e) if no panel layout meets (a)-(c) without changing a ruled string, the placement or the open-in-the-finish condition, HALT `blocked` with an `intent gap` naming the band and the numbers (the runner takes it to the Planner).
  - [ ] [Review] AMENDED rework targets (lead ruling 2026-11-06 after the rework pass's intent gap; ruling category=veto, inbox U-296; they replace target (b) above; the rulings on strings, placement and open-in-the-finish stay): (b1) outside the compact height band (viewport height 680px and over), the chat's visible height in the finish with the panel open is at least 160px at 1280x800, 1024x768 and 1100x720 (lower the non-compact reserve as needed); (b2) in the compact height band (under 680px tall: 1280x650, 1280x600), the chat keeps at least 64px; (b3) at every framed size the panel's scroll window shows at least its label line plus one complete control (about 64px), so every control scrolls fully into view on Tab; (a) no whole-page scroll and (c)-(d) as above. Pin (b1)-(b3) and (a) in K16 at 1280x800, 1024x768, 1100x720, 1280x650 and 1280x600 (and the stacked band's own contract), with `mutation:` lines for the bound, the reserve and the window minimum. K16's 1100x720 row asserts the 160px of (b1), matching DESIGN.md.
  - [ ] [Review] From the rework pass's own review (MED, fix in this pass): the panel group gets a `data-guide-focus` key handled by the focus rule (`FINISH_PARTS`), so focus held by the scrolling group is handed on when the finish ends; the grid's `minmax(20rem, 1fr)` becomes overflow-safe at 320px (e.g. `minmax(min(20rem, 100%), 1fr)`); pin the grid and the stacked-column contract (a source or e2e assertion), and write a `mutation:` line for every behaviour this pass changed. Also measure the chat height when the link opens the panel before the finish (prompt branch) at 1280x800 and 1280x600, and hold it to (b1)/(b2) and (b3) the same way.
- [x] [Review][Patch] MED: K14 pressed before the Persona card's failed read was answered [web/e2e/guide/more-to-try.spec.ts:568] — the case now counts the routed `/persona` answers and waits for one before the press (Rule 19 readiness). Fix-risk low. Fixed.
- [x] [Review][Patch] LOW: item 1 pressed Change only when `aria-expanded` was exactly `"false"`; Always 1 says "not `true`" [web/src/app/guide/more-to-try.ts:157] — now `!== 'true'`. Fix-risk low. Fixed.
- [x] [Review][Patch] LOW: the FOCUS_RULE contract comment did not list the panel's controls among the finish's parts, nor say that a panel still on the page takes focus at its first control [web/src/app/guide/demo-guide.ts:62]. Fix-risk low. Fixed.
- [x] [Review][Patch] LOW: Q11's doc comment narrated the story's history (Rule 14) [web/e2e/guide/guide.spec.ts:633] — rewritten as the contract. Fix-risk low. Fixed.
- [x] [Review][Patch] LOW: Q9's doc comment still said "Q11 pins that fit"; where row 1 already wraps at the normal size (Linux) Q9's wrap poll holds at once and its "nothing past the row" checks carry it [web/e2e/guide/guide.spec.ts:662] — comment corrected. Fix-risk low. Fixed.
- [x] [Review][Patch] LOW: no test checked that the link's `aria-controls` names the panel [web/e2e/guide/more-to-try.spec.ts:197] — K2 now asserts the id holds the "Other things to try" group. Fix-risk low. Fixed.
- [x] [Review][Defer] MED: DW-804, Q11 relaxed from one line to at most two [web/e2e/guide/guide.spec.ts:637] — deferred: kept by design. The review's arithmetic (Verification) shows trimming row 1's spacing cannot recover the 34.2px without changing the other controls or the ruled placement; the reason is Decided 9. Fix-risk high. DW-804 is this story's entry; the lead closes it at adjudication.
- [x] [Review][Defer] LOW: item 5 repeats TryItRow's send guard (`used`, `blocked`, `describedBy`) rather than sharing one helper (Rule 2, weak reason) [web/src/app/guide/more-to-try.ts:143] — deferred: DW-809 `wontfix-accepted`, reopen_if a third guard appears or TryItRow's guard gains a condition. Fix-risk med (the change touches 4.10's allowance-sources pins).
- [x] [Review][Defer] LOW: Demo.Features' MEMORY, DOCUMENTS and HEARTBEAT names cannot be killed by a test on this branch [src/ocutalon/cls/OcuTalon/Demo/Features.cls:17] — deferred: DW-810 `wontfix-theoretical`; the test's own probes turn red at the merge of 19.3, 19.4 or Epic 39. Fix-risk low.
- [x] [Review][Defer] LOW: item 6, the Documents link, does not activate with Space [web/src/app/guide/more-to-try.ts:54] — deferred: DW-811 `by-design`; Always 6 names a native `<a routerLink>` and the sources test forbids `(keydown`. Fix-risk med.

Rejected:
- false: (edge) focus drops to the body when the finish begins with focus in the prompt-bar panel. The finish's panel carries the same `moreItem` key, and a null `whenGone` falls through to the main region.
- false: (edge) a reordered SAMPLES makes item 2 press another chip silently. K6's POST path and `more-to-try-view` (c), which pins `SAMPLES[2].label`, both go red.
- false: (acceptance) M13 was weakened. The conversation-link check still covers the whole finish, and the scope now names the finish links, its subject.
- false: (acceptance) EXPERIENCE's finish-list Try it yourself bullet was not reworded. The panel bullet before it states "before the Try it yourself row".
- false: (acceptance) the Payloads.cls diff has two lines. The `Run` line's comma is required by the JSON of the ruled line.
- low: (blind) focus goes to the panel's first control rather than the same one when the panel moves between placements. Rare (it needs focus in the panel while the finish comes or goes by itself), and the spec gives every control the one `moreItem` key.
- low: (blind) items 1 and 7 are not run in every narrow band. `focusRegion` is Layout's own, K5b covers item 1 in the drawer band, and item 7 is hidden here.
- low: (edge) Test.Demo.Features would raise INVALID OREF if `features` were missing from the JSON. That still fails loudly.
- low: (verification) item 4's `aria-checked` guard cannot be reached. Already by design in the mutation results.
- low: (acceptance) `more-to-try-view.ts` also exports `BREAK_FEED_BUTTON` and two types. That is Rule 2's reuse, with no named harm.
- low: (acceptance) K5's cleanup closes Change by click rather than Esc. It is only cleanup.
- low: (acceptance) Enter and Space are pressed on only some controls. They are native buttons, and K4 covers both keys on the link.
- spec edit: (blind, verification, acceptance) DW-805 and the Auto Run Result are stale after QA, and the frontmatter `deferred` still says "unverified". The fix edits the spec's machine sections, and the lead closes DW-805 at adjudication.

## Spec Change Log

- 2026-11-06 (rework iteration 1, re-dispatch after the review-step intent gap, lead): the panel-bound attempt (`4-11-rework-1-panel-bound.patch`) is re-applied and the spec set `in-review`; target (b) amended to (b1)-(b3) by the lead's veto-window ruling (inbox U-296): chat floor 64px in the compact height band, 160px elsewhere, and a panel window of at least one label line plus one control at every framed size. The open-in-the-finish ruling, the placement and the ruled strings are unchanged.

- 2026-11-06 (rework iteration 1, lead): code review found one HIGH (the panel open in the finish squeezes the chat to 0px; Task 0 (c) had not been measured). Spec re-opened `in-progress`; the work is the unchecked `[Review]` items only (the HIGH and its rework targets). DW-805 is resolved by QA's K12/K13 (closed at adjudication); DW-804 kept by design per the review's arithmetic (Decided 9).

- 2026-11-06 (spec gate, runner): the Planner's PUBLIC TEXT ruling (exact strings; naming clash P1 with the finish-open condition) and the orchestrator's contention ruling (approach A allowed; `payloads.ts` regenerated only; Payloads.cls plain union, higher count) written into Design Notes. Item 3's "Simulated phone" verified as `DEVICE_TEXTS.phoneTab` (device-view.ts:19). Flake classes for this story's runs: DW-349, DW-376, DW-396, DW-414, DW-333, DW-415, DW-462, DW-471, DW-497, DW-550, DW-555, DW-764, DW-772, DW-774, DW-453, DW-670 (GuideApi).

## Review Triage Log

### 2026-11-06 — Review pass
- verdicts: 36 findings — high 0, medium 10, low 20, false 4, maybe-false 2
- findings:
  - `[low]` `[patch]` (blind) DESIGN.md says the link is `{typography.body-sm}` but the code uses the caption tokens — the code follows the row's other small text (duration); DESIGN.md now reads `{typography.caption}`, underlined like a link.
  - `[low]` `[reject]` (blind) The panel stays open after Run again when an item was pressed in the finish — spec-bound: Decided 7 keeps the list in view when item 3 ends the finish, and Always resets only on the rising edge of `finished`; K11 pins it.
  - `[low]` `[reject]` (blind) The link is a dead control when `features` is empty or missing — the real server always lists at least the three constants (Task 0 (a), K1); only a routed spec omits the field; the fix adds a branch for an unreachable case.
  - `[false]` `[reject]` (blind) Item 7 only focuses the rail and not the Heartbeat card — Always 7 and the ruled button text say exactly this; the card arrives with Story 39.5, re-checked at Epic 39's merge.
  - `[medium]` `[defer]` (blind) Q11 was relaxed from one line to at most two at 1280px instead of fixing the layout — real: the link makes row 1 about 34px wider than the 896px of the Linux host; fix-risk high (the row is shared, the placement is ruled); recorded under Decided in-stage 9 and deferred.
  - `[low]` `[reject]` (blind) Present() runs its probes on every Guide.View — four existence checks and two parameter reads per view; nothing measurable; a cache would need an invalidation on recompile.
  - `[false]` `[reject]` (blind) The probes hard-code class names that later epics might name differently — the names are the spec's and AD-29's (`STUB`); `TestPresentFollowsTheProbes` computes the same probes itself.
  - `[low]` `[reject]` (blind) `TestReadOnly` is a fragile substring scan — the spec asks for a source read (Tasks (d)); the `Set ^` mutation turned it red.
  - `[maybe-false]` `[defer]` (blind) Items 2 and 3 are untested in the narrow layout bands, where their targets may not be on the page — settled by running K6 and K7 in the drawer and stacked bands; if the devices column or the box is absent there the press does nothing.
  - `[false]` `[reject]` (blind) Item 4's press emits `pressed` on a component about to go away — the emit comes before the click and sets a signal of the same live component; the result is the panel open when the view returns, as Decided 7 has it.
  - `[medium]` `[patch]` (blind) The turn-in-flight case of item 5 and its `aria-describedby` are not tested — K9 now asserts aria-disabled and no second POST while the first turn is in flight, and the reason link while the allowance is used up; mutation `blocked` is `used()` only turned K9 red.
  - `[low]` `[reject]` (edge) carried: the panel stays open after Run again when an item was pressed — as the blind row: spec-bound.
  - `[low]` `[reject]` (edge) carried: the link shows with no items — as the blind row: unreachable on a real server.
  - `[low]` `[reject]` (edge) Item 1 falls back to the Persona heading, which is not focusable — only while the card has not loaded, and `focusRegion` has put focus on the rail; the spec names this fallback.
  - `[maybe-false]` `[defer]` (edge) carried: `handTo` ends silently when its target is not on the page — as the blind row on the narrow bands.
  - `[false]` `[reject]` (edge) carried: item 7 only focuses the rail — as the blind row: ruled.
  - `[low]` `[reject]` (edge) `outbox.send` returns false and the panel ignores it — `TryItRow` ignores it the same way and the composer path announces a failed send; a refused send is the outbox's own line.
  - `[low]` `[reject]` (edge) carried: Present() is not cached — as the blind row.
  - `[medium]` `[defer]` (edge) carried: Q11 relaxed — as the blind row.
  - `[low]` `[reject]` (edge) carried (claim): the choice resets only on a rising edge — as the blind row: spec-bound.
  - `[medium]` `[defer]` (edge) carried (claim): Q11 loosened beyond "only to the new shape" — as the blind row.
  - `[medium]` `[patch]` (verification-gap) The open-state transitions are pinned only by source-text regexes — K11 added (finish leaves, close then new finish, press then finish leaves); mutations rising-edge reset removed and `(pressed)` made a no-op each turned a K11 assertion red.
  - `[medium]` `[patch]` (verification-gap) `'moreItem'` in FINISH_PARTS is pinned only by a source regex — K11's first assertion (focus on Break the feed when the finish leaves); the mutation turned it red.
  - `[medium]` `[patch]` (verification-gap) Item 1 in the drawer band is untested — K5b added at 1100x720 (drawer opens, Change open and focused); the mutation of dropping `focusRegion` turned it red.
  - `[medium]` `[patch]` (verification-gap) K9 lacks the in-flight case and the `aria-describedby` assertion; the card-absent fallback is untested — the first two are in K9 now; the card-absent case is closed as a low reject (a path before the card loads, with the spec's fallback).
  - `[medium]` `[patch]` (verification-gap) `TestStubsAreNotFeatures` asserted the test class's own helper — rewritten to assert `Present()` against each stub, and listed-iff-built once a story builds one; the mutation `Built` returns 1 turned it red.
  - `[low]` `[patch]` (verification-gap) AC7 has no `mutation:` line — mutation: `liveView` read the ungated snapshot, K10 and K8 went red; line written.
  - `[medium]` `[defer]` (verification-gap) carried: Q11 weakened — as the blind row.
  - `[low]` `[reject]` (verification-gap) M13 counts the links of `.finish-links` only — with seven ids item 6 is a link in the panel; the cap's subject, the finish links, is unchanged.
  - `[low]` `[reject]` (verification-gap) K8's "no request" covers writes only — GET polls run all the time, so "no request" is not assertable; a write is the press's only possible effect.
  - `[low]` `[reject]` (verification-gap) K1 compares labels with the product's own `itemsFor` — `itemsFor` is pinned by `more-to-try-view` (b) and the ITEMS oracle of K2; K1's subject is the server list.
  - `[low]` `[reject]` (verification-gap) Fixed 500 ms waits before negative assertions — a negative assertion needs a dwell; each case acts only after the loaded snapshot.
  - `[low]` `[reject]` (verification-gap) carried: `TestReadOnly` is a static scan — as the blind row.
  - `[low]` `[reject]` (verification-gap) Item 4's `aria-checked` guard cannot be killed — by-design: the spec states the guard; the guide renders only while the switch is on; recorded in the mutation results.
  - `[low]` `[reject]` (intent-alignment) K1 and the row 13 check use `arrayContaining`, not equality with `Present()` — Test.Demo.Features (c) pins Compute and Blank to `Present()`, `Test.Web.GuideApi` pins /v1/state to Compute, and Decided 4 forbids a hard list in e2e.
  - `[low]` `[reject]` (intent-alignment) carried: the link stays when the list is empty — as the blind row.

### 2026-11-06 — Review pass (rework iteration 1)
- verdicts: 32 findings — high 2, medium 10, low 16, false 1, maybe-false 3
- findings:
  - `[low]` `[reject]` (blind) `tabindex="0"` on the group is unconditional, so it is an extra Tab stop in the stacked column and where the panel does not overflow — harmless extra stop; a conditional needs a viewport signal and a branch.
  - `[medium]` `[patch]` (blind) K16's 1100x720 row (drawer band, not compact) asserts 96px while DESIGN.md says 160px outside the compact band; the measured chat is 191.6px — moot under the intent gap; the row would assert 160.
  - `[low]` `[reject]` (blind) the 685px and 592px reserves are hard-coded estimates of the rest of the page — K16 goes red at five sizes when the page changes, so the drift is loud; a derived layout is outside the footprint.
  - `[high]` `[intent_gap]` (blind) at the small framed sizes the bound leaves the panel almost invisible (about 19px, the label line, at 1280x600; about 35px at 1100x720; about 58px at 1280x650), so target (c) "its controls scroll into view on Tab" cannot hold while target (b) holds — verified against the measured closed-panel chat heights (126px at 1280x600 against the 96px floor leaves 30px for the whole panel, a label line and a 36px control need about 64px). HALT, see the Auto Run Result.
  - `[maybe-false]` `[defer]` (blind) K16 covers only the finish with four ids; the panel opened by the link before the finish has a different guide height and the same reserve — settled by one measurement of the chat's height with the link-opened panel at the K16 sizes; if the chat falls under its floor, the reserve is wrong for that state. Medium if true (unverified).
  - `[medium]` `[patch]` (blind) the stacked K16 row asserts only `chat >= 1`, so "the stacked column grows and the page scrolls" has no behavioural check — moot; grouped with the verification-gap row on the stacked contract.
  - `[low]` `[patch]` (blind) DESIGN.md says "Widths follow the layout bands only" but the `auto-fill` grid follows the container's width, and `padding-inline` is undocumented — moot; the sentence would say so.
  - `[low]` `[patch]` (blind) `console.log` left in K16 as debug output — moot; it would become an annotation.
  - `[low]` `[reject]` (blind) the rework-target checkbox, the baseline mismatch and a Dev Agent Record entry are not in the diff — spec edit; the lead owns the checkbox and `baseline_commit` is the story's first baseline.
  - `[low]` `[reject]` (blind) the contract line "No `transition`, no fixed height" disagrees with the DESIGN.md amendment — the contract is read-only, and a `max-height` bound is not a fixed height.
  - `[medium]` `[patch]` (edge) `repeat(auto-fill, minmax(20rem, 1fr))` forces a 320px track, so a container narrower than 20rem (a 320px viewport in the stacked band) overflows horizontally — moot; `minmax(min(20rem, 100%), 1fr)`.
  - `[low]` `[reject]` (edge) carried: the reserve constants are estimates — as the blind row.
  - `[high]` `[intent_gap]` (edge) carried: the clamp to the label line at small heights makes the controls unusable — as the blind intent-gap row.
  - `[low]` `[reject]` (edge) carried: the static `tabindex` — as the blind row.
  - `[medium]` `[patch]` (edge) the new focusable group carries no `data-guide-focus` key, and `FOCUS_RULE` never sees it, so focus falls to the body when the finish leaves while the group holds focus — verified: only the two controls carry `moreItem`; moot; the group would carry the key.
  - `[low]` `[reject]` (edge) the focus ring of the last control can clip at the scroller's bottom edge — `scroll-padding` is the project's scroller rule (floor-sources) and the chat's list uses the same; the ring is 4px.
  - `[false]` `[reject]` (edge) in the 680-703px band the 685px reserve gives the chat less than 160px — the panel is then at its label floor, so the chat is about 190px or more (measured 214.8px at 800px with a 115px panel, so the rest of the page is about 470px).
  - `[maybe-false]` `[defer]` (edge) K16 has no wide, seven-item or link-opened rows — seven items are bounded by the same `max-height`, so only the link-opened state is open; carried with the blind row.
  - `[low]` `[patch]` (edge) carried (claim): "Widths follow the layout bands only" — as the blind row.
  - `[medium]` `[patch]` (edge) carried (claim): the 1100x720 row asserts 96px against a documented 160px — as the blind row.
  - `[medium]` `[patch]` (verification-gap) nothing pins the two-column grid at wide widths; putting `.items` back to a flex column keeps K16 green — moot; two items would share a `top` at the wide and drawer rows, with a `mutation:` line.
  - `[medium]` `[intent_gap]` (verification-gap) nothing stops the bound from being too tight (the reserve at 5000px keeps K16 green) — the missing pin is a minimum panel height, which is the number the intent gap leaves open.
  - `[medium]` `[patch]` (verification-gap) K16 measures once after a poll that passes at the first sample that clears a lower bound — moot; it would wait for two equal samples.
  - `[medium]` `[patch]` (verification-gap) the stacked contract (no nested scroller, the page scrolls) is only a source regex — moot; grouped with the blind stacked row.
  - `[medium]` `[patch]` (verification-gap) Rule 19: the grid, the compact reserve, the framed-only condition, `tabindex`, `scroll-padding` and the page-scroll assertion have no `mutation:` line — moot.
  - `[low]` `[reject]` (verification-gap) the source-text pins prove no rendered behaviour, and K16 runs in chromium only — K16 is the behavioural pin; `live floor` ran the finish in three engines and stayed green.
  - `[low]` `[reject]` (verification-gap) carried: the reserve constants — as the blind row.
  - `[low]` `[reject]` (verification-gap) carried: the static `tabindex` — as the blind row.
  - `[low]` `[patch]` (verification-gap) carried: `console.log` in K16 — as the blind row.
  - `[low]` `[reject]` (intent-alignment) the grid, the markup (`tabindex`, `ring-inside`) and the viewport-derived `max-height` depart from the contract's flex-wrap rows, plain group and "no fixed height" — rework target (c) directs the bound, the grid and the Tab stop, and a bound is not a fixed height.
  - `[maybe-false]` `[defer]` (intent-alignment) the reserves are calibrated to one fixture (four ids, finished, Break the feed active) and other guide heights are not exercised — carried with the link-opened row.
  - `[low]` `[reject]` (intent-alignment) the regex pins check that the declarations are written, not that they work — carried (verification-gap, source-text pins).

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
9. **Q11 (row 1 at 1280px) is relaxed, not widened (implement stage, kept by the review pass).** With the ruled link in row 1, the children take about 930px of the 896px that the Linux host gives the row (glyphs rounded to whole pixels), so row 1 cannot stay on one line without changing the row's other controls or the ruled placement. Q11 now pins "at most two lines, the label and the steps on the first, nothing past the row, the link visible"; Q9 and Q1 keep the rest. Reversible: a later layout change can restore the one-line pin. Deferred for the lead (item below).
10. **Added in the review pass:** K5b (drawer band), K9's in-flight and described-by cases and K11 (leaving the finish), all in `web/e2e/guide/more-to-try.spec.ts`; no new file, folder or CI unit.

**Veto items:** the public text, handled by the Public text section above. Nothing touches security, roles, a stored table (`GuideState` is a `%RegisteredObject` payload), a dependency, an AD or a PRD guarantee.

**Expected CI cost (inference):**
- `live:sign-in` gains 10 routed or light cases, about 40-70 s on CI. The browser group goes from about 1,680 s (Planner's split, 2026-11-05; units 628/575 s, `groups_max=29.2min`) to about 1,750 s, under REL-4's 35 minutes.
- `shard:lane-b` (image, about 1,740 s) gains one class of about 1 s.
- `live:floor` (shards-3, about 1,890 s) gains no case.

## Verification

`<B>` means `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=4 stage=<stage>'`, run from the worktree root.
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

**Mutation results (Rule 19, implement stage).** Each was applied, observed red, reverted, and the tree confirmed byte-identical.
- mutation: `open` is `chosen() ?? false` → `more-to-try-sources` (b) red; live: K2 red (with K1, K3, K9, try-it Y1).
- mutation: two registry entries swapped → `more-to-try-view` (a) red (6 failures).
- mutation: the link's handler leaves `chosen` unchanged → live: K4 red (with K1).
- mutation: `View` drops `Features` → `Test.Demo.Features` TestGuideCarriesTheCatalog red.
- mutation: `Ids` ignores the memory flag → `Test.Demo.Features` TestIds red (3 asserts).
- mutation: `itemsFor` keeps only the first four entries → `more-to-try-view` (b) red.
- mutation: item 2's selector names `SAMPLES[0]` → live: K6 red.
- mutation: item 3 calls nothing → live: K7 red.
- mutation: item 4 never presses → live: K8 red. The planned mutation "presses regardless of `aria-checked`" cannot be killed: the guide renders only while the switch is on, so no press can find the switch off. The guard is kept as the spec states it.
- mutation: item 1 always clicks Change → live: K5 red (the second press, with the card already open, closes it).
- mutation: the link placed after Hide guide → `more-to-try-sources` (b) red.
- mutation: `'moreItem'` removed from `FINISH_PARTS` → `more-to-try-sources` (b) red.
- mutation: one word of a ruled string changed in EXPERIENCE.md → `ux-strings` red.
- mutation: "Pirate" changed in a look-for → `more-to-try-view` (a) and (c) red.
- mutation: a `Set ^` added to `Features.cls` → `Test.Demo.Features` TestReadOnly red.
- mutation: AC7, `DemoGuide.liveView` reads the ungated `live.snapshot()` instead of the demo view's `demoView.snapshot()` -> live: K10 red (the link shows with the switch off), and K8 red (the guide stays after the switch is turned off).
- mutation: AC6/AC2 (review pass), `'moreItem'` removed from `FINISH_PARTS` -> live: K11 red at "focus went to Break the feed when the finish left".
- mutation: the rising-edge reset of `chosen` removed from `follow()` -> live: K11 red at "a new finish opens the panel again".
- mutation: `(pressed)` made a no-op (`chosen.set(this.chosen())`) -> live: K11 red at "the panel the press kept open stays" (alone, after the two above were reverted).
- mutation: item 5's `blocked` is `used()` only -> live: K9 red at "while its turn is in flight the control is aria-disabled".
- mutation: item 1 without `layout.focusRegion(RAIL_REGION)` -> live: K5b red at "the drawer is open" (K5 at 1280px stays green).
- mutation: `Demo.Features.Built` returns 1 whatever `STUB` says -> `Test.Demo.Features` TestPresentFollowsTheProbes and TestStubsAreNotFeatures red (warm stack; the class green again after the revert).
- All of the above were reverted: `shasum` of `demo-guide.ts` and `more-to-try.ts` and of `Features.cls` equal to before, and `git status --short` unchanged.

**Measured (Task 0, implement and review passes, lane B, ARM).**
- (a) `guide.features` on a fresh stack is `persona,suspiciousEmail,rejectFix,demoView` (K1 prints it): items 5-7 are hidden on this branch.
- (b) The sign-in stack is in demo mode (K1-K11 find the guide and the link on it).
- (c) Not measured as numbers: the guide's and the chat's heights at the three sizes were not recorded. `live:floor` passed in all 107 cases (M1, M9, M10, M13 and M14 updated, no floor rule weakened), so no floor layout case fails because of the panel.
- Final runs on the patched tree: `npm --prefix web test` 1487 pass; lint clean; warm `Test.Demo.Features`, `Test.Live.Payloads`, `Test.Demo.Guide`, `Test.Web.GuideApi` pass; `live sign-in` parts 1/3 (81), 2/3 (88, K1-K11) and 3/3 (71) pass; `live floor` 107 pass; `live demo-path` 28 pass (UJ-1; 5.5 min; the implement pass's three red runs were this host's time budget at a load average near 9.5, none on a test); `live demo-switch` all checks passed; `shard lane-b` forward (105 classes) and `--reverse` in two parts (53 and 52) pass; `docker/tests/test-web-build.sh` and `bash ci/checks.sh` pass; the contended-path guard commands print an empty diff and exactly the two ruled lines.

**QA pass (stage qa, tag e4s11q, lane B).**
- Files (QA): `web/e2e/guide/more-to-try.spec.ts` (K12 and K13 in the drawer band 1100x720 and the stacked band 800x720; K14; K15) and `web/e2e/guide/guide.spec.ts` (Q11 records row 1's measurements as an annotation and a log line; its assertions are unchanged).
- Gaps closed: DW-805 (items 2 and 3 reach the chip and the box in both narrow bands); matrix row 5's error handling (K14: card not loaded, focus on the Persona heading); matrix row 6's error handling (K15: email limit, tab selected, inactive chip focused and described by the limit, no second POST).
- Run: `live sign-in --part 2/3` PASS, 79 cases, with K1-K15 and Q11 green; `npm --prefix web test` 1487 pass; `npm --prefix web run lint` exit 0. Flakes: none hit.
- DW-805 result: both targets are reachable in both bands. No product change is needed.
- DW-804 measurement (Linux throwaway, 1280x800, Inter loaded): row 896.0px; children 930.2px including four 8px gaps (label 83.7, steps 552.8, duration 92.8, More to try 78.2, Hide guide 90.7); 2 lines; nothing past the row. The row is 34.2px short of one line.
- mutation (AC5, items 2 and 3 in the narrow bands): `this.tabs.select('mailbox')` removed -> K12 (both bands) and K15 red (with K6); item 3's hand-off replaced by a no-op -> K13 (both bands) red (with K7, K11).
- mutation (matrix 5 error row): the Persona heading selector removed from item 1's hand-off list -> K14 red.
- All three were applied in one build, observed red, reverted from a saved copy: `shasum` of `more-to-try.ts` equal to before, and `git status --short` and `git diff --stat` identical to before the mutation.

**Code review pass (stage code-review, tag e4s11r, lane B).**
- Task 0 (c), measured (Linux throwaway, routed finish with the four ids, a temporary case removed after the run; `app-chat-panel .list` visible height, the guide's height, the page's vertical scroll):
  - 1280x800: panel open (the finish default) guide 639px, panel 351px, chat 0px, page scrolls 21px; panel closed guide 280px, chat 338px, no scroll.
  - 1024x768: open guide 757px, panel 446px, chat 0px, scroll 185px; closed guide 303px, chat 269px.
  - 1280x650: open guide 840px, panel 540px, chat 0px, scroll 372px; closed guide 292px, chat 176px.
  - 1280x600 (compact band): open guide 840px, panel 540px, chat 0px, scroll 422px; closed guide 292px, chat 126px.
  - So the open panel in the finish takes the chat's whole height at every desktop size (review finding, HIGH).
- DW-804, the arithmetic: dropping `.more-link`'s inline padding (2 x 8px) and halving the four 8px gaps saves 32px of the 34.2px overrun; a one-line row 1 needs the other controls' spacing or the ruled placement changed. The relaxation of Q11 is kept as a consequence of the ruled text and placement (Decided 9).
- Run on the review's patched tree: `npm --prefix web test` 1487 pass; lint clean; `live sign-in --part 2/3` PASS (Q1, Q9, Q11, K1-K15 green). Flakes: none hit.

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

Status: blocked
Blocking condition: intent gap: with the ruled strings, placement and open-in-the-finish condition fixed, no panel layout meets rework targets (b) and (c) together in the compact height band and at 1100x720 (see Rework pass 1 below); the attempted change is saved as _bmad-output/implementation-artifacts/4-11-rework-1-panel-bound.patch and the code is reverted

**Summary.** The demo guide has an "Other things to try" panel with a "More to try" link in row 1. A read-only `OcuTalon.Demo.Features` lists the instance's feature ids (compiled classes and the `STUB` contract); `Guide.View` puts them in `GuideState.Features`, so they ride `/v1/state` and `guide.state` in demo mode only. A framework-free registry of seven items (`more-to-try-view.ts`) and `app-more-to-try` show the server's items in registry order: on this branch items 1-4 (`persona,suspiciousEmail,rejectFix,demoView`); items 5-7 appear by themselves when Epics 19 and 39 merge. Each button focuses and presses the real control. The panel is open in the finish, in the place of the old "More to try" line (ruling P1: `GUIDE_TEXTS.moreToTry` and its pins are gone), and closed elsewhere until the link is pressed. The ruled texts are used verbatim and are in EXPERIENCE.md, DESIGN.md and the C4 mockup with the 2026-11-06 marker.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Demo/Features.cls` (new): the catalog, `Present()` and `Ids()`; `Live/Payload/GuideState.cls` (`Features`); `Demo/Guide.cls` (`View` fills it).
- `src/ocutalon/cls/OcuTalon/Test/Demo/Features.cls` (new): catalog mapping, probes, stubs, Compute/Blank carry it, read-only source read; `Test/Live/Payloads.cls`: the one ruled contract line; `web/src/app/live/payloads.ts`: regenerated, one line.
- `web/src/app/guide/more-to-try-view.ts`, `more-to-try.ts` (new); `demo-guide.ts` (link, both placements, open state, `FINISH_PARTS`); `guide-view.ts` (finish line removed); `chat/try-it-row.ts` (comment).
- Tests: `more-to-try-view.test.mjs`, `more-to-try-sources.test.mjs` (new); `ux-strings`, `announce-focus-sources`, `guide-view`, `try-it-sources`, `allowance-sources` updated; `web/e2e/guide/more-to-try.spec.ts` (new, K1-K11 with K5b); pins of the old shape in `floor/guide.spec.ts` (M1, M9, M13), `guide/guide.spec.ts` (Q1, Q11), `chat/try-it.spec.ts` (Y1), `api/api.spec.ts` (row 13).
- `EXPERIENCE.md`, `DESIGN.md`, `mockups/states.html` under the UX folder.

**Review findings.** 36 findings from four layers (high 0, medium 10, low 20, false 4, maybe-false 2); see the Review Triage Log.
- Patched (the review pass, by the lead): K11 (leaving the finish: focus rule, closed outside the finish, new finish reopens, a press keeps it open), K5b (drawer band), K9 (turn in flight, the described-by reason), the `TestStubsAreNotFeatures` rewrite, DESIGN.md's link token (caption), and the AC7 mutation line. Patched mediums: 6; no high.
- Deferred (2, in the frontmatter): Q11's relaxation (row 1 is about 34px wider than the Linux host's row with the ruled link) and items 2/3 in the narrow bands (unverified).
- Rejected with reasons (spec-bound, unreachable on a real server, or duplicates): the panel staying open after Run again (Decided 7), a link with an empty list, item 7 focusing only the rail (ruled), the uncached probes, the substring read in `TestReadOnly`, M13's narrower count, K8's writes-only check, K1's use of `itemsFor`, fixed 500 ms dwells, the dead `aria-checked` guard (stated by the spec).

**Follow-up review recommended: true.** Two or more mediums were patched on this first pass. The unverified risk is the new browser cases K5b and K11, which were observed green and red on the lane-B throwaway only (their timing rests on the polled `guide.state` push), and Q11's one-line pin, which is relaxed (deferred item 1).

**Verification.** See "Measured" under Verification: unit and lint green; the four warm classes green; `live sign-in` parts 1-3, `floor` (107), `demo-path` (28, UJ-1), `demo-switch`, `shard lane-b` forward and reverse, `test-web-build.sh` and `ci/checks.sh` green; the contended-path guard diffs as ruled. Flakes: none hit. `demo-path` failed three times in the implement pass on this host's time budget (a load average near 9.5) and passed on the review pass's run.

**Residual risks.** Task 0 (c)'s heights were not recorded as numbers (floor passed). The layout of the narrow bands for items 2 and 3 is unverified (deferred). CI's `live:sign-in` gains 11 cases (about 1 minute); no deadline was raised.

**Rework pass 1 (2026-11-06, intent gap).** The earlier result above is the first pass; this pass did not finish.
- Attempted: the panel group became a scroll region of its own (`tabindex="0"`, named by the panel label) under the framed width query, bounded by `max-height: max(label line, 100vh - reserve)` (reserve 685px, 592px in the compact height band), with the items in an `auto-fill` grid of 20rem columns; K16 (six sizes) and source pins; DESIGN.md and EXPERIENCE.md updated; mutation (the bound removed) red at five sizes. `npm --prefix web test` 1488 pass, lint clean, `live sign-in --part 2/3` and `live floor` green. Saved as `_bmad-output/implementation-artifacts/4-11-rework-1-panel-bound.patch`; the tree was reverted to HEAD.
- Measured with that layout (chat list visible height, page scroll 0 in every framed size; panel window approximate): 1280x800 chat 214.8px, panel about 115px; 1024x768 chat 177.6px, panel about 83px; 1100x720 chat 191.6px, panel about 35px; 1280x650 chat 110.3px, panel about 58px; 1280x600 chat 99.5px, panel about 19px (the label line); 800x720 stacked chat 490.8px, unbounded. Closed-panel chat heights (review pass): 338, 269, 176 and 126px at 1280x800, 1024x768, 1280x650 and 1280x600.
- The gap: at 1280x600 the closed chat is 126px and the floor is 96px, so the whole panel may take 30px, which is the label line and 11px of a 36px control. At 1280x650 the room is 80px (about 58px measured), and at 1100x720 the panel measured 35px. A control cannot scroll fully into view in such a window, so target (c) fails where target (b) holds, with the strings, placement and open-in-the-finish condition fixed. Common laptop viewports (1366x768 gives about 657px of height) fall in this band.
- Recommended amendment (the Planner decides): (A) in the compact height band (viewport height under 680px) the panel is closed in the finish until "More to try" is pressed, and the bound applies when it is open; or (B) lower the compact band's chat floor from 96px to about 64px so that the panel can show its label and one control (about 64px) at 1280x600. The rest can be built inside the rulings: the 1100x720 row can hold 160px of chat with a one-control panel by lowering the non-compact reserve, and the findings routed to patch (focus key on the group, `minmax(min(20rem, 100%), 1fr)`, the K16 rows and mutation lines, the doc wording) are in the triage log. The saved patch is the base for the re-run.
- Deferred (unverified, medium if true): the chat's height with the panel opened by the link before the finish.
