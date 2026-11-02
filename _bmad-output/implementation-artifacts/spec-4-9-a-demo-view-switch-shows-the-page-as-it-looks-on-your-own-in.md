---
title: 'Story 4.9: A Demo view switch shows the page as it looks on your own install'
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_revision: 'cc0418c4012ae4cf4b5d851a861c2def5736af5d'
baseline_commit: 'cc0418c4012ae4cf4b5d851a861c2def5736af5d'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** On a demo-mode page a judge can't see what OcuTalon looks like on a real install, because the demo guide, Break the feed and the simulated devices are always there. The owner asked for this on 2026-11-01: "We need a toggle switch to "turn off demo mode", which would hide the guide and simulated phone to show what the screen would look like for a real deployment."

**Approach:**
- **The switch.** Add a client-only "Demo view" switch to the top bar. It shows only when the server's `demoMode` is true, and it is on by default.
- **One signal.** Add one demo view signal: the server's `demoMode` and the switch both on. Every demo-mode reader routes through it, except the header pill, which keeps reading the server's flag.
- **Off renders like demo mode off.** With the switch off, the page renders through the same path as a server with demo mode off. Nothing is sent to the server.
- **Docs and tests.** Write the switch into the UX spec with markers. Pin the behaviour with e2e cases on the real server switch and with a source test.

## Boundaries & Constraints

**Always:**
- **The signal file.** One new root service, `DemoView` in `web/src/app/shared/demo-view.ts`, holds the signal:
  - `available`: the server's `demoMode` is true. The switch shows only then.
  - `switchedOn`: the switch's state.
  - `on`: `available() && switchedOn()`.
  - `snapshot`: the live snapshot while `on()`, else `undefined`.
  - `set(on)`.
- **Who reads what:**
  - Only `DemoView` reads the server's `demoMode` from `LiveState`.
  - The one sanctioned direct read is the header pill: `header.ts`'s `badge`, kept exactly as written, because `ux-strings.test.mjs` L94-95 grab it.
  - The view models `guideOf`, `phoneOf` and `mailOf` keep their gate on their argument, `snapshot.demoMode !== true`, and every caller passes `this.demoView.snapshot()`.
  - Chat panel (empty chat), device panel, skip links and status rail read `this.demoView.on()`.
- **Storage.** The switch is kept per browser tab in sessionStorage under `ocutalon.demoView.off`: `'1'` means off and `'0'` means on.
  - It is read once when the service starts and written on each change, both through `shared/stored-flag.ts` (try/catch).
  - Anything else falls back to on, and a storage that throws keeps the choice in memory for the page.
- **What a change does.** A change touches only the view:
  - no server request (only the page's ongoing `GET /events` poll continues);
  - focus stays on the switch;
  - the page's `Announcer` says nothing, and the state change reaches assistive technology through `aria-checked` on the focused switch.
- **Markup.** A native `<button type="button" role="switch" [attr.aria-checked]>` (Space and Enter toggle it), named by its content "Demo view".
  - The help text "Off shows the page as it looks on your own install." is its `aria-describedby` description. It lives in a visually hidden element outside the button, so the name stays "Demo view".
  - The texts live in the framework-free `web/src/app/header/demo-view-texts.ts` (`DEMO_VIEW_TEXTS`).
- **Place and look.** In the header's left group, right after the context badge. A ghost header control: a 32x18 track with a thumb, then the label "Demo view".
  - Colours, only DESIGN.md tokens: on is the `--action` fill with an `--on-action` thumb on the right; off is the `--surface` fill with a `--border-strong` border and an `--ink-muted` thumb on the left.
  - No `transition`.
  - Width queries only through `LAYOUT_QUERIES`.
- **Bands:**
  - **Drawer band** (`LAYOUT_QUERIES.drawer`): the label is visually hidden (still the name) and the pointer tooltip is "Demo view".
  - **Other bands:** the label shows and the tooltip is the help text.
  - **Stacked band:** the switch wraps with the header, and nothing scrolls across at any width from 320px.
- **When the switch is back on:**
  - the guide shows the session's current step (the selection follows the first view, as on a load), silently;
  - its Hide guide choice (localStorage) is as it was;
  - the device tabs' new-content counts start at 0, as on a load.
- **Text.** The only public strings are "Demo view" and the help text, both verbatim from the AC, written into EXPERIENCE.md with markers. Straight ASCII quotes.

**Never:**
- **Out of footprint.** Never touch:
  - `web/src/app/api/api-types.ts`, `web/src/app/live/live-store.ts` (Epic 11), `web/src/app/rail/telegram-card/**` (Epic 12);
  - `web/e2e/demo-path/0[2-6]-*.spec.ts`, `web/e2e/support/*`, `web/e2e-online/*`;
  - any server class, `ci/**`, `docker/**`.

  In `web/scripts/ux-strings.test.mjs` and `web/scripts/guide-view.test.mjs`, only add lines; never change or delete one. Anything else outside the Code Map's list is an escalation.
- **Server state.** No new route, `/state` key, payload, table or server-side demo-mode change. The switch never posts, never reloads `/state`, and never changes the guide markers, the allowance, watches, reminders, incidents or approvals.
- **Nothing hidden that a real install shows:**
  - a pending approval request is never hidden: the chat card and the rail row stay;
  - the online demo's markers stay: the "Online demo" pill, the reset countdown and the allowance lines;
  - so does the local "Demo mode" pill;
  - the Telegram card is unchanged.
- **No new speaker or focus move.** No `Announcer` call, no `.focus(` call, and no new key binding.
- **No new CI unit and no new e2e folder.**

## I/O & Edge-Case Matrix

`S` is the switch, `D` the server's `demoMode`. "Demo parts" are the Demo guide region (with its Break the feed box) and the Simulated devices region.

| # | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| 1 | `D` true, snapshot loaded, no stored choice | `S` shows after the badge, `aria-checked="true"`, name "Demo view", described by the help text; the demo parts show | sessionStorage throws: same, and a press still toggles for the page |
| 2 | `D` false (real server switch), or the snapshot is loading or failed | No `S`. The page is as today | none |
| 3 | Press `S` (click, Space or Enter) with it on | **(Integration)** The consumers react:<br>- the guide (`DemoGuide`) and the device panel render nothing, and main ends at the viewport's right edge;<br>- `SkipLinks` drops "Skip to simulated devices";<br>- the empty chat shows "Ask OcuTalon to watch a production, set a reminder, or say what you need.";<br>- the rail's empty Background checks line is the non-demo one.<br>The regions, landmarks, skip links and rail section labels equal those of the same page with `D` false. Focus stays on `S`, `aria-checked="false"`, no request except the poll, no announcement | none |
| 4 | `S` off, the user sends a chat message | It sends and its reply lands as on any install | none |
| 5 | `S` off, then reload the tab | `S` still off (sessionStorage); a new tab opens with `S` on | none |
| 6 | `S` off on the online demo (`onlineDemo` true) | "Online demo" pill, reset countdown and allowance banner/line stay; on a local demo, the "Demo mode" pill stays | none |
| 7 | A pending approval request (chat card, rail row, phone message); `S` off | **(Integration)** The card is answerable in the chat and the rail row stays. Approve on the card, the answered notification arrives, then `S` on: the simulated phone (`SimulatedPhone`) shows that message answered (its answer line, no buttons) | none |
| 8 | Guide at step 3, user selected step 1, Hide guide pressed or not; `S` off then on | **(Integration)** The guide returns at step 3, selected; collapsed if it was collapsed, expanded if it was not. No "Step n of 5" announcement | none |
| 9 | Header at 1024x800 on the online demo (pill and Status button), and at 320, 640, 1280 and 1440 | No horizontal scroll, and the right group ends inside the header. In the drawer band only the track shows | none |

</intent-contract>

## Code Map

**The signal and the switch (new):**
- `web/src/app/shared/demo-view.ts`: `DemoView` and the key and flag constants (`DEMO_VIEW_KEY = 'ocutalon.demoView.off'`, `DEMO_VIEW_OFF = '1'`, `DEMO_VIEW_ON = '0'`).
  - **Siblings it extends:**
    - `shared/trace-help.ts`: a root service reading `LiveState`, with a sessionStorage flag read once through `readFlag` and written through `writeFlag`;
    - `shared/trace-view.ts:47-53`: its key constants;
    - `devices/device-tabs.ts:16-24`: a stored choice held as a signal.
- `web/src/app/header/demo-view-texts.ts`: `DEMO_VIEW_TEXTS = { label: 'Demo view', help: 'Off shows the page as it looks on your own install.' }` and `DEMO_VIEW_HELP_ID`. A framework-free module, the sibling of `header/sign-out-texts.ts`.
- `web/src/app/header/demo-view-switch.ts`: `app-demo-view-switch`. It renders only `@if (demoView.available())`.
  - **Reuses:**
    - the `.button .button-ghost` style and the header-button look (`header.ts:271-276`);
    - `shared/tooltip.ts` `[appTooltip]` (a tooltip whose text reaches assistive technology another way);
    - `Layout.band()` (`shared/layout.ts`) for the drawer-band tooltip;
    - the global `.visually-hidden`.
- `web/src/app/shared/stored-flag.ts`: `readFlag` and `writeFlag` (read only).

**Readers to route through `DemoView`:**
- `header/header.ts`:
  - `:85` imports;
  - `:94-96`, the badge `@if`: add `<app-demo-view-switch />` after it, inside `.side`;
  - `:377-383` `badge`: unchanged, the sanctioned read.
  - The stacked header already wraps (`:290-299`). The left `.side` must let the switch wrap too: no scroll across at 320px.
- `header/skip-links.ts:68`: `link.demo !== true || this.demoView.on()`. Keep the `SKIP_LINKS` shape (`ux-strings` L89 grabs it).
- `chat/chat-panel.ts:283`: `demo = computed(() => this.demoView.on())`. It feeds `<app-empty-chat [demo]>` (`:140`; `empty-chat.ts:37`).
- `devices/device-panel.ts`:
  - `:243`: `demo` becomes `demoView.on()`. It sets the host class `on` (`:55`), which gives main the width (`main-page.ts` reads no `demoMode`; layout only).
  - `:269-274`: the effect reads `this.demoView.snapshot()`.
  - `:316-321`: `note()` keeps calling `phoneOf` and `mailOf` with that snapshot. A changed snapshot identity is a fresh look, so the counts are 0.
- `rail/status-rail.ts:262`: `railView(store, formatAt(Date.now()), this.demoView.on())`. In `rail-view.ts:319,339` the `demo` flag picks `emptyChecksDemo` or `emptyChecks`.
- `guide/demo-guide.ts`:
  - `:522` `liveView` becomes `guideOf(this.demoView.snapshot() as GuideSnapshot | undefined, this.live.store())`;
  - `:597` `showMe` becomes `phoneOf(this.demoView.snapshot() …)`.
  - No other change: `follow()` (`:600-608`) with an undefined view already clears `last` and `selected`, so the return is a first view (`guide-view.ts:263-286`, `advance` and `followSelection`). `hidden` (`:537`) is localStorage and survives.
- `phone/simulated-phone.ts:230`: `phoneOf(this.demoView.snapshot() …)`.
- `mailbox/simulated-mailbox.ts:497`: `mailOf(this.demoView.snapshot() …)`.
- Unchanged gates, which keep their unit tests:
  - `guide/guide-view.ts:80-85` (`guide-view.test.mjs:87-99`);
  - `phone/phone-view.ts:33-36`;
  - `mailbox/mailbox-view.ts:65-67`.
- `app.ts:40` renders `<app-demo-guide />` always; the guide renders nothing when its model is undefined.

**Unit tests (`web/scripts/`, `node --test`):**
- New `web/scripts/demo-view-sources.test.mjs`. It extends the shape of `announce-focus-sources.test.mjs` and uses `source-files.mjs` `sourceFiles` and `code`. It asserts:
  - (a) Among `web/src/app/**/*.ts`, `\bdemoMode\b` (comments stripped) appears only in:
    - `api/api-types.ts`;
    - `shared/demo-view.ts`;
    - `header/header.ts`, exactly once, in `snapshot?.demoMode ? 'Demo mode'`;
    - `guide/guide-view.ts`, `phone/phone-view.ts` and `mailbox/mailbox-view.ts`, each exactly once, in `snapshot.demoMode !== true`.
  - (b) Every call of `guideOf(`, `phoneOf(` or `mailOf(` outside their own modules passes a snapshot from `demoView.snapshot()`, and none passes `live.snapshot()`.
  - (c) `chat-panel.ts`, `device-panel.ts`, `skip-links.ts` and `status-rail.ts` read `demoView.on()`.
  - (d) `shared/demo-view.ts` reads and writes `window.sessionStorage` only through `readFlag` and `writeFlag`.
  - (e) `header/demo-view-switch.ts` has `role="switch"` and `aria-checked`, and no `Announcer`, `.focus(`, `ApiClient` or `HttpClient`.
- `web/scripts/ux-strings.test.mjs` (add lines only):
  - in `IMPORTED` (`:43-61`), add `['header/demo-view-texts.ts', ['DEMO_VIEW_TEXTS']]`;
  - in `SOURCES.ux` (`:153`), add `'Demo view'` and `'Off shows the page as it looks on your own install.'`.
- `announce-focus-sources.test.mjs`, `floor-sources.test.mjs`, `shell-styles.test.mjs` and `page-safety.test.mjs` should pass unchanged: no speaker, no focus call, no key binding, and only declared tokens. Run them; do not edit them.

**E2E:**
- New `web/e2e/demo-switch/view.spec.ts` (project `demo-switch`, unit `live:demo-switch`). The bash runner (`docker/tests/test-demo-switch.sh:319` `e2e 0`, `:370` `e2e 1`) runs the folder with `D` really off, then on again.
  - The file sorts last ("view"), so its chat turn on the README session comes after every other spec of the folder and after the runner's chat checks.
  - It copies `stackMode()` from `badge.spec.ts:11-17`: a spec file can't import another without running its tests, and `support/*` is off limits.
  - **Uses:**
    - `support/api.ts:27` `changeSnapshot` (the F2 pattern, `frame/frame.spec.ts:101-122`);
    - `support/floor.ts` `signInReadmeLoaded`, `composerOf` and `mainOf`;
    - `support/page.ts:56,87` `recordAnnouncements` and `announcedTexts`.
  - Set the stored choice with `page.addInitScript(() => sessionStorage.setItem('ocutalon.demoView.off', '1'))`.
- `web/e2e/answers/answers.spec.ts` (project `answers`, unit `live:answers`): add case X11 after X10. It reuses the file's `open`, `raise` (`support/approvals.ts:67`), `noticeOnPhone`, `requestCard`, `phoneOf`/`messageOf` and X3's answered-notification step (`:308-370`).
- `web/e2e/frame/frame.spec.ts:126-161`, F3, the shared surface:
  - the box order gains the switch (badge, then switch, then Visual Trace);
  - Tab from the home link reaches the "Demo view" switch, then the Visual Trace button, then the theme button.
- Read only:
  - R8 in `web/e2e-online/reset.spec.ts:628-665`, the fit rule at 1024 and 640 that this story must keep;
  - `web/e2e/demo-switch/guide.spec.ts` (the demo texts per mode);
  - `web/scripts/playwright-projects.test.mjs` (new files in existing folders need no edit).

**UX (`_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/`):**
- `EXPERIENCE.md:222-231`, "Demo guide and controls";
- `EXPERIENCE.md:573-575`, the intro of "Demo Mode and the Online Demo";
- `DESIGN.md:738-744`, Frame › App header.

## Tasks & Acceptance

**Execution** (in dependency order):
- [ ] **Task 0 (measure, throwaway only).** After the switch exists, run `ci/iris.sh build`. Then re-measure the header's free width at 1024x800 with the online-demo snapshot, with the final component in both forms. Use the plan's method: a throwaway Playwright script outside the repository, in the stage's scratch folder. Serve `src/ocutalon/csp/` statically at `/ocutalon/` and route `/ocutalon/api/v1/state` and `/events`; register the catch-all `api/v1/**` route first, because a later route wins. A static page needs no stack.
  - If the drawer-band form leaves under 16px, record it and HALT with a clarification; never shrink other header items.
  - Also confirm that the demo-switch stack answers an unscripted `zz` chat message with a reply (the runner's step 1 does). If it doesn't, use the text "zz demo switch hello".
- [ ] `web/src/app/shared/demo-view.ts`: `DemoView` as in Always. Rule 14: the comments state the contract.
- [ ] `web/src/app/header/demo-view-texts.ts` and `web/src/app/header/demo-view-switch.ts`: the switch as in Always.
- [ ] `web/src/app/header/header.ts`: the import and `<app-demo-view-switch />` after the badge; let the stacked left group wrap.
- [ ] `skip-links.ts`, `chat-panel.ts`, `device-panel.ts`, `status-rail.ts`, `demo-guide.ts`, `simulated-phone.ts` and `simulated-mailbox.ts`: route through `DemoView`, as in the Code Map.
- [ ] `web/scripts/demo-view-sources.test.mjs` (new): (a) to (e).
- [ ] `web/scripts/ux-strings.test.mjs`: the three lines.
- [ ] `web/e2e/demo-switch/view.spec.ts` (new). A shared `structure(page)` reads:
  - landmarks and regions (role and accessible name, from `aria-label` or the `aria-labelledby` text);
  - the texts of `app-skip-links a`;
  - the labels of `section.rail` headings, without their counts;
  - whether main's right edge is within 1px of the viewport's.

  No pixels or screenshots. The cases:
  - **Mode 0, V0:** no `getByRole('switch')`. Load page A, the real snapshot; then page B, `changeSnapshot` with `demoMode` true and the stored choice off. B shows the switch, unchecked, and `structure(B)` equals `structure(A)` (matrix 2, 3).
  - **Mode 1, V1:** the switch has role `switch`, name "Demo view", the help text as its description, `aria-checked="true"`, and it sits after the badge.
    - Focus it, then Space: unchecked, focus still on it. Enter: checked. Click: unchecked.
    - Meanwhile no request but `GET /events`, and no announcement.
    - Reload: still unchecked. `context.newPage()`: checked (matrix 1, 3, 5).
  - **Mode 1, V2:** with the switch off:
    - the Demo guide and Simulated devices regions and the box are gone;
    - main ends at the viewport's right edge;
    - "Skip to simulated devices" is absent;
    - with `changeSnapshot` emptying the chat and the rail's checks: the non-demo empty chat line and empty checks line.

    Then `structure` equals that of page B (`changeSnapshot` `demoMode` false). Switch on: the regions and the skip link return (matrix 3).
  - **Mode 1, V3:** switch off, then send "zz demo view hello" from the composer: the turn and its reply show (matrix 4).
  - **Mode 1, V4:** `changeSnapshot` gives the guide at step 3 (steps 1 and 2 done).
    - The user selects step 1 and presses Hide guide. Switch off, then on: the collapsed bar shows "step 3 of 5".
    - Show guide: step 3 is current and selected.
    - Repeat without Hide guide: expanded, step 3 selected.
    - No "Step 3 of 5" announcement (matrix 8).
  - **Mode 1, V5:**
    - `changeSnapshot` with `onlineDemo` true, `nextReset` 2 h ahead, and an active `allowance` status. Switch off: the "Online demo" pill, the countdown and the allowance banner stay.
    - At 1024x800 and 640x800: no scroll across, and the right group ends inside the header. In the drawer band the label is hidden and the track visible.
    - At 320x800: no scroll across.
    - Real snapshot, switch off: the "Demo mode" pill stays (matrix 6, 9).
- [ ] `web/e2e/answers/answers.spec.ts`: add **X11**:
  - raise a request with its phone notice (as X3), then switch off;
  - the request card in the chat has Approve and Reject, the rail row is there, and the Simulated devices region is gone;
  - Approve on the card, then 200; send the answered notification as X3 does;
  - switch on: the phone's message shows "Approved from the web chat at HH:MM." with no buttons. Clean up in `finally` (matrix 7).
- [ ] `web/e2e/frame/frame.spec.ts`: F3 as in the Code Map. Change nothing else.
- [ ] Search the other test trees for the header's control list and Tab sequences: `web/e2e/**`, `web/scripts/**`, and read-only `web/e2e-online/**`. Fix only in-footprint pins of the old shape. If an off-limits file needs a change, escalate.
- [ ] `EXPERIENCE.md`, each with the marker `[ADDED 2026-11-01, Story 4.9, owner request relayed by the Contest Planner; the owner: "We need a toggle switch to "turn off demo mode", which would hide the guide and simulated phone to show what the screen would look like for a real deployment."]`:
  - **"Demo guide and controls":** a bullet, **Demo view switch.** Demo mode only, in the app header after the context badge.
    - A native switch (`role="switch"`, `aria-checked`), labelled "Demo view", on by default.
    - Its help text, "Off shows the page as it looks on your own install.", is its accessible description and its pointer tooltip. In the 1024-1279px band, where the label is hidden, the tooltip is "Demo view".
    - A press (click, Space or Enter) changes only the view. Nothing is sent to the server, and focus stays on it. Screen readers hear the new state from `aria-checked`; the page announces nothing.
    - It is kept per browser tab, falling back to on.
  - **"Demo Mode and the Online Demo" intro:** a paragraph, **The Demo view switch.**
    - Off, the page shows as on your own install: no demo guide, no Break the feed, no Simulated devices. The chat takes their width, the skip links drop "Skip to simulated devices", and the empty chat and Background checks show their non-demo lines.
    - The honest markers stay: the "Demo mode" pill on a local install, and the "Online demo" pill, the reset countdown and the allowance lines on the online demo. The Telegram card follows the server's Telegram state.
    - Nothing on the server changes. A pending approval request stays answerable in the chat.
    - Back on, the guide shows the session's current step with its Hide guide choice as before, and the simulated phone shows answers given meanwhile.
    - Text the server writes may still name the simulated phone while the switch is off.
- [ ] `DESIGN.md` Frame › App header: after the context-badge bullet, add a bullet for the Demo view switch (demo mode only), with the same marker:
  - a ghost control: a 32x18 track (on: `{colors.action}` fill and `{colors.on-action}` thumb at the right; off: `{colors.surface}` fill, `{colors.border-strong}` border and `{colors.ink-muted}` thumb at the left);
  - then the label "Demo view" in `{typography.body-strong}`;
  - the track alone in the 1024-1279px band;
  - the standard focus ring, and no animation.

**Acceptance Criteria:**
- **AC1.** Given `D` is true, when the top bar renders, then it has a native switch (`role="switch"`, `aria-checked`) labelled "Demo view", on by default, described by "Off shows the page as it looks on your own install.", reachable by keyboard, and toggled by Space, Enter and click. Given `D` is false on the server, then there is no switch.
- **AC2.** Given the switch is off, when the page re-renders, then the demo guide, the Demo control with Break the feed and the Simulated devices region are gone. The regions, landmarks, skip links and rail sections equal those of the same page with `D` false, compared as structure, never pixels. Main takes the devices' width, and the empty chat and empty-checks lines are the non-demo ones.
- **AC3.** Given the web sources, when the source test runs, then no file reads `demoMode` except `DemoView`, the pill and the three view-model gates. Every view-model call passes `demoView.snapshot()`, and the four boolean readers use `demoView.on()`.
- **AC4.** Given the switch is off, when the page renders on the online demo or a local demo install, then its pill (and on the online demo, the reset countdown and allowance lines) stay, and the Telegram card is unchanged.
- **AC5.** Given the switch, when it changes, then no request but the poll is made, focus stays on it, and the page announces nothing. The choice survives a reload of the tab, and a new tab starts on.
- **AC6.** Given a pending approval request, when the switch goes off and on, then it is answerable in the chat while off, and an answer given while off shows on the simulated phone as answered once the switch is on.
- **AC7.** Given the guide at some step with a Hide guide choice, when the switch goes off and on, then the guide shows the session's current step, selected, with its Hide guide choice unchanged, and no announcement.
- **AC8.** Given widths from 320px up, including 1024px on the online demo with the pill and the Status button, when the header renders, then nothing scrolls across and the right group ends inside the header.
- **AC9.** Given this story merges, when the UX documents are read, then EXPERIENCE.md's "Demo guide and controls" and "Demo Mode and the Online Demo" sections and DESIGN.md's app header carry the switch, each with the 2026-11-01 marker. `ux-strings.test.mjs` finds both strings in EXPERIENCE.md.
- **AC10.** Given the change, when it merges, then the story stays inside the footprint, adds no CI unit or e2e folder, and CI is green on every workflow.

- [x] [Review] G4 compact-header pin vs the switch at 200% - `web/e2e/floor/layout.spec.ts` (`expectColumn`, the `headerBlock < wideBlock` check) - amend as the Spec Change Log ruling of 2026-11-01 (U-202) says, add its EXPERIENCE.md marker, and record a `mutation:` line (e.g. the header block forced to 40% of the viewport -> G4 red); then `live floor` must pass 106 of 106.

### Review Findings

Code review 2026-11-01 (stage code-review, diff `cc0418c4` to the working tree; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 18 rows, 7 entries kept, 11 rejected; no high, no medium in-story).

- [x] [Review][Patch] The switch's host is an empty flex item when demo mode is off, adding a 12px gap to the header's left group (matrix row 2, "the page is as today") — `:host { display: contents; }`, as `skip-links.ts` and `empty-chat.ts` do [web/src/app/header/demo-view-switch.ts:39]
- [x] [Review][Patch] V5 checked only the `visually-hidden` class where the label should show, so a label hidden by CSS passed — the label's box must be wider than 20px outside the drawer band; mutation recorded under Verification [web/e2e/demo-switch/view.spec.ts:281]
- [x] [Review][Patch] V3's chat text was fixed, so `toHaveCount(1)` on the turn fails on any rerun on the same stack — the text keeps "zz demo view hello" and gains a run suffix [web/e2e/demo-switch/view.spec.ts:213]
- [x] [Review][Patch] X11 used `answeredAt ?? ''` unchecked, so a reply without the answer time compared "at ." to "at ." — the file's own format assertion (X3's, `:270`) added [web/e2e/answers/answers.spec.ts:791]
- [x] [Review][Patch] view.spec.ts's header said "V1 to V5 run in mode 1" and did not say V5 is two cases — the comment states the cases as they are [web/e2e/demo-switch/view.spec.ts:7]
- [x] [Review][Patch] EXPERIENCE.md's canonical main-page order and "Without demo mode" line did not name the switch — both amended with a Story 4.9 marker [EXPERIENCE.md:66,73]
- [x] [Review][Defer] The amended "Narrower than 1024" row says the compact header stays within a quarter of the window's height, but at 320px wide the measured header is 157px (local) / 180px (online), over a quarter of a window under about 720px high (320x568: 142px) [EXPERIENCE.md:472, header.ts stacked block] — deferred: the narrow stacked header case of U-202, already ledgered as DW-530 (owner Story 31.2); occurrence to be appended there (DW-530 is not in this branch's ledger yet)

**Rejected:**
- `low` The label is hidden and the help text is tooltip-only in the drawer band (blind) — the lead's ruling (2) and Decided 4; by-design.
- `low` No forced-colors rule: the thumb takes Canvas there, so on and off look alike (blind) — the repo has no forced-colors handling anywhere and the state still reaches assistive technology through `aria-checked`; the fix adds a media branch for a rare mode. wontfix-accepted, reopen_if=a forced-colors check (Playwright `emulateMedia({ forcedColors: 'active' })`) is added to the floor suite or a user reports the switch's state invisible in high contrast.
- `low` The stacked wrap and 4px padding also apply without demo mode while the amended row says "in demo mode" (blind) — accepted by the lead (flex-wrap, padding) and the marker is the ruling's text; by-design.
- `false` F7 steps over the switch without checking its ring (blind) — floor K4 checks the 2px ring at every tab stop of the demo page, the switch included (106 of 106 in this pass).
- `low` Two cases share the id V5 (blind, edge, auditor) — both are the spec's V5 (online-demo markers and fit; local-demo pill) and the recorded mutations name them so; the header comment now says so.
- `low` `.header-switch` repeats four declarations of header.ts's `.header-button` (blind, Rule 2) — header.ts's component styles cannot reach a child component's button, and Decided 12 keeps the class apart; a shared global class is more than a two-way door. wontfix-accepted, reopen_if=`.header-button`'s gap, padding, colour or weight changes in header.ts and `.header-switch` does not.
- `low` A sample-email POST in flight when the switch goes off loses the mailbox's focus target (edge) — needs a toggle inside one request's round trip; theoretical; would be real if the mailbox's send took seconds.
- `low` G4 at 1000x800 could take the quarter bound if the header wrapped (verification-gap) — the lead's ruling U-202 is exactly "the old check where the header fits one row, the quarter where it wraps"; by-design.
- `false` AC1, AC4 and AC6 clauses without a `mutation:` line (verification-gap) — Rule 19 asks one demonstrated mutation per AC, and each of AC1, AC4 and AC6 has one recorded.
- `low` The source pins are source text only (verification-gap, other) — complementary to the browser cases; the routing they pin has no runtime surface while the components are absent.
- `low` The Auto Run Result's counts predate QA (auditor) — fixing it edits the spec's run record; the QA lines under Verification hold the current counts.
- `false` "Its state is announced when it changes" rests on `aria-checked` (auditor note) — the spec's Always rule and Decided 5 decide it; by-design.

## Spec Change Log

- 2026-11-01 (lead, unattended ruling, veto item U-202; implement-stage intent gap on floor G4): the switch makes the sticky demo-mode header wrap to a second control row at 200% (640x360, scale 2): about 77px against about 56px at 1280x720, which contradicts G4's "the compact header is shorter than at 1280x720" (`web/e2e/floor/layout.spec.ts`, the `expectColumn` helper). **Ruled (veto, reversible):** amend G4's compact-header check, not the header: with demo mode on, the compact header may wrap to a second row, and at every G4 size its block size is at most a quarter of the viewport's height (`<= innerHeight * 0.25`); keep the old `< wideBlock` check wherever demo mode is off or the header still fits one row, keep "only the header is sticky" and "there is no horizontal scroll" exactly as they are. `web/e2e/floor/layout.spec.ts` is outside the story's listed footprint and in no in-flight epic's diff: a footprint extension the lead reports. EXPERIENCE.md's "Narrower than 1024" row ("Nothing is sticky except a compact header") gains a marker: `[AMENDED 2026-11-01, Story 4.9, owner request of 2026-11-01: in demo mode the compact header may wrap to a second row for the Demo view switch, and stays within a quarter of the window's height]`. Rejected: shrinking or hiding other header items (the pill and the online demo's markers must stay), dropping the switch from the stacked band (AC: the switch is in the top bar; scope change). Also accepted by the lead: F7's extra Tab step in `frame.spec.ts`, the `playwright-projects.test.mjs` answers pin (X1-X11, 21 cases), and the stacked header's `flex-wrap` and 4px padding (fixes a pre-existing 189px scroll across at 320px on the online demo).
- The rest of the implementation is in the working tree, uncommitted (the halt came before finalize); keep it, do only the open G4 item below, then re-run verification and finalize.

## Review Triage Log

### 2026-11-01 - Review pass (whole story, diff from cc0418c4)
- verdicts: 32 findings - high 0, medium 6, low 23, false 3, maybe-false 0
- findings:
  - Blind hunter:
    - `[low]` `[reject]` no forced-colors fallback on the switch - the repo has no forced-colors handling anywhere; the thumb position and `aria-checked` still carry the state; the fix adds a media branch for a cosmetic gain.
    - `[low]` `[reject]` the new track/thumb colour pairs are not in DESIGN.md's contrast table - they are existing tokens; a documentation-only completeness point with no user-reachable failure.
    - `[false]` `[reject]` the device tabs' new counts reset on switch-on - intended: Boundaries ("start at 0, as on a load") and Decided-in-stage 7.
    - `[low]` `[reject]` V1's request window is a fixed 1500 ms and the listener is added after sign-in - a negative window needs a duration; the listener is added before the first press; mutation `set()` also calls `retry()` showed the check can fail.
    - `[false]` `[reject]` V3 depends on a real model reply - the spec requires a live reply (every demo step is generated live); the unit runs with the stack's own key setup.
    - `[low]` `[reject]` the compact-header height bound is checked only in G4, and the padding/flex-wrap change touches the non-demo compact header - the lead's ruling of 2026-11-01 accepted the wrap and the 4px padding; V5 pins the fit from 320px.
    - `[low]` `[patch]` the sources test's `doesNotMatch(/live\.snapshot\(/)` cannot fail (the capture stops at the first `)` and the earlier `match` already requires `demoView.snapshot(`) - deleted the line.
    - `[low]` `[reject]` other looseness of the source-shape tests (the pill literal, only `.ts` files, `^\s*snapshot\b`) - a stricter pin than the whole-file `demoMode` list would break on reformatting; each pin has a recorded mutation.
    - `[low]` `[reject]` the help is visible only on hover - the tooltip component is the app's one tooltip (pointer only by design, F8); keyboard users get the description; the spec decided this (Decided 4).
    - `[low]` `[reject]` no unit-level tests of `DemoView` - the web tests are framework-free; V1 and V6 run the service in the browser.
  - Edge case hunter:
    - `[low]` `[reject]` the guide's `answered` signal survives an off/on - the next live event replaces it; no user-reachable wrong state shown.
    - `[low]` `[reject]` an in-flight Break the feed request loses its pending state while off - the server is unchanged and the box rebuilds from the next view.
    - `[medium]` `[patch]` 1440 is named in matrix row 9 but not in V5's loop - added 1440.
    - `[low]` `[reject]` tabs opened by `context.newPage()` stay open - the page closes with the test context.
    - `[low]` `[reject]` V1's request window can see other legitimate requests - the same row as the blind hunter's V1 row.
    - `[low]` `[reject]` G4 could pass a header of three rows under a quarter of the window - the ruling is exactly "at most a quarter of the viewport's height".
  - Verification-gap reviewer:
    - `[medium]` `[patch]` the tooltip text is never asserted in either band - V1 now hovers the switch (the help text) and V5 hovers at 1024 ("Demo view"); the swapped-branch mutation is covered by these.
    - `[medium]` `[patch]` no `mutation:` line for the empty-chat and empty-checks routing, or for `set()` announcing or moving focus - four mutations run and recorded below (V2 chat line, V2 checks line, V1 focus, V1 announcement).
    - `[medium]` `[patch]` V4's "no announcement" cannot be shown to fail - a mutation that announces on every view turned V4 red, which shows the recorder catches the guide's speech.
    - `[medium]` `[patch]` the stacked `.side` `flex-wrap` has no mutation and 1440 is not looped - mutation recorded (V5 red at 320); 1440 added.
    - `[medium]` `[patch]` matrix row 1's "sessionStorage throws" has no case - V6 added (mode 1); mutation recorded.
    - `[low]` `[reject]` AC4's countdown/banner/Telegram card and AC6's second half have no mutation - those components do not read `demoMode` and `DemoView` cannot change them; reopen_if=a component there starts reading `DemoView`.
    - `[low]` `[reject]` V3 depends on file order and the shared README session - V3 asserts `before + 1` and the later cases do not count replies; a rerun adds one turn and passes.
    - `[low]` `[reject]` V1's fixed 1500 ms wait - as above.
    - `[low]` `[reject]` V2 selects the checks line with `.nth(1)` - the mutation on `status-rail.ts` showed it fails on the wrong text.
    - `[low]` `[reject]` `structure` could compare two empty lists - each list is non-empty on these pages and V2 asserts the individual regions and lines too.
    - `[low]` `[reject]` G4 branches on a value the page produces - the ruling's own shape; the switch and a second row must both be present for the quarter bound to apply.
    - `[low]` `[reject]` the sources test is source-text only - it is a complement to the browser cases, and each of its checks has a recorded mutation.
  - Intent-alignment auditor (descriptive; no defects filed):
    - `[low]` `[reject]` row 1 error handling pinned only by source text - closed by V6 (patched above).
    - `[low]` `[reject]` the visual spec (32x18 track, tokens, no transition) has no assertion - `shell-styles.test.mjs` and `floor-sources.test.mjs` pin the tokens and the no-fixed-height rule; the sizes are a DESIGN.md value.
    - `[low]` `[reject]` the device tabs' counts reset on return is pinned only by construction - `DevicePanel.note` is unchanged and a changed snapshot identity is its fresh look; reopen_if=the panel keeps a baseline across an undefined snapshot.
    - `[false]` `[reject]` the "snapshot loading or failed" half of row 2 - `available` is false until a snapshot says so; frame F-cases of the failed snapshot (no badge, no switch) pass.

## Design Notes

**Architecture decisions** (spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`, status final):
- **AD-1** (L102): the switch is no command. It sends nothing, and REST writes stay UI markers only.
- **AD-12** (L381): the snapshot and live events are unchanged. The guide's step and Break the feed's availability still come only from `Guide.Compute`; the page only chooses not to render them.
- **AD-11** (L353) and **AD-32** (L1013): the approval row is the truth, and the phone's answered line is the server's edit. Off hides the phone copy only, never the request.
- **AD-25** (L833) and **AD-20** (L631): the online demo's markers and allowance are untouched.
- **AD-29** (L925): lane B and the home lane's files; Epic 11's and Epic 12's files are untouched.
- **AD-33** (L1025): no new event type or owner.
- **Conventions:**
  - L1088, Announcements and focus: no new speaker or focus move;
  - L1111, Angular: standalone components and signals, styled from DESIGN.md tokens;
  - L1115, Tests;
  - L1090, Text OcuTalon sends: server-built text stays the catalog's, which is the dev note's known limit.
- No AC contradicts an AD's Rule. No NFR trips Rule 5 (UX-DR43, UX-DR48 and UX-DR80 are measurable as written).

**Integration ACs (Rule 1):** matrix rows 3, 7 and 8 have consumers reading the signal and producing an observable effect, each on a real stack:
- the guide, the device panel, the skip links, the empty chat and the rail: `live:demo-switch`, with the real server switch;
- the simulated phone: `live:answers`.

**Consumed-by:**
- Story 4.10: its "Try it yourself" chips show only while `DemoView.on()`, in the finish state and the empty chat.
- Any later demo-only part reads `DemoView`, never `demoMode`, and the source test keeps that true.

**Consumes:**
- Story 4.1: the server's `demoMode` and the demo-switch unit;
- Story 4.4: the guide, the box, the empty-chat and empty-checks demo lines;
- Story 4.5: the device panel and `DeviceTabs`;
- Story 4.7: the guide's selection rules;
- Story 2.14: the skip links;
- Story 16.8: the reset pill, R8's fit rule;
- Story 16.9: the allowance lines;
- Story 6.3: the answers unit's fixtures.

**Rule 2 (extend, don't copy):**
- `DemoView` extends `TraceHelp`'s pattern: a root service, a sessionStorage flag through `stored-flag.ts`, read once.
- `demo-view-texts.ts` follows `sign-out-texts.ts`.
- The switch reuses the ghost header-button style and `Tooltip`.
- The source test extends `announce-focus-sources.test.mjs`'s shape on `source-files.mjs`.
- X11 extends `answers.spec.ts`'s own helpers.
- One copy is justified: `stackMode()` in `view.spec.ts`. Spec files can't share helpers without `support/*`, which is off limits.

**Ledger (Rule 17):** the inbox is empty; this story owns no entry.

**Measured in this plan** (the built bundle of `5927cadb` served statically, `/state` routed with the online-demo user "DemoVisitor" and a reset 2 h ahead, Chromium, a throwaway script outside the repository):
- **The header's free width between its two groups:**
  - online demo: 104px at 1024, 188px at 1100, 359px at 1279, 467px at 1280, 627px at 1440;
  - local demo: 345px at 1024 and 699px at 1280.
- **The stand-in switch** (track and "Demo view") needs 131px plus a 12px gap. So the full form does not fit the drawer band on the online demo, and the track alone (about 48px plus 12px) does (inference until Task 0).
- **The sign-in split:** part 1/2 is 8 files and 127 of 223 tests, ending with `guide/guide.spec.ts`; `frame/frame.spec.ts` is in part 1.

**Measured in implement** (the final bundle served statically with the online-demo snapshot, a throwaway Playwright script outside the repository, Chromium; the numbers are the gap between the header's two groups):
- **1024x800, online demo:** 42px with the switch on and 50px with it off (the countdown text differs by a few px), in the drawer form: the switch is 50px wide (track alone). The full form (131px plus the 12px gap) would not fit. So the drawer-band form leaves at least 42px, above the 16px floor: no HALT.
- **Local demo:** 265px at 1024. Online: 118px at 1100, 297px at 1279, 316px at 1280 (full form, 131px), 476px at 1440.
- **Stacked band:** at 640 and 320 the page does not scroll across (scrollWidth equals clientWidth) with the switch, on both the online and the local snapshot. The right group needed `flex-wrap` in the stacked band: before this story the online demo's right group alone was 497px wide, so the page scrolled across by 189px at 320 (the same on a snapshot with demo mode off). The header is 77px at 640 and 157px (local) / 180px (online) at 320, in two or more rows. Floor G4 (`web/e2e/floor/layout.spec.ts:452`, 640x360 at scale 2, demo snapshot) requires the header to be shorter than at 1280x720; the demo header at 640 had 15px free and the switch needs at least 62px even as a track, so G4 is red (105 of 106 floor cases pass).
- **The unscripted `zz` message:** the demo-switch stack answers it with a reply. V3 ("zz demo view hello") passed in mode 1, so the fallback text "zz demo switch hello" was not needed.
- **Times, locally:** `live:demo-switch` 308 s (mode 0: 6 cases; mode 1: 19 cases, view.spec.ts included), `live:answers` 349 s (21 cases, X11 10 s), `live:floor` 372 s, `live:sign-in` part 1/2 329 s (127 cases) and part 2/2 318 s (96), `live:demo-path` 170 s, `live:online-demo` 383 s (`MEASURED R8` at 1024px: 0px across, right group ends -16px past the edge; at 640px: 0px across, -103.9px).

**Decided in-stage** (unattended: small, reversible, within the intent):
1. **The view-model gates stay.** `guideOf`, `phoneOf` and `mailOf` keep `snapshot.demoMode !== true` on their argument, and their callers pass `DemoView.snapshot()`, which is undefined outside the demo view.
   - Why: removing the gates would change `guide-view.test.mjs:87-99`, where only added lines are allowed.
   - The source test whitelists exactly these three reads and pins every call site, so no component can bypass the signal. This meets the AC's "no component outside the demo view signal reads demoMode". It is narrower than the orchestrator's "nothing outside the signal file" only by those three argument gates.
2. **The signal's home.** `web/src/app/shared/demo-view.ts`, beside its sibling `TraceHelp`. The texts are in `header/demo-view-texts.ts`, so `ux-strings` can import them (a decorated file cannot be imported by Node).
3. **The switch's place:** the left group, after the context badge, beside the demo marker. Frame F3's Tab sequence and box order follow it.
4. **The help text is the description and the tooltip,** not visible text. The header has no room for it (measured), and `Tooltip` allows text that reaches assistive technology another way.
   - In the drawer band the label is visually hidden and the tooltip names the switch, as the theme button's does. The trigger is the measured 104px.
5. **The announcement is the switch's own state.** The change is announced through `aria-checked` on the focused switch (the switch pattern; inference: not measured with a screen reader). The `Announcer` says nothing, because a page announcement would need a new public string, a veto item.
6. **The stored key:** `ocutalon.demoView.off` (`'1'` off, `'0'` on), so a missing or unreadable value is on.
7. **Device tab counts on return:** a fresh look, so they start at 0, as on a load.
8. **The guide's selection on return:** the current step, as on a load, per the AC's "at the step the session's own state gives". A step the user selected before going off is not kept.
9. **The e2e placement:**
   - The structure and behaviour cases go in `live:demo-switch`, for the real server switch in both modes and its own README session that no other unit asserts on.
   - The approval case goes in `live:answers`, for its fixtures.
   - The sign-in unit gets no new case (README is pinned there; F3 only changes).
10. **The CI cost (inference):** `live:demo-switch` gains about 60-90 s (locally 290-320 s, so under about 7 minutes) and `live:answers` about 15-25 s. No group gains a unit. shards-2 (with demo-switch) stays under about 32 minutes, and browser (answers) under about 27. Implement records the measured times.
11. **The stacked header wraps by design, with room above and below.** The stacked `.side` groups wrap (`flex-wrap`) so that nothing scrolls across from 320px, and the stacked `.header` has 4px of block padding (`--space-1`), so that the home link's focus ring stays inside the window when the left group wraps (floor G5 at 200%). A single-row stacked header is unchanged (its 48px minimum holds).
12. **A control class of its own.** The switch carries `.header-switch`, not `.header-button`, because it is not a menu button and the cases that pick the account button read `app-header button.header-button` `.last()`.
13. **F7 (frame.spec.ts) gets one Tab step.** F7 walked Tab from the home link to the Visual Trace button; the switch is now the first stop. The step is added in the file F3 is in (the spec said "change nothing else" of F3 only).
14. **The answers project's case count.** `web/scripts/playwright-projects.test.mjs` pinned X1 to X10 and 20 cases; it now pins X1 to X11 and 21 (the spec's own count).
15. **Track and thumb sizes are minimums.** `floor-sources` allows no fixed `height`, so the 18px track and the 12px thumb use `min-height`.
16. **G4 (floor) follows the lead's ruling of 2026-11-01 (U-202).** In `layout.spec.ts` `expectColumn`, the compact header with the Demo view switch present and more than one control row must be at most a quarter of the window high; otherwise it stays shorter than at 1280x720. EXPERIENCE.md's "Narrower than 1024" row carries the ruling's AMENDED marker.

**Veto items:** none.
- The two strings are the AC's own.
- Nothing touches security, roles, stored data, a dependency, an AD or a PRD guarantee.

## Verification

`<B>` means `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=4 stage=<stage>'`, run from the worktree root.
- **Tags:** fresh `e4s9i`; QA `e4s9q`; review `e4s9r`. There is no warm stack: no server class changes.
- **Slot B is not needed.** If an IRIS MCP call is ever made, use `server` `ocutalon-slot-b` and namespace `OCUTALON`, checked first with `iris_server_info`.
- **One command per foreground call** (`timeout: 600000`), and one `iris_execute_tests` per message.
- **Flakes** (one rerun): DW-349, DW-376, DW-396, DW-414, DW-333, DW-415, DW-462, DW-471, DW-497.

**Commands:**

`(loop)`:
- `npm --prefix web test` -- expected: every node test passes (`demo-view-sources`, `ux-strings`, `announce-focus-sources`, `floor-sources`, `shell-styles` and `guide-view` included).
- `npm --prefix web run lint` -- expected: exit 0.
- `<B> OCUTALON_RUN_TAG=e4s9i ci/iris.sh build` -- run before any live unit, and again after any `web/` change or merge.
- `<B> OCUTALON_RUN_TAG=e4s9i ci/iris.sh live demo-switch` -- expected: all PASS, with mode 0 and mode 1 including `view.spec.ts`. About 350-410 s; record the time.
- `<B> OCUTALON_RUN_TAG=e4s9i ci/iris.sh live answers` -- expected: every case passes, X11 included. That is 21 by the count at `5927cadb` (10 in `answers.spec.ts` and 10 in `close-loop.spec.ts`, plus X11). Record the time.
- `<B> OCUTALON_RUN_TAG=e4s9i ci/iris.sh live floor` -- expected: PASS in all three projects. This covers the scan, words, keyboard and layout of the new header control. About 330-370 s.
- `<B> OCUTALON_RUN_TAG=e4s9i ci/iris.sh live sign-in --part 1/2` -- expected: PASS (F3 is in part 1). About 5.5 min.

`(once)`:
- `<B> OCUTALON_RUN_TAG=e4s9i ci/iris.sh live sign-in --part 2/2` -- expected: PASS, case count unchanged.
- `<B> OCUTALON_RUN_TAG=e4s9i ci/iris.sh live demo-path` -- expected: PASS, with STEP 1's counts as on the base head.
- `<B> OCUTALON_RUN_TAG=e4s9i ci/iris.sh live online-demo` -- expected: PASS, R8 included. Record its `MEASURED R8` lines. It should take under about 8 minutes locally (inference: 631 s on the CI runner).
- `bash docker/tests/test-web-build.sh` -- expected: passes.
- `bash ci/checks.sh` -- expected: exit 0.
- `grep -n 'Demo view' _bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md _bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/DESIGN.md` -- expected: each hit is in a section that carries the `ADDED 2026-11-01, Story 4.9` marker.
- At the end, also after a failure: `<B> OCUTALON_RUN_TAG=e4s9i ci/iris.sh teardown`.

**Planned mutations (Rule 19).** Apply each one, observe red, revert, and confirm that `git status --short` and `git diff --stat` are unchanged. Record each as `mutation: … → …`.
- **AC1:**
  - the switch renders `@if (true)` instead of `available()` → V0 (a switch in mode 0);
  - drop `role="switch"` → V1.
- **AC2:**
  - `device-panel.ts` `demo` reads `this.live.snapshot()?.demoMode === true` → V2's structure equality (Simulated devices present) and `demo-view-sources` (a);
  - `skip-links.ts` ignores the signal → V2 (the skip-link list).
- **AC3:** `demo-guide.ts` passes `this.live.snapshot()` to `guideOf` → `demo-view-sources` (b).
- **AC4:** `badge` reads `demoView.on()` → V5 (no pill with the switch off).
- **AC5:**
  - `set()` also calls `this.live.retry()` → V1 (a `/state` request seen);
  - `set()` skips `writeFlag` → V1 (on after the reload).
- **AC6:** the request card in the incident card renders only while `demoView.on()` → X11 (no Approve while off).
- **AC7:** `demo-guide.ts`'s view effect skips an undefined view (`if (view === undefined) return;`) → V4 (step 1 still selected on return).
- **AC8:** the drawer-band rule hides nothing (the label always shows) → V5 at 1024 (the right group ends past the header, or the page scrolls across).
- **AC9:** change one word of the help text in EXPERIENCE.md → `ux-strings` "finds each ux and design string in its document".

**Recorded mutations (implement, Rule 19).** Each was applied, built (`ci/iris.sh build`), run, observed red, and reverted (the tree was byte-identical to its state before: `git diff` and `git status --short` equal, rebuilt after the revert).
- mutation: the switch renders `@if (true)` instead of `available()` -> `live:demo-switch` mode 0, V0 red ("demo mode is off on the server: no switch").
- mutation: drop `role="switch"` -> `live:demo-switch`, V1 red (and every case that finds the switch by role); `demo-view-sources` (e) red.
- mutation: `device-panel.ts` `demo` reads `this.live.snapshot()?.demoMode === true` -> `live:demo-switch` V2 red ("no Simulated devices"), V0 structure red in mode 0, and `demo-view-sources` (a) and (c) red.
- mutation: `skip-links.ts` ignores the signal -> `live:demo-switch` V2 red (with V0 in mode 0).
- mutation: `demo-guide.ts` passes `this.live.snapshot()` to `guideOf` -> `demo-view-sources` (b) red.
- mutation: `badge` reads `demoView.on()` -> `live:demo-switch` V5 (local demo pill) red.
- mutation: `set()` also calls `this.live.retry().subscribe()` -> `live:demo-switch` V1 red ("no request but the poll").
- mutation: `set()` skips `writeFlag` -> `live:demo-switch` V1 red (a run of six mutations; V1 was the only case that needed it).
- mutation: the incident card's request cards render only while `demoView.on()` -> `live:answers` X11 red ("the chat card keeps Approve"); the other 20 cases passed.
- mutation: the view effect of `demo-guide.ts` skips an undefined view -> `live:demo-switch` V4 red.
- mutation: the drawer-band rule hides nothing (the label always shows) -> `live:demo-switch` V5 red (the label-hidden check at 1024).
- mutation: one word of the help text changed in EXPERIENCE.md -> `ux-strings` "finds each ux and design string in its document" red.
- mutation: the stacked header forced to `min-height: 40vh` (`header.ts`, rebuilt) -> `live:floor` G4 at 200% red ("with the Demo view switch the compact header may wrap to a second row, and stays within a quarter of the window (360px)"), 4 cases red in all: the two column cases through the quarter check (1000x800 and 200%), plus the empty-chat G4 and G5 at 200%, which the tall header starves of room; reverted from my own backup, tree byte-identical, rebuilt, and `live:floor` is 106 of 106 without it.
- mutation (review pass, built with `ci/iris.sh build`, run, red, reverted from my own backup, tree byte-identical, rebuilt):
  - `chat-panel.ts` `demo` reads `demoView.available()` -> `live:demo-switch` V2 red ("the non-demo empty chat line").
  - `status-rail.ts` passes `demoView.available()` to `railView` -> `live:demo-switch` V2 red ("and the non-demo empty checks line"; it ran in a second run because the chat line fails first).
  - `demo-view-switch.ts` blurs the target on click -> `live:demo-switch` V1 red ("focus stays on it").
  - `DemoView.set()` announces through the `Announcer` -> `live:demo-switch` V1 red ("nothing was announced").
  - `demo-guide.ts` `follow()` announces for every view -> `live:demo-switch` V4 red ("no step announcement").
  - `header.ts` drops the stacked `.side` `flex-wrap` -> `live:demo-switch` V5 red ("320px: nothing scrolls across").
  - `DemoView.set()` calls `window.sessionStorage.setItem` unguarded before the state -> `live:demo-switch` V6 red ("a press turns it off for the page").
  - The label rule is still the AC8 line above; V1's and V5's tooltip assertions were added in this pass and are exercised by the green run (a swapped tooltip branch reads the other text).
- The runs that held several mutations at once (the run of six and the run of two) were read test by test: each red case is the one that the mutation names above.
- QA pass (tag `e4s9q`; lane B): files changed or added, all `(QA)`:
  - `web/e2e/demo-switch/view.spec.ts` (QA): V7 (the Telegram card, section and link are the same with the switch off and on, for the states off, rejected and on on a local demo and for off on the online demo), V8 (a failed snapshot: no switch, whatever this tab stored), V9 (only a stored `1` reads off; `0`, empty, `true` and `off` read on; a press writes `1` and `0`); V4 gains a network check (going off and back on sends and loads nothing but the poll).
  - `web/scripts/demo-view-sources.test.mjs` (QA): `DemoView` calls no announcer, focus, server client or reload; `view.spec.ts` takes no screenshot and reads no pixel.
- QA mutations (each applied, `ci/iris.sh build`, run, red, reverted from the stage's own backup in scratch, tree identical to before by `git diff`, rebuilt, and `live:demo-switch` is green again: mode 0 6 passed, mode 1 23 passed, 326 s). Three source mutations were run in one live run and read test by test.
  - mutation: the Telegram card in `status-rail.ts` wrapped in `@if (demoView.on())` -> `live:demo-switch` V7 red (the card is gone after the switch goes off).
  - mutation: `DemoView.available` is `computed(() => true)` -> `live:demo-switch` V8 red ("no Demo view switch without a snapshot that says demo mode"); V2 and, in mode 0, V0 and the badge, phone and mailbox specs red too.
  - mutation: the stored value `0` also reads off (`!readFlag(OFF) && !readFlag(ON)`) -> `live:demo-switch` V9 red ("a stored "0" reads on"); no other case red.
  - mutation: `set()` also calls `this.live.retry().subscribe()` -> `live:demo-switch` V1 red ("no request but the poll", `GET /state`) and V4 red (the new network check).
  - mutation: `set()` also calls `this.live.retry()` -> `demo-view-sources` "has DemoView call no announcer, focus, server client or reload" red.
  - mutation: `await expect(page).toHaveScreenshot();` appended to `view.spec.ts` -> `demo-view-sources` "has view.spec.ts take no screenshot and read no pixel" red.
- Code review (tag `e4s9c`, lane B): mutation: `demo-view-switch.ts` `.label { display: inline-block; width: 0; overflow: hidden; }` (the name kept, the label gone from view) -> `live:demo-switch` V5 red ("1440px: the label takes its width"), the other 22 mode-1 cases passed; reverted from the stage's own backup, tree byte-identical (`git status --short`, `git diff --stat` and `git diff` equal), rebuilt. After the review patches: `npm --prefix web test` 1135 pass, lint 0; `live:demo-switch` mode 0 6 passed, mode 1 23 passed (324 s); `live:floor` 106 passed (392 s); `live:sign-in --part 1/2` 127 passed (332 s); `live:answers` 21 passed (356 s); stack `e4s9c` torn down.

**Shared surfaces:**
- the header's control list, box order and Tab sequence (frame F3; any floor or online walk; R8's right-group fit, read only);
- the skip-link list per demo view (floor keyboard K-cases keep the demo list with the switch on);
- the landmark and region lists (frame F1, F2);
- the UX string inventory (`ux-strings` `IMPORTED` and `SOURCES`);
- the speaker and focus-source lists (`announce-focus-sources`, unchanged);
- the key-binding list (`floor-sources`, unchanged);
- the tokens read (`shell-styles`);
- the per-component demo-mode assertions that use `changeSnapshot` `demoMode` (`frame` F2 and F3, `phone/phone.spec.ts`, `demo-switch/*`), unchanged because the switch defaults to on;
- the README session of the demo-switch stack (V3 adds one turn, after every other spec);
- the ANSWERS user's rows (X11 cleans up in `finally`).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

This pass: the lead's G4 ruling (U-202) applied, then the review of the whole story (diff from `cc0418c4`, untracked files included).

**Summary.** A client-only "Demo view" switch in the header (demo mode only, on by default, kept per tab). One `DemoView` signal (the server's demo mode and the switch) feeds the guide, Break the feed, the simulated devices, the skip links, the empty chat and the rail's empty checks line; the header pill keeps the server's flag. Nothing is sent to the server. The stacked header wraps so that nothing scrolls across from 320px. EXPERIENCE.md and DESIGN.md carry the switch with markers; floor G4 now allows a second header row in demo mode (a quarter of the window at most), as the lead ruled.

**Files changed.**
- `web/src/app/shared/demo-view.ts`, `header/demo-view-switch.ts`, `header/demo-view-texts.ts` (new): the signal, the switch and its texts.
- `web/src/app/header/header.ts`, `header/skip-links.ts`, `chat/chat-panel.ts`, `devices/device-panel.ts`, `rail/status-rail.ts`, `guide/demo-guide.ts`, `phone/simulated-phone.ts`, `mailbox/simulated-mailbox.ts`: route through `DemoView`; the stacked header wraps.
- `web/scripts/demo-view-sources.test.mjs` (new), `ux-strings.test.mjs`, `playwright-projects.test.mjs`: source pins, the two strings, the answers project's X1-X11 / 21 cases.
- `web/e2e/demo-switch/view.spec.ts` (new: V0-V6), `answers/answers.spec.ts` (X11), `frame/frame.spec.ts` (F3 box order and Tab sequence, F7 one Tab step), `floor/layout.spec.ts` (G4 compact-header check, a sanctioned footprint extension).
- `EXPERIENCE.md`, `DESIGN.md`: the switch, with the 2026-11-01 markers; the "Narrower than 1024" row carries the ruling's AMENDED marker.

**Review.** 32 findings: 6 medium, 23 low, 3 false. Patches applied: 6 medium (tooltip assertions, mutations for the chat, rail, focus and announcement, V4's recorder, the stacked wrap, 1440 in V5, V6 for a throwing storage) and 1 low (a dead assertion deleted); no high. Deferred: none. Rejected with their reasons: see the Review Triage Log.

**Follow-up review recommendation:** `false` (this pass patched no high; the patches are test additions and a deleted assertion, with source unchanged).

**Verification.**
- `npm --prefix web test` 1133 pass; lint 0.
- `live:floor` 106 of 106 (after the G4 amendment, 389 s); `live:demo-switch` mode 0 6 passed, mode 1 20 passed (311 s, with V6 and the tooltip assertions); `live:answers` 21 passed (352 s); `live:sign-in` part 1/2 127 passed (330 s), part 2/2 96 passed (321 s); `live:demo-path` pass (145 s); `live:online-demo` 50 passed (383 s; `MEASURED R8` at 1024px: 0px across, right group -16px past the edge; at 640px: 0px across, -103.9px); `docker/tests/test-web-build.sh` passes; `ci/checks.sh` exit 0.
- The `grep -n 'Demo view'` check: every hit sits in a section with the story's marker (the "Narrower than 1024" hit carries the ruling's AMENDED marker).
- G4 mutation and the review-pass mutations: see `## Verification`. Stack e4s9i torn down; HEAD stayed `fa199fab` until finalize; nothing pushed.

**Residual risks.** Screen-reader speech of `aria-checked` is an inference (not measured). The tooltip is pointer-only by the app's design. The online demo's real-world header fit at 1024px keeps the 42px measured margin.

Footprint extensions: `web/e2e/floor/layout.spec.ts` (the lead's ruling). Amendments: EXPERIENCE.md "Narrower than 1024" row (the ruling's marker).
