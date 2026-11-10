# Epic 0 Context: OcuTalon installs, starts and lets you sign in

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 0 is the walking skeleton: one image build and `docker compose up` give OcuTalon in its own OCUTALON namespace, installed and upgraded by its one IPM package at every start, with a branded page behind sign-in, the Orders demo production in OCUORDERS, every cross-lane contract and production stub, and CI with the model mock, so the build lanes can work in parallel. Stories 0.1 to 0.21 are done. Epic 0 is re-opened once more (lane C, after Story 8.8) for Story 0.22, under the Contest Planner's More to try capacity ruling: the demo guide's More to try panel has grown into a long flat list, so its items are shown under three short group headings, letting a visitor find the kind of thing they want to try without reading every item.

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
- Story 0.19: The README names the contest (done)
- Story 0.20: Rebalance the IRIS CI groups so every group finishes well under the 35-minute budget (done)
- Story 0.21: The README opens with a centred header: logo, tagline and badges (done)
- Story 0.22: The More to try panel shows its items under three group headings (backlog)

## Requirements & Constraints

**Ruled public text (0.22).** The three group headings and their order are fixed verbatim: "Incidents and fixes", then "Memory and documents", then "Safety and settings". Current items map as: rejectFix to Incidents and fixes; memory, documents and sources to Memory and documents; suspiciousEmail, heartbeat, persona and demoView to Safety and settings. Any other new public string (an accessible name, the EXPERIENCE.md line, a fallback label for ungrouped items) goes to the Contest Planner as PUBLIC TEXT at the spec gate, before implement. Approved text is committed verbatim; if a check refuses it, the conflict goes back to the Planner, not a rewording.

**Scope of change (0.22).** Only `web/src/app/guide/more-to-try.ts`, `web/src/app/guide/more-to-try-view.ts` (the `MORE_TO_TRY_ITEMS` registry), their unit tests under `web/scripts/`, `web/e2e/guide/`, and one marked line in EXPERIENCE.md. No item's label, look-for or control text changes; no registry row changes except its `group:` field. README.md is unchanged.

**Grouping behaviour.**
- Group order lives in one exported constant. Within a group, items keep registry order. An item a later story puts first in the registry (23.6's incidentSummary) still renders first overall.
- Headings come from registry data plus the ordering constant, never a hard-coded list of three; a fourth group must need only data.
- A group with no present item (after `itemsFor` filters by the instance's features) shows no heading.
- An item with no `group` still renders, in a place the spec decides and a unit test pins.

**Tests.** Unit tests cover grouping, group order, empty-group suppression, the ungrouped fallback and focus order, reading the registry rather than a literal count. An e2e shows each heading with its items in the open panel.

**Counts and docs.** README.md and EXPERIENCE.md keep the TOTAL item count (the registry rule). EXPERIENCE.md gains one line, carrying this story's marker, listing the three groups in order; no other text changes.

**Done means:** `docker/tests/test-boundaries.sh` passes, and lane-a and ci are green.

## Technical Decisions

- **Registry is the single source.** `MORE_TO_TRY_ITEMS` already has an optional `group` field (added by Story 20.3); `itemsFor` filters items by the features the server lists in the guide's payload, and an absent feature means the item is absent, not disabled.
- **In-flight items carry their own group.** incidentSummary (23.6), reroute (23.2), warnPartner (23.5), memoryCard / pinMemory (41.13) and 37.2's item declare their own `group:` in their own stories; the merges are a plain union, so 0.22 must not depend on them.
- **Existing pins.** Ruled item strings are pinned byte for byte in `web/e2e/guide/more-to-try.spec.ts`, `web/scripts/more-to-try-view.test.mjs` and `web/scripts/ux-strings.test.mjs`; no pin may be deleted or weakened.
- **CI cost.** Story 4.11's More to try e2e tests once pushed the `live:sign-in` CI unit over its ~1,000 s line; keep the new e2e lean.
- **Lane ownership.** Epic 0 may edit files from any lane in one story.

## UX & Interaction Patterns

- **The panel.** "Other things to try" is a labelled group inside the demo guide (demo view only), opened by the "More to try" link-button (`aria-expanded`, focus stays on the link). Its label is a paragraph, never a heading. It is open by itself in the finish state (after the links, before the Try it yourself row) except in the compact band (height after banners under 680px) or where the room cannot hold its shortest window; otherwise closed until the link is pressed.
- **Group headings.** Each shown group renders as a real heading inside the panel, at the level below the panel's label, followed by its items. Since the label itself is a paragraph, the spec must settle the concrete heading level against the guide's heading outline.
- **Focus and scrolling.** The panel is one Tab stop named "Other things to try" in every band; headings take no focus and keyboard focus still moves item by item. Where the page fills the viewport the panel scrolls on its own, sized by the room the chat leaves above its floor (64px in the compact band, 160px above it), and a focused control scrolls into view. Every item must stay reachable in the compact band. The panel announces nothing; focus moves only on the user's own press.
- **Layout.** Items sit in a grid of as many columns as fit (each at least 20rem, `gap` `{spacing.2}` rows / `{spacing.4}` columns); headings must not break that layout or widen the page at 320px. The panel keeps `{spacing.1}` inline padding and a `{spacing.1}` list gutter so focus rings are never clipped. Item label is `{typography.body}` strong in `{colors.ink}`, look-for line `{typography.body-sm}` in `{colors.ink-muted}`, control a `button-secondary`.

## Cross-Story Dependencies

- **Built on 20.3 and 4.11.** 20.3 added the `group` field and the sample-runbook controls of items 6 and 8; 4.11 built the panel, its sizing and focus rules. Both are merged.
- **Sequenced after 8.8** on lane C.
- **Later stories add grouped items** (23.2, 23.5, 23.6, 37.2, 41.13); each sets its own `group:` and must render correctly through 0.22's data-driven headings.
- **Known flakes.** Inherited CI flakes (for example DW-973, DW-774, DW-689 and DW-1026) can turn a run red without a cause in this story. Classify them; do not change the story to work around them.
