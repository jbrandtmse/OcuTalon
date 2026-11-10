---
title: "Story 41.15: Learned saves are announced by code"
type: 'feature'
created: '2026-11-10'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** OcuTalon can save a fact it learned from the person's own words without saying so. Chat's instructions ask the model to announce such a save, but the 1.0.6 release-candidate eval showed Claude Haiku 5.5 saved the memory and stayed silent in 3 of 3 runs (`memory-learned-save` 0/3). So 41.8's promise, "a learned save is never silent", does not hold on the real model.

**Approach:**
- Code, not the model, announces the save.
- When `save_memory` stores a memory with `Source` `learned` and answers `saved`, `MemoryTools` records `{memoryRef, text}` in the turn's HostData member `learned`.
- `Conversation` keeps the entries on the Turn as the new property `Learned`. It carries them on the Outbound (which the trace shows) and on `chat.message` and the `/v1/state` chat items.
- The web chat and Telegram render one line per entry under the reply, from the catalog key `memory.learnedSaved`:
  `I'll remember this: "{fact}". You can tell me to forget it.`
- No line is shown when the reply already says "I'll remember" or "I will remember".
- The reply text, the guard and Chat's instructions do not change.

## Boundaries & Constraints

**Always:**
- **Only a learned save that answered `saved` counts (AD-21).** It is recorded only when the stored row's `Source` is `learned`. This is 41.8's code decision, read back from the row, never guessed.
  - A told save adds nothing.
  - An old row (empty `Source`, read as told) adds nothing.
  - A save the gate denied adds nothing (the tool never runs).
  - A NOSESSION refusal, an owner refusal and a failed save add nothing.
- **HostData `learned` is a JSON array of `{memoryRef, text}` only.**
  - `text` is the stored text.
  - Each memoryRef appears once. There are at most 3 entries, in the order saved.
  - The member is absent when there is no entry.
  - A memory that `forget_memory` forgets later in the same turn is taken out again.
- **The Turn keeps the entries as `Learned` (JSON, at most 3).**
  - They are taken only from a usable reply, after the guard, as `Citations` and `Memories` are (Conversation.cls:27-34).
  - Malformed entries are dropped. The property is absent when there are none.
  - Turns saved before this story carry none.
- **The line is the catalog key `memory.learnedSaved`, verbatim** (Contest Planner ruling 2026-11-10): `I'll remember this: "{fact}". You can tell me to forget it.`
  - `{fact}` is the stored text unchanged, except for two cuts:
    - one trailing full stop (`.`) is removed;
    - text then longer than 200 characters is cut to 199 characters plus "…" (U+2026), so 200 in all.
- **One line per entry follows the reply**, in the same turn, on each channel that shows the reply:
  - the web chat, after the check rows and before the source chips;
  - Telegram, through Notify's routing to `TelegramOut`, after the reply and its check sentence.
- **Plain text everywhere** (the fact comes from the user's words):
  - Angular interpolation on the page, with no `innerHTML`;
  - no Telegram `parse_mode`.
- **No doubling.** No line is shown for a turn whose reply text already says "I'll remember" or "I will remember". This uses the reply guard's own matching (`ReplyGuard.PatternOf`: case ignored, any white space, `'` or U+2019, whole words). It is decided by one ObjectScript method that every renderer uses.
- **The reply text is never changed.**
  - The guard runs once on model text and never sees the line (AD-28).
  - `Conversation` renders no text.
- **Eval.** `memory-learned-save` stays report-only. It also scores right when the turn is not a fallback, the save rule holds, `TurnResult.Learned` holds the entry and the line renders. The existing phrase rule stays as it is. [AMENDED 2026-11-11, Contest Planner spec-gate ruling 4, owner's delegation] It is also right when the save rule holds and the reply passes the same no-doubling check (`Memory.Learned.Said`, the one server method), so a reply such as "I'll remember Lee…" counts as announced, and the eval and the user see the same thing. This is a one-call reuse in Epic 41's own eval file (`Eval/Report.cls`).
- **Session isolation.** One session's `Learned` never shows in another session's chat or `/v1/state` payload (AD-4).
- **Tests stand alone.** Every test added or changed passes on a fresh environment, in either order, and creates and removes its own rows, turns, memories and settings.

**Never:**
- Change `Agent/Chat.cls`: not its INSTRUCTIONS, not the learned-save bullet. The same goes for any tool description, which includes `SaveMemory`'s method doc comment. That text is model-facing and belongs to the release gate.
- Change the reply text, `ReplyGuard`, `eval/memory-learned-save/case.json` or the pins on it in `Test/Eval/Cases.cls`.
- Add any user-facing text other than the ruled line. That rules out a label, a heading, an aria-label, a Telegram prefix and a trace caption shown to users.
- Give the catalog entry a `web` variant.
- Make a non-additive edit to a contended path:
  - `Msg/Catalog/**`
  - `Agent/Chat.cls`
  - `web/src/app/{msg,incidents}/**`
  - `Live/Payload/**`
  - `Web/Api.cls`
  - `Data/Ownership.cls`
  - `web/src/app/{usage,history,header}/**`
  - `ci/iris.sh`
  - `docker/tests/lib-live.sh`
- Edit `Production.cls`, `ci/units.sh` or `src/module.xml`. No new test area, shard or group is needed.
- Add a role, a grant, a column to `Data.Memory`, or a stored property other than those named under Design Notes' spec-gate item 1.
- Change `MemoryOps`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Learned save | user turn "The Results partner's contact is Lee." → `save_memory`, row `Source` learned, `saved` | HostData `learned` = `[{memoryRef, text}]`; the Turn's `Learned` holds it; the page and Telegram show `I'll remember this: "The Results partner's contact is Lee". You can tell me to forget it.` | none |
| Fact ends in a full stop | stored "Lee is the contact." | `{fact}` = "Lee is the contact" (one stop removed; "Wait.." gives "Wait.") | none |
| 300-character fact | stored text of 300 characters | `{fact}` = the first 199 characters + "…", 200 in all; exactly 200 stays whole | none |
| Markup in the fact | stored `<b>Lee</b> & <script>x</script>` | the web shows the characters (no element made); Telegram sends them as written with no `parse_mode` | none |
| Told save | turn text holds "remember" → row `Source` told | nothing in `learned`; no line | none |
| Refused save | gate-denied (untrusted/tainted), NOSESSION, or owner `refused` | nothing in `learned`; no line | the tool's answer is unchanged |
| Failed save | owner `failed`, a failed submit, or the row not readable | nothing in `learned`; no line | a failed row read logs one warning (redacted status) |
| Reply already says it | reply "I'll remember that Lee is the contact." (or "I will remember", U+2019, any case) | the Turn keeps `Learned`; no line on any channel | none |
| Same memory twice | two saves answering the same memoryRef (repeat) | one entry | none |
| Four learned saves | four distinct learned memoryRefs in one turn | the first three entries | none |
| Saved then forgotten | `forget_memory` answers `forgotten` for a learned ref in the same turn | the entry is removed; the member goes when none is left | none |
| Fallback turn | the reply is unusable | no `Learned` on the Turn; no line | none |
| Another session | PANEL signed in while LIVE has a learned turn | PANEL's `/v1/state`, its events and its page carry no `learned` and no LIVE turn | none |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless given in full. Line numbers are as of `0eb14ea2`.

**Lane A: the producer**
- `Tools/MemoryTools.cls`:
  - The class doc :1-27 is not model-facing; add a bullet for `learned`.
  - `SaveMemory` :78-87 calls `CommandCall.Session()` without `.context`. Take the context here.
  - `Outcome` :130-136 builds the answer with `outcome`. The hook point is after `Outcome`: `answer.outcome = "saved"` and `answer.ref '= ""`.
  - `Remember`/`Merge` :154-195 are the merge siblings. `Merge` caps at `SEARCHLIMIT` and keeps `{memoryRef, text, savedAt}`.
  - `Unremember(memoryRef)` :167-182 is called by `ForgetMemory` :125. Extend it with the member name instead of copying it.
  - `ReadFailed` (~:199) is the warning sibling.
- The row read is `Data/Ownership.cls` `Memory(ref, sessionRef, .sc)` :764, read-only use. It is the tools' way to read rows (RecentActivity :132). It works for any session, eval sessions included (query :1180-1183). `Data/Memory.cls` `Source` :37, `Text` :21.
- `Tools/MemorySource.cls`: `TOLD`/`LEARNED` :9-12.
- `Memory/Ops.cls` (read-only):
  - `OnSave` :81-123: a repeat answers `saved` with the first row's Ref :93-95.
  - `Source` :128-135.
- `Tools/HostData.cls`: `Put`/`Get`/`Remove` :14-26.
- The new `Memory/Learned.cls` is pure code, with no production, AI Hub or Python. Its siblings are `Tools/MemorySource.cls` (pure phrase code) and `Checks/ReplyGuard.cls`:
  - `PatternOf(phrases)` :83-93 is public; the matching rule is in the doc :6-8.
  - The reuse precedent is `Docs/Reply.cls:22`.

**Lane B: keep and carry**
- `Core/Conversation.cls`:
  - The doc :27-34.
  - `LOGSOURCES` :122 and `MAXSOURCES` :125.
  - `Replied` :520-536 calls `Checked`, then `Sourced`, then `Conclude(turn, answer.Text, "")`.
  - `Sourced` :566-580 keeps the `memories` via `Kept(data, "memories", $ListBuild("memoryRef","text","savedAt"), "")`.
  - `Kept` :584-606 caps at `MAXSOURCES`. Give it an optional cap argument rather than copying it.
  - `Announce` :693-701 calls `ChatMessage.FromRow`.
  - `Tell` :703-727 copies `Citations` and `Memories` at :715-716, and sets `outbound.Text = turn.ReplyText`.
- `Data/Turn.cls`:
  - `ReplyText` :42, `Citations` :79, `Memories` :83.
  - Storage `TurnDefaultData` ends at `<Value name="25">Memories` :176-178. Append 26.
- `Msg/Outbound.cls`:
  - `Citations` :35, `Memories` :38.
  - Storage ends at name 11 :74-76. Append 12.
  - Nothing in `Channel/` reads `Citations` or `Memories` today. They exist for the trace (Story 20.2).
- `Live/Payload/ChatMessage.cls` (contended, additive only):
  - `Memories` :64 is `list Of Part.Memory(%JSONFIELDNAME="memories")`.
  - `FromRow` :72-100, with the memories at :97-98. Insert after them.
  - Empty lists are not exported: a running event has no member.
- `Live/Payload/Part/Memory.cls` (`ListFromJSON`) is the sibling for the new `Part/Learned.cls`.
- `Web/Api.cls` `ChatItems` :1201-1208 builds the `/v1/state` chat items through `ChatMessage.FromRow`. **No change**, and the same goes for `Data/Ownership.cls`.
- `Core/Rule/Notify.cls` :4 and its rule at ~:23-30 send an Outbound to `WebChatOut`, plus `TelegramOut` when the turn is a paired Telegram turn. **No change.**
  - `Channel/SimPhone/Out.cls` :56 maps `Msg.Notification` only, and no Turn has channel `phone`. So the phone shows no reply and gets no line (Design Notes).

**Channels**
- `Channel/Telegram/Out.cls`:
  - Doc :19 (plain text).
  - `OnOutbound` :151-164: `text`, then `$Char(10,10)` and `CheckSentence` :352, then `Deliver`.
  - `SendPart` :456-466 sets `chat_id`, `text` and `reply_markup` only. There is no `parse_mode`.
- The catalog:
  - `Msg/Catalog/Core.cls` (Lane B, contended): `XData Entries` :14, 135 keys, no `memory.*` prefix yet.
    - A key prefix lives in one class only (:10).
    - The text-slot sibling is `Msg/Catalog/Watch.cls:56-62` (`checks.notEverything`, `"slots": {"whatFailed": "text"}`).
    - Allowed fields: `text, web, slots, source, gap, one`. `source` must be ASCII.
  - `Msg/Catalog.cls`:
    - `Render(key, slots, channel, .sc)` :52.
    - `SlotText` :153-178: its trailing-period rule fires only when the template's next character is `.`, so it does not fire here.
    - `Clean` :276-282 handles control characters, line breaks and spaces. There is no truncation.
- `web/scripts/catalog.mjs` writes `web/src/app/msg/catalog.ts` (checked in; contended).
  - `LISTED_KEYS` :61-105 and `TEXT_SLOT_KEYS` :119-130 decide what the page gets.
  - Appending gives one new `PAGE_TEXTS` line and one `PAGE_SLOTS` line, with no reflow. `npm run build` runs `--check`.
- `web/src/app/msg/catalog.ts`: `renderPageText(key, slots)` :206 (a `text` slot is cleaned).
- The web chat (`web/src/app/chat/`, not contended):
  - `ocutalon-reply.ts` :83-88: `<app-check-rows>`, then `<app-answer-sources>`. Insert the learned lines between them.
  - `check-rows.ts`: `.sentence` :26 and the styles :70-79 are the styling sibling. Every value is interpolated.
  - `chat-view.ts`: `TurnView` :133-142 and the payload mapping :398-412 (`memories` :407-409).
  - There is no `innerHTML` anywhere under `web/src/app`.
- `web/scripts/payloads.mjs` generates `web/src/app/live/payloads.ts` (`ChatMessagePayload` :123-146, `interface Memory` :105). `--check` runs in the build.

**Eval**
- `Eval/In.cls`:
  - `Converse` :987-1008 bypasses Conversation by design (:176).
  - `Cite` :1139-1151 copies `HostData.memories` into `TurnResult.Memories`. Add `learned` beside it.
- `Eval/Msg/TurnResult.cls`:
  - `ReplyText` :32, `Fallback` :41, `Memories` :50.
  - Storage slots 11-12 :86-91. Append 13.
- `Eval/Report.cls`:
  - The doc :17-27.
  - `LEARNEDCASES` :128, `IsLearnedCase` :529.
  - `ScoreTurn` :719-803: the memory branch :761-767, the `learnedSave` tally :799.
  - `SaveSteps` :1051-1078, `MemoryRule` :1117-1141.
- `eval/memory-learned-save/case.json`: `keyPhrases [["I'll remember that","I will remember that"]]`, `save: saved`. Unchanged.
- `ci/mock/scenarios/B/memory-learned-save-chat.json` replies "I'll remember that …". This is the doubling case on the mock.

**Tests to extend (siblings)**
- `Test/Tools/Memory.cls` (InProduction, CommandsDouble behind CommandsIn):
  - `TestWriteAnswers` :224 pins the answer shape, which stays.
  - `TestHostDataMerge` :274, `TestForgetLeavesHostData` :356, `Begin(owner, itemId)` :464.
  - The fixture is `Test/Memory/Fixture.cls` `Store(owner, ref, text, savedAt, origin, itemId, source)` :114.
- `Test/Tools/CommandsDouble.cls`: SaveMemory answers `MEMORYREF`; modes `refuse`, `fail` and `empty`. Add a mode that answers a given Ref.
- `Test/Core/ConversationTurns.cls`:
  - `TestSourcesCarried` :1710, `TestSourcesShape` :1743, `TestSourcesNotOnFallbacks` :1808.
  - The probe is `Test/Core/ConversationProbe.cls:33-43` (it records the Outbound fields).
- `Test/Live/Payloads.cls`:
  - `TestContracts` :77, with the count 34 at :93.
  - The ChatMessage contract :1148-1171; `Part.Memory` :1483.
  - `TestChatMessageCarriesItsDecision` :382.
- `Test/Msg/Contracts.cls`: Outbound :210-224.
- `Test/Data/Tables.cls`: Turn :381-410.
- `Test/Web/Api.cls`: `TestStateChatDecision` :492 (`mine`/`theirs`, `StateBody`).
- `Test/Channel/TelegramOut.cls` (LiveCase on the CI mock):
  - `TestPlainText` :205, `TestCheckSentence` :505.
  - `Outbound(chatRef, text)` :78.
- `Test/Msg/Catalog.cls`:
  - Header :3.
  - `TestEntries` :80-86 counts 135 and 90; the ruling-comment pattern is :81-83.
  - The ten `web` wordings :489-490 stay as they are.
  - `XData Keys` :969 and `XData Fixtures` :1368 need an entry for every key.
- `Test/Eval/Report.cls` (add lines only):
  - `TestLearnedSaveReportOnly` :1083, `TestLearnedSaveNeedsTheSave` :1115.
  - `LearnedRun` :2378, `LearnedExpectation` :2417, `MemoryReport` :2442.
  - `TurnRow` :2543 sets any property.
- `Test/Eval/MemoryCases.cls`: `TestLearnedSaved` :519-544, `TestLearnedRefused` :547. Run it warm after a production restart.
- The web unit tests:
  - `web/scripts/chat-view.test.mjs` :314, :323.
  - `web/scripts/catalog.test.mjs`: :105-113 (`length, 54`), :119, :692-704.
  - `web/scripts/payloads.test.mjs` :83-85: the exact `ChatMessagePayload` tail regex.
  - `web/scripts/ux-strings.test.mjs`: `SOURCES` :174, `ac` :621. The line is in `epics.md`, not in EXPERIENCE.md.
- The e2e tests:
  - `web/e2e/chat/sources.spec.ts`:
    - `seed` :61, `open` :86.
    - S5's second session :341.
    - S7's real turn :486-556 (`wipe`, `send`, the CHAT user, scenario `memory-save`).
  - `web/e2e/api/memory.spec.ts`: the LIVE/PANEL idiom :225, :232, :333.
  - `web/e2e/support/iris.ts` `seedTurns` :416-447 sets `t.Memories` at :447.
  - `web/e2e/support/api.ts`: the events helpers.
  - The route is `/v1/events` (`Web/Api.cls:227`).
- `ci/mock/scenarios/A/memory-save.json` is the shape for a marker scenario. Its test is `ci/mock/test/scenarios.test.mjs`.

## Tasks & Acceptance

**Execution (in dependency order):**

0. **Measure first (Task 0, on the warm stack).**
   - (a) Confirm that `Ownership.Memory(ref, evalSessionRef)` opens an eval session's row inside a session case, so that the eval path can see `Source`.
   - (b) Confirm that an empty `list Of` is left out of `chat.message`'s JSON (`TestSourcesCarried`'s `%IsDefined` = 0).
   - Record both under Design Notes. If (a) fails, HALT with `intent gap`: the eval ruling then needs another source.

1. `src/ocutalon/cls/OcuTalon/Memory/Learned.cls` (new, Lane A). Pure code, with these parameters:
   - `KEY = "memory.learnedSaved"`
   - `MAXENTRIES = 3`
   - `FACTMAX = 200`
   - `SAID = "I'll remember,I will remember"`

   And these class methods:
   - `Fact(text)`: removes one trailing `.`, then cuts text longer than `FACTMAX` to `FACTMAX - 1` characters plus `$Char(8230)`.
   - `Said(replyText)`: `$Locate(replyText, ReplyGuard.PatternOf(..#SAID)) > 0`.
   - `Shown(learned As %String, replyText As %String) As %DynamicArray`: `[]` when `Said`, or when the JSON is bad or not an array. Otherwise `{memoryRef, fact}` for each object whose `memoryRef` and `text` are non-empty strings, at most `MAXENTRIES`.
   - `Lines(learned, replyText, channel, .sc) As %DynamicArray`: one `Msg.Catalog.Render(KEY, {"fact": …}, channel)` per `Shown` entry.

   The class doc states the contract. Write non-ASCII characters only as `$Char`.

2. `src/ocutalon/cls/OcuTalon/Tools/MemoryTools.cls`:
   - In `SaveMemory`, take `.context`. When the answer is `saved` with a `ref`, read the row through `Ownership.Memory(ref, context.OwnerRef, .sc)`. When `row.Source = MemorySource.#LEARNED`, merge `{memoryRef: ref, text: row.Text}` into HostData `learned`: the held entries first, then the new one, each memoryRef once, at most `Learned.#MAXENTRIES`.
   - A read error logs one warning through the `ReadFailed` pattern (no answer change) and adds nothing. A missing row adds nothing.
   - Extend `Unremember` to take the member, so that `ForgetMemory` removes the ref from both `memories` and `learned`.
   - The tool's answer is unchanged. Add a class-doc bullet. No method doc changes.

3. `src/ocutalon/cls/OcuTalon/Data/Turn.cls`: add `Property Learned As %String(MAXLEN = "")` after `Memories`, with a doc line ("rows saved before Story 41.15 hold no value"). Its storage is `<Value name="26">`.

4. `src/ocutalon/cls/OcuTalon/Msg/Outbound.cls`: add `Learned` after `Memories`, documented as for the trace and `TelegramOut`. Its storage is name 12.

5. `src/ocutalon/cls/OcuTalon/Core/Conversation.cls`:
   - Add `Parameter MAXLEARNED = 3`.
   - `Kept` gains an optional cap argument, with `MAXSOURCES` as the default.
   - `Sourced` sets `turn.Learned` from `Kept(data, "learned", $ListBuild("memoryRef","text"), "", ..#MAXLEARNED)`.
   - `Tell` copies `turn.Learned` to `outbound.Learned`.
   - Doc :27-34 names `learned`. Conversation renders nothing.

6. `src/ocutalon/cls/OcuTalon/Live/Payload/Part/Learned.cls` (new): `MemoryRef` (`memoryRef`) and `Fact` (`fact`), following `Part/Memory.cls`.
   `src/ocutalon/cls/OcuTalon/Live/Payload/ChatMessage.cls` (contended, additive only):
   - add one property `Learned As list Of Part.Learned(%JSONFIELDNAME = "learned")` after `Memories`;
   - in `FromRow`, insert after :98 the lines that fill it from `##class(OcuTalon.Memory.Learned).Shown(row.Learned, row.ReplyText)`.

7. `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls`: in `OnOutbound`, after the check sentence, when `Learned.Lines(request.Learned, request.Text, ..#TEXTCHANNEL)` is non-empty, append `$Char(10,10)` and the lines joined by `$Char(10)`. There is no `parse_mode`. Add a doc line.

8. `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` (contended, additive only): insert one entry **between two existing entries**, never at the end:
   ```
   "memory.learnedSaved": {"text": "I'll remember this: \"{fact}\". You can tell me to forget it.", "slots": {"fact": "text"}, "source": "Story 41.15 AC (Contest Planner ruling 2026-11-10)"}
   ```
   It has no `web` member.

9. `web/scripts/catalog.mjs`: add the key to `LISTED_KEYS` and `TEXT_SLOT_KEYS`. Regenerate `web/src/app/msg/catalog.ts` with `node scripts/catalog.mjs`. Expect two inserted lines and nothing else. `git diff` must show only `+` lines there.

10. `web/scripts/payloads.mjs` output: regenerate `web/src/app/live/payloads.ts`, which inserts the `Learned` interface and `learned?: Learned[]`.

11. The web chat:
    - `web/src/app/chat/chat-view.ts`: `TurnView.learned?` holds the payload entries, set only when non-empty, mapped beside `memories`.
    - `web/src/app/chat/learned-lines.ts` (new component `app-learned-lines`): one `<p class="learned">{{ line }}</p>` per entry, where `line = renderPageText('memory.learnedSaved', {fact})`. It has no label or aria text, and its styling follows `check-rows.ts` `.sentence`.
    - `web/src/app/chat/ocutalon-reply.ts`: insert it between the check rows and the answer sources.

12. `src/ocutalon/cls/OcuTalon/Eval/Msg/TurnResult.cls`: add `Learned` after `Memories`, with storage slot 13.
    `Eval/In.cls` `Cite`: copy a non-empty `HostData.learned` array, as `memories` is copied.
    `Eval/Report.cls`:
    - In the learned-case memory rule, right also when all of these hold: not a fallback, the save rule holds, `row.Learned` holds at least one entry, and `Learned.Lines(row.Learned, row.ReplyText, "web")` is non-empty.
    - The existing phrase rule is kept unchanged.
    - [AMENDED 2026-11-11, Contest Planner spec-gate ruling 4, owner's delegation] Right also when not a fallback, the save rule holds, and `##class(OcuTalon.Memory.Learned).Said(row.ReplyText)` is true: ONE call, added to the same rule, nothing else changed in the eval files. If that cannot be done as a one-call reuse in Epic 41's own eval files (`Eval/Report.cls`, `Test/Eval/Report.cls`, `Test/Eval/MemoryCases.cls`), HALT with an `intent gap` naming what more it needs (the lead reports it to the Planner).
    - Update the doc :17-27.
    - The tallies and report-only status are unchanged.

13. Tests (new methods and added lines; in-place edits only where noted):
    - `Test/Memory/Learned.cls` (new, plain `%UnitTest.TestCase`). Pin the I/O matrix rows:
      - `Fact`: stop, "..", 300 → 200, exactly 200, 201 ending in ".";
      - `Said`: both phrases, U+2019, case, "remembered" no, "We'll remember" no;
      - `Shown`: malformed, bad JSON, cap 3, said → `[]`;
      - `Lines`: the exact text for web and telegram, and markup kept as characters.
    - `Test/Tools/CommandsDouble.cls`: add the mode `^OcuTalonTest("CommandsDouble","memoryRef") = <ref>` for SaveMemory.
    - `Test/Tools/Memory.cls`, new tests:
      - `TestLearnedHostData`: a learned row stored at the double's Ref gives one entry; a repeat gives one; four refs give three; other members are kept.
      - `TestLearnedNothing`:
        - a told row, an old row and another session's row;
        - NOSESSION, `refuse` and `fail`;
        - each adds nothing, and the answer is unchanged.
      - `TestLearnedForgotten`.
    - `Test/Core/ConversationTurns.cls` and the probe (record `learned`):
      - `TestLearnedCarried`: Turn, Outbound and the done `chat.message` carry it; a running event does not.
      - `TestLearnedShape`: cap 3 and malformed entries.
      - `TestLearnedNotOnFallbacks`.
      - `TestLearnedSaid`: the Turn keeps the entries, and `chat.message` has no `learned`.
    - `Test/Live/Payloads.cls`:
      - in place: count 34 → 35;
      - added lines: the contracts for `Learned` and `Part.Learned`;
      - `TestChatMessageLearned`: fact shaping, said, absent when empty.
    - `Test/Msg/Contracts.cls` (Outbound) and `Test/Data/Tables.cls` (Turn): one inserted contract line each.
    - `Test/Web/Api.cls` `TestStateLearned`: `StateBody` gives `mine` its `learned` and `theirs` none.
    - `Test/Channel/TelegramOut.cls` `TestLearnedLines`, on the mock:
      - the exact sent text (reply, blank line, the line);
      - markup sent as written;
      - no `parse_mode`;
      - a 300-character fact;
      - a reply that says it adds nothing;
      - the check sentence first when present.
    - `Test/Msg/Catalog.cls`:
      - in place: the core count 135 → 136, with a ruling comment as at :81-83;
      - added: the `Keys` entry and the `Fixtures` entry, inserted mid-list.
    - `Test/Eval/Report.cls` (added lines only):
      - `TestLearnedSaveByTheLine`: a silent reply, a saved step and `Learned` give right;
      - the same with `Learned` empty gives wrong;
      - with `Fallback` it is wrong;
      - [AMENDED 2026-11-11, Contest Planner spec-gate ruling 4, owner's delegation] `TestLearnedSaveBySaid`: a reply "I'll remember Lee is the contact." (no "that"), a saved step and `Learned` give right; the same reply with no saved step gives wrong;
      - SM-1 and `commands` are unchanged.
    - `Test/Eval/MemoryCases.cls` `TestLearnedEntry` (added method):
      - the learned-save case's `TurnResult.Learned` holds the session memory's Ref and text;
      - `Lines` is empty, because the mock reply says it;
      - `memory-documents-remember` (denied) and `memory-learned-refused` (NOSESSION) have no `Learned`.
    - Web:
      - `chat-view.test.mjs`: a new test that carries `learned`;
      - `catalog.test.mjs`: in place, the key lists and `length` 54 → 55;
      - `payloads.test.mjs`: in place, the tail regex;
      - `ux-strings.test.mjs`: one added `ac` source, "Story 41.15 …".
    - e2e:
      - `web/e2e/support/iris.ts`: `SeedTurn.learned?` and one `Set t.Learned` line.
      - `ci/mock/scenarios/A/memory-learned-line.json` (new; marker `memory-learned-line`): `save_memory` {text "the Results partner's contact is Lee"}, then the reply "Noted."
      - `web/e2e/chat/sources.spec.ts`, new tests:
        - S10, seeded: a stop removed, 300 → 200 with "…", two entries in order after the reply, markup shown as characters (no `b`/`script` element).
        - S11, seeded: a reply "I'll remember that …" shows no line.
        - S12: inside S7's describe (reuse `wipe` and `send`), "The Results partner's contact is Lee. [[mock:memory-learned-line]]" shows the line live and again after a reload. S7's told save ("Remember that …") shows none.
      - `web/e2e/api/memory.spec.ts`, a new test as LIVE and PANEL:
        - LIVE's `GET /v1/state` is 200 with the seeded turn's `learned`;
        - PANEL's `/v1/state`, its `/v1/events` after LIVE's publish, and its page hold no `learned` and no LIVE turn.

14. The spine, `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`:
    - Add one bullet under AD-21's "Told and learned" and one under AD-28's Rule, each `[ADDED 2026-11-10, Story 41.15]`, as drafted under Design Notes.
    - Refresh `updated:`.
    - Run `memlog.py append --type decision`.
    - Run `lint_spine.py`. Expect the baseline only.

**Acceptance Criteria:**
- **AC 1 (AD-21).** Given a user turn's `save_memory`, when MemoryOps stores the row with `Source` `learned` and answers `saved`, then HostData `learned` holds `{memoryRef, text}` (the row's Ref and stored text), each ref once, at most 3, and absent when empty. A told save, an old row, a refusal (NOSESSION or owner) and a failed save add nothing. A ref forgotten in the same turn is removed. Pinned by `Tools.Memory:TestLearnedHostData` and `TestLearnedNothing`.
- **AC 2 (AD-21, AD-28).** Given a usable reply whose HostData holds `learned`, when Conversation keeps it, then:
  - the Turn's `Learned` and the Outbound's `Learned` hold the entries (malformed dropped, at most 3);
  - the reply text is byte-identical to the guarded text;
  - a fallback keeps none.
  Pinned by `ConversationTurns:TestLearnedCarried`, `TestLearnedShape` and `TestLearnedNotOnFallbacks`.
- **AC 3 (AD-28, Text OcuTalon sends).** Given a Turn with `Learned`, when its reply shows in the web chat (live and after reload) and on Telegram, then one line per entry follows the reply and reads exactly `I'll remember this: "{fact}". You can tell me to forget it.`. `{fact}` is the stored text with one trailing stop removed and cut to 200 with "…". Pinned by `Memory.Learned:TestFact`, `TelegramOut:TestLearnedLines`, `Payloads:TestChatMessageLearned`, and e2e S10 and S12.
- **AC 4 (plain text).** Given a fact with markup, when it is shown, then the page shows the characters and makes no element, and Telegram sends the text as written with no `parse_mode`. Pinned by e2e S10 and `TelegramOut:TestLearnedLines`.
- **AC 5 (no doubling).** Given a reply that already says "I'll remember" or "I will remember" (any case, `'` or U+2019, any white space), when it is shown, then no line appears on any channel. The Turn still keeps `Learned`. Pinned by `Memory.Learned:TestSaid`, `ConversationTurns:TestLearnedSaid`, `TelegramOut:TestLearnedLines` and e2e S11.
- **AC 6 (AD-4, standing route rule).** Given LIVE (OcuTalonUser only) with a learned turn and a PANEL second session, when each reads `GET /v1/state` and the events over real HTTP, then LIVE gets 200 with its `learned`, and PANEL sees no `learned` and no LIVE turn. Pinned by `api/memory.spec.ts` (new test) and `Web.Api:TestStateLearned`.
- **AC 7 (Integration).** Given the real chain on the CI mock, when the CHAT user sends a learned fact, then `MemoryTools` → HostData → `Conversation` → `chat.message` and `/v1/state` → the page shows the line, and a told save shows none. Pinned by e2e S12. On the eval path, `MemoryCases:TestLearnedEntry` pins the `learned` entry from the real `MemoryTools`.
- **AC 8 (AD-7).** Given `Agent/Chat.cls` and every tool description, when this story ships, then they are byte-identical to `0eb14ea2` (`git diff 0eb14ea2 -- src/ocutalon/cls/OcuTalon/Agent/Chat.cls` is empty, and `Test.Tools.Memory:TestInstructions` passes).
- **AC 9 (AD-22).** Given `memory-learned-save`, when it is scored, then it is right when the learned entry and the rendered line are both present (and not a fallback, with the save rule holding), and still right by the phrase rule, and [AMENDED 2026-11-11, Contest Planner spec-gate ruling 4, owner's delegation] also right when the save rule holds and the reply passes `Memory.Learned.Said` ("I'll remember Lee…" counts as announced). It stays report-only: SM-1 and `commands` are unchanged. Pinned by `Report:TestLearnedSaveByTheLine`, `Report:TestLearnedSaveBySaid` and `TestLearnedSaveReportOnly` (unchanged).

## Spec Change Log

- 2026-11-11 (spec gate; Contest Planner rulings ~00:15Z under the owner's delegation, relayed by the orchestrator; verbatim terms, from the orchestrator's `prompts/epic-41-rulings-4115.md`, section "Spec-gate rulings"; implement may start):
  > 1. STORED DATA: both ACCEPTED. (a) Msg.Outbound.Learned and (b) Eval.Msg.TurnResult.Learned: nullable JSON appended to storage, no migration, no grant, role or Data.Memory column (20.2 and 41.14 precedents).
  > 2. SCOPE: CONFIRMED, web chat and Telegram only (the channels that show a reply). Nothing is added for the phone. ("Telegram/phone" was the Planner's error.)
  > 3. CUT: ACCEPTED, 199 characters + "…" (200 in all), after removing one trailing ASCII full stop, matching Conversation.Cut.
  > 4. EVAL: fold in now. memory-learned-save scores right when the turn's Learned line would be shown, OR when the reply passes the same no-doubling check (the one server method), so "I'll remember Lee…" counts as announced and the eval and the user see the same thing. A one-call reuse in Epic 41's own eval files; if it's more than that, report it. The case stays report-only.
  Lead note (2026-11-11, decide): feature moved to 9f7db82c (Story 23.2 merged; it changed `Agent/Chat.cls`, `Msg/Catalog/Core.cls`, `Live/Payload/**`). This story is implemented on the current base and the lead integrates 9f7db82c (once green) before the push. AC 8's intent is "this story changes nothing in `Agent/Chat.cls` or any tool description": before the integrate-forward, `git diff 0eb14ea2 -- src/ocutalon/cls/OcuTalon/Agent/Chat.cls` is empty; after it, the check is `git diff <the merged feature head> HEAD -- src/ocutalon/cls/OcuTalon/Agent/Chat.cls` empty. Count lines and catalog entries that 23.2 also changed are summed at the integrate-forward (plain union).
  Applied: items 1-3 match the plan as written (Design Notes spec-gate items 1 and 3, "The phone", the 200-character cut). Item 4 amends the Eval bullet in Boundaries, Task 12's `Eval/Report.cls` rule, the `Test/Eval/Report.cls` task (`TestLearnedSaveBySaid`), AC 9, Design Notes "The eval rule", and the AC 9 mutation, each marked [AMENDED 2026-11-11, Contest Planner spec-gate ruling 4, owner's delegation].

## Review Triage Log

## Design Notes

**ADs:**
- AD-21: memory, `Source`, HostData.
- AD-28: code-written lines, the guard, catalog keys rendered by the `*Out` operations and the page.
- AD-6: HostData reaches Conversation on the Reply.
- AD-4: session ownership; the second-session check.
- AD-12: chat.message and the snapshot.
- AD-13: the web page.
- AD-14: Outbound routing.
- AD-31: the guard as ReplyFilterClass.
- AD-7: Chat is unchanged.
- AD-10: gate refusals.
- AD-22: eval.
- AD-5: storage appended.
- AD-29 and AD-33: lanes and owners.
- Conventions rows: "HostData", "Citations and memories", "Citations and memories on the page", "Text OcuTalon sends".

No AC contradicts an AD's Rule.

**Spine lines (Task 14, accepted veto items):**
- **AD-21**, under "Told and learned":
  > **Learned saves are announced (Story 41.15).** When `save_memory` answers `saved` and the stored row's `Source` is `learned` (read through `Ownership.Memory`), `MemoryTools` puts `{memoryRef, text}` into the HostData member `learned`: each memoryRef once, at most 3, and taken out again when the turn forgets it. A told, refused or failed save adds nothing. `Conversation` keeps a usable reply's entries on the `Turn` as `Learned` (JSON, at most 3, malformed entries dropped, absent when none) and on the `Outbound`. `chat.message` and the `/v1/state` chat items carry the entries to show as `learned` (`Live.Payload.Part.Learned`, `{memoryRef, fact}`). `Eval.Msg.TurnResult` keeps `HostData.learned`. [ADDED 2026-11-10, Story 41.15]
- **AD-28**:
  > **The learned-save line (Story 41.15).** One line per `Learned` entry follows the reply on the web chat and on Telegram. It is the catalog key `memory.learnedSaved`, whose `{fact}` comes from `OcuTalon.Memory.Learned` (the stored text with one trailing full stop removed, cut to 200 characters with "…"). The page and `TelegramOut` render it as plain text. No line is shown when the guarded reply already says "I'll remember" or "I will remember" (`ReplyGuard.PatternOf`). The guard never sees the line, and the reply text is never changed. [ADDED 2026-11-10, Story 41.15]

**Decided in-stage:**
- **Where the doubling rule sits.** The no-doubling check runs where the line is rendered, in one ObjectScript method, `Memory.Learned.Shown`. `ChatMessage.FromRow` (for both the page and `/v1/state`), `TelegramOut` and `Eval.Report` all use it against the guarded reply text (`Turn.ReplyText`, which is also `Outbound.Text`).
  - The Turn always keeps the entries, so the record and the trace are complete.
  - No `announced` member is stored, and the web holds no copy of the rule. The ruling fixes "no line rendered", and this meets it with one decision point.
- **The fact is shaped on the server.** The payload's `learned` carries `fact` (shaped by `Learned.Fact`), not the raw text. The page only fills the slot, so the shaping is not copied into TypeScript.
- **The 200-character cut** gives 199 characters plus "…", 200 in all. This follows the IRIS convention of `Conversation.Cut` and `Summary` (`Conversation.cls:402-407`, `:835-839`). The full stop is removed before the cut. Only an ASCII `.` is removed, and only once. `Catalog.Render`'s `Clean` then runs on the slot as for every slot.
- **The Source is read back through `Ownership.Memory`**, the tools' row-read API, after `saved`. `MemoryOps` does not change. The ruled Lane A scope is `MemoryTools` only, and a repeat (the first row's Ref) is covered for free. A failed read logs a warning and adds nothing: a save that cannot be shown to be learned is not announced.
- **A forgotten memory leaves `learned`**, as it leaves `memories`, so a turn never announces a fact that it deleted.
- **Usable replies only.** `learned` is read only from a usable reply, which is Conversation's existing rule for citations and memories. A fallback turn has no model reply to sit under and shows no line. The memory still shows as Learned in the Memory card.
- **Placement.**
  - The page: reply, check rows, learned lines, source chips.
  - Telegram: reply, blank line, check sentence (when there is one), blank line, then the lines one per line.
- **The phone.** The simulated phone never shows a turn reply. Notify's Outbound rule targets `WebChatOut` and `TelegramOut` only, `SimPhone/Out.cls` maps `Notification` only, and no Turn has channel `phone`. So the line follows the reply on every channel that shows one, which is the web chat and Telegram. Nothing is added for the phone.
- **The eval rule.** `memory-learned-save` stays right by its phrase rule, and is now also right by "entry and line". `case.json` and its pins in `Test/Eval/Cases.cls` are unchanged.
  - On the mock the reply says "I'll remember that", so the line is suppressed and the phrase rule scores it.
  - ~~Edge (inference; report-only): a real reply that says "I'll remember Lee …" without "that" suppresses the line and misses the phrase rule, so it scores wrong.~~ RULED (spec-gate ruling 4): such a reply passes `Memory.Learned.Said` and scores right.
- **The catalog entry goes in `Core.cls`.** That is Lane B's class, and the catalog is in Lane B's ruled scope. The entry is inserted between existing entries, so the edit is plain added lines. It has no `web` variant, so the "ten web wordings" pin stays.
- **e2e placement.** The real-turn test joins S7's describe, reusing its `wipe`, `send` and keys. The seeded tests join `sources.spec.ts` (the 20.2 sibling). The second-session test joins `api/memory.spec.ts` (the LIVE/PANEL idiom). One new mock scenario, A/`memory-learned-line.json`, is added because no existing scenario saves a learned fact with a silent reply.

**Spec-gate items (for the lead; veto window or footprint, ruled before implement as at 41.14):** RULED 2026-11-11 by the Contest Planner (see the Spec Change Log): item 1 ACCEPTED (both properties); scope web chat and Telegram only CONFIRMED; the 199 + "…" cut ACCEPTED; the eval also counts a reply that passes `Memory.Learned.Said`.
1. **Stored data beyond the ruled `Turn.Learned` (veto window item 3).** Both are needed for ruled ACs. Both are nullable JSON strings, appended to storage, and need no migration.
   - `Msg.Outbound.Learned`: `TelegramOut` renders from the Outbound, and the trace shows the Turn's `Learned` through the Outbound body. This is Story 20.2's precedent for `Citations`/`Memories`.
   - `Eval.Msg.TurnResult.Learned`: the eval ruling scores on the learned entry, and the eval path never reads the Turn (`In.cls:176`). This is the 19.4 and 41.14 precedent for `Citations`/`Memories`.
2. **Contended paths, additive edits only:**
   - `Msg/Catalog/Core.cls`: one inserted entry.
   - `web/src/app/msg/catalog.ts`: regenerated, two inserted lines.
   - `Live/Payload/ChatMessage.cls`: one property and the `FromRow` lines inserted.
   - `Live/Payload/Part/Learned.cls`: a new file.

   `Agent/Chat.cls`, `Web/Api.cls` and `Data/Ownership.cls` do not change.

   Count lines edited in place in test files that are not on the contended list:
   - `Test/Msg/Catalog.cls`: 135 → 136.
   - `Test/Live/Payloads.cls`: 34 → 35.
   - `catalog.test.mjs`: 54 → 55, plus the lists.
   - `payloads.test.mjs`: the tail regex.

   The second epic to merge sums the counts. This is the plain-union pattern of the orchestrator's 41.13 ruling.
3. **Footprint extensions (Rule 11; none contended beyond item 2):**
   - `Data/Turn.cls`
   - `Msg/Outbound.cls`
   - `Channel/Telegram/Out.cls` (Lane A; Epic 17's footprint, merged)
   - `Eval/{In,Report}.cls`
   - `Eval/Msg/TurnResult.cls`
   - `Test/{Core/ConversationTurns,Core/ConversationProbe,Live/Payloads,Msg/Contracts,Data/Tables,Web/Api,Channel/TelegramOut,Msg/Catalog,Eval/MemoryCases,Tools/CommandsDouble}.cls`
   - `web/src/app/chat/**`
   - `web/src/app/live/payloads.ts`
   - `web/scripts/{catalog.mjs,*.test.mjs}`
   - `web/e2e/{chat/sources.spec.ts,api/memory.spec.ts,support/iris.ts}`
   - `ci/mock/scenarios/A/memory-learned-line.json`

**Extend, don't copy:**
- `MemoryTools`' learned merge follows `Remember`/`Merge`. `Unremember` is extended with the member name.
- `Conversation.Kept` gains a cap argument.
- `Part.Learned` follows `Part.Memory`.
- The doubling match reuses `ReplyGuard.PatternOf`.
- `Learned.Lines` reuses `Catalog.Render`.
- The page reuses `renderPageText` and the `.sentence` styling.
- `TelegramOut` follows its `CheckSentence` join.
- The eval follows `Cite`'s memories copy.
- The tests follow `TestSourcesCarried`/`Shape`/`NotOnFallbacks`, `TestStateChatDecision`, `TestCheckSentence`, `TestHostDataMerge`, S7, and `memory.spec.ts`'s second session.
- A stated copy: `Memory.Learned` is a new class, not an addition to `MemorySource`. `MemorySource` decides the source; this class shapes and gates the announcement, and four callers in three areas share it.

**Integration ACs:** AC 7.
- `Conversation` reads `MemoryTools`' HostData `learned` and produces the Turn's `Learned`.
- The page, through `chat.message` and `/v1/state`, and `TelegramOut`, through the Outbound, produce the line.
- `Eval.Report` reads `TurnResult.Learned`.

**Consumes:**
- 41.8's `Source`.
- 20.2's citations and memories path.
- Epic 5's catalog, check-row rendering and `ReplyGuard`.
- 41.14's session case for `memory-learned-save`.

**Consumed-by:** no later story in Epic 41 (this is its last). The 1.0.7+ RC eval (REL-5) reads the report-only line.

**Ledger inbox:** none.

## Verification

Run every command from the worktree root, one per call, with `timeout: 600000`, each sized to about 150 s.

Prefix every `ci/` call with:
```
OCUTALON_LOCK_DIR=<lock-dir>/lane-a OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=41 stage=<stage>'
```
The fresh tag is `e41s15i` and the warm tag is `e41s15iw`.

Rules for the runs:
- Never run two tests in one message.
- Every IRIS MCP call names `server` `ocutalon-slot-a` and `namespace` `OCUTALON`, after one `iris_server_info` identity check.
- Use no real key and no Telegram bot.
- Write `ci/mock/scenarios/A/memory-learned-line.json` before `warm.sh up`.
- After recompiling a class that a production job runs, restart the warm stack's production before an in-production class. Those classes are `MemoryTools`, `Conversation`, `Telegram.Out`, `Eval.In`, `Memory.Learned` and `ChatMessage`.

**Shared surfaces:**
- The catalog key count and lists:
  - `Test.Msg.Catalog` `TestEntries`/`Keys`/`Fixtures`;
  - `catalog.test.mjs` `PAGE_TEXTS`/`PAGE_SLOTS`/`TEXT_SLOT_KEYS`;
  - `ux-strings.test.mjs` `SOURCES`.
- Turn's property list (`Test.Data.Tables`).
- Outbound's (`Test.Msg.Contracts`, `ConversationProbe`).
- `TurnResult`, `Turn` and `Outbound` storage (`test-storage.sh`).
- The ChatMessage payload shape:
  - `Test.Live.Payloads` contracts and the count of 34;
  - `payloads.test.mjs`, `payloads.ts`, `chat-view.test.mjs`;
  - `Test.Web.Api`'s state items.
- The HostData members (`Test.Tools.Memory`).
- Telegram's sent text (`Test.Channel.TelegramOut`).
- The eval `learnedSave` tally (`Test.Eval.Report`).
- The mock scenario set (`ci/mock/test/scenarios.test.mjs`).

Every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once) `OCUTALON_RUN_TAG=e41s15iw ci/warm.sh up`. Expected: ready.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e41s15iw ci/iris.sh class <Class>`, one class per call. Expected: passed.
  - `OcuTalon.Test.Memory.Learned`
  - `OcuTalon.Test.Tools.Memory`
  - `OcuTalon.Test.Core.ConversationTurns`
  - `OcuTalon.Test.Live.Payloads`
  - `OcuTalon.Test.Msg.Contracts`
  - `OcuTalon.Test.Data.Tables`
  - `OcuTalon.Test.Web.Api`
  - `OcuTalon.Test.Channel.TelegramOut`
  - `OcuTalon.Test.Msg.Catalog`
  - `OcuTalon.Test.Eval.Report`
  - `OcuTalon.Test.Eval.MemoryCases` (after the production restart)
- (loop) `cd web && node --test scripts/<file>.test.mjs`, one file each. Expected: pass.
  - `chat-view`
  - `catalog`
  - `payloads`
  - `ux-strings`
- (once) `cd web && node scripts/catalog.mjs --check && node scripts/payloads.mjs --check`, then `npm run lint`, then `npx playwright test --list e2e/chat/sources.spec.ts e2e/api/memory.spec.ts`. Expected: exit 0, and S10-S12 and the new memory test listed.
- (once) `cd web && npx ng build`. Expected: success.
- (once) `bash docker/tests/test-mock.sh`, then `bash docker/tests/test-storage.sh`, then `bash docker/tests/test-class-rules.sh`, then `bash docker/tests/test-boundaries.sh`. Expected: pass.
- (once) `git diff 0eb14ea2 -- src/ocutalon/cls/OcuTalon/Agent/Chat.cls web/src/app/msg/catalog.ts`. Expected: Chat empty, and only `+` lines in `catalog.ts`.
- (once) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16`. Expected: the baseline (`"ok": false`, the 10 low `placeholder` findings, nothing new).
- (once) `OCUTALON_RUN_TAG=e41s15iw ci/warm.sh down`, then `OCUTALON_RUN_TAG=e41s15i ci/iris.sh teardown`.
- **Left to CI** (each over 150 s locally):
  - `live:sign-in` (`sources.spec.ts` S10-S12, `api/memory.spec.ts`);
  - the shards;
  - `bash ci/checks.sh`;
  - the lead's fresh-environment check.

**Mutations (Rule 19), one per AC.** Apply each on the warm stack (or the web unit), observe red, revert, and confirm the tree is byte-identical (`git status --short`, `git diff --stat`). Record each as `mutation: … → … red`.
- AC 1: `SaveMemory` skips the `Source` check (any `saved` is recorded) → `Tools.Memory:TestLearnedNothing` red.
- AC 2: `Sourced` skips `learned` → `ConversationTurns:TestLearnedCarried` red.
- AC 3: `Fact` cuts to 200 plus "…" → `Memory.Learned:TestFact` red. `OnOutbound` skips the lines → `TelegramOut:TestLearnedLines` red.
- AC 4: the stand-in is `learned-lines.ts` binding `[innerHTML]` → e2e S10 red (CI). Locally, `TelegramOut` sets `parse_mode` HTML → `TestLearnedLines` red.
- AC 5: `Said` returns 0 → `Memory.Learned:TestSaid` and `ConversationTurns:TestLearnedSaid` red.
- AC 6: drop the `SessionRef` term from `Ownership.RecentTurns`' query. This is a temporary edit to a contended file and is reverted at once. Then `Web.Api:TestStateLearned` is red: `theirs` sees `mine`'s `learned`. The real-HTTP test (`api/memory.spec.ts`) runs in CI.
- AC 7: `Cite` skips `learned` → `MemoryCases:TestLearnedEntry` red. S12 runs in CI.
- AC 8: a bullet changed in `Chat.cls` → `Tools.Memory:TestInstructions` red.
- AC 9: the "entry and line" rule removed → `Report:TestLearnedSaveByTheLine` red; the `Said` call removed → `Report:TestLearnedSaveBySaid` red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
