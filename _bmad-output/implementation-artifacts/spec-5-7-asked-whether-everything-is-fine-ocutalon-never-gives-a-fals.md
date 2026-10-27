---
title: 'Asked whether everything is fine, OcuTalon never gives a false all-clear'
type: 'feature'
created: '2026-10-26'
status: 'done'
baseline_revision: '4f96b6e6acc985db9307b28cd7ee64df9e34880d'
baseline_commit: '4f96b6e6acc985db9307b28cd7ee64df9e34880d'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Since Story 5.6, each watch records its latest check result on its `BackgroundCheck` row. The chat still cannot answer "is everything fine?" from those results:
- the Chat agent has no `check_status` tool;
- `Checks.Render` is Epic 0's stub, so it returns no key and no rows;
- `Checks.ReplyGuard` passes every model text through, so a model-written "everything is fine" reaches the user;
- the page shows no sentence for `checks.notEverything` and `checks.notEverythingRestPassed`, because their `whatFailed` slot has no source (DW-90).

**Approach:**
- Add the safe, read-only, trusted-output tool `check_status` to the Chat agent's watch toolset. It copies the session's rows into `HostData.checks`, which `Conversation` already passes to `Render`.
- Implement `Render`: a pure function from results to a catalog key plus rows ordered failing first.
- Implement the guard: it deletes the reserved sentences and the closed list of banned phrases, and keeps the rest of the text.
- The page derives `whatFailed` from the rows (DW-90). The pinned `Render(results, *rows)` signature does not change.
- This spec is written to the recommended answers of rulings Q1 and V1 (Design Notes).

## Boundaries & Constraints

**Always:**
- **`check_status` is `OcuTalon.Tools.WatchTools.CheckStatus()`** (no arguments). It is listed in `Tools.Watching` as `check_status` (`Tools.Names.#CHECKSTATUS`). The parameters are `STEPLABELCHECKSTATUS` "Reading the check results", `CLASSIFICATIONCHECKSTATUS` "safe", `READONLYCHECKSTATUS` 1 and `TRUSTEDOUTPUTCHECKSTATUS` 1.
  1. `CommandCall.Session(.context)` runs first. With no session it answers `NOSESSION`, reads nothing and leaves `HostData` as it was.
  2. `WatchAnswers.CheckResults(sessionRef, .results)` is the one source of the results. 9.3 will add its `eval` branch here.
     - It reads `Data.Ownership.Checks(session)`.
     - A failed read answers `{"ok": false, "message": CHECKSNOTREAD}` and leaves `HostData` as it was.
     - Otherwise `results` holds one `{"result": Result, "entry": ENTRY with {name} = DisplayName, "finding": Finding, "checkedAt": LastRunAt}` per row of `Kind` `production`, in the order Ownership gives (by ID). The values are copied from the row, and the tool never decides a result (AD-28).
  3. `WatchAnswers.PutChecks(results)` sets `checks` on `HostData`.
     - When `HostData` already holds a JSON object, its other members are kept, and `checks` replaces any earlier value.
     - Otherwise `HostData` becomes `{"checks": results}`.
     - It writes through `Bridge.Context.Put`, also when `results` is `[]`.
  4. The answer for the model is `{"ok": true, "checks": [{"result", "entry", "finding", "checked"}]}`, where `checked` is `Data.Time.ForMessage(checkedAt)` ("" before the first run). The UTC time never reaches the model.
  5. It submits nothing and writes no row. Nothing from outside the instance is in its answer or its `HostData`, so it is trusted output (AD-10).
- **`Checks.Render(results, *rows)`** is a pure function. It reads no table and no context, writes nothing, and never throws for any JSON value.
  - `rows` is always a `%DynamicArray`. When `results` is not a `%DynamicArray`, the key is "" and `rows` is `[]`.
  - An empty array gives `KEYNOTHINGWATCHED` (`checks.nothingWatched`) with `[]`.
  - An element is a result only when it is an object whose `entry` is a string that is not blank. Other elements are skipped. A non-empty array with no result gives "" and `[]`, so `Test.Core.ConversationTurns.TestStubRenderAddsNothing` stays green.
  - Each result becomes the row `{"result", "entry", "finding", "checkedAt"}`, built in this order:
    1. `checkedAt` is the element's own when it is a UTC stamp (`YYYY-MM-DDThh:mm:ssZ`), otherwise "".
    2. `result` is `passed` or `failed` only when the element says exactly that and `checkedAt` is set. Anything else is `not_checked`.
    3. `finding` is the element's string, or "". A `not_checked` row with no finding and no `checkedAt` gets `REASONNOTRUN` "Not run yet" (V1).
    4. `entry` and `finding` are cut to 1000 characters, the `CheckRow` limit.
  - The rows are ordered `failed`, then `not_checked`, then `passed`, each group in input order.
  - The key:
    - `KEYALLPASSED` (`checks.allPassed`) when every row passed;
    - else `KEYRESTPASSED` (`checks.notEverythingRestPassed`) when at least one row passed;
    - else `KEYNOTEVERYTHING` (`checks.notEverything`).
- **`Checks.ReplyGuard.Filter(text)`** overrides `ReplyFilter.Filter`. Decide calls it once per model text (AD-31).
  - It holds two lists: `RESERVED` ("Everything I checked passed,Everything else I checked passed,Your IRIS system is healthy") and `BANNED` ("all good,everything's fine,everything is fine,no issues,no problems,nothing to worry about", the UX's closed list).
  - **How a phrase matches:**
    - case is ignored;
    - a space in the phrase matches any run of white space (a no-break space included);
    - an apostrophe matches `'` or U+2019, written as an escape (Rule 14);
    - the character before the phrase and the character after it must not be a letter or digit.
  - **How the text is filtered:**
    - The text is filtered line by line. Lines are split on LF, and a CR before an LF stays with the line break.
    - Each match is deleted together with the run of `.!?,;:` that directly follows it.
    - In a line that had a match, runs of spaces and tabs become one space and the line is trimmed. A line left empty is dropped with its line break.
    - Lines with no match, and a text with no match at all, come back unchanged byte for byte.
  - It never adds or rewrites words. If an exception occurs, it returns "" (fail closed), so Decide falls back instead of passing unfiltered text.
- **The page (DW-90)** takes `whatFailed` from the rows, never from `Render`.
  - `whatFailed` covers every row whose `result` is not `passed` — the `failed` rows first, then the `not_checked` rows, each group in row order, and never a `passed` row (the orchestrator's condition 3, read with the epics criterion "the failing or unchecked entry first"; veto U-111). Each one is `{entry} ({finding}, at {time})`:
    - the finding's first character is lowercased;
    - `{time}` is the page's `pageTime(checkedAt)`;
    - an empty part is left out (`{entry} ({finding})`, `{entry} (at {time})` or `{entry}` alone);
    - rows with an empty entry are skipped.
  - The parts are joined with "; ".
  - The sentence is `renderPageText(key, {whatFailed})`. It is "" when the key needs `whatFailed` and `whatFailed` is "".
  - `checkSentence` returns the catalog text for `checks.allPassed`, `checks.everythingElsePassed` and `checks.nothingWatched` exactly as the page does today, never derives an all-clear from the rows (N1: only the key, which `Render` chose in code, can say everything passed), and gives "" for any other key; `check-sentence.test.mjs` pins all four (orchestrator ruling Q1, conditions 1-5).
  - The logic lives in the new, framework-free `web/src/app/shared/check-sentence.ts`. It has no runtime imports: the catalog and the time function are passed in. `check-rows.ts` only wires it (Q1).
- **The Chat agent's instructions** gain one block after the dismiss block. The words of each reply stay the model's:
  - "If the user asks whether everything is fine, OK or working, or how the watched productions are doing, call check_status. OcuTalon shows the check results under your reply, with its own sentence that says whether everything passed. Then reply in one short sentence of your own that does not repeat the results, for example what the user can do next. Never say that everything is fine, that everything passed or that the system is healthy, and never write all good, no issues, no problems or nothing to worry about: only OcuTalon's own sentence may say that."
  - "If the answer of check_status is not ok, say in one short sentence that you could not read the checks."
- **Unchanged:** `Render`'s signature (`Test.Contract.Ac`), the catalog entries in `Msg/Catalog/Watch.cls`, `Conversation`, `Decide`, the `Production` setting `ReplyFilterClass`, `Turn`, `Outbound`, the `Live` payloads, and Chat's `TOOLSETS`.

**Never:**
- No server-side `whatFailed` and no new slot path. No change to a schema or payload, and no regeneration of `payloads.ts`. No `*Out` operation renders a check key in this story.
- `OcuTalon.Tools.*` never references `OcuTalon.Checks`, and the tool never interprets a result.
- No phrase outside the two lists. The guard never rephrases, capitalizes or adds text.
- No real-model call. The mock scenario is CI-only test input, never a canned product reply.
- No edits to a contended path except Q1's lines of `web/src/app/chat/check-rows.ts`.
  - `Test/Core/**`, `Test/Data/Fixture.cls`, `Data/Ownership.cls`, `Test/Core/{InProduction,Observe}.cls`, `docker/tests/**` and `web/src/app/live/payloads.ts` are called or read only.
  - Nothing else under `web/src/app/{chat,rail,live,…}` changes.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| All passed | `[passed A t1, passed B t2]` | `checks.allPassed`; rows A, B | none |
| One failing | `[passed A t1, failed B "3 new failures" t2, passed C t3]` | `checks.notEverythingRestPassed`; rows B, A, C | none |
| None passed | `[not_checked A "No answer in time" t1, failed B "Production stopped" t2]` | `checks.notEverything`; rows B, A | none |
| Nothing watched | `[]` | `checks.nothingWatched`; `[]` | none |
| Not run yet | `[{entry A, result "", finding "", checkedAt ""}]` | `checks.notEverything`; row `{not_checked, A, "Not run yet", ""}` | none |
| Not results | not an array; `[{"zz":"result"}]`; `[1, "x", {"entry": " "}]` | "" and `[]` | none |
| Odd values | `passed` with no or a bad `checkedAt`; result "zz"; an entry of 1,200 characters | `not_checked` (finding kept, else "Not run yet"); entry cut to 1000 | none |
| check_status | Session A: passed, failed and not-run rows, plus a row of another `Kind`; session B: a row | `{ok: true, checks: [A's three production rows, by ID]}` with `checked`; `HostData` `{"checks": [...]}` with UTC `checkedAt`; never B's or the other kind; nothing submitted | none |
| HostData kept | A watches nothing; `HostData` first `{"zz":1}`, then "not json", then a second call after a watch exists | `{ok: true, checks: []}`; `{"zz":1,"checks":[]}`; `{"checks":[]}`; the second call replaces `checks` | none |
| Refused | No context; owner `instance`, `eval` or ""; empty ItemId; `CheckResults("instance")` | `NOSESSION` with `HostData` untouched; `{ok: false, message: CHECKSNOTREAD}` | refusal |
| Guard removes | Each phrase of both lists, in upper and mixed case, with U+2019, with two spaces or a no-break space, and followed by `.`, `!` or `,` | "All good! The Orders production is running." gives "The Orders production is running."; "Everything’s fine, nothing to worry about. I looked at Orders." gives "I looked at Orders." | none |
| Guard keeps | "Overall good progress."; "no issuesX"; "Nothing failed."; a text with no match, with double spaces and CRLF | Unchanged, byte for byte | none |
| Guard lines | "Line one.\n\nAll good.\nLine three."; "Everything I checked passed." | "Line one.\n\nLine three."; "" (for a turn, Decide's existing fallback `invalid`) | none; an exception inside the guard gives "" (fail closed) |
| Through the chat (AC 1) | Orders failing for session S (3 failures tagged with its TraceRef, then a real Tick); S sends "Is everything OK? [[mock:checks-false-all-clear]]" | Reply "I looked at the Orders production for you."; `checks.notEverything`; one row `{failed, "Orders production", the row's Finding (begins "3 new failures"), the row's LastRunAt}` on the Turn and on the done `chat.message` | none |
| All-clear only from code (AC 2) | The same message, for a passing watch, then for no watch | The same filtered reply; `checks.allPassed` with one passed row; `checks.nothingWatched` with no row | none |
| Page (DW-90) | `checks.notEverything` with `[failed "Orders production" "3 new failures" 14:13Z]`; `notEverythingRestPassed` with a passed row and two non-passed rows; a `whatFailed` key with no non-passed row | "Not everything: Orders production (3 new failures, at {pageTime})."; both rows named, joined with "; ", then "Everything else I checked passed."; no sentence | none |
| Untrusted or tainted turn | The gate, for `check_status` | Runs (safe, read-only), and the taint is unchanged (trusted output) | allowed |

</intent-contract>

## Code Map

Every path is under `src/ocutalon/cls/OcuTalon/` unless noted.

- **Checks:**
  - `Checks/Render.cls` (14 lines; the `Render` stub at L8-12) is written here.
  - `Checks/ReplyGuard.cls` (6 lines, empty) is written here.
  - `Checks/Process.cls` holds 5.6's `FINDING*` and `REASON*` parameters, the texts that reach `Finding`. Read only.
- **Bridge (read only):**
  - `src/bridge/cls/OcuTalon/Bridge/Ext/ReplyFilter.cls` L9: `ClassMethod Filter(text) As %String`.
  - `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
    - `Conclude` L715-800: a turn's text is filtered once at L761, and a text left blank is `invalid` (L762, then `Classify` at L692);
    - `Interpret` L801-850: each reason (L817) and each `FILTERED` property (L823-840) is filtered, then the payload is validated again.
  - `src/bridge/cls/OcuTalon/Bridge/Context.cls`: `HostData` L46; `Begin` L59-75 empties it; `Current` L90; `Put` L102.
  - `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` L434 copies `HostData` onto the `Reply`.
- **Lane B (read only):**
  - `Core/Conversation.cls`:
    - `Replied` L430-443: a fallback never reaches `Checked` (L441-442);
    - `Checked` L449-463: it calls `Render` only for a JSON object with an array `checks`;
    - `RenderChecks` L466-469.
  - `Live/Payload/ChatMessage.cls`: `CheckKey` and `Checks` at L55-58, set at L86-88.
  - `Live/Payload/Part/CheckRow.cls` L5-15 sets the limits: entry and finding 1000, checkedAt 32.
  - `Msg/Catalog/Watch.cls` L49-77 holds the five `checks.*` entries, unchanged.
- **Data:**
  - `Data/BackgroundCheck.cls`: the run fields at L36-46, and `DisplayName` at L25.
  - `Data/Ownership.cls` `Checks` L213, by ID (contended; call only).
  - `Data/Time.cls` `ForMessage` L34, which gives "" for "".
- **Tools:**
  - `Tools/WatchTools.cls`:
    - the class doc L1-29 gets a fifth tool;
    - the parameters are at L36-66;
    - `DismissIncident` L119 is the pattern.
  - `Tools/WatchAnswers.cls`: the class doc L1-20; `KIND` L23; `ResolveStop` L45 reads `Ownership.Checks`, which is the pattern for `CheckResults`.
  - `Tools/Watching.cls` L10-16: the `<ToolSet>` and its `Description`.
  - `Tools/CommandCall.cls`: `Session` L66-74 and `NOSESSION` L23.
  - `Tools/Result.cls`: `Return`.
- **Agent:** `Agent/Chat.cls`: the class doc L1-6; the instructions L25-61, with the dismiss block at L53-58.
- **Web:**
  - **Contended (Q1):** `web/src/app/chat/check-rows.ts`:
    - L4 imports `PAGE_TEXTS`;
    - L6 imports `checkRowView, CHECK_KEY_PREFIX, DECISION_TEXTS`;
    - the doc at L10-14;
    - `sentence` at L113-116 returns `PAGE_TEXTS[key]` raw;
    - `rows` at L119-126.
  - **Read only:**
    - `web/src/app/chat/decision-view.ts`: `CHECK_KEY_PREFIX` L44 and `checkRowView` L194-203;
    - `web/src/app/chat/page-time.ts` `pageTime` L27-33 (browser zone; "" for "");
    - `web/src/app/chat/ocutalon-reply.ts` L82-83, which hosts `<app-check-rows>`;
    - `web/src/app/live/payloads.ts` L3-8, the `CheckRow` type (import the type only).
  - **`web/scripts/catalog.mjs`:**
    - the header L13-24;
    - `LISTED_KEYS` L37-54;
    - `SLOT_TYPES` L56-57;
    - `pageText`'s slot-type gate at L120-124, which refuses `text`;
    - `RENDERER` L150-183 (its doc at L171), where `renderPageText` cleans every non-reason slot with `cleanSlot`, so a `text` slot needs no renderer code;
    - the `PAGE_SLOTS` comment at L237.
    - Regenerate with `node web/scripts/catalog.mjs`, which writes `web/src/app/msg/catalog.ts`.
- **Tests:**
  - **`Test/Watch/Tools.cls`:**
    - `TestDeclarations` L53-121: the `want` entries at L57-60, the count at L63, L71, and the own methods at L114;
    - `TestNoSession` L265-301;
    - `CallTool` L704-710 (an unknown name falls through to `StopWatch`).
  - **`Test/Watch/Case.cls`:**
    - `Begin(owner, itemId)` L387, `Watch` L435, `Fail` L463, `WaitFailed` L496, `PointKeys` L371, `Stream` L1027, `AssertObject` L1142;
    - `OnAfterOneTest` L147-164 removes the steps, decisions and usage of `..ItemIds`, then the rows and incidents;
    - `OnAfterAllTests` L166-178.
  - **`Test/Core/InProduction.cls`** (contended; inherited and called only): `Send` L72-82 (a `WebChat.Post` into `WebChatIn`), `WaitDone` L85-97, `Session` L100-107.
  - **`Test/Core/ConversationProduction.cls`** L57-60 is the `Fixture.AdoptTurns` clean-up pattern (read only).
  - **`Test/Checks/Heartbeat.cls`:** `Tick(tickAt)` L172-183, and the `HEARTBEAT`, `CHECKS` and `TICKWAIT` parameters L17-27, move to `Test.Watch.Case`. `TestFailingOrders` L62-83 is the pattern.
  - **`Test/Data/Fixture.cls`** (contended; call only): `Check` L65-77 (fields set after the defaults), `AdoptTurns` L242, `Clean` L292.
  - **`Test/Contract/Mock.cls`:** `Arm(marker, remaining)` L333 (`""` clears it). `Test/Agent/Conversation.cls` `Arm` L474, with `Armed` cleared at L94-97, is the pattern.
  - **`Test/Agent/RunnerFixture.cls`:** `StepsOf` L335.
  - **`Test/Core/Observe.cls`** (contended; call only): `Events(session, "chat.message", count, seconds)` L46.
  - **Tool-list assertions to update:**
    - `Test/Watch/Turns.cls` L56;
    - `Test/Agent/Runners.cls`: the doc L43-45, `REMINDERTOOLS` L72-73, `TestToolInventory` L312-359 (L317, L324-327);
    - `Test/Agent/Instructions.cls`: the doc L19-20 and L120-125, `TestChat` L66-107, `TestToolsets` L126-198 (L160-166; L180 skips a tool with no `arguments` entry; L184-185 expect `NOSESSION` exactly);
    - `Test/Tools/Reminders.cls` L263;
    - `Test/Bridge/Gate.cls`: `TRUSTEDTOOLS` L103, `READONLYTOOLS` L105, `TestWatchToolsAreClassified` L231-252, `TestFlagsAreListed` L1291-1307, and `AssertSafeReadOnlyOnly` L1652-1715, whose allowed block for `list_productions` at L1666-1672 is the pattern.
  - **The stub oracles to update:**
    - `Test/Bridge/Ext.cls`: the doc L8-9 and L176-177, and L202;
    - `Test/Bridge/Api.cls`: the doc L4-6 and L13-16, and `TestNeutralValues` L22-25.
  - **Run only:**
    - `Test/Bridge/Decide.cls` L1583 (measures itself; it uses explicit filter classes, so the guard does not touch it);
    - `Test/Contract/Ac.cls` L316;
    - `Test/Core/ConversationTurns.cls` `TestStubRenderAddsNothing` L1353-1369 (contended; HostData `{"checks":[{"zz":"result"}]}` from `DecideDouble` L34).
- **Web tests:**
  - **`web/scripts/catalog.test.mjs`:**
    - the header L1-7;
    - 27 keys become 29 at L57-65;
    - the `PAGE_SLOTS` map L67-81;
    - L111-116 is inverted;
    - the `WATCH` fixture at L201 lacks `checks.notEverythingRestPassed`;
    - the key lists at L217-233;
    - L277-286, L296-303 and L327-341 stay valid with a per-key allowance.
  - **`web/scripts/ux-strings.test.mjs`:** `IMPORTED` L41-51; `SOURCES` `ux`, `ac` and `format`; `isFormat` allows the word "at".
  - **`web/e2e/chat/decision.spec.ts`** D7 L296-351: L308 seeds `checks.notEverything` on a mixed list, and L331 expects no sentence. It runs in `live sign-in`.
- **Mock:**
  - `ci/mock/scenarios/A/triage.json` is the shape of a triage reply, and `reminder-list.json` the shape of a `toolUse` with `{}`.
  - `ci/mock/mock.mjs` L15-24: the marker picks the scenario for the triage request and the turn request alike. With a countdown armed at 1, the first request gets `replies[0]` and the later ones get `replies[1 + k]`.
  - `Conversation.Decided` (L382-393) sends the turn only after the decide answer.
- **CI:** `ci/units.sh` L17 already puts `Checks` in lane-a, so the new `Test.Checks.*` classes join it without a change.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Checks/Render.cls` -- implement `Render` as Always gives it -- AD-28: one chooser of the reserved sentence.
  - The parameters are `KEYALLPASSED`, `KEYRESTPASSED`, `KEYNOTEVERYTHING`, `KEYNOTHINGWATCHED` and `REASONNOTRUN`.
  - The class doc states the contract: the input, a result, the order and the key.
- `src/ocutalon/cls/OcuTalon/Checks/ReplyGuard.cls` -- add `RESERVED`, `BANNED` and `Filter` as Always gives them, with the pattern built from the two parameters -- AD-28 and AD-31. The class doc states the rules.
- `src/ocutalon/cls/OcuTalon/Tools/WatchAnswers.cls` -- shape the answers here, since this is the one helper for the watch tools' answers (Rule 2):
  - add `CheckResults`, `PutChecks` and `Checked`;
  - add the parameters `ENTRY` "{name} production" (the UX's and the rail's "Orders production") and `CHECKSNOTREAD` "The background checks of this conversation could not be read, so nothing is known about them." (model text, ASCII);
  - update the class doc.
- `src/ocutalon/cls/OcuTalon/Tools/WatchTools.cls`:
  - add `CheckStatus` and its four parameters;
  - the method doc is the model's description: what each field means, that an empty result means the check has not run yet, to call it when asked whether things are fine, and that OcuTalon shows the results itself;
  - rewrite the class doc for five tools.
- `src/ocutalon/cls/OcuTalon/Tools/Watching.cls`:
  - add `<Tool Name="check_status" Class="OcuTalon.Tools.WatchTools" Method="CheckStatus"/>`;
  - the `Description` adds "and read the latest results of the user's background checks";
  - update the class doc.
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls` -- add the instruction block from Always; the class doc names `check_status` (footprint extension).
- `ci/mock/scenarios/A/checks-false-all-clear.json` -- new. It has the marker `checks-false-all-clear` and three replies:
  1. the triage text `{"outcome":"tellnow","reasons":["The CI mock answers the user now."],"confidence":0.9}`;
  2. `toolUse` `check_status` with `{}`;
  3. "Everything is fine, nothing to worry about. Everything I checked passed. I looked at the Orders production for you."
  - It is used with its countdown armed at 1.
- `web/src/app/shared/check-sentence.ts` -- new and framework-free, with only a type import of `CheckRow` (footprint extension). It exports:
  - `CHECK_TEXTS` = `{ entry: '{entry} ({detail})', detail: '{finding}, at {time}', detailTime: 'at {time}', separator: '; ' }`;
  - `interface CheckCatalog { texts; slots; render(key, slots) }`;
  - `whatFailed(rows, time)` and `checkSentence(key, rows, catalog, time)`, as Always gives them.
- `web/scripts/catalog.mjs` -- (footprint extension):
  - list `checks.notEverything` and `checks.notEverythingRestPassed` after `checks.nothingWatched`;
  - allow a `text` slot for those two keys only, through a per-key allowance beside `SLOT_TYPES`, so every other key still refuses `text`;
  - update the header, the `SLOT_TYPES` comment, the `RENDERER` doc and the `PAGE_SLOTS` comment;
  - then run `node web/scripts/catalog.mjs` to regenerate `web/src/app/msg/catalog.ts`.
- `web/src/app/chat/check-rows.ts` (contended; ONLY under the orchestrator's ruling Q1) -- exactly Q1's (a) lines (the L4 import, one added import of `../shared/check-sentence`, the module constant `CATALOG`, the `sentence` computed at L114-115, the doc clause at L11-12), and nothing else in the file. The reworded doc clause keeps the line that an all-clear never comes from the rows, around the two keys whose `whatFailed` comes from the rows. Use `pageTime` exactly as the feature exports it (Epic 6 is editing `page-time.ts`; whoever integrates later adapts).
- `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls` -- receives `Tick(tickAt)` and its three parameters from `Test.Checks.Heartbeat`, unchanged apart from the move -- extend, don't copy. `src/ocutalon/cls/OcuTalon/Test/Checks/Heartbeat.cls` -- drop its copy of them.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Render.cls` -- new, warm, with no production:
  - one test per Render row of the matrix: `TestAllPassed`, `TestOneFailing`, `TestNonePassed`, `TestNothingWatched`, `TestNotRunYet`, `TestNotResults`, `TestOddValues`;
  - `TestRowsShape`: exactly four string keys, and `rows` is always an array;
  - `TestKeysAreCatalogKeys`: each `KEY*` renders through `Msg.Catalog.Render`.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Guard.cls` -- new, warm:
  - `TestReservedSentences` and `TestBannedPhrases`, which compare the two lists with their sources (`RESERVED` with the catalog texts of `checks.allPassed` and `checks.everythingElsePassed`, minus their periods, plus "Your IRIS system is healthy"; `BANNED` with EXPERIENCE.md's closed list, as written in the test);
  - `TestVariants`, `TestKeepsTheRest` (the byte-for-byte cases), `TestLines`, and `TestEmptied`;
  - `TestThroughConclude` calls `OcuTalon.Bridge.Process.Decide.Conclude(request, ref, reply, "OcuTalon.Bridge.Msg.DecisionPayload", "OcuTalon.Checks.ReplyGuard", "OcuTalon.Bridge.Ext.HostSink", 4242, .response)`, as `Test.Bridge.Decide`'s `Conclude` helper L2905 does. Two cases:
    - a turn reply "All good. I looked at Orders." gives the text "I looked at Orders.";
    - a decide reply whose reasons are "No issues." and "The partner changed its date format." keeps only the second reason line.
    - The test removes its Decision rows.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Turns.cls` -- new. It extends `Test.Watch.Case` and runs fresh: real turns through `WebChatIn`, `Conversation`, the real `Decide` and `ChatAgent` against the CI mock (`PointKeys`).
  - The helper `Ask(session, name)` arms the countdown at 1, `Send`s "Is everything OK? [[mock:checks-false-all-clear]]", and returns `WaitDone`'s Turn.
  - The helper `AssertNoAllClear(text)` checks that the text holds no phrase of `RESERVED` or `BANNED`, ignoring case.
  - `TestFailingOrdersInTheChat` covers AC 1.
  - `TestAllClearOnlyFromCode` covers AC 2, with a `Watch` row whose run fields are set to `passed` with `LastRunAt` now.
  - `TestNothingWatchedInTheChat` covers AC 2.
  - **Clean-up:**
    - each Turn's ItemId joins `..ItemIds`;
    - the countdown is cleared in `OnAfterOneTest`;
    - `OnAfterAllTests` sets `..Refs = Fixture.AdoptTurns(..Sessions, ..Refs)` before `##super()`.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Tools.cls` -- runs warm:
  - `TestDeclarations`: five tools; `want("check_status") = ("safe", 1, 1, "Reading the check results", "", "")`; the own methods become "CheckStatus,DismissIncident,ListProductions,StartWatch,StopWatch";
  - new `TestCheckStatus`, `TestCheckStatusHostData` and `TestCheckStatusNotRead`, which cover the matrix rows "check_status", "HostData kept" and "Refused". Each asserts the whole answer and the whole `HostData` with `AssertObject`, so a field added later fails, and that the double recorded no command;
  - `TestNoSession` covers `CheckStatus()` too, with `HostData` untouched;
  - class doc.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Gate.cls`:
  - `TRUSTEDTOOLS` and `READONLYTOOLS` gain `OcuTalon.Tools.WatchTools:check_status`;
  - `TestWatchToolsAreClassified` asserts `{"classification":"safe","readOnly":1,"trustedOutput":1,"by":"code"}`;
  - `AssertSafeReadOnlyOnly` gains a `check_status` block beside the one for `list_productions`: it runs in untrusted and tainted turns, with one `turn.step` and the taint unchanged;
  - (lead decision at the gate, as U-102 / DW-288 for `dismiss_incident`) a new `TestCheckStatusAnswerIsCodeBuilt` beside `TestDismissAnswerIsCodeBuilt`: every answer shape of `check_status` (rows of each result, no watch, no session, the read failing) has exactly the allowed keys and each check entry exactly its allowed keys (both lists as class parameters), every reason or finding is one of `Checks`' parameters or a count built from one (read from the class, never copied), and none of an incident's `Cause`, `Element`, `FixSummary` or `SampleError` text appears;
  - docs.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls`:
  - `TestChat` asserts "call check_status", "does not repeat the results", "only OcuTalon's own sentence may say that" and "could not read the checks";
  - `TestToolsets` expects eight names and `arguments("check_status") = {}`, which answers `NOSESSION`;
  - docs.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls` -- `REMINDERTOOLS` becomes "cancel_reminder,check_status,dismiss_incident,list_productions,list_reminders,set_reminder,start_watch,stop_watch"; `TestToolInventory` adds `providerOf("ChatAgent", CHECKSTATUS)` = `WatchTools`; docs.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Turns.cls` L56 and `src/ocutalon/cls/OcuTalon/Test/Tools/Reminders.cls` L263 -- the eight names, and their messages.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Ext.cls` L202 -- `Filter("Everything I checked passed.")` is now "", with the message "ReplyGuard removes a reserved sentence (Story 5.7; Test.Checks.Guard pins the rest)"; docs.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls` -- remove the `Render` lines L22-25. The docs say "Checks.Render is no stub since Story 5.7; Test.Checks.Render pins it".
- `web/scripts/check-sentence.test.mjs` -- new. It imports `check-sentence.ts` and `msg/catalog.ts` as they are, and covers every rule of `whatFailed` and `checkSentence` in Always and the matrix row "Page", with a stub time function.
- `web/scripts/catalog.test.mjs` -- update the anchors listed in the Code Map:
  - 29 keys;
  - the two keys in `PAGE_SLOTS` as `{ whatFailed: 'text' }`;
  - L111-116 becomes "renders both whatFailed keys" with a `whatFailed` value;
  - the `WATCH` fixture gains `checks.notEverythingRestPassed`;
  - new: a `text` slot on any other listed key is still refused.
- `web/scripts/ux-strings.test.mjs`:
  - `IMPORTED` gains `['shared/check-sentence.ts', ['CHECK_TEXTS']]`;
  - `SOURCES.ux` gains 'Not everything: {whatFailed}.';
  - `SOURCES.ac` gains, under 'Story 5.7: Asked whether everything is fine, OcuTalon never gives a false all-clear (the failing entry first, then "Everything else I checked passed." only if other checks passed)', the string 'Not everything: {whatFailed}. Everything else I checked passed.';
  - `SOURCES.format` gains the four `CHECK_TEXTS` strings.
- `web/e2e/chat/decision.spec.ts` D7 (footprint extension; only after Q1):
  - the "D7 mixed" turn's key becomes `checks.notEverythingRestPassed`;
  - L331 asserts the sentence `Not everything: Warehouse queue (12 messages are waiting, at ${clock('2025-03-01T10:01:00Z')}); Partner feed (the check did not run, at ${clock('2025-03-01T10:02:00Z')}). Everything else I checked passed.`;
  - a fifth seeded turn "D7 failing" (`checks.notEverything`, with a failed row and a `not_checked` row "Not run yet" with no time) asserts `Not everything: Warehouse queue (12 messages are waiting, at ${clock(...)}); Partner feed (not run yet).`;
  - L341 stays.

**Acceptance Criteria:**
- **AC 1 (Integration AC: consumer `Conversation`, through the `Reply`'s `HostData` and `Checks.Render`, and the page's `chat.message`).** Given session S watches Orders, three failing orders tagged with S's TraceRef have been sent, and a real Tick has recorded the watch as `failed`, when S sends "Is everything OK? [[mock:checks-false-all-clear]]" through `WebChatIn`, the Chat agent calls `check_status`, and the agent then writes an all-clear, then:
  - the Turn is `done` and not a fallback, and its reply is exactly "I looked at the Orders production for you.", with no reserved sentence and no banned phrase;
  - its `CheckKey` is `checks.notEverything`;
  - its `CheckRows` is one row: `failed`, "Orders production", the row's `Finding` (which begins "3 new failures") and the row's `LastRunAt`;
  - the done `chat.message` on S's stream carries the same `replyText`, `checkKey` and `checks`;
  - the turn decision has exactly one tool step, "Reading the check results", `ok`.
- **AC 2 (AD-28 "Prevents").** Given the same message, when S watches Orders with a recorded `passed` run, then the reply is the same filtered text and the key is `checks.allPassed` with one passed row: the all-clear comes only from code, and the guard never removes it. When S watches nothing, the key is `checks.nothingWatched` with no row.
- **AC 3.** Given each `check_status` row of the matrix, when the tool is called in the session's turn, then the answer and `HostData` are exactly the matrix's, nothing is submitted, and a refusal leaves `HostData` untouched.
- **AC 4.** Given each `Render` row of the matrix, when `Checks.Render` is called, then the key and the rows are exactly the matrix's.
- **AC 5.** Given each guard row of the matrix, when `ReplyGuard.Filter` runs, directly or through `Decide.Conclude`, then exactly the listed wording is gone and the rest of the text is kept.
- **AC 6.** Given the gate and the Chat agent, when `check_status` is classified and offered, then:
  - it is safe, read-only and trusted output by code;
  - it runs in untrusted and tainted turns without tainting them;
  - Chat offers eight tools, `check_status` once, from `WatchTools`;
  - the instructions say to call it and never to write an all-clear.
- **DW-90** (ledger; routed by spec_gate 2026-10-22). Given a `chat.message` with `checks.notEverything` or `checks.notEverythingRestPassed` and its rows, when the page shows the reply, then:
  - the sentence above the rows is the catalog text, with `whatFailed` naming every non-passed row as Always gives it, and no raw `{whatFailed}`;
  - a check key with no `whatFailed` left shows no sentence.
  - It is pinned by `check-sentence.test.mjs`, `catalog.test.mjs` and e2e D7.
- **AC 8 (lead decision, the U-102 pattern).** Given every answer shape of `check_status`, when `Test.Bridge.Gate` reads it, then its keys and each entry's keys are exactly the code-built allow-list and every reason or finding comes from `Checks`' parameters, so a free-text field added later fails the test instead of reaching the model as trusted output.
- **AC 7.** Given the product source, when `Test.Bridge.CodeRules`, `Test.Bridge.Ext`, `Test.Bridge.Api`, `Test.Contract.Ac`, `Test.Core.ConversationTurns`, `bash ci/checks.sh`, `node web/scripts/catalog.mjs --check` and `bash docker/tests/test-web-build.sh` run, then they pass. The tool returns through `Result` and has a unique step label, `Render`'s signature is unchanged, and `TestStubRenderAddsNothing` stays green.

## Spec Change Log

- 2026-10-27, spec gate (Epic 5 runner): the orchestrator ruled Q1 (a) with five conditions (recorded in Always, the `check-rows.ts` task and Design Notes); condition 3 read with the epics criterion (veto U-111); status set to `ready-for-dev`.
- 2026-10-27, spec gate (Epic 5 runner): V1 ruled keep (veto U-110); the Gate pinning test for `check_status` added as a lead decision; spine rows written ("HostData" amended, "Reply guard" new, "Tool classification" names `check_status`); Q1 (contended `web/src/app/chat/check-rows.ts`) sent to the orchestrator; status stays `blocked` until Q1 is ruled.
## Review Triage Log

### 2026-10-27 -- Review pass
- verdicts: 26 findings -- high 0, medium 1, low 22, false 0, maybe-false 3
- findings:
  - Blind Hunter
    - `[low]` `[reject]` guard lists are narrow (other all-clear wordings pass) -- the closed list is the UX's; the spec's Never says "No phrase outside the two lists"; the fix edits the intent
    - `[low]` `[reject]` a deleted phrase can leave a fragment ("Not everything is fine" -> "Not") -- spec-bound: removal is literal and never rewrites (Design Notes "Phrase-level removal is literal"); the model is told never to write the phrases
    - `[medium]` `[reject]` a reply the guard empties loses the check results (Decide's `invalid` fallback never reaches `Checked`) -- spec-bound (matrix "Guard lines": an emptied turn is Decide's existing fallback) and the fix is in the contended `Conversation`; the Chat instruction asks for a reply of the model's own
    - `[low]` `[reject]` `CheckStatus` ignores the status of `PutChecks`, no cap on `HostData` -- `Put` fails only with no context, which `Session` has already ruled out; `HostData` is `MAXLEN=""`; a guard for a state not demonstrated
    - `[low]` `[reject]` `whatFailed` lowercases the first character of every finding -- spec-bound (Always); the findings are 5.6's code-built texts, none starts with an acronym
    - `[low]` `[reject]` sentence time has no day -- spec-bound: `{time}` is the page's `pageTime` (Q1), and the time zone and day logic belong to Epic 6's `page-time.ts`
    - `[low]` `[reject]` key lists are hard-coded in several places -- real but small; a shared list across `catalog.mjs`, the page and Render needs a cross-language source; the catalog tests fail when a listed key is missing
    - `[low]` `[reject]` the guard also rewrites reasons and digest lines -- spec-bound (AD-31: the filter runs once on every model text, and the closed list is the UX's)
    - `[low]` `[reject]` `Gate.CodeFinding` treats the allowed texts as regular expressions -- a developer-only looseness that errors loudly on a bad pattern and passes today; no named harm
    - `[low]` `[patch]` `TestEmptied` accepts a whitespace-only result -- tightened to `AssertEquals(..., "")` for the six single-text cases; the blank-line case keeps the blank check (fixed in `Test/Checks/Guard.cls`)
  - Edge Case Hunter
    - `[low]` `[reject]` negation next to a phrase leaves a fragment -- same as the second Blind Hunter finding
    - `[low]` `[reject]` a hyphen or underscore after a phrase counts as a boundary -- the spec says the neighbours must not be a letter or digit; a rare wording
    - `[maybe-false]` `[reject]` a line of only a no-break space after the deletion is kept -- would need a model text that is a phrase and a no-break space alone; low if true
    - `[low]` `[reject]` all-clear wordings outside the lists pass -- same as the first Blind Hunter finding
    - `[low]` `[reject]` no `check_status` call, no rows -- the words and the call are the model's; the instructions ask for the call, and the guard stays literal
    - `[maybe-false]` `[reject]` `Render` and the page differ on an entry of Unicode spaces only -- entries come from `{name} production`, never blank; low if true
    - `[maybe-false]` `[reject]` a `checkedAt` of the right shape but impossible digits -- the value is `LastRunAt`, set by code; low if true
    - `[low]` `[reject]` an empty `DisplayName` gives " production" -- `StartWatch` always sets the display name; not reachable
    - `[low]` `[reject]` non-web channels show no rows -- the spec's Never: no `*Out` operation renders a check key in this story
  - Verification Gap
    - `[low]` `[reject]` no test runs `CheckStatus` with a failing `CheckResults` inside a session turn -- the failure needs an `Ownership.Rows` SQL error, which no test can cause without a seam; the matrix row "Refused" names `CheckResults` directly, as 5.9's `TestIncidentsNotRead` does; reopen_if a read error is observed to answer "nothing watched"
    - `[low]` `[patch]` the `check-rows.ts` wiring is pinned only by an e2e D7 that did not run -- applied: the wiring passes `[]` to `checkSentence`, `live sign-in` went red in D7 only (1 of 193), reverted, and the line is recorded in `## Verification`; the unmutated run is green (192 passed, 1 skipped)
    - `[low]` `[patch]` the fail-closed path has no recorded mutation -- applied: `Catch` returns the text, `Checks.Guard.TestFailsClosed` red, reverted, line recorded
  - Intent Alignment (descriptive; no divergence between the readings)
    - `[low]` `[patch]` the test label "an emptied last line goes without the break before it" says the opposite of its assertion ("Hi.\n") -- the label now says the break before it stays, the assertion follows the spec ("dropped with its line break")
    - `[low]` `[reject]` an edge no-break space may not be trimmed -- same as the Edge Case Hunter's no-break-space finding
    - `[low]` `[reject]` the chat-level tests run only in CI stacks -- they ran in this pass (`Test.Checks.Turns` green fresh, `live sign-in` green); nothing to fix
    - `[low]` `[reject]` files edited that the intent does not name (catalog generator, shared tests, `Tick` moved, `BrokenGuard`) -- all are in the spec's Tasks and footprint extensions, except `Test/Checks/BrokenGuard.cls`, a test-only class that the fail-closed test needs

## Design Notes

**Rulings (all RULED 2026-10-27).** Q1 RULED by the orchestrator: decide, option (a), shared-by-entry, exactly the lines listed in the `check-rows.ts` task; conditions: `checkSentence` returns the three no-slot keys' catalog text as today, never derives an all-clear from the rows (N1), fills `whatFailed` only from rows that did not pass (the lead reads "failed" with the epics criterion's "failing or unchecked entry", veto U-111), gives "" for any other key, and its test pins all four; `check-rows.ts` and `shared/check-sentence.ts` (new) go under `footprint_extensions:`. Originally: Q1 was with the orchestrator (`web/src/app/chat/**` is Epic 6's, and Epic 6 is running). Lead decision at the gate (decide, tightens security posture): `check_status`, declared trusted output by the epics criterion, gets the same guard the owner set for `dismiss_incident` (U-102, DW-288): a `Test.Bridge.Gate` test pins its answer's keys and each check entry's keys to the code-built allow-list, with every reason or finding one of the `Checks` parameters, so a free-text field added later fails it.**
- **Q1. Contended `web/src/app/chat/check-rows.ts` (Epic 6's `web/src/app/chat/**`), the page half of DW-90.**
  - **Why.** The page shows a check key's sentence only through `CheckRows.sentence` (L113-116), and that returns `PAGE_TEXTS[key]` raw. If `catalog.mjs` lists the two keys, the page shows "Not everything: {whatFailed}." with the placeholder. If it does not list them, the page shows no sentence (DW-90). No file outside the contended path renders that sentence.
  - **Recommended (a): allow these lines as shared-by-entry wiring:**
    - L4 becomes `import { PAGE_SLOTS, PAGE_TEXTS, renderPageText } from '../msg/catalog';`;
    - one new line, `import { checkSentence, type CheckCatalog } from '../shared/check-sentence';`;
    - one module constant, `const CATALOG: CheckCatalog = { texts: PAGE_TEXTS, slots: PAGE_SLOTS, render: renderPageText };`;
    - L114-115 become `const key = this.checkKey() ?? ''; return key.startsWith(CHECK_KEY_PREFIX) ? checkSentence(key, this.checks() ?? [], CATALOG, pageTime) : '';`;
    - in the doc, the clause at L11-12 ("when the page renders that key (checks.allPassed, checks.everythingElsePassed and checks.nothingWatched); any other key shows no sentence") is replaced by one that names the two keys whose `whatFailed` comes from the rows.
    - Nothing else in the file changes. Precedent: 5.6's Q2 ruling, one line of `rail-view.ts`.
  - **Alternative (b): route the wiring to an Epic 6 story** (an AC on another epic's story, veto item 8). 5.7 then leaves the two keys unlisted, D7 stays as it is, and DW-90's page half moves with the wiring (veto item 7). `check-sentence.ts` and its test still land, unused.
  - **Alternative (c): a server slot path** (a `Turn` column and a `chat.message` field). That is a schema change (veto item 3) that touches Lane B's `Conversation` and Epic 16's `payloads.ts`, and the page still needs this same edit. Not recommended.

**Veto item for the spec gate (RULED 2026-10-27 by the epic lead: keep as worded, veto U-110):**
- **V1. Public text not written in the UX (veto window, item 5).**
  - `REASONNOTRUN` "Not run yet": the reason of a watch with no run. It appears in its row and in the sentence.
  - The `whatFailed` form `{entry} ({finding}, at {time})`, joined with "; ". The UX writes the catalog sentence ("Not everything: {what failed, with its time}."), the entry ("Orders production") and the digest example "Not checked: Jira (unreachable since 02:10)." The form only arranges those parts, and its strings pass `ux-strings`' `format` check. The findings are 5.6's texts (veto U-105).
  - The `ac` source for "Not everything: {whatFailed}. Everything else I checked passed.".
  - **Recommended:** keep as worded. Rewording is a parameter or constant edit.

**Governing ADs:**
- AD-28: results only from `Checks`; key and rows only from `Render`; the guard on every model text; `check_status` and `HostData`.
- AD-31: `ReplyFilterClass` runs exactly once, before Decide records.
- AD-6: `HostData` goes from the context to the `Reply`.
- AD-10: `check_status` is named as trusted output; read-only rules and taint.
- AD-7: Chat's toolsets and instructions.
- AD-9: the step label.
- AD-32: tools return values, and the page renders catalog keys.
- AD-30: `Conversation` calls `Render` after the guard.
- AD-4: the session's own rows, through the ownership API.
- AD-18: one `BackgroundCheck` table.
- AD-22: the CI mock and throwaways.
- AD-29: Lane A.
- No AC contradicts an AD's Rule. No NFR is unmeasurable.

Conventions: "HostData", "Tool classification", "Tool results", "Agent step labels", "Background checks", "Text OcuTalon sends", "Times", "Tests".

**Integration ACs, Consumes, Consumed-by:**
- **New:** the `check_status` tool, the built `Render` and `ReplyGuard`, `check-sentence.ts`, and the scenario.
- **Integration ACs:**
  - AC 1: the consumer is `Conversation`, against the real production, with the done `chat.message` the page reads;
  - DW-90: the consumer is the page, through e2e D7.
- **Consumes:**
  - 5.6: the run fields and the code-built findings;
  - Epic 0: `Render`'s signature, `ReplyFilter`, `ReplyFilterClass`, `Context.HostData`, `Reply.HostData`, and the `checks.*` keys;
  - 2.6: `Conversation.Checked`, `Turn.CheckKey` and `CheckRows`, `chat.message`, and `check-rows.ts`;
  - 5.1 and 5.9: `Watching`, `WatchTools`, `WatchAnswers` and `CommandCall.Session`;
  - Epic 3: the gate;
  - Epic 1: Decide, the runners and the mock.
- **Consumed-by:**
  - 9.3: `EvalIn` calls `Render`, and `check_status`'s `eval` branch goes in `CheckResults`;
  - Epic 17: the digest's all-clear from `Render`, and the guard's "Your IRIS system is healthy";
  - Epic 8: the page's check rows;
  - a later `*Out` operation that renders a check key builds `whatFailed` by the same rule (spine candidate).

**Extend, don't copy:**
- The tool joins `Watching` and `WatchTools`. Its shaping lives in `WatchAnswers`, whose `ResolveStop` already reads `Ownership.Checks`, and its refusal is `CommandCall.Session`.
- `Tick` moves into `Test.Watch.Case` and is not copied.
- `Turns` inherits `Send`, `WaitDone` and `Session` from `InProduction` through `Case`.
- `check-sentence.ts` reuses `renderPageText`, which already does the slot cleaning, and `pageTime`.
- The new Gate block follows `list_productions`' block.

**Ledger inbox:** DW-90 is addressed: Tasks, the matrix row "Page", the DW-90 AC, and Q1.

**The epic context's "(inference)" lines:**
- **Confirmed:**
  - a not-checked reason is in `Finding` (5.6, Conventions "Background checks");
  - a missing `checks` stays distinct from `[]` (`Conversation.Checked`, and Render's "empty array");
  - `check_status` must be in Chat's toolset (`TOOLSETS` holds `Watching`);
  - the page half reaches a contended path (Q1).
- **Adopted:**
  - a watch with no run counts as not checked ("Not run yet", V1);
  - the source is replaceable (`CheckResults`);
  - `whatFailed`'s time comes from the row's `checkedAt`, formatted by the page's own time function.
- **Decided:**
  - the guard's matching covers case, either apostrophe, any white space, and whole words only;
  - what the guard leaves is never padded: an emptied turn is Decide's existing `invalid` fallback, and an emptied `FILTERED` field is re-validated as Decide already does;
  - no separate Gate test for `check_status`: `Watch.Tools` pins its whole answer and `HostData` exactly, so an added field fails. AD-10 already names `check_status` as trusted output, and no ruling asks for more.

**Decided in-stage:**
- **`whatFailed` names every non-passed row.** So `checks.notEverythingRestPassed`, which `Render` chooses when at least one row passed, is always true: "Everything else" is exactly the rows not named.
- **A result counts as passed only with a check time.** An element with no entry is no result (and keeps the contended `TestStubRenderAddsNothing` green). A stale pass is still a pass with its time: staleness is FR-32's banner (Epic 8), and 5.6 decided that the run time is the check's own.
- **The order is failed, then not checked, then passed.**
- **The model reads `checked` in the instance's time, never UTC,** as `CommandCall.Answer` already does for reminders.
- **Phrase-level removal is literal.** The AC says the guard "removed the reserved sentences and the … phrases and kept the rest of the text". Whole sentences are not removed, so true content around a phrase survives.
- **The guard fails closed.**
- **Step label:** "Reading the check results", in the style of "Reading the failed messages".
- **The page logic goes in `web/src/app/shared/`,** which no epic contends, so that the contended file only wires it. It imports nothing at runtime, so Node's type stripping can test it as `decision-view.test.mjs` tests its module.
- **One scenario, with the countdown.** The marker also reaches the triage request, which `Conversation` sends first and answers before the turn (`Decided` → `Ask`). With the countdown at 1, triage gets `replies[0]` and Chat gets `replies[1]` and then `[2]` (`mock.mjs`'s rule).
- **The failing case is real:** failures, then a real Tick, as in 5.6's `TestFailingOrders`. The passing case uses a fixture run, so it needs no clean Orders.
- **No Task 0.** The context `Put` inside a callback is `CommandCall`'s `CommandCount` path. The ownership read inside the callback is `ResolveStop`. The turn through `WebChatIn` and the countdown are read from the source.
- **(inference), to be shown by the first fresh run:** `ChatAgent` resolves the mock key that `PointKeys` points for a turn that `Conversation` sends, as it does for `RunnerFixture`'s turns. `Turns` pins it.

**Known residual (contended, not ours):** `Test.Core.ConversationTurns`' doc L44-45 and L1350-1352 still says "the real stub". Its assertions hold. The doc belongs to its owner.

**Footprint extensions** (reported under `footprint_extensions:`):
- Not contended:
  - `Agent/Chat.cls`;
  - `Test/Agent/{Instructions,Runners}.cls`;
  - `Test/Bridge/{Gate,Ext,Api}.cls`;
  - `web/scripts/{catalog.mjs,catalog.test.mjs,ux-strings.test.mjs,check-sentence.test.mjs}`;
  - `web/src/app/msg/catalog.ts`, which is generated, so a conflict is resolved by regenerating it;
  - `web/src/app/shared/check-sentence.ts`, which is new;
  - `web/e2e/chat/decision.spec.ts`, D7 only.
- Contended, only under Q1: `web/src/app/chat/check-rows.ts`.

**Spine candidates (Rule 20, for the lead):**
- **The "HostData" row** gets `Render`'s rules and the `whatFailed` rule, the way the page and any later renderer build it (DW-90):
  - an empty array is nothing watched, and an element with no entry is no result;
  - a pass needs a time;
  - the order is failed, then not checked, then passed;
  - `notEverythingRestPassed` iff at least one row passed;
  - `whatFailed` takes every non-passed row as `{entry} ({finding}, at {time})`, joined with "; ".
- **The "Tool classification" row** names `check_status`: its answer is built from the session's own rows (`DisplayName`, `Result`, the code-built `Finding`, `LastRunAt`), pinned by `Test.Watch.Tools`.
- **An AD-28 clarification** of the guard's matching: case-insensitive, either apostrophe, whole words, the phrase deleted with its punctuation, line tidy, never adds text, fails closed.

**Story size:** one story, flagged `oversized`, about Story 5.6's size: some 350 product lines, about 1,000 test lines, and one contended wiring edit. A split (the page half as 5.10) is recommended only if Q1 is answered (b).

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/../.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=5 stage=implement'`.
- Run one command per call, each with `timeout: 600000`.
- Never put two IRIS test runs in one message, and chain nothing after a shard part.

**Commands:**
- (loop) `node --test web/scripts/check-sentence.test.mjs web/scripts/catalog.test.mjs web/scripts/ux-strings.test.mjs` -- expected: every test passes.
- (loop) `node web/scripts/catalog.mjs --check` -- expected: "catalog: generated files are current".
- (loop) `bash docker/tests/test-mock.sh` -- expected: every test passes, and the new scenario loads.
- (loop) `<lane> OCUTALON_RUN_TAG=e5s7iw ci/warm.sh up` -- once per stage, after the scenario file exists. A later change under `ci/mock` needs `down`, then `up`. Expected: READY, and the after-start `RESULT OK` line.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s7iw ci/iris.sh class <Class>`, one call per class -- expected: `CLASS … passed`. The classes:
  - `OcuTalon.Test.Checks.Render`, `OcuTalon.Test.Checks.Guard`, `OcuTalon.Test.Watch.Tools`;
  - `OcuTalon.Test.Bridge.Gate`, `OcuTalon.Test.Agent.Instructions`, `OcuTalon.Test.Bridge.Ext`, `OcuTalon.Test.Bridge.Api`, `OcuTalon.Test.Bridge.CodeRules`, `OcuTalon.Test.Bridge.Decide`.
- (loop) `<lane> OCUTALON_RUN_TAG=e5s7i ci/iris.sh class <Class>`, fresh, one call per class -- expected: passed. The classes: `OcuTalon.Test.Checks.Turns`, `OcuTalon.Test.Checks.Heartbeat`, `OcuTalon.Test.Watch.Turns`, `OcuTalon.Test.Agent.Runners`, `OcuTalon.Test.Tools.Reminders`.
- (once) `<lane> OCUTALON_RUN_TAG=e5s7i ci/iris.sh shard lane-a --part 1/4`, then `--part 2/4`, `--part 3/4` and `--part 4/4`, each in its own call. Lane-a grows from 67 to 70 classes. Use `--part k/5` if a part passes 480 s, and record each part's time.
- (once) `<lane> OCUTALON_RUN_TAG=e5s7i ci/iris.sh shard lane-b` -- expected: passed. It includes `Test.Core.ConversationTurns` with the real `Render`, and `Test.Contract.Ac`.
- (once) `bash ci/checks.sh` -- expected: all pass.
- (once) `bash docker/tests/test-web-build.sh` -- expected: passes (`catalog.mjs --check`, and the build of `check-rows.ts`).
- (once) `npm --prefix web test` -- expected: every script test passes.
- (once) `<lane> OCUTALON_RUN_TAG=e5s7i ci/iris.sh live sign-in` -- expected: passes, D7 included.
- (once) `<lane> OCUTALON_RUN_TAG=e5s7iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e5s7i ci/iris.sh teardown`.

**Shared surfaces:**
- **The Chat agent's tool list** (seven names become eight; `Watching` grows from four tools to five):
  - `Test.Watch.Tools`: `TestDeclarations`;
  - `Test.Watch.Turns`: L56;
  - `Test.Agent.Runners`: `REMINDERTOOLS` and `TestToolInventory`;
  - `Test.Agent.Instructions`: `TestToolsets`;
  - `Test.Tools.Reminders`: L263;
  - `Test.Bridge.Gate`: `TRUSTEDTOOLS`, `READONLYTOOLS`, `TestFlagsAreListed`, `TestWatchToolsAreClassified` and `AssertSafeReadOnlyOnly`;
  - `Test.Bridge.Decide`: measured, with no fixed number;
  - `Test.Bridge.CodeRules`: the step-label floor of 12 and uniqueness.
  - The contended trees assert no tool list (searched: `Test/Core`, `Test/Web`, `Test/Data`, `Test/Live`, `web/e2e`, `eval`).
- **Chat's instructions:** `Test.Agent.Instructions.TestChat`.
- **`Render`'s answer, no longer empty:**
  - `Test.Bridge.Api` (its lines are removed);
  - `Test.Core.ConversationTurns.TestStubRenderAddsNothing` (contended; stays green, run in lane-b);
  - `Test.Contract.Ac` (the signature is unchanged).
- **The guard, no longer pass-through:**
  - `Test.Bridge.Ext` L202;
  - every real turn through the production's Decide. No mock scenario and no `eval` case holds a phrase of either list (searched), and `Test.Bridge.Decide` uses explicit filter classes.
- **The page's catalog module and the check sentence:** `catalog.test.mjs`, `ux-strings.test.mjs`, `test-web-build.sh` (`--check`), and e2e D7 in `live sign-in`.
- **`Tick`** moves from `Test.Checks.Heartbeat` to `Test.Watch.Case`.
- **The mock's scenario folder:** `scenarios.test.mjs` checks for no count.
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to apply** (Rule 19). The implement stage applies each one, observes red, reverts byte-identically and records it here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1 | `CheckStatus` skips `PutChecks` | `Watch.Tools.TestCheckStatus`, `Checks.Turns.TestFailingOrdersInTheChat` (no key on the Turn) |
| AC 1, AC 5 | `ReplyGuard.Filter` returns the text unchanged | `Checks.Turns.TestFailingOrdersInTheChat`, `Checks.Guard.*`, `Bridge.Ext` |
| AC 2 | `Render` gives `KEYRESTPASSED` when every row passed | `Checks.Render.TestAllPassed`, `Checks.Turns.TestAllClearOnlyFromCode` |
| AC 2 | `KEYNOTHINGWATCHED` returned as "" for `[]` | `Checks.Render.TestNothingWatched`, `Checks.Turns.TestNothingWatchedInTheChat` |
| AC 3 | the session filter dropped (B's rows read) | `Watch.Tools.TestCheckStatus` |
| AC 3 | `checked` holds the UTC `checkedAt` | `Watch.Tools.TestCheckStatus` |
| AC 8 | `check_status`'s answer gains a `cause` key, or an entry's finding takes an incident's `Cause` | `Gate.TestCheckStatusAnswerIsCodeBuilt` |
| AC 3 | `PutChecks` overwrites `HostData` whole | `Watch.Tools.TestCheckStatusHostData` |
| AC 4 | `allPassed` when a `not_checked` row is present | `Checks.Render.TestNonePassed`, `TestNotRunYet` |
| AC 4 | `RestPassed` with no passed row | `Checks.Render.TestNonePassed` |
| AC 4 | input order kept (failed not first) | `Checks.Render.TestOneFailing` |
| AC 4 | `passed` without `checkedAt` kept passed | `Checks.Render.TestOddValues` |
| AC 4, AC 7 | an element with no entry becomes a `not_checked` row | `Checks.Render.TestNotResults`, `Core.ConversationTurns.TestStubRenderAddsNothing` (lane-b) |
| AC 5 | case-sensitive matching | `Checks.Guard.TestVariants` |
| AC 5 | the word boundary dropped | `Checks.Guard.TestKeepsTheRest` ("Overall good progress.") |
| AC 5 | the tidy step runs on every line | `Checks.Guard.TestKeepsTheRest` (byte-for-byte) |
| AC 5 | "no problems" removed from `BANNED` | `Checks.Guard.TestBannedPhrases` |
| AC 6 | `check_status` left out of `Watching` | `Watch.Tools.TestDeclarations`, `Instructions.TestToolsets`, `Runners.TestToolInventory` |
| AC 6 | `READONLYCHECKSTATUS` 0 | `Gate.TestWatchToolsAreClassified`, `Gate.TestFlagsAreListed`, `Watch.Tools.TestDeclarations` |
| AC 6 | `TRUSTEDOUTPUTCHECKSTATUS` 0 | `Gate.TestFlagsAreListed`, `Gate` (the `check_status` block: taint set) |
| AC 6 | the instruction block cut | `Instructions.TestChat` |
| DW-90 | `checkSentence` returns `texts[key]` with no slot filled | `check-sentence.test.mjs`, e2e D7 |
| DW-90 | `whatFailed` names only the first non-passed row | `check-sentence.test.mjs`, e2e D7 |
| DW-90 | `checks.notEverythingRestPassed` dropped from `LISTED_KEYS` | `catalog.test.mjs`, `check-sentence.test.mjs` |

**Mutations applied (Rule 19, implement stage).** Each was applied, observed red, and reverted byte-identically (tree hash equal to the one before the mutation):
- mutation: `CheckStatus` without `PutChecks` -> `Watch.Tools.TestCheckStatus` and `TestCheckStatusHostData`, `Checks.Turns` (all three tests: no key on the Turn)
- mutation: `ReplyGuard.Filter` returns the text unchanged -> `Checks.Turns.TestFailingOrdersInTheChat` and `TestNothingWatchedInTheChat`, `Checks.Guard.TestVariants` (and the other line tests), `Bridge.Ext.TestExtensionBases`
- mutation: `Render` gives `KEYRESTPASSED` when every row passed -> `Checks.Render.TestAllPassed`, `Checks.Turns.TestAllClearOnlyFromCode`
- mutation: `Render` returns "" for `[]` -> `Checks.Render.TestNothingWatched`, `Checks.Turns.TestNothingWatchedInTheChat`
- mutation: `CheckResults` reads every session's rows (the session filter dropped) -> `Watch.Tools.TestCheckStatus`
- mutation: `Checked` gives the UTC `checkedAt` as `checked` -> `Watch.Tools.TestCheckStatus`
- mutation: the answer of `check_status` gains a `cause` key -> `Bridge.Gate.TestCheckStatusAnswerIsCodeBuilt` (keys and free text)
- mutation: `PutChecks` ignores the existing `HostData` (overwrites it whole) -> `Watch.Tools.TestCheckStatusHostData`
- mutation: `allPassed` when a `not_checked` row is present (the not-checked group ignored) -> `Checks.Render.TestNonePassed` and `TestNotRunYet`
- mutation: `RestPassed` always, also with no passed row -> `Checks.Render.TestNonePassed`
- mutation: input order kept (the failed, not-checked, passed grouping dropped) -> `Checks.Render.TestOneFailing` and `TestNonePassed`
- mutation: `passed` without `checkedAt` kept passed -> `Checks.Render.TestOddValues`
- mutation: an element with no entry becomes a `not_checked` row -> `Checks.Render.TestNotResults`, `Core.ConversationTurns.TestStubRenderAddsNothing` (run warm)
- mutation: case-sensitive matching (`(?i)` removed) -> `Checks.Guard.TestVariants`
- mutation: the word boundary dropped (lookbehind and lookahead removed) -> `Checks.Guard.TestKeepsTheRest` ("Overall good progress.")
- mutation: the tidy step runs on every line -> `Checks.Guard.TestKeepsTheRest` and `TestLines`
- mutation: "no problems" removed from `BANNED` -> `Checks.Guard.TestBannedPhrases`
- mutation: `check_status` left out of `Watching` -> `Watch.Tools.TestDeclarations`, `Agent.Instructions.TestToolsets`, `Agent.Runners.TestToolInventory` (fresh)
- mutation: `READONLYCHECKSTATUS` 0 -> `Bridge.Gate.TestWatchToolsAreClassified`, `Bridge.Gate.TestFlagsAreListed`, `Watch.Tools.TestDeclarations`
- mutation: `TRUSTEDOUTPUTCHECKSTATUS` 0 -> `Bridge.Gate.TestFlagsAreListed`, `Bridge.Gate.TestWatchToolsAreClassified` and the taint assertions of the `check_status` block
- mutation: the instruction block cut from `Chat` -> `Agent.Instructions.TestChat`
- mutation: `checkSentence` returns `texts[key]` with no slot filled -> `check-sentence.test.mjs` (and e2e D7 for the wiring, below)
- mutation: `whatFailed` names only the first non-passed row -> `check-sentence.test.mjs`
- mutation: `checks.notEverythingRestPassed` dropped from `LISTED_KEYS` (catalog regenerated) -> `catalog.test.mjs` and `check-sentence.test.mjs`
- mutation: `ReplyGuard.Filter`'s `Catch` returns the unfiltered text instead of "" -> `Checks.Guard.TestFailsClosed` (warm; reverted, hash equal)
- mutation: `check-rows.ts` passes `[]` instead of `this.checks()` to `checkSentence` -> e2e D7 in `live sign-in` (the only red of 193; reverted, hash equal)

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `check_status` (safe, read-only, trusted output) copies the session's own production rows into `HostData.checks`; `Checks.Render` is a pure chooser of the key and the rows (failed, not checked, passed); `Checks.ReplyGuard` deletes the reserved sentences and the closed list of banned phrases (case-insensitive, either apostrophe, whole words, fail closed); the page derives `whatFailed` from the rows that did not pass (DW-90, Q1 wiring in `check-rows.ts`). A scenario of the CI mock (`checks-false-all-clear`) drives the real chat turn.

**Files changed.**
- Product: `Checks/Render.cls` and `Checks/ReplyGuard.cls` (built), `Tools/{WatchTools,WatchAnswers,Watching}.cls` (`check_status`, `CheckResults`, `PutChecks`, `Checked`), `Agent/Chat.cls` (instruction block), `ci/mock/scenarios/A/checks-false-all-clear.json` (new), `web/src/app/shared/check-sentence.ts` (new), `web/scripts/catalog.mjs` and the generated `web/src/app/msg/catalog.ts`, and the Q1 lines of `web/src/app/chat/check-rows.ts` (contended; the import, `CATALOG`, `sentence`, the doc clause; nothing else).
- Tests: new `Test/Checks/{Render,Guard,Turns,BrokenGuard}.cls` and `web/scripts/check-sentence.test.mjs`; updated `Test/Watch/{Case,Tools,Turns}.cls` (`Tick` moved from `Test/Checks/Heartbeat.cls`), `Test/Bridge/{Gate,Ext,Api}.cls`, `Test/Agent/{Instructions,Runners}.cls`, `Test/Tools/Reminders.cls`, `web/scripts/{catalog.test,ux-strings.test}.mjs` and D7 of `web/e2e/chat/decision.spec.ts`. No edit to `Test/Core/**` or `Test/Live/**`.

**Review.** 26 findings from four layers: high 0, medium 1, low 22, maybe-false 3. Patches applied: `TestEmptied` tightened and a test label corrected (`Test/Checks/Guard.cls`); two mutation lines recorded (fail-closed; the `check-rows.ts` wiring through e2e D7). Deferred: none. Rejected with reasons: see the Review Triage Log (mostly spec-bound wording rules, such as the closed phrase list, literal removal, and an emptied turn becoming Decide's fallback).

**Follow-up review recommended:** false (no high patched; the patches were two test edits and two mutation records).

**Verification.** All passed:
- Web: `node --test` of the three web test files (59), `catalog.mjs --check`, `docker/tests/test-mock.sh`, `npm --prefix web test` (581).
- Warm classes: `Test.Checks.{Render,Guard}`, `Test.Watch.Tools`, `Test.Bridge.{Gate,Ext,Api,CodeRules,Decide}`, `Test.Agent.Instructions`.
- Fresh classes: `Test.Checks.{Turns,Heartbeat}`, `Test.Watch.Turns`, `Test.Agent.Runners`, `Test.Tools.Reminders`.
- Shards: `lane-a` parts 1/4 to 4/4 (333 s, 148 s, 137 s, 357 s; 70 classes) and `lane-b` (116 s, 42 classes, `Test.Core.ConversationTurns` and `Test.Contract.Ac` among them).
- `bash ci/checks.sh`, `bash docker/tests/test-web-build.sh`, and `live sign-in` (192 passed, 1 skipped; D7 included).
- All mutations of `## Verification` were applied, observed red and reverted. The warm and fresh stacks were torn down; the lane-a lock folder is empty.

**Residual risks.**
- A reply that the guard empties becomes Decide's `invalid` fallback with no check key and no rows, as the spec says (the Chat instruction asks the model for a sentence of its own).
- The guard is a closed list (the UX's), so an all-clear in other words is not removed; only the key chosen in code adds a check sentence.
- `Test.Core.ConversationTurns`' doc still says "the real stub" (contended, not ours).

**Footprint extensions to report:**
- Not contended: `Agent/Chat.cls`; `Test/Agent/{Instructions,Runners}.cls`; `Test/Bridge/{Gate,Ext,Api}.cls`; `Test/Checks/BrokenGuard.cls` (new); `web/scripts/{catalog.mjs,catalog.test.mjs,ux-strings.test.mjs,check-sentence.test.mjs}`; `web/src/app/msg/catalog.ts` (generated); `web/src/app/shared/check-sentence.ts` (new); `web/e2e/chat/decision.spec.ts` (D7 only).
- Contended, under Q1 only: `web/src/app/chat/check-rows.ts`.

**Spine candidates (Rule 20, for the lead):**
- the "HostData" row: `Render`'s rules and the `whatFailed` rule;
- the "Tool classification" row: name `check_status`;
- an AD-28 clarification of the guard's matching.
