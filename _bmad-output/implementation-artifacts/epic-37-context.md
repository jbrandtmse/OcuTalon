# Epic 37 Context: Step 6's contracts: approver roles named, and the Usage page (step 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 37 is step 6's contract epic. It groups the step's first Lane A and first Lane B stories so that the feature epics, 25 (Lane B) and 26 (Lane A), can build in parallel against fixed names. Story 37.2 (the Usage page) is done. The only open story, 37.1, is Lane A's contract story. It writes step 6's names into the spine as additive text and lands the cross-lane APIs in code as compiling signatures with stub or interim bodies. The names cover the approver kinds and roles, the role check and role assignment, the photo-caption request, and the file read result that Story 25.6 renders (DW-1231). Nothing behaves differently until Stories 26.2, 26.3 and 26.4 build them.

## Stories

- Story 37.1: Fix step 6's contracts: approver roles and the photo caption
- Story 37.2: See tokens and cost over time on the Usage page (done)

## Requirements & Constraints

- **Contracts only, no behaviour.** 37.1 creates no role, resource, grant, column, enum value, REST route, production item, user-visible text or new AD id. It does not change `Approval.Answer`/`Raise`/`HoldsRole`, `Decide`'s `ApprovalRole` default, `Bridge.Audit`, `Agent.Input.Render`, `READSFILES`, any fix kind or `Install.Step.Users`. A demo or local install behaves exactly as before.
- **Spine edits are unions.** New bullets and rows only, each marked `[ADDED <date>, Story 37.1]`. Existing sentences stay word for word. The one exception is the Deferred row "Approver kinds and per-kind checks", which is removed with an `[AMENDED ...]` marker. Refresh `updated:`. `lint_spine.py` may report nothing beyond the baseline low `placeholder` findings.
- **Binding Contest Planner rulings (2026-11-13, owner's delegation)** on the spec's spine text:
  - **Seven approver kinds:** `resend`, `reroute`, `suspend`, `rollback`, `partner`, `email`, `tool`, plus one per later fix kind's `APPROVERKIND`. There is no `OcuTalonApprover_setting`.
  - **`setting` rows keep today's rule.** A persona proposal gets no `ApproverKind`, and its `RequiredRole` stays `OcuTalonUser` across the take-over. A user never needs an approver role to accept their own assistant's persona. The owning-session rule still applies.
  - **`Roles.Assign` is admin-only and uses an allowlist of exactly `OcuTalonApprover` and `OcuTalonViewer`** (never a denylist). It refuses every other role: the per-kind roles, `OcuTalonAdmin`, `OcuTalonUser`, `OcuTalonTraceViewer` and every `%` role, `%All` included. It also refuses the installer-managed accounts (the demo and read-only accounts, `OcuTalonService`, `OcuTalonWorkflow`). Each refusal is an error naming what was refused, and nothing changes. Every assignment and removal writes an IRIS audit entry. On the online demo the Roles routes answer 409 `not_available` before the body is read. Story 26.4 adds a test per refusal. Administrators grant per-kind roles in IRIS.
  - **Both `OcuTalonApprover` grants** (the online demo account's and the README account's) are pinned by tests in Story 26.4.
  - **The audit rule is narrowed by exactly this sentence**, added as its own bullet: "The IRIS audit entry of a role change, and of a settings change, may hold the IRIS user names involved, plus the on-call contact values (36.2 V3); OcuTalon's own Action audit holds no identities."
  - **"No file content in a production message body"** (Story 25.6) means no file bytes and no image. Extracted document text may reach a turn's input like chat text. Story 26.2's rendering stays in `Conversation`'s job and does not move into the runner.
  - The obligations these rulings put on Stories 25.4, 25.5, 25.6, 26.2 and 26.4 are ledger entries DW-1267 to DW-1271. The orchestrator adds their epics.md bullets after the merge, not 37.1.
- **Quality bars:** ASCII only, no local machine path. Every new signature is pinned in `OcuTalon.Test.Contract.Ac`, whose floor goes from 89 to 93, with its class-doc count corrected. Mutation checks (Rule 19) prove each pin goes red.

## Technical Decisions

- **APIs 37.1 lands** (Lane A; signatures exactly as the spine names them):
  - `OcuTalon.Bridge.Approval.MayAnswer(ref, irisUser, Output kind) As %Boolean`, placed after `HoldsRole`. Its interim body is today's rule: the row's `RequiredRole` in the user's recursed role set, via `IsRef` + `RefIndexOpen` + `HoldsRole`. `kind` is "". It writes and fires nothing, ignores state and expiry, and answers 0 for an unknown or malformed Ref or an empty user. The body is interim, not 5003, so that Story 25.5 can wire it in before 26.4 without breaking the demo.
  - `OcuTalon.Install.Step.Roles.Assign(userName, role, grant, Output changed) As %Status` and `Roles.Holders(Output users As %DynamicArray) As %Status`. Both are stubs: `$$$ERROR($$$NotImplemented)` (5003), with `changed` 0 and `users` `[]`. When built they run in `%SYS` in `SettingsOps`' job, which needs `%Admin_Secure:USE`. Follow `Install.Step.Mcp.Grant`/`Revoke`.
  - `OcuTalon.Agent.Input.ReadFile(item, Output result As %DynamicObject) As %Status` is a stub: 5003 with `{}`, and it opens no file.
  - Stub pattern as in Story 33.1. Tests go in `OcuTalon.Test.Bridge.Api` (Lane A's cross-lane stub test); there is no new test class.
- **Approver kinds and the role rule (spine, built by 26.4):**
  - `ApprovalRequest` gains an appended `ApproverKind`. It is the caller's value, else `tool` for a `tool_call`, else the fix kind's `APPROVERKIND` (default its `NAME`). The mapping is `repair_resend` to `resend`, `reroute` to `reroute`, `suspend_item`/`resume_item` to `suspend`, `rollback_setting` (Epic 36's AD-16 name) to `rollback`, `partner_warning` to `partner`, and `email` to `email`. A page raises no request.
  - The kind's role is `<RequiredRole>_<ApproverKind>`, so the bridge derives every name from its one approval-role setting and hard-codes none. A standalone bridge keeps working, and an unknown kind fails safe.
  - Each approver role holds Use on a resource with its own name. A row with an `ApproverKind` whose `RequiredRole` names an existing resource is answerable when `CheckUserPermission(user, RequiredRole, "U")` or the kind role's check succeeds. Every other row keeps the recursed-role-set rule, which covers pre-upgrade rows and standalone bridges.
  - **Take-over:** Story 26.4 changes `Decide`'s `ApprovalRole` default from `OcuTalonUser` to `OcuTalonApprover` in the change that creates the roles. An explicitly set value stays. Earlier rows keep `OcuTalonUser` until they expire (24 h).
  - `not_allowed`'s slot `kind` carries the `ApproverKind`. The approval audit entry gains `role`: the approver role that allowed the answer.
- **Roles:** `OcuTalonApprover` (every kind), `OcuTalonApprover_<kind>` and `OcuTalonViewer`. `OcuTalonViewer` holds the R grants the areas declare for `OcuTalonUser` and no W or U grant, and the post-sign-in check admits it by name. The demo account gains `OcuTalonApprover` (`DEMOROLES`, owning-session rule kept, never admin), and the README account gains it at the step 6 upgrade. The read-only, service, Workflow and SQL-watch users never hold an approver or viewer role. The forbidden-privilege list is unchanged. Its one step-5 exception, `%Ens_ProductionConfig:W` for `rollback_setting`, is Story 23.3's grant and is left out of the demo install; the step 6 text must not contradict it.
- **Personal data:** no IRIS user name other than the actor's goes into a traced message. The Roles section hands the user name and role to `SettingsOps` through `Core.SecretHandoff`, so `Changes` holds only `{handoff}`, and `Holders`' list returns through a handoff uri. This follows the on-call keys' rule: values reach only the IRIS audit log, and a leak-scan test pins it.
- **Read result (DW-1231):** built by code, never from model text, with no bytes and no extracted text. The fields are:
  - `fileRef`: the `SentFile` `Ref`.
  - `kind`: `document` or `photo`.
  - `read`: 1 or 0.
  - When `read` is 0: `reason` (a `Docs.Extract` code; a photo that can't be sent is `failed`) and `text` (`Docs.Extract.Failure`).
  - For a document that was read: `chars`, `cut` and `addable` 1.
  - For a photo: `addable` 0.

  `Conversation` (Story 25.6) calls `ReadFile` once `Core.Files.Readable()` is 1. When `read` is 0 the turn ends with `text` and makes no model request. Add to documents re-extracts from the stored file by `fileRef` through `DocumentOps`.
- **Photo caption:**
  - It is a plain `turn` request of provenance `untrusted`, with no new request kind and no `Msg.Enum` edit. It runs in a throwaway, never-linked AI session with read-only tools at most, and usage and cost are recorded as usual.
  - The image reaches the model only in the runner's job, through the new extension `ContentClass`: base `OcuTalon.Bridge.Ext.Content`, a setting on `Decide` read through `Ext.Accessor.ClassFor`, `Part` for one `ImageData` via `ChatWithContent`, and `Accepted`. OcuTalon's class for it is `OcuTalon.Agent.Content`.
  - After a usable reply, `Accepted` saves the caption (at most 2,000 characters) as a memory: origin `system`, `Source` `learned`, and the photo Item's `ItemId`. It returns HostData `caption` `{memoryRef, text}`, following the `citations`/`memories`/`learned` precedent. An unusable reply saves nothing.
- **Spine anchors (S1 to S9):**
  - AD-11: a new bullet after the approval-role setting bullet.
  - AD-24: a new bullet after the online demo account bullet.
  - AD-17: a new bullet after the "Production jobs run as..." bullet, plus the ruling sentence.
  - AD-21: a new final Rule bullet.
  - AD-31: a `ContentClass` sub-bullet before "The bridge reads the three settings".
  - AD-6: a clause allowing a runner's `ChatWithContent`.
  - Conventions: a "File read results" row after "Citations and memories on the page".
  - Ownership: four rows after Story 25.3's rows.
  - AD-29: an "Epic 37's names" bullet after the now-merged "Epic 36's names" bullet.
  - Deferred: the row removal described above.
- **Bridge separability:** no `OcuTalon.Bridge` class names another OcuTalon package or a new role literal. `test-class-rules.sh` (bridge-refs) enforces this.

## UX & Interaction Patterns

- 37.1 adds no text. The texts the contracts point at already exist:
  - "I couldn't read that file: {reason}."
  - **Add to documents**
  - "Saved to memory"
  - the fixture "Only an approver for resends can answer this request."
- The per-kind "Only an approver for ..." sentences for the other six kinds are Story 25.5's to propose as public text.
- Settings > Roles is admin-only and is absent on the online demo (Story 25.4).

## Cross-Story Dependencies

- **Upstream:**
  - Epic 36's contracts (36.1, 36.2) are merged into this branch, so S-text must match their spine wording: `rollback_setting`, the `%Ens_ProductionConfig:W` ruling, the dry-run fields and the on-call audit rule.
  - Story 25.3 (`Core.Files`, `SentFile`, `Readable`) is done.
  - Story 23.3 (rollback) is still in backlog.
  - Epic 22 also edits `Bridge/Approval.cls` (`ToolFingerprint` at storage slot 26). Keep `MayAnswer` away from its methods, and Story 26.4 must append `ApproverKind` after `ToolFingerprint`.
- **Downstream (wait on 37.1):**
  - 25.4 calls `Assign`/`Holders` through the handoff.
  - 25.5 calls `MayAnswer` before `Answer`.
  - 25.6 calls `ReadFile` and renders `caption`.
  - 26.2 builds `ReadFile` for documents and sets `READSFILES`.
  - 26.3 builds `ContentClass`, `Agent.Content`, the photo branch and `caption`.
  - 26.4 builds the real `MayAnswer` rule, `ApproverKind`, the roles, resources and grants, `Assign`/`Holders`, the `ApprovalRole` default and the audit `role`.
- **Inside Epic 37:** none. 37.2 no longer depends on 37.1.
