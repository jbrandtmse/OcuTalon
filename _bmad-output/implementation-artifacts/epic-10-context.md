# Epic 10 Context: Install in one command, with a README that gets a judge running

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A judge with the build 154 image loaded runs one script and gets a running OcuTalon, and the README takes them from download to sign-in while claiming only what the release ships. Lane B's session side of Telegram is also built here, switched off until a release includes Telegram. Stories 10.1 to 10.4 are done. The owner re-opened the epic for two docs-only stories in 1.0.0's scope, neither launch-blocking. Story 10.5 (planned next) lets a judge see the product before installing it, through five vetted screenshots, and adds a "How you talk to it" section. Story 10.6 adds that section's Telegram row once Telegram ships. The Clarity of Instructions and Developer Experience criteria are judged largely on this README, and the feature branch's README is what GitHub visitors see.

## Stories

- Story 10.1: One script finds the image, starts OcuTalon and says where to sign in (done)
- Story 10.2: The README gets a judge from download to sign-in (done)
- Story 10.3: The session side of Telegram is ready and stays off (done)
- Story 10.4: The README opens with what OcuTalon is for, and what a model adds (done)
- Story 10.5: The README shows the product and says how you talk to it
- Story 10.6: The README's "How you talk to it" section adds Telegram (waits on Epic 12)

## Requirements & Constraints

**"How you talk to it" (10.5)**
- A new section after "What you can use it for"; a small table is fine.
- The web chat page is the product on every install. The demo adds only the demo guide, Break the feed, the simulated phone and the simulated mailbox. Email comes in a later release (step 4). Slack is not named.
- No Telegram row and no Telegram word: that row is Story 10.6's. Every claim matches what 1.0.0 ships.

**Telegram row (10.6)**
- Telegram, to chat and approve on your phone, is in 1.0.0, on your own install with your own bot token. It points to Epic 12's README Telegram section and never duplicates or edits its steps.
- No online-demo text claims Telegram, pairing or phone approvals (the demo has no bot). Quoted UI strings match the built page exactly.

**Screenshots (10.5)**
- Exactly the five images the Contest Planner vets and delivers: the page with an incident (the hero), the incident card, the resolved incident, a Visual Trace of the decision, and the page with Demo view off. The draft Visual Trace watch shots are not used.
- Copy them as delivered into `docs/images/`; never re-shoot or edit. The hero goes under the opening paragraph, the others where the text describes them, each with alt text saying what it shows.
- Look at every image before committing (the repository is public). An IP address, credential, token, session id, cookie, gate user name, personal or account detail, or any host name other than `demo.ocutalon.com` stops the story with a clarification, and that image is never committed.
- Not in 10.5: the Mermaid diagram, the evaluation line and the CI badge (the 1.0.0 README pass).

**README rules that stay in force**
- Claims only what the release ships; links only to what exists. No private infrastructure, IPv4 address, key or local path; no other model provider; no "from your phone".
- The not-affiliated note word for word, OpenClaw only in it; BMAD Method and Claude Code credits; licence pointers.
- Class names and error codes only in "For admins and developers". Every anchor reaches a heading, no duplicate slugs. "What's interesting" stays at 120 words or fewer.
- Story 10.4's owner text stays exact: the opening paragraph, the teaser, "What you can use it for" and the with-a-model table.

## Technical Decisions

- **Footprints.** 10.5: only `README.md`, `docs/images/*` and `docker/tests/test-readme.sh`. 10.6: only `README.md` and `docker/tests/test-readme.sh`. All Lane B files. CI green on every workflow.
- **Telegram is still off on this branch.** `OcuTalon.Channel.Telegram.In.Included()` has its test-only body, so the `no-telegram` rule refuses the word Telegram anywhere in README.md. The `public-text` rule refuses "from your phone" on every branch, so 10.6 says "on your phone". When Epic 12 replaces that body, the check allows the word and requires a `#telegram` heading on its own; the README changes, not the check.
- **Existing rules that collide with 10.5's images.** The `top` rule allows only the opening paragraph and the teaser line between the title and the first H2, so a hero under the opening paragraph breaks it. The `teaser` rule flags any image or embed (`![`, `<img>`, `<picture>` and the like) anywhere in the README. 10.5 has to rework both rules to allow its images, keeping their other pins: the teaser stays a plain link two lines below the opening. `top` also pins the H2 order, so the new section's place goes there.
- **New checks (10.5).** The new section's heading, and every image link resolving to a file in `docs/images/` with non-empty alt text. Make the image check general: it covers every image link and names no files. Story 31.3 (backlog, a later README pass) also adds screenshots under `docs/images/` (each under 300 KB) and its own checks in test-readme.sh, so a check listing the five files would have to be undone. `readme-links` already resolves link targets to repository files.
- **Out of scope.** DW-554 (one shared name scanner for test-readme.sh and `release/checklist.sh`) is routed to Epic 10's first README story after 1.0.0, not to 10.5.
- **Demo view** (Story 4.9) is client-only. With it off, the guide, the Demo control with Break the feed, and the simulated phone and mailbox disappear, and the page looks as it does on a real install. The online demo's "Online demo" pill, reset countdown and allowance lines stay. Describe that screenshot to match.

## UX & Interaction Patterns

- Use the product terms exactly: Ignore, Digest, Tell now, Act, Break the feed, Visual Trace, Simulated phone, simulated mailbox, Demo view.
- On every install, the web page is where you chat and approve. The demo guide, Break the feed and the simulated devices are demo-only.

## Cross-Story Dependencies

- **10.5 starts** once Story 4.9 is deployed to the demo host and the Contest Planner has delivered the five images.
- **10.6 starts** only after Epic 12 has merged to the feature branch and been integrated into this epic's branch. That merge replaces `Included()`'s body and adds the README's Telegram section, in the same Epic 12 change. 10.6 edits the section 10.5 added.
- **Story 31.3 (backlog)** adds its own README screenshots (the page on the demo path, and a Visual Trace of one decision) under "What's interesting". If they overlap 10.5's images, raise a clarification rather than deciding it here.
- **Later additions to "What you can use it for" belong to their own stories:** Epic 12's Telegram approval sentence and Story 13.3's bridge-guide item. Story 30.4's production-stopped sentence is already in.
