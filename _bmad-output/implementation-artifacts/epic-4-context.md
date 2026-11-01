# Epic 4 Context: The demo page: guide, simulated phone and mailbox, and Break the feed

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Demo mode turns the signed-in page into the self-guided two-minute demo: a demo guide with one-click prompts, a labelled simulated phone and simulated mailbox that are real production channels, and a Break the feed control that makes the simulated partner send the session's 50 orders in a changed date format that fail for real. The server derives guide progress and Break the feed availability from what really happened, so nothing is claimed or canned. Stories 4.1 to 4.7 built all of this. Epic 4 is re-opened for three owner-requested refinements to the page, none of them launch-blocking: step 3 loses its redundant button, a client-only "Demo view" switch shows the page as it looks on a real install, and "Try it yourself" chips let a judge try abilities the guide doesn't show. Lane B.

## Stories

- Story 4.1: Switch demo mode from the terminal (done)
- Story 4.2: Derive the guide state and Break the feed availability on the server (done)
- Story 4.3: Break the feed with a real batch of 50 orders (done)
- Story 4.4: Show the demo guide and the Break the feed box (done)
- Story 4.5: Get notifications on the simulated phone (done)
- Story 4.6: Simulate incoming email in the simulated mailbox (done)
- Story 4.7: Finish the demo guide (done)
- Story 4.8: Step 3 of the guide points to Break the feed without a second button
- Story 4.9: A Demo view switch shows the page as it looks on your own install
- Story 4.10: "Try it yourself" example prompts, one press each

## Requirements & Constraints

- **All three stories are web-only.** Nothing changes on the server: no new route, no `/state` key, no payload, no table.
  - 4.8 touches only `web/src/app/guide/*`, its tests and the two UX files.
  - 4.9 touches only `web/src/app/**`, the web unit and e2e tests and the UX files. It does not touch `api/api-types.ts` or `live/live-store.ts` (Epic 11 is changing them) or `rail/telegram-card/**` (Epic 12).
  - 4.10 stays within 4.9's footprint, plus new mock scenario files. Don't edit the existing `guide-*.json` scenarios.
  - CI is green on every workflow at each merge.
- **Step 3 (4.8).** The Next bar shows only the instruction line ("Press Break the feed. The partner will send 50 orders in a new date format."; while waiting, "Waiting for OcuTalon. The reminder may arrive first.") and no action button. **Go to Break the feed** goes completely: its `goToBreakFeed` prompt action, its text and its handler. The box's "Next step" tag and teal left bar stay as they are; they now point the visitor to the red button.
- **Demo view (4.9).**
  - **The switch:** a top-bar switch labelled "Demo view", on by default, shown only when the server's `demoMode` is true.
  - **Off:** the guide, the Demo control and the Simulated devices region are gone, and the page lays out exactly as with demo mode off on the server. The chat takes the devices' width, the skip links drop the demo targets, and the empty-chat and empty-checks lines are the non-demo ones.
  - **Honest markers stay:** the "Online demo" pill, the reset countdown and the allowance lines on the online demo, and the "Demo mode" pill on a local demo install. The Telegram card follows the server's real state as now.
  - **Client-only:** a change makes no server request and changes nothing else: demo mode, the session, guide markers, allowance, watches, reminders and incidents all stay. The incident flow and the Orders production keep running underneath.
  - **Approvals:** a pending approval is never hidden. While the switch is off it is answerable in the chat; an answer given while off shows as answered on the phone when the switch is back on.
  - **Turning it back on** restores the guide at the step the session's state gives, with its Hide guide choice as it was.
  - **Known limit:** server-built text (for example a catalog line mentioning the simulated phone) may still name the phone while the switch is off. That is accepted. A client-side string of that kind may follow the signal, within the footprint.
- **Try it yourself (4.10).**
  - **Where:** only in the demo view: after the "More to try" line in the finish state, and after the last line of the empty chat.
  - **The chips, in order:** "Which productions are running?" (`list_productions`), "Is anything wrong right now?" (`check_status`; its answer stays code-built), "What was that failure earlier?" (5.13's `recent_activity`, now merged, so it ships with the others) and "What can you do?". The final wording comes from the UX spec, and the chips don't repeat the guide's watch and reminder prompts.
  - **A press** sends the text once as an ordinary chat turn: no "From the demo guide" tag, the same decision strip, reply and trace link as any turn, and it counts against the allowance. Nothing is sent without a press.
  - **Disabled** while a turn is in flight or the allowance is used up; the existing allowance line says why. The chips are native buttons named by their text.

## Technical Decisions

- **Guide state stays server-derived.** `Demo.Guide.Compute` is the single source of each step's state, the Break the feed state and the finish; the page never decides progress. The page reads `/state`'s `guide` and the `guide.state` events through the guide-owned `GuideSnapshot` type. The "trace opened" and "run again" markers are the only REST writes the guide makes.
- **One demo view signal (4.9).** One client-side signal is true only when the server's `demoMode` is true and the switch is on. Every component that reads demo mode today uses it, and nothing else reads `demoMode` directly: the guide, Demo control, chat panel and empty chat, phone, mailbox, device panel, rail, skip links and main page. Off renders through the same path as a server with demo mode off. A source test enforces this.
- **Persistence (4.9).** The switch is kept per browser tab in `sessionStorage`, read and written inside try/catch, falling back to on. The guide's Hide guide choice and the selected device tab stay per browser, as before.
- **Chips use the normal chat path (4.10).** They submit exactly as typed text does, never with `fromGuide`. They show only when the demo view signal is true.
- **The all-clear rule.** An all-clear comes only from code. `check_status` and `recent_activity` are trusted-output tools whose answers are built by code from the session's own rows. When a session has no incident yet, `recent_activity` gives a code-built "nothing yet" answer, never an all-clear.
- **CI mock scenarios.**
  - Each chip's exact text needs a scenario in a new file under `ci/mock/scenarios/B/`; the loader refuses a repeated prompt. The guide's scenarios (`guide-watch.json`, `guide-reminder.json`) match on `"prompt"`.
  - Story 5.13's `ci/mock/scenarios/A/recent-activity.json` matches only the marker `recent-activity`, not a prompt, so a chip that sends its text verbatim doesn't hit it. Its reply also ends with an all-clear that the guard removes.
  - No new evaluation cases.
- **Focus and announcements.** The page speaks only through `Announcer`. Focus moves only on the user's own action, or through `shared/focus-rule.ts` when an update removes the focused element.
- **Pinned surfaces.** A new e2e folder updates `playwright-projects.test.mjs`. Floor specs live in `web/e2e/floor/` (`live:floor` only), and floor rules apply: no `transition`, fixed heights, `sticky` or `IntersectionObserver`, and width queries only through `LAYOUT_QUERIES`.

## UX & Interaction Patterns

- **Step 3 focus (4.8).** When step 3 becomes current by the user's own press (Send on step 2, or **Run again** from the finish state), focus moves to the box's **Break the feed** button and nothing is pressed. It never moves when step 3 becomes current any other way. The guide's other focus rules are unchanged: the next step's action button or the `tabindex="-1"` prompt text, the "Step {n} of 5: {step}" announcement, and the finish state's first line.
- **The switch (4.9).** A native switch (`role="switch"`, `aria-checked`), reachable by keyboard, with help text along the lines of "Off shows the page as it looks on your own install." (the UX spec fixes the exact text). Its state is announced when it changes, and focus stays on it.
- **Exact text.** Public text follows the UX spec verbatim, with straight ASCII quotes. Style only with DESIGN.md tokens.
- **UX documents to update.** Each change carries a marker citing the owner's request of 2026-11-01.
  - **4.8:** EXPERIENCE.md's demo guide table row 3 and Flow 1 step 5 ("Dana presses Go to Break the feed, then Break the feed"), and the mockup's C2 state (`states.html`: the Next bar's button and the C2 caption). The spec still shows the button today.
  - **4.9:** EXPERIENCE.md's "Demo guide and controls" and "Demo Mode and the Online Demo", and DESIGN.md's top bar (the Frame's app header: logo, wordmark, context badge, then right-aligned the countdown, Visual Trace, theme and account menus).
  - **4.10:** EXPERIENCE.md's "Demo guide and controls" (the finish state and the empty chat).

## Cross-Story Dependencies

- **4.8, then 4.9, then 4.10** run in that order on the same runner. 4.9 edits the same guide files as 4.8, and 4.10 relies on 4.9's demo view signal.
- **4.8's tests to update:**
  - the floor cases M7, M10 and M12 and the step 2 to step 3 case in `web/e2e/floor/guide.spec.ts`;
  - `web/e2e/guide/guide.spec.ts` and `01-page.spec.ts`'s step 3 row;
  - `guide-view.test.mjs`, `announce-focus-sources.test.mjs`, and `ux-strings.test.mjs`'s guide string list.
- **4.9's e2e cases:**
  - Off: the guide, the Demo control and the devices are gone, and the chat still sends and answers.
  - Back on: they return with the guide step preserved.
  - A pending approval survives off and on.
  - The off page's regions, landmarks, skip links and rail sections equal a demo-mode-off page's, compared as structure, never as pixels.
- **4.10's e2e cases:**
  - One per chip on the CI mock: press it and see the turn, a reply and its trace link.
  - One that presses the third chip with no incident yet and gets `recent_activity`'s code-built "nothing yet" answer, with no all-clear.
- **Built pieces these stories reuse:** 4.7's finish state and "More to try" line, 4.4's empty-chat demo line and box, the allowance banner, and the Telegram card (Epic 12 owns it).
