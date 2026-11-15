# Epic 26 Context: Approver roles and reading files (step 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 6, Lane A side. A PDF or Word file sent from the web chat or Telegram becomes an item OcuTalon answers about, always as untrusted data. A photo gets a model caption that is kept as a memory. That part is done: Story 26.3 is merged. Admins get approver roles (one for every risky kind, one per kind) and a viewer role, and the bridge enforces them wherever an answer arrives. Story 37.1 fixed the names and left stubs. This epic replaces the stubs with working code that Lane B's Epic 25 stories call. Story 26.2 is next.

## Stories

- Story 26.2: Files sent from the chat or Telegram become items
- Story 26.3: Caption a photo and keep the caption as a memory (done)
- Story 26.4: Approver roles for all risky actions or one kind, and a viewer role

## Requirements & Constraints

- **Untrusted files.** Text extracted from a sent file reaches the model as quoted, untrusted data, never as the user's own words. The turn is tainted, so only read-only tools run. An instruction inside a file, such as "approve all pending requests", changes nothing.
- **Unreadable files.** A file that can't be read gets no model request. The failure and its reason go back for the reply.
- **Telegram documents and photos:**
  - `TelegramIn` checks the size Telegram reports before downloading.
  - It stores the file through the file-store call, channel `telegram`, and sends the same kind of untrusted Item the web route sends.
  - It never logs the download URL, which holds the bot token.
  - Runners without a bot use the CI Telegram mock: `getFile` and `/file/bot<token>/<path>`, where the token is logged by length only. A real bot is used only in the Contest Planner's hands-on pass.
  - Telegram never runs on the online demo, and sending files is off there.
- **Limits and refusal text.** The limit is 10 MB. Refusals happen before storing, using the file store's codes and text. Release checks belong to the Contest Planner and never park a story on the owner.
- **Owed by 26.2, because `READSFILES` makes photos visible:**
  - DW-1312: the security overview adds "A chat turn with a photo also carries that photo." to the model-request bullet, and says photos never appear in the trace while captions do, like chat replies.
  - DW-1313: on a 409 `pin_photo`, the memory card shows "This memory came from a photo, so it can't be pinned." instead of the over-cap notice, in a lazy chunk. This may fall to 25.6 if that story owns the card change.
  - DW-1321: a photo turn's decide (triage) request gets Render's caption ask but no image. Give the photo ask only to the turn request, and give the decide request a neutral line.
  - Overflow, also routed here: DW-894 (batch the per-passage embedding in `Docs.Store.Write`) and DW-929 (lift `Test.Docs.Turns`' private helpers into one shared `Test.Docs` fixture).
- **Story 26.4 roles:**
  - The roles are created at install and at upgrade.
  - A refusal changes nothing.
  - An allowed answer's audit entry names the approver's IRIS user, role, session and channel.
  - The security overview lists the new roles and what each may do.
  - Tests in `OcuTalon.Test.Bridge` answer each kind as four users: another kind's role, that kind's role, `OcuTalonApprover`, and a viewer.
  - The role-assignment method refuses `OcuTalonAdmin` and `%All`, with a test for each refusal.

## Technical Decisions

**The read result: `OcuTalon.Agent.Input.ReadFile(item, Output result) As %Status`.**
- It opens the file through `Core.Files.Open(item.FileRef, item.SessionRef)`. Story 26.3 built the photo branch, and the PDF and .docx branch is still the 5003 stub, which 26.2 replaces.
- Code builds the result, never the model. It holds no file bytes and no extracted text. Fields:
  - `fileRef`, `kind` (`document` or `photo`), `read` (1 or 0)
  - read 0: `reason` (a `Docs.Extract` code) and `text` = `Docs.Extract.Failure(reason)`, "I couldn't read that file: <reason>."
  - a document that was read: `chars`, `cut` (1 when `MAXTEXT` cut the text), `addable` 1
  - a photo that was read: `addable` 0
- In the same change, 26.2 sets `Parameter READSFILES = 1` on `Agent.Input`. That turns on `Core.Files.Readable()` and `/v1/state`'s `filesReadable`, which shows the paperclip. From then on, `Conversation` runs a file turn through `Decide` as untrusted instead of answering `NoReaderText`.
- Calling `ReadFile` from `Conversation`, and ending the turn with `text` when `read` is 0, belong to Lane B's Story 25.6. The 26.2 spec must settle how its "no model request for an unreadable file" criterion holds before then.
- Extracted text may enter the turn's `Input` the way chat text does; 26.2 does not move into the runner. Read the file once in the same job for both `ReadFile` and `Render`, or read it twice. Extraction is never stored. Add to documents re-extracts from the `fileRef` through the documents route (25.6).
- `Docs.Extract.Read`:
  - Runs in the one-worker `OcuTalon.Docs.Extractor` WorkMgr category. Python never runs in a caller's process or inside a callback.
  - Takes one read at a time under a lock and never throws.
  - Answers `{ok, text, cut, markers}`, or `{ok:0, reason}` with one of these codes: `too_large`, `contents_too_large`, `wrong_type`, `encrypted`, `damaged`, `no_text`, `legacy_doc`, `timed_out`, `failed`.
  - Limits: `MAXBYTES` 10,485,760, `MAXTEXT` 200,000 characters, cut at a line break.
  - The bytes' signature picks the parser.
  - A wait of up to about 45 s in `Conversation`'s job matters for pool size.

**Telegram.**
- `TelegramIn` is `OcuTalon.Channel.Telegram.In` (Lane A). Its calls use `%Net.HttpRequest`.
- The token comes from the environment and never appears in a setting, a `%Status` text or a log.
- Messages carry `SessionRef`, never a chat id. Chat ids never reach the audit writer, logs or step summaries.
- File store: `Core.Files.Store(sessionRef, channel, name, content, .file, .sc)`, then `SetItem(item, file)`. The Item holds `FileRef`, `FileName`, `FileMediaType` and `FileSize`, never the bytes. Refusal text comes from `RefusalText(code, size)`.

**Photos (done in 26.3; keep intact).**
- `OcuTalon.Bridge.Ext.Content` is read through the `ContentClass` setting on `Decide`, and OcuTalon's class is `OcuTalon.Agent.Content`.
- `Part` runs only for an untrusted `turn` request, in a throwaway session. The image goes out with `ChatWithContent` and one `ImageData` part, and never appears in a message body, a step or a log.
- `Accepted` is called once, after the decision row. It saves the caption (at most 2,000 characters) through `SaveMemory` with origin `photo`, and answers `{"caption": {memoryRef, text}}`.
- Origin `photo` is listed in `Commands`' `FEATUREORIGINS`, not in `Msg.Enum`. Recalling the memory taints a turn, and pinning it answers 409 `pin_photo` (FR-73 as amended).

**Approver kinds and roles (26.4).**
- `ApprovalRequest` gains `ApproverKind`, appended to the class.
- How `Raise` sets it:
  - From the caller, when given: lower-case letters and `_`, at most 32 characters.
  - Otherwise `tool` for a tool call, or the fix's `APPROVERKIND`: resend, reroute, suspend (suspend and resume), rollback, partner, email.
  - `setting` rows get no kind and keep `OcuTalonUser`, with no role literal in the bridge.
- The rule: a user may answer if `CheckUserPermission(user, RequiredRole, "U")` is 1, or the same check on `RequiredRole_"_"_ApproverKind`.
  - `Answer` applies it under the row's lock and returns `not_allowed` with the kind.
  - The audit `role` is the role that passed.
  - `Decide`'s `ApprovalRole` default becomes `OcuTalonApprover`. A value set on the item stays.
- `MayAnswer(ref, irisUser, Output kind)` reads without the lock, ignores state, and writes nothing.
- The installer creates:
  - `OcuTalonApprover`
  - `OcuTalonApprover_<kind>` for each of the seven kinds
  - `OcuTalonViewer`, which holds only `OcuTalonUser`'s R grants
  - one same-named resource for each approver role
- Grants are composed from each area's `Grants()`, within AD-24's limits.
- The demo account (`DEMOROLES`) and the README account gain `OcuTalonApprover`.
- `Install.Step.Roles.Assign`:
  - Runs in `%SYS`, admin-only.
  - Allowlist is exactly `OcuTalonApprover` and `OcuTalonViewer`. Every other role and every installer-managed account is refused with a named error.
  - Writes one IRIS audit entry per change.
  - Refused on the online demo.
- `Holders` has the same guards.
- No IRIS user name other than the acting user's appears in a traced message.

## UX & Interaction Patterns

- Over the limit: "That file is 14 MB; the limit is 10 MB." When reading fails: "I couldn't read that file: {reason}."
- A document's reply offers **Add to documents**. A photo's reply shows a "Saved to memory" chip. Lane B renders both in 25.6, and 25.6 also adds the guide line.
- 26.4: when Telegram returns `not_allowed`, `TelegramIn` shows the catalog sentence for the kind (fixture: "Only an approver for resends can answer this request.") as an alert that stays until dismissed.

## Cross-Story Dependencies

- Story 26.2 waits only on Stories 25.3, 25.4 and 25.5, not all of Epic 25; this breaks the cycle with 25.6. All three are merged: the file store with `SentFile` and the mock's `getFile`, the Roles section, and `AnswersIn`'s role check through `Live.Payload.Approval.Answerable`.
- Story 25.6 (backlog) consumes 26.2's read path, `ReadFile` together with `READSFILES`.
- Epics 19, 37 and 14 are done.
- Story 26.4 also needs Epic 23 merged, which is still in progress. Until 26.4 lands, the `kind` in `AnswersIn`'s `not_allowed` is empty, and 25.4's Settings calls the `Assign`/`Holders` stubs.
