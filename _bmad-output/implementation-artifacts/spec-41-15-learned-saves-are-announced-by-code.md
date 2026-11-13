---
title: "Story 41.15: Learned saves are announced by code"
type: 'feature'
created: '2026-11-10'
status: 'done'
baseline_revision: '2da790c8b7376e7385eab8aadc5a6f03d9b2ee56'
baseline_commit: '2da790c8b7376e7385eab8aadc5a6f03d9b2ee56'
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

### Review Findings

Code review 2026-11-11 (first review; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, full-opus tier). 36 raw rows → 6 entries (high 0, med 3, low 3); 2 patched, 4 ledgered terminal, 30 rows rejected.

- [x] [Review][Patch] `MemoryTools.MergeLearned` and `Announce`'s merge block were near-copies of `Merge`/`Remember` (Rule 2, med, fix-risk low: private, both paths pinned by `Tools.Memory`) [src/ocutalon/cls/OcuTalon/Tools/MemoryTools.cls:166] — fixed: `Remember` takes an optional member, cap and field list, `Merge` takes the cap and fields, `MergeLearned` is gone and `Announce` calls `Remember(..., "learned", Learned.#MAXENTRIES, $ListBuild("memoryRef","text"))`. `Tools.Memory`, `Eval.MemoryCases` passed warm after a production restart.
- [x] [Review][Patch] `Memory.Learned.Fact` could cut a UTF-16 surrogate pair in half at position 199, leaving a lone high surrogate before the ellipsis (invalid UTF-8 for Telegram's sendMessage, which would lose the whole reply) (med, fix-risk low; same guard as `Telegram.Api.Split`) [src/ocutalon/cls/OcuTalon/Memory/Learned.cls:32] — fixed: the cut steps back one unit off a high surrogate; `Test.Memory.Learned:TestFact` gained two assertions (a split pair left out whole, a pair ending at the cut kept). `Memory.Learned`, `Live.Payloads` passed warm; `test-class-rules.sh` passed.
- [x] [Review][Defer] One "I'll remember" anywhere in the reply suppresses every learned line of the turn [src/ocutalon/cls/OcuTalon/Memory/Learned.cls:55] — deferred: DW-1104 `by-design` (AC 5 and the ruling fix a per-turn check).
- [x] [Review][Defer] The eval waiver covers the whole missing key-phrase list and does not tie `Learned` to the saved step [src/ocutalon/cls/OcuTalon/Eval/Report.cls:1142] — deferred: DW-1105 `wontfix-theoretical` (real when a learned case gains a second keyPhrases group).
- [x] [Review][Defer] `Test/Eval/Report.cls` has 3 in-place lines where the spec says added lines only [src/ocutalon/cls/OcuTalon/Test/Eval/Report.cls] — deferred: DW-1106 `wontfix-accepted`, reopen_if a merge conflict there.
- [x] [Review][Defer] The eval report lists the "I'll remember that" phrase as missing on a learned turn scored right [src/ocutalon/cls/OcuTalon/Eval/Report.cls:1142] — deferred: DW-1107 `by-design` (ruling 4 keeps the phrase rule's output).

Rejected:
- false: the spec's triage log, Auto Run Result residual risks, file list and Shared surfaces count are stale (blind, edge, verification-gap) — the fix edits the spec under review; the Spec Change Log already records the lost triage rows.
- false: `Test/Tools/MemoryAnnouncer.cls` ships an `%AI.Tool` subclass with a public method taking a session (blind, auditor) — it follows the `Test/Tools/RecentActivityUnread.cls` test-double precedent; no toolset names it, so no model can call it, and any caller able to run it can already call `Ownership.Memory` directly.
- false: the new line is not in EXPERIENCE.md and splits the `pairing.*` block (blind) — the ruled line lives in `epics.md` (the `ux-strings.test.mjs` `ac` source exists for that), and Task 8 forces a mid-list insertion.
- low: a fact of only zero-width characters renders an empty-quote line (edge) — not reachable in practice (the model saves the user's words; `OnSave` strips white space and control characters); a guard adds a branch.
- low: `TelegramOut` ignores `Lines`' status (edge) — `Shown` filters every entry `Render` would refuse, so a render error is not reachable; a branch for it adds complexity.
- low: the PANEL check in `api/memory.spec.ts` fails if PANEL ever had a learned turn (edge) — no test gives PANEL a learned turn, and the seeded LIVE turn is removed in `finally`.
- false: `Memory.Learned`'s doc overstates that every renderer shows exactly what `Shown`/`Lines` give (edge) — the page shows `Shown`'s entries through the payload and the same generated catalog text.
- false: AC pins without their own `mutation:` line (AC 1 forget, AC 2 fallbacks, AC 3 Payloads/S10/S12, AC 5 S11, AC 6 e2e, AC 7 S12, AC 9 report-only; 9 rows, verification-gap) — Rule 19 asks one demonstrated mutation per AC, and every AC has one.
- false: AC 4's web mutation was observed only on a source-text guard, and `learned-lines.ts` has no local test host (verification-gap) — the spec names e2e S10 as the web pin (CI `live:sign-in`), and AC 4's Telegram mutation is demonstrated on `TelegramOut:TestLearnedLines`; Rule 3 is met by S10-S12 and `api/memory.spec.ts`.
- false: the AC 6 e2e negatives could be vacuous when the 2025 seeded turn ranks out of the newest 100 (verification-gap) — under the `SessionRef` mutation LIVE's own `toBeDefined` check then goes red, so the test fails either way.
- false: `TestShown`'s label "a reply of no text says nothing" contradicts its assertion (verification-gap) — "says nothing" means `Said` is 0, so the entry shows, which is what it asserts.
- low: `TestLearnedReadFailed` sees the warning under the helper's class name; `TestStateLearned` cleans outside try/finally; `TestLearnedEntry` needs the production restart (verification-gap, 3 rows) — the test pins the warning's text and count; the class convention; the order is in `## Verification`.
- false: the eval change is more than one call (auditor) — the entry-and-line rule is Task 12's own; ruling 4's addition is the one `Said` call.
- false: QA files are uncommitted; the integrate-forward is pending (auditor, 2 rows) — the lead commits after the smoke gate; the Spec Change Log already carries the integrate-forward.
- [x] [CI] iris (shards-2) shard:lane-a@rest and iris (shards-4) live:memory-offline, run 42943118887 (https://github.com/jbrandtmse/OcuTalon/actions/runs/42943118887): `OcuTalon.Test.Memory.Turns:TestSaveRecallListThroughTheAgent` fails "the reply is not tainted and carries no HostData" (`Test/Memory/Turns.cls:253`). Cause: this test sends the turn straight to the Chat agent job, so no `Data.Turn` exists and `Memory.Ops.Source` reads the save as `learned` (41.8's rule, unchanged), and this story then correctly records it in HostData `learned`. Fix (lead decision, decide-level; the reply guard, taint and 41.8's source rule do not change): update the pin, not the data. Assert `answer.Tainted` = 0 and that `answer.HostData` is exactly `{"learned":[{"memoryRef":<the saved Ref>,"text":<the saved text>}]}` (no `memories` member), with a one-line comment saying why the save is learned on this path; update the class doc line for this method (`Turns.cls:7`) to say so. Keep every other assertion. Add `Test.Memory.Turns` (the HostData pins of its save and list turns) to the spec's `Shared surfaces:` line under `## Verification`, and a `mutation:` line for the new pin (e.g. `Announce` skips the `Remember` call -> `Memory.Turns:TestSaveRecallListThroughTheAgent` red). Run `OcuTalon.Test.Memory.Turns` (it needs the CI mock reachable: run it on the lane-A warm stack after `ci/mock/scenarios/A/memory-learned-line.json` is in place) and every other `OcuTalon.Test.Memory.*` class, one per call.

Re-review (CI rework iteration 1, code-review stage, 2026-11-11, scope `2da790c8..HEAD`; checklist: the `[CI]` item is fixed, the new pin is exact and its `mutation:` line names a real mutation; in the product path `Conversation.Take` saves the `Data.Turn` before `Begin`/`Ask` send its ItemId, `Ownership.TurnOfItem` has no state filter and `Ops.TurnOf` also finds a retry ItemId on a queued or running turn, so "Remember that ..." stays `told` and `Announce` quits on a non-learned row (e2e S7 pins "a told save is not announced"); no other test pins an empty HostData after a successful save with no `Data.Turn`):
- [x] [Review][Patch] `## Verification`'s class loop did not run `OcuTalon.Test.Memory.Turns`, the surface that went red in CI run 42943118887 (low, fix-risk low: one list line) [_bmad-output/implementation-artifacts/spec-41-15-learned-saves-are-announced-by-code.md:632] — fix

Rejected (re-review):
- low: the rework triage rows say `TestToldAndLearnedThroughTheAgent` pins the told path (blind, auditor) — it pins the told and learned `Source` only and makes no HostData assertion; the no-announcement pins are `Tools.Memory:TestLearnedNothing` and e2e S7 (`web/e2e/chat/sources.spec.ts`), and the rejections stand on those.
- low: "`Memory.Turns` ran to its pin" does not say the whole class passed (blind, verification-gap) — the class's other methods were green in CI run 42943118887 on the same production code; the rework changed one assertion.
- low: AC 1's "Pinned by" omits `Memory.Turns` (verification-gap) — the fix edits the AC text; `## Verification` carries the pin's `mutation:` line and its Shared surfaces entry.
- low: the Auto Run Result does not record the `e41s15rw` teardown (blind) — the cycle log's `dev_complete` records it; no lane-a lock remains.
- false: the frontmatter baselines were moved to `2da790c8` (blind) — the lead's rework protocol sets the rework baseline; `c79da26f` stays in the Auto Run Result and the cycle log.
- false: the implement pass's self-review reads as this review, and `status: 'done'` precedes it (blind, verification-gap, auditor) — `bmad-build-auto` writes its own review pass and frontmatter status (cycle log `self_review=7_low_rejected`); this stage's verdict is this block and the sprint-status sync.

## Spec Change Log

- 2026-11-11 (spec gate; Contest Planner rulings ~00:15Z under the owner's delegation, relayed by the orchestrator; verbatim terms, from the orchestrator's `prompts/epic-41-rulings-4115.md`, section "Spec-gate rulings"; implement may start):
  > 1. STORED DATA: both ACCEPTED. (a) Msg.Outbound.Learned and (b) Eval.Msg.TurnResult.Learned: nullable JSON appended to storage, no migration, no grant, role or Data.Memory column (20.2 and 41.14 precedents).
  > 2. SCOPE: CONFIRMED, web chat and Telegram only (the channels that show a reply). Nothing is added for the phone. ("Telegram/phone" was the Planner's error.)
  > 3. CUT: ACCEPTED, 199 characters + "…" (200 in all), after removing one trailing ASCII full stop, matching Conversation.Cut.
  > 4. EVAL: fold in now. memory-learned-save scores right when the turn's Learned line would be shown, OR when the reply passes the same no-doubling check (the one server method), so "I'll remember Lee…" counts as announced and the eval and the user see the same thing. A one-call reuse in Epic 41's own eval files; if it's more than that, report it. The case stays report-only.
  Lead note (2026-11-11, decide): feature moved to 9f7db82c (Story 23.2 merged; it changed `Agent/Chat.cls`, `Msg/Catalog/Core.cls`, `Live/Payload/**`). This story is implemented on the current base and the lead integrates 9f7db82c (once green) before the push. AC 8's intent is "this story changes nothing in `Agent/Chat.cls` or any tool description": before the integrate-forward, `git diff 0eb14ea2 -- src/ocutalon/cls/OcuTalon/Agent/Chat.cls` is empty; after it, the check is `git diff <the merged feature head> HEAD -- src/ocutalon/cls/OcuTalon/Agent/Chat.cls` empty. Count lines and catalog entries that 23.2 also changed are summed at the integrate-forward (plain union).
  Applied: items 1-3 match the plan as written (Design Notes spec-gate items 1 and 3, "The phone", the 200-character cut). Item 4 amends the Eval bullet in Boundaries, Task 12's `Eval/Report.cls` rule, the `Test/Eval/Report.cls` task (`TestLearnedSaveBySaid`), AC 9, Design Notes "The eval rule", and the AC 9 mutation, each marked [AMENDED 2026-11-11, Contest Planner spec-gate ruling 4, owner's delegation].
- 2026-11-11 (lead, after the implement pass; decide): the implement pass's finalize write of `## Review Triage Log` replaced the rest of the spec: `## Design Notes`, `## Verification` (with its Mutations list) and the `## Auto Run Result` heading were lost, and the triage log kept 6 of its 25 rows. The lead restored `## Design Notes` and `## Verification` byte for byte from the pre-implement spec (c79da26f, which carries the spec-gate rulings), re-added the `## Auto Run Result` heading and its `Blocking condition: none` line, and kept the pass's own result text. The implement pass reported all nine AC mutations observed red and reverted (AC 8 held by the empty Chat.cls diff and `TestInstructions`); QA re-demonstrates one mutation per AC and records each `mutation:` line under `## Verification`.
- 2026-11-11 (lead, CI rework iteration 1; trigger=ci): run 42943118887 red. Story reds: `Test.Memory.Turns:TestSaveRecallListThroughTheAgent` in shards-2 (lane-a@rest) and shards-4 (live:memory-offline), one root cause, see the `[CI]` item. Not this story's: DW-675 flake (shards-11, occurrence appended), DW-1099 infra (shards, occurrence appended). The planned `Shared surfaces:` line missed `Test.Memory.Turns`.

## Review Triage Log

### 2026-11-10 - Review pass
- verdicts: 25 findings - high 0, medium 1, low 19, false 5, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: whitespace around the fact is not trimmed before shaping - `Memory.Ops.OnSave` stores `$ZStrip(text,"<>WC")`, so a stored text never ends in white space and is never white-space only; `Shown` already drops an entry whose fact is empty once shaped.
  - `[low]` `[reject]` Blind: a catalog failure drops the Telegram line with no warning - `Shown` filters every entry the catalog would refuse (non-empty slot), so a render failure is not reachable; a guard would add a branch for it.
  - `[low]` `[reject]` Blind: the cap of 3 is defined in `Conversation` and in `Memory.Learned` - Task 5 names `Conversation.MAXLEARNED`; the spec fixes it.
  - `[low]` `[reject]` Blind: an announcement outlives a later forget in another turn - the spec scopes removal to a forget in the same turn; the memory chips behave the same.
  - `[low]` `[reject]` Blind: the web and live-HTTP pieces were not run - the spec leaves S10-S12 and `api/memory.spec.ts` to CI `live:sign-in`; `--list` was run.
  - `[false]` `[reject]` Blind: the spec's status is inconsistent - the frontmatter and `## Auto Run Result` (line truncated by the implement pass's spec write; the remaining triage rows of the 25 were lost with it, see the Spec Change Log)

### 2026-11-11 - Review pass (CI rework iteration 1, follow-up pass)
- verdicts: 7 findings - high 0, medium 0, low 7, false 0, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: the new pin does not assert the saved row's `Source` - `TestToldAndLearnedThroughTheAgent` already pins that a save with no `Data.Turn` reads as learned, and the pin's own comment names the cause; an extra column and assertion would add no new failure case.
  - `[low]` `[reject]` Blind: whole-string compare couples the pin to key and member order - the lead's decision fixes the pin as "exactly" `{"learned":[{"memoryRef","text"}]}`, and `Announce` fixes that order; spec-bound.
  - `[low]` `[reject]` Blind: `TestToldAndLearnedThroughTheAgent` asserts no HostData for the told and learned-with-turn paths - outside the `[CI]` item; `Tools.Memory:TestLearnedNothing` and `Tools.Memory:TestLearnedHostData` pin those at the tool.
  - `[low]` `[reject]` Blind: no end-to-end test of forget removal, the cap of 3 or `Turn.Learned` and `Outbound.Learned` - already pinned by `Tools.Memory` and `ConversationTurns` (`TestLearnedCarried`); the item scopes this pass to the one pin.
  - `[low]` `[reject]` Blind: the class-doc bullet is awkwardly wrapped and the comment says `Memory.Ops.Source` - cosmetic; the short class name is the one the class doc uses throughout.
  - `[low]` `[reject]` Blind: nothing checks the `learned` entry does not leak into the later recall and list turns - HostData is built per turn, and the list turn still pins no HostData at all.
  - `[low]` `[reject]` Intent: the pin asserts an announcement on a path with no `Data.Turn`, where the real path would read the same words as told - the lead's recorded decision (update the pin, not the data; 41.8's source rule unchanged); `TestToldAndLearnedThroughTheAgent` pins the told path.
- Edge Case Hunter and Verification Gap reported nothing.

### 2026-11-11 - Code-review stage (CI rework iteration 1, re-review of `2da790c8..HEAD`)
- verdicts: 8 findings - high 0, medium 0, low 5, false 3, maybe-false 0
- findings:
  - `[low]` `[patch]` Verification Gap: the `## Verification` class loop does not run `OcuTalon.Test.Memory.Turns` - added (after the production restart).
  - `[low]` `[reject]` Blind+Auditor: the rework triage rows say `TestToldAndLearnedThroughTheAgent` pins the told path - it asserts `Source` only; `Tools.Memory:TestLearnedNothing` and e2e S7 pin no announcement.
  - `[low]` `[reject]` Blind+Verification Gap: "ran to its pin" is ambiguous - the other methods were green in CI run 42943118887 on the same production code.
  - `[low]` `[reject]` Verification Gap: AC 1's "Pinned by" omits `Memory.Turns` - an AC-text edit; `## Verification` carries the mutation line.
  - `[low]` `[reject]` Blind: the Auto Run Result omits the `e41s15rw` teardown - the cycle log records it; no lane-a lock remains.
  - `[false]` `[reject]` Blind: the baselines moved to `2da790c8` - the rework protocol's baseline.
  - `[false]` `[reject]` Blind+Verification Gap: the implement pass's self-review reads as this review - `bmad-build-auto`'s own pass (cycle log `self_review=7_low_rejected`).
  - `[false]` `[reject]` Auditor: frontmatter `done` vs sprint-status `review` - the frontmatter is `bmad-build-auto`'s; sprint-status is synced by this stage.
- Edge Case Hunter reported nothing. Rule 3: S7 and S12 (`web/e2e/chat/sources.spec.ts`) remain the real-runtime pins; this rework touched one test assertion only.

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
- The HostData of the memory turns through the agent (`Test.Memory.Turns`): the save turn pins HostData exactly `{"learned":[{memoryRef,text}]}`, the list turn pins no HostData.

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
  - `OcuTalon.Test.Memory.Turns` (after the production restart; through the Chat agent job)
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

**Mutations demonstrated by the QA pass (Rule 19), on the warm stack `e41s15qw`.** Each was applied, observed red, reverted from a backup, and the tree was byte-identical afterwards (a hash of `git status --short`, `git diff` and the untracked files was the same before and after each).
- mutation: AC 1, `MemoryTools.Announce` skips the `Source = learned` check (any `saved` is recorded) → `Tools.Memory:TestLearnedNothing` red (told, old and another session's row each added an entry).
- mutation: AC 1 (QA gap 1, the failed row read), `Announce` logs the failed read as Info instead of a warning → `Tools.Memory:TestLearnedReadFailed` red.
- mutation: AC 2, `Conversation.Sourced` never sets `turn.Learned` → `ConversationTurns:TestLearnedCarried`, `TestLearnedShape` and `TestLearnedSaid` red.
- mutation: AC 3, `Learned.Fact` cuts to 200 characters plus "…" (201 in all) → `Memory.Learned:TestFact` and `TestLines` red.
- mutation: AC 3, `Telegram.Out.OnOutbound` never appends the lines → `TelegramOut:TestLearnedLines` red.
- mutation: AC 4 (Telegram), `SendPart` sets `parse_mode` HTML → `TelegramOut:TestLearnedLines` (and `TestPlainText`, `TestSummary`) red.
- mutation: AC 4 (web, local stand-in), `learned-lines.ts` binds `[innerHTML]="line"` → `chat-view.test.mjs` "the learned lines are plain text" red (QA test; e2e S10 is the CI pin).
- mutation: AC 5, `Learned.Said` returns 0 → `Memory.Learned:TestSaid` and `ConversationTurns:TestLearnedSaid` red.
- mutation: AC 6, `Ownership.RecentTurns`' query loses its `SessionRef` term (`(SessionRef = ? OR 1 = 1)`) → `Web.Api:TestStateLearned` red (and `TestStateSections`). The edit to the contended file was reverted at once.
- mutation: AC 7, `Eval.In.Cite` skips `learned` → `Eval.MemoryCases:TestLearnedEntry` red (production restarted before the run, and again after the revert).
- mutation: AC 8, one character of the learned-save bullet in `Agent/Chat.cls` ("yoo") → `Tools.Memory:TestInstructions` red; reverted at once, and `git diff c79da26f -- Agent/Chat.cls` is empty.
- mutation: AC 9, `Report.Announced` loses its entry-and-line rule → `Eval.Report:TestLearnedSaveByTheLine` red; the `Said` call removed → `Eval.Report:TestLearnedSaveBySaid` red.

**Mutations demonstrated by the code review (Rule 19), on the warm stack `e41s15cw`.** Each was applied from a backup, observed red, reverted, the class was green again on the same stack, and a hash of `git status --short`, `git diff` and the untracked file was the same before and after.
- mutation: AC 3 (review patch, the surrogate-safe cut), `Learned.Fact` loses its step back off a high surrogate → `Memory.Learned:TestFact` red ("a surrogate pair the cut would split is left out whole").
- mutation: AC 1 (the cap of 3 after the review's `Remember` extension), `Announce` passes cap 5 instead of `Learned.#MAXENTRIES` → `Tools.Memory:TestLearnedHostData` red ("four distinct Refs hold the first three, in the order saved").

**Mutation demonstrated by the CI rework (Rule 19), on the warm stack `e41s15rw`.** Applied from a backup, observed red, reverted, `Memory.Turns` green again, and a hash of `git status --short`, `git diff` and the untracked files was the same before and after.
- mutation: AC 1 (the save turn through the agent job, no `Data.Turn`, so the save reads as learned), `MemoryTools.Announce` quits before the `Remember` call (the saved learned memory is not recorded in HostData `learned`) → `Memory.Turns:TestSaveRecallListThroughTheAgent` red ("the reply is not tainted and its HostData is exactly the learned entry {memoryRef, text} of the saved memory"). The old pin (HostData empty) was observed red on the unchanged code first.

**QA pass files (QA).**
- `src/ocutalon/cls/OcuTalon/Test/Tools/Memory.cls` (QA): new `TestLearnedReadFailed` (the failed-row-read warning, I/O matrix "Failed save") and its class-doc bullet.
- `src/ocutalon/cls/OcuTalon/Test/Tools/MemoryAnnouncer.cls` (QA, new): a helper subclass of `MemoryTools` that reaches the private `Announce` (no context accepts the Ref that makes the read fail); it is not a test class.
- `web/scripts/chat-view.test.mjs` (QA): a source guard that `learned-lines.ts` interpolates and never binds HTML, and carries no label.

**QA re-run (warm `e41s15qw`, after the review patches).** All 11 Verification classes passed, the four web unit files passed (chat-view 71 with the QA tests, catalog 66, payloads 20, ux-strings 13), `playwright --list` shows S10, S11, S12 and the new memory test, `test-class-rules.sh` and `test-boundaries.sh` passed.


## Auto Run Result

Status: done
Blocking condition: none

Summary: code, not the model, announces a learned save. `MemoryTools` reads the saved row back and records `{memoryRef, text}` in HostData `learned` for a `learned` source (told, old, refused and failed saves add nothing; a forget in the same turn removes it). `Conversation` keeps a usable reply's entries as `Turn.Learned` and `Outbound.Learned`; `chat.message` and `/v1/state` carry the entries to show (`Part.Learned`, `{memoryRef, fact}`) through the one method `Memory.Learned.Shown`, which also applies the no-doubling check. The web chat (`app-learned-lines`) and Telegram show the ruled line `memory.learnedSaved` as plain text; the eval also scores `memory-learned-save` right by the entry-and-line rule or by the one-call `Learned.Said` reuse (report-only). The spine's AD-21 and AD-28 have the two accepted bullets. `Agent/Chat.cls`, `Web/Api.cls` and `Data/Ownership.cls` are unchanged.

Files changed: see the commit; new files are `Memory/Learned.cls`, `Live/Payload/Part/Learned.cls`, `Test/Memory/Learned.cls`, `web/src/app/chat/learned-lines.ts` and `ci/mock/scenarios/A/memory-learned-line.json`; stored data appended to `Data.Turn` (slot 26), `Msg.Outbound` (slot 12) and `Eval.Msg.TurnResult` (slot 13); `Msg/Catalog/Core.cls`, `Live/Payload/ChatMessage.cls`, `web/src/app/msg/catalog.ts` and `web/src/app/live/payloads.ts` have added lines only.

Review: 25 findings; 2 patched (`TestLearnedLines` count assertions before its guards, medium; `TestLearnedHostData` stored text versus the call's text, low); 0 deferred; 23 rejected with the reasons in the Review Triage Log.

Follow-up review recommended: false (no patched high; one patched medium).

Verification: on the warm stack (tag `e41s15iw`) every class in the Verification list passed after the implement pass, and `Tools.Memory` and `Channel.TelegramOut` passed again after the two review patches; the four web unit files, `catalog.mjs --check`, `payloads.mjs --check`, `npm run lint`, `ng build`, `test-mock.sh`, `test-storage.sh` passed in the implement pass; `test-class-rules.sh` and `test-boundaries.sh` and the spine lint (baseline: `"ok": false`, 10 findings) were re-run after the patches; `git diff 0eb14ea2 -- Agent/Chat.cls` is empty and `catalog.ts` shows only `+` lines. All nine AC mutations were observed red and reverted (AC 8 is held by the empty diff and `TestInstructions`). The warm stack and its lock are removed.

Residual risks: e2e S10-S12 and `api/memory.spec.ts` (real HTTP, second session) and the web `[innerHTML]` mutation run in CI `live:sign-in` only; the failed-row-read warning in `MemoryTools.Announce` has no unit test; the count lines (Catalog 135 to 136, Payloads 34 to 35, `catalog.test.mjs` 54 to 55) are summed with Story 23.2's at the integrate-forward.

CI rework iteration 1 (this pass only): `Test.Memory.Turns:TestSaveRecallListThroughTheAgent` now pins the save turn's reply as untainted with HostData exactly `{"learned":[{memoryRef,text}]}` (the turn goes straight to the agent job, so no `Data.Turn` holds its ItemId and the save reads as learned). Only `src/ocutalon/cls/OcuTalon/Test/Memory/Turns.cls` changed; no production class, data or other test. Review: 7 findings, all low, all rejected with reasons in the Review Triage Log; 0 patched, 0 deferred. Follow-up review recommended: false (no patched high). Verification on the warm stack `e41s15rw`: the old pin was red, the new pin is green, `Memory.Turns` ran to its pin; every other `OcuTalon.Test.Memory.*` class passed (`Diagnostics`, `Drop`, `Embedding`, `Install`, `Learned`, `Offline`, `Ops`, `Pins`, `Search`; `Volume` skips by design outside `live:memory-offline`); the mutation is in `## Verification`; `test-boundaries.sh` and `test-class-rules.sh` passed. Residual risk: CI shards-2 and shards-4 re-run is the remaining confirmation.
