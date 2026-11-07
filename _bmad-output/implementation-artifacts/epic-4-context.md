# Epic 4 Context: The demo page: guide, simulated phone and mailbox, and Break the feed

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Demo mode turns the signed-in page into the self-guided two-minute demo. It has a demo guide with one-click prompts and a labelled simulated phone and simulated mailbox, which are real production channels. Its Break the feed control makes the simulated partner send the session's 50 orders in a changed date format, and they fail for real. The server derives guide progress and Break the feed availability from what really happened, so nothing is claimed or canned. Stories 4.1 to 4.10 built all of this, including the step 3 cleanup, the client-only Demo view switch and the "Try it yourself" chips. Epic 4 is re-opened for Story 4.11, an "Other things to try" panel. It lets a judge see more of what OcuTalon does, each item with one button that uses an action the demo already has. Target: the Saturday release; not launch-blocking. Lane B.

## Stories

- Story 4.1: Switch demo mode from the terminal (done)
- Story 4.2: Derive the guide state and Break the feed availability on the server (done)
- Story 4.3: Break the feed with a real batch of 50 orders (done)
- Story 4.4: Show the demo guide and the Break the feed box (done)
- Story 4.5: Get notifications on the simulated phone (done)
- Story 4.6: Simulate incoming email in the simulated mailbox (done)
- Story 4.7: Finish the demo guide (done)
- Story 4.8: Step 3 of the guide points to Break the feed without a second button (done)
- Story 4.9: A Demo view switch shows the page as it looks on your own install (done)
- Story 4.10: "Try it yourself" example prompts, one press each (done)
- Story 4.11: Other things to try

## Requirements & Constraints

- **When the panel shows.** Only in the demo view: the server's demo mode is on and the Demo view switch is on.
  - It opens in the guide's finish state, after all five steps are done.
  - It also opens at any time from a new "More to try" link in the guide row.
  - With the demo view off, or on a non-demo install, neither the panel nor the link shows.
- **Items, in order.** Each item has a short label, one look-for line and one button that does it. An item shows only when its feature is present on the instance.
  1. **Change how OcuTalon talks.** Opens the Persona card, suggests a style such as Pirate or Spanish, then suggests asking "Is anything wrong right now?".
  2. **Send a suspicious email.** Drops the existing suspicious sample into the Simulated mailbox. Look for the refusal and its reasons.
  3. **Reject a fix.** Break the feed again, then reject. Look for "Nothing was changed."
  4. **See it as on your own install.** Turns the Demo view off.
  5. **Remember something, then ask about it later.** Needs Epic 19's memory.
  6. **Add a document and ask about it.** Look for the citation. Needs Epic 19's documents.
  7. **Write a heartbeat checklist and press Run now.** Needs Epic 39's heartbeat.
- **What ships now.** Items 1 to 4. Items 5 to 7 stay hidden on this branch because their epics (19 and 39) are still in the backlog. Their labels and look-for lines may be ruled now, so later epics only flip availability.
- **Look-for lines.** They name only what the demo shows on screen. None of the lines for items 1 to 4 mentions memory, documents or the heartbeat.
- **Labels name the on-screen controls exactly as they appear** (the owner's video script follows them):
  - the rail's Persona card, headed "Persona";
  - the mailbox chip "Sample: suspicious request";
  - the "Demo view" switch;
  - the "Break the feed" button.
  - The Planner wants every label and look-for line as early as the spec gate.
- **Public text.**
  - Every string follows the UX spec verbatim, under the public-text rules: straight ASCII quotes, styled only with DESIGN.md tokens.
  - The finish state's existing line "More to try: simulate an incoming email ..." (4.7) stays beside the new link. It changes only if the spec-gate ruling changes it.
- **Footprint.** The story touches only:
  - `web/src/app/guide/**` and new files under `web/src/app/`;
  - at most one small new read-only server class or method, for availability;
  - the web unit and e2e tests;
  - new `ci/mock/scenarios/B/*.json` files (never edit an existing scenario);
  - the UX files.
- **Tests.**
  - The panel appears after step 5 and through the link.
  - Each button performs its action on the demo path.
  - Items 5 to 7 are absent while their features are unavailable, and a unit test of the catalog shows that a feature's appearance shows its item.
  - Every control works by keyboard.
  - Nothing appears with the Demo view off or on a non-demo instance.
  - Fixed-strings tests pin the ruled strings.
  - CI is green on every workflow at merge.

## Technical Decisions

- **Server-built availability catalog.**
  - The server builds the catalog of which items to show from what it already knows about its installed classes and settings. The existing pattern for that kind of check is `OcuTalon.Channel.Telegram.In.Included()`.
  - The page reads it through a read-only read. There is no new write path, role or install step.
  - The client never hard-codes which epics have merged, so a later feature appears without a client change.
  - Fallback: if gating per feature can't avoid a code change, add one line per item when its epic merges. The spec must say which way was built.
- **Buttons reuse the existing controls exactly.** Each button acts as the existing control does:
  - the Persona card's Change disclosure (Epic 40, done). The online demo offers presets and Another language only, never Your own words;
  - the suspicious mailbox sample (`POST /api/v1/mailbox/samples/suspicious-request`, decided live as untrusted email);
  - Break the feed (`POST /api/v1/demo/break-feed`). Its availability still comes only from `Demo.Guide.Compute`, and it is inactive while an Orders incident is open;
  - the Demo view switch (4.9's client-only signal, kept in `sessionStorage`).
  - Nothing happens without a press.
- **One demo view signal.** The panel and the link read only 4.9's demo view signal, never `demoMode` directly. A source test enforces this.
- **Guide state stays server-derived.** `Demo.Guide.Compute` alone decides the finish state and step states. The page never decides progress. The "trace opened" and "run again" markers are the guide's only REST writes.
- **The all-clear rule.** An all-clear comes only from code. `check_status`'s answer is code-built, so the "Is anything wrong right now?" suggestion under a persona still gets a code-built status.
- **Focus and announcements.**
  - Focus moves only on the user's own press, or through `shared/focus-rule.ts` when an update removes the focused element.
  - The page speaks only through `Announcer`.
  - Every control is a native button or link.
- **Pinned surfaces.**
  - A new e2e folder updates `playwright-projects.test.mjs`.
  - Floor specs live in `web/e2e/floor/` (`live:floor` only). Floor rules apply there: no `transition`, no fixed heights, no `sticky` or `IntersectionObserver`, and width queries only through `LAYOUT_QUERIES`.

## UX & Interaction Patterns

- **Where it lives.** The panel belongs to the demo guide, and the "More to try" link sits in the guide row.
- **The finish state** already shows, in order: the Done line, the run total, the links, the "More to try" line, the Try it yourself chips (4.10) and Run again. The panel must coexist with these.
- **UX documents to update.** Each change carries a marker citing the owner decision of 2026-11-06.
  - EXPERIENCE.md's "Demo guide and controls": the finish state and the guide row.
  - DESIGN.md, wherever the guide's look changes.
- **Look of related controls.**
  - The Try it yourself chips use the sample email chips' look.
  - Persona card styling uses no attention colors.
  - Break the feed keeps its attention and secondary style rules.

## Cross-Story Dependencies

- **Builds on:**
  - 4.7's finish state and its "More to try" line;
  - 4.9's demo view signal and switch;
  - 4.10's Try it yourself row;
  - 4.6's sample chips;
  - 4.4's Break the feed box and its availability rules;
  - Epic 40's Persona card (done; `web/src/app/rail/persona-card/`).
- **Later epics.** Items 5 to 7 turn on through the catalog when Epic 19 (memory, documents) and Epic 39 (heartbeat) merge. They are not built in this story.
- **Run order.** The Planner ordered Story 11.26 (DW-775) to run before 4.11 on Lane B, for the 1.0.2 cut.
