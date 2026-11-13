# Epic 25 Context: Usage, history and files in the page (step 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 6 gives a signed-in user a look back at OcuTalon and more ways into it. A History page filters past decisions and incidents (done). Users can send a PDF, Word file or photo from the web chat or from Telegram. The file is stored safely and becomes an Item (25.3), and OcuTalon's reply says whether it could read the file and offers the next step (25.6). Approver and viewer roles decide who may answer each kind of approval request (25.4, 25.5). The Usage page that was this epic's first story now lives in Epic 37 (Story 37.2, done). The epic is built in Lane B's files. Lane A's Epic 26 depends on it: Story 26.2 reads files, 26.3 captions photos and 26.4 enforces roles.

## Stories

- Story 25.1: moved to Story 37.2 (Usage page, done)
- Story 25.2: Filter past decisions and incidents on the History page (done)
- Story 25.3: Send a PDF, Word file or photo from the web app or Telegram (ready for dev)
- Story 25.4: Assign approver and viewer roles in Settings
- Story 25.5: Answer only with the right approver role, and say why otherwise
- Story 25.6: Reply to a sent file: Add to documents, Saved to memory and the read failure

## Requirements & Constraints

- **Accepted files (25.3):** PDF, Word (.docx), and JPEG or PNG photos, sent from the web chat or from the paired Telegram chat.
- **Size limit:** 10 MB (10,485,760 bytes), the same constant the documents route and the extractor use. A larger file from either channel is refused before anything is stored, with "That file is 14 MB; the limit is 10 MB." (the size filled in), and nothing else happens.
- **Type check:** the type comes from the file's bytes, never only from its name or declared type. Any other type, a renamed .exe or .html included, is refused the same way with "I couldn't read that file: {reason}.", where the reason is "it isn't a PDF, Word (.docx), JPEG or PNG file".
- **The Item:** a file becomes an Item that carries the file's `Ref`, name, media type and size, never its bytes.
- **Four security conditions (25.3), each with its own test:**
  1. A file turn has `untrusted` provenance even when its text is empty, so only read-only tools run in it. Story 26.2 keeps that marking when it reads the content.
  2. No route serves a stored file's bytes back to anyone except, at most, its own session.
  3. The type is detected from the bytes, as described above.
  4. Nothing about a file reaches a log, the trace or a production message body except its ref, name, type and size. The name is length-capped and escaped.
- **Online demo (25.3): sending files is off.**
  - The paperclip is hidden.
  - A file dropped on the chat shows "Sending files is off on the online demo. It works on your own install."
  - The file route answers 409 `not_available` before it reads the body. Nothing is stored and nothing is counted against the allowance.
  - Telegram never runs on the demo.
  - Wherever files do run, a sent file belongs to its session and is dropped at sign-out, at the reset and by the standard purge.
- **Before there is a reader (25.3):** on a local install, the paperclip and the chat drop stay hidden behind a `/v1/state` capability flag that turns on only once Story 26.2's read path has merged. As defence in depth, a file turn that arrives with no reader gets the fixed reply "I got {name}, but I can't read files yet." and no model call is made.
- **Replies (25.6):**
  - A file that couldn't be read gets "I couldn't read that file: {reason}." with a plain reason.
  - A file that was read gets a reply offering **Add to documents**, which adds it through the documents route.
  - A photo's reply shows a "Saved to memory" chip.
  - Telegram replies carry the same failure text, and a Telegram file that was read can be added to the documents too, through the documents route taking the stored file's `Ref`.
  - The guide's "New since 1.0.0" gains its file line only with the clauses whose stories have merged: "offers to add it to your documents" with 25.6, and "a photo's caption is saved to memory" with 26.3.
- **Accessibility:** the paperclip button is labelled and works by keyboard. Drag-and-drop is never the only way to send a file. Keyboard-only use, labelled controls and WCAG 2.1 AA contrast apply throughout.
- **Tests:**
  - 25.3: automated tests plus a Playwright spec under `web/e2e/` with fixture Telegram file Items. They send each accepted type, a file of another type and an oversized file, from the page and through the file-store call as Telegram files. The Items and refusals must match, and no file content may appear in a production message body. A mock test fetches a file through `getFile` and the download path.
  - 25.6: uses fixture read results until 26.2, 26.3 and 37.1 merge. Replies match, Add to documents adds the file, and no file content appears in a production message body anywhere in the flow.
- **Viewers (25.4):** a viewer is read-only, with no composer. Every state-changing route refuses a viewer with 403.

## Technical Decisions

- **Web envelope:**
  - State-changing calls need JSON, `X-OcuTalon-Request: 1` and a matching `Origin`.
  - A request with no session gets 401 `signed_out`. A user without the role gets 403 `no_role`.
  - Errors use the form `{"error": {"code", "message"}}`, with 409 for "not available".
  - Demo-off routes follow the email and webhook settings precedent: 409 `not_available` before the body is read, and the page hides the feature.
  - The API's default body limit is 256 KB. A route that takes a file declares its own bound in `XData BodyBounds`, as the documents route does: its `BODYMAX` of 13,985,112 bytes covers 10 MB in base64 plus the JSON around it. It refuses a larger body with 413 `body_too_large` before parsing and reads the bytes from the request stream, never through a string.
  - Untrusted text, including file names and model text, renders as text only.
- **What exists from step 3:**
  - `POST /api/v1/documents` takes `{name, content}` with the bytes in base64, maps the extension to `ContentType`, and refuses `wrong_type`, `too_large` and `empty` with 400 `bad_document`.
  - It stages the bytes in `OcuTalon.Data.Upload` (matched by `Ref` plus `SessionRef` through `Ownership.Upload`), because a message body can't hold a global stream.
  - `Upload.Take` deletes the row it returns, and `Upload.Purge` drops untaken rows after an hour. A sent file must outlive its Item, so the criteria call for Lane B's own private file table rather than this staging table.
  - 25.6's Telegram path needs the documents route to accept a stored file's `Ref` as well as base64 content.
- **Extraction (Lane A, built in 19.6):** `OcuTalon.Docs.Extract.Read` picks the parser from the bytes' signature. It returns text or a code: `too_large`, `wrong_type`, `encrypted`, `damaged`, `no_text`, `legacy_doc`, `contents_too_large`, `timed_out` or `failed`. `Failure(code)` fits each code into "I couldn't read that file: <reason>.".
- **New contracts that 25.3 adds to the spine in the same change** (AD-29, AD-33):
  - the upload route in the REST table
  - the private file table in the ownership tables
  - the file fields on `OcuTalon.Msg.Item`, which today has none
  - the file-store call that Lane A's `TelegramIn` will call, in the cross-area API table
  - the `/v1/state` capability flag
  - Only the owning lane edits a class, so 25.3 must not edit `TelegramIn` (Lane A).
- **Items and provenance:** every inbound message is an `OcuTalon.Msg.Item` with `SessionRef`, `Channel`, `Provenance` (`user` or `untrusted`) and content. An untrusted turn runs in a fresh AI session, and only read-only tools may run in it. File text reaches the model only as quoted, untrusted data through `OcuTalon.Agent.Input`, which is Story 26.2's job.
- **Telegram:** the bot token comes from the environment and never enters a setting, a status text or a log line. Chat ids and display names never reach the audit writer, logs or step summaries.
- **CI mock (Lane B):** the mock currently refuses `getFile` with a 404 that points at Story 25.3. 25.3 adds `getFile` and the download path `/file/bot<token>/<file path>`, and logs the token by length only there too.
- **Roles (25.4/25.5):**
  - Role names: `OcuTalonApprover`, `OcuTalonApprover_<kind>`, `OcuTalonViewer`.
  - `Approval.MayAnswer` and the role-assignment method are Lane A's. Story 37.1 supplies stubs until Story 26.4 builds them, and until then tests create the roles as fixtures.
  - `AnswersIn` returns `not_allowed` with the kind. From step 6 the demo account holds `OcuTalonApprover`, and the owning-session rule still applies.

## UX & Interaction Patterns

- **Composer:** it is labelled "Message OcuTalon" persistently. Enter sends; Shift+Enter adds a new line. Step 6 adds a paperclip button, with drag-and-drop on the chat as a second way. Both stay hidden while the capability flag is off and on the demo.
- **File texts:**
  - "That file is 14 MB; the limit is 10 MB."
  - "I couldn't read that file: {reason}."
  - "Sending files is off on the online demo. It works on your own install."
  - "I got {name}, but I can't read files yet."
  - the **Add to documents** offer
  - the "Saved to memory" chip
  - Telegram and the simulated phone share each text exactly, as plain text with no Markdown.
- **Viewers:** see everything read-only, with no composer.
- **Roles UI:** a Settings › Roles section. Where a user can't answer, the request reads "Only an approver for resends can answer this request." (the fixture sentence for one kind), with no **Approve** or **Reject**.

## Cross-Story Dependencies

- **25.3 provides for Epic 26:**
  - Story 26.2 needs 25.3's file-store call and the mock's `getFile`. `TelegramIn` will check the size, download, store the file and send the Item, and 26.2's merge turns on the capability flag.
  - Story 26.3 needs 25.3's photo Items.
- **25.6 depends on 25.3** (the stored file, its `Ref` and the Item) and on read results from Lane A's 19.6 (done), 26.2 and 26.3. Its reply contract is to be fixed by an added criterion on Story 37.1. It uses fixtures until they merge.
- **25.4 and 25.5** depend on Story 37.1's stubs. Story 26.4 needs 25.5's `not_allowed` from `AnswersIn`. Story 25.4 builds on the demo account and the step-2 Settings sections.
