# Epic 31 Context: Lane B post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Finish the Lane B pieces that were moved off the demo path so that they ship in 1.0.0. Stories 31.1, 31.2, 31.5 and 31.6 are done: live events over a WebSocket on local installs, and tool-call approvals with Approve and Reject on the phone, the paired chat and the web chat. The remaining work in this dispatch is Story 31.3. It brings the README up to 1.0.0 so that a judge goes straight to the online demo or installs without help. It also adds the MIT licence and the screenshots, adds the About and finish-state links, adds a Telegram row for your own install, and turns on the Telegram test cases left switched off in Epic 16. Epic 31 merges for the first 1.0.0 candidate once 31.3 is done, with only 31.4 still in backlog. The candidate is not cut until 31.3 has merged.

## Stories

- Story 31.1: Push live events over a WebSocket on local installs (done)
- Story 31.2: A tool call's approval request reaches the phone with Approve and Reject (part 1) (done)
- Story 31.3: The README leads to the demo, and the launched demo is measured (this dispatch)
- Story 31.4: The paired chat stays isolated under load too (backlog until after the v1.0.0 tag)
- Story 31.5: A tool call's approval request reaches the phone with Approve and Reject (notices) (done)
- Story 31.6: A tool call's approval request appears in the web chat with Approve and Reject (card) (done)

## Requirements & Constraints

- **Top of the README:** "Try it in two minutes" comes first. It has the online demo link and a note that the sign-in details are on the splash screen. It names the read-only Visual Trace account and says that trace links on the demo open Visual Trace without a second sign-in. Keep release 1's top section (What's interesting, the contest-task table and the video link) and update it for what 1.0.0 adds.
- **Full README list:** the attention decision and its four outcomes; the early-access image and build, where to get it, and which file to pick for your CPU; the load and retag steps; `ANTHROPIC_API_KEY` and the other providers; the commands to start OcuTalon and check it; the web app and read-only accounts; optional Telegram. Claim only what 1.0.0 ships.
- **IPM install section,** taken from `docs/install-ipm.md`: the registry install comes first (the community-registry line, then `zpm "install ocutalon"`), and load-from-folder second, for developers, in the same order as the IPM guide.
- **Build 109:** the early-access portal no longer offers build 154, and OcuTalon runs unchanged on build 109. Apply the Contest Planner's build-109 README wording exactly as given; the wording file is named in the dispatch, not in the planning docs. Also add its two sentences exactly as given: the bridge guide's "What you need" bullet and line 7 of `docs/install-ipm.md`. Leave every other mention of build 154. `install.sh` still finds only build 154; teaching it to find build 109 is deferred (DW-636), so the README keeps a separate path for starting with build 109. The README also carries a step 5 phrase from owner decision U-238; its text comes with the dispatch.
- **LAN warning (DW-360):** next to the README account's how-to, add how to change the default IRIS accounts' passwords in the Management Portal.
- **Public text:** plain English, with no class names or error codes outside the developer sections. No keys, local paths, private infrastructure or host names, or other entrants. Every link resolves. Keep the BMAD Method and Claude Code credits, and keep the not-affiliated note word for word.
- **Licence:** add `LICENSE` at the repository root with the standard MIT text and the holder line "Copyright (c) 2026 jbrandtmse". Under "Credits and licences" add: "OcuTalon is under the MIT License: [LICENSE](LICENSE)." The README test pins both.
- **Screenshots:** under What's interesting, show (1) the page on the demo path, with the incident card, its dry run with counts and the approval request, and (2) Visual Trace of one decision, with the model requests and tool calls as steps. Each needs plain-English alt text, lives in `docs/images/` and stays under 300 KB. A Playwright spec captures them on a throwaway stack, the way the existing trace e2e opens real Visual Trace pages; the mocked model is fine. They must show no secret other than the README account's password. The README already shows `page-incident.png` (the hero image) and `vt-decision.png`, so reuse or move those rather than adding duplicates (DW-613). New images need `git add -f`, because the ignore rule `images/` matches `docs/images/`.
- **Telegram row** in "How you talk to it": Telegram, to chat and approve on your phone, is in 1.0.0 on your own install with your own bot token. The row points to the README's Telegram section and never copies or edits its steps. This change touches only `README.md` and `docker/tests/test-readme.sh`.
- **The online demo has no bot:** nothing public in 1.0.0 (the README, docs, splash or release notes) may claim Telegram, pairing or phone approvals on the online demo, or paired-chat isolation under load. Any other sentence that mentions Telegram says "your own install". Every quoted UI string matches the built page exactly. Never write "from your phone".
- **Tests:** turn on Story 16.4's and Story 16.9's Telegram cases on their real Lane A paths: watches stop for a signed-out session, and an approval completes while both caps hold. `docker/tests/test-readme.sh` passes, and CI is green on every workflow.
- **Routed ledger items** (settle each one at story time): DW-416 (behind the demo's TLS proxy, every online-demo API POST fails the origin check; the host maps the origin as a workaround), plus the flakes DW-432, DW-453, DW-549 and DW-599.
- **Measuring the launched demo** is a 1.0.0 release check that the author runs on the public host. The story never waits on it.

## Technical Decisions

- **Lane ownership:** the README, `docker/`, `ci/` and the install script are Lane B's. The README's Telegram section (`#telegram`), `docs/bridge-guide.md`, `docs/security-overview.md`, `docs/install-ipm.md`, the rail's Telegram card and the `telegram-*.spec.ts` files are Lane A's. Link to them and don't rewrite them; the only exception is the two build-109 sentences.
- **README links:** there is one address, `https://github.com/jbrandtmse/OcuTalon#readme`, defined once as `README_URL` in `web/src/app/links.ts`. A link to a section replaces `#readme` with that section's anchor.
- **Telegram switch:** `Telegram.In.Included()` is on since Epic 12, so the README test's guard that refused the word "Telegram" no longer fires, and `#telegram` must resolve. The test also checks the Telegram section, its strings, its facts and the demo-text rule.
- **Accounts:** a local install has the README account, `ocutalon`/`ocutalon`, which holds the user, admin and trace-viewer roles. The online demo account holds the user and trace-viewer roles, so trace links open without a second sign-in. The read-only account holds the trace-viewer role only. Neither public account can change its own password. The README prints only the README account's password.

## UX & Interaction Patterns

- **About dialog:** gains the bridge developer guide and security overview links, which go after the README link and before the credits and the not-affiliated note.
- **Demo guide finish state:** gains "Use the same bridge in your own production ↗". The ↗ is hidden from screen readers, and the link's name says it opens a new tab. Both use the paths from Stories 13.3 and 14.2, which have merged.

## Cross-Story Dependencies

- Epics 10, 12, 13, 14 and 15 have merged and been integrated into this branch, so Telegram, the guide paths and `docs/install-ipm.md` are all present.
- Story 12.10, the Telegram step in narrower windows, re-opens Epic 12 on another runner. Story 31.3 does not build it.
- Story 31.4 stays in backlog. It re-opens Epic 31 after the v1.0.0 tag, along with its ledger items. Until then, host configuration keeps Telegram pairing off on the public demo.
- The epic merge requires 31.1, 31.2, 31.3, 31.5 and 31.6 to be done. Stories 39.5 and 41.5 wait for Epic 31 to merge.
