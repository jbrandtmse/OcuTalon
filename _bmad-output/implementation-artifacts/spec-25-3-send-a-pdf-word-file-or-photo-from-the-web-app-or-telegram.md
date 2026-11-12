---
title: 'Story 25.3: Send a PDF, Word file or photo from the web app or Telegram'
type: 'feature'
created: '2026-11-12'
status: 'draft'
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

Line numbers are on `acb9c045` (OCT-epic25, feature `b8780de6` integrated).

**Backend (Lane B; edit or add):**
- `src/ocutalon/cls/OcuTalon/Web/Documents.cls`, the sibling route:
  - `FILEMAX` :29 and `BODYMAX` :33; `XData BodyBounds` :68-73; `Add` :101-108.
  - `ParseBody` :245 reads `%FromJSON(..Characters(content))`, then `%Get("content",,"stream<base64")`. `Characters` :269 is `[Private]`, so make it callable with no behaviour change, or call it through `ParseBody`.
  - `ContentTypeOf` :305; `Refuse` :319; `Dispatch` :189-213 (Put, Submit, drop on a failure); `Sweep` :217.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`: UrlMap `/v1/messages` :252 and `<Map Prefix="/v1/documents" …>` :288. The full-path `BodyBounds` entry is :301. `Messages` :441 and `Post` :515 run `CreateBusinessService("WebChatIn")`. Error constants are near :149-192 (`MESSAGENOTAVAILABLE` :192 is email's). The header doc bullets are :3-101.
- `src/ocutalon/cls/OcuTalon/Web/BodyLimit.cls` `TooLarge` :68 (reads `class||BodyBounds`); `MAXBYTES` 262144.
- `src/ocutalon/cls/OcuTalon/Web/HookSettings.cls` :35-44: the "409 `not_available` on the online demo, before anything is read" precedent (`Data.Setting.Get("onlineDemo")`).
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Post.cls` (SessionRef, ClientId, Text, FromGuide) and `Channel/WebChat/In.cls` `Accept` :58-105. `Accept` checks a duplicate ClientId, calls `Allowed` :135 (`Core.Allowance.TryConsume`, a no-op off the demo), builds the Item :83-91 and sends it async to `Conversation`.
- `src/ocutalon/cls/OcuTalon/Msg/Item.cls`: 12 properties, no file fields (Lane B).
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls`: `Untrusted` :243-250 drops an Item with `$ZStrip(Text)=""` (`DROPNOTEXT`) or with Provenance other than `user`. The Turn is saved and `chat.message` published :701-705.
- `src/ocutalon/cls/OcuTalon/Data/Turn.cls` (`^OcuTalonP.Turn`; `Citations`/`Memories`/`Learned` are JSON-string precedents :79-87). `Live/Payload/ChatMessage.cls` `FromRow` :75, with the `Learned` part list :67/:102 as the model. Parts are in `Live/Payload/Part/`.
- `src/ocutalon/cls/OcuTalon/Data/Upload.cls`: the sibling table, never edited. `Put` :40, `DropSession` :81 (`%ExecDirect`), `Purge` :97 (a walk of `^OcuTalonP.UploadD`), storage :135-160. Its contract test is `Test/Core/UploadContract.cls`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: `Upload` :449 and kind `upload` :1350-1351 (the model for `sentFile`); `Rows`; `LocalFlag` :1096. Class doc :44.
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` `EndDocumentsAndMemories` :599 and `DropUploads` :617/:639.
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` `Purge` :137-147 (Upload :141).
- `src/short-names.tsv` (the Upload row is :33). The `docker/tests/test-storage.sh` rules need a `DEFAULTGLOBAL` `^OcuTalonP.<Short>` row.
- `src/ocutalon/cls/OcuTalon/Bridge/Ids.cls` `NewRef()` (public Refs).
- Read only (Lane A): `Docs/Extract.cls` (`FAILUREFRAME` :50, `REASONTOOLARGESIZE` :54, `SizeText`, `Failure` :159 strips one trailing period). `Channel/Telegram/In.cls` (`HandleUpdate` :341 reads only `message.text`; `Other` :619-626; `Turn` :631 builds the Item :652-659). `Agent/Input.cls` `Render`.

**CI mock (Lane B; edit):**
- `ci/mock/mock.mjs`:
  - `BOT_PATH` :61; `handle` :630-640; `handleBot` :514-621.
  - The `getFile` refusal :561-563 and the header :21.
  - `shortPath` :187-190 rewrites only `^/bot`; `send` :246-251 is JSON or text only; `tokenLength` :530; `telegramControl` :324-393 (`replies` refuses `getFile` :379); `defaultAnswer` :198-210.
- `ci/mock/scenarios.mjs`: the doc :22-28; `TELEGRAM_REPLY_FIELDS` :41 and `BOT_METHODS` :42-43; the `getFile` refusal :212-213 and :24-25.
- `ci/mock/test/telegram.test.mjs`: pins :94 (log keys), :105-119, :135, :303, :317-318 and :347-354. `scenarios.test.mjs`: :58 and :253-263 (`BOT_METHODS` exact list). `server.test.mjs:619` (log keys). `docker/tests/test-mock.sh` runs them.
- `ci/compose.ci.yml:27` (`OCUTALON_TELEGRAM_API_BASE`). `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls` `TestTelegramBotApi` (Lane B, `TELEGRAMBASE` :53) and `Test/Channel/BotApi.cls` `BotReply` :95 are the IRIS-side models.

**Web (Lane B; edit or add):**
- `web/src/app/chat/composer.ts`: the template :31-56, `onKey` :131-137, `send` :141, `reason` :110-113. `CHAT_TEXTS` (`chat/chat-view.ts:44`) is pinned by deepEqual (`scripts/chat-view.test.mjs:538-544`), so new texts go in a new file. `chat/chat-panel.ts:186` places the composer.
- `chat/chat-outbox.ts` :101-109 (refusals, `takeBack`); `api/api-client.ts` `postMessage` :132-142 and `addDocument` :246-248; `api/envelope.interceptor.ts:32` adds the header; `api/api-types.ts:59` `onlineDemo`.
- `web/src/app/documents/documents-page.ts`: the picker :64-68 and the drop handlers `dragOver` :321, `dragLeave` :328 and `dropped` :335 (CSS :122). `addFile` :419; `encode` :469 (private); `reasonOf` :447.
- `documents/documents-view.ts`: `REASON_TEXTS` :50-63 and `formatSize` :69 (exported: reuse).
- The user's turn rendering in `chat/chat-view.ts` (`TurnView` :138-143) and the chat message list. `web/src/app/live/payloads.ts` is generated by `web/scripts/payloads.mjs`.
- `web/src/app/settings/settings-view.ts:85` `offOnDemo` and `webhooks-section.ts:47` are the off-on-the-demo text precedent.

**Tests and shared surfaces (edit):**
- `Test/Data/Tables.cls` `XData Registry` :701 (Upload row :800-802), checked by `TestEveryTableIsRegistered` :46. `Test/Msg/Contracts.cls` :164-180 pins `Msg.Item`'s exact properties. `Test/Data/Ownership.cls` `TestIsolationEveryRowKind` :481-490.
- Siblings to model: `Test/Core/SessionOpsDocuments.cls` (+`SessionOpsDropProbe`), `Test/Core/ConversationTurns.cls`, `WebChatMessages.cls`, `Test/Web/DocumentsApi.cls` :248-371 (base64 cases; its `TestList` forces `onlineDemo` and restores it) and `DocumentsProbe.cls`.
- `Test/Docs/Samples.cls` (Lane A, read only) builds PDF/DOCX bytes; no image builder exists, so tests build PNG/JPEG headers inline.
- `web/scripts/`:
  - `ux-strings.test.mjs` `IMPORTED` :41-78.
  - `floor-sources.test.mjs`: `KEY_HANDLERS` :103-104, bindings :159, and the `BANNED` drag-and-drop allow-list :362-367, which allows only `documents-page.ts`.
  - `api-client-sources.test.mjs` (method bodies; no `headers`) and `allowance-sources.test.mjs:107-109`, which counts exactly 2 `aria-disabled` bindings in `composer.ts`. Keep that count.
  - `payloads.mjs --check`.
- e2e:
  - Ambiguous `app-composer button` at `web/e2e/floor/keyboard.spec.ts:384` and `floor/devices.spec.ts:101,202`.
  - Tab-order walks: `frame/frame.spec.ts:116,177-191`, `floor/layout.spec.ts:172`, `floor/focus.spec.ts:196`, `chat/chat.spec.ts:194-196`, `banners/banners.spec.ts`.
  - Models: `e2e/api/memory.spec.ts` (`envelope`, `expectError`, `signInOverHttp`, `fixtureUser('LIVE'|'PANEL')`, PANEL isolation :225-233) and `e2e/api/body-limit.spec.ts`. `documents/documents.spec.ts` has D5 (the early `filechooser` listener), D6 (a `DataTransfer` drop) and D7/D8 (`setInputFiles` 11 MB/10 MB).
- `ci/units.sh`: `Test.Core`/`Data`/`Contract`/`Live` run in `image` (`shard:lane-b@Contract,Core,Data,Live`) and `Test.Web` in `shards-6` (`lane-b@rest`), with no edit. `web/e2e/files/` and `web/e2e/api/` join the `chromium` project (`live:sign-in`, `shards-10`) with no config edit.

**Planning (edit; this story's rows only):** `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`:
- AD-4 sign-out sentence :194;
- AD-22 :851;
- AD-27 :1027;
- Conventions REST :1220;
- Tables paragraph :1418, at its end;
- cross-area table after :1492;
- REST table after :1657.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (implement, before any edit):
  - Re-check the Code Map anchors by name.
  - On slot A (`ocutalon-slot-a`, `OCUTALON`, read-only `iris_execute_classmethod`), record what `OcuTalon.Agent.Input.Render` returns for an Item with empty `Text` and file fields set. That is evidence for Design Notes → For the Planner 8; record it in the Spec Change Log.
  - At the first compile of `Data.SentFile` and `Msg.Item`, confirm that the table, its columns and the `sentFile` statement prepare on build 154. If a name is an SQL reserved word, rename it and record the new name.
  - Take the `lint_spine.py` baseline.
- [ ] `src/ocutalon/cls/OcuTalon/Data/SentFile.cls` (new) and `src/short-names.tsv` -- add a persistent class with `DEFAULTGLOBAL "^OcuTalonP.SentFile"` and the row `SentFile ^OcuTalonP.SentFile OcuTalon.Data.SentFile B`. Its properties: `Ref` and `SessionRef` (EXACT, 22), `Channel`, `Name` (255), `MediaType` (128), `Size`, `Content As %Stream.GlobalBinary`, `CreatedAt`. Its indexes are `RefIndex` (unique) and `SessionRefIndex`. Its methods: `Put(sessionRef, channel, name, mediaType, bytes, .sc)` returns the Ref; `DropSession(sessionRef)`; `Drop(ref, sessionRef)`; `Purge(daysToKeep, now)` deletes rows whose `CreatedAt` is older than `daysToKeep` days, with no SQL. -- Rationale: AD-3, AD-27. It copies Upload's shape, not its lifecycle (Design Notes, Rule 2).
- [ ] `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- add the Rows kind `sentFile` (`SELECT f.ID FROM OcuTalon_Data.SentFile f WHERE f.Ref = ? AND f.SessionRef = ?`), appended after `upload`, and `SentFile(ref, sessionRef, .sc)` beside `Upload`, with a class-doc line. -- Rationale: AD-4, the one read path.
- [ ] `src/ocutalon/cls/OcuTalon/Core/Files.cls` (new; the file-store call) -- holds:
  - `Store(sessionRef, channel, name, content As %Stream.Object, Output file As %DynamicObject, Output sc) As %String`. It returns `""` or the refusal code `too_large`/`empty`/`wrong_type`, checking size, then empty, then signature and extension. An empty name becomes `photo.jpg`/`photo.png`/`file.pdf`/`file.docx` by type. It writes the row through `SentFile.Put` and sets `file` = `{ref, name, mediaType, size}`.
  - `Open(ref, sessionRef, Output sc)`, which returns a `%Stream.TmpBinary` copy found through `Ownership.SentFile`, or `""`.
  - `SetItem(item As Msg.Item, file)`, which sets the four Item fields.
  - `RefusalText(code, size)`, which gives the PUBLIC TEXT sentences (size through a `SizeText` that writes "14 MB" as `Docs.Extract.SizeText` does; pinned equal to it).
  - The parameters `FILEMAX` (= `##class(OcuTalon.Web.Documents).#FILEMAX`, by expression) and the texts.
  -- Rationale: the one store for web and Telegram (AC 2); 26.2 calls `Store`/`SetItem`/`RefusalText` and 26.2/26.3 call `Open`.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Item.cls` and `src/ocutalon/cls/OcuTalon/Channel/WebChat/Post.cls` -- append the properties `FileRef` (22), `FileName` (255), `FileMediaType` (128) and `FileSize` (`%Integer`) to Item. Append `FileRef`, `FileName`, `FileMediaType` and `FileSize` to Post. Storage only appends slots. -- Rationale: AC 1, never bytes (AD-21's key proof stays true).
- [ ] `src/ocutalon/cls/OcuTalon/Channel/WebChat/In.cls` -- `Accept` copies the Post's file fields onto the Item and reports whether it queued the Item (a new output, so `Web.Files` can drop the row of a duplicate or refused send). A message's path is unchanged. -- Rationale: one way into Conversation.
- [ ] `src/ocutalon/cls/OcuTalon/Core/Conversation.cls`, `src/ocutalon/cls/OcuTalon/Data/Turn.cls`, `src/ocutalon/cls/OcuTalon/Live/Payload/Part/SentFile.cls` (new) and `Live/Payload/ChatMessage.cls`:
  - `Untrusted` takes an Item with `FileRef` set and empty text; every other drop is unchanged.
  - The saved Turn gets `SentFile` (a JSON string `{ref,name,mediaType,size}`, appended, like `Citations`).
  - `ChatMessage` gains `sentFile` (`Part.SentFile`: `ref`, `name`, `mediaType`, `size`) from `FromRow`.
  - The turn then runs like any turn (For the Planner 8).
  - Regenerate `web/src/app/live/payloads.ts` with `node web/scripts/payloads.mjs`.
  -- Rationale: the page shows the user's file message from the live event and the snapshot.
- [ ] `src/ocutalon/cls/OcuTalon/Web/Files.cls` (new; `Extends OcuTalon.Web.Api`, mirroring `Web.Documents`) and `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - `Web.Files` has UrlMap `"" POST Send` and `XData BodyBounds` `[{"method":"POST","url":"","bytes":13985112}]`.
  - `Send` checks, in order:
    1. `onlineDemo` 1 gives 409 `not_available` with `Core.Files` off text (before the body is read);
    2. it parses through `Web.Documents.ParseBody` (plus `clientId`);
    3. a bad body gives 400 `bad_file` `MESSAGEBADFILE`;
    4. `Core.Files.Store(SessionRef, "web", …)`, where a refusal gives 400 `bad_file` with `reason` and `size`;
    5. a `Channel.WebChat.Post` with the file fields goes through `Web.Api.Post`;
    6. if the Item was not queued (duplicate) or the send failed, it drops the row;
    7. 202 `{"clientId","file"}`; a failure is 500 `server_error`.
  - In `Web.Api`, add `<Map Prefix="/v1/files" Forward="OcuTalon.Web.Files"/>` after the documents map, the full-path `BodyBounds` entry `{"method":"POST","url":"/v1/files","bytes":13985112}`, and one header doc bullet.
  -- Rationale: AD-13 envelope and bound; the documents precedent.
- [ ] `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls` and `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` -- `EndDocumentsAndMemories` also runs `SentFile.DropSession` (a step beside `DropUploads`, under the same "each step tried" rule), and the Web area's `Purge` calls `SentFile.Purge(daysToKeep)`. Update both doc comments. -- Rationale: AD-4 (session end), AD-27 (standard purge).
- [ ] `ci/mock/mock.mjs` and `ci/mock/scenarios.mjs` -- remove the `getFile` refusals and add `getFile` to `BOT_METHODS`:
  - Add the control route `POST /_mock/telegram/files` `{fileId, filePath, contentType, base64}`, which registers a fixture file. `reset` clears the registry.
  - `getFile` answers from the registry (a queued scenario reply still wins), and an unknown `file_id` gets the matrix's 400.
  - Add the route `GET /file/bot<token>/<file_path>`, matched before the model API branch. An empty token is 401. It serves the registered bytes with their `Content-Type` and `Content-Length` as a Buffer, and an unknown path is 404. It is recorded in `calls` as `{method:'download', params:{file_path}}`.
  - `shortPath` also rewrites `/file/bot<token>/` to `/file/bot[redacted]/`. The log entry keeps the pinned keys and carries `tokenLength`.
  - Update the file headers.
  -- Rationale: AC 2's second half, AD-22, NFR-11. New code is in mock.mjs/scenarios.mjs only.
- [ ] `web/src/app/shared/file-encode.ts` (new) and `web/src/app/shared/file-drop.ts` (new) -- move `encode` out of `documents-page.ts` unchanged. Add a `FileDrop` directive (`dragover`/`dragleave`/`drop` with the `Files` type check, a `dragging` class and a `files` output) that holds the logic of `dragOver`/`dragLeave`/`dropped`. `documents-page.ts` uses both, with no behaviour change (D5, D6, D7 and D8 pass unedited). -- Rationale: Rule 2.
- [ ] `web/src/app/chat/files-view.ts` (new, pure) -- holds:
  - `FILES_TEXTS` (PUBLIC TEXT);
  - `ACCEPT_FILES = '.pdf,.docx,.jpg,.jpeg,.png'`;
  - `checkFile({name,size,type})` returns `''` or `too_large`/`empty`/`wrong_type` (by extension; size first);
  - `refusalText(code, size)` uses the imported `formatSize`;
  - `fileLine(name, size)` gives "{name} · {size}".
- [ ] `web/src/app/chat/composer.ts`, `web/src/app/chat/chat-panel.ts`, `web/src/app/chat/file-chip.ts` (new), the user's turn rendering, and `web/src/app/api/api-client.ts`:
  - The paperclip `<button type="button">` comes before the textarea, with `aria-label` `FILES_TEXTS.send` and an inline SVG icon (`aria-hidden`). It opens a hidden `<input type="file" multiple [accept]>`, and it is not rendered when `onlineDemo` is true.
  - The chat panel takes `FileDrop`. On the online demo a drop shows the off text.
  - Each picked or dropped file is checked by `checkFile`. A refusal shows in a `<p class="file-refusal" role="status">` above the composer and is announced through the existing Announcer. A valid file is encoded and posted with `api.sendFile(clientId, name, content)` (POST `${BASE}/files`, body only).
  - Files go one at a time. A 400 `bad_file`/413 shows the matching refusal; any other failure shows `FILES_TEXTS.notSent`.
  - The user's turn with `sentFile` shows `<app-file-chip>` (name and size as text).
  - Enter/Space on the paperclip opens the picker. The textarea's content is never touched. The Send button and the allowance bindings are unchanged.
  -- Rationale: UX-DR129/147, NFR-25.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/SentFile.cls` (new) -- `Put`; `Ownership.SentFile` owner-scoped (B cannot find A's); `DropSession` drops only that session; `Purge` by age at the edge; storage under `^OcuTalonP.SentFile`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/Files.cls` (new) -- `Store`:
  - each type by signature, with every media type exact;
  - 10,485,760 accepted and 10,485,761 `too_large` with no row;
  - empty;
  - each `wrong_type` row of the matrix;
  - a default name;
  - channel `telegram`.
  - Also `Open` owner-scoped, `SetItem` fields, and `RefusalText` for each code equal to the PUBLIC TEXT and to `Docs.Extract`'s frame. The Item's exported properties hold no byte of the content: a marker string in the PDF is absent from every Item property.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/ConversationFiles.cls` (new; modelled on `ConversationTurns`) -- the integration AC:
  - a web file Item and a fixture Telegram file Item (built through `Store` and `SetItem`) each become a queued Turn of their session with `SentFile` set;
  - the published `chat.message` carries `sentFile` with exactly the four keys;
  - an Item with no text and no `FileRef` is still dropped;
  - no production message body or Turn text holds the content marker.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Web/FilesApi.cls` and `Test/Web/FilesProbe.cls` (new; modelled on `DocumentsApi`/`DocumentsProbe`) -- covers:
  - Dispatch: exactly one Map for `/v1/files`, the route `POST ""`, and GET as no route.
  - Every matrix row at the route: each type 202 with the exact keys; `too_large`, `empty`, `wrong_type` and the bad bodies with their exact codes; a body `sessionRef` ignored; a duplicate `clientId` with no second row.
  - `onlineDemo` 1 gives 409 with the off text, nothing stored and no allowance consumed (forced and restored).
  - 403 `no_role`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/SessionOpsDocuments.cls` -- add `TestSentFilesDropped` beside `TestUploadsDropped`. `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls` -- add `TestTelegramFileDownload`: register, `getFile`, download with `%Net.HttpRequest`, the bytes equal, and the mock log carries the token's length and not the token.
- [ ] Shared tests (Rule 19) -- update these:
  - `Test/Data/Tables.cls`: the registry row.
  - `Test/Msg/Contracts.cls`: Item's four properties.
  - `Test/Data/Ownership.cls`: the `sentFile` kind in `TestIsolationEveryRowKind`.
  - `ci/mock/test/telegram.test.mjs` and `scenarios.test.mjs`: the `getFile` pins become the new behaviour, `BOT_METHODS` gains `getFile`, and new tests cover the registry, `getFile`, the download (bytes and type), the unknown id and path, the token by length on the download path, `calls` and `reset`.
  - `web/scripts/ux-strings.test.mjs`: `IMPORTED` gets `['chat/files-view.ts', ['FILES_TEXTS']]`, with its `ux`/`ruled` sources.
  - `floor-sources.test.mjs`: the drag-and-drop allow-list gains `shared/file-drop.ts` (its UX-DR129 reason: the paperclip is the first way), plus the key handler list if the paperclip adds one.
  - `api-client-sources.test.mjs`: `sendFile`'s exact body.
  - `payloads.test.mjs` if it pins ChatMessage's fields.
  - `web/scripts/files-view.test.mjs` (new): `checkFile`, `refusalText` and `fileLine`, plus `FILES_TEXTS` equal to `Core.Files`' text parameters (read from the class source).
  - `web/scripts/files-docs.test.mjs` (new; the 25.2 `history-docs.test.mjs` model): the SPINE ROWS present once each, with the REST row naming exactly the route that `Web.Files`' URL map serves.
  - The e2e locators and Tab walks in the Code Map: locate Send by name, and add the paperclip stop where a walk lists stops.
- [ ] `web/e2e/api/files.spec.ts` (new; real HTTP, modelled on `api/memory.spec.ts`) -- the SECURITY tests in Design Notes, cleaning their rows in `finally`.
- [ ] `web/e2e/files/files.spec.ts` (new; chromium) -- covers:
  - the paperclip by keyboard (Tab, Enter, the early `filechooser` listener) for PDF, DOCX, JPEG and PNG fixture buffers with real signatures; each shows the user's file chip (name and size) and survives a reload;
  - a drop as the second way;
  - 14 MB: "That file is 14 MB; the limit is 10 MB.", with no request sent (counted with `page.route`);
  - `.txt`, and an empty `.pdf`, with their texts;
  - a name holding `<b>` renders as text;
  - `/state` stubbed with `onlineDemo: true`: no paperclip, and a drop shows the off text;
  - a PANEL session never sees LIVE's file.
- [ ] `ARCHITECTURE-SPINE.md` -- write the rows in Design Notes → SPINE ROWS, as the Planner rules them. Refresh `updated:` and run `lint_spine.py`. No `.memlog.md` exists (25.2): record that, and create nothing.

**Acceptance Criteria:**
- Given the composer on a local install, when the user presses the paperclip (by mouse, or Tab then Enter/Space) or drops a file on the chat, then a PDF, .docx, JPEG or PNG is posted to `POST /api/v1/files` with the custom request header and a matching `Origin`. It is stored in `SentFile` and becomes an Item with its `Ref`, name, media type and size and no bytes, and the user's message shows the file's name and size. The paperclip has an accessible name, and the drop is never the only way.
- Given a fixture Telegram file passed to `Core.Files.Store` with channel `telegram`, when its Item (from `SetItem`) reaches `Conversation`, then the same `SentFile` row shape and the same kind of Item and Turn result, and `RefusalText` gives the PUBLIC TEXT for each refusal. `TelegramIn` is untouched.
- Given a fixture file registered on the CI mock, when a client calls `getFile` and then downloads `/file/bot<token>/<file_path>`, then it gets the file's path and the exact bytes and content type, and the mock's log and summary carry the token's length only.
- Given a file over 10 MB, of 0 bytes or of another type, from the page or through `Store`, when it arrives, then nothing is stored or sent: the page shows "That file is 14 MB; the limit is 10 MB." (with its size) or "I couldn't read that file: {reason}.", and the route and `Store` answer the matching code.
- Given the online demo, when a visitor opens the chat, then there is no paperclip, a drop shows the off text, and `POST /api/v1/files` answers 409 `not_available` with nothing stored or counted (the AC's demo clause as ruled: For the Planner 1).
- Given two sessions that each send a file, when either reads `/v1/state` or its events, then it sees only its own `sentFile`. At its sign-out the session's rows are dropped, and the standard purge deletes rows past its days.
- Given the spine, when this story merges, then its REST, tables and cross-area rows (SPINE ROWS) are present.

## Spec Change Log

- 2026-11-12 (lead, spec gate): the Contest Planner's rulings (`story-253-rulings-20261112.md`) written into the intent contract and Design Notes; status reset to `draft` for a re-plan on this spec path. Rulings: demo OFF (a); split to Story 25.6 approved (inserted into epics.md); veto items approved with four security conditions, each with a test; the gap closed by a `/v1/state` capability flag (true only once 26.2's read path is merged) plus a fixed no-model reply; PUBLIC TEXT rows 1-9 approved verbatim, plus the fixed reply; rows 11-13 go with 25.6/26.2. Decided 6, 10 and 11 and For the Planner 8 are superseded where they differ.

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6):**
- AD-1: the Item is a production message; `WebChatIn` is the way in.
- AD-3: a private global and a short-names row.
- AD-4: ownership reads, no client `SessionRef`, the sign-out drop.
- AD-12: the `chat.message` payload and the generated types.
- AD-13: the envelope, `BodyBounds`, the error codes, text-only names.
- AD-14: Item, Channel, Provenance `user`.
- AD-19: `onlineDemo`; the bot token from the environment.
- AD-20: the allowance (unreached while files are off on the demo).
- AD-21: no stream in a message body; Upload unchanged.
- AD-22: the CI mock; the token by length.
- AD-25: a JSON body, not multipart; the golden copy.
- AD-27: the standard purge.
- AD-29: Lane B files only; `TelegramIn` is Lane A's.
- AD-33: the rows land in the same change.
- No AC contradicts an AD Rule. The demo clause conflicts with the project's ONLINE DEMO SAFETY rule, not with an AD (For the Planner 1).

**Rule 1/2.**
- Integration AC: `Conversation` (a real instance, `Test.Core.ConversationFiles`) reads the web Item and the fixture Telegram Item and produces a queued Turn plus a `chat.message` carrying `sentFile`. The page (`files/files.spec.ts`, against the real route) reads that event and the snapshot and shows the file chip.
- Consumed-by:
  - Story 26.2: `TelegramIn` calls `Core.Files.Store`, `SetItem` and `RefusalText`; `Agent.Input` reads the Item's file fields and `Core.Files.Open`; its download test uses the mock's `getFile` and download path.
  - Story 26.3: photo Items and `Open` for the image bytes.
  - Proposed Story 25.6: the replies; Add to documents through the documents route by `Core.Files.Open`.
- Consumes:
  - `Web.Documents` (`FILEMAX`, `ParseBody`);
  - `Web.BodyLimit`;
  - `Web.Api.Post` and `WebChatIn.Accept`;
  - `Ownership.Rows`;
  - `SessionOps.EndDocumentsAndMemories`;
  - `Install/Step/Web.Purge`;
  - `Bridge.Ids.NewRef`;
  - `documents-view.ts` `formatSize`;
  - `documents-page.ts` `encode` and the drop logic, both extracted;
  - the Announcer;
  - `Test.Web.Api.Written`.
- Siblings, extended or copied with a reason:
  - `Data.SentFile` copies `Data.Upload`'s shape (`Put`/`DropSession`/no-SQL `Purge`, about 50 lines) and not its lifecycle. Upload is take-once with a one-hour purge, pinned by `UploadContract` and AD-21. A shared base would change that pinned storage contract, and a file Item's row must be read many times until sign-out or the purge.
  - `Web.Files` calls `Web.Documents`' `ParseBody`/`FILEMAX`/`BODYMAX` and does not copy them. Its own refusals differ: other types, the code `bad_file`, and a demo refusal.
  - The page extracts `encode` and `FileDrop` from the Documents page and imports `formatSize`.
  - The mock's download path reuses `shortPath`/`redact`/the calls log.
  - `Part.SentFile` follows `Part.Learned`.

**Ledger inbox:** none.

**AC evidence already met:** none of the ACs is met on this branch. The prerequisites are built: the body-bound mechanism (`Web.BodyLimit`, 34.2), the extraction and its failure frame (19.6, `Docs/Extract.cls`), the allowance (`Core.Allowance`) and the sign-out drops (`SessionOps` :599). The Documents page's PDF and Word types moved to Story 34.2 (done).

**Seams (read results).** Reading a file is Lane A's (19.6 built; 26.2 and 26.3 not merged; 37.1 not planned and with no spec, OCT-epic37 holds only its cycle log).
- This story's seam ends at the Item and `chat.message` `sentFile`: `Core.Files.Store`/`Open`/`SetItem`/`RefusalText` and the Item's four fields.
- No read result is rendered here. The replies, with their fixture read results, are the proposed 25.6 (For the Planner 2).
- The Telegram path is proven with a fixture Telegram file Item through `Store`, never through `TelegramIn`.

**Decided in-stage:**
1. A new table, not `Data.Upload` (Rule 2 above). Named `SentFile`, not `File`, to stay clear of SQL's FILE (Task 0 confirms).
2. Media types are the IANA ones (the AC's "media type"), read from the bytes' signature. A `.docx` needs the zip signature and the `.docx` extension, so a `.xlsx` is `wrong_type`.
3. The route is `POST /api/v1/files` with `{clientId, name, content}`. A new code `bad_file` (with `reason` and `size`) mirrors `bad_document`. Over the bound is 413, as everywhere.
4. The page checks size, then empty, then extension before it sends, because a 14 MB file's body (about 18.7 MB) would only get a 413. The server checks again with the signature.
5. A file is sent alone. The composer's text stays in the composer, and several picked or dropped files go one at a time, each its own Item, as the Documents page does.
6. Provenance `user`, because the user sent it (AD-14). The file's content is untrusted data for 26.2's `Agent.Input`.
7. The refusal texts live in `Core.Files` parameters and `FILES_TEXTS`, not in the contended `Msg/Catalog/Core.cls` (the `Docs.Extract` precedent). A test pins them equal.
8. No visible drop hint (34.2's Decided 10: no unsourced text). The chat outlines while dragging, as the Documents page does.
9. `Turn.SentFile` is a JSON string (the `Citations` precedent), so a reload shows the chip even after the file row is purged.
10. The paperclip comes before the textarea, so walks that end at Send still end there. It carries no allowance binding: the allowance applies only on the online demo, where the paperclip is hidden, so the pinned count of 2 holds.
11. No More to try item (files are off on the demo, where the guide runs) and no GUIDE.md line in this child (For the Planner 5). No new live unit: the new classes join `image` and `shards-6`, the specs join `live:sign-in` (`shards-10`), and the mock tests run in the hosted `web` job.
12. The demo pin is class-level (`FilesApi`, `onlineDemo` forced and restored, the `DocumentsApi.TestList` precedent) plus the chromium spec with `/state` stubbed. `live:online-demo` has no `--part` and takes about 9 minutes, so no `e2e-online` test is added (For the Planner 1).

### Planner rulings (2026-11-12, Contest Planner under the owner's delegation; binding)

1. Demo: (a) OFF as planned: the route returns 409 `not_available` before reading the body, the paperclip is hidden, a dropped file shows text 6, all pinned. Telegram never runs on the demo.
2. Split to Story 25.6 APPROVED (inserted into epics.md, with the moved ACs and markers). U-326 (the reply-contract AC added to 37.1, DW-1231) stands. `getFile` stays in 25.3.
3. Veto items APPROVED (route, `SentFile`, appended columns, payload and error code, CI mock, spine appends), plus FOUR SECURITY CONDITIONS, each with a test: (i) a turn that carries a `SentFile` is UNTRUSTED provenance from 25.3 on, even with empty text: only read-only tools run in that turn (as for a failed message or an email); when 26.2 reads the content, it keeps that marking. (ii) No route serves a stored file's bytes back, except possibly to its own session; no public or cross-session download (this story adds none at all). (iii) The type check uses the file's bytes, never only the name or the declared type; a renamed .exe or .html is refused with text 4. (iv) Nothing about a file goes into any log, trace or production message body except ref, name, type and size; the name is length-capped and escaped. The real-HTTP test list is approved as written.
4. THE GAP: don't ship a half feature. Hide the paperclip and the chat drop behind a `/v1/state` capability flag that turns on only when 26.2's read path is merged. Defence in depth: a file turn with no reader gets a fixed code reply "I got {name}, but I can't read files yet." and NO model call. A judge on a local install must never see the model reply to an empty message. (Supersedes For the Planner 8's recommendation and Decided 10's "the paperclip is hidden only on the demo".)
5. GUIDE "New since" line goes with 25.6 or 26.2, whichever makes it true; line 13 approved, each clause only once its story has merged. Not in 25.3.
PUBLIC TEXT: rows 1-9 approved verbatim; rows 11 and 12 go with 25.6; row 13 under (5); plus the fixed reply (row 14).

### For the Planner (spec gate, as sent; ruled above)

1. **Online demo behaviour (ONLINE DEMO SAFETY vs the AC's demo clause).** This is the planned default; nothing else in this spec depends on the choice.
   - **(a) OFF, recommended.** The route answers 409 `not_available` with the off text before the body is read. The page shows no paperclip, and a drop shows the off text. It is pinned by `Test.Web.FilesApi` (`onlineDemo` 1) and by `files.spec.ts` (stubbed `/state`). The AC's demo clause becomes "refused on the demo, nothing stored, nothing counted". Session ownership, the sign-out drop and the purge still apply wherever files run. The allowance call is left out, because it can't be reached; (b) or (c) add it, with `TryConsume` before the store and its test.
   - **(b) SIMULATED.** On the demo, the paperclip becomes "Send the sample runbook", the built-in sample PDF the Documents page already offers. The visitor's own bytes are never taken. It counts against the allowance, belongs to the session, and is dropped at sign-out and cleared by the reset. Cost: one more control and text, plus allowance and demo tests (about a day).
   - **(c) ON as the AC is worded,** as the Documents upload already is on the demo (34.2, DW-892). The visitor's files are stored per session, counted, dropped at sign-out and cleared by the golden-copy reset (AD-25 :977; a host procedure, H16). Risks: arbitrary visitor files on a shared host, file names in the shared Visual Trace, and the 14 MB body through the demo proxy (34.2's owner-side check).
   - The Telegram path never runs on the demo.
2. **Split (veto item 7: moving ACs to a not-yet-planned story in this release).**
   - Recommended: this spec is 25.3. The AC "Given the result of reading a file … When the reply is sent …" and the "replies match" part of the last AC move to a new **Story 25.6, "Reply to a sent file: Add to documents, Saved to memory and the read failure"**. 25.6 holds the reply rendering against fixture read results, `POST /api/v1/documents` taking a `fileRef` (so a Telegram file can be added too), the Telegram reply texts, the whole-flow "no file content in a production message body" e2e, and the GUIDE line.
   - The mock's `getFile` stays in 25.3, so 26.2's dependency statement ("Lane B's Story 25.3 merged (its file-store call and the mock's `getFile`)") stays true. A three-way split that moved the mock would change that statement, which is owner-only.
   - 25.6 needs the reply contract that no story fixes yet: what Lane A's reply carries for a read file (read or failed, the reason, the photo memory's `memoryRef`). Recommended: route it into Story 37.1 (its photo-caption contract) as an added AC. That is another epic's unplanned story, so it is the orchestrator's call.
3. **Veto items.** Each lists its online-demo behaviour.
   - **Route** `POST /api/v1/files`: any OcuTalonUser behind the AD-13 envelope. It stores only under the caller's own session and returns only that file's `{ref,name,mediaType,size}`. No route reads a file back in this story. Demo: 409.
   - **Table** `OcuTalon.Data.SentFile` (`^OcuTalonP.SentFile`, private database):
     - retention: the standard purge's `daysToKeep`;
     - session end: `DropSession`;
     - reset: the golden copy holds none;
     - Purge: Web area.
     - Demo: never written under (a).
   - **Columns**: `Msg.Item` +`FileRef`, `FileName`, `FileMediaType`, `FileSize`; `Channel.WebChat.Post` +the same four; `Data.Turn` +`SentFile` (JSON). Every one is an appended slot.
   - **Payload**: `chat.message` +`sentFile` (no new event type). **Error code**: `bad_file`, a Conventions row.
   - **Privileges, roles, grants, resources**: none. **Dependencies**: none.
   - **CI mock**: `getFile`, the download path, the control route `POST /_mock/telegram/files`, and `BOT_METHODS` +`getFile`.
   - **Spine Rule text**: an append to AD-4's sign-out list, AD-22 :851 (now built), and AD-27's Web-area purge list (SPINE ROWS). No new AD is needed; the contracts are rows of the existing tables.
4. **Standing real-HTTP route tests** (`web/e2e/api/files.spec.ts`):
   1. signed out on POST gives 401 `signed_out`;
   2. LIVE (OcuTalonUser) gets 202 with exactly `clientId` and `file{ref,name,mediaType,size}`, and LIVE's `/v1/state` shows the `sentFile`;
   3. second-session isolation both ways: PANEL's state and events never show LIVE's file, and LIVE's never show PANEL's;
   4. invalid parameters: every bad-body row and each refusal code, with the exact `{error:{code,message},reason,size}`;
   5. the body bound: a 14 MB body gives 413 `body_too_large`, and 10,485,761 bytes within the bound gives 400 `too_large`;
   6. the envelope: no `X-OcuTalon-Request` gives 403 `no_request_header`, `text/plain` gives 403 `not_json`, and `Origin: http://evil.example` gives 403 `wrong_origin`;
   7. `OCUTALON_TRACEONLY_USER` gives 403 `no_role`;
   8. a body `sessionRef` is ignored.
   The demo's 409 is class-level (Decided 12).
5. **GUIDE.md "New since 1.0.0"** (under "Your documents and memory"). Recommended in 25.6, once a sent file gets a reply. Proposed text: `- **Send a file in the chat.** On your own install, press the paperclip beside the message box, or drop a file on the chat, to send a PDF, a Word (.docx) file, or a JPEG or PNG photo of up to 10 MB. OcuTalon reads it and offers to add it to your documents; a photo's caption is saved to memory. Sending files is off on the online demo.` The README keeps its pointer. If the Planner wants a line in 25.3 instead, it says only what 25.3 does: `… to send it into the conversation. Sending files is off on the online demo.`
6. **Contended overlaps.** None of the planned files is in Epic 22's or Epic 36's footprint, and the spine is the only file Epic 0 also edits.
   - Epic 21: `Test/Data/Tables.cls`, where Epic 21 edits the Delivery row near :452 and this story appends near the Upload row :800.
   - Epic 21 and Epic 22: `ARCHITECTURE-SPINE.md`. Epic 21 edits :499-507, :655-659 and :864 (near this story's AD-22 :851 edit); Epic 22 edits :384.
   - `ci/mock/`: Epic 21's `server.mjs` and `helpers.mjs` and Epic 22's `constants.test.mjs` are not touched. This story edits `mock.mjs`, `scenarios.mjs`, `telegram.test.mjs` and `scenarios.test.mjs` only.
   - The catalog, README and GUIDE.md are not touched.
7. **Lead's numbers, corrected from code:** the More to try registry holds **16** items (`more-to-try-view.ts:160-177`), not fourteen. The last K number is **K30** (`more-to-try.spec.ts:395`; K29 is in `more-to-try-queues.spec.ts`). README :42 says "sixteen … fifteen of them on the online demo". This story adds no item.
8. **Interim before 26.2.** A file turn runs through `Decide` like any turn. Until 26.2, Lane A's `Agent.Input` renders only `Text`, which is empty for a file. Task 0 records what it renders. Locally, a sent file then gets a model reply to an empty message until 26.2 merges. Options: accept it, recommended (files are off on the demo, and step 6's release needs Epic 26); or hide the paperclip until 26.2 merges, which takes a capability flag in `/v1/state`, more surface. A canned interim reply is not offered: it would be a fixed reply on a channel, and Lane A would have to remove it from a Lane B class.
9. **CI groups:** no new live unit (`new_units: none`).
   - `Test.Core.Files`, `Test.Core.ConversationFiles` and `Test.Data.SentFile` join `image` (`lane-b@Contract,Core,Data,Live`), together with the `Test.Contract.Mock` and `Test.Core.SessionOpsDocuments` additions.
   - `Test.Web.FilesApi` joins `shards-6`.
   - The two specs join `live:sign-in` in `shards-10`.
   - The mock tests run in the hosted `web` job.
   - If `shards-10` has no room, add `files` to `SIGN_IN_2_DIRS` (`shards-4`).

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

### SPINE ROWS (this story's own; AD-33, Story 25.2's amended first AC)

`<date>` is the implement stage's UTC date.
- **Tables paragraph (:1418), appended:** `From step 6 Lane B owns \`SentFile\` (each file a user sends from the chat or, from Story 26.2, from Telegram: \`Ref\`, \`SessionRef\`, \`Channel\`, \`Name\`, \`MediaType\`, \`Size\`, the bytes in its private global stream and \`CreatedAt\`), written only by \`Core.Files.Store\`, read only through \`Ownership.SentFile\` (\`Core.Files.Open\`), dropped by \`SentFile.DropSession\` at a session's end and deleted by age with the standard purge; the online demo stores none while sending files is off there. [ADDED <date>, Story 25.3]`
- **Cross-area table, after :1492:** `| \`OcuTalon.Core.Files\`: \`Store(sessionRef, channel, name, content, .file, .sc)\` (the file-store call: size, empty and signature checks before anything is stored; codes \`too_large\`, \`empty\`, \`wrong_type\`), \`Open(ref, sessionRef, .sc)\`, \`SetItem(item, file)\` and \`RefusalText(code, size)\`; \`OcuTalon.Msg.Item\`'s \`FileRef\`, \`FileName\`, \`FileMediaType\` and \`FileSize\` (never the bytes, AD-21); \`chat.message\`'s \`sentFile\`. Called by \`Web.Files\` and, from Story 26.2, by Lane A's \`TelegramIn\`; \`Open\` is read by Story 26.2's \`Agent.Input\` and Story 26.3's caption request [ADDED <date>, Story 25.3] | B | Story 25.3 |`
- **Same table:** `| The composer's paperclip button and the chat's file drop (\`web/src/app/chat/\`), which post only to \`POST /api/v1/files\`; hidden on the online demo [ADDED <date>, Story 25.3] | B | Story 25.3 |`
- **REST table, after :1657:** `| \`POST /api/v1/files\` (\`clientId\`, \`name\`, \`content\` in base64) | \`OcuTalon.Web.Files\`, forwarded from \`Web.Api\`'s map: \`Core.Files.Store\` under the CSP session's \`SessionRef\`, then \`WebChatIn\` with the file's fields on the Item; 202 \`{"clientId", "file"}\`; 400 \`bad_file\` (with \`reason\` \`too_large\`, \`empty\` or \`wrong_type\`, and \`size\`); 413 \`body_too_large\` over 13,985,112 bytes; 409 \`not_available\` on the online demo before the body is read; any user with the OcuTalon user role, behind the AD-13 envelope [ADDED <date>, Story 25.3] |`
- **Conventions REST (:1220):** 400 codes gain "`bad_file` (with `reason` `too_large`, `empty` or `wrong_type`)" [ADDED <date>, Story 25.3].
- **AD-4 :194, AD-22 :851, AD-27 :1027 (Planner ruling, For the Planner 3):**
  - AD-4's sign-out list gains "from step 6 the session's sent files (`OcuTalon.Data.SentFile.DropSession`)".
  - AD-22's "`getFile` and the file-download path arrive in Story 25.3 (Lane B), for Story 26.2" becomes "`getFile` and the file-download path (`/file/bot<token>/…`, the token logged by length there too) serve fixture files registered through the control endpoint (Story 25.3), for Story 26.2".
  - AD-27's Web-area purge gains "and `SentFile` rows older than the task's days".

## Verification

`$LANE` stands for these variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=25 stage=implement'`. The fresh tag is `e25s3i` and the warm tag is `e25s3iw`.

Compile checks may use slot A: profile `ocutalon-slot-a`, namespace `OCUTALON`, passed on every MCP call, with `iris_server_info` first and one `iris_execute_tests` per message. Run one command per tool call, each sized to about 150 s; one test class per call is always safe. A call that the harness moves to the background is waited for in bounded foreground polls. Tear down only your own tags, and run `ci/warm.sh down` at the end, also after a failure. Scratch goes under the session scratchpad's `e25s3impl/`.

**Commands:**
- (loop) `$LANE OCUTALON_RUN_TAG=e25s3iw ci/warm.sh up` once. Then one class per call, `$LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e25s3iw ci/iris.sh class <Class>`, for each of:
  - `OcuTalon.Test.Data.SentFile`, `OcuTalon.Test.Core.Files`, `OcuTalon.Test.Core.ConversationFiles`, `OcuTalon.Test.Web.FilesApi`;
  - `OcuTalon.Test.Contract.Mock`, `OcuTalon.Test.Core.SessionOpsDocuments`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Data.Ownership`, `OcuTalon.Test.Msg.Contracts`;
  - the siblings `OcuTalon.Test.Core.ConversationTurns`, `OcuTalon.Test.Core.WebChatMessages`, `OcuTalon.Test.Web.DocumentsApi`, `OcuTalon.Test.Core.UploadContract` and `OcuTalon.Test.Live.Payloads`.
  Expected: each `CLASS … passed`.
- (loop) `node --test ci/mock/test/telegram.test.mjs ci/mock/test/scenarios.test.mjs ci/mock/test/server.test.mjs` -- all pass.
- (loop) `node --test web/scripts/files-view.test.mjs web/scripts/files-docs.test.mjs web/scripts/ux-strings.test.mjs web/scripts/floor-sources.test.mjs web/scripts/api-client-sources.test.mjs web/scripts/allowance-sources.test.mjs web/scripts/chat-view.test.mjs web/scripts/payloads.test.mjs`, then `node web/scripts/payloads.mjs --check` -- all pass.
- (loop) e2e:
  - First `$LANE OCUTALON_RUN_TAG=e25s3i ci/iris.sh build`.
  - Run `npm --silent --prefix web run e2e -- --list --reporter=json > "$SCRATCH/chromium.json"` and `node web/scripts/e2e-part.mjs k/n "$SCRATCH/chromium.json"`, choosing n so that the part holds at most two spec files.
  - Then `$LANE OCUTALON_RUN_TAG=e25s3i ci/iris.sh live sign-in --part k/n` for the parts holding `api/files.spec.ts`, `files/files.spec.ts`, `documents/documents.spec.ts`, `chat/chat.spec.ts`, `frame/frame.spec.ts` and `banners/banners.spec.ts` -- each part passes.
  - Finally `$LANE OCUTALON_RUN_TAG=e25s3i ci/iris.sh teardown`.
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- no `ad_id`, `ad_fields` or new `placeholder` finding, against the baseline taken at Task 0.
- (once) `$LANE OCUTALON_RUN_TAG=e25s3i ci/iris.sh live floor` (no `--part`; about 4 minutes, so it is polled if moved) and `$LANE OCUTALON_RUN_TAG=e25s3i ci/iris.sh live demo-path`, one per call -- each passes, with the paperclip in the floor walks.
- (once) `npm --prefix web test`; `npm --prefix web run lint`; `npm --prefix web run build`; `bash docker/tests/test-mock.sh` -- each passes.
- (once) `bash ci/checks.sh`, in batches of `CHECK_SCRIPTS` if one call cannot hold it -- every block passes, among them `test-storage.sh` (short names, prefix, release-diff), `test-class-rules.sh` (no new unchecked prepare), `test-boundaries.sh` (ASCII, Rule 14) and `test-ci-config.sh`.
- The full shards and groups are left to CI.

**Shared surfaces:**
- the table registry (`Test/Data/Tables.cls`) and `src/short-names.tsv`;
- `Msg.Item`'s properties (`Test.Msg.Contracts`) and the storage release-diff of `Msg.Item`, `Channel.WebChat.Post` and `Data.Turn`;
- the Ownership kinds (`TestIsolationEveryRowKind`);
- the REST table and `Web.Api`'s URL map and `BodyBounds` (the Map pins in `DocumentsApi`/`UsageApi`/`HistoryApi`);
- the `chat.message` payload and `payloads.ts`;
- the CI mock's `BOT_METHODS`, its log keys and its `getFile` pins;
- the composer's controls and the Tab order (frame, floor, chat and banners walks; `allowance-sources` counts unchanged);
- the `ux-strings`, `floor-sources` (drag-and-drop allow-list) and `api-client-sources` lists;
- the Documents page's picker and drop (D5-D8, unedited);
- `SessionOps.End`'s steps and the Web area's purge list;
- the spine's tables.

No More to try item, README or GUIDE count changes. Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations to record (Rule 19; one per AC, each observed red and reverted byte-identical):**
- AC 1: `Core.Files.SetItem` not setting `FileRef` -> `ConversationFiles` red and `files.spec.ts` (chip) red.
- AC 2: `Store` ignoring its `channel` argument -> `Test.Core.Files` (telegram) and `ConversationFiles` (telegram Item) red.
- AC 3: the download path serving the bytes base64-encoded as text -> `telegram.test.mjs` download test red; `shortPath` not rewriting `/file/bot` -> the token-length test red.
- AC 4: the size check removed from `checkFile` -> `files-view.test.mjs` and `files.spec.ts` (the 14 MB case: a request is counted) red; the size check removed from `Store` -> `Test.Core.Files` (10,485,761 bytes) red.
- AC 5: the `onlineDemo` check removed from `Send` -> `FilesApi` demo test red; the paperclip's demo `@if` removed -> `files.spec.ts` demo case red.
- AC 6: the `sentFile` kind's `SessionRef` clause removed -> `Test.Data.SentFile` and `api/files.spec.ts` (3) red; `DropSession` not called in `End` -> `TestSentFilesDropped` red.
- AC 7: the REST row deleted -> `files-docs.test.mjs` red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned as the first child of the split proposed in Design Notes → For the Planner 2 (25.3 here; the replies to a proposed Story 25.6). The online-demo behaviour is planned as OFF (option a), pending the Planner's ruling (For the Planner 1). The veto items, the public text and the spine's AD-text appends wait for the spec gate (For the Planner 3 to 6, PUBLIC TEXT, SPINE ROWS). Nothing was implemented, committed or pushed.
