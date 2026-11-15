# Epic 25 Context: Usage, history and files in the page (step 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 25 is Lane B's half of step 6. It adds the History page, sending a file from the web app or Telegram, and assigning and enforcing approver and viewer roles. Every story except 25.6 is done. Story 25.6 closes the file feature: OcuTalon's reply to a sent file says whether the file could be read and offers the next step. A read document can be added to the documents, and a photo's caption is remembered. Story 25.6 also turns file reading on (`Agent.Input` `READSFILES` from 0 to 1), on the web and in Telegram at the same time. Until it does, every file turn gets the fixed no-reader reply and reaches no model.

## Stories

- Story 25.2: Filter past decisions and incidents on the History page (done)
- Story 25.3: Send a PDF, Word file or photo from the web app or Telegram (done)
- Story 25.4: Assign approver and viewer roles in Settings (done)
- Story 25.5: Answer only with the right approver role, and say why otherwise (done)
- Story 25.6: Reply to a sent file: Add to documents, Saved to memory and the read failure (next)
- Story 25.7: Epic 25 burn-down: a cancelled CI job's stack no longer blocks its runner's web port (done)

## Requirements & Constraints

- **Read failure.** The reply reads "I couldn't read that file: {reason}." with a plain reason, and no model request is made.
- **Read document.** The reply offers **Add to documents**, which adds the file through the documents route using the stored file's `Ref`. A Telegram file that was read can be added the same way, and a Telegram failure uses the same failure text.
- **Photo.** The reply shows a "Saved to memory" chip.
- **The flip.** Set `READSFILES` to 1, together with the chip and the three approved texts below, all in this story's commit. Web and Telegram must never differ. Once it is 1, `/v1/state` `filesReadable` turns true and the paperclip and the chat drop appear on a local install. The online demo stays OFF: no paperclip, the off text on a drop, 409 `not_available` from the route, and Telegram never runs there.
- **Approved texts, verbatim:**
  1. In `docs/security-overview.md`, the model-requests bullet: "A chat turn with a PDF or Word file carries the text OcuTalon read from it, quoted as data. A chat turn with a photo also carries that photo."
  2. In `docs/security-overview.md`, after the trace-content bullet: "The trace also holds the text OcuTalon read from a file sent in the chat or Telegram, and a photo's caption, like a chat reply; a file's bytes and a photo itself are never in it."
  3. In `GUIDE.md` "New since 1.0.0", under "Your documents and memory": "- **Send a file in the chat.** On your own install, press the paperclip beside the message box, or drop a file on the chat, to send a PDF, a Word (.docx) file, or a JPEG or PNG photo of up to 10 MB; in Telegram, send it to your paired chat. OcuTalon reads it, and a photo's caption is saved to memory. Sending files is off on the online demo."
  - Adding "offers to add it to your documents" to text 3 needs the Planner's approval first. That approval takes precedence over the story's own "New since" clause rule.
  - The doc self-tests (`test-readme.sh`, `test-heartbeat-overview.sh`) come along with the texts. Texts 1 and 2 also close DW-1312.
- **Content hygiene.** Across the whole flow, no file bytes, no base64 of them and no image appear in a production message body, an agent step or a log. About the file itself, only its ref, name, type and size may appear. Extracted text may appear only in the turn's `Input`, as a chat turn's own text does. It is never stored and never logged.
- **DW-1313.** When a memory card pin returns 409 `pin_photo`, show "This memory came from a photo, so it can't be pinned." in place of the over-cap notice, in a lazy chunk.
- **DW-1342.** Add production tests: a readable-PDF Telegram turn and a photo Telegram turn (`TelegramChat` with the reader on), and a readable web file turn.
- **Tests from 26.2.** The `[[mock:file-read]]` real-HTTP readable-PDF e2e test moved to this story. Flip the gap assertions in `web/e2e/api/files.spec.ts`.
- **Tests.** Automated tests plus a Playwright spec under `web/e2e/` cover each type, read and failed: the replies match, Add to documents adds the file, and no file content appears in a message body.

## Technical Decisions

- **The read result.** It is Lane A's `Agent.Input.ReadFile(item, .result)`. For a turn with a `SentFile`, `Conversation` calls it once `Core.Files.Readable()` is 1, before the turn's requests are sent. The result is built by code and holds no bytes and no text. Its fields:
  - every result: `fileRef`, `kind` (`document` or `photo`) and `read`;
  - `read` 0: `reason` (a `Docs.Extract` code; a photo the model can't be sent is `failed`) and `text` (`Docs.Extract.Failure`). A `read` 0 result ends the turn with `text` and makes no model request, the same way the no-reader reply does;
  - `read` 1, a document: `chars`, `cut` and `addable` 1;
  - `read` 1, a photo: `addable` 0.
  - Otherwise the turn runs as an untrusted turn, and the result rides on its reply.
  - The status is OK in every case. An Item with no `FileRef` answers 5003 and `{}`.
  - DW-1270 allowed re-reading instead of caching, so there is no cache. Every `Render` and `ReadFile` call re-extracts, and `Docs.Extract` can run for up to 45 s in a worker.
- **Unreadable path.** `Render` answers `""` for a document it can't read, so `Decide` refuses the empty input. Reword AD-21's sentence "while `READSFILES` is 0, a file turn ... gets the fixed no-reader reply" for the value 1. Also update the ownership row for the `READSFILES` probe and `Test.Core.Files.TestNoReaderYet`.
- **Add to documents.** It goes through the documents route with the `fileRef`. The route opens the stored file for the session through `Core.Files.Open` and extracts it again through `DocumentOps`; the extracted text is never stored. Only the owning session can read a file (AD-4), and no route serves a file's bytes back.
- **Photo caption (AD-31).** `ContentClass` on `Decide` is `OcuTalon.Agent.Content`:
  - `Part` sends the image only for a `turn` request of provenance `untrusted`, inside the runner's job (`ChatWithContent` with one `ImageData`).
  - `Accepted` saves the caption, at most 2,000 characters, as a memory with origin `photo` and Source `learned`. That memory can't be pinned and taints a later turn when recalled.
  - `Accepted` returns HostData `caption` `{memoryRef, text}`, which is absent when nothing was saved.
  - `Conversation` carries `caption` the way it carries `learned`: onto `Data.Turn`, `chat.message` and `/v1/state`, and the page shows the chip.
- **Untrusted turns (AD-10, AD-14).**
  - A file turn has provenance `untrusted` from end to end, even with empty text.
  - It runs in a throwaway AI session that is never saved or linked, and only safe read-only tools run in it. `send_email` is refused as UNTRUSTED.
  - An offer never becomes an approval request (AD-11): outside content can't raise one.
  - Quarantine: a tainted reply makes the session's next turn fresh, with a recap written by code.
- **Carriers (Conventions row).** File read results follow the citations and `learned` precedent: built by code, never from model text, and absent when empty. Story 25.6 names the Lane B carriers in its own spine rows (`Turn`, `Outbound`, `chat.message`, `/v1/state`).
- **Standing DW-1282 rule.**
  - The initial web bundle keeps its 1 MB cap, which is never raised. The 500 kB warning stays a warning.
  - New web code goes into lazy chunks: the Add to documents control (`files-view.ts`), the chip and the DW-1313 text.
  - A change that would push the initial bundle past the cap goes to the Planner.
  - Story 36.5 moved Settings, History and Usage into lazy chunks.

## UX & Interaction Patterns

- "Add to documents" is a labelled native button that works by keyboard. "Saved to memory" is a chip on the photo's reply.
- **More to try.**
  - Every item belongs to a group and appears only when the instance has its feature.
  - An item that needs your own install shows only off the online demo.
  - A control does exactly what the control it names does, and nothing else.
  - A new item, and its "Try it:" clause in GUIDE, is public text that needs the Planner's ruling. None is approved for this story, so approved text 3 has no "Try it" clause.

## Cross-Story Dependencies

- **Done.** Stories 25.3, 26.2, 26.3 and 37.1 are merged:
  - 25.3: `SentFile`, `Core.Files`, `POST /api/v1/files`, the no-reader reply and the `filesReadable` probe.
  - 26.2: `ReadFile` and `Render` for PDF and Word, `READSFILES` = 0 and the gated Telegram path.
  - 26.3: photo captions through `ContentClass`.
  - 37.1: the contracts.
- **Telegram risks.** Flipping the flag makes two deferred Telegram risks from 26.2 reachable. Fix them, or note them as known:
  - A paired chat's file is fetched and stored before the allowance is checked.
  - `Api.Download` bounds each read but not the total time.
- **DW-1321.** A photo turn's decide request carries `PHOTOASK` but no image. The fix needs `Conversation` and `Intake` to pass context, and those belong to Lane B.
- **After merge.** The Contest Planner's step 6 hands-on pass exercises a file and a photo from both channels.
