# Epic 20 Context: Add documents in the web app (step 3)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A user who asks about their documents or what OcuTalon remembers can see where each answer came from. Every web chat answer that drew on documents ends with citation chips that open the passage. An answer that recalled a memory carries a "From memory" chip. This makes document answers and memory recall checkable, and it completes step 3's user-facing promise. In this run the epic holds only Story 20.2. Adding and removing documents (the former Story 20.1) moved to Story 34.2 and is already merged.

## Stories

- Story 20.2: See citations and memories in answers

## Requirements & Constraints

- Answers drawn from documents cite each document and section, using at most 5 passages per model request. When no document is relevant, OcuTalon says "None of your documents cover that." instead of guessing.
- An answer that uses a memory must say so. The "From memory" chip meets this requirement.
- **Owner ruling U-280 (binding):**
  - A reply that says "None of your documents cover that." never carries document citations, and a reply with document citations never says it. Code decides both from the same turn's tool results, and tests cover both directions.
  - Chip and citation labels state provenance, never reliance. "Sources" and "From memory" are allowed. "used", "relied on" and "based on" are not.
- Accessibility floor:
  - Keyboard-only use works.
  - Each chip is a button whose accessible name includes its document or memory.
  - Nothing relies on colour alone.
  - Text contrast meets WCAG AA.
  - Text resizes to 200% without loss.
- Every new fixed string must be added to the fixed-strings test (`ux-strings.test.mjs` reads them from EXPERIENCE.md).
- Public-text rule: changing a public string needs a Contest Planner ruling. Both open items below are public strings:
  - Restoring a citation line in the demo guide's "Ask about a document" look-for (DW-975). This means changing `more-to-try-view.ts` `documents.lookFor`, its three test pins and EXPERIENCE.md item 6 together.
  - The Documents page empty state, which already promises cited answers (DW-976).
- Ledger items owned by 20.2:
  - DW-383: `Eval.In.Render` copies the private `Core.Conversation.Checked` line for line, so a change to Conversation's HostData handling makes the evaluation drift. Keep the two in step or record the drift.
  - DW-721: the U-280 chip rules.
  - DW-733: a GuideRefresh flake candidate on a warm stack.
  - DW-975 and DW-976: the public strings above.
- Release check: the Contest Planner's hands-on pass at step 3's release exercises memory and cited-document answers on the web and in Telegram. This check does not block the story.

## Technical Decisions

- **The data shape is fixed and built upstream by Lane A (already merged).** The bridge `Reply`'s `HostData` carries two arrays beside `checks`:
  - `citations`: one `{documentRef, document, section, passage, chunkIndex}` per distinct passage returned by the turn's `documents` tool calls, in order, at most 5.
  - `memories`: one `{memoryRef, text, savedAt}` per memory that `search_memories` returned in the turn, at most 5.

  Code builds both from tool results, never from model text, and leaves each out when it is empty.
- **Carrying them (Lane B, `Conversation`).** `Conversation` puts the citations and memories on the outbound reply and on the `chat.message` live event after the reply filter has run. It does this the same way it already handles check rows: the AD-28 pattern of reading `HostData` from the `Reply`, then attaching the data to the outbound reply and `chat.message` after the guard. `Conversation` is the sole publisher of `chat.message`. Live-event payload keys are camelCase.
- **Reply filter contract.** `ReplyFilterClass` is called as `Filter(text, hostData)`. `OcuTalon.Checks.ReplyGuard` runs `OcuTalon.Docs.Reply.Apply`, which strips "None of your documents cover that." from a reply whose `hostData` holds citations. Do not duplicate that logic in Lane B; carry what the filter leaves.
- **Passage display.** Show passage text as plain text, never rendered markup, at most 6 lines.
- **Lanes.** Epic 20 lives in Lane B's files: `Conversation`, the web chat's message view and its tests. Lane A owns building the `HostData` arrays, the Documents/Memory tables and the guard. Do not edit Lane A's code.
- Until real replies are available in a test, use fixture replies with the fixed shape. Stories 19.3 and 19.4, which fill it, are merged.

## UX & Interaction Patterns

- **Citation chip (D `citation-chip`)**
  - Look: `info-soft` background, 1px `info-ink` border and `info-ink` text, `rounded.xs` (4px), caption typography, `file-text` icon.
  - Label: "{document} § {section}". Fixture: "Results runbook § Rotating the certificate".
  - Placement: the chips end the answer.
- **Citation popover:** the passage (at most 6 lines), the document, the section, and "Open document". "Open document" shows that document's text on the Documents page (Story 34.2's page).
- **Memory chip:** "From memory". Its popover shows the remembered text and the date it was saved.
- **Popover rules (D `popover`)**
  - It is a non-modal `role="dialog"` named by its heading.
  - Focus goes to its first control when it opens.
  - Esc, a press outside it, or focus leaving it closes it and returns focus to the trigger chip.
- Reference flow: Sam asks what the runbook says about rotating the Results certificate. The answer gives the steps, then the chip, and Sam presses the chip to check the passage.

## Cross-Story Dependencies

- These dependencies are all merged:
  - Epic 34: Story 34.1 fixed the `HostData` citations and memories shape. Story 34.2 built the Documents page that "Open document" targets.
  - Epic 19: Stories 19.3 and 19.4 fill `memories` and `citations`, and Story 19.7 covers PDF and Word.
  - Epic 18: Story 18.4 already changed the web chat message view and its tests (the digest card and **Got it**), so build the chips alongside that work.
- `Eval.In.Render` (DW-383) mirrors `Conversation`'s HostData glue, so a change to it can affect the evaluation's all-clear path.
- Story 4.12 removed the guide's citation promise for 1.0.4. When 20.2 ships, it owns restoring that promise, subject to a Planner ruling on the public text.
