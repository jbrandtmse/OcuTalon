---
title: 'Story 25.5: Answer only with the right approver role, and say why otherwise'
type: 'feature'
created: '2026-11-13'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-25-4-assign-approver-and-viewer-roles-in-settings.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-37-1-fix-step-6-s-contracts-approver-roles-and-the-photo-caption.md'
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Step 6 gives each risky action an approver kind, but nothing asks the role check before an answer, and the page and the simulated phone learn that a user can't answer only after a press. Today the 403 text is chosen from the row's `Kind` (`Web/Api.cls:742`): every fix says "resends", and the Telegram `not_allowed` slot carries `fix` (`Core/AnswersIn.cls:113-116`). Story 22.7 (lane D) also leaves a non-admin's email request raised with no one able to approve it (the 22.7 email DW).

**Approach:** `AnswersIn` asks Lane A's `Approval.MayAnswer` for the session's IRIS user after its ownership and answer-shape checks and before the hand-over. A refusal carries the approver kind to every channel. The approval payload tells each recipient session whether it may answer, so the card and the phone drop Approve and Reject and show the kind's sentence from the catalog. The email DW is resolved by refusing a non-admin's email to another address at raise time (Planner Gate question 1).

## Boundaries & Constraints

**Always:**
- The answer rule order in `AnswersIn.OnProcessInput` is: 1 bridge context, 2 SessionRef shape, 3 ownership (`Ownership.Approval`, cancelled), 4 action and channel, 5 (new) the session row exists, else `not_found`, 6 (new) `MayAnswer(row.Ref, session.IrisUser, .kind)`, then the hand-over. A refusal at 5 or 6 sends nothing to `AnswerOps`, and the row stays as it was.
- The IRIS user always comes from the `Data.Session` row of the server-side SessionRef, never from the caller.
- The `not_allowed` refusal is `{"kind": <approver kind or "">}`. When 22.7's email rule refused (below), it is `{"kind": "email", "admin": true}`. `kind` is `MayAnswer`'s output verbatim: empty until Story 26.4. Lane B never derives a kind from `FixKind`.
- Composition with Story 22.7: `MayAnswer` runs first, in `AnswersIn`. `Fix.Kind.Email.MayApprove` stays where 22.7 put it, in `AnswerOps.Carry` before `Approval.Answer`, for an approve only, and its hunk is not changed. `Approval.Answer`'s check under the lock stays last.
- Every refusal sentence is a catalog entry. `RefusalKey(kind, admin)` picks `answered.notAdmin` when `admin` is set. Otherwise it picks `answered.notApprover<Kind>`, whose name is the kind with its first letter in upper case, when the kind is 1 to 32 lower-case letters or `_` and that entry exists. Anything else falls back to `answered.notApprover`. The texts are exactly the Planner Gate's PUBLIC TEXT.
- A `setting` row keeps today's rule (V6). It has no approver kind, so its refusal is the fallback sentence.
- The payload's `answerable` and `approverKind` are computed by the server for the session the payload is for, at every build: the `/v1/state` snapshot, every `approval` event (`BridgeSink`, one per recipient) and the answer reply. They are computed only for a pending row with a session; every other payload has `answerable` true and `approverKind` "".
- The page and the phone follow the payload. A press refused with 403 `not_allowed` turns that request into the can't-answer state at once, with the server's sentence.
- The REL-2 demo path stays green. The README account and the demo account keep their buttons.

**Never:**
- Edit `Approval.MayAnswer`, `Answer`, `Decide`, the roles, resources or grants, or `Install.Step.Users`. Widen `OcuTalonUser`.
- Let any session but the owning one (or a watcher of an instance incident, as today) see or answer a request. This means no change to `Ownership`.
- Add a property to a message class (`AnswerResult`, `Answer`) or any stored column.
- Edit GUIDE.md (P1 is lane D's text) or add a More to try item.
- Add a production setting, a global switch or any product-side seam that can make the role check answer 1.
- Add a new IRIS test class, a live unit or a CI group.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Refused by role (web) | Own pending row; `MayAnswer` 0, kind `resend` (double) | `FromPage` result `not_allowed`, refusal `{"kind":"resend"}`, no send. Route: 403 `not_allowed` "Only an approver for resends can answer this request." | none |
| Refused, interim | Real stub; row `RequiredRole` a fixture role the user lacks | `not_allowed`, `{"kind":""}`; 403 with the fallback sentence | none |
| Unknown kind | kind `zz_new`, `Bad`, or 40 characters | fallback key | none |
| Ownership first | Another session's row, user may answer | 404 `not_found`; Telegram `not_visible`; `MayAnswer` not asked | none |
| Shape first | Own row, action `delete` | `bad_answer`; `MayAnswer` not asked | none |
| No session row | Ref-shaped SessionRef with no `Session` row | `not_found`, no send | none |
| Allowed | `MayAnswer` 1 | Handed over unchanged. `AnswerOps` passes `IrisUser` and `SessionRef` to `Answer`. "Approved from {channel} at {time}" on every copy within 5 s | as today |
| Telegram | Paired chat, refused, kind `reroute` | code `not_allowed`, slots `{"kind":"reroute"}`, row pending | as today |
| Email, non-admin approve (22.7 merged) | Own email row; `MayAnswer` 1; `MayApprove` 0 | `not_allowed`, `{"kind":"email","admin":true}`; 403 "Only an OcuTalon admin can approve this email."; no send. A reject by the same user is answered. | none |
| Email raise, non-admin | Risky `send_email` to another address; requester lacks `OcuTalonAdmin` | No row raised. Refusal "Only an OcuTalon admin can send email to another address, so the email wasn't sent." | as for the other `Raise` refusals |
| Payload | Pending row, recipient may not answer | `answerable:false`, `approverKind:<kind>` | `MayAnswer` error → `answerable:false` |
| Online demo | Demo user holds fixture `OcuTalonApprover`; row `RequiredRole` `OcuTalonApprover` | Own request answered; another session's `not_found` / `not_visible`, row pending | none |

</intent-contract>

## Code Map

Paths are relative to `src/ocutalon/cls/OcuTalon/` unless they start with `src/bridge/`, `web/`, `docker/`, `ci/` or `_bmad-output/`.

**Answer path (Lane B):**
- `Core/AnswersIn.cls`:
  - Class doc :1-18, the rules.
  - `FromPage` :31-41. `FromTelegram` :56-79, with its slot doc at :46-55.
  - `TelegramCode` :86-121. The `not_allowed` branch :113-116 reads `row.Kind`, and it changes.
  - `Deliver` :124-130, the seam overridden by `Test/Core/AnswersTelegramProbe.cls`.
  - `OnProcessInput` :132-152. The session is opened at :147, only for `TraceRef`.
  - `Send` :158 and `Refuse` :164.
- `Core/AnswerOps.cls`. Read it; do not change it.
  - `APPROVALAPI` :17 is the sibling for AnswersIn's new parameter.
  - `Answer(..., session.IrisUser, request.SessionRef, .winner)` :58. AC 5's IRIS user and session are already passed.
  - On `OCT-epic22`, 22.7's `MayApprove` hunk sits before :58 (`git diff origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic22 -- src/ocutalon/cls/OcuTalon/Core/AnswerOps.cls`).
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls:420-431`: `MayAnswer`, the interim stub (`HoldsRole` on `RequiredRole`; `kind` ""). Lane A; call it, never edit it. `HoldsRole` is at :405-418.
- `Web/Api.cls` (contended):
  - `MESSAGENOTAPPROVER` :177, `MESSAGENOTAPPROVERTOOL` :179 and `MESSAGENOTAPPROVERSETTING` :2180.
  - `AnswerApproval` :697-712. 22.7 rewrites its `Set kind` line :706.
  - `AnswerResponse` :735-773, with `not_allowed` at :742.
  - `RailBody` :1423 calls `FromRow(row, sessionRef)` in the web job.
- `Live/Payload/Approval.cls`: properties :6-58 and `FromRow(row, sessionRef)` :69-142. 22.7 adds `EmailPart` (contended).
- `Core/BridgeSink.cls:165`, `:347-349`: `FromRow(row, recipient)` in a production job. Unchanged; it picks up the new fields.
- `Data/Session.cls:34`: `IrisUser`.
- `Msg/Catalog.cls`: `Render` :52 and `Entry(key,.sc)` :80. Entries live in `Msg/Catalog/Core.cls` XData `Entries`; the `answered.*` keys are at :87-140, and `gap`/`source` fields follow the convention.
- `web/src/app/msg/catalog.ts` is generated by `npm --prefix web run catalog`.

**Email (Story 22.7, Lane A; on `origin/OCT-epic22`):**
- `Fix/Kind/Email.cls`: `Raise` (~:218-255; its refusals come before `Approval.Raise`), `MayApprove` (~:261-281), `OwnAddressOnly` (~:105-121) and `EMAILNOSTART` (~:37, the parameter sibling).
- `Tools/EmailTools.cls:64-66`: `HoldSENDEMAIL` returns `Raise`'s refusal.
- `Test/Fix/Email.cls`: `TestOnlyAnAdminApprovesAnEmailToAnotherAddress` ~:1007, with `MakeUser`/`CreateUser` ~:1077-1090 and the throwaway guard `StubReason` ~:112.

**Web (Lane B):**
- `web/src/app/live/payloads.ts:235-255`: `ApprovalPayload`.
- `web/src/app/approvals/approval-view.ts`:
  - `APPROVAL_TEXTS.notApprover`/`notApproverFix` :83-84.
  - `ApprovalView` :155-179, `approvalView()` :393-425.
  - `answerOutcomeOf` :452, with the 403 branch at :466-468.
- `web/src/app/approvals/approval-request-card.ts`: the buttons are under `@if (view().pending)` :174-203, the status at :205-209 and the notice at :237-238 (`answer.notice` :517). Story 25.4 adds its viewer guard at :174-202.
- `web/src/app/approvals/answer-press.ts:107-109`: notAllowed maps to `outcome.message`.
- `web/src/app/phone/phone-view.ts`: the doc rule :14-17 and `requestView` :152-171, with `buttons` at :166.
- `web/src/app/phone/phone-request.ts`: the buttons :95-126, the notice :134-135, the press :233-259.

**Tests (siblings):**
- `Test/Core/ApprovalDouble.cls`: the double of `AnswerOps`' API (`Begin`/`End`, records under `^OcuTalonTest("ApprovalDouble", run)`).
- `Test/Core/AnswersInProbe.cls` overrides `Send`. `Test/Core/AnswersTelegramProbe.cls` overrides `Deliver`.
- `Test/Core/AnswersIn.cls`: `TestResultsPassThrough` :76, `TestBridgeContextRefuses` :184 and `TestRoleRefusalReachesCaller` :286.
- `Test/Core/AnswersTelegram.cls:88-101`: `{"kind":"fix"}`.
- `Test/Core/AnswersTelegramProduction.cls:83-90`: `{"kind":"fix"}`.
- `Test/Core/AnswersInProduction.cls`: :143-174 pins the 403 texts, and :319.
- `Test/Core/AnswersInWebRoles.cls`: the throwaway guard `Reason` :93, `CreateUser` :383, the web-context job `Probe` :293 and `Roles()` :398. Story 25.4 adds `TestDemoApproverOwnSessionOnly`.
- `Test/Data/Fixture.cls:22`: `Session(user)` and `Approval(owner, incident, state, , fields)`.
- `Test/Bridge/ApprovalRows.cls:7`: `ANSWERER` (the README account).
- `Test/Web/Api.cls:397`: the snapshot approval equals `FromRow`.
- Web unit tests:
  - `web/scripts/approval-view.test.mjs` :103-107, :531-534, :743-744;
  - `answer-press.test.mjs:87-91`;
  - `phone-view.test.mjs`, `phone-request-sources.test.mjs`, `approval-sources.test.mjs` and `ux-strings.test.mjs`.
- Playwright:
  - `web/e2e/cards/approval-card.spec.ts:555-572` and `web/e2e/answers/answers.spec.ts:371,432`, the mocked 403 texts;
  - `web/e2e/support/iris.ts:740-800` `seedApproval` (`requiredRole`, `fixKind`, owner), `support/approvals.ts:70` `raise`, and `support/iris.ts` `answerQuietly` and `irisScript`.
- Fixture setup:
  - `docker/tests/test-sign-in.sh`, with 25.4's `live_fixture_role`, the fixture roles and `ZzRoleTarget`;
  - `web/playwright.config.ts:52`: `phone` is in `SIGN_IN_2_DIRS`, and `api/` runs in `live:sign-in`.
- REL-2: `docker/tests/test-demo-path.sh` (README account; `05-approval.spec.ts:26-45` presses Approve on the phone) and `web/e2e-online/demo-path/demo-path.spec.ts:229,258` (demo account).

## Tasks & Acceptance

**Precondition (implement start):**
- Story 22.7 must be on `origin/feature/OCT_OcuTalon_MVP` and integrated forward into `OCT-epic25`, and Story 25.4 must be implemented on this branch. Otherwise HALT `blocked` with `dependency: 22.7 merged and 25.4 implemented` before any edit (Planner Gate question 5).

**Execution:**
- [ ] Task 0 (measure on the lane's fresh throwaway, inside the new `AnswersInWebRoles` methods' first run). In a job logged in as a fixture user with exactly `OcuTalonUser` plus the application roles (the class's `Probe` context):
  - `Approval.MayAnswer(ref, $Username, .kind)` answers 1 for a row whose `RequiredRole` the user holds, and 0 for a fixture role the user lacks, with no error status and no `<PROTECT>`. This measures `GetUserRecursedRoleSet` for one's own name with no `%Admin_Secure` (inference from `irissys/%SYSTEM/Security.cls:315-327` until measured).
  - If it fails, stop with `## Clarification Needed`: the web job could not compute `answerable`. Record the result under Design Notes "Measured".
- [ ] `Live/Payload/Approval.cls`:
  - Add `Property Answerable As %Boolean(%JSONFIELDNAME = "answerable") [ InitialExpression = 1 ]` and `Property ApproverKind As %String(%JSONFIELDNAME = "approverKind", MAXLEN = 32)` after `TraceNamespace`.
  - New `ClassMethod Answerable(ref, sessionRef, Output kind, api As %String = "OcuTalon.Bridge.Approval") As %Boolean`:
    - It reads `Data.Session.RefIndexOpen(sessionRef).IrisUser`. No row or no user gives 0 with kind "".
    - It returns `$ClassMethod(api, "MayAnswer", ref, user, .kind)`. An exception gives 0.
  - New `ClassMethod RefusalKey(kind As %String, admin As %Boolean = 0) As %String`, by the rule in Boundaries, using `Msg.Catalog.Entry` for the existence check.
  - `FromRow(row, sessionRef, api As %String = "OcuTalon.Bridge.Approval")`: for a `pending` row and an `IsRef` sessionRef, set `Answerable` and `ApproverKind` from `Answerable(...)`.
  - -- AC 3; the one Lane B wrapper that `AnswersIn`, `Web.Api` and, from Story 26.4, Lane A's `TelegramIn` read.
- [ ] `Msg/Catalog/Core.cls`: add the nine `answered.*` entries of PUBLIC TEXT items 1-9 (no slots), each with `source` (EXPERIENCE.md:721 for `resend`, Api.cls for the fallback) or `gap` ("Story 25.5 PUBLIC TEXT, Planner gate"). Then regenerate `web/src/app/msg/catalog.ts` with `npm --prefix web run catalog`. -- AC 3.
- [ ] `Core/AnswersIn.cls`:
  - Add `Parameter APPROVALAPI = "OcuTalon.Bridge.Approval";` (sibling: `AnswerOps.APPROVALAPI`) and a transient `Property Refusal As %DynamicObject`.
  - `OnProcessInput` first sets `..Refusal = {}` (a shadow instance is reused between calls). It opens the session before the hand-over. When there is no row, `Refuse("not_found")`. Then call `##class(OcuTalon.Live.Payload.Approval).Answerable(row.Ref, pInput.SessionRef, .kind, ..#APPROVALAPI)`. On 0, set `..Refusal = {"kind": kind}` and `Refuse("not_allowed")`.
  - After `Send`, when the response is `not_allowed`, the row is a `fix` of `FixKind` `email` and the action is `approve`, set `..Refusal = {"kind": "email", "admin": true}`. Otherwise a `not_allowed` refusal stays `{"kind": ""}`.
  - Rule 1's refusal is `{"kind": ""}`.
  - `Deliver(answer, .result, .refusal)` returns the service's `Refusal` (`{}` when none).
  - `FromPage` gains a trailing `Output refusal As %DynamicObject`.
  - `TelegramCode`'s `not_allowed` slots become the refusal object, so `row.Kind` is no longer read. The doc lines change to match.
  - -- AC 1, AC 4, AC 7; DW-1268.
- [ ] `Web/Api.cls` (contended):
  - `AnswerApproval` passes `.refusal` to `FromPage` and on to `AnswerResponse`. 22.7's `Set kind` line goes.
  - `AnswerResponse`'s `not_allowed` answers 403 with `Msg.Catalog.Render(Approval.RefusalKey(refusal.kind, refusal.admin), {}, "web")`.
  - Remove the three `MESSAGENOTAPPROVER*` parameters, whose texts move to the catalog, and update the doc lines.
  - -- AC 1, AC 7.
- [ ] `Fix/Kind/Email.cls` (Lane A, 22.7; footprint extension, Planner Gate question 1):
  - Add `Parameter MESSAGENOTADMIN` (PUBLIC TEXT 10).
  - In `Raise`, after the dry run and before `Approval.Raise`, refuse with it when `'..MayApprove(request, user)`, where `user` is the `IrisUser` of the session of `ownerRef`.
  - Doc lines.
  - -- AC 8; the 22.7 email DW.
- [ ] `web/src/app/live/payloads.ts`: `answerable?: boolean; approverKind?: string` on `ApprovalPayload`.
- [ ] `web/src/app/approvals/approval-view.ts`:
  - `refusalText(kind, render)` mirrors `RefusalKey` without `admin`: `'answered.notApprover' + Kind` when the catalog has it, else `'answered.notApprover'`.
  - `ApprovalView` gains `cannotAnswer: string`, which is "" unless the request is pending and `answerable === false`.
  - `answerOutcomeOf`'s 403 uses the server's message, else the fallback text. `notApproverFix` goes, and `notApprover` becomes the fallback text.
  - Doc lines.
- [ ] `web/src/app/approvals/approval-request-card.ts` and `answer-press.ts`:
  - Approve and Reject render only when `pending && !cannotAnswer && !refused`.
  - In their place, the status line shows `refused || cannotAnswer` with no new layout, using the existing status line's markup.
  - A `notAllowed` press outcome sets `refused` to its message.
  - Story 25.4's viewer guard stays.
- [ ] `web/src/app/phone/phone-view.ts` and `phone-request.ts`:
  - `requestView` gains `cannot: string`.
  - `buttons` also needs `approval?.answerable !== false` and no local refusal.
  - `cannot` is `refusalText(approval.approverKind)` or the local refusal's message, shown where the notice is.
  - Doc rule :14-17 gains the one exception: a store payload with `answerable: false`.
  - -- AC 3.
- [ ] `Test/Core/ApprovalDouble.cls`:
  - Add `MayAnswer(ref, irisUser, Output kind)`.
  - With no run, or no script for the ref, it answers 1 with kind "", so the existing probe tests, whose fixture sessions name no real IRIS user, keep their results.
  - `May(ref, result, kind)` scripts a result.
  - `Kind(ref, kind)` scripts the step-6 rule over real roles: 1 when `GetUserRecursedRoleSet(irisUser)` holds the row's `RequiredRole` or `RequiredRole_kind`, else 0 with the kind.
  - Calls are recorded under `"mayCalls"`.
  - Doc lines.
- [ ] `Test/Core/AnswersInProbe.cls` and `AnswersTelegramProbe.cls`: `Parameter APPROVALAPI = "OcuTalon.Test.Core.ApprovalDouble";`. `Deliver`'s override gains `.refusal`.
- [ ] `Test/Core/AnswersIn.cls`. Add these tests:
  - `TestRoleCheckBeforeHandOver`: scripted 0/`resend` gives `not_allowed`, `Sends` 0, the row is unchanged and the refusal is `{"kind":"resend"}`. A scripted 1 hands over. The `not_found`/`bad_answer` rows and the bridge context never ask (`mayCalls` 0). No session row gives `not_found`.
  - `TestRefusalKey`: the seven kinds, "", `zz_new`, `Bad`, 33 characters, and `admin`; `Render` of each equals PUBLIC TEXT.
  - `TestPayloadAnswerable`: `FromRow(row, s, double)` for pending refused, pending allowed, answered and no session.
  - `TestEmailAdminRefusal`: an own email row (fixture `fix`/`email` with another address), and a fixture session whose user is no admin. `AnswerOpsProbe`'s real `Carry` refuses, so the refusal is `{"kind":"email","admin":true}`. A reject is handed over to `Answer`.
- [ ] `Test/Core/AnswersTelegram.cls:101`, `AnswersTelegramProduction.cls:90`, `AnswersInProduction.cls:143-174`, `Test/Web/Api.cls:397` and `OcuTalon.Test.Msg.Catalog`: update the pins to the new slots, texts, keys and payload members.
- [ ] `Test/Core/AnswersInWebRoles.cls` (THROWAWAY guard). Add `EnsureRole(name)`, which creates a role with no resources only when it is absent and records it for removal. Reuse 25.4's IRIS helper instead if its delivered code has one.
  - `TestMayAnswerInAWebJob`: Task 0, as an assertion.
  - `TestApproverMatrix`: the fixture roles `OcuTalonApprover` and the seven `OcuTalonApprover_<kind>`. Rows have `RequiredRole` `OcuTalonApprover` and `Kind(ref,k)` for each kind. Through `AnswersInProbe` and `FromTelegram` (`AnswersTelegramProbe`):
    - a user holding only `OcuTalonApprover_<k'>` (k' ≠ k) is refused with kind k, and the row stays pending;
    - the holder of `OcuTalonApprover_<k>` is handed over;
    - the holder of `OcuTalonApprover` is handed over;
    - the README account (`ApprovalRows.#ANSWERER`), granted the fixture `OcuTalonApprover` and restored after, is handed over.
  - `TestFixtureRoleOnTheRealPath`: through the real production in the web-context job, on a row with `RequiredRole` `OcuTalonApprover`:
    - `FromPage` as a user without the role gives `not_allowed` `{"kind":""}`, and the row stays pending;
    - as a holder, `done`;
    - with `onlineDemo` forced (restored after), the demo-role holder answers its own request and gets `not_found` for another session's request, which stays pending.
  - -- AC 2, AC 6.
- [ ] `Test/Fix/Email.cls` (Lane A, 22.7; footprint extension): `TestNonAdminEmailIsRefusedAtRaise`, following `TestRiskyTurnApprovedSendsOnce`. A non-admin's risky email to another address gets `MESSAGENOTADMIN` and no `ApprovalRequest` row. An admin's raises one. -- AC 8.
- [ ] `docker/tests/test-sign-in.sh`: after 25.4's fixture roles, add the fixture user `ZzApprover` (`OcuTalonUser,OcuTalonApprover`, random password). Pass `OCUTALON_APPROVER_USER/_PASSWORD` to Playwright and add the password to the `show_log` redaction. -- AC 3 fixture.
- [ ] `web/e2e/phone/approver.spec.ts` (new; `live:sign-in-2`):
  - (a) Real path. `seedApproval` + `raise` a pending fix row for `ZzRoleTarget`'s session with `requiredRole` `OcuTalonApprover`. The card and the phone show no Approve or Reject (none focusable by Tab) and the status "Only an approver can answer this request."
  - (b) `ZzApprover`'s own such row shows both buttons, and Approve gives "Approved from the web chat at {time}" on the card and the phone within 5 s.
  - (c) A row that is answerable at load gets its `RequiredRole` changed by `irisScript`. Approve is then refused, and the card switches to the server's sentence with no buttons. The phone does the same.
  - (d) A mocked `approverKind: 'resend'` (route-fulfilled `/v1/state`, as `approval-card.spec.ts` mocks) shows "Only an approver for resends can answer this request." on the card and the phone.
  - Each case removes its rows. -- AC 3, AC 5.
- [ ] `web/e2e/api/approver.spec.ts` (new; `live:sign-in`, real HTTP):
  - Signed out, `POST /api/v1/approvals/:ref/answer` gives 401.
  - LIVE unprivileged `ZzRoleTarget` on its own row (`RequiredRole` `OcuTalonApprover`) gets 403 `not_allowed` with the fallback sentence, and the row is pending (read back).
  - `GET /api/v1/state` shows that row with `answerable:false`, `approverKind:""`.
  - `ZzApprover` answering `ZzRoleTarget`'s row gets 404 `not_found` (second-session isolation: ownership before role), and the row is pending.
  - `ZzApprover` on its own row gets 200 `done`.
  - The README account's state shows its `OcuTalonUser` rows with `answerable:true`.
  - -- AC 1, AC 6.
- [ ] Web unit tests:
  - `web/scripts/approval-view.test.mjs`, `answer-press.test.mjs`, `phone-view.test.mjs`: `refusalText` for the seven kinds, "" and unknown; `cannotAnswer` and `buttons` for `answerable` false, true and absent; a refused press.
  - `ux-strings.test.mjs`: the new strings.
  - `approval-card.spec.ts:555-572` and `answers.spec.ts:371,432`: the new texts.
- [ ] Spine (`ARCHITECTURE-SPINE.md`), additive and marked `[ADDED 2026-11-13, Story 25.5]`:
  - AD-11 `AnswersIn` bullet: rules 5-6, the refusal object and the composition order with 22.7's rule.
  - AD-12/REST row: the approval payload's `answerable`/`approverKind`; the 403 text from `answered.notApprover*`.
  - The cross-lane table: `Live.Payload.Approval.Answerable` and `RefusalKey` (B), read by `AnswersIn`, `Web.Api` and Lane A's `TelegramIn` (Story 26.4).
  - AD-16's email bullet: the raise-time refusal.
  - Then run `lint_spine.py`.

**Acceptance Criteria:**
- AC 1: Given an answer from any channel to a request the session can see, when `AnswersIn`'s handler takes it, then after the ownership and answer-shape checks it asks `Approval.MayAnswer` for the session's IRIS user. On 0 it returns `not_allowed` with `{"kind"}`, answers nothing and sends nothing to `AnswerOps`. On 1 it hands the answer over as before.
- AC 2: Given the online demo, when the demo-role user holding the fixture `OcuTalonApprover` answers, then its own request is answered and another session's request is refused by the owning-session rule and stays pending: both checks run.
- AC 3: Given a pending request that the signed-in user may not answer, when it shows on the page and on the simulated phone, then Approve and Reject are absent and the status reads the kind's sentence, or the fallback for an empty or unknown kind. It is recomputed at every snapshot and `approval` event, and at once after a refused press.
- AC 4: Given the user's paired Telegram chat, when they press Approve or Reject, then `FromTelegram` returns `not_allowed` with slots `{"kind"}` and answers nothing.
- AC 5: Given a user who may answer, when they answer, then every copy shows "Approved from {channel} at {time}" within 5 s, and `AnswerOps` passes the IRIS user and the SessionRef to `Answer` (already met; see Design Notes).
- AC 6: Given the fixture roles and the double, when each kind is answered by a holder of only another kind's role, by a holder of the kind's role, by a holder of `OcuTalonApprover` and by the README account with the fixture `OcuTalonApprover`, then only the right roles answer, the others are told why on the page, the phone and Telegram, and `live:demo-path` passes.
- AC 7: Given Story 22.7's rule, when a non-admin who passes `MayAnswer` approves another-address email request, then the refusal is `{"kind":"email","admin":true}` with "Only an OcuTalon admin can approve this email.", and their reject is answered.
- AC 8: Given a non-admin's risky email to another address, when the gate holds it, then no request is raised and the turn's refusal is PUBLIC TEXT 10. An admin's request is raised as before.
- DW-1268: AC 1, AC 3, AC 4 and the catalog task.

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6):**
- AD-1: `AnswersIn` is the one entry, and `AnswerOps` its only sender.
- AD-4: ownership comes first and is unchanged. Messages carry a SessionRef, never a user name.
- AD-11: the step-6 answer rule, `MayAnswer`, the `not_allowed` kind, V6 `setting` rows.
- AD-12: the payload, `BridgeSink` the one publisher.
- AD-13: REST, the 403 envelope, the web job.
- AD-16: the email fix kind's raise.
- AD-17: unchanged; Lane A's audit names the role (26.4).
- AD-24: the roles; the demo account's `OcuTalonApprover`.
- AD-29: lanes; the footprint below.
- AD-32: the catalog renders every text.
- AD-33: rows land in the same change.
- No AC contradicts an AD's Rule. Letting another user answer the email request would contradict AD-11 ("only the owning session can see or answer it (FR-8's rules, as for any request)") and AD-4. This plan does not do that (Planner Gate question 1).

**Rule 1/2.**
- Integration: the page and the phone (e2e `phone/approver.spec.ts`) and the real-HTTP spec read the real `Answerable` → `MayAnswer` through `/v1/state`, `BridgeSink` events and the answer route. `TestFixtureRoleOnTheRealPath` runs the real production.
- Consumes: `Approval.MayAnswer` (Story 37.1, Lane A), `Fix.Kind.Email.MayApprove` (Story 22.7), 25.4's fixture roles and users (`live_fixture_role`, `ZzRoleTarget`, `AnswersInWebRoles`' guard), and `Msg.Catalog`.
- Consumed-by: Story 26.4. Its `TelegramIn` alert renders `RefusalKey(slots.kind, slots.admin)` with channel `telegram`, its real `MayAnswer` fills `kind`, and it decides `MayApprove`'s future (question 2).
- Extend, don't copy:
  - `AnswersIn.APPROVALAPI` follows `AnswerOps.APPROVALAPI`.
  - The double extends `Test.Core.ApprovalDouble`.
  - The matrix extends `AnswersInWebRoles`.
  - The email refusal reuses `MayApprove` on the unsaved row, not a second admin check, and follows `Raise`'s refusal parameters.
  - `refusalText` mirrors `RefusalKey` because the page has no server call there; the node test pins both against the same key list.

**Ledger inbox:**
- DW-1268 is addressed by the `AnswersIn`, `Live/Payload/Approval`, catalog and web tasks (AC 1, 3, 4).
- The 22.7 email DW (lane D, Planner P2; not yet filed) is addressed by AC 7 (the answer-time composition and its sentence) and AC 8 (the raise-time refusal), as recommended in Planner Gate question 1.

**AC evidence already met:** AC 5's hand-over: `Core/AnswerOps.cls:58` passes `session.IrisUser` and `request.SessionRef` to `Answer`. The 5-second copies are unchanged; the existing `answers.spec.ts` X3/X8 and `live:demo-path` stay as regression evidence.

**Footprint (Rule 11).**
- Lane B's own files, plus Lane A's `Fix/Kind/Email.cls` and `Test/Fix/Email.cls` as a footprint extension for the email DW, only if the Planner picks option (a) of question 1.
- `Approval.MayAnswer`, `TelegramIn` and every role or grant stay Lane A's.
- `docker/tests/test-sign-in.sh` is shared with 25.4 (same epic, implemented first).

**Contended hunks** (each additive except where named):
- `Core/AnswersIn.cls`:
  - (1) the parameter and the property;
  - (2) `OnProcessInput`: the session open moves up, with rules 5-6 and the post-send email label;
  - (3) `Deliver`/`FromPage` outputs;
  - (4) `TelegramCode`'s `not_allowed` branch (replaced);
  - (5) doc lines.
- `Core/AnswerOps.cls`: none.
- `Web/Api.cls`:
  - (1) `AnswerApproval`: the `FromPage` call, and 22.7's `Set kind` line removed;
  - (2) `AnswerResponse`'s signature and its `not_allowed` line;
  - (3) the three parameters removed (:177, :179, :2180);
  - (4) doc lines.
- `Live/Payload/Approval.cls`: two properties, two class methods, three lines in `FromRow`, and doc lines. Next to 22.7's `EmailPart`.
- `Fix/Kind/Email.cls`: one parameter, and one refusal branch in `Raise`.
- `Msg/Catalog/Core.cls`: nine entries.
- Settings (lane B 36.4): none.

**Decided in-stage:**
1. The role check runs after rules 1-4, so a request the session can't see never reveals its kind, and a bad answer is `bad_answer`.
2. A missing `Session` row is `not_found` in `AnswersIn`, as `AnswerOps` already answers. Before, it reached `AnswerOps`.
3. The refusal travels in-process (a transient service property, then `Deliver`'s output), so no message class gains a stored property.
4. `kind` is `MayAnswer`'s output verbatim. Until 26.4 it is "", and the page, the phone and the 403 show the fallback sentence, which is true then: the user lacks the request's one role.
5. Sentences are chosen by catalog-key existence, so 26.4's later kinds and a fix kind's own `APPROVERKIND` need no Lane B list. An unknown kind is the fallback.
6. The email label is inferred in `AnswersIn` (a `not_allowed` from `AnswerOps` for an approve of an email row after `MayAnswer` passed). This keeps 22.7's hunk byte-identical. A role removed in the milliseconds before `Answer`'s own check is mislabelled `admin` on an email row only (theoretical).
7. "Recomputed when the user's roles change" means the server recomputes at every payload build (snapshot, event, answer reply), and the page switches at once on a refused press. A grant shows at the next snapshot or event (question 3).
8. The phone reads `answerable` from the store's payload: the one exception to its "buttons never come from the store" rule. The UX's "a press gets the same sentence" still holds for a stale phone.
9. The `Api` texts move to the catalog. The fallback keeps today's exact text. The page's "Only an approver for fixes ..." goes, replaced by the suspend sentence.
10. `new_units: none`. `ci_groups`:
    - `image` (lane-b `@Core`: `AnswersIn`, `AnswersTelegram*`, `AnswersInProduction`, `AnswersInWebRoles`);
    - `shards-6` (lane-b rest: `Test.Web.Api`, `OcuTalon.Test.Msg.Catalog`);
    - `shards-11` (lane-a `@Fix`: `Test.Fix.Email`);
    - `shards-4` (`live:sign-in-2`: `phone/approver.spec.ts`);
    - `shards-10` (`live:sign-in`: `api/approver.spec.ts`);
    - the edited existing specs stay in `shards-11` (`live:cards`) and `shards-7` (`live:answers`).

**Measured (plan stage):** nothing was run. Slot A has no OcuTalon roles and no 22.7 code. Task 0 measures the one platform behaviour this plan rests on, and it is labelled (inference) until then.

## Planner Gate

**PUBLIC TEXT** (catalog `Msg/Catalog/Core.cls`, regenerated into `web/src/app/msg/catalog.ts`, unless noted):
1. `answered.notApproverResend`: "Only an approver for resends can answer this request." (from UX, EXPERIENCE.md:721)
2. `answered.notApproverReroute`: "Only an approver for reroutes can answer this request." New.
3. `answered.notApproverSuspend`: "Only an approver for suspending and resuming items can answer this request." New. The `suspend` kind covers both `suspend_item` and `resume_item`.
4. `answered.notApproverRollback`: "Only an approver for rollbacks can answer this request." New.
5. `answered.notApproverPartner`: "Only an approver for partner notices can answer this request." New.
6. `answered.notApproverEmail`: "Only an approver for emails can answer this request." New.
7. `answered.notApproverTool`: "Only an approver for tool calls can answer this request." New.
8. Fallback `answered.notApprover` (empty or unknown kind; `setting` rows): "Only an approver can answer this request." Today's text (`Web/Api.cls:179,2180`), moved.
9. `answered.notAdmin` (22.7's email rule at answer time): "Only an OcuTalon admin can approve this email." New.
10. Raise-time refusal (`Fix/Kind/Email.cls` `MESSAGENOTADMIN`; question 1 (a)): "Only an OcuTalon admin can send email to another address, so the email wasn't sent." New, in the style of `Channel.Email.Out`'s refusals.
11. Removed: the page's "Only an approver for fixes can answer this request." (`approval-view.ts:84`), replaced by item 3.
12. More to try and GUIDE "New since 1.0.0": none. Until Story 26.4 no install has approver roles, so the per-kind sentences can't appear for real users; the step-6 roles line belongs with 26.4. GUIDE P1 stays lane D's (question 6).

**SECURITY:**
1. Answer paths: web (`POST /api/v1/approvals/:ref/answer`, which is changed), the simulated phone (the same route, channel `phone`) and Telegram (`AnswersIn.FromTelegram`). Each now refuses, before the hand-over, a user whom `MayAnswer` refuses. Nothing is widened.
2. Who may answer what:
   - The owning session only, or a watcher of an instance incident on a local install (unchanged, AD-4).
   - The user must also pass `MayAnswer` (until 26.4: the row's `RequiredRole` in their role set; then AD-11's per-kind rule).
   - For an email approve, the user must also pass 22.7's `MayApprove`.
   - Then `Answer`'s check under the lock.
3. Order and kinds:
   - not_found / not_visible: ownership first.
   - bad_answer.
   - not_found for no session row.
   - not_allowed `{kind}` from `MayAnswer`, in `AnswersIn`.
   - not_allowed `{kind:"email", admin:true}` from `MayApprove`, in `AnswerOps`.
   - not_allowed from `Answer`.
   - The user sees PUBLIC TEXT 1-8 for the first not_allowed and 9 for the second.
4. The email DW: refuse at raise time (question 1 (a)). The owning-session rule is untouched.
5. Roles, grants, resources, tables and columns: no change. No message class gains a property. `OcuTalonUser` is not widened. Test setup creates fixture roles only on throwaways, the e2e fixture user `ZzApprover` included.
6. The web job calls `MayAnswer` only for the signed-in user's own name (Task 0 measures that this needs no `%Admin_Secure`). `BridgeSink` calls it in the production job for each recipient's user.
7. Online demo: the demo account passes by its `OcuTalonApprover` (fixture until 26.4; before 26.4 the real rule is its `OcuTalonUser`). The owning-session rule still refuses other sessions' requests. Email is refused at raise there already (`MESSAGEUNAVAILABLE`, first). Nothing new is reachable.
8. The payload discloses only, to the session that can already see the request, whether it may answer and the row's approver kind. No user name or role list is disclosed.
9. Tests:
   - each kind answered by a holder of only another kind's role, by `OcuTalonApprover`, by the kind's role and by the README account after an upgrade (fixture role): `TestApproverMatrix`;
   - Telegram `not_allowed` with the kind: the matrix and `AnswersTelegram`;
   - the real-HTTP route spec with LIVE unprivileged `OcuTalonUser` (`ZzRoleTarget`), README admin, signed-out 401 and second-session isolation (`api/approver.spec.ts`);
   - the demo (`TestFixtureRoleOnTheRealPath`);
   - the raise refusal (`Test.Fix.Email`).

**QUESTIONS:**
1. The 22.7 email DW: how should it be resolved? Options:
   - (a) Refuse at raise time, in Lane A's `Fix.Kind.Email.Raise`, using 22.7's own `MayApprove` on the unsaved request with the requester's IRIS user. The text is item 10. 25.5 does it as a footprint extension into Lane A's file, after 22.7 merges (precedent: 25.4's extension into `Install.Step.Roles`).
   - (b) The same check, routed instead to Lane A's Story 26.4. That adds an AC to another epic's unplanned story (veto item 8).
   - (c) Let another user, an admin or an email approver, answer the requester's email. This contradicts AD-11's setting-row sentence and FR-8 ("only the owning session can see or answer it"). It needs an AD amendment and shows the email's recipients, subject and text to another user (DW-1255 rule 4's private-row concern).
   - (d) Let the requester answer when they hold the email approver role (after 26.4). That needs `MayApprove` relaxed, and it still leaves every non-approver's request unanswerable.
   - **Recommend (a).** It is fail-closed, there is no dead request, no security widening, and the message comes at once. AC 7 stays as the backstop for a role removed after the raise.
2. `MayApprove`'s future at Story 26.4: keep it admin-only (today's DW-1262 interim), or let `OcuTalonApprover`/`OcuTalonApprover_email` approve (its doc anticipates "until the approver-role check ... covers the kind email")? **Recommend** deciding at 26.4's plan and keeping admin-only until then. If (a) is taken, the raise check must follow the same rule.
3. "Recomputed when the user's roles change". Options:
   - (a) The server recomputes at every snapshot, event and reply, and the page switches on a refused press (planned).
   - (b) As (a), plus the page reloads the snapshot's approvals every 60 s, matching "Applies within a minute".
   - (c) As (a), plus Settings › Roles publishes `approval` events for the target's pending requests. This misses IRIS-portal grants.
   - **Recommend (a).** A newly granted user sees the buttons after a reload.
4. The answer-time email refusal's text: (a) its own sentence (item 9, with slot `admin`), (b) the email kind's sentence (item 6), which would be false for a non-admin email approver after 26.4, or (c) 22.7's current fallback. **Recommend (a).**
5. The implement precondition: 22.7 merged and integrated forward, and 25.4 implemented, else HALT. This sequences 25.5 after 22.7 because the DW exists only with 22.7's code. **Recommend accept.** The alternative is to split the email work into a follow-on story.
6. GUIDE P1 (lane D's text) stays true under (a): a non-admin is no longer asked, and an approval refused after a role removal still is. Optional rewording for lane D: "Only an OcuTalon admin can send email to other addresses: without the admin role OcuTalon tells you so and sends nothing, and no other user can approve it for you." **Recommend** that lane D decide, not 25.5.
7. The plural nouns of items 2-7, especially "suspending and resuming items" and "partner notices". **Recommend** as written.

## Verification

`$LANE` stands for these variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=25 stage=implement'`. The fresh tag is `e25s5i` and the warm tag is `e25s5iw`.

Runtime targets:
- The lane's own throwaways (the tags above) for every test run and for Task 0.
- Slot A (profile `ocutalon-slot-a`, namespace `OCUTALON`, on every MCP call, `iris_server_info` first) for compile checks only: no security mutation, one `iris_execute_tests` per message.

Run one command per tool call, in the foreground, with `timeout: 600000`, each sized to about 150 s; one test class per call is always safe. Tear down only your own tags, and run `ci/warm.sh down` at the end, also after a failure.

**Commands:**
- (loop) `$LANE OCUTALON_RUN_TAG=e25s5iw ci/warm.sh up` once, then one class per call: `$LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e25s5iw ci/iris.sh class <Class>`. The classes:
  - `OcuTalon.Test.Core.AnswersIn`, `.AnswersTelegram`, `.AnswersTelegramProduction`, `.AnswersInProduction`, `.AnswersInWebRoles`;
  - `OcuTalon.Test.Web.Api`, `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Fix.Email`;
  - unchanged siblings: `.AnswerPrecedents`, `.PersonaAnswers`, `OcuTalon.Test.Bridge.Api`, `OcuTalon.Test.Contract.Ac`, `OcuTalon.Test.Channel.TelegramApproval`.
  - Each must print `CLASS … passed`.
- (loop) `node --test web/scripts/approval-view.test.mjs web/scripts/answer-press.test.mjs web/scripts/phone-view.test.mjs web/scripts/phone-request-sources.test.mjs web/scripts/approval-sources.test.mjs web/scripts/ux-strings.test.mjs` -- all pass.
- (loop) `npm --prefix web run catalog` -- `git diff --stat web/src/app/msg/catalog.ts` shows only the nine keys.
- (loop) e2e, one call each:
  - `$LANE OCUTALON_RUN_TAG=e25s5i ci/iris.sh build`.
  - List the specs: `npm --silent --prefix web run e2e -- --list --reporter=json > "$SCRATCH/chromium.json"`. Choose n so that each part holds at most two spec files, and find the parts with `node web/scripts/e2e-part.mjs k/n`.
  - Run `ci/iris.sh live sign-in --part k/n` for the part that holds `api/approver.spec.ts`, and `ci/iris.sh live sign-in-2 --part k/n` for the part that holds `phone/approver.spec.ts`. Each passes.
  - `$LANE OCUTALON_RUN_TAG=e25s5i ci/iris.sh teardown`.
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- `"ok": true`, with no new finding.
- (once) `$LANE OCUTALON_RUN_TAG=e25s5i ci/iris.sh live demo-path` -- passes (REL-2; the README account keeps its buttons).
- (once) `$LANE OCUTALON_RUN_TAG=e25s5i ci/iris.sh live answers` and `ci/iris.sh live cards` -- the edited mocked-403 specs pass. Split with `--part` if a call would pass 150 s.
- (once) `npm --prefix web test`; `npm --prefix web run lint`; `npm --prefix web run build` -- one per call, each passes.
- (once) `bash ci/checks.sh`, in batches of `CHECK_SCRIPTS` if needed -- every block passes, among them `test-boundaries.sh` (ASCII, Rule 14) and `test-ci-config.sh`.
- The full shards, groups and `live:online-demo-path` are left to CI.

**Shared surfaces:**
- the approval payload's members (`Test/Web/Api.cls:397`, `ApprovalPayload`, every payload pin found by searching `traceNamespace` in `src/` and `web/`);
- the 403 `not_allowed` texts (`AnswersInProduction`, `approval-view.test.mjs`, `answer-press.test.mjs`, `approval-card.spec.ts`, `answers.spec.ts`);
- the Telegram `not_allowed` slots (`AnswersTelegram`, `AnswersTelegramProduction`);
- the catalog key list and count (`OcuTalon.Test.Msg.Catalog`, `catalog.ts`, `ux-strings`);
- `test-sign-in.sh`'s fixture users and roles, shared by the three sign-in units;
- `FromPage`'s and `Deliver`'s signatures (`AnswersTelegramProbe`, `Web.Api`);
- the phone's button rule (`phone-view.test.mjs`);
- the spine's tables.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations to record (Rule 19; one per AC, each observed red and reverted byte-identical):**
- AC 1: skip rule 6 → `TestRoleCheckBeforeHandOver` and `api/approver.spec.ts` go red.
- AC 2: move rule 6 before rule 3 → the demo case of `TestFixtureRoleOnTheRealPath` (another session's request gives `not_found`) goes red.
- AC 3: ignore `answerable` in the card's `@if` → `phone/approver.spec.ts` (a) goes red. Make `RefusalKey` always return the fallback → `TestRefusalKey` and spec (d) go red.
- AC 4: put `row.Kind` back in `TelegramCode` → `AnswersTelegram` goes red.
- AC 5: drop `session.IrisUser` from `AnswerOps`' `Answer` call → `Test.Core.AnswersIn:TestMalformedSessionRefNeverReaches` (the existing irisUser pin at :165) goes red, and `phone/approver.spec.ts` (b) goes red.
- AC 6: make the double ignore `RequiredRole_kind` → `TestApproverMatrix`'s kind-role holder goes red.
- AC 7: drop the post-send email label → `TestEmailAdminRefusal` goes red.
- AC 8: remove the `MayApprove` call in `Raise` → `TestNonAdminEmailIsRefusedAtRaise` goes red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned 2026-11-13 (plan stage, halt after planning). The spec meets the READY FOR DEVELOPMENT standard.
- The Planner Gate goes to the Contest Planner before implement: PUBLIC TEXT has 12 items, SECURITY 9 and QUESTIONS 7.
- The recommendation for the 22.7 email DW is to refuse at raise time (question 1 (a)).
- Implement has a precondition: 22.7 merged and integrated forward, and 25.4 implemented.
