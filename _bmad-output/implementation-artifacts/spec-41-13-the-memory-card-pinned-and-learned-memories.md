---
title: "Story 41.13: The Memory card: pinned and learned memories"
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

**Problem:** The Memory card shows only Notes and Your answers, so a person can't see, search, pin, unpin or forget their told and learned memories, and can't see how much of the 1,000-token core memory their pins use. The routes from 41.9 can't back a Pinned tab (DW-1030). A search is not counted against the online demo's allowance (DW-1031). Its 503 `search_busy` would put the whole demo page into its busy state (DW-1040). And the card's Forget dialog is a near-copy of the Documents page's Remove dialog, whose failure notice is never announced (DW-996, DW-997).

**Approach:** The card gains the tabs "Pinned" and "All memories".
- All memories lists the newest memories through the existing items route and searches only on submit. Each row has a Told or Learned chip, Pin or Unpin, and Forget.
- Pinned reads a new route, `GET /api/v1/memory/pinned`. It is answered by a new read verb, `ListPinnedMemories`, which `MemoryOps` handles with 41.12's `Memory.Pinned` and `Memory.CoreBlock`, so "{used} of 1,000 tokens (estimated)" is the cap's own computation.
- On the online demo, `CommandsIn` counts each `SearchMemory` against the message allowance and records no Turn for it.
- The search's 503 carries `Retry-After`, and the client's one demo-busy hook skips `search_busy`.
- One shared confirm dialog replaces both dialogs and announces its failure notice.
- The demo guide's More to try panel and the README point to the card.

## Boundaries & Constraints

**Always:**
- **The figure is the cap's computation (41.12 ruling).** `used` = ceil(`$Length` of `Memory.CoreBlock(sessionRef, "", .block)` / `Memory.#CHARSPERTOKEN`), computed in `MemoryOps` and never as a sum of text lengths. The page shows the number it is given and never computes it.
- **AD-13/AD-4.** The web layer never calls `OcuTalon.Memory`, `Agent.*` or `Core.Allowance`. The session is always `Ownership.SessionRef`, never the client's. Every write keeps the envelope.
- **Only the person pins.** Pin, Unpin and Forget go only through 41.9's routes.
- **The allowance (DW-1031).** Only `SearchMemory` counts, once per submitted search, only while `onlineDemo` = 1, against the same `Limit()` and window as messages (no new number).
  - A refused search records no Turn, does not open the allowance window or its one notice, and answers 429 `allowance` with the messages route's exact body (`{"error":{"code":"allowance","message":"You've used this session's {limit} messages for the hour."},"retryAt":…,"limit":n}`).
  - The list (blank `q`) and the pinned read never count.
- **Busy (DW-1040).**
  - Every 503 `search_busy` (the search, and the pinned read) carries `Retry-After: 5`.
  - The client's whole-page busy rule changes in ONE place (`envelope.interceptor.ts`, through a pure helper): a 503 whose body `error.code` is `search_busy` does not reach `DemoBusyState`, and every other 503 still does.
  - The card shows its own message: "Search is busy right now. Try again in a moment."
- **No false all-clear (AD-28).**
  - A panel whose read has not answered, or failed, shows only its intro: no rows, no figure, no empty text.
  - A row leaves the list only after a 200 or 404.
  - Every notice is announced once and named in its control's `describedBy`.
- **Search on submit only:** Enter or the Search button, never on input. A submit while one is in flight is ignored. A blank submit shows the newest list again.
- **Shared files:** in `Core/CommandsIn.cls` and `Web/Api.cls`, edits are added lines only (Epic 35 Story 35.2). Spine lines are additive, marked `[ADDED 2026-11-09, Story 41.13]`.
- **Tests:** every test added or changed passes on a fresh environment, in either order, and creates and removes its own rows and settings.

**Never:**
- Add a column, index or table, or change `Data.Memory` storage.
- Grant any role, privilege or service to `OcuTalonUser` or the demo account.
- Count the list, a pin, an unpin, a forget or the pinned read against the allowance. Refund a busy or failed search.
- Add a new number: the 1,000 tokens and the allowance's limit are the existing ones.
- Edit contended paths: `Mcp/**`, `Bridge/Adapter/**`, `Msg/Catalog/**`, `Test/Msg/Catalog.cls`, `Production.cls`, `ci/units.sh`, `src/short-names.tsv`, `release/**`, workflows, compose files.
- Reword existing shared lines of `CommandsIn` (`TOOLVERBS`, Routes rows) or `Web.Api` (`IsAdmin`).
- Implement before 41.12 has merged into this branch.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Pinned read | `GET /v1/memory/pinned`, session with pins | 200 `{"items":[{ref,text,savedAt,source,pinned:true}],"used":n}`, newest pin first, `used` = ceil(len(`Memory.CoreBlock`)/4) | failed/no session 500 |
| No pins | same, none pinned | 200 `{"items":[],"used":0}`; the tab shows "0 of 1,000 tokens (estimated)." and "Nothing pinned yet." | none |
| Pinned read busy | `MemoryOps` no answer in 20 s | 503 `search_busy` + `Retry-After: 5`; the tab shows its intro only | the page is not demo-busy |
| Search | submit "vpn" | `GET /v1/memory/items?q=vpn`; best 5 rows; with none, "No memories match." | none |
| Search busy | 503 `search_busy` | `Retry-After: 5`; the card's notice "Search is busy right now. Try again in a moment.", announced; no demo-busy | none |
| Search over allowance | online demo, `Limit()` entries in window | 429 `allowance`, messages' body; nothing sent to `MemoryOps`; no Turn; the card shows the served message | lock busy (`retryAt` ""): 500 |
| Search, local install | `onlineDemo` ≠ 1 | never counted | none |
| List | blank submit or tab opened | newest 20 + `total`; when `total` > rows, "Showing the newest {shown} of {total}. Search to find the others." | read fails: the search form only |
| Pin | Pin on an unpinned row | 200: the row shows Unpin; Pinned re-reads when shown | 409: overCap notice; 404: the row leaves; else "Couldn't pin it. Nothing was changed." |
| Unpin | Unpin on a pinned row | 200: the row shows Pin; on Pinned the list and figure re-read | 404: the row leaves; else "Couldn't unpin it. Nothing was changed." |
| Forget a memory | Forget, then confirm | 200/404: the dialog closes, the row leaves both lists, and Pinned re-reads if it was pinned; a later search can't find it | other: the dialog stays open with its notice, announced and in `describedBy` |
| Typing | keys in the search box | no request | none |
| Online demo | `onlineDemo` true | the card shows the demo rule line; local installs don't | none |
| Other 503 | any API 503 whose code is not `search_busy` | `DemoBusyState` as today | none |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` (server) or `web/` (client) unless given in full. Line numbers are as of `6af03cf1`. 41.12 is planned, not implemented: its symbols (`Memory.Pinned`, `Memory.CoreBlock`, `PINCAPTOKENS`, `CHARSPERTOKEN`, `COREMAX`, `MemoryOps.OnPin`/`OnUnpin`, `Test/Memory/Pins.cls`, `web/e2e/support/memory.ts pinnedCountOf`) come from its spec. Check them on the merged code before starting.

**Server**
- `Msg/Command/ListPinnedMemories.cls` (new): sibling of `Msg/Command/SearchMemory.cls`. No property beyond the base (`SessionRef`). Doc: a read, owner MemoryOps, origin web_user only, not a tool verb, never counted. The compiler writes the storage.
- `Core/CommandsIn.cls`:
  - Routes XData (208-238): append `{"verb": "ListPinnedMemories", "owner": "MemoryOps", "origins": "web_user"}`. Fix the JSON comma by adding to the last row; that is the only touch to an existing line.
  - `Send` (110-114): one added line routing `ListPinnedMemories` through `SendSearch` (119-123, `SEARCHTIMEOUT` 20 at 49).
  - `Carry` (82-104): one added line after the origin checks and before `Join` (99). For verb `SearchMemory` it calls a new private `SearchAllowance(command)`:
    - `Core.Allowance.TryConsumeRead(command.SessionRef, .retryAt)` allows → `""`;
    - refused with a `retryAt` → `..Result("allowance", "")` with `Data` `{"retryAt", "limit": Allowance.Limit()}`;
    - `retryAt` "" → `Result("failed", ..#MESSAGEFAILED)`.
  - Doc lines 16-17 and 30: new lines only.
- `Core/Allowance.cls`:
  - Move `TryConsume`'s body (50-104) into a private `Consume(sessionRef, channel, text, record As %Boolean, Output retryAt, Output firstRefusal)`. `TryConsume` = `Consume(…, 1, …)`, with behaviour unchanged.
  - New public `TryConsumeRead(sessionRef, Output retryAt) As %Boolean` = `Consume(sessionRef, "", "", 0, …)`. With `record` 0 a refusal sets `retryAt` (the oldest blocking entry + `WINDOW`), writes nothing (no `Refused` Turn, no `AllowanceUntil`, `firstRefusal` 0) and needs no transaction.
  - Class doc (2-17): add the read.
- `Memory/Ops.cls` (Lane A; spec-gate item 2):
  - MessageMap (44-56): add `ListPinnedMemories`→`OnListPinned`.
  - Extract `OnSearch`'s item loop (172-181) into a private `Items(rows) As %DynamicArray`, used by both handlers.
  - `OnListPinned`: `Memory.Pinned(request.SessionRef, .rows)`, then `Memory.CoreBlock(request.SessionRef, "", .block)`. Answer `Answer(.response, 1, "done", "")` with `Data` `{"items": ..Items(rows), "used": ($Length(block) + c - 1) \ c}`, where `c` = `Memory.#CHARSPERTOKEN`. An error status or a throw → `Failed`. No lock: `MemoryOps` runs one job (`Production.cls:65` PoolSize 1), which is the only writer of `Pinned`.
  - Class comment: the verb.
- `Web/Api.cls` (added lines only):
  - UrlMap after 244: `<Route Url="/v1/memory/pinned" Method="GET" Call="PinnedMemories"/>`.
  - `Parameter SEARCHRETRYAFTER = 5;` near 187.
  - New private `SearchBusy()`: `Do %response.SetHeader("Retry-After", ..#SEARCHRETRYAFTER)`, then `Quit ..Fail(503, "search_busy", ..#MESSAGESEARCHBUSY)`. `MemoryItems` line 1819 calls it. That one line is an in-place edit of a 41.9 line, which Epic 35 does not touch.
  - New `PinnedMemories()` after `MemoryItems`, modelled on `MemoryItems`/`SearchMemories` (1812-1883):
    - `Ownership.SessionRef`, then `SubmitMemory` of a `ListPinnedMemories`;
    - Ok → 200 with `Data` relayed as `{items, used}`;
    - `busy` → `SearchBusy()`;
    - anything else → 500. A probe seam like `ReadMemories` makes it testable.
  - `ReadMemories`/`SearchMemories` (1827-1883) gain `Output refusal` (`{retryAt, limit}` from `Data` when `Outcome` = `allowance`). `MemoryItems` answers it as `Fail(429, "allowance", $Replace(..#MESSAGEALLOWANCE, "{limit}", limit), , {"retryAt", "limit"})`, the call at `Messages` line 433.
  - Header (77-84): new lines for the pinned route, `Retry-After` and the 429.
- `Eval/Report.cls:1170-1180` `Actions`: the read verbs `SearchMemory` and `ListPinnedMemories` are both left out (`NOT IN (…)`). Update the doc line 1170.
- `Demo/Features.cls` `Ids` (38-47): `memoryCard` right after `memory` (same `has.memory` flag).
- Read only:
  - `Core/Allowance.cls:178` `Limit`;
  - `Web/Api.cls:1339-1368` `Fail` (sets no header);
  - `Web/Public/Status.cls:61` (the `SetHeader` precedent);
  - `Data/Ownership.cls:713-728`;
  - `Memory.cls` `Row` 197.

**Client** (`web/src/app/`)
- `shared/confirm-dialog.ts` (new; replaces `rail/memory-card/forget-dialog.ts` and `documents/remove-dialog.ts`, which are deleted):
  - `ConfirmRequest` (root injectable) holds a signal `{question, confirm, cancel, failed, act: () => Observable<unknown>}`.
  - `ConfirmDialog` (`app-confirm-dialog`), `CONFIRM_TITLE_ID`, `CONFIRMED`. The template, styles and 200/404 rule are those of both dialogs today.
  - The failure notice has an id (`confirm-dialog-notice-${n}`, as `chat/noise-control.ts:16,89`), sits in the confirm `ServerButton`'s `[describedBy]` (`shared/server-button.ts:89`), and is announced once through `Announcer.announce` (`shared/announcer.ts:31`), as `noise-control.ts:115-133` and `incidents/incident-dismiss.ts:107-114` do.
- `rail/memory-card/memory-card-view.ts`:
  - `MemoryTab` gains `'pinned' | 'memories'`; `nextTab(tab, step)` cycles four tabs.
  - New pure helpers:
    - `sourceLabel(source)`: Told, or Learned;
    - `usedText(used)`: en-US grouping;
    - `memoryName(word, text)`: the word, then the text's first 80 characters plus `…` when longer;
    - `listMore(shown, total)`.
  - `MEMORY_TEXTS` gains the strings of spec-gate item 1.
- `rail/memory-card/memory-card.ts`:
  - `TABS` (16) = notes, answers, pinned, memories. The tab style becomes the header navigation's (`header/header-nav.ts:49-56`: 2px, `--action`; DESIGN.md:869). The tab row wraps.
  - New panels:
    - **Pinned:** intro + figure (`font-variant-numeric: tabular-nums`), rows, empty text.
    - **All memories:** `<form role="search">` with a visible label and a submit button (`(ngSubmit)`/`(submit)` only), the more-line, rows, empty and no-match texts.
  - One memory-row template serves both panels:
    - the text;
    - a neutral chip styled with the `--context-badge-*` tokens (`styles/tokens.css:143-150`; `header/header.ts:276-286` is the look);
    - `pageWhen(savedAt)`;
    - a `ServerButton` variant ghost that toggles Pin and Unpin, with the label switching on the same element so focus stays;
    - a ghost Forget.
  - Pinned and All memories read when selected (and again each time), not at construction.
  - Notices follow the noise-control pattern: one per panel, with an id, announced, and named in the pressed row button's `describedBy`.
  - Forget for answers and memories opens `ConfirmDialog` (replacing `ask`, 299-308). After it closes `CONFIRMED`, the row leaves (`gone`, 311-314), Pinned re-reads if the row was pinned, and focus goes to the Memory heading.
  - The demo rule line goes under the tab list when `LiveState.snapshot()?.onlineDemo === true` (`chat/chat-panel.ts:311`).
  - Class doc: the four tabs.
- `documents/documents-page.ts:14,224`: open `ConfirmDialog` with `DOCUMENTS_TEXTS` (`documents-view.ts:25-29`). The behaviour is unchanged.
- `api/api-client.ts` (beside `forgetPrecedent`, 264):
  - `memoryItems(q?)` GET `/memory/items`, with `?q=` when not blank;
  - `pinnedMemories()` GET `/memory/pinned`;
  - `pinMemory(ref)` POST `/memory/:ref/pin` with `{}`;
  - `unpinMemory(ref)` DELETE `/memory/:ref/pin` with `{body: {}}`;
  - `forgetMemory(ref)` DELETE `/memory/items/:ref` with `{body: {}}`.
- `api/memory-card-types.ts`: `MemoryItem` (`source: 'told' | 'learned'`, `pinned: boolean`), `MemoryItems`, `PinnedMemories {items, used}`.
- `live/demo-busy.ts` (framework-free, `DEMO_BUSY_STATUS` at 20): `export function makesDemoBusy(status: number, body: unknown): boolean`, which is false for a body whose `error.code` is `search_busy`.
- `api/envelope.interceptor.ts:43-45`: the one place: `if (error instanceof HttpErrorResponse && makesDemoBusy(error.status, error.error))`. Doc line 18.
- `guide/more-to-try-view.ts`:
  - `MORE_TO_TRY_TEXTS` (21-69) and `MORE_TO_TRY_ITEMS` (87-95) gain `memoryCard` after `memory`;
  - `MoreToTryAction` (75) widens.
- `guide/more-to-try.ts` `press` (206-233): `memoryCard` does what `heartbeat` does, with `#${MEMORY_HEADING_ID}`.
- Root files:
  - `README.md:30`: "seven" becomes "eight".
  - New since 1.0.0 (32-41): one new bullet, plus the forgetting sentence in the Memory bullet (36).

**Tests**
- Server (all on shadow instances, no production):
  - `Test/Core/Allowance.cls`: `TryConsumeRead` tests.
  - `Test/Core/CommandsStep3.cls`:
    - `Contracts` XData (237) and `TestContracts` (40, "seven" verb classes → eight);
    - `TestOrigins` (52);
    - `TestSearchMemoryWaits` (159) also covers `ListPinnedMemories`;
    - new `TestSearchAllowance`.
  - `Test/Memory/Pins.cls` (41.12's): `TestListPinned`.
  - `Test/Web/MemoryApi.cls`:
    - new `TestPinned`, `TestPinnedBusy` and `TestSearchAllowance`;
    - `TestSearchBusy` (368) and `TestSearchSubmitsTheVerb` (338) assert `Retry-After`;
    - `TestNoSessionIs500` (624) and `Call` (723) take the new route.
  - `Test/Web/MemoryApiProbe.cls`: a seam for the pinned read.
  - `Test/Web/Api.cls:953-957`: `TestRoutes` 36 → 37, in map order.
  - `Test/Eval/Report.cls:342` `TestInjectionActions`.
  - `Test/Demo/Features.cls:49-57` `TestIds`.
- Web unit (`web/scripts/`):
  - `memory-card-view.test.mjs` (18-44, 47, 105-109);
  - `demo-busy.test.mjs`;
  - `more-to-try-view.test.mjs` (77, 83, 87-95, 116-119);
  - `ux-strings.test.mjs` (`IMPORTED` 41-71 incl. `ANSWER_WORDS`, DW-998; `SOURCES` 747-753; a new block for this story);
  - `documents-view.test.mjs:27-28`;
  - `floor-sources.test.mjs` (109, 147, 158, 376, 388, 403-405);
  - `announce-focus-sources.test.mjs` (100-127, 136-156);
  - `more-to-try-sources.test.mjs` (37-50).
- e2e:
  - `web/e2e/memory-card.spec.ts` (sign-in-3): MC1 (128), the arrow tests (417-419), `tabOf` types (57-58), MC4-MC9 (the dialog), and the new tests below.
  - `web/e2e/api/memory.spec.ts` (chromium): new LIVE/PANEL tests.
  - `web/e2e/documents/documents.spec.ts` D10 (281) and D12 (316).
  - `web/e2e/guide/more-to-try.spec.ts` (`SEVEN` 62, K3 267-273).
  - New `web/e2e-online/memory-card.spec.ts` (online-demo project).
  - New `web/e2e-online/allowance/memory-search.spec.ts` (online-allowance project).
  - `web/e2e/support/memory.ts`: `setMemorySource(ref, source)` through `irisScript`, beside `seedMemory` (72).

## Tasks & Acceptance

**Execution:**
1. Confirm 41.12 is merged and its named symbols exist. Otherwise HALT `blocked`.
2. `Core/Allowance.cls`: `Consume`, `TryConsumeRead`, the doc. Then `Test/Core/Allowance.cls`:
   - TestReadUnderLimit;
   - TestReadAtLimitRecordsNothing: no new Turn, `AllowanceUntil` unchanged, and a following `TryConsume` still flags `firstRefusal` 1;
   - TestReadFlagOff;
   - TestReadBusyLock.
3. `Msg/Command/ListPinnedMemories.cls`; the `CommandsIn` Routes row, `Send` line, `Carry` line and `SearchAllowance`. Then `CommandsStep3`:
   - Contracts and TestContracts;
   - TestOrigins (web_user only; tool and bridge context refused);
   - TestSearchMemoryWaits for the new verb;
   - TestSearchAllowance, with `onlineDemo` 1 set and restored by the test: at the limit a `SearchMemory` answers Ok 0 `allowance` with `Data` retryAt/limit, nothing is sent and no Turn is added; under the limit it is sent and adds one entry; `ListPinnedMemories` adds none; with the flag off nothing is counted.
4. `Memory/Ops.cls`: `Items`, `OnListPinned`, MessageMap. Then `Test/Memory/Pins.cls` TestListPinned. Expected values are held arithmetic, never read from the code under test:
   - pins of 2,000 and 1,956 single-line characters → items newest first, `used` 1000;
   - one 19-character pin → `used` 15 (block 36 + 3 + 19 + 2 = 60);
   - none → `[]` and 0;
   - another session's pins are never listed.
5. `Web/Api.cls`: route, `SEARCHRETRYAFTER`, `SearchBusy`, `PinnedMemories`, the 429 refusal, header. Then the probe and `MemoryApi` tests, `Api:TestRoutes`, and `Eval/Report` with `Test/Eval/Report:TestInjectionActions` (a `ListPinnedMemories` of session eval leaves `commands` unchanged).
6. `Demo/Features.cls` and `Test/Demo/Features:TestIds`.
7. Client:
   - `live/demo-busy.ts` `makesDemoBusy` with its unit test, then the interceptor;
   - `shared/confirm-dialog.ts`; switch the Memory card and Documents page over; delete both old dialogs;
   - the api functions and types;
   - `memory-card-view.ts`, then `memory-card.ts`;
   - the More to try item and `press`.
   - Search `web/` for `app-forget-answer-dialog`, `app-remove-document-dialog`, `forget-dialog`, `remove-dialog`, `FORGET_TITLE_ID`, `REMOVE_TITLE_ID`, `FORGOTTEN`, `REMOVED`, `'Notes', 'Your answers'`, `nextTab` and the seven-item lists, and update every hit.
8. Web unit tests (paths in Code Map), including the ux-strings sources for every string of spec-gate item 1.
9. e2e:
   - `memory-card.spec.ts` (LIVE), new tests:
     - MC11: four tabs, in order, with roles; arrows cycle all four;
     - MC12: All memories lists a seeded told and a learned row with their chips; typing makes no `/memory/items?q=` request and Enter makes one; a match and "No memories match.";
     - MC13: Pin moves a row to Pinned with the figure (held arithmetic); Unpin re-reads it;
     - MC14: two rows pinned through the API (2,000 + 1,956), then the card's Pin on a 2-character row shows the overCap text, which is announced and named in the button's `describedBy`, and the row stays unpinned;
     - MC15: Forget asks, then the row leaves All memories and Pinned, and a search no longer finds it;
     - MC16: a faked 503 `search_busy` shows the local busy notice;
     - MC17: the confirm dialog's faked 500 notice is announced and named in Forget's `describedBy`;
     - MC18: no demo rule line on a local install.
   - `documents.spec.ts` D10: the same notice checks.
   - `api/memory.spec.ts`, as LIVE:
     - `GET /memory/pinned` signed out 401; 200 with exactly `items` and `used`;
     - after a pin, the row and `used` = ceil((41 + len) / 4);
     - PANEL's pinned list holds none of LIVE's refs;
     - after the unpin, `[]` and 0.
   - `web/e2e-online/memory-card.spec.ts`:
     - the demo rule line shows;
     - a faked 503 `search_busy` (with `Retry-After`) on `?q=` shows the card's notice, and `[data-banner="demoBusy"]` stays at 0;
     - the control case: a faked 503 with code `busy` on the same route shows the banner.
   - `web/e2e-online/allowance/memory-search.spec.ts`, on a fresh demo session:
     - seed its `AllowanceTimes` with 49 current entries through `irisScript`;
     - one search from the card answers 200 or 503 and makes the count 50;
     - the next answers 429 with the messages body, and the card shows the served text;
     - a chat `POST /messages` is then 429 too (the shared count);
     - no refused Turn of the run is left (the unit's own post-check).
   - `more-to-try.spec.ts`: eight items.
10. Spine, bottom up (spec-gate item 3). Then `memlog.py append --type decision --text "Story 41.13: ListPinnedMemories read verb and GET /api/v1/memory/pinned (used = the cap's own computation); each SearchMemory counts against the online demo's message allowance in CommandsIn with no Turn; 503 search_busy carries Retry-After and is not the page's busy state; 429 is taken by the allowance"`, then `lint_spine.py`.
11. `README.md`: lines 30, 36 and the new bullet (spec-gate item 1).

**Acceptance Criteria:**
- AC 1 (FR-41, FR-73, FR-74): Given the signed-in page, when the Memory card loads, then its tabs are Notes (selected), Your answers, Pinned and All memories, in the header navigation's style. All memories has a search box and, on each row, a Told or Learned chip, Pin or Unpin, and Forget. Every control is labelled and usable from the keyboard (MC11, MC12).
- AC 2 (FR-74, DW-1030, AD-21, AD-7): Given pins, when Pinned is shown, then it reads "Pinned facts are read at the start of each conversation. {used} of 1,000 tokens (estimated)." with `used` from `GET /api/v1/memory/pinned`, which equals ceil(len(`Memory.CoreBlock`)/4), and its rows newest pin first. A refused pin shows "That would go over the 1,000-token limit. Unpin something first.", announced (`Pins:TestListPinned`, MC13, MC14, `memory.spec.ts` as LIVE with PANEL isolation).
- AC 3 (FR-73): Given a memory, when Forget is confirmed, then after a 200 or 404 it leaves All memories, Pinned and a later search at once. Otherwise the dialog stays open with an announced notice (MC15, MC17).
- AC 4 (DW-1031, AD-20): Given the online demo, when searches are submitted, then each one counts against the message allowance and the one past the limit answers 429 with the messages body, records no Turn, and leaves the chat's next 429 still the first refusal. The list and the pinned read never count. Searches run only on submit (`CommandsStep3:TestSearchAllowance`, `Allowance:TestReadAtLimitRecordsNothing`, MC12, `memory-search.spec.ts`).
- AC 5 (DW-1040, AD-25): Given a 503 `search_busy`, when it reaches the page, then it carries `Retry-After: 5`, the card shows "Search is busy right now. Try again in a moment.", and the page does not become demo-busy, while any other 503 still does. 429 is taken by the allowance (`MemoryApi:TestSearchBusy`, `TestPinnedBusy`, `demo-busy.test.mjs`, `e2e-online/memory-card.spec.ts`).
- AC 6 (DW-996, DW-997, NFR-25): Given Forget an answer, Forget a memory or Remove a document, when it fails, then the one `ConfirmDialog` shows the notice, names it in the confirm button's `describedBy` and announces it once (MC17, D10, `floor-sources`, `announce-focus-sources`).
- AC 7 (FR-73; findability): Given the card on the online demo, when it loads, then it shows the per-session rule (`e2e-online/memory-card.spec.ts`, MC18). Given the README, when this story updates it, then its memory bullet says what forgetting removes and that earlier messages aren't rewritten, New since 1.0.0 has the Memory card line, and line 30 says eight. Given More to try, when the panel opens, then it holds eight items with `memoryCard` after `memory`, and its button focuses the Memory heading (`TestIds`, `more-to-try-view.test.mjs`, `more-to-try.spec.ts`).
- AC 8 (Rule 1 integration): Given LIVE with a seeded memory, when the card's Pin is pressed and Pinned opened, then the row and the held-arithmetic figure come back through the real route, `CommandsIn`, `MemoryOps.OnListPinned` and `Memory.CoreBlock` (MC13).

## Spec Change Log

- 2026-11-09 (planner-2026-11-09-41.13, Contest Planner under the owner's delegation, relayed by the orchestrator): the spec-gate items are ruled as below (verbatim). Where a text below differs from the Design Notes' drafts, the ruling wins; implement uses these exact strings.

  1. PUBLIC TEXT: everything APPROVED as drafted EXCEPT:
  - Empty states (findability):
    - "Nothing pinned yet. Pin a memory from All memories."
    - "No memories yet. Say "Remember that ..." in the chat."  (straight ASCII quotes, as in the other look-for lines)
  - More to try look-for: "First do "Ask it to remember something". Then open All memories in the Memory card and press Pin on the memory marked Told. Open Pinned to see it: pinned facts are read at the start of each conversation, up to 1,000 tokens."
  - README bullet: "- **The Memory card.** In the Memory card, All memories lists what OcuTalon remembers, each marked Told or Learned, with Pin, Unpin and Forget on each and a search box. Pinned shows the facts read at the start of each conversation and how much of their 1,000-token limit they use. Try it: More to try, *Pin a memory*."
  - The Memory bullet's added sentence at L36: APPROVED as drafted.
  - The online-demo note is APPROVED ONLY AS A VERIFIED CLAIM: review checks both halves against the code (deleted on sign-out; deleted at the demo reset). If either half is not true, DROP that half rather than change the code to match, and report it (PLANNER REPORT).
  - Placement: right after `memory`. The count follows the registry; up to ten items in all is fine.
  2. ListPinnedMemories + GET /api/v1/memory/pinned: APPROVED (41.9 precedent). `used` comes from Memory.CoreBlock, the same computation as 41.12's cap, so the card's figure and the refusal never disagree; a test pins that. Owner from the session. Corrected route rule: LIVE gets 200 for its own pins; the second session sees none.
  3. SPINE: the additive lines under AD-1, AD-20, AD-21, AD-33, the REST table and AD-25: APPROVED as worded.
  4. SEARCH ALLOWANCE: APPROVED. Allowance.TryConsumeRead, no refused turn, no notice window; a refused search answers 429 with the messages route's body, and the card shows the existing allowance message. 41.9's read-verb condition still holds (a search counts as no command or Act in the eval or the gates).
  DW-1030's paging is declined (newest 20 + search).

## Review Triage Log

## Design Notes

**ADs:**
- AD-1: the gate; the new read verb is web_user only.
- AD-4: the server-side session.
- AD-7: the figure uses `Memory.CoreBlock`, which formats only through `Agent.Input.CoreBlock`.
- AD-13: no privilege for the CSP user, the envelope, and no `Memory`/`Agent` call from `Web`.
- AD-20: the allowance.
- AD-21: memory and the cap.
- AD-25: the busy state, amended by an additive line.
- AD-28: no false empty.
- AD-29 and AD-33: lanes and owners.
- The dependency direction (spine "Invariants & Rules"): `Web` may reference only `Msg`, `Data`, `Commands.Submit` and the shared APIs, and only channel services call `Core.Allowance`. So the count sits in `CommandsIn`, inside Core.

No AC contradicts an AD's Rule except AD-25's "whose 503 the page itself shows as busy". The Planner's DW-1040 ruling decides that, and it is written as an additive amendment line (spec-gate item 3).

**Already met (evidence):**
- Pin, Unpin, Forget and the list/search routes with LIVE/PANEL tests: 41.9 (`Web/Api.cls:238-244, 1812-1935`) and 41.12 (pins).
- "When the second part is on": no flag exists. The tabs are on wherever this code is, and the memory store (Epic 19) is in every build of this branch.
- The `over_cap` text is approved (41.9).

**Decided in-stage:**
- **The pinned read is a `MemoryOps` read verb, not an `Ownership` kind.** The figure must be `Memory.CoreBlock`'s, which runs SQL the CSP user may not run (AD-13), and `Web` may not call `Memory` or `Agent.Input`. One answer that holds both the rows and `used` can't disagree with itself, because `MemoryOps` runs one job and is the only writer of pins.
- **`used` rounds up.** With ceil, "1,000 of 1,000" shows exactly when no further pin can fit: the smallest pin adds 4 characters, so 3,997 characters or more cannot take one. With no pins, `used` is 0.
- **`search_busy` is the one busy code of the memory reads.** The pinned read's busy answers it too, so the client's one exemption covers both. On Pinned, a busy read shows the intro only, as any failed read does.
- **`Retry-After: 5`** (seconds), shorter than the 20 s wait already spent. It is an implementation detail.
- **Allowance:**
  - A busy or failed search still counts, because it reached the queue that DW-1031 protects; no refund.
  - A refused search opens no window, so the chat's own first refusal still gets its one notice.
  - The card shows the served 429 message and does not call the page's `AllowanceState`. The chat learns of the refusal on its own next send.
- **Reads:** Pinned and All memories read when selected, so every page load costs no `MemoryOps` round trip. Notes and Your answers keep 41.6's reads.
- **One card-level demo rule line**, under the tab list.
- **Accessible names** use the text's first 80 characters, the length of a note's opening.
- **The tab style** moves from 3px device tabs to DESIGN.md:869's 2px header-navigation style. The tab row wraps so that four tabs fit the rail.
- **Errors:**
  - Pin and unpin answering 404 remove the row (it is gone).
  - A search failure other than busy or the allowance shows the served `error.message`, else the busy text.
- **The More to try button** focuses the Memory heading (the heartbeat item's pattern). Its look-for text says to open All memories, so no card API is needed.
- **Panel capacity:** the panel has no count cap; its room is a scroll region (`more-to-try-room.ts`). Eight items fit, so no grouping is needed.

**Extend, don't copy:**
- `ConfirmDialog` replaces `ForgetDialog` and `RemoveDocumentDialog` (DW-996).
- `ListPinnedMemories` follows `SearchMemory`.
- `OnListPinned` follows `OnSearch` and shares `Items`.
- `TryConsumeRead` shares `TryConsume`'s core (`Consume`).
- `PinnedMemories` follows `MemoryItems`; one `SearchBusy` serves both 503s.
- The notices follow `noise-control.ts`.
- The More to try item follows `heartbeat`.
- The api functions follow `forgetPrecedent`.
- `setMemorySource` sits beside `seedMemory`.

**Integration ACs:** AC 8. The consumer is the card, through the real route, gate, `MemoryOps` and `Memory.CoreBlock`. AC 4's online test drives the real `CommandsIn` and allowance.

**Consumes:**
- 41.9's items, pin and forget routes, `SearchMemory`, `SendSearch` and `MESSAGESEARCHBUSY`.
- 41.12's `OnPin`/`OnUnpin`, `Memory.Pinned`, `Memory.CoreBlock`, `CHARSPERTOKEN` and `pinnedCountOf`.
- `Core.Allowance`, `ServerButton`, `Announcer`, `Dialogs` and `InlineNotice`.

**Consumed-by:**
- 41.14: the card's Forget and the pinned route, for the forget proofs.
- The release check: the Planner pins a fact on the card.

**Ledger inbox:**
- DW-996: `shared/confirm-dialog.ts`; AC 6.
- DW-997: AC 6, MC17 and D10.
- DW-1030: `GET /memory/pinned` gives every pinned row and `used`; AC 2. Declined DW-1030 (paging part only): All memories shows the newest 20 with the "Showing the newest … Search to find the others." line, and search reaches the rest. Paging would add a route parameter that no AC asks for.
- DW-1031: submit-only and `CommandsIn` counting; AC 4.
- DW-1040: `Retry-After`, the one-place exemption, the e2e proof and AD-25's line; 429 is taken (`POST /api/v1/messages`, `Web/Api.cls:433`); AC 5.
- DW-998 (terminal; its `reopen_if` is met by this story's ux-strings edit): `ANSWER_WORDS` joins `IMPORTED`.

**Spec-gate items (RULED 2026-11-09, see the Spec Change Log entry planner-2026-11-09-41.13: approved with four text edits — the two empty states, the More to try look-for and the README bullet; the online-demo note only as a verified claim, dropping any half the code does not do):**
1. **Public text.** EXPERIENCE.md is cited as `E` with its line.
   - **Tabs** "Pinned", "All memories" (E:1050).
   - **Pinned intro** "Pinned facts are read at the start of each conversation." with "{used} of 1,000 tokens (estimated)." (E:1054, shown as two parts).
   - **Chips** "Told", "Learned" (E:1055).
   - **Buttons** "Pin", "Unpin", "Forget" (epics.md 41.13). Accessible names "Pin {opening}", "Unpin {opening}", "Forget {opening}" (not in UX).
   - **Reused, approved:**
     - over_cap "That would go over the 1,000-token limit. Unpin something first." (E:1054, 41.9);
     - busy "Search is busy right now. Try again in a moment." (41.9);
     - the allowance message (served);
     - "Cancel" and "Forget" (41.6).
   - **Not in UX (new):**
     - search label "Search your memories" and button "Search";
     - "Nothing pinned yet.";
     - "No memories yet.";
     - "No memories match.";
     - "Showing the newest {shown} of {total}. Search to find the others.";
     - "Forget this memory? OcuTalon will stop using it." (modelled on E:1053);
     - "Couldn't pin it. Nothing was changed.";
     - "Couldn't unpin it. Nothing was changed.";
     - the demo rule: "On the online demo, your memories and pins belong to this visit: they're deleted when you sign out or the demo resets. Each search counts as one of your messages."
   - **More to try** (not in UX): label "Pin a memory", button "Go to the Memory card", look-for "After Ask it to remember something, open All memories in the Memory card and press Pin on the memory, marked Told. Then open Pinned: pinned facts are read at the start of each conversation, up to 1,000 tokens."
   - **README:**
     - line 30 "seven" → "eight";
     - the new bullet "- **The Memory card.** In the Memory card, All memories lists what OcuTalon remembered, each marked Told or Learned, with a search and Pin, Unpin and Forget on each. Pinned shows the facts read at the start of each conversation and how much of their 1,000-token limit they use. Try it: More to try, *Pin a memory*.";
     - appended to the Memory bullet (36): "Forgetting deletes the memory, its search entries and any pin at once, so no later session start reads it; earlier messages of the current conversation aren't rewritten."
2. **Lane A edit by a Lane B story** (the epic: "Each story keeps its home lane's files"): `Memory/Ops.cls` gets one MessageMap entry, one handler and the shared `Items` helper, and `Test/Memory/Pins.cls` gets one test. This is 41.9's ruled precedent for `SearchMemory`, and the alternatives need a spine dependency arrow (`Web` → `Agent`/`Memory`).
3. **Spine lines** (additive, `[ADDED 2026-11-09, Story 41.13]`):
   - AD-1 after L122: `ListPinnedMemories`, web_user only, a read, with the bounded wait.
   - AD-20 after L687: `CommandsIn` counts each `SearchMemory` through `TryConsumeRead` (no Turn, no window); a refusal is 429 `allowance`.
   - AD-21 after L714: the Pinned tab reads `ListPinnedMemories`; `used` = ceil(len(`Memory.CoreBlock`)/`CHARSPERTOKEN`).
   - **AD-25 amendment**, after the "Demo busy" bullet: a 503 whose code is `search_busy` is the Memory card's own message, never the page's busy state (one client exemption), and carries `Retry-After`; 429 is the allowance's.
   - AD-33 cross-area row after L1400.
   - A REST row after L1548: `GET /api/v1/memory/pinned`; the search's 429 and `Retry-After`.
4. **Security:**
   - no new role or grant;
   - the new route is the session's own, with the server-side `SessionRef` and the read verb from web_user only;
   - the allowance write uses the existing row lock.

**Contended (Epic 35.2):** `CommandsIn` and `Web.Api` get added lines only, except the Routes JSON comma and `MemoryItems`' busy line (a 41.9 line). Footprint extensions: `Core/Allowance.cls`, `Eval/Report.cls`, `Demo/Features.cls`, `web/src/app/documents/**`, `web/e2e/documents/**` and `web/e2e-online/**`.

**CI:** no new unit, area or group. The new e2e files fall into the existing projects by folder (`online-demo`, `online-allowance`, `sign-in-3`, `chromium`).

## Verification

Run from the worktree root, one command per call, `timeout: 600000`, each sized to about 150 s. Prefix every `ci/` call with `OCUTALON_LOCK_DIR=<lock-dir>/lane-a OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=41 stage=<stage>'`. The fresh tag is `e41s13i`, the warm tag `e41s13iw`. Never two test runs in one message. Every IRIS MCP call names `server` and `namespace`. No real key, no Telegram bot. After recompiling `MemoryOps` on the warm stack, restart its production (41.9).

**Shared surfaces:**
- the card's tab list (MC1, the arrow tests, `nextTab`, `floor-sources`);
- the dialog files (`floor-sources`, `announce-focus-sources`, MC4-MC9, D10, D12);
- the More to try item count (`more-to-try-view.test.mjs`, `more-to-try.spec.ts`, `Test.Demo.Features:TestIds`, `more-to-try-sources`);
- README.md:30's count;
- the ux-strings lists (`IMPORTED`, `SOURCES`);
- `MEMORY_TEXTS`;
- `TestRoutes` (37);
- `CommandsStep3` Contracts and TestContracts;
- `Eval.Report` actions;
- the interceptor's 503 rule (`demo-busy.test.mjs`, `busy-state.test.mjs`, `e2e-online/busy.spec.ts`);
- `memory.spec.ts`;
- `Allowance.TryConsume`'s behaviour (`Test.Core.Allowance`, `online-allowance`).

Every test added or changed passes on a fresh environment, in either order, and creates and removes its own rows and settings.

**Commands:**
- (once) `OCUTALON_RUN_TAG=e41s13iw ci/warm.sh up`. Expected: ready.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e41s13iw ci/iris.sh class <Class>`, one call each. Expected: passed.
  - `OcuTalon.Test.Core.Allowance`
  - `OcuTalon.Test.Core.CommandsStep3`
  - `OcuTalon.Test.Memory.Pins`
  - `OcuTalon.Test.Web.MemoryApi`
  - `OcuTalon.Test.Web.Api`
  - `OcuTalon.Test.Eval.Report`
  - `OcuTalon.Test.Demo.Features`
  - `OcuTalon.Test.Core.AllowanceInProduction`
- (loop) `cd web && node --test scripts/<file>.test.mjs`, one file each. Expected: pass.
  - `memory-card-view`
  - `demo-busy`
  - `busy-state`
  - `more-to-try-view`
  - `more-to-try-sources`
  - `ux-strings`
  - `documents-view`
  - `floor-sources`
  - `announce-focus-sources`
  - `playwright-projects`
- (once) `cd web && npm run lint`, then `npx playwright test --list e2e/memory-card.spec.ts e2e/api/memory.spec.ts e2e-online/memory-card.spec.ts e2e-online/allowance/memory-search.spec.ts`. Expected: exit 0, and every new test listed.
- (once) `cd web && npx ng build`. Expected: success.
- (once) `bash docker/tests/test-class-rules.sh`, then `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-readme.sh`. Expected: pass.
- (once) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16`. Expected: the baseline (`"ok": false`, 10 low `placeholder` findings, nothing new).
- (once) `OCUTALON_RUN_TAG=e41s13iw ci/warm.sh down`, then `OCUTALON_RUN_TAG=e41s13i ci/iris.sh teardown`.
- **Left to CI** (each over 150 s locally):
  - `live:sign-in-3` (`memory-card.spec.ts`, `more-to-try.spec.ts`);
  - `live:sign-in` (`api/memory.spec.ts`, `documents.spec.ts`);
  - `live:online-demo` (`e2e-online/memory-card.spec.ts`);
  - `live:online-allowance` (`memory-search.spec.ts`);
  - the shards;
  - `bash ci/checks.sh`;
  - the lead's fresh-environment check.

**Mutations (Rule 19), one per AC.** Apply on the warm stack (or the web unit), observe red, revert, confirm byte-identical (`git status --short`, `git diff --stat`). Record each as `mutation: … → … red`.
- AC 1: `TABS` without `memories` → `memory-card-view.test.mjs` (`nextTab` cycle) red. MC11 is CI only.
- AC 2: `OnListPinned` computes `used` from the sum of the text lengths → `Pins:TestListPinned` red (989 against 1000).
- AC 3: CI only, as 41.9's e2e mutations: the card keeps the row after `CONFIRMED` → MC15 red. QA or review records it from a CI or `live:sign-in-3 --part` run.
- AC 4: `SearchAllowance` skipped → `CommandsStep3:TestSearchAllowance` red. `Consume` records a Turn when `record` is 0 → `Allowance:TestReadAtLimitRecordsNothing` red.
- AC 5: `SearchBusy` without `SetHeader` → `MemoryApi:TestSearchBusy` red. `makesDemoBusy` ignores the code → `demo-busy.test.mjs` red (and the online spec in CI).
- AC 6: the notice id removed from `describedBy` → `floor-sources`/`announce-focus-sources` or MC17 red (name the test that went red).
- AC 7: `Ids` without `memoryCard` → `Features:TestIds` red.
- AC 8: CI only (MC13). The local stand-in is AC 2's mutation.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
