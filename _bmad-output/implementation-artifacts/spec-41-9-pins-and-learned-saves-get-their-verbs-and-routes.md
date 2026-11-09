---
title: "Story 41.9: Pins and learned saves get their verbs and routes"
type: 'feature'
created: '2026-11-09'
status: 'in-progress'
baseline_revision: 'da11990b3e7ca934d3b52f9815f3498cac48cd6c'
baseline_commit: 'da11990b3e7ca934d3b52f9815f3498cac48cd6c'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      The real-HTTP test of the pin routes (web/e2e/api/memory.spec.ts) cannot assert a success status until MemoryOps handles PinMemory and UnpinMemory; it asserts the matrix's 500 server_error today.
    evidence: |-
      MemoryOps' MessageMap has no pin entry before Story 41.12 (Task 0: a pin gives Outcome failed). The standing rule asks for the success status of every new route; the pin and unpin routes have none to show yet.
    location: >-
      web/e2e/api/memory.spec.ts (the pin step of the memory items test), for Story 41.12: replace the 500 with 200 {"result":"done"}, 409 over_cap and a second-session 404
  - summary: >-
      The search's 503 search_busy (ruled by the Planner) reaches the Angular client as an API 503, which the online demo reads as its whole-page busy state (DemoBusyState, chat outbox), not as a local "search is busy" message.
    evidence: |-
      web/src/app/live/demo-busy.ts holds the API cause "from an API answer of 503 until the next 2xx"; web/src/app/chat/chat-outbox.ts offers a typed message back on a 503 on the online demo; AD-25 says the same. No client calls the route yet (the card is Story 41.13), so nothing is wrong today; once the card searches, a stuck embedder (20 s) would raise the banner for the session. A fix is either the client ignoring a 503 whose code is search_busy, or a different status for the busy answer (a Planner call, because the ruling fixed 503).
    location: >-
      web/src/app/live/demo-busy.ts, web/src/app/envelope.interceptor.ts (Story 41.13, the Memory card's search)
    severity: medium
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

- [x] [Review][Decision] HIGH: `GET /v1/memory/items` is 500 for every real signed-in user — measured on the warm stack over HTTP as the README account (`/state` and `/memory/precedents` 200; `/memory/items` and `?q=vpn` 500). The console log gives the causes: the list's `Memory.List` prepares with the SQL privilege check ("The memories could not be counted: User ocutalon is not privileged for the operation"), and the search's embedding needs `%Service_EmbeddedPython:U` ("<OBJECT DISPATCH>Embed+5^OcuTalon.Memory.Embedder.1 *Resource %Service_EmbeddedPython:U is required"). AD-13 allows unchecked prepares only in `Session.ForUser`, `Live.Event.Since` and `Ownership.Rows`, and the spine (L107, AD-4) lets the web layer read `Data.Memory` only through the ownership API. So the spec's read path (`Memory.List`/`Search` called from `Web.Api`) cannot work in the CSP process. The unit tests passed because they run as a privileged user. The e2e list test (left to CI) would go red. [Web/Api.cls ReadMemories] — fix-risk high (a privilege or AD choice); in-story; escalated as `## Clarification Needed` (Rule 4).
- [x] [Review][Patch] MED: no real-HTTP test lists a seeded memory row (the five-member item, `pinned` a JSON boolean) or forgets one with 200 through the running production. The e2e spec checks only top-level keys and a 404. [web/e2e/api/memory.spec.ts] — fix-risk low; in-story; left for the rework iteration together with the HIGH (Rule 3).
- [x] [Review][Patch] MED: the "a failed search or embed gives 500" matrix row has no pinning test. The product's `ReadMemories` search branch never runs failing: the probe's `fail` mode replaces the method. [Web/Api.cls ReadMemories; Test/Web/MemoryApi.cls] — fix-risk low; in-story; left for the rework iteration, because the search path depends on the HIGH's ruling (Rule 19).
- [x] [Review][Ruling] HIGH, part LIST (planner-2026-11-09-41.9-readpath (1)): add a `memory` row kind to `OcuTalon.Data.Ownership.Rows`, to AD-13 to the letter: fixed SQL text inside `Ownership` for the kind, the owner check (`SessionRef = ?`, the caller's server-side `SessionRef`) in the `WHERE` clause, never caller-supplied text, field or table names; newest 20 and the session's `total`. `Web.Api` `MemoryItems` with a blank `q` reads through it and never calls `Memory.List` or embeds anything. Items keep the shape `{ref, text, savedAt, source, pinned}` (`pinned` a JSON boolean; an empty stored `Pinned`/`Source` reads as 0/told, as `Memory.Row` does, DW-1014). The ownership cross-session test (the existing per-kind test in `Test.Data.Ownership*`) proves session B gets none of session A's memory rows on the list AND on a direct id.
- [x] [Review][Ruling] HIGH, part SEARCH (planner-2026-11-09-41.9-readpath (2b)): add the read verb `OcuTalon.Msg.Command.SearchMemory` (`Property Query As %String(MAXLEN = 2000)`, sibling `PinMemory`; no `SessionRef` taken from the client: the web layer sets the server-side `Ownership.SessionRef` exactly as for pin and forget). `CommandsIn` routes it to `MemoryOps` from origin `web_user` only (an appended Routes row; not a tool verb). `MemoryOps` (`Memory/Ops.cls`, a MessageMap entry and one handler; this Lane A edit is authorized by the ruling) runs `Memory.Search(<the command's own SessionRef>, query, 5)` in the production job and answers `CommandResult` `Ok 1`, `Outcome` `done`, `Data` = the JSON items array (same item shape). Conditions: (1) the owner is the session `CommandsIn` records, never the request body or query; the cross-session test also covers search: session B's search for a phrase only A's memory contains returns no items. (2) SearchMemory is a READ: no approval; it never counts as a command, an action or an Act wherever the eval or the release gates count them (the "0 approvals, commands, setting changes or fix runs" tallies and the held-out "nothing acted" checks); add one assertion that a search leaves those counters unchanged (find where they are counted; if a search would count, exclude read verbs there). (3) Bounded wait: a slow or stuck embedder gives the page 503 with code `search_busy` and the text "Search is busy right now. Try again in a moment." (NEW PUBLIC TEXT, pending the Planner's approval: write it as one `Parameter MESSAGESEARCHBUSY` so a changed wording is a one-line fix), never a hang or a 500; Task 0 measures how `Commands.Submit` behaves when the operation does not answer in time, and the route sets an explicit timeout. (4) An empty or blank `q` never submits `SearchMemory`: it returns the list through `Ownership.Rows` with no embedding. (5) The spine lines go in as separate additive lines, each marked `[ADDED 2026-11-09, Story 41.9]`, a plain union with Epic 35's rows: an AD-1 origins note (SearchMemory from origin `web_user` only, a read), the AD-21 note "the web layer reads the memory list through `Ownership.Rows`, and searches through the `SearchMemory` read verb to `MemoryOps`", an AD-33 cross-area row for `SearchMemory`, and the REST row amended by an added line (not a reworded one) for the search path.
- [x] [Review][Ruling] Standing rule (Planner, all lanes, 2026-11-09): every new or changed `/api/v1` route of this story has at least one test over real HTTP signed in as the unprivileged README account, asserting the success status and, for owned data, a second-session isolation check (two browser contexts are two sessions). This absorbs the two MEDs above: `web/e2e/api/memory.spec.ts` lists a seeded memory row (200, the five-member item, `pinned` boolean), searches it (200, found), forgets it (200 `{"result":"done"}`, then gone), and a second session lists, searches and forgets none of the first session's rows (404 on its ref); seed rows by the existing e2e support helpers (`web/e2e/support/**`) or a test-only seeding path the suite already uses, never a new public route. The search-failure row is pinned by a unit test of the real `ReadMemories`/search branch (and the busy 503 by one that makes the operation not answer in time).
- [ ] [Review][Ruling] Standing route-test rule CORRECTED (Planner, 2026-11-09): the README account holds `OcuTalonAdmin`, so it is NOT the unprivileged account. Every new or changed `/api/v1` route of this story has real-HTTP tests over a signed-in session (i) as the unprivileged LIVE fixture user (`fixtureUser('LIVE')`, role `OcuTalonUser` only, the demo visitors' role): the success status for these user routes (`GET /memory/items` blank and with `q` → 200; the forget → 200 then 404; the pin routes keep today's matrix answer until 41.12, DW-1039) and (iii) for owned data a second-session isolation check (a second OcuTalonUser-only fixture session gets none of LIVE's rows; its forget of LIVE's ref is 404). In `web/e2e/api/memory.spec.ts`, sign in as LIVE (not README) for this story's item routes (the list/search/forget test and the item-route and pin-envelope tests); leave the Story 41.2 precedent/notes test as it is. The lead's smoke already measured the behaviour as two OcuTalonUser-only users (list, search, isolation, forget all as expected); this item is the suite's test.
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

Code review round 2, 2026-11-09 (re-review of the rework `da11990b..HEAD`; full mode; layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 16 findings, 9 entries). Round 1's checklist: (1) HIGH `GET /v1/memory/items` 500: FIXED, re-measured over HTTP on the warm throwaway `e41s9cw` as the README account `ocutalon`: `/memory/items` 200 with the seeded item `{ref, text, savedAt, source:"told", pinned:false}` and total 1, `?q=` 200, `?q=zzcrwombat relay` 200 with the item, then its forget 200 `{"result":"done"}`, a second forget 404 not_found and the list empty; `test-class-rules.sh` passes (the unchecked prepare is still only in `Session.ForUser`, `Live.Event.Since` and `Ownership.Rows`). (2) MED no real-HTTP test lists or forgets a seeded row: FIXED (`web/e2e/api/memory.spec.ts`, the standing-rule test, CI `live:sign-in`). (3) MED no pin for "a failed search or embed gives 500": FIXED (`MemoryApi:TestSearchSubmitsTheVerb`, mutation recorded). Verdict: no HIGH; story closes.
- [x] [Review][Patch] MED: the answered path of `CommandsIn.SendSearch` had no unit test: every test that reached it expected busy, so a `SendSearch` that turned every OK send into busy stayed green and only the e2e test (CI) would see it. `CommandsTimeoutProbe` gains `Answer` (an owner that answers in time) and `TestSearchMemoryWaits` asserts the owner's answer comes back as it is; mutation recorded under Verification. [Test/Core/CommandsTimeoutProbe.cls, Test/Core/CommandsStep3.cls] — fix-risk low; in-story.
- [x] [Review][Patch] MED: the standing-rule e2e test could not fit Playwright's default 45 s test timeout when a search finds the embedder busy (each 503 after a 20 s wait, asked up to three times), so a cold CI stack would fail it as a timeout. It now sets `test.setTimeout(150_000)`. [web/e2e/api/memory.spec.ts] — fix-risk low; in-story.
- [x] [Review][Patch] LOW: `MemoryOps.OnSearch` had no Try/Catch, while the class description says any exception answers failed: a throw in the embed or the item loop left the handler as an Ens error instead of the failed `CommandResult`. Wrapped as `OnForget` is. [Memory/Ops.cls OnSearch]
- [x] [Review][Patch] LOW: `SearchMemory`'s doc comment said it searches "one of the session's memories"; it searches all of them. [Msg/Command/SearchMemory.cls:1]
- [x] [Review][Patch] LOW: the rework appended its busy sentence to an existing shared comment line of `CommandsIn` (the Epic 35 contention ruling asks for added lines); the old line is restored and the sentence is a line of its own. [Core/CommandsIn.cls:30]
- [x] [Review][Patch] LOW: `Test.Web.MemoryApi` called the search_busy sentence "approved" (the SEARCHBUSY parameter and four assertion labels); it is pending the Planner's PUBLIC TEXT approval. Labels now say the busy sentence, pending. [Test/Web/MemoryApi.cls]
- [x] [Review][Patch] LOW: AC 3's mutation lines were stale against the rework (the reason named `Memory.List`, and a `MEMORYSEARCHMAX` mutation named a removed parameter). The first was re-applied on the rework's code and corrected; the clause about the removed parameter is replaced. [spec Verification]
- [x] [Review][Defer] MED (occurrence): DW-1031's premise ("unreachable today") is no longer true: the rework made `?q=` work, so a direct GET loop reaches `SearchMemory` → `MemoryOps` (PoolSize 1, shared with every session's saves and forgets) with no server-side allowance. Occurrence and note appended to DW-1031 (owner 41-13): the allowance must be enforced in the route, not only by the card. — fix-risk med; in-epic.
- [x] [Review][Defer] MED (occurrence): DW-1040's fix must also amend AD-25, which says the client shows the demo's busy state for any API 503. Occurrence and note appended to DW-1040 (owner 41-13). — fix-risk low; in-epic.
- `[low]` `wontfix-accepted` (DW-1046): a search copies up to five memory texts into `CommandResult.Data`, and its query into the `SearchMemory` body; both stay in the data database's messages for 90 days (AD-27) and survive a later Forget. `SaveMemory` bodies already carry the text the same way, and FR-15's shared trace already shows message bodies, so nothing new is exposed. reopen_if: a requirement that Forget removes a memory's text from message bodies, or that the trace viewer must not see memory text.
- `[low]` reject: the acceptance auditor noted that the bounded wait is set in `CommandsIn` (`SEARCHTIMEOUT`), not in the route as condition (3) says. `Commands.Submit` takes no timeout (Decided in-stage, read-path rework); the behaviour is the ruling's, and the REST row carries the 20 s wait. by-design.
- `[low]` reject: the spec's Security note, Consumes and older Design Notes lines still name `Memory.List`/`Search`. The fix edits the spec's intent text; the "Read path (ruled ...)" paragraph supersedes them.
- `[low]` reject: `Memory/Ops.cls`'s closing sentence still says origin tool only, and DW-1029's pointer (`:19`) is now line 22. It is DW-1029's item, already owned by 41.12; no new entry.
- `[low]` reject: the e2e test has never run locally and has no mutation line. The run is left to CI (`live:sign-in`, over the 10-minute cap); the HTTP re-measure above mirrors it, and the unit mutations pin the same seams.

Rejected / closed at emission:
- `[low]` `wontfix-theoretical`: `/v1/memory/:ref/pin` also matches `/v1/memory/items/pin`, `/precedents/pin` and `/notes/pin`. The earlier triage line said these answer 404; until 41.12 they reach the pin verbs with refs `items`, `precedents` or `notes` and answer 500 (failed), and after 41.12 they answer not_found. reopen_if: a memory ref can be user-chosen, or a fixed segment under `/v1/memory/` is named `pin`.
- `[low]` reject (edge): a 2,000-character cut of `q` can split a surrogate pair. That needs a query of over 2,000 characters with an emoji exactly at the boundary, and the fix adds a guard.

## Spec Change Log

- 2026-11-09 (planner-2026-11-09-41.9-readpath, Contest Planner under the owner's delegation, relayed by the orchestrator): code review's HIGH (the memory items reads answer 500 for the unprivileged CSP user: privilege-checked SQL in `Memory.List`, `%Service_EmbeddedPython:U` for search; AD-13, AD-4) is ruled. APPROVED: the list reads through a new `memory` kind of `Ownership.Rows`; search goes through a `SearchMemory` read verb to `MemoryOps` (option b). REJECTED: granting any privilege to the user role (it is also the demo visitors' role), and moving `q` out of this story. Conditions as written in the [Review][Ruling] items under Tasks & Acceptance. DW-1031 (search allowance): 41.13's card searches only on submit, never per keystroke, and on the demo each search counts against the existing message allowance (no new number); routed to 41.13 by owner. New standing rule: every new or changed `/api/v1` route has a real-HTTP test as the unprivileged README account with a second-session isolation check for owned data.

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

### 2026-11-09 — Review pass (rework of the read path)
- verdicts: 27 findings — high 0, medium 3, low 21, false 2, maybe-false 1
- findings:
  - `[medium]` `[defer]` Blind: the 503 search_busy trips the demo's whole-page busy state — real (demo-busy.ts, chat-outbox.ts read it for any API 503), but the status is the Planner's ruling and the fix is in web/src (Story 41.13's) or a different status; no client calls the route yet; deferred to 41.13 in the frontmatter.
  - `[low]` `[reject]` Blind: the REST conventions row has no 503 search_busy — the spec allows additive lines only; the new REST row carries the status, code and 20 s wait.
  - `[low]` `[reject]` Blind: the old REST row says Memory.List/Search beside the new "never" row — the spec forbids rewording existing lines (Epic 35 contention); the added row is the later word.
  - `[low]` `[reject]` Blind: a timed-out search still runs in MemoryOps and queues stale work — needs a stuck embedder; the card searches only on submit and DW-1031 is ruled; a staleness branch is more than a direct correction.
  - `[false]` `[reject]` Blind: Ownership.Memory has no production caller — the ruling requires the direct-id kind and its cross-session test (Review Findings, LIST).
  - `[low]` `[reject]` Blind: Memories opens whole Data.Memory objects, vector included — Rows opens objects for every kind; 20 opens per list; a projection kind is new design for no shown harm.
  - `[low]` `[reject]` Blind: the eval exclusion hard-codes one class name — the only read verb today; a shared read-verb list is new surface for a second verb nobody has.
  - `[low]` `[reject]` Blind: the e2e pin step asserts today's 500 — recorded as a deferral for 41.12 (frontmatter).
  - `[low]` `[reject]` Edge: abandoned search queues behind a stuck embedder — same as the Blind row above.
  - `[false]` `[reject]` Edge: Memories with max 0, negative or non-integer — the only caller passes the constant MEMORYLISTMAX (20).
  - `[low]` `[reject]` Edge: Data of a SearchMemory answer may hold non-object elements — Data is written by OnSearch alone, in the five-member shape; a shape guard is a branch for a case not shown reachable.
  - `[low]` `[reject]` Edge: the list and its count are two reads — a save between them shows a transient count difference; the card refreshes.
  - `[maybe-false]` `[reject]` Edge: an error status from the send gives failed (500), not busy — by design (Carry's failed or not_built); busy is exactly the no-answer-in-time case that Task 0 measured; if wrong, the cost is a 500 instead of a 503 on a hard error.
  - `[low]` `[reject]` Edge: the eval test asserts only the commands counter — a search touches no other counter (it writes no approval, setting or fix run).
  - `[low]` `[patch]` Verification gap: no test pins the `ID DESC` tie-break of the memories list — TestBounds now saves three rows with one SavedAt and expects later-saved first; mutation line recorded (red with `ID ASC`).
  - `[medium]` `[patch]` Verification gap: the real ListMemories error propagation is never run failing — the probe gained the read mode `ownershipFails` and TestItems expects 500 for it; mutation line recorded (red with the two error checks dropped).
  - `[medium]` `[patch]` Verification gap: no mutation line for TestSearchHandler's cross-session half — mutation applied (OnSearch searches another session), observed red, reverted, line recorded.
  - `[low]` `[reject]` Verification gap: the e2e test has no mutation line — CI only; the spec records that and the unit mutations at the same seams.
  - `[low]` `[reject]` Verification gap: no mutation for SearchMemory in TestContextOwnSessionOnly — the origins table already refuses a tool for it (TestOrigins mutation recorded); the reviewer rates it low risk.
  - `[low]` `[reject]` Verification gap (other): TestItemsSearch and the search half of TestSearchHandler skip off the image — a named skip by design, as for the other embedder tests.
  - `[low]` `[reject]` Verification gap (other): the e2e pin step depends on the missing handler — same as the deferral.
  - `[low]` `[reject]` Verification gap (other): the e2e helper retries a 503 twice on a cold embedder — a readiness allowance, not a hidden failure.
  - `[low]` `[reject]` Verification gap (other): the e2e seeded row must be in the newest 20 and best 5 of a quiet account — the test seeds its own unique phrase.
  - `[low]` `[reject]` Verification gap (other): TestSearchMemoryWaits ignores the status of one GetShadowInstance — cosmetic; the next use would surface it.
  - `[low]` `[reject]` Intent: 503 search_busy is pinned at unit level only — a stuck embedder cannot be made to order over HTTP; the bound is pinned by CommandsStep3:TestSearchMemoryWaits and MemoryApi:TestSearchBusy.
  - `[low]` `[reject]` Intent: pin and unpin have no HTTP success status — no handler exists before 41.12 (Task 0); the deferral names the e2e step to flip.
  - `[low]` `[reject]` Intent: the "never counted" rule is one name filter — same as the Blind row on the eval exclusion.

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
- (implement) Rework of the read path (planner-2026-11-09-41.9-readpath):
  - The list is `Ownership.Memories` (newest 20), `MemoryTotal` and `Memory` (a direct Ref), the `memories`, `memoryTotal` and `memory` kinds of `Ownership.Rows`. The count kind has an empty row class: `Rows` then returns `{"total": n}` for each result row and opens nothing. No schema change.
  - `MEMORYSEARCHMAX` is gone from `Web.Api`: the best 5 are `Memory.MAXLIMIT`, applied in `MemoryOps.OnSearch`. `ReadMemories` stays the test seam and gains an `Output busy`; `ListMemories` and `SearchMemories` are its two branches.
  - `Commands.Submit` has no timeout argument, so the bounded wait lives in `CommandsIn`: a `SearchMemory` is sent by `SendSearch`, which waits `SEARCHTIMEOUT` (20 s), not `TIMEOUT` (120 s). The framework ends a timed-out synchronous send with an OK status and no response (Task 0), which `SendSearch` answers as `CommandResult` Ok 0, Outcome `busy` with the gate's own failed sentence; every other verb keeps 120 s and `failed`. `Web.Api` maps `busy` to 503 `search_busy` and uses no other new text. `503` is added to `Fail`'s status cases and `HTTP503SERVICEUNAVAILABLE` to the class, as `%CSP.REST` has none.
  - `OnSearch` answers Message empty (the web layer never relays it, so no new sentence), takes no lock, and does not check for a Session row (a read for an unknown session finds nothing). Its items are `{ref, text, savedAt, source, pinned}` with `pinned` a boolean and no origin, so `Web.Api` relays them as they are.
  - The only evaluation tally of commands is `Eval.Report.Actions` (`commands`); it now leaves out `SearchMemory`, and `Test.Eval.Report:TestInjectionActions` asserts a search of session `eval` leaves the count unchanged. The release gates read that report; no other place counts `Msg.Command` rows.
  - The e2e second session is the links fixture user (`fixtureUser('LINKS')`), whose durable session differs from the README account's. Rows are seeded through `Test.Memory.Fixture.Store` run by `irisScript` (support/memory.ts `seedMemory`), never through a route.
  - The e2e pin step asserts today's 500 (no handler before 41.12); the deferral is in the frontmatter.
  - A warm stack runs the old `MemoryOps` in its production job after the class is recompiled ("continuing to run using code from previous version"): restart the production there (a fresh stack needs nothing).

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

**Read path (ruled 2026-11-09, supersedes the matrix's `Memory.List`/`Memory.Search` calls from `Web.Api` and the Never-bullet on Lane A files for exactly two edits):** `Web.Api` never calls `Memory.List` or `Memory.Search` itself: the CSP user has no SQL grant and no Embedded Python service (AD-13). The list is `Ownership.Rows`' `memory` kind; the search is the `SearchMemory` read verb, handled in `MemoryOps` (`Memory/Ops.cls`: one MessageMap entry and one handler, authorized by the Planner's ruling; no other Lane A edit). `SearchMemory` is not a tool verb, needs no approval and is never counted as a command or an action. A slow embedder answers 503 `search_busy` within a bounded wait. The one new text, "Search is busy right now. Try again in a moment.", is pending the Planner's PUBLIC TEXT approval; it lives in one Parameter.

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
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e41s9iw ci/iris.sh class <Class>`, once each for `OcuTalon.Test.Core.CommandsStep3`, `OcuTalon.Test.Core.CommandsPrecedent`, `OcuTalon.Test.Web.MemoryApi` and `OcuTalon.Test.Web.Api`, and, from the read-path rework, `OcuTalon.Test.Data.OwnershipMemories`, `OcuTalon.Test.Eval.Report` and `OcuTalon.Test.Memory.Ops`. Expected: passed.
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
  - mutation: MemoryItems reads with session "" -> MemoryApi:TestItems red (the empty list answers 500 instead of 200; `Ownership.Memories` refuses an empty session). Re-applied on the rework's code in code review round 2 (warm throwaway `e41s9cw`): TestItems red ("no memories: an empty list"), and TestItemsQuery, TestItemsSearch, TestSearchBusy and TestSearchSubmitsTheVerb red too; reverted, cmp identical.
  - mutation: ReadMemories always lists (the search branch dropped) -> MemoryApi:TestItemsSearch red (seven memories match: 7 items and total 7 instead of 5 and 5). The best 5 are `Memory.MAXLIMIT`, applied in `MemoryOps.OnSearch` (the route has no search constant since the rework).
  - mutation (code review): MemoryItemCommand's over_cap -> 409 line dropped -> MemoryApi:TestPin and TestOverCapText red (the pin's and unpin's over_cap answer 500); reverted, cmp identical.
- Rework of the read path (implement, 2026-11-09), each applied in the warm throwaway `e41s9iw`, observed red, and reverted (`cmp` byte-identical):
  - mutation: `Ownership` `memory` kind's `m.SessionRef = ?` dropped from the WHERE clause -> OwnershipMemories:TestIsolation red (B finds A's memory by its Ref and A finds B's).
  - mutation: `memories` kind's owner check dropped -> OwnershipMemories:TestIsolation red (A's list, B's list and a session with no memory); `memoryTotal` kind's owner check dropped -> TestIsolation red (the counts).
  - mutation: `SendSearch`'s no-response -> busy line dropped -> CommandsStep3:TestSearchMemoryWaits red (no answer in time is not busy) and MemoryApi:TestSearchBusy red (no 503, and an error is logged).
  - mutation: `SEARCHTIMEOUT` 20 -> 120 -> CommandsStep3:TestSearchMemoryWaits red (a search waits 20 seconds).
  - mutation: `SearchMemory` origins "web_user" -> "web_user,telegram" -> CommandsStep3:TestOrigins red (SearchMemory from 'telegram' sends nothing / is not_allowed / says why).
  - mutation: `MemoryItems`' `If busy Quit ..Fail(503, ...)` dropped -> MemoryApi:TestSearchBusy and TestSearchSubmitsTheVerb red.
  - mutation: `SearchMemories`' `If 'result.Ok` error line dropped -> stays green until the case "a failed answer that carries items" was added; then MemoryApi:TestSearchSubmitsTheVerb red (a failed answer with items is 200 instead of 500). This is the failed-search row of the matrix.
  - mutation: `OnSearch` leaves `pinned` a number, or adds `origin` -> MemoryApi:TestSearchHandler and TestItemsSearch red.
  - mutation: `SearchMemories` sets the command's `SessionRef` to "" -> MemoryApi:TestItemsSearch red (no search is answered for the session).
  - mutation: a blank `q` always submits a search (the `ListMemories` branch dropped) -> MemoryApi:TestItems red.
  - mutation: `ListMemories` reads 5 instead of `MEMORYLISTMAX` -> MemoryApi:TestItems red (at most 20 items).
  - mutation: `Eval.Report.Actions` without its `SearchMemory` exclusion -> Eval.Report:TestInjectionActions red (a search of session eval is counted).
  - mutation (code review of the rework): `Ownership` `memories` kind's tie-break `m.ID DESC` -> `m.ID ASC` -> OwnershipMemories:TestBounds red (rows saved with one SavedAt come later-saved first); reverted, cmp identical.
  - mutation (code review of the rework): `ListMemories`' two `If $SYSTEM.Status.IsError(sc) Quit sc` lines dropped -> MemoryApi:TestItems red (a list that Ownership refuses is 200 with an empty list instead of 500 server_error; the probe's `ownershipFails` read mode runs the real list branch); reverted, cmp identical.
  - mutation (code review of the rework): `MemoryOps.OnSearch` searches the session that holds a memory with the query's text instead of the command's own `SessionRef` -> MemoryApi:TestSearchHandler red (another session's search for the same phrase finds the first session's memory); reverted, cmp identical.
  - mutation (code review round 2): `SendSearch`'s `'$IsObject($Get(response))` dropped, so every OK send is busy -> CommandsStep3:TestSearchMemoryWaits red ("and its answer is the owner's, as it is", "Ok 1, done, with the items, never busy": a search answered in time, through the timeout probe's `Answer`); reverted, cmp identical. Before this, every unit test that reached `SendSearch` expected busy.
  - Not demonstrated: the e2e test of the standing rule (list, search, forget, second session) has no local mutation, because the Playwright run is left to CI (`live:sign-in`); the unit mutations above pin the same behaviours at the `Ownership.Rows` and `OnSearch` seams.
  - Not demonstrable locally: a route that reads through `Memory.List` or `Memory.Search` again passes every unit test, because the tests run as a privileged user; only the e2e spec (CI, `live:sign-in`) goes red. The unit tests assert the read path through `Ownership.Rows` and the `OnSearch` handler.
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

**Task 0, rework (measured on the warm stack e41s9iw, 2026-11-09, how `Commands.Submit` behaves when the operation does not answer):** with the `MemoryOps` item disabled in the throwaway production, a `ForgetMemory` from web_user through `Commands.Submit` returned after 120.01 s with status OK and a CommandResult Ok 0, Outcome `failed` (`CommandsIn.TIMEOUT` is 120; the framework ends a timed-out synchronous send with an OK status and no response, `Ens.Host.queueRequestSync`). That is a hang for a page. After the fix, a `SearchMemory` in the same state returned after 20.01 s (`SEARCHTIMEOUT`) with status OK and Ok 0, Outcome `busy`; with the item enabled it returned Ok 1, `done` in 0.4 s.

**HTTP re-measure of the HIGH (warm stack e41s9iw, signed in over HTTP as the README account `ocutalon`):** `/state` 200, `/memory/precedents` 200, `/memory/items` 200 `{"items":[{ref,text,savedAt,source,pinned}],"total":1}` for a seeded memory, `/memory/items?q=zzquokka` 200 with the item (after the production was restarted onto the new `MemoryOps`; before that it was 500 because the old handler was still loaded), `?q=` 200. A mirror of the new e2e test (python over HTTP, a second fixture user with the user role): the second user lists none and finds none of the first's row, its forget is 404 and the row is kept, the first user's pin is 500 (no handler), its forget is 200 `{"result":"done"}`, then the row, the list and the search are empty and a second forget is 404. The Playwright test itself was only type-checked (`tsc -p tsconfig.e2e.json`) and listed (4 tests in the file); it needs the sign-in stack (over 150 s), so its run is left to CI (`live:sign-in`).

**Task 0 (measured on the warm stack e41s9iw, 2026-11-09):** a `PinMemory` (origin web_user, a fixture session, MemoryRef `zzunknownref`) through `Commands.Submit` to the running production gave status OK and a CommandResult with Ok 0, Outcome `failed` and Message "Something went wrong inside OcuTalon, so the command may not have finished." That is the predicted outcome, so the matrix row and Design Notes stand. The same session's `ForgetMemory` from web_user gave Ok 0, Outcome `not_found` (the real gate and the real `MemoryOps`).

## Auto Run Result

Status: done
Blocking condition: none

Summary (rework pass 1 of Story 41.9, the Planner's read-path ruling): the memory list now reads through `Ownership.Rows` (`memories`, `memory`, `memoryTotal` kinds, fixed SQL, owner check in WHERE), and a search is the new read verb `SearchMemory` (web_user only, no tool verb) handled by one `MemoryOps.OnSearch`, with a 20 s bounded wait that gives 503 `search_busy` (`MESSAGESEARCHBUSY`, pending the Planner's public-text approval). `Web.Api` no longer calls `Memory.List` or `Memory.Search`. A search is left out of the evaluation's command count. Four additive spine lines. The real-HTTP test as the README account with a second session is in `web/e2e/api/memory.spec.ts`.

Files changed in this pass:
- `Core/CommandsIn.cls` (Routes row, `SEARCHTIMEOUT`, `SendSearch`), `Data/Ownership.cls` (three kinds), `Eval/Report.cls` (exclusion), `Memory/Ops.cls` (one MessageMap entry, `OnSearch`), `Msg/Command/SearchMemory.cls` (new), `Web/Api.cls` (list, search, 503).
- Tests: `Test/Data/OwnershipMemories.cls`, `Test/Core/CommandsTimeoutProbe.cls` (new), `Test/Core/CommandsStep3.cls`, `CommandsStep3Probe.cls`, `Test/Eval/Report.cls`, `Test/Web/MemoryApi.cls`, `MemoryApiProbe.cls`; `web/e2e/api/memory.spec.ts`, `web/e2e/support/memory.ts`.
- The spine (four lines) and this spec.

Review findings: 27 reported. Patches applied: 3 (medium 2: the real `ListMemories` failure path, the `OnSearch` cross-session mutation line; low 1: the `ID DESC` tie-break), each with a mutation line. Deferred: 1 (medium: the 503 reads as the demo's busy state in the client, for 41.13), beside the pin-success e2e deferral for 41.12. Rejected: 23, each with its reason in the Review Triage Log.

Follow-up review recommended: false (no high patched; two medium and one low patched).

Verification (warm throwaway `e41s9iw`, torn down; no fresh stack started): `CommandsStep3`, `CommandsPrecedent`, `Test.Web.MemoryApi`, `Test.Web.Api` (skips `TestMessagesNoProductionIs500`, as before), `Test.Data.OwnershipMemories`, `Test.Eval.Report` and `Test.Memory.Ops` passed; after the patches `OwnershipMemories` and `MemoryApi` passed, and each new mutation went red and was reverted byte-identical. `test-class-rules.sh` and `test-boundaries.sh` passed; `lint_spine.py` at its baseline (ok false, 10 low findings). HTTP re-measure as the README account: `/memory/items` 200, a blank `q` 200, `?q=` 200 with the seeded item. `tsc -p tsconfig.e2e.json` clean; the Playwright run, `ci/checks.sh` and `live:sign-in` are left to CI.

Residual risks: the e2e pin step asserts today's 500 and goes red when 41.12 adds the handler (deferred to 41.12); the 503 search_busy text awaits the Planner's public-text approval, and the client reads a 503 as the demo-busy state (deferred to 41.13); a route that went back to `Memory.List` or `Memory.Search` would pass every unit test (they run privileged) and fail only the CI e2e; a warm stack needs its production restarted after `MemoryOps` is recompiled.
