---
title: "Story 41.8: Told or learned, and facts OcuTalon learns in your own turns"
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

**Problem:** Memory (Epic 19) saves only when the person asks, and a row does not record whether the person asked. Nothing lets Chat keep a lasting fact the person mentions in passing, and nothing tells the person which memories they asked for and which OcuTalon kept on its own. The spine names the second part's columns and verbs, but not their contract or ownership rows.

**Approach:** `Data.Memory` gains the appended columns `Source`, `Pinned` and `PinnedAt`. `MemoryOps` sets `Source` in code when it saves: it reads the person's own text for the save's turn (`Ownership.TurnOfItem`) and checks it against a fixed phrase list in `OcuTalon.Tools.MemorySource`. If a phrase matches, the source is `told`; otherwise it is `learned`. Search and List return each row's source. The list and search tools hand it to the model. Chat's instructions gain the UX learning paragraph, word for word, and tell the model to write "(told)" or "(learned)" after each memory it names. The spine records the names, the verbs and their ownership rows.

## Boundaries & Constraints

**Always:**
- Code decides `Source`. The model's arguments never carry it, and `MemoryOps` decides it only from the `Data.Turn.Text` of the save's own turn: same ItemId, same session.
- The gate is unchanged. In an untrusted or tainted turn, `save_memory` is still denied, with no command and no row (AD-10, `MemoryTools` `READONLYSAVEMEMORY` 0).
- Storage is append-only (AD-5). The `Storage` block keeps every existing slot. The three new values follow at 9, 10 and 11, as the compiler writes them. Every reader treats an empty `Source` as `told` and an empty `Pinned` as 0.
- The learning paragraph is used exactly as written at EXPERIENCE.md:1062. It is static XData with no `{{`. The forget confirmation stays exactly "Forgotten." (EXPERIENCE.md:977).
- `HostData.memories` keeps its shape, `{memoryRef, text, savedAt}` (Conventions, "Citations and memories").
- Every test added or changed passes on a fresh environment, in either order, and creates and removes the rows it asserts on.

**Never:**
- Edit a Lane B class or test: `Core/**`, `Msg/**`, `Web/**`, `Data/Ownership.cls`, `Data/Turn.cls`, `Test/Core/**`, `Test/Data/**`, `Test/Web/**`, `web/**`. `SaveMemory` gains no property in this story.
- Pin, unpin or route a pin. That is 41.9's job (the verbs and routes) and 41.12's (the handling and the cap). Also out of scope: the HostSink event `conversation.compacted` (41.10 and 41.11 are out of scope), and the Memory card (41.13).
- Back-fill old rows, add an index, or change purge or `DropSession`.
- Edit a contended path: `Mcp/**`, `Bridge/Adapter/**`, `Msg/Catalog/Watch.cls`, `Production.cls`, `ci/units.sh`, `src/short-names.tsv`, AD-16, AD-31.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Told | Turn text "Remember that the VPN host is vpn.example", trusted and untainted; the model saves | row `Source` told, `Pinned` 0, `PinnedAt` "" | none |
| Each phrase | "keep in mind", "Note that", "DON'T FORGET", or "don’t forget" with U+2019 | told: case-folded, U+2019 read as an apostrophe, whole words | none |
| Learned | "Our VPN host is vpn.example." (no phrase), or "I remembered the host" (not a whole word) | `learned` | none |
| No turn | the save's ItemId has no `Data.Turn` row of the session, or only another session's row | `learned` | none |
| Turn read fails | `TurnOfItem` gives an error status | `failed` (`MESSAGEFAILED`), no row | one Type 3 warning, redacted |
| Repeat | the same session, ItemId and text | answers saved with the first Ref; the first row's `Source` is kept | none |
| Untrusted or tainted | untrusted turn, or a turn tainted by a recall | the gate denies the save; no command, no row (unchanged) | the gate's sentence |
| Old row | a row saved before 41.8 (`Source`, `Pinned` empty) | Search/List give `source` told, `pinned` 0 | none |
| List / search | the session's told, learned and old rows | each tool memory is `{ref, text, saved, source}`, with `source` told or learned | NOTLISTED / NOTSEARCHED as before |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless given in full. Line numbers are as of `b60f10e4`.

**Files to change (Lane A)**
- `Data/Memory.cls`:
  - Append `Source As %String(MAXLEN = 16)`, `Pinned As %Boolean [ InitialExpression = 0 ]` and `PinnedAt As %String(MAXLEN = 20)` after `Embedding` (32), each with a doc comment.
  - Compile, then commit the compiler's `Storage` block, which adds values 9 to 11 after `Embedding` (69-70). Update the class comment (1-6).
- `Tools/MemorySource.cls` (new, plain class, not a toolset member):
  - `Parameter TOLD = "told"`, `Parameter LEARNED = "learned"`, and `Parameter PHRASES = "remember,keep in mind,note that,don't forget"`.
  - `ClassMethod Of(text As %String) As %String`, which gives `told` or `learned`. The text is lowercased, and `$Char(8217)` becomes `'` (Rule 14: no literal byte). Matching is whole words: the phrase must be at the start or end of the text, or bounded by a character that is not `a-z` or `0-9`.
  - Its sibling is `Tools/Names.cls`, the fixed parameter lists. It is a separate class because `Names` holds tool names, and a public method on a tool class would become a tool.
- `Memory/Ops.cls`:
  - In `OnSave` (51-91), inside the lock and before the embed (67), call a new overridable seam `Method Source(sessionRef, itemId, Output source As %String) As %Status`. It calls `Data.Ownership.TurnOfItem(itemId, sessionRef, .sc)`. An error is returned. No turn gives `learned`. A turn gives `MemorySource.Of(turn.Text)`.
  - An error from the seam goes to `..Failed`. Set `row.Source` (75). A repeat (63-65) does not call the seam.
  - Update the class comment (1-16).
- `Memory.cls`:
  - Add `Source` and `Pinned` to `NEARESTSQL` (45), `KEYWORDSQL` (48) and `List`'s SELECT (139). `Hits` (184-195) and `List` (142) push `"source": $Select(Source = "learned": "learned", 1: "told")` and `"pinned": +Pinned`. `Fuse` (84-125, the push at 119) carries both members through.
  - Update the comments at 11, 50, 81-83, 127 and 182.
- `Tools/MemoryTools.cls`:
  - `Shown` (139-151) pushes `"source": (row.source)`.
  - Update the doc comments of `SaveMemory` (76) and of `SearchMemories` and `ListMemories` (88, 103). Their wording is under Design Notes, "Model-facing text".
  - Update the class comment (6-7).
- `Agent/Chat.cls`:
  - Replace the bullets at 68, 69 and 70 with the texts under Design Notes.
  - Append the learning paragraph after line 78, after one blank line, as the block's last text.
  - The class comment (1-7) names the learning paragraph and the labels.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: the additive lines under Design Notes, "Spine lines".

**Tests to change or add (Lane A)**
- `Test/Tools/Memory.cls`:
  - `TestSourceOf` is new and safe on a slot. Add it to the header's list of slot-safe tests. It covers every row of the matrix's Told, Each phrase and Learned entries, plus "" and "Remembering".
  - In `TestSearchAnswer` (233) and `TestListAnswer` (367), the keys become `ref,saved,source,text`. Store one learned row and one old row through `Fixture.Store`, and assert `learned` and `told`.
  - `TestInstructions` (402): the three new bullets, word for word.
- `Test/Memory/Fixture.cls`: `Store` (113) gains a trailing `source As %String = ""`.
- `Test/Memory/OpsProbe.cls`:
  - Add a `SourceFails As %Boolean [ Transient ]` property, and a `Source` override that returns `$SYSTEM.Status.Error(5001, ...)` when it is set and calls `##super` otherwise.
- `Test/Memory/Ops.cls`:
  - `TestSource` uses a shadow `OpsProbe`, as `TestTunedOnSave` (333) does. Turn rows come from `Test.Data.Fixture.Turn(session, , "running", text)`: read the ItemId with `Data.Turn.RefIndexOpen`, and remove the rows with `Test.Data.Fixture.Clean(refs)` in `OnAfterOneTest`. It covers the matrix's Told, Each phrase, Learned, No turn and Repeat rows, plus `Pinned` 0 and `PinnedAt` "".
  - `TestSourceReadFails`: with `SourceFails` set, the answer is failed, Ok 0, with no row.
- `Test/Memory/Search.cls`:
  - Update the key pins at 100, 159, 271 and 273 to include `source` and `pinned`.
  - `TestList` also covers a learned row, an old row (told, 0) and a row stored with `Pinned` 1 (`pinned` 1).
- `Test/Memory/Turns.cls`: `TestToldAndLearnedThroughTheAgent` (Integration, AC 2 and AC 4). The private `Turn` (142) gains an optional `itemId`, which overrides `request.ItemId`:
  - On a fixture `Data.Turn` of the session with "Remember that the Results partner's contact is Lee. [[mock:memory-save]]", the row is told.
  - On a second turn, "The Results partner's contact is Lee. [[mock:memory-save]]", the row is learned.
  - A third turn, "Remember that ... [[mock:memory-save]]" with no Turn row, gives learned.
  - Then `[[mock:memory-list]]`: in the model's next request, the tool result lists the three memories newest first, with source learned, learned, told.
  - Update the header.
- `Test/Agent/PersonaBlock.cls`:
  - `XData UX` (38-45) gains `"chatLearning"`, the EXPERIENCE.md:1062 text.
  - `TestParagraphs` (211): the paragraph is in Chat exactly once and is the block's last text, after the proposals paragraph and one blank line (this replaces the assertion at 224). It holds no `{{`.
- `Test/Contract/Step3.cls`: in `XData Contracts` (146-163), `OcuTalon.Data.Memory.props` gains `Source`, `Pinned` and `PinnedAt`, with the types as the contract renders them.

**Consumed as built (read only)**
- `Data/Ownership.cls:303` `TurnOfItem(itemId, sessionRef, .sc)`: owner-scoped, exact compare.
- `Core/Conversation.cls:194-203`: every trusted chat turn, on every channel, is a `Data.Turn` with `ItemId` = the Item's and `Text` = the person's text.
- `Tools/CommandCall.cls:41-44`: `IdempotencyKey` is `context.ItemId:<n>`, and `SessionRef` is `context.OwnerRef`.
- `Memory/Ops.cls:58`: the ItemId is the key before its last colon.
- `Test/Data/Fixture.cls:35` `Turn` and `:369` `Clean`.
- `ci/mock/scenarios/A/memory-save.json` and `memory-list.json`. No new scenario is needed.

## Tasks & Acceptance

**Execution:**
1. `Data/Memory.cls`: the columns and the compiled storage block. `Test/Contract/Step3.cls`: the contract.
2. `Tools/MemorySource.cls`, and `Test/Tools/Memory.cls` `TestSourceOf`.
3. `Memory/Ops.cls`: the `Source` seam and the column. `Test/Memory/OpsProbe.cls`, `Test/Memory/Fixture.cls`, and `Test/Memory/Ops.cls` `TestSource` and `TestSourceReadFails`.
4. `Memory.cls`: the row members. `Test/Memory/Search.cls`.
5. `Tools/MemoryTools.cls`: `source` and the descriptions. `Test/Tools/Memory.cls` search and list updates.
6. `Agent/Chat.cls`: the bullets and the paragraph. `Test/Tools/Memory.cls` `TestInstructions` and `Test/Agent/PersonaBlock.cls`.
7. `Test/Memory/Turns.cls` `TestToldAndLearnedThroughTheAgent`.
8. The spine: insert the lines under Design Notes, refresh `updated:` to `'2026-11-09'`, then run `uv run --no-cache _bmad/scripts/memlog.py append --workspace <spine-dir> --type decision --text "Story 41.8: Data.Memory Source/Pinned/PinnedAt and the verbs PinMemory/UnpinMemory named; MemoryOps decides Source from the person's own turn text (MemorySource.PHRASES)"` and `lint_spine.py` (`"ok": true`).
9. Search the test trees for the old shapes, and update every pin: `"ref,saved,text"`, `memoryRef,text,savedAt,origin`, the old memory bullets, "proposals paragraph is the block's last text", and the old `Data.Memory` property list.

**Acceptance Criteria:**
- AC 1: Given the spine at the re-open, when this story updates it, then AD-29 holds the "Epic 41's second-part names" line, and the cross-area table holds the `PinMemory`/`UnpinMemory`, `MemorySource` and `TurnOfItem` rows, as quoted under Design Notes. AD-21's lines 705 and 714 and AD-33's tables line 1338 already name the columns and verbs and stay as they are. No line records `conversation.compacted`, and `lint_spine.py` answers `"ok": true`.
- AC 2: Given a person's trusted, untainted chat turn on the running production with the CI mock, when the Chat agent calls `save_memory`, then the new row's `Source` is `told` if that turn's `Data.Turn.Text` holds one of the fixed phrases ("remember", "keep in mind", "note that", "don't forget"), and `learned` otherwise or when the turn has no row of the session. `Pinned` is 0 and `PinnedAt` is "". In an untrusted or tainted turn, the save is still denied with no row (`Turns:TestToldAndLearnedThroughTheAgent`, `Ops:TestSource`, and the existing `Turns:TestUntrustedSave` and `TestTaintedSave`).
- AC 3: Given Chat's compiled INSTRUCTIONS, when they are read, then they hold the EXPERIENCE.md:1062 learning paragraph exactly once, as the block's last text, after the proposals paragraph and one blank line, and the block holds no `{{` (`PersonaBlock:TestParagraphs`, `Instructions:TestNoTemplates`).
- AC 4: Given a session with told, learned and pre-41.8 memories, when `list_memories` or `search_memories` runs in a person's turn, then every memory in the tool result the model reads carries `source` `told` or `learned`, with an empty `Source` read as told. Chat's list, search and forget bullets tell the model to write "(told)" or "(learned)" after each memory it names, and the forget confirmation is still exactly "Forgotten." (`Turns:TestToldAndLearnedThroughTheAgent`, `Tools.Memory:TestListAnswer`, `TestSearchAnswer` and `TestInstructions`).

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions:**
- AD-21, "Told and learned" (spine 712-717): the appended columns, code deciding the source, and the gate.
- AD-5: append-only storage.
- AD-10: the gate is unchanged.
- AD-7: static instructions with no `{{`.
- AD-1: a save is still a `SaveMemory` from origin `tool`.
- AD-4: an owner-scoped read of the turn.
- AD-29 and AD-33: lanes, names, one writer.
- AD-6: the phrase check is pure code, run in `MemoryOps`' job.
- AD-22: tests run on the mock.
- AD-31: no event is added.

No AC contradicts an AD's Rule.

**AC already met (evidence):**
- The gate's refusal: `Tools/MemoryTools.cls:52-56` (save is not read-only) and `Test/Memory/Turns.cls:340-412` (tainted, parallel and untrusted saves are denied with no row).
- The spine already records the columns (AD-21 line 714), the verbs (AD-21 line 705), and that Lane A appends the columns in 41.8 (AD-33's tables, line 1338).

**Out of scope here (AD-31):** the spine AC's third bullet, the HostSink event `conversation.compacted`. AD-31's amendment is undecided, and 41.10 and 41.11 are optional and out of scope. 41.8 needs neither of them.

**Lanes:** every file changed is Lane A's.
- `Data.Memory` is a Lane A table (spine 1338).
- `.Memory`, `.Tools` and `.Agent` are Lane A packages (AD-29).
- `Test/Contract/Step3.cls` holds the contract of Lane A's step-3 tables, and Lane A's Story 34.1 created it (`169816e9`). Its edit is the additive insertion that contract tests take from either lane, as 41.2 did in `Ac.cls`.
- `Ownership.TurnOfItem` and `Test.Data.Fixture` are only called, never edited.

**Footprint extensions (Rule 11 (b)):** `Test/Tools/Memory.cls` and `Test/Contract/Step3.cls`. Neither is a contended path.

**Integration ACs:** `Turns:TestToldAndLearnedThroughTheAgent` runs the real gate, tools, CommandsIn, `MemoryOps` and `Memory.List` through the Chat agent on the CI mock. The consumer is the model's next request, which carries each memory's source.

**Consumes:**
- Epic 19's `MemoryOps`, `Memory.Search` and `Memory.List`, and the four tools.
- `Ownership.TurnOfItem` (Lane B, built).
- Conversation's Turn rows.

**Consumed-by:**
- 41.9: the names `PinMemory` and `UnpinMemory` (`MemoryRef`). Its items route reads `source` and `pinned` (from `Memory.List` and `Search`, or through Ownership).
- 41.12: `Pinned` and `PinnedAt`, the cap, and core memory.
- 41.13: the "Told" and "Learned" labels.
- 41.14: the gate proofs and the evals.

**Extend, don't copy:**
- `MemorySource` follows `Tools.Names`' parameter-list pattern.
- The `Source` seam follows `Tuned` and `OpsProbe`.
- `Fixture.Store` gains an argument rather than getting a sibling.
- The integration test extends `Test.Memory.Turns`' `Turn` helper.

**Decided in-stage:**
- **`MemoryOps` decides the source, not the tool.** `SaveMemory` (Lane B) has no `Source` field. Deciding from `Data.Turn` keeps the model out of it. A message-carried source for origin `system` is 41.11's, if it is ever built.
- **Matching is whole words and case-folded, with U+2019 read as `'`.** "I remembered" is learned, and "dont forget" (no apostrophe) is not on the fixed list.
- **A failed turn read fails the save.** It does not guess, as `RefOf` does today.
- **An empty `Source` is told.** Before 41.8, `save_memory` said "Use it only when the user asks you to remember something", so every saved row was asked for.
- **All three columns come in 41.8.** The spine names 41.8 as the story that appends them, and 41.9's route (before 41.12) needs `pinned`. Search and List also return `pinned`, so that 41.9, which is Lane B, needs no Lane A edit.
- **Forgetting shows labels only on the which-one question.** UX line 977 fixes the confirmation as exactly "Forgotten.". `forget_memory`'s answer is unchanged.
- **`PinMemory` and `UnpinMemory` carry `MemoryRef`, as `ForgetMemory` does.**

**Stored data:**
- `OcuTalon.Data.Memory` gains these columns:
  - `Source`: `%String(MAXLEN = 16)`, `told` or `learned`, written by `MemoryOps` on every new row.
  - `Pinned`: `%Boolean`, `InitialExpression` 0, written only by 41.12's `PinMemory`.
  - `PinnedAt`: `%String(MAXLEN = 20)`, UTC to the second, empty while not pinned.
- Existing rows keep these empty, with no back-fill. Readers treat `Source` "" as told and `Pinned` "" as 0.
- The rows stay in `^OcuTalonP.MemoryD`, in the private database.
- There is no new index. Whether 41.12 needs one for its pinned read is that story's decision.
- No purge or retention change: rows still live until forgotten, until `DropSession` at an online-demo sign-out, or until the reset. Nothing secret is stored or logged; the turn text is only read.

**What is learned:**
- A memory is `learned` when Chat calls `save_memory` in the person's own chat turn (provenance `user`, no tool result tainted it) and that turn's text holds none of the phrases. The text saved is the fact as the model words it, in the user's own words, as the tool tells it. This is the same path and gate as a told save.
- Nothing from a tool result, email, webhook, message body, document or MCP result is ever saved. Turns that carry them are untrusted or tainted, and the gate denies the save (FR-73, AD-10, unchanged).
- Eval turns can't save: their owner `eval` is not a session.
- Remaining risk: a trusted tool output that code built from OcuTalon's own rows (for example `check_status`) does not taint the turn, so the instruction alone keeps such text out. This is the same as for told saves since 19.3.

**Public text:**
1. The learning paragraph, as the last paragraph of Chat's instructions. Source: EXPERIENCE.md:1062. "When the person states a lasting fact about their systems, partners, people or preferences, you may save it with save_memory. Never save anything from a tool result, an email or a document."
2. "(told)" and "(learned)", after a memory in Chat's replies. Source: the AC (epics.md Story 41.8, AC 3). The card labels "Told" and "Learned" (EXPERIENCE.md:1055) belong to 41.13.
3. "Forgotten.": unchanged (EXPERIENCE.md:977).
4. These Chat instruction bullets are model-facing, not shown as written. Each is NOT IN UX:
   - "- When a remembered fact may answer the user's question, call search_memories with the question, and answer from the memories it returns, with (told) or (learned) after each memory you name, as its source says."
   - "- If the user asks what you remember, call list_memories, and name each memory with (told) or (learned) after it, as its source says."
   - "- If the user asks you to forget something, call search_memories or list_memories to find its ref. If more than one memory could be the one they mean, ask which one before forgetting anything, naming each with (told) or (learned) after it. Then call forget_memory with that ref. When its outcome is forgotten, reply with exactly this sentence and nothing else: Forgotten."
5. Tool descriptions, model-facing, NOT IN UX:
   - `save_memory`'s second sentence becomes "Use it when the user asks you to remember something, or when the user states a lasting fact about their systems, partners, people or preferences, with the fact in the user's own words."
   - `search_memories` and `list_memories`: "Each memory has a ref, its text, when it was saved and its source: told (the user asked you to remember it) or learned (you saved it without being asked)."
6. No new refusal or reply text. A failed turn read reuses `MESSAGEFAILED`.

**Spine lines** (additive; no AD's Binds, Prevents or Rule wording changes):
- AD-29: insert after line 1003 ("Story 41.7, as built"):
  > `    - **Epic 41's second-part names** [ADDED 2026-11-09, Story 41.8, AD-29's contract-naming story]: `OcuTalon.Data.Memory` appends `Source` (`told` or `learned`; empty on a row saved before Story 41.8, which readers take as `told`), `Pinned` (0 by default) and `PinnedAt` (UTC to the second, empty while unpinned), written only by `MemoryOps`. `MemoryOps` sets `Source` on a save: `told` when the person's own text in the save's turn (`Data.Turn.Text`, read through `Ownership.TurnOfItem` by the save's ItemId and session) holds a phrase of `OcuTalon.Tools.MemorySource` `PHRASES` ("remember", "keep in mind", "note that", "don't forget"; whole words, case-folded), else `learned`; `Memory.Search` and `.List` give each row's `source` and `pinned`. The verbs `OcuTalon.Msg.Command.PinMemory` (`MemoryRef`) and `.UnpinMemory` (`MemoryRef`) carry the common `Origin`, `IdempotencyKey` and `SessionRef`, are accepted from origin `web_user` only (AD-1) and are routed by `CommandsIn` to `MemoryOps` (Story 41.9 creates them; Story 41.12 handles them). AD-31's `conversation.compacted` is not recorded: its amendment is undecided.`
- The cross-area table (AD-33's tables): insert after line 1393:
  > `| `OcuTalon.Msg.Command.PinMemory` and `.UnpinMemory` (`MemoryRef`) (AD-1, AD-21), submitted by the web layer through `Commands.Submit` with origin `web_user` only and routed by `CommandsIn` to `MemoryOps` [ADDED 2026-11-09, Story 41.8] | B | Story 41.9 (classes and routing), Story 41.12 (`MemoryOps`' handling) |`
  > `| `OcuTalon.Tools.MemorySource.Of(text)` and `PHRASES` (AD-21), read by `MemoryOps` [ADDED 2026-11-09, Story 41.8] | A | Story 41.8 |`
  > `| `OcuTalon.Data.Ownership.TurnOfItem(itemId, sessionRef)` (AD-4), read by `MemoryOps` for a save's source [ADDED 2026-11-09, Story 41.8] | B | built (read by `DailyNote.Build` since Story 41.3) |`
- `updated:` (line 10) becomes `'2026-11-09'`.

**For the lead (not a halt):**
- 41.13's Forget still has no web delete route: `ForgetMemory` is origin `tool` only, and 41.9's AC lists only the items and pin routes. This belongs at 41.9's plan, as an AC and an AD-1 note.

**CI:** no new unit, area or group, and no `ci/units.sh` change.
- `Test.Memory` and `Test.Tools` run in `shard:lane-a@rest` (`shards-2`). `Test.Agent` runs in `shard:lane-a@Agent` (`production`). `Test.Contract` runs in `lane-b` (`image`).
- The new tests add about 10 to 30 s to `shards-2` (inference).

## Verification

Run from the worktree root, one command per call, with `timeout: 600000`, each sized to about 150 s. Prefix every `ci/` call with:

`OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=41 stage=implement'`

- The fresh tag is `e41s8i` and the warm tag is `e41s8iw`.
- Run one test class per call, and never two test runs in one message.
- At the end, tear down with `ci/warm.sh down`, then `ci/iris.sh teardown` with tag `e41s8i`.
- Every IRIS MCP call names `server` `ocutalon-slot-a` and `namespace` `OCUTALON`.
- Use no real key and no Telegram bot.

**Shared surfaces:**
- `Data.Memory`'s property list and storage block (`Test.Contract.Step3`);
- `Memory.Search` and `.List` row members (`Test.Memory.Search`, and any test that compares rows);
- the `search_memories` and `list_memories` member set (`Test.Tools.Memory`, `Test.Memory.Turns`, `Test.Docs.*`);
- Chat's memory bullets (`Test.Tools.Memory:TestInstructions`);
- Chat's last paragraph (`Test.Agent.PersonaBlock:TestParagraphs`);
- `Test.Memory.Fixture.Store`'s signature.

`HostData.memories` does not change. Every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once) `OCUTALON_RUN_TAG=e41s8iw ci/warm.sh up`. Expected: ready.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e41s8iw ci/iris.sh class <Class>`, one call each, for:
  - `OcuTalon.Test.Tools.Memory`
  - `OcuTalon.Test.Memory.Ops`
  - `OcuTalon.Test.Memory.Search`
  - `OcuTalon.Test.Agent.PersonaBlock`
  - `OcuTalon.Test.Agent.Instructions`
  - `OcuTalon.Test.Contract.Step3`

  Expected: each `CLASS ... passed`. A red that a stale `MemoryOps` job could explain counts only if the class is still red on a fresh run.
- (loop) `OCUTALON_RUN_TAG=e41s8i ci/iris.sh class OcuTalon.Test.Memory.Turns`. It runs fresh, because the ChatAgent and MemoryOps jobs must hold the new code. Expected: passed, in about 120 to 150 s on ARM (inference).
- (once) `OCUTALON_RUN_TAG=e41s8i ci/iris.sh class OcuTalon.Test.Memory.Ops`. Expected: passed, fresh.
- (once) `bash docker/tests/test-storage.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh` and `bash docker/tests/test-ci-config.sh`. Expected: all pass.
- (once) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16`. Expected: `"ok": true`.
- **Left to CI:** the `shards-2`, `production` and `image` pieces, `live:storage-roundtrip` (the compiled storage block against the committed one), `bash ci/checks.sh`, and the lead's fresh-environment check, forward and `--reverse`. The real model's reply wording ("(told)" in a reply) is REL-5's and 41.14's to measure.

**Mutations (Rule 19), one per AC. Record each as `mutation: <change> -> <test red>`:**
- AC 1: none. It is a documentation AC, checked by `lint_spine.py` and by grepping the three quoted lines.
- AC 2: `MemorySource.Of` always gives `learned` -> `Ops:TestSource` and `Turns:TestToldAndLearnedThroughTheAgent` (the told row). A second mutation: `READONLYSAVEMEMORY` 1 -> `Turns:TestUntrustedSave`.
- AC 3: one word of the learning paragraph changed in `Chat.cls` -> `PersonaBlock:TestParagraphs`.
- AC 4: `Shown` omits `source` -> `Tools.Memory:TestListAnswer` and `Turns:TestToldAndLearnedThroughTheAgent`.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

- Planned only (Halt after planning). Spec verified against the READY-FOR-DEVELOPMENT standard. The veto-window items for the spec gate are under Design Notes: Stored data, What is learned, Public text, Spine lines, plus the footprint extensions `Test/Tools/Memory.cls` and `Test/Contract/Step3.cls`. No Lane B edit. The AD-31 event is not in scope.
