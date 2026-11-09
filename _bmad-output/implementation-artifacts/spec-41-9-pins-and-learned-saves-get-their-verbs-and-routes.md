---
title: "Story 41.9: Pins and learned saves get their verbs and routes"
type: 'feature'
created: '2026-11-09'
status: 'in-progress'
baseline_revision: 'adb697c77de7cd479f63d237e4a0586c4851562f'
baseline_commit: 'adb697c77de7cd479f63d237e4a0586c4851562f'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 41.8 named `PinMemory` and `UnpinMemory`, but no class, route or gate entry exists. The web has no way to list, search, pin or forget a memory: `ForgetMemory` is accepted from origin `tool` only, and Web.Api has no memory-item routes. The Memory card (41.13) and core memory (41.12) need both.

**Approach:** Add the two verb classes (sibling `ForgetMemory`). `CommandsIn` routes them to `MemoryOps` from `web_user` only, and also accepts `ForgetMemory` from `web_user`. `Web.Api` gains `GET /v1/memory/items`, `POST`/`DELETE /v1/memory/:ref/pin` and `DELETE /v1/memory/items/:ref`. They are built like the precedent routes: the session comes from `Ownership.SessionRef`, the submit goes through `SubmitMemory` with origin `web_user`, and they sit behind the AD-13 envelope. The spine gets three additive lines.

## Boundaries & Constraints

**Always:**
- No route takes a `SessionRef` from the client. The session is `Ownership.SessionRef`'s (AD-4).
- Write routes rely on the existing `OnPreDispatch` envelope: `Content-Type: application/json`, `X-OcuTalon-Request: 1` and a same-site `Origin` (AD-13). No route bypasses it.
- Error bodies reuse existing `Web.Api` codes and texts. The one new text is `over_cap`, quoted from EXPERIENCE.md:1054.
- `ForgetMemory` from origin `tool` keeps its bridge-context check (`CommandsIn.cls:88`).
- Every test added or changed passes on a fresh environment, in either order, and creates and removes its own rows.

**Never:**
- Edit a Lane A file: `Memory/**`, `Memory.cls`, `Tools/**`, `Agent/**`, `Data/Memory.cls`, `Test/Memory/**`, `Test/Tools/**`. Lane A test helpers such as `Test.Memory.Fixture.Store` may be called but not edited.
- Handle a pin in `MemoryOps`, or add the cap. That is 41.12's work.
- Touch `web/src/**` or the card. That is 41.13's work.
- Add a `Source` property to `SaveMemory`, or accept `system` origin. See Design Notes.
- Edit a contended path: `Mcp/**`, `Bridge/Adapter/**`, `Msg/Catalog/**`, `Test/Msg/Catalog.cls`, `Production.cls`, `ci/units.sh`, `src/short-names.tsv`, `release/**`, compose files, AD-16 or AD-31.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected | Error |
|---|---|---|---|
| List | `GET /v1/memory/items`, no `q` or a blank `q` | 200 `{"items":[{ref,text,savedAt,source,pinned}],"total":n}` from `Memory.List`: newest 20 of the session's rows | a failed read gives 500 server_error |
| Search | `GET /v1/memory/items?q=vpn` | 200 with the same shape from `Memory.Search(session, q, 5)`; `total` is the item count | a failed search or embed gives 500 server_error |
| Pin / unpin | `POST`/`DELETE /v1/memory/:ref/pin` | submits `PinMemory`/`UnpinMemory` `{MemoryRef, SessionRef}` with origin web_user. Ok gives 200 `{"result":"done"}` | not_found 404, over_cap 409, not_built 501, else 500 |
| Forget | `DELETE /v1/memory/items/:ref` | submits `ForgetMemory` with origin web_user. forgotten gives 200 `{"result":"done"}` | not_found 404, not_built 501, else 500 |
| Another session's ref | forget with a ref of another session's real row | the real `MemoryOps` answers not_found, the route gives 404, and the row is kept | none |
| Gate | `PinMemory`/`UnpinMemory` from any origin but web_user, including from inside a bridge context | not_allowed, nothing sent (tool: "That can't be done from the chat. Nothing was changed.") | none |
| Pin before 41.12 | real `MemoryOps` has no handler | CommandsIn `failed`, the route gives 500 server_error (inference; Task 0 measures it) | Ens logs the unhandled request |
| No CSP session | any new route | 500 server_error, nothing submitted | none |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless given in full. Line numbers are as of `95ab8336`.

- `Msg/Command/PinMemory.cls`, `UnpinMemory.cls` (new): `Property MemoryRef As %String(MAXLEN = 22)`. Copy `ForgetMemory.cls`' form and let the compiler write the storage. Doc comment: owner MemoryOps (handled from Story 41.12), origin web_user only.
- `Msg/Command/ForgetMemory.cls:1-2`: the comment says origin tool or web_user.
- `Core/CommandsIn.cls`: in Routes (205-212), `ForgetMemory` origins become `"tool,web_user"`. Append `PinMemory` and `UnpinMemory` → `MemoryOps`, `"web_user"`. Not in `TOOLVERBS` (38). Update the comments at 10-11 and 179-183.
- `Web/Api.cls`:
  - UrlMap: after 214, add `GET /v1/memory/items MemoryItems`, `POST /v1/memory/:ref/pin PinMemory`, `DELETE /v1/memory/:ref/pin UnpinMemory` and `DELETE /v1/memory/items/:ref ForgetMemory`.
  - Add `Parameter MESSAGEOVERCAP`.
  - New methods after `Notes` (1745-1773). Extend `ForgetPrecedent` (1717-1740), which submits through `SubmitMemory` (1782). Share one private outcome mapper among the three write routes instead of copying it.
  - `q` is trimmed and capped at 2,000 characters.
  - Each item is `Memory.Row` without `origin`: `{ref, text, savedAt, source, pinned}`.
  - Update the header (68-76) and `SubmitMemory`'s comment.
- `Memory.cls:53, 129` `Search` and `List` are read only: owner-scoped (AD-21), already returning `source` and `pinned`.
- `Memory/Ops.cls:41-51, 128-155` is read only. Its MessageMap has no pin. `OnForget` answers not_found for another session's ref (138).
- `Test/Core/CommandsStep3.cls`:
  - XData Contracts (206) gains the two classes.
  - `TestOrigins` (50) adds both verbs (web_user only) and ForgetMemory's `tool,web_user`.
  - `TestContextOwnSessionOnly` (84): a pin inside a context is refused.
  - Update the header.
- `Test/Core/CommandsStep3Probe.cls:20-24`: dispatch by class with `$Case` (SaveMemory→OnSave, ForgetMemory→OnForget, otherwise error 5001), so that a pin is never sent to OnForget.
- `Test/Web/MemoryApiProbe.cls:13-31`: record `MemoryRef`. A new mode `"real"` sets Origin web_user and answers a shadow `Test.Core.CommandsStep3Probe`'s `OnProcessInput`, so the real gate and the real `MemoryOps.OnForget` answer.
- `Test/Web/MemoryApi.cls`:
  - Add `TestItems`, `TestPin`, `TestForgetMemory` and `TestForgetOtherSessionReal`. The last stores rows through `Test.Memory.Fixture.Store`, with a named skip when `Fixture.OnImage()` is 0.
  - Extend `TestNoSessionIs500` and `Call` (291) with the new methods.
- `Test/Web/Api.cls:952-956` `TestRoutes`: 32 → 36 routes, inserted in map order.
- `web/e2e/api/memory.spec.ts`: over real HTTP:
  - signed out, the four routes are 401;
  - `GET /memory/items` is 200 `{items,total}`;
  - `DELETE /memory/items/zzunknownref` with the envelope is 404 not_found;
  - the same without `X-OcuTalon-Request` is refused as the other write routes are.
- Spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: the lines under Design Notes.

## Tasks & Acceptance

**Execution:**
0. Measure on the warm stack: submit a `PinMemory` (origin web_user, a fixture session) through `Commands.Submit` to the running production. Record the Outcome under Verification, and fix the matrix row and Design Notes if it is not `failed`.
1. Create the verb classes and make the `ForgetMemory` comment edit. Then the `CommandsIn` routes and comments.
2. Update `Test/Core/CommandsStep3.cls` and its probe.
3. Write the `Web/Api.cls` routes, the mapper and `MESSAGEOVERCAP`.
4. Update `Test/Web/MemoryApiProbe.cls`, `Test/Web/MemoryApi.cls` and `Test/Web/Api.cls` `TestRoutes`.
5. Extend `web/e2e/api/memory.spec.ts`.
6. Insert the spine lines from the bottom up and run `memlog.py append --type decision --text "Story 41.9: PinMemory/UnpinMemory routed web_user-only; ForgetMemory also from web_user; memory items, pin and forget routes"`. Then run `lint_spine.py`.
7. Search the test trees for the old shapes: `"origins": "tool"}` for ForgetMemory, the 32-route list, and `ForgetMemory` "tool only" pins. Update each one.

**Acceptance Criteria:**
- AC 1 (AD-1): Given the gate, when `PinMemory` or `UnpinMemory` arrives from each origin of `Msg.Enum ORIGIN`, then only web_user reaches `MemoryOps`. Origin tool, including web_user inside a bridge context, is not_allowed with the chat sentence and nothing is sent. Neither verb is in `TOOLVERBS` (`CommandsStep3:TestOrigins`, `TestContextOwnSessionOnly`).
- AC 2 (AD-21, moved): Given the save-memory AC for origin `system`, when this story is implemented, then this story leaves `SaveMemory` and its origins unchanged: the Planner moved that AC to Story 41.11 (planner-2026-11-09-41.9 item (d); epics.md Story 41.11, `[MOVED 2026-11-09 from Story 41.9]`), and 41.8's rule that code decides the source stands.
- AC 3 (AD-4): Given a CSP session, when `GET /v1/memory/items` is called with and without `q`, then it answers only that session's rows with `source` and `pinned`, and never another session's. When the pin routes are called, they submit `PinMemory`/`UnpinMemory` with the session's `SessionRef` and map every outcome (`MemoryApi:TestItems`, `TestPin`, and the e2e spec).
- AC 4 (AD-1, AD-4, AD-13): Given `DELETE /v1/memory/items/:ref`, then it submits `ForgetMemory` with origin web_user for the session, and maps forgotten 200, not_found 404, not_built 501 and the rest 500. Another session's real row answers 404 not_found through the real `MemoryOps` and is still stored. Without the envelope, it is refused before anything is submitted (`MemoryApi:TestForgetMemory`, `TestForgetOtherSessionReal`, and the e2e spec). The spine holds the AD-1 note, and `lint_spine.py` stays at its baseline (`"ok": false`, exactly 10 low `placeholder` findings, nothing new).

### Review Findings

Code review 2026-11-09 (full mode; layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 23 rows, 15 entries). Verdict: `in-progress`.

- [ ] [Review][Decision] HIGH: `GET /v1/memory/items` is 500 for every real signed-in user — measured on the warm stack over HTTP as the README account (`/state` and `/memory/precedents` 200; `/memory/items` and `?q=vpn` 500). The console log gives the causes: the list's `Memory.List` prepares with the SQL privilege check ("The memories could not be counted: User ocutalon is not privileged for the operation"), and the search's embedding needs `%Service_EmbeddedPython:U` ("<OBJECT DISPATCH>Embed+5^OcuTalon.Memory.Embedder.1 *Resource %Service_EmbeddedPython:U is required"). AD-13 allows unchecked prepares only in `Session.ForUser`, `Live.Event.Since` and `Ownership.Rows`, and the spine (L107, AD-4) lets the web layer read `Data.Memory` only through the ownership API. So the spec's read path (`Memory.List`/`Search` called from `Web.Api`) cannot work in the CSP process. The unit tests passed because they run as a privileged user. The e2e list test (left to CI) would go red. [Web/Api.cls ReadMemories] — fix-risk high (a privilege or AD choice); in-story; escalated as `## Clarification Needed` (Rule 4).
- [ ] [Review][Patch] MED: no real-HTTP test lists a seeded memory row (the five-member item, `pinned` a JSON boolean) or forgets one with 200 through the running production. The e2e spec checks only top-level keys and a 404. [web/e2e/api/memory.spec.ts] — fix-risk low; in-story; left for the rework iteration together with the HIGH (Rule 3).
- [ ] [Review][Patch] MED: the "a failed search or embed gives 500" matrix row has no pinning test. The product's `ReadMemories` search branch never runs failing: the probe's `fail` mode replaces the method. [Web/Api.cls ReadMemories; Test/Web/MemoryApi.cls] — fix-risk low; in-story; left for the rework iteration, because the search path depends on the HIGH's ruling (Rule 19).
- [x] [Review][Patch] MED: `TestWriteRoutesBehindEnvelope`'s "and nothing was submitted" could not fail, because only `OnPreDispatch` runs and nothing reaches `SubmitMemory`. Removed, and the doc comment now names the `continue` flag that is the real evidence (Rule 19). [Test/Web/MemoryApi.cls]
- [x] [Review][Patch] MED: `MemoryApi.PreDispatch` was the fourth copy of the OnPreDispatch runner (`DocumentsApi`, `SettingsApi`). Rule 2: it now calls the new shared `Test.Web.Api.PreDispatchOf` beside `Capture`/`Collect`. The remaining two copies are out of this story's footprint and routed (DW-1028, owner burndown). [Test/Web/MemoryApi.cls, Test/Web/Api.cls]
- [x] [Review][Defer] MED: `MemoryItemCommand`'s submit-and-map tail near-copies `ForgetPrecedent`'s and `MarkNoise`'s. Unifying them would edit shared `Web/Api.cls` lines, which the Epic 35 contention ruling forbids in this story. [Web/Api.cls] — deferred: routed DW-1027, owner burndown (a Rule 2 copy forced by the ruling).
- [x] [Review][Defer] MED: the pin tests stop at a probe. `CommandsStep3Probe` answers a pin with 5001, and `TestPin`'s real mode pins 500, so both stay green after 41.12 adds the handler. `Memory/Ops.cls:19` still says tool only. — deferred: routed DW-1029, owner 41-12.
- [x] [Review][Defer] MED: the items route cannot back 41.13's Pinned tab: newest 20 only, with no pinned filter, paging or used-token figure. — deferred: routed DW-1030, owner 41-13.
- [x] [Review][Defer] MED: item search embeds on every GET with no allowance, so it can fill the shared Embedder queue. It is unreachable today (see the HIGH). — deferred: decision-pending DW-1031, owner burndown.
- [x] [Review][Patch] LOW: the `Web.Api` class header said over_cap 409 was for "a pin only". It now says a pin or an unpin, and 500 for a forget, as the code does. [Web/Api.cls header]
- [x] [Review][Patch] LOW: stale test headers corrected: the `MemoryApi` intro (the 41.9 routes, the `ReadMemories` seam, real mode, memory-row clean-up), `MemoryApiProbe`'s first sentence (three seams), and `TestContextOwnSessionOnly`'s comment (the pin refusals). [Test/Web/MemoryApi.cls, MemoryApiProbe.cls, Test/Core/CommandsStep3.cls]
- [x] [Review][Patch] LOW: `TestItemsSearch` and `TestForgetOtherSessionReal` ignored `Fixture.Prepare`'s status. Both now assert it. [Test/Web/MemoryApi.cls]
- [x] [Review][Patch] LOW: AC 2 and AC 3's pin half had pinning tests with no `mutation:` line. Both mutations were applied, observed red and reverted; the lines are under Verification. The e2e spec's mutation cannot be shown locally (CI only).

Rejected / closed at emission:
- `[low]` `wontfix-theoretical`: `/v1/memory/:ref/pin` also matches `/v1/memory/items/pin`, `/precedents/pin` and `/notes/pin`. The earlier triage line said these answer 404; until 41.12 they reach the pin verbs with refs `items`, `precedents` or `notes` and answer 500 (failed), and after 41.12 they answer not_found. reopen_if: a memory ref can be user-chosen, or a fixed segment under `/v1/memory/` is named `pin`.
- `[low]` reject (edge): a 2,000-character cut of `q` can split a surrogate pair. That needs a query of over 2,000 characters with an emoji exactly at the boundary, and the fix adds a guard.

## Spec Change Log

- 2026-11-09 (planner-2026-11-09-41.9, Contest Planner under the owner's delegation, relayed by the orchestrator): the spec-gate items ruled. (a) PUBLIC TEXT approved verbatim: 409 `over_cap` "That would go over the 1,000-token limit. Unpin something first." (EXPERIENCE.md:1054). (b) Security as listed under Design Notes (AD-13 envelope in `OnPreDispatch`, server-side `Ownership.SessionRef`, `MemoryOps`' row-owner check, no new role): approved, no veto. (c) The three additive spine lines (AD-1 note, AD-33 cross-area row, REST row, marker `[ADDED 2026-11-09, Story 41.9]`): approved. (d) AC 2 (save-memory from origin `system` with `Source` `learned`) MOVES to Story 41.11 with its AD-31 amendment; 41.9 keeps 41.8's rule that code decides the source. Recorded in epics.md (Rule 5, Story 41.9 `[AMENDED 2026-11-09]`, Story 41.11 `[MOVED 2026-11-09 from Story 41.9]`). The pin-before-41.12 500 (item 5) stands as written; Task 0 measures it.

## Review Triage Log

### 2026-11-09 — Review pass
- verdicts: 20 findings — high 0, medium 1, low 11, false 5, maybe-false 3
- findings:
  - `[low]` `[reject]` Blind: REST table keeps the placeholder row beside the new Story 41.9 row — the spec names this insertion ("after line 1541"), approved by the Planner; contended spine, plain union.
  - `[low]` `[reject]` Blind: step-3 bullet and the 34.2 contracts row still say tool only — the AD-1 sub-bullet and the AD-33 row added right beside them carry the amendment; the spec forbids rewording existing lines (Epic 35 contention).
  - `[false]` `[reject]` Blind: `total` differs between list and search — the matrix fixes it ("`total` is the item count"); spec-bound.
  - `[false]` `[reject]` Blind: pin routes always 500 until 41.12 — ruled by the Planner (matrix row, Task 0 measured `failed`); spec-bound.
  - `[low]` `[patch]` Blind: e2e header says "with the row untouched" but no row is seeded — comment corrected.
  - `[false]` `[reject]` Blind: stale "four verbs" in `TestRealStubOwners` — that test still covers the four verbs of the two real stub owners; unchanged and accurate.
  - `[low]` `[reject]` Blind: `ReadMemories` probe override has no doc comment — the class header documents it, as for `SubmitMemory` and `NoteText`; cosmetic.
  - `[low]` `[reject]` Edge: `DELETE /v1/memory/items/pin` matches `:ref/pin` with ref `items` — refs are generated 22-character ids, a ref named `pin` cannot exist, and the answer for the stray path is 404 not_found; wontfix-theoretical, reopen_if a ref can be user-chosen.
  - `[maybe-false]` `[reject]` Edge: `Memory.Search` might throw outside its Try — an unhandled exception in a route is answered by the REST framework's error handling as a 500, as for the sibling routes; a guard adds a branch for a case not shown reachable.
  - `[false]` `[reject]` Edge: unpin over_cap shows the pin sentence — the matrix gives one row for pin and unpin with over_cap 409; spec-bound, and `MemoryOps` has no unpin over_cap case.
  - `[false]` `[reject]` Edge: search `total` is the hit count — same as above, the matrix fixes it.
  - `[low]` `[reject]` Edge: `Memory/Ops.cls:19` comment says tool origin only — Lane A file the spec forbids editing; Story 41.12 edits `MemoryOps` and updates it. reopen_if: 41.12 leaves the class comment unchanged.
  - `[medium]` `[patch]` Verification gap: `TestItemsSearch` had one matching memory, so "total is the item count" and the best-5 cut could not fail — now seven session memories and one other session's: 5 items, total 5, all the session's own; mutation line recorded (red when the search branch is dropped).
  - `[low]` `[reject]` Verification gap: no mutation for the pin mapper or the e2e envelope — Rule 19 asks one demonstrated mutation per AC and AC 3 and AC 4 have them; the e2e spec runs in CI (`live:sign-in`).
  - `[low]` `[patch]` Verification gap: `TestPin` real mode pins the probe's answer, not `MemoryOps` — the comment now says so; the real `MemoryOps` is Task 0's measurement, and 41.12 replaces the probe branch with its handler.
  - `[low]` `[reject]` Verification gap (other): `TestItemsSearch` and `TestForgetOtherSessionReal` skip off the image — by design, and both ran on the image stack.
  - `[low]` `[reject]` Verification gap (other): the e2e `total >= items.length` is weak — a shape check of the list; the counts are pinned by `TestItems`.
  - `[maybe-false]` `[reject]` Intent: tests sit at the method surface while the envelope and dispatch live at HTTP — the e2e spec covers the envelope refusal and the 401s over HTTP (CI); the descriptive divergence is the spec's own test plan.
  - `[low]` `[reject]` Intent: `over_cap` text not tied to EXPERIENCE.md — approved verbatim by the Planner (Spec Change Log (a)); the test holds the approved copy.
  - `[maybe-false]` `[reject]` Intent: the 404 pre-check on an empty or over-long ref is beyond the matrix — recorded under Decided in-stage; without it a 23-character ref fails message validation as 500.

## Design Notes

**ADs:**
- AD-1: the gate and the origins.
- AD-4: the session is never taken from the client.
- AD-13: the envelope.
- AD-21: the memory verbs, and `Memory.List`/`Search` as the read path.
- AD-29 and AD-33: Lane B, and the names fixed by 41.8.
- AD-31: untouched.

No AC contradicts an AD's Rule.

**Already met (evidence):**
- Another session's forget is refused in `MemoryOps.OnForget` (`Memory/Ops.cls:138`, DW-740).
- List and Search return `source` and `pinned` (`Memory.cls:197-212`).
- The envelope is applied to every non-GET call (`Web/Api.cls` header, the AD-13 bullet, and `OnPreDispatch`).

**Before 41.12 (inference, Task 0 measures):** `MemoryOps`' MessageMap has no `PinMemory`, so Ens's default `OnMessage` answers `$$$EnsError($$$EnsErrRequestNotHandled)` (`irislib/Ens/BusinessOperation.cls:707-710`). That is not code 5003, so `CommandsIn.IsStub` is 0, and the gate answers `failed`. The pin routes then give 500 server_error "Something went wrong inside OcuTalon. Try again.", and Ens logs the unhandled request. Nothing calls them before 41.12 lands in this epic (the card is 41.13). Turning this into not_built would widen `IsStub`, which is left out to keep the story small.

**AC 2 (ruled 2026-11-09, moved to 41.11):** accepting `SaveMemory` from origin `system` with `Source` `learned` would need:
- a message-carried `Source`, which contradicts 41.8's rule (spec Always 1, and Decided in-stage: "a message-carried source for origin `system` is 41.11's, if it is ever built");
- a decision on Epic 19's trust rule, under which a non-`tool` row makes recall untrusted. That is Lane A.

The Contest Planner, under the owner's delegation, moved the AC to Story 41.11 with its AD-31 amendment (planner-2026-11-09-41.9 item (d)). This story keeps 41.8's rule: no `Source` on `SaveMemory`, no `system` origin.

**Decided in-stage:**
- The forget path is `DELETE /v1/memory/items/:ref`. `/v1/memory/:ref` would also catch `precedents` and `items`.
- There is no route pre-check for a memory row. Owner scope is `MemoryOps`' check ("through Memory.Ops", per the AC). The precedents route pre-checks through `Ownership.Precedent`, but `Data.Memory` is Lane A and AD-21 names `Memory.List`/`Search` as its reads.
- Items leave out `origin`.
- `q` is capped at 2,000 characters, the length of `Data.Memory.Text`.
- Search returns 5 items and List 20.
- The governance test extends `CommandsStep3`, which owns the memory verbs, rather than starting a new class.
- No `short-names.tsv` or `Msg/Catalog` line is needed: the precedent verbs have none.
- (implement) `pinned` in an item is a JSON boolean; `Memory.List`/`Search` return 1 or 0. Story 41.13's card reads a boolean.
- (implement) A ref that is empty or longer than 22 characters (`MEMORYREFMAX`, the length of `Data.Memory.Ref`) is 404 not_found before anything is submitted; otherwise message validation would fail it as 500.
- (implement) `over_cap` is 409 for both pin and unpin (the matrix row), and 500 for forget.

**Extend, don't copy:**
- The verb classes follow `ForgetMemory`.
- The routes follow `ForgetPrecedent` and `Precedents`, with one shared outcome mapper.
- The tests follow `MemoryApiProbe` and `CommandsStep3Probe`.

**Consumes:**
- `Memory.List`/`Search` (41.8);
- `MemoryOps.OnForget` (19.3);
- `Ownership.SessionRef`;
- `Commands.Submit`.

**Consumed-by:**
- 41.12: handles `PinMemory`/`UnpinMemory` and answers `over_cap`.
- 41.13: the card calls items, pin, unpin and forget.

**Integration AC:** `TestForgetOtherSessionReal` runs the real gate and the real `MemoryOps.OnForget`. The consumer for the pins is 41.12, the first consumer that handles them.

**Security** (approved, no veto, planner-2026-11-09-41.9 (b)):
- CSRF and same origin: the AD-13 envelope in `OnPreDispatch`, which all write routes use.
- Session check: `Ownership.SessionRef`, where no session gives 500, and 401 signed_out comes from `ApiBase`.
- Owner scope: list and search pass the session to `Memory.List`/`Search` (`WHERE SessionRef = ?`). Pin and forget carry only the server-side `SessionRef`, and `MemoryOps` matches the row's `SessionRef`.
- No new role or grant.

**Public text** (approved verbatim, planner-2026-11-09-41.9 (a)):
- New: 409 `over_cap` "That would go over the 1,000-token limit. Unpin something first." (EXPERIENCE.md:1054).
- Reused, unchanged:
  - "OcuTalon has nothing at this address."
  - "This part of OcuTalon isn't built yet."
  - "Something went wrong inside OcuTalon. Try again."
  - the envelope refusals
  - CommandsIn's "That can't be done from the chat. Nothing was changed." and "OcuTalon can't take that command from here. Nothing was changed."

**Spine lines** (approved, planner-2026-11-09-41.9 (c); inserted bottom up, each marked `[ADDED 2026-11-09, Story 41.9]`; no Binds, Prevents or Rule wording changes):
1. The REST table, after line 1541:
   > `| `GET /api/v1/memory/items` (`q` blank: `Memory.List`, the newest 20 and `total`; else `Memory.Search`, the best 5), each `{ref, text, savedAt, source, pinned}`; `POST` and `DELETE /api/v1/memory/:ref/pin` submit `PinMemory` and `UnpinMemory`, and `DELETE /api/v1/memory/items/:ref` submits `ForgetMemory`, each with origin `web_user` through `CommandsIn` to `MemoryOps`, which scopes the ref to the CSP session's `SessionRef`; behind the AD-13 envelope [ADDED 2026-11-09, Story 41.9] | the memory operation (AD-21) |`
2. AD-33's cross-area table, after line 1395:
   > `| `OcuTalon.Msg.Command.ForgetMemory` (`MemoryRef`) also from origin `web_user`, submitted by the web layer through `Commands.Submit` for `DELETE /api/v1/memory/items/:ref` and routed by `CommandsIn` to `MemoryOps` (AD-1, AD-4) [ADDED 2026-11-09, Story 41.9] | B | Story 41.9 (`MemoryOps`' owner check, Story 19.3) |`
3. AD-1, after line 120:
   > `    - From Epic 41's second part `CommandsIn` also accepts `ForgetMemory` from origin `web_user`, for the Memory card's Forget (`DELETE /api/v1/memory/items/:ref`): the web layer sets the CSP session's `SessionRef` (AD-4) and `MemoryOps` forgets only that session's own row, so another session's ref answers `not_found`; origin `tool` keeps the context check above. `PinMemory` and `UnpinMemory` are accepted from origin `web_user` only. [ADDED 2026-11-09, Story 41.9]`

**Contended with Epic 35 (orchestrator ruling 2026-11-09, decide, plain union):** Story 35.2 (lane B, in flight) appends 6 rows to `Core/CommandsIn.cls`' XData Routes, adds `SendEmail` to `TOOLVERBS` and a Carry check, changes only the body of `Web/Api.cls` `IsAdmin()`, and adds an AD-1 sub-bullet right after spine L120 plus REST and cross-area table rows. Both stories proceed as planned; whichever merges second integrates forward keeping both sides (both sets of Routes rows with JSON commas fixed, both AD-1 sub-bullets in merge order, both sets of table rows, this story's `ForgetMemory` origin change plus 35.2's `TOOLVERBS`/Carry lines). So this story writes its edits as separate, added lines: new Routes rows appended, new methods and UrlMap lines added, new spine lines inserted; the only in-place edit to a shared line is `ForgetMemory`'s origins (`"tool"` to `"tool,web_user"`). No rewording of existing shared lines (comment updates in `CommandsIn` go in new lines next to the old, never rewrite `TOOLVERBS` or `IsAdmin`). A conflict that would need a behaviour choice is escalated, not resolved in-stage.

**CI:** no new unit, area or group. `Test.Core`, `Test.Web` and the e2e spec are in their existing shards and units.

## Verification

Run from the worktree root, one command per call, with `timeout: 600000`, each sized to about 150 s. Prefix every `ci/` call with `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=41 stage=<stage>'`.

- The fresh tag is `e41s9i` and the warm tag `e41s9iw`. Never run two test runs in one message.
- Every IRIS MCP call names `server` and `namespace`. Use no real key and no Telegram bot.

**Shared surfaces:**
- `Test.Web.Api:TestRoutes`' UrlMap list (32 → 36);
- the `CommandsIn` Routes table and its origin pins (`Test.Core.CommandsStep3`, and any test that pins `ForgetMemory` as tool-only);
- `CommandsStep3Probe`'s dispatch;
- `MemoryApiProbe`'s recorded fields.

`Test.Web.BodyLimit` is unaffected, because the pin POST takes the default limit. Every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once) `OCUTALON_RUN_TAG=e41s9iw ci/warm.sh up`, then the Task 0 measurement.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e41s9iw ci/iris.sh class <Class>`, once each for `OcuTalon.Test.Core.CommandsStep3`, `OcuTalon.Test.Core.CommandsPrecedent`, `OcuTalon.Test.Web.MemoryApi` and `OcuTalon.Test.Web.Api`. Expected: passed.
- (once) `bash docker/tests/test-class-rules.sh`, then `bash docker/tests/test-boundaries.sh`. Expected: pass.
- (once) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16`. Expected: the baseline from AC 4.
- (once) `ci/warm.sh down`, then `ci/iris.sh teardown` with `e41s9i`.
- **Left to CI:** `live:sign-in` (the e2e spec; over 150 s locally), the shards, `bash ci/checks.sh`, and the lead's fresh-environment check.

**Mutations (Rule 19), one per AC:**
- AC 1: `PinMemory` origins `"web_user,telegram"` makes `CommandsStep3:TestOrigins` go red.
  - mutation: PinMemory origins "web_user,telegram" -> CommandsStep3:TestOrigins red ("PinMemory from 'telegram' sends nothing / is not_allowed / says why").
  - mutation: PinMemory origins "web_user,tool" alone -> stays green: the gate refuses a tool for any verb outside TOOLVERBS before it reads the origins, so the table entry alone is not a way in. With `PinMemory` also added to TOOLVERBS -> CommandsStep3:TestOrigins red (PinMemory from 'tool') and TestContextOwnSessionOnly red (a pin for the context's own session is routed instead of refused).
- AC 2: none (moved to 41.11).
  - mutation (code review): SaveMemory origins "tool" -> "tool,system" -> CommandsStep3:TestOrigins red ("SaveMemory from 'system' sends nothing / is not_allowed / says why"); reverted, cmp identical.
- AC 3: `MemoryItems` passes `""` as the session makes `MemoryApi:TestItems` go red.
  - mutation: MemoryItems reads with session "" -> MemoryApi:TestItems red (the empty list answers 500 instead of 200; `Memory.List` refuses an empty session).
  - mutation: ReadMemories always lists (the search branch dropped) -> MemoryApi:TestItemsSearch red (seven memories match: 7 items and total 7 instead of 5 and 5). `MEMORYSEARCHMAX` 5 -> 50 stays green: `Memory.MAXLIMIT` (5) clamps the search, so the route's constant is not the limit.
  - mutation (code review): MemoryItemCommand's over_cap -> 409 line dropped -> MemoryApi:TestPin and TestOverCapText red (the pin's and unpin's over_cap answer 500); reverted, cmp identical.
- AC 4: drop `web_user` from ForgetMemory's origins, which makes `TestForgetOtherSessionReal` go red: the own row is refused not_allowed instead of forgotten. Also, `MemoryOps`' check is reached only through the real mode, so a route that answers 200 without submitting makes the same test go red, because the other session's row is expected to be kept and the route to give 404.
  - mutation: ForgetMemory origins "tool,web_user" -> "tool" -> MemoryApi:TestForgetOtherSessionReal red (another session's row is not answered 404 by MemoryOps, the own row is not forgotten and still stored) and TestForgetMemory red (the real-mode unknown ref is not 404).
  - mutation: the route answers 200 done for ForgetMemory without submitting -> MemoryApi:TestForgetOtherSessionReal red (another session's row is expected 404 and the own row gone, and the route answers 200 for both) and TestForgetMemory red (no command was submitted).
  - Each mutation was applied in the warm throwaway, observed red, and reverted; the files are byte-identical to the pre-mutation copies (cmp).

**QA additions (QA, warm stack e41s9qw, 2026-11-09):**
- `src/ocutalon/cls/OcuTalon/Test/Web/MemoryApi.cls` (QA): `TestRefLength`, `TestItemsQuery`, `TestSessionNeverFromClient`, `TestWriteRoutesBehindEnvelope`.
- `src/ocutalon/cls/OcuTalon/Test/Web/MemoryApiProbe.cls` (QA): `HasUserRole` answers 1, so that `OnPreDispatch` can be run past the role check to the AD-13 envelope.
- `web/e2e/api/memory.spec.ts` (QA): a third test, the envelope on the two pin routes and a 23-character ref (404) on all three writes. Type-checked locally (`tsc -p tsconfig.e2e.json`, listed by Playwright); the run is left to CI (`live:sign-in`).
- mutation (QA): `MEMORYREFMAX` 22 -> 21 -> MemoryApi:TestRefLength red (a 22-character ref is 404 instead of submitted), and TestForgetOtherSessionReal red too. Before this, a 22-character ref (the boundary of the matrix row) had no pinning test: only 23 and empty were pinned.
- mutation (QA): the outer `$ZStrip` of `q` after the 2,000-character cut dropped -> MemoryApi:TestItemsQuery red (a cut that ends in whitespace keeps 2,000 characters).
- mutation (QA): `MemoryItems` and `MemoryItemCommand` take the session from `%request.Get("SessionRef")` when it is given -> MemoryApi:TestSessionNeverFromClient red (the list answers the other session's row, the search and the three writes carry the client's Ref). This pins "no route takes a SessionRef from the client".
- mutation (QA): `OnPreDispatch` skips the envelope for URLs under `/v1/memory/` -> MemoryApi:TestWriteRoutesBehindEnvelope red (nine refusals: no header, text/plain, another Origin, on all three write routes). Before this the envelope on the new routes was pinned only by the e2e spec (CI) and for the forget route alone.
- Each mutation was applied in the warm throwaway, observed red, and reverted; `Web/Api.cls` is byte-identical to the pre-mutation copy (cmp) and `git status --short` / `git diff --stat` show only the QA files. Not demonstrated: the e2e additions (left to CI); the unit mutations above cover the same behaviours.
- Matrix rows that already had a pinning test and were not duplicated: the empty and 23-character refs (`TestPin`, `TestForgetMemory`), the q cap (`TestItems`), the unpin outcomes (`TestPin`), no CSP session (`TestNoSessionIs500`), over_cap 409 and its text (`TestPin`, `TestOverCapText`), not_built 501 (`TestPin`, `TestForgetMemory`), the gate (`CommandsStep3`).

**Task 0 (measured on the warm stack e41s9iw, 2026-11-09):** a `PinMemory` (origin web_user, a fixture session, MemoryRef `zzunknownref`) through `Commands.Submit` to the running production gave status OK and a CommandResult with Ok 0, Outcome `failed` and Message "Something went wrong inside OcuTalon, so the command may not have finished." That is the predicted outcome, so the matrix row and Design Notes stand. The same session's `ForgetMemory` from web_user gave Ok 0, Outcome `not_found` (the real gate and the real `MemoryOps`).

## Auto Run Result

Status: done
Blocking condition: none

Summary: Story 41.9 adds `PinMemory` and `UnpinMemory` (sibling `ForgetMemory`), routes them to `MemoryOps` from `web_user` only, accepts `ForgetMemory` from `web_user` as well, and adds the four memory item routes to `Web.Api` (`GET /v1/memory/items`, `POST`/`DELETE /v1/memory/:ref/pin`, `DELETE /v1/memory/items/:ref`) behind the AD-13 envelope, with one shared outcome mapper and the approved 409 `over_cap` text. `SaveMemory` and its origins are unchanged (AC 2 moved to 41.11).

Files changed:
- `src/ocutalon/cls/OcuTalon/Msg/Command/PinMemory.cls`, `UnpinMemory.cls` (new): the verbs; `ForgetMemory.cls`: comment.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls`: Routes rows and comments.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`: UrlMap, `MESSAGEOVERCAP`, `MemoryItems`, `ReadMemories`, `PinMemory`, `UnpinMemory`, `ForgetMemory`, `MemoryItemCommand`.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsStep3.cls`, `CommandsStep3Probe.cls`; `Test/Web/MemoryApi.cls`, `MemoryApiProbe.cls`, `Api.cls` (`TestRoutes` 36): tests.
- `web/e2e/api/memory.spec.ts`: signed-out 401s, list shape, unknown forget 404, envelope refusal.
- Spine: AD-1 note, AD-33 cross-area row, REST row; memlog entry.

Review findings: 20 reported. Patches applied: 3 (medium 1: `TestItemsSearch` now has seven matching memories and pins the best-5 cut and the item-count total, mutation line recorded; low 2: the e2e header comment and the `TestPin` comment). Deferred: none. Rejected: 17, each with its reason in the Review Triage Log (spec-bound rulings, Lane A file, theoretical, cosmetic).

Follow-up review recommended: false (no high patched, one medium patched).

Verification (warm throwaway `e41s9iw`): `CommandsStep3`, `CommandsPrecedent`, `MemoryApi` and `Web.Api` passed (`Web.Api` skips `TestMessagesNoProductionIs500`, as before); after the patch `MemoryApi` passed, red under the search-branch mutation and green again after the revert; `test-class-rules.sh` and `test-boundaries.sh` passed; `lint_spine.py` at its baseline (`ok` false, 10 low `placeholder` findings). Task 0 measured `failed` for a pin (see Verification). The e2e spec and `ci/checks.sh` are left to CI. Warm stack torn down; no fresh stack started.

Residual risks: the pin routes answer 500 until Story 41.12 handles them; the e2e spec was only type-checked locally; the AC 1 mutation as first written (`"web_user,tool"`) stays green because the gate refuses tool for any verb outside `TOOLVERBS`, so the spec records `"web_user,telegram"` instead.
