# Epic 37 Context: Step 6's contracts: approver roles named, and the Usage page (step 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 37 is step 6's contract epic. It holds the step's first Lane A story and first Lane B story so that the feature epics, 25 (Lane B) and 26 (Lane A), can build in parallel against fixed names. Story 37.2, the Usage page, is done and merged. The remaining story, 37.1, is Lane A's contract-naming story. It fixes step 6's names in the spine and puts them in code as stubs: the approver and viewer roles and the resources they hold, the role-check and role-assignment methods, the photo-caption request, and the read-result reply contract that Story 25.6 uses. Once these names exist, Stories 25.4, 25.5, 25.6, 26.2, 26.3 and 26.4 can build and test without waiting for each other.

## Stories

- Story 37.1: Fix step 6's contracts: approver roles and the photo caption
- Story 37.2: See tokens and cost over time on the Usage page (done)

## Requirements & Constraints

- **Roles (step 6):**
  - An admin assigns approver roles, either for all risky actions or for one kind, and a viewer role.
  - A user without the right approver role still sees the request but cannot answer it, and is told why.
  - The audit entry for an approval records the approver's role.
  - The online demo account also holds the approver role. On the demo, only the session that owns a request can answer it, so both checks apply.
- **Approval kinds the roles cover:** at least resend, reroute, suspend and resume, roll back, partner warnings and tool calls. These come from step 5.
- **Files and photos (step 6):**
  - A file sent from the chat or Telegram becomes an item and can be added as a document.
  - A photo gets a model caption, which is kept as a memory.
  - When reading fails, the user is told why.
  - Files over 10 MB are refused.
- **The read-result reply contract (DW-1231):** Story 37.1 must fix the shape of the result that Story 25.6 turns into the reply. It has four parts:
  - the extracted-text summary reference;
  - the **Add to documents** offer;
  - the photo's memory caption: the caption plus the memory's reference, which drives the "Saved to memory" chip;
  - the read-failure reason, which reaches the user as "I couldn't read that file: {reason}."

  Story 25.6 uses fixtures until 37.1, 26.2 and 26.3 merge, so the names must be final. The contract must also work for Telegram, where **Add to documents** goes through the documents route using the stored file's `Ref`.
- **No PDF or Word extraction work here.** It moved to step 3 and is built (Stories 19.6, 19.7, 34.1 and 34.2).
- **Release:** the story ships in the first daily release after the epic merges.

## Technical Decisions

- **The story's shape:** fix the names in the spine and add stubs in code, in the same change. Follow the pattern of Story 33.1.
  - Cross-lane APIs are signatures with stub bodies. Callers test against the stubs with fixtures until Story 26.4 builds them.
  - `OcuTalon.Test.Contract.Ac`'s signature oracle pins the cross-lane signatures, and the owning lane keeps it green.
  - An unbuilt production item answers "not implemented" and carries `Parameter STUB = 1`.
  - Mark spine changes `[ADDED <date>, Story 37.1]` or `[AMENDED …]`, keeping the old text.
- **The stubs Story 37.1 must create:**
  - `Approval.MayAnswer(Ref, IrisUser)`, which Story 26.4 builds. It answers whether the user may answer the request, or else the kind of role they would need.
  - A role-assignment method in the installer's role area. It grants or removes only the approver and viewer roles, and Story 26.4 makes it refuse every other role, `OcuTalonAdmin` and `%All` included.
  - Lane B calls both: `AnswersIn` (Story 25.5) and `SettingsOps` for the Roles section (Story 25.4).
- **How approvals work now:**
  - `OcuTalon.Bridge.Approval.Raise` creates the `ApprovalRequest` row, and the row is the truth.
  - Only the API changes its state (`Answer`, `Expire`, `Cancel`, `StartExecution`, `FinishExecution`), each under `LOCK ^OcuTalon.Bridge.Approval(Ref)`.
  - `Answer` already checks the row's `RequiredRole` against the user's recursed role set and returns `not_allowed`.
  - Every channel answers through `AnswersIn`, one handler that applies the owning-session rule and then calls `AnswerOps` → `Approval.Answer`.
  - `AnswersIn`'s Telegram result codes already include `not_allowed` (the approver-role refusal) with the request's kind as its slot.
  - Step 6 adds the role check in that one handler.
  - Story 26.4 makes `Raise` record which roles may answer: `OcuTalonApprover` or the kind's role.
- **The approval-role setting:**
  - It is `Decide`'s host setting `ApprovalRole`, in category Bridge, read through `Ext.Accessor.ValueFor`. It is seeded with `OcuTalonUser` until step 6, and an empty value refuses `Raise`.
  - The spine must state how the approver roles take over from it. Story 26.4's upgrade then moves the setting.
  - A `setting` request (a proposed persona) also uses this setting as its required role.
  - `ApprovalKind` is `fix, tool_call, setting`, while the per-kind roles are finer (resend, reroute, and so on). The spine update must say how a row maps to `OcuTalonApprover_<kind>`.
- **The bridge stays separable:**
  - No `OcuTalon.Bridge` class may reference another `OcuTalon` package, and a CI check enforces this.
  - The bridge reaches its host only through the extension classes named in `Decide`'s settings, so a standalone bridge still works with whatever role its developer sets.
  - OcuTalon's role names therefore reach the bridge through settings or extension classes. They are never hard-coded in bridge code.
- **Roles and their limits:**
  - Step 6 roles: `OcuTalonApprover` (every kind), one `OcuTalonApprover_<kind>` per approval kind, and `OcuTalonViewer`.
  - The installer composes their grants from each area's `Grants()`.
  - No OcuTalon role may hold `%All`, `%Development`, `%Ens_MessageEditResend`, `%Ens_MessageDiscard`, `%Ens_ProductionRun`, `%Ens_ProductionConfig` or the Workflow inbox.
  - No person is a Workflow user: `OcuTalonApprovals` has exactly one member, `OcuTalonWorkflow`.
  - Story 26.4 checks roles with `$SYSTEM.Security.CheckUserPermission` on a resource each approver role holds. The spine must name those resources.
  - `OcuTalonViewer` must hold what the post-sign-in check needs to admit a viewer who has no `OcuTalonUser`.
  - The security overview lists the new roles.
- **The AD-24 amendment:** from step 6 the online demo account holds `OcuTalonApprover` beside `OcuTalonUser` and `OcuTalonTraceViewer`. It is never an admin, and the owning-session rule still applies. The README account gains `OcuTalonApprover` on upgrade.
- **Settings and audit:**
  - At run time, `SettingsOps` is the only writer of settings, and installer steps write only seeds. The Roles section therefore changes roles through `SettingsOps`, which calls Lane A's role-assignment method. Each change is audited as a settings change.
  - From step 6, audit entries name the acting user's role, along with the user, the `SessionRef` and the channel.
- **The photo-caption request (built by 26.3):**
  - It goes through `Decide` in a fresh AI session that is never linked to the conversation, and its usage and cost are recorded.
  - It uses `%AI.Agent`'s `ChatWithContent` with `ImageData`, under the model-use rules: no sampling parameters and an output cap of at least 4,000 tokens.
  - The image never appears in a production message body, an agent step or a log.
  - A usable caption is saved through the save-memory command, with the photo as its source, marked untrusted.
  - An unusable reply takes the fallback route and saves no memory.
  - Any new value in an enumeration (such as `RequestKind`) must go into both `OcuTalon.Msg.Enum` and `OcuTalon.Bridge.Msg.Enum`, which a contract test keeps equal.
- **Files as they stand (Story 25.3, Lane B):**
  - `OcuTalon.Core.Files` provides `Store`, `Open`, `Describe`, `SetItem` and `RefusalText`.
  - An `OcuTalon.Msg.Item` with provenance `untrusted` carries `FileRef`, `FileName`, `FileMediaType` and `FileSize`, never the bytes.
  - `Core.Files.Readable()` is 1 only once `Agent.Input`'s parameter `READSFILES` is 1, which Story 26.2 adds. Until then a file turn gets `Core.Files.NoReaderText` and no model request.
  - `Docs.Extract.Read` answers `{ok:0, reason}` with fixed codes: `too_large`, `contents_too_large`, `wrong_type`, `encrypted`, `damaged`, `no_text`, `legacy_doc`, `timed_out` and `failed`. `Failure(code)` fits each code into the "couldn't read" sentence.
- **Precedent for data attached to a reply:** code-built `HostData` members on the bridge `Reply` (`citations`, `memories`, `learned`). `Conversation` (Lane B) carries them onto the `Turn`, the `Outbound` and `chat.message`. They are built from tool results, never from model text, and absent when empty.
- **Ownership:** 37.1 changes only Lane A files: `OcuTalon.Bridge.*`, Lane A's installer areas and tests (`OcuTalon.Test.Bridge`), and Lane A's catalog class `Catalog.Watch`. A Lane B contract addition (for example on `AnswersIn`, `Core.Files`, the Roles routes or `chat.message`) gets its spine row from the story that builds it. When 37.1 needs a property on a Lane B contract, it asks Lane B for it.

## UX & Interaction Patterns

- **Can't answer:**
  - The Approve and Reject buttons are absent, and the status reads the sentence for the request's kind. Fixture: "Only an approver for resends can answer this request."
  - On the phone and in Telegram, a press gets the same sentence, as an alert that stays until dismissed.
  - Texts are rendered from the catalog. A new text is proposed for approval before it ships.
- **Answered:** "Approved from {channel} at {time}" on every copy within 5 seconds, as before.
- **File replies:**
  - On failure: "I couldn't read that file: {reason}."
  - A file that was read: a reply offering **Add to documents**.
  - A photo: a "Saved to memory" chip.
  - The guide's "New since 1.0.0" file line gains each clause only once its story has merged.
- **Roles and viewers:**
  - Settings gains a Roles section, for admins only.
  - A viewer sees everything read-only, with no composer and no Approve, Reject, Dismiss or Break the feed.

## Cross-Story Dependencies

- **Upstream:** the epic's real edge is Epic 36, for step 5's approval kinds. The sprint file still shows Epic 36 in backlog. Of step 5's kinds, Stories 23.2 (suspend, resume and reroute) and 23.5 (partner notices) are done; Story 23.3 (roll back) is still in backlog.
- **Downstream (wait on 37.1):**
  - Stories 25.4 and 25.5 call the `MayAnswer` and role-assignment stubs, and their tests create fixture roles with the names 37.1 fixes.
  - Story 25.6 uses the read-result reply contract.
  - Stories 26.2, 26.3 and 26.4 build on 37.1's names and replace its stubs.
- **Inside Epic 37:** Story 37.2 no longer depends on 37.1, because each story now adds its own step-6 spine rows.
