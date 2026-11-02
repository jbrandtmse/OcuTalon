# Epic 10 Context: Install in one command, with a README that gets a judge running

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A judge with the build 154 image loaded runs one script and gets a running OcuTalon. The README then takes them from download to sign-in and claims only what the release ships. Lane B's session side of Telegram is also built here, switched off until a release includes Telegram. Stories 10.1 to 10.3 have merged. The owner re-opened the epic for Story 10.4, which rewrites the top of the README so a judge sees what OcuTalon is for, and what a model adds over fixed rules, before installing anything. The Clarity of Instructions and Developer Experience criteria are judged largely on this README. From the online demo launch the feature branch becomes GitHub's default branch, so its README is what visitors see.

## Stories

- Story 10.1: One script finds the image, starts OcuTalon and says where to sign in (done)
- Story 10.2: The README gets a judge from download to sign-in (done)
- Story 10.3: The session side of Telegram is ready and stays off (done)
- Story 10.4: The README opens with what OcuTalon is for, and what a model adds

## Requirements & Constraints

**Story 10.4's new README top**
- Remove the "Contest task → where to see it" H2 and its whole table.
- Right under `# OcuTalon` comes, in this order:
  1. the owner's opening paragraph;
  2. a blank line;
  3. the existing teaser line, moved up and left unchanged;
  4. the H2s "Try it in two minutes", "What's interesting" and the new "What you can use it for".
- "What you can use it for" has exactly the story's two items: the partner feed that breaks at 2am, and "Only tell me if something needs me."
- In "What OcuTalon does", the "No key, still works." bullet is replaced by the "With a model, and without one." paragraph and its three-row table. The fixed-rules sentence in "Set a model key" stays as it is.
- Use the owner's text exactly as the story gives it. Don't polish it.
- Check every table cell against the built behaviour. If the build contradicts a cell, report it to the orchestrator for the Contest Planner. Never change the claim to match the build.
- Don't add anything else now. Later items go in with the stories that ship their features. Screenshots, a flow diagram, the measured 0.1.0 line and a CI badge are the Contest Planner's later additions.

**What the table's cells must match (the fallback route)**
- A model reply is unusable when it is a refusal, empty, cut off, an error, a timeout (60 s by default) or over a budget, or when no key is set. In each case OcuTalon never acts.
- **An item:** the outcome is Tell now, marked as a fallback with the reason.
- **An incident:** failures are grouped by fixed rules (the same production item and error pattern within the settle window). No cause is claimed and no fix is proposed.
- **A chat turn:** a plain "I couldn't answer that: {reason}. Nothing was changed."
- **With no key:** OcuTalon still starts, the page shows the no-model-key banner, every decision takes the fallback route, and the production never fails.
- Every fallback is flagged in Visual Trace. The default model is Claude Haiku 5.5.

**README rules that stay in force**
- The README claims only what the release ships and links only to what exists.
- It contains no Telegram text, no other model provider, no "from your phone" and no "per step".
- It contains no private infrastructure, no IPv4 address, no key and no local path.
- The not-affiliated note appears word for word, and OpenClaw appears only in that note. The README credits the BMAD Method and Claude Code and points to the licence notices.
- Class names and error codes appear only in "For admins and developers".
- Every anchor the page can link to reaches a heading, and no two headings share a slug.
- "What's interesting" stays at 120 words or fewer.

## Technical Decisions

- **Scope.** Story 10.4 changes only `README.md`, `docker/tests/test-readme.sh` and Story 10.2's criteria in `epics.md`. No open branch touches these files. All three belong to Lane B, and the story runs on runner B.
- **`docker/tests/test-readme.sh`:**
  - The `top` rule pins the new order.
  - The `teaser` rule pins the teaser line under the opening paragraph.
  - The `contest-table` rule is removed.
  - The pin on the "No key, still works." bullet (in `outcomes` or `key-account`) moves to the new paragraph and table.
  - Every other rule stays, above all `public-text`, `no-telegram` and the rule that the README claims only what ships.
- **Story 10.2's criteria.** Its "top of the README" criterion and its table line get an `[AMENDED 2026-10-31, owner decision, relayed by the Contest Planner]` marker that quotes what they used to say.
- **Facts behind the opening paragraph's claims:**
  - **Risk:** one governance gate classifies every tool call by fixed rules. It fails closed, and anything unclassified counts as risky.
  - **Audit:** every approval is written to the IRIS audit log through one writer.
  - **Fallback:** the bridge alone decides when a reply is unusable, and the result is a fallback.
  - **The all-clear:** it comes only from code, and a guard strips all-clear wording from model text.

## UX & Interaction Patterns

- Use the product terms exactly: Ignore, Digest, Tell now, Act, Break the feed, Visual Trace and Simulated phone.
- The README's tone is plain English for a judge.

## Cross-Story Dependencies

- **Story 10.4 depends on nothing unmerged.** It must reach the feature branch before the online demo launch, which is Sat Oct 31 midday PDT at the earliest.
- **Later additions to "What you can use it for":**
  - Story 30.4 (Epic 30's merge) appends the production-stopped or item-disabled sentence to the second item.
  - Epic 12's Telegram README section, added with Story 12.7 when it turns on `Included()`, appends the Telegram approval sentence to the first item.
  - Story 13.3's bridge guide adds a third item, linking the guide's real path.
- **Downstream.** Epic 11 (release 1) depends on Epic 10. Epic 12 builds on Story 10.3 and merges only after `v0.1.0` is tagged.
