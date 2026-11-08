# Epic 4 Context: The demo page: guide, simulated phone and mailbox, and Break the feed

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Demo mode turns the signed-in page into the self-guided two-minute demo. It has a demo guide with one-click prompts, a labelled simulated phone and simulated mailbox (real production channels), and a Break the feed control that makes the simulated partner send the session's 50 orders in a changed date format, which fail for real. The server derives guide progress and Break the feed availability from what really happened, so nothing is claimed or canned. Stories 4.1 to 4.11 built all of this, ending with the "Other things to try" panel. Epic 4 is re-opened for Story 4.12, a one-string fix-forward. The panel's document tip promises "the citation under the answer", but the web chat draws no citations in 1.0.4 (that is Story 20.2, not built). A judge who follows the tip would look for something that is not there. The fix makes the tip promise only what the page shows. Target: the v1.0.4 cut, which waits for it. Lane B.

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
- Story 4.11: Other things to try (done)
- Story 4.12: The demo guide's document tip promises only what 1.0.4 shows

## Requirements & Constraints

- **The ruled string (public text, the Planner's ruling `guide_documents_citation_promise`).** Item 6, labelled "Ask about a document", gets this look-for line, verbatim and byte for byte:
  `On the Documents page, add a short file, such as a runbook (nothing personal: Visual Trace on the demo is shared). Then ask about it in the chat, and look for the answer that comes from your file.`
  - It lives in `web/src/app/guide/more-to-try-view.ts`, as the `documents` item's `lookFor`.
  - Item 6's label and its control "Open the Documents page" stay as they are.
- **Exactly four files change, each hunk a one-string swap:**
  - `web/src/app/guide/more-to-try-view.ts` (the source);
  - `web/e2e/guide/more-to-try.spec.ts` (pin);
  - `web/scripts/more-to-try-view.test.mjs` (pin);
  - `web/scripts/ux-strings.test.mjs` (pin).
  - No label, button or other string changes. No other file changes.
- **The UX source is already amended.** EXPERIENCE.md's item 6 already carries the ruled string with a marker citing the ruling (the lead made this planning amendment at the charter). `ux-strings.test.mjs` reads EXPERIENCE.md as the string's source, so the code and all three pins must match it exactly. The developer does not edit EXPERIENCE.md.
- **Public-text rules apply.** Straight ASCII quotes and punctuation exactly as ruled. Nothing is paraphrased or reflowed.
- **Later work.** Story 20.2 restores a citation line when it ships, and the ledger entry for that belongs to 20.2. This story adds no ledger entry for it.
- **CI is green on every workflow at merge.**

## Technical Decisions

- **How the panel works (from 4.11, unchanged here).**
  - The panel has seven items, in a fixed order, each with a label, a look-for line and one native button or link.
  - The server lists which features are present in the guide's payload, through a read-only read. An item whose feature is absent is left out, not shown disabled.
  - The client never hard-codes which epics have merged.
- **Signals and state.**
  - The panel and the "More to try" link read only 4.9's demo view signal, never `demoMode` directly.
  - `Demo.Guide.Compute` alone decides guide progress.
- **Strings are pinned in three places.** The e2e spec, the view's unit test and the UX-strings test each pin the ruled strings. A changed string means all three pins change in the same commit as the source.

## UX & Interaction Patterns

- **Where the panel lives.** It sits in the demo guide, in the demo view only. In the finish state it opens by itself, after the links and before the Try it yourself row. The "More to try" link in the guide row opens it at any time.
- **Item 6's control** is a link to the Documents page.
- **Look-for lines name only what the demo shows on screen.** That rule is the reason for 4.12: the 1.0.4 chat draws no citation, so no line may promise one.

## Cross-Story Dependencies

- **Builds on 4.11.** 4.12 changes only one string from 4.11's item catalog (`more-to-try-view.ts`) and its existing pins.
- **Story 20.2** (web chat citations, not built) will bring a citation promise back when it ships.
- **The v1.0.4 release cut** waits for this story to merge.
