---
title: "Story 41.9: Pins and learned saves get their verbs and routes"
type: 'feature'
created: '2026-11-09'
status: 'ready-for-dev'
baseline_revision: '95ab8336c1830227f42b51a9b24e150765478e84'
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
- AC 2 (AD-21, held): Given the save-memory AC for origin `system`, when this story is implemented, then this story leaves `SaveMemory` and its origins unchanged. The AC stays on 41.9 as waiting for 41.11, under Design Notes, for the lead.
- AC 3 (AD-4): Given a CSP session, when `GET /v1/memory/items` is called with and without `q`, then it answers only that session's rows with `source` and `pinned`, and never another session's. When the pin routes are called, they submit `PinMemory`/`UnpinMemory` with the session's `SessionRef` and map every outcome (`MemoryApi:TestItems`, `TestPin`, and the e2e spec).
- AC 4 (AD-1, AD-4, AD-13): Given `DELETE /v1/memory/items/:ref`, then it submits `ForgetMemory` with origin web_user for the session, and maps forgotten 200, not_found 404, not_built 501 and the rest 500. Another session's real row answers 404 not_found through the real `MemoryOps` and is still stored. Without the envelope, it is refused before anything is submitted (`MemoryApi:TestForgetMemory`, `TestForgetOtherSessionReal`, and the e2e spec). The spine holds the AD-1 note, and `lint_spine.py` stays at its baseline (`"ok": false`, exactly 10 low `placeholder` findings, nothing new).

## Spec Change Log

## Review Triage Log

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

**AC 2, for the lead (escalate, not a halt):** accepting `SaveMemory` from origin `system` with `Source` `learned` would need:
- a message-carried `Source`, which contradicts 41.8's rule (spec Always 1, and Decided in-stage: "a message-carried source for origin `system` is 41.11's, if it is ever built");
- a decision on Epic 19's trust rule, under which a non-`tool` row makes recall untrusted. That is Lane A.

41.11 is out of scope, and AD-31's amendment is undecided. The AC is kept as waiting for 41.11, not dropped. Dropping it or moving it is the owner's call.

**Decided in-stage:**
- The forget path is `DELETE /v1/memory/items/:ref`. `/v1/memory/:ref` would also catch `precedents` and `items`.
- There is no route pre-check for a memory row. Owner scope is `MemoryOps`' check ("through Memory.Ops", per the AC). The precedents route pre-checks through `Ownership.Precedent`, but `Data.Memory` is Lane A and AD-21 names `Memory.List`/`Search` as its reads.
- Items leave out `origin`.
- `q` is capped at 2,000 characters, the length of `Data.Memory.Text`.
- Search returns 5 items and List 20.
- The governance test extends `CommandsStep3`, which owns the memory verbs, rather than starting a new class.
- No `short-names.tsv` or `Msg/Catalog` line is needed: the precedent verbs have none.

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

**Security:**
- CSRF and same origin: the AD-13 envelope in `OnPreDispatch`, which all write routes use.
- Session check: `Ownership.SessionRef`, where no session gives 500, and 401 signed_out comes from `ApiBase`.
- Owner scope: list and search pass the session to `Memory.List`/`Search` (`WHERE SessionRef = ?`). Pin and forget carry only the server-side `SessionRef`, and `MemoryOps` matches the row's `SessionRef`.
- No new role or grant.

**Public text:**
- New: 409 `over_cap` "That would go over the 1,000-token limit. Unpin something first." (EXPERIENCE.md:1054).
- Reused, unchanged:
  - "OcuTalon has nothing at this address."
  - "This part of OcuTalon isn't built yet."
  - "Something went wrong inside OcuTalon. Try again."
  - the envelope refusals
  - CommandsIn's "That can't be done from the chat. Nothing was changed." and "OcuTalon can't take that command from here. Nothing was changed."

**Spine lines** (inserted bottom up, each marked `[ADDED 2026-11-09, Story 41.9]`; no Binds, Prevents or Rule wording changes):
1. The REST table, after line 1541:
   > `| `GET /api/v1/memory/items` (`q` blank: `Memory.List`, the newest 20 and `total`; else `Memory.Search`, the best 5), each `{ref, text, savedAt, source, pinned}`; `POST` and `DELETE /api/v1/memory/:ref/pin` submit `PinMemory` and `UnpinMemory`, and `DELETE /api/v1/memory/items/:ref` submits `ForgetMemory`, each with origin `web_user` through `CommandsIn` to `MemoryOps`, which scopes the ref to the CSP session's `SessionRef`; behind the AD-13 envelope [ADDED 2026-11-09, Story 41.9] | the memory operation (AD-21) |`
2. AD-33's cross-area table, after line 1395:
   > `| `OcuTalon.Msg.Command.ForgetMemory` (`MemoryRef`) also from origin `web_user`, submitted by the web layer through `Commands.Submit` for `DELETE /api/v1/memory/items/:ref` and routed by `CommandsIn` to `MemoryOps` (AD-1, AD-4) [ADDED 2026-11-09, Story 41.9] | B | Story 41.9 (`MemoryOps`' owner check, Story 19.3) |`
3. AD-1, after line 120:
   > `    - From Epic 41's second part `CommandsIn` also accepts `ForgetMemory` from origin `web_user`, for the Memory card's Forget (`DELETE /api/v1/memory/items/:ref`): the web layer sets the CSP session's `SessionRef` (AD-4) and `MemoryOps` forgets only that session's own row, so another session's ref answers `not_found`; origin `tool` keeps the context check above. `PinMemory` and `UnpinMemory` are accepted from origin `web_user` only. [ADDED 2026-11-09, Story 41.9]`

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
- AC 1: `PinMemory` origins `"web_user,tool"` makes `CommandsStep3:TestOrigins` go red.
- AC 2: none (held).
- AC 3: `MemoryItems` passes `""` as the session makes `MemoryApi:TestItems` go red.
- AC 4: drop `web_user` from ForgetMemory's origins, which makes `TestForgetOtherSessionReal` go red: the own row is refused not_allowed instead of forgotten. Also, `MemoryOps`' check is reached only through the real mode, so a route that answers 200 without submitting makes the same test go red, because the other session's row is expected to be kept and the route to give 404.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
