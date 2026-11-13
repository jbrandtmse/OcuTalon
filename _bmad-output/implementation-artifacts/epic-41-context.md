# Epic 41 Context: OcuTalon keeps a daily note, learns from your answers, and remembers what matters

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

OcuTalon's memory is controlled and seen by the person, and nothing from outside can feed it: daily notes, precedents from the person's own answers, learned and told memories, and pinned core memory. Part 1 (41.1 to 41.7) and part 2 (41.8, 41.9, 41.12 to 41.14) are done. The last story, 41.15, makes sure a learned save is never silent. When OcuTalon saves a fact it learned from the person's own words, code (not the model) adds a fixed line under the reply on every channel. The model can no longer leave out the announcement, as the 1.0.6 RC eval showed it does (memory-learned-save 0/3).

## Stories

- Stories 41.1 to 41.9 and 41.12 to 41.14: done
- Story 41.15: Learned saves are announced by code (next; backlog)
- Parked: 41.10 and 41.11 (compaction facts). Don't plan around them or build toward them.

## Requirements & Constraints

**41.15's scope and priority:**
- It is not a 1.0.7 requirement, and the README makes no claim about it.
- In the pool it comes after the judge-visible items still queued (23.2, 37.2, 25.2, 23.5). Take it earlier only if a lane would otherwise idle.
- Chat's learned-save bullet stays exactly as it is. No change reaches the model, so no release-gate run is needed.

**The announcement:**
- Only a learned save that answers `saved` records an entry. Told, refused (gate-denied) and failed saves add nothing.
- At most 3 entries per turn. Each entry carries `memoryRef` and `text` only.
- The line is the catalog key `memory.learnedSaved`, verbatim: `I'll remember this: "{fact}". You can tell me to forget it.`
  - `{fact}` is the stored text unchanged, except that one trailing full stop is removed and text over 200 characters is cut to 200 with "…".
  - One line per entry follows the reply, the way check rows render, in the same turn: in the web chat, and on Telegram or the phone through Notify.
  - The line is plain text on every channel, because the fact comes from the user's words. It is escaped in the web chat and sent with no Telegram parse mode.
  - **No doubling:** no line is shown when the reply already says "I'll remember" or "I will remember", matched the way the reply guard matches a phrase.
- The reply text itself is never changed.

**Tests 41.15 must have:**
- A fact ending in a full stop, and a 300-character fact.
- A fact containing markup, rendered inert on the web and on Telegram.
- A told save, a refused save and a failed save each add nothing.
- The reply already says it, so no line is shown.
- A second-session check proves that one session's `Learned` never shows in another session's chat or `/v1/state` payload.
- The eval case `memory-learned-save` stays report-only. It scores right whenever both the learned entry and the rendered line are present.

**Standing rules:**
- **Real-HTTP route tests:** sign in as the unprivileged LIVE fixture user (`OcuTalonUser` only, never the README admin account). A PANEL second session sees none of LIVE's rows.
- **No real model key in any runner:** CI uses the mock, and real-model eval runs only at the release gate.
- **Tests stand alone:** each passes on a fresh environment, in either order, and creates and removes its own rows.

**Memory invariants:**
- **Never from outside content:** an untrusted or tainted turn is denied `save_memory` at the gate.
- **Learned saves come only from the person's own turns:** an unasked save happens only in a trusted, untainted turn.
- **Only the person pins:** pins come only from `PinMemory` with origin `web_user`.
- **Forgetting really forgets:** it removes the row, the vector, the `%iFind` entry and any pin. Earlier messages in the current conversation aren't rewritten.

## Technical Decisions

**Lanes for 41.15:**
- Lane A: `Tools/MemoryTools.cls`.
- Lane B: `Core/Conversation.cls`, `Data/Turn.cls`, the message catalog, the web chat and `Notify`.
- Shared files take added lines only.
- The spine gets additive lines under AD-21 and AD-28 (accepted veto items).

**The data path follows the citations and memories pattern:**
- The runner copies the bridge context's `HostData` (JSON that tools fill) onto the bridge `Reply`. It reaches `Conversation` beside `checks`, `citations` and `memories`, which are built by code from tool results, never from model text, and are absent when empty.
- 41.15 adds the HostData member `learned`, an array of `{memoryRef, text}`, filled by `MemoryTools` on a `save_memory` that stored `Source` `learned` and answered `saved`.
- `Conversation` keeps the entries on the Turn as a new property `Learned` (JSON, at most 3 entries), beside `Citations` and `Memories`. Model the drop rules on those: malformed entries dropped, absent when there are none.
- `Conversation` carries the entries on the `Outbound` and on `chat.message` / the `/v1/state` chat items, the way it carries citations and memories.
- The trace shows the Turn's `Learned`.

**AD-28, code-written lines:**
- Reserved and code-written text is a catalog entry, chosen by code and rendered by the `*Out` operations and the page. It is added after the reply guard has run.
- The guard (`OcuTalon.Checks.ReplyGuard`, the bridge's `ReplyFilterClass`, `Filter(text, hostData)`) runs once on model text. It must not touch the code-written line.
- `Catalog.Render`'s slot cleaning removes only control characters and line breaks. Escaping for the web and plain sending for Telegram are the channel's job.

**Told or learned (built in 41.8):**
- `MemoryOps` sets `Source` on a save. A save is `told` when the person's own turn text holds a phrase from `OcuTalon.Tools.MemorySource` `PHRASES` ("remember", "keep in mind", "note that", "don't forget"; whole words, case-folded). Every other save is `learned`.
- An empty `Source` (a row saved before 41.8) reads as told.
- A repeated save (same `ItemId` and the same text) answers `saved` with the first row's `Ref` and writes no second row.

**Eval:**
- `Eval.Report` has a report-only `learnedSave` line. `Report.IsLearnedCase` keeps the case out of the gated scores.
- Owner-`eval` items never reach `Notify`.
- A `command` case may declare `session` (41.14): `EvalIn` makes an eval-only Session row, and `TurnResult` keeps `HostData.memories`.
- `Test.Eval.Cases`, `Test.Eval.Report` and `Test.Eval.In` are contended across epics, so add lines only.
- A warm stack keeps running old operation code after a recompile, so restart the production there.

## UX & Interaction Patterns

- Check rows are code-computed lines that render under the reply. The learned-save line renders the same way, one line per learned entry.
- An answer that recalls a memory carries a "From memory" chip. Memories are labelled "Told" or "Learned" in the Memory card.
- The line's wording promises that the person can say "forget it". Forgetting goes through the existing `forget_memory` tool and the card's Forget.

## Cross-Story Dependencies

- 41.15 builds on 41.8's `Source` decision and save gate, and on 41.14's eval session case for `memory-learned-save`.
- From Epics 19 and 20 it reuses `save_memory` / `MemoryOps`, the HostData `memories` and `citations` path, and the Turn's `Citations` and `Memories` storage and payload parts.
- It reuses Epic 5's catalog, check-row rendering and reply guard, and the Telegram and phone delivery through `Notify`.
