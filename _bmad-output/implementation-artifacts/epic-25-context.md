# Epic 25 Context: Usage, history and files in the page (step 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Lane B's half of step 6: a user filters past decisions and incidents, and sends a PDF, Word file or photo from the web app or Telegram (both done). The remaining stories finish the epic. Admins assign approver and viewer roles in Settings. Approval answers are checked against the request's approver kind, and a user who can't answer is told why. A sent file gets a reply that reports the read failure, offers **Add to documents**, or shows "Saved to memory" for a photo. Lane A's Epic 26 builds the other side of each contract. Story 37.1 fixed those contracts as stubs, so this epic builds against the stubs and fixtures and never waits for Epic 26.

## Stories

- Story 25.2: Filter past decisions and incidents on the History page (done)
- Story 25.3: Send a PDF, Word file or photo from the web app or Telegram (done)
- Story 25.4: Assign approver and viewer roles in Settings
- Story 25.5: Answer only with the right approver role, and say why otherwise
- Story 25.6: Reply to a sent file: Add to documents, Saved to memory and the read failure

## Requirements & Constraints

- An admin grants or removes the approver role for all risky actions (`OcuTalonApprover`) and the viewer role (`OcuTalonViewer`). Per-kind roles (`OcuTalonApprover_<kind>`) are shown but are granted in IRIS, not through OcuTalon. Each change confirms with the step-2 settings text and is audited as a settings change. Non-admins get 403 on the Roles routes.
- A viewer signs in and sees the page, History and Usage read-only: no composer and no Approve, Reject, Dismiss or Break the feed. Every state-changing route refuses a viewer with 403 and changes nothing.
- A user without the right approver role still sees the request. Approve and Reject are absent, and the status reads "Only an approver for {kind} can answer this request." This is recomputed when roles change. A Telegram press gets `not_allowed` with the kind.
- An allowed answer still shows "Approved from {channel} at {time}" on every copy within 5 seconds.
- Online demo: the demo account holds `OcuTalonApprover` (beside `OcuTalonUser` and `OcuTalonTraceViewer`), so its buttons stay. The owning-session rule still applies, and both checks run. No Roles section shows there. The Roles routes answer 409 `not_available` before reading the body, with a test per refusal.
- File replies: a failure reads "I couldn't read that file: {reason}." A read document offers **Add to documents**. A photo shows a "Saved to memory" chip. The same failure text and Add to documents apply to Telegram files. No file bytes, image or extracted text ever appear in a production message body.
- The guide's "New since 1.0.0" gains its file line only with the clauses whose stories have merged.
- Tests: the setup creates `OcuTalonApprover`, the seven per-kind roles and `OcuTalonViewer` as fixture roles. `MayAnswer` is answered by a test double, and read results come from fixtures. Each story has a Playwright spec under `web/e2e/` where it touches the page. Keyboard access and labelled controls are required. The REL-2 demo path must stay green.

## Technical Decisions

**Approver kinds.**
- The kinds are `resend`, `reroute`, `suspend`, `rollback`, `partner`, `email` and `tool`, and later each fix kind's `APPROVERKIND`.
- `setting` rows (persona proposals) have no kind and keep today's rule. Their `RequiredRole` stays `OcuTalonUser`, and there is no `OcuTalonApprover_setting`.
- A kind's role is `<RequiredRole>_<ApproverKind>`. A user may answer a row when they hold Use on `RequiredRole`, or on the kind's role.

**`OcuTalon.Bridge.Approval.MayAnswer(ref, irisUser, Output kind) As %Boolean`** (Lane A; until Story 26.4 a stub that applies the role-set rule with `kind` empty).
- `AnswersIn` calls it before `Approval.Answer` (Story 25.5), and the page's approval state calls it too.
- It reads without the lock, ignores state and expiry, and writes nothing.
- It answers 0 with `kind` set to the row's `ApproverKind`, or empty for an unknown Ref.
- On 0, `AnswersIn` answers nothing and returns `not_allowed`, whose slot `kind` carries the `ApproverKind`.
- `AnswersIn` passes the answering IRIS user and session to `Answer`, which re-checks under the row's lock. Lane A's audit then names the approver role.
- The catalog gains one public-text "Only an approver for ..." sentence per approver kind (seven). `setting` rows keep today's rule.

**`OcuTalon.Install.Step.Roles.Assign(userName, role, grant, Output changed) As %Status` and `.Holders(Output users As %DynamicArray)`** (Lane A; until Story 26.4 they are stubs that answer 5003, and `Holders` answers `[]`).
- Both are admin-only. They run in `%SYS` in the caller's job, which needs `%Admin_Secure:USE`, so `SettingsOps`' production job calls them.
- `Assign` takes an allowlist of exactly `OcuTalonApprover` and `OcuTalonViewer`. It refuses every other role and every installer-managed account, and it refuses on the online demo too. `changed` is 0 when the user was already in that state.
- `Holders` returns `{user, roles}` sorted.
- Lane B builds the Roles section, its routes and the `SettingsOps` handling.

**Personal data in the Roles flow.** An IRIS user name other than the acting user's never enters a traced message.
- The route hands the target user name and the role to `SettingsOps` through `OcuTalon.Core.SecretHandoff`, so `SaveSettings.Changes` holds only `{"handoff": uri}`.
- The `Holders` list returns as a handoff uri in the `CommandResult`.
- The names reach only IRIS audit entries: the role change's own entry and the `Settings` entry. OcuTalon's own Action audit holds no identities.
- A route test scans the change's message bodies for the user name (a leak scan, as for the on-call keys).

**Viewer sign-in.** The post-sign-in check admits `OcuTalonViewer` by name, as well as `OcuTalonUser`. The web applications grant a viewer read access. `OcuTalonViewer` holds only the R grants declared for `OcuTalonUser`. Lane A creates the roles and the per-role resources in Story 26.4.

**File read result.** `OcuTalon.Agent.Input.ReadFile(item, Output result As %DynamicObject) As %Status` is Lane A's. Until Stories 26.2 and 26.3 it is a stub that answers 5003 with `{}`.
- `Conversation` calls it for a turn with a `SentFile`, once `Core.Files.Readable()` is 1 and before the turn's requests are sent.
- `read` 0 ends the turn with `result.text` and makes no model request. Otherwise the turn runs untrusted (read-only tools), and the result rides on its reply.
- The fields:
  - `fileRef`;
  - `kind` (`document` or `photo`);
  - `read`;
  - when `read` is 0: `reason` and `text`, which is "I couldn't read that file: <reason>.";
  - when a document is read: `chars`, `cut` and `addable` 1;
  - when a photo is read: `addable` 0.
- Add to documents goes through the documents route with the `fileRef`. That route opens the stored file through `Core.Files.Open` and extracts it again through `DocumentOps`. The extracted text is never stored.
- **Photo caption.** Lane A's `ContentClass.Accepted` saves the caption memory. The Reply's HostData then carries `caption: {memoryRef, text}`, which is absent when nothing was saved. `Conversation` carries it as it carries `learned`, and the page shows "Saved to memory".
- **Carriers.** The read result and `caption` follow the `citations`, `memories` and `learned` precedent: built by code, never model text, absent when empty, with no bytes and no extracted text. Story 25.6 names the Lane B carriers (`Turn`, `Outbound`, `chat.message`, `/v1/state`) in its own spine rows.

**Spine rows (same-change rule).** Each story adds its own step-6 spine rows (REST, ownership, conventions) in the same change. Lane B's halves (the Roles section, `AnswersIn`'s check and the file replies) get their rows from Stories 25.4, 25.5 and 25.6. Lane B stays in its own files. `MayAnswer`, `Roles.Assign`/`Holders`, `ReadFile` and `ContentClass` are Lane A's, so call them and never edit them.

## UX & Interaction Patterns

- The Settings › Roles section lists users holding an OcuTalon role, with grant and remove controls. It is admin-only and hidden from the demo account.
- Can't answer: the buttons are absent and the status sentence names the kind. The phone and Telegram get the same sentence (in Telegram, Lane A shows it as an alert).
- File replies: the failure text, an **Add to documents** offer on a read document, and a "Saved to memory" chip on a photo.

## Cross-Story Dependencies

- 25.4 needs Epics 16 and 18 (merged: the demo account and the Settings section). It calls Lane A's `Roles.Assign` and `Holders`, which are stubs until Story 26.4.
- 25.5 calls the `MayAnswer` stub until Story 26.4. Story 26.4 depends on 25.5's `not_allowed` result and uses it for `TelegramIn`'s alert.
- 25.6 uses fixture read results until Stories 26.2 (documents) and 26.3 (photo caption) merge. Its Telegram reply depends on 26.2 reading the Telegram Item. The guide's photo clause waits for 26.3.
- Epic 26 depends on Epic 25 merging (26.2 needs 25.3's file-store call and the mock's `getFile`).
- Story 26.4 later changes `Decide`'s `ApprovalRole` default to `OcuTalonApprover`, grants the demo and README accounts `OcuTalonApprover`, and creates the real roles. Until then the fixture roles stand in.
