---
title: 'Story 31.2 part 1: a fix result says how far it got, the next turn knows a tool call finished, and three layout fixes'
type: 'feature'
created: '2026-11-02'
status: 'done'
baseline_revision: 'aa312ea4c9d9b56cb7409af90580336c03e5bb2c'
baseline_commit: 'aa312ea4c9d9b56cb7409af90580336c03e5bb2c'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad/custom/skill-rules.md'
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: 'DW-473 residual: the page cannot show a still-running fix run''s counts so far (result.stillResending needs completed and count), because Live.Payload.Incident fills Requests[].Result only from an ended FixRun (Incident.cls:144-147) and the progress notice is record-only on the web channel (WebChat.Out INCIDENTKINDS)'
    evidence: 'spec-30-5 row 2 (FixRun has no EndedAt and no counts, the row stays executing); payloads.ts IncidentRequestResult; Watch.Notice ResultSlots needs completed/count'
    location: 'src/ocutalon/cls/OcuTalon/Live/Payload/Incident.cls (Lane A), src/ocutalon/cls/OcuTalon/Fix/Run.cls (Lane A)'
    severity: 'low'
---

<intent-contract>

## Intent

**Problem:** This is part 1 of Story 31.2, split under the lead's direction 2 (see `## Clarification Needed`). It covers five things:
- **DW-472:** the page shows a fix run that stopped partway as "had changed since the dry run" (`result.skipped`). The server's notice already says `result.stoppedPartway`.
- **DW-473:** the page has no named still-resending state for a run that goes past FixExecutor's 60-second wait.
- **DW-443:** the next turn is never told that an approved tool call finished (AD-30's code-written `SystemNote`).
- **DW-530, DW-542 and DW-543:** three small layout faults.
- **DW-497:** cards A7 is flaky at its browser sign-in.

**Approach:** Work only in Lane B's page and Core code, and read only what Lane A already sends:
- **DW-472:** `resultView` picks `result.stoppedPartway` exactly where the server's `Watch.Notice.ResultKey` does, and the web catalog list gains the key.
- **DW-473:** the card's existing fixing line is the page's still-resending state. The counts-so-far residual is deferred.
- **DW-443:** `Conversation.Ask` puts a code-written note on the turn request, built from the session's own `tool_call` rows that finished in that turn's window, through a new `Ownership` read.
- **DW-530:** the stacked header stops sticking where it would pass a quarter of the window.
- **DW-542:** the guide's finish state wraps to full width.
- **DW-543:** the empty chat opens at its top.
- **DW-497:** A7 signs in over HTTP.

## Boundaries & Constraints

**Always:**
- **The page's result key order mirrors `Watch.Notice.ResultKey`** (`src/ocutalon/cls/OcuTalon/Watch/Notice.cls` :180-191):
  - state `executing` gives `stillResending`;
  - then `interrupted` above 0 gives `interrupted`;
  - then `couldNotStart`;
  - **then `unreached` above 0 gives `stoppedPartway`**;
  - then `failedAndSkipped`, `failedAgain`, `skipped`, `allThrough`.
- **The stoppedPartway slots mirror `ResultSlots`** (:231-235): `count` = total, `itemNoun`, `completed`, `resent`, and `notTried` = max(unreached - 1, 0). Tone `partial`, icon `triangle-alert`. A missing or non-numeric `unreached` counts as 0, so older payloads pick exactly the keys they pick today.
- **The type is already there.** `unreached` is read from the generated `web/src/app/live/payloads.ts` `IncidentRequestResult.unreached` (:80, regenerated in c67cdf16). AD-12's one-shape rule therefore holds with no local type.
- **The tool note is code-written** from the approval row's fields `ToolName`, `State` and `FinishedAt` only (AD-30, AD-10 3a).
  - Never `ToolArguments`, a tool result, a Decision's `Reasons` or any model-written text.
  - The time comes from `OcuTalon.Data.Time.ForMessage`, never as UTC.
  - Row `State` `done` reads "done". `failed` (including Result `interrupted`) reads "failed".
- **Which rows the note reads:** the session's own rows (`OwnerRef` = the turn's SessionRef) of `Kind` `tool_call` with `FinishedAt` set, through the `OcuTalon.Data.Ownership` API (AD-31, read-only bridge data).
- **Each finished call lands in exactly one turn's note.** The window is (the previous Turn row's `CreatedAt`, this turn's `CreatedAt`], with "" as the lower bound for a session's first turn. The note is the same each time `Ask` runs for the same turn: Busy retry, broken retry, fresh after taint.
- **A failed read never stops the turn.** It is logged, and the note is "".
- **Conversation keeps its scanned boundaries** (`Test.Core.ConversationTurns` `TestSourceKeepsToItsBoundaries` :1133): no `OcuTalon.Msg.Catalog`, no `SendRequestSync`, no `OcuTalon.Core.Allowance`.
- **The header stays sticky** wherever its height is at most a quarter of the window's height, so `floor/layout.spec.ts` at 1000x800 and at 640x360 is unchanged.
- **With entries, the chat's bottom-follow is unchanged.**
- Every test added or changed creates and removes its own rows, and passes on a fresh stack in either order.

**Never:**
- **Never edit these files** (contended, or another lane's):
  - Lane A: `Live/Payload/Incident.cls`, `Live/Payload/Part/*`, `Fix/**`, `Watch/**`, `Bridge/**`;
  - catalog: `Msg/Catalog/*.cls`, `Msg/Catalog.cls`, `Test/Msg/Catalog.cls`;
  - other server files: `Agent/*`, `Web/Api.cls`, `Test/Data/Fixture.cls` (calling its helpers is fine), `Test/Live/Payloads.cls`;
  - web: `web/src/app/api/api-types.ts`, `web/src/app/live/live-store.ts`, `web/src/app/live/payloads.ts`;
  - e2e: `web/e2e/support/floor.ts`, `web/e2e/support/{approvals,demo-path,devices,iris,navigate,rehearsal,trace}.ts`, `web/e2e/sign-in/helpers.ts`, `web/e2e/banners/banners.spec.ts`, `web/e2e-online/**`, `web/e2e/answers/close-loop.spec.ts`;
  - build and CI: `web/package.json`, `ci/units.sh`, `.github/workflows/ci.yml`, `web/src/styles/**`.
- **No new stored data:** no new stored property, global, column or table.
- **No new text:** no new catalog key or text, and no new page string.
- **No new result band, and no timer, for a still-running run.**
- **Part 2's scope stays out:** no tool-call notification from `BridgeSink`, and no DW-454 reason wiring.
- **No CI change:** no CI job, group or unit is added or moved.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Stopped partway (DW-472) | request `done`, result `{total 3, resent 2, completed 2, failedAgain 0, skipped 1, interrupted 0, unreached 1}`, noun order/orders | key `result.stoppedPartway`; text "The resend stopped partway: I resent 2 of the 3 orders (2 went through), the next one couldn't be resent, and 0 more weren't tried. Nothing else was changed, and I won't resend the rest without a new approval."; partial, `triangle-alert` | none |
| Count-of-one form | the same with `total 4, skipped 2, unreached 2` | `notTried` 1, so the one form "...and 1 more wasn't tried..." | none |
| Order | `unreached` 1 together with `interrupted` 1; with the couldNotStart shape plus a reason; with `failedAgain` 1 and `skipped` 1 | `interrupted`; `couldNotStart`; `stoppedPartway` (not failedAndSkipped) | none |
| Older payload | `unreached` absent, 0, `null` or `"x"` | today's keys, unchanged | treated as 0 |
| Still running (DW-473) | incident `fixing`, request `executing` with no `result` | no result band; the card shows "Repairing and resending {n} {noun}…"; never `allThrough` | none |
| Tool note (DW-443) | the session's `tool_call` row, State `done`, ToolName `zz_send`, FinishedAt between the previous turn's CreatedAt and this turn's | that turn's Decide `turn` request carries `SystemNote` = TOOLNOTEHEAD + "\n- zz_send: done at " + ForMessage(FinishedAt) | none |
| Note: failed | State `failed` (Result `failed` or `interrupted`) | the line reads "failed at ..." | none |
| Note: exactly once | a call that finished before turn 2 was created | in turn 2's note only, not in turn 3's; the same note when turn 2 is asked again (Busy, broken retry, fresh after taint) | none |
| Note: not this session's | another session's row; a `fix` row; a `tool_call` row with no FinishedAt (pending, approved, executing) | no line; the note is "" when none is left | none |
| Note: read fails | the Ownership read returns an error status | note "", the error logged, the turn runs | logged, never stops the turn |
| Header (DW-530) | the floor at 320x180 (and at any stacked size where the header is over innerHeight/4) | `app-header` computed `position: static`; `--app-header-block-size` is `0px`; after a scroll to the bottom the header's bottom is at or above 0 | none |
| Header unchanged | 1000x800, 640x360 at scale 2 | sticky, as `layout.spec.ts` :451-477 asserts | none |
| Guide finish (DW-542) | the finish state at 640x360, scale 2 | `.finish` starts below `.row1` and spans `.main`'s content width | none |
| Empty chat (DW-543) | a fresh chat (welcome only) whose list overflows, at 1280x800 or a height where it overflows | list `scrollTop` 0, and `app-empty-chat` `.headline` top at or below the list's top; after the first send or arrival the list follows the bottom | none |
| A7 (DW-497) | A7's API checks | session from `signInOverHttp(page.request, ...)` and `/state` 200; the four assertions unchanged | none |

</intent-contract>

## Code Map

Line numbers are at the worktree head `2a84fb6b`.

**Page: result band (DW-472, DW-473)**
- `web/src/app/approvals/approval-view.ts`:
  - `resultView` :351-395 and its doc table :340-349. Add the branch after `couldNotStart` (:379) and before `failedAndSkipped` (:382).
  - `numberOf`/`textOf` are the existing readers.
  - `remaining` at :376 is not clamped. Leave it.
- `web/src/app/approvals/result-band.ts` :20-27 -- the DOM: `div.band[data-part="result"][data-tone]`, `span.text`. Unchanged.
- `web/src/app/approvals/approval-request-card.ts` :195-196, :422-426, and `web/src/app/incidents/incident-view.ts` `bandsOf` :379-389 and `fixingLineOf` :264-270 (the "Repairing and resending" line :46) -- consumers. Unchanged.
- `web/src/app/live/payloads.ts` :80 -- `unreached?: number`. Generated and read only.
- `web/scripts/catalog.mjs` :51-87 `LISTED_KEYS` -- add `'result.stoppedPartway'` right after `'result.couldNotStart'`, and make the header :17-18 say eight `result.*` texts.
  - Regenerate with `npm --prefix web run catalog`. That writes `web/src/app/msg/catalog.ts`, with the one form keyed on `notTried` taken from `Watch.cls` :235-249.
- `src/ocutalon/cls/OcuTalon/Watch/Notice.cls` :180-235 -- the server order and slots to mirror. Read only.
- Tests:
  - `web/scripts/approval-view.test.mjs` 'the result band (Story 6.4)' :309ff, with the helpers `result()` and `band()`; :317 pins "no result gives undefined, executing included".
  - `web/scripts/catalog.test.mjs`: `RESULT_KEYS` :67-76 (in `LISTED_KEYS` order), `length 8` :104 (becomes 9), the slot map :122-131, the render examples :189-216, `PAGE_ONE_FORMS` :219-227 and :472, and the `RESULTS` fixture :420-428, which every listed key needs (:644 iterates them).
  - `web/scripts/incident-view.test.mjs` -- the fixing-line tests (about :654).
  - `web/e2e/cards/approval-card.spec.ts` -- the request card's band test goes here as A11. `raise` :109-127 seeds a real request row (`seedApproval`, whose `over` can set the state) and publishes the incident (`publishIncident`, `incidentOf` :61) and the `approval` event (`sinkEvent`); all are imports from `support/iris.ts`, which is read only. The file's doc :19-30 lists its cases. The pattern for a band row is close-loop C2 (`web/e2e/answers/close-loop.spec.ts` :87, :252-279: a request row in state `done`, then a `resolved` incident payload whose request carries `result`). Read close-loop.spec.ts only; never edit it.

**Core: tool note (DW-443)**
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls`:
  - `Ask` :400-416 is where `request.SystemNote` gets set, for both the fresh and the continue branch.
  - `Recap` :625-649 and its parameters `RECAPHEAD` and so on (:82-91) are the pattern: code-written parameter texts and an `Ownership.Turns` read. `Turns` is ordered by CreatedAt and ID, which gives the previous turn.
  - The class doc :1-40 gains one bullet.
- `src/bridge/cls/OcuTalon/Bridge/Msg/Request.cls` :47-49 `SystemNote`, and `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` :483-492 `ChatInput`, which sends the note on fresh and continue turns. Read only.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` -- `Kind` :15, `State` :24, `ToolName`, `Result` :63, `FinishedAt` :66 (a UTC string of length 20, which compares as a string with `Turn.CreatedAt`), and the index `OwnerRefIndex` :87. Read only.
- `src/ocutalon/cls/OcuTalon/Data/Turn.cls` :30 `CreatedAt`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`:
  - `Rows`/`Statement` (kinds about :700-770; `approval` :762 shows the `ApprovalRequest` form, and the bind letters are `o` for the owner and `a` for an argument).
  - Public wrappers such as `Approval` :400 and `Approvals` :301.
  - Add the kind `finishedToolCalls` with a public `FinishedToolCalls(sessionRef, after, through, .sc)`: `SELECT a.ID FROM OcuTalon_Bridge_Data.ApprovalRequest a WHERE a.OwnerRef = ? AND a.Kind = 'tool_call' AND a.FinishedAt IS NOT NULL AND a.FinishedAt > ? AND a.FinishedAt <= ? ORDER BY a.FinishedAt, a.ID`.
- `src/ocutalon/cls/OcuTalon/Data/Time.cls` :88 `ForMessage(utc, now)`.
- Tests:
  - `src/ocutalon/cls/OcuTalon/Test/Core/ConversationTurns.cls` -- `Test.Core.DecideDouble` records `systemNote` (:53). `TestRecapFromTurnRows` :666 and `TestBrokenRetriedFresh` :427 are the patterns.
  - `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls` -- the list of every statement kind at :512 (the new kind joins it) and the probe `Test.Data.OwnershipProbe`. Seed approval rows with `Test.Data.Fixture.Approval(owner, incident, state, raisedAt, fields)`: call it, never edit it, with fields `{"Kind":"tool_call","ToolName":...,"Result":...,"FinishedAt":...}`.

**Layout (DW-530, DW-542, DW-543)**
- `web/src/app/header/header.ts`:
  - The stacked CSS :292-306 (`:host` sticky).
  - The `ResizeObserver` :411-421, which writes `HEADER_SIZE`.
  - The class doc :83-86.
  - `web/src/app/shared/layout-view.ts` :17 `LAYOUT_QUERIES.stacked`.
  - `web/src/styles/base.css` :78-83 reads `--app-header-block-size`. Read only.
- `web/src/app/guide/demo-guide.ts`:
  - The finish markup :164-181.
  - The `HEIGHT_QUERIES.compact` block :463-485 (`.prompt, .finish { flex: 1 }`).
  - The stacked block :486-497 (`.main { flex-wrap: wrap }`).
- `web/src/app/chat/chat-panel.ts`:
  - `atBottom` :272 and `fresh` :288.
  - The `ResizeObserver` :360-366.
  - `onScroll` :402-413, `onSent` :416-420, `scrollToBottom` :466.
  - The class doc :110.
  - `web/src/app/chat/empty-chat.ts` :48-54.
- Tests:
  - `web/e2e/floor/layout.spec.ts` -- `expectColumn` :425-480, with the runs at :483 (1000x800) and :539 (640x360 at scale 2).
  - `web/e2e/floor/guide.spec.ts` -- M9 :514-589 (the finish at :551-577).
  - `web/e2e/chat/chat.spec.ts` -- C11 :825-857 routes `/state` with `chat: []`, which is the pattern; `scrollTop` assertions are at :654-670 and :788.

**Flake (DW-497)**
- `web/e2e/cards/approval-card.spec.ts`:
  - A7 :348-368 calls `open(page)` :96-102, which is `loadedAfter` plus `signIn`.
  - Import `signInOverHttp` from `../sign-in/helpers` (:66) and `STATE` from `../support/api` (:14). Both are imports only.
  - The pattern is `web/e2e/session/session.spec.ts` :118-119.

**Runtime units:**
- Cards specs run in `live:cards` (CI group install-upgrade).
- Floor specs run in `live:floor` (shards).
- `chat/**` runs in `live:sign-in` (browser).
- Test.Core and Test.Data run in `shard:lane-b` (image).

## Tasks & Acceptance

**Execution:**
- [x] `web/src/app/approvals/approval-view.ts` -- read `unreached` with `numberOf`. Add the `result.stoppedPartway` branch after couldNotStart, with slots `{count, itemNoun, completed, resent, notTried}` as strings, like the other slots, and tone and icon as in Boundaries. Add the row to the doc table, plus one line: a run still going reaches the page as `executing` with no result, so the card's fixing line is its still-resending state (DW-473) -- DW-472, DW-473.
- [x] `web/scripts/catalog.mjs` then `npm --prefix web run catalog` (writes `web/src/app/msg/catalog.ts`) -- list the key after couldNotStart and update the header count -- DW-472.
- [x] `web/scripts/catalog.test.mjs` -- `RESULT_KEYS` gains the key in order (9). Add its slot types, a render example for each form, the `PAGE_ONE_FORMS` lists (:219, :472) with slot `notTried`, and a `RESULTS` fixture entry -- DW-472.
- [x] `web/scripts/approval-view.test.mjs` -- cover the matrix's first four rows: the text, the one form, notTried 0, each ordering case, and an absent, 0, null or non-number `unreached` -- DW-472.
- [x] `web/scripts/incident-view.test.mjs` -- pin the still-running row: a `fixing` incident whose request is `executing` with no result gives the fixing line and no band. If an existing case already pins exactly this, name it under Verification instead -- DW-473.
- [x] `web/e2e/cards/approval-card.spec.ts` -- new A11 (and the file doc's case list). Seed a request row in state `done`, then publish a `resolved` incident whose request result is `{total 3, resent 2, completed 2, failedAgain 0, skipped 1, interrupted 0, unreached 1, reason ''}`. The request card's `[data-part="result"]` reads the stopped-partway text (partial tone, `triangle-alert`) and not "had changed since the dry run". It creates and cleans its own rows -- DW-472 (real-runtime, Rule 3).
- [x] `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- add the `finishedToolCalls` kind and `FinishedToolCalls`. An empty `through` is an error. It keeps the class's owner-Ref checks -- DW-443.
- [x] `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls` -- add the kind to the :512 list. Add a row test: own vs another session, `fix` vs `tool_call`, no FinishedAt, both window bounds (the lower one exclusive, the upper one inclusive) and the order -- DW-443.
- [x] `src/ocutalon/cls/OcuTalon/Core/Conversation.cls`:
  - Add the parameters `TOOLNOTEHEAD` = "Approved tool calls that finished since the last message, as OcuTalon recorded them (not their output):", `TOOLNOTEDONE` = "- {tool}: done at {time}" and `TOOLNOTEFAILED` = "- {tool}: failed at {time}", filled by `$Replace`, not the catalog.
  - Add a `ToolNote(turn)` class method that finds the window from `Ownership.Turns` and reads `FinishedToolCalls`.
  - `Ask` sets `request.SystemNote` on both branches.
  - Add the class doc bullet.
  - DW-443.
- [x] `src/ocutalon/cls/OcuTalon/Test/Core/ConversationTurns.cls` -- cover the matrix's five note rows through the DecideDouble's `systemNote`, with real `ApprovalRequest` rows that the test seeds and removes. Assert the note holds no `ToolArguments` value. `TestSourceKeepsToItsBoundaries` stays green -- DW-443 (the integration AC: Conversation reads `Ownership.FinishedToolCalls` against real rows).
- [x] `web/src/app/header/header.ts`:
  - One `update()`, called by the existing observer and by a window `resize` listener that is removed on destroy. It toggles the host class `scrolls` when the layout is stacked and the host height is over `innerHeight / 4`, and then writes `0px` to `HEADER_SIZE`; otherwise it writes the height.
  - CSS `:host(.scrolls) { position: static; }` inside the stacked block.
  - Update the class doc.
  - DW-530.
- [x] `web/e2e/floor/layout.spec.ts` -- new case: open at a normal size, resize to 320x180, scroll to the bottom; `app-header` is `position: static`, its bottom is at or above 0, and the root `--app-header-block-size` is `0px`. Restore the viewport -- DW-530.
- [x] `web/src/app/guide/demo-guide.ts` -- `@media ${HEIGHT_QUERIES.compact} and ${LAYOUT_QUERIES.stacked} { .finish { flex-basis: 100%; } }` after the stacked block. `.prompt` is unchanged -- DW-542.
- [x] `web/e2e/floor/guide.spec.ts` -- in M9, once the finish shows, at 640x360 at scale 2, `.finish` top is at or below `.row1` bottom, and its width is within 2px of `.main`'s content width. Restore the viewport -- DW-542.
- [x] `web/src/app/chat/chat-panel.ts` -- the observer scrolls only when `this.atBottom && !this.fresh()`, and `onScroll` returns early while `fresh()`. Update the class doc -- DW-543.
- [x] `web/e2e/chat/chat.spec.ts` -- new case on C11's routed empty `/state`, at a size where the empty chat overflows (assert `scrollHeight > clientHeight` as the precondition): `scrollTop` 0 and the headline in view. Then the first send leaves the list at the bottom -- DW-543.
- [x] `web/e2e/cards/approval-card.spec.ts` -- in A7, replace `open(page)` with `signInOverHttp(page.request, user, password)` and `expect((await page.request.get(STATE)).status()).toBe(200)`. Its assertions are unchanged -- DW-497.

**Acceptance Criteria:**
- Given a resolved incident whose request result has `unreached` 1, when the signed-in page shows its card, then the result band reads `result.stoppedPartway`'s text and never `result.skipped`'s (DW-472; pinned by A11).
- Given a fix run still going after FixExecutor's 60-second wait (incident `fixing`, request `executing`, no result), when the page shows the card, then it shows the fixing line and no result band, so it never claims an outcome (DW-473).
- Given an approved tool call of the session that finished after one message, when the session's next message is turned, then the Decide `turn` request's `SystemNote` names the tool, done or failed, and the time in the instance's zone, and holds no tool arguments or output. The turn after it does not repeat it (DW-443, AD-30).
- Given a window of 320x180, when the stacked header would pass a quarter of the window, then it scrolls with the page, and at 1000x800 and 640x360 it stays sticky (DW-530, floor G4 as amended by U-202).
- Given the guide's finish state at 640x360, when it shows, then it takes the full width under the step row (DW-542).
- Given a fresh chat at 1280x800, when the page opens, then the welcome heading is not clipped and the list is at its top (DW-543).
- Given cards A7, when it runs, then it needs no browser page load and asserts the same four things (DW-497).
- Given the demo path, when `live:demo-path` runs, then it passes unchanged: no tool call in UJ-1, so the note is empty (default 1).

## Spec Change Log

## Review Triage Log

### 2026-11-02 - Review pass
- verdicts: 31 findings - high 0, medium 4, low 16, false 11, maybe-false 0
- findings:
  - `[medium]` `[patch]` (blind) a refused turn's window is lost: ToolNote took the lower bound from every Turn, refused ones included - a refused turn never reaches Ask, so its calls were named in no note. Fixed: the lower bound skips a refused Turn; TestToolNoteNamesTheFinishedCalls gained a refused turn between two asked ones.
  - `[low]` `[reject]` (blind) the note has no line or name-length cap - a user approves each call, so a window of dozens of calls is not reachable, and a cap adds a branch and a new model-facing text.
  - `[low]` `[patch]` (blind) a tool name holding `{time}` was rewritten by the second `$Replace`. Fixed: `{time}` is filled first, then `{tool}`; the test seeds `zz_{time}x`.
  - `[low]` `[reject]` (blind) every Ask reads all of the session's turns - the same read and cost shape as Recap; a one-row read would be a new Ownership kind for no observed cost.
  - `[low]` `[patch]` (blind) missing tests (the turn-not-among-its-session branch, the Turns failure, log clean-up, FinishedAt precision) - the not-among branch now has a test and a mutation; a Turns failure is not reachable without a fault injection, the log clean-up follows the existing probe-log pattern, and FinishedAt is system-written in one fixed form.
  - `[false]` `[reject]` (blind) the stopped-partway band hides the reason - the server's ResultKey order and slots are the contract (spec Always); the catalog text of `result.stoppedPartway` has no reason slot (U-182).
  - `[false]` `[reject]` (blind) "0 more weren't tried" reads awkwardly - the text is ruled (U-182) and pinned by the matrix's first row; a zero form is a new public text.
  - `[false]` `[reject]` (blind) `onScroll`'s early return leaves `lastTop` stale - the chat leaves the fresh state once and for good, and the first scroll afterwards sets `atBottom` from the position (at the bottom wins; a scroll up needs a lower top than the stale 0, which it cannot have).
  - `[low]` `[reject]` (blind) the header flips on the phone keyboard's innerHeight change - the quarter-of-the-window rule is the spec's (Decided 4); static there only loses stickiness and writes 0px, which is the wanted behaviour for a short window, and a hysteresis is a new rule.
  - `[low]` `[patch]` (blind) `iconPaths` could return no paths - fixed: it asserts at least one path; the cwd-relative read is the way the other e2e specs read sources.
  - `[medium]` `[patch]` (edge) same root cause as the refused turn's window above (patched once).
  - `[false]` `[reject]` (edge) a previous Turn with an empty CreatedAt makes the lower bound "0" - a Turn gets its CreatedAt when it is created (Fixture and the page's POST both set it); no reachable row has none.
  - `[low]` `[reject]` (edge) a call that commits after the first Ask in the turn's own second - FinishedAt is whole seconds, the upper bound is the turn's CreatedAt (a call in a later second goes to the next turn, once); the tie is the spec's rule (Decided 3).
  - `[medium]` `[patch]` (edge) ForMessage defaulted `now` to the clock, so the note's text changed across a local midnight between two asks of one turn. Fixed: `now` is the turn's CreatedAt; the tests pass the turn's time.
  - `[low]` `[patch]` (edge) same root cause as the `{time}` order above (patched once).
  - `[false]` `[reject]` (edge) ToolName is model-chosen text - the row's ToolName is the registered tool's name that the governance recorded, and the spec names it as an allowed field (AD-30); control characters are stripped.
  - `[low]` `[reject]` (edge) no line cap - same as the first cap finding.
  - `[false]` `[reject]` (edge) an unreadable FinishedAt gives an empty time - FinishedAt is written by FinishExecution in one form; an unreadable value is not reachable.
  - `[low]` `[reject]` (edge) the read loads every Turn - same as the all-turns finding.
  - `[false]` `[reject]` (edge) `atBottom` stale if the chat emptied while scrolled up - a chat never goes back to empty on a live page.
  - `[false]` `[reject]` (edge) C16 runs at 1280x560, not 1280x800 - the matrix says "at 1280x800 or a height where it overflows"; at 1280x800 the welcome panel fits, which the control assertion would show.
  - `[medium]` `[patch]` (gap) the `onScroll` early return and the arrival path were unpinned - C16 never scrolled the list and the first entry was a send. Fixed: C16 reloads the empty chat, scrolls the list down and up, lets a tall seeded turn arrive and asserts the list follows the bottom (with a control that it overflows); mutation recorded.
  - `[low]` `[reject]` (gap) ToolNote's Catch is never executed - it is a defensive branch for an unforeseen exception; the two reachable failures (an empty window end, a turn not among its session's) are pinned.
  - `[low]` `[patch]` (gap) several AC clauses had no `mutation:` line (the window's lower bound, the done/failed mapping, no tool arguments, the time, `unreached` non-numeric, the header's sticky half, DW-542 alone). Fixed: each was applied, seen red and reverted; the lines are in Verification.
  - `[low]` `[patch]` (gap) the new ConversationTurns tests did not collect their ApprovalRequest Refs, so OnAfterAllTests left them. Fixed: `Finished` and the two direct rows go through `Kept`, which adds the Ref to the cleaned Refs.
  - `[low]` `[reject]` (gap) the failure test deletes its log rows after its assertions - the rows are scoped by mark and SourceMethod, and OnBeforeAllTests' sibling probes clean the log in OnAfterAllTests.
  - `[low]` `[patch]` (gap) same root cause as the `{time}` order above (patched once).
  - `[low]` `[patch]` (gap) same root cause as the `iconPaths` guard above (patched once).
  - `[false]` `[reject]` (intent) DW-472's server-to-page path is not in A11 - the Lane A payload is read-only here; the AC sits at the page given the payload (the order is mirrored from ResultKey and pinned in approval-view tests).
  - `[false]` `[reject]` (intent) DW-543's AC names 1280x800 but C16 runs at 1280x560 - same as the size finding above.
  - `[false]` `[reject]` (intent) DW-443 is pinned at the Decide request, not through the model - the AC names the Decide `turn` request's SystemNote; ChatInput's carrying of the note is unchanged and pinned by Test.Bridge.Conversation.

## Design Notes

**Governing ADs (Rule 6):**
- **AD-12:** the page reads the generated payload shape (`payloads.ts`), which is one shape; a payload is never changed by its consumer.
- **AD-16:** the result semantics (couldNotStart, stoppedPartway, the 60-second "in progress").
- **AD-32:** producers never render; the page renders listed catalog keys through the generated `catalog.ts`, with count-of-one forms.
- **AD-30 and AD-10 3a:** the tool note is code-written: the tool, done or failed, and the time, never result text.
- **AD-31:** Core reads `OcuTalon.Bridge.Data` read-only through the ownership API.
- **AD-11:** the row is the truth, so the note reads row state, not events.
- **AD-33 and AD-29:** Lane B's files only; Lane A's payload, Fix, Watch and catalog classes are read.
- **AD-5:** no storage change.
- **AD-22:** tests on throwaways.

**Integration ACs (Rule 1).**
- Part 1 adds no service or shared component. `FinishedToolCalls` is a method on the existing `Ownership` module, and its consumer, `Conversation`, is in this story: the DW-443 AC exercises it against real `ApprovalRequest` rows.
- **Consumes:**
  - Story 30.5's `Requests[].Result.Unreached` and `result.stoppedPartway`;
  - Story 30.3's `FinishExecution` writes of `State`, `Result` and `FinishedAt` on `tool_call` rows;
  - `Bridge.Msg.Request.SystemNote` and `Adapter.Agent.ChatInput`.
- **Consumed-by:** none in part 1. Part 2 (below) reads nothing that part 1 adds.

**Extend, don't copy (Rule 2):**
- The stoppedPartway branch extends `resultView`.
- `finishedToolCalls` follows `Ownership`'s `Rows`/`Statement` kinds, like `approval`.
- `ToolNote` follows `Recap`: parameter texts plus an `Ownership` read.
- The header's `update()` extends the existing observer callback.
- A7 reuses `signInOverHttp`, as `session.spec.ts` does.

**Decided in-stage (unattended, small and reversible):**
1. **DW-473 band:** the page's still-resending state is the existing fixing line. No new band.
   - No key renders without counts: `result.stillResending` needs `completed` and `count`.
   - The page receives no counts while a run is still going (`Incident.cls` :144-147; the progress notice is record-only on web).
   - A count-free band would be new public text (a veto item) and would contradict pinned "no band before a result" behaviour (`approval-view.test.mjs` :317, `close-loop.spec.ts` :183, Epic 11's file).
   - The counts-so-far residual goes to the `deferred:` frontmatter, for the lead to route to Lane A.
2. **No local type:** `payloads.ts` already types `unreached`, so `api-types.ts` is untouched (direction 4).
3. **DW-443 lives in `Conversation.Ask`, with a stateless window, not in `BridgeSink`.** `BridgeSink` could only hand the note to the next turn through new storage (a veto item). The window gives each call to exactly one turn and is the same on every `Ask` for that turn.
   - The wording is model-facing and code-written (the parameters above), not public text.
   - A tie to the second between `FinishedAt` and a turn's `CreatedAt` goes to that turn, because the upper bound is inclusive.
4. **DW-530:** the JS rule (static plus `0px` scroll padding where the header is over a quarter) rather than a width or height media query. A query can't know the wrapped height (3 to 5 rows online), and it would leave up to 180px of scroll padding for a header that no longer covers anything (`base.css`, outside the footprint).
5. **DW-542:** the CSS is limited to compact height and stacked width; windows 1024px and wider keep one compact row.
6. **DW-543:** only the fresh (welcome-only) chat is exempt from bottom-follow; the first entry or send pins the bottom as before.
7. **DW-497:** fixed for A7, the one failing occurrence, which never used the rendered page. The shared `loadedAfter` (`floor.ts`, never edited) is unchanged. Another `open()` test failing the same way is an `occurrence` on DW-497's root cause, not a new entry.
8. **DW-443 window and refused turns (review):** the window's lower bound is the previous Turn that was not refused. A refused turn is never asked, so its calls go to the next turn that is, and each call still lands in exactly one note.
9. **DW-443 time (review):** `Time.ForMessage` is called with the turn's `CreatedAt` as `now`, so the note is the same each time the turn is asked, even across a local midnight.

**Ledger inbox (Rule 17):**
- DW-472: addressed (tasks 1-4 and 6).
- DW-473: addressed (task 1's doc line, task 5, Decided 1; residual deferred).
- DW-443: addressed (tasks 7-10).
- DW-530, DW-542, DW-543 and DW-497: addressed (tasks 11-17).
- Declined DW-454: it belongs to part 2.
  - Its visible surface is the tool-call `result` notice and the phone request card. Both need part 2's new catalog keys in the contended `Msg/Catalog/Core.cls`.
  - Its reason is saved after `approval.result` fires, so it rides on part 2's `decision.recorded` path.
  - The lead re-owns it to the part-2 story.

**Footprint extensions (Rule 11 (b); none is contended, checked against `origin/OCT-epic{11,12,13,15,30,40}`):**
- Server: `Core/Conversation.cls`, `Data/Ownership.cls`, `Test/Core/ConversationTurns.cls`, `Test/Data/Ownership.cls`.
- Web scripts and catalog: `web/scripts/{catalog.mjs,catalog.test.mjs,approval-view.test.mjs,incident-view.test.mjs}`, `web/src/app/msg/catalog.ts` (generated).
- E2E: `web/e2e/{cards/approval-card,floor/layout,floor/guide,chat/chat}.spec.ts`.

`new_units:` none (existing classes and specs only).

## Clarification Needed

**Split of Story 31.2 (direction 2; Rule 5 tier-2; the lead inserts the children).**

The story's main AC cannot be planned without two rulings that a stage may not take:
- **The catalog file is contended.** Tool-call notices need new Lane B catalog keys: no key fits a tool-call request or its result, the `result.*` prefix is Lane A's, and `Test/Msg/Catalog.cls` enforces one class per prefix. Lane B's keys live in `Msg/Catalog/Core.cls`, which Epic 40 (`origin/OCT-epic40`) also changes, along with `Test/Msg/Catalog.cls`'s key counts.
- **The texts are not in the UX.** Only the card's "Run {tool} on {server}" and "No dry run is available for this tool. Approving runs exactly this call once." are (EXPERIENCE.md :946), so the result texts are new public text (a veto item).

So the story is planned as two children:
- **Part 1, this spec** (keeps the key `31-2-…`). Retitling is the lead's call; a suggested title is "A fix result says how far it got, and the next turn knows a tool call finished".
  - ACs: the eight above.
  - DW entries: 472, 473, 443, 530, 542, 543, 497.
- **Part 2, a new Story 31.5,** "A tool call's approval request reaches the phone with Approve and Reject (notices)".
  - AC: Story 31.2's AC verbatim, without its spent "until Story 30.3 merges" clause.
  - Its tests use the real replay path (`Test.Bridge.Approval` `TestReplayReachesTheLiveStream` :1632 is the model; its private `HeldCall` raises with `ProbeSink`, so `approval.raised` needs a fixture event).
  - DW entries: DW-454.

  It needs, before it is planned:
  - **Q1 (where the keys live).**
    - (a) Recommended: append them to `Core.cls`'s Entries and its count in `Test/Msg/Catalog.cls`, with the orchestrator serializing against Epic 40.
    - (b) A new class `Msg/Catalog/Tool.cls`, plus `Msg/Catalog.cls` `CLASSES` and `Test/Msg/Catalog.cls` :76-120. These edits sit next to Epic 40's count lines.
  - **Q2 (the texts, a veto item).** Proposed:
    - `toolCall.request`: "Run {tool}. No dry run is available for this tool. Approving runs exactly this call once."
    - `toolCall.done`: "{tool} ran once at {time}."
    - `toolCall.failed`: "{tool} didn't finish at {time}. I won't run it again without a new approval."
    - `toolCall.failedWithReason`, for DW-454: "{tool} didn't run: {reason} I won't run it again without a new approval."
    - Answered statuses: reuse `answered.approved`, `answered.rejected` and `answered.expired`.
  - **Q3 (the result on the phone).** Keep Story 6.4's rule, a new message with no buttons (recommended, as for fixes), or edit the request in place, as epic-31-context's UX line says ("and later its result").

  Known design points for its plan:
  - `Delivery.FindByApproval` takes the newest row, so the answered edit must not land on the result message; read the row state, not the event order (30.3).
  - DW-454's sentence is saved after `approval.result` fires, so it rides on `decision.recorded`.
  - An old held row has no phone request message.
  - No web chat card exists for a `tool_call` (the card's reason reaches the state and rail through `Live.Payload.Approval.FromRow`, which is Lane B's and not contended).

Part 1 needs no answer: it is ready for development as written.

## Verification

Use these variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=31 stage=implement'`, with tags `e31s2i` (fresh) and `e31s2iw` (warm).
- Pass `timeout: 600000` on every call.
- Make one test-runner call per message, and never re-submit a call after a client-side timeout.
- Before any browser unit, run `ci/iris.sh build`, because the bundle is not rebuilt by itself (Rule 21).
- No real model key, ever.

**Commands:**
- (loop) `npm --prefix web run catalog` then `node web/scripts/catalog.mjs --check` -- expected: `catalog.ts` is current.
- (loop) `npm --prefix web test` -- expected: every `scripts/*.test.mjs` passes, `catalog`, `approval-view`, `incident-view` and `chat-announcements` included.
- (loop) `npm --prefix web run lint` -- expected: exit 0.
- (loop) `OCUTALON_RUN_TAG=e31s2iw ci/warm.sh up` once. Then run each of these on its own call; each is expected to print `CLASS ... passed`:
  - `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e31s2iw ci/iris.sh class OcuTalon.Test.Core.ConversationTurns`
  - `... class OcuTalon.Test.Data.Ownership`
  - `... class OcuTalon.Test.Bridge.Conversation` (the note reaches `ChatInput`; unchanged)

  At the stage's end, also after a failure: `OCUTALON_RUN_TAG=e31s2iw ci/warm.sh down`.
- (once) `OCUTALON_RUN_TAG=e31s2i ci/iris.sh build` -- expected: the bundle is rebuilt with the page changes.
- (once) `OCUTALON_RUN_TAG=e31s2i ci/iris.sh live cards` -- expected: passes, with A11 and A7.
- (once) `OCUTALON_RUN_TAG=e31s2i ci/iris.sh live floor` -- expected: passes (`layout.spec.ts` with the new case, guide M9; Firefox and WebKit `@browsers` cases); about 5 minutes.
- (once) `OCUTALON_RUN_TAG=e31s2i ci/iris.sh live sign-in --part 1/3`, then `--part 2/3`, then `--part 3/3`, one per call -- expected: every part passes, the new chat case included (about 200 to 310 s each, as measured in 31.1).
- (once) `OCUTALON_RUN_TAG=e31s2i ci/iris.sh live answers` -- expected: passes (close-loop C1 to C3 bands unchanged).
- (once) `OCUTALON_RUN_TAG=e31s2i ci/iris.sh live demo-path` -- expected: passes (UJ-1).
- (once) Fresh `shard lane-b@Core,Data`, forward then `--reverse`, one per call (Rule 19) -- expected: every class passes.
- (once) `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-storage.sh` and `bash docker/tests/test-ci-config.sh`, one per call -- expected: all pass (ASCII escapes, no local paths, no storage change, shard coverage).
- (once) `OCUTALON_RUN_TAG=e31s2i ci/iris.sh teardown`.

**Shared surfaces:**
- `Ownership`'s list of statement kinds, pinned at `Test/Data/Ownership.cls` :512; the new kind joins it.
- The Decide turn request's `SystemNote`: search `Test/Core` and `Test/Bridge` for assertions that it is empty, and confirm that none of them seeds a finished `tool_call` row for the same session inside a turn's window (each test's sessions are its own, so they stay true).
- The web catalog's listed keys, `RESULT_KEYS` count and `PAGE_ONE_FORMS` list (`catalog.test.mjs`).
- The result-band decision table (`approval-view.test.mjs`).
- The header's sticky set and `--app-header-block-size` (`floor/layout.spec.ts` :451-477).
- The guide's compact layout (`floor/guide.spec.ts`).
- The chat's scroll position (`chat/chat.spec.ts` :654-670, :788).

Every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to apply** (the implement stage writes `mutation: <change> → <red test>` next to each):
- DW-472: drop the stoppedPartway branch → the `approval-view.test.mjs` stoppedPartway case and A11 go red.
  - mutation: `unreached > 0` branch of `resultView` made never true -> `approval-view.test.mjs` 'is the partial band with triangle-alert for a run that stopped partway ...' and 'puts stopped partway after interrupted ...' red, and cards A11 red (live:cards, bundle rebuilt with the mutation); reverted byte-identically.
  - mutation: `unreached` read as `result.unreached ? 1 : 0` (a non-numeric value counts as 1) -> `approval-view.test.mjs` 'is the partial band with triangle-alert ...' and 'reads an absent, 0, null or non-numeric unreached as 0 ...' red; reverted byte-identically.
- DW-473: give an executing request with no result a band → task 5's pin (and `approval-view.test.mjs` :317) goes red.
  - mutation: `resultView` reads an executing request with no `result` as `{}` -> `approval-view.test.mjs` 'is undefined for a request with no result ...' and `incident-view.test.mjs` 'show no band for a fix run that is still going ...' red; reverted byte-identically.
- DW-443 (a): `Ask` sets no `SystemNote` → the ConversationTurns note case goes red. (b) Make the lower bound inclusive → the `Test.Data.Ownership` bounds case goes red (a row whose FinishedAt equals the lower bound). (c) Drop the `OwnerRef` bind → the other-session case and the `Test.Data.Ownership` row test go red.
  - mutation (a): `Set request.SystemNote = ""` in `Ask` -> `Test.Core.ConversationTurns` TestToolNoteNamesTheFinishedCalls, TestToolNoteIsTheSameOnEveryAsk and TestToolNoteReadFailureNeverStopsTurn red; reverted byte-identically, class green again on the same warm stack.
  - mutation (b): `a.FinishedAt >= ?` in the `finishedToolCalls` statement -> `Test.Data.Ownership` TestFinishedToolCalls ('the lower bound is exclusive ...', 'a window whose bounds are one time is empty', 'a window after the newest is empty') red; reverted byte-identically.
  - mutation (c): `a.OwnerRef = ?` and its bind removed from the statement (binds "aa") -> `Test.Data.Ownership` TestFinishedToolCalls ('... other session's or instance request', 'another session reads its own only') and `Test.Core.ConversationTurns` TestToolNoteNamesTheFinishedCalls, TestToolNoteIsTheSameOnEveryAsk red; reverted byte-identically, both classes green again on the same warm stack.
  - mutation (d): `Set after = ""` instead of advancing the lower bound -> `Test.Core.ConversationTurns` TestToolNoteNamesTheFinishedCalls (the third and the second turn's note) red; reverted byte-identically.
  - mutation (e): the line chosen by `call.Result = "done"` instead of `call.State = "done"` -> TestToolNoteNamesTheFinishedCalls red (a failed row whose Result is done); reverted byte-identically.
  - mutation (f): `call.ToolArguments` appended to each line -> TestToolNoteNamesTheFinishedCalls ('and holds no tool arguments') and TestToolNoteIsTheSameOnEveryAsk red; reverted byte-identically.
  - mutation (g): `ForMessage(call.FinishedAt)` without the turn's CreatedAt -> TestToolNoteNamesTheFinishedCalls and TestToolNoteIsTheSameOnEveryAsk red (the time text depends on the clock); reverted byte-identically.
  - mutation (h): the refused-turn skip removed from the lower bound -> TestToolNoteNamesTheFinishedCalls red; reverted byte-identically.
  - mutation (i): `{tool}` filled before `{time}` -> TestToolNoteNamesTheFinishedCalls (the `zz_{time}x` call) red; reverted byte-identically.
  - mutation (j): the turn-not-among-its-session's error removed -> TestToolNoteReadFailureNeverStopsTurn red; reverted byte-identically.
- DW-530: drop `:host(.scrolls)` → the new layout case goes red.
  - mutation: `:host(.scrolls) { position: static; }` removed from `header.ts` -> `floor/layout.spec.ts` 'G4: at 320x180 a header over a quarter of the window scrolls with the page' red (toHaveCSS position static); reverted byte-identically.
  - mutation (sticky half): `const scrolls = this.layout.stacked();` (no quarter-of-the-window test) -> `floor/layout.spec.ts` 'G4: at 1000x800 ...', 'at 200%: ... G4' and 'at 200%: ... G5' red (live:floor, applied together with the DW-542 mutation below; 4 failed, 103 passed); reverted byte-identically.
- DW-542: drop the `.finish` flex-basis rule → M9's new assertion goes red.
  - mutation: the `${HEIGHT_QUERIES.compact} and ${LAYOUT_QUERIES.stacked}` block removed from `demo-guide.ts` -> `floor/guide.spec.ts` M9 red (applied together with the DW-530 mutation in one live:floor run: exactly these two cases failed, 105 passed); reverted byte-identically. The viewport is 640x360 at the default device scale: CSS pixels, so the layout is the same as at scale 2.
  - mutation (alone, in the same live:floor run as the sticky-half mutation): only `floor/guide.spec.ts` M9 is red among the guide cases, with the layout cases red for the other mutation; reverted byte-identically.
- DW-543: drop `!this.fresh()` → the new chat case goes red.
  - mutation: `!this.fresh()` removed from the ResizeObserver callback of `chat-panel.ts` -> `chat/chat.spec.ts` C16 red (live:sign-in --part 1/3: scrollTop expected 0, received 252; 89 passed); reverted byte-identically.
  - mutation (onScroll): the `if (this.fresh()) return;` in `onScroll` removed -> `chat/chat.spec.ts` C16 red alone (live:sign-in --part 1/3: after an arrival the list follows the bottom, expected <= 24, received 599; 89 passed); reverted byte-identically.
- DW-497: none. It removes a dependency; the evidence is A7 passing without `open()`.

**Manual checks:**
- `git status --short` shows no path from the Never list.
- `payloads.ts` and `api-types.ts` are byte-identical.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The page shows a run that stopped partway as `result.stoppedPartway` (DW-472); a run still going keeps the fixing line and no band (DW-473, pinned; counts-so-far deferred). `Conversation.Ask` puts a code-written `SystemNote` on the turn request from the session's own finished `tool_call` rows in the turn's window, through the new `Ownership.FinishedToolCalls` (DW-443). The stacked header scrolls away where it passes a quarter of the window (DW-530), the guide's finish state takes full width at compact stacked sizes (DW-542), the empty chat opens at its top (DW-543), and cards A7 signs in over HTTP (DW-497).

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls`: `ToolNote`, the three `TOOLNOTE*` parameters, `Ask` sets the note.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: kind `finishedToolCalls` and `FinishedToolCalls`.
- `src/ocutalon/cls/OcuTalon/Test/Core/ConversationTurns.cls`, `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls`: note and row tests.
- `web/src/app/approvals/approval-view.ts`, `web/scripts/catalog.mjs`, `web/src/app/msg/catalog.ts` (generated): the stoppedPartway branch and listed key.
- `web/src/app/header/header.ts`, `web/src/app/guide/demo-guide.ts`, `web/src/app/chat/chat-panel.ts`: DW-530, DW-542, DW-543.
- Tests: `web/scripts/{approval-view,catalog,incident-view}.test.mjs`; `web/e2e/cards/approval-card.spec.ts` (A11, A7), `web/e2e/floor/{layout,guide}.spec.ts`, `web/e2e/chat/chat.spec.ts` (C16).
- Footprint extensions beyond the spec's list (Rule 11 (b), none contended): `web/scripts/ux-strings.test.mjs` (the ruled U-182 text of `result.stoppedPartway`), `web/scripts/floor-sources.test.mjs` (a leading height query may precede a width band), `web/scripts/playwright-projects.test.mjs` (cards A2 to A11, 20 cases).

**Review.** 31 findings (high 0, medium 4, low 16, false 11). Patches applied: the refused-turn window, `{time}` in a tool name, the `now` of the note's time, the not-among-turns test, the `iconPaths` guard, C16's scroll-then-arrival segment, the test Refs clean-up, and the missing mutation lines. Rejected with reasons: see the Review Triage Log. Deferred: none new (the DW-473 residual stays).

**Follow-up review recommendation.** `followup_review_recommended: true`: three medium entries were patched. The unverified risk is the refused-turn skip in `ToolNote`: it is pinned by a unit fixture with a refused Turn, not by an online-demo refusal end to end.

**Verification (final tree).**
- (loop) catalog current; `npm --prefix web test` 1181 of 1181; lint exit 0; warm `ConversationTurns`, `Data.Ownership` and `Bridge.Conversation` passed.
- (once, fresh tag e31s2i, bundle rebuilt after the last patch): `live cards` 20 passed (A7, A11); `live floor` 107 passed; `live sign-in` parts 1/3 90, 2/3 76, 3/3 81 passed; `live answers` 21 passed; `live demo-path` 12 passed, 9 skipped as before; `shard lane-b@Core,Data` forward and `--reverse` 41 classes each passed; `test-boundaries`, `test-class-rules`, `test-storage` and `test-ci-config` passed. No known flake occurred, so no rerun.
- Mutations: each recorded under Verification was applied, seen red and reverted byte-identically (`cmp`). The warm and fresh stacks were torn down.

**Residual risks.** `docker/tests/test-cards.sh` still words its pass line as "A2-A10". `FinishedToolCalls` binds "0" for an empty lower bound because an empty string binds as NULL (documented on the method).
