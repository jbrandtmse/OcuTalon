---
title: 'Story 25.3: Send a PDF, Word file or photo from the web app or Telegram'
type: 'feature'
created: '2026-11-12'
status: 'ready-for-dev'
baseline_revision: 'acb9c0459fc30bb6adf44f07cee69e5be18013ef'
planned_against: 'feature b8780de6094a8e8186718832d926e1dc721bfc68 (integrated into OCT-epic25)'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-25-context.md'
  - '{project-root}/_bmad/custom/skill-rules.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A user cannot send OcuTalon a file. Nothing stores a sent file, `OcuTalon.Msg.Item` has no file fields, Lane A's `TelegramIn` (Story 26.2) has no file-store call to use, and the CI Telegram mock refuses `getFile` with a 404 that points at this story (FR-54, UX-DR147).

**Approach:** Add Lane B's private file table `OcuTalon.Data.SentFile`, the file-store call `OcuTalon.Core.Files` (store with the size and type checks, owner-scoped open, Item fields, refusal texts) and four file fields on `Msg.Item`. Add `POST /api/v1/files` (`OcuTalon.Web.Files`), which stores the file and sends the Item through `WebChatIn`. `Conversation` takes a file Item as a turn, and `chat.message` carries the file. The composer gets a paperclip button and a drop on the chat. The CI mock gains `getFile` and the download path. The page refuses files before sending them. Sending files is off on the online demo (Planner ruling 1, option (a)). This spec is the first child of the approved split; the replies (Add to documents, the Saved to memory chip, the read-failure reply) are Story 25.6 (Planner ruling 2). Until Lane A's read path (Story 26.2) is merged, the paperclip and the chat drop stay hidden behind a `/v1/state` capability flag, and a file turn with no reader gets the fixed reply "I got {name}, but I can't read files yet." with no model call (Planner ruling 4). A file turn is untrusted provenance, the type is read from the bytes, no route serves a file's bytes back, and only a file's ref, name, type and size ever reach a log, the trace or a production message body (Planner ruling 3, four security conditions, each with a test). See Design Notes → Planner rulings (2026-11-12).

## Boundaries & Constraints

**Always:**
- Accepted: PDF, Word (.docx), JPEG and PNG, at most 10,485,760 bytes (`Web.Documents.#FILEMAX`, read, never copied). The media type comes from the bytes' signature (`%PDF-`; `PK\x03\x04` with a `.docx` name; `FF D8 FF`; the 8-byte PNG signature). A name whose extension names another type is `wrong_type`. Checks run in order size, empty, type, and every refusal comes before anything is stored.
- The `SessionRef` comes from the CSP session (`Ownership.SessionRef`) or, for Telegram, from the caller, and never from a request body. Every read of a `SentFile` row goes through `Ownership` (kind `sentFile`, `Ref` and `SessionRef` matched exactly).
- An Item and every production message carry the file's `Ref`, name, media type and size only, never its bytes or text (AD-4, AD-21). A file name renders as text only (AD-13).
- The upload is a JSON body (`clientId`, `name`, `content` in base64), never multipart (AD-25). It needs the custom request header and a matching `Origin` (AD-13), and declares its own `BodyBounds` of 13,985,112 bytes.
- On the online demo (`onlineDemo` 1) the route answers 409 `not_available` before the body is read, the page shows no paperclip, and a drop shows the off text. No file row is written on the demo.
- Lane B files only. Visible strings are exactly those in Design Notes → PUBLIC TEXT, as the Planner ruled them (rows 1-9 and the fixed reply, row 14).
- Security condition (i): a turn that carries a `SentFile` is untrusted provenance (`Msg.Enum` PROVENANCE `untrusted`, as for an email), even with empty text; only read-only tools may run in such a turn, and the marking is kept on the Item, the Turn and whatever 26.2 later builds from it. `Conversation` admits a file Item with untrusted provenance as the one exception to its untrusted drop; every other drop is unchanged.
- Security condition (ii): no route serves a stored file's bytes back (no GET, no download, no public or cross-session read); `Core.Files.Open` is a class call only, owner-scoped.
- Security condition (iii): the type check uses the bytes' signature, never only the name or the declared type; a renamed `.exe` or `.html` (any name, any declared type) is `wrong_type`, refused with PUBLIC TEXT row 4.
- Security condition (iv): nothing about a file reaches a log, the trace, the event log or a production message body except its ref, name, media type and size; the name is length-capped (255) and escaped wherever it is written into text.
- The gap (ruling 4): `/v1/state` carries a capability flag for sending files that is true only when Lane A's read path (Story 26.2) is present in the code (a code-level probe, never a setting a user can flip); on this branch it is false, so the paperclip and the chat drop are hidden on every install until 26.2 merges. As defence in depth, a file turn with no reader is answered with the fixed reply "I got {name}, but I can't read files yet." and makes no model call.

**Never:**
- No edit to `TelegramIn`, `Agent.Input`, `Docs.Extract` or any other Lane A class. No change to `Data.Upload` or its contract.
- No reply text other than the fixed no-reader reply; no Add to documents control, Saved to memory chip or read-result rendering (Story 25.6). No More to try item and no GUIDE.md or README line in this story (ruling 5: the line goes with 25.6 or 26.2).
- No route that returns a stored file's bytes (ruling 3 (ii)).
- No new role, grant, resource or web/Python dependency. Never widen `OcuTalonUser`. No `%Prepare` outside `Ownership.Rows`.
- No edit to `Msg/Catalog.cls`, `Msg/Catalog/Core.cls`, `ci/mock/server.mjs` or `ci/mock/test/helpers.mjs` (contended with Epic 21).
- No real Telegram bot and no api.telegram.org, only the CI mock. No test deleted, skipped, tagged off or shortened.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Send each type | OcuTalonUser; `POST /api/v1/files` with a valid `.pdf`, `.docx`, `.jpg`/`.jpeg`, `.png` | 202 `{"clientId","file":{"ref","name","mediaType","size"}}` with media types `application/pdf`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document`, `image/jpeg`, `image/png`. One `SentFile` row is written for the session, and one Item with Channel `web`, Provenance `untrusted` and the four file fields reaches `Conversation`. A queued Turn has `SentFile` set and is marked untrusted. `chat.message` and `/v1/state` carry `sentFile`. With no reader (this branch), the turn gets the fixed reply "I got {name}, but I can't read files yet." and no model request is made | No error expected |
| Too large | Content of 10,485,761 bytes or more, within the body bound | No row, no Item | 400 `bad_file`, `reason` `too_large`, `size` in bytes |
| Body over the bound | Body over 13,985,112 bytes (a 14 MB file) | Nothing parsed or stored | 413 `body_too_large` |
| Empty | Content of 0 bytes | No row, no Item | 400 `bad_file`, `reason` `empty` |
| Other type | `.txt`, `.md`, `.gif`, `.doc`, a `.png` name on PDF bytes, unknown bytes, a renamed `.exe` (MZ bytes) or `.html` named `x.pdf` or `x.png`, any declared type | No row, no Item | 400 `bad_file`, `reason` `wrong_type`; the page and `RefusalText` show PUBLIC TEXT row 4 |
| No reader | A file Item reaches `Conversation` while Lane A's read path is absent | Turn saved (untrusted); the fixed reply "I got {name}, but I can't read files yet." with `{name}` escaped; zero model requests (CI mock call count unchanged) | — |
| Capability flag | `/v1/state` on a local install on this branch | The flag is false; no paperclip, and a drop does nothing visible beyond today's behaviour; the route itself still works for the API tests | — |
| No byte read-back | `GET` on `/api/v1/files`, `/api/v1/files/<ref>`, any other path naming a file `Ref` | No route returns the bytes | 404 (no route) |
| Log and trace hygiene | A file whose bytes carry a marker string, and a name with `<script>` and 400 characters | The marker appears in no log, trace, event-log entry, production message body or Turn text; only ref, name (capped, escaped), type and size appear | — |
| Bad body | Not JSON; `name` missing, empty after trim, over 255 characters or holding a control character; `content` missing, not a string or not base64; `clientId` missing, empty or over 128 characters | Nothing stored | 400 `bad_file` with no `reason` |
| Duplicate clientId | Same `clientId` sent twice by one session | Second answer is 202 with the same `clientId`; no second row or Turn (the stored row is dropped when `WebChatIn` does not queue the Item) | — |
| Body sessionRef | A `sessionRef` key in the body | Ignored; the row belongs to the caller's session | — |
| Online demo | `onlineDemo` 1, any body within the bound | No row, no Item, no allowance consumed | 409 `not_available` with the off text |
| Envelope | No `X-OcuTalon-Request`, `text/plain`, a foreign `Origin` | Nothing read | 403 `no_request_header` / `not_json` / `wrong_origin` |
| Signed out / no role | No CSP session / no OcuTalonUser | — | 401 `signed_out` / 403 `no_role` |
| Telegram fixture | `Core.Files.Store(sessionRef, "telegram", name, stream, .file)` and `SetItem` | Same row shape, Channel `telegram`. The Item reaches `Conversation` as a turn of that session | Refusals as above, as codes; `RefusalText(code, size)` gives the PUBLIC TEXT sentence |
| Isolation | Sessions A and B each send a file | Each session's `/v1/state` and events hold only its own `sentFile`. `Core.Files.Open(refOfA, B)` finds nothing | — |
| Page refusals | The page picks or drops a file over 10 MB, of 0 bytes, or of another type | Nothing is sent. The PUBLIC TEXT refusal shows above the composer and is announced | — |
| Session end / purge | `SessionOps.End(A)`; the standard purge with `daysToKeep` | A's rows are dropped; rows older than `daysToKeep` are deleted | Errors returned as for `Upload` |
| Mock | Fixture file registered on the mock; `getFile`, then `GET /file/bot<token>/<file_path>` | `getFile` answers `{ok, result:{file_id, file_unique_id, file_size, file_path}}`, and the download returns the same bytes and content type. The log has the token's length only | Unknown `file_id`: 400 `{"ok":false,"error_code":400,"description":"Bad Request: invalid file_id"}`; unknown path: 404 |

</intent-contract>

## Code Map

Line numbers are on `acb9c045` (OCT-epic25, feature `b8780de6` integrated); `38f23542` changes no code (`git diff --stat acb9c045 38f23542 -- src web ci docker` is empty).

**Backend (Lane B; edit or add):**
- `src/ocutalon/cls/OcuTalon/Web/Documents.cls`, the sibling route:
  - `FILEMAX` :29 and `BODYMAX` :33; `XData BodyBounds` :68-73; `Add` :101-108.
  - `ParseBody` :245 reads `%FromJSON(..Characters(content))`, then `%Get("content",,"stream<base64")`. `Characters` :269 is `[Private]`, so make it callable with no behaviour change, or call it through `ParseBody`.
  - `ContentTypeOf` :305; `Refuse` :319; `Dispatch` :189-213 (Put, Submit, drop on a failure); `Sweep` :217.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - UrlMap `/v1/messages` :252 and `<Map Prefix="/v1/documents" …>` :288; the full-path `BodyBounds` entry :301. `Messages` :441 and `Post` :515 run `CreateBusinessService("WebChatIn")`. Error constants near :149-192 (`MESSAGENOTAVAILABLE` :192). Header doc bullets :3-101.
  - `ReportHttpStatusCode` :356 turns 404 into `not_found` and 405 into `method_not_allowed`. `%CSP.REST` `DispatchRequest` answers a known URL with a wrong verb through `Http405` (`irislib/%CSP/REST.cls` :435), and `Http405` :574 is overridable (not `Final`).
  - `StateBody` :1247-1302 (doc :1232-1246): `onlineDemo` :1269, `demoMode` :1270, then `models`. `telegram.included` :1277 reads `Channel.Telegram.In.Included()` :759, which turns off only through `^OcuTalonTest("TelegramIncluded")` (a precedent this story does not copy: Decided 13).
- `src/ocutalon/cls/OcuTalon/Web/BodyLimit.cls` `TooLarge` :68 (reads `class||BodyBounds`); `MAXBYTES` 262144.
- `src/ocutalon/cls/OcuTalon/Web/HookSettings.cls` :35-44: the "409 `not_available` on the online demo, before anything is read" precedent (`Data.Setting.Get("onlineDemo")`).
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Post.cls` (SessionRef, ClientId, Text, FromGuide) and `Channel/WebChat/In.cls` `Accept` :58-105. `Accept` checks a duplicate ClientId, calls `Allowed` :135 (`Core.Allowance.TryConsume`, a no-op off the demo), builds the Item :83-91 with `Provenance = "user"` :88 and sends it async to `Conversation`.
- `src/ocutalon/cls/OcuTalon/Msg/Item.cls`: 12 properties, no file fields (Lane B). Its doc :17: provenance is `user` for text the user writes, `untrusted` for everything else (AD-14).
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls` (897 lines):
  - `Take` :199-228 saves the queued Turn and publishes; `Untrusted` :243-251 drops provenance other than `user` (`DROPPROVENANCE` :141), no ItemId, `$ZStrip(Text)=""` (`DROPNOTEXT` :145) and no Session; the warning is `LOGDROPPED` :139.
  - `Begin` :350-372 joins the trace and sends the decide request; `Request` :387 calls `Intake.RequestFor`; `ItemOf` :393-404 rebuilds the Item from the Turn with `Provenance = "user"` hard-coded :399.
  - The fixed-reply path: `Conclude(turn, replyText, reason)` :684-699 saves done, then `Announce` :702 (chat.message), `Tell` :714 (Outbound to Notify) and `Next`. The fallbacks (`Conclude(turn, "", reason)`, the catalog key `FALLBACKKEY` :82) are the code-written replies that reach no model; the catalog is contended (Epic 21), so the no-reader reply goes through `Conclude` as `replyText`.
  - The test seam pattern: `Served` :503 ("a seam for the tests") and `RenderChecks` :564, overridden in `Test/Core/ConversationProbe.cls`.
- `src/ocutalon/cls/OcuTalon/Data/Turn.cls` (`^OcuTalonP.Turn`; `Tainted` :61; `Citations`/`Memories`/`Learned` are JSON-string precedents :79-87). `Live/Payload/ChatMessage.cls` `FromRow` :75, with the `Learned` part list :67/:102 as the model. Parts are in `Live/Payload/Part/`.
- `src/ocutalon/cls/OcuTalon/Data/Upload.cls`: the sibling table, never edited. `Put` :40, `DropSession` :81 (`%ExecDirect`), `Purge` :97 (a walk of `^OcuTalonP.UploadD`), storage :135-160. Its contract test is `Test/Core/UploadContract.cls`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: `Upload` :449 and kind `upload` :1350-1351 (the model for `sentFile`); `Rows`; `LocalFlag` :1096. Class doc :44.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` `EndDocumentsAndMemories` :599 and `DropUploads` :617/:639.
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` `Purge` :137-147 (Upload :141).
- `src/short-names.tsv` (the Upload row is :33). The `docker/tests/test-storage.sh` rules need a `DEFAULTGLOBAL` `^OcuTalonP.<Short>` row.
- `src/ocutalon/cls/OcuTalon/Bridge/Ids.cls` `NewRef()` (public Refs).

**The untrusted mechanism (read only; nothing here is edited):**
- `src/ocutalon/cls/OcuTalon/Core/Intake.cls` `RequestFor` :153-166 copies `item.Provenance` into `Bridge.Msg.Request.Provenance` :157 and renders `Agent.Input.Render(item, "", context)` :158.
- `src/bridge/cls/OcuTalon/Bridge/Context.cls`: `FIELDS` :18 carries `Provenance` from the request; `Begin(request, …)` :68, `End` :88, `Put` :112.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls` (Epic 22's area): `Decision` :171-200; the rule :183 denies every call that is not both `safe` and `readOnly 1` with `UNTRUSTED` :97 when `context.Provenance '= USERPROVENANCE` (`"user"`, :103) or the turn is tainted. Pinned by `Test/Bridge/Gate.cls` `TestUntrustedTurnRunsOnlySafeReadOnly` (doc :46; helpers `Begin(kind, provenance)` and `Sentence`).
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` :849 accepts any `Msg.Enum` PROVENANCE (`user,untrusted`, `Msg/Enum.cls` :9).
- `src/ocutalon/cls/OcuTalon/Agent/Input.cls` (Lane A) :6-9 renders any provenance other than `user` as quoted untrusted content; it has no `READSFILES` parameter (its parameters :195-219).
- So the Lane B marking is enough: a file Item and the Item that `ItemOf` rebuilds carry `untrusted`, and the gate already lets only safe read-only tools run in that turn. No Lane A or Bridge class changes.

**CI mock (Lane B; edit):**
- `ci/mock/mock.mjs`:
  - `BOT_PATH` :61; `handle` :630-640; `handleBot` :514-621.
  - The `getFile` refusal :561-563 and the header :21.
  - `shortPath` :187-190 rewrites only `^/bot`; `send` :246-251 is JSON or text only; `tokenLength` :530; `telegramControl` :324-393 (`replies` refuses `getFile` :379); `defaultAnswer` :198-210.
- `ci/mock/scenarios.mjs`: the doc :22-28; `TELEGRAM_REPLY_FIELDS` :41 and `BOT_METHODS` :42-43; the `getFile` refusal :212-213 and :24-25.
- `ci/mock/test/telegram.test.mjs`: pins :94 (log keys), :105-119, :135, :303, :317-318 and :347-354. `scenarios.test.mjs`: :58 and :253-263 (`BOT_METHODS` exact list). `server.test.mjs:619` (log keys). `docker/tests/test-mock.sh` runs them.
- `ci/compose.ci.yml:27` (`OCUTALON_TELEGRAM_API_BASE`). `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls` `TestTelegramBotApi` (`TELEGRAMBASE` :53), `LogMark` :471 and `LogSince` :484; `Test/Channel/BotApi.cls` `BotReply` :95.

**Web (Lane B; edit or add):**
- `web/src/app/chat/composer.ts`: the template :31-56, `onKey` :131-137, `send` :141, `reason` :110-113. `CHAT_TEXTS` (`chat/chat-view.ts:44`) is pinned by deepEqual (`scripts/chat-view.test.mjs:538-544`), so new texts go in a new file.
- `web/src/app/chat/chat-panel.ts`: the composer :163/:186; `onlineDemo = computed(() => this.live.snapshot()?.onlineDemo === true)` :311 is the model for `filesReadable`.
- `chat/chat-outbox.ts` :101-109 (refusals, `takeBack`); `api/api-client.ts` `postMessage` :132-142 and `addDocument` :246-248; `api/envelope.interceptor.ts:32` adds the header; `api/api-types.ts` `StateSnapshot` :43-69 (`onlineDemo` :59, `demoMode` :60).
- `web/src/app/documents/documents-page.ts`: the picker :64-68 and the drop handlers `dragOver` :321, `dragLeave` :328 and `dropped` :335 (CSS :122). `addFile` :419; `encode` :469 (private); `reasonOf` :447.
- `documents/documents-view.ts`: `REASON_TEXTS` :50-63 and `formatSize` :69 (exported: reuse).
- The user's turn rendering in `chat/chat-view.ts` (`TurnView` :138-143); the reply renders `replyText` as text. `web/src/app/live/payloads.ts` is generated by `web/scripts/payloads.mjs`.
- `web/src/app/settings/settings-view.ts:85` `offOnDemo` and `webhooks-section.ts:47` are the off-on-the-demo text precedent.

**Tests and shared surfaces (edit):**
- `Test/Data/Tables.cls` `XData Registry` :701 (Upload row :800-802), checked by `TestEveryTableIsRegistered` :46. `Test/Msg/Contracts.cls` :164-180 pins `Msg.Item`'s exact properties. `Test/Data/Ownership.cls` `TestIsolationEveryRowKind` :481-490.
- The `/v1/state` key order is pinned in three places: `Test/Web/Api.cls:132`, `web/e2e/api/api.spec.ts:135` and `web/e2e/frame/frame.spec.ts:607`.
- `Test/Core/ConversationProbe.cls` (Send seam, `RenderChecks` seam via `^OcuTalonTest("ConversationProbe", RunNumber, …)`, `ItemFor`), driven by `Test/Core/ConversationTurns.cls` (`TestUntrustedItemRefused` :1007 asserts no Turn, no call, no event).
- `Test/Eval/KeyProof.cls` `TraceHits(value, after, .places, .stats, namespace)` :268 exports every message header and body above a header ID as XML and counts the hits (-1 when a body can't be read). Throwaway and CI only (Rule 21), as `shard:lane-b` is.
- `web/e2e/support/api.ts` `changeSnapshot(page, change)` :27 (the `/state` rewrite the demo cases use, e.g. `frame/frame.spec.ts:244`); `web/e2e/support/memory.ts` `logMark` :196 and `triageRequests` :214 (reading the mock log through `LogSince`), `removeDecisionsOf` :249; `support/iris.ts` `irisScript`.
- Siblings to model: `Test/Core/SessionOpsDocuments.cls` (+`SessionOpsDropProbe`), `WebChatMessages.cls`, `Test/Web/DocumentsApi.cls` :100-125 (Map and `DispatchMap` assertions) and :248-371 (base64 cases; `TestList` forces `onlineDemo` and restores it), `DocumentsProbe.cls`.
- `Test/Docs/Samples.cls` (Lane A, read only): `Pdf` :99, `Docx` :290 (its entries include `word/document.xml`), `Zip` :243. No image builder exists, so tests build PNG/JPEG headers inline.
- `web/scripts/`: `ux-strings.test.mjs` `IMPORTED` :41-78; `floor-sources.test.mjs` `KEY_HANDLERS` :103-104, bindings :159 and the `BANNED` drag-and-drop allow-list :362-367 (only `documents-page.ts`); `api-client-sources.test.mjs`; `allowance-sources.test.mjs:107-109` (exactly 2 `aria-disabled` bindings in `composer.ts`); `payloads.mjs --check`.
- e2e: `e2e/api/memory.spec.ts` (`envelope`, `expectError`, `signInOverHttp`, `fixtureUser('LIVE'|'PANEL')`, PANEL isolation :225-233) and `e2e/api/body-limit.spec.ts`; `documents/documents.spec.ts` D5 (the early `filechooser` listener), D6 (a `DataTransfer` drop), D7/D8 (`setInputFiles` 11 MB/10 MB).
- `ci/units.sh`: `Test.Core`/`Data`/`Contract`/`Live` run in `image` (`shard:lane-b@Contract,Core,Data,Live`) and `Test.Web` in `shards-6` (`lane-b@rest`), with no edit. `web/e2e/files/` and `web/e2e/api/` join the `chromium` project (`live:sign-in`, `shards-10`) with no config edit.

**Planning (edit; this story's rows only):** `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: AD-4 sign-out sentence :194; AD-22 :851; AD-27 :1027; Conventions REST :1220; Tables paragraph :1418, at its end; cross-area table after :1492; REST table: the `GET /api/v1/state` rows :1614/:1629, and after :1657.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (implement, before any edit):
  - Re-check the Code Map anchors by name.
  - On slot A (`ocutalon-slot-a`, `OCUTALON`, `iris_server_info` first, read-only), record what `$Parameter("OcuTalon.Agent.Input", "READSFILES")` returns on build 154 for a parameter the class does not define (expected `""`, no error), and that `##class(%Dictionary.CompiledParameter).%ExistsId("OcuTalon.Agent.Input||READSFILES")` is 0. Record both in the Spec Change Log; if `$Parameter` errors, `Readable` checks `%ExistsId` first.
  - At the first compile of `Data.SentFile` and `Msg.Item`, confirm that the table, its columns and the `sentFile` statement prepare on build 154. If a name is an SQL reserved word, rename it and record the new name.
  - Take the `lint_spine.py` baseline.
- [ ] `src/ocutalon/cls/OcuTalon/Data/SentFile.cls` (new) and `src/short-names.tsv` -- add a persistent class with `DEFAULTGLOBAL "^OcuTalonP.SentFile"` and the row `SentFile ^OcuTalonP.SentFile OcuTalon.Data.SentFile B`. Properties `Ref` and `SessionRef` (EXACT, 22), `Channel`, `Name` (255), `MediaType` (128), `Size`, `Content As %Stream.GlobalBinary`, `CreatedAt`; indexes `RefIndex` (unique) and `SessionRefIndex`. Methods `Put(sessionRef, channel, name, mediaType, bytes, .sc)` returns the Ref; `DropSession(sessionRef)`; `Drop(ref, sessionRef)`; `Purge(daysToKeep, now)` deletes rows whose `CreatedAt` is older than `daysToKeep` days, with no SQL. -- AD-3, AD-27; Upload's shape, not its lifecycle (Design Notes, Rule 2).
- [ ] `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- add the Rows kind `sentFile` (`SELECT f.ID FROM OcuTalon_Data.SentFile f WHERE f.Ref = ? AND f.SessionRef = ?`), appended after `upload`, and `SentFile(ref, sessionRef, .sc)` beside `Upload`, with a class-doc line. -- AD-4, the one read path.
- [ ] `src/ocutalon/cls/OcuTalon/Core/Files.cls` (new; the file-store call) -- holds:
  - `Store(sessionRef, channel, name, content As %Stream.Object, Output file As %DynamicObject, Output sc) As %String`: `""` or the refusal code `too_large`/`empty`/`wrong_type`, checked in the order size, empty, type. The type comes from the bytes only: `%PDF-` (`application/pdf`), `FF D8 FF` (`image/jpeg`), the 8-byte PNG signature (`image/png`), and for Word `PK\x03\x04` plus the entry name `word/document.xml` in the bytes (`application/vnd.openxmlformats-officedocument.wordprocessingml.document`); the name's extension must name the same type (`.pdf`, `.jpg`/`.jpeg`, `.png`, `.docx`), else `wrong_type`. No declared type is read. The name goes through `SafeName` first; an empty result becomes `photo.jpg`/`photo.png`/`file.pdf`/`file.docx` by type. It writes the row through `SentFile.Put` and sets `file` = `{ref, name, mediaType, size}`. It writes nothing to any log.
  - `SafeName(name)`: removes control characters (`$ZStrip(…, "*C")`) and the Unicode bidirectional controls U+202A-U+202E and U+2066-U+2069 (as `$Char` escapes, Rule 14), trims white space and keeps the first 255 characters.
  - `Open(ref, sessionRef, Output sc)`: a `%Stream.TmpBinary` copy found through `Ownership.SentFile`, or `""`. The only reader of `SentFile.Content`.
  - `Describe(ref, sessionRef, Output sc) As %DynamicObject`: `{ref, name, mediaType, size}` of the session's row through `Ownership.SentFile`, or `""`; never the bytes. `Core.Files` is the only caller of `Ownership.SentFile`.
  - `SetItem(item As Msg.Item, file)`: sets the four Item fields, never `Text`.
  - `RefusalText(code, size)`: the PUBLIC TEXT sentences (size through a `SizeText` that writes "14 MB" as `Docs.Extract.SizeText` does; pinned equal to it).
  - `Readable(readerClass As %String = {..#READERCLASS}) As %Boolean`: 1 only when `$Parameter(readerClass, ..#READERPARAMETER)` is exactly 1, with `READERCLASS = "OcuTalon.Agent.Input"` and `READERPARAMETER = "READSFILES"` (Design Notes → For Story 26.2). The argument is the test seam; no caller in the product passes one.
  - `NoReaderText(name)`: `TEXTNOREADER` = "I got {name}, but I can't read files yet." with `{name}` replaced by `SafeName(name)` (PUBLIC TEXT row 14).
  - The parameters `FILEMAX` (= `##class(OcuTalon.Web.Documents).#FILEMAX`, by expression) and the texts.
  -- The one store for web and Telegram (AC 2); 26.2 calls `Store`/`SetItem`/`RefusalText` and 26.2/26.3 call `Open`.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Item.cls` and `src/ocutalon/cls/OcuTalon/Channel/WebChat/Post.cls` -- append `FileRef` (22), `FileName` (255), `FileMediaType` (128) and `FileSize` (`%Integer`) to both; storage only appends slots. Update Item's provenance doc line: an Item carrying a file is `untrusted`. -- AC 1, never bytes (AD-21's key proof stays true), AD-14.
- [ ] `src/ocutalon/cls/OcuTalon/Channel/WebChat/In.cls` -- `Accept` copies the Post's file fields onto the Item and sets `Provenance = "untrusted"` when `FileRef` is set (`user` otherwise, as today), and reports whether it queued the Item (a new output, so `Web.Files` can drop the row of a duplicate or refused send). A message's path is unchanged. -- Security condition (i), one way into Conversation.
- [ ] `src/ocutalon/cls/OcuTalon/Core/Conversation.cls`, `src/ocutalon/cls/OcuTalon/Data/Turn.cls`, `src/ocutalon/cls/OcuTalon/Live/Payload/Part/SentFile.cls` (new) and `Live/Payload/ChatMessage.cls`:
  - `Untrusted`: an Item with `FileRef` set is taken only when its Provenance is `untrusted` and `Core.Files.Describe(FileRef, SessionRef)` finds the row (new drop texts `DROPFILEPROVENANCE`, `DROPNOFILE`; they name no file); its text may be empty. Every other Item takes the checks as today.
  - `Take` sets `Turn.SentFile` (appended `%String(MAXLEN="")`, a JSON string `{ref,name,mediaType,size}`) from `Describe` (the row), never from the Item.
  - `ItemOf` sets `Provenance` to `untrusted` and the four file fields (`Core.Files.SetItem`) when the Turn has `SentFile`, `user` otherwise. A Turn with `SentFile` is the untrusted marking; no Provenance column is added.
  - `Reader()` (new, private, a test seam like `Served`): `Quit ##class(OcuTalon.Core.Files).Readable()`.
  - `Begin`: after `Join`, a Turn with `SentFile` when `'..Reader()` ends with `Conclude(turn, ##class(OcuTalon.Core.Files).NoReaderText(name), "")` and sends nothing to Decide (no decide request, no turn request). With a reader, the turn runs as any turn, untrusted.
  - `ChatMessage` gains `sentFile` (`Part.SentFile`: `ref`, `name`, `mediaType`, `size`) from `FromRow`. Regenerate `web/src/app/live/payloads.ts` with `node web/scripts/payloads.mjs`.
  - Update the class doc (the Item bullet, the file turn, the no-reader reply).
  -- Ruling 3 (i) and ruling 4; AD-6, AD-10, AD-14, AD-30.
- [ ] `src/ocutalon/cls/OcuTalon/Web/Files.cls` (new; `Extends OcuTalon.Web.Api`, mirroring `Web.Documents`) and `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - `Web.Files` has UrlMap `"" POST Send` only and `XData BodyBounds` `[{"method":"POST","url":"","bytes":13985112}]`. It overrides `Http405` to answer 404 `not_found` (no `Allow` header), so every other method on `/v1/files`, like every path below it, has no route (Decided 18).
  - `Send` checks, in order: (1) `onlineDemo` 1 gives 409 `not_available` with `Core.Files` off text, before the body is read; (2) it parses through `Web.Documents.ParseBody` (plus `clientId`), and any other body key (`sessionRef`, `mediaType`, `type`) is ignored; (3) a bad body gives 400 `bad_file` `MESSAGEBADFILE`; (4) `Core.Files.Store(SessionRef, "web", …)`, where a refusal gives 400 `bad_file` with `reason` and `size`; (5) a `Channel.WebChat.Post` with the file fields goes through `Web.Api.Post`; (6) if the Item was not queued (duplicate) or the send failed, it drops the row; (7) 202 `{"clientId","file"}`; a failure is 500 `server_error`. It logs nothing about the file.
  - The route does not read the capability flag: it works while the flag is false (Decided 15).
  - In `Web.Api`: `<Map Prefix="/v1/files" Forward="OcuTalon.Web.Files"/>` after the documents map; the full-path `BodyBounds` entry `{"method":"POST","url":"/v1/files","bytes":13985112}`; `StateBody` sets `filesReadable` (boolean, `Core.Files.Readable()`) right after `demoMode`; the header doc bullet for the route and the `StateBody` doc line.
  -- AD-13 envelope and bound; ruling 3 (ii); ruling 4.
- [ ] `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` and `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` -- `EndDocumentsAndMemories` also runs `SentFile.DropSession` (a step beside `DropUploads`, under the same "each step tried" rule), and the Web area's `Purge` calls `SentFile.Purge(daysToKeep)`. Update both doc comments. -- AD-4 (session end), AD-27 (standard purge).
- [ ] `ci/mock/mock.mjs` and `ci/mock/scenarios.mjs` -- remove the `getFile` refusals and add `getFile` to `BOT_METHODS`:
  - The control route `POST /_mock/telegram/files` `{fileId, filePath, contentType, base64}` registers a fixture file; `reset` clears the registry.
  - `getFile` answers from the registry (a queued scenario reply still wins); an unknown `file_id` gets the matrix's 400.
  - The route `GET /file/bot<token>/<file_path>`, matched before the model API branch: an empty token is 401; it serves the registered bytes with their `Content-Type` and `Content-Length` as a Buffer; an unknown path is 404; it is recorded in `calls` as `{method:'download', params:{file_path}}`.
  - `shortPath` also rewrites `/file/bot<token>/` to `/file/bot[redacted]/`; the log entry keeps the pinned keys and carries `tokenLength`. Update the file headers.
  -- AC 3, AD-22, NFR-11; new code in mock.mjs/scenarios.mjs only.
- [ ] `web/src/app/shared/file-encode.ts` (new) and `web/src/app/shared/file-drop.ts` (new) -- move `encode` out of `documents-page.ts` unchanged; add a `FileDrop` directive (`dragover`/`dragleave`/`drop` with the `Files` type check, a `dragging` class, a `files` output and an `active` input: when false it binds no handler, so the browser's default stays as today) holding the logic of `dragOver`/`dragLeave`/`dropped`. `documents-page.ts` uses both with no behaviour change (D5-D8 pass unedited). -- Rule 2.
- [ ] `web/src/app/chat/files-view.ts` (new, pure) -- `FILES_TEXTS` (PUBLIC TEXT rows 1-9; row 14 is not in it: the page shows it only as the reply's `replyText`); `ACCEPT_FILES = '.pdf,.docx,.jpg,.jpeg,.png'`; `checkFile({name,size})` returns `''` or `too_large`/`empty`/`wrong_type` (by extension only, size first; the server decides by the bytes); `refusalText(code, size)` with the imported `formatSize`; `fileLine(name, size)` gives "{name} · {size}"; `fileControls(filesReadable, onlineDemo)` returns `{paperclip, drop}`: `paperclip` is `filesReadable && !onlineDemo`, and `drop` is `'off'` on the online demo, `'send'` when `filesReadable`, else `'none'`.
- [ ] `web/src/app/api/api-types.ts` -- `StateSnapshot` gains `filesReadable: boolean` (doc line: true only when the install's code can read a sent file; Story 26.2), after `demoMode`.
- [ ] `web/src/app/chat/composer.ts`, `web/src/app/chat/chat-panel.ts`, `web/src/app/chat/file-chip.ts` (new), the user's turn rendering, and `web/src/app/api/api-client.ts`:
  - `chat-panel` computes `filesReadable` from the snapshot (the `onlineDemo` model :311) and `fileControls`. The paperclip `<button type="button">` before the textarea, with `aria-label` `FILES_TEXTS.send` and an inline SVG icon (`aria-hidden`), renders only when `paperclip`; it opens a hidden `<input type="file" multiple [accept]>`. The chat panel's `FileDrop` is active only when `drop` is not `'none'`; with `'off'` a drop shows the off text.
  - Each picked or dropped file is checked by `checkFile`. A refusal shows in a `<p class="file-refusal" role="status">` above the composer and is announced through the existing Announcer. A valid file is encoded and posted with `api.sendFile(clientId, name, content)` (POST `${BASE}/files`, body only). Files go one at a time. A 400 `bad_file` shows the refusal of its `reason` (so a renamed file that passed `checkFile` shows row 4 in row 3's frame), a 413 the size refusal, any other failure `FILES_TEXTS.notSent`.
  - The user's turn with `sentFile` shows `<app-file-chip>` (name and size as text); the reply renders as today.
  - Enter/Space on the paperclip opens the picker. The textarea's content is never touched. The Send button and the allowance bindings are unchanged.
  -- UX-DR129/147, NFR-25, ruling 4.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/SentFile.cls` (new) -- `Put`; `Ownership.SentFile` owner-scoped (B cannot find A's); `DropSession` drops only that session; `Purge` by age at the edge; storage under `^OcuTalonP.SentFile`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/Files.cls` and `src/ocutalon/cls/OcuTalon/Test/Core/FilesReaderProbe.cls` (new; the probe is a class with `Parameter READSFILES = 1;` and no Test methods, which the product never names) -- `Store`: each type by signature with every media type exact; 10,485,760 accepted and 10,485,761 `too_large` with no row; empty; each `wrong_type` row of the matrix, among them `MZ` bytes named `x.pdf`, `<html><script>` bytes named `x.pdf` and `x.png`, PDF bytes named `x.png`, and a zip without `word/document.xml` named `x.docx`; a default name; channel `telegram`. `SafeName`: a 400-character name holding `<script>`, a newline and U+202E is cut to 255 with the controls gone. `Open` owner-scoped; `SetItem` fields (and `Text` untouched); `RefusalText` for each code equal to the PUBLIC TEXT and to `Docs.Extract`'s frame; `NoReaderText` exact. Content marker absent from every Item property. `TestNoReaderYet`: `Readable()` is 0 on this branch and `READSFILES` is not defined on `Agent.Input` (the tripwire Story 26.2 flips); `Readable("OcuTalon.Test.Core.FilesReaderProbe")` is 1, and a class whose `READSFILES` is absent, 0 or `"1 "` gives 0.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/ConversationFiles.cls` (new; modelled on `ConversationTurns`) and `src/ocutalon/cls/OcuTalon/Test/Core/ConversationProbe.cls` (append a `Reader()` override: `^OcuTalonTest("ConversationProbe", RunNumber, "reader")` when set, else `##super()`) -- the integration AC:
  - a web file Item and a fixture Telegram file Item (built through `Store` and `SetItem`, Provenance `untrusted`) each become a queued Turn of their session with `SentFile` set from the row, and the queued `chat.message` carries `sentFile` with exactly the four keys;
  - `TestNoReaderReply`: with no reader (the real `Readable()`), each of the two turns ends done with `ReplyText` "I got {name}, but I can't read files yet." (the safe name), nothing is sent to Decide (zero calls to `Decide`), the done `chat.message` carries it, and one Outbound goes to Notify with that text and the turn's channel;
  - `TestReaderTurnIsUntrusted`: with the probe's reader set to 1, the decide and turn requests both carry Provenance `untrusted`, and `ItemFor` gives an untrusted Item with the four file fields; then `Bridge.Context.Begin` with the recorded turn request and `Bridge.Policy.Gate.Check` of `set_reminder` (not read-only) is denied with the gate's `UNTRUSTED` sentence (modelled on `Test.Bridge.Gate`'s helpers), and `Context.End`;
  - `TestFileItemDrops`: a file Item with Provenance `user`, one whose `FileRef` is another session's, and one with an unknown `FileRef` are each dropped (no Turn, no call, no event); an Item with no text and no `FileRef` is still dropped;
  - the content marker is in no recorded call (requests, Outbound) and no Turn field.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/FilesApi.cls` and `Test/Web/FilesProbe.cls` (new; modelled on `DocumentsApi`/`DocumentsProbe`) -- Dispatch: exactly one Map for `/v1/files`; `Routes("OcuTalon.Web.Files")` is exactly `POST  Send`; `DispatchMap` of GET/PUT/DELETE/PATCH on `""` and of every method on `/zzRef` is no route, and the wrong-verb answer is 404 `not_found`. Every matrix row at the route: each type 202 with the exact keys; `too_large`, `empty`, `wrong_type` (the renamed `.exe` and `.html` with a body `mediaType` of `application/pdf`) and the bad bodies with their exact codes; a body `sessionRef` ignored; a duplicate `clientId` with no second row. `onlineDemo` 1 gives 409 with the off text, nothing stored, no allowance consumed (forced and restored). 403 `no_role`. `TestStateFlagOff`: `StateBody` holds `filesReadable` false, as a boolean, right after `demoMode` (a tripwire 26.2 flips).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/SessionOpsDocuments.cls` -- add `TestSentFilesDropped` beside `TestUploadsDropped`. `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls` -- add `TestTelegramFileDownload`: register, `getFile`, download with `%Net.HttpRequest`, the bytes equal, and the mock log carries the token's length and not the token.
- [ ] Shared tests (Rule 19) -- update these:
  - `Test/Data/Tables.cls`: the registry row. `Test/Msg/Contracts.cls`: Item's four properties. `Test/Data/Ownership.cls`: the `sentFile` kind in `TestIsolationEveryRowKind`.
  - The `/v1/state` key order with `filesReadable` after `demoMode`: `Test/Web/Api.cls:132` (and there `filesReadable` equals `Core.Files.Readable()`), `web/e2e/api/api.spec.ts:135`, `web/e2e/frame/frame.spec.ts:607`.
  - `ci/mock/test/telegram.test.mjs` and `scenarios.test.mjs`: the `getFile` pins become the new behaviour, `BOT_METHODS` gains `getFile`, and new tests cover the registry, `getFile`, the download (bytes and type), the unknown id and path, the token by length on the download path, `calls` and `reset`.
  - `web/scripts/ux-strings.test.mjs`: `IMPORTED` gets `['chat/files-view.ts', ['FILES_TEXTS']]`, with `ux`/`ruled` sources (rows 1-9 as the Planner ruled them on 2026-11-12).
  - `floor-sources.test.mjs`: the drag-and-drop allow-list gains `shared/file-drop.ts` (its UX-DR129 reason: the paperclip is the first way), plus the key handler list if the paperclip adds one.
  - `api-client-sources.test.mjs`: `sendFile`'s exact body. `payloads.test.mjs` if it pins ChatMessage's fields.
  - `web/scripts/files-view.test.mjs` (new): `checkFile` (a `.pdf` name passes whatever its bytes), `refusalText`, `fileLine`, `fileControls` for the four combinations, `FILES_TEXTS` equal to `Core.Files`' text parameters and `TEXTNOREADER` equal to PUBLIC TEXT row 14 (read from the class source).
  - `web/scripts/files-sources.test.mjs` (new): over `src/ocutalon/cls/**/*.cls` outside `Test/`, only `Data/SentFile.cls`, `Data/Ownership.cls`, `Core/Files.cls`, `Core/SessionOps.cls` and `Install/Step/Web.cls` name the table (`OcuTalon.Data.SentFile` or `OcuTalon_Data.SentFile`); only `Core/Files.cls` calls `Ownership).SentFile(` and reads `.Content` of a row; no class under `Web/` names `Core.Files).Open`; `Web/Files.cls`'s UrlMap holds exactly one `<Route>` (`Url=""`, `Method="POST"`); `Core/Files.cls` and `Web/Files.cls` hold no `$$$LOG` macro.
  - `web/scripts/files-docs.test.mjs` (new; the 25.2 `history-docs.test.mjs` model): the SPINE ROWS present once each, with the REST row naming exactly the route that `Web.Files`' URL map serves and the state row naming `filesReadable`.
- [ ] `web/e2e/api/files.spec.ts` (new; real HTTP, modelled on `api/memory.spec.ts`; cleans its rows, Decisions and Turns in `finally`) -- the approved route tests (Design Notes → For the Planner 4: 401; LIVE 202 exact keys and its `/v1/state` `sentFile`; PANEL/LIVE isolation both ways; bad bodies and each code; 14 MB 413 and 10,485,761 bytes 400 `too_large`; the envelope 403s; the trace-only user 403 `no_role`; a body `sessionRef` ignored), plus:
  - (ii) GET, PUT, DELETE and PATCH on `/v1/files`, and every method on `/v1/files/<ref>`, `/v1/files/<ref>/content` and `/v1/documents/<ref>` (the ref of LIVE's stored file), answer 404 `not_found`, and no answer body holds the content marker;
  - (iii) `MZ` bytes named `setup.pdf` and `<html><script>` bytes named `page.png`, each with a body `mediaType` of `application/pdf`, answer 400 `bad_file` `wrong_type`, with no row;
  - (iv) hygiene: a mark taken first (the highest `Ens.MessageHeader` ID and `Ens_Util.Log` ID, and `logMark()`), then a PDF whose bytes hold a fresh marker and whose name is `zz<script>x-<n>.pdf`, then a 400-character name (refused 400, nothing stored); once the turn is done, `Test.Eval.KeyProof.TraceHits(marker, mark)` is 0 while `TraceHits(<the file's ref>, mark)` is at least 1 (the positive control); no `Ens_Util.Log` row after the mark holds the marker, the name or the 400-character name; the Turn's `Text` is empty and its `SentFile` has exactly the four keys and no marker; no mock log entry after the mark holds the marker;
  - ruling 4: `/v1/state` `filesReadable` is false (a tripwire 26.2 flips); the file turn's done `chat.message` has `replyText` "I got zz<script>x-<n>.pdf, but I can't read files yet."; the turn's ItemId has no Decision of kind `decide` or `turn`, and no mock `POST /v1/messages` entry after the mark holds the file's name.
- [ ] `web/e2e/files/files.spec.ts` (new; chromium; every case stubs `/state` with `changeSnapshot`, setting `filesReadable` and `onlineDemo` explicitly, so no case depends on this branch's flag) -- with `filesReadable: true`:
  - the paperclip by keyboard (Tab, Enter, the early `filechooser` listener; its accessible name "Send a file") for PDF, DOCX, JPEG and PNG fixture buffers with real signatures; each shows the user's file chip (name and size) and the reply "I got {name}, but I can't read files yet.", and both survive a reload;
  - a drop as the second way;
  - 14 MB: "That file is 14 MB; the limit is 10 MB.", with no request sent (counted with `page.route`); `.txt` and an empty `.pdf` with their texts;
  - `MZ` bytes named `setup.pdf`: the page sends it, and shows "I couldn't read that file: it isn't a PDF, Word (.docx), JPEG or PNG file."; no chip;
  - names holding `<b>` and `<script>` (no `/` in a name) render as text in the chip and the reply (no such element in the chat);
  - with `filesReadable: false`: no paperclip, and a dispatched drop sends no request and shows no refusal or off text;
  - with `onlineDemo: true` (and `filesReadable` true): no paperclip, and a drop shows the off text;
  - a PANEL session never sees LIVE's file.
- [ ] `ARCHITECTURE-SPINE.md` -- write the rows in Design Notes → SPINE ROWS. Refresh `updated:` and run `lint_spine.py`. No `.memlog.md` exists (25.2): record that, and create nothing.

**Acceptance Criteria:**
- AC 1: Given a local install whose `/v1/state` says `filesReadable` true, when the user presses the paperclip (by mouse, or Tab then Enter/Space) or drops a file on the chat, then a PDF, .docx, JPEG or PNG is posted to `POST /api/v1/files` with the custom request header and a matching `Origin`, stored in `SentFile`, and becomes an Item with its `Ref`, name, media type and size and no bytes; the user's message shows the file's name and size. The paperclip has an accessible name, and the drop is never the only way.
- AC 2: Given a fixture Telegram file passed to `Core.Files.Store` with channel `telegram`, when its Item (from `SetItem`, Provenance `untrusted`) reaches `Conversation`, then the same `SentFile` row shape and the same kind of Item and Turn result, and `RefusalText` gives the PUBLIC TEXT for each refusal. `TelegramIn` is untouched.
- AC 3: Given a fixture file registered on the CI mock, when a client calls `getFile` and then downloads `/file/bot<token>/<file_path>`, then it gets the file's path and the exact bytes and content type, and the mock's log and summary carry the token's length only.
- AC 4: Given a file over 10 MB, of 0 bytes or with another extension, from the page or through `Store`, when it arrives, then nothing is stored or sent: the page shows "That file is 14 MB; the limit is 10 MB." (with its size) or "I couldn't read that file: {reason}.", and the route and `Store` answer the matching code.
- AC 5: Given a file whose bytes are not a PDF, Word file, JPEG or PNG (a renamed `.exe` or `.html`), whatever its name and any declared type, when it reaches the route or `Store`, then it is refused `wrong_type` with nothing stored, and the page, whose pre-check passed it by its extension, shows "I couldn't read that file: it isn't a PDF, Word (.docx), JPEG or PNG file." (ruling 3 (iii)).
- AC 6: Given the online demo, when a visitor opens the chat, then there is no paperclip, a drop shows the off text, and `POST /api/v1/files` answers 409 `not_available` with nothing stored or counted.
- AC 7: Given two sessions that each send a file, when either reads `/v1/state` or its events, then it sees only its own `sentFile`; `Core.Files.Open(refOfA, B)` finds nothing; at its sign-out the session's rows are dropped, and the standard purge deletes rows past its days.
- AC 8: Given a file Item from either channel, when `Conversation` takes it, then it is admitted only with Provenance `untrusted` and a `FileRef` of its own session, its Turn is marked untrusted (`SentFile`), and every request built from that Turn carries Provenance `untrusted`, in which the gate denies every tool that is not safe and read-only (ruling 3 (i)).
- AC 9: Given a stored file, when any method is sent to `/api/v1/files` other than POST, or to any path naming the file's `Ref`, then the answer is 404 with no byte of the file, and `Core.Files.Open` (owner-scoped) is the only reader of its bytes (ruling 3 (ii)).
- AC 10: Given a file whose bytes hold a marker and a name holding `<script>`, when it is sent and its turn ends, then the marker is in no production message body, event-log entry, Turn field or mock log entry, only the ref, name, media type and size are, and the name renders as text; a name over 255 characters is refused at the route and cut to 255 by `Store` (ruling 3 (iv)).
- AC 11: Given this branch (no `READSFILES` on `Agent.Input`), when the page loads `/v1/state` or a file turn runs, then `filesReadable` is false, the paperclip and the chat drop are not there, and the file turn's reply is "I got {name}, but I can't read files yet." with no model request (ruling 4).
- AC 12: Given the spine, when this story merges, then its REST, tables, state and cross-area rows (SPINE ROWS) are present.

## Spec Change Log

- 2026-11-12 (lead, spec gate): the Contest Planner's rulings (`story-253-rulings-20261112.md`) written into the intent contract and Design Notes; status reset to `draft` for a re-plan on this spec path. Rulings: demo OFF (a); split to Story 25.6 approved (inserted into epics.md); veto items approved with four security conditions, each with a test; the gap closed by a `/v1/state` capability flag (true only once 26.2's read path is merged) plus a fixed no-model reply; PUBLIC TEXT rows 1-9 approved verbatim, plus the fixed reply; rows 11-13 go with 25.6/26.2. Decided 6, 10 and 11 and For the Planner 8 are superseded where they differ.
- 2026-11-12 (plan, re-plan, cycle iteration 2): everything outside the intent contract re-derived to the rulings. Added: the untrusted marking through Lane B only (WebChatIn, `Conversation.Untrusted`/`ItemOf`; the existing gate rule does the rest), the no-reader branch in `Begin`, `Core.Files.Readable`/`NoReaderText`/`SafeName`/`Describe`, `filesReadable` in `/v1/state`, `Web.Files`' 404 for every other method, the byte-only Word check, the hygiene and no-read-back tests, the page's `fileControls`, AC 5 and AC 8-11. Dropped: Task 0's `Agent.Input.Render` measurement (no model call now), the e2e Tab-walk and locator edits and the `live floor` run (the paperclip is hidden on every real state; For Story 26.2). KEEP: the approved route-test list, the demo OFF pins, the mock design, the Upload-shape table.

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6):**
- AD-1: the Item is a production message; `WebChatIn` is the way in.
- AD-3: a private global and a short-names row.
- AD-4: ownership reads, no client `SessionRef`, the sign-out drop; `Core.Files` is the only caller of `Ownership.SentFile`.
- AD-6: the Decide request carries rendered input and code-written fields only; a no-reader file turn sends none.
- AD-10: an untrusted turn lets only safe read-only tools run (the gate's rule, unchanged); a later fresh session follows the reply's `Tainted`.
- AD-12: the `chat.message` payload and the generated types.
- AD-13: the envelope, `BodyBounds`, the error codes, text-only names.
- AD-14: Channel and Provenance; a file is not text the user writes, so its Item is `untrusted` (Msg/Item.cls :17).
- AD-19: `onlineDemo`; the bot token from the environment.
- AD-20: the allowance (unreached while files are off on the demo).
- AD-21: no stream in a message body; Upload unchanged.
- AD-22: the CI mock; the token by length.
- AD-25: a JSON body, not multipart; the golden copy.
- AD-26: the trace session the hygiene scan reads.
- AD-27: the standard purge.
- AD-29: Lane B files only; `TelegramIn`, `Agent.Input` and the bridge's gate are read, never edited.
- AD-30: `Conclude`'s order (done and saved, chat.message, Notify, next turn) for the no-reader reply.
- AD-33: the rows land in the same change.
- No AC contradicts an AD Rule.

**Rule 1/2.**
- Integration AC: `Conversation` (a real instance, `Test.Core.ConversationFiles`) reads the web Item and the fixture Telegram Item and produces a queued untrusted Turn, a `chat.message` carrying `sentFile`, and the no-reader reply with no Decide call. The page (`files/files.spec.ts`, against the real route) reads that event and the snapshot and shows the chip and the reply.
- Consumed-by:
  - Story 26.2: `TelegramIn` calls `Core.Files.Store`, `SetItem` and `RefusalText`; `Agent.Input` reads the Item's file fields and `Core.Files.Open`, and defines `READSFILES` (For Story 26.2); its download test uses the mock's `getFile` and download path.
  - Story 26.3: photo Items and `Open` for the image bytes.
  - Story 25.6: the replies; Add to documents through the documents route by `Core.Files.Open`.
- Consumes: `Web.Documents` (`FILEMAX`, `ParseBody`); `Web.BodyLimit`; `Web.Api.Post` and `WebChatIn.Accept`; `Ownership.Rows`; `SessionOps.EndDocumentsAndMemories`; `Install/Step/Web.Purge`; `Bridge.Ids.NewRef`; `Intake.RequestFor` and `Bridge.Policy.Gate` (read only); `documents-view.ts` `formatSize`; `documents-page.ts` `encode` and the drop logic, both extracted; the Announcer; `Test.Web.Api.Written`; `Test.Eval.KeyProof.TraceHits`; `Test.Contract.Mock.LogMark`/`LogSince`.
- Siblings, extended or copied with a reason:
  - `Data.SentFile` copies `Data.Upload`'s shape (`Put`/`DropSession`/no-SQL `Purge`, about 50 lines), not its lifecycle. Upload is take-once with a one-hour purge, pinned by `UploadContract` and AD-21; a shared base would change that pinned storage contract, and a file's row is read many times until sign-out or the purge.
  - `Web.Files` calls `Web.Documents`' `ParseBody`/`FILEMAX`/`BODYMAX` and does not copy them. Its own refusals differ: other types, the code `bad_file`, a demo refusal.
  - The page extracts `encode` and `FileDrop` from the Documents page and imports `formatSize`. The mock's download path reuses `shortPath`/`redact`/the calls log. `Part.SentFile` follows `Part.Learned`.
  - The `Reader()` seam extends `Conversation`'s seam pattern (`Served`, `RenderChecks`) and `ConversationProbe`'s override; the hygiene scan reuses `KeyProof.TraceHits` rather than a second trace walker.

**Ledger inbox:** none.

**AC evidence already met:** none of the ACs is met on this branch. The prerequisites are built: the body-bound mechanism (`Web.BodyLimit`, 34.2), the extraction and its failure frame (19.6, `Docs/Extract.cls`), the allowance (`Core.Allowance`), the sign-out drops (`SessionOps` :599) and the gate's untrusted rule (`Gate.cls` :183).

**Seams (read results).** Reading a file is Lane A's (19.6 built; 26.2 and 26.3 not merged). This story's seam ends at the Item, `chat.message` `sentFile`, the no-reader reply and the `READSFILES` probe. No read result is rendered here (25.6). The Telegram path is proven with a fixture Telegram file Item through `Store`, never through `TelegramIn`.

**The untrusted mechanism (security condition (i)).** The code restricts tools for untrusted input in one place: `Bridge.Policy.Gate.Decision` :183 denies every call that is not `safe` with `readOnly 1` when the turn context's Provenance is not exactly `user` (an email, a webhook, Intake's turns, Digest's summary) or the turn is tainted. The context's Provenance is the request's (`Bridge.Context` FIELDS), and the request's is the Item's (`Intake.RequestFor` :157). So 25.3 marks on the Lane B side only: WebChatIn sets `untrusted` on a file Item; `Conversation.Untrusted` admits a file Item only when it is `untrusted` and its `FileRef` is the session's; the Turn's `SentFile` is the marking; `ItemOf` rebuilds an `untrusted` Item with the file fields, so every decide and turn request of that Turn is untrusted. In 25.3 no file turn reaches Decide at all (`Begin`'s no-reader branch), so no tool can run; `TestReaderTurnIsUntrusted` forces the reader on through the probe to pin the provenance of the requests and the gate's denial. No Lane A, Bridge or Epic 22 class is edited.

**For Story 26.2 (what it must provide and keep):**
1. Provide `Parameter READSFILES = 1;` on `OcuTalon.Agent.Input`, in the same change in which `Agent.Input.Render` renders a file Item (its `FileRef` read through `Core.Files.Open`, the text through `Docs.Extract`) as quoted untrusted data, and never before. `Core.Files.Readable()` reads exactly that value (1 and nothing else), and `/v1/state` `filesReadable` and the page's paperclip and drop follow it with no Lane B edit.
2. Flip the three tripwires that pin "false on this branch" in the same change: `Test.Core.Files` `TestNoReaderYet`, `Test.Web.FilesApi` `TestStateFlagOff`, and the state case of `web/e2e/api/files.spec.ts`.
3. Keep the marking: every file Item `TelegramIn` builds has Provenance `untrusted`, its fields set by `Core.Files.SetItem`, and a `FileRef` that `Core.Files.Store` returned for that session (else Conversation drops it); never re-set a file turn's request to `user`; keep `Intake.RequestFor`'s copy of the Provenance and `Agent.Input`'s quoted rendering of any provenance that is not `user`; leave the gate's rule as it is.
4. Once the paperclip shows on a real state, the composer has two buttons and one more Tab stop. Then locate Send by name at `web/e2e/floor/keyboard.spec.ts:384` and `floor/devices.spec.ts:101,202`, and add the paperclip stop (before the textarea) to the walks at `frame/frame.spec.ts:116,177-191`, `floor/layout.spec.ts:172`, `floor/focus.spec.ts:196`, `chat/chat.spec.ts:194-196` and `banners/banners.spec.ts`; `allowance-sources`' count of 2 stays (the paperclip has no allowance binding).
5. The no-reader branch stays for any build where `Readable()` is 0; with a reader the turn runs through Decide as any turn, untrusted.

**Decided in-stage:**
1. A new table, not `Data.Upload` (Rule 2 above). Named `SentFile`, not `File`, to stay clear of SQL's FILE (Task 0 confirms).
2. Media types are the IANA ones, read from the bytes' signature, and the extension must name the same type. ~~A `.docx` needs the zip signature and the `.docx` extension~~ (superseded by 20).
3. The route is `POST /api/v1/files` with `{clientId, name, content}`. A new code `bad_file` (with `reason` and `size`) mirrors `bad_document`. Over the bound is 413, as everywhere.
4. The page checks size, then empty, then extension before it sends, because a 14 MB file's body (about 18.7 MB) would only get a 413. The server decides by the bytes.
5. A file is sent alone. The composer's text stays in the composer; several picked or dropped files go one at a time, each its own Item, as the Documents page does.
6. ~~Provenance `user`~~ Superseded by ruling 3 (i): a file Item is `untrusted`.
7. The refusal texts live in `Core.Files` parameters and `FILES_TEXTS`, not in the contended `Msg/Catalog/Core.cls` (the `Docs.Extract` precedent). A test pins them equal.
8. No visible drop hint (34.2's Decided 10: no unsourced text). The chat outlines while dragging, as the Documents page does.
9. `Turn.SentFile` is a JSON string (the `Citations` precedent), so a reload shows the chip even after the file row is purged.
10. The paperclip comes before the textarea and carries no allowance binding, so the pinned count of 2 holds. ~~Hidden only on the demo~~ (superseded by ruling 4: hidden unless `filesReadable`, and on the demo).
11. No More to try item, no GUIDE.md or README line (ruling 5). No new live unit: the new classes join `image` and `shards-6`, the specs join `live:sign-in` (`shards-10`), the node tests run in the hosted `web` job. `new_units: none`.
12. The demo pin is class-level (`FilesApi`, `onlineDemo` forced and restored) plus the chromium spec with `/state` stubbed; no `e2e-online` test (`live:online-demo` has no `--part` and takes about 9 minutes).
13. The capability flag is `filesReadable` (boolean, after `demoMode`): `Core.Files.Readable()`, 1 only when `Agent.Input`'s `READSFILES` is exactly 1. It is a code probe only; the page combines it with `onlineDemo` (`fileControls`). A class parameter rather than a method name, so that 26.2 states the capability in one reviewed line and the probe needs no signature. No `^OcuTalonTest` override (the `Telegram.In.Included()` precedent): a global left set would show the paperclip with no reader.
14. Test seams, never a setting: `Readable(readerClass)`'s argument with `Test.Core.FilesReaderProbe`; `Conversation.Reader()` overridden by `ConversationProbe`; the chromium specs stub `/state` (`changeSnapshot`). The e2e paperclip flow therefore runs against the real route with the real no-reader reply.
15. The route does not read the flag: it serves the API tests while the flag is false, and it is still behind the role, the envelope and the demo check. The flag hides UI only.
16. The no-reader reply is `Conclude(turn, NoReaderText(name), "")`: a code-written `ReplyText` published and sent like every concluded turn (chat.message, Outbound to Notify), because the fallback's catalog key lives in the contended catalog. Neither the decide nor the turn request is sent, so no model is called and no Decision or Usage row is written. The Turn is not marked `Tainted`: no file content reached an AI session. The text is `Core.Files` `TEXTNOREADER`, not in `FILES_TEXTS` (the page shows it only as the reply's text); pinned by `Test.Core.Files`, `ConversationFiles` and `files-view.test.mjs`.
17. The untrusted marking is `Turn.SentFile` (no Provenance column: the approved columns only). `Conversation` admits a file Item only when it is `untrusted` and `Core.Files.Describe` finds its `FileRef` in the session, and builds `SentFile` from the row; a file Item with Provenance `user` is dropped (it names a caller bug and fails safe).
18. Every method on `/v1/files` other than POST is 404 `not_found` (the frozen matrix row), through `Web.Files`' `Http405` override; `Web.Api`'s 405 elsewhere is unchanged.
19. `SafeName` (control and bidirectional characters removed, trimmed, 255 at most) runs in `Store` for every caller. The route still refuses a name over 255 characters or holding a control character with 400 `bad_file` (the frozen bad-body row); the reply and the chip show the safe name as text, and no channel renders it as markup (Telegram sends plain text, the page interpolates).
20. Word is `PK\x03\x04` plus the entry name `word/document.xml` in the bytes plus a `.docx` name, so the bytes decide (ruling 3 (iii)) and a renamed zip is `wrong_type`.
21. The hygiene scan reuses `KeyProof.TraceHits` with a positive control (the file's ref is found), reads `Ens_Util.Log` after a mark by SQL, and the mock log through `LogSince`. The console log is not scanned (no file code writes to it; a 500 writes only a status).
22. The Tab walks and composer locators are unchanged in this story (the paperclip is not rendered on any real state); their update is 26.2's (For Story 26.2, 4). `live floor` is therefore not in Verification.

### Planner rulings (2026-11-12, Contest Planner under the owner's delegation; binding)

1. Demo: (a) OFF as planned: the route returns 409 `not_available` before reading the body, the paperclip is hidden, a dropped file shows text 6, all pinned. Telegram never runs on the demo.
2. Split to Story 25.6 APPROVED (inserted into epics.md, with the moved ACs and markers). U-326 (the reply-contract AC added to 37.1, DW-1231) stands. `getFile` stays in 25.3.
3. Veto items APPROVED (route, `SentFile`, appended columns, payload and error code, CI mock, spine appends), plus FOUR SECURITY CONDITIONS, each with a test: (i) a turn that carries a `SentFile` is UNTRUSTED provenance from 25.3 on, even with empty text: only read-only tools run in that turn (as for a failed message or an email); when 26.2 reads the content, it keeps that marking. (ii) No route serves a stored file's bytes back, except possibly to its own session; no public or cross-session download (this story adds none at all). (iii) The type check uses the file's bytes, never only the name or the declared type; a renamed .exe or .html is refused with text 4. (iv) Nothing about a file goes into any log, trace or production message body except ref, name, type and size; the name is length-capped and escaped. The real-HTTP test list is approved as written.
4. THE GAP: don't ship a half feature. Hide the paperclip and the chat drop behind a `/v1/state` capability flag that turns on only when 26.2's read path is merged. Defence in depth: a file turn with no reader gets a fixed code reply "I got {name}, but I can't read files yet." and NO model call. A judge on a local install must never see the model reply to an empty message. (Supersedes For the Planner 8's recommendation and Decided 10's "the paperclip is hidden only on the demo".)
5. GUIDE "New since" line goes with 25.6 or 26.2, whichever makes it true; line 13 approved, each clause only once its story has merged. Not in 25.3.
PUBLIC TEXT: rows 1-9 approved verbatim; rows 11 and 12 go with 25.6; row 13 under (5); plus the fixed reply (row 14).

### For the Planner (spec gate, as sent; ruled above)

Items 1, 2, 5, 7 and 8 were ruled (rulings 1, 2, 5 and 4; item 7 was the lead's numbers: 16 More to try items, none added). Kept as sent:

3. **Veto items** (approved by ruling 3). Each lists its online-demo behaviour.
   - **Route** `POST /api/v1/files`: any OcuTalonUser behind the AD-13 envelope. It stores only under the caller's own session and returns only that file's `{ref,name,mediaType,size}`. No route reads a file back. Demo: 409.
   - **Table** `OcuTalon.Data.SentFile` (`^OcuTalonP.SentFile`, private database): retention the standard purge's `daysToKeep`; session end `DropSession`; reset: the golden copy holds none; Purge: Web area. Demo: never written.
   - **Columns**: `Msg.Item` +`FileRef`, `FileName`, `FileMediaType`, `FileSize`; `Channel.WebChat.Post` +the same four; `Data.Turn` +`SentFile` (JSON). Every one is an appended slot.
   - **Payload**: `chat.message` +`sentFile` (no new event type). **Error code**: `bad_file`, a Conventions row.
   - **Privileges, roles, grants, resources**: none. **Dependencies**: none.
   - **CI mock**: `getFile`, the download path, the control route `POST /_mock/telegram/files`, and `BOT_METHODS` +`getFile`.
   - **Spine Rule text**: an append to AD-4's sign-out list, AD-22 :851 (now built), and AD-27's Web-area purge list (SPINE ROWS). No new AD; the contracts are rows of the existing tables.
   - The re-plan adds no veto item: `filesReadable` and the `READSFILES` probe are ruling 4's flag (a state key, no stored data), and their spine rows document it.
4. **Standing real-HTTP route tests** (`web/e2e/api/files.spec.ts`; approved as written):
   1. signed out on POST gives 401 `signed_out`;
   2. LIVE (OcuTalonUser) gets 202 with exactly `clientId` and `file{ref,name,mediaType,size}`, and LIVE's `/v1/state` shows the `sentFile`;
   3. second-session isolation both ways: PANEL's state and events never show LIVE's file, and LIVE's never show PANEL's;
   4. invalid parameters: every bad-body row and each refusal code, with the exact `{error:{code,message},reason,size}`;
   5. the body bound: a 14 MB body gives 413 `body_too_large`, and 10,485,761 bytes within the bound gives 400 `too_large`;
   6. the envelope: no `X-OcuTalon-Request` gives 403 `no_request_header`, `text/plain` gives 403 `not_json`, and `Origin: http://evil.example` gives 403 `wrong_origin`;
   7. `OCUTALON_TRACEONLY_USER` gives 403 `no_role`;
   8. a body `sessionRef` is ignored.
   The demo's 409 is class-level (Decided 12). The re-plan adds the cases of security conditions (ii)-(iv) and ruling 4 (Tasks).
6. **Contended overlaps** (re-checked at the re-plan):
   - Epic 21: `Test/Data/Tables.cls` (Epic 21 edits the Delivery row near :452; this story appends near the Upload row :800). `ARCHITECTURE-SPINE.md` (Epic 21 edits :499-507, :655-659 and :864, near this story's AD-22 :851 edit; Epic 22 edits :384). This story's new state row goes after :1629, away from both.
   - Epic 22: `Bridge/Policy/Gate.cls`, `Bridge/Context.cls` and `Test/Bridge/Gate.cls` are read and called from a test, never edited.
   - `ci/mock/`: Epic 21's `server.mjs` and `helpers.mjs` and Epic 22's `constants.test.mjs` are not touched; this story edits `mock.mjs`, `scenarios.mjs`, `telegram.test.mjs` and `scenarios.test.mjs` only.
   - New at the re-plan, none contended: `Test/Web/Api.cls`, `Test/Core/ConversationProbe.cls`, `web/e2e/api/api.spec.ts`, `web/e2e/frame/frame.spec.ts` (one key list), `web/src/app/api/api-types.ts`. Dropped: the floor, chat and banners walk edits. The catalog, `Test/Web/SettingsApi.cls`, `web/src/app/settings/**`, README and GUIDE.md are not touched.
9. **CI groups:** no new live unit (`new_units: none`). `Test.Core.Files`, `Test.Core.ConversationFiles`, `Test.Data.SentFile` and the `Test.Contract.Mock`/`Test.Core.SessionOpsDocuments` additions join `image` (`lane-b@Contract,Core,Data,Live`); `Test.Web.FilesApi` and the `Test.Web.Api` change join `shards-6`; the two specs join `live:sign-in` in `shards-10` (if it has no room, add `files` to `SIGN_IN_2_DIRS`, `shards-4`); the mock and node tests run in the hosted `web` job.

### PUBLIC TEXT (for the Planner's ruling)

| # | Where (file; location) | String (verbatim) | Status |
|---|---|---|---|
| 1 | `chat/files-view.ts` `FILES_TEXTS.send`; the paperclip's `aria-label` | "Send a file" | New |
| 2 | `FILES_TEXTS.tooLarge`; `Core.Files` `TEXTTOOLARGE` (page refusal, `RefusalText`) | "That file is {size}; the limit is 10 MB." (fixture "That file is 14 MB; the limit is 10 MB.") | Given: EXPERIENCE :1089, AC 3 |
| 3 | `FILES_TEXTS.unreadable`; `Core.Files` `TEXTUNREADABLE` | "I couldn't read that file: {reason}." | Given: EXPERIENCE :1090, AC 3 |
| 4 | `FILES_TEXTS.reasons.wrong_type`; `Core.Files` | "it isn't a PDF, Word (.docx), JPEG or PNG file" | New |
| 5 | `FILES_TEXTS.reasons.empty`; `Core.Files` | "the file is empty" | Shipped (`REASON_TEXTS.empty`, ruled at 34.2), without the period inside the frame |
| 6 | `FILES_TEXTS.offOnDemo`; `Core.Files` `TEXTOFFONDEMO` (409 message, drop on the demo) | "Sending files is off on the online demo. It works on your own install." | New (the shape of the ruled webhooks text) |
| 7 | `FILES_TEXTS.notSent` (send failed: network or 500) | "File not sent" | New (the shape of shipped "Message not sent") |
| 8 | `file-chip.ts`, the user's file message | "{name} · {size}" (name as data; size by `formatSize`, e.g. "2.1 MB") | Pattern shipped (" · " separator, `formatSize`) |
| 9 | `Web.Files` `MESSAGEBADFILE` (400 `bad_file`) | "OcuTalon can read PDF, Word (.docx), JPEG and PNG files up to 10 MB." | New |
| 10 | Drop hint | none (Decided 8) | — |
| 11 | "Add to documents" control and accessible name | "Add to documents" | Given: EXPERIENCE :1091. Planned for 25.6 (`files-view.ts`), not in this story |
| 12 | Photo reply chip | "Saved to memory" | Given: EXPERIENCE :1092. Planned for 25.6, not in this story |
| 13 | GUIDE.md line | For the Planner 5 | Approved for 25.6/26.2 (ruling 5); not in 25.3 |
| 14 | `Core.Conversation` (or `Core.Files`) parameter, the no-reader reply; `FILES_TEXTS` if the page shows it | "I got {name}, but I can't read files yet." (`{name}` as escaped text) | Approved (ruling 4) |

Row 14 lives in `Core.Files` as `TEXTNOREADER` (Decided 16), with `{name}` replaced by `SafeName(name)`; the page shows it only as the reply's `replyText`, so it is not in `FILES_TEXTS`. No public text beyond rows 1-9 and 14 is planned.

### SPINE ROWS (this story's own; AD-33, Story 25.2's amended first AC)

`<date>` is the implement stage's UTC date.
- **Tables paragraph (:1418), appended:** `From step 6 Lane B owns \`SentFile\` (each file a user sends from the chat or, from Story 26.2, from Telegram: \`Ref\`, \`SessionRef\`, \`Channel\`, \`Name\`, \`MediaType\`, \`Size\`, the bytes in its private global stream and \`CreatedAt\`), written only by \`Core.Files.Store\`, read only through \`Ownership.SentFile\` by \`Core.Files\` (\`Open\` for the bytes, \`Describe\` for the rest), dropped by \`SentFile.DropSession\` at a session's end and deleted by age with the standard purge; no route serves its bytes; the online demo stores none while sending files is off there. [ADDED <date>, Story 25.3]`
- **Cross-area table, after :1492:** `| \`OcuTalon.Core.Files\`: \`Store(sessionRef, channel, name, content, .file, .sc)\` (the file-store call: size, empty and byte-signature checks before anything is stored; codes \`too_large\`, \`empty\`, \`wrong_type\`; the name made safe and cut to 255), \`Open(ref, sessionRef, .sc)\`, \`Describe(ref, sessionRef, .sc)\`, \`SetItem(item, file)\` and \`RefusalText(code, size)\`; \`OcuTalon.Msg.Item\`'s \`FileRef\`, \`FileName\`, \`FileMediaType\` and \`FileSize\` (never the bytes, AD-21), on an Item of provenance \`untrusted\` (AD-14); \`chat.message\`'s \`sentFile\`. Called by \`Web.Files\` and, from Story 26.2, by Lane A's \`TelegramIn\`; \`Open\` is read by Story 26.2's \`Agent.Input\` and Story 26.3's caption request [ADDED <date>, Story 25.3] | B | Story 25.3 |`
- **Same table:** `| The read-path probe: \`OcuTalon.Core.Files.Readable()\` is 1 only when \`OcuTalon.Agent.Input\`'s parameter \`READSFILES\` is 1, which Story 26.2 adds in the change that makes \`Agent.Input\` read a sent file; until then a file turn gets the code-written reply \`Core.Files.NoReaderText\` and no model request [ADDED <date>, Story 25.3] | A (the parameter), B (the probe) | Story 25.3 (probe), Story 26.2 (parameter) |`
- **Same table:** `| The composer's paperclip button and the chat's file drop (\`web/src/app/chat/\`), which post only to \`POST /api/v1/files\`; shown only while \`/v1/state\`'s \`filesReadable\` is true, and never on the online demo, where a drop shows the off text [ADDED <date>, Story 25.3] | B | Story 25.3 |`
- **REST table, after :1629:** `| \`GET /api/v1/state\` from step 6 | also carries \`filesReadable\` (\`Core.Files.Readable()\`: whether the install's code can read a sent file), right after \`demoMode\`; the page shows the paperclip and takes a chat drop only when it is true and the instance is not the online demo [ADDED <date>, Story 25.3] |`
- **REST table, after :1657:** `| \`POST /api/v1/files\` (\`clientId\`, \`name\`, \`content\` in base64) | \`OcuTalon.Web.Files\`, forwarded from \`Web.Api\`'s map: \`Core.Files.Store\` under the CSP session's \`SessionRef\`, then \`WebChatIn\` with the file's fields on an untrusted Item; 202 \`{"clientId", "file"}\`; 400 \`bad_file\` (with \`reason\` \`too_large\`, \`empty\` or \`wrong_type\`, and \`size\`); 413 \`body_too_large\` over 13,985,112 bytes; 409 \`not_available\` on the online demo before the body is read; every other method and every path below it 404 \`not_found\` (no route reads a file back); any user with the OcuTalon user role, behind the AD-13 envelope [ADDED <date>, Story 25.3] |`
- **Conventions REST (:1220):** 400 codes gain "`bad_file` (with `reason` `too_large`, `empty` or `wrong_type`)" [ADDED <date>, Story 25.3].
- **AD-4 :194, AD-22 :851, AD-27 :1027 (Planner ruling, For the Planner 3):**
  - AD-4's sign-out list gains "from step 6 the session's sent files (`OcuTalon.Data.SentFile.DropSession`)".
  - AD-22's "`getFile` and the file-download path arrive in Story 25.3 (Lane B), for Story 26.2" becomes "`getFile` and the file-download path (`/file/bot<token>/…`, the token logged by length there too) serve fixture files registered through the control endpoint (Story 25.3), for Story 26.2".
  - AD-27's Web-area purge gains "and `SentFile` rows older than the task's days".

## Verification

`$LANE` stands for these variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=25 stage=implement'`. The fresh tag is `e25s3i` and the warm tag is `e25s3iw`.

Runtime targets: the lane's own throwaways (`ci/iris.sh`, `ci/warm.sh`, tags above) for every test run; slot A (profile `ocutalon-slot-a`, namespace `OCUTALON`, passed on every MCP call, `iris_server_info` first) for Task 0's read-only measurement and compile checks only, with one `iris_execute_tests` per message. Run one command per tool call in the foreground with `timeout: 600000`, each sized to about 150 s; one test class per call is always safe. Tear down only your own tags, and run `ci/warm.sh down` at the end, also after a failure. Scratch goes under the session scratchpad's `e25s3impl/`.

**Commands:**
- (loop) `$LANE OCUTALON_RUN_TAG=e25s3iw ci/warm.sh up` once. Then one class per call, `$LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e25s3iw ci/iris.sh class <Class>`, for each of:
  - `OcuTalon.Test.Data.SentFile`, `OcuTalon.Test.Core.Files`, `OcuTalon.Test.Core.ConversationFiles`, `OcuTalon.Test.Web.FilesApi`;
  - `OcuTalon.Test.Contract.Mock`, `OcuTalon.Test.Core.SessionOpsDocuments`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Data.Ownership`, `OcuTalon.Test.Msg.Contracts`, `OcuTalon.Test.Web.Api`;
  - the siblings `OcuTalon.Test.Core.ConversationTurns`, `OcuTalon.Test.Core.ConversationSessionStart`, `OcuTalon.Test.Core.WebChatMessages`, `OcuTalon.Test.Web.DocumentsApi`, `OcuTalon.Test.Core.UploadContract`, `OcuTalon.Test.Live.Payloads` and `OcuTalon.Test.Bridge.Gate` (unchanged; it pins the rule AC 8 relies on).
  Expected: each `CLASS … passed`.
- (loop) `node --test ci/mock/test/telegram.test.mjs ci/mock/test/scenarios.test.mjs ci/mock/test/server.test.mjs` -- all pass.
- (loop) `node --test web/scripts/files-view.test.mjs web/scripts/files-sources.test.mjs web/scripts/files-docs.test.mjs web/scripts/ux-strings.test.mjs web/scripts/floor-sources.test.mjs web/scripts/api-client-sources.test.mjs web/scripts/allowance-sources.test.mjs web/scripts/chat-view.test.mjs web/scripts/payloads.test.mjs`, then `node web/scripts/payloads.mjs --check` -- all pass.
- (loop) e2e, one call each:
  - `$LANE OCUTALON_RUN_TAG=e25s3i ci/iris.sh build`.
  - `npm --silent --prefix web run e2e -- --list --reporter=json > "$SCRATCH/chromium.json"`, then `node web/scripts/e2e-part.mjs k/n "$SCRATCH/chromium.json"`, choosing n so that each part holds at most two spec files.
  - `$LANE OCUTALON_RUN_TAG=e25s3i ci/iris.sh live sign-in --part k/n` for each part holding `api/files.spec.ts`, `files/files.spec.ts`, `api/api.spec.ts`, `frame/frame.spec.ts`, `documents/documents.spec.ts` or `chat/chat.spec.ts` -- each part passes.
  - `$LANE OCUTALON_RUN_TAG=e25s3i ci/iris.sh teardown`.
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- `"ok": true`, and no `ad_id`, `ad_fields` or new `placeholder` finding against Task 0's baseline.
- (once) `$LANE OCUTALON_RUN_TAG=e25s3i ci/iris.sh live demo-path` -- passes (UJ-1 unchanged: no paperclip on the demo path's state).
- (once) `npm --prefix web test`; `npm --prefix web run lint`; `npm --prefix web run build`; `bash docker/tests/test-mock.sh` -- each passes, one per call.
- (once) `bash ci/checks.sh`, in batches of `CHECK_SCRIPTS` if one call cannot hold it -- every block passes, among them `test-storage.sh` (short names, prefix, release-diff), `test-class-rules.sh` (no new unchecked prepare), `test-boundaries.sh` (ASCII, Rule 14) and `test-ci-config.sh`.
- The full shards and groups are left to CI.

**Shared surfaces:**
- the table registry (`Test/Data/Tables.cls`) and `src/short-names.tsv`;
- `Msg.Item`'s properties (`Test.Msg.Contracts`) and the storage release-diff of `Msg.Item`, `Channel.WebChat.Post` and `Data.Turn`;
- the Ownership kinds (`TestIsolationEveryRowKind`);
- the `/v1/state` key order (`Test/Web/Api.cls:132`, `e2e/api/api.spec.ts:135`, `e2e/frame/frame.spec.ts:607`) and `StateSnapshot`;
- the REST table and `Web.Api`'s URL map and `BodyBounds` (the Map pins in `DocumentsApi`/`UsageApi`/`HistoryApi`);
- the `chat.message` payload and `payloads.ts`;
- `Conversation`'s drop rules (`TestUntrustedItemRefused`) and `ConversationProbe`'s seams;
- the CI mock's `BOT_METHODS`, its log keys and its `getFile` pins;
- the composer's controls (unchanged on every real state; `allowance-sources` counts unchanged);
- the `ux-strings`, `floor-sources` (drag-and-drop allow-list) and `api-client-sources` lists;
- the Documents page's picker and drop (D5-D8, unedited);
- `SessionOps.End`'s steps and the Web area's purge list;
- the spine's tables.

No More to try item, README or GUIDE count changes. Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations to record (Rule 19; one per AC, each observed red and reverted byte-identical):**
- AC 1: `Core.Files.SetItem` not setting `FileRef` -> `ConversationFiles` red and `files.spec.ts` (chip) red.
- AC 2: `Store` ignoring its `channel` argument -> `Test.Core.Files` (telegram) and `ConversationFiles` (telegram Item) red.
- AC 3: the download path serving the bytes base64-encoded as text -> `telegram.test.mjs` download test red.
- AC 4: the size check removed from `checkFile` -> `files-view.test.mjs` and `files.spec.ts` (the 14 MB case counts a request) red.
- AC 5: `Store`'s signature check replaced by the extension alone -> `Test.Core.Files` (`MZ` bytes named `x.pdf`), `FilesApi` and `files.spec.ts` (`setup.pdf`) red.
- AC 6: the `onlineDemo` check removed from `Send` -> `FilesApi` demo test red.
- AC 7: the `sentFile` kind's `SessionRef` clause removed -> `Test.Data.SentFile` and `api/files.spec.ts` (3) red.
- AC 8: `ItemOf` setting Provenance `user` for a Turn with `SentFile` -> `ConversationFiles` `TestReaderTurnIsUntrusted` red (the requests' provenance and the gate's denial).
- AC 9: a `<Route Url="/:ref" Method="GET" Call="Send"/>` added to `Web.Files`' UrlMap -> `FilesApi` dispatch test, `files-sources.test.mjs` and `api/files.spec.ts` (ii) red.
- AC 10: `SetItem` also writing the first 200 bytes of the content into `item.Text` -> `Test.Core.Files` (marker in an Item property) and `api/files.spec.ts` (iv, `TraceHits(marker)` above 0) red.
- AC 11: the no-reader branch removed from `Begin` -> `ConversationFiles` `TestNoReaderReply` red (a Decide call is recorded).
- AC 12: the REST row deleted -> `files-docs.test.mjs` red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Re-planned (cycle iteration 2) to the Planner's 2026-11-12 rulings, with the intent contract kept verbatim. Each ruling has its ACs, tasks, tests and mutation lines; the capability-flag probe and what Story 26.2 must provide are under Design Notes → For Story 26.2. No new public text beyond rows 1-9 and 14, no new veto item, no new contended overlap. Nothing was implemented, committed or pushed.
