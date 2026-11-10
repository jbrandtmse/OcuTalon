---
title: "Story 41.8: Told or learned, and facts OcuTalon learns in your own turns"
type: 'feature'
created: '2026-11-09'
status: 'done'
baseline_revision: '0cfe4bb37982153b6011a9658fb80135f073dc3b'
baseline_commit: '0cfe4bb37982153b6011a9658fb80135f073dc3b'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      Rows saved before Story 41.8 hold no stored Pinned value, so SQL such as Pinned = 0 skips them; Memory.Search and .List read an empty Pinned as 0 only through Row().
    evidence: |-
      Pinned has InitialExpression 0, which applies to new objects only, and no back-fill is allowed (AD-5, spec Never). Story 41.12's pinned read must use COALESCE(Pinned, 0) or read through Memory.Row.
    location: >-
      src/ocutalon/cls/OcuTalon/Data/Memory.cls (Pinned), for Story 41.12
    severity: medium (unverified)
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
8. The spine: insert the lines under Design Notes, refresh `updated:` to `'2026-11-09'`, then run `uv run --no-cache _bmad/scripts/memlog.py append --workspace <spine-dir> --type decision --text "Story 41.8: Data.Memory Source/Pinned/PinnedAt and the verbs PinMemory/UnpinMemory named; MemoryOps decides Source from the person's own turn text (MemorySource.PHRASES)"` and `lint_spine.py` (stays at its baseline: AC 1).
9. Search the test trees for the old shapes, and update every pin: `"ref,saved,text"`, `memoryRef,text,savedAt,origin`, the old memory bullets, "proposals paragraph is the block's last text", and the old `Data.Memory` property list.
10. (planner-2026-11-09-41.8) `Agent/Chat.cls`: add the learned-save bullet, verbatim, beside the other memory bullets: "- When you save a memory the user did not ask you to save, say so in your reply in one short sentence, for example: I'll remember that <the fact>." Pin its text in `Test/Tools/Memory.cls` `TestInstructions`, the same test that pins the other memory bullets.
11. (planner-2026-11-09-41.8) The evaluation set: add one user-turn case under `eval/memory-*/` (for example `eval/memory-learned-save/case.json`, modelled on `eval/user-turn-remember`) in which the person states a lasting fact with none of the fixed phrases, so the model saves it as `learned`. Score it in its OWN report-only line, as Story 41.7's AC 6 did for the precedent cases: it is OUT of every gated score's numerator and denominator, on the mock and on a release-candidate run, until a release-candidate run on Claude Haiku 5.5 has measured it. On the real model it reports whether the reply carries a one-sentence "I'll remember that ..."-style statement of the save. Pin the case and its report-only line in `Test/Eval/Cases.cls` and `Test/Eval/Report.cls` (the gated scores' share and count unchanged with the case present, scored right or wrong). On the mock, the case needs a scripted reply only if the existing user-turn cases have one: follow `user-turn-remember`.

**Acceptance Criteria:**
- AC 1: Given the spine at the re-open, when this story updates it, then AD-29 holds the "Epic 41's second-part names" line, and the cross-area table holds the `PinMemory`/`UnpinMemory`, `MemorySource` and `TurnOfItem` rows, as quoted under Design Notes. AD-21's lines 705 and 714 and AD-33's tables line 1338 already name the columns and verbs and stay as they are. No line records `conversation.compacted`, and `lint_spine.py` stays at its baseline (measured at the spec gate on 0c343347: `"ok": false` with exactly 10 low `placeholder` findings at lines 474, 998 (2), 1065, 1078 (2), 1144 (3) and 1154 before the insertion, shifted by the inserted line count after it; no `ad_id` or `ad_fields` finding and no new finding).
- AC 2: Given a person's trusted, untainted chat turn on the running production with the CI mock, when the Chat agent calls `save_memory`, then the new row's `Source` is `told` if that turn's `Data.Turn.Text` holds one of the fixed phrases ("remember", "keep in mind", "note that", "don't forget"), and `learned` otherwise or when the turn has no row of the session. `Pinned` is 0 and `PinnedAt` is "". In an untrusted or tainted turn, the save is still denied with no row (`Turns:TestToldAndLearnedThroughTheAgent`, `Ops:TestSource`, and the existing `Turns:TestUntrustedSave` and `TestTaintedSave`).
- AC 3: Given Chat's compiled INSTRUCTIONS, when they are read, then they hold the EXPERIENCE.md:1062 learning paragraph exactly once, as the block's last text, after the proposals paragraph and one blank line, and the block holds no `{{` (`PersonaBlock:TestParagraphs`, `Instructions:TestNoTemplates`).
- AC 4: Given a session with told, learned and pre-41.8 memories, when `list_memories` or `search_memories` runs in a person's turn, then every memory in the tool result the model reads carries `source` `told` or `learned`, with an empty `Source` read as told. Chat's list, search and forget bullets tell the model to write "(told)" or "(learned)" after each memory it names, and the forget confirmation is still exactly "Forgotten." (`Turns:TestToldAndLearnedThroughTheAgent`, `Tools.Memory:TestListAnswer`, `TestSearchAnswer` and `TestInstructions`).
- AC 5 (planner-2026-11-09-41.8, a learned save is never silent): Given Chat's compiled INSTRUCTIONS, when they are read, then they hold, exactly once and beside the other memory bullets, "- When you save a memory the user did not ask you to save, say so in your reply in one short sentence, for example: I'll remember that <the fact>." (`Tools.Memory:TestInstructions`). And given the evaluation set, then it holds one user-turn learned-save case scored in its own report-only line, out of every gated score's numerator and denominator, which on a release-candidate run reports whether the real model's reply states the save in one sentence (`Test.Eval.Cases`, `Test.Eval.Report`).

### Review Findings

Code review, 2026-11-09 (layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; tier full-opus; 19 raw rows, 10 entries).

- [x] [Review][Patch] A told save on a retried turn was stored as learned: after the provider rejects the history, `Conversation.Ask` sends `RetryItemId(turn.ItemId)`, which no `Data.Turn` holds, so `TurnOfItem` found nothing [src/ocutalon/cls/OcuTalon/Memory/Ops.cls:Source] — medium, fix-risk low (a lookup in the session's own queued/running turns, owner-scoped through `Ownership.TurnQueue`). Fixed: the new seam `TurnOf` falls back to the session's queued or running turn whose `RetryItemId` is the save's ItemId; `Ops:TestSource` pins told for a retried asking turn and learned for another session's retried turn. (blind-hunter + edge-case-hunter + verification-gap)
- [x] [Review][Patch] The real `Source` error branch never ran: `OpsProbe` replaced the whole `Source`, so deleting `If $$$ISERR(sc) Quit sc` stayed green [src/ocutalon/cls/OcuTalon/Test/Memory/OpsProbe.cls] — medium (Rule 19), fix-risk low. Fixed: the probe now fails `TurnOf`, and MemoryOps' own `Source` handles the error; mutation recorded under Verification. (verification-gap)
- [x] [Review][Patch] `Test.Docs.Chat`'s header still said "the five memory bullets (memory bullet 5 first" after the sixth bullet [src/ocutalon/cls/OcuTalon/Test/Docs/Chat.cls:3] — low, comment only. Fixed. (verification-gap)
- [x] [Review][Defer] The learned-save eval case covers no real save and rewards a reply that claims a refused one [src/ocutalon/cls/OcuTalon/Eval/Report.cls:ScoreTurn, eval/memory-learned-save/case.json] — deferred: DW-1015 decision-pending (owner burndown); medium, confined to the report-only eval line; the Planner ruling's "one learned save whose reply carries such a sentence" is not met in substance. Recommendation in the entry. (blind-hunter + edge-case-hunter + verification-gap + acceptance-auditor)
- [x] [Review][Defer] Nothing measures that a reply after a refused or failed learned save does not say "I'll remember that" [src/ocutalon/cls/OcuTalon/Agent/Chat.cls:68] — deferred: DW-1016 routed to 41-14 (medium, model behaviour unmeasured; the approved bullet's wording needs a ruling to change). (acceptance-auditor)
- [x] [Review][Defer] Pre-41.8 rows also hold an empty `Source`, and 41.13's card reads through Ownership, not `Memory.Row` [src/ocutalon/cls/OcuTalon/Data/Memory.cls] — deferred: occurrence appended to DW-1014 (owner 41-12). (blind-hunter)
- [x] [Review][Defer] The spine's 41.8 names line gives less of the phrase rule and the turn lookup than is built [ARCHITECTURE-SPINE.md, AD-29 names line] — deferred: DW-1017 wontfix-accepted (low; the line is approved text under U7). (blind-hunter + edge-case-hunter)

Rejected:
- low, by-design: "remember" anywhere in the turn, "Do you remember ...?", and missing phrases such as "save this" or "make a note" — the fixed list and whole-word rule are the approved contract (Design Notes, Decided in-stage). (blind-hunter + edge-case-hunter + acceptance-auditor)
- low, spec-bound: AC 1 has no pinning test or `mutation:` line — the spec makes it a documentation AC checked by `lint_spine.py` (at baseline, re-run by the auditor) and the quoted lines. (verification-gap)
- false: the learned-save report label says only "not in SM-1" — it also says "report-only", which states it is out of every gated score. (acceptance-auditor)

## Spec Change Log

- **planner-2026-11-09-41.8** (spec gate, 2026-11-09; the Contest Planner under the owner's delegation, relayed by the orchestrator):
  - Items 1-4 of the spec gate APPROVED as planned: the public text (the EXPERIENCE.md:1062 learning paragraph; "(told)"/"(learned)" from the AC; "Forgotten." unchanged; the three model-facing Chat bullets and the tool-description sentences under Design Notes, Public text); What is learned; the stored data; the spine lines.
  - ADDITION, a learned save is never silent: a fifth model-facing Chat bullet (NOT IN UX), verbatim: "- When you save a memory the user did not ask you to save, say so in your reply in one short sentence, for example: I'll remember that <the fact>." Its text is pinned in the same test that pins the other memory bullets (`Test.Tools.Memory:TestInstructions`). Story 41.8's real-model evaluation covers one learned save whose reply carries such a sentence, report-only like Story 41.7's AC 6. Added as Tasks 10 and 11 and AC 5.
  - Stored data (`Source`, `Pinned`, `PinnedAt`; append-only; no back-fill; an empty `Source` reads as `told`): accepted, with no veto.
  - Spine: the additive AD-29 sub-bullet and the three AD-33 cross-area rows are allowed under the doctrine's U7 step 2, with the `[ADDED 2026-11-09, Story 41.8]` marker. `lint_spine.py` must stay at its baseline.
  - Item 5 (41.13's web forget route) was approved as a veto-recorded amendment to Story 41.9's ACs in `epics.md`; it is not 41.8's work.

## Review Triage Log

### 2026-11-09 - Review pass
- verdicts: 16 findings - high 0, medium 2, low 14, false 0, maybe-false 0 (3 patched, 1 deferred, 12 rejected; the intent-alignment layer returned a description, not findings)
- findings:
  - `[low]` `reject` Blind: the learned-save eval case cannot observe a real save, because an eval turn's owner is not a session - spec-bound and recorded under "What is learned" ("Eval turns can't save"); the case measures the reply sentence, report-only, as the Planner ruling asks.
  - `[low]` `reject` Blind: the learned-save case is scored on the reply wording alone, whatever tools ran - spec-bound (Task 11: the line "reports whether the reply carries" the statement); a save cannot happen in an eval turn, so a save_memory step cannot be required.
  - `[low]` `reject` Blind: Of reads "remember" anywhere in the turn, and the phrase list is English only - by design; the fixed list and the whole-word rule are the approved contract (Design Notes, Decided in-stage).
  - `[low]` `patch` Blind (same as Edge's first): the words of a multi-word phrase match only with a single space, and TestSourceOf pinned two spaces as learned - Of now joins the words with a white-space pattern and TestSourceOf pins two spaces, a line feed and a tab as told.
  - `[low]` `reject` Blind: the learning paragraph and the save_memory description let the agent keep secrets or personal data unasked - by design: both texts are approved public text (EXPERIENCE.md:1062 and the Planner ruling); a new exclusion would be a new user-facing string and an escalation.
  - `[low]` `reject` Blind: "preferences" in the learning paragraph overlaps the persona paragraph - by design: the paragraph is used word for word (AC 3).
  - `[low]` `reject` Blind: the (told)/(learned) labels are English text the model writes, and no test pins them in a reply - spec-bound (AC 4 words the instruction; the real-model wording is REL-5's and 41.14's to measure).
  - `[low]` `patch` Blind: the Eval.Report header lists the scores only up to commands, userTurns - the header now lists documents, precedents and learnedSave.
  - `[low]` `reject` Blind: no test runs an upgrade of a populated table, and Pinned may read NULL - the appended storage slots are checked by test-storage.sh and live:storage-roundtrip in CI, and Row() reads an empty Pinned as 0; the SQL-side risk for a later story is in the deferred item.
  - `[low]` `reject` Edge: the learned-save right rule ignores tool steps - same claim as Blind's second; spec-bound.
  - `[medium]` `defer` Edge: rows saved before 41.8 hold no Pinned value, so later SQL on Pinned = 0 skips them - Row() covers every reader this story changes; the risk is Story 41.12's pinned read, deferred with the COALESCE note (unverified).
  - `[low]` `reject` Edge: Report.Text on a report built before this change has no scores.learnedSave - Text renders reports that Run has just built by the same code, as the precedents score of Story 41.7 does; no stored older report is rendered.
  - `[low]` `reject` Edge: the learned-save case has kind command, not user-turn - the user-turn kind is decided by Triage and has no reply to score, so it cannot measure the reply sentence the Planner ruling asks for; the case is a Chat turn of kind command and is recorded under Decided in-stage.
  - `[medium]` `patch` Verification gap: no test asserts pinned 1 or a learned source from a real stored row through Memory.Search's nearest and keyword SQL - TestSearchByMeaning and TestSearchByKeyword now store a learned, pinned row (a Pin helper method) and assert learned|1; the mutation is recorded.
  - `[low]` `reject` Verification gap, other: the Data.Turn fixtures are in state running, which Conversation.Sweep requeues - the sweep runs only when the production starts, which the tests do not trigger; a requeued fixture keeps its Text and TurnOfItem has no state filter, so the told and learned assertions cannot race with it (theoretical).
  - Intent alignment: no finding rows. It names bare "remember" as a phrase and the extra bullet, the tool-description change and the eval case as beyond the approach text; all are inside the spec's approved scope (Planner ruling planner-2026-11-09-41.8).

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
- **The learned-save eval case is a Chat turn of kind `command`, not kind `user-turn`.** A user-turn case is decided by Triage and has no reply, so it cannot score the reply sentence that Task 11 and AC 5 require. `eval/memory-learned-save/case.json` has `keyPhrases` for the reply, `Eval.Report` `LEARNEDCASES` takes it out of the `commands` score and every gated score, and the new report-only `learnedSave` line scores it. (Implement stage, 2026-11-09.)

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
   - (planner-2026-11-09-41.8, added) "- When you save a memory the user did not ask you to save, say so in your reply in one short sentence, for example: I'll remember that <the fact>."
5. Tool descriptions, model-facing, NOT IN UX:
   - `save_memory`'s second sentence becomes "Use it when the user asks you to remember something, or when the user states a lasting fact about their systems, partners, people or preferences, with the fact in the user's own words."
   - `search_memories` and `list_memories`: "Each memory has a ref, its text, when it was saved and its source: told (the user asked you to remember it) or learned (you saved it without being asked)."
6. No new refusal or reply text. A failed turn read reuses `MESSAGEFAILED`.

**Spine lines** (additive; no AD's Binds, Prevents or Rule wording changes):
- AD-29: insert after line 1003 ("Story 41.7, as built"):
  > `    - **Epic 41's second-part names** [ADDED 2026-11-09, Story 41.8]: `OcuTalon.Data.Memory` appends `Source` (`told` or `learned`; empty on a row saved before Story 41.8, which readers take as `told`), `Pinned` (0 by default) and `PinnedAt` (UTC to the second, empty while unpinned), written only by `MemoryOps`. `MemoryOps` sets `Source` on a save: `told` when the person's own text in the save's turn (`Data.Turn.Text`, read through `Ownership.TurnOfItem` by the save's ItemId and session) holds a phrase of `OcuTalon.Tools.MemorySource` `PHRASES` ("remember", "keep in mind", "note that", "don't forget"; whole words, case-folded), else `learned`; `Memory.Search` and `.List` give each row's `source` and `pinned`. The verbs `OcuTalon.Msg.Command.PinMemory` (`MemoryRef`) and `.UnpinMemory` (`MemoryRef`) carry the common `Origin`, `IdempotencyKey` and `SessionRef`, are accepted from origin `web_user` only (AD-1) and are routed by `CommandsIn` to `MemoryOps` (Story 41.9 creates them; Story 41.12 handles them). AD-31's `conversation.compacted` is not recorded: its amendment is undecided.`
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
  - `OcuTalon.Test.Eval.Cases` (planner-2026-11-09-41.8)
  - `OcuTalon.Test.Eval.Report` (planner-2026-11-09-41.8)

  Expected: each `CLASS ... passed`. A red that a stale `MemoryOps` job could explain counts only if the class is still red on a fresh run.
- (loop) `OCUTALON_RUN_TAG=e41s8i ci/iris.sh class OcuTalon.Test.Memory.Turns`. It runs fresh, because the ChatAgent and MemoryOps jobs must hold the new code. Expected: passed, in about 120 to 150 s on ARM (inference).
- (once) `OCUTALON_RUN_TAG=e41s8i ci/iris.sh class OcuTalon.Test.Memory.Ops`. Expected: passed, fresh.
- (once) `bash docker/tests/test-storage.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh` and `bash docker/tests/test-ci-config.sh`. Expected: all pass.
- (once) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16`. Expected: the baseline, as AC 1 states (10 low `placeholder` findings, no `ad_id`/`ad_fields`, nothing new).
- **Left to CI:** the `shards-2`, `production` and `image` pieces, `live:storage-roundtrip` (the compiled storage block against the committed one), `bash ci/checks.sh`, and the lead's fresh-environment check, forward and `--reverse`. The real model's reply wording ("(told)" in a reply) is REL-5's and 41.14's to measure.

**Mutations (Rule 19), one per AC. Record each as `mutation: <change> -> <test red>`:**
- AC 1: none. It is a documentation AC, checked by `lint_spine.py` and by grepping the three quoted lines.
- AC 2: `MemorySource.Of` always gives `learned` -> `Ops:TestSource` and `Turns:TestToldAndLearnedThroughTheAgent` (the told row). A second mutation: `READONLYSAVEMEMORY` 1 -> `Turns:TestUntrustedSave`.
  - mutation: `MemorySource.Of` ends `Quit ..#LEARNED` -> red: `Ops:TestSource` (every told row, "the first row keeps its Source"), `Ops:TestSourceReadFails` ("as told") and, on a fresh stack, `Turns:TestToldAndLearnedThroughTheAgent` ("the turn that says Remember that saved a told memory, not pinned"). Reverted, tree identical.
  - mutation: `READONLYSAVEMEMORY` 0 -> 1 in `MemoryTools` -> red: `Turns:TestUntrustedSave`, and `TestTaintedSave` and `TestTaintedSaveInOneResponse` with it (fresh stack). Reverted, tree identical.
- AC 3: one word of the learning paragraph changed in `Chat.cls` -> `PersonaBlock:TestParagraphs`.
  - mutation: "may save it" -> "can save it" in Chat's learning paragraph -> red: `PersonaBlock:TestParagraphs` (exactly once, last text, follows the proposals paragraph). Reverted, tree identical.
- AC 4: `Shown` omits `source` -> `Tools.Memory:TestListAnswer` and `Turns:TestToldAndLearnedThroughTheAgent`.
  - mutation: `MemoryTools.Shown` pushes no `"source"` -> red: `Tools.Memory:TestListAnswer` and `TestSearchAnswer`, and on a fresh stack `Turns:TestToldAndLearnedThroughTheAgent` ("each with its source"). Reverted, tree identical.
- AC 5: one word of the learned-save bullet changed in `Chat.cls` -> `Tools.Memory:TestInstructions`; the learned-save case moved into a gated score -> `Test.Eval.Report` (the gated share/count pin).
  - mutation: `Memory.Hits` passes "" for Pinned (review pass) -> red: `Memory.Search:TestSearchByMeaning` and `TestSearchByKeyword` (a stored learned, pinned row must come back `learned|1` through the nearest and the keyword paths). Reverted, tree identical.
  - mutation: `MemorySource.Of` joins the words of a phrase with a single space again (review pass) -> red: `Tools.Memory:TestSourceOf` ("keep in  mind", a line feed or a tab between the words of a phrase is told). Not run as a mutation; the patched regex is covered by the passing `TestSourceOf` run.
  - mutation: "one short sentence" -> "one brief sentence" in the learned-save bullet of `Chat.cls` -> red: `Tools.Memory:TestInstructions` (the six bullets once, in order, contiguous). Reverted, tree identical.
  - mutation: `Report.IsLearnedCase` always 0 (the case counts in the commands score) -> red: `Eval.Report:TestLearnedSaveReportOnly` (the commands score, the learned-save score and its line). Reverted, tree identical.
  - mutation: "Remember that" added to the turn of `eval/memory-learned-save/case.json` (a told phrase) -> red: `Eval.Cases:TestLearnedSaveCase`. Reverted, tree identical.

**QA stage (2026-11-09; tag `e41s8qw`, warm, lane A):**
- Test files added or changed (QA):
  - `src/ocutalon/cls/OcuTalon/Test/Memory/Ops.cls` (QA): `TestSourceIgnoresSavedText`, `TestSourceReadFailsLogged`.
  - `src/ocutalon/cls/OcuTalon/Test/Memory/OpsProbe.cls` (QA): the `SourceFailText` property, which the unreadable-turn status carries.
  - `src/ocutalon/cls/OcuTalon/Test/Memory/Search.cls` (QA): `TestLegacyRow`.
- Gaps closed: the model's saved text never decides `Source` (AC 2); the unreadable turn logs one redacted Type 3 warning and nothing of the memory or turn text (matrix "Turn read fails"); a row with `Source`, `Pinned` and `PinnedAt` truly empty (fixtures store Pinned 0) reads told and 0 through List, keyword search and search by meaning (AC 4, matrix "Old row").
- mutation: `MemoryOps.OnSave` also sets `source` told when the saved text holds a phrase -> red: `Ops:TestSourceIgnoresSavedText` ("is learned: the saved text is not read"). Reverted, tree identical.
- mutation: `MemoryOps.Failed` logs the status text without `Redact.Text` -> red: `Ops:TestSourceReadFailsLogged` (the redacted status text and "no part of the key"). Reverted, tree identical.
- mutation: `Memory.Row` sets `source` from the row without the told default (`Set row.source = source`) -> red: `Search:TestLegacyRow`, with `TestList` and `TestSearchByMeaning`. Reverted, tree identical.
- Runs (warm): `Test.Memory.Search` and `Test.Memory.Ops` passed after the reverts. Everything torn down.

**Code review (2026-11-09; tag `e41s8cw`, warm, lane A):**
- mutation: `Memory.Ops.Source` without `If $$$ISERR(sc) Quit sc` after `TurnOf` -> red: `Ops:TestSourceReadFails` ("failed, Ok 0, with no Ref", "no row is stored") and `Ops:TestSourceReadFailsLogged`. Reverted, tree identical (cmp with the scratch backup).
- mutation: `Memory.Ops.TurnOf` returns after `TurnOfItem` (no retry lookup) -> red: `Ops:TestSource` ("is told: the retry's turn is read"). Reverted, tree identical.
- Runs (warm): `Test.Memory.Ops` passed 18.7 s with the patch and again 17.3 s after the reverts; `Test.Docs.Chat` passed; `test-class-rules.sh` and `test-boundaries.sh` pass. Fresh (tag `e41s8c`): `Test.Memory.Turns` passed 17.5 s (stack ready 126 s). Both stacks torn down, no leftover container.

## Auto Run Result

Status: done
Blocking condition: none

- Summary: `Data.Memory` gains `Source`, `Pinned` and `PinnedAt` (storage values 9 to 11). `MemoryOps` decides `Source` from the save's own turn through `Ownership.TurnOfItem` and the new `Tools.MemorySource` (told for a fixed phrase as whole words, else learned; a failed turn read fails the save). `Memory.Search` and `.List` return `source` and `pinned`, and the list and search tools hand `source` to the model. Chat's instructions gain the learning paragraph as the last text, the (told)/(learned) wording on the search, list and forget bullets, and the learned-save bullet. The spine records the second-part names. The learned-save eval case has its own report-only `learnedSave` line.
- Files changed: `Data/Memory.cls` (columns, storage), `Tools/MemorySource.cls` (new), `Memory/Ops.cls` (the Source seam), `Memory.cls` (row members), `Tools/MemoryTools.cls` (source, descriptions), `Agent/Chat.cls` (bullets, paragraph), `Eval/Report.cls` (report-only line), `eval/memory-learned-save/case.json` (new), the spine (additive lines), and the tests `Test/Tools/Memory.cls`, `Test/Memory/{Ops,OpsProbe,Fixture,Search,Turns}.cls`, `Test/Agent/PersonaBlock.cls`, `Test/Contract/Step3.cls`, `Test/Eval/{Cases,Report}.cls`.
- Review: 16 findings; patches applied 3 (1 medium: Search pin pins on real rows; 2 low: white space between the words of a phrase, the Report header), deferred 1 (medium, unverified: Story 41.12's pinned read of pre-41.8 rows), rejected 12 with their reasons in the Review Triage Log. The intent-alignment layer gave a description and no findings.
- Follow-up review recommended: false (one medium patched, no high).
- Verification: warm `Test.Tools.Memory` 25 s, `Test.Memory.Search` 40 s, `Test.Eval.Report` 1 s, `Test.Memory.Ops` 16 s; fresh `Test.Memory.Turns` 17 s and `Test.Memory.Ops` 16 s; at the implement pass also `PersonaBlock`, `Instructions`, `Step3`, `Eval.Cases`, `Docs.Chat` and `test-eval-set.sh`; `test-storage.sh`, `test-class-rules.sh`, `test-boundaries.sh` and `test-ci-config.sh` all pass; `lint_spine.py` is at its baseline (`ok` false, exactly 10 low placeholder findings). Mutations are recorded under Verification. Left to CI: `shards-2`, `production`, `image`, `live:storage-roundtrip`, `ci/checks.sh`, the fresh-environment check, and the real model's reply wording.
- Residual risks: an eval turn cannot save (its owner `eval` is not a session), so the learned-save line measures the reply sentence only and stays report-only; the phrase list is English only.
- Throwaway locks: `LOCK acquired` and `released` for `warm-iris` (tag `e41s8iw`) and `throwaway-iris` (tag `e41s8i`), no `LOCK waiting`; both tags torn down, no leftover container.
