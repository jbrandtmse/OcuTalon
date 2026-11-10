---
title: 'Story 0.22: The More to try panel shows its items under three group headings'
type: 'feature'
created: '2026-11-09'
status: 'done'
baseline_revision: '9ad2d7a492e0fc4648c832bcc8623bdfd891b6db'
baseline_commit: '9ad2d7a492e0fc4648c832bcc8623bdfd891b6db'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The demo guide's "Other things to try" panel shows its items as one flat list, and the in-flight stories (23.6, 23.2, 23.5, 41.13, 37.2) will take it to twelve or more. A visitor has to read every item to find the kind of thing they want to try.

**Approach:** Every registry item declares one of three ruled groups. One exported constant holds the order of the groups. A framework-free `groupsOf` in `more-to-try-view.ts` turns the items that `itemsFor` gives into ordered groups. The panel renders each group as an `h4` heading followed by its own list. Focus order, the room logic and every item text stay as they are. EXPERIENCE.md gets one marked line.

## Boundaries & Constraints

**Always:**
- Group text, membership and order are exactly as ruled (Contest Planner, 2026-11-10, with its CORRECTION):
  - "Incidents and fixes": `rejectFix`.
  - "Memory and documents": `memory`, `documents`, `sources`.
  - "Safety and settings": `suspiciousEmail`, `heartbeat`, `persona`, `demoView`.
  - The groups show in that order. Within a group, items keep their registry order.
- The order lives in ONE exported constant, `MORE_TO_TRY_GROUPS` in `more-to-try-view.ts`. Headings are rendered from item data plus that constant. No list of the three headings is written in the component or the template.
- `groupsOf(items)` returns, in this order:
  1. The items with no group (`group` undefined, empty or whitespace only), as one set with no heading, in input order.
  2. Each group of `MORE_TO_TRY_GROUPS` that has at least one item.
  3. Any other group, in the order its name first appears in the input.
  Every input item appears exactly once, and within each set the input order is kept.
- Headings are `<h4>` elements. They have no `tabindex` and no `id`, and their text is the group's own string. The panel label stays a `<p>`. The panel stays one Tab stop, and Tab then moves control by control in the order shown.
- Registry rows change by their `group:` field ONLY, appended at the end of the row. Rows are not reordered or reformatted. No item label, look-for or control text changes. The comment lines that in-flight branches edit or that `sources-docs.test.mjs` pins stay byte-identical: `more-to-try-view.ts` lines 1-12 and line 94, and `more-to-try.ts` lines 33-55 and 58.
- README.md is unchanged (it keeps the total count). EXPERIENCE.md gains exactly the one line under Design Notes, plus the renumbering by group (below), and no other text changes. [AMENDED 2026-11-10 by the lead, Contest Planner ruling ~06:40Z relayed by the orchestrator: EXPERIENCE.md's More to try entries are renumbered by group: the three ruled headings, with the order inside each group; EXPERIENCE-only, marker `[AMENDED 2026-11-10, Contest Planner ruling]`; the TOTAL count rule stays; in-flight items stay a plain union at their merges.] The renumbered section is exactly the text under `### EXPERIENCE renumbering` in Design Notes: one `    - Heading "<group>".` entry per group, each followed by its items as `    - Item <n>. ...` numbered 1 to 8 in the panel's order, and the item numbers in the two lines after the list renumbered to match. Item labels, look-fors and controls do not change.
- No test pins a group's size or the number of groups as a literal; headings and membership come from the registry data and `MORE_TO_TRY_GROUPS`. [ADDED 2026-11-10 by the lead, Contest Planner ruling for Story 37.2 ~07:00Z relayed by the orchestrator: the 13th item, id `usage` (Story 37.2), joins "Safety and settings" as its LAST item, so that group will have five; there is no fourth heading; it arrives as a plain union at 37.2's merge.]
- Source stays ASCII (Rule 14). Comments state the contract only.

**Never:**
- Never add an item, a group string other than the three, an `aria-label`, a fallback label, or any other visible or assistive string.
- Never change `more-to-try-room.ts`, `COMPACT_BAND_HEIGHT`, `CHAT_FLOOR`, `windowBound`, `--more-window-min` or the guide (`demo-guide.ts`).
- Never edit `origin/OCT-epic23`, `origin/OCT-epic41` or any other branch. Never delete or weaken an existing pin. A pin whose shape moves is re-expressed (see Shared surfaces).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Every feature | finish, `features` = every registry id | The headings, each followed by its items:<br>- "Incidents and fixes": Reject a fix<br>- "Memory and documents": Ask it to remember something, Ask about a document, See where an answer came from<br>- "Safety and settings": Change how OcuTalon talks, Send a suspicious email, See the page as on your own install, Run a heartbeat check-in | No error expected |
| A group with no present item | `persona, suspiciousEmail, rejectFix, demoView` | "Incidents and fixes" (Reject a fix), then "Safety and settings" (the other three). There is no "Memory and documents" heading. | No error expected |
| No features | `undefined` or `[]` | `groupsOf` gives `[]`: no heading and no list | No error expected |
| Ungrouped item (later story forgets `group`) | an item with no group, or `group: '  '` | It renders first, before the first heading, in a list with no heading | It never becomes an empty heading |
| Group not in the constant | an item with `group: 'X'` | After the ordered groups, under heading "X", in first-appearance order | No error expected |
| 23.6's item, first in the registry | an item first in the input, with group "Incidents and fixes" | It is first overall | No error expected |
| Keyboard | panel open, Tab from its stop | The controls take focus one by one, in the order shown. No heading takes focus. | No error expected |
| Compact band | framed 1280x650 and 1280x600 | Tab brings every control wholly into view, with its ring, inside the panel's own scroll | No error expected |

</intent-contract>

## Code Map

- `web/src/app/guide/more-to-try-view.ts` -- framework-free registry module.
  - `MoreToTryItem.group?: string` (line 91; Story 20.3).
  - `MORE_TO_TRY_ITEMS` rows (lines 96-103). Only `sources` has a group today.
  - `itemsFor` (106-112) filters by the server's features (AD-12). It is the sibling that `groupsOf` composes on.
  - Line 94 `/** The eight items, in the order the panel shows them. */` is pinned by `sources-docs.test.mjs:54`, and both in-flight branches rewrite it. Leave it.
- `web/src/app/guide/more-to-try.ts` -- the panel.
  - Template lines 65-87: one `<ul class="items">` inside `.group` (role=group, tabindex 0, `data-guide-focus="moreItem"`).
  - Styles lines 89-171. In framed mode, `.items` has `padding-block-end: var(--space-scroll-gutter)` (pinned).
  - `items` input (185). `sampleFirst` reads `items()`; keep that.
  - The doc comment is edited by both in-flight branches at lines 37-43 and 58. The safe insertion point is after line 56.
- `web/src/app/guide/more-to-try-room.ts` -- read only. It measures `.group`'s whole height (content-agnostic), so the headings only add scroll content.
- `web/src/app/rail/memory-card/memory-card.ts:70,171-177` -- precedent: `h4.day` group headings under a card's h3, styled caption size, strong weight, ink-muted.
- `web/src/app/main-page/main-page.ts:65-108` and EXPERIENCE.md line 79 -- the heading outline: one `h1`, one `h2` per region, one `h3` per rail section or card headline. The guide (`app.ts:45`) is a region labelled by a span, with no heading. It sits before the `h1` in DOM order.
- `web/scripts/more-to-try-view.test.mjs` -- `GROUP_OF` (line 98) and the test "no other entry a group yet" (116-118) move. New `groupsOf` cases go here.
- `web/scripts/more-to-try-sources.test.mjs` -- these pins move:
  - "names no aria-label and no icon on a control, and no heading" (50-54), which asserts the template has no `<h[1-6]`.
  - "is a labelled group with a list" (56-60). It keeps `<ul class="items">` and the three `data-guide-focus` occurrences.
- `web/scripts/ux-strings.test.mjs` -- line 67 is `IMPORTED` for this module, and `SOURCES.ux` holds the panel strings (around 429-458). Add the three headings after `"Remember that the Results partner's contact is Lee.",` (no in-flight branch touches that spot).
- `web/scripts/sources-docs.test.mjs` -- the counts follow the registry (unchanged). Add the EXPERIENCE group-line check at the end of the `EXPERIENCE.md, More to try` describe.
- `web/e2e/guide/more-to-try.spec.ts` (runs in `live:sign-in-3`):
  - K1 (233), K2 (253 `'and no heading'`, 255-256) and K3 (285) assert the flat registry order.
  - K4 (352-355) asserts Tab order over `FOUR`.
  - `measureRoom.columns` (801, 811) reads the first row of all `li` together. `clipped` (815) checks `.item-label, .look-for`.
  - `expectRoom` (911) expects `min(FOUR.length, fit)` columns, and `expectTabInView` (928) iterates `FOUR`.
  - `FOUR` and `ALL` are defined at 61-63.
- `web/e2e/guide/guide.spec.ts:131,201` -- read only. Q1 checks a blank guide (panel closed): no heading, and level 2 is only Status and Chat. Both still hold.
- `web/e2e/guide/more-to-try-sample.spec.ts`, `web/e2e/floor/guide.spec.ts:564-580` and `web/e2e/chat/try-it.spec.ts:292-297` -- read only. They find items by listitem or name and assert no order, so they still hold.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md:245-255` -- the count line (245, unchanged), the eight `    - Item n.` entries (246-253), and the two lines that cite item numbers (254 `  - Item 5 sends ...`, 255 `  - A control does what ...`). The renumbering replaces 246-255 with the text under `### EXPERIENCE renumbering`; the new marked line goes right after it, before `  - Every control is a native button or link`.

## Tasks & Acceptance

**Execution:**
- `web/src/app/guide/more-to-try-view.ts`:
  - Add `export const MORE_TO_TRY_GROUPS: readonly string[] = ['Incidents and fixes', 'Memory and documents', 'Safety and settings'];` with a doc comment: the panel's group headings, in the order shown.
  - Add the exported `MoreToTryGroup` type (`heading?: string; items: readonly MoreToTryItem[]`) and the exported `groupsOf(items)` (Boundaries rule), each with a contract doc comment. Place them after `itemsFor`.
  - Append the `group:` of each row, as ruled.
  - Add one module-header bullet for `MORE_TO_TRY_GROUPS`/`groupsOf`, inserted after line 12 (lines 1-12 untouched).
- `web/src/app/guide/more-to-try.ts`:
  - Add `protected readonly groups = computed(() => groupsOf(this.items()));`.
  - In the template, after the label, add `@for` over `groups()`. For each set: `@if (set.heading)` renders `<h4 class="set-heading">{{ set.heading }}</h4>`, then `<ul class="items">` holds that set's existing `<li>` markup, unchanged.
  - Style `.set-heading`: `margin: var(--space-2) 0 0`, caption font size and line height, `--type-body-strong-font-weight`, `color: var(--ink-muted)`. It wraps at 320px and is never clipped.
  - Add one sentence about the headings to the doc comment, after line 56.
- `web/scripts/more-to-try-view.test.mjs`:
  - `GROUP_OF` holds every ruled id, one key per line. Retitle the group test to "give every entry its ruled group".
  - Add a `groupsOf` describe, reading the registry and never a literal count. It covers:
    - `MORE_TO_TRY_GROUPS` is exactly the ruled three, in order.
    - Every registry group is in `MORE_TO_TRY_GROUPS` (typo guard).
    - Over the whole registry: heading order, and registry order within each group.
    - Empty-group suppression (`FOUR`, `[]`).
    - The ungrouped fallback (undefined and blank groups come first, with no heading).
    - Unknown groups go last, in first-appearance order.
    - A synthetic "Incidents and fixes" item first in the input stays first overall.
    - Every input item appears once, for `itemsFor([...FOUR, id])` for each id. The flattened sets are the focus order.
- `web/scripts/more-to-try-sources.test.mjs`:
  - Replace the no-heading pin. The template's only heading is one `<h4 class="set-heading">` with no `tabindex` or `id`, and its text is `{{ set.heading }}`. Still no `aria-label` and no icon.
  - `more-to-try.ts` holds none of the three heading strings.
  - The template iterates `groups()` from `groupsOf(this.items())`.
  - Keep the `<ul class="items">` and `data-guide-focus` (3) pins.
- `web/scripts/ux-strings.test.mjs` -- line 67 becomes `['MORE_TO_TRY_TEXTS', 'MORE_TO_TRY_GROUPS']`. Add the three headings to `SOURCES.ux`.
- `web/scripts/sources-docs.test.mjs`:
  - A new `it`: EXPERIENCE.md has exactly one line holding this story's marker. That line names every `MORE_TO_TRY_GROUPS` entry, quoted, in order, and says the count word `WORDS[MORE_TO_TRY_GROUPS.length]`.
  - The registry-order test ("lists the registry's items in the order of its entries") moves to the panel's order: the labels of the lines matching `/^    - (Item \d+|First item)\b/` equal the labels of `groupsOf(MORE_TO_TRY_ITEMS)` flattened, and no other (the same line filter `origin/OCT-epic23` uses, so 23.6's "First item" and 23.2's "Item 9" fit at their merges). The `    - Heading "<group>".` lines are exactly the headings of `groupsOf(MORE_TO_TRY_ITEMS)`, in order, and each is followed by exactly its group's item lines. No literal group size or count.
  - The `[6, 'documents']`, `[8, 'sources']` pins compute each entry's number from the panel order (the position in `groupsOf(MORE_TO_TRY_ITEMS)` flattened, plus 1), never a literal number.
- `web/e2e/guide/more-to-try.spec.ts`:
  - Import `groupsOf` and `MORE_TO_TRY_GROUPS`. Add `shown(ids)` = the ids of `groupsOf(itemsFor(ids))`, flattened.
  - K1, K2, K3 and K4 assert the shown order. K2 drops `'and no heading'` and asserts `panel.getByRole('heading', { level: 4 })` is `['Incidents and fixes', 'Safety and settings']`, and that the label is still a `p`.
  - `expectTabInView` iterates `shown(FOUR)`.
  - `measureRoom.columns` is per `ul.items`, and `expectRoom` expects `min(list size, fit)` for each list. Add `.set-heading` to `clipped`.
  - Add one lean test, K25 (routed finish, `ALL`, 1280x900). Its oracle is the ruled heading strings written out. The level-4 headings in the panel are exactly the groups that have items, in order. Each heading's next `ul.items` holds exactly its group's labels, in registry order. The label `p` is not a heading, and no heading has a `tabindex`. Update the header list to name K25.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- replace lines 246-255 with the text under `### EXPERIENCE renumbering` verbatim (byte for byte, as approved at the gate), then insert the approved marked line verbatim right after it.

**Open items (infra re-dispatch, 2026-11-10 08:2xZ; the code and tests are written and uncommitted in the tree):**
- [x] [Infra] Run e2e part 2/9 of `sign-in-3` locally (holds `e2e/guide/more-to-try.spec.ts`: K1-K4, K16/K17, K25) on a fresh lane-C throwaway (`n` is 9) -- passes. Post-crash (2026-11-10 ~15Z, orchestrator): the host hold and stack cap are lifted and lane C is first in the stagger, so the local e2e tier is tried first; if the start fails (400 s timeout or a stuck bake), fallback (a) under `## Verification` applies (CI carries this item).
- [x] [Infra] Run e2e part 1/9 of `sign-in-3` locally (holds `guide.spec.ts` and `more-to-try-sample.spec.ts`) -- passes (same fallback).
- [x] [Infra] Demonstrate the e2e-level mutations (K25, K2, K4, K16) on the lane-C throwaway, each red and reverted byte-identical, with their `mutation:` lines. If no stack can start, they move to QA (fallback (a), condition 2), never skipped.
- [x] [Infra] `bash ci/checks.sh` (in batches of its `CHECK_SCRIPTS`) -- every block passes.
- [x] [Infra] Then the skill's review layers and the finalize commit.

**Acceptance Criteria:**
- Given the registry, when this story merges:
  - every existing item declares its ruled group, and `MORE_TO_TRY_GROUPS` is the ruled order;
  - the diff of `MORE_TO_TRY_ITEMS` changes only `group:` fields;
  - `more-to-try-view.test.mjs` pins all of it.
- Given the open panel (consumer `more-to-try.ts` reads `groupsOf` and renders, the Integration AC), when it renders `itemsFor`'s items:
  - each group with an item shows an `h4` with its text, followed by its items;
  - a group with no item shows no heading;
  - ungrouped items render first, with no heading;
  - all of this is pinned by K25, K2 and the `groupsOf` unit tests.
- Given the keyboard, when Tab moves from the panel's stop, then each control takes focus in the order shown and no heading takes focus (K4). In the compact band, every control scrolls wholly into view with its ring (K16 and K17 at 1280x650 and 1280x600).
- Given the docs:
  - README.md is unchanged;
  - EXPERIENCE.md's item count and item texts are unchanged; its entries are listed and numbered by group in the panel's order (the approved renumbering), plus the one marked line;
  - `sources-docs.test.mjs`, `ux-strings.test.mjs` and `docker/tests/test-boundaries.sh` pass;
  - lane-a and ci are green.

### Review Findings

Code review 2026-11-10 (review tier full-opus; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 35 raw rows, 9 entries after grouping).

- [x] [Review][Patch] (med, fix-risk low, in-story) K25 wrote each group's member ids out by hand (`RULED_GROUPS`), so every in-flight item (23.6 `incidentSummary`, 23.2, 23.5, 41.13, 37.2 `usage`) turned K25 red and needed an edit of an existing line, against the 37.2 ruling ("membership come from the registry data") -- K25 now keeps the ruled heading strings written out as its oracle and takes membership from the registry's `group` fields, so an item that declares its group needs no K25 edit [web/e2e/guide/more-to-try.spec.ts:1464]
- [x] [Review][Patch] (med, fix-risk low, in-story) `sources-docs.test.mjs` numbered EXPERIENCE entries by panel position, so 23.6's unnumbered "First item" entry (already on feature, "the numbers of the items below stay as they are") would turn the panel-order and Documents-item pins red at integrate-forward -- the number of an entry now counts only the panel's items whose entry is numbered (`NUMBERED`); identical today [web/scripts/sources-docs.test.mjs:102]
- [x] [Review][Patch] (med, fix-risk low, in-story) K2 narrowed the old guide-wide "no heading" guard to the panel, so a heading added elsewhere in the finished guide went unpinned (spec: never weaken an existing pin) -- K2 counts the headings of the whole guide region (2) [web/e2e/guide/more-to-try.spec.ts:259]
- [x] [Review][Patch] (low) the template's heading pin matched only headings with plain text, so a second heading with child markup escaped it -- added a count of every `<h1-6` opening (one) [web/scripts/more-to-try-sources.test.mjs:72]
- [x] [Review][Patch] (low) the unit case "the flattened sets are the focus order" asserted no order -- it now asserts the order shown, from `GROUP_OF` [web/scripts/more-to-try-view.test.mjs:223]
- [x] [Review][Patch] (low) `expectRoom`'s clipped message still named only labels and look-fors after `.set-heading` joined the check [web/e2e/guide/more-to-try.spec.ts:904]
- [x] [Review][Patch] (low) the EXPERIENCE marked-line test sat mid-describe, not at its end as the Code Map asks -- moved to the end [web/scripts/sources-docs.test.mjs:171]
- [x] [Review][Patch] (low) the spec's planned e2e mutation "two entries of `MORE_TO_TRY_GROUPS` swapped -> K25 red" was never run -- demonstrated (see `## Verification`)
- [x] [Review][Defer] (low) the render of an ungrouped set is pinned by unit tests and a source-text match only (no component test host; every registry row is grouped, so no e2e can render one) [web/src/app/guide/more-to-try.ts:69] -- deferred: DW-1084 `wontfix-accepted`, reopen_if a registry item ships with no group or web gains a component test host

Merge note (integrate-forward with feature, which holds 23.6): `git merge-tree` shows textual conflicts in EXPERIENCE.md, the registry, the e2e spec and the three unit files, as the in-flight rows were expected to give. After this review's patches, 23.6 needs: `group: 'Incidents and fixes'` on `incidentSummary` (the ruled merge instruction), its `GROUP_OF` line, and its "First item" EXPERIENCE entry placed after `Heading "Incidents and fixes"` and before Item 1; K25 and the numbering pins need no edit.

Rejected:
- (by-design) Edge 1/2/6: `--more-window-min` and `measureRoom.need` leave out the heading height -- the spec's Never list keeps `--more-window-min` unchanged; the first item's label and look-for already sat above its control before this story; K16/K17 (Tab brings every control wholly into view) are green.
- (by-design) Blind 1 (part): `GROUP_OF` needs a key for each in-flight item -- the spec designs it one key per line, a one-line union at each merge; it is AC1's literal membership pin.
- (low, theoretical) Edge 4: a group name with stray whitespace or case becomes a second heading -- registry data is authored and the typo-guard unit test compares exact strings.
- (false) Edge 7: spec `status: done` against sprint-status `review` -- the frontmatter is bmad-build-auto's machine state; the review verdict lives in sprint-status.
- (low) Gap 3: registry row order across groups is unpinned -- not observable by a user or the panel; this review checked the diff: rows are byte-identical but for the appended `group:`.
- (false) Gap other: six assertions that "cannot fail on their own" -- each sits beside a pinning assertion that has a recorded mutation; redundancy is not unfalsifiability.
- (false) Gap other: AC sub-bullets with no mutation line -- Rule 19 asks one demonstrated mutation per AC; AC1-AC4 each have one.
- (false) Blind 7, Auditor 5: AC2 and AC3 shown red at e2e only together -- each has a single-change mutation too (AC3: the flat `items()` template, K4; AC1/AC2: QA's `rejectFix` move, K25/K2; AC2: this review's `MORE_TO_TRY_GROUPS` swap, K25).
- (false) Auditor 2: the comment sentence sits after line 55, not 56 -- lines 33-55 and 58 are byte-identical and `git merge-tree` against feature shows no conflict in the doc comment.
- (reject: fix edits the spec) Blind 4 and 5: the Auto Run Result's fallback wording and one triage-log reason.

## Spec Change Log

- 2026-11-10 ~15:05Z (lead): the host crashed at ~11:29Z with implement pass 4 being spawned; it left no edit (worktree byte-identical to the orchestrator's snapshot `refs/recovery/crash-20261110-epic-0`). The lead re-read the uncommitted diff against this spec and both rulings, and re-ran the unit level on the preserved tree (82 unit tests, 1780 web tests, lint, build, test-boundaries: all pass). Orchestrator: host hold and stack cap lifted, lane C first in the stagger: the local e2e tier is tried first (the three e2e `[Infra]` items re-opened); fallback (a) still applies if a start fails. Re-dispatched (pass 5).

- 2026-11-10 ~09:52Z (lead): implement pass 3 (quiet window) blocked again on the host (bake stalled ~19 min, Docker daemon unresponsive, load 170-260; no test ran). The Planner's pre-ruled fallback (a) applies: the e2e tier is carried by CI's `browser` group (marked amendment under `## Verification`); the e2e-level mutations move to QA on a lane-C throwaway; implement finalizes on unit green. Re-dispatched (pass 4): `ci/checks.sh`, the review layers and the finalize commit only.

- 2026-11-10 ~09:20Z (lead): implement pass 2 blocked again on host Docker contention (no test ran); reported as TOOLING. Orchestrator ruling (option 1): a quiet window on the Docker host (lanes A and B start no new bake or fresh stack; marker `<coordination>/locks/host-quiet-0.22`). Re-dispatched (pass 3) for the `[Infra]` items only; if the first start fails again (400 s timeout or a stuck bake), no retry: HALT for TOOLING.

- 2026-11-10 ~08:25Z (lead): implement pass 1 halted `blocked` on host infrastructure, not the code (two lane-C throwaway starts failed: a 1027 s image-layer export, then a 400 s first-start timeout at load average ~262; the orchestrator also killed a hung `docker buildx bake` from this stage at ~08:1xZ and confirmed Docker builds work again). Classified infra (U5: fixed, never answered). Re-dispatched with status `in-progress` to work ONLY the `[Infra]` open items; the written code and tests stay as they are.

- 2026-11-10 (lead, spec gate): two Contest Planner rulings relayed by the orchestrator during planning, applied: (1) ~06:40Z, EXPERIENCE.md's More to try entries renumbered by group (scope added: Boundaries, Code Map, Tasks, Acceptance, Public text, `### EXPERIENCE renumbering`, the `sources-docs.test.mjs` panel-order test, one mutation); (2) ~07:00Z, Story 37.2's `usage` joins "Safety and settings" last, no fourth heading, and no test pins a group size as a literal (Boundaries, Decided in-stage). The renumbered text and the marked line go to the Planner as PUBLIC TEXT before the implement stage.
- 2026-11-10 ~07:45Z (lead): Contest Planner ruling (owner's delegated authority, `prompts/epic-0-rulings-022.md` in the coordination folder): PUBLIC TEXT OK, implement may start. (1) The marked line is approved verbatim. (2) The renumbering is approved as proposed (old 1->5, 2->6, 3->1, 4->7, 5->2, 6->3, 7->8, 8->4; every number in the renumbered lines 254/255 checked). (3) No other strings, headings as `h4`, no `tabindex`: OK. Clarification: the ruled group lists fix membership only; within each group the panel keeps REGISTRY order ("Safety and settings" shows persona, suspiciousEmail, demoView, heartbeat, then 37.2's usage). Registry rows are never reordered. Merge instruction (orchestrator): if 23.6's `incidentSummary` (or 23.2's `reroute`) is on feature without a `group:` at this story's integrate-forward, the lead adds `group: 'Incidents and fixes'` to it (ruled text, not new).

## Review Triage Log

### 2026-11-10 — Review pass (implement pass 5)
- verdicts: 25 findings reported, logged in 20 rows (duplicates across layers share a row) — rows: high 0, medium 1, low 14, false 5, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind 1 and Edge 4: the registry caption and header say "in the order the panel shows them" while panel order is by group -- decided in-stage (Design Notes: line 94 and header lines 1-12 stay byte-identical for union merges; the new contract is in the new comments).
  - `[low]` `[reject]` Blind 2, Edge 5: item numbers in code comments and e2e titles count in registry order -- lead decision at the spec gate (Design Notes), not public text; only EXPERIENCE follows the groups.
  - `[low]` `[reject]` Blind 3: EXPERIENCE line 244 still says "with a list inside" -- the spec's Boundaries allow exactly the marked line and the renumbering and no other EXPERIENCE text change (approved public text); closed by-design.
  - `[false]` `[reject]` Blind 4: DESIGN.md not updated for `.set-heading` -- the heading reuses the existing tokens (Design Notes: memory-card recipe); the spec scopes no DESIGN change.
  - `[false]` `[reject]` Blind 5, Intent 3: room logic ignores heading height -- the room measures `.group`'s whole height (content-agnostic) and K16, K17 and K23 passed at 1280x650, 1280x600 and the drawer sizes with two headings; a taller first control row scrolls inside the panel's own window and Tab brings each control in view (K16/K17 green).
  - `[false]` `[reject]` Blind 6: `h4` level is arbitrary -- ruled in Design Notes (outline h1/h2/h3, then h4 as in the Memory card) and pinned by K25, K2 and the source pin.
  - `[low]` `[reject]` Blind 7: lists not tied to headings by aria-labelledby -- the spec's Never list forbids any other assistive string and the headings are not asked to label lists.
  - `[low]` `[reject]` Blind 8: group names written twice, no type-level link -- the typo-guard unit test fails on any registry group missing from `MORE_TO_TRY_GROUPS`; a type change is not worth its complexity.
  - `[medium]` `[patch]` Blind 9 and Gap 1: the `@if (set.heading)` guard, which keeps an ungrouped set from rendering an empty h4, was pinned by no test -- patched: one `assert.match` for the guarded h4 in `more-to-try-sources.test.mjs`, with its mutation line.
  - `[false]` `[reject]` Blind 10: sources-docs test fragile (four-space indent) -- the indent is the document's own list format; the old extra-item guard is replaced by the label-list comparison, which catches extras.
  - `[low]` `[reject]` Edge 1: K25's `RULED_GROUPS` membership omits a later story's item -- spec-bound: K25's oracle is the ruled strings written out; a later story's merge adds its id (the same as ITEMS in K3).
  - `[low]` `[reject]` Edge 2: framed `.items { padding-block-end }` repeats for each list -- the rule is pinned by the existing test and the spec; the gutter only adds a small space between groups, K16/K17 are green; not a two-way door worth the change.
  - `[low]` `[reject]` Edge 3: a group name differing by surrounding whitespace becomes a second heading -- theoretical: registry data is authored, the typo guard compares exact strings.
  - `[low]` `[patch]` Edge 6, Intent 1: the module-header bullet was inserted after old line 10, inside the 1-12 block the spec keeps untouched -- patched: moved to after the itemsFor bullet (after old line 12); no pin reads it.
  - `[false]` `[reject]` Edge 7, Intent 2: K2's `toHaveCount(2)` pins a literal group count -- the spec prescribes K2's two headings for `FOUR` (Tasks); it is the heading count of one routed input, not a group count of the registry.
  - `[low]` `[reject]` Gap other 1: AC2 and AC3 e2e mutations were applied together -- each red is attributable (K25/K2 only by h3, K16 only by overflow); unit-level single mutations exist.
  - `[low]` `[reject]` Gap other 2: AC1 mutations are red at the unit tier only -- K25, K2, K4, K16 each shown red at e2e level as the fallback ruling names; closed.
  - `[low]` `[reject]` Gap other 3: K1, K3, K4 expected values derive from `groupsOf` -- K25 (ruled strings) and the unit tests are the independent oracles.
  - `[low]` `[reject]` Gap other 4: AMENDED wording and the CI-browser-group condition are untested -- process item, not code; the e2e tier ran locally.
  - `[low]` `[reject]` Blind 9 residual, Intent 4: the ungrouped path has no e2e rendering -- no registry item is ungrouped; unit test plus the new source pin cover it.

## Design Notes

### Public text for the gate

**APPROVED 2026-11-10 ~07:45Z by the Contest Planner (owner's delegated authority), in full: the marked line verbatim, the renumbering as proposed, `h4` headings with no `tabindex`, no other strings. Commit both exactly as written below.**

- The three headings are ruled verbatim (no gate).
- One new string is the EXPERIENCE.md marked line, placed right after the renumbered section (before `  - Every control is a native button or link`). The line is indented two spaces:

  `  - The panel shows its items under three headings, in this order: "Incidents and fixes", "Memory and documents" and "Safety and settings", each with its items as listed above. A heading whose items are all absent does not show. [ADDED 2026-11-10, Story 0.22, More to try capacity ruling option (a), Contest Planner under the owner's delegation]`
  (Lead edit at the spec gate: the plan's wording "Under each heading the items keep the order above" no longer fit once the list above is itself grouped by the renumbering ruling.)
- The renumbering (Planner ruling ~06:40Z): the text under `### EXPERIENCE renumbering` below -- the three `    - Heading "<group>".` entries, the first carrying the marker, the renumbered `Item n.` prefixes, and the two renumbered lines after the list, each with a short marker. Sent to the Planner at the spec gate (PUBLIC TEXT).
- Nothing else. No `aria-label`, no fallback label, and no new UI string: each heading's accessible name is its own text, and the ungrouped set has no heading. Test titles and messages are not shown to users.

### EXPERIENCE renumbering

Replaces EXPERIENCE.md lines 246-255 (the eight item entries and the two lines that cite item numbers). Item texts after `Item n. ` are byte-identical to today's. Old to new numbers: 1 to 5, 2 to 6, 3 to 1, 4 to 7, 5 to 2, 6 to 3, 7 to 8, 8 to 4. The quoted earlier text inside the 20.3 marker (`It read: "Items 6 and 8's controls ..."`) is history and stays as it is.

```text
    - Heading "Incidents and fixes". [AMENDED 2026-11-10, Contest Planner ruling: the items are listed and numbered by group, in the order the panel shows them; Items 1 to 8 were, in order, the items now numbered 5, 6, 1, 7, 2, 3, 8 and 4]
    - Item 1. Label "Reject a fix". Look for: "This presses Break the feed again. OcuTalon usually notices within a minute. When the fix waits for your approval, press Reject in the chat or on the Simulated phone, and look for "Nothing was changed."" Control: "Break it again".
    - Heading "Memory and documents".
    - Item 2. Label "Ask it to remember something". Look for: "This sends "Remember that the Results partner's contact is Lee." Later, ask "Who do I call about Results?" and look for the answer it remembered." Control: "Ask it to remember".
    - Item 3. Label "Ask about a document". Look for: "On the Documents page, press Add the sample runbook, or add a short file of your own (nothing personal: Visual Trace on the demo is shared). When it reads Ready, ask in the chat "According to the runbook, what should I do when partner orders fail with a date error?", or ask about your own file, and look for the chip under the answer that names the document and its section." Control: "Open the Documents page". [AMENDED 2026-11-08, Story 4.12, Contest Planner ruling under the owner's delegation (guide_documents_citation_promise): the web chat shows no citations in 1.0.4 (Story 20.2), and the earlier line promised a citation; Story 20.2 restores a citation line when it ships] [AMENDED 2026-11-09, Story 20.2, Planner ruling planner-2026-11-09-20.2 (public text 9). It read: "On the Documents page, add a short file, such as a runbook (nothing personal: Visual Trace on the demo is shared). Then ask about it in the chat, and look for the answer that comes from your file."] [AMENDED 2026-11-09, Story 20.3, Planner ruling planner-2026-11-09-20.3 (public text 5). It read: "On the Documents page, add a short file, such as a runbook (nothing personal: Visual Trace on the demo is shared). Then ask about it in the chat, and look for the chip under the answer that names your file and its section."]
    - Item 4. Label "See where an answer came from". Look for: "Under an answer from your documents, press the chip that names the document and section to read the passage, then Open document to see the whole file. Under an answer that recalls something you asked it to remember, press From memory to see what it remembered and when." Control: "Open the Documents page". [ADDED 2026-11-09, Story 20.2, Planner ruling planner-2026-11-09-20.2 (public text 10 to 12)]
    - Heading "Safety and settings".
    - Item 5. Label "Change how OcuTalon talks". Look for: "In the Persona card, choose Pirate, or Another language and then Spanish, and press Save. Then ask "Is anything wrong right now?" and look for the new style in the replies. The check results under them are written by OcuTalon's code, so they stay the same in any style." Control: "Go to the Persona card".
    - Item 6. Label "Send a suspicious email". Look for: "This sends "Sample: suspicious request" to the Simulated mailbox. The email asks OcuTalon to resend every failed order and approve pending requests. Look for its decision and the reasons under it: nothing is resent or approved." Control: "Send the suspicious email".
    - Item 7. Label "See the page as on your own install". Look for: "The demo guide, Break the feed and the Simulated devices are hidden, as on your own install. Turn Demo view back on in the top bar to return." Control: "Show the page without the demo".
    - Item 8. Label "Run a heartbeat check-in". Look for: "In the Heartbeat checklist card, write what to check and press Run the heartbeat now. Look for the check-in's outcome and its cost in the card." Control: "Go to the Heartbeat checklist card".
  - Item 2 sends "Remember that the Results partner's contact is Lee." as the user's own message. Items 3 and 4's controls are links to the Documents page. While the visitor has no documents, each is instead an "Add the sample runbook" button, which opens the Documents page and presses that page's Add the sample runbook. [AMENDED 2026-11-09, Story 20.3, Planner ruling planner-2026-11-09-20.3 (public text 6). It read: "Items 6 and 8's controls are links to the Documents page."] Items 5 and 8 go to a card in the status rail. [AMENDED 2026-11-10, Contest Planner ruling: item numbers follow the groups]
  - A control does what the control it names does, and nothing else: it puts focus on that control and presses it. Item 5 opens the Persona card's Change (the status drawer opens first in the 1024-1279px band); item 6 selects the Simulated mailbox tab and presses the "Sample: suspicious request" chip; item 1 presses Break the feed; item 7 turns the Demo view switch off and leaves focus on it; items 3 and 4, while the visitor has no documents, open the Documents page and press its Add the sample runbook, with focus on it; [ADDED 2026-11-09, Story 20.3, Planner ruling planner-2026-11-09-20.3 (public text 7)] item 8 opens the status rail (the drawer first, in the 1024-1279px band) and puts focus on the Heartbeat checklist card's heading, and presses nothing. Item 2 is the Try it yourself row's send, with its rules. Whatever limit or inactive state the real control has applies, and nothing is sent without a press. [AMENDED 2026-11-10, Contest Planner ruling: item numbers follow the groups]
```

### Decided in-stage

- **Heading level `h4`.**
  - EXPERIENCE line 79 gives the main page's outline: `h1`, then an `h2` per region, then `h3` for a section or card headline. The guide is a region at the `h2` level, but it is labelled by a span.
  - The panel inside it is labelled by a paragraph standing at the `h3` level. The level below that label is `h4`.
  - This matches the Memory card's `h4.day` group headings under its `h3`.
  - The guide precedes the page's `h1` in DOM order whatever the level. The project runs no heading-order audit.
  - Pinned by K25, K2 (`level: 4`) and the source pin.
- **Ungrouped items come first, with no heading.** An un-headed item placed after the last group would read, by sight and in screen-reader heading navigation, as part of "Safety and settings". Placed first, it is visibly outside every group. The typo-guard unit test makes the fallback a defensive render only: a story that forgets `group:` turns its own tests red at integrate-forward. So with correct data, 23.6's item stays first overall.
- **Unknown groups:** they render after the ordered groups, in order of first appearance. A fourth group, if one is ever ruled, adds one entry to `MORE_TO_TRY_GROUPS` and its row. That is data only. (37.2's `usage` is ruled into "Safety and settings" as its last item, with no fourth heading.) The registry test requires every group to be in the constant, so a typo cannot publish a stray heading.
- **Blank group:** an empty or whitespace-only group counts as no group, so an empty `h4` can never render.
- **Structure:** one `ul.items` per set, each a direct child of `.group`. The heading style follows the memory-card recipe.
- **Item numbers in code comments** (`more-to-try.ts` lines 38 and 58, `web/e2e-online/demo-path/demo-path.spec.ts:236`) count in registry order and stay as they are (lead decision at the spec gate, 2026-11-10: they are not public text, lines 33-58 are union-sensitive, and registry order is unchanged); only EXPERIENCE.md's numbers follow the groups.
- **Comments left as they are, for union-friendly merges:** the module header lines 1-12, line 94 and the component comment lines 33-58. Line 94's "in the order the panel shows them" still holds within a group. The new contract is written in new comments: the `groupsOf` doc, a new header bullet, and the sentence after line 56.

### Constraints and links

- **Governing ADs:**
  - AD-12: the page decides nothing about which items exist. `groupsOf` only orders what `itemsFor` gives.
  - AD-29: Epic 0 may edit any lane's files.
  - The spine's Angular convention: signals, standalone components, and styles from DESIGN tokens.
  - No AC contradicts an AD.
- **Integration ACs:** `more-to-try.ts` consumes `groupsOf` (K25, K2).
  - **Consumed-by:**
    - Stories 23.6, 23.2 and 23.5 (Incidents and fixes) and 41.13 (`memoryCard`, Memory and documents) declare `group:` on their own items. Their items then render under the headings.
    - Story 37.2 may add a fourth group: one constant entry, plus its row, the EXPERIENCE line and `SOURCES.ux`.
  - **Consumes:**
    - Story 20.3's `group?` field.
    - Story 4.11's panel and room logic.
    - The server's `guide.features`.
- **Extend, don't copy:** `groupsOf` composes on `itemsFor`'s output and does not re-filter features. The component keeps its single `items` input. The `.set-heading` CSS repeats the memory-card `.day` values (five declarations). Component styles are encapsulated, and the project has no shared heading class, so a copy is simpler than a new global style.
- **How the in-flight rows combine** (checked on `origin/OCT-epic23` b99d6529 and `origin/OCT-epic41` 28229232):
  - Their new rows (`incidentSummary` before `persona`, `memoryCard` between `memory` and `documents`) sit next to rows this story edits. Git reports an adjacent-lines conflict there. The resolution is to keep both: their row plus this story's `group:` fields.
  - `origin/OCT-epic23`'s `incidentSummary` row declares no `group:` yet. Under this story's typo guard, 23.6's integrate-forward stays red until it adds `group: 'Incidents and fixes'`, which the ruling requires anyway. This is flagged for the orchestrator.
  - `GROUP_OF` holds one key per line, so 41.13's `memoryCard` key is a one-line addition.
- **Ledger inbox:** none.

## Verification

`$LANE` stands for these variables on every `ci/iris.sh` / `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=0 stage=<stage>'`.

- Run tags are `e0s22<stage letter>`: implement `e0s22i`, QA `e0s22q`, review `e0s22r`.
- No IRIS class changes, so no warm stack is needed.
- Throwaway stacks only. The dev slot is `ocutalon-slot-c` (MCP profile `ocutalon-slot-c`, namespace `OCUTALON`), and it is not needed here. Never use another instance.
- Run one command per tool call, sized to about 150 s. The part that holds `more-to-try.spec.ts` (a file stays whole) may run longer: about 93 s of stack setup plus the file's run (inference). If the harness moves it to the background, wait in bounded foreground polls before doing anything else.

Shared surfaces:
- The More to try registry (`MORE_TO_TRY_ITEMS` `group:` fields, plus the new `MORE_TO_TRY_GROUPS` and `groupsOf`).
- The panel's rendered DOM: `h4` headings inside the guide region while the panel is open, several `ul.items` instead of one, and the shown order.
- The panel's focus order.
- EXPERIENCE.md's More to try lines (renumbered by group with three heading entries, one marked line added; the count and item texts are unchanged), and README's count (unchanged).
- Tests that move with these surfaces:
  - `more-to-try-view.test.mjs` (`GROUP_OF`, the group test);
  - `more-to-try-sources.test.mjs` (the no-heading pin);
  - `ux-strings.test.mjs` (`IMPORTED`, `SOURCES.ux`);
  - `sources-docs.test.mjs` (the new line check);
  - `more-to-try.spec.ts`: K1-K4, `measureRoom`, `expectRoom`, `expectTabInView` and the new K25.
- Unchanged readers, checked: `guide.spec.ts` Q1 (131, 201), `more-to-try-sample.spec.ts`, `floor/guide.spec.ts`, `try-it.spec.ts`.
- Standing criterion: every test added or changed passes on a fresh environment, in either order.

**[AMENDED 2026-11-10, Contest Planner fallback ruling (a), owner's delegated authority, `prompts/epic-0-rulings-022-fallback.md` in the coordination folder]** The e2e tier (`sign-in-3` parts 1/9 and 2/9: `more-to-try.spec.ts` K1-K25, `guide.spec.ts`, `more-to-try-sample.spec.ts`) was carried by CI because of host contention: three implement passes could not start a lane-C throwaway on the shared Docker host (load 100-260; image bakes stalled; 400 s first-start timeouts; no test ran). CI's iris jobs run on the separate Linux runners, so its `browser` group is a clean e2e tier. Conditions: (1) implement finalizes on unit green (the unit, lint, build, `test-boundaries.sh` and `ci/checks.sh` lines below); (2) the e2e-level mutations (K25, K2, K4, K16) are demonstrated on a lane-C throwaway at QA at the latest, before PART READY, and reported (never skipped) if the host still cannot start a stack; (3) no part merge until CI's `browser` group is green on the code head.

**Commands:**
- (loop) `node --test web/scripts/more-to-try-view.test.mjs web/scripts/more-to-try-sources.test.mjs web/scripts/sources-docs.test.mjs web/scripts/ux-strings.test.mjs` -- all pass (about 11 s, measured on the baseline: 71 tests).
- (loop) `bash docker/tests/test-boundaries.sh` -- `test-boundaries: all rules passed`.
- (loop) The e2e:
  1. After web changes, build once: `$LANE OCUTALON_RUN_TAG=e0s22i ci/iris.sh build`.
  2. List the project: `npm --silent --prefix web run e2e:sign-in-3 -- --list --reporter=json > "$SCRATCH/sign-in-3.json"`, where `$SCRATCH` is a folder of the session scratchpad.
  3. Pick the part: `node web/scripts/e2e-part.mjs k/n "$SCRATCH/sign-in-3.json"`. Choose an n (for example 12), and the k that holds `e2e/guide/more-to-try.spec.ts`.
  4. Run it: `$LANE OCUTALON_RUN_TAG=e0s22i ci/iris.sh live sign-in-3 --part k/n` -- the part passes.
  5. Repeat steps 3 and 4 for the part that holds `e2e/guide/guide.spec.ts`, if it is a different part.
  6. Tear down: `$LANE OCUTALON_RUN_TAG=e0s22i ci/iris.sh teardown`.
- (once) Run `npm --prefix web test`, `npm --prefix web run lint` and `npm --prefix web run build`, one per call -- each passes.
- (once) `bash ci/checks.sh`, in batches of its `CHECK_SCRIPTS` if one call cannot hold it -- every block passes.
- `live:floor` takes no `--part`, and its panel assertion is order-free and heading-free, so CI covers it.

**Mutations to record (Rule 19), one per AC, each observed red and reverted byte-identical:**
- `rejectFix`'s group set to "Safety and settings" -> `more-to-try-view.test.mjs` group test red, and K2 red (K25 takes membership from the registry).
- Two entries of `MORE_TO_TRY_GROUPS` swapped -> the ruled-order unit test and K25 red.
- The `h4` changed to `h3`, or the heading dropped -> K25 and K2 red, and the source pin red.
- `groupsOf` keeping empty groups as headed sets -> the suppression unit test red, and K2 red.
- `groupsOf` dropping ungrouped items, or putting them last -> the fallback unit test red.
- The template iterating `items()` in place of `groups()` -> K4 (Tab order), K1 and K3 red.
- In framed mode `.group { overflow-y: hidden }` -> K16 at 1280x650 and 1280x600 red (Tab not in view).
- Two groups swapped in the EXPERIENCE line -> `sources-docs.test.mjs` red. A heading missing from EXPERIENCE -> `ux-strings.test.mjs` red.
- Two item entries swapped in EXPERIENCE's renumbered list (or an entry moved under the wrong heading entry) -> the panel-order test in `sources-docs.test.mjs` red.

Quiet-window marker `host-quiet-0.22` deleted 2026-11-10 09:50:59Z (pass 3 halted blocked, TOOLING).

mutation: AC1 (`rejectFix` in the wrong group): `group: 'Incidents and fixes'` of the `rejectFix` row changed to `'Safety and settings'` in `more-to-try-view.ts`, observed red in `more-to-try-view.test.mjs`: `give every entry its ruled group`, `gives the whole registry under the headings in order, and each group in registry order` and `leaves out a group with no item, and gives nothing for no items`; restored from the scratch copy, byte-identical, `git diff --stat` identical. K25 (e2e) not run here, for the parent.
mutation: AC1 (two entries of `MORE_TO_TRY_GROUPS` swapped): the first two entries swapped, observed red: `holds the ruled headings, in the ruled order` and `keeps an Incidents and fixes item that comes first in the input first overall`; restored, byte-identical. K25 (e2e) not run here, for the parent.
mutation: AC2 (`h4` to `h3`, and the heading dropped): in the template of `more-to-try.ts`, `<h4 class="set-heading">` changed to `<h3 ...>`, and separately the heading line removed, each observed red in `more-to-try-sources.test.mjs` (`names no aria-label and no icon, and its only heading is the group heading, which takes no focus`); restored, byte-identical. K25 and K2 (e2e) not run here, for the parent.
mutation: AC2 (`groupsOf` keeping empty groups as headed sets): the `if (set !== undefined)` guard replaced by `?? []` and an unconditional push, observed red in `more-to-try-view.test.mjs`: `leaves out a group with no item, and gives nothing for no items`, `puts the items with no group, or a blank one, first and with no heading` and `puts a group the constant does not hold after the ordered groups, in order of first appearance`; restored, byte-identical. K2 (e2e) not run here, for the parent.
mutation: AC2 (`groupsOf` dropping ungrouped items, and putting them last): the ungrouped set dropped, and separately appended after the last set, each observed red: `puts the items with no group, or a blank one, first and with no heading`; restored, byte-identical.
mutation: AC2/AC3 (the template iterating the flat `items()`): the `@for (set of groups(); ...)` header replaced by a single set over `items()`, observed red in `more-to-try-sources.test.mjs`: `holds none of the heading strings, and iterates the sets that groupsOf gives`; restored, byte-identical. K4, K1 and K3 (e2e) not run here, for the parent.
mutation: AC3 (framed `.group { overflow-y: hidden }`): `overflow-y: auto` changed to `hidden` in `more-to-try.ts`, observed red in `more-to-try-sources.test.mjs` (`is bounded where the page fills the viewport: its own vertical scroll, ...`); restored, byte-identical. K16 at 1280x650 and 1280x600 (e2e) not run here, for the parent.
mutation: AC4 (two groups swapped in the EXPERIENCE line): `"Incidents and fixes", "Memory and documents" and` changed to `"Memory and documents", "Incidents and fixes" and`, observed red in `sources-docs.test.mjs`: `has exactly one line for the headings, naming each in order with its count word (Story 0.22)`; restored, byte-identical.
mutation: AC4 (a heading missing from EXPERIENCE): every `Memory and documents` in EXPERIENCE.md renamed, observed red in `ux-strings.test.mjs`: `finds each ux and design string in its document` (`"Memory and documents" is not in EXPERIENCE.md`); restored, byte-identical.
mutation: AC4 (renumbered list out of order): the `Heading "Memory and documents"` entry moved below Item 2 in EXPERIENCE.md, observed red in `sources-docs.test.mjs`: `lists the headings of the panel, each followed by exactly its group's items`; with a heading entry removed instead, the same test is red; with an item entry's label changed, `lists the registry's items in the panel's order, and no item past them` is red too; restored, byte-identical.

e2e tier (pass 5, 2026-11-10, lane-C throwaway, run tag e0s22i; the first start succeeded, so fallback (a) was not used and these results are binding): `ci/iris.sh live sign-in-3 --part 2/9` 97 passed (K1-K4, K16/K17, K22-K25 included), 15:05:49Z-15:09:05Z; `--part 1/9` 26 passed (guide.spec.ts, more-to-try-sample.spec.ts), 15:09:10Z-15:13:14Z. `bash ci/checks.sh`: all 32 CHECK_SCRIPTS blocks passed, `checks: all scripts passed`. Each stack was torn down; the lane-C lock folder was empty afterwards.

mutation: AC2 (`h4` to `h3`) and AC3 (framed `.group { overflow-y: hidden }`) applied together in `more-to-try.ts`, `ci/iris.sh live sign-in-3 --part 2/9` observed red (38 failed, 59 passed): K25, K2 and K16 at 1280x650 and 1280x600 (and every other framed K16/K16b size); restored from the scratch copy, `shasum` and `git diff --stat` identical.
mutation: AC2/AC3 (the template iterating the flat `items()` as one headed-less set in place of `groups()`): observed red in the same part: K1, K2, K3, K4, K25 and K16/K17 sizes; restored from the scratch copy, `shasum` and `git diff --stat` identical.
mutation: AC2 (the `@if (set.heading)` guard of the heading): in `more-to-try.ts`, `@if (set.heading) {` replaced by `@if (true) {`, observed red in `more-to-try-sources.test.mjs` (`names no aria-label and no icon, and its only heading is the group heading, which takes no focus`); restored from the scratch copy, `shasum` identical.

QA stage (2026-11-10, lane-C throwaway, run tag e0s22q; audit found no AC or matrix row without a pinning test and no assertion that cannot fail, so no test file was added (QA)): the four unit files 82 passed (34, 20, 15, 13); `ci/iris.sh live sign-in-3 --part 2/9` 97 passed (15:59Z-16:03Z) and `--part 1/9` 26 passed (16:03Z-16:06Z); stacks torn down, lane-C lock folder empty.

mutation: AC1 (`rejectFix` in the wrong group, at e2e) (QA): `group: 'Incidents and fixes'` of the `rejectFix` row changed to `'Safety and settings'`, web rebuilt, `ci/iris.sh live sign-in-3 --part 2/9` observed red (2 failed, 95 passed): K25 and K2 (before the review took K25's membership from the registry; re-run below); restored from the scratch copy, `shasum` and `git diff --stat` identical, web rebuilt from the restored tree.
mutation: AC2 (items of a group no longer in registry order) (QA): `set.push(item)` changed to `set.unshift(item)` in `groupsOf`, observed red in `more-to-try-view.test.mjs`: `gives the whole registry under the headings in order, and each group in registry order`, `puts a group the constant does not hold after the ordered groups, in order of first appearance` and `keeps an Incidents and fixes item that comes first in the input first overall`; restored, `shasum` and `git diff --stat` identical.
mutation: AC2 (groups the constant does not hold sorted instead of in first-appearance order) (QA): `.sort()` appended to the `others` filter in `groupsOf`, observed red in `more-to-try-view.test.mjs`: `puts a group the constant does not hold after the ordered groups, in order of first appearance`; restored, `shasum` and `git diff --stat` identical.

Code review stage (2026-11-10, lane-C throwaway, run tag e0s22r): after the review patches, the four unit files 82 passed, `npm --prefix web test` 1780 passed, lint passes; `ci/iris.sh live sign-in-3 --part 2/9` 97 passed (to 16:25Z, K25 as re-expressed and K2 included); stacks torn down, lane-C lock folder empty.

mutation: AC2 (two entries of `MORE_TO_TRY_GROUPS` swapped, at e2e, with K25's membership from the registry) (code review): the first two entries swapped in `more-to-try-view.ts`, web rebuilt, `ci/iris.sh live sign-in-3 --part 2/9` observed red (1 failed, 96 passed): K25 (`the page's constant is the ruled order`); restored from the scratch copy, `shasum`, `git status --short` and `git diff --stat` identical, web rebuilt from the restored tree.
mutation: AC4 (EXPERIENCE entries numbered out of the panel's order, with numbers counted over the numbered entries) (code review): the numbers of Item 3 and Item 4 swapped in EXPERIENCE.md, entries left in place, observed red in `sources-docs.test.mjs`: `lists the registry's items in the panel's order, and no item past them`, both `The documents/sources entry is the registry's ...` and `marks the change to the documents item ...`; restored, byte-identical.
mutation: AC1 (`rejectFix` in the wrong group, at e2e, re-run after the K25 change) (code review): `group: 'Incidents and fixes'` of the `rejectFix` row changed to `'Safety and settings'`, web rebuilt, `ci/iris.sh live sign-in-3 --part 2/9` observed red (1 failed, 96 passed): K2 (its ruled headings for the four ids). K25 stays green by design: it takes membership from the registry (37.2 ruling), and the literal membership pin is the unit test `give every entry its ruled group`. Restored from the scratch copy, `shasum`, `git status --short` and `git diff --stat` identical, web rebuilt from the restored tree; teardown of e0s22r, lane-C lock folder empty.
mutation: AC2 (a second heading element with child markup in the template) (code review): `<h3><span>x</span></h3>` added after the label in `more-to-try.ts`, observed red in `more-to-try-sources.test.mjs`: `names no aria-label and no icon, and its only heading is the group heading, which takes no focus`; restored, byte-identical.
mutation: AC3 (the flattened sets out of the order shown) (code review): `groupsOf` walking `MORE_TO_TRY_GROUPS` in reverse, observed red in `more-to-try-view.test.mjs`, `gives every input item once, and the flattened sets are the focus order` among six; restored, byte-identical.

## Auto Run Result

Status: done
Blocking condition: none

Pass 5 (post-crash re-dispatch, covers this pass only). Summary: the written implementation is unchanged except two review patches. Registry rows carry their ruled `group:`; `MORE_TO_TRY_GROUPS` and `groupsOf` give the sets; the panel renders each group as an `h4` heading with its own `ul.items`; EXPERIENCE.md carries the approved renumbering and the marked line.

Files changed:
- `web/src/app/guide/more-to-try-view.ts`: `group:` per row, `MORE_TO_TRY_GROUPS`, `MoreToTryGroup`, `groupsOf`, one header bullet.
- `web/src/app/guide/more-to-try.ts`: `groups` computed, `h4.set-heading` per group, one list per set, one comment sentence.
- `web/scripts/more-to-try-view.test.mjs`, `more-to-try-sources.test.mjs`, `ux-strings.test.mjs`, `sources-docs.test.mjs`: pins moved and added (including the `@if (set.heading)` pin from this pass).
- `web/e2e/guide/more-to-try.spec.ts`: K1-K4, room helpers and Tab order follow the shown order; new K25.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md`: renumbering by group and the marked line (approved text).

Review: 4 layers, 25 findings. Patches applied: 2 (medium: the `@if (set.heading)` guard pin with its mutation line; low: the header bullet moved after old line 12). Deferred: none. Every rejected finding and its reason is in `## Review Triage Log`.

followup_pass: true (evaluated as a follow-up pass): this pass patched no `high`, so `followup_review_recommended` is false. Patched counts: high 0, medium 1, low 1.

Verification (pass 5, lane-C throwaway, tag e0s22i; the first start succeeded, so fallback (a) was not used and the e2e results are binding): e2e `sign-in-3` part 2/9 97 passed, part 1/9 26 passed; the e2e-level mutations (K25, K2, K4, K16) each red and reverted byte-identical; `bash ci/checks.sh` all 32 blocks passed; after the patches: the four unit files 82 passed, `npm --prefix web test` 1780 passed, lint, build and `test-boundaries.sh` pass. Stacks torn down; the lane-C lock folder was empty afterwards.

Residual risks: CI's `browser` group must still be green on the code head before the part merges (fallback condition 3); at integrate-forward, K25's `RULED_GROUPS` and the `ITEMS` oracle need one line per item that 23.6, 23.2, 23.5, 41.13 and 37.2 add (with `group:` per the rulings). The implementation-handoff subagent was not spawned this pass: the lead's re-dispatch ordered only the `[Infra]` items on the existing tree.
