---
title: 'Story 25.6: Reply to a sent file: Add to documents, Saved to memory and the read failure'
type: 'feature'
created: '2026-11-14'
status: 'done'
baseline_revision: '47e92fb818b0fb20dbcbc33786691ad6a447c47b'
baseline_commit: '47e92fb818b0fb20dbcbc33786691ad6a447c47b'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: ['oversized']
deferred:
  - summary: >-
      lint_spine.py answers "ok": false on the spine because of 10 pre-existing low "unfilled template token" findings (catalog slot syntax such as {time}, {day}, {n}), so the AC wording "ok: true" cannot hold; this story adds none.
    evidence: |-
      The same 10 findings, at lines 523, 1181, 1272, 1285, 1358 and 1370, are reported at baseline_revision and after this story. The ledger already holds this root cause as DW-638.
    location: >-
      _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md
    severity: low
  - summary: >-
      The Conversation hold of a document file turn under the production's PoolSize 1 is unmeasured (one ReadFile plus two Render reads per turn).
    evidence: |-
      Task 0 (d) measured 1.9 s (2-page PDF), 3.4 s (10-page) and 13.6 s (cap case, 199,989 characters) in a unit harness with a Decide double; 26.2's stop lines are 10 s and 45 s a read. A measurement on the running production under load would settle it.
    location: >-
      src/ocutalon/cls/OcuTalon/Core/Conversation.cls (ReadSentFile)
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** File turns are built end to end (25.3 store and route, 26.2 document read, 26.3 photo caption, 37.1 contracts), but `Agent.Input` `READSFILES` is 0. Every file turn, from the web or Telegram, gets the fixed no-reader reply and reaches no model. Nothing on the Lane B side calls `ReadFile`, carries the read result or the photo `caption`, or offers **Add to documents**. The memory card shows the over-cap notice for a 409 `pin_photo`.

**Approach:** Flip `READSFILES` to 1, for web and Telegram together. `Conversation` reads the file first. A failed read ends the turn with the code-written failure sentence and no model request. Otherwise the turn runs untrusted as today. The read result and the photo caption are carried on `Turn`, `chat.message` and `/v1/state`. The page shows, from a lazy chunk, a native **Add to documents** button for a read document and a "Saved to memory" chip for a photo. The documents route takes `{fileRef}`. The three approved texts, the AD-21 rewording and the DW-1313 notice land in the same commit.

## Boundaries & Constraints

**Always:**
- `READSFILES` is exactly 1. Web and Telegram reach the same `Conversation` read path, and no path differs between them.
- A file turn stays provenance `untrusted` from end to end (25.3 (i), AD-10 3b). The gate path is unchanged.
- `ReadFile` runs before the turn's first request is sent.
  - `read` 0 concludes the turn with `result.text` through `Conclude`. Nothing is sent to Decide, and no model request is made.
  - A status error from `ReadFile`, or a result that is not an object, is handled as `read` 0 with `Docs.Extract.Failure("failed")`.
- Carriers are built by code, are absent when empty, and hold no bytes, no base64 and no extracted text (Conventions row "File read results").
  - `Turn.FileRead` is the result without `text`.
  - `chat.message` `fileRead` is `{fileRef, kind, read, addable}`.
  - `Turn.Caption` and `chat.message` `caption` are `{memoryRef, text}`, kept only for a usable reply.
- Extracted text appears only in the turn requests' `Input`, as chat text does (37.1 ESCALATED ruling). It is never stored and never logged.
- About the file itself, a message body, step, log or trace carries only its ref, name, type and size (25.3 (iv)).
- Add to documents uses `POST /api/v1/documents` with `{"fileRef"}`. The bytes come only through `Core.Files.Open(ref, sessionRef)` of the caller's own session (AD-4). They go to `DocumentOps` through `Data.Upload`, as the `{name, content}` form does. No route serves bytes back (25.3 (ii)). The type comes from the stored row's byte-derived media type (25.3 (iii)).
- Online demo stays OFF. The files route answers 409 before reading the body, the paperclip is hidden, and a drop shows the off text. Telegram answers `files.offOnDemo` and fetches nothing. `ReadFile` reads nothing on the demo.
- New web code goes in lazy chunks: the reply's file controls and the DW-1313 sentence. `web/scripts/initial-bundle.test.mjs` (921,000 bytes) passes, and the cap is never raised.
- Texts 1, 2 and 3 land verbatim, and so does every other ruled string. New strings are only those listed in the Planner Gate.

**Never:**
- No GUIDE clause "offers to add it to your documents" (a Planner gate item; text 3 ships verbatim).
- No cache of extracted text (DW-1270).
- No new Telegram text, button or callback. A Telegram file is added from the web chat, where its turn shows.
- No change to the gate, `Agent.Content`, `Docs.Extract` or the Telegram fetch.
- No `PoolSize` change.
- No More to try item.
- No bytes or image in an `Outbound`, `Turn`, `chat.message` or `AddDocument` body.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Readable document (web) | PDF or .docx, text `[[mock:file-read]] <marker>` | The reply is the mock's. `fileRead` is `{fileRef, kind:"document", read:1, addable:1}`. The page shows **Add to documents** | none |
| Read failure (web) | Damaged, encrypted or no-text PDF | The reply is "I couldn't read that file: it's damaged or incomplete." (the reason by code). `fileRead` read 0, addable 0. No Decide request and no model request | Turn ends done; no Decision |
| Photo (web) | JPEG or PNG | The caption is saved (origin `photo`). `caption` is `{memoryRef, text}`, and the page shows "Saved to memory". No button | An unusable reply saves nothing: no `caption` |
| Photo not sendable | `Agent.Content.Readable` 0 | read 0 with reason `failed`: "I couldn't read that file: something went wrong while reading it." | No model request |
| Telegram readable PDF, photo or damaged PDF | Paired chat, product flag 1 (no seam) | The same replies in the chat. The Turn carries FileRead/Caption, and the web chat item shows the button or chip | Demo: `files.offOnDemo`, no fetch |
| Add by fileRef | `{"fileRef": own PDF/.docx}` | 200 `{result:"done", ref}`. AddDocument goes out with the stored name and type `pdf`/`docx` | 501 `not_built` as today |
| Add by fileRef: refused | Another session's, unknown or purged ref; a photo's ref; both or neither of fileRef/content; fileRef not a string | 404 `not_found`; 400 `bad_document` `wrong_type`; 400 `bad_document` | No command, no Upload row |
| Injection (live path) | Web PDF and Telegram photo caption asking to email, propose a fix or approve | `send_email` and `propose_fix` are denied UNTRUSTED. No approval row, no CommandsIn command (except the photo's SaveMemory), and the user's link is unchanged | none |
| Pin a caption | Memory card Pin on a photo memory (409 `pin_photo`) | "This memory came from a photo, so it can't be pinned." 409 `over_cap` still shows overCap | none |

</intent-contract>

## Code Map

Paths relative to the worktree; `S` = `src/ocutalon/cls/OcuTalon`.

**Flag and read (Lane A file, granted by 26.2 ruling H2):**
- `S/Agent/Input.cls`
  - `:315` `Parameter READSFILES = 0;` becomes 1. Rewrite `:313-314` and the class doc `:46-48`, which say "until Story 25.6".
  - `ReadFile` `:226-257` gives the result shapes: photo `{fileRef, kind, read, addable 0}` or read 0 `failed`; document `{..., chars, cut, addable 1}` or `{read 0, reason, text}`.
  - `ReadFile` re-extracts on every call (`ReadText` `:278`). So does `Render` (`:56`).
- `S/Core/Files.cls`
  - `Readable()` `:202` (with the seam argument).
  - `NoReaderText` `:214`, which stays for the seam path.
  - `Open` `:153` and `Describe` `:165`.
  - Rewrite the doc comment `:14-16`.

**Conversation (Lane B):**
- `S/Core/Conversation.cls`
  - `Begin` `:380-404`: the no-reader branch is at `:389-390`, and the decide send at `:392`.
  - `Reader()` `:537-542` is the seam that `Test.Core.ConversationProbe:88` overrides.
  - `ItemOf` `:427-438` gives provenance untrusted at `:432`.
  - `Conclude` `:725-740`: saves, then `Announce`, `Tell` and `Next`.
  - `Sourced` `:610-627` reads `learned` through `Kept` (`:621`, arrays only).
  - `Tell` `:757-776` carries `Learned` (`:767`).
  - Class doc `:7-12` and `:41-43`.
  - `Conversation` has `PoolSize` 1 (`S/Production.cls:89`).
- `S/Data/Turn.cls`: `Learned` `:87` and `SentFile` `:92`. The storage `<Value>`s end at 27 (`:191`), so new properties take 28 and up.
- `S/Live/Payload/ChatMessage.cls`
  - `Learned` `:67` and `SentFile` `:70`.
  - `FromRow` `:78-110`: SentFile at `:97`, Learned at `:106-107`.
- Parts to copy: `S/Live/Payload/Part/SentFile.cls` (`FromJSON` `:18`) and `Part/Learned.cls`.
- `/v1/state` chat items come from `S/Web/Api.cls` `ChatItems` `:1472`, which calls `ChatMessage.FromRow` (`:1479`), so nothing extra is needed there.
- `S/Agent/Content.cls` `Accepted` `:52-71` returns HostData `{"caption": {memoryRef, text}}` (`:70`). It is read only.

**Documents route (Lane B):**
- `S/Web/Documents.cls`
  - `Add()` `:97-124` parses `{name, content}` through `ParseBody` `:246`. The size checks are at `:101-108`.
  - The AddDocument build is at `:109-112`.
  - `Dispatch(command, .result, .bytes)` `:189-214` puts the bytes in `Data.Upload` and sets `UploadRef`.
  - `MESSAGEBADDOCUMENT` `:52`.
  - The class doc is at `:5-16`.
- `S/Msg/Command/AddDocument.cls` (Name, ContentType VALUELIST, UploadRef) and `S/Docs/Ops.cls` `OnAdd` `:91` are unchanged.

**Telegram (Lane A; doc comments only):**
- `S/Channel/Telegram/In.cls` `File()` `:657-681`.
  - The checks run in this order: demo, then size, then `Readable()` (`:671`), then file_id, then `Turn`. `Turn` checks the allowance before `Stored`/`Fetch` (DW-1340 fixed).
  - Rewrite the doc `:66-67`.
  - `NoReaderName` `:713` stays for the seam.
- `S/Channel/Telegram/Out.cls` `OnOutbound` `:162-178` is unchanged (no new Telegram text).

**Web (Lane B):**
- `web/src/app/chat/ocutalon-reply.ts`: the learned line is at `:87-88`. The new host goes after it.
- `web/src/app/chat/chat-view.ts`: `TurnView` `:114`. `caption` at `:122` is the "via Telegram" label, so the new photo field is `savedCaption`. The copies of learned and sentFile are at `:418-423`.
- `web/src/app/live/payloads.ts` is generated: `npm --prefix web run payloads`. `web/scripts/payloads.test.mjs:85` pins the `ChatMessagePayload` member order.
- The lazy pattern to copy is `web/src/app/settings/settings-page.ts:308` (`import('./mcp-section')` into a signal, then `*ngComponentOutlet`).
- `web/src/app/api/api-client.ts:311` `addDocument(name, content)` is the sibling of the new `addDocumentFromFile(fileRef)`.
- Memory card:
  - `web/src/app/rail/memory-card/memory-card.ts:691-707` `toggleFailed`: the 409 mapping is at `:705`.
  - `MEMORY_TEXTS` is at `memory-card-view.ts:25`. The card is eager (`rail/status-rail.ts:17`).
  - The sentence already exists at `S/Web/Api.cls:225` `MESSAGEPINPHOTO`.
- `web/src/app/chat/files-view.ts:75` `fileControls` is unchanged. It is eager and imported by `chat-files.ts`, `file-chip.ts` and `composer.ts`.
- `web/scripts/initial-bundle.test.mjs` (`MAX_INITIAL_BYTES` 921,000; 878.98 kB after 36.5) and `web/scripts/lazy-routes.test.mjs` (the static import graph).

**Docs:**
- `docs/security-overview.md`
  - Text 1 is appended to the model-requests bullet `:186`.
  - Text 2 is a new bullet right after the trace-content bullet `:169`, before the email bullet `:170`.
  - Pinned by `docker/tests/test-heartbeat-overview.sh` and `lib-heartbeat-overview.sh` (`overview_bullet_rule`).
- `GUIDE.md`: text 3 is the last bullet under "#### Your documents and memory" (`:20-25`).
  - `docker/tests/test-readme.sh`: add `B Send a file in the chat` to `NS_WANT` (`:1066-1085`) after `B The Memory card`, and change the header "17 bullets" (`:61-63`) to 18.
  - `telegram-demo` (`:1743`) passes as written.
  - `web/scripts/files-docs.test.mjs:4` comment.

**Spine:** `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`
- AD-21's file block `:902-923`. The unreadable-path sentence is at `:915`.
- AD-21's documents bullet `:813`.
- Conventions row "File read results" `:1360`.
- Ownership rows `:1633-1635` (the `READSFILES` probe row is `:1634`).
- AD-10 3b already holds DW-1343's sentence.

**Tests that pin the old state (shared surfaces; red at 1 unless changed):**
- `Test.Core.Files:TestNoReaderYet` `:215-226`
- `Test.Agent.SentFiles:TestSwitchOff` `:203-211`
- `Test.Channel.TelegramFile:TestNoReader` `:462-495` (asserts `Readable()` 0 at `:468`)
- `Test.Channel.TelegramChat:TestFileTurn` `:557-637` (production; no seam; asserts 0 at `:568`)
- `Test.Web.FilesApi:TestStateFlagOff` `:285-294` (`:293`)
- `web/e2e/api/files.spec.ts` `:224-233` and `:293-415` (`:368-369`, `:408-413`)
- `web/e2e/files/files.spec.ts`
  - `:112`, `:137` and `:205`: real turns that expect the no-reader reply (`:128`, `:133`, `:153`, `:210`).
  - `:232-242`: the real-state tripwire.
- `web/e2e-online/files.spec.ts` header `:13-17`.

**Seam-safe, unchanged:**
- `ConversationFiles:TestNoReaderReply` (seam 0), `TestReaderTurnIsUntrusted` and `TestMarkerReachesNothing` (seam 1)
- `TelegramFile` `NewProbe()` (reader 1)

**Rerun at 1 (no seam):** `ConversationFiles:TestFileItemBecomesTurn` `:80`, `TestSentFileFromTheRow` `:102` and `TestFileItemDrops` `:168`.

**Composer at 1:** the paperclip now shows on every local install. `web/e2e/floor/keyboard.spec.ts` (`:404` Shift+Tab from the composer) and any Tab walk or button count over the composer must be checked.

**Pins reused for DW-1343 (same gate path, `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls:222`, which reads only provenance and taint):**
- `Test.Bridge.Gate:TestUntrustedTurnRunsOnlySafeReadOnly` `:2015`, `:TestTaintedTurnRunsOnlySafeReadOnly` `:2025`, `:TestProxyDirectIsClassifiedAsTheNativeCall` `:1038` and `:TestProxyUnknownServer` `:1072`
- `Test.Mcp.Attach:TestDirectCall` `:1453` and `:TestReadOnlyTurn` `:437`
- `Test.Fix.AskedTurns:TestInjectedTurn` `:113` (`propose_fix`) and `Test.Fix.PartnerTurns:TestInjectedTurn` `:136`
- `Test.Agent.SentFiles:TestInjectionTurn` `:435` and `:TestInjectedEmail` `:469` (Decide level, flag-independent)

**Mock scenarios** (`ci/mock/scenarios/A/`): `file-read`, `file-injection`, `send-email-injected`, `propose-fix-injected` and `photo-caption` (marker). A web file turn has no text, so a web photo carries no marker.

**Message-body scan:** `Test.Core.SecretHandoff.TraceLeaks(text)` `S/Test/Core/SecretHandoff.cls:240`.

## Tasks & Acceptance

**Execution:**
- [x] Task 0 -- `## Verification` → Task 0 results -- measure before any product change, on the lane's warm stack:
  - (a) `node --test web/scripts/initial-bundle.test.mjs`: the initial total at HEAD.
  - (b) What `Docs.Extract` answers for the fake-bytes "PDFs" of `web/e2e/files/files.spec.ts` and of `web/e2e/api/files.spec.ts:293` (the reason code each would show).
  - (c) Whether a web photo turn (no text, so no marker) gets a usable reply from the mock. This decides whether the real-HTTP photo case can assert `caption`, or whether it is pinned through Telegram (with a marker) and ConversationFiles.
  - (d) The Conversation hold, in ms from `Begin` to the turn request's send, for the 2-page PDF and the cap case (`PdfBigText`). The record is labelled: one `ReadFile` plus two `Render` reads.
- [x] `S/Agent/Input.cls` -- set `READSFILES` to 1 and rewrite the "until Story 25.6" comments (`:46-48`, `:313-314`) -- ruling H2.
- [x] `S/Data/Turn.cls` -- append `FileRead` and `Caption` (`%String(MAXLEN = "")` JSON) with storage values 28 and 29 -- append-only under AD-5. Rows saved before this story hold no value.
- [x] `S/Core/Conversation.cls` --
  - In `Begin`, when `turn.SentFile` is set and `Reader()` is 1, call `##class(OcuTalon.Agent.Input).ReadFile(..ItemOf(turn), .result)`.
  - Set `turn.FileRead` (the result without `text`; an error or a non-object counts as read 0 `failed`).
  - For `read` 0, `Conclude(turn, text, "")`.
  - Otherwise save the turn, then send the decide request as today.
  - In `Sourced`, keep the HostData object `caption` as `turn.Caption` when `memoryRef` and `text` are non-empty strings. Use a small object reader beside `Kept`; name `Kept` as its sibling.
  - Update the class doc `:7-12` and `:41-43` -- DW-1269, AD-21.
- [x] `S/Live/Payload/Part/FileRead.cls` (new; `fileRef`, `kind`, `read`, `addable`; `FromJSON` like `Part/SentFile.cls`) and `S/Live/Payload/Part/Caption.cls` (new; `memoryRef`, `text`) -- extend the Part pattern.
- [x] `S/Live/Payload/ChatMessage.cls` -- add `FileRead` (`%JSONFIELDNAME=fileRead`) and `Caption` (`caption`) after `SentFile`, and fill them in `FromRow` -- `/v1/state` follows through `ChatItems`.
- [x] `S/Web/Documents.cls` --
  - In `Add()`, a body whose only member is a string `fileRef` takes the file form.
  - `Core.Files.Describe(fileRef, sessionRef)` returns "" → 404 `not_found`.
  - A media type that is not PDF or .docx → `Refuse(wrong_type)`.
  - `Core.Files.Open` gives the bytes. Build AddDocument with `Name` = the stored name and `ContentType` `pdf`/`docx` from the media type, and `Dispatch` as today.
  - A body with both forms, or with a non-string `fileRef`, → 400 `bad_document`.
  - The `BODYMAX` check stays first. Update the class doc and AD-21's documents bullet.
- [x] `S/Core/Files.cls`, `S/Channel/Telegram/In.cls` -- doc comments only (`:14-16`; `:66-67`) -- Readable is 1 from 25.6, and the no-reader reply is the seam path.
- [x] `web/src/app/live/payloads.ts` (regenerated), `web/scripts/payloads.test.mjs` -- the new members and their order.
- [x] `web/src/app/chat/chat-view.ts` -- `TurnView.fileRead?` and `savedCaption?`, copied from the payload when present.
- [x] `web/src/app/chat/file-reply.ts` and `file-reply-view.ts` (new, lazy) --
  - For a document with `read` 1 and `addable` 1: a native `<button type="button">Add to documents</button>`.
  - While its POST is pending, the button is disabled. On success it gives way to the `added` line; on failure the `addFailed` line shows. Both lines are `role="status"`.
  - For a turn with `savedCaption`: a "Saved to memory" chip, styled like `answer-sources.ts`'s `.chip`.
  - Its texts live only in `file-reply-view.ts`.
- [x] `web/src/app/chat/ocutalon-reply.ts` -- after the learned line, `@if` the turn has `fileRead?.addable` or `savedCaption`. Load `./file-reply` with `import()` into a signal, and mount it with `*ngComponentOutlet` and inputs. Follow the `settings-page.ts:308` pattern.
- [x] `web/src/app/api/api-client.ts` -- `addDocumentFromFile(fileRef)` posts `{fileRef}` to `${BASE}/documents`, next to `addDocument`.
- [x] `web/src/app/rail/memory-card/memory-card.ts`, `memory-card/pin-photo-text.ts` (new, lazy) -- for a 409 whose body code is `pin_photo`, `import('./pin-photo-text')` and set the notice to its sentence. The over-cap notice stays for `over_cap` -- DW-1313.
- [x] `docs/security-overview.md` -- texts 1 and 2 verbatim, at the places in the Code Map -- DW-1312.
- [x] `GUIDE.md` -- text 3 verbatim, as the last bullet under "Your documents and memory".
- [x] `docker/tests/test-readme.sh` -- `NS_WANT` and the header count.
- [x] `docker/tests/test-heartbeat-overview.sh`, `lib-heartbeat-overview.sh` -- a once-each rule for text 1's two sentences inside the model-requests bullet, and one for text 2 as its own bullet right after the trace-content bullet.
- [x] `web/scripts/files-docs.test.mjs`, `web/e2e-online/files.spec.ts` -- comment and header updates.
- [x] `ARCHITECTURE-SPINE.md` --
  - AD-21 `:915`, reworded (Design Notes).
  - AD-21's documents bullet gains the `{fileRef}` form.
  - The Conventions row `:1360` names the carriers: `Turn.FileRead`/`Caption`, `chat.message` `fileRead`/`caption`, and `/v1/state` chat items. No `Outbound`, and why.
  - The ownership row `:1634`: Story 25.6 sets it to 1.
  - New ownership rows (Lane B): the Turn columns, the payload parts, `file-reply.ts` (lazy) and the documents fileRef form.
  - Lint.
- [x] Tests -- IRIS:
  - `Test.Core.Files:TestReaderOn` (renamed from `TestNoReaderYet`): READSFILES 1, `Readable()` 1, and the four probe classes unchanged.
  - `Test.Agent.SentFiles:TestSwitchOn`: READSFILES 1.
  - `Test.Web.FilesApi:TestStateFlagOn`: true and equal to `Readable()`.
  - `Test.Channel.TelegramFile:TestNoReader`: the probe's reader forced 0, so the gated path stays pinned.
  - `Test.Core.ConversationFiles`, new with the seam on:
    - `TestReadFailure`: damaged PDF → the Failure text, no Decide send, `FileRead` read 0, and the chat.message `fileRead`.
    - `TestReadDocument`: readable PDF → decide sent after `FileRead` addable 1 is saved.
    - `TestReadError`: an Item whose `ReadFile` errs → `failed`.
    - `TestCaptionCarried`: a reply HostData `caption` → `Turn.Caption` and chat.message `caption`; a malformed caption is dropped.
    - `TestNoExtractedText`: the content marker is in no Turn column, chat.message or Outbound.
  - `Test.Live.Payloads`: the two parts.
  - `Test.Web.DocumentsApi:TestAddFromFile`: the I/O rows for the documents route. No base64 or bytes marker in any message body (`TraceLeaks`). Another session's ref → 404 and no Upload row.
  - `Test.Channel.TelegramChat:TestFileTurn`, rewritten at the product flag (DW-1342):
    - A readable PDF with `[[mock:file-read]]` → the mock's reply. A photo with caption `[[mock:photo-caption]]` → its reply, the photo memory, and `Turn.Caption`. A damaged PDF → the Failure text.
    - The size, demo and stranger cases are kept, and so is the token scan.
    - The session's `/v1/state` chat item for the PDF has `fileRead.addable` 1, and `Web.Documents` `{fileRef}` adds it.
  - `TelegramChat:TestInjectedFileTurn`: a PDF with `[[mock:send-email-injected]]` and one with `[[mock:propose-fix-injected]]`, and a photo whose caption carries `[[mock:send-email-injected]]` → each denial is UNTRUSTED; no ApprovalRequest row and no EmailOut/CommandsIn command (except the photo's SaveMemory); the session's AI link is unchanged.
- [x] Tests -- web:
  - `web/scripts/file-reply-view.test.mjs`: texts and the which-control rule.
  - `web/scripts/lazy-routes.test.mjs` (or a sibling): `file-reply` and `pin-photo-text` are never statically imported.
  - `memory-card-view.test.mjs` if texts move.
  - `web/e2e/api/files.spec.ts`:
    - Flip `:224` to true.
    - `:293` becomes the read-failure reply: the Failure text, no Decision, `decidesql` 0, and no mock entry naming the file.
    - New readable-PDF real-HTTP test (moved from 26.2): `[[mock:file-read]] <content marker>` with a `%<bytes marker>` comment → the done reply is the mock's, and `fileRead` addable 1. `POST /api/v1/documents {fileRef}` → 200, and GET lists the name (then removed). The bytes marker and the base64 are in no message and no mock log; the content marker is in no `Turn.Text`/`ReplyText`, no event-log row, and only in the turn request bodies.
    - New injection test: a PDF `[[mock:send-email-injected]]` → the mock log's tool result holds the UNTRUSTED denial, and no approval row.
  - `web/e2e/files/files.spec.ts`:
    - Real-path tests: the read-failure reply.
    - Real state: the paperclip is visible.
    - New: a readable PDF through the paperclip shows **Add to documents**. A keyboard press (Enter) gives the `added` line and the document on the Documents page.
    - A stubbed snapshot item with `caption` shows the "Saved to memory" chip, and a turn with neither shows no control.
  - `web/e2e/memory-card.spec.ts`: a mocked 409 `pin_photo` shows the sentence, and `over_cap` still shows overCap.
  - Floor and keyboard specs updated for the visible paperclip.

- [x] [Ruling] Contest Planner rulings on the Planner Gate (~04:50Z 2026-11-15, `.coordination/prompts/story-256-rulings-20261115.md`, BINDING):
  - P1: both texts approved verbatim, "Added to your documents." and "Couldn't add it to your documents. Nothing was changed."; pin both (Msg.Catalog or the view test).
  - P2: approved IN this story: text 3's GUIDE sentence ships as "OcuTalon reads it, offers to add a PDF or Word file to your documents, and saves a photo's caption to memory." (the rest of text 3 verbatim). Update the `docker/tests/test-readme.sh` / `NS_WANT` pin to match; the drop-text-3 mutation must still go red. FALLBACK: if the pin change spreads beyond `test-readme.sh` and `NS_WANT`, ship text 3 verbatim instead and record the new sentence under Design Notes as a follow-up for the Planner (the lead reports it as `PLANNER REPORT:`).
  - P3: the `FileRead` and `Caption` JSON columns on `Data.Turn` (storage 28-29) approved, on condition: `TestNoExtractedText` asserts neither column holds the extracted text, a copy of its characters, or any bytes (the hygiene mutation).
  - P4: `POST /api/v1/documents {fileRef}` approved, with conditions: (a) a fileRef of another user or another session gets EXACTLY the same answer (status and body) as a fileRef that does not exist — pin it as a row in `TestAddFromFile`; (b) the size and type limits are those of a direct upload, the type from the bytes, never the name; (c) no bytes and no extracted text in the response, the log or the trace.
  - P5: accepted; no Telegram chip, Add button or line.
  - More to try: none.
**Acceptance Criteria:**
- Given a local install at this story's HEAD, when `GET /api/v1/state` is read and the chat is opened, then `filesReadable` is true, `$Parameter("OcuTalon.Agent.Input","READSFILES")` is 1, and the paperclip and drop show. On the online demo the route still answers 409 `not_available` before the body, the paperclip is hidden, a drop shows the off text, and a Telegram file gets `files.offOnDemo` with no getFile.
- Given a signed-in user on a local install, when they send a damaged PDF through `POST /api/v1/files`, then the done `chat.message` reply is "I couldn't read that file: {reason}." (its code's plain reason), `fileRead.read` is 0, and no Decide request, Decision or model request exists for its Item.
- Given a readable PDF or .docx sent from the web chat, when its reply arrives, then the page shows a native **Add to documents** button under the reply. Pressing it by mouse or keyboard posts `{fileRef}` to `/api/v1/documents`, the line "Added to your documents." (Planner gate P1) replaces it, and the Documents page lists the file under its stored name.
- Given a photo sent from the web chat or a paired Telegram chat whose reply is usable, when its reply arrives, then a memory with origin `photo` exists, the `chat.message` carries `caption` `{memoryRef, text}`, and the page shows the "Saved to memory" chip and no Add button.
- Given a paired Telegram chat on the running production with the product flag (no seam), when it sends a readable PDF, a photo and a damaged PDF, then the chat gets the model's reply, the photo's reply and the same failure text. The session's `/v1/state` chat item for the PDF carries `fileRead.addable` 1, and `POST /api/v1/documents {fileRef}` adds it (DW-1342; AD-4, AD-29).
- Given `POST /api/v1/documents` with `{fileRef}`, when the ref is another session's, unknown or purged, or a photo's, or the body mixes forms, then it answers 404 `not_found`, 400 `bad_document` with `wrong_type`, or 400 `bad_document`, with no command and no Upload row. No message body holds the file's bytes or base64.
- Given READSFILES 1, when a web PDF whose text asks to email `x@example.com` or to propose a fix, and a Telegram photo whose caption asks to email, are processed through the production, then `send_email` and `propose_fix` are denied UNTRUSTED, no approval request is raised, no changing command reaches CommandsIn (except the photo's SaveMemory), and the user's AI link is unchanged. `call_mcp_tool` risky or unclassified is refused on the same gate path (cited pins, Design Notes).
- Given any web or Telegram file turn in this story's tests, when its messages, steps, event log and trace are scanned, then none holds the file's bytes, their base64 or an image, and `Turn`, `chat.message` and `Outbound` hold no extracted text.
- Given the memory card, when Pin on a photo memory answers 409 `pin_photo`, then the notice reads "This memory came from a photo, so it can't be pinned.", loaded from a lazy chunk, and a 409 `over_cap` still shows the over-cap notice (DW-1313).
- Given the docs and the spine at HEAD, when the doc tests and `lint_spine.py` run, then texts 1, 2 and 3 are present verbatim once each, `test-readme.sh` and `test-heartbeat-overview.sh` pass, AD-21's unreadable-path sentence reads for `READSFILES` 1, and the lint is `"ok": true`.
- Given the built web app, when `initial-bundle.test.mjs` and the lazy-import pin run, then the initial total is at most 921,000 bytes and `file-reply` and `pin-photo-text` are lazy chunks.
- Integration (Rule 1): the consumer, the web chat page, reads `chat.message` `fileRead`/`caption` that `Conversation` publishes on the real production, and shows the button or chip (`web/e2e/files/files.spec.ts` and `api/files.spec.ts`, real HTTP). The consumer `DocumentOps` receives the AddDocument that `Web.Documents` builds from a `fileRef`, and its document appears in `GET /api/v1/documents`.

### Review Findings

Code review 2026-11-15 (Blind Hunter 12, Edge Case Hunter 9, Verification Gap 7, Acceptance Auditor 7 findings; 11 patch, 1 defer, 21 rejected; high 0). Every patch below was applied in the review pass.

- [x] [Review][Patch] [medium] The Add to documents button hand-rolled half of the busy rule (aria-disabled only: no aria-busy, no spinner, no 10 s restore and notice; EXPERIENCE.md:423, Rule 2 reuse) -- it is now the shared `ServerButton` [web/src/app/chat/file-reply.ts:27]; the pending-add spec pins `aria-busy` and no `disabled` attribute [web/e2e/files/files.spec.ts:314]
- [x] [Review][Patch] [medium] `TestInjectedFileTurn` used chat 84017734136, which `TestEmptyTurn` counts texts for, so the two passed only in name order -- it has its own chat 84017734139 (added to `CHATS`) [src/ocutalon/cls/OcuTalon/Test/Channel/TelegramChat.cls:45]
- [x] [Review][Patch] [medium] The Telegram file tests left their sent files and photo memories behind (DropSessions deletes neither) -- `DropFiles` deletes both after each test, on every path [src/ocutalon/cls/OcuTalon/Test/Channel/TelegramChat.cls]
- [x] [Review][Patch] [medium] The probe recorded Begin's in-memory Turn, so "FileRead is saved before the decide request" could not fail -- `Record` reads the stored `FileRead` through SQL [src/ocutalon/cls/OcuTalon/Test/Core/ConversationProbe.cls:135]
- [x] [Review][Patch] [medium] AC 8 had no bytes, base64 or image scan on a Telegram file turn, and no file turn's agent steps were scanned -- `TestFileTurn` scans headers, bodies, audit and both turns' steps for the PDF's and the photo's base64 and the photo's bytes [src/ocutalon/cls/OcuTalon/Test/Channel/TelegramChat.cls]
- [x] [Review][Patch] [low] The Integration AC's caption half was unpinned on the real production -- `TestFileTurn` asserts that the photo's `/v1/state` chat item carries the Turn's caption [src/ocutalon/cls/OcuTalon/Test/Channel/TelegramChat.cls]
- [x] [Review][Patch] [low] `TestReadOnDemo`'s "no Caption" could not fail (no caption was scripted) -- the Decide double now holds a usable caption reply [src/ocutalon/cls/OcuTalon/Test/Core/ConversationFiles.cls:336]
- [x] [Review][Patch] [low] No `mutation:` line for the lazy `pin-photo-text` pin or for text 1 -- both applied, red observed, restored (Verification, code review)
- [x] [Review][Patch] [low] An error status from `ReadFile` was dropped without a log entry -- `ReadSentFile` logs it [src/ocutalon/cls/OcuTalon/Core/Conversation.cls:424]
- [x] [Review][Patch] [low] The web injection test computed `CHK|approvals` and never asserted it -- asserted equal to the count before the turn [web/e2e/api/files.spec.ts:577]
- [x] [Review][Patch] [low] TelegramIn's class doc said a readable file "goes on to Conversation" at step (3), before steps (4) to (6) -- reworded and wrapped [src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls:66]
- [x] [Review][Defer] [medium, unverified] Add to documents makes DocumentOps take the instance-wide `Docs.Extract` lock, which the next file turn's `ReadFile` waits on in Conversation's one job [src/ocutalon/cls/OcuTalon/Web/Documents.cls] -- deferred: an `occurrence` on DW-1357 (the PoolSize 1 hold, owner burndown); a measurement on the running production settles it

Rejected:
- (low, ledgered DW-1359 wontfix-accepted) A later `Render` re-read that fails after `ReadFile` succeeded falls back with the button shown -- the three reads are the spec's "Known, not changed".
- (low, DW-1360 wontfix-accepted) A destroyed component's late add answer -- not shown reachable; a guard would be untested.
- (low, DW-1361 wontfix-accepted) The memory card's late pin-photo notice race (Blind 12, Edge 8) -- a 119-byte cached chunk; needs a sequence guard.
- (low, DW-1362 wontfix-accepted) Identical "Add to documents" names and a chip that does not name the caption -- the UX text is fixed; a per-file name is new public text.
- (low, DW-1363 wontfix-theoretical) A failed Turn save in `ReadSentFile` -- logged; real only if a save fails on a healthy instance.
- (low, DW-1364 wontfix-theoretical) The fileRef form's `empty`/`too_large` checks are unreachable -- `Core.Files.Store` refuses both.
- (false) Read 0 with no `text` shows `failed` while `FileRead.reason` keeps its code (Edge 1, Acceptance 5) -- `Agent.Input.ReadFile` always sets `text` on read 0 (`:240`, `:254`); only QA's seam reaches it, on purpose.
- (false) `ReadFile` OK with an object missing members -- every OK path of `ReadFile` sets fileRef, kind and read.
- (by-design) A second add makes a second document -- Decided in-stage 6.
- (known) A rejected `import('./file-reply')` -- spec "Known, not changed" (DW-1330 family).
- (low, prior) The mount test `addable` vs `read && addable` -- the server never exports read 0 with addable 1.
- (false) `TestCaptionCarried`'s Outbound check misses a Caption member -- `Msg.Outbound` has no Caption property; the JSON members a caption could ride (`Learned`, `Memories`) are checked.
- (low) No "approve" injection case -- AC 7 names email and propose a fix; the approval count is asserted in every case.
- (false) "The extracted text is never stored" -- it means no cache and no Turn column; text 2 states that the trace holds it, as for chat text (37.1).
- (spec edit) The stale "Known, not changed" estimate and the Tasks' `role="status"` text -- spec edits; the deviations are recorded in Decided 12-13 and Task 0 (d).
- (prior) No live web-photo caption assertion -- Decided in-stage 18 and Task 0 (c).
- (by-design) DW-1343's `call_mcp_tool` and a caption `propose_fix` are pinned by citation -- the ruling allows the same-gate-path pins; Design Notes record them.
- (duplicate) `lint_spine.py` "ok": false -- DW-638.
- (false) memory-card MC14b/c "nothing was pinned" cannot fail -- it fails if the route stub stops matching and the real server pins.
- (low) `TestMarkerReachesNothing` now sees a damaged read -- the property is pinned for a readable PDF by `TestNoExtractedText`.

## Spec Change Log

- 2026-11-15 ~04:55Z, lead: Planner Gate ruled (`story-256-rulings-20261115.md`): P1 approved verbatim (pin), P2 approved in this story (with the test-readme/NS_WANT fallback), P3 approved with TestNoExtractedText, P4 approved with (a)-(c), P5 accepted. Worked into Tasks & Acceptance as the `[Ruling]` item.

## Review Triage Log

### 2026-11-14 -- Review pass
- verdicts: 33 findings (Blind Hunter 10, Edge Case Hunter 9, Verification Gap 14; the Intent Alignment Auditor is descriptive and filed no finding) -- high 0, medium 11, low 22, false 0, maybe-false 0
- findings:
  - `[low]` `[reject]` Add to documents shows again after a reload and a second press adds a second document (Blind 1, Edge 14) -- Decided in-stage 6 states it (no new stored state; the Documents page's own add allows duplicates); a per-ref idempotence is stored-data shape beyond the ruled columns.
  - `[medium]` `[patch]` Focus falls to the page when the pressed Add button gives way to the added line (Blind 2) -- the added line takes tabindex -1 and focus after render; pinned by the Enter test (`toBeFocused`); mutation recorded.
  - `[medium]` `[patch]` A rejected lazy import of pin-photo-text leaves the refused pin with no notice (Blind 3, Edge 12) -- `.catch` sets the existing pinFailed text; MC14c aborts the chunk and pins it; mutation recorded.
  - `[medium]` `[patch]` `mockcontent >= 0` can never fail, `readTrace` ignores a missing Turn row, `fileread`/`replytext` unasserted (Blind 4, VG 24) -- asserts `turnfound` 1, the fileread members without text, the mock's reply and `mockcontent` equal to the 2 turn-carrying requests.
  - `[low]` `[reject]` No live web-photo test asserts a usable reply (Blind 5, VG 30) -- Decided in-stage 18 and Task 0 (c): a web photo carries no mock marker; the photo is pinned through Telegram and ConversationFiles.
  - `[low]` `[reject]` GUIDE says Telegram users are offered Add to documents (Blind 6) -- the sentence is the Planner-ruled P2 text, shipped verbatim; no Telegram line is ruled (P5).
  - `[low]` `[reject]` No direct test of the add's states (Blind 7) -- the live specs pin pending, added, failed and Enter; the second press is added (VG 21).
  - `[low]` `[reject]` Two predicates for the controls (`addable` vs `read` and `addable`) (Blind 8, VG 32) -- the server never exports read 0 with addable 1; no reachable harm.
  - `[low]` `[patch]` `AddByFileRef` can leave the fixture session changed (Blind 9, VG 31) -- restored after a Try/Catch and the saves are asserted.
  - `[low]` `[patch]` The AD-10 3b amendment marker is spliced mid-sentence; the spec's Auto Run Result is stale (Blind 10, VG 33) -- the marker sits before the added sentence; Auto Run Result is rewritten here.
  - `[low]` `[reject]` A failed dynamic import of file-reply is unhandled (Edge 11) -- spec "Known, not changed" (DW-1330 family); the reply text still shows.
  - `[low]` `[reject]` The button stays after a purge answers 404 (Edge 13) -- a retry shows the failure line and changes nothing; no new text is ruled for a purge.
  - `[low]` `[reject]` Stale caption after a re-begun turn or a forgotten memory (Edge 15) -- Caption is set only from a usable reply that concludes the turn; a later Forget changes memories, as for the other chips; the fix is complex.
  - `[low]` `[reject]` FromFile does not re-check the stored name's extension (Edge 16) -- P4 (b): the type comes from the bytes, never the name; AddDocument carries ContentType.
  - `[low]` `[reject]` ReadFile may throw and bypass the read-failure reply (Edge 17) -- ReadFile returns statuses on every path read; a guard would be untested code.
  - `[low]` `[reject]` Added and failed lines carry no role=status (Edge 18) -- Decided in-stage 13 (one live region, EXPERIENCE.md:466).
  - `[low]` `[reject]` aria-disabled, not native disabled, while pending (Edge 19) -- Decided in-stage 12 (the shared busy-button convention); Playwright's toBeDisabled accepts it.
  - `[medium]` `[patch]` Text 3's wording is pinned only by bullet name (VG 20) -- `test-readme.sh` pins the bullet once, word for word, with three synthetic variants that must be flagged; mutation recorded.
  - `[medium]` `[patch]` A second press while the POST is pending is unpinned (VG 21) -- the pending-add spec counts POSTs and presses twice (exactly 1); mutation recorded (2 POSTs).
  - `[low]` `[patch]` No mutation lines for the chip copy, wrong_type and the mixed-body check (VG 22) -- each applied, red observed, restored; lines recorded.
  - `[low]` `[patch]` Two live mutation lines were never run red (VG 23) -- both run: the read-failure test and the injection test went red.
  - `[medium]` `[patch]` TestAddFromFile's TraceLeaks scan passes whatever the route does (VG 25) -- the probe now holds each command's properties; the scan covers them and the responses, with a positive control; a mutation that puts bytes in a command goes red.
  - `[medium]` `[patch]` TestInjectedFileTurn compares a link that may be empty and allows SaveMemory in all cases (VG 26) -- the link is asserted non-empty; SaveMemory is allowed only in the photo case.
  - `[medium]` `[patch]` An unusable or fallback reply with a caption is unpinned (VG 27) -- a new TestCaptionCarried case; mutation (Sourced above the fallback exit) goes red.
  - `[medium]` `[patch]` TestFileTurn lost its no-getFile assertion for the over-limit file (VG 28) -- the fetch record is taken before that file is sent and asserted unchanged.
  - `[low]` `[patch]` The readable-PDF spec removes the document at the end of `try` (VG 29) -- removal runs in `finally`.

## Design Notes

**Planner rulings (2026-11-15 ~04:50Z, binding; `.coordination/prompts/story-256-rulings-20261115.md`).** P1 approved verbatim; P2 approved in 25.6 (GUIDE sentence "OcuTalon reads it, offers to add a PDF or Word file to your documents, and saves a photo's caption to memory.", fallback to text 3 verbatim if the pin change spreads beyond test-readme.sh/NS_WANT); P3 approved with TestNoExtractedText; P4 approved with (a) same answer for another user's/session's fileRef as a missing one, (b) direct-upload limits, type from bytes, (c) no bytes/extracted text in response, log or trace; P5 accepted. Merge after 22.15; integrate forward before the push.

**Governing ADs:**
- **AD-21:** the read result, the unreadable path, the photo caption memory and the documents route.
- **AD-31:** `ContentClass` `Agent.Content` `Part`/`Accepted`, and HostData `caption`.
- **AD-10:** rules 3, 3a and 3b. An untrusted turn runs only safe read-only tools, and its content never reaches the user's link.
- **AD-11:** an offer never becomes an approval request.
- **AD-14:** provenance.
- **AD-4:** session ownership through `Core.Files.Open`/`Describe`.
- **AD-12:** the payload and snapshot carriers.
- **AD-5:** appended columns.
- **AD-6:** the image only in the runner's job.
- **AD-29:** lanes. The flag and the Telegram doc comments are Lane A files, granted by ruling H2. The test edits in `Test/Channel` and `Test/Agent` are footprint extensions for the runner to report.
- **AD-33:** one owner per row.
- **AD-30:** Conversation's order.
- **AD-13:** the web route envelope.

**Binding rulings, quoted:**
- **26.2 (f) H2:** "26.2 ships with **READSFILES = 0**. Story 25.6 flips it, together with its chip and texts." "Web and Telegram must not differ." Texts 1-3: "they land in **25.6's commit**". On text 3: "If 25.6 adds 'offers to add it to your documents', that extension goes to the Planner."
- **26.2 Spine:** "Word the AD-21 unreadable-path sentence for READSFILES = 0, so it stays true until 25.6 flips it."
- **26.2 condition 1:** "A PDF whose text says, for example, 'email the report to x@example.com' must make a TAINTED turn. A Telegram photo whose caption says the same must also make a tainted turn. In both, send_email is refused UNTRUSTED, no approval is raised and no tool runs."
- **DW-1343, option A:** "Untrusted plus quarantine meets that, AS LONG AS it covers EVERY approval-raising or risky path"; "propose_fix raises NO approval request; call_mcp_tool for a risky or unclassified tool is REFUSED; NO tool that changes anything runs."
- **25.3:**
  - "(a) OFF ... the route returns 409 not_available before reading the body, the paperclip is hidden ... Telegram never runs on the demo."
  - (i) "A turn that carries a SentFile is UNTRUSTED provenance".
  - (ii) "No route serves a stored file's bytes back".
  - (iii) "The type check uses the file's bytes".
  - (iv) "Nothing about a file goes into any log, trace or production message body except ref, name, type and size".
  - (5) "'offers to add it to your documents' needs 25.6".
- **37.1 ESCALATED:** "no bytes and no image. Extracted text may reach the turn like chat text".
- **Standing (DW-1282):** "new web code goes into lazy chunks ... Never raise the cap"; IRIS MCP calls name their profile.

**The approved texts, verbatim (26.2 H2; epics.md 25.6 block):**
1. Appended to the model-requests bullet of `docs/security-overview.md`: "A chat turn with a PDF or Word file carries the text OcuTalon read from it, quoted as data. A chat turn with a photo also carries that photo."
2. A new bullet after the trace-content bullet: "The trace also holds the text OcuTalon read from a file sent in the chat or Telegram, and a photo's caption, like a chat reply; a file's bytes and a photo itself are never in it."
3. `GUIDE.md`, the last bullet under "Your documents and memory": "- **Send a file in the chat.** On your own install, press the paperclip beside the message box, or drop a file on the chat, to send a PDF, a Word (.docx) file, or a JPEG or PNG photo of up to 10 MB; in Telegram, send it to your paired chat. OcuTalon reads it, and a photo's caption is saved to memory. Sending files is off on the online demo."

**AD-21 rewording (ruled; applied by Task "spine"):** "**The document read (Story 26.2)**: from Story 25.6 `Agent.Input` `READSFILES` is 1, so `Conversation` reads a web or Telegram file turn's file with `ReadFile` before its requests. A turn whose file cannot be read ends with `text` and reaches no model. A build whose `READSFILES` is not 1 (the probe's seam in tests) gives a file turn `Core.Files`' fixed no-reader reply instead." The rest of the sentence (`Render` reads, `""` for an unreadable document, `PHOTOASK`) is kept.

**Already delivered at HEAD (evidence):**
- `ReadFile` for both kinds: `Agent/Input.cls:226-257`.
- The caption memory and HostData: `Agent/Content.cls:52-71`.
- The failure sentence and reasons: `Docs/Extract.cls:50-70,159`.
- The no-reader gating of Telegram with the allowance before fetch: `Channel/Telegram/In.cls:657-681,777-797` (DW-1340 and DW-1341 resolved by 26.2).
- The demo guards: `Web/Files.cls`; `Telegram/In.cls:659`.
- Provenance untrusted for file turns: `Conversation.cls:432`.
- The AD-10 3b sentence: spine `:375`.
- The 409 `pin_photo` route and sentence: `Web/Api.cls:225,2274`.
- The paperclip gating by `filesReadable`: `files-view.ts:75`.

The AC parts not met at HEAD are the flip, the carriers, the button, the chip, the route form, DW-1313, the texts and the live-path pins.

**Consumes:**
- `Agent.Input.ReadFile`/`Render` (26.2, 26.3)
- `Agent.Content.Accepted` HostData `caption` (26.3)
- `Core.Files.Open`/`Describe` (25.3)
- `Web.Documents`/`DocumentOps` (34.2)
- `Docs.Extract` (19.6, 19.7)
- The CI mock scenarios
- `Test.Contract.Ac` is the signature oracle (37.1).

**Consumed-by:** no later story is planned. The new payload parts and Turn columns are read only by this story's page.

**Extend, don't copy (Rule 2):**
- `Part/FileRead` and `Part/Caption` extend the `Part/SentFile` pattern.
- The caption reader sits beside `Conversation.Kept`.
- `addDocumentFromFile` sits beside `ApiClient.addDocument`.
- The fileRef form reuses `Web.Documents.Dispatch`, `Refuse` and `Fail`.
- The lazy mount copies `settings-page.ts:308`.
- The TelegramChat file tests extend `TestFileTurn`.

**Ledger inbox (Rule 17):**
- **DW-1269:** addressed. `ReadFile` runs in `Begin`; read 0 ends through `Conclude`; the carriers are named; Add to documents goes by fileRef; and the hygiene AC uses "no bytes and no image".
- **DW-1312:** texts 1-2.
- **DW-1313:** the memory card task and its AC.
- **DW-1342:** `TelegramChat:TestFileTurn` at the product flag, and the real-HTTP web turn in `api/files.spec.ts`.

**DW-1343 and condition 1 on the live path:**
- The gate (`Gate.cls:222`) reads only the context's provenance and taint, never the channel or the item kind. So the generic pins cover a file turn once the live path is shown to hand the gate provenance `untrusted`. The cited pins: Gate:TestUntrustedTurnRunsOnlySafeReadOnly, :TestTaintedTurnRunsOnlySafeReadOnly, :TestProxyDirectIsClassifiedAsTheNativeCall and :TestProxyUnknownServer; Mcp.Attach:TestDirectCall and :TestReadOnlyTurn; Fix.AskedTurns:TestInjectedTurn; Fix.PartnerTurns:TestInjectedTurn; SentFiles:TestInjectionTurn and :TestInjectedEmail.
- The new live-path pins at READSFILES 1 are `TelegramChat:TestInjectedFileTurn` and the injection test in `api/files.spec.ts`. They prove `send_email` and `propose_fix` end to end.
- `call_mcp_tool` is proved by the cited gate and Attach pins plus the live provenance. No MCP server is attached in a file-turn fixture, because that would need a new mock scenario for little gain (inference).
- A text-only PDF turn is untrusted with `Tainted` 0, which is by design (DW-1343 option A).

**Decided in-stage:**
1. Telegram gets no "Saved to memory" line and no Add button, because either would be new Telegram text. A Telegram file is added from the web chat, where the same session's turn shows. So `Outbound` carries neither member, and the Conventions row says why.
2. `Turn.FileRead` and the chat.message `fileRead` are kept whatever the reply's outcome. A read document stays addable even if the model fell back.
3. A `ReadFile` error is read 0 `failed` (existing reason text).
4. The fileRef form refuses a mixed or bad body with the existing 400 `bad_document`/`MESSAGEBADDOCUMENT`, and an unseen ref with 404 `not_found`, as GET `/:ref` does. There is no demo branch, because no SentFile exists on the demo.
5. The content type comes from the stored, byte-derived media type, not from the name.
6. After a reload the button shows again. A second add is a second document, as the Documents page's own add allows (no new stored state).
7. Text 2 goes right after `:169`, the bullet on what the trace's content holds.
8. A web photo carries no mock marker, so Task 0 (c) decides the real-HTTP photo assertion.
9. The DW-1313 sentence is the server's, copied into the lazy text module, so the page keeps its own texts.

10. P2 was taken, not the fallback: text 3's GUIDE bullet ships with "OcuTalon reads it, offers to add a PDF or Word file to your documents, and saves a photo's caption to memory." The pin change stayed in `docker/tests/test-readme.sh` (`NS_WANT` by bold name, and the header counts 17 to 18); the sentence itself is pinned nowhere else, so no follow-up goes to the Planner.
11. `test-readme.sh`'s `docs` rule pinned the email trace bullet directly after the trace-role bullet; text 2 now sits between them, so the rule pins text 2 after the trace-role bullet and the email bullet after text 2, with a mutation for each. `test-heartbeat-overview.sh` and `lib-heartbeat-overview.sh` hold the rules `filetext` (text 1's two sentences once each, in order, inside the model-requests bullet) and `filetrace` (text 2 once, as its own bullet right after the trace-content bullet), each with synthetic variants that must be flagged.
12. The Add to documents button uses the shared `button button-secondary` classes. While its post is out it is `aria-disabled` (the busy-button convention of `controls.css`) and a second press does nothing.
13. DEVIATION (small, decided here): the added line and the failed line are plain paragraphs spoken once through the `Announcer`, and carry no `role="status"`. The task text says both are `role="status"`, but EXPERIENCE.md:466 rules "A single polite live region carries every announcement", and `announce-focus-sources.test.mjs` pins that no template holds a live role. The spec's intent (a screen reader hears each line once) is kept. The speakers list of that test gained `app/chat/file-reply.ts`.
14. Pins that the new surfaces moved, updated with their reason: `files-sources.test.mjs` (Web.Documents now calls `Core.Files.Open`, only to hand the bytes to the Upload row, and writes none), `ux-strings.test.mjs` (the `FILE_REPLY_TEXTS` import, "Add to documents" and "Saved to memory" as `ux`, the two P1 texts as `ruled`), `Test.Data.Tables` (Turn columns 28-29), `Test.Live.Payloads` (the contracts 36 to 38 and `TestChatMessageFileRead`).
15. `Conversation` gains the private seam `ReadFile` (a call of `Agent.Input.ReadFile`), which `Test.Core.ConversationProbe` overrides to inject an error status or a non-object (`readfile` in its records); the probe also records the Turn's `FileRead` at each call, so that "FileRead is saved before the decide request" is observable.
16. `FileRead` keeps `reason` for a failed read (a code, no text), and `chars` and `cut` for a read document; `chat.message` exports only `{fileRef, kind, read, addable}` (a failed read exports `addable` 0).
17. `Web.Documents.ParseBody` keeps its signature and behaviour; it now calls the new `ParseJSON` and `Interpret`, so that `Add` parses the body once and can take the fileRef form. Any other member beside `fileRef` is 400 `bad_document`.
18. Task 0 (c) decided that no live web-photo test asserts `caption`: the photo and its caption are pinned through Telegram (`TelegramChat:TestFileTurn`, with a marker) and `ConversationFiles:TestCaptionCarried`. The real-HTTP web test sends a readable PDF.
19. The live specs that need a model reply point the runners at the CI mock (`pointKeys`) and put the keys back (`restoreKeys`), because the sign-in stack has no model key (the turn would be the fallback `no_key`).
20. `TelegramChat.AddByFileRef` sets the fixture session's `IrisUser` to the signed-in user for the one route call and puts it back, because `Ownership.SessionRef` resolves the session of `$Username`.
21. `lint_spine.py` answers `"ok": false` at HEAD and now, with the same 10 low "unfilled template token" findings (`{time}`, `{old}`, `{new}`, `{day}`, `{reason}`, `{entry}`, `{finding}`, `{n}` in existing rows); this story adds none. The AC's "`"ok": true`" cannot hold until those rows are fixed (a deferral candidate).
22. `test-boundaries.sh` flagged an absolute local path in this spec's own Verification (`$LANE`), which was replaced by `<the coordination folder>`.
23. Review patches (this pass): after Add succeeds the added line (`tabindex="-1"`) takes focus through `afterNextRender`, because the pressed button leaves with the press (the focus-call pin of `announce-focus-sources.test.mjs` lists `file-reply.ts`); the lazy import of `pin-photo-text` that rejects shows the existing pin-failed text; `Test.Web.DocumentsApi:TestAddFromFile` scans what the probe records of each command (`DocumentsProbe.Held`, every property value) and the response bodies for the bytes marker and its base64, with a positive control, because the trace globals saw nothing of a probe that sends no message; `test-readme.sh` pins the whole GUIDE bullet of text 3 once; the live readable-PDF test asserts that the Turn row was found, its stored `FileRead` has no `text` member, its `ReplyText` is the mock's, and that the mock saw the content in exactly the file turn's two model requests.

**Known, not changed:**
- A document turn reads the file three times in Conversation's single job (`PoolSize` 1). 26.2 measured the cap case at 3.3 s per read, so about 10 s per turn (inference until Task 0 (d) measures it). A timed-out read ends the turn after one 45 s read.
- A lazy chunk that fails to load in a tab left open across an upgrade leaves the reply without its button (the DW-1330 family). The reply text still shows.

Planner gate: see `## Planner Gate`.

## Planner Gate

- **P1 new public text** (`web/src/app/chat/file-reply-view.ts`, new):
  - "Added to your documents." (after a successful add) is new.
  - "Couldn't add it to your documents. Nothing was changed." (after a failed add) is new; it echoes Documents' `removeFailed`.
  - Not new:
    - "Add to documents" is from UX (`EXPERIENCE.md:1161`).
    - "Saved to memory" is from UX (`EXPERIENCE.md:1162`).
    - "This memory came from a photo, so it can't be pinned." is ruled (26.3, `Web/Api.cls:225`).
    - "I couldn't read that file: {reason}." and its reasons are approved (`Docs/Extract.cls:50-70`).
  - Recommendation: approve both new texts.
- **P2 GUIDE extension (proposed, NOT shipped):** text 3's sentence "OcuTalon reads it, and a photo's caption is saved to memory." would become "OcuTalon reads it, offers to add a PDF or Word file to your documents, and saves a photo's caption to memory."
  - Recommendation: approve it as a one-line follow-up once 25.6 merges. It is then true, and 25.3 ruling 5 reserved the clause for this story.
  - The story ships text 3 verbatim either way.
- **P3 stored-data shape (veto window):** `OcuTalon.Data.Turn` appends `FileRead` and `Caption` (JSON strings, storage 28-29, AD-5). Neither holds extracted text or bytes. `Caption.text` is the model's caption, which is already stored as the photo memory and in `ReplyText`. Recommendation: approve.
- **P4 security posture (veto window):** `POST /api/v1/documents` gains `{fileRef}`.
  - It reads the caller's own stored file's bytes (AD-4, `Core.Files.Open`) into a `Data.Upload` row for `DocumentOps`.
  - It serves no bytes back.
  - The type comes from the bytes.
  - Recommendation: approve.
  - The flip itself (egress of file text and photos to the model) was approved under 26.2 H2. It is noted here, not re-asked.
- **P5 Telegram parity of the controls:** no Telegram text for the chip or the add (Decided 1).
  - Recommendation: accept.
  - A Telegram line would be new public text and a follow-up.
- **More to try:** none proposed. Sending files is off on the online demo, so an item would show only on own installs. Recommendation: none.

## Verification

`$LANE` stands for these variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR=<the coordination folder>/locks/lane-a OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=25 stage=implement'`. The fresh tag is `e25s6i` and the warm tag is `e25s6iw`.

**Runtime targets:**
- The lane's own throwaways (the tags above) for every test run and for Task 0.
- Slot A (MCP profile `ocutalon-slot-a`, namespace `OCUTALON`, named on every call, `iris_server_info` first) for compile checks only.
- Never a demo or shared server, and never `ocutalon-aihub-test`. One `iris_execute_tests` per message.

**How to run:**
- One command per tool call, in the foreground, with `timeout: 600000`.
- Each call is sized to about 150 s. One test class per call is always safe.
- Split browser units with `--part k/n` so that a part holds at most two spec files.
- Tear down only your own tags. Run `ci/warm.sh down` at the end, also after a failure.

**Commands:**
- (once) Task 0 on `$LANE OCUTALON_RUN_TAG=e25s6iw ci/warm.sh up`, then a scratch method run with `OCUTALON_WARM=1 ... ci/iris.sh class OcuTalon.Test.Agent.SentFiles:TestTask0`, and `node --test web/scripts/initial-bundle.test.mjs`.
- (loop) Warm, one class per call: `$LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e25s6iw ci/iris.sh class <Class>`. Each must print `CLASS … passed`.
  - `OcuTalon.Test.Core.Files`, `.Core.ConversationFiles` and `.Core.ConversationTurns`
  - `OcuTalon.Test.Agent.SentFiles` and `.Agent.Content`
  - `OcuTalon.Test.Web.FilesApi`, `.Web.DocumentsApi`, `.Web.Api` and `.Web.MemoryApi`
  - `OcuTalon.Test.Live.Payloads` and `.Contract.Ac`
  - `OcuTalon.Test.Channel.TelegramFile`
  - `OcuTalon.Test.Channel.TelegramChat:TestFileTurn` and `:TestInjectedFileTurn`, one call each
  - The cited pins: `OcuTalon.Test.Bridge.Gate`, `.Fix.AskedTurns`, `.Mcp.Attach` and `.Msg.Catalog`
- (loop) `node --test web/scripts/file-reply-view.test.mjs web/scripts/payloads.test.mjs web/scripts/lazy-routes.test.mjs web/scripts/files-view.test.mjs web/scripts/memory-card-view.test.mjs web/scripts/files-docs.test.mjs` -- all pass.
- (loop) `npm --prefix web run payloads`, then `git diff --stat web/src/app/live/payloads.ts` -- only the two members and two parts.
- (loop) e2e, one call each:
  - `$LANE OCUTALON_RUN_TAG=e25s6i ci/iris.sh build`.
  - List the specs with `npm --silent --prefix web run e2e -- --list --reporter=json > <scratch>/chromium.json`, and find the parts with `node web/scripts/e2e-part.mjs k/n`.
  - `ci/iris.sh live sign-in --part k/n` for the parts that hold `api/files.spec.ts` and `files/files.spec.ts`.
  - `ci/iris.sh live sign-in-3 --part k/n` for `memory-card.spec.ts`.
  - Each passes. Then `$LANE OCUTALON_RUN_TAG=e25s6i ci/iris.sh teardown`.
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- `"ok": true`, with no new finding.
- (once) `$LANE OCUTALON_RUN_TAG=e25s6i ci/iris.sh live demo-path` -- passes (UJ-1; the paperclip is now visible on a local install).
- (once) `ci/iris.sh live floor`, split with `--part` -- the keyboard and Tab walks with the paperclip pass.
- (once) `ci/iris.sh live online-demo`, split -- `e2e-online/files.spec.ts` passes: no paperclip, the off text, 409.
- (once) `node --test web/scripts/initial-bundle.test.mjs` -- at most 921,000 bytes, with the measured total recorded. Then `npm --prefix web test`, `npm --prefix web run lint` and `npm --prefix web run build`, one per call.
- (once) `bash ci/checks.sh`, in batches of `CHECK_SCRIPTS` if needed -- every block passes, among them `test-readme.sh`, `test-heartbeat-overview.sh`, `test-boundaries.sh` (ASCII, Rule 14) and `test-ci-config.sh`.
- (once) Fresh check (Rule 19): `ci/iris.sh shard lane-b@Contract,Core,Data,Live` and `shard lane-a@Channel`, forward and `--reverse`, one per call, split with `--part`. The full shards and groups are left to CI.

**Shared surfaces:**
- The `READSFILES` / `Readable()` / `filesReadable` / no-reader tripwires listed in the Code Map. Search `src/`, `web/e2e`, `web/e2e-online` and `web/scripts` for `filesReadable`, `READSFILES`, `NoReaderText` and `can't read files yet`.
- The `chat.message` payload members and their order (`payloads.test.mjs:85`, `Test.Live.Payloads:1300`, `payloads.ts`).
- `Data.Turn` storage.
- The `/v1/documents` body shapes (`Test.Web.DocumentsApi` `TestBadBodies`).
- The composer's button count and Tab order on a local install (floor, keyboard and chat specs).
- GUIDE's New since bullet list (`NS_WANT`) and the security-overview rules.
- The initial bundle and the static import graph.
- The memory card's 409 notices (`memory-card.spec.ts:659,843-848`).

Standing criterion: every test added or changed passes on a fresh environment, in either order. Each creates and removes its own sessions, files, documents and memories.

**Mutations (Rule 19; one per AC; apply, observe red, revert byte-identical):**
- AC flip: `READSFILES = 0` → `Core.Files:TestReaderOn`, `FilesApi:TestStateFlagOn` and the `files.spec.ts` real-state test go red.
- AC failure: in `Begin`, skip the read-0 `Conclude` (always send decide) → `ConversationFiles:TestReadFailure` (a Decide send is recorded) and `api/files.spec.ts` read-failure (`decidesql` > 0) go red.
- AC add: `addDocumentFromFile` posts `{name: fileRef}` → the `files/files.spec.ts` Add test goes red. `Web.Documents` ignores `fileRef` → `DocumentsApi:TestAddFromFile` goes red.
- AC photo: `Sourced` drops `caption` → `ConversationFiles:TestCaptionCarried` and `TelegramChat:TestFileTurn` (`Turn.Caption`) go red.
- AC Telegram: `Reader()`/`Readable()` answers 0 for channel telegram only → `TelegramChat:TestFileTurn` goes red (parity).
- AC route refusals: `Describe` called with `""` sessionRef (ownership skipped) → `DocumentsApi:TestAddFromFile`'s other-session row goes red.
- AC injection: `ItemOf` gives provenance `user` to a file turn → `TelegramChat:TestInjectedFileTurn` and the `api/files.spec.ts` injection test go red.
- AC hygiene: `FileRead` keeps `text` and a `chars` copy of the extracted text → `ConversationFiles:TestNoExtractedText` goes red.
- AC DW-1313: `pin_photo` mapped to overCap → the `memory-card.spec.ts` pin_photo case goes red.
- AC docs: drop text 2 → `test-heartbeat-overview.sh` goes red. Drop text 3 → `test-readme.sh` new-since goes red.
- AC bundle: import `file-reply` statically in `ocutalon-reply.ts` → the lazy-import pin goes red.

### Results (implement stage, 2026-11-15)

**Task 0 results** (measured before any product change was kept; warm stack `e25s6iw`, scratch method removed afterwards):
- (a) Initial bundle at HEAD: 888.40 kB (an `ng build` of `git archive HEAD web`). After this story: 889.67 kB (`npm --prefix web run build`; `file-reply` 2.78 kB and `pin-photo-text` 119 bytes are lazy chunks). `initial-bundle.test.mjs` passes with the cap unchanged at 921,000 bytes.
- (b) `Docs.Extract` answers the fake-bytes `%PDF-1.4 zz...` of `files/files.spec.ts` and `api/files.spec.ts:293` with reason `damaged` ("I couldn't read that file: it's damaged or incomplete."), and the fake `.docx` of `files.spec.ts` (a stored zip whose `word/document.xml` entry holds "zz") with reason `damaged` too. Those tests now assert that sentence.
- (c) A web photo has no text, so its Input holds no `[[mock:..]]` marker; by the mock's selection order (mock.mjs header: marker, guide prompt, mock key, else 500) it has no scenario, so no usable reply and no caption. Not run live (inference). So no real-HTTP web-photo test asserts `caption`: the photo and its caption are pinned through Telegram (`TelegramChat:TestFileTurn`, with a marker) and `ConversationFiles:TestCaptionCarried`; the web page is pinned by a stubbed snapshot item.
- (d) Conversation hold, from `Begin` to the turn request's send, labelled one `ReadFile` plus two `Render` reads, in a unit harness with a Decide double: fake PDF (a failed read, one `ReadFile` only) 784 ms; 2-page PDF 1,886 ms; 10-page PDF 3,370 ms; `PdfBigText` (the cap case, 199,989 characters, cut) 13,583 ms. Both are inside 26.2's stop lines (10-page 10 s, cap 45 s a read); this is a unit harness, not the production's `PoolSize` 1 path under load (UNMEASURED there).

**Mutations** (Rule 19; each applied, red observed, restored byte-identical from a saved copy):
- mutation: `READSFILES = 0` -> `Test.Core.Files:TestReaderOn` and `Test.Web.FilesApi:TestStateFlagOn` red (and, on a fresh stack, `files/files.spec.ts` "on the real state, with no stub, the paperclip is visible" red, with 5 more of that file's cases).
- mutation: in `Begin`'s `ReadSentFile`, skip the read-0 end (always send decide) -> `Test.Core.ConversationFiles:TestReadFailure` (a Decide send is recorded, no sentence) and `TestReadError` red. Live (fresh stack, `live sign-in --part 2/17`): the same mutation at `ReadSentFile` (`Quit 1` for a failed read) turns the `api/files.spec.ts` read-failure test red (see the patch mutations below).
- mutation: `addDocumentFromFile` posts `{name: fileRef}` -> `files/files.spec.ts` "a readable PDF: ... Enter adds it ..." red (the only red of that part, live).
- mutation: `Web.Documents` ignores `fileRef` (`If 0 {`) -> `Test.Web.DocumentsApi:TestAddFromFile` red.
- mutation: `Sourced` drops `caption` -> `Test.Core.ConversationFiles:TestCaptionCarried` and `Test.Channel.TelegramChat:TestFileTurn` ("the Turn's Caption ...", "names a photo memory") red.
- mutation: `Begin` treats telegram as not readable (`|| (turn.Channel = "telegram")`) -> `TelegramChat:TestFileTurn` red.
- mutation: `FromFile` takes the file's own session for `Describe` (ownership skipped) -> `DocumentsApi:TestAddFromFile` "another session's ref answers exactly like an unknown one" red.
- mutation: `ItemOf` gives a file turn provenance `user` -> `TelegramChat:TestInjectedFileTurn` red (the email and fix PDFs: "one tool step, so no tool ran"; the photo's denial sentence). `ConversationFiles:TestReaderTurnIsUntrusted` stays the unit pin; the `api/files.spec.ts` injection test is mutated live below.
- mutation: `FileRead` keeps `text` (the rendered extracted text) -> `ConversationFiles:TestNoExtractedText` red.
- mutation: `pin_photo` mapped to the over-cap notice (the lazy branch never taken) -> `memory-card.spec.ts` MC14b red (the only red of that part, live).
- mutation: drop text 2 from `docs/security-overview.md` -> `test-heartbeat-overview.sh` (`filetrace`) red. Drop the text 3 bullet from `GUIDE.md` -> `test-readme.sh` new-since "missing 'B Send a file in the chat'" red.
- mutation: import `file-reply` statically in `ocutalon-reply.ts` -> `lazy-routes.test.mjs` (no static import reaches file-reply) and `file-reply-view.test.mjs` (the dynamic-import pin) red.
- mutation (review patches, each restored byte-identical from a saved copy, `cmp` clean and `git diff --stat` unchanged): `chat-view.ts` stops copying `caption` into `savedCaption` -> `files/files.spec.ts` "a snapshot item with a saved caption shows the Saved to memory chip ..." red (live, `sign-in --part 10/17`).
- mutation: delete `this.state() === 'pending' ||` in `file-reply.ts` -> `files/files.spec.ts` "a turn that failed to add shows the failure line and keeps the button, and a pending add disables it" red (a forced second press made two POSTs to /documents; live, same run).
- mutation: remove the `afterNextRender(... '.added' ... .focus())` in `file-reply.ts` -> `files/files.spec.ts` "a readable PDF: the reply shows Add to documents, Enter adds it ..." red (the added line is not focused; live, same run).
- mutation: remove the `.catch(() => MEMORY_TEXTS.pinFailed)` of the lazy import in `memory-card.ts` -> `memory-card.spec.ts` MC14c red (live, `sign-in-3 --part 7/8`).
- mutation: `Web.Documents.FromFile` skips the wrong_type check (a photo's ref gets through) -> `Test.Web.DocumentsApi:TestAddFromFile` "a photo's ref is 400 bad_document with wrong_type" red.
- mutation: the mixed-body check `parsed.%Size() '= 1` removed -> `Test.Web.DocumentsApi:TestAddFromFile` bodies 1 to 4 (the mixed forms and another member) red.
- mutation: `Web.Documents.Add` puts the file's first 3,000 bytes into the command (`IdempotencyKey`) -> `Test.Web.DocumentsApi:TestAddFromFile` "the bytes marker and its base64 are in no command and no response" red.
- mutation: `Conversation.ReadSentFile` skips the read-0 end (`Quit 1` for a failed read, so decide is always sent) -> `api/files.spec.ts` "isolation and the read failure ..." red (live, `sign-in --part 2/17`; run together with the next).
- mutation: `Conversation.ItemOf` gives a file turn provenance `user` -> `api/files.spec.ts` injection test red ("the mock log's tool result holds the UNTRUSTED denial"), and the readable-PDF test goes red too (the turn falls back, reason `unusable`); same run. The injection test is therefore not vacuous.
- mutation: move `Do ..Sourced(...)` above the fallback exit in `Conversation.Replied` -> `Test.Core.ConversationFiles:TestCaptionCarried` red ("the Turn has no Caption" and "its chat.message has no caption", for both fallback replies).
- mutation: change one word of the GUIDE bullet ("offers to add" to "offers to save") -> `test-readme.sh` new-since "the guide does not hold the ruled bullet 'Send a file in the chat' once, word for word" red.

**Commands run, all green** (warm stack `e25s6iw` unless noted; fresh stack `e25s6i`):
- IRIS classes: `Test.Core.Files`, `.Core.ConversationFiles`, `.Core.ConversationTurns`, `.Agent.SentFiles`, `.Agent.Content`, `.Web.FilesApi`, `.Web.DocumentsApi`, `.Web.Api`, `.Web.MemoryApi`, `.Live.Payloads`, `.Data.Tables`, `.Contract.Ac`, `.Channel.TelegramFile`, `.Channel.TelegramChat:TestFileTurn` and `:TestInjectedFileTurn`, and the cited pins `.Bridge.Gate`, `.Fix.AskedTurns`, `.Mcp.Attach:TestDirectCall` and `:TestReadOnlyTurn` (the class's other methods were not run after a first call timed out client-side; the two cited ones pass), `.Msg.Catalog`.
- Fresh (Rule 19): `shard lane-b@Contract,Core,Data,Live` forward `--part 3/10` and `--part 10/10`, `--reverse --part 8/10` and `--reverse --part 1/10`; `shard lane-a@Channel` forward `--part 2/4` and `--reverse --part 3/4` (each holds `TelegramChat` and `TelegramFile`); `class OcuTalon.Test.Web.DocumentsApi`. The full shards are left to CI.
- Live: `live sign-in --part 2/17` (`api/files.spec.ts`, 20 passed), `--part 10/17` (`files/files.spec.ts`, 21 passed, run again after the Announcer change), `live sign-in-3 --part 7/8` (`memory-card.spec.ts`, 25 passed), `live floor` (110 passed; `keyboard.spec.ts` and `devices.spec.ts` updated for the paperclip), `live demo-path` (8 of 8 steps), `live online-demo` (56 passed; `e2e-online/files.spec.ts` passes).
- Web: `npm --prefix web test` (2,101 pass), `npm --prefix web run lint`, `npm --prefix web run build`, `node --test web/scripts/initial-bundle.test.mjs`; `npm --prefix web run payloads` changed only the two interfaces and the two members.
- Checks (`docker/tests/test-<name>.sh`): boundaries, storage, class-rules, ci-config, ci-changes, ci-sweep, compose-file, pinned-sources, after-start, healthcheck, lib-live, bootstrap, demo-path-gate, ci-warm, probe, install-script, readme, release-notes, release-checklist, bridge-guide, triage-heartbeat, mcp-notices, redact-shapes, cpf, bridge-example, eval-personas and heartbeat-overview pass. NOT completed inside the 150 s cap: eval-set, online-host, online-load, upgrade-harness, rehearsal and release-sequence (none reads a file of this story; left to CI).
- `lint_spine.py`: `"ok": false` at HEAD and now, 10 low placeholder findings both times, none new (Decided in-stage 21).

**New IRIS test units:** none. `TestAddFromFile`, `TestReadFailure`, `TestReadDocument`, `TestReadError`, `TestCaptionCarried`, `TestNoExtractedText`, `TestChatMessageFileRead` and `TestInjectedFileTurn` are methods of classes that already run in their groups (`lane-b` Core, Live, Web; `lane-a` Channel).

### QA stage (2026-11-15)

Gaps found by reading the implement stage's tests against the matrix and the rulings: the "read 0 with no text" guard of `ReadSentFile` and its photo branch could not fail; no test pinned a photo through `Conversation` (FileRead photo, addable 0) or a file turn with the online demo flag set; a failed `{fileRef}` add (the owner says not_built, failed, an error, or is not running) was not pinned (the file must stay, so that the button that stays after a failure can be pressed again); the ruling P4 refusals (another session's ref the same as an unknown one, a photo's ref, mixed bodies) were pinned only through the route class, not over real HTTP with two real users.

**Files (QA).**
- (QA) `src/ocutalon/cls/OcuTalon/Test/Core/ConversationProbe.cls`: the `ReadFile` seam gains the mode `notext` (read 0 with a reason and no `text` member).
- (QA) `src/ocutalon/cls/OcuTalon/Test/Core/ConversationFiles.cls`: `TestReadError` runs three modes (error, nonobject, notext) for a PDF and for a photo and asserts no Decision and the file's `kind`; new `TestReadPhoto` and `TestReadOnDemo`.
- (QA) `src/ocutalon/cls/OcuTalon/Test/Web/DocumentsApi.cls`: new `TestAddFromFileFailures`.
- (QA) `web/e2e/api/files.spec.ts`: new `uploadsOf` helper and the test "POST /api/v1/documents {fileRef}: another session's, an unknown and a photo's ref, and a body that mixes forms, are refused over real HTTP, and add nothing" (part 2/17).

No new IRIS test class, no CI group change, no product file touched.

**QA mutations** (Rule 19; each applied, red observed, restored byte-identical from a copy saved in the scratch folder, `cmp` clean):
- mutation: `ReadSentFile` swaps the `document` and `photo` branches of the fallback result's `kind` -> `Test.Core.ConversationFiles:TestReadError` red (the "error" and "nonobject" rows, document and photo).
- mutation: `ReadSentFile` drops its `If failure = "" Set failure = Failure("failed")` line (a read 0 with no text goes on to Decide) -> `TestReadError` red for the notext rows (the sentence, "nothing is sent to Decide", "no Decision").
- mutation: `Agent.Input.ReadFile` answers `addable 1` for a photo -> `Test.Core.ConversationFiles:TestReadPhoto` red (FileRead and chat.message fileRead).
- mutation: `Agent.Input.OnlineDemo` answers 0 -> `Test.Core.ConversationFiles:TestReadOnDemo` red (a PDF is read on the demo, a Decide request goes out).
- mutation: `Web.Documents.Add` discards the stored file after `FromFile` (a failed add consumes the file) -> `Test.Web.DocumentsApi:TestAddFromFileFailures` red ("the stored file is still there" for every answer, and the retry).
- mutation: `Web.Documents.Add` accepts a body with other members (`parsed.%Size() '= 1` removed) and `FromFile` skips the `wrong_type` check -> the new real-HTTP test in `web/e2e/api/files.spec.ts` red (live, `live sign-in --part 2/17`: a photo's ref answered 200 `done`; the only red of that part).

**QA runs** (lane-a throwaways, tags `e25s6qw` warm and `e25s6q` fresh, all torn down): `OcuTalon.Test.Core.ConversationFiles` passed (20 s), `OcuTalon.Test.Web.DocumentsApi` passed (1 s), `live sign-in --part 2/17` passed (21 passed, 52 s of tests, the new test 0.9 s); `npm --prefix web run lint` passed. The class `ConversationFiles` runs in the `lane-b` Core group and `DocumentsApi` in `lane-b` Web, both unchanged in `ci/units.sh`; `api/files.spec.ts` is in the chromium project.

### Code review (2026-11-15)

Lane-A throwaways only (warm `e25s6cw`, fresh `e25s6c`, both torn down). Each mutation applied, red observed, restored from a saved copy (`cmp` clean).
- mutation: delete `ReadSentFile`'s `turn.%Save()` (FileRead not saved before decide) -> `Test.Core.ConversationFiles` `TestReadDocument` and `TestReadPhoto` red (the probe reads the stored FileRead); green again on the same stack after the revert.
- mutation: `file-reply.ts` back to the hand-made `aria-disabled` button (the implement head) -> `files/files.spec.ts` "a turn that failed to add ... a pending add disables it" red on `aria-busy` (live `sign-in --part 10/17`, the only red of the part).
- mutation: a static `import { PIN_PHOTO_TEXT } from './pin-photo-text'` in `memory-card.ts` -> `lazy-routes.test.mjs` "no static import from the entry point reaches the file reply controls or the pin-photo text" red.
- mutation: drop "A chat turn with a photo also carries that photo." from `docs/security-overview.md` -> `test-heartbeat-overview.sh` `filetext` red.
- Not mutated (labelled): the new Telegram bytes/base64/image scan and the photo state-caption assertion (no product change that puts bytes in a body was tried), `TestReadOnDemo`'s caption (QA's `OnlineDemo` 0 mutation covers the test), and the chat-id and clean-up changes (`TestEmptyTurn` after `TestInjectedFileTurn` was not run in one call).
- Runs, all green: `Test.Core.ConversationFiles`; `Test.Channel.TelegramChat:TestFileTurn` and `:TestInjectedFileTurn`; live `sign-in --part 10/17` (21 passed) and `--part 2/17` (21 passed); `npm --prefix web test` (2,101), `npm --prefix web run lint`, `initial-bundle.test.mjs` (ServerButton is already in the initial bundle through `got-it.ts`); `test-boundaries.sh`, `test-class-rules.sh`.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `READSFILES` is 1 for the web chat and Telegram on one path. `Conversation.Begin` reads a file turn's file with `ReadFile` first (`ReadSentFile`): read 0, an error status or a non-object ends the turn through `Conclude` with the code-written failure sentence and sends nothing to a model; a readable file runs untrusted as before. `Turn.FileRead` (no text) and `Turn.Caption` (storage 28 and 29) feed `chat.message` `fileRead` and `caption` through the new payload parts and `/v1/state`. `POST /api/v1/documents` takes `{fileRef}` (own session only, bytes through `Core.Files.Open`, type from the stored byte-derived media type, another session's ref answers as a missing one). The page shows **Add to documents** and the "Saved to memory" chip from the lazy chunk `file-reply`, and the memory card shows the pin-photo sentence from the lazy chunk `pin-photo-text` (DW-1313). Texts 1-3 (text 3 with Planner-ruled P2 sentence), the AD-21 and AD-10 spine amendments, and the ownership/convention rows are in.

**Files changed.** Product (IRIS): `Agent/Input.cls`, `Core/Conversation.cls`, `Core/Files.cls` (doc), `Channel/Telegram/In.cls` (doc), `Data/Turn.cls`, `Live/Payload/ChatMessage.cls`, `Live/Payload/Part/FileRead.cls` and `Part/Caption.cls` (new), `Web/Documents.cls`. Product (web): `chat/file-reply.ts` and `file-reply-view.ts` (new, lazy), `chat/ocutalon-reply.ts`, `chat/chat-view.ts`, `api/api-client.ts`, `live/payloads.ts`, `rail/memory-card/memory-card.ts` and `pin-photo-text.ts` (new, lazy). Docs: `GUIDE.md`, `docs/security-overview.md`, the architecture spine. Tests: IRIS `Test/Core/ConversationFiles`, `ConversationProbe`, `Files`, `Data/Tables`, `Live/Payloads`, `Web/DocumentsApi`, `DocumentsProbe`, `FilesApi`, `Channel/TelegramChat`, `TelegramFile`, `Agent/SentFiles`; web `file-reply-view`, `lazy-routes`, `payloads`, `ux-strings`, `announce-focus-sources`, `files-sources`, `files-docs`, and e2e `api/files`, `files/files`, `memory-card`, `floor/keyboard`, `floor/devices`, `support/pdf`, `e2e-online/files`; shell `test-readme.sh`, `test-heartbeat-overview.sh`, `lib-heartbeat-overview.sh`.

**Review findings.** 33 findings in 26 grouped triage rows: 14 patched (9 of them medium), 12 rejected with the reasons recorded in the triage log, and 2 pre-existing or unmeasured items deferred from the implement stage (frontmatter `deferred:`). Nothing was `intent_gap` or `bad_spec`.

**Follow-up review recommended: true.** Nine medium entries were patched in this pass. The unverified risk: the patch pass's own edits (the focus move and tabindex in `file-reply.ts`, the `.catch` in `memory-card.ts`, `DocumentsProbe.Held` and the rewritten `TestAddFromFile` scans) were run green and mutated by their author but had no independent review.

**Verification performed.** Implement stage and patch pass: the IRIS classes of the Verification list pass on the warm stack; fresh-stack shards (forward and reverse parts) pass; live `sign-in` parts 2/17 (api/files, 20 passed) and 10/17 (files/files, 21 passed), `sign-in-3` 7/8 (memory-card, 26 passed), `floor` (110), `demo-path` and `online-demo` (56) pass; `npm --prefix web test` (2,101), lint and build pass; the initial bundle is 889.70 kB against the 921,000-byte cap (`file-reply` 2.95 kB and `pin-photo-text` 119 bytes lazy). The build-auto stage re-ran the doc and web script tests, `test-boundaries`, `test-readme`, `test-heartbeat-overview`, `test-class-rules` and the six scripts the implement stage could not finish (`eval-set`, `online-host`, `online-load`, `upgrade-harness`, `rehearsal`, `release-sequence`), all passing, and `ConversationFiles`, `DocumentsApi` and `TelegramChat:TestInjectedFileTurn` on a fresh warm stack. Mutation lines are under Verification (all red observed, restored byte-identical). No new IRIS test unit or CI group.

**Residual risks.** `lint_spine.py` stays `"ok": false` from 10 pre-existing placeholder findings (deferred, DW-638). The PoolSize 1 hold under load is unmeasured (deferred). A tab left open across an upgrade can lose the lazy chunk (spec "Known, not changed").
