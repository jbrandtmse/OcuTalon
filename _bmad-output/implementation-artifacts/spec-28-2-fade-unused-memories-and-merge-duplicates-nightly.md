---
title: 'Story 28.2: Fade unused memories and merge duplicates nightly'
type: 'feature'
created: '2026-11-16'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-28-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/evidence/19-3-task0-memory-indexes.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Recall ranks a memory nobody has used for months exactly like a fresh one, and repeated saves of the same fact pile up as duplicates, so recall gets less relevant as memory grows (FR-43, step 7).

**Approach:** Record when a memory is used in an answer (a new `LastUsedAt` on `OcuTalon.Data.Memory`, written by `MemoryOps`), weight down unused memories in the recall fusion after a configured period (product setting `memory.fadeDays`, seed 90), and run a nightly task that enters through the production, merges duplicates within one owner by vector plus keyword similarity without a model, keeps every source on the kept memory and every merged memory's text in an owned merge record, and shows each merge in Visual Trace.

## Boundaries & Constraints

**Always:**
- **R-28.2-1 (BINDING, Planner condition 1): an explicitly saved memory is never lost without a trace.** (a) Fading only multiplies an unpinned memory's fused score by `FADEWEIGHT`; it never drops a memory from a result it would otherwise be in, so a faded memory still comes back when nothing else matches. (b) Pinned memories are never merged (neither kept nor merged away) and never fade. (c) In a duplicate set that holds a `told` memory the kept memory is `told` (the oldest `told` member). (d) In the same transaction that deletes a merged memory, its text, `Source`, `Origin`, `ItemId`, `SavedAt`, `LastUsedAt` and `Sources` are written to the merge record and its source entries are added to the kept memory's `Sources`. (e) Only a forget of the kept memory (`OnForget`) or a session drop (`Memory.DropSession`) deletes a merge record.
- **R-28.2-2 (never more trusted, Planner condition 5):** the kept memory's `Origin` is `tool` only when every member's `Origin` is `tool`; otherwise it takes the `Origin` of the oldest member (by `SavedAt`, then row id) whose `Origin` is not `tool`. A recall that returns it is therefore never trusted when any merged memory would not have been.
- **R-28.2-3 (BINDING, Planner gate 2026-11-16): merge precision before any merge runs.** Task 0 builds a labelled set of at least 20 true near-duplicate pairs and at least 20 similar-but-DISTINCT pairs (including the same subject with a different value or date, and negations); the chosen `DUPCOSINE` / `DUPKEYWORDS` give ZERO merges on the distinct pairs. The rates and thresholds go to the Planner before implementation continues past Task 0; if zero false merges is not reachable with a useful true-merge rate, this story ships fading only (ACs 1-3) and the nightly merge moves to Story 28.4 (pre-approved split).
- **Equivalence (BINDING, Planner gate):** with every memory inside `memory.fadeDays` and no merge records, recall returns exactly the same refs, in the same order and with the same text, as before this story. Any change that would alter recall for fresh memories is model-facing: STOP and report it.
- Owners never mix (AD-4): one `Consolidate` message names one `SessionRef`, and every query of the merge carries `WHERE SessionRef = ?`.
- `MemoryOps` (`OcuTalon.Memory.Ops`) stays the only writer of `Data.Memory` and of the merge record (AD-21, AD-33); `Memory.DropSession` deletes both in `SessionOps`' job under the same lock.
- The nightly path calls no model and no embedding (NFR-20): it uses stored vectors only.
- Storage is append-only (AD-5): new properties take the next slots; every new persistent or message class commits its compiler-generated `Storage` block.
- Product code reads the period only through `OcuTalon.Data.Setting.Get` (Conventions "Settings").

**Never:**
- No Lane B file is edited (AD-33; Epic 27 is in flight): not `Core/Conversation.cls`, `Core/CommandsIn.cls`, `Core/SettingsOps.cls`, `Msg/Catalog/Core.cls`, `Msg/Command/*`, `Test/Core/**` or the web app.
- No model-facing text changes: no tool description, prompt line, `search_memories`/`list_memories` answer shape or core-memory block changes.
- No memory text in a production message body, log line, warning or audit entry written by this story; texts live only in `Data.Memory` and the merge record.
- No user-facing text ships unless the Planner accepted it at the spec gate (PUBLIC TEXT proposals below; P2 never ships in this story).
- The nightly task changes nothing on an online-demo install.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Used in an answer | Usable turn reply whose `HostData.memories` holds refs R1, R2 of the session | `LastUsedAt` of R1, R2 = the accept time; other memories unchanged | Async; a failure is one warning, the reply is never changed |
| Used: foreign or unknown ref | `Used` names another session's ref or an unknown ref | Ignored, nothing written | none |
| Used: older time | `UsedAt` earlier than the stored `LastUsedAt` | Stored value kept (never moves back) | none |
| Fallback reply | Unusable reply | `Accepted` not called, nothing written | none |
| Fade, equal match | Two unpinned memories, same fused score, one last used (else saved) before now − `memory.fadeDays` | Recent one ranks first | none |
| Fade, only match | Only a faded memory matches | It is returned | none |
| Fade, pinned | Pinned memory older than the period | Never weighted down | none |
| Setting value | `memory.fadeDays` absent, empty, not a whole number ≥ 1 | 90 days | none |
| Duplicates merge | Owner A: d1 (`told`, `tool`), d2 (`learned`, `tool`) duplicate | One merge: d1 kept, d2 deleted, d1 `Sources` holds both, one merge record with d2's text and source | Transaction; failure rolls back the set, warning, next set |
| Mixed origin | Duplicate set with one `photo` member | Kept `Origin` = `photo` (R-28.2-2) | none |
| Pinned duplicate | A pinned memory duplicates an unpinned one | Neither changes | none |
| Near-miss distinct | Same sentence, different name ("Lee" vs "Kim") | Not merged | none |
| Other owner | Owner B holds the same texts | B's rows never join A's sets; B's own duplicates merge within B only | none |
| Second run | Same data, task runs again | No merge, no new record; `Consolidated.Count` 0 | none |
| Kept merged again | Kept K1 (with records) is merged away into K2 | K1's records are re-pointed to K2; K2's `Sources` holds all | none |
| Forget kept | `ForgetMemory` of a kept memory | Row and every merge record with that `KeptRef` deleted | Same transaction |
| Sign-out | `Memory.DropSession` | Session's memories and merge records deleted | Lock timeout → error status (resumable) |
| Sources overflow | Merged `Sources` would pass `MAXLEN` | That set is not merged; counted `skipped` | Warning without text |
| Production stopped / demo | Task runs while production stopped, or on the online demo | Ends OK, sends nothing, changes nothing | none |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Data/Memory.cls` -- Lane A table; storage slots 1–11 (last `PinnedAt`); append `LastUsedAt` (%String MAXLEN 20, slot 12) and `Sources` (%String MAXLEN 32000, JSON array, slot 13).
- `src/ocutalon/cls/OcuTalon/Memory.cls` -- `Search`, `Fuse` (RRF k=60, ties newer `savedAt` then higher id; output keys pinned by `Test.Memory.Search` line ~101), `NEARESTSQL`/`KEYWORDSQL` (selected columns; `NEARESTSQL` text is explained by `Test.Memory.Volume`, do not change its plan-relevant text), `Hits`, private `Row`, `Words` (token rule to reuse), `DropSession`.
- `src/ocutalon/cls/OcuTalon/Memory/Ops.cls` -- `MessageMap`, `Lock` (`^OcuTalon.Memory(sessionRef)`, 5 s), `Answer`, `Failed` (redacted warning), `OnForget`, `OpsProbe`/`PinsProbe` test subclasses call handlers directly.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls:1513-1530` -- `Accept(request, text, response)` calls `ContentClass.Accepted` once after the decision row is saved; `response.HostData` holds the reply's `memories` (built by code, Conventions "Citations and memories").
- `src/bridge/cls/OcuTalon/Bridge/Ext/Content.cls:27` -- base `Accepted(request, text, Output hostData)`; overrides: `src/ocutalon/cls/OcuTalon/Agent/Content.cls:52`, `src/ocutalon/cls/OcuTalon/Test/Bridge/ContentProbe.cls:28`.
- `src/ocutalon/cls/OcuTalon/Agent/Content.cls:52-75` -- caption save; returns early for non-untrusted turns, so the `Used` send must come before that gate; `OnlineDemo()` seam (line ~108) and `Test/Agent/ZzDemoContent.cls` show the demo-override pattern.
- `src/ocutalon/cls/OcuTalon/Schedule/HeartbeatTask.cls` (Lane B, read-only) -- `OnTask`/`Stopped`/`Quiet` with `ITEM`; the sibling the new task extends.
- `src/ocutalon/cls/OcuTalon/Watch/FailurePoller.cls:115-119` -- per-session trace: `Set ..%SessionId = ""`, `Set ..%SuperSession = <TraceRef>` before each send.
- `src/ocutalon/cls/OcuTalon/Install/Step/Memory.cls` -- `Run` only today; add `Tasks()` and the seed. `Install/Step/Retention.cls:25-90` (`Tasks()` shape, `Schedule()` = daily 03:00, `RescheduleOnStart`), `Install/Step/Digest.cls:14-15` (`Install.Seeds.Defaults` call).
- `src/ocutalon/cls/OcuTalon/Production.cls:15-71` -- Lane A region; adapterless service shape: line 29 `ApprovalStartIn` `PoolSize="0"`; `MemoryOps` at line 68.
- `src/short-names.tsv:31` -- registry row shape; `docker/tests/test-storage.sh` enforces rows, `^OcuTalonP.` and storage locations.
- `src/ocutalon/cls/OcuTalon/Test/Memory/Fixture.cls` -- `Store(owner, ref, text, savedAt, origin, itemId, source)` (real embedding), `Purge(prefix)`; `Test/Memory/Pins.cls:455-470` -- session fixture and a row with a constructed vector (no embedder).
- `src/ocutalon/cls/OcuTalon/Test/Memory/Turns.cls` -- real Chat turns through `Decide` (`OcuTalon.Test.Agent.RunnerFixture`, CI mock scenario `memory-recall-keyword`), reads `HostData.memories`; base `OcuTalon.Test.Core.InProduction` (Lane B, extend only).
- `src/ocutalon/cls/OcuTalon/Test/Contract/Step3.cls:143-167` -- XData `Contracts` pins `Data.Memory`'s exact properties.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` -- XData `Items` (Lane A rows ~896-928) and item counts (~173, ~179).
- `docs/bridge-guide.md:319` and `docker/tests/test-bridge-guide.sh:704-708` (`content_lines`) -- the ruled `ContentClass` bullet, pinned verbatim.
- `ci/units.sh:20,156` -- Memory area runs in `shards-2` (`shard:lane-a@rest`), about 5 min headroom (inference); no line to add.

## Tasks & Acceptance

**Execution:**
**SCOPE (2026-11-16, R-28.2-3 fallback, pre-approved by the Contest Planner): this story ships last-used and fading only (ACs 1-3 of the epic block, plus the equivalence pin). Everything about merging (the consolidation, the merge record, `Sources`, the nightly task, `Consolidate`/`Consolidated`, the merge matrix rows, R-28.2-1 (b)-(e), R-28.2-2, R-28.2-3, the purge pin) is Story 28.4's and is NOT built here; see Design Notes "Moved to Story 28.4". Task 0 is done: `evidence/28-2-task0-duplicate-thresholds.md`.**

- [DONE 2026-11-16 by the lead: 3/30 true, 0/42 false at the only zero-false-merge setting; verdict fallback; `evidence/28-2-task0-duplicate-thresholds.md`. Do NOT re-run.] Task 0 (measure, throwaway only; R-28.2-3 HARD GATE, run and reported by the lead before the implement stage) -- on a lane-C throwaway, embed a labelled set of at least 20 true near-duplicate pairs (exact, case/punctuation, word order, light rephrasing) and at least 20 similar-but-DISTINCT pairs (same subject with a different value, number, name or date; negations) through `OcuTalon.Memory.Embedding.Embed`; record each pair's cosine and keyword Jaccard (the `Words` token rule); choose `DUPCOSINE` and `DUPKEYWORDS` that give ZERO merges on the distinct pairs, then the true-merge rate they reach; write `_bmad-output/implementation-artifacts/evidence/28-2-task0-duplicate-thresholds.md` (pairs, scores, thresholds, both rates). The implement stage takes the thresholds from that file and does not re-run Task 0.
- `src/ocutalon/cls/OcuTalon/Data/Memory.cls` -- append `LastUsedAt` with a doc comment; recompile and commit the generated storage (slot 12). (`Sources` is Story 28.4's.)
- `src/ocutalon/cls/OcuTalon/Memory/Msg/Used.cls`, `Consolidate.cls` (Ens.Request), `Consolidated.cls` (Ens.Response) (new) -- this story builds `Used` only (`SessionRef`, `MemoryRefs` (JSON array), `UsedAt`; readable class description, AD-26); `Consolidate` and `Consolidated` are Story 28.4's.
- `src/ocutalon/cls/OcuTalon/Memory.cls` -- parameters `FADEKEY = "memory.fadeDays"`, `FADEDAYS = 90`, `FADEWEIGHT = 0.5`; `FadeDays()` (setting, whole number ≥ 1 else 90); `NEARESTSQL`/`KEYWORDSQL` also select `LastUsedAt`, `Hits` carries `lastUsedAt` on input hits only; `Fuse(nearest, keyword, limit, fadeBefore = "")` multiplies the score of an unpinned hit whose `lastUsedAt` (else `savedAt`) is before `fadeBefore`, output shape unchanged; `Search` passes now − `FadeDays()`; (`Tokens` extraction and the merge-record delete in `DropSession` are Story 28.4's.)
- `src/ocutalon/cls/OcuTalon/Memory/Ops.cls` -- MessageMap `OnUsed` (session lock; own rows only; never moves `LastUsedAt` back); update the class description. (`OnConsolidate` and the merge-record delete in `OnForget` are Story 28.4's.)
- `src/ocutalon/cls/OcuTalon/Memory/In.cls` (new) -- adapterless business service `MemoryIn`: input a `Used` → `SendRequestAsync("MemoryOps")` with `%SuperSession` = the session's `TraceRef`; any other input is refused with an error status and changes nothing. (The nightly task's empty-input path is Story 28.4's.)
- `src/ocutalon/cls/OcuTalon/Install/Step/Memory.cls` -- `Run` seeds `{"memory.fadeDays": 90}` through `OcuTalon.Install.Seeds.Defaults`.
- `src/ocutalon/cls/OcuTalon/Production.cls` -- Lane A region: `<Item Name="MemoryIn" ClassName="OcuTalon.Memory.In" PoolSize="0" Enabled="true"/>` after `MemoryOps`.
- `src/bridge/cls/OcuTalon/Bridge/Ext/Content.cls`, `Bridge/Process/Decide.cls` -- `Accepted(request, text, Output hostData, replyHostData As %String = "")`; `Decide.Accept` passes `response.HostData`; the bridge names no OcuTalon class (rule `bridge-refs`).
- `src/ocutalon/cls/OcuTalon/Agent/Content.cls` -- `Accepted` first sends one `Used` (refs from `replyHostData.memories`, at most 5, `UsedAt` = now) through `MemoryIn` for a `turn` with an `OwnerRef`, then the unchanged caption logic; a `Used` failure never stops the caption and adds no member.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ContentProbe.cls`, `docs/bridge-guide.md:319`, `docker/tests/test-bridge-guide.sh` -- `ContentProbe` follows the new signature; the guide line and its `content_lines` copy change together to P1's exact text (approved verbatim by the Planner, 2026-11-16).
- `src/ocutalon/cls/OcuTalon/Test/Contract/Step3.cls`, `Test/Install/Production.cls` -- shared-surface updates (new properties; `MemoryIn` row and counts).
- `src/ocutalon/cls/OcuTalon/Test/Memory/Fixture.cls` -- extend `Store` with optional `lastUsedAt`, `pinned` (Rule 2: extend, don't copy `Pins.Memory`).
- Equivalence pin (Planner, replaces a key-holder A/B): `Test.Memory.Fade` asserts that, with every memory inside `memory.fadeDays` and no merge records, `Memory.Search` over the eval's memory fixtures (the memories the eval cases seed, `Eval.In` / `eval/**` memory cases, loaded in a test session) returns exactly the refs, order and texts that the pre-28.2 fusion returns (call `Fuse` with `fadeBefore` empty as the reference, and compare with `Search`'s output; also compare against a hard-coded expected list for at least one fixture set so the reference itself cannot drift).
- Tests (new, `OcuTalon.Test.Memory`): `Fade` (Fuse rows, real `Search`, the equivalence pin and the behaviour pins), `LastUsed` (InProduction: real turn, foreign/unknown refs ignored, never backwards, a `Used` through `OnUsed` via `OpsProbe`); `Test/Bridge/Content.cls` gains `TestAcceptedGetsReplyHostData`. Keep the new classes' total run near 2 minutes (shards-2 headroom).

**Acceptance Criteria:**
- Given a session memory and a Chat turn through `Decide` (CI mock `memory-recall-keyword`) whose usable reply's `HostData.memories` holds it, when `Decide` accepts the reply, then within 10 seconds the row's `LastUsedAt` is at or after the turn's start, another memory of the session keeps an empty `LastUsedAt`, and the reply's `HostData` is unchanged by it (Integration AC: consumer `Agent.Content` via `Decide`; `Test.Memory.LastUsed`).
- Given `Decide` accepts a usable turn reply, when it calls `ContentClass.Accepted`, then the probe receives the reply's `HostData` JSON as `replyHostData` (`Test.Bridge.Content`).
- Given two memories of one owner with the same match, one last used (else saved) before now − `memory.fadeDays` and unpinned, when `OcuTalon.Memory.Search` ranks them, then the recent one comes first; given only the faded one matches, then it is returned; given it is pinned, then it is not weighted down; given it was forgotten, then it never comes back (`Test.Memory.Fade`).
- Given memories all inside `memory.fadeDays` and no merge records, when `OcuTalon.Memory.Search` runs over the eval's memory fixtures, then it returns exactly the refs, order and texts the pre-28.2 fusion returns (equivalence pin; `Test.Memory.Fade`).

## Spec Change Log

- 2026-11-16 (lead, R-28.2-3 fallback after Task 0: 3/30 true, 0/42 false at the only zero-false-merge setting): split per the Planner's pre-approval. 28.2 = last-used + fading + equivalence pin; the merge, its record, `Sources`, the task and the purge pin moved to Story 28.4 (inserted in epics.md). Task 0 is complete and not re-run.

- 2026-11-16 (lead, Planner spec gate): R-28.2-3 and the equivalence rule added to Always; Task 0 enlarged to the 20+20 labelled set with zero false merges, run and reported by the lead before implement; purge and equivalence pins added to Tasks and ACs; the Nightly AC amended per G7; P1 approved verbatim.

## Review Triage Log

## Design Notes

**Planner gate rulings (2026-11-16, `prompts/story-282-rulings-20261116.md`, binding):** G1-G4 approved (condition: merge records hold personal text, so the existing user and session data purge deletes them too; pinned). G5 approved: AD-31's optional `replyHostData` is recorded in the spine as a re-architecture under U7 (reason: it keeps the story inside Lane A's files, and an optional trailing argument breaks no caller). G6 approved (Tick precedent). G7: texts stay out of Visual Trace; the AC now says the trace shows refs, sources, counts and time only; no literal one-line change. G8: R-28.2-1, R-28.2-2 binding, plus R-28.2-3 (merge precision hard gate in Task 0, report before continuing). P1 approved verbatim. P2 not shipped (it comes with the story that shows it). Model-facing: no A/B; instead the equivalence pin and the behaviour pins (faded sole match returns; faded ranks below a fresh equal match; pinned never fades) and the STOP rule. Split fallback pre-approved (28.2 = ACs 1-3, 28.4 = the nightly merge), also under R-28.2-3. CI: report the measured shards-2 time at PART READY.

**Moved to Story 28.4 (not this story's work; kept here for 28.4's planner):**
  - `src/ocutalon/cls/OcuTalon/Memory/Data/Merge.cls` (new, Lane A) -- persistent merge record, `DEFAULTGLOBAL = "^OcuTalonP.MemoryMerge"`: `Ref` (unique), `SessionRef`, `KeptRef` (indexed), `MergedAt`, `Merged` (JSON array of `{memoryRef, text, source, origin, itemId, savedAt, lastUsedAt, sources}`); committed storage.
  - `src/short-names.tsv` -- add `MemoryMerge	^OcuTalonP.MemoryMerge	OcuTalon.Memory.Data.Merge	A`.
  - `src/ocutalon/cls/OcuTalon/Memory/Consolidation.cls` (new) -- the merge rules as class methods called only from `MemoryOps`' job: candidates = the owner's unpinned rows in (`SavedAt`, id) order; for each unassigned seed, neighbours from a separate owner-filtered nearest query that selects the cosine (do not reuse `NEARESTSQL`, whose text `Volume` explains); duplicate = cosine ≥ `DUPCOSINE` and token Jaccard ≥ `DUPKEYWORDS`; kept per R-28.2-1 (c) else the oldest; kept `Source`/`Origin`/`LastUsedAt` (max)/`Sources` per R-28.2-1 and R-28.2-2; per set one transaction: write the record, re-point records whose `KeptRef` is a merged ref, update the kept row, delete the merged rows.
  - `src/ocutalon/cls/OcuTalon/Memory/Task.cls` (new) -- extends `OcuTalon.Schedule.HeartbeatTask` with `TaskName = "OcuTalon memory consolidation"`, `ITEM = "MemoryIn"`; `OnTask` returns OK and does nothing when `OnlineDemo()` (seam: `Data.Setting.Get("onlineDemo") = 1`), else the inherited run.
  - Purge pin (Planner condition on G1-G4): merge records hold personal text, so every existing path that deletes a session's or user's memories deletes its merge records too: `Memory.DropSession` (sign-out, and `Eval.In`'s eval-session drop, which calls it) and `OnForget` of the kept memory. Pin both in `Test.Memory.Consolidate`, and assert that `OcuTalon.Install.Step.PrivateData`'s storage scan lists `^OcuTalonP.MemoryMerge` (it resolves to OCUTALON_PRIVATE). `Data.Purge` deletes no memories (a session holding one is kept), and a merge record only exists with its kept memory: state this in the class description.
  - ACs moved:
  - Given owners A and B with duplicate, near-miss and pinned memories and production running, when `OcuTalon.Memory.Task` runs, then only A's and B's own duplicates merge (never across owners), every source is on the kept memory, each merge record (owned, `OcuTalon.Memory.Data.Merge`) holds the merged texts, sources and time, Visual Trace (`Ens.MessageHeader`) holds a `Consolidate`→`MemoryOps` request and a `Consolidated` response per owner with `SuperSession` = that owner's `TraceRef`, showing refs, sources, counts and time only, and no memory text in either body [AMENDED 2026-11-16, Planner gate G7: the trace shows refs, sources, counts and time only; texts live only in the owned merge record], and the CI mock's log records no model request during the run (Integration AC: consumer Visual Trace; `Test.Memory.Nightly`).
  - Given the same data, when the task runs a second time, then no merge is made, no record is added and `Count` is 0 (`Test.Memory.Nightly`).
  - Given the online-demo seam answers 1 or the production is stopped, when the task runs, then it returns OK, sends no message and changes no row (`Test.Memory.Nightly`).
  - Given a kept memory with merge records, when it is forgotten or its session is dropped (sign-out or eval-session drop through `Memory.DropSession`), then no merge record of it remains, and the private-data check lists the merge global (`Test.Memory.Consolidate`).

**Governing ADs (Rule 6):** AD-1 (production messages; `Used`/`Consolidate` are not command verbs), AD-4 (one owner per message), AD-5 (append-only storage), AD-6 (no model, no embedding in the nightly path), AD-10 (trust from `Origin`), AD-19 (product setting `memory.fadeDays`), AD-21 (memory, single writer, forgetting really forgets), AD-23/AD-27 (task declared by the area; retention), AD-26 (trace session tagged with `TraceRef`), AD-29 (lanes), AD-31 (`ContentClass.Accepted`), AD-33 (one owner per item and table). No AC contradicts an AD Rule; AD-31 and AD-1 need the amendments below.

**ACs against delivered code:** none is met today: `Data.Memory` has no last-used or sources property, `Fuse` has no fading, no consolidation, task, service or merge record exists (checked at `82d8f9f4425de2a741eb9433ec6b981e946539c3`).

**"Used in an answer" (Planner condition 4):** a memory is used in an answer when its Ref is in the `memories` member of the `HostData` of a usable turn reply that `Decide` accepts: the memories `search_memories` returned in that turn and the turn did not forget, the same list the reply's "From memory" chip shows. `list_memories` results, fallbacks and the Memory card's search do not count. The update happens when the answer is recorded: `Decide.Accept` runs after the decision row is saved. Path, Lane A only: `Decide.Accept` → `Agent.Content.Accepted(…, replyHostData)` → `MemoryIn` → `MemoryOps.OnUsed`. No Lane B edit is needed; the cost is the AD-31 contract change (gate item G5). Alternative not chosen: a hunk in Lane B's `Core/Conversation.cls` after it keeps `Turn.Memories`.

**Visual Trace and texts (Planner condition 8, gate item G7):** the texts of merged memories are the person's own stored data and are kept only in the merge record `OcuTalon.Memory.Data.Merge` (owned by the session, `SessionRef`, deleted with the kept memory or the session). Visual Trace shows each merge as the `Consolidated` response in the owner's trace (merge Ref, kept Ref, merged Refs with `Source`, `Origin`, `ItemId`, `SavedAt`, and the time) and never a text. If the Planner prefers the AC's literal reading (texts visible in the trace, as `SaveMemory` bodies already carry `Text`), add `text` to the `merged` entries; that is a one-line change.

**Decided in-stage:** pinned memories are excluded from merging and never fade; kept = oldest `told` member, else the oldest member; the kept memory keeps its own text (no rewrite); fading is a score weight (`FADEWEIGHT` 0.5), not a tie-break, because equal RRF scores almost never occur; `LastUsedAt` empty reads as `SavedAt`; the merge class lives in `OcuTalon.Memory.Data` (precedent `OcuTalon.Digest.Data.Item`), which keeps it out of `Test.Data.Tables` (Lane B shared, also changed by OCT-epic24); the task runs daily at 03:00 through `Retention.Schedule()`; one owner per `Consolidate`, sent synchronously (300 s) so the response shows in the trace; duplicate grouping is seed-based, not transitive, so a second run finds nothing new; thresholds come from Task 0.

**Rule 2 (extend, don't copy):** `Memory.Task` extends `Schedule.HeartbeatTask` (`ITEM`, `Stopped`, `Quiet`); `Fixture.Store` is extended instead of copying `Pins.Memory`; `Memory.Tokens` is extracted from `Words`; `Install.Step.Memory` reuses `Retention.Schedule()` and `Install.Seeds.Defaults`. Copy with reason: the consolidation's nearest query is a separate parameter because `Test.Memory.Volume` explains `NEARESTSQL` verbatim.

**Integration ACs, Consumes / Consumed-by (Rules 1–2):** Consumes: `Bridge.Process.Decide` (`ContentClass`), `Data.Setting.Get` and `Data.Session` `TraceRef` (Lane B, read only), `Install.Seeds`, `Install.Step.Tasks`, `Schedule.HeartbeatTask`. Consumed-by: Visual Trace (this story), `Tools.MemoryTools.SearchMemories` and `MemoryOps.OnSearch` through `Memory.Search` (this story). No consumers of the merge record or `Sources` beyond Visual Trace in this story; no later story is planned to read them.

**Online demo:** `LastUsedAt` updates and fading run (own session data only, nothing outward); the nightly task is OFF (does nothing), pinned by `Test.Memory.Nightly`; the merge record is never written there; `memory.fadeDays` is seeded as everywhere.

**Gate items (veto window):** G1 `Data.Memory` gains `LastUsedAt` and `Sources` (slots 12–13; demo: `LastUsedAt` only). G2 new table `OcuTalon.Memory.Data.Merge` holding memory texts; retention: lives until its kept memory is forgotten or the session dropped, never purged by age (demo: never written). G3 new task "OcuTalon memory consolidation", daily 03:00, through new item `MemoryIn` (demo: OFF). G4 new seeded product key `memory.fadeDays` = 90, no settings-page field (changing it on the page is a later Lane B story: `SettingsOps` `ALLOWLIST`, its `XData Sections`, the web settings form and a PUBLIC TEXT label). G5 AD-31 amendment: `Accepted` gains `replyHostData`. G6 AD-1: `MemoryIn` carries two internal messages outside `CommandsIn` (the heartbeat Tick precedent). G7 texts kept off the trace (above). G8 R-28.2-1/-2 as the merge's trust and keep rules.

**Proposed spine update (Rule 20; the lead writes it after the gate):**
- AD-21, new sub-bullet under Memory: "**Fading and consolidation (step 7, Story 28.2).** `Data.Memory` gains `LastUsedAt` (UTC) and `Sources` (JSON `{memoryRef, itemId, origin, source, savedAt}`), appended under AD-5. A memory is used when its Ref is in a usable turn reply's `HostData.memories`; `Agent.Content.Accepted` sends `OcuTalon.Memory.Msg.Used` through the adapterless `MemoryIn` and `MemoryOps` sets `LastUsedAt`, never backwards. `Memory.Fuse` multiplies the score of an unpinned memory last used (else saved) more than `memory.fadeDays` days ago (product setting, seed 90) by 0.5; it never removes one. The task `OcuTalon memory consolidation` (`OcuTalon.Memory.Task`, declared by the Memory step, daily 03:00, off on the online demo) calls `MemoryIn`, which sends `MemoryOps` one `Consolidate` per owner in that owner's trace session; `MemoryOps` merges unpinned duplicates (cosine ≥ `DUPCOSINE` and token Jaccard ≥ `DUPKEYWORDS`, measured in Story 28.2 Task 0) without a model, keeps the oldest `told` member else the oldest, gives it `Origin` `tool` only when every member had it, adds every member's sources, writes `OcuTalon.Memory.Data.Merge` (`^OcuTalonP.MemoryMerge`: kept Ref, merged texts and sources, time) and answers `Consolidated` (Refs, sources, time; no text). Forgetting the kept memory or dropping the session deletes its merge records."
- AD-31 `ContentClass` bullet: "`Accepted(request, text, Output hostData, replyHostData As %String = \"\")` … `Decide` passes the accepted reply's `HostData` JSON as `replyHostData`."
- AD-1: after the eval-seed bullet: "`MemoryIn` sends `MemoryOps` two internal messages that are not command verbs and that no tool, route or channel can send: `Memory.Msg.Used` (from `Agent.Content`) and `Memory.Msg.Consolidate` (from the nightly task)."
- AD-27: "Merge records (`Memory.Data.Merge`) are never purged by age; they go with their kept memory."
- Ownership tables: production item row `MemoryIn` | `OcuTalon.Memory.In` | A; Tables: Lane A gains `Memory.Data.Merge`; messages `OcuTalon.Memory.Msg.Used`, `.Consolidate`, `.Consolidated` | A.

**PUBLIC TEXT proposals (not shipped by this story):** P1 `docs/bridge-guide.md` ruled ContentClass bullet, the `Accepted` clause: "`Accepted(request, text, hostData, replyHostData)` is called once after `Decide` accepts a usable chat reply, with the filtered reply text and the reply's `HostData` as JSON text, and the members it returns in `hostData` are added to the reply's `HostData`." P2 (for a later Memory-card line, keys in `OcuTalon.Msg.Catalog.Watch`, new prefix `memoryMerge`): `memoryMerge.note` "{count} duplicate memories were merged into this one. Every source is kept." with one-form "1 duplicate memory was merged into this one. Its source is kept."

**Model-facing changes:** none (the order of recall results can change; no text the model reads changes).

**Contention (Planner condition 11):** OCT-epic27: no shared file. OCT-epic24: shares the spine (lead-written) only; its `Test/Data/Tables.cls` change is avoided by the merge class's package. OCT-epic25: no diff against the feature branch. Lane B classes are extended or read only (`Schedule.HeartbeatTask`, `Test.Core.InProduction`, `Data.Setting`, `Data.Session`).

**Ledger inbox:** none.

**Split fallback:** if the implement pass cannot finish, the natural split is 28.2 = last used and fading (ACs 1–3), 28.4 = nightly consolidation (ACs 4–7).

## Verification

Throwaway only (slot C is busy; the story mutates stored data). Fresh tag `e28s2i`, warm tag `e28s2iw`. Prefix every `ci/` command with `L` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=28 stage=implement'`. End with `ci/warm.sh down` (also after a failure). One test command per call, `timeout: 600000`.

**Commands:**
- `L OCUTALON_RUN_TAG=e28s2iw ci/warm.sh up` (once) -- expected: warm stack ready.
- `L OCUTALON_WARM=1 OCUTALON_RUN_TAG=e28s2iw ci/iris.sh class OcuTalon.Test.Memory.Fade` (loop) -- passed.
- `L OCUTALON_WARM=1 OCUTALON_RUN_TAG=e28s2iw ci/iris.sh class OcuTalon.Test.Memory.LastUsed` (loop) -- passed.
- `L OCUTALON_WARM=1 OCUTALON_RUN_TAG=e28s2iw ci/iris.sh class OcuTalon.Test.Bridge.Content` (loop) -- passed.
- `bash docker/tests/test-storage.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-bridge-guide.sh` (loop) -- exit 0.
- `L OCUTALON_RUN_TAG=e28s2i ci/iris.sh class OcuTalon.Test.Install.Production` (once, fresh: proves the `MemoryIn` item and the `memory.fadeDays` seed from the install) -- passed.
- `L OCUTALON_WARM=1 OCUTALON_RUN_TAG=e28s2iw ci/iris.sh class <C>` (once, one call each) for `OcuTalon.Test.Contract.Step3`, `OcuTalon.Test.Memory.Search`, `OcuTalon.Test.Memory.Ops`, `OcuTalon.Test.Memory.Pins`, `OcuTalon.Test.Memory.Drop`, `OcuTalon.Test.Memory.Turns`, `OcuTalon.Test.Agent.Content`, `OcuTalon.Test.Tools.Memory` -- passed. The rest of the suite is CI's (`shard:lane-a`, `shards-2`).

**Mutations (Rule 19, one per AC, recorded by the implement stage as `mutation: … → …`):** LastUsed: skip the `Used` send in `Agent.Content`; Bridge: pass `""` in `Decide.Accept`; Fade: `FADEWEIGHT` 1; equivalence: apply the weight to every memory (or change the tie-break) and observe the equivalence pin red; pinned: drop the pinned exemption; OnUsed: drop the never-backwards check.

**Shared surfaces:** `Data.Memory` property list (`Test.Contract.Step3` XData `Contracts`); production item list and counts (`Test.Install.Production` XData `Items`); the `ContentClass.Accepted` signature (`Test.Bridge.ContentProbe`, `Agent.Content`, the ruled guide line in `test-bridge-guide.sh`); `Data.Setting` rows (new seeded key; no test asserts the full list); Task Manager tasks (new task; no test asserts the full list). Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned at `82d8f9f4425de2a741eb9433ec6b981e946539c3` on `OCT-epic28`; halted after planning as instructed. Gate items G1-G8, PUBLIC TEXT P1-P2 and the proposed spine update are listed under Design Notes for the Contest Planner's spec gate.
