---
title: 'Story 4.4: Show the demo guide and the Break the feed box'
type: 'feature'
created: '2026-10-25'
status: 'in-progress'
baseline_revision: '59409294fa4171ceb00d4f826c9c26f41d83f333'
baseline_commit: '59409294fa4171ceb00d4f826c9c26f41d83f333'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** In demo mode the server already derives the guide (`/state`'s `guide`, the `guide.state` event; Story 4.2) and answers `POST /api/v1/demo/break-feed` (Story 4.3), but the page shows neither. A judge sees no guide, no one-click prompts and no Break the feed control.

**Approach:**
- A guide-owned component renders the "Demo guide" region from the server's guide view. The region sits between the banners and the rail and chat, in `app.ts`.
  - Row 1 holds the steps; row 2 is the prompt bar.
  - Steps 1 and 2 send their exact prompts through the existing `ChatOutbox` with `fromGuide`.
- A feed-owned box at the region's right presses the route. Its look and lines come from `guide.state` (`breakFeed`), the press's answer and `watch.progress`.
- Two CI mock scenarios under `ci/mock/scenarios/B/` answer the two prompts.
- The rail's focus-ring helper gets the 1 px margin of DW-198.

## Boundaries & Constraints

**Always:**
- **Server-derived (AD-12).** The page never decides any of these; it shows what `guide.state` says:
  - whether a step is done;
  - the current step;
  - Break the feed's availability, reason or stage.

  The page computes only four things: the elapsed time, the 90 s and 3 min lines from that elapsed time, which step is selected, and which `watch.progress` line is the newest. The button's activity always follows the server's `active` (EXPERIENCE L606: "The button follows the server's state").
- **The guide view.** It is the latest `guide.state` from `live.store()` or, when there is none, `live.snapshot().guide`. It shows only while `snapshot.demoMode` is true; a snapshot that still carries `guide` with `demoMode` false shows nothing.
- **Contended files.** `web/src/app/api/**` is not edited:
  - `guide` is read through a guide-owned type, `StateSnapshot & { guide?: GuideStatePayload }`, using the generated `live/payloads.ts`;
  - the press is a guide-owned `HttpClient` call through the existing envelope interceptor (veto item V1).
- **Exact texts.** Every visible or accessible string is an exact UX or AC string (EXPERIENCE.md L225-230, L268-273, L330-334, L405-436, L572-607; DESIGN.md L761-774; epics.md L2292-2327).
  - Quotes are straight ASCII.
  - Code writes U+2026 and U+00B7 as `\u2026` and `\u00B7` (Rule 14).
  - The elapsed time follows EXPERIENCE L183's format ("23 s", minutes under an hour, full words for accessible text).
  - New public text is V2 only.
- **Announcements and focus** (conventions row "Announcements and focus").
  - The page speaks only through `Announcer`. The guide announces "Step {n} of 5: {step}"; the box announces only "Sent. OcuTalon usually notices within a minute.". The first snapshot is silent, and so is any ticking.
  - Focus moves only when an update removed the focused element, through `shared/focus-rule.ts`, or when the user acts. No live region, live role or `aria-live` is added.
- **Box rules.**
  - The box always shows "Demo control".
  - An inactive button stays focusable with `aria-disabled` (never `disabled`), and a press on it sends nothing.
  - Its visible hint or status line is its `aria-describedby`.
- **Focus rings** stay inside the viewport and every scroller at every tab stop (floor G1, K4, G5).
- **Texts and styles live where they do today.** Strings sit in framework-free `*-view.ts` modules as `*_TEXTS` constants. Styles come only from DESIGN.md tokens (`tokens.css`); no opacity on text.

**Never:**
- No server, payload, route, table or live-event change: Story 4.2 and Story 4.3 are consumed as built.
- No edit to `web/src/app/api/**`, `docker/**`, `ci/mock/**` outside `scenarios/B/`, `Test/{Agent,Tools,Bridge,Contract}/**` (calling them is fine), or `web/src/styles/tokens.css` (it is generated).
- Not in this story:
  - steps 3-5's prompt texts and buttons (Go to Break the feed, Show me, Open the trace), step 3's waiting text, step 4's variants, the finish state, Run again and the markers endpoint. These are Story 4.7 (epics L2406-2420), so the prompt bar holds no prompt while step 3, 4 or 5 is selected;
  - the simulated devices (Stories 4.5 and 4.6);
  - turning on the demo-path `notBuilt(..., '4.7')` parts;
  - gating the prompt buttons at the allowance limit (UX-DR45 states it; no Story 4.4 AC does).
- Never claim progress the server did not report. A `watch.progress` line from an earlier run is never shown.

## I/O & Edge-Case Matrix

Conventions for the rows:
- "View" is the guide view. Steps are 1 Watch, 2 Reminder, 3 Break the feed, 4 Approve, 5 Open the trace.
- P1 = "Watch the Orders production and only tell me if something needs me."
- P2 = "Remind me in 1 minute to stretch."
- H1 = "Ask OcuTalon to watch the Orders production first (step 1)."
- H2 = "Finish the current Orders incident first: approve or reject its fix, or dismiss the incident."

| # | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| 1. Blank guide | demo on; view step 1, nothing done, `breakFeed {active:false, reason:not_watching}` | Region "Demo guide" between `.banner-slot` and the rail and main. Row 1 holds the label "Demo guide", the five steps joined by decorative chevrons (`aria-hidden`), "About 2 minutes" and a ghost "Hide guide". Step 1: teal disc "1", `aria-current="step"`, name "Step 1, Watch, current". Steps 2-5: hollow circles with numbers, named "Step {n}, {label}, upcoming" (V2). Row 2 (sunken): `Next:` `"P1"` and **Send**. The box at the right: "Demo control", inactive button "Break the feed" (`aria-disabled`), H1 beneath it as its description, and a **Do step 1** link-styled button | no guide view: no region |
| 2. Demo off | `snapshot.demoMode` false (even with a `guide` key) | No region and no box. The empty chat's last line is "Ask OcuTalon to watch a production, set a reminder, or say what you need."; empty Background checks read "Ask OcuTalon to watch a production." | none |
| 3. Demo texts | demo on, empty chat and no checks | The last line is "Start with step 1 of the demo guide above."; Background checks read "Nothing yet. Step 1 of the guide sets up a watch." | none |
| 4. Select | press step 2 (or any step), in any order | Step 2 gets the 2px bottom bar (ink, never a teal ring), and the prompt bar shows `"P2"` and **Send**. `aria-current` stays on the current step, and nothing becomes done | steps 3-5 selected: the prompt bar holds no prompt (Story 4.7) |
| 5. Send | **Send** on step 1 or 2 | `POST /messages` sends `{clientId, text: P1 or P2 exactly, fromGuide: true}` through `ChatOutbox.send(text, true)`. The message shows the caption "From the demo guide · {time}". Nothing is announced for the send, and the step is not marked done by the click | a second press while that message is still `sending` sends nothing |
| 6. Advance | a later view whose `step` is greater (same `runEpoch`) | The selection moves to the new current step, and "Step {n} of 5: {label}" is announced once. Focus on the prompt bar's action stays on the prompt bar's action (or moves to it, if the update replaced it; with no action, to the prompt text with `tabindex="-1"`, else to the prompt bar). Focus anywhere else (the composer, a step) stays put | first view, a reload with the same step, or a lower step (Run again): silent, no focus move |
| 7. Telegram row | view `telegramRow` true | A buttonless line, "Optional: scan the QR code in the Telegram card to get the notice on your own phone.", shows before step 1's prompt line in the prompt bar | false: absent |
| 8. Box active | `active:true`, stage not sending/waiting/still_waiting | An attention button with `zap`, "Break the feed". On step 3 it adds a 4px `action` left bar and a "Next step" tag. On step 5 it is the secondary style with no tag. Any other step: attention, no tag | none |
| 9. Incident in progress | `incident_in_progress`, stage `""` or `notice_arrived` | Inactive, H2 beneath it as its description, no Do step 1 | none |
| 10. Press | active; press | Spinner, `aria-busy`, `aria-disabled`; the line reads "Sending 50 orders…". On 200: inactive, and "Sent. OcuTalon usually notices within a minute." is announced once per `startedAt`, with the elapsed time "{n} s" (spoken "{n} seconds"; "{n} min" from 60 s). This local state holds until a guide view shows that `startedAt` past `sending`, or a different `startedAt` (another run, or none) | 409: H1 or H2 by `error.code` until the next view, nothing announced. 500 or a network error: no new text, and the box follows the view. No answer in 10 s: ServerButton's existing notice |
| 11. Progress | stage `waiting`, and `watch.progress` events for refs first seen after this run's stage appeared on the page | The newest stage's line replaces the sent line: `noticed` → "OcuTalon noticed failures in the Orders production", `settling` → "Waiting for the failures to settle", `diagnosing` → "Working out the cause from the failed messages". The elapsed time stays, and no line shows a count | a ref already in the store before the run: ignored |
| 12. Late stages | elapsed ≥ 90 s or stage `still_waiting`; elapsed ≥ 180 s or stage `no_notice` (no notice yet) | From 90 s: "Still waiting. The notice will appear in the chat and on the Simulated phone tab." plus the elapsed time, replacing any progress line. From 180 s: "No notice after 3 minutes, so something went wrong with this run. Open the Orders watch's trace in Background checks, or try again." The button stays inactive until the server's view says `active` (`no_notice`, up to one 15 s tick later) | stage `notice_arrived` ends the lines (row 9). Stage `sending` with no press of this page: "Sending 50 orders…", button inactive with no spinner |
| 13. Not live | the guide and the box | No `aria-live`, live role or `aria-atomic` in either. The ticking elapsed time is never announced | none |
| 14. Hide/Show | press "Hide guide" | One bar, "Demo guide · step {n} of 5 ·" plus a **Show guide** button (`aria-expanded="false"`), min height 40px. The box keeps its place and rules at the bar's right end, with "Demo control" inline before the button. Focus goes to Show guide, and the choice is stored under `ocutalon.guide.hidden` and survives a reload. Show guide restores the guide, with focus on Hide guide | storage throws: works for the page's life, no console error |
| 15. Sizes | viewport under 680px tall; 1024-1279px wide; under 1024px | Under 680 tall: one compact row (numbered steps and the prompt bar), min `--space-guide-compact-height`, nothing clipped, and at 1280x600 the page does not scroll. 1024-1279 wide: numbers instead of labels, names unchanged. Under 1024: header, banners, the guide (box after the prompt bar), then main, then the rail | none |
| 16. DW-198 | a rail control at the rail's edge in WebKit (1280x600) | `revealRing` scrolls whole pixels until the ring plus 1 px lies inside the scroller. Floor G1's ring check passes | none |
| 17. Mock | a Chat turn whose input is P1 or P2 (after the `Agent.Input` preamble), against the CI mock | The mock picks `guide-watch` or `guide-reminder` (`selectedBy` `prompt`), and the reply is the scenario's text, not a fallback. `guide-reminder` calls `set_reminder` `{text:"stretch", delaySeconds:60}` first | a marker in the same message still wins (Test.Tools.Reminders) |
| 18. Real data | FLOOR session on the floor stack: an Orders check, then a reminder, are seeded and published | The real `guide.state` advances the page to step 2, then to step 3 (rows 6 and 8). A real press answers 200; "Sent. …" shows and is announced once. A `watch.progress` `noticed` sunk for a new ref shows its line | none |

</intent-contract>

## Code Map

**Page frame and live data (Lane B, Epic 2's; extend):**
- `web/src/app/app.ts:23-27` -- the shell template: skip links, header, `.banner-slot`, `router-outlet`. The guide's slot goes between `.banner-slot` and `router-outlet` with `flex: none`. The host is a flex column, viewport-high from 1024px (`:35-40`). There is one route (`app.config.ts:12`).
- `web/src/app/main-page/main-page.ts:65-121` -- the rail (`section.rail`) and `main.main`; `place()` (`:309-326`) relies on `:scope > .rail` and `.main`, so do not wrap them. `:290-292` is `reveal()` → `revealRing`.
- `web/src/app/live/live-state.ts:151,177-190` -- `snapshot` and `store` signals; a reload calls `accept()`, which resets the store.
- `web/src/app/live/live-store.ts`:
  - `:49,53,55` the collections `watchProgress` (keyed by `ref`, in store order), `guideState` and `breakfeedProgress` (latest only);
  - `:120-126` `fromSnapshot` seeds `guideState: undefined` and never reads `snapshot.guide`.

  No change is needed.
- `web/src/app/live/payloads.ts:28-38,233-246,270` -- `GuideBreakFeed`, `GuideStep`, `BreakFeedProgressPayload`, `GuideStatePayload` and `WatchProgressPayload`. The file is generated: read it, never edit it.
- `web/src/app/api/api-types.ts:32-49` (CONTENDED, read-only) -- `StateSnapshot` has no `guide`. `:59-63` `MessagePost.fromGuide` already exists. The interceptor (`api/envelope.interceptor.ts`) adds the AD-13 headers to any POST under `/ocutalon/api/`.

**Chat and rail texts:**
- `web/src/app/chat/chat-outbox.ts:49` -- `send(text, fromGuide = false)`, public and `providedIn: 'root'`. `:82` announces only a failure.
- `web/src/app/chat/chat-view.ts`:
  - `:46` `fromGuide: 'From the demo guide'`; `:264-270` `captionOf`, which already captions guide sends;
  - `:49-52` the empty texts. Add the demo line beside `emptyAsk`.
- `web/src/app/chat/empty-chat.ts:17,34-36` -- the last line, whose doc says "Story 4.4 adds the demo mode's line". It is used at `chat-panel.ts:109`.
- `web/src/app/rail/rail-view.ts`:
  - `:33` `emptyChecks`;
  - `:323-326` `railView(store, format)` builds the checks section; it is called at `status-rail.ts:236`. Demo mode reaches it from `live.snapshot()?.demoMode`.

**Shared pieces to reuse:**
- `web/src/app/shared/server-button.ts:29-108` -- the busy button: spinner, `aria-busy`, `aria-disabled`, `describedBy`, and `BUSY_NOTICE` after 10 s. Today it has no server-inactive state, and its press always calls.
- `web/src/app/shared/announcer.ts:31` -- `announce(text)`, polite only.
- `web/src/app/shared/focus-rule.ts:53` -- `keepFocus(host, injector, popovers, rule)`, called from an effect before render. `whenGone` is used only when an `item` held focus; otherwise focus falls back to `main.main`.
- `web/src/app/shared/stored-flag.ts` -- `readFlag` and `writeFlag`; keys are `ocutalon.<area>.<flag>`, value `'1'`.
- `web/src/app/shared/layout-view.ts:14-23` -- `LAYOUT_QUERIES` (stacked, framed, drawer `(1024px <= width < 1280px)`, wide). There is no height query yet.
- `web/src/app/chat/page-time.ts:82-100,170-194` -- `WHEN_TEXTS` and `countdownText` (seconds under a minute, minutes under an hour, spoken forms). The elapsed time extends this sibling.
- `web/src/app/icon/icon.ts:4-24,58,141` -- `zap` and `check` exist; `chevron-right` does not. Icons are Lucide paths (ISC) in the SVG `@switch`.
- `web/src/app/shared/reveal-ring.ts:22-38` -- `above` and `below` are `scrollPadding` sums with no margin and no rounding (DW-198).
- `web/src/styles/tokens.css` (generated):
  - `:115-116` `--space-guide-min-height` 92px and `--space-guide-compact-height` 56px;
  - `:120` `--space-device-width` 352px and `-wide` 384px;
  - `:233-261` `--demo-guide-*`, `--guide-step-*`, `--guide-collapsed-bar-*` and `--break-the-feed-*`.

  `--break-the-feed-next-step-accent` and `--guide-step-selected-indicator` are descriptive strings, not valid CSS values: build the bars from `--action` and `--ink`. `styles/controls.css` holds `.button-attention|secondary|ghost|inactive`. The 4px bar pattern is `chat/notice-card.ts:59-60`.

**Source-scanning unit tests that pin the new files** (`web/scripts/`, run by `node --test`, importing `.ts` view modules directly, so use erasable syntax and type-only imports):
- `ux-strings.test.mjs`:
  - every template text and aria value needs one `SOURCES` entry (`ux` verbatim in EXPERIENCE.md, `design`, `ac` keyed by story title, `ruled`, `format`; table about `:280-300`);
  - `IMPORTED` (`:412-417`) must list each new `*_TEXTS`;
  - only U+2026 and U+00B7 (written `\u2026` and `\u00B7`) are allowed beyond ASCII;
  - `:162,199` pin the two old empty strings.
- `announce-focus-sources.test.mjs`:
  - `:94-103` the speakers list (add the guide and box files);
  - `:109-116` `FOCUS_CALLS` (a count and reason per file);
  - `:132-138` the `keepFocus` hosts;
  - also no `aria-live`, no live roles, and `afterNextRender` only in four files.
- `floor-sources.test.mjs`:
  - `:362` bans `tablist`, `role="tab"` and a bare `prompt(`, `alert(` or `confirm(` call (do not name a signal `prompt`);
  - `:400-440` width `@media` only through the four `LAYOUT_QUERIES`, from the listed files (`:431`). A `(height < 680px)` condition is caught as a width query (`[<>=]\s*\d+px`);
  - `:214-219` `FIXED_HEIGHTS`;
  - `:286-299` scrollers;
  - keys Enter and Escape only; no `transition`.
- `layout-view.test.mjs:18-26` pins exactly the four queries.
- `reveal-ring.test.mjs:56-82` pins the exact scroll amounts (24, -24, -3, 20, and the no-call cases).
- `chat-view.test.mjs:428` and `rail-view.test.mjs:102,161` pin the old empty strings.
- `playwright-projects.test.mjs:184-191` lists the floor ids that must be `@browsers`.

**Budgets:** `web/angular.json:48-59` allows any component's styles 4kB (warning) and 8kB (error). Keep the guide and the box as separate components.

**E2E (shared surfaces, all on stacks in demo mode).** Every Docker throwaway runs in demo mode (`api.spec.ts:125`), so the guide shows in every chromium and floor spec.
- `web/e2e/chat/chat.spec.ts:183-187` -- C1 asserts the three `.line` texts, `emptyAsk` last. `:145` allows exactly one h2 in main.
- `web/e2e/rail/rail.spec.ts:111-116` (R1) and `web/e2e/demo-path/01-page.spec.ts:100-105` (`@floor`; title pinned at `playwright-projects.test.mjs:125-129`) assert `'Ask OcuTalon to watch a production.'`. 01-page's L44 comment leaves out the demo line.
- `web/e2e/frame/frame.spec.ts`:
  - `:71` h2s exactly `['Status','Chat']`, so the guide adds no heading;
  - `:88-91` DOM order header, `.banner-slot`, rail, main;
  - F2 (`:100-110`) already asserts no region "Demo guide" with demo mode off, through `changeSnapshot`.
- `web/e2e/banners/banners.spec.ts:195` -- h2s `['Status','Chat']`. `web/e2e/sign-in/shell.spec.ts:38` -- `main > *` count 2, so the guide stays outside main.
- `web/e2e/floor/layout.spec.ts`:
  - `:94-104` `placeOfFocus` (guide controls fall in `'other'`);
  - `:107-130` `walk`;
  - G1 `:136-185` ends its walk at the first stop whose name includes "Send" (`:174`), and the guide's Send comes first;
  - `:76-91` `layers()`;
  - G4 `:422-440`;
  - G5 `:537-573`.
- `web/e2e/floor/keyboard.spec.ts:350-380` -- K4's walk also ends at "Send".
- `web/e2e/floor/announcements.spec.ts:344-349` -- A7's `places` list (no `aria-live`).
- `web/e2e/floor/words.spec.ts:159` -- W2's selector list.
- `web/e2e/support/floor.ts`:
  - `:134` `openFloor`;
  - `:142` `applied`;
  - `:234-292` `readFocus` and `expectStopRing` (ring = box + outline-offset + outline-width; tolerance 0.5px).
- `web/e2e/support/iris.ts`:
  - `:47` `fixtureUser` (kinds are fixed by the contended `test-sign-in.sh`, so add no kind);
  - `:405` `sinkEvent`;
  - `:610` `cleanFixtureRows`;
  - `:697` `seedCheck` (`{namespace:'OCUORDERS', production:'OcuTalon.Demo.Orders.Production'}` gives an Orders watch);
  - `:722` `publishCheck`; `seedReminder` and `publishReminder`.

  `Test.Data.Fixture` `:315` `Clean` and `:467` `DropGuide` drop `GuideState` and `BreakFeedRun` only for fixture sessions.
- `web/e2e/support/api.ts:27` (`changeSnapshot`), `:37` (`post`); `support/clock.ts:109` (`runUntil`); `support/page.ts:53` (`recordAnnouncements`, `announcedTexts`).
- `web/e2e/demo-switch/badge.spec.ts:18` -- a page check that follows the stack's demo mode (runs with modes 0 and 1; Epic 4's own).
- `web/playwright.config.ts:36-48` -- `chromium` takes every folder except demo-path, demo-switch and floor, so a new `web/e2e/guide/` needs no project edit.

**Server (read-only; built in Stories 4.2 and 4.3):**
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - `:391` `/state`'s `guide` (last key, demo on only; empty strings dropped);
  - `:238-262` `BreakFeed` → 404, 500, 409 `{"error":{"code":"not_watching"|"incident_in_progress","message":H1|H2}}`, or 200 `{"state":"sent","startedAt"}`;
  - `:194` `fromGuide` is true only for JSON true.
- `src/ocutalon/cls/OcuTalon/Demo/Guide.cls:28,31` -- `REASONS` and `STAGES` (`sending, waiting, still_waiting, no_notice, notice_arrived`; `still_waiting` from 90 s, `no_notice` from 180 s). `step` is the first step not done.
- `src/ocutalon/cls/OcuTalon/Live/Payload/WatchProgress.cls` -- `STAGES` `noticed, settling, diagnosing`. Nothing publishes it in this tree (Epic 5).

**CI mock (`ci/mock/`; only `scenarios/B/` is ours):**
- `scenarios.mjs:208` -- `loadScenarios` reads `A/*.json` then `B/*.json`, dotfiles skipped.
- `:161` -- `match.prompt` is allowed only under B.
- `:255-271` -- a prompt may not repeat or contain another.
- `mock.mjs:249-278` -- the order is marker, then prompt (`text.includes`), then mock key.
- `scenarios/A/reminder-set-relative.json` -- the reply template.
- `scenarios/B/.gitkeep` -- the folder's only file.

The mock's tests run in `docker/tests/test-mock.sh` and need no list update.
- `src/ocutalon/cls/OcuTalon/Agent/Input.cls:23` -- a user item is `preamble_$C(10,10)_item.Text`, so the prompt reaches the mock verbatim.
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls:14` -- the only toolset is `OcuTalon.Tools.Reminders`; there is no watch tool until Epic 5.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` (Lane A, call only):
  - `:276` `NewRequest("turn","user",text,.ref,owner)`;
  - `:378` `Run`;
  - `:918` `FindRequests`;
  - `:456` `PointKeys` and `:463` `RestoreKeys`.
- `Test/Contract/Mock.cls` -- `LogMark` and `LogSince`; log entries carry `selectedBy` and `scenario`.
- The pattern to follow is `Test/Tools/Reminders.cls:896-924` (`Turn`, `AssertTurn`; private in a contended class, so the few lines are rewritten, not called).

## Tasks & Acceptance

**Execution** (in dependency order):
- [ ] `web/src/app/shared/reveal-ring.ts` -- **DW-198**: a 1 px `MARGIN` past the ring on both edges, and the scroll rounded up to whole pixels (`Math.ceil`), in every engine. Update the contract comment (row 16).
- [ ] `web/src/app/shared/server-button.ts` -- add an input that holds the button `aria-disabled` and ignores presses while the server says the control is inactive (Rule 2: extend; existing callers unchanged).
- [ ] `web/src/app/chat/page-time.ts` -- add `elapsedText(sinceIso, nowMs)` → `{text:'{n} s'|'{n} min', spoken}` beside `countdownText`, never below 0, with its `WHEN_TEXTS` entries.
- [ ] `web/src/app/icon/icon.ts` -- add `chevron-right` (Lucide path, ISC, same header).
- [ ] `web/src/app/shared/layout-view.ts` -- a height query for the compact row (`'(height < 680px)'`), kept apart from the four width bands.
- [ ] `web/src/app/guide/guide-view.ts` (new; framework-free, erasable TS) holds:
  - `GUIDE_TEXTS`: the label, "About 2 minutes", "Hide guide", "Show guide", "Next:", the five labels, P1, P2, "Send", the Telegram line, the step-name pattern and its three states (V2), "Step {n} of 5: {step}", and the collapsed bar's "Demo guide \u00B7 step {n} of 5";
  - `type GuideSnapshot`, and `guideOf(snapshot, store)`, which returns `undefined` unless `demoMode`;
  - `guideView(view, selected)`: markers, names, `current`, `selected`, the prompt entry for steps 1-2 only, and the Telegram row;
  - `advance(previous, next)`: the announcement, or `null` (row 6).
- [ ] `web/src/app/feed/break-feed-view.ts` (new; framework-free) holds:
  - `FEED_TEXTS`: "Demo control", "Break the feed", "Next step", H1, H2, "Do step 1", "Sending 50 orders\u2026", the sent line, the three progress lines, the 90 s line and the 3 min line;
  - `boxView(view, local, watchLine, nowMs)` → `{style, busy, nextStep, line, hint, doStep1, elapsed}`, following rows 8-12;
  - `watchLine(watchProgress, baselineRefs)`.
- [ ] `web/src/app/feed/break-feed-api.ts` (new; V1) -- `@Injectable({providedIn:'root'})`, `press(): Observable<{state:'sent'; startedAt:string}>`, a POST to `/ocutalon/api/v1/demo/break-feed` with body `{}`. A 409 surfaces its `error.code`. Its doc names V1 and the planned move into `ApiClient`.
- [ ] `web/src/app/feed/break-feed-box.ts` (new component):
  - `ServerButton` with `zap`;
  - the local press result (Decided in-stage 5): the 200's `startedAt`, held until a guide view shows that `startedAt` past `sending` or a different `startedAt`, or a 409 code, held until the next guide view;
  - the baseline of `watchProgress` refs, taken when a run's stage first appears;
  - a 1 s clock only while the elapsed time shows;
  - one announcement per `startedAt`;
  - the **Do step 1** text-link button selects step 1 through an output (rows 1, 8-13).
- [ ] `web/src/app/guide/demo-guide.ts` (new component, `app-demo-guide`):
  - The region is labelled "Demo guide" by its visible label; it has no heading.
  - The steps are an `<ol>` of `<button>`s; the chevrons and `·` are `aria-hidden`.
  - The prompt bar uses `ChatOutbox.send(text, true)` and ignores a press while that send is still `sending` (row 5).
  - The selection is local and follows an advance.
  - It announces through `Announcer`, and keeps focus through `keepFocus` with a rule whose `whenGone` picks the prompt bar's action, else the prompt text (`tabindex="-1"`), else the prompt bar (`tabindex="-1"`).
  - Hide and Show are stored with `stored-flag` under `ocutalon.guide.hidden`; focus after either goes to the other button.
  - It renders the compact row, the drawer-band numbers, the stacked order and the collapsed bar (rows 1, 4-7, 13-15).
  - It hosts the box.
- [ ] `web/src/app/app.ts` -- the guide slot between `.banner-slot` and `router-outlet`; update the doc.
- [ ] `web/src/app/chat/chat-view.ts`, `empty-chat.ts`, `chat-panel.ts` -- `emptyDemo` "Start with step 1 of the demo guide above.", shown as the last line when `demoMode` (rows 2-3).
- [ ] `web/src/app/rail/rail-view.ts`, `status-rail.ts` -- `emptyChecksDemo` "Nothing yet. Step 1 of the guide sets up a watch." when `demoMode` (rows 2-3).
- [ ] `web/scripts/guide-view.test.mjs` and `break-feed-view.test.mjs` (new) -- every matrix row's view logic:
  - markers and names;
  - an advance with and without announcement (first view, same step, lower step);
  - the prompt entries (steps 3-5 none) and the Telegram row;
  - each stage, reason, active and step combination, the tag, secondary, the 409 override and its clearing, sending without a press;
  - the watch line's baseline and newest stage;
  - the elapsed boundaries 0, 59, 60, 89, 90, 179 and 180 s (format, the 90 s and 3 min lines, the button still following `active`);
  - `guideOf` with `demoMode` false.
- [ ] Shared-surface unit tests, each edited with its reason:
  - `ux-strings.test.mjs`: the sources of every new string, and `IMPORTED`;
  - `announce-focus-sources.test.mjs`: speakers, `FOCUS_CALLS`, the `keepFocus` host;
  - `floor-sources.test.mjs`: a height condition is not a width condition; the media and height lists if the new files need them;
  - `layout-view.test.mjs`;
  - `reveal-ring.test.mjs`: the new amounts (25, -25, -4, 21; no call at 105-195) and a fractional case that scrolls a whole pixel;
  - `chat-view.test.mjs`, `rail-view.test.mjs`: the demo lines;
  - `playwright-projects.test.mjs`: M1 and M2 tagged.
- [ ] `ci/mock/scenarios/B/guide-watch.json` and `guide-reminder.json` (new):
  - `guide-watch`: `match.prompt` P1, one text reply "The CI mock answered the guide's watch prompt.";
  - `guide-reminder`: `match.prompt` P2, with `reminder-set-relative`'s replies (`set_reminder` `{text:"stretch", delaySeconds:60}`, then "The CI mock set the reminder.").

  `name` equals the file name (row 17).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Demo/GuidePrompts.cls` (new; throwaways and CI only, guarded like `Test.Tools.Reminders`):
  - `PointKeys` in `OnBeforeAllTests`, `RestoreKeys` in `OnAfterAllTests` on every path;
  - `TestWatchPrompt` and `TestReminderPrompt`: a turn with exactly P1 or P2 through `RunnerFixture.NewRequest/Run`. The mock log's first entry for the turn has `selectedBy` `prompt` and the scenario's name. The answer is a `Reply` with the scenario's text, not a fallback. For P2, the model's second request carries a `tool_result` for `set_reminder` (row 17). The lane-b shard already holds `Demo`.
- [ ] `web/e2e/guide/guide.spec.ts` (new; chromium on the sign-in stack, README, no server writes):
  - Q1: the real blank guide of README, which watches nothing on this stack (`api.spec.ts:136-144`) (row 1). The demo texts (row 3) are checked under `changeSnapshot` with `chat: []` and `rail.checks: []`, so the result does not depend on README's history;
  - Q2: select in any order, steps 3-5 hold no prompt, done only from the view (row 4, via `changeSnapshot`);
  - Q3: Send for P1 and P2. `page.route('**/messages')` captures the body and fulfils 202. The caption shows, nothing is announced, and a double press posts once (row 5);
  - Q4: the Telegram row (row 7);
  - Q5: the box styles, hints, `aria-describedby`, and Do step 1 (rows 1, 8, 9);
  - Q6: a routed press. A delayed 200 shows busy, then sent, announced once, with `page.clock` elapsed. Then 409 for each code, and 500 (row 10);
  - Q7: the stages via `changeSnapshot` and `page.clock` (row 12). `waiting` at 89 s shows the sent line, and at 90 s the 90 s line, by the page clock. Page time 180 s with the server still `still_waiting` shows the 3 min line with the button still inactive. The server's `no_notice` with `active: true` shows the line with an active button. `sending` with no press shows no spinner;
  - Q8: Hide and Show, reload, and storage that throws (row 14).
- [ ] `web/e2e/floor/guide.spec.ts` (new; the floor stack, FLOOR user):
  - M1 `@browsers`: keyboard, names, `aria-current`, Enter selects, rings inside the viewport at 1280x720 and 1280x600 (rows 1, 4, 15);
  - M2 `@browsers`: the inactive box is focusable, `aria-disabled` and described; a press sends no request; Hide and Show `aria-expanded` and focus (rows 1, 14);
  - M3: real advance. `seedCheck` Orders plus `publishCheck`, then `seedReminder` plus `publishReminder`. Steps 2 then 3, each announced once. Focus on the prompt bar's Send stays on the prompt bar's action. Focus in the composer stays there. At step 3 the box is active with the tag (rows 6, 8, 18);
  - M4: a real press from step 3. Busy, then "Sending 50 orders…", then the sent line, announced once, with the elapsed time ticking and nothing more announced. `sinkEvent` `watch.progress` `{ref:new, stage:'noticed'}` shows its line. The `finally` removes the check and the reminder (`cleanFixtureRows`) and the batch's OCUORDERS messages (`Test.Data.Fixture.RemoveMessages([traceRef], "OCUORDERS")` via `irisScript`). It also deletes the FLOOR session's `BreakFeedRun` rows by its `SessionRef` via `irisScript`: FLOOR's session is not a fixture session, so `Clean` keeps them, and a run left under 180 s old would make M3 red when it runs after M4 (rows 10, 11, 18);
  - M5: layout. 1280x600 compact single row, 1100x720 numbers only, 1000x800 stacked order, the collapsed bar with the box at its right end, no live attributes (rows 13-15).
- [ ] Existing e2e, edited for the guide:
  - `chat/chat.spec.ts` C1: the demo last line;
  - `rail/rail.spec.ts` R1 and `demo-path/01-page.spec.ts`: the demo checks text, and 01-page's chat test also asserts the demo line;
  - `frame/frame.spec.ts` F1: the guide region between `.banner-slot` and the rail in the DOM order, and present once;
  - `floor/layout.spec.ts`: `placeOfFocus` gains `'guide'`; G1's walk ends at main's Send (`walk`'s `last` gets the place); `layers()` gains the guide (G4: slot ≤ guide < main);
  - `floor/keyboard.spec.ts` K4: ends at main's Send;
  - `floor/announcements.spec.ts` A7: the guide and box join `places`;
  - `floor/words.spec.ts` W2: the box's selector joins the list.
- [ ] `web/e2e/demo-switch/badge.spec.ts` -- a test: the region "Demo guide" and the box show, and the empty chat's last line is the demo line, exactly when `OCUTALON_E2E_DEMO_MODE` is 1. With 0 there is no region and the line is `emptyAsk` (rows 2-3, on a real switch).

- [ ] [CI] `ci` workflow, job `iris (browser)`, unit `live:sign-in`: `web/e2e/guide/guide.spec.ts:584` Q9 fails on the Linux CI host (ca4838f): "at the normal size the row is one line", expected 1 line, got 2 -- https://github.com/jbrandtmse/OcuTalon/actions/runs/40285090544/job/121446738347 -- with the CI host's Chromium fonts, row 1 already wraps at 1280x800 at the normal text size, so Q9's premise is font-dependent (it passed on macOS). Fix it so the case passes on Linux and macOS alike: preferably keep row 1 on one line from 1280px at the normal size in both font sets (for example tighter gaps or a smaller ghost-button padding, within DESIGN's tokens, or switching to the numbered steps by measured fit instead of only by the 1280px breakpoint), and make Q9 independent of font metrics (it may measure the fit first and assert the wrap and "nothing runs past the row" relative to that); keep the case able to fail on the `.row1` `flex-wrap` mutation. You cannot see Linux fonts locally unless you run the browser in a Linux container; say in the spec how the fix is shown to hold on Linux (CI on the next push counts).

**Acceptance Criteria:**
- **AC1.** Given demo mode on, when the main page renders, then the region "Demo guide" sits between the banners and the rail and chat, with row 1, the sunken prompt bar and the box at the right. Its step markers, names and `aria-current` come from the server's guide view. The empty chat and Background checks show the demo texts. With demo mode off (a faked snapshot or a real switch) none of it shows and the old texts return.
- **AC2.** Given the guide, when I select steps or a step's completion arrives from the server, then:
  - any step is selectable, and nothing is marked done by a click;
  - an advance moves the selection and announces "Step {n} of 5: {step}" once;
  - focus follows the focus rule: the prompt bar's action, or its text, only when the update replaced the focused element (UX-DR131, EXPERIENCE L410-415, the spine's "Announcements and focus" row, which names Story 4.4);
  - the Telegram row follows `telegramRow`.
- **AC3.** Given step 1 or 2 selected, when I press Send, then the exact prompt goes as my own message with `fromGuide: true`, shows "From the demo guide" and is not announced. Given the CI mock and a model key pointed at it, when a Chat turn's input is either exact prompt, then its B scenario answers it.
- **AC4.** Given the box, when it renders from the guide view, then "Demo control" always shows. Active is the attention `zap` button, with the 4px `action` bar and "Next step" tag on step 3 until pressed, and the secondary style on step 5. Inactive is focusable with `aria-disabled` and the reason's exact hint as its description, with **Do step 1** selecting step 1 for `not_watching`.
- **AC5.** Given I press Break the feed, when the run goes on, then:
  - the button goes busy with "Sending 50 orders…";
  - once sent it is inactive with "Sent. OcuTalon usually notices within a minute." (announced once) and the elapsed time;
  - the run's own `watch.progress` lines replace it, never with a count;
  - from 90 s and from 3 min (the page's elapsed time, or the server's stage if that comes first) the matching lines show, while the button's activity follows only the server's `active`;
  - the box is never a live region.
- **AC6.** Given the guide's size and visibility, when I press Hide guide, resize, or reload, then the collapsed bar, its `aria-expanded` Show guide, the box at its right end, the per-browser memory, the compact row under 680px tall, the numbers from 1024 to 1279px, and the stacked order hold. The floor suite stays green in all three browsers.
- **AC7.** Given DW-198, when a rail control at the rail's edge takes focus in WebKit at 1280x600, then its ring ends at least 1 px inside the scroller. G1 passes on the floor run, and on the Linux CI runs the lead records.
- **AC8.** Given the floor stack's FLOOR session with seeded Orders check and reminder rows, when their check and reminder events publish and the page presses Break the feed, then the page renders the real `guide.state` and the real `POST /v1/demo/break-feed` answer as rows 6, 8, 10 and 11 describe (M3, M4: Integration).
- **AC9.** Given the demo-switch stack, when demo mode is switched off and on for real, then the page hides and shows the guide and its texts (Integration).

### Review Findings

Code review 2026-10-26 (`review_mode` full; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, plus the reviewer's Rule 2 check). Each line: severity, fix-risk, footprint (all in-story, spec-clear). All patched; `npm --prefix web test` 624 pass, lint 0, `ci/checks.sh` 0, `live sign-in` 209 passed, `live floor` 80 passed (Chromium, Firefox, WebKit), `live demo-switch` passed.

- [x] [Review][Patch] A press from the server's `no_notice` view (the "try again" path) showed the earlier run's 3 min line, with "Sent" announced, until the next view -- med, fix-risk low (the view's stage is ignored while a sent press holds over another run's view) [web/src/app/feed/break-feed-view.ts:149]
- [x] [Review][Patch] The steps never wrapped: at twice the text size with labels (1280-1439px wide, 680px tall or more) they ran 41.6px past the row into the box -- med, fix-risk low (`.steps` wraps and may shrink) [web/src/app/guide/demo-guide.ts:169]
- [x] [Review][Patch] Focus on Do step 1 fell to `main.main` when an update removed it (EXPERIENCE focus replacement: nearest container) -- med, fix-risk low (keyed `step1`; `whenGone` gives the Break the feed button) [web/src/app/guide/demo-guide.ts:38, web/src/app/feed/break-feed-box.ts:60]
- [x] [Review][Patch] The live-view "Sent" announcement and the first view's silence after a reload were unpinned in the component -- med, fix-risk low (two Q10 cases routing `guide.state` events into real polls) [web/src/app/feed/break-feed-box.ts:236]
- [x] [Review][Patch] The `watch.progress` baseline taken in `follow()` was unpinned (the AC8 mutation emptied both captures) -- med, fix-risk low (Q10 baseline case) [web/src/app/feed/break-feed-box.ts:234]
- [x] [Review][Patch] The box's 10 s no-answer path had no test -- med, fix-risk low (new Q6 case on the page clock) [web/src/app/feed/break-feed-box.ts:220]
- [x] [Review][Patch] Q7 asserted the 89 s sent line before the box redrew (Rule 19: acting before ready) -- med, fix-risk low (the redraw signal first) [web/e2e/guide/guide.spec.ts:Q7]
- [x] [Review][Patch] Q1's demo-texts case and the badge spec read Background checks as `.empty` nth(1), relying on README having no approvals (Rule 19: state not created) -- med, fix-risk low (the served snapshot empties approvals) [web/e2e/guide/guide.spec.ts:serve, web/e2e/demo-switch/badge.spec.ts:45]
- [x] [Review][Patch] Rule 2: three inline copies of `support/page.ts`'s `tokenColor` -- med, fix-risk low (the helper is used) [web/e2e/guide/guide.spec.ts:Q1,Q2,Q5]
- [x] [Review][Patch] After a 409 on step 3 the "Next step" tag and bar stayed beside the reason's hint (DESIGN: the marker leaves once pressed) -- low, fix-risk low [web/src/app/feed/break-feed-view.ts:188]
- [x] [Review][Patch] Floor cleanup: `dropBreakFeed` dropped `RemoveMessages`'s status; M4's `finally` ran `settleBatch` with no press; its doc said 30 s -- low, fix-risk low [web/e2e/support/guide.ts:44, web/e2e/floor/guide.spec.ts:M4]
- [x] [Review][Patch] GuidePrompts' docs said the turn's input is exactly the prompt; NewRequest appends the turn's ref -- low, fix-risk low (doc only; compiled on slot B) [src/ocutalon/cls/OcuTalon/Test/Demo/GuidePrompts.cls:1]
- [x] [Review][Patch] M4's no-count check matched `\b50\b` against the line with its elapsed time (a false red at 50 s) -- low, fix-risk low (text nodes only) [web/e2e/floor/guide.spec.ts:M4]
- [x] [Review][Patch] Q1's demo-texts title claimed the old texts return outside demo mode without checking it -- low, fix-risk low (renamed; the badge spec's mode 0 pins them) [web/e2e/guide/guide.spec.ts:Q1]
- [x] [Review][Patch] The step buttons were 30px tall, under DESIGN's 32px target minimum (L732) -- low, fix-risk low (`--space-target-min`; Q1 measures it) [web/src/app/guide/demo-guide.ts:209]

Rejected:
- low: Do step 1 changes nothing visible on the blank guide -- Decided 9 (it selects step 1; focus stays): spec-bound.
- low: the Telegram line shows while steps 2-5 are selected -- AC2 has it follow `telegramRow`, which the server ends at step 1 done; Telegram is off until 0.1.1.
- low: GuidePrompts leaves a reminder if the owner check regresses -- only on a run whose assertion already failed; the fix guards a state the test asserts never happens.
- low: the spec's closing sections are stale after QA -- the fix edits the spec under review.
- low: a late answer after the 10 s timeout overwrites a second press -- needs a POST hung past 10 s while the view stays active; the fix adds a press-id guard.
- low: a run first seen in the same poll as its own `watch.progress` hides its progress -- adjudicated at implement: `guide.state` is published at the press, and this page's press takes the press-time refs.
- false: nine planned mutations unrecorded -- Rule 19 asks one observed-red mutation per AC; AC1-AC9 each carry one, and this review adds eight.
- false: QA's edits are uncommitted -- stages never commit; the lead commits after the smoke gate.
- low: Q1, M1, M2 and M5 rely on README's and FLOOR's starting state -- Decided 14; each asserts that state, so a leftover fails red, never green.
- low: raw px lengths in the new components -- no user-visible harm, the tokens have no 3, 6, 10 or 13px steps, and Epic 2's header and rail do the same.
- low: the collapsed bar takes two lines with an inactive box -- DESIGN's Inactive rule puts the hint beneath the button, and row 14 keeps the box's rules in the bar.
- low: two planned-mutation rows were rewritten without a Spec Change Log line -- the fix edits the spec; the triage log records why.
- low: `elapsedText` has no hour form -- unreachable: the elapsed time shows only under 180 s.
- false: frontmatter `done` against sprint `review` -- `status:` is build-auto's machine state; sprint-status carries the review state.

## Spec Change Log

- 2026-10-26, rework iteration 1 (trigger: CI red on ca4838f, `live:sign-in` Q9 on the Linux host): one `[CI]` item under Tasks & Acceptance.

- 2026-10-26, spec gate (runner): V1 and V2 kept as veto items (U-84, U-85); DW-231 and DW-232 filed; focus reading confirmed against the spine.

## Review Triage Log

### 2026-10-25 -- Review pass
- verdicts: 35 findings -- high 0, medium 2, low 26, false 7, maybe-false 0
- findings:
  - `[low]` `[patch]` blind: `dropBreakFeed` never fails (its CHK line is unconditional) -- `web/e2e/support/guide.ts` now captures the prepare status and the delete's `%SQLCODE` and prints 0 on an error; the guard can fail.
  - `[low]` `[patch]` blind: the guide's prompt wording is copied into the scenario files, `GuidePrompts`, `GUIDE_TEXTS` and two specs with nothing linking them -- `guide-view.test.mjs` now reads both B scenarios and asserts their `match.prompt` equals `GUIDE_TEXTS`.
  - `[low]` `[patch]` blind: `GuidePrompts.Turn` swallows a `LogSince` failure -- the status now reaches `Decide answers the turn`, so the real cause is the failure text.
  - `[low]` `[patch]` blind: `TestReminderPrompt` promises "no reminder is set" and the tool input without checking them -- it now asserts the `set_reminder` input (`stretch|60`) and the Reminder row count before and after.
  - `[low]` `[patch]` blind: the step row can overflow at large text sizes above 1024px -- `.row1` now wraps (`flex-wrap: wrap`); nothing pins it (reopen_if: a floor case that doubles the font tokens at 1280px reads the row's right edge).
  - `[low]` `[reject]` blind: two buttons named "Send" -- the matrix (row 5) and EXPERIENCE name the prompt bar's button "Send" and give it the "Next:" prompt line as context; a distinct name is a spec amendment.
  - `[low]` `[reject]` blind: a reload mid-run drops the run's `watch.progress` refs into the baseline -- Decided 7 states this fallback; a ref only arrives after the guide view that carries the run's `startedAt`, so no real order produces it.
  - `[low]` `[reject]` blind: the 90 s and 3 min lines depend on the browser clock -- Decided 4 chose the page's elapsed time (the AC says "the page's elapsed time"); the server's stage still moves the line forward.
  - `[low]` `[reject]` blind: `BoxView.busy` is unused by the template, and `current` is not clamped -- a field no user reaches; the server sends steps 1 to 5.
  - `[false]` `[reject]` blind: unrelated behaviour bundled (reveal-ring, F8) -- both are listed Tasks of the spec (DW-198, and the F8 mouse position that the guide's empty-chat chip made unstable).
  - `[low]` `[reject]` edge: Do step 1 while the guide is hidden changes a hidden selection -- the AC asks only that it selects step 1; the hint and button sit in the collapsed bar, and Show guide shows the selection. A user must press Hide guide first.
  - `[false]` `[reject]` edge: the chat and rail say "the guide above" when the guide is hidden or absent -- hidden leaves the "Demo guide" bar above; the server sends `guide` whenever demo mode is on.
  - `[false]` `[reject]` edge: `guideOf` has no fallback when demo mode is on but no guide came -- the spec (row 1, "no guide view: no region") says so, and the server always sends `guide` in demo mode.
  - `[low]` `[reject]` edge: browser clock ahead of the server shows the 3 min line at once -- the same as the clock finding above (Decided 4).
  - `[low]` `[reject]` edge: Object.prototype keys as a code, reason or stage -- the values come from the server's fixed vocabularies (Guide.REASONS, STAGES, WatchProgress.STAGES).
  - `[low]` `[reject]` edge: a waiting run with an empty `startedAt` renders empty elapsed spans -- the server writes `startedAt` with every run.
  - `[low]` `[reject]` edge: `heldSent` releases on object identity of a re-delivered equal view -- Decided 5 releases on a view with a different or no `startedAt`; a stale poll after the 200 is the only path and the next view corrects it.
  - `[low]` `[reject]` edge: `heldSent` stays while the view never leaves `sending` -- the view leaves `sending` within a poll; `no_notice` frees the control by 195 s.
  - `[low]` `[reject]` edge: `watchLine` takes the last ref in store order, so an older incident can win -- one run has one incident; baseline refs are the earlier ones.
  - `[low]` `[reject]` edge: this run's `watch.progress` could land in the baseline when it precedes its `guide.state` -- the server publishes `guide.state` at the press, long before a notice.
  - `[low]` `[patch]` edge: `GuidePrompts.OnAfterAllTests` skips the restore when the production is not running -- the `Running` condition is removed; a failed restore now fails the class.
  - `[low]` `[patch]` edge: the module doc says the button "always follows" `active` while a press holds it -- the doc now names the two local holds.
  - `[low]` `[patch]` verification-gap: no recorded mutation line for AC1 to AC9 -- the ten mutations are in `## Verification`, each observed red and reverted.
  - `[medium]` `[patch]` verification-gap: the focus rule's removed-element branch is unpinned (M3's Send persists across 1 to 2) -- floor case M6 (focus on the prompt bar's Send at step 2, advance to step 3; and focus in the composer through 1 to 2); red under the `whenGone` mutation.
  - `[medium]` `[patch]` verification-gap: the box's baseline capture is unpinned (M4's store held no earlier ref) -- M4 now publishes an earlier run's `watch.progress` first, waits for a following event of the same stream, and asserts the sent line survives; red under the baseline mutation.
  - `[low]` `[patch]` verification-gap: G1's two added assertions cannot fail -- removed; the guide-Send assertion before them stays.
  - `[low]` `[patch]` verification-gap: Q6 checks absence before the system is ready -- a settle after the busy press, and a positive signal (the 500 was served) before its absences.
  - `[low]` `[patch]` verification-gap: cases rely on state they did not create -- Q3 and Q5 serve an empty chat; M4's fixed 4 s wait is `settleBatch` (the batch stops growing). Q1's blank guide and the floor's empty FLOOR session are the spec's own design (Decided 14).
  - `[low]` `[patch]` verification-gap: the AC9 planned mutation cannot go red on a real mode-0 stack -- the row now names the chat's demo flag, which the badge spec catches.
  - `[low]` `[patch]` verification-gap: the AC8 planned mutation would not go red in M4 -- the row now names the baseline mutation, which M4 catches.
  - `[low]` `[reject]` verification-gap: components have no unit host -- the project hosts components in Playwright only; Q and M cases cover them.
  - `[false]` `[reject]` intent: tests exercise pure functions and faked snapshots more than the real server -- the spec places the real server at M3, M4 and Q1 by design.
  - `[false]` `[reject]` intent: row 17's test sends a Decide request, not a page send -- the spec's `GuidePrompts` task names `RunnerFixture.NewRequest/Run`.
  - `[false]` `[reject]` intent: the box's activity "always follows" `active` against row 10's local hold -- row 10 states the hold.
  - `[false]` `[reject]` intent: the baseline is taken at the run's first sight, not at the `waiting` stage -- equivalent: no notice precedes `waiting`.

## Design Notes

**Lead rulings at the spec gate (runner, 2026-10-26; policy 9e90866):**
- **V1 (veto, kept; inbox U-84):** the guide-owned `feed/break-feed-api.ts` beside `ApiClient`, as recommended. The unification is ledgered as DW-231, routed to Story 10.3 (Epic 10 edits `web/src/app/api/**`).
- **V2 (veto, kept; inbox U-85):** the "done" and "upcoming" step names.
- **Focus on auto-advance (decide):** the spine's Announcements-and-focus row names Story 4.4 among the stories that follow `shared/focus-rule.ts` (focus moves only when an update removed the focused element); the plan's reading stands.
- **Story 8.4 collision:** ledgered as DW-232, routed to `8-4-set-list-and-cancel-reminders-in-plain-words` (extend `guide-reminder.json`); the orchestrator plans its bullet. Story 5.1 is done without a scenario keyed by P1, so nothing is routed there.
- **DW-198:** the code fix is this story's; the "green over several Linux runs" part is confirmed from CI history at the burn-down gate (the floor runs on every later push), so adjudication re-owns only that residual if it is still open.


**Architecture decisions** (spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`):
- **AD-12** (L330-343): the guide and Break the feed come only from `Guide.Compute` (`/state`'s `guide` and `guide.state`). The page decides nothing (Prevents: "the page deciding guide progress or Break the feed availability itself"). It reads the snapshot, then the events.
- **AD-13** (L367, L370): the press and the sends carry the browser envelope, through the existing interceptor. Untrusted text renders as text only; nothing calls `bypassSecurityTrust*`.
- **AD-4** (L177): the body names no session.
- **AD-14** (L396): a guide send is the user's own text, with provenance `user`.
- **AD-30** (L814): `FromGuide` is display-only.
- **AD-15** (L410): before the notice only `watch.progress` (`noticed`, `settling`, `diagnosing`) exists, and the box shows exactly those.
- **AD-22** (L589-602): guide-prompt scenarios live under `scenarios/B/` and are matched by exact text contained in the user message. There is no default reply.
- **AD-29** (L776-777): Lane B's `web/`; REL-2's demo-path parts stay Story 4.7's.
- **AD-33**: the page publishes nothing; one publisher per type is unchanged.
- **Conventions:**
  - L913 "Announcements and focus" names Story 4.4 as following `focus-rule.ts`;
  - L926 "one typed API client and one live-event service" (V1);
  - L904 display names live in the web app;
  - L929 and L952: icons are vendored Lucide paths (ISC).

**Decided in-stage:**
1. **Focus on advance.** The AC's "focus moves to the prompt bar's action button" is read through UX-DR131 (the AC cites it): "When an update removes the focused element…". The same reading appears in EXPERIENCE L410-415 (focus replacement) and the spine's L913, which names Story 4.4. So focus moves only when the advance replaced the focused element, and focus in the composer or on a step stays. This is not an intent gap: the AC's own citation selects the reading.
2. **Steps 3-5's prompt bar is empty in this story.** Their texts and buttons are Story 4.7's ACs (epics L2406-2420), and moving them here would be a veto item (moving an AC). Steps 1-2, the Telegram row and the frame are this story's. `whenGone` falls back to the prompt bar itself (EXPERIENCE L410: "or to the nearest container").
3. **Placement.** The guide goes in `app.ts` between `.banner-slot` and `router-outlet` (release 1 has one route). Inside `main-page.ts` it would break `place()` and floor G4/G5's `section.rail + main.main` adjacency. Without a heading, F1's and B's h2 lists hold, and `main > *` stays 2.
4. **The 90 s and 3 min lines are timed by the page, and the button by the server.**
   - The server's stage moves on `StatusMonitor`'s 15 s tick, so on its own it could show "Still waiting" as late as 105 s; the AC says "from 90 seconds". So each line shows from the page's elapsed time (`startedAt` plus 90 s or 180 s), or from the server's `still_waiting` or `no_notice`, whichever comes first.
   - The button's activity follows only the server's `active`, because `no_notice` frees the control (AD-12). This is EXPERIENCE L606's "The button follows the server's state".
   - The server's `notice_arrived` ends the lines.
   - The elapsed time is clamped at 0.
5. **The press's local state.** It covers the gap between the answer and the poll, so the box never flashes active.
   - The 200's `startedAt` holds until a guide view shows that `startedAt` past `sending`, or a different `startedAt`. A poll that still carries the run's `sending` view cannot undo the sent line.
   - A 409's code holds until the next guide view. A 500 or a network error adds no text (none is specified, and "Nothing was changed" would be false after a partner failure). The guide view then shows the truth: `sending` until `no_notice` frees it.
6. **Precedence in the box.** The stage line replaces the hint while the stage is `sending`, `waiting` or `still_waiting`. For `no_notice`, the line shows, plus the hint if the box is inactive. For `""` and `notice_arrived`, the hint shows if the box is inactive. The "Next step" tag shows when step 3 is current, the box is active and no run is in flight, so it returns after `no_notice`.
7. **The `watch.progress` baseline.** The payload has no time. Refs already in the store when this run's stage first appears are an earlier run's and are ignored. A reload mid-run starts empty, so it falls back to the sent line.
8. **"Sent" is announced once per `startedAt`**, from the 200 or from a live view, never from the first snapshot.
9. **Do step 1** is a `<button>` styled as a text link. Under hash routing, an `<a href="#">` would navigate. It selects step 1 and leaves focus where it is (the AC asks only "selects step 1").
10. **Hide guide** carries no `aria-expanded`; the AC and EXPERIENCE L230 give it to Show guide only.
11. **No `aria-pressed` on steps.** UX L428 gives guide steps `aria-current` only. The selected step's visible cue is the 2px bar, and the prompt bar names the selection.
12. **A double Send** while the first is `sending` sends nothing: one click is one prompt and one allowance use.
13. **Mock texts are CI-only, not public.** `guide-watch` has no tool call, because Chat offers no watch tool until Epic 5. `guide-reminder` copies `reminder-set-relative`. `Test.Tools.Reminders`' P2 turn carries a marker, which wins, so it is unaffected; no other test or eval sends either prompt (grepped).
14. **Tests and users.** `fixtureUser` kinds are fixed by the contended `test-sign-in.sh`. So the chromium spec uses README with routed snapshots and stubs and writes nothing to the server, and the real-data cases (M3, M4) use FLOOR, whose specs seed and clean by design. Floor ids M (floor) and Q (chromium) are unused letters.
15. **DW-198's fix applies in every engine.** The module has no engine switch, and one more pixel is harmless in Chromium and Firefox. It covers both explanations (inference): a sub-pixel `below` that WebKit's whole-pixel `scrollTop` rounds away, or a scroller edge 0.78 px past the viewport.
16. **The compact query.** The page's only height query lives beside `LAYOUT_QUERIES` as its own constant, and `floor-sources` learns that it is not a width band (the floor rule "heights are minimums" holds).

**Veto-window items (with the recommendation):**
- **V1 (amending a convention, L926 "one typed API client").** `web/src/app/api/**` is contended (Epic 10), so the break-feed POST lives in `web/src/app/feed/break-feed-api.ts`: a second typed caller of the API, through the same interceptor and envelope.
  - **Recommendation: keep.** It is the orchestrator's stated route.
  - **Reversal:** move `press()` into `ApiClient` as `breakFeed()`, with its answer type in `api-types.ts` (about 10 lines), when Epic 10 frees `api/`, or now on a lead ruling that permits that one method. The lead routes this to the Epic 10 story that next edits `api-client.ts`.
- **V2 (public text: step state names).** EXPERIENCE L225 gives only "Step 3, Break the feed, current", but the AC needs every step's name to include its state. "Step {n}, {label}, done" and "Step {n}, {label}, upcoming" use DESIGN L765's own state words ("a check for done … current … upcoming").
  - **Recommendation: keep**, registered in `ux-strings` as `ruled` with the spec gate's ruling.
  - **Reversal:** other state words, as the owner prefers.

**Rule 2 (extend, don't copy):**
- `elapsedText` extends `page-time.ts` beside `countdownText`, sharing its `fill` and plural helpers.
- The box extends `ServerButton` with an inactive input instead of copying its busy logic.
- Hide/Show uses `stored-flag`, and focus uses `keepFocus`.
- The sends use `ChatOutbox.send`.
- The views follow the `rail-view` and `chat-view` pattern.
- `GuidePrompts` rewrites `Test.Tools.Reminders`' eight-line `Turn` around the public `RunnerFixture` and `Test.Contract.Mock` helpers, because that one is private in a contended class.
- The B scenario copies `reminder-set-relative`'s replies. A scenario has no include mechanism, and A is Lane A's.

**Integration ACs (Rule 1):**
- The page (`app-demo-guide` and the box) reads the real `guide.state` and `/state` `guide`, and the real break-feed route (M3, M4 on the floor stack; Q1 the real blank guide).
- The real demo switch hides and shows it (demo-switch badge spec).
- The Chat agent's real turn of P1 or P2 reads the B scenarios through the mock (`GuidePrompts`).

**Consumes:**
- Story 4.2: `guide.state`, `/state` `guide`, `Guide.Compute`'s stages and reasons.
- Story 4.3: `POST /v1/demo/break-feed`, its 200 and 409.
- Epic 2: `LiveState`, `ChatOutbox`, `Announcer`, `focus-rule`, `ServerButton`, `stored-flag`, `page-time`, `revealRing`, the tokens.
- Story 0.11's mock loader.

**Consumed-by:**
- Story 4.5: the device column aligns under the box (`--space-device-width`), and the still-waiting line names its Simulated phone tab.
- Story 4.7: fills steps 3-5's prompt entries and buttons. Its "Go to Break the feed" focuses the box's button. It adds the finish state, Run again and the attention style at the finish, and turns on 01, 02, 03 and 06's parts with these scenarios.
- Story 8.4 (epics L3074): uses `guide-reminder.json`.
- Story 5.1: gives `guide-watch.json` its watch tool call.
- Epic 10: takes V1's method into `ApiClient`.

**Ledger:**
- **DW-198** is addressed by the `reveal-ring.ts` task, matrix row 16 and the DW-198 AC.
  - The local `live floor` run is the implement stage's evidence.
  - "Green over several Linux runs" can only come from CI. The lead's adjudication cites `floor-webkit` G1 passing on at least three Linux CI runs of this epic's pushed heads, starting with this story's.

**For the lead:**
- **Story 8.4 collision.** Story 8.4's AC (epics L3074) asks for a B scenario keyed by P2 too. The loader refuses a repeated prompt (`scenarios.mjs:255`), so 8.4 should extend `guide-reminder.json`, not add another. This touches another epic's not-yet-planned story, so it is the orchestrator's routing. Likewise Story 5.1 should add `start_watch` to `guide-watch.json` once Chat offers it.
- **Mockup differences.** `main-page.html` L362 and `states.html` L783 word H2 differently, and `states.html` keeps the "Next step" chip after a press. EXPERIENCE and the AC win; recorded here only.
- **Allowance gating.** UX-DR45's prompt-button gating at the allowance limit has no Story 4.4 AC. It is not built here: the composer is never disabled either, and the server answers at the limit.
- **Footprint.** Outside Epic 4's listed footprint, all Lane B home areas and none contended:
  - `web/src/app/{app.ts, chat/*, rail/*, shared/*, icon/icon.ts}`;
  - `web/scripts/*.test.mjs`;
  - `web/e2e/{chat,rail,frame,floor}/*.spec.ts`;
  - the new `web/e2e/guide/`.

  In Epic 4's footprint: `web/src/app/{guide,feed}/**`, `web/e2e/demo-path/01-page.spec.ts`, `web/e2e/demo-switch/badge.spec.ts`, `ci/mock/scenarios/B/**`, `Test/Demo/GuidePrompts.cls`.

## Verification

`<B>` means: `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=4 stage=implement'`.
- The fresh tag is `e4s4i`; tear it down with `ci/iris.sh teardown`.
- One command per foreground call (`timeout: 600000`).
- The live units and `GuidePrompts` (which changes the runners' keys) run only on fresh throwaways. Slot B is for loading and compiling `GuidePrompts` only.

**Commands:**

`(loop)`:
- `npm --prefix web test` -- expected: every node test passes, the new and edited view, source and string tests included.
- `npm --prefix web run lint` -- expected: exit 0.
- `bash docker/tests/test-mock.sh` -- expected: the mock's tests pass with the two B files loaded (no problem, no repeated prompt).
- `<B> OCUTALON_RUN_TAG=e4s4i ci/iris.sh class OcuTalon.Test.Demo.GuidePrompts` -- expected: `CLASS ... passed`, no skip.
- `<B> OCUTALON_RUN_TAG=e4s4i ci/iris.sh live sign-in` -- expected: PASS (chromium: Q1-Q8, C1, R1, F1, F2).
- `<B> OCUTALON_RUN_TAG=e4s4i ci/iris.sh live floor` -- expected: PASS in all three projects (M1-M5, G1, K4, A7, W2).

`(once)`:
- `bash docker/tests/test-web-build.sh` -- expected: the build passes (generator checks, budgets under the error level).
- `<B> OCUTALON_RUN_TAG=e4s4i ci/iris.sh live demo-path` -- expected: PASS (01-page's demo texts).
- `<B> OCUTALON_RUN_TAG=e4s4i ci/iris.sh live demo-switch` -- expected: all PASS (the badge spec's guide test in modes 0 and 1).
- `<B> OCUTALON_RUN_TAG=e4s4i ci/iris.sh shard lane-b` -- expected: every class passed.
- `<B> OCUTALON_RUN_TAG=e4s4i ci/iris.sh shard lane-a` -- expected: every class passed.
- `bash ci/checks.sh` -- expected: exit 0.

**Not a command of this stage (DW-198's Linux evidence, for the lead):** `floor-webkit` G1 passes on at least three Linux CI runs of this epic's pushed heads. Record the run ids at the ledger adjudication.

**Planned mutations (Rule 19).** Apply each, observe red, revert, confirm `git status --short` and `git diff --stat` are unchanged, and record it as `mutation: … -> …`.

| AC | Mutation | Expected red |
| --- | --- | --- |
| 1 | `guideOf` ignores `demoMode` | `guide-view.test`, F2 (region count 0) |
| 1 | a done step gets the current marker | `guide-view.test`; Q2 |
| 1 | the demo line not used in demo mode | `chat-view.test`; C1 |
| 2 | the page marks the clicked step done | Q2 ("not done by a click") |
| 2 | `advance` also announces on the first view | `guide-view.test`; M3 (announced once) |
| 2 | focus moved to the action on every advance | M3 (the composer keeps focus) |
| 3 | `send(text)` without `true` | Q3 (`fromGuide: true`) |
| 3 | P2's text differs by one character | Q3 and `GuidePrompts` (`selectedBy` mock key or 500) |
| 4 | the inactive button gets `disabled` | M2 (focusable, `aria-disabled`) |
| 4 | the tag ignores the in-flight run | `break-feed-view.test` |
| 5 | an old ref's `watch.progress` shown | `break-feed-view.test`; M4 |
| 5 | "Sent" announced on every view | Q6 and M4 (once) |
| 5 | the 90 s line only from the server's stage | `break-feed-view.test`; Q7 (90 s by the page clock) |
| 5 | the button made active by the page's 180 s | `break-feed-view.test`; Q7 (inactive until the server says `active`) |
| 6 | the hidden flag not stored | Q8 (after reload) |
| 6 | the compact row dropped | M5 (one row at 1280x600) |
| 7 | `MARGIN` 0 and no rounding | `reveal-ring.test` (fractional case) |
| 8 | the box ignores the `watch.progress` baseline (an earlier run's ref shows its line) | M4 (the sent line must survive an earlier run's ref) |
| 9 | the chat's demo line shown whatever `demoMode` says | the demo-switch badge spec in mode 0 (the line must be `emptyAsk`) |

**Recorded mutations (Rule 19).** Each was applied to the tree, observed red, and reverted; `git diff | md5` and `git status --short` were identical before and after every one. The browser units were rebuilt with `ci/iris.sh build` before each run (a `live` call alone does not rebuild the web bundle).
- AC1: mutation: `guideOf` ignores `demoMode` -> `guide-view.test` "is undefined outside demo mode, even for a snapshot that still carries a guide and a store that holds one" red.
- AC2: mutation: `advance` also announces for the first view -> `guide-view.test` "is silent for the first view, a view of the same step, a lower step and another run" red.
- AC2: mutation: `whenGone` returns null for the prompt bar's keys (the removed Send hands focus to the main region) -> `live floor` M6 red, 79 other cases passed.
- AC3: mutation: `guide-reminder.json` keys P2 with one character changed -> `guide-view.test` "key the exact text of the guide's step 1 and step 2 prompts" red.
- AC4: mutation: the "Next step" tag ignores the in-flight press -> `break-feed-view.test` "is busy with \"Sending 50 orders...\" while the press has no answer, and the tag is gone" red.
- AC5: mutation: the 90 s line shows only from the server's `still_waiting` -> `break-feed-view.test` "shows the 90 s line from the page's clock at 90 s, and the sent line at 89 s, while the server still says waiting" (and two more) red.
- AC6: mutation: the compact media block of `demo-guide.ts` never applies -> `live floor` M5 red.
- AC7: mutation: `MARGIN` 0 and no `Math.ceil` -> `reveal-ring.test` "scrolls down by the overflow and the gutter when the control passes the bottom" (and five more) red.
- AC8: mutation: both baseline captures of `break-feed-box.ts` use an empty ref set -> `live floor` M4 red (an earlier run's `watch.progress` line replaced the sent line).
- AC9: mutation: the chat's `demo` is always true -> `live demo-switch` badge spec red in mode 0 ("Start with step 1 of the demo guide above." where `emptyAsk` belongs).

**QA stage additions (Rule 19; all (QA)).** `web/e2e/guide/guide.spec.ts` gains Q9 and four strengthened cases; each mutation was applied, observed red in `live sign-in` after `ci/iris.sh build`, reverted from a backup, and `git diff | md5` and `git status --short` matched the pre-mutation values.
- (QA) `web/e2e/guide/guide.spec.ts` Q9 (new): the step row wraps at a larger text size (the text tokens scaled between "the steps alone fit" and "everything fits") and nothing runs past the row.
- (QA) Q1 now counts the four chevrons and asks each for `aria-hidden`; Q5 and Q6 assert the box has its 1px divider (no 4px action bar) while inactive, active without the tag, on step 5, and once pressed; Q2 asserts that selecting steps announces nothing; Q8 asserts that the two `\u00B7` separators of the collapsed bar are `aria-hidden`.
- AC6: mutation (QA): `flex-wrap: wrap` removed from `.row1` of `demo-guide.ts` -> `live sign-in` Q9 red ("the row wraps onto a second line": 1 line, expected more than 1).
- AC4: mutation (QA): the box's base `border-inline-start` made the 4px action bar -> `live sign-in` Q5 and Q6 red ("no 4px bar while inactive": 4px, expected 1px).
- AC1: mutation (QA): the chevron span loses `aria-hidden="true"` -> `live sign-in` Q1 red ("each is aria-hidden").
- AC2: mutation (QA): `select()` also announces -> `live sign-in` Q2 red ("selecting a step announces nothing") and Q3 red.

**Code review additions (Rule 19; all (CR)).** Run A carried the three box mutations together with the code from before the review's fixes, and run C carried one mutation over the fixed tree. Each run was rebuilt with `ci/iris.sh build`, red only where named, and reverted from a backup; the box's md5 and `git diff | md5` matched the pre-mutation values. Node mutations were observed with `npm --prefix web test`.
- AC5: mutation (CR): `follow()` no longer marks the first view's run as announced -> `live sign-in` Q10 "a page loaded during a run announces nothing for that run's later views" red ("Sent" announced).
- AC5: mutation (CR): `follow()`'s "Sent" announcement removed -> `live sign-in` Q10 "a run first seen through a live view is announced once" red (expected 1, received 0).
- AC8: mutation (CR): `follow()`'s baseline is an empty set -> `live sign-in` Q10 "an earlier run's watch.progress never shows ..." red (the earlier run's diagnosing line).
- AC5: mutation (CR): the box's 10 s timer removed -> `live sign-in` Q6 "a press with no answer in 10 s ..." red (the sending line stayed).
- AC2: mutation (CR): Do step 1 without its focus key (the code before the fix) -> `live sign-in` Q10 "when an update removes the focused Do step 1 ..." red (focus not on Break the feed).
- AC6: mutation (CR): `.steps` without wrap and `flex: none` (the code before the fix) -> `live sign-in` Q9 red at twice the text (41.6px past the row).
- AC1: mutation (CR): the steps' 30px minimum height (the code before the fix) -> `live sign-in` Q1 red (30, expected at least 32).
- AC5: mutation (CR): the view's stage read under a sent press over another run's view (before the fix) -> `break-feed-view.test` "shows the sent line for a press from an earlier run's no_notice view ..." red.
- AC4: mutation (CR): the tag ignores a held 409 (before the fix) -> `break-feed-view.test` "drops the Next step tag while a 409 holds ..." red.

**Shared surfaces:**
- the page's region order and tab order (F1, G1, G4, G5, K1, K4);
- the empty chat and Background checks texts (C1, R1, 01-page, the unit pins);
- the speakers, focus-call and `keepFocus` lists (`announce-focus-sources`);
- the width and height query list and its tests (`floor-sources`, `layout-view`);
- the `ux-strings` inventory;
- the floor `@browsers` id list (`playwright-projects`);
- A7's places and W2's selectors;
- `revealRing`'s amounts (rail and chat list; K4, E2, G1);
- the mock's scenario set (Story 8.4's planned P2 scenario);
- the runners' Config Store keys during `GuidePrompts` (restored);
- the FLOOR session on the floor stack, which gains, then loses, an Orders check, a reminder, a run and a batch of 50 orders in OCUORDERS (M4 removes them).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The page shows the demo guide and the Break the feed box in demo mode. `app-demo-guide` (steps, prompt bar, Hide and Show, compact row, numbers band, stacked order) sits between the banners and the rail; `app-break-feed-box` reads the guide view, the page's own press (V1's guide-owned `BreakFeedApi`) and `watch.progress`. The empty chat and Background checks have their demo lines. DW-198's fix (1 px margin, whole pixels) is in `reveal-ring.ts`. Two CI mock scenarios answer P1 and P2, and `Test.Demo.GuidePrompts` runs them through Decide.

**Files changed.**
- `web/src/app/guide/{guide-view,demo-guide}.ts`, `web/src/app/feed/{break-feed-view,break-feed-api,break-feed-box}.ts` -- new: view models, the guide, the box and the press call.
- `web/src/app/{app,chat/chat-panel,chat/chat-view,chat/empty-chat,chat/page-time,icon/icon,rail/rail-view,rail/status-rail,shared/layout-view,shared/reveal-ring,shared/server-button}.ts` -- the guide slot, the demo lines, `elapsedText`, `chevron-right`, the height query, the ring margin and the inactive input.
- `ci/mock/scenarios/B/guide-{watch,reminder}.json` and `src/ocutalon/cls/OcuTalon/Test/Demo/GuidePrompts.cls` -- the scenarios and their test.
- `web/scripts/*.test.mjs` (two new, ten edited), `web/e2e/guide/guide.spec.ts`, `web/e2e/floor/guide.spec.ts` (M1 to M6), `web/e2e/support/guide.ts`, and the edited chat, rail, frame, banners, demo-path, demo-switch and floor specs.

**Review.** 35 findings: 0 high, 2 medium, 26 low, 7 false. Patched: 15 rows (the unpinned focus branch and baseline capture, the vacuous and premature assertions, the dropBreakFeed and GuidePrompts gaps, the prompt-link test, the step row's wrap, the module doc, the two planned-mutation rows, the ten mutation lines). Deferred: none. Rejected: 20 rows (13 low, 7 false) with their reasons in the log above.

**Follow-up review recommended: true.** Two medium findings were patched (patched counts: medium 2, low 13). The unverified risk: the `.row1` wrap (`flex-wrap: wrap`) has no test of its own, and the new floor cases M6 and M4's extension were written after the review layers read the diff.

**Verification.** `npm --prefix web test` 622 pass; `npm --prefix web run lint` exit 0; `bash docker/tests/test-mock.sh` 94 pass; `GuidePrompts` passed (no skip); `live sign-in` 203 passed, 1 skipped (not a guide case); `live floor` 80 passed in Chromium, Firefox and WebKit (M1 to M6, G1, K4, A7, W2); `live demo-path` all checks passed (floor 4 of 4); `live demo-switch` all checks passed; `shard lane-b` 54 classes passed; `shard lane-a` 47 classes passed; `bash docker/tests/test-web-build.sh` and `bash ci/checks.sh` passed (after the non-ASCII literals of ten source lines became `\u2026` and `\u00B7`, which `boundaries` flagged). The web bundle was rebuilt with `ci/iris.sh build` before the final floor and sign-in runs.

**Residual risks.**
- DW-198's "green over several Linux CI runs" can only come from CI (`floor-webkit` G1).
- The initial bundle was over its 500 kB warning before this story (540 kB) and is 561 kB now; no budget error.
- In the collapsed bar with an inactive box the hint wraps under the button, so the bar is about 70 px tall; M5 holds it under 110 px.
- Departures from the spec text, all small: M4 publishes `watch.progress` through `Live.Publish` (`BridgeSink` ignores that type); Hide and Show store `1` and `0`; `boxView` takes the elapsed formatter as a parameter (view modules import no values); the existing chat and banners specs scope their Send locator to `main`, and frame F8 moves the mouse to a point with no tooltip.
- Edits outside Epic 4's listed footprint, all Lane B home areas and none contended: `web/src/app/{app.ts,chat/*,rail/*,shared/*,icon/icon.ts}`, `web/scripts/*.test.mjs`, `web/e2e/{chat,rail,frame,floor,banners}/*.spec.ts`, the new `web/e2e/guide/` and `web/e2e/support/guide.ts`.
