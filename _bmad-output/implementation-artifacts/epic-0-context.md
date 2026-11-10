# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton: one image build and `docker compose up` give OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start, with a branded page behind sign-in, the Orders demo production in OCUORDERS, every cross-lane contract and production stub, and CI with the model mock, so both build lanes can work in parallel. Stories 0.1 to 0.18 and 0.20 are done. Epic 0 is re-opened again for release 1.0.6 with two README stories, both owner-approved through the Contest Planner. Story 0.19 names the contest in the README's contest checklist (DW-1020). Story 0.21 then opens the README with a centred header (logo, title, tagline and status badges), so a judge sees what OcuTalon is and whether it is healthy before reading the body.

## Stories

- Story 0.1: The image builds and starts OcuTalon in its own namespace (done)
- Story 0.2: The package installs and upgrades itself at every start (done)
- Story 0.3: Sign in to an empty OcuTalon page (done)
- Story 0.4: The cross-lane message and data contracts (done)
- Story 0.5: Live events and the REST skeleton (done)
- Story 0.6: Every release-1 production item runs as a stub, beside the Orders production (done)
- Story 0.7: CI runs on hosted runners and the IRIS runner, with the model mock (done)
- Story 0.8: The demo-path test signs in and loads the page (done)
- Story 0.9: The message catalog and its one renderer (done)
- Story 0.10: The Orders demo production runs in OCUORDERS (done)
- Story 0.11: The CI model mock answers every scenario the stories need (done)
- Story 0.12: Epic 0 burn-down (done)
- Story 0.13: A start retries the CPF merge when IRIS cannot quiesce (done)
- Story 0.14: A start that recovers through the merge retry passes the live checks and the upgrade harness (done)
- Story 0.15: The Dockerfile sits at the repository root (done)
- Story 0.16: The Embedded Python callback crash (S11) is re-verified with a minimal reproduction (done)
- Story 0.17: The README's evaluation table shows release 1.0.4's numbers (done)
- Story 0.18: The README shows judges where to look (done)
- Story 0.19: The README names the contest (backlog)
- Story 0.20: Rebalance the IRIS CI groups so every group finishes well under the 35-minute budget (done)
- Story 0.21: The README opens with a centred header: logo, tagline and badges (backlog)

## Requirements & Constraints

**Approved public text is committed verbatim.** The 0.19 checklist line and the 0.21 tagline are approved word for word. If a README check rule refuses approved text, the text is not reworded; the conflict goes back to the Contest Planner.

**The spec gate for 0.21.** The exact header markup (alt texts, badge labels, link targets) and any new or changed README-check rule message go to the Contest Planner as PUBLIC TEXT before the implement stage. The `test-readme.sh` change is not a release tool, so it needs no release-tool review.

**Scope of change.**
- 0.19 changes README.md only, and only the one checklist line. Nothing else in the README changes.
- 0.21 changes only README.md, `docker/tests/test-readme.sh` and the new `docs/images/ocutalon-logo.png`.

**README rules that stay in force:**
- "Try it in two minutes" stays at the top of the body, with the online demo link. The existing link bar follows the new header unchanged.
- The README keeps the not-affiliated note, the credits, and plain language.
- Public text holds no keys, local machine paths, private infrastructure details or other entrants' names.

**The README check (0.21).**
- The new allowance covers only the one header block: badge images from img.shields.io and from the repository's own CI `badge.svg` path, images inside links within the block, a centred HTML wrapper if needed, and the logo PNG.
- Every existing rule stays as strict outside the block. The top rule (opening paragraph, teaser, hero image) applies from the first line after the header.
- New self-tests prove that each of these is flagged: a badge outside the header, a badge from another host, and an image inside a link outside the header.
- No pin is deleted or weakened.

**Done means:**
- `bash docker/tests/test-readme.sh` passes every rule and self-test.
- `docker/tests/test-boundaries.sh` passes.
- Lane-a CI is green.
- For 0.21, the header renders correctly on the pushed branch's GitHub README page.

## Technical Decisions

- **Badge anchors must resolve.** The badges link to in-page anchors (`#start-it-with-the-install-script`, `#install-it-with-ipm`, `#whats-interesting`). Each must match a heading's GitHub slug in the current README. The license badge links to `LICENSE`, the online-demo badge to https://demo.ocutalon.com, CI to the ci.yml runs page and the version badge to Releases. Static shields use plain colours. The docker logo on its badge is optional.
- **Link allow-list.** `community.intersystems.com` is already on `test-readme.sh`'s allow-list, so 0.19's contest-post link needs no rule change. No AI Hub bug-report repository may be allowed.
- **Portability.** `test-readme.sh` also runs under macOS's bash 3.2 in hermetic tests, so shell changes must be portable.
- **Lane ownership.** `docker/` belongs to Lane B, but Epic 0 may edit files from both lanes in one story.

## UX & Interaction Patterns

- **Choosing the logo.** `docs/images/ocutalon-logo.png` is about 200 px, made from `logo/OcuTalon-Icon.jpeg` or the light logo, whichever reads better at about 160 px on both of GitHub's themes.
- **Brand rules.** The light logo has a white background box that shows on dark or tinted surfaces. The icon mark carries a navy tile, which must stay intact. Never recolour, crop, outline or animate the logo.
- **Header order.** The logo, the title OcuTalon, the one-line tagline, the badge row, then the existing link bar.

## Cross-Story Dependencies

- **0.21 follows 0.19.** Both are on the same lane and both edit README.md, so build 0.21 on 0.19's merged README.
- **Built on earlier stories.** Both build on the 0.17 and 0.18 README (link bar, judges' table, contest checklist) and on 0.15's root Dockerfile, all already merged.
- **Release target.** Both target release 1.0.6.
- **Known flakes.** Inherited CI flakes (for example DW-973, DW-774, DW-689 and DW-1026) can turn a run red without a cause in these stories. Classify them; do not change the stories to work around them.
