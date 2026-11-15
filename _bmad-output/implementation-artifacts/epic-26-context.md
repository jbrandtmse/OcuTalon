# Epic 26 Context: Approver roles and reading files (step 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Step 6, Lane A side. A PDF or Word file sent from the web chat or Telegram becomes an item OcuTalon answers about as untrusted data. A photo gets a model caption that is saved as a memory. Admins get approver roles (one for every kind of risky action, one per kind) and a viewer role, and the bridge enforces them wherever an answer arrives. Story 37.1 (formerly 26.1, done) already fixed the names and contracts and left stubs. This epic replaces those stubs with working code that Lane B's Stories 25.4 to 25.6 call.

## Stories

- Story 26.2: Files sent from the chat or Telegram become items
- Story 26.3: Caption a photo and keep the caption as a memory
- Story 26.4: Approver roles for all risky actions or one kind, and a viewer role

## Requirements & Constraints

- Text extracted from a sent file reaches the model as quoted, untrusted data, never as the user's own words. The turn is tainted and only read-only tools run in it. An instruction inside a file (for example "approve all pending requests") changes nothing.
- A file that can't be read gets no model request. Its failure reason goes back for the reply.
- Telegram documents and photos: check the size Telegram reports before downloading, store through the file-store call, send the same kind of Item, and never log the download URL (it holds the bot token). Runners without a bot use the CI Telegram mock (its `getFile` and file download exist).
- Photo captions:
  - The first test, on build 154, proves that `%AI.Agent.ChatWithContent` with `%AI.LLM.ContentPart.ImageData` works on the shipped provider path, with no sampling parameters and an output cap of at least 4,000 tokens. If it doesn't work, report it, and photos get the unreadable-file reply until it does.
  - An unusable reply (refusal, empty, cut off, error, timeout or over budget) takes the fallback route, saves no memory and tells the user the fallback reason.
  - The image never appears in a production message body, an agent step or a log. Visual Trace shows the caption request as an agent step with a summary.
  - A CI mock scenario under `ci/mock/scenarios/A/` must accept image content. The end-to-end test asks "what was in the photo" and the answer says it used a memory.
- Roles:
  - Approver and viewer roles are created at both install and upgrade.
  - A refusal changes nothing.
  - An allowed answer's audit entry names the approver's IRIS user, role, session and channel.
  - The security overview lists the new roles and what each may do.
  - Tests in `OcuTalon.Test.Bridge` cover each kind with four users: another kind's role, that kind's role, `OcuTalonApprover`, and a viewer.
- Release checks are the Contest Planner's (demo host and hands-on pass). They never park a story on the owner.

## Technical Decisions

**Read result (`OcuTalon.Agent.Input.ReadFile(item, Output result) As %Status`, now a stub answering 5003 and `{}`).**
- It opens the file through `Core.Files.Open(item.FileRef, item.SessionRef)`. Story 26.2 builds it for PDF and .docx, using Story 19.6's `Docs.Extract`. Story 26.3 builds it for JPEG and PNG.
- The result is built by code and never holds file bytes or extracted text. Fields:
  - `fileRef`
  - `kind`: `document` or `photo`
  - `read`: 1 or 0
  - when `read` is 0: `reason`, one of `Docs.Extract`'s codes (a photo that can't be sent is `failed`), and `text` = `Docs.Extract.Failure(reason)`
  - when a document was read: `chars`, `cut` (1 when `MAXTEXT` cut the text) and `addable` 1
  - when a photo was read: `addable` 0
- Story 26.2 sets the parameter `READSFILES = 1` on `Agent.Input` in the same change. That flips `Core.Files.Readable()` and `/v1/state`'s `filesReadable`. Until then, a file turn gets `Core.Files.NoReaderText`.
- Lane B's `Conversation` (Story 25.6) calls `ReadFile` before sending the turn's requests. When `read` is 0 it ends the turn with `text`. Otherwise it runs the turn as untrusted.
- Extracted text may enter the turn's `Input` the way chat text does (26.2 stays out of the runner). Read the file once in the same job for both `ReadFile` and `Render`, or read it again. `Docs.Extract` can run for up to 45 s in Conversation's job, which matters for pool size.
- Python work never runs inside a callback. It goes to a `%SYSTEM.WorkMgr` worker.

**Photo-caption request.**
- The photo's turn is the caption request: a `turn` request of provenance `untrusted` through `Decide` to `ChatAgent`. There is no new request kind.
- It runs in a throwaway AI session that is never linked to the conversation, with read-only tools at most. Decision, usage and cost are recorded as for any turn.
- New extension class (AD-31):
  - The base is `OcuTalon.Bridge.Ext.Content`. The setting `ContentClass` is on `Decide`, category Extensions, read through `Ext.Accessor.ClassFor` (add the pair to `BASES`). OcuTalon's class is `OcuTalon.Agent.Content`. The bridge alone sends no content.
  - `Part(request, Output mediaType, Output data As %Stream.Object)`:
    - Runs in the runner's job before the model call, never inside a callback. It defaults to no content.
    - OcuTalon goes from the request's `ItemId` and `OwnerRef` to the `SentFile`, then through `Core.Files.Open`.
    - When it answers content, the runner calls `ChatWithContent` with the text part and one `ImageData` part instead of `Chat`. Every runner rule still applies: gate, step audit policy, session lock, usage record, and no `%AI` or Python calls from callbacks.
  - `Accepted(request, text, Output hostData)`:
    - `Decide` calls it in its own job after it accepts a usable `turn` reply.
    - OcuTalon saves the reply text (at most 2,000 characters) as a memory through `SaveMemory` to `MemoryOps`, with the photo's `ItemId`, origin `system` (so recalling it taints a turn) and `Source` `learned`.
    - It answers `{"caption": {memoryRef, text}}`. `Decide` merges that into the Reply's `HostData`. The member is absent when nothing was saved.

**Approver kinds (AD-11).**
- `ApprovalRequest` gains `ApproverKind`, appended to the class (AD-5).
- How `Raise` sets it:
  - From the caller when given: lower-case letters and `_`, at most 32 characters, never checked against a host list.
  - Otherwise `tool` for a `tool_call`, and the `FixKind` for a `fix`.
  - OcuTalon's callers pass the fix kind's `APPROVERKIND` (default its `NAME`): `repair_resend` is `resend`, `reroute` is `reroute`, `suspend_item` and `resume_item` are `suspend`, `rollback_setting` is `rollback`, `partner_warning` is `partner`, `email` is `email`.
- `setting` rows (persona proposals) get no `ApproverKind` and keep `RequiredRole` `OcuTalonUser`. Do it without putting a role literal in the bridge. There is no `OcuTalonApprover_setting`.
- Who may answer a row that has an `ApproverKind` and whose `RequiredRole` names an existing resource: a user for whom `$SYSTEM.Security.CheckUserPermission(user, RequiredRole, "U")` or `CheckUserPermission(user, RequiredRole_"_"_ApproverKind, "U")` is 1. Every other row keeps the recursed role-set rule.
- `Answer` applies the rule under the row's lock and returns `not_allowed` with the kind. The audit `role` is `RequiredRole` when the user passes that check, otherwise the kind's role.
- The take-over: in the same change, the default of `Decide`'s `ApprovalRole` becomes `OcuTalonApprover`. A value set on the item stays. Rows raised before the upgrade keep `OcuTalonUser` until they expire.
- `Approval.MayAnswer(ref, irisUser, Output kind) As %Boolean`:
  - Returns 1 when the user may answer. Otherwise 0, with `kind` = the row's `ApproverKind`, or empty when no row has that Ref.
  - It reads without the lock, ignores state and expiry, and writes and fires nothing.

**Roles (AD-24).**
- The installer creates:
  - `OcuTalonApprover`
  - one `OcuTalonApprover_<kind>` for each kind: `resend`, `reroute`, `suspend`, `rollback`, `partner`, `email`, `tool`
  - `OcuTalonViewer`
  - one resource with the same name for each approver role, held (Use) only by that role
- Grants are composed from the areas' `Grants()`, inside AD-24's limits. `%Ens_ProductionConfig:W` stays Story 23.3's exception and is left out on the online demo.
- `OcuTalonViewer` holds only the R grants declared for `OcuTalonUser`; measure what the web apps need. Lane B's post-sign-in check admits it by name.
- Accounts:
  - Add `OcuTalonApprover` to `Install.Step.Users` `DEMOROLES` (online demo account; the owning-session rule still applies).
  - The README account gains `OcuTalonApprover` at upgrade.
  - Pin both grants in tests.
  - The read-only, service, Workflow and SQL-watch users never hold an approver or viewer role.
- `Install.Step.Roles.Assign(userName, role, grant, Output changed)`:
  - Runs in `%SYS` in the caller's job (needs `%Admin_Secure:USE`) and is admin-only.
  - Works from an allowlist of exactly `OcuTalonApprover` and `OcuTalonViewer`.
  - Refuses every other role (per-kind roles, other OcuTalon roles, any `%` role including `%All`) and every installer-managed account. Each refusal is a named error and changes nothing.
  - Writes an IRIS audit entry for each grant and each removal.
  - Refuses on the online demo.
  - `changed` is 0 when nothing changed.
- `Roles.Holders(Output users)` lists `{user, roles}`, sorted, with the same admin-only and online-demo guards.
- An IRIS user name other than the acting user's is never in a traced message.

## UX & Interaction Patterns

- The reply to a photo carries the caption and the memory reference, so the page shows a "Saved to memory" chip.
- When Telegram returns `not_allowed`, `TelegramIn` shows the catalog sentence for the kind (fixture: "Only an approver for resends can answer this request.") as an alert that stays until dismissed. Nothing is answered.

## Cross-Story Dependencies

- Epic 37 is done: names, the spine and stubs are in place.
- Epic 19 is done: `Docs.Extract`, the save-memory command and memory.
- Story 25.3 is on this branch: `Core.Files`, the `Item` file fields and the mock's `getFile`. Stories 25.4 to 25.6 are still backlog.
- Story 26.4's Telegram `not_allowed` test needs Story 25.5 merged.
- Story 26.4 also needs Epics 14 (security overview) and 23 (step 5's approval kinds) merged. Epic 23 is still in progress.
- Stories 26.2 and 26.3 both build `ReadFile`: 26.2 for documents (and `READSFILES`), 26.3 for photos.
