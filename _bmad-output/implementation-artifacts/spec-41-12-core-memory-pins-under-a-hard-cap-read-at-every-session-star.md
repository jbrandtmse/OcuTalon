---
title: "Story 41.12: Core memory: pins under a hard cap, read at every session start"
type: 'feature'
created: '2026-11-09'
status: 'done'
baseline_revision: 'b9bbcd53a7ed2bfd23c4fbf3b5d3c889e45001f6'
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
- **The cap (FR-74, NFR-27; Contest Planner ruling 2026-11-09).** The core-memory block, heading and quotes included, is capped at 4,000 characters (1,000 tokens at 4 characters a token). A pin is refused with Outcome `over_cap`, Ok 0 (the existing full answer; no new message), and nothing changes, when the rendered core-memory block (heading, quotes and line breaks included) with the new pin would pass 4,000 characters. One computation renders the block for both the cap check and `Agent.Input.Render` (and the card's remaining-space figure, 41.13, uses the same one). Nothing is ever unpinned to make room, and a pinned fact is NEVER left out of the input while it shows as pinned. A test pins the pin that would cross the line by one character.
  - Use the epics' numbers as given: 1,000 tokens, 4 characters a token, 4,000 characters for the block.
  - The constants `PINCAPTOKENS = 1000` and `CHARSPERTOKEN = 4` are defined once, in `OcuTalon.Memory`.
- **Lock and scope.** The cap sum and the pin write happen under `MemoryOps`' lock `^OcuTalon.Memory(sessionRef)`. The ref must be the command's own session's row: an unknown ref and another session's ref both answer `not_found`, the same way (DW-740).
- **DW-1014.** The pinned read and the cap sum use `COALESCE(Pinned, 0) = 1`. A row saved before Story 41.8 (stored `Pinned` empty) is not pinned, and it can be pinned.
- **The core-memory block.** It is only for an item with provenance `user` whose context has `sessionStart` 1, and whose owner is a session, never `eval`, `instance` or empty.
  - It opens with `"Your core memory (facts you pinned):"` on its own line (EXPERIENCE.md:1070), then each pin through `Quoted`, newest pin first (`PinnedAt DESC`, then row `ID DESC`), then a blank line.
  - Every pinned memory is in the block, whole. Because the cap is checked on the rendered block, the block, the closing blank line included, is never over 4,000 characters (`COREMAX`), and no pin is left out.
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
| Pin within cap | own unpinned memory; the rendered block with it ≤ 4,000 characters | `Pinned` 1, `PinnedAt` now (UTC to the second); Ok 1, Outcome `pinned`; route 200 `{"result":"done"}` | none |
| Exactly at cap | the rendered block with it = 4,000 characters | pinned | none |
| Over cap | the rendered block with it = 4,001 characters or more (the test: exactly one character over) | Ok 0, `over_cap`; no row changes; route 409 with the approved over_cap text | none |
| Already pinned | own pinned memory | Ok 1, `pinned`; `PinnedAt` unchanged; no cap re-check | none |
| Pre-41.8 row | own row whose stored `Pinned` is empty | treated as unpinned; the pin follows the cap rule; not counted in the sum before it is pinned | none |
| Unpin | own memory, pinned or not | `Pinned` 0, `PinnedAt` ""; Ok 1, Outcome `unpinned`; route 200 | none |
| Other session / unknown ref | ref of another session's row, or no row | Ok 0, `not_found`; nothing changes; route 404 | none |
| No session row | command's `SessionRef` has no `Data.Session` | `no_session` (as `OnForget`); route 500 | none |
| Lock or save fails | lock not free in 5 s; `%Save` error; exception | `failed` (shared `Failed`), one Type 3 warning | route 500 |
| Forget a pinned memory | own pinned row | deleted (existing `OnForget`); gone from `Memory.Pinned` and from the next session-start block | none |
| Session start with pins | user item, `sessionStart` 1, session has pins | preamble, persona block, core block, notes block, then text | a failed pinned read: no core block, one warning, the rest rendered |
| Block at the bound | pins whose rendered block is exactly 4,000 characters | every pin, whole; the block is 4,000 characters; nothing is left out | none |
| Not a session start | no `sessionStart`, untrusted item, owner eval/instance/"" | no core block, and no read | none |
| DW-967 | earlier same-day turn ended in a fallback whose reply decision has no Usage row (no_key, daily_cap, budget, too_large, a thrown Chat) | it does not count, so the next turn is a session start | a failed read: counts as a start, with one warning (as today) |
| DW-967 reached | earlier same-day fallback turn whose reply decision has a Usage row (e.g. refusal, cut_off) | counts, so the next turn is not a start | none |
| DW-977 | session start; today's note | leaves out the turn with the item's ItemId, every later turn of the session (CreatedAt, then ID), and the decide decisions those turns made | an ItemId that names no turn of the session: the whole note, as today |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless given in full. Line numbers are as of `0183ce4f`; nothing under `src/`, `web/`, `docker/` or `ci/` has changed since (checked at `65d8f389`).

**The one block computation (the cap ruling).** Two methods, one formatter:
- `Agent.Input.CoreBlock(texts As %DynamicArray) As %String` (new, public, pure): the exact text Render inserts for the core memory. `""` for no texts; otherwise `COREOPENING`, then for each text `LF_..Quoted(text)`, then `LF LF`. It is the only place the block is formatted (AD-7: `Agent.Input` is the one renderer). No SQL, no reads.
- `Memory.CoreBlock(sessionRef, candidate As %String = "", Output block As %String) As %Status` (new, public): reads `Pinned` for the session, puts `candidate` (a text) first when it is not `""`, and answers `Agent.Input.CoreBlock` of the texts. The cap check (with the candidate) and `Agent.Input.CorePart` (without) both call it. An empty session is an error status, with `block` `""`.
- The cap: `$Length(block) > ##class(OcuTalon.Memory).#COREMAX` refuses.

Files:
- `Memory.cls`:
  - Add `Parameter PINCAPTOKENS = 1000;`, `Parameter CHARSPERTOKEN = 4;` and `Parameter COREMAX = {..#PINCAPTOKENS * ..#CHARSPERTOKEN};` (the brace form as `NEARESTSQL` at 45).
  - Add `ClassMethod Pinned(sessionRef, Output rows As %DynamicArray) As %Status`, a sibling of `List` (129-150): `SELECT Ref, Text, SavedAt, Origin, Source, Pinned FROM ... WHERE SessionRef = ? AND COALESCE(Pinned, 0) = 1 ORDER BY PinnedAt DESC, ID DESC`; rows shaped by `Row` (197); an empty session is an error status.
  - Add `CoreBlock` (above).
  - Class comment (1-18): add `Pinned`, `CoreBlock` and the cap constants. `List` and `Search` are unchanged.
- `Memory/Ops.cls`:
  - MessageMap (44-57): add `PinMemory`→`OnPin`, `UnpinMemory`→`OnUnpin`.
  - Both handlers follow `OnForget` (135-161): the no_session check, `Lock`, `RefIndexOpen` with the owner check, Try/Catch, release.
  - `OnPin`: an own row already pinned (`+row.Pinned = 1`) answers `pinned` with no write. Otherwise `Memory.CoreBlock(request.SessionRef, row.Text, .block)`; an error status is `Failed`; over `COREMAX` answers `Answer(.response, 0, "over_cap", "")` and writes nothing; else `Pinned` 1, `PinnedAt` `Data.Time.NowUtc()`, `%Save`, `Answer(.response, 1, "pinned", "", row.Ref)`.
  - `OnUnpin`: own row → `Pinned` 0, `PinnedAt` "", `%Save`, `unpinned`.
  - Reuse `Answer` and `Failed` (204-235). The pin answers carry an empty Message, as `OnSearch` does (185).
  - Class comment: the two handlers, and line 22 for DW-1029 (SaveMemory from origin tool; ForgetMemory from tool or web_user; PinMemory, UnpinMemory and SearchMemory from web_user only).
- `Agent/Input.cls`:
  - `Render` (48): a user item becomes `preamble_LF LF_PersonaPart_CorePart_NotesPart_text`.
  - New private `CorePart(item, context)`: `""` unless provenance `user`, `..Flag(context, "sessionStart")` and `##class(OcuTalon.Bridge.Approval).IsRef(item.SessionRef)` (as `PrecedentPart` at 107; `src/bridge/cls/OcuTalon/Bridge/Approval.cls:288`). Then `..CoreOf(item.SessionRef)` in a Try/Catch modelled on `NotesPart` (76-90): a throw gives `""` and one `LOGCORE` warning (redacted). It inserts what `CoreOf` answers unchanged: no bound, no cut.
  - New private seam `CoreOf(sessionRef)`: `Memory.CoreBlock(sessionRef, "", .block)`, throws on an error status, answers `block`.
  - New public `CoreBlock(texts)` (above).
  - Add `Parameter COREOPENING = "Your core memory (facts you pinned):";` and `Parameter LOGCORE = "The core memory of the session could not be read, so it was left out of the input: ";` beside `NOTESOPENING` and `LOGNOTES` (154, 169).
  - `NotesPart`/`NoteOf` (72-98): pass `item.ItemId` as `Build`'s new third argument.
  - Class comment (1-31): the core block's place, its form, `CoreBlock`, and that it is never cut.
- `Data/DailyNote.cls`: `Build(sessionRef, day, itemId As %String = "")` (58). When `itemId` names a turn of the session (`Ownership.TurnOfItem` through the `TurnOf` seam at 188), `Messages` (127-137) skips that turn and every later turn by (CreatedAt, ID), and `Decisions` (141-160) skips decisions whose `TurnOf(row.ItemId)` is a skipped turn. Update the header (1-16).
- `Core/Conversation.cls` `StartsSession` (443-474): the loop condition (462) also requires the earlier turn to have reached a model, either `FallbackReason = ""` or its `TurnDecisionRef` has a Usage row of the session (`Ownership.DecisionServed`). A read error returns 1 with one `LOGSTART` warning. Update the doc comment and header 15-17.
- `Data/Ownership.cls`: add `DecisionServed(decisionRef, sessionRef, Output sc) As %Boolean`, 1 when the decision has a Usage row of the session. Sibling of `DecisionChannel` (769-781), reading the `turnUsage` kind (996). Added lines only.
- `Test/Agent/InputProbe.cls`: the `NoteOf` override (7) takes and passes the third argument. Add a `CoreOf` override that throws while `^||InputProbe("failCore")` is set, else `##super`.
- Read only:
  - `Core/CommandsIn.cls:235-236`;
  - `Web/Api.cls:1908-1929` `MemoryItemCommand` (Ok→200, not_found 404, over_cap 409, else 500);
  - `Msg/Command/PinMemory.cls`;
  - `src/bridge/.../Process/Decide.cls:1147-1161, 1271-1281, 1595-1638` (a precheck or a thrown Chat with no spend writes no Usage row);
  - `Test/Data/Fixture.cls:22, 35, 160` (`Session`, `Turn`, `Usage`);
  - `Test/Web/MemoryApi.cls:674-693` (`Memory`: a fixture row with a vector of ones, `pinned` optional);
  - `web/e2e/support/memory.ts:72` (`seedMemory`).
- Tests:
  - `Test/Memory/Pins.cls` (new, area Memory, shard lane-a). Safe on a slot: it calls the handlers on a shadow instance of `OcuTalon.Memory.Ops`, with a fixture session and rows saved directly with a vector of ones (`Test.Memory.Fixture.ToVector`, as `MemoryApi.Memory`). No embedder, no production.
  - `Test/Agent/RenderMemory.cls`: the core-block tests.
  - `Test/Data/DailyNote.cls`: the DW-977 cut.
  - `Test/Data/OwnershipNotes.cls`: `DecisionServed`.
  - `Test/Core/ConversationSessionStart.cls`: DW-967 cases in `TestStartsSessionBoundaries` (183-213, after the refused case at 198-201), and the integration test. Shadow instances, no production.
  - `Test/Core/CommandsStep3Probe.cls:21-22`: dispatch `PinMemory`→`OnPin`, `UnpinMemory`→`OnUnpin`.
  - `Test/Core/CommandsStep3.cls`: any pin outcome that is now the handler's.
  - `Test/Web/MemoryApi.cls` `TestPin` (432-465): the real-mode tail and its doc comment (shadow instances, no production).
  - `Test/Bridge/SecondModel.cls` `TestIntegrationWebChat` (534-593) and class doc 25-27.
  - `web/e2e/api/memory.spec.ts`: the pin step (245-248), the header (22-31) and the comment at 161.
  - `web/e2e/support/memory.ts`: `pinnedCountOf(session)` through `irisScript`, beside `memoryExists` (94).

## Tasks & Acceptance

**Execution:**
1. `Memory.cls`: the three constants, `Pinned`, `CoreBlock`, the class comment.
2. `Agent/Input.cls`: `COREOPENING`, `LOGCORE`, `CoreBlock`, `CorePart`, `CoreOf`, the Render order, the ItemId passed to `NoteOf`, the class comment. Then `Test/Agent/InputProbe.cls`.
3. `Memory/Ops.cls`: the MessageMap entries, `OnPin` and `OnUnpin` per the matrix, the class comment (DW-1029).
4. `Data/DailyNote.cls`: Build's third argument (DW-977).
5. `Data/Ownership.cls` `DecisionServed`, then `Core/Conversation.cls` `StartsSession` (DW-967).
6. Tests. Expected lengths are held arithmetic in the test, never read from the code under test: the opening is 36 characters, each single-line pin adds `3 + its length` (LF and `"> "`), the close adds 2. Two single-line pins of 2,000 and 1,956 characters make exactly 4,000.
   - `Test/Memory/Pins.cls` (new):
     - TestPin;
     - TestCap: pin A (2,000) → pinned. Candidate B1 (1,957, one over) → `over_cap`, Ok 0, and A and B1 unchanged (`Pinned`, `PinnedAt`); `$Length` of `Memory.CoreBlock(session, B1's text)` is 4,001. Candidate B2 (1,956) → pinned, and `Memory.CoreBlock(session)` is 4,000. A third pin of 1 character → `over_cap`;
     - TestCapRendered: pin A (2,000); a candidate of 1,950 characters holding 5 line feeds (text sum 3,950, block 4,004) → `over_cap`;
     - TestAlreadyPinned; TestOldRow (DW-1014: stored `Pinned` empty is not in `Pinned`, and can be pinned); TestUnpin; TestOtherSession; TestNoSession; TestForgetPinned;
     - TestPinnedOrder (`Memory.Pinned`: newest pin first, then ID DESC, and only the session's rows).
   - `RenderMemory`:
     - TestCoreTexts: `COREOPENING` against a held copy; `Memory` `PINCAPTOKENS` 1000, `CHARSPERTOKEN` 4, `COREMAX` 4000;
     - TestCoreForm: `Agent.Input.CoreBlock(["zz new", "zz old"_CR LF_"zz line"])` equals a held string, and `CoreBlock([])` is "";
     - TestCoreBlock: the place between persona and notes, newest pin first, a multi-line pin quoted line by line;
     - TestCoreAgrees (byte for byte): pins whose block is exactly 4,000; the core block in Render's output (between the persona part and the notes opening) equals `Memory.CoreBlock(session)`, has every pin whole, and its length (4,000) equals the length `Memory.CoreBlock(session, text)` gave for the last pin just before it was pinned;
     - TestCoreNeverCut: pins written directly whose block is about 4,100 (only a direct write can make one) → Render holds every pin whole;
     - TestCoreOnlyAtAStart; TestCoreReadFailure (through `InputProbe` `failCore`: no core block, one `LOGCORE` warning, redacted, the rest rendered).
   - `DailyNote`: TestLeavesOutCurrentTurn (an earlier turn kept; the current and a later turn and the current turn's decide decision left out; two arguments, and an unknown ItemId, give the whole note).
   - `OwnershipNotes`: TestDecisionServed (a Usage row of the session is 1, none is 0, another owner's Usage is 0).
7. `Test/Core/ConversationSessionStart.cls`:
   - In `TestStartsSessionBoundaries`: a no_key fallback turn earlier the same day with no Usage row leaves the next turn a start (DW-967); a refusal fallback with a Usage row (`Test.Data.Fixture.Usage`) makes it not a start.
   - New `TestCoreMemoryAtStart` (Rule 1 integration).
   - Search the Test tree for tests whose first turn falls back and expect the next turn's context, and for tests comparing a rendered session-start input with a fixed text; update each.
8. DW-1029: `CommandsStep3Probe` dispatches pins to the real handlers. `MemoryApi:TestPin` real mode, with real rows (`Memory` helper): own pin 200 and `Pinned` 1; unpin 200 and `Pinned` 0; with a pinned 2,000-character row, a 1,957-character row's pin 409 `over_cap` and the row unchanged; another session's ref 404 and its row unchanged; an unknown ref 404. Remove the 500 assertion, fix the doc comments, re-run `CommandsStep3` and update any pin expectation.
9. DW-977: `Test/Bridge/SecondModel.cls:TestIntegrationWebChat`: on one local day, no request holds a notes block quoting `zz17first`, and the first message appears exactly once in the held request; across a day change a block still quotes it once (yesterday's). Drop the `notesBlocks > 0` assertion; update the class doc.
10. DW-1039, `web/e2e/api/memory.spec.ts`, as LIVE:
    - In the list/search/forget test, replace the 500 step: pin 200 `{"result":"done"}` and the list shows `pinned: true`; PANEL's POST and DELETE of the pin on LIVE's ref are 404 `not_found` and LIVE's row stays pinned; unpin 200 and `pinned: false`; pin again 200; then the existing forget of the now pinned row: 200, then gone.
    - New test `the pin cap as the LIVE user`: precondition `pinnedCountOf(LIVE session)` is 0; seed single-line memories of 2,000, 1,956 and 2 characters; pin the first two: 200 each (block exactly 4,000); pin the short one: 409 `over_cap` with the approved text, and it is not pinned; unpin the 1,956 one: 200; pin the short one: 200; remove the rows in `finally`.
    - Update the header and the comment at 161.
11. `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`, bottom up (the approved lines, `[ADDED 2026-11-09, Story 41.12]`): (b) after AD-21 line 756 (session start): DW-967's "reached a model" and DW-977's cut; (a) after line 727 (core memory): `MemoryOps` handles the pin verbs; the cap is the rendered block's length (`Memory.CoreBlock`, formatted only by `Agent.Input.CoreBlock`) against `COREMAX` 4,000; the block's place; it is never cut. Then `uv run --no-cache _bmad/scripts/memlog.py append --workspace <that folder> --type decision --text "Story 41.12: MemoryOps pins under the cap measured on the rendered core-memory block (Memory.CoreBlock / Agent.Input.CoreBlock, at most 4,000 characters, never cut); the block goes after the persona block at session start; session start counts only turns that reached a model (DW-967); the session-start note leaves out the current and later turns (DW-977)"`, then `lint_spine.py` (Verification).

**Acceptance Criteria:**
- AC 1 (FR-74, AD-21, AD-4): Given a `PinMemory` from web_user for one of the session's memories, when `MemoryOps` handles it, then it pins while the rendered block with the pin is at most 4,000 characters and answers `over_cap` and changes nothing at 4,001, as the matrix says; `UnpinMemory` clears the pin and forgetting a pinned memory deletes it. Over real HTTP as LIVE, the pin routes answer 200, 409 and 404 as the matrix says, and PANEL's write on LIVE's ref is 404 (`Test.Memory.Pins`, `MemoryApi:TestPin`, `memory.spec.ts`).
- AC 2 (FR-74): Given the delivered gate, when any origin other than web_user, a save, or a tool asks, then no pin is set; only `OnPin` writes `Pinned` 1. Met by delivered code (Design Notes) and stays green (`CommandsStep3:TestOrigins`, `Test.Memory.Ops:TestSource`).
- AC 3 (FR-74, AD-7, NFR-27): Given a user item rendered with `sessionStart` 1 for a session with pins, when `Agent.Input.Render` runs, then the core block sits after the persona block and before the notes, holds every pin whole newest first, and is byte for byte the `Memory.CoreBlock` the cap check measures (`RenderMemory` core tests).
- AC 4 (Rule 1 integration; AD-21, AD-30): Given a session with a pinned memory, when `Conversation` sends its first turn of the day through the real `Conversation` and `Agent.Input` (`ConversationSessionStart:TestCoreMemoryAtStart`), then that turn request's Input holds the opening and the pin, quoted; a second turn the same day holds neither; after an unpin, the next session start holds no core block.
- AC 5 (DW-967, AD-21, AD-20): Given an earlier turn of the same local day whose reply decision has no Usage row, when the next turn is sent, then it is a session start; with a Usage row, it is not.
- AC 6 (DW-977): Given a session start, when today's note is built for the turn's item, then it holds neither the current message's opening nor any later turn's, and the Notes route still lists the whole day.

## Spec Change Log

- 2026-11-09 (Contest Planner rulings on the spec-gate items, relayed by the orchestrator): (1) CAP: the alternative is ruled. The core-memory block, heading and quotes included, is capped at 4,000 characters (1,000 tokens at 4 characters a token); a pin is refused with the existing `over_cap` answer when the rendered block would pass 4,000; a pinned fact is never left out of the input while it shows as pinned; 41.14's "never over 4,000 characters" holds exactly; 41.13's remaining-space figure uses the same computation; a test pins the pin that crosses the line by one character. Applied to the intent block (Always: the cap; the core-memory block; the matrix rows) and to epics.md Story 41.12 as a Rule 5 amendment `[AMENDED 2026-11-09, Contest Planner ruling]`. Re-planned (status draft). (2) The operator log line "The core memory of the session could not be read, so it was left out of the input: " is APPROVED. The heading stays "Your core memory (facts you pinned):" (EXPERIENCE.md:1070). (3) The two additive AD-21 spine lines, marked `[ADDED 2026-11-09, Story 41.12]`, are APPROVED.
- 2026-11-09 (re-plan after the ruling): Code Map, Tasks, ACs, Design Notes and Verification brought in line. The renderer's bound and its cut are gone; the cap check measures `Memory.CoreBlock` with the candidate; `COREMAX` moves to `OcuTalon.Memory`, derived from the two constants; the `PinsOf` seam becomes `CoreOf`; TestCap, TestCapRendered, TestCoreAgrees and TestCoreNeverCut replace the text-sum tests; the e2e cap test seeds 2,000 + 1,956 characters (two 2,000-character pins no longer fit). The intent block is unchanged. KEEP: DW-967, DW-977, DW-1014, DW-1029, DW-1039 and the LIVE/PANEL route tests as planned.

## Review Triage Log

### 2026-11-09 — Review pass
- verdicts: 25 findings — high 1, medium 0, low 12, false 12, maybe-false 0 (Intent Alignment reported no findings; its description is in the note below)
- findings:
  - `[high]` `[patch]` (Blind Hunter 1, Edge Case 1+2, Verification Gap 1; one root cause) `Test/Memory/OpsProbe.cls` was overwritten with a Lock-only probe, removing `Tunes`, `SourceFails`, `SourceFailText`, `TurnOf` and `Tuned` that `Test.Memory.Ops` uses (made in this stage's review pass) — restored the file from git (byte-identical to HEAD) and moved the lock switch to a new `Test/Memory/PinsProbe.cls` that `Pins:TestLockBusy` uses; `Test.Memory.Ops` run green on the warm stack.
  - `[false]` `[reject]` (Blind Hunter 2, Edge Case 5) a failed core-memory read drops the block, so a pinned fact is left out — the intent block says a failing read leaves the block out with one warning; "never cut" is about the cap, and the log line is the signal.
  - `[low]` `[reject]` (Blind Hunter 3) `StartsSession` reads one Usage query per earlier fallback turn — only fallback turns pay it, the loop stops at the first turn that reached a model, and a fix adds a cache.
  - `[low]` `[reject]` (Blind Hunter 4) no cap test with CR, VT, FF or U+2028 separators — the cap and the render call the same `CoreBlock`, so they cannot disagree; `TestCoreForm` pins CRLF.
  - `[low]` `[reject]` (Blind Hunter 5) no tests for an empty-text pin, a pin while the block is already over the cap, or a failed `%Save` — an empty-text row cannot be saved by `SaveMemory`; the already-over case is refused by the same comparison; the save-failure branch is the shared `Failed`.
  - `[low]` `[reject]` (Blind Hunter 6) a `RetryItemId` decision maps to no turn so `Skipped` keeps it — its line holds an outcome and no message text, so the current message is not quoted.
  - `[low]` `[patch]` (Blind Hunter 7a, 7b) two garbled comments (`Agent.Input` class comment, `StartsSession` header) — both rewritten; the `MemoryTurns` assertion is looser than its header but a session start there holds one message, so the check is exact.
  - `[low]` `[reject]` (Blind Hunter 8) no handler-level same-second tie test for `PinnedAt` — `TestPinnedOrder` pins the row-id tiebreak with a hand-made tie.
  - `[false]` `[reject]` (Edge Case 3) `Served` reads only `TurnDecisionRef` — the spec's signal is the reply decision's Usage row.
  - `[false]` `[reject]` (Edge Case 4) an already-pinned memory is answered without a cap check — the matrix row says so (no cap re-check).
  - `[false]` `[reject]` (Verification Gap 2 and Intent Alignment 2, same root as the OpsProbe row, counted there) AC 2 stays green: `Test.Memory.Ops` passes.
  - `[low]` `[patch]` (Verification Gap 2b) AC 2 had no `mutation:` line — recorded: `OnSave` setting `Pinned` 1 turns `Test.Memory.Ops` red; the gate's own mutations are 41.9's.
  - `[low]` `[patch]` (Verification Gap 3) no mutation lines for `TestOtherSession`, `TestUnpin`, `TestNoSession` — three mutations applied, each red, reverted, lines recorded.
  - `[low]` `[reject]` (Verification Gap 4) `TestMessageMap` is a text match, not a dispatch — the real dispatch is the LIVE e2e spec, left to CI by the spec.
  - `[low]` `[reject]` (Verification Gap 5) `TestCoreMemoryAtStart` asserts nothing if the two turns straddle local midnight — the existing `StartIfNewDay` pattern; a fix adds a branch for a one-minute window.
  - `[low]` `[patch]` (Verification Gap 6) a fixture session in `TestStartsSessionBoundaries` was not tracked for cleanup — now made through the class's `Session` helper.
  - `[low]` `[reject]` (Verification Gap 7) the `SecondModel` day-change branch can no longer fail if the yesterday block is absent — it only runs across midnight, and the same-day branch has its mutation.
  - `[false]` `[reject]` (Verification Gap other 1) `OpsProbe.cls` listed twice in the diff — an artifact of the staged diff; the working tree held one version (now the HEAD one).
  - `[false]` `[reject]` (Verification Gap other 2, Blind Hunter 5) empty candidate text not counted by `CoreBlock` — an empty-text row cannot exist.
  - `[false]` `[reject]` (Verification Gap other 3) `PinnedAt` window assertion — the reviewer found it sound.
  - `[false]` `[reject]` (Verification Gap other 4) the e2e cap test's precondition is state it did not create — it fails loudly, and the spec asks for the precondition.
  - `[false]` `[reject]` (Verification Gap other 5) `pinnedCountOf` and the cap test have no local executed host — the spec leaves `live:sign-in` to CI.
  - `[false]` `[reject]` (Edge Case: `CorePart` unbounded) the spec says "no bound, no cut"; the cap is enforced at pin time.
  - `[false]` `[reject]` (Intent Alignment 1) route and production-dispatch expectations are exercised by handler tests and the LIVE e2e spec — the e2e run is CI's by the spec.
  - `[false]` `[reject]` (Intent Alignment 5, 6) fallback with an empty decision, and the shared LIVE session — the first is tested and consistent; the second as above.
- note: the Intent Alignment auditor reported readings and surfaces only (handler-level and function-level tests, with the route and dispatch layer carried by the LIVE e2e spec); its one concrete divergence, the replaced `OpsProbe`, is the high row above.

## Design Notes

**ADs:**
- AD-1: the gate is unchanged; pins come from web_user only.
- AD-4: the session is set server-side; `MemoryOps` scopes the ref.
- AD-5: no schema change; appended columns may be empty.
- AD-7: `Agent.Input` is the one renderer, so the block's form lives only in `Agent.Input.CoreBlock`; `Memory.CoreBlock` reads and delegates.
- AD-13: the web layer reads nothing new and never calls `Memory.*`.
- AD-18: local days.
- AD-20: Usage rows are the "reached a model" signal.
- AD-21: memory, core memory, the cap and the session start.
- AD-29 and AD-33: the lanes, with `MemoryOps` as the only writer of `Data.Memory`.
- AD-30: Conversation.

No AC contradicts an AD's Rule. AD-21's "at most 1,000 tokens, estimated at 4 characters a token" holds: the estimate is now of the rendered block, which is what reaches the model. DW-967 and DW-977 refine AD-21's "session start" and "daily notes" bullets by additive lines.

**Already met (evidence):**
- Only the person pins: `CommandsIn.cls:235-236` routes `PinMemory` and `UnpinMemory` from web_user only, and neither is in `TOOLVERBS` (`CommandsStep3:TestOrigins`, `TestContextOwnSessionOnly`, mutations recorded in 41.9). `SaveMemory` has no `Pinned` property and `OnSave` never sets it (`Test.Memory.Ops:TestSource`: every new row has Pinned 0). Compaction saves (41.10, 41.11) are parked.
- Forgetting deletes any own row, pinned or not (`Memory/Ops.cls:135-161`); TestForgetPinned adds the pinned case.
- The routes and their mapper (`Web/Api.cls:1908-1929`) need no change.

**Decided in-stage:**
- **What "the rendered block" is.** Exactly the string Render inserts between the persona part and the notes part: the opening, each pin as `LF` + `Quoted(text)`, and the closing blank line (`LF LF`). Its `$Length` is measured, closing blank line included, as `PRECEDENTMAX` counts its block. So 41.14's "never over 4,000 characters" holds for any reading of the block's end.
- **One computation, two layers.** `Agent.Input.CoreBlock(texts)` is the pure formatter; `Memory.CoreBlock(sessionRef, candidate)` reads the pins and calls it. The cap check and `CorePart` call `Memory.CoreBlock`, so they cannot disagree. 41.13 cannot run `Memory`'s SQL from the web layer (AD-13), so its figure comes from `Agent.Input.CoreBlock` over the pinned texts its own read returns (DW-1030), or from a `MemoryOps` read verb that calls `Memory.CoreBlock`.
- **The candidate goes first** (it would be the newest pin). Order never changes the length, so a same-second `PinnedAt` tie cannot make the check and the render differ.
- **The bound is enforced at pin time only.** `CorePart` never cuts, so a pinned fact is never left out. Only a direct write could make a block over 4,000; TestCoreNeverCut pins that even then nothing is dropped.
- **A refused single pin.** A text of up to 2,000 characters with many line breaks can render over 4,000 by itself (each line adds `"> "`), so even a first pin can be `over_cap`. That follows the ruling; the card's existing text ("Unpin something first.") is 41.13's.
- `COREMAX` is in `OcuTalon.Memory`, derived from `PINCAPTOKENS * CHARSPERTOKEN`, so the number is written once.
- The Approach's "sums the pinned texts through `Memory.Pinned`" is read under the amended Always rule: the check measures the rendered block, which `Memory.CoreBlock` builds from `Memory.Pinned`'s rows.
- Already pinned answers `pinned` and keeps `PinnedAt`, so re-pinning never moves a pin to the front. Unpinning an unpinned own row answers `unpinned`. Pin answers carry an empty Message, as `OnSearch` does.
- **The DW-967 signal** is a Usage row of the turn's `TurnDecisionRef`. The runner writes one after every Chat that returns, and after a thrown Chat only when it spent; a precheck writes none (`Decide.cls:1147-1161`, `Agent.cls:724`). A reason list would miss a thrown Chat ("error"). Only fallback turns are checked, so ordinary replies cost no read. (inference) A timeout whose Usage row lands after the next turn is sent counts as "not reached"; the next turn then repeats the session start, which adds a block and never loses one.
- **DW-977** passes the item's ItemId (always the turn's own; `RetryItemId` is set after rendering, `Conversation.cls:430`). Build looks the turn up, so a Busy resend gives the same result. Only messages and their decide decisions are cut; incidents, approvals and reminders are no person's words.

**Decided in-stage (implement):**
- `Conversation` gets a private seam `Served(decisionRef, sessionRef, Output sc)` over `Ownership.DecisionServed`, so `ConversationStartProbe` can fail it (`^||ConversationStartProbe("failServed")`) and the matrix row "a failed read counts as a start, with one warning" is tested.
- `DailyNote.Build` reads the turn only when `itemId` is not empty (two arguments and `""` make no extra read, so the Notes route and `DailyNoteProbe`'s failing `TurnOf` are unchanged).
- `Pins:TestMessageMap` was added: the probe of the real gate dispatches by class name, so only the compiled map pins the production's delivery of the two verbs.
- `CommandsStep3:TestRealStubOwners` now also sends `PinMemory` and `UnpinMemory` (origin `web_user`) to the real handlers (no_session for a session with no row).
- `Agent.MemoryTurns:TestNotesAtSessionStart` asserted the old behaviour (the notes hold the current message's own line); it now asserts there is none (DW-977).
- The unpin answer carries the memory's Ref, as the pin answer does; both carry an empty Message.
- `Memory.CoreBlock` reads `Agent.Input.CoreBlock` (the Memory area calls Agent, as it already calls Bridge); `test-class-rules.sh` and `test-boundaries.sh` pass.

**Extend, don't copy:**
- `OnPin`/`OnUnpin` follow `OnForget`.
- `Memory.Pinned` follows `List` and shares `Row`; `Memory.CoreBlock` uses `Pinned`.
- `Agent.Input.CoreBlock` reuses `Quoted`; `CorePart` follows `NotesPart`'s failure handling and `PrecedentPart`'s owner check; `CoreOf` follows the `NoteOf` seam.
- `DecisionServed` follows `DecisionChannel`.
- `Test.Memory.Pins` is a new class, not an addition to `Test.Memory.Ops`, because that class needs the running production and the embedder, and the pin handlers need neither.

**Integration ACs:** AC 4 (the consumer, `Conversation` through `Agent.Input`, reads `Memory.CoreBlock` against real rows; the observable effect is the turn request's Input) and AC 3's TestCoreAgrees (the render equals the cap's computation). AC 1's e2e test exercises the real gate, `MemoryOps` and the routes as LIVE.

**Consumes:** 41.9's verbs, routes and `MemoryItemCommand`; `Memory.Row`; `Agent.Input.Quoted`; `Ownership.TurnOfItem`; the `turnUsage` kind; `Test.Data.Fixture.Usage`.

**Consumed-by:**
- 41.13: the Pinned tab's pin and unpin and `over_cap`; "{used} of 1,000 tokens (estimated)" from the same block computation (`Agent.Input.CoreBlock` over its pinned read, or `Memory.CoreBlock` behind a `MemoryOps` read verb) and `CHARSPERTOKEN` (DW-1030).
- 41.14: the cap and forget proofs, and the block of at most 4,000 characters.

**Ledger inbox:**
- DW-967: Tasks 5 and 7; AC 5.
- DW-977: Tasks 4, 6 and 9; AC 6.
- DW-1014: the COALESCE read and TestOldRow.
- DW-1029: Tasks 3 and 8.
- DW-1039: Task 10.

None is declined.

**Spec-gate items (for the Planner):**
1. **Public and model-facing text.**
   - `COREOPENING` "Your core memory (facts you pinned):" (EXPERIENCE.md:1070; epics.md): approved (2026-11-09).
   - over_cap "That would go over the 1,000-token limit. Unpin something first.": reused unchanged, approved in 41.9; no new message.
   - Operator log `LOGCORE` "The core memory of the session could not be read, so it was left out of the input: ": approved (2026-11-09).
   - No other new string. The pin answers' Message is empty.
2. **Stored data.** No schema change. `Pinned` and `PinnedAt` are written only by `OnPin` and `OnUnpin`.
3. **Spine lines** (additive, Rule 20): approved (2026-11-09). Their text now says the cap is measured on the rendered block (Task 11).

## Verification

Run from the worktree root, one command per call, `timeout: 600000`, each sized to about 150 s. Prefix every `ci/` call with `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-a OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=41 stage=<stage>'`. The fresh tag is `e41s12i`, the warm tag `e41s12iw`. Never two test runs in one message. Every IRIS MCP call names `server` and `namespace`. No real key, no Telegram bot.

**Shared surfaces:**
- `DailyNote.Build`'s signature and `InputProbe.NoteOf`;
- the session-start Input text: any test that compares a rendered session-start input with a fixed text (search the Test tree for `NOTESOPENING` and `sessionStart`);
- `StartsSession`'s answer after a fallback turn;
- `CommandsStep3Probe`'s dispatch;
- `MemoryApi:TestPin` real mode;
- `memory.spec.ts`' pin step and the LIVE session's pins (the cap test's precondition);
- `SecondModel:TestIntegrationWebChat`'s notes assertions.

Every test added or changed passes on a fresh environment, in either order, and creates and removes its own rows.

**Commands:**
- (once) `OCUTALON_RUN_TAG=e41s12iw ci/warm.sh up`. Expected: ready.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e41s12iw ci/iris.sh class <Class>`, one call each. None needs the production (shadow instances). Expected: passed.
  - `OcuTalon.Test.Memory.Pins`
  - `OcuTalon.Test.Agent.RenderMemory`
  - `OcuTalon.Test.Data.DailyNote`
  - `OcuTalon.Test.Data.OwnershipNotes`
  - `OcuTalon.Test.Core.ConversationSessionStart`
  - `OcuTalon.Test.Core.CommandsStep3`
  - `OcuTalon.Test.Web.MemoryApi`
  - `OcuTalon.Test.Core.ConversationTurns`
- (once) `OCUTALON_RUN_TAG=e41s12i ci/iris.sh class OcuTalon.Test.Bridge.SecondModel:TestIntegrationWebChat`. It needs the real production, so it runs on a fresh stack. Expected: passed. If the call nears 150 s, leave it to CI (`shard lane-a@rest`) and say so.
- (once) `bash docker/tests/test-class-rules.sh`, then `bash docker/tests/test-boundaries.sh`. Expected: pass.
- (once) `cd web && npx tsc -p tsconfig.e2e.json`, then `npx playwright test --list e2e/api/memory.spec.ts`. Expected: exit 0, and 5 tests listed.
- (once) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16`. Expected: the 41.9 baseline (`"ok": false`, 10 low `placeholder` findings, nothing new).
- (once) `OCUTALON_RUN_TAG=e41s12iw ci/warm.sh down`, then `OCUTALON_RUN_TAG=e41s12i ci/iris.sh teardown`.
- **Left to CI:** `live:sign-in` (the e2e spec, over 150 s locally), the shards, `bash ci/checks.sh`, and the lead's fresh-environment check.

**Mutations (Rule 19), at least one per AC.** Apply on the warm stack, observe red, revert, confirm the files byte-identical (`git status --short`, `git diff --stat`). Record each as `mutation: ... -> ... red`.
- AC 1: the cap comparison `>` becomes `>=` → `Pins:TestCap` red (the 4,000 block refused). `OnPin` measures `Memory.CoreBlock(session)` without the candidate → `Pins:TestCap` red (the one-over pin accepted). `MemoryOps` without the `PinMemory` MapItem → `MemoryApi:TestPin` red (real mode 500).
- Rendered, not summed: `CoreBlock` quotes nothing (texts joined bare) → `Pins:TestCapRendered` red.
- DW-1014: the already-pinned check becomes `row.Pinned '= 0` → `Pins:TestOldRow` red.
- AC 3: `CorePart` placed after `NotesPart` → `RenderMemory:TestCoreBlock` red. `CorePart` appends one more `LF` to `CoreOf`'s answer → `TestCoreAgrees` red. `CorePart` drops pins past 4,000 characters → `TestCoreNeverCut` red.
- AC 4: `CorePart` ignores `sessionStart` → `ConversationSessionStart:TestCoreMemoryAtStart` red (a second turn holds the block).
- AC 5: `StartsSession` without the reached-model condition → `TestStartsSessionBoundaries` red.
- AC 6: `Build` ignores `itemId` → `DailyNote:TestLeavesOutCurrentTurn` red, and `SecondModel:TestIntegrationWebChat` red (on the fresh stack, once).
- DW-1039: CI only; not demonstrable locally, as in 41.9.

**Recorded (implement stage, warm stack `e41s12iw`; each applied, observed red, reverted, files byte-identical with `cmp`):**
- mutation: `OnPin` cap comparison `>` -> `>=` (Memory/Ops.cls) -> `Pins:TestCap` red (the exactly-4,000 pin refused), `TestOldRow` and `TestForgetPinned` red too.
- mutation: `OnPin` measures `Memory.CoreBlock(session, "", .block)` without the candidate (Memory/Ops.cls) -> `Pins:TestCap` red (the one-over pin accepted), `TestCapRendered` and `TestForgetPinned` red.
- mutation: `MemoryOps` without the `PinMemory` MapItem -> `MemoryApi:TestPin` stayed GREEN (its real mode reaches the handlers through `CommandsStep3Probe`, which dispatches by class name, as the delivered probe always did), so the pin of the map is `Pins:TestMessageMap` (added in-stage): red ("PinMemory goes to OnPin"). The predicted `MemoryApi:TestPin` red is not available.
- mutation: `Agent.Input.CoreBlock` quotes nothing (`block_$Char(10)_text`) -> `Pins:TestCapRendered` red (4,004 not reached, the candidate accepted), `TestPinnedOrder` and `TestOldRow` red.
- mutation: `OnPin` ignores a lock it could not take (`If 'lock Quit ..Failed` -> `If 0 Quit ..Failed`, Memory/Ops.cls) -> `Pins:TestLockBusy` red (the pin is written with the lock busy); reverted, files byte-identical.
- mutation: `OnPin` without the owner check (`'$IsObject(row) || (row.SessionRef '= request.SessionRef)` -> `'$IsObject(row)`) -> `Pins:TestOtherSession` red (another session's ref pinned instead of not_found).
- mutation: `OnUnpin` without `Set row.PinnedAt = ""` -> `Pins:TestUnpin` red.
- mutation: `OnPin` without the no_session check (`If '$IsObject(...Session...RefIndexOpen...) Quit` -> `If 0 Quit`) -> `Pins:TestNoSession` red.
- AC 2 mutation: `OnSave` sets `Pinned` 1 on the new row (Memory/Ops.cls) -> `Test.Memory.Ops` red (`TestSourceIgnoresSavedText`, `TestSourceReadFails` and the other source tests); the origin gate's own mutations are 41.9's (`CommandsStep3:TestOrigins`). All reverted, files byte-identical.
- mutation: `OnPin` already-pinned check `+row.Pinned = 1` -> `row.Pinned '= 0` -> `Pins:TestOldRow` red (the empty-Pinned row is answered pinned and never written).
- mutation: `CorePart` placed after `NotesPart` (Render order) -> `RenderMemory:TestCoreBlock` and `TestCoreAgrees` red.
- mutation: `CorePart` appends one more `LF` to `CoreOf`'s non-empty answer -> `RenderMemory:TestCoreAgrees`, `TestCoreBlock` and `TestCoreNeverCut` red.
- mutation: `CorePart` cuts the block at 4,000 characters (`$Extract(..CoreOf(...), 1, 4000)`) -> `RenderMemory:TestCoreNeverCut` red.
- mutation: `CorePart` ignores `sessionStart` -> `ConversationSessionStart:TestCoreMemoryAtStart` red (the second turn holds the block and the pin).
- mutation: `StartsSession` without the reached-model condition (`If reached {` -> `If 1 {`) -> `ConversationSessionStart:TestStartsSessionBoundaries` red (no_key fallback, no-decision fallback, foreign usage row).
- mutation: `DecisionServed` answers 1 for any decision (`Quit rows.Count() > 0` -> `Quit 1`) -> `OwnershipNotes:TestDecisionServed` red.
- mutation: `DailyNote.Build` ignores `itemId` (`If $Get(itemId) '= "" {` -> `If 0 {`) -> `DailyNote:TestLeavesOutCurrentTurn` red, and on a fresh stack (tag `e41s12i`, torn down afterwards) `SecondModel:TestIntegrationWebChat` red ("on one local day no request holds a notes block that quotes the first message").
- Unmutated: `SecondModel:TestIntegrationWebChat` passed on the fresh stack (READY 278 s, test 17.6 s, run 296 s: over the 150 s guide because of the stack build). `web/e2e/api/memory.spec.ts` (tsc exit 0, 5 tests listed) is left to `live:sign-in` in CI.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `MemoryOps` handles `PinMemory` and `UnpinMemory` under the session's lock: a pin is refused with `over_cap` when the rendered core-memory block (`Memory.CoreBlock`, formatted only by `Agent.Input.CoreBlock`) would pass `COREMAX` (4,000 characters = `PINCAPTOKENS` 1,000 x `CHARSPERTOKEN` 4). `Agent.Input.Render` puts the same block after the persona block and before the notes at a user item's session start, never cut. `StartsSession` counts only earlier turns that reached a model (DW-967). `DailyNote.Build` takes the turn's ItemId and leaves out that turn and later ones (DW-977). The tests that stopped at a probe now assert the real outcomes (DW-1029, DW-1039). Two additive spine lines and a memlog decision record the rule.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Memory.cls`: cap constants, `Pinned`, `CoreBlock`.
- `src/ocutalon/cls/OcuTalon/Memory/Ops.cls`: `OnPin`, `OnUnpin`, message map, class comment.
- `src/ocutalon/cls/OcuTalon/Agent/Input.cls`: `COREOPENING`, `LOGCORE`, `CoreBlock`, `CorePart`, `CoreOf`, Render order, ItemId to `NoteOf`.
- `src/ocutalon/cls/OcuTalon/Data/DailyNote.cls`: `Build(sessionRef, day, itemId)`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: `DecisionServed`.
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls`: `StartsSession` and the `Served` seam.
- Tests: new `Test/Memory/Pins.cls` and `Test/Memory/PinsProbe.cls`; changed `RenderMemory`, `InputProbe`, `MemoryTurns`, `DailyNote`, `OwnershipNotes`, `ConversationSessionStart`, `ConversationStartProbe`, `CommandsStep3`, `CommandsStep3Probe`, `MemoryApi`, `SecondModel`, `web/e2e/api/memory.spec.ts`, `web/e2e/support/memory.ts`.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` (+ `.memlog.md`): two `[ADDED 2026-11-09, Story 41.12]` lines and the decision.

**Review.** 25 findings: 1 high (patched, caused by this stage's own overwrite of `OpsProbe`), 5 low patched (comments, fixture cleanup, mutation lines, a lock-busy test for the matrix's lock row), the rest rejected with reasons in the log. Deferred: none.

**Follow-up review recommended: false** (one high patched, but it was a self-inflicted test-double overwrite, restored byte-identical and re-verified by running `Test.Memory.Ops`).

**Verification.** Warm stack `e41s12iw` (torn down, 0 leftovers): `Pins`, `RenderMemory`, `DailyNote`, `OwnershipNotes`, `ConversationSessionStart`, `CommandsStep3`, `MemoryApi`, `ConversationTurns`, `MemoryTurns` and `Memory.Ops` passed; `Pins` and `ConversationSessionStart` re-run after the patches. `SecondModel:TestIntegrationWebChat` passed once on a fresh stack in the handoff (about 296 s, torn down); only comments changed in `Input` and `Conversation` since. `test-class-rules.sh` and `test-boundaries.sh` pass; `tsc -p tsconfig.e2e.json` exit 0; `playwright --list` shows 5 tests; the spine lint equals the 41.9 baseline (10 low placeholder findings). Mutations recorded in `## Verification` for AC 1 to 6 (the MapItem one did not go red in `MemoryApi:TestPin`; `Pins:TestMessageMap` pins it).

**Residual risks.** `live:sign-in` (the `memory.spec.ts` pin and cap tests, real HTTP as LIVE with PANEL) was not run locally: left to CI. `SecondModel` fresh-stack run also in CI's `shard lane-a@rest`. The handoff ran one `ci/iris.sh class` call from the main checkout by mistake (a failed `cd` chain): it started and cleaned up its own throwaway, left no containers, and changed nothing in that checkout.
