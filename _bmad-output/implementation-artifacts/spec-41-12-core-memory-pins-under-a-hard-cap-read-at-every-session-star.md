---
title: "Story 41.12: Core memory: pins under a hard cap, read at every session start"
type: 'feature'
created: '2026-11-09'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 41.9 routes `PinMemory` and `UnpinMemory` to `MemoryOps`, but `MemoryOps` has no handler for them, so both pin routes answer 500 and nothing can be pinned. No pinned memory reaches a model. Two session-start defects also lose or duplicate context. A first turn of the day that falls back before reaching a model uses up the day's session start (DW-967). And today's note quotes the person's current message back to the model (DW-977).

**Approach:** `MemoryOps` gains `OnPin` and `OnUnpin`. Under the session's lock, `OnPin` sums the pinned texts through a new owner-scoped read, `OcuTalon.Memory.Pinned`, then sets the pin or refuses with `over_cap`. `Agent.Input.Render` adds the core-memory block at a user item's session start, after the persona block and before the notes. `Conversation.StartsSession` counts only earlier turns whose request reached a model. `DailyNote.Build` takes the ItemId of the turn being answered, and leaves out that turn and every later one. The tests that stopped at a probe are re-pinned on the real outcomes (DW-1029, DW-1039).

## Boundaries & Constraints

**Always:**
- **The cap (FR-74, NFR-27).** It is the sum of `$Length(Text)` over the session's pinned memories plus the new one, at 4 characters a token. A sum up to 4,000 characters (1,000 tokens) is pinned. A larger sum is refused with Outcome `over_cap`, Ok 0, and nothing changes. Nothing is ever unpinned to make room.
  - Use the epics' numbers as given: 1,000 tokens, 4 characters a token, 4,000 characters for the block.
  - The constants `PINCAPTOKENS = 1000` and `CHARSPERTOKEN = 4` are defined once, in `OcuTalon.Memory`.
- **Lock and scope.** The cap sum and the pin write happen under `MemoryOps`' lock `^OcuTalon.Memory(sessionRef)`. The ref must be the command's own session's row: an unknown ref and another session's ref both answer `not_found`, the same way (DW-740).
- **DW-1014.** The pinned read and the cap sum use `COALESCE(Pinned, 0) = 1`. A row saved before Story 41.8 (stored `Pinned` empty) is not pinned, and it can be pinned.
- **The core-memory block.** It is only for an item with provenance `user` whose context has `sessionStart` 1, and whose owner is a session, never `eval`, `instance` or empty.
  - It opens with `"Your core memory (facts you pinned):"` on its own line (EXPERIENCE.md:1070), then each pin through `Quoted`, newest pin first (`PinnedAt DESC`, then row `ID DESC`), then a blank line.
  - Each pin is whole or left out, together with every older pin. The block, the closing blank line included, is at most 4,000 characters (`COREMAX`).
  - A read that throws leaves the block out and logs one warning (redacted). Render never throws because of it.
- **Lanes and shared files.** `Ownership` gets added lines only. `Conversation` and `DailyNote` are this epic's own Lane B files, and the lead found no contention on them. The spine gets additive lines only, marked `[ADDED 2026-11-09, Story 41.12]`.
- **Tests.** Every test added or changed passes on a fresh environment, in either order, and creates and removes its own rows.

**Never:**
- Edit `Core/CommandsIn.cls` or `Web/Api.cls`. 41.9's gate, routes and outcome mapper already give 200, 404, 409 and 501.
- Pin from any path other than `PinMemory` handled in `MemoryOps`.
- Add a column or index, or change `Data.Memory` storage. Any of these is a veto item.
- Add new user-facing or model-facing text. The block's opening is the only text, and it comes from the UX.
- Touch `web/src/**` or the Memory card (that is 41.13's work).
- Change the output of `Web.Api` Notes (`DailyNote.Build` with two arguments).
- Edit contended paths: `Mcp/**`, `Bridge/Adapter/**`, `Msg/Catalog/**`, `Test/Msg/Catalog.cls`, `Production.cls`, `ci/units.sh`, `src/short-names.tsv`, `release/**`, workflows, compose files.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Pin within cap | own unpinned memory; pinned sum + its length ≤ 4,000 | `Pinned` 1, `PinnedAt` now (UTC to the second); Ok 1, Outcome `pinned`; route 200 `{"result":"done"}` | none |
| Exactly at cap | pinned sum + new = 4,000 | pinned | none |
| Over cap | pinned sum + new > 4,000 | Ok 0, `over_cap`; no row changes; route 409 with the approved over_cap text | none |
| Already pinned | own pinned memory | Ok 1, `pinned`; `PinnedAt` unchanged; no cap re-check | none |
| Pre-41.8 row | own row whose stored `Pinned` is empty | treated as unpinned; the pin follows the cap rule; not counted in the sum before it is pinned | none |
| Unpin | own memory, pinned or not | `Pinned` 0, `PinnedAt` ""; Ok 1, Outcome `unpinned`; route 200 | none |
| Other session / unknown ref | ref of another session's row, or no row | Ok 0, `not_found`; nothing changes; route 404 | none |
| No session row | command's `SessionRef` has no `Data.Session` | `no_session` (as `OnForget`); route 500 | none |
| Lock or save fails | lock not free in 5 s; `%Save` error; exception | `failed` (shared `Failed`), one Type 3 warning | route 500 |
| Forget a pinned memory | own pinned row | deleted (existing `OnForget`); gone from `Memory.Pinned` and from the next session-start block | none |
| Session start with pins | user item, `sessionStart` 1, session has pins | preamble, persona block, core block, notes block, then text | a failed pinned read: no core block, one warning, the rest rendered |
| Block at the bound | pins whose whole quoted block would exceed 4,000 | newest pins whole up to the bound; the first pin that doesn't fit is left out, with every older one; no marker line | none |
| Not a session start | no `sessionStart`, untrusted item, owner eval/instance/"" | no core block, and no read | none |
| DW-967 | earlier same-day turn ended in a fallback whose reply decision has no Usage row (no_key, daily_cap, budget, too_large, a thrown Chat) | it does not count, so the next turn is a session start | a failed read: counts as a start, with one warning (as today) |
| DW-967 reached | earlier same-day fallback turn whose reply decision has a Usage row (e.g. refusal, cut_off) | counts, so the next turn is not a start | none |
| DW-977 | session start; today's note | leaves out the turn with the item's ItemId, every later turn of the session (CreatedAt, then ID), and the decide decisions those turns made | an ItemId that names no turn of the session: the whole note, as today |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless given in full. Line numbers are as of `0183ce4f`.

- `Memory/Ops.cls`:
  - MessageMap (44-57): add `PinMemory`→`OnPin` and `UnpinMemory`→`OnUnpin`.
  - Model both handlers on `OnForget` (135-161): the no_session check, `Lock`, `RefIndexOpen` with the owner check, Try/Catch, release.
  - Reuse `Answer` and `Failed` (204-235). The pin answers carry an empty Message, as `OnSearch` does (186), because the web layer never relays it.
  - Class comment:
    - add the two handlers;
    - fix line 22 for DW-1029: SaveMemory comes from origin tool; ForgetMemory from tool or web_user; PinMemory, UnpinMemory and SearchMemory from web_user only.
- `Memory.cls`:
  - Add `Parameter PINCAPTOKENS = 1000` and `CHARSPERTOKEN = 4`.
  - Add `ClassMethod Pinned(sessionRef, Output rows As %DynamicArray) As %Status`, a sibling of `List` (129-150):
    - `SELECT Ref, Text, SavedAt, Origin, Source, Pinned FROM ... WHERE SessionRef = ? AND COALESCE(Pinned, 0) = 1 ORDER BY PinnedAt DESC, ID DESC`;
    - rows are shaped by `Row` (197);
    - an empty session is an error status.
  - Add it to the class comment. List and Search are unchanged.
- `Agent/Input.cls`:
  - `Render` (48): a user item becomes `preamble_LF LF_PersonaPart_CorePart_NotesPart_text`.
  - New private `CorePart(item, context)`, modelled on `PrecedentPart`'s whole-line bound (113-126) and `NotesPart`'s Try/Catch and warning (76-90).
  - New private seam `PinsOf(sessionRef)` that calls `Memory.Pinned` and throws on an error status.
  - Add `Parameter COREOPENING = "Your core memory (facts you pinned):"`, `COREMAX = 4000` (equal to `PINCAPTOKENS * CHARSPERTOKEN`; a test pins the equality) and `LOGCORE`.
  - `NotesPart`/`NoteOf` (72-98): pass `item.ItemId` as Build's new third argument.
  - Update the class comment (1-31).
- `Data/DailyNote.cls`:
  - `Build(sessionRef, day, itemId As %String = "")` (58).
  - When `itemId` names a turn of the session (`Ownership.TurnOfItem`, through the existing `TurnOf` seam at 188), `Messages` (127-137) skips that turn and every turn after it by (CreatedAt, ID), and `Decisions` (141-160) skips decisions whose `TurnOf(row.ItemId)` is a skipped turn.
  - Update the header (1-16).
- `Core/Conversation.cls` `StartsSession` (443-474):
  - The loop condition (462) also requires the earlier turn to have reached a model: `FallbackReason = ""`, or its `TurnDecisionRef` has a Usage row of the session.
  - A read error returns 1 with one `LOGSTART` warning.
  - Update the doc comment and the header lines 15-17.
- `Data/Ownership.cls`: add `DecisionServed(decisionRef, sessionRef, Output sc) As %Boolean`, which is 1 when the decision has at least one Usage row of the session. It is a sibling of `DecisionChannel` (769-781) and reads the same `turnUsage` kind (996). Added lines only.
- `Test/Agent/InputProbe.cls:7`: the `NoteOf` override takes and passes the new argument. Add a `PinsOf` override that throws while `^||InputProbe("failCore")` is set.
- Read only:
  - `Core/CommandsIn.cls:235-236` (the routes);
  - `Web/Api.cls:1908-1929` `MemoryItemCommand` (Ok→200, not_found 404, over_cap 409, else 500);
  - `Msg/Command/PinMemory.cls`;
  - `bridge/.../Process/Decide.cls:1147-1161, 1271-1281, 1595-1638` (a precheck or a thrown Chat with no spend writes no Usage row);
  - `Test/Data/Fixture.cls:22, 35, 160` (`Session`, `Turn`, `Usage`).
- Tests:
  - `Test/Memory/Pins.cls` (new, area Memory, shard lane-a). Safe on a slot. It calls the handlers on a shadow instance of `OcuTalon.Memory.Ops`, with a fixture session and memory rows saved directly with a vector of ones (`Test.Memory.Fixture.ToVector`, as `Test.Web.MemoryApi.Memory` at 674-693), so it needs no embedder and no production.
  - `Test/Agent/RenderMemory.cls`: core-block tests.
  - `Test/Data/DailyNote.cls`: the DW-977 cut.
  - `Test/Data/OwnershipNotes.cls`: `DecisionServed`.
  - `Test/Core/ConversationSessionStart.cls`: DW-967 cases in `TestStartsSessionBoundaries` (183-213, after the refused case at 198-201), and the integration test.
  - `Test/Core/CommandsStep3Probe.cls:21-22`: dispatch `PinMemory`→`OnPin` and `UnpinMemory`→`OnUnpin`.
  - `Test/Core/CommandsStep3.cls`: wherever a pin's outcome is now the handler's.
  - `Test/Web/MemoryApi.cls` `TestPin` (432-465): the real-mode tail and its doc comment.
  - `Test/Bridge/SecondModel.cls` `TestIntegrationWebChat` (534-593) and class doc 25-27.
  - `web/e2e/api/memory.spec.ts`: the pin step (245-248), the header (22-31) and the comment at 161.
  - `web/e2e/support/memory.ts`: a `pinnedCountOf(session)` read through `irisScript`.

## Tasks & Acceptance

**Execution:**
1. `Memory.cls`: the constants and `Pinned`, and the class comment.
2. `Memory/Ops.cls`: the MessageMap entries, `OnPin` and `OnUnpin` per the matrix, and the class comment (DW-1029).
3. `Agent/Input.cls`: `COREOPENING`, `COREMAX`, `LOGCORE`, `CorePart`, `PinsOf`, the Render order and the ItemId passed to `NoteOf`. Then update `Test/Agent/InputProbe.cls`.
4. `Data/DailyNote.cls`: Build's third argument (DW-977).
5. `Data/Ownership.cls` `DecisionServed`, then `Core/Conversation.cls` `StartsSession` (DW-967).
6. Tests:
   - `Test/Memory/Pins.cls` (new):
     - TestPin;
     - TestCap: pins summing exactly 4,000 succeed, the next is over_cap, and every row is unchanged;
     - TestAlreadyPinned;
     - TestOldRow (DW-1014: a row with stored `Pinned` empty is not in `Memory.Pinned`, and it can be pinned);
     - TestUnpin;
     - TestOtherSession;
     - TestNoSession;
     - TestForgetPinned;
     - TestPinnedOrder (`Memory.Pinned` gives newest pin first and only the session's rows).
   - `RenderMemory`:
     - TestCoreTexts (the opening and `COREMAX` = `PINCAPTOKENS*CHARSPERTOKEN` = 4000 against held copies);
     - TestCoreBlock (the place between persona and notes, newest first, a multi-line pin quoted line by line);
     - TestCoreOnlyAtAStart;
     - TestCoreCap (whole pins; the block at most 4,000 characters, closing blank line included; an older pin is left out);
     - TestCoreReadFailure (through `InputProbe`).
   - `DailyNote`: TestLeavesOutCurrentTurn (an earlier turn kept; the current and a later turn and the current turn's decide decision left out; two arguments, and an unknown ItemId, give the whole note).
   - `OwnershipNotes`: TestDecisionServed (a Usage row of the session is 1, none is 0, and another owner's Usage is 0).
7. `Test/Core/ConversationSessionStart.cls`:
   - In `TestStartsSessionBoundaries`: a no_key fallback turn earlier the same day, with no Usage row, leaves the next turn a start (DW-967); a refusal fallback with a Usage row (`Test.Data.Fixture.Usage`) makes it not a start.
   - New `TestCoreMemoryAtStart` (Rule 1 integration).
   - Search the Test tree for other tests whose first turn falls back and that expect the next turn's context. Update each one.
8. DW-1029:
   - In `CommandsStep3Probe`, dispatch pins to the real handlers.
   - In `MemoryApi:TestPin` real mode, use real rows (the `Memory` helper):
     - own pin 200 and `Pinned` 1;
     - unpin 200 and `Pinned` 0;
     - a pin over the cap 409 over_cap and the row unchanged;
     - another session's ref 404 and its row unchanged;
     - an unknown ref 404.
   - Remove the 500 assertion and fix the doc comments.
   - Re-run `CommandsStep3` and update any pin expectation there.
9. DW-977: update `Test/Bridge/SecondModel.cls:TestIntegrationWebChat`:
   - When both turns are on one local day, no request holds a notes block that quotes `zz17first`, and the first message appears exactly once in the held request.
   - A block on a day crossing still quotes it once (yesterday's).
   - Drop the `notesBlocks > 0` assertion.
   - Update the class doc.
10. DW-1039, in `web/e2e/api/memory.spec.ts`, as LIVE:
    - In the list/search/forget test, replace the 500 step with:
      - pin 200 `{"result":"done"}`, and the list shows `pinned: true`;
      - PANEL's POST and DELETE of the pin on LIVE's ref are 404 `not_found`, and LIVE's row stays pinned;
      - unpin 200 and `pinned: false`;
      - pin again 200;
      - then the existing forget, now of a pinned row: 200, then gone.
    - New test `the pin cap as the LIVE user`:
      - precondition: `pinnedCountOf(LIVE session)` is 0;
      - seed two 2,000-character memories and one short one;
      - pin both long ones: 200 each (exactly 1,000 tokens);
      - pin the short one: 409 `over_cap` with the approved text, and it is not pinned;
      - unpin one long one: 200;
      - pin the short one: 200;
      - remove the rows in `finally`.
    - Update the header and the 161 comment.
11. Spine (bottom up), then `memlog.py append --type decision --text "Story 41.12: MemoryOps handles PinMemory/UnpinMemory under the 1,000-token cap via Memory.Pinned; Agent.Input core-memory block at session start (whole pins, at most 4,000 characters); session start counts only turns that reached a model (DW-967); the session-start note leaves out the current and later turns (DW-977)"`, then `lint_spine.py`.

**Acceptance Criteria:**
- AC 1 (FR-74, AD-21, AD-4): Given a `PinMemory` from web_user for one of the session's memories, when `MemoryOps` handles it, then the pin and the refusal follow the matrix: up to 4,000 characters of pinned text it pins, above that it answers `over_cap` and changes nothing. `UnpinMemory` clears the pin, and forgetting a pinned memory deletes it. Over real HTTP as LIVE, the pin routes answer 200, 409 and 404 as the matrix says (`Test.Memory.Pins`, `MemoryApi:TestPin`, `memory.spec.ts`).
- AC 2 (FR-74): Given the delivered gate, when any origin other than web_user, or a save, or a tool asks, then no pin is set. Only `OnPin` writes `Pinned` 1. This is met by delivered code (see Design Notes) and stays green (`CommandsStep3:TestOrigins`, `Test.Memory.Ops:TestSource`).
- AC 3 (FR-74, AD-7, NFR-27): Given a user item rendered with `sessionStart` 1 for a session with pins, when `Agent.Input.Render` runs, then the core block is placed and bounded as the Always rules say, before the notes (`RenderMemory` core tests).
- AC 4 (Rule 1 integration; AD-21, AD-30): Given a session with a pinned memory, when `Conversation` sends its first turn of the day through the real `Conversation` and `Agent.Input` (`ConversationSessionStart:TestCoreMemoryAtStart`), then that turn request's Input holds the opening and the pin, quoted. A second turn the same day holds neither, and after an unpin, the next session start's Input holds no core block.
- AC 5 (DW-967, AD-21, AD-20): Given an earlier turn of the same local day whose reply decision has no Usage row, when the next turn is sent, then it is a session start. With a Usage row, it is not.
- AC 6 (DW-977): Given a session start, when today's note is built for the turn's item, then the note holds neither the current message's opening nor any later turn's. The Memory card's Notes route still lists the whole day.

## Spec Change Log

## Review Triage Log

## Design Notes

**ADs:**
- AD-1: the gate is unchanged; pins come from web_user only.
- AD-4: the session is set server-side; `MemoryOps` scopes the ref.
- AD-5: no schema change; appended columns may be empty.
- AD-7: the context blocks are rendered only by `Agent.Input`.
- AD-13: the web layer reads nothing new.
- AD-18: local days.
- AD-20: Usage rows are the "reached a model" signal.
- AD-21: memory, core memory, the cap and the session start.
- AD-29 and AD-33: the lanes, with `MemoryOps` as the owner.
- AD-30: Conversation.

No AC contradicts an AD's Rule. DW-967 and DW-977 refine AD-21's "session start" and "daily notes" bullets by additive lines.

**Already met (evidence):**
- Only the person pins:
  - `CommandsIn.cls:235-236` routes `PinMemory` and `UnpinMemory` from web_user only, and neither is in `TOOLVERBS`; `CommandsStep3:TestOrigins` and `TestContextOwnSessionOnly` pin this, with mutations recorded in 41.9.
  - `SaveMemory` has no `Pinned` property, and `OnSave` never sets it, so the `InitialExpression` 0 holds; `Test.Memory.Ops:TestSource` asserts that every new row has Pinned 0.
  - Compaction saves (41.10 and 41.11) are parked.
- Forgetting deletes any own row, pinned or not (`Memory/Ops.cls:135-161`). TestForgetPinned adds the pinned case.
- The routes and their mapper (`Web/Api.cls:1908-1929`) need no change.

**Decided in-stage:**
- **The 4,000-character bound sits in the renderer.** The epics' AC sums text lengths only. Story 41.14's AC says "the block is never over 4,000 characters" with pins up to the cap, so the block's own opening, quotes and line feeds must fit inside 4,000. This follows `PRECEDENTMAX`: whole pins, newest first, no marker line, so no new text is needed.
- Already pinned answers `pinned` and keeps `PinnedAt`, so re-pinning never moves a pin to the front. Unpinning an unpinned own row answers `unpinned`.
- Pin answers carry an empty Message, as `OnSearch` does (41.9), so no new sentence is needed.
- **The DW-967 signal** is a Usage row of the turn's `TurnDecisionRef`. The runner writes a Usage row after every Chat that returns, and after a thrown Chat only when it spent; a precheck writes none (`Decide.cls:1147-1161`, `Agent.cls:724`). A reason list (no_key, ...) would miss a thrown Chat ("error"). Only fallback turns are checked, so ordinary replies cost no read.
  - (inference) A timeout whose Usage row lands after the next turn is sent counts as "not reached". The next turn then repeats the session start, which adds a block and never loses one, the direction `StartsSession` already prefers.
- **DW-977** passes the item's ItemId (always the turn's own; `RetryItemId` is set after rendering, `Conversation.cls:430`). Build looks the turn up, which keeps the result the same on a Busy resend. Only messages and their decide decisions are cut. Incidents, approvals and reminders are no person's words.
- The cap constants live in `OcuTalon.Memory` (AD-21's entry points), so 41.13's "{used}" figure (DW-1030) can reuse them.

**Extend, don't copy:**
- `OnPin`/`OnUnpin` follow `OnForget`.
- `Memory.Pinned` follows `List` and shares `Row`.
- `CorePart` follows `PrecedentPart`'s bound and `NotesPart`'s failure handling.
- `DecisionServed` follows `DecisionChannel`.
- `Test.Memory.Pins` is a new class rather than an addition to `Test.Memory.Ops`, because that class needs the running production and the embedder, and the pin handlers need neither.

**Integration ACs:** AC 4. The consumer, `Conversation` through `Agent.Input`, reads `Memory.Pinned` against real rows, and the observable effect is the turn request's Input. The e2e test (AC 1) exercises the real gate, `MemoryOps` and the routes as LIVE.

**Consumes:**
- 41.9's verbs, routes and `MemoryItemCommand`;
- `Memory.Row`;
- `Ownership.TurnOfItem`;
- the `turnUsage` kind;
- `Test.Data.Fixture.Usage`.

**Consumed-by:**
- 41.13: the Pinned tab's pin and unpin, `over_cap`, and the cap constants for "{used}" (DW-1030 adds its own read through `Ownership.Rows`).
- 41.14: the cap and forget proofs, and the block of at most 4,000 characters.

**Ledger inbox:**
- DW-967: Tasks 5 and 7; AC 5.
- DW-977: Tasks 4, 6 and 9; AC 6.
- DW-1014: the COALESCE read and TestOldRow.
- DW-1029: Tasks 2 and 8.
- DW-1039: Task 10.

None is declined.

**Spec-gate items (for the Planner):**
1. **Public text.**
   - New in code: `COREOPENING` "Your core memory (facts you pinned):" (EXPERIENCE.md:1070; epics.md:10244).
   - Reused unchanged: over_cap "That would go over the 1,000-token limit. Unpin something first." (approved in 41.9).
   - Operator log, not in UX: `LOGCORE` "The core memory of the session could not be read, so it was left out of the input: " (the form of `LOGNOTES`).
   - No other new string. The pin answers' Message is empty.
2. **Guarantee at the boundary.** Pins whose text sums near the cap (above about 3,960 characters, depending on the pin count and line breaks) cannot all fit in a 4,000-character block. The oldest pins are then left out of the session-start input while still counted as pinned. The alternative is to count the block's overhead in the cap check, which would change the epics' "text lengths" wording (a product-number decision). Recommend: keep the renderer bound as planned.
3. **Stored data.** No schema change. `Pinned` and `PinnedAt` are written only by `OnPin` and `OnUnpin`.
4. **Spine lines** (additive, Rule 20):
   - (a) AD-21 Core memory, after line 727: the handlers, `Memory.Pinned`, the cap check, and the block's place and bound, as built.
   - (b) AD-21 "At a session start", after line 756: DW-967's "reached a model" (a fallback turn counts only with a Usage row of its reply decision) and DW-977's cut (the turn being answered and later turns are left out; the Notes route reads the whole day).

## Verification

Run from the worktree root, one command per call, with `timeout: 600000`, each sized to about 150 s. Prefix every `ci/` call with `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-a OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=41 stage=<stage>'`.
- The fresh tag is `e41s12i` and the warm tag `e41s12iw`.
- Never run two test runs in one message.
- Every IRIS MCP call names `server` and `namespace`. Use no real key and no Telegram bot.

**Shared surfaces:**
- `DailyNote.Build`'s signature and `InputProbe.NoteOf`;
- the session-start Input text, which any test that compares a rendered session-start input with a fixed text must cover (search the Test tree for `NOTESOPENING` and `sessionStart`);
- `StartsSession`'s answer after a fallback turn;
- `CommandsStep3Probe`'s dispatch;
- `MemoryApi:TestPin` real mode;
- `memory.spec.ts`' pin step;
- `SecondModel:TestIntegrationWebChat`'s notes assertions.

Every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once) `OCUTALON_RUN_TAG=e41s12iw ci/warm.sh up`. Expected: ready.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e41s12iw ci/iris.sh class <Class>`, once each for:
  - `OcuTalon.Test.Memory.Pins`
  - `OcuTalon.Test.Agent.RenderMemory`
  - `OcuTalon.Test.Data.DailyNote`
  - `OcuTalon.Test.Data.OwnershipNotes`
  - `OcuTalon.Test.Core.ConversationSessionStart`
  - `OcuTalon.Test.Core.CommandsStep3`
  - `OcuTalon.Test.Web.MemoryApi`
  - `OcuTalon.Test.Core.ConversationTurns`

  Expected: passed.
- (once) `OCUTALON_RUN_TAG=e41s12i ci/iris.sh class OcuTalon.Test.Bridge.SecondModel:TestIntegrationWebChat`. It needs the real production, so it runs on a fresh stack; a warm stack keeps the old Conversation running. Expected: passed. If the call nears 150 s, leave it to CI (`shard lane-a@Bridge,Agent`) and say so.
- (once) `bash docker/tests/test-class-rules.sh`, then `bash docker/tests/test-boundaries.sh`. Expected: pass.
- (once) `cd web && npx tsc -p tsconfig.e2e.json`, then `npx playwright test --list e2e/api/memory.spec.ts`. Expected: exit 0, and 5 tests listed.
- (once) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16`. Expected: the 41.9 baseline (`"ok": false`, 10 low `placeholder` findings, nothing new).
- (once) `ci/warm.sh down`, then `ci/iris.sh teardown` with `e41s12i`.
- **Left to CI:** `live:sign-in` (the e2e spec, over 150 s locally), the shards, `bash ci/checks.sh`, and the lead's fresh-environment check.

**Mutations (Rule 19), one per AC at least.** Apply each on the warm stack, observe red, revert, and confirm the files are byte-identical. Record each as `mutation: ... -> ... red`.
- AC 1: the cap comparison `>` becomes `>=` → `Pins:TestCap` red (exactly 4,000 refused). `MemoryOps` without the `PinMemory` MapItem → `MemoryApi:TestPin` red (real mode 500).
- DW-1014: the already-pinned check `row.Pinned '= 0` → `Pins:TestOldRow` red.
- AC 3: `CorePart` placed after `NotesPart` → `RenderMemory:TestCoreBlock` red. `COREMAX` 4000 becomes 4100 → `TestCoreCap` red.
- AC 4: `CorePart` ignores `sessionStart` → `ConversationSessionStart:TestCoreMemoryAtStart` red (a second turn holds the block).
- AC 5: `StartsSession` without the reached-model condition → `TestStartsSessionBoundaries` red.
- AC 6: `Build` ignores `itemId` → `DailyNote:TestLeavesOutCurrentTurn` red, and `SecondModel:TestIntegrationWebChat` red (on the fresh stack, once).
- DW-1039: CI only. Not demonstrable locally, as in 41.9.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
