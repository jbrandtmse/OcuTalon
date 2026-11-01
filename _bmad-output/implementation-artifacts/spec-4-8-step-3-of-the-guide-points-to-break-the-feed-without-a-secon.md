---
title: 'Story 4.8: Step 3 of the guide points to Break the feed without a second button'
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_revision: '0ca9d869348741fcc47411f71e5a6721102ca0b9'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      No test pins the negative cell of matrix row 4 (the prompt bar comes back at step 1 or 2 after Run again: focus goes to Send, not the box button).
    evidence: |-
      FOCUS_RULE.whenGone hands focus to the box only when the bar carries data-guide-step="3". M6, M10 and M12 all end at step 3, so a mutation that ignores the mark (find('bar') !== null) may survive; existing floor cases that lose a prompt part at other steps might already catch it. Unverified.
    location: >-
      web/src/app/guide/demo-guide.ts (FOCUS_RULE.whenGone), web/e2e/floor/guide.spec.ts
    severity: medium (unverified)

---

<intent-contract>

## Intent

**Problem:** On step 3 the guide's Next bar shows a primary "Go to Break the feed" button right beside the red Break the feed button in the box. The owner, after walking through the demo (2026-11-01), called it redundant: "The demo seems to work fine, but the green "Go to Break the feed" button is redundent when teh "Break the feed" red button is right next to it."

**Approach:**
- **Remove** the button completely: the `goToBreakFeed` member of `PromptAction` and of `GUIDE_TEXTS`, its `@case` in the template and the `goToBreakFeed()` handler. Step 3's prompt keeps its instruction line (and its waiting line) with action `none`.
- **Keep** the keyboard and screen-reader path the button gave. When step 3 becomes current by the user's own press (Send on step 2; Run again from the finish), the guide's existing focus rule hands focus to the box's Break the feed button. Nothing is pressed.
- **Update** the UX spec and the mockup, with markers, and rework the tests that pinned the button.

## Boundaries & Constraints

**Always:**
- **The page decides no progress (AD-12).** Step 3 comes from the server's view as today. The page only chooses what to render, and where focus goes when an update removes the focused element.
- **Focus moves only through `shared/focus-rule.ts`** (spine convention "Announcements and focus").
  - The hand-off to the box's button happens in the guide's `FOCUS_RULE.whenGone`, when an update removes the prompt bar part or the finish part that held focus and the prompt bar now shows step 3.
  - It adds no `.focus(` call to `demo-guide.ts`. `FOCUS_RULE` stays a module-level `const FOCUS_RULE: FocusRule = { item: …, keyOf, whenGone }` (announce-focus-sources pins this shape).
  - An inactive (`aria-disabled`) box button still takes focus. Nothing is ever pressed or posted (AD-1).
- **Unchanged:**
  - the instruction line "Press Break the feed. The partner will send 50 orders in a new date format.", in quotes after "Next:";
  - the waiting line "Waiting for OcuTalon. The reminder may arrive first.", with no "Next:", no quotes and no button;
  - the box's "Next step" tag and its 4px teal (`--action`) left bar;
  - every other step, the finish state, the announcements ("Step 3 of 5: Break the feed" once per advance; Run again silent) and the other hand-offs (Hide/Show, Do step 1, finish).
- **Texts.** The story adds no public string. It only removes "Go to Break the feed".
- **Floor rules:** no `transition`, fixed height, `sticky` or `IntersectionObserver`; width queries only through `LAYOUT_QUERIES`.

**Never:**
- **Files outside the footprint** (Rule 11, the orchestrator's ruling). This story may edit only:
  - `web/src/app/guide/*`;
  - `web/e2e/floor/guide.spec.ts` and `web/e2e/guide/guide.spec.ts`;
  - `web/e2e/demo-path/01-page.spec.ts`, its step 3 coverage only;
  - `web/scripts/announce-focus-sources.test.mjs`;
  - in `web/scripts/guide-view.test.mjs`, only L47 and L229-231;
  - in `web/scripts/ux-strings.test.mjs`, only the removal of the 'Go to Break the feed' entry (L345);
  - `EXPERIENCE.md` and `mockups/states.html`.

  These are never edited: `web/src/app/feed/**` (the box), `web/e2e/demo-path/0[2-6]-*`, `web/e2e/support/*`, `web/e2e-online/*`, `web/src/app/api/api-types.ts`, `web/src/app/live/live-store.ts`, `web/src/app/rail/telegram-card/**`, `DESIGN.md`, any server class and `ci/mock/**`. Anything else needed is an escalation.
- **No focus move without the user's own press.** A first load, a reload, a poll or event while focus is elsewhere (the composer, the body) never moves focus to the box. A user's click on the step 3 step button doesn't either: it keeps focus.
- **No new test case and no new spec file.** M7 and M12 are reworked, not deleted.

## I/O & Edge-Case Matrix

`V` is the server's guide view. "Box button" is `app-break-feed-box app-server-button button`.

| # | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| 1 | Step 3 selected, `breakFeed.stage` not sending/waiting/still_waiting | **Prompt bar:** "Next:", the quoted instruction line, and no button and no link. `promptOf(3)` = {text, quoted, action `'none'`}.<br>**Box:** "Next step" tag and teal left bar, as today | none |
| 2 | Step 3 selected, stage sending/waiting/still_waiting | The waiting line only (unchanged) | none |
| 3 | Focus on step 2's Send; `V` advances to step 3 | Focus moves to the box button. No POST to `/demo/break-feed`. "Step 3 of 5: Break the feed" is announced once | **Box inactive** (`aria-disabled`): it still takes focus and stays inactive |
| 4 | Focus on Run again; the 200 answer (or the live view) brings back the prompt bar at step 3 | Focus moves to the box button. Silent. No POST to `/demo/break-feed` | **The prompt bar comes back at step 1 or 2** (watch or reminder gone): focus goes to its Send, as today |
| 5 | `V` reaches step 3 while focus is in the composer, on the body, or on a step button; or the page loads at step 3 | Focus stays where it is (the body stays the body) | none |
| 6 | Focus on step 1's Send; `V` jumps from 1 to 3 | Focus moves to the box button (the same hand-off: the user's Send) | none |

</intent-contract>

## Code Map

**Page (`web/src/app/guide/`):**
- `guide-view.ts`:
  - `:36` `GUIDE_TEXTS.goToBreakFeed`: delete it.
  - `:115-116` `PromptAction`: drop `'goToBreakFeed'` and fix the doc line.
  - `:172-176` `promptOf` case 3: `shown(GUIDE_TEXTS.promptBreakFeed, 'none')`.
  - `:11` the header line "step 3 sends the user to Break the feed or waits" stays accurate.
- `demo-guide.ts`:
  - `:30-31` `BREAK_FEED_BUTTON`, reused.
  - `:33-34` `PROMPT_KEYS`; `:36-38` `FINISH_KEY`/`FINISH_PARTS`.
  - `:47-68` `FOCUS_RULE`. `whenGone`'s `step1` branch already hands focus to `BREAK_FEED_BUTTON`. The prompt hand-off is `:65-66`: the action, else the text, else the bar; for finish parts the prompt, else the finish line.
  - `:168` the prompt bar `div.prompt` (`data-guide-focus="bar"`), which can carry the step-3 mark that `whenGone` reads (the model is `guide`; `guide.selected` is the shown step).
  - `:178-198` the `@switch`; `:189-191` the `@case ('goToBreakFeed')`: delete it.
  - `:70-96` the class doc: `:75` and `:95` name Go to Break the feed; restate them.
  - `:582-585` `goToBreakFeed()`: delete it.
  - `:544-558` the effects: `follow`, the clearing of the held answer, `keepFocus`. They are unchanged. `afterNextRender` stays (Show me).
- `web/src/app/shared/focus-rule.ts:53-92` `keepFocus` (read only). It records the focused item's key before the render. After the render, only if focus was lost, it focuses the same key or `whenGone(...)`, else `main.main`.
- `web/src/app/feed/break-feed-box.ts:37-42,75-77` and `break-feed-view.ts:146-190`: the host class `next-step`, the tag, `border-inline-start: 4px solid var(--action)`. Read only.

**Unit tests (`web/scripts/`, `node --test`):**
- `guide-view.test.mjs`:
  - `:47` delete the `goToBreakFeed:` line of the `GUIDE_TEXTS` deepEqual;
  - `:229` and `:231` change `action: 'goToBreakFeed'` to `action: 'none'`.

  Edit no other line: Epic 11 adds lines at L214-220.
- `announce-focus-sources.test.mjs:123` `FOCUS_CALLS['app/guide/demo-guide.ts']`: 2 becomes 1, with the reason "Show me focuses the phone's pending notification or its feed, for the user's own press (Story 4.7)". `:144` (`afterNextRender` list) and `:157` (the rule's shape) are unchanged.
- `ux-strings.test.mjs:345` delete `'Go to Break the feed',` (an entry that matches no inventory string fails "has no entry that matches no inventory string"). Edit nothing else: Epic 12 adds lines at L42 and L220.
- `allowance-sources.test.mjs:112` pins the Send button's markup. Leave it as it is.

**E2E:**
- `web/e2e/floor/guide.spec.ts` (`live floor`):
  - `:21-22` the header names M7 and M12 as Go to Break the feed: restate them.
  - `:61` `goOf`: delete it once unused. `:58` `boxOf`, `:57` `breakOf`, `:62` `promptText`.
  - **M3** `:178`, `:207`: `goOf` visible becomes "the prompt bar holds no button" (`.prompt` `getByRole('button')` count 0). `:204` (composer focus kept on 2→3) is AC4's pin.
  - **M6** `:223-247` (the step 2 to 3 case), `:237-243`: focus on Send, then the reminder lands. Assert focus on `breakOf(page)`, and collect POSTs: none to `/demo/break-feed`. Restate the title and doc to say the removed Send hands focus to the box's button.
  - **M7** `:344-392`: rework as described under Tasks.
  - **M10** `:600-645`, `:638`: `goOf` focused becomes `breakOf(page)` focused, and no `/demo/break-feed` POST. Restate the title and doc.
  - **M12** `:660-708`, the Go half `:689-701`: rework as described under Tasks.
  - **M13** `:775-778` asserts only the step 3 text after Run again. Unchanged.
  - Helpers in this file: `seedWatch :164`, `seedStretch :171`, `seedIncidentPath :333`, `seedFinishingRun :440`, `holdPolls :473`, `endRun :488`.
- `web/e2e/support/{guide,iris,page,floor}.ts`: helpers to call, never edit:
  - `startEpochAt` (`guide.ts:194`);
  - `seedIncident` with `noticedAt` (`iris.ts:953-982`);
  - `publishCheck`, `publishReminder`, `cleanFixtureRows`;
  - `tokenColor` (`page.ts:20`).
- `web/e2e/guide/guide.spec.ts` (chromium, so `live sign-in`, part 1/2):
  - `:218` (Q2, step 3 selected) and `:241` (Q2 markers): "Go to Break the feed visible" becomes "the prompt bar holds no button".
  - Existing pins of the box tag, left as they are: `:334`, `:513`.
- `web/e2e/demo-path/01-page.spec.ts:176-191`, the `@floor` test "the demo guide lists the steps". Row 3 `:180` asserts the button, and the loop asserts exactly one button per row.
- `src/ocutalon/cls/OcuTalon/Demo/Guide.cls:9-10,145-176`, read only. Break the feed is inactive while any visible Orders incident is open (`Ownership.IncidentInProgress`, window-free). The step reads only the run window's incident, so an open incident noticed before the epoch start leaves step 3 current with the box inactive (inference).

**UX (`_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/`):**
- `EXPERIENCE.md`:
  - `:516` Flow 1 step 5, "Dana presses **Go to Break the feed**, then **Break the feed**";
  - `:584` the demo guide table, row 3's Action button cell;
  - `:419` the Accessibility Floor › Focus replacement row "Guide step advances".
- `mockups/states.html`: `:675` the C2 Next bar's `<button … btn-primary>Go to Break the feed</button>`, and `:683` the C2 caption.

## Tasks & Acceptance

**Execution** (in dependency order):
- [ ] `web/src/app/guide/guide-view.ts`: remove `goToBreakFeed` from `GUIDE_TEXTS` and `PromptAction`, and make step 3 non-waiting action `'none'`. Rule 14: comments state the contract.
- [ ] `web/src/app/guide/demo-guide.ts`:
  - delete the `@case ('goToBreakFeed')` and `goToBreakFeed()`;
  - mark the prompt bar when it shows step 3, in either form;
  - in `FOCUS_RULE.whenGone`, when the lost key is a prompt part (`action`/`text`/`bar`) or a finish part and the prompt bar now carries the step-3 mark, return `host.querySelector(BREAK_FEED_BUTTON)`. Otherwise keep today's order;
  - restate the class doc (focus moves for the user's own action: Show me; and through the focus rule, which hands step 3's focus to the box).
- [ ] `web/scripts/guide-view.test.mjs`: L47 and L229-231 only, as in the Code Map.
- [ ] `web/scripts/announce-focus-sources.test.mjs`: L123, a count of 1 and the new reason.
- [ ] `web/scripts/ux-strings.test.mjs`: delete L345's entry only.
- [ ] `web/e2e/floor/guide.spec.ts`:
  - **M3, M6, M10:** as in the Code Map.
  - **M7:** the page opens at step 3. Assert:
    - the quoted line after "Next:";
    - no button or link in `.prompt`;
    - the box has class `next-step` and its "Next step" tag, with `border-inline-start-width` 4px in `tokenColor(page, '--action')`;
    - after `settled(page)`, focus is not on `breakOf(page)` (the load moved nothing);
    - no POST.

    The waiting and no-notice parts stay, each with no button. Retitle it: "M7: step 3 shows only its instruction line, with the box's Next step tag and teal bar, and a run in flight shows only the waiting line".
  - **M12:** the Show me half is unchanged. The Go half becomes the inactive hand-off:
    - seed the watch and an open Orders incident noticed before the epoch start (`seedIncident(user, { ...ORDERS, noticedAt: inMs(-600_000), state: 'open', … })`, then `startEpochAt(user, inMs(-300_000))`, restored in `finally` as M7 does);
    - at step 2, focus Send, then seed and publish the reminder;
    - assert step 3 current, `breakOf` `aria-disabled="true"`, focus on it, still `aria-disabled`, and no POST to `/demo/break-feed`, `/guide/markers` or `/messages`.

    If the seeding does not give step 3 with an inactive box, any seeded inactive state reached through that same Send hand-off will do; record it. Retitle it accordingly.
  - Delete `goOf` and fix the header.
- [ ] `web/e2e/guide/guide.spec.ts`: L218 and L241, as in the Code Map. No case is added.
- [ ] `web/e2e/demo-path/01-page.spec.ts`:
  - take row 3 out of the table (L180);
  - after the loop, add a step 3 block shaped like the step 5 block: click step 3, assert its name, the quoted P3 and `prompt.getByRole('button')` count 0.

  Nothing else in the file changes.
- [ ] `EXPERIENCE.md`:
  - **Row 3's Action button cell:** "None. The box's "Next step" tag and teal left bar point to **Break the feed**; when step 3 becomes current by the user's own press (Send on step 2, or Run again), focus moves to the box's Break the feed button without pressing it."
  - **Flow 1 step 5:** "Dana presses **Break the feed**."
  - **The `:419` row:** append "; on step 3, which has none, the box's Break the feed button".

  Each change gets a marker, `[AMENDED 2026-11-01, Story 4.8, owner feedback from the demo walk-through, relayed by the Contest Planner; the owner: "…redundent when teh "Break the feed" red button is right next to it." It read: "<old text>"]`.
- [ ] `mockups/states.html`:
  - **C2:** delete the Next bar's button, and leave an HTML comment marker in its place citing the owner's feedback of 2026-11-01.
  - **The C2 caption:** "step 3 (no action button; the box's "Next step" tag and teal left bar point to Break the feed)", with the same marker in brackets.

**Acceptance Criteria:**
- **AC1.** Given step 3 is current or selected, when the Next bar renders, then it shows only the instruction line (or, while waiting, only the waiting line) with no action button. The `goToBreakFeed` action, its text, its `@case` and its handler are gone from `web/src` and `web/e2e`.
- **AC2.** Given step 3 is current, when the box renders, then its "Next step" tag and 4px teal left bar are as before.
- **AC3.** Given step 3 becomes current by the user's own press (Send on step 2, or Run again from the finish), when the guide moves to step 3, then focus is on the box's Break the feed button, active or inactive, and nothing is pressed or posted.
- **AC4.** Given step 3 becomes current with no user press (a load, or an update while focus is elsewhere), when it renders, then focus does not move.
- **AC5.** Given the UX spec and the mockup, when this story merges, then EXPERIENCE.md's row 3, its Flow 1 step 5 and its focus-replacement row, and states.html's C2 Next bar and caption, show no button. Each change carries a 2026-11-01 owner-feedback marker.
- **AC6.** Given the change, when it merges, then the listed tests follow it, no test case or spec file is added, and CI is green on every workflow.

## Spec Change Log

## Review Triage Log

### 2026-11-01 - Review pass
- verdicts: 19 findings - high 0, medium 1, low 14, false 3, maybe-false 1
- findings:
  - `[low]` `[patch]` Blind: step-3 branch in whenGone returns null when the box button is missing, skipping the prompt fallback (Edge Case Hunter reported the same) - whenGone now falls through to today's order when the box button is absent.
  - `[low]` `[reject]` Blind: bare `=== 3` mark repeated as a magic number - two uses of one documented attribute; no named harm.
  - `[false]` `[reject]` Blind: UX wording "user's own press" narrower than the rule - the rule fires when the focused prompt part is removed (the spine's focus convention), which is what the spec, Decided in-stage 1 and the EXPERIENCE text state.
  - `[medium]` `[patch]` Blind: coverage gaps for the new path (1 to 3 jump, row 6, had no test) - M12 now starts at step 1 and one refreshGuide jumps the guide to step 3 with Send focused, asserting focus on the inactive box. The waiting form, the missing-button fallback and selected-not-current stay untested (low, unlikely, a test would need new seeded states).
  - `[low]` `[reject]` Blind: AC1 mutation line says the live M7 check was not run - the node test is red for that mutation and M7 asserts the same shape; recorded as such.
  - `[low]` `[patch]` Blind: M7's no-notice "no button" check used a class locator - now `.prompt` plus getByRole('button').
  - `[low]` `[patch]` Blind: M12 fragile and leaves a run_again epoch bump (Edge Case Hunter and verification-gap reported the same) - the finally block restores the epoch start and ends the run with endRun, as M9 to M11 do.
  - `[low]` `[patch]` Edge: the same missing-button fallback as the first row - patched with it.
  - `[false]` `[reject]` Edge: focus moves without a press, wording wider than code - same as the third row; by design.
  - `[low]` `[patch]` Edge: epoch restore in finally runs after cleanFixtureRows and restores the post-marker value - patched with the M12 cleanup row.
  - `[maybe-false]` `[defer]` Verification gap: no test for row 4's negative cell (prompt bar back at step 1 or 2 hands focus to Send) - deferred, unverified medium; a mutation run ignoring the mark would settle it.
  - `[low]` `[reject]` Verification gap: the step 3 waiting form's hand-off has no test - rare path (Break the feed pressed from step 2), same single branch as M6/M10; a test needs a new seeded state.
  - `[low]` `[reject]` Verification gap: a click on the step 3 step button keeping focus is not asserted - the select handler is untouched and no focus call was added; the only focus mutation (AC4) is pinned.
  - `[low]` `[patch]` Verification gap, other: M10's no-POST check had no settled() before it - settled(page) added.
  - `[low]` `[patch]` Verification gap, other: M12 hermeticity - the same cleanup as above.
  - `[low]` `[reject]` Verification gap, other: M7's 4px and --action assertions were not mutated - the same values are pinned at guide/guide.spec.ts:334 and :513, and the next-step class and tag are mutated.
  - `[low]` `[reject]` Intent alignment: the click on the step 3 step button keeping focus is not asserted - same as the earlier row.
  - `[low]` `[reject]` Intent alignment: the mark follows `selected`, not the current step - the two coincide after an advance or Run again (followSelection); the spec says "shown step".
  - `[false]` `[reject]` Intent alignment: M12 changed shape - the spec allows another seeded inactive state reached through the same hand-off.

## Design Notes

**Architecture decisions** (spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`, status final):
- **AD-1** (L102): REST writes only UI markers. Moving focus presses nothing and posts nothing.
- **AD-12** (L381): `Guide.Compute` alone decides the step and Break the feed's availability. The page renders the step; nothing changes on the server.
- **AD-29** (L925): Lane B, and each epic keeps its home lane's files.
- **Conventions:**
  - L1088, Announcements and focus: focus moves only through `focus-rule` when an update removed the focused element. That is exactly the hand-off this story uses.
  - L1111, Angular: standalone and signals.
  - L1115, Tests: floor cases only in `live:floor`; the demo-path `@floor` test.
- No AC contradicts an AD's Rule, and no NFR trips Rule 5 (the ACs cite UX-DR44, UX-DR48, UX-DR131).

**Integration ACs (Rule 1):** no new service, module or shared component. This story is a removal (the Go to Break the feed button, its action, text and handler) plus a focus-target change inside the guide's existing focus rule. It has no consumers to name.
- **Consumes:**
  - Story 4.4: `FOCUS_RULE`, `BREAK_FEED_BUTTON`, the box and its "Next step" tag;
  - Story 4.7: the prompt bar of steps 3 to 5, Run again and its held answer;
  - Story 2.12: `shared/focus-rule.ts` `keepFocus`.
- **Consumed-by:**
  - Story 4.9: it edits the same guide files next, and its Demo view switch hides the guide;
  - Story 4.10: it relies on 4.9's signal and the finish state.

**Rule 2 (extend, don't copy):** the step-3 hand-off extends `FOCUS_RULE.whenGone`, the sibling that already hands `step1` (Do step 1) to `BREAK_FEED_BUTTON`. It reuses that selector. There is no new focus helper and no new `.focus(` call, and `keepFocus` makes the move.

**Ledger (Rule 17):** the inbox is empty, so this story owns no entry.

**Decided in-stage** (unattended: small, reversible, within the intent):
1. **The hand-off goes through the focus rule, not a handler call.** Both user-press paths leave focus on an element that the update removes: Send (key `action`) and Run again (key `runAgain`). The spine's focus convention allows exactly this move.
   - If the user has moved focus elsewhere after pressing, nothing moves (AC4).
   - An update that removes a focused prompt part for another reason (say, Run again pressed in another tab) hands focus to the box. Before this story it handed it to Go to Break the feed, so this is the same focus replacement with a new target, not a new move.
2. **Step 3's waiting form hands focus to the box too.** It is reachable when Break the feed was pressed on step 2, because the box is active from step 1. The inactive button takes focus, as the AC says.
3. **Step 1's Send, when the view jumps from 1 to 3,** takes the same hand-off (row 6). It is still the user's own Send.
4. **M6 and M12 represent the press by focus on Send,** M6's existing pattern. A real Send on the floor stack would post a model turn, which is not the subject here. M10's Run again is a real press.
5. **01-page's step 3 coverage moves after the loop,** in the step 5 block's shape. The loop asserts exactly one button per row, so a button-less row 3 cannot stay in it. Moving it is the smallest edit that keeps the loop as it is.
6. **EXPERIENCE.md's focus-replacement row (`:419`) also changes.** It says a step with no action hands focus to the prompt text, which would contradict AC3 for step 3. The edit is in an allowed file, with the same marker.
7. **These stay unchanged:** DESIGN.md L763 ("the step's action button"), which is outside the footprint, and EXPERIENCE.md L226 ("its action button"). Both are generic, and steps 4 and 5 already show no button in some states. Story 4.9 edits the L222 section next.
8. **M12's inactive state:** an open incident noticed before the epoch start (inferred from `Guide.cls`). The task allows another seeded inactive state reached through the same hand-off.
9. **The cost:** about the same `live floor` time (no case added; M12 gains one publish).

**Veto items:** none. There is no new public text (only "Go to Break the feed" leaves), and nothing is touched on security, data, dependencies or ADs.

## Verification

`<B>` means `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=4 stage=<stage>'`, run from the worktree root.
- **Fresh tag:** `e4s8i`. There is no warm stack: no server class changes.
- **Slot B is not needed.** If an IRIS MCP call is ever made, use `server` `ocutalon-slot-b` and namespace `OCUTALON`, checked first with `iris_server_info`.
- **One command per foreground call** (`timeout: 600000`), and one `iris_execute_tests` per message.

**Commands:**

`(loop)`:
- `npm --prefix web test` -- expected: every node test passes (guide-view, announce-focus-sources and ux-strings included).
- `npm --prefix web run lint` -- expected: exit 0.
- `git grep -n -e 'goToBreakFeed' -e 'Go to Break the feed' -- web` -- expected: no output.
- `grep -n 'Go to Break the feed' _bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md _bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/mockups/states.html | grep -v 'AMENDED 2026-11-01'` -- expected: no output. Every remaining mention is inside a marker.
- `<B> OCUTALON_RUN_TAG=e4s8i ci/iris.sh build` -- run before any browser unit, and again after any merge that brings `web/` changes.
- `<B> OCUTALON_RUN_TAG=e4s8i ci/iris.sh live floor` -- expected: PASS in all three projects. About 315-333 s (Story 4.7); record the time.
- `<B> OCUTALON_RUN_TAG=e4s8i ci/iris.sh live sign-in --part 1/2` -- expected: PASS. Part 1/2 holds `guide/guide.spec.ts`: measured in this plan from Playwright's listing, 8 of 19 files, 127 of 223 tests.
- `<B> OCUTALON_RUN_TAG=e4s8i ci/iris.sh live demo-path` -- expected: PASS. STEP 1 passes with the same counts as the base head; the floor count is unchanged.

`(once)`:
- `<B> OCUTALON_RUN_TAG=e4s8i ci/iris.sh live sign-in --part 2/2` -- expected: PASS, with the case count unchanged.
- `bash docker/tests/test-web-build.sh` -- expected: passes.
- `bash ci/checks.sh` -- expected: exit 0.
- At the end, also after a failure: `<B> OCUTALON_RUN_TAG=e4s8i ci/iris.sh teardown`.
- Not run: `live demo-switch`. The guide payload and keys are unchanged; CI's groups run it.

**Planned mutations (Rule 19).** Apply each one, observe red, revert, and confirm that `git status --short` and `git diff --stat` are unchanged. Record each as `mutation: … → …`.
- AC1: `promptOf(3)` gives action `'showMe'` → `guide-view.test.mjs` "step 3 sends the user to Break the feed…", and M7 (a button in `.prompt`).
- AC1: keep `goToBreakFeed()` with its `.focus(` → `announce-focus-sources.test.mjs` (a count of 2, not 1).
- AC2: `boxView` sets `nextStep: false` at step 3 (applied temporarily, never kept) → M7 (no `next-step` class or tag).
- AC3: `whenGone` without the step-3 hand-off → M6 and M10 (focus on the prompt text), and M12.
- AC3: the hand-off also clicks the box's button → M6 and M10 (a `/demo/break-feed` POST seen).
- AC4: `follow()` focuses `BREAK_FEED_BUTTON` whenever the view's step becomes 3 → M3 (the composer loses focus on 2 to 3), and M7 (focus after the load).
- AC5: restore EXPERIENCE.md row 3's old cell with no marker → the UX `grep … | grep -v` command prints it.
- AC6: leave the 'Go to Break the feed' entry in `ux-strings.test.mjs` → "has no entry that matches no inventory string".

**Mutation results (implement stage, each applied, observed red, reverted; tree byte-identical by `git diff --stat` and md5):**
- mutation: AC1: `promptOf(3)` gives action `'showMe'` -> red in `guide-view.test.mjs` "step 3 sends the user to Break the feed, quoted, for every stage but the waiting ones (row 1)" (the live M7 button check was not run for this one).
- mutation: AC1: keep a `goToBreakFeed()` with its `.focus(` in `demo-guide.ts` -> red in `announce-focus-sources.test.mjs` "has a .focus( call only in the files that ...".
- mutation: AC2: `break-feed-view.ts` `nextStep` needs `current === 99` (temporary, restored) -> red: floor M3 and M7 (M7 on `toHaveClass(/next-step/)`).
- mutation: AC3: `whenGone` step-3 mark test compares with `'x'` (no step-3 hand-off) -> red: floor M6, M10 and M12 (`toBeFocused`); M3 and M7 stay green.
- mutation: AC3: the hand-off also clicks the box's button -> red: floor M6, M10 and M12 (M6: a `/demo/break-feed` POST seen; M10: the prompt did not come back).
- mutation: AC4: `follow()` focuses `BREAK_FEED_BUTTON` whenever the view's step is 3 -> red: floor M3 (composer loses focus) and M7 (focus after the load); M6, M10 and M12 stay green.
- mutation: AC5: EXPERIENCE.md row 3's old cell with no marker -> the UX `grep ... | grep -v 'AMENDED 2026-11-01'` command prints the line.
- mutation: AC6: leave the 'Go to Break the feed' entry in `ux-strings.test.mjs` -> red "has no entry that matches no inventory string".

**Decided in-stage (implement):**
- The hand-off marker is `data-guide-step="3"` on `div.prompt` (set when `guide.selected === 3`); `FOCUS_RULE.whenGone` reads it through `find('bar')`.
- M12's second half reloads the page with `loadedAfter(page, () => page.reload())` (a second sign-in on a signed-in page hangs) and writes a `run_again` marker first, so the session has its guide state row and `startEpochAt` sets the window whichever case ran before; with no row, `startEpochAt` writes nothing and the old open incident would count (step 4).

**Decided in-stage (review pass):** M12's second half now covers matrix row 6 as well as the inactive cell: the page reloads at step 1 (an open incident noticed before the run window, no watch), Send is focused, the watch and the reminder rows are seeded and one refreshGuide jumps the guide from step 1 to step 3.

**Shared surfaces:**
- the guide's `PromptAction` union (`guide-view.ts` and `demo-guide.ts`'s `@switch`);
- `GUIDE_TEXTS` (`guide-view.test.mjs`'s deepEqual, and `ux-strings.test.mjs`'s inventory);
- the UX string list `SOURCES` in `ux-strings.test.mjs`;
- the focus-call list `FOCUS_CALLS` in `announce-focus-sources.test.mjs`;
- the step 3 prompt bar's shape (floor M3, M6, M7, M10, M12 and M13; `guide/guide.spec.ts` Q2 twice; `01-page.spec.ts`'s guide test);
- `FOCUS_RULE`'s hand-off order (floor M6, M9, M10 and M13; `guide/guide.spec.ts:730-734`'s Do step 1 hand-off);
- EXPERIENCE.md's strings read by `ux-strings.test.mjs`, `host-pages.test.mjs` and `mailbox-view.test.mjs` (the step 3 lines stay verbatim);
- the floor user's `GuideState` (M12's `startEpochAt` is restored in `finally`).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Plan summary.** A web-only removal of step 3's Go to Break the feed button, with the keyboard path kept. The guide's existing focus rule hands focus to the box's Break the feed button when step 3 becomes current by the user's Send or Run again. The UX spec and the mockup are updated with 2026-11-01 owner-feedback markers. The tests listed in the ruling are reworked; no case is added. Footprint extensions: none. Amendments: none. Clarifications: none.

**Implemented change.** Step 3's "Go to Break the feed" button is removed (`goToBreakFeed` in `PromptAction`, `GUIDE_TEXTS`, the `@case` and the handler). The prompt bar carries `data-guide-step="3"` while step 3 is shown; `FOCUS_RULE.whenGone` hands a lost prompt part or finish part to the box's Break the feed button then (active or inactive, never pressed), and falls through to the old order if the button is absent.

**Files changed.**
- `web/src/app/guide/guide-view.ts`, `demo-guide.ts`: the removal and the focus hand-off.
- `web/scripts/guide-view.test.mjs`, `announce-focus-sources.test.mjs`, `ux-strings.test.mjs`: action `none`, one `.focus(` call, the string entry removed.
- `web/e2e/floor/guide.spec.ts` (M3, M6, M7, M10, M12), `web/e2e/guide/guide.spec.ts` (Q2 twice), `web/e2e/demo-path/01-page.spec.ts` (a button-less step 3 block): reworked to the new behaviour.
- `EXPERIENCE.md`, `mockups/states.html`: row 3, Flow 1 step 5, the focus-replacement row, and the C2 bar and caption, each with a 2026-11-01 marker.

**Review.** Patches applied: 5 entries (1 medium, 4 low). Deferred: 1 (row 4's negative cell, unverified medium). Rejected: the rest, with reasons in the Review Triage Log. Follow-up review recommended: false (no high patched, one medium patched).

**Verification performed.**
- `npm --prefix web test`: 1127 pass. `npm --prefix web run lint`: exit 0. Both grep checks: no output.
- `ci/iris.sh live floor`: 105 passed (6:12). `live sign-in --part 1/2`: first run 1 failure (B2, DW-349 flake), unchanged rerun 127 passed (5:30). `live demo-path`: floor 7 of 7, 5 of 6 steps ran, 0 failed (2:24). `live sign-in --part 2/2`: 96 passed (5:20). `docker/tests/test-web-build.sh` and `ci/checks.sh`: pass. Tag `e4s8i` torn down, no containers left.
- Mutations: eight planned, each red and reverted (see Verification).

**Residual risks.** Row 4's negative cell and the waiting-form hand-off have no pinning test (see `deferred`). Footprint extensions: none. Amendments: none.
