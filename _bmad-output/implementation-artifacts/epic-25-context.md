# Epic 25 Context: Usage, history and files in the page (step 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 6 gives a signed-in user a look back at OcuTalon and more ways into it. A History page filters past decisions and incidents (done). Users can send a PDF, Word file or photo from the web chat or from Telegram, and it becomes an Item that OcuTalon can read, add as a document, or remember. Approver and viewer roles decide who may answer each kind of approval request. The Usage page that was this epic's first story now lives in Epic 37 (Story 37.2, done). The epic is built in Lane B's files. Lane A's Epic 26 depends on it: Story 26.2 reads files, 26.3 captions photos and 26.4 enforces roles.

## Stories

- Story 25.1: moved to Story 37.2 (Usage page, done)
- Story 25.2: Filter past decisions and incidents on the History page (done)
- Story 25.3: Send a PDF, Word file or photo from the web app or Telegram (next to plan)
- Story 25.4: Assign approver and viewer roles in Settings
- Story 25.5: Answer only with the right approver role, and say why otherwise

## Requirements & Constraints

- **Accepted files:** PDF, Word (.docx), and JPEG or PNG photos, sent from the web chat or from the paired Telegram chat.
- **Size limit:** 10 MB, which is 10,485,760 bytes, the same constant as the documents route and the extractor. A larger file is refused before anything is stored, with "That file is 14 MB; the limit is 10 MB." (the size is filled in), and nothing else happens.
- **Other types and read failures:** any other type is refused the same way with "I couldn't read that file: {reason}." and a plain reason. A file that couldn't be read gets that same sentence as its reply.
- **Replies:** a file that was read gets a reply offering **Add to documents**, which adds it through the existing documents route. A photo's reply shows a "Saved to memory" chip.
- **The Item:** a file becomes an Item carrying the file's `Ref`, name, media type and size, never its bytes. No file content may appear in a production message body.
- **Online demo:**
  - A file belongs to its session and is cleared at the reset.
  - Each send counts as one message against the session's allowance: 50 an hour, rolling, shared by chat, Telegram and guide prompts.
  - Sprint planning raised a concern about this criterion, because the Planner's online-demo safety rule decides what is switched on on the demo. The spec must say how the criterion is met and tested.
- **Accessibility:** the paperclip button is labelled and works by keyboard. Drag-and-drop is never the only way to send a file. Keyboard-only use, labelled controls and WCAG 2.1 AA contrast apply throughout.
- **Tests:** automated tests plus a Playwright spec under `web/e2e/`, using fixture Telegram file Items. They send each accepted type, a file of another type and an oversized file, from the page and through the file-store call as Telegram files. A mock test fetches a file through `getFile` and the download path.
- **Viewers (25.4):** a viewer is read-only, with no composer. Every state-changing route refuses a viewer with 403.

## Technical Decisions

- **Web envelope:**
  - State-changing calls need JSON, `X-OcuTalon-Request: 1` and a matching `Origin`.
  - A request with no session gets 401 `signed_out`. A user without the role gets 403 `no_role`.
  - The API's default body limit is 256 KB. A route that takes a file declares its own bound in `XData BodyBounds`, as the documents route does: its `BODYMAX` of 13,985,112 bytes covers 10 MB in base64 plus the JSON around it. It refuses a larger body with 413 `body_too_large` before parsing and reads the bytes from the request stream, never through a string.
  - Untrusted text, including file names and model text, renders as text only.
- **What exists from step 3:**
  - `POST /api/v1/documents` takes `{name, content}`, with the bytes in base64. It maps the extension to `ContentType` and refuses `wrong_type`, `too_large` and `empty` with 400 `bad_document` before it submits.
  - It stages the bytes in `OcuTalon.Data.Upload` (Lane B; `Ref` plus `SessionRef` matched exactly through `Ownership.Upload`), because a message body can't hold a global stream. `AddDocument` carries the `UploadRef`.
  - `Upload.Take(ref, sessionRef)` deletes the row it returns. `Upload.Purge` drops untaken rows after an hour. `Upload.DropSession` runs in `SessionOps.End`.
  - Because of the purge and the delete-on-take, the existing Upload table doesn't obviously fit a file that must outlive its Item. The spec decides whether to reuse it or add a private file table.
- **Extraction (Lane A, built):** `OcuTalon.Docs.Extract.Read` picks the parser from the bytes' signature. It returns text or a machine code: `too_large`, `wrong_type`, `encrypted`, `damaged`, `no_text`, `legacy_doc`, `contents_too_large`, `timed_out` or `failed`. `Failure(code)` fits each code into "I couldn't read that file: <reason>.", and the `too_large` and `wrong_type` reasons match the web catalog's text exactly.
- **New contracts 25.3 adds in the same change** (AD-29, AD-33):
  - the upload route in the REST table
  - the private file table in the ownership tables
  - the file fields on `OcuTalon.Msg.Item`, which today has none
  - the file-store call that Lane A's `TelegramIn` will call, in the cross-area API table
  - None of these are in the spine yet. Only the owning lane edits a class, so 25.3 must not edit `TelegramIn` (Lane A).
- **Items and provenance:** every inbound message is an `OcuTalon.Msg.Item` with `SessionRef`, `Channel`, `Provenance` and content. File text reaches the model only as quoted, untrusted data through `OcuTalon.Agent.Input`, which is Story 26.2's job.
- **Telegram:**
  - The bot token comes from the environment and never enters a setting, a status text or a log line.
  - Chat ids and display names never reach the audit writer, logs or step summaries.
  - On the online demo, an outbound gateway swaps a dummy token for the real one. Its file-path route is a release check for Story 26.2.
- **CI mock (Lane B):**
  - Telegram scenarios name a Bot API method and reply with `status`, `headers`, `delayMs` and `body`. The control endpoint records every call.
  - The mock currently refuses `getFile` with a 404 that points at Story 25.3. 25.3 adds `getFile` and the download path `/file/bot<token>/<file path>`.
  - The token is logged by length only, in the URL path as everywhere else.
- **Online demo data:** a reset restores a golden copy that holds no sessions. A sign-out runs `SessionOps.End`, which drops the session's uploads, documents and memories. `Core.Allowance` is called synchronously before a turn is queued. On refusal, `POST /messages` returns 429 with `retryAt`.
- **Roles (25.4/25.5):**
  - Role names: `OcuTalonApprover`, `OcuTalonApprover_<kind>`, `OcuTalonViewer`.
  - `Approval.MayAnswer(Ref, IrisUser)` and the role-assignment method are Lane A's. Story 37.1 (still in the backlog) supplies stubs until Story 26.4 builds them. Until then tests create the roles as fixtures.
  - `AnswersIn` returns `not_allowed` with the kind. From step 6 the demo account holds `OcuTalonApprover`, and the owning-session rule still applies.

## UX & Interaction Patterns

- **Composer:**
  - It is labelled "Message OcuTalon", persistently. Enter sends; Shift+Enter adds a new line.
  - Step 6 adds a paperclip button in the composer, with drag-and-drop on the chat as a second way. Telegram files follow the same rules.
  - When the allowance is used up, the composer is `aria-disabled` with its reason as visible text above it, linked by `aria-describedby`.
  - Styling: a surface text area with the strong border and a primary "Send" button.
- **File texts:**
  - "That file is 14 MB; the limit is 10 MB."
  - "I couldn't read that file: {reason}."
  - the **Add to documents** offer on a file's reply
  - the "Saved to memory" chip on a photo's reply
  - Telegram and the simulated phone share each catalog text exactly, as plain text with no Markdown.
- **Viewers:** see everything read-only, with no composer.
- **Roles UI:** a Settings › Roles section. Where a user can't answer, the request reads "Only an approver for resends can answer this request." (the fixture sentence for one kind), with no **Approve** or **Reject**.

## Cross-Story Dependencies

- **Story 25.3 provides for Epic 26:**
  - Story 26.2 needs 25.3's file-store call and the mock's `getFile`; `TelegramIn` will check the size, download, store the file and send the Item.
  - Story 26.3 needs 25.3's photo Items; its reply carries the caption and the memory's reference for the chip.
- **25.3 builds against results it doesn't have yet:**
  - The read results come from Lane A's Stories 19.6 (built), 26.2 and 26.3, all unmerged except 19.6. 25.3 uses fixture results and fixture Telegram file Items until they merge.
  - Story 37.1 hasn't fixed a photo-caption name yet.
- **Stories 25.4 and 25.5:** depend on Story 37.1's stubs. Story 26.4 needs 25.5's `not_allowed` from `AnswersIn`. Story 25.4 builds on the online demo account and the step-2 Settings sections.
